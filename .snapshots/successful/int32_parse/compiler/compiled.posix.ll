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
  %t19 = call ptr @__showInt32(ptr %t17)
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
  %t240 = getelementptr [3 x i8], ptr @.str.14, i64 0, i64 0
  %t241 = call ptr @__concat(ptr %t19, ptr %t240)
  %t242 = getelementptr ptr, ptr %t241, i32 0
  %t243 = load ptr, ptr %t242
  %t244 = ptrtoint ptr %t243 to i64
  switch i64 %t244, label %case.default.245 [ i64 0, label %case.arm.0.247 i64 1, label %case.arm.1.255 ]
case.arm.0.247:
  %t249 = getelementptr ptr, ptr %t241, i32 1
  %t250 = load ptr, ptr %t249
  %t251 = call ptr @malloc(i64 16)
  %t252 = inttoptr i64 0 to ptr
  %t253 = getelementptr ptr, ptr %t251, i32 0
  store ptr %t252, ptr %t253
  %t254 = getelementptr ptr, ptr %t251, i32 1
  store ptr %t250, ptr %t254
  br label %case.end.0.248
case.end.0.248:
  br label %case.join.246
case.arm.1.255:
  %t257 = getelementptr ptr, ptr %t241, i32 1
  %t258 = load ptr, ptr %t257
  %t259 = call ptr @__concat(ptr %t258, ptr %t39)
  %t260 = getelementptr ptr, ptr %t259, i32 0
  %t261 = load ptr, ptr %t260
  %t262 = ptrtoint ptr %t261 to i64
  switch i64 %t262, label %case.default.263 [ i64 0, label %case.arm.0.265 i64 1, label %case.arm.1.273 ]
case.arm.0.265:
  %t267 = getelementptr ptr, ptr %t259, i32 1
  %t268 = load ptr, ptr %t267
  %t269 = call ptr @malloc(i64 16)
  %t270 = inttoptr i64 0 to ptr
  %t271 = getelementptr ptr, ptr %t269, i32 0
  store ptr %t270, ptr %t271
  %t272 = getelementptr ptr, ptr %t269, i32 1
  store ptr %t268, ptr %t272
  br label %case.end.0.266
case.end.0.266:
  br label %case.join.264
case.arm.1.273:
  %t275 = getelementptr ptr, ptr %t259, i32 1
  %t276 = load ptr, ptr %t275
  %t277 = getelementptr [3 x i8], ptr @.str.14, i64 0, i64 0
  %t278 = call ptr @__concat(ptr %t276, ptr %t277)
  %t279 = getelementptr ptr, ptr %t278, i32 0
  %t280 = load ptr, ptr %t279
  %t281 = ptrtoint ptr %t280 to i64
  switch i64 %t281, label %case.default.282 [ i64 0, label %case.arm.0.284 i64 1, label %case.arm.1.292 ]
case.arm.0.284:
  %t286 = getelementptr ptr, ptr %t278, i32 1
  %t287 = load ptr, ptr %t286
  %t288 = call ptr @malloc(i64 16)
  %t289 = inttoptr i64 0 to ptr
  %t290 = getelementptr ptr, ptr %t288, i32 0
  store ptr %t289, ptr %t290
  %t291 = getelementptr ptr, ptr %t288, i32 1
  store ptr %t287, ptr %t291
  br label %case.end.0.285
case.end.0.285:
  br label %case.join.283
case.arm.1.292:
  %t294 = getelementptr ptr, ptr %t278, i32 1
  %t295 = load ptr, ptr %t294
  %t296 = call ptr @__concat(ptr %t295, ptr %t59)
  %t297 = getelementptr ptr, ptr %t296, i32 0
  %t298 = load ptr, ptr %t297
  %t299 = ptrtoint ptr %t298 to i64
  switch i64 %t299, label %case.default.300 [ i64 0, label %case.arm.0.302 i64 1, label %case.arm.1.310 ]
case.arm.0.302:
  %t304 = getelementptr ptr, ptr %t296, i32 1
  %t305 = load ptr, ptr %t304
  %t306 = call ptr @malloc(i64 16)
  %t307 = inttoptr i64 0 to ptr
  %t308 = getelementptr ptr, ptr %t306, i32 0
  store ptr %t307, ptr %t308
  %t309 = getelementptr ptr, ptr %t306, i32 1
  store ptr %t305, ptr %t309
  br label %case.end.0.303
