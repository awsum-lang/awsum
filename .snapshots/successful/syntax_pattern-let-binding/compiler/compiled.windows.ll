; External C declarations
declare ptr @malloc(i64)
declare ptr @strcpy(ptr, ptr)
declare ptr @strcat(ptr, ptr)
declare i64 @strlen(ptr)
declare i32 @printf(ptr, ...)
declare i32 @snprintf(ptr, i64, ptr, ...)
declare {i32, i1} @llvm.smul.with.overflow.i32(i32, i32)

@.fmt = private unnamed_addr constant [3 x i8] c"%s\00"
@.fmt_i32 = private unnamed_addr constant [3 x i8] c"%d\00"
@.fmt_u8 = private unnamed_addr constant [3 x i8] c"%u\00"
@.empty = private unnamed_addr constant [1 x i8] c"\00"

@.str.0 = private unnamed_addr constant [2 x i8] c"[\00"
@.str.1 = private unnamed_addr constant [3 x i8] c", \00"
@.str.2 = private unnamed_addr constant [2 x i8] c"]\00"
@.str.3 = private unnamed_addr constant [16 x i8] c"STRING_TOO_LONG\00"

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


define internal ptr @__showInt32(ptr %p) {
  %v = load i32, ptr %p
  %buf = call ptr @malloc(i64 16)
  call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 16, ptr @.fmt_i32, i32 %v)
  ret ptr %buf
}


define internal ptr @__mulInt32(ptr %pa, ptr %pb) {
  %a = load i32, ptr %pa
  %b = load i32, ptr %pb
  %res = call {i32, i1} @llvm.smul.with.overflow.i32(i32 %a, i32 %b)
  %prod = extractvalue {i32, i1} %res, 0
  %ovf = extractvalue {i32, i1} %res, 1
  br i1 %ovf, label %err, label %ok
err:
  %xor_ab = xor i32 %a, %b
  %same_sign = icmp sge i32 %xor_ab, 0
  %row_tag_idx = select i1 %same_sign, i64 882564211, i64 3768445577
  %inner = call ptr @malloc(i64 8)
  %inner_tag = inttoptr i64 0 to ptr
  store ptr %inner_tag, ptr %inner
  %row = call ptr @malloc(i64 16)
  %row_tag = inttoptr i64 %row_tag_idx to ptr
  store ptr %row_tag, ptr %row
  %row_f = getelementptr ptr, ptr %row, i32 1
  store ptr %inner, ptr %row_f
  %left = call ptr @malloc(i64 16)
  %left_tag = inttoptr i64 0 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %row, ptr %left_f
  ret ptr %left
ok:
  %box = call ptr @malloc(i64 4)
  store i32 %prod, ptr %box
  %right = call ptr @malloc(i64 16)
  %right_tag = inttoptr i64 1 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %box, ptr %right_f
  ret ptr %right
}


define internal ptr @v_threeAndDouble(ptr %v_n) {
  %t0 = call ptr @malloc(i64 4)
  store i32 2, ptr %t0
  %t1 = call ptr @__mulInt32(ptr %v_n, ptr %t0)
  %t2 = getelementptr ptr, ptr %t1, i32 0
  %t3 = load ptr, ptr %t2
  %t4 = ptrtoint ptr %t3 to i64
  switch i64 %t4, label %case.default.5 [ i64 0, label %case.arm.0.7 i64 1, label %case.arm.1.16 ]
case.arm.0.7:
  %t9 = getelementptr ptr, ptr %t1, i32 1
  %t10 = load ptr, ptr %t9
  %t11 = call ptr @malloc(i64 24)
  %t12 = inttoptr i64 0 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  %t14 = getelementptr ptr, ptr %t11, i32 1
  store ptr %v_n, ptr %t14
  %t15 = getelementptr ptr, ptr %t11, i32 2
  store ptr %v_n, ptr %t15
  br label %case.end.0.8
case.end.0.8:
  br label %case.join.6
case.arm.1.16:
  %t18 = getelementptr ptr, ptr %t1, i32 1
  %t19 = load ptr, ptr %t18
  %t20 = call ptr @malloc(i64 24)
  %t21 = inttoptr i64 0 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = getelementptr ptr, ptr %t20, i32 1
  store ptr %v_n, ptr %t23
  %t24 = getelementptr ptr, ptr %t20, i32 2
  store ptr %t19, ptr %t24
  br label %case.end.1.17
case.end.1.17:
  br label %case.join.6
case.default.5:
  unreachable
case.join.6:
  %t25 = phi ptr [%t11, %case.end.0.8], [%t20, %case.end.1.17]
  ret ptr %t25
}

