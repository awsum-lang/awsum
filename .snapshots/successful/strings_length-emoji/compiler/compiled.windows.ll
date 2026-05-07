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

@.str.0 = private unnamed_addr constant [4 x i8] c"=ok\00"
@.str.1 = private unnamed_addr constant [16 x i8] c"=FAIL(expected=\00"
@.str.2 = private unnamed_addr constant [7 x i8] c", got=\00"
@.str.3 = private unnamed_addr constant [2 x i8] c")\00"
@.str.4 = private unnamed_addr constant [5 x i8] c"\F0\9F\94\A5\00"
@.str.5 = private unnamed_addr constant [17 x i8] c"lengthCodePoints\00"
@.str.6 = private unnamed_addr constant [21 x i8] c"lengthUtf16CodeUnits\00"
@.str.7 = private unnamed_addr constant [18 x i8] c"lengthBytesAsUtf8\00"
@.str.8 = private unnamed_addr constant [3 x i8] c", \00"
@.str.9 = private unnamed_addr constant [16 x i8] c"STRING_TOO_LONG\00"

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


define internal ptr @__showUInt32(ptr %p) {
  %v = load i32, ptr %p
  %buf = call ptr @malloc(i64 16)
  call i32 (ptr, i64, ptr, ...) @snprintf(ptr %buf, i64 16, ptr @.fmt_u8, i32 %v)
  ret ptr %buf
}


define internal ptr @__eqUInt32(ptr %a, ptr %b) {
  %va = load i32, ptr %a
  %vb = load i32, ptr %b
  %eq = icmp eq i32 %va, %vb
  %tag = select i1 %eq, i64 0, i64 1
  %box = call ptr @malloc(i64 8)
  %tag_ptr = inttoptr i64 %tag to ptr
  store ptr %tag_ptr, ptr %box
  ret ptr %box
}


