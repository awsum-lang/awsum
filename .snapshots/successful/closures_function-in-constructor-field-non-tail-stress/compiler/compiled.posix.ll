; External C declarations
declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare ptr @memcpy(ptr, ptr, i64)
declare i64 @strlen(ptr)
declare i64 @write(i32, ptr, i64)
declare i32 @printf(ptr, ...)
declare i32 @snprintf(ptr, i64, ptr, ...)

@.fmt_i32 = private unnamed_addr constant [3 x i8] c"%d\00"
@.fmt_u8 = private unnamed_addr constant [3 x i8] c"%u\00"
@.empty = private unnamed_addr constant {i32, i32, i32, i32, i32} { i32 0, i32 0, i32 0, i32 0, i32 0 }
@.cli_argc = internal global i64 0
@.cli_argv = internal global ptr null

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

define internal void @__free(ptr %p) {
  %hdr_ptr = getelementptr i8, ptr %p, i64 -12
  %flag = load i32, ptr %hdr_ptr
  %is_heap = icmp eq i32 %flag, 1
  br i1 %is_heap, label %do_free, label %skip
do_free:
  call void @free(ptr %hdr_ptr)
  br label %skip
skip:
  ret void
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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [9 x i8]} { i32 0, i32 0, i32 0, i32 9, i32 9, [9 x i8] c"underflow" }

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

define internal ptr @v_identity(ptr %v_n) {
  ret ptr %v_n
}

define internal ptr @v_countWithBox(ptr %v_b, ptr %v_n) {
  call void @__inc_ref(ptr %v_b)
  call void @__inc_ref(ptr %v_n)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 24 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps_countWithBox(ptr %v_b, ptr %v_n, ptr %t0)
  call void @__free_recursive(ptr %v_b)
  call void @__free_recursive(ptr %v_n)
  ret ptr %t3
}

define internal ptr @v__cps_countWithBox(ptr %v_b, ptr %v_n, ptr %v__k) {
entry:
  %t3 = alloca ptr
  store ptr %v_b, ptr %t3
  %t4 = alloca ptr
  store ptr %v_n, ptr %t4
  %t5 = alloca ptr
  store ptr %v__k, ptr %t5
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t6 = load ptr, ptr %t3
  %t7 = load ptr, ptr %t4
  %t8 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t7)
  %t9 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t9
  %t10 = call ptr @__eqInt32(ptr %t7, ptr %t9)
  %t11 = getelementptr ptr, ptr %t10, i32 0
  %t12 = load ptr, ptr %t11
  %t13 = ptrtoint ptr %t12 to i64
  switch i64 %t13, label %tco.case.default.14 [ i64 1, label %tco.case.arm.1.15 i64 2, label %tco.case.arm.2.22 ]
tco.case.arm.1.15:
  call void @__inc_ref(ptr %t8)
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 4 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t19
  %t20 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t19, ptr %t20
  %t21 = call ptr @v__apply_countWithBox(ptr %t8, ptr %t16)
  call void @__free_recursive(ptr %t10)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t7)
  call void @__free_recursive(ptr %t8)
  store ptr %t21, ptr %t2
  br label %tco.exit.1
tco.case.arm.2.22:
  call void @__inc_ref(ptr %t7)
  %t23 = call ptr @__predInt32(ptr %t7)
  %t24 = getelementptr ptr, ptr %t23, i32 0
  %t25 = load ptr, ptr %t24
  %t26 = ptrtoint ptr %t25 to i64
  switch i64 %t26, label %tco.case.default.27 [ i64 3, label %tco.case.arm.3.28 i64 4, label %tco.case.arm.4.36 ]
tco.case.arm.3.28:
  %t29 = getelementptr ptr, ptr %t23, i32 1
  %t30 = load ptr, ptr %t29
  call void @__inc_ref(ptr %t30)
  call void @__inc_ref(ptr %t8)
  %t31 = call ptr @__alloc(i64 16, i32 1)
  %t32 = inttoptr i64 3 to ptr
  %t33 = getelementptr ptr, ptr %t31, i32 0
  store ptr %t32, ptr %t33
  call void @__inc_ref(ptr %t30)
  %t34 = getelementptr ptr, ptr %t31, i32 1
  store ptr %t30, ptr %t34
  %t35 = call ptr @v__apply_countWithBox(ptr %t8, ptr %t31)
  call void @__free_recursive(ptr %t23)
  call void @__free_recursive(ptr %t10)
  call void @__free_recursive(ptr %t30)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t7)
  call void @__free_recursive(ptr %t8)
  store ptr %t35, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.36:
  %t37 = getelementptr ptr, ptr %t23, i32 1
  %t38 = load ptr, ptr %t37
  call void @__inc_ref(ptr %t38)
  %t39 = call ptr @__alloc(i64 24, i32 2)
  %t40 = inttoptr i64 25 to ptr
  %t41 = getelementptr ptr, ptr %t39, i32 0
  store ptr %t40, ptr %t41
  call void @__inc_ref(ptr %t8)
  %t42 = getelementptr ptr, ptr %t39, i32 1
  store ptr %t8, ptr %t42
  call void @__inc_ref(ptr %t6)
  %t43 = getelementptr ptr, ptr %t39, i32 2
  store ptr %t6, ptr %t43
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t38)
  call void @__free_recursive(ptr %t23)
  call void @__free_recursive(ptr %t10)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t7)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t38)
  store ptr %t6, ptr %t3
  store ptr %t38, ptr %t4
  store ptr %t39, ptr %t5
  br label %tco.loop.0
