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

@.str.0 = private unnamed_addr constant {i32, i32, [13 x i8]} { i32 13, i32 13, [13 x i8] c"OverflowError" }
@.str.1 = private unnamed_addr constant {i32, i32, [10 x i8]} { i32 10, i32 10, [10 x i8] c"overflow: " }
@.str.2 = private unnamed_addr constant {i32, i32, [4 x i8]} { i32 4, i32 4, [4 x i8] c"ok: " }
@.str.3 = private unnamed_addr constant {i32, i32, [2 x i8]} { i32 2, i32 2, [2 x i8] c", " }
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


define internal ptr @__showUInt32(ptr %p) {
  %v = load i32, ptr %p
  %buf = call ptr @malloc(i64 24)
  %payload = getelementptr i8, ptr %buf, i64 8
  %n = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %payload, i64 16, ptr @.fmt_u8, i32 %v)
  store i32 %n, ptr %buf
  %u16p = getelementptr i8, ptr %buf, i64 4
  store i32 %n, ptr %u16p
  ret ptr %buf
}


define internal ptr @__mulUInt32(ptr %pa, ptr %pb) {
  %a = load i32, ptr %pa
  %b = load i32, ptr %pb
  %a64 = zext i32 %a to i64
  %b64 = zext i32 %b to i64
  %prod64 = mul i64 %a64, %b64
  %ovf = icmp ugt i64 %prod64, 4294967295
  br i1 %ovf, label %err, label %ok
err:
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
  %newv = trunc i64 %prod64 to i32
  %box = call ptr @malloc(i64 4)
  store i32 %newv, ptr %box
  %right = call ptr @malloc(i64 16)
  %right_tag = inttoptr i64 1 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %box, ptr %right_f
  ret ptr %right
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

define internal ptr @v_showOverflowError(ptr %v__wild0) {
  ret ptr @.str.0
}

define internal ptr @v_minUInt32() {
  %t0 = call ptr @malloc(i64 4)
  store i32 0, ptr %t0
  ret ptr %t0
}

define internal ptr @v_maxUInt32() {
  %t0 = call ptr @malloc(i64 4)
  store i32 -1, ptr %t0
  ret ptr %t0
}

define internal ptr @v_render(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 0, label %case.arm.0.5 i64 1, label %case.arm.1.11 ]
case.arm.0.5:
  %t7 = getelementptr ptr, ptr %v_r, i32 1
  %t8 = load ptr, ptr %t7
  %t9 = call ptr @v_showOverflowError(ptr %t8)
  %t10 = call ptr @__concat(ptr @.str.1, ptr %t9)
  br label %case.end.0.6
case.end.0.6:
  br label %case.join.4
case.arm.1.11:
  %t13 = getelementptr ptr, ptr %v_r, i32 1
  %t14 = load ptr, ptr %t13
  %t15 = call ptr @__showUInt32(ptr %t14)
  %t16 = call ptr @__concat(ptr @.str.2, ptr %t15)
  br label %case.end.1.12
case.end.1.12:
  br label %case.join.4
case.default.3:
  unreachable
case.join.4:
  %t17 = phi ptr [%t10, %case.end.0.6], [%t16, %case.end.1.12]
  ret ptr %t17
}

