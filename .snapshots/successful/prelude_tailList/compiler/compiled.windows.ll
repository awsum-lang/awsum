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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"Nil" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"," }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [7 x i8]} { i32 0, i32 0, i32 0, i32 7, i32 7, [7 x i8] c"Nothing" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"Just " }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"a" }
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"b" }
@.str.6 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"c" }
@.str.7 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"|" }
@.str.8 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }

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

define internal ptr @v__cps_showList(ptr %v_xs, ptr %v__k) {
entry:
  %t3 = alloca ptr
  store ptr %v_xs, ptr %t3
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
  switch i64 %t9, label %tco.case.default.10 [ i64 13, label %tco.case.arm.13.11 i64 14, label %tco.case.arm.14.17 ]
tco.case.arm.13.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 16, i32 1)
  %t13 = inttoptr i64 4 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t15
  %t16 = call ptr @v__apply_showList(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t16, ptr %t2
  br label %tco.exit.1
tco.case.arm.14.17:
  %t18 = getelementptr ptr, ptr %t5, i32 1
  %t19 = load ptr, ptr %t18
  %t20 = getelementptr ptr, ptr %t5, i32 2
  %t21 = load ptr, ptr %t20
  call void @__inc_ref(ptr %t21)
  %t28 = getelementptr i8, ptr %t5, i64 -8
  %t29 = load i32, ptr %t28
  %t30 = icmp eq i32 %t29, 1
  br i1 %t30, label %reuse.in_place.31, label %reuse.copy.32
reuse.in_place.31:
  %t22 = getelementptr ptr, ptr %t5, i32 2
  %t23 = load ptr, ptr %t22
  call void @__free_recursive(ptr %t23)
  %t26 = inttoptr i64 21 to ptr
  %t27 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t26, ptr %t27
  call void @__inc_ref(ptr %t6)
  %t24 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t24
  %t25 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t19, ptr %t25
  br label %reuse.in_place.end.34
reuse.in_place.end.34:
  br label %reuse.join.33
reuse.copy.32:
  %t36 = call ptr @__alloc(i64 24, i32 2)
  %t37 = inttoptr i64 21 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  call void @__inc_ref(ptr %t6)
  %t39 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t6, ptr %t39
  call void @__inc_ref(ptr %t19)
  %t40 = getelementptr ptr, ptr %t36, i32 2
  store ptr %t19, ptr %t40
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.35
reuse.copy.end.35:
  br label %reuse.join.33
reuse.join.33:
  %t41 = phi ptr [ %t5, %reuse.in_place.end.34 ], [ %t36, %reuse.copy.end.35 ]
  call void @__inc_ref(ptr %t21)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t21)
  store ptr %t21, ptr %t3
  store ptr %t41, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t42 = load ptr, ptr %t2
  ret ptr %t42
}

define internal ptr @v__apply_showList(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 20, label %tco.case.arm.20.11 i64 21, label %tco.case.arm.21.12 ]
tco.case.arm.20.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.21.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  %t15 = getelementptr ptr, ptr %t6, i32 0
  %t16 = load ptr, ptr %t15
  %t17 = ptrtoint ptr %t16 to i64
  switch i64 %t17, label %tco.case.default.18 [ i64 3, label %tco.case.arm.3.19 i64 4, label %tco.case.arm.4.20 ]
