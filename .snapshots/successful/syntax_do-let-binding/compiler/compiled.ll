; External C declarations
declare ptr @malloc(i64)
declare ptr @strcpy(ptr, ptr)
declare ptr @strcat(ptr, ptr)
declare i64 @strlen(ptr)
declare i32 @printf(ptr, ...)
declare i32 @snprintf(ptr, i64, ptr, ...)
declare {i32, i1} @llvm.sadd.with.overflow.i32(i32, i32)
declare {i32, i1} @llvm.smul.with.overflow.i32(i32, i32)

@.fmt = private unnamed_addr constant [3 x i8] c"%s\00"
@.fmt_i32 = private unnamed_addr constant [3 x i8] c"%d\00"
@.fmt_u8 = private unnamed_addr constant [3 x i8] c"%u\00"
@.empty = private unnamed_addr constant [1 x i8] c"\00"

@.str.0 = private unnamed_addr constant [9 x i8] c"overflow\00"
@.str.1 = private unnamed_addr constant [8 x i8] c"answer=\00"
@.str.2 = private unnamed_addr constant [6 x i8] c"err: \00"

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


define internal ptr @__addInt32(ptr %pa, ptr %pb) {
  %a = load i32, ptr %pa
  %b = load i32, ptr %pb
  %res = call {i32, i1} @llvm.sadd.with.overflow.i32(i32 %a, i32 %b)
  %sum = extractvalue {i32, i1} %res, 0
  %ovf = extractvalue {i32, i1} %res, 1
  br i1 %ovf, label %err, label %ok
err:
  %is_pos = icmp sge i32 %a, 0
  %row_tag_idx = select i1 %is_pos, i64 882564211, i64 3768445577
  %inner = call ptr @malloc(i64 8)
  %inner_tag = inttoptr i64 0 to ptr
  store ptr %inner_tag, ptr %inner
  %row = call ptr @malloc(i64 16)
  %row_tag = inttoptr i64 %row_tag_idx to ptr
  store ptr %row_tag, ptr %row
  %row_f = getelementptr ptr, ptr %row, i32 1
  store ptr %inner, ptr %row_f
  %left = call ptr @malloc(i64 16)
  %left_tag = inttoptr i64 0 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %row, ptr %left_f
  ret ptr %left
ok:
  %box = call ptr @malloc(i64 4)
  store i32 %sum, ptr %box
  %right = call ptr @malloc(i64 16)
  %right_tag = inttoptr i64 1 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %box, ptr %right_f
  ret ptr %right
}