case.end.0.303:
  br label %case.join.301
case.arm.1.310:
  %t312 = getelementptr ptr, ptr %t296, i32 1
  %t313 = load ptr, ptr %t312
  %t314 = getelementptr [3 x i8], ptr @.str.14, i64 0, i64 0
  %t315 = call ptr @__concat(ptr %t313, ptr %t314)
  %t316 = getelementptr ptr, ptr %t315, i32 0
  %t317 = load ptr, ptr %t316
  %t318 = ptrtoint ptr %t317 to i64
  switch i64 %t318, label %case.default.319 [ i64 0, label %case.arm.0.321 i64 1, label %case.arm.1.329 ]
case.arm.0.321:
  %t323 = getelementptr ptr, ptr %t315, i32 1
  %t324 = load ptr, ptr %t323
  %t325 = call ptr @malloc(i64 16)
  %t326 = inttoptr i64 0 to ptr
  %t327 = getelementptr ptr, ptr %t325, i32 0
  store ptr %t326, ptr %t327
  %t328 = getelementptr ptr, ptr %t325, i32 1
  store ptr %t324, ptr %t328
  br label %case.end.0.322
case.end.0.322:
  br label %case.join.320
case.arm.1.329:
  %t331 = getelementptr ptr, ptr %t315, i32 1
  %t332 = load ptr, ptr %t331
  %t333 = call ptr @__concat(ptr %t332, ptr %t79)
  %t334 = getelementptr ptr, ptr %t333, i32 0
  %t335 = load ptr, ptr %t334
  %t336 = ptrtoint ptr %t335 to i64
  switch i64 %t336, label %case.default.337 [ i64 0, label %case.arm.0.339 i64 1, label %case.arm.1.347 ]
case.arm.0.339:
  %t341 = getelementptr ptr, ptr %t333, i32 1
  %t342 = load ptr, ptr %t341
  %t343 = call ptr @malloc(i64 16)
  %t344 = inttoptr i64 0 to ptr
  %t345 = getelementptr ptr, ptr %t343, i32 0
  store ptr %t344, ptr %t345
  %t346 = getelementptr ptr, ptr %t343, i32 1
  store ptr %t342, ptr %t346
  br label %case.end.0.340
case.end.0.340:
  br label %case.join.338
case.arm.1.347:
  %t349 = getelementptr ptr, ptr %t333, i32 1
  %t350 = load ptr, ptr %t349
  %t351 = getelementptr [3 x i8], ptr @.str.14, i64 0, i64 0
  %t352 = call ptr @__concat(ptr %t350, ptr %t351)
  %t353 = getelementptr ptr, ptr %t352, i32 0
  %t354 = load ptr, ptr %t353
  %t355 = ptrtoint ptr %t354 to i64
  switch i64 %t355, label %case.default.356 [ i64 0, label %case.arm.0.358 i64 1, label %case.arm.1.366 ]
case.arm.0.358:
  %t360 = getelementptr ptr, ptr %t352, i32 1
  %t361 = load ptr, ptr %t360
  %t362 = call ptr @malloc(i64 16)
  %t363 = inttoptr i64 0 to ptr
  %t364 = getelementptr ptr, ptr %t362, i32 0
  store ptr %t363, ptr %t364
  %t365 = getelementptr ptr, ptr %t362, i32 1
  store ptr %t361, ptr %t365
  br label %case.end.0.359
case.end.0.359:
  br label %case.join.357
case.arm.1.366:
  %t368 = getelementptr ptr, ptr %t352, i32 1
  %t369 = load ptr, ptr %t368
  %t370 = call ptr @__concat(ptr %t369, ptr %t99)
  %t371 = getelementptr ptr, ptr %t370, i32 0
  %t372 = load ptr, ptr %t371
  %t373 = ptrtoint ptr %t372 to i64
  switch i64 %t373, label %case.default.374 [ i64 0, label %case.arm.0.376 i64 1, label %case.arm.1.384 ]
case.arm.0.376:
  %t378 = getelementptr ptr, ptr %t370, i32 1
  %t379 = load ptr, ptr %t378
  %t380 = call ptr @malloc(i64 16)
  %t381 = inttoptr i64 0 to ptr
  %t382 = getelementptr ptr, ptr %t380, i32 0
  store ptr %t381, ptr %t382
  %t383 = getelementptr ptr, ptr %t380, i32 1
  store ptr %t379, ptr %t383
  br label %case.end.0.377
