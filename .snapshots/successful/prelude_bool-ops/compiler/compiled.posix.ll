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

@.str.0 = private unnamed_addr constant [2 x i8] c"T\00"
@.str.1 = private unnamed_addr constant [2 x i8] c"F\00"
@.str.2 = private unnamed_addr constant [16 x i8] c"STRING_TOO_LONG\00"

define internal ptr @__concat(ptr %a, ptr %b) {
  %la_box = call ptr @__lengthUtf16CodeUnits(ptr %a)
  %la = load i32, ptr %la_box
  %lb_box = call ptr @__lengthUtf16CodeUnits(ptr %b)
  %lb = load i32, ptr %lb_box
  %la64 = zext i32 %la to i64
  %lb64 = zext i32 %lb to i64
  %sum64 = add i64 %la64, %lb64
  %over = icmp ugt i64 %sum64, 134217728
  br i1 %over, label %too_long, label %ok
too_long:
  %stl = call ptr @malloc(i64 8)
  %stl_tag = inttoptr i64 0 to ptr
  store ptr %stl_tag, ptr %stl
  %left = call ptr @malloc(i64 16)
  %left_tag = inttoptr i64 0 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %stl, ptr %left_f
  ret ptr %left
ok:
  %ba = call i64 @strlen(ptr %a)
  %bb = call i64 @strlen(ptr %b)
  %bsum = add i64 %ba, %bb
  %total = add i64 %bsum, 1
  %buf = call ptr @malloc(i64 %total)
  call ptr @strcpy(ptr %buf, ptr %a)
  call ptr @strcat(ptr %buf, ptr %b)
  %right = call ptr @malloc(i64 16)
  %right_tag = inttoptr i64 1 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %buf, ptr %right_f
  ret ptr %right
}


define internal ptr @__print(ptr %s) {
  call i32 (ptr, ...) @printf(ptr @.fmt, ptr %s)
  %unit = call ptr @malloc(i64 8)
  %unit_tag_ptr = getelementptr ptr, ptr %unit, i32 0
  %unit_tag = inttoptr i64 0 to ptr
  store ptr %unit_tag, ptr %unit_tag_ptr
  ret ptr %unit
}


define internal ptr @__lengthUtf16CodeUnits(ptr %s) {
entry:
  %i_p = alloca i64, align 8
  store i64 0, ptr %i_p
  %n_p = alloca i32, align 4
  store i32 0, ptr %n_p
  br label %head
head:
  %i = load i64, ptr %i_p
  %bp = getelementptr i8, ptr %s, i64 %i
  %b = load i8, ptr %bp
  %is_nul = icmp eq i8 %b, 0
  br i1 %is_nul, label %done, label %body
body:
  %bz = zext i8 %b to i32
  %top2 = and i32 %bz, 192
  %is_cont = icmp eq i32 %top2, 128
  br i1 %is_cont, label %step, label %check4
check4:
  %top5 = and i32 %bz, 248
  %is_4 = icmp eq i32 %top5, 240
  br i1 %is_4, label %add2, label %add1
add2:
  %n2_0 = load i32, ptr %n_p
  %n2_1 = add i32 %n2_0, 2
  store i32 %n2_1, ptr %n_p
  br label %step
add1:
  %n1_0 = load i32, ptr %n_p
  %n1_1 = add i32 %n1_0, 1
  store i32 %n1_1, ptr %n_p
  br label %step
step:
  %i1 = add i64 %i, 1
  store i64 %i1, ptr %i_p
  br label %head
done:
  %nf = load i32, ptr %n_p
  %box = call ptr @malloc(i64 4)
  store i32 %nf, ptr %box
  ret ptr %box
}


define internal ptr @v_not(ptr %v_b) {
  %t0 = getelementptr ptr, ptr %v_b, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.10 ]
case.arm.0.5:
  %t7 = call ptr @malloc(i64 8)
  %t8 = inttoptr i64 1 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.10:
  %t12 = call ptr @malloc(i64 8)
  %t13 = inttoptr i64 0 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  br label %case.end.1.11
case.end.1.11:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t15 = phi ptr [%t7, %case.end.0.6], [%t12, %case.end.1.11]
  ret ptr %t15
}

define internal ptr @v_and(ptr %v_a, ptr %v_b) {
  %t0 = getelementptr ptr, ptr %v_a, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.7 ]
case.arm.0.5:
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.7:
  %t9 = call ptr @malloc(i64 8)
  %t10 = inttoptr i64 1 to ptr
  %t11 = getelementptr ptr, ptr %t9, i32 0
  store ptr %t10, ptr %t11
  br label %case.end.1.8