define internal ptr @__mulInt32(ptr %pa, ptr %pb) {
  %a = load i32, ptr %pa
  %b = load i32, ptr %pb
  %res = call {i32, i1} @llvm.smul.with.overflow.i32(i32 %a, i32 %b)
  %prod = extractvalue {i32, i1} %res, 0
  %ovf = extractvalue {i32, i1} %res, 1
  br i1 %ovf, label %err, label %ok
err:
  %xor_ab = xor i32 %a, %b
  %same_sign = icmp sge i32 %xor_ab, 0
  %row_tag_idx = select i1 %same_sign, i64 882564211, i64 3768445577
  %inner = call ptr @malloc(i64 8)
  %inner_tag = inttoptr i64 0 to ptr
  store ptr %inner_tag, ptr %inner
  %row = call ptr @malloc(i64 16)
  %row_tag = inttoptr i64 %row_tag_idx to ptr
  store ptr %row_tag, ptr %row
  %row_f = getelementptr ptr, ptr %row, i32 1
  store ptr %inner, ptr %row_f
  %left = call ptr @malloc(i64 16)
  %left_tag = inttoptr i64 0 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %row, ptr %left_f
  ret ptr %left
ok:
  %box = call ptr @malloc(i64 4)
  store i32 %prod, ptr %box
  %right = call ptr @malloc(i64 16)
  %right_tag = inttoptr i64 1 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %box, ptr %right_f
  ret ptr %right
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

define internal ptr @v_step1(ptr %v_n) {
  %t0 = call ptr @malloc(i64 4)
  store i32 10, ptr %t0
  %t1 = call ptr @__addInt32(ptr %v_n, ptr %t0)
  %t2 = getelementptr ptr, ptr %t1, i32 0
  %t3 = load ptr, ptr %t2
  %t4 = ptrtoint ptr %t3 to i64
  switch i64 %t4, label %case.default.5 [ i64 0, label %case.arm.0.7 i64 1, label %case.arm.1.16 ]
case.arm.0.7:
  %t9 = getelementptr ptr, ptr %t1, i32 1
  %t10 = load ptr, ptr %t9
  %t11 = call ptr @malloc(i64 16)
  %t12 = inttoptr i64 0 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  %t14 = getelementptr [9 x i8], ptr @.str.0, i64 0, i64 0
  %t15 = getelementptr ptr, ptr %t11, i32 1
  store ptr %t14, ptr %t15
  br label %case.end.0.8
case.end.0.8:
  br label %case.join.6
case.arm.1.16:
  %t18 = getelementptr ptr, ptr %t1, i32 1
  %t19 = load ptr, ptr %t18
  %t20 = call ptr @malloc(i64 16)
  %t21 = inttoptr i64 1 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = getelementptr ptr, ptr %t20, i32 1
  store ptr %t19, ptr %t23
  br label %case.end.1.17
case.end.1.17:
  br label %case.join.6
case.default.5:
  unreachable
case.join.6:
  %t24 = phi ptr [%t11, %case.end.0.8], [%t20, %case.end.1.17]
  ret ptr %t24
}

define internal ptr @v_step2(ptr %v_n) {
  %t0 = call ptr @malloc(i64 4)
  store i32 2, ptr %t0
  %t1 = call ptr @__mulInt32(ptr %v_n, ptr %t0)
  %t2 = getelementptr ptr, ptr %t1, i32 0
  %t3 = load ptr, ptr %t2
  %t4 = ptrtoint ptr %t3 to i64
  switch i64 %t4, label %case.default.5 [ i64 0, label %case.arm.0.7 i64 1, label %case.arm.1.16 ]
case.arm.0.7:
  %t9 = getelementptr ptr, ptr %t1, i32 1
  %t10 = load ptr, ptr %t9
  %t11 = call ptr @malloc(i64 16)
  %t12 = inttoptr i64 0 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  %t14 = getelementptr [9 x i8], ptr @.str.0, i64 0, i64 0
  %t15 = getelementptr ptr, ptr %t11, i32 1
  store ptr %t14, ptr %t15
  br label %case.end.0.8
case.end.0.8:
  br label %case.join.6
case.arm.1.16:
  %t18 = getelementptr ptr, ptr %t1, i32 1
  %t19 = load ptr, ptr %t18
  %t20 = call ptr @malloc(i64 16)
  %t21 = inttoptr i64 1 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = getelementptr ptr, ptr %t20, i32 1
  store ptr %t19, ptr %t23
  br label %case.end.1.17
case.end.1.17:
  br label %case.join.6
case.default.5:
  unreachable
case.join.6:
  %t24 = phi ptr [%t11, %case.end.0.8], [%t20, %case.end.1.17]
  ret ptr %t24
}

define internal ptr @v_run(ptr %v_start) {
  %t0 = call ptr @v_step1(ptr %v_start)
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 0, label %case.arm.0.6 i64 1, label %case.arm.1.14 ]
case.arm.0.6:
  %t8 = getelementptr ptr, ptr %t0, i32 1
  %t9 = load ptr, ptr %t8
  %t10 = call ptr @malloc(i64 16)
  %t11 = inttoptr i64 0 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  %t13 = getelementptr ptr, ptr %t10, i32 1
  store ptr %t9, ptr %t13
  br label %case.end.0.7
case.end.0.7:
  br label %case.join.5
case.arm.1.14:
  %t16 = getelementptr ptr, ptr %t0, i32 1
  %t17 = load ptr, ptr %t16
  %t18 = getelementptr [8 x i8], ptr @.str.1, i64 0, i64 0
  %t19 = call ptr @v__let_1(ptr %t17, ptr %t18)
  br label %case.end.1.15
case.end.1.15:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t20 = phi ptr [%t10, %case.end.0.7], [%t19, %case.end.1.15]
  ret ptr %t20
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 4)
  store i32 5, ptr %t0
  %t1 = call ptr @v_run(ptr %t0)
  %t2 = getelementptr ptr, ptr %t1, i32 0
  %t3 = load ptr, ptr %t2
  %t4 = ptrtoint ptr %t3 to i64
  switch i64 %t4, label %case.default.5 [ i64 0, label %case.arm.0.7 i64 1, label %case.arm.1.14 ]
case.arm.0.7:
  %t9 = getelementptr ptr, ptr %t1, i32 1
  %t10 = load ptr, ptr %t9
  %t11 = getelementptr [6 x i8], ptr @.str.2, i64 0, i64 0
  %t12 = call ptr @__concat(ptr %t11, ptr %t10)
  %t13 = call ptr @__print(ptr %t12)
  br label %case.end.0.8
case.end.0.8:
  br label %case.join.6
case.arm.1.14:
  %t16 = getelementptr ptr, ptr %t1, i32 1
  %t17 = load ptr, ptr %t16
  %t18 = call ptr @__print(ptr %t17)
  br label %case.end.1.15
case.end.1.15:
  br label %case.join.6
case.default.5:
  unreachable
case.join.6:
  %t19 = phi ptr [%t13, %case.end.0.8], [%t18, %case.end.1.15]
  ret ptr %t19
}

define internal ptr @v__let_1(ptr %v_a, ptr %v_prefix) {
  %t0 = call ptr @v_step2(ptr %v_a)
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 0, label %case.arm.0.6 i64 1, label %case.arm.1.14 ]
case.arm.0.6:
  %t8 = getelementptr ptr, ptr %t0, i32 1
  %t9 = load ptr, ptr %t8
  %t10 = call ptr @malloc(i64 16)
  %t11 = inttoptr i64 0 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  %t13 = getelementptr ptr, ptr %t10, i32 1
  store ptr %t9, ptr %t13
  br label %case.end.0.7
case.end.0.7:
  br label %case.join.5
case.arm.1.14:
  %t16 = getelementptr ptr, ptr %t0, i32 1
  %t17 = load ptr, ptr %t16
  %t18 = call ptr @__showInt32(ptr %t17)
  %t19 = call ptr @__concat(ptr %v_prefix, ptr %t18)
  %t20 = call ptr @v_pureEither(ptr %t19)
  br label %case.end.1.15
case.end.1.15:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t21 = phi ptr [%t10, %case.end.0.7], [%t20, %case.end.1.15]
  ret ptr %t21
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