case.end.0.377:
  br label %case.join.375
case.arm.1.384:
  %t386 = getelementptr ptr, ptr %t370, i32 1
  %t387 = load ptr, ptr %t386
  %t388 = getelementptr [3 x i8], ptr @.str.14, i64 0, i64 0
  %t389 = call ptr @__concat(ptr %t387, ptr %t388)
  %t390 = getelementptr ptr, ptr %t389, i32 0
  %t391 = load ptr, ptr %t390
  %t392 = ptrtoint ptr %t391 to i64
  switch i64 %t392, label %case.default.393 [ i64 0, label %case.arm.0.395 i64 1, label %case.arm.1.403 ]
case.arm.0.395:
  %t397 = getelementptr ptr, ptr %t389, i32 1
  %t398 = load ptr, ptr %t397
  %t399 = call ptr @malloc(i64 16)
  %t400 = inttoptr i64 0 to ptr
  %t401 = getelementptr ptr, ptr %t399, i32 0
  store ptr %t400, ptr %t401
  %t402 = getelementptr ptr, ptr %t399, i32 1
  store ptr %t398, ptr %t402
  br label %case.end.0.396
case.end.0.396:
  br label %case.join.394
case.arm.1.403:
  %t405 = getelementptr ptr, ptr %t389, i32 1
  %t406 = load ptr, ptr %t405
  %t407 = call ptr @__concat(ptr %t406, ptr %t119)
  %t408 = getelementptr ptr, ptr %t407, i32 0
  %t409 = load ptr, ptr %t408
  %t410 = ptrtoint ptr %t409 to i64
  switch i64 %t410, label %case.default.411 [ i64 0, label %case.arm.0.413 i64 1, label %case.arm.1.421 ]
case.arm.0.413:
  %t415 = getelementptr ptr, ptr %t407, i32 1
  %t416 = load ptr, ptr %t415
  %t417 = call ptr @malloc(i64 16)
  %t418 = inttoptr i64 0 to ptr
  %t419 = getelementptr ptr, ptr %t417, i32 0
  store ptr %t418, ptr %t419
  %t420 = getelementptr ptr, ptr %t417, i32 1
  store ptr %t416, ptr %t420
  br label %case.end.0.414
case.end.0.414:
  br label %case.join.412
case.arm.1.421:
  %t423 = getelementptr ptr, ptr %t407, i32 1
  %t424 = load ptr, ptr %t423
  %t425 = getelementptr [3 x i8], ptr @.str.14, i64 0, i64 0
  %t426 = call ptr @__concat(ptr %t424, ptr %t425)
  %t427 = getelementptr ptr, ptr %t426, i32 0
  %t428 = load ptr, ptr %t427
  %t429 = ptrtoint ptr %t428 to i64
  switch i64 %t429, label %case.default.430 [ i64 0, label %case.arm.0.432 i64 1, label %case.arm.1.440 ]
case.arm.0.432:
  %t434 = getelementptr ptr, ptr %t426, i32 1
  %t435 = load ptr, ptr %t434
  %t436 = call ptr @malloc(i64 16)
  %t437 = inttoptr i64 0 to ptr
  %t438 = getelementptr ptr, ptr %t436, i32 0
  store ptr %t437, ptr %t438
  %t439 = getelementptr ptr, ptr %t436, i32 1
  store ptr %t435, ptr %t439
  br label %case.end.0.433
case.end.0.433:
  br label %case.join.431
case.arm.1.440:
  %t442 = getelementptr ptr, ptr %t426, i32 1
  %t443 = load ptr, ptr %t442
  %t444 = call ptr @__concat(ptr %t443, ptr %t139)
  %t445 = getelementptr ptr, ptr %t444, i32 0
  %t446 = load ptr, ptr %t445
  %t447 = ptrtoint ptr %t446 to i64
  switch i64 %t447, label %case.default.448 [ i64 0, label %case.arm.0.450 i64 1, label %case.arm.1.458 ]
