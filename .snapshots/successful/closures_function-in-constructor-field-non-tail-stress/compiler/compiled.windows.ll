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

@.str.0 = private unnamed_addr constant {i32, i32, [9 x i8]} { i32 9, i32 9, [9 x i8] c"underflow" }

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


define internal ptr @__predInt32(ptr %p) {
  %v = load i32, ptr %p
  %is_min = icmp eq i32 %v, -2147483648
  br i1 %is_min, label %overflow, label %ok
overflow:
  %oe = call ptr @malloc(i64 8)
  %oe_tag = inttoptr i64 0 to ptr
  store ptr %oe_tag, ptr %oe
  %left = call ptr @malloc(i64 16)
  %left_tag = inttoptr i64 0 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %oe, ptr %left_f
  ret ptr %left
ok:
  %newv = sub i32 %v, 1
  %box = call ptr @malloc(i64 4)
  store i32 %newv, ptr %box
  %right = call ptr @malloc(i64 16)
  %right_tag = inttoptr i64 1 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %box, ptr %right_f
  ret ptr %right
}


define internal ptr @__eqInt32(ptr %a, ptr %b) {
  %va = load i32, ptr %a
  %vb = load i32, ptr %b
  %eq = icmp eq i32 %va, %vb
  %tag = select i1 %eq, i64 0, i64 1
  %box = call ptr @malloc(i64 8)
  %tag_ptr = inttoptr i64 %tag to ptr
  store ptr %tag_ptr, ptr %box
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

define internal ptr @v_identity(ptr %v_n) {
  ret ptr %v_n
}

define internal ptr @v_countWithBox(ptr %v_b, ptr %v_n) {
  %t0 = call ptr @malloc(i64 8)
  %t1 = inttoptr i64 0 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps_countWithBox(ptr %v_b, ptr %v_n, ptr %t0)
  ret ptr %t3
}

define internal ptr @v__cps_countWithBox(ptr %v_b, ptr %v_n, ptr %v__k) {
entry:
  %t3 = alloca ptr
  store ptr %v_b, ptr %t3
  %t4 = alloca ptr
  store ptr %v_n, ptr %t4
  %t5 = alloca ptr
  store ptr %v__k, ptr %t5
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t6 = load ptr, ptr %t3
  %t7 = load ptr, ptr %t4
  %t8 = load ptr, ptr %t5
  %t9 = call ptr @malloc(i64 4)
  store i32 0, ptr %t9
  %t10 = call ptr @__eqInt32(ptr %t7, ptr %t9)
  %t11 = getelementptr ptr, ptr %t10, i32 0
  %t12 = load ptr, ptr %t11
  %t13 = ptrtoint ptr %t12 to i64
  switch i64 %t13, label %tco.case.default.14 [ i64 0, label %tco.case.arm.0.15 i64 1, label %tco.case.arm.1.22 ]
tco.case.arm.0.15:
  %t16 = call ptr @malloc(i64 16)
  %t17 = inttoptr i64 1 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = call ptr @malloc(i64 4)
  store i32 0, ptr %t19
  %t20 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t19, ptr %t20
  %t21 = call ptr @v__apply_countWithBox(ptr %t8, ptr %t16)
  store ptr %t21, ptr %t2
  br label %tco.exit.1
tco.case.arm.1.22:
  %t23 = call ptr @__predInt32(ptr %t7)
  %t24 = getelementptr ptr, ptr %t23, i32 0
  %t25 = load ptr, ptr %t24
  %t26 = ptrtoint ptr %t25 to i64
  switch i64 %t26, label %tco.case.default.27 [ i64 0, label %tco.case.arm.0.28 i64 1, label %tco.case.arm.1.36 ]
tco.case.arm.0.28:
  %t29 = getelementptr ptr, ptr %t23, i32 1
  %t30 = load ptr, ptr %t29
  %t31 = call ptr @malloc(i64 16)
  %t32 = inttoptr i64 0 to ptr
  %t33 = getelementptr ptr, ptr %t31, i32 0
  store ptr %t32, ptr %t33
  %t34 = getelementptr ptr, ptr %t31, i32 1
  store ptr %t30, ptr %t34
  %t35 = call ptr @v__apply_countWithBox(ptr %t8, ptr %t31)
  store ptr %t35, ptr %t2
  br label %tco.exit.1
tco.case.arm.1.36:
  %t37 = getelementptr ptr, ptr %t23, i32 1
  %t38 = load ptr, ptr %t37
  %t39 = call ptr @malloc(i64 24)
  %t40 = inttoptr i64 1 to ptr
  %t41 = getelementptr ptr, ptr %t39, i32 0
  store ptr %t40, ptr %t41
  %t42 = getelementptr ptr, ptr %t39, i32 1
  store ptr %t8, ptr %t42
  %t43 = getelementptr ptr, ptr %t39, i32 2
  store ptr %t6, ptr %t43
  store ptr %t6, ptr %t3
  store ptr %t38, ptr %t4
  store ptr %t39, ptr %t5
  br label %tco.loop.0
tco.case.default.27:
  unreachable
tco.case.default.14:
  unreachable
tco.exit.1:
  %t44 = load ptr, ptr %t2
  ret ptr %t44
}

define internal ptr @v__apply_countWithBox(ptr %v__k, ptr %v__x) {
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
  %t17 = getelementptr ptr, ptr %t6, i32 0
  %t18 = load ptr, ptr %t17
  %t19 = ptrtoint ptr %t18 to i64
  switch i64 %t19, label %tco.case.default.20 [ i64 0, label %tco.case.arm.0.21 i64 1, label %tco.case.arm.1.28 ]
tco.case.arm.0.21:
  %t22 = getelementptr ptr, ptr %t6, i32 1
  %t23 = load ptr, ptr %t22
  %t24 = call ptr @malloc(i64 16)
  %t25 = inttoptr i64 0 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = getelementptr ptr, ptr %t24, i32 1
  store ptr %t23, ptr %t27
  store ptr %t14, ptr %t3
  store ptr %t24, ptr %t4
  br label %tco.loop.0
tco.case.arm.1.28:
  %t29 = getelementptr ptr, ptr %t6, i32 1
  %t30 = load ptr, ptr %t29
  %t31 = getelementptr ptr, ptr %t16, i32 0
  %t32 = load ptr, ptr %t31
  %t33 = ptrtoint ptr %t32 to i64
  switch i64 %t33, label %tco.case.default.34 [ i64 0, label %tco.case.arm.0.35 ]
tco.case.arm.0.35:
  %t36 = getelementptr ptr, ptr %t16, i32 1
  %t37 = load ptr, ptr %t36
  %t38 = call ptr @malloc(i64 16)
  %t39 = inttoptr i64 1 to ptr
  %t40 = getelementptr ptr, ptr %t38, i32 0
  store ptr %t39, ptr %t40
  %t41 = call ptr @v__apply1(ptr %t37, ptr %t30)
  %t42 = getelementptr ptr, ptr %t38, i32 1
  store ptr %t41, ptr %t42
  store ptr %t14, ptr %t3
  store ptr %t38, ptr %t4
  br label %tco.loop.0
tco.case.default.34:
  unreachable
tco.case.default.20:
  unreachable
tco.case.default.10:
  unreachable
tco.exit.1:
  %t43 = load ptr, ptr %t2
  ret ptr %t43
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 0 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @malloc(i64 8)
  %t4 = inttoptr i64 0 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  %t7 = call ptr @malloc(i64 4)
  store i32 1000000, ptr %t7
  %t8 = call ptr @v_countWithBox(ptr %t0, ptr %t7)
  %t9 = getelementptr ptr, ptr %t8, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %case.default.12 [ i64 0, label %case.arm.0.14 i64 1, label %case.arm.1.30 ]
case.arm.0.14:
  %t16 = getelementptr ptr, ptr %t8, i32 1
  %t17 = load ptr, ptr %t16
  %t18 = call ptr @malloc(i64 24)
  %t19 = inttoptr i64 2 to ptr
  %t20 = getelementptr ptr, ptr %t18, i32 0
  store ptr %t19, ptr %t20
  %t21 = getelementptr ptr, ptr %t18, i32 1
  store ptr @.str.0, ptr %t21
  %t22 = call ptr @malloc(i64 16)
  %t23 = inttoptr i64 0 to ptr
  %t24 = getelementptr ptr, ptr %t22, i32 0
  store ptr %t23, ptr %t24
  %t25 = call ptr @malloc(i64 8)
  %t26 = inttoptr i64 0 to ptr
  %t27 = getelementptr ptr, ptr %t25, i32 0
  store ptr %t26, ptr %t27
  %t28 = getelementptr ptr, ptr %t22, i32 1
  store ptr %t25, ptr %t28
  %t29 = getelementptr ptr, ptr %t18, i32 2
  store ptr %t22, ptr %t29
  br label %case.end.0.15
case.end.0.15:
  br label %case.join.13
case.arm.1.30:
  %t32 = getelementptr ptr, ptr %t8, i32 1
  %t33 = load ptr, ptr %t32
  %t34 = call ptr @malloc(i64 24)
  %t35 = inttoptr i64 2 to ptr
  %t36 = getelementptr ptr, ptr %t34, i32 0
  store ptr %t35, ptr %t36
  %t37 = call ptr @__showInt32(ptr %t33)
  %t38 = getelementptr ptr, ptr %t34, i32 1
  store ptr %t37, ptr %t38
  %t39 = call ptr @malloc(i64 16)
  %t40 = inttoptr i64 0 to ptr
  %t41 = getelementptr ptr, ptr %t39, i32 0
  store ptr %t40, ptr %t41
  %t42 = call ptr @malloc(i64 8)
  %t43 = inttoptr i64 0 to ptr
  %t44 = getelementptr ptr, ptr %t42, i32 0
  store ptr %t43, ptr %t44
  %t45 = getelementptr ptr, ptr %t39, i32 1
  store ptr %t42, ptr %t45
  %t46 = getelementptr ptr, ptr %t34, i32 2
  store ptr %t39, ptr %t46
  br label %case.end.1.31
case.end.1.31:
  br label %case.join.13
case.default.12:
  unreachable
case.join.13:
  %t47 = phi ptr [%t18, %case.end.0.15], [%t34, %case.end.1.31]
  ret ptr %t47
}

define internal ptr @v__apply1(ptr %v__cl, ptr %v__arg0) {
  %t0 = getelementptr ptr, ptr %v__cl, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 ]
case.arm.0.5:
  %t7 = call ptr @v_identity(ptr %v__arg0)
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t8 = phi ptr [%t7, %case.end.0.6]
  ret ptr %t8
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
