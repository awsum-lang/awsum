; External C declarations
declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare ptr @memcpy(ptr, ptr, i64)
declare i64 @write(i32, ptr, i64)


define internal ptr @__alloc(i64 %sz, i32 %shape) {
  %total = add i64 %sz, 12
  %raw = call ptr @malloc(i64 %total)
  store i32 1, ptr %raw
  %rc_p = getelementptr i8, ptr %raw, i64 4
  store i32 1, ptr %rc_p
  %shape_p = getelementptr i8, ptr %raw, i64 8
  store i32 %shape, ptr %shape_p
  %user = getelementptr i8, ptr %raw, i64 12
  ret ptr %user
}

define internal void @__inc_ref(ptr %p) {
  %hdr_ptr = getelementptr i8, ptr %p, i64 -12
  %flag = load i32, ptr %hdr_ptr
  %is_heap = icmp eq i32 %flag, 1
  br i1 %is_heap, label %do_inc, label %skip_inc
do_inc:
  %rc_p = getelementptr i8, ptr %p, i64 -8
  %rc_old = load i32, ptr %rc_p
  %rc_new = add i32 %rc_old, 1
  store i32 %rc_new, ptr %rc_p
  br label %skip_inc
skip_inc:
  ret void
}

@__free_worklist = internal global ptr null
@__free_worklist_top = internal global i64 0
@__free_worklist_cap = internal global i64 0

define internal void @__free_worklist_push(ptr %p) {
entry:
  %top = load i64, ptr @__free_worklist_top
  %cap = load i64, ptr @__free_worklist_cap
  %is_full = icmp eq i64 %top, %cap
  br i1 %is_full, label %grow, label %store
grow:
  %cap_zero = icmp eq i64 %cap, 0
  %doubled = shl i64 %cap, 1
  %new_cap = select i1 %cap_zero, i64 16, i64 %doubled
  %bytes = mul i64 %new_cap, 8
  %old_buf = load ptr, ptr @__free_worklist
  %new_buf = call ptr @realloc(ptr %old_buf, i64 %bytes)
  store ptr %new_buf, ptr @__free_worklist
  store i64 %new_cap, ptr @__free_worklist_cap
  br label %store
store:
  %buf = load ptr, ptr @__free_worklist
  %slot = getelementptr ptr, ptr %buf, i64 %top
  store ptr %p, ptr %slot
  %top_new = add i64 %top, 1
  store i64 %top_new, ptr @__free_worklist_top
  ret void
}

define internal void @__free_recursive(ptr %p_arg) {
entry:
  br label %top
top:
  %p = phi ptr [ %p_arg, %entry ], [ %p_after, %continue ]
  %hdr_ptr = getelementptr i8, ptr %p, i64 -12
  %flag = load i32, ptr %hdr_ptr
  %is_heap = icmp eq i32 %flag, 1
  br i1 %is_heap, label %do_dec, label %try_pop
do_dec:
  %rc_p = getelementptr i8, ptr %p, i64 -8
  %rc_old = load i32, ptr %rc_p
  %rc_new = sub i32 %rc_old, 1
  store i32 %rc_new, ptr %rc_p
  %is_zero = icmp eq i32 %rc_new, 0
  br i1 %is_zero, label %do_cascade, label %try_pop
do_cascade:
  %shape_p = getelementptr i8, ptr %p, i64 -4
  %shape = load i32, ptr %shape_p
  %shape_zero = icmp eq i32 %shape, 0
  br i1 %shape_zero, label %free_and_pop, label %loop_check
loop_check:
  %i = phi i32 [ 1, %do_cascade ], [ %i_next, %loop_body ]
  %cmp = icmp ult i32 %i, %shape
  br i1 %cmp, label %loop_body, label %tail_jump_prep
loop_body:
  %i64 = zext i32 %i to i64
  %slot_p = getelementptr ptr, ptr %p, i64 %i64
  %child = load ptr, ptr %slot_p
  call void @__free_worklist_push(ptr %child)
  %i_next = add i32 %i, 1
  br label %loop_check
tail_jump_prep:
  %shape64 = zext i32 %shape to i64
  %last_slot_p = getelementptr ptr, ptr %p, i64 %shape64
  %p_next_tail = load ptr, ptr %last_slot_p
  call void @free(ptr %hdr_ptr)
  br label %continue
free_and_pop:
  call void @free(ptr %hdr_ptr)
  br label %try_pop
try_pop:
  %top_old = load i64, ptr @__free_worklist_top
  %is_empty = icmp eq i64 %top_old, 0
  br i1 %is_empty, label %done, label %do_pop
do_pop:
  %top_new = sub i64 %top_old, 1
  store i64 %top_new, ptr @__free_worklist_top
  %wl_buf = load ptr, ptr @__free_worklist
  %wl_slot = getelementptr ptr, ptr %wl_buf, i64 %top_new
  %p_popped = load ptr, ptr %wl_slot
  br label %continue
continue:
  %p_after = phi ptr [ %p_next_tail, %tail_jump_prep ], [ %p_popped, %do_pop ]
  br label %top
done:
  ret void
}

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"a" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"b" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"u" }

