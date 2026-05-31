; External C declarations
declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare ptr @memcpy(ptr, ptr, i64)
declare i64 @write(i32, ptr, i64)
declare i32 @snprintf(ptr, i64, ptr, ...)

@.fmt_i32 = private unnamed_addr constant [3 x i8] c"%d\00"

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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [14 x i8]} { i32 0, i32 0, i32 0, i32 14, i32 14, [14 x i8] c"UnderflowError" }

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


define internal ptr @__showInt32(ptr %p) {
  %v = load i32, ptr %p
  %buf = call ptr @__alloc(i64 24, i32 0)
  %payload = getelementptr i8, ptr %buf, i64 8
  %n = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %payload, i64 16, ptr @.fmt_i32, i32 %v)
  store i32 %n, ptr %buf
  %u16p = getelementptr i8, ptr %buf, i64 4
  store i32 %n, ptr %u16p
  call void @__free_recursive(ptr %p)
  ret ptr %buf
}


define internal ptr @__predInt32(ptr %p) {
  %v = load i32, ptr %p
  %is_min = icmp eq i32 %v, -2147483648
  br i1 %is_min, label %overflow, label %ok
overflow:
  %oe = call ptr @__alloc(i64 8, i32 0)
  %oe_tag = inttoptr i64 16 to ptr
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
  %t15 = getelementptr ptr, ptr %t4, i32 2
  %t16 = load ptr, ptr %t15
  call void @__inc_ref(ptr %t16)
  call void @__inc_ref(ptr %t14)
  %t17 = call ptr @__print(ptr %t14)
  %t18 = getelementptr ptr, ptr %t17, i32 0
  %t19 = load ptr, ptr %t18
  %t20 = ptrtoint ptr %t19 to i64
  switch i64 %t20, label %tco.case.default.21 [ i64 0, label %tco.case.arm.0.22 ]
tco.case.arm.0.22:
  call void @__inc_ref(ptr %t16)
  call void @__free_recursive(ptr %t17)
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t16)
  call void @__free_recursive(ptr %t14)
  store ptr %t16, ptr %t3
  br label %tco.loop.0
tco.case.default.21:
  unreachable
tco.case.default.8:
  unreachable
tco.exit.1:
  %t23 = load ptr, ptr %t2
  ret ptr %t23
}

define internal ptr @v_showUnderflowError(ptr %v__wild0) {
  call void @__free_recursive(ptr %v__wild0)
  ret ptr getelementptr inbounds (i8, ptr @.str.0, i64 12)
}

define internal ptr @v_main() {
  %t0 = call ptr @v_runDemo()
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 3, label %case.arm.3.6 i64 4, label %case.arm.4.23 ]
case.arm.3.6:
  %t8 = getelementptr ptr, ptr %t0, i32 1
  %t9 = load ptr, ptr %t8
  call void @__inc_ref(ptr %t9)
  %t10 = call ptr @__alloc(i64 24, i32 2)
  %t11 = inttoptr i64 7 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  call void @__inc_ref(ptr %t9)
  %t13 = call ptr @v_showUnderflowError(ptr %t9)
  %t14 = getelementptr ptr, ptr %t10, i32 1
  store ptr %t13, ptr %t14
  %t15 = call ptr @__alloc(i64 16, i32 1)
  %t16 = inttoptr i64 5 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = call ptr @__alloc(i64 8, i32 0)
  %t19 = inttoptr i64 0 to ptr
  %t20 = getelementptr ptr, ptr %t18, i32 0
  store ptr %t19, ptr %t20
  %t21 = getelementptr ptr, ptr %t15, i32 1
  store ptr %t18, ptr %t21
  %t22 = getelementptr ptr, ptr %t10, i32 2
  store ptr %t15, ptr %t22
  br label %case.end.3.7
case.end.3.7:
  br label %case.join.5
case.arm.4.23:
  %t25 = getelementptr ptr, ptr %t0, i32 1
  %t26 = load ptr, ptr %t25
  call void @__inc_ref(ptr %t26)
  %t27 = call ptr @__alloc(i64 24, i32 2)
  %t28 = inttoptr i64 7 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  call void @__inc_ref(ptr %t26)
  %t30 = call ptr @__showInt32(ptr %t26)
  %t31 = getelementptr ptr, ptr %t27, i32 1
  store ptr %t30, ptr %t31
  %t32 = call ptr @__alloc(i64 16, i32 1)
  %t33 = inttoptr i64 5 to ptr
  %t34 = getelementptr ptr, ptr %t32, i32 0
  store ptr %t33, ptr %t34
  %t35 = call ptr @__alloc(i64 8, i32 0)
  %t36 = inttoptr i64 0 to ptr
  %t37 = getelementptr ptr, ptr %t35, i32 0
  store ptr %t36, ptr %t37
  %t38 = getelementptr ptr, ptr %t32, i32 1
  store ptr %t35, ptr %t38
  %t39 = getelementptr ptr, ptr %t27, i32 2
  store ptr %t32, ptr %t39
  br label %case.end.4.24
case.end.4.24:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t40 = phi ptr [%t10, %case.end.3.7], [%t27, %case.end.4.24]
  call void @__free_recursive(ptr %t0)
  ret ptr %t40
}

define internal ptr @v_runDemo() {
  %t0 = call ptr @__alloc(i64 4, i32 0)
  store i32 10000, ptr %t0
  %t1 = call ptr @v_buildTree(ptr %t0)
  %t2 = getelementptr ptr, ptr %t1, i32 0
  %t3 = load ptr, ptr %t2
  %t4 = ptrtoint ptr %t3 to i64
  switch i64 %t4, label %case.default.5 [ i64 3, label %case.arm.3.7 i64 4, label %case.arm.4.15 ]
case.arm.3.7:
  %t9 = getelementptr ptr, ptr %t1, i32 1
  %t10 = load ptr, ptr %t9
  call void @__inc_ref(ptr %t10)
  %t11 = call ptr @__alloc(i64 16, i32 1)
  %t12 = inttoptr i64 3 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  call void @__inc_ref(ptr %t10)
  %t14 = getelementptr ptr, ptr %t11, i32 1
  store ptr %t10, ptr %t14
  br label %case.end.3.8
case.end.3.8:
  br label %case.join.6
case.arm.4.15:
  %t17 = getelementptr ptr, ptr %t1, i32 1
  %t18 = load ptr, ptr %t17
  call void @__inc_ref(ptr %t18)
  %t19 = call ptr @__alloc(i64 4, i32 0)
  store i32 500, ptr %t19
  call void @__inc_ref(ptr %t18)
  %t20 = call ptr @v_mirrorN(ptr %t19, ptr %t18)
  %t21 = getelementptr ptr, ptr %t20, i32 0
  %t22 = load ptr, ptr %t21
  %t23 = ptrtoint ptr %t22 to i64
  switch i64 %t23, label %case.default.24 [ i64 3, label %case.arm.3.26 i64 4, label %case.arm.4.34 ]
case.arm.3.26:
  %t28 = getelementptr ptr, ptr %t20, i32 1
  %t29 = load ptr, ptr %t28
  call void @__inc_ref(ptr %t29)
  %t30 = call ptr @__alloc(i64 16, i32 1)
  %t31 = inttoptr i64 3 to ptr
  %t32 = getelementptr ptr, ptr %t30, i32 0
  store ptr %t31, ptr %t32
  call void @__inc_ref(ptr %t29)
  %t33 = getelementptr ptr, ptr %t30, i32 1
  store ptr %t29, ptr %t33
  br label %case.end.3.27
case.end.3.27:
  br label %case.join.25
case.arm.4.34:
  %t36 = getelementptr ptr, ptr %t20, i32 1
  %t37 = load ptr, ptr %t36
  call void @__inc_ref(ptr %t37)
  %t38 = call ptr @__alloc(i64 16, i32 1)
  %t39 = inttoptr i64 4 to ptr
  %t40 = getelementptr ptr, ptr %t38, i32 0
  store ptr %t39, ptr %t40
  %t41 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t41
  call void @__inc_ref(ptr %t37)
  %t42 = call ptr @v_deepestLeftA(ptr %t41, ptr %t37)
  %t43 = getelementptr ptr, ptr %t38, i32 1
  store ptr %t42, ptr %t43
  br label %case.end.4.35
case.end.4.35:
  br label %case.join.25
case.default.24:
  unreachable
case.join.25:
  %t44 = phi ptr [%t30, %case.end.3.27], [%t38, %case.end.4.35]
  call void @__free_recursive(ptr %t20)
  br label %case.end.4.16
case.end.4.16:
  br label %case.join.6
case.default.5:
  unreachable
case.join.6:
  %t45 = phi ptr [%t11, %case.end.3.8], [%t44, %case.end.4.16]
  call void @__free_recursive(ptr %t1)
  ret ptr %t45
}

