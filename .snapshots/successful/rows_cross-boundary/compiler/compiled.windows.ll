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

@.str.0 = private unnamed_addr constant {i32, i32, [1 x i8]} { i32 1, i32 1, [1 x i8] c"T" }
@.str.1 = private unnamed_addr constant {i32, i32, [1 x i8]} { i32 1, i32 1, [1 x i8] c"F" }
@.str.2 = private unnamed_addr constant {i32, i32, [1 x i8]} { i32 1, i32 1, [1 x i8] c"N" }
@.str.3 = private unnamed_addr constant {i32, i32, [1 x i8]} { i32 1, i32 1, [1 x i8] c"J" }
@.str.4 = private unnamed_addr constant {i32, i32, [0 x i8]} { i32 0, i32 0, [0 x i8] zeroinitializer }
@.str.5 = private unnamed_addr constant {i32, i32, [4 x i8]} { i32 4, i32 4, [4 x i8] c"ErrA" }
@.str.6 = private unnamed_addr constant {i32, i32, [3 x i8]} { i32 3, i32 3, [3 x i8] c" / " }
@.str.7 = private unnamed_addr constant {i32, i32, [15 x i8]} { i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }

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

define internal ptr @v_defaultJust() {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 10 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @malloc(i64 8)
  %t4 = inttoptr i64 1 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  ret ptr %t0
}

define internal ptr @v_defaultBools() {
  %t0 = call ptr @malloc(i64 24)
  %t1 = inttoptr i64 21 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @malloc(i64 8)
  %t4 = inttoptr i64 1 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  %t7 = call ptr @malloc(i64 24)
  %t8 = inttoptr i64 21 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = call ptr @malloc(i64 8)
  %t11 = inttoptr i64 2 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  %t13 = getelementptr ptr, ptr %t7, i32 1
  store ptr %t10, ptr %t13
  %t14 = call ptr @malloc(i64 8)
  %t15 = inttoptr i64 20 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  %t17 = call ptr @v__lift_7(ptr %t14)
  %t18 = getelementptr ptr, ptr %t7, i32 2
  store ptr %t17, ptr %t18
  %t19 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t7, ptr %t19
  ret ptr %t0
}

define internal ptr @v_defaultRight() {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 4 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @malloc(i64 16)
  %t4 = inttoptr i64 10 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = call ptr @malloc(i64 8)
  %t7 = inttoptr i64 2 to ptr
  %t8 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t7, ptr %t8
  %t9 = getelementptr ptr, ptr %t3, i32 1
  store ptr %t6, ptr %t9
  %t10 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t10
  ret ptr %t0
}

define internal ptr @v_dispatchInner(ptr %v_x) {
  %t0 = getelementptr ptr, ptr %v_x, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 796142685, label %case.arm.796142685.5 ]
case.arm.796142685.5:
  %t7 = getelementptr ptr, ptr %v_x, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr ptr, ptr %t8, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %case.default.12 [ i64 1, label %case.arm.1.14 i64 2, label %case.arm.2.16 ]
case.arm.1.14:
  br label %case.end.1.15
case.end.1.15:
  br label %case.join.13
case.arm.2.16:
  br label %case.end.2.17
case.end.2.17:
  br label %case.join.13
case.default.12:
  unreachable
case.join.13:
  %t18 = phi ptr [@.str.0, %case.end.1.15], [@.str.1, %case.end.2.17]
  br label %case.end.796142685.6
case.end.796142685.6:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t19 = phi ptr [%t18, %case.end.796142685.6]
  ret ptr %t19
}

define internal ptr @v_describeMaybe(ptr %v_m) {
  %t0 = getelementptr ptr, ptr %v_m, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 9, label %case.arm.9.5 i64 10, label %case.arm.10.11 ]
case.arm.9.5:
  %t7 = call ptr @malloc(i64 16)
  %t8 = inttoptr i64 4 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = getelementptr ptr, ptr %t7, i32 1
  store ptr @.str.2, ptr %t10
  br label %case.end.9.6
case.end.9.6:
  br label %case.join.4
case.arm.10.11:
  %t13 = getelementptr ptr, ptr %v_m, i32 1
  %t14 = load ptr, ptr %t13
  %t15 = call ptr @v_dispatchInner(ptr %t14)
  %t16 = call ptr @__concat(ptr @.str.3, ptr %t15)
  br label %case.end.10.12
