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
@.cli_arg = internal global ptr null

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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [14 x i8]} { i32 0, i32 0, i32 0, i32 14, i32 14, [14 x i8] c"UnderflowError" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"," }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [6 x i8]} { i32 0, i32 0, i32 0, i32 6, i32 6, [6 x i8] c"left: " }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [7 x i8]} { i32 0, i32 0, i32 0, i32 7, i32 7, [7 x i8] c"right: " }

define internal ptr @__concat(ptr %a, ptr %b) {
  %ba = load i32, ptr %a
  %ua_p = getelementptr i8, ptr %a, i64 4
  %ua = load i32, ptr %ua_p
  %bb = load i32, ptr %b
  %ub_p = getelementptr i8, ptr %b, i64 4
  %ub = load i32, ptr %ub_p
  %ua64 = zext i32 %ua to i64
  %ub64 = zext i32 %ub to i64
  %usum64 = add i64 %ua64, %ub64
  %over = icmp ugt i64 %usum64, 134217728
  br i1 %over, label %too_long, label %ok
too_long:
  %stl = call ptr @__alloc(i64 8, i32 0)
  %stl_tag = inttoptr i64 16 to ptr
  store ptr %stl_tag, ptr %stl
  %left = call ptr @__alloc(i64 16, i32 1)
  %left_tag = inttoptr i64 3 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %stl, ptr %left_f
  br label %join
ok:
  %ba64 = zext i32 %ba to i64
  %bb64 = zext i32 %bb to i64
  %bsum64 = add i64 %ba64, %bb64
  %alloc64 = add i64 %bsum64, 8
  %buf = call ptr @__alloc(i64 %alloc64, i32 0)
  %bsum32 = trunc i64 %bsum64 to i32
  store i32 %bsum32, ptr %buf
  %usum32 = trunc i64 %usum64 to i32
  %buf_u16p = getelementptr i8, ptr %buf, i64 4
  store i32 %usum32, ptr %buf_u16p
  %buf_payload = getelementptr i8, ptr %buf, i64 8
  %a_payload = getelementptr i8, ptr %a, i64 8
  call ptr @memcpy(ptr %buf_payload, ptr %a_payload, i64 %ba64)
  %buf_payload_b = getelementptr i8, ptr %buf_payload, i64 %ba64
  %b_payload = getelementptr i8, ptr %b, i64 8
  call ptr @memcpy(ptr %buf_payload_b, ptr %b_payload, i64 %bb64)
  %right = call ptr @__alloc(i64 16, i32 1)
  %right_tag = inttoptr i64 4 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %buf, ptr %right_f
  br label %join
join:
  %result = phi ptr [%left, %too_long], [%right, %ok]
  call void @__free_recursive(ptr %a)
  call void @__free_recursive(ptr %b)
  ret ptr %result
}


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


define internal ptr @__showUInt8(ptr %p) {
  %b = load i8, ptr %p
  %v = zext i8 %b to i32
  %buf = call ptr @__alloc(i64 24, i32 0)
  %payload = getelementptr i8, ptr %buf, i64 8
  %n = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %payload, i64 16, ptr @.fmt_u8, i32 %v)
  store i32 %n, ptr %buf
  %u16p = getelementptr i8, ptr %buf, i64 4
  store i32 %n, ptr %u16p
  call void @__free_recursive(ptr %p)
  ret ptr %buf
}


define internal ptr @__predUInt8(ptr %p) {
  %v = load i8, ptr %p
  %is_zero = icmp eq i8 %v, 0
  br i1 %is_zero, label %overflow, label %ok
overflow:
  %oe = call ptr @__alloc(i64 8, i32 0)
  %oe_tag = inttoptr i64 14 to ptr
  store ptr %oe_tag, ptr %oe
  %left = call ptr @__alloc(i64 16, i32 1)
  %left_tag = inttoptr i64 3 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %oe, ptr %left_f
  call void @__free_recursive(ptr %p)
  ret ptr %left
ok:
  %newv = sub i8 %v, 1
  %box = call ptr @__alloc(i64 1, i32 0)
  store i8 %newv, ptr %box
  %right = call ptr @__alloc(i64 16, i32 1)
  %right_tag = inttoptr i64 4 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %box, ptr %right_f
  call void @__free_recursive(ptr %p)
  ret ptr %right
}


