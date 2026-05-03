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

@.str.0 = private unnamed_addr constant [15 x i8] c"UnderflowError\00"
@.str.1 = private unnamed_addr constant [2 x i8] c",\00"
@.str.2 = private unnamed_addr constant [16 x i8] c"STRING_TOO_LONG\00"
@.str.3 = private unnamed_addr constant [7 x i8] c"left: \00"
@.str.4 = private unnamed_addr constant [8 x i8] c"right: \00"
@.str.5 = private unnamed_addr constant [1 x i8] c"\00"

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


define internal ptr @__showUInt8(ptr %p) {
  %b = load i8, ptr %p
  %v = zext i8 %b to i32
  %buf = call ptr @malloc(i64 16)
  call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 16, ptr @.fmt_u8, i32 %v)
  ret ptr %buf
}


define internal ptr @__predUInt8(ptr %p) {
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


define internal ptr @__eqUInt8(ptr %a, ptr %b) {
  %va = load i8, ptr %a
  %vb = load i8, ptr %b
  %eq = icmp eq i8 %va, %vb
  %tag = select i1 %eq, i64 0, i64 1
  %box = call ptr @malloc(i64 8)
  %tag_ptr = inttoptr i64 %tag to ptr
  store ptr %tag_ptr, ptr %box
  ret ptr %box
}


define internal ptr @v_showUnderflowError(ptr %v__wild0) {
  %t0 = getelementptr [15 x i8], ptr @.str.0, i64 0, i64 0
  ret ptr %t0
}

define internal ptr @v_countDown(ptr %v_n, ptr %v_acc) {
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
  %t7 = call ptr @malloc(i64 1)
  store i8 0, ptr %t7
  %t8 = call ptr @__eqUInt8(ptr %t5, ptr %t7)
  %t9 = getelementptr ptr, ptr %t8, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %tco.case.default.12 [ i64 0, label %tco.case.arm.0.13 i64 1, label %tco.case.arm.1.20 ]
tco.case.arm.0.13:
  %t14 = call ptr @malloc(i64 16)
  %t15 = inttoptr i64 1 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  %t17 = call ptr @__showUInt8(ptr %t5)
  %t18 = call ptr @__concat(ptr %t6, ptr %t17)
  %t19 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t18, ptr %t19
  store ptr %t14, ptr %t2
  br label %tco.exit.1
tco.case.arm.1.20:
  %t21 = call ptr @__predUInt8(ptr %t5)
  %t22 = getelementptr ptr, ptr %t21, i32 0
  %t23 = load ptr, ptr %t22
  %t24 = ptrtoint ptr %t23 to i64
  switch i64 %t24, label %tco.case.default.25 [ i64 0, label %tco.case.arm.0.26 i64 1, label %tco.case.arm.1.37 ]
tco.case.arm.0.26:
  %t27 = getelementptr ptr, ptr %t21, i32 1
  %t28 = load ptr, ptr %t27
  %t29 = call ptr @malloc(i64 16)
  %t30 = inttoptr i64 0 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = call ptr @malloc(i64 16)
  %t33 = inttoptr i64 3768445577 to ptr
  %t34 = getelementptr ptr, ptr %t32, i32 0
  store ptr %t33, ptr %t34
  %t35 = getelementptr ptr, ptr %t32, i32 1
  store ptr %t28, ptr %t35
  %t36 = getelementptr ptr, ptr %t29, i32 1
  store ptr %t32, ptr %t36
  store ptr %t29, ptr %t2
  br label %tco.exit.1
tco.case.arm.1.37:
  %t38 = getelementptr ptr, ptr %t21, i32 1
  %t39 = load ptr, ptr %t38
  %t40 = call ptr @malloc(i64 16)
  %t41 = inttoptr i64 1 to ptr
  %t42 = getelementptr ptr, ptr %t40, i32 0
  store ptr %t41, ptr %t42
  %t43 = call ptr @__showUInt8(ptr %t5)
  %t44 = call ptr @__concat(ptr %t6, ptr %t43)
  %t45 = getelementptr ptr, ptr %t40, i32 1
  store ptr %t44, ptr %t45
  %t46 = getelementptr ptr, ptr %t40, i32 0
  %t47 = load ptr, ptr %t46
  %t48 = ptrtoint ptr %t47 to i64
  switch i64 %t48, label %tco.case.default.49 [ i64 0, label %tco.case.arm.0.50 i64 1, label %tco.case.arm.1.61 ]
tco.case.arm.0.50:
  %t51 = getelementptr ptr, ptr %t40, i32 1
  %t52 = load ptr, ptr %t51
  %t53 = call ptr @malloc(i64 16)
  %t54 = inttoptr i64 0 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  %t56 = call ptr @malloc(i64 16)
  %t57 = inttoptr i64 3768445577 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  %t59 = getelementptr ptr, ptr %t56, i32 1
  store ptr %t52, ptr %t59
  %t60 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t56, ptr %t60
  store ptr %t53, ptr %t2
  br label %tco.exit.1
tco.case.arm.1.61:
  %t62 = getelementptr ptr, ptr %t40, i32 1
  %t63 = load ptr, ptr %t62
  %t64 = call ptr @malloc(i64 16)
  %t65 = inttoptr i64 1 to ptr
  %t66 = getelementptr ptr, ptr %t64, i32 0
  store ptr %t65, ptr %t66
  %t67 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  %t68 = call ptr @__concat(ptr %t63, ptr %t67)
  %t69 = getelementptr ptr, ptr %t64, i32 1
  store ptr %t68, ptr %t69
  %t70 = getelementptr ptr, ptr %t64, i32 0
  %t71 = load ptr, ptr %t70
  %t72 = ptrtoint ptr %t71 to i64
  switch i64 %t72, label %tco.case.default.73 [ i64 0, label %tco.case.arm.0.74 i64 1, label %tco.case.arm.1.85 ]
tco.case.arm.0.74:
  %t75 = getelementptr ptr, ptr %t64, i32 1
  %t76 = load ptr, ptr %t75
  %t77 = call ptr @malloc(i64 16)
  %t78 = inttoptr i64 0 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  %t80 = call ptr @malloc(i64 16)
  %t81 = inttoptr i64 3768445577 to ptr
  %t82 = getelementptr ptr, ptr %t80, i32 0
  store ptr %t81, ptr %t82
  %t83 = getelementptr ptr, ptr %t80, i32 1
  store ptr %t76, ptr %t83
  %t84 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t80, ptr %t84
  store ptr %t77, ptr %t2
  br label %tco.exit.1
tco.case.arm.1.85:
  %t86 = getelementptr ptr, ptr %t64, i32 1
  %t87 = load ptr, ptr %t86
  store ptr %t39, ptr %t3
  store ptr %t87, ptr %t4
  br label %tco.loop.0
tco.case.default.73:
  unreachable
tco.case.default.49:
  unreachable
tco.case.default.25:
  unreachable
tco.case.default.12:
  unreachable
tco.exit.1:
  %t88 = load ptr, ptr %t2
  ret ptr %t88
}

define internal ptr @v_showResult(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.35 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_r, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr ptr, ptr %t8, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %case.default.12 [ i64 589989748, label %case.arm.589989748.14 i64 3768445577, label %case.arm.3768445577.23 ]
case.arm.589989748.14:
  %t16 = getelementptr ptr, ptr %t8, i32 1
  %t17 = load ptr, ptr %t16
  %t18 = call ptr @malloc(i64 16)
  %t19 = inttoptr i64 1 to ptr
  %t20 = getelementptr ptr, ptr %t18, i32 0
  store ptr %t19, ptr %t20
  %t21 = getelementptr [16 x i8], ptr @.str.2, i64 0, i64 0
  %t22 = getelementptr ptr, ptr %t18, i32 1
  store ptr %t21, ptr %t22
  br label %case.end.589989748.15
case.end.589989748.15:
  br label %case.join.13
case.arm.3768445577.23:
  %t25 = getelementptr ptr, ptr %t8, i32 1
  %t26 = load ptr, ptr %t25
  %t27 = call ptr @malloc(i64 16)
  %t28 = inttoptr i64 1 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  %t30 = getelementptr [7 x i8], ptr @.str.3, i64 0, i64 0
  %t31 = call ptr @v_showUnderflowError(ptr %t26)
  %t32 = call ptr @__concat(ptr %t30, ptr %t31)
  %t33 = getelementptr ptr, ptr %t27, i32 1
  store ptr %t32, ptr %t33
  br label %case.end.3768445577.24
case.end.3768445577.24:
  br label %case.join.13
case.default.12:
  unreachable
case.join.13:
  %t34 = phi ptr [%t18, %case.end.589989748.15], [%t27, %case.end.3768445577.24]
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.35:
  %t37 = getelementptr ptr, ptr %v_r, i32 1
  %t38 = load ptr, ptr %t37
  %t39 = call ptr @malloc(i64 16)
  %t40 = inttoptr i64 1 to ptr
  %t41 = getelementptr ptr, ptr %t39, i32 0
  store ptr %t40, ptr %t41
  %t42 = getelementptr [8 x i8], ptr @.str.4, i64 0, i64 0
  %t43 = call ptr @__concat(ptr %t42, ptr %t38)
  %t44 = getelementptr ptr, ptr %t39, i32 1
  store ptr %t43, ptr %t44
  br label %case.end.1.36
case.end.1.36:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t45 = phi ptr [%t34, %case.end.0.6], [%t39, %case.end.1.36]
  ret ptr %t45
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 1)
  store i8 255, ptr %t0
  %t1 = getelementptr [1 x i8], ptr @.str.5, i64 0, i64 0
  %t2 = call ptr @v_countDown(ptr %t0, ptr %t1)
  %t3 = call ptr @v_showResult(ptr %t2)
  %t4 = call ptr @v__let_1(ptr %t3)
  ret ptr %t4
}

define internal ptr @v__let_1(ptr %v_res) {
  %t0 = getelementptr ptr, ptr %v_res, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.11 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_res, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr [16 x i8], ptr @.str.2, i64 0, i64 0
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
