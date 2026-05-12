; External C declarations
declare ptr @malloc(i64)
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

define internal void @__free_recursive(ptr %p_arg) {
entry:
  br label %top
top:
  %p = phi ptr [ %p_arg, %entry ], [ %p_next, %tail_jump ]
  %hdr_ptr = getelementptr i8, ptr %p, i64 -12
  %flag = load i32, ptr %hdr_ptr
  %is_heap = icmp eq i32 %flag, 1
  br i1 %is_heap, label %do_dec, label %skip_dec
do_dec:
  %rc_p = getelementptr i8, ptr %p, i64 -8
  %rc_old = load i32, ptr %rc_p
  %rc_new = sub i32 %rc_old, 1
  store i32 %rc_new, ptr %rc_p
  %is_zero = icmp eq i32 %rc_new, 0
  br i1 %is_zero, label %do_cascade, label %skip_dec
do_cascade:
  %shape_p = getelementptr i8, ptr %p, i64 -4
  %shape = load i32, ptr %shape_p
  %shape_zero = icmp eq i32 %shape, 0
  br i1 %shape_zero, label %loop_done, label %loop_check
loop_check:
  %i = phi i32 [ 1, %do_cascade ], [ %i_next, %loop_body ]
  %cmp = icmp ult i32 %i, %shape
  br i1 %cmp, label %loop_body, label %tail_jump_prep
loop_body:
  %i64 = zext i32 %i to i64
  %slot_p = getelementptr ptr, ptr %p, i64 %i64
  %child = load ptr, ptr %slot_p
  call void @__free_recursive(ptr %child)
  %i_next = add i32 %i, 1
  br label %loop_check
tail_jump_prep:
  %shape64 = zext i32 %shape to i64
  %last_slot_p = getelementptr ptr, ptr %p, i64 %shape64
  %p_next = load ptr, ptr %last_slot_p
  call void @free(ptr %hdr_ptr)
  br label %tail_jump
tail_jump:
  br label %top
loop_done:
  call void @free(ptr %hdr_ptr)
  br label %skip_dec
skip_dec:
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
  %stl_tag = inttoptr i64 15 to ptr
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


define internal ptr @__predUInt32(ptr %p) {
  %v = load i32, ptr %p
  %is_zero = icmp eq i32 %v, 0
  br i1 %is_zero, label %overflow, label %ok
overflow:
  %ue = call ptr @__alloc(i64 8, i32 0)
  %ue_tag = inttoptr i64 13 to ptr
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
  call void @__inc_ref(ptr %t1)
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
  call void @__inc_ref(ptr %t17)
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
  %t40 = phi ptr [getelementptr inbounds (i8, ptr @.str.3, i64 12), %case.end.3.33], [getelementptr inbounds (i8, ptr @.str.4, i64 12), %case.end.4.37]
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
  %t43 = phi ptr [%t40, %case.end.1.25], [getelementptr inbounds (i8, ptr @.str.5, i64 12), %case.end.2.42]
  call void @__free_recursive(ptr %t18)
  br label %case.end.4.13
case.end.4.13:
  br label %case.join.7
case.default.6:
  unreachable
case.join.7:
  %t44 = phi ptr [getelementptr inbounds (i8, ptr @.str.1, i64 12), %case.end.3.9], [%t43, %case.end.4.13]
  call void @__free_recursive(ptr %t2)
  ret ptr %t44
}

define internal ptr @v_main() {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 7 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_runTest()
  call void @__inc_ref(ptr %t3)
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

define internal ptr @v__lift_0(ptr %v___input) {
  %t0 = getelementptr ptr, ptr %v___input, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.11 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v___input, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = call ptr @__alloc(i64 16, i32 1)
  %t8 = inttoptr i64 3 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  call void @__inc_ref(ptr %t6)
  %t10 = getelementptr ptr, ptr %t7, i32 1
  store ptr %t6, ptr %t10
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t7
case.arm.4.11:
  %t12 = getelementptr ptr, ptr %v___input, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @__alloc(i64 16, i32 1)
  %t15 = inttoptr i64 4 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  call void @__inc_ref(ptr %t13)
  %t17 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t13, ptr %t17
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t14
case.default.3:
  unreachable
}

define internal ptr @v__lift_8(ptr %v___input) {
  %t0 = getelementptr ptr, ptr %v___input, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.11 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v___input, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = call ptr @__alloc(i64 16, i32 1)
  %t8 = inttoptr i64 3 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  call void @__inc_ref(ptr %t6)
  %t10 = getelementptr ptr, ptr %t7, i32 1
  store ptr %t6, ptr %t10
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t7
case.arm.4.11:
  %t12 = getelementptr ptr, ptr %v___input, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @__alloc(i64 16, i32 1)
  %t15 = inttoptr i64 4 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  call void @__inc_ref(ptr %t13)
  %t17 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t13, ptr %t17
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t14
case.default.3:
  unreachable
}

define internal ptr @v__scc__df_andThenEither_0__lam_7_build(ptr %v__args) {
  call void @__inc_ref(ptr %v__args)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 11 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__scc__df_andThenEither_0__lam_7_build(ptr %v__args, ptr %t0)
  call void @__free_recursive(ptr %v__args)
  ret ptr %t3
}

define internal ptr @v__cps__scc__df_andThenEither_0__lam_7_build(ptr %v__args, ptr %v__k) {
entry:
  %t3 = alloca ptr
  store ptr %v__args, ptr %t3
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
  switch i64 %t9, label %tco.case.default.10 [ i64 8, label %tco.case.arm.8.11 i64 9, label %tco.case.arm.9.55 i64 10, label %tco.case.arm.10.74 ]
tco.case.arm.8.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t5, i32 2
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  %t16 = getelementptr ptr, ptr %t13, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %tco.case.default.19 [ i64 3, label %tco.case.arm.3.20 i64 4, label %tco.case.arm.4.28 ]
tco.case.arm.3.20:
  %t21 = getelementptr ptr, ptr %t13, i32 1
  %t22 = load ptr, ptr %t21
  call void @__inc_ref(ptr %t22)
  call void @__inc_ref(ptr %t6)
  %t23 = call ptr @__alloc(i64 16, i32 1)
  %t24 = inttoptr i64 3 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  call void @__inc_ref(ptr %t22)
  %t26 = getelementptr ptr, ptr %t23, i32 1
  store ptr %t22, ptr %t26
  %t27 = call ptr @v__apply__scc__df_andThenEither_0__lam_7_build(ptr %t6, ptr %t23)
  call void @__free_recursive(ptr %t22)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t27, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.28:
  %t29 = getelementptr ptr, ptr %t13, i32 1
  %t30 = load ptr, ptr %t29
  call void @__inc_ref(ptr %t30)
  %t31 = getelementptr i8, ptr %t5, i64 -8
  %t32 = load i32, ptr %t31
  %t33 = icmp eq i32 %t32, 1
  br i1 %t33, label %reuse.in_place.34, label %reuse.copy.35
reuse.in_place.34:
  %t37 = getelementptr ptr, ptr %t5, i32 1
  %t38 = load ptr, ptr %t37
  call void @__free_recursive(ptr %t38)
  %t39 = getelementptr ptr, ptr %t5, i32 2
  %t40 = load ptr, ptr %t39
  call void @__free_recursive(ptr %t40)
  %t43 = inttoptr i64 9 to ptr
  %t44 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t43, ptr %t44
  call void @__inc_ref(ptr %t15)
  %t41 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t15, ptr %t41
  call void @__inc_ref(ptr %t30)
  %t42 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t30, ptr %t42
  br label %reuse.join.36
reuse.copy.35:
  %t45 = call ptr @__alloc(i64 24, i32 2)
  %t46 = inttoptr i64 9 to ptr
  %t47 = getelementptr ptr, ptr %t45, i32 0
  store ptr %t46, ptr %t47
  call void @__inc_ref(ptr %t15)
  %t48 = getelementptr ptr, ptr %t45, i32 1
  store ptr %t15, ptr %t48
  call void @__inc_ref(ptr %t30)
  %t49 = getelementptr ptr, ptr %t45, i32 2
  store ptr %t30, ptr %t49
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.36
reuse.join.36:
  %t50 = phi ptr [ %t5, %reuse.in_place.34 ], [ %t45, %reuse.copy.35 ]
  %t51 = call ptr @__alloc(i64 16, i32 1)
  %t52 = inttoptr i64 12 to ptr
  %t53 = getelementptr ptr, ptr %t51, i32 0
  store ptr %t52, ptr %t53
  call void @__inc_ref(ptr %t6)
  %t54 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t6, ptr %t54
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t30)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t50, ptr %t3
  store ptr %t51, ptr %t4
  br label %tco.loop.0
tco.case.default.19:
  unreachable
tco.case.arm.9.55:
  %t56 = getelementptr ptr, ptr %t5, i32 1
  %t57 = load ptr, ptr %t56
  call void @__inc_ref(ptr %t57)
  %t58 = getelementptr ptr, ptr %t5, i32 2
  %t59 = load ptr, ptr %t58
  call void @__inc_ref(ptr %t59)
  %t60 = getelementptr i8, ptr %t5, i64 -8
  %t61 = load i32, ptr %t60
  %t62 = icmp eq i32 %t61, 1
  br i1 %t62, label %reuse.in_place.63, label %reuse.copy.64
reuse.in_place.63:
  %t66 = inttoptr i64 10 to ptr
  %t67 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t66, ptr %t67
  br label %reuse.join.65
reuse.copy.64:
  %t68 = call ptr @__alloc(i64 24, i32 2)
  %t69 = inttoptr i64 10 to ptr
  %t70 = getelementptr ptr, ptr %t68, i32 0
  store ptr %t69, ptr %t70
  call void @__inc_ref(ptr %t57)
  %t71 = getelementptr ptr, ptr %t68, i32 1
  store ptr %t57, ptr %t71
  call void @__inc_ref(ptr %t59)
  %t72 = getelementptr ptr, ptr %t68, i32 2
  store ptr %t59, ptr %t72
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.65
reuse.join.65:
  %t73 = phi ptr [ %t5, %reuse.in_place.63 ], [ %t68, %reuse.copy.64 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t59)
  call void @__free_recursive(ptr %t57)
  store ptr %t73, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.10.74:
  %t75 = getelementptr ptr, ptr %t5, i32 1
  %t76 = load ptr, ptr %t75
  call void @__inc_ref(ptr %t76)
  %t77 = getelementptr ptr, ptr %t5, i32 2
  %t78 = load ptr, ptr %t77
  call void @__inc_ref(ptr %t78)
  call void @__inc_ref(ptr %t76)
  %t79 = call ptr @__predUInt32(ptr %t76)
  %t80 = getelementptr ptr, ptr %t79, i32 0
  %t81 = load ptr, ptr %t80
  %t82 = ptrtoint ptr %t81 to i64
  switch i64 %t82, label %tco.case.default.83 [ i64 3, label %tco.case.arm.3.84 i64 4, label %tco.case.arm.4.92 ]
tco.case.arm.3.84:
  %t85 = getelementptr ptr, ptr %t79, i32 1
  %t86 = load ptr, ptr %t85
  call void @__inc_ref(ptr %t86)
  call void @__inc_ref(ptr %t6)
  %t87 = call ptr @__alloc(i64 16, i32 1)
  %t88 = inttoptr i64 4 to ptr
  %t89 = getelementptr ptr, ptr %t87, i32 0
  store ptr %t88, ptr %t89
  call void @__inc_ref(ptr %t78)
  %t90 = getelementptr ptr, ptr %t87, i32 1
  store ptr %t78, ptr %t90
  %t91 = call ptr @v__apply__scc__df_andThenEither_0__lam_7_build(ptr %t6, ptr %t87)
  call void @__free_recursive(ptr %t79)
  call void @__free_recursive(ptr %t86)
  call void @__free_recursive(ptr %t78)
  call void @__free_recursive(ptr %t76)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t91, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.92:
  %t93 = getelementptr ptr, ptr %t79, i32 1
  %t94 = load ptr, ptr %t93
  call void @__inc_ref(ptr %t94)
  call void @__inc_ref(ptr %t78)
  call void @__inc_ref(ptr %t78)
  %t95 = call ptr @__concat(ptr %t78, ptr %t78)
  %t96 = call ptr @v__lift_8(ptr %t95)
  %t97 = getelementptr i8, ptr %t5, i64 -8
  %t98 = load i32, ptr %t97
  %t99 = icmp eq i32 %t98, 1
  br i1 %t99, label %reuse.in_place.100, label %reuse.copy.101
reuse.in_place.100:
  %t103 = getelementptr ptr, ptr %t5, i32 1
  %t104 = load ptr, ptr %t103
  call void @__free_recursive(ptr %t104)
  %t105 = getelementptr ptr, ptr %t5, i32 2
  %t106 = load ptr, ptr %t105
  call void @__free_recursive(ptr %t106)
  %t109 = inttoptr i64 8 to ptr
  %t110 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t109, ptr %t110
  %t107 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t96, ptr %t107
  call void @__inc_ref(ptr %t94)
  %t108 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t94, ptr %t108
  br label %reuse.join.102
reuse.copy.101:
  %t111 = call ptr @__alloc(i64 24, i32 2)
  %t112 = inttoptr i64 8 to ptr
  %t113 = getelementptr ptr, ptr %t111, i32 0
  store ptr %t112, ptr %t113
  %t114 = getelementptr ptr, ptr %t111, i32 1
  store ptr %t96, ptr %t114
  call void @__inc_ref(ptr %t94)
  %t115 = getelementptr ptr, ptr %t111, i32 2
  store ptr %t94, ptr %t115
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.102
reuse.join.102:
  %t116 = phi ptr [ %t5, %reuse.in_place.100 ], [ %t111, %reuse.copy.101 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t79)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t94)
  call void @__free_recursive(ptr %t78)
  call void @__free_recursive(ptr %t76)
  store ptr %t116, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.default.83:
  unreachable
tco.case.default.10:
  unreachable
tco.exit.1:
  %t117 = load ptr, ptr %t2
  ret ptr %t117
}

