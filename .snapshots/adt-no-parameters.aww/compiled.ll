; External C declarations
declare ptr @malloc(i64)
declare ptr @strcpy(ptr, ptr)
declare ptr @strcat(ptr, ptr)
declare i64 @strlen(ptr)
declare i32 @printf(ptr, ...)

@.fmt = private unnamed_addr constant [3 x i8] c"%s\00"
@.empty = private unnamed_addr constant [1 x i8] c"\00"

@.str.0 = private unnamed_addr constant [4 x i8] c"Red\00"
@.str.1 = private unnamed_addr constant [6 x i8] c"Green\00"
@.str.2 = private unnamed_addr constant [5 x i8] c"Blue\00"
@.str.3 = private unnamed_addr constant [3 x i8] c", \00"

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

define ptr @v_show(ptr %v_c) {
  %t0 = getelementptr ptr, ptr %v_c, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.7 i64 2, label %case.arm.2.9 ]
case.arm.0.5:
  %t6 = getelementptr [4 x i8], ptr @.str.0, i64 0, i64 0
  br label %case.join.4
case.arm.1.7:
  %t8 = getelementptr [6 x i8], ptr @.str.1, i64 0, i64 0
  br label %case.join.4
case.arm.2.9:
  %t10 = getelementptr [5 x i8], ptr @.str.2, i64 0, i64 0
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t11 = phi ptr [%t6, %case.arm.0.5], [%t8, %case.arm.1.7], [%t10, %case.arm.2.9]
  ret ptr %t11
}

define ptr @v_main(ptr %v_input) {
  %t0 = call ptr @malloc(i64 8)
  %t1 = inttoptr i64 0 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_show(ptr %t0)
  %t4 = getelementptr [3 x i8], ptr @.str.3, i64 0, i64 0
  %t5 = call ptr @__concat(ptr %t3, ptr %t4)
  %t6 = call ptr @malloc(i64 8)
  %t7 = inttoptr i64 1 to ptr
  %t8 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t7, ptr %t8
  %t9 = call ptr @v_show(ptr %t6)
  %t10 = call ptr @__concat(ptr %t5, ptr %t9)
  %t11 = getelementptr [3 x i8], ptr @.str.3, i64 0, i64 0
  %t12 = call ptr @__concat(ptr %t10, ptr %t11)
  %t13 = call ptr @malloc(i64 8)
  %t14 = inttoptr i64 2 to ptr
  %t15 = getelementptr ptr, ptr %t13, i32 0
  store ptr %t14, ptr %t15
  %t16 = call ptr @v_show(ptr %t13)
  %t17 = call ptr @__concat(ptr %t12, ptr %t16)
  %t18 = call ptr @__print(ptr %t17)
  ret ptr %t18
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