define internal ptr @__print(ptr %s) {
  %byte_count = load i32, ptr %s
  %byte_count_64 = zext i32 %byte_count to i64
  %payload = getelementptr i8, ptr %s, i64 8
  call i64 @write(i32 1, ptr %payload, i64 %byte_count_64)
  %unit = call ptr @__alloc(i64 8, i32 0)
  %unit_tag_ptr = getelementptr ptr, ptr %unit, i32 0
  %unit_tag = inttoptr i64 0 to ptr
  store ptr %unit_tag, ptr %unit_tag_ptr
  call void @__free_recursive(ptr %s)
  ret ptr %unit
}


define internal ptr @__predInt32(ptr %p) {
  %v = load i32, ptr %p
  %is_min = icmp eq i32 %v, -2147483648
  br i1 %is_min, label %overflow, label %ok
overflow:
  %oe = call ptr @__alloc(i64 8, i32 0)
  %oe_tag = inttoptr i64 17 to ptr
  store ptr %oe_tag, ptr %oe
  %left = call ptr @__alloc(i64 16, i32 1)
  %left_tag = inttoptr i64 3 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %oe, ptr %left_f
  call void @__free_recursive(ptr %p)
  ret ptr %left
ok:
  %newv = sub i32 %v, 1
  %box = call ptr @__alloc(i64 4, i32 0)
  store i32 %newv, ptr %box
  %right = call ptr @__alloc(i64 16, i32 1)
  %right_tag = inttoptr i64 4 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %box, ptr %right_f
  call void @__free_recursive(ptr %p)
  ret ptr %right
}


define internal ptr @__eqInt32(ptr %a, ptr %b) {
  %va = load i32, ptr %a
  %vb = load i32, ptr %b
  %eq = icmp eq i32 %va, %vb
  %tag = select i1 %eq, i64 1, i64 2
  %box = call ptr @__alloc(i64 8, i32 0)
  %tag_ptr = inttoptr i64 %tag to ptr
  store ptr %tag_ptr, ptr %box
  call void @__free_recursive(ptr %a)
  call void @__free_recursive(ptr %b)
  ret ptr %box
}


