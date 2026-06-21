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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [13 x i8]} { i32 0, i32 0, i32 0, i32 13, i32 13, [13 x i8] c"OverflowError" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [14 x i8]} { i32 0, i32 0, i32 0, i32 14, i32 14, [14 x i8] c"UnderflowError" }

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


define internal ptr @__succInt32(ptr %p) {
  %v = load i32, ptr %p
  %is_max = icmp eq i32 %v, 2147483647
  br i1 %is_max, label %overflow, label %ok
overflow:
  %oe = call ptr @__alloc(i64 8, i32 0)
  %oe_tag = inttoptr i64 18 to ptr
  store ptr %oe_tag, ptr %oe
  %left = call ptr @__alloc(i64 16, i32 1)
  %left_tag = inttoptr i64 3 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %oe, ptr %left_f
  call void @__free_recursive(ptr %p)
  ret ptr %left
ok:
  %newv = add i32 %v, 1
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

define internal ptr @v_main() {
  %t0 = call ptr @v_runDemo()
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 3, label %case.arm.3.6 i64 4, label %case.arm.4.32 ]
case.arm.3.6:
  %t8 = getelementptr ptr, ptr %t0, i32 1
  %t9 = load ptr, ptr %t8
  call void @__inc_ref(ptr %t9)
  %t10 = call ptr @__alloc(i64 24, i32 2)
  %t11 = inttoptr i64 7 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  %t13 = getelementptr ptr, ptr %t9, i32 0
  %t14 = load ptr, ptr %t13
  %t15 = ptrtoint ptr %t14 to i64
  switch i64 %t15, label %case.default.16 [ i64 882564211, label %case.arm.882564211.18 i64 3768445577, label %case.arm.3768445577.20 ]
case.arm.882564211.18:
  br label %case.end.882564211.19
case.end.882564211.19:
  br label %case.join.17
case.arm.3768445577.20:
  br label %case.end.3768445577.21
case.end.3768445577.21:
  br label %case.join.17
case.default.16:
  unreachable
case.join.17:
  %t22 = phi ptr [ getelementptr inbounds (i8, ptr @.str.0, i64 12), %case.end.882564211.19 ], [ getelementptr inbounds (i8, ptr @.str.1, i64 12), %case.end.3768445577.21 ]
  %t23 = getelementptr ptr, ptr %t10, i32 1
  store ptr %t22, ptr %t23
  %t24 = call ptr @__alloc(i64 16, i32 1)
  %t25 = inttoptr i64 5 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @__alloc(i64 8, i32 0)
  %t28 = inttoptr i64 0 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  %t30 = getelementptr ptr, ptr %t24, i32 1
  store ptr %t27, ptr %t30
  %t31 = getelementptr ptr, ptr %t10, i32 2
  store ptr %t24, ptr %t31
  br label %case.end.3.7
case.end.3.7:
  br label %case.join.5
case.arm.4.32:
  %t34 = getelementptr ptr, ptr %t0, i32 1
  %t35 = load ptr, ptr %t34
  call void @__inc_ref(ptr %t35)
  %t36 = call ptr @__alloc(i64 24, i32 2)
  %t37 = inttoptr i64 7 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  call void @__inc_ref(ptr %t35)
  %t39 = call ptr @__showInt32(ptr %t35)
  %t40 = getelementptr ptr, ptr %t36, i32 1
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
  %t48 = getelementptr ptr, ptr %t36, i32 2
  store ptr %t41, ptr %t48
  br label %case.end.4.33
case.end.4.33:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t49 = phi ptr [ %t10, %case.end.3.7 ], [ %t36, %case.end.4.33 ]
  call void @__free_recursive(ptr %t0)
  ret ptr %t49
}

