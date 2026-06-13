; External C declarations
declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare ptr @memcpy(ptr, ptr, i64)
declare i64 @write(i32, ptr, i64)
declare i32 @snprintf(ptr, i64, ptr, ...)

@.fmt_u8 = private unnamed_addr constant [3 x i8] c"%u\00"

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
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"none" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [8 x i8]} { i32 0, i32 0, i32 0, i32 8, i32 8, [8 x i8] c"OVERFLOW" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"|" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [8 x i8]} { i32 0, i32 0, i32 0, i32 8, i32 8, [8 x i8] c"TOO_LONG" }

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


define internal ptr @__showUInt32(ptr %p) {
  %v = load i32, ptr %p
  %buf = call ptr @__alloc(i64 24, i32 0)
  %payload = getelementptr i8, ptr %buf, i64 8
  %n = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %payload, i64 16, ptr @.fmt_u8, i32 %v)
  store i32 %n, ptr %buf
  %u16p = getelementptr i8, ptr %buf, i64 4
  store i32 %n, ptr %u16p
  call void @__free_recursive(ptr %p)
  ret ptr %buf
}


define internal ptr @__eqUInt32(ptr %a, ptr %b) {
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


define internal ptr @__addUInt32(ptr %pa, ptr %pb) {
  %a = load i32, ptr %pa
  %b = load i32, ptr %pb
  %a64 = zext i32 %a to i64
  %b64 = zext i32 %b to i64
  %sum64 = add i64 %a64, %b64
  %ovf = icmp ugt i64 %sum64, 4294967295
  br i1 %ovf, label %err, label %ok
err:
  %oe = call ptr @__alloc(i64 8, i32 0)
  %oe_tag = inttoptr i64 18 to ptr
  store ptr %oe_tag, ptr %oe
  %left = call ptr @__alloc(i64 16, i32 1)
  %left_tag = inttoptr i64 3 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %oe, ptr %left_f
  br label %join
ok:
  %newv = trunc i64 %sum64 to i32
  %box = call ptr @__alloc(i64 4, i32 0)
  store i32 %newv, ptr %box
  %right = call ptr @__alloc(i64 16, i32 1)
  %right_tag = inttoptr i64 4 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %box, ptr %right_f
  br label %join
join:
  %result = phi ptr [ %left, %err ], [ %right, %ok ]
  call void @__free_recursive(ptr %pa)
  call void @__free_recursive(ptr %pb)
  ret ptr %result
}


define internal ptr @__subUInt32(ptr %pa, ptr %pb) {
  %a = load i32, ptr %pa
  %b = load i32, ptr %pb
  %unf = icmp ult i32 %a, %b
  br i1 %unf, label %err, label %ok
err:
  %ue = call ptr @__alloc(i64 8, i32 0)
  %ue_tag = inttoptr i64 17 to ptr
  store ptr %ue_tag, ptr %ue
  %left = call ptr @__alloc(i64 16, i32 1)
  %left_tag = inttoptr i64 3 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %ue, ptr %left_f
  br label %join
ok:
  %newv = sub i32 %a, %b
  %box = call ptr @__alloc(i64 4, i32 0)
  store i32 %newv, ptr %box
  %right = call ptr @__alloc(i64 16, i32 1)
  %right_tag = inttoptr i64 4 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %box, ptr %right_f
  br label %join
join:
  %result = phi ptr [ %left, %err ], [ %right, %ok ]
  call void @__free_recursive(ptr %pa)
  call void @__free_recursive(ptr %pb)
  ret ptr %result
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

define internal ptr @v_swap(ptr %v_n, ptr %v_a, ptr %v_b) {
entry:
  %t3 = alloca ptr
  store ptr %v_n, ptr %t3
  %t4 = alloca ptr
  store ptr %v_a, ptr %t4
  %t5 = alloca ptr
  store ptr %v_b, ptr %t5
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t6 = load ptr, ptr %t3
  %t7 = load ptr, ptr %t4
  %t8 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t9 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t9
  %t10 = call ptr @__eqUInt32(ptr %t6, ptr %t9)
  %t11 = getelementptr ptr, ptr %t10, i32 0
  %t12 = load ptr, ptr %t11
  %t13 = ptrtoint ptr %t12 to i64
  switch i64 %t13, label %tco.case.default.14 [ i64 1, label %tco.case.arm.1.15 i64 2, label %tco.case.arm.2.17 ]
tco.case.arm.1.15:
  call void @__inc_ref(ptr %t7)
  %t16 = call ptr @__showUInt32(ptr %t7)
  call void @__free_recursive(ptr %t10)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t7)
  call void @__free_recursive(ptr %t8)
  store ptr %t16, ptr %t2
  br label %tco.exit.1
tco.case.arm.2.17:
  call void @__inc_ref(ptr %t6)
  %t18 = call ptr @__alloc(i64 4, i32 0)
  store i32 1, ptr %t18
  %t19 = call ptr @__subUInt32(ptr %t6, ptr %t18)
  %t20 = getelementptr ptr, ptr %t19, i32 0
  %t21 = load ptr, ptr %t20
  %t22 = ptrtoint ptr %t21 to i64
  switch i64 %t22, label %tco.case.default.23 [ i64 3, label %tco.case.arm.3.24 i64 4, label %tco.case.arm.4.25 ]
tco.case.arm.3.24:
  call void @__free_recursive(ptr %t19)
  call void @__free_recursive(ptr %t10)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t7)
  call void @__free_recursive(ptr %t8)
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t2
  br label %tco.exit.1
tco.case.arm.4.25:
  %t26 = getelementptr ptr, ptr %t19, i32 1
  %t27 = load ptr, ptr %t26
  call void @__inc_ref(ptr %t27)
  call void @__inc_ref(ptr %t27)
  call void @__inc_ref(ptr %t8)
  call void @__inc_ref(ptr %t7)
  call void @__free_recursive(ptr %t19)
  call void @__free_recursive(ptr %t10)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t7)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t27)
  store ptr %t27, ptr %t3
  store ptr %t8, ptr %t4
  store ptr %t7, ptr %t5
  br label %tco.loop.0