define internal ptr @v_runIO(ptr %v_io) {
entry:
  %t3 = alloca ptr
  store ptr %v_io, ptr %t3
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t4 = load ptr, ptr %t3
  %t5 = getelementptr ptr, ptr %t4, i32 0
  %t6 = load ptr, ptr %t5
  %t7 = ptrtoint ptr %t6 to i64
  switch i64 %t7, label %tco.case.default.8 [ i64 5, label %tco.case.arm.5.9 i64 7, label %tco.case.arm.7.12 ]
tco.case.arm.5.9:
  %t10 = getelementptr ptr, ptr %t4, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  call void @__free_recursive(ptr %t4)
  store ptr %t11, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.12:
  %t13 = getelementptr ptr, ptr %t4, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  %t15 = call ptr @__print(ptr %t14)
  %t16 = getelementptr ptr, ptr %t4, i32 2
  %t17 = load ptr, ptr %t16
  call void @__inc_ref(ptr %t17)
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t15)
  store ptr %t17, ptr %t3
  br label %tco.loop.0
tco.case.default.8:
  unreachable
tco.exit.1:
  %t18 = load ptr, ptr %t2
  ret ptr %t18
}

define internal ptr @v_make(ptr %v_n) {
entry:
  %t3 = alloca ptr
  store ptr %v_n, ptr %t3
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t4 = load ptr, ptr %t3
  call void @__inc_ref(ptr %t4)
  %t5 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t5
  %t6 = call ptr @__eqInt32(ptr %t4, ptr %t5)
  %t7 = getelementptr ptr, ptr %t6, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %tco.case.default.10 [ i64 1, label %tco.case.arm.1.11 i64 2, label %tco.case.arm.2.21 ]
tco.case.arm.1.11:
  %t12 = call ptr @__alloc(i64 16, i32 1)
  %t13 = inttoptr i64 26 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = call ptr @__alloc(i64 24, i32 2)
  %t16 = inttoptr i64 24 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = getelementptr ptr, ptr %t15, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t18
  %t19 = getelementptr ptr, ptr %t15, i32 2
  store ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t19
  %t20 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t15, ptr %t20
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t4)
  store ptr %t12, ptr %t2
  br label %tco.exit.1
tco.case.arm.2.21:
  call void @__inc_ref(ptr %t4)
  %t22 = call ptr @__predInt32(ptr %t4)
  %t23 = getelementptr ptr, ptr %t22, i32 0
  %t24 = load ptr, ptr %t23
  %t25 = ptrtoint ptr %t24 to i64
  switch i64 %t25, label %tco.case.default.26 [ i64 3, label %tco.case.arm.3.27 i64 4, label %tco.case.arm.4.36 ]
tco.case.arm.3.27:
  %t28 = call ptr @__alloc(i64 16, i32 1)
  %t29 = inttoptr i64 26 to ptr
  %t30 = getelementptr ptr, ptr %t28, i32 0
  store ptr %t29, ptr %t30
  %t31 = call ptr @__alloc(i64 16, i32 1)
  %t32 = inttoptr i64 25 to ptr
  %t33 = getelementptr ptr, ptr %t31, i32 0
  store ptr %t32, ptr %t33
  %t34 = getelementptr ptr, ptr %t31, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t34
  %t35 = getelementptr ptr, ptr %t28, i32 1
  store ptr %t31, ptr %t35
  call void @__free_recursive(ptr %t22)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t4)
  store ptr %t28, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.36:
  %t37 = getelementptr ptr, ptr %t22, i32 1
  %t38 = load ptr, ptr %t37
  call void @__inc_ref(ptr %t38)
  call void @__free_recursive(ptr %t22)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t4)
  store ptr %t38, ptr %t3
  br label %tco.loop.0
tco.case.default.26:
  unreachable
tco.case.default.10:
  unreachable
tco.exit.1:
  %t39 = load ptr, ptr %t2
  ret ptr %t39
}

