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
@.str.5 = private unnamed_addr constant [3 x i8] c"; \00"

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

define internal ptr @v_whatsInside(ptr %v_x) {
  %t0 = getelementptr ptr, ptr %v_x, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.8 ]
case.arm.0.5:
  %t7 = getelementptr [8 x i8], ptr @.str.1, i64 0, i64 0
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.8:
  %t10 = getelementptr ptr, ptr %v_x, i32 1
  %t11 = load ptr, ptr %t10
  %t12 = getelementptr ptr, ptr %t11, i32 0
  %t13 = load ptr, ptr %t12
  %t14 = ptrtoint ptr %t13 to i64
  switch i64 %t14, label %case.default.15 [ i64 796142685, label %case.arm.796142685.17 i64 1759602215, label %case.arm.1759602215.33 ]
case.arm.796142685.17:
  %t19 = getelementptr ptr, ptr %t11, i32 1
  %t20 = load ptr, ptr %t19
  %t21 = getelementptr ptr, ptr %t20, i32 0
  %t22 = load ptr, ptr %t21
  %t23 = ptrtoint ptr %t22 to i64
  switch i64 %t23, label %case.default.24 [ i64 0, label %case.arm.0.26 i64 1, label %case.arm.1.29 ]
case.arm.0.26:
  %t28 = getelementptr [10 x i8], ptr @.str.2, i64 0, i64 0
  br label %case.end.0.27
case.end.0.27:
  br label %case.join.25
case.arm.1.29:
  %t31 = getelementptr [11 x i8], ptr @.str.3, i64 0, i64 0
  br label %case.end.1.30
case.end.1.30:
  br label %case.join.25
case.default.24:
  unreachable
case.join.25:
  %t32 = phi ptr [%t28, %case.end.0.27], [%t31, %case.end.1.30]
  br label %case.end.796142685.18
case.end.796142685.18:
  br label %case.join.16
case.arm.1759602215.33:
  %t35 = getelementptr ptr, ptr %t11, i32 1
  %t36 = load ptr, ptr %t35
  %t37 = getelementptr [6 x i8], ptr @.str.4, i64 0, i64 0
  %t38 = call ptr @v_showUnit(ptr %t36)
  %t39 = call ptr @__concat(ptr %t37, ptr %t38)
  br label %case.end.1759602215.34
case.end.1759602215.34:
  br label %case.join.16
case.default.15:
  unreachable
case.join.16:
  %t40 = phi ptr [%t32, %case.end.796142685.18], [%t39, %case.end.1759602215.34]
  br label %case.end.1.9
case.end.1.9:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t41 = phi ptr [%t7, %case.end.0.6], [%t40, %case.end.1.9]
  ret ptr %t41
}

define internal ptr @v_summary() {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @malloc(i64 16)
  %t4 = inttoptr i64 796142685 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = call ptr @malloc(i64 8)
  %t7 = inttoptr i64 0 to ptr
  %t8 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t7, ptr %t8
  %t9 = getelementptr ptr, ptr %t3, i32 1
  store ptr %t6, ptr %t9
  %t10 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t10
  %t11 = call ptr @v_whatsInside(ptr %t0)
  %t12 = getelementptr [3 x i8], ptr @.str.5, i64 0, i64 0
  %t13 = call ptr @__concat(ptr %t11, ptr %t12)
  %t14 = call ptr @malloc(i64 16)
  %t15 = inttoptr i64 1 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  %t17 = call ptr @malloc(i64 16)
  %t18 = inttoptr i64 1759602215 to ptr
  %t19 = getelementptr ptr, ptr %t17, i32 0
  store ptr %t18, ptr %t19
  %t20 = call ptr @malloc(i64 8)
  %t21 = inttoptr i64 0 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = getelementptr ptr, ptr %t17, i32 1
  store ptr %t20, ptr %t23
  %t24 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t17, ptr %t24
  %t25 = call ptr @v_whatsInside(ptr %t14)
  %t26 = call ptr @__concat(ptr %t13, ptr %t25)
  %t27 = getelementptr [3 x i8], ptr @.str.5, i64 0, i64 0
  %t28 = call ptr @__concat(ptr %t26, ptr %t27)
  %t29 = call ptr @malloc(i64 8)
  %t30 = inttoptr i64 0 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = call ptr @v_whatsInside(ptr %t29)
  %t33 = call ptr @__concat(ptr %t28, ptr %t32)
  ret ptr %t33
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @v_summary()
  %t1 = call ptr @__print(ptr %t0)
  ret ptr %t1
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
