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

define internal ptr @v_bBox() {
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
  ret ptr %t0
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 4)
  store i32 1000000, ptr %t0
  %t1 = call ptr @v_a(ptr %t0)
  %t2 = getelementptr ptr, ptr %t1, i32 0
  %t3 = load ptr, ptr %t2
  %t4 = ptrtoint ptr %t3 to i64
  switch i64 %t4, label %case.default.5 [ i64 0, label %case.arm.0.7 i64 1, label %case.arm.1.23 ]
case.arm.0.7:
  %t9 = getelementptr ptr, ptr %t1, i32 1
  %t10 = load ptr, ptr %t9
  %t11 = call ptr @malloc(i64 24)
  %t12 = inttoptr i64 2 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  %t14 = getelementptr ptr, ptr %t11, i32 1
  store ptr @.str.0, ptr %t14
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
  %t22 = getelementptr ptr, ptr %t11, i32 2
  store ptr %t15, ptr %t22
  br label %case.end.0.8
case.end.0.8:
  br label %case.join.6
case.arm.1.23:
  %t25 = getelementptr ptr, ptr %t1, i32 1
  %t26 = load ptr, ptr %t25
  %t27 = call ptr @malloc(i64 24)
  %t28 = inttoptr i64 2 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  %t30 = call ptr @__showInt32(ptr %t26)
  %t31 = getelementptr ptr, ptr %t27, i32 1
  store ptr %t30, ptr %t31
  %t32 = call ptr @malloc(i64 16)
  %t33 = inttoptr i64 0 to ptr
  %t34 = getelementptr ptr, ptr %t32, i32 0
  store ptr %t33, ptr %t34
  %t35 = call ptr @malloc(i64 8)
  %t36 = inttoptr i64 0 to ptr
  %t37 = getelementptr ptr, ptr %t35, i32 0
  store ptr %t36, ptr %t37
  %t38 = getelementptr ptr, ptr %t32, i32 1
  store ptr %t35, ptr %t38
  %t39 = getelementptr ptr, ptr %t27, i32 2
  store ptr %t32, ptr %t39
  br label %case.end.1.24
case.end.1.24:
  br label %case.join.6
case.default.5:
  unreachable
case.join.6:
  %t40 = phi ptr [%t11, %case.end.0.8], [%t27, %case.end.1.24]
  ret ptr %t40
}