case.end.1.8:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t12 = phi ptr [%v_b, %case.end.0.6], [%t9, %case.end.1.8]
  ret ptr %t12
}

define internal ptr @v_or(ptr %v_a, ptr %v_b) {
  %t0 = getelementptr ptr, ptr %v_a, i32 0
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
  br label %case.end.1.11
case.end.1.11:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t12 = phi ptr [%t7, %case.end.0.6], [%v_b, %case.end.1.11]
  ret ptr %t12
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

define internal ptr @v_showBool(ptr %v_b) {
  %t0 = getelementptr ptr, ptr %v_b, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.8 ]
case.arm.0.5:
  %t7 = getelementptr [2 x i8], ptr @.str.0, i64 0, i64 0
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.8:
  %t10 = getelementptr [2 x i8], ptr @.str.1, i64 0, i64 0
  br label %case.end.1.9
case.end.1.9:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t11 = phi ptr [%t7, %case.end.0.6], [%t10, %case.end.1.9]
  ret ptr %t11
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 8)
  %t1 = inttoptr i64 0 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_not(ptr %t0)
  %t4 = call ptr @v_showBool(ptr %t3)
  %t5 = call ptr @malloc(i64 8)
  %t6 = inttoptr i64 1 to ptr
  %t7 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t6, ptr %t7
  %t8 = call ptr @v_not(ptr %t5)
  %t9 = call ptr @v_showBool(ptr %t8)
  %t10 = call ptr @__concat(ptr %t4, ptr %t9)
  %t11 = getelementptr ptr, ptr %t10, i32 0
  %t12 = load ptr, ptr %t11
  %t13 = ptrtoint ptr %t12 to i64
  switch i64 %t13, label %case.default.14 [ i64 0, label %case.arm.0.16 i64 1, label %case.arm.1.24 ]
case.arm.0.16:
  %t18 = getelementptr ptr, ptr %t10, i32 1
  %t19 = load ptr, ptr %t18
  %t20 = call ptr @malloc(i64 16)
  %t21 = inttoptr i64 0 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = getelementptr ptr, ptr %t20, i32 1
  store ptr %t19, ptr %t23
  br label %case.end.0.17
case.end.0.17:
  br label %case.join.15
case.arm.1.24:
  %t26 = getelementptr ptr, ptr %t10, i32 1
  %t27 = load ptr, ptr %t26
  %t28 = call ptr @malloc(i64 8)
  %t29 = inttoptr i64 0 to ptr
  %t30 = getelementptr ptr, ptr %t28, i32 0
  store ptr %t29, ptr %t30
  %t31 = call ptr @malloc(i64 8)
  %t32 = inttoptr i64 1 to ptr
  %t33 = getelementptr ptr, ptr %t31, i32 0
  store ptr %t32, ptr %t33
  %t34 = call ptr @v_and(ptr %t28, ptr %t31)
  %t35 = call ptr @v_showBool(ptr %t34)
  %t36 = call ptr @__concat(ptr %t27, ptr %t35)
  %t37 = getelementptr ptr, ptr %t36, i32 0
  %t38 = load ptr, ptr %t37
  %t39 = ptrtoint ptr %t38 to i64
  switch i64 %t39, label %case.default.40 [ i64 0, label %case.arm.0.42 i64 1, label %case.arm.1.50 ]
case.arm.0.42:
  %t44 = getelementptr ptr, ptr %t36, i32 1
  %t45 = load ptr, ptr %t44
  %t46 = call ptr @malloc(i64 16)
  %t47 = inttoptr i64 0 to ptr
  %t48 = getelementptr ptr, ptr %t46, i32 0
  store ptr %t47, ptr %t48
  %t49 = getelementptr ptr, ptr %t46, i32 1
  store ptr %t45, ptr %t49
  br label %case.end.0.43
case.end.0.43:
  br label %case.join.41
case.arm.1.50:
  %t52 = getelementptr ptr, ptr %t36, i32 1
  %t53 = load ptr, ptr %t52
  %t54 = call ptr @malloc(i64 8)
  %t55 = inttoptr i64 0 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  %t57 = call ptr @malloc(i64 8)
  %t58 = inttoptr i64 0 to ptr
  %t59 = getelementptr ptr, ptr %t57, i32 0
  store ptr %t58, ptr %t59
  %t60 = call ptr @v_and(ptr %t54, ptr %t57)
  %t61 = call ptr @v_showBool(ptr %t60)
  %t62 = call ptr @__concat(ptr %t53, ptr %t61)
  %t63 = getelementptr ptr, ptr %t62, i32 0
  %t64 = load ptr, ptr %t63
  %t65 = ptrtoint ptr %t64 to i64
  switch i64 %t65, label %case.default.66 [ i64 0, label %case.arm.0.68 i64 1, label %case.arm.1.76 ]
