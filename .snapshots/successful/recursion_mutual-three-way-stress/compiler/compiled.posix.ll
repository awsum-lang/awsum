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
@.str.3 = private unnamed_addr constant [16 x i8] c"STRING_TOO_LONG\00"

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

define internal ptr @v_showResult(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.16 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_r, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = call ptr @malloc(i64 16)
  %t10 = inttoptr i64 1 to ptr
  %t11 = getelementptr ptr, ptr %t9, i32 0
  store ptr %t10, ptr %t11
  %t12 = getelementptr [7 x i8], ptr @.str.1, i64 0, i64 0
  %t13 = call ptr @v_showUnderflowError(ptr %t8)
  %t14 = call ptr @__concat(ptr %t12, ptr %t13)
  %t15 = getelementptr ptr, ptr %t9, i32 1
  store ptr %t14, ptr %t15
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.16:
  %t18 = getelementptr ptr, ptr %v_r, i32 1
  %t19 = load ptr, ptr %t18
  %t20 = call ptr @malloc(i64 16)
  %t21 = inttoptr i64 1 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = getelementptr [8 x i8], ptr @.str.2, i64 0, i64 0
  %t24 = call ptr @__showInt32(ptr %t19)
  %t25 = call ptr @__concat(ptr %t23, ptr %t24)
  %t26 = getelementptr ptr, ptr %t20, i32 1
  store ptr %t25, ptr %t26
  br label %case.end.1.17
case.end.1.17:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t27 = phi ptr [%t9, %case.end.0.6], [%t20, %case.end.1.17]
  ret ptr %t27
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 4)
  store i32 1000000, ptr %t0
  %t1 = call ptr @v_stepA(ptr %t0)
  %t2 = call ptr @v_showResult(ptr %t1)
  %t3 = call ptr @v__let_1(ptr %t2)
  ret ptr %t3
}

