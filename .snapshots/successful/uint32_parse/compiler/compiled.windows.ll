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
  %t19 = call ptr @__showUInt32(ptr %t17)
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
  %t180 = getelementptr [3 x i8], ptr @.str.11, i64 0, i64 0
  %t181 = call ptr @__concat(ptr %t19, ptr %t180)
  %t182 = getelementptr ptr, ptr %t181, i32 0
  %t183 = load ptr, ptr %t182
  %t184 = ptrtoint ptr %t183 to i64
  switch i64 %t184, label %case.default.185 [ i64 0, label %case.arm.0.187 i64 1, label %case.arm.1.195 ]
case.arm.0.187:
  %t189 = getelementptr ptr, ptr %t181, i32 1
  %t190 = load ptr, ptr %t189
  %t191 = call ptr @malloc(i64 16)
  %t192 = inttoptr i64 0 to ptr
  %t193 = getelementptr ptr, ptr %t191, i32 0
  store ptr %t192, ptr %t193
  %t194 = getelementptr ptr, ptr %t191, i32 1
  store ptr %t190, ptr %t194
  br label %case.end.0.188
case.end.0.188:
  br label %case.join.186
case.arm.1.195:
  %t197 = getelementptr ptr, ptr %t181, i32 1
  %t198 = load ptr, ptr %t197
  %t199 = call ptr @__concat(ptr %t198, ptr %t39)
  %t200 = getelementptr ptr, ptr %t199, i32 0
  %t201 = load ptr, ptr %t200
  %t202 = ptrtoint ptr %t201 to i64
  switch i64 %t202, label %case.default.203 [ i64 0, label %case.arm.0.205 i64 1, label %case.arm.1.213 ]
case.arm.0.205:
  %t207 = getelementptr ptr, ptr %t199, i32 1
  %t208 = load ptr, ptr %t207
  %t209 = call ptr @malloc(i64 16)
  %t210 = inttoptr i64 0 to ptr
  %t211 = getelementptr ptr, ptr %t209, i32 0
  store ptr %t210, ptr %t211
  %t212 = getelementptr ptr, ptr %t209, i32 1
  store ptr %t208, ptr %t212
  br label %case.end.0.206
case.end.0.206:
  br label %case.join.204
case.arm.1.213:
  %t215 = getelementptr ptr, ptr %t199, i32 1
  %t216 = load ptr, ptr %t215
  %t217 = getelementptr [3 x i8], ptr @.str.11, i64 0, i64 0
  %t218 = call ptr @__concat(ptr %t216, ptr %t217)
  %t219 = getelementptr ptr, ptr %t218, i32 0
  %t220 = load ptr, ptr %t219
  %t221 = ptrtoint ptr %t220 to i64
  switch i64 %t221, label %case.default.222 [ i64 0, label %case.arm.0.224 i64 1, label %case.arm.1.232 ]
case.arm.0.224:
  %t226 = getelementptr ptr, ptr %t218, i32 1
  %t227 = load ptr, ptr %t226
  %t228 = call ptr @malloc(i64 16)
  %t229 = inttoptr i64 0 to ptr
  %t230 = getelementptr ptr, ptr %t228, i32 0
  store ptr %t229, ptr %t230
  %t231 = getelementptr ptr, ptr %t228, i32 1
  store ptr %t227, ptr %t231
  br label %case.end.0.225
case.end.0.225:
  br label %case.join.223
case.arm.1.232:
  %t234 = getelementptr ptr, ptr %t218, i32 1
  %t235 = load ptr, ptr %t234
  %t236 = call ptr @__concat(ptr %t235, ptr %t59)
  %t237 = getelementptr ptr, ptr %t236, i32 0
  %t238 = load ptr, ptr %t237
  %t239 = ptrtoint ptr %t238 to i64
  switch i64 %t239, label %case.default.240 [ i64 0, label %case.arm.0.242 i64 1, label %case.arm.1.250 ]
case.arm.0.242:
  %t244 = getelementptr ptr, ptr %t236, i32 1
  %t245 = load ptr, ptr %t244
  %t246 = call ptr @malloc(i64 16)
  %t247 = inttoptr i64 0 to ptr
  %t248 = getelementptr ptr, ptr %t246, i32 0
  store ptr %t247, ptr %t248
  %t249 = getelementptr ptr, ptr %t246, i32 1
  store ptr %t245, ptr %t249
  br label %case.end.0.243
