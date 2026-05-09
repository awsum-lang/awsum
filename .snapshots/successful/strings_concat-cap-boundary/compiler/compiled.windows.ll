; External C declarations
declare ptr @malloc(i64)
declare ptr @memcpy(ptr, ptr, i64)
declare i64 @strlen(ptr)
declare i64 @write(i32, ptr, i64)
declare i32 @printf(ptr, ...)
declare i32 @snprintf(ptr, i64, ptr, ...)

@.fmt_i32 = private unnamed_addr constant [3 x i8] c"%d\00"
@.fmt_u8 = private unnamed_addr constant [3 x i8] c"%u\00"
@.empty = private unnamed_addr constant {i32, i32} { i32 0, i32 0 }
@.cli_arg = internal global ptr null

@.str.0 = private unnamed_addr constant {i32, i32, [384 x i8]} { i32 384, i32 128, [384 x i8] c"\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C\E4\BD\A0\E5\A5\BD\E4\B8\96\E7\95\8C" }
@.str.1 = private unnamed_addr constant {i32, i32, [36 x i8]} { i32 36, i32 36, [36 x i8] c"FAIL: build returned Left at the cap" }
@.str.2 = private unnamed_addr constant {i32, i32, [1 x i8]} { i32 1, i32 1, [1 x i8] c"!" }
@.str.3 = private unnamed_addr constant {i32, i32, [2 x i8]} { i32 2, i32 2, [2 x i8] c"OK" }
@.str.4 = private unnamed_addr constant {i32, i32, [28 x i8]} { i32 28, i32 28, [28 x i8] c"FAIL: cap + 1 returned Right" }
@.str.5 = private unnamed_addr constant {i32, i32, [39 x i8]} { i32 39, i32 39, [39 x i8] c"FAIL: built string length is not at cap" }

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
  %stl = call ptr @malloc(i64 8)
  %stl_tag = inttoptr i64 15 to ptr
  store ptr %stl_tag, ptr %stl
  %left = call ptr @malloc(i64 16)
  %left_tag = inttoptr i64 3 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %stl, ptr %left_f
  ret ptr %left
ok:
  %ba64 = zext i32 %ba to i64
  %bb64 = zext i32 %bb to i64
  %bsum64 = add i64 %ba64, %bb64
  %alloc64 = add i64 %bsum64, 8
  %buf = call ptr @malloc(i64 %alloc64)
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
  %right = call ptr @malloc(i64 16)
  %right_tag = inttoptr i64 4 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %buf, ptr %right_f
  ret ptr %right
}


define internal ptr @__print(ptr %s) {
  %byte_count = load i32, ptr %s
  %byte_count_64 = zext i32 %byte_count to i64
  %payload = getelementptr i8, ptr %s, i64 8
  call i64 @write(i32 1, ptr %payload, i64 %byte_count_64)
  %unit = call ptr @malloc(i64 8)
  %unit_tag_ptr = getelementptr ptr, ptr %unit, i32 0
  %unit_tag = inttoptr i64 0 to ptr
  store ptr %unit_tag, ptr %unit_tag_ptr
  ret ptr %unit
}


define internal ptr @__predUInt32(ptr %p) {
  %v = load i32, ptr %p
  %is_zero = icmp eq i32 %v, 0
  br i1 %is_zero, label %overflow, label %ok
overflow:
  %ue = call ptr @malloc(i64 8)
  %ue_tag = inttoptr i64 13 to ptr
  store ptr %ue_tag, ptr %ue
  %left = call ptr @malloc(i64 16)
  %left_tag = inttoptr i64 3 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %ue, ptr %left_f
  ret ptr %left
ok:
  %newv = sub i32 %v, 1
  %box = call ptr @malloc(i64 4)
  store i32 %newv, ptr %box
  %right = call ptr @malloc(i64 16)
  %right_tag = inttoptr i64 4 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %box, ptr %right_f
  ret ptr %right
}


define internal ptr @__eqUInt32(ptr %a, ptr %b) {
  %va = load i32, ptr %a
  %vb = load i32, ptr %b
  %eq = icmp eq i32 %va, %vb
  %tag = select i1 %eq, i64 1, i64 2
  %box = call ptr @malloc(i64 8)
  %tag_ptr = inttoptr i64 %tag to ptr
  store ptr %tag_ptr, ptr %box
  ret ptr %box
}


define internal ptr @__lengthUtf16CodeUnits(ptr %s) {
  %u16p = getelementptr i8, ptr %s, i64 4
  %u16 = load i32, ptr %u16p
  %box = call ptr @malloc(i64 4)
  store i32 %u16, ptr %box
  ret ptr %box
}


