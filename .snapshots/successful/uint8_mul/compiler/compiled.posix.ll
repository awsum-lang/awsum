; External C declarations
declare ptr @malloc(i64)
declare void @free(ptr)
declare ptr @memcpy(ptr, ptr, i64)
declare i64 @strlen(ptr)
declare i64 @write(i32, ptr, i64)
declare i32 @printf(ptr, ...)
declare i32 @snprintf(ptr, i64, ptr, ...)

@.fmt_i32 = private unnamed_addr constant [3 x i8] c"%d\00"
@.fmt_u8 = private unnamed_addr constant [3 x i8] c"%u\00"
@.empty = private unnamed_addr constant {i32, i32, i32, i32, i32} { i32 0, i32 0, i32 0, i32 0, i32 0 }
@.cli_arg = internal global ptr null

define internal ptr @__alloc(i64 %sz, i32 %shape) {
  %total = add i64 %sz, 12
  %raw = call ptr @malloc(i64 %total)
  store i32 1, ptr %raw
  %rc_p = getelementptr i8, ptr %raw, i64 4
  store i32 1, ptr %rc_p
  %shape_p = getelementptr i8, ptr %raw, i64 8
  store i32 %shape, ptr %shape_p
  %user = getelementptr i8, ptr %raw, i64 12
  ret ptr %user
}

define internal void @__free(ptr %p) {
  %hdr_ptr = getelementptr i8, ptr %p, i64 -12
  %flag = load i32, ptr %hdr_ptr
  %is_heap = icmp eq i32 %flag, 1
  br i1 %is_heap, label %do_free, label %skip
do_free:
  call void @free(ptr %hdr_ptr)
  br label %skip
skip:
  ret void
}

define internal void @__inc_ref(ptr %p) {
  %hdr_ptr = getelementptr i8, ptr %p, i64 -12
  %flag = load i32, ptr %hdr_ptr
  %is_heap = icmp eq i32 %flag, 1
  br i1 %is_heap, label %do_inc, label %skip_inc
do_inc:
  %rc_p = getelementptr i8, ptr %p, i64 -8
  %rc_old = load i32, ptr %rc_p
  %rc_new = add i32 %rc_old, 1
  store i32 %rc_new, ptr %rc_p
  br label %skip_inc
skip_inc:
  ret void
}

define internal void @__free_recursive(ptr %p_arg) {
entry:
  br label %top
top:
  %p = phi ptr [ %p_arg, %entry ], [ %p_next, %tail_jump ]
  %hdr_ptr = getelementptr i8, ptr %p, i64 -12
  %flag = load i32, ptr %hdr_ptr
  %is_heap = icmp eq i32 %flag, 1
  br i1 %is_heap, label %do_dec, label %skip_dec
do_dec:
  %rc_p = getelementptr i8, ptr %p, i64 -8
  %rc_old = load i32, ptr %rc_p
  %rc_new = sub i32 %rc_old, 1
  store i32 %rc_new, ptr %rc_p
  %is_zero = icmp eq i32 %rc_new, 0
  br i1 %is_zero, label %do_cascade, label %skip_dec
do_cascade:
  %shape_p = getelementptr i8, ptr %p, i64 -4
  %shape = load i32, ptr %shape_p
  %shape_zero = icmp eq i32 %shape, 0
  br i1 %shape_zero, label %loop_done, label %loop_check
loop_check:
  %i = phi i32 [ 1, %do_cascade ], [ %i_next, %loop_body ]
  %cmp = icmp ult i32 %i, %shape
  br i1 %cmp, label %loop_body, label %tail_jump_prep
loop_body:
  %i64 = zext i32 %i to i64
  %slot_p = getelementptr ptr, ptr %p, i64 %i64
  %child = load ptr, ptr %slot_p
  call void @__free_recursive(ptr %child)
  %i_next = add i32 %i, 1
  br label %loop_check
tail_jump_prep:
  %shape64 = zext i32 %shape to i64
  %last_slot_p = getelementptr ptr, ptr %p, i64 %shape64
  %p_next = load ptr, ptr %last_slot_p
  call void @free(ptr %hdr_ptr)
  br label %tail_jump
tail_jump:
  br label %top
loop_done:
  call void @free(ptr %hdr_ptr)
  br label %skip_dec
skip_dec:
  ret void
}

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [13 x i8]} { i32 0, i32 0, i32 0, i32 13, i32 13, [13 x i8] c"OverflowError" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [10 x i8]} { i32 0, i32 0, i32 0, i32 10, i32 10, [10 x i8] c"overflow: " }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"ok: " }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c", " }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }

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
  %stl = call ptr @__alloc(i64 8, i32 0)
  %stl_tag = inttoptr i64 15 to ptr
  store ptr %stl_tag, ptr %stl
  %left = call ptr @__alloc(i64 16, i32 1)
  %left_tag = inttoptr i64 3 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %stl, ptr %left_f
  br label %join
