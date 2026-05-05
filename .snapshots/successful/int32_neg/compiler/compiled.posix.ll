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
  ret ptr null
}


define internal ptr @__showInt32(ptr %p) {
  %v = load i32, ptr %p
  %buf = call ptr @malloc(i64 16)
  call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 16, ptr @.fmt_i32, i32 %v)
  ret ptr %buf
}


define internal ptr @__negInt32(ptr %p) {
  %v = load i32, ptr %p
  %is_min = icmp eq i32 %v, -2147483648
  br i1 %is_min, label %overflow, label %ok
overflow:
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
  %newv = sub i32 0, %v
  %box = call ptr @malloc(i64 4)
  store i32 %newv, ptr %box
  %right = call ptr @malloc(i64 16)
  %right_tag = inttoptr i64 1 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %box, ptr %right_f
  ret ptr %right
}


define internal ptr @v_showOverflowError(ptr %v__wild0) {
  %t0 = getelementptr [14 x i8], ptr @.str.0, i64 0, i64 0
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
  %t24 = call ptr @__showInt32(ptr %t19)
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
  store i32 5, ptr %t0
  %t1 = call ptr @__negInt32(ptr %t0)
  %t2 = call ptr @v_render(ptr %t1)
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
  %t20 = call ptr @malloc(i64 4)
  store i32 -5, ptr %t20
  %t21 = call ptr @__negInt32(ptr %t20)
  %t22 = call ptr @v_render(ptr %t21)
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
  %t40 = call ptr @malloc(i64 4)
  store i32 0, ptr %t40
  %t41 = call ptr @__negInt32(ptr %t40)
  %t42 = call ptr @v_render(ptr %t41)
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
  %t60 = call ptr @v_maxInt32()
  %t61 = call ptr @__negInt32(ptr %t60)
  %t62 = call ptr @v_render(ptr %t61)
  %t63 = getelementptr ptr, ptr %t62, i32 0
  %t64 = load ptr, ptr %t63
  %t65 = ptrtoint ptr %t64 to i64
  switch i64 %t65, label %case.default.66 [ i64 0, label %case.arm.0.68 i64 1, label %case.arm.1.76 ]
case.arm.0.68:
  %t70 = getelementptr ptr, ptr %t62, i32 1
  %t71 = load ptr, ptr %t70
  %t72 = call ptr @malloc(i64 16)
  %t73 = inttoptr i64 0 to ptr
  %t74 = getelementptr ptr, ptr %t72, i32 0
  store ptr %t73, ptr %t74
  %t75 = getelementptr ptr, ptr %t72, i32 1
  store ptr %t71, ptr %t75
  br label %case.end.0.69
case.end.0.69:
  br label %case.join.67
case.arm.1.76:
  %t78 = getelementptr ptr, ptr %t62, i32 1
  %t79 = load ptr, ptr %t78
  %t80 = call ptr @v_minInt32()
  %t81 = call ptr @__negInt32(ptr %t80)
  %t82 = call ptr @v_render(ptr %t81)
  %t83 = getelementptr ptr, ptr %t82, i32 0
  %t84 = load ptr, ptr %t83
  %t85 = ptrtoint ptr %t84 to i64
  switch i64 %t85, label %case.default.86 [ i64 0, label %case.arm.0.88 i64 1, label %case.arm.1.96 ]
case.arm.0.88:
  %t90 = getelementptr ptr, ptr %t82, i32 1
  %t91 = load ptr, ptr %t90
  %t92 = call ptr @malloc(i64 16)
  %t93 = inttoptr i64 0 to ptr
  %t94 = getelementptr ptr, ptr %t92, i32 0
  store ptr %t93, ptr %t94
  %t95 = getelementptr ptr, ptr %t92, i32 1
  store ptr %t91, ptr %t95
  br label %case.end.0.89
case.end.0.89:
  br label %case.join.87
case.arm.1.96:
  %t98 = getelementptr ptr, ptr %t82, i32 1
  %t99 = load ptr, ptr %t98
  %t100 = call ptr @malloc(i64 16)
  %t101 = inttoptr i64 1 to ptr
  %t102 = getelementptr ptr, ptr %t100, i32 0
  store ptr %t101, ptr %t102
  %t103 = getelementptr [3 x i8], ptr @.str.3, i64 0, i64 0
  %t104 = call ptr @__concat(ptr %t19, ptr %t103)
  %t105 = getelementptr ptr, ptr %t100, i32 1
  store ptr %t104, ptr %t105
  %t106 = getelementptr ptr, ptr %t100, i32 0
  %t107 = load ptr, ptr %t106
  %t108 = ptrtoint ptr %t107 to i64
  switch i64 %t108, label %case.default.109 [ i64 0, label %case.arm.0.111 i64 1, label %case.arm.1.119 ]
case.arm.0.111:
  %t113 = getelementptr ptr, ptr %t100, i32 1
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
  %t121 = getelementptr ptr, ptr %t100, i32 1
  %t122 = load ptr, ptr %t121
  %t123 = call ptr @malloc(i64 16)
  %t124 = inttoptr i64 1 to ptr
  %t125 = getelementptr ptr, ptr %t123, i32 0
  store ptr %t124, ptr %t125
  %t126 = call ptr @__concat(ptr %t122, ptr %t39)
  %t127 = getelementptr ptr, ptr %t123, i32 1
  store ptr %t126, ptr %t127
  %t128 = getelementptr ptr, ptr %t123, i32 0
  %t129 = load ptr, ptr %t128
  %t130 = ptrtoint ptr %t129 to i64
  switch i64 %t130, label %case.default.131 [ i64 0, label %case.arm.0.133 i64 1, label %case.arm.1.141 ]
case.arm.0.133:
  %t135 = getelementptr ptr, ptr %t123, i32 1
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
  %t143 = getelementptr ptr, ptr %t123, i32 1
  %t144 = load ptr, ptr %t143
  %t145 = call ptr @malloc(i64 16)
  %t146 = inttoptr i64 1 to ptr
  %t147 = getelementptr ptr, ptr %t145, i32 0
  store ptr %t146, ptr %t147
  %t148 = getelementptr [3 x i8], ptr @.str.3, i64 0, i64 0
  %t149 = call ptr @__concat(ptr %t144, ptr %t148)
  %t150 = getelementptr ptr, ptr %t145, i32 1
  store ptr %t149, ptr %t150
  %t151 = getelementptr ptr, ptr %t145, i32 0
  %t152 = load ptr, ptr %t151
  %t153 = ptrtoint ptr %t152 to i64
  switch i64 %t153, label %case.default.154 [ i64 0, label %case.arm.0.156 i64 1, label %case.arm.1.164 ]
case.arm.0.156:
  %t158 = getelementptr ptr, ptr %t145, i32 1
  %t159 = load ptr, ptr %t158
  %t160 = call ptr @malloc(i64 16)
  %t161 = inttoptr i64 0 to ptr
  %t162 = getelementptr ptr, ptr %t160, i32 0
  store ptr %t161, ptr %t162
  %t163 = getelementptr ptr, ptr %t160, i32 1
  store ptr %t159, ptr %t163
  br label %case.end.0.157
case.end.0.157:
  br label %case.join.155
case.arm.1.164:
  %t166 = getelementptr ptr, ptr %t145, i32 1
  %t167 = load ptr, ptr %t166
  %t168 = call ptr @malloc(i64 16)
  %t169 = inttoptr i64 1 to ptr
  %t170 = getelementptr ptr, ptr %t168, i32 0
  store ptr %t169, ptr %t170
  %t171 = call ptr @__concat(ptr %t167, ptr %t59)
  %t172 = getelementptr ptr, ptr %t168, i32 1
  store ptr %t171, ptr %t172
  %t173 = getelementptr ptr, ptr %t168, i32 0
  %t174 = load ptr, ptr %t173
  %t175 = ptrtoint ptr %t174 to i64
  switch i64 %t175, label %case.default.176 [ i64 0, label %case.arm.0.178 i64 1, label %case.arm.1.186 ]
case.arm.0.178:
  %t180 = getelementptr ptr, ptr %t168, i32 1
  %t181 = load ptr, ptr %t180
  %t182 = call ptr @malloc(i64 16)
  %t183 = inttoptr i64 0 to ptr
  %t184 = getelementptr ptr, ptr %t182, i32 0
  store ptr %t183, ptr %t184
  %t185 = getelementptr ptr, ptr %t182, i32 1
  store ptr %t181, ptr %t185
  br label %case.end.0.179
case.end.0.179:
  br label %case.join.177
case.arm.1.186:
  %t188 = getelementptr ptr, ptr %t168, i32 1
  %t189 = load ptr, ptr %t188
  %t190 = call ptr @malloc(i64 16)
  %t191 = inttoptr i64 1 to ptr
  %t192 = getelementptr ptr, ptr %t190, i32 0
  store ptr %t191, ptr %t192
  %t193 = getelementptr [3 x i8], ptr @.str.3, i64 0, i64 0
  %t194 = call ptr @__concat(ptr %t189, ptr %t193)
  %t195 = getelementptr ptr, ptr %t190, i32 1
  store ptr %t194, ptr %t195
  %t196 = getelementptr ptr, ptr %t190, i32 0
  %t197 = load ptr, ptr %t196
  %t198 = ptrtoint ptr %t197 to i64
  switch i64 %t198, label %case.default.199 [ i64 0, label %case.arm.0.201 i64 1, label %case.arm.1.209 ]
case.arm.0.201:
  %t203 = getelementptr ptr, ptr %t190, i32 1
  %t204 = load ptr, ptr %t203
  %t205 = call ptr @malloc(i64 16)
  %t206 = inttoptr i64 0 to ptr
  %t207 = getelementptr ptr, ptr %t205, i32 0
  store ptr %t206, ptr %t207
  %t208 = getelementptr ptr, ptr %t205, i32 1
  store ptr %t204, ptr %t208
  br label %case.end.0.202
case.end.0.202:
  br label %case.join.200
case.arm.1.209:
  %t211 = getelementptr ptr, ptr %t190, i32 1
  %t212 = load ptr, ptr %t211
  %t213 = call ptr @malloc(i64 16)
  %t214 = inttoptr i64 1 to ptr
  %t215 = getelementptr ptr, ptr %t213, i32 0
  store ptr %t214, ptr %t215
  %t216 = call ptr @__concat(ptr %t212, ptr %t79)
  %t217 = getelementptr ptr, ptr %t213, i32 1
  store ptr %t216, ptr %t217
  %t218 = getelementptr ptr, ptr %t213, i32 0
  %t219 = load ptr, ptr %t218
  %t220 = ptrtoint ptr %t219 to i64
  switch i64 %t220, label %case.default.221 [ i64 0, label %case.arm.0.223 i64 1, label %case.arm.1.231 ]
case.arm.0.223:
  %t225 = getelementptr ptr, ptr %t213, i32 1
  %t226 = load ptr, ptr %t225
  %t227 = call ptr @malloc(i64 16)
  %t228 = inttoptr i64 0 to ptr
  %t229 = getelementptr ptr, ptr %t227, i32 0
  store ptr %t228, ptr %t229
  %t230 = getelementptr ptr, ptr %t227, i32 1
  store ptr %t226, ptr %t230
  br label %case.end.0.224
case.end.0.224:
  br label %case.join.222
case.arm.1.231:
  %t233 = getelementptr ptr, ptr %t213, i32 1
  %t234 = load ptr, ptr %t233
  %t235 = call ptr @malloc(i64 16)
  %t236 = inttoptr i64 1 to ptr
  %t237 = getelementptr ptr, ptr %t235, i32 0
  store ptr %t236, ptr %t237
  %t238 = getelementptr [3 x i8], ptr @.str.3, i64 0, i64 0
  %t239 = call ptr @__concat(ptr %t234, ptr %t238)
  %t240 = getelementptr ptr, ptr %t235, i32 1
  store ptr %t239, ptr %t240
  %t241 = getelementptr ptr, ptr %t235, i32 0
  %t242 = load ptr, ptr %t241
  %t243 = ptrtoint ptr %t242 to i64
  switch i64 %t243, label %case.default.244 [ i64 0, label %case.arm.0.246 i64 1, label %case.arm.1.254 ]
case.arm.0.246:
  %t248 = getelementptr ptr, ptr %t235, i32 1
  %t249 = load ptr, ptr %t248
  %t250 = call ptr @malloc(i64 16)
  %t251 = inttoptr i64 0 to ptr
  %t252 = getelementptr ptr, ptr %t250, i32 0
  store ptr %t251, ptr %t252
  %t253 = getelementptr ptr, ptr %t250, i32 1
  store ptr %t249, ptr %t253
  br label %case.end.0.247
case.end.0.247:
  br label %case.join.245
case.arm.1.254:
  %t256 = getelementptr ptr, ptr %t235, i32 1
  %t257 = load ptr, ptr %t256
  %t258 = call ptr @malloc(i64 16)
  %t259 = inttoptr i64 1 to ptr
  %t260 = getelementptr ptr, ptr %t258, i32 0
  store ptr %t259, ptr %t260
  %t261 = call ptr @__concat(ptr %t257, ptr %t99)
  %t262 = getelementptr ptr, ptr %t258, i32 1
  store ptr %t261, ptr %t262
  br label %case.end.1.255
case.end.1.255:
  br label %case.join.245
case.default.244:
  unreachable
case.join.245:
  %t263 = phi ptr [%t250, %case.end.0.247], [%t258, %case.end.1.255]
  br label %case.end.1.232
case.end.1.232:
  br label %case.join.222
case.default.221:
  unreachable
case.join.222:
  %t264 = phi ptr [%t227, %case.end.0.224], [%t263, %case.end.1.232]
  br label %case.end.1.210
case.end.1.210:
  br label %case.join.200
case.default.199:
  unreachable
case.join.200:
  %t265 = phi ptr [%t205, %case.end.0.202], [%t264, %case.end.1.210]
  br label %case.end.1.187
case.end.1.187:
  br label %case.join.177
case.default.176:
  unreachable
case.join.177:
  %t266 = phi ptr [%t182, %case.end.0.179], [%t265, %case.end.1.187]
  br label %case.end.1.165
case.end.1.165:
  br label %case.join.155
case.default.154:
  unreachable
case.join.155:
  %t267 = phi ptr [%t160, %case.end.0.157], [%t266, %case.end.1.165]
  br label %case.end.1.142
case.end.1.142:
  br label %case.join.132
case.default.131:
  unreachable
case.join.132:
  %t268 = phi ptr [%t137, %case.end.0.134], [%t267, %case.end.1.142]
  br label %case.end.1.120
case.end.1.120:
  br label %case.join.110
case.default.109:
  unreachable
case.join.110:
  %t269 = phi ptr [%t115, %case.end.0.112], [%t268, %case.end.1.120]
  br label %case.end.1.97
case.end.1.97:
  br label %case.join.87
case.default.86:
  unreachable
case.join.87:
  %t270 = phi ptr [%t92, %case.end.0.89], [%t269, %case.end.1.97]
  br label %case.end.1.77
case.end.1.77:
  br label %case.join.67
case.default.66:
  unreachable
case.join.67:
  %t271 = phi ptr [%t72, %case.end.0.69], [%t270, %case.end.1.77]
  br label %case.end.1.57
case.end.1.57:
  br label %case.join.47
case.default.46:
  unreachable
case.join.47:
  %t272 = phi ptr [%t52, %case.end.0.49], [%t271, %case.end.1.57]
  br label %case.end.1.37
case.end.1.37:
  br label %case.join.27
case.default.26:
  unreachable
case.join.27:
  %t273 = phi ptr [%t32, %case.end.0.29], [%t272, %case.end.1.37]
  br label %case.end.1.17
case.end.1.17:
  br label %case.join.7
case.default.6:
  unreachable
case.join.7:
  %t274 = phi ptr [%t12, %case.end.0.9], [%t273, %case.end.1.17]
  %t275 = call ptr @v__let_1(ptr %t274)
  ret ptr %t275
}

define internal ptr @v__let_1(ptr %v_res) {
  %t0 = getelementptr ptr, ptr %v_res, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.11 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_res, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr [16 x i8], ptr @.str.4, i64 0, i64 0
  %t10 = call ptr @__print(ptr %t9)
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.11:
  %t13 = getelementptr ptr, ptr %v_res, i32 1
  %t14 = load ptr, ptr %t13
  %t15 = call ptr @__print(ptr %t14)
  br label %case.end.1.12
case.end.1.12:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t16 = phi ptr [%t10, %case.end.0.6], [%t15, %case.end.1.12]
  ret ptr %t16
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
  call ptr @v_main(ptr %right_box)
  ret i32 0
}
