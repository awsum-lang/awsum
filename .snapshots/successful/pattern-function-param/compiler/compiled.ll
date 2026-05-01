; External C declarations
declare ptr @malloc(i64)
declare ptr @strcpy(ptr, ptr)
declare ptr @strcat(ptr, ptr)
declare i64 @strlen(ptr)
declare i32 @printf(ptr, ...)
declare i32 @snprintf(ptr, i64, ptr, ...)
declare {i32, i1} @llvm.sadd.with.overflow.i32(i32, i32)

@.fmt = private unnamed_addr constant [3 x i8] c"%s\00"
@.fmt_i32 = private unnamed_addr constant [3 x i8] c"%d\00"
@.fmt_u8 = private unnamed_addr constant [3 x i8] c"%u\00"
@.empty = private unnamed_addr constant [1 x i8] c"\00"

@.str.0 = private unnamed_addr constant [4 x i8] c" / \00"

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


define internal ptr @v_sumTriple(ptr %v__arg_21_11) {
  %t0 = getelementptr ptr, ptr %v__arg_21_11, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v__arg_21_11, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr ptr, ptr %v__arg_21_11, i32 2
  %t10 = load ptr, ptr %t9
  %t11 = getelementptr ptr, ptr %v__arg_21_11, i32 3
  %t12 = load ptr, ptr %t11
  %t13 = call ptr @__addInt32(ptr %t8, ptr %t10)
  %t14 = getelementptr ptr, ptr %t13, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %case.default.17 [ i64 0, label %case.arm.0.19 i64 1, label %case.arm.1.24 ]
case.arm.0.19:
  %t21 = getelementptr ptr, ptr %t13, i32 1
  %t22 = load ptr, ptr %t21
  %t23 = call ptr @malloc(i64 4)
  store i32 0, ptr %t23
  br label %case.end.0.20
case.end.0.20:
  br label %case.join.18
case.arm.1.24:
  %t26 = getelementptr ptr, ptr %t13, i32 1
  %t27 = load ptr, ptr %t26
  %t28 = call ptr @__addInt32(ptr %t27, ptr %t12)
  %t29 = getelementptr ptr, ptr %t28, i32 0
  %t30 = load ptr, ptr %t29
  %t31 = ptrtoint ptr %t30 to i64
  switch i64 %t31, label %case.default.32 [ i64 0, label %case.arm.0.34 i64 1, label %case.arm.1.39 ]
case.arm.0.34:
  %t36 = getelementptr ptr, ptr %t28, i32 1
  %t37 = load ptr, ptr %t36
  %t38 = call ptr @malloc(i64 4)
  store i32 0, ptr %t38
  br label %case.end.0.35
case.end.0.35:
  br label %case.join.33
case.arm.1.39:
  %t41 = getelementptr ptr, ptr %t28, i32 1
  %t42 = load ptr, ptr %t41
  br label %case.end.1.40
case.end.1.40:
  br label %case.join.33
case.default.32:
  unreachable
case.join.33:
  %t43 = phi ptr [%t38, %case.end.0.35], [%t42, %case.end.1.40]
  br label %case.end.1.25
case.end.1.25:
  br label %case.join.18
case.default.17:
  unreachable
case.join.18:
  %t44 = phi ptr [%t23, %case.end.0.20], [%t43, %case.end.1.25]
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t45 = phi ptr [%t44, %case.end.0.6]
  ret ptr %t45
}

define internal ptr @v_apply(ptr %v_f, ptr %v_t) {
  %t0 = call ptr %v_f(ptr %v_t)
  ret ptr %t0
}

define internal ptr @v_sumPair(ptr %v__arg_31_9) {
  %t0 = getelementptr ptr, ptr %v__arg_31_9, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v__arg_31_9, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr ptr, ptr %v__arg_31_9, i32 2
  %t10 = load ptr, ptr %t9
  %t11 = call ptr @__addInt32(ptr %t8, ptr %t10)
  %t12 = getelementptr ptr, ptr %t11, i32 0
  %t13 = load ptr, ptr %t12
  %t14 = ptrtoint ptr %t13 to i64
  switch i64 %t14, label %case.default.15 [ i64 0, label %case.arm.0.17 i64 1, label %case.arm.1.22 ]
case.arm.0.17:
  %t19 = getelementptr ptr, ptr %t11, i32 1
  %t20 = load ptr, ptr %t19
  %t21 = call ptr @malloc(i64 4)
  store i32 0, ptr %t21
  br label %case.end.0.18
case.end.0.18:
  br label %case.join.16
case.arm.1.22:
  %t24 = getelementptr ptr, ptr %t11, i32 1
  %t25 = load ptr, ptr %t24
  br label %case.end.1.23
case.end.1.23:
  br label %case.join.16
case.default.15:
  unreachable
case.join.16:
  %t26 = phi ptr [%t21, %case.end.0.18], [%t25, %case.end.1.23]
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t27 = phi ptr [%t26, %case.end.0.6]
  ret ptr %t27
}

define internal ptr @v_triple() {
  %t0 = call ptr @malloc(i64 32)
  %t1 = inttoptr i64 0 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @malloc(i64 4)
  store i32 10, ptr %t3
  %t4 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t4
  %t5 = call ptr @malloc(i64 4)
  store i32 20, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t5, ptr %t6
  %t7 = call ptr @malloc(i64 4)
  store i32 30, ptr %t7
  %t8 = getelementptr ptr, ptr %t0, i32 3
  store ptr %t7, ptr %t8
  ret ptr %t0
}

define internal ptr @v_pair() {
  %t0 = call ptr @malloc(i64 24)
  %t1 = inttoptr i64 0 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @malloc(i64 4)
  store i32 100, ptr %t3
  %t4 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t4
  %t5 = call ptr @malloc(i64 4)
  store i32 200, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t5, ptr %t6
  ret ptr %t0
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @v_triple()
  %t1 = call ptr @v_sumTriple(ptr %t0)
  %t2 = call ptr @v__let_2(ptr %t1)
  ret ptr %t2
}

define internal ptr @v__lam_0(ptr %v__arg_44_19) {
  %t0 = getelementptr ptr, ptr %v__arg_44_19, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v__arg_44_19, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr ptr, ptr %v__arg_44_19, i32 2
  %t10 = load ptr, ptr %t9
  %t11 = call ptr @malloc(i64 24)
  %t12 = inttoptr i64 0 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  %t14 = getelementptr ptr, ptr %t11, i32 1
  store ptr %t8, ptr %t14
  %t15 = getelementptr ptr, ptr %t11, i32 2
  store ptr %t10, ptr %t15
  %t16 = call ptr @v_sumPair(ptr %t11)
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t17 = phi ptr [%t16, %case.end.0.6]
  ret ptr %t17
}

define internal ptr @v__let_1(ptr %v_n, ptr %v_m) {
  %t0 = call ptr @__showInt32(ptr %v_n)
  %t1 = getelementptr [4 x i8], ptr @.str.0, i64 0, i64 0
  %t2 = call ptr @__concat(ptr %t0, ptr %t1)
  %t3 = call ptr @__showInt32(ptr %v_m)
  %t4 = call ptr @__concat(ptr %t2, ptr %t3)
  %t5 = call ptr @__print(ptr %t4)
  ret ptr %t5
}

define internal ptr @v__let_2(ptr %v_n) {
  %t0 = call ptr @v_pair()
  %t1 = call ptr @v_apply(ptr @v__lam_0, ptr %t0)
  %t2 = call ptr @v__let_1(ptr %v_n, ptr %t1)
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