tco.case.default.27:
  unreachable
tco.case.default.14:
  unreachable
tco.exit.1:
  %t44 = load ptr, ptr %t2
  ret ptr %t44
}

define internal ptr @v__apply_countWithBox(ptr %v__k, ptr %v__x) {
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
  %t17 = getelementptr ptr, ptr %t6, i32 0
  %t18 = load ptr, ptr %t17
  %t19 = ptrtoint ptr %t18 to i64
  switch i64 %t19, label %tco.case.default.20 [ i64 3, label %tco.case.arm.3.21 i64 4, label %tco.case.arm.4.37 ]
tco.case.arm.3.21:
  %t22 = getelementptr ptr, ptr %t6, i32 1
  %t23 = load ptr, ptr %t22
  %t24 = getelementptr i8, ptr %t6, i64 -8
  %t25 = load i32, ptr %t24
  %t26 = icmp eq i32 %t25, 1
  br i1 %t26, label %reuse.in_place.27, label %reuse.copy.28
reuse.in_place.27:
  %t30 = inttoptr i64 3 to ptr
  %t31 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t30, ptr %t31
  br label %reuse.join.29
reuse.copy.28:
  %t32 = call ptr @__alloc(i64 16, i32 1)
  %t33 = inttoptr i64 3 to ptr
  %t34 = getelementptr ptr, ptr %t32, i32 0
  store ptr %t33, ptr %t34
  call void @__inc_ref(ptr %t23)
  %t35 = getelementptr ptr, ptr %t32, i32 1
  store ptr %t23, ptr %t35
  call void @__free_recursive(ptr %t6)
  br label %reuse.join.29
reuse.join.29:
  %t36 = phi ptr [ %t6, %reuse.in_place.27 ], [ %t32, %reuse.copy.28 ]
  call void @__inc_ref(ptr %t14)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t16)
  call void @__free_recursive(ptr %t14)
  store ptr %t14, ptr %t3
  store ptr %t36, ptr %t4
  br label %tco.loop.0
tco.case.arm.4.37:
  %t38 = getelementptr ptr, ptr %t6, i32 1
  %t39 = load ptr, ptr %t38
  call void @__inc_ref(ptr %t39)
  %t40 = getelementptr ptr, ptr %t16, i32 0
  %t41 = load ptr, ptr %t40
  %t42 = ptrtoint ptr %t41 to i64
  switch i64 %t42, label %tco.case.default.43 [ i64 22, label %tco.case.arm.22.44 ]
tco.case.arm.22.44:
  %t45 = getelementptr ptr, ptr %t16, i32 1
  %t46 = load ptr, ptr %t45
  call void @__inc_ref(ptr %t46)
  call void @__inc_ref(ptr %t46)
  call void @__inc_ref(ptr %t39)
  %t47 = call ptr @v__apply1(ptr %t46, ptr %t39)
  %t48 = getelementptr i8, ptr %t6, i64 -8
  %t49 = load i32, ptr %t48
  %t50 = icmp eq i32 %t49, 1
  br i1 %t50, label %reuse.in_place.51, label %reuse.copy.52
reuse.in_place.51:
  %t54 = getelementptr ptr, ptr %t6, i32 1
  %t55 = load ptr, ptr %t54
  call void @__free_recursive(ptr %t55)
  %t57 = inttoptr i64 4 to ptr
  %t58 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t57, ptr %t58
  %t56 = getelementptr ptr, ptr %t6, i32 1
  store ptr %t47, ptr %t56
  br label %reuse.join.53
reuse.copy.52:
  %t59 = call ptr @__alloc(i64 16, i32 1)
  %t60 = inttoptr i64 4 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  %t62 = getelementptr ptr, ptr %t59, i32 1
  store ptr %t47, ptr %t62
  call void @__free_recursive(ptr %t6)
  br label %reuse.join.53