define internal ptr @v_runDemo() {
  %t0 = call ptr @__alloc(i64 4, i32 0)
  store i32 5000000, ptr %t0
  %t1 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t1
  %t2 = call ptr @v_countTail(ptr %t0, ptr %t1)
  %t3 = getelementptr ptr, ptr %t2, i32 0
  %t4 = load ptr, ptr %t3
  %t5 = ptrtoint ptr %t4 to i64
  switch i64 %t5, label %case.default.6 [ i64 3, label %case.arm.3.8 i64 4, label %case.arm.4.16 ]
case.arm.3.8:
  %t10 = getelementptr ptr, ptr %t2, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  %t12 = call ptr @__alloc(i64 16, i32 1)
  %t13 = inttoptr i64 3 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  call void @__inc_ref(ptr %t11)
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t11, ptr %t15
  br label %case.end.3.9
case.end.3.9:
  br label %case.join.7
case.arm.4.16:
  %t18 = getelementptr ptr, ptr %t2, i32 1
  %t19 = load ptr, ptr %t18
  call void @__inc_ref(ptr %t19)
  %t20 = call ptr @__alloc(i64 4, i32 0)
  store i32 25, ptr %t20
  call void @__inc_ref(ptr %t19)
  %t21 = call ptr @v_descendN(ptr %t20, ptr %t19)
  %t22 = getelementptr ptr, ptr %t21, i32 0
  %t23 = load ptr, ptr %t22
  %t24 = ptrtoint ptr %t23 to i64
  switch i64 %t24, label %case.default.25 [ i64 3, label %case.arm.3.27 i64 4, label %case.arm.4.35 ]
case.arm.3.27:
  %t29 = getelementptr ptr, ptr %t21, i32 1
  %t30 = load ptr, ptr %t29
  call void @__inc_ref(ptr %t30)
  %t31 = call ptr @__alloc(i64 16, i32 1)
  %t32 = inttoptr i64 3 to ptr
  %t33 = getelementptr ptr, ptr %t31, i32 0
  store ptr %t32, ptr %t33
  call void @__inc_ref(ptr %t30)
  %t34 = getelementptr ptr, ptr %t31, i32 1
  store ptr %t30, ptr %t34
  br label %case.end.3.28
case.end.3.28:
  br label %case.join.26
case.arm.4.35:
  %t37 = getelementptr ptr, ptr %t21, i32 1
  %t38 = load ptr, ptr %t37
  call void @__inc_ref(ptr %t38)
  %t39 = call ptr @__alloc(i64 24, i32 2)
  %t40 = inttoptr i64 8 to ptr
  %t41 = getelementptr ptr, ptr %t39, i32 0
  store ptr %t40, ptr %t41
  call void @__inc_ref(ptr %t38)
  %t42 = getelementptr ptr, ptr %t39, i32 1
  store ptr %t38, ptr %t42
  %t43 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t43
  %t44 = getelementptr ptr, ptr %t39, i32 2
  store ptr %t43, ptr %t44
  %t45 = call ptr @v__scc_spinA_spinB_spinC(ptr %t39)
  br label %case.end.4.36
case.end.4.36:
  br label %case.join.26
case.default.25:
  unreachable
case.join.26:
  %t46 = phi ptr [ %t31, %case.end.3.28 ], [ %t45, %case.end.4.36 ]
  call void @__free_recursive(ptr %t21)
  br label %case.end.4.17
case.end.4.17:
  br label %case.join.7
case.default.6:
  unreachable
case.join.7:
  %t47 = phi ptr [ %t12, %case.end.3.9 ], [ %t46, %case.end.4.17 ]
  call void @__free_recursive(ptr %t2)
  ret ptr %t47
}

define internal ptr @v_countTail(ptr %v_remaining, ptr %v_acc) {
entry:
  %t3 = alloca ptr
  store ptr %v_remaining, ptr %t3
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
  call void @__inc_ref(ptr %t6)
  %t19 = call ptr @__succInt32(ptr %t6)
  %t20 = getelementptr ptr, ptr %t19, i32 0
  %t21 = load ptr, ptr %t20
  %t22 = ptrtoint ptr %t21 to i64
  switch i64 %t22, label %tco.case.default.23 [ i64 3, label %tco.case.arm.3.24 i64 4, label %tco.case.arm.4.35 ]
tco.case.arm.3.24:
  %t25 = getelementptr ptr, ptr %t19, i32 1
  %t26 = load ptr, ptr %t25
  call void @__inc_ref(ptr %t26)
  %t27 = call ptr @__alloc(i64 16, i32 1)
  %t28 = inttoptr i64 3 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  %t30 = call ptr @__alloc(i64 16, i32 1)
  %t31 = inttoptr i64 882564211 to ptr
  %t32 = getelementptr ptr, ptr %t30, i32 0
  store ptr %t31, ptr %t32
  call void @__inc_ref(ptr %t26)
  %t33 = getelementptr ptr, ptr %t30, i32 1
  store ptr %t26, ptr %t33
  %t34 = getelementptr ptr, ptr %t27, i32 1
  store ptr %t30, ptr %t34
  call void @__free_recursive(ptr %t19)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t26)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t27, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.35:
  %t36 = getelementptr ptr, ptr %t19, i32 1
  %t37 = load ptr, ptr %t36
  call void @__inc_ref(ptr %t37)
  call void @__inc_ref(ptr %t5)
  %t38 = call ptr @__predInt32(ptr %t5)
  %t39 = getelementptr ptr, ptr %t38, i32 0
  %t40 = load ptr, ptr %t39
  %t41 = ptrtoint ptr %t40 to i64
  switch i64 %t41, label %tco.case.default.42 [ i64 3, label %tco.case.arm.3.43 i64 4, label %tco.case.arm.4.54 ]
