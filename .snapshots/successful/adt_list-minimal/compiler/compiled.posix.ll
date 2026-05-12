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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"a" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"b" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"c" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [0 x i8]} { i32 0, i32 0, i32 0, i32 0, i32 0, [0 x i8] zeroinitializer }
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"," }

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

define internal ptr @v_main() {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 19 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t3
  %t4 = call ptr @__alloc(i64 24, i32 2)
  %t5 = inttoptr i64 19 to ptr
  %t6 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5, ptr %t6
  %t7 = getelementptr ptr, ptr %t4, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t7
  %t8 = call ptr @__alloc(i64 24, i32 2)
  %t9 = inttoptr i64 19 to ptr
  %t10 = getelementptr ptr, ptr %t8, i32 0
  store ptr %t9, ptr %t10
  %t11 = getelementptr ptr, ptr %t8, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t11
  %t12 = call ptr @__alloc(i64 8, i32 0)
  %t13 = inttoptr i64 20 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = call ptr @v__lift_7(ptr %t12)
  %t16 = getelementptr ptr, ptr %t8, i32 2
  store ptr %t15, ptr %t16
  %t17 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t8, ptr %t17
  %t18 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t4, ptr %t18
  %t19 = call ptr @v_show(ptr %t0)
  %t20 = call ptr @v__let_8(ptr %t19)
  ret ptr %t20
}

define internal ptr @v__lift_7(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 23 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__lift_7(ptr %v___input, ptr %t0)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t3
}

define internal ptr @v__cps__lift_7(ptr %v___input, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 19, label %tco.case.arm.19.11 i64 20, label %tco.case.arm.20.36 ]
tco.case.arm.19.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t5, i32 2
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  %t16 = getelementptr i8, ptr %t5, i64 -8
  %t17 = load i32, ptr %t16
  %t18 = icmp eq i32 %t17, 1
  br i1 %t18, label %reuse.in_place.19, label %reuse.copy.20
reuse.in_place.19:
  %t22 = getelementptr ptr, ptr %t5, i32 1
  %t23 = load ptr, ptr %t22
  call void @__free_recursive(ptr %t23)
  %t24 = getelementptr ptr, ptr %t5, i32 2
  %t25 = load ptr, ptr %t24
  call void @__free_recursive(ptr %t25)
  %t28 = inttoptr i64 24 to ptr
  %t29 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t28, ptr %t29
  call void @__inc_ref(ptr %t6)
  %t26 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t26
  call void @__inc_ref(ptr %t13)
  %t27 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t13, ptr %t27
  br label %reuse.join.21
reuse.copy.20:
  %t30 = call ptr @__alloc(i64 24, i32 2)
  %t31 = inttoptr i64 24 to ptr
  %t32 = getelementptr ptr, ptr %t30, i32 0
  store ptr %t31, ptr %t32
  call void @__inc_ref(ptr %t6)
  %t33 = getelementptr ptr, ptr %t30, i32 1
  store ptr %t6, ptr %t33
  call void @__inc_ref(ptr %t13)
  %t34 = getelementptr ptr, ptr %t30, i32 2
  store ptr %t13, ptr %t34
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.21
reuse.join.21:
  %t35 = phi ptr [ %t5, %reuse.in_place.19 ], [ %t30, %reuse.copy.20 ]
  call void @__inc_ref(ptr %t15)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t15, ptr %t3
  store ptr %t35, ptr %t4
  br label %tco.loop.0
tco.case.arm.20.36:
  call void @__inc_ref(ptr %t6)
  %t37 = call ptr @__alloc(i64 8, i32 0)
  %t38 = inttoptr i64 20 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = call ptr @v__apply__lift_7(ptr %t6, ptr %t37)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t40, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t41 = load ptr, ptr %t2
  ret ptr %t41
}

define internal ptr @v__apply__lift_7(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 23, label %tco.case.arm.23.11 i64 24, label %tco.case.arm.24.12 ]
tco.case.arm.23.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.24.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  %t15 = getelementptr ptr, ptr %t5, i32 2
  %t16 = load ptr, ptr %t15
  call void @__inc_ref(ptr %t16)
  %t17 = getelementptr i8, ptr %t5, i64 -8
  %t18 = load i32, ptr %t17
  %t19 = icmp eq i32 %t18, 1
  br i1 %t19, label %reuse.in_place.20, label %reuse.copy.21