define internal ptr @v_eat(ptr %v_k, ptr %v_q) {
entry:
  %t3 = alloca ptr
  store ptr %v_k, ptr %t3
  %t4 = alloca ptr
  store ptr %v_q, ptr %t4
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t5 = load ptr, ptr %t3
  %t6 = load ptr, ptr %t4
  call void @__inc_ref(ptr %t5)
  %t7 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t7
  %t8 = call ptr @__eqInt32(ptr %t5, ptr %t7)
  %t9 = getelementptr ptr, ptr %t8, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %tco.case.default.12 [ i64 1, label %tco.case.arm.1.13 i64 2, label %tco.case.arm.2.16 ]
tco.case.arm.1.13:
  %t14 = getelementptr ptr, ptr %t6, i32 1
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t15, ptr %t2
  br label %tco.exit.1
tco.case.arm.2.16:
  call void @__inc_ref(ptr %t5)
  %t17 = call ptr @__predInt32(ptr %t5)
  %t18 = getelementptr ptr, ptr %t17, i32 0
  %t19 = load ptr, ptr %t18
  %t20 = ptrtoint ptr %t19 to i64
  switch i64 %t20, label %tco.case.default.21 [ i64 3, label %tco.case.arm.3.22 i64 4, label %tco.case.arm.4.23 ]
tco.case.arm.3.22:
  call void @__free_recursive(ptr %t17)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t2
  br label %tco.exit.1
tco.case.arm.4.23:
  %t24 = getelementptr ptr, ptr %t17, i32 1
  %t25 = load ptr, ptr %t24
  call void @__inc_ref(ptr %t25)
  call void @__free_recursive(ptr %t17)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t5)
  store ptr %t25, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.default.21:
  unreachable
tco.case.default.12:
  unreachable
tco.exit.1:
  %t26 = load ptr, ptr %t2
  ret ptr %t26
}

define internal ptr @v_spin(ptr %v_c, ptr %v_q2) {
entry:
  %t3 = alloca ptr
  store ptr %v_c, ptr %t3
  %t4 = alloca ptr
  store ptr %v_q2, ptr %t4
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t5 = load ptr, ptr %t3
  %t6 = load ptr, ptr %t4
  call void @__inc_ref(ptr %t5)
  %t7 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t7
  %t8 = call ptr @__eqInt32(ptr %t5, ptr %t7)
  %t9 = getelementptr ptr, ptr %t8, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %tco.case.default.12 [ i64 1, label %tco.case.arm.1.13 i64 2, label %tco.case.arm.2.14 ]
tco.case.arm.1.13:
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.2.14:
  call void @__inc_ref(ptr %t5)
  %t15 = call ptr @__predInt32(ptr %t5)
  %t16 = getelementptr ptr, ptr %t15, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %tco.case.default.19 [ i64 3, label %tco.case.arm.3.20 i64 4, label %tco.case.arm.4.21 ]
tco.case.arm.3.20:
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.21:
  %t22 = getelementptr ptr, ptr %t15, i32 1
  %t23 = load ptr, ptr %t22
  call void @__inc_ref(ptr %t23)
  %t24 = getelementptr ptr, ptr %t6, i32 0
  %t25 = load ptr, ptr %t24
  %t26 = ptrtoint ptr %t25 to i64
  switch i64 %t26, label %tco.case.default.27 [ i64 24, label %tco.case.arm.24.28 i64 25, label %tco.case.arm.25.51 ]
tco.case.arm.24.28:
  %t29 = getelementptr ptr, ptr %t6, i32 1
  %t30 = load ptr, ptr %t29
  %t31 = getelementptr ptr, ptr %t6, i32 2
  %t32 = load ptr, ptr %t31
  %t37 = getelementptr i8, ptr %t6, i64 -8
  %t38 = load i32, ptr %t37
  %t39 = icmp eq i32 %t38, 1
  br i1 %t39, label %reuse.in_place.40, label %reuse.copy.41
reuse.in_place.40:
  %t35 = inttoptr i64 24 to ptr
  %t36 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t35, ptr %t36
  %t33 = getelementptr ptr, ptr %t6, i32 1
  store ptr %t32, ptr %t33
  %t34 = getelementptr ptr, ptr %t6, i32 2
  store ptr %t30, ptr %t34
  br label %reuse.in_place.end.43
reuse.in_place.end.43:
  br label %reuse.join.42
reuse.copy.41:
  %t45 = call ptr @__alloc(i64 24, i32 2)
  %t46 = inttoptr i64 24 to ptr
  %t47 = getelementptr ptr, ptr %t45, i32 0
  store ptr %t46, ptr %t47
  call void @__inc_ref(ptr %t32)
  %t48 = getelementptr ptr, ptr %t45, i32 1
  store ptr %t32, ptr %t48
  call void @__inc_ref(ptr %t30)
  %t49 = getelementptr ptr, ptr %t45, i32 2
  store ptr %t30, ptr %t49
  call void @__free_recursive(ptr %t6)
  br label %reuse.copy.end.44
reuse.copy.end.44:
  br label %reuse.join.42
reuse.join.42:
  %t50 = phi ptr [ %t6, %reuse.in_place.end.43 ], [ %t45, %reuse.copy.end.44 ]
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t5)
  store ptr %t23, ptr %t3
  store ptr %t50, ptr %t4
  br label %tco.loop.0
