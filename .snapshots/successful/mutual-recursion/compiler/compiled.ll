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

define ptr @v__scc_handleA_handleB(ptr %v__args) {
  %t0 = call ptr @malloc(i64 8)
  %t1 = inttoptr i64 0 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__scc_handleA_handleB(ptr %v__args, ptr %t0)
  ret ptr %t3
}

define ptr @v__cps__scc_handleA_handleB(ptr %v__args, ptr %v__k) {
entry:
  %t3 = alloca ptr
  store ptr %v__args, ptr %t3
  %t4 = alloca ptr
  store ptr %v__k, ptr %t4
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t5 = load ptr, ptr %t3
  %t6 = load ptr, ptr %t4
  %t7 = getelementptr ptr, ptr %t5, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %tco.case.default.10 [ i64 0, label %tco.case.arm.0.11 i64 1, label %tco.case.arm.1.43 ]
tco.case.arm.0.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  %t14 = getelementptr ptr, ptr %t13, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %tco.case.default.17 [ i64 0, label %tco.case.arm.0.18 i64 1, label %tco.case.arm.1.30 i64 2, label %tco.case.arm.2.35 i64 3, label %tco.case.arm.3.40 ]
tco.case.arm.0.18:
  %t19 = call ptr @malloc(i64 16)
  %t20 = inttoptr i64 1 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = call ptr @malloc(i64 8)
  %t23 = inttoptr i64 1 to ptr
  %t24 = getelementptr ptr, ptr %t22, i32 0
  store ptr %t23, ptr %t24
  %t25 = getelementptr ptr, ptr %t19, i32 1
  store ptr %t22, ptr %t25
  %t26 = call ptr @malloc(i64 16)
  %t27 = inttoptr i64 1 to ptr
  %t28 = getelementptr ptr, ptr %t26, i32 0
  store ptr %t27, ptr %t28
  %t29 = getelementptr ptr, ptr %t26, i32 1
  store ptr %t6, ptr %t29
  store ptr %t19, ptr %t3
  store ptr %t26, ptr %t4
  br label %tco.loop.0
tco.case.arm.1.30:
  %t31 = call ptr @malloc(i64 16)
  %t32 = inttoptr i64 1 to ptr
  %t33 = getelementptr ptr, ptr %t31, i32 0
  store ptr %t32, ptr %t33
  %t34 = getelementptr ptr, ptr %t31, i32 1
  store ptr %t13, ptr %t34
  store ptr %t31, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.2.35:
  %t36 = call ptr @malloc(i64 16)
  %t37 = inttoptr i64 1 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t13, ptr %t39
  store ptr %t36, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.3.40:
  %t41 = getelementptr [1 x i8], ptr @.str.0, i64 0, i64 0
  %t42 = call ptr @v__apply__scc_handleA_handleB(ptr %t6, ptr %t41)
  store ptr %t42, ptr %t2
  br label %tco.exit.1
tco.case.default.17:
  unreachable
tco.case.arm.1.43:
  %t44 = getelementptr ptr, ptr %t5, i32 1
  %t45 = load ptr, ptr %t44
  %t46 = getelementptr ptr, ptr %t45, i32 0
  %t47 = load ptr, ptr %t46
  %t48 = ptrtoint ptr %t47 to i64
  switch i64 %t48, label %tco.case.default.49 [ i64 0, label %tco.case.arm.0.50 i64 1, label %tco.case.arm.1.55 i64 2, label %tco.case.arm.2.67 i64 3, label %tco.case.arm.3.79 ]
tco.case.arm.0.50:
  %t51 = call ptr @malloc(i64 16)
  %t52 = inttoptr i64 0 to ptr
  %t53 = getelementptr ptr, ptr %t51, i32 0
  store ptr %t52, ptr %t53
  %t54 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t45, ptr %t54
  store ptr %t51, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.1.55:
  %t56 = call ptr @malloc(i64 16)
  %t57 = inttoptr i64 0 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  %t59 = call ptr @malloc(i64 8)
  %t60 = inttoptr i64 2 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  %t62 = getelementptr ptr, ptr %t56, i32 1
  store ptr %t59, ptr %t62
  %t63 = call ptr @malloc(i64 16)
  %t64 = inttoptr i64 2 to ptr
  %t65 = getelementptr ptr, ptr %t63, i32 0
  store ptr %t64, ptr %t65
  %t66 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t6, ptr %t66
  store ptr %t56, ptr %t3
  store ptr %t63, ptr %t4
  br label %tco.loop.0
tco.case.arm.2.67:
  %t68 = call ptr @malloc(i64 16)
  %t69 = inttoptr i64 0 to ptr
  %t70 = getelementptr ptr, ptr %t68, i32 0
  store ptr %t69, ptr %t70
  %t71 = call ptr @malloc(i64 8)
  %t72 = inttoptr i64 3 to ptr
  %t73 = getelementptr ptr, ptr %t71, i32 0
  store ptr %t72, ptr %t73
  %t74 = getelementptr ptr, ptr %t68, i32 1
  store ptr %t71, ptr %t74
  %t75 = call ptr @malloc(i64 16)
  %t76 = inttoptr i64 3 to ptr
  %t77 = getelementptr ptr, ptr %t75, i32 0
  store ptr %t76, ptr %t77
  %t78 = getelementptr ptr, ptr %t75, i32 1
  store ptr %t6, ptr %t78
  store ptr %t68, ptr %t3
  store ptr %t75, ptr %t4
  br label %tco.loop.0
tco.case.arm.3.79:
  %t80 = getelementptr [1 x i8], ptr @.str.0, i64 0, i64 0
  %t81 = call ptr @v__apply__scc_handleA_handleB(ptr %t6, ptr %t80)
  store ptr %t81, ptr %t2
  br label %tco.exit.1
tco.case.default.49:
  unreachable
tco.case.default.10:
  unreachable
tco.exit.1:
  %t82 = load ptr, ptr %t2
  ret ptr %t82
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
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 0 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v_step, ptr %t3
  %t4 = call ptr @v__scc_handleA_handleB(ptr %t0)
  ret ptr %t4
}

define ptr @v_handleB(ptr %v_step) {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v_step, ptr %t3
  %t4 = call ptr @v__scc_handleA_handleB(ptr %t0)
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