define internal ptr @v_buildTree(ptr %v_depth) {
  call void @__inc_ref(ptr %v_depth)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 22 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__lift_15(ptr %t0)
  %t4 = call ptr @v_buildLeft(ptr %v_depth, ptr %t3)
  %t5 = getelementptr ptr, ptr %t4, i32 0
  %t6 = load ptr, ptr %t5
  %t7 = ptrtoint ptr %t6 to i64
  switch i64 %t7, label %case.default.8 [ i64 3, label %case.arm.3.9 i64 4, label %case.arm.4.16 ]
case.arm.3.9:
  %t10 = getelementptr ptr, ptr %t4, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  %t12 = call ptr @__alloc(i64 16, i32 1)
  %t13 = inttoptr i64 3 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  call void @__inc_ref(ptr %t11)
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t11, ptr %t15
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %v_depth)
  ret ptr %t12
case.arm.4.16:
  %t17 = getelementptr ptr, ptr %t4, i32 1
  %t18 = load ptr, ptr %t17
  call void @__inc_ref(ptr %t18)
  call void @__inc_ref(ptr %v_depth)
  %t19 = call ptr @__alloc(i64 8, i32 0)
  %t20 = inttoptr i64 22 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = call ptr @v__lift_15(ptr %t19)
  %t23 = call ptr @v_buildRight(ptr %v_depth, ptr %t22)
  %t24 = getelementptr ptr, ptr %t23, i32 0
  %t25 = load ptr, ptr %t24
  %t26 = ptrtoint ptr %t25 to i64
  switch i64 %t26, label %case.default.27 [ i64 3, label %case.arm.3.28 i64 4, label %case.arm.4.35 ]
case.arm.3.28:
  %t29 = getelementptr ptr, ptr %t23, i32 1
  %t30 = load ptr, ptr %t29
  call void @__inc_ref(ptr %t30)
  %t31 = call ptr @__alloc(i64 16, i32 1)
  %t32 = inttoptr i64 3 to ptr
  %t33 = getelementptr ptr, ptr %t31, i32 0
  store ptr %t32, ptr %t33
  call void @__inc_ref(ptr %t30)
  %t34 = getelementptr ptr, ptr %t31, i32 1
  store ptr %t30, ptr %t34
  call void @__free_recursive(ptr %t23)
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t30)
  call void @__free_recursive(ptr %t18)
  call void @__free_recursive(ptr %v_depth)
  ret ptr %t31
case.arm.4.35:
  %t36 = getelementptr ptr, ptr %t23, i32 1
  %t37 = load ptr, ptr %t36
  call void @__inc_ref(ptr %t37)
  %t38 = call ptr @__alloc(i64 16, i32 1)
  %t39 = inttoptr i64 4 to ptr
  %t40 = getelementptr ptr, ptr %t38, i32 0
  store ptr %t39, ptr %t40
  %t41 = call ptr @__alloc(i64 32, i32 3)
  %t42 = inttoptr i64 23 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  call void @__inc_ref(ptr %t18)
  %t44 = getelementptr ptr, ptr %t41, i32 1
  store ptr %t18, ptr %t44
  %t45 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t45
  %t46 = getelementptr ptr, ptr %t41, i32 2
  store ptr %t45, ptr %t46
  call void @__inc_ref(ptr %t37)
  %t47 = getelementptr ptr, ptr %t41, i32 3
  store ptr %t37, ptr %t47
  %t48 = getelementptr ptr, ptr %t38, i32 1
  store ptr %t41, ptr %t48
  call void @__free_recursive(ptr %t23)
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t37)
  call void @__free_recursive(ptr %t18)
  call void @__free_recursive(ptr %v_depth)
  ret ptr %t38
case.default.27:
  unreachable
case.default.8:
  unreachable
}

define internal ptr @v_buildLeft(ptr %v_depth, ptr %v_acc) {
entry:
  %t3 = alloca ptr
  store ptr %v_depth, ptr %t3
  %t4 = alloca ptr
  store ptr %v_acc, ptr %t4
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
  switch i64 %t11, label %tco.case.default.12 [ i64 1, label %tco.case.arm.1.13 i64 2, label %tco.case.arm.2.18 ]
tco.case.arm.1.13:
  %t14 = call ptr @__alloc(i64 16, i32 1)
  %t15 = inttoptr i64 4 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  call void @__inc_ref(ptr %t6)
  %t17 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t6, ptr %t17
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t14, ptr %t2
  br label %tco.exit.1
tco.case.arm.2.18:
  call void @__inc_ref(ptr %t5)
  %t19 = call ptr @__predInt32(ptr %t5)
  %t20 = getelementptr ptr, ptr %t19, i32 0
  %t21 = load ptr, ptr %t20
  %t22 = ptrtoint ptr %t21 to i64
  switch i64 %t22, label %tco.case.default.23 [ i64 3, label %tco.case.arm.3.24 i64 4, label %tco.case.arm.4.31 ]
tco.case.arm.3.24:
  %t25 = getelementptr ptr, ptr %t19, i32 1
  %t26 = load ptr, ptr %t25
  call void @__inc_ref(ptr %t26)
  %t27 = call ptr @__alloc(i64 16, i32 1)
  %t28 = inttoptr i64 3 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  call void @__inc_ref(ptr %t26)
  %t30 = getelementptr ptr, ptr %t27, i32 1
  store ptr %t26, ptr %t30
  call void @__free_recursive(ptr %t19)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t26)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t27, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.31:
  %t32 = getelementptr ptr, ptr %t19, i32 1
  %t33 = load ptr, ptr %t32
  call void @__inc_ref(ptr %t33)
  %t34 = call ptr @__alloc(i64 32, i32 3)
  %t35 = inttoptr i64 23 to ptr
  %t36 = getelementptr ptr, ptr %t34, i32 0
  store ptr %t35, ptr %t36
  call void @__inc_ref(ptr %t6)
  %t37 = getelementptr ptr, ptr %t34, i32 1
  store ptr %t6, ptr %t37
  call void @__inc_ref(ptr %t5)
  %t38 = getelementptr ptr, ptr %t34, i32 2
  store ptr %t5, ptr %t38
  %t39 = call ptr @__alloc(i64 8, i32 0)
  %t40 = inttoptr i64 22 to ptr
  %t41 = getelementptr ptr, ptr %t39, i32 0
  store ptr %t40, ptr %t41
  %t42 = call ptr @v__lift_15(ptr %t39)
  %t43 = getelementptr ptr, ptr %t34, i32 3
  store ptr %t42, ptr %t43
  call void @__inc_ref(ptr %t33)
  call void @__free_recursive(ptr %t19)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t33)
  store ptr %t33, ptr %t3
  store ptr %t34, ptr %t4
  br label %tco.loop.0
tco.case.default.23:
  unreachable
tco.case.default.12:
  unreachable
tco.exit.1:
  %t44 = load ptr, ptr %t2
  ret ptr %t44
}

define internal ptr @v_buildRight(ptr %v_depth, ptr %v_acc) {
entry:
  %t3 = alloca ptr
  store ptr %v_depth, ptr %t3
  %t4 = alloca ptr
  store ptr %v_acc, ptr %t4
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
  switch i64 %t11, label %tco.case.default.12 [ i64 1, label %tco.case.arm.1.13 i64 2, label %tco.case.arm.2.18 ]
tco.case.arm.1.13:
  %t14 = call ptr @__alloc(i64 16, i32 1)
  %t15 = inttoptr i64 4 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  call void @__inc_ref(ptr %t6)
  %t17 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t6, ptr %t17
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t14, ptr %t2
  br label %tco.exit.1
tco.case.arm.2.18:
  call void @__inc_ref(ptr %t5)
  %t19 = call ptr @__predInt32(ptr %t5)
  %t20 = getelementptr ptr, ptr %t19, i32 0
  %t21 = load ptr, ptr %t20
  %t22 = ptrtoint ptr %t21 to i64
  switch i64 %t22, label %tco.case.default.23 [ i64 3, label %tco.case.arm.3.24 i64 4, label %tco.case.arm.4.31 ]
tco.case.arm.3.24:
  %t25 = getelementptr ptr, ptr %t19, i32 1
  %t26 = load ptr, ptr %t25
  call void @__inc_ref(ptr %t26)
  %t27 = call ptr @__alloc(i64 16, i32 1)
  %t28 = inttoptr i64 3 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  call void @__inc_ref(ptr %t26)
  %t30 = getelementptr ptr, ptr %t27, i32 1
  store ptr %t26, ptr %t30
  call void @__free_recursive(ptr %t19)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t26)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t27, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.31:
  %t32 = getelementptr ptr, ptr %t19, i32 1
  %t33 = load ptr, ptr %t32
  call void @__inc_ref(ptr %t33)
  %t34 = call ptr @__alloc(i64 32, i32 3)
  %t35 = inttoptr i64 23 to ptr
  %t36 = getelementptr ptr, ptr %t34, i32 0
  store ptr %t35, ptr %t36
  %t37 = call ptr @__alloc(i64 8, i32 0)
  %t38 = inttoptr i64 22 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = call ptr @v__lift_15(ptr %t37)
  %t41 = getelementptr ptr, ptr %t34, i32 1
  store ptr %t40, ptr %t41
  call void @__inc_ref(ptr %t5)
  %t42 = getelementptr ptr, ptr %t34, i32 2
  store ptr %t5, ptr %t42
  call void @__inc_ref(ptr %t6)
  %t43 = getelementptr ptr, ptr %t34, i32 3
  store ptr %t6, ptr %t43
  call void @__inc_ref(ptr %t33)
  call void @__free_recursive(ptr %t19)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t33)
  store ptr %t33, ptr %t3
  store ptr %t34, ptr %t4
  br label %tco.loop.0