tco.case.arm.25.51:
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t5)
  store ptr %t23, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.default.27:
  unreachable
tco.case.default.19:
  unreachable
tco.case.default.12:
  unreachable
tco.exit.1:
  %t52 = load ptr, ptr %t2
  ret ptr %t52
}

define internal ptr @v_main() {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 7 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 4, i32 0)
  store i32 1, ptr %t3
  %t4 = call ptr @__alloc(i64 4, i32 0)
  store i32 1, ptr %t4
  %t5 = call ptr @v_make(ptr %t4)
  %t6 = getelementptr ptr, ptr %t5, i32 0
  %t7 = load ptr, ptr %t6
  %t8 = ptrtoint ptr %t7 to i64
  switch i64 %t8, label %case.default.9 [ i64 26, label %case.arm.26.11 ]
case.arm.26.11:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  %t15 = getelementptr ptr, ptr %t14, i32 0
  %t16 = load ptr, ptr %t15
  %t17 = ptrtoint ptr %t16 to i64
  switch i64 %t17, label %case.default.18 [ i64 24, label %case.arm.24.20 i64 25, label %case.arm.25.31 ]
case.arm.24.20:
  %t22 = call ptr @__alloc(i64 24, i32 2)
  %t23 = inttoptr i64 24 to ptr
  %t24 = getelementptr ptr, ptr %t22, i32 0
  store ptr %t23, ptr %t24
  %t25 = getelementptr ptr, ptr %t14, i32 2
  %t26 = load ptr, ptr %t25
  call void @__inc_ref(ptr %t26)
  %t27 = getelementptr ptr, ptr %t22, i32 1
  store ptr %t26, ptr %t27
  %t28 = getelementptr ptr, ptr %t14, i32 1
  %t29 = load ptr, ptr %t28
  call void @__inc_ref(ptr %t29)
  %t30 = getelementptr ptr, ptr %t22, i32 2
  store ptr %t29, ptr %t30
  br label %case.end.24.21
case.end.24.21:
  br label %case.join.19
case.arm.25.31:
  call void @__inc_ref(ptr %t14)
  br label %case.end.25.32
case.end.25.32:
  br label %case.join.19
case.default.18:
  unreachable
case.join.19:
  %t33 = phi ptr [ %t22, %case.end.24.21 ], [ %t14, %case.end.25.32 ]
  br label %case.end.26.12
case.end.26.12:
  br label %case.join.10
case.default.9:
  unreachable
