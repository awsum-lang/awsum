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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [9 x i8]} { i32 0, i32 0, i32 0, i32 9, i32 9, [9 x i8] c"UNDERFLOW" }

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

define internal ptr @v_buildRight(ptr %v_n, ptr %v_acc) {
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
  switch i64 %t11, label %tco.case.default.12 [ i64 1, label %tco.case.arm.1.13 i64 2, label %tco.case.arm.2.18 ]
tco.case.arm.1.13:
  call void @__free_recursive(ptr %t8)
  %t14 = call ptr @__alloc(i64 16, i32 1)
  %t15 = inttoptr i64 4 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  call void @__inc_ref(ptr %t6)
  %t17 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t6, ptr %t17
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t14, ptr %t2
  br label %tco.exit.1
tco.case.arm.2.18:
  call void @__free_recursive(ptr %t8)
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
  call void @__free_recursive(ptr %t19)
  %t27 = call ptr @__alloc(i64 16, i32 1)
  %t28 = inttoptr i64 3 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  call void @__inc_ref(ptr %t26)
  %t30 = getelementptr ptr, ptr %t27, i32 1
  store ptr %t26, ptr %t30
  call void @__free_recursive(ptr %t26)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t27, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.31:
  %t32 = getelementptr ptr, ptr %t19, i32 1
  %t33 = load ptr, ptr %t32
  call void @__inc_ref(ptr %t33)
  call void @__free_recursive(ptr %t19)
  %t34 = call ptr @__alloc(i64 32, i32 3)
  %t35 = inttoptr i64 25 to ptr
  %t36 = getelementptr ptr, ptr %t34, i32 0
  store ptr %t35, ptr %t36
  %t37 = call ptr @__alloc(i64 8, i32 0)
  %t38 = inttoptr i64 24 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = getelementptr ptr, ptr %t34, i32 1
  store ptr %t37, ptr %t40
  call void @__inc_ref(ptr %t5)
  %t41 = getelementptr ptr, ptr %t34, i32 2
  store ptr %t5, ptr %t41
  call void @__inc_ref(ptr %t6)
  %t42 = getelementptr ptr, ptr %t34, i32 3
  store ptr %t6, ptr %t42
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  store ptr %t33, ptr %t3
  store ptr %t34, ptr %t4
  br label %tco.loop.0
tco.case.default.23:
  unreachable
tco.case.default.12:
  unreachable
tco.exit.1:
  %t43 = load ptr, ptr %t2
  ret ptr %t43
}

define internal ptr @v_spineLast(ptr %v_t, ptr %v_lastV) {
entry:
  %t3 = alloca ptr
  store ptr %v_t, ptr %t3
  %t4 = alloca ptr
  store ptr %v_lastV, ptr %t4
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
  call void @__inc_ref(ptr %t14)
  %t15 = getelementptr ptr, ptr %t5, i32 2
  %t16 = load ptr, ptr %t15
  call void @__inc_ref(ptr %t16)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  store ptr %t14, ptr %t3
  store ptr %t16, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t17 = load ptr, ptr %t2
  ret ptr %t17
}