ok:
  %ba64 = zext i32 %ba to i64
  %bb64 = zext i32 %bb to i64
  %bsum64 = add i64 %ba64, %bb64
  %alloc64 = add i64 %bsum64, 8
  %buf = call ptr @__alloc(i64 %alloc64, i32 0)
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
  %right = call ptr @__alloc(i64 16, i32 1)
  %right_tag = inttoptr i64 4 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %buf, ptr %right_f
  br label %join
join:
  %result = phi ptr [%left, %too_long], [%right, %ok]
  call void @__free_recursive(ptr %a)
  call void @__free_recursive(ptr %b)
  ret ptr %result
}


define internal ptr @__print(ptr %s) {
  %byte_count = load i32, ptr %s
  %byte_count_64 = zext i32 %byte_count to i64
  %payload = getelementptr i8, ptr %s, i64 8
  call i64 @write(i32 1, ptr %payload, i64 %byte_count_64)
  %unit = call ptr @__alloc(i64 8, i32 0)
  %unit_tag_ptr = getelementptr ptr, ptr %unit, i32 0
  %unit_tag = inttoptr i64 0 to ptr
  store ptr %unit_tag, ptr %unit_tag_ptr
  call void @__free_recursive(ptr %s)
  ret ptr %unit
}


define internal ptr @__showUInt8(ptr %p) {
  %b = load i8, ptr %p
  %v = zext i8 %b to i32
  %buf = call ptr @__alloc(i64 24, i32 0)
  %payload = getelementptr i8, ptr %buf, i64 8
  %n = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %payload, i64 16, ptr @.fmt_u8, i32 %v)
  store i32 %n, ptr %buf
  %u16p = getelementptr i8, ptr %buf, i64 4
  store i32 %n, ptr %u16p
  call void @__free_recursive(ptr %p)
  ret ptr %buf
}


define internal ptr @__mulUInt8(ptr %pa, ptr %pb) {
  %a = load i8, ptr %pa
  %b = load i8, ptr %pb
  %a32 = zext i8 %a to i32
  %b32 = zext i8 %b to i32
  %prod32 = mul i32 %a32, %b32
  %ovf = icmp ugt i32 %prod32, 255
  br i1 %ovf, label %err, label %ok
err:
  %oe = call ptr @__alloc(i64 8, i32 0)
  %oe_tag = inttoptr i64 14 to ptr
  store ptr %oe_tag, ptr %oe
  %left = call ptr @__alloc(i64 16, i32 1)
  %left_tag = inttoptr i64 3 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %oe, ptr %left_f
  br label %join
ok:
  %newv = trunc i32 %prod32 to i8
  %box = call ptr @__alloc(i64 1, i32 0)
  store i8 %newv, ptr %box
  %right = call ptr @__alloc(i64 16, i32 1)
  %right_tag = inttoptr i64 4 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %box, ptr %right_f
  br label %join
join:
  %result = phi ptr [%left, %err], [%right, %ok]
  call void @__free_recursive(ptr %pa)
  call void @__free_recursive(ptr %pb)
  ret ptr %result
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
  switch i64 %t7, label %tco.case.default.8 [ i64 5, label %tco.case.arm.5.9 i64 7, label %tco.case.arm.7.12 ]
tco.case.arm.5.9:
  %t10 = getelementptr ptr, ptr %t4, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  call void @__free_recursive(ptr %t4)
  store ptr %t11, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.12:
  %t13 = getelementptr ptr, ptr %t4, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  %t15 = getelementptr ptr, ptr %t4, i32 2
  %t16 = load ptr, ptr %t15
  call void @__inc_ref(ptr %t16)
  call void @__inc_ref(ptr %t14)
  %t17 = call ptr @__print(ptr %t14)
  %t18 = getelementptr ptr, ptr %t17, i32 0
  %t19 = load ptr, ptr %t18
  %t20 = ptrtoint ptr %t19 to i64
  switch i64 %t20, label %tco.case.default.21 [ i64 0, label %tco.case.arm.0.22 ]
tco.case.arm.0.22:
  call void @__inc_ref(ptr %t16)
  call void @__free_recursive(ptr %t17)
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t16)
  call void @__free_recursive(ptr %t14)
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
  call void @__free_recursive(ptr %v__wild0)
  ret ptr getelementptr inbounds (i8, ptr @.str.0, i64 12)
}

