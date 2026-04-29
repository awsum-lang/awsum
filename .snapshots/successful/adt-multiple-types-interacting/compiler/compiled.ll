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

@.str.0 = private unnamed_addr constant [4 x i8] c"red\00"
@.str.1 = private unnamed_addr constant [6 x i8] c"green\00"
@.str.2 = private unnamed_addr constant [5 x i8] c"blue\00"
@.str.3 = private unnamed_addr constant [2 x i8] c" \00"

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


define internal ptr @v_colorName(ptr %v_c) {
  %t0 = getelementptr ptr, ptr %v_c, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.8 i64 2, label %case.arm.2.11 ]
case.arm.0.5:
  %t7 = getelementptr [4 x i8], ptr @.str.0, i64 0, i64 0
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.8:
  %t10 = getelementptr [6 x i8], ptr @.str.1, i64 0, i64 0
  br label %case.end.1.9
case.end.1.9:
  br label %case.join.4
case.arm.2.11:
  %t13 = getelementptr [5 x i8], ptr @.str.2, i64 0, i64 0
  br label %case.end.2.12
case.end.2.12:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t14 = phi ptr [%t7, %case.end.0.6], [%t10, %case.end.1.9], [%t13, %case.end.2.12]
  ret ptr %t14
}

define internal ptr @v_showBoxedColor(ptr %v_bc) {
  %t0 = getelementptr ptr, ptr %v_bc, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_bc, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = call ptr @v_colorName(ptr %t8)
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t10 = phi ptr [%t9, %case.end.0.6]
  ret ptr %t10
}

define internal ptr @v_showResult(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.10 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_r, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = call ptr @v_showBoxedColor(ptr %t8)
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.10:
  %t12 = getelementptr ptr, ptr %v_r, i32 1
  %t13 = load ptr, ptr %t12
  br label %case.end.1.11
case.end.1.11:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t14 = phi ptr [%t9, %case.end.0.6], [%t13, %case.end.1.11]
  ret ptr %t14
}

define internal ptr @v_main(ptr %v__input) {
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
  %t7 = call ptr @v_showBoxedColor(ptr %t0)
  %t8 = getelementptr [2 x i8], ptr @.str.3, i64 0, i64 0
  %t9 = call ptr @__concat(ptr %t7, ptr %t8)
  %t10 = call ptr @malloc(i64 16)
  %t11 = inttoptr i64 0 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  %t13 = call ptr @malloc(i64 16)
  %t14 = inttoptr i64 0 to ptr
  %t15 = getelementptr ptr, ptr %t13, i32 0
  store ptr %t14, ptr %t15
  %t16 = call ptr @malloc(i64 8)
  %t17 = inttoptr i64 1 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = getelementptr ptr, ptr %t13, i32 1
  store ptr %t16, ptr %t19
  %t20 = getelementptr ptr, ptr %t10, i32 1
  store ptr %t13, ptr %t20
  %t21 = call ptr @v_showResult(ptr %t10)
  %t22 = call ptr @__concat(ptr %t9, ptr %t21)
  %t23 = call ptr @__print(ptr %t22)
  ret ptr %t23
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
