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
@.cli_arg = internal global ptr null

@.str.0 = private unnamed_addr constant {i32, i32, [6 x i8]} { i32 6, i32 6, [6 x i8] c"got E1" }
@.str.1 = private unnamed_addr constant {i32, i32, [6 x i8]} { i32 6, i32 6, [6 x i8] c"got E2" }

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
  %right_tag = inttoptr i64 4 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %wrapped, ptr %right_f
  ret ptr %right
too_long:
  %tl_inner = call ptr @malloc(i64 8)
  %tl_inner_tag = inttoptr i64 15 to ptr
  store ptr %tl_inner_tag, ptr %tl_inner
  %tl_row = call ptr @malloc(i64 16)
  %tl_row_tag = inttoptr i64 589989748 to ptr
  store ptr %tl_row_tag, ptr %tl_row
  %tl_row_f = getelementptr ptr, ptr %tl_row, i32 1
  store ptr %tl_inner, ptr %tl_row_f
  %tl_left = call ptr @malloc(i64 16)
  %tl_left_tag = inttoptr i64 3 to ptr
  store ptr %tl_left_tag, ptr %tl_left
  %tl_left_f = getelementptr ptr, ptr %tl_left, i32 1
  store ptr %tl_row, ptr %tl_left_f
  ret ptr %tl_left
unpaired:
  %us_inner = call ptr @malloc(i64 8)
  %us_inner_tag = inttoptr i64 16 to ptr
  store ptr %us_inner_tag, ptr %us_inner
  %us_row = call ptr @malloc(i64 16)
  %us_row_tag = inttoptr i64 502975519 to ptr
  store ptr %us_row_tag, ptr %us_row
  %us_row_f = getelementptr ptr, ptr %us_row, i32 1
  store ptr %us_inner, ptr %us_row_f
  %us_left = call ptr @malloc(i64 16)
  %us_left_tag = inttoptr i64 3 to ptr
  store ptr %us_left_tag, ptr %us_left
  %us_left_f = getelementptr ptr, ptr %us_left, i32 1
  store ptr %us_row, ptr %us_left_f
  ret ptr %us_left
}


define internal ptr @__getArgs() {
  %arg = load ptr, ptr @.cli_arg
  %either = call ptr @__entryArgEither(ptr %arg)
  ret ptr %either
}


define internal ptr @v_failIO(ptr %v_e) {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 6 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v_e, ptr %t3
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
  switch i64 %t7, label %tco.case.default.8 [ i64 5, label %tco.case.arm.5.9 i64 7, label %tco.case.arm.7.12 i64 8, label %tco.case.arm.8.23 ]
tco.case.arm.5.9:
  %t10 = getelementptr ptr, ptr %t4, i32 1
  %t11 = load ptr, ptr %t10
  store ptr %t11, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.12:
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
tco.case.arm.8.23:
  %t24 = getelementptr ptr, ptr %t4, i32 1
  %t25 = load ptr, ptr %t24
  %t26 = call ptr @__getArgs()
  %t27 = call ptr @v__apply1(ptr %t25, ptr %t26)
  store ptr %t27, ptr %t3
  br label %tco.loop.0
tco.case.default.8:
  unreachable
tco.exit.1:
  %t28 = load ptr, ptr %t2
  ret ptr %t28
}

define internal ptr @v_failingComputation() {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 63694499 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @malloc(i64 8)
  %t4 = inttoptr i64 19 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  %t7 = call ptr @v_failIO(ptr %t0)
  ret ptr %t7
}

define internal ptr @v_handleSomeErrors(ptr %v_e) {
  %t0 = getelementptr ptr, ptr %v_e, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 63694499, label %case.arm.63694499.5 i64 80472118, label %case.arm.80472118.25 ]
case.arm.63694499.5:
  %t7 = getelementptr ptr, ptr %v_e, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr ptr, ptr %t8, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %case.default.12 [ i64 19, label %case.arm.19.14 ]
case.arm.19.14:
  %t16 = call ptr @malloc(i64 16)
  %t17 = inttoptr i64 63694499 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = call ptr @malloc(i64 8)
  %t20 = inttoptr i64 19 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t19, ptr %t22
  %t23 = call ptr @v_failIO(ptr %t16)
  br label %case.end.19.15
case.end.19.15:
  br label %case.join.13