case.arm.0.450:
  %t452 = getelementptr ptr, ptr %t444, i32 1
  %t453 = load ptr, ptr %t452
  %t454 = call ptr @malloc(i64 16)
  %t455 = inttoptr i64 0 to ptr
  %t456 = getelementptr ptr, ptr %t454, i32 0
  store ptr %t455, ptr %t456
  %t457 = getelementptr ptr, ptr %t454, i32 1
  store ptr %t453, ptr %t457
  br label %case.end.0.451
case.end.0.451:
  br label %case.join.449
case.arm.1.458:
  %t460 = getelementptr ptr, ptr %t444, i32 1
  %t461 = load ptr, ptr %t460
  %t462 = getelementptr [3 x i8], ptr @.str.14, i64 0, i64 0
  %t463 = call ptr @__concat(ptr %t461, ptr %t462)
  %t464 = getelementptr ptr, ptr %t463, i32 0
  %t465 = load ptr, ptr %t464
  %t466 = ptrtoint ptr %t465 to i64
  switch i64 %t466, label %case.default.467 [ i64 0, label %case.arm.0.469 i64 1, label %case.arm.1.477 ]
case.arm.0.469:
  %t471 = getelementptr ptr, ptr %t463, i32 1
  %t472 = load ptr, ptr %t471
  %t473 = call ptr @malloc(i64 16)
  %t474 = inttoptr i64 0 to ptr
  %t475 = getelementptr ptr, ptr %t473, i32 0
  store ptr %t474, ptr %t475
  %t476 = getelementptr ptr, ptr %t473, i32 1
  store ptr %t472, ptr %t476
  br label %case.end.0.470
case.end.0.470:
  br label %case.join.468
case.arm.1.477:
  %t479 = getelementptr ptr, ptr %t463, i32 1
  %t480 = load ptr, ptr %t479
  %t481 = call ptr @__concat(ptr %t480, ptr %t159)
  %t482 = getelementptr ptr, ptr %t481, i32 0
  %t483 = load ptr, ptr %t482
  %t484 = ptrtoint ptr %t483 to i64
  switch i64 %t484, label %case.default.485 [ i64 0, label %case.arm.0.487 i64 1, label %case.arm.1.495 ]
case.arm.0.487:
  %t489 = getelementptr ptr, ptr %t481, i32 1
  %t490 = load ptr, ptr %t489
  %t491 = call ptr @malloc(i64 16)
  %t492 = inttoptr i64 0 to ptr
  %t493 = getelementptr ptr, ptr %t491, i32 0
  store ptr %t492, ptr %t493
  %t494 = getelementptr ptr, ptr %t491, i32 1
  store ptr %t490, ptr %t494
  br label %case.end.0.488
case.end.0.488:
  br label %case.join.486
case.arm.1.495:
  %t497 = getelementptr ptr, ptr %t481, i32 1
  %t498 = load ptr, ptr %t497
  %t499 = getelementptr [3 x i8], ptr @.str.14, i64 0, i64 0
  %t500 = call ptr @__concat(ptr %t498, ptr %t499)
  %t501 = getelementptr ptr, ptr %t500, i32 0
  %t502 = load ptr, ptr %t501
  %t503 = ptrtoint ptr %t502 to i64
  switch i64 %t503, label %case.default.504 [ i64 0, label %case.arm.0.506 i64 1, label %case.arm.1.514 ]
case.arm.0.506:
  %t508 = getelementptr ptr, ptr %t500, i32 1
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
  %t516 = getelementptr ptr, ptr %t500, i32 1
  %t517 = load ptr, ptr %t516
  %t518 = call ptr @__concat(ptr %t517, ptr %t179)
  %t519 = getelementptr ptr, ptr %t518, i32 0
  %t520 = load ptr, ptr %t519
  %t521 = ptrtoint ptr %t520 to i64
  switch i64 %t521, label %case.default.522 [ i64 0, label %case.arm.0.524 i64 1, label %case.arm.1.532 ]
case.arm.0.524:
  %t526 = getelementptr ptr, ptr %t518, i32 1
  %t527 = load ptr, ptr %t526
  %t528 = call ptr @malloc(i64 16)
  %t529 = inttoptr i64 0 to ptr
  %t530 = getelementptr ptr, ptr %t528, i32 0
  store ptr %t529, ptr %t530
  %t531 = getelementptr ptr, ptr %t528, i32 1
  store ptr %t527, ptr %t531
  br label %case.end.0.525
case.end.0.525:
  br label %case.join.523