reuse.in_place.20:
  %t23 = getelementptr ptr, ptr %t5, i32 1
  %t24 = load ptr, ptr %t23
  call void @__free_recursive(ptr %t24)
  %t25 = getelementptr ptr, ptr %t5, i32 2
  %t26 = load ptr, ptr %t25
  call void @__free_recursive(ptr %t26)
  %t29 = inttoptr i64 19 to ptr
  %t30 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t29, ptr %t30
  call void @__inc_ref(ptr %t16)
  %t27 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t16, ptr %t27
  call void @__inc_ref(ptr %t6)
  %t28 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t6, ptr %t28
  br label %reuse.join.22
reuse.copy.21:
  %t31 = call ptr @__alloc(i64 24, i32 2)
  %t32 = inttoptr i64 19 to ptr
  %t33 = getelementptr ptr, ptr %t31, i32 0
  store ptr %t32, ptr %t33
  call void @__inc_ref(ptr %t16)
  %t34 = getelementptr ptr, ptr %t31, i32 1
  store ptr %t16, ptr %t34
  call void @__inc_ref(ptr %t6)
  %t35 = getelementptr ptr, ptr %t31, i32 2
  store ptr %t6, ptr %t35
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.22
reuse.join.22:
  %t36 = phi ptr [ %t5, %reuse.in_place.20 ], [ %t31, %reuse.copy.21 ]
  call void @__inc_ref(ptr %t14)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t16)
  call void @__free_recursive(ptr %t14)
  store ptr %t14, ptr %t3
  store ptr %t36, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t37 = load ptr, ptr %t2
  ret ptr %t37
}

define internal ptr @v__let_8(ptr %v_res) {
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
  store ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t10
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

define internal ptr @v__scc_show_showCons(ptr %v__args) {
  call void @__inc_ref(ptr %v__args)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 25 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__scc_show_showCons(ptr %v__args, ptr %t0)
  call void @__free_recursive(ptr %v__args)
  ret ptr %t3
}

define internal ptr @v__cps__scc_show_showCons(ptr %v__args, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 21, label %tco.case.arm.21.11 i64 22, label %tco.case.arm.22.34 ]
tco.case.arm.21.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t13, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %tco.case.default.17 [ i64 19, label %tco.case.arm.19.18 i64 20, label %tco.case.arm.20.28 ]
tco.case.arm.19.18:
  %t19 = getelementptr ptr, ptr %t13, i32 1
  %t20 = load ptr, ptr %t19
  call void @__inc_ref(ptr %t20)
  %t21 = getelementptr ptr, ptr %t13, i32 2
  %t22 = load ptr, ptr %t21
  call void @__inc_ref(ptr %t22)
  %t23 = call ptr @__alloc(i64 24, i32 2)
  %t24 = inttoptr i64 22 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  call void @__inc_ref(ptr %t20)
  %t26 = getelementptr ptr, ptr %t23, i32 1
  store ptr %t20, ptr %t26
  call void @__inc_ref(ptr %t22)
  %t27 = getelementptr ptr, ptr %t23, i32 2
  store ptr %t22, ptr %t27
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t22)
  call void @__free_recursive(ptr %t20)
  call void @__free_recursive(ptr %t13)
  store ptr %t23, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.20.28:
  call void @__inc_ref(ptr %t6)
  %t29 = call ptr @__alloc(i64 16, i32 1)
  %t30 = inttoptr i64 4 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = getelementptr ptr, ptr %t29, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t32
  %t33 = call ptr @v__apply__scc_show_showCons(ptr %t6, ptr %t29)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t33, ptr %t2
  br label %tco.exit.1
tco.case.default.17:
  unreachable
tco.case.arm.22.34:
  %t35 = getelementptr ptr, ptr %t5, i32 1
  %t36 = load ptr, ptr %t35
  call void @__inc_ref(ptr %t36)
  %t37 = getelementptr ptr, ptr %t5, i32 2
  %t38 = load ptr, ptr %t37
  call void @__inc_ref(ptr %t38)
  call void @__inc_ref(ptr %t36)
  %t39 = call ptr @__concat(ptr %t36, ptr getelementptr inbounds (i8, ptr @.str.5, i64 12))
  %t40 = getelementptr ptr, ptr %t39, i32 0
  %t41 = load ptr, ptr %t40
  %t42 = ptrtoint ptr %t41 to i64
  switch i64 %t42, label %tco.case.default.43 [ i64 3, label %tco.case.arm.3.44 i64 4, label %tco.case.arm.4.52 ]
