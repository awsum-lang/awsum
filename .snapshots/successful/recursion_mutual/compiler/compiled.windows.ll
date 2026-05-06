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

@.str.0 = private unnamed_addr constant [16 x i8] c"STRING_TOO_LONG\00"
@.str.1 = private unnamed_addr constant [1 x i8] c"\00"
@.str.2 = private unnamed_addr constant [2 x i8] c"A\00"
@.str.3 = private unnamed_addr constant [2 x i8] c"B\00"
@.str.4 = private unnamed_addr constant [2 x i8] c"C\00"

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


define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 8)
  %t1 = inttoptr i64 0 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_handleA(ptr %t0)
  %t4 = call ptr @v__let_1(ptr %t3)
  ret ptr %t4
}

define internal ptr @v__let_1(ptr %v_res) {
  %t0 = getelementptr ptr, ptr %v_res, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.11 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_res, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr [16 x i8], ptr @.str.0, i64 0, i64 0
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

define internal ptr @v__scc_handleA_handleB(ptr %v__args) {
  %t0 = call ptr @malloc(i64 8)
  %t1 = inttoptr i64 0 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__scc_handleA_handleB(ptr %v__args, ptr %t0)
  ret ptr %t3
}

define internal ptr @v__cps__scc_handleA_handleB(ptr %v__args, ptr %v__k) {
entry:
  %t3 = alloca ptr
  store ptr %v__args, ptr %t3
  %t4 = alloca ptr
  store ptr %v__k, ptr %t4
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t5 = load ptr, ptr %t3
  %t6 = load ptr, ptr %t4
  %t7 = getelementptr ptr, ptr %t5, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %tco.case.default.10 [ i64 0, label %tco.case.arm.0.11 i64 1, label %tco.case.arm.1.47 ]
tco.case.arm.0.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  %t14 = getelementptr ptr, ptr %t13, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %tco.case.default.17 [ i64 0, label %tco.case.arm.0.18 i64 1, label %tco.case.arm.1.30 i64 2, label %tco.case.arm.2.35 i64 3, label %tco.case.arm.3.40 ]
tco.case.arm.0.18:
  %t19 = call ptr @malloc(i64 16)
  %t20 = inttoptr i64 1 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = call ptr @malloc(i64 8)
  %t23 = inttoptr i64 1 to ptr
  %t24 = getelementptr ptr, ptr %t22, i32 0
  store ptr %t23, ptr %t24
  %t25 = getelementptr ptr, ptr %t19, i32 1
  store ptr %t22, ptr %t25
  %t26 = call ptr @malloc(i64 16)
  %t27 = inttoptr i64 1 to ptr
  %t28 = getelementptr ptr, ptr %t26, i32 0
  store ptr %t27, ptr %t28
  %t29 = getelementptr ptr, ptr %t26, i32 1
  store ptr %t6, ptr %t29
  store ptr %t19, ptr %t3
  store ptr %t26, ptr %t4
  br label %tco.loop.0
tco.case.arm.1.30:
  %t31 = call ptr @malloc(i64 16)
  %t32 = inttoptr i64 1 to ptr
  %t33 = getelementptr ptr, ptr %t31, i32 0
  store ptr %t32, ptr %t33
  %t34 = getelementptr ptr, ptr %t31, i32 1
  store ptr %t13, ptr %t34
  store ptr %t31, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.2.35:
  %t36 = call ptr @malloc(i64 16)
  %t37 = inttoptr i64 1 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t13, ptr %t39
  store ptr %t36, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.3.40:
  %t41 = call ptr @malloc(i64 16)
  %t42 = inttoptr i64 1 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = getelementptr [1 x i8], ptr @.str.1, i64 0, i64 0
  %t45 = getelementptr ptr, ptr %t41, i32 1
  store ptr %t44, ptr %t45
  %t46 = call ptr @v__apply__scc_handleA_handleB(ptr %t6, ptr %t41)
  store ptr %t46, ptr %t2
  br label %tco.exit.1
tco.case.default.17:
  unreachable
tco.case.arm.1.47:
  %t48 = getelementptr ptr, ptr %t5, i32 1
  %t49 = load ptr, ptr %t48
  %t50 = getelementptr ptr, ptr %t49, i32 0
  %t51 = load ptr, ptr %t50
  %t52 = ptrtoint ptr %t51 to i64
  switch i64 %t52, label %tco.case.default.53 [ i64 0, label %tco.case.arm.0.54 i64 1, label %tco.case.arm.1.59 i64 2, label %tco.case.arm.2.71 i64 3, label %tco.case.arm.3.83 ]
tco.case.arm.0.54:
  %t55 = call ptr @malloc(i64 16)
  %t56 = inttoptr i64 0 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  %t58 = getelementptr ptr, ptr %t55, i32 1
  store ptr %t49, ptr %t58
  store ptr %t55, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.1.59:
  %t60 = call ptr @malloc(i64 16)
  %t61 = inttoptr i64 0 to ptr
  %t62 = getelementptr ptr, ptr %t60, i32 0
  store ptr %t61, ptr %t62
  %t63 = call ptr @malloc(i64 8)
  %t64 = inttoptr i64 2 to ptr
  %t65 = getelementptr ptr, ptr %t63, i32 0
  store ptr %t64, ptr %t65
  %t66 = getelementptr ptr, ptr %t60, i32 1
  store ptr %t63, ptr %t66
  %t67 = call ptr @malloc(i64 16)
  %t68 = inttoptr i64 2 to ptr
  %t69 = getelementptr ptr, ptr %t67, i32 0
  store ptr %t68, ptr %t69
  %t70 = getelementptr ptr, ptr %t67, i32 1
  store ptr %t6, ptr %t70
  store ptr %t60, ptr %t3
  store ptr %t67, ptr %t4
  br label %tco.loop.0
tco.case.arm.2.71:
  %t72 = call ptr @malloc(i64 16)
  %t73 = inttoptr i64 0 to ptr
  %t74 = getelementptr ptr, ptr %t72, i32 0
  store ptr %t73, ptr %t74
  %t75 = call ptr @malloc(i64 8)
  %t76 = inttoptr i64 3 to ptr
  %t77 = getelementptr ptr, ptr %t75, i32 0
  store ptr %t76, ptr %t77
  %t78 = getelementptr ptr, ptr %t72, i32 1
  store ptr %t75, ptr %t78
  %t79 = call ptr @malloc(i64 16)
  %t80 = inttoptr i64 3 to ptr
  %t81 = getelementptr ptr, ptr %t79, i32 0
  store ptr %t80, ptr %t81
  %t82 = getelementptr ptr, ptr %t79, i32 1
  store ptr %t6, ptr %t82
  store ptr %t72, ptr %t3
  store ptr %t79, ptr %t4
  br label %tco.loop.0
tco.case.arm.3.83:
  %t84 = call ptr @malloc(i64 16)
  %t85 = inttoptr i64 1 to ptr
  %t86 = getelementptr ptr, ptr %t84, i32 0
  store ptr %t85, ptr %t86
  %t87 = getelementptr [1 x i8], ptr @.str.1, i64 0, i64 0
  %t88 = getelementptr ptr, ptr %t84, i32 1
  store ptr %t87, ptr %t88
  %t89 = call ptr @v__apply__scc_handleA_handleB(ptr %t6, ptr %t84)
  store ptr %t89, ptr %t2
  br label %tco.exit.1
tco.case.default.53:
  unreachable
tco.case.default.10:
  unreachable
tco.exit.1:
  %t90 = load ptr, ptr %t2
  ret ptr %t90
}

define internal ptr @v__apply__scc_handleA_handleB(ptr %v__k, ptr %v__x) {
entry:
  %t3 = alloca ptr
  store ptr %v__k, ptr %t3
  %t4 = alloca ptr
  store ptr %v__x, ptr %t4
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t5 = load ptr, ptr %t3
  %t6 = load ptr, ptr %t4
  %t7 = getelementptr ptr, ptr %t5, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %tco.case.default.10 [ i64 0, label %tco.case.arm.0.11 i64 1, label %tco.case.arm.1.12 i64 2, label %tco.case.arm.2.35 i64 3, label %tco.case.arm.3.58 ]
tco.case.arm.0.11:
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.1.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  %t15 = getelementptr ptr, ptr %t6, i32 0
  %t16 = load ptr, ptr %t15
  %t17 = ptrtoint ptr %t16 to i64
  switch i64 %t17, label %tco.case.default.18 [ i64 0, label %tco.case.arm.0.19 i64 1, label %tco.case.arm.1.26 ]
tco.case.arm.0.19:
  %t20 = getelementptr ptr, ptr %t6, i32 1
  %t21 = load ptr, ptr %t20
  %t22 = call ptr @malloc(i64 16)
  %t23 = inttoptr i64 0 to ptr
  %t24 = getelementptr ptr, ptr %t22, i32 0
  store ptr %t23, ptr %t24
  %t25 = getelementptr ptr, ptr %t22, i32 1
  store ptr %t21, ptr %t25
  store ptr %t14, ptr %t3
  store ptr %t22, ptr %t4
  br label %tco.loop.0
tco.case.arm.1.26:
  %t27 = getelementptr ptr, ptr %t6, i32 1
  %t28 = load ptr, ptr %t27
  %t29 = call ptr @malloc(i64 16)
  %t30 = inttoptr i64 1 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = getelementptr [2 x i8], ptr @.str.2, i64 0, i64 0
  %t33 = call ptr @__concat(ptr %t32, ptr %t28)
  %t34 = getelementptr ptr, ptr %t29, i32 1
  store ptr %t33, ptr %t34
  store ptr %t14, ptr %t3
  store ptr %t29, ptr %t4
  br label %tco.loop.0
tco.case.default.18:
  unreachable
tco.case.arm.2.35:
  %t36 = getelementptr ptr, ptr %t5, i32 1
  %t37 = load ptr, ptr %t36
  %t38 = getelementptr ptr, ptr %t6, i32 0
  %t39 = load ptr, ptr %t38
  %t40 = ptrtoint ptr %t39 to i64
  switch i64 %t40, label %tco.case.default.41 [ i64 0, label %tco.case.arm.0.42 i64 1, label %tco.case.arm.1.49 ]
tco.case.arm.0.42:
  %t43 = getelementptr ptr, ptr %t6, i32 1
  %t44 = load ptr, ptr %t43
  %t45 = call ptr @malloc(i64 16)
  %t46 = inttoptr i64 0 to ptr
  %t47 = getelementptr ptr, ptr %t45, i32 0
  store ptr %t46, ptr %t47
  %t48 = getelementptr ptr, ptr %t45, i32 1
  store ptr %t44, ptr %t48
  store ptr %t37, ptr %t3
  store ptr %t45, ptr %t4
  br label %tco.loop.0
tco.case.arm.1.49:
  %t50 = getelementptr ptr, ptr %t6, i32 1
  %t51 = load ptr, ptr %t50
  %t52 = call ptr @malloc(i64 16)
  %t53 = inttoptr i64 1 to ptr
  %t54 = getelementptr ptr, ptr %t52, i32 0
  store ptr %t53, ptr %t54
  %t55 = getelementptr [2 x i8], ptr @.str.3, i64 0, i64 0
  %t56 = call ptr @__concat(ptr %t55, ptr %t51)
  %t57 = getelementptr ptr, ptr %t52, i32 1
  store ptr %t56, ptr %t57
  store ptr %t37, ptr %t3
  store ptr %t52, ptr %t4
  br label %tco.loop.0
tco.case.default.41:
  unreachable
tco.case.arm.3.58:
  %t59 = getelementptr ptr, ptr %t5, i32 1
  %t60 = load ptr, ptr %t59
  %t61 = getelementptr ptr, ptr %t6, i32 0
  %t62 = load ptr, ptr %t61
  %t63 = ptrtoint ptr %t62 to i64
  switch i64 %t63, label %tco.case.default.64 [ i64 0, label %tco.case.arm.0.65 i64 1, label %tco.case.arm.1.72 ]
tco.case.arm.0.65:
  %t66 = getelementptr ptr, ptr %t6, i32 1
  %t67 = load ptr, ptr %t66
  %t68 = call ptr @malloc(i64 16)
  %t69 = inttoptr i64 0 to ptr
  %t70 = getelementptr ptr, ptr %t68, i32 0
  store ptr %t69, ptr %t70
  %t71 = getelementptr ptr, ptr %t68, i32 1
  store ptr %t67, ptr %t71
  store ptr %t60, ptr %t3
  store ptr %t68, ptr %t4
  br label %tco.loop.0
tco.case.arm.1.72:
  %t73 = getelementptr ptr, ptr %t6, i32 1
  %t74 = load ptr, ptr %t73
  %t75 = call ptr @malloc(i64 16)
  %t76 = inttoptr i64 1 to ptr
  %t77 = getelementptr ptr, ptr %t75, i32 0
  store ptr %t76, ptr %t77
  %t78 = getelementptr [2 x i8], ptr @.str.4, i64 0, i64 0
  %t79 = call ptr @__concat(ptr %t78, ptr %t74)
  %t80 = getelementptr ptr, ptr %t75, i32 1
  store ptr %t79, ptr %t80
  store ptr %t60, ptr %t3
  store ptr %t75, ptr %t4
  br label %tco.loop.0
tco.case.default.64:
  unreachable
tco.case.default.10:
  unreachable
tco.exit.1:
  %t81 = load ptr, ptr %t2
  ret ptr %t81
}

define internal ptr @v_handleA(ptr %v_step) {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 0 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v_step, ptr %t3
  %t4 = call ptr @v__scc_handleA_handleB(ptr %t0)
  ret ptr %t4
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