tco.case.default.23:
  unreachable
tco.case.default.12:
  unreachable
tco.exit.1:
  %t44 = load ptr, ptr %t2
  ret ptr %t44
}

define internal ptr @v_mirror(ptr %v_t) {
  call void @__inc_ref(ptr %v_t)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 27 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps_mirror(ptr %v_t, ptr %t0)
  call void @__free_recursive(ptr %v_t)
  ret ptr %t3
}

define internal ptr @v_mirrorN(ptr %v_times, ptr %v_t) {
entry:
  %t3 = alloca ptr
  store ptr %v_times, ptr %t3
  %t4 = alloca ptr
  store ptr %v_t, ptr %t4
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
  switch i64 %t11, label %tco.case.default.12 [ i64 1, label %tco.case.arm.1.13 i64 2, label %tco.case.arm.2.19 ]
tco.case.arm.1.13:
  %t14 = call ptr @__alloc(i64 16, i32 1)
  %t15 = inttoptr i64 4 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  call void @__inc_ref(ptr %t6)
  %t17 = call ptr @v__lift_16(ptr %t6)
  %t18 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t17, ptr %t18
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t14, ptr %t2
  br label %tco.exit.1
tco.case.arm.2.19:
  call void @__inc_ref(ptr %t5)
  %t20 = call ptr @__predInt32(ptr %t5)
  %t21 = getelementptr ptr, ptr %t20, i32 0
  %t22 = load ptr, ptr %t21
  %t23 = ptrtoint ptr %t22 to i64
  switch i64 %t23, label %tco.case.default.24 [ i64 3, label %tco.case.arm.3.25 i64 4, label %tco.case.arm.4.32 ]
tco.case.arm.3.25:
  %t26 = getelementptr ptr, ptr %t20, i32 1
  %t27 = load ptr, ptr %t26
  call void @__inc_ref(ptr %t27)
  %t28 = call ptr @__alloc(i64 16, i32 1)
  %t29 = inttoptr i64 3 to ptr
  %t30 = getelementptr ptr, ptr %t28, i32 0
  store ptr %t29, ptr %t30
  call void @__inc_ref(ptr %t27)
  %t31 = getelementptr ptr, ptr %t28, i32 1
  store ptr %t27, ptr %t31
  call void @__free_recursive(ptr %t20)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t27)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t28, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.32:
  %t33 = getelementptr ptr, ptr %t20, i32 1
  %t34 = load ptr, ptr %t33
  call void @__inc_ref(ptr %t34)
  call void @__inc_ref(ptr %t6)
  %t35 = call ptr @v_mirror(ptr %t6)
  call void @__inc_ref(ptr %t34)
  call void @__free_recursive(ptr %t20)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t34)
  store ptr %t34, ptr %t3
  store ptr %t35, ptr %t4
  br label %tco.loop.0
tco.case.default.24:
  unreachable
tco.case.default.12:
  unreachable
tco.exit.1:
  %t36 = load ptr, ptr %t2
  ret ptr %t36
}

define internal ptr @v__lift_15(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 30 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__lift_15(ptr %v___input, ptr %t0)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t3
}

define internal ptr @v__lift_16(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 33 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__lift_16(ptr %v___input, ptr %t0)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t3
}

define internal ptr @v__scc_deepestLeftA_deepestLeftB_deepestLeftC(ptr %v__args) {
entry:
  %t3 = alloca ptr
  store ptr %v__args, ptr %t3
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t4 = load ptr, ptr %t3
  %t5 = getelementptr ptr, ptr %t4, i32 0
  %t6 = load ptr, ptr %t5
  %t7 = ptrtoint ptr %t6 to i64
  switch i64 %t7, label %tco.case.default.8 [ i64 24, label %tco.case.arm.24.9 i64 25, label %tco.case.arm.25.46 i64 26, label %tco.case.arm.26.83 ]
tco.case.arm.24.9:
  %t10 = getelementptr ptr, ptr %t4, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  %t12 = getelementptr ptr, ptr %t4, i32 2
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t13, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %tco.case.default.17 [ i64 22, label %tco.case.arm.22.18 i64 23, label %tco.case.arm.23.19 ]
tco.case.arm.22.18:
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t4)
  store ptr %t11, ptr %t2
  br label %tco.exit.1
tco.case.arm.23.19:
  %t20 = getelementptr ptr, ptr %t13, i32 1
  %t21 = load ptr, ptr %t20
  call void @__inc_ref(ptr %t21)
  %t22 = getelementptr ptr, ptr %t13, i32 2
  %t23 = load ptr, ptr %t22
  call void @__inc_ref(ptr %t23)
  %t24 = getelementptr ptr, ptr %t13, i32 3
  %t25 = load ptr, ptr %t24
  call void @__inc_ref(ptr %t25)
  %t26 = getelementptr i8, ptr %t4, i64 -8
  %t27 = load i32, ptr %t26
  %t28 = icmp eq i32 %t27, 1
  br i1 %t28, label %reuse.in_place.29, label %reuse.copy.30
reuse.in_place.29:
  %t32 = getelementptr ptr, ptr %t4, i32 1
  %t33 = load ptr, ptr %t32
  call void @__free_recursive(ptr %t33)
  %t34 = getelementptr ptr, ptr %t4, i32 2
  %t35 = load ptr, ptr %t34
  call void @__free_recursive(ptr %t35)
  %t38 = inttoptr i64 25 to ptr
  %t39 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t38, ptr %t39
  call void @__inc_ref(ptr %t23)
  %t36 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t23, ptr %t36
  call void @__inc_ref(ptr %t21)
  %t37 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t21, ptr %t37
  br label %reuse.join.31
reuse.copy.30:
  %t40 = call ptr @__alloc(i64 24, i32 2)
  %t41 = inttoptr i64 25 to ptr
  %t42 = getelementptr ptr, ptr %t40, i32 0
  store ptr %t41, ptr %t42
  call void @__inc_ref(ptr %t23)
  %t43 = getelementptr ptr, ptr %t40, i32 1
  store ptr %t23, ptr %t43
  call void @__inc_ref(ptr %t21)
  %t44 = getelementptr ptr, ptr %t40, i32 2
  store ptr %t21, ptr %t44
  call void @__free_recursive(ptr %t4)
  br label %reuse.join.31
reuse.join.31:
  %t45 = phi ptr [ %t4, %reuse.in_place.29 ], [ %t40, %reuse.copy.30 ]
  call void @__free_recursive(ptr %t25)
  call void @__free_recursive(ptr %t23)
  call void @__free_recursive(ptr %t21)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t45, ptr %t3
  br label %tco.loop.0
tco.case.default.17:
  unreachable
tco.case.arm.25.46:
  %t47 = getelementptr ptr, ptr %t4, i32 1
  %t48 = load ptr, ptr %t47
  call void @__inc_ref(ptr %t48)
  %t49 = getelementptr ptr, ptr %t4, i32 2
  %t50 = load ptr, ptr %t49
  call void @__inc_ref(ptr %t50)
  %t51 = getelementptr ptr, ptr %t50, i32 0
  %t52 = load ptr, ptr %t51
  %t53 = ptrtoint ptr %t52 to i64
  switch i64 %t53, label %tco.case.default.54 [ i64 22, label %tco.case.arm.22.55 i64 23, label %tco.case.arm.23.56 ]
tco.case.arm.22.55:
  call void @__free_recursive(ptr %t50)
  call void @__free_recursive(ptr %t4)
  store ptr %t48, ptr %t2
  br label %tco.exit.1
tco.case.arm.23.56:
  %t57 = getelementptr ptr, ptr %t50, i32 1
  %t58 = load ptr, ptr %t57
  call void @__inc_ref(ptr %t58)
  %t59 = getelementptr ptr, ptr %t50, i32 2
  %t60 = load ptr, ptr %t59
  call void @__inc_ref(ptr %t60)
  %t61 = getelementptr ptr, ptr %t50, i32 3
  %t62 = load ptr, ptr %t61
  call void @__inc_ref(ptr %t62)
  %t63 = getelementptr i8, ptr %t4, i64 -8
  %t64 = load i32, ptr %t63
  %t65 = icmp eq i32 %t64, 1
  br i1 %t65, label %reuse.in_place.66, label %reuse.copy.67
reuse.in_place.66:
  %t69 = getelementptr ptr, ptr %t4, i32 1
  %t70 = load ptr, ptr %t69
  call void @__free_recursive(ptr %t70)
  %t71 = getelementptr ptr, ptr %t4, i32 2
  %t72 = load ptr, ptr %t71
  call void @__free_recursive(ptr %t72)
  %t75 = inttoptr i64 26 to ptr
  %t76 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t75, ptr %t76
  call void @__inc_ref(ptr %t60)
  %t73 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t60, ptr %t73
  call void @__inc_ref(ptr %t58)
  %t74 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t58, ptr %t74
  br label %reuse.join.68