tco.case.default.23:
  unreachable
tco.case.default.14:
  unreachable
tco.exit.1:
  %t28 = load ptr, ptr %t2
  ret ptr %t28
}

define internal ptr @v_wrap(ptr %v_n, ptr %v_d, ptr %v_acc) {
entry:
  %t3 = alloca ptr
  store ptr %v_n, ptr %t3
  %t4 = alloca ptr
  store ptr %v_d, ptr %t4
  %t5 = alloca ptr
  store ptr %v_acc, ptr %t5
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t6 = load ptr, ptr %t3
  %t7 = load ptr, ptr %t4
  %t8 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t9 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t9
  %t10 = call ptr @__eqUInt32(ptr %t6, ptr %t9)
  %t11 = getelementptr ptr, ptr %t10, i32 0
  %t12 = load ptr, ptr %t11
  %t13 = ptrtoint ptr %t12 to i64
  switch i64 %t13, label %tco.case.default.14 [ i64 1, label %tco.case.arm.1.15 i64 2, label %tco.case.arm.2.25 ]
tco.case.arm.1.15:
  %t16 = getelementptr ptr, ptr %t8, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %tco.case.default.19 [ i64 13, label %tco.case.arm.13.20 i64 14, label %tco.case.arm.14.21 ]
tco.case.arm.13.20:
  call void @__free_recursive(ptr %t10)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t7)
  call void @__free_recursive(ptr %t8)
  store ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t2
  br label %tco.exit.1
tco.case.arm.14.21:
  %t22 = getelementptr ptr, ptr %t8, i32 1
  %t23 = load ptr, ptr %t22
  call void @__inc_ref(ptr %t23)
  %t24 = call ptr @__showUInt32(ptr %t23)
  call void @__free_recursive(ptr %t10)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t7)
  call void @__free_recursive(ptr %t8)
  store ptr %t24, ptr %t2
  br label %tco.exit.1
