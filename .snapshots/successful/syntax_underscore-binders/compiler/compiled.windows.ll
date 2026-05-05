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

@.str.0 = private unnamed_addr constant [3 x i8] c"hi\00"
@.str.1 = private unnamed_addr constant [10 x i8] c"unwrapped\00"
@.str.2 = private unnamed_addr constant [16 x i8] c"unwrapped-named\00"
@.str.3 = private unnamed_addr constant [7 x i8] c"paired\00"
@.str.4 = private unnamed_addr constant [2 x i8] c"x\00"
@.str.5 = private unnamed_addr constant [2 x i8] c" \00"
@.str.6 = private unnamed_addr constant [2 x i8] c"a\00"
@.str.7 = private unnamed_addr constant [2 x i8] c"b\00"
@.str.8 = private unnamed_addr constant [2 x i8] c"l\00"
@.str.9 = private unnamed_addr constant [2 x i8] c"r\00"
@.str.10 = private unnamed_addr constant [16 x i8] c"STRING_TOO_LONG\00"

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


define internal ptr @v_greeting(ptr %v__wild0) {
  %t0 = getelementptr [3 x i8], ptr @.str.0, i64 0, i64 0
  ret ptr %t0
}

define internal ptr @v_unwrapBox(ptr %v_b) {
  %t0 = getelementptr ptr, ptr %v_b, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_b, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr [10 x i8], ptr @.str.1, i64 0, i64 0
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t10 = phi ptr [%t9, %case.end.0.6]
  ret ptr %t10
}

define internal ptr @v_unwrapBoxNamed(ptr %v_b) {
  %t0 = getelementptr ptr, ptr %v_b, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_b, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr [16 x i8], ptr @.str.2, i64 0, i64 0
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t10 = phi ptr [%t9, %case.end.0.6]
  ret ptr %t10
}

