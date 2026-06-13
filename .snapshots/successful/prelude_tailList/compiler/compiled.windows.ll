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
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [7 x i8]} { i32 0, i32 0, i32 0, i32 7, i32 7, [7 x i8] c"Nothing" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"Just " }
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"a" }
@.str.6 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"b" }
@.str.7 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"c" }
@.str.8 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"|" }

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
  %t26 = inttoptr i64 16 to ptr
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
  %t37 = inttoptr i64 16 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 15, label %tco.case.arm.15.11 i64 16, label %tco.case.arm.16.12 ]
tco.case.arm.15.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.16.12:
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

define internal ptr @v_main() {
  %v__inl80_scrut.jslot = alloca ptr
  %t2 = call ptr @__alloc(i64 8, i32 0)
  %t3 = inttoptr i64 13 to ptr
  %t4 = getelementptr ptr, ptr %t2, i32 0
  store ptr %t3, ptr %t4
  %t5 = getelementptr ptr, ptr %t2, i32 0
  %t6 = load ptr, ptr %t5
  %t7 = ptrtoint ptr %t6 to i64
  switch i64 %t7, label %case.default.8 [ i64 13, label %case.arm.13.10 i64 14, label %case.arm.14.16 ]
case.arm.13.10:
  %t12 = call ptr @__alloc(i64 16, i32 1)
  %t13 = inttoptr i64 4 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t15
  br label %case.end.13.11
case.end.13.11:
  br label %case.join.9
case.arm.14.16:
  %t18 = getelementptr ptr, ptr %t2, i32 2
  %t19 = load ptr, ptr %t18
  call void @__inc_ref(ptr %t19)
  %t20 = call ptr @__alloc(i64 8, i32 0)
  %t21 = inttoptr i64 15 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = call ptr @v__cps_showList(ptr %t19, ptr %t20)
  %t24 = getelementptr ptr, ptr %t23, i32 0
  %t25 = load ptr, ptr %t24
  %t26 = ptrtoint ptr %t25 to i64
  switch i64 %t26, label %case.default.27 [ i64 3, label %case.arm.3.29 i64 4, label %case.arm.4.37 ]
case.arm.3.29:
  %t31 = getelementptr ptr, ptr %t23, i32 1
  %t32 = load ptr, ptr %t31
  call void @__inc_ref(ptr %t32)
  %t33 = call ptr @__alloc(i64 16, i32 1)
  %t34 = inttoptr i64 3 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  call void @__inc_ref(ptr %t32)
  %t36 = getelementptr ptr, ptr %t33, i32 1
  store ptr %t32, ptr %t36
  br label %case.end.3.30
case.end.3.30:
  br label %case.join.28
case.arm.4.37:
  %t39 = getelementptr ptr, ptr %t23, i32 1
  %t40 = load ptr, ptr %t39
  call void @__inc_ref(ptr %t40)
  call void @__inc_ref(ptr %t40)
  %t41 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t40)
  br label %case.end.4.38
case.end.4.38:
  br label %case.join.28
case.default.27:
  unreachable
case.join.28:
  %t42 = phi ptr [ %t33, %case.end.3.30 ], [ %t41, %case.end.4.38 ]
  call void @__free_recursive(ptr %t23)
  br label %case.end.14.17
case.end.14.17:
  br label %case.join.9
case.default.8:
  unreachable
case.join.9:
  %t43 = phi ptr [ %t12, %case.end.13.11 ], [ %t42, %case.end.14.17 ]
  %t44 = getelementptr ptr, ptr %t43, i32 0
  %t45 = load ptr, ptr %t44
  %t46 = ptrtoint ptr %t45 to i64
  switch i64 %t46, label %join.case.default.47 [ i64 3, label %join.case.arm.3.48 i64 4, label %join.case.arm.4.62 ]