tco.case.arm.3.19:
  call void @__inc_ref(ptr %t14)
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t14)
  store ptr %t14, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.4.20:
  %t21 = getelementptr ptr, ptr %t6, i32 1
  %t22 = load ptr, ptr %t21
  call void @__inc_ref(ptr %t22)
  %t23 = getelementptr ptr, ptr %t5, i32 2
  %t24 = load ptr, ptr %t23
  call void @__inc_ref(ptr %t24)
  %t25 = call ptr @__concat(ptr %t24, ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  %t26 = getelementptr ptr, ptr %t25, i32 0
  %t27 = load ptr, ptr %t26
  %t28 = ptrtoint ptr %t27 to i64
  switch i64 %t28, label %tco.case.default.29 [ i64 3, label %tco.case.arm.3.30 i64 4, label %tco.case.arm.4.51 ]
tco.case.arm.3.30:
  %t31 = getelementptr ptr, ptr %t25, i32 1
  %t32 = load ptr, ptr %t31
  call void @__inc_ref(ptr %t32)
  %t38 = getelementptr i8, ptr %t6, i64 -8
  %t39 = load i32, ptr %t38
  %t40 = icmp eq i32 %t39, 1
  br i1 %t40, label %reuse.in_place.41, label %reuse.copy.42
reuse.in_place.41:
  %t33 = getelementptr ptr, ptr %t6, i32 1
  %t34 = load ptr, ptr %t33
  call void @__free_recursive(ptr %t34)
  %t36 = inttoptr i64 3 to ptr
  %t37 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t36, ptr %t37
  call void @__inc_ref(ptr %t32)
  %t35 = getelementptr ptr, ptr %t6, i32 1
  store ptr %t32, ptr %t35
  br label %reuse.in_place.end.44
reuse.in_place.end.44:
  br label %reuse.join.43
reuse.copy.42:
  %t46 = call ptr @__alloc(i64 16, i32 1)
  %t47 = inttoptr i64 3 to ptr
  %t48 = getelementptr ptr, ptr %t46, i32 0
  store ptr %t47, ptr %t48
  call void @__inc_ref(ptr %t32)
  %t49 = getelementptr ptr, ptr %t46, i32 1
  store ptr %t32, ptr %t49
  call void @__free_recursive(ptr %t6)
  br label %reuse.copy.end.45
reuse.copy.end.45:
  br label %reuse.join.43
reuse.join.43:
  %t50 = phi ptr [ %t6, %reuse.in_place.end.44 ], [ %t46, %reuse.copy.end.45 ]
  call void @__inc_ref(ptr %t14)
  call void @__free_recursive(ptr %t25)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t32)
  call void @__free_recursive(ptr %t22)
  call void @__free_recursive(ptr %t14)
  store ptr %t14, ptr %t3
  store ptr %t50, ptr %t4
  br label %tco.loop.0
tco.case.arm.4.51:
  %t52 = getelementptr ptr, ptr %t25, i32 1
  %t53 = load ptr, ptr %t52
  call void @__inc_ref(ptr %t53)
  call void @__inc_ref(ptr %t53)
  call void @__inc_ref(ptr %t22)
  %t54 = call ptr @__concat(ptr %t53, ptr %t22)
  call void @__inc_ref(ptr %t14)
  call void @__free_recursive(ptr %t25)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t53)
  call void @__free_recursive(ptr %t22)
  call void @__free_recursive(ptr %t14)
  store ptr %t14, ptr %t3
  store ptr %t54, ptr %t4
  br label %tco.loop.0
tco.case.default.29:
  unreachable
tco.case.default.18:
  unreachable
tco.case.default.10:
  unreachable
tco.exit.1:
  %t55 = load ptr, ptr %t2
  ret ptr %t55
}

define internal ptr @v_res() {
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 13 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 0
  %t4 = load ptr, ptr %t3
  %t5 = ptrtoint ptr %t4 to i64
  switch i64 %t5, label %case.default.6 [ i64 13, label %case.arm.13.8 i64 14, label %case.arm.14.14 ]
case.arm.13.8:
  %t10 = call ptr @__alloc(i64 16, i32 1)
  %t11 = inttoptr i64 4 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  %t13 = getelementptr ptr, ptr %t10, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t13
  br label %case.end.13.9
case.end.13.9:
  br label %case.join.7
case.arm.14.14:
  %t16 = getelementptr ptr, ptr %t0, i32 2
  %t17 = load ptr, ptr %t16
  call void @__inc_ref(ptr %t17)
  %t18 = call ptr @__alloc(i64 8, i32 0)
  %t19 = inttoptr i64 20 to ptr
  %t20 = getelementptr ptr, ptr %t18, i32 0
  store ptr %t19, ptr %t20
  %t21 = call ptr @v__cps_showList(ptr %t17, ptr %t18)
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
  call void @__inc_ref(ptr %t38)
  %t39 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t38)
  br label %case.end.4.36
case.end.4.36:
  br label %case.join.26
case.default.25:
  unreachable
case.join.26:
  %t40 = phi ptr [ %t31, %case.end.3.28 ], [ %t39, %case.end.4.36 ]
  call void @__free_recursive(ptr %t21)
  br label %case.end.14.15
case.end.14.15:
  br label %case.join.7
case.default.6:
  unreachable