tco.case.default.19:
  unreachable
tco.case.arm.2.25:
  call void @__inc_ref(ptr %t6)
  %t26 = call ptr @__alloc(i64 4, i32 0)
  store i32 1, ptr %t26
  %t27 = call ptr @__subUInt32(ptr %t6, ptr %t26)
  %t28 = getelementptr ptr, ptr %t27, i32 0
  %t29 = load ptr, ptr %t28
  %t30 = ptrtoint ptr %t29 to i64
  switch i64 %t30, label %tco.case.default.31 [ i64 3, label %tco.case.arm.3.32 i64 4, label %tco.case.arm.4.33 ]
tco.case.arm.3.32:
  call void @__free_recursive(ptr %t27)
  call void @__free_recursive(ptr %t10)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t7)
  call void @__free_recursive(ptr %t8)
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t2
  br label %tco.exit.1
tco.case.arm.4.33:
  %t34 = getelementptr ptr, ptr %t27, i32 1
  %t35 = load ptr, ptr %t34
  call void @__inc_ref(ptr %t35)
  %t36 = call ptr @__alloc(i64 24, i32 2)
  %t37 = inttoptr i64 14 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  call void @__inc_ref(ptr %t7)
  %t39 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t7, ptr %t39
  call void @__inc_ref(ptr %t8)
  %t40 = getelementptr ptr, ptr %t36, i32 2
  store ptr %t8, ptr %t40
  call void @__inc_ref(ptr %t35)
  call void @__inc_ref(ptr %t35)
  call void @__free_recursive(ptr %t27)
  call void @__free_recursive(ptr %t10)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t7)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t35)
  store ptr %t35, ptr %t3
  store ptr %t35, ptr %t4
  store ptr %t36, ptr %t5
  br label %tco.loop.0
tco.case.default.31:
  unreachable
tco.case.default.14:
  unreachable
tco.exit.1:
  %t41 = load ptr, ptr %t2
  ret ptr %t41
}

define internal ptr @v_fib(ptr %v_n, ptr %v_a, ptr %v_b) {
entry:
  %t3 = alloca ptr
  store ptr %v_n, ptr %t3
  %t4 = alloca ptr
  store ptr %v_a, ptr %t4
  %t5 = alloca ptr
  store ptr %v_b, ptr %t5
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t6 = load ptr, ptr %t3
  %t7 = load ptr, ptr %t4
  %t8 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t9 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t9
  %t10 = call ptr @__eqUInt32(ptr %t6, ptr %t9)
  %t11 = getelementptr ptr, ptr %t10, i32 0
  %t12 = load ptr, ptr %t11
  %t13 = ptrtoint ptr %t12 to i64
  switch i64 %t13, label %tco.case.default.14 [ i64 1, label %tco.case.arm.1.15 i64 2, label %tco.case.arm.2.17 ]
tco.case.arm.1.15:
  call void @__inc_ref(ptr %t7)
  %t16 = call ptr @__showUInt32(ptr %t7)
  call void @__free_recursive(ptr %t10)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t7)
  call void @__free_recursive(ptr %t8)
  store ptr %t16, ptr %t2
  br label %tco.exit.1
tco.case.arm.2.17:
  call void @__inc_ref(ptr %t7)
  call void @__inc_ref(ptr %t8)
  %t18 = call ptr @__addUInt32(ptr %t7, ptr %t8)
  %t19 = getelementptr ptr, ptr %t18, i32 0
  %t20 = load ptr, ptr %t19
  %t21 = ptrtoint ptr %t20 to i64
  switch i64 %t21, label %tco.case.default.22 [ i64 3, label %tco.case.arm.3.23 i64 4, label %tco.case.arm.4.24 ]
tco.case.arm.3.23:
  call void @__free_recursive(ptr %t18)
  call void @__free_recursive(ptr %t10)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t7)
  call void @__free_recursive(ptr %t8)
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t2
  br label %tco.exit.1
