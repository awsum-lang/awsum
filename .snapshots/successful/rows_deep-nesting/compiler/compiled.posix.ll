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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"=" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"\0A" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [11 x i8]} { i32 0, i32 0, i32 0, i32 11, i32 11, [11 x i8] c"directDeepT" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"N" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"L" }
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"RT" }
@.str.6 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"RF" }
@.str.7 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"RU" }
@.str.8 = private unnamed_addr constant {i32, i32, i32, i32, i32, [11 x i8]} { i32 0, i32 0, i32 0, i32 11, i32 11, [11 x i8] c"widenedDeep" }
@.str.9 = private unnamed_addr constant {i32, i32, i32, i32, i32, [11 x i8]} { i32 0, i32 0, i32 0, i32 11, i32 11, [11 x i8] c"directDeepU" }
@.str.10 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }

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

define internal ptr @v_directDeepT() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 25 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 16, i32 1)
  %t4 = inttoptr i64 12 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = call ptr @__alloc(i64 16, i32 1)
  %t7 = inttoptr i64 4 to ptr
  %t8 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t7, ptr %t8
  %t9 = call ptr @__alloc(i64 16, i32 1)
  %t10 = inttoptr i64 796142685 to ptr
  %t11 = getelementptr ptr, ptr %t9, i32 0
  store ptr %t10, ptr %t11
  %t12 = call ptr @__alloc(i64 8, i32 0)
  %t13 = inttoptr i64 1 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t9, i32 1
  store ptr %t12, ptr %t15
  %t16 = getelementptr ptr, ptr %t6, i32 1
  store ptr %t9, ptr %t16
  %t17 = getelementptr ptr, ptr %t3, i32 1
  store ptr %t6, ptr %t17
  %t18 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t18
  ret ptr %t0
}

define internal ptr @v_directDeepU() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 25 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 16, i32 1)
  %t4 = inttoptr i64 12 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = call ptr @__alloc(i64 16, i32 1)
  %t7 = inttoptr i64 4 to ptr
  %t8 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t7, ptr %t8
  %t9 = call ptr @__alloc(i64 16, i32 1)
  %t10 = inttoptr i64 1759602215 to ptr
  %t11 = getelementptr ptr, ptr %t9, i32 0
  store ptr %t10, ptr %t11
  %t12 = call ptr @__alloc(i64 8, i32 0)
  %t13 = inttoptr i64 0 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t9, i32 1
  store ptr %t12, ptr %t15
  %t16 = getelementptr ptr, ptr %t6, i32 1
  store ptr %t9, ptr %t16
  %t17 = getelementptr ptr, ptr %t3, i32 1
  store ptr %t6, ptr %t17
  %t18 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t18
  ret ptr %t0
}

define internal ptr @v_narrowDeep() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 25 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 16, i32 1)
  %t4 = inttoptr i64 12 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = call ptr @__alloc(i64 16, i32 1)
  %t7 = inttoptr i64 4 to ptr
  %t8 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t7, ptr %t8
  %t9 = call ptr @__alloc(i64 8, i32 0)
  %t10 = inttoptr i64 1 to ptr
  %t11 = getelementptr ptr, ptr %t9, i32 0
  store ptr %t10, ptr %t11
  %t12 = getelementptr ptr, ptr %t6, i32 1
  store ptr %t9, ptr %t12
  %t13 = getelementptr ptr, ptr %t3, i32 1
  store ptr %t6, ptr %t13
  %t14 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t14
  ret ptr %t0
}

define internal ptr @v_widenedDeep() {
  %t0 = call ptr @v_narrowDeep()
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 25, label %case.arm.25.6 ]
case.arm.25.6:
  %t8 = getelementptr ptr, ptr %t0, i32 1
  %t9 = load ptr, ptr %t8
  call void @__inc_ref(ptr %t9)
  %t10 = call ptr @__alloc(i64 16, i32 1)
  %t11 = inttoptr i64 25 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  %t13 = getelementptr ptr, ptr %t9, i32 0
  %t14 = load ptr, ptr %t13
  %t15 = ptrtoint ptr %t14 to i64
  switch i64 %t15, label %case.default.16 [ i64 11, label %case.arm.11.18 i64 12, label %case.arm.12.20 ]
case.arm.11.18:
  call void @__inc_ref(ptr %t9)
  br label %case.end.11.19
