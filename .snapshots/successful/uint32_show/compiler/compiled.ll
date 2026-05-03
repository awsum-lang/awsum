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

@.str.0 = private unnamed_addr constant [3 x i8] c", \00"
@.str.1 = private unnamed_addr constant [16 x i8] c"STRING_TOO_LONG\00"

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


define internal ptr @__showUInt32(ptr %p) {
  %v = load i32, ptr %p
  %buf = call ptr @malloc(i64 16)
  call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 16, ptr @.fmt_u8, i32 %v)
  ret ptr %buf
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

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_minUInt32()
  %t4 = call ptr @__showUInt32(ptr %t3)
  %t5 = getelementptr [3 x i8], ptr @.str.0, i64 0, i64 0
  %t6 = call ptr @__concat(ptr %t4, ptr %t5)
  %t7 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t6, ptr %t7
  %t8 = getelementptr ptr, ptr %t0, i32 0
  %t9 = load ptr, ptr %t8
  %t10 = ptrtoint ptr %t9 to i64
  switch i64 %t10, label %case.default.11 [ i64 0, label %case.arm.0.13 i64 1, label %case.arm.1.21 ]
case.arm.0.13:
  %t15 = getelementptr ptr, ptr %t0, i32 1
  %t16 = load ptr, ptr %t15
  %t17 = call ptr @malloc(i64 16)
  %t18 = inttoptr i64 0 to ptr
  %t19 = getelementptr ptr, ptr %t17, i32 0
  store ptr %t18, ptr %t19
  %t20 = getelementptr ptr, ptr %t17, i32 1
  store ptr %t16, ptr %t20
  br label %case.end.0.14
case.end.0.14:
  br label %case.join.12
case.arm.1.21:
  %t23 = getelementptr ptr, ptr %t0, i32 1
  %t24 = load ptr, ptr %t23
  %t25 = call ptr @malloc(i64 16)
  %t26 = inttoptr i64 1 to ptr
  %t27 = getelementptr ptr, ptr %t25, i32 0
  store ptr %t26, ptr %t27
  %t28 = call ptr @malloc(i64 4)
  store i32 42, ptr %t28
  %t29 = call ptr @__showUInt32(ptr %t28)
  %t30 = call ptr @__concat(ptr %t24, ptr %t29)
  %t31 = getelementptr ptr, ptr %t25, i32 1
  store ptr %t30, ptr %t31
  %t32 = getelementptr ptr, ptr %t25, i32 0
  %t33 = load ptr, ptr %t32
  %t34 = ptrtoint ptr %t33 to i64
  switch i64 %t34, label %case.default.35 [ i64 0, label %case.arm.0.37 i64 1, label %case.arm.1.45 ]
case.arm.0.37:
  %t39 = getelementptr ptr, ptr %t25, i32 1
  %t40 = load ptr, ptr %t39
  %t41 = call ptr @malloc(i64 16)
  %t42 = inttoptr i64 0 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = getelementptr ptr, ptr %t41, i32 1
  store ptr %t40, ptr %t44
  br label %case.end.0.38
case.end.0.38:
  br label %case.join.36
case.arm.1.45:
  %t47 = getelementptr ptr, ptr %t25, i32 1
  %t48 = load ptr, ptr %t47
  %t49 = call ptr @malloc(i64 16)
  %t50 = inttoptr i64 1 to ptr
  %t51 = getelementptr ptr, ptr %t49, i32 0
  store ptr %t50, ptr %t51
  %t52 = getelementptr [3 x i8], ptr @.str.0, i64 0, i64 0
  %t53 = call ptr @__concat(ptr %t48, ptr %t52)
  %t54 = getelementptr ptr, ptr %t49, i32 1
  store ptr %t53, ptr %t54
  %t55 = getelementptr ptr, ptr %t49, i32 0
  %t56 = load ptr, ptr %t55
  %t57 = ptrtoint ptr %t56 to i64
  switch i64 %t57, label %case.default.58 [ i64 0, label %case.arm.0.60 i64 1, label %case.arm.1.68 ]
case.arm.0.60:
  %t62 = getelementptr ptr, ptr %t49, i32 1
  %t63 = load ptr, ptr %t62
  %t64 = call ptr @malloc(i64 16)
  %t65 = inttoptr i64 0 to ptr
  %t66 = getelementptr ptr, ptr %t64, i32 0
  store ptr %t65, ptr %t66
  %t67 = getelementptr ptr, ptr %t64, i32 1
  store ptr %t63, ptr %t67
  br label %case.end.0.61
