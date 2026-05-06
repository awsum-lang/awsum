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

@.str.0 = private unnamed_addr constant [6 x i8] c"ERR_A\00"
@.str.1 = private unnamed_addr constant [6 x i8] c"ERR_B\00"
@.str.2 = private unnamed_addr constant [12 x i8] c"PARSE_ERROR\00"

define internal ptr @__print(ptr %s) {
  call i32 (ptr, ...) @printf(ptr @.fmt, ptr %s)
  %unit = call ptr @malloc(i64 8)
  %unit_tag_ptr = getelementptr ptr, ptr %unit, i32 0
  %unit_tag = inttoptr i64 0 to ptr
  store ptr %unit_tag, ptr %unit_tag_ptr
  ret ptr %unit
}


define internal ptr @__showInt32(ptr %p) {
  %v = load i32, ptr %p
  %buf = call ptr @malloc(i64 16)
  call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 16, ptr @.fmt_i32, i32 %v)
  ret ptr %buf
}


define internal ptr @v_pureEither(ptr %v_x) {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v_x, ptr %t3
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

define internal ptr @v_opA() {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @malloc(i64 4)
  store i32 1, ptr %t3
  %t4 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t4
  ret ptr %t0
}

define internal ptr @v_opB() {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @malloc(i64 4)
  store i32 2, ptr %t3
  %t4 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t4
  ret ptr %t0
}

define internal ptr @v_main(ptr %v__wild0) {
  %t0 = call ptr @v_opA()
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 0, label %case.arm.0.6 i64 1, label %case.arm.1.18 ]
case.arm.0.6:
  %t8 = getelementptr ptr, ptr %t0, i32 1
  %t9 = load ptr, ptr %t8
  %t10 = call ptr @malloc(i64 16)
  %t11 = inttoptr i64 0 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  %t13 = call ptr @malloc(i64 16)
  %t14 = inttoptr i64 2252990199 to ptr
  %t15 = getelementptr ptr, ptr %t13, i32 0
  store ptr %t14, ptr %t15
  %t16 = getelementptr ptr, ptr %t13, i32 1
  store ptr %t9, ptr %t16
  %t17 = getelementptr ptr, ptr %t10, i32 1
  store ptr %t13, ptr %t17
  br label %case.end.0.7
case.end.0.7:
  br label %case.join.5
case.arm.1.18:
  %t20 = getelementptr ptr, ptr %t0, i32 1
  %t21 = load ptr, ptr %t20
  %t22 = call ptr @v_opB()
  %t23 = getelementptr ptr, ptr %t22, i32 0
  %t24 = load ptr, ptr %t23
  %t25 = ptrtoint ptr %t24 to i64
  switch i64 %t25, label %case.default.26 [ i64 0, label %case.arm.0.28 i64 1, label %case.arm.1.40 ]
case.arm.0.28:
  %t30 = getelementptr ptr, ptr %t22, i32 1
  %t31 = load ptr, ptr %t30
  %t32 = call ptr @malloc(i64 16)
  %t33 = inttoptr i64 0 to ptr
  %t34 = getelementptr ptr, ptr %t32, i32 0
  store ptr %t33, ptr %t34
  %t35 = call ptr @malloc(i64 16)
  %t36 = inttoptr i64 2269767818 to ptr
  %t37 = getelementptr ptr, ptr %t35, i32 0
  store ptr %t36, ptr %t37
  %t38 = getelementptr ptr, ptr %t35, i32 1
  store ptr %t31, ptr %t38
  %t39 = getelementptr ptr, ptr %t32, i32 1
  store ptr %t35, ptr %t39
  br label %case.end.0.29
case.end.0.29:
  br label %case.join.27
case.arm.1.40:
  %t42 = getelementptr ptr, ptr %t22, i32 1
  %t43 = load ptr, ptr %t42
  %t44 = call ptr @v_pureEither(ptr %t43)
  br label %case.end.1.41
case.end.1.41:
  br label %case.join.27
case.default.26:
  unreachable
case.join.27:
  %t45 = phi ptr [%t32, %case.end.0.29], [%t44, %case.end.1.41]
  br label %case.end.1.19
case.end.1.19:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t46 = phi ptr [%t10, %case.end.0.7], [%t45, %case.end.1.19]
  %t47 = call ptr @v__let_2(ptr %t46)
  ret ptr %t47
}

