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

@.str.0 = private unnamed_addr constant [4 x i8] c"err\00"
@.str.1 = private unnamed_addr constant [4 x i8] c"ok:\00"
@.str.2 = private unnamed_addr constant [2 x i8] c"0\00"
@.str.3 = private unnamed_addr constant [4 x i8] c"255\00"
@.str.4 = private unnamed_addr constant [4 x i8] c"256\00"
@.str.5 = private unnamed_addr constant [3 x i8] c"-1\00"
@.str.6 = private unnamed_addr constant [1 x i8] c"\00"
@.str.7 = private unnamed_addr constant [4 x i8] c"abc\00"
@.str.8 = private unnamed_addr constant [3 x i8] c" 5\00"
@.str.9 = private unnamed_addr constant [4 x i8] c"12a\00"
@.str.10 = private unnamed_addr constant [3 x i8] c", \00"
@.str.11 = private unnamed_addr constant [16 x i8] c"STRING_TOO_LONG\00"

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


define internal ptr @__showUInt8(ptr %p) {
  %b = load i8, ptr %p
  %v = zext i8 %b to i32
  %buf = call ptr @malloc(i64 16)
  call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 16, ptr @.fmt_u8, i32 %v)
  ret ptr %buf
}


define internal ptr @__parseUInt8(ptr %s) {
entry:
  %i_alloca = alloca i64, align 8
  store i64 0, ptr %i_alloca
  %acc_alloca = alloca i32, align 4
  store i32 0, ptr %acc_alloca
  %len = call i64 @strlen(ptr %s)
  %is_empty = icmp eq i64 %len, 0
  br i1 %is_empty, label %fail, label %loop_head
loop_head:
  %i = load i64, ptr %i_alloca
  %acc = load i32, ptr %acc_alloca
  %cond = icmp ult i64 %i, %len
  br i1 %cond, label %body, label %ok
body:
  %ptr_c = getelementptr i8, ptr %s, i64 %i
  %c = load i8, ptr %ptr_c
  %c_i32 = zext i8 %c to i32
  %low = icmp ult i32 %c_i32, 48
  %high = icmp ugt i32 %c_i32, 57
  %bad = or i1 %low, %high
  br i1 %bad, label %fail, label %parse
parse:
  %d = sub i32 %c_i32, 48
  %x10 = mul i32 %acc, 10
  %acc_next = add i32 %x10, %d
  %big = icmp ugt i32 %acc_next, 255
  br i1 %big, label %fail, label %body_end
body_end:
  store i32 %acc_next, ptr %acc_alloca
  %i_next = add i64 %i, 1
  store i64 %i_next, ptr %i_alloca
  br label %loop_head
ok:
  %result_i8 = trunc i32 %acc to i8
  %box = call ptr @malloc(i64 1)
  store i8 %result_i8, ptr %box
  %right = call ptr @malloc(i64 16)
  %right_tag = inttoptr i64 1 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %box, ptr %right_f
  ret ptr %right
fail:
  %pe = call ptr @malloc(i64 8)
  %pe_tag = inttoptr i64 0 to ptr
  store ptr %pe_tag, ptr %pe
  %left = call ptr @malloc(i64 16)
  %left_tag = inttoptr i64 0 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %pe, ptr %left_f
  ret ptr %left
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

define internal ptr @v_render(ptr %v_r) {
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
  %t12 = getelementptr [4 x i8], ptr @.str.0, i64 0, i64 0
  %t13 = getelementptr ptr, ptr %t9, i32 1
  store ptr %t12, ptr %t13
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.14:
  %t16 = getelementptr ptr, ptr %v_r, i32 1
  %t17 = load ptr, ptr %t16
  %t18 = call ptr @malloc(i64 16)
  %t19 = inttoptr i64 1 to ptr
  %t20 = getelementptr ptr, ptr %t18, i32 0
  store ptr %t19, ptr %t20
  %t21 = getelementptr [4 x i8], ptr @.str.1, i64 0, i64 0
  %t22 = call ptr @__showUInt8(ptr %t17)
  %t23 = call ptr @__concat(ptr %t21, ptr %t22)
  %t24 = getelementptr ptr, ptr %t18, i32 1
  store ptr %t23, ptr %t24
  br label %case.end.1.15
case.end.1.15:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t25 = phi ptr [%t9, %case.end.0.6], [%t18, %case.end.1.15]
  ret ptr %t25
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = getelementptr [2 x i8], ptr @.str.2, i64 0, i64 0
  %t1 = call ptr @__parseUInt8(ptr %t0)
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
  %t20 = getelementptr [4 x i8], ptr @.str.3, i64 0, i64 0
  %t21 = call ptr @__parseUInt8(ptr %t20)
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
  %t40 = getelementptr [4 x i8], ptr @.str.4, i64 0, i64 0
  %t41 = call ptr @__parseUInt8(ptr %t40)
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
  %t60 = getelementptr [3 x i8], ptr @.str.5, i64 0, i64 0
  %t61 = call ptr @__parseUInt8(ptr %t60)
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
  %t80 = getelementptr [1 x i8], ptr @.str.6, i64 0, i64 0
  %t81 = call ptr @__parseUInt8(ptr %t80)
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
  %t100 = getelementptr [4 x i8], ptr @.str.7, i64 0, i64 0
  %t101 = call ptr @__parseUInt8(ptr %t100)
  %t102 = call ptr @v_render(ptr %t101)
  %t103 = getelementptr ptr, ptr %t102, i32 0
  %t104 = load ptr, ptr %t103
  %t105 = ptrtoint ptr %t104 to i64
  switch i64 %t105, label %case.default.106 [ i64 0, label %case.arm.0.108 i64 1, label %case.arm.1.116 ]
case.arm.0.108:
  %t110 = getelementptr ptr, ptr %t102, i32 1
  %t111 = load ptr, ptr %t110
  %t112 = call ptr @malloc(i64 16)
  %t113 = inttoptr i64 0 to ptr
  %t114 = getelementptr ptr, ptr %t112, i32 0
  store ptr %t113, ptr %t114
  %t115 = getelementptr ptr, ptr %t112, i32 1
  store ptr %t111, ptr %t115
  br label %case.end.0.109
case.end.0.109:
  br label %case.join.107
case.arm.1.116:
  %t118 = getelementptr ptr, ptr %t102, i32 1
  %t119 = load ptr, ptr %t118
  %t120 = getelementptr [3 x i8], ptr @.str.8, i64 0, i64 0
  %t121 = call ptr @__parseUInt8(ptr %t120)
  %t122 = call ptr @v_render(ptr %t121)
  %t123 = getelementptr ptr, ptr %t122, i32 0
  %t124 = load ptr, ptr %t123
  %t125 = ptrtoint ptr %t124 to i64
  switch i64 %t125, label %case.default.126 [ i64 0, label %case.arm.0.128 i64 1, label %case.arm.1.136 ]
case.arm.0.128:
  %t130 = getelementptr ptr, ptr %t122, i32 1
  %t131 = load ptr, ptr %t130
  %t132 = call ptr @malloc(i64 16)
  %t133 = inttoptr i64 0 to ptr
  %t134 = getelementptr ptr, ptr %t132, i32 0
  store ptr %t133, ptr %t134
  %t135 = getelementptr ptr, ptr %t132, i32 1
  store ptr %t131, ptr %t135
  br label %case.end.0.129
case.end.0.129:
  br label %case.join.127
case.arm.1.136:
  %t138 = getelementptr ptr, ptr %t122, i32 1
  %t139 = load ptr, ptr %t138
  %t140 = getelementptr [4 x i8], ptr @.str.9, i64 0, i64 0
  %t141 = call ptr @__parseUInt8(ptr %t140)
  %t142 = call ptr @v_render(ptr %t141)
  %t143 = getelementptr ptr, ptr %t142, i32 0
  %t144 = load ptr, ptr %t143
  %t145 = ptrtoint ptr %t144 to i64
  switch i64 %t145, label %case.default.146 [ i64 0, label %case.arm.0.148 i64 1, label %case.arm.1.156 ]
case.arm.0.148:
  %t150 = getelementptr ptr, ptr %t142, i32 1
  %t151 = load ptr, ptr %t150
  %t152 = call ptr @malloc(i64 16)
  %t153 = inttoptr i64 0 to ptr
  %t154 = getelementptr ptr, ptr %t152, i32 0
  store ptr %t153, ptr %t154
  %t155 = getelementptr ptr, ptr %t152, i32 1
  store ptr %t151, ptr %t155
  br label %case.end.0.149
case.end.0.149:
  br label %case.join.147
case.arm.1.156:
  %t158 = getelementptr ptr, ptr %t142, i32 1
  %t159 = load ptr, ptr %t158
  %t160 = call ptr @malloc(i64 16)
  %t161 = inttoptr i64 1 to ptr
  %t162 = getelementptr ptr, ptr %t160, i32 0
  store ptr %t161, ptr %t162
  %t163 = getelementptr [3 x i8], ptr @.str.10, i64 0, i64 0
  %t164 = call ptr @__concat(ptr %t19, ptr %t163)
  %t165 = getelementptr ptr, ptr %t160, i32 1
  store ptr %t164, ptr %t165
  %t166 = getelementptr ptr, ptr %t160, i32 0
  %t167 = load ptr, ptr %t166
  %t168 = ptrtoint ptr %t167 to i64
  switch i64 %t168, label %case.default.169 [ i64 0, label %case.arm.0.171 i64 1, label %case.arm.1.179 ]
case.arm.0.171:
  %t173 = getelementptr ptr, ptr %t160, i32 1
  %t174 = load ptr, ptr %t173
  %t175 = call ptr @malloc(i64 16)
  %t176 = inttoptr i64 0 to ptr
  %t177 = getelementptr ptr, ptr %t175, i32 0
  store ptr %t176, ptr %t177
  %t178 = getelementptr ptr, ptr %t175, i32 1
  store ptr %t174, ptr %t178
  br label %case.end.0.172
case.end.0.172:
  br label %case.join.170
case.arm.1.179:
  %t181 = getelementptr ptr, ptr %t160, i32 1
  %t182 = load ptr, ptr %t181
  %t183 = call ptr @malloc(i64 16)
  %t184 = inttoptr i64 1 to ptr
  %t185 = getelementptr ptr, ptr %t183, i32 0
  store ptr %t184, ptr %t185
  %t186 = call ptr @__concat(ptr %t182, ptr %t39)
  %t187 = getelementptr ptr, ptr %t183, i32 1
  store ptr %t186, ptr %t187
  %t188 = getelementptr ptr, ptr %t183, i32 0
  %t189 = load ptr, ptr %t188
  %t190 = ptrtoint ptr %t189 to i64
  switch i64 %t190, label %case.default.191 [ i64 0, label %case.arm.0.193 i64 1, label %case.arm.1.201 ]
case.arm.0.193:
  %t195 = getelementptr ptr, ptr %t183, i32 1
  %t196 = load ptr, ptr %t195
  %t197 = call ptr @malloc(i64 16)
  %t198 = inttoptr i64 0 to ptr
  %t199 = getelementptr ptr, ptr %t197, i32 0
  store ptr %t198, ptr %t199
  %t200 = getelementptr ptr, ptr %t197, i32 1
  store ptr %t196, ptr %t200
  br label %case.end.0.194
case.end.0.194:
  br label %case.join.192
case.arm.1.201:
  %t203 = getelementptr ptr, ptr %t183, i32 1
  %t204 = load ptr, ptr %t203
  %t205 = call ptr @malloc(i64 16)
  %t206 = inttoptr i64 1 to ptr
  %t207 = getelementptr ptr, ptr %t205, i32 0
  store ptr %t206, ptr %t207
  %t208 = getelementptr [3 x i8], ptr @.str.10, i64 0, i64 0
  %t209 = call ptr @__concat(ptr %t204, ptr %t208)
  %t210 = getelementptr ptr, ptr %t205, i32 1
  store ptr %t209, ptr %t210
  %t211 = getelementptr ptr, ptr %t205, i32 0
  %t212 = load ptr, ptr %t211
  %t213 = ptrtoint ptr %t212 to i64
  switch i64 %t213, label %case.default.214 [ i64 0, label %case.arm.0.216 i64 1, label %case.arm.1.224 ]
case.arm.0.216:
  %t218 = getelementptr ptr, ptr %t205, i32 1
  %t219 = load ptr, ptr %t218
  %t220 = call ptr @malloc(i64 16)
  %t221 = inttoptr i64 0 to ptr
  %t222 = getelementptr ptr, ptr %t220, i32 0
  store ptr %t221, ptr %t222
  %t223 = getelementptr ptr, ptr %t220, i32 1
  store ptr %t219, ptr %t223
  br label %case.end.0.217
case.end.0.217:
  br label %case.join.215
case.arm.1.224:
  %t226 = getelementptr ptr, ptr %t205, i32 1
  %t227 = load ptr, ptr %t226
  %t228 = call ptr @malloc(i64 16)
  %t229 = inttoptr i64 1 to ptr
  %t230 = getelementptr ptr, ptr %t228, i32 0
  store ptr %t229, ptr %t230
  %t231 = call ptr @__concat(ptr %t227, ptr %t59)
  %t232 = getelementptr ptr, ptr %t228, i32 1
  store ptr %t231, ptr %t232
  %t233 = getelementptr ptr, ptr %t228, i32 0
  %t234 = load ptr, ptr %t233
  %t235 = ptrtoint ptr %t234 to i64
  switch i64 %t235, label %case.default.236 [ i64 0, label %case.arm.0.238 i64 1, label %case.arm.1.246 ]
case.arm.0.238:
  %t240 = getelementptr ptr, ptr %t228, i32 1
  %t241 = load ptr, ptr %t240
  %t242 = call ptr @malloc(i64 16)
  %t243 = inttoptr i64 0 to ptr
  %t244 = getelementptr ptr, ptr %t242, i32 0
  store ptr %t243, ptr %t244
  %t245 = getelementptr ptr, ptr %t242, i32 1
  store ptr %t241, ptr %t245
  br label %case.end.0.239
case.end.0.239:
  br label %case.join.237
case.arm.1.246:
  %t248 = getelementptr ptr, ptr %t228, i32 1
  %t249 = load ptr, ptr %t248
  %t250 = call ptr @malloc(i64 16)
  %t251 = inttoptr i64 1 to ptr
  %t252 = getelementptr ptr, ptr %t250, i32 0
  store ptr %t251, ptr %t252
  %t253 = getelementptr [3 x i8], ptr @.str.10, i64 0, i64 0
  %t254 = call ptr @__concat(ptr %t249, ptr %t253)
  %t255 = getelementptr ptr, ptr %t250, i32 1
  store ptr %t254, ptr %t255
  %t256 = getelementptr ptr, ptr %t250, i32 0
  %t257 = load ptr, ptr %t256
  %t258 = ptrtoint ptr %t257 to i64
  switch i64 %t258, label %case.default.259 [ i64 0, label %case.arm.0.261 i64 1, label %case.arm.1.269 ]
case.arm.0.261:
  %t263 = getelementptr ptr, ptr %t250, i32 1
  %t264 = load ptr, ptr %t263
  %t265 = call ptr @malloc(i64 16)
  %t266 = inttoptr i64 0 to ptr
  %t267 = getelementptr ptr, ptr %t265, i32 0
  store ptr %t266, ptr %t267
  %t268 = getelementptr ptr, ptr %t265, i32 1
  store ptr %t264, ptr %t268
  br label %case.end.0.262
case.end.0.262:
  br label %case.join.260
case.arm.1.269:
  %t271 = getelementptr ptr, ptr %t250, i32 1
  %t272 = load ptr, ptr %t271
  %t273 = call ptr @malloc(i64 16)
  %t274 = inttoptr i64 1 to ptr
  %t275 = getelementptr ptr, ptr %t273, i32 0
  store ptr %t274, ptr %t275
  %t276 = call ptr @__concat(ptr %t272, ptr %t79)
  %t277 = getelementptr ptr, ptr %t273, i32 1
  store ptr %t276, ptr %t277
  %t278 = getelementptr ptr, ptr %t273, i32 0
  %t279 = load ptr, ptr %t278
  %t280 = ptrtoint ptr %t279 to i64
  switch i64 %t280, label %case.default.281 [ i64 0, label %case.arm.0.283 i64 1, label %case.arm.1.291 ]
case.arm.0.283:
  %t285 = getelementptr ptr, ptr %t273, i32 1
  %t286 = load ptr, ptr %t285
  %t287 = call ptr @malloc(i64 16)
  %t288 = inttoptr i64 0 to ptr
  %t289 = getelementptr ptr, ptr %t287, i32 0
  store ptr %t288, ptr %t289
  %t290 = getelementptr ptr, ptr %t287, i32 1
  store ptr %t286, ptr %t290
  br label %case.end.0.284
case.end.0.284:
  br label %case.join.282
case.arm.1.291:
  %t293 = getelementptr ptr, ptr %t273, i32 1
  %t294 = load ptr, ptr %t293
  %t295 = call ptr @malloc(i64 16)
  %t296 = inttoptr i64 1 to ptr
  %t297 = getelementptr ptr, ptr %t295, i32 0
  store ptr %t296, ptr %t297
  %t298 = getelementptr [3 x i8], ptr @.str.10, i64 0, i64 0
  %t299 = call ptr @__concat(ptr %t294, ptr %t298)
  %t300 = getelementptr ptr, ptr %t295, i32 1
  store ptr %t299, ptr %t300
  %t301 = getelementptr ptr, ptr %t295, i32 0
  %t302 = load ptr, ptr %t301
  %t303 = ptrtoint ptr %t302 to i64
  switch i64 %t303, label %case.default.304 [ i64 0, label %case.arm.0.306 i64 1, label %case.arm.1.314 ]
case.arm.0.306:
  %t308 = getelementptr ptr, ptr %t295, i32 1
  %t309 = load ptr, ptr %t308
  %t310 = call ptr @malloc(i64 16)
  %t311 = inttoptr i64 0 to ptr
  %t312 = getelementptr ptr, ptr %t310, i32 0
  store ptr %t311, ptr %t312
  %t313 = getelementptr ptr, ptr %t310, i32 1
  store ptr %t309, ptr %t313
  br label %case.end.0.307
case.end.0.307:
  br label %case.join.305
case.arm.1.314:
  %t316 = getelementptr ptr, ptr %t295, i32 1
  %t317 = load ptr, ptr %t316
  %t318 = call ptr @malloc(i64 16)
  %t319 = inttoptr i64 1 to ptr
  %t320 = getelementptr ptr, ptr %t318, i32 0
  store ptr %t319, ptr %t320
  %t321 = call ptr @__concat(ptr %t317, ptr %t99)
  %t322 = getelementptr ptr, ptr %t318, i32 1
  store ptr %t321, ptr %t322
  %t323 = getelementptr ptr, ptr %t318, i32 0
  %t324 = load ptr, ptr %t323
  %t325 = ptrtoint ptr %t324 to i64
  switch i64 %t325, label %case.default.326 [ i64 0, label %case.arm.0.328 i64 1, label %case.arm.1.336 ]
case.arm.0.328:
  %t330 = getelementptr ptr, ptr %t318, i32 1
  %t331 = load ptr, ptr %t330
  %t332 = call ptr @malloc(i64 16)
  %t333 = inttoptr i64 0 to ptr
  %t334 = getelementptr ptr, ptr %t332, i32 0
  store ptr %t333, ptr %t334
  %t335 = getelementptr ptr, ptr %t332, i32 1
  store ptr %t331, ptr %t335
  br label %case.end.0.329
case.end.0.329:
  br label %case.join.327
case.arm.1.336:
  %t338 = getelementptr ptr, ptr %t318, i32 1
  %t339 = load ptr, ptr %t338
  %t340 = call ptr @malloc(i64 16)
  %t341 = inttoptr i64 1 to ptr
  %t342 = getelementptr ptr, ptr %t340, i32 0
  store ptr %t341, ptr %t342
  %t343 = getelementptr [3 x i8], ptr @.str.10, i64 0, i64 0
  %t344 = call ptr @__concat(ptr %t339, ptr %t343)
  %t345 = getelementptr ptr, ptr %t340, i32 1
  store ptr %t344, ptr %t345
  %t346 = getelementptr ptr, ptr %t340, i32 0
  %t347 = load ptr, ptr %t346
  %t348 = ptrtoint ptr %t347 to i64
  switch i64 %t348, label %case.default.349 [ i64 0, label %case.arm.0.351 i64 1, label %case.arm.1.359 ]
case.arm.0.351:
  %t353 = getelementptr ptr, ptr %t340, i32 1
  %t354 = load ptr, ptr %t353
  %t355 = call ptr @malloc(i64 16)
  %t356 = inttoptr i64 0 to ptr
  %t357 = getelementptr ptr, ptr %t355, i32 0
  store ptr %t356, ptr %t357
  %t358 = getelementptr ptr, ptr %t355, i32 1
  store ptr %t354, ptr %t358
  br label %case.end.0.352
case.end.0.352:
  br label %case.join.350
case.arm.1.359:
  %t361 = getelementptr ptr, ptr %t340, i32 1
  %t362 = load ptr, ptr %t361
  %t363 = call ptr @malloc(i64 16)
  %t364 = inttoptr i64 1 to ptr
  %t365 = getelementptr ptr, ptr %t363, i32 0
  store ptr %t364, ptr %t365
  %t366 = call ptr @__concat(ptr %t362, ptr %t119)
  %t367 = getelementptr ptr, ptr %t363, i32 1
  store ptr %t366, ptr %t367
  %t368 = getelementptr ptr, ptr %t363, i32 0
  %t369 = load ptr, ptr %t368
  %t370 = ptrtoint ptr %t369 to i64
  switch i64 %t370, label %case.default.371 [ i64 0, label %case.arm.0.373 i64 1, label %case.arm.1.381 ]
case.arm.0.373:
  %t375 = getelementptr ptr, ptr %t363, i32 1
  %t376 = load ptr, ptr %t375
  %t377 = call ptr @malloc(i64 16)
  %t378 = inttoptr i64 0 to ptr
  %t379 = getelementptr ptr, ptr %t377, i32 0
  store ptr %t378, ptr %t379
  %t380 = getelementptr ptr, ptr %t377, i32 1
  store ptr %t376, ptr %t380
  br label %case.end.0.374
case.end.0.374:
  br label %case.join.372
case.arm.1.381:
  %t383 = getelementptr ptr, ptr %t363, i32 1
  %t384 = load ptr, ptr %t383
  %t385 = call ptr @malloc(i64 16)
  %t386 = inttoptr i64 1 to ptr
  %t387 = getelementptr ptr, ptr %t385, i32 0
  store ptr %t386, ptr %t387
  %t388 = getelementptr [3 x i8], ptr @.str.10, i64 0, i64 0
  %t389 = call ptr @__concat(ptr %t384, ptr %t388)
  %t390 = getelementptr ptr, ptr %t385, i32 1
  store ptr %t389, ptr %t390
  %t391 = getelementptr ptr, ptr %t385, i32 0
  %t392 = load ptr, ptr %t391
  %t393 = ptrtoint ptr %t392 to i64
  switch i64 %t393, label %case.default.394 [ i64 0, label %case.arm.0.396 i64 1, label %case.arm.1.404 ]
case.arm.0.396:
  %t398 = getelementptr ptr, ptr %t385, i32 1
  %t399 = load ptr, ptr %t398
  %t400 = call ptr @malloc(i64 16)
  %t401 = inttoptr i64 0 to ptr
  %t402 = getelementptr ptr, ptr %t400, i32 0
  store ptr %t401, ptr %t402
  %t403 = getelementptr ptr, ptr %t400, i32 1
  store ptr %t399, ptr %t403
  br label %case.end.0.397
case.end.0.397:
  br label %case.join.395
case.arm.1.404:
  %t406 = getelementptr ptr, ptr %t385, i32 1
  %t407 = load ptr, ptr %t406
  %t408 = call ptr @malloc(i64 16)
  %t409 = inttoptr i64 1 to ptr
  %t410 = getelementptr ptr, ptr %t408, i32 0
  store ptr %t409, ptr %t410
  %t411 = call ptr @__concat(ptr %t407, ptr %t139)
  %t412 = getelementptr ptr, ptr %t408, i32 1
  store ptr %t411, ptr %t412
  %t413 = getelementptr ptr, ptr %t408, i32 0
  %t414 = load ptr, ptr %t413
  %t415 = ptrtoint ptr %t414 to i64
  switch i64 %t415, label %case.default.416 [ i64 0, label %case.arm.0.418 i64 1, label %case.arm.1.426 ]
case.arm.0.418:
  %t420 = getelementptr ptr, ptr %t408, i32 1
  %t421 = load ptr, ptr %t420
  %t422 = call ptr @malloc(i64 16)
  %t423 = inttoptr i64 0 to ptr
  %t424 = getelementptr ptr, ptr %t422, i32 0
  store ptr %t423, ptr %t424
  %t425 = getelementptr ptr, ptr %t422, i32 1
  store ptr %t421, ptr %t425
  br label %case.end.0.419
case.end.0.419:
  br label %case.join.417
case.arm.1.426:
  %t428 = getelementptr ptr, ptr %t408, i32 1
  %t429 = load ptr, ptr %t428
  %t430 = call ptr @malloc(i64 16)
  %t431 = inttoptr i64 1 to ptr
  %t432 = getelementptr ptr, ptr %t430, i32 0
  store ptr %t431, ptr %t432
  %t433 = getelementptr [3 x i8], ptr @.str.10, i64 0, i64 0
  %t434 = call ptr @__concat(ptr %t429, ptr %t433)
  %t435 = getelementptr ptr, ptr %t430, i32 1
  store ptr %t434, ptr %t435
  %t436 = getelementptr ptr, ptr %t430, i32 0
  %t437 = load ptr, ptr %t436
  %t438 = ptrtoint ptr %t437 to i64
  switch i64 %t438, label %case.default.439 [ i64 0, label %case.arm.0.441 i64 1, label %case.arm.1.449 ]
case.arm.0.441:
  %t443 = getelementptr ptr, ptr %t430, i32 1
  %t444 = load ptr, ptr %t443
  %t445 = call ptr @malloc(i64 16)
  %t446 = inttoptr i64 0 to ptr
  %t447 = getelementptr ptr, ptr %t445, i32 0
  store ptr %t446, ptr %t447
  %t448 = getelementptr ptr, ptr %t445, i32 1
  store ptr %t444, ptr %t448
  br label %case.end.0.442
case.end.0.442:
  br label %case.join.440
case.arm.1.449:
  %t451 = getelementptr ptr, ptr %t430, i32 1
  %t452 = load ptr, ptr %t451
  %t453 = call ptr @malloc(i64 16)
  %t454 = inttoptr i64 1 to ptr
  %t455 = getelementptr ptr, ptr %t453, i32 0
  store ptr %t454, ptr %t455
  %t456 = call ptr @__concat(ptr %t452, ptr %t159)
  %t457 = getelementptr ptr, ptr %t453, i32 1
  store ptr %t456, ptr %t457
  br label %case.end.1.450
case.end.1.450:
  br label %case.join.440
case.default.439:
  unreachable
case.join.440:
  %t458 = phi ptr [%t445, %case.end.0.442], [%t453, %case.end.1.450]
  br label %case.end.1.427
case.end.1.427:
  br label %case.join.417
case.default.416:
  unreachable
case.join.417:
  %t459 = phi ptr [%t422, %case.end.0.419], [%t458, %case.end.1.427]
  br label %case.end.1.405
case.end.1.405:
  br label %case.join.395
case.default.394:
  unreachable
case.join.395:
  %t460 = phi ptr [%t400, %case.end.0.397], [%t459, %case.end.1.405]
  br label %case.end.1.382
case.end.1.382:
  br label %case.join.372
case.default.371:
  unreachable
case.join.372:
  %t461 = phi ptr [%t377, %case.end.0.374], [%t460, %case.end.1.382]
  br label %case.end.1.360
case.end.1.360:
  br label %case.join.350
case.default.349:
  unreachable
case.join.350:
  %t462 = phi ptr [%t355, %case.end.0.352], [%t461, %case.end.1.360]
  br label %case.end.1.337
case.end.1.337:
  br label %case.join.327
case.default.326:
  unreachable
case.join.327:
  %t463 = phi ptr [%t332, %case.end.0.329], [%t462, %case.end.1.337]
  br label %case.end.1.315
case.end.1.315:
  br label %case.join.305
case.default.304:
  unreachable
case.join.305:
  %t464 = phi ptr [%t310, %case.end.0.307], [%t463, %case.end.1.315]
  br label %case.end.1.292
case.end.1.292:
  br label %case.join.282
case.default.281:
  unreachable
case.join.282:
  %t465 = phi ptr [%t287, %case.end.0.284], [%t464, %case.end.1.292]
  br label %case.end.1.270
case.end.1.270:
  br label %case.join.260
case.default.259:
  unreachable
case.join.260:
  %t466 = phi ptr [%t265, %case.end.0.262], [%t465, %case.end.1.270]
  br label %case.end.1.247
case.end.1.247:
  br label %case.join.237
case.default.236:
  unreachable
case.join.237:
  %t467 = phi ptr [%t242, %case.end.0.239], [%t466, %case.end.1.247]
  br label %case.end.1.225
case.end.1.225:
  br label %case.join.215
case.default.214:
  unreachable
case.join.215:
  %t468 = phi ptr [%t220, %case.end.0.217], [%t467, %case.end.1.225]
  br label %case.end.1.202
case.end.1.202:
  br label %case.join.192
case.default.191:
  unreachable
case.join.192:
  %t469 = phi ptr [%t197, %case.end.0.194], [%t468, %case.end.1.202]
  br label %case.end.1.180
case.end.1.180:
  br label %case.join.170
case.default.169:
  unreachable
case.join.170:
  %t470 = phi ptr [%t175, %case.end.0.172], [%t469, %case.end.1.180]
  br label %case.end.1.157
case.end.1.157:
  br label %case.join.147
case.default.146:
  unreachable
case.join.147:
  %t471 = phi ptr [%t152, %case.end.0.149], [%t470, %case.end.1.157]
  br label %case.end.1.137
case.end.1.137:
  br label %case.join.127
case.default.126:
  unreachable
case.join.127:
  %t472 = phi ptr [%t132, %case.end.0.129], [%t471, %case.end.1.137]
  br label %case.end.1.117
case.end.1.117:
  br label %case.join.107
case.default.106:
  unreachable
case.join.107:
  %t473 = phi ptr [%t112, %case.end.0.109], [%t472, %case.end.1.117]
  br label %case.end.1.97
case.end.1.97:
  br label %case.join.87
case.default.86:
  unreachable
case.join.87:
  %t474 = phi ptr [%t92, %case.end.0.89], [%t473, %case.end.1.97]
  br label %case.end.1.77
case.end.1.77:
  br label %case.join.67
case.default.66:
  unreachable
case.join.67:
  %t475 = phi ptr [%t72, %case.end.0.69], [%t474, %case.end.1.77]
  br label %case.end.1.57
case.end.1.57:
  br label %case.join.47
case.default.46:
  unreachable
case.join.47:
  %t476 = phi ptr [%t52, %case.end.0.49], [%t475, %case.end.1.57]
  br label %case.end.1.37
case.end.1.37:
  br label %case.join.27
case.default.26:
  unreachable
case.join.27:
  %t477 = phi ptr [%t32, %case.end.0.29], [%t476, %case.end.1.37]
  br label %case.end.1.17
case.end.1.17:
  br label %case.join.7
case.default.6:
  unreachable
case.join.7:
  %t478 = phi ptr [%t12, %case.end.0.9], [%t477, %case.end.1.17]
  %t479 = call ptr @v__let_2(ptr %t478)
  ret ptr %t479
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
  %t12 = getelementptr [16 x i8], ptr @.str.11, i64 0, i64 0
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
