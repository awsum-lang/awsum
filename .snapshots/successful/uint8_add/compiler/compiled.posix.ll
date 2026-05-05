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

@.str.0 = private unnamed_addr constant [14 x i8] c"OverflowError\00"
@.str.1 = private unnamed_addr constant [11 x i8] c"overflow: \00"
@.str.2 = private unnamed_addr constant [5 x i8] c"ok: \00"
@.str.3 = private unnamed_addr constant [3 x i8] c", \00"
@.str.4 = private unnamed_addr constant [16 x i8] c"STRING_TOO_LONG\00"

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


define internal ptr @__showUInt8(ptr %p) {
  %b = load i8, ptr %p
  %v = zext i8 %b to i32
  %buf = call ptr @malloc(i64 16)
  call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 16, ptr @.fmt_u8, i32 %v)
  ret ptr %buf
}


define internal ptr @__addUInt8(ptr %pa, ptr %pb) {
  %a = load i8, ptr %pa
  %b = load i8, ptr %pb
  %a32 = zext i8 %a to i32
  %b32 = zext i8 %b to i32
  %sum32 = add i32 %a32, %b32
  %ovf = icmp ugt i32 %sum32, 255
  br i1 %ovf, label %err, label %ok
err:
  %oe = call ptr @malloc(i64 8)
  %oe_tag = inttoptr i64 0 to ptr
  store ptr %oe_tag, ptr %oe
  %left = call ptr @malloc(i64 16)
  %left_tag = inttoptr i64 0 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %oe, ptr %left_f
  ret ptr %left
ok:
  %newv = trunc i32 %sum32 to i8
  %box = call ptr @malloc(i64 1)
  store i8 %newv, ptr %box
  %right = call ptr @malloc(i64 16)
  %right_tag = inttoptr i64 1 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %box, ptr %right_f
  ret ptr %right
}


define internal ptr @v_showOverflowError(ptr %v__wild0) {
  %t0 = getelementptr [14 x i8], ptr @.str.0, i64 0, i64 0
  ret ptr %t0
}

define internal ptr @v_minUInt8() {
  %t0 = call ptr @malloc(i64 1)
  store i8 0, ptr %t0
  ret ptr %t0
}

define internal ptr @v_maxUInt8() {
  %t0 = call ptr @malloc(i64 1)
  store i8 255, ptr %t0
  ret ptr %t0
}

define internal ptr @v_render(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.16 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_r, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = call ptr @malloc(i64 16)
  %t10 = inttoptr i64 1 to ptr
  %t11 = getelementptr ptr, ptr %t9, i32 0
  store ptr %t10, ptr %t11
  %t12 = getelementptr [11 x i8], ptr @.str.1, i64 0, i64 0
  %t13 = call ptr @v_showOverflowError(ptr %t8)
  %t14 = call ptr @__concat(ptr %t12, ptr %t13)
  %t15 = getelementptr ptr, ptr %t9, i32 1
  store ptr %t14, ptr %t15
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.16:
  %t18 = getelementptr ptr, ptr %v_r, i32 1
  %t19 = load ptr, ptr %t18
  %t20 = call ptr @malloc(i64 16)
  %t21 = inttoptr i64 1 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = getelementptr [5 x i8], ptr @.str.2, i64 0, i64 0
  %t24 = call ptr @__showUInt8(ptr %t19)
  %t25 = call ptr @__concat(ptr %t23, ptr %t24)
  %t26 = getelementptr ptr, ptr %t20, i32 1
  store ptr %t25, ptr %t26
  br label %case.end.1.17
case.end.1.17:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t27 = phi ptr [%t9, %case.end.0.6], [%t20, %case.end.1.17]
  ret ptr %t27
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 1)
  store i8 200, ptr %t0
  %t1 = call ptr @malloc(i64 1)
  store i8 55, ptr %t1
  %t2 = call ptr @__addUInt8(ptr %t0, ptr %t1)
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
  %t21 = call ptr @malloc(i64 1)
  store i8 200, ptr %t21
  %t22 = call ptr @malloc(i64 1)
  store i8 56, ptr %t22
  %t23 = call ptr @__addUInt8(ptr %t21, ptr %t22)
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
  %t42 = call ptr @v_maxUInt8()
  %t43 = call ptr @v_maxUInt8()
  %t44 = call ptr @__addUInt8(ptr %t42, ptr %t43)
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
  %t63 = call ptr @v_minUInt8()
  %t64 = call ptr @v_minUInt8()
  %t65 = call ptr @__addUInt8(ptr %t63, ptr %t64)
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
  %t84 = call ptr @malloc(i64 16)
  %t85 = inttoptr i64 1 to ptr
  %t86 = getelementptr ptr, ptr %t84, i32 0
  store ptr %t85, ptr %t86
  %t87 = getelementptr [3 x i8], ptr @.str.3, i64 0, i64 0
  %t88 = call ptr @__concat(ptr %t20, ptr %t87)
  %t89 = getelementptr ptr, ptr %t84, i32 1
  store ptr %t88, ptr %t89
  %t90 = getelementptr ptr, ptr %t84, i32 0
  %t91 = load ptr, ptr %t90
  %t92 = ptrtoint ptr %t91 to i64
  switch i64 %t92, label %case.default.93 [ i64 0, label %case.arm.0.95 i64 1, label %case.arm.1.103 ]