tco.case.arm.3.43:
  %t44 = getelementptr ptr, ptr %t38, i32 1
  %t45 = load ptr, ptr %t44
  call void @__inc_ref(ptr %t45)
  %t46 = call ptr @__alloc(i64 16, i32 1)
  %t47 = inttoptr i64 3 to ptr
  %t48 = getelementptr ptr, ptr %t46, i32 0
  store ptr %t47, ptr %t48
  %t49 = call ptr @__alloc(i64 16, i32 1)
  %t50 = inttoptr i64 3768445577 to ptr
  %t51 = getelementptr ptr, ptr %t49, i32 0
  store ptr %t50, ptr %t51
  call void @__inc_ref(ptr %t45)
  %t52 = getelementptr ptr, ptr %t49, i32 1
  store ptr %t45, ptr %t52
  %t53 = getelementptr ptr, ptr %t46, i32 1
  store ptr %t49, ptr %t53
  call void @__free_recursive(ptr %t38)
  call void @__free_recursive(ptr %t19)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t45)
  call void @__free_recursive(ptr %t37)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t46, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.54:
  %t55 = getelementptr ptr, ptr %t38, i32 1
  %t56 = load ptr, ptr %t55
  call void @__inc_ref(ptr %t56)
  call void @__free_recursive(ptr %t38)
  call void @__free_recursive(ptr %t19)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  store ptr %t56, ptr %t3
  store ptr %t37, ptr %t4
  br label %tco.loop.0
tco.case.default.42:
  unreachable
tco.case.default.23:
  unreachable
tco.case.default.12:
  unreachable
tco.exit.1:
  %t57 = load ptr, ptr %t2
  ret ptr %t57
}

define internal ptr @v_descendN(ptr %v_rounds, ptr %v_depth) {
entry:
  %t3 = alloca ptr
  store ptr %v_rounds, ptr %t3
  %t4 = alloca ptr
  store ptr %v_depth, ptr %t4
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
  call void @__inc_ref(ptr %t6)
  %t19 = call ptr @__alloc(i64 8, i32 0)
  %t20 = inttoptr i64 11 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = call ptr @v__cps_descend(ptr %t6, ptr %t19)
  %t23 = getelementptr ptr, ptr %t22, i32 0
  %t24 = load ptr, ptr %t23
  %t25 = ptrtoint ptr %t24 to i64
  switch i64 %t25, label %tco.case.default.26 [ i64 3, label %tco.case.arm.3.27 i64 4, label %tco.case.arm.4.34 ]
tco.case.arm.3.27:
  %t28 = getelementptr ptr, ptr %t22, i32 1
  %t29 = load ptr, ptr %t28
  call void @__inc_ref(ptr %t29)
  %t30 = call ptr @__alloc(i64 16, i32 1)
  %t31 = inttoptr i64 3 to ptr
  %t32 = getelementptr ptr, ptr %t30, i32 0
  store ptr %t31, ptr %t32
  call void @__inc_ref(ptr %t29)
  %t33 = getelementptr ptr, ptr %t30, i32 1
  store ptr %t29, ptr %t33
  call void @__free_recursive(ptr %t22)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t29)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t30, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.34:
  %t35 = getelementptr ptr, ptr %t22, i32 1
  %t36 = load ptr, ptr %t35
  call void @__inc_ref(ptr %t36)
  call void @__inc_ref(ptr %t5)
  %t37 = call ptr @__predInt32(ptr %t5)
  %t38 = getelementptr ptr, ptr %t37, i32 0
  %t39 = load ptr, ptr %t38
  %t40 = ptrtoint ptr %t39 to i64
  switch i64 %t40, label %tco.case.default.41 [ i64 3, label %tco.case.arm.3.42 i64 4, label %tco.case.arm.4.53 ]
tco.case.arm.3.42:
  %t43 = getelementptr ptr, ptr %t37, i32 1
  %t44 = load ptr, ptr %t43
  call void @__inc_ref(ptr %t44)
  %t45 = call ptr @__alloc(i64 16, i32 1)
  %t46 = inttoptr i64 3 to ptr
  %t47 = getelementptr ptr, ptr %t45, i32 0
  store ptr %t46, ptr %t47
  %t48 = call ptr @__alloc(i64 16, i32 1)
  %t49 = inttoptr i64 3768445577 to ptr
  %t50 = getelementptr ptr, ptr %t48, i32 0
  store ptr %t49, ptr %t50
  call void @__inc_ref(ptr %t44)
  %t51 = getelementptr ptr, ptr %t48, i32 1
  store ptr %t44, ptr %t51
  %t52 = getelementptr ptr, ptr %t45, i32 1
  store ptr %t48, ptr %t52
  call void @__free_recursive(ptr %t37)
  call void @__free_recursive(ptr %t22)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t44)
  call void @__free_recursive(ptr %t36)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t45, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.53:
  %t54 = getelementptr ptr, ptr %t37, i32 1
  %t55 = load ptr, ptr %t54
  call void @__inc_ref(ptr %t55)
  call void @__free_recursive(ptr %t37)
  call void @__free_recursive(ptr %t22)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  store ptr %t55, ptr %t3
  store ptr %t36, ptr %t4
  br label %tco.loop.0
