; External C declarations
declare ptr @malloc(i64)
declare ptr @strcpy(ptr, ptr)
declare ptr @strcat(ptr, ptr)
declare i64 @strlen(ptr)
declare i32 @printf(ptr, ...)

@.fmt = private unnamed_addr constant [3 x i8] c"%s\00"
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

define ptr @v_greeting(ptr %v__wild0) {
  %t0 = getelementptr [3 x i8], ptr @.str.0, i64 0, i64 0
  ret ptr %t0
}

define ptr @v_unwrapBox(ptr %v_b) {
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

define ptr @v_unwrapBoxNamed(ptr %v_b) {
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

define ptr @v_showPair(ptr %v_p) {
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

define ptr @v_main(ptr %v__input) {
  %t0 = getelementptr [2 x i8], ptr @.str.4, i64 0, i64 0
  %t1 = call ptr @v_greeting(ptr %t0)
  %t2 = getelementptr [2 x i8], ptr @.str.5, i64 0, i64 0
  %t3 = call ptr @__concat(ptr %t1, ptr %t2)
  %t4 = call ptr @malloc(i64 16)
  %t5 = inttoptr i64 0 to ptr
  %t6 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5, ptr %t6
  %t7 = getelementptr [2 x i8], ptr @.str.6, i64 0, i64 0
  %t8 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t7, ptr %t8
  %t9 = call ptr @v_unwrapBox(ptr %t4)
  %t10 = call ptr @__concat(ptr %t3, ptr %t9)
  %t11 = getelementptr [2 x i8], ptr @.str.5, i64 0, i64 0
  %t12 = call ptr @__concat(ptr %t10, ptr %t11)
  %t13 = call ptr @malloc(i64 16)
  %t14 = inttoptr i64 0 to ptr
  %t15 = getelementptr ptr, ptr %t13, i32 0
  store ptr %t14, ptr %t15
  %t16 = getelementptr [2 x i8], ptr @.str.7, i64 0, i64 0
  %t17 = getelementptr ptr, ptr %t13, i32 1
  store ptr %t16, ptr %t17
  %t18 = call ptr @v_unwrapBoxNamed(ptr %t13)
  %t19 = call ptr @__concat(ptr %t12, ptr %t18)
  %t20 = getelementptr [2 x i8], ptr @.str.5, i64 0, i64 0
  %t21 = call ptr @__concat(ptr %t19, ptr %t20)
  %t22 = call ptr @malloc(i64 24)
  %t23 = inttoptr i64 0 to ptr
  %t24 = getelementptr ptr, ptr %t22, i32 0
  store ptr %t23, ptr %t24
  %t25 = getelementptr [2 x i8], ptr @.str.8, i64 0, i64 0
  %t26 = getelementptr ptr, ptr %t22, i32 1
  store ptr %t25, ptr %t26
  %t27 = getelementptr [2 x i8], ptr @.str.9, i64 0, i64 0
  %t28 = getelementptr ptr, ptr %t22, i32 2
  store ptr %t27, ptr %t28
  %t29 = call ptr @v_showPair(ptr %t22)
  %t30 = call ptr @__concat(ptr %t21, ptr %t29)
  %t31 = call ptr @__print(ptr %t30)
  ret ptr %t31
}

define ptr @v__con_Box(ptr %v__x0) {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 0 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v__x0, ptr %t3
  ret ptr %t0
}

define ptr @v__con_Pair(ptr %v__x0, ptr %v__x1) {
  %t0 = call ptr @malloc(i64 24)
  %t1 = inttoptr i64 0 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v__x0, ptr %t3
  %t4 = getelementptr ptr, ptr %t0, i32 2
  store ptr %v__x1, ptr %t4
  ret ptr %t0
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
