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
@.str.1 = private unnamed_addr constant [8 x i8] c"Nothing\00"
@.str.2 = private unnamed_addr constant [10 x i8] c"Just True\00"
@.str.3 = private unnamed_addr constant [11 x i8] c"Just False\00"
@.str.4 = private unnamed_addr constant [6 x i8] c"Just \00"
@.str.5 = private unnamed_addr constant [8 x i8] c"String \00"
@.str.6 = private unnamed_addr constant [7 x i8] c"Int32 \00"

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


define internal ptr @v_showUnit(ptr %v__wild0) {
  %t0 = getelementptr [5 x i8], ptr @.str.0, i64 0, i64 0
  ret ptr %t0
}

define internal ptr @v_whatsThat(ptr %v_x) {
  %t0 = getelementptr ptr, ptr %v_x, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 1454647603, label %case.arm.1454647603.5 i64 1615808600, label %case.arm.1615808600.51 i64 2711245919, label %case.arm.2711245919.57 ]
case.arm.1454647603.5:
  %t7 = getelementptr ptr, ptr %v_x, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr ptr, ptr %t8, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %case.default.12 [ i64 0, label %case.arm.0.14 i64 1, label %case.arm.1.17 ]
case.arm.0.14:
  %t16 = getelementptr [8 x i8], ptr @.str.1, i64 0, i64 0
  br label %case.end.0.15
case.end.0.15:
  br label %case.join.13
case.arm.1.17:
  %t19 = getelementptr ptr, ptr %t8, i32 1
  %t20 = load ptr, ptr %t19
  %t21 = getelementptr ptr, ptr %t20, i32 0
  %t22 = load ptr, ptr %t21
  %t23 = ptrtoint ptr %t22 to i64
  switch i64 %t23, label %case.default.24 [ i64 796142685, label %case.arm.796142685.26 i64 1759602215, label %case.arm.1759602215.42 ]
case.arm.796142685.26:
  %t28 = getelementptr ptr, ptr %t20, i32 1
  %t29 = load ptr, ptr %t28
  %t30 = getelementptr ptr, ptr %t29, i32 0
  %t31 = load ptr, ptr %t30
  %t32 = ptrtoint ptr %t31 to i64
  switch i64 %t32, label %case.default.33 [ i64 0, label %case.arm.0.35 i64 1, label %case.arm.1.38 ]
case.arm.0.35:
  %t37 = getelementptr [10 x i8], ptr @.str.2, i64 0, i64 0
  br label %case.end.0.36
case.end.0.36:
  br label %case.join.34
case.arm.1.38:
  %t40 = getelementptr [11 x i8], ptr @.str.3, i64 0, i64 0
  br label %case.end.1.39
case.end.1.39:
  br label %case.join.34
case.default.33:
  unreachable
case.join.34:
  %t41 = phi ptr [%t37, %case.end.0.36], [%t40, %case.end.1.39]
  br label %case.end.796142685.27
case.end.796142685.27:
  br label %case.join.25
case.arm.1759602215.42:
  %t44 = getelementptr ptr, ptr %t20, i32 1
  %t45 = load ptr, ptr %t44
  %t46 = getelementptr [6 x i8], ptr @.str.4, i64 0, i64 0
  %t47 = call ptr @v_showUnit(ptr %t45)
  %t48 = call ptr @__concat(ptr %t46, ptr %t47)
  br label %case.end.1759602215.43
case.end.1759602215.43:
  br label %case.join.25
case.default.24:
  unreachable
case.join.25:
  %t49 = phi ptr [%t41, %case.end.796142685.27], [%t48, %case.end.1759602215.43]
  br label %case.end.1.18
case.end.1.18:
  br label %case.join.13
case.default.12:
  unreachable
case.join.13:
  %t50 = phi ptr [%t16, %case.end.0.15], [%t49, %case.end.1.18]
  br label %case.end.1454647603.6
case.end.1454647603.6:
  br label %case.join.4
case.arm.1615808600.51:
  %t53 = getelementptr ptr, ptr %v_x, i32 1
  %t54 = load ptr, ptr %t53
  %t55 = getelementptr [8 x i8], ptr @.str.5, i64 0, i64 0
  %t56 = call ptr @__concat(ptr %t55, ptr %t54)
  br label %case.end.1615808600.52
case.end.1615808600.52:
  br label %case.join.4
case.arm.2711245919.57:
  %t59 = getelementptr ptr, ptr %v_x, i32 1
  %t60 = load ptr, ptr %t59
  %t61 = getelementptr [7 x i8], ptr @.str.6, i64 0, i64 0
  %t62 = call ptr @__showInt32(ptr %t60)
  %t63 = call ptr @__concat(ptr %t61, ptr %t62)
  br label %case.end.2711245919.58
case.end.2711245919.58:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t64 = phi ptr [%t50, %case.end.1454647603.6], [%t56, %case.end.1615808600.52], [%t63, %case.end.2711245919.58]
  ret ptr %t64
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 1454647603 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @malloc(i64 16)
  %t4 = inttoptr i64 1 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = call ptr @malloc(i64 16)
  %t7 = inttoptr i64 796142685 to ptr
  %t8 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t7, ptr %t8
  %t9 = call ptr @malloc(i64 8)
  %t10 = inttoptr i64 0 to ptr
  %t11 = getelementptr ptr, ptr %t9, i32 0
  store ptr %t10, ptr %t11
  %t12 = getelementptr ptr, ptr %t6, i32 1
  store ptr %t9, ptr %t12
  %t13 = getelementptr ptr, ptr %t3, i32 1
  store ptr %t6, ptr %t13
  %t14 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t14
  %t15 = call ptr @v_whatsThat(ptr %t0)
  %t16 = call ptr @__print(ptr %t15)
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
  call ptr @v_main(ptr %input)
  ret i32 0
}