tco.case.default.41:
  unreachable
tco.case.default.26:
  unreachable
tco.case.default.12:
  unreachable
tco.exit.1:
  %t56 = load ptr, ptr %t2
  ret ptr %t56
}

define internal ptr @v__cps_descend(ptr %v_n, ptr %v__k) {
entry:
  %t3 = alloca ptr
  store ptr %v_n, ptr %t3
  %t4 = alloca ptr
  store ptr %v__k, ptr %t4
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
  switch i64 %t11, label %tco.case.default.12 [ i64 1, label %tco.case.arm.1.13 i64 2, label %tco.case.arm.2.20 ]
tco.case.arm.1.13:
  call void @__inc_ref(ptr %t6)
  %t14 = call ptr @__alloc(i64 16, i32 1)
  %t15 = inttoptr i64 4 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  %t17 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t17
  %t18 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t17, ptr %t18
  %t19 = call ptr @v__apply_descend(ptr %t6, ptr %t14)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t19, ptr %t2
  br label %tco.exit.1
tco.case.arm.2.20:
  call void @__inc_ref(ptr %t5)
  %t21 = call ptr @__predInt32(ptr %t5)
  %t22 = getelementptr ptr, ptr %t21, i32 0
  %t23 = load ptr, ptr %t22
  %t24 = ptrtoint ptr %t23 to i64
  switch i64 %t24, label %tco.case.default.25 [ i64 3, label %tco.case.arm.3.26 i64 4, label %tco.case.arm.4.38 ]
tco.case.arm.3.26:
  %t27 = getelementptr ptr, ptr %t21, i32 1
  %t28 = load ptr, ptr %t27
  call void @__inc_ref(ptr %t28)
  call void @__inc_ref(ptr %t6)
  %t29 = call ptr @__alloc(i64 16, i32 1)
  %t30 = inttoptr i64 3 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = call ptr @__alloc(i64 16, i32 1)
  %t33 = inttoptr i64 3768445577 to ptr
  %t34 = getelementptr ptr, ptr %t32, i32 0
  store ptr %t33, ptr %t34
  call void @__inc_ref(ptr %t28)
  %t35 = getelementptr ptr, ptr %t32, i32 1
  store ptr %t28, ptr %t35
  %t36 = getelementptr ptr, ptr %t29, i32 1
  store ptr %t32, ptr %t36
  %t37 = call ptr @v__apply_descend(ptr %t6, ptr %t29)
  call void @__free_recursive(ptr %t21)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t28)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t37, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.38:
  %t39 = getelementptr ptr, ptr %t21, i32 1
  %t40 = load ptr, ptr %t39
  call void @__inc_ref(ptr %t40)
  %t41 = call ptr @__alloc(i64 16, i32 1)
  %t42 = inttoptr i64 12 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  call void @__inc_ref(ptr %t6)
  %t44 = getelementptr ptr, ptr %t41, i32 1
  store ptr %t6, ptr %t44
  call void @__free_recursive(ptr %t21)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  store ptr %t40, ptr %t3
  store ptr %t41, ptr %t4
  br label %tco.loop.0
tco.case.default.25:
  unreachable
tco.case.default.12:
  unreachable
tco.exit.1:
  %t45 = load ptr, ptr %t2
  ret ptr %t45
}

define internal ptr @v__apply_descend(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 11, label %tco.case.arm.11.11 i64 12, label %tco.case.arm.12.12 ]
tco.case.arm.11.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.12.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  %t15 = getelementptr ptr, ptr %t6, i32 0
  %t16 = load ptr, ptr %t15
  %t17 = ptrtoint ptr %t16 to i64
  switch i64 %t17, label %tco.case.default.18 [ i64 3, label %tco.case.arm.3.19 i64 4, label %tco.case.arm.4.20 ]
tco.case.arm.3.19:
  call void @__free_recursive(ptr %t5)
  store ptr %t14, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.4.20:
  %t21 = getelementptr ptr, ptr %t6, i32 1
  %t22 = load ptr, ptr %t21
  call void @__inc_ref(ptr %t22)
  %t23 = call ptr @__succInt32(ptr %t22)
  %t24 = getelementptr ptr, ptr %t23, i32 0
  %t25 = load ptr, ptr %t24
  %t26 = ptrtoint ptr %t25 to i64
  switch i64 %t26, label %case.default.27 [ i64 3, label %case.arm.3.29 i64 4, label %case.arm.4.42 ]
