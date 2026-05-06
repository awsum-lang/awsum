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
@.str.3 = private unnamed_addr constant [11 x i8] c"4294967295\00"
@.str.4 = private unnamed_addr constant [11 x i8] c"4294967296\00"
@.str.5 = private unnamed_addr constant [3 x i8] c"-1\00"
@.str.6 = private unnamed_addr constant [1 x i8] c"\00"
@.str.7 = private unnamed_addr constant [4 x i8] c"abc\00"
@.str.8 = private unnamed_addr constant [3 x i8] c" 5\00"
@.str.9 = private unnamed_addr constant [4 x i8] c"12a\00"
@.str.10 = private unnamed_addr constant [11 x i8] c"2147483648\00"
@.str.11 = private unnamed_addr constant [3 x i8] c", \00"
@.str.12 = private unnamed_addr constant [16 x i8] c"STRING_TOO_LONG\00"

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


define internal ptr @__parseUInt32(ptr %s) {
entry:
  %i_alloca = alloca i64, align 8
  store i64 0, ptr %i_alloca
  %acc_alloca = alloca i64, align 8
  store i64 0, ptr %acc_alloca
  %len = call i64 @strlen(ptr %s)
  %is_empty = icmp eq i64 %len, 0
  br i1 %is_empty, label %fail, label %loop_head
loop_head:
  %i = load i64, ptr %i_alloca
  %acc = load i64, ptr %acc_alloca
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
  %d_i64 = zext i32 %d to i64
  %x10 = mul i64 %acc, 10
  %acc_next = add i64 %x10, %d_i64
  %big = icmp ugt i64 %acc_next, 4294967295
  br i1 %big, label %fail, label %body_end
body_end:
  store i64 %acc_next, ptr %acc_alloca
  %i_next = add i64 %i, 1
  store i64 %i_next, ptr %i_alloca
  br label %loop_head
ok:
  %result_i32 = trunc i64 %acc to i32
  %box = call ptr @malloc(i64 4)
  store i32 %result_i32, ptr %box
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
  %t22 = call ptr @__showUInt32(ptr %t17)
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
  %t1 = call ptr @__parseUInt32(ptr %t0)
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
  %t20 = getelementptr [11 x i8], ptr @.str.3, i64 0, i64 0
  %t21 = call ptr @__parseUInt32(ptr %t20)
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
  %t40 = getelementptr [11 x i8], ptr @.str.4, i64 0, i64 0
  %t41 = call ptr @__parseUInt32(ptr %t40)
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
  %t61 = call ptr @__parseUInt32(ptr %t60)
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
  %t81 = call ptr @__parseUInt32(ptr %t80)
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
  %t101 = call ptr @__parseUInt32(ptr %t100)
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
  %t121 = call ptr @__parseUInt32(ptr %t120)
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
  %t141 = call ptr @__parseUInt32(ptr %t140)
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
  %t160 = getelementptr [11 x i8], ptr @.str.10, i64 0, i64 0
  %t161 = call ptr @__parseUInt32(ptr %t160)
  %t162 = call ptr @v_render(ptr %t161)
  %t163 = getelementptr ptr, ptr %t162, i32 0
  %t164 = load ptr, ptr %t163
  %t165 = ptrtoint ptr %t164 to i64
  switch i64 %t165, label %case.default.166 [ i64 0, label %case.arm.0.168 i64 1, label %case.arm.1.176 ]
case.arm.0.168:
  %t170 = getelementptr ptr, ptr %t162, i32 1
  %t171 = load ptr, ptr %t170
  %t172 = call ptr @malloc(i64 16)
  %t173 = inttoptr i64 0 to ptr
  %t174 = getelementptr ptr, ptr %t172, i32 0
  store ptr %t173, ptr %t174
  %t175 = getelementptr ptr, ptr %t172, i32 1
  store ptr %t171, ptr %t175
  br label %case.end.0.169
case.end.0.169:
  br label %case.join.167
case.arm.1.176:
  %t178 = getelementptr ptr, ptr %t162, i32 1
  %t179 = load ptr, ptr %t178
  %t180 = call ptr @malloc(i64 16)
  %t181 = inttoptr i64 1 to ptr
  %t182 = getelementptr ptr, ptr %t180, i32 0
  store ptr %t181, ptr %t182
  %t183 = getelementptr [3 x i8], ptr @.str.11, i64 0, i64 0
  %t184 = call ptr @__concat(ptr %t19, ptr %t183)
  %t185 = getelementptr ptr, ptr %t180, i32 1
  store ptr %t184, ptr %t185
  %t186 = getelementptr ptr, ptr %t180, i32 0
  %t187 = load ptr, ptr %t186
  %t188 = ptrtoint ptr %t187 to i64
  switch i64 %t188, label %case.default.189 [ i64 0, label %case.arm.0.191 i64 1, label %case.arm.1.199 ]
case.arm.0.191:
  %t193 = getelementptr ptr, ptr %t180, i32 1
  %t194 = load ptr, ptr %t193
  %t195 = call ptr @malloc(i64 16)
  %t196 = inttoptr i64 0 to ptr
  %t197 = getelementptr ptr, ptr %t195, i32 0
  store ptr %t196, ptr %t197
  %t198 = getelementptr ptr, ptr %t195, i32 1
  store ptr %t194, ptr %t198
  br label %case.end.0.192
case.end.0.192:
  br label %case.join.190
case.arm.1.199:
  %t201 = getelementptr ptr, ptr %t180, i32 1
  %t202 = load ptr, ptr %t201
  %t203 = call ptr @malloc(i64 16)
  %t204 = inttoptr i64 1 to ptr
  %t205 = getelementptr ptr, ptr %t203, i32 0
  store ptr %t204, ptr %t205
  %t206 = call ptr @__concat(ptr %t202, ptr %t39)
  %t207 = getelementptr ptr, ptr %t203, i32 1
  store ptr %t206, ptr %t207
  %t208 = getelementptr ptr, ptr %t203, i32 0
  %t209 = load ptr, ptr %t208
  %t210 = ptrtoint ptr %t209 to i64
  switch i64 %t210, label %case.default.211 [ i64 0, label %case.arm.0.213 i64 1, label %case.arm.1.221 ]
case.arm.0.213:
  %t215 = getelementptr ptr, ptr %t203, i32 1
  %t216 = load ptr, ptr %t215
  %t217 = call ptr @malloc(i64 16)
  %t218 = inttoptr i64 0 to ptr
  %t219 = getelementptr ptr, ptr %t217, i32 0
  store ptr %t218, ptr %t219
  %t220 = getelementptr ptr, ptr %t217, i32 1
  store ptr %t216, ptr %t220
  br label %case.end.0.214
case.end.0.214:
  br label %case.join.212
case.arm.1.221:
  %t223 = getelementptr ptr, ptr %t203, i32 1
  %t224 = load ptr, ptr %t223
  %t225 = call ptr @malloc(i64 16)
  %t226 = inttoptr i64 1 to ptr
  %t227 = getelementptr ptr, ptr %t225, i32 0
  store ptr %t226, ptr %t227
  %t228 = getelementptr [3 x i8], ptr @.str.11, i64 0, i64 0
  %t229 = call ptr @__concat(ptr %t224, ptr %t228)
  %t230 = getelementptr ptr, ptr %t225, i32 1
  store ptr %t229, ptr %t230
  %t231 = getelementptr ptr, ptr %t225, i32 0
  %t232 = load ptr, ptr %t231
  %t233 = ptrtoint ptr %t232 to i64
  switch i64 %t233, label %case.default.234 [ i64 0, label %case.arm.0.236 i64 1, label %case.arm.1.244 ]
case.arm.0.236:
  %t238 = getelementptr ptr, ptr %t225, i32 1
  %t239 = load ptr, ptr %t238
  %t240 = call ptr @malloc(i64 16)
  %t241 = inttoptr i64 0 to ptr
  %t242 = getelementptr ptr, ptr %t240, i32 0
  store ptr %t241, ptr %t242
  %t243 = getelementptr ptr, ptr %t240, i32 1
  store ptr %t239, ptr %t243
  br label %case.end.0.237
case.end.0.237:
  br label %case.join.235
case.arm.1.244:
  %t246 = getelementptr ptr, ptr %t225, i32 1
  %t247 = load ptr, ptr %t246
  %t248 = call ptr @malloc(i64 16)
  %t249 = inttoptr i64 1 to ptr
  %t250 = getelementptr ptr, ptr %t248, i32 0
  store ptr %t249, ptr %t250
  %t251 = call ptr @__concat(ptr %t247, ptr %t59)
  %t252 = getelementptr ptr, ptr %t248, i32 1
  store ptr %t251, ptr %t252
  %t253 = getelementptr ptr, ptr %t248, i32 0
  %t254 = load ptr, ptr %t253
  %t255 = ptrtoint ptr %t254 to i64
  switch i64 %t255, label %case.default.256 [ i64 0, label %case.arm.0.258 i64 1, label %case.arm.1.266 ]
case.arm.0.258:
  %t260 = getelementptr ptr, ptr %t248, i32 1
  %t261 = load ptr, ptr %t260
  %t262 = call ptr @malloc(i64 16)
  %t263 = inttoptr i64 0 to ptr
  %t264 = getelementptr ptr, ptr %t262, i32 0
  store ptr %t263, ptr %t264
  %t265 = getelementptr ptr, ptr %t262, i32 1
  store ptr %t261, ptr %t265
  br label %case.end.0.259
case.end.0.259:
  br label %case.join.257
case.arm.1.266:
  %t268 = getelementptr ptr, ptr %t248, i32 1
  %t269 = load ptr, ptr %t268
  %t270 = call ptr @malloc(i64 16)
  %t271 = inttoptr i64 1 to ptr
  %t272 = getelementptr ptr, ptr %t270, i32 0
  store ptr %t271, ptr %t272
  %t273 = getelementptr [3 x i8], ptr @.str.11, i64 0, i64 0
  %t274 = call ptr @__concat(ptr %t269, ptr %t273)
  %t275 = getelementptr ptr, ptr %t270, i32 1
  store ptr %t274, ptr %t275
  %t276 = getelementptr ptr, ptr %t270, i32 0
  %t277 = load ptr, ptr %t276
  %t278 = ptrtoint ptr %t277 to i64
  switch i64 %t278, label %case.default.279 [ i64 0, label %case.arm.0.281 i64 1, label %case.arm.1.289 ]
case.arm.0.281:
  %t283 = getelementptr ptr, ptr %t270, i32 1
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
  %t291 = getelementptr ptr, ptr %t270, i32 1
  %t292 = load ptr, ptr %t291
  %t293 = call ptr @malloc(i64 16)
  %t294 = inttoptr i64 1 to ptr
  %t295 = getelementptr ptr, ptr %t293, i32 0
  store ptr %t294, ptr %t295
  %t296 = call ptr @__concat(ptr %t292, ptr %t79)
  %t297 = getelementptr ptr, ptr %t293, i32 1
  store ptr %t296, ptr %t297
  %t298 = getelementptr ptr, ptr %t293, i32 0
  %t299 = load ptr, ptr %t298
  %t300 = ptrtoint ptr %t299 to i64
  switch i64 %t300, label %case.default.301 [ i64 0, label %case.arm.0.303 i64 1, label %case.arm.1.311 ]
case.arm.0.303:
  %t305 = getelementptr ptr, ptr %t293, i32 1
  %t306 = load ptr, ptr %t305
  %t307 = call ptr @malloc(i64 16)
  %t308 = inttoptr i64 0 to ptr
  %t309 = getelementptr ptr, ptr %t307, i32 0
  store ptr %t308, ptr %t309
  %t310 = getelementptr ptr, ptr %t307, i32 1
  store ptr %t306, ptr %t310
  br label %case.end.0.304
case.end.0.304:
  br label %case.join.302
case.arm.1.311:
  %t313 = getelementptr ptr, ptr %t293, i32 1
  %t314 = load ptr, ptr %t313
  %t315 = call ptr @malloc(i64 16)
  %t316 = inttoptr i64 1 to ptr
  %t317 = getelementptr ptr, ptr %t315, i32 0
  store ptr %t316, ptr %t317
  %t318 = getelementptr [3 x i8], ptr @.str.11, i64 0, i64 0
  %t319 = call ptr @__concat(ptr %t314, ptr %t318)
  %t320 = getelementptr ptr, ptr %t315, i32 1
  store ptr %t319, ptr %t320
  %t321 = getelementptr ptr, ptr %t315, i32 0
  %t322 = load ptr, ptr %t321
  %t323 = ptrtoint ptr %t322 to i64
  switch i64 %t323, label %case.default.324 [ i64 0, label %case.arm.0.326 i64 1, label %case.arm.1.334 ]
case.arm.0.326:
  %t328 = getelementptr ptr, ptr %t315, i32 1
  %t329 = load ptr, ptr %t328
  %t330 = call ptr @malloc(i64 16)
  %t331 = inttoptr i64 0 to ptr
  %t332 = getelementptr ptr, ptr %t330, i32 0
  store ptr %t331, ptr %t332
  %t333 = getelementptr ptr, ptr %t330, i32 1
  store ptr %t329, ptr %t333
  br label %case.end.0.327
case.end.0.327:
  br label %case.join.325
case.arm.1.334:
  %t336 = getelementptr ptr, ptr %t315, i32 1
  %t337 = load ptr, ptr %t336
  %t338 = call ptr @malloc(i64 16)
  %t339 = inttoptr i64 1 to ptr
  %t340 = getelementptr ptr, ptr %t338, i32 0
  store ptr %t339, ptr %t340
  %t341 = call ptr @__concat(ptr %t337, ptr %t99)
  %t342 = getelementptr ptr, ptr %t338, i32 1
  store ptr %t341, ptr %t342
  %t343 = getelementptr ptr, ptr %t338, i32 0
  %t344 = load ptr, ptr %t343
  %t345 = ptrtoint ptr %t344 to i64
  switch i64 %t345, label %case.default.346 [ i64 0, label %case.arm.0.348 i64 1, label %case.arm.1.356 ]
case.arm.0.348:
  %t350 = getelementptr ptr, ptr %t338, i32 1
  %t351 = load ptr, ptr %t350
  %t352 = call ptr @malloc(i64 16)
  %t353 = inttoptr i64 0 to ptr
  %t354 = getelementptr ptr, ptr %t352, i32 0
  store ptr %t353, ptr %t354
  %t355 = getelementptr ptr, ptr %t352, i32 1
  store ptr %t351, ptr %t355
  br label %case.end.0.349
case.end.0.349:
  br label %case.join.347
case.arm.1.356:
  %t358 = getelementptr ptr, ptr %t338, i32 1
  %t359 = load ptr, ptr %t358
  %t360 = call ptr @malloc(i64 16)
  %t361 = inttoptr i64 1 to ptr
  %t362 = getelementptr ptr, ptr %t360, i32 0
  store ptr %t361, ptr %t362
  %t363 = getelementptr [3 x i8], ptr @.str.11, i64 0, i64 0
  %t364 = call ptr @__concat(ptr %t359, ptr %t363)
  %t365 = getelementptr ptr, ptr %t360, i32 1
  store ptr %t364, ptr %t365
  %t366 = getelementptr ptr, ptr %t360, i32 0
  %t367 = load ptr, ptr %t366
  %t368 = ptrtoint ptr %t367 to i64
  switch i64 %t368, label %case.default.369 [ i64 0, label %case.arm.0.371 i64 1, label %case.arm.1.379 ]
case.arm.0.371:
  %t373 = getelementptr ptr, ptr %t360, i32 1
  %t374 = load ptr, ptr %t373
  %t375 = call ptr @malloc(i64 16)
  %t376 = inttoptr i64 0 to ptr
  %t377 = getelementptr ptr, ptr %t375, i32 0
  store ptr %t376, ptr %t377
  %t378 = getelementptr ptr, ptr %t375, i32 1
  store ptr %t374, ptr %t378
  br label %case.end.0.372
case.end.0.372:
  br label %case.join.370
case.arm.1.379:
  %t381 = getelementptr ptr, ptr %t360, i32 1
  %t382 = load ptr, ptr %t381
  %t383 = call ptr @malloc(i64 16)
  %t384 = inttoptr i64 1 to ptr
  %t385 = getelementptr ptr, ptr %t383, i32 0
  store ptr %t384, ptr %t385
  %t386 = call ptr @__concat(ptr %t382, ptr %t119)
  %t387 = getelementptr ptr, ptr %t383, i32 1
  store ptr %t386, ptr %t387
  %t388 = getelementptr ptr, ptr %t383, i32 0
  %t389 = load ptr, ptr %t388
  %t390 = ptrtoint ptr %t389 to i64
  switch i64 %t390, label %case.default.391 [ i64 0, label %case.arm.0.393 i64 1, label %case.arm.1.401 ]
case.arm.0.393:
  %t395 = getelementptr ptr, ptr %t383, i32 1
  %t396 = load ptr, ptr %t395
  %t397 = call ptr @malloc(i64 16)
  %t398 = inttoptr i64 0 to ptr
  %t399 = getelementptr ptr, ptr %t397, i32 0
  store ptr %t398, ptr %t399
  %t400 = getelementptr ptr, ptr %t397, i32 1
  store ptr %t396, ptr %t400
  br label %case.end.0.394
case.end.0.394:
  br label %case.join.392
case.arm.1.401:
  %t403 = getelementptr ptr, ptr %t383, i32 1
  %t404 = load ptr, ptr %t403
  %t405 = call ptr @malloc(i64 16)
  %t406 = inttoptr i64 1 to ptr
  %t407 = getelementptr ptr, ptr %t405, i32 0
  store ptr %t406, ptr %t407
  %t408 = getelementptr [3 x i8], ptr @.str.11, i64 0, i64 0
  %t409 = call ptr @__concat(ptr %t404, ptr %t408)
  %t410 = getelementptr ptr, ptr %t405, i32 1
  store ptr %t409, ptr %t410
  %t411 = getelementptr ptr, ptr %t405, i32 0
  %t412 = load ptr, ptr %t411
  %t413 = ptrtoint ptr %t412 to i64
  switch i64 %t413, label %case.default.414 [ i64 0, label %case.arm.0.416 i64 1, label %case.arm.1.424 ]
case.arm.0.416:
  %t418 = getelementptr ptr, ptr %t405, i32 1
  %t419 = load ptr, ptr %t418
  %t420 = call ptr @malloc(i64 16)
  %t421 = inttoptr i64 0 to ptr
  %t422 = getelementptr ptr, ptr %t420, i32 0
  store ptr %t421, ptr %t422
  %t423 = getelementptr ptr, ptr %t420, i32 1
  store ptr %t419, ptr %t423
  br label %case.end.0.417
case.end.0.417:
  br label %case.join.415
case.arm.1.424:
  %t426 = getelementptr ptr, ptr %t405, i32 1
  %t427 = load ptr, ptr %t426
  %t428 = call ptr @malloc(i64 16)
  %t429 = inttoptr i64 1 to ptr
  %t430 = getelementptr ptr, ptr %t428, i32 0
  store ptr %t429, ptr %t430
  %t431 = call ptr @__concat(ptr %t427, ptr %t139)
  %t432 = getelementptr ptr, ptr %t428, i32 1
  store ptr %t431, ptr %t432
  %t433 = getelementptr ptr, ptr %t428, i32 0
  %t434 = load ptr, ptr %t433
  %t435 = ptrtoint ptr %t434 to i64
  switch i64 %t435, label %case.default.436 [ i64 0, label %case.arm.0.438 i64 1, label %case.arm.1.446 ]
case.arm.0.438:
  %t440 = getelementptr ptr, ptr %t428, i32 1
  %t441 = load ptr, ptr %t440
  %t442 = call ptr @malloc(i64 16)
  %t443 = inttoptr i64 0 to ptr
  %t444 = getelementptr ptr, ptr %t442, i32 0
  store ptr %t443, ptr %t444
  %t445 = getelementptr ptr, ptr %t442, i32 1
  store ptr %t441, ptr %t445
  br label %case.end.0.439
case.end.0.439:
  br label %case.join.437
case.arm.1.446:
  %t448 = getelementptr ptr, ptr %t428, i32 1
  %t449 = load ptr, ptr %t448
  %t450 = call ptr @malloc(i64 16)
  %t451 = inttoptr i64 1 to ptr
  %t452 = getelementptr ptr, ptr %t450, i32 0
  store ptr %t451, ptr %t452
  %t453 = getelementptr [3 x i8], ptr @.str.11, i64 0, i64 0
  %t454 = call ptr @__concat(ptr %t449, ptr %t453)
  %t455 = getelementptr ptr, ptr %t450, i32 1
  store ptr %t454, ptr %t455
  %t456 = getelementptr ptr, ptr %t450, i32 0
  %t457 = load ptr, ptr %t456
  %t458 = ptrtoint ptr %t457 to i64
  switch i64 %t458, label %case.default.459 [ i64 0, label %case.arm.0.461 i64 1, label %case.arm.1.469 ]
case.arm.0.461:
  %t463 = getelementptr ptr, ptr %t450, i32 1
  %t464 = load ptr, ptr %t463
  %t465 = call ptr @malloc(i64 16)
  %t466 = inttoptr i64 0 to ptr
  %t467 = getelementptr ptr, ptr %t465, i32 0
  store ptr %t466, ptr %t467
  %t468 = getelementptr ptr, ptr %t465, i32 1
  store ptr %t464, ptr %t468
  br label %case.end.0.462
case.end.0.462:
  br label %case.join.460
case.arm.1.469:
  %t471 = getelementptr ptr, ptr %t450, i32 1
  %t472 = load ptr, ptr %t471
  %t473 = call ptr @malloc(i64 16)
  %t474 = inttoptr i64 1 to ptr
  %t475 = getelementptr ptr, ptr %t473, i32 0
  store ptr %t474, ptr %t475
  %t476 = call ptr @__concat(ptr %t472, ptr %t159)
  %t477 = getelementptr ptr, ptr %t473, i32 1
  store ptr %t476, ptr %t477
  %t478 = getelementptr ptr, ptr %t473, i32 0
  %t479 = load ptr, ptr %t478
  %t480 = ptrtoint ptr %t479 to i64
  switch i64 %t480, label %case.default.481 [ i64 0, label %case.arm.0.483 i64 1, label %case.arm.1.491 ]
case.arm.0.483:
  %t485 = getelementptr ptr, ptr %t473, i32 1
  %t486 = load ptr, ptr %t485
  %t487 = call ptr @malloc(i64 16)
  %t488 = inttoptr i64 0 to ptr
  %t489 = getelementptr ptr, ptr %t487, i32 0
  store ptr %t488, ptr %t489
  %t490 = getelementptr ptr, ptr %t487, i32 1
  store ptr %t486, ptr %t490
  br label %case.end.0.484
case.end.0.484:
  br label %case.join.482
case.arm.1.491:
  %t493 = getelementptr ptr, ptr %t473, i32 1
  %t494 = load ptr, ptr %t493
  %t495 = call ptr @malloc(i64 16)
  %t496 = inttoptr i64 1 to ptr
  %t497 = getelementptr ptr, ptr %t495, i32 0
  store ptr %t496, ptr %t497
  %t498 = getelementptr [3 x i8], ptr @.str.11, i64 0, i64 0
  %t499 = call ptr @__concat(ptr %t494, ptr %t498)
  %t500 = getelementptr ptr, ptr %t495, i32 1
  store ptr %t499, ptr %t500
  %t501 = getelementptr ptr, ptr %t495, i32 0
  %t502 = load ptr, ptr %t501
  %t503 = ptrtoint ptr %t502 to i64
  switch i64 %t503, label %case.default.504 [ i64 0, label %case.arm.0.506 i64 1, label %case.arm.1.514 ]
case.arm.0.506:
  %t508 = getelementptr ptr, ptr %t495, i32 1
  %t509 = load ptr, ptr %t508
  %t510 = call ptr @malloc(i64 16)
  %t511 = inttoptr i64 0 to ptr
  %t512 = getelementptr ptr, ptr %t510, i32 0
  store ptr %t511, ptr %t512
  %t513 = getelementptr ptr, ptr %t510, i32 1
  store ptr %t509, ptr %t513
  br label %case.end.0.507
case.end.0.507:
  br label %case.join.505
case.arm.1.514:
  %t516 = getelementptr ptr, ptr %t495, i32 1
  %t517 = load ptr, ptr %t516
  %t518 = call ptr @malloc(i64 16)
  %t519 = inttoptr i64 1 to ptr
  %t520 = getelementptr ptr, ptr %t518, i32 0
  store ptr %t519, ptr %t520
  %t521 = call ptr @__concat(ptr %t517, ptr %t179)
  %t522 = getelementptr ptr, ptr %t518, i32 1
  store ptr %t521, ptr %t522
  br label %case.end.1.515
case.end.1.515:
  br label %case.join.505
case.default.504:
  unreachable
case.join.505:
  %t523 = phi ptr [%t510, %case.end.0.507], [%t518, %case.end.1.515]
  br label %case.end.1.492
case.end.1.492:
  br label %case.join.482
case.default.481:
  unreachable
case.join.482:
  %t524 = phi ptr [%t487, %case.end.0.484], [%t523, %case.end.1.492]
  br label %case.end.1.470
case.end.1.470:
  br label %case.join.460
case.default.459:
  unreachable
case.join.460:
  %t525 = phi ptr [%t465, %case.end.0.462], [%t524, %case.end.1.470]
  br label %case.end.1.447
case.end.1.447:
  br label %case.join.437
case.default.436:
  unreachable
case.join.437:
  %t526 = phi ptr [%t442, %case.end.0.439], [%t525, %case.end.1.447]
  br label %case.end.1.425
case.end.1.425:
  br label %case.join.415
case.default.414:
  unreachable
case.join.415:
  %t527 = phi ptr [%t420, %case.end.0.417], [%t526, %case.end.1.425]
  br label %case.end.1.402
case.end.1.402:
  br label %case.join.392
case.default.391:
  unreachable
case.join.392:
  %t528 = phi ptr [%t397, %case.end.0.394], [%t527, %case.end.1.402]
  br label %case.end.1.380
case.end.1.380:
  br label %case.join.370
case.default.369:
  unreachable
case.join.370:
  %t529 = phi ptr [%t375, %case.end.0.372], [%t528, %case.end.1.380]
  br label %case.end.1.357
case.end.1.357:
  br label %case.join.347
case.default.346:
  unreachable
case.join.347:
  %t530 = phi ptr [%t352, %case.end.0.349], [%t529, %case.end.1.357]
  br label %case.end.1.335
case.end.1.335:
  br label %case.join.325
case.default.324:
  unreachable
case.join.325:
  %t531 = phi ptr [%t330, %case.end.0.327], [%t530, %case.end.1.335]
  br label %case.end.1.312
case.end.1.312:
  br label %case.join.302
case.default.301:
  unreachable
case.join.302:
  %t532 = phi ptr [%t307, %case.end.0.304], [%t531, %case.end.1.312]
  br label %case.end.1.290
case.end.1.290:
  br label %case.join.280
case.default.279:
  unreachable
case.join.280:
  %t533 = phi ptr [%t285, %case.end.0.282], [%t532, %case.end.1.290]
  br label %case.end.1.267
case.end.1.267:
  br label %case.join.257
case.default.256:
  unreachable
case.join.257:
  %t534 = phi ptr [%t262, %case.end.0.259], [%t533, %case.end.1.267]
  br label %case.end.1.245
case.end.1.245:
  br label %case.join.235
case.default.234:
  unreachable
case.join.235:
  %t535 = phi ptr [%t240, %case.end.0.237], [%t534, %case.end.1.245]
  br label %case.end.1.222
case.end.1.222:
  br label %case.join.212
case.default.211:
  unreachable
case.join.212:
  %t536 = phi ptr [%t217, %case.end.0.214], [%t535, %case.end.1.222]
  br label %case.end.1.200
case.end.1.200:
  br label %case.join.190
case.default.189:
  unreachable
case.join.190:
  %t537 = phi ptr [%t195, %case.end.0.192], [%t536, %case.end.1.200]
  br label %case.end.1.177
case.end.1.177:
  br label %case.join.167
case.default.166:
  unreachable
case.join.167:
  %t538 = phi ptr [%t172, %case.end.0.169], [%t537, %case.end.1.177]
  br label %case.end.1.157
case.end.1.157:
  br label %case.join.147
case.default.146:
  unreachable
case.join.147:
  %t539 = phi ptr [%t152, %case.end.0.149], [%t538, %case.end.1.157]
  br label %case.end.1.137
case.end.1.137:
  br label %case.join.127
case.default.126:
  unreachable
case.join.127:
  %t540 = phi ptr [%t132, %case.end.0.129], [%t539, %case.end.1.137]
  br label %case.end.1.117
case.end.1.117:
  br label %case.join.107
case.default.106:
  unreachable
case.join.107:
  %t541 = phi ptr [%t112, %case.end.0.109], [%t540, %case.end.1.117]
  br label %case.end.1.97
case.end.1.97:
  br label %case.join.87
case.default.86:
  unreachable
case.join.87:
  %t542 = phi ptr [%t92, %case.end.0.89], [%t541, %case.end.1.97]
  br label %case.end.1.77
case.end.1.77:
  br label %case.join.67
case.default.66:
  unreachable
case.join.67:
  %t543 = phi ptr [%t72, %case.end.0.69], [%t542, %case.end.1.77]
  br label %case.end.1.57
case.end.1.57:
  br label %case.join.47
case.default.46:
  unreachable
case.join.47:
  %t544 = phi ptr [%t52, %case.end.0.49], [%t543, %case.end.1.57]
  br label %case.end.1.37
case.end.1.37:
  br label %case.join.27
case.default.26:
  unreachable
case.join.27:
  %t545 = phi ptr [%t32, %case.end.0.29], [%t544, %case.end.1.37]
  br label %case.end.1.17
case.end.1.17:
  br label %case.join.7
case.default.6:
  unreachable
case.join.7:
  %t546 = phi ptr [%t12, %case.end.0.9], [%t545, %case.end.1.17]
  %t547 = call ptr @v__let_2(ptr %t546)
  ret ptr %t547
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
  %t12 = getelementptr [16 x i8], ptr @.str.12, i64 0, i64 0
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
