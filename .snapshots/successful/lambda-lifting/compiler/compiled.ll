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

@.str.0 = private unnamed_addr constant [5 x i8] c"ErrA\00"
@.str.1 = private unnamed_addr constant [5 x i8] c"ErrB\00"
@.str.2 = private unnamed_addr constant [4 x i8] c"Ok \00"
@.str.3 = private unnamed_addr constant [4 x i8] c" / \00"

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


define internal ptr @__showInt32(ptr %p) {
  %v = load i32, ptr %p
  %buf = call ptr @malloc(i64 16)
  call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 16, ptr @.fmt_i32, i32 %v)
  ret ptr %buf
}


define internal ptr @v_bindEither(ptr %v_x, ptr %v_k) {
  %t0 = getelementptr ptr, ptr %v_x, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.13 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_x, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = call ptr @malloc(i64 16)
  %t10 = inttoptr i64 0 to ptr
  %t11 = getelementptr ptr, ptr %t9, i32 0
  store ptr %t10, ptr %t11
  %t12 = getelementptr ptr, ptr %t9, i32 1
  store ptr %t8, ptr %t12
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.13:
  %t15 = getelementptr ptr, ptr %v_x, i32 1
  %t16 = load ptr, ptr %t15
  %t17 = call ptr %v_k(ptr %t16)
  br label %case.end.1.14
case.end.1.14:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t18 = phi ptr [%t9, %case.end.0.6], [%t17, %case.end.1.14]
  ret ptr %t18
}

define internal ptr @v_pureEither(ptr %v_x) {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v_x, ptr %t3
  ret ptr %t0
}

define internal ptr @v_apply(ptr %v_f, ptr %v_x) {
  %t0 = call ptr %v_f(ptr %v_x)
  ret ptr %t0
}

define internal ptr @v_answer() {
  %t0 = call ptr @malloc(i64 4)
  store i32 42, ptr %t0
  ret ptr %t0
}

define internal ptr @v_inc42() {
  %t0 = call ptr @v_answer()
  %t1 = call ptr @v_apply(ptr @v__lam_0, ptr %t0)
  ret ptr %t1
}

define internal ptr @v_op1() {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @malloc(i64 4)
  store i32 1, ptr %t3
  %t4 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t4
  ret ptr %t0
}

define internal ptr @v_op2WithA(ptr %v_n) {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v_n, ptr %t3
  ret ptr %t0
}

define internal ptr @v_g() {
  %t0 = call ptr @v_op1()
  %t1 = call ptr @v_bindEither(ptr %t0, ptr @v__lam_1)
  ret ptr %t1
}

define internal ptr @v_describe(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.25 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_r, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr ptr, ptr %t8, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %case.default.12 [ i64 2252990199, label %case.arm.2252990199.14 i64 2269767818, label %case.arm.2269767818.19 ]
case.arm.2252990199.14:
  %t16 = getelementptr ptr, ptr %t8, i32 1
  %t17 = load ptr, ptr %t16
  %t18 = getelementptr [5 x i8], ptr @.str.0, i64 0, i64 0
  br label %case.end.2252990199.15
case.end.2252990199.15:
  br label %case.join.13
case.arm.2269767818.19:
  %t21 = getelementptr ptr, ptr %t8, i32 1
  %t22 = load ptr, ptr %t21
  %t23 = getelementptr [5 x i8], ptr @.str.1, i64 0, i64 0
  br label %case.end.2269767818.20
case.end.2269767818.20:
  br label %case.join.13
case.default.12:
  unreachable
case.join.13:
  %t24 = phi ptr [%t18, %case.end.2252990199.15], [%t23, %case.end.2269767818.20]
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.25:
  %t27 = getelementptr ptr, ptr %v_r, i32 1
  %t28 = load ptr, ptr %t27
  %t29 = getelementptr [4 x i8], ptr @.str.2, i64 0, i64 0
  %t30 = call ptr @__showInt32(ptr %t28)
  %t31 = call ptr @__concat(ptr %t29, ptr %t30)
  br label %case.end.1.26
case.end.1.26:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t32 = phi ptr [%t24, %case.end.0.6], [%t31, %case.end.1.26]
  ret ptr %t32
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @v_inc42()
  %t1 = call ptr @__showInt32(ptr %t0)
  %t2 = getelementptr [4 x i8], ptr @.str.3, i64 0, i64 0
  %t3 = call ptr @__concat(ptr %t1, ptr %t2)
  %t4 = call ptr @v_g()
  %t5 = call ptr @v_describe(ptr %t4)
  %t6 = call ptr @__concat(ptr %t3, ptr %t5)
  %t7 = call ptr @__print(ptr %t6)
  ret ptr %t7
}

define internal ptr @v__lam_0(ptr %v_n) {
  ret ptr %v_n
}

define internal ptr @v__lam_1(ptr %v_a) {
  %t0 = call ptr @v_op2WithA(ptr %v_a)
  %t1 = call ptr @v_bindEither(ptr %t0, ptr @v_pureEither)
  ret ptr %t1
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
