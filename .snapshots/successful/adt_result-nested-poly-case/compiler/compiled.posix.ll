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

@.str.0 = private unnamed_addr constant [2 x i8] c"1\00"
@.str.1 = private unnamed_addr constant [2 x i8] c",\00"
@.str.2 = private unnamed_addr constant [2 x i8] c"2\00"
@.str.3 = private unnamed_addr constant [2 x i8] c"3\00"
@.str.4 = private unnamed_addr constant [2 x i8] c"4\00"
@.str.5 = private unnamed_addr constant [16 x i8] c"STRING_TOO_LONG\00"

define internal ptr @__concat(ptr %a, ptr %b) {
  %la_box = call ptr @__lengthUtf16CodeUnits(ptr %a)
  %la = load i32, ptr %la_box
  %lb_box = call ptr @__lengthUtf16CodeUnits(ptr %b)
  %lb = load i32, ptr %lb_box
  %la64 = zext i32 %la to i64
  %lb64 = zext i32 %lb to i64
  %sum64 = add i64 %la64, %lb64
  %over = icmp ugt i64 %sum64, 134217728
  br i1 %over, label %too_long, label %ok
too_long:
  %stl = call ptr @malloc(i64 8)
  %stl_tag = inttoptr i64 0 to ptr
  store ptr %stl_tag, ptr %stl
  %left = call ptr @malloc(i64 16)
  %left_tag = inttoptr i64 0 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %stl, ptr %left_f
  ret ptr %left
ok:
  %ba = call i64 @strlen(ptr %a)
  %bb = call i64 @strlen(ptr %b)
  %bsum = add i64 %ba, %bb
  %total = add i64 %bsum, 1
  %buf = call ptr @malloc(i64 %total)
  call ptr @strcpy(ptr %buf, ptr %a)
  call ptr @strcat(ptr %buf, ptr %b)
  %right = call ptr @malloc(i64 16)
  %right_tag = inttoptr i64 1 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %buf, ptr %right_f
  ret ptr %right
}