case.arm.1.532:
  %t534 = getelementptr ptr, ptr %t518, i32 1
  %t535 = load ptr, ptr %t534
  %t536 = getelementptr [3 x i8], ptr @.str.14, i64 0, i64 0
  %t537 = call ptr @__concat(ptr %t535, ptr %t536)
  %t538 = getelementptr ptr, ptr %t537, i32 0
  %t539 = load ptr, ptr %t538
  %t540 = ptrtoint ptr %t539 to i64
  switch i64 %t540, label %case.default.541 [ i64 0, label %case.arm.0.543 i64 1, label %case.arm.1.551 ]
case.arm.0.543:
  %t545 = getelementptr ptr, ptr %t537, i32 1
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
  %t553 = getelementptr ptr, ptr %t537, i32 1
  %t554 = load ptr, ptr %t553
  %t555 = call ptr @__concat(ptr %t554, ptr %t199)
  %t556 = getelementptr ptr, ptr %t555, i32 0
  %t557 = load ptr, ptr %t556
  %t558 = ptrtoint ptr %t557 to i64
  switch i64 %t558, label %case.default.559 [ i64 0, label %case.arm.0.561 i64 1, label %case.arm.1.569 ]
case.arm.0.561:
  %t563 = getelementptr ptr, ptr %t555, i32 1
  %t564 = load ptr, ptr %t563
  %t565 = call ptr @malloc(i64 16)
  %t566 = inttoptr i64 0 to ptr
  %t567 = getelementptr ptr, ptr %t565, i32 0
  store ptr %t566, ptr %t567
  %t568 = getelementptr ptr, ptr %t565, i32 1
  store ptr %t564, ptr %t568
  br label %case.end.0.562
case.end.0.562:
  br label %case.join.560
case.arm.1.569:
  %t571 = getelementptr ptr, ptr %t555, i32 1
  %t572 = load ptr, ptr %t571
  %t573 = getelementptr [3 x i8], ptr @.str.14, i64 0, i64 0
  %t574 = call ptr @__concat(ptr %t572, ptr %t573)
  %t575 = getelementptr ptr, ptr %t574, i32 0
  %t576 = load ptr, ptr %t575
  %t577 = ptrtoint ptr %t576 to i64
  switch i64 %t577, label %case.default.578 [ i64 0, label %case.arm.0.580 i64 1, label %case.arm.1.588 ]
case.arm.0.580:
  %t582 = getelementptr ptr, ptr %t574, i32 1
  %t583 = load ptr, ptr %t582
  %t584 = call ptr @malloc(i64 16)
  %t585 = inttoptr i64 0 to ptr
  %t586 = getelementptr ptr, ptr %t584, i32 0
  store ptr %t585, ptr %t586
  %t587 = getelementptr ptr, ptr %t584, i32 1
  store ptr %t583, ptr %t587
  br label %case.end.0.581
case.end.0.581:
  br label %case.join.579
case.arm.1.588:
  %t590 = getelementptr ptr, ptr %t574, i32 1
  %t591 = load ptr, ptr %t590
  %t592 = call ptr @__concat(ptr %t591, ptr %t219)
  %t593 = getelementptr ptr, ptr %t592, i32 0
  %t594 = load ptr, ptr %t593
  %t595 = ptrtoint ptr %t594 to i64
  switch i64 %t595, label %case.default.596 [ i64 0, label %case.arm.0.598 i64 1, label %case.arm.1.606 ]
case.arm.0.598:
  %t600 = getelementptr ptr, ptr %t592, i32 1
  %t601 = load ptr, ptr %t600
  %t602 = call ptr @malloc(i64 16)
  %t603 = inttoptr i64 0 to ptr
  %t604 = getelementptr ptr, ptr %t602, i32 0
  store ptr %t603, ptr %t604
  %t605 = getelementptr ptr, ptr %t602, i32 1
  store ptr %t601, ptr %t605
  br label %case.end.0.599
case.end.0.599:
  br label %case.join.597
case.arm.1.606:
  %t608 = getelementptr ptr, ptr %t592, i32 1
  %t609 = load ptr, ptr %t608
  %t610 = getelementptr [3 x i8], ptr @.str.14, i64 0, i64 0
  %t611 = call ptr @__concat(ptr %t609, ptr %t610)
  %t612 = getelementptr ptr, ptr %t611, i32 0
  %t613 = load ptr, ptr %t612
  %t614 = ptrtoint ptr %t613 to i64
  switch i64 %t614, label %case.default.615 [ i64 0, label %case.arm.0.617 i64 1, label %case.arm.1.625 ]