join.case.arm.3.48:
  %t49 = call ptr @__alloc(i64 24, i32 2)
  %t50 = inttoptr i64 7 to ptr
  %t51 = getelementptr ptr, ptr %t49, i32 0
  store ptr %t50, ptr %t51
  %t52 = getelementptr ptr, ptr %t49, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t52
  %t53 = call ptr @__alloc(i64 16, i32 1)
  %t54 = inttoptr i64 5 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  %t56 = call ptr @__alloc(i64 8, i32 0)
  %t57 = inttoptr i64 0 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  %t59 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t56, ptr %t59
  %t60 = getelementptr ptr, ptr %t49, i32 2
  store ptr %t53, ptr %t60
  call void @__free_recursive(ptr %t2)
  call void @__free_recursive(ptr %t43)
  br label %join.val.61
join.val.61:
  br label %join.after.1
join.case.arm.4.62:
  %t63 = getelementptr ptr, ptr %t43, i32 1
  %t64 = load ptr, ptr %t63
  call void @__inc_ref(ptr %t64)
  %t65 = call ptr @__alloc(i64 24, i32 2)
  %t66 = inttoptr i64 14 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  %t68 = getelementptr ptr, ptr %t65, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.5, i64 12), ptr %t68
  %t69 = call ptr @__alloc(i64 8, i32 0)
  %t70 = inttoptr i64 13 to ptr
  %t71 = getelementptr ptr, ptr %t69, i32 0
  store ptr %t70, ptr %t71
  %t72 = getelementptr ptr, ptr %t65, i32 2
  store ptr %t69, ptr %t72
  %t73 = getelementptr ptr, ptr %t65, i32 0
  %t74 = load ptr, ptr %t73
  %t75 = ptrtoint ptr %t74 to i64
  switch i64 %t75, label %case.default.76 [ i64 13, label %case.arm.13.78 i64 14, label %case.arm.14.84 ]
case.arm.13.78:
  %t80 = call ptr @__alloc(i64 16, i32 1)
  %t81 = inttoptr i64 4 to ptr
  %t82 = getelementptr ptr, ptr %t80, i32 0
  store ptr %t81, ptr %t82
  %t83 = getelementptr ptr, ptr %t80, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t83
  br label %case.end.13.79
case.end.13.79:
  br label %case.join.77
case.arm.14.84:
  %t86 = getelementptr ptr, ptr %t65, i32 2
  %t87 = load ptr, ptr %t86
  call void @__inc_ref(ptr %t87)
  %t88 = call ptr @__alloc(i64 8, i32 0)
  %t89 = inttoptr i64 15 to ptr
  %t90 = getelementptr ptr, ptr %t88, i32 0
  store ptr %t89, ptr %t90
  %t91 = call ptr @v__cps_showList(ptr %t87, ptr %t88)
  %t92 = getelementptr ptr, ptr %t91, i32 0
  %t93 = load ptr, ptr %t92
  %t94 = ptrtoint ptr %t93 to i64
  switch i64 %t94, label %case.default.95 [ i64 3, label %case.arm.3.97 i64 4, label %case.arm.4.105 ]
case.arm.3.97:
  %t99 = getelementptr ptr, ptr %t91, i32 1
  %t100 = load ptr, ptr %t99
  call void @__inc_ref(ptr %t100)
  %t101 = call ptr @__alloc(i64 16, i32 1)
  %t102 = inttoptr i64 3 to ptr
  %t103 = getelementptr ptr, ptr %t101, i32 0
  store ptr %t102, ptr %t103
  call void @__inc_ref(ptr %t100)
  %t104 = getelementptr ptr, ptr %t101, i32 1
  store ptr %t100, ptr %t104
  br label %case.end.3.98
case.end.3.98:
  br label %case.join.96
case.arm.4.105:
  %t107 = getelementptr ptr, ptr %t91, i32 1
  %t108 = load ptr, ptr %t107
  call void @__inc_ref(ptr %t108)
  call void @__inc_ref(ptr %t108)
  %t109 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t108)
  br label %case.end.4.106
case.end.4.106:
  br label %case.join.96
case.default.95:
  unreachable
case.join.96:
  %t110 = phi ptr [ %t101, %case.end.3.98 ], [ %t109, %case.end.4.106 ]
  call void @__free_recursive(ptr %t91)
  br label %case.end.14.85