define internal ptr @__print(ptr %s) {
  call i32 (ptr, ...) @printf(ptr @.fmt, ptr %s)
  %unit = call ptr @malloc(i64 8)
  %unit_tag_ptr = getelementptr ptr, ptr %unit, i32 0
  %unit_tag = inttoptr i64 0 to ptr
  store ptr %unit_tag, ptr %unit_tag_ptr
  ret ptr %unit
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

define internal ptr @v_unwrap(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.23 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_r, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr ptr, ptr %t8, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %case.default.12 [ i64 0, label %case.arm.0.14 i64 1, label %case.arm.1.18 ]
case.arm.0.14:
  %t16 = getelementptr ptr, ptr %t8, i32 1
  %t17 = load ptr, ptr %t16
  br label %case.end.0.15
case.end.0.15:
  br label %case.join.13
case.arm.1.18:
  %t20 = getelementptr ptr, ptr %t8, i32 1
  %t21 = load ptr, ptr %t20
  br label %case.end.1.19
case.end.1.19:
  br label %case.join.13
case.default.12:
  unreachable
case.join.13:
  %t22 = phi ptr [%t17, %case.end.0.15], [%t21, %case.end.1.19]
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.23:
  %t25 = getelementptr ptr, ptr %v_r, i32 1
  %t26 = load ptr, ptr %t25
  %t27 = getelementptr ptr, ptr %t26, i32 0
  %t28 = load ptr, ptr %t27
  %t29 = ptrtoint ptr %t28 to i64
  switch i64 %t29, label %case.default.30 [ i64 0, label %case.arm.0.32 i64 1, label %case.arm.1.36 ]
case.arm.0.32:
  %t34 = getelementptr ptr, ptr %t26, i32 1
  %t35 = load ptr, ptr %t34
  br label %case.end.0.33
case.end.0.33:
  br label %case.join.31
case.arm.1.36:
  %t38 = getelementptr ptr, ptr %t26, i32 1
  %t39 = load ptr, ptr %t38
  br label %case.end.1.37
case.end.1.37:
  br label %case.join.31
case.default.30:
  unreachable
case.join.31:
  %t40 = phi ptr [%t35, %case.end.0.33], [%t39, %case.end.1.37]
  br label %case.end.1.24
case.end.1.24:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t41 = phi ptr [%t22, %case.end.0.6], [%t40, %case.end.1.24]
  ret ptr %t41
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 0 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @malloc(i64 16)
  %t4 = inttoptr i64 0 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr [2 x i8], ptr @.str.0, i64 0, i64 0
  %t7 = getelementptr ptr, ptr %t3, i32 1
  store ptr %t6, ptr %t7
  %t8 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t8
  %t9 = call ptr @v_unwrap(ptr %t0)
  %t10 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  %t11 = call ptr @__concat(ptr %t9, ptr %t10)
  %t12 = getelementptr ptr, ptr %t11, i32 0
  %t13 = load ptr, ptr %t12
  %t14 = ptrtoint ptr %t13 to i64
  switch i64 %t14, label %case.default.15 [ i64 0, label %case.arm.0.17 i64 1, label %case.arm.1.25 ]
case.arm.0.17:
  %t19 = getelementptr ptr, ptr %t11, i32 1
  %t20 = load ptr, ptr %t19
  %t21 = call ptr @malloc(i64 16)
  %t22 = inttoptr i64 0 to ptr
  %t23 = getelementptr ptr, ptr %t21, i32 0
  store ptr %t22, ptr %t23
  %t24 = getelementptr ptr, ptr %t21, i32 1
  store ptr %t20, ptr %t24
  br label %case.end.0.18
case.end.0.18:
  br label %case.join.16
case.arm.1.25:
  %t27 = getelementptr ptr, ptr %t11, i32 1
  %t28 = load ptr, ptr %t27
  %t29 = call ptr @malloc(i64 16)
  %t30 = inttoptr i64 0 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = call ptr @malloc(i64 16)
  %t33 = inttoptr i64 1 to ptr
  %t34 = getelementptr ptr, ptr %t32, i32 0
  store ptr %t33, ptr %t34
  %t35 = getelementptr [2 x i8], ptr @.str.2, i64 0, i64 0
  %t36 = getelementptr ptr, ptr %t32, i32 1
  store ptr %t35, ptr %t36
  %t37 = getelementptr ptr, ptr %t29, i32 1
  store ptr %t32, ptr %t37
  %t38 = call ptr @v_unwrap(ptr %t29)
  %t39 = call ptr @__concat(ptr %t28, ptr %t38)
  %t40 = getelementptr ptr, ptr %t39, i32 0
  %t41 = load ptr, ptr %t40
  %t42 = ptrtoint ptr %t41 to i64
  switch i64 %t42, label %case.default.43 [ i64 0, label %case.arm.0.45 i64 1, label %case.arm.1.53 ]
case.arm.0.45:
  %t47 = getelementptr ptr, ptr %t39, i32 1
  %t48 = load ptr, ptr %t47
  %t49 = call ptr @malloc(i64 16)
  %t50 = inttoptr i64 0 to ptr
  %t51 = getelementptr ptr, ptr %t49, i32 0
  store ptr %t50, ptr %t51
  %t52 = getelementptr ptr, ptr %t49, i32 1
  store ptr %t48, ptr %t52
  br label %case.end.0.46
case.end.0.46:
  br label %case.join.44
case.arm.1.53:
  %t55 = getelementptr ptr, ptr %t39, i32 1
  %t56 = load ptr, ptr %t55
  %t57 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  %t58 = call ptr @__concat(ptr %t56, ptr %t57)
  %t59 = getelementptr ptr, ptr %t58, i32 0
  %t60 = load ptr, ptr %t59
  %t61 = ptrtoint ptr %t60 to i64
  switch i64 %t61, label %case.default.62 [ i64 0, label %case.arm.0.64 i64 1, label %case.arm.1.72 ]
case.arm.0.64:
  %t66 = getelementptr ptr, ptr %t58, i32 1
  %t67 = load ptr, ptr %t66
  %t68 = call ptr @malloc(i64 16)
  %t69 = inttoptr i64 0 to ptr
  %t70 = getelementptr ptr, ptr %t68, i32 0
  store ptr %t69, ptr %t70
  %t71 = getelementptr ptr, ptr %t68, i32 1
  store ptr %t67, ptr %t71
  br label %case.end.0.65
case.end.0.65:
  br label %case.join.63
case.arm.1.72:
  %t74 = getelementptr ptr, ptr %t58, i32 1
  %t75 = load ptr, ptr %t74
  %t76 = call ptr @malloc(i64 16)
  %t77 = inttoptr i64 1 to ptr
  %t78 = getelementptr ptr, ptr %t76, i32 0
  store ptr %t77, ptr %t78
  %t79 = call ptr @malloc(i64 16)
  %t80 = inttoptr i64 0 to ptr
  %t81 = getelementptr ptr, ptr %t79, i32 0
  store ptr %t80, ptr %t81
  %t82 = getelementptr [2 x i8], ptr @.str.3, i64 0, i64 0
  %t83 = getelementptr ptr, ptr %t79, i32 1
  store ptr %t82, ptr %t83
  %t84 = getelementptr ptr, ptr %t76, i32 1
  store ptr %t79, ptr %t84
  %t85 = call ptr @v_unwrap(ptr %t76)
  %t86 = call ptr @__concat(ptr %t75, ptr %t85)
  %t87 = getelementptr ptr, ptr %t86, i32 0
  %t88 = load ptr, ptr %t87
  %t89 = ptrtoint ptr %t88 to i64
  switch i64 %t89, label %case.default.90 [ i64 0, label %case.arm.0.92 i64 1, label %case.arm.1.100 ]
case.arm.0.92:
  %t94 = getelementptr ptr, ptr %t86, i32 1
  %t95 = load ptr, ptr %t94
  %t96 = call ptr @malloc(i64 16)
  %t97 = inttoptr i64 0 to ptr
  %t98 = getelementptr ptr, ptr %t96, i32 0
  store ptr %t97, ptr %t98
  %t99 = getelementptr ptr, ptr %t96, i32 1
  store ptr %t95, ptr %t99
  br label %case.end.0.93
case.end.0.93:
  br label %case.join.91
case.arm.1.100:
  %t102 = getelementptr ptr, ptr %t86, i32 1
  %t103 = load ptr, ptr %t102
  %t104 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  %t105 = call ptr @__concat(ptr %t103, ptr %t104)
  %t106 = getelementptr ptr, ptr %t105, i32 0
  %t107 = load ptr, ptr %t106
  %t108 = ptrtoint ptr %t107 to i64
  switch i64 %t108, label %case.default.109 [ i64 0, label %case.arm.0.111 i64 1, label %case.arm.1.119 ]
case.arm.0.111:
  %t113 = getelementptr ptr, ptr %t105, i32 1
  %t114 = load ptr, ptr %t113
  %t115 = call ptr @malloc(i64 16)
  %t116 = inttoptr i64 0 to ptr
  %t117 = getelementptr ptr, ptr %t115, i32 0
  store ptr %t116, ptr %t117
  %t118 = getelementptr ptr, ptr %t115, i32 1
  store ptr %t114, ptr %t118
  br label %case.end.0.112
case.end.0.112:
  br label %case.join.110
case.arm.1.119:
  %t121 = getelementptr ptr, ptr %t105, i32 1
  %t122 = load ptr, ptr %t121
  %t123 = call ptr @malloc(i64 16)
  %t124 = inttoptr i64 1 to ptr
  %t125 = getelementptr ptr, ptr %t123, i32 0
  store ptr %t124, ptr %t125
  %t126 = call ptr @malloc(i64 16)
  %t127 = inttoptr i64 1 to ptr
  %t128 = getelementptr ptr, ptr %t126, i32 0
  store ptr %t127, ptr %t128
  %t129 = getelementptr [2 x i8], ptr @.str.4, i64 0, i64 0
  %t130 = getelementptr ptr, ptr %t126, i32 1
  store ptr %t129, ptr %t130
  %t131 = getelementptr ptr, ptr %t123, i32 1
  store ptr %t126, ptr %t131
  %t132 = call ptr @v_unwrap(ptr %t123)
  %t133 = call ptr @__concat(ptr %t122, ptr %t132)
  br label %case.end.1.120
case.end.1.120:
  br label %case.join.110
case.default.109:
  unreachable
case.join.110:
  %t134 = phi ptr [%t115, %case.end.0.112], [%t133, %case.end.1.120]
  br label %case.end.1.101
case.end.1.101:
  br label %case.join.91
case.default.90:
  unreachable
case.join.91:
  %t135 = phi ptr [%t96, %case.end.0.93], [%t134, %case.end.1.101]
  br label %case.end.1.73
case.end.1.73:
  br label %case.join.63
case.default.62:
  unreachable
case.join.63:
  %t136 = phi ptr [%t68, %case.end.0.65], [%t135, %case.end.1.73]
  br label %case.end.1.54
case.end.1.54:
  br label %case.join.44
case.default.43:
  unreachable
case.join.44:
  %t137 = phi ptr [%t49, %case.end.0.46], [%t136, %case.end.1.54]
  br label %case.end.1.26
case.end.1.26:
  br label %case.join.16
case.default.15:
  unreachable
case.join.16:
  %t138 = phi ptr [%t21, %case.end.0.18], [%t137, %case.end.1.26]
  %t139 = call ptr @v__let_2(ptr %t138)
  ret ptr %t139
}

define internal ptr @v__let_2(ptr %v_res) {
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
  %t12 = getelementptr [16 x i8], ptr @.str.5, i64 0, i64 0
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