case.end.0.61:
  br label %case.join.59
case.arm.1.68:
  %t70 = getelementptr ptr, ptr %t49, i32 1
  %t71 = load ptr, ptr %t70
  %t72 = call ptr @malloc(i64 16)
  %t73 = inttoptr i64 1 to ptr
  %t74 = getelementptr ptr, ptr %t72, i32 0
  store ptr %t73, ptr %t74
  %t75 = call ptr @malloc(i64 4)
  store i32 -2147483648, ptr %t75
  %t76 = call ptr @__showUInt32(ptr %t75)
  %t77 = call ptr @__concat(ptr %t71, ptr %t76)
  %t78 = getelementptr ptr, ptr %t72, i32 1
  store ptr %t77, ptr %t78
  %t79 = getelementptr ptr, ptr %t72, i32 0
  %t80 = load ptr, ptr %t79
  %t81 = ptrtoint ptr %t80 to i64
  switch i64 %t81, label %case.default.82 [ i64 0, label %case.arm.0.84 i64 1, label %case.arm.1.92 ]
case.arm.0.84:
  %t86 = getelementptr ptr, ptr %t72, i32 1
  %t87 = load ptr, ptr %t86
  %t88 = call ptr @malloc(i64 16)
  %t89 = inttoptr i64 0 to ptr
  %t90 = getelementptr ptr, ptr %t88, i32 0
  store ptr %t89, ptr %t90
  %t91 = getelementptr ptr, ptr %t88, i32 1
  store ptr %t87, ptr %t91
  br label %case.end.0.85
case.end.0.85:
  br label %case.join.83
case.arm.1.92:
  %t94 = getelementptr ptr, ptr %t72, i32 1
  %t95 = load ptr, ptr %t94
  %t96 = call ptr @malloc(i64 16)
  %t97 = inttoptr i64 1 to ptr
  %t98 = getelementptr ptr, ptr %t96, i32 0
  store ptr %t97, ptr %t98
  %t99 = getelementptr [3 x i8], ptr @.str.0, i64 0, i64 0
  %t100 = call ptr @__concat(ptr %t95, ptr %t99)
  %t101 = getelementptr ptr, ptr %t96, i32 1
  store ptr %t100, ptr %t101
  %t102 = getelementptr ptr, ptr %t96, i32 0
  %t103 = load ptr, ptr %t102
  %t104 = ptrtoint ptr %t103 to i64
  switch i64 %t104, label %case.default.105 [ i64 0, label %case.arm.0.107 i64 1, label %case.arm.1.115 ]
case.arm.0.107:
  %t109 = getelementptr ptr, ptr %t96, i32 1
  %t110 = load ptr, ptr %t109
  %t111 = call ptr @malloc(i64 16)
  %t112 = inttoptr i64 0 to ptr
  %t113 = getelementptr ptr, ptr %t111, i32 0
  store ptr %t112, ptr %t113
  %t114 = getelementptr ptr, ptr %t111, i32 1
  store ptr %t110, ptr %t114
  br label %case.end.0.108
case.end.0.108:
  br label %case.join.106
case.arm.1.115:
  %t117 = getelementptr ptr, ptr %t96, i32 1
  %t118 = load ptr, ptr %t117
  %t119 = call ptr @malloc(i64 16)
  %t120 = inttoptr i64 1 to ptr
  %t121 = getelementptr ptr, ptr %t119, i32 0
  store ptr %t120, ptr %t121
  %t122 = call ptr @malloc(i64 4)
  store i32 -294967296, ptr %t122
  %t123 = call ptr @__showUInt32(ptr %t122)
  %t124 = call ptr @__concat(ptr %t118, ptr %t123)
  %t125 = getelementptr ptr, ptr %t119, i32 1
  store ptr %t124, ptr %t125
  %t126 = getelementptr ptr, ptr %t119, i32 0
  %t127 = load ptr, ptr %t126
  %t128 = ptrtoint ptr %t127 to i64
  switch i64 %t128, label %case.default.129 [ i64 0, label %case.arm.0.131 i64 1, label %case.arm.1.139 ]