case.default.12:
  unreachable
case.join.13:
  %t24 = phi ptr [%t23, %case.end.19.15]
  br label %case.end.63694499.6
case.end.63694499.6:
  br label %case.join.4
case.arm.80472118.25:
  %t27 = getelementptr ptr, ptr %v_e, i32 1
  %t28 = load ptr, ptr %t27
  %t29 = getelementptr ptr, ptr %t28, i32 0
  %t30 = load ptr, ptr %t29
  %t31 = ptrtoint ptr %t30 to i64
  switch i64 %t31, label %case.default.32 [ i64 20, label %case.arm.20.34 ]
case.arm.20.34:
  %t36 = call ptr @malloc(i64 16)
  %t37 = inttoptr i64 80472118 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = call ptr @malloc(i64 8)
  %t40 = inttoptr i64 20 to ptr
  %t41 = getelementptr ptr, ptr %t39, i32 0
  store ptr %t40, ptr %t41
  %t42 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t39, ptr %t42
  %t43 = call ptr @v_failIO(ptr %t36)
  br label %case.end.20.35
case.end.20.35:
  br label %case.join.33
case.default.32:
  unreachable
case.join.33:
  %t44 = phi ptr [%t43, %case.end.20.35]
  br label %case.end.80472118.26
case.end.80472118.26:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t45 = phi ptr [%t24, %case.end.63694499.6], [%t44, %case.end.80472118.26]
  ret ptr %t45
}

define internal ptr @v_handleRemainingErrors(ptr %v_e) {
  %t0 = getelementptr ptr, ptr %v_e, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 63694499, label %case.arm.63694499.5 i64 80472118, label %case.arm.80472118.29 ]
case.arm.63694499.5:
  %t7 = getelementptr ptr, ptr %v_e, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = getelementptr ptr, ptr %t8, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %case.default.12 [ i64 19, label %case.arm.19.14 ]
case.arm.19.14:
  %t16 = call ptr @malloc(i64 24)
  %t17 = inttoptr i64 7 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = getelementptr ptr, ptr %t16, i32 1
  store ptr @.str.0, ptr %t19
  %t20 = call ptr @malloc(i64 16)
  %t21 = inttoptr i64 5 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = call ptr @malloc(i64 8)
  %t24 = inttoptr i64 0 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  %t26 = getelementptr ptr, ptr %t20, i32 1
  store ptr %t23, ptr %t26
  %t27 = getelementptr ptr, ptr %t16, i32 2
  store ptr %t20, ptr %t27
  br label %case.end.19.15
case.end.19.15:
  br label %case.join.13
case.default.12:
  unreachable
case.join.13:
  %t28 = phi ptr [%t16, %case.end.19.15]
  br label %case.end.63694499.6
case.end.63694499.6:
  br label %case.join.4
case.arm.80472118.29:
  %t31 = getelementptr ptr, ptr %v_e, i32 1
  %t32 = load ptr, ptr %t31
  %t33 = getelementptr ptr, ptr %t32, i32 0
  %t34 = load ptr, ptr %t33
  %t35 = ptrtoint ptr %t34 to i64
  switch i64 %t35, label %case.default.36 [ i64 20, label %case.arm.20.38 ]
case.arm.20.38:
  %t40 = call ptr @malloc(i64 24)
  %t41 = inttoptr i64 7 to ptr
  %t42 = getelementptr ptr, ptr %t40, i32 0
  store ptr %t41, ptr %t42
  %t43 = getelementptr ptr, ptr %t40, i32 1
  store ptr @.str.1, ptr %t43
  %t44 = call ptr @malloc(i64 16)
  %t45 = inttoptr i64 5 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  %t47 = call ptr @malloc(i64 8)
  %t48 = inttoptr i64 0 to ptr
  %t49 = getelementptr ptr, ptr %t47, i32 0
  store ptr %t48, ptr %t49
  %t50 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t47, ptr %t50
  %t51 = getelementptr ptr, ptr %t40, i32 2
  store ptr %t44, ptr %t51
  br label %case.end.20.39
case.end.20.39:
  br label %case.join.37
case.default.36:
  unreachable
case.join.37:
  %t52 = phi ptr [%t40, %case.end.20.39]
  br label %case.end.80472118.30
