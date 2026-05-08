; External C declarations
declare ptr @malloc(i64)
declare ptr @memcpy(ptr, ptr, i64)
declare i64 @strlen(ptr)
declare i64 @write(i32, ptr, i64)
declare i32 @printf(ptr, ...)
declare i32 @snprintf(ptr, i64, ptr, ...)

@.fmt_i32 = private unnamed_addr constant [3 x i8] c"%d\00"
@.fmt_u8 = private unnamed_addr constant [3 x i8] c"%u\00"
@.empty = private unnamed_addr constant {i32, i32} { i32 0, i32 0 }

@.str.0 = private unnamed_addr constant {i32, i32, [6 x i8]} { i32 6, i32 6, [6 x i8] c"ErrorA" }
@.str.1 = private unnamed_addr constant {i32, i32, [6 x i8]} { i32 6, i32 6, [6 x i8] c"ErrorC" }
@.str.2 = private unnamed_addr constant {i32, i32, [6 x i8]} { i32 6, i32 6, [6 x i8] c"ErrorB" }
@.str.3 = private unnamed_addr constant {i32, i32, [3 x i8]} { i32 3, i32 3, [3 x i8] c"Ok " }
@.str.4 = private unnamed_addr constant {i32, i32, [15 x i8]} { i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }

define internal ptr @__concat(ptr %a, ptr %b) {
  %ba = load i32, ptr %a
  %ua_p = getelementptr i8, ptr %a, i64 4
  %ua = load i32, ptr %ua_p
  %bb = load i32, ptr %b
  %ub_p = getelementptr i8, ptr %b, i64 4
  %ub = load i32, ptr %ub_p
  %ua64 = zext i32 %ua to i64
  %ub64 = zext i32 %ub to i64
  %usum64 = add i64 %ua64, %ub64
  %over = icmp ugt i64 %usum64, 134217728
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
  %ba64 = zext i32 %ba to i64
  %bb64 = zext i32 %bb to i64
  %bsum64 = add i64 %ba64, %bb64
  %alloc64 = add i64 %bsum64, 8
  %buf = call ptr @malloc(i64 %alloc64)
  %bsum32 = trunc i64 %bsum64 to i32
  store i32 %bsum32, ptr %buf
  %usum32 = trunc i64 %usum64 to i32
  %buf_u16p = getelementptr i8, ptr %buf, i64 4
  store i32 %usum32, ptr %buf_u16p
  %buf_payload = getelementptr i8, ptr %buf, i64 8
  %a_payload = getelementptr i8, ptr %a, i64 8
  call ptr @memcpy(ptr %buf_payload, ptr %a_payload, i64 %ba64)
  %buf_payload_b = getelementptr i8, ptr %buf_payload, i64 %ba64
  %b_payload = getelementptr i8, ptr %b, i64 8
  call ptr @memcpy(ptr %buf_payload_b, ptr %b_payload, i64 %bb64)
  %right = call ptr @malloc(i64 16)
  %right_tag = inttoptr i64 1 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %buf, ptr %right_f
  ret ptr %right
}


define internal ptr @__print(ptr %s) {
  %byte_count = load i32, ptr %s
  %byte_count_64 = zext i32 %byte_count to i64
  %payload = getelementptr i8, ptr %s, i64 8
  call i64 @write(i32 1, ptr %payload, i64 %byte_count_64)
  %unit = call ptr @malloc(i64 8)
  %unit_tag_ptr = getelementptr ptr, ptr %unit, i32 0
  %unit_tag = inttoptr i64 0 to ptr
  store ptr %unit_tag, ptr %unit_tag_ptr
  ret ptr %unit
}