case.end.11.19:
  br label %case.join.17
case.arm.12.20:
  %t22 = getelementptr ptr, ptr %t9, i32 1
  %t23 = load ptr, ptr %t22
  call void @__inc_ref(ptr %t23)
  %t24 = call ptr @__alloc(i64 16, i32 1)
  %t25 = inttoptr i64 12 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = getelementptr ptr, ptr %t23, i32 0
  %t28 = load ptr, ptr %t27
  %t29 = ptrtoint ptr %t28 to i64
  switch i64 %t29, label %case.default.30 [ i64 3, label %case.arm.3.32 i64 4, label %case.arm.4.34 ]
case.arm.3.32:
  call void @__inc_ref(ptr %t23)
  br label %case.end.3.33
case.end.3.33:
  br label %case.join.31
case.arm.4.34:
  %t36 = call ptr @__alloc(i64 16, i32 1)
  %t37 = inttoptr i64 4 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = call ptr @__alloc(i64 16, i32 1)
  %t40 = inttoptr i64 796142685 to ptr
  %t41 = getelementptr ptr, ptr %t39, i32 0
  store ptr %t40, ptr %t41
  %t42 = getelementptr ptr, ptr %t23, i32 1
  %t43 = load ptr, ptr %t42
  call void @__inc_ref(ptr %t43)
  %t44 = getelementptr ptr, ptr %t39, i32 1
  store ptr %t43, ptr %t44
  %t45 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t39, ptr %t45
  br label %case.end.4.35
case.end.4.35:
  br label %case.join.31
case.default.30:
  unreachable
case.join.31:
  %t46 = phi ptr [ %t23, %case.end.3.33 ], [ %t36, %case.end.4.35 ]
  %t47 = getelementptr ptr, ptr %t24, i32 1
  store ptr %t46, ptr %t47
  br label %case.end.12.21
case.end.12.21:
  br label %case.join.17
case.default.16:
  unreachable
case.join.17:
  %t48 = phi ptr [ %t9, %case.end.11.19 ], [ %t24, %case.end.12.21 ]
  %t49 = getelementptr ptr, ptr %t10, i32 1
  store ptr %t48, ptr %t49
  br label %case.end.25.7
case.end.25.7:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t50 = phi ptr [ %t10, %case.end.25.7 ]
  call void @__free_recursive(ptr %t0)
  ret ptr %t50
}

define internal ptr @v_tagged(ptr %v_label, ptr %v_val) {
  call void @__inc_ref(ptr %v_label)
  %t0 = call ptr @__concat(ptr %v_label, ptr getelementptr inbounds (i8, ptr @.str.0, i64 12))
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 3, label %case.arm.3.5 i64 4, label %case.arm.4.12 ]
case.arm.3.5:
  %t6 = getelementptr ptr, ptr %t0, i32 1
  %t7 = load ptr, ptr %t6
  call void @__inc_ref(ptr %t7)
  %t8 = call ptr @__alloc(i64 16, i32 1)
  %t9 = inttoptr i64 3 to ptr
  %t10 = getelementptr ptr, ptr %t8, i32 0
  store ptr %t9, ptr %t10
  call void @__inc_ref(ptr %t7)
  %t11 = getelementptr ptr, ptr %t8, i32 1
  store ptr %t7, ptr %t11
  call void @__free_recursive(ptr %t0)
  call void @__free_recursive(ptr %t7)
  call void @__free_recursive(ptr %v_label)
  call void @__free_recursive(ptr %v_val)
  ret ptr %t8
case.arm.4.12:
  %t13 = getelementptr ptr, ptr %t0, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  call void @__inc_ref(ptr %t14)
  call void @__inc_ref(ptr %v_val)
  %t15 = call ptr @__concat(ptr %t14, ptr %v_val)
  %t16 = getelementptr ptr, ptr %t15, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %case.default.19 [ i64 3, label %case.arm.3.20 i64 4, label %case.arm.4.27 ]
case.arm.3.20:
  %t21 = getelementptr ptr, ptr %t15, i32 1
  %t22 = load ptr, ptr %t21
  call void @__inc_ref(ptr %t22)
  %t23 = call ptr @__alloc(i64 16, i32 1)
  %t24 = inttoptr i64 3 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  call void @__inc_ref(ptr %t22)
  %t26 = getelementptr ptr, ptr %t23, i32 1
  store ptr %t22, ptr %t26
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t0)
  call void @__free_recursive(ptr %t22)
  call void @__free_recursive(ptr %t14)
  call void @__free_recursive(ptr %v_label)
  call void @__free_recursive(ptr %v_val)
  ret ptr %t23