case.end.10.12:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t17 = phi ptr [%t7, %case.end.9.6], [%t16, %case.end.10.12]
  ret ptr %t17
}

define internal ptr @v_describeLst(ptr %v_xs) {
  %t0 = call ptr @malloc(i64 8)
  %t1 = inttoptr i64 22 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps_describeLst(ptr %v_xs, ptr %t0)
  ret ptr %t3
}

define internal ptr @v__cps_describeLst(ptr %v_xs, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 20, label %tco.case.arm.20.11 i64 21, label %tco.case.arm.21.17 ]
tco.case.arm.20.11:
  %t12 = call ptr @malloc(i64 16)
  %t13 = inttoptr i64 4 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr @.str.4, ptr %t15
  %t16 = call ptr @v__apply_describeLst(ptr %t6, ptr %t12)
  store ptr %t16, ptr %t2
  br label %tco.exit.1
tco.case.arm.21.17:
  %t18 = getelementptr ptr, ptr %t5, i32 1
  %t19 = load ptr, ptr %t18
  %t20 = getelementptr ptr, ptr %t5, i32 2
  %t21 = load ptr, ptr %t20
  %t22 = call ptr @malloc(i64 24)
  %t23 = inttoptr i64 23 to ptr
  %t24 = getelementptr ptr, ptr %t22, i32 0
  store ptr %t23, ptr %t24
  %t25 = getelementptr ptr, ptr %t22, i32 1
  store ptr %t6, ptr %t25
  %t26 = getelementptr ptr, ptr %t22, i32 2
  store ptr %t19, ptr %t26
  store ptr %t21, ptr %t3
  store ptr %t22, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t27 = load ptr, ptr %t2
  ret ptr %t27
}

define internal ptr @v__apply_describeLst(ptr %v__k, ptr %v__x) {
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
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.23.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  %t15 = getelementptr ptr, ptr %t5, i32 2
  %t16 = load ptr, ptr %t15
  %t17 = getelementptr ptr, ptr %t6, i32 0
  %t18 = load ptr, ptr %t17
  %t19 = ptrtoint ptr %t18 to i64
  switch i64 %t19, label %tco.case.default.20 [ i64 3, label %tco.case.arm.3.21 i64 4, label %tco.case.arm.4.28 ]
tco.case.arm.3.21:
  %t22 = getelementptr ptr, ptr %t6, i32 1
  %t23 = load ptr, ptr %t22
  %t24 = call ptr @malloc(i64 16)
  %t25 = inttoptr i64 3 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = getelementptr ptr, ptr %t24, i32 1
  store ptr %t23, ptr %t27
  store ptr %t14, ptr %t3
  store ptr %t24, ptr %t4
  br label %tco.loop.0
tco.case.arm.4.28:
  %t29 = getelementptr ptr, ptr %t6, i32 1
  %t30 = load ptr, ptr %t29
  %t31 = call ptr @v_dispatchInner(ptr %t16)
  %t32 = call ptr @__concat(ptr %t31, ptr %t30)
  store ptr %t14, ptr %t3
  store ptr %t32, ptr %t4
  br label %tco.loop.0
tco.case.default.20:
  unreachable
tco.case.default.10:
  unreachable
tco.exit.1:
  %t33 = load ptr, ptr %t2
  ret ptr %t33
}

define internal ptr @v_describeEither(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.5 i64 4, label %case.arm.4.13 ]
case.arm.3.5:
  %t7 = getelementptr ptr, ptr %v_r, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = call ptr @malloc(i64 16)
  %t10 = inttoptr i64 4 to ptr
  %t11 = getelementptr ptr, ptr %t9, i32 0
  store ptr %t10, ptr %t11
  %t12 = getelementptr ptr, ptr %t9, i32 1
  store ptr @.str.5, ptr %t12
  br label %case.end.3.6
case.end.3.6:
  br label %case.join.4
case.arm.4.13:
  %t15 = getelementptr ptr, ptr %v_r, i32 1
  %t16 = load ptr, ptr %t15
  %t17 = call ptr @v_describeMaybe(ptr %t16)
  br label %case.end.4.14
case.end.4.14:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t18 = phi ptr [%t9, %case.end.3.6], [%t17, %case.end.4.14]
  ret ptr %t18
}