reuse.copy.67:
  %t77 = call ptr @__alloc(i64 24, i32 2)
  %t78 = inttoptr i64 26 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  call void @__inc_ref(ptr %t60)
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t60, ptr %t80
  call void @__inc_ref(ptr %t58)
  %t81 = getelementptr ptr, ptr %t77, i32 2
  store ptr %t58, ptr %t81
  call void @__free_recursive(ptr %t4)
  br label %reuse.join.68
reuse.join.68:
  %t82 = phi ptr [ %t4, %reuse.in_place.66 ], [ %t77, %reuse.copy.67 ]
  call void @__free_recursive(ptr %t62)
  call void @__free_recursive(ptr %t60)
  call void @__free_recursive(ptr %t58)
  call void @__free_recursive(ptr %t50)
  call void @__free_recursive(ptr %t48)
  store ptr %t82, ptr %t3
  br label %tco.loop.0
tco.case.default.54:
  unreachable
tco.case.arm.26.83:
  %t84 = getelementptr ptr, ptr %t4, i32 1
  %t85 = load ptr, ptr %t84
  call void @__inc_ref(ptr %t85)
  %t86 = getelementptr ptr, ptr %t4, i32 2
  %t87 = load ptr, ptr %t86
  call void @__inc_ref(ptr %t87)
  %t88 = getelementptr ptr, ptr %t87, i32 0
  %t89 = load ptr, ptr %t88
  %t90 = ptrtoint ptr %t89 to i64
  switch i64 %t90, label %tco.case.default.91 [ i64 22, label %tco.case.arm.22.92 i64 23, label %tco.case.arm.23.93 ]
tco.case.arm.22.92:
  call void @__free_recursive(ptr %t87)
  call void @__free_recursive(ptr %t4)
  store ptr %t85, ptr %t2
  br label %tco.exit.1
tco.case.arm.23.93:
  %t94 = getelementptr ptr, ptr %t87, i32 1
  %t95 = load ptr, ptr %t94
  call void @__inc_ref(ptr %t95)
  %t96 = getelementptr ptr, ptr %t87, i32 2
  %t97 = load ptr, ptr %t96
  call void @__inc_ref(ptr %t97)
  %t98 = getelementptr ptr, ptr %t87, i32 3
  %t99 = load ptr, ptr %t98
  call void @__inc_ref(ptr %t99)
  %t100 = getelementptr i8, ptr %t4, i64 -8
  %t101 = load i32, ptr %t100
  %t102 = icmp eq i32 %t101, 1
  br i1 %t102, label %reuse.in_place.103, label %reuse.copy.104
reuse.in_place.103:
  %t106 = getelementptr ptr, ptr %t4, i32 1
  %t107 = load ptr, ptr %t106
  call void @__free_recursive(ptr %t107)
  %t108 = getelementptr ptr, ptr %t4, i32 2
  %t109 = load ptr, ptr %t108
  call void @__free_recursive(ptr %t109)
  %t112 = inttoptr i64 24 to ptr
  %t113 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t112, ptr %t113
  call void @__inc_ref(ptr %t97)
  %t110 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t97, ptr %t110
  call void @__inc_ref(ptr %t95)
  %t111 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t95, ptr %t111
  br label %reuse.join.105
reuse.copy.104:
  %t114 = call ptr @__alloc(i64 24, i32 2)
  %t115 = inttoptr i64 24 to ptr
  %t116 = getelementptr ptr, ptr %t114, i32 0
  store ptr %t115, ptr %t116
  call void @__inc_ref(ptr %t97)
  %t117 = getelementptr ptr, ptr %t114, i32 1
  store ptr %t97, ptr %t117
  call void @__inc_ref(ptr %t95)
  %t118 = getelementptr ptr, ptr %t114, i32 2
  store ptr %t95, ptr %t118
  call void @__free_recursive(ptr %t4)
  br label %reuse.join.105
reuse.join.105:
  %t119 = phi ptr [ %t4, %reuse.in_place.103 ], [ %t114, %reuse.copy.104 ]
  call void @__free_recursive(ptr %t99)
  call void @__free_recursive(ptr %t97)
  call void @__free_recursive(ptr %t95)
  call void @__free_recursive(ptr %t87)
  call void @__free_recursive(ptr %t85)
  store ptr %t119, ptr %t3
  br label %tco.loop.0
tco.case.default.91:
  unreachable
tco.case.default.8:
  unreachable
tco.exit.1:
  %t120 = load ptr, ptr %t2
  ret ptr %t120
}

define internal ptr @v_deepestLeftA(ptr %v_lastV, ptr %v_t) {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 24 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  call void @__inc_ref(ptr %v_lastV)
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v_lastV, ptr %t3
  call void @__inc_ref(ptr %v_t)
  %t4 = getelementptr ptr, ptr %t0, i32 2
  store ptr %v_t, ptr %t4
  %t5 = call ptr @v__scc_deepestLeftA_deepestLeftB_deepestLeftC(ptr %t0)
  call void @__free_recursive(ptr %v_lastV)
  call void @__free_recursive(ptr %v_t)
  ret ptr %t5
}

define internal ptr @v__scc__apply_mirror__cps_mirror(ptr %v__args) {
entry:
  %t3 = alloca ptr
  store ptr %v__args, ptr %t3
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t4 = load ptr, ptr %t3
  %t5 = getelementptr ptr, ptr %t4, i32 0
  %t6 = load ptr, ptr %t5
  %t7 = ptrtoint ptr %t6 to i64
  switch i64 %t7, label %tco.case.default.8 [ i64 36, label %tco.case.arm.36.9 i64 37, label %tco.case.arm.37.85 ]
tco.case.arm.36.9:
  %t10 = getelementptr ptr, ptr %t4, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  %t12 = getelementptr ptr, ptr %t4, i32 2
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t11, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %tco.case.default.17 [ i64 27, label %tco.case.arm.27.18 i64 29, label %tco.case.arm.29.19 i64 28, label %tco.case.arm.28.52 ]
tco.case.arm.27.18:
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %t4)
  store ptr %t13, ptr %t2
  br label %tco.exit.1
tco.case.arm.29.19:
  %t20 = getelementptr ptr, ptr %t11, i32 1
  %t21 = load ptr, ptr %t20
  call void @__inc_ref(ptr %t21)
  %t22 = getelementptr ptr, ptr %t11, i32 2
  %t23 = load ptr, ptr %t22
  call void @__inc_ref(ptr %t23)
  %t24 = getelementptr ptr, ptr %t11, i32 3
  %t25 = load ptr, ptr %t24
  call void @__inc_ref(ptr %t25)
  %t26 = call ptr @__alloc(i64 32, i32 3)
  %t27 = inttoptr i64 23 to ptr
  %t28 = getelementptr ptr, ptr %t26, i32 0
  store ptr %t27, ptr %t28
  call void @__inc_ref(ptr %t23)
  %t29 = getelementptr ptr, ptr %t26, i32 1
  store ptr %t23, ptr %t29
  call void @__inc_ref(ptr %t25)
  %t30 = getelementptr ptr, ptr %t26, i32 2
  store ptr %t25, ptr %t30
  call void @__inc_ref(ptr %t13)
  %t31 = getelementptr ptr, ptr %t26, i32 3
  store ptr %t13, ptr %t31
  %t32 = getelementptr i8, ptr %t4, i64 -8
  %t33 = load i32, ptr %t32
  %t34 = icmp eq i32 %t33, 1
  br i1 %t34, label %reuse.in_place.35, label %reuse.copy.36
reuse.in_place.35:
  %t38 = getelementptr ptr, ptr %t4, i32 1
  %t39 = load ptr, ptr %t38
  call void @__free_recursive(ptr %t39)
  %t40 = getelementptr ptr, ptr %t4, i32 2
  %t41 = load ptr, ptr %t40
  call void @__free_recursive(ptr %t41)
  %t44 = inttoptr i64 36 to ptr
  %t45 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t44, ptr %t45
  call void @__inc_ref(ptr %t21)
  %t42 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t21, ptr %t42
  %t43 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t26, ptr %t43
  br label %reuse.join.37
reuse.copy.36:
  %t46 = call ptr @__alloc(i64 24, i32 2)
  %t47 = inttoptr i64 36 to ptr
  %t48 = getelementptr ptr, ptr %t46, i32 0
  store ptr %t47, ptr %t48
  call void @__inc_ref(ptr %t21)
  %t49 = getelementptr ptr, ptr %t46, i32 1
  store ptr %t21, ptr %t49
  %t50 = getelementptr ptr, ptr %t46, i32 2
  store ptr %t26, ptr %t50
  call void @__free_recursive(ptr %t4)
  br label %reuse.join.37