define internal ptr @v_main() {
  %t0 = call ptr @__alloc(i64 4, i32 0)
  store i32 100000, ptr %t0
  %t1 = call ptr @__alloc(i64 8, i32 0)
  %t2 = inttoptr i64 24 to ptr
  %t3 = getelementptr ptr, ptr %t1, i32 0
  store ptr %t2, ptr %t3
  %t4 = call ptr @v_buildRight(ptr %t0, ptr %t1)
  %t5 = getelementptr ptr, ptr %t4, i32 0
  %t6 = load ptr, ptr %t5
  %t7 = ptrtoint ptr %t6 to i64
  switch i64 %t7, label %case.default.8 [ i64 3, label %case.arm.3.10 i64 4, label %case.arm.4.18 ]
case.arm.3.10:
  %t12 = call ptr @__alloc(i64 16, i32 1)
  %t13 = inttoptr i64 6 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t4, i32 1
  %t16 = load ptr, ptr %t15
  call void @__inc_ref(ptr %t16)
  %t17 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t16, ptr %t17
  br label %case.end.3.11
case.end.3.11:
  br label %case.join.9
case.arm.4.18:
  %t20 = call ptr @__alloc(i64 16, i32 1)
  %t21 = inttoptr i64 5 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = getelementptr ptr, ptr %t4, i32 1
  %t24 = load ptr, ptr %t23
  call void @__inc_ref(ptr %t24)
  %t25 = getelementptr ptr, ptr %t20, i32 1
  store ptr %t24, ptr %t25
  br label %case.end.4.19
case.end.4.19:
  br label %case.join.9
case.default.8:
  unreachable
case.join.9:
  %t26 = phi ptr [ %t12, %case.end.3.11 ], [ %t20, %case.end.4.19 ]
  call void @__free_recursive(ptr %t4)
  %t27 = call ptr @__alloc(i64 8, i32 0)
  %t28 = inttoptr i64 31 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  %t30 = call ptr @v_$cps$$df$andThenIO$4(ptr %t26, ptr %t27)
  %t31 = call ptr @__alloc(i64 8, i32 0)
  %t32 = inttoptr i64 29 to ptr
  %t33 = getelementptr ptr, ptr %t31, i32 0
  store ptr %t32, ptr %t33
  %t34 = call ptr @v_$cps$$df$handleErrorIO$0(ptr %t30, ptr %t31)
  ret ptr %t34
}

