; External C declarations
declare ptr @malloc(i64)
declare ptr @strcpy(ptr, ptr)
declare ptr @strcat(ptr, ptr)
declare i64 @strlen(ptr)
declare i32 @printf(ptr, ...)
declare i32 @snprintf(ptr, i64, ptr, ...)
declare {i32, i1} @llvm.smul.with.overflow.i32(i32, i32)

@.fmt = private unnamed_addr constant [3 x i8] c"%s\00"
@.fmt_i32 = private unnamed_addr constant [3 x i8] c"%d\00"
@.fmt_u8 = private unnamed_addr constant [3 x i8] c"%u\00"
@.empty = private unnamed_addr constant [1 x i8] c"\00"

@.str.0 = private unnamed_addr constant [15 x i8] c"UnderflowError\00"
@.str.1 = private unnamed_addr constant [14 x i8] c"OverflowError\00"
@.str.2 = private unnamed_addr constant [6 x i8] c"err: \00"
@.str.3 = private unnamed_addr constant [5 x i8] c"ok: \00"
@.str.4 = private unnamed_addr constant [3 x i8] c", \00"
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


define internal ptr @__showInt32(ptr %p) {
  %v = load i32, ptr %p
  %buf = call ptr @malloc(i64 16)
  call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 16, ptr @.fmt_i32, i32 %v)
  ret ptr %buf
}


