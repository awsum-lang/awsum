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

@.str.0 = private unnamed_addr constant [1 x i8] c"\00"
@.str.1 = private unnamed_addr constant [2 x i8] c"A\00"
@.str.2 = private unnamed_addr constant [2 x i8] c"B\00"
@.str.3 = private unnamed_addr constant [2 x i8] c"C\00"

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


define ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 8)
  %t1 = inttoptr i64 0 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_handleA(ptr %t0)
  %t4 = call ptr @__print(ptr %t3)
  ret ptr %t4
}

define ptr @v__scc_handleA_handleB(ptr %v__fn, ptr %v__arg_0) {
  %t0 = call ptr @malloc(i64 8)
  %t1 = inttoptr i64 0 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__scc_handleA_handleB(ptr %v__fn, ptr %v__arg_0, ptr %t0)
  ret ptr %t3
}

define ptr @v__cps__scc_handleA_handleB(ptr %v__fn, ptr %v__arg_0, ptr %v__k) {
entry:
  %t3 = alloca ptr
  store ptr %v__fn, ptr %t3
  %t4 = alloca ptr
  store ptr %v__arg_0, ptr %t4
  %t5 = alloca ptr
  store ptr %v__k, ptr %t5
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t6 = load ptr, ptr %t3
  %t7 = load ptr, ptr %t4
  %t8 = load ptr, ptr %t5
  %t9 = getelementptr ptr, ptr %t6, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %tco.case.default.12 [ i64 0, label %tco.case.arm.0.13 i64 1, label %tco.case.arm.1.40 ]
tco.case.arm.0.13:
  %t14 = getelementptr ptr, ptr %t7, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %tco.case.default.17 [ i64 0, label %tco.case.arm.0.18 i64 1, label %tco.case.arm.1.29 i64 2, label %tco.case.arm.2.33 i64 3, label %tco.case.arm.3.37 ]
tco.case.arm.0.18:
  %t19 = call ptr @malloc(i64 8)
  %t20 = inttoptr i64 1 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = call ptr @malloc(i64 8)
  %t23 = inttoptr i64 1 to ptr
  %t24 = getelementptr ptr, ptr %t22, i32 0
  store ptr %t23, ptr %t24
  %t25 = call ptr @malloc(i64 16)
  %t26 = inttoptr i64 1 to ptr
  %t27 = getelementptr ptr, ptr %t25, i32 0
  store ptr %t26, ptr %t27
  %t28 = getelementptr ptr, ptr %t25, i32 1
  store ptr %t8, ptr %t28
  store ptr %t19, ptr %t3
  store ptr %t22, ptr %t4
  store ptr %t25, ptr %t5
  br label %tco.loop.0
tco.case.arm.1.29:
  %t30 = call ptr @malloc(i64 8)
  %t31 = inttoptr i64 1 to ptr
  %t32 = getelementptr ptr, ptr %t30, i32 0
  store ptr %t31, ptr %t32
  store ptr %t30, ptr %t3
  store ptr %t7, ptr %t4
  store ptr %t8, ptr %t5
  br label %tco.loop.0
tco.case.arm.2.33:
  %t34 = call ptr @malloc(i64 8)
  %t35 = inttoptr i64 1 to ptr
  %t36 = getelementptr ptr, ptr %t34, i32 0
  store ptr %t35, ptr %t36
  store ptr %t34, ptr %t3
  store ptr %t7, ptr %t4
  store ptr %t8, ptr %t5
  br label %tco.loop.0
tco.case.arm.3.37:
  %t38 = getelementptr [1 x i8], ptr @.str.0, i64 0, i64 0
  %t39 = call ptr @v__apply__scc_handleA_handleB(ptr %t8, ptr %t38)
  store ptr %t39, ptr %t2
  br label %tco.exit.1
tco.case.default.17:
  unreachable
tco.case.arm.1.40:
  %t41 = getelementptr ptr, ptr %t7, i32 0
  %t42 = load ptr, ptr %t41
  %t43 = ptrtoint ptr %t42 to i64
  switch i64 %t43, label %tco.case.default.44 [ i64 0, label %tco.case.arm.0.45 i64 1, label %tco.case.arm.1.49 i64 2, label %tco.case.arm.2.60 i64 3, label %tco.case.arm.3.71 ]
tco.case.arm.0.45:
  %t46 = call ptr @malloc(i64 8)
  %t47 = inttoptr i64 0 to ptr
  %t48 = getelementptr ptr, ptr %t46, i32 0
  store ptr %t47, ptr %t48
  store ptr %t46, ptr %t3
  store ptr %t7, ptr %t4
  store ptr %t8, ptr %t5
  br label %tco.loop.0
tco.case.arm.1.49:
  %t50 = call ptr @malloc(i64 8)
  %t51 = inttoptr i64 0 to ptr
  %t52 = getelementptr ptr, ptr %t50, i32 0
  store ptr %t51, ptr %t52
  %t53 = call ptr @malloc(i64 8)
  %t54 = inttoptr i64 2 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  %t56 = call ptr @malloc(i64 16)
  %t57 = inttoptr i64 2 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  %t59 = getelementptr ptr, ptr %t56, i32 1
  store ptr %t8, ptr %t59
  store ptr %t50, ptr %t3
  store ptr %t53, ptr %t4
  store ptr %t56, ptr %t5
  br label %tco.loop.0
tco.case.arm.2.60:
  %t61 = call ptr @malloc(i64 8)
  %t62 = inttoptr i64 0 to ptr
  %t63 = getelementptr ptr, ptr %t61, i32 0
  store ptr %t62, ptr %t63
  %t64 = call ptr @malloc(i64 8)
  %t65 = inttoptr i64 3 to ptr
  %t66 = getelementptr ptr, ptr %t64, i32 0
  store ptr %t65, ptr %t66
  %t67 = call ptr @malloc(i64 16)
  %t68 = inttoptr i64 3 to ptr
  %t69 = getelementptr ptr, ptr %t67, i32 0
  store ptr %t68, ptr %t69
  %t70 = getelementptr ptr, ptr %t67, i32 1
  store ptr %t8, ptr %t70
  store ptr %t61, ptr %t3
  store ptr %t64, ptr %t4
  store ptr %t67, ptr %t5
  br label %tco.loop.0
tco.case.arm.3.71:
  %t72 = getelementptr [1 x i8], ptr @.str.0, i64 0, i64 0
  %t73 = call ptr @v__apply__scc_handleA_handleB(ptr %t8, ptr %t72)
  store ptr %t73, ptr %t2
  br label %tco.exit.1
tco.case.default.44:
  unreachable
tco.case.default.12:
  unreachable
tco.exit.1:
  %t74 = load ptr, ptr %t2
  ret ptr %t74
}

