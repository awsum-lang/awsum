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

@.str.0 = private unnamed_addr constant [12 x i8] c"PARSE_ERROR\00"

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


define internal ptr @v_pureEither(ptr %v_x) {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v_x, ptr %t3
  ret ptr %t0
}

define internal ptr @v_opTuple(ptr %v__wild0) {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @malloc(i64 32)
  %t4 = inttoptr i64 0 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = call ptr @malloc(i64 4)
  store i32 1, ptr %t6
  %t7 = getelementptr ptr, ptr %t3, i32 1
  store ptr %t6, ptr %t7
  %t8 = call ptr @malloc(i64 4)
  store i32 2, ptr %t8
  %t9 = getelementptr ptr, ptr %t3, i32 2
  store ptr %t8, ptr %t9
  %t10 = call ptr @malloc(i64 4)
  store i32 3, ptr %t10
  %t11 = getelementptr ptr, ptr %t3, i32 3
  store ptr %t10, ptr %t11
  %t12 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t12
  ret ptr %t0
}

define internal ptr @v_main(ptr %v_raw) {
  %t0 = call ptr @v_opTuple(ptr %v_raw)
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
  %t18 = getelementptr ptr, ptr %t17, i32 0
  %t19 = load ptr, ptr %t18
  %t20 = ptrtoint ptr %t19 to i64
  switch i64 %t20, label %case.default.21 [ i64 0, label %case.arm.0.23 ]
case.arm.0.23:
  %t25 = getelementptr ptr, ptr %t17, i32 1
  %t26 = load ptr, ptr %t25
  %t27 = getelementptr ptr, ptr %t17, i32 2
  %t28 = load ptr, ptr %t27
  %t29 = getelementptr ptr, ptr %t17, i32 3
  %t30 = load ptr, ptr %t29
  %t31 = call ptr @__addInt32(ptr %t26, ptr %t28)
  %t32 = getelementptr ptr, ptr %t31, i32 0
  %t33 = load ptr, ptr %t32
  %t34 = ptrtoint ptr %t33 to i64
  switch i64 %t34, label %case.default.35 [ i64 0, label %case.arm.0.37 i64 1, label %case.arm.1.41 ]
case.arm.0.37:
  %t39 = getelementptr ptr, ptr %t31, i32 1
  %t40 = load ptr, ptr %t39
  br label %case.end.0.38
case.end.0.38:
  br label %case.join.36
case.arm.1.41:
  %t43 = getelementptr ptr, ptr %t31, i32 1
  %t44 = load ptr, ptr %t43
  %t45 = call ptr @__addInt32(ptr %t44, ptr %t30)
  %t46 = getelementptr ptr, ptr %t45, i32 0
  %t47 = load ptr, ptr %t46
  %t48 = ptrtoint ptr %t47 to i64
  switch i64 %t48, label %case.default.49 [ i64 0, label %case.arm.0.51 i64 1, label %case.arm.1.55 ]
case.arm.0.51:
  %t53 = getelementptr ptr, ptr %t45, i32 1
  %t54 = load ptr, ptr %t53
  br label %case.end.0.52
case.end.0.52:
  br label %case.join.50
case.arm.1.55:
  %t57 = getelementptr ptr, ptr %t45, i32 1
  %t58 = load ptr, ptr %t57
  br label %case.end.1.56
case.end.1.56:
  br label %case.join.50
case.default.49:
  unreachable
case.join.50:
  %t59 = phi ptr [%t30, %case.end.0.52], [%t58, %case.end.1.56]
  br label %case.end.1.42
case.end.1.42:
  br label %case.join.36
case.default.35:
  unreachable
case.join.36:
  %t60 = phi ptr [%t30, %case.end.0.38], [%t59, %case.end.1.42]
  %t61 = call ptr @v_pureEither(ptr %t60)
  br label %case.end.0.24
case.end.0.24:
  br label %case.join.22
case.default.21:
  unreachable
case.join.22:
  %t62 = phi ptr [%t61, %case.end.0.24]
  br label %case.end.1.15
case.end.1.15:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t63 = phi ptr [%t10, %case.end.0.7], [%t62, %case.end.1.15]
  %t64 = call ptr @v__let_1(ptr %t63)
  ret ptr %t64
}

define internal ptr @v__let_1(ptr %v_res) {
  %t0 = getelementptr ptr, ptr %v_res, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.11 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_res, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr [12 x i8], ptr @.str.0, i64 0, i64 0
  %t10 = call ptr @__print(ptr %t9)
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.11:
  %t13 = getelementptr ptr, ptr %v_res, i32 1
  %t14 = load ptr, ptr %t13
  %t15 = call ptr @__showInt32(ptr %t14)
  %t16 = call ptr @__print(ptr %t15)
  br label %case.end.1.12
case.end.1.12:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t17 = phi ptr [%t10, %case.end.0.6], [%t16, %case.end.1.12]
  ret ptr %t17
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