case.join.7:
  %t41 = phi ptr [ %t10, %case.end.13.9 ], [ %t40, %case.end.14.15 ]
  %t42 = getelementptr ptr, ptr %t41, i32 0
  %t43 = load ptr, ptr %t42
  %t44 = ptrtoint ptr %t43 to i64
  switch i64 %t44, label %case.default.45 [ i64 3, label %case.arm.3.47 i64 4, label %case.arm.4.55 ]
case.arm.3.47:
  %t49 = getelementptr ptr, ptr %t41, i32 1
  %t50 = load ptr, ptr %t49
  call void @__inc_ref(ptr %t50)
  %t51 = call ptr @__alloc(i64 16, i32 1)
  %t52 = inttoptr i64 3 to ptr
  %t53 = getelementptr ptr, ptr %t51, i32 0
  store ptr %t52, ptr %t53
  call void @__inc_ref(ptr %t50)
  %t54 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t50, ptr %t54
  br label %case.end.3.48
case.end.3.48:
  br label %case.join.46
case.arm.4.55:
  %t57 = getelementptr ptr, ptr %t41, i32 1
  %t58 = load ptr, ptr %t57
  call void @__inc_ref(ptr %t58)
  %t59 = call ptr @__alloc(i64 24, i32 2)
  %t60 = inttoptr i64 14 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  %t62 = getelementptr ptr, ptr %t59, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t62
  %t63 = call ptr @__alloc(i64 8, i32 0)
  %t64 = inttoptr i64 13 to ptr
  %t65 = getelementptr ptr, ptr %t63, i32 0
  store ptr %t64, ptr %t65
  %t66 = getelementptr ptr, ptr %t59, i32 2
  store ptr %t63, ptr %t66
  %t67 = getelementptr ptr, ptr %t59, i32 0
  %t68 = load ptr, ptr %t67
  %t69 = ptrtoint ptr %t68 to i64
  switch i64 %t69, label %case.default.70 [ i64 13, label %case.arm.13.72 i64 14, label %case.arm.14.78 ]
case.arm.13.72:
  %t74 = call ptr @__alloc(i64 16, i32 1)
  %t75 = inttoptr i64 4 to ptr
  %t76 = getelementptr ptr, ptr %t74, i32 0
  store ptr %t75, ptr %t76
  %t77 = getelementptr ptr, ptr %t74, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t77
  br label %case.end.13.73
case.end.13.73:
  br label %case.join.71
case.arm.14.78:
  %t80 = getelementptr ptr, ptr %t59, i32 2
  %t81 = load ptr, ptr %t80
  call void @__inc_ref(ptr %t81)
  %t82 = call ptr @__alloc(i64 8, i32 0)
  %t83 = inttoptr i64 20 to ptr
  %t84 = getelementptr ptr, ptr %t82, i32 0
  store ptr %t83, ptr %t84
  %t85 = call ptr @v__cps_showList(ptr %t81, ptr %t82)
  %t86 = getelementptr ptr, ptr %t85, i32 0
  %t87 = load ptr, ptr %t86
  %t88 = ptrtoint ptr %t87 to i64
  switch i64 %t88, label %case.default.89 [ i64 3, label %case.arm.3.91 i64 4, label %case.arm.4.99 ]
case.arm.3.91:
  %t93 = getelementptr ptr, ptr %t85, i32 1
  %t94 = load ptr, ptr %t93
  call void @__inc_ref(ptr %t94)
  %t95 = call ptr @__alloc(i64 16, i32 1)
  %t96 = inttoptr i64 3 to ptr
  %t97 = getelementptr ptr, ptr %t95, i32 0
  store ptr %t96, ptr %t97
  call void @__inc_ref(ptr %t94)
  %t98 = getelementptr ptr, ptr %t95, i32 1
  store ptr %t94, ptr %t98
  br label %case.end.3.92
case.end.3.92:
  br label %case.join.90
case.arm.4.99:
  %t101 = getelementptr ptr, ptr %t85, i32 1
  %t102 = load ptr, ptr %t101
  call void @__inc_ref(ptr %t102)
  call void @__inc_ref(ptr %t102)
  %t103 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t102)
  br label %case.end.4.100
case.end.4.100:
  br label %case.join.90
case.default.89:
  unreachable
case.join.90:
  %t104 = phi ptr [ %t95, %case.end.3.92 ], [ %t103, %case.end.4.100 ]
  call void @__free_recursive(ptr %t85)
  br label %case.end.14.79
case.end.14.79:
  br label %case.join.71
case.default.70:
  unreachable