define internal ptr @v_summary() {
  %t0 = call ptr @v_defaultJust()
  %t1 = call ptr @v__lift_8(ptr %t0)
  %t2 = call ptr @v_describeMaybe(ptr %t1)
  %t3 = getelementptr ptr, ptr %t2, i32 0
  %t4 = load ptr, ptr %t3
  %t5 = ptrtoint ptr %t4 to i64
  switch i64 %t5, label %case.default.6 [ i64 3, label %case.arm.3.8 i64 4, label %case.arm.4.16 ]
case.arm.3.8:
  %t10 = getelementptr ptr, ptr %t2, i32 1
  %t11 = load ptr, ptr %t10
  %t12 = call ptr @malloc(i64 16)
  %t13 = inttoptr i64 3 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t11, ptr %t15
  br label %case.end.3.9
case.end.3.9:
  br label %case.join.7
case.arm.4.16:
  %t18 = getelementptr ptr, ptr %t2, i32 1
  %t19 = load ptr, ptr %t18
  %t20 = call ptr @v_defaultBools()
  %t21 = call ptr @v__lift_9(ptr %t20)
  %t22 = call ptr @v_describeLst(ptr %t21)
  %t23 = getelementptr ptr, ptr %t22, i32 0
  %t24 = load ptr, ptr %t23
  %t25 = ptrtoint ptr %t24 to i64
  switch i64 %t25, label %case.default.26 [ i64 3, label %case.arm.3.28 i64 4, label %case.arm.4.36 ]
case.arm.3.28:
  %t30 = getelementptr ptr, ptr %t22, i32 1
  %t31 = load ptr, ptr %t30
  %t32 = call ptr @malloc(i64 16)
  %t33 = inttoptr i64 3 to ptr
  %t34 = getelementptr ptr, ptr %t32, i32 0
  store ptr %t33, ptr %t34
  %t35 = getelementptr ptr, ptr %t32, i32 1
  store ptr %t31, ptr %t35
  br label %case.end.3.29
case.end.3.29:
  br label %case.join.27
case.arm.4.36:
  %t38 = getelementptr ptr, ptr %t22, i32 1
  %t39 = load ptr, ptr %t38
  %t40 = call ptr @v_defaultRight()
  %t41 = call ptr @v__lift_10(ptr %t40)
  %t42 = call ptr @v_describeEither(ptr %t41)
  %t43 = getelementptr ptr, ptr %t42, i32 0
  %t44 = load ptr, ptr %t43
  %t45 = ptrtoint ptr %t44 to i64
  switch i64 %t45, label %case.default.46 [ i64 3, label %case.arm.3.48 i64 4, label %case.arm.4.56 ]
case.arm.3.48:
  %t50 = getelementptr ptr, ptr %t42, i32 1
  %t51 = load ptr, ptr %t50
  %t52 = call ptr @malloc(i64 16)
  %t53 = inttoptr i64 3 to ptr
  %t54 = getelementptr ptr, ptr %t52, i32 0
  store ptr %t53, ptr %t54
  %t55 = getelementptr ptr, ptr %t52, i32 1
  store ptr %t51, ptr %t55
  br label %case.end.3.49
case.end.3.49:
  br label %case.join.47
case.arm.4.56:
  %t58 = getelementptr ptr, ptr %t42, i32 1
  %t59 = load ptr, ptr %t58
  %t60 = call ptr @__concat(ptr %t19, ptr @.str.6)
  %t61 = getelementptr ptr, ptr %t60, i32 0
  %t62 = load ptr, ptr %t61
  %t63 = ptrtoint ptr %t62 to i64
  switch i64 %t63, label %case.default.64 [ i64 3, label %case.arm.3.66 i64 4, label %case.arm.4.74 ]
case.arm.3.66:
  %t68 = getelementptr ptr, ptr %t60, i32 1
  %t69 = load ptr, ptr %t68
  %t70 = call ptr @malloc(i64 16)
  %t71 = inttoptr i64 3 to ptr
  %t72 = getelementptr ptr, ptr %t70, i32 0
  store ptr %t71, ptr %t72
  %t73 = getelementptr ptr, ptr %t70, i32 1
  store ptr %t69, ptr %t73
  br label %case.end.3.67
case.end.3.67:
  br label %case.join.65
case.arm.4.74:
  %t76 = getelementptr ptr, ptr %t60, i32 1
  %t77 = load ptr, ptr %t76
  %t78 = call ptr @__concat(ptr %t77, ptr %t39)
  %t79 = getelementptr ptr, ptr %t78, i32 0
  %t80 = load ptr, ptr %t79
  %t81 = ptrtoint ptr %t80 to i64
  switch i64 %t81, label %case.default.82 [ i64 3, label %case.arm.3.84 i64 4, label %case.arm.4.92 ]
case.arm.3.84:
  %t86 = getelementptr ptr, ptr %t78, i32 1
  %t87 = load ptr, ptr %t86
  %t88 = call ptr @malloc(i64 16)
  %t89 = inttoptr i64 3 to ptr
  %t90 = getelementptr ptr, ptr %t88, i32 0
  store ptr %t89, ptr %t90
  %t91 = getelementptr ptr, ptr %t88, i32 1
  store ptr %t87, ptr %t91
  br label %case.end.3.85
case.end.3.85:
  br label %case.join.83
case.arm.4.92:
  %t94 = getelementptr ptr, ptr %t78, i32 1
  %t95 = load ptr, ptr %t94
  %t96 = call ptr @__concat(ptr %t95, ptr @.str.6)
  %t97 = getelementptr ptr, ptr %t96, i32 0
  %t98 = load ptr, ptr %t97
  %t99 = ptrtoint ptr %t98 to i64
  switch i64 %t99, label %case.default.100 [ i64 3, label %case.arm.3.102 i64 4, label %case.arm.4.110 ]
case.arm.3.102:
  %t104 = getelementptr ptr, ptr %t96, i32 1
  %t105 = load ptr, ptr %t104
  %t106 = call ptr @malloc(i64 16)
  %t107 = inttoptr i64 3 to ptr
  %t108 = getelementptr ptr, ptr %t106, i32 0
  store ptr %t107, ptr %t108
  %t109 = getelementptr ptr, ptr %t106, i32 1
  store ptr %t105, ptr %t109
  br label %case.end.3.103
case.end.3.103:
  br label %case.join.101
case.arm.4.110:
  %t112 = getelementptr ptr, ptr %t96, i32 1
  %t113 = load ptr, ptr %t112
  %t114 = call ptr @__concat(ptr %t113, ptr %t59)
  br label %case.end.4.111
case.end.4.111:
  br label %case.join.101
case.default.100:
  unreachable
case.join.101:
  %t115 = phi ptr [%t106, %case.end.3.103], [%t114, %case.end.4.111]
  br label %case.end.4.93
case.end.4.93:
  br label %case.join.83
case.default.82:
  unreachable
case.join.83:
  %t116 = phi ptr [%t88, %case.end.3.85], [%t115, %case.end.4.93]
  br label %case.end.4.75
case.end.4.75:
  br label %case.join.65
case.default.64:
  unreachable
case.join.65:
  %t117 = phi ptr [%t70, %case.end.3.67], [%t116, %case.end.4.75]
  br label %case.end.4.57
case.end.4.57:
  br label %case.join.47
case.default.46:
  unreachable
case.join.47:
  %t118 = phi ptr [%t52, %case.end.3.49], [%t117, %case.end.4.57]
  br label %case.end.4.37
case.end.4.37:
  br label %case.join.27
case.default.26:
  unreachable
case.join.27:
  %t119 = phi ptr [%t32, %case.end.3.29], [%t118, %case.end.4.37]
  br label %case.end.4.17
case.end.4.17:
  br label %case.join.7
case.default.6:
  unreachable
case.join.7:
  %t120 = phi ptr [%t12, %case.end.3.9], [%t119, %case.end.4.17]
  ret ptr %t120
}