case.arm.0.68:
  %t70 = getelementptr ptr, ptr %t62, i32 1
  %t71 = load ptr, ptr %t70
  %t72 = call ptr @malloc(i64 16)
  %t73 = inttoptr i64 0 to ptr
  %t74 = getelementptr ptr, ptr %t72, i32 0
  store ptr %t73, ptr %t74
  %t75 = getelementptr ptr, ptr %t72, i32 1
  store ptr %t71, ptr %t75
  br label %case.end.0.69
case.end.0.69:
  br label %case.join.67
case.arm.1.76:
  %t78 = getelementptr ptr, ptr %t62, i32 1
  %t79 = load ptr, ptr %t78
  %t80 = call ptr @malloc(i64 8)
  %t81 = inttoptr i64 1 to ptr
  %t82 = getelementptr ptr, ptr %t80, i32 0
  store ptr %t81, ptr %t82
  %t83 = call ptr @malloc(i64 8)
  %t84 = inttoptr i64 1 to ptr
  %t85 = getelementptr ptr, ptr %t83, i32 0
  store ptr %t84, ptr %t85
  %t86 = call ptr @v_or(ptr %t80, ptr %t83)
  %t87 = call ptr @v_showBool(ptr %t86)
  %t88 = call ptr @__concat(ptr %t79, ptr %t87)
  %t89 = getelementptr ptr, ptr %t88, i32 0
  %t90 = load ptr, ptr %t89
  %t91 = ptrtoint ptr %t90 to i64
  switch i64 %t91, label %case.default.92 [ i64 0, label %case.arm.0.94 i64 1, label %case.arm.1.102 ]
case.arm.0.94:
  %t96 = getelementptr ptr, ptr %t88, i32 1
  %t97 = load ptr, ptr %t96
  %t98 = call ptr @malloc(i64 16)
  %t99 = inttoptr i64 0 to ptr
  %t100 = getelementptr ptr, ptr %t98, i32 0
  store ptr %t99, ptr %t100
  %t101 = getelementptr ptr, ptr %t98, i32 1
  store ptr %t97, ptr %t101
  br label %case.end.0.95
case.end.0.95:
  br label %case.join.93
case.arm.1.102:
  %t104 = getelementptr ptr, ptr %t88, i32 1
  %t105 = load ptr, ptr %t104
  %t106 = call ptr @malloc(i64 8)
  %t107 = inttoptr i64 0 to ptr
  %t108 = getelementptr ptr, ptr %t106, i32 0
  store ptr %t107, ptr %t108
  %t109 = call ptr @malloc(i64 8)
  %t110 = inttoptr i64 1 to ptr
  %t111 = getelementptr ptr, ptr %t109, i32 0
  store ptr %t110, ptr %t111
  %t112 = call ptr @v_or(ptr %t106, ptr %t109)
  %t113 = call ptr @v_showBool(ptr %t112)
  %t114 = call ptr @__concat(ptr %t105, ptr %t113)
  br label %case.end.1.103
case.end.1.103:
  br label %case.join.93
case.default.92:
  unreachable
case.join.93:
  %t115 = phi ptr [%t98, %case.end.0.95], [%t114, %case.end.1.103]
  br label %case.end.1.77
case.end.1.77:
  br label %case.join.67
case.default.66:
  unreachable
case.join.67:
  %t116 = phi ptr [%t72, %case.end.0.69], [%t115, %case.end.1.77]
  br label %case.end.1.51
case.end.1.51:
  br label %case.join.41
case.default.40:
  unreachable
case.join.41:
  %t117 = phi ptr [%t46, %case.end.0.43], [%t116, %case.end.1.51]
  br label %case.end.1.25
case.end.1.25:
  br label %case.join.15
case.default.14:
  unreachable
case.join.15:
  %t118 = phi ptr [%t20, %case.end.0.17], [%t117, %case.end.1.25]
  %t119 = call ptr @v__let_2(ptr %t118)
  ret ptr %t119
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
  %t12 = getelementptr [16 x i8], ptr @.str.2, i64 0, i64 0
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
