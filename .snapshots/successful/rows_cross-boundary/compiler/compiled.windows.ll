; External C declarations
declare ptr @malloc(i64)
declare ptr @strcpy(ptr, ptr)
declare ptr @strcat(ptr, ptr)
declare i64 @strlen(ptr)
declare i32 @printf(ptr, ...)
declare i32 @snprintf(ptr, i64, ptr, ...)

@.fmt = private unnamed_addr constant [3 x i8] c"%s\00"
@.fmt_i32 = private unnamed_addr constant [3 x i8] c"%d\00"
@.fmt_u8 = private unnamed_addr constant [3 x i8] c"%u\00"
@.empty = private unnamed_addr constant [1 x i8] c"\00"

@.str.0 = private unnamed_addr constant [5 x i8] c"Unit\00"
@.str.1 = private unnamed_addr constant [2 x i8] c"T\00"
@.str.2 = private unnamed_addr constant [2 x i8] c"F\00"
@.str.3 = private unnamed_addr constant [2 x i8] c"N\00"
@.str.4 = private unnamed_addr constant [2 x i8] c"J\00"
@.str.5 = private unnamed_addr constant [1 x i8] c"\00"
@.str.6 = private unnamed_addr constant [5 x i8] c"ErrA\00"
@.str.7 = private unnamed_addr constant [4 x i8] c" / \00"
@.str.8 = private unnamed_addr constant [16 x i8] c"STRING_TOO_LONG\00"

define internal ptr @__concat(ptr %a, ptr %b) {
  %la = call i64 @strlen(ptr %a)
  %lb = call i64 @strlen(ptr %b)
  %sum = add i64 %la, %lb
  %total = add i64 %sum, 1
  %buf = call ptr @malloc(i64 %total)
  call ptr @strcpy(ptr %buf, ptr %a)
  call ptr @strcat(ptr %buf, ptr %b)
  ret ptr %buf
}


define internal ptr @__print(ptr %s) {
  call i32 (ptr, ...) @printf(ptr @.fmt, ptr %s)
  %unit = call ptr @malloc(i64 8)
  %unit_tag_ptr = getelementptr ptr, ptr %unit, i32 0
  %unit_tag = inttoptr i64 0 to ptr
  store ptr %unit_tag, ptr %unit_tag_ptr
  ret ptr %unit
}


define internal ptr @v_showUnit(ptr %v__wild0) {
  %t0 = getelementptr [5 x i8], ptr @.str.0, i64 0, i64 0
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
  switch i64 %t7, label %tco.case.default.8 [ i64 0, label %tco.case.arm.0.9 i64 2, label %tco.case.arm.2.12 ]
tco.case.arm.0.9:
  %t10 = getelementptr ptr, ptr %t4, i32 1
  %t11 = load ptr, ptr %t10
  store ptr %t11, ptr %t2
  br label %tco.exit.1
tco.case.arm.2.12:
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
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @malloc(i64 8)
  %t4 = inttoptr i64 0 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  ret ptr %t0
}

define internal ptr @v_defaultBools() {
  %t0 = call ptr @malloc(i64 24)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @malloc(i64 8)
  %t4 = inttoptr i64 0 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  %t7 = call ptr @malloc(i64 24)
  %t8 = inttoptr i64 1 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = call ptr @malloc(i64 8)
  %t11 = inttoptr i64 1 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  %t13 = getelementptr ptr, ptr %t7, i32 1
  store ptr %t10, ptr %t13
  %t14 = call ptr @malloc(i64 8)
  %t15 = inttoptr i64 0 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  %t17 = getelementptr ptr, ptr %t7, i32 2
  store ptr %t14, ptr %t17
  %t18 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t7, ptr %t18
  ret ptr %t0
}