define internal ptr @v_main() {
  %t0 = call ptr @v_summary()
  %t1 = call ptr @v__let_11(ptr %t0)
  ret ptr %t1
}

define internal ptr @v__lift_7(ptr %v___input) {
  %t0 = call ptr @malloc(i64 8)
  %t1 = inttoptr i64 24 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__lift_7(ptr %v___input, ptr %t0)
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
  switch i64 %t9, label %tco.case.default.10 [ i64 20, label %tco.case.arm.20.11 i64 21, label %tco.case.arm.21.16 ]
tco.case.arm.20.11:
  %t12 = call ptr @malloc(i64 8)
  %t13 = inttoptr i64 20 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = call ptr @v__apply__lift_7(ptr %t6, ptr %t12)
  store ptr %t15, ptr %t2
  br label %tco.exit.1
tco.case.arm.21.16:
  %t17 = getelementptr ptr, ptr %t5, i32 1
  %t18 = load ptr, ptr %t17
  %t19 = getelementptr ptr, ptr %t5, i32 2
  %t20 = load ptr, ptr %t19
  %t21 = call ptr @malloc(i64 24)
  %t22 = inttoptr i64 25 to ptr
  %t23 = getelementptr ptr, ptr %t21, i32 0
  store ptr %t22, ptr %t23
  %t24 = getelementptr ptr, ptr %t21, i32 1
  store ptr %t6, ptr %t24
  %t25 = getelementptr ptr, ptr %t21, i32 2
  store ptr %t18, ptr %t25
  store ptr %t20, ptr %t3
  store ptr %t21, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t26 = load ptr, ptr %t2
  ret ptr %t26
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
  switch i64 %t9, label %tco.case.default.10 [ i64 24, label %tco.case.arm.24.11 i64 25, label %tco.case.arm.25.12 ]
tco.case.arm.24.11:
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.25.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  %t15 = getelementptr ptr, ptr %t5, i32 2
  %t16 = load ptr, ptr %t15
  %t17 = call ptr @malloc(i64 24)
  %t18 = inttoptr i64 21 to ptr
  %t19 = getelementptr ptr, ptr %t17, i32 0
  store ptr %t18, ptr %t19
  %t20 = getelementptr ptr, ptr %t17, i32 1
  store ptr %t16, ptr %t20
  %t21 = getelementptr ptr, ptr %t17, i32 2
  store ptr %t6, ptr %t21
  store ptr %t14, ptr %t3
  store ptr %t17, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t22 = load ptr, ptr %t2
  ret ptr %t22
}