reuse.join.37:
  %t51 = phi ptr [ %t4, %reuse.in_place.35 ], [ %t46, %reuse.copy.36 ]
  call void @__free_recursive(ptr %t25)
  call void @__free_recursive(ptr %t23)
  call void @__free_recursive(ptr %t21)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t51, ptr %t3
  br label %tco.loop.0
tco.case.arm.28.52:
  %t53 = getelementptr ptr, ptr %t11, i32 1
  %t54 = load ptr, ptr %t53
  call void @__inc_ref(ptr %t54)
  %t55 = getelementptr ptr, ptr %t11, i32 2
  %t56 = load ptr, ptr %t55
  call void @__inc_ref(ptr %t56)
  %t57 = getelementptr ptr, ptr %t11, i32 3
  %t58 = load ptr, ptr %t57
  call void @__inc_ref(ptr %t58)
  %t59 = call ptr @__alloc(i64 32, i32 3)
  %t60 = inttoptr i64 29 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  call void @__inc_ref(ptr %t54)
  %t62 = getelementptr ptr, ptr %t59, i32 1
  store ptr %t54, ptr %t62
  call void @__inc_ref(ptr %t13)
  %t63 = getelementptr ptr, ptr %t59, i32 2
  store ptr %t13, ptr %t63
  call void @__inc_ref(ptr %t58)
  %t64 = getelementptr ptr, ptr %t59, i32 3
  store ptr %t58, ptr %t64
  %t65 = getelementptr i8, ptr %t4, i64 -8
  %t66 = load i32, ptr %t65
  %t67 = icmp eq i32 %t66, 1
  br i1 %t67, label %reuse.in_place.68, label %reuse.copy.69
reuse.in_place.68:
  %t71 = getelementptr ptr, ptr %t4, i32 1
  %t72 = load ptr, ptr %t71
  call void @__free_recursive(ptr %t72)
  %t73 = getelementptr ptr, ptr %t4, i32 2
  %t74 = load ptr, ptr %t73
  call void @__free_recursive(ptr %t74)
  %t77 = inttoptr i64 37 to ptr
  %t78 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t77, ptr %t78
  call void @__inc_ref(ptr %t56)
  %t75 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t56, ptr %t75
  %t76 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t59, ptr %t76
  br label %reuse.join.70
reuse.copy.69:
  %t79 = call ptr @__alloc(i64 24, i32 2)
  %t80 = inttoptr i64 37 to ptr
  %t81 = getelementptr ptr, ptr %t79, i32 0
  store ptr %t80, ptr %t81
  call void @__inc_ref(ptr %t56)
  %t82 = getelementptr ptr, ptr %t79, i32 1
  store ptr %t56, ptr %t82
  %t83 = getelementptr ptr, ptr %t79, i32 2
  store ptr %t59, ptr %t83
  call void @__free_recursive(ptr %t4)
  br label %reuse.join.70
reuse.join.70:
  %t84 = phi ptr [ %t4, %reuse.in_place.68 ], [ %t79, %reuse.copy.69 ]
  call void @__free_recursive(ptr %t58)
  call void @__free_recursive(ptr %t56)
  call void @__free_recursive(ptr %t54)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t84, ptr %t3
  br label %tco.loop.0
tco.case.default.17:
  unreachable
tco.case.arm.37.85:
  %t86 = getelementptr ptr, ptr %t4, i32 1
  %t87 = load ptr, ptr %t86
  call void @__inc_ref(ptr %t87)
  %t88 = getelementptr ptr, ptr %t4, i32 2
  %t89 = load ptr, ptr %t88
  call void @__inc_ref(ptr %t89)
  %t90 = getelementptr ptr, ptr %t87, i32 0
  %t91 = load ptr, ptr %t90
  %t92 = ptrtoint ptr %t91 to i64
  switch i64 %t92, label %tco.case.default.93 [ i64 22, label %tco.case.arm.22.94 i64 23, label %tco.case.arm.23.118 ]
tco.case.arm.22.94:
  %t95 = call ptr @__alloc(i64 8, i32 0)
  %t96 = inttoptr i64 22 to ptr
  %t97 = getelementptr ptr, ptr %t95, i32 0
  store ptr %t96, ptr %t97
  %t98 = getelementptr i8, ptr %t4, i64 -8
  %t99 = load i32, ptr %t98
  %t100 = icmp eq i32 %t99, 1
  br i1 %t100, label %reuse.in_place.101, label %reuse.copy.102
reuse.in_place.101:
  %t104 = getelementptr ptr, ptr %t4, i32 1
  %t105 = load ptr, ptr %t104
  call void @__free_recursive(ptr %t105)
  %t106 = getelementptr ptr, ptr %t4, i32 2
  %t107 = load ptr, ptr %t106
  call void @__free_recursive(ptr %t107)
  %t110 = inttoptr i64 36 to ptr
  %t111 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t110, ptr %t111
  call void @__inc_ref(ptr %t89)
  %t108 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t89, ptr %t108
  %t109 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t95, ptr %t109
  br label %reuse.join.103
reuse.copy.102:
  %t112 = call ptr @__alloc(i64 24, i32 2)
  %t113 = inttoptr i64 36 to ptr
  %t114 = getelementptr ptr, ptr %t112, i32 0
  store ptr %t113, ptr %t114
  call void @__inc_ref(ptr %t89)
  %t115 = getelementptr ptr, ptr %t112, i32 1
  store ptr %t89, ptr %t115
  %t116 = getelementptr ptr, ptr %t112, i32 2
  store ptr %t95, ptr %t116
  call void @__free_recursive(ptr %t4)
  br label %reuse.join.103
reuse.join.103:
  %t117 = phi ptr [ %t4, %reuse.in_place.101 ], [ %t112, %reuse.copy.102 ]
  call void @__free_recursive(ptr %t89)
  call void @__free_recursive(ptr %t87)
  store ptr %t117, ptr %t3
  br label %tco.loop.0
tco.case.arm.23.118:
  %t119 = getelementptr ptr, ptr %t87, i32 1
  %t120 = load ptr, ptr %t119
  call void @__inc_ref(ptr %t120)
  %t121 = getelementptr ptr, ptr %t87, i32 2
  %t122 = load ptr, ptr %t121
  call void @__inc_ref(ptr %t122)
  %t123 = getelementptr ptr, ptr %t87, i32 3
  %t124 = load ptr, ptr %t123
  call void @__inc_ref(ptr %t124)
  %t125 = call ptr @__alloc(i64 32, i32 3)
  %t126 = inttoptr i64 28 to ptr
  %t127 = getelementptr ptr, ptr %t125, i32 0
  store ptr %t126, ptr %t127
  call void @__inc_ref(ptr %t89)
  %t128 = getelementptr ptr, ptr %t125, i32 1
  store ptr %t89, ptr %t128
  call void @__inc_ref(ptr %t120)
  %t129 = getelementptr ptr, ptr %t125, i32 2
  store ptr %t120, ptr %t129
  call void @__inc_ref(ptr %t122)
  %t130 = getelementptr ptr, ptr %t125, i32 3
  store ptr %t122, ptr %t130
  %t131 = getelementptr i8, ptr %t4, i64 -8
  %t132 = load i32, ptr %t131
  %t133 = icmp eq i32 %t132, 1
  br i1 %t133, label %reuse.in_place.134, label %reuse.copy.135
reuse.in_place.134:
  %t137 = getelementptr ptr, ptr %t4, i32 1
  %t138 = load ptr, ptr %t137
  call void @__free_recursive(ptr %t138)
  %t139 = getelementptr ptr, ptr %t4, i32 2
  %t140 = load ptr, ptr %t139
  call void @__free_recursive(ptr %t140)
  %t143 = inttoptr i64 37 to ptr
  %t144 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t143, ptr %t144
  call void @__inc_ref(ptr %t124)
  %t141 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t124, ptr %t141
  %t142 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t125, ptr %t142
  br label %reuse.join.136
reuse.copy.135:
  %t145 = call ptr @__alloc(i64 24, i32 2)
  %t146 = inttoptr i64 37 to ptr
  %t147 = getelementptr ptr, ptr %t145, i32 0
  store ptr %t146, ptr %t147
  call void @__inc_ref(ptr %t124)
  %t148 = getelementptr ptr, ptr %t145, i32 1
  store ptr %t124, ptr %t148
  %t149 = getelementptr ptr, ptr %t145, i32 2
  store ptr %t125, ptr %t149
  call void @__free_recursive(ptr %t4)
  br label %reuse.join.136
reuse.join.136:
  %t150 = phi ptr [ %t4, %reuse.in_place.134 ], [ %t145, %reuse.copy.135 ]
  call void @__free_recursive(ptr %t124)
  call void @__free_recursive(ptr %t122)
  call void @__free_recursive(ptr %t120)
  call void @__free_recursive(ptr %t89)
  call void @__free_recursive(ptr %t87)
  store ptr %t150, ptr %t3
  br label %tco.loop.0
tco.case.default.93:
  unreachable
tco.case.default.8:
  unreachable
tco.exit.1:
  %t151 = load ptr, ptr %t2
  ret ptr %t151
}

