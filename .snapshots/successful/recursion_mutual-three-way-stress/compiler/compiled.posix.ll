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

define internal ptr @v_main() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 18 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 4, i32 0)
  store i32 1000000, ptr %t3
  %t4 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t4
  %t5 = call ptr @v__scc_stepA_stepB_stepC(ptr %t0)
  %t6 = getelementptr ptr, ptr %t5, i32 0
  %t7 = load ptr, ptr %t6
  %t8 = ptrtoint ptr %t7 to i64
  switch i64 %t8, label %case.default.9 [ i64 3, label %case.arm.3.11 i64 4, label %case.arm.4.19 ]
case.arm.3.11:
  %t13 = call ptr @__alloc(i64 16, i32 1)
  %t14 = inttoptr i64 6 to ptr
  %t15 = getelementptr ptr, ptr %t13, i32 0
  store ptr %t14, ptr %t15
  %t16 = getelementptr ptr, ptr %t5, i32 1
  %t17 = load ptr, ptr %t16
  call void @__inc_ref(ptr %t17)
  %t18 = getelementptr ptr, ptr %t13, i32 1
  store ptr %t17, ptr %t18
  br label %case.end.3.12
case.end.3.12:
  br label %case.join.10
case.arm.4.19:
  %t21 = call ptr @__alloc(i64 16, i32 1)
  %t22 = inttoptr i64 5 to ptr
  %t23 = getelementptr ptr, ptr %t21, i32 0
  store ptr %t22, ptr %t23
  %t24 = getelementptr ptr, ptr %t5, i32 1
  %t25 = load ptr, ptr %t24
  call void @__inc_ref(ptr %t25)
  %t26 = getelementptr ptr, ptr %t21, i32 1
  store ptr %t25, ptr %t26
  br label %case.end.4.20
case.end.4.20:
  br label %case.join.10
case.default.9:
  unreachable
case.join.10:
  %t27 = phi ptr [ %t13, %case.end.3.12 ], [ %t21, %case.end.4.20 ]
  call void @__free_recursive(ptr %t5)
  %t28 = call ptr @__alloc(i64 8, i32 0)
  %t29 = inttoptr i64 23 to ptr
  %t30 = getelementptr ptr, ptr %t28, i32 0
  store ptr %t29, ptr %t30
  %t31 = call ptr @v__cps__df_andThenIO_4(ptr %t27, ptr %t28)
  %t32 = call ptr @__alloc(i64 8, i32 0)
  %t33 = inttoptr i64 21 to ptr
  %t34 = getelementptr ptr, ptr %t32, i32 0
  store ptr %t33, ptr %t34
  %t35 = call ptr @v__cps__df_handleErrorIO_0(ptr %t31, ptr %t32)
  ret ptr %t35
}