case.end.80472118.30:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t53 = phi ptr [%t28, %case.end.63694499.6], [%t52, %case.end.80472118.30]
  ret ptr %t53
}

define internal ptr @v_main() {
  %t0 = call ptr @v_failingComputation()
  %t1 = call ptr @v__df_handleErrorIO_2(ptr %t0)
  %t2 = call ptr @v__df_handleErrorIO_0(ptr %t1)
  ret ptr %t2
}

define internal ptr @v__df_handleErrorIO_0(ptr %v_io) {
  %t0 = call ptr @malloc(i64 8)
  %t1 = inttoptr i64 26 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_handleErrorIO_0(ptr %v_io, ptr %t0)
  ret ptr %t3
}

define internal ptr @v__cps__df_handleErrorIO_0(ptr %v_io, ptr %v__k) {
entry:
  %t3 = alloca ptr
  store ptr %v_io, ptr %t3
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.19 i64 7, label %tco.case.arm.7.24 i64 8, label %tco.case.arm.8.34 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  %t14 = call ptr @malloc(i64 16)
  %t15 = inttoptr i64 5 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  %t17 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t13, ptr %t17
  %t18 = call ptr @v__apply__df_handleErrorIO_0(ptr %t6, ptr %t14)
  store ptr %t18, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.19:
  %t20 = getelementptr ptr, ptr %t5, i32 1
  %t21 = load ptr, ptr %t20
  %t22 = call ptr @v_handleRemainingErrors(ptr %t21)
  %t23 = call ptr @v__apply__df_handleErrorIO_0(ptr %t6, ptr %t22)
  store ptr %t23, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.24:
  %t25 = getelementptr ptr, ptr %t5, i32 1
  %t26 = load ptr, ptr %t25
  %t27 = getelementptr ptr, ptr %t5, i32 2
  %t28 = load ptr, ptr %t27
  %t29 = call ptr @malloc(i64 24)
  %t30 = inttoptr i64 27 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = getelementptr ptr, ptr %t29, i32 1
  store ptr %t6, ptr %t32
  %t33 = getelementptr ptr, ptr %t29, i32 2
  store ptr %t26, ptr %t33
  store ptr %t28, ptr %t3
  store ptr %t29, ptr %t4
  br label %tco.loop.0
tco.case.arm.8.34:
  %t35 = getelementptr ptr, ptr %t5, i32 1
  %t36 = load ptr, ptr %t35
  %t37 = call ptr @malloc(i64 16)
  %t38 = inttoptr i64 8 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = call ptr @malloc(i64 16)
  %t41 = inttoptr i64 21 to ptr
  %t42 = getelementptr ptr, ptr %t40, i32 0
  store ptr %t41, ptr %t42
  %t43 = getelementptr ptr, ptr %t40, i32 1
  store ptr %t36, ptr %t43
  %t44 = getelementptr ptr, ptr %t37, i32 1
  store ptr %t40, ptr %t44
  %t45 = call ptr @v__apply__df_handleErrorIO_0(ptr %t6, ptr %t37)
  store ptr %t45, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t46 = load ptr, ptr %t2
  ret ptr %t46
}

define internal ptr @v__apply__df_handleErrorIO_0(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 26, label %tco.case.arm.26.11 i64 27, label %tco.case.arm.27.12 ]
tco.case.arm.26.11:
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.27.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  %t15 = getelementptr ptr, ptr %t5, i32 2
  %t16 = load ptr, ptr %t15
  %t17 = call ptr @malloc(i64 24)
  %t18 = inttoptr i64 7 to ptr
  %t19 = getelementptr ptr, ptr %t17, i32 0
  store ptr %t18, ptr %t19
  %t20 = getelementptr ptr, ptr %t17, i32 1
  store ptr %t16, ptr %t20
  %t21 = getelementptr ptr, ptr %t17, i32 2
  store ptr %t6, ptr %t21
  store ptr %t14, ptr %t3
  store ptr %t17, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t22 = load ptr, ptr %t2
  ret ptr %t22
}

define internal ptr @v__df_handleErrorIO_2(ptr %v_io) {
  %t0 = call ptr @malloc(i64 8)
  %t1 = inttoptr i64 28 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_handleErrorIO_2(ptr %v_io, ptr %t0)
  ret ptr %t3
}

