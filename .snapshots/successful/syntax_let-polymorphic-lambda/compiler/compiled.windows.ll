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

@.str.0 = private unnamed_addr constant [2 x i8] c"A\00"
@.str.1 = private unnamed_addr constant [2 x i8] c"B\00"
@.str.2 = private unnamed_addr constant [2 x i8] c"C\00"
@.str.3 = private unnamed_addr constant [6 x i8] c"hello\00"
@.str.4 = private unnamed_addr constant [16 x i8] c"STRING_TOO_LONG\00"
@.str.5 = private unnamed_addr constant [2 x i8] c"/\00"

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


define internal ptr @__showInt32(ptr %p) {
  %v = load i32, ptr %p
  %buf = call ptr @malloc(i64 16)
  call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 16, ptr @.fmt_i32, i32 %v)
  ret ptr %buf
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

define internal ptr @v_showTri(ptr %v_t) {
  %t0 = getelementptr ptr, ptr %v_t, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.8 i64 2, label %case.arm.2.11 ]
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
case.arm.2.11:
  %t13 = getelementptr [2 x i8], ptr @.str.2, i64 0, i64 0
  br label %case.end.2.12
case.end.2.12:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t14 = phi ptr [%t7, %case.end.0.6], [%t10, %case.end.1.9], [%t13, %case.end.2.12]
  ret ptr %t14
}

define internal ptr @v_threeTypes(ptr %v_n, ptr %v_s, ptr %v_b) {
  %t0 = call ptr @v__df__let_3_0(ptr %v_b, ptr %v_n, ptr %v_s)
  ret ptr %t0
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 4)
  store i32 42, ptr %t0
  %t1 = getelementptr [6 x i8], ptr @.str.3, i64 0, i64 0
  %t2 = call ptr @malloc(i64 8)
  %t3 = inttoptr i64 0 to ptr
  %t4 = getelementptr ptr, ptr %t2, i32 0
  store ptr %t3, ptr %t4
  %t5 = call ptr @v_threeTypes(ptr %t0, ptr %t1, ptr %t2)
  %t6 = call ptr @v__let_4(ptr %t5)
  ret ptr %t6
}

define internal ptr @v__lam_2(ptr %v_x) {
  ret ptr %v_x
}

define internal ptr @v__let_4(ptr %v_res) {
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
  %t12 = getelementptr [16 x i8], ptr @.str.4, i64 0, i64 0
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

define internal ptr @v__df__let_3_0(ptr %v_b, ptr %v_n, ptr %v_s) {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__lam_2(ptr %v_n)
  %t4 = call ptr @__showInt32(ptr %t3)
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
  %t28 = call ptr @v__lam_2(ptr %v_s)
  %t29 = call ptr @__concat(ptr %t24, ptr %t28)
  %t30 = getelementptr ptr, ptr %t25, i32 1
  store ptr %t29, ptr %t30
  %t31 = getelementptr ptr, ptr %t25, i32 0
  %t32 = load ptr, ptr %t31
  %t33 = ptrtoint ptr %t32 to i64
  switch i64 %t33, label %case.default.34 [ i64 0, label %case.arm.0.36 i64 1, label %case.arm.1.44 ]
case.arm.0.36:
  %t38 = getelementptr ptr, ptr %t25, i32 1
  %t39 = load ptr, ptr %t38
  %t40 = call ptr @malloc(i64 16)
  %t41 = inttoptr i64 0 to ptr
  %t42 = getelementptr ptr, ptr %t40, i32 0
  store ptr %t41, ptr %t42
  %t43 = getelementptr ptr, ptr %t40, i32 1
  store ptr %t39, ptr %t43
  br label %case.end.0.37
case.end.0.37:
  br label %case.join.35
case.arm.1.44:
  %t46 = getelementptr ptr, ptr %t25, i32 1
  %t47 = load ptr, ptr %t46
  %t48 = call ptr @malloc(i64 16)
  %t49 = inttoptr i64 1 to ptr
  %t50 = getelementptr ptr, ptr %t48, i32 0
  store ptr %t49, ptr %t50
  %t51 = getelementptr [2 x i8], ptr @.str.5, i64 0, i64 0
  %t52 = call ptr @__concat(ptr %t47, ptr %t51)
  %t53 = getelementptr ptr, ptr %t48, i32 1
  store ptr %t52, ptr %t53
  %t54 = getelementptr ptr, ptr %t48, i32 0
  %t55 = load ptr, ptr %t54
  %t56 = ptrtoint ptr %t55 to i64
  switch i64 %t56, label %case.default.57 [ i64 0, label %case.arm.0.59 i64 1, label %case.arm.1.67 ]
case.arm.0.59:
  %t61 = getelementptr ptr, ptr %t48, i32 1
  %t62 = load ptr, ptr %t61
  %t63 = call ptr @malloc(i64 16)
  %t64 = inttoptr i64 0 to ptr
  %t65 = getelementptr ptr, ptr %t63, i32 0
  store ptr %t64, ptr %t65
  %t66 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t62, ptr %t66
  br label %case.end.0.60
case.end.0.60:
  br label %case.join.58
case.arm.1.67:
  %t69 = getelementptr ptr, ptr %t48, i32 1
  %t70 = load ptr, ptr %t69
  %t71 = call ptr @malloc(i64 16)
  %t72 = inttoptr i64 1 to ptr
  %t73 = getelementptr ptr, ptr %t71, i32 0
  store ptr %t72, ptr %t73
  %t74 = call ptr @v__lam_2(ptr %v_b)
  %t75 = call ptr @v_showTri(ptr %t74)
  %t76 = call ptr @__concat(ptr %t70, ptr %t75)
  %t77 = getelementptr ptr, ptr %t71, i32 1
  store ptr %t76, ptr %t77
  br label %case.end.1.68
case.end.1.68:
  br label %case.join.58
case.default.57:
  unreachable
case.join.58:
  %t78 = phi ptr [%t63, %case.end.0.60], [%t71, %case.end.1.68]
  br label %case.end.1.45
case.end.1.45:
  br label %case.join.35
case.default.34:
  unreachable
case.join.35:
  %t79 = phi ptr [%t40, %case.end.0.37], [%t78, %case.end.1.45]
  br label %case.end.1.22
case.end.1.22:
  br label %case.join.12
case.default.11:
  unreachable
case.join.12:
  %t80 = phi ptr [%t17, %case.end.0.14], [%t79, %case.end.1.22]
  ret ptr %t80
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
