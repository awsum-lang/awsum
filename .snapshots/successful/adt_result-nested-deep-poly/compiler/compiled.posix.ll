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
@.str.5 = private unnamed_addr constant [2 x i8] c"5\00"
@.str.6 = private unnamed_addr constant [2 x i8] c"6\00"
@.str.7 = private unnamed_addr constant [2 x i8] c"7\00"
@.str.8 = private unnamed_addr constant [2 x i8] c"8\00"
@.str.9 = private unnamed_addr constant [16 x i8] c"STRING_TOO_LONG\00"

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
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.51 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_r, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr ptr, ptr %t8, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %case.default.12 [ i64 0, label %case.arm.0.14 i64 1, label %case.arm.1.32 ]
case.arm.0.14:
  %t16 = getelementptr ptr, ptr %t8, i32 1
  %t17 = load ptr, ptr %t16
  %t18 = getelementptr ptr, ptr %t17, i32 0
  %t19 = load ptr, ptr %t18
  %t20 = ptrtoint ptr %t19 to i64
  switch i64 %t20, label %case.default.21 [ i64 0, label %case.arm.0.23 i64 1, label %case.arm.1.27 ]
case.arm.0.23:
  %t25 = getelementptr ptr, ptr %t17, i32 1
  %t26 = load ptr, ptr %t25
  br label %case.end.0.24
case.end.0.24:
  br label %case.join.22
case.arm.1.27:
  %t29 = getelementptr ptr, ptr %t17, i32 1
  %t30 = load ptr, ptr %t29
  br label %case.end.1.28
case.end.1.28:
  br label %case.join.22
case.default.21:
  unreachable
case.join.22:
  %t31 = phi ptr [%t26, %case.end.0.24], [%t30, %case.end.1.28]
  br label %case.end.0.15
case.end.0.15:
  br label %case.join.13
case.arm.1.32:
  %t34 = getelementptr ptr, ptr %t8, i32 1
  %t35 = load ptr, ptr %t34
  %t36 = getelementptr ptr, ptr %t35, i32 0
  %t37 = load ptr, ptr %t36
  %t38 = ptrtoint ptr %t37 to i64
  switch i64 %t38, label %case.default.39 [ i64 0, label %case.arm.0.41 i64 1, label %case.arm.1.45 ]
case.arm.0.41:
  %t43 = getelementptr ptr, ptr %t35, i32 1
  %t44 = load ptr, ptr %t43
  br label %case.end.0.42
case.end.0.42:
  br label %case.join.40
case.arm.1.45:
  %t47 = getelementptr ptr, ptr %t35, i32 1
  %t48 = load ptr, ptr %t47
  br label %case.end.1.46
case.end.1.46:
  br label %case.join.40
case.default.39:
  unreachable
case.join.40:
  %t49 = phi ptr [%t44, %case.end.0.42], [%t48, %case.end.1.46]
  br label %case.end.1.33
case.end.1.33:
  br label %case.join.13
case.default.12:
  unreachable
case.join.13:
  %t50 = phi ptr [%t31, %case.end.0.15], [%t49, %case.end.1.33]
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.51:
  %t53 = getelementptr ptr, ptr %v_r, i32 1
  %t54 = load ptr, ptr %t53
  %t55 = getelementptr ptr, ptr %t54, i32 0
  %t56 = load ptr, ptr %t55
  %t57 = ptrtoint ptr %t56 to i64
  switch i64 %t57, label %case.default.58 [ i64 0, label %case.arm.0.60 i64 1, label %case.arm.1.78 ]
case.arm.0.60:
  %t62 = getelementptr ptr, ptr %t54, i32 1
  %t63 = load ptr, ptr %t62
  %t64 = getelementptr ptr, ptr %t63, i32 0
  %t65 = load ptr, ptr %t64
  %t66 = ptrtoint ptr %t65 to i64
  switch i64 %t66, label %case.default.67 [ i64 0, label %case.arm.0.69 i64 1, label %case.arm.1.73 ]