define internal ptr @v__let_2(ptr %v_res) {
  %t0 = getelementptr ptr, ptr %v_res, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.66 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_res, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr ptr, ptr %t8, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %case.default.12 [ i64 2252990199, label %case.arm.2252990199.14 i64 2269767818, label %case.arm.2269767818.31 i64 2448244154, label %case.arm.2448244154.48 ]
case.arm.2252990199.14:
  %t16 = getelementptr ptr, ptr %t8, i32 1
  %t17 = load ptr, ptr %t16
  %t18 = call ptr @malloc(i64 24)
  %t19 = inttoptr i64 2 to ptr
  %t20 = getelementptr ptr, ptr %t18, i32 0
  store ptr %t19, ptr %t20
  %t21 = getelementptr [6 x i8], ptr @.str.0, i64 0, i64 0
  %t22 = getelementptr ptr, ptr %t18, i32 1
  store ptr %t21, ptr %t22
  %t23 = call ptr @malloc(i64 16)
  %t24 = inttoptr i64 0 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  %t26 = call ptr @malloc(i64 8)
  %t27 = inttoptr i64 0 to ptr
  %t28 = getelementptr ptr, ptr %t26, i32 0
  store ptr %t27, ptr %t28
  %t29 = getelementptr ptr, ptr %t23, i32 1
  store ptr %t26, ptr %t29
  %t30 = getelementptr ptr, ptr %t18, i32 2
  store ptr %t23, ptr %t30
  br label %case.end.2252990199.15
case.end.2252990199.15:
  br label %case.join.13
case.arm.2269767818.31:
  %t33 = getelementptr ptr, ptr %t8, i32 1
  %t34 = load ptr, ptr %t33
  %t35 = call ptr @malloc(i64 24)
  %t36 = inttoptr i64 2 to ptr
  %t37 = getelementptr ptr, ptr %t35, i32 0
  store ptr %t36, ptr %t37
  %t38 = getelementptr [6 x i8], ptr @.str.1, i64 0, i64 0
  %t39 = getelementptr ptr, ptr %t35, i32 1
  store ptr %t38, ptr %t39
  %t40 = call ptr @malloc(i64 16)
  %t41 = inttoptr i64 0 to ptr
  %t42 = getelementptr ptr, ptr %t40, i32 0
  store ptr %t41, ptr %t42
  %t43 = call ptr @malloc(i64 8)
  %t44 = inttoptr i64 0 to ptr
  %t45 = getelementptr ptr, ptr %t43, i32 0
  store ptr %t44, ptr %t45
  %t46 = getelementptr ptr, ptr %t40, i32 1
  store ptr %t43, ptr %t46
  %t47 = getelementptr ptr, ptr %t35, i32 2
  store ptr %t40, ptr %t47
  br label %case.end.2269767818.32
case.end.2269767818.32:
  br label %case.join.13
case.arm.2448244154.48:
  %t50 = getelementptr ptr, ptr %t8, i32 1
  %t51 = load ptr, ptr %t50
  %t52 = call ptr @malloc(i64 24)
  %t53 = inttoptr i64 2 to ptr
  %t54 = getelementptr ptr, ptr %t52, i32 0
  store ptr %t53, ptr %t54
  %t55 = getelementptr [12 x i8], ptr @.str.2, i64 0, i64 0
  %t56 = getelementptr ptr, ptr %t52, i32 1
  store ptr %t55, ptr %t56
  %t57 = call ptr @malloc(i64 16)
  %t58 = inttoptr i64 0 to ptr
  %t59 = getelementptr ptr, ptr %t57, i32 0
  store ptr %t58, ptr %t59
  %t60 = call ptr @malloc(i64 8)
  %t61 = inttoptr i64 0 to ptr
  %t62 = getelementptr ptr, ptr %t60, i32 0
  store ptr %t61, ptr %t62
  %t63 = getelementptr ptr, ptr %t57, i32 1
  store ptr %t60, ptr %t63
  %t64 = getelementptr ptr, ptr %t52, i32 2
  store ptr %t57, ptr %t64
  br label %case.end.2448244154.49
case.end.2448244154.49:
  br label %case.join.13
case.default.12:
  unreachable
case.join.13:
  %t65 = phi ptr [%t18, %case.end.2252990199.15], [%t35, %case.end.2269767818.32], [%t52, %case.end.2448244154.49]
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.66:
  %t68 = getelementptr ptr, ptr %v_res, i32 1
  %t69 = load ptr, ptr %t68
  %t70 = call ptr @malloc(i64 24)
  %t71 = inttoptr i64 2 to ptr
  %t72 = getelementptr ptr, ptr %t70, i32 0
  store ptr %t71, ptr %t72
  %t73 = call ptr @__showInt32(ptr %t69)
  %t74 = getelementptr ptr, ptr %t70, i32 1
  store ptr %t73, ptr %t74
  %t75 = call ptr @malloc(i64 16)
  %t76 = inttoptr i64 0 to ptr
  %t77 = getelementptr ptr, ptr %t75, i32 0
  store ptr %t76, ptr %t77
  %t78 = call ptr @malloc(i64 8)
  %t79 = inttoptr i64 0 to ptr
  %t80 = getelementptr ptr, ptr %t78, i32 0
  store ptr %t79, ptr %t80
  %t81 = getelementptr ptr, ptr %t75, i32 1
  store ptr %t78, ptr %t81
  %t82 = getelementptr ptr, ptr %t70, i32 2
  store ptr %t75, ptr %t82
  br label %case.end.1.67
case.end.1.67:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t83 = phi ptr [%t65, %case.end.0.6], [%t70, %case.end.1.67]
  ret ptr %t83
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