case.end.14.85:
  br label %case.join.77
case.default.76:
  unreachable
case.join.77:
  %t111 = phi ptr [ %t80, %case.end.13.79 ], [ %t110, %case.end.14.85 ]
  %t112 = getelementptr ptr, ptr %t111, i32 0
  %t113 = load ptr, ptr %t112
  %t114 = ptrtoint ptr %t113 to i64
  switch i64 %t114, label %case.default.115 [ i64 3, label %case.arm.3.117 i64 4, label %case.arm.4.125 ]
case.arm.3.117:
  %t119 = getelementptr ptr, ptr %t111, i32 1
  %t120 = load ptr, ptr %t119
  call void @__inc_ref(ptr %t120)
  %t121 = call ptr @__alloc(i64 16, i32 1)
  %t122 = inttoptr i64 3 to ptr
  %t123 = getelementptr ptr, ptr %t121, i32 0
  store ptr %t122, ptr %t123
  call void @__inc_ref(ptr %t120)
  %t124 = getelementptr ptr, ptr %t121, i32 1
  store ptr %t120, ptr %t124
  br label %case.end.3.118
case.end.3.118:
  br label %case.join.116
case.arm.4.125:
  %t127 = getelementptr ptr, ptr %t111, i32 1
  %t128 = load ptr, ptr %t127
  call void @__inc_ref(ptr %t128)
  %t129 = call ptr @__alloc(i64 24, i32 2)
  %t130 = inttoptr i64 14 to ptr
  %t131 = getelementptr ptr, ptr %t129, i32 0
  store ptr %t130, ptr %t131
  %t132 = getelementptr ptr, ptr %t129, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.5, i64 12), ptr %t132
  %t133 = call ptr @__alloc(i64 24, i32 2)
  %t134 = inttoptr i64 14 to ptr
  %t135 = getelementptr ptr, ptr %t133, i32 0
  store ptr %t134, ptr %t135
  %t136 = getelementptr ptr, ptr %t133, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.6, i64 12), ptr %t136
  %t137 = call ptr @__alloc(i64 24, i32 2)
  %t138 = inttoptr i64 14 to ptr
  %t139 = getelementptr ptr, ptr %t137, i32 0
  store ptr %t138, ptr %t139
  %t140 = getelementptr ptr, ptr %t137, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.7, i64 12), ptr %t140
  %t141 = call ptr @__alloc(i64 8, i32 0)
  %t142 = inttoptr i64 13 to ptr
  %t143 = getelementptr ptr, ptr %t141, i32 0
  store ptr %t142, ptr %t143
  %t144 = getelementptr ptr, ptr %t137, i32 2
  store ptr %t141, ptr %t144
  %t145 = getelementptr ptr, ptr %t133, i32 2
  store ptr %t137, ptr %t145
  %t146 = getelementptr ptr, ptr %t129, i32 2
  store ptr %t133, ptr %t146
  %t147 = getelementptr ptr, ptr %t129, i32 0
  %t148 = load ptr, ptr %t147
  %t149 = ptrtoint ptr %t148 to i64
  switch i64 %t149, label %case.default.150 [ i64 13, label %case.arm.13.152 i64 14, label %case.arm.14.158 ]
case.arm.13.152:
  %t154 = call ptr @__alloc(i64 16, i32 1)
  %t155 = inttoptr i64 4 to ptr
  %t156 = getelementptr ptr, ptr %t154, i32 0
  store ptr %t155, ptr %t156
  %t157 = getelementptr ptr, ptr %t154, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t157
  br label %case.end.13.153
case.end.13.153:
  br label %case.join.151
