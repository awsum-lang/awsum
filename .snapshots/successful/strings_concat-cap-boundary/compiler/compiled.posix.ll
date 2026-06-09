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

define internal ptr @v_block() {
  ret ptr getelementptr inbounds (i8, ptr @.str.0, i64 12)
}

define internal ptr @v_runTest() {
  %t0 = call ptr @__alloc(i64 4, i32 0)
  store i32 20, ptr %t0
  %t1 = call ptr @v_block()
  %t2 = call ptr @v_build(ptr %t0, ptr %t1)
  %t3 = getelementptr ptr, ptr %t2, i32 0
  %t4 = load ptr, ptr %t3
  %t5 = ptrtoint ptr %t4 to i64
  switch i64 %t5, label %case.default.6 [ i64 3, label %case.arm.3.8 i64 4, label %case.arm.4.12 ]
case.arm.3.8:
  %t10 = getelementptr ptr, ptr %t2, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  br label %case.end.3.9
case.end.3.9:
  br label %case.join.7
case.arm.4.12:
  %t14 = getelementptr ptr, ptr %t2, i32 1
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  call void @__inc_ref(ptr %t15)
  %t16 = call ptr @__lengthUtf16CodeUnits(ptr %t15)
  %t17 = call ptr @v_maxStringLengthUtf16CodeUnits()
  %t18 = call ptr @__eqUInt32(ptr %t16, ptr %t17)
  %t19 = getelementptr ptr, ptr %t18, i32 0
  %t20 = load ptr, ptr %t19
  %t21 = ptrtoint ptr %t20 to i64
  switch i64 %t21, label %case.default.22 [ i64 1, label %case.arm.1.24 i64 2, label %case.arm.2.41 ]
case.arm.1.24:
  call void @__inc_ref(ptr %t15)
  %t26 = call ptr @__concat(ptr %t15, ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
  %t27 = getelementptr ptr, ptr %t26, i32 0
  %t28 = load ptr, ptr %t27
  %t29 = ptrtoint ptr %t28 to i64
  switch i64 %t29, label %case.default.30 [ i64 3, label %case.arm.3.32 i64 4, label %case.arm.4.36 ]
case.arm.3.32:
  %t34 = getelementptr ptr, ptr %t26, i32 1
  %t35 = load ptr, ptr %t34
  call void @__inc_ref(ptr %t35)
  br label %case.end.3.33
case.end.3.33:
  br label %case.join.31
case.arm.4.36:
  %t38 = getelementptr ptr, ptr %t26, i32 1
  %t39 = load ptr, ptr %t38
  call void @__inc_ref(ptr %t39)
  br label %case.end.4.37
case.end.4.37:
  br label %case.join.31
case.default.30:
  unreachable
case.join.31:
  %t40 = phi ptr [ getelementptr inbounds (i8, ptr @.str.3, i64 12), %case.end.3.33 ], [ getelementptr inbounds (i8, ptr @.str.4, i64 12), %case.end.4.37 ]
  call void @__free_recursive(ptr %t26)
  br label %case.end.1.25
case.end.1.25:
  br label %case.join.23
case.arm.2.41:
  br label %case.end.2.42
case.end.2.42:
  br label %case.join.23
case.default.22:
  unreachable
case.join.23:
  %t43 = phi ptr [ %t40, %case.end.1.25 ], [ getelementptr inbounds (i8, ptr @.str.5, i64 12), %case.end.2.42 ]
  call void @__free_recursive(ptr %t18)
  br label %case.end.4.13
case.end.4.13:
  br label %case.join.7
case.default.6:
  unreachable
case.join.7:
  %t44 = phi ptr [ getelementptr inbounds (i8, ptr @.str.1, i64 12), %case.end.3.9 ], [ %t43, %case.end.4.13 ]
  call void @__free_recursive(ptr %t2)
  ret ptr %t44
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

define internal ptr @v__scc__df_andThenEither_0__lam_13_build(ptr %v__args) {
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
  switch i64 %t7, label %tco.case.default.8 [ i64 8, label %tco.case.arm.8.9 i64 9, label %tco.case.arm.9.46 i64 10, label %tco.case.arm.10.65 ]
tco.case.arm.8.9:
  %t10 = getelementptr ptr, ptr %t4, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  %t12 = getelementptr ptr, ptr %t4, i32 2
  %t13 = load ptr, ptr %t12
  %t14 = getelementptr ptr, ptr %t11, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %tco.case.default.17 [ i64 3, label %tco.case.arm.3.18 i64 4, label %tco.case.arm.4.25 ]
tco.case.arm.3.18:
  %t19 = getelementptr ptr, ptr %t11, i32 1
  %t20 = load ptr, ptr %t19
  call void @__inc_ref(ptr %t20)
  %t21 = call ptr @__alloc(i64 16, i32 1)
  %t22 = inttoptr i64 3 to ptr
  %t23 = getelementptr ptr, ptr %t21, i32 0
  store ptr %t22, ptr %t23
  call void @__inc_ref(ptr %t20)
  %t24 = getelementptr ptr, ptr %t21, i32 1
  store ptr %t20, ptr %t24
  call void @__free_recursive(ptr %t20)
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %t4)
  store ptr %t21, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.25:
  %t26 = getelementptr ptr, ptr %t11, i32 1
  %t27 = load ptr, ptr %t26
  call void @__inc_ref(ptr %t27)
  %t28 = getelementptr i8, ptr %t4, i64 -8
  %t29 = load i32, ptr %t28
  %t30 = icmp eq i32 %t29, 1
  br i1 %t30, label %reuse.in_place.31, label %reuse.copy.32
reuse.in_place.31:
  %t34 = getelementptr ptr, ptr %t4, i32 1
  %t35 = load ptr, ptr %t34
  call void @__free_recursive(ptr %t35)
  %t38 = inttoptr i64 9 to ptr
  %t39 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t38, ptr %t39
  %t36 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t13, ptr %t36
  call void @__inc_ref(ptr %t27)
  %t37 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t27, ptr %t37
  br label %reuse.join.33
reuse.copy.32:
  %t40 = call ptr @__alloc(i64 24, i32 2)
  %t41 = inttoptr i64 9 to ptr
  %t42 = getelementptr ptr, ptr %t40, i32 0
  store ptr %t41, ptr %t42
  call void @__inc_ref(ptr %t13)
  %t43 = getelementptr ptr, ptr %t40, i32 1
  store ptr %t13, ptr %t43
  call void @__inc_ref(ptr %t27)
  %t44 = getelementptr ptr, ptr %t40, i32 2
  store ptr %t27, ptr %t44
  call void @__free_recursive(ptr %t4)
  br label %reuse.join.33
reuse.join.33:
  %t45 = phi ptr [ %t4, %reuse.in_place.31 ], [ %t40, %reuse.copy.32 ]
  call void @__free_recursive(ptr %t27)
  call void @__free_recursive(ptr %t11)
  store ptr %t45, ptr %t3
  br label %tco.loop.0
tco.case.default.17:
  unreachable
tco.case.arm.9.46:
  %t47 = getelementptr ptr, ptr %t4, i32 1
  %t48 = load ptr, ptr %t47
  %t49 = getelementptr ptr, ptr %t4, i32 2
  %t50 = load ptr, ptr %t49
  %t51 = getelementptr i8, ptr %t4, i64 -8
  %t52 = load i32, ptr %t51
  %t53 = icmp eq i32 %t52, 1
  br i1 %t53, label %reuse.in_place.54, label %reuse.copy.55
reuse.in_place.54:
  %t57 = inttoptr i64 10 to ptr
  %t58 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t57, ptr %t58
  br label %reuse.join.56
reuse.copy.55:
  %t59 = call ptr @__alloc(i64 24, i32 2)
  %t60 = inttoptr i64 10 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  call void @__inc_ref(ptr %t48)
  %t62 = getelementptr ptr, ptr %t59, i32 1
  store ptr %t48, ptr %t62
  call void @__inc_ref(ptr %t50)
  %t63 = getelementptr ptr, ptr %t59, i32 2
  store ptr %t50, ptr %t63
  call void @__free_recursive(ptr %t4)
  br label %reuse.join.56
reuse.join.56:
  %t64 = phi ptr [ %t4, %reuse.in_place.54 ], [ %t59, %reuse.copy.55 ]
  store ptr %t64, ptr %t3
  br label %tco.loop.0
tco.case.arm.10.65:
  %t66 = getelementptr ptr, ptr %t4, i32 1
  %t67 = load ptr, ptr %t66
  call void @__inc_ref(ptr %t67)
  %t68 = getelementptr ptr, ptr %t4, i32 2
  %t69 = load ptr, ptr %t68
  call void @__inc_ref(ptr %t69)
  call void @__inc_ref(ptr %t67)
  %t70 = call ptr @__predUInt32(ptr %t67)
  %t71 = getelementptr ptr, ptr %t70, i32 0
  %t72 = load ptr, ptr %t71
  %t73 = ptrtoint ptr %t72 to i64
  switch i64 %t73, label %tco.case.default.74 [ i64 3, label %tco.case.arm.3.75 i64 4, label %tco.case.arm.4.82 ]
tco.case.arm.3.75:
  %t76 = getelementptr ptr, ptr %t70, i32 1
  %t77 = load ptr, ptr %t76
  call void @__inc_ref(ptr %t77)
  %t78 = call ptr @__alloc(i64 16, i32 1)
  %t79 = inttoptr i64 4 to ptr
  %t80 = getelementptr ptr, ptr %t78, i32 0
  store ptr %t79, ptr %t80
  call void @__inc_ref(ptr %t69)
  %t81 = getelementptr ptr, ptr %t78, i32 1
  store ptr %t69, ptr %t81
  call void @__free_recursive(ptr %t70)
  call void @__free_recursive(ptr %t77)
  call void @__free_recursive(ptr %t69)
  call void @__free_recursive(ptr %t67)
  call void @__free_recursive(ptr %t4)
  store ptr %t78, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.82:
  %t83 = getelementptr ptr, ptr %t70, i32 1
  %t84 = load ptr, ptr %t83
  call void @__inc_ref(ptr %t84)
  call void @__inc_ref(ptr %t69)
  call void @__inc_ref(ptr %t69)
  %t85 = call ptr @__concat(ptr %t69, ptr %t69)
  %t86 = getelementptr i8, ptr %t4, i64 -8
  %t87 = load i32, ptr %t86
  %t88 = icmp eq i32 %t87, 1
  br i1 %t88, label %reuse.in_place.89, label %reuse.copy.90
reuse.in_place.89:
  %t92 = getelementptr ptr, ptr %t4, i32 1
  %t93 = load ptr, ptr %t92
  call void @__free_recursive(ptr %t93)
  %t94 = getelementptr ptr, ptr %t4, i32 2
  %t95 = load ptr, ptr %t94
  call void @__free_recursive(ptr %t95)
  %t98 = inttoptr i64 8 to ptr
  %t99 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t98, ptr %t99
  %t96 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t85, ptr %t96
  call void @__inc_ref(ptr %t84)
  %t97 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t84, ptr %t97
  br label %reuse.join.91
reuse.copy.90:
  %t100 = call ptr @__alloc(i64 24, i32 2)
  %t101 = inttoptr i64 8 to ptr
  %t102 = getelementptr ptr, ptr %t100, i32 0
  store ptr %t101, ptr %t102
  %t103 = getelementptr ptr, ptr %t100, i32 1
  store ptr %t85, ptr %t103
  call void @__inc_ref(ptr %t84)
  %t104 = getelementptr ptr, ptr %t100, i32 2
  store ptr %t84, ptr %t104
  call void @__free_recursive(ptr %t4)
  br label %reuse.join.91
reuse.join.91:
  %t105 = phi ptr [ %t4, %reuse.in_place.89 ], [ %t100, %reuse.copy.90 ]
  call void @__free_recursive(ptr %t70)
  call void @__free_recursive(ptr %t84)
  call void @__free_recursive(ptr %t69)
  call void @__free_recursive(ptr %t67)
  store ptr %t105, ptr %t3
  br label %tco.loop.0
tco.case.default.74:
  unreachable
tco.case.default.8:
  unreachable
tco.exit.1:
  %t106 = load ptr, ptr %t2
  ret ptr %t106
}

define internal ptr @v_build(ptr %v_n, ptr %v_acc) {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 10 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  call void @__inc_ref(ptr %v_n)
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v_n, ptr %t3
  call void @__inc_ref(ptr %v_acc)
  %t4 = getelementptr ptr, ptr %t0, i32 2
  store ptr %v_acc, ptr %t4
  %t5 = call ptr @v__scc__df_andThenEither_0__lam_13_build(ptr %t0)
  call void @__free_recursive(ptr %v_n)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t5
}

define i32 @main(i32 %argc, ptr %argv) {
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
