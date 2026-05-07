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
  %t18 = getelementptr [4 x i8], ptr @.str.1, i64 0, i64 0
  %t19 = call ptr @__showUInt8(ptr %t17)
  %t20 = call ptr @__concat(ptr %t18, ptr %t19)
  br label %case.end.1.15
case.end.1.15:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t21 = phi ptr [%t9, %case.end.0.6], [%t20, %case.end.1.15]
  ret ptr %t21
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
  %t160 = getelementptr [3 x i8], ptr @.str.10, i64 0, i64 0
  %t161 = call ptr @__concat(ptr %t19, ptr %t160)
  %t162 = getelementptr ptr, ptr %t161, i32 0
  %t163 = load ptr, ptr %t162
  %t164 = ptrtoint ptr %t163 to i64
  switch i64 %t164, label %case.default.165 [ i64 0, label %case.arm.0.167 i64 1, label %case.arm.1.175 ]
case.arm.0.167:
  %t169 = getelementptr ptr, ptr %t161, i32 1
  %t170 = load ptr, ptr %t169
  %t171 = call ptr @malloc(i64 16)
  %t172 = inttoptr i64 0 to ptr
  %t173 = getelementptr ptr, ptr %t171, i32 0
  store ptr %t172, ptr %t173
  %t174 = getelementptr ptr, ptr %t171, i32 1
  store ptr %t170, ptr %t174
  br label %case.end.0.168
case.end.0.168:
  br label %case.join.166
case.arm.1.175:
  %t177 = getelementptr ptr, ptr %t161, i32 1
  %t178 = load ptr, ptr %t177
  %t179 = call ptr @__concat(ptr %t178, ptr %t39)
  %t180 = getelementptr ptr, ptr %t179, i32 0
  %t181 = load ptr, ptr %t180
  %t182 = ptrtoint ptr %t181 to i64
  switch i64 %t182, label %case.default.183 [ i64 0, label %case.arm.0.185 i64 1, label %case.arm.1.193 ]
case.arm.0.185:
  %t187 = getelementptr ptr, ptr %t179, i32 1
  %t188 = load ptr, ptr %t187
  %t189 = call ptr @malloc(i64 16)
  %t190 = inttoptr i64 0 to ptr
  %t191 = getelementptr ptr, ptr %t189, i32 0
  store ptr %t190, ptr %t191
  %t192 = getelementptr ptr, ptr %t189, i32 1
  store ptr %t188, ptr %t192
  br label %case.end.0.186
case.end.0.186:
  br label %case.join.184
case.arm.1.193:
  %t195 = getelementptr ptr, ptr %t179, i32 1
  %t196 = load ptr, ptr %t195
  %t197 = getelementptr [3 x i8], ptr @.str.10, i64 0, i64 0
  %t198 = call ptr @__concat(ptr %t196, ptr %t197)
  %t199 = getelementptr ptr, ptr %t198, i32 0
  %t200 = load ptr, ptr %t199
  %t201 = ptrtoint ptr %t200 to i64
  switch i64 %t201, label %case.default.202 [ i64 0, label %case.arm.0.204 i64 1, label %case.arm.1.212 ]
case.arm.0.204:
  %t206 = getelementptr ptr, ptr %t198, i32 1
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
  %t214 = getelementptr ptr, ptr %t198, i32 1
  %t215 = load ptr, ptr %t214
  %t216 = call ptr @__concat(ptr %t215, ptr %t59)
  %t217 = getelementptr ptr, ptr %t216, i32 0
  %t218 = load ptr, ptr %t217
  %t219 = ptrtoint ptr %t218 to i64
  switch i64 %t219, label %case.default.220 [ i64 0, label %case.arm.0.222 i64 1, label %case.arm.1.230 ]
case.arm.0.222:
  %t224 = getelementptr ptr, ptr %t216, i32 1
  %t225 = load ptr, ptr %t224
  %t226 = call ptr @malloc(i64 16)
  %t227 = inttoptr i64 0 to ptr
  %t228 = getelementptr ptr, ptr %t226, i32 0
  store ptr %t227, ptr %t228
  %t229 = getelementptr ptr, ptr %t226, i32 1
  store ptr %t225, ptr %t229
  br label %case.end.0.223
case.end.0.223:
  br label %case.join.221
case.arm.1.230:
  %t232 = getelementptr ptr, ptr %t216, i32 1
  %t233 = load ptr, ptr %t232
  %t234 = getelementptr [3 x i8], ptr @.str.10, i64 0, i64 0
  %t235 = call ptr @__concat(ptr %t233, ptr %t234)
  %t236 = getelementptr ptr, ptr %t235, i32 0
  %t237 = load ptr, ptr %t236
  %t238 = ptrtoint ptr %t237 to i64
  switch i64 %t238, label %case.default.239 [ i64 0, label %case.arm.0.241 i64 1, label %case.arm.1.249 ]
