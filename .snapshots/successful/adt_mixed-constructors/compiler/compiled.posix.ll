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

@.str.0 = private unnamed_addr constant [6 x i8] c"word:\00"
@.str.1 = private unnamed_addr constant [5 x i8] c"num:\00"
@.str.2 = private unnamed_addr constant [2 x i8] c",\00"
@.str.3 = private unnamed_addr constant [6 x i8] c"<eof>\00"
@.str.4 = private unnamed_addr constant [6 x i8] c"hello\00"
@.str.5 = private unnamed_addr constant [3 x i8] c"42\00"
@.str.6 = private unnamed_addr constant [2 x i8] c" \00"
@.str.7 = private unnamed_addr constant [16 x i8] c"STRING_TOO_LONG\00"

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

define internal ptr @v_showToken(ptr %v_token) {
  %t0 = getelementptr ptr, ptr %v_token, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.15 i64 2, label %case.arm.2.25 i64 3, label %case.arm.3.32 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_token, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = call ptr @malloc(i64 16)
  %t10 = inttoptr i64 1 to ptr
  %t11 = getelementptr ptr, ptr %t9, i32 0
  store ptr %t10, ptr %t11
  %t12 = getelementptr [6 x i8], ptr @.str.0, i64 0, i64 0
  %t13 = call ptr @__concat(ptr %t12, ptr %t8)
  %t14 = getelementptr ptr, ptr %t9, i32 1
  store ptr %t13, ptr %t14
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.15:
  %t17 = getelementptr ptr, ptr %v_token, i32 1
  %t18 = load ptr, ptr %t17
  %t19 = call ptr @malloc(i64 16)
  %t20 = inttoptr i64 1 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr [5 x i8], ptr @.str.1, i64 0, i64 0
  %t23 = call ptr @__concat(ptr %t22, ptr %t18)
  %t24 = getelementptr ptr, ptr %t19, i32 1
  store ptr %t23, ptr %t24
  br label %case.end.1.16
case.end.1.16:
  br label %case.join.4
case.arm.2.25:
  %t27 = call ptr @malloc(i64 16)
  %t28 = inttoptr i64 1 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  %t30 = getelementptr [2 x i8], ptr @.str.2, i64 0, i64 0
  %t31 = getelementptr ptr, ptr %t27, i32 1
  store ptr %t30, ptr %t31
  br label %case.end.2.26
case.end.2.26:
  br label %case.join.4
case.arm.3.32:
  %t34 = call ptr @malloc(i64 16)
  %t35 = inttoptr i64 1 to ptr
  %t36 = getelementptr ptr, ptr %t34, i32 0
  store ptr %t35, ptr %t36
  %t37 = getelementptr [6 x i8], ptr @.str.3, i64 0, i64 0
  %t38 = getelementptr ptr, ptr %t34, i32 1
  store ptr %t37, ptr %t38
  br label %case.end.3.33
case.end.3.33:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t39 = phi ptr [%t9, %case.end.0.6], [%t19, %case.end.1.16], [%t27, %case.end.2.26], [%t34, %case.end.3.33]
  ret ptr %t39
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 0 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr [6 x i8], ptr @.str.4, i64 0, i64 0
  %t4 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t4
  %t5 = call ptr @v_showToken(ptr %t0)
  %t6 = getelementptr ptr, ptr %t5, i32 0
  %t7 = load ptr, ptr %t6
  %t8 = ptrtoint ptr %t7 to i64
  switch i64 %t8, label %case.default.9 [ i64 0, label %case.arm.0.11 i64 1, label %case.arm.1.19 ]
case.arm.0.11:
  %t13 = getelementptr ptr, ptr %t5, i32 1
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
  %t21 = getelementptr ptr, ptr %t5, i32 1
  %t22 = load ptr, ptr %t21
  %t23 = call ptr @malloc(i64 8)
  %t24 = inttoptr i64 2 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  %t26 = call ptr @v_showToken(ptr %t23)
  %t27 = getelementptr ptr, ptr %t26, i32 0
  %t28 = load ptr, ptr %t27
  %t29 = ptrtoint ptr %t28 to i64
  switch i64 %t29, label %case.default.30 [ i64 0, label %case.arm.0.32 i64 1, label %case.arm.1.40 ]
case.arm.0.32:
  %t34 = getelementptr ptr, ptr %t26, i32 1
  %t35 = load ptr, ptr %t34
  %t36 = call ptr @malloc(i64 16)
  %t37 = inttoptr i64 0 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t35, ptr %t39
  br label %case.end.0.33
case.end.0.33:
  br label %case.join.31
case.arm.1.40:
  %t42 = getelementptr ptr, ptr %t26, i32 1
  %t43 = load ptr, ptr %t42
  %t44 = call ptr @malloc(i64 16)
  %t45 = inttoptr i64 1 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  %t47 = getelementptr [3 x i8], ptr @.str.5, i64 0, i64 0
  %t48 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t47, ptr %t48
  %t49 = call ptr @v_showToken(ptr %t44)
  %t50 = getelementptr ptr, ptr %t49, i32 0
  %t51 = load ptr, ptr %t50
  %t52 = ptrtoint ptr %t51 to i64
  switch i64 %t52, label %case.default.53 [ i64 0, label %case.arm.0.55 i64 1, label %case.arm.1.63 ]
case.arm.0.55:
  %t57 = getelementptr ptr, ptr %t49, i32 1
  %t58 = load ptr, ptr %t57
  %t59 = call ptr @malloc(i64 16)
  %t60 = inttoptr i64 0 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  %t62 = getelementptr ptr, ptr %t59, i32 1
  store ptr %t58, ptr %t62
  br label %case.end.0.56
case.end.0.56:
  br label %case.join.54
case.arm.1.63:
  %t65 = getelementptr ptr, ptr %t49, i32 1
  %t66 = load ptr, ptr %t65
  %t67 = call ptr @malloc(i64 8)
  %t68 = inttoptr i64 3 to ptr
  %t69 = getelementptr ptr, ptr %t67, i32 0
  store ptr %t68, ptr %t69
  %t70 = call ptr @v_showToken(ptr %t67)
  %t71 = getelementptr ptr, ptr %t70, i32 0
  %t72 = load ptr, ptr %t71
  %t73 = ptrtoint ptr %t72 to i64
  switch i64 %t73, label %case.default.74 [ i64 0, label %case.arm.0.76 i64 1, label %case.arm.1.84 ]
case.arm.0.76:
  %t78 = getelementptr ptr, ptr %t70, i32 1
  %t79 = load ptr, ptr %t78
  %t80 = call ptr @malloc(i64 16)
  %t81 = inttoptr i64 0 to ptr
  %t82 = getelementptr ptr, ptr %t80, i32 0
  store ptr %t81, ptr %t82
  %t83 = getelementptr ptr, ptr %t80, i32 1
  store ptr %t79, ptr %t83
  br label %case.end.0.77
case.end.0.77:
  br label %case.join.75
case.arm.1.84:
  %t86 = getelementptr ptr, ptr %t70, i32 1
  %t87 = load ptr, ptr %t86
  %t88 = call ptr @malloc(i64 16)
  %t89 = inttoptr i64 1 to ptr
  %t90 = getelementptr ptr, ptr %t88, i32 0
  store ptr %t89, ptr %t90
  %t91 = getelementptr [2 x i8], ptr @.str.6, i64 0, i64 0
  %t92 = call ptr @__concat(ptr %t22, ptr %t91)
  %t93 = getelementptr ptr, ptr %t88, i32 1
  store ptr %t92, ptr %t93
  %t94 = getelementptr ptr, ptr %t88, i32 0
  %t95 = load ptr, ptr %t94
  %t96 = ptrtoint ptr %t95 to i64
  switch i64 %t96, label %case.default.97 [ i64 0, label %case.arm.0.99 i64 1, label %case.arm.1.107 ]
case.arm.0.99:
  %t101 = getelementptr ptr, ptr %t88, i32 1
  %t102 = load ptr, ptr %t101
  %t103 = call ptr @malloc(i64 16)
  %t104 = inttoptr i64 0 to ptr
  %t105 = getelementptr ptr, ptr %t103, i32 0
  store ptr %t104, ptr %t105
  %t106 = getelementptr ptr, ptr %t103, i32 1
  store ptr %t102, ptr %t106
  br label %case.end.0.100
case.end.0.100:
  br label %case.join.98
case.arm.1.107:
  %t109 = getelementptr ptr, ptr %t88, i32 1
  %t110 = load ptr, ptr %t109
  %t111 = call ptr @malloc(i64 16)
  %t112 = inttoptr i64 1 to ptr
  %t113 = getelementptr ptr, ptr %t111, i32 0
  store ptr %t112, ptr %t113
  %t114 = call ptr @__concat(ptr %t110, ptr %t43)
  %t115 = getelementptr ptr, ptr %t111, i32 1
  store ptr %t114, ptr %t115
  %t116 = getelementptr ptr, ptr %t111, i32 0
  %t117 = load ptr, ptr %t116
  %t118 = ptrtoint ptr %t117 to i64
  switch i64 %t118, label %case.default.119 [ i64 0, label %case.arm.0.121 i64 1, label %case.arm.1.129 ]
case.arm.0.121:
  %t123 = getelementptr ptr, ptr %t111, i32 1
  %t124 = load ptr, ptr %t123
  %t125 = call ptr @malloc(i64 16)
  %t126 = inttoptr i64 0 to ptr
  %t127 = getelementptr ptr, ptr %t125, i32 0
  store ptr %t126, ptr %t127
  %t128 = getelementptr ptr, ptr %t125, i32 1
  store ptr %t124, ptr %t128
  br label %case.end.0.122
case.end.0.122:
  br label %case.join.120
case.arm.1.129:
  %t131 = getelementptr ptr, ptr %t111, i32 1
  %t132 = load ptr, ptr %t131
  %t133 = call ptr @malloc(i64 16)
  %t134 = inttoptr i64 1 to ptr
  %t135 = getelementptr ptr, ptr %t133, i32 0
  store ptr %t134, ptr %t135
  %t136 = getelementptr [2 x i8], ptr @.str.6, i64 0, i64 0
  %t137 = call ptr @__concat(ptr %t132, ptr %t136)
  %t138 = getelementptr ptr, ptr %t133, i32 1
  store ptr %t137, ptr %t138
  %t139 = getelementptr ptr, ptr %t133, i32 0
  %t140 = load ptr, ptr %t139
  %t141 = ptrtoint ptr %t140 to i64
  switch i64 %t141, label %case.default.142 [ i64 0, label %case.arm.0.144 i64 1, label %case.arm.1.152 ]
case.arm.0.144:
  %t146 = getelementptr ptr, ptr %t133, i32 1
  %t147 = load ptr, ptr %t146
  %t148 = call ptr @malloc(i64 16)
  %t149 = inttoptr i64 0 to ptr
  %t150 = getelementptr ptr, ptr %t148, i32 0
  store ptr %t149, ptr %t150
  %t151 = getelementptr ptr, ptr %t148, i32 1
  store ptr %t147, ptr %t151
  br label %case.end.0.145
case.end.0.145:
  br label %case.join.143
case.arm.1.152:
  %t154 = getelementptr ptr, ptr %t133, i32 1
  %t155 = load ptr, ptr %t154
  %t156 = call ptr @malloc(i64 16)
  %t157 = inttoptr i64 1 to ptr
  %t158 = getelementptr ptr, ptr %t156, i32 0
  store ptr %t157, ptr %t158
  %t159 = call ptr @__concat(ptr %t155, ptr %t66)
  %t160 = getelementptr ptr, ptr %t156, i32 1
  store ptr %t159, ptr %t160
  %t161 = getelementptr ptr, ptr %t156, i32 0
  %t162 = load ptr, ptr %t161
  %t163 = ptrtoint ptr %t162 to i64
  switch i64 %t163, label %case.default.164 [ i64 0, label %case.arm.0.166 i64 1, label %case.arm.1.174 ]
case.arm.0.166:
  %t168 = getelementptr ptr, ptr %t156, i32 1
  %t169 = load ptr, ptr %t168
  %t170 = call ptr @malloc(i64 16)
  %t171 = inttoptr i64 0 to ptr
  %t172 = getelementptr ptr, ptr %t170, i32 0
  store ptr %t171, ptr %t172
  %t173 = getelementptr ptr, ptr %t170, i32 1
  store ptr %t169, ptr %t173
  br label %case.end.0.167
case.end.0.167:
  br label %case.join.165
case.arm.1.174:
  %t176 = getelementptr ptr, ptr %t156, i32 1
  %t177 = load ptr, ptr %t176
  %t178 = call ptr @malloc(i64 16)
  %t179 = inttoptr i64 1 to ptr
  %t180 = getelementptr ptr, ptr %t178, i32 0
  store ptr %t179, ptr %t180
  %t181 = getelementptr [2 x i8], ptr @.str.6, i64 0, i64 0
  %t182 = call ptr @__concat(ptr %t177, ptr %t181)
  %t183 = getelementptr ptr, ptr %t178, i32 1
  store ptr %t182, ptr %t183
  %t184 = getelementptr ptr, ptr %t178, i32 0
  %t185 = load ptr, ptr %t184
  %t186 = ptrtoint ptr %t185 to i64
  switch i64 %t186, label %case.default.187 [ i64 0, label %case.arm.0.189 i64 1, label %case.arm.1.197 ]
case.arm.0.189:
  %t191 = getelementptr ptr, ptr %t178, i32 1
  %t192 = load ptr, ptr %t191
  %t193 = call ptr @malloc(i64 16)
  %t194 = inttoptr i64 0 to ptr
  %t195 = getelementptr ptr, ptr %t193, i32 0
  store ptr %t194, ptr %t195
  %t196 = getelementptr ptr, ptr %t193, i32 1
  store ptr %t192, ptr %t196
  br label %case.end.0.190
case.end.0.190:
  br label %case.join.188
case.arm.1.197:
  %t199 = getelementptr ptr, ptr %t178, i32 1
  %t200 = load ptr, ptr %t199
  %t201 = call ptr @malloc(i64 16)
  %t202 = inttoptr i64 1 to ptr
  %t203 = getelementptr ptr, ptr %t201, i32 0
  store ptr %t202, ptr %t203
  %t204 = call ptr @__concat(ptr %t200, ptr %t87)
  %t205 = getelementptr ptr, ptr %t201, i32 1
  store ptr %t204, ptr %t205
  br label %case.end.1.198
case.end.1.198:
  br label %case.join.188
case.default.187:
  unreachable
case.join.188:
  %t206 = phi ptr [%t193, %case.end.0.190], [%t201, %case.end.1.198]
  br label %case.end.1.175
case.end.1.175:
  br label %case.join.165
case.default.164:
  unreachable
case.join.165:
  %t207 = phi ptr [%t170, %case.end.0.167], [%t206, %case.end.1.175]
  br label %case.end.1.153
case.end.1.153:
  br label %case.join.143
case.default.142:
  unreachable
case.join.143:
  %t208 = phi ptr [%t148, %case.end.0.145], [%t207, %case.end.1.153]
  br label %case.end.1.130
case.end.1.130:
  br label %case.join.120
case.default.119:
  unreachable
case.join.120:
  %t209 = phi ptr [%t125, %case.end.0.122], [%t208, %case.end.1.130]
  br label %case.end.1.108
case.end.1.108:
  br label %case.join.98
case.default.97:
  unreachable
case.join.98:
  %t210 = phi ptr [%t103, %case.end.0.100], [%t209, %case.end.1.108]
  br label %case.end.1.85
case.end.1.85:
  br label %case.join.75
case.default.74:
  unreachable
case.join.75:
  %t211 = phi ptr [%t80, %case.end.0.77], [%t210, %case.end.1.85]
  br label %case.end.1.64
case.end.1.64:
  br label %case.join.54
case.default.53:
  unreachable
case.join.54:
  %t212 = phi ptr [%t59, %case.end.0.56], [%t211, %case.end.1.64]
  br label %case.end.1.41
case.end.1.41:
  br label %case.join.31
case.default.30:
  unreachable
case.join.31:
  %t213 = phi ptr [%t36, %case.end.0.33], [%t212, %case.end.1.41]
  br label %case.end.1.20
case.end.1.20:
  br label %case.join.10
case.default.9:
  unreachable
case.join.10:
  %t214 = phi ptr [%t15, %case.end.0.12], [%t213, %case.end.1.20]
  %t215 = call ptr @v__let_2(ptr %t214)
  ret ptr %t215
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
  %t12 = getelementptr [16 x i8], ptr @.str.7, i64 0, i64 0
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