define internal ptr @v__cps__df_handleErrorIO_0(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.13 i64 7, label %tco.case.arm.7.27 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t12 = call ptr @v__apply__df_handleErrorIO_0(ptr %t6, ptr %t5)
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
  %t26 = call ptr @v__apply__df_handleErrorIO_0(ptr %t6, ptr %t14)
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
  %t36 = inttoptr i64 22 to ptr
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
  %t47 = inttoptr i64 22 to ptr
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

define internal ptr @v__apply__df_handleErrorIO_0(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 21, label %tco.case.arm.21.11 i64 22, label %tco.case.arm.22.12 ]
tco.case.arm.21.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.22.12:
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

define internal ptr @v__cps__df_andThenIO_4(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.28 i64 7, label %tco.case.arm.7.30 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t5, i32 1
  %t16 = load ptr, ptr %t15
  call void @__inc_ref(ptr %t16)
  %t17 = call ptr @__showInt32(ptr %t16)
  %t18 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t17, ptr %t18
  %t19 = call ptr @__alloc(i64 16, i32 1)
  %t20 = inttoptr i64 5 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = call ptr @__alloc(i64 8, i32 0)
  %t23 = inttoptr i64 0 to ptr
  %t24 = getelementptr ptr, ptr %t22, i32 0
  store ptr %t23, ptr %t24
  %t25 = getelementptr ptr, ptr %t19, i32 1
  store ptr %t22, ptr %t25
  %t26 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t19, ptr %t26
  %t27 = call ptr @v__apply__df_andThenIO_4(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t27, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.28:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t29 = call ptr @v__apply__df_andThenIO_4(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t29, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.30:
  %t31 = getelementptr ptr, ptr %t5, i32 1
  %t32 = load ptr, ptr %t31
  %t33 = getelementptr ptr, ptr %t5, i32 2
  %t34 = load ptr, ptr %t33
  call void @__inc_ref(ptr %t34)
  %t41 = getelementptr i8, ptr %t5, i64 -8
  %t42 = load i32, ptr %t41
  %t43 = icmp eq i32 %t42, 1
  br i1 %t43, label %reuse.in_place.44, label %reuse.copy.45
reuse.in_place.44:
  %t35 = getelementptr ptr, ptr %t5, i32 2
  %t36 = load ptr, ptr %t35
  call void @__free_recursive(ptr %t36)
  %t39 = inttoptr i64 24 to ptr
  %t40 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t39, ptr %t40
  call void @__inc_ref(ptr %t6)
  %t37 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t37
  %t38 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t32, ptr %t38
  br label %reuse.in_place.end.47
reuse.in_place.end.47:
  br label %reuse.join.46
reuse.copy.45:
  %t49 = call ptr @__alloc(i64 24, i32 2)
  %t50 = inttoptr i64 24 to ptr
  %t51 = getelementptr ptr, ptr %t49, i32 0
  store ptr %t50, ptr %t51
  call void @__inc_ref(ptr %t6)
  %t52 = getelementptr ptr, ptr %t49, i32 1
  store ptr %t6, ptr %t52
  call void @__inc_ref(ptr %t32)
  %t53 = getelementptr ptr, ptr %t49, i32 2
  store ptr %t32, ptr %t53
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.48
reuse.copy.end.48:
  br label %reuse.join.46
reuse.join.46:
  %t54 = phi ptr [ %t5, %reuse.in_place.end.47 ], [ %t49, %reuse.copy.end.48 ]
  call void @__free_recursive(ptr %t6)
  store ptr %t34, ptr %t3
  store ptr %t54, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t55 = load ptr, ptr %t2
  ret ptr %t55
}

define internal ptr @v__apply__df_andThenIO_4(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 23, label %tco.case.arm.23.11 i64 24, label %tco.case.arm.24.12 ]
tco.case.arm.23.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.24.12:
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

define internal ptr @v__scc_stepA_stepB_stepC(ptr %v__args) {
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
  switch i64 %t7, label %tco.case.default.8 [ i64 18, label %tco.case.arm.18.9 i64 19, label %tco.case.arm.19.45 i64 20, label %tco.case.arm.20.81 ]
tco.case.arm.18.9:
  %t10 = getelementptr ptr, ptr %t4, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  call void @__inc_ref(ptr %t11)
  %t12 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t12
  %t13 = call ptr @__eqInt32(ptr %t11, ptr %t12)
  %t14 = getelementptr ptr, ptr %t13, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %tco.case.default.17 [ i64 1, label %tco.case.arm.1.18 i64 2, label %tco.case.arm.2.24 ]
tco.case.arm.1.18:
  %t19 = call ptr @__alloc(i64 16, i32 1)
  %t20 = inttoptr i64 4 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t22
  %t23 = getelementptr ptr, ptr %t19, i32 1
  store ptr %t22, ptr %t23
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %t4)
  store ptr %t19, ptr %t2
  br label %tco.exit.1
tco.case.arm.2.24:
  call void @__inc_ref(ptr %t11)
  %t25 = call ptr @__predInt32(ptr %t11)
  %t26 = getelementptr ptr, ptr %t25, i32 0
  %t27 = load ptr, ptr %t26
  %t28 = ptrtoint ptr %t27 to i64
  switch i64 %t28, label %tco.case.default.29 [ i64 3, label %tco.case.arm.3.30 i64 4, label %tco.case.arm.4.37 ]
tco.case.arm.3.30:
  %t31 = getelementptr ptr, ptr %t25, i32 1
  %t32 = load ptr, ptr %t31
  call void @__inc_ref(ptr %t32)
  %t33 = call ptr @__alloc(i64 16, i32 1)
  %t34 = inttoptr i64 3 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  call void @__inc_ref(ptr %t32)
  %t36 = getelementptr ptr, ptr %t33, i32 1
  store ptr %t32, ptr %t36
  call void @__free_recursive(ptr %t25)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t32)
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %t4)
  store ptr %t33, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.37:
  %t38 = getelementptr ptr, ptr %t25, i32 1
  %t39 = load ptr, ptr %t38
  call void @__inc_ref(ptr %t39)
  %t40 = getelementptr ptr, ptr %t4, i32 1
  %t41 = load ptr, ptr %t40
  call void @__free_recursive(ptr %t41)
  %t43 = inttoptr i64 19 to ptr
  %t44 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t43, ptr %t44
  call void @__inc_ref(ptr %t39)
  %t42 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t39, ptr %t42
  call void @__free_recursive(ptr %t25)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t39)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.29:
  unreachable