define ptr @v__apply__scc_handleA_handleB(ptr %v__k, ptr %v__x) {
entry:
  %t3 = alloca ptr
  store ptr %v__k, ptr %t3
  %t4 = alloca ptr
  store ptr %v__x, ptr %t4
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t5 = load ptr, ptr %t3
  %t6 = load ptr, ptr %t4
  %t7 = getelementptr ptr, ptr %t5, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %tco.case.default.10 [ i64 0, label %tco.case.arm.0.11 i64 1, label %tco.case.arm.1.12 i64 2, label %tco.case.arm.2.17 i64 3, label %tco.case.arm.3.22 ]
tco.case.arm.0.11:
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.1.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  %t15 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  %t16 = call ptr @__concat(ptr %t15, ptr %t6)
  store ptr %t14, ptr %t3
  store ptr %t16, ptr %t4
  br label %tco.loop.0
tco.case.arm.2.17:
  %t18 = getelementptr ptr, ptr %t5, i32 1
  %t19 = load ptr, ptr %t18
  %t20 = getelementptr [2 x i8], ptr @.str.2, i64 0, i64 0
  %t21 = call ptr @__concat(ptr %t20, ptr %t6)
  store ptr %t19, ptr %t3
  store ptr %t21, ptr %t4
  br label %tco.loop.0
tco.case.arm.3.22:
  %t23 = getelementptr ptr, ptr %t5, i32 1
  %t24 = load ptr, ptr %t23
  %t25 = getelementptr [2 x i8], ptr @.str.3, i64 0, i64 0
  %t26 = call ptr @__concat(ptr %t25, ptr %t6)
  store ptr %t24, ptr %t3
  store ptr %t26, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t27 = load ptr, ptr %t2
  ret ptr %t27
}

define ptr @v_handleA(ptr %v_step) {
  %t0 = call ptr @malloc(i64 8)
  %t1 = inttoptr i64 0 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__scc_handleA_handleB(ptr %t0, ptr %v_step)
  ret ptr %t3
}

define ptr @v_handleB(ptr %v_step) {
  %t0 = call ptr @malloc(i64 8)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__scc_handleA_handleB(ptr %t0, ptr %v_step)
  ret ptr %t3
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
