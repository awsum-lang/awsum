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


define ptr @v_zero() {
  %t0 = call ptr @malloc(i64 4)
  store i32 0, ptr %t0
  ret ptr %t0
}

define ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 8)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_parseExpr(ptr %t0)
  %t4 = call ptr @__showInt32(ptr %t3)
  %t5 = call ptr @__print(ptr %t4)
  ret ptr %t5
}

define ptr @v__scc_parseBinary_parseExpr(ptr %v__args) {
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
  switch i64 %t7, label %tco.case.default.8 [ i64 0, label %tco.case.arm.0.9 i64 1, label %tco.case.arm.1.28 ]
tco.case.arm.0.9:
  %t10 = getelementptr ptr, ptr %t4, i32 1
  %t11 = load ptr, ptr %t10
  %t12 = getelementptr ptr, ptr %t4, i32 2
  %t13 = load ptr, ptr %t12
  %t14 = getelementptr ptr, ptr %t11, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %tco.case.default.17 [ i64 0, label %tco.case.arm.0.18 i64 1, label %tco.case.arm.1.20 ]
tco.case.arm.0.18:
  %t19 = call ptr @v_zero()
  store ptr %t19, ptr %t2
  br label %tco.exit.1
tco.case.arm.1.20:
  %t21 = call ptr @malloc(i64 16)
  %t22 = inttoptr i64 1 to ptr
  %t23 = getelementptr ptr, ptr %t21, i32 0
  store ptr %t22, ptr %t23
  %t24 = call ptr @malloc(i64 8)
  %t25 = inttoptr i64 0 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = getelementptr ptr, ptr %t21, i32 1
  store ptr %t24, ptr %t27
  store ptr %t21, ptr %t3
  br label %tco.loop.0
tco.case.default.17:
  unreachable
tco.case.arm.1.28:
  %t29 = getelementptr ptr, ptr %t4, i32 1
  %t30 = load ptr, ptr %t29
  %t31 = getelementptr ptr, ptr %t30, i32 0
  %t32 = load ptr, ptr %t31
  %t33 = ptrtoint ptr %t32 to i64
  switch i64 %t33, label %tco.case.default.34 [ i64 0, label %tco.case.arm.0.35 i64 1, label %tco.case.arm.1.37 ]
tco.case.arm.0.35:
  %t36 = call ptr @v_zero()
  store ptr %t36, ptr %t2
  br label %tco.exit.1
tco.case.arm.1.37:
  %t38 = call ptr @malloc(i64 24)
  %t39 = inttoptr i64 0 to ptr
  %t40 = getelementptr ptr, ptr %t38, i32 0
  store ptr %t39, ptr %t40
  %t41 = getelementptr ptr, ptr %t38, i32 1
  store ptr %t30, ptr %t41
  %t42 = call ptr @v_zero()
  %t43 = getelementptr ptr, ptr %t38, i32 2
  store ptr %t42, ptr %t43
  store ptr %t38, ptr %t3
  br label %tco.loop.0
tco.case.default.34:
  unreachable
tco.case.default.8:
  unreachable
tco.exit.1:
  %t44 = load ptr, ptr %t2
  ret ptr %t44
}

define ptr @v_parseBinary(ptr %v_tok, ptr %v__acc) {
  %t0 = call ptr @malloc(i64 24)
  %t1 = inttoptr i64 0 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v_tok, ptr %t3
  %t4 = getelementptr ptr, ptr %t0, i32 2
  store ptr %v__acc, ptr %t4
  %t5 = call ptr @v__scc_parseBinary_parseExpr(ptr %t0)
  ret ptr %t5
}

define ptr @v_parseExpr(ptr %v_tok) {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v_tok, ptr %t3
  %t4 = call ptr @v__scc_parseBinary_parseExpr(ptr %t0)
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