define internal ptr @__mulInt32(ptr %pa, ptr %pb) {
  %a = load i32, ptr %pa
  %b = load i32, ptr %pb
  %res = call {i32, i1} @llvm.smul.with.overflow.i32(i32 %a, i32 %b)
  %prod = extractvalue {i32, i1} %res, 0
  %ovf = extractvalue {i32, i1} %res, 1
  br i1 %ovf, label %err, label %ok
err:
  %xor_ab = xor i32 %a, %b
  %same_sign = icmp sge i32 %xor_ab, 0
  %row_tag_idx = select i1 %same_sign, i64 882564211, i64 3768445577
  %inner = call ptr @malloc(i64 8)
  %inner_tag = inttoptr i64 0 to ptr
  store ptr %inner_tag, ptr %inner
  %row = call ptr @malloc(i64 16)
  %row_tag = inttoptr i64 %row_tag_idx to ptr
  store ptr %row_tag, ptr %row
  %row_f = getelementptr ptr, ptr %row, i32 1
  store ptr %inner, ptr %row_f
  %left = call ptr @malloc(i64 16)
  %left_tag = inttoptr i64 0 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %row, ptr %left_f
  ret ptr %left
ok:
  %box = call ptr @malloc(i64 4)
  store i32 %prod, ptr %box
  %right = call ptr @malloc(i64 16)
  %right_tag = inttoptr i64 1 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %box, ptr %right_f
  ret ptr %right
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

define internal ptr @v_showUnderflowError(ptr %v__wild0) {
  %t0 = getelementptr [15 x i8], ptr @.str.0, i64 0, i64 0
  ret ptr %t0
}

define internal ptr @v_showOverflowError(ptr %v__wild0) {
  %t0 = getelementptr [14 x i8], ptr @.str.1, i64 0, i64 0
  ret ptr %t0
}

define internal ptr @v_minInt32() {
  %t0 = call ptr @malloc(i64 4)
  store i32 -2147483648, ptr %t0
  ret ptr %t0
}

define internal ptr @v_render(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.29 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_r, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr ptr, ptr %t8, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %case.default.12 [ i64 882564211, label %case.arm.882564211.14 i64 3768445577, label %case.arm.3768445577.21 ]
case.arm.882564211.14:
  %t16 = getelementptr ptr, ptr %t8, i32 1
  %t17 = load ptr, ptr %t16
  %t18 = getelementptr [6 x i8], ptr @.str.2, i64 0, i64 0
  %t19 = call ptr @v_showOverflowError(ptr %t17)
  %t20 = call ptr @__concat(ptr %t18, ptr %t19)
  br label %case.end.882564211.15
case.end.882564211.15:
  br label %case.join.13
case.arm.3768445577.21:
  %t23 = getelementptr ptr, ptr %t8, i32 1
  %t24 = load ptr, ptr %t23
  %t25 = getelementptr [6 x i8], ptr @.str.2, i64 0, i64 0
  %t26 = call ptr @v_showUnderflowError(ptr %t24)
  %t27 = call ptr @__concat(ptr %t25, ptr %t26)
  br label %case.end.3768445577.22
case.end.3768445577.22:
  br label %case.join.13
case.default.12:
  unreachable
case.join.13:
  %t28 = phi ptr [%t20, %case.end.882564211.15], [%t27, %case.end.3768445577.22]
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.29:
  %t31 = getelementptr ptr, ptr %v_r, i32 1
  %t32 = load ptr, ptr %t31
  %t33 = getelementptr [5 x i8], ptr @.str.3, i64 0, i64 0
  %t34 = call ptr @__showInt32(ptr %t32)
  %t35 = call ptr @__concat(ptr %t33, ptr %t34)
  br label %case.end.1.30
case.end.1.30:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t36 = phi ptr [%t28, %case.end.0.6], [%t35, %case.end.1.30]
  ret ptr %t36
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 4)
  store i32 6, ptr %t0
  %t1 = call ptr @malloc(i64 4)
  store i32 7, ptr %t1
  %t2 = call ptr @__mulInt32(ptr %t0, ptr %t1)
  %t3 = call ptr @v_render(ptr %t2)
  %t4 = getelementptr ptr, ptr %t3, i32 0
  %t5 = load ptr, ptr %t4
  %t6 = ptrtoint ptr %t5 to i64
  switch i64 %t6, label %case.default.7 [ i64 0, label %case.arm.0.9 i64 1, label %case.arm.1.17 ]
case.arm.0.9:
  %t11 = getelementptr ptr, ptr %t3, i32 1
  %t12 = load ptr, ptr %t11
  %t13 = call ptr @malloc(i64 16)
  %t14 = inttoptr i64 0 to ptr
  %t15 = getelementptr ptr, ptr %t13, i32 0
  store ptr %t14, ptr %t15
  %t16 = getelementptr ptr, ptr %t13, i32 1
  store ptr %t12, ptr %t16
  br label %case.end.0.10
case.end.0.10:
  br label %case.join.8
case.arm.1.17:
  %t19 = getelementptr ptr, ptr %t3, i32 1
  %t20 = load ptr, ptr %t19
  %t21 = call ptr @malloc(i64 4)
  store i32 -6, ptr %t21
  %t22 = call ptr @malloc(i64 4)
  store i32 7, ptr %t22
  %t23 = call ptr @__mulInt32(ptr %t21, ptr %t22)
  %t24 = call ptr @v_render(ptr %t23)
  %t25 = getelementptr ptr, ptr %t24, i32 0
  %t26 = load ptr, ptr %t25
  %t27 = ptrtoint ptr %t26 to i64
  switch i64 %t27, label %case.default.28 [ i64 0, label %case.arm.0.30 i64 1, label %case.arm.1.38 ]
case.arm.0.30:
  %t32 = getelementptr ptr, ptr %t24, i32 1
  %t33 = load ptr, ptr %t32
  %t34 = call ptr @malloc(i64 16)
  %t35 = inttoptr i64 0 to ptr
  %t36 = getelementptr ptr, ptr %t34, i32 0
  store ptr %t35, ptr %t36
  %t37 = getelementptr ptr, ptr %t34, i32 1
  store ptr %t33, ptr %t37
  br label %case.end.0.31
case.end.0.31:
  br label %case.join.29
case.arm.1.38:
  %t40 = getelementptr ptr, ptr %t24, i32 1
  %t41 = load ptr, ptr %t40
  %t42 = call ptr @malloc(i64 4)
  store i32 100000, ptr %t42
  %t43 = call ptr @malloc(i64 4)
  store i32 100000, ptr %t43
  %t44 = call ptr @__mulInt32(ptr %t42, ptr %t43)
  %t45 = call ptr @v_render(ptr %t44)
  %t46 = getelementptr ptr, ptr %t45, i32 0
  %t47 = load ptr, ptr %t46
  %t48 = ptrtoint ptr %t47 to i64
  switch i64 %t48, label %case.default.49 [ i64 0, label %case.arm.0.51 i64 1, label %case.arm.1.59 ]
case.arm.0.51:
  %t53 = getelementptr ptr, ptr %t45, i32 1
  %t54 = load ptr, ptr %t53
  %t55 = call ptr @malloc(i64 16)
  %t56 = inttoptr i64 0 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  %t58 = getelementptr ptr, ptr %t55, i32 1
  store ptr %t54, ptr %t58
  br label %case.end.0.52
case.end.0.52:
  br label %case.join.50
case.arm.1.59:
  %t61 = getelementptr ptr, ptr %t45, i32 1
  %t62 = load ptr, ptr %t61
  %t63 = call ptr @malloc(i64 4)
  store i32 -100000, ptr %t63
  %t64 = call ptr @malloc(i64 4)
  store i32 100000, ptr %t64
  %t65 = call ptr @__mulInt32(ptr %t63, ptr %t64)
  %t66 = call ptr @v_render(ptr %t65)
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
  %t84 = call ptr @v_minInt32()
  %t85 = call ptr @malloc(i64 4)
  store i32 -1, ptr %t85
  %t86 = call ptr @__mulInt32(ptr %t84, ptr %t85)
  %t87 = call ptr @v_render(ptr %t86)
  %t88 = getelementptr ptr, ptr %t87, i32 0
  %t89 = load ptr, ptr %t88
  %t90 = ptrtoint ptr %t89 to i64
  switch i64 %t90, label %case.default.91 [ i64 0, label %case.arm.0.93 i64 1, label %case.arm.1.101 ]
case.arm.0.93:
  %t95 = getelementptr ptr, ptr %t87, i32 1
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
  %t103 = getelementptr ptr, ptr %t87, i32 1
  %t104 = load ptr, ptr %t103
  %t105 = call ptr @v_minInt32()
  %t106 = call ptr @malloc(i64 4)
  store i32 1, ptr %t106
  %t107 = call ptr @__mulInt32(ptr %t105, ptr %t106)
  %t108 = call ptr @v_render(ptr %t107)
  %t109 = getelementptr ptr, ptr %t108, i32 0
  %t110 = load ptr, ptr %t109
  %t111 = ptrtoint ptr %t110 to i64
  switch i64 %t111, label %case.default.112 [ i64 0, label %case.arm.0.114 i64 1, label %case.arm.1.122 ]
case.arm.0.114:
  %t116 = getelementptr ptr, ptr %t108, i32 1
  %t117 = load ptr, ptr %t116
  %t118 = call ptr @malloc(i64 16)
  %t119 = inttoptr i64 0 to ptr
  %t120 = getelementptr ptr, ptr %t118, i32 0
  store ptr %t119, ptr %t120
  %t121 = getelementptr ptr, ptr %t118, i32 1
  store ptr %t117, ptr %t121
  br label %case.end.0.115
case.end.0.115:
  br label %case.join.113
case.arm.1.122:
  %t124 = getelementptr ptr, ptr %t108, i32 1
  %t125 = load ptr, ptr %t124
  %t126 = getelementptr [3 x i8], ptr @.str.4, i64 0, i64 0
  %t127 = call ptr @__concat(ptr %t20, ptr %t126)
  %t128 = getelementptr ptr, ptr %t127, i32 0
  %t129 = load ptr, ptr %t128
  %t130 = ptrtoint ptr %t129 to i64
  switch i64 %t130, label %case.default.131 [ i64 0, label %case.arm.0.133 i64 1, label %case.arm.1.141 ]
case.arm.0.133:
  %t135 = getelementptr ptr, ptr %t127, i32 1
  %t136 = load ptr, ptr %t135
  %t137 = call ptr @malloc(i64 16)
  %t138 = inttoptr i64 0 to ptr
  %t139 = getelementptr ptr, ptr %t137, i32 0
  store ptr %t138, ptr %t139
  %t140 = getelementptr ptr, ptr %t137, i32 1
  store ptr %t136, ptr %t140
  br label %case.end.0.134
case.end.0.134:
  br label %case.join.132
case.arm.1.141:
  %t143 = getelementptr ptr, ptr %t127, i32 1
  %t144 = load ptr, ptr %t143
  %t145 = call ptr @__concat(ptr %t144, ptr %t41)
  %t146 = getelementptr ptr, ptr %t145, i32 0
  %t147 = load ptr, ptr %t146
  %t148 = ptrtoint ptr %t147 to i64
  switch i64 %t148, label %case.default.149 [ i64 0, label %case.arm.0.151 i64 1, label %case.arm.1.159 ]
case.arm.0.151:
  %t153 = getelementptr ptr, ptr %t145, i32 1
  %t154 = load ptr, ptr %t153
  %t155 = call ptr @malloc(i64 16)
  %t156 = inttoptr i64 0 to ptr
  %t157 = getelementptr ptr, ptr %t155, i32 0
  store ptr %t156, ptr %t157
  %t158 = getelementptr ptr, ptr %t155, i32 1
  store ptr %t154, ptr %t158
  br label %case.end.0.152
case.end.0.152:
  br label %case.join.150
case.arm.1.159:
  %t161 = getelementptr ptr, ptr %t145, i32 1
  %t162 = load ptr, ptr %t161
  %t163 = getelementptr [3 x i8], ptr @.str.4, i64 0, i64 0
  %t164 = call ptr @__concat(ptr %t162, ptr %t163)
  %t165 = getelementptr ptr, ptr %t164, i32 0
  %t166 = load ptr, ptr %t165
  %t167 = ptrtoint ptr %t166 to i64
  switch i64 %t167, label %case.default.168 [ i64 0, label %case.arm.0.170 i64 1, label %case.arm.1.178 ]
case.arm.0.170:
  %t172 = getelementptr ptr, ptr %t164, i32 1
  %t173 = load ptr, ptr %t172
  %t174 = call ptr @malloc(i64 16)
  %t175 = inttoptr i64 0 to ptr
  %t176 = getelementptr ptr, ptr %t174, i32 0
  store ptr %t175, ptr %t176
  %t177 = getelementptr ptr, ptr %t174, i32 1
  store ptr %t173, ptr %t177
  br label %case.end.0.171
case.end.0.171:
  br label %case.join.169
case.arm.1.178:
  %t180 = getelementptr ptr, ptr %t164, i32 1
  %t181 = load ptr, ptr %t180
  %t182 = call ptr @__concat(ptr %t181, ptr %t62)
  %t183 = getelementptr ptr, ptr %t182, i32 0
  %t184 = load ptr, ptr %t183
  %t185 = ptrtoint ptr %t184 to i64
  switch i64 %t185, label %case.default.186 [ i64 0, label %case.arm.0.188 i64 1, label %case.arm.1.196 ]
case.arm.0.188:
  %t190 = getelementptr ptr, ptr %t182, i32 1
  %t191 = load ptr, ptr %t190
  %t192 = call ptr @malloc(i64 16)
  %t193 = inttoptr i64 0 to ptr
  %t194 = getelementptr ptr, ptr %t192, i32 0
  store ptr %t193, ptr %t194
  %t195 = getelementptr ptr, ptr %t192, i32 1
  store ptr %t191, ptr %t195
  br label %case.end.0.189
case.end.0.189:
  br label %case.join.187
case.arm.1.196:
  %t198 = getelementptr ptr, ptr %t182, i32 1
  %t199 = load ptr, ptr %t198
  %t200 = getelementptr [3 x i8], ptr @.str.4, i64 0, i64 0
  %t201 = call ptr @__concat(ptr %t199, ptr %t200)
  %t202 = getelementptr ptr, ptr %t201, i32 0
  %t203 = load ptr, ptr %t202
  %t204 = ptrtoint ptr %t203 to i64
  switch i64 %t204, label %case.default.205 [ i64 0, label %case.arm.0.207 i64 1, label %case.arm.1.215 ]
case.arm.0.207:
  %t209 = getelementptr ptr, ptr %t201, i32 1
  %t210 = load ptr, ptr %t209
  %t211 = call ptr @malloc(i64 16)
  %t212 = inttoptr i64 0 to ptr
  %t213 = getelementptr ptr, ptr %t211, i32 0
  store ptr %t212, ptr %t213
  %t214 = getelementptr ptr, ptr %t211, i32 1
  store ptr %t210, ptr %t214
  br label %case.end.0.208
case.end.0.208:
  br label %case.join.206
case.arm.1.215:
  %t217 = getelementptr ptr, ptr %t201, i32 1
  %t218 = load ptr, ptr %t217
  %t219 = call ptr @__concat(ptr %t218, ptr %t83)
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
  %t237 = getelementptr [3 x i8], ptr @.str.4, i64 0, i64 0
  %t238 = call ptr @__concat(ptr %t236, ptr %t237)
  %t239 = getelementptr ptr, ptr %t238, i32 0
  %t240 = load ptr, ptr %t239
  %t241 = ptrtoint ptr %t240 to i64
  switch i64 %t241, label %case.default.242 [ i64 0, label %case.arm.0.244 i64 1, label %case.arm.1.252 ]
case.arm.0.244:
  %t246 = getelementptr ptr, ptr %t238, i32 1
  %t247 = load ptr, ptr %t246
  %t248 = call ptr @malloc(i64 16)
  %t249 = inttoptr i64 0 to ptr
  %t250 = getelementptr ptr, ptr %t248, i32 0
  store ptr %t249, ptr %t250
  %t251 = getelementptr ptr, ptr %t248, i32 1
  store ptr %t247, ptr %t251
  br label %case.end.0.245
case.end.0.245:
  br label %case.join.243
case.arm.1.252:
  %t254 = getelementptr ptr, ptr %t238, i32 1
  %t255 = load ptr, ptr %t254
  %t256 = call ptr @__concat(ptr %t255, ptr %t104)
  %t257 = getelementptr ptr, ptr %t256, i32 0
  %t258 = load ptr, ptr %t257
  %t259 = ptrtoint ptr %t258 to i64
  switch i64 %t259, label %case.default.260 [ i64 0, label %case.arm.0.262 i64 1, label %case.arm.1.270 ]
case.arm.0.262:
  %t264 = getelementptr ptr, ptr %t256, i32 1
  %t265 = load ptr, ptr %t264
  %t266 = call ptr @malloc(i64 16)
  %t267 = inttoptr i64 0 to ptr
  %t268 = getelementptr ptr, ptr %t266, i32 0
  store ptr %t267, ptr %t268
  %t269 = getelementptr ptr, ptr %t266, i32 1
  store ptr %t265, ptr %t269
  br label %case.end.0.263
case.end.0.263:
  br label %case.join.261
case.arm.1.270:
  %t272 = getelementptr ptr, ptr %t256, i32 1
  %t273 = load ptr, ptr %t272
  %t274 = getelementptr [3 x i8], ptr @.str.4, i64 0, i64 0
  %t275 = call ptr @__concat(ptr %t273, ptr %t274)
  %t276 = getelementptr ptr, ptr %t275, i32 0
  %t277 = load ptr, ptr %t276
  %t278 = ptrtoint ptr %t277 to i64
  switch i64 %t278, label %case.default.279 [ i64 0, label %case.arm.0.281 i64 1, label %case.arm.1.289 ]
case.arm.0.281:
  %t283 = getelementptr ptr, ptr %t275, i32 1
  %t284 = load ptr, ptr %t283
  %t285 = call ptr @malloc(i64 16)
  %t286 = inttoptr i64 0 to ptr
  %t287 = getelementptr ptr, ptr %t285, i32 0
  store ptr %t286, ptr %t287
  %t288 = getelementptr ptr, ptr %t285, i32 1
  store ptr %t284, ptr %t288
  br label %case.end.0.282
case.end.0.282:
  br label %case.join.280
case.arm.1.289:
  %t291 = getelementptr ptr, ptr %t275, i32 1
  %t292 = load ptr, ptr %t291
  %t293 = call ptr @__concat(ptr %t292, ptr %t125)
  br label %case.end.1.290
case.end.1.290:
  br label %case.join.280
case.default.279:
  unreachable
case.join.280:
  %t294 = phi ptr [%t285, %case.end.0.282], [%t293, %case.end.1.290]
  br label %case.end.1.271
case.end.1.271:
  br label %case.join.261
case.default.260:
  unreachable
case.join.261:
  %t295 = phi ptr [%t266, %case.end.0.263], [%t294, %case.end.1.271]
  br label %case.end.1.253
case.end.1.253:
  br label %case.join.243
case.default.242:
  unreachable
case.join.243:
  %t296 = phi ptr [%t248, %case.end.0.245], [%t295, %case.end.1.253]
  br label %case.end.1.234
case.end.1.234:
  br label %case.join.224
case.default.223:
  unreachable
case.join.224:
  %t297 = phi ptr [%t229, %case.end.0.226], [%t296, %case.end.1.234]
  br label %case.end.1.216
case.end.1.216:
  br label %case.join.206
case.default.205:
  unreachable
case.join.206:
  %t298 = phi ptr [%t211, %case.end.0.208], [%t297, %case.end.1.216]
  br label %case.end.1.197
case.end.1.197:
  br label %case.join.187
case.default.186:
  unreachable
case.join.187:
  %t299 = phi ptr [%t192, %case.end.0.189], [%t298, %case.end.1.197]
  br label %case.end.1.179
case.end.1.179:
  br label %case.join.169
case.default.168:
  unreachable
case.join.169:
  %t300 = phi ptr [%t174, %case.end.0.171], [%t299, %case.end.1.179]
  br label %case.end.1.160
case.end.1.160:
  br label %case.join.150
case.default.149:
  unreachable
case.join.150:
  %t301 = phi ptr [%t155, %case.end.0.152], [%t300, %case.end.1.160]
  br label %case.end.1.142
case.end.1.142:
  br label %case.join.132
case.default.131:
  unreachable
case.join.132:
  %t302 = phi ptr [%t137, %case.end.0.134], [%t301, %case.end.1.142]
  br label %case.end.1.123
case.end.1.123:
  br label %case.join.113
case.default.112:
  unreachable
case.join.113:
  %t303 = phi ptr [%t118, %case.end.0.115], [%t302, %case.end.1.123]
  br label %case.end.1.102
case.end.1.102:
  br label %case.join.92
case.default.91:
  unreachable
case.join.92:
  %t304 = phi ptr [%t97, %case.end.0.94], [%t303, %case.end.1.102]
  br label %case.end.1.81
case.end.1.81:
  br label %case.join.71
case.default.70:
  unreachable
case.join.71:
  %t305 = phi ptr [%t76, %case.end.0.73], [%t304, %case.end.1.81]
  br label %case.end.1.60
case.end.1.60:
  br label %case.join.50
case.default.49:
  unreachable
case.join.50:
  %t306 = phi ptr [%t55, %case.end.0.52], [%t305, %case.end.1.60]
  br label %case.end.1.39
case.end.1.39:
  br label %case.join.29
case.default.28:
  unreachable
case.join.29:
  %t307 = phi ptr [%t34, %case.end.0.31], [%t306, %case.end.1.39]
  br label %case.end.1.18
case.end.1.18:
  br label %case.join.8
case.default.7:
  unreachable
case.join.8:
  %t308 = phi ptr [%t13, %case.end.0.10], [%t307, %case.end.1.18]
  %t309 = call ptr @v__let_2(ptr %t308)
  ret ptr %t309
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
