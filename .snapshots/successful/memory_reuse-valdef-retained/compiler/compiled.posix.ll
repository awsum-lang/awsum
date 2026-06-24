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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"E" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"e" }

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

define internal ptr @v_mk(ptr %v_n, ptr %v_acc) {
entry:
  %t3 = alloca ptr
  store ptr %v_n, ptr %t3
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
  switch i64 %t11, label %tco.case.default.12 [ i64 1, label %tco.case.arm.1.13 i64 2, label %tco.case.arm.2.14 ]
tco.case.arm.1.13:
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.2.14:
  call void @__free_recursive(ptr %t8)
  call void @__inc_ref(ptr %t5)
  %t15 = call ptr @__predInt32(ptr %t5)
  %t16 = getelementptr ptr, ptr %t15, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %tco.case.default.19 [ i64 3, label %tco.case.arm.3.20 i64 4, label %tco.case.arm.4.21 ]
tco.case.arm.3.20:
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.21:
  %t22 = getelementptr ptr, ptr %t15, i32 1
  %t23 = load ptr, ptr %t22
  call void @__inc_ref(ptr %t23)
  call void @__free_recursive(ptr %t15)
  %t24 = call ptr @__alloc(i64 24, i32 2)
  %t25 = inttoptr i64 25 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  call void @__inc_ref(ptr %t5)
  %t27 = call ptr @__showInt32(ptr %t5)
  %t28 = getelementptr ptr, ptr %t24, i32 1
  store ptr %t27, ptr %t28
  call void @__inc_ref(ptr %t6)
  %t29 = getelementptr ptr, ptr %t24, i32 2
  store ptr %t6, ptr %t29
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  store ptr %t23, ptr %t3
  store ptr %t24, ptr %t4
  br label %tco.loop.0
tco.case.default.19:
  unreachable
tco.case.default.12:
  unreachable
tco.exit.1:
  %t30 = load ptr, ptr %t2
  ret ptr %t30
}

define internal ptr @v_threeUp() {
  %t0 = call ptr @__alloc(i64 4, i32 0)
  store i32 3, ptr %t0
  %t1 = call ptr @__alloc(i64 8, i32 0)
  %t2 = inttoptr i64 24 to ptr
  %t3 = getelementptr ptr, ptr %t1, i32 0
  store ptr %t2, ptr %t3
  %t4 = call ptr @v_mk(ptr %t0, ptr %t1)
  ret ptr %t4
}

define internal ptr @v_revInto2(ptr %v_lst, ptr %v_acc) {
entry:
  %t3 = alloca ptr
  store ptr %v_lst, ptr %t3
  %t4 = alloca ptr
  store ptr %v_acc, ptr %t4
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t5 = load ptr, ptr %t3
  %t6 = load ptr, ptr %t4
  %t7 = getelementptr ptr, ptr %t5, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %tco.case.default.10 [ i64 24, label %tco.case.arm.24.11 i64 25, label %tco.case.arm.25.12 ]
tco.case.arm.24.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.25.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  %t15 = getelementptr ptr, ptr %t5, i32 2
  %t16 = load ptr, ptr %t15
  call void @__inc_ref(ptr %t16)
  %t22 = getelementptr i8, ptr %t5, i64 -8
  %t23 = load i32, ptr %t22
  %t24 = icmp eq i32 %t23, 1
  br i1 %t24, label %reuse.in_place.25, label %reuse.copy.26
reuse.in_place.25:
  %t17 = getelementptr ptr, ptr %t5, i32 2
  %t18 = load ptr, ptr %t17
  call void @__free_recursive(ptr %t18)
  %t20 = inttoptr i64 25 to ptr
  %t21 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t20, ptr %t21
  call void @__inc_ref(ptr %t6)
  %t19 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t6, ptr %t19
  br label %reuse.in_place.end.28
reuse.in_place.end.28:
  br label %reuse.join.27
reuse.copy.26:
  %t30 = call ptr @__alloc(i64 24, i32 2)
  %t31 = inttoptr i64 25 to ptr
  %t32 = getelementptr ptr, ptr %t30, i32 0
  store ptr %t31, ptr %t32
  call void @__inc_ref(ptr %t14)
  %t33 = getelementptr ptr, ptr %t30, i32 1
  store ptr %t14, ptr %t33
  call void @__inc_ref(ptr %t6)
  %t34 = getelementptr ptr, ptr %t30, i32 2
  store ptr %t6, ptr %t34
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.29
reuse.copy.end.29:
  br label %reuse.join.27
reuse.join.27:
  %t35 = phi ptr [ %t5, %reuse.in_place.end.28 ], [ %t30, %reuse.copy.end.29 ]
  call void @__free_recursive(ptr %t6)
  store ptr %t16, ptr %t3
  store ptr %t35, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t36 = load ptr, ptr %t2
  ret ptr %t36
}

