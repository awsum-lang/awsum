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

@.str.0 = private unnamed_addr constant [14 x i8] c"OverflowError\00"
@.str.1 = private unnamed_addr constant [11 x i8] c"overflow: \00"
@.str.2 = private unnamed_addr constant [5 x i8] c"ok: \00"
@.str.3 = private unnamed_addr constant [3 x i8] c", \00"

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


define internal ptr @__showUInt8(ptr %p) {
  %b = load i8, ptr %p
  %v = zext i8 %b to i32
  %buf = call ptr @malloc(i64 16)
  call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 16, ptr @.fmt_u8, i32 %v)
  ret ptr %buf
}


define internal ptr @__mulUInt8(ptr %pa, ptr %pb) {
  %a = load i8, ptr %pa
  %b = load i8, ptr %pb
  %a32 = zext i8 %a to i32
  %b32 = zext i8 %b to i32
  %prod32 = mul i32 %a32, %b32
  %ovf = icmp ugt i32 %prod32, 255
  br i1 %ovf, label %err, label %ok
err:
  %oe = call ptr @malloc(i64 8)
  %oe_tag = inttoptr i64 0 to ptr
  store ptr %oe_tag, ptr %oe
  %left = call ptr @malloc(i64 16)
  %left_tag = inttoptr i64 0 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %oe, ptr %left_f
  ret ptr %left
ok:
  %newv = trunc i32 %prod32 to i8
  %box = call ptr @malloc(i64 1)
  store i8 %newv, ptr %box
  %right = call ptr @malloc(i64 16)
  %right_tag = inttoptr i64 1 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %box, ptr %right_f
  ret ptr %right
}


define internal ptr @v_showOverflowError(ptr %v__wild0) {
  %t0 = getelementptr [14 x i8], ptr @.str.0, i64 0, i64 0
  ret ptr %t0
}

define internal ptr @v_minUInt8() {
  %t0 = call ptr @malloc(i64 1)
  store i8 0, ptr %t0
  ret ptr %t0
}

define internal ptr @v_maxUInt8() {
  %t0 = call ptr @malloc(i64 1)
  store i8 255, ptr %t0
  ret ptr %t0
}

define internal ptr @v_render(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.12 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_r, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr [11 x i8], ptr @.str.1, i64 0, i64 0
  %t10 = call ptr @v_showOverflowError(ptr %t8)
  %t11 = call ptr @__concat(ptr %t9, ptr %t10)
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.12:
  %t14 = getelementptr ptr, ptr %v_r, i32 1
  %t15 = load ptr, ptr %t14
  %t16 = getelementptr [5 x i8], ptr @.str.2, i64 0, i64 0
  %t17 = call ptr @__showUInt8(ptr %t15)
  %t18 = call ptr @__concat(ptr %t16, ptr %t17)
  br label %case.end.1.13
case.end.1.13:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t19 = phi ptr [%t11, %case.end.0.6], [%t18, %case.end.1.13]
  ret ptr %t19
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 1)
  store i8 15, ptr %t0
  %t1 = call ptr @malloc(i64 1)
  store i8 17, ptr %t1
  %t2 = call ptr @__mulUInt8(ptr %t0, ptr %t1)
  %t3 = call ptr @v_render(ptr %t2)
  %t4 = getelementptr [3 x i8], ptr @.str.3, i64 0, i64 0
  %t5 = call ptr @__concat(ptr %t3, ptr %t4)
  %t6 = call ptr @malloc(i64 1)
  store i8 16, ptr %t6
  %t7 = call ptr @malloc(i64 1)
  store i8 16, ptr %t7
  %t8 = call ptr @__mulUInt8(ptr %t6, ptr %t7)
  %t9 = call ptr @v_render(ptr %t8)
  %t10 = call ptr @__concat(ptr %t5, ptr %t9)
  %t11 = getelementptr [3 x i8], ptr @.str.3, i64 0, i64 0
  %t12 = call ptr @__concat(ptr %t10, ptr %t11)
  %t13 = call ptr @v_maxUInt8()
  %t14 = call ptr @v_maxUInt8()
  %t15 = call ptr @__mulUInt8(ptr %t13, ptr %t14)
  %t16 = call ptr @v_render(ptr %t15)
  %t17 = call ptr @__concat(ptr %t12, ptr %t16)
  %t18 = getelementptr [3 x i8], ptr @.str.3, i64 0, i64 0
  %t19 = call ptr @__concat(ptr %t17, ptr %t18)
  %t20 = call ptr @v_minUInt8()
  %t21 = call ptr @malloc(i64 1)
  store i8 200, ptr %t21
  %t22 = call ptr @__mulUInt8(ptr %t20, ptr %t21)
  %t23 = call ptr @v_render(ptr %t22)
  %t24 = call ptr @__concat(ptr %t19, ptr %t23)
  %t25 = getelementptr [3 x i8], ptr @.str.3, i64 0, i64 0
  %t26 = call ptr @__concat(ptr %t24, ptr %t25)
  %t27 = call ptr @malloc(i64 1)
  store i8 1, ptr %t27
  %t28 = call ptr @malloc(i64 1)
  store i8 200, ptr %t28
  %t29 = call ptr @__mulUInt8(ptr %t27, ptr %t28)
  %t30 = call ptr @v_render(ptr %t29)
  %t31 = call ptr @__concat(ptr %t26, ptr %t30)
  %t32 = call ptr @__print(ptr %t31)
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
  call ptr @v_main(ptr %input)
  ret i32 0
}
