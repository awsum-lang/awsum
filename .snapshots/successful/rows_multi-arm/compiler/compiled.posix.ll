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

@.str.0 = private unnamed_addr constant [5 x i8] c"Unit\00"
@.str.1 = private unnamed_addr constant [8 x i8] c"Nothing\00"
@.str.2 = private unnamed_addr constant [10 x i8] c"Just True\00"
@.str.3 = private unnamed_addr constant [11 x i8] c"Just False\00"
@.str.4 = private unnamed_addr constant [6 x i8] c"Just \00"
@.str.5 = private unnamed_addr constant [3 x i8] c"; \00"
@.str.6 = private unnamed_addr constant [16 x i8] c"STRING_TOO_LONG\00"

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


define internal ptr @v_showUnit(ptr %v__wild0) {
  %t0 = getelementptr [5 x i8], ptr @.str.0, i64 0, i64 0
  ret ptr %t0
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

define internal ptr @v_whatsInside(ptr %v_x) {
  %t0 = getelementptr ptr, ptr %v_x, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.12 ]
case.arm.0.5:
  %t7 = call ptr @malloc(i64 16)
  %t8 = inttoptr i64 1 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = getelementptr [8 x i8], ptr @.str.1, i64 0, i64 0
  %t11 = getelementptr ptr, ptr %t7, i32 1
  store ptr %t10, ptr %t11
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.12:
  %t14 = getelementptr ptr, ptr %v_x, i32 1
  %t15 = load ptr, ptr %t14
  %t16 = getelementptr ptr, ptr %t15, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %case.default.19 [ i64 796142685, label %case.arm.796142685.21 i64 1759602215, label %case.arm.1759602215.45 ]
case.arm.796142685.21:
  %t23 = getelementptr ptr, ptr %t15, i32 1
  %t24 = load ptr, ptr %t23
  %t25 = getelementptr ptr, ptr %t24, i32 0
  %t26 = load ptr, ptr %t25
  %t27 = ptrtoint ptr %t26 to i64
  switch i64 %t27, label %case.default.28 [ i64 0, label %case.arm.0.30 i64 1, label %case.arm.1.37 ]
case.arm.0.30:
  %t32 = call ptr @malloc(i64 16)
  %t33 = inttoptr i64 1 to ptr
  %t34 = getelementptr ptr, ptr %t32, i32 0
  store ptr %t33, ptr %t34
  %t35 = getelementptr [10 x i8], ptr @.str.2, i64 0, i64 0
  %t36 = getelementptr ptr, ptr %t32, i32 1
  store ptr %t35, ptr %t36
  br label %case.end.0.31
case.end.0.31:
  br label %case.join.29
case.arm.1.37:
  %t39 = call ptr @malloc(i64 16)
  %t40 = inttoptr i64 1 to ptr
  %t41 = getelementptr ptr, ptr %t39, i32 0
  store ptr %t40, ptr %t41
  %t42 = getelementptr [11 x i8], ptr @.str.3, i64 0, i64 0
  %t43 = getelementptr ptr, ptr %t39, i32 1
  store ptr %t42, ptr %t43
  br label %case.end.1.38
case.end.1.38:
  br label %case.join.29
case.default.28:
  unreachable
case.join.29:
  %t44 = phi ptr [%t32, %case.end.0.31], [%t39, %case.end.1.38]
  br label %case.end.796142685.22
case.end.796142685.22:
  br label %case.join.20
case.arm.1759602215.45:
  %t47 = getelementptr ptr, ptr %t15, i32 1
  %t48 = load ptr, ptr %t47
  %t49 = call ptr @malloc(i64 16)
  %t50 = inttoptr i64 1 to ptr
  %t51 = getelementptr ptr, ptr %t49, i32 0
  store ptr %t50, ptr %t51
  %t52 = getelementptr [6 x i8], ptr @.str.4, i64 0, i64 0
  %t53 = call ptr @v_showUnit(ptr %t48)
  %t54 = call ptr @__concat(ptr %t52, ptr %t53)
  %t55 = getelementptr ptr, ptr %t49, i32 1
  store ptr %t54, ptr %t55
  br label %case.end.1759602215.46
case.end.1759602215.46:
  br label %case.join.20
case.default.19:
  unreachable
case.join.20:
  %t56 = phi ptr [%t44, %case.end.796142685.22], [%t49, %case.end.1759602215.46]
  br label %case.end.1.13
case.end.1.13:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t57 = phi ptr [%t7, %case.end.0.6], [%t56, %case.end.1.13]
  ret ptr %t57
}

