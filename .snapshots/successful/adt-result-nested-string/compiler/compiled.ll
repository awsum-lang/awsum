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

@.str.0 = private unnamed_addr constant [2 x i8] c"1\00"
@.str.1 = private unnamed_addr constant [2 x i8] c",\00"
@.str.2 = private unnamed_addr constant [2 x i8] c"2\00"
@.str.3 = private unnamed_addr constant [2 x i8] c"3\00"
@.str.4 = private unnamed_addr constant [2 x i8] c"4\00"

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

define ptr @v_unwrap(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.23 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_r, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr ptr, ptr %t8, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %case.default.12 [ i64 0, label %case.arm.0.14 i64 1, label %case.arm.1.18 ]
case.arm.0.14:
  %t16 = getelementptr ptr, ptr %t8, i32 1
  %t17 = load ptr, ptr %t16
  br label %case.end.0.15
case.end.0.15:
  br label %case.join.13
case.arm.1.18:
  %t20 = getelementptr ptr, ptr %t8, i32 1
  %t21 = load ptr, ptr %t20
  br label %case.end.1.19
case.end.1.19:
  br label %case.join.13
case.default.12:
  unreachable
case.join.13:
  %t22 = phi ptr [%t17, %case.end.0.15], [%t21, %case.end.1.19]
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.23:
  %t25 = getelementptr ptr, ptr %v_r, i32 1
  %t26 = load ptr, ptr %t25
  %t27 = getelementptr ptr, ptr %t26, i32 0
  %t28 = load ptr, ptr %t27
  %t29 = ptrtoint ptr %t28 to i64
  switch i64 %t29, label %case.default.30 [ i64 0, label %case.arm.0.32 i64 1, label %case.arm.1.36 ]
case.arm.0.32:
  %t34 = getelementptr ptr, ptr %t26, i32 1
  %t35 = load ptr, ptr %t34
  br label %case.end.0.33
case.end.0.33:
  br label %case.join.31
case.arm.1.36:
  %t38 = getelementptr ptr, ptr %t26, i32 1
  %t39 = load ptr, ptr %t38
  br label %case.end.1.37
case.end.1.37:
  br label %case.join.31
case.default.30:
  unreachable
case.join.31:
  %t40 = phi ptr [%t35, %case.end.0.33], [%t39, %case.end.1.37]
  br label %case.end.1.24
case.end.1.24:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t41 = phi ptr [%t22, %case.end.0.6], [%t40, %case.end.1.24]
  ret ptr %t41
}

define ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 0 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @malloc(i64 16)
  %t4 = inttoptr i64 0 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr [2 x i8], ptr @.str.0, i64 0, i64 0
  %t7 = getelementptr ptr, ptr %t3, i32 1
  store ptr %t6, ptr %t7
  %t8 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t8
  %t9 = call ptr @v_unwrap(ptr %t0)
  %t10 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  %t11 = call ptr @__concat(ptr %t9, ptr %t10)
  %t12 = call ptr @malloc(i64 16)
  %t13 = inttoptr i64 0 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = call ptr @malloc(i64 16)
  %t16 = inttoptr i64 1 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = getelementptr [2 x i8], ptr @.str.2, i64 0, i64 0
  %t19 = getelementptr ptr, ptr %t15, i32 1
  store ptr %t18, ptr %t19
  %t20 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t15, ptr %t20
  %t21 = call ptr @v_unwrap(ptr %t12)
  %t22 = call ptr @__concat(ptr %t11, ptr %t21)
  %t23 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  %t24 = call ptr @__concat(ptr %t22, ptr %t23)
  %t25 = call ptr @malloc(i64 16)
  %t26 = inttoptr i64 1 to ptr
  %t27 = getelementptr ptr, ptr %t25, i32 0
  store ptr %t26, ptr %t27
  %t28 = call ptr @malloc(i64 16)
  %t29 = inttoptr i64 0 to ptr
  %t30 = getelementptr ptr, ptr %t28, i32 0
  store ptr %t29, ptr %t30
  %t31 = getelementptr [2 x i8], ptr @.str.3, i64 0, i64 0
  %t32 = getelementptr ptr, ptr %t28, i32 1
  store ptr %t31, ptr %t32
  %t33 = getelementptr ptr, ptr %t25, i32 1
  store ptr %t28, ptr %t33
  %t34 = call ptr @v_unwrap(ptr %t25)
  %t35 = call ptr @__concat(ptr %t24, ptr %t34)
  %t36 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  %t37 = call ptr @__concat(ptr %t35, ptr %t36)
  %t38 = call ptr @malloc(i64 16)
  %t39 = inttoptr i64 1 to ptr
  %t40 = getelementptr ptr, ptr %t38, i32 0
  store ptr %t39, ptr %t40
  %t41 = call ptr @malloc(i64 16)
  %t42 = inttoptr i64 1 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = getelementptr [2 x i8], ptr @.str.4, i64 0, i64 0
  %t45 = getelementptr ptr, ptr %t41, i32 1
  store ptr %t44, ptr %t45
  %t46 = getelementptr ptr, ptr %t38, i32 1
  store ptr %t41, ptr %t46
  %t47 = call ptr @v_unwrap(ptr %t38)
  %t48 = call ptr @__concat(ptr %t37, ptr %t47)
  %t49 = call ptr @__print(ptr %t48)
  ret ptr %t49
}

define ptr @v__con_Err(ptr %v__x0) {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v__x0, ptr %t3
  ret ptr %t0
}

define ptr @v__con_Ok(ptr %v__x0) {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 0 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v__x0, ptr %t3
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