case.end.0.243:
  br label %case.join.241
case.arm.1.250:
  %t252 = getelementptr ptr, ptr %t236, i32 1
  %t253 = load ptr, ptr %t252
  %t254 = getelementptr [3 x i8], ptr @.str.11, i64 0, i64 0
  %t255 = call ptr @__concat(ptr %t253, ptr %t254)
  %t256 = getelementptr ptr, ptr %t255, i32 0
  %t257 = load ptr, ptr %t256
  %t258 = ptrtoint ptr %t257 to i64
  switch i64 %t258, label %case.default.259 [ i64 0, label %case.arm.0.261 i64 1, label %case.arm.1.269 ]
case.arm.0.261:
  %t263 = getelementptr ptr, ptr %t255, i32 1
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
  %t271 = getelementptr ptr, ptr %t255, i32 1
  %t272 = load ptr, ptr %t271
  %t273 = call ptr @__concat(ptr %t272, ptr %t79)
  %t274 = getelementptr ptr, ptr %t273, i32 0
  %t275 = load ptr, ptr %t274
  %t276 = ptrtoint ptr %t275 to i64
  switch i64 %t276, label %case.default.277 [ i64 0, label %case.arm.0.279 i64 1, label %case.arm.1.287 ]
case.arm.0.279:
  %t281 = getelementptr ptr, ptr %t273, i32 1
  %t282 = load ptr, ptr %t281
  %t283 = call ptr @malloc(i64 16)
  %t284 = inttoptr i64 0 to ptr
  %t285 = getelementptr ptr, ptr %t283, i32 0
  store ptr %t284, ptr %t285
  %t286 = getelementptr ptr, ptr %t283, i32 1
  store ptr %t282, ptr %t286
  br label %case.end.0.280
case.end.0.280:
  br label %case.join.278
case.arm.1.287:
  %t289 = getelementptr ptr, ptr %t273, i32 1
  %t290 = load ptr, ptr %t289
  %t291 = getelementptr [3 x i8], ptr @.str.11, i64 0, i64 0
  %t292 = call ptr @__concat(ptr %t290, ptr %t291)
  %t293 = getelementptr ptr, ptr %t292, i32 0
  %t294 = load ptr, ptr %t293
  %t295 = ptrtoint ptr %t294 to i64
  switch i64 %t295, label %case.default.296 [ i64 0, label %case.arm.0.298 i64 1, label %case.arm.1.306 ]
case.arm.0.298:
  %t300 = getelementptr ptr, ptr %t292, i32 1
  %t301 = load ptr, ptr %t300
  %t302 = call ptr @malloc(i64 16)
  %t303 = inttoptr i64 0 to ptr
  %t304 = getelementptr ptr, ptr %t302, i32 0
  store ptr %t303, ptr %t304
  %t305 = getelementptr ptr, ptr %t302, i32 1
  store ptr %t301, ptr %t305
  br label %case.end.0.299
case.end.0.299:
  br label %case.join.297
case.arm.1.306:
  %t308 = getelementptr ptr, ptr %t292, i32 1
  %t309 = load ptr, ptr %t308
  %t310 = call ptr @__concat(ptr %t309, ptr %t99)
  %t311 = getelementptr ptr, ptr %t310, i32 0
  %t312 = load ptr, ptr %t311
  %t313 = ptrtoint ptr %t312 to i64
  switch i64 %t313, label %case.default.314 [ i64 0, label %case.arm.0.316 i64 1, label %case.arm.1.324 ]
case.arm.0.316:
  %t318 = getelementptr ptr, ptr %t310, i32 1
  %t319 = load ptr, ptr %t318
  %t320 = call ptr @malloc(i64 16)
  %t321 = inttoptr i64 0 to ptr
  %t322 = getelementptr ptr, ptr %t320, i32 0
  store ptr %t321, ptr %t322
  %t323 = getelementptr ptr, ptr %t320, i32 1
  store ptr %t319, ptr %t323
  br label %case.end.0.317
case.end.0.317:
  br label %case.join.315
case.arm.1.324:
  %t326 = getelementptr ptr, ptr %t310, i32 1
  %t327 = load ptr, ptr %t326
  %t328 = getelementptr [3 x i8], ptr @.str.11, i64 0, i64 0
  %t329 = call ptr @__concat(ptr %t327, ptr %t328)
  %t330 = getelementptr ptr, ptr %t329, i32 0
  %t331 = load ptr, ptr %t330
  %t332 = ptrtoint ptr %t331 to i64
  switch i64 %t332, label %case.default.333 [ i64 0, label %case.arm.0.335 i64 1, label %case.arm.1.343 ]