define internal ptr @v__let_1(ptr %v_res) {
  %t0 = getelementptr ptr, ptr %v_res, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.11 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_res, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr [16 x i8], ptr @.str.3, i64 0, i64 0
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

define internal ptr @v__scc_stepA_stepB_stepC(ptr %v__args) {
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
  switch i64 %t7, label %tco.case.default.8 [ i64 0, label %tco.case.arm.0.9 i64 1, label %tco.case.arm.1.44 i64 2, label %tco.case.arm.2.79 ]
tco.case.arm.0.9:
  %t10 = getelementptr ptr, ptr %t4, i32 1
  %t11 = load ptr, ptr %t10
  %t12 = call ptr @malloc(i64 4)
  store i32 0, ptr %t12
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
  %t22 = call ptr @malloc(i64 4)
  store i32 0, ptr %t22
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
  %t40 = call ptr @malloc(i64 16)
  %t41 = inttoptr i64 1 to ptr
  %t42 = getelementptr ptr, ptr %t40, i32 0
  store ptr %t41, ptr %t42
  %t43 = getelementptr ptr, ptr %t40, i32 1
  store ptr %t39, ptr %t43
  store ptr %t40, ptr %t3
  br label %tco.loop.0
tco.case.default.29:
  unreachable
tco.case.default.17:
  unreachable
tco.case.arm.1.44:
  %t45 = getelementptr ptr, ptr %t4, i32 1
  %t46 = load ptr, ptr %t45
  %t47 = call ptr @malloc(i64 4)
  store i32 0, ptr %t47
  %t48 = call ptr @__eqInt32(ptr %t46, ptr %t47)
  %t49 = getelementptr ptr, ptr %t48, i32 0
  %t50 = load ptr, ptr %t49
  %t51 = ptrtoint ptr %t50 to i64
  switch i64 %t51, label %tco.case.default.52 [ i64 0, label %tco.case.arm.0.53 i64 1, label %tco.case.arm.1.59 ]
tco.case.arm.0.53:
  %t54 = call ptr @malloc(i64 16)
  %t55 = inttoptr i64 1 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  %t57 = call ptr @malloc(i64 4)
  store i32 0, ptr %t57
  %t58 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t57, ptr %t58
  store ptr %t54, ptr %t2
  br label %tco.exit.1
tco.case.arm.1.59:
  %t60 = call ptr @__predInt32(ptr %t46)
  %t61 = getelementptr ptr, ptr %t60, i32 0
  %t62 = load ptr, ptr %t61
  %t63 = ptrtoint ptr %t62 to i64
  switch i64 %t63, label %tco.case.default.64 [ i64 0, label %tco.case.arm.0.65 i64 1, label %tco.case.arm.1.72 ]
tco.case.arm.0.65:
  %t66 = getelementptr ptr, ptr %t60, i32 1
  %t67 = load ptr, ptr %t66
  %t68 = call ptr @malloc(i64 16)
  %t69 = inttoptr i64 0 to ptr
  %t70 = getelementptr ptr, ptr %t68, i32 0
  store ptr %t69, ptr %t70
  %t71 = getelementptr ptr, ptr %t68, i32 1
  store ptr %t67, ptr %t71
  store ptr %t68, ptr %t2
  br label %tco.exit.1
tco.case.arm.1.72:
  %t73 = getelementptr ptr, ptr %t60, i32 1
  %t74 = load ptr, ptr %t73
  %t75 = call ptr @malloc(i64 16)
  %t76 = inttoptr i64 2 to ptr
  %t77 = getelementptr ptr, ptr %t75, i32 0
  store ptr %t76, ptr %t77
  %t78 = getelementptr ptr, ptr %t75, i32 1
  store ptr %t74, ptr %t78
  store ptr %t75, ptr %t3
  br label %tco.loop.0
tco.case.default.64:
  unreachable
tco.case.default.52:
  unreachable
tco.case.arm.2.79:
  %t80 = getelementptr ptr, ptr %t4, i32 1
  %t81 = load ptr, ptr %t80
  %t82 = call ptr @malloc(i64 4)
  store i32 0, ptr %t82
  %t83 = call ptr @__eqInt32(ptr %t81, ptr %t82)
  %t84 = getelementptr ptr, ptr %t83, i32 0
  %t85 = load ptr, ptr %t84
  %t86 = ptrtoint ptr %t85 to i64
  switch i64 %t86, label %tco.case.default.87 [ i64 0, label %tco.case.arm.0.88 i64 1, label %tco.case.arm.1.94 ]
tco.case.arm.0.88:
  %t89 = call ptr @malloc(i64 16)
  %t90 = inttoptr i64 1 to ptr
  %t91 = getelementptr ptr, ptr %t89, i32 0
  store ptr %t90, ptr %t91
  %t92 = call ptr @malloc(i64 4)
  store i32 0, ptr %t92
  %t93 = getelementptr ptr, ptr %t89, i32 1
  store ptr %t92, ptr %t93
  store ptr %t89, ptr %t2
  br label %tco.exit.1
tco.case.arm.1.94:
  %t95 = call ptr @__predInt32(ptr %t81)
  %t96 = getelementptr ptr, ptr %t95, i32 0
  %t97 = load ptr, ptr %t96
  %t98 = ptrtoint ptr %t97 to i64
  switch i64 %t98, label %tco.case.default.99 [ i64 0, label %tco.case.arm.0.100 i64 1, label %tco.case.arm.1.107 ]
tco.case.arm.0.100:
  %t101 = getelementptr ptr, ptr %t95, i32 1
  %t102 = load ptr, ptr %t101
  %t103 = call ptr @malloc(i64 16)
  %t104 = inttoptr i64 0 to ptr
  %t105 = getelementptr ptr, ptr %t103, i32 0
  store ptr %t104, ptr %t105
  %t106 = getelementptr ptr, ptr %t103, i32 1
  store ptr %t102, ptr %t106
  store ptr %t103, ptr %t2
  br label %tco.exit.1
tco.case.arm.1.107:
  %t108 = getelementptr ptr, ptr %t95, i32 1
  %t109 = load ptr, ptr %t108
  %t110 = call ptr @malloc(i64 16)
  %t111 = inttoptr i64 0 to ptr
  %t112 = getelementptr ptr, ptr %t110, i32 0
  store ptr %t111, ptr %t112
  %t113 = getelementptr ptr, ptr %t110, i32 1
  store ptr %t109, ptr %t113
  store ptr %t110, ptr %t3
  br label %tco.loop.0
tco.case.default.99:
  unreachable
tco.case.default.87:
  unreachable
tco.case.default.8:
  unreachable
tco.exit.1:
  %t114 = load ptr, ptr %t2
  ret ptr %t114
}

define internal ptr @v_stepA(ptr %v_n) {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 0 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v_n, ptr %t3
  %t4 = call ptr @v__scc_stepA_stepB_stepC(ptr %t0)
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
  %right_box = call ptr @malloc(i64 16)
  %right_tag_ptr = getelementptr ptr, ptr %right_box, i32 0
  %right_tag = inttoptr i64 1 to ptr
  store ptr %right_tag, ptr %right_tag_ptr
  %right_payload_ptr = getelementptr ptr, ptr %right_box, i32 1
  store ptr %input, ptr %right_payload_ptr
  call ptr @v_main(ptr %right_box)
  ret i32 0
}
