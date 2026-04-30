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

@.str.0 = private unnamed_addr constant [7 x i8] c"ErrorA\00"
@.str.1 = private unnamed_addr constant [7 x i8] c"ErrorC\00"
@.str.2 = private unnamed_addr constant [7 x i8] c"ErrorB\00"
@.str.3 = private unnamed_addr constant [4 x i8] c"Ok \00"

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

define internal ptr @v_const(ptr %v_x, ptr %v__y) {
  ret ptr %v_x
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

define internal ptr @v_op2() {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 0 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @malloc(i64 16)
  %t4 = inttoptr i64 435006518 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = call ptr @malloc(i64 8)
  %t7 = inttoptr i64 0 to ptr
  %t8 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t7, ptr %t8
  %t9 = getelementptr ptr, ptr %t3, i32 1
  store ptr %t6, ptr %t9
  %t10 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t10
  ret ptr %t0
}

define internal ptr @v_op3() {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @malloc(i64 4)
  store i32 3, ptr %t3
  %t4 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t4
  ret ptr %t0
}

define internal ptr @v_f() {
  %t0 = call ptr @v_op1()
  %t1 = call ptr @v_bindEither(ptr %t0, ptr @v__pap_1)
  ret ptr %t1
}

define internal ptr @v_describe(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.30 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_r, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr ptr, ptr %t8, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %case.default.12 [ i64 401451280, label %case.arm.401451280.14 i64 435006518, label %case.arm.435006518.19 i64 451784137, label %case.arm.451784137.24 ]
case.arm.401451280.14:
  %t16 = getelementptr ptr, ptr %t8, i32 1
  %t17 = load ptr, ptr %t16
  %t18 = getelementptr [7 x i8], ptr @.str.0, i64 0, i64 0
  br label %case.end.401451280.15
case.end.401451280.15:
  br label %case.join.13
case.arm.435006518.19:
  %t21 = getelementptr ptr, ptr %t8, i32 1
  %t22 = load ptr, ptr %t21
  %t23 = getelementptr [7 x i8], ptr @.str.1, i64 0, i64 0
  br label %case.end.435006518.20
case.end.435006518.20:
  br label %case.join.13
case.arm.451784137.24:
  %t26 = getelementptr ptr, ptr %t8, i32 1
  %t27 = load ptr, ptr %t26
  %t28 = getelementptr [7 x i8], ptr @.str.2, i64 0, i64 0
  br label %case.end.451784137.25
case.end.451784137.25:
  br label %case.join.13
case.default.12:
  unreachable
case.join.13:
  %t29 = phi ptr [%t18, %case.end.401451280.15], [%t23, %case.end.435006518.20], [%t28, %case.end.451784137.25]
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.30:
  %t32 = getelementptr ptr, ptr %v_r, i32 1
  %t33 = load ptr, ptr %t32
  %t34 = getelementptr [4 x i8], ptr @.str.3, i64 0, i64 0
  %t35 = call ptr @__showInt32(ptr %t33)
  %t36 = call ptr @__concat(ptr %t34, ptr %t35)
  br label %case.end.1.31
case.end.1.31:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t37 = phi ptr [%t29, %case.end.0.6], [%t36, %case.end.1.31]
  ret ptr %t37
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @v_f()
  %t1 = call ptr @v_describe(ptr %t0)
  %t2 = call ptr @__print(ptr %t1)
  ret ptr %t2
}

define internal ptr @v__pap_0(ptr %v__eta0) {
  %t0 = call ptr @v_op3()
  %t1 = call ptr @v_bindEither(ptr %t0, ptr @v_pureEither)
  %t2 = call ptr @v_const(ptr %t1, ptr %v__eta0)
  ret ptr %t2
}

define internal ptr @v__pap_1(ptr %v__eta0) {
  %t0 = call ptr @v_op2()
  %t1 = call ptr @v_bindEither(ptr %t0, ptr @v__pap_0)
  %t2 = call ptr @v_const(ptr %t1, ptr %v__eta0)
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