define internal ptr @v__lift_8(ptr %v___input) {
  %t0 = getelementptr ptr, ptr %v___input, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 9, label %case.arm.9.5 i64 10, label %case.arm.10.10 ]
case.arm.9.5:
  %t7 = call ptr @malloc(i64 8)
  %t8 = inttoptr i64 9 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  br label %case.end.9.6
case.end.9.6:
  br label %case.join.4
case.arm.10.10:
  %t12 = getelementptr ptr, ptr %v___input, i32 1
  %t13 = load ptr, ptr %t12
  %t14 = call ptr @malloc(i64 16)
  %t15 = inttoptr i64 10 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  %t17 = call ptr @malloc(i64 16)
  %t18 = inttoptr i64 796142685 to ptr
  %t19 = getelementptr ptr, ptr %t17, i32 0
  store ptr %t18, ptr %t19
  %t20 = getelementptr ptr, ptr %t17, i32 1
  store ptr %t13, ptr %t20
  %t21 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t17, ptr %t21
  br label %case.end.10.11
case.end.10.11:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t22 = phi ptr [%t7, %case.end.9.6], [%t14, %case.end.10.11]
  ret ptr %t22
}

define internal ptr @v__lift_9(ptr %v___input) {
  %t0 = call ptr @malloc(i64 8)
  %t1 = inttoptr i64 26 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__lift_9(ptr %v___input, ptr %t0)
  ret ptr %t3
}

define internal ptr @v__cps__lift_9(ptr %v___input, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 20, label %tco.case.arm.20.11 i64 21, label %tco.case.arm.21.16 ]
tco.case.arm.20.11:
  %t12 = call ptr @malloc(i64 8)
  %t13 = inttoptr i64 20 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = call ptr @v__apply__lift_9(ptr %t6, ptr %t12)
  store ptr %t15, ptr %t2
  br label %tco.exit.1