case.arm.0.95:
  %t97 = getelementptr ptr, ptr %t84, i32 1
  %t98 = load ptr, ptr %t97
  %t99 = call ptr @malloc(i64 16)
  %t100 = inttoptr i64 0 to ptr
  %t101 = getelementptr ptr, ptr %t99, i32 0
  store ptr %t100, ptr %t101
  %t102 = getelementptr ptr, ptr %t99, i32 1
  store ptr %t98, ptr %t102
  br label %case.end.0.96
case.end.0.96:
  br label %case.join.94
case.arm.1.103:
  %t105 = getelementptr ptr, ptr %t84, i32 1
  %t106 = load ptr, ptr %t105
  %t107 = call ptr @malloc(i64 16)
  %t108 = inttoptr i64 1 to ptr
  %t109 = getelementptr ptr, ptr %t107, i32 0
  store ptr %t108, ptr %t109
  %t110 = call ptr @__concat(ptr %t106, ptr %t41)
  %t111 = getelementptr ptr, ptr %t107, i32 1
  store ptr %t110, ptr %t111
  %t112 = getelementptr ptr, ptr %t107, i32 0
  %t113 = load ptr, ptr %t112
  %t114 = ptrtoint ptr %t113 to i64
  switch i64 %t114, label %case.default.115 [ i64 0, label %case.arm.0.117 i64 1, label %case.arm.1.125 ]
case.arm.0.117:
  %t119 = getelementptr ptr, ptr %t107, i32 1
  %t120 = load ptr, ptr %t119
  %t121 = call ptr @malloc(i64 16)
  %t122 = inttoptr i64 0 to ptr
  %t123 = getelementptr ptr, ptr %t121, i32 0
  store ptr %t122, ptr %t123
  %t124 = getelementptr ptr, ptr %t121, i32 1
  store ptr %t120, ptr %t124
  br label %case.end.0.118
case.end.0.118:
  br label %case.join.116
case.arm.1.125:
  %t127 = getelementptr ptr, ptr %t107, i32 1
  %t128 = load ptr, ptr %t127
  %t129 = call ptr @malloc(i64 16)
  %t130 = inttoptr i64 1 to ptr
  %t131 = getelementptr ptr, ptr %t129, i32 0
  store ptr %t130, ptr %t131
  %t132 = getelementptr [3 x i8], ptr @.str.3, i64 0, i64 0
  %t133 = call ptr @__concat(ptr %t128, ptr %t132)
  %t134 = getelementptr ptr, ptr %t129, i32 1
  store ptr %t133, ptr %t134
  %t135 = getelementptr ptr, ptr %t129, i32 0
  %t136 = load ptr, ptr %t135
  %t137 = ptrtoint ptr %t136 to i64
  switch i64 %t137, label %case.default.138 [ i64 0, label %case.arm.0.140 i64 1, label %case.arm.1.148 ]
case.arm.0.140:
  %t142 = getelementptr ptr, ptr %t129, i32 1
  %t143 = load ptr, ptr %t142
  %t144 = call ptr @malloc(i64 16)
  %t145 = inttoptr i64 0 to ptr
  %t146 = getelementptr ptr, ptr %t144, i32 0
  store ptr %t145, ptr %t146
  %t147 = getelementptr ptr, ptr %t144, i32 1
  store ptr %t143, ptr %t147
  br label %case.end.0.141
case.end.0.141:
  br label %case.join.139
case.arm.1.148:
  %t150 = getelementptr ptr, ptr %t129, i32 1
  %t151 = load ptr, ptr %t150
  %t152 = call ptr @malloc(i64 16)
  %t153 = inttoptr i64 1 to ptr
  %t154 = getelementptr ptr, ptr %t152, i32 0
  store ptr %t153, ptr %t154
  %t155 = call ptr @__concat(ptr %t151, ptr %t62)
  %t156 = getelementptr ptr, ptr %t152, i32 1
  store ptr %t155, ptr %t156
  %t157 = getelementptr ptr, ptr %t152, i32 0
  %t158 = load ptr, ptr %t157
  %t159 = ptrtoint ptr %t158 to i64
  switch i64 %t159, label %case.default.160 [ i64 0, label %case.arm.0.162 i64 1, label %case.arm.1.170 ]
