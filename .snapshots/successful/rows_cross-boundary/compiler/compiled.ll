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

@.str.0 = private unnamed_addr constant [5 x i8] c"Unit\00"
@.str.1 = private unnamed_addr constant [2 x i8] c"T\00"
@.str.2 = private unnamed_addr constant [2 x i8] c"F\00"
@.str.3 = private unnamed_addr constant [2 x i8] c"N\00"
@.str.4 = private unnamed_addr constant [2 x i8] c"J\00"
@.str.5 = private unnamed_addr constant [1 x i8] c"\00"
@.str.6 = private unnamed_addr constant [5 x i8] c"ErrA\00"
@.str.7 = private unnamed_addr constant [4 x i8] c" / \00"

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


define internal ptr @v_showUnit(ptr %v__wild0) {
  %t0 = getelementptr [5 x i8], ptr @.str.0, i64 0, i64 0
  ret ptr %t0
}

define internal ptr @v_defaultJust() {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @malloc(i64 8)
  %t4 = inttoptr i64 0 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  ret ptr %t0
}

define internal ptr @v_defaultBools() {
  %t0 = call ptr @malloc(i64 24)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @malloc(i64 8)
  %t4 = inttoptr i64 0 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  %t7 = call ptr @malloc(i64 24)
  %t8 = inttoptr i64 1 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = call ptr @malloc(i64 8)
  %t11 = inttoptr i64 1 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  %t13 = getelementptr ptr, ptr %t7, i32 1
  store ptr %t10, ptr %t13
  %t14 = call ptr @malloc(i64 8)
  %t15 = inttoptr i64 0 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  %t17 = getelementptr ptr, ptr %t7, i32 2
  store ptr %t14, ptr %t17
  %t18 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t7, ptr %t18
  ret ptr %t0
}

define internal ptr @v_defaultRight() {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @malloc(i64 16)
  %t4 = inttoptr i64 1 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = call ptr @malloc(i64 8)
  %t7 = inttoptr i64 1 to ptr
  %t8 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t7, ptr %t8
  %t9 = getelementptr ptr, ptr %t3, i32 1
  store ptr %t6, ptr %t9
  %t10 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t10
  ret ptr %t0
}

define internal ptr @v_dispatchInner(ptr %v_x) {
  %t0 = getelementptr ptr, ptr %v_x, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 796142685, label %case.arm.796142685.5 i64 1759602215, label %case.arm.1759602215.21 ]
case.arm.796142685.5:
  %t7 = getelementptr ptr, ptr %v_x, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr ptr, ptr %t8, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %case.default.12 [ i64 0, label %case.arm.0.14 i64 1, label %case.arm.1.17 ]
case.arm.0.14:
  %t16 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  br label %case.end.0.15
case.end.0.15:
  br label %case.join.13
case.arm.1.17:
  %t19 = getelementptr [2 x i8], ptr @.str.2, i64 0, i64 0
  br label %case.end.1.18
case.end.1.18:
  br label %case.join.13
case.default.12:
  unreachable
case.join.13:
  %t20 = phi ptr [%t16, %case.end.0.15], [%t19, %case.end.1.18]
  br label %case.end.796142685.6
case.end.796142685.6:
  br label %case.join.4
case.arm.1759602215.21:
  %t23 = getelementptr ptr, ptr %v_x, i32 1
  %t24 = load ptr, ptr %t23
  %t25 = call ptr @v_showUnit(ptr %t24)
  br label %case.end.1759602215.22
case.end.1759602215.22:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t26 = phi ptr [%t20, %case.end.796142685.6], [%t25, %case.end.1759602215.22]
  ret ptr %t26
}

define internal ptr @v_describeMaybe(ptr %v_m) {
  %t0 = getelementptr ptr, ptr %v_m, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.8 ]
case.arm.0.5:
  %t7 = getelementptr [2 x i8], ptr @.str.3, i64 0, i64 0
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.8:
  %t10 = getelementptr ptr, ptr %v_m, i32 1
  %t11 = load ptr, ptr %t10
  %t12 = getelementptr [2 x i8], ptr @.str.4, i64 0, i64 0
  %t13 = call ptr @v_dispatchInner(ptr %t11)
  %t14 = call ptr @__concat(ptr %t12, ptr %t13)
  br label %case.end.1.9
