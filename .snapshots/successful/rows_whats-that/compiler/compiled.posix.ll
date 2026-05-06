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
@.str.7 = private unnamed_addr constant [16 x i8] c"STRING_TOO_LONG\00"

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
  %unit = call ptr @malloc(i64 8)
  %unit_tag_ptr = getelementptr ptr, ptr %unit, i32 0
  %unit_tag = inttoptr i64 0 to ptr
  store ptr %unit_tag, ptr %unit_tag_ptr
  ret ptr %unit
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

define internal ptr @v_runIO(ptr %v_io) {
entry:
  %t3 = alloca ptr
  store ptr %v_io, ptr %t3
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t4 = load ptr, ptr %t3
  %t5 = getelementptr ptr, ptr %t4, i32 0
  %t6 = load ptr, ptr %t5
  %t7 = ptrtoint ptr %t6 to i64
  switch i64 %t7, label %tco.case.default.8 [ i64 0, label %tco.case.arm.0.9 i64 2, label %tco.case.arm.2.12 ]
tco.case.arm.0.9:
  %t10 = getelementptr ptr, ptr %t4, i32 1
  %t11 = load ptr, ptr %t10
  store ptr %t11, ptr %t2
  br label %tco.exit.1
tco.case.arm.2.12:
  %t13 = getelementptr ptr, ptr %t4, i32 1
  %t14 = load ptr, ptr %t13
  %t15 = getelementptr ptr, ptr %t4, i32 2
  %t16 = load ptr, ptr %t15
  %t17 = call ptr @__print(ptr %t14)
  %t18 = getelementptr ptr, ptr %t17, i32 0
  %t19 = load ptr, ptr %t18
  %t20 = ptrtoint ptr %t19 to i64
  switch i64 %t20, label %tco.case.default.21 [ i64 0, label %tco.case.arm.0.22 ]
tco.case.arm.0.22:
  store ptr %t16, ptr %t3
  br label %tco.loop.0
tco.case.default.21:
  unreachable
tco.case.default.8:
  unreachable
tco.exit.1:
  %t23 = load ptr, ptr %t2
  ret ptr %t23
}

define internal ptr @v_whatsThat(ptr %v_x) {
  %t0 = getelementptr ptr, ptr %v_x, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 1454647603, label %case.arm.1454647603.5 i64 1615808600, label %case.arm.1615808600.67 i64 2711245919, label %case.arm.2711245919.77 ]
case.arm.1454647603.5:
  %t7 = getelementptr ptr, ptr %v_x, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr ptr, ptr %t8, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %case.default.12 [ i64 0, label %case.arm.0.14 i64 1, label %case.arm.1.21 ]
case.arm.0.14:
  %t16 = call ptr @malloc(i64 16)
  %t17 = inttoptr i64 1 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = getelementptr [8 x i8], ptr @.str.1, i64 0, i64 0
  %t20 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t19, ptr %t20
  br label %case.end.0.15
case.end.0.15:
  br label %case.join.13
case.arm.1.21:
  %t23 = getelementptr ptr, ptr %t8, i32 1
  %t24 = load ptr, ptr %t23
  %t25 = getelementptr ptr, ptr %t24, i32 0
  %t26 = load ptr, ptr %t25
  %t27 = ptrtoint ptr %t26 to i64
  switch i64 %t27, label %case.default.28 [ i64 796142685, label %case.arm.796142685.30 i64 1759602215, label %case.arm.1759602215.54 ]
case.arm.796142685.30:
  %t32 = getelementptr ptr, ptr %t24, i32 1
  %t33 = load ptr, ptr %t32
  %t34 = getelementptr ptr, ptr %t33, i32 0
  %t35 = load ptr, ptr %t34
  %t36 = ptrtoint ptr %t35 to i64
  switch i64 %t36, label %case.default.37 [ i64 0, label %case.arm.0.39 i64 1, label %case.arm.1.46 ]
case.arm.0.39:
  %t41 = call ptr @malloc(i64 16)
  %t42 = inttoptr i64 1 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = getelementptr [10 x i8], ptr @.str.2, i64 0, i64 0
  %t45 = getelementptr ptr, ptr %t41, i32 1
  store ptr %t44, ptr %t45
  br label %case.end.0.40
case.end.0.40:
  br label %case.join.38
case.arm.1.46:
  %t48 = call ptr @malloc(i64 16)
  %t49 = inttoptr i64 1 to ptr
  %t50 = getelementptr ptr, ptr %t48, i32 0
  store ptr %t49, ptr %t50
  %t51 = getelementptr [11 x i8], ptr @.str.3, i64 0, i64 0
  %t52 = getelementptr ptr, ptr %t48, i32 1
  store ptr %t51, ptr %t52
  br label %case.end.1.47
case.end.1.47:
  br label %case.join.38
case.default.37:
  unreachable
case.join.38:
  %t53 = phi ptr [%t41, %case.end.0.40], [%t48, %case.end.1.47]
  br label %case.end.796142685.31
case.end.796142685.31:
  br label %case.join.29