case.arm.3.29:
  %t31 = call ptr @__alloc(i64 16, i32 1)
  %t32 = inttoptr i64 882564211 to ptr
  %t33 = getelementptr ptr, ptr %t31, i32 0
  store ptr %t32, ptr %t33
  %t34 = getelementptr ptr, ptr %t23, i32 1
  %t35 = load ptr, ptr %t34
  call void @__inc_ref(ptr %t35)
  %t36 = getelementptr ptr, ptr %t31, i32 1
  store ptr %t35, ptr %t36
  %t37 = getelementptr ptr, ptr %t5, i32 1
  %t38 = load ptr, ptr %t37
  call void @__free_recursive(ptr %t38)
  %t40 = inttoptr i64 3 to ptr
  %t41 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t40, ptr %t41
  %t39 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t31, ptr %t39
  br label %case.end.3.30
case.end.3.30:
  br label %case.join.28
case.arm.4.42:
  call void @__free_recursive(ptr %t5)
  call void @__inc_ref(ptr %t23)
  br label %case.end.4.43
case.end.4.43:
  br label %case.join.28
case.default.27:
  unreachable
case.join.28:
  %t44 = phi ptr [ %t5, %case.end.3.30 ], [ %t23, %case.end.4.43 ]
  call void @__free_recursive(ptr %t23)
  call void @__free_recursive(ptr %t6)
  store ptr %t14, ptr %t3
  store ptr %t44, ptr %t4
  br label %tco.loop.0
tco.case.default.18:
  unreachable
tco.case.default.10:
  unreachable
tco.exit.1:
  %t45 = load ptr, ptr %t2
  ret ptr %t45
}

define internal ptr @v__scc_spinA_spinB_spinC(ptr %v__args) {
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
  switch i64 %t7, label %tco.case.default.8 [ i64 8, label %tco.case.arm.8.9 i64 9, label %tco.case.arm.9.72 i64 10, label %tco.case.arm.10.135 ]
tco.case.arm.8.9:
  %t10 = getelementptr ptr, ptr %t4, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  %t12 = getelementptr ptr, ptr %t4, i32 2
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t11)
  %t14 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t14
  %t15 = call ptr @__eqInt32(ptr %t11, ptr %t14)
  %t16 = getelementptr ptr, ptr %t15, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %tco.case.default.19 [ i64 1, label %tco.case.arm.1.20 i64 2, label %tco.case.arm.2.25 ]
tco.case.arm.1.20:
  %t21 = call ptr @__alloc(i64 16, i32 1)
  %t22 = inttoptr i64 4 to ptr
  %t23 = getelementptr ptr, ptr %t21, i32 0
  store ptr %t22, ptr %t23
  call void @__inc_ref(ptr %t13)
  %t24 = getelementptr ptr, ptr %t21, i32 1
  store ptr %t13, ptr %t24
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %t4)
  store ptr %t21, ptr %t2
  br label %tco.exit.1
tco.case.arm.2.25:
  call void @__inc_ref(ptr %t13)
  %t26 = call ptr @__succInt32(ptr %t13)
  %t27 = getelementptr ptr, ptr %t26, i32 0
  %t28 = load ptr, ptr %t27
  %t29 = ptrtoint ptr %t28 to i64
  switch i64 %t29, label %tco.case.default.30 [ i64 3, label %tco.case.arm.3.31 i64 4, label %tco.case.arm.4.42 ]
tco.case.arm.3.31:
  %t32 = getelementptr ptr, ptr %t26, i32 1
  %t33 = load ptr, ptr %t32
  call void @__inc_ref(ptr %t33)
  %t34 = call ptr @__alloc(i64 16, i32 1)
  %t35 = inttoptr i64 3 to ptr
  %t36 = getelementptr ptr, ptr %t34, i32 0
  store ptr %t35, ptr %t36
  %t37 = call ptr @__alloc(i64 16, i32 1)
  %t38 = inttoptr i64 882564211 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  call void @__inc_ref(ptr %t33)
  %t40 = getelementptr ptr, ptr %t37, i32 1
  store ptr %t33, ptr %t40
  %t41 = getelementptr ptr, ptr %t34, i32 1
  store ptr %t37, ptr %t41
  call void @__free_recursive(ptr %t26)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t33)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %t4)
  store ptr %t34, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.42:
  %t43 = getelementptr ptr, ptr %t26, i32 1
  %t44 = load ptr, ptr %t43
  call void @__inc_ref(ptr %t44)
  call void @__inc_ref(ptr %t11)
  %t45 = call ptr @__predInt32(ptr %t11)
  %t46 = getelementptr ptr, ptr %t45, i32 0
  %t47 = load ptr, ptr %t46
  %t48 = ptrtoint ptr %t47 to i64
  switch i64 %t48, label %tco.case.default.49 [ i64 3, label %tco.case.arm.3.50 i64 4, label %tco.case.arm.4.61 ]