case.arm.4.27:
  %t28 = getelementptr ptr, ptr %t15, i32 1
  %t29 = load ptr, ptr %t28
  call void @__inc_ref(ptr %t29)
  call void @__inc_ref(ptr %t29)
  %t30 = call ptr @__concat(ptr %t29, ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t0)
  call void @__free_recursive(ptr %t29)
  call void @__free_recursive(ptr %t14)
  call void @__free_recursive(ptr %v_label)
  call void @__free_recursive(ptr %v_val)
  ret ptr %t30
case.default.19:
  unreachable
case.default.4:
  unreachable
}

define internal ptr @v_render() {
  %v_$inl33$scrut.jslot = alloca ptr
  %t0 = call ptr @v_directDeepT()
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 25, label %case.arm.25.6 ]
case.arm.25.6:
  %t8 = getelementptr ptr, ptr %t0, i32 1
  %t9 = load ptr, ptr %t8
  call void @__inc_ref(ptr %t9)
  %t10 = getelementptr ptr, ptr %t9, i32 0
  %t11 = load ptr, ptr %t10
  %t12 = ptrtoint ptr %t11 to i64
  switch i64 %t12, label %case.default.13 [ i64 11, label %case.arm.11.15 i64 12, label %case.arm.12.17 ]
case.arm.11.15:
  br label %case.end.11.16
case.end.11.16:
  br label %case.join.14
case.arm.12.17:
  %t19 = getelementptr ptr, ptr %t9, i32 1
  %t20 = load ptr, ptr %t19
  call void @__inc_ref(ptr %t20)
  %t21 = getelementptr ptr, ptr %t20, i32 0
  %t22 = load ptr, ptr %t21
  %t23 = ptrtoint ptr %t22 to i64
  switch i64 %t23, label %case.default.24 [ i64 3, label %case.arm.3.26 i64 4, label %case.arm.4.28 ]
case.arm.3.26:
  br label %case.end.3.27
case.end.3.27:
  br label %case.join.25
case.arm.4.28:
  %t30 = getelementptr ptr, ptr %t20, i32 1
  %t31 = load ptr, ptr %t30
  call void @__inc_ref(ptr %t31)
  %t32 = getelementptr ptr, ptr %t31, i32 0
  %t33 = load ptr, ptr %t32
  %t34 = ptrtoint ptr %t33 to i64
  switch i64 %t34, label %case.default.35 [ i64 796142685, label %case.arm.796142685.37 i64 1759602215, label %case.arm.1759602215.51 ]
case.arm.796142685.37:
  %t39 = getelementptr ptr, ptr %t31, i32 1
  %t40 = load ptr, ptr %t39
  call void @__inc_ref(ptr %t40)
  %t41 = getelementptr ptr, ptr %t40, i32 0
  %t42 = load ptr, ptr %t41
  %t43 = ptrtoint ptr %t42 to i64
  switch i64 %t43, label %case.default.44 [ i64 1, label %case.arm.1.46 i64 2, label %case.arm.2.48 ]
case.arm.1.46:
  br label %case.end.1.47
case.end.1.47:
  br label %case.join.45
case.arm.2.48:
  br label %case.end.2.49
case.end.2.49:
  br label %case.join.45
case.default.44:
  unreachable
case.join.45:
  %t50 = phi ptr [ getelementptr inbounds (i8, ptr @.str.5, i64 12), %case.end.1.47 ], [ getelementptr inbounds (i8, ptr @.str.6, i64 12), %case.end.2.49 ]
  call void @__free_recursive(ptr %t40)
  br label %case.end.796142685.38
case.end.796142685.38:
  br label %case.join.36
case.arm.1759602215.51:
  br label %case.end.1759602215.52
case.end.1759602215.52:
  br label %case.join.36
case.default.35:
  unreachable
case.join.36:
  %t53 = phi ptr [ %t50, %case.end.796142685.38 ], [ getelementptr inbounds (i8, ptr @.str.7, i64 12), %case.end.1759602215.52 ]
  br label %case.end.4.29
case.end.4.29:
  br label %case.join.25