define internal ptr @__showInt32(ptr %p) {
  %v = load i32, ptr %p
  %buf = call ptr @malloc(i64 24)
  %payload = getelementptr i8, ptr %buf, i64 8
  %n = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %payload, i64 16, ptr @.fmt_i32, i32 %v)
  store i32 %n, ptr %buf
  %u16p = getelementptr i8, ptr %buf, i64 4
  store i32 %n, ptr %u16p
  ret ptr %buf
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
  %byte_count_64 = load i64, ptr %i_p
  %byte_count_32 = trunc i64 %byte_count_64 to i32
  %alloc_size_64 = add i64 %byte_count_64, 8
  %wrapped = call ptr @malloc(i64 %alloc_size_64)
  store i32 %byte_count_32, ptr %wrapped
  %wrapped_u16p = getelementptr i8, ptr %wrapped, i64 4
  store i32 %n_final, ptr %wrapped_u16p
  %wrapped_payload = getelementptr i8, ptr %wrapped, i64 8
  call ptr @memcpy(ptr %wrapped_payload, ptr %arg, i64 %byte_count_64)
  %right = call ptr @malloc(i64 16)
  %right_tag = inttoptr i64 1 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %wrapped, ptr %right_f
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


define internal ptr @v_pureEither(ptr %v_x) {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v_x, ptr %t3
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

define internal ptr @v_op1() {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @malloc(i64 4)
  store i32 1, ptr %t3
  %t4 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t4
  ret ptr %t0
}

define internal ptr @v_op2() {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 0 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @malloc(i64 16)
  %t4 = inttoptr i64 435006518 to ptr
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
  ret ptr %t0
}

define internal ptr @v_op3() {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 1 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @malloc(i64 4)
  store i32 3, ptr %t3
  %t4 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t4
  ret ptr %t0
}

define internal ptr @v_f() {
  %t0 = call ptr @v_op1()
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 0, label %case.arm.0.6 i64 1, label %case.arm.1.18 ]
case.arm.0.6:
  %t8 = getelementptr ptr, ptr %t0, i32 1
  %t9 = load ptr, ptr %t8
  %t10 = call ptr @malloc(i64 16)
  %t11 = inttoptr i64 0 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  %t13 = call ptr @malloc(i64 16)
  %t14 = inttoptr i64 401451280 to ptr
  %t15 = getelementptr ptr, ptr %t13, i32 0
  store ptr %t14, ptr %t15
  %t16 = getelementptr ptr, ptr %t13, i32 1
  store ptr %t9, ptr %t16
  %t17 = getelementptr ptr, ptr %t10, i32 1
  store ptr %t13, ptr %t17
  br label %case.end.0.7
case.end.0.7:
  br label %case.join.5
case.arm.1.18:
  %t20 = getelementptr ptr, ptr %t0, i32 1
  %t21 = load ptr, ptr %t20
  %t22 = call ptr @v_op2()
  %t23 = getelementptr ptr, ptr %t22, i32 0
  %t24 = load ptr, ptr %t23
  %t25 = ptrtoint ptr %t24 to i64
  switch i64 %t25, label %case.default.26 [ i64 0, label %case.arm.0.28 i64 1, label %case.arm.1.36 ]
case.arm.0.28:
  %t30 = getelementptr ptr, ptr %t22, i32 1
  %t31 = load ptr, ptr %t30
  %t32 = call ptr @malloc(i64 16)
  %t33 = inttoptr i64 0 to ptr
  %t34 = getelementptr ptr, ptr %t32, i32 0
  store ptr %t33, ptr %t34
  %t35 = getelementptr ptr, ptr %t32, i32 1
  store ptr %t31, ptr %t35
  br label %case.end.0.29
case.end.0.29:
  br label %case.join.27
case.arm.1.36:
  %t38 = getelementptr ptr, ptr %t22, i32 1
  %t39 = load ptr, ptr %t38
  %t40 = call ptr @v_op3()
  %t41 = getelementptr ptr, ptr %t40, i32 0
  %t42 = load ptr, ptr %t41
  %t43 = ptrtoint ptr %t42 to i64
  switch i64 %t43, label %case.default.44 [ i64 0, label %case.arm.0.46 i64 1, label %case.arm.1.58 ]
case.arm.0.46:
  %t48 = getelementptr ptr, ptr %t40, i32 1
  %t49 = load ptr, ptr %t48
  %t50 = call ptr @malloc(i64 16)
  %t51 = inttoptr i64 0 to ptr
  %t52 = getelementptr ptr, ptr %t50, i32 0
  store ptr %t51, ptr %t52
  %t53 = call ptr @malloc(i64 16)
  %t54 = inttoptr i64 451784137 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  %t56 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t49, ptr %t56
  %t57 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t53, ptr %t57
  br label %case.end.0.47
case.end.0.47:
  br label %case.join.45
case.arm.1.58:
  %t60 = getelementptr ptr, ptr %t40, i32 1
  %t61 = load ptr, ptr %t60
  %t62 = call ptr @v_pureEither(ptr %t61)
  br label %case.end.1.59
case.end.1.59:
  br label %case.join.45
case.default.44:
  unreachable
case.join.45:
  %t63 = phi ptr [%t50, %case.end.0.47], [%t62, %case.end.1.59]
  br label %case.end.1.37
case.end.1.37:
  br label %case.join.27
case.default.26:
  unreachable
case.join.27:
  %t64 = phi ptr [%t32, %case.end.0.29], [%t63, %case.end.1.37]
  br label %case.end.1.19
case.end.1.19:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t65 = phi ptr [%t10, %case.end.0.7], [%t64, %case.end.1.19]
  ret ptr %t65
}

