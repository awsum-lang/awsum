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
  %la_box = call ptr @__lengthUtf16CodeUnits(ptr %a)
  %la = load i32, ptr %la_box
  %lb_box = call ptr @__lengthUtf16CodeUnits(ptr %b)
  %lb = load i32, ptr %lb_box
  %la64 = zext i32 %la to i64
  %lb64 = zext i32 %lb to i64
  %sum64 = add i64 %la64, %lb64
  %over = icmp ugt i64 %sum64, 134217728
  br i1 %over, label %too_long, label %ok
too_long:
  %stl = call ptr @malloc(i64 8)
  %stl_tag = inttoptr i64 0 to ptr
  store ptr %stl_tag, ptr %stl
  %left = call ptr @malloc(i64 16)
  %left_tag = inttoptr i64 0 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %stl, ptr %left_f
  ret ptr %left
ok:
  %ba = call i64 @strlen(ptr %a)
  %bb = call i64 @strlen(ptr %b)
  %bsum = add i64 %ba, %bb
  %total = add i64 %bsum, 1
  %buf = call ptr @malloc(i64 %total)
  call ptr @strcpy(ptr %buf, ptr %a)
  call ptr @strcat(ptr %buf, ptr %b)
  %right = call ptr @malloc(i64 16)
  %right_tag = inttoptr i64 1 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %buf, ptr %right_f
  ret ptr %right
}


define internal ptr @__print(ptr %s) {
  call i32 (ptr, ...) @printf(ptr @.fmt, ptr %s)
  %unit = call ptr @malloc(i64 8)
  %unit_tag_ptr = getelementptr ptr, ptr %unit, i32 0
  %unit_tag = inttoptr i64 0 to ptr
  store ptr %unit_tag, ptr %unit_tag_ptr
  ret ptr %unit
}