tco.case.arm.3.50:
  %t51 = getelementptr ptr, ptr %t45, i32 1
  %t52 = load ptr, ptr %t51
  call void @__inc_ref(ptr %t52)
  %t53 = call ptr @__alloc(i64 16, i32 1)
  %t54 = inttoptr i64 3 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  %t56 = call ptr @__alloc(i64 16, i32 1)
  %t57 = inttoptr i64 3768445577 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  call void @__inc_ref(ptr %t52)
  %t59 = getelementptr ptr, ptr %t56, i32 1
  store ptr %t52, ptr %t59
  %t60 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t56, ptr %t60
  call void @__free_recursive(ptr %t45)
  call void @__free_recursive(ptr %t26)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t52)
  call void @__free_recursive(ptr %t44)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %t4)
  store ptr %t53, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.61:
  %t62 = getelementptr ptr, ptr %t45, i32 1
  %t63 = load ptr, ptr %t62
  call void @__inc_ref(ptr %t63)
  %t64 = getelementptr ptr, ptr %t4, i32 1
  %t65 = load ptr, ptr %t64
  call void @__free_recursive(ptr %t65)
  %t66 = getelementptr ptr, ptr %t4, i32 2
  %t67 = load ptr, ptr %t66
  call void @__free_recursive(ptr %t67)
  %t70 = inttoptr i64 9 to ptr
  %t71 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t70, ptr %t71
  call void @__inc_ref(ptr %t63)
  %t68 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t63, ptr %t68
  call void @__inc_ref(ptr %t44)
  %t69 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t44, ptr %t69
  call void @__free_recursive(ptr %t45)
  call void @__free_recursive(ptr %t26)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t63)
  call void @__free_recursive(ptr %t44)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.49:
  unreachable
tco.case.default.30:
  unreachable
tco.case.default.19:
  unreachable
tco.case.arm.9.72:
  %t73 = getelementptr ptr, ptr %t4, i32 1
  %t74 = load ptr, ptr %t73
  call void @__inc_ref(ptr %t74)
  %t75 = getelementptr ptr, ptr %t4, i32 2
  %t76 = load ptr, ptr %t75
  call void @__inc_ref(ptr %t76)
  call void @__inc_ref(ptr %t74)
  %t77 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t77
  %t78 = call ptr @__eqInt32(ptr %t74, ptr %t77)
  %t79 = getelementptr ptr, ptr %t78, i32 0
  %t80 = load ptr, ptr %t79
  %t81 = ptrtoint ptr %t80 to i64
  switch i64 %t81, label %tco.case.default.82 [ i64 1, label %tco.case.arm.1.83 i64 2, label %tco.case.arm.2.88 ]
tco.case.arm.1.83:
  %t84 = call ptr @__alloc(i64 16, i32 1)
  %t85 = inttoptr i64 4 to ptr
  %t86 = getelementptr ptr, ptr %t84, i32 0
  store ptr %t85, ptr %t86
  call void @__inc_ref(ptr %t76)
  %t87 = getelementptr ptr, ptr %t84, i32 1
  store ptr %t76, ptr %t87
  call void @__free_recursive(ptr %t78)
  call void @__free_recursive(ptr %t76)
  call void @__free_recursive(ptr %t74)
  call void @__free_recursive(ptr %t4)
  store ptr %t84, ptr %t2
  br label %tco.exit.1
tco.case.arm.2.88:
  call void @__inc_ref(ptr %t76)
  %t89 = call ptr @__succInt32(ptr %t76)
  %t90 = getelementptr ptr, ptr %t89, i32 0
  %t91 = load ptr, ptr %t90
  %t92 = ptrtoint ptr %t91 to i64
  switch i64 %t92, label %tco.case.default.93 [ i64 3, label %tco.case.arm.3.94 i64 4, label %tco.case.arm.4.105 ]
tco.case.arm.3.94:
  %t95 = getelementptr ptr, ptr %t89, i32 1
  %t96 = load ptr, ptr %t95
  call void @__inc_ref(ptr %t96)
  %t97 = call ptr @__alloc(i64 16, i32 1)
  %t98 = inttoptr i64 3 to ptr
  %t99 = getelementptr ptr, ptr %t97, i32 0
  store ptr %t98, ptr %t99
  %t100 = call ptr @__alloc(i64 16, i32 1)
  %t101 = inttoptr i64 882564211 to ptr
  %t102 = getelementptr ptr, ptr %t100, i32 0
  store ptr %t101, ptr %t102
  call void @__inc_ref(ptr %t96)
  %t103 = getelementptr ptr, ptr %t100, i32 1
  store ptr %t96, ptr %t103
  %t104 = getelementptr ptr, ptr %t97, i32 1
  store ptr %t100, ptr %t104
  call void @__free_recursive(ptr %t89)
  call void @__free_recursive(ptr %t78)
  call void @__free_recursive(ptr %t96)
  call void @__free_recursive(ptr %t76)
  call void @__free_recursive(ptr %t74)
  call void @__free_recursive(ptr %t4)
  store ptr %t97, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.105:
  %t106 = getelementptr ptr, ptr %t89, i32 1
  %t107 = load ptr, ptr %t106
  call void @__inc_ref(ptr %t107)
  call void @__inc_ref(ptr %t74)
  %t108 = call ptr @__predInt32(ptr %t74)
  %t109 = getelementptr ptr, ptr %t108, i32 0
  %t110 = load ptr, ptr %t109
  %t111 = ptrtoint ptr %t110 to i64
  switch i64 %t111, label %tco.case.default.112 [ i64 3, label %tco.case.arm.3.113 i64 4, label %tco.case.arm.4.124 ]
