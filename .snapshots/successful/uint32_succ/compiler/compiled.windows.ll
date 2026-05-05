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


define internal ptr @__showUInt32(ptr %p) {
  %v = load i32, ptr %p
  %buf = call ptr @malloc(i64 16)
  call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 16, ptr @.fmt_u8, i32 %v)
  ret ptr %buf
}


define internal ptr @__succUInt32(ptr %p) {
  %v = load i32, ptr %p
  %is_max = icmp eq i32 %v, -1
  br i1 %is_max, label %overflow, label %ok
overflow:
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
  %newv = add i32 %v, 1
  %box = call ptr @malloc(i64 4)
  store i32 %newv, ptr %box
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
  %t24 = call ptr @__showUInt32(ptr %t19)
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
  %t0 = call ptr @v_maxUInt32()
  %t1 = call ptr @__succUInt32(ptr %t0)
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
  %t20 = call ptr @malloc(i64 4)
  store i32 -2, ptr %t20
  %t21 = call ptr @__succUInt32(ptr %t20)
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
  %t40 = call ptr @malloc(i64 4)
  store i32 2147483647, ptr %t40
  %t41 = call ptr @__succUInt32(ptr %t40)
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
  %t60 = call ptr @v_minUInt32()
  %t61 = call ptr @__succUInt32(ptr %t60)
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
  %t80 = call ptr @malloc(i64 16)
  %t81 = inttoptr i64 1 to ptr
  %t82 = getelementptr ptr, ptr %t80, i32 0
  store ptr %t81, ptr %t82
  %t83 = getelementptr [3 x i8], ptr @.str.3, i64 0, i64 0
  %t84 = call ptr @__concat(ptr %t19, ptr %t83)
  %t85 = getelementptr ptr, ptr %t80, i32 1
  store ptr %t84, ptr %t85
  %t86 = getelementptr ptr, ptr %t80, i32 0
  %t87 = load ptr, ptr %t86
  %t88 = ptrtoint ptr %t87 to i64
  switch i64 %t88, label %case.default.89 [ i64 0, label %case.arm.0.91 i64 1, label %case.arm.1.99 ]
case.arm.0.91:
  %t93 = getelementptr ptr, ptr %t80, i32 1
  %t94 = load ptr, ptr %t93
  %t95 = call ptr @malloc(i64 16)
  %t96 = inttoptr i64 0 to ptr
  %t97 = getelementptr ptr, ptr %t95, i32 0
  store ptr %t96, ptr %t97
  %t98 = getelementptr ptr, ptr %t95, i32 1
  store ptr %t94, ptr %t98
  br label %case.end.0.92
case.end.0.92:
  br label %case.join.90
case.arm.1.99:
  %t101 = getelementptr ptr, ptr %t80, i32 1
  %t102 = load ptr, ptr %t101
  %t103 = call ptr @malloc(i64 16)
  %t104 = inttoptr i64 1 to ptr
  %t105 = getelementptr ptr, ptr %t103, i32 0
  store ptr %t104, ptr %t105
  %t106 = call ptr @__concat(ptr %t102, ptr %t39)
  %t107 = getelementptr ptr, ptr %t103, i32 1
  store ptr %t106, ptr %t107
  %t108 = getelementptr ptr, ptr %t103, i32 0
  %t109 = load ptr, ptr %t108
  %t110 = ptrtoint ptr %t109 to i64
  switch i64 %t110, label %case.default.111 [ i64 0, label %case.arm.0.113 i64 1, label %case.arm.1.121 ]
case.arm.0.113:
  %t115 = getelementptr ptr, ptr %t103, i32 1
  %t116 = load ptr, ptr %t115
  %t117 = call ptr @malloc(i64 16)
  %t118 = inttoptr i64 0 to ptr
  %t119 = getelementptr ptr, ptr %t117, i32 0
  store ptr %t118, ptr %t119
  %t120 = getelementptr ptr, ptr %t117, i32 1
  store ptr %t116, ptr %t120
  br label %case.end.0.114
case.end.0.114:
  br label %case.join.112
case.arm.1.121:
  %t123 = getelementptr ptr, ptr %t103, i32 1
  %t124 = load ptr, ptr %t123
  %t125 = call ptr @malloc(i64 16)
  %t126 = inttoptr i64 1 to ptr
  %t127 = getelementptr ptr, ptr %t125, i32 0
  store ptr %t126, ptr %t127
  %t128 = getelementptr [3 x i8], ptr @.str.3, i64 0, i64 0
  %t129 = call ptr @__concat(ptr %t124, ptr %t128)
  %t130 = getelementptr ptr, ptr %t125, i32 1
  store ptr %t129, ptr %t130
  %t131 = getelementptr ptr, ptr %t125, i32 0
  %t132 = load ptr, ptr %t131
  %t133 = ptrtoint ptr %t132 to i64
  switch i64 %t133, label %case.default.134 [ i64 0, label %case.arm.0.136 i64 1, label %case.arm.1.144 ]
case.arm.0.136:
  %t138 = getelementptr ptr, ptr %t125, i32 1
  %t139 = load ptr, ptr %t138
  %t140 = call ptr @malloc(i64 16)
  %t141 = inttoptr i64 0 to ptr
  %t142 = getelementptr ptr, ptr %t140, i32 0
  store ptr %t141, ptr %t142
  %t143 = getelementptr ptr, ptr %t140, i32 1
  store ptr %t139, ptr %t143
  br label %case.end.0.137
case.end.0.137:
  br label %case.join.135
case.arm.1.144:
  %t146 = getelementptr ptr, ptr %t125, i32 1
  %t147 = load ptr, ptr %t146
  %t148 = call ptr @malloc(i64 16)
  %t149 = inttoptr i64 1 to ptr
  %t150 = getelementptr ptr, ptr %t148, i32 0
  store ptr %t149, ptr %t150
  %t151 = call ptr @__concat(ptr %t147, ptr %t59)
  %t152 = getelementptr ptr, ptr %t148, i32 1
  store ptr %t151, ptr %t152
  %t153 = getelementptr ptr, ptr %t148, i32 0
  %t154 = load ptr, ptr %t153
  %t155 = ptrtoint ptr %t154 to i64
  switch i64 %t155, label %case.default.156 [ i64 0, label %case.arm.0.158 i64 1, label %case.arm.1.166 ]
case.arm.0.158:
  %t160 = getelementptr ptr, ptr %t148, i32 1
  %t161 = load ptr, ptr %t160
  %t162 = call ptr @malloc(i64 16)
  %t163 = inttoptr i64 0 to ptr
  %t164 = getelementptr ptr, ptr %t162, i32 0
  store ptr %t163, ptr %t164
  %t165 = getelementptr ptr, ptr %t162, i32 1
  store ptr %t161, ptr %t165
  br label %case.end.0.159
case.end.0.159:
  br label %case.join.157
case.arm.1.166:
  %t168 = getelementptr ptr, ptr %t148, i32 1
  %t169 = load ptr, ptr %t168
  %t170 = call ptr @malloc(i64 16)
  %t171 = inttoptr i64 1 to ptr
  %t172 = getelementptr ptr, ptr %t170, i32 0
  store ptr %t171, ptr %t172
  %t173 = getelementptr [3 x i8], ptr @.str.3, i64 0, i64 0
  %t174 = call ptr @__concat(ptr %t169, ptr %t173)
  %t175 = getelementptr ptr, ptr %t170, i32 1
  store ptr %t174, ptr %t175
  %t176 = getelementptr ptr, ptr %t170, i32 0
  %t177 = load ptr, ptr %t176
  %t178 = ptrtoint ptr %t177 to i64
  switch i64 %t178, label %case.default.179 [ i64 0, label %case.arm.0.181 i64 1, label %case.arm.1.189 ]
case.arm.0.181:
  %t183 = getelementptr ptr, ptr %t170, i32 1
  %t184 = load ptr, ptr %t183
  %t185 = call ptr @malloc(i64 16)
  %t186 = inttoptr i64 0 to ptr
  %t187 = getelementptr ptr, ptr %t185, i32 0
  store ptr %t186, ptr %t187
  %t188 = getelementptr ptr, ptr %t185, i32 1
  store ptr %t184, ptr %t188
  br label %case.end.0.182
case.end.0.182:
  br label %case.join.180
case.arm.1.189:
  %t191 = getelementptr ptr, ptr %t170, i32 1
  %t192 = load ptr, ptr %t191
  %t193 = call ptr @malloc(i64 16)
  %t194 = inttoptr i64 1 to ptr
  %t195 = getelementptr ptr, ptr %t193, i32 0
  store ptr %t194, ptr %t195
  %t196 = call ptr @__concat(ptr %t192, ptr %t79)
  %t197 = getelementptr ptr, ptr %t193, i32 1
  store ptr %t196, ptr %t197
  br label %case.end.1.190
case.end.1.190:
  br label %case.join.180
case.default.179:
  unreachable
case.join.180:
  %t198 = phi ptr [%t185, %case.end.0.182], [%t193, %case.end.1.190]
  br label %case.end.1.167
case.end.1.167:
  br label %case.join.157
case.default.156:
  unreachable
case.join.157:
  %t199 = phi ptr [%t162, %case.end.0.159], [%t198, %case.end.1.167]
  br label %case.end.1.145
case.end.1.145:
  br label %case.join.135
case.default.134:
  unreachable
case.join.135:
  %t200 = phi ptr [%t140, %case.end.0.137], [%t199, %case.end.1.145]
  br label %case.end.1.122
case.end.1.122:
  br label %case.join.112
case.default.111:
  unreachable
case.join.112:
  %t201 = phi ptr [%t117, %case.end.0.114], [%t200, %case.end.1.122]
  br label %case.end.1.100
case.end.1.100:
  br label %case.join.90
case.default.89:
  unreachable
case.join.90:
  %t202 = phi ptr [%t95, %case.end.0.92], [%t201, %case.end.1.100]
  br label %case.end.1.77
case.end.1.77:
  br label %case.join.67
case.default.66:
  unreachable
case.join.67:
  %t203 = phi ptr [%t72, %case.end.0.69], [%t202, %case.end.1.77]
  br label %case.end.1.57
case.end.1.57:
  br label %case.join.47
case.default.46:
  unreachable
case.join.47:
  %t204 = phi ptr [%t52, %case.end.0.49], [%t203, %case.end.1.57]
  br label %case.end.1.37
case.end.1.37:
  br label %case.join.27
case.default.26:
  unreachable
case.join.27:
  %t205 = phi ptr [%t32, %case.end.0.29], [%t204, %case.end.1.37]
  br label %case.end.1.17
case.end.1.17:
  br label %case.join.7
case.default.6:
  unreachable
case.join.7:
  %t206 = phi ptr [%t12, %case.end.0.9], [%t205, %case.end.1.17]
  %t207 = call ptr @v__let_1(ptr %t206)
  ret ptr %t207
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
  call ptr @v_main(ptr %right_box)
  ret i32 0
}