case.arm.14.158:
  %t160 = getelementptr ptr, ptr %t129, i32 2
  %t161 = load ptr, ptr %t160
  call void @__inc_ref(ptr %t161)
  %t162 = call ptr @__alloc(i64 8, i32 0)
  %t163 = inttoptr i64 15 to ptr
  %t164 = getelementptr ptr, ptr %t162, i32 0
  store ptr %t163, ptr %t164
  %t165 = call ptr @v__cps_showList(ptr %t161, ptr %t162)
  %t166 = getelementptr ptr, ptr %t165, i32 0
  %t167 = load ptr, ptr %t166
  %t168 = ptrtoint ptr %t167 to i64
  switch i64 %t168, label %case.default.169 [ i64 3, label %case.arm.3.171 i64 4, label %case.arm.4.179 ]
case.arm.3.171:
  %t173 = getelementptr ptr, ptr %t165, i32 1
  %t174 = load ptr, ptr %t173
  call void @__inc_ref(ptr %t174)
  %t175 = call ptr @__alloc(i64 16, i32 1)
  %t176 = inttoptr i64 3 to ptr
  %t177 = getelementptr ptr, ptr %t175, i32 0
  store ptr %t176, ptr %t177
  call void @__inc_ref(ptr %t174)
  %t178 = getelementptr ptr, ptr %t175, i32 1
  store ptr %t174, ptr %t178
  br label %case.end.3.172
case.end.3.172:
  br label %case.join.170
case.arm.4.179:
  %t181 = getelementptr ptr, ptr %t165, i32 1
  %t182 = load ptr, ptr %t181
  call void @__inc_ref(ptr %t182)
  call void @__inc_ref(ptr %t182)
  %t183 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t182)
  br label %case.end.4.180
case.end.4.180:
  br label %case.join.170
case.default.169:
  unreachable
case.join.170:
  %t184 = phi ptr [ %t175, %case.end.3.172 ], [ %t183, %case.end.4.180 ]
  call void @__free_recursive(ptr %t165)
  br label %case.end.14.159
case.end.14.159:
  br label %case.join.151
case.default.150:
  unreachable
case.join.151:
  %t185 = phi ptr [ %t154, %case.end.13.153 ], [ %t184, %case.end.14.159 ]
  %t186 = getelementptr ptr, ptr %t185, i32 0
  %t187 = load ptr, ptr %t186
  %t188 = ptrtoint ptr %t187 to i64
  switch i64 %t188, label %case.default.189 [ i64 3, label %case.arm.3.191 i64 4, label %case.arm.4.199 ]
case.arm.3.191:
  %t193 = getelementptr ptr, ptr %t185, i32 1
  %t194 = load ptr, ptr %t193
  call void @__inc_ref(ptr %t194)
  %t195 = call ptr @__alloc(i64 16, i32 1)
  %t196 = inttoptr i64 3 to ptr
  %t197 = getelementptr ptr, ptr %t195, i32 0
  store ptr %t196, ptr %t197
  call void @__inc_ref(ptr %t194)
  %t198 = getelementptr ptr, ptr %t195, i32 1
  store ptr %t194, ptr %t198
  br label %case.end.3.192
case.end.3.192:
  br label %case.join.190
case.arm.4.199:
  %t201 = getelementptr ptr, ptr %t185, i32 1
  %t202 = load ptr, ptr %t201
  call void @__inc_ref(ptr %t202)
  call void @__inc_ref(ptr %t64)
  %t203 = call ptr @__concat(ptr %t64, ptr getelementptr inbounds (i8, ptr @.str.8, i64 12))
  %t204 = getelementptr ptr, ptr %t203, i32 0
  %t205 = load ptr, ptr %t204
  %t206 = ptrtoint ptr %t205 to i64
  switch i64 %t206, label %case.default.207 [ i64 3, label %case.arm.3.209 i64 4, label %case.arm.4.217 ]
case.arm.3.209:
  %t211 = getelementptr ptr, ptr %t203, i32 1
  %t212 = load ptr, ptr %t211
  call void @__inc_ref(ptr %t212)
  %t213 = call ptr @__alloc(i64 16, i32 1)
  %t214 = inttoptr i64 3 to ptr
  %t215 = getelementptr ptr, ptr %t213, i32 0
  store ptr %t214, ptr %t215
  call void @__inc_ref(ptr %t212)
  %t216 = getelementptr ptr, ptr %t213, i32 1
  store ptr %t212, ptr %t216
  br label %case.end.3.210