tco.case.arm.3.113:
  %t114 = getelementptr ptr, ptr %t108, i32 1
  %t115 = load ptr, ptr %t114
  call void @__inc_ref(ptr %t115)
  %t116 = call ptr @__alloc(i64 16, i32 1)
  %t117 = inttoptr i64 3 to ptr
  %t118 = getelementptr ptr, ptr %t116, i32 0
  store ptr %t117, ptr %t118
  %t119 = call ptr @__alloc(i64 16, i32 1)
  %t120 = inttoptr i64 3768445577 to ptr
  %t121 = getelementptr ptr, ptr %t119, i32 0
  store ptr %t120, ptr %t121
  call void @__inc_ref(ptr %t115)
  %t122 = getelementptr ptr, ptr %t119, i32 1
  store ptr %t115, ptr %t122
  %t123 = getelementptr ptr, ptr %t116, i32 1
  store ptr %t119, ptr %t123
  call void @__free_recursive(ptr %t108)
  call void @__free_recursive(ptr %t89)
  call void @__free_recursive(ptr %t78)
  call void @__free_recursive(ptr %t115)
  call void @__free_recursive(ptr %t107)
  call void @__free_recursive(ptr %t76)
  call void @__free_recursive(ptr %t74)
  call void @__free_recursive(ptr %t4)
  store ptr %t116, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.124:
  %t125 = getelementptr ptr, ptr %t108, i32 1
  %t126 = load ptr, ptr %t125
  call void @__inc_ref(ptr %t126)
  %t127 = getelementptr ptr, ptr %t4, i32 1
  %t128 = load ptr, ptr %t127
  call void @__free_recursive(ptr %t128)
  %t129 = getelementptr ptr, ptr %t4, i32 2
  %t130 = load ptr, ptr %t129
  call void @__free_recursive(ptr %t130)
  %t133 = inttoptr i64 10 to ptr
  %t134 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t133, ptr %t134
  call void @__inc_ref(ptr %t126)
  %t131 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t126, ptr %t131
  call void @__inc_ref(ptr %t107)
  %t132 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t107, ptr %t132
  call void @__free_recursive(ptr %t108)
  call void @__free_recursive(ptr %t89)
  call void @__free_recursive(ptr %t78)
  call void @__free_recursive(ptr %t126)
  call void @__free_recursive(ptr %t107)
  call void @__free_recursive(ptr %t76)
  call void @__free_recursive(ptr %t74)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.112:
  unreachable
tco.case.default.93:
  unreachable
tco.case.default.82:
  unreachable
tco.case.arm.10.135:
  %t136 = getelementptr ptr, ptr %t4, i32 1
  %t137 = load ptr, ptr %t136
  call void @__inc_ref(ptr %t137)
  %t138 = getelementptr ptr, ptr %t4, i32 2
  %t139 = load ptr, ptr %t138
  call void @__inc_ref(ptr %t139)
  call void @__inc_ref(ptr %t137)
  %t140 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t140
  %t141 = call ptr @__eqInt32(ptr %t137, ptr %t140)
  %t142 = getelementptr ptr, ptr %t141, i32 0
  %t143 = load ptr, ptr %t142
  %t144 = ptrtoint ptr %t143 to i64
  switch i64 %t144, label %tco.case.default.145 [ i64 1, label %tco.case.arm.1.146 i64 2, label %tco.case.arm.2.151 ]
tco.case.arm.1.146:
  %t147 = call ptr @__alloc(i64 16, i32 1)
  %t148 = inttoptr i64 4 to ptr
  %t149 = getelementptr ptr, ptr %t147, i32 0
  store ptr %t148, ptr %t149
  call void @__inc_ref(ptr %t139)
  %t150 = getelementptr ptr, ptr %t147, i32 1
  store ptr %t139, ptr %t150
  call void @__free_recursive(ptr %t141)
  call void @__free_recursive(ptr %t139)
  call void @__free_recursive(ptr %t137)
  call void @__free_recursive(ptr %t4)
  store ptr %t147, ptr %t2
  br label %tco.exit.1