define internal ptr @v_defaultRight() {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @malloc(i64 16)
  %t4 = inttoptr i64 1 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = call ptr @malloc(i64 8)
  %t7 = inttoptr i64 1 to ptr
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
  switch i64 %t2, label %case.default.3 [ i64 796142685, label %case.arm.796142685.5 i64 1759602215, label %case.arm.1759602215.21 ]
case.arm.796142685.5:
  %t7 = getelementptr ptr, ptr %v_x, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr ptr, ptr %t8, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %case.default.12 [ i64 0, label %case.arm.0.14 i64 1, label %case.arm.1.17 ]
case.arm.0.14:
  %t16 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  br label %case.end.0.15
case.end.0.15:
  br label %case.join.13
case.arm.1.17:
  %t19 = getelementptr [2 x i8], ptr @.str.2, i64 0, i64 0
  br label %case.end.1.18
case.end.1.18:
  br label %case.join.13
case.default.12:
  unreachable
case.join.13:
  %t20 = phi ptr [%t16, %case.end.0.15], [%t19, %case.end.1.18]
  br label %case.end.796142685.6
case.end.796142685.6:
  br label %case.join.4
case.arm.1759602215.21:
  %t23 = getelementptr ptr, ptr %v_x, i32 1
  %t24 = load ptr, ptr %t23
  %t25 = call ptr @v_showUnit(ptr %t24)
  br label %case.end.1759602215.22
case.end.1759602215.22:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t26 = phi ptr [%t20, %case.end.796142685.6], [%t25, %case.end.1759602215.22]
  ret ptr %t26
}

define internal ptr @v_describeMaybe(ptr %v_m) {
  %t0 = getelementptr ptr, ptr %v_m, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.12 ]
case.arm.0.5:
  %t7 = call ptr @malloc(i64 16)
  %t8 = inttoptr i64 1 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = getelementptr [2 x i8], ptr @.str.3, i64 0, i64 0
  %t11 = getelementptr ptr, ptr %t7, i32 1
  store ptr %t10, ptr %t11
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.12:
  %t14 = getelementptr ptr, ptr %v_m, i32 1
  %t15 = load ptr, ptr %t14
  %t16 = call ptr @malloc(i64 16)
  %t17 = inttoptr i64 1 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = getelementptr [2 x i8], ptr @.str.4, i64 0, i64 0
  %t20 = call ptr @v_dispatchInner(ptr %t15)
  %t21 = call ptr @__concat(ptr %t19, ptr %t20)
  %t22 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t21, ptr %t22
  br label %case.end.1.13
case.end.1.13:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t23 = phi ptr [%t7, %case.end.0.6], [%t16, %case.end.1.13]
  ret ptr %t23
}

define internal ptr @v_describeLst(ptr %v_xs) {
  %t0 = call ptr @malloc(i64 8)
  %t1 = inttoptr i64 0 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 0, label %tco.case.arm.0.11 i64 1, label %tco.case.arm.1.18 ]
tco.case.arm.0.11:
  %t12 = call ptr @malloc(i64 16)
  %t13 = inttoptr i64 1 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr [1 x i8], ptr @.str.5, i64 0, i64 0
  %t16 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t15, ptr %t16
  %t17 = call ptr @v__apply_describeLst(ptr %t6, ptr %t12)
  store ptr %t17, ptr %t2
  br label %tco.exit.1
tco.case.arm.1.18:
  %t19 = getelementptr ptr, ptr %t5, i32 1
  %t20 = load ptr, ptr %t19
  %t21 = getelementptr ptr, ptr %t5, i32 2
  %t22 = load ptr, ptr %t21
  %t23 = call ptr @malloc(i64 24)
  %t24 = inttoptr i64 1 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  %t26 = getelementptr ptr, ptr %t23, i32 1
  store ptr %t6, ptr %t26
  %t27 = getelementptr ptr, ptr %t23, i32 2
  store ptr %t20, ptr %t27
  store ptr %t22, ptr %t3
  store ptr %t23, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t28 = load ptr, ptr %t2
  ret ptr %t28
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
  switch i64 %t9, label %tco.case.default.10 [ i64 0, label %tco.case.arm.0.11 i64 1, label %tco.case.arm.1.12 ]
tco.case.arm.0.11:
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.1.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  %t15 = getelementptr ptr, ptr %t5, i32 2
  %t16 = load ptr, ptr %t15
  %t17 = getelementptr ptr, ptr %t6, i32 0
  %t18 = load ptr, ptr %t17
  %t19 = ptrtoint ptr %t18 to i64
  switch i64 %t19, label %tco.case.default.20 [ i64 0, label %tco.case.arm.0.21 i64 1, label %tco.case.arm.1.28 ]
tco.case.arm.0.21:
  %t22 = getelementptr ptr, ptr %t6, i32 1
  %t23 = load ptr, ptr %t22
  %t24 = call ptr @malloc(i64 16)
  %t25 = inttoptr i64 0 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = getelementptr ptr, ptr %t24, i32 1
  store ptr %t23, ptr %t27
  store ptr %t14, ptr %t3
  store ptr %t24, ptr %t4
  br label %tco.loop.0