case.end.1.9:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t15 = phi ptr [%t7, %case.end.0.6], [%t14, %case.end.1.9]
  ret ptr %t15
}

define internal ptr @v_describeLst(ptr %v_xs) {
  %t0 = call ptr @malloc(i64 8)
  %t1 = inttoptr i64 0 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps_describeLst(ptr %v_xs, ptr %t0)
  ret ptr %t3
}

define internal ptr @v__cps_describeLst(ptr %v_xs, ptr %v__k) {
entry:
  %t3 = alloca ptr
  store ptr %v_xs, ptr %t3
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
  switch i64 %t9, label %tco.case.default.10 [ i64 0, label %tco.case.arm.0.11 i64 1, label %tco.case.arm.1.14 ]
tco.case.arm.0.11:
  %t12 = getelementptr [1 x i8], ptr @.str.5, i64 0, i64 0
  %t13 = call ptr @v__apply_describeLst(ptr %t6, ptr %t12)
  store ptr %t13, ptr %t2
  br label %tco.exit.1
tco.case.arm.1.14:
  %t15 = getelementptr ptr, ptr %t5, i32 1
  %t16 = load ptr, ptr %t15
  %t17 = getelementptr ptr, ptr %t5, i32 2
  %t18 = load ptr, ptr %t17
  %t19 = call ptr @malloc(i64 24)
  %t20 = inttoptr i64 1 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr ptr, ptr %t19, i32 1
  store ptr %t6, ptr %t22
  %t23 = getelementptr ptr, ptr %t19, i32 2
  store ptr %t16, ptr %t23
  store ptr %t18, ptr %t3
  store ptr %t19, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t24 = load ptr, ptr %t2
  ret ptr %t24
}

define internal ptr @v__apply_describeLst(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 0, label %tco.case.arm.0.11 i64 1, label %tco.case.arm.1.12 ]
tco.case.arm.0.11:
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.1.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  %t15 = getelementptr ptr, ptr %t5, i32 2
  %t16 = load ptr, ptr %t15
  %t17 = call ptr @v_dispatchInner(ptr %t16)
  %t18 = call ptr @__concat(ptr %t17, ptr %t6)
  store ptr %t14, ptr %t3
  store ptr %t18, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t19 = load ptr, ptr %t2
  ret ptr %t19
}

define internal ptr @v_describeEither(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.10 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_r, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr [5 x i8], ptr @.str.6, i64 0, i64 0
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.10:
  %t12 = getelementptr ptr, ptr %v_r, i32 1
  %t13 = load ptr, ptr %t12
  %t14 = call ptr @v_describeMaybe(ptr %t13)
  br label %case.end.1.11
case.end.1.11:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t15 = phi ptr [%t9, %case.end.0.6], [%t14, %case.end.1.11]
  ret ptr %t15
}

define internal ptr @v_summary() {
  %t0 = call ptr @v_defaultJust()
  %t1 = call ptr @v__lift_0(ptr %t0)
  %t2 = call ptr @v_describeMaybe(ptr %t1)
  %t3 = getelementptr [4 x i8], ptr @.str.7, i64 0, i64 0
  %t4 = call ptr @__concat(ptr %t2, ptr %t3)
  %t5 = call ptr @v_defaultBools()
  %t6 = call ptr @v__lift_1(ptr %t5)
  %t7 = call ptr @v_describeLst(ptr %t6)
  %t8 = call ptr @__concat(ptr %t4, ptr %t7)
  %t9 = getelementptr [4 x i8], ptr @.str.7, i64 0, i64 0
  %t10 = call ptr @__concat(ptr %t8, ptr %t9)
  %t11 = call ptr @v_defaultRight()
  %t12 = call ptr @v__lift_2(ptr %t11)
  %t13 = call ptr @v_describeEither(ptr %t12)
  %t14 = call ptr @__concat(ptr %t10, ptr %t13)
  ret ptr %t14
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @v_summary()
  %t1 = call ptr @__print(ptr %t0)
  ret ptr %t1
}

define internal ptr @v__lift_0(ptr %v___input) {
  %t0 = getelementptr ptr, ptr %v___input, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.10 ]
