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
@.str.1 = private unnamed_addr constant [1 x i8] c"\00"
@.str.2 = private unnamed_addr constant [2 x i8] c"B\00"
@.str.3 = private unnamed_addr constant [2 x i8] c"C\00"

define ptr @__concat(ptr %a, ptr %b) {
  %la = call i64 @strlen(ptr %a)
  %lb = call i64 @strlen(ptr %b)
  %sum = add i64 %la, %lb
  %total = add i64 %sum, 1
  %buf = call ptr @malloc(i64 %total)
  call ptr @strcpy(ptr %buf, ptr %a)
  call ptr @strcat(ptr %buf, ptr %b)
  ret ptr %buf
}

define ptr @__print(ptr %s) {
  call i32 (ptr, ...) @printf(ptr @.fmt, ptr %s)
  ret ptr null
}

define ptr @__showInt32(ptr %p) {
  %v = load i32, ptr %p
  %buf = call ptr @malloc(i64 16)
  call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 16, ptr @.fmt_i32, i32 %v)
  ret ptr %buf
}

define ptr @__showUInt8(ptr %p) {
  %b = load i8, ptr %p
  %v = zext i8 %b to i32
  %buf = call ptr @malloc(i64 16)
  call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 16, ptr @.fmt_u8, i32 %v)
  ret ptr %buf
}

define ptr @v_handleA(ptr %v_step) {
  %t0 = getelementptr ptr, ptr %v_step, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.13 i64 2, label %case.arm.2.16 i64 3, label %case.arm.3.19 ]
case.arm.0.5:
  %t7 = getelementptr [2 x i8], ptr @.str.0, i64 0, i64 0
  %t8 = call ptr @malloc(i64 8)
  %t9 = inttoptr i64 1 to ptr
  %t10 = getelementptr ptr, ptr %t8, i32 0
  store ptr %t9, ptr %t10
  %t11 = call ptr @v_handleB(ptr %t8)
  %t12 = call ptr @__concat(ptr %t7, ptr %t11)
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.13:
  %t15 = call ptr @v_handleB(ptr %v_step)
  br label %case.end.1.14
case.end.1.14:
  br label %case.join.4
case.arm.2.16:
  %t18 = call ptr @v_handleB(ptr %v_step)
  br label %case.end.2.17
case.end.2.17:
  br label %case.join.4
case.arm.3.19:
  %t21 = getelementptr [1 x i8], ptr @.str.1, i64 0, i64 0
  br label %case.end.3.20
case.end.3.20:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t22 = phi ptr [%t12, %case.end.0.6], [%t15, %case.end.1.14], [%t18, %case.end.2.17], [%t21, %case.end.3.20]
  ret ptr %t22
}

define ptr @v_handleB(ptr %v_step) {
  %t0 = getelementptr ptr, ptr %v_step, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.8 i64 2, label %case.arm.2.16 i64 3, label %case.arm.3.24 ]
case.arm.0.5:
  %t7 = call ptr @v_handleA(ptr %v_step)
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.8:
  %t10 = getelementptr [2 x i8], ptr @.str.2, i64 0, i64 0
  %t11 = call ptr @malloc(i64 8)
  %t12 = inttoptr i64 2 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  %t14 = call ptr @v_handleA(ptr %t11)
  %t15 = call ptr @__concat(ptr %t10, ptr %t14)
  br label %case.end.1.9
case.end.1.9:
  br label %case.join.4
case.arm.2.16:
  %t18 = getelementptr [2 x i8], ptr @.str.3, i64 0, i64 0
  %t19 = call ptr @malloc(i64 8)
  %t20 = inttoptr i64 3 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = call ptr @v_handleA(ptr %t19)
  %t23 = call ptr @__concat(ptr %t18, ptr %t22)
  br label %case.end.2.17
case.end.2.17:
  br label %case.join.4
case.arm.3.24:
  %t26 = getelementptr [1 x i8], ptr @.str.1, i64 0, i64 0
  br label %case.end.3.25
case.end.3.25:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t27 = phi ptr [%t7, %case.end.0.6], [%t15, %case.end.1.9], [%t23, %case.end.2.17], [%t26, %case.end.3.25]
  ret ptr %t27
}

define ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 8)
  %t1 = inttoptr i64 0 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_handleA(ptr %t0)
  %t4 = call ptr @__print(ptr %t3)
  ret ptr %t4
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
  call ptr @v_main(ptr %input)
  ret i32 0
}