define internal ptr @v__cps_mirror(ptr %v_t, ptr %v__k) {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 37 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  call void @__inc_ref(ptr %v_t)
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v_t, ptr %t3
  call void @__inc_ref(ptr %v__k)
  %t4 = getelementptr ptr, ptr %t0, i32 2
  store ptr %v__k, ptr %t4
  %t5 = call ptr @v__scc__apply_mirror__cps_mirror(ptr %t0)
  call void @__free_recursive(ptr %v_t)
  call void @__free_recursive(ptr %v__k)
  ret ptr %t5
}

define internal ptr @v__scc__apply__lift_16__cps__lift_16(ptr %v__args) {
entry:
  %t3 = alloca ptr
  store ptr %v__args, ptr %t3
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t4 = load ptr, ptr %t3
  %t5 = getelementptr ptr, ptr %t4, i32 0
  %t6 = load ptr, ptr %t5
  %t7 = ptrtoint ptr %t6 to i64
  switch i64 %t7, label %tco.case.default.8 [ i64 38, label %tco.case.arm.38.9 i64 39, label %tco.case.arm.39.85 ]
tco.case.arm.38.9:
  %t10 = getelementptr ptr, ptr %t4, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  %t12 = getelementptr ptr, ptr %t4, i32 2
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t11, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %tco.case.default.17 [ i64 33, label %tco.case.arm.33.18 i64 35, label %tco.case.arm.35.19 i64 34, label %tco.case.arm.34.52 ]
tco.case.arm.33.18:
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %t4)
  store ptr %t13, ptr %t2
  br label %tco.exit.1
tco.case.arm.35.19:
  %t20 = getelementptr ptr, ptr %t11, i32 1
  %t21 = load ptr, ptr %t20
  call void @__inc_ref(ptr %t21)
  %t22 = getelementptr ptr, ptr %t11, i32 2
  %t23 = load ptr, ptr %t22
  call void @__inc_ref(ptr %t23)
  %t24 = getelementptr ptr, ptr %t11, i32 3
  %t25 = load ptr, ptr %t24
  call void @__inc_ref(ptr %t25)
  %t26 = call ptr @__alloc(i64 32, i32 3)
  %t27 = inttoptr i64 23 to ptr
  %t28 = getelementptr ptr, ptr %t26, i32 0
  store ptr %t27, ptr %t28
  call void @__inc_ref(ptr %t23)
  %t29 = getelementptr ptr, ptr %t26, i32 1
  store ptr %t23, ptr %t29
  call void @__inc_ref(ptr %t25)
  %t30 = getelementptr ptr, ptr %t26, i32 2
  store ptr %t25, ptr %t30
  call void @__inc_ref(ptr %t13)
  %t31 = getelementptr ptr, ptr %t26, i32 3
  store ptr %t13, ptr %t31
  %t32 = getelementptr i8, ptr %t4, i64 -8
  %t33 = load i32, ptr %t32
  %t34 = icmp eq i32 %t33, 1
  br i1 %t34, label %reuse.in_place.35, label %reuse.copy.36
reuse.in_place.35:
  %t38 = getelementptr ptr, ptr %t4, i32 1
  %t39 = load ptr, ptr %t38
  call void @__free_recursive(ptr %t39)
  %t40 = getelementptr ptr, ptr %t4, i32 2
  %t41 = load ptr, ptr %t40
  call void @__free_recursive(ptr %t41)
  %t44 = inttoptr i64 38 to ptr
  %t45 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t44, ptr %t45
  call void @__inc_ref(ptr %t21)
  %t42 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t21, ptr %t42
  %t43 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t26, ptr %t43
  br label %reuse.join.37
reuse.copy.36:
  %t46 = call ptr @__alloc(i64 24, i32 2)
  %t47 = inttoptr i64 38 to ptr
  %t48 = getelementptr ptr, ptr %t46, i32 0
  store ptr %t47, ptr %t48
  call void @__inc_ref(ptr %t21)
  %t49 = getelementptr ptr, ptr %t46, i32 1
  store ptr %t21, ptr %t49
  %t50 = getelementptr ptr, ptr %t46, i32 2
  store ptr %t26, ptr %t50
  call void @__free_recursive(ptr %t4)
  br label %reuse.join.37
reuse.join.37:
  %t51 = phi ptr [ %t4, %reuse.in_place.35 ], [ %t46, %reuse.copy.36 ]
  call void @__free_recursive(ptr %t25)
  call void @__free_recursive(ptr %t23)
  call void @__free_recursive(ptr %t21)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t51, ptr %t3
  br label %tco.loop.0
tco.case.arm.34.52:
  %t53 = getelementptr ptr, ptr %t11, i32 1
  %t54 = load ptr, ptr %t53
  call void @__inc_ref(ptr %t54)
  %t55 = getelementptr ptr, ptr %t11, i32 2
  %t56 = load ptr, ptr %t55
  call void @__inc_ref(ptr %t56)
  %t57 = getelementptr ptr, ptr %t11, i32 3
  %t58 = load ptr, ptr %t57
  call void @__inc_ref(ptr %t58)
  %t59 = call ptr @__alloc(i64 32, i32 3)
  %t60 = inttoptr i64 35 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  call void @__inc_ref(ptr %t54)
  %t62 = getelementptr ptr, ptr %t59, i32 1
  store ptr %t54, ptr %t62
  call void @__inc_ref(ptr %t13)
  %t63 = getelementptr ptr, ptr %t59, i32 2
  store ptr %t13, ptr %t63
  call void @__inc_ref(ptr %t56)
  %t64 = getelementptr ptr, ptr %t59, i32 3
  store ptr %t56, ptr %t64
  %t65 = getelementptr i8, ptr %t4, i64 -8
  %t66 = load i32, ptr %t65
  %t67 = icmp eq i32 %t66, 1
  br i1 %t67, label %reuse.in_place.68, label %reuse.copy.69
reuse.in_place.68:
  %t71 = getelementptr ptr, ptr %t4, i32 1
  %t72 = load ptr, ptr %t71
  call void @__free_recursive(ptr %t72)
  %t73 = getelementptr ptr, ptr %t4, i32 2
  %t74 = load ptr, ptr %t73
  call void @__free_recursive(ptr %t74)
  %t77 = inttoptr i64 39 to ptr
  %t78 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t77, ptr %t78
  call void @__inc_ref(ptr %t58)
  %t75 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t58, ptr %t75
  %t76 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t59, ptr %t76
  br label %reuse.join.70
reuse.copy.69:
  %t79 = call ptr @__alloc(i64 24, i32 2)
  %t80 = inttoptr i64 39 to ptr
  %t81 = getelementptr ptr, ptr %t79, i32 0
  store ptr %t80, ptr %t81
  call void @__inc_ref(ptr %t58)
  %t82 = getelementptr ptr, ptr %t79, i32 1
  store ptr %t58, ptr %t82
  %t83 = getelementptr ptr, ptr %t79, i32 2
  store ptr %t59, ptr %t83
  call void @__free_recursive(ptr %t4)
  br label %reuse.join.70
reuse.join.70:
  %t84 = phi ptr [ %t4, %reuse.in_place.68 ], [ %t79, %reuse.copy.69 ]
  call void @__free_recursive(ptr %t58)
  call void @__free_recursive(ptr %t56)
  call void @__free_recursive(ptr %t54)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t84, ptr %t3
  br label %tco.loop.0
tco.case.default.17:
  unreachable
tco.case.arm.39.85:
  %t86 = getelementptr ptr, ptr %t4, i32 1
  %t87 = load ptr, ptr %t86
  call void @__inc_ref(ptr %t87)
  %t88 = getelementptr ptr, ptr %t4, i32 2
  %t89 = load ptr, ptr %t88
  call void @__inc_ref(ptr %t89)
  %t90 = getelementptr ptr, ptr %t87, i32 0
  %t91 = load ptr, ptr %t90
  %t92 = ptrtoint ptr %t91 to i64
  switch i64 %t92, label %tco.case.default.93 [ i64 22, label %tco.case.arm.22.94 i64 23, label %tco.case.arm.23.118 ]
tco.case.arm.22.94:
  %t95 = call ptr @__alloc(i64 8, i32 0)
  %t96 = inttoptr i64 22 to ptr
  %t97 = getelementptr ptr, ptr %t95, i32 0
  store ptr %t96, ptr %t97
  %t98 = getelementptr i8, ptr %t4, i64 -8
  %t99 = load i32, ptr %t98
  %t100 = icmp eq i32 %t99, 1
  br i1 %t100, label %reuse.in_place.101, label %reuse.copy.102
reuse.in_place.101:
  %t104 = getelementptr ptr, ptr %t4, i32 1
  %t105 = load ptr, ptr %t104
  call void @__free_recursive(ptr %t105)
  %t106 = getelementptr ptr, ptr %t4, i32 2
  %t107 = load ptr, ptr %t106
  call void @__free_recursive(ptr %t107)
  %t110 = inttoptr i64 38 to ptr
  %t111 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t110, ptr %t111
  call void @__inc_ref(ptr %t89)
  %t108 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t89, ptr %t108
  %t109 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t95, ptr %t109
  br label %reuse.join.103