case.join.71:
  %t105 = phi ptr [ %t74, %case.end.13.73 ], [ %t104, %case.end.14.79 ]
  %t106 = getelementptr ptr, ptr %t105, i32 0
  %t107 = load ptr, ptr %t106
  %t108 = ptrtoint ptr %t107 to i64
  switch i64 %t108, label %case.default.109 [ i64 3, label %case.arm.3.111 i64 4, label %case.arm.4.119 ]
case.arm.3.111:
  %t113 = getelementptr ptr, ptr %t105, i32 1
  %t114 = load ptr, ptr %t113
  call void @__inc_ref(ptr %t114)
  %t115 = call ptr @__alloc(i64 16, i32 1)
  %t116 = inttoptr i64 3 to ptr
  %t117 = getelementptr ptr, ptr %t115, i32 0
  store ptr %t116, ptr %t117
  call void @__inc_ref(ptr %t114)
  %t118 = getelementptr ptr, ptr %t115, i32 1
  store ptr %t114, ptr %t118
  br label %case.end.3.112
case.end.3.112:
  br label %case.join.110
case.arm.4.119:
  %t121 = getelementptr ptr, ptr %t105, i32 1
  %t122 = load ptr, ptr %t121
  call void @__inc_ref(ptr %t122)
  %t123 = call ptr @__alloc(i64 24, i32 2)
  %t124 = inttoptr i64 14 to ptr
  %t125 = getelementptr ptr, ptr %t123, i32 0
  store ptr %t124, ptr %t125
  %t126 = getelementptr ptr, ptr %t123, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t126
  %t127 = call ptr @__alloc(i64 24, i32 2)
  %t128 = inttoptr i64 14 to ptr
  %t129 = getelementptr ptr, ptr %t127, i32 0
  store ptr %t128, ptr %t129
  %t130 = getelementptr ptr, ptr %t127, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.5, i64 12), ptr %t130
  %t131 = call ptr @__alloc(i64 24, i32 2)
  %t132 = inttoptr i64 14 to ptr
  %t133 = getelementptr ptr, ptr %t131, i32 0
  store ptr %t132, ptr %t133
  %t134 = getelementptr ptr, ptr %t131, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.6, i64 12), ptr %t134
  %t135 = call ptr @__alloc(i64 8, i32 0)
  %t136 = inttoptr i64 13 to ptr
  %t137 = getelementptr ptr, ptr %t135, i32 0
  store ptr %t136, ptr %t137
  %t138 = getelementptr ptr, ptr %t131, i32 2
  store ptr %t135, ptr %t138
  %t139 = getelementptr ptr, ptr %t127, i32 2
  store ptr %t131, ptr %t139
  %t140 = getelementptr ptr, ptr %t123, i32 2
  store ptr %t127, ptr %t140
  %t141 = getelementptr ptr, ptr %t123, i32 0
  %t142 = load ptr, ptr %t141
  %t143 = ptrtoint ptr %t142 to i64
  switch i64 %t143, label %case.default.144 [ i64 13, label %case.arm.13.146 i64 14, label %case.arm.14.152 ]
case.arm.13.146:
  %t148 = call ptr @__alloc(i64 16, i32 1)
  %t149 = inttoptr i64 4 to ptr
  %t150 = getelementptr ptr, ptr %t148, i32 0
  store ptr %t149, ptr %t150
  %t151 = getelementptr ptr, ptr %t148, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t151
  br label %case.end.13.147
case.end.13.147:
  br label %case.join.145
case.arm.14.152:
  %t154 = getelementptr ptr, ptr %t123, i32 2
  %t155 = load ptr, ptr %t154
  call void @__inc_ref(ptr %t155)
  %t156 = call ptr @__alloc(i64 8, i32 0)
  %t157 = inttoptr i64 20 to ptr
  %t158 = getelementptr ptr, ptr %t156, i32 0
  store ptr %t157, ptr %t158
  %t159 = call ptr @v__cps_showList(ptr %t155, ptr %t156)
  %t160 = getelementptr ptr, ptr %t159, i32 0
  %t161 = load ptr, ptr %t160
  %t162 = ptrtoint ptr %t161 to i64
  switch i64 %t162, label %case.default.163 [ i64 3, label %case.arm.3.165 i64 4, label %case.arm.4.173 ]