case.arm.0.131:
  %t133 = getelementptr ptr, ptr %t119, i32 1
  %t134 = load ptr, ptr %t133
  %t135 = call ptr @malloc(i64 16)
  %t136 = inttoptr i64 0 to ptr
  %t137 = getelementptr ptr, ptr %t135, i32 0
  store ptr %t136, ptr %t137
  %t138 = getelementptr ptr, ptr %t135, i32 1
  store ptr %t134, ptr %t138
  br label %case.end.0.132
case.end.0.132:
  br label %case.join.130
case.arm.1.139:
  %t141 = getelementptr ptr, ptr %t119, i32 1
  %t142 = load ptr, ptr %t141
  %t143 = call ptr @malloc(i64 16)
  %t144 = inttoptr i64 1 to ptr
  %t145 = getelementptr ptr, ptr %t143, i32 0
  store ptr %t144, ptr %t145
  %t146 = getelementptr [3 x i8], ptr @.str.0, i64 0, i64 0
  %t147 = call ptr @__concat(ptr %t142, ptr %t146)
  %t148 = getelementptr ptr, ptr %t143, i32 1
  store ptr %t147, ptr %t148
  %t149 = getelementptr ptr, ptr %t143, i32 0
  %t150 = load ptr, ptr %t149
  %t151 = ptrtoint ptr %t150 to i64
  switch i64 %t151, label %case.default.152 [ i64 0, label %case.arm.0.154 i64 1, label %case.arm.1.162 ]
case.arm.0.154:
  %t156 = getelementptr ptr, ptr %t143, i32 1
  %t157 = load ptr, ptr %t156
  %t158 = call ptr @malloc(i64 16)
  %t159 = inttoptr i64 0 to ptr
  %t160 = getelementptr ptr, ptr %t158, i32 0
  store ptr %t159, ptr %t160
  %t161 = getelementptr ptr, ptr %t158, i32 1
  store ptr %t157, ptr %t161
  br label %case.end.0.155
case.end.0.155:
  br label %case.join.153
case.arm.1.162:
  %t164 = getelementptr ptr, ptr %t143, i32 1
  %t165 = load ptr, ptr %t164
  %t166 = call ptr @malloc(i64 16)
  %t167 = inttoptr i64 1 to ptr
  %t168 = getelementptr ptr, ptr %t166, i32 0
  store ptr %t167, ptr %t168
  %t169 = call ptr @v_maxUInt32()
  %t170 = call ptr @__showUInt32(ptr %t169)
  %t171 = call ptr @__concat(ptr %t165, ptr %t170)
  %t172 = getelementptr ptr, ptr %t166, i32 1
  store ptr %t171, ptr %t172
  br label %case.end.1.163
case.end.1.163:
  br label %case.join.153
case.default.152:
  unreachable
case.join.153:
  %t173 = phi ptr [%t158, %case.end.0.155], [%t166, %case.end.1.163]
  br label %case.end.1.140
case.end.1.140:
  br label %case.join.130
case.default.129:
  unreachable
case.join.130:
  %t174 = phi ptr [%t135, %case.end.0.132], [%t173, %case.end.1.140]
  br label %case.end.1.116
case.end.1.116:
  br label %case.join.106
case.default.105:
  unreachable
case.join.106:
  %t175 = phi ptr [%t111, %case.end.0.108], [%t174, %case.end.1.116]
  br label %case.end.1.93
case.end.1.93:
  br label %case.join.83
case.default.82:
  unreachable
case.join.83:
  %t176 = phi ptr [%t88, %case.end.0.85], [%t175, %case.end.1.93]
  br label %case.end.1.69
case.end.1.69:
  br label %case.join.59
case.default.58:
  unreachable
case.join.59:
  %t177 = phi ptr [%t64, %case.end.0.61], [%t176, %case.end.1.69]
  br label %case.end.1.46
case.end.1.46:
  br label %case.join.36
case.default.35:
  unreachable
case.join.36:
  %t178 = phi ptr [%t41, %case.end.0.38], [%t177, %case.end.1.46]
  br label %case.end.1.22
case.end.1.22:
  br label %case.join.12
case.default.11:
  unreachable
case.join.12:
  %t179 = phi ptr [%t17, %case.end.0.14], [%t178, %case.end.1.22]
  %t180 = call ptr @v__let_1(ptr %t179)
  ret ptr %t180
}

define internal ptr @v__let_1(ptr %v_res) {
  %t0 = getelementptr ptr, ptr %v_res, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.11 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_res, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr [16 x i8], ptr @.str.1, i64 0, i64 0
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