case.arm.0.69:
  %t71 = getelementptr ptr, ptr %t63, i32 1
  %t72 = load ptr, ptr %t71
  br label %case.end.0.70
case.end.0.70:
  br label %case.join.68
case.arm.1.73:
  %t75 = getelementptr ptr, ptr %t63, i32 1
  %t76 = load ptr, ptr %t75
  br label %case.end.1.74
case.end.1.74:
  br label %case.join.68
case.default.67:
  unreachable
case.join.68:
  %t77 = phi ptr [%t72, %case.end.0.70], [%t76, %case.end.1.74]
  br label %case.end.0.61
case.end.0.61:
  br label %case.join.59
case.arm.1.78:
  %t80 = getelementptr ptr, ptr %t54, i32 1
  %t81 = load ptr, ptr %t80
  %t82 = getelementptr ptr, ptr %t81, i32 0
  %t83 = load ptr, ptr %t82
  %t84 = ptrtoint ptr %t83 to i64
  switch i64 %t84, label %case.default.85 [ i64 0, label %case.arm.0.87 i64 1, label %case.arm.1.91 ]
case.arm.0.87:
  %t89 = getelementptr ptr, ptr %t81, i32 1
  %t90 = load ptr, ptr %t89
  br label %case.end.0.88
case.end.0.88:
  br label %case.join.86
case.arm.1.91:
  %t93 = getelementptr ptr, ptr %t81, i32 1
  %t94 = load ptr, ptr %t93
  br label %case.end.1.92
case.end.1.92:
  br label %case.join.86
case.default.85:
  unreachable
case.join.86:
  %t95 = phi ptr [%t90, %case.end.0.88], [%t94, %case.end.1.92]
  br label %case.end.1.79
case.end.1.79:
  br label %case.join.59
case.default.58:
  unreachable
case.join.59:
  %t96 = phi ptr [%t77, %case.end.0.61], [%t95, %case.end.1.79]
  br label %case.end.1.52
case.end.1.52:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t97 = phi ptr [%t50, %case.end.0.6], [%t96, %case.end.1.52]
  ret ptr %t97
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
  %t6 = call ptr @malloc(i64 16)
  %t7 = inttoptr i64 0 to ptr
  %t8 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t7, ptr %t8
  %t9 = getelementptr [2 x i8], ptr @.str.0, i64 0, i64 0
  %t10 = getelementptr ptr, ptr %t6, i32 1
  store ptr %t9, ptr %t10
  %t11 = getelementptr ptr, ptr %t3, i32 1
  store ptr %t6, ptr %t11
  %t12 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t12
  %t13 = call ptr @v_unwrap(ptr %t0)
  %t14 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  %t15 = call ptr @__concat(ptr %t13, ptr %t14)
  %t16 = getelementptr ptr, ptr %t15, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %case.default.19 [ i64 0, label %case.arm.0.21 i64 1, label %case.arm.1.29 ]
case.arm.0.21:
  %t23 = getelementptr ptr, ptr %t15, i32 1
  %t24 = load ptr, ptr %t23
  %t25 = call ptr @malloc(i64 16)
  %t26 = inttoptr i64 0 to ptr
  %t27 = getelementptr ptr, ptr %t25, i32 0
  store ptr %t26, ptr %t27
  %t28 = getelementptr ptr, ptr %t25, i32 1
  store ptr %t24, ptr %t28
  br label %case.end.0.22
case.end.0.22:
  br label %case.join.20