case.arm.3.165:
  %t167 = getelementptr ptr, ptr %t159, i32 1
  %t168 = load ptr, ptr %t167
  call void @__inc_ref(ptr %t168)
  %t169 = call ptr @__alloc(i64 16, i32 1)
  %t170 = inttoptr i64 3 to ptr
  %t171 = getelementptr ptr, ptr %t169, i32 0
  store ptr %t170, ptr %t171
  call void @__inc_ref(ptr %t168)
  %t172 = getelementptr ptr, ptr %t169, i32 1
  store ptr %t168, ptr %t172
  br label %case.end.3.166
case.end.3.166:
  br label %case.join.164
case.arm.4.173:
  %t175 = getelementptr ptr, ptr %t159, i32 1
  %t176 = load ptr, ptr %t175
  call void @__inc_ref(ptr %t176)
  call void @__inc_ref(ptr %t176)
  %t177 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t176)
  br label %case.end.4.174
case.end.4.174:
  br label %case.join.164
case.default.163:
  unreachable
case.join.164:
  %t178 = phi ptr [ %t169, %case.end.3.166 ], [ %t177, %case.end.4.174 ]
  call void @__free_recursive(ptr %t159)
  br label %case.end.14.153
case.end.14.153:
  br label %case.join.145
case.default.144:
  unreachable
case.join.145:
  %t179 = phi ptr [ %t148, %case.end.13.147 ], [ %t178, %case.end.14.153 ]
  %t180 = getelementptr ptr, ptr %t179, i32 0
  %t181 = load ptr, ptr %t180
  %t182 = ptrtoint ptr %t181 to i64
  switch i64 %t182, label %case.default.183 [ i64 3, label %case.arm.3.185 i64 4, label %case.arm.4.193 ]
case.arm.3.185:
  %t187 = getelementptr ptr, ptr %t179, i32 1
  %t188 = load ptr, ptr %t187
  call void @__inc_ref(ptr %t188)
  %t189 = call ptr @__alloc(i64 16, i32 1)
  %t190 = inttoptr i64 3 to ptr
  %t191 = getelementptr ptr, ptr %t189, i32 0
  store ptr %t190, ptr %t191
  call void @__inc_ref(ptr %t188)
  %t192 = getelementptr ptr, ptr %t189, i32 1
  store ptr %t188, ptr %t192
  br label %case.end.3.186
case.end.3.186:
  br label %case.join.184
case.arm.4.193:
  %t195 = getelementptr ptr, ptr %t179, i32 1
  %t196 = load ptr, ptr %t195
  call void @__inc_ref(ptr %t196)
  call void @__inc_ref(ptr %t58)
  %t197 = call ptr @__concat(ptr %t58, ptr getelementptr inbounds (i8, ptr @.str.7, i64 12))
  %t198 = getelementptr ptr, ptr %t197, i32 0
  %t199 = load ptr, ptr %t198
  %t200 = ptrtoint ptr %t199 to i64
  switch i64 %t200, label %case.default.201 [ i64 3, label %case.arm.3.203 i64 4, label %case.arm.4.211 ]
case.arm.3.203:
  %t205 = getelementptr ptr, ptr %t197, i32 1
  %t206 = load ptr, ptr %t205
  call void @__inc_ref(ptr %t206)
  %t207 = call ptr @__alloc(i64 16, i32 1)
  %t208 = inttoptr i64 3 to ptr
  %t209 = getelementptr ptr, ptr %t207, i32 0
  store ptr %t208, ptr %t209
  call void @__inc_ref(ptr %t206)
  %t210 = getelementptr ptr, ptr %t207, i32 1
  store ptr %t206, ptr %t210
  br label %case.end.3.204
case.end.3.204:
  br label %case.join.202
case.arm.4.211:
  %t213 = getelementptr ptr, ptr %t197, i32 1
  %t214 = load ptr, ptr %t213
  call void @__inc_ref(ptr %t214)
  call void @__inc_ref(ptr %t214)
  call void @__inc_ref(ptr %t122)
  %t215 = call ptr @__concat(ptr %t214, ptr %t122)
  %t216 = getelementptr ptr, ptr %t215, i32 0
  %t217 = load ptr, ptr %t216
  %t218 = ptrtoint ptr %t217 to i64
  switch i64 %t218, label %case.default.219 [ i64 3, label %case.arm.3.221 i64 4, label %case.arm.4.229 ]
