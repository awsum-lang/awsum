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

@.str.0 = private unnamed_addr constant [3 x i8] c", \00"

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

define ptr @v_main(ptr %v__input) {
  %t0 = call ptr @v_minUInt8()
  %t1 = call ptr @__showUInt8(ptr %t0)
  %t2 = getelementptr [3 x i8], ptr @.str.0, i64 0, i64 0
  %t3 = call ptr @__concat(ptr %t1, ptr %t2)
  %t4 = call ptr @v_small()
  %t5 = call ptr @__showUInt8(ptr %t4)
  %t6 = call ptr @__concat(ptr %t3, ptr %t5)
  %t7 = getelementptr [3 x i8], ptr @.str.0, i64 0, i64 0
  %t8 = call ptr @__concat(ptr %t6, ptr %t7)
  %t9 = call ptr @v_aboveSignedByte()
  %t10 = call ptr @__showUInt8(ptr %t9)
  %t11 = call ptr @__concat(ptr %t8, ptr %t10)
  %t12 = getelementptr [3 x i8], ptr @.str.0, i64 0, i64 0
  %t13 = call ptr @__concat(ptr %t11, ptr %t12)
  %t14 = call ptr @v_maxUInt8()
  %t15 = call ptr @__showUInt8(ptr %t14)
  %t16 = call ptr @__concat(ptr %t13, ptr %t15)
  %t17 = call ptr @__print(ptr %t16)
  ret ptr %t17
}

define ptr @v_minUInt8() {
  %t0 = call ptr @malloc(i64 1)
  store i8 0, ptr %t0
  ret ptr %t0
}

define ptr @v_small() {
  %t0 = call ptr @malloc(i64 1)
  store i8 42, ptr %t0
  ret ptr %t0
}

define ptr @v_aboveSignedByte() {
  %t0 = call ptr @malloc(i64 1)
  store i8 200, ptr %t0
  ret ptr %t0
}

define ptr @v_maxUInt8() {
  %t0 = call ptr @malloc(i64 1)
  store i8 255, ptr %t0
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