define internal ptr @v_summary() {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @malloc(i64 16)
  %t4 = inttoptr i64 796142685 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = call ptr @malloc(i64 8)
  %t7 = inttoptr i64 0 to ptr
  %t8 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t7, ptr %t8
  %t9 = getelementptr ptr, ptr %t3, i32 1
  store ptr %t6, ptr %t9
  %t10 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t10
  %t11 = call ptr @v_whatsInside(ptr %t0)
  %t12 = getelementptr ptr, ptr %t11, i32 0
  %t13 = load ptr, ptr %t12
  %t14 = ptrtoint ptr %t13 to i64
  switch i64 %t14, label %case.default.15 [ i64 0, label %case.arm.0.17 i64 1, label %case.arm.1.25 ]
case.arm.0.17:
  %t19 = getelementptr ptr, ptr %t11, i32 1
  %t20 = load ptr, ptr %t19
  %t21 = call ptr @malloc(i64 16)
  %t22 = inttoptr i64 0 to ptr
  %t23 = getelementptr ptr, ptr %t21, i32 0
  store ptr %t22, ptr %t23
  %t24 = getelementptr ptr, ptr %t21, i32 1
  store ptr %t20, ptr %t24
  br label %case.end.0.18
case.end.0.18:
  br label %case.join.16
case.arm.1.25:
  %t27 = getelementptr ptr, ptr %t11, i32 1
  %t28 = load ptr, ptr %t27
  %t29 = call ptr @malloc(i64 16)
  %t30 = inttoptr i64 1 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = call ptr @malloc(i64 16)
  %t33 = inttoptr i64 1759602215 to ptr
  %t34 = getelementptr ptr, ptr %t32, i32 0
  store ptr %t33, ptr %t34
  %t35 = call ptr @malloc(i64 8)
  %t36 = inttoptr i64 0 to ptr
  %t37 = getelementptr ptr, ptr %t35, i32 0
  store ptr %t36, ptr %t37
  %t38 = getelementptr ptr, ptr %t32, i32 1
  store ptr %t35, ptr %t38
  %t39 = getelementptr ptr, ptr %t29, i32 1
  store ptr %t32, ptr %t39
  %t40 = call ptr @v_whatsInside(ptr %t29)
  %t41 = getelementptr ptr, ptr %t40, i32 0
  %t42 = load ptr, ptr %t41
  %t43 = ptrtoint ptr %t42 to i64
  switch i64 %t43, label %case.default.44 [ i64 0, label %case.arm.0.46 i64 1, label %case.arm.1.54 ]
case.arm.0.46:
  %t48 = getelementptr ptr, ptr %t40, i32 1
  %t49 = load ptr, ptr %t48
  %t50 = call ptr @malloc(i64 16)
  %t51 = inttoptr i64 0 to ptr
  %t52 = getelementptr ptr, ptr %t50, i32 0
  store ptr %t51, ptr %t52
  %t53 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t49, ptr %t53
  br label %case.end.0.47
case.end.0.47:
  br label %case.join.45
case.arm.1.54:
  %t56 = getelementptr ptr, ptr %t40, i32 1
  %t57 = load ptr, ptr %t56
  %t58 = call ptr @malloc(i64 8)
  %t59 = inttoptr i64 0 to ptr
  %t60 = getelementptr ptr, ptr %t58, i32 0
  store ptr %t59, ptr %t60
  %t61 = call ptr @v_whatsInside(ptr %t58)
  %t62 = getelementptr ptr, ptr %t61, i32 0
  %t63 = load ptr, ptr %t62
  %t64 = ptrtoint ptr %t63 to i64
  switch i64 %t64, label %case.default.65 [ i64 0, label %case.arm.0.67 i64 1, label %case.arm.1.75 ]
case.arm.0.67:
  %t69 = getelementptr ptr, ptr %t61, i32 1
  %t70 = load ptr, ptr %t69
  %t71 = call ptr @malloc(i64 16)
  %t72 = inttoptr i64 0 to ptr
  %t73 = getelementptr ptr, ptr %t71, i32 0
  store ptr %t72, ptr %t73
  %t74 = getelementptr ptr, ptr %t71, i32 1
  store ptr %t70, ptr %t74
  br label %case.end.0.68
case.end.0.68:
  br label %case.join.66
case.arm.1.75:
  %t77 = getelementptr ptr, ptr %t61, i32 1
  %t78 = load ptr, ptr %t77
  %t79 = call ptr @malloc(i64 16)
  %t80 = inttoptr i64 1 to ptr
  %t81 = getelementptr ptr, ptr %t79, i32 0
  store ptr %t80, ptr %t81
  %t82 = getelementptr [3 x i8], ptr @.str.5, i64 0, i64 0
  %t83 = call ptr @__concat(ptr %t28, ptr %t82)
  %t84 = getelementptr ptr, ptr %t79, i32 1
  store ptr %t83, ptr %t84
  %t85 = getelementptr ptr, ptr %t79, i32 0
  %t86 = load ptr, ptr %t85
  %t87 = ptrtoint ptr %t86 to i64
  switch i64 %t87, label %case.default.88 [ i64 0, label %case.arm.0.90 i64 1, label %case.arm.1.98 ]
case.arm.0.90:
  %t92 = getelementptr ptr, ptr %t79, i32 1
  %t93 = load ptr, ptr %t92
  %t94 = call ptr @malloc(i64 16)
  %t95 = inttoptr i64 0 to ptr
  %t96 = getelementptr ptr, ptr %t94, i32 0
  store ptr %t95, ptr %t96
  %t97 = getelementptr ptr, ptr %t94, i32 1
  store ptr %t93, ptr %t97
  br label %case.end.0.91
case.end.0.91:
  br label %case.join.89
case.arm.1.98:
  %t100 = getelementptr ptr, ptr %t79, i32 1
  %t101 = load ptr, ptr %t100
  %t102 = call ptr @malloc(i64 16)
  %t103 = inttoptr i64 1 to ptr
  %t104 = getelementptr ptr, ptr %t102, i32 0
  store ptr %t103, ptr %t104
  %t105 = call ptr @__concat(ptr %t101, ptr %t57)
  %t106 = getelementptr ptr, ptr %t102, i32 1
  store ptr %t105, ptr %t106
  %t107 = getelementptr ptr, ptr %t102, i32 0
  %t108 = load ptr, ptr %t107
  %t109 = ptrtoint ptr %t108 to i64
  switch i64 %t109, label %case.default.110 [ i64 0, label %case.arm.0.112 i64 1, label %case.arm.1.120 ]
case.arm.0.112:
  %t114 = getelementptr ptr, ptr %t102, i32 1
  %t115 = load ptr, ptr %t114
  %t116 = call ptr @malloc(i64 16)
  %t117 = inttoptr i64 0 to ptr
  %t118 = getelementptr ptr, ptr %t116, i32 0
  store ptr %t117, ptr %t118
  %t119 = getelementptr ptr, ptr %t116, i32 1
  store ptr %t115, ptr %t119
  br label %case.end.0.113
case.end.0.113:
  br label %case.join.111
case.arm.1.120:
  %t122 = getelementptr ptr, ptr %t102, i32 1
  %t123 = load ptr, ptr %t122
  %t124 = call ptr @malloc(i64 16)
  %t125 = inttoptr i64 1 to ptr
  %t126 = getelementptr ptr, ptr %t124, i32 0
  store ptr %t125, ptr %t126
  %t127 = getelementptr [3 x i8], ptr @.str.5, i64 0, i64 0
  %t128 = call ptr @__concat(ptr %t123, ptr %t127)
  %t129 = getelementptr ptr, ptr %t124, i32 1
  store ptr %t128, ptr %t129
  %t130 = getelementptr ptr, ptr %t124, i32 0
  %t131 = load ptr, ptr %t130
  %t132 = ptrtoint ptr %t131 to i64
  switch i64 %t132, label %case.default.133 [ i64 0, label %case.arm.0.135 i64 1, label %case.arm.1.143 ]
case.arm.0.135:
  %t137 = getelementptr ptr, ptr %t124, i32 1
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
  %t145 = getelementptr ptr, ptr %t124, i32 1
  %t146 = load ptr, ptr %t145
  %t147 = call ptr @malloc(i64 16)
  %t148 = inttoptr i64 1 to ptr
  %t149 = getelementptr ptr, ptr %t147, i32 0
  store ptr %t148, ptr %t149
  %t150 = call ptr @__concat(ptr %t146, ptr %t78)
  %t151 = getelementptr ptr, ptr %t147, i32 1
  store ptr %t150, ptr %t151
  br label %case.end.1.144
case.end.1.144:
  br label %case.join.134
case.default.133:
  unreachable
case.join.134:
  %t152 = phi ptr [%t139, %case.end.0.136], [%t147, %case.end.1.144]
  br label %case.end.1.121
case.end.1.121:
  br label %case.join.111
case.default.110:
  unreachable
case.join.111:
  %t153 = phi ptr [%t116, %case.end.0.113], [%t152, %case.end.1.121]
  br label %case.end.1.99
case.end.1.99:
  br label %case.join.89
case.default.88:
  unreachable
case.join.89:
  %t154 = phi ptr [%t94, %case.end.0.91], [%t153, %case.end.1.99]
  br label %case.end.1.76
case.end.1.76:
  br label %case.join.66
case.default.65:
  unreachable
case.join.66:
  %t155 = phi ptr [%t71, %case.end.0.68], [%t154, %case.end.1.76]
  br label %case.end.1.55
case.end.1.55:
  br label %case.join.45
case.default.44:
  unreachable
case.join.45:
  %t156 = phi ptr [%t50, %case.end.0.47], [%t155, %case.end.1.55]
  br label %case.end.1.26
case.end.1.26:
  br label %case.join.16
case.default.15:
  unreachable
case.join.16:
  %t157 = phi ptr [%t21, %case.end.0.18], [%t156, %case.end.1.26]
  ret ptr %t157
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @v_summary()
  %t1 = call ptr @v__let_2(ptr %t0)
  ret ptr %t1
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
  %t12 = getelementptr [16 x i8], ptr @.str.6, i64 0, i64 0
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