define internal ptr @v_maxStringLengthUtf16CodeUnits() {
  %t0 = call ptr @malloc(i64 4)
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
  store ptr %t11, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.12:
  %t13 = getelementptr ptr, ptr %t4, i32 1
  %t14 = load ptr, ptr %t13
  %t15 = getelementptr ptr, ptr %t4, i32 2
  %t16 = load ptr, ptr %t15
  %t17 = call ptr @__print(ptr %t14)
  %t18 = getelementptr ptr, ptr %t17, i32 0
  %t19 = load ptr, ptr %t18
  %t20 = ptrtoint ptr %t19 to i64
  switch i64 %t20, label %tco.case.default.21 [ i64 0, label %tco.case.arm.0.22 ]
tco.case.arm.0.22:
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
  ret ptr @.str.0
}

define internal ptr @v_runTest() {
  %t0 = call ptr @malloc(i64 4)
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
  br label %case.end.3.9
case.end.3.9:
  br label %case.join.7
case.arm.4.12:
  %t14 = getelementptr ptr, ptr %t2, i32 1
  %t15 = load ptr, ptr %t14
  %t16 = call ptr @__lengthUtf16CodeUnits(ptr %t15)
  %t17 = call ptr @v_maxStringLengthUtf16CodeUnits()
  %t18 = call ptr @__eqUInt32(ptr %t16, ptr %t17)
  %t19 = getelementptr ptr, ptr %t18, i32 0
  %t20 = load ptr, ptr %t19
  %t21 = ptrtoint ptr %t20 to i64
  switch i64 %t21, label %case.default.22 [ i64 1, label %case.arm.1.24 i64 2, label %case.arm.2.41 ]
case.arm.1.24:
  %t26 = call ptr @__concat(ptr %t15, ptr @.str.2)
  %t27 = getelementptr ptr, ptr %t26, i32 0
  %t28 = load ptr, ptr %t27
  %t29 = ptrtoint ptr %t28 to i64
  switch i64 %t29, label %case.default.30 [ i64 3, label %case.arm.3.32 i64 4, label %case.arm.4.36 ]
case.arm.3.32:
  %t34 = getelementptr ptr, ptr %t26, i32 1
  %t35 = load ptr, ptr %t34
  br label %case.end.3.33
case.end.3.33:
  br label %case.join.31
case.arm.4.36:
  %t38 = getelementptr ptr, ptr %t26, i32 1
  %t39 = load ptr, ptr %t38
  br label %case.end.4.37
case.end.4.37:
  br label %case.join.31
case.default.30:
  unreachable
case.join.31:
  %t40 = phi ptr [@.str.3, %case.end.3.33], [@.str.4, %case.end.4.37]
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
  %t43 = phi ptr [%t40, %case.end.1.25], [@.str.5, %case.end.2.42]
  br label %case.end.4.13
case.end.4.13:
  br label %case.join.7
case.default.6:
  unreachable
case.join.7:
  %t44 = phi ptr [@.str.1, %case.end.3.9], [%t43, %case.end.4.13]
  ret ptr %t44
}

define internal ptr @v_main() {
  %t0 = call ptr @malloc(i64 24)
  %t1 = inttoptr i64 7 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_runTest()
  %t4 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t4
  %t5 = call ptr @malloc(i64 16)
  %t6 = inttoptr i64 5 to ptr
  %t7 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t6, ptr %t7
  %t8 = call ptr @malloc(i64 8)
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
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.5 i64 4, label %case.arm.4.13 ]
case.arm.3.5:
  %t7 = getelementptr ptr, ptr %v___input, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = call ptr @malloc(i64 16)
  %t10 = inttoptr i64 3 to ptr
  %t11 = getelementptr ptr, ptr %t9, i32 0
  store ptr %t10, ptr %t11
  %t12 = getelementptr ptr, ptr %t9, i32 1
  store ptr %t8, ptr %t12
  br label %case.end.3.6
case.end.3.6:
  br label %case.join.4
case.arm.4.13:
  %t15 = getelementptr ptr, ptr %v___input, i32 1
  %t16 = load ptr, ptr %t15
  %t17 = call ptr @malloc(i64 16)
  %t18 = inttoptr i64 4 to ptr
  %t19 = getelementptr ptr, ptr %t17, i32 0
  store ptr %t18, ptr %t19
  %t20 = getelementptr ptr, ptr %t17, i32 1
  store ptr %t16, ptr %t20
  br label %case.end.4.14
case.end.4.14:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t21 = phi ptr [%t9, %case.end.3.6], [%t17, %case.end.4.14]
  ret ptr %t21
}