tco.case.arm.4.24:
  %t25 = getelementptr ptr, ptr %t18, i32 1
  %t26 = load ptr, ptr %t25
  call void @__inc_ref(ptr %t26)
  call void @__inc_ref(ptr %t6)
  %t27 = call ptr @__alloc(i64 4, i32 0)
  store i32 1, ptr %t27
  %t28 = call ptr @__subUInt32(ptr %t6, ptr %t27)
  %t29 = getelementptr ptr, ptr %t28, i32 0
  %t30 = load ptr, ptr %t29
  %t31 = ptrtoint ptr %t30 to i64
  switch i64 %t31, label %tco.case.default.32 [ i64 3, label %tco.case.arm.3.33 i64 4, label %tco.case.arm.4.34 ]
tco.case.arm.3.33:
  call void @__free_recursive(ptr %t28)
  call void @__free_recursive(ptr %t18)
  call void @__free_recursive(ptr %t10)
  call void @__free_recursive(ptr %t26)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t7)
  call void @__free_recursive(ptr %t8)
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t2
  br label %tco.exit.1
tco.case.arm.4.34:
  %t35 = getelementptr ptr, ptr %t28, i32 1
  %t36 = load ptr, ptr %t35
  call void @__inc_ref(ptr %t36)
  call void @__inc_ref(ptr %t36)
  call void @__inc_ref(ptr %t8)
  call void @__inc_ref(ptr %t26)
  call void @__free_recursive(ptr %t28)
  call void @__free_recursive(ptr %t18)
  call void @__free_recursive(ptr %t10)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t7)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t36)
  call void @__free_recursive(ptr %t26)
  store ptr %t36, ptr %t3
  store ptr %t8, ptr %t4
  store ptr %t26, ptr %t5
  br label %tco.loop.0
tco.case.default.32:
  unreachable
tco.case.default.22:
  unreachable
tco.case.default.14:
  unreachable
tco.exit.1:
  %t37 = load ptr, ptr %t2
  ret ptr %t37
}