case.arm.1759602215.54:
  %t56 = getelementptr ptr, ptr %t24, i32 1
  %t57 = load ptr, ptr %t56
  %t58 = call ptr @malloc(i64 16)
  %t59 = inttoptr i64 1 to ptr
  %t60 = getelementptr ptr, ptr %t58, i32 0
  store ptr %t59, ptr %t60
  %t61 = getelementptr [6 x i8], ptr @.str.4, i64 0, i64 0
  %t62 = call ptr @v_showUnit(ptr %t57)
  %t63 = call ptr @__concat(ptr %t61, ptr %t62)
  %t64 = getelementptr ptr, ptr %t58, i32 1
  store ptr %t63, ptr %t64
  br label %case.end.1759602215.55
case.end.1759602215.55:
  br label %case.join.29
case.default.28:
  unreachable
case.join.29:
  %t65 = phi ptr [%t53, %case.end.796142685.31], [%t58, %case.end.1759602215.55]
  br label %case.end.1.22
case.end.1.22:
  br label %case.join.13
case.default.12:
  unreachable
case.join.13:
  %t66 = phi ptr [%t16, %case.end.0.15], [%t65, %case.end.1.22]
  br label %case.end.1454647603.6
case.end.1454647603.6:
  br label %case.join.4
case.arm.1615808600.67:
  %t69 = getelementptr ptr, ptr %v_x, i32 1
  %t70 = load ptr, ptr %t69
  %t71 = call ptr @malloc(i64 16)
  %t72 = inttoptr i64 1 to ptr
  %t73 = getelementptr ptr, ptr %t71, i32 0
  store ptr %t72, ptr %t73
  %t74 = getelementptr [8 x i8], ptr @.str.5, i64 0, i64 0
  %t75 = call ptr @__concat(ptr %t74, ptr %t70)
  %t76 = getelementptr ptr, ptr %t71, i32 1
  store ptr %t75, ptr %t76
  br label %case.end.1615808600.68
case.end.1615808600.68:
  br label %case.join.4
case.arm.2711245919.77:
  %t79 = getelementptr ptr, ptr %v_x, i32 1
  %t80 = load ptr, ptr %t79
  %t81 = call ptr @malloc(i64 16)
  %t82 = inttoptr i64 1 to ptr
  %t83 = getelementptr ptr, ptr %t81, i32 0
  store ptr %t82, ptr %t83
  %t84 = getelementptr [7 x i8], ptr @.str.6, i64 0, i64 0
  %t85 = call ptr @__showInt32(ptr %t80)
  %t86 = call ptr @__concat(ptr %t84, ptr %t85)
  %t87 = getelementptr ptr, ptr %t81, i32 1
  store ptr %t86, ptr %t87
  br label %case.end.2711245919.78
case.end.2711245919.78:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t88 = phi ptr [%t66, %case.end.1454647603.6], [%t71, %case.end.1615808600.68], [%t81, %case.end.2711245919.78]
  ret ptr %t88
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
  %t16 = call ptr @v__let_2(ptr %t15)
  ret ptr %t16
}

define internal ptr @v__let_2(ptr %v_res) {
  %t0 = getelementptr ptr, ptr %v_res, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.22 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_res, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = call ptr @malloc(i64 24)
  %t10 = inttoptr i64 2 to ptr
  %t11 = getelementptr ptr, ptr %t9, i32 0
  store ptr %t10, ptr %t11
  %t12 = getelementptr [16 x i8], ptr @.str.7, i64 0, i64 0
  %t13 = getelementptr ptr, ptr %t9, i32 1
  store ptr %t12, ptr %t13
  %t14 = call ptr @malloc(i64 16)
  %t15 = inttoptr i64 0 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  %t17 = call ptr @malloc(i64 8)
  %t18 = inttoptr i64 0 to ptr
  %t19 = getelementptr ptr, ptr %t17, i32 0
  store ptr %t18, ptr %t19
  %t20 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t17, ptr %t20
  %t21 = getelementptr ptr, ptr %t9, i32 2
  store ptr %t14, ptr %t21
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.22:
  %t24 = getelementptr ptr, ptr %v_res, i32 1
  %t25 = load ptr, ptr %t24
  %t26 = call ptr @malloc(i64 24)
  %t27 = inttoptr i64 2 to ptr
  %t28 = getelementptr ptr, ptr %t26, i32 0
  store ptr %t27, ptr %t28
  %t29 = getelementptr ptr, ptr %t26, i32 1
  store ptr %t25, ptr %t29
  %t30 = call ptr @malloc(i64 16)
  %t31 = inttoptr i64 0 to ptr
  %t32 = getelementptr ptr, ptr %t30, i32 0
  store ptr %t31, ptr %t32
  %t33 = call ptr @malloc(i64 8)
  %t34 = inttoptr i64 0 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = getelementptr ptr, ptr %t30, i32 1
  store ptr %t33, ptr %t36
  %t37 = getelementptr ptr, ptr %t26, i32 2
  store ptr %t30, ptr %t37
  br label %case.end.1.23
case.end.1.23:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t38 = phi ptr [%t9, %case.end.0.6], [%t26, %case.end.1.23]
  ret ptr %t38
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
  %io = call ptr @v_main(ptr %right_box)
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