case.arm.0.162:
  %t164 = getelementptr ptr, ptr %t152, i32 1
  %t165 = load ptr, ptr %t164
  %t166 = call ptr @malloc(i64 16)
  %t167 = inttoptr i64 0 to ptr
  %t168 = getelementptr ptr, ptr %t166, i32 0
  store ptr %t167, ptr %t168
  %t169 = getelementptr ptr, ptr %t166, i32 1
  store ptr %t165, ptr %t169
  br label %case.end.0.163
case.end.0.163:
  br label %case.join.161
case.arm.1.170:
  %t172 = getelementptr ptr, ptr %t152, i32 1
  %t173 = load ptr, ptr %t172
  %t174 = call ptr @malloc(i64 16)
  %t175 = inttoptr i64 1 to ptr
  %t176 = getelementptr ptr, ptr %t174, i32 0
  store ptr %t175, ptr %t176
  %t177 = getelementptr [3 x i8], ptr @.str.3, i64 0, i64 0
  %t178 = call ptr @__concat(ptr %t173, ptr %t177)
  %t179 = getelementptr ptr, ptr %t174, i32 1
  store ptr %t178, ptr %t179
  %t180 = getelementptr ptr, ptr %t174, i32 0
  %t181 = load ptr, ptr %t180
  %t182 = ptrtoint ptr %t181 to i64
  switch i64 %t182, label %case.default.183 [ i64 0, label %case.arm.0.185 i64 1, label %case.arm.1.193 ]
case.arm.0.185:
  %t187 = getelementptr ptr, ptr %t174, i32 1
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
  %t195 = getelementptr ptr, ptr %t174, i32 1
  %t196 = load ptr, ptr %t195
  %t197 = call ptr @malloc(i64 16)
  %t198 = inttoptr i64 1 to ptr
  %t199 = getelementptr ptr, ptr %t197, i32 0
  store ptr %t198, ptr %t199
  %t200 = call ptr @__concat(ptr %t196, ptr %t83)
  %t201 = getelementptr ptr, ptr %t197, i32 1
  store ptr %t200, ptr %t201
  br label %case.end.1.194
case.end.1.194:
  br label %case.join.184
case.default.183:
  unreachable
case.join.184:
  %t202 = phi ptr [%t189, %case.end.0.186], [%t197, %case.end.1.194]
  br label %case.end.1.171
case.end.1.171:
  br label %case.join.161
case.default.160:
  unreachable
case.join.161:
  %t203 = phi ptr [%t166, %case.end.0.163], [%t202, %case.end.1.171]
  br label %case.end.1.149
case.end.1.149:
  br label %case.join.139
case.default.138:
  unreachable
case.join.139:
  %t204 = phi ptr [%t144, %case.end.0.141], [%t203, %case.end.1.149]
  br label %case.end.1.126
case.end.1.126:
  br label %case.join.116
case.default.115:
  unreachable
case.join.116:
  %t205 = phi ptr [%t121, %case.end.0.118], [%t204, %case.end.1.126]
  br label %case.end.1.104
case.end.1.104:
  br label %case.join.94
case.default.93:
  unreachable
case.join.94:
  %t206 = phi ptr [%t99, %case.end.0.96], [%t205, %case.end.1.104]
  br label %case.end.1.81
case.end.1.81:
  br label %case.join.71
case.default.70:
  unreachable
case.join.71:
  %t207 = phi ptr [%t76, %case.end.0.73], [%t206, %case.end.1.81]
  br label %case.end.1.60
case.end.1.60:
  br label %case.join.50
case.default.49:
  unreachable
case.join.50:
  %t208 = phi ptr [%t55, %case.end.0.52], [%t207, %case.end.1.60]
  br label %case.end.1.39
case.end.1.39:
  br label %case.join.29
case.default.28:
  unreachable
case.join.29:
  %t209 = phi ptr [%t34, %case.end.0.31], [%t208, %case.end.1.39]
  br label %case.end.1.18
case.end.1.18:
  br label %case.join.8
case.default.7:
  unreachable
case.join.8:
  %t210 = phi ptr [%t13, %case.end.0.10], [%t209, %case.end.1.18]
  %t211 = call ptr @v__let_1(ptr %t210)
  ret ptr %t211
}

define internal ptr @v__let_1(ptr %v_res) {
  %t0 = getelementptr ptr, ptr %v_res, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.11 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_res, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr [16 x i8], ptr @.str.4, i64 0, i64 0
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