define internal ptr @v_main() {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 7 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_threeUp()
  %t4 = call ptr @__alloc(i64 8, i32 0)
  %t5 = inttoptr i64 24 to ptr
  %t6 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5, ptr %t6
  %t7 = call ptr @v_revInto2(ptr %t3, ptr %t4)
  %t8 = getelementptr ptr, ptr %t7, i32 0
  %t9 = load ptr, ptr %t8
  %t10 = ptrtoint ptr %t9 to i64
  switch i64 %t10, label %case.default.11 [ i64 24, label %case.arm.24.13 i64 25, label %case.arm.25.15 ]
case.arm.24.13:
  br label %case.end.24.14
case.end.24.14:
  br label %case.join.12
case.arm.25.15:
  %t17 = getelementptr ptr, ptr %t7, i32 2
  %t18 = load ptr, ptr %t17
  call void @__inc_ref(ptr %t18)
  %t19 = getelementptr ptr, ptr %t18, i32 0
  %t20 = load ptr, ptr %t19
  %t21 = ptrtoint ptr %t20 to i64
  switch i64 %t21, label %case.default.22 [ i64 24, label %case.arm.24.24 i64 25, label %case.arm.25.26 ]
case.arm.24.24:
  br label %case.end.24.25
case.end.24.25:
  br label %case.join.23
case.arm.25.26:
  %t28 = getelementptr ptr, ptr %t18, i32 1
  %t29 = load ptr, ptr %t28
  call void @__inc_ref(ptr %t29)
  br label %case.end.25.27
case.end.25.27:
  br label %case.join.23
case.default.22:
  unreachable
case.join.23:
  %t30 = phi ptr [ getelementptr inbounds (i8, ptr @.str.1, i64 12), %case.end.24.25 ], [ %t29, %case.end.25.27 ]
  br label %case.end.25.16
case.end.25.16:
  br label %case.join.12
case.default.11:
  unreachable
case.join.12:
  %t31 = phi ptr [ getelementptr inbounds (i8, ptr @.str.0, i64 12), %case.end.24.14 ], [ %t30, %case.end.25.16 ]
  call void @__free_recursive(ptr %t7)
  %t32 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t31, ptr %t32
  %t33 = call ptr @__alloc(i64 16, i32 1)
  %t34 = inttoptr i64 5 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = call ptr @__alloc(i64 8, i32 0)
  %t37 = inttoptr i64 0 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t33, i32 1
  store ptr %t36, ptr %t39
  %t40 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t33, ptr %t40
  %t41 = call ptr @__alloc(i64 8, i32 0)
  %t42 = inttoptr i64 26 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = call ptr @v_$cps$$df$andThenIO$0(ptr %t0, ptr %t41)
  ret ptr %t44
}