case.arm.0.335:
  %t337 = getelementptr ptr, ptr %t329, i32 1
  %t338 = load ptr, ptr %t337
  %t339 = call ptr @malloc(i64 16)
  %t340 = inttoptr i64 0 to ptr
  %t341 = getelementptr ptr, ptr %t339, i32 0
  store ptr %t340, ptr %t341
  %t342 = getelementptr ptr, ptr %t339, i32 1
  store ptr %t338, ptr %t342
  br label %case.end.0.336
case.end.0.336:
  br label %case.join.334
case.arm.1.343:
  %t345 = getelementptr ptr, ptr %t329, i32 1
  %t346 = load ptr, ptr %t345
  %t347 = call ptr @__concat(ptr %t346, ptr %t119)
  %t348 = getelementptr ptr, ptr %t347, i32 0
  %t349 = load ptr, ptr %t348
  %t350 = ptrtoint ptr %t349 to i64
  switch i64 %t350, label %case.default.351 [ i64 0, label %case.arm.0.353 i64 1, label %case.arm.1.361 ]
case.arm.0.353:
  %t355 = getelementptr ptr, ptr %t347, i32 1
  %t356 = load ptr, ptr %t355
  %t357 = call ptr @malloc(i64 16)
  %t358 = inttoptr i64 0 to ptr
  %t359 = getelementptr ptr, ptr %t357, i32 0
  store ptr %t358, ptr %t359
  %t360 = getelementptr ptr, ptr %t357, i32 1
  store ptr %t356, ptr %t360
  br label %case.end.0.354
case.end.0.354:
  br label %case.join.352
case.arm.1.361:
  %t363 = getelementptr ptr, ptr %t347, i32 1
  %t364 = load ptr, ptr %t363
  %t365 = getelementptr [3 x i8], ptr @.str.11, i64 0, i64 0
  %t366 = call ptr @__concat(ptr %t364, ptr %t365)
  %t367 = getelementptr ptr, ptr %t366, i32 0
  %t368 = load ptr, ptr %t367
  %t369 = ptrtoint ptr %t368 to i64
  switch i64 %t369, label %case.default.370 [ i64 0, label %case.arm.0.372 i64 1, label %case.arm.1.380 ]
case.arm.0.372:
  %t374 = getelementptr ptr, ptr %t366, i32 1
  %t375 = load ptr, ptr %t374
  %t376 = call ptr @malloc(i64 16)
  %t377 = inttoptr i64 0 to ptr
  %t378 = getelementptr ptr, ptr %t376, i32 0
  store ptr %t377, ptr %t378
  %t379 = getelementptr ptr, ptr %t376, i32 1
  store ptr %t375, ptr %t379
  br label %case.end.0.373
case.end.0.373:
  br label %case.join.371
case.arm.1.380:
  %t382 = getelementptr ptr, ptr %t366, i32 1
  %t383 = load ptr, ptr %t382
  %t384 = call ptr @__concat(ptr %t383, ptr %t139)
  %t385 = getelementptr ptr, ptr %t384, i32 0
  %t386 = load ptr, ptr %t385
  %t387 = ptrtoint ptr %t386 to i64
  switch i64 %t387, label %case.default.388 [ i64 0, label %case.arm.0.390 i64 1, label %case.arm.1.398 ]
case.arm.0.390:
  %t392 = getelementptr ptr, ptr %t384, i32 1
  %t393 = load ptr, ptr %t392
  %t394 = call ptr @malloc(i64 16)
  %t395 = inttoptr i64 0 to ptr
  %t396 = getelementptr ptr, ptr %t394, i32 0
  store ptr %t395, ptr %t396
  %t397 = getelementptr ptr, ptr %t394, i32 1
  store ptr %t393, ptr %t397
  br label %case.end.0.391
case.end.0.391:
  br label %case.join.389
case.arm.1.398:
  %t400 = getelementptr ptr, ptr %t384, i32 1
  %t401 = load ptr, ptr %t400
  %t402 = getelementptr [3 x i8], ptr @.str.11, i64 0, i64 0
  %t403 = call ptr @__concat(ptr %t401, ptr %t402)
  %t404 = getelementptr ptr, ptr %t403, i32 0
  %t405 = load ptr, ptr %t404
  %t406 = ptrtoint ptr %t405 to i64
  switch i64 %t406, label %case.default.407 [ i64 0, label %case.arm.0.409 i64 1, label %case.arm.1.417 ]
