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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [12 x i8]} { i32 0, i32 0, i32 0, i32 12, i32 12, [12 x i8] c"Left Missing" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [6 x i8]} { i32 0, i32 0, i32 0, i32 6, i32 6, [6 x i8] c"Right " }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"|" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"first" }
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [6 x i8]} { i32 0, i32 0, i32 0, i32 6, i32 6, [6 x i8] c"second" }
@.str.6 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"hi" }

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
  %stl_tag = inttoptr i64 19 to ptr
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
  %result = phi ptr [ %left, %too_long ], [ %right, %ok ]
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


define internal ptr @v_pureEither(ptr %v_x) {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 4 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  call void @__inc_ref(ptr %v_x)
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v_x, ptr %t3
  call void @__free_recursive(ptr %v_x)
  ret ptr %t0
}

define internal ptr @v_nothingAsLeft(ptr %v_e, ptr %v_m) {
  %t0 = getelementptr ptr, ptr %v_m, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 11, label %case.arm.11.4 i64 12, label %case.arm.12.9 ]
case.arm.11.4:
  %t5 = call ptr @__alloc(i64 16, i32 1)
  %t6 = inttoptr i64 3 to ptr
  %t7 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t6, ptr %t7
  call void @__inc_ref(ptr %v_e)
  %t8 = getelementptr ptr, ptr %t5, i32 1
  store ptr %v_e, ptr %t8
  call void @__free_recursive(ptr %v_e)
  call void @__free_recursive(ptr %v_m)
  ret ptr %t5
case.arm.12.9:
  %t10 = getelementptr ptr, ptr %v_m, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  %t12 = call ptr @__alloc(i64 16, i32 1)
  %t13 = inttoptr i64 4 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  call void @__inc_ref(ptr %t11)
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t11, ptr %t15
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %v_e)
  call void @__free_recursive(ptr %v_m)
  ret ptr %t12
case.default.3:
  unreachable
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

define internal ptr @v_headList(ptr %v_xs) {
  %t0 = getelementptr ptr, ptr %v_xs, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 13, label %case.arm.13.4 i64 14, label %case.arm.14.8 ]
case.arm.13.4:
  %t5 = call ptr @__alloc(i64 8, i32 0)
  %t6 = inttoptr i64 11 to ptr
  %t7 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t6, ptr %t7
  call void @__free_recursive(ptr %v_xs)
  ret ptr %t5
case.arm.14.8:
  %t9 = getelementptr ptr, ptr %v_xs, i32 1
  %t10 = load ptr, ptr %t9
  call void @__inc_ref(ptr %t10)
  %t11 = getelementptr ptr, ptr %v_xs, i32 2
  %t12 = load ptr, ptr %t11
  call void @__inc_ref(ptr %t12)
  %t13 = call ptr @__alloc(i64 16, i32 1)
  %t14 = inttoptr i64 12 to ptr
  %t15 = getelementptr ptr, ptr %t13, i32 0
  store ptr %t14, ptr %t15
  call void @__inc_ref(ptr %t10)
  %t16 = getelementptr ptr, ptr %t13, i32 1
  store ptr %t10, ptr %t16
  call void @__free_recursive(ptr %t12)
  call void @__free_recursive(ptr %t10)
  call void @__free_recursive(ptr %v_xs)
  ret ptr %t13
case.default.3:
  unreachable
}

define internal ptr @v_show(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.16 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v_r, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = getelementptr ptr, ptr %t6, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %case.default.10 [ i64 24, label %case.arm.24.11 ]
case.arm.24.11:
  %t12 = call ptr @__alloc(i64 16, i32 1)
  %t13 = inttoptr i64 4 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t15
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_r)
  ret ptr %t12
case.default.10:
  unreachable
case.arm.4.16:
  %t17 = getelementptr ptr, ptr %v_r, i32 1
  %t18 = load ptr, ptr %t17
  call void @__inc_ref(ptr %t18)
  call void @__inc_ref(ptr %t18)
  %t19 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t18)
  call void @__free_recursive(ptr %t18)
  call void @__free_recursive(ptr %v_r)
  ret ptr %t19
case.default.3:
  unreachable
}