case.arm.1.29:
  %t31 = getelementptr ptr, ptr %t15, i32 1
  %t32 = load ptr, ptr %t31
  %t33 = call ptr @malloc(i64 16)
  %t34 = inttoptr i64 0 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = call ptr @malloc(i64 16)
  %t37 = inttoptr i64 0 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = call ptr @malloc(i64 16)
  %t40 = inttoptr i64 1 to ptr
  %t41 = getelementptr ptr, ptr %t39, i32 0
  store ptr %t40, ptr %t41
  %t42 = getelementptr [2 x i8], ptr @.str.2, i64 0, i64 0
  %t43 = getelementptr ptr, ptr %t39, i32 1
  store ptr %t42, ptr %t43
  %t44 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t39, ptr %t44
  %t45 = getelementptr ptr, ptr %t33, i32 1
  store ptr %t36, ptr %t45
  %t46 = call ptr @v_unwrap(ptr %t33)
  %t47 = call ptr @__concat(ptr %t32, ptr %t46)
  %t48 = getelementptr ptr, ptr %t47, i32 0
  %t49 = load ptr, ptr %t48
  %t50 = ptrtoint ptr %t49 to i64
  switch i64 %t50, label %case.default.51 [ i64 0, label %case.arm.0.53 i64 1, label %case.arm.1.61 ]
case.arm.0.53:
  %t55 = getelementptr ptr, ptr %t47, i32 1
  %t56 = load ptr, ptr %t55
  %t57 = call ptr @malloc(i64 16)
  %t58 = inttoptr i64 0 to ptr
  %t59 = getelementptr ptr, ptr %t57, i32 0
  store ptr %t58, ptr %t59
  %t60 = getelementptr ptr, ptr %t57, i32 1
  store ptr %t56, ptr %t60
  br label %case.end.0.54
case.end.0.54:
  br label %case.join.52
case.arm.1.61:
  %t63 = getelementptr ptr, ptr %t47, i32 1
  %t64 = load ptr, ptr %t63
  %t65 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  %t66 = call ptr @__concat(ptr %t64, ptr %t65)
  %t67 = getelementptr ptr, ptr %t66, i32 0
  %t68 = load ptr, ptr %t67
  %t69 = ptrtoint ptr %t68 to i64
  switch i64 %t69, label %case.default.70 [ i64 0, label %case.arm.0.72 i64 1, label %case.arm.1.80 ]
case.arm.0.72:
  %t74 = getelementptr ptr, ptr %t66, i32 1
  %t75 = load ptr, ptr %t74
  %t76 = call ptr @malloc(i64 16)
  %t77 = inttoptr i64 0 to ptr
  %t78 = getelementptr ptr, ptr %t76, i32 0
  store ptr %t77, ptr %t78
  %t79 = getelementptr ptr, ptr %t76, i32 1
  store ptr %t75, ptr %t79
  br label %case.end.0.73
case.end.0.73:
  br label %case.join.71
case.arm.1.80:
  %t82 = getelementptr ptr, ptr %t66, i32 1
  %t83 = load ptr, ptr %t82
  %t84 = call ptr @malloc(i64 16)
  %t85 = inttoptr i64 0 to ptr
  %t86 = getelementptr ptr, ptr %t84, i32 0
  store ptr %t85, ptr %t86
  %t87 = call ptr @malloc(i64 16)
  %t88 = inttoptr i64 1 to ptr
  %t89 = getelementptr ptr, ptr %t87, i32 0
  store ptr %t88, ptr %t89
  %t90 = call ptr @malloc(i64 16)
  %t91 = inttoptr i64 0 to ptr
  %t92 = getelementptr ptr, ptr %t90, i32 0
  store ptr %t91, ptr %t92
  %t93 = getelementptr [2 x i8], ptr @.str.3, i64 0, i64 0
  %t94 = getelementptr ptr, ptr %t90, i32 1
  store ptr %t93, ptr %t94
  %t95 = getelementptr ptr, ptr %t87, i32 1
  store ptr %t90, ptr %t95
  %t96 = getelementptr ptr, ptr %t84, i32 1
  store ptr %t87, ptr %t96
  %t97 = call ptr @v_unwrap(ptr %t84)
  %t98 = call ptr @__concat(ptr %t83, ptr %t97)
  %t99 = getelementptr ptr, ptr %t98, i32 0
  %t100 = load ptr, ptr %t99
  %t101 = ptrtoint ptr %t100 to i64
  switch i64 %t101, label %case.default.102 [ i64 0, label %case.arm.0.104 i64 1, label %case.arm.1.112 ]
