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

@.str.0 = private unnamed_addr constant [2 x i8] c"T\00"
@.str.1 = private unnamed_addr constant [2 x i8] c"F\00"

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


define internal ptr @v_not(ptr %v_b) {
  %t0 = getelementptr ptr, ptr %v_b, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.10 ]
case.arm.0.5:
  %t7 = call ptr @malloc(i64 8)
  %t8 = inttoptr i64 1 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.10:
  %t12 = call ptr @malloc(i64 8)
  %t13 = inttoptr i64 0 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  br label %case.end.1.11
case.end.1.11:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t15 = phi ptr [%t7, %case.end.0.6], [%t12, %case.end.1.11]
  ret ptr %t15
}

define internal ptr @v_and(ptr %v_a, ptr %v_b) {
  %t0 = getelementptr ptr, ptr %v_a, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.7 ]
case.arm.0.5:
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.7:
  %t9 = call ptr @malloc(i64 8)
  %t10 = inttoptr i64 1 to ptr
  %t11 = getelementptr ptr, ptr %t9, i32 0
  store ptr %t10, ptr %t11
  br label %case.end.1.8
case.end.1.8:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t12 = phi ptr [%v_b, %case.end.0.6], [%t9, %case.end.1.8]
  ret ptr %t12
}

define internal ptr @v_or(ptr %v_a, ptr %v_b) {
  %t0 = getelementptr ptr, ptr %v_a, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.10 ]
case.arm.0.5:
  %t7 = call ptr @malloc(i64 8)
  %t8 = inttoptr i64 0 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.10:
  br label %case.end.1.11
case.end.1.11:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t12 = phi ptr [%t7, %case.end.0.6], [%v_b, %case.end.1.11]
  ret ptr %t12
}

define internal ptr @v_showBool(ptr %v_b) {
  %t0 = getelementptr ptr, ptr %v_b, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.8 ]
case.arm.0.5:
  %t7 = getelementptr [2 x i8], ptr @.str.0, i64 0, i64 0
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.8:
  %t10 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  br label %case.end.1.9
case.end.1.9:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t11 = phi ptr [%t7, %case.end.0.6], [%t10, %case.end.1.9]
  ret ptr %t11
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 8)
  %t1 = inttoptr i64 0 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_not(ptr %t0)
  %t4 = call ptr @v_showBool(ptr %t3)
  %t5 = call ptr @malloc(i64 8)
  %t6 = inttoptr i64 1 to ptr
  %t7 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t6, ptr %t7
  %t8 = call ptr @v_not(ptr %t5)
  %t9 = call ptr @v_showBool(ptr %t8)
  %t10 = call ptr @__concat(ptr %t4, ptr %t9)
  %t11 = call ptr @malloc(i64 8)
  %t12 = inttoptr i64 0 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  %t14 = call ptr @malloc(i64 8)
  %t15 = inttoptr i64 1 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  %t17 = call ptr @v_and(ptr %t11, ptr %t14)
  %t18 = call ptr @v_showBool(ptr %t17)
  %t19 = call ptr @__concat(ptr %t10, ptr %t18)
  %t20 = call ptr @malloc(i64 8)
  %t21 = inttoptr i64 0 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = call ptr @malloc(i64 8)
  %t24 = inttoptr i64 0 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  %t26 = call ptr @v_and(ptr %t20, ptr %t23)
  %t27 = call ptr @v_showBool(ptr %t26)
  %t28 = call ptr @__concat(ptr %t19, ptr %t27)
  %t29 = call ptr @malloc(i64 8)
  %t30 = inttoptr i64 1 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = call ptr @malloc(i64 8)
  %t33 = inttoptr i64 1 to ptr
  %t34 = getelementptr ptr, ptr %t32, i32 0
  store ptr %t33, ptr %t34
  %t35 = call ptr @v_or(ptr %t29, ptr %t32)
  %t36 = call ptr @v_showBool(ptr %t35)
  %t37 = call ptr @__concat(ptr %t28, ptr %t36)
  %t38 = call ptr @malloc(i64 8)
  %t39 = inttoptr i64 0 to ptr
  %t40 = getelementptr ptr, ptr %t38, i32 0
  store ptr %t39, ptr %t40
  %t41 = call ptr @malloc(i64 8)
  %t42 = inttoptr i64 1 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = call ptr @v_or(ptr %t38, ptr %t41)
  %t45 = call ptr @v_showBool(ptr %t44)
  %t46 = call ptr @__concat(ptr %t37, ptr %t45)
  %t47 = call ptr @__print(ptr %t46)
  ret ptr %t47
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
