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

@.str.0 = private unnamed_addr constant [2 x i8] c"[\00"
@.str.1 = private unnamed_addr constant [2 x i8] c"]\00"
@.str.2 = private unnamed_addr constant [3 x i8] c"hi\00"
@.str.3 = private unnamed_addr constant [2 x i8] c"<\00"
@.str.4 = private unnamed_addr constant [2 x i8] c">\00"
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
  ret ptr null
}


define internal ptr @v_pad(ptr %v_s) {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr [2 x i8], ptr @.str.0, i64 0, i64 0
  %t4 = call ptr @__concat(ptr %t3, ptr %v_s)
  %t5 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 0
  %t7 = load ptr, ptr %t6
  %t8 = ptrtoint ptr %t7 to i64
  switch i64 %t8, label %case.default.9 [ i64 0, label %case.arm.0.11 i64 1, label %case.arm.1.19 ]
case.arm.0.11:
  %t13 = getelementptr ptr, ptr %t0, i32 1
  %t14 = load ptr, ptr %t13
  %t15 = call ptr @malloc(i64 16)
  %t16 = inttoptr i64 0 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = getelementptr ptr, ptr %t15, i32 1
  store ptr %t14, ptr %t18
  br label %case.end.0.12
case.end.0.12:
  br label %case.join.10
case.arm.1.19:
  %t21 = getelementptr ptr, ptr %t0, i32 1
  %t22 = load ptr, ptr %t21
  %t23 = call ptr @malloc(i64 16)
  %t24 = inttoptr i64 1 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  %t26 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  %t27 = call ptr @__concat(ptr %t22, ptr %t26)
  %t28 = getelementptr ptr, ptr %t23, i32 1
  store ptr %t27, ptr %t28
  %t29 = getelementptr ptr, ptr %t23, i32 0
  %t30 = load ptr, ptr %t29
  %t31 = ptrtoint ptr %t30 to i64
  switch i64 %t31, label %case.default.32 [ i64 0, label %case.arm.0.34 i64 1, label %case.arm.1.42 ]
case.arm.0.34:
  %t36 = getelementptr ptr, ptr %t23, i32 1
  %t37 = load ptr, ptr %t36
  %t38 = call ptr @malloc(i64 16)
  %t39 = inttoptr i64 0 to ptr
  %t40 = getelementptr ptr, ptr %t38, i32 0
  store ptr %t39, ptr %t40
  %t41 = getelementptr ptr, ptr %t38, i32 1
  store ptr %t37, ptr %t41
  br label %case.end.0.35
case.end.0.35:
  br label %case.join.33
case.arm.1.42:
  %t44 = getelementptr ptr, ptr %t23, i32 1
  %t45 = load ptr, ptr %t44
  %t46 = call ptr @malloc(i64 16)
  %t47 = inttoptr i64 1 to ptr
  %t48 = getelementptr ptr, ptr %t46, i32 0
  store ptr %t47, ptr %t48
  %t49 = call ptr @__concat(ptr %t45, ptr %t45)
  %t50 = getelementptr ptr, ptr %t46, i32 1
  store ptr %t49, ptr %t50
  br label %case.end.1.43
case.end.1.43:
  br label %case.join.33
case.default.32:
  unreachable
case.join.33:
  %t51 = phi ptr [%t38, %case.end.0.35], [%t46, %case.end.1.43]
  br label %case.end.1.20
case.end.1.20:
  br label %case.join.10
case.default.9:
  unreachable
case.join.10:
  %t52 = phi ptr [%t15, %case.end.0.12], [%t51, %case.end.1.20]
  ret ptr %t52
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = getelementptr [3 x i8], ptr @.str.2, i64 0, i64 0
  %t1 = call ptr @v_pad(ptr %t0)
  %t2 = getelementptr ptr, ptr %t1, i32 0
  %t3 = load ptr, ptr %t2
  %t4 = ptrtoint ptr %t3 to i64
  switch i64 %t4, label %case.default.5 [ i64 0, label %case.arm.0.7 i64 1, label %case.arm.1.15 ]
case.arm.0.7:
  %t9 = getelementptr ptr, ptr %t1, i32 1
  %t10 = load ptr, ptr %t9
  %t11 = call ptr @malloc(i64 16)
  %t12 = inttoptr i64 0 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  %t14 = getelementptr ptr, ptr %t11, i32 1
  store ptr %t10, ptr %t14
  br label %case.end.0.8
case.end.0.8:
  br label %case.join.6
case.arm.1.15:
  %t17 = getelementptr ptr, ptr %t1, i32 1
  %t18 = load ptr, ptr %t17
  %t19 = call ptr @malloc(i64 16)
  %t20 = inttoptr i64 1 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr [2 x i8], ptr @.str.3, i64 0, i64 0
  %t23 = call ptr @__concat(ptr %t22, ptr %t18)
  %t24 = getelementptr ptr, ptr %t19, i32 1
  store ptr %t23, ptr %t24
  %t25 = getelementptr ptr, ptr %t19, i32 0
  %t26 = load ptr, ptr %t25
  %t27 = ptrtoint ptr %t26 to i64
  switch i64 %t27, label %case.default.28 [ i64 0, label %case.arm.0.30 i64 1, label %case.arm.1.38 ]
case.arm.0.30:
  %t32 = getelementptr ptr, ptr %t19, i32 1
  %t33 = load ptr, ptr %t32
  %t34 = call ptr @malloc(i64 16)
  %t35 = inttoptr i64 0 to ptr
  %t36 = getelementptr ptr, ptr %t34, i32 0
  store ptr %t35, ptr %t36
  %t37 = getelementptr ptr, ptr %t34, i32 1
  store ptr %t33, ptr %t37
  br label %case.end.0.31
case.end.0.31:
  br label %case.join.29
case.arm.1.38:
  %t40 = getelementptr ptr, ptr %t19, i32 1
  %t41 = load ptr, ptr %t40
  %t42 = call ptr @malloc(i64 16)
  %t43 = inttoptr i64 1 to ptr
  %t44 = getelementptr ptr, ptr %t42, i32 0
  store ptr %t43, ptr %t44
  %t45 = getelementptr [2 x i8], ptr @.str.4, i64 0, i64 0
  %t46 = call ptr @__concat(ptr %t41, ptr %t45)
  %t47 = getelementptr ptr, ptr %t42, i32 1
  store ptr %t46, ptr %t47
  br label %case.end.1.39
case.end.1.39:
  br label %case.join.29
case.default.28:
  unreachable
case.join.29:
  %t48 = phi ptr [%t34, %case.end.0.31], [%t42, %case.end.1.39]
  br label %case.end.1.16
case.end.1.16:
  br label %case.join.6
case.default.5:
  unreachable
case.join.6:
  %t49 = phi ptr [%t11, %case.end.0.8], [%t48, %case.end.1.16]
  %t50 = call ptr @v__let_1(ptr %t49)
  ret ptr %t50
}

define internal ptr @v__let_1(ptr %v_res) {
  %t0 = getelementptr ptr, ptr %v_res, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.11 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_res, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr [16 x i8], ptr @.str.5, i64 0, i64 0
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