case.arm.0.104:
  %t106 = getelementptr ptr, ptr %t98, i32 1
  %t107 = load ptr, ptr %t106
  %t108 = call ptr @malloc(i64 16)
  %t109 = inttoptr i64 0 to ptr
  %t110 = getelementptr ptr, ptr %t108, i32 0
  store ptr %t109, ptr %t110
  %t111 = getelementptr ptr, ptr %t108, i32 1
  store ptr %t107, ptr %t111
  br label %case.end.0.105
case.end.0.105:
  br label %case.join.103
case.arm.1.112:
  %t114 = getelementptr ptr, ptr %t98, i32 1
  %t115 = load ptr, ptr %t114
  %t116 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  %t117 = call ptr @__concat(ptr %t115, ptr %t116)
  %t118 = getelementptr ptr, ptr %t117, i32 0
  %t119 = load ptr, ptr %t118
  %t120 = ptrtoint ptr %t119 to i64
  switch i64 %t120, label %case.default.121 [ i64 0, label %case.arm.0.123 i64 1, label %case.arm.1.131 ]
case.arm.0.123:
  %t125 = getelementptr ptr, ptr %t117, i32 1
  %t126 = load ptr, ptr %t125
  %t127 = call ptr @malloc(i64 16)
  %t128 = inttoptr i64 0 to ptr
  %t129 = getelementptr ptr, ptr %t127, i32 0
  store ptr %t128, ptr %t129
  %t130 = getelementptr ptr, ptr %t127, i32 1
  store ptr %t126, ptr %t130
  br label %case.end.0.124
case.end.0.124:
  br label %case.join.122
case.arm.1.131:
  %t133 = getelementptr ptr, ptr %t117, i32 1
  %t134 = load ptr, ptr %t133
  %t135 = call ptr @malloc(i64 16)
  %t136 = inttoptr i64 0 to ptr
  %t137 = getelementptr ptr, ptr %t135, i32 0
  store ptr %t136, ptr %t137
  %t138 = call ptr @malloc(i64 16)
  %t139 = inttoptr i64 1 to ptr
  %t140 = getelementptr ptr, ptr %t138, i32 0
  store ptr %t139, ptr %t140
  %t141 = call ptr @malloc(i64 16)
  %t142 = inttoptr i64 1 to ptr
  %t143 = getelementptr ptr, ptr %t141, i32 0
  store ptr %t142, ptr %t143
  %t144 = getelementptr [2 x i8], ptr @.str.4, i64 0, i64 0
  %t145 = getelementptr ptr, ptr %t141, i32 1
  store ptr %t144, ptr %t145
  %t146 = getelementptr ptr, ptr %t138, i32 1
  store ptr %t141, ptr %t146
  %t147 = getelementptr ptr, ptr %t135, i32 1
  store ptr %t138, ptr %t147
  %t148 = call ptr @v_unwrap(ptr %t135)
  %t149 = call ptr @__concat(ptr %t134, ptr %t148)
  %t150 = getelementptr ptr, ptr %t149, i32 0
  %t151 = load ptr, ptr %t150
  %t152 = ptrtoint ptr %t151 to i64
  switch i64 %t152, label %case.default.153 [ i64 0, label %case.arm.0.155 i64 1, label %case.arm.1.163 ]
case.arm.0.155:
  %t157 = getelementptr ptr, ptr %t149, i32 1
  %t158 = load ptr, ptr %t157
  %t159 = call ptr @malloc(i64 16)
  %t160 = inttoptr i64 0 to ptr
  %t161 = getelementptr ptr, ptr %t159, i32 0
  store ptr %t160, ptr %t161
  %t162 = getelementptr ptr, ptr %t159, i32 1
  store ptr %t158, ptr %t162
  br label %case.end.0.156
