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

@.str.0 = private unnamed_addr constant [4 x i8] c"=ok\00"
@.str.1 = private unnamed_addr constant [16 x i8] c"=FAIL(expected=\00"
@.str.2 = private unnamed_addr constant [7 x i8] c", got=\00"
@.str.3 = private unnamed_addr constant [2 x i8] c")\00"
@.str.4 = private unnamed_addr constant [5 x i8] c"\F0\9F\94\A5\00"
@.str.5 = private unnamed_addr constant [17 x i8] c"lengthCodePoints\00"
@.str.6 = private unnamed_addr constant [21 x i8] c"lengthUtf16CodeUnits\00"
@.str.7 = private unnamed_addr constant [18 x i8] c"lengthBytesAsUtf8\00"
@.str.8 = private unnamed_addr constant [3 x i8] c", \00"
@.str.9 = private unnamed_addr constant [16 x i8] c"STRING_TOO_LONG\00"

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


define internal ptr @__showUInt32(ptr %p) {
  %v = load i32, ptr %p
  %buf = call ptr @malloc(i64 16)
  call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 16, ptr @.fmt_u8, i32 %v)
  ret ptr %buf
}


define internal ptr @__eqUInt32(ptr %a, ptr %b) {
  %va = load i32, ptr %a
  %vb = load i32, ptr %b
  %eq = icmp eq i32 %va, %vb
  %tag = select i1 %eq, i64 0, i64 1
  %box = call ptr @malloc(i64 8)
  %tag_ptr = inttoptr i64 %tag to ptr
  store ptr %tag_ptr, ptr %box
  ret ptr %box
}


define internal ptr @__lengthCodePoints(ptr %s) {
entry:
  %i_p = alloca i64, align 8
  store i64 0, ptr %i_p
  %n_p = alloca i32, align 4
  store i32 0, ptr %n_p
  br label %head
head:
  %i = load i64, ptr %i_p
  %bp = getelementptr i8, ptr %s, i64 %i
  %b = load i8, ptr %bp
  %is_nul = icmp eq i8 %b, 0
  br i1 %is_nul, label %done, label %body
body:
  %bz = zext i8 %b to i32
  %top2 = and i32 %bz, 192
  %is_cont = icmp eq i32 %top2, 128
  br i1 %is_cont, label %step, label %inc
inc:
  %n0 = load i32, ptr %n_p
  %n1 = add i32 %n0, 1
  store i32 %n1, ptr %n_p
  br label %step
step:
  %i1 = add i64 %i, 1
  store i64 %i1, ptr %i_p
  br label %head
done:
  %nf = load i32, ptr %n_p
  %box = call ptr @malloc(i64 4)
  store i32 %nf, ptr %box
  ret ptr %box
}


define internal ptr @__lengthUtf16CodeUnits(ptr %s) {
entry:
  %i_p = alloca i64, align 8
  store i64 0, ptr %i_p
  %n_p = alloca i32, align 4
  store i32 0, ptr %n_p
  br label %head
head:
  %i = load i64, ptr %i_p
  %bp = getelementptr i8, ptr %s, i64 %i
  %b = load i8, ptr %bp
  %is_nul = icmp eq i8 %b, 0
  br i1 %is_nul, label %done, label %body
body:
  %bz = zext i8 %b to i32
  %top2 = and i32 %bz, 192
  %is_cont = icmp eq i32 %top2, 128
  br i1 %is_cont, label %step, label %check4
check4:
  %top5 = and i32 %bz, 248
  %is_4 = icmp eq i32 %top5, 240
  br i1 %is_4, label %add2, label %add1
add2:
  %n2_0 = load i32, ptr %n_p
  %n2_1 = add i32 %n2_0, 2
  store i32 %n2_1, ptr %n_p
  br label %step
add1:
  %n1_0 = load i32, ptr %n_p
  %n1_1 = add i32 %n1_0, 1
  store i32 %n1_1, ptr %n_p
  br label %step
step:
  %i1 = add i64 %i, 1
  store i64 %i1, ptr %i_p
  br label %head
done:
  %nf = load i32, ptr %n_p
  %box = call ptr @malloc(i64 4)
  store i32 %nf, ptr %box
  ret ptr %box
}