case.default.24:
  unreachable
case.join.25:
  %t54 = phi ptr [ getelementptr inbounds (i8, ptr @.str.4, i64 12), %case.end.3.27 ], [ %t53, %case.end.4.29 ]
  call void @__free_recursive(ptr %t20)
  br label %case.end.12.18
case.end.12.18:
  br label %case.join.14
case.default.13:
  unreachable
case.join.14:
  %t55 = phi ptr [ getelementptr inbounds (i8, ptr @.str.3, i64 12), %case.end.11.16 ], [ %t54, %case.end.12.18 ]
  br label %case.end.25.7
case.end.25.7:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t56 = phi ptr [ %t55, %case.end.25.7 ]
  call void @__free_recursive(ptr %t0)
  %t57 = call ptr @v_tagged(ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t56)
  %t58 = getelementptr ptr, ptr %t57, i32 0
  %t59 = load ptr, ptr %t58
  %t60 = ptrtoint ptr %t59 to i64
  switch i64 %t60, label %case.default.61 [ i64 3, label %case.arm.3.63 i64 4, label %case.arm.4.71 ]
case.arm.3.63:
  %t65 = getelementptr ptr, ptr %t57, i32 1
  %t66 = load ptr, ptr %t65
  call void @__inc_ref(ptr %t66)
  %t67 = call ptr @__alloc(i64 16, i32 1)
  %t68 = inttoptr i64 3 to ptr
  %t69 = getelementptr ptr, ptr %t67, i32 0
  store ptr %t68, ptr %t69
  call void @__inc_ref(ptr %t66)
  %t70 = getelementptr ptr, ptr %t67, i32 1
  store ptr %t66, ptr %t70
  br label %case.end.3.64
case.end.3.64:
  br label %case.join.62
case.arm.4.71:
  %t73 = getelementptr ptr, ptr %t57, i32 1
  %t74 = load ptr, ptr %t73
  call void @__inc_ref(ptr %t74)
  %t77 = call ptr @v_directDeepU()
  %t78 = getelementptr ptr, ptr %t77, i32 0
  %t79 = load ptr, ptr %t78
  %t80 = ptrtoint ptr %t79 to i64
  switch i64 %t80, label %case.default.81 [ i64 25, label %case.arm.25.83 ]
case.arm.25.83:
  %t85 = getelementptr ptr, ptr %t77, i32 1
  %t86 = load ptr, ptr %t85
  call void @__inc_ref(ptr %t86)
  %t87 = getelementptr ptr, ptr %t86, i32 0
  %t88 = load ptr, ptr %t87
  %t89 = ptrtoint ptr %t88 to i64
  switch i64 %t89, label %case.default.90 [ i64 11, label %case.arm.11.92 i64 12, label %case.arm.12.94 ]
case.arm.11.92:
  br label %case.end.11.93
case.end.11.93:
  br label %case.join.91
case.arm.12.94:
  %t96 = getelementptr ptr, ptr %t86, i32 1
  %t97 = load ptr, ptr %t96
  call void @__inc_ref(ptr %t97)
  %t98 = getelementptr ptr, ptr %t97, i32 0
  %t99 = load ptr, ptr %t98
  %t100 = ptrtoint ptr %t99 to i64
  switch i64 %t100, label %case.default.101 [ i64 3, label %case.arm.3.103 i64 4, label %case.arm.4.105 ]
case.arm.3.103:
  br label %case.end.3.104
case.end.3.104:
  br label %case.join.102
case.arm.4.105:
  %t107 = getelementptr ptr, ptr %t97, i32 1
  %t108 = load ptr, ptr %t107
  call void @__inc_ref(ptr %t108)
  %t109 = getelementptr ptr, ptr %t108, i32 0
  %t110 = load ptr, ptr %t109
  %t111 = ptrtoint ptr %t110 to i64
  switch i64 %t111, label %case.default.112 [ i64 796142685, label %case.arm.796142685.114 i64 1759602215, label %case.arm.1759602215.128 ]
case.arm.796142685.114:
  %t116 = getelementptr ptr, ptr %t108, i32 1
  %t117 = load ptr, ptr %t116
  call void @__inc_ref(ptr %t117)
  %t118 = getelementptr ptr, ptr %t117, i32 0
  %t119 = load ptr, ptr %t118
  %t120 = ptrtoint ptr %t119 to i64
  switch i64 %t120, label %case.default.121 [ i64 1, label %case.arm.1.123 i64 2, label %case.arm.2.125 ]