case.end.0.156:
  br label %case.join.154
case.arm.1.163:
  %t165 = getelementptr ptr, ptr %t149, i32 1
  %t166 = load ptr, ptr %t165
  %t167 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  %t168 = call ptr @__concat(ptr %t166, ptr %t167)
  %t169 = getelementptr ptr, ptr %t168, i32 0
  %t170 = load ptr, ptr %t169
  %t171 = ptrtoint ptr %t170 to i64
  switch i64 %t171, label %case.default.172 [ i64 0, label %case.arm.0.174 i64 1, label %case.arm.1.182 ]
case.arm.0.174:
  %t176 = getelementptr ptr, ptr %t168, i32 1
  %t177 = load ptr, ptr %t176
  %t178 = call ptr @malloc(i64 16)
  %t179 = inttoptr i64 0 to ptr
  %t180 = getelementptr ptr, ptr %t178, i32 0
  store ptr %t179, ptr %t180
  %t181 = getelementptr ptr, ptr %t178, i32 1
  store ptr %t177, ptr %t181
  br label %case.end.0.175
case.end.0.175:
  br label %case.join.173
case.arm.1.182:
  %t184 = getelementptr ptr, ptr %t168, i32 1
  %t185 = load ptr, ptr %t184
  %t186 = call ptr @malloc(i64 16)
  %t187 = inttoptr i64 1 to ptr
  %t188 = getelementptr ptr, ptr %t186, i32 0
  store ptr %t187, ptr %t188
  %t189 = call ptr @malloc(i64 16)
  %t190 = inttoptr i64 0 to ptr
  %t191 = getelementptr ptr, ptr %t189, i32 0
  store ptr %t190, ptr %t191
  %t192 = call ptr @malloc(i64 16)
  %t193 = inttoptr i64 0 to ptr
  %t194 = getelementptr ptr, ptr %t192, i32 0
  store ptr %t193, ptr %t194
  %t195 = getelementptr [2 x i8], ptr @.str.5, i64 0, i64 0
  %t196 = getelementptr ptr, ptr %t192, i32 1
  store ptr %t195, ptr %t196
  %t197 = getelementptr ptr, ptr %t189, i32 1
  store ptr %t192, ptr %t197
  %t198 = getelementptr ptr, ptr %t186, i32 1
  store ptr %t189, ptr %t198
  %t199 = call ptr @v_unwrap(ptr %t186)
  %t200 = call ptr @__concat(ptr %t185, ptr %t199)
  %t201 = getelementptr ptr, ptr %t200, i32 0
  %t202 = load ptr, ptr %t201
  %t203 = ptrtoint ptr %t202 to i64
  switch i64 %t203, label %case.default.204 [ i64 0, label %case.arm.0.206 i64 1, label %case.arm.1.214 ]
case.arm.0.206:
  %t208 = getelementptr ptr, ptr %t200, i32 1
  %t209 = load ptr, ptr %t208
  %t210 = call ptr @malloc(i64 16)
  %t211 = inttoptr i64 0 to ptr
  %t212 = getelementptr ptr, ptr %t210, i32 0
  store ptr %t211, ptr %t212
  %t213 = getelementptr ptr, ptr %t210, i32 1
  store ptr %t209, ptr %t213
  br label %case.end.0.207
case.end.0.207:
  br label %case.join.205
case.arm.1.214:
  %t216 = getelementptr ptr, ptr %t200, i32 1
  %t217 = load ptr, ptr %t216
  %t218 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  %t219 = call ptr @__concat(ptr %t217, ptr %t218)
  %t220 = getelementptr ptr, ptr %t219, i32 0
  %t221 = load ptr, ptr %t220
  %t222 = ptrtoint ptr %t221 to i64
  switch i64 %t222, label %case.default.223 [ i64 0, label %case.arm.0.225 i64 1, label %case.arm.1.233 ]
