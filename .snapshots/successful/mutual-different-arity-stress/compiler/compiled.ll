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
@.str.1 = private unnamed_addr constant [7 x i8] c"left: \00"
@.str.2 = private unnamed_addr constant [8 x i8] c"right: \00"

define ptr @__concat(ptr %a, ptr %b) {
  %la = call i64 @strlen(ptr %a)
  %lb = call i64 @strlen(ptr %b)
  %sum = add i64 %la, %lb
  %total = add i64 %sum, 1
  %buf = call ptr @malloc(i64 %total)
  call ptr @strcpy(ptr %buf, ptr %a)
  call ptr @strcat(ptr %buf, ptr %b)
  ret ptr %buf
}


define ptr @__print(ptr %s) {
  call i32 (ptr, ...) @printf(ptr @.fmt, ptr %s)
  ret ptr null
}


define ptr @__showInt32(ptr %p) {
  %v = load i32, ptr %p
  %buf = call ptr @malloc(i64 16)
  call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 16, ptr @.fmt_i32, i32 %v)
  ret ptr %buf
}


define ptr @__predInt32(ptr %p) {
  %v = load i32, ptr %p
  %is_min = icmp eq i32 %v, -2147483648
  br i1 %is_min, label %overflow, label %ok
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
  %newv = sub i32 %v, 1
  %box = call ptr @malloc(i64 4)
  store i32 %newv, ptr %box
  %right = call ptr @malloc(i64 16)
  %right_tag = inttoptr i64 1 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %box, ptr %right_f
  ret ptr %right
}


define ptr @__eqInt32(ptr %a, ptr %b) {
  %va = load i32, ptr %a
  %vb = load i32, ptr %b
  %eq = icmp eq i32 %va, %vb
  %tag = select i1 %eq, i64 0, i64 1
  %box = call ptr @malloc(i64 8)
  %tag_ptr = inttoptr i64 %tag to ptr
  store ptr %tag_ptr, ptr %box
  ret ptr %box
}


define ptr @v_showUnderflowError(ptr %v__wild0) {
  %t0 = getelementptr [15 x i8], ptr @.str.0, i64 0, i64 0
  ret ptr %t0
}

define ptr @v_zero() {
  %t0 = call ptr @malloc(i64 4)
  store i32 0, ptr %t0
  ret ptr %t0
}

define ptr @v_showResult(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.12 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_r, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr [7 x i8], ptr @.str.1, i64 0, i64 0
  %t10 = call ptr @v_showUnderflowError(ptr %t8)
  %t11 = call ptr @__concat(ptr %t9, ptr %t10)
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.12:
  %t14 = getelementptr ptr, ptr %v_r, i32 1
  %t15 = load ptr, ptr %t14
  %t16 = getelementptr [8 x i8], ptr @.str.2, i64 0, i64 0
  %t17 = call ptr @__showInt32(ptr %t15)
  %t18 = call ptr @__concat(ptr %t16, ptr %t17)
  br label %case.end.1.13
case.end.1.13:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t19 = phi ptr [%t11, %case.end.0.6], [%t18, %case.end.1.13]
  ret ptr %t19
}

define ptr @v_start() {
  %t0 = call ptr @malloc(i64 4)
  store i32 100000, ptr %t0
  ret ptr %t0
}

define ptr @v_main(ptr %v__input) {
  %t0 = call ptr @v_start()
  %t1 = call ptr @v_pingOne(ptr %t0)
  %t2 = call ptr @v_showResult(ptr %t1)
  %t3 = call ptr @__print(ptr %t2)
  ret ptr %t3
}