define internal ptr @v_describe(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.63 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_r, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr ptr, ptr %t8, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %case.default.12 [ i64 401451280, label %case.arm.401451280.14 i64 435006518, label %case.arm.435006518.30 i64 451784137, label %case.arm.451784137.46 ]
case.arm.401451280.14:
  %t16 = getelementptr ptr, ptr %t8, i32 1
  %t17 = load ptr, ptr %t16
  %t18 = getelementptr ptr, ptr %t17, i32 0
  %t19 = load ptr, ptr %t18
  %t20 = ptrtoint ptr %t19 to i64
  switch i64 %t20, label %case.default.21 [ i64 0, label %case.arm.0.23 ]
case.arm.0.23:
  %t25 = call ptr @malloc(i64 16)
  %t26 = inttoptr i64 1 to ptr
  %t27 = getelementptr ptr, ptr %t25, i32 0
  store ptr %t26, ptr %t27
  %t28 = getelementptr ptr, ptr %t25, i32 1
  store ptr @.str.0, ptr %t28
  br label %case.end.0.24
case.end.0.24:
  br label %case.join.22
case.default.21:
  unreachable
case.join.22:
  %t29 = phi ptr [%t25, %case.end.0.24]
  br label %case.end.401451280.15
case.end.401451280.15:
  br label %case.join.13
case.arm.435006518.30:
  %t32 = getelementptr ptr, ptr %t8, i32 1
  %t33 = load ptr, ptr %t32
  %t34 = getelementptr ptr, ptr %t33, i32 0
  %t35 = load ptr, ptr %t34
  %t36 = ptrtoint ptr %t35 to i64
  switch i64 %t36, label %case.default.37 [ i64 0, label %case.arm.0.39 ]
case.arm.0.39:
  %t41 = call ptr @malloc(i64 16)
  %t42 = inttoptr i64 1 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = getelementptr ptr, ptr %t41, i32 1
  store ptr @.str.1, ptr %t44
  br label %case.end.0.40
case.end.0.40:
  br label %case.join.38
case.default.37:
  unreachable
case.join.38:
  %t45 = phi ptr [%t41, %case.end.0.40]
  br label %case.end.435006518.31
case.end.435006518.31:
  br label %case.join.13
case.arm.451784137.46:
  %t48 = getelementptr ptr, ptr %t8, i32 1
  %t49 = load ptr, ptr %t48
  %t50 = getelementptr ptr, ptr %t49, i32 0
  %t51 = load ptr, ptr %t50
  %t52 = ptrtoint ptr %t51 to i64
  switch i64 %t52, label %case.default.53 [ i64 0, label %case.arm.0.55 ]
case.arm.0.55:
  %t57 = call ptr @malloc(i64 16)
  %t58 = inttoptr i64 1 to ptr
  %t59 = getelementptr ptr, ptr %t57, i32 0
  store ptr %t58, ptr %t59
  %t60 = getelementptr ptr, ptr %t57, i32 1
  store ptr @.str.2, ptr %t60
  br label %case.end.0.56
case.end.0.56:
  br label %case.join.54
case.default.53:
  unreachable
case.join.54:
  %t61 = phi ptr [%t57, %case.end.0.56]
  br label %case.end.451784137.47
case.end.451784137.47:
  br label %case.join.13
case.default.12:
  unreachable
case.join.13:
  %t62 = phi ptr [%t29, %case.end.401451280.15], [%t45, %case.end.435006518.31], [%t61, %case.end.451784137.47]
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.63:
  %t65 = getelementptr ptr, ptr %v_r, i32 1
  %t66 = load ptr, ptr %t65
  %t67 = call ptr @__showInt32(ptr %t66)
  %t68 = call ptr @__concat(ptr @.str.3, ptr %t67)
  br label %case.end.1.64
case.end.1.64:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t69 = phi ptr [%t62, %case.end.0.6], [%t68, %case.end.1.64]
  ret ptr %t69
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @v_f()
  %t1 = call ptr @v_describe(ptr %t0)
  %t2 = call ptr @v__let_2(ptr %t1)
  ret ptr %t2
}