define internal ptr @v_$cps$$df$andThenIO$0(ptr %v_io, ptr %v_$k) {
entry:
  %t3 = alloca ptr
  store ptr %v_io, ptr %t3
  %t4 = alloca ptr
  store ptr %v_$k, ptr %t4
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t5 = load ptr, ptr %t3
  %t6 = load ptr, ptr %t4
  %t7 = getelementptr ptr, ptr %t5, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 7, label %tco.case.arm.7.50 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = call ptr @v_threeUp()
  %t16 = getelementptr ptr, ptr %t15, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %case.default.19 [ i64 24, label %case.arm.24.21 i64 25, label %case.arm.25.23 ]
case.arm.24.21:
  br label %case.end.24.22
case.end.24.22:
  br label %case.join.20
case.arm.25.23:
  %t25 = getelementptr ptr, ptr %t15, i32 2
  %t26 = load ptr, ptr %t25
  call void @__inc_ref(ptr %t26)
  %t27 = getelementptr ptr, ptr %t26, i32 0
  %t28 = load ptr, ptr %t27
  %t29 = ptrtoint ptr %t28 to i64
  switch i64 %t29, label %case.default.30 [ i64 24, label %case.arm.24.32 i64 25, label %case.arm.25.34 ]
case.arm.24.32:
  br label %case.end.24.33
case.end.24.33:
  br label %case.join.31
case.arm.25.34:
  %t36 = getelementptr ptr, ptr %t26, i32 1
  %t37 = load ptr, ptr %t36
  call void @__inc_ref(ptr %t37)
  br label %case.end.25.35
case.end.25.35:
  br label %case.join.31
case.default.30:
  unreachable
case.join.31:
  %t38 = phi ptr [ getelementptr inbounds (i8, ptr @.str.1, i64 12), %case.end.24.33 ], [ %t37, %case.end.25.35 ]
  call void @__free_recursive(ptr %t26)
  br label %case.end.25.24
case.end.25.24:
  br label %case.join.20
case.default.19:
  unreachable
case.join.20:
  %t39 = phi ptr [ getelementptr inbounds (i8, ptr @.str.0, i64 12), %case.end.24.22 ], [ %t38, %case.end.25.24 ]
  call void @__free_recursive(ptr %t15)
  %t40 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t39, ptr %t40
  %t41 = call ptr @__alloc(i64 16, i32 1)
  %t42 = inttoptr i64 5 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = call ptr @__alloc(i64 8, i32 0)
  %t45 = inttoptr i64 0 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  %t47 = getelementptr ptr, ptr %t41, i32 1
  store ptr %t44, ptr %t47
  %t48 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t41, ptr %t48
  %t49 = call ptr @v_$apply$$df$andThenIO$0(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t49, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.50:
  %t51 = getelementptr ptr, ptr %t5, i32 1
  %t52 = load ptr, ptr %t51
  %t53 = getelementptr ptr, ptr %t5, i32 2
  %t54 = load ptr, ptr %t53
  call void @__inc_ref(ptr %t54)
  %t61 = getelementptr i8, ptr %t5, i64 -8
  %t62 = load i32, ptr %t61
  %t63 = icmp eq i32 %t62, 1
  br i1 %t63, label %reuse.in_place.64, label %reuse.copy.65
reuse.in_place.64:
  %t55 = getelementptr ptr, ptr %t5, i32 2
  %t56 = load ptr, ptr %t55
  call void @__free_recursive(ptr %t56)
  %t59 = inttoptr i64 27 to ptr
  %t60 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t59, ptr %t60
  call void @__inc_ref(ptr %t6)
  %t57 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t57
  %t58 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t52, ptr %t58
  br label %reuse.in_place.end.67
reuse.in_place.end.67:
  br label %reuse.join.66
reuse.copy.65:
  %t69 = call ptr @__alloc(i64 24, i32 2)
  %t70 = inttoptr i64 27 to ptr
  %t71 = getelementptr ptr, ptr %t69, i32 0
  store ptr %t70, ptr %t71
  call void @__inc_ref(ptr %t6)
  %t72 = getelementptr ptr, ptr %t69, i32 1
  store ptr %t6, ptr %t72
  call void @__inc_ref(ptr %t52)
  %t73 = getelementptr ptr, ptr %t69, i32 2
  store ptr %t52, ptr %t73
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.68
reuse.copy.end.68:
  br label %reuse.join.66
reuse.join.66:
  %t74 = phi ptr [ %t5, %reuse.in_place.end.67 ], [ %t69, %reuse.copy.end.68 ]
  call void @__free_recursive(ptr %t6)
  store ptr %t54, ptr %t3
  store ptr %t74, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t75 = load ptr, ptr %t2
  ret ptr %t75
}

define internal ptr @v_$apply$$df$andThenIO$0(ptr %v_$k, ptr %v_$x) {
entry:
  %t3 = alloca ptr
  store ptr %v_$k, ptr %t3
  %t4 = alloca ptr
  store ptr %v_$x, ptr %t4
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t5 = load ptr, ptr %t3
  %t6 = load ptr, ptr %t4
  %t7 = getelementptr ptr, ptr %t5, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %tco.case.default.10 [ i64 26, label %tco.case.arm.26.11 i64 27, label %tco.case.arm.27.12 ]
tco.case.arm.26.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.27.12:
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

define i32 @main(i32 %argc, ptr %argv) {
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