case.end.3.210:
  br label %case.join.208
case.arm.4.217:
  %t219 = getelementptr ptr, ptr %t203, i32 1
  %t220 = load ptr, ptr %t219
  call void @__inc_ref(ptr %t220)
  call void @__inc_ref(ptr %t220)
  call void @__inc_ref(ptr %t128)
  %t221 = call ptr @__concat(ptr %t220, ptr %t128)
  %t222 = getelementptr ptr, ptr %t221, i32 0
  %t223 = load ptr, ptr %t222
  %t224 = ptrtoint ptr %t223 to i64
  switch i64 %t224, label %case.default.225 [ i64 3, label %case.arm.3.227 i64 4, label %case.arm.4.235 ]
case.arm.3.227:
  %t229 = getelementptr ptr, ptr %t221, i32 1
  %t230 = load ptr, ptr %t229
  call void @__inc_ref(ptr %t230)
  %t231 = call ptr @__alloc(i64 16, i32 1)
  %t232 = inttoptr i64 3 to ptr
  %t233 = getelementptr ptr, ptr %t231, i32 0
  store ptr %t232, ptr %t233
  call void @__inc_ref(ptr %t230)
  %t234 = getelementptr ptr, ptr %t231, i32 1
  store ptr %t230, ptr %t234
  br label %case.end.3.228
case.end.3.228:
  br label %case.join.226
case.arm.4.235:
  %t237 = getelementptr ptr, ptr %t221, i32 1
  %t238 = load ptr, ptr %t237
  call void @__inc_ref(ptr %t238)
  call void @__inc_ref(ptr %t238)
  %t239 = call ptr @__concat(ptr %t238, ptr getelementptr inbounds (i8, ptr @.str.8, i64 12))
  %t240 = getelementptr ptr, ptr %t239, i32 0
  %t241 = load ptr, ptr %t240
  %t242 = ptrtoint ptr %t241 to i64
  switch i64 %t242, label %case.default.243 [ i64 3, label %case.arm.3.245 i64 4, label %case.arm.4.253 ]
case.arm.3.245:
  %t247 = getelementptr ptr, ptr %t239, i32 1
  %t248 = load ptr, ptr %t247
  call void @__inc_ref(ptr %t248)
  %t249 = call ptr @__alloc(i64 16, i32 1)
  %t250 = inttoptr i64 3 to ptr
  %t251 = getelementptr ptr, ptr %t249, i32 0
  store ptr %t250, ptr %t251
  call void @__inc_ref(ptr %t248)
  %t252 = getelementptr ptr, ptr %t249, i32 1
  store ptr %t248, ptr %t252
  br label %case.end.3.246
case.end.3.246:
  br label %case.join.244
case.arm.4.253:
  %t255 = getelementptr ptr, ptr %t239, i32 1
  %t256 = load ptr, ptr %t255
  call void @__inc_ref(ptr %t256)
  call void @__inc_ref(ptr %t256)
  call void @__inc_ref(ptr %t202)
  %t257 = call ptr @__concat(ptr %t256, ptr %t202)
  br label %case.end.4.254
case.end.4.254:
  br label %case.join.244
case.default.243:
  unreachable
case.join.244:
  %t258 = phi ptr [ %t249, %case.end.3.246 ], [ %t257, %case.end.4.254 ]
  call void @__free_recursive(ptr %t239)
  br label %case.end.4.236
case.end.4.236:
  br label %case.join.226
case.default.225:
  unreachable
case.join.226:
  %t259 = phi ptr [ %t231, %case.end.3.228 ], [ %t258, %case.end.4.236 ]
  call void @__free_recursive(ptr %t221)
  br label %case.end.4.218
case.end.4.218:
  br label %case.join.208
case.default.207:
  unreachable
case.join.208:
  %t260 = phi ptr [ %t213, %case.end.3.210 ], [ %t259, %case.end.4.218 ]
  call void @__free_recursive(ptr %t203)
  br label %case.end.4.200