reuse.copy.102:
  %t112 = call ptr @__alloc(i64 24, i32 2)
  %t113 = inttoptr i64 38 to ptr
  %t114 = getelementptr ptr, ptr %t112, i32 0
  store ptr %t113, ptr %t114
  call void @__inc_ref(ptr %t89)
  %t115 = getelementptr ptr, ptr %t112, i32 1
  store ptr %t89, ptr %t115
  %t116 = getelementptr ptr, ptr %t112, i32 2
  store ptr %t95, ptr %t116
  call void @__free_recursive(ptr %t4)
  br label %reuse.join.103
reuse.join.103:
  %t117 = phi ptr [ %t4, %reuse.in_place.101 ], [ %t112, %reuse.copy.102 ]
  call void @__free_recursive(ptr %t89)
  call void @__free_recursive(ptr %t87)
  store ptr %t117, ptr %t3
  br label %tco.loop.0
tco.case.arm.23.118:
  %t119 = getelementptr ptr, ptr %t87, i32 1
  %t120 = load ptr, ptr %t119
  call void @__inc_ref(ptr %t120)
  %t121 = getelementptr ptr, ptr %t87, i32 2
  %t122 = load ptr, ptr %t121
  call void @__inc_ref(ptr %t122)
  %t123 = getelementptr ptr, ptr %t87, i32 3
  %t124 = load ptr, ptr %t123
  call void @__inc_ref(ptr %t124)
  %t125 = call ptr @__alloc(i64 32, i32 3)
  %t126 = inttoptr i64 34 to ptr
  %t127 = getelementptr ptr, ptr %t125, i32 0
  store ptr %t126, ptr %t127
  call void @__inc_ref(ptr %t89)
  %t128 = getelementptr ptr, ptr %t125, i32 1
  store ptr %t89, ptr %t128
  call void @__inc_ref(ptr %t122)
  %t129 = getelementptr ptr, ptr %t125, i32 2
  store ptr %t122, ptr %t129
  call void @__inc_ref(ptr %t124)
  %t130 = getelementptr ptr, ptr %t125, i32 3
  store ptr %t124, ptr %t130
  %t131 = getelementptr i8, ptr %t4, i64 -8
  %t132 = load i32, ptr %t131
  %t133 = icmp eq i32 %t132, 1
  br i1 %t133, label %reuse.in_place.134, label %reuse.copy.135
reuse.in_place.134:
  %t137 = getelementptr ptr, ptr %t4, i32 1
  %t138 = load ptr, ptr %t137
  call void @__free_recursive(ptr %t138)
  %t139 = getelementptr ptr, ptr %t4, i32 2
  %t140 = load ptr, ptr %t139
  call void @__free_recursive(ptr %t140)
  %t143 = inttoptr i64 39 to ptr
  %t144 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t143, ptr %t144
  call void @__inc_ref(ptr %t120)
  %t141 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t120, ptr %t141
  %t142 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t125, ptr %t142
  br label %reuse.join.136
reuse.copy.135:
  %t145 = call ptr @__alloc(i64 24, i32 2)
  %t146 = inttoptr i64 39 to ptr
  %t147 = getelementptr ptr, ptr %t145, i32 0
  store ptr %t146, ptr %t147
  call void @__inc_ref(ptr %t120)
  %t148 = getelementptr ptr, ptr %t145, i32 1
  store ptr %t120, ptr %t148
  %t149 = getelementptr ptr, ptr %t145, i32 2
  store ptr %t125, ptr %t149
  call void @__free_recursive(ptr %t4)
  br label %reuse.join.136
reuse.join.136:
  %t150 = phi ptr [ %t4, %reuse.in_place.134 ], [ %t145, %reuse.copy.135 ]
  call void @__free_recursive(ptr %t124)
  call void @__free_recursive(ptr %t122)
  call void @__free_recursive(ptr %t120)
  call void @__free_recursive(ptr %t89)
  call void @__free_recursive(ptr %t87)
  store ptr %t150, ptr %t3
  br label %tco.loop.0
tco.case.default.93:
  unreachable
tco.case.default.8:
  unreachable
tco.exit.1:
  %t151 = load ptr, ptr %t2
  ret ptr %t151
}

define internal ptr @v__cps__lift_16(ptr %v___input, ptr %v__k) {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 39 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  call void @__inc_ref(ptr %v___input)
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v___input, ptr %t3
  call void @__inc_ref(ptr %v__k)
  %t4 = getelementptr ptr, ptr %t0, i32 2
  store ptr %v__k, ptr %t4
  %t5 = call ptr @v__scc__apply__lift_16__cps__lift_16(ptr %t0)
  call void @__free_recursive(ptr %v___input)
  call void @__free_recursive(ptr %v__k)
  ret ptr %t5
}

define internal ptr @v__scc__apply__lift_15__cps__lift_15(ptr %v__args) {
entry:
  %t3 = alloca ptr
  store ptr %v__args, ptr %t3
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t4 = load ptr, ptr %t3
  %t5 = getelementptr ptr, ptr %t4, i32 0
  %t6 = load ptr, ptr %t5
  %t7 = ptrtoint ptr %t6 to i64
  switch i64 %t7, label %tco.case.default.8 [ i64 40, label %tco.case.arm.40.9 i64 41, label %tco.case.arm.41.85 ]
tco.case.arm.40.9:
  %t10 = getelementptr ptr, ptr %t4, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  %t12 = getelementptr ptr, ptr %t4, i32 2
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t11, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %tco.case.default.17 [ i64 30, label %tco.case.arm.30.18 i64 32, label %tco.case.arm.32.19 i64 31, label %tco.case.arm.31.52 ]
tco.case.arm.30.18:
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %t4)
  store ptr %t13, ptr %t2
  br label %tco.exit.1
tco.case.arm.32.19:
  %t20 = getelementptr ptr, ptr %t11, i32 1
  %t21 = load ptr, ptr %t20
  call void @__inc_ref(ptr %t21)
  %t22 = getelementptr ptr, ptr %t11, i32 2
  %t23 = load ptr, ptr %t22
  call void @__inc_ref(ptr %t23)
  %t24 = getelementptr ptr, ptr %t11, i32 3
  %t25 = load ptr, ptr %t24
  call void @__inc_ref(ptr %t25)
  %t26 = call ptr @__alloc(i64 32, i32 3)
  %t27 = inttoptr i64 23 to ptr
  %t28 = getelementptr ptr, ptr %t26, i32 0
  store ptr %t27, ptr %t28
  call void @__inc_ref(ptr %t23)
  %t29 = getelementptr ptr, ptr %t26, i32 1
  store ptr %t23, ptr %t29
  call void @__inc_ref(ptr %t25)
  %t30 = getelementptr ptr, ptr %t26, i32 2
  store ptr %t25, ptr %t30
  call void @__inc_ref(ptr %t13)
  %t31 = getelementptr ptr, ptr %t26, i32 3
  store ptr %t13, ptr %t31
  %t32 = getelementptr i8, ptr %t4, i64 -8
  %t33 = load i32, ptr %t32
  %t34 = icmp eq i32 %t33, 1
  br i1 %t34, label %reuse.in_place.35, label %reuse.copy.36
reuse.in_place.35:
  %t38 = getelementptr ptr, ptr %t4, i32 1
  %t39 = load ptr, ptr %t38
  call void @__free_recursive(ptr %t39)
  %t40 = getelementptr ptr, ptr %t4, i32 2
  %t41 = load ptr, ptr %t40
  call void @__free_recursive(ptr %t41)
  %t44 = inttoptr i64 40 to ptr
  %t45 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t44, ptr %t45
  call void @__inc_ref(ptr %t21)
  %t42 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t21, ptr %t42
  %t43 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t26, ptr %t43
  br label %reuse.join.37
reuse.copy.36:
  %t46 = call ptr @__alloc(i64 24, i32 2)
  %t47 = inttoptr i64 40 to ptr
  %t48 = getelementptr ptr, ptr %t46, i32 0
  store ptr %t47, ptr %t48
  call void @__inc_ref(ptr %t21)
  %t49 = getelementptr ptr, ptr %t46, i32 1
  store ptr %t21, ptr %t49
  %t50 = getelementptr ptr, ptr %t46, i32 2
  store ptr %t26, ptr %t50
  call void @__free_recursive(ptr %t4)
  br label %reuse.join.37
reuse.join.37:
  %t51 = phi ptr [ %t4, %reuse.in_place.35 ], [ %t46, %reuse.copy.36 ]
  call void @__free_recursive(ptr %t25)
  call void @__free_recursive(ptr %t23)
  call void @__free_recursive(ptr %t21)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t51, ptr %t3
  br label %tco.loop.0
