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

@.str.0 = private unnamed_addr constant [14 x i8] c"OverflowError\00"
@.str.1 = private unnamed_addr constant [11 x i8] c"overflow: \00"
@.str.2 = private unnamed_addr constant [5 x i8] c"ok: \00"
@.str.3 = private unnamed_addr constant [3 x i8] c", \00"
@.str.4 = private unnamed_addr constant [16 x i8] c"STRING_TOO_LONG\00"

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


define internal ptr @__mulUInt32(ptr %pa, ptr %pb) {
  %a = load i32, ptr %pa
  %b = load i32, ptr %pb
  %a64 = zext i32 %a to i64
  %b64 = zext i32 %b to i64
  %prod64 = mul i64 %a64, %b64
  %ovf = icmp ugt i64 %prod64, 4294967295
  br i1 %ovf, label %err, label %ok
err:
  %oe = call ptr @malloc(i64 8)
  %oe_tag = inttoptr i64 0 to ptr
  store ptr %oe_tag, ptr %oe
  %left = call ptr @malloc(i64 16)
  %left_tag = inttoptr i64 0 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %oe, ptr %left_f
  ret ptr %left
ok:
  %newv = trunc i64 %prod64 to i32
  %box = call ptr @malloc(i64 4)
  store i32 %newv, ptr %box
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

define internal ptr @v_showOverflowError(ptr %v__wild0) {
  %t0 = getelementptr [14 x i8], ptr @.str.0, i64 0, i64 0
  ret ptr %t0
}

define internal ptr @v_minUInt32() {
  %t0 = call ptr @malloc(i64 4)
  store i32 0, ptr %t0
  ret ptr %t0
}

define internal ptr @v_maxUInt32() {
  %t0 = call ptr @malloc(i64 4)
  store i32 -1, ptr %t0
  ret ptr %t0
}

define internal ptr @v_render(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.16 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_r, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = call ptr @malloc(i64 16)
  %t10 = inttoptr i64 1 to ptr
  %t11 = getelementptr ptr, ptr %t9, i32 0
  store ptr %t10, ptr %t11
  %t12 = getelementptr [11 x i8], ptr @.str.1, i64 0, i64 0
  %t13 = call ptr @v_showOverflowError(ptr %t8)
  %t14 = call ptr @__concat(ptr %t12, ptr %t13)
  %t15 = getelementptr ptr, ptr %t9, i32 1
  store ptr %t14, ptr %t15
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.16:
  %t18 = getelementptr ptr, ptr %v_r, i32 1
  %t19 = load ptr, ptr %t18
  %t20 = call ptr @malloc(i64 16)
  %t21 = inttoptr i64 1 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = getelementptr [5 x i8], ptr @.str.2, i64 0, i64 0
  %t24 = call ptr @__showUInt32(ptr %t19)
  %t25 = call ptr @__concat(ptr %t23, ptr %t24)
  %t26 = getelementptr ptr, ptr %t20, i32 1
  store ptr %t25, ptr %t26
  br label %case.end.1.17
case.end.1.17:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t27 = phi ptr [%t9, %case.end.0.6], [%t20, %case.end.1.17]
  ret ptr %t27
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 4)
  store i32 65535, ptr %t0
  %t1 = call ptr @malloc(i64 4)
  store i32 65537, ptr %t1
  %t2 = call ptr @__mulUInt32(ptr %t0, ptr %t1)
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
  store i32 65536, ptr %t21
  %t22 = call ptr @malloc(i64 4)
  store i32 65536, ptr %t22
  %t23 = call ptr @__mulUInt32(ptr %t21, ptr %t22)
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
  %t42 = call ptr @v_maxUInt32()
  %t43 = call ptr @v_maxUInt32()
  %t44 = call ptr @__mulUInt32(ptr %t42, ptr %t43)
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
  %t63 = call ptr @v_minUInt32()
  %t64 = call ptr @v_maxUInt32()
  %t65 = call ptr @__mulUInt32(ptr %t63, ptr %t64)
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
  store i32 1, ptr %t84
  %t85 = call ptr @malloc(i64 4)
  store i32 -2147483648, ptr %t85
  %t86 = call ptr @__mulUInt32(ptr %t84, ptr %t85)
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
  %t105 = call ptr @malloc(i64 4)
  store i32 2, ptr %t105
  %t106 = call ptr @malloc(i64 4)
  store i32 -2147483648, ptr %t106
  %t107 = call ptr @__mulUInt32(ptr %t105, ptr %t106)
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
  %t126 = call ptr @malloc(i64 16)
  %t127 = inttoptr i64 1 to ptr
  %t128 = getelementptr ptr, ptr %t126, i32 0
  store ptr %t127, ptr %t128
  %t129 = getelementptr [3 x i8], ptr @.str.3, i64 0, i64 0
  %t130 = call ptr @__concat(ptr %t20, ptr %t129)
  %t131 = getelementptr ptr, ptr %t126, i32 1
  store ptr %t130, ptr %t131
  %t132 = getelementptr ptr, ptr %t126, i32 0
  %t133 = load ptr, ptr %t132
  %t134 = ptrtoint ptr %t133 to i64
  switch i64 %t134, label %case.default.135 [ i64 0, label %case.arm.0.137 i64 1, label %case.arm.1.145 ]
case.arm.0.137:
  %t139 = getelementptr ptr, ptr %t126, i32 1
  %t140 = load ptr, ptr %t139
  %t141 = call ptr @malloc(i64 16)
  %t142 = inttoptr i64 0 to ptr
  %t143 = getelementptr ptr, ptr %t141, i32 0
  store ptr %t142, ptr %t143
  %t144 = getelementptr ptr, ptr %t141, i32 1
  store ptr %t140, ptr %t144
  br label %case.end.0.138
case.end.0.138:
  br label %case.join.136
case.arm.1.145:
  %t147 = getelementptr ptr, ptr %t126, i32 1
  %t148 = load ptr, ptr %t147
  %t149 = call ptr @malloc(i64 16)
  %t150 = inttoptr i64 1 to ptr
  %t151 = getelementptr ptr, ptr %t149, i32 0
  store ptr %t150, ptr %t151
  %t152 = call ptr @__concat(ptr %t148, ptr %t41)
  %t153 = getelementptr ptr, ptr %t149, i32 1
  store ptr %t152, ptr %t153
  %t154 = getelementptr ptr, ptr %t149, i32 0
  %t155 = load ptr, ptr %t154
  %t156 = ptrtoint ptr %t155 to i64
  switch i64 %t156, label %case.default.157 [ i64 0, label %case.arm.0.159 i64 1, label %case.arm.1.167 ]
case.arm.0.159:
  %t161 = getelementptr ptr, ptr %t149, i32 1
  %t162 = load ptr, ptr %t161
  %t163 = call ptr @malloc(i64 16)
  %t164 = inttoptr i64 0 to ptr
  %t165 = getelementptr ptr, ptr %t163, i32 0
  store ptr %t164, ptr %t165
  %t166 = getelementptr ptr, ptr %t163, i32 1
  store ptr %t162, ptr %t166
  br label %case.end.0.160
case.end.0.160:
  br label %case.join.158
case.arm.1.167:
  %t169 = getelementptr ptr, ptr %t149, i32 1
  %t170 = load ptr, ptr %t169
  %t171 = call ptr @malloc(i64 16)
  %t172 = inttoptr i64 1 to ptr
  %t173 = getelementptr ptr, ptr %t171, i32 0
  store ptr %t172, ptr %t173
  %t174 = getelementptr [3 x i8], ptr @.str.3, i64 0, i64 0
  %t175 = call ptr @__concat(ptr %t170, ptr %t174)
  %t176 = getelementptr ptr, ptr %t171, i32 1
  store ptr %t175, ptr %t176
  %t177 = getelementptr ptr, ptr %t171, i32 0
  %t178 = load ptr, ptr %t177
  %t179 = ptrtoint ptr %t178 to i64
  switch i64 %t179, label %case.default.180 [ i64 0, label %case.arm.0.182 i64 1, label %case.arm.1.190 ]
case.arm.0.182:
  %t184 = getelementptr ptr, ptr %t171, i32 1
  %t185 = load ptr, ptr %t184
  %t186 = call ptr @malloc(i64 16)
  %t187 = inttoptr i64 0 to ptr
  %t188 = getelementptr ptr, ptr %t186, i32 0
  store ptr %t187, ptr %t188
  %t189 = getelementptr ptr, ptr %t186, i32 1
  store ptr %t185, ptr %t189
  br label %case.end.0.183
case.end.0.183:
  br label %case.join.181
case.arm.1.190:
  %t192 = getelementptr ptr, ptr %t171, i32 1
  %t193 = load ptr, ptr %t192
  %t194 = call ptr @malloc(i64 16)
  %t195 = inttoptr i64 1 to ptr
  %t196 = getelementptr ptr, ptr %t194, i32 0
  store ptr %t195, ptr %t196
  %t197 = call ptr @__concat(ptr %t193, ptr %t62)
  %t198 = getelementptr ptr, ptr %t194, i32 1
  store ptr %t197, ptr %t198
  %t199 = getelementptr ptr, ptr %t194, i32 0
  %t200 = load ptr, ptr %t199
  %t201 = ptrtoint ptr %t200 to i64
  switch i64 %t201, label %case.default.202 [ i64 0, label %case.arm.0.204 i64 1, label %case.arm.1.212 ]
case.arm.0.204:
  %t206 = getelementptr ptr, ptr %t194, i32 1
  %t207 = load ptr, ptr %t206
  %t208 = call ptr @malloc(i64 16)
  %t209 = inttoptr i64 0 to ptr
  %t210 = getelementptr ptr, ptr %t208, i32 0
  store ptr %t209, ptr %t210
  %t211 = getelementptr ptr, ptr %t208, i32 1
  store ptr %t207, ptr %t211
  br label %case.end.0.205
case.end.0.205:
  br label %case.join.203
case.arm.1.212:
  %t214 = getelementptr ptr, ptr %t194, i32 1
  %t215 = load ptr, ptr %t214
  %t216 = call ptr @malloc(i64 16)
  %t217 = inttoptr i64 1 to ptr
  %t218 = getelementptr ptr, ptr %t216, i32 0
  store ptr %t217, ptr %t218
  %t219 = getelementptr [3 x i8], ptr @.str.3, i64 0, i64 0
  %t220 = call ptr @__concat(ptr %t215, ptr %t219)
  %t221 = getelementptr ptr, ptr %t216, i32 1
  store ptr %t220, ptr %t221
  %t222 = getelementptr ptr, ptr %t216, i32 0
  %t223 = load ptr, ptr %t222
  %t224 = ptrtoint ptr %t223 to i64
  switch i64 %t224, label %case.default.225 [ i64 0, label %case.arm.0.227 i64 1, label %case.arm.1.235 ]
case.arm.0.227:
  %t229 = getelementptr ptr, ptr %t216, i32 1
  %t230 = load ptr, ptr %t229
  %t231 = call ptr @malloc(i64 16)
  %t232 = inttoptr i64 0 to ptr
  %t233 = getelementptr ptr, ptr %t231, i32 0
  store ptr %t232, ptr %t233
  %t234 = getelementptr ptr, ptr %t231, i32 1
  store ptr %t230, ptr %t234
  br label %case.end.0.228
case.end.0.228:
  br label %case.join.226
case.arm.1.235:
  %t237 = getelementptr ptr, ptr %t216, i32 1
  %t238 = load ptr, ptr %t237
  %t239 = call ptr @malloc(i64 16)
  %t240 = inttoptr i64 1 to ptr
  %t241 = getelementptr ptr, ptr %t239, i32 0
  store ptr %t240, ptr %t241
  %t242 = call ptr @__concat(ptr %t238, ptr %t83)
  %t243 = getelementptr ptr, ptr %t239, i32 1
  store ptr %t242, ptr %t243
  %t244 = getelementptr ptr, ptr %t239, i32 0
  %t245 = load ptr, ptr %t244
  %t246 = ptrtoint ptr %t245 to i64
  switch i64 %t246, label %case.default.247 [ i64 0, label %case.arm.0.249 i64 1, label %case.arm.1.257 ]
case.arm.0.249:
  %t251 = getelementptr ptr, ptr %t239, i32 1
  %t252 = load ptr, ptr %t251
  %t253 = call ptr @malloc(i64 16)
  %t254 = inttoptr i64 0 to ptr
  %t255 = getelementptr ptr, ptr %t253, i32 0
  store ptr %t254, ptr %t255
  %t256 = getelementptr ptr, ptr %t253, i32 1
  store ptr %t252, ptr %t256
  br label %case.end.0.250
case.end.0.250:
  br label %case.join.248
case.arm.1.257:
  %t259 = getelementptr ptr, ptr %t239, i32 1
  %t260 = load ptr, ptr %t259
  %t261 = call ptr @malloc(i64 16)
  %t262 = inttoptr i64 1 to ptr
  %t263 = getelementptr ptr, ptr %t261, i32 0
  store ptr %t262, ptr %t263
  %t264 = getelementptr [3 x i8], ptr @.str.3, i64 0, i64 0
  %t265 = call ptr @__concat(ptr %t260, ptr %t264)
  %t266 = getelementptr ptr, ptr %t261, i32 1
  store ptr %t265, ptr %t266
  %t267 = getelementptr ptr, ptr %t261, i32 0
  %t268 = load ptr, ptr %t267
  %t269 = ptrtoint ptr %t268 to i64
  switch i64 %t269, label %case.default.270 [ i64 0, label %case.arm.0.272 i64 1, label %case.arm.1.280 ]
case.arm.0.272:
  %t274 = getelementptr ptr, ptr %t261, i32 1
  %t275 = load ptr, ptr %t274
  %t276 = call ptr @malloc(i64 16)
  %t277 = inttoptr i64 0 to ptr
  %t278 = getelementptr ptr, ptr %t276, i32 0
  store ptr %t277, ptr %t278
  %t279 = getelementptr ptr, ptr %t276, i32 1
  store ptr %t275, ptr %t279
  br label %case.end.0.273
case.end.0.273:
  br label %case.join.271
case.arm.1.280:
  %t282 = getelementptr ptr, ptr %t261, i32 1
  %t283 = load ptr, ptr %t282
  %t284 = call ptr @malloc(i64 16)
  %t285 = inttoptr i64 1 to ptr
  %t286 = getelementptr ptr, ptr %t284, i32 0
  store ptr %t285, ptr %t286
  %t287 = call ptr @__concat(ptr %t283, ptr %t104)
  %t288 = getelementptr ptr, ptr %t284, i32 1
  store ptr %t287, ptr %t288
  %t289 = getelementptr ptr, ptr %t284, i32 0
  %t290 = load ptr, ptr %t289
  %t291 = ptrtoint ptr %t290 to i64
  switch i64 %t291, label %case.default.292 [ i64 0, label %case.arm.0.294 i64 1, label %case.arm.1.302 ]
case.arm.0.294:
  %t296 = getelementptr ptr, ptr %t284, i32 1
  %t297 = load ptr, ptr %t296
  %t298 = call ptr @malloc(i64 16)
  %t299 = inttoptr i64 0 to ptr
  %t300 = getelementptr ptr, ptr %t298, i32 0
  store ptr %t299, ptr %t300
  %t301 = getelementptr ptr, ptr %t298, i32 1
  store ptr %t297, ptr %t301
  br label %case.end.0.295
case.end.0.295:
  br label %case.join.293
case.arm.1.302:
  %t304 = getelementptr ptr, ptr %t284, i32 1
  %t305 = load ptr, ptr %t304
  %t306 = call ptr @malloc(i64 16)
  %t307 = inttoptr i64 1 to ptr
  %t308 = getelementptr ptr, ptr %t306, i32 0
  store ptr %t307, ptr %t308
  %t309 = getelementptr [3 x i8], ptr @.str.3, i64 0, i64 0
  %t310 = call ptr @__concat(ptr %t305, ptr %t309)
  %t311 = getelementptr ptr, ptr %t306, i32 1
  store ptr %t310, ptr %t311
  %t312 = getelementptr ptr, ptr %t306, i32 0
  %t313 = load ptr, ptr %t312
  %t314 = ptrtoint ptr %t313 to i64
  switch i64 %t314, label %case.default.315 [ i64 0, label %case.arm.0.317 i64 1, label %case.arm.1.325 ]
case.arm.0.317:
  %t319 = getelementptr ptr, ptr %t306, i32 1
  %t320 = load ptr, ptr %t319
  %t321 = call ptr @malloc(i64 16)
  %t322 = inttoptr i64 0 to ptr
  %t323 = getelementptr ptr, ptr %t321, i32 0
  store ptr %t322, ptr %t323
  %t324 = getelementptr ptr, ptr %t321, i32 1
  store ptr %t320, ptr %t324
  br label %case.end.0.318
case.end.0.318:
  br label %case.join.316
case.arm.1.325:
  %t327 = getelementptr ptr, ptr %t306, i32 1
  %t328 = load ptr, ptr %t327
  %t329 = call ptr @malloc(i64 16)
  %t330 = inttoptr i64 1 to ptr
  %t331 = getelementptr ptr, ptr %t329, i32 0
  store ptr %t330, ptr %t331
  %t332 = call ptr @__concat(ptr %t328, ptr %t125)
  %t333 = getelementptr ptr, ptr %t329, i32 1
  store ptr %t332, ptr %t333
  br label %case.end.1.326
case.end.1.326:
  br label %case.join.316
case.default.315:
  unreachable
case.join.316:
  %t334 = phi ptr [%t321, %case.end.0.318], [%t329, %case.end.1.326]
  br label %case.end.1.303
case.end.1.303:
  br label %case.join.293
case.default.292:
  unreachable
case.join.293:
  %t335 = phi ptr [%t298, %case.end.0.295], [%t334, %case.end.1.303]
  br label %case.end.1.281
case.end.1.281:
  br label %case.join.271
case.default.270:
  unreachable
case.join.271:
  %t336 = phi ptr [%t276, %case.end.0.273], [%t335, %case.end.1.281]
  br label %case.end.1.258
case.end.1.258:
  br label %case.join.248
case.default.247:
  unreachable
case.join.248:
  %t337 = phi ptr [%t253, %case.end.0.250], [%t336, %case.end.1.258]
  br label %case.end.1.236
case.end.1.236:
  br label %case.join.226
case.default.225:
  unreachable
case.join.226:
  %t338 = phi ptr [%t231, %case.end.0.228], [%t337, %case.end.1.236]
  br label %case.end.1.213
case.end.1.213:
  br label %case.join.203
case.default.202:
  unreachable
case.join.203:
  %t339 = phi ptr [%t208, %case.end.0.205], [%t338, %case.end.1.213]
  br label %case.end.1.191
case.end.1.191:
  br label %case.join.181
case.default.180:
  unreachable
case.join.181:
  %t340 = phi ptr [%t186, %case.end.0.183], [%t339, %case.end.1.191]
  br label %case.end.1.168
case.end.1.168:
  br label %case.join.158
case.default.157:
  unreachable
case.join.158:
  %t341 = phi ptr [%t163, %case.end.0.160], [%t340, %case.end.1.168]
  br label %case.end.1.146
case.end.1.146:
  br label %case.join.136
case.default.135:
  unreachable
case.join.136:
  %t342 = phi ptr [%t141, %case.end.0.138], [%t341, %case.end.1.146]
  br label %case.end.1.123
case.end.1.123:
  br label %case.join.113
case.default.112:
  unreachable
case.join.113:
  %t343 = phi ptr [%t118, %case.end.0.115], [%t342, %case.end.1.123]
  br label %case.end.1.102
case.end.1.102:
  br label %case.join.92
case.default.91:
  unreachable
case.join.92:
  %t344 = phi ptr [%t97, %case.end.0.94], [%t343, %case.end.1.102]
  br label %case.end.1.81
case.end.1.81:
  br label %case.join.71
case.default.70:
  unreachable
case.join.71:
  %t345 = phi ptr [%t76, %case.end.0.73], [%t344, %case.end.1.81]
  br label %case.end.1.60
case.end.1.60:
  br label %case.join.50
case.default.49:
  unreachable
case.join.50:
  %t346 = phi ptr [%t55, %case.end.0.52], [%t345, %case.end.1.60]
  br label %case.end.1.39
case.end.1.39:
  br label %case.join.29
case.default.28:
  unreachable
case.join.29:
  %t347 = phi ptr [%t34, %case.end.0.31], [%t346, %case.end.1.39]
  br label %case.end.1.18
case.end.1.18:
  br label %case.join.8
case.default.7:
  unreachable
case.join.8:
  %t348 = phi ptr [%t13, %case.end.0.10], [%t347, %case.end.1.18]
  %t349 = call ptr @v__let_2(ptr %t348)
  ret ptr %t349
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
  %t12 = getelementptr [16 x i8], ptr @.str.4, i64 0, i64 0
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