define internal ptr @v__scc__df_andThenEither_0__lam_7_build(ptr %v__args) {
  %t0 = call ptr @malloc(i64 8)
  %t1 = inttoptr i64 11 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__scc__df_andThenEither_0__lam_7_build(ptr %v__args, ptr %t0)
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
  switch i64 %t9, label %tco.case.default.10 [ i64 8, label %tco.case.arm.8.11 i64 9, label %tco.case.arm.9.40 i64 10, label %tco.case.arm.10.50 ]
tco.case.arm.8.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  %t14 = getelementptr ptr, ptr %t5, i32 2
  %t15 = load ptr, ptr %t14
  %t16 = getelementptr ptr, ptr %t13, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %tco.case.default.19 [ i64 3, label %tco.case.arm.3.20 i64 4, label %tco.case.arm.4.28 ]
tco.case.arm.3.20:
  %t21 = getelementptr ptr, ptr %t13, i32 1
  %t22 = load ptr, ptr %t21
  %t23 = call ptr @malloc(i64 16)
  %t24 = inttoptr i64 3 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  %t26 = getelementptr ptr, ptr %t23, i32 1
  store ptr %t22, ptr %t26
  %t27 = call ptr @v__apply__scc__df_andThenEither_0__lam_7_build(ptr %t6, ptr %t23)
  store ptr %t27, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.28:
  %t29 = getelementptr ptr, ptr %t13, i32 1
  %t30 = load ptr, ptr %t29
  %t31 = call ptr @malloc(i64 24)
  %t32 = inttoptr i64 9 to ptr
  %t33 = getelementptr ptr, ptr %t31, i32 0
  store ptr %t32, ptr %t33
  %t34 = getelementptr ptr, ptr %t31, i32 1
  store ptr %t15, ptr %t34
  %t35 = getelementptr ptr, ptr %t31, i32 2
  store ptr %t30, ptr %t35
  %t36 = call ptr @malloc(i64 16)
  %t37 = inttoptr i64 12 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t6, ptr %t39
  store ptr %t31, ptr %t3
  store ptr %t36, ptr %t4
  br label %tco.loop.0
tco.case.default.19:
  unreachable
tco.case.arm.9.40:
  %t41 = getelementptr ptr, ptr %t5, i32 1
  %t42 = load ptr, ptr %t41
  %t43 = getelementptr ptr, ptr %t5, i32 2
  %t44 = load ptr, ptr %t43
  %t45 = call ptr @malloc(i64 24)
  %t46 = inttoptr i64 10 to ptr
  %t47 = getelementptr ptr, ptr %t45, i32 0
  store ptr %t46, ptr %t47
  %t48 = getelementptr ptr, ptr %t45, i32 1
  store ptr %t42, ptr %t48
  %t49 = getelementptr ptr, ptr %t45, i32 2
  store ptr %t44, ptr %t49
  store ptr %t45, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.10.50:
  %t51 = getelementptr ptr, ptr %t5, i32 1
  %t52 = load ptr, ptr %t51
  %t53 = getelementptr ptr, ptr %t5, i32 2
  %t54 = load ptr, ptr %t53
  %t55 = call ptr @__predUInt32(ptr %t52)
  %t56 = getelementptr ptr, ptr %t55, i32 0
  %t57 = load ptr, ptr %t56
  %t58 = ptrtoint ptr %t57 to i64
  switch i64 %t58, label %tco.case.default.59 [ i64 3, label %tco.case.arm.3.60 i64 4, label %tco.case.arm.4.68 ]
tco.case.arm.3.60:
  %t61 = getelementptr ptr, ptr %t55, i32 1
  %t62 = load ptr, ptr %t61
  %t63 = call ptr @malloc(i64 16)
  %t64 = inttoptr i64 4 to ptr
  %t65 = getelementptr ptr, ptr %t63, i32 0
  store ptr %t64, ptr %t65
  %t66 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t54, ptr %t66
  %t67 = call ptr @v__apply__scc__df_andThenEither_0__lam_7_build(ptr %t6, ptr %t63)
  store ptr %t67, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.68:
  %t69 = getelementptr ptr, ptr %t55, i32 1
  %t70 = load ptr, ptr %t69
  %t71 = call ptr @malloc(i64 24)
  %t72 = inttoptr i64 8 to ptr
  %t73 = getelementptr ptr, ptr %t71, i32 0
  store ptr %t72, ptr %t73
  %t74 = call ptr @__concat(ptr %t54, ptr %t54)
  %t75 = getelementptr ptr, ptr %t71, i32 1
  store ptr %t74, ptr %t75
  %t76 = getelementptr ptr, ptr %t71, i32 2
  store ptr %t70, ptr %t76
  store ptr %t71, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.default.59:
  unreachable
tco.case.default.10:
  unreachable
tco.exit.1:
  %t77 = load ptr, ptr %t2
  ret ptr %t77
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
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.12.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  %t15 = call ptr @v__lift_0(ptr %t6)
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
  %t0 = call ptr @malloc(i64 24)
  %t1 = inttoptr i64 10 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v_n, ptr %t3
  %t4 = getelementptr ptr, ptr %t0, i32 2
  store ptr %v_acc, ptr %t4
  %t5 = call ptr @v__scc__df_andThenEither_0__lam_7_build(ptr %t0)
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
  %buf = call ptr @malloc(i64 %needed64)
  %written = call i32 @WideCharToMultiByte(i32 65001, i32 0, ptr %arg_w, i32 -1, ptr %buf, i32 %needed, ptr null, ptr null)
  br label %call_main
no_arg:
  br label %call_main
call_main:
  %input = phi ptr [%buf, %do_convert], [@.empty, %no_arg]
  store ptr %input, ptr @.cli_arg
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