define internal ptr @v_showPair(ptr %v_p) {
  %t0 = getelementptr ptr, ptr %v_p, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_p, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr ptr, ptr %v_p, i32 2
  %t10 = load ptr, ptr %t9
  %t11 = getelementptr [7 x i8], ptr @.str.3, i64 0, i64 0
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t12 = phi ptr [%t11, %case.end.0.6]
  ret ptr %t12
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr [2 x i8], ptr @.str.4, i64 0, i64 0
  %t4 = call ptr @v_greeting(ptr %t3)
  %t5 = getelementptr [2 x i8], ptr @.str.5, i64 0, i64 0
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
  %t28 = call ptr @malloc(i64 16)
  %t29 = inttoptr i64 0 to ptr
  %t30 = getelementptr ptr, ptr %t28, i32 0
  store ptr %t29, ptr %t30
  %t31 = getelementptr [2 x i8], ptr @.str.6, i64 0, i64 0
  %t32 = getelementptr ptr, ptr %t28, i32 1
  store ptr %t31, ptr %t32
  %t33 = call ptr @v_unwrapBox(ptr %t28)
  %t34 = call ptr @__concat(ptr %t24, ptr %t33)
  %t35 = getelementptr ptr, ptr %t25, i32 1
  store ptr %t34, ptr %t35
  %t36 = getelementptr ptr, ptr %t25, i32 0
  %t37 = load ptr, ptr %t36
  %t38 = ptrtoint ptr %t37 to i64
  switch i64 %t38, label %case.default.39 [ i64 0, label %case.arm.0.41 i64 1, label %case.arm.1.49 ]
case.arm.0.41:
  %t43 = getelementptr ptr, ptr %t25, i32 1
  %t44 = load ptr, ptr %t43
  %t45 = call ptr @malloc(i64 16)
  %t46 = inttoptr i64 0 to ptr
  %t47 = getelementptr ptr, ptr %t45, i32 0
  store ptr %t46, ptr %t47
  %t48 = getelementptr ptr, ptr %t45, i32 1
  store ptr %t44, ptr %t48
  br label %case.end.0.42
case.end.0.42:
  br label %case.join.40
case.arm.1.49:
  %t51 = getelementptr ptr, ptr %t25, i32 1
  %t52 = load ptr, ptr %t51
  %t53 = call ptr @malloc(i64 16)
  %t54 = inttoptr i64 1 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  %t56 = getelementptr [2 x i8], ptr @.str.5, i64 0, i64 0
  %t57 = call ptr @__concat(ptr %t52, ptr %t56)
  %t58 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t57, ptr %t58
  %t59 = getelementptr ptr, ptr %t53, i32 0
  %t60 = load ptr, ptr %t59
  %t61 = ptrtoint ptr %t60 to i64
  switch i64 %t61, label %case.default.62 [ i64 0, label %case.arm.0.64 i64 1, label %case.arm.1.72 ]
case.arm.0.64:
  %t66 = getelementptr ptr, ptr %t53, i32 1
  %t67 = load ptr, ptr %t66
  %t68 = call ptr @malloc(i64 16)
  %t69 = inttoptr i64 0 to ptr
  %t70 = getelementptr ptr, ptr %t68, i32 0
  store ptr %t69, ptr %t70
  %t71 = getelementptr ptr, ptr %t68, i32 1
  store ptr %t67, ptr %t71
  br label %case.end.0.65
case.end.0.65:
  br label %case.join.63
case.arm.1.72:
  %t74 = getelementptr ptr, ptr %t53, i32 1
  %t75 = load ptr, ptr %t74
  %t76 = call ptr @malloc(i64 16)
  %t77 = inttoptr i64 1 to ptr
  %t78 = getelementptr ptr, ptr %t76, i32 0
  store ptr %t77, ptr %t78
  %t79 = call ptr @malloc(i64 16)
  %t80 = inttoptr i64 0 to ptr
  %t81 = getelementptr ptr, ptr %t79, i32 0
  store ptr %t80, ptr %t81
  %t82 = getelementptr [2 x i8], ptr @.str.7, i64 0, i64 0
  %t83 = getelementptr ptr, ptr %t79, i32 1
  store ptr %t82, ptr %t83
  %t84 = call ptr @v_unwrapBoxNamed(ptr %t79)
  %t85 = call ptr @__concat(ptr %t75, ptr %t84)
  %t86 = getelementptr ptr, ptr %t76, i32 1
  store ptr %t85, ptr %t86
  %t87 = getelementptr ptr, ptr %t76, i32 0
  %t88 = load ptr, ptr %t87
  %t89 = ptrtoint ptr %t88 to i64
  switch i64 %t89, label %case.default.90 [ i64 0, label %case.arm.0.92 i64 1, label %case.arm.1.100 ]
case.arm.0.92:
  %t94 = getelementptr ptr, ptr %t76, i32 1
  %t95 = load ptr, ptr %t94
  %t96 = call ptr @malloc(i64 16)
  %t97 = inttoptr i64 0 to ptr
  %t98 = getelementptr ptr, ptr %t96, i32 0
  store ptr %t97, ptr %t98
  %t99 = getelementptr ptr, ptr %t96, i32 1
  store ptr %t95, ptr %t99
  br label %case.end.0.93
case.end.0.93:
  br label %case.join.91
case.arm.1.100:
  %t102 = getelementptr ptr, ptr %t76, i32 1
  %t103 = load ptr, ptr %t102
  %t104 = call ptr @malloc(i64 16)
  %t105 = inttoptr i64 1 to ptr
  %t106 = getelementptr ptr, ptr %t104, i32 0
  store ptr %t105, ptr %t106
  %t107 = getelementptr [2 x i8], ptr @.str.5, i64 0, i64 0
  %t108 = call ptr @__concat(ptr %t103, ptr %t107)
  %t109 = getelementptr ptr, ptr %t104, i32 1
  store ptr %t108, ptr %t109
  %t110 = getelementptr ptr, ptr %t104, i32 0
  %t111 = load ptr, ptr %t110
  %t112 = ptrtoint ptr %t111 to i64
  switch i64 %t112, label %case.default.113 [ i64 0, label %case.arm.0.115 i64 1, label %case.arm.1.123 ]
case.arm.0.115:
  %t117 = getelementptr ptr, ptr %t104, i32 1
  %t118 = load ptr, ptr %t117
  %t119 = call ptr @malloc(i64 16)
  %t120 = inttoptr i64 0 to ptr
  %t121 = getelementptr ptr, ptr %t119, i32 0
  store ptr %t120, ptr %t121
  %t122 = getelementptr ptr, ptr %t119, i32 1
  store ptr %t118, ptr %t122
  br label %case.end.0.116
case.end.0.116:
  br label %case.join.114
case.arm.1.123:
  %t125 = getelementptr ptr, ptr %t104, i32 1
  %t126 = load ptr, ptr %t125
  %t127 = call ptr @malloc(i64 16)
  %t128 = inttoptr i64 1 to ptr
  %t129 = getelementptr ptr, ptr %t127, i32 0
  store ptr %t128, ptr %t129
  %t130 = call ptr @malloc(i64 24)
  %t131 = inttoptr i64 0 to ptr
  %t132 = getelementptr ptr, ptr %t130, i32 0
  store ptr %t131, ptr %t132
  %t133 = getelementptr [2 x i8], ptr @.str.8, i64 0, i64 0
  %t134 = getelementptr ptr, ptr %t130, i32 1
  store ptr %t133, ptr %t134
  %t135 = getelementptr [2 x i8], ptr @.str.9, i64 0, i64 0
  %t136 = getelementptr ptr, ptr %t130, i32 2
  store ptr %t135, ptr %t136
  %t137 = call ptr @v_showPair(ptr %t130)
  %t138 = call ptr @__concat(ptr %t126, ptr %t137)
  %t139 = getelementptr ptr, ptr %t127, i32 1
  store ptr %t138, ptr %t139
  br label %case.end.1.124
case.end.1.124:
  br label %case.join.114
case.default.113:
  unreachable
case.join.114:
  %t140 = phi ptr [%t119, %case.end.0.116], [%t127, %case.end.1.124]
  br label %case.end.1.101
case.end.1.101:
  br label %case.join.91
case.default.90:
  unreachable
case.join.91:
  %t141 = phi ptr [%t96, %case.end.0.93], [%t140, %case.end.1.101]
  br label %case.end.1.73
case.end.1.73:
  br label %case.join.63
case.default.62:
  unreachable
case.join.63:
  %t142 = phi ptr [%t68, %case.end.0.65], [%t141, %case.end.1.73]
  br label %case.end.1.50
case.end.1.50:
  br label %case.join.40
case.default.39:
  unreachable
case.join.40:
  %t143 = phi ptr [%t45, %case.end.0.42], [%t142, %case.end.1.50]
  br label %case.end.1.22
case.end.1.22:
  br label %case.join.12
case.default.11:
  unreachable
case.join.12:
  %t144 = phi ptr [%t17, %case.end.0.14], [%t143, %case.end.1.22]
  %t145 = call ptr @v__let_1(ptr %t144)
  ret ptr %t145
}

define internal ptr @v__let_1(ptr %v_res) {
  %t0 = getelementptr ptr, ptr %v_res, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.11 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_res, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr [16 x i8], ptr @.str.10, i64 0, i64 0
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