case.arm.0.241:
  %t243 = getelementptr ptr, ptr %t235, i32 1
  %t244 = load ptr, ptr %t243
  %t245 = call ptr @malloc(i64 16)
  %t246 = inttoptr i64 0 to ptr
  %t247 = getelementptr ptr, ptr %t245, i32 0
  store ptr %t246, ptr %t247
  %t248 = getelementptr ptr, ptr %t245, i32 1
  store ptr %t244, ptr %t248
  br label %case.end.0.242
case.end.0.242:
  br label %case.join.240
case.arm.1.249:
  %t251 = getelementptr ptr, ptr %t235, i32 1
  %t252 = load ptr, ptr %t251
  %t253 = call ptr @__concat(ptr %t252, ptr %t79)
  %t254 = getelementptr ptr, ptr %t253, i32 0
  %t255 = load ptr, ptr %t254
  %t256 = ptrtoint ptr %t255 to i64
  switch i64 %t256, label %case.default.257 [ i64 0, label %case.arm.0.259 i64 1, label %case.arm.1.267 ]
case.arm.0.259:
  %t261 = getelementptr ptr, ptr %t253, i32 1
  %t262 = load ptr, ptr %t261
  %t263 = call ptr @malloc(i64 16)
  %t264 = inttoptr i64 0 to ptr
  %t265 = getelementptr ptr, ptr %t263, i32 0
  store ptr %t264, ptr %t265
  %t266 = getelementptr ptr, ptr %t263, i32 1
  store ptr %t262, ptr %t266
  br label %case.end.0.260
case.end.0.260:
  br label %case.join.258
case.arm.1.267:
  %t269 = getelementptr ptr, ptr %t253, i32 1
  %t270 = load ptr, ptr %t269
  %t271 = getelementptr [3 x i8], ptr @.str.10, i64 0, i64 0
  %t272 = call ptr @__concat(ptr %t270, ptr %t271)
  %t273 = getelementptr ptr, ptr %t272, i32 0
  %t274 = load ptr, ptr %t273
  %t275 = ptrtoint ptr %t274 to i64
  switch i64 %t275, label %case.default.276 [ i64 0, label %case.arm.0.278 i64 1, label %case.arm.1.286 ]
case.arm.0.278:
  %t280 = getelementptr ptr, ptr %t272, i32 1
  %t281 = load ptr, ptr %t280
  %t282 = call ptr @malloc(i64 16)
  %t283 = inttoptr i64 0 to ptr
  %t284 = getelementptr ptr, ptr %t282, i32 0
  store ptr %t283, ptr %t284
  %t285 = getelementptr ptr, ptr %t282, i32 1
  store ptr %t281, ptr %t285
  br label %case.end.0.279
case.end.0.279:
  br label %case.join.277
case.arm.1.286:
  %t288 = getelementptr ptr, ptr %t272, i32 1
  %t289 = load ptr, ptr %t288
  %t290 = call ptr @__concat(ptr %t289, ptr %t99)
  %t291 = getelementptr ptr, ptr %t290, i32 0
  %t292 = load ptr, ptr %t291
  %t293 = ptrtoint ptr %t292 to i64
  switch i64 %t293, label %case.default.294 [ i64 0, label %case.arm.0.296 i64 1, label %case.arm.1.304 ]
case.arm.0.296:
  %t298 = getelementptr ptr, ptr %t290, i32 1
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
  %t306 = getelementptr ptr, ptr %t290, i32 1
  %t307 = load ptr, ptr %t306
  %t308 = getelementptr [3 x i8], ptr @.str.10, i64 0, i64 0
  %t309 = call ptr @__concat(ptr %t307, ptr %t308)
  %t310 = getelementptr ptr, ptr %t309, i32 0
  %t311 = load ptr, ptr %t310
  %t312 = ptrtoint ptr %t311 to i64
  switch i64 %t312, label %case.default.313 [ i64 0, label %case.arm.0.315 i64 1, label %case.arm.1.323 ]
case.arm.0.315:
  %t317 = getelementptr ptr, ptr %t309, i32 1
  %t318 = load ptr, ptr %t317
  %t319 = call ptr @malloc(i64 16)
  %t320 = inttoptr i64 0 to ptr
  %t321 = getelementptr ptr, ptr %t319, i32 0
  store ptr %t320, ptr %t321
  %t322 = getelementptr ptr, ptr %t319, i32 1
  store ptr %t318, ptr %t322
  br label %case.end.0.316
case.end.0.316:
  br label %case.join.314
