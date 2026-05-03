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

@.str.0 = private unnamed_addr constant [25 x i8] c"UNPAIRED_UTF16_SURROGATE\00"
@.str.1 = private unnamed_addr constant [16 x i8] c"STRING_TOO_LONG\00"
@.str.2 = private unnamed_addr constant [12 x i8] c"PARSE_ERROR\00"

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

define internal ptr @v_main(ptr %v_rawArg) {
  %t0 = getelementptr ptr, ptr %v_rawArg, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.13 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_rawArg, i32 1
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
  %t15 = getelementptr ptr, ptr %v_rawArg, i32 1
  %t16 = load ptr, ptr %t15
  %t17 = call ptr @v_opTuple(ptr %t16)
  %t18 = getelementptr ptr, ptr %t17, i32 0
  %t19 = load ptr, ptr %t18
  %t20 = ptrtoint ptr %t19 to i64
  switch i64 %t20, label %case.default.21 [ i64 0, label %case.arm.0.23 i64 1, label %case.arm.1.35 ]
case.arm.0.23:
  %t25 = getelementptr ptr, ptr %t17, i32 1
  %t26 = load ptr, ptr %t25
  %t27 = call ptr @malloc(i64 16)
  %t28 = inttoptr i64 0 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  %t30 = call ptr @malloc(i64 16)
  %t31 = inttoptr i64 2448244154 to ptr
  %t32 = getelementptr ptr, ptr %t30, i32 0
  store ptr %t31, ptr %t32
  %t33 = getelementptr ptr, ptr %t30, i32 1
  store ptr %t26, ptr %t33
  %t34 = getelementptr ptr, ptr %t27, i32 1
  store ptr %t30, ptr %t34
  br label %case.end.0.24
case.end.0.24:
  br label %case.join.22
case.arm.1.35:
  %t37 = getelementptr ptr, ptr %t17, i32 1
  %t38 = load ptr, ptr %t37
  %t39 = getelementptr ptr, ptr %t38, i32 0
  %t40 = load ptr, ptr %t39
  %t41 = ptrtoint ptr %t40 to i64
  switch i64 %t41, label %case.default.42 [ i64 0, label %case.arm.0.44 ]
case.arm.0.44:
  %t46 = getelementptr ptr, ptr %t38, i32 1
  %t47 = load ptr, ptr %t46
  %t48 = getelementptr ptr, ptr %t38, i32 2
  %t49 = load ptr, ptr %t48
  %t50 = getelementptr ptr, ptr %t38, i32 3
  %t51 = load ptr, ptr %t50
  %t52 = call ptr @__addInt32(ptr %t47, ptr %t49)
  %t53 = getelementptr ptr, ptr %t52, i32 0
  %t54 = load ptr, ptr %t53
  %t55 = ptrtoint ptr %t54 to i64
  switch i64 %t55, label %case.default.56 [ i64 0, label %case.arm.0.58 i64 1, label %case.arm.1.62 ]
case.arm.0.58:
  %t60 = getelementptr ptr, ptr %t52, i32 1
  %t61 = load ptr, ptr %t60
  br label %case.end.0.59
case.end.0.59:
  br label %case.join.57
case.arm.1.62:
  %t64 = getelementptr ptr, ptr %t52, i32 1
  %t65 = load ptr, ptr %t64
  %t66 = call ptr @__addInt32(ptr %t65, ptr %t51)
  %t67 = getelementptr ptr, ptr %t66, i32 0
  %t68 = load ptr, ptr %t67
  %t69 = ptrtoint ptr %t68 to i64
  switch i64 %t69, label %case.default.70 [ i64 0, label %case.arm.0.72 i64 1, label %case.arm.1.76 ]
case.arm.0.72:
  %t74 = getelementptr ptr, ptr %t66, i32 1
  %t75 = load ptr, ptr %t74
  br label %case.end.0.73
case.end.0.73:
  br label %case.join.71
case.arm.1.76:
  %t78 = getelementptr ptr, ptr %t66, i32 1
  %t79 = load ptr, ptr %t78
  br label %case.end.1.77
case.end.1.77:
  br label %case.join.71
case.default.70:
  unreachable
case.join.71:
  %t80 = phi ptr [%t51, %case.end.0.73], [%t79, %case.end.1.77]
  br label %case.end.1.63
case.end.1.63:
  br label %case.join.57
case.default.56:
  unreachable
case.join.57:
  %t81 = phi ptr [%t51, %case.end.0.59], [%t80, %case.end.1.63]
  %t82 = call ptr @v_pureEither(ptr %t81)
  br label %case.end.0.45
case.end.0.45:
  br label %case.join.43
case.default.42:
  unreachable
case.join.43:
  %t83 = phi ptr [%t82, %case.end.0.45]
  br label %case.end.1.36
case.end.1.36:
  br label %case.join.22
case.default.21:
  unreachable
case.join.22:
  %t84 = phi ptr [%t27, %case.end.0.24], [%t83, %case.end.1.36]
  br label %case.end.1.14
case.end.1.14:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t85 = phi ptr [%t9, %case.end.0.6], [%t84, %case.end.1.14]
  %t86 = call ptr @v__let_1(ptr %t85)
  ret ptr %t86
}