case.arm.0.225:
  %t227 = getelementptr ptr, ptr %t219, i32 1
  %t228 = load ptr, ptr %t227
  %t229 = call ptr @malloc(i64 16)
  %t230 = inttoptr i64 0 to ptr
  %t231 = getelementptr ptr, ptr %t229, i32 0
  store ptr %t230, ptr %t231
  %t232 = getelementptr ptr, ptr %t229, i32 1
  store ptr %t228, ptr %t232
  br label %case.end.0.226
case.end.0.226:
  br label %case.join.224
case.arm.1.233:
  %t235 = getelementptr ptr, ptr %t219, i32 1
  %t236 = load ptr, ptr %t235
  %t237 = call ptr @malloc(i64 16)
  %t238 = inttoptr i64 1 to ptr
  %t239 = getelementptr ptr, ptr %t237, i32 0
  store ptr %t238, ptr %t239
  %t240 = call ptr @malloc(i64 16)
  %t241 = inttoptr i64 0 to ptr
  %t242 = getelementptr ptr, ptr %t240, i32 0
  store ptr %t241, ptr %t242
  %t243 = call ptr @malloc(i64 16)
  %t244 = inttoptr i64 1 to ptr
  %t245 = getelementptr ptr, ptr %t243, i32 0
  store ptr %t244, ptr %t245
  %t246 = getelementptr [2 x i8], ptr @.str.6, i64 0, i64 0
  %t247 = getelementptr ptr, ptr %t243, i32 1
  store ptr %t246, ptr %t247
  %t248 = getelementptr ptr, ptr %t240, i32 1
  store ptr %t243, ptr %t248
  %t249 = getelementptr ptr, ptr %t237, i32 1
  store ptr %t240, ptr %t249
  %t250 = call ptr @v_unwrap(ptr %t237)
  %t251 = call ptr @__concat(ptr %t236, ptr %t250)
  %t252 = getelementptr ptr, ptr %t251, i32 0
  %t253 = load ptr, ptr %t252
  %t254 = ptrtoint ptr %t253 to i64
  switch i64 %t254, label %case.default.255 [ i64 0, label %case.arm.0.257 i64 1, label %case.arm.1.265 ]
case.arm.0.257:
  %t259 = getelementptr ptr, ptr %t251, i32 1
  %t260 = load ptr, ptr %t259
  %t261 = call ptr @malloc(i64 16)
  %t262 = inttoptr i64 0 to ptr
  %t263 = getelementptr ptr, ptr %t261, i32 0
  store ptr %t262, ptr %t263
  %t264 = getelementptr ptr, ptr %t261, i32 1
  store ptr %t260, ptr %t264
  br label %case.end.0.258
case.end.0.258:
  br label %case.join.256
case.arm.1.265:
  %t267 = getelementptr ptr, ptr %t251, i32 1
  %t268 = load ptr, ptr %t267
  %t269 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  %t270 = call ptr @__concat(ptr %t268, ptr %t269)
  %t271 = getelementptr ptr, ptr %t270, i32 0
  %t272 = load ptr, ptr %t271
  %t273 = ptrtoint ptr %t272 to i64
  switch i64 %t273, label %case.default.274 [ i64 0, label %case.arm.0.276 i64 1, label %case.arm.1.284 ]
case.arm.0.276:
  %t278 = getelementptr ptr, ptr %t270, i32 1
  %t279 = load ptr, ptr %t278
  %t280 = call ptr @malloc(i64 16)
  %t281 = inttoptr i64 0 to ptr
  %t282 = getelementptr ptr, ptr %t280, i32 0
  store ptr %t281, ptr %t282
  %t283 = getelementptr ptr, ptr %t280, i32 1
  store ptr %t279, ptr %t283
  br label %case.end.0.277