define internal ptr @v_show(ptr %v_pair) {
  %t0 = getelementptr ptr, ptr %v_pair, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_pair, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr ptr, ptr %v_pair, i32 2
  %t10 = load ptr, ptr %t9
  %t11 = call ptr @malloc(i64 16)
  %t12 = inttoptr i64 1 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  %t14 = getelementptr [2 x i8], ptr @.str.0, i64 0, i64 0
  %t15 = call ptr @__showInt32(ptr %t8)
  %t16 = call ptr @__concat(ptr %t14, ptr %t15)
  %t17 = getelementptr ptr, ptr %t11, i32 1
  store ptr %t16, ptr %t17
  %t18 = getelementptr ptr, ptr %t11, i32 0
  %t19 = load ptr, ptr %t18
  %t20 = ptrtoint ptr %t19 to i64
  switch i64 %t20, label %case.default.21 [ i64 0, label %case.arm.0.23 i64 1, label %case.arm.1.31 ]
case.arm.0.23:
  %t25 = getelementptr ptr, ptr %t11, i32 1
  %t26 = load ptr, ptr %t25
  %t27 = call ptr @malloc(i64 16)
  %t28 = inttoptr i64 0 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  %t30 = getelementptr ptr, ptr %t27, i32 1
  store ptr %t26, ptr %t30
  br label %case.end.0.24
case.end.0.24:
  br label %case.join.22
case.arm.1.31:
  %t33 = getelementptr ptr, ptr %t11, i32 1
  %t34 = load ptr, ptr %t33
  %t35 = call ptr @malloc(i64 16)
  %t36 = inttoptr i64 1 to ptr
  %t37 = getelementptr ptr, ptr %t35, i32 0
  store ptr %t36, ptr %t37
  %t38 = getelementptr [3 x i8], ptr @.str.1, i64 0, i64 0
  %t39 = call ptr @__concat(ptr %t34, ptr %t38)
  %t40 = getelementptr ptr, ptr %t35, i32 1
  store ptr %t39, ptr %t40
  %t41 = getelementptr ptr, ptr %t35, i32 0
  %t42 = load ptr, ptr %t41
  %t43 = ptrtoint ptr %t42 to i64
  switch i64 %t43, label %case.default.44 [ i64 0, label %case.arm.0.46 i64 1, label %case.arm.1.54 ]
case.arm.0.46:
  %t48 = getelementptr ptr, ptr %t35, i32 1
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
  %t56 = getelementptr ptr, ptr %t35, i32 1
  %t57 = load ptr, ptr %t56
  %t58 = call ptr @malloc(i64 16)
  %t59 = inttoptr i64 1 to ptr
  %t60 = getelementptr ptr, ptr %t58, i32 0
  store ptr %t59, ptr %t60
  %t61 = call ptr @__showInt32(ptr %t10)
  %t62 = call ptr @__concat(ptr %t57, ptr %t61)
  %t63 = getelementptr ptr, ptr %t58, i32 1
  store ptr %t62, ptr %t63
  %t64 = getelementptr ptr, ptr %t58, i32 0
  %t65 = load ptr, ptr %t64
  %t66 = ptrtoint ptr %t65 to i64
  switch i64 %t66, label %case.default.67 [ i64 0, label %case.arm.0.69 i64 1, label %case.arm.1.77 ]
case.arm.0.69:
  %t71 = getelementptr ptr, ptr %t58, i32 1
  %t72 = load ptr, ptr %t71
  %t73 = call ptr @malloc(i64 16)
  %t74 = inttoptr i64 0 to ptr
  %t75 = getelementptr ptr, ptr %t73, i32 0
  store ptr %t74, ptr %t75
  %t76 = getelementptr ptr, ptr %t73, i32 1
  store ptr %t72, ptr %t76
  br label %case.end.0.70
case.end.0.70:
  br label %case.join.68
case.arm.1.77:
  %t79 = getelementptr ptr, ptr %t58, i32 1
  %t80 = load ptr, ptr %t79
  %t81 = call ptr @malloc(i64 16)
  %t82 = inttoptr i64 1 to ptr
  %t83 = getelementptr ptr, ptr %t81, i32 0
  store ptr %t82, ptr %t83
  %t84 = getelementptr [2 x i8], ptr @.str.2, i64 0, i64 0
  %t85 = call ptr @__concat(ptr %t80, ptr %t84)
  %t86 = getelementptr ptr, ptr %t81, i32 1
  store ptr %t85, ptr %t86
  br label %case.end.1.78
case.end.1.78:
  br label %case.join.68
case.default.67:
  unreachable
case.join.68:
  %t87 = phi ptr [%t73, %case.end.0.70], [%t81, %case.end.1.78]
  br label %case.end.1.55
case.end.1.55:
  br label %case.join.45
case.default.44:
  unreachable
case.join.45:
  %t88 = phi ptr [%t50, %case.end.0.47], [%t87, %case.end.1.55]
  br label %case.end.1.32
case.end.1.32:
  br label %case.join.22
case.default.21:
  unreachable
case.join.22:
  %t89 = phi ptr [%t27, %case.end.0.24], [%t88, %case.end.1.32]
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t90 = phi ptr [%t89, %case.end.0.6]
  ret ptr %t90
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 4)
  store i32 5, ptr %t0
  %t1 = call ptr @v_threeAndDouble(ptr %t0)
  %t2 = call ptr @v_show(ptr %t1)
  %t3 = call ptr @v__let_1(ptr %t2)
  ret ptr %t3
}

define internal ptr @v__let_1(ptr %v_res) {
  %t0 = getelementptr ptr, ptr %v_res, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.11 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_res, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr [16 x i8], ptr @.str.3, i64 0, i64 0
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