define internal ptr @v__let_2(ptr %v_res) {
  %t0 = getelementptr ptr, ptr %v_res, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.21 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_res, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = call ptr @malloc(i64 24)
  %t10 = inttoptr i64 2 to ptr
  %t11 = getelementptr ptr, ptr %t9, i32 0
  store ptr %t10, ptr %t11
  %t12 = getelementptr ptr, ptr %t9, i32 1
  store ptr @.str.4, ptr %t12
  %t13 = call ptr @malloc(i64 16)
  %t14 = inttoptr i64 0 to ptr
  %t15 = getelementptr ptr, ptr %t13, i32 0
  store ptr %t14, ptr %t15
  %t16 = call ptr @malloc(i64 8)
  %t17 = inttoptr i64 0 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = getelementptr ptr, ptr %t13, i32 1
  store ptr %t16, ptr %t19
  %t20 = getelementptr ptr, ptr %t9, i32 2
  store ptr %t13, ptr %t20
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.21:
  %t23 = getelementptr ptr, ptr %v_res, i32 1
  %t24 = load ptr, ptr %t23
  %t25 = call ptr @malloc(i64 24)
  %t26 = inttoptr i64 2 to ptr
  %t27 = getelementptr ptr, ptr %t25, i32 0
  store ptr %t26, ptr %t27
  %t28 = getelementptr ptr, ptr %t25, i32 1
  store ptr %t24, ptr %t28
  %t29 = call ptr @malloc(i64 16)
  %t30 = inttoptr i64 0 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = call ptr @malloc(i64 8)
  %t33 = inttoptr i64 0 to ptr
  %t34 = getelementptr ptr, ptr %t32, i32 0
  store ptr %t33, ptr %t34
  %t35 = getelementptr ptr, ptr %t29, i32 1
  store ptr %t32, ptr %t35
  %t36 = getelementptr ptr, ptr %t25, i32 2
  store ptr %t29, ptr %t36
  br label %case.end.1.22
case.end.1.22:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t37 = phi ptr [%t9, %case.end.0.6], [%t25, %case.end.1.22]
  ret ptr %t37
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
