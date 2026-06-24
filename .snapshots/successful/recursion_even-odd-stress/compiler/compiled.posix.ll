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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [6 x i8]} { i32 0, i32 0, i32 0, i32 6, i32 6, [6 x i8] c"left: " }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [14 x i8]} { i32 0, i32 0, i32 0, i32 14, i32 14, [14 x i8] c"UnderflowError" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [7 x i8]} { i32 0, i32 0, i32 0, i32 7, i32 7, [7 x i8] c"right: " }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"True" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"False" }
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }

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

define internal ptr @v_res() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 20 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 4, i32 0)
  store i32 1000000, ptr %t3
  %t4 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t4
  %t5 = call ptr @v_$scc$evenInt__oddInt(ptr %t0)
  %t6 = getelementptr ptr, ptr %t5, i32 0
  %t7 = load ptr, ptr %t6
  %t8 = ptrtoint ptr %t7 to i64
  switch i64 %t8, label %case.default.9 [ i64 3, label %case.arm.3.11 i64 4, label %case.arm.4.14 ]
case.arm.3.11:
  %t13 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  br label %case.end.3.12
case.end.3.12:
  br label %case.join.10
case.arm.4.14:
  %t16 = getelementptr ptr, ptr %t5, i32 1
  %t17 = load ptr, ptr %t16
  call void @__inc_ref(ptr %t17)
  %t18 = getelementptr ptr, ptr %t17, i32 0
  %t19 = load ptr, ptr %t18
  %t20 = ptrtoint ptr %t19 to i64
  switch i64 %t20, label %case.default.21 [ i64 1, label %case.arm.1.23 i64 2, label %case.arm.2.25 ]
case.arm.1.23:
  br label %case.end.1.24
case.end.1.24:
  br label %case.join.22
case.arm.2.25:
  br label %case.end.2.26
case.end.2.26:
  br label %case.join.22
case.default.21:
  unreachable
case.join.22:
  %t27 = phi ptr [ getelementptr inbounds (i8, ptr @.str.3, i64 12), %case.end.1.24 ], [ getelementptr inbounds (i8, ptr @.str.4, i64 12), %case.end.2.26 ]
  call void @__free_recursive(ptr %t17)
  %t28 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t27)
  br label %case.end.4.15
case.end.4.15:
  br label %case.join.10
case.default.9:
  unreachable
case.join.10:
  %t29 = phi ptr [ %t13, %case.end.3.12 ], [ %t28, %case.end.4.15 ]
  call void @__free_recursive(ptr %t5)
  ret ptr %t29
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
  %t26 = call ptr @v_$cps$$df$andThenIO$4(ptr %t22, ptr %t23)
  %t27 = call ptr @__alloc(i64 8, i32 0)
  %t28 = inttoptr i64 22 to ptr
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
  store ptr getelementptr inbounds (i8, ptr @.str.5, i64 12), ptr %t17
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

define internal ptr @v_$scc$evenInt__oddInt(ptr %v_$args) {
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
  switch i64 %t7, label %tco.case.default.8 [ i64 20, label %tco.case.arm.20.9 i64 21, label %tco.case.arm.21.47 ]
tco.case.arm.20.9:
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
  switch i64 %t16, label %tco.case.default.17 [ i64 1, label %tco.case.arm.1.18 i64 2, label %tco.case.arm.2.26 ]
tco.case.arm.1.18:
  call void @__free_recursive(ptr %t13)
  %t19 = call ptr @__alloc(i64 16, i32 1)
  %t20 = inttoptr i64 4 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = call ptr @__alloc(i64 8, i32 0)
  %t23 = inttoptr i64 1 to ptr
  %t24 = getelementptr ptr, ptr %t22, i32 0
  store ptr %t23, ptr %t24
  %t25 = getelementptr ptr, ptr %t19, i32 1
  store ptr %t22, ptr %t25
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %t4)
  store ptr %t19, ptr %t2
  br label %tco.exit.1
tco.case.arm.2.26:
  call void @__free_recursive(ptr %t13)
  call void @__inc_ref(ptr %t11)
  %t27 = call ptr @__predInt32(ptr %t11)
  %t28 = getelementptr ptr, ptr %t27, i32 0
  %t29 = load ptr, ptr %t28
  %t30 = ptrtoint ptr %t29 to i64
  switch i64 %t30, label %tco.case.default.31 [ i64 3, label %tco.case.arm.3.32 i64 4, label %tco.case.arm.4.39 ]