tco.case.arm.1.28:
  %t29 = getelementptr ptr, ptr %t6, i32 1
  %t30 = load ptr, ptr %t29
  %t31 = call ptr @malloc(i64 16)
  %t32 = inttoptr i64 1 to ptr
  %t33 = getelementptr ptr, ptr %t31, i32 0
  store ptr %t32, ptr %t33
  %t34 = call ptr @v_dispatchInner(ptr %t16)
  %t35 = call ptr @__concat(ptr %t34, ptr %t30)
  %t36 = getelementptr ptr, ptr %t31, i32 1
  store ptr %t35, ptr %t36
  store ptr %t14, ptr %t3
  store ptr %t31, ptr %t4
  br label %tco.loop.0
tco.case.default.20:
  unreachable
tco.case.default.10:
  unreachable
tco.exit.1:
  %t37 = load ptr, ptr %t2
  ret ptr %t37
}

define internal ptr @v_describeEither(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.14 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_r, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = call ptr @malloc(i64 16)
  %t10 = inttoptr i64 1 to ptr
  %t11 = getelementptr ptr, ptr %t9, i32 0
  store ptr %t10, ptr %t11
  %t12 = getelementptr [5 x i8], ptr @.str.6, i64 0, i64 0
  %t13 = getelementptr ptr, ptr %t9, i32 1
  store ptr %t12, ptr %t13
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.14:
  %t16 = getelementptr ptr, ptr %v_r, i32 1
  %t17 = load ptr, ptr %t16
  %t18 = call ptr @v_describeMaybe(ptr %t17)
  br label %case.end.1.15
case.end.1.15:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t19 = phi ptr [%t9, %case.end.0.6], [%t18, %case.end.1.15]
  ret ptr %t19
}