case.arm.0.617:
  %t619 = getelementptr ptr, ptr %t611, i32 1
  %t620 = load ptr, ptr %t619
  %t621 = call ptr @malloc(i64 16)
  %t622 = inttoptr i64 0 to ptr
  %t623 = getelementptr ptr, ptr %t621, i32 0
  store ptr %t622, ptr %t623
  %t624 = getelementptr ptr, ptr %t621, i32 1
  store ptr %t620, ptr %t624
  br label %case.end.0.618
case.end.0.618:
  br label %case.join.616
case.arm.1.625:
  %t627 = getelementptr ptr, ptr %t611, i32 1
  %t628 = load ptr, ptr %t627
  %t629 = call ptr @__concat(ptr %t628, ptr %t239)
  br label %case.end.1.626
case.end.1.626:
  br label %case.join.616
case.default.615:
  unreachable
case.join.616:
  %t630 = phi ptr [%t621, %case.end.0.618], [%t629, %case.end.1.626]
  br label %case.end.1.607
case.end.1.607:
  br label %case.join.597
case.default.596:
  unreachable
case.join.597:
  %t631 = phi ptr [%t602, %case.end.0.599], [%t630, %case.end.1.607]
  br label %case.end.1.589
case.end.1.589:
  br label %case.join.579
case.default.578:
  unreachable
case.join.579:
  %t632 = phi ptr [%t584, %case.end.0.581], [%t631, %case.end.1.589]
  br label %case.end.1.570
case.end.1.570:
  br label %case.join.560
case.default.559:
  unreachable
case.join.560:
  %t633 = phi ptr [%t565, %case.end.0.562], [%t632, %case.end.1.570]
  br label %case.end.1.552
case.end.1.552:
  br label %case.join.542
case.default.541:
  unreachable
case.join.542:
  %t634 = phi ptr [%t547, %case.end.0.544], [%t633, %case.end.1.552]
  br label %case.end.1.533
case.end.1.533:
  br label %case.join.523
case.default.522:
  unreachable
case.join.523:
  %t635 = phi ptr [%t528, %case.end.0.525], [%t634, %case.end.1.533]
  br label %case.end.1.515
case.end.1.515:
  br label %case.join.505
case.default.504:
  unreachable
case.join.505:
  %t636 = phi ptr [%t510, %case.end.0.507], [%t635, %case.end.1.515]
  br label %case.end.1.496
case.end.1.496:
  br label %case.join.486
case.default.485:
  unreachable
case.join.486:
  %t637 = phi ptr [%t491, %case.end.0.488], [%t636, %case.end.1.496]
  br label %case.end.1.478
case.end.1.478:
  br label %case.join.468
case.default.467:
  unreachable
case.join.468:
  %t638 = phi ptr [%t473, %case.end.0.470], [%t637, %case.end.1.478]
  br label %case.end.1.459
case.end.1.459:
  br label %case.join.449
case.default.448:
  unreachable
case.join.449:
  %t639 = phi ptr [%t454, %case.end.0.451], [%t638, %case.end.1.459]
  br label %case.end.1.441
case.end.1.441:
  br label %case.join.431
case.default.430:
  unreachable
case.join.431:
  %t640 = phi ptr [%t436, %case.end.0.433], [%t639, %case.end.1.441]
  br label %case.end.1.422
case.end.1.422:
  br label %case.join.412
case.default.411:
  unreachable
case.join.412:
  %t641 = phi ptr [%t417, %case.end.0.414], [%t640, %case.end.1.422]
  br label %case.end.1.404
case.end.1.404:
  br label %case.join.394
case.default.393:
  unreachable
case.join.394:
  %t642 = phi ptr [%t399, %case.end.0.396], [%t641, %case.end.1.404]
  br label %case.end.1.385
case.end.1.385:
  br label %case.join.375
case.default.374:
  unreachable
case.join.375:
  %t643 = phi ptr [%t380, %case.end.0.377], [%t642, %case.end.1.385]
  br label %case.end.1.367
case.end.1.367:
  br label %case.join.357
case.default.356:
  unreachable