define internal ptr @v_main(ptr %v__input) {
  %t0 = call ptr @malloc(i64 4)
  store i32 65535, ptr %t0
  %t1 = call ptr @malloc(i64 4)
  store i32 65537, ptr %t1
  %t2 = call ptr @__mulUInt32(ptr %t0, ptr %t1)
  %t3 = call ptr @v_render(ptr %t2)
  %t4 = getelementptr ptr, ptr %t3, i32 0
  %t5 = load ptr, ptr %t4
  %t6 = ptrtoint ptr %t5 to i64
  switch i64 %t6, label %case.default.7 [ i64 0, label %case.arm.0.9 i64 1, label %case.arm.1.17 ]
case.arm.0.9:
  %t11 = getelementptr ptr, ptr %t3, i32 1
  %t12 = load ptr, ptr %t11
  %t13 = call ptr @malloc(i64 16)
  %t14 = inttoptr i64 0 to ptr
  %t15 = getelementptr ptr, ptr %t13, i32 0
  store ptr %t14, ptr %t15
  %t16 = getelementptr ptr, ptr %t13, i32 1
  store ptr %t12, ptr %t16
  br label %case.end.0.10
case.end.0.10:
  br label %case.join.8
case.arm.1.17:
  %t19 = getelementptr ptr, ptr %t3, i32 1
  %t20 = load ptr, ptr %t19
  %t21 = call ptr @malloc(i64 4)
  store i32 65536, ptr %t21
  %t22 = call ptr @malloc(i64 4)
  store i32 65536, ptr %t22
  %t23 = call ptr @__mulUInt32(ptr %t21, ptr %t22)
  %t24 = call ptr @v_render(ptr %t23)
  %t25 = getelementptr ptr, ptr %t24, i32 0
  %t26 = load ptr, ptr %t25
  %t27 = ptrtoint ptr %t26 to i64
  switch i64 %t27, label %case.default.28 [ i64 0, label %case.arm.0.30 i64 1, label %case.arm.1.38 ]
case.arm.0.30:
  %t32 = getelementptr ptr, ptr %t24, i32 1
  %t33 = load ptr, ptr %t32
  %t34 = call ptr @malloc(i64 16)
  %t35 = inttoptr i64 0 to ptr
  %t36 = getelementptr ptr, ptr %t34, i32 0
  store ptr %t35, ptr %t36
  %t37 = getelementptr ptr, ptr %t34, i32 1
  store ptr %t33, ptr %t37
  br label %case.end.0.31
case.end.0.31:
  br label %case.join.29
case.arm.1.38:
  %t40 = getelementptr ptr, ptr %t24, i32 1
  %t41 = load ptr, ptr %t40
  %t42 = call ptr @v_maxUInt32()
  %t43 = call ptr @v_maxUInt32()
  %t44 = call ptr @__mulUInt32(ptr %t42, ptr %t43)
  %t45 = call ptr @v_render(ptr %t44)
  %t46 = getelementptr ptr, ptr %t45, i32 0
  %t47 = load ptr, ptr %t46
  %t48 = ptrtoint ptr %t47 to i64
  switch i64 %t48, label %case.default.49 [ i64 0, label %case.arm.0.51 i64 1, label %case.arm.1.59 ]
case.arm.0.51:
  %t53 = getelementptr ptr, ptr %t45, i32 1
  %t54 = load ptr, ptr %t53
  %t55 = call ptr @malloc(i64 16)
  %t56 = inttoptr i64 0 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  %t58 = getelementptr ptr, ptr %t55, i32 1
  store ptr %t54, ptr %t58
  br label %case.end.0.52
case.end.0.52:
  br label %case.join.50
case.arm.1.59:
  %t61 = getelementptr ptr, ptr %t45, i32 1
  %t62 = load ptr, ptr %t61
  %t63 = call ptr @v_minUInt32()
  %t64 = call ptr @v_maxUInt32()
  %t65 = call ptr @__mulUInt32(ptr %t63, ptr %t64)
  %t66 = call ptr @v_render(ptr %t65)
  %t67 = getelementptr ptr, ptr %t66, i32 0
  %t68 = load ptr, ptr %t67
  %t69 = ptrtoint ptr %t68 to i64
  switch i64 %t69, label %case.default.70 [ i64 0, label %case.arm.0.72 i64 1, label %case.arm.1.80 ]
case.arm.0.72:
  %t74 = getelementptr ptr, ptr %t66, i32 1
  %t75 = load ptr, ptr %t74
  %t76 = call ptr @malloc(i64 16)
  %t77 = inttoptr i64 0 to ptr
  %t78 = getelementptr ptr, ptr %t76, i32 0
  store ptr %t77, ptr %t78
  %t79 = getelementptr ptr, ptr %t76, i32 1
  store ptr %t75, ptr %t79
  br label %case.end.0.73
case.end.0.73:
  br label %case.join.71
case.arm.1.80:
  %t82 = getelementptr ptr, ptr %t66, i32 1
  %t83 = load ptr, ptr %t82
  %t84 = call ptr @malloc(i64 4)
  store i32 1, ptr %t84
  %t85 = call ptr @malloc(i64 4)
  store i32 -2147483648, ptr %t85
  %t86 = call ptr @__mulUInt32(ptr %t84, ptr %t85)
  %t87 = call ptr @v_render(ptr %t86)
  %t88 = getelementptr ptr, ptr %t87, i32 0
  %t89 = load ptr, ptr %t88
  %t90 = ptrtoint ptr %t89 to i64
  switch i64 %t90, label %case.default.91 [ i64 0, label %case.arm.0.93 i64 1, label %case.arm.1.101 ]
case.arm.0.93:
  %t95 = getelementptr ptr, ptr %t87, i32 1
  %t96 = load ptr, ptr %t95
  %t97 = call ptr @malloc(i64 16)
  %t98 = inttoptr i64 0 to ptr
  %t99 = getelementptr ptr, ptr %t97, i32 0
  store ptr %t98, ptr %t99
  %t100 = getelementptr ptr, ptr %t97, i32 1
  store ptr %t96, ptr %t100
  br label %case.end.0.94
case.end.0.94:
  br label %case.join.92
case.arm.1.101:
  %t103 = getelementptr ptr, ptr %t87, i32 1
  %t104 = load ptr, ptr %t103
  %t105 = call ptr @malloc(i64 4)
  store i32 2, ptr %t105
  %t106 = call ptr @malloc(i64 4)
  store i32 -2147483648, ptr %t106
  %t107 = call ptr @__mulUInt32(ptr %t105, ptr %t106)
  %t108 = call ptr @v_render(ptr %t107)
  %t109 = getelementptr ptr, ptr %t108, i32 0
  %t110 = load ptr, ptr %t109
  %t111 = ptrtoint ptr %t110 to i64
  switch i64 %t111, label %case.default.112 [ i64 0, label %case.arm.0.114 i64 1, label %case.arm.1.122 ]
case.arm.0.114:
  %t116 = getelementptr ptr, ptr %t108, i32 1
  %t117 = load ptr, ptr %t116
  %t118 = call ptr @malloc(i64 16)
  %t119 = inttoptr i64 0 to ptr
  %t120 = getelementptr ptr, ptr %t118, i32 0
  store ptr %t119, ptr %t120
  %t121 = getelementptr ptr, ptr %t118, i32 1
  store ptr %t117, ptr %t121
  br label %case.end.0.115
case.end.0.115:
  br label %case.join.113
case.arm.1.122:
  %t124 = getelementptr ptr, ptr %t108, i32 1
  %t125 = load ptr, ptr %t124
  %t126 = call ptr @__concat(ptr %t20, ptr @.str.3)
  %t127 = getelementptr ptr, ptr %t126, i32 0
  %t128 = load ptr, ptr %t127
  %t129 = ptrtoint ptr %t128 to i64
  switch i64 %t129, label %case.default.130 [ i64 0, label %case.arm.0.132 i64 1, label %case.arm.1.140 ]
case.arm.0.132:
  %t134 = getelementptr ptr, ptr %t126, i32 1
  %t135 = load ptr, ptr %t134
  %t136 = call ptr @malloc(i64 16)
  %t137 = inttoptr i64 0 to ptr
  %t138 = getelementptr ptr, ptr %t136, i32 0
  store ptr %t137, ptr %t138
  %t139 = getelementptr ptr, ptr %t136, i32 1
  store ptr %t135, ptr %t139
  br label %case.end.0.133
case.end.0.133:
  br label %case.join.131
case.arm.1.140:
  %t142 = getelementptr ptr, ptr %t126, i32 1
  %t143 = load ptr, ptr %t142
  %t144 = call ptr @__concat(ptr %t143, ptr %t41)
  %t145 = getelementptr ptr, ptr %t144, i32 0
  %t146 = load ptr, ptr %t145
  %t147 = ptrtoint ptr %t146 to i64
  switch i64 %t147, label %case.default.148 [ i64 0, label %case.arm.0.150 i64 1, label %case.arm.1.158 ]
case.arm.0.150:
  %t152 = getelementptr ptr, ptr %t144, i32 1
  %t153 = load ptr, ptr %t152
  %t154 = call ptr @malloc(i64 16)
  %t155 = inttoptr i64 0 to ptr
  %t156 = getelementptr ptr, ptr %t154, i32 0
  store ptr %t155, ptr %t156
  %t157 = getelementptr ptr, ptr %t154, i32 1
  store ptr %t153, ptr %t157
  br label %case.end.0.151
case.end.0.151:
  br label %case.join.149
case.arm.1.158:
  %t160 = getelementptr ptr, ptr %t144, i32 1
  %t161 = load ptr, ptr %t160
  %t162 = call ptr @__concat(ptr %t161, ptr @.str.3)
  %t163 = getelementptr ptr, ptr %t162, i32 0
  %t164 = load ptr, ptr %t163
  %t165 = ptrtoint ptr %t164 to i64
  switch i64 %t165, label %case.default.166 [ i64 0, label %case.arm.0.168 i64 1, label %case.arm.1.176 ]
case.arm.0.168:
  %t170 = getelementptr ptr, ptr %t162, i32 1
  %t171 = load ptr, ptr %t170
  %t172 = call ptr @malloc(i64 16)
  %t173 = inttoptr i64 0 to ptr
  %t174 = getelementptr ptr, ptr %t172, i32 0
  store ptr %t173, ptr %t174
  %t175 = getelementptr ptr, ptr %t172, i32 1
  store ptr %t171, ptr %t175
  br label %case.end.0.169
case.end.0.169:
  br label %case.join.167
case.arm.1.176:
  %t178 = getelementptr ptr, ptr %t162, i32 1
  %t179 = load ptr, ptr %t178
  %t180 = call ptr @__concat(ptr %t179, ptr %t62)
  %t181 = getelementptr ptr, ptr %t180, i32 0
  %t182 = load ptr, ptr %t181
  %t183 = ptrtoint ptr %t182 to i64
  switch i64 %t183, label %case.default.184 [ i64 0, label %case.arm.0.186 i64 1, label %case.arm.1.194 ]
case.arm.0.186:
  %t188 = getelementptr ptr, ptr %t180, i32 1
  %t189 = load ptr, ptr %t188
  %t190 = call ptr @malloc(i64 16)
  %t191 = inttoptr i64 0 to ptr
  %t192 = getelementptr ptr, ptr %t190, i32 0
  store ptr %t191, ptr %t192
  %t193 = getelementptr ptr, ptr %t190, i32 1
  store ptr %t189, ptr %t193
  br label %case.end.0.187
case.end.0.187:
  br label %case.join.185
case.arm.1.194:
  %t196 = getelementptr ptr, ptr %t180, i32 1
  %t197 = load ptr, ptr %t196
  %t198 = call ptr @__concat(ptr %t197, ptr @.str.3)
  %t199 = getelementptr ptr, ptr %t198, i32 0
  %t200 = load ptr, ptr %t199
  %t201 = ptrtoint ptr %t200 to i64
  switch i64 %t201, label %case.default.202 [ i64 0, label %case.arm.0.204 i64 1, label %case.arm.1.212 ]
case.arm.0.204:
  %t206 = getelementptr ptr, ptr %t198, i32 1
  %t207 = load ptr, ptr %t206
  %t208 = call ptr @malloc(i64 16)
  %t209 = inttoptr i64 0 to ptr
  %t210 = getelementptr ptr, ptr %t208, i32 0
  store ptr %t209, ptr %t210
  %t211 = getelementptr ptr, ptr %t208, i32 1
  store ptr %t207, ptr %t211
  br label %case.end.0.205
case.end.0.205:
  br label %case.join.203
case.arm.1.212:
  %t214 = getelementptr ptr, ptr %t198, i32 1
  %t215 = load ptr, ptr %t214
  %t216 = call ptr @__concat(ptr %t215, ptr %t83)
  %t217 = getelementptr ptr, ptr %t216, i32 0
  %t218 = load ptr, ptr %t217
  %t219 = ptrtoint ptr %t218 to i64
  switch i64 %t219, label %case.default.220 [ i64 0, label %case.arm.0.222 i64 1, label %case.arm.1.230 ]
case.arm.0.222:
  %t224 = getelementptr ptr, ptr %t216, i32 1
  %t225 = load ptr, ptr %t224
  %t226 = call ptr @malloc(i64 16)
  %t227 = inttoptr i64 0 to ptr
  %t228 = getelementptr ptr, ptr %t226, i32 0
  store ptr %t227, ptr %t228
  %t229 = getelementptr ptr, ptr %t226, i32 1
  store ptr %t225, ptr %t229
  br label %case.end.0.223
case.end.0.223:
  br label %case.join.221
case.arm.1.230:
  %t232 = getelementptr ptr, ptr %t216, i32 1
  %t233 = load ptr, ptr %t232
  %t234 = call ptr @__concat(ptr %t233, ptr @.str.3)
  %t235 = getelementptr ptr, ptr %t234, i32 0
  %t236 = load ptr, ptr %t235
  %t237 = ptrtoint ptr %t236 to i64
  switch i64 %t237, label %case.default.238 [ i64 0, label %case.arm.0.240 i64 1, label %case.arm.1.248 ]
case.arm.0.240:
  %t242 = getelementptr ptr, ptr %t234, i32 1
  %t243 = load ptr, ptr %t242
  %t244 = call ptr @malloc(i64 16)
  %t245 = inttoptr i64 0 to ptr
  %t246 = getelementptr ptr, ptr %t244, i32 0
  store ptr %t245, ptr %t246
  %t247 = getelementptr ptr, ptr %t244, i32 1
  store ptr %t243, ptr %t247
  br label %case.end.0.241
case.end.0.241:
  br label %case.join.239
case.arm.1.248:
  %t250 = getelementptr ptr, ptr %t234, i32 1
  %t251 = load ptr, ptr %t250
  %t252 = call ptr @__concat(ptr %t251, ptr %t104)
  %t253 = getelementptr ptr, ptr %t252, i32 0
  %t254 = load ptr, ptr %t253
  %t255 = ptrtoint ptr %t254 to i64
  switch i64 %t255, label %case.default.256 [ i64 0, label %case.arm.0.258 i64 1, label %case.arm.1.266 ]
case.arm.0.258:
  %t260 = getelementptr ptr, ptr %t252, i32 1
  %t261 = load ptr, ptr %t260
  %t262 = call ptr @malloc(i64 16)
  %t263 = inttoptr i64 0 to ptr
  %t264 = getelementptr ptr, ptr %t262, i32 0
  store ptr %t263, ptr %t264
  %t265 = getelementptr ptr, ptr %t262, i32 1
  store ptr %t261, ptr %t265
  br label %case.end.0.259
case.end.0.259:
  br label %case.join.257
case.arm.1.266:
  %t268 = getelementptr ptr, ptr %t252, i32 1
  %t269 = load ptr, ptr %t268
  %t270 = call ptr @__concat(ptr %t269, ptr @.str.3)
  %t271 = getelementptr ptr, ptr %t270, i32 0
  %t272 = load ptr, ptr %t271
  %t273 = ptrtoint ptr %t272 to i64
  switch i64 %t273, label %case.default.274 [ i64 0, label %case.arm.0.276 i64 1, label %case.arm.1.284 ]
case.arm.0.276:
  %t278 = getelementptr ptr, ptr %t270, i32 1
  %t279 = load ptr, ptr %t278
  %t280 = call ptr @malloc(i64 16)
  %t281 = inttoptr i64 0 to ptr
  %t282 = getelementptr ptr, ptr %t280, i32 0
  store ptr %t281, ptr %t282
  %t283 = getelementptr ptr, ptr %t280, i32 1
  store ptr %t279, ptr %t283
  br label %case.end.0.277
case.end.0.277:
  br label %case.join.275
case.arm.1.284:
  %t286 = getelementptr ptr, ptr %t270, i32 1
  %t287 = load ptr, ptr %t286
  %t288 = call ptr @__concat(ptr %t287, ptr %t125)
  br label %case.end.1.285
case.end.1.285:
  br label %case.join.275
case.default.274:
  unreachable
case.join.275:
  %t289 = phi ptr [%t280, %case.end.0.277], [%t288, %case.end.1.285]
  br label %case.end.1.267
case.end.1.267:
  br label %case.join.257
case.default.256:
  unreachable
case.join.257:
  %t290 = phi ptr [%t262, %case.end.0.259], [%t289, %case.end.1.267]
  br label %case.end.1.249
case.end.1.249:
  br label %case.join.239
case.default.238:
  unreachable
case.join.239:
  %t291 = phi ptr [%t244, %case.end.0.241], [%t290, %case.end.1.249]
  br label %case.end.1.231
case.end.1.231:
  br label %case.join.221
case.default.220:
  unreachable
case.join.221:
  %t292 = phi ptr [%t226, %case.end.0.223], [%t291, %case.end.1.231]
  br label %case.end.1.213
case.end.1.213:
  br label %case.join.203
case.default.202:
  unreachable
case.join.203:
  %t293 = phi ptr [%t208, %case.end.0.205], [%t292, %case.end.1.213]
  br label %case.end.1.195
case.end.1.195:
  br label %case.join.185
case.default.184:
  unreachable
case.join.185:
  %t294 = phi ptr [%t190, %case.end.0.187], [%t293, %case.end.1.195]
  br label %case.end.1.177
case.end.1.177:
  br label %case.join.167
case.default.166:
  unreachable
case.join.167:
  %t295 = phi ptr [%t172, %case.end.0.169], [%t294, %case.end.1.177]
  br label %case.end.1.159
case.end.1.159:
  br label %case.join.149
case.default.148:
  unreachable
case.join.149:
  %t296 = phi ptr [%t154, %case.end.0.151], [%t295, %case.end.1.159]
  br label %case.end.1.141
case.end.1.141:
  br label %case.join.131
case.default.130:
  unreachable
case.join.131:
  %t297 = phi ptr [%t136, %case.end.0.133], [%t296, %case.end.1.141]
  br label %case.end.1.123
case.end.1.123:
  br label %case.join.113
case.default.112:
  unreachable
case.join.113:
  %t298 = phi ptr [%t118, %case.end.0.115], [%t297, %case.end.1.123]
  br label %case.end.1.102
case.end.1.102:
  br label %case.join.92
case.default.91:
  unreachable
case.join.92:
  %t299 = phi ptr [%t97, %case.end.0.94], [%t298, %case.end.1.102]
  br label %case.end.1.81
case.end.1.81:
  br label %case.join.71
case.default.70:
  unreachable
case.join.71:
  %t300 = phi ptr [%t76, %case.end.0.73], [%t299, %case.end.1.81]
  br label %case.end.1.60
case.end.1.60:
  br label %case.join.50
case.default.49:
  unreachable
case.join.50:
  %t301 = phi ptr [%t55, %case.end.0.52], [%t300, %case.end.1.60]
  br label %case.end.1.39
case.end.1.39:
  br label %case.join.29
case.default.28:
  unreachable
case.join.29:
  %t302 = phi ptr [%t34, %case.end.0.31], [%t301, %case.end.1.39]
  br label %case.end.1.18
case.end.1.18:
  br label %case.join.8
case.default.7:
  unreachable
case.join.8:
  %t303 = phi ptr [%t13, %case.end.0.10], [%t302, %case.end.1.18]
  %t304 = call ptr @v__let_2(ptr %t303)
  ret ptr %t304
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
  %either = call ptr @__entryArgEither(ptr %input)
  %io = call ptr @v_main(ptr %either)
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