tco.case.default.17:
  unreachable
tco.case.arm.19.45:
  %t46 = getelementptr ptr, ptr %t4, i32 1
  %t47 = load ptr, ptr %t46
  call void @__inc_ref(ptr %t47)
  call void @__inc_ref(ptr %t47)
  %t48 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t48
  %t49 = call ptr @__eqInt32(ptr %t47, ptr %t48)
  %t50 = getelementptr ptr, ptr %t49, i32 0
  %t51 = load ptr, ptr %t50
  %t52 = ptrtoint ptr %t51 to i64
  switch i64 %t52, label %tco.case.default.53 [ i64 1, label %tco.case.arm.1.54 i64 2, label %tco.case.arm.2.60 ]
tco.case.arm.1.54:
  %t55 = call ptr @__alloc(i64 16, i32 1)
  %t56 = inttoptr i64 4 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  %t58 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t58
  %t59 = getelementptr ptr, ptr %t55, i32 1
  store ptr %t58, ptr %t59
  call void @__free_recursive(ptr %t49)
  call void @__free_recursive(ptr %t47)
  call void @__free_recursive(ptr %t4)
  store ptr %t55, ptr %t2
  br label %tco.exit.1
tco.case.arm.2.60:
  call void @__inc_ref(ptr %t47)
  %t61 = call ptr @__predInt32(ptr %t47)
  %t62 = getelementptr ptr, ptr %t61, i32 0
  %t63 = load ptr, ptr %t62
  %t64 = ptrtoint ptr %t63 to i64
  switch i64 %t64, label %tco.case.default.65 [ i64 3, label %tco.case.arm.3.66 i64 4, label %tco.case.arm.4.73 ]
tco.case.arm.3.66:
  %t67 = getelementptr ptr, ptr %t61, i32 1
  %t68 = load ptr, ptr %t67
  call void @__inc_ref(ptr %t68)
  %t69 = call ptr @__alloc(i64 16, i32 1)
  %t70 = inttoptr i64 3 to ptr
  %t71 = getelementptr ptr, ptr %t69, i32 0
  store ptr %t70, ptr %t71
  call void @__inc_ref(ptr %t68)
  %t72 = getelementptr ptr, ptr %t69, i32 1
  store ptr %t68, ptr %t72
  call void @__free_recursive(ptr %t61)
  call void @__free_recursive(ptr %t49)
  call void @__free_recursive(ptr %t68)
  call void @__free_recursive(ptr %t47)
  call void @__free_recursive(ptr %t4)
  store ptr %t69, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.73:
  %t74 = getelementptr ptr, ptr %t61, i32 1
  %t75 = load ptr, ptr %t74
  call void @__inc_ref(ptr %t75)
  %t76 = getelementptr ptr, ptr %t4, i32 1
  %t77 = load ptr, ptr %t76
  call void @__free_recursive(ptr %t77)
  %t79 = inttoptr i64 20 to ptr
  %t80 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t79, ptr %t80
  call void @__inc_ref(ptr %t75)
  %t78 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t75, ptr %t78
  call void @__free_recursive(ptr %t61)
  call void @__free_recursive(ptr %t49)
  call void @__free_recursive(ptr %t75)
  call void @__free_recursive(ptr %t47)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.65:
  unreachable
