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
@.str.2 = private unnamed_addr constant [3 x i8] c"42\00"
@.str.3 = private unnamed_addr constant [4 x i8] c"-42\00"
@.str.4 = private unnamed_addr constant [2 x i8] c"0\00"
@.str.5 = private unnamed_addr constant [11 x i8] c"2147483647\00"
@.str.6 = private unnamed_addr constant [12 x i8] c"-2147483648\00"
@.str.7 = private unnamed_addr constant [11 x i8] c"2147483648\00"
@.str.8 = private unnamed_addr constant [12 x i8] c"-2147483649\00"
@.str.9 = private unnamed_addr constant [1 x i8] c"\00"
@.str.10 = private unnamed_addr constant [2 x i8] c"-\00"
@.str.11 = private unnamed_addr constant [4 x i8] c"+42\00"
@.str.12 = private unnamed_addr constant [4 x i8] c" 42\00"
@.str.13 = private unnamed_addr constant [6 x i8] c"12abc\00"
@.str.14 = private unnamed_addr constant [3 x i8] c", \00"
@.str.15 = private unnamed_addr constant [16 x i8] c"STRING_TOO_LONG\00"

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


define internal ptr @__parseInt32(ptr %s) {
entry:
  %neg_alloca = alloca i32, align 4
  store i32 0, ptr %neg_alloca
  %i_alloca = alloca i64, align 8
  store i64 0, ptr %i_alloca
  %acc_alloca = alloca i64, align 8
  store i64 0, ptr %acc_alloca
  %len = call i64 @strlen(ptr %s)
  %is_empty = icmp eq i64 %len, 0
  br i1 %is_empty, label %fail, label %check_sign
check_sign:
  %first = load i8, ptr %s
  %first_i32 = zext i8 %first to i32
  %is_neg = icmp eq i32 %first_i32, 45
  br i1 %is_neg, label %sign_minus, label %loop_head
sign_minus:
  %is_lone = icmp eq i64 %len, 1
  br i1 %is_lone, label %fail, label %sign_setup
sign_setup:
  store i32 1, ptr %neg_alloca
  store i64 1, ptr %i_alloca
  br label %loop_head
loop_head:
  %i = load i64, ptr %i_alloca
  %acc = load i64, ptr %acc_alloca
  %cond = icmp ult i64 %i, %len
  br i1 %cond, label %body, label %after
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
  %big = icmp ugt i64 %acc_next, 2147483648
  br i1 %big, label %fail, label %body_end
body_end:
  store i64 %acc_next, ptr %acc_alloca
  %i_next = add i64 %i, 1
  store i64 %i_next, ptr %i_alloca
  br label %loop_head
after:
  %neg_val = load i32, ptr %neg_alloca
  %is_neg2 = icmp ne i32 %neg_val, 0
  br i1 %is_neg2, label %finalize_neg, label %finalize_pos
finalize_pos:
  %big_pos = icmp ugt i64 %acc, 2147483647
  br i1 %big_pos, label %fail, label %ok_pos
finalize_neg:
  %acc_neg = sub i64 0, %acc
  br label %ok_neg
ok_pos:
  %result_pos = trunc i64 %acc to i32
  br label %build_right
ok_neg:
  %result_neg = trunc i64 %acc_neg to i32
  br label %build_right
build_right:
  %result = phi i32 [%result_pos, %ok_pos], [%result_neg, %ok_neg]
  %box = call ptr @malloc(i64 4)
  store i32 %result, ptr %box
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
  %t22 = call ptr @__showInt32(ptr %t17)
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
  %t0 = getelementptr [3 x i8], ptr @.str.2, i64 0, i64 0
  %t1 = call ptr @__parseInt32(ptr %t0)
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
  %t21 = call ptr @__parseInt32(ptr %t20)
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
  %t40 = getelementptr [2 x i8], ptr @.str.4, i64 0, i64 0
  %t41 = call ptr @__parseInt32(ptr %t40)
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
  %t60 = getelementptr [11 x i8], ptr @.str.5, i64 0, i64 0
  %t61 = call ptr @__parseInt32(ptr %t60)
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
  %t80 = getelementptr [12 x i8], ptr @.str.6, i64 0, i64 0
  %t81 = call ptr @__parseInt32(ptr %t80)
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
  %t100 = getelementptr [11 x i8], ptr @.str.7, i64 0, i64 0
  %t101 = call ptr @__parseInt32(ptr %t100)
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
  %t120 = getelementptr [12 x i8], ptr @.str.8, i64 0, i64 0
  %t121 = call ptr @__parseInt32(ptr %t120)
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
  %t140 = getelementptr [1 x i8], ptr @.str.9, i64 0, i64 0
  %t141 = call ptr @__parseInt32(ptr %t140)
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
  %t160 = getelementptr [2 x i8], ptr @.str.10, i64 0, i64 0
  %t161 = call ptr @__parseInt32(ptr %t160)
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
  %t180 = getelementptr [4 x i8], ptr @.str.11, i64 0, i64 0
  %t181 = call ptr @__parseInt32(ptr %t180)
  %t182 = call ptr @v_render(ptr %t181)
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
  %t200 = getelementptr [4 x i8], ptr @.str.12, i64 0, i64 0
  %t201 = call ptr @__parseInt32(ptr %t200)
  %t202 = call ptr @v_render(ptr %t201)
  %t203 = getelementptr ptr, ptr %t202, i32 0
  %t204 = load ptr, ptr %t203
  %t205 = ptrtoint ptr %t204 to i64
  switch i64 %t205, label %case.default.206 [ i64 0, label %case.arm.0.208 i64 1, label %case.arm.1.216 ]
case.arm.0.208:
  %t210 = getelementptr ptr, ptr %t202, i32 1
  %t211 = load ptr, ptr %t210
  %t212 = call ptr @malloc(i64 16)
  %t213 = inttoptr i64 0 to ptr
  %t214 = getelementptr ptr, ptr %t212, i32 0
  store ptr %t213, ptr %t214
  %t215 = getelementptr ptr, ptr %t212, i32 1
  store ptr %t211, ptr %t215
  br label %case.end.0.209
case.end.0.209:
  br label %case.join.207
case.arm.1.216:
  %t218 = getelementptr ptr, ptr %t202, i32 1
  %t219 = load ptr, ptr %t218
  %t220 = getelementptr [6 x i8], ptr @.str.13, i64 0, i64 0
  %t221 = call ptr @__parseInt32(ptr %t220)
  %t222 = call ptr @v_render(ptr %t221)
  %t223 = getelementptr ptr, ptr %t222, i32 0
  %t224 = load ptr, ptr %t223
  %t225 = ptrtoint ptr %t224 to i64
  switch i64 %t225, label %case.default.226 [ i64 0, label %case.arm.0.228 i64 1, label %case.arm.1.236 ]
case.arm.0.228:
  %t230 = getelementptr ptr, ptr %t222, i32 1
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
  %t238 = getelementptr ptr, ptr %t222, i32 1
  %t239 = load ptr, ptr %t238
  %t240 = call ptr @malloc(i64 16)
  %t241 = inttoptr i64 1 to ptr
  %t242 = getelementptr ptr, ptr %t240, i32 0
  store ptr %t241, ptr %t242
  %t243 = getelementptr [3 x i8], ptr @.str.14, i64 0, i64 0
  %t244 = call ptr @__concat(ptr %t19, ptr %t243)
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
  %t266 = call ptr @__concat(ptr %t262, ptr %t39)
  %t267 = getelementptr ptr, ptr %t263, i32 1
  store ptr %t266, ptr %t267
  %t268 = getelementptr ptr, ptr %t263, i32 0
  %t269 = load ptr, ptr %t268
  %t270 = ptrtoint ptr %t269 to i64
  switch i64 %t270, label %case.default.271 [ i64 0, label %case.arm.0.273 i64 1, label %case.arm.1.281 ]
case.arm.0.273:
  %t275 = getelementptr ptr, ptr %t263, i32 1
  %t276 = load ptr, ptr %t275
  %t277 = call ptr @malloc(i64 16)
  %t278 = inttoptr i64 0 to ptr
  %t279 = getelementptr ptr, ptr %t277, i32 0
  store ptr %t278, ptr %t279
  %t280 = getelementptr ptr, ptr %t277, i32 1
  store ptr %t276, ptr %t280
  br label %case.end.0.274
case.end.0.274:
  br label %case.join.272
case.arm.1.281:
  %t283 = getelementptr ptr, ptr %t263, i32 1
  %t284 = load ptr, ptr %t283
  %t285 = call ptr @malloc(i64 16)
  %t286 = inttoptr i64 1 to ptr
  %t287 = getelementptr ptr, ptr %t285, i32 0
  store ptr %t286, ptr %t287
  %t288 = getelementptr [3 x i8], ptr @.str.14, i64 0, i64 0
  %t289 = call ptr @__concat(ptr %t284, ptr %t288)
  %t290 = getelementptr ptr, ptr %t285, i32 1
  store ptr %t289, ptr %t290
  %t291 = getelementptr ptr, ptr %t285, i32 0
  %t292 = load ptr, ptr %t291
  %t293 = ptrtoint ptr %t292 to i64
  switch i64 %t293, label %case.default.294 [ i64 0, label %case.arm.0.296 i64 1, label %case.arm.1.304 ]
case.arm.0.296:
  %t298 = getelementptr ptr, ptr %t285, i32 1
  %t299 = load ptr, ptr %t298
  %t300 = call ptr @malloc(i64 16)
  %t301 = inttoptr i64 0 to ptr
  %t302 = getelementptr ptr, ptr %t300, i32 0
  store ptr %t301, ptr %t302
  %t303 = getelementptr ptr, ptr %t300, i32 1
  store ptr %t299, ptr %t303
  br label %case.end.0.297
case.end.0.297:
  br label %case.join.295
case.arm.1.304:
  %t306 = getelementptr ptr, ptr %t285, i32 1
  %t307 = load ptr, ptr %t306
  %t308 = call ptr @malloc(i64 16)
  %t309 = inttoptr i64 1 to ptr
  %t310 = getelementptr ptr, ptr %t308, i32 0
  store ptr %t309, ptr %t310
  %t311 = call ptr @__concat(ptr %t307, ptr %t59)
  %t312 = getelementptr ptr, ptr %t308, i32 1
  store ptr %t311, ptr %t312
  %t313 = getelementptr ptr, ptr %t308, i32 0
  %t314 = load ptr, ptr %t313
  %t315 = ptrtoint ptr %t314 to i64
  switch i64 %t315, label %case.default.316 [ i64 0, label %case.arm.0.318 i64 1, label %case.arm.1.326 ]
case.arm.0.318:
  %t320 = getelementptr ptr, ptr %t308, i32 1
  %t321 = load ptr, ptr %t320
  %t322 = call ptr @malloc(i64 16)
  %t323 = inttoptr i64 0 to ptr
  %t324 = getelementptr ptr, ptr %t322, i32 0
  store ptr %t323, ptr %t324
  %t325 = getelementptr ptr, ptr %t322, i32 1
  store ptr %t321, ptr %t325
  br label %case.end.0.319
case.end.0.319:
  br label %case.join.317
case.arm.1.326:
  %t328 = getelementptr ptr, ptr %t308, i32 1
  %t329 = load ptr, ptr %t328
  %t330 = call ptr @malloc(i64 16)
  %t331 = inttoptr i64 1 to ptr
  %t332 = getelementptr ptr, ptr %t330, i32 0
  store ptr %t331, ptr %t332
  %t333 = getelementptr [3 x i8], ptr @.str.14, i64 0, i64 0
  %t334 = call ptr @__concat(ptr %t329, ptr %t333)
  %t335 = getelementptr ptr, ptr %t330, i32 1
  store ptr %t334, ptr %t335
  %t336 = getelementptr ptr, ptr %t330, i32 0
  %t337 = load ptr, ptr %t336
  %t338 = ptrtoint ptr %t337 to i64
  switch i64 %t338, label %case.default.339 [ i64 0, label %case.arm.0.341 i64 1, label %case.arm.1.349 ]
case.arm.0.341:
  %t343 = getelementptr ptr, ptr %t330, i32 1
  %t344 = load ptr, ptr %t343
  %t345 = call ptr @malloc(i64 16)
  %t346 = inttoptr i64 0 to ptr
  %t347 = getelementptr ptr, ptr %t345, i32 0
  store ptr %t346, ptr %t347
  %t348 = getelementptr ptr, ptr %t345, i32 1
  store ptr %t344, ptr %t348
  br label %case.end.0.342
case.end.0.342:
  br label %case.join.340
case.arm.1.349:
  %t351 = getelementptr ptr, ptr %t330, i32 1
  %t352 = load ptr, ptr %t351
  %t353 = call ptr @malloc(i64 16)
  %t354 = inttoptr i64 1 to ptr
  %t355 = getelementptr ptr, ptr %t353, i32 0
  store ptr %t354, ptr %t355
  %t356 = call ptr @__concat(ptr %t352, ptr %t79)
  %t357 = getelementptr ptr, ptr %t353, i32 1
  store ptr %t356, ptr %t357
  %t358 = getelementptr ptr, ptr %t353, i32 0
  %t359 = load ptr, ptr %t358
  %t360 = ptrtoint ptr %t359 to i64
  switch i64 %t360, label %case.default.361 [ i64 0, label %case.arm.0.363 i64 1, label %case.arm.1.371 ]
case.arm.0.363:
  %t365 = getelementptr ptr, ptr %t353, i32 1
  %t366 = load ptr, ptr %t365
  %t367 = call ptr @malloc(i64 16)
  %t368 = inttoptr i64 0 to ptr
  %t369 = getelementptr ptr, ptr %t367, i32 0
  store ptr %t368, ptr %t369
  %t370 = getelementptr ptr, ptr %t367, i32 1
  store ptr %t366, ptr %t370
  br label %case.end.0.364
case.end.0.364:
  br label %case.join.362
case.arm.1.371:
  %t373 = getelementptr ptr, ptr %t353, i32 1
  %t374 = load ptr, ptr %t373
  %t375 = call ptr @malloc(i64 16)
  %t376 = inttoptr i64 1 to ptr
  %t377 = getelementptr ptr, ptr %t375, i32 0
  store ptr %t376, ptr %t377
  %t378 = getelementptr [3 x i8], ptr @.str.14, i64 0, i64 0
  %t379 = call ptr @__concat(ptr %t374, ptr %t378)
  %t380 = getelementptr ptr, ptr %t375, i32 1
  store ptr %t379, ptr %t380
  %t381 = getelementptr ptr, ptr %t375, i32 0
  %t382 = load ptr, ptr %t381
  %t383 = ptrtoint ptr %t382 to i64
  switch i64 %t383, label %case.default.384 [ i64 0, label %case.arm.0.386 i64 1, label %case.arm.1.394 ]
case.arm.0.386:
  %t388 = getelementptr ptr, ptr %t375, i32 1
  %t389 = load ptr, ptr %t388
  %t390 = call ptr @malloc(i64 16)
  %t391 = inttoptr i64 0 to ptr
  %t392 = getelementptr ptr, ptr %t390, i32 0
  store ptr %t391, ptr %t392
  %t393 = getelementptr ptr, ptr %t390, i32 1
  store ptr %t389, ptr %t393
  br label %case.end.0.387
case.end.0.387:
  br label %case.join.385
case.arm.1.394:
  %t396 = getelementptr ptr, ptr %t375, i32 1
  %t397 = load ptr, ptr %t396
  %t398 = call ptr @malloc(i64 16)
  %t399 = inttoptr i64 1 to ptr
  %t400 = getelementptr ptr, ptr %t398, i32 0
  store ptr %t399, ptr %t400
  %t401 = call ptr @__concat(ptr %t397, ptr %t99)
  %t402 = getelementptr ptr, ptr %t398, i32 1
  store ptr %t401, ptr %t402
  %t403 = getelementptr ptr, ptr %t398, i32 0
  %t404 = load ptr, ptr %t403
  %t405 = ptrtoint ptr %t404 to i64
  switch i64 %t405, label %case.default.406 [ i64 0, label %case.arm.0.408 i64 1, label %case.arm.1.416 ]
case.arm.0.408:
  %t410 = getelementptr ptr, ptr %t398, i32 1
  %t411 = load ptr, ptr %t410
  %t412 = call ptr @malloc(i64 16)
  %t413 = inttoptr i64 0 to ptr
  %t414 = getelementptr ptr, ptr %t412, i32 0
  store ptr %t413, ptr %t414
  %t415 = getelementptr ptr, ptr %t412, i32 1
  store ptr %t411, ptr %t415
  br label %case.end.0.409
case.end.0.409:
  br label %case.join.407
case.arm.1.416:
  %t418 = getelementptr ptr, ptr %t398, i32 1
  %t419 = load ptr, ptr %t418
  %t420 = call ptr @malloc(i64 16)
  %t421 = inttoptr i64 1 to ptr
  %t422 = getelementptr ptr, ptr %t420, i32 0
  store ptr %t421, ptr %t422
  %t423 = getelementptr [3 x i8], ptr @.str.14, i64 0, i64 0
  %t424 = call ptr @__concat(ptr %t419, ptr %t423)
  %t425 = getelementptr ptr, ptr %t420, i32 1
  store ptr %t424, ptr %t425
  %t426 = getelementptr ptr, ptr %t420, i32 0
  %t427 = load ptr, ptr %t426
  %t428 = ptrtoint ptr %t427 to i64
  switch i64 %t428, label %case.default.429 [ i64 0, label %case.arm.0.431 i64 1, label %case.arm.1.439 ]
case.arm.0.431:
  %t433 = getelementptr ptr, ptr %t420, i32 1
  %t434 = load ptr, ptr %t433
  %t435 = call ptr @malloc(i64 16)
  %t436 = inttoptr i64 0 to ptr
  %t437 = getelementptr ptr, ptr %t435, i32 0
  store ptr %t436, ptr %t437
  %t438 = getelementptr ptr, ptr %t435, i32 1
  store ptr %t434, ptr %t438
  br label %case.end.0.432
case.end.0.432:
  br label %case.join.430
case.arm.1.439:
  %t441 = getelementptr ptr, ptr %t420, i32 1
  %t442 = load ptr, ptr %t441
  %t443 = call ptr @malloc(i64 16)
  %t444 = inttoptr i64 1 to ptr
  %t445 = getelementptr ptr, ptr %t443, i32 0
  store ptr %t444, ptr %t445
  %t446 = call ptr @__concat(ptr %t442, ptr %t119)
  %t447 = getelementptr ptr, ptr %t443, i32 1
  store ptr %t446, ptr %t447
  %t448 = getelementptr ptr, ptr %t443, i32 0
  %t449 = load ptr, ptr %t448
  %t450 = ptrtoint ptr %t449 to i64
  switch i64 %t450, label %case.default.451 [ i64 0, label %case.arm.0.453 i64 1, label %case.arm.1.461 ]
case.arm.0.453:
  %t455 = getelementptr ptr, ptr %t443, i32 1
  %t456 = load ptr, ptr %t455
  %t457 = call ptr @malloc(i64 16)
  %t458 = inttoptr i64 0 to ptr
  %t459 = getelementptr ptr, ptr %t457, i32 0
  store ptr %t458, ptr %t459
  %t460 = getelementptr ptr, ptr %t457, i32 1
  store ptr %t456, ptr %t460
  br label %case.end.0.454
case.end.0.454:
  br label %case.join.452
case.arm.1.461:
  %t463 = getelementptr ptr, ptr %t443, i32 1
  %t464 = load ptr, ptr %t463
  %t465 = call ptr @malloc(i64 16)
  %t466 = inttoptr i64 1 to ptr
  %t467 = getelementptr ptr, ptr %t465, i32 0
  store ptr %t466, ptr %t467
  %t468 = getelementptr [3 x i8], ptr @.str.14, i64 0, i64 0
  %t469 = call ptr @__concat(ptr %t464, ptr %t468)
  %t470 = getelementptr ptr, ptr %t465, i32 1
  store ptr %t469, ptr %t470
  %t471 = getelementptr ptr, ptr %t465, i32 0
  %t472 = load ptr, ptr %t471
  %t473 = ptrtoint ptr %t472 to i64
  switch i64 %t473, label %case.default.474 [ i64 0, label %case.arm.0.476 i64 1, label %case.arm.1.484 ]
case.arm.0.476:
  %t478 = getelementptr ptr, ptr %t465, i32 1
  %t479 = load ptr, ptr %t478
  %t480 = call ptr @malloc(i64 16)
  %t481 = inttoptr i64 0 to ptr
  %t482 = getelementptr ptr, ptr %t480, i32 0
  store ptr %t481, ptr %t482
  %t483 = getelementptr ptr, ptr %t480, i32 1
  store ptr %t479, ptr %t483
  br label %case.end.0.477
case.end.0.477:
  br label %case.join.475
case.arm.1.484:
  %t486 = getelementptr ptr, ptr %t465, i32 1
  %t487 = load ptr, ptr %t486
  %t488 = call ptr @malloc(i64 16)
  %t489 = inttoptr i64 1 to ptr
  %t490 = getelementptr ptr, ptr %t488, i32 0
  store ptr %t489, ptr %t490
  %t491 = call ptr @__concat(ptr %t487, ptr %t139)
  %t492 = getelementptr ptr, ptr %t488, i32 1
  store ptr %t491, ptr %t492
  %t493 = getelementptr ptr, ptr %t488, i32 0
  %t494 = load ptr, ptr %t493
  %t495 = ptrtoint ptr %t494 to i64
  switch i64 %t495, label %case.default.496 [ i64 0, label %case.arm.0.498 i64 1, label %case.arm.1.506 ]
case.arm.0.498:
  %t500 = getelementptr ptr, ptr %t488, i32 1
  %t501 = load ptr, ptr %t500
  %t502 = call ptr @malloc(i64 16)
  %t503 = inttoptr i64 0 to ptr
  %t504 = getelementptr ptr, ptr %t502, i32 0
  store ptr %t503, ptr %t504
  %t505 = getelementptr ptr, ptr %t502, i32 1
  store ptr %t501, ptr %t505
  br label %case.end.0.499
case.end.0.499:
  br label %case.join.497
case.arm.1.506:
  %t508 = getelementptr ptr, ptr %t488, i32 1
  %t509 = load ptr, ptr %t508
  %t510 = call ptr @malloc(i64 16)
  %t511 = inttoptr i64 1 to ptr
  %t512 = getelementptr ptr, ptr %t510, i32 0
  store ptr %t511, ptr %t512
  %t513 = getelementptr [3 x i8], ptr @.str.14, i64 0, i64 0
  %t514 = call ptr @__concat(ptr %t509, ptr %t513)
  %t515 = getelementptr ptr, ptr %t510, i32 1
  store ptr %t514, ptr %t515
  %t516 = getelementptr ptr, ptr %t510, i32 0
  %t517 = load ptr, ptr %t516
  %t518 = ptrtoint ptr %t517 to i64
  switch i64 %t518, label %case.default.519 [ i64 0, label %case.arm.0.521 i64 1, label %case.arm.1.529 ]
case.arm.0.521:
  %t523 = getelementptr ptr, ptr %t510, i32 1
  %t524 = load ptr, ptr %t523
  %t525 = call ptr @malloc(i64 16)
  %t526 = inttoptr i64 0 to ptr
  %t527 = getelementptr ptr, ptr %t525, i32 0
  store ptr %t526, ptr %t527
  %t528 = getelementptr ptr, ptr %t525, i32 1
  store ptr %t524, ptr %t528
  br label %case.end.0.522
case.end.0.522:
  br label %case.join.520
case.arm.1.529:
  %t531 = getelementptr ptr, ptr %t510, i32 1
  %t532 = load ptr, ptr %t531
  %t533 = call ptr @malloc(i64 16)
  %t534 = inttoptr i64 1 to ptr
  %t535 = getelementptr ptr, ptr %t533, i32 0
  store ptr %t534, ptr %t535
  %t536 = call ptr @__concat(ptr %t532, ptr %t159)
  %t537 = getelementptr ptr, ptr %t533, i32 1
  store ptr %t536, ptr %t537
  %t538 = getelementptr ptr, ptr %t533, i32 0
  %t539 = load ptr, ptr %t538
  %t540 = ptrtoint ptr %t539 to i64
  switch i64 %t540, label %case.default.541 [ i64 0, label %case.arm.0.543 i64 1, label %case.arm.1.551 ]
case.arm.0.543:
  %t545 = getelementptr ptr, ptr %t533, i32 1
  %t546 = load ptr, ptr %t545
  %t547 = call ptr @malloc(i64 16)
  %t548 = inttoptr i64 0 to ptr
  %t549 = getelementptr ptr, ptr %t547, i32 0
  store ptr %t548, ptr %t549
  %t550 = getelementptr ptr, ptr %t547, i32 1
  store ptr %t546, ptr %t550
  br label %case.end.0.544
case.end.0.544:
  br label %case.join.542
case.arm.1.551:
  %t553 = getelementptr ptr, ptr %t533, i32 1
  %t554 = load ptr, ptr %t553
  %t555 = call ptr @malloc(i64 16)
  %t556 = inttoptr i64 1 to ptr
  %t557 = getelementptr ptr, ptr %t555, i32 0
  store ptr %t556, ptr %t557
  %t558 = getelementptr [3 x i8], ptr @.str.14, i64 0, i64 0
  %t559 = call ptr @__concat(ptr %t554, ptr %t558)
  %t560 = getelementptr ptr, ptr %t555, i32 1
  store ptr %t559, ptr %t560
  %t561 = getelementptr ptr, ptr %t555, i32 0
  %t562 = load ptr, ptr %t561
  %t563 = ptrtoint ptr %t562 to i64
  switch i64 %t563, label %case.default.564 [ i64 0, label %case.arm.0.566 i64 1, label %case.arm.1.574 ]
case.arm.0.566:
  %t568 = getelementptr ptr, ptr %t555, i32 1
  %t569 = load ptr, ptr %t568
  %t570 = call ptr @malloc(i64 16)
  %t571 = inttoptr i64 0 to ptr
  %t572 = getelementptr ptr, ptr %t570, i32 0
  store ptr %t571, ptr %t572
  %t573 = getelementptr ptr, ptr %t570, i32 1
  store ptr %t569, ptr %t573
  br label %case.end.0.567
case.end.0.567:
  br label %case.join.565
case.arm.1.574:
  %t576 = getelementptr ptr, ptr %t555, i32 1
  %t577 = load ptr, ptr %t576
  %t578 = call ptr @malloc(i64 16)
  %t579 = inttoptr i64 1 to ptr
  %t580 = getelementptr ptr, ptr %t578, i32 0
  store ptr %t579, ptr %t580
  %t581 = call ptr @__concat(ptr %t577, ptr %t179)
  %t582 = getelementptr ptr, ptr %t578, i32 1
  store ptr %t581, ptr %t582
  %t583 = getelementptr ptr, ptr %t578, i32 0
  %t584 = load ptr, ptr %t583
  %t585 = ptrtoint ptr %t584 to i64
  switch i64 %t585, label %case.default.586 [ i64 0, label %case.arm.0.588 i64 1, label %case.arm.1.596 ]
case.arm.0.588:
  %t590 = getelementptr ptr, ptr %t578, i32 1
  %t591 = load ptr, ptr %t590
  %t592 = call ptr @malloc(i64 16)
  %t593 = inttoptr i64 0 to ptr
  %t594 = getelementptr ptr, ptr %t592, i32 0
  store ptr %t593, ptr %t594
  %t595 = getelementptr ptr, ptr %t592, i32 1
  store ptr %t591, ptr %t595
  br label %case.end.0.589
case.end.0.589:
  br label %case.join.587
case.arm.1.596:
  %t598 = getelementptr ptr, ptr %t578, i32 1
  %t599 = load ptr, ptr %t598
  %t600 = call ptr @malloc(i64 16)
  %t601 = inttoptr i64 1 to ptr
  %t602 = getelementptr ptr, ptr %t600, i32 0
  store ptr %t601, ptr %t602
  %t603 = getelementptr [3 x i8], ptr @.str.14, i64 0, i64 0
  %t604 = call ptr @__concat(ptr %t599, ptr %t603)
  %t605 = getelementptr ptr, ptr %t600, i32 1
  store ptr %t604, ptr %t605
  %t606 = getelementptr ptr, ptr %t600, i32 0
  %t607 = load ptr, ptr %t606
  %t608 = ptrtoint ptr %t607 to i64
  switch i64 %t608, label %case.default.609 [ i64 0, label %case.arm.0.611 i64 1, label %case.arm.1.619 ]
case.arm.0.611:
  %t613 = getelementptr ptr, ptr %t600, i32 1
  %t614 = load ptr, ptr %t613
  %t615 = call ptr @malloc(i64 16)
  %t616 = inttoptr i64 0 to ptr
  %t617 = getelementptr ptr, ptr %t615, i32 0
  store ptr %t616, ptr %t617
  %t618 = getelementptr ptr, ptr %t615, i32 1
  store ptr %t614, ptr %t618
  br label %case.end.0.612
case.end.0.612:
  br label %case.join.610
case.arm.1.619:
  %t621 = getelementptr ptr, ptr %t600, i32 1
  %t622 = load ptr, ptr %t621
  %t623 = call ptr @malloc(i64 16)
  %t624 = inttoptr i64 1 to ptr
  %t625 = getelementptr ptr, ptr %t623, i32 0
  store ptr %t624, ptr %t625
  %t626 = call ptr @__concat(ptr %t622, ptr %t199)
  %t627 = getelementptr ptr, ptr %t623, i32 1
  store ptr %t626, ptr %t627
  %t628 = getelementptr ptr, ptr %t623, i32 0
  %t629 = load ptr, ptr %t628
  %t630 = ptrtoint ptr %t629 to i64
  switch i64 %t630, label %case.default.631 [ i64 0, label %case.arm.0.633 i64 1, label %case.arm.1.641 ]
case.arm.0.633:
  %t635 = getelementptr ptr, ptr %t623, i32 1
  %t636 = load ptr, ptr %t635
  %t637 = call ptr @malloc(i64 16)
  %t638 = inttoptr i64 0 to ptr
  %t639 = getelementptr ptr, ptr %t637, i32 0
  store ptr %t638, ptr %t639
  %t640 = getelementptr ptr, ptr %t637, i32 1
  store ptr %t636, ptr %t640
  br label %case.end.0.634
case.end.0.634:
  br label %case.join.632
case.arm.1.641:
  %t643 = getelementptr ptr, ptr %t623, i32 1
  %t644 = load ptr, ptr %t643
  %t645 = call ptr @malloc(i64 16)
  %t646 = inttoptr i64 1 to ptr
  %t647 = getelementptr ptr, ptr %t645, i32 0
  store ptr %t646, ptr %t647
  %t648 = getelementptr [3 x i8], ptr @.str.14, i64 0, i64 0
  %t649 = call ptr @__concat(ptr %t644, ptr %t648)
  %t650 = getelementptr ptr, ptr %t645, i32 1
  store ptr %t649, ptr %t650
  %t651 = getelementptr ptr, ptr %t645, i32 0
  %t652 = load ptr, ptr %t651
  %t653 = ptrtoint ptr %t652 to i64
  switch i64 %t653, label %case.default.654 [ i64 0, label %case.arm.0.656 i64 1, label %case.arm.1.664 ]
case.arm.0.656:
  %t658 = getelementptr ptr, ptr %t645, i32 1
  %t659 = load ptr, ptr %t658
  %t660 = call ptr @malloc(i64 16)
  %t661 = inttoptr i64 0 to ptr
  %t662 = getelementptr ptr, ptr %t660, i32 0
  store ptr %t661, ptr %t662
  %t663 = getelementptr ptr, ptr %t660, i32 1
  store ptr %t659, ptr %t663
  br label %case.end.0.657
case.end.0.657:
  br label %case.join.655
case.arm.1.664:
  %t666 = getelementptr ptr, ptr %t645, i32 1
  %t667 = load ptr, ptr %t666
  %t668 = call ptr @malloc(i64 16)
  %t669 = inttoptr i64 1 to ptr
  %t670 = getelementptr ptr, ptr %t668, i32 0
  store ptr %t669, ptr %t670
  %t671 = call ptr @__concat(ptr %t667, ptr %t219)
  %t672 = getelementptr ptr, ptr %t668, i32 1
  store ptr %t671, ptr %t672
  %t673 = getelementptr ptr, ptr %t668, i32 0
  %t674 = load ptr, ptr %t673
  %t675 = ptrtoint ptr %t674 to i64
  switch i64 %t675, label %case.default.676 [ i64 0, label %case.arm.0.678 i64 1, label %case.arm.1.686 ]
case.arm.0.678:
  %t680 = getelementptr ptr, ptr %t668, i32 1
  %t681 = load ptr, ptr %t680
  %t682 = call ptr @malloc(i64 16)
  %t683 = inttoptr i64 0 to ptr
  %t684 = getelementptr ptr, ptr %t682, i32 0
  store ptr %t683, ptr %t684
  %t685 = getelementptr ptr, ptr %t682, i32 1
  store ptr %t681, ptr %t685
  br label %case.end.0.679
case.end.0.679:
  br label %case.join.677
case.arm.1.686:
  %t688 = getelementptr ptr, ptr %t668, i32 1
  %t689 = load ptr, ptr %t688
  %t690 = call ptr @malloc(i64 16)
  %t691 = inttoptr i64 1 to ptr
  %t692 = getelementptr ptr, ptr %t690, i32 0
  store ptr %t691, ptr %t692
  %t693 = getelementptr [3 x i8], ptr @.str.14, i64 0, i64 0
  %t694 = call ptr @__concat(ptr %t689, ptr %t693)
  %t695 = getelementptr ptr, ptr %t690, i32 1
  store ptr %t694, ptr %t695
  %t696 = getelementptr ptr, ptr %t690, i32 0
  %t697 = load ptr, ptr %t696
  %t698 = ptrtoint ptr %t697 to i64
  switch i64 %t698, label %case.default.699 [ i64 0, label %case.arm.0.701 i64 1, label %case.arm.1.709 ]
case.arm.0.701:
  %t703 = getelementptr ptr, ptr %t690, i32 1
  %t704 = load ptr, ptr %t703
  %t705 = call ptr @malloc(i64 16)
  %t706 = inttoptr i64 0 to ptr
  %t707 = getelementptr ptr, ptr %t705, i32 0
  store ptr %t706, ptr %t707
  %t708 = getelementptr ptr, ptr %t705, i32 1
  store ptr %t704, ptr %t708
  br label %case.end.0.702
case.end.0.702:
  br label %case.join.700
case.arm.1.709:
  %t711 = getelementptr ptr, ptr %t690, i32 1
  %t712 = load ptr, ptr %t711
  %t713 = call ptr @malloc(i64 16)
  %t714 = inttoptr i64 1 to ptr
  %t715 = getelementptr ptr, ptr %t713, i32 0
  store ptr %t714, ptr %t715
  %t716 = call ptr @__concat(ptr %t712, ptr %t239)
  %t717 = getelementptr ptr, ptr %t713, i32 1
  store ptr %t716, ptr %t717
  br label %case.end.1.710
case.end.1.710:
  br label %case.join.700
case.default.699:
  unreachable
case.join.700:
  %t718 = phi ptr [%t705, %case.end.0.702], [%t713, %case.end.1.710]
  br label %case.end.1.687
case.end.1.687:
  br label %case.join.677
case.default.676:
  unreachable
case.join.677:
  %t719 = phi ptr [%t682, %case.end.0.679], [%t718, %case.end.1.687]
  br label %case.end.1.665
case.end.1.665:
  br label %case.join.655
case.default.654:
  unreachable
case.join.655:
  %t720 = phi ptr [%t660, %case.end.0.657], [%t719, %case.end.1.665]
  br label %case.end.1.642
case.end.1.642:
  br label %case.join.632
case.default.631:
  unreachable
case.join.632:
  %t721 = phi ptr [%t637, %case.end.0.634], [%t720, %case.end.1.642]
  br label %case.end.1.620
case.end.1.620:
  br label %case.join.610
case.default.609:
  unreachable
case.join.610:
  %t722 = phi ptr [%t615, %case.end.0.612], [%t721, %case.end.1.620]
  br label %case.end.1.597
case.end.1.597:
  br label %case.join.587
case.default.586:
  unreachable
case.join.587:
  %t723 = phi ptr [%t592, %case.end.0.589], [%t722, %case.end.1.597]
  br label %case.end.1.575
case.end.1.575:
  br label %case.join.565
case.default.564:
  unreachable
case.join.565:
  %t724 = phi ptr [%t570, %case.end.0.567], [%t723, %case.end.1.575]
  br label %case.end.1.552
case.end.1.552:
  br label %case.join.542
case.default.541:
  unreachable
case.join.542:
  %t725 = phi ptr [%t547, %case.end.0.544], [%t724, %case.end.1.552]
  br label %case.end.1.530
case.end.1.530:
  br label %case.join.520
case.default.519:
  unreachable
case.join.520:
  %t726 = phi ptr [%t525, %case.end.0.522], [%t725, %case.end.1.530]
  br label %case.end.1.507
case.end.1.507:
  br label %case.join.497
case.default.496:
  unreachable
case.join.497:
  %t727 = phi ptr [%t502, %case.end.0.499], [%t726, %case.end.1.507]
  br label %case.end.1.485
case.end.1.485:
  br label %case.join.475
case.default.474:
  unreachable
case.join.475:
  %t728 = phi ptr [%t480, %case.end.0.477], [%t727, %case.end.1.485]
  br label %case.end.1.462
case.end.1.462:
  br label %case.join.452
case.default.451:
  unreachable
case.join.452:
  %t729 = phi ptr [%t457, %case.end.0.454], [%t728, %case.end.1.462]
  br label %case.end.1.440
case.end.1.440:
  br label %case.join.430
case.default.429:
  unreachable
case.join.430:
  %t730 = phi ptr [%t435, %case.end.0.432], [%t729, %case.end.1.440]
  br label %case.end.1.417
case.end.1.417:
  br label %case.join.407
case.default.406:
  unreachable
case.join.407:
  %t731 = phi ptr [%t412, %case.end.0.409], [%t730, %case.end.1.417]
  br label %case.end.1.395
case.end.1.395:
  br label %case.join.385
case.default.384:
  unreachable
case.join.385:
  %t732 = phi ptr [%t390, %case.end.0.387], [%t731, %case.end.1.395]
  br label %case.end.1.372
case.end.1.372:
  br label %case.join.362
case.default.361:
  unreachable
case.join.362:
  %t733 = phi ptr [%t367, %case.end.0.364], [%t732, %case.end.1.372]
  br label %case.end.1.350
case.end.1.350:
  br label %case.join.340
case.default.339:
  unreachable
case.join.340:
  %t734 = phi ptr [%t345, %case.end.0.342], [%t733, %case.end.1.350]
  br label %case.end.1.327
case.end.1.327:
  br label %case.join.317
case.default.316:
  unreachable
case.join.317:
  %t735 = phi ptr [%t322, %case.end.0.319], [%t734, %case.end.1.327]
  br label %case.end.1.305
case.end.1.305:
  br label %case.join.295
case.default.294:
  unreachable
case.join.295:
  %t736 = phi ptr [%t300, %case.end.0.297], [%t735, %case.end.1.305]
  br label %case.end.1.282
case.end.1.282:
  br label %case.join.272
case.default.271:
  unreachable
case.join.272:
  %t737 = phi ptr [%t277, %case.end.0.274], [%t736, %case.end.1.282]
  br label %case.end.1.260
case.end.1.260:
  br label %case.join.250
case.default.249:
  unreachable
case.join.250:
  %t738 = phi ptr [%t255, %case.end.0.252], [%t737, %case.end.1.260]
  br label %case.end.1.237
case.end.1.237:
  br label %case.join.227
case.default.226:
  unreachable
case.join.227:
  %t739 = phi ptr [%t232, %case.end.0.229], [%t738, %case.end.1.237]
  br label %case.end.1.217
case.end.1.217:
  br label %case.join.207
case.default.206:
  unreachable
case.join.207:
  %t740 = phi ptr [%t212, %case.end.0.209], [%t739, %case.end.1.217]
  br label %case.end.1.197
case.end.1.197:
  br label %case.join.187
case.default.186:
  unreachable
case.join.187:
  %t741 = phi ptr [%t192, %case.end.0.189], [%t740, %case.end.1.197]
  br label %case.end.1.177
case.end.1.177:
  br label %case.join.167
case.default.166:
  unreachable
case.join.167:
  %t742 = phi ptr [%t172, %case.end.0.169], [%t741, %case.end.1.177]
  br label %case.end.1.157
case.end.1.157:
  br label %case.join.147
case.default.146:
  unreachable
case.join.147:
  %t743 = phi ptr [%t152, %case.end.0.149], [%t742, %case.end.1.157]
  br label %case.end.1.137
case.end.1.137:
  br label %case.join.127
case.default.126:
  unreachable
case.join.127:
  %t744 = phi ptr [%t132, %case.end.0.129], [%t743, %case.end.1.137]
  br label %case.end.1.117
case.end.1.117:
  br label %case.join.107
case.default.106:
  unreachable
case.join.107:
  %t745 = phi ptr [%t112, %case.end.0.109], [%t744, %case.end.1.117]
  br label %case.end.1.97
case.end.1.97:
  br label %case.join.87
case.default.86:
  unreachable
case.join.87:
  %t746 = phi ptr [%t92, %case.end.0.89], [%t745, %case.end.1.97]
  br label %case.end.1.77
case.end.1.77:
  br label %case.join.67
case.default.66:
  unreachable
case.join.67:
  %t747 = phi ptr [%t72, %case.end.0.69], [%t746, %case.end.1.77]
  br label %case.end.1.57
case.end.1.57:
  br label %case.join.47
case.default.46:
  unreachable
case.join.47:
  %t748 = phi ptr [%t52, %case.end.0.49], [%t747, %case.end.1.57]
  br label %case.end.1.37
case.end.1.37:
  br label %case.join.27
case.default.26:
  unreachable
case.join.27:
  %t749 = phi ptr [%t32, %case.end.0.29], [%t748, %case.end.1.37]
  br label %case.end.1.17
case.end.1.17:
  br label %case.join.7
case.default.6:
  unreachable
case.join.7:
  %t750 = phi ptr [%t12, %case.end.0.9], [%t749, %case.end.1.17]
  %t751 = call ptr @v__let_2(ptr %t750)
  ret ptr %t751
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
  %t12 = getelementptr [16 x i8], ptr @.str.15, i64 0, i64 0
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