case.arm.3.221:
  %t223 = getelementptr ptr, ptr %t215, i32 1
  %t224 = load ptr, ptr %t223
  call void @__inc_ref(ptr %t224)
  %t225 = call ptr @__alloc(i64 16, i32 1)
  %t226 = inttoptr i64 3 to ptr
  %t227 = getelementptr ptr, ptr %t225, i32 0
  store ptr %t226, ptr %t227
  call void @__inc_ref(ptr %t224)
  %t228 = getelementptr ptr, ptr %t225, i32 1
  store ptr %t224, ptr %t228
  br label %case.end.3.222
case.end.3.222:
  br label %case.join.220
case.arm.4.229:
  %t231 = getelementptr ptr, ptr %t215, i32 1
  %t232 = load ptr, ptr %t231
  call void @__inc_ref(ptr %t232)
  call void @__inc_ref(ptr %t232)
  %t233 = call ptr @__concat(ptr %t232, ptr getelementptr inbounds (i8, ptr @.str.7, i64 12))
  %t234 = getelementptr ptr, ptr %t233, i32 0
  %t235 = load ptr, ptr %t234
  %t236 = ptrtoint ptr %t235 to i64
  switch i64 %t236, label %case.default.237 [ i64 3, label %case.arm.3.239 i64 4, label %case.arm.4.247 ]
case.arm.3.239:
  %t241 = getelementptr ptr, ptr %t233, i32 1
  %t242 = load ptr, ptr %t241
  call void @__inc_ref(ptr %t242)
  %t243 = call ptr @__alloc(i64 16, i32 1)
  %t244 = inttoptr i64 3 to ptr
  %t245 = getelementptr ptr, ptr %t243, i32 0
  store ptr %t244, ptr %t245
  call void @__inc_ref(ptr %t242)
  %t246 = getelementptr ptr, ptr %t243, i32 1
  store ptr %t242, ptr %t246
  br label %case.end.3.240
case.end.3.240:
  br label %case.join.238
case.arm.4.247:
  %t249 = getelementptr ptr, ptr %t233, i32 1
  %t250 = load ptr, ptr %t249
  call void @__inc_ref(ptr %t250)
  call void @__inc_ref(ptr %t250)
  call void @__inc_ref(ptr %t196)
  %t251 = call ptr @__concat(ptr %t250, ptr %t196)
  br label %case.end.4.248
case.end.4.248:
  br label %case.join.238
case.default.237:
  unreachable
case.join.238:
  %t252 = phi ptr [ %t243, %case.end.3.240 ], [ %t251, %case.end.4.248 ]
  call void @__free_recursive(ptr %t233)
  br label %case.end.4.230
case.end.4.230:
  br label %case.join.220
case.default.219:
  unreachable
case.join.220:
  %t253 = phi ptr [ %t225, %case.end.3.222 ], [ %t252, %case.end.4.230 ]
  call void @__free_recursive(ptr %t215)
  br label %case.end.4.212
case.end.4.212:
  br label %case.join.202
case.default.201:
  unreachable
case.join.202:
  %t254 = phi ptr [ %t207, %case.end.3.204 ], [ %t253, %case.end.4.212 ]
  call void @__free_recursive(ptr %t197)
  br label %case.end.4.194
case.end.4.194:
  br label %case.join.184
case.default.183:
  unreachable
case.join.184:
  %t255 = phi ptr [ %t189, %case.end.3.186 ], [ %t254, %case.end.4.194 ]
  call void @__free_recursive(ptr %t179)
  call void @__free_recursive(ptr %t123)
  br label %case.end.4.120
case.end.4.120:
  br label %case.join.110
case.default.109:
  unreachable
case.join.110:
  %t256 = phi ptr [ %t115, %case.end.3.112 ], [ %t255, %case.end.4.120 ]
  call void @__free_recursive(ptr %t105)
  call void @__free_recursive(ptr %t59)
  br label %case.end.4.56
case.end.4.56:
  br label %case.join.46
case.default.45:
  unreachable
case.join.46:
  %t257 = phi ptr [ %t51, %case.end.3.48 ], [ %t256, %case.end.4.56 ]
  call void @__free_recursive(ptr %t41)
  call void @__free_recursive(ptr %t0)
  ret ptr %t257
}

