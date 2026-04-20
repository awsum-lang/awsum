; External C declarations
declare ptr @malloc(i64)
declare ptr @strcpy(ptr, ptr)
declare ptr @strcat(ptr, ptr)
declare i64 @strlen(ptr)
declare i32 @printf(ptr, ...)

@.fmt = private unnamed_addr constant [3 x i8] c"%s\00"
@.empty = private unnamed_addr constant [1 x i8] c"\00"

@.str.0 = private unnamed_addr constant [2 x i8] c",\00"
@.str.1 = private unnamed_addr constant [1 x i8] c"\00"
@.str.2 = private unnamed_addr constant [2 x i8] c"a\00"
@.str.3 = private unnamed_addr constant [2 x i8] c"b\00"
@.str.4 = private unnamed_addr constant [2 x i8] c"c\00"

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

define ptr @v_show(ptr %v_xs) {
  %t0 = getelementptr ptr, ptr %v_xs, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.15 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_xs, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr ptr, ptr %v_xs, i32 2
  %t10 = load ptr, ptr %t9
  %t11 = getelementptr [2 x i8], ptr @.str.0, i64 0, i64 0
  %t12 = call ptr @__concat(ptr %t8, ptr %t11)
  %t13 = call ptr @v_show(ptr %t10)
  %t14 = call ptr @__concat(ptr %t12, ptr %t13)
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.15:
  %t17 = getelementptr [1 x i8], ptr @.str.1, i64 0, i64 0
  br label %case.end.1.16
case.end.1.16:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t18 = phi ptr [%t14, %case.end.0.6], [%t17, %case.end.1.16]
  ret ptr %t18
}

define ptr @v_exampleList() {
  %t0 = call ptr @malloc(i64 24)
  %t1 = inttoptr i64 0 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr [2 x i8], ptr @.str.2, i64 0, i64 0
  %t4 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t4
  %t5 = call ptr @malloc(i64 24)
  %t6 = inttoptr i64 0 to ptr
  %t7 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t6, ptr %t7
  %t8 = getelementptr [2 x i8], ptr @.str.3, i64 0, i64 0
  %t9 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t8, ptr %t9
  %t10 = call ptr @malloc(i64 24)
  %t11 = inttoptr i64 0 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  %t13 = getelementptr [2 x i8], ptr @.str.4, i64 0, i64 0
  %t14 = getelementptr ptr, ptr %t10, i32 1
  store ptr %t13, ptr %t14
  %t15 = call ptr @malloc(i64 8)
  %t16 = inttoptr i64 1 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = getelementptr ptr, ptr %t10, i32 2
  store ptr %t15, ptr %t18
  %t19 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t10, ptr %t19
  %t20 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t5, ptr %t20
  ret ptr %t0
}

define ptr @v_main(ptr %v__input) {
  %t0 = call ptr @v_exampleList()
  %t1 = call ptr @v_show(ptr %t0)
  %t2 = call ptr @__print(ptr %t1)
  ret ptr %t2
}

define ptr @v__con_Cons(ptr %v__x0, ptr %v__x1) {
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
