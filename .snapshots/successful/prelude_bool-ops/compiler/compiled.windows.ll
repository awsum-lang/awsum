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

@.str.0 = private unnamed_addr constant [2 x i8] c"T\00"
@.str.1 = private unnamed_addr constant [2 x i8] c"F\00"
@.str.2 = private unnamed_addr constant [16 x i8] c"STRING_TOO_LONG\00"

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


define internal ptr @v_not(ptr %v_b) {
  %t0 = getelementptr ptr, ptr %v_b, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.10 ]
case.arm.0.5:
  %t7 = call ptr @malloc(i64 8)
  %t8 = inttoptr i64 1 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.10:
  %t12 = call ptr @malloc(i64 8)
  %t13 = inttoptr i64 0 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  br label %case.end.1.11
case.end.1.11:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t15 = phi ptr [%t7, %case.end.0.6], [%t12, %case.end.1.11]
  ret ptr %t15
}

define internal ptr @v_and(ptr %v_a, ptr %v_b) {
  %t0 = getelementptr ptr, ptr %v_a, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.7 ]
case.arm.0.5:
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.7:
  %t9 = call ptr @malloc(i64 8)
  %t10 = inttoptr i64 1 to ptr
  %t11 = getelementptr ptr, ptr %t9, i32 0
  store ptr %t10, ptr %t11
  br label %case.end.1.8
case.end.1.8:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t12 = phi ptr [%v_b, %case.end.0.6], [%t9, %case.end.1.8]
  ret ptr %t12
}

define internal ptr @v_or(ptr %v_a, ptr %v_b) {
  %t0 = getelementptr ptr, ptr %v_a, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.10 ]
case.arm.0.5:
  %t7 = call ptr @malloc(i64 8)
  %t8 = inttoptr i64 0 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.10:
  br label %case.end.1.11
case.end.1.11:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t12 = phi ptr [%t7, %case.end.0.6], [%v_b, %case.end.1.11]
  ret ptr %t12
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

define internal ptr @v_showBool(ptr %v_b) {
  %t0 = getelementptr ptr, ptr %v_b, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.8 ]
case.arm.0.5:
  %t7 = getelementptr [2 x i8], ptr @.str.0, i64 0, i64 0
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.8:
  %t10 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  br label %case.end.1.9
case.end.1.9:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t11 = phi ptr [%t7, %case.end.0.6], [%t10, %case.end.1.9]
  ret ptr %t11
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @malloc(i64 8)
  %t4 = inttoptr i64 0 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = call ptr @v_not(ptr %t3)
  %t7 = call ptr @v_showBool(ptr %t6)
  %t8 = call ptr @malloc(i64 8)
  %t9 = inttoptr i64 1 to ptr
  %t10 = getelementptr ptr, ptr %t8, i32 0
  store ptr %t9, ptr %t10
  %t11 = call ptr @v_not(ptr %t8)
  %t12 = call ptr @v_showBool(ptr %t11)
  %t13 = call ptr @__concat(ptr %t7, ptr %t12)
  %t14 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t0, i32 0
  %t16 = load ptr, ptr %t15
  %t17 = ptrtoint ptr %t16 to i64
  switch i64 %t17, label %case.default.18 [ i64 0, label %case.arm.0.20 i64 1, label %case.arm.1.28 ]
case.arm.0.20:
  %t22 = getelementptr ptr, ptr %t0, i32 1
  %t23 = load ptr, ptr %t22
  %t24 = call ptr @malloc(i64 16)
  %t25 = inttoptr i64 0 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = getelementptr ptr, ptr %t24, i32 1
  store ptr %t23, ptr %t27
  br label %case.end.0.21
case.end.0.21:
  br label %case.join.19
case.arm.1.28:
  %t30 = getelementptr ptr, ptr %t0, i32 1
  %t31 = load ptr, ptr %t30
  %t32 = call ptr @malloc(i64 16)
  %t33 = inttoptr i64 1 to ptr
  %t34 = getelementptr ptr, ptr %t32, i32 0
  store ptr %t33, ptr %t34
  %t35 = call ptr @malloc(i64 8)
  %t36 = inttoptr i64 0 to ptr
  %t37 = getelementptr ptr, ptr %t35, i32 0
  store ptr %t36, ptr %t37
  %t38 = call ptr @malloc(i64 8)
  %t39 = inttoptr i64 1 to ptr
  %t40 = getelementptr ptr, ptr %t38, i32 0
  store ptr %t39, ptr %t40
  %t41 = call ptr @v_and(ptr %t35, ptr %t38)
  %t42 = call ptr @v_showBool(ptr %t41)
  %t43 = call ptr @__concat(ptr %t31, ptr %t42)
  %t44 = getelementptr ptr, ptr %t32, i32 1
  store ptr %t43, ptr %t44
  %t45 = getelementptr ptr, ptr %t32, i32 0
  %t46 = load ptr, ptr %t45
  %t47 = ptrtoint ptr %t46 to i64
  switch i64 %t47, label %case.default.48 [ i64 0, label %case.arm.0.50 i64 1, label %case.arm.1.58 ]
case.arm.0.50:
  %t52 = getelementptr ptr, ptr %t32, i32 1
  %t53 = load ptr, ptr %t52
  %t54 = call ptr @malloc(i64 16)
  %t55 = inttoptr i64 0 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t53, ptr %t57
  br label %case.end.0.51
case.end.0.51:
  br label %case.join.49