define internal ptr @v__cps__df_handleErrorIO_2(ptr %v_io, ptr %v__k) {
entry:
  %t3 = alloca ptr
  store ptr %v_io, ptr %t3
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.19 i64 7, label %tco.case.arm.7.24 i64 8, label %tco.case.arm.8.34 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  %t14 = call ptr @malloc(i64 16)
  %t15 = inttoptr i64 5 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  %t17 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t13, ptr %t17
  %t18 = call ptr @v__apply__df_handleErrorIO_2(ptr %t6, ptr %t14)
  store ptr %t18, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.19:
  %t20 = getelementptr ptr, ptr %t5, i32 1
  %t21 = load ptr, ptr %t20
  %t22 = call ptr @v_handleSomeErrors(ptr %t21)
  %t23 = call ptr @v__apply__df_handleErrorIO_2(ptr %t6, ptr %t22)
  store ptr %t23, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.24:
  %t25 = getelementptr ptr, ptr %t5, i32 1
  %t26 = load ptr, ptr %t25
  %t27 = getelementptr ptr, ptr %t5, i32 2
  %t28 = load ptr, ptr %t27
  %t29 = call ptr @malloc(i64 24)
  %t30 = inttoptr i64 29 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = getelementptr ptr, ptr %t29, i32 1
  store ptr %t6, ptr %t32
  %t33 = getelementptr ptr, ptr %t29, i32 2
  store ptr %t26, ptr %t33
  store ptr %t28, ptr %t3
  store ptr %t29, ptr %t4
  br label %tco.loop.0
tco.case.arm.8.34:
  %t35 = getelementptr ptr, ptr %t5, i32 1
  %t36 = load ptr, ptr %t35
  %t37 = call ptr @malloc(i64 16)
  %t38 = inttoptr i64 8 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = call ptr @malloc(i64 16)
  %t41 = inttoptr i64 22 to ptr
  %t42 = getelementptr ptr, ptr %t40, i32 0
  store ptr %t41, ptr %t42
  %t43 = getelementptr ptr, ptr %t40, i32 1
  store ptr %t36, ptr %t43
  %t44 = getelementptr ptr, ptr %t37, i32 1
  store ptr %t40, ptr %t44
  %t45 = call ptr @v__apply__df_handleErrorIO_2(ptr %t6, ptr %t37)
  store ptr %t45, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t46 = load ptr, ptr %t2
  ret ptr %t46
}

define internal ptr @v__apply__df_handleErrorIO_2(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 28, label %tco.case.arm.28.11 i64 29, label %tco.case.arm.29.12 ]
tco.case.arm.28.11:
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.29.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  %t15 = getelementptr ptr, ptr %t5, i32 2
  %t16 = load ptr, ptr %t15
  %t17 = call ptr @malloc(i64 24)
  %t18 = inttoptr i64 7 to ptr
  %t19 = getelementptr ptr, ptr %t17, i32 0
  store ptr %t18, ptr %t19
  %t20 = getelementptr ptr, ptr %t17, i32 1
  store ptr %t16, ptr %t20
  %t21 = getelementptr ptr, ptr %t17, i32 2
  store ptr %t6, ptr %t21
  store ptr %t14, ptr %t3
  store ptr %t17, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t22 = load ptr, ptr %t2
  ret ptr %t22
}

define internal ptr @v__scc__apply1__df__lam_6_1__df__lam_6_3(ptr %v__args) {
  %t0 = call ptr @malloc(i64 8)
  %t1 = inttoptr i64 30 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__scc__apply1__df__lam_6_1__df__lam_6_3(ptr %v__args, ptr %t0)
  ret ptr %t3
}

define internal ptr @v__cps__scc__apply1__df__lam_6_1__df__lam_6_3(ptr %v__args, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 23, label %tco.case.arm.23.11 i64 24, label %tco.case.arm.24.36 i64 25, label %tco.case.arm.25.50 ]
tco.case.arm.23.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  %t14 = getelementptr ptr, ptr %t5, i32 2
  %t15 = load ptr, ptr %t14
  %t16 = getelementptr ptr, ptr %t13, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %tco.case.default.19 [ i64 21, label %tco.case.arm.21.20 i64 22, label %tco.case.arm.22.28 ]