define internal ptr @v_minUInt8() {
  %t0 = call ptr @__alloc(i64 1, i32 0)
  store i8 0, ptr %t0
  ret ptr %t0
}

define internal ptr @v_maxUInt8() {
  %t0 = call ptr @__alloc(i64 1, i32 0)
  store i8 255, ptr %t0
  ret ptr %t0
}

define internal ptr @v_render(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.9 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v_r, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t6)
  %t7 = call ptr @v_showOverflowError(ptr %t6)
  %t8 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t7)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_r)
  ret ptr %t8
case.arm.4.9:
  %t10 = getelementptr ptr, ptr %v_r, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  call void @__inc_ref(ptr %t11)
  %t12 = call ptr @__showUInt8(ptr %t11)
  %t13 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t12)
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %v_r)
  ret ptr %t13
case.default.3:
  unreachable
}

define internal ptr @v_main() {
  %t0 = call ptr @__alloc(i64 1, i32 0)
  store i8 15, ptr %t0
  %t1 = call ptr @__alloc(i64 1, i32 0)
  store i8 17, ptr %t1
  %t2 = call ptr @__mulUInt8(ptr %t0, ptr %t1)
  %t3 = call ptr @v_render(ptr %t2)
  %t4 = getelementptr ptr, ptr %t3, i32 0
  %t5 = load ptr, ptr %t4
  %t6 = ptrtoint ptr %t5 to i64
  switch i64 %t6, label %case.default.7 [ i64 3, label %case.arm.3.9 i64 4, label %case.arm.4.17 ]
case.arm.3.9:
  %t11 = getelementptr ptr, ptr %t3, i32 1
  %t12 = load ptr, ptr %t11
  call void @__inc_ref(ptr %t12)
  %t13 = call ptr @__alloc(i64 16, i32 1)
  %t14 = inttoptr i64 3 to ptr
  %t15 = getelementptr ptr, ptr %t13, i32 0
  store ptr %t14, ptr %t15
  call void @__inc_ref(ptr %t12)
  %t16 = getelementptr ptr, ptr %t13, i32 1
  store ptr %t12, ptr %t16
  br label %case.end.3.10
case.end.3.10:
  br label %case.join.8
case.arm.4.17:
  %t19 = getelementptr ptr, ptr %t3, i32 1
  %t20 = load ptr, ptr %t19
  call void @__inc_ref(ptr %t20)
  %t21 = call ptr @__alloc(i64 1, i32 0)
  store i8 16, ptr %t21
  %t22 = call ptr @__alloc(i64 1, i32 0)
  store i8 16, ptr %t22
  %t23 = call ptr @__mulUInt8(ptr %t21, ptr %t22)
  %t24 = call ptr @v_render(ptr %t23)
  %t25 = getelementptr ptr, ptr %t24, i32 0
  %t26 = load ptr, ptr %t25
  %t27 = ptrtoint ptr %t26 to i64
  switch i64 %t27, label %case.default.28 [ i64 3, label %case.arm.3.30 i64 4, label %case.arm.4.38 ]
case.arm.3.30:
  %t32 = getelementptr ptr, ptr %t24, i32 1
  %t33 = load ptr, ptr %t32
  call void @__inc_ref(ptr %t33)
  %t34 = call ptr @__alloc(i64 16, i32 1)
  %t35 = inttoptr i64 3 to ptr
  %t36 = getelementptr ptr, ptr %t34, i32 0
  store ptr %t35, ptr %t36
  call void @__inc_ref(ptr %t33)
  %t37 = getelementptr ptr, ptr %t34, i32 1
  store ptr %t33, ptr %t37
  br label %case.end.3.31
case.end.3.31:
  br label %case.join.29
case.arm.4.38:
  %t40 = getelementptr ptr, ptr %t24, i32 1
  %t41 = load ptr, ptr %t40
  call void @__inc_ref(ptr %t41)
  %t42 = call ptr @v_maxUInt8()
  call void @__inc_ref(ptr %t42)
  %t43 = call ptr @v_maxUInt8()
  call void @__inc_ref(ptr %t43)
  %t44 = call ptr @__mulUInt8(ptr %t42, ptr %t43)
  %t45 = call ptr @v_render(ptr %t44)
  %t46 = getelementptr ptr, ptr %t45, i32 0
  %t47 = load ptr, ptr %t46
  %t48 = ptrtoint ptr %t47 to i64
  switch i64 %t48, label %case.default.49 [ i64 3, label %case.arm.3.51 i64 4, label %case.arm.4.59 ]
case.arm.3.51:
  %t53 = getelementptr ptr, ptr %t45, i32 1
  %t54 = load ptr, ptr %t53
  call void @__inc_ref(ptr %t54)
  %t55 = call ptr @__alloc(i64 16, i32 1)
  %t56 = inttoptr i64 3 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  call void @__inc_ref(ptr %t54)
  %t58 = getelementptr ptr, ptr %t55, i32 1
  store ptr %t54, ptr %t58
  br label %case.end.3.52
case.end.3.52:
  br label %case.join.50
case.arm.4.59:
  %t61 = getelementptr ptr, ptr %t45, i32 1
  %t62 = load ptr, ptr %t61
  call void @__inc_ref(ptr %t62)
  %t63 = call ptr @v_minUInt8()
  call void @__inc_ref(ptr %t63)
  %t64 = call ptr @__alloc(i64 1, i32 0)
  store i8 200, ptr %t64
  %t65 = call ptr @__mulUInt8(ptr %t63, ptr %t64)
  %t66 = call ptr @v_render(ptr %t65)
  %t67 = getelementptr ptr, ptr %t66, i32 0
  %t68 = load ptr, ptr %t67
  %t69 = ptrtoint ptr %t68 to i64
  switch i64 %t69, label %case.default.70 [ i64 3, label %case.arm.3.72 i64 4, label %case.arm.4.80 ]
case.arm.3.72:
  %t74 = getelementptr ptr, ptr %t66, i32 1
  %t75 = load ptr, ptr %t74
  call void @__inc_ref(ptr %t75)
  %t76 = call ptr @__alloc(i64 16, i32 1)
  %t77 = inttoptr i64 3 to ptr
  %t78 = getelementptr ptr, ptr %t76, i32 0
  store ptr %t77, ptr %t78
  call void @__inc_ref(ptr %t75)
  %t79 = getelementptr ptr, ptr %t76, i32 1
  store ptr %t75, ptr %t79
  br label %case.end.3.73
case.end.3.73:
  br label %case.join.71
case.arm.4.80:
  %t82 = getelementptr ptr, ptr %t66, i32 1
  %t83 = load ptr, ptr %t82
  call void @__inc_ref(ptr %t83)
  %t84 = call ptr @__alloc(i64 1, i32 0)
  store i8 1, ptr %t84
  %t85 = call ptr @__alloc(i64 1, i32 0)
  store i8 200, ptr %t85
  %t86 = call ptr @__mulUInt8(ptr %t84, ptr %t85)
  %t87 = call ptr @v_render(ptr %t86)
  %t88 = getelementptr ptr, ptr %t87, i32 0
  %t89 = load ptr, ptr %t88
  %t90 = ptrtoint ptr %t89 to i64
  switch i64 %t90, label %case.default.91 [ i64 3, label %case.arm.3.93 i64 4, label %case.arm.4.101 ]
case.arm.3.93:
  %t95 = getelementptr ptr, ptr %t87, i32 1
  %t96 = load ptr, ptr %t95
  call void @__inc_ref(ptr %t96)
  %t97 = call ptr @__alloc(i64 16, i32 1)
  %t98 = inttoptr i64 3 to ptr
  %t99 = getelementptr ptr, ptr %t97, i32 0
  store ptr %t98, ptr %t99
  call void @__inc_ref(ptr %t96)
  %t100 = getelementptr ptr, ptr %t97, i32 1
  store ptr %t96, ptr %t100
  br label %case.end.3.94
case.end.3.94:
  br label %case.join.92
case.arm.4.101:
  %t103 = getelementptr ptr, ptr %t87, i32 1
  %t104 = load ptr, ptr %t103
  call void @__inc_ref(ptr %t104)
  call void @__inc_ref(ptr %t20)
  %t105 = call ptr @__concat(ptr %t20, ptr getelementptr inbounds (i8, ptr @.str.3, i64 12))
  %t106 = getelementptr ptr, ptr %t105, i32 0
  %t107 = load ptr, ptr %t106
  %t108 = ptrtoint ptr %t107 to i64
  switch i64 %t108, label %case.default.109 [ i64 3, label %case.arm.3.111 i64 4, label %case.arm.4.119 ]
case.arm.3.111:
  %t113 = getelementptr ptr, ptr %t105, i32 1
  %t114 = load ptr, ptr %t113
  call void @__inc_ref(ptr %t114)
  %t115 = call ptr @__alloc(i64 16, i32 1)
  %t116 = inttoptr i64 3 to ptr
  %t117 = getelementptr ptr, ptr %t115, i32 0
  store ptr %t116, ptr %t117
  call void @__inc_ref(ptr %t114)
  %t118 = getelementptr ptr, ptr %t115, i32 1
  store ptr %t114, ptr %t118
  br label %case.end.3.112
case.end.3.112:
  br label %case.join.110
case.arm.4.119:
  %t121 = getelementptr ptr, ptr %t105, i32 1
  %t122 = load ptr, ptr %t121
  call void @__inc_ref(ptr %t122)
  call void @__inc_ref(ptr %t122)
  call void @__inc_ref(ptr %t41)
  %t123 = call ptr @__concat(ptr %t122, ptr %t41)
  %t124 = getelementptr ptr, ptr %t123, i32 0
  %t125 = load ptr, ptr %t124
  %t126 = ptrtoint ptr %t125 to i64
  switch i64 %t126, label %case.default.127 [ i64 3, label %case.arm.3.129 i64 4, label %case.arm.4.137 ]
case.arm.3.129:
  %t131 = getelementptr ptr, ptr %t123, i32 1
  %t132 = load ptr, ptr %t131
  call void @__inc_ref(ptr %t132)
  %t133 = call ptr @__alloc(i64 16, i32 1)
  %t134 = inttoptr i64 3 to ptr
  %t135 = getelementptr ptr, ptr %t133, i32 0
  store ptr %t134, ptr %t135
  call void @__inc_ref(ptr %t132)
  %t136 = getelementptr ptr, ptr %t133, i32 1
  store ptr %t132, ptr %t136
  br label %case.end.3.130
case.end.3.130:
  br label %case.join.128
case.arm.4.137:
  %t139 = getelementptr ptr, ptr %t123, i32 1
  %t140 = load ptr, ptr %t139
  call void @__inc_ref(ptr %t140)
  call void @__inc_ref(ptr %t140)
  %t141 = call ptr @__concat(ptr %t140, ptr getelementptr inbounds (i8, ptr @.str.3, i64 12))
  %t142 = getelementptr ptr, ptr %t141, i32 0
  %t143 = load ptr, ptr %t142
  %t144 = ptrtoint ptr %t143 to i64
  switch i64 %t144, label %case.default.145 [ i64 3, label %case.arm.3.147 i64 4, label %case.arm.4.155 ]
case.arm.3.147:
  %t149 = getelementptr ptr, ptr %t141, i32 1
  %t150 = load ptr, ptr %t149
  call void @__inc_ref(ptr %t150)
  %t151 = call ptr @__alloc(i64 16, i32 1)
  %t152 = inttoptr i64 3 to ptr
  %t153 = getelementptr ptr, ptr %t151, i32 0
  store ptr %t152, ptr %t153
  call void @__inc_ref(ptr %t150)
  %t154 = getelementptr ptr, ptr %t151, i32 1
  store ptr %t150, ptr %t154
  br label %case.end.3.148
case.end.3.148:
  br label %case.join.146
case.arm.4.155:
  %t157 = getelementptr ptr, ptr %t141, i32 1
  %t158 = load ptr, ptr %t157
  call void @__inc_ref(ptr %t158)
  call void @__inc_ref(ptr %t158)
  call void @__inc_ref(ptr %t62)
  %t159 = call ptr @__concat(ptr %t158, ptr %t62)
  %t160 = getelementptr ptr, ptr %t159, i32 0
  %t161 = load ptr, ptr %t160
  %t162 = ptrtoint ptr %t161 to i64
  switch i64 %t162, label %case.default.163 [ i64 3, label %case.arm.3.165 i64 4, label %case.arm.4.173 ]
case.arm.3.165:
  %t167 = getelementptr ptr, ptr %t159, i32 1
  %t168 = load ptr, ptr %t167
  call void @__inc_ref(ptr %t168)
  %t169 = call ptr @__alloc(i64 16, i32 1)
  %t170 = inttoptr i64 3 to ptr
  %t171 = getelementptr ptr, ptr %t169, i32 0
  store ptr %t170, ptr %t171
  call void @__inc_ref(ptr %t168)
  %t172 = getelementptr ptr, ptr %t169, i32 1
  store ptr %t168, ptr %t172
  br label %case.end.3.166
case.end.3.166:
  br label %case.join.164
case.arm.4.173:
  %t175 = getelementptr ptr, ptr %t159, i32 1
  %t176 = load ptr, ptr %t175
  call void @__inc_ref(ptr %t176)
  call void @__inc_ref(ptr %t176)
  %t177 = call ptr @__concat(ptr %t176, ptr getelementptr inbounds (i8, ptr @.str.3, i64 12))
  %t178 = getelementptr ptr, ptr %t177, i32 0
  %t179 = load ptr, ptr %t178
  %t180 = ptrtoint ptr %t179 to i64
  switch i64 %t180, label %case.default.181 [ i64 3, label %case.arm.3.183 i64 4, label %case.arm.4.191 ]
case.arm.3.183:
  %t185 = getelementptr ptr, ptr %t177, i32 1
  %t186 = load ptr, ptr %t185
  call void @__inc_ref(ptr %t186)
  %t187 = call ptr @__alloc(i64 16, i32 1)
  %t188 = inttoptr i64 3 to ptr
  %t189 = getelementptr ptr, ptr %t187, i32 0
  store ptr %t188, ptr %t189
  call void @__inc_ref(ptr %t186)
  %t190 = getelementptr ptr, ptr %t187, i32 1
  store ptr %t186, ptr %t190
  br label %case.end.3.184
case.end.3.184:
  br label %case.join.182
case.arm.4.191:
  %t193 = getelementptr ptr, ptr %t177, i32 1
  %t194 = load ptr, ptr %t193
  call void @__inc_ref(ptr %t194)
  call void @__inc_ref(ptr %t194)
  call void @__inc_ref(ptr %t83)
  %t195 = call ptr @__concat(ptr %t194, ptr %t83)
  %t196 = getelementptr ptr, ptr %t195, i32 0
  %t197 = load ptr, ptr %t196
  %t198 = ptrtoint ptr %t197 to i64
  switch i64 %t198, label %case.default.199 [ i64 3, label %case.arm.3.201 i64 4, label %case.arm.4.209 ]
case.arm.3.201:
  %t203 = getelementptr ptr, ptr %t195, i32 1
  %t204 = load ptr, ptr %t203
  call void @__inc_ref(ptr %t204)
  %t205 = call ptr @__alloc(i64 16, i32 1)
  %t206 = inttoptr i64 3 to ptr
  %t207 = getelementptr ptr, ptr %t205, i32 0
  store ptr %t206, ptr %t207
  call void @__inc_ref(ptr %t204)
  %t208 = getelementptr ptr, ptr %t205, i32 1
  store ptr %t204, ptr %t208
  br label %case.end.3.202
case.end.3.202:
  br label %case.join.200
case.arm.4.209:
  %t211 = getelementptr ptr, ptr %t195, i32 1
  %t212 = load ptr, ptr %t211
  call void @__inc_ref(ptr %t212)
  call void @__inc_ref(ptr %t212)
  %t213 = call ptr @__concat(ptr %t212, ptr getelementptr inbounds (i8, ptr @.str.3, i64 12))
  %t214 = getelementptr ptr, ptr %t213, i32 0
  %t215 = load ptr, ptr %t214
  %t216 = ptrtoint ptr %t215 to i64
  switch i64 %t216, label %case.default.217 [ i64 3, label %case.arm.3.219 i64 4, label %case.arm.4.227 ]
case.arm.3.219:
  %t221 = getelementptr ptr, ptr %t213, i32 1
  %t222 = load ptr, ptr %t221
  call void @__inc_ref(ptr %t222)
  %t223 = call ptr @__alloc(i64 16, i32 1)
  %t224 = inttoptr i64 3 to ptr
  %t225 = getelementptr ptr, ptr %t223, i32 0
  store ptr %t224, ptr %t225
  call void @__inc_ref(ptr %t222)
  %t226 = getelementptr ptr, ptr %t223, i32 1
  store ptr %t222, ptr %t226
  br label %case.end.3.220
case.end.3.220:
  br label %case.join.218
case.arm.4.227:
  %t229 = getelementptr ptr, ptr %t213, i32 1
  %t230 = load ptr, ptr %t229
  call void @__inc_ref(ptr %t230)
  call void @__inc_ref(ptr %t230)
  call void @__inc_ref(ptr %t104)
  %t231 = call ptr @__concat(ptr %t230, ptr %t104)
  br label %case.end.4.228
case.end.4.228:
  br label %case.join.218
case.default.217:
  unreachable
case.join.218:
  %t232 = phi ptr [%t223, %case.end.3.220], [%t231, %case.end.4.228]
  call void @__free_recursive(ptr %t213)
  br label %case.end.4.210
case.end.4.210:
  br label %case.join.200
case.default.199:
  unreachable
case.join.200:
  %t233 = phi ptr [%t205, %case.end.3.202], [%t232, %case.end.4.210]
  call void @__free_recursive(ptr %t195)
  br label %case.end.4.192
case.end.4.192:
  br label %case.join.182
case.default.181:
  unreachable
case.join.182:
  %t234 = phi ptr [%t187, %case.end.3.184], [%t233, %case.end.4.192]
  call void @__free_recursive(ptr %t177)
  br label %case.end.4.174
case.end.4.174:
  br label %case.join.164
case.default.163:
  unreachable
case.join.164:
  %t235 = phi ptr [%t169, %case.end.3.166], [%t234, %case.end.4.174]
  call void @__free_recursive(ptr %t159)
  br label %case.end.4.156
case.end.4.156:
  br label %case.join.146
case.default.145:
  unreachable
case.join.146:
  %t236 = phi ptr [%t151, %case.end.3.148], [%t235, %case.end.4.156]
  call void @__free_recursive(ptr %t141)
  br label %case.end.4.138
case.end.4.138:
  br label %case.join.128
case.default.127:
  unreachable
case.join.128:
  %t237 = phi ptr [%t133, %case.end.3.130], [%t236, %case.end.4.138]
  call void @__free_recursive(ptr %t123)
  br label %case.end.4.120
case.end.4.120:
  br label %case.join.110
case.default.109:
  unreachable
case.join.110:
  %t238 = phi ptr [%t115, %case.end.3.112], [%t237, %case.end.4.120]
  call void @__free_recursive(ptr %t105)
  br label %case.end.4.102
case.end.4.102:
  br label %case.join.92
case.default.91:
  unreachable
case.join.92:
  %t239 = phi ptr [%t97, %case.end.3.94], [%t238, %case.end.4.102]
  call void @__free_recursive(ptr %t87)
  br label %case.end.4.81
case.end.4.81:
  br label %case.join.71
case.default.70:
  unreachable
case.join.71:
  %t240 = phi ptr [%t76, %case.end.3.73], [%t239, %case.end.4.81]
  call void @__free_recursive(ptr %t66)
  br label %case.end.4.60
case.end.4.60:
  br label %case.join.50
case.default.49:
  unreachable
case.join.50:
  %t241 = phi ptr [%t55, %case.end.3.52], [%t240, %case.end.4.60]
  call void @__free_recursive(ptr %t45)
  br label %case.end.4.39
case.end.4.39:
  br label %case.join.29
case.default.28:
  unreachable
case.join.29:
  %t242 = phi ptr [%t34, %case.end.3.31], [%t241, %case.end.4.39]
  call void @__free_recursive(ptr %t24)
  br label %case.end.4.18
case.end.4.18:
  br label %case.join.8
case.default.7:
  unreachable
case.join.8:
  %t243 = phi ptr [%t13, %case.end.3.10], [%t242, %case.end.4.18]
  call void @__free_recursive(ptr %t3)
  %t244 = call ptr @v__let_7(ptr %t243)
  ret ptr %t244
}