define internal ptr @__lengthUtf16CodeUnits(ptr %s) {
entry:
  %i_p = alloca i64, align 8
  store i64 0, ptr %i_p
  %n_p = alloca i32, align 4
  store i32 0, ptr %n_p
  br label %head
head:
  %i = load i64, ptr %i_p
  %bp = getelementptr i8, ptr %s, i64 %i
  %b = load i8, ptr %bp
  %is_nul = icmp eq i8 %b, 0
  br i1 %is_nul, label %done, label %body
body:
  %bz = zext i8 %b to i32
  %top2 = and i32 %bz, 192
  %is_cont = icmp eq i32 %top2, 128
  br i1 %is_cont, label %step, label %check4
check4:
  %top5 = and i32 %bz, 248
  %is_4 = icmp eq i32 %top5, 240
  br i1 %is_4, label %add2, label %add1
add2:
  %n2_0 = load i32, ptr %n_p
  %n2_1 = add i32 %n2_0, 2
  store i32 %n2_1, ptr %n_p
  br label %step
add1:
  %n1_0 = load i32, ptr %n_p
  %n1_1 = add i32 %n1_0, 1
  store i32 %n1_1, ptr %n_p
  br label %step
step:
  %i1 = add i64 %i, 1
  store i64 %i1, ptr %i_p
  br label %head
done:
  %nf = load i32, ptr %n_p
  %box = call ptr @malloc(i64 4)
  store i32 %nf, ptr %box
  ret ptr %box
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
  %t0 = getelementptr [2 x i8], ptr @.str.4, i64 0, i64 0
  %t1 = call ptr @v_greeting(ptr %t0)
  %t2 = getelementptr [2 x i8], ptr @.str.5, i64 0, i64 0
  %t3 = call ptr @__concat(ptr %t1, ptr %t2)
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
  %t21 = call ptr @malloc(i64 16)
  %t22 = inttoptr i64 0 to ptr
  %t23 = getelementptr ptr, ptr %t21, i32 0
  store ptr %t22, ptr %t23
  %t24 = getelementptr [2 x i8], ptr @.str.6, i64 0, i64 0
  %t25 = getelementptr ptr, ptr %t21, i32 1
  store ptr %t24, ptr %t25
  %t26 = call ptr @v_unwrapBox(ptr %t21)
  %t27 = call ptr @__concat(ptr %t20, ptr %t26)
  %t28 = getelementptr ptr, ptr %t27, i32 0
  %t29 = load ptr, ptr %t28
  %t30 = ptrtoint ptr %t29 to i64
  switch i64 %t30, label %case.default.31 [ i64 0, label %case.arm.0.33 i64 1, label %case.arm.1.41 ]
case.arm.0.33:
  %t35 = getelementptr ptr, ptr %t27, i32 1
  %t36 = load ptr, ptr %t35
  %t37 = call ptr @malloc(i64 16)
  %t38 = inttoptr i64 0 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = getelementptr ptr, ptr %t37, i32 1
  store ptr %t36, ptr %t40
  br label %case.end.0.34
case.end.0.34:
  br label %case.join.32
case.arm.1.41:
  %t43 = getelementptr ptr, ptr %t27, i32 1
  %t44 = load ptr, ptr %t43
  %t45 = getelementptr [2 x i8], ptr @.str.5, i64 0, i64 0
  %t46 = call ptr @__concat(ptr %t44, ptr %t45)
  %t47 = getelementptr ptr, ptr %t46, i32 0
  %t48 = load ptr, ptr %t47
  %t49 = ptrtoint ptr %t48 to i64
  switch i64 %t49, label %case.default.50 [ i64 0, label %case.arm.0.52 i64 1, label %case.arm.1.60 ]
case.arm.0.52:
  %t54 = getelementptr ptr, ptr %t46, i32 1
  %t55 = load ptr, ptr %t54
  %t56 = call ptr @malloc(i64 16)
  %t57 = inttoptr i64 0 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  %t59 = getelementptr ptr, ptr %t56, i32 1
  store ptr %t55, ptr %t59
  br label %case.end.0.53
case.end.0.53:
  br label %case.join.51
case.arm.1.60:
  %t62 = getelementptr ptr, ptr %t46, i32 1
  %t63 = load ptr, ptr %t62
  %t64 = call ptr @malloc(i64 16)
  %t65 = inttoptr i64 0 to ptr
  %t66 = getelementptr ptr, ptr %t64, i32 0
  store ptr %t65, ptr %t66
  %t67 = getelementptr [2 x i8], ptr @.str.7, i64 0, i64 0
  %t68 = getelementptr ptr, ptr %t64, i32 1
  store ptr %t67, ptr %t68
  %t69 = call ptr @v_unwrapBoxNamed(ptr %t64)
  %t70 = call ptr @__concat(ptr %t63, ptr %t69)
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
  %t88 = getelementptr [2 x i8], ptr @.str.5, i64 0, i64 0
  %t89 = call ptr @__concat(ptr %t87, ptr %t88)
  %t90 = getelementptr ptr, ptr %t89, i32 0
  %t91 = load ptr, ptr %t90
  %t92 = ptrtoint ptr %t91 to i64
  switch i64 %t92, label %case.default.93 [ i64 0, label %case.arm.0.95 i64 1, label %case.arm.1.103 ]
case.arm.0.95:
  %t97 = getelementptr ptr, ptr %t89, i32 1
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
  %t105 = getelementptr ptr, ptr %t89, i32 1
  %t106 = load ptr, ptr %t105
  %t107 = call ptr @malloc(i64 24)
  %t108 = inttoptr i64 0 to ptr
  %t109 = getelementptr ptr, ptr %t107, i32 0
  store ptr %t108, ptr %t109
  %t110 = getelementptr [2 x i8], ptr @.str.8, i64 0, i64 0
  %t111 = getelementptr ptr, ptr %t107, i32 1
  store ptr %t110, ptr %t111
  %t112 = getelementptr [2 x i8], ptr @.str.9, i64 0, i64 0
  %t113 = getelementptr ptr, ptr %t107, i32 2
  store ptr %t112, ptr %t113
  %t114 = call ptr @v_showPair(ptr %t107)
  %t115 = call ptr @__concat(ptr %t106, ptr %t114)
  br label %case.end.1.104
case.end.1.104:
  br label %case.join.94
case.default.93:
  unreachable
case.join.94:
  %t116 = phi ptr [%t99, %case.end.0.96], [%t115, %case.end.1.104]
  br label %case.end.1.85
case.end.1.85:
  br label %case.join.75
case.default.74:
  unreachable
case.join.75:
  %t117 = phi ptr [%t80, %case.end.0.77], [%t116, %case.end.1.85]
  br label %case.end.1.61
case.end.1.61:
  br label %case.join.51
case.default.50:
  unreachable
case.join.51:
  %t118 = phi ptr [%t56, %case.end.0.53], [%t117, %case.end.1.61]
  br label %case.end.1.42
case.end.1.42:
  br label %case.join.32
case.default.31:
  unreachable
case.join.32:
  %t119 = phi ptr [%t37, %case.end.0.34], [%t118, %case.end.1.42]
  br label %case.end.1.18
case.end.1.18:
  br label %case.join.8
case.default.7:
  unreachable
case.join.8:
  %t120 = phi ptr [%t13, %case.end.0.10], [%t119, %case.end.1.18]
  %t121 = call ptr @v__let_2(ptr %t120)
  ret ptr %t121
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
  %t12 = getelementptr [16 x i8], ptr @.str.10, i64 0, i64 0
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