define internal ptr @v_main() {
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 24 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 8, i32 0)
  %t4 = inttoptr i64 11 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = call ptr @v__lift_28(ptr %t3)
  %t7 = call ptr @v_nothingAsLeft(ptr %t0, ptr %t6)
  %t8 = call ptr @v__let_29(ptr %t7)
  ret ptr %t8
}

define internal ptr @v__let_23(ptr %v_msg) {
  %t0 = getelementptr ptr, ptr %v_msg, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.19 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v_msg, i32 1
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
  call void @__free_recursive(ptr %v_msg)
  ret ptr %t7
case.arm.4.19:
  %t20 = getelementptr ptr, ptr %v_msg, i32 1
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
  call void @__free_recursive(ptr %v_msg)
  ret ptr %t22
case.default.3:
  unreachable
}

define internal ptr @v__lift_24(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 25 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__lift_24(ptr %v___input, ptr %t0)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t3
}

define internal ptr @v__cps__lift_24(ptr %v___input, ptr %v__k) {
entry:
  %t3 = alloca ptr
  store ptr %v___input, ptr %t3
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
  switch i64 %t9, label %tco.case.default.10 [ i64 13, label %tco.case.arm.13.11 i64 14, label %tco.case.arm.14.16 ]
tco.case.arm.13.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 8, i32 0)
  %t13 = inttoptr i64 13 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = call ptr @v__apply__lift_24(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t15, ptr %t2
  br label %tco.exit.1
tco.case.arm.14.16:
  %t17 = getelementptr ptr, ptr %t5, i32 1
  %t18 = load ptr, ptr %t17
  %t19 = getelementptr ptr, ptr %t5, i32 2
  %t20 = load ptr, ptr %t19
  call void @__inc_ref(ptr %t20)
  %t21 = getelementptr i8, ptr %t5, i64 -8
  %t22 = load i32, ptr %t21
  %t23 = icmp eq i32 %t22, 1
  br i1 %t23, label %reuse.in_place.24, label %reuse.copy.25
reuse.in_place.24:
  %t27 = getelementptr ptr, ptr %t5, i32 2
  %t28 = load ptr, ptr %t27
  call void @__free_recursive(ptr %t28)
  %t31 = inttoptr i64 26 to ptr
  %t32 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t31, ptr %t32
  call void @__inc_ref(ptr %t6)
  %t29 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t29
  %t30 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t18, ptr %t30
  br label %reuse.join.26
reuse.copy.25:
  %t33 = call ptr @__alloc(i64 24, i32 2)
  %t34 = inttoptr i64 26 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  call void @__inc_ref(ptr %t6)
  %t36 = getelementptr ptr, ptr %t33, i32 1
  store ptr %t6, ptr %t36
  call void @__inc_ref(ptr %t18)
  %t37 = getelementptr ptr, ptr %t33, i32 2
  store ptr %t18, ptr %t37
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.26
reuse.join.26:
  %t38 = phi ptr [ %t5, %reuse.in_place.24 ], [ %t33, %reuse.copy.25 ]
  call void @__inc_ref(ptr %t20)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t20)
  store ptr %t20, ptr %t3
  store ptr %t38, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t39 = load ptr, ptr %t2
  ret ptr %t39
}

define internal ptr @v__apply__lift_24(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 25, label %tco.case.arm.25.11 i64 26, label %tco.case.arm.26.12 ]
tco.case.arm.25.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.26.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  %t15 = getelementptr ptr, ptr %t5, i32 2
  %t16 = load ptr, ptr %t15
  %t17 = getelementptr i8, ptr %t5, i64 -8
  %t18 = load i32, ptr %t17
  %t19 = icmp eq i32 %t18, 1
  br i1 %t19, label %reuse.in_place.20, label %reuse.copy.21
reuse.in_place.20:
  %t23 = getelementptr ptr, ptr %t5, i32 1
  %t24 = load ptr, ptr %t23
  call void @__free_recursive(ptr %t24)
  %t27 = inttoptr i64 14 to ptr
  %t28 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t27, ptr %t28
  %t25 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t16, ptr %t25
  call void @__inc_ref(ptr %t6)
  %t26 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t6, ptr %t26
  br label %reuse.join.22
