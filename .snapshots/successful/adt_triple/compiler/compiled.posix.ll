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

@.str.0 = private unnamed_addr constant [4 x i8] c"one\00"
@.str.1 = private unnamed_addr constant [4 x i8] c"two\00"
@.str.2 = private unnamed_addr constant [6 x i8] c"three\00"
@.str.3 = private unnamed_addr constant [2 x i8] c" \00"
@.str.4 = private unnamed_addr constant [16 x i8] c"STRING_TOO_LONG\00"

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


define internal ptr @v_showTriple(ptr %v_t) {
  %t0 = getelementptr ptr, ptr %v_t, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_t, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr ptr, ptr %v_t, i32 2
  %t10 = load ptr, ptr %t9
  %t11 = getelementptr ptr, ptr %v_t, i32 3
  %t12 = load ptr, ptr %t11
  %t13 = call ptr @v_h0(ptr %t8, ptr %t10, ptr %t12)
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t14 = phi ptr [%t13, %case.end.0.6]
  ret ptr %t14
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 32)
  %t1 = inttoptr i64 0 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr [4 x i8], ptr @.str.0, i64 0, i64 0
  %t4 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t4
  %t5 = getelementptr [4 x i8], ptr @.str.1, i64 0, i64 0
  %t6 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t5, ptr %t6
  %t7 = getelementptr [6 x i8], ptr @.str.2, i64 0, i64 0
  %t8 = getelementptr ptr, ptr %t0, i32 3
  store ptr %t7, ptr %t8
  %t9 = call ptr @v_showTriple(ptr %t0)
  %t10 = call ptr @v__let_1(ptr %t9)
  ret ptr %t10
}

define internal ptr @v_h0(ptr %v_a, ptr %v_b, ptr %v_c) {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr [2 x i8], ptr @.str.3, i64 0, i64 0
  %t4 = call ptr @__concat(ptr %v_a, ptr %t3)
  %t5 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 0
  %t7 = load ptr, ptr %t6
  %t8 = ptrtoint ptr %t7 to i64
  switch i64 %t8, label %case.default.9 [ i64 0, label %case.arm.0.11 i64 1, label %case.arm.1.19 ]
case.arm.0.11:
  %t13 = getelementptr ptr, ptr %t0, i32 1
  %t14 = load ptr, ptr %t13
  %t15 = call ptr @malloc(i64 16)
  %t16 = inttoptr i64 0 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = getelementptr ptr, ptr %t15, i32 1
  store ptr %t14, ptr %t18
  br label %case.end.0.12
case.end.0.12:
  br label %case.join.10
case.arm.1.19:
  %t21 = getelementptr ptr, ptr %t0, i32 1
  %t22 = load ptr, ptr %t21
  %t23 = call ptr @malloc(i64 16)
  %t24 = inttoptr i64 1 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  %t26 = call ptr @__concat(ptr %t22, ptr %v_b)
  %t27 = getelementptr ptr, ptr %t23, i32 1
  store ptr %t26, ptr %t27
  %t28 = getelementptr ptr, ptr %t23, i32 0
  %t29 = load ptr, ptr %t28
  %t30 = ptrtoint ptr %t29 to i64
  switch i64 %t30, label %case.default.31 [ i64 0, label %case.arm.0.33 i64 1, label %case.arm.1.41 ]
case.arm.0.33:
  %t35 = getelementptr ptr, ptr %t23, i32 1
  %t36 = load ptr, ptr %t35
  %t37 = call ptr @malloc(i64 16)
  %t38 = inttoptr i64 0 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = getelementptr ptr, ptr %t37, i32 1
  store ptr %t36, ptr %t40
  br label %case.end.0.34
case.end.0.34:
  br label %case.join.32
case.arm.1.41:
  %t43 = getelementptr ptr, ptr %t23, i32 1
  %t44 = load ptr, ptr %t43
  %t45 = call ptr @malloc(i64 16)
  %t46 = inttoptr i64 1 to ptr
  %t47 = getelementptr ptr, ptr %t45, i32 0
  store ptr %t46, ptr %t47
  %t48 = getelementptr [2 x i8], ptr @.str.3, i64 0, i64 0
  %t49 = call ptr @__concat(ptr %t44, ptr %t48)
  %t50 = getelementptr ptr, ptr %t45, i32 1
  store ptr %t49, ptr %t50
  %t51 = getelementptr ptr, ptr %t45, i32 0
  %t52 = load ptr, ptr %t51
  %t53 = ptrtoint ptr %t52 to i64
  switch i64 %t53, label %case.default.54 [ i64 0, label %case.arm.0.56 i64 1, label %case.arm.1.64 ]
case.arm.0.56:
  %t58 = getelementptr ptr, ptr %t45, i32 1
  %t59 = load ptr, ptr %t58
  %t60 = call ptr @malloc(i64 16)
  %t61 = inttoptr i64 0 to ptr
  %t62 = getelementptr ptr, ptr %t60, i32 0
  store ptr %t61, ptr %t62
  %t63 = getelementptr ptr, ptr %t60, i32 1
  store ptr %t59, ptr %t63
  br label %case.end.0.57
case.end.0.57:
  br label %case.join.55
case.arm.1.64:
  %t66 = getelementptr ptr, ptr %t45, i32 1
  %t67 = load ptr, ptr %t66
  %t68 = call ptr @malloc(i64 16)
  %t69 = inttoptr i64 1 to ptr
  %t70 = getelementptr ptr, ptr %t68, i32 0
  store ptr %t69, ptr %t70
  %t71 = call ptr @__concat(ptr %t67, ptr %v_c)
  %t72 = getelementptr ptr, ptr %t68, i32 1
  store ptr %t71, ptr %t72
  br label %case.end.1.65
case.end.1.65:
  br label %case.join.55
case.default.54:
  unreachable
case.join.55:
  %t73 = phi ptr [%t60, %case.end.0.57], [%t68, %case.end.1.65]
  br label %case.end.1.42
case.end.1.42:
  br label %case.join.32
case.default.31:
  unreachable
case.join.32:
  %t74 = phi ptr [%t37, %case.end.0.34], [%t73, %case.end.1.42]
  br label %case.end.1.20
case.end.1.20:
  br label %case.join.10
case.default.9:
  unreachable
case.join.10:
  %t75 = phi ptr [%t15, %case.end.0.12], [%t74, %case.end.1.20]
  ret ptr %t75
}

define internal ptr @v__let_1(ptr %v_res) {
  %t0 = getelementptr ptr, ptr %v_res, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.11 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_res, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr [16 x i8], ptr @.str.4, i64 0, i64 0
  %t10 = call ptr @__print(ptr %t9)
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.11:
  %t13 = getelementptr ptr, ptr %v_res, i32 1
  %t14 = load ptr, ptr %t13
  %t15 = call ptr @__print(ptr %t14)
  br label %case.end.1.12
case.end.1.12:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t16 = phi ptr [%t10, %case.end.0.6], [%t15, %case.end.1.12]
  ret ptr %t16
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