case.arm.1.123:
  br label %case.end.1.124
case.end.1.124:
  br label %case.join.122
case.arm.2.125:
  br label %case.end.2.126
case.end.2.126:
  br label %case.join.122
case.default.121:
  unreachable
case.join.122:
  %t127 = phi ptr [ getelementptr inbounds (i8, ptr @.str.5, i64 12), %case.end.1.124 ], [ getelementptr inbounds (i8, ptr @.str.6, i64 12), %case.end.2.126 ]
  call void @__free_recursive(ptr %t117)
  br label %case.end.796142685.115
case.end.796142685.115:
  br label %case.join.113
case.arm.1759602215.128:
  br label %case.end.1759602215.129
case.end.1759602215.129:
  br label %case.join.113
case.default.112:
  unreachable
case.join.113:
  %t130 = phi ptr [ %t127, %case.end.796142685.115 ], [ getelementptr inbounds (i8, ptr @.str.7, i64 12), %case.end.1759602215.129 ]
  br label %case.end.4.106
case.end.4.106:
  br label %case.join.102
case.default.101:
  unreachable
case.join.102:
  %t131 = phi ptr [ getelementptr inbounds (i8, ptr @.str.4, i64 12), %case.end.3.104 ], [ %t130, %case.end.4.106 ]
  call void @__free_recursive(ptr %t97)
  br label %case.end.12.95
case.end.12.95:
  br label %case.join.91
case.default.90:
  unreachable
case.join.91:
  %t132 = phi ptr [ getelementptr inbounds (i8, ptr @.str.3, i64 12), %case.end.11.93 ], [ %t131, %case.end.12.95 ]
  br label %case.end.25.84
case.end.25.84:
  br label %case.join.82
case.default.81:
  unreachable
case.join.82:
  %t133 = phi ptr [ %t132, %case.end.25.84 ]
  call void @__free_recursive(ptr %t77)
  %t134 = call ptr @v_tagged(ptr getelementptr inbounds (i8, ptr @.str.9, i64 12), ptr %t133)
  %t135 = getelementptr ptr, ptr %t134, i32 0
  %t136 = load ptr, ptr %t135
  %t137 = ptrtoint ptr %t136 to i64
  switch i64 %t137, label %join.case.default.138 [ i64 3, label %join.case.arm.3.139 i64 4, label %join.case.arm.4.147 ]
join.case.arm.3.139:
  %t140 = getelementptr ptr, ptr %t134, i32 1
  %t141 = load ptr, ptr %t140
  call void @__inc_ref(ptr %t141)
  %t142 = call ptr @__alloc(i64 16, i32 1)
  %t143 = inttoptr i64 3 to ptr
  %t144 = getelementptr ptr, ptr %t142, i32 0
  store ptr %t143, ptr %t144
  call void @__inc_ref(ptr %t141)
  %t145 = getelementptr ptr, ptr %t142, i32 1
  store ptr %t141, ptr %t145
  call void @__free_recursive(ptr %t134)
  br label %join.val.146
join.val.146:
  br label %join.after.76
join.case.arm.4.147:
  %t148 = getelementptr ptr, ptr %t134, i32 1
  %t149 = load ptr, ptr %t148
  call void @__inc_ref(ptr %t149)
  call void @__inc_ref(ptr %t74)
  call void @__inc_ref(ptr %t149)
  %t150 = call ptr @__concat(ptr %t74, ptr %t149)
  call void @__free_recursive(ptr %t134)
  store ptr %t150, ptr %v_$inl33$scrut.jslot
  br label %join.75
join.case.default.138:
  unreachable
join.75:
  %t151 = load ptr, ptr %v_$inl33$scrut.jslot
  %t152 = getelementptr ptr, ptr %t151, i32 0
  %t153 = load ptr, ptr %t152
  %t154 = ptrtoint ptr %t153 to i64
  switch i64 %t154, label %case.default.155 [ i64 3, label %case.arm.3.157 i64 4, label %case.arm.4.159 ]
case.arm.3.157:
  call void @__inc_ref(ptr %t151)
  br label %case.end.3.158
case.end.3.158:
  br label %case.join.156