case.join.357:
  %t644 = phi ptr [%t362, %case.end.0.359], [%t643, %case.end.1.367]
  br label %case.end.1.348
case.end.1.348:
  br label %case.join.338
case.default.337:
  unreachable
case.join.338:
  %t645 = phi ptr [%t343, %case.end.0.340], [%t644, %case.end.1.348]
  br label %case.end.1.330
case.end.1.330:
  br label %case.join.320
case.default.319:
  unreachable
case.join.320:
  %t646 = phi ptr [%t325, %case.end.0.322], [%t645, %case.end.1.330]
  br label %case.end.1.311
case.end.1.311:
  br label %case.join.301
case.default.300:
  unreachable
case.join.301:
  %t647 = phi ptr [%t306, %case.end.0.303], [%t646, %case.end.1.311]
  br label %case.end.1.293
case.end.1.293:
  br label %case.join.283
case.default.282:
  unreachable
case.join.283:
  %t648 = phi ptr [%t288, %case.end.0.285], [%t647, %case.end.1.293]
  br label %case.end.1.274
case.end.1.274:
  br label %case.join.264
case.default.263:
  unreachable
case.join.264:
  %t649 = phi ptr [%t269, %case.end.0.266], [%t648, %case.end.1.274]
  br label %case.end.1.256
case.end.1.256:
  br label %case.join.246
case.default.245:
  unreachable
case.join.246:
  %t650 = phi ptr [%t251, %case.end.0.248], [%t649, %case.end.1.256]
  br label %case.end.1.237
case.end.1.237:
  br label %case.join.227
case.default.226:
  unreachable
case.join.227:
  %t651 = phi ptr [%t232, %case.end.0.229], [%t650, %case.end.1.237]
  br label %case.end.1.217
case.end.1.217:
  br label %case.join.207
case.default.206:
  unreachable
case.join.207:
  %t652 = phi ptr [%t212, %case.end.0.209], [%t651, %case.end.1.217]
  br label %case.end.1.197
case.end.1.197:
  br label %case.join.187
case.default.186:
  unreachable
case.join.187:
  %t653 = phi ptr [%t192, %case.end.0.189], [%t652, %case.end.1.197]
  br label %case.end.1.177
case.end.1.177:
  br label %case.join.167
case.default.166:
  unreachable
case.join.167:
  %t654 = phi ptr [%t172, %case.end.0.169], [%t653, %case.end.1.177]
  br label %case.end.1.157
case.end.1.157:
  br label %case.join.147
case.default.146:
  unreachable
case.join.147:
  %t655 = phi ptr [%t152, %case.end.0.149], [%t654, %case.end.1.157]
  br label %case.end.1.137
case.end.1.137:
  br label %case.join.127
case.default.126:
  unreachable
case.join.127:
  %t656 = phi ptr [%t132, %case.end.0.129], [%t655, %case.end.1.137]
  br label %case.end.1.117
case.end.1.117:
  br label %case.join.107
case.default.106:
  unreachable
case.join.107:
  %t657 = phi ptr [%t112, %case.end.0.109], [%t656, %case.end.1.117]
  br label %case.end.1.97
case.end.1.97:
  br label %case.join.87
case.default.86:
  unreachable
case.join.87:
  %t658 = phi ptr [%t92, %case.end.0.89], [%t657, %case.end.1.97]
  br label %case.end.1.77
case.end.1.77:
  br label %case.join.67
case.default.66:
  unreachable
case.join.67:
  %t659 = phi ptr [%t72, %case.end.0.69], [%t658, %case.end.1.77]
  br label %case.end.1.57
case.end.1.57:
  br label %case.join.47
case.default.46:
  unreachable
case.join.47:
  %t660 = phi ptr [%t52, %case.end.0.49], [%t659, %case.end.1.57]
  br label %case.end.1.37
case.end.1.37:
  br label %case.join.27
case.default.26:
  unreachable
case.join.27:
  %t661 = phi ptr [%t32, %case.end.0.29], [%t660, %case.end.1.37]
  br label %case.end.1.17
case.end.1.17:
  br label %case.join.7
case.default.6:
  unreachable
case.join.7:
  %t662 = phi ptr [%t12, %case.end.0.9], [%t661, %case.end.1.17]
  %t663 = call ptr @v__let_2(ptr %t662)
  ret ptr %t663
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