reuse.copy.21:
  %t29 = call ptr @__alloc(i64 24, i32 2)
  %t30 = inttoptr i64 14 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  call void @__inc_ref(ptr %t16)
  %t32 = getelementptr ptr, ptr %t29, i32 1
  store ptr %t16, ptr %t32
  call void @__inc_ref(ptr %t6)
  %t33 = getelementptr ptr, ptr %t29, i32 2
  store ptr %t6, ptr %t33
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.22
reuse.join.22:
  %t34 = phi ptr [ %t5, %reuse.in_place.20 ], [ %t29, %reuse.copy.21 ]
  call void @__inc_ref(ptr %t14)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t14)
  store ptr %t14, ptr %t3
  store ptr %t34, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t35 = load ptr, ptr %t2
  ret ptr %t35
}

define internal ptr @v__lift_25(ptr %v___input) {
  %t0 = getelementptr ptr, ptr %v___input, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 11, label %case.arm.11.4 i64 12, label %case.arm.12.8 ]
case.arm.11.4:
  %t5 = call ptr @__alloc(i64 8, i32 0)
  %t6 = inttoptr i64 11 to ptr
  %t7 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t6, ptr %t7
  call void @__free_recursive(ptr %v___input)
  ret ptr %t5
case.arm.12.8:
  %t9 = getelementptr ptr, ptr %v___input, i32 1
  %t10 = load ptr, ptr %t9
  call void @__inc_ref(ptr %t10)
  %t11 = call ptr @__alloc(i64 16, i32 1)
  %t12 = inttoptr i64 12 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  call void @__inc_ref(ptr %t10)
  %t14 = getelementptr ptr, ptr %t11, i32 1
  store ptr %t10, ptr %t14
  call void @__free_recursive(ptr %t10)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t11
case.default.3:
  unreachable
}

define internal ptr @v__let_26(ptr %v_fromJust, ptr %v_fromNothing, ptr %v_chained) {
  call void @__inc_ref(ptr %v_fromNothing)
  %t0 = call ptr @v_show(ptr %v_fromNothing)
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 3, label %case.arm.3.6 i64 4, label %case.arm.4.14 ]
case.arm.3.6:
  %t8 = getelementptr ptr, ptr %t0, i32 1
  %t9 = load ptr, ptr %t8
  call void @__inc_ref(ptr %t9)
  %t10 = call ptr @__alloc(i64 16, i32 1)
  %t11 = inttoptr i64 3 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  call void @__inc_ref(ptr %t9)
  %t13 = getelementptr ptr, ptr %t10, i32 1
  store ptr %t9, ptr %t13
  call void @__free_recursive(ptr %t9)
  br label %case.end.3.7
case.end.3.7:
  br label %case.join.5
case.arm.4.14:
  %t16 = getelementptr ptr, ptr %t0, i32 1
  %t17 = load ptr, ptr %t16
  call void @__inc_ref(ptr %t17)
  call void @__inc_ref(ptr %v_fromJust)
  %t18 = call ptr @v_show(ptr %v_fromJust)
  %t19 = getelementptr ptr, ptr %t18, i32 0
  %t20 = load ptr, ptr %t19
  %t21 = ptrtoint ptr %t20 to i64
  switch i64 %t21, label %case.default.22 [ i64 3, label %case.arm.3.24 i64 4, label %case.arm.4.32 ]
case.arm.3.24:
  %t26 = getelementptr ptr, ptr %t18, i32 1
  %t27 = load ptr, ptr %t26
  call void @__inc_ref(ptr %t27)
  %t28 = call ptr @__alloc(i64 16, i32 1)
  %t29 = inttoptr i64 3 to ptr
  %t30 = getelementptr ptr, ptr %t28, i32 0
  store ptr %t29, ptr %t30
  call void @__inc_ref(ptr %t27)
  %t31 = getelementptr ptr, ptr %t28, i32 1
  store ptr %t27, ptr %t31
  call void @__free_recursive(ptr %t27)
  br label %case.end.3.25
case.end.3.25:
  br label %case.join.23