define internal ptr @__eqUInt8(ptr %a, ptr %b) {
  %va = load i8, ptr %a
  %vb = load i8, ptr %b
  %eq = icmp eq i8 %va, %vb
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

define internal ptr @v_countDown(ptr %v_n) {
  call void @__inc_ref(ptr %v_n)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 17 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps_countDown(ptr %v_n, ptr %t0)
  call void @__free_recursive(ptr %v_n)
  ret ptr %t3
}

define internal ptr @v__cps_countDown(ptr %v_n, ptr %v__k) {
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
  %t7 = call ptr @__alloc(i64 1, i32 0)
  store i8 0, ptr %t7
  %t8 = call ptr @__eqUInt8(ptr %t5, ptr %t7)
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
  call void @__inc_ref(ptr %t5)
  %t17 = call ptr @__showUInt8(ptr %t5)
  %t18 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t17, ptr %t18
  %t19 = call ptr @v__apply_countDown(ptr %t6, ptr %t14)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t19, ptr %t2
  br label %tco.exit.1
tco.case.arm.2.20:
  call void @__inc_ref(ptr %t5)
  %t21 = call ptr @__predUInt8(ptr %t5)
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
  %t37 = call ptr @v__apply_countDown(ptr %t6, ptr %t29)
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
  %t41 = call ptr @__alloc(i64 24, i32 2)
  %t42 = inttoptr i64 18 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  call void @__inc_ref(ptr %t6)
  %t44 = getelementptr ptr, ptr %t41, i32 1
  store ptr %t6, ptr %t44
  call void @__inc_ref(ptr %t5)
  %t45 = getelementptr ptr, ptr %t41, i32 2
  store ptr %t5, ptr %t45
  call void @__inc_ref(ptr %t40)
  call void @__free_recursive(ptr %t21)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t40)
  store ptr %t40, ptr %t3
  store ptr %t41, ptr %t4
  br label %tco.loop.0
tco.case.default.25:
  unreachable
tco.case.default.12:
  unreachable
tco.exit.1:
  %t46 = load ptr, ptr %t2
  ret ptr %t46
}

define internal ptr @v__apply_countDown(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 17, label %tco.case.arm.17.11 i64 18, label %tco.case.arm.18.12 ]
tco.case.arm.17.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.18.12:
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
  call void @__inc_ref(ptr %t16)
  %t40 = call ptr @__showUInt8(ptr %t16)
  %t41 = call ptr @__concat(ptr %t40, ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  %t42 = getelementptr ptr, ptr %t41, i32 0
  %t43 = load ptr, ptr %t42
  %t44 = ptrtoint ptr %t43 to i64
  switch i64 %t44, label %tco.case.default.45 [ i64 3, label %tco.case.arm.3.46 i64 4, label %tco.case.arm.4.69 ]
tco.case.arm.3.46:
  %t47 = getelementptr ptr, ptr %t41, i32 1
  %t48 = load ptr, ptr %t47
  call void @__inc_ref(ptr %t48)
  %t49 = call ptr @__alloc(i64 16, i32 1)
  %t50 = inttoptr i64 589989748 to ptr
  %t51 = getelementptr ptr, ptr %t49, i32 0
  store ptr %t50, ptr %t51
  call void @__inc_ref(ptr %t48)
  %t52 = getelementptr ptr, ptr %t49, i32 1
  store ptr %t48, ptr %t52
  %t53 = getelementptr i8, ptr %t6, i64 -8
  %t54 = load i32, ptr %t53
  %t55 = icmp eq i32 %t54, 1
  br i1 %t55, label %reuse.in_place.56, label %reuse.copy.57
reuse.in_place.56:
  %t59 = getelementptr ptr, ptr %t6, i32 1
  %t60 = load ptr, ptr %t59
  call void @__free_recursive(ptr %t60)
  %t62 = inttoptr i64 3 to ptr
  %t63 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t62, ptr %t63
  %t61 = getelementptr ptr, ptr %t6, i32 1
  store ptr %t49, ptr %t61
  br label %reuse.join.58
reuse.copy.57:
  %t64 = call ptr @__alloc(i64 16, i32 1)
  %t65 = inttoptr i64 3 to ptr
  %t66 = getelementptr ptr, ptr %t64, i32 0
  store ptr %t65, ptr %t66
  %t67 = getelementptr ptr, ptr %t64, i32 1
  store ptr %t49, ptr %t67
  call void @__free_recursive(ptr %t6)
  br label %reuse.join.58
reuse.join.58:
  %t68 = phi ptr [ %t6, %reuse.in_place.56 ], [ %t64, %reuse.copy.57 ]
  call void @__inc_ref(ptr %t14)
  call void @__free_recursive(ptr %t41)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t48)
  call void @__free_recursive(ptr %t39)
  call void @__free_recursive(ptr %t16)
  call void @__free_recursive(ptr %t14)
  store ptr %t14, ptr %t3
  store ptr %t68, ptr %t4
  br label %tco.loop.0
tco.case.arm.4.69:
  %t70 = getelementptr ptr, ptr %t41, i32 1
  %t71 = load ptr, ptr %t70
  call void @__inc_ref(ptr %t71)
  call void @__inc_ref(ptr %t71)
  call void @__inc_ref(ptr %t39)
  %t72 = call ptr @__concat(ptr %t71, ptr %t39)
  call void @__inc_ref(ptr %t14)
  call void @__free_recursive(ptr %t41)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t71)
  call void @__free_recursive(ptr %t39)
  call void @__free_recursive(ptr %t16)
  call void @__free_recursive(ptr %t14)
  store ptr %t14, ptr %t3
  store ptr %t72, ptr %t4
  br label %tco.loop.0