case.arm.0.409:
  %t411 = getelementptr ptr, ptr %t403, i32 1
  %t412 = load ptr, ptr %t411
  %t413 = call ptr @malloc(i64 16)
  %t414 = inttoptr i64 0 to ptr
  %t415 = getelementptr ptr, ptr %t413, i32 0
  store ptr %t414, ptr %t415
  %t416 = getelementptr ptr, ptr %t413, i32 1
  store ptr %t412, ptr %t416
  br label %case.end.0.410
case.end.0.410:
  br label %case.join.408
case.arm.1.417:
  %t419 = getelementptr ptr, ptr %t403, i32 1
  %t420 = load ptr, ptr %t419
  %t421 = call ptr @__concat(ptr %t420, ptr %t159)
  %t422 = getelementptr ptr, ptr %t421, i32 0
  %t423 = load ptr, ptr %t422
  %t424 = ptrtoint ptr %t423 to i64
  switch i64 %t424, label %case.default.425 [ i64 0, label %case.arm.0.427 i64 1, label %case.arm.1.435 ]
case.arm.0.427:
  %t429 = getelementptr ptr, ptr %t421, i32 1
  %t430 = load ptr, ptr %t429
  %t431 = call ptr @malloc(i64 16)
  %t432 = inttoptr i64 0 to ptr
  %t433 = getelementptr ptr, ptr %t431, i32 0
  store ptr %t432, ptr %t433
  %t434 = getelementptr ptr, ptr %t431, i32 1
  store ptr %t430, ptr %t434
  br label %case.end.0.428
case.end.0.428:
  br label %case.join.426
case.arm.1.435:
  %t437 = getelementptr ptr, ptr %t421, i32 1
  %t438 = load ptr, ptr %t437
  %t439 = getelementptr [3 x i8], ptr @.str.11, i64 0, i64 0
  %t440 = call ptr @__concat(ptr %t438, ptr %t439)
  %t441 = getelementptr ptr, ptr %t440, i32 0
  %t442 = load ptr, ptr %t441
  %t443 = ptrtoint ptr %t442 to i64
  switch i64 %t443, label %case.default.444 [ i64 0, label %case.arm.0.446 i64 1, label %case.arm.1.454 ]
case.arm.0.446:
  %t448 = getelementptr ptr, ptr %t440, i32 1
  %t449 = load ptr, ptr %t448
  %t450 = call ptr @malloc(i64 16)
  %t451 = inttoptr i64 0 to ptr
  %t452 = getelementptr ptr, ptr %t450, i32 0
  store ptr %t451, ptr %t452
  %t453 = getelementptr ptr, ptr %t450, i32 1
  store ptr %t449, ptr %t453
  br label %case.end.0.447
case.end.0.447:
  br label %case.join.445
case.arm.1.454:
  %t456 = getelementptr ptr, ptr %t440, i32 1
  %t457 = load ptr, ptr %t456
  %t458 = call ptr @__concat(ptr %t457, ptr %t179)
  br label %case.end.1.455
case.end.1.455:
  br label %case.join.445
case.default.444:
  unreachable
case.join.445:
  %t459 = phi ptr [%t450, %case.end.0.447], [%t458, %case.end.1.455]
  br label %case.end.1.436
case.end.1.436:
  br label %case.join.426
case.default.425:
  unreachable
case.join.426:
  %t460 = phi ptr [%t431, %case.end.0.428], [%t459, %case.end.1.436]
  br label %case.end.1.418
case.end.1.418:
  br label %case.join.408
case.default.407:
  unreachable
case.join.408:
  %t461 = phi ptr [%t413, %case.end.0.410], [%t460, %case.end.1.418]
  br label %case.end.1.399
case.end.1.399:
  br label %case.join.389
case.default.388:
  unreachable
case.join.389:
  %t462 = phi ptr [%t394, %case.end.0.391], [%t461, %case.end.1.399]
  br label %case.end.1.381
case.end.1.381:
  br label %case.join.371
case.default.370:
  unreachable
case.join.371:
  %t463 = phi ptr [%t376, %case.end.0.373], [%t462, %case.end.1.381]
  br label %case.end.1.362