define internal ptr @v_summary() {
  %t0 = call ptr @v_defaultJust()
  %t1 = call ptr @v__lift_2(ptr %t0)
  %t2 = call ptr @v_describeMaybe(ptr %t1)
  %t3 = getelementptr ptr, ptr %t2, i32 0
  %t4 = load ptr, ptr %t3
  %t5 = ptrtoint ptr %t4 to i64
  switch i64 %t5, label %case.default.6 [ i64 0, label %case.arm.0.8 i64 1, label %case.arm.1.16 ]
case.arm.0.8:
  %t10 = getelementptr ptr, ptr %t2, i32 1
  %t11 = load ptr, ptr %t10
  %t12 = call ptr @malloc(i64 16)
  %t13 = inttoptr i64 0 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t11, ptr %t15
  br label %case.end.0.9
case.end.0.9:
  br label %case.join.7
case.arm.1.16:
  %t18 = getelementptr ptr, ptr %t2, i32 1
  %t19 = load ptr, ptr %t18
  %t20 = call ptr @v_defaultBools()
  %t21 = call ptr @v__lift_3(ptr %t20)
  %t22 = call ptr @v_describeLst(ptr %t21)
  %t23 = getelementptr ptr, ptr %t22, i32 0
  %t24 = load ptr, ptr %t23
  %t25 = ptrtoint ptr %t24 to i64
  switch i64 %t25, label %case.default.26 [ i64 0, label %case.arm.0.28 i64 1, label %case.arm.1.36 ]
case.arm.0.28:
  %t30 = getelementptr ptr, ptr %t22, i32 1
  %t31 = load ptr, ptr %t30
  %t32 = call ptr @malloc(i64 16)
  %t33 = inttoptr i64 0 to ptr
  %t34 = getelementptr ptr, ptr %t32, i32 0
  store ptr %t33, ptr %t34
  %t35 = getelementptr ptr, ptr %t32, i32 1
  store ptr %t31, ptr %t35
  br label %case.end.0.29
case.end.0.29:
  br label %case.join.27
case.arm.1.36:
  %t38 = getelementptr ptr, ptr %t22, i32 1
  %t39 = load ptr, ptr %t38
  %t40 = call ptr @v_defaultRight()
  %t41 = call ptr @v__lift_4(ptr %t40)
  %t42 = call ptr @v_describeEither(ptr %t41)
  %t43 = getelementptr ptr, ptr %t42, i32 0
  %t44 = load ptr, ptr %t43
  %t45 = ptrtoint ptr %t44 to i64
  switch i64 %t45, label %case.default.46 [ i64 0, label %case.arm.0.48 i64 1, label %case.arm.1.56 ]
case.arm.0.48:
  %t50 = getelementptr ptr, ptr %t42, i32 1
  %t51 = load ptr, ptr %t50
  %t52 = call ptr @malloc(i64 16)
  %t53 = inttoptr i64 0 to ptr
  %t54 = getelementptr ptr, ptr %t52, i32 0
  store ptr %t53, ptr %t54
  %t55 = getelementptr ptr, ptr %t52, i32 1
  store ptr %t51, ptr %t55
  br label %case.end.0.49
case.end.0.49:
  br label %case.join.47
case.arm.1.56:
  %t58 = getelementptr ptr, ptr %t42, i32 1
  %t59 = load ptr, ptr %t58
  %t60 = call ptr @malloc(i64 16)
  %t61 = inttoptr i64 1 to ptr
  %t62 = getelementptr ptr, ptr %t60, i32 0
  store ptr %t61, ptr %t62
  %t63 = getelementptr [4 x i8], ptr @.str.7, i64 0, i64 0
  %t64 = call ptr @__concat(ptr %t19, ptr %t63)
  %t65 = getelementptr ptr, ptr %t60, i32 1
  store ptr %t64, ptr %t65
  %t66 = getelementptr ptr, ptr %t60, i32 0
  %t67 = load ptr, ptr %t66
  %t68 = ptrtoint ptr %t67 to i64
  switch i64 %t68, label %case.default.69 [ i64 0, label %case.arm.0.71 i64 1, label %case.arm.1.79 ]
case.arm.0.71:
  %t73 = getelementptr ptr, ptr %t60, i32 1
  %t74 = load ptr, ptr %t73
  %t75 = call ptr @malloc(i64 16)
  %t76 = inttoptr i64 0 to ptr
  %t77 = getelementptr ptr, ptr %t75, i32 0
  store ptr %t76, ptr %t77
  %t78 = getelementptr ptr, ptr %t75, i32 1
  store ptr %t74, ptr %t78
  br label %case.end.0.72
case.end.0.72:
  br label %case.join.70
case.arm.1.79:
  %t81 = getelementptr ptr, ptr %t60, i32 1
  %t82 = load ptr, ptr %t81
  %t83 = call ptr @malloc(i64 16)
  %t84 = inttoptr i64 1 to ptr
  %t85 = getelementptr ptr, ptr %t83, i32 0
  store ptr %t84, ptr %t85
  %t86 = call ptr @__concat(ptr %t82, ptr %t39)
  %t87 = getelementptr ptr, ptr %t83, i32 1
  store ptr %t86, ptr %t87
  %t88 = getelementptr ptr, ptr %t83, i32 0
  %t89 = load ptr, ptr %t88
  %t90 = ptrtoint ptr %t89 to i64
  switch i64 %t90, label %case.default.91 [ i64 0, label %case.arm.0.93 i64 1, label %case.arm.1.101 ]
case.arm.0.93:
  %t95 = getelementptr ptr, ptr %t83, i32 1
  %t96 = load ptr, ptr %t95
  %t97 = call ptr @malloc(i64 16)
  %t98 = inttoptr i64 0 to ptr
  %t99 = getelementptr ptr, ptr %t97, i32 0
  store ptr %t98, ptr %t99
  %t100 = getelementptr ptr, ptr %t97, i32 1
  store ptr %t96, ptr %t100
  br label %case.end.0.94
case.end.0.94:
  br label %case.join.92
case.arm.1.101:
  %t103 = getelementptr ptr, ptr %t83, i32 1
  %t104 = load ptr, ptr %t103
  %t105 = call ptr @malloc(i64 16)
  %t106 = inttoptr i64 1 to ptr
  %t107 = getelementptr ptr, ptr %t105, i32 0
  store ptr %t106, ptr %t107
  %t108 = getelementptr [4 x i8], ptr @.str.7, i64 0, i64 0
  %t109 = call ptr @__concat(ptr %t104, ptr %t108)
  %t110 = getelementptr ptr, ptr %t105, i32 1
  store ptr %t109, ptr %t110
  %t111 = getelementptr ptr, ptr %t105, i32 0
  %t112 = load ptr, ptr %t111
  %t113 = ptrtoint ptr %t112 to i64
  switch i64 %t113, label %case.default.114 [ i64 0, label %case.arm.0.116 i64 1, label %case.arm.1.124 ]
case.arm.0.116:
  %t118 = getelementptr ptr, ptr %t105, i32 1
  %t119 = load ptr, ptr %t118
  %t120 = call ptr @malloc(i64 16)
  %t121 = inttoptr i64 0 to ptr
  %t122 = getelementptr ptr, ptr %t120, i32 0
  store ptr %t121, ptr %t122
  %t123 = getelementptr ptr, ptr %t120, i32 1
  store ptr %t119, ptr %t123
  br label %case.end.0.117
case.end.0.117:
  br label %case.join.115
case.arm.1.124:
  %t126 = getelementptr ptr, ptr %t105, i32 1
  %t127 = load ptr, ptr %t126
  %t128 = call ptr @malloc(i64 16)
  %t129 = inttoptr i64 1 to ptr
  %t130 = getelementptr ptr, ptr %t128, i32 0
  store ptr %t129, ptr %t130
  %t131 = call ptr @__concat(ptr %t127, ptr %t59)
  %t132 = getelementptr ptr, ptr %t128, i32 1
  store ptr %t131, ptr %t132
  br label %case.end.1.125
case.end.1.125:
  br label %case.join.115
case.default.114:
  unreachable
case.join.115:
  %t133 = phi ptr [%t120, %case.end.0.117], [%t128, %case.end.1.125]
  br label %case.end.1.102
case.end.1.102:
  br label %case.join.92
case.default.91:
  unreachable
case.join.92:
  %t134 = phi ptr [%t97, %case.end.0.94], [%t133, %case.end.1.102]
  br label %case.end.1.80
case.end.1.80:
  br label %case.join.70
case.default.69:
  unreachable
case.join.70:
  %t135 = phi ptr [%t75, %case.end.0.72], [%t134, %case.end.1.80]
  br label %case.end.1.57
case.end.1.57:
  br label %case.join.47
case.default.46:
  unreachable
case.join.47:
  %t136 = phi ptr [%t52, %case.end.0.49], [%t135, %case.end.1.57]
  br label %case.end.1.37
case.end.1.37:
  br label %case.join.27
case.default.26:
  unreachable
case.join.27:
  %t137 = phi ptr [%t32, %case.end.0.29], [%t136, %case.end.1.37]
  br label %case.end.1.17
case.end.1.17:
  br label %case.join.7
case.default.6:
  unreachable
case.join.7:
  %t138 = phi ptr [%t12, %case.end.0.9], [%t137, %case.end.1.17]
  ret ptr %t138
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @v_summary()
  %t1 = call ptr @v__let_5(ptr %t0)
  ret ptr %t1
}

