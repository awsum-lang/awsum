; External C declarations
declare ptr @malloc(i64)
declare ptr @strcpy(ptr, ptr)
declare ptr @strcat(ptr, ptr)
declare i64 @strlen(ptr)
declare i32 @printf(ptr, ...)
declare i32 @snprintf(ptr, i64, ptr, ...)
declare {i32, i1} @llvm.ssub.with.overflow.i32(i32, i32)

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


define internal ptr @__showInt32(ptr %p) {
  %v = load i32, ptr %p
  %buf = call ptr @malloc(i64 16)
  call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 16, ptr @.fmt_i32, i32 %v)
  ret ptr %buf
}


define internal ptr @__subInt32(ptr %pa, ptr %pb) {
  %a = load i32, ptr %pa
  %b = load i32, ptr %pb
  %res = call {i32, i1} @llvm.ssub.with.overflow.i32(i32 %a, i32 %b)
  %diff = extractvalue {i32, i1} %res, 0
  %ovf = extractvalue {i32, i1} %res, 1
  br i1 %ovf, label %err, label %ok
err:
  %is_pos = icmp sge i32 %a, 0
  %row_tag_idx = select i1 %is_pos, i64 882564211, i64 3768445577
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
  store i32 %diff, ptr %box
  %right = call ptr @malloc(i64 16)
  %right_tag = inttoptr i64 1 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %box, ptr %right_f
  ret ptr %right
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

define internal ptr @v_maxInt32() {
  %t0 = call ptr @malloc(i64 4)
  store i32 2147483647, ptr %t0
  ret ptr %t0
}

define internal ptr @v_render(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.37 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_r, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr ptr, ptr %t8, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %case.default.12 [ i64 882564211, label %case.arm.882564211.14 i64 3768445577, label %case.arm.3768445577.25 ]
case.arm.882564211.14:
  %t16 = getelementptr ptr, ptr %t8, i32 1
  %t17 = load ptr, ptr %t16
  %t18 = call ptr @malloc(i64 16)
  %t19 = inttoptr i64 1 to ptr
  %t20 = getelementptr ptr, ptr %t18, i32 0
  store ptr %t19, ptr %t20
  %t21 = getelementptr [6 x i8], ptr @.str.2, i64 0, i64 0
  %t22 = call ptr @v_showOverflowError(ptr %t17)
  %t23 = call ptr @__concat(ptr %t21, ptr %t22)
  %t24 = getelementptr ptr, ptr %t18, i32 1
  store ptr %t23, ptr %t24
  br label %case.end.882564211.15
case.end.882564211.15:
  br label %case.join.13
case.arm.3768445577.25:
  %t27 = getelementptr ptr, ptr %t8, i32 1
  %t28 = load ptr, ptr %t27
  %t29 = call ptr @malloc(i64 16)
  %t30 = inttoptr i64 1 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = getelementptr [6 x i8], ptr @.str.2, i64 0, i64 0
  %t33 = call ptr @v_showUnderflowError(ptr %t28)
  %t34 = call ptr @__concat(ptr %t32, ptr %t33)
  %t35 = getelementptr ptr, ptr %t29, i32 1
  store ptr %t34, ptr %t35
  br label %case.end.3768445577.26
case.end.3768445577.26:
  br label %case.join.13
case.default.12:
  unreachable
case.join.13:
  %t36 = phi ptr [%t18, %case.end.882564211.15], [%t29, %case.end.3768445577.26]
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.37:
  %t39 = getelementptr ptr, ptr %v_r, i32 1
  %t40 = load ptr, ptr %t39
  %t41 = call ptr @malloc(i64 16)
  %t42 = inttoptr i64 1 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = getelementptr [5 x i8], ptr @.str.3, i64 0, i64 0
  %t45 = call ptr @__showInt32(ptr %t40)
  %t46 = call ptr @__concat(ptr %t44, ptr %t45)
  %t47 = getelementptr ptr, ptr %t41, i32 1
  store ptr %t46, ptr %t47
  br label %case.end.1.38
case.end.1.38:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t48 = phi ptr [%t36, %case.end.0.6], [%t41, %case.end.1.38]
  ret ptr %t48
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 4)
  store i32 100, ptr %t0
  %t1 = call ptr @malloc(i64 4)
  store i32 23, ptr %t1
  %t2 = call ptr @__subInt32(ptr %t0, ptr %t1)
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
  store i32 100, ptr %t21
  %t22 = call ptr @malloc(i64 4)
  store i32 -50, ptr %t22
  %t23 = call ptr @__subInt32(ptr %t21, ptr %t22)
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
  %t42 = call ptr @v_maxInt32()
  %t43 = call ptr @malloc(i64 4)
  store i32 -1, ptr %t43
  %t44 = call ptr @__subInt32(ptr %t42, ptr %t43)
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
  %t63 = call ptr @v_minInt32()
  %t64 = call ptr @malloc(i64 4)
  store i32 1, ptr %t64
  %t65 = call ptr @__subInt32(ptr %t63, ptr %t64)
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
  %t84 = call ptr @malloc(i64 4)
  store i32 0, ptr %t84
  %t85 = call ptr @v_minInt32()
  %t86 = call ptr @__subInt32(ptr %t84, ptr %t85)
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
  %t105 = call ptr @malloc(i64 16)
  %t106 = inttoptr i64 1 to ptr
  %t107 = getelementptr ptr, ptr %t105, i32 0
  store ptr %t106, ptr %t107
  %t108 = getelementptr [3 x i8], ptr @.str.4, i64 0, i64 0
  %t109 = call ptr @__concat(ptr %t20, ptr %t108)
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
  %t131 = call ptr @__concat(ptr %t127, ptr %t41)
  %t132 = getelementptr ptr, ptr %t128, i32 1
  store ptr %t131, ptr %t132
  %t133 = getelementptr ptr, ptr %t128, i32 0
  %t134 = load ptr, ptr %t133
  %t135 = ptrtoint ptr %t134 to i64
  switch i64 %t135, label %case.default.136 [ i64 0, label %case.arm.0.138 i64 1, label %case.arm.1.146 ]
case.arm.0.138:
  %t140 = getelementptr ptr, ptr %t128, i32 1
  %t141 = load ptr, ptr %t140
  %t142 = call ptr @malloc(i64 16)
  %t143 = inttoptr i64 0 to ptr
  %t144 = getelementptr ptr, ptr %t142, i32 0
  store ptr %t143, ptr %t144
  %t145 = getelementptr ptr, ptr %t142, i32 1
  store ptr %t141, ptr %t145
  br label %case.end.0.139
case.end.0.139:
  br label %case.join.137
case.arm.1.146:
  %t148 = getelementptr ptr, ptr %t128, i32 1
  %t149 = load ptr, ptr %t148
  %t150 = call ptr @malloc(i64 16)
  %t151 = inttoptr i64 1 to ptr
  %t152 = getelementptr ptr, ptr %t150, i32 0
  store ptr %t151, ptr %t152
  %t153 = getelementptr [3 x i8], ptr @.str.4, i64 0, i64 0
  %t154 = call ptr @__concat(ptr %t149, ptr %t153)
  %t155 = getelementptr ptr, ptr %t150, i32 1
  store ptr %t154, ptr %t155
  %t156 = getelementptr ptr, ptr %t150, i32 0
  %t157 = load ptr, ptr %t156
  %t158 = ptrtoint ptr %t157 to i64
  switch i64 %t158, label %case.default.159 [ i64 0, label %case.arm.0.161 i64 1, label %case.arm.1.169 ]
case.arm.0.161:
  %t163 = getelementptr ptr, ptr %t150, i32 1
  %t164 = load ptr, ptr %t163
  %t165 = call ptr @malloc(i64 16)
  %t166 = inttoptr i64 0 to ptr
  %t167 = getelementptr ptr, ptr %t165, i32 0
  store ptr %t166, ptr %t167
  %t168 = getelementptr ptr, ptr %t165, i32 1
  store ptr %t164, ptr %t168
  br label %case.end.0.162
case.end.0.162:
  br label %case.join.160
case.arm.1.169:
  %t171 = getelementptr ptr, ptr %t150, i32 1
  %t172 = load ptr, ptr %t171
  %t173 = call ptr @malloc(i64 16)
  %t174 = inttoptr i64 1 to ptr
  %t175 = getelementptr ptr, ptr %t173, i32 0
  store ptr %t174, ptr %t175
  %t176 = call ptr @__concat(ptr %t172, ptr %t62)
  %t177 = getelementptr ptr, ptr %t173, i32 1
  store ptr %t176, ptr %t177
  %t178 = getelementptr ptr, ptr %t173, i32 0
  %t179 = load ptr, ptr %t178
  %t180 = ptrtoint ptr %t179 to i64
  switch i64 %t180, label %case.default.181 [ i64 0, label %case.arm.0.183 i64 1, label %case.arm.1.191 ]
case.arm.0.183:
  %t185 = getelementptr ptr, ptr %t173, i32 1
  %t186 = load ptr, ptr %t185
  %t187 = call ptr @malloc(i64 16)
  %t188 = inttoptr i64 0 to ptr
  %t189 = getelementptr ptr, ptr %t187, i32 0
  store ptr %t188, ptr %t189
  %t190 = getelementptr ptr, ptr %t187, i32 1
  store ptr %t186, ptr %t190
  br label %case.end.0.184
case.end.0.184:
  br label %case.join.182
case.arm.1.191:
  %t193 = getelementptr ptr, ptr %t173, i32 1
  %t194 = load ptr, ptr %t193
  %t195 = call ptr @malloc(i64 16)
  %t196 = inttoptr i64 1 to ptr
  %t197 = getelementptr ptr, ptr %t195, i32 0
  store ptr %t196, ptr %t197
  %t198 = getelementptr [3 x i8], ptr @.str.4, i64 0, i64 0
  %t199 = call ptr @__concat(ptr %t194, ptr %t198)
  %t200 = getelementptr ptr, ptr %t195, i32 1
  store ptr %t199, ptr %t200
  %t201 = getelementptr ptr, ptr %t195, i32 0
  %t202 = load ptr, ptr %t201
  %t203 = ptrtoint ptr %t202 to i64
  switch i64 %t203, label %case.default.204 [ i64 0, label %case.arm.0.206 i64 1, label %case.arm.1.214 ]
case.arm.0.206:
  %t208 = getelementptr ptr, ptr %t195, i32 1
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
  %t216 = getelementptr ptr, ptr %t195, i32 1
  %t217 = load ptr, ptr %t216
  %t218 = call ptr @malloc(i64 16)
  %t219 = inttoptr i64 1 to ptr
  %t220 = getelementptr ptr, ptr %t218, i32 0
  store ptr %t219, ptr %t220
  %t221 = call ptr @__concat(ptr %t217, ptr %t83)
  %t222 = getelementptr ptr, ptr %t218, i32 1
  store ptr %t221, ptr %t222
  %t223 = getelementptr ptr, ptr %t218, i32 0
  %t224 = load ptr, ptr %t223
  %t225 = ptrtoint ptr %t224 to i64
  switch i64 %t225, label %case.default.226 [ i64 0, label %case.arm.0.228 i64 1, label %case.arm.1.236 ]
case.arm.0.228:
  %t230 = getelementptr ptr, ptr %t218, i32 1
  %t231 = load ptr, ptr %t230
  %t232 = call ptr @malloc(i64 16)
  %t233 = inttoptr i64 0 to ptr
  %t234 = getelementptr ptr, ptr %t232, i32 0
  store ptr %t233, ptr %t234
  %t235 = getelementptr ptr, ptr %t232, i32 1
  store ptr %t231, ptr %t235
  br label %case.end.0.229
case.end.0.229:
  br label %case.join.227
case.arm.1.236:
  %t238 = getelementptr ptr, ptr %t218, i32 1
  %t239 = load ptr, ptr %t238
  %t240 = call ptr @malloc(i64 16)
  %t241 = inttoptr i64 1 to ptr
  %t242 = getelementptr ptr, ptr %t240, i32 0
  store ptr %t241, ptr %t242
  %t243 = getelementptr [3 x i8], ptr @.str.4, i64 0, i64 0
  %t244 = call ptr @__concat(ptr %t239, ptr %t243)
  %t245 = getelementptr ptr, ptr %t240, i32 1
  store ptr %t244, ptr %t245
  %t246 = getelementptr ptr, ptr %t240, i32 0
  %t247 = load ptr, ptr %t246
  %t248 = ptrtoint ptr %t247 to i64
  switch i64 %t248, label %case.default.249 [ i64 0, label %case.arm.0.251 i64 1, label %case.arm.1.259 ]
case.arm.0.251:
  %t253 = getelementptr ptr, ptr %t240, i32 1
  %t254 = load ptr, ptr %t253
  %t255 = call ptr @malloc(i64 16)
  %t256 = inttoptr i64 0 to ptr
  %t257 = getelementptr ptr, ptr %t255, i32 0
  store ptr %t256, ptr %t257
  %t258 = getelementptr ptr, ptr %t255, i32 1
  store ptr %t254, ptr %t258
  br label %case.end.0.252
case.end.0.252:
  br label %case.join.250
case.arm.1.259:
  %t261 = getelementptr ptr, ptr %t240, i32 1
  %t262 = load ptr, ptr %t261
  %t263 = call ptr @malloc(i64 16)
  %t264 = inttoptr i64 1 to ptr
  %t265 = getelementptr ptr, ptr %t263, i32 0
  store ptr %t264, ptr %t265
  %t266 = call ptr @__concat(ptr %t262, ptr %t104)
  %t267 = getelementptr ptr, ptr %t263, i32 1
  store ptr %t266, ptr %t267
  br label %case.end.1.260
case.end.1.260:
  br label %case.join.250
case.default.249:
  unreachable
case.join.250:
  %t268 = phi ptr [%t255, %case.end.0.252], [%t263, %case.end.1.260]
  br label %case.end.1.237
case.end.1.237:
  br label %case.join.227
case.default.226:
  unreachable
case.join.227:
  %t269 = phi ptr [%t232, %case.end.0.229], [%t268, %case.end.1.237]
  br label %case.end.1.215
case.end.1.215:
  br label %case.join.205
case.default.204:
  unreachable
case.join.205:
  %t270 = phi ptr [%t210, %case.end.0.207], [%t269, %case.end.1.215]
  br label %case.end.1.192
case.end.1.192:
  br label %case.join.182
case.default.181:
  unreachable
case.join.182:
  %t271 = phi ptr [%t187, %case.end.0.184], [%t270, %case.end.1.192]
  br label %case.end.1.170
case.end.1.170:
  br label %case.join.160
case.default.159:
  unreachable
case.join.160:
  %t272 = phi ptr [%t165, %case.end.0.162], [%t271, %case.end.1.170]
  br label %case.end.1.147
case.end.1.147:
  br label %case.join.137
case.default.136:
  unreachable
case.join.137:
  %t273 = phi ptr [%t142, %case.end.0.139], [%t272, %case.end.1.147]
  br label %case.end.1.125
case.end.1.125:
  br label %case.join.115
case.default.114:
  unreachable
case.join.115:
  %t274 = phi ptr [%t120, %case.end.0.117], [%t273, %case.end.1.125]
  br label %case.end.1.102
case.end.1.102:
  br label %case.join.92
case.default.91:
  unreachable
case.join.92:
  %t275 = phi ptr [%t97, %case.end.0.94], [%t274, %case.end.1.102]
  br label %case.end.1.81
case.end.1.81:
  br label %case.join.71
case.default.70:
  unreachable
case.join.71:
  %t276 = phi ptr [%t76, %case.end.0.73], [%t275, %case.end.1.81]
  br label %case.end.1.60
case.end.1.60:
  br label %case.join.50
case.default.49:
  unreachable
case.join.50:
  %t277 = phi ptr [%t55, %case.end.0.52], [%t276, %case.end.1.60]
  br label %case.end.1.39
case.end.1.39:
  br label %case.join.29
case.default.28:
  unreachable
case.join.29:
  %t278 = phi ptr [%t34, %case.end.0.31], [%t277, %case.end.1.39]
  br label %case.end.1.18
case.end.1.18:
  br label %case.join.8
case.default.7:
  unreachable
case.join.8:
  %t279 = phi ptr [%t13, %case.end.0.10], [%t278, %case.end.1.18]
  %t280 = call ptr @v__let_2(ptr %t279)
  ret ptr %t280
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
