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

@.str.0 = private unnamed_addr constant [2 x i8] c"1\00"
@.str.1 = private unnamed_addr constant [2 x i8] c",\00"
@.str.2 = private unnamed_addr constant [2 x i8] c"2\00"
@.str.3 = private unnamed_addr constant [2 x i8] c"3\00"
@.str.4 = private unnamed_addr constant [2 x i8] c"4\00"
@.str.5 = private unnamed_addr constant [2 x i8] c"5\00"
@.str.6 = private unnamed_addr constant [2 x i8] c"6\00"
@.str.7 = private unnamed_addr constant [2 x i8] c"7\00"
@.str.8 = private unnamed_addr constant [2 x i8] c"8\00"
@.str.9 = private unnamed_addr constant [16 x i8] c"STRING_TOO_LONG\00"

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

define internal ptr @v_unwrap(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.51 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_r, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr ptr, ptr %t8, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %case.default.12 [ i64 0, label %case.arm.0.14 i64 1, label %case.arm.1.32 ]
case.arm.0.14:
  %t16 = getelementptr ptr, ptr %t8, i32 1
  %t17 = load ptr, ptr %t16
  %t18 = getelementptr ptr, ptr %t17, i32 0
  %t19 = load ptr, ptr %t18
  %t20 = ptrtoint ptr %t19 to i64
  switch i64 %t20, label %case.default.21 [ i64 0, label %case.arm.0.23 i64 1, label %case.arm.1.27 ]
case.arm.0.23:
  %t25 = getelementptr ptr, ptr %t17, i32 1
  %t26 = load ptr, ptr %t25
  br label %case.end.0.24
case.end.0.24:
  br label %case.join.22
case.arm.1.27:
  %t29 = getelementptr ptr, ptr %t17, i32 1
  %t30 = load ptr, ptr %t29
  br label %case.end.1.28
case.end.1.28:
  br label %case.join.22
case.default.21:
  unreachable
case.join.22:
  %t31 = phi ptr [%t26, %case.end.0.24], [%t30, %case.end.1.28]
  br label %case.end.0.15
case.end.0.15:
  br label %case.join.13
case.arm.1.32:
  %t34 = getelementptr ptr, ptr %t8, i32 1
  %t35 = load ptr, ptr %t34
  %t36 = getelementptr ptr, ptr %t35, i32 0
  %t37 = load ptr, ptr %t36
  %t38 = ptrtoint ptr %t37 to i64
  switch i64 %t38, label %case.default.39 [ i64 0, label %case.arm.0.41 i64 1, label %case.arm.1.45 ]
case.arm.0.41:
  %t43 = getelementptr ptr, ptr %t35, i32 1
  %t44 = load ptr, ptr %t43
  br label %case.end.0.42
case.end.0.42:
  br label %case.join.40
case.arm.1.45:
  %t47 = getelementptr ptr, ptr %t35, i32 1
  %t48 = load ptr, ptr %t47
  br label %case.end.1.46
case.end.1.46:
  br label %case.join.40
case.default.39:
  unreachable
case.join.40:
  %t49 = phi ptr [%t44, %case.end.0.42], [%t48, %case.end.1.46]
  br label %case.end.1.33
case.end.1.33:
  br label %case.join.13
case.default.12:
  unreachable
case.join.13:
  %t50 = phi ptr [%t31, %case.end.0.15], [%t49, %case.end.1.33]
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.51:
  %t53 = getelementptr ptr, ptr %v_r, i32 1
  %t54 = load ptr, ptr %t53
  %t55 = getelementptr ptr, ptr %t54, i32 0
  %t56 = load ptr, ptr %t55
  %t57 = ptrtoint ptr %t56 to i64
  switch i64 %t57, label %case.default.58 [ i64 0, label %case.arm.0.60 i64 1, label %case.arm.1.78 ]
case.arm.0.60:
  %t62 = getelementptr ptr, ptr %t54, i32 1
  %t63 = load ptr, ptr %t62
  %t64 = getelementptr ptr, ptr %t63, i32 0
  %t65 = load ptr, ptr %t64
  %t66 = ptrtoint ptr %t65 to i64
  switch i64 %t66, label %case.default.67 [ i64 0, label %case.arm.0.69 i64 1, label %case.arm.1.73 ]
case.arm.0.69:
  %t71 = getelementptr ptr, ptr %t63, i32 1
  %t72 = load ptr, ptr %t71
  br label %case.end.0.70
case.end.0.70:
  br label %case.join.68
case.arm.1.73:
  %t75 = getelementptr ptr, ptr %t63, i32 1
  %t76 = load ptr, ptr %t75
  br label %case.end.1.74
case.end.1.74:
  br label %case.join.68
case.default.67:
  unreachable
case.join.68:
  %t77 = phi ptr [%t72, %case.end.0.70], [%t76, %case.end.1.74]
  br label %case.end.0.61
case.end.0.61:
  br label %case.join.59
case.arm.1.78:
  %t80 = getelementptr ptr, ptr %t54, i32 1
  %t81 = load ptr, ptr %t80
  %t82 = getelementptr ptr, ptr %t81, i32 0
  %t83 = load ptr, ptr %t82
  %t84 = ptrtoint ptr %t83 to i64
  switch i64 %t84, label %case.default.85 [ i64 0, label %case.arm.0.87 i64 1, label %case.arm.1.91 ]
case.arm.0.87:
  %t89 = getelementptr ptr, ptr %t81, i32 1
  %t90 = load ptr, ptr %t89
  br label %case.end.0.88
case.end.0.88:
  br label %case.join.86
case.arm.1.91:
  %t93 = getelementptr ptr, ptr %t81, i32 1
  %t94 = load ptr, ptr %t93
  br label %case.end.1.92
case.end.1.92:
  br label %case.join.86
case.default.85:
  unreachable
case.join.86:
  %t95 = phi ptr [%t90, %case.end.0.88], [%t94, %case.end.1.92]
  br label %case.end.1.79
case.end.1.79:
  br label %case.join.59
case.default.58:
  unreachable
case.join.59:
  %t96 = phi ptr [%t77, %case.end.0.61], [%t95, %case.end.1.79]
  br label %case.end.1.52
case.end.1.52:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t97 = phi ptr [%t50, %case.end.0.6], [%t96, %case.end.1.52]
  ret ptr %t97
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @malloc(i64 16)
  %t4 = inttoptr i64 0 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = call ptr @malloc(i64 16)
  %t7 = inttoptr i64 0 to ptr
  %t8 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t7, ptr %t8
  %t9 = call ptr @malloc(i64 16)
  %t10 = inttoptr i64 0 to ptr
  %t11 = getelementptr ptr, ptr %t9, i32 0
  store ptr %t10, ptr %t11
  %t12 = getelementptr [2 x i8], ptr @.str.0, i64 0, i64 0
  %t13 = getelementptr ptr, ptr %t9, i32 1
  store ptr %t12, ptr %t13
  %t14 = getelementptr ptr, ptr %t6, i32 1
  store ptr %t9, ptr %t14
  %t15 = getelementptr ptr, ptr %t3, i32 1
  store ptr %t6, ptr %t15
  %t16 = call ptr @v_unwrap(ptr %t3)
  %t17 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  %t18 = call ptr @__concat(ptr %t16, ptr %t17)
  %t19 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t18, ptr %t19
  %t20 = getelementptr ptr, ptr %t0, i32 0
  %t21 = load ptr, ptr %t20
  %t22 = ptrtoint ptr %t21 to i64
  switch i64 %t22, label %case.default.23 [ i64 0, label %case.arm.0.25 i64 1, label %case.arm.1.33 ]
case.arm.0.25:
  %t27 = getelementptr ptr, ptr %t0, i32 1
  %t28 = load ptr, ptr %t27
  %t29 = call ptr @malloc(i64 16)
  %t30 = inttoptr i64 0 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = getelementptr ptr, ptr %t29, i32 1
  store ptr %t28, ptr %t32
  br label %case.end.0.26
case.end.0.26:
  br label %case.join.24
case.arm.1.33:
  %t35 = getelementptr ptr, ptr %t0, i32 1
  %t36 = load ptr, ptr %t35
  %t37 = call ptr @malloc(i64 16)
  %t38 = inttoptr i64 1 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = call ptr @malloc(i64 16)
  %t41 = inttoptr i64 0 to ptr
  %t42 = getelementptr ptr, ptr %t40, i32 0
  store ptr %t41, ptr %t42
  %t43 = call ptr @malloc(i64 16)
  %t44 = inttoptr i64 0 to ptr
  %t45 = getelementptr ptr, ptr %t43, i32 0
  store ptr %t44, ptr %t45
  %t46 = call ptr @malloc(i64 16)
  %t47 = inttoptr i64 1 to ptr
  %t48 = getelementptr ptr, ptr %t46, i32 0
  store ptr %t47, ptr %t48
  %t49 = getelementptr [2 x i8], ptr @.str.2, i64 0, i64 0
  %t50 = getelementptr ptr, ptr %t46, i32 1
  store ptr %t49, ptr %t50
  %t51 = getelementptr ptr, ptr %t43, i32 1
  store ptr %t46, ptr %t51
  %t52 = getelementptr ptr, ptr %t40, i32 1
  store ptr %t43, ptr %t52
  %t53 = call ptr @v_unwrap(ptr %t40)
  %t54 = call ptr @__concat(ptr %t36, ptr %t53)
  %t55 = getelementptr ptr, ptr %t37, i32 1
  store ptr %t54, ptr %t55
  %t56 = getelementptr ptr, ptr %t37, i32 0
  %t57 = load ptr, ptr %t56
  %t58 = ptrtoint ptr %t57 to i64
  switch i64 %t58, label %case.default.59 [ i64 0, label %case.arm.0.61 i64 1, label %case.arm.1.69 ]
case.arm.0.61:
  %t63 = getelementptr ptr, ptr %t37, i32 1
  %t64 = load ptr, ptr %t63
  %t65 = call ptr @malloc(i64 16)
  %t66 = inttoptr i64 0 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  %t68 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t64, ptr %t68
  br label %case.end.0.62
case.end.0.62:
  br label %case.join.60
case.arm.1.69:
  %t71 = getelementptr ptr, ptr %t37, i32 1
  %t72 = load ptr, ptr %t71
  %t73 = call ptr @malloc(i64 16)
  %t74 = inttoptr i64 1 to ptr
  %t75 = getelementptr ptr, ptr %t73, i32 0
  store ptr %t74, ptr %t75
  %t76 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  %t77 = call ptr @__concat(ptr %t72, ptr %t76)
  %t78 = getelementptr ptr, ptr %t73, i32 1
  store ptr %t77, ptr %t78
  %t79 = getelementptr ptr, ptr %t73, i32 0
  %t80 = load ptr, ptr %t79
  %t81 = ptrtoint ptr %t80 to i64
  switch i64 %t81, label %case.default.82 [ i64 0, label %case.arm.0.84 i64 1, label %case.arm.1.92 ]
case.arm.0.84:
  %t86 = getelementptr ptr, ptr %t73, i32 1
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
  %t94 = getelementptr ptr, ptr %t73, i32 1
  %t95 = load ptr, ptr %t94
  %t96 = call ptr @malloc(i64 16)
  %t97 = inttoptr i64 1 to ptr
  %t98 = getelementptr ptr, ptr %t96, i32 0
  store ptr %t97, ptr %t98
  %t99 = call ptr @malloc(i64 16)
  %t100 = inttoptr i64 0 to ptr
  %t101 = getelementptr ptr, ptr %t99, i32 0
  store ptr %t100, ptr %t101
  %t102 = call ptr @malloc(i64 16)
  %t103 = inttoptr i64 1 to ptr
  %t104 = getelementptr ptr, ptr %t102, i32 0
  store ptr %t103, ptr %t104
  %t105 = call ptr @malloc(i64 16)
  %t106 = inttoptr i64 0 to ptr
  %t107 = getelementptr ptr, ptr %t105, i32 0
  store ptr %t106, ptr %t107
  %t108 = getelementptr [2 x i8], ptr @.str.3, i64 0, i64 0
  %t109 = getelementptr ptr, ptr %t105, i32 1
  store ptr %t108, ptr %t109
  %t110 = getelementptr ptr, ptr %t102, i32 1
  store ptr %t105, ptr %t110
  %t111 = getelementptr ptr, ptr %t99, i32 1
  store ptr %t102, ptr %t111
  %t112 = call ptr @v_unwrap(ptr %t99)
  %t113 = call ptr @__concat(ptr %t95, ptr %t112)
  %t114 = getelementptr ptr, ptr %t96, i32 1
  store ptr %t113, ptr %t114
  %t115 = getelementptr ptr, ptr %t96, i32 0
  %t116 = load ptr, ptr %t115
  %t117 = ptrtoint ptr %t116 to i64
  switch i64 %t117, label %case.default.118 [ i64 0, label %case.arm.0.120 i64 1, label %case.arm.1.128 ]
case.arm.0.120:
  %t122 = getelementptr ptr, ptr %t96, i32 1
  %t123 = load ptr, ptr %t122
  %t124 = call ptr @malloc(i64 16)
  %t125 = inttoptr i64 0 to ptr
  %t126 = getelementptr ptr, ptr %t124, i32 0
  store ptr %t125, ptr %t126
  %t127 = getelementptr ptr, ptr %t124, i32 1
  store ptr %t123, ptr %t127
  br label %case.end.0.121
case.end.0.121:
  br label %case.join.119
case.arm.1.128:
  %t130 = getelementptr ptr, ptr %t96, i32 1
  %t131 = load ptr, ptr %t130
  %t132 = call ptr @malloc(i64 16)
  %t133 = inttoptr i64 1 to ptr
  %t134 = getelementptr ptr, ptr %t132, i32 0
  store ptr %t133, ptr %t134
  %t135 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  %t136 = call ptr @__concat(ptr %t131, ptr %t135)
  %t137 = getelementptr ptr, ptr %t132, i32 1
  store ptr %t136, ptr %t137
  %t138 = getelementptr ptr, ptr %t132, i32 0
  %t139 = load ptr, ptr %t138
  %t140 = ptrtoint ptr %t139 to i64
  switch i64 %t140, label %case.default.141 [ i64 0, label %case.arm.0.143 i64 1, label %case.arm.1.151 ]
case.arm.0.143:
  %t145 = getelementptr ptr, ptr %t132, i32 1
  %t146 = load ptr, ptr %t145
  %t147 = call ptr @malloc(i64 16)
  %t148 = inttoptr i64 0 to ptr
  %t149 = getelementptr ptr, ptr %t147, i32 0
  store ptr %t148, ptr %t149
  %t150 = getelementptr ptr, ptr %t147, i32 1
  store ptr %t146, ptr %t150
  br label %case.end.0.144
case.end.0.144:
  br label %case.join.142
case.arm.1.151:
  %t153 = getelementptr ptr, ptr %t132, i32 1
  %t154 = load ptr, ptr %t153
  %t155 = call ptr @malloc(i64 16)
  %t156 = inttoptr i64 1 to ptr
  %t157 = getelementptr ptr, ptr %t155, i32 0
  store ptr %t156, ptr %t157
  %t158 = call ptr @malloc(i64 16)
  %t159 = inttoptr i64 0 to ptr
  %t160 = getelementptr ptr, ptr %t158, i32 0
  store ptr %t159, ptr %t160
  %t161 = call ptr @malloc(i64 16)
  %t162 = inttoptr i64 1 to ptr
  %t163 = getelementptr ptr, ptr %t161, i32 0
  store ptr %t162, ptr %t163
  %t164 = call ptr @malloc(i64 16)
  %t165 = inttoptr i64 1 to ptr
  %t166 = getelementptr ptr, ptr %t164, i32 0
  store ptr %t165, ptr %t166
  %t167 = getelementptr [2 x i8], ptr @.str.4, i64 0, i64 0
  %t168 = getelementptr ptr, ptr %t164, i32 1
  store ptr %t167, ptr %t168
  %t169 = getelementptr ptr, ptr %t161, i32 1
  store ptr %t164, ptr %t169
  %t170 = getelementptr ptr, ptr %t158, i32 1
  store ptr %t161, ptr %t170
  %t171 = call ptr @v_unwrap(ptr %t158)
  %t172 = call ptr @__concat(ptr %t154, ptr %t171)
  %t173 = getelementptr ptr, ptr %t155, i32 1
  store ptr %t172, ptr %t173
  %t174 = getelementptr ptr, ptr %t155, i32 0
  %t175 = load ptr, ptr %t174
  %t176 = ptrtoint ptr %t175 to i64
  switch i64 %t176, label %case.default.177 [ i64 0, label %case.arm.0.179 i64 1, label %case.arm.1.187 ]
case.arm.0.179:
  %t181 = getelementptr ptr, ptr %t155, i32 1
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
  %t189 = getelementptr ptr, ptr %t155, i32 1
  %t190 = load ptr, ptr %t189
  %t191 = call ptr @malloc(i64 16)
  %t192 = inttoptr i64 1 to ptr
  %t193 = getelementptr ptr, ptr %t191, i32 0
  store ptr %t192, ptr %t193
  %t194 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  %t195 = call ptr @__concat(ptr %t190, ptr %t194)
  %t196 = getelementptr ptr, ptr %t191, i32 1
  store ptr %t195, ptr %t196
  %t197 = getelementptr ptr, ptr %t191, i32 0
  %t198 = load ptr, ptr %t197
  %t199 = ptrtoint ptr %t198 to i64
  switch i64 %t199, label %case.default.200 [ i64 0, label %case.arm.0.202 i64 1, label %case.arm.1.210 ]
case.arm.0.202:
  %t204 = getelementptr ptr, ptr %t191, i32 1
  %t205 = load ptr, ptr %t204
  %t206 = call ptr @malloc(i64 16)
  %t207 = inttoptr i64 0 to ptr
  %t208 = getelementptr ptr, ptr %t206, i32 0
  store ptr %t207, ptr %t208
  %t209 = getelementptr ptr, ptr %t206, i32 1
  store ptr %t205, ptr %t209
  br label %case.end.0.203
case.end.0.203:
  br label %case.join.201
case.arm.1.210:
  %t212 = getelementptr ptr, ptr %t191, i32 1
  %t213 = load ptr, ptr %t212
  %t214 = call ptr @malloc(i64 16)
  %t215 = inttoptr i64 1 to ptr
  %t216 = getelementptr ptr, ptr %t214, i32 0
  store ptr %t215, ptr %t216
  %t217 = call ptr @malloc(i64 16)
  %t218 = inttoptr i64 1 to ptr
  %t219 = getelementptr ptr, ptr %t217, i32 0
  store ptr %t218, ptr %t219
  %t220 = call ptr @malloc(i64 16)
  %t221 = inttoptr i64 0 to ptr
  %t222 = getelementptr ptr, ptr %t220, i32 0
  store ptr %t221, ptr %t222
  %t223 = call ptr @malloc(i64 16)
  %t224 = inttoptr i64 0 to ptr
  %t225 = getelementptr ptr, ptr %t223, i32 0
  store ptr %t224, ptr %t225
  %t226 = getelementptr [2 x i8], ptr @.str.5, i64 0, i64 0
  %t227 = getelementptr ptr, ptr %t223, i32 1
  store ptr %t226, ptr %t227
  %t228 = getelementptr ptr, ptr %t220, i32 1
  store ptr %t223, ptr %t228
  %t229 = getelementptr ptr, ptr %t217, i32 1
  store ptr %t220, ptr %t229
  %t230 = call ptr @v_unwrap(ptr %t217)
  %t231 = call ptr @__concat(ptr %t213, ptr %t230)
  %t232 = getelementptr ptr, ptr %t214, i32 1
  store ptr %t231, ptr %t232
  %t233 = getelementptr ptr, ptr %t214, i32 0
  %t234 = load ptr, ptr %t233
  %t235 = ptrtoint ptr %t234 to i64
  switch i64 %t235, label %case.default.236 [ i64 0, label %case.arm.0.238 i64 1, label %case.arm.1.246 ]
case.arm.0.238:
  %t240 = getelementptr ptr, ptr %t214, i32 1
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
  %t248 = getelementptr ptr, ptr %t214, i32 1
  %t249 = load ptr, ptr %t248
  %t250 = call ptr @malloc(i64 16)
  %t251 = inttoptr i64 1 to ptr
  %t252 = getelementptr ptr, ptr %t250, i32 0
  store ptr %t251, ptr %t252
  %t253 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
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
  %t276 = call ptr @malloc(i64 16)
  %t277 = inttoptr i64 1 to ptr
  %t278 = getelementptr ptr, ptr %t276, i32 0
  store ptr %t277, ptr %t278
  %t279 = call ptr @malloc(i64 16)
  %t280 = inttoptr i64 0 to ptr
  %t281 = getelementptr ptr, ptr %t279, i32 0
  store ptr %t280, ptr %t281
  %t282 = call ptr @malloc(i64 16)
  %t283 = inttoptr i64 1 to ptr
  %t284 = getelementptr ptr, ptr %t282, i32 0
  store ptr %t283, ptr %t284
  %t285 = getelementptr [2 x i8], ptr @.str.6, i64 0, i64 0
  %t286 = getelementptr ptr, ptr %t282, i32 1
  store ptr %t285, ptr %t286
  %t287 = getelementptr ptr, ptr %t279, i32 1
  store ptr %t282, ptr %t287
  %t288 = getelementptr ptr, ptr %t276, i32 1
  store ptr %t279, ptr %t288
  %t289 = call ptr @v_unwrap(ptr %t276)
  %t290 = call ptr @__concat(ptr %t272, ptr %t289)
  %t291 = getelementptr ptr, ptr %t273, i32 1
  store ptr %t290, ptr %t291
  %t292 = getelementptr ptr, ptr %t273, i32 0
  %t293 = load ptr, ptr %t292
  %t294 = ptrtoint ptr %t293 to i64
  switch i64 %t294, label %case.default.295 [ i64 0, label %case.arm.0.297 i64 1, label %case.arm.1.305 ]
case.arm.0.297:
  %t299 = getelementptr ptr, ptr %t273, i32 1
  %t300 = load ptr, ptr %t299
  %t301 = call ptr @malloc(i64 16)
  %t302 = inttoptr i64 0 to ptr
  %t303 = getelementptr ptr, ptr %t301, i32 0
  store ptr %t302, ptr %t303
  %t304 = getelementptr ptr, ptr %t301, i32 1
  store ptr %t300, ptr %t304
  br label %case.end.0.298
case.end.0.298:
  br label %case.join.296
case.arm.1.305:
  %t307 = getelementptr ptr, ptr %t273, i32 1
  %t308 = load ptr, ptr %t307
  %t309 = call ptr @malloc(i64 16)
  %t310 = inttoptr i64 1 to ptr
  %t311 = getelementptr ptr, ptr %t309, i32 0
  store ptr %t310, ptr %t311
  %t312 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  %t313 = call ptr @__concat(ptr %t308, ptr %t312)
  %t314 = getelementptr ptr, ptr %t309, i32 1
  store ptr %t313, ptr %t314
  %t315 = getelementptr ptr, ptr %t309, i32 0
  %t316 = load ptr, ptr %t315
  %t317 = ptrtoint ptr %t316 to i64
  switch i64 %t317, label %case.default.318 [ i64 0, label %case.arm.0.320 i64 1, label %case.arm.1.328 ]
case.arm.0.320:
  %t322 = getelementptr ptr, ptr %t309, i32 1
  %t323 = load ptr, ptr %t322
  %t324 = call ptr @malloc(i64 16)
  %t325 = inttoptr i64 0 to ptr
  %t326 = getelementptr ptr, ptr %t324, i32 0
  store ptr %t325, ptr %t326
  %t327 = getelementptr ptr, ptr %t324, i32 1
  store ptr %t323, ptr %t327
  br label %case.end.0.321
case.end.0.321:
  br label %case.join.319
case.arm.1.328:
  %t330 = getelementptr ptr, ptr %t309, i32 1
  %t331 = load ptr, ptr %t330
  %t332 = call ptr @malloc(i64 16)
  %t333 = inttoptr i64 1 to ptr
  %t334 = getelementptr ptr, ptr %t332, i32 0
  store ptr %t333, ptr %t334
  %t335 = call ptr @malloc(i64 16)
  %t336 = inttoptr i64 1 to ptr
  %t337 = getelementptr ptr, ptr %t335, i32 0
  store ptr %t336, ptr %t337
  %t338 = call ptr @malloc(i64 16)
  %t339 = inttoptr i64 1 to ptr
  %t340 = getelementptr ptr, ptr %t338, i32 0
  store ptr %t339, ptr %t340
  %t341 = call ptr @malloc(i64 16)
  %t342 = inttoptr i64 0 to ptr
  %t343 = getelementptr ptr, ptr %t341, i32 0
  store ptr %t342, ptr %t343
  %t344 = getelementptr [2 x i8], ptr @.str.7, i64 0, i64 0
  %t345 = getelementptr ptr, ptr %t341, i32 1
  store ptr %t344, ptr %t345
  %t346 = getelementptr ptr, ptr %t338, i32 1
  store ptr %t341, ptr %t346
  %t347 = getelementptr ptr, ptr %t335, i32 1
  store ptr %t338, ptr %t347
  %t348 = call ptr @v_unwrap(ptr %t335)
  %t349 = call ptr @__concat(ptr %t331, ptr %t348)
  %t350 = getelementptr ptr, ptr %t332, i32 1
  store ptr %t349, ptr %t350
  %t351 = getelementptr ptr, ptr %t332, i32 0
  %t352 = load ptr, ptr %t351
  %t353 = ptrtoint ptr %t352 to i64
  switch i64 %t353, label %case.default.354 [ i64 0, label %case.arm.0.356 i64 1, label %case.arm.1.364 ]
case.arm.0.356:
  %t358 = getelementptr ptr, ptr %t332, i32 1
  %t359 = load ptr, ptr %t358
  %t360 = call ptr @malloc(i64 16)
  %t361 = inttoptr i64 0 to ptr
  %t362 = getelementptr ptr, ptr %t360, i32 0
  store ptr %t361, ptr %t362
  %t363 = getelementptr ptr, ptr %t360, i32 1
  store ptr %t359, ptr %t363
  br label %case.end.0.357
case.end.0.357:
  br label %case.join.355
case.arm.1.364:
  %t366 = getelementptr ptr, ptr %t332, i32 1
  %t367 = load ptr, ptr %t366
  %t368 = call ptr @malloc(i64 16)
  %t369 = inttoptr i64 1 to ptr
  %t370 = getelementptr ptr, ptr %t368, i32 0
  store ptr %t369, ptr %t370
  %t371 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  %t372 = call ptr @__concat(ptr %t367, ptr %t371)
  %t373 = getelementptr ptr, ptr %t368, i32 1
  store ptr %t372, ptr %t373
  %t374 = getelementptr ptr, ptr %t368, i32 0
  %t375 = load ptr, ptr %t374
  %t376 = ptrtoint ptr %t375 to i64
  switch i64 %t376, label %case.default.377 [ i64 0, label %case.arm.0.379 i64 1, label %case.arm.1.387 ]
case.arm.0.379:
  %t381 = getelementptr ptr, ptr %t368, i32 1
  %t382 = load ptr, ptr %t381
  %t383 = call ptr @malloc(i64 16)
  %t384 = inttoptr i64 0 to ptr
  %t385 = getelementptr ptr, ptr %t383, i32 0
  store ptr %t384, ptr %t385
  %t386 = getelementptr ptr, ptr %t383, i32 1
  store ptr %t382, ptr %t386
  br label %case.end.0.380
case.end.0.380:
  br label %case.join.378
case.arm.1.387:
  %t389 = getelementptr ptr, ptr %t368, i32 1
  %t390 = load ptr, ptr %t389
  %t391 = call ptr @malloc(i64 16)
  %t392 = inttoptr i64 1 to ptr
  %t393 = getelementptr ptr, ptr %t391, i32 0
  store ptr %t392, ptr %t393
  %t394 = call ptr @malloc(i64 16)
  %t395 = inttoptr i64 1 to ptr
  %t396 = getelementptr ptr, ptr %t394, i32 0
  store ptr %t395, ptr %t396
  %t397 = call ptr @malloc(i64 16)
  %t398 = inttoptr i64 1 to ptr
  %t399 = getelementptr ptr, ptr %t397, i32 0
  store ptr %t398, ptr %t399
  %t400 = call ptr @malloc(i64 16)
  %t401 = inttoptr i64 1 to ptr
  %t402 = getelementptr ptr, ptr %t400, i32 0
  store ptr %t401, ptr %t402
  %t403 = getelementptr [2 x i8], ptr @.str.8, i64 0, i64 0
  %t404 = getelementptr ptr, ptr %t400, i32 1
  store ptr %t403, ptr %t404
  %t405 = getelementptr ptr, ptr %t397, i32 1
  store ptr %t400, ptr %t405
  %t406 = getelementptr ptr, ptr %t394, i32 1
  store ptr %t397, ptr %t406
  %t407 = call ptr @v_unwrap(ptr %t394)
  %t408 = call ptr @__concat(ptr %t390, ptr %t407)
  %t409 = getelementptr ptr, ptr %t391, i32 1
  store ptr %t408, ptr %t409
  br label %case.end.1.388
case.end.1.388:
  br label %case.join.378
case.default.377:
  unreachable
case.join.378:
  %t410 = phi ptr [%t383, %case.end.0.380], [%t391, %case.end.1.388]
  br label %case.end.1.365
case.end.1.365:
  br label %case.join.355
case.default.354:
  unreachable
case.join.355:
  %t411 = phi ptr [%t360, %case.end.0.357], [%t410, %case.end.1.365]
  br label %case.end.1.329
case.end.1.329:
  br label %case.join.319
case.default.318:
  unreachable
case.join.319:
  %t412 = phi ptr [%t324, %case.end.0.321], [%t411, %case.end.1.329]
  br label %case.end.1.306
case.end.1.306:
  br label %case.join.296
case.default.295:
  unreachable
case.join.296:
  %t413 = phi ptr [%t301, %case.end.0.298], [%t412, %case.end.1.306]
  br label %case.end.1.270
case.end.1.270:
  br label %case.join.260
case.default.259:
  unreachable
case.join.260:
  %t414 = phi ptr [%t265, %case.end.0.262], [%t413, %case.end.1.270]
  br label %case.end.1.247
case.end.1.247:
  br label %case.join.237
case.default.236:
  unreachable
case.join.237:
  %t415 = phi ptr [%t242, %case.end.0.239], [%t414, %case.end.1.247]
  br label %case.end.1.211
case.end.1.211:
  br label %case.join.201
case.default.200:
  unreachable
case.join.201:
  %t416 = phi ptr [%t206, %case.end.0.203], [%t415, %case.end.1.211]
  br label %case.end.1.188
case.end.1.188:
  br label %case.join.178
case.default.177:
  unreachable
case.join.178:
  %t417 = phi ptr [%t183, %case.end.0.180], [%t416, %case.end.1.188]
  br label %case.end.1.152
case.end.1.152:
  br label %case.join.142
case.default.141:
  unreachable
case.join.142:
  %t418 = phi ptr [%t147, %case.end.0.144], [%t417, %case.end.1.152]
  br label %case.end.1.129
case.end.1.129:
  br label %case.join.119
case.default.118:
  unreachable
case.join.119:
  %t419 = phi ptr [%t124, %case.end.0.121], [%t418, %case.end.1.129]
  br label %case.end.1.93
case.end.1.93:
  br label %case.join.83
case.default.82:
  unreachable
case.join.83:
  %t420 = phi ptr [%t88, %case.end.0.85], [%t419, %case.end.1.93]
  br label %case.end.1.70
case.end.1.70:
  br label %case.join.60
case.default.59:
  unreachable
case.join.60:
  %t421 = phi ptr [%t65, %case.end.0.62], [%t420, %case.end.1.70]
  br label %case.end.1.34
case.end.1.34:
  br label %case.join.24
case.default.23:
  unreachable
case.join.24:
  %t422 = phi ptr [%t29, %case.end.0.26], [%t421, %case.end.1.34]
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
  %t12 = getelementptr [16 x i8], ptr @.str.9, i64 0, i64 0
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
