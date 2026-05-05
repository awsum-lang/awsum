; External C declarations
declare ptr @malloc(i64)
declare ptr @strcpy(ptr, ptr)
declare ptr @strcat(ptr, ptr)
declare i64 @strlen(ptr)
declare i32 @printf(ptr, ...)
declare i32 @snprintf(ptr, i64, ptr, ...)
declare ptr @strstr(ptr, ptr)
declare ptr @memcpy(ptr, ptr, i64)

@.fmt = private unnamed_addr constant [3 x i8] c"%s\00"
@.fmt_i32 = private unnamed_addr constant [3 x i8] c"%d\00"
@.fmt_u8 = private unnamed_addr constant [3 x i8] c"%u\00"
@.empty = private unnamed_addr constant [1 x i8] c"\00"

@.str.0 = private unnamed_addr constant [8 x i8] c"Nothing\00"
@.str.1 = private unnamed_addr constant [6 x i8] c"Just(\00"
@.str.2 = private unnamed_addr constant [2 x i8] c"|\00"
@.str.3 = private unnamed_addr constant [2 x i8] c")\00"
@.str.4 = private unnamed_addr constant [2 x i8] c",\00"
@.str.5 = private unnamed_addr constant [6 x i8] c"a,b,c\00"
@.str.6 = private unnamed_addr constant [3 x i8] c"::\00"
@.str.7 = private unnamed_addr constant [16 x i8] c"user::42::admin\00"
@.str.8 = private unnamed_addr constant [2 x i8] c"x\00"
@.str.9 = private unnamed_addr constant [4 x i8] c"abc\00"
@.str.10 = private unnamed_addr constant [1 x i8] c"\00"
@.str.11 = private unnamed_addr constant [2 x i8] c":\00"
@.str.12 = private unnamed_addr constant [5 x i8] c":foo\00"
@.str.13 = private unnamed_addr constant [5 x i8] c"foo:\00"
@.str.14 = private unnamed_addr constant [6 x i8] c"abcde\00"
@.str.15 = private unnamed_addr constant [3 x i8] c"ab\00"
@.str.16 = private unnamed_addr constant [3 x i8] c", \00"
@.str.17 = private unnamed_addr constant [16 x i8] c"STRING_TOO_LONG\00"

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


define internal ptr @__splitOnFirst(ptr %sep, ptr %str) {
  %pos = call ptr @strstr(ptr %str, ptr %sep)
  %is_null = icmp eq ptr %pos, null
  br i1 %is_null, label %not_found, label %found
not_found:
  %nothing = call ptr @malloc(i64 8)
  %nothing_tag = inttoptr i64 0 to ptr
  store ptr %nothing_tag, ptr %nothing
  ret ptr %nothing
found:
  %str_int = ptrtoint ptr %str to i64
  %pos_int = ptrtoint ptr %pos to i64
  %prefix_len = sub i64 %pos_int, %str_int
  %sep_len = call i64 @strlen(ptr %sep)
  %suffix_start = getelementptr i8, ptr %pos, i64 %sep_len
  %suffix_len = call i64 @strlen(ptr %suffix_start)
  %prefix_total = add i64 %prefix_len, 1
  %prefix = call ptr @malloc(i64 %prefix_total)
  call ptr @memcpy(ptr %prefix, ptr %str, i64 %prefix_len)
  %prefix_term = getelementptr i8, ptr %prefix, i64 %prefix_len
  store i8 0, ptr %prefix_term
  %suffix_total = add i64 %suffix_len, 1
  %suffix = call ptr @malloc(i64 %suffix_total)
  call ptr @memcpy(ptr %suffix, ptr %suffix_start, i64 %suffix_len)
  %suffix_term = getelementptr i8, ptr %suffix, i64 %suffix_len
  store i8 0, ptr %suffix_term
  %tuple = call ptr @malloc(i64 24)
  %tuple_tag = inttoptr i64 0 to ptr
  store ptr %tuple_tag, ptr %tuple
  %tuple_a = getelementptr ptr, ptr %tuple, i32 1
  store ptr %prefix, ptr %tuple_a
  %tuple_b = getelementptr ptr, ptr %tuple, i32 2
  store ptr %suffix, ptr %tuple_b
  %just = call ptr @malloc(i64 16)
  %just_tag = inttoptr i64 1 to ptr
  store ptr %just_tag, ptr %just
  %just_f = getelementptr ptr, ptr %just, i32 1
  store ptr %tuple, ptr %just_f
  ret ptr %just
}