case.end.4.200:
  br label %case.join.190
case.default.189:
  unreachable
case.join.190:
  %t261 = phi ptr [ %t195, %case.end.3.192 ], [ %t260, %case.end.4.200 ]
  call void @__free_recursive(ptr %t185)
  call void @__free_recursive(ptr %t129)
  br label %case.end.4.126
case.end.4.126:
  br label %case.join.116
case.default.115:
  unreachable
case.join.116:
  %t262 = phi ptr [ %t121, %case.end.3.118 ], [ %t261, %case.end.4.126 ]
  call void @__free_recursive(ptr %t111)
  call void @__free_recursive(ptr %t65)
  call void @__free_recursive(ptr %t2)
  call void @__free_recursive(ptr %t43)
  store ptr %t262, ptr %v__inl80_scrut.jslot
  br label %join.0
join.case.default.47:
  unreachable
join.0:
  %t263 = load ptr, ptr %v__inl80_scrut.jslot
  %t264 = getelementptr ptr, ptr %t263, i32 0
  %t265 = load ptr, ptr %t264
  %t266 = ptrtoint ptr %t265 to i64
  switch i64 %t266, label %case.default.267 [ i64 3, label %case.arm.3.269 i64 4, label %case.arm.4.283 ]
case.arm.3.269:
  %t271 = call ptr @__alloc(i64 24, i32 2)
  %t272 = inttoptr i64 7 to ptr
  %t273 = getelementptr ptr, ptr %t271, i32 0
  store ptr %t272, ptr %t273
  %t274 = getelementptr ptr, ptr %t271, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t274
  %t275 = call ptr @__alloc(i64 16, i32 1)
  %t276 = inttoptr i64 5 to ptr
  %t277 = getelementptr ptr, ptr %t275, i32 0
  store ptr %t276, ptr %t277
  %t278 = call ptr @__alloc(i64 8, i32 0)
  %t279 = inttoptr i64 0 to ptr
  %t280 = getelementptr ptr, ptr %t278, i32 0
  store ptr %t279, ptr %t280
  %t281 = getelementptr ptr, ptr %t275, i32 1
  store ptr %t278, ptr %t281
  %t282 = getelementptr ptr, ptr %t271, i32 2
  store ptr %t275, ptr %t282
  br label %case.end.3.270
case.end.3.270:
  br label %case.join.268
case.arm.4.283:
  %t285 = call ptr @__alloc(i64 24, i32 2)
  %t286 = inttoptr i64 7 to ptr
  %t287 = getelementptr ptr, ptr %t285, i32 0
  store ptr %t286, ptr %t287
  %t288 = getelementptr ptr, ptr %t263, i32 1
  %t289 = load ptr, ptr %t288
  call void @__inc_ref(ptr %t289)
  %t290 = getelementptr ptr, ptr %t285, i32 1
  store ptr %t289, ptr %t290
  %t291 = call ptr @__alloc(i64 16, i32 1)
  %t292 = inttoptr i64 5 to ptr
  %t293 = getelementptr ptr, ptr %t291, i32 0
  store ptr %t292, ptr %t293
  %t294 = call ptr @__alloc(i64 8, i32 0)
  %t295 = inttoptr i64 0 to ptr
  %t296 = getelementptr ptr, ptr %t294, i32 0
  store ptr %t295, ptr %t296
  %t297 = getelementptr ptr, ptr %t291, i32 1
  store ptr %t294, ptr %t297
  %t298 = getelementptr ptr, ptr %t285, i32 2
  store ptr %t291, ptr %t298
  br label %case.end.4.284
case.end.4.284:
  br label %case.join.268
case.default.267:
  unreachable
case.join.268:
  %t299 = phi ptr [ %t271, %case.end.3.270 ], [ %t285, %case.end.4.284 ]
  call void @__free_recursive(ptr %t263)
  br label %join.end.300
join.end.300:
  br label %join.after.1
join.after.1:
  %t301 = phi ptr [ %t49, %join.val.61 ], [ %t299, %join.end.300 ]
  ret ptr %t301
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
