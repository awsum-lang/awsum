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
@.str.5 = private unnamed_addr constant [16 x i8] c"STRING_TOO_LONG\00"

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
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.23 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_r, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr ptr, ptr %t8, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %case.default.12 [ i64 0, label %case.arm.0.14 i64 1, label %case.arm.1.18 ]
case.arm.0.14:
  %t16 = getelementptr ptr, ptr %t8, i32 1
  %t17 = load ptr, ptr %t16
  br label %case.end.0.15
case.end.0.15:
  br label %case.join.13
case.arm.1.18:
  %t20 = getelementptr ptr, ptr %t8, i32 1
  %t21 = load ptr, ptr %t20
  br label %case.end.1.19
case.end.1.19:
  br label %case.join.13
case.default.12:
  unreachable
case.join.13:
  %t22 = phi ptr [%t17, %case.end.0.15], [%t21, %case.end.1.19]
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.23:
  %t25 = getelementptr ptr, ptr %v_r, i32 1
  %t26 = load ptr, ptr %t25
  %t27 = getelementptr ptr, ptr %t26, i32 0
  %t28 = load ptr, ptr %t27
  %t29 = ptrtoint ptr %t28 to i64
  switch i64 %t29, label %case.default.30 [ i64 0, label %case.arm.0.32 i64 1, label %case.arm.1.36 ]
case.arm.0.32:
  %t34 = getelementptr ptr, ptr %t26, i32 1
  %t35 = load ptr, ptr %t34
  br label %case.end.0.33
case.end.0.33:
  br label %case.join.31
case.arm.1.36:
  %t38 = getelementptr ptr, ptr %t26, i32 1
  %t39 = load ptr, ptr %t38
  br label %case.end.1.37
case.end.1.37:
  br label %case.join.31
case.default.30:
  unreachable
case.join.31:
  %t40 = phi ptr [%t35, %case.end.0.33], [%t39, %case.end.1.37]
  br label %case.end.1.24
case.end.1.24:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t41 = phi ptr [%t22, %case.end.0.6], [%t40, %case.end.1.24]
  ret ptr %t41
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
  %t9 = getelementptr [2 x i8], ptr @.str.0, i64 0, i64 0
  %t10 = getelementptr ptr, ptr %t6, i32 1
  store ptr %t9, ptr %t10
  %t11 = getelementptr ptr, ptr %t3, i32 1
  store ptr %t6, ptr %t11
  %t12 = call ptr @v_unwrap(ptr %t3)
  %t13 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  %t14 = call ptr @__concat(ptr %t12, ptr %t13)
  %t15 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t14, ptr %t15
  %t16 = getelementptr ptr, ptr %t0, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %case.default.19 [ i64 0, label %case.arm.0.21 i64 1, label %case.arm.1.29 ]
case.arm.0.21:
  %t23 = getelementptr ptr, ptr %t0, i32 1
  %t24 = load ptr, ptr %t23
  %t25 = call ptr @malloc(i64 16)
  %t26 = inttoptr i64 0 to ptr
  %t27 = getelementptr ptr, ptr %t25, i32 0
  store ptr %t26, ptr %t27
  %t28 = getelementptr ptr, ptr %t25, i32 1
  store ptr %t24, ptr %t28
  br label %case.end.0.22
case.end.0.22:
  br label %case.join.20
case.arm.1.29:
  %t31 = getelementptr ptr, ptr %t0, i32 1
  %t32 = load ptr, ptr %t31
  %t33 = call ptr @malloc(i64 16)
  %t34 = inttoptr i64 1 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = call ptr @malloc(i64 16)
  %t37 = inttoptr i64 0 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = call ptr @malloc(i64 16)
  %t40 = inttoptr i64 1 to ptr
  %t41 = getelementptr ptr, ptr %t39, i32 0
  store ptr %t40, ptr %t41
  %t42 = getelementptr [2 x i8], ptr @.str.2, i64 0, i64 0
  %t43 = getelementptr ptr, ptr %t39, i32 1
  store ptr %t42, ptr %t43
  %t44 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t39, ptr %t44
  %t45 = call ptr @v_unwrap(ptr %t36)
  %t46 = call ptr @__concat(ptr %t32, ptr %t45)
  %t47 = getelementptr ptr, ptr %t33, i32 1
  store ptr %t46, ptr %t47
  %t48 = getelementptr ptr, ptr %t33, i32 0
  %t49 = load ptr, ptr %t48
  %t50 = ptrtoint ptr %t49 to i64
  switch i64 %t50, label %case.default.51 [ i64 0, label %case.arm.0.53 i64 1, label %case.arm.1.61 ]
case.arm.0.53:
  %t55 = getelementptr ptr, ptr %t33, i32 1
  %t56 = load ptr, ptr %t55
  %t57 = call ptr @malloc(i64 16)
  %t58 = inttoptr i64 0 to ptr
  %t59 = getelementptr ptr, ptr %t57, i32 0
  store ptr %t58, ptr %t59
  %t60 = getelementptr ptr, ptr %t57, i32 1
  store ptr %t56, ptr %t60
  br label %case.end.0.54
case.end.0.54:
  br label %case.join.52
case.arm.1.61:
  %t63 = getelementptr ptr, ptr %t33, i32 1
  %t64 = load ptr, ptr %t63
  %t65 = call ptr @malloc(i64 16)
  %t66 = inttoptr i64 1 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  %t68 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  %t69 = call ptr @__concat(ptr %t64, ptr %t68)
  %t70 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t69, ptr %t70
  %t71 = getelementptr ptr, ptr %t65, i32 0
  %t72 = load ptr, ptr %t71
  %t73 = ptrtoint ptr %t72 to i64
  switch i64 %t73, label %case.default.74 [ i64 0, label %case.arm.0.76 i64 1, label %case.arm.1.84 ]