define internal ptr @v_main() {
  %t0 = call ptr @v_res()
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 3, label %case.arm.3.6 i64 4, label %case.arm.4.14 ]
case.arm.3.6:
  %t8 = call ptr @__alloc(i64 16, i32 1)
  %t9 = inttoptr i64 6 to ptr
  %t10 = getelementptr ptr, ptr %t8, i32 0
  store ptr %t9, ptr %t10
  %t11 = getelementptr ptr, ptr %t0, i32 1
  %t12 = load ptr, ptr %t11
  call void @__inc_ref(ptr %t12)
  %t13 = getelementptr ptr, ptr %t8, i32 1
  store ptr %t12, ptr %t13
  br label %case.end.3.7
case.end.3.7:
  br label %case.join.5
case.arm.4.14:
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 5 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = getelementptr ptr, ptr %t0, i32 1
  %t20 = load ptr, ptr %t19
  call void @__inc_ref(ptr %t20)
  %t21 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t20, ptr %t21
  br label %case.end.4.15
case.end.4.15:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t22 = phi ptr [ %t8, %case.end.3.7 ], [ %t16, %case.end.4.15 ]
  call void @__free_recursive(ptr %t0)
  %t23 = call ptr @__alloc(i64 8, i32 0)
  %t24 = inttoptr i64 24 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  %t26 = call ptr @v__cps__df_andThenIO_4(ptr %t22, ptr %t23)
  %t27 = call ptr @__alloc(i64 8, i32 0)
  %t28 = inttoptr i64 22 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  %t30 = call ptr @v__cps__df_handleErrorIO_0(ptr %t26, ptr %t27)
  ret ptr %t30
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
  store ptr getelementptr inbounds (i8, ptr @.str.8, i64 12), ptr %t17
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
  %t36 = inttoptr i64 23 to ptr
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
  %t47 = inttoptr i64 23 to ptr
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
  call void @__inc_ref(ptr %t31)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t31)
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
  switch i64 %t9, label %tco.case.default.10 [ i64 22, label %tco.case.arm.22.11 i64 23, label %tco.case.arm.23.12 ]
tco.case.arm.22.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.23.12:
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
  call void @__inc_ref(ptr %t14)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t14)
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.27 i64 7, label %tco.case.arm.7.29 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t5, i32 1
  %t16 = load ptr, ptr %t15
  call void @__inc_ref(ptr %t16)
  %t17 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t16, ptr %t17
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
  %t25 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t18, ptr %t25
  %t26 = call ptr @v__apply__df_andThenIO_4(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t26, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.27:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t28 = call ptr @v__apply__df_andThenIO_4(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t28, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.29:
  %t30 = getelementptr ptr, ptr %t5, i32 1
  %t31 = load ptr, ptr %t30
  %t32 = getelementptr ptr, ptr %t5, i32 2
  %t33 = load ptr, ptr %t32
  call void @__inc_ref(ptr %t33)
  %t40 = getelementptr i8, ptr %t5, i64 -8
  %t41 = load i32, ptr %t40
  %t42 = icmp eq i32 %t41, 1
  br i1 %t42, label %reuse.in_place.43, label %reuse.copy.44
reuse.in_place.43:
  %t34 = getelementptr ptr, ptr %t5, i32 2
  %t35 = load ptr, ptr %t34
  call void @__free_recursive(ptr %t35)
  %t38 = inttoptr i64 25 to ptr
  %t39 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t38, ptr %t39
  call void @__inc_ref(ptr %t6)
  %t36 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t36
  %t37 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t31, ptr %t37
  br label %reuse.in_place.end.46
reuse.in_place.end.46:
  br label %reuse.join.45
reuse.copy.44:
  %t48 = call ptr @__alloc(i64 24, i32 2)
  %t49 = inttoptr i64 25 to ptr
  %t50 = getelementptr ptr, ptr %t48, i32 0
  store ptr %t49, ptr %t50
  call void @__inc_ref(ptr %t6)
  %t51 = getelementptr ptr, ptr %t48, i32 1
  store ptr %t6, ptr %t51
  call void @__inc_ref(ptr %t31)
  %t52 = getelementptr ptr, ptr %t48, i32 2
  store ptr %t31, ptr %t52
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.47
reuse.copy.end.47:
  br label %reuse.join.45
reuse.join.45:
  %t53 = phi ptr [ %t5, %reuse.in_place.end.46 ], [ %t48, %reuse.copy.end.47 ]
  call void @__inc_ref(ptr %t33)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t33)
  store ptr %t33, ptr %t3
  store ptr %t53, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t54 = load ptr, ptr %t2
  ret ptr %t54
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
  call void @__inc_ref(ptr %t14)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t14)
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