case.arm.4.32:
  %t34 = getelementptr ptr, ptr %t18, i32 1
  %t35 = load ptr, ptr %t34
  call void @__inc_ref(ptr %t35)
  call void @__inc_ref(ptr %v_chained)
  %t36 = call ptr @v_show(ptr %v_chained)
  %t37 = getelementptr ptr, ptr %t36, i32 0
  %t38 = load ptr, ptr %t37
  %t39 = ptrtoint ptr %t38 to i64
  switch i64 %t39, label %case.default.40 [ i64 3, label %case.arm.3.42 i64 4, label %case.arm.4.50 ]
case.arm.3.42:
  %t44 = getelementptr ptr, ptr %t36, i32 1
  %t45 = load ptr, ptr %t44
  call void @__inc_ref(ptr %t45)
  %t46 = call ptr @__alloc(i64 16, i32 1)
  %t47 = inttoptr i64 3 to ptr
  %t48 = getelementptr ptr, ptr %t46, i32 0
  store ptr %t47, ptr %t48
  call void @__inc_ref(ptr %t45)
  %t49 = getelementptr ptr, ptr %t46, i32 1
  store ptr %t45, ptr %t49
  call void @__free_recursive(ptr %t45)
  br label %case.end.3.43
case.end.3.43:
  br label %case.join.41
case.arm.4.50:
  %t52 = getelementptr ptr, ptr %t36, i32 1
  %t53 = load ptr, ptr %t52
  call void @__inc_ref(ptr %t53)
  call void @__inc_ref(ptr %t17)
  %t54 = call ptr @__concat(ptr %t17, ptr getelementptr inbounds (i8, ptr @.str.3, i64 12))
  %t55 = getelementptr ptr, ptr %t54, i32 0
  %t56 = load ptr, ptr %t55
  %t57 = ptrtoint ptr %t56 to i64
  switch i64 %t57, label %case.default.58 [ i64 3, label %case.arm.3.60 i64 4, label %case.arm.4.68 ]
case.arm.3.60:
  %t62 = getelementptr ptr, ptr %t54, i32 1
  %t63 = load ptr, ptr %t62
  call void @__inc_ref(ptr %t63)
  %t64 = call ptr @__alloc(i64 16, i32 1)
  %t65 = inttoptr i64 3 to ptr
  %t66 = getelementptr ptr, ptr %t64, i32 0
  store ptr %t65, ptr %t66
  call void @__inc_ref(ptr %t63)
  %t67 = getelementptr ptr, ptr %t64, i32 1
  store ptr %t63, ptr %t67
  call void @__free_recursive(ptr %t63)
  br label %case.end.3.61
case.end.3.61:
  br label %case.join.59
case.arm.4.68:
  %t70 = getelementptr ptr, ptr %t54, i32 1
  %t71 = load ptr, ptr %t70
  call void @__inc_ref(ptr %t71)
  call void @__inc_ref(ptr %t71)
  call void @__inc_ref(ptr %t35)
  %t72 = call ptr @__concat(ptr %t71, ptr %t35)
  %t73 = getelementptr ptr, ptr %t72, i32 0
  %t74 = load ptr, ptr %t73
  %t75 = ptrtoint ptr %t74 to i64
  switch i64 %t75, label %case.default.76 [ i64 3, label %case.arm.3.78 i64 4, label %case.arm.4.86 ]
case.arm.3.78:
  %t80 = getelementptr ptr, ptr %t72, i32 1
  %t81 = load ptr, ptr %t80
  call void @__inc_ref(ptr %t81)
  %t82 = call ptr @__alloc(i64 16, i32 1)
  %t83 = inttoptr i64 3 to ptr
  %t84 = getelementptr ptr, ptr %t82, i32 0
  store ptr %t83, ptr %t84
  call void @__inc_ref(ptr %t81)
  %t85 = getelementptr ptr, ptr %t82, i32 1
  store ptr %t81, ptr %t85
  call void @__free_recursive(ptr %t81)
  br label %case.end.3.79
case.end.3.79:
  br label %case.join.77