case.arm.1.58:
  %t60 = getelementptr ptr, ptr %t32, i32 1
  %t61 = load ptr, ptr %t60
  %t62 = call ptr @malloc(i64 16)
  %t63 = inttoptr i64 1 to ptr
  %t64 = getelementptr ptr, ptr %t62, i32 0
  store ptr %t63, ptr %t64
  %t65 = call ptr @malloc(i64 8)
  %t66 = inttoptr i64 0 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  %t68 = call ptr @malloc(i64 8)
  %t69 = inttoptr i64 0 to ptr
  %t70 = getelementptr ptr, ptr %t68, i32 0
  store ptr %t69, ptr %t70
  %t71 = call ptr @v_and(ptr %t65, ptr %t68)
  %t72 = call ptr @v_showBool(ptr %t71)
  %t73 = call ptr @__concat(ptr %t61, ptr %t72)
  %t74 = getelementptr ptr, ptr %t62, i32 1
  store ptr %t73, ptr %t74
  %t75 = getelementptr ptr, ptr %t62, i32 0
  %t76 = load ptr, ptr %t75
  %t77 = ptrtoint ptr %t76 to i64
  switch i64 %t77, label %case.default.78 [ i64 0, label %case.arm.0.80 i64 1, label %case.arm.1.88 ]
case.arm.0.80:
  %t82 = getelementptr ptr, ptr %t62, i32 1
  %t83 = load ptr, ptr %t82
  %t84 = call ptr @malloc(i64 16)
  %t85 = inttoptr i64 0 to ptr
  %t86 = getelementptr ptr, ptr %t84, i32 0
  store ptr %t85, ptr %t86
  %t87 = getelementptr ptr, ptr %t84, i32 1
  store ptr %t83, ptr %t87
  br label %case.end.0.81
case.end.0.81:
  br label %case.join.79
case.arm.1.88:
  %t90 = getelementptr ptr, ptr %t62, i32 1
  %t91 = load ptr, ptr %t90
  %t92 = call ptr @malloc(i64 16)
  %t93 = inttoptr i64 1 to ptr
  %t94 = getelementptr ptr, ptr %t92, i32 0
  store ptr %t93, ptr %t94
  %t95 = call ptr @malloc(i64 8)
  %t96 = inttoptr i64 1 to ptr
  %t97 = getelementptr ptr, ptr %t95, i32 0
  store ptr %t96, ptr %t97
  %t98 = call ptr @malloc(i64 8)
  %t99 = inttoptr i64 1 to ptr
  %t100 = getelementptr ptr, ptr %t98, i32 0
  store ptr %t99, ptr %t100
  %t101 = call ptr @v_or(ptr %t95, ptr %t98)
  %t102 = call ptr @v_showBool(ptr %t101)
  %t103 = call ptr @__concat(ptr %t91, ptr %t102)
  %t104 = getelementptr ptr, ptr %t92, i32 1
  store ptr %t103, ptr %t104
  %t105 = getelementptr ptr, ptr %t92, i32 0
  %t106 = load ptr, ptr %t105
  %t107 = ptrtoint ptr %t106 to i64
  switch i64 %t107, label %case.default.108 [ i64 0, label %case.arm.0.110 i64 1, label %case.arm.1.118 ]
case.arm.0.110:
  %t112 = getelementptr ptr, ptr %t92, i32 1
  %t113 = load ptr, ptr %t112
  %t114 = call ptr @malloc(i64 16)
  %t115 = inttoptr i64 0 to ptr
  %t116 = getelementptr ptr, ptr %t114, i32 0
  store ptr %t115, ptr %t116
  %t117 = getelementptr ptr, ptr %t114, i32 1
  store ptr %t113, ptr %t117
  br label %case.end.0.111
case.end.0.111:
  br label %case.join.109
case.arm.1.118:
  %t120 = getelementptr ptr, ptr %t92, i32 1
  %t121 = load ptr, ptr %t120
  %t122 = call ptr @malloc(i64 16)
  %t123 = inttoptr i64 1 to ptr
  %t124 = getelementptr ptr, ptr %t122, i32 0
  store ptr %t123, ptr %t124
  %t125 = call ptr @malloc(i64 8)
  %t126 = inttoptr i64 0 to ptr
  %t127 = getelementptr ptr, ptr %t125, i32 0
  store ptr %t126, ptr %t127
  %t128 = call ptr @malloc(i64 8)
  %t129 = inttoptr i64 1 to ptr
  %t130 = getelementptr ptr, ptr %t128, i32 0
  store ptr %t129, ptr %t130
  %t131 = call ptr @v_or(ptr %t125, ptr %t128)
  %t132 = call ptr @v_showBool(ptr %t131)
  %t133 = call ptr @__concat(ptr %t121, ptr %t132)
  %t134 = getelementptr ptr, ptr %t122, i32 1
  store ptr %t133, ptr %t134
  br label %case.end.1.119
case.end.1.119:
  br label %case.join.109
case.default.108:
  unreachable
case.join.109:
  %t135 = phi ptr [%t114, %case.end.0.111], [%t122, %case.end.1.119]
  br label %case.end.1.89
case.end.1.89:
  br label %case.join.79
case.default.78:
  unreachable
case.join.79:
  %t136 = phi ptr [%t84, %case.end.0.81], [%t135, %case.end.1.89]
  br label %case.end.1.59
case.end.1.59:
  br label %case.join.49
case.default.48:
  unreachable
case.join.49:
  %t137 = phi ptr [%t54, %case.end.0.51], [%t136, %case.end.1.59]
  br label %case.end.1.29
case.end.1.29:
  br label %case.join.19
case.default.18:
  unreachable
case.join.19:
  %t138 = phi ptr [%t24, %case.end.0.21], [%t137, %case.end.1.29]
  %t139 = call ptr @v__let_2(ptr %t138)
  ret ptr %t139
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
  %t12 = getelementptr [16 x i8], ptr @.str.2, i64 0, i64 0
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