case.join.10:
  %t34 = phi ptr [ %t33, %case.end.26.12 ]
  call void @__free_recursive(ptr %t5)
  %t35 = call ptr @v_eat(ptr %t3, ptr %t34)
  %t36 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t35, ptr %t36
  %t37 = call ptr @__alloc(i64 16, i32 1)
  %t38 = inttoptr i64 5 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = call ptr @__alloc(i64 8, i32 0)
  %t41 = inttoptr i64 0 to ptr
  %t42 = getelementptr ptr, ptr %t40, i32 0
  store ptr %t41, ptr %t42
  %t43 = getelementptr ptr, ptr %t37, i32 1
  store ptr %t40, ptr %t43
  %t44 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t37, ptr %t44
  %t45 = call ptr @__alloc(i64 8, i32 0)
  %t46 = inttoptr i64 27 to ptr
  %t47 = getelementptr ptr, ptr %t45, i32 0
  store ptr %t46, ptr %t47
  %t48 = call ptr @v__cps__df_andThenIO_0(ptr %t0, ptr %t45)
  ret ptr %t48
}

define internal ptr @v__cps__df_andThenIO_0(ptr %v_io, ptr %v__k) {
entry:
  %t3 = alloca ptr
  store ptr %v_io, ptr %t3
  %t4 = alloca ptr
  store ptr %v__k, ptr %t4
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t5 = load ptr, ptr %t3
  %t6 = load ptr, ptr %t4
  %t7 = getelementptr ptr, ptr %t5, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 7, label %tco.case.arm.7.60 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t15
  %t16 = call ptr @__alloc(i64 4, i32 0)
  store i32 1, ptr %t16
  %t17 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t17
  %t18 = call ptr @v_make(ptr %t17)
  %t19 = getelementptr ptr, ptr %t18, i32 0
  %t20 = load ptr, ptr %t19
  %t21 = ptrtoint ptr %t20 to i64
  switch i64 %t21, label %case.default.22 [ i64 26, label %case.arm.26.24 ]
case.arm.26.24:
  %t26 = getelementptr ptr, ptr %t18, i32 1
  %t27 = load ptr, ptr %t26
  call void @__inc_ref(ptr %t27)
  %t28 = getelementptr ptr, ptr %t27, i32 0
  %t29 = load ptr, ptr %t28
  %t30 = ptrtoint ptr %t29 to i64
  switch i64 %t30, label %case.default.31 [ i64 24, label %case.arm.24.33 i64 25, label %case.arm.25.44 ]
case.arm.24.33:
  %t35 = call ptr @__alloc(i64 24, i32 2)
  %t36 = inttoptr i64 24 to ptr
  %t37 = getelementptr ptr, ptr %t35, i32 0
  store ptr %t36, ptr %t37
  %t38 = getelementptr ptr, ptr %t27, i32 2
  %t39 = load ptr, ptr %t38
  call void @__inc_ref(ptr %t39)
  %t40 = getelementptr ptr, ptr %t35, i32 1
  store ptr %t39, ptr %t40
  %t41 = getelementptr ptr, ptr %t27, i32 1
  %t42 = load ptr, ptr %t41
  call void @__inc_ref(ptr %t42)
  %t43 = getelementptr ptr, ptr %t35, i32 2
  store ptr %t42, ptr %t43
  br label %case.end.24.34
case.end.24.34:
  br label %case.join.32
case.arm.25.44:
  call void @__inc_ref(ptr %t27)
  br label %case.end.25.45
case.end.25.45:
  br label %case.join.32
case.default.31:
  unreachable
case.join.32:
  %t46 = phi ptr [ %t35, %case.end.24.34 ], [ %t27, %case.end.25.45 ]
  call void @__free_recursive(ptr %t27)
  br label %case.end.26.25
case.end.26.25:
  br label %case.join.23
case.default.22:
  unreachable
case.join.23:
  %t47 = phi ptr [ %t46, %case.end.26.25 ]
  call void @__free_recursive(ptr %t18)
  %t48 = call ptr @v_spin(ptr %t16, ptr %t47)
  %t49 = call ptr @v_eat(ptr %t15, ptr %t48)
  %t50 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t49, ptr %t50
  %t51 = call ptr @__alloc(i64 16, i32 1)
  %t52 = inttoptr i64 5 to ptr
  %t53 = getelementptr ptr, ptr %t51, i32 0
  store ptr %t52, ptr %t53
  %t54 = call ptr @__alloc(i64 8, i32 0)
  %t55 = inttoptr i64 0 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  %t57 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t57
  %t58 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t51, ptr %t58
  %t59 = call ptr @v__apply__df_andThenIO_0(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t59, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.60:
  %t61 = getelementptr ptr, ptr %t5, i32 1
  %t62 = load ptr, ptr %t61
  %t63 = getelementptr ptr, ptr %t5, i32 2
  %t64 = load ptr, ptr %t63
  call void @__inc_ref(ptr %t64)
  %t71 = getelementptr i8, ptr %t5, i64 -8
  %t72 = load i32, ptr %t71
  %t73 = icmp eq i32 %t72, 1
  br i1 %t73, label %reuse.in_place.74, label %reuse.copy.75
reuse.in_place.74:
  %t65 = getelementptr ptr, ptr %t5, i32 2
  %t66 = load ptr, ptr %t65
  call void @__free_recursive(ptr %t66)
  %t69 = inttoptr i64 28 to ptr
  %t70 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t69, ptr %t70
  call void @__inc_ref(ptr %t6)
  %t67 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t67
  %t68 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t62, ptr %t68
  br label %reuse.in_place.end.77
reuse.in_place.end.77:
  br label %reuse.join.76
reuse.copy.75:
  %t79 = call ptr @__alloc(i64 24, i32 2)
  %t80 = inttoptr i64 28 to ptr
  %t81 = getelementptr ptr, ptr %t79, i32 0
  store ptr %t80, ptr %t81
  call void @__inc_ref(ptr %t6)
  %t82 = getelementptr ptr, ptr %t79, i32 1
  store ptr %t6, ptr %t82
  call void @__inc_ref(ptr %t62)
  %t83 = getelementptr ptr, ptr %t79, i32 2
  store ptr %t62, ptr %t83
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.78
reuse.copy.end.78:
  br label %reuse.join.76
reuse.join.76:
  %t84 = phi ptr [ %t5, %reuse.in_place.end.77 ], [ %t79, %reuse.copy.end.78 ]
  call void @__free_recursive(ptr %t6)
  store ptr %t64, ptr %t3
  store ptr %t84, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t85 = load ptr, ptr %t2
  ret ptr %t85
}

define internal ptr @v__apply__df_andThenIO_0(ptr %v__k, ptr %v__x) {
entry:
  %t3 = alloca ptr
  store ptr %v__k, ptr %t3
  %t4 = alloca ptr
  store ptr %v__x, ptr %t4
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t5 = load ptr, ptr %t3
  %t6 = load ptr, ptr %t4
  %t7 = getelementptr ptr, ptr %t5, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %tco.case.default.10 [ i64 27, label %tco.case.arm.27.11 i64 28, label %tco.case.arm.28.12 ]
tco.case.arm.27.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.28.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  %t15 = getelementptr ptr, ptr %t5, i32 2
  %t16 = load ptr, ptr %t15
  %t17 = getelementptr ptr, ptr %t5, i32 1
  %t18 = load ptr, ptr %t17
  call void @__free_recursive(ptr %t18)
  %t21 = inttoptr i64 7 to ptr
  %t22 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t21, ptr %t22
  %t19 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t16, ptr %t19
  call void @__inc_ref(ptr %t6)
  %t20 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t6, ptr %t20
  call void @__free_recursive(ptr %t6)
  store ptr %t14, ptr %t3
  store ptr %t5, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t23 = load ptr, ptr %t2
  ret ptr %t23
}

declare i32 @_setmode(i32, i32)

define i32 @main(i32 %argc_posix, ptr %argv_posix) {
entry:
  call i32 @_setmode(i32 1, i32 32768)
  call i32 @_setmode(i32 0, i32 32768)
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