case.arm.1.323:
  %t325 = getelementptr ptr, ptr %t309, i32 1
  %t326 = load ptr, ptr %t325
  %t327 = call ptr @__concat(ptr %t326, ptr %t119)
  %t328 = getelementptr ptr, ptr %t327, i32 0
  %t329 = load ptr, ptr %t328
  %t330 = ptrtoint ptr %t329 to i64
  switch i64 %t330, label %case.default.331 [ i64 0, label %case.arm.0.333 i64 1, label %case.arm.1.341 ]
case.arm.0.333:
  %t335 = getelementptr ptr, ptr %t327, i32 1
  %t336 = load ptr, ptr %t335
  %t337 = call ptr @malloc(i64 16)
  %t338 = inttoptr i64 0 to ptr
  %t339 = getelementptr ptr, ptr %t337, i32 0
  store ptr %t338, ptr %t339
  %t340 = getelementptr ptr, ptr %t337, i32 1
  store ptr %t336, ptr %t340
  br label %case.end.0.334
case.end.0.334:
  br label %case.join.332
case.arm.1.341:
  %t343 = getelementptr ptr, ptr %t327, i32 1
  %t344 = load ptr, ptr %t343
  %t345 = getelementptr [3 x i8], ptr @.str.10, i64 0, i64 0
  %t346 = call ptr @__concat(ptr %t344, ptr %t345)
  %t347 = getelementptr ptr, ptr %t346, i32 0
  %t348 = load ptr, ptr %t347
  %t349 = ptrtoint ptr %t348 to i64
  switch i64 %t349, label %case.default.350 [ i64 0, label %case.arm.0.352 i64 1, label %case.arm.1.360 ]
case.arm.0.352:
  %t354 = getelementptr ptr, ptr %t346, i32 1
  %t355 = load ptr, ptr %t354
  %t356 = call ptr @malloc(i64 16)
  %t357 = inttoptr i64 0 to ptr
  %t358 = getelementptr ptr, ptr %t356, i32 0
  store ptr %t357, ptr %t358
  %t359 = getelementptr ptr, ptr %t356, i32 1
  store ptr %t355, ptr %t359
  br label %case.end.0.353
case.end.0.353:
  br label %case.join.351
case.arm.1.360:
  %t362 = getelementptr ptr, ptr %t346, i32 1
  %t363 = load ptr, ptr %t362
  %t364 = call ptr @__concat(ptr %t363, ptr %t139)
  %t365 = getelementptr ptr, ptr %t364, i32 0
  %t366 = load ptr, ptr %t365
  %t367 = ptrtoint ptr %t366 to i64
  switch i64 %t367, label %case.default.368 [ i64 0, label %case.arm.0.370 i64 1, label %case.arm.1.378 ]
case.arm.0.370:
  %t372 = getelementptr ptr, ptr %t364, i32 1
  %t373 = load ptr, ptr %t372
  %t374 = call ptr @malloc(i64 16)
  %t375 = inttoptr i64 0 to ptr
  %t376 = getelementptr ptr, ptr %t374, i32 0
  store ptr %t375, ptr %t376
  %t377 = getelementptr ptr, ptr %t374, i32 1
  store ptr %t373, ptr %t377
  br label %case.end.0.371
case.end.0.371:
  br label %case.join.369
case.arm.1.378:
  %t380 = getelementptr ptr, ptr %t364, i32 1
  %t381 = load ptr, ptr %t380
  %t382 = getelementptr [3 x i8], ptr @.str.10, i64 0, i64 0
  %t383 = call ptr @__concat(ptr %t381, ptr %t382)
  %t384 = getelementptr ptr, ptr %t383, i32 0
  %t385 = load ptr, ptr %t384
  %t386 = ptrtoint ptr %t385 to i64
  switch i64 %t386, label %case.default.387 [ i64 0, label %case.arm.0.389 i64 1, label %case.arm.1.397 ]
case.arm.0.389:
  %t391 = getelementptr ptr, ptr %t383, i32 1
  %t392 = load ptr, ptr %t391
  %t393 = call ptr @malloc(i64 16)
  %t394 = inttoptr i64 0 to ptr
  %t395 = getelementptr ptr, ptr %t393, i32 0
  store ptr %t394, ptr %t395
  %t396 = getelementptr ptr, ptr %t393, i32 1
  store ptr %t392, ptr %t396
  br label %case.end.0.390
case.end.0.390:
  br label %case.join.388
case.arm.1.397:
  %t399 = getelementptr ptr, ptr %t383, i32 1
  %t400 = load ptr, ptr %t399
  %t401 = call ptr @__concat(ptr %t400, ptr %t159)
  br label %case.end.1.398
case.end.1.398:
  br label %case.join.388
case.default.387:
  unreachable