case.end.1.362:
  br label %case.join.352
case.default.351:
  unreachable
case.join.352:
  %t464 = phi ptr [%t357, %case.end.0.354], [%t463, %case.end.1.362]
  br label %case.end.1.344
case.end.1.344:
  br label %case.join.334
case.default.333:
  unreachable
case.join.334:
  %t465 = phi ptr [%t339, %case.end.0.336], [%t464, %case.end.1.344]
  br label %case.end.1.325
case.end.1.325:
  br label %case.join.315
case.default.314:
  unreachable
case.join.315:
  %t466 = phi ptr [%t320, %case.end.0.317], [%t465, %case.end.1.325]
  br label %case.end.1.307
case.end.1.307:
  br label %case.join.297
case.default.296:
  unreachable
case.join.297:
  %t467 = phi ptr [%t302, %case.end.0.299], [%t466, %case.end.1.307]
  br label %case.end.1.288
case.end.1.288:
  br label %case.join.278
case.default.277:
  unreachable
case.join.278:
  %t468 = phi ptr [%t283, %case.end.0.280], [%t467, %case.end.1.288]
  br label %case.end.1.270
case.end.1.270:
  br label %case.join.260
case.default.259:
  unreachable
case.join.260:
  %t469 = phi ptr [%t265, %case.end.0.262], [%t468, %case.end.1.270]
  br label %case.end.1.251
case.end.1.251:
  br label %case.join.241
case.default.240:
  unreachable
case.join.241:
  %t470 = phi ptr [%t246, %case.end.0.243], [%t469, %case.end.1.251]
  br label %case.end.1.233
case.end.1.233:
  br label %case.join.223
case.default.222:
  unreachable
case.join.223:
  %t471 = phi ptr [%t228, %case.end.0.225], [%t470, %case.end.1.233]
  br label %case.end.1.214
case.end.1.214:
  br label %case.join.204
case.default.203:
  unreachable
case.join.204:
  %t472 = phi ptr [%t209, %case.end.0.206], [%t471, %case.end.1.214]
  br label %case.end.1.196
case.end.1.196:
  br label %case.join.186
case.default.185:
  unreachable
case.join.186:
  %t473 = phi ptr [%t191, %case.end.0.188], [%t472, %case.end.1.196]
  br label %case.end.1.177
case.end.1.177:
  br label %case.join.167
case.default.166:
  unreachable
case.join.167:
  %t474 = phi ptr [%t172, %case.end.0.169], [%t473, %case.end.1.177]
  br label %case.end.1.157
case.end.1.157:
  br label %case.join.147
case.default.146:
  unreachable
case.join.147:
  %t475 = phi ptr [%t152, %case.end.0.149], [%t474, %case.end.1.157]
  br label %case.end.1.137
case.end.1.137:
  br label %case.join.127
case.default.126:
  unreachable
case.join.127:
  %t476 = phi ptr [%t132, %case.end.0.129], [%t475, %case.end.1.137]
  br label %case.end.1.117
case.end.1.117:
  br label %case.join.107
case.default.106:
  unreachable
case.join.107:
  %t477 = phi ptr [%t112, %case.end.0.109], [%t476, %case.end.1.117]
  br label %case.end.1.97
case.end.1.97:
  br label %case.join.87
case.default.86:
  unreachable
case.join.87:
  %t478 = phi ptr [%t92, %case.end.0.89], [%t477, %case.end.1.97]
  br label %case.end.1.77
case.end.1.77:
  br label %case.join.67
case.default.66:
  unreachable
case.join.67:
  %t479 = phi ptr [%t72, %case.end.0.69], [%t478, %case.end.1.77]
  br label %case.end.1.57
case.end.1.57:
  br label %case.join.47
case.default.46:
  unreachable
case.join.47:
  %t480 = phi ptr [%t52, %case.end.0.49], [%t479, %case.end.1.57]
  br label %case.end.1.37
case.end.1.37:
  br label %case.join.27
case.default.26:
  unreachable
case.join.27:
  %t481 = phi ptr [%t32, %case.end.0.29], [%t480, %case.end.1.37]
  br label %case.end.1.17
case.end.1.17:
  br label %case.join.7
case.default.6:
  unreachable
case.join.7:
  %t482 = phi ptr [%t12, %case.end.0.9], [%t481, %case.end.1.17]
  %t483 = call ptr @v__let_2(ptr %t482)
  ret ptr %t483
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
