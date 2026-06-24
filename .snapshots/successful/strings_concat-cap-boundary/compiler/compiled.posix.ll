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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [384 x i8]} { i32 0, i32 0, i32 0, i32 384, i32 128, [384 x i8] c"\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [36 x i8]} { i32 0, i32 0, i32 0, i32 36, i32 36, [36 x i8] c"FAIL: build returned Left at the cap" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"!" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"OK" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [28 x i8]} { i32 0, i32 0, i32 0, i32 28, i32 28, [28 x i8] c"FAIL: cap + 1 returned Right" }
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [39 x i8]} { i32 0, i32 0, i32 0, i32 39, i32 39, [39 x i8] c"FAIL: built string length is not at cap" }

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


define internal ptr @__predUInt32(ptr %p) {
  %v = load i32, ptr %p
  %is_zero = icmp eq i32 %v, 0
  br i1 %is_zero, label %overflow, label %ok
overflow:
  %ue = call ptr @__alloc(i64 8, i32 0)
  %ue_tag = inttoptr i64 17 to ptr
  store ptr %ue_tag, ptr %ue
  %left = call ptr @__alloc(i64 16, i32 1)
  %left_tag = inttoptr i64 3 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %ue, ptr %left_f
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


define internal ptr @__lengthUtf16CodeUnits(ptr %s) {
  %u16p = getelementptr i8, ptr %s, i64 4
  %u16 = load i32, ptr %u16p
  %box = call ptr @__alloc(i64 4, i32 0)
  store i32 %u16, ptr %box
  call void @__free_recursive(ptr %s)
  ret ptr %box
}


define internal ptr @v_maxStringLengthUtf16CodeUnits() {
  %t0 = call ptr @__alloc(i64 4, i32 0)
  store i32 134217728, ptr %t0
  ret ptr %t0
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

define internal ptr @v_block() {
  ret ptr getelementptr inbounds (i8, ptr @.str.0, i64 12)
}

define internal ptr @v_runTest() {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 10 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 4, i32 0)
  store i32 20, ptr %t3
  %t4 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t4
  %t5 = call ptr @v_block()
  %t6 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t5, ptr %t6
  %t7 = call ptr @v_$scc$$df$andThenEither$0__$lam$13__build(ptr %t0)
  %t8 = getelementptr ptr, ptr %t7, i32 0
  %t9 = load ptr, ptr %t8
  %t10 = ptrtoint ptr %t9 to i64
  switch i64 %t10, label %case.default.11 [ i64 3, label %case.arm.3.13 i64 4, label %case.arm.4.15 ]
case.arm.3.13:
  br label %case.end.3.14
case.end.3.14:
  br label %case.join.12
case.arm.4.15:
  %t17 = getelementptr ptr, ptr %t7, i32 1
  %t18 = load ptr, ptr %t17
  call void @__inc_ref(ptr %t18)
  call void @__inc_ref(ptr %t18)
  %t19 = call ptr @__lengthUtf16CodeUnits(ptr %t18)
  %t20 = call ptr @v_maxStringLengthUtf16CodeUnits()
  %t21 = call ptr @__eqUInt32(ptr %t19, ptr %t20)
  %t22 = getelementptr ptr, ptr %t21, i32 0
  %t23 = load ptr, ptr %t22
  %t24 = ptrtoint ptr %t23 to i64
  switch i64 %t24, label %case.default.25 [ i64 1, label %case.arm.1.27 i64 2, label %case.arm.2.40 ]
case.arm.1.27:
  call void @__inc_ref(ptr %t18)
  %t29 = call ptr @__concat(ptr %t18, ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
  %t30 = getelementptr ptr, ptr %t29, i32 0
  %t31 = load ptr, ptr %t30
  %t32 = ptrtoint ptr %t31 to i64
  switch i64 %t32, label %case.default.33 [ i64 3, label %case.arm.3.35 i64 4, label %case.arm.4.37 ]
case.arm.3.35:
  br label %case.end.3.36
case.end.3.36:
  br label %case.join.34
case.arm.4.37:
  br label %case.end.4.38
case.end.4.38:
  br label %case.join.34
case.default.33:
  unreachable
case.join.34:
  %t39 = phi ptr [ getelementptr inbounds (i8, ptr @.str.3, i64 12), %case.end.3.36 ], [ getelementptr inbounds (i8, ptr @.str.4, i64 12), %case.end.4.38 ]
  call void @__free_recursive(ptr %t29)
  br label %case.end.1.28
case.end.1.28:
  br label %case.join.26
case.arm.2.40:
  br label %case.end.2.41
case.end.2.41:
  br label %case.join.26
case.default.25:
  unreachable
case.join.26:
  %t42 = phi ptr [ %t39, %case.end.1.28 ], [ getelementptr inbounds (i8, ptr @.str.5, i64 12), %case.end.2.41 ]
  call void @__free_recursive(ptr %t21)
  br label %case.end.4.16
case.end.4.16:
  br label %case.join.12
case.default.11:
  unreachable
case.join.12:
  %t43 = phi ptr [ getelementptr inbounds (i8, ptr @.str.1, i64 12), %case.end.3.14 ], [ %t42, %case.end.4.16 ]
  call void @__free_recursive(ptr %t7)
  ret ptr %t43
}

define internal ptr @v_main() {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 7 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_runTest()
  %t4 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t4
  %t5 = call ptr @__alloc(i64 16, i32 1)
  %t6 = inttoptr i64 5 to ptr
  %t7 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t6, ptr %t7
  %t8 = call ptr @__alloc(i64 8, i32 0)
  %t9 = inttoptr i64 0 to ptr
  %t10 = getelementptr ptr, ptr %t8, i32 0
  store ptr %t9, ptr %t10
  %t11 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t8, ptr %t11
  %t12 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t5, ptr %t12
  ret ptr %t0
}

define internal ptr @v_$scc$$df$andThenEither$0__$lam$13__build(ptr %v_$args) {
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
  switch i64 %t7, label %tco.case.default.8 [ i64 8, label %tco.case.arm.8.9 i64 9, label %tco.case.arm.9.28 i64 10, label %tco.case.arm.10.35 ]
tco.case.arm.8.9:
  %t10 = getelementptr ptr, ptr %t4, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  %t12 = getelementptr ptr, ptr %t4, i32 2
  %t13 = load ptr, ptr %t12
  %t14 = getelementptr ptr, ptr %t11, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %tco.case.default.17 [ i64 3, label %tco.case.arm.3.18 i64 4, label %tco.case.arm.4.19 ]
tco.case.arm.3.18:
  call void @__free_recursive(ptr %t4)
  store ptr %t11, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.19:
  %t20 = getelementptr ptr, ptr %t11, i32 1
  %t21 = load ptr, ptr %t20
  call void @__inc_ref(ptr %t21)
  %t22 = getelementptr ptr, ptr %t4, i32 1
  %t23 = load ptr, ptr %t22
  call void @__free_recursive(ptr %t23)
  %t26 = inttoptr i64 9 to ptr
  %t27 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t26, ptr %t27
  %t24 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t13, ptr %t24
  %t25 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t21, ptr %t25
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.17:
  unreachable
tco.case.arm.9.28:
  %t29 = getelementptr ptr, ptr %t4, i32 1
  %t30 = load ptr, ptr %t29
  %t31 = getelementptr ptr, ptr %t4, i32 2
  %t32 = load ptr, ptr %t31
  %t33 = inttoptr i64 10 to ptr
  %t34 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t33, ptr %t34
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.10.35:
  %t36 = getelementptr ptr, ptr %t4, i32 1
  %t37 = load ptr, ptr %t36
  call void @__inc_ref(ptr %t37)
  %t38 = getelementptr ptr, ptr %t4, i32 2
  %t39 = load ptr, ptr %t38
  call void @__inc_ref(ptr %t39)
  call void @__inc_ref(ptr %t37)
  %t40 = call ptr @__predUInt32(ptr %t37)
  %t41 = getelementptr ptr, ptr %t40, i32 0
  %t42 = load ptr, ptr %t41
  %t43 = ptrtoint ptr %t42 to i64
  switch i64 %t43, label %tco.case.default.44 [ i64 3, label %tco.case.arm.3.45 i64 4, label %tco.case.arm.4.50 ]
tco.case.arm.3.45:
  call void @__free_recursive(ptr %t40)
  %t46 = call ptr @__alloc(i64 16, i32 1)
  %t47 = inttoptr i64 4 to ptr
  %t48 = getelementptr ptr, ptr %t46, i32 0
  store ptr %t47, ptr %t48
  call void @__inc_ref(ptr %t39)
  %t49 = getelementptr ptr, ptr %t46, i32 1
  store ptr %t39, ptr %t49
  call void @__free_recursive(ptr %t39)
  call void @__free_recursive(ptr %t37)
  call void @__free_recursive(ptr %t4)
  store ptr %t46, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.50:
  %t51 = getelementptr ptr, ptr %t40, i32 1
  %t52 = load ptr, ptr %t51
  call void @__inc_ref(ptr %t52)
  call void @__free_recursive(ptr %t40)
  call void @__inc_ref(ptr %t39)
  call void @__inc_ref(ptr %t39)
  %t53 = call ptr @__concat(ptr %t39, ptr %t39)
  %t54 = getelementptr ptr, ptr %t4, i32 1
  %t55 = load ptr, ptr %t54
  call void @__free_recursive(ptr %t55)
  %t56 = getelementptr ptr, ptr %t4, i32 2
  %t57 = load ptr, ptr %t56
  call void @__free_recursive(ptr %t57)
  %t60 = inttoptr i64 8 to ptr
  %t61 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t60, ptr %t61
  %t58 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t53, ptr %t58
  call void @__inc_ref(ptr %t52)
  %t59 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t52, ptr %t59
  call void @__free_recursive(ptr %t52)
  call void @__free_recursive(ptr %t39)
  call void @__free_recursive(ptr %t37)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.44:
  unreachable
tco.case.default.8:
  unreachable
tco.exit.1:
  %t62 = load ptr, ptr %t2
  ret ptr %t62
}

define i32 @main(i32 %argc, ptr %argv) {
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