define ptr @v__scc_pingOne_pongTwo(ptr %v__args) {
entry:
  %t3 = alloca ptr
  store ptr %v__args, ptr %t3
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t4 = load ptr, ptr %t3
  %t5 = getelementptr ptr, ptr %t4, i32 0
  %t6 = load ptr, ptr %t5
  %t7 = ptrtoint ptr %t6 to i64
  switch i64 %t7, label %tco.case.default.8 [ i64 0, label %tco.case.arm.0.9 i64 1, label %tco.case.arm.1.46 ]
tco.case.arm.0.9:
  %t10 = getelementptr ptr, ptr %t4, i32 1
  %t11 = load ptr, ptr %t10
  %t12 = call ptr @v_zero()
  %t13 = call ptr @__eqInt32(ptr %t11, ptr %t12)
  %t14 = getelementptr ptr, ptr %t13, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %tco.case.default.17 [ i64 0, label %tco.case.arm.0.18 i64 1, label %tco.case.arm.1.24 ]
tco.case.arm.0.18:
  %t19 = call ptr @malloc(i64 16)
  %t20 = inttoptr i64 1 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = call ptr @v_zero()
  %t23 = getelementptr ptr, ptr %t19, i32 1
  store ptr %t22, ptr %t23
  store ptr %t19, ptr %t2
  br label %tco.exit.1
tco.case.arm.1.24:
  %t25 = call ptr @__predInt32(ptr %t11)
  %t26 = getelementptr ptr, ptr %t25, i32 0
  %t27 = load ptr, ptr %t26
  %t28 = ptrtoint ptr %t27 to i64
  switch i64 %t28, label %tco.case.default.29 [ i64 0, label %tco.case.arm.0.30 i64 1, label %tco.case.arm.1.37 ]
tco.case.arm.0.30:
  %t31 = getelementptr ptr, ptr %t25, i32 1
  %t32 = load ptr, ptr %t31
  %t33 = call ptr @malloc(i64 16)
  %t34 = inttoptr i64 0 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = getelementptr ptr, ptr %t33, i32 1
  store ptr %t32, ptr %t36
  store ptr %t33, ptr %t2
  br label %tco.exit.1
tco.case.arm.1.37:
  %t38 = getelementptr ptr, ptr %t25, i32 1
  %t39 = load ptr, ptr %t38
  %t40 = call ptr @malloc(i64 24)
  %t41 = inttoptr i64 1 to ptr
  %t42 = getelementptr ptr, ptr %t40, i32 0
  store ptr %t41, ptr %t42
  %t43 = getelementptr ptr, ptr %t40, i32 1
  store ptr %t39, ptr %t43
  %t44 = call ptr @v_zero()
  %t45 = getelementptr ptr, ptr %t40, i32 2
  store ptr %t44, ptr %t45
  store ptr %t40, ptr %t3
  br label %tco.loop.0
tco.case.default.29:
  unreachable
tco.case.default.17:
  unreachable
tco.case.arm.1.46:
  %t47 = getelementptr ptr, ptr %t4, i32 1
  %t48 = load ptr, ptr %t47
  %t49 = getelementptr ptr, ptr %t4, i32 2
  %t50 = load ptr, ptr %t49
  %t51 = call ptr @v_zero()
  %t52 = call ptr @__eqInt32(ptr %t48, ptr %t51)
  %t53 = getelementptr ptr, ptr %t52, i32 0
  %t54 = load ptr, ptr %t53
  %t55 = ptrtoint ptr %t54 to i64
  switch i64 %t55, label %tco.case.default.56 [ i64 0, label %tco.case.arm.0.57 i64 1, label %tco.case.arm.1.63 ]
tco.case.arm.0.57:
  %t58 = call ptr @malloc(i64 16)
  %t59 = inttoptr i64 1 to ptr
  %t60 = getelementptr ptr, ptr %t58, i32 0
  store ptr %t59, ptr %t60
  %t61 = call ptr @v_zero()
  %t62 = getelementptr ptr, ptr %t58, i32 1
  store ptr %t61, ptr %t62
  store ptr %t58, ptr %t2
  br label %tco.exit.1
tco.case.arm.1.63:
  %t64 = call ptr @__predInt32(ptr %t48)
  %t65 = getelementptr ptr, ptr %t64, i32 0
  %t66 = load ptr, ptr %t65
  %t67 = ptrtoint ptr %t66 to i64
  switch i64 %t67, label %tco.case.default.68 [ i64 0, label %tco.case.arm.0.69 i64 1, label %tco.case.arm.1.76 ]
tco.case.arm.0.69:
  %t70 = getelementptr ptr, ptr %t64, i32 1
  %t71 = load ptr, ptr %t70
  %t72 = call ptr @malloc(i64 16)
  %t73 = inttoptr i64 0 to ptr
  %t74 = getelementptr ptr, ptr %t72, i32 0
  store ptr %t73, ptr %t74
  %t75 = getelementptr ptr, ptr %t72, i32 1
  store ptr %t71, ptr %t75
  store ptr %t72, ptr %t2
  br label %tco.exit.1
tco.case.arm.1.76:
  %t77 = getelementptr ptr, ptr %t64, i32 1
  %t78 = load ptr, ptr %t77
  %t79 = call ptr @malloc(i64 16)
  %t80 = inttoptr i64 0 to ptr
  %t81 = getelementptr ptr, ptr %t79, i32 0
  store ptr %t80, ptr %t81
  %t82 = getelementptr ptr, ptr %t79, i32 1
  store ptr %t78, ptr %t82
  store ptr %t79, ptr %t3
  br label %tco.loop.0
tco.case.default.68:
  unreachable
tco.case.default.56:
  unreachable
tco.case.default.8:
  unreachable
tco.exit.1:
  %t83 = load ptr, ptr %t2
  ret ptr %t83
}

define ptr @v_pingOne(ptr %v_n) {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 0 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v_n, ptr %t3
  %t4 = call ptr @v__scc_pingOne_pongTwo(ptr %t0)
  ret ptr %t4
}

define ptr @v_pongTwo(ptr %v_n, ptr %v__acc) {
  %t0 = call ptr @malloc(i64 24)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v_n, ptr %t3
  %t4 = getelementptr ptr, ptr %t0, i32 2
  store ptr %v__acc, ptr %t4
  %t5 = call ptr @v__scc_pingOne_pongTwo(ptr %t0)
  ret ptr %t5
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
