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
@.str.1 = private unnamed_addr constant [5 x i8] c"true\00"
@.str.2 = private unnamed_addr constant [6 x i8] c"false\00"
@.str.3 = private unnamed_addr constant [7 x i8] c"left: \00"
@.str.4 = private unnamed_addr constant [8 x i8] c"right: \00"

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


define internal ptr @__predInt32(ptr %p) {
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


define internal ptr @__eqInt32(ptr %a, ptr %b) {
  %va = load i32, ptr %a
  %vb = load i32, ptr %b
  %eq = icmp eq i32 %va, %vb
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

define internal ptr @v_showBool(ptr %v_b) {
  %t0 = getelementptr ptr, ptr %v_b, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.8 ]
case.arm.0.5:
  %t7 = getelementptr [5 x i8], ptr @.str.1, i64 0, i64 0
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.8:
  %t10 = getelementptr [6 x i8], ptr @.str.2, i64 0, i64 0
  br label %case.end.1.9
case.end.1.9:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t11 = phi ptr [%t7, %case.end.0.6], [%t10, %case.end.1.9]
  ret ptr %t11
}

define internal ptr @v_showResult(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.12 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_r, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr [7 x i8], ptr @.str.3, i64 0, i64 0
  %t10 = call ptr @v_showUnderflowError(ptr %t8)
  %t11 = call ptr @__concat(ptr %t9, ptr %t10)
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.12:
  %t14 = getelementptr ptr, ptr %v_r, i32 1
  %t15 = load ptr, ptr %t14
  %t16 = getelementptr [8 x i8], ptr @.str.4, i64 0, i64 0
  %t17 = call ptr @v_showBool(ptr %t15)
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

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 4)
  store i32 1000000, ptr %t0
  %t1 = call ptr @v_evenInt(ptr %t0)
  %t2 = call ptr @v_showResult(ptr %t1)
  %t3 = call ptr @__print(ptr %t2)
  ret ptr %t3
}

define internal ptr @v__scc_evenInt_oddInt(ptr %v__args) {
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
  %t12 = call ptr @malloc(i64 4)
  store i32 0, ptr %t12
  %t13 = call ptr @__eqInt32(ptr %t11, ptr %t12)
  %t14 = getelementptr ptr, ptr %t13, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %tco.case.default.17 [ i64 0, label %tco.case.arm.0.18 i64 1, label %tco.case.arm.1.26 ]
tco.case.arm.0.18:
  %t19 = call ptr @malloc(i64 16)
  %t20 = inttoptr i64 1 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = call ptr @malloc(i64 8)
  %t23 = inttoptr i64 0 to ptr
  %t24 = getelementptr ptr, ptr %t22, i32 0
  store ptr %t23, ptr %t24
  %t25 = getelementptr ptr, ptr %t19, i32 1
  store ptr %t22, ptr %t25
  store ptr %t19, ptr %t2
  br label %tco.exit.1
tco.case.arm.1.26:
  %t27 = call ptr @__predInt32(ptr %t11)
  %t28 = getelementptr ptr, ptr %t27, i32 0
  %t29 = load ptr, ptr %t28
  %t30 = ptrtoint ptr %t29 to i64
  switch i64 %t30, label %tco.case.default.31 [ i64 0, label %tco.case.arm.0.32 i64 1, label %tco.case.arm.1.39 ]
tco.case.arm.0.32:
  %t33 = getelementptr ptr, ptr %t27, i32 1
  %t34 = load ptr, ptr %t33
  %t35 = call ptr @malloc(i64 16)
  %t36 = inttoptr i64 0 to ptr
  %t37 = getelementptr ptr, ptr %t35, i32 0
  store ptr %t36, ptr %t37
  %t38 = getelementptr ptr, ptr %t35, i32 1
  store ptr %t34, ptr %t38
  store ptr %t35, ptr %t2
  br label %tco.exit.1
tco.case.arm.1.39:
  %t40 = getelementptr ptr, ptr %t27, i32 1
  %t41 = load ptr, ptr %t40
  %t42 = call ptr @malloc(i64 16)
  %t43 = inttoptr i64 1 to ptr
  %t44 = getelementptr ptr, ptr %t42, i32 0
  store ptr %t43, ptr %t44
  %t45 = getelementptr ptr, ptr %t42, i32 1
  store ptr %t41, ptr %t45
  store ptr %t42, ptr %t3
  br label %tco.loop.0
tco.case.default.31:
  unreachable
tco.case.default.17:
  unreachable
tco.case.arm.1.46:
  %t47 = getelementptr ptr, ptr %t4, i32 1
  %t48 = load ptr, ptr %t47
  %t49 = call ptr @malloc(i64 4)
  store i32 0, ptr %t49
  %t50 = call ptr @__eqInt32(ptr %t48, ptr %t49)
  %t51 = getelementptr ptr, ptr %t50, i32 0
  %t52 = load ptr, ptr %t51
  %t53 = ptrtoint ptr %t52 to i64
  switch i64 %t53, label %tco.case.default.54 [ i64 0, label %tco.case.arm.0.55 i64 1, label %tco.case.arm.1.63 ]
tco.case.arm.0.55:
  %t56 = call ptr @malloc(i64 16)
  %t57 = inttoptr i64 1 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  %t59 = call ptr @malloc(i64 8)
  %t60 = inttoptr i64 1 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  %t62 = getelementptr ptr, ptr %t56, i32 1
  store ptr %t59, ptr %t62
  store ptr %t56, ptr %t2
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
tco.case.default.54:
  unreachable
tco.case.default.8:
  unreachable
tco.exit.1:
  %t83 = load ptr, ptr %t2
  ret ptr %t83
}

define internal ptr @v_evenInt(ptr %v_n) {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 0 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v_n, ptr %t3
  %t4 = call ptr @v__scc_evenInt_oddInt(ptr %t0)
  ret ptr %t4
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