define internal ptr @v_$cps$$df$handleErrorIO$0(ptr %v_io, ptr %v_$k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.13 i64 7, label %tco.case.arm.7.27 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t12 = call ptr @v_$apply$$df$handleErrorIO$0(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t12, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.13:
  call void @__inc_ref(ptr %t6)
  %t14 = call ptr @__alloc(i64 24, i32 2)
  %t15 = inttoptr i64 7 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  %t17 = getelementptr ptr, ptr %t14, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t17
  %t18 = call ptr @__alloc(i64 16, i32 1)
  %t19 = inttoptr i64 5 to ptr
  %t20 = getelementptr ptr, ptr %t18, i32 0
  store ptr %t19, ptr %t20
  %t21 = call ptr @__alloc(i64 8, i32 0)
  %t22 = inttoptr i64 0 to ptr
  %t23 = getelementptr ptr, ptr %t21, i32 0
  store ptr %t22, ptr %t23
  %t24 = getelementptr ptr, ptr %t18, i32 1
  store ptr %t21, ptr %t24
  %t25 = getelementptr ptr, ptr %t14, i32 2
  store ptr %t18, ptr %t25
  %t26 = call ptr @v_$apply$$df$handleErrorIO$0(ptr %t6, ptr %t14)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t26, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.27:
  %t28 = getelementptr ptr, ptr %t5, i32 1
  %t29 = load ptr, ptr %t28
  %t30 = getelementptr ptr, ptr %t5, i32 2
  %t31 = load ptr, ptr %t30
  call void @__inc_ref(ptr %t31)
  %t38 = getelementptr i8, ptr %t5, i64 -8
  %t39 = load i32, ptr %t38
  %t40 = icmp eq i32 %t39, 1
  br i1 %t40, label %reuse.in_place.41, label %reuse.copy.42
reuse.in_place.41:
  %t32 = getelementptr ptr, ptr %t5, i32 2
  %t33 = load ptr, ptr %t32
  call void @__free_recursive(ptr %t33)
  %t36 = inttoptr i64 30 to ptr
  %t37 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t36, ptr %t37
  call void @__inc_ref(ptr %t6)
  %t34 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t34
  %t35 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t29, ptr %t35
  br label %reuse.in_place.end.44
reuse.in_place.end.44:
  br label %reuse.join.43
reuse.copy.42:
  %t46 = call ptr @__alloc(i64 24, i32 2)
  %t47 = inttoptr i64 30 to ptr
  %t48 = getelementptr ptr, ptr %t46, i32 0
  store ptr %t47, ptr %t48
  call void @__inc_ref(ptr %t6)
  %t49 = getelementptr ptr, ptr %t46, i32 1
  store ptr %t6, ptr %t49
  call void @__inc_ref(ptr %t29)
  %t50 = getelementptr ptr, ptr %t46, i32 2
  store ptr %t29, ptr %t50
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.45
reuse.copy.end.45:
  br label %reuse.join.43
reuse.join.43:
  %t51 = phi ptr [ %t5, %reuse.in_place.end.44 ], [ %t46, %reuse.copy.end.45 ]
  call void @__free_recursive(ptr %t6)
  store ptr %t31, ptr %t3
  store ptr %t51, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t52 = load ptr, ptr %t2
  ret ptr %t52
}

define internal ptr @v_$apply$$df$handleErrorIO$0(ptr %v_$k, ptr %v_$x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 29, label %tco.case.arm.29.11 i64 30, label %tco.case.arm.30.12 ]
tco.case.arm.29.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.30.12:
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

define internal ptr @v_$cps$$df$andThenIO$4(ptr %v_io, ptr %v_$k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.39 i64 7, label %tco.case.arm.7.41 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = call ptr @__alloc(i64 24, i32 2)
  %t16 = inttoptr i64 34 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = getelementptr ptr, ptr %t5, i32 1
  %t19 = load ptr, ptr %t18
  call void @__inc_ref(ptr %t19)
  %t20 = getelementptr ptr, ptr %t15, i32 1
  store ptr %t19, ptr %t20
  %t21 = call ptr @__alloc(i64 8, i32 0)
  %t22 = inttoptr i64 26 to ptr
  %t23 = getelementptr ptr, ptr %t21, i32 0
  store ptr %t22, ptr %t23
  %t24 = getelementptr ptr, ptr %t15, i32 2
  store ptr %t21, ptr %t24
  %t25 = call ptr @v_$scc$$apply$mirror__$cps$mirror(ptr %t15)
  %t26 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t26
  %t27 = call ptr @v_spineLast(ptr %t25, ptr %t26)
  %t28 = call ptr @__showInt32(ptr %t27)
  %t29 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t28, ptr %t29
  %t30 = call ptr @__alloc(i64 16, i32 1)
  %t31 = inttoptr i64 5 to ptr
  %t32 = getelementptr ptr, ptr %t30, i32 0
  store ptr %t31, ptr %t32
  %t33 = call ptr @__alloc(i64 8, i32 0)
  %t34 = inttoptr i64 0 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = getelementptr ptr, ptr %t30, i32 1
  store ptr %t33, ptr %t36
  %t37 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t30, ptr %t37
  %t38 = call ptr @v_$apply$$df$andThenIO$4(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t38, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.39:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t40 = call ptr @v_$apply$$df$andThenIO$4(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t40, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.41:
  %t42 = getelementptr ptr, ptr %t5, i32 1
  %t43 = load ptr, ptr %t42
  %t44 = getelementptr ptr, ptr %t5, i32 2
  %t45 = load ptr, ptr %t44
  call void @__inc_ref(ptr %t45)
  %t52 = getelementptr i8, ptr %t5, i64 -8
  %t53 = load i32, ptr %t52
  %t54 = icmp eq i32 %t53, 1
  br i1 %t54, label %reuse.in_place.55, label %reuse.copy.56
reuse.in_place.55:
  %t46 = getelementptr ptr, ptr %t5, i32 2
  %t47 = load ptr, ptr %t46
  call void @__free_recursive(ptr %t47)
  %t50 = inttoptr i64 32 to ptr
  %t51 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t50, ptr %t51
  call void @__inc_ref(ptr %t6)
  %t48 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t48
  %t49 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t43, ptr %t49
  br label %reuse.in_place.end.58
reuse.in_place.end.58:
  br label %reuse.join.57
reuse.copy.56:
  %t60 = call ptr @__alloc(i64 24, i32 2)
  %t61 = inttoptr i64 32 to ptr
  %t62 = getelementptr ptr, ptr %t60, i32 0
  store ptr %t61, ptr %t62
  call void @__inc_ref(ptr %t6)
  %t63 = getelementptr ptr, ptr %t60, i32 1
  store ptr %t6, ptr %t63
  call void @__inc_ref(ptr %t43)
  %t64 = getelementptr ptr, ptr %t60, i32 2
  store ptr %t43, ptr %t64
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.59
reuse.copy.end.59:
  br label %reuse.join.57
reuse.join.57:
  %t65 = phi ptr [ %t5, %reuse.in_place.end.58 ], [ %t60, %reuse.copy.end.59 ]
  call void @__free_recursive(ptr %t6)
  store ptr %t45, ptr %t3
  store ptr %t65, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t66 = load ptr, ptr %t2
  ret ptr %t66
}

define internal ptr @v_$apply$$df$andThenIO$4(ptr %v_$k, ptr %v_$x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 31, label %tco.case.arm.31.11 i64 32, label %tco.case.arm.32.12 ]
tco.case.arm.31.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.32.12:
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

define internal ptr @v_$scc$$apply$mirror__$cps$mirror(ptr %v_$args) {
entry:
  %t3 = alloca ptr
  store ptr %v_$args, ptr %t3
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t4 = load ptr, ptr %t3
  %t5 = getelementptr ptr, ptr %t4, i32 0
  %t6 = load ptr, ptr %t5
  %t7 = ptrtoint ptr %t6 to i64
  switch i64 %t7, label %tco.case.default.8 [ i64 33, label %tco.case.arm.33.9 i64 34, label %tco.case.arm.34.61 ]
tco.case.arm.33.9:
  %t10 = getelementptr ptr, ptr %t4, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  %t12 = getelementptr ptr, ptr %t4, i32 2
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t11, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %tco.case.default.17 [ i64 26, label %tco.case.arm.26.18 i64 28, label %tco.case.arm.28.19 i64 27, label %tco.case.arm.27.41 ]
tco.case.arm.26.18:
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %t4)
  store ptr %t13, ptr %t2
  br label %tco.exit.1
tco.case.arm.28.19:
  %t20 = getelementptr ptr, ptr %t11, i32 1
  %t21 = load ptr, ptr %t20
  call void @__inc_ref(ptr %t21)
  %t22 = getelementptr ptr, ptr %t11, i32 2
  %t23 = load ptr, ptr %t22
  %t24 = getelementptr ptr, ptr %t11, i32 3
  %t25 = load ptr, ptr %t24
  %t26 = getelementptr ptr, ptr %t4, i32 1
  %t27 = load ptr, ptr %t26
  call void @__free_recursive(ptr %t27)
  %t28 = getelementptr ptr, ptr %t4, i32 2
  %t29 = load ptr, ptr %t28
  call void @__free_recursive(ptr %t29)
  %t39 = inttoptr i64 33 to ptr
  %t40 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t39, ptr %t40
  call void @__inc_ref(ptr %t21)
  %t30 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t21, ptr %t30
  %t31 = getelementptr ptr, ptr %t11, i32 1
  %t32 = load ptr, ptr %t31
  call void @__free_recursive(ptr %t32)
  %t36 = inttoptr i64 25 to ptr
  %t37 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t36, ptr %t37
  %t33 = getelementptr ptr, ptr %t11, i32 1
  store ptr %t23, ptr %t33
  %t34 = getelementptr ptr, ptr %t11, i32 2
  store ptr %t25, ptr %t34
  call void @__inc_ref(ptr %t13)
  %t35 = getelementptr ptr, ptr %t11, i32 3
  store ptr %t13, ptr %t35
  %t38 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t11, ptr %t38
  call void @__free_recursive(ptr %t21)
  call void @__free_recursive(ptr %t13)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.27.41:
  %t42 = getelementptr ptr, ptr %t11, i32 1
  %t43 = load ptr, ptr %t42
  %t44 = getelementptr ptr, ptr %t11, i32 2
  %t45 = load ptr, ptr %t44
  call void @__inc_ref(ptr %t45)
  %t46 = getelementptr ptr, ptr %t11, i32 3
  %t47 = load ptr, ptr %t46
  %t48 = getelementptr ptr, ptr %t4, i32 1
  %t49 = load ptr, ptr %t48
  call void @__free_recursive(ptr %t49)
  %t50 = getelementptr ptr, ptr %t4, i32 2
  %t51 = load ptr, ptr %t50
  call void @__free_recursive(ptr %t51)
  %t59 = inttoptr i64 34 to ptr
  %t60 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t59, ptr %t60
  call void @__inc_ref(ptr %t45)
  %t52 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t45, ptr %t52
  %t53 = getelementptr ptr, ptr %t11, i32 2
  %t54 = load ptr, ptr %t53
  call void @__free_recursive(ptr %t54)
  %t56 = inttoptr i64 28 to ptr
  %t57 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t56, ptr %t57
  call void @__inc_ref(ptr %t13)
  %t55 = getelementptr ptr, ptr %t11, i32 2
  store ptr %t13, ptr %t55
  %t58 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t11, ptr %t58
  call void @__free_recursive(ptr %t45)
  call void @__free_recursive(ptr %t13)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.17:
  unreachable
tco.case.arm.34.61:
  %t62 = getelementptr ptr, ptr %t4, i32 1
  %t63 = load ptr, ptr %t62
  call void @__inc_ref(ptr %t63)
  %t64 = getelementptr ptr, ptr %t4, i32 2
  %t65 = load ptr, ptr %t64
  call void @__inc_ref(ptr %t65)
  %t66 = getelementptr ptr, ptr %t63, i32 0
  %t67 = load ptr, ptr %t66
  %t68 = ptrtoint ptr %t67 to i64
  switch i64 %t68, label %tco.case.default.69 [ i64 24, label %tco.case.arm.24.70 i64 25, label %tco.case.arm.25.79 ]
tco.case.arm.24.70:
  %t71 = getelementptr ptr, ptr %t4, i32 1
  %t72 = load ptr, ptr %t71
  call void @__free_recursive(ptr %t72)
  %t73 = getelementptr ptr, ptr %t4, i32 2
  %t74 = load ptr, ptr %t73
  call void @__free_recursive(ptr %t74)
  %t77 = inttoptr i64 33 to ptr
  %t78 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t77, ptr %t78
  call void @__inc_ref(ptr %t65)
  %t75 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t65, ptr %t75
  call void @__inc_ref(ptr %t63)
  %t76 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t63, ptr %t76
  call void @__free_recursive(ptr %t65)
  call void @__free_recursive(ptr %t63)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.25.79:
  %t80 = getelementptr ptr, ptr %t63, i32 3
  %t81 = load ptr, ptr %t80
  call void @__inc_ref(ptr %t81)
  %t82 = call ptr @__alloc(i64 32, i32 3)
  %t83 = inttoptr i64 27 to ptr
  %t84 = getelementptr ptr, ptr %t82, i32 0
  store ptr %t83, ptr %t84
  call void @__inc_ref(ptr %t65)
  %t85 = getelementptr ptr, ptr %t82, i32 1
  store ptr %t65, ptr %t85
  %t86 = getelementptr ptr, ptr %t63, i32 1
  %t87 = load ptr, ptr %t86
  call void @__inc_ref(ptr %t87)
  %t88 = getelementptr ptr, ptr %t82, i32 2
  store ptr %t87, ptr %t88
  %t89 = getelementptr ptr, ptr %t63, i32 2
  %t90 = load ptr, ptr %t89
  call void @__inc_ref(ptr %t90)
  %t91 = getelementptr ptr, ptr %t82, i32 3
  store ptr %t90, ptr %t91
  %t92 = getelementptr ptr, ptr %t4, i32 1
  %t93 = load ptr, ptr %t92
  call void @__free_recursive(ptr %t93)
  %t94 = getelementptr ptr, ptr %t4, i32 2
  %t95 = load ptr, ptr %t94
  call void @__free_recursive(ptr %t95)
  %t98 = inttoptr i64 34 to ptr
  %t99 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t98, ptr %t99
  %t96 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t81, ptr %t96
  %t97 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t82, ptr %t97
  call void @__free_recursive(ptr %t65)
  call void @__free_recursive(ptr %t63)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.69:
  unreachable
tco.case.default.8:
  unreachable
tco.exit.1:
  %t100 = load ptr, ptr %t2
  ret ptr %t100
}

define i32 @main(i32 %argc, ptr %argv) {
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
