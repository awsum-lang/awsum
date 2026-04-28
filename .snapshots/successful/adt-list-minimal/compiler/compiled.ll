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

@.str.0 = private unnamed_addr constant [1 x i8] c"\00"
@.str.1 = private unnamed_addr constant [2 x i8] c",\00"
@.str.2 = private unnamed_addr constant [2 x i8] c"a\00"
@.str.3 = private unnamed_addr constant [2 x i8] c"b\00"
@.str.4 = private unnamed_addr constant [2 x i8] c"c\00"

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


define internal ptr @v_show(ptr %v_xs) {
  %t0 = call ptr @malloc(i64 8)
  %t1 = inttoptr i64 0 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps_show(ptr %v_xs, ptr %t0)
  ret ptr %t3
}

define internal ptr @v__cps_show(ptr %v_xs, ptr %v__k) {
entry:
  %t3 = alloca ptr
  store ptr %v_xs, ptr %t3
  %t4 = alloca ptr
  store ptr %v__k, ptr %t4
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t5 = load ptr, ptr %t3
  %t6 = load ptr, ptr %t4
  %t7 = getelementptr ptr, ptr %t5, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %tco.case.default.10 [ i64 0, label %tco.case.arm.0.11 i64 1, label %tco.case.arm.1.21 ]
tco.case.arm.0.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  %t14 = getelementptr ptr, ptr %t5, i32 2
  %t15 = load ptr, ptr %t14
  %t16 = call ptr @malloc(i64 24)
  %t17 = inttoptr i64 1 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t6, ptr %t19
  %t20 = getelementptr ptr, ptr %t16, i32 2
  store ptr %t13, ptr %t20
  store ptr %t15, ptr %t3
  store ptr %t16, ptr %t4
  br label %tco.loop.0
tco.case.arm.1.21:
  %t22 = getelementptr [1 x i8], ptr @.str.0, i64 0, i64 0
  %t23 = call ptr @v__apply_show(ptr %t6, ptr %t22)
  store ptr %t23, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t24 = load ptr, ptr %t2
  ret ptr %t24
}

define internal ptr @v__apply_show(ptr %v__k, ptr %v__x) {
entry:
  %t3 = alloca ptr
  store ptr %v__k, ptr %t3
  %t4 = alloca ptr
  store ptr %v__x, ptr %t4
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t5 = load ptr, ptr %t3
  %t6 = load ptr, ptr %t4
  %t7 = getelementptr ptr, ptr %t5, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %tco.case.default.10 [ i64 0, label %tco.case.arm.0.11 i64 1, label %tco.case.arm.1.12 ]
tco.case.arm.0.11:
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.1.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  %t15 = getelementptr ptr, ptr %t5, i32 2
  %t16 = load ptr, ptr %t15
  %t17 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  %t18 = call ptr @__concat(ptr %t16, ptr %t17)
  %t19 = call ptr @__concat(ptr %t18, ptr %t6)
  store ptr %t14, ptr %t3
  store ptr %t19, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t20 = load ptr, ptr %t2
  ret ptr %t20
}

define internal ptr @v_exampleList() {
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

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @v_exampleList()
  %t1 = call ptr @v_show(ptr %t0)
  %t2 = call ptr @__print(ptr %t1)
  ret ptr %t2
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
