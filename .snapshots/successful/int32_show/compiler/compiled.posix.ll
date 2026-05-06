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

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_minInt32()
  %t4 = call ptr @__showInt32(ptr %t3)
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
  store i32 -42, ptr %t28
  %t29 = call ptr @__showInt32(ptr %t28)
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
  store i32 0, ptr %t75
  %t76 = call ptr @__showInt32(ptr %t75)
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
  store i32 7, ptr %t122
  %t123 = call ptr @__showInt32(ptr %t122)
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
  %t169 = call ptr @malloc(i64 4)
  store i32 1234567, ptr %t169
  %t170 = call ptr @__showInt32(ptr %t169)
  %t171 = call ptr @__concat(ptr %t165, ptr %t170)
  %t172 = getelementptr ptr, ptr %t166, i32 1
  store ptr %t171, ptr %t172
  %t173 = getelementptr ptr, ptr %t166, i32 0
  %t174 = load ptr, ptr %t173
  %t175 = ptrtoint ptr %t174 to i64
  switch i64 %t175, label %case.default.176 [ i64 0, label %case.arm.0.178 i64 1, label %case.arm.1.186 ]
case.arm.0.178:
  %t180 = getelementptr ptr, ptr %t166, i32 1
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
  %t188 = getelementptr ptr, ptr %t166, i32 1
  %t189 = load ptr, ptr %t188
  %t190 = call ptr @malloc(i64 16)
  %t191 = inttoptr i64 1 to ptr
  %t192 = getelementptr ptr, ptr %t190, i32 0
  store ptr %t191, ptr %t192
  %t193 = getelementptr [3 x i8], ptr @.str.0, i64 0, i64 0
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
  %t216 = call ptr @v_maxInt32()
  %t217 = call ptr @__showInt32(ptr %t216)
  %t218 = call ptr @__concat(ptr %t212, ptr %t217)
  %t219 = getelementptr ptr, ptr %t213, i32 1
  store ptr %t218, ptr %t219
  br label %case.end.1.210
case.end.1.210:
  br label %case.join.200
case.default.199:
  unreachable
case.join.200:
  %t220 = phi ptr [%t205, %case.end.0.202], [%t213, %case.end.1.210]
  br label %case.end.1.187
case.end.1.187:
  br label %case.join.177
case.default.176:
  unreachable
case.join.177:
  %t221 = phi ptr [%t182, %case.end.0.179], [%t220, %case.end.1.187]
  br label %case.end.1.163
case.end.1.163:
  br label %case.join.153
case.default.152:
  unreachable
case.join.153:
  %t222 = phi ptr [%t158, %case.end.0.155], [%t221, %case.end.1.163]
  br label %case.end.1.140
case.end.1.140:
  br label %case.join.130
case.default.129:
  unreachable
case.join.130:
  %t223 = phi ptr [%t135, %case.end.0.132], [%t222, %case.end.1.140]
  br label %case.end.1.116
case.end.1.116:
  br label %case.join.106
case.default.105:
  unreachable
case.join.106:
  %t224 = phi ptr [%t111, %case.end.0.108], [%t223, %case.end.1.116]
  br label %case.end.1.93
case.end.1.93:
  br label %case.join.83
case.default.82:
  unreachable
case.join.83:
  %t225 = phi ptr [%t88, %case.end.0.85], [%t224, %case.end.1.93]
  br label %case.end.1.69
case.end.1.69:
  br label %case.join.59
case.default.58:
  unreachable
case.join.59:
  %t226 = phi ptr [%t64, %case.end.0.61], [%t225, %case.end.1.69]
  br label %case.end.1.46
case.end.1.46:
  br label %case.join.36
case.default.35:
  unreachable
case.join.36:
  %t227 = phi ptr [%t41, %case.end.0.38], [%t226, %case.end.1.46]
  br label %case.end.1.22
case.end.1.22:
  br label %case.join.12
case.default.11:
  unreachable
case.join.12:
  %t228 = phi ptr [%t17, %case.end.0.14], [%t227, %case.end.1.22]
  %t229 = call ptr @v__let_2(ptr %t228)
  ret ptr %t229
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
  %t12 = getelementptr [16 x i8], ptr @.str.1, i64 0, i64 0
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