define internal ptr @__lengthBytesAsUtf8(ptr %s) {
  %len64 = call i64 @strlen(ptr %s)
  %len32 = trunc i64 %len64 to i32
  %box = call ptr @malloc(i64 4)
  store i32 %len32, ptr %box
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

define internal ptr @v_check(ptr %v_expected, ptr %v_actual, ptr %v_label) {
  %t0 = call ptr @__eqUInt32(ptr %v_expected, ptr %v_actual)
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 0, label %case.arm.0.6 i64 1, label %case.arm.1.14 ]
case.arm.0.6:
  %t8 = call ptr @malloc(i64 16)
  %t9 = inttoptr i64 1 to ptr
  %t10 = getelementptr ptr, ptr %t8, i32 0
  store ptr %t9, ptr %t10
  %t11 = getelementptr [4 x i8], ptr @.str.0, i64 0, i64 0
  %t12 = call ptr @__concat(ptr %v_label, ptr %t11)
  %t13 = getelementptr ptr, ptr %t8, i32 1
  store ptr %t12, ptr %t13
  br label %case.end.0.7
case.end.0.7:
  br label %case.join.5
case.arm.1.14:
  %t16 = call ptr @malloc(i64 16)
  %t17 = inttoptr i64 1 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = getelementptr [16 x i8], ptr @.str.1, i64 0, i64 0
  %t20 = call ptr @__concat(ptr %v_label, ptr %t19)
  %t21 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t20, ptr %t21
  %t22 = getelementptr ptr, ptr %t16, i32 0
  %t23 = load ptr, ptr %t22
  %t24 = ptrtoint ptr %t23 to i64
  switch i64 %t24, label %case.default.25 [ i64 0, label %case.arm.0.27 i64 1, label %case.arm.1.35 ]
case.arm.0.27:
  %t29 = getelementptr ptr, ptr %t16, i32 1
  %t30 = load ptr, ptr %t29
  %t31 = call ptr @malloc(i64 16)
  %t32 = inttoptr i64 0 to ptr
  %t33 = getelementptr ptr, ptr %t31, i32 0
  store ptr %t32, ptr %t33
  %t34 = getelementptr ptr, ptr %t31, i32 1
  store ptr %t30, ptr %t34
  br label %case.end.0.28
case.end.0.28:
  br label %case.join.26
case.arm.1.35:
  %t37 = getelementptr ptr, ptr %t16, i32 1
  %t38 = load ptr, ptr %t37
  %t39 = call ptr @malloc(i64 16)
  %t40 = inttoptr i64 1 to ptr
  %t41 = getelementptr ptr, ptr %t39, i32 0
  store ptr %t40, ptr %t41
  %t42 = call ptr @__showUInt32(ptr %v_expected)
  %t43 = call ptr @__concat(ptr %t38, ptr %t42)
  %t44 = getelementptr ptr, ptr %t39, i32 1
  store ptr %t43, ptr %t44
  %t45 = getelementptr ptr, ptr %t39, i32 0
  %t46 = load ptr, ptr %t45
  %t47 = ptrtoint ptr %t46 to i64
  switch i64 %t47, label %case.default.48 [ i64 0, label %case.arm.0.50 i64 1, label %case.arm.1.58 ]
case.arm.0.50:
  %t52 = getelementptr ptr, ptr %t39, i32 1
  %t53 = load ptr, ptr %t52
  %t54 = call ptr @malloc(i64 16)
  %t55 = inttoptr i64 0 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t53, ptr %t57
  br label %case.end.0.51
case.end.0.51:
  br label %case.join.49
case.arm.1.58:
  %t60 = getelementptr ptr, ptr %t39, i32 1
  %t61 = load ptr, ptr %t60
  %t62 = call ptr @malloc(i64 16)
  %t63 = inttoptr i64 1 to ptr
  %t64 = getelementptr ptr, ptr %t62, i32 0
  store ptr %t63, ptr %t64
  %t65 = getelementptr [7 x i8], ptr @.str.2, i64 0, i64 0
  %t66 = call ptr @__concat(ptr %t61, ptr %t65)
  %t67 = getelementptr ptr, ptr %t62, i32 1
  store ptr %t66, ptr %t67
  %t68 = getelementptr ptr, ptr %t62, i32 0
  %t69 = load ptr, ptr %t68
  %t70 = ptrtoint ptr %t69 to i64
  switch i64 %t70, label %case.default.71 [ i64 0, label %case.arm.0.73 i64 1, label %case.arm.1.81 ]
case.arm.0.73:
  %t75 = getelementptr ptr, ptr %t62, i32 1
  %t76 = load ptr, ptr %t75
  %t77 = call ptr @malloc(i64 16)
  %t78 = inttoptr i64 0 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t76, ptr %t80
  br label %case.end.0.74
case.end.0.74:
  br label %case.join.72
case.arm.1.81:
  %t83 = getelementptr ptr, ptr %t62, i32 1
  %t84 = load ptr, ptr %t83
  %t85 = call ptr @malloc(i64 16)
  %t86 = inttoptr i64 1 to ptr
  %t87 = getelementptr ptr, ptr %t85, i32 0
  store ptr %t86, ptr %t87
  %t88 = call ptr @__showUInt32(ptr %v_actual)
  %t89 = call ptr @__concat(ptr %t84, ptr %t88)
  %t90 = getelementptr ptr, ptr %t85, i32 1
  store ptr %t89, ptr %t90
  %t91 = getelementptr ptr, ptr %t85, i32 0
  %t92 = load ptr, ptr %t91
  %t93 = ptrtoint ptr %t92 to i64
  switch i64 %t93, label %case.default.94 [ i64 0, label %case.arm.0.96 i64 1, label %case.arm.1.104 ]
case.arm.0.96:
  %t98 = getelementptr ptr, ptr %t85, i32 1
  %t99 = load ptr, ptr %t98
  %t100 = call ptr @malloc(i64 16)
  %t101 = inttoptr i64 0 to ptr
  %t102 = getelementptr ptr, ptr %t100, i32 0
  store ptr %t101, ptr %t102
  %t103 = getelementptr ptr, ptr %t100, i32 1
  store ptr %t99, ptr %t103
  br label %case.end.0.97
case.end.0.97:
  br label %case.join.95
case.arm.1.104:
  %t106 = getelementptr ptr, ptr %t85, i32 1
  %t107 = load ptr, ptr %t106
  %t108 = call ptr @malloc(i64 16)
  %t109 = inttoptr i64 1 to ptr
  %t110 = getelementptr ptr, ptr %t108, i32 0
  store ptr %t109, ptr %t110
  %t111 = getelementptr [2 x i8], ptr @.str.3, i64 0, i64 0
  %t112 = call ptr @__concat(ptr %t107, ptr %t111)
  %t113 = getelementptr ptr, ptr %t108, i32 1
  store ptr %t112, ptr %t113
  br label %case.end.1.105
case.end.1.105:
  br label %case.join.95
case.default.94:
  unreachable
case.join.95:
  %t114 = phi ptr [%t100, %case.end.0.97], [%t108, %case.end.1.105]
  br label %case.end.1.82
case.end.1.82:
  br label %case.join.72
case.default.71:
  unreachable
case.join.72:
  %t115 = phi ptr [%t77, %case.end.0.74], [%t114, %case.end.1.82]
  br label %case.end.1.59
case.end.1.59:
  br label %case.join.49
case.default.48:
  unreachable
case.join.49:
  %t116 = phi ptr [%t54, %case.end.0.51], [%t115, %case.end.1.59]
  br label %case.end.1.36
case.end.1.36:
  br label %case.join.26
case.default.25:
  unreachable
case.join.26:
  %t117 = phi ptr [%t31, %case.end.0.28], [%t116, %case.end.1.36]
  br label %case.end.1.15
case.end.1.15:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t118 = phi ptr [%t8, %case.end.0.7], [%t117, %case.end.1.15]
  ret ptr %t118
}