case.arm.4.159:
  %t161 = call ptr @v_widenedDeep()
  %t162 = getelementptr ptr, ptr %t161, i32 0
  %t163 = load ptr, ptr %t162
  %t164 = ptrtoint ptr %t163 to i64
  switch i64 %t164, label %case.default.165 [ i64 25, label %case.arm.25.167 ]
case.arm.25.167:
  %t169 = getelementptr ptr, ptr %t161, i32 1
  %t170 = load ptr, ptr %t169
  call void @__inc_ref(ptr %t170)
  %t171 = getelementptr ptr, ptr %t170, i32 0
  %t172 = load ptr, ptr %t171
  %t173 = ptrtoint ptr %t172 to i64
  switch i64 %t173, label %case.default.174 [ i64 11, label %case.arm.11.176 i64 12, label %case.arm.12.178 ]
case.arm.11.176:
  br label %case.end.11.177
case.end.11.177:
  br label %case.join.175
case.arm.12.178:
  %t180 = getelementptr ptr, ptr %t170, i32 1
  %t181 = load ptr, ptr %t180
  call void @__inc_ref(ptr %t181)
  %t182 = getelementptr ptr, ptr %t181, i32 0
  %t183 = load ptr, ptr %t182
  %t184 = ptrtoint ptr %t183 to i64
  switch i64 %t184, label %case.default.185 [ i64 3, label %case.arm.3.187 i64 4, label %case.arm.4.189 ]
case.arm.3.187:
  br label %case.end.3.188
case.end.3.188:
  br label %case.join.186
case.arm.4.189:
  %t191 = getelementptr ptr, ptr %t181, i32 1
  %t192 = load ptr, ptr %t191
  call void @__inc_ref(ptr %t192)
  %t193 = getelementptr ptr, ptr %t192, i32 0
  %t194 = load ptr, ptr %t193
  %t195 = ptrtoint ptr %t194 to i64
  switch i64 %t195, label %case.default.196 [ i64 796142685, label %case.arm.796142685.198 i64 1759602215, label %case.arm.1759602215.212 ]
case.arm.796142685.198:
  %t200 = getelementptr ptr, ptr %t192, i32 1
  %t201 = load ptr, ptr %t200
  call void @__inc_ref(ptr %t201)
  %t202 = getelementptr ptr, ptr %t201, i32 0
  %t203 = load ptr, ptr %t202
  %t204 = ptrtoint ptr %t203 to i64
  switch i64 %t204, label %case.default.205 [ i64 1, label %case.arm.1.207 i64 2, label %case.arm.2.209 ]
case.arm.1.207:
  br label %case.end.1.208
case.end.1.208:
  br label %case.join.206
case.arm.2.209:
  br label %case.end.2.210
case.end.2.210:
  br label %case.join.206
case.default.205:
  unreachable
case.join.206:
  %t211 = phi ptr [ getelementptr inbounds (i8, ptr @.str.5, i64 12), %case.end.1.208 ], [ getelementptr inbounds (i8, ptr @.str.6, i64 12), %case.end.2.210 ]
  call void @__free_recursive(ptr %t201)
  br label %case.end.796142685.199
case.end.796142685.199:
  br label %case.join.197
case.arm.1759602215.212:
  br label %case.end.1759602215.213
case.end.1759602215.213:
  br label %case.join.197
case.default.196:
  unreachable
case.join.197:
  %t214 = phi ptr [ %t211, %case.end.796142685.199 ], [ getelementptr inbounds (i8, ptr @.str.7, i64 12), %case.end.1759602215.213 ]
  call void @__free_recursive(ptr %t192)
  br label %case.end.4.190
case.end.4.190:
  br label %case.join.186
case.default.185:
  unreachable
case.join.186:
  %t215 = phi ptr [ getelementptr inbounds (i8, ptr @.str.4, i64 12), %case.end.3.188 ], [ %t214, %case.end.4.190 ]
  call void @__free_recursive(ptr %t181)
  br label %case.end.12.179
case.end.12.179:
  br label %case.join.175
case.default.174:
  unreachable
case.join.175:
  %t216 = phi ptr [ getelementptr inbounds (i8, ptr @.str.3, i64 12), %case.end.11.177 ], [ %t215, %case.end.12.179 ]
  call void @__free_recursive(ptr %t170)
  br label %case.end.25.168
case.end.25.168:
  br label %case.join.166