case.arm.4.86:
  %t88 = getelementptr ptr, ptr %t72, i32 1
  %t89 = load ptr, ptr %t88
  call void @__inc_ref(ptr %t89)
  call void @__inc_ref(ptr %t89)
  %t90 = call ptr @__concat(ptr %t89, ptr getelementptr inbounds (i8, ptr @.str.3, i64 12))
  %t91 = getelementptr ptr, ptr %t90, i32 0
  %t92 = load ptr, ptr %t91
  %t93 = ptrtoint ptr %t92 to i64
  switch i64 %t93, label %case.default.94 [ i64 3, label %case.arm.3.96 i64 4, label %case.arm.4.104 ]
case.arm.3.96:
  %t98 = getelementptr ptr, ptr %t90, i32 1
  %t99 = load ptr, ptr %t98
  call void @__inc_ref(ptr %t99)
  %t100 = call ptr @__alloc(i64 16, i32 1)
  %t101 = inttoptr i64 3 to ptr
  %t102 = getelementptr ptr, ptr %t100, i32 0
  store ptr %t101, ptr %t102
  call void @__inc_ref(ptr %t99)
  %t103 = getelementptr ptr, ptr %t100, i32 1
  store ptr %t99, ptr %t103
  call void @__free_recursive(ptr %t99)
  br label %case.end.3.97
case.end.3.97:
  br label %case.join.95
case.arm.4.104:
  %t106 = getelementptr ptr, ptr %t90, i32 1
  %t107 = load ptr, ptr %t106
  call void @__inc_ref(ptr %t107)
  call void @__inc_ref(ptr %t107)
  call void @__inc_ref(ptr %t53)
  %t108 = call ptr @__concat(ptr %t107, ptr %t53)
  call void @__free_recursive(ptr %t107)
  br label %case.end.4.105
case.end.4.105:
  br label %case.join.95
case.default.94:
  unreachable
case.join.95:
  %t109 = phi ptr [ %t100, %case.end.3.97 ], [ %t108, %case.end.4.105 ]
  call void @__free_recursive(ptr %t90)
  call void @__free_recursive(ptr %t89)
  br label %case.end.4.87
case.end.4.87:
  br label %case.join.77
case.default.76:
  unreachable
case.join.77:
  %t110 = phi ptr [ %t82, %case.end.3.79 ], [ %t109, %case.end.4.87 ]
  call void @__free_recursive(ptr %t72)
  call void @__free_recursive(ptr %t71)
  br label %case.end.4.69
case.end.4.69:
  br label %case.join.59
case.default.58:
  unreachable
case.join.59:
  %t111 = phi ptr [ %t64, %case.end.3.61 ], [ %t110, %case.end.4.69 ]
  call void @__free_recursive(ptr %t54)
  call void @__free_recursive(ptr %t53)
  br label %case.end.4.51
case.end.4.51:
  br label %case.join.41
case.default.40:
  unreachable
case.join.41:
  %t112 = phi ptr [ %t46, %case.end.3.43 ], [ %t111, %case.end.4.51 ]
  call void @__free_recursive(ptr %t36)
  call void @__free_recursive(ptr %t35)
  br label %case.end.4.33
case.end.4.33:
  br label %case.join.23
case.default.22:
  unreachable
case.join.23:
  %t113 = phi ptr [ %t28, %case.end.3.25 ], [ %t112, %case.end.4.33 ]
  call void @__free_recursive(ptr %t18)
  call void @__free_recursive(ptr %t17)
  br label %case.end.4.15
case.end.4.15:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t114 = phi ptr [ %t10, %case.end.3.7 ], [ %t113, %case.end.4.15 ]
  call void @__free_recursive(ptr %t0)
  %t115 = call ptr @v__let_23(ptr %t114)
  call void @__free_recursive(ptr %v_fromJust)
  call void @__free_recursive(ptr %v_fromNothing)
  call void @__free_recursive(ptr %v_chained)
  ret ptr %t115
}