define internal ptr @v_run() {
  %t0 = call ptr @malloc(i64 4)
  store i32 1, ptr %t0
  %t1 = getelementptr [2 x i8], ptr @.str.4, i64 0, i64 0
  %t2 = call ptr @__lengthCodePoints(ptr %t1)
  %t3 = getelementptr [17 x i8], ptr @.str.5, i64 0, i64 0
  %t4 = call ptr @v_check(ptr %t0, ptr %t2, ptr %t3)
  %t5 = getelementptr ptr, ptr %t4, i32 0
  %t6 = load ptr, ptr %t5
  %t7 = ptrtoint ptr %t6 to i64
  switch i64 %t7, label %case.default.8 [ i64 0, label %case.arm.0.10 i64 1, label %case.arm.1.18 ]
case.arm.0.10:
  %t12 = getelementptr ptr, ptr %t4, i32 1
  %t13 = load ptr, ptr %t12
  %t14 = call ptr @malloc(i64 16)
  %t15 = inttoptr i64 0 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  %t17 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t13, ptr %t17
  br label %case.end.0.11
case.end.0.11:
  br label %case.join.9
case.arm.1.18:
  %t20 = getelementptr ptr, ptr %t4, i32 1
  %t21 = load ptr, ptr %t20
  %t22 = call ptr @malloc(i64 4)
  store i32 2, ptr %t22
  %t23 = getelementptr [2 x i8], ptr @.str.4, i64 0, i64 0
  %t24 = call ptr @__lengthUtf16CodeUnits(ptr %t23)
  %t25 = getelementptr [21 x i8], ptr @.str.6, i64 0, i64 0
  %t26 = call ptr @v_check(ptr %t22, ptr %t24, ptr %t25)
  %t27 = getelementptr ptr, ptr %t26, i32 0
  %t28 = load ptr, ptr %t27
  %t29 = ptrtoint ptr %t28 to i64
  switch i64 %t29, label %case.default.30 [ i64 0, label %case.arm.0.32 i64 1, label %case.arm.1.40 ]
case.arm.0.32:
  %t34 = getelementptr ptr, ptr %t26, i32 1
  %t35 = load ptr, ptr %t34
  %t36 = call ptr @malloc(i64 16)
  %t37 = inttoptr i64 0 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t35, ptr %t39
  br label %case.end.0.33
case.end.0.33:
  br label %case.join.31
case.arm.1.40:
  %t42 = getelementptr ptr, ptr %t26, i32 1
  %t43 = load ptr, ptr %t42
  %t44 = call ptr @malloc(i64 4)
  store i32 4, ptr %t44
  %t45 = getelementptr [2 x i8], ptr @.str.4, i64 0, i64 0
  %t46 = call ptr @__lengthBytesAsUtf8(ptr %t45)
  %t47 = getelementptr [18 x i8], ptr @.str.7, i64 0, i64 0
  %t48 = call ptr @v_check(ptr %t44, ptr %t46, ptr %t47)
  %t49 = getelementptr ptr, ptr %t48, i32 0
  %t50 = load ptr, ptr %t49
  %t51 = ptrtoint ptr %t50 to i64
  switch i64 %t51, label %case.default.52 [ i64 0, label %case.arm.0.54 i64 1, label %case.arm.1.62 ]
case.arm.0.54:
  %t56 = getelementptr ptr, ptr %t48, i32 1
  %t57 = load ptr, ptr %t56
  %t58 = call ptr @malloc(i64 16)
  %t59 = inttoptr i64 0 to ptr
  %t60 = getelementptr ptr, ptr %t58, i32 0
  store ptr %t59, ptr %t60
  %t61 = getelementptr ptr, ptr %t58, i32 1
  store ptr %t57, ptr %t61
  br label %case.end.0.55
case.end.0.55:
  br label %case.join.53
case.arm.1.62:
  %t64 = getelementptr ptr, ptr %t48, i32 1
  %t65 = load ptr, ptr %t64
  %t66 = call ptr @malloc(i64 16)
  %t67 = inttoptr i64 1 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  %t69 = getelementptr [3 x i8], ptr @.str.8, i64 0, i64 0
  %t70 = call ptr @__concat(ptr %t21, ptr %t69)
  %t71 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t70, ptr %t71
  %t72 = getelementptr ptr, ptr %t66, i32 0
  %t73 = load ptr, ptr %t72
  %t74 = ptrtoint ptr %t73 to i64
  switch i64 %t74, label %case.default.75 [ i64 0, label %case.arm.0.77 i64 1, label %case.arm.1.85 ]
case.arm.0.77:
  %t79 = getelementptr ptr, ptr %t66, i32 1
  %t80 = load ptr, ptr %t79
  %t81 = call ptr @malloc(i64 16)
  %t82 = inttoptr i64 0 to ptr
  %t83 = getelementptr ptr, ptr %t81, i32 0
  store ptr %t82, ptr %t83
  %t84 = getelementptr ptr, ptr %t81, i32 1
  store ptr %t80, ptr %t84
  br label %case.end.0.78
case.end.0.78:
  br label %case.join.76
case.arm.1.85:
  %t87 = getelementptr ptr, ptr %t66, i32 1
  %t88 = load ptr, ptr %t87
  %t89 = call ptr @malloc(i64 16)
  %t90 = inttoptr i64 1 to ptr
  %t91 = getelementptr ptr, ptr %t89, i32 0
  store ptr %t90, ptr %t91
  %t92 = call ptr @__concat(ptr %t88, ptr %t43)
  %t93 = getelementptr ptr, ptr %t89, i32 1
  store ptr %t92, ptr %t93
  %t94 = getelementptr ptr, ptr %t89, i32 0
  %t95 = load ptr, ptr %t94
  %t96 = ptrtoint ptr %t95 to i64
  switch i64 %t96, label %case.default.97 [ i64 0, label %case.arm.0.99 i64 1, label %case.arm.1.107 ]
case.arm.0.99:
  %t101 = getelementptr ptr, ptr %t89, i32 1
  %t102 = load ptr, ptr %t101
  %t103 = call ptr @malloc(i64 16)
  %t104 = inttoptr i64 0 to ptr
  %t105 = getelementptr ptr, ptr %t103, i32 0
  store ptr %t104, ptr %t105
  %t106 = getelementptr ptr, ptr %t103, i32 1
  store ptr %t102, ptr %t106
  br label %case.end.0.100
case.end.0.100:
  br label %case.join.98
case.arm.1.107:
  %t109 = getelementptr ptr, ptr %t89, i32 1
  %t110 = load ptr, ptr %t109
  %t111 = call ptr @malloc(i64 16)
  %t112 = inttoptr i64 1 to ptr
  %t113 = getelementptr ptr, ptr %t111, i32 0
  store ptr %t112, ptr %t113
  %t114 = getelementptr [3 x i8], ptr @.str.8, i64 0, i64 0
  %t115 = call ptr @__concat(ptr %t110, ptr %t114)
  %t116 = getelementptr ptr, ptr %t111, i32 1
  store ptr %t115, ptr %t116
  %t117 = getelementptr ptr, ptr %t111, i32 0
  %t118 = load ptr, ptr %t117
  %t119 = ptrtoint ptr %t118 to i64
  switch i64 %t119, label %case.default.120 [ i64 0, label %case.arm.0.122 i64 1, label %case.arm.1.130 ]
case.arm.0.122:
  %t124 = getelementptr ptr, ptr %t111, i32 1
  %t125 = load ptr, ptr %t124
  %t126 = call ptr @malloc(i64 16)
  %t127 = inttoptr i64 0 to ptr
  %t128 = getelementptr ptr, ptr %t126, i32 0
  store ptr %t127, ptr %t128
  %t129 = getelementptr ptr, ptr %t126, i32 1
  store ptr %t125, ptr %t129
  br label %case.end.0.123
case.end.0.123:
  br label %case.join.121
case.arm.1.130:
  %t132 = getelementptr ptr, ptr %t111, i32 1
  %t133 = load ptr, ptr %t132
  %t134 = call ptr @malloc(i64 16)
  %t135 = inttoptr i64 1 to ptr
  %t136 = getelementptr ptr, ptr %t134, i32 0
  store ptr %t135, ptr %t136
  %t137 = call ptr @__concat(ptr %t133, ptr %t65)
  %t138 = getelementptr ptr, ptr %t134, i32 1
  store ptr %t137, ptr %t138
  br label %case.end.1.131
case.end.1.131:
  br label %case.join.121
case.default.120:
  unreachable
case.join.121:
  %t139 = phi ptr [%t126, %case.end.0.123], [%t134, %case.end.1.131]
  br label %case.end.1.108
case.end.1.108:
  br label %case.join.98
case.default.97:
  unreachable
case.join.98:
  %t140 = phi ptr [%t103, %case.end.0.100], [%t139, %case.end.1.108]
  br label %case.end.1.86
case.end.1.86:
  br label %case.join.76
case.default.75:
  unreachable
case.join.76:
  %t141 = phi ptr [%t81, %case.end.0.78], [%t140, %case.end.1.86]
  br label %case.end.1.63
case.end.1.63:
  br label %case.join.53
case.default.52:
  unreachable
case.join.53:
  %t142 = phi ptr [%t58, %case.end.0.55], [%t141, %case.end.1.63]
  br label %case.end.1.41
case.end.1.41:
  br label %case.join.31
case.default.30:
  unreachable
case.join.31:
  %t143 = phi ptr [%t36, %case.end.0.33], [%t142, %case.end.1.41]
  br label %case.end.1.19
case.end.1.19:
  br label %case.join.9
case.default.8:
  unreachable
case.join.9:
  %t144 = phi ptr [%t14, %case.end.0.11], [%t143, %case.end.1.19]
  ret ptr %t144
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @v_run()
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 0, label %case.arm.0.6 i64 1, label %case.arm.1.23 ]
case.arm.0.6:
  %t8 = getelementptr ptr, ptr %t0, i32 1
  %t9 = load ptr, ptr %t8
  %t10 = call ptr @malloc(i64 24)
  %t11 = inttoptr i64 2 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  %t13 = getelementptr [16 x i8], ptr @.str.9, i64 0, i64 0
  %t14 = getelementptr ptr, ptr %t10, i32 1
  store ptr %t13, ptr %t14
  %t15 = call ptr @malloc(i64 16)
  %t16 = inttoptr i64 0 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = call ptr @malloc(i64 8)
  %t19 = inttoptr i64 0 to ptr
  %t20 = getelementptr ptr, ptr %t18, i32 0
  store ptr %t19, ptr %t20
  %t21 = getelementptr ptr, ptr %t15, i32 1
  store ptr %t18, ptr %t21
  %t22 = getelementptr ptr, ptr %t10, i32 2
  store ptr %t15, ptr %t22
  br label %case.end.0.7