define internal ptr @v__scc__apply1__lam_2_a_b(ptr %v__args) {
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
  switch i64 %t7, label %tco.case.default.8 [ i64 0, label %tco.case.arm.0.9 i64 1, label %tco.case.arm.1.23 i64 2, label %tco.case.arm.2.30 i64 3, label %tco.case.arm.3.74 ]
tco.case.arm.0.9:
  %t10 = getelementptr ptr, ptr %t4, i32 1
  %t11 = load ptr, ptr %t10
  %t12 = getelementptr ptr, ptr %t4, i32 2
  %t13 = load ptr, ptr %t12
  %t14 = getelementptr ptr, ptr %t11, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %tco.case.default.17 [ i64 0, label %tco.case.arm.0.18 ]
tco.case.arm.0.18:
  %t19 = call ptr @malloc(i64 16)
  %t20 = inttoptr i64 1 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr ptr, ptr %t19, i32 1
  store ptr %t13, ptr %t22
  store ptr %t19, ptr %t3
  br label %tco.loop.0
tco.case.default.17:
  unreachable
tco.case.arm.1.23:
  %t24 = getelementptr ptr, ptr %t4, i32 1
  %t25 = load ptr, ptr %t24
  %t26 = call ptr @malloc(i64 16)
  %t27 = inttoptr i64 3 to ptr
  %t28 = getelementptr ptr, ptr %t26, i32 0
  store ptr %t27, ptr %t28
  %t29 = getelementptr ptr, ptr %t26, i32 1
  store ptr %t25, ptr %t29
  store ptr %t26, ptr %t3
  br label %tco.loop.0
tco.case.arm.2.30:
  %t31 = getelementptr ptr, ptr %t4, i32 1
  %t32 = load ptr, ptr %t31
  %t33 = call ptr @malloc(i64 4)
  store i32 0, ptr %t33
  %t34 = call ptr @__eqInt32(ptr %t32, ptr %t33)
  %t35 = getelementptr ptr, ptr %t34, i32 0
  %t36 = load ptr, ptr %t35
  %t37 = ptrtoint ptr %t36 to i64
  switch i64 %t37, label %tco.case.default.38 [ i64 0, label %tco.case.arm.0.39 i64 1, label %tco.case.arm.1.45 ]
tco.case.arm.0.39:
  %t40 = call ptr @malloc(i64 16)
  %t41 = inttoptr i64 1 to ptr
  %t42 = getelementptr ptr, ptr %t40, i32 0
  store ptr %t41, ptr %t42
  %t43 = call ptr @malloc(i64 4)
  store i32 0, ptr %t43
  %t44 = getelementptr ptr, ptr %t40, i32 1
  store ptr %t43, ptr %t44
  store ptr %t40, ptr %t2
  br label %tco.exit.1
tco.case.arm.1.45:
  %t46 = call ptr @__predInt32(ptr %t32)
  %t47 = getelementptr ptr, ptr %t46, i32 0
  %t48 = load ptr, ptr %t47
  %t49 = ptrtoint ptr %t48 to i64
  switch i64 %t49, label %tco.case.default.50 [ i64 0, label %tco.case.arm.0.51 i64 1, label %tco.case.arm.1.58 ]
tco.case.arm.0.51:
  %t52 = getelementptr ptr, ptr %t46, i32 1
  %t53 = load ptr, ptr %t52
  %t54 = call ptr @malloc(i64 16)
  %t55 = inttoptr i64 0 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t53, ptr %t57
  store ptr %t54, ptr %t2
  br label %tco.exit.1
tco.case.arm.1.58:
  %t59 = getelementptr ptr, ptr %t46, i32 1
  %t60 = load ptr, ptr %t59
  %t61 = call ptr @v_bBox()
  %t62 = getelementptr ptr, ptr %t61, i32 0
  %t63 = load ptr, ptr %t62
  %t64 = ptrtoint ptr %t63 to i64
  switch i64 %t64, label %tco.case.default.65 [ i64 0, label %tco.case.arm.0.66 ]
tco.case.arm.0.66:
  %t67 = getelementptr ptr, ptr %t61, i32 1
  %t68 = load ptr, ptr %t67
  %t69 = call ptr @malloc(i64 24)
  %t70 = inttoptr i64 0 to ptr
  %t71 = getelementptr ptr, ptr %t69, i32 0
  store ptr %t70, ptr %t71
  %t72 = getelementptr ptr, ptr %t69, i32 1
  store ptr %t68, ptr %t72
  %t73 = getelementptr ptr, ptr %t69, i32 2
  store ptr %t60, ptr %t73
  store ptr %t69, ptr %t3
  br label %tco.loop.0
tco.case.default.65:
  unreachable
tco.case.default.50:
  unreachable
tco.case.default.38:
  unreachable
tco.case.arm.3.74:
  %t75 = getelementptr ptr, ptr %t4, i32 1
  %t76 = load ptr, ptr %t75
  %t77 = call ptr @malloc(i64 4)
  store i32 0, ptr %t77
  %t78 = call ptr @__eqInt32(ptr %t76, ptr %t77)
  %t79 = getelementptr ptr, ptr %t78, i32 0
  %t80 = load ptr, ptr %t79
  %t81 = ptrtoint ptr %t80 to i64
  switch i64 %t81, label %tco.case.default.82 [ i64 0, label %tco.case.arm.0.83 i64 1, label %tco.case.arm.1.89 ]
tco.case.arm.0.83:
  %t84 = call ptr @malloc(i64 16)
  %t85 = inttoptr i64 1 to ptr
  %t86 = getelementptr ptr, ptr %t84, i32 0
  store ptr %t85, ptr %t86
  %t87 = call ptr @malloc(i64 4)
  store i32 0, ptr %t87
  %t88 = getelementptr ptr, ptr %t84, i32 1
  store ptr %t87, ptr %t88
  store ptr %t84, ptr %t2
  br label %tco.exit.1
tco.case.arm.1.89:
  %t90 = call ptr @__predInt32(ptr %t76)
  %t91 = getelementptr ptr, ptr %t90, i32 0
  %t92 = load ptr, ptr %t91
  %t93 = ptrtoint ptr %t92 to i64
  switch i64 %t93, label %tco.case.default.94 [ i64 0, label %tco.case.arm.0.95 i64 1, label %tco.case.arm.1.102 ]
tco.case.arm.0.95:
  %t96 = getelementptr ptr, ptr %t90, i32 1
  %t97 = load ptr, ptr %t96
  %t98 = call ptr @malloc(i64 16)
  %t99 = inttoptr i64 0 to ptr
  %t100 = getelementptr ptr, ptr %t98, i32 0
  store ptr %t99, ptr %t100
  %t101 = getelementptr ptr, ptr %t98, i32 1
  store ptr %t97, ptr %t101
  store ptr %t98, ptr %t2
  br label %tco.exit.1
tco.case.arm.1.102:
  %t103 = getelementptr ptr, ptr %t90, i32 1
  %t104 = load ptr, ptr %t103
  %t105 = call ptr @malloc(i64 16)
  %t106 = inttoptr i64 2 to ptr
  %t107 = getelementptr ptr, ptr %t105, i32 0
  store ptr %t106, ptr %t107
  %t108 = getelementptr ptr, ptr %t105, i32 1
  store ptr %t104, ptr %t108
  store ptr %t105, ptr %t3
  br label %tco.loop.0
tco.case.default.94:
  unreachable
tco.case.default.82:
  unreachable
tco.case.default.8:
  unreachable
tco.exit.1:
  %t109 = load ptr, ptr %t2
  ret ptr %t109
}

define internal ptr @v_a(ptr %v_n) {
  %t0 = call ptr @malloc(i64 16)
  %t1 = inttoptr i64 2 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v_n, ptr %t3
  %t4 = call ptr @v__scc__apply1__lam_2_a_b(ptr %t0)
  ret ptr %t4
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