tco.case.arm.2.151:
  call void @__inc_ref(ptr %t139)
  %t152 = call ptr @__succInt32(ptr %t139)
  %t153 = getelementptr ptr, ptr %t152, i32 0
  %t154 = load ptr, ptr %t153
  %t155 = ptrtoint ptr %t154 to i64
  switch i64 %t155, label %tco.case.default.156 [ i64 3, label %tco.case.arm.3.157 i64 4, label %tco.case.arm.4.168 ]
tco.case.arm.3.157:
  %t158 = getelementptr ptr, ptr %t152, i32 1
  %t159 = load ptr, ptr %t158
  call void @__inc_ref(ptr %t159)
  %t160 = call ptr @__alloc(i64 16, i32 1)
  %t161 = inttoptr i64 3 to ptr
  %t162 = getelementptr ptr, ptr %t160, i32 0
  store ptr %t161, ptr %t162
  %t163 = call ptr @__alloc(i64 16, i32 1)
  %t164 = inttoptr i64 882564211 to ptr
  %t165 = getelementptr ptr, ptr %t163, i32 0
  store ptr %t164, ptr %t165
  call void @__inc_ref(ptr %t159)
  %t166 = getelementptr ptr, ptr %t163, i32 1
  store ptr %t159, ptr %t166
  %t167 = getelementptr ptr, ptr %t160, i32 1
  store ptr %t163, ptr %t167
  call void @__free_recursive(ptr %t152)
  call void @__free_recursive(ptr %t141)
  call void @__free_recursive(ptr %t159)
  call void @__free_recursive(ptr %t139)
  call void @__free_recursive(ptr %t137)
  call void @__free_recursive(ptr %t4)
  store ptr %t160, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.168:
  %t169 = getelementptr ptr, ptr %t152, i32 1
  %t170 = load ptr, ptr %t169
  call void @__inc_ref(ptr %t170)
  call void @__inc_ref(ptr %t137)
  %t171 = call ptr @__predInt32(ptr %t137)
  %t172 = getelementptr ptr, ptr %t171, i32 0
  %t173 = load ptr, ptr %t172
  %t174 = ptrtoint ptr %t173 to i64
  switch i64 %t174, label %tco.case.default.175 [ i64 3, label %tco.case.arm.3.176 i64 4, label %tco.case.arm.4.187 ]
tco.case.arm.3.176:
  %t177 = getelementptr ptr, ptr %t171, i32 1
  %t178 = load ptr, ptr %t177
  call void @__inc_ref(ptr %t178)
  %t179 = call ptr @__alloc(i64 16, i32 1)
  %t180 = inttoptr i64 3 to ptr
  %t181 = getelementptr ptr, ptr %t179, i32 0
  store ptr %t180, ptr %t181
  %t182 = call ptr @__alloc(i64 16, i32 1)
  %t183 = inttoptr i64 3768445577 to ptr
  %t184 = getelementptr ptr, ptr %t182, i32 0
  store ptr %t183, ptr %t184
  call void @__inc_ref(ptr %t178)
  %t185 = getelementptr ptr, ptr %t182, i32 1
  store ptr %t178, ptr %t185
  %t186 = getelementptr ptr, ptr %t179, i32 1
  store ptr %t182, ptr %t186
  call void @__free_recursive(ptr %t171)
  call void @__free_recursive(ptr %t152)
  call void @__free_recursive(ptr %t141)
  call void @__free_recursive(ptr %t178)
  call void @__free_recursive(ptr %t170)
  call void @__free_recursive(ptr %t139)
  call void @__free_recursive(ptr %t137)
  call void @__free_recursive(ptr %t4)
  store ptr %t179, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.187:
  %t188 = getelementptr ptr, ptr %t171, i32 1
  %t189 = load ptr, ptr %t188
  call void @__inc_ref(ptr %t189)
  %t190 = getelementptr ptr, ptr %t4, i32 1
  %t191 = load ptr, ptr %t190
  call void @__free_recursive(ptr %t191)
  %t192 = getelementptr ptr, ptr %t4, i32 2
  %t193 = load ptr, ptr %t192
  call void @__free_recursive(ptr %t193)
  %t196 = inttoptr i64 8 to ptr
  %t197 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t196, ptr %t197
  call void @__inc_ref(ptr %t189)
  %t194 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t189, ptr %t194
  call void @__inc_ref(ptr %t170)
  %t195 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t170, ptr %t195
  call void @__free_recursive(ptr %t171)
  call void @__free_recursive(ptr %t152)
  call void @__free_recursive(ptr %t141)
  call void @__free_recursive(ptr %t189)
  call void @__free_recursive(ptr %t170)
  call void @__free_recursive(ptr %t139)
  call void @__free_recursive(ptr %t137)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.175:
  unreachable
tco.case.default.156:
  unreachable
tco.case.default.145:
  unreachable
tco.case.default.8:
  unreachable
tco.exit.1:
  %t198 = load ptr, ptr %t2
  ret ptr %t198
}

define i32 @main(i32 %argc, ptr %argv) {
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