define internal ptr @v__lift_2(ptr %v___input) {
  %t0 = getelementptr ptr, ptr %v___input, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.10 ]
case.arm.0.5:
  %t7 = call ptr @malloc(i64 8)
  %t8 = inttoptr i64 0 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.10:
  %t12 = getelementptr ptr, ptr %v___input, i32 1
  %t13 = load ptr, ptr %t12
  %t14 = call ptr @malloc(i64 16)
  %t15 = inttoptr i64 1 to ptr
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
  br label %case.end.1.11
case.end.1.11:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t22 = phi ptr [%t7, %case.end.0.6], [%t14, %case.end.1.11]
  ret ptr %t22
}

define internal ptr @v__lift_3(ptr %v___input) {
  %t0 = call ptr @malloc(i64 8)
  %t1 = inttoptr i64 0 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__lift_3(ptr %v___input, ptr %t0)
  ret ptr %t3
}

define internal ptr @v__cps__lift_3(ptr %v___input, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 0, label %tco.case.arm.0.11 i64 1, label %tco.case.arm.1.16 ]
tco.case.arm.0.11:
  %t12 = call ptr @malloc(i64 8)
  %t13 = inttoptr i64 0 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = call ptr @v__apply__lift_3(ptr %t6, ptr %t12)
  store ptr %t15, ptr %t2
  br label %tco.exit.1