define internal ptr @v__let_27(ptr %v_fromNothing, ptr %v_fromJust) {
  call void @__inc_ref(ptr %v_fromJust)
  call void @__inc_ref(ptr %v_fromNothing)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 24 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 24, i32 2)
  %t4 = inttoptr i64 14 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t3, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t6
  %t7 = call ptr @__alloc(i64 24, i32 2)
  %t8 = inttoptr i64 14 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = getelementptr ptr, ptr %t7, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.5, i64 12), ptr %t10
  %t11 = call ptr @__alloc(i64 8, i32 0)
  %t12 = inttoptr i64 13 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  %t14 = call ptr @v__lift_24(ptr %t11)
  %t15 = getelementptr ptr, ptr %t7, i32 2
  store ptr %t14, ptr %t15
  %t16 = getelementptr ptr, ptr %t3, i32 2
  store ptr %t7, ptr %t16
  %t17 = call ptr @v_headList(ptr %t3)
  %t18 = call ptr @v__lift_25(ptr %t17)
  %t19 = call ptr @v_nothingAsLeft(ptr %t0, ptr %t18)
  %t20 = getelementptr ptr, ptr %t19, i32 0
  %t21 = load ptr, ptr %t20
  %t22 = ptrtoint ptr %t21 to i64
  switch i64 %t22, label %case.default.23 [ i64 3, label %case.arm.3.25 i64 4, label %case.arm.4.33 ]
case.arm.3.25:
  %t27 = getelementptr ptr, ptr %t19, i32 1
  %t28 = load ptr, ptr %t27
  call void @__inc_ref(ptr %t28)
  %t29 = call ptr @__alloc(i64 16, i32 1)
  %t30 = inttoptr i64 3 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  call void @__inc_ref(ptr %t28)
  %t32 = getelementptr ptr, ptr %t29, i32 1
  store ptr %t28, ptr %t32
  call void @__free_recursive(ptr %t28)
  br label %case.end.3.26
case.end.3.26:
  br label %case.join.24
case.arm.4.33:
  %t35 = getelementptr ptr, ptr %t19, i32 1
  %t36 = load ptr, ptr %t35
  call void @__inc_ref(ptr %t36)
  call void @__inc_ref(ptr %t36)
  %t37 = call ptr @v_pureEither(ptr %t36)
  call void @__free_recursive(ptr %t36)
  br label %case.end.4.34
case.end.4.34:
  br label %case.join.24
case.default.23:
  unreachable
case.join.24:
  %t38 = phi ptr [ %t29, %case.end.3.26 ], [ %t37, %case.end.4.34 ]
  call void @__free_recursive(ptr %t19)
  %t39 = call ptr @v__let_26(ptr %v_fromJust, ptr %v_fromNothing, ptr %t38)
  call void @__free_recursive(ptr %v_fromNothing)
  call void @__free_recursive(ptr %v_fromJust)
  ret ptr %t39
}

define internal ptr @v__lift_28(ptr %v___input) {
  %t0 = getelementptr ptr, ptr %v___input, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 11, label %case.arm.11.4 i64 12, label %case.arm.12.8 ]
case.arm.11.4:
  %t5 = call ptr @__alloc(i64 8, i32 0)
  %t6 = inttoptr i64 11 to ptr
  %t7 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t6, ptr %t7
  call void @__free_recursive(ptr %v___input)
  ret ptr %t5
case.arm.12.8:
  %t9 = getelementptr ptr, ptr %v___input, i32 1
  %t10 = load ptr, ptr %t9
  call void @__inc_ref(ptr %t10)
  %t11 = call ptr @__alloc(i64 16, i32 1)
  %t12 = inttoptr i64 12 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  call void @__inc_ref(ptr %t10)
  %t14 = getelementptr ptr, ptr %t11, i32 1
  store ptr %t10, ptr %t14
  call void @__free_recursive(ptr %t10)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t11
case.default.3:
  unreachable
}

define internal ptr @v__let_29(ptr %v_fromNothing) {
  call void @__inc_ref(ptr %v_fromNothing)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 24 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 16, i32 1)
  %t4 = inttoptr i64 12 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t3, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.6, i64 12), ptr %t6
  %t7 = call ptr @v_nothingAsLeft(ptr %t0, ptr %t3)
  %t8 = call ptr @v__let_27(ptr %v_fromNothing, ptr %t7)
  call void @__free_recursive(ptr %v_fromNothing)
  ret ptr %t8
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