case.arm.0.76:
  %t78 = getelementptr ptr, ptr %t65, i32 1
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
  %t86 = getelementptr ptr, ptr %t65, i32 1
  %t87 = load ptr, ptr %t86
  %t88 = call ptr @malloc(i64 16)
  %t89 = inttoptr i64 1 to ptr
  %t90 = getelementptr ptr, ptr %t88, i32 0
  store ptr %t89, ptr %t90
  %t91 = call ptr @malloc(i64 16)
  %t92 = inttoptr i64 1 to ptr
  %t93 = getelementptr ptr, ptr %t91, i32 0
  store ptr %t92, ptr %t93
  %t94 = call ptr @malloc(i64 16)
  %t95 = inttoptr i64 0 to ptr
  %t96 = getelementptr ptr, ptr %t94, i32 0
  store ptr %t95, ptr %t96
  %t97 = getelementptr [2 x i8], ptr @.str.3, i64 0, i64 0
  %t98 = getelementptr ptr, ptr %t94, i32 1
  store ptr %t97, ptr %t98
  %t99 = getelementptr ptr, ptr %t91, i32 1
  store ptr %t94, ptr %t99
  %t100 = call ptr @v_unwrap(ptr %t91)
  %t101 = call ptr @__concat(ptr %t87, ptr %t100)
  %t102 = getelementptr ptr, ptr %t88, i32 1
  store ptr %t101, ptr %t102
  %t103 = getelementptr ptr, ptr %t88, i32 0
  %t104 = load ptr, ptr %t103
  %t105 = ptrtoint ptr %t104 to i64
  switch i64 %t105, label %case.default.106 [ i64 0, label %case.arm.0.108 i64 1, label %case.arm.1.116 ]
case.arm.0.108:
  %t110 = getelementptr ptr, ptr %t88, i32 1
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
  %t118 = getelementptr ptr, ptr %t88, i32 1
  %t119 = load ptr, ptr %t118
  %t120 = call ptr @malloc(i64 16)
  %t121 = inttoptr i64 1 to ptr
  %t122 = getelementptr ptr, ptr %t120, i32 0
  store ptr %t121, ptr %t122
  %t123 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  %t124 = call ptr @__concat(ptr %t119, ptr %t123)
  %t125 = getelementptr ptr, ptr %t120, i32 1
  store ptr %t124, ptr %t125
  %t126 = getelementptr ptr, ptr %t120, i32 0
  %t127 = load ptr, ptr %t126
  %t128 = ptrtoint ptr %t127 to i64
  switch i64 %t128, label %case.default.129 [ i64 0, label %case.arm.0.131 i64 1, label %case.arm.1.139 ]
case.arm.0.131:
  %t133 = getelementptr ptr, ptr %t120, i32 1
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
  %t141 = getelementptr ptr, ptr %t120, i32 1
  %t142 = load ptr, ptr %t141
  %t143 = call ptr @malloc(i64 16)
  %t144 = inttoptr i64 1 to ptr
  %t145 = getelementptr ptr, ptr %t143, i32 0
  store ptr %t144, ptr %t145
  %t146 = call ptr @malloc(i64 16)
  %t147 = inttoptr i64 1 to ptr
  %t148 = getelementptr ptr, ptr %t146, i32 0
  store ptr %t147, ptr %t148
  %t149 = call ptr @malloc(i64 16)
  %t150 = inttoptr i64 1 to ptr
  %t151 = getelementptr ptr, ptr %t149, i32 0
  store ptr %t150, ptr %t151
  %t152 = getelementptr [2 x i8], ptr @.str.4, i64 0, i64 0
  %t153 = getelementptr ptr, ptr %t149, i32 1
  store ptr %t152, ptr %t153
  %t154 = getelementptr ptr, ptr %t146, i32 1
  store ptr %t149, ptr %t154
  %t155 = call ptr @v_unwrap(ptr %t146)
  %t156 = call ptr @__concat(ptr %t142, ptr %t155)
  %t157 = getelementptr ptr, ptr %t143, i32 1
  store ptr %t156, ptr %t157
  br label %case.end.1.140
case.end.1.140:
  br label %case.join.130
case.default.129:
  unreachable
case.join.130:
  %t158 = phi ptr [%t135, %case.end.0.132], [%t143, %case.end.1.140]
  br label %case.end.1.117
case.end.1.117:
  br label %case.join.107
case.default.106:
  unreachable
case.join.107:
  %t159 = phi ptr [%t112, %case.end.0.109], [%t158, %case.end.1.117]
  br label %case.end.1.85
case.end.1.85:
  br label %case.join.75
case.default.74:
  unreachable
case.join.75:
  %t160 = phi ptr [%t80, %case.end.0.77], [%t159, %case.end.1.85]
  br label %case.end.1.62
case.end.1.62:
  br label %case.join.52
case.default.51:
  unreachable
case.join.52:
  %t161 = phi ptr [%t57, %case.end.0.54], [%t160, %case.end.1.62]
  br label %case.end.1.30
case.end.1.30:
  br label %case.join.20
case.default.19:
  unreachable
case.join.20:
  %t162 = phi ptr [%t25, %case.end.0.22], [%t161, %case.end.1.30]
  %t163 = call ptr @v__let_2(ptr %t162)
  ret ptr %t163
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
  %t12 = getelementptr [16 x i8], ptr @.str.5, i64 0, i64 0
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