case.end.0.277:
  br label %case.join.275
case.arm.1.284:
  %t286 = getelementptr ptr, ptr %t270, i32 1
  %t287 = load ptr, ptr %t286
  %t288 = call ptr @malloc(i64 16)
  %t289 = inttoptr i64 1 to ptr
  %t290 = getelementptr ptr, ptr %t288, i32 0
  store ptr %t289, ptr %t290
  %t291 = call ptr @malloc(i64 16)
  %t292 = inttoptr i64 1 to ptr
  %t293 = getelementptr ptr, ptr %t291, i32 0
  store ptr %t292, ptr %t293
  %t294 = call ptr @malloc(i64 16)
  %t295 = inttoptr i64 0 to ptr
  %t296 = getelementptr ptr, ptr %t294, i32 0
  store ptr %t295, ptr %t296
  %t297 = getelementptr [2 x i8], ptr @.str.7, i64 0, i64 0
  %t298 = getelementptr ptr, ptr %t294, i32 1
  store ptr %t297, ptr %t298
  %t299 = getelementptr ptr, ptr %t291, i32 1
  store ptr %t294, ptr %t299
  %t300 = getelementptr ptr, ptr %t288, i32 1
  store ptr %t291, ptr %t300
  %t301 = call ptr @v_unwrap(ptr %t288)
  %t302 = call ptr @__concat(ptr %t287, ptr %t301)
  %t303 = getelementptr ptr, ptr %t302, i32 0
  %t304 = load ptr, ptr %t303
  %t305 = ptrtoint ptr %t304 to i64
  switch i64 %t305, label %case.default.306 [ i64 0, label %case.arm.0.308 i64 1, label %case.arm.1.316 ]
case.arm.0.308:
  %t310 = getelementptr ptr, ptr %t302, i32 1
  %t311 = load ptr, ptr %t310
  %t312 = call ptr @malloc(i64 16)
  %t313 = inttoptr i64 0 to ptr
  %t314 = getelementptr ptr, ptr %t312, i32 0
  store ptr %t313, ptr %t314
  %t315 = getelementptr ptr, ptr %t312, i32 1
  store ptr %t311, ptr %t315
  br label %case.end.0.309
case.end.0.309:
  br label %case.join.307
case.arm.1.316:
  %t318 = getelementptr ptr, ptr %t302, i32 1
  %t319 = load ptr, ptr %t318
  %t320 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  %t321 = call ptr @__concat(ptr %t319, ptr %t320)
  %t322 = getelementptr ptr, ptr %t321, i32 0
  %t323 = load ptr, ptr %t322
  %t324 = ptrtoint ptr %t323 to i64
  switch i64 %t324, label %case.default.325 [ i64 0, label %case.arm.0.327 i64 1, label %case.arm.1.335 ]
case.arm.0.327:
  %t329 = getelementptr ptr, ptr %t321, i32 1
  %t330 = load ptr, ptr %t329
  %t331 = call ptr @malloc(i64 16)
  %t332 = inttoptr i64 0 to ptr
  %t333 = getelementptr ptr, ptr %t331, i32 0
  store ptr %t332, ptr %t333
  %t334 = getelementptr ptr, ptr %t331, i32 1
  store ptr %t330, ptr %t334
  br label %case.end.0.328
case.end.0.328:
  br label %case.join.326
