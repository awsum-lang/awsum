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
  %t0 = ptrtoint ptr %v_c to i64
  switch i64 %t0, label %case.default.1 [ i64 0, label %case.arm.0.3 i64 1, label %case.arm.1.5 i64 2, label %case.arm.2.7 ]
case.arm.0.3:
  %t4 = getelementptr [4 x i8], ptr @.str.0, i64 0, i64 0
  br label %case.join.2
case.arm.1.5:
  %t6 = getelementptr [6 x i8], ptr @.str.1, i64 0, i64 0
  br label %case.join.2
case.arm.2.7:
  %t8 = getelementptr [5 x i8], ptr @.str.2, i64 0, i64 0
  br label %case.join.2
case.default.1:
  unreachable
case.join.2:
  %t9 = phi ptr [%t4, %case.arm.0.3], [%t6, %case.arm.1.5], [%t8, %case.arm.2.7]
  ret ptr %t9
}

define ptr @v_main(ptr %v_input) {
  %t0 = inttoptr i64 0 to ptr
  %t1 = call ptr @v_show(ptr %t0)
  %t2 = getelementptr [3 x i8], ptr @.str.3, i64 0, i64 0
  %t3 = call ptr @__concat(ptr %t1, ptr %t2)
  %t4 = inttoptr i64 1 to ptr
  %t5 = call ptr @v_show(ptr %t4)
  %t6 = call ptr @__concat(ptr %t3, ptr %t5)
  %t7 = getelementptr [3 x i8], ptr @.str.3, i64 0, i64 0
  %t8 = call ptr @__concat(ptr %t6, ptr %t7)
  %t9 = inttoptr i64 2 to ptr
  %t10 = call ptr @v_show(ptr %t9)
  %t11 = call ptr @__concat(ptr %t8, ptr %t10)
  %t12 = call ptr @__print(ptr %t11)
  ret ptr %t12
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