tco.case.default.45:
  unreachable
tco.case.default.20:
  unreachable
tco.case.default.10:
  unreachable
tco.exit.1:
  %t73 = load ptr, ptr %t2
  ret ptr %t73
}

define internal ptr @v_showResult(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.28 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v_r, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = getelementptr ptr, ptr %t6, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %case.default.10 [ i64 589989748, label %case.arm.589989748.11 i64 3768445577, label %case.arm.3768445577.23 ]
case.arm.589989748.11:
  %t12 = getelementptr ptr, ptr %t6, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t13, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %case.default.17 [ i64 16, label %case.arm.16.18 ]
case.arm.16.18:
  %t19 = call ptr @__alloc(i64 16, i32 1)
  %t20 = inttoptr i64 4 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr ptr, ptr %t19, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t22
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_r)
  ret ptr %t19
case.default.17:
  unreachable
case.arm.3768445577.23:
  %t24 = getelementptr ptr, ptr %t6, i32 1
  %t25 = load ptr, ptr %t24
  call void @__inc_ref(ptr %t25)
  call void @__inc_ref(ptr %t25)
  %t26 = call ptr @v_showUnderflowError(ptr %t25)
  %t27 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t26)
  call void @__free_recursive(ptr %t25)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_r)
  ret ptr %t27
case.default.10:
  unreachable
case.arm.4.28:
  %t29 = getelementptr ptr, ptr %v_r, i32 1
  %t30 = load ptr, ptr %t29
  call void @__inc_ref(ptr %t30)
  call void @__inc_ref(ptr %t30)
  %t31 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t30)
  call void @__free_recursive(ptr %t30)
  call void @__free_recursive(ptr %v_r)
  ret ptr %t31
case.default.3:
  unreachable
}

define internal ptr @v_main() {
  %t0 = call ptr @__alloc(i64 1, i32 0)
  store i8 255, ptr %t0
  %t1 = call ptr @v_countDown(ptr %t0)
  %t2 = call ptr @v_showResult(ptr %t1)
  %t3 = call ptr @v__let_12(ptr %t2)
  ret ptr %t3
}

define internal ptr @v__let_12(ptr %v_res) {
  %t0 = getelementptr ptr, ptr %v_res, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.19 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v_res, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = call ptr @__alloc(i64 24, i32 2)
  %t8 = inttoptr i64 7 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = getelementptr ptr, ptr %t7, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t10
  %t11 = call ptr @__alloc(i64 16, i32 1)
  %t12 = inttoptr i64 5 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  %t14 = call ptr @__alloc(i64 8, i32 0)
  %t15 = inttoptr i64 0 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  %t17 = getelementptr ptr, ptr %t11, i32 1
  store ptr %t14, ptr %t17
  %t18 = getelementptr ptr, ptr %t7, i32 2
  store ptr %t11, ptr %t18
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_res)
  ret ptr %t7
case.arm.4.19:
  %t20 = getelementptr ptr, ptr %v_res, i32 1
  %t21 = load ptr, ptr %t20
  call void @__inc_ref(ptr %t21)
  %t22 = call ptr @__alloc(i64 24, i32 2)
  %t23 = inttoptr i64 7 to ptr
  %t24 = getelementptr ptr, ptr %t22, i32 0
  store ptr %t23, ptr %t24
  call void @__inc_ref(ptr %t21)
  %t25 = getelementptr ptr, ptr %t22, i32 1
  store ptr %t21, ptr %t25
  %t26 = call ptr @__alloc(i64 16, i32 1)
  %t27 = inttoptr i64 5 to ptr
  %t28 = getelementptr ptr, ptr %t26, i32 0
  store ptr %t27, ptr %t28
  %t29 = call ptr @__alloc(i64 8, i32 0)
  %t30 = inttoptr i64 0 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = getelementptr ptr, ptr %t26, i32 1
  store ptr %t29, ptr %t32
  %t33 = getelementptr ptr, ptr %t22, i32 2
  store ptr %t26, ptr %t33
  call void @__free_recursive(ptr %t21)
  call void @__free_recursive(ptr %v_res)
  ret ptr %t22
case.default.3:
  unreachable
}

define i32 @main(i32 %argc, ptr %argv) {
  %has_arg = icmp sgt i32 %argc, 1
  br i1 %has_arg, label %with_arg, label %no_arg
with_arg:
  %argptr = getelementptr ptr, ptr %argv, i64 1
  %arg = load ptr, ptr %argptr
  br label %call_main
no_arg:
  br label %call_main
call_main:
  %input = phi ptr [%arg, %with_arg], [getelementptr inbounds (i8, ptr @.empty, i64 12), %no_arg]
  store ptr %input, ptr @.cli_arg
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