case.arm.1.335:
  %t337 = getelementptr ptr, ptr %t321, i32 1
  %t338 = load ptr, ptr %t337
  %t339 = call ptr @malloc(i64 16)
  %t340 = inttoptr i64 1 to ptr
  %t341 = getelementptr ptr, ptr %t339, i32 0
  store ptr %t340, ptr %t341
  %t342 = call ptr @malloc(i64 16)
  %t343 = inttoptr i64 1 to ptr
  %t344 = getelementptr ptr, ptr %t342, i32 0
  store ptr %t343, ptr %t344
  %t345 = call ptr @malloc(i64 16)
  %t346 = inttoptr i64 1 to ptr
  %t347 = getelementptr ptr, ptr %t345, i32 0
  store ptr %t346, ptr %t347
  %t348 = getelementptr [2 x i8], ptr @.str.8, i64 0, i64 0
  %t349 = getelementptr ptr, ptr %t345, i32 1
  store ptr %t348, ptr %t349
  %t350 = getelementptr ptr, ptr %t342, i32 1
  store ptr %t345, ptr %t350
  %t351 = getelementptr ptr, ptr %t339, i32 1
  store ptr %t342, ptr %t351
  %t352 = call ptr @v_unwrap(ptr %t339)
  %t353 = call ptr @__concat(ptr %t338, ptr %t352)
  br label %case.end.1.336
case.end.1.336:
  br label %case.join.326
case.default.325:
  unreachable
case.join.326:
  %t354 = phi ptr [%t331, %case.end.0.328], [%t353, %case.end.1.336]
  br label %case.end.1.317
case.end.1.317:
  br label %case.join.307
case.default.306:
  unreachable
case.join.307:
  %t355 = phi ptr [%t312, %case.end.0.309], [%t354, %case.end.1.317]
  br label %case.end.1.285
case.end.1.285:
  br label %case.join.275
case.default.274:
  unreachable
case.join.275:
  %t356 = phi ptr [%t280, %case.end.0.277], [%t355, %case.end.1.285]
  br label %case.end.1.266
case.end.1.266:
  br label %case.join.256
case.default.255:
  unreachable
case.join.256:
  %t357 = phi ptr [%t261, %case.end.0.258], [%t356, %case.end.1.266]
  br label %case.end.1.234
case.end.1.234:
  br label %case.join.224
case.default.223:
  unreachable
case.join.224:
  %t358 = phi ptr [%t229, %case.end.0.226], [%t357, %case.end.1.234]
  br label %case.end.1.215
case.end.1.215:
  br label %case.join.205
case.default.204:
  unreachable
case.join.205:
  %t359 = phi ptr [%t210, %case.end.0.207], [%t358, %case.end.1.215]
  br label %case.end.1.183
case.end.1.183:
  br label %case.join.173
case.default.172:
  unreachable
case.join.173:
  %t360 = phi ptr [%t178, %case.end.0.175], [%t359, %case.end.1.183]
  br label %case.end.1.164
case.end.1.164:
  br label %case.join.154
case.default.153:
  unreachable
case.join.154:
  %t361 = phi ptr [%t159, %case.end.0.156], [%t360, %case.end.1.164]
  br label %case.end.1.132
case.end.1.132:
  br label %case.join.122
case.default.121:
  unreachable
case.join.122:
  %t362 = phi ptr [%t127, %case.end.0.124], [%t361, %case.end.1.132]
  br label %case.end.1.113
case.end.1.113:
  br label %case.join.103
case.default.102:
  unreachable
case.join.103:
  %t363 = phi ptr [%t108, %case.end.0.105], [%t362, %case.end.1.113]
  br label %case.end.1.81
case.end.1.81:
  br label %case.join.71
case.default.70:
  unreachable
case.join.71:
  %t364 = phi ptr [%t76, %case.end.0.73], [%t363, %case.end.1.81]
  br label %case.end.1.62
case.end.1.62:
  br label %case.join.52
case.default.51:
  unreachable
case.join.52:
  %t365 = phi ptr [%t57, %case.end.0.54], [%t364, %case.end.1.62]
  br label %case.end.1.30
case.end.1.30:
  br label %case.join.20
case.default.19:
  unreachable
case.join.20:
  %t366 = phi ptr [%t25, %case.end.0.22], [%t365, %case.end.1.30]
  %t367 = call ptr @v__let_2(ptr %t366)
  ret ptr %t367
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
  %t12 = getelementptr [16 x i8], ptr @.str.9, i64 0, i64 0
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
