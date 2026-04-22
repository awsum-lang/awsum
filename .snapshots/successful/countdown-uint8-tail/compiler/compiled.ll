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

@.str.0 = private unnamed_addr constant [2 x i8] c",\00"
@.str.1 = private unnamed_addr constant [1 x i8] c"\00"

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


define ptr @__showUInt8(ptr %p) {
  %b = load i8, ptr %p
  %v = zext i8 %b to i32
  %buf = call ptr @malloc(i64 16)
  call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 16, ptr @.fmt_u8, i32 %v)
  ret ptr %buf
}


define ptr @__predUInt8(ptr %p) {
  %v = load i8, ptr %p
  %is_zero = icmp eq i8 %v, 0
  br i1 %is_zero, label %overflow, label %ok
overflow:
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
  %newv = sub i8 %v, 1
  %box = call ptr @malloc(i64 1)
  store i8 %newv, ptr %box
  %right = call ptr @malloc(i64 16)
  %right_tag = inttoptr i64 1 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %box, ptr %right_f
  ret ptr %right
}


define ptr @v_countDown(ptr %v_n, ptr %v_acc) {
entry:
  %t3 = alloca ptr
  store ptr %v_n, ptr %t3
  %t4 = alloca ptr
  store ptr %v_acc, ptr %t4
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t5 = load ptr, ptr %t3
  %t6 = load ptr, ptr %t4
  %t7 = call ptr @__predUInt8(ptr %t5)
  %t8 = getelementptr ptr, ptr %t7, i32 0
  %t9 = load ptr, ptr %t8
  %t10 = ptrtoint ptr %t9 to i64
  switch i64 %t10, label %tco.case.default.11 [ i64 0, label %tco.case.arm.0.12 i64 1, label %tco.case.arm.1.17 ]
tco.case.arm.0.12:
  %t13 = getelementptr ptr, ptr %t7, i32 1
  %t14 = load ptr, ptr %t13
  %t15 = call ptr @__showUInt8(ptr %t5)
  %t16 = call ptr @__concat(ptr %t6, ptr %t15)
  store ptr %t16, ptr %t2
  br label %tco.exit.1
tco.case.arm.1.17:
  %t18 = getelementptr ptr, ptr %t7, i32 1
  %t19 = load ptr, ptr %t18
  %t20 = call ptr @__showUInt8(ptr %t5)
  %t21 = call ptr @__concat(ptr %t6, ptr %t20)
  %t22 = getelementptr [2 x i8], ptr @.str.0, i64 0, i64 0
  %t23 = call ptr @__concat(ptr %t21, ptr %t22)
  store ptr %t19, ptr %t3
  store ptr %t23, ptr %t4
  br label %tco.loop.0
tco.case.default.11:
  unreachable
tco.exit.1:
  %t24 = load ptr, ptr %t2
  ret ptr %t24
}

define ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 1)
  store i8 255, ptr %t0
  %t1 = getelementptr [1 x i8], ptr @.str.1, i64 0, i64 0
  %t2 = call ptr @v_countDown(ptr %t0, ptr %t1)
  %t3 = call ptr @__print(ptr %t2)
  ret ptr %t3
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
