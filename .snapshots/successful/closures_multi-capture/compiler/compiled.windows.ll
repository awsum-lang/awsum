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

@.str.0 = private unnamed_addr constant [2 x i8] c"/\00"
@.str.1 = private unnamed_addr constant [16 x i8] c"STRING_TOO_LONG\00"

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


define internal ptr @v_zero() {
  %t0 = call ptr @malloc(i64 4)
  store i32 0, ptr %t0
  ret ptr %t0
}

define internal ptr @v_both(ptr %v_a, ptr %v_b) {
  %t0 = call ptr @v_zero()
  %t1 = call ptr @v__df_apply_0(ptr %t0, ptr %v_a, ptr %v_b)
  ret ptr %t1
}

define internal ptr @v_bothBody(ptr %v_a, ptr %v_b) {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__showInt32(ptr %v_a)
  %t4 = getelementptr [2 x i8], ptr @.str.0, i64 0, i64 0
  %t5 = call ptr @__concat(ptr %t3, ptr %t4)
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t5, ptr %t6
  %t7 = getelementptr ptr, ptr %t0, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %case.default.10 [ i64 0, label %case.arm.0.12 i64 1, label %case.arm.1.20 ]
case.arm.0.12:
  %t14 = getelementptr ptr, ptr %t0, i32 1
  %t15 = load ptr, ptr %t14
  %t16 = call ptr @malloc(i64 16)
  %t17 = inttoptr i64 0 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t15, ptr %t19
  br label %case.end.0.13
case.end.0.13:
  br label %case.join.11
case.arm.1.20:
  %t22 = getelementptr ptr, ptr %t0, i32 1
  %t23 = load ptr, ptr %t22
  %t24 = call ptr @malloc(i64 16)
  %t25 = inttoptr i64 1 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @__showInt32(ptr %v_b)
  %t28 = call ptr @__concat(ptr %t23, ptr %t27)
  %t29 = getelementptr ptr, ptr %t24, i32 1
  store ptr %t28, ptr %t29
  br label %case.end.1.21
case.end.1.21:
  br label %case.join.11
case.default.10:
  unreachable
case.join.11:
  %t30 = phi ptr [%t16, %case.end.0.13], [%t24, %case.end.1.21]
  ret ptr %t30
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 4)
  store i32 11, ptr %t0
  %t1 = call ptr @malloc(i64 4)
  store i32 22, ptr %t1
  %t2 = call ptr @v_both(ptr %t0, ptr %t1)
  %t3 = call ptr @v__let_2(ptr %t2)
  ret ptr %t3
}

define internal ptr @v__lam_1(ptr %v_a, ptr %v_b, ptr %v__n) {
  %t0 = call ptr @v_bothBody(ptr %v_a, ptr %v_b)
  ret ptr %t0
}

define internal ptr @v__let_2(ptr %v_res) {
  %t0 = getelementptr ptr, ptr %v_res, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.11 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_res, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr [16 x i8], ptr @.str.1, i64 0, i64 0
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

define internal ptr @v__df_apply_0(ptr %v_x, ptr %v__df_apply_0_cap0_0, ptr %v__df_apply_0_cap0_1) {
  %t0 = call ptr @v__lam_1(ptr %v__df_apply_0_cap0_0, ptr %v__df_apply_0_cap0_1, ptr %v_x)
  ret ptr %t0
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
