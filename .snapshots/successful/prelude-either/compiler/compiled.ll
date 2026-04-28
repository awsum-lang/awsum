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

@.str.0 = private unnamed_addr constant [7 x i8] c"left: \00"
@.str.1 = private unnamed_addr constant [8 x i8] c"right: \00"
@.str.2 = private unnamed_addr constant [4 x i8] c"bad\00"
@.str.3 = private unnamed_addr constant [3 x i8] c", \00"
@.str.4 = private unnamed_addr constant [5 x i8] c"good\00"

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


define internal ptr @v_unwrap(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.11 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_r, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr [7 x i8], ptr @.str.0, i64 0, i64 0
  %t10 = call ptr @__concat(ptr %t9, ptr %t8)
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.11:
  %t13 = getelementptr ptr, ptr %v_r, i32 1
  %t14 = load ptr, ptr %t13
  %t15 = getelementptr [8 x i8], ptr @.str.1, i64 0, i64 0
  %t16 = call ptr @__concat(ptr %t15, ptr %t14)
  br label %case.end.1.12
case.end.1.12:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t17 = phi ptr [%t10, %case.end.0.6], [%t16, %case.end.1.12]
  ret ptr %t17
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 0 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr [4 x i8], ptr @.str.2, i64 0, i64 0
  %t4 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t4
  %t5 = call ptr @v_unwrap(ptr %t0)
  %t6 = getelementptr [3 x i8], ptr @.str.3, i64 0, i64 0
  %t7 = call ptr @__concat(ptr %t5, ptr %t6)
  %t8 = call ptr @malloc(i64 16)
  %t9 = inttoptr i64 1 to ptr
  %t10 = getelementptr ptr, ptr %t8, i32 0
  store ptr %t9, ptr %t10
  %t11 = getelementptr [5 x i8], ptr @.str.4, i64 0, i64 0
  %t12 = getelementptr ptr, ptr %t8, i32 1
  store ptr %t11, ptr %t12
  %t13 = call ptr @v_unwrap(ptr %t8)
  %t14 = call ptr @__concat(ptr %t7, ptr %t13)
  %t15 = call ptr @__print(ptr %t14)
  ret ptr %t15
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