reuse.join.53:
  %t63 = phi ptr [ %t6, %reuse.in_place.51 ], [ %t59, %reuse.copy.52 ]
  call void @__inc_ref(ptr %t14)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t46)
  call void @__free_recursive(ptr %t39)
  call void @__free_recursive(ptr %t16)
  call void @__free_recursive(ptr %t14)
  store ptr %t14, ptr %t3
  store ptr %t63, ptr %t4
  br label %tco.loop.0
tco.case.default.43:
  unreachable
tco.case.default.20:
  unreachable
tco.case.default.10:
  unreachable
tco.exit.1:
  %t64 = load ptr, ptr %t2
  ret ptr %t64
}

define internal ptr @v_main() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 22 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 8, i32 0)
  %t4 = inttoptr i64 23 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  %t7 = call ptr @__alloc(i64 4, i32 0)
  store i32 1000000, ptr %t7
  %t8 = call ptr @v_countWithBox(ptr %t0, ptr %t7)
  %t9 = getelementptr ptr, ptr %t8, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %case.default.12 [ i64 3, label %case.arm.3.14 i64 4, label %case.arm.4.30 ]
case.arm.3.14:
  %t16 = getelementptr ptr, ptr %t8, i32 1
  %t17 = load ptr, ptr %t16
  call void @__inc_ref(ptr %t17)
  %t18 = call ptr @__alloc(i64 24, i32 2)
  %t19 = inttoptr i64 7 to ptr
  %t20 = getelementptr ptr, ptr %t18, i32 0
  store ptr %t19, ptr %t20
  %t21 = getelementptr ptr, ptr %t18, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t21
  %t22 = call ptr @__alloc(i64 16, i32 1)
  %t23 = inttoptr i64 5 to ptr
  %t24 = getelementptr ptr, ptr %t22, i32 0
  store ptr %t23, ptr %t24
  %t25 = call ptr @__alloc(i64 8, i32 0)
  %t26 = inttoptr i64 0 to ptr
  %t27 = getelementptr ptr, ptr %t25, i32 0
  store ptr %t26, ptr %t27
  %t28 = getelementptr ptr, ptr %t22, i32 1
  store ptr %t25, ptr %t28
  %t29 = getelementptr ptr, ptr %t18, i32 2
  store ptr %t22, ptr %t29
  br label %case.end.3.15
case.end.3.15:
  br label %case.join.13
case.arm.4.30:
  %t32 = getelementptr ptr, ptr %t8, i32 1
  %t33 = load ptr, ptr %t32
  call void @__inc_ref(ptr %t33)
  %t34 = call ptr @__alloc(i64 24, i32 2)
  %t35 = inttoptr i64 7 to ptr
  %t36 = getelementptr ptr, ptr %t34, i32 0
  store ptr %t35, ptr %t36
  call void @__inc_ref(ptr %t33)
  %t37 = call ptr @__showInt32(ptr %t33)
  %t38 = getelementptr ptr, ptr %t34, i32 1
  store ptr %t37, ptr %t38
  %t39 = call ptr @__alloc(i64 16, i32 1)
  %t40 = inttoptr i64 5 to ptr
  %t41 = getelementptr ptr, ptr %t39, i32 0
  store ptr %t40, ptr %t41
  %t42 = call ptr @__alloc(i64 8, i32 0)
  %t43 = inttoptr i64 0 to ptr
  %t44 = getelementptr ptr, ptr %t42, i32 0
  store ptr %t43, ptr %t44
  %t45 = getelementptr ptr, ptr %t39, i32 1
  store ptr %t42, ptr %t45
  %t46 = getelementptr ptr, ptr %t34, i32 2
  store ptr %t39, ptr %t46
  br label %case.end.4.31
case.end.4.31:
  br label %case.join.13
case.default.12:
  unreachable
case.join.13:
  %t47 = phi ptr [%t18, %case.end.3.15], [%t34, %case.end.4.31]
  call void @__free_recursive(ptr %t8)
  ret ptr %t47
}

define internal ptr @v__apply1(ptr %v__cl, ptr %v__arg0) {
  %t0 = getelementptr ptr, ptr %v__cl, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 23, label %case.arm.23.4 ]
case.arm.23.4:
  call void @__inc_ref(ptr %v__arg0)
  %t5 = call ptr @v_identity(ptr %v__arg0)
  call void @__free_recursive(ptr %v__cl)
  call void @__free_recursive(ptr %v__arg0)
  ret ptr %t5
case.default.3:
  unreachable
}

define i32 @main(i32 %argc, ptr %argv) {
  %argc64 = sext i32 %argc to i64
  store i64 %argc64, ptr @.cli_argc
  store ptr %argv, ptr @.cli_argv
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
