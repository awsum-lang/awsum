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

@.str.0 = private unnamed_addr constant [5 x i8] c"ErrA\00"
@.str.1 = private unnamed_addr constant [5 x i8] c"ErrB\00"
@.str.2 = private unnamed_addr constant [4 x i8] c"Ok \00"
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


define internal ptr @v_opA(ptr %v_n) {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v_n, ptr %t3
  ret ptr %t0
}

define internal ptr @v_opB(ptr %v__n) {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 0 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @malloc(i64 8)
  %t4 = inttoptr i64 0 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  ret ptr %t0
}

define internal ptr @v_run(ptr %v_x) {
  %t0 = call ptr @v_opA(ptr %v_x)
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
  %t22 = call ptr @v_opB(ptr %t21)
  %t23 = call ptr @v__lift_1(ptr %t22)
  br label %case.end.1.19
case.end.1.19:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t24 = phi ptr [%t10, %case.end.0.7], [%t23, %case.end.1.19]
  ret ptr %t24
}

define internal ptr @v_describe(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.33 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_r, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr ptr, ptr %t8, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %case.default.12 [ i64 2252990199, label %case.arm.2252990199.14 i64 2269767818, label %case.arm.2269767818.23 ]
case.arm.2252990199.14:
  %t16 = getelementptr ptr, ptr %t8, i32 1
  %t17 = load ptr, ptr %t16
  %t18 = call ptr @malloc(i64 16)
  %t19 = inttoptr i64 1 to ptr
  %t20 = getelementptr ptr, ptr %t18, i32 0
  store ptr %t19, ptr %t20
  %t21 = getelementptr [5 x i8], ptr @.str.0, i64 0, i64 0
  %t22 = getelementptr ptr, ptr %t18, i32 1
  store ptr %t21, ptr %t22
  br label %case.end.2252990199.15
case.end.2252990199.15:
  br label %case.join.13
case.arm.2269767818.23:
  %t25 = getelementptr ptr, ptr %t8, i32 1
  %t26 = load ptr, ptr %t25
  %t27 = call ptr @malloc(i64 16)
  %t28 = inttoptr i64 1 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  %t30 = getelementptr [5 x i8], ptr @.str.1, i64 0, i64 0
  %t31 = getelementptr ptr, ptr %t27, i32 1
  store ptr %t30, ptr %t31
  br label %case.end.2269767818.24
case.end.2269767818.24:
  br label %case.join.13
case.default.12:
  unreachable
case.join.13:
  %t32 = phi ptr [%t18, %case.end.2252990199.15], [%t27, %case.end.2269767818.24]
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.33:
  %t35 = getelementptr ptr, ptr %v_r, i32 1
  %t36 = load ptr, ptr %t35
  %t37 = call ptr @malloc(i64 16)
  %t38 = inttoptr i64 1 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = getelementptr [4 x i8], ptr @.str.2, i64 0, i64 0
  %t41 = call ptr @__showInt32(ptr %t36)
  %t42 = call ptr @__concat(ptr %t40, ptr %t41)
  %t43 = getelementptr ptr, ptr %t37, i32 1
  store ptr %t42, ptr %t43
  br label %case.end.1.34
case.end.1.34:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t44 = phi ptr [%t32, %case.end.0.6], [%t37, %case.end.1.34]
  ret ptr %t44
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 4)
  store i32 5, ptr %t0
  %t1 = call ptr @v_run(ptr %t0)
  %t2 = call ptr @v_describe(ptr %t1)
  %t3 = call ptr @v__let_2(ptr %t2)
  ret ptr %t3
}

define internal ptr @v__lift_1(ptr %v___input) {
  %t0 = getelementptr ptr, ptr %v___input, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.17 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v___input, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = call ptr @malloc(i64 16)
  %t10 = inttoptr i64 0 to ptr
  %t11 = getelementptr ptr, ptr %t9, i32 0
  store ptr %t10, ptr %t11
  %t12 = call ptr @malloc(i64 16)
  %t13 = inttoptr i64 2269767818 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t8, ptr %t15
  %t16 = getelementptr ptr, ptr %t9, i32 1
  store ptr %t12, ptr %t16
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.17:
  %t19 = getelementptr ptr, ptr %v___input, i32 1
  %t20 = load ptr, ptr %t19
  %t21 = call ptr @malloc(i64 16)
  %t22 = inttoptr i64 1 to ptr
  %t23 = getelementptr ptr, ptr %t21, i32 0
  store ptr %t22, ptr %t23
  %t24 = getelementptr ptr, ptr %t21, i32 1
  store ptr %t20, ptr %t24
  br label %case.end.1.18
case.end.1.18:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t25 = phi ptr [%t9, %case.end.0.6], [%t21, %case.end.1.18]
  ret ptr %t25
}

define internal ptr @v__let_2(ptr %v_res) {
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