define internal ptr @v_main() {
  %t0 = call ptr @__alloc(i64 4, i32 0)
  store i32 5, ptr %t0
  %t1 = call ptr @__alloc(i64 4, i32 0)
  store i32 7, ptr %t1
  %t2 = call ptr @__alloc(i64 4, i32 0)
  store i32 9, ptr %t2
  %t3 = call ptr @v_swap(ptr %t0, ptr %t1, ptr %t2)
  %t4 = call ptr @__concat(ptr %t3, ptr getelementptr inbounds (i8, ptr @.str.3, i64 12))
  %t5 = getelementptr ptr, ptr %t4, i32 0
  %t6 = load ptr, ptr %t5
  %t7 = ptrtoint ptr %t6 to i64
  switch i64 %t7, label %case.default.8 [ i64 3, label %case.arm.3.10 i64 4, label %case.arm.4.24 ]
case.arm.3.10:
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t15
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 5 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = call ptr @__alloc(i64 8, i32 0)
  %t20 = inttoptr i64 0 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t19, ptr %t22
  %t23 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t16, ptr %t23
  br label %case.end.3.11
case.end.3.11:
  br label %case.join.9
case.arm.4.24:
  %t26 = getelementptr ptr, ptr %t4, i32 1
  %t27 = load ptr, ptr %t26
  call void @__inc_ref(ptr %t27)
  call void @__inc_ref(ptr %t27)
  %t28 = call ptr @__alloc(i64 4, i32 0)
  store i32 4, ptr %t28
  %t29 = call ptr @__alloc(i64 4, i32 0)
  store i32 1, ptr %t29
  %t30 = call ptr @__alloc(i64 24, i32 2)
  %t31 = inttoptr i64 14 to ptr
  %t32 = getelementptr ptr, ptr %t30, i32 0
  store ptr %t31, ptr %t32
  %t33 = call ptr @__alloc(i64 4, i32 0)
  store i32 1, ptr %t33
  %t34 = getelementptr ptr, ptr %t30, i32 1
  store ptr %t33, ptr %t34
  %t35 = call ptr @__alloc(i64 8, i32 0)
  %t36 = inttoptr i64 13 to ptr
  %t37 = getelementptr ptr, ptr %t35, i32 0
  store ptr %t36, ptr %t37
  %t38 = getelementptr ptr, ptr %t30, i32 2
  store ptr %t35, ptr %t38
  %t39 = call ptr @v_wrap(ptr %t28, ptr %t29, ptr %t30)
  %t40 = call ptr @__concat(ptr %t27, ptr %t39)
  %t41 = getelementptr ptr, ptr %t40, i32 0
  %t42 = load ptr, ptr %t41
  %t43 = ptrtoint ptr %t42 to i64
  switch i64 %t43, label %case.default.44 [ i64 3, label %case.arm.3.46 i64 4, label %case.arm.4.60 ]
case.arm.3.46:
  %t48 = call ptr @__alloc(i64 24, i32 2)
  %t49 = inttoptr i64 7 to ptr
  %t50 = getelementptr ptr, ptr %t48, i32 0
  store ptr %t49, ptr %t50
  %t51 = getelementptr ptr, ptr %t48, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t51
  %t52 = call ptr @__alloc(i64 16, i32 1)
  %t53 = inttoptr i64 5 to ptr
  %t54 = getelementptr ptr, ptr %t52, i32 0
  store ptr %t53, ptr %t54
  %t55 = call ptr @__alloc(i64 8, i32 0)
  %t56 = inttoptr i64 0 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  %t58 = getelementptr ptr, ptr %t52, i32 1
  store ptr %t55, ptr %t58
  %t59 = getelementptr ptr, ptr %t48, i32 2
  store ptr %t52, ptr %t59
  br label %case.end.3.47
case.end.3.47:
  br label %case.join.45
case.arm.4.60:
  %t62 = getelementptr ptr, ptr %t40, i32 1
  %t63 = load ptr, ptr %t62
  call void @__inc_ref(ptr %t63)
  call void @__inc_ref(ptr %t63)
  %t64 = call ptr @__concat(ptr %t63, ptr getelementptr inbounds (i8, ptr @.str.3, i64 12))
  %t65 = getelementptr ptr, ptr %t64, i32 0
  %t66 = load ptr, ptr %t65
  %t67 = ptrtoint ptr %t66 to i64
  switch i64 %t67, label %case.default.68 [ i64 3, label %case.arm.3.70 i64 4, label %case.arm.4.84 ]
case.arm.3.70:
  %t72 = call ptr @__alloc(i64 24, i32 2)
  %t73 = inttoptr i64 7 to ptr
  %t74 = getelementptr ptr, ptr %t72, i32 0
  store ptr %t73, ptr %t74
  %t75 = getelementptr ptr, ptr %t72, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t75
  %t76 = call ptr @__alloc(i64 16, i32 1)
  %t77 = inttoptr i64 5 to ptr
  %t78 = getelementptr ptr, ptr %t76, i32 0
  store ptr %t77, ptr %t78
  %t79 = call ptr @__alloc(i64 8, i32 0)
  %t80 = inttoptr i64 0 to ptr
  %t81 = getelementptr ptr, ptr %t79, i32 0
  store ptr %t80, ptr %t81
  %t82 = getelementptr ptr, ptr %t76, i32 1
  store ptr %t79, ptr %t82
  %t83 = getelementptr ptr, ptr %t72, i32 2
  store ptr %t76, ptr %t83
  br label %case.end.3.71
case.end.3.71:
  br label %case.join.69
case.arm.4.84:
  %t86 = getelementptr ptr, ptr %t64, i32 1
  %t87 = load ptr, ptr %t86
  call void @__inc_ref(ptr %t87)
  call void @__inc_ref(ptr %t87)
  %t88 = call ptr @__alloc(i64 4, i32 0)
  store i32 40, ptr %t88
  %t89 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t89
  %t90 = call ptr @__alloc(i64 4, i32 0)
  store i32 1, ptr %t90
  %t91 = call ptr @v_fib(ptr %t88, ptr %t89, ptr %t90)
  %t92 = call ptr @__concat(ptr %t87, ptr %t91)
  %t93 = getelementptr ptr, ptr %t92, i32 0
  %t94 = load ptr, ptr %t93
  %t95 = ptrtoint ptr %t94 to i64
  switch i64 %t95, label %case.default.96 [ i64 3, label %case.arm.3.98 i64 4, label %case.arm.4.112 ]
case.arm.3.98:
  %t100 = call ptr @__alloc(i64 24, i32 2)
  %t101 = inttoptr i64 7 to ptr
  %t102 = getelementptr ptr, ptr %t100, i32 0
  store ptr %t101, ptr %t102
  %t103 = getelementptr ptr, ptr %t100, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t103
  %t104 = call ptr @__alloc(i64 16, i32 1)
  %t105 = inttoptr i64 5 to ptr
  %t106 = getelementptr ptr, ptr %t104, i32 0
  store ptr %t105, ptr %t106
  %t107 = call ptr @__alloc(i64 8, i32 0)
  %t108 = inttoptr i64 0 to ptr
  %t109 = getelementptr ptr, ptr %t107, i32 0
  store ptr %t108, ptr %t109
  %t110 = getelementptr ptr, ptr %t104, i32 1
  store ptr %t107, ptr %t110
  %t111 = getelementptr ptr, ptr %t100, i32 2
  store ptr %t104, ptr %t111
  br label %case.end.3.99
case.end.3.99:
  br label %case.join.97
case.arm.4.112:
  %t114 = getelementptr ptr, ptr %t92, i32 1
  %t115 = load ptr, ptr %t114
  call void @__inc_ref(ptr %t115)
  %t116 = call ptr @__alloc(i64 24, i32 2)
  %t117 = inttoptr i64 7 to ptr
  %t118 = getelementptr ptr, ptr %t116, i32 0
  store ptr %t117, ptr %t118
  call void @__inc_ref(ptr %t115)
  %t119 = getelementptr ptr, ptr %t116, i32 1
  store ptr %t115, ptr %t119
  %t120 = call ptr @__alloc(i64 16, i32 1)
  %t121 = inttoptr i64 5 to ptr
  %t122 = getelementptr ptr, ptr %t120, i32 0
  store ptr %t121, ptr %t122
  %t123 = call ptr @__alloc(i64 8, i32 0)
  %t124 = inttoptr i64 0 to ptr
  %t125 = getelementptr ptr, ptr %t123, i32 0
  store ptr %t124, ptr %t125
  %t126 = getelementptr ptr, ptr %t120, i32 1
  store ptr %t123, ptr %t126
  %t127 = getelementptr ptr, ptr %t116, i32 2
  store ptr %t120, ptr %t127
  br label %case.end.4.113
case.end.4.113:
  br label %case.join.97
case.default.96:
  unreachable
case.join.97:
  %t128 = phi ptr [ %t100, %case.end.3.99 ], [ %t116, %case.end.4.113 ]
  call void @__free_recursive(ptr %t92)
  br label %case.end.4.85
case.end.4.85:
  br label %case.join.69
case.default.68:
  unreachable
case.join.69:
  %t129 = phi ptr [ %t72, %case.end.3.71 ], [ %t128, %case.end.4.85 ]
  call void @__free_recursive(ptr %t64)
  br label %case.end.4.61
case.end.4.61:
  br label %case.join.45
case.default.44:
  unreachable
case.join.45:
  %t130 = phi ptr [ %t48, %case.end.3.47 ], [ %t129, %case.end.4.61 ]
  call void @__free_recursive(ptr %t40)
  br label %case.end.4.25
case.end.4.25:
  br label %case.join.9
case.default.8:
  unreachable
case.join.9:
  %t131 = phi ptr [ %t12, %case.end.3.11 ], [ %t130, %case.end.4.25 ]
  call void @__free_recursive(ptr %t4)
  ret ptr %t131
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