tco.case.default.53:
  unreachable
tco.case.arm.20.81:
  %t82 = getelementptr ptr, ptr %t4, i32 1
  %t83 = load ptr, ptr %t82
  call void @__inc_ref(ptr %t83)
  call void @__inc_ref(ptr %t83)
  %t84 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t84
  %t85 = call ptr @__eqInt32(ptr %t83, ptr %t84)
  %t86 = getelementptr ptr, ptr %t85, i32 0
  %t87 = load ptr, ptr %t86
  %t88 = ptrtoint ptr %t87 to i64
  switch i64 %t88, label %tco.case.default.89 [ i64 1, label %tco.case.arm.1.90 i64 2, label %tco.case.arm.2.96 ]
tco.case.arm.1.90:
  %t91 = call ptr @__alloc(i64 16, i32 1)
  %t92 = inttoptr i64 4 to ptr
  %t93 = getelementptr ptr, ptr %t91, i32 0
  store ptr %t92, ptr %t93
  %t94 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t94
  %t95 = getelementptr ptr, ptr %t91, i32 1
  store ptr %t94, ptr %t95
  call void @__free_recursive(ptr %t85)
  call void @__free_recursive(ptr %t83)
  call void @__free_recursive(ptr %t4)
  store ptr %t91, ptr %t2
  br label %tco.exit.1
tco.case.arm.2.96:
  call void @__inc_ref(ptr %t83)
  %t97 = call ptr @__predInt32(ptr %t83)
  %t98 = getelementptr ptr, ptr %t97, i32 0
  %t99 = load ptr, ptr %t98
  %t100 = ptrtoint ptr %t99 to i64
  switch i64 %t100, label %tco.case.default.101 [ i64 3, label %tco.case.arm.3.102 i64 4, label %tco.case.arm.4.109 ]
tco.case.arm.3.102:
  %t103 = getelementptr ptr, ptr %t97, i32 1
  %t104 = load ptr, ptr %t103
  call void @__inc_ref(ptr %t104)
  %t105 = call ptr @__alloc(i64 16, i32 1)
  %t106 = inttoptr i64 3 to ptr
  %t107 = getelementptr ptr, ptr %t105, i32 0
  store ptr %t106, ptr %t107
  call void @__inc_ref(ptr %t104)
  %t108 = getelementptr ptr, ptr %t105, i32 1
  store ptr %t104, ptr %t108
  call void @__free_recursive(ptr %t97)
  call void @__free_recursive(ptr %t85)
  call void @__free_recursive(ptr %t104)
  call void @__free_recursive(ptr %t83)
  call void @__free_recursive(ptr %t4)
  store ptr %t105, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.109:
  %t110 = getelementptr ptr, ptr %t97, i32 1
  %t111 = load ptr, ptr %t110
  call void @__inc_ref(ptr %t111)
  %t112 = getelementptr ptr, ptr %t4, i32 1
  %t113 = load ptr, ptr %t112
  call void @__free_recursive(ptr %t113)
  %t115 = inttoptr i64 18 to ptr
  %t116 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t115, ptr %t116
  call void @__inc_ref(ptr %t111)
  %t114 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t111, ptr %t114
  call void @__free_recursive(ptr %t97)
  call void @__free_recursive(ptr %t85)
  call void @__free_recursive(ptr %t111)
  call void @__free_recursive(ptr %t83)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.101:
  unreachable
tco.case.default.89:
  unreachable
tco.case.default.8:
  unreachable
tco.exit.1:
  %t117 = load ptr, ptr %t2
  ret ptr %t117
}

define i32 @main(i32 %argc, ptr %argv) {
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