tco.case.arm.21.16:
  %t17 = getelementptr ptr, ptr %t5, i32 1
  %t18 = load ptr, ptr %t17
  %t19 = getelementptr ptr, ptr %t5, i32 2
  %t20 = load ptr, ptr %t19
  %t21 = call ptr @malloc(i64 24)
  %t22 = inttoptr i64 27 to ptr
  %t23 = getelementptr ptr, ptr %t21, i32 0
  store ptr %t22, ptr %t23
  %t24 = getelementptr ptr, ptr %t21, i32 1
  store ptr %t6, ptr %t24
  %t25 = getelementptr ptr, ptr %t21, i32 2
  store ptr %t18, ptr %t25
  store ptr %t20, ptr %t3
  store ptr %t21, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t26 = load ptr, ptr %t2
  ret ptr %t26
}

define internal ptr @v__apply__lift_9(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 26, label %tco.case.arm.26.11 i64 27, label %tco.case.arm.27.12 ]
tco.case.arm.26.11:
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.27.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  %t15 = getelementptr ptr, ptr %t5, i32 2
  %t16 = load ptr, ptr %t15
  %t17 = call ptr @malloc(i64 24)
  %t18 = inttoptr i64 21 to ptr
  %t19 = getelementptr ptr, ptr %t17, i32 0
  store ptr %t18, ptr %t19
  %t20 = call ptr @malloc(i64 16)
  %t21 = inttoptr i64 796142685 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = getelementptr ptr, ptr %t20, i32 1
  store ptr %t16, ptr %t23
  %t24 = getelementptr ptr, ptr %t17, i32 1
  store ptr %t20, ptr %t24
  %t25 = getelementptr ptr, ptr %t17, i32 2
  store ptr %t6, ptr %t25
  store ptr %t14, ptr %t3
  store ptr %t17, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t26 = load ptr, ptr %t2
  ret ptr %t26
}

define internal ptr @v__lift_10(ptr %v___input) {
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
  %t20 = call ptr @v__lift_8(ptr %t16)
  %t21 = getelementptr ptr, ptr %t17, i32 1
  store ptr %t20, ptr %t21
  br label %case.end.4.14
case.end.4.14:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t22 = phi ptr [%t9, %case.end.3.6], [%t17, %case.end.4.14]
  ret ptr %t22
}

define internal ptr @v__let_11(ptr %v_res) {
  %t0 = getelementptr ptr, ptr %v_res, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.5 i64 4, label %case.arm.4.21 ]
case.arm.3.5:
  %t7 = getelementptr ptr, ptr %v_res, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = call ptr @malloc(i64 24)
  %t10 = inttoptr i64 7 to ptr
  %t11 = getelementptr ptr, ptr %t9, i32 0
  store ptr %t10, ptr %t11
  %t12 = getelementptr ptr, ptr %t9, i32 1
  store ptr @.str.7, ptr %t12
  %t13 = call ptr @malloc(i64 16)
  %t14 = inttoptr i64 5 to ptr
  %t15 = getelementptr ptr, ptr %t13, i32 0
  store ptr %t14, ptr %t15
  %t16 = call ptr @malloc(i64 8)
  %t17 = inttoptr i64 0 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = getelementptr ptr, ptr %t13, i32 1
  store ptr %t16, ptr %t19
  %t20 = getelementptr ptr, ptr %t9, i32 2
  store ptr %t13, ptr %t20
  br label %case.end.3.6
case.end.3.6:
  br label %case.join.4
case.arm.4.21:
  %t23 = getelementptr ptr, ptr %v_res, i32 1
  %t24 = load ptr, ptr %t23
  %t25 = call ptr @malloc(i64 24)
  %t26 = inttoptr i64 7 to ptr
  %t27 = getelementptr ptr, ptr %t25, i32 0
  store ptr %t26, ptr %t27
  %t28 = getelementptr ptr, ptr %t25, i32 1
  store ptr %t24, ptr %t28
  %t29 = call ptr @malloc(i64 16)
  %t30 = inttoptr i64 5 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = call ptr @malloc(i64 8)
  %t33 = inttoptr i64 0 to ptr
  %t34 = getelementptr ptr, ptr %t32, i32 0
  store ptr %t33, ptr %t34
  %t35 = getelementptr ptr, ptr %t29, i32 1
  store ptr %t32, ptr %t35
  %t36 = getelementptr ptr, ptr %t25, i32 2
  store ptr %t29, ptr %t36
  br label %case.end.4.22
case.end.4.22:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t37 = phi ptr [%t9, %case.end.3.6], [%t25, %case.end.4.22]
  ret ptr %t37
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