define internal ptr @v__apply__scc__df_andThenEither_0__lam_7_build(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 11, label %tco.case.arm.11.11 i64 12, label %tco.case.arm.12.12 ]
tco.case.arm.11.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.12.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  call void @__inc_ref(ptr %t6)
  %t15 = call ptr @v__lift_0(ptr %t6)
  call void @__inc_ref(ptr %t14)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t14)
  store ptr %t14, ptr %t3
  store ptr %t15, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t16 = load ptr, ptr %t2
  ret ptr %t16
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
  %t5 = call ptr @v__scc__df_andThenEither_0__lam_7_build(ptr %t0)
  call void @__free_recursive(ptr %v_n)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t5
}

declare ptr @GetCommandLineW()
declare ptr @CommandLineToArgvW(ptr, ptr)
declare i32 @WideCharToMultiByte(i32, i32, ptr, i32, ptr, i32, ptr, ptr)

define i32 @main(i32 %argc_posix, ptr %argv_posix) {
entry:
  %cmdline = call ptr @GetCommandLineW()
  %argc_slot = alloca i32
  %argv_w = call ptr @CommandLineToArgvW(ptr %cmdline, ptr %argc_slot)
  %argc_w = load i32, ptr %argc_slot
  %has_arg = icmp sgt i32 %argc_w, 1
  br i1 %has_arg, label %with_arg, label %no_arg
with_arg:
  %arg_w_slot = getelementptr ptr, ptr %argv_w, i64 1
  %arg_w = load ptr, ptr %arg_w_slot
  %needed = call i32 @WideCharToMultiByte(i32 65001, i32 0, ptr %arg_w, i32 -1, ptr null, i32 0, ptr null, ptr null)
  %need_ok = icmp sgt i32 %needed, 0
  br i1 %need_ok, label %do_convert, label %no_arg
do_convert:
  %needed64 = sext i32 %needed to i64
  %buf = call ptr @__alloc(i64 %needed64, i32 0)
  %written = call i32 @WideCharToMultiByte(i32 65001, i32 0, ptr %arg_w, i32 -1, ptr %buf, i32 %needed, ptr null, ptr null)
  br label %call_main
no_arg:
  br label %call_main
call_main:
  %input = phi ptr [%buf, %do_convert], [getelementptr inbounds (i8, ptr @.empty, i64 12), %no_arg]
  store ptr %input, ptr @.cli_arg
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