define internal ptr @v__let_7(ptr %v_res) {
  %t0 = getelementptr ptr, ptr %v_res, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.19 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v_res, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = call ptr @__alloc(i64 24, i32 2)
  %t8 = inttoptr i64 7 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = getelementptr ptr, ptr %t7, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t10
  %t11 = call ptr @__alloc(i64 16, i32 1)
  %t12 = inttoptr i64 5 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  %t14 = call ptr @__alloc(i64 8, i32 0)
  %t15 = inttoptr i64 0 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  %t17 = getelementptr ptr, ptr %t11, i32 1
  store ptr %t14, ptr %t17
  %t18 = getelementptr ptr, ptr %t7, i32 2
  store ptr %t11, ptr %t18
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_res)
  ret ptr %t7
case.arm.4.19:
  %t20 = getelementptr ptr, ptr %v_res, i32 1
  %t21 = load ptr, ptr %t20
  call void @__inc_ref(ptr %t21)
  %t22 = call ptr @__alloc(i64 24, i32 2)
  %t23 = inttoptr i64 7 to ptr
  %t24 = getelementptr ptr, ptr %t22, i32 0
  store ptr %t23, ptr %t24
  call void @__inc_ref(ptr %t21)
  %t25 = getelementptr ptr, ptr %t22, i32 1
  store ptr %t21, ptr %t25
  %t26 = call ptr @__alloc(i64 16, i32 1)
  %t27 = inttoptr i64 5 to ptr
  %t28 = getelementptr ptr, ptr %t26, i32 0
  store ptr %t27, ptr %t28
  %t29 = call ptr @__alloc(i64 8, i32 0)
  %t30 = inttoptr i64 0 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = getelementptr ptr, ptr %t26, i32 1
  store ptr %t29, ptr %t32
  %t33 = getelementptr ptr, ptr %t22, i32 2
  store ptr %t26, ptr %t33
  call void @__free_recursive(ptr %t21)
  call void @__free_recursive(ptr %v_res)
  ret ptr %t22
case.default.3:
  unreachable
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
  %input = phi ptr [%arg, %with_arg], [getelementptr inbounds (i8, ptr @.empty, i64 12), %no_arg]
  store ptr %input, ptr @.cli_arg
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
