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

@.str.0 = private unnamed_addr constant [7 x i8] c"left: \00"
@.str.1 = private unnamed_addr constant [8 x i8] c"right: \00"
@.str.2 = private unnamed_addr constant [4 x i8] c"bad\00"
@.str.3 = private unnamed_addr constant [5 x i8] c"good\00"
@.str.4 = private unnamed_addr constant [3 x i8] c", \00"
@.str.5 = private unnamed_addr constant [16 x i8] c"STRING_TOO_LONG\00"

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


define internal ptr @v_unwrap(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.15 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_r, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = call ptr @malloc(i64 16)
  %t10 = inttoptr i64 1 to ptr
  %t11 = getelementptr ptr, ptr %t9, i32 0
  store ptr %t10, ptr %t11
  %t12 = getelementptr [7 x i8], ptr @.str.0, i64 0, i64 0
  %t13 = call ptr @__concat(ptr %t12, ptr %t8)
  %t14 = getelementptr ptr, ptr %t9, i32 1
  store ptr %t13, ptr %t14
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.15:
  %t17 = getelementptr ptr, ptr %v_r, i32 1
  %t18 = load ptr, ptr %t17
  %t19 = call ptr @malloc(i64 16)
  %t20 = inttoptr i64 1 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr [8 x i8], ptr @.str.1, i64 0, i64 0
  %t23 = call ptr @__concat(ptr %t22, ptr %t18)
  %t24 = getelementptr ptr, ptr %t19, i32 1
  store ptr %t23, ptr %t24
  br label %case.end.1.16
case.end.1.16:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t25 = phi ptr [%t9, %case.end.0.6], [%t19, %case.end.1.16]
  ret ptr %t25
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 0 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr [4 x i8], ptr @.str.2, i64 0, i64 0
  %t4 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t4
  %t5 = call ptr @v_unwrap(ptr %t0)
  %t6 = getelementptr ptr, ptr %t5, i32 0
  %t7 = load ptr, ptr %t6
  %t8 = ptrtoint ptr %t7 to i64
  switch i64 %t8, label %case.default.9 [ i64 0, label %case.arm.0.11 i64 1, label %case.arm.1.19 ]
case.arm.0.11:
  %t13 = getelementptr ptr, ptr %t5, i32 1
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
  %t21 = getelementptr ptr, ptr %t5, i32 1
  %t22 = load ptr, ptr %t21
  %t23 = call ptr @malloc(i64 16)
  %t24 = inttoptr i64 1 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  %t26 = getelementptr [5 x i8], ptr @.str.3, i64 0, i64 0
  %t27 = getelementptr ptr, ptr %t23, i32 1
  store ptr %t26, ptr %t27
  %t28 = call ptr @v_unwrap(ptr %t23)
  %t29 = getelementptr ptr, ptr %t28, i32 0
  %t30 = load ptr, ptr %t29
  %t31 = ptrtoint ptr %t30 to i64
  switch i64 %t31, label %case.default.32 [ i64 0, label %case.arm.0.34 i64 1, label %case.arm.1.42 ]
case.arm.0.34:
  %t36 = getelementptr ptr, ptr %t28, i32 1
  %t37 = load ptr, ptr %t36
  %t38 = call ptr @malloc(i64 16)
  %t39 = inttoptr i64 0 to ptr
  %t40 = getelementptr ptr, ptr %t38, i32 0
  store ptr %t39, ptr %t40
  %t41 = getelementptr ptr, ptr %t38, i32 1
  store ptr %t37, ptr %t41
  br label %case.end.0.35
case.end.0.35:
  br label %case.join.33
case.arm.1.42:
  %t44 = getelementptr ptr, ptr %t28, i32 1
  %t45 = load ptr, ptr %t44
  %t46 = call ptr @malloc(i64 16)
  %t47 = inttoptr i64 1 to ptr
  %t48 = getelementptr ptr, ptr %t46, i32 0
  store ptr %t47, ptr %t48
  %t49 = getelementptr [3 x i8], ptr @.str.4, i64 0, i64 0
  %t50 = call ptr @__concat(ptr %t22, ptr %t49)
  %t51 = getelementptr ptr, ptr %t46, i32 1
  store ptr %t50, ptr %t51
  %t52 = getelementptr ptr, ptr %t46, i32 0
  %t53 = load ptr, ptr %t52
  %t54 = ptrtoint ptr %t53 to i64
  switch i64 %t54, label %case.default.55 [ i64 0, label %case.arm.0.57 i64 1, label %case.arm.1.65 ]
case.arm.0.57:
  %t59 = getelementptr ptr, ptr %t46, i32 1
  %t60 = load ptr, ptr %t59
  %t61 = call ptr @malloc(i64 16)
  %t62 = inttoptr i64 0 to ptr
  %t63 = getelementptr ptr, ptr %t61, i32 0
  store ptr %t62, ptr %t63
  %t64 = getelementptr ptr, ptr %t61, i32 1
  store ptr %t60, ptr %t64
  br label %case.end.0.58
case.end.0.58:
  br label %case.join.56
case.arm.1.65:
  %t67 = getelementptr ptr, ptr %t46, i32 1
  %t68 = load ptr, ptr %t67
  %t69 = call ptr @malloc(i64 16)
  %t70 = inttoptr i64 1 to ptr
  %t71 = getelementptr ptr, ptr %t69, i32 0
  store ptr %t70, ptr %t71
  %t72 = call ptr @__concat(ptr %t68, ptr %t45)
  %t73 = getelementptr ptr, ptr %t69, i32 1
  store ptr %t72, ptr %t73
  br label %case.end.1.66
case.end.1.66:
  br label %case.join.56
case.default.55:
  unreachable
case.join.56:
  %t74 = phi ptr [%t61, %case.end.0.58], [%t69, %case.end.1.66]
  br label %case.end.1.43
case.end.1.43:
  br label %case.join.33
case.default.32:
  unreachable
case.join.33:
  %t75 = phi ptr [%t38, %case.end.0.35], [%t74, %case.end.1.43]
  br label %case.end.1.20
case.end.1.20:
  br label %case.join.10
case.default.9:
  unreachable
case.join.10:
  %t76 = phi ptr [%t15, %case.end.0.12], [%t75, %case.end.1.20]
  %t77 = call ptr @v__let_1(ptr %t76)
  ret ptr %t77
}

define internal ptr @v__let_1(ptr %v_res) {
  %t0 = getelementptr ptr, ptr %v_res, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.11 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_res, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr [16 x i8], ptr @.str.5, i64 0, i64 0
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