tco.case.arm.21.20:
  %t21 = getelementptr ptr, ptr %t13, i32 1
  %t22 = load ptr, ptr %t21
  %t23 = call ptr @malloc(i64 24)
  %t24 = inttoptr i64 24 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  %t26 = getelementptr ptr, ptr %t23, i32 1
  store ptr %t22, ptr %t26
  %t27 = getelementptr ptr, ptr %t23, i32 2
  store ptr %t15, ptr %t27
  store ptr %t23, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.22.28:
  %t29 = getelementptr ptr, ptr %t13, i32 1
  %t30 = load ptr, ptr %t29
  %t31 = call ptr @malloc(i64 24)
  %t32 = inttoptr i64 25 to ptr
  %t33 = getelementptr ptr, ptr %t31, i32 0
  store ptr %t32, ptr %t33
  %t34 = getelementptr ptr, ptr %t31, i32 1
  store ptr %t30, ptr %t34
  %t35 = getelementptr ptr, ptr %t31, i32 2
  store ptr %t15, ptr %t35
  store ptr %t31, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.default.19:
  unreachable
tco.case.arm.24.36:
  %t37 = getelementptr ptr, ptr %t5, i32 1
  %t38 = load ptr, ptr %t37
  %t39 = getelementptr ptr, ptr %t5, i32 2
  %t40 = load ptr, ptr %t39
  %t41 = call ptr @malloc(i64 24)
  %t42 = inttoptr i64 23 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = getelementptr ptr, ptr %t41, i32 1
  store ptr %t38, ptr %t44
  %t45 = getelementptr ptr, ptr %t41, i32 2
  store ptr %t40, ptr %t45
  %t46 = call ptr @malloc(i64 16)
  %t47 = inttoptr i64 31 to ptr
  %t48 = getelementptr ptr, ptr %t46, i32 0
  store ptr %t47, ptr %t48
  %t49 = getelementptr ptr, ptr %t46, i32 1
  store ptr %t6, ptr %t49
  store ptr %t41, ptr %t3
  store ptr %t46, ptr %t4
  br label %tco.loop.0
tco.case.arm.25.50:
  %t51 = getelementptr ptr, ptr %t5, i32 1
  %t52 = load ptr, ptr %t51
  %t53 = getelementptr ptr, ptr %t5, i32 2
  %t54 = load ptr, ptr %t53
  %t55 = call ptr @malloc(i64 24)
  %t56 = inttoptr i64 23 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  %t58 = getelementptr ptr, ptr %t55, i32 1
  store ptr %t52, ptr %t58
  %t59 = getelementptr ptr, ptr %t55, i32 2
  store ptr %t54, ptr %t59
  %t60 = call ptr @malloc(i64 16)
  %t61 = inttoptr i64 32 to ptr
  %t62 = getelementptr ptr, ptr %t60, i32 0
  store ptr %t61, ptr %t62
  %t63 = getelementptr ptr, ptr %t60, i32 1
  store ptr %t6, ptr %t63
  store ptr %t55, ptr %t3
  store ptr %t60, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t64 = load ptr, ptr %t2
  ret ptr %t64
}

define internal ptr @v__apply__scc__apply1__df__lam_6_1__df__lam_6_3(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 30, label %tco.case.arm.30.11 i64 31, label %tco.case.arm.31.12 i64 32, label %tco.case.arm.32.16 ]
tco.case.arm.30.11:
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.31.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  %t15 = call ptr @v__df_handleErrorIO_0(ptr %t6)
  store ptr %t14, ptr %t3
  store ptr %t15, ptr %t4
  br label %tco.loop.0
tco.case.arm.32.16:
  %t17 = getelementptr ptr, ptr %t5, i32 1
  %t18 = load ptr, ptr %t17
  %t19 = call ptr @v__df_handleErrorIO_2(ptr %t6)
  store ptr %t18, ptr %t3
  store ptr %t19, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t20 = load ptr, ptr %t2
  ret ptr %t20
}

define internal ptr @v__apply1(ptr %v__cl, ptr %v__arg0) {
  %t0 = call ptr @malloc(i64 24)
  %t1 = inttoptr i64 23 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v__cl, ptr %t3
  %t4 = getelementptr ptr, ptr %t0, i32 2
  store ptr %v__arg0, ptr %t4
  %t5 = call ptr @v__scc__apply1__df__lam_6_1__df__lam_6_3(ptr %t0)
  ret ptr %t5
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
  store ptr %input, ptr @.cli_arg
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