case.arm.0.5:
  %t7 = call ptr @malloc(i64 8)
  %t8 = inttoptr i64 0 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.10:
  %t12 = getelementptr ptr, ptr %v___input, i32 1
  %t13 = load ptr, ptr %t12
  %t14 = call ptr @malloc(i64 16)
  %t15 = inttoptr i64 1 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  %t17 = call ptr @malloc(i64 16)
  %t18 = inttoptr i64 796142685 to ptr
  %t19 = getelementptr ptr, ptr %t17, i32 0
  store ptr %t18, ptr %t19
  %t20 = getelementptr ptr, ptr %t17, i32 1
  store ptr %t13, ptr %t20
  %t21 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t17, ptr %t21
  br label %case.end.1.11
case.end.1.11:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t22 = phi ptr [%t7, %case.end.0.6], [%t14, %case.end.1.11]
  ret ptr %t22
}

define internal ptr @v__lift_1(ptr %v___input) {
  %t0 = call ptr @malloc(i64 8)
  %t1 = inttoptr i64 0 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__lift_1(ptr %v___input, ptr %t0)
  ret ptr %t3
}

define internal ptr @v__cps__lift_1(ptr %v___input, ptr %v__k) {
entry:
  %t3 = alloca ptr
  store ptr %v___input, ptr %t3
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
  switch i64 %t9, label %tco.case.default.10 [ i64 0, label %tco.case.arm.0.11 i64 1, label %tco.case.arm.1.16 ]
tco.case.arm.0.11:
  %t12 = call ptr @malloc(i64 8)
  %t13 = inttoptr i64 0 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = call ptr @v__apply__lift_1(ptr %t6, ptr %t12)
  store ptr %t15, ptr %t2
  br label %tco.exit.1
tco.case.arm.1.16:
  %t17 = getelementptr ptr, ptr %t5, i32 1
  %t18 = load ptr, ptr %t17
  %t19 = getelementptr ptr, ptr %t5, i32 2
  %t20 = load ptr, ptr %t19
  %t21 = call ptr @malloc(i64 24)
  %t22 = inttoptr i64 1 to ptr
  %t23 = getelementptr ptr, ptr %t21, i32 0
  store ptr %t22, ptr %t23
  %t24 = getelementptr ptr, ptr %t21, i32 1
  store ptr %t6, ptr %t24
  %t25 = getelementptr ptr, ptr %t21, i32 2
  store ptr %t18, ptr %t25
  store ptr %t20, ptr %t3
  store ptr %t21, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t26 = load ptr, ptr %t2
  ret ptr %t26
}

define internal ptr @v__apply__lift_1(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 0, label %tco.case.arm.0.11 i64 1, label %tco.case.arm.1.12 ]
tco.case.arm.0.11:
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.1.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  %t15 = getelementptr ptr, ptr %t5, i32 2
  %t16 = load ptr, ptr %t15
  %t17 = call ptr @malloc(i64 24)
  %t18 = inttoptr i64 1 to ptr
  %t19 = getelementptr ptr, ptr %t17, i32 0
  store ptr %t18, ptr %t19
  %t20 = call ptr @malloc(i64 16)
  %t21 = inttoptr i64 796142685 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = getelementptr ptr, ptr %t20, i32 1
  store ptr %t16, ptr %t23
  %t24 = getelementptr ptr, ptr %t17, i32 1
  store ptr %t20, ptr %t24
  %t25 = getelementptr ptr, ptr %t17, i32 2
  store ptr %t6, ptr %t25
  store ptr %t14, ptr %t3
  store ptr %t17, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t26 = load ptr, ptr %t2
  ret ptr %t26
}

define internal ptr @v__lift_2(ptr %v___input) {
  %t0 = getelementptr ptr, ptr %v___input, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.13 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v___input, i32 1
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
  %t15 = getelementptr ptr, ptr %v___input, i32 1
  %t16 = load ptr, ptr %t15
  %t17 = call ptr @malloc(i64 16)
  %t18 = inttoptr i64 1 to ptr
  %t19 = getelementptr ptr, ptr %t17, i32 0
  store ptr %t18, ptr %t19
  %t20 = call ptr @v__lift_0(ptr %t16)
  %t21 = getelementptr ptr, ptr %t17, i32 1
  store ptr %t20, ptr %t21
  br label %case.end.1.14
case.end.1.14:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t22 = phi ptr [%t9, %case.end.0.6], [%t17, %case.end.1.14]
  ret ptr %t22
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