tco.case.arm.31.52:
  %t53 = getelementptr ptr, ptr %t11, i32 1
  %t54 = load ptr, ptr %t53
  call void @__inc_ref(ptr %t54)
  %t55 = getelementptr ptr, ptr %t11, i32 2
  %t56 = load ptr, ptr %t55
  call void @__inc_ref(ptr %t56)
  %t57 = getelementptr ptr, ptr %t11, i32 3
  %t58 = load ptr, ptr %t57
  call void @__inc_ref(ptr %t58)
  %t59 = call ptr @__alloc(i64 32, i32 3)
  %t60 = inttoptr i64 32 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  call void @__inc_ref(ptr %t54)
  %t62 = getelementptr ptr, ptr %t59, i32 1
  store ptr %t54, ptr %t62
  call void @__inc_ref(ptr %t13)
  %t63 = getelementptr ptr, ptr %t59, i32 2
  store ptr %t13, ptr %t63
  call void @__inc_ref(ptr %t56)
  %t64 = getelementptr ptr, ptr %t59, i32 3
  store ptr %t56, ptr %t64
  %t65 = getelementptr i8, ptr %t4, i64 -8
  %t66 = load i32, ptr %t65
  %t67 = icmp eq i32 %t66, 1
  br i1 %t67, label %reuse.in_place.68, label %reuse.copy.69
reuse.in_place.68:
  %t71 = getelementptr ptr, ptr %t4, i32 1
  %t72 = load ptr, ptr %t71
  call void @__free_recursive(ptr %t72)
  %t73 = getelementptr ptr, ptr %t4, i32 2
  %t74 = load ptr, ptr %t73
  call void @__free_recursive(ptr %t74)
  %t77 = inttoptr i64 41 to ptr
  %t78 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t77, ptr %t78
  call void @__inc_ref(ptr %t58)
  %t75 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t58, ptr %t75
  %t76 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t59, ptr %t76
  br label %reuse.join.70
reuse.copy.69:
  %t79 = call ptr @__alloc(i64 24, i32 2)
  %t80 = inttoptr i64 41 to ptr
  %t81 = getelementptr ptr, ptr %t79, i32 0
  store ptr %t80, ptr %t81
  call void @__inc_ref(ptr %t58)
  %t82 = getelementptr ptr, ptr %t79, i32 1
  store ptr %t58, ptr %t82
  %t83 = getelementptr ptr, ptr %t79, i32 2
  store ptr %t59, ptr %t83
  call void @__free_recursive(ptr %t4)
  br label %reuse.join.70
reuse.join.70:
  %t84 = phi ptr [ %t4, %reuse.in_place.68 ], [ %t79, %reuse.copy.69 ]
  call void @__free_recursive(ptr %t58)
  call void @__free_recursive(ptr %t56)
  call void @__free_recursive(ptr %t54)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t84, ptr %t3
  br label %tco.loop.0
tco.case.default.17:
  unreachable
tco.case.arm.41.85:
  %t86 = getelementptr ptr, ptr %t4, i32 1
  %t87 = load ptr, ptr %t86
  call void @__inc_ref(ptr %t87)
  %t88 = getelementptr ptr, ptr %t4, i32 2
  %t89 = load ptr, ptr %t88
  call void @__inc_ref(ptr %t89)
  %t90 = getelementptr ptr, ptr %t87, i32 0
  %t91 = load ptr, ptr %t90
  %t92 = ptrtoint ptr %t91 to i64
  switch i64 %t92, label %tco.case.default.93 [ i64 22, label %tco.case.arm.22.94 i64 23, label %tco.case.arm.23.118 ]
tco.case.arm.22.94:
  %t95 = call ptr @__alloc(i64 8, i32 0)
  %t96 = inttoptr i64 22 to ptr
  %t97 = getelementptr ptr, ptr %t95, i32 0
  store ptr %t96, ptr %t97
  %t98 = getelementptr i8, ptr %t4, i64 -8
  %t99 = load i32, ptr %t98
  %t100 = icmp eq i32 %t99, 1
  br i1 %t100, label %reuse.in_place.101, label %reuse.copy.102
reuse.in_place.101:
  %t104 = getelementptr ptr, ptr %t4, i32 1
  %t105 = load ptr, ptr %t104
  call void @__free_recursive(ptr %t105)
  %t106 = getelementptr ptr, ptr %t4, i32 2
  %t107 = load ptr, ptr %t106
  call void @__free_recursive(ptr %t107)
  %t110 = inttoptr i64 40 to ptr
  %t111 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t110, ptr %t111
  call void @__inc_ref(ptr %t89)
  %t108 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t89, ptr %t108
  %t109 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t95, ptr %t109
  br label %reuse.join.103
reuse.copy.102:
  %t112 = call ptr @__alloc(i64 24, i32 2)
  %t113 = inttoptr i64 40 to ptr
  %t114 = getelementptr ptr, ptr %t112, i32 0
  store ptr %t113, ptr %t114
  call void @__inc_ref(ptr %t89)
  %t115 = getelementptr ptr, ptr %t112, i32 1
  store ptr %t89, ptr %t115
  %t116 = getelementptr ptr, ptr %t112, i32 2
  store ptr %t95, ptr %t116
  call void @__free_recursive(ptr %t4)
  br label %reuse.join.103
reuse.join.103:
  %t117 = phi ptr [ %t4, %reuse.in_place.101 ], [ %t112, %reuse.copy.102 ]
  call void @__free_recursive(ptr %t89)
  call void @__free_recursive(ptr %t87)
  store ptr %t117, ptr %t3
  br label %tco.loop.0
tco.case.arm.23.118:
  %t119 = getelementptr ptr, ptr %t87, i32 1
  %t120 = load ptr, ptr %t119
  call void @__inc_ref(ptr %t120)
  %t121 = getelementptr ptr, ptr %t87, i32 2
  %t122 = load ptr, ptr %t121
  call void @__inc_ref(ptr %t122)
  %t123 = getelementptr ptr, ptr %t87, i32 3
  %t124 = load ptr, ptr %t123
  call void @__inc_ref(ptr %t124)
  %t125 = call ptr @__alloc(i64 32, i32 3)
  %t126 = inttoptr i64 31 to ptr
  %t127 = getelementptr ptr, ptr %t125, i32 0
  store ptr %t126, ptr %t127
  call void @__inc_ref(ptr %t89)
  %t128 = getelementptr ptr, ptr %t125, i32 1
  store ptr %t89, ptr %t128
  call void @__inc_ref(ptr %t122)
  %t129 = getelementptr ptr, ptr %t125, i32 2
  store ptr %t122, ptr %t129
  call void @__inc_ref(ptr %t124)
  %t130 = getelementptr ptr, ptr %t125, i32 3
  store ptr %t124, ptr %t130
  %t131 = getelementptr i8, ptr %t4, i64 -8
  %t132 = load i32, ptr %t131
  %t133 = icmp eq i32 %t132, 1
  br i1 %t133, label %reuse.in_place.134, label %reuse.copy.135
reuse.in_place.134:
  %t137 = getelementptr ptr, ptr %t4, i32 1
  %t138 = load ptr, ptr %t137
  call void @__free_recursive(ptr %t138)
  %t139 = getelementptr ptr, ptr %t4, i32 2
  %t140 = load ptr, ptr %t139
  call void @__free_recursive(ptr %t140)
  %t143 = inttoptr i64 41 to ptr
  %t144 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t143, ptr %t144
  call void @__inc_ref(ptr %t120)
  %t141 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t120, ptr %t141
  %t142 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t125, ptr %t142
  br label %reuse.join.136
reuse.copy.135:
  %t145 = call ptr @__alloc(i64 24, i32 2)
  %t146 = inttoptr i64 41 to ptr
  %t147 = getelementptr ptr, ptr %t145, i32 0
  store ptr %t146, ptr %t147
  call void @__inc_ref(ptr %t120)
  %t148 = getelementptr ptr, ptr %t145, i32 1
  store ptr %t120, ptr %t148
  %t149 = getelementptr ptr, ptr %t145, i32 2
  store ptr %t125, ptr %t149
  call void @__free_recursive(ptr %t4)
  br label %reuse.join.136
reuse.join.136:
  %t150 = phi ptr [ %t4, %reuse.in_place.134 ], [ %t145, %reuse.copy.135 ]
  call void @__free_recursive(ptr %t124)
  call void @__free_recursive(ptr %t122)
  call void @__free_recursive(ptr %t120)
  call void @__free_recursive(ptr %t89)
  call void @__free_recursive(ptr %t87)
  store ptr %t150, ptr %t3
  br label %tco.loop.0
tco.case.default.93:
  unreachable
tco.case.default.8:
  unreachable
tco.exit.1:
  %t151 = load ptr, ptr %t2
  ret ptr %t151
}

define internal ptr @v__cps__lift_15(ptr %v___input, ptr %v__k) {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 41 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  call void @__inc_ref(ptr %v___input)
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v___input, ptr %t3
  call void @__inc_ref(ptr %v__k)
  %t4 = getelementptr ptr, ptr %t0, i32 2
  store ptr %v__k, ptr %t4
  %t5 = call ptr @v__scc__apply__lift_15__cps__lift_15(ptr %t0)
  call void @__free_recursive(ptr %v___input)
  call void @__free_recursive(ptr %v__k)
  ret ptr %t5
}

define i32 @main(i32 %argc, ptr %argv) {
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