case.default.165:
  unreachable
case.join.166:
  %t217 = phi ptr [ %t216, %case.end.25.168 ]
  call void @__free_recursive(ptr %t161)
  %t218 = call ptr @v_tagged(ptr getelementptr inbounds (i8, ptr @.str.8, i64 12), ptr %t217)
  %t219 = getelementptr ptr, ptr %t218, i32 0
  %t220 = load ptr, ptr %t219
  %t221 = ptrtoint ptr %t220 to i64
  switch i64 %t221, label %case.default.222 [ i64 3, label %case.arm.3.224 i64 4, label %case.arm.4.232 ]
case.arm.3.224:
  %t226 = getelementptr ptr, ptr %t218, i32 1
  %t227 = load ptr, ptr %t226
  call void @__inc_ref(ptr %t227)
  %t228 = call ptr @__alloc(i64 16, i32 1)
  %t229 = inttoptr i64 3 to ptr
  %t230 = getelementptr ptr, ptr %t228, i32 0
  store ptr %t229, ptr %t230
  call void @__inc_ref(ptr %t227)
  %t231 = getelementptr ptr, ptr %t228, i32 1
  store ptr %t227, ptr %t231
  call void @__free_recursive(ptr %t227)
  br label %case.end.3.225
case.end.3.225:
  br label %case.join.223
case.arm.4.232:
  %t234 = getelementptr ptr, ptr %t218, i32 1
  %t235 = load ptr, ptr %t234
  call void @__inc_ref(ptr %t235)
  %t236 = getelementptr ptr, ptr %t151, i32 1
  %t237 = load ptr, ptr %t236
  call void @__inc_ref(ptr %t237)
  call void @__inc_ref(ptr %t235)
  %t238 = call ptr @__concat(ptr %t237, ptr %t235)
  call void @__free_recursive(ptr %t235)
  br label %case.end.4.233
case.end.4.233:
  br label %case.join.223
case.default.222:
  unreachable
case.join.223:
  %t239 = phi ptr [ %t228, %case.end.3.225 ], [ %t238, %case.end.4.233 ]
  call void @__free_recursive(ptr %t218)
  br label %case.end.4.160
case.end.4.160:
  br label %case.join.156
case.default.155:
  unreachable
case.join.156:
  %t240 = phi ptr [ %t151, %case.end.3.158 ], [ %t239, %case.end.4.160 ]
  call void @__free_recursive(ptr %t151)
  br label %join.end.241
join.end.241:
  br label %join.after.76
join.after.76:
  %t242 = phi ptr [ %t142, %join.val.146 ], [ %t240, %join.end.241 ]
  br label %case.end.4.72
case.end.4.72:
  br label %case.join.62
case.default.61:
  unreachable
case.join.62:
  %t243 = phi ptr [ %t67, %case.end.3.64 ], [ %t242, %case.end.4.72 ]
  call void @__free_recursive(ptr %t57)
  ret ptr %t243
}

define internal ptr @v_main() {
  %t0 = call ptr @v_render()
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
  %t24 = inttoptr i64 28 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  %t26 = call ptr @v_$cps$$df$andThenIO$4(ptr %t22, ptr %t23)
  %t27 = call ptr @__alloc(i64 8, i32 0)
  %t28 = inttoptr i64 26 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  %t30 = call ptr @v_$cps$$df$handleErrorIO$0(ptr %t26, ptr %t27)
  ret ptr %t30
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
  store ptr getelementptr inbounds (i8, ptr @.str.10, i64 12), ptr %t17
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
  %t36 = inttoptr i64 27 to ptr
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
  %t47 = inttoptr i64 27 to ptr
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
  %t26 = call ptr @v_$apply$$df$andThenIO$4(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t26, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.27:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t28 = call ptr @v_$apply$$df$andThenIO$4(ptr %t6, ptr %t5)
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
  %t38 = inttoptr i64 29 to ptr
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
  %t49 = inttoptr i64 29 to ptr
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
  call void @__free_recursive(ptr %t6)
  store ptr %t33, ptr %t3
  store ptr %t53, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t54 = load ptr, ptr %t2
  ret ptr %t54
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
  switch i64 %t9, label %tco.case.default.10 [ i64 28, label %tco.case.arm.28.11 i64 29, label %tco.case.arm.29.12 ]
tco.case.arm.28.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.29.12:
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