define internal ptr @v_render(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.12 ]
case.arm.0.5:
  %t7 = call ptr @malloc(i64 16)
  %t8 = inttoptr i64 1 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = getelementptr [8 x i8], ptr @.str.0, i64 0, i64 0
  %t11 = getelementptr ptr, ptr %t7, i32 1
  store ptr %t10, ptr %t11
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.12:
  %t14 = getelementptr ptr, ptr %v_r, i32 1
  %t15 = load ptr, ptr %t14
  %t16 = getelementptr ptr, ptr %t15, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %case.default.19 [ i64 0, label %case.arm.0.21 ]
case.arm.0.21:
  %t23 = getelementptr ptr, ptr %t15, i32 1
  %t24 = load ptr, ptr %t23
  %t25 = getelementptr ptr, ptr %t15, i32 2
  %t26 = load ptr, ptr %t25
  %t27 = call ptr @v_renderTuple(ptr %t24, ptr %t26)
  br label %case.end.0.22
case.end.0.22:
  br label %case.join.20
case.default.19:
  unreachable
case.join.20:
  %t28 = phi ptr [%t27, %case.end.0.22]
  br label %case.end.1.13
case.end.1.13:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t29 = phi ptr [%t7, %case.end.0.6], [%t28, %case.end.1.13]
  ret ptr %t29
}