case.join.388:
  %t402 = phi ptr [%t393, %case.end.0.390], [%t401, %case.end.1.398]
  br label %case.end.1.379
case.end.1.379:
  br label %case.join.369
case.default.368:
  unreachable
case.join.369:
  %t403 = phi ptr [%t374, %case.end.0.371], [%t402, %case.end.1.379]
  br label %case.end.1.361
case.end.1.361:
  br label %case.join.351
case.default.350:
  unreachable
case.join.351:
  %t404 = phi ptr [%t356, %case.end.0.353], [%t403, %case.end.1.361]
  br label %case.end.1.342
case.end.1.342:
  br label %case.join.332
case.default.331:
  unreachable
case.join.332:
  %t405 = phi ptr [%t337, %case.end.0.334], [%t404, %case.end.1.342]
  br label %case.end.1.324
case.end.1.324:
  br label %case.join.314
case.default.313:
  unreachable
case.join.314:
  %t406 = phi ptr [%t319, %case.end.0.316], [%t405, %case.end.1.324]
  br label %case.end.1.305
case.end.1.305:
  br label %case.join.295
case.default.294:
  unreachable
case.join.295:
  %t407 = phi ptr [%t300, %case.end.0.297], [%t406, %case.end.1.305]
  br label %case.end.1.287
case.end.1.287:
  br label %case.join.277
case.default.276:
  unreachable
case.join.277:
  %t408 = phi ptr [%t282, %case.end.0.279], [%t407, %case.end.1.287]
  br label %case.end.1.268
case.end.1.268:
  br label %case.join.258
case.default.257:
  unreachable
case.join.258:
  %t409 = phi ptr [%t263, %case.end.0.260], [%t408, %case.end.1.268]
  br label %case.end.1.250
case.end.1.250:
  br label %case.join.240
case.default.239:
  unreachable
case.join.240:
  %t410 = phi ptr [%t245, %case.end.0.242], [%t409, %case.end.1.250]
  br label %case.end.1.231
case.end.1.231:
  br label %case.join.221
case.default.220:
  unreachable
case.join.221:
  %t411 = phi ptr [%t226, %case.end.0.223], [%t410, %case.end.1.231]
  br label %case.end.1.213
case.end.1.213:
  br label %case.join.203
case.default.202:
  unreachable
case.join.203:
  %t412 = phi ptr [%t208, %case.end.0.205], [%t411, %case.end.1.213]
  br label %case.end.1.194
case.end.1.194:
  br label %case.join.184
case.default.183:
  unreachable
case.join.184:
  %t413 = phi ptr [%t189, %case.end.0.186], [%t412, %case.end.1.194]
  br label %case.end.1.176
case.end.1.176:
  br label %case.join.166
case.default.165:
  unreachable
case.join.166:
  %t414 = phi ptr [%t171, %case.end.0.168], [%t413, %case.end.1.176]
  br label %case.end.1.157
case.end.1.157:
  br label %case.join.147
case.default.146:
  unreachable
case.join.147:
  %t415 = phi ptr [%t152, %case.end.0.149], [%t414, %case.end.1.157]
  br label %case.end.1.137
case.end.1.137:
  br label %case.join.127
case.default.126:
  unreachable
case.join.127:
  %t416 = phi ptr [%t132, %case.end.0.129], [%t415, %case.end.1.137]
  br label %case.end.1.117
case.end.1.117:
  br label %case.join.107
case.default.106:
  unreachable
case.join.107:
  %t417 = phi ptr [%t112, %case.end.0.109], [%t416, %case.end.1.117]
  br label %case.end.1.97
case.end.1.97:
  br label %case.join.87
case.default.86:
  unreachable
case.join.87:
  %t418 = phi ptr [%t92, %case.end.0.89], [%t417, %case.end.1.97]
  br label %case.end.1.77
case.end.1.77:
  br label %case.join.67
case.default.66:
  unreachable
case.join.67:
  %t419 = phi ptr [%t72, %case.end.0.69], [%t418, %case.end.1.77]
  br label %case.end.1.57
case.end.1.57:
  br label %case.join.47
case.default.46:
  unreachable
case.join.47:
  %t420 = phi ptr [%t52, %case.end.0.49], [%t419, %case.end.1.57]
  br label %case.end.1.37
case.end.1.37:
  br label %case.join.27
case.default.26:
  unreachable
case.join.27:
  %t421 = phi ptr [%t32, %case.end.0.29], [%t420, %case.end.1.37]
  br label %case.end.1.17
case.end.1.17:
  br label %case.join.7
case.default.6:
  unreachable
case.join.7:
  %t422 = phi ptr [%t12, %case.end.0.9], [%t421, %case.end.1.17]
  %t423 = call ptr @v__let_2(ptr %t422)
  ret ptr %t423
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