define internal ptr @__lengthCodePoints(ptr %s) {
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
  br i1 %is_cont, label %step, label %inc
inc:
  %n0 = load i32, ptr %n_p
  %n1 = add i32 %n0, 1
  store i32 %n1, ptr %n_p
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


define internal ptr @__lengthBytesAsUtf8(ptr %s) {
  %len64 = call i64 @strlen(ptr %s)
  %len32 = trunc i64 %len64 to i32
  %box = call ptr @malloc(i64 4)
  store i32 %len32, ptr %box
  ret ptr %box
}


define internal ptr @__entryArgEither(ptr %arg) {
entry:
  %i_p = alloca i64, align 8
  store i64 0, ptr %i_p
  %n_p = alloca i32, align 4
  store i32 0, ptr %n_p
  %surr_p = alloca i32, align 4
  store i32 0, ptr %surr_p
  br label %head
head:
  %i = load i64, ptr %i_p
  %bp = getelementptr i8, ptr %arg, i64 %i
  %b = load i8, ptr %bp
  %is_nul = icmp eq i8 %b, 0
  br i1 %is_nul, label %scan_done, label %body
body:
  %bz = zext i8 %b to i32
  %top2 = and i32 %bz, 192
  %is_cont = icmp eq i32 %top2, 128
  br i1 %is_cont, label %step, label %surrogate_check
surrogate_check:
  %is_ED = icmp eq i32 %bz, 237
  br i1 %is_ED, label %peek_next, label %check4
peek_next:
  %i_next = add i64 %i, 1
  %bp_next = getelementptr i8, ptr %arg, i64 %i_next
  %nxt = load i8, ptr %bp_next
  %nxt_z = zext i8 %nxt to i32
  %nxt_top3 = and i32 %nxt_z, 224
  %is_surr = icmp eq i32 %nxt_top3, 160
  br i1 %is_surr, label %set_surr, label %check4
set_surr:
  store i32 1, ptr %surr_p
  br label %check4
check4:
  %top5 = and i32 %bz, 248
  %is_4 = icmp eq i32 %top5, 240
  br i1 %is_4, label %add2, label %add1
add2:
  %n2 = load i32, ptr %n_p
  %n2_new = add i32 %n2, 2
  store i32 %n2_new, ptr %n_p
  %over2 = icmp ugt i32 %n2_new, 134217728
  br i1 %over2, label %scan_done, label %step
add1:
  %n1 = load i32, ptr %n_p
  %n1_new = add i32 %n1, 1
  store i32 %n1_new, ptr %n_p
  %over1 = icmp ugt i32 %n1_new, 134217728
  br i1 %over1, label %scan_done, label %step
step:
  %i1 = add i64 %i, 1
  store i64 %i1, ptr %i_p
  br label %head
scan_done:
  %n_final = load i32, ptr %n_p
  %over_final = icmp ugt i32 %n_final, 134217728
  br i1 %over_final, label %too_long, label %check_surr
check_surr:
  %surr_final = load i32, ptr %surr_p
  %is_surr_set = icmp ne i32 %surr_final, 0
  br i1 %is_surr_set, label %unpaired, label %fits
fits:
  %right = call ptr @malloc(i64 16)
  %right_tag = inttoptr i64 1 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %arg, ptr %right_f
  ret ptr %right
too_long:
  %tl_inner = call ptr @malloc(i64 8)
  %tl_inner_tag = inttoptr i64 0 to ptr
  store ptr %tl_inner_tag, ptr %tl_inner
  %tl_row = call ptr @malloc(i64 16)
  %tl_row_tag = inttoptr i64 589989748 to ptr
  store ptr %tl_row_tag, ptr %tl_row
  %tl_row_f = getelementptr ptr, ptr %tl_row, i32 1
  store ptr %tl_inner, ptr %tl_row_f
  %tl_left = call ptr @malloc(i64 16)
  %tl_left_tag = inttoptr i64 0 to ptr
  store ptr %tl_left_tag, ptr %tl_left
  %tl_left_f = getelementptr ptr, ptr %tl_left, i32 1
  store ptr %tl_row, ptr %tl_left_f
  ret ptr %tl_left
unpaired:
  %us_inner = call ptr @malloc(i64 8)
  %us_inner_tag = inttoptr i64 0 to ptr
  store ptr %us_inner_tag, ptr %us_inner
  %us_row = call ptr @malloc(i64 16)
  %us_row_tag = inttoptr i64 502975519 to ptr
  store ptr %us_row_tag, ptr %us_row
  %us_row_f = getelementptr ptr, ptr %us_row, i32 1
  store ptr %us_inner, ptr %us_row_f
  %us_left = call ptr @malloc(i64 16)
  %us_left_tag = inttoptr i64 0 to ptr
  store ptr %us_left_tag, ptr %us_left
  %us_left_f = getelementptr ptr, ptr %us_left, i32 1
  store ptr %us_row, ptr %us_left_f
  ret ptr %us_left
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

define internal ptr @v_check(ptr %v_expected, ptr %v_actual, ptr %v_label) {
  %t0 = call ptr @__eqUInt32(ptr %v_expected, ptr %v_actual)
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 0, label %case.arm.0.6 i64 1, label %case.arm.1.10 ]
case.arm.0.6:
  %t8 = getelementptr [4 x i8], ptr @.str.0, i64 0, i64 0
  %t9 = call ptr @__concat(ptr %v_label, ptr %t8)
  br label %case.end.0.7
case.end.0.7:
  br label %case.join.5
case.arm.1.10:
  %t12 = getelementptr [16 x i8], ptr @.str.1, i64 0, i64 0
  %t13 = call ptr @__concat(ptr %v_label, ptr %t12)
  %t14 = getelementptr ptr, ptr %t13, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %case.default.17 [ i64 0, label %case.arm.0.19 i64 1, label %case.arm.1.27 ]
case.arm.0.19:
  %t21 = getelementptr ptr, ptr %t13, i32 1
  %t22 = load ptr, ptr %t21
  %t23 = call ptr @malloc(i64 16)
  %t24 = inttoptr i64 0 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  %t26 = getelementptr ptr, ptr %t23, i32 1
  store ptr %t22, ptr %t26
  br label %case.end.0.20
case.end.0.20:
  br label %case.join.18
case.arm.1.27:
  %t29 = getelementptr ptr, ptr %t13, i32 1
  %t30 = load ptr, ptr %t29
  %t31 = call ptr @__showUInt32(ptr %v_expected)
  %t32 = call ptr @__concat(ptr %t30, ptr %t31)
  %t33 = getelementptr ptr, ptr %t32, i32 0
  %t34 = load ptr, ptr %t33
  %t35 = ptrtoint ptr %t34 to i64
  switch i64 %t35, label %case.default.36 [ i64 0, label %case.arm.0.38 i64 1, label %case.arm.1.46 ]
case.arm.0.38:
  %t40 = getelementptr ptr, ptr %t32, i32 1
  %t41 = load ptr, ptr %t40
  %t42 = call ptr @malloc(i64 16)
  %t43 = inttoptr i64 0 to ptr
  %t44 = getelementptr ptr, ptr %t42, i32 0
  store ptr %t43, ptr %t44
  %t45 = getelementptr ptr, ptr %t42, i32 1
  store ptr %t41, ptr %t45
  br label %case.end.0.39
case.end.0.39:
  br label %case.join.37
case.arm.1.46:
  %t48 = getelementptr ptr, ptr %t32, i32 1
  %t49 = load ptr, ptr %t48
  %t50 = getelementptr [7 x i8], ptr @.str.2, i64 0, i64 0
  %t51 = call ptr @__concat(ptr %t49, ptr %t50)
  %t52 = getelementptr ptr, ptr %t51, i32 0
  %t53 = load ptr, ptr %t52
  %t54 = ptrtoint ptr %t53 to i64
  switch i64 %t54, label %case.default.55 [ i64 0, label %case.arm.0.57 i64 1, label %case.arm.1.65 ]
case.arm.0.57:
  %t59 = getelementptr ptr, ptr %t51, i32 1
  %t60 = load ptr, ptr %t59
  %t61 = call ptr @malloc(i64 16)
  %t62 = inttoptr i64 0 to ptr
  %t63 = getelementptr ptr, ptr %t61, i32 0
  store ptr %t62, ptr %t63
  %t64 = getelementptr ptr, ptr %t61, i32 1
  store ptr %t60, ptr %t64
  br label %case.end.0.58
case.end.0.58:
  br label %case.join.56
case.arm.1.65:
  %t67 = getelementptr ptr, ptr %t51, i32 1
  %t68 = load ptr, ptr %t67
  %t69 = call ptr @__showUInt32(ptr %v_actual)
  %t70 = call ptr @__concat(ptr %t68, ptr %t69)
  %t71 = getelementptr ptr, ptr %t70, i32 0
  %t72 = load ptr, ptr %t71
  %t73 = ptrtoint ptr %t72 to i64
  switch i64 %t73, label %case.default.74 [ i64 0, label %case.arm.0.76 i64 1, label %case.arm.1.84 ]
case.arm.0.76:
  %t78 = getelementptr ptr, ptr %t70, i32 1
  %t79 = load ptr, ptr %t78
  %t80 = call ptr @malloc(i64 16)
  %t81 = inttoptr i64 0 to ptr
  %t82 = getelementptr ptr, ptr %t80, i32 0
  store ptr %t81, ptr %t82
  %t83 = getelementptr ptr, ptr %t80, i32 1
  store ptr %t79, ptr %t83
  br label %case.end.0.77
case.end.0.77:
  br label %case.join.75
case.arm.1.84:
  %t86 = getelementptr ptr, ptr %t70, i32 1
  %t87 = load ptr, ptr %t86
  %t88 = getelementptr [2 x i8], ptr @.str.3, i64 0, i64 0
  %t89 = call ptr @__concat(ptr %t87, ptr %t88)
  br label %case.end.1.85
case.end.1.85:
  br label %case.join.75
case.default.74:
  unreachable
case.join.75:
  %t90 = phi ptr [%t80, %case.end.0.77], [%t89, %case.end.1.85]
  br label %case.end.1.66
case.end.1.66:
  br label %case.join.56
case.default.55:
  unreachable
case.join.56:
  %t91 = phi ptr [%t61, %case.end.0.58], [%t90, %case.end.1.66]
  br label %case.end.1.47
case.end.1.47:
  br label %case.join.37
case.default.36:
  unreachable
case.join.37:
  %t92 = phi ptr [%t42, %case.end.0.39], [%t91, %case.end.1.47]
  br label %case.end.1.28
case.end.1.28:
  br label %case.join.18
case.default.17:
  unreachable
case.join.18:
  %t93 = phi ptr [%t23, %case.end.0.20], [%t92, %case.end.1.28]
  br label %case.end.1.11
case.end.1.11:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t94 = phi ptr [%t9, %case.end.0.7], [%t93, %case.end.1.11]
  ret ptr %t94
}

define internal ptr @v_run() {
  %t0 = call ptr @malloc(i64 4)
  store i32 1, ptr %t0
  %t1 = getelementptr [2 x i8], ptr @.str.4, i64 0, i64 0
  %t2 = call ptr @__lengthCodePoints(ptr %t1)
  %t3 = getelementptr [17 x i8], ptr @.str.5, i64 0, i64 0
  %t4 = call ptr @v_check(ptr %t0, ptr %t2, ptr %t3)
  %t5 = getelementptr ptr, ptr %t4, i32 0
  %t6 = load ptr, ptr %t5
  %t7 = ptrtoint ptr %t6 to i64
  switch i64 %t7, label %case.default.8 [ i64 0, label %case.arm.0.10 i64 1, label %case.arm.1.18 ]
case.arm.0.10:
  %t12 = getelementptr ptr, ptr %t4, i32 1
  %t13 = load ptr, ptr %t12
  %t14 = call ptr @malloc(i64 16)
  %t15 = inttoptr i64 0 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  %t17 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t13, ptr %t17
  br label %case.end.0.11
case.end.0.11:
  br label %case.join.9
case.arm.1.18:
  %t20 = getelementptr ptr, ptr %t4, i32 1
  %t21 = load ptr, ptr %t20
  %t22 = call ptr @malloc(i64 4)
  store i32 2, ptr %t22
  %t23 = getelementptr [2 x i8], ptr @.str.4, i64 0, i64 0
  %t24 = call ptr @__lengthUtf16CodeUnits(ptr %t23)
  %t25 = getelementptr [21 x i8], ptr @.str.6, i64 0, i64 0
  %t26 = call ptr @v_check(ptr %t22, ptr %t24, ptr %t25)
  %t27 = getelementptr ptr, ptr %t26, i32 0
  %t28 = load ptr, ptr %t27
  %t29 = ptrtoint ptr %t28 to i64
  switch i64 %t29, label %case.default.30 [ i64 0, label %case.arm.0.32 i64 1, label %case.arm.1.40 ]
case.arm.0.32:
  %t34 = getelementptr ptr, ptr %t26, i32 1
  %t35 = load ptr, ptr %t34
  %t36 = call ptr @malloc(i64 16)
  %t37 = inttoptr i64 0 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t35, ptr %t39
  br label %case.end.0.33
case.end.0.33:
  br label %case.join.31
case.arm.1.40:
  %t42 = getelementptr ptr, ptr %t26, i32 1
  %t43 = load ptr, ptr %t42
  %t44 = call ptr @malloc(i64 4)
  store i32 4, ptr %t44
  %t45 = getelementptr [2 x i8], ptr @.str.4, i64 0, i64 0
  %t46 = call ptr @__lengthBytesAsUtf8(ptr %t45)
  %t47 = getelementptr [18 x i8], ptr @.str.7, i64 0, i64 0
  %t48 = call ptr @v_check(ptr %t44, ptr %t46, ptr %t47)
  %t49 = getelementptr ptr, ptr %t48, i32 0
  %t50 = load ptr, ptr %t49
  %t51 = ptrtoint ptr %t50 to i64
  switch i64 %t51, label %case.default.52 [ i64 0, label %case.arm.0.54 i64 1, label %case.arm.1.62 ]
case.arm.0.54:
  %t56 = getelementptr ptr, ptr %t48, i32 1
  %t57 = load ptr, ptr %t56
  %t58 = call ptr @malloc(i64 16)
  %t59 = inttoptr i64 0 to ptr
  %t60 = getelementptr ptr, ptr %t58, i32 0
  store ptr %t59, ptr %t60
  %t61 = getelementptr ptr, ptr %t58, i32 1
  store ptr %t57, ptr %t61
  br label %case.end.0.55
case.end.0.55:
  br label %case.join.53
case.arm.1.62:
  %t64 = getelementptr ptr, ptr %t48, i32 1
  %t65 = load ptr, ptr %t64
  %t66 = getelementptr [3 x i8], ptr @.str.8, i64 0, i64 0
  %t67 = call ptr @__concat(ptr %t21, ptr %t66)
  %t68 = getelementptr ptr, ptr %t67, i32 0
  %t69 = load ptr, ptr %t68
  %t70 = ptrtoint ptr %t69 to i64
  switch i64 %t70, label %case.default.71 [ i64 0, label %case.arm.0.73 i64 1, label %case.arm.1.81 ]
case.arm.0.73:
  %t75 = getelementptr ptr, ptr %t67, i32 1
  %t76 = load ptr, ptr %t75
  %t77 = call ptr @malloc(i64 16)
  %t78 = inttoptr i64 0 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t76, ptr %t80
  br label %case.end.0.74
case.end.0.74:
  br label %case.join.72
case.arm.1.81:
  %t83 = getelementptr ptr, ptr %t67, i32 1
  %t84 = load ptr, ptr %t83
  %t85 = call ptr @__concat(ptr %t84, ptr %t43)
  %t86 = getelementptr ptr, ptr %t85, i32 0
  %t87 = load ptr, ptr %t86
  %t88 = ptrtoint ptr %t87 to i64
  switch i64 %t88, label %case.default.89 [ i64 0, label %case.arm.0.91 i64 1, label %case.arm.1.99 ]
case.arm.0.91:
  %t93 = getelementptr ptr, ptr %t85, i32 1
  %t94 = load ptr, ptr %t93
  %t95 = call ptr @malloc(i64 16)
  %t96 = inttoptr i64 0 to ptr
  %t97 = getelementptr ptr, ptr %t95, i32 0
  store ptr %t96, ptr %t97
  %t98 = getelementptr ptr, ptr %t95, i32 1
  store ptr %t94, ptr %t98
  br label %case.end.0.92
case.end.0.92:
  br label %case.join.90
case.arm.1.99:
  %t101 = getelementptr ptr, ptr %t85, i32 1
  %t102 = load ptr, ptr %t101
  %t103 = getelementptr [3 x i8], ptr @.str.8, i64 0, i64 0
  %t104 = call ptr @__concat(ptr %t102, ptr %t103)
  %t105 = getelementptr ptr, ptr %t104, i32 0
  %t106 = load ptr, ptr %t105
  %t107 = ptrtoint ptr %t106 to i64
  switch i64 %t107, label %case.default.108 [ i64 0, label %case.arm.0.110 i64 1, label %case.arm.1.118 ]
case.arm.0.110:
  %t112 = getelementptr ptr, ptr %t104, i32 1
  %t113 = load ptr, ptr %t112
  %t114 = call ptr @malloc(i64 16)
  %t115 = inttoptr i64 0 to ptr
  %t116 = getelementptr ptr, ptr %t114, i32 0
  store ptr %t115, ptr %t116
  %t117 = getelementptr ptr, ptr %t114, i32 1
  store ptr %t113, ptr %t117
  br label %case.end.0.111
case.end.0.111:
  br label %case.join.109
case.arm.1.118:
  %t120 = getelementptr ptr, ptr %t104, i32 1
  %t121 = load ptr, ptr %t120
  %t122 = call ptr @__concat(ptr %t121, ptr %t65)
  br label %case.end.1.119
case.end.1.119:
  br label %case.join.109
case.default.108:
  unreachable
case.join.109:
  %t123 = phi ptr [%t114, %case.end.0.111], [%t122, %case.end.1.119]
  br label %case.end.1.100
case.end.1.100:
  br label %case.join.90
case.default.89:
  unreachable
case.join.90:
  %t124 = phi ptr [%t95, %case.end.0.92], [%t123, %case.end.1.100]
  br label %case.end.1.82
case.end.1.82:
  br label %case.join.72
case.default.71:
  unreachable
case.join.72:
  %t125 = phi ptr [%t77, %case.end.0.74], [%t124, %case.end.1.82]
  br label %case.end.1.63
case.end.1.63:
  br label %case.join.53
case.default.52:
  unreachable
case.join.53:
  %t126 = phi ptr [%t58, %case.end.0.55], [%t125, %case.end.1.63]
  br label %case.end.1.41
case.end.1.41:
  br label %case.join.31
case.default.30:
  unreachable
case.join.31:
  %t127 = phi ptr [%t36, %case.end.0.33], [%t126, %case.end.1.41]
  br label %case.end.1.19
case.end.1.19:
  br label %case.join.9
case.default.8:
  unreachable
case.join.9:
  %t128 = phi ptr [%t14, %case.end.0.11], [%t127, %case.end.1.19]
  ret ptr %t128
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @v_run()
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 0, label %case.arm.0.6 i64 1, label %case.arm.1.23 ]
case.arm.0.6:
  %t8 = getelementptr ptr, ptr %t0, i32 1
  %t9 = load ptr, ptr %t8
  %t10 = call ptr @malloc(i64 24)
  %t11 = inttoptr i64 2 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  %t13 = getelementptr [16 x i8], ptr @.str.9, i64 0, i64 0
  %t14 = getelementptr ptr, ptr %t10, i32 1
  store ptr %t13, ptr %t14
  %t15 = call ptr @malloc(i64 16)
  %t16 = inttoptr i64 0 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = call ptr @malloc(i64 8)
  %t19 = inttoptr i64 0 to ptr
  %t20 = getelementptr ptr, ptr %t18, i32 0
  store ptr %t19, ptr %t20
  %t21 = getelementptr ptr, ptr %t15, i32 1
  store ptr %t18, ptr %t21
  %t22 = getelementptr ptr, ptr %t10, i32 2
  store ptr %t15, ptr %t22
  br label %case.end.0.7
case.end.0.7:
  br label %case.join.5
case.arm.1.23:
  %t25 = getelementptr ptr, ptr %t0, i32 1
  %t26 = load ptr, ptr %t25
  %t27 = call ptr @malloc(i64 24)
  %t28 = inttoptr i64 2 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  %t30 = getelementptr ptr, ptr %t27, i32 1
  store ptr %t26, ptr %t30
  %t31 = call ptr @malloc(i64 16)
  %t32 = inttoptr i64 0 to ptr
  %t33 = getelementptr ptr, ptr %t31, i32 0
  store ptr %t32, ptr %t33
  %t34 = call ptr @malloc(i64 8)
  %t35 = inttoptr i64 0 to ptr
  %t36 = getelementptr ptr, ptr %t34, i32 0
  store ptr %t35, ptr %t36
  %t37 = getelementptr ptr, ptr %t31, i32 1
  store ptr %t34, ptr %t37
  %t38 = getelementptr ptr, ptr %t27, i32 2
  store ptr %t31, ptr %t38
  br label %case.end.1.24
case.end.1.24:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t39 = phi ptr [%t10, %case.end.0.7], [%t27, %case.end.1.24]
  ret ptr %t39
}