define internal ptr @v_renderTuple(ptr %v_a, ptr %v_b) {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr [6 x i8], ptr @.str.1, i64 0, i64 0
  %t4 = call ptr @__concat(ptr %t3, ptr %v_a)
  %t5 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 0
  %t7 = load ptr, ptr %t6
  %t8 = ptrtoint ptr %t7 to i64
  switch i64 %t8, label %case.default.9 [ i64 0, label %case.arm.0.11 i64 1, label %case.arm.1.19 ]
case.arm.0.11:
  %t13 = getelementptr ptr, ptr %t0, i32 1
  %t14 = load ptr, ptr %t13
  %t15 = call ptr @malloc(i64 16)
  %t16 = inttoptr i64 0 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = getelementptr ptr, ptr %t15, i32 1
  store ptr %t14, ptr %t18
  br label %case.end.0.12
case.end.0.12:
  br label %case.join.10
case.arm.1.19:
  %t21 = getelementptr ptr, ptr %t0, i32 1
  %t22 = load ptr, ptr %t21
  %t23 = call ptr @malloc(i64 16)
  %t24 = inttoptr i64 1 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  %t26 = getelementptr [2 x i8], ptr @.str.2, i64 0, i64 0
  %t27 = call ptr @__concat(ptr %t22, ptr %t26)
  %t28 = getelementptr ptr, ptr %t23, i32 1
  store ptr %t27, ptr %t28
  %t29 = getelementptr ptr, ptr %t23, i32 0
  %t30 = load ptr, ptr %t29
  %t31 = ptrtoint ptr %t30 to i64
  switch i64 %t31, label %case.default.32 [ i64 0, label %case.arm.0.34 i64 1, label %case.arm.1.42 ]
case.arm.0.34:
  %t36 = getelementptr ptr, ptr %t23, i32 1
  %t37 = load ptr, ptr %t36
  %t38 = call ptr @malloc(i64 16)
  %t39 = inttoptr i64 0 to ptr
  %t40 = getelementptr ptr, ptr %t38, i32 0
  store ptr %t39, ptr %t40
  %t41 = getelementptr ptr, ptr %t38, i32 1
  store ptr %t37, ptr %t41
  br label %case.end.0.35
case.end.0.35:
  br label %case.join.33
case.arm.1.42:
  %t44 = getelementptr ptr, ptr %t23, i32 1
  %t45 = load ptr, ptr %t44
  %t46 = call ptr @malloc(i64 16)
  %t47 = inttoptr i64 1 to ptr
  %t48 = getelementptr ptr, ptr %t46, i32 0
  store ptr %t47, ptr %t48
  %t49 = call ptr @__concat(ptr %t45, ptr %v_b)
  %t50 = getelementptr ptr, ptr %t46, i32 1
  store ptr %t49, ptr %t50
  %t51 = getelementptr ptr, ptr %t46, i32 0
  %t52 = load ptr, ptr %t51
  %t53 = ptrtoint ptr %t52 to i64
  switch i64 %t53, label %case.default.54 [ i64 0, label %case.arm.0.56 i64 1, label %case.arm.1.64 ]
case.arm.0.56:
  %t58 = getelementptr ptr, ptr %t46, i32 1
  %t59 = load ptr, ptr %t58
  %t60 = call ptr @malloc(i64 16)
  %t61 = inttoptr i64 0 to ptr
  %t62 = getelementptr ptr, ptr %t60, i32 0
  store ptr %t61, ptr %t62
  %t63 = getelementptr ptr, ptr %t60, i32 1
  store ptr %t59, ptr %t63
  br label %case.end.0.57
case.end.0.57:
  br label %case.join.55
case.arm.1.64:
  %t66 = getelementptr ptr, ptr %t46, i32 1
  %t67 = load ptr, ptr %t66
  %t68 = call ptr @malloc(i64 16)
  %t69 = inttoptr i64 1 to ptr
  %t70 = getelementptr ptr, ptr %t68, i32 0
  store ptr %t69, ptr %t70
  %t71 = getelementptr [2 x i8], ptr @.str.3, i64 0, i64 0
  %t72 = call ptr @__concat(ptr %t67, ptr %t71)
  %t73 = getelementptr ptr, ptr %t68, i32 1
  store ptr %t72, ptr %t73
  br label %case.end.1.65
case.end.1.65:
  br label %case.join.55
case.default.54:
  unreachable
case.join.55:
  %t74 = phi ptr [%t60, %case.end.0.57], [%t68, %case.end.1.65]
  br label %case.end.1.43
case.end.1.43:
  br label %case.join.33
case.default.32:
  unreachable
case.join.33:
  %t75 = phi ptr [%t38, %case.end.0.35], [%t74, %case.end.1.43]
  br label %case.end.1.20
case.end.1.20:
  br label %case.join.10
case.default.9:
  unreachable
case.join.10:
  %t76 = phi ptr [%t15, %case.end.0.12], [%t75, %case.end.1.20]
  ret ptr %t76
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = getelementptr [2 x i8], ptr @.str.4, i64 0, i64 0
  %t1 = getelementptr [6 x i8], ptr @.str.5, i64 0, i64 0
  %t2 = call ptr @__splitOnFirst(ptr %t0, ptr %t1)
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
  %t21 = getelementptr [3 x i8], ptr @.str.6, i64 0, i64 0
  %t22 = getelementptr [16 x i8], ptr @.str.7, i64 0, i64 0
  %t23 = call ptr @__splitOnFirst(ptr %t21, ptr %t22)
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
  %t42 = getelementptr [2 x i8], ptr @.str.8, i64 0, i64 0
  %t43 = getelementptr [4 x i8], ptr @.str.9, i64 0, i64 0
  %t44 = call ptr @__splitOnFirst(ptr %t42, ptr %t43)
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
  %t63 = getelementptr [1 x i8], ptr @.str.10, i64 0, i64 0
  %t64 = getelementptr [4 x i8], ptr @.str.9, i64 0, i64 0
  %t65 = call ptr @__splitOnFirst(ptr %t63, ptr %t64)
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
  %t84 = getelementptr [2 x i8], ptr @.str.11, i64 0, i64 0
  %t85 = getelementptr [5 x i8], ptr @.str.12, i64 0, i64 0
  %t86 = call ptr @__splitOnFirst(ptr %t84, ptr %t85)
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
  %t105 = getelementptr [2 x i8], ptr @.str.11, i64 0, i64 0
  %t106 = getelementptr [5 x i8], ptr @.str.13, i64 0, i64 0
  %t107 = call ptr @__splitOnFirst(ptr %t105, ptr %t106)
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
  %t126 = getelementptr [4 x i8], ptr @.str.9, i64 0, i64 0
  %t127 = getelementptr [4 x i8], ptr @.str.9, i64 0, i64 0
  %t128 = call ptr @__splitOnFirst(ptr %t126, ptr %t127)
  %t129 = call ptr @v_render(ptr %t128)
  %t130 = getelementptr ptr, ptr %t129, i32 0
  %t131 = load ptr, ptr %t130
  %t132 = ptrtoint ptr %t131 to i64
  switch i64 %t132, label %case.default.133 [ i64 0, label %case.arm.0.135 i64 1, label %case.arm.1.143 ]
case.arm.0.135:
  %t137 = getelementptr ptr, ptr %t129, i32 1
  %t138 = load ptr, ptr %t137
  %t139 = call ptr @malloc(i64 16)
  %t140 = inttoptr i64 0 to ptr
  %t141 = getelementptr ptr, ptr %t139, i32 0
  store ptr %t140, ptr %t141
  %t142 = getelementptr ptr, ptr %t139, i32 1
  store ptr %t138, ptr %t142
  br label %case.end.0.136
case.end.0.136:
  br label %case.join.134
case.arm.1.143:
  %t145 = getelementptr ptr, ptr %t129, i32 1
  %t146 = load ptr, ptr %t145
  %t147 = getelementptr [6 x i8], ptr @.str.14, i64 0, i64 0
  %t148 = getelementptr [3 x i8], ptr @.str.15, i64 0, i64 0
  %t149 = call ptr @__splitOnFirst(ptr %t147, ptr %t148)
  %t150 = call ptr @v_render(ptr %t149)
  %t151 = getelementptr ptr, ptr %t150, i32 0
  %t152 = load ptr, ptr %t151
  %t153 = ptrtoint ptr %t152 to i64
  switch i64 %t153, label %case.default.154 [ i64 0, label %case.arm.0.156 i64 1, label %case.arm.1.164 ]
case.arm.0.156:
  %t158 = getelementptr ptr, ptr %t150, i32 1
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
  %t166 = getelementptr ptr, ptr %t150, i32 1
  %t167 = load ptr, ptr %t166
  %t168 = call ptr @malloc(i64 16)
  %t169 = inttoptr i64 1 to ptr
  %t170 = getelementptr ptr, ptr %t168, i32 0
  store ptr %t169, ptr %t170
  %t171 = getelementptr [3 x i8], ptr @.str.16, i64 0, i64 0
  %t172 = call ptr @__concat(ptr %t20, ptr %t171)
  %t173 = getelementptr ptr, ptr %t168, i32 1
  store ptr %t172, ptr %t173
  %t174 = getelementptr ptr, ptr %t168, i32 0
  %t175 = load ptr, ptr %t174
  %t176 = ptrtoint ptr %t175 to i64
  switch i64 %t176, label %case.default.177 [ i64 0, label %case.arm.0.179 i64 1, label %case.arm.1.187 ]
case.arm.0.179:
  %t181 = getelementptr ptr, ptr %t168, i32 1
  %t182 = load ptr, ptr %t181
  %t183 = call ptr @malloc(i64 16)
  %t184 = inttoptr i64 0 to ptr
  %t185 = getelementptr ptr, ptr %t183, i32 0
  store ptr %t184, ptr %t185
  %t186 = getelementptr ptr, ptr %t183, i32 1
  store ptr %t182, ptr %t186
  br label %case.end.0.180
case.end.0.180:
  br label %case.join.178
case.arm.1.187:
  %t189 = getelementptr ptr, ptr %t168, i32 1
  %t190 = load ptr, ptr %t189
  %t191 = call ptr @malloc(i64 16)
  %t192 = inttoptr i64 1 to ptr
  %t193 = getelementptr ptr, ptr %t191, i32 0
  store ptr %t192, ptr %t193
  %t194 = call ptr @__concat(ptr %t190, ptr %t41)
  %t195 = getelementptr ptr, ptr %t191, i32 1
  store ptr %t194, ptr %t195
  %t196 = getelementptr ptr, ptr %t191, i32 0
  %t197 = load ptr, ptr %t196
  %t198 = ptrtoint ptr %t197 to i64
  switch i64 %t198, label %case.default.199 [ i64 0, label %case.arm.0.201 i64 1, label %case.arm.1.209 ]
case.arm.0.201:
  %t203 = getelementptr ptr, ptr %t191, i32 1
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
  %t211 = getelementptr ptr, ptr %t191, i32 1
  %t212 = load ptr, ptr %t211
  %t213 = call ptr @malloc(i64 16)
  %t214 = inttoptr i64 1 to ptr
  %t215 = getelementptr ptr, ptr %t213, i32 0
  store ptr %t214, ptr %t215
  %t216 = getelementptr [3 x i8], ptr @.str.16, i64 0, i64 0
  %t217 = call ptr @__concat(ptr %t212, ptr %t216)
  %t218 = getelementptr ptr, ptr %t213, i32 1
  store ptr %t217, ptr %t218
  %t219 = getelementptr ptr, ptr %t213, i32 0
  %t220 = load ptr, ptr %t219
  %t221 = ptrtoint ptr %t220 to i64
  switch i64 %t221, label %case.default.222 [ i64 0, label %case.arm.0.224 i64 1, label %case.arm.1.232 ]
case.arm.0.224:
  %t226 = getelementptr ptr, ptr %t213, i32 1
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
  %t234 = getelementptr ptr, ptr %t213, i32 1
  %t235 = load ptr, ptr %t234
  %t236 = call ptr @malloc(i64 16)
  %t237 = inttoptr i64 1 to ptr
  %t238 = getelementptr ptr, ptr %t236, i32 0
  store ptr %t237, ptr %t238
  %t239 = call ptr @__concat(ptr %t235, ptr %t62)
  %t240 = getelementptr ptr, ptr %t236, i32 1
  store ptr %t239, ptr %t240
  %t241 = getelementptr ptr, ptr %t236, i32 0
  %t242 = load ptr, ptr %t241
  %t243 = ptrtoint ptr %t242 to i64
  switch i64 %t243, label %case.default.244 [ i64 0, label %case.arm.0.246 i64 1, label %case.arm.1.254 ]
case.arm.0.246:
  %t248 = getelementptr ptr, ptr %t236, i32 1
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
  %t256 = getelementptr ptr, ptr %t236, i32 1
  %t257 = load ptr, ptr %t256
  %t258 = call ptr @malloc(i64 16)
  %t259 = inttoptr i64 1 to ptr
  %t260 = getelementptr ptr, ptr %t258, i32 0
  store ptr %t259, ptr %t260
  %t261 = getelementptr [3 x i8], ptr @.str.16, i64 0, i64 0
  %t262 = call ptr @__concat(ptr %t257, ptr %t261)
  %t263 = getelementptr ptr, ptr %t258, i32 1
  store ptr %t262, ptr %t263
  %t264 = getelementptr ptr, ptr %t258, i32 0
  %t265 = load ptr, ptr %t264
  %t266 = ptrtoint ptr %t265 to i64
  switch i64 %t266, label %case.default.267 [ i64 0, label %case.arm.0.269 i64 1, label %case.arm.1.277 ]
case.arm.0.269:
  %t271 = getelementptr ptr, ptr %t258, i32 1
  %t272 = load ptr, ptr %t271
  %t273 = call ptr @malloc(i64 16)
  %t274 = inttoptr i64 0 to ptr
  %t275 = getelementptr ptr, ptr %t273, i32 0
  store ptr %t274, ptr %t275
  %t276 = getelementptr ptr, ptr %t273, i32 1
  store ptr %t272, ptr %t276
  br label %case.end.0.270
case.end.0.270:
  br label %case.join.268
case.arm.1.277:
  %t279 = getelementptr ptr, ptr %t258, i32 1
  %t280 = load ptr, ptr %t279
  %t281 = call ptr @malloc(i64 16)
  %t282 = inttoptr i64 1 to ptr
  %t283 = getelementptr ptr, ptr %t281, i32 0
  store ptr %t282, ptr %t283
  %t284 = call ptr @__concat(ptr %t280, ptr %t83)
  %t285 = getelementptr ptr, ptr %t281, i32 1
  store ptr %t284, ptr %t285
  %t286 = getelementptr ptr, ptr %t281, i32 0
  %t287 = load ptr, ptr %t286
  %t288 = ptrtoint ptr %t287 to i64
  switch i64 %t288, label %case.default.289 [ i64 0, label %case.arm.0.291 i64 1, label %case.arm.1.299 ]
case.arm.0.291:
  %t293 = getelementptr ptr, ptr %t281, i32 1
  %t294 = load ptr, ptr %t293
  %t295 = call ptr @malloc(i64 16)
  %t296 = inttoptr i64 0 to ptr
  %t297 = getelementptr ptr, ptr %t295, i32 0
  store ptr %t296, ptr %t297
  %t298 = getelementptr ptr, ptr %t295, i32 1
  store ptr %t294, ptr %t298
  br label %case.end.0.292
case.end.0.292:
  br label %case.join.290
case.arm.1.299:
  %t301 = getelementptr ptr, ptr %t281, i32 1
  %t302 = load ptr, ptr %t301
  %t303 = call ptr @malloc(i64 16)
  %t304 = inttoptr i64 1 to ptr
  %t305 = getelementptr ptr, ptr %t303, i32 0
  store ptr %t304, ptr %t305
  %t306 = getelementptr [3 x i8], ptr @.str.16, i64 0, i64 0
  %t307 = call ptr @__concat(ptr %t302, ptr %t306)
  %t308 = getelementptr ptr, ptr %t303, i32 1
  store ptr %t307, ptr %t308
  %t309 = getelementptr ptr, ptr %t303, i32 0
  %t310 = load ptr, ptr %t309
  %t311 = ptrtoint ptr %t310 to i64
  switch i64 %t311, label %case.default.312 [ i64 0, label %case.arm.0.314 i64 1, label %case.arm.1.322 ]
case.arm.0.314:
  %t316 = getelementptr ptr, ptr %t303, i32 1
  %t317 = load ptr, ptr %t316
  %t318 = call ptr @malloc(i64 16)
  %t319 = inttoptr i64 0 to ptr
  %t320 = getelementptr ptr, ptr %t318, i32 0
  store ptr %t319, ptr %t320
  %t321 = getelementptr ptr, ptr %t318, i32 1
  store ptr %t317, ptr %t321
  br label %case.end.0.315
case.end.0.315:
  br label %case.join.313
case.arm.1.322:
  %t324 = getelementptr ptr, ptr %t303, i32 1
  %t325 = load ptr, ptr %t324
  %t326 = call ptr @malloc(i64 16)
  %t327 = inttoptr i64 1 to ptr
  %t328 = getelementptr ptr, ptr %t326, i32 0
  store ptr %t327, ptr %t328
  %t329 = call ptr @__concat(ptr %t325, ptr %t104)
  %t330 = getelementptr ptr, ptr %t326, i32 1
  store ptr %t329, ptr %t330
  %t331 = getelementptr ptr, ptr %t326, i32 0
  %t332 = load ptr, ptr %t331
  %t333 = ptrtoint ptr %t332 to i64
  switch i64 %t333, label %case.default.334 [ i64 0, label %case.arm.0.336 i64 1, label %case.arm.1.344 ]
case.arm.0.336:
  %t338 = getelementptr ptr, ptr %t326, i32 1
  %t339 = load ptr, ptr %t338
  %t340 = call ptr @malloc(i64 16)
  %t341 = inttoptr i64 0 to ptr
  %t342 = getelementptr ptr, ptr %t340, i32 0
  store ptr %t341, ptr %t342
  %t343 = getelementptr ptr, ptr %t340, i32 1
  store ptr %t339, ptr %t343
  br label %case.end.0.337
case.end.0.337:
  br label %case.join.335
case.arm.1.344:
  %t346 = getelementptr ptr, ptr %t326, i32 1
  %t347 = load ptr, ptr %t346
  %t348 = call ptr @malloc(i64 16)
  %t349 = inttoptr i64 1 to ptr
  %t350 = getelementptr ptr, ptr %t348, i32 0
  store ptr %t349, ptr %t350
  %t351 = getelementptr [3 x i8], ptr @.str.16, i64 0, i64 0
  %t352 = call ptr @__concat(ptr %t347, ptr %t351)
  %t353 = getelementptr ptr, ptr %t348, i32 1
  store ptr %t352, ptr %t353
  %t354 = getelementptr ptr, ptr %t348, i32 0
  %t355 = load ptr, ptr %t354
  %t356 = ptrtoint ptr %t355 to i64
  switch i64 %t356, label %case.default.357 [ i64 0, label %case.arm.0.359 i64 1, label %case.arm.1.367 ]
case.arm.0.359:
  %t361 = getelementptr ptr, ptr %t348, i32 1
  %t362 = load ptr, ptr %t361
  %t363 = call ptr @malloc(i64 16)
  %t364 = inttoptr i64 0 to ptr
  %t365 = getelementptr ptr, ptr %t363, i32 0
  store ptr %t364, ptr %t365
  %t366 = getelementptr ptr, ptr %t363, i32 1
  store ptr %t362, ptr %t366
  br label %case.end.0.360
case.end.0.360:
  br label %case.join.358
case.arm.1.367:
  %t369 = getelementptr ptr, ptr %t348, i32 1
  %t370 = load ptr, ptr %t369
  %t371 = call ptr @malloc(i64 16)
  %t372 = inttoptr i64 1 to ptr
  %t373 = getelementptr ptr, ptr %t371, i32 0
  store ptr %t372, ptr %t373
  %t374 = call ptr @__concat(ptr %t370, ptr %t125)
  %t375 = getelementptr ptr, ptr %t371, i32 1
  store ptr %t374, ptr %t375
  %t376 = getelementptr ptr, ptr %t371, i32 0
  %t377 = load ptr, ptr %t376
  %t378 = ptrtoint ptr %t377 to i64
  switch i64 %t378, label %case.default.379 [ i64 0, label %case.arm.0.381 i64 1, label %case.arm.1.389 ]
case.arm.0.381:
  %t383 = getelementptr ptr, ptr %t371, i32 1
  %t384 = load ptr, ptr %t383
  %t385 = call ptr @malloc(i64 16)
  %t386 = inttoptr i64 0 to ptr
  %t387 = getelementptr ptr, ptr %t385, i32 0
  store ptr %t386, ptr %t387
  %t388 = getelementptr ptr, ptr %t385, i32 1
  store ptr %t384, ptr %t388
  br label %case.end.0.382
case.end.0.382:
  br label %case.join.380
case.arm.1.389:
  %t391 = getelementptr ptr, ptr %t371, i32 1
  %t392 = load ptr, ptr %t391
  %t393 = call ptr @malloc(i64 16)
  %t394 = inttoptr i64 1 to ptr
  %t395 = getelementptr ptr, ptr %t393, i32 0
  store ptr %t394, ptr %t395
  %t396 = getelementptr [3 x i8], ptr @.str.16, i64 0, i64 0
  %t397 = call ptr @__concat(ptr %t392, ptr %t396)
  %t398 = getelementptr ptr, ptr %t393, i32 1
  store ptr %t397, ptr %t398
  %t399 = getelementptr ptr, ptr %t393, i32 0
  %t400 = load ptr, ptr %t399
  %t401 = ptrtoint ptr %t400 to i64
  switch i64 %t401, label %case.default.402 [ i64 0, label %case.arm.0.404 i64 1, label %case.arm.1.412 ]
case.arm.0.404:
  %t406 = getelementptr ptr, ptr %t393, i32 1
  %t407 = load ptr, ptr %t406
  %t408 = call ptr @malloc(i64 16)
  %t409 = inttoptr i64 0 to ptr
  %t410 = getelementptr ptr, ptr %t408, i32 0
  store ptr %t409, ptr %t410
  %t411 = getelementptr ptr, ptr %t408, i32 1
  store ptr %t407, ptr %t411
  br label %case.end.0.405
case.end.0.405:
  br label %case.join.403
case.arm.1.412:
  %t414 = getelementptr ptr, ptr %t393, i32 1
  %t415 = load ptr, ptr %t414
  %t416 = call ptr @malloc(i64 16)
  %t417 = inttoptr i64 1 to ptr
  %t418 = getelementptr ptr, ptr %t416, i32 0
  store ptr %t417, ptr %t418
  %t419 = call ptr @__concat(ptr %t415, ptr %t146)
  %t420 = getelementptr ptr, ptr %t416, i32 1
  store ptr %t419, ptr %t420
  %t421 = getelementptr ptr, ptr %t416, i32 0
  %t422 = load ptr, ptr %t421
  %t423 = ptrtoint ptr %t422 to i64
  switch i64 %t423, label %case.default.424 [ i64 0, label %case.arm.0.426 i64 1, label %case.arm.1.434 ]
case.arm.0.426:
  %t428 = getelementptr ptr, ptr %t416, i32 1
  %t429 = load ptr, ptr %t428
  %t430 = call ptr @malloc(i64 16)
  %t431 = inttoptr i64 0 to ptr
  %t432 = getelementptr ptr, ptr %t430, i32 0
  store ptr %t431, ptr %t432
  %t433 = getelementptr ptr, ptr %t430, i32 1
  store ptr %t429, ptr %t433
  br label %case.end.0.427
case.end.0.427:
  br label %case.join.425
case.arm.1.434:
  %t436 = getelementptr ptr, ptr %t416, i32 1
  %t437 = load ptr, ptr %t436
  %t438 = call ptr @malloc(i64 16)
  %t439 = inttoptr i64 1 to ptr
  %t440 = getelementptr ptr, ptr %t438, i32 0
  store ptr %t439, ptr %t440
  %t441 = getelementptr [3 x i8], ptr @.str.16, i64 0, i64 0
  %t442 = call ptr @__concat(ptr %t437, ptr %t441)
  %t443 = getelementptr ptr, ptr %t438, i32 1
  store ptr %t442, ptr %t443
  %t444 = getelementptr ptr, ptr %t438, i32 0
  %t445 = load ptr, ptr %t444
  %t446 = ptrtoint ptr %t445 to i64
  switch i64 %t446, label %case.default.447 [ i64 0, label %case.arm.0.449 i64 1, label %case.arm.1.457 ]
case.arm.0.449:
  %t451 = getelementptr ptr, ptr %t438, i32 1
  %t452 = load ptr, ptr %t451
  %t453 = call ptr @malloc(i64 16)
  %t454 = inttoptr i64 0 to ptr
  %t455 = getelementptr ptr, ptr %t453, i32 0
  store ptr %t454, ptr %t455
  %t456 = getelementptr ptr, ptr %t453, i32 1
  store ptr %t452, ptr %t456
  br label %case.end.0.450
case.end.0.450:
  br label %case.join.448
case.arm.1.457:
  %t459 = getelementptr ptr, ptr %t438, i32 1
  %t460 = load ptr, ptr %t459
  %t461 = call ptr @malloc(i64 16)
  %t462 = inttoptr i64 1 to ptr
  %t463 = getelementptr ptr, ptr %t461, i32 0
  store ptr %t462, ptr %t463
  %t464 = call ptr @__concat(ptr %t460, ptr %t167)
  %t465 = getelementptr ptr, ptr %t461, i32 1
  store ptr %t464, ptr %t465
  br label %case.end.1.458
case.end.1.458:
  br label %case.join.448
case.default.447:
  unreachable
case.join.448:
  %t466 = phi ptr [%t453, %case.end.0.450], [%t461, %case.end.1.458]
  br label %case.end.1.435
case.end.1.435:
  br label %case.join.425
case.default.424:
  unreachable
case.join.425:
  %t467 = phi ptr [%t430, %case.end.0.427], [%t466, %case.end.1.435]
  br label %case.end.1.413
case.end.1.413:
  br label %case.join.403
case.default.402:
  unreachable
case.join.403:
  %t468 = phi ptr [%t408, %case.end.0.405], [%t467, %case.end.1.413]
  br label %case.end.1.390
case.end.1.390:
  br label %case.join.380
case.default.379:
  unreachable
case.join.380:
  %t469 = phi ptr [%t385, %case.end.0.382], [%t468, %case.end.1.390]
  br label %case.end.1.368
case.end.1.368:
  br label %case.join.358
case.default.357:
  unreachable
case.join.358:
  %t470 = phi ptr [%t363, %case.end.0.360], [%t469, %case.end.1.368]
  br label %case.end.1.345
case.end.1.345:
  br label %case.join.335
case.default.334:
  unreachable
case.join.335:
  %t471 = phi ptr [%t340, %case.end.0.337], [%t470, %case.end.1.345]
  br label %case.end.1.323
case.end.1.323:
  br label %case.join.313
case.default.312:
  unreachable
case.join.313:
  %t472 = phi ptr [%t318, %case.end.0.315], [%t471, %case.end.1.323]
  br label %case.end.1.300
case.end.1.300:
  br label %case.join.290
case.default.289:
  unreachable
case.join.290:
  %t473 = phi ptr [%t295, %case.end.0.292], [%t472, %case.end.1.300]
  br label %case.end.1.278
case.end.1.278:
  br label %case.join.268
case.default.267:
  unreachable
case.join.268:
  %t474 = phi ptr [%t273, %case.end.0.270], [%t473, %case.end.1.278]
  br label %case.end.1.255
case.end.1.255:
  br label %case.join.245
case.default.244:
  unreachable
case.join.245:
  %t475 = phi ptr [%t250, %case.end.0.247], [%t474, %case.end.1.255]
  br label %case.end.1.233
case.end.1.233:
  br label %case.join.223
case.default.222:
  unreachable
case.join.223:
  %t476 = phi ptr [%t228, %case.end.0.225], [%t475, %case.end.1.233]
  br label %case.end.1.210
case.end.1.210:
  br label %case.join.200
case.default.199:
  unreachable
case.join.200:
  %t477 = phi ptr [%t205, %case.end.0.202], [%t476, %case.end.1.210]
  br label %case.end.1.188
case.end.1.188:
  br label %case.join.178
case.default.177:
  unreachable
case.join.178:
  %t478 = phi ptr [%t183, %case.end.0.180], [%t477, %case.end.1.188]
  br label %case.end.1.165
case.end.1.165:
  br label %case.join.155
case.default.154:
  unreachable
case.join.155:
  %t479 = phi ptr [%t160, %case.end.0.157], [%t478, %case.end.1.165]
  br label %case.end.1.144
case.end.1.144:
  br label %case.join.134
case.default.133:
  unreachable
case.join.134:
  %t480 = phi ptr [%t139, %case.end.0.136], [%t479, %case.end.1.144]
  br label %case.end.1.123
case.end.1.123:
  br label %case.join.113
case.default.112:
  unreachable
case.join.113:
  %t481 = phi ptr [%t118, %case.end.0.115], [%t480, %case.end.1.123]
  br label %case.end.1.102
case.end.1.102:
  br label %case.join.92
case.default.91:
  unreachable
case.join.92:
  %t482 = phi ptr [%t97, %case.end.0.94], [%t481, %case.end.1.102]
  br label %case.end.1.81
case.end.1.81:
  br label %case.join.71
case.default.70:
  unreachable
case.join.71:
  %t483 = phi ptr [%t76, %case.end.0.73], [%t482, %case.end.1.81]
  br label %case.end.1.60
case.end.1.60:
  br label %case.join.50
case.default.49:
  unreachable
case.join.50:
  %t484 = phi ptr [%t55, %case.end.0.52], [%t483, %case.end.1.60]
  br label %case.end.1.39
case.end.1.39:
  br label %case.join.29
case.default.28:
  unreachable
case.join.29:
  %t485 = phi ptr [%t34, %case.end.0.31], [%t484, %case.end.1.39]
  br label %case.end.1.18
case.end.1.18:
  br label %case.join.8
case.default.7:
  unreachable
case.join.8:
  %t486 = phi ptr [%t13, %case.end.0.10], [%t485, %case.end.1.18]
  %t487 = call ptr @v__let_1(ptr %t486)
  ret ptr %t487
}

define internal ptr @v__let_1(ptr %v_res) {
  %t0 = getelementptr ptr, ptr %v_res, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.11 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_res, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr [16 x i8], ptr @.str.17, i64 0, i64 0
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