case.end.0.7:
  br label %case.join.5
case.arm.1.23:
  %t25 = getelementptr ptr, ptr %t0, i32 1
  %t26 = load ptr, ptr %t25
  %t27 = call ptr @malloc(i64 24)
  %t28 = inttoptr i64 2 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  %t30 = getelementptr ptr, ptr %t27, i32 1
  store ptr %t26, ptr %t30
  %t31 = call ptr @malloc(i64 16)
  %t32 = inttoptr i64 0 to ptr
  %t33 = getelementptr ptr, ptr %t31, i32 0
  store ptr %t32, ptr %t33
  %t34 = call ptr @malloc(i64 8)
  %t35 = inttoptr i64 0 to ptr
  %t36 = getelementptr ptr, ptr %t34, i32 0
  store ptr %t35, ptr %t36
  %t37 = getelementptr ptr, ptr %t31, i32 1
  store ptr %t34, ptr %t37
  %t38 = getelementptr ptr, ptr %t27, i32 2
  store ptr %t31, ptr %t38
  br label %case.end.1.24
case.end.1.24:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t39 = phi ptr [%t10, %case.end.0.7], [%t27, %case.end.1.24]
  ret ptr %t39
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
  %input = phi ptr [%arg, %with_arg], [@.empty, %no_arg]
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