declare ptr @GetCommandLineW()
declare ptr @CommandLineToArgvW(ptr, ptr)
declare i32 @WideCharToMultiByte(i32, i32, ptr, i32, ptr, i32, ptr, ptr)

define i32 @main(i32 %argc_posix, ptr %argv_posix) {
entry:
  %cmdline = call ptr @GetCommandLineW()
  %argc_slot = alloca i32
  %argv_w = call ptr @CommandLineToArgvW(ptr %cmdline, ptr %argc_slot)
  %argc_w = load i32, ptr %argc_slot
  %has_arg = icmp sgt i32 %argc_w, 1
  br i1 %has_arg, label %with_arg, label %no_arg
with_arg:
  %arg_w_slot = getelementptr ptr, ptr %argv_w, i64 1
  %arg_w = load ptr, ptr %arg_w_slot
  %needed = call i32 @WideCharToMultiByte(i32 65001, i32 0, ptr %arg_w, i32 -1, ptr null, i32 0, ptr null, ptr null)
  %need_ok = icmp sgt i32 %needed, 0
  br i1 %need_ok, label %do_convert, label %no_arg
do_convert:
  %needed64 = sext i32 %needed to i64
  %buf = call ptr @malloc(i64 %needed64)
  %written = call i32 @WideCharToMultiByte(i32 65001, i32 0, ptr %arg_w, i32 -1, ptr %buf, i32 %needed, ptr null, ptr null)
  br label %call_main
no_arg:
  br label %call_main
call_main:
  %input = phi ptr [%buf, %do_convert], [@.empty, %no_arg]
  %either = call ptr @__entryArgEither(ptr %input)
  %io = call ptr @v_main(ptr %either)
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
