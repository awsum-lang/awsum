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

@.str.0 = private unnamed_addr constant [6 x i8] c"Hello\00"
@.str.1 = private unnamed_addr constant [3 x i8] c", \00"
@.str.2 = private unnamed_addr constant [2 x i8] c"!\00"
@.str.3 = private unnamed_addr constant [25 x i8] c"UNPAIRED_UTF16_SURROGATE\00"
@.str.4 = private unnamed_addr constant [16 x i8] c"STRING_TOO_LONG\00"

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


define internal ptr @v_main(ptr %v_inputArg) {
  %t0 = getelementptr ptr, ptr %v_inputArg, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.13 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_inputArg, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = call ptr @malloc(i64 16)
  %t10 = inttoptr i64 0 to ptr
  %t11 = getelementptr ptr, ptr %t9, i32 0
  store ptr %t10, ptr %t11
  %t12 = getelementptr ptr, ptr %t9, i32 1
  store ptr %t8, ptr %t12
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.13:
  %t15 = getelementptr ptr, ptr %v_inputArg, i32 1
  %t16 = load ptr, ptr %t15
  %t17 = call ptr @v_addGreeting(ptr %t16)
  %t18 = call ptr @v__lift_1(ptr %t17)
  br label %case.end.1.14
case.end.1.14:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t19 = phi ptr [%t9, %case.end.0.6], [%t18, %case.end.1.14]
  %t20 = call ptr @v__let_2(ptr %t19)
  ret ptr %t20
}

define internal ptr @v_greeting() {
  %t0 = getelementptr [6 x i8], ptr @.str.0, i64 0, i64 0
  ret ptr %t0
}

define internal ptr @v_addGreeting(ptr %v_name) {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_greeting()
  %t4 = getelementptr [3 x i8], ptr @.str.1, i64 0, i64 0
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
  %t27 = call ptr @__concat(ptr %t23, ptr %v_name)
  %t28 = getelementptr ptr, ptr %t24, i32 1
  store ptr %t27, ptr %t28
  %t29 = getelementptr ptr, ptr %t24, i32 0
  %t30 = load ptr, ptr %t29
  %t31 = ptrtoint ptr %t30 to i64
  switch i64 %t31, label %case.default.32 [ i64 0, label %case.arm.0.34 i64 1, label %case.arm.1.42 ]
case.arm.0.34:
  %t36 = getelementptr ptr, ptr %t24, i32 1
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
  %t44 = getelementptr ptr, ptr %t24, i32 1
  %t45 = load ptr, ptr %t44
  %t46 = call ptr @malloc(i64 16)
  %t47 = inttoptr i64 1 to ptr
  %t48 = getelementptr ptr, ptr %t46, i32 0
  store ptr %t47, ptr %t48
  %t49 = getelementptr [2 x i8], ptr @.str.2, i64 0, i64 0
  %t50 = call ptr @__concat(ptr %t45, ptr %t49)
  %t51 = getelementptr ptr, ptr %t46, i32 1
  store ptr %t50, ptr %t51
  br label %case.end.1.43
case.end.1.43:
  br label %case.join.33
case.default.32:
  unreachable
case.join.33:
  %t52 = phi ptr [%t38, %case.end.0.35], [%t46, %case.end.1.43]
  br label %case.end.1.21
case.end.1.21:
  br label %case.join.11
case.default.10:
  unreachable
case.join.11:
  %t53 = phi ptr [%t16, %case.end.0.13], [%t52, %case.end.1.21]
  ret ptr %t53
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
  %t13 = inttoptr i64 589989748 to ptr
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
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.27 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_res, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr ptr, ptr %t8, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %case.default.12 [ i64 502975519, label %case.arm.502975519.14 i64 589989748, label %case.arm.589989748.20 ]
case.arm.502975519.14:
  %t16 = getelementptr ptr, ptr %t8, i32 1
  %t17 = load ptr, ptr %t16
  %t18 = getelementptr [25 x i8], ptr @.str.3, i64 0, i64 0
  %t19 = call ptr @__print(ptr %t18)
  br label %case.end.502975519.15
case.end.502975519.15:
  br label %case.join.13
case.arm.589989748.20:
  %t22 = getelementptr ptr, ptr %t8, i32 1
  %t23 = load ptr, ptr %t22
  %t24 = getelementptr [16 x i8], ptr @.str.4, i64 0, i64 0
  %t25 = call ptr @__print(ptr %t24)
  br label %case.end.589989748.21
case.end.589989748.21:
  br label %case.join.13
case.default.12:
  unreachable
case.join.13:
  %t26 = phi ptr [%t19, %case.end.502975519.15], [%t25, %case.end.589989748.21]
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.27:
  %t29 = getelementptr ptr, ptr %v_res, i32 1
  %t30 = load ptr, ptr %t29
  %t31 = call ptr @__print(ptr %t30)
  br label %case.end.1.28
case.end.1.28:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t32 = phi ptr [%t26, %case.end.0.6], [%t31, %case.end.1.28]
  ret ptr %t32
}

define i32 @main(i32 %argc, ptr %argv) {
  %has_arg = icmp sgt i32 %argc, 1
  br i1 %has_arg, label %with_arg, label %no_arg
with_arg:
  %argptr = getelementptr ptr, ptr %argv, i64 1
  %arg = load ptr, ptr %argptr
  br label %call_main
no_arg:
  br label %call_main
call_main:
  %input = phi ptr [%arg, %with_arg], [@.empty, %no_arg]
  %right_box = call ptr @malloc(i64 16)
  %right_tag_ptr = getelementptr ptr, ptr %right_box, i32 0
  %right_tag = inttoptr i64 1 to ptr
  store ptr %right_tag, ptr %right_tag_ptr
  %right_payload_ptr = getelementptr ptr, ptr %right_box, i32 1
  store ptr %input, ptr %right_payload_ptr
  call ptr @v_main(ptr %right_box)
  ret i32 0
}