define internal ptr @v__let_1(ptr %v_res) {
  %t0 = getelementptr ptr, ptr %v_res, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.33 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_res, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr ptr, ptr %t8, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %case.default.12 [ i64 502975519, label %case.arm.502975519.14 i64 589989748, label %case.arm.589989748.20 i64 2448244154, label %case.arm.2448244154.26 ]
case.arm.502975519.14:
  %t16 = getelementptr ptr, ptr %t8, i32 1
  %t17 = load ptr, ptr %t16
  %t18 = getelementptr [25 x i8], ptr @.str.0, i64 0, i64 0
  %t19 = call ptr @__print(ptr %t18)
  br label %case.end.502975519.15
case.end.502975519.15:
  br label %case.join.13
case.arm.589989748.20:
  %t22 = getelementptr ptr, ptr %t8, i32 1
  %t23 = load ptr, ptr %t22
  %t24 = getelementptr [16 x i8], ptr @.str.1, i64 0, i64 0
  %t25 = call ptr @__print(ptr %t24)
  br label %case.end.589989748.21
case.end.589989748.21:
  br label %case.join.13
case.arm.2448244154.26:
  %t28 = getelementptr ptr, ptr %t8, i32 1
  %t29 = load ptr, ptr %t28
  %t30 = getelementptr [12 x i8], ptr @.str.2, i64 0, i64 0
  %t31 = call ptr @__print(ptr %t30)
  br label %case.end.2448244154.27
case.end.2448244154.27:
  br label %case.join.13
case.default.12:
  unreachable
case.join.13:
  %t32 = phi ptr [%t19, %case.end.502975519.15], [%t25, %case.end.589989748.21], [%t31, %case.end.2448244154.27]
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.33:
  %t35 = getelementptr ptr, ptr %v_res, i32 1
  %t36 = load ptr, ptr %t35
  %t37 = call ptr @__showInt32(ptr %t36)
  %t38 = call ptr @__print(ptr %t37)
  br label %case.end.1.34
case.end.1.34:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t39 = phi ptr [%t32, %case.end.0.6], [%t38, %case.end.1.34]
  ret ptr %t39
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
  %right_box = call ptr @malloc(i64 16)
  %right_tag_ptr = getelementptr ptr, ptr %right_box, i32 0
  %right_tag = inttoptr i64 1 to ptr
  store ptr %right_tag, ptr %right_tag_ptr
  %right_payload_ptr = getelementptr ptr, ptr %right_box, i32 1
  store ptr %input, ptr %right_payload_ptr
  call ptr @v_main(ptr %right_box)
  ret i32 0
}