tco.case.arm.3.44:
  %t45 = getelementptr ptr, ptr %t39, i32 1
  %t46 = load ptr, ptr %t45
  call void @__inc_ref(ptr %t46)
  call void @__inc_ref(ptr %t6)
  %t47 = call ptr @__alloc(i64 16, i32 1)
  %t48 = inttoptr i64 3 to ptr
  %t49 = getelementptr ptr, ptr %t47, i32 0
  store ptr %t48, ptr %t49
  call void @__inc_ref(ptr %t46)
  %t50 = getelementptr ptr, ptr %t47, i32 1
  store ptr %t46, ptr %t50
  %t51 = call ptr @v__apply__scc_show_showCons(ptr %t6, ptr %t47)
  call void @__free_recursive(ptr %t39)
  call void @__free_recursive(ptr %t46)
  call void @__free_recursive(ptr %t38)
  call void @__free_recursive(ptr %t36)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t51, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.52:
  %t53 = getelementptr ptr, ptr %t39, i32 1
  %t54 = load ptr, ptr %t53
  call void @__inc_ref(ptr %t54)
  %t55 = call ptr @__alloc(i64 16, i32 1)
  %t56 = inttoptr i64 21 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  call void @__inc_ref(ptr %t38)
  %t58 = getelementptr ptr, ptr %t55, i32 1
  store ptr %t38, ptr %t58
  %t59 = getelementptr i8, ptr %t5, i64 -8
  %t60 = load i32, ptr %t59
  %t61 = icmp eq i32 %t60, 1
  br i1 %t61, label %reuse.in_place.62, label %reuse.copy.63
reuse.in_place.62:
  %t65 = getelementptr ptr, ptr %t5, i32 1
  %t66 = load ptr, ptr %t65
  call void @__free_recursive(ptr %t66)
  %t67 = getelementptr ptr, ptr %t5, i32 2
  %t68 = load ptr, ptr %t67
  call void @__free_recursive(ptr %t68)
  %t71 = inttoptr i64 26 to ptr
  %t72 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t71, ptr %t72
  call void @__inc_ref(ptr %t6)
  %t69 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t69
  call void @__inc_ref(ptr %t54)
  %t70 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t54, ptr %t70
  br label %reuse.join.64
reuse.copy.63:
  %t73 = call ptr @__alloc(i64 24, i32 2)
  %t74 = inttoptr i64 26 to ptr
  %t75 = getelementptr ptr, ptr %t73, i32 0
  store ptr %t74, ptr %t75
  call void @__inc_ref(ptr %t6)
  %t76 = getelementptr ptr, ptr %t73, i32 1
  store ptr %t6, ptr %t76
  call void @__inc_ref(ptr %t54)
  %t77 = getelementptr ptr, ptr %t73, i32 2
  store ptr %t54, ptr %t77
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.64
reuse.join.64:
  %t78 = phi ptr [ %t5, %reuse.in_place.62 ], [ %t73, %reuse.copy.63 ]
  call void @__free_recursive(ptr %t39)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t54)
  call void @__free_recursive(ptr %t38)
  call void @__free_recursive(ptr %t36)
  store ptr %t55, ptr %t3
  store ptr %t78, ptr %t4
  br label %tco.loop.0
tco.case.default.43:
  unreachable
tco.case.default.10:
  unreachable
tco.exit.1:
  %t79 = load ptr, ptr %t2
  ret ptr %t79
}

define internal ptr @v__apply__scc_show_showCons(ptr %v__k, ptr %v__x) {
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
  call void @__inc_ref(ptr %t16)
  %t17 = getelementptr ptr, ptr %t6, i32 0
  %t18 = load ptr, ptr %t17
  %t19 = ptrtoint ptr %t18 to i64
  switch i64 %t19, label %tco.case.default.20 [ i64 3, label %tco.case.arm.3.21 i64 4, label %tco.case.arm.4.37 ]
tco.case.arm.3.21:
  %t22 = getelementptr ptr, ptr %t6, i32 1
  %t23 = load ptr, ptr %t22
  call void @__inc_ref(ptr %t23)
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
  call void @__free_recursive(ptr %t23)
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
  call void @__inc_ref(ptr %t39)
  %t40 = call ptr @__concat(ptr %t16, ptr %t39)
  call void @__inc_ref(ptr %t14)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t39)
  call void @__free_recursive(ptr %t16)
  call void @__free_recursive(ptr %t14)
  store ptr %t14, ptr %t3
  store ptr %t40, ptr %t4
  br label %tco.loop.0
tco.case.default.20:
  unreachable
tco.case.default.10:
  unreachable
tco.exit.1:
  %t41 = load ptr, ptr %t2
  ret ptr %t41
}

define internal ptr @v_show(ptr %v_xs) {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 21 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  call void @__inc_ref(ptr %v_xs)
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v_xs, ptr %t3
  %t4 = call ptr @v__scc_show_showCons(ptr %t0)
  call void @__free_recursive(ptr %v_xs)
  ret ptr %t4
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