tco.case.arm.3.32:
  %t33 = getelementptr ptr, ptr %t27, i32 1
  %t34 = load ptr, ptr %t33
  call void @__inc_ref(ptr %t34)
  call void @__free_recursive(ptr %t27)
  %t35 = call ptr @__alloc(i64 16, i32 1)
  %t36 = inttoptr i64 3 to ptr
  %t37 = getelementptr ptr, ptr %t35, i32 0
  store ptr %t36, ptr %t37
  call void @__inc_ref(ptr %t34)
  %t38 = getelementptr ptr, ptr %t35, i32 1
  store ptr %t34, ptr %t38
  call void @__free_recursive(ptr %t34)
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %t4)
  store ptr %t35, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.39:
  %t40 = getelementptr ptr, ptr %t27, i32 1
  %t41 = load ptr, ptr %t40
  call void @__inc_ref(ptr %t41)
  call void @__free_recursive(ptr %t27)
  %t42 = getelementptr ptr, ptr %t4, i32 1
  %t43 = load ptr, ptr %t42
  call void @__free_recursive(ptr %t43)
  %t45 = inttoptr i64 21 to ptr
  %t46 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t45, ptr %t46
  call void @__inc_ref(ptr %t41)
  %t44 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t41, ptr %t44
  call void @__free_recursive(ptr %t41)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.31:
  unreachable
tco.case.default.17:
  unreachable
tco.case.arm.21.47:
  %t48 = getelementptr ptr, ptr %t4, i32 1
  %t49 = load ptr, ptr %t48
  call void @__inc_ref(ptr %t49)
  call void @__inc_ref(ptr %t49)
  %t50 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t50
  %t51 = call ptr @__eqInt32(ptr %t49, ptr %t50)
  %t52 = getelementptr ptr, ptr %t51, i32 0
  %t53 = load ptr, ptr %t52
  %t54 = ptrtoint ptr %t53 to i64
  switch i64 %t54, label %tco.case.default.55 [ i64 1, label %tco.case.arm.1.56 i64 2, label %tco.case.arm.2.64 ]
tco.case.arm.1.56:
  call void @__free_recursive(ptr %t51)
  %t57 = call ptr @__alloc(i64 16, i32 1)
  %t58 = inttoptr i64 4 to ptr
  %t59 = getelementptr ptr, ptr %t57, i32 0
  store ptr %t58, ptr %t59
  %t60 = call ptr @__alloc(i64 8, i32 0)
  %t61 = inttoptr i64 2 to ptr
  %t62 = getelementptr ptr, ptr %t60, i32 0
  store ptr %t61, ptr %t62
  %t63 = getelementptr ptr, ptr %t57, i32 1
  store ptr %t60, ptr %t63
  call void @__free_recursive(ptr %t49)
  call void @__free_recursive(ptr %t4)
  store ptr %t57, ptr %t2
  br label %tco.exit.1
tco.case.arm.2.64:
  call void @__free_recursive(ptr %t51)
  call void @__inc_ref(ptr %t49)
  %t65 = call ptr @__predInt32(ptr %t49)
  %t66 = getelementptr ptr, ptr %t65, i32 0
  %t67 = load ptr, ptr %t66
  %t68 = ptrtoint ptr %t67 to i64
  switch i64 %t68, label %tco.case.default.69 [ i64 3, label %tco.case.arm.3.70 i64 4, label %tco.case.arm.4.77 ]
tco.case.arm.3.70:
  %t71 = getelementptr ptr, ptr %t65, i32 1
  %t72 = load ptr, ptr %t71
  call void @__inc_ref(ptr %t72)
  call void @__free_recursive(ptr %t65)
  %t73 = call ptr @__alloc(i64 16, i32 1)
  %t74 = inttoptr i64 3 to ptr
  %t75 = getelementptr ptr, ptr %t73, i32 0
  store ptr %t74, ptr %t75
  call void @__inc_ref(ptr %t72)
  %t76 = getelementptr ptr, ptr %t73, i32 1
  store ptr %t72, ptr %t76
  call void @__free_recursive(ptr %t72)
  call void @__free_recursive(ptr %t49)
  call void @__free_recursive(ptr %t4)
  store ptr %t73, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.77:
  %t78 = getelementptr ptr, ptr %t65, i32 1
  %t79 = load ptr, ptr %t78
  call void @__inc_ref(ptr %t79)
  call void @__free_recursive(ptr %t65)
  %t80 = getelementptr ptr, ptr %t4, i32 1
  %t81 = load ptr, ptr %t80
  call void @__free_recursive(ptr %t81)
  %t83 = inttoptr i64 20 to ptr
  %t84 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t83, ptr %t84
  call void @__inc_ref(ptr %t79)
  %t82 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t79, ptr %t82
  call void @__free_recursive(ptr %t79)
  call void @__free_recursive(ptr %t49)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.69:
  unreachable
tco.case.default.55:
  unreachable
tco.case.default.8:
  unreachable
tco.exit.1:
  %t85 = load ptr, ptr %t2
  ret ptr %t85
}

define i32 @main(i32 %argc, ptr %argv) {
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