tco.case.arm.1.16:
  %t17 = getelementptr ptr, ptr %t5, i32 1
  %t18 = load ptr, ptr %t17
  %t19 = getelementptr ptr, ptr %t5, i32 2
  %t20 = load ptr, ptr %t19
  %t21 = call ptr @malloc(i64 24)
  %t22 = inttoptr i64 1 to ptr
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

define internal ptr @v__apply__lift_3(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 0, label %tco.case.arm.0.11 i64 1, label %tco.case.arm.1.12 ]
tco.case.arm.0.11:
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.1.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  %t15 = getelementptr ptr, ptr %t5, i32 2
  %t16 = load ptr, ptr %t15
  %t17 = call ptr @malloc(i64 24)
  %t18 = inttoptr i64 1 to ptr
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

define internal ptr @v__lift_4(ptr %v___input) {
  %t0 = getelementptr ptr, ptr %v___input, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.13 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v___input, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = call ptr @malloc(i64 16)
  %t10 = inttoptr i64 0 to ptr
  %t11 = getelementptr ptr, ptr %t9, i32 0
  store ptr %t10, ptr %t11
  %t12 = getelementptr ptr, ptr %t9, i32 1
  store ptr %t8, ptr %t12
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.13:
  %t15 = getelementptr ptr, ptr %v___input, i32 1
  %t16 = load ptr, ptr %t15
  %t17 = call ptr @malloc(i64 16)
  %t18 = inttoptr i64 1 to ptr
  %t19 = getelementptr ptr, ptr %t17, i32 0
  store ptr %t18, ptr %t19
  %t20 = call ptr @v__lift_2(ptr %t16)
  %t21 = getelementptr ptr, ptr %t17, i32 1
  store ptr %t20, ptr %t21
  br label %case.end.1.14
case.end.1.14:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t22 = phi ptr [%t9, %case.end.0.6], [%t17, %case.end.1.14]
  ret ptr %t22
}

define internal ptr @v__let_5(ptr %v_res) {
  %t0 = getelementptr ptr, ptr %v_res, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.22 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_res, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = call ptr @malloc(i64 24)
  %t10 = inttoptr i64 2 to ptr
  %t11 = getelementptr ptr, ptr %t9, i32 0
  store ptr %t10, ptr %t11
  %t12 = getelementptr [16 x i8], ptr @.str.8, i64 0, i64 0
  %t13 = getelementptr ptr, ptr %t9, i32 1
  store ptr %t12, ptr %t13
  %t14 = call ptr @malloc(i64 16)
  %t15 = inttoptr i64 0 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  %t17 = call ptr @malloc(i64 8)
  %t18 = inttoptr i64 0 to ptr
  %t19 = getelementptr ptr, ptr %t17, i32 0
  store ptr %t18, ptr %t19
  %t20 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t17, ptr %t20
  %t21 = getelementptr ptr, ptr %t9, i32 2
  store ptr %t14, ptr %t21
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.22:
  %t24 = getelementptr ptr, ptr %v_res, i32 1
  %t25 = load ptr, ptr %t24
  %t26 = call ptr @malloc(i64 24)
  %t27 = inttoptr i64 2 to ptr
  %t28 = getelementptr ptr, ptr %t26, i32 0
  store ptr %t27, ptr %t28
  %t29 = getelementptr ptr, ptr %t26, i32 1
  store ptr %t25, ptr %t29
  %t30 = call ptr @malloc(i64 16)
  %t31 = inttoptr i64 0 to ptr
  %t32 = getelementptr ptr, ptr %t30, i32 0
  store ptr %t31, ptr %t32
  %t33 = call ptr @malloc(i64 8)
  %t34 = inttoptr i64 0 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = getelementptr ptr, ptr %t30, i32 1
  store ptr %t33, ptr %t36
  %t37 = getelementptr ptr, ptr %t26, i32 2
  store ptr %t30, ptr %t37
  br label %case.end.1.23
case.end.1.23:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t38 = phi ptr [%t9, %case.end.0.6], [%t26, %case.end.1.23]
  ret ptr %t38
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
  %right_box = call ptr @malloc(i64 16)
  %right_tag_ptr = getelementptr ptr, ptr %right_box, i32 0
  %right_tag = inttoptr i64 1 to ptr
  store ptr %right_tag, ptr %right_tag_ptr
  %right_payload_ptr = getelementptr ptr, ptr %right_box, i32 1
  store ptr %input, ptr %right_payload_ptr
  %io = call ptr @v_main(ptr %right_box)
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
