; External C declarations
declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare ptr @memcpy(ptr, ptr, i64)
declare i64 @write(i32, ptr, i64)
declare i32 @snprintf(ptr, i64, ptr, ...)

@.fmt_u8 = private unnamed_addr constant [3 x i8] c"%u\00"

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

@__free_worklist = internal global ptr null
@__free_worklist_top = internal global i64 0
@__free_worklist_cap = internal global i64 0

define internal void @__free_worklist_push(ptr %p) {
entry:
  %top = load i64, ptr @__free_worklist_top
  %cap = load i64, ptr @__free_worklist_cap
  %is_full = icmp eq i64 %top, %cap
  br i1 %is_full, label %grow, label %store
grow:
  %cap_zero = icmp eq i64 %cap, 0
  %doubled = shl i64 %cap, 1
  %new_cap = select i1 %cap_zero, i64 16, i64 %doubled
  %bytes = mul i64 %new_cap, 8
  %old_buf = load ptr, ptr @__free_worklist
  %new_buf = call ptr @realloc(ptr %old_buf, i64 %bytes)
  store ptr %new_buf, ptr @__free_worklist
  store i64 %new_cap, ptr @__free_worklist_cap
  br label %store
store:
  %buf = load ptr, ptr @__free_worklist
  %slot = getelementptr ptr, ptr %buf, i64 %top
  store ptr %p, ptr %slot
  %top_new = add i64 %top, 1
  store i64 %top_new, ptr @__free_worklist_top
  ret void
}

define internal void @__free_recursive(ptr %p_arg) {
entry:
  br label %top
top:
  %p = phi ptr [ %p_arg, %entry ], [ %p_after, %continue ]
  %hdr_ptr = getelementptr i8, ptr %p, i64 -12
  %flag = load i32, ptr %hdr_ptr
  %is_heap = icmp eq i32 %flag, 1
  br i1 %is_heap, label %do_dec, label %try_pop
do_dec:
  %rc_p = getelementptr i8, ptr %p, i64 -8
  %rc_old = load i32, ptr %rc_p
  %rc_new = sub i32 %rc_old, 1
  store i32 %rc_new, ptr %rc_p
  %is_zero = icmp eq i32 %rc_new, 0
  br i1 %is_zero, label %do_cascade, label %try_pop
do_cascade:
  %shape_p = getelementptr i8, ptr %p, i64 -4
  %shape = load i32, ptr %shape_p
  %shape_zero = icmp eq i32 %shape, 0
  br i1 %shape_zero, label %free_and_pop, label %loop_check
loop_check:
  %i = phi i32 [ 1, %do_cascade ], [ %i_next, %loop_body ]
  %cmp = icmp ult i32 %i, %shape
  br i1 %cmp, label %loop_body, label %tail_jump_prep
loop_body:
  %i64 = zext i32 %i to i64
  %slot_p = getelementptr ptr, ptr %p, i64 %i64
  %child = load ptr, ptr %slot_p
  call void @__free_worklist_push(ptr %child)
  %i_next = add i32 %i, 1
  br label %loop_check
tail_jump_prep:
  %shape64 = zext i32 %shape to i64
  %last_slot_p = getelementptr ptr, ptr %p, i64 %shape64
  %p_next_tail = load ptr, ptr %last_slot_p
  call void @free(ptr %hdr_ptr)
  br label %continue
free_and_pop:
  call void @free(ptr %hdr_ptr)
  br label %try_pop
try_pop:
  %top_old = load i64, ptr @__free_worklist_top
  %is_empty = icmp eq i64 %top_old, 0
  br i1 %is_empty, label %done, label %do_pop
do_pop:
  %top_new = sub i64 %top_old, 1
  store i64 %top_new, ptr @__free_worklist_top
  %wl_buf = load ptr, ptr @__free_worklist
  %wl_slot = getelementptr ptr, ptr %wl_buf, i64 %top_new
  %p_popped = load ptr, ptr %wl_slot
  br label %continue
continue:
  %p_after = phi ptr [ %p_next_tail, %tail_jump_prep ], [ %p_popped, %do_pop ]
  br label %top
done:
  ret void
}

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [10 x i8]} { i32 0, i32 0, i32 0, i32 10, i32 10, [10 x i8] c"overflow: " }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [13 x i8]} { i32 0, i32 0, i32 0, i32 13, i32 13, [13 x i8] c"OverflowError" }
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
  %stl_tag = inttoptr i64 19 to ptr
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
  %result = phi ptr [ %left, %too_long ], [ %right, %ok ]
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


define internal ptr @__showUInt32(ptr %p) {
  %v = load i32, ptr %p
  %buf = call ptr @__alloc(i64 24, i32 0)
  %payload = getelementptr i8, ptr %buf, i64 8
  %n = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %payload, i64 16, ptr @.fmt_u8, i32 %v)
  store i32 %n, ptr %buf
  %u16p = getelementptr i8, ptr %buf, i64 4
  store i32 %n, ptr %u16p
  call void @__free_recursive(ptr %p)
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
  %oe = call ptr @__alloc(i64 8, i32 0)
  %oe_tag = inttoptr i64 18 to ptr
  store ptr %oe_tag, ptr %oe
  %left = call ptr @__alloc(i64 16, i32 1)
  %left_tag = inttoptr i64 3 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %oe, ptr %left_f
  br label %join
ok:
  %newv = trunc i64 %prod64 to i32
  %box = call ptr @__alloc(i64 4, i32 0)
  store i32 %newv, ptr %box
  %right = call ptr @__alloc(i64 16, i32 1)
  %right_tag = inttoptr i64 4 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %box, ptr %right_f
  br label %join
join:
  %result = phi ptr [ %left, %err ], [ %right, %ok ]
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
  %t15 = call ptr @__print(ptr %t14)
  %t16 = getelementptr ptr, ptr %t4, i32 2
  %t17 = load ptr, ptr %t16
  call void @__inc_ref(ptr %t17)
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t15)
  store ptr %t17, ptr %t3
  br label %tco.loop.0
tco.case.default.8:
  unreachable
tco.exit.1:
  %t18 = load ptr, ptr %t2
  ret ptr %t18
}

define internal ptr @v_minUInt32() {
  %t0 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t0
  ret ptr %t0
}

define internal ptr @v_maxUInt32() {
  %t0 = call ptr @__alloc(i64 4, i32 0)
  store i32 -1, ptr %t0
  ret ptr %t0
}

define internal ptr @v_res() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 4 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 4, i32 0)
  store i32 -1, ptr %t3
  %t4 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t4
  %t5 = getelementptr ptr, ptr %t0, i32 0
  %t6 = load ptr, ptr %t5
  %t7 = ptrtoint ptr %t6 to i64
  switch i64 %t7, label %case.default.8 [ i64 3, label %case.arm.3.10 i64 4, label %case.arm.4.13 ]
case.arm.3.10:
  %t12 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  br label %case.end.3.11
case.end.3.11:
  br label %case.join.9
case.arm.4.13:
  %t15 = getelementptr ptr, ptr %t0, i32 1
  %t16 = load ptr, ptr %t15
  call void @__inc_ref(ptr %t16)
  %t17 = call ptr @__showUInt32(ptr %t16)
  %t18 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t17)
  br label %case.end.4.14
case.end.4.14:
  br label %case.join.9
case.default.8:
  unreachable
case.join.9:
  %t19 = phi ptr [ %t12, %case.end.3.11 ], [ %t18, %case.end.4.14 ]
  %t20 = getelementptr ptr, ptr %t19, i32 0
  %t21 = load ptr, ptr %t20
  %t22 = ptrtoint ptr %t21 to i64
  switch i64 %t22, label %case.default.23 [ i64 3, label %case.arm.3.25 i64 4, label %case.arm.4.33 ]
case.arm.3.25:
  %t27 = getelementptr ptr, ptr %t19, i32 1
  %t28 = load ptr, ptr %t27
  call void @__inc_ref(ptr %t28)
  %t29 = call ptr @__alloc(i64 16, i32 1)
  %t30 = inttoptr i64 3 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  call void @__inc_ref(ptr %t28)
  %t32 = getelementptr ptr, ptr %t29, i32 1
  store ptr %t28, ptr %t32
  br label %case.end.3.26
case.end.3.26:
  br label %case.join.24
case.arm.4.33:
  %t35 = getelementptr ptr, ptr %t19, i32 1
  %t36 = load ptr, ptr %t35
  call void @__inc_ref(ptr %t36)
  %t37 = call ptr @__alloc(i64 16, i32 1)
  %t38 = inttoptr i64 3 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = call ptr @__alloc(i64 8, i32 0)
  %t41 = inttoptr i64 18 to ptr
  %t42 = getelementptr ptr, ptr %t40, i32 0
  store ptr %t41, ptr %t42
  %t43 = getelementptr ptr, ptr %t37, i32 1
  store ptr %t40, ptr %t43
  %t44 = getelementptr ptr, ptr %t37, i32 0
  %t45 = load ptr, ptr %t44
  %t46 = ptrtoint ptr %t45 to i64
  switch i64 %t46, label %case.default.47 [ i64 3, label %case.arm.3.49 i64 4, label %case.arm.4.52 ]
case.arm.3.49:
  %t51 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  br label %case.end.3.50
case.end.3.50:
  br label %case.join.48
case.arm.4.52:
  %t54 = getelementptr ptr, ptr %t37, i32 1
  %t55 = load ptr, ptr %t54
  call void @__inc_ref(ptr %t55)
  %t56 = call ptr @__showUInt32(ptr %t55)
  %t57 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t56)
  br label %case.end.4.53
case.end.4.53:
  br label %case.join.48
case.default.47:
  unreachable
case.join.48:
  %t58 = phi ptr [ %t51, %case.end.3.50 ], [ %t57, %case.end.4.53 ]
  %t59 = getelementptr ptr, ptr %t58, i32 0
  %t60 = load ptr, ptr %t59
  %t61 = ptrtoint ptr %t60 to i64
  switch i64 %t61, label %case.default.62 [ i64 3, label %case.arm.3.64 i64 4, label %case.arm.4.72 ]
case.arm.3.64:
  %t66 = getelementptr ptr, ptr %t58, i32 1
  %t67 = load ptr, ptr %t66
  call void @__inc_ref(ptr %t67)
  %t68 = call ptr @__alloc(i64 16, i32 1)
  %t69 = inttoptr i64 3 to ptr
  %t70 = getelementptr ptr, ptr %t68, i32 0
  store ptr %t69, ptr %t70
  call void @__inc_ref(ptr %t67)
  %t71 = getelementptr ptr, ptr %t68, i32 1
  store ptr %t67, ptr %t71
  br label %case.end.3.65
case.end.3.65:
  br label %case.join.63
case.arm.4.72:
  %t74 = getelementptr ptr, ptr %t58, i32 1
  %t75 = load ptr, ptr %t74
  call void @__inc_ref(ptr %t75)
  %t76 = call ptr @v_maxUInt32()
  %t77 = call ptr @v_maxUInt32()
  %t78 = call ptr @__mulUInt32(ptr %t76, ptr %t77)
  %t79 = getelementptr ptr, ptr %t78, i32 0
  %t80 = load ptr, ptr %t79
  %t81 = ptrtoint ptr %t80 to i64
  switch i64 %t81, label %case.default.82 [ i64 3, label %case.arm.3.84 i64 4, label %case.arm.4.87 ]
case.arm.3.84:
  %t86 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  br label %case.end.3.85
case.end.3.85:
  br label %case.join.83
case.arm.4.87:
  %t89 = getelementptr ptr, ptr %t78, i32 1
  %t90 = load ptr, ptr %t89
  call void @__inc_ref(ptr %t90)
  %t91 = call ptr @__showUInt32(ptr %t90)
  %t92 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t91)
  br label %case.end.4.88
case.end.4.88:
  br label %case.join.83
case.default.82:
  unreachable
case.join.83:
  %t93 = phi ptr [ %t86, %case.end.3.85 ], [ %t92, %case.end.4.88 ]
  %t94 = getelementptr ptr, ptr %t93, i32 0
  %t95 = load ptr, ptr %t94
  %t96 = ptrtoint ptr %t95 to i64
  switch i64 %t96, label %case.default.97 [ i64 3, label %case.arm.3.99 i64 4, label %case.arm.4.107 ]
case.arm.3.99:
  %t101 = getelementptr ptr, ptr %t93, i32 1
  %t102 = load ptr, ptr %t101
  call void @__inc_ref(ptr %t102)
  %t103 = call ptr @__alloc(i64 16, i32 1)
  %t104 = inttoptr i64 3 to ptr
  %t105 = getelementptr ptr, ptr %t103, i32 0
  store ptr %t104, ptr %t105
  call void @__inc_ref(ptr %t102)
  %t106 = getelementptr ptr, ptr %t103, i32 1
  store ptr %t102, ptr %t106
  br label %case.end.3.100
case.end.3.100:
  br label %case.join.98
case.arm.4.107:
  %t109 = getelementptr ptr, ptr %t93, i32 1
  %t110 = load ptr, ptr %t109
  call void @__inc_ref(ptr %t110)
  %t111 = call ptr @v_minUInt32()
  %t112 = call ptr @v_maxUInt32()
  %t113 = call ptr @__mulUInt32(ptr %t111, ptr %t112)
  %t114 = getelementptr ptr, ptr %t113, i32 0
  %t115 = load ptr, ptr %t114
  %t116 = ptrtoint ptr %t115 to i64
  switch i64 %t116, label %case.default.117 [ i64 3, label %case.arm.3.119 i64 4, label %case.arm.4.122 ]
case.arm.3.119:
  %t121 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  br label %case.end.3.120
case.end.3.120:
  br label %case.join.118
case.arm.4.122:
  %t124 = getelementptr ptr, ptr %t113, i32 1
  %t125 = load ptr, ptr %t124
  call void @__inc_ref(ptr %t125)
  %t126 = call ptr @__showUInt32(ptr %t125)
  %t127 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t126)
  br label %case.end.4.123
case.end.4.123:
  br label %case.join.118
case.default.117:
  unreachable
case.join.118:
  %t128 = phi ptr [ %t121, %case.end.3.120 ], [ %t127, %case.end.4.123 ]
  %t129 = getelementptr ptr, ptr %t128, i32 0
  %t130 = load ptr, ptr %t129
  %t131 = ptrtoint ptr %t130 to i64
  switch i64 %t131, label %case.default.132 [ i64 3, label %case.arm.3.134 i64 4, label %case.arm.4.142 ]
case.arm.3.134:
  %t136 = getelementptr ptr, ptr %t128, i32 1
  %t137 = load ptr, ptr %t136
  call void @__inc_ref(ptr %t137)
  %t138 = call ptr @__alloc(i64 16, i32 1)
  %t139 = inttoptr i64 3 to ptr
  %t140 = getelementptr ptr, ptr %t138, i32 0
  store ptr %t139, ptr %t140
  call void @__inc_ref(ptr %t137)
  %t141 = getelementptr ptr, ptr %t138, i32 1
  store ptr %t137, ptr %t141
  br label %case.end.3.135
case.end.3.135:
  br label %case.join.133
case.arm.4.142:
  %t144 = getelementptr ptr, ptr %t128, i32 1
  %t145 = load ptr, ptr %t144
  call void @__inc_ref(ptr %t145)
  %t146 = call ptr @__alloc(i64 16, i32 1)
  %t147 = inttoptr i64 4 to ptr
  %t148 = getelementptr ptr, ptr %t146, i32 0
  store ptr %t147, ptr %t148
  %t149 = call ptr @__alloc(i64 4, i32 0)
  store i32 -2147483648, ptr %t149
  %t150 = getelementptr ptr, ptr %t146, i32 1
  store ptr %t149, ptr %t150
  %t151 = getelementptr ptr, ptr %t146, i32 0
  %t152 = load ptr, ptr %t151
  %t153 = ptrtoint ptr %t152 to i64
  switch i64 %t153, label %case.default.154 [ i64 3, label %case.arm.3.156 i64 4, label %case.arm.4.159 ]
case.arm.3.156:
  %t158 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  br label %case.end.3.157
case.end.3.157:
  br label %case.join.155
case.arm.4.159:
  %t161 = getelementptr ptr, ptr %t146, i32 1
  %t162 = load ptr, ptr %t161
  call void @__inc_ref(ptr %t162)
  %t163 = call ptr @__showUInt32(ptr %t162)
  %t164 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t163)
  br label %case.end.4.160
case.end.4.160:
  br label %case.join.155
case.default.154:
  unreachable
case.join.155:
  %t165 = phi ptr [ %t158, %case.end.3.157 ], [ %t164, %case.end.4.160 ]
  %t166 = getelementptr ptr, ptr %t165, i32 0
  %t167 = load ptr, ptr %t166
  %t168 = ptrtoint ptr %t167 to i64
  switch i64 %t168, label %case.default.169 [ i64 3, label %case.arm.3.171 i64 4, label %case.arm.4.179 ]
case.arm.3.171:
  %t173 = getelementptr ptr, ptr %t165, i32 1
  %t174 = load ptr, ptr %t173
  call void @__inc_ref(ptr %t174)
  %t175 = call ptr @__alloc(i64 16, i32 1)
  %t176 = inttoptr i64 3 to ptr
  %t177 = getelementptr ptr, ptr %t175, i32 0
  store ptr %t176, ptr %t177
  call void @__inc_ref(ptr %t174)
  %t178 = getelementptr ptr, ptr %t175, i32 1
  store ptr %t174, ptr %t178
  br label %case.end.3.172
case.end.3.172:
  br label %case.join.170
case.arm.4.179:
  %t181 = getelementptr ptr, ptr %t165, i32 1
  %t182 = load ptr, ptr %t181
  call void @__inc_ref(ptr %t182)
  %t183 = call ptr @__alloc(i64 16, i32 1)
  %t184 = inttoptr i64 3 to ptr
  %t185 = getelementptr ptr, ptr %t183, i32 0
  store ptr %t184, ptr %t185
  %t186 = call ptr @__alloc(i64 8, i32 0)
  %t187 = inttoptr i64 18 to ptr
  %t188 = getelementptr ptr, ptr %t186, i32 0
  store ptr %t187, ptr %t188
  %t189 = getelementptr ptr, ptr %t183, i32 1
  store ptr %t186, ptr %t189
  %t190 = getelementptr ptr, ptr %t183, i32 0
  %t191 = load ptr, ptr %t190
  %t192 = ptrtoint ptr %t191 to i64
  switch i64 %t192, label %case.default.193 [ i64 3, label %case.arm.3.195 i64 4, label %case.arm.4.198 ]
case.arm.3.195:
  %t197 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  br label %case.end.3.196
case.end.3.196:
  br label %case.join.194
case.arm.4.198:
  %t200 = getelementptr ptr, ptr %t183, i32 1
  %t201 = load ptr, ptr %t200
  call void @__inc_ref(ptr %t201)
  %t202 = call ptr @__showUInt32(ptr %t201)
  %t203 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t202)
  br label %case.end.4.199
case.end.4.199:
  br label %case.join.194
case.default.193:
  unreachable
case.join.194:
  %t204 = phi ptr [ %t197, %case.end.3.196 ], [ %t203, %case.end.4.199 ]
  %t205 = getelementptr ptr, ptr %t204, i32 0
  %t206 = load ptr, ptr %t205
  %t207 = ptrtoint ptr %t206 to i64
  switch i64 %t207, label %case.default.208 [ i64 3, label %case.arm.3.210 i64 4, label %case.arm.4.218 ]
case.arm.3.210:
  %t212 = getelementptr ptr, ptr %t204, i32 1
  %t213 = load ptr, ptr %t212
  call void @__inc_ref(ptr %t213)
  %t214 = call ptr @__alloc(i64 16, i32 1)
  %t215 = inttoptr i64 3 to ptr
  %t216 = getelementptr ptr, ptr %t214, i32 0
  store ptr %t215, ptr %t216
  call void @__inc_ref(ptr %t213)
  %t217 = getelementptr ptr, ptr %t214, i32 1
  store ptr %t213, ptr %t217
  br label %case.end.3.211
case.end.3.211:
  br label %case.join.209
case.arm.4.218:
  %t220 = getelementptr ptr, ptr %t204, i32 1
  %t221 = load ptr, ptr %t220
  call void @__inc_ref(ptr %t221)
  call void @__inc_ref(ptr %t36)
  %t222 = call ptr @__concat(ptr %t36, ptr getelementptr inbounds (i8, ptr @.str.3, i64 12))
  %t223 = getelementptr ptr, ptr %t222, i32 0
  %t224 = load ptr, ptr %t223
  %t225 = ptrtoint ptr %t224 to i64
  switch i64 %t225, label %case.default.226 [ i64 3, label %case.arm.3.228 i64 4, label %case.arm.4.236 ]
case.arm.3.228:
  %t230 = getelementptr ptr, ptr %t222, i32 1
  %t231 = load ptr, ptr %t230
  call void @__inc_ref(ptr %t231)
  %t232 = call ptr @__alloc(i64 16, i32 1)
  %t233 = inttoptr i64 3 to ptr
  %t234 = getelementptr ptr, ptr %t232, i32 0
  store ptr %t233, ptr %t234
  call void @__inc_ref(ptr %t231)
  %t235 = getelementptr ptr, ptr %t232, i32 1
  store ptr %t231, ptr %t235
  br label %case.end.3.229
case.end.3.229:
  br label %case.join.227
case.arm.4.236:
  %t238 = getelementptr ptr, ptr %t222, i32 1
  %t239 = load ptr, ptr %t238
  call void @__inc_ref(ptr %t239)
  call void @__inc_ref(ptr %t239)
  call void @__inc_ref(ptr %t75)
  %t240 = call ptr @__concat(ptr %t239, ptr %t75)
  %t241 = getelementptr ptr, ptr %t240, i32 0
  %t242 = load ptr, ptr %t241
  %t243 = ptrtoint ptr %t242 to i64
  switch i64 %t243, label %case.default.244 [ i64 3, label %case.arm.3.246 i64 4, label %case.arm.4.254 ]
case.arm.3.246:
  %t248 = getelementptr ptr, ptr %t240, i32 1
  %t249 = load ptr, ptr %t248
  call void @__inc_ref(ptr %t249)
  %t250 = call ptr @__alloc(i64 16, i32 1)
  %t251 = inttoptr i64 3 to ptr
  %t252 = getelementptr ptr, ptr %t250, i32 0
  store ptr %t251, ptr %t252
  call void @__inc_ref(ptr %t249)
  %t253 = getelementptr ptr, ptr %t250, i32 1
  store ptr %t249, ptr %t253
  br label %case.end.3.247
case.end.3.247:
  br label %case.join.245
case.arm.4.254:
  %t256 = getelementptr ptr, ptr %t240, i32 1
  %t257 = load ptr, ptr %t256
  call void @__inc_ref(ptr %t257)
  call void @__inc_ref(ptr %t257)
  %t258 = call ptr @__concat(ptr %t257, ptr getelementptr inbounds (i8, ptr @.str.3, i64 12))
  %t259 = getelementptr ptr, ptr %t258, i32 0
  %t260 = load ptr, ptr %t259
  %t261 = ptrtoint ptr %t260 to i64
  switch i64 %t261, label %case.default.262 [ i64 3, label %case.arm.3.264 i64 4, label %case.arm.4.272 ]
case.arm.3.264:
  %t266 = getelementptr ptr, ptr %t258, i32 1
  %t267 = load ptr, ptr %t266
  call void @__inc_ref(ptr %t267)
  %t268 = call ptr @__alloc(i64 16, i32 1)
  %t269 = inttoptr i64 3 to ptr
  %t270 = getelementptr ptr, ptr %t268, i32 0
  store ptr %t269, ptr %t270
  call void @__inc_ref(ptr %t267)
  %t271 = getelementptr ptr, ptr %t268, i32 1
  store ptr %t267, ptr %t271
  br label %case.end.3.265
case.end.3.265:
  br label %case.join.263
case.arm.4.272:
  %t274 = getelementptr ptr, ptr %t258, i32 1
  %t275 = load ptr, ptr %t274
  call void @__inc_ref(ptr %t275)
  call void @__inc_ref(ptr %t275)
  call void @__inc_ref(ptr %t110)
  %t276 = call ptr @__concat(ptr %t275, ptr %t110)
  %t277 = getelementptr ptr, ptr %t276, i32 0
  %t278 = load ptr, ptr %t277
  %t279 = ptrtoint ptr %t278 to i64
  switch i64 %t279, label %case.default.280 [ i64 3, label %case.arm.3.282 i64 4, label %case.arm.4.290 ]
case.arm.3.282:
  %t284 = getelementptr ptr, ptr %t276, i32 1
  %t285 = load ptr, ptr %t284
  call void @__inc_ref(ptr %t285)
  %t286 = call ptr @__alloc(i64 16, i32 1)
  %t287 = inttoptr i64 3 to ptr
  %t288 = getelementptr ptr, ptr %t286, i32 0
  store ptr %t287, ptr %t288
  call void @__inc_ref(ptr %t285)
  %t289 = getelementptr ptr, ptr %t286, i32 1
  store ptr %t285, ptr %t289
  br label %case.end.3.283
case.end.3.283:
  br label %case.join.281
case.arm.4.290:
  %t292 = getelementptr ptr, ptr %t276, i32 1
  %t293 = load ptr, ptr %t292
  call void @__inc_ref(ptr %t293)
  call void @__inc_ref(ptr %t293)
  %t294 = call ptr @__concat(ptr %t293, ptr getelementptr inbounds (i8, ptr @.str.3, i64 12))
  %t295 = getelementptr ptr, ptr %t294, i32 0
  %t296 = load ptr, ptr %t295
  %t297 = ptrtoint ptr %t296 to i64
  switch i64 %t297, label %case.default.298 [ i64 3, label %case.arm.3.300 i64 4, label %case.arm.4.308 ]
case.arm.3.300:
  %t302 = getelementptr ptr, ptr %t294, i32 1
  %t303 = load ptr, ptr %t302
  call void @__inc_ref(ptr %t303)
  %t304 = call ptr @__alloc(i64 16, i32 1)
  %t305 = inttoptr i64 3 to ptr
  %t306 = getelementptr ptr, ptr %t304, i32 0
  store ptr %t305, ptr %t306
  call void @__inc_ref(ptr %t303)
  %t307 = getelementptr ptr, ptr %t304, i32 1
  store ptr %t303, ptr %t307
  br label %case.end.3.301
case.end.3.301:
  br label %case.join.299
case.arm.4.308:
  %t310 = getelementptr ptr, ptr %t294, i32 1
  %t311 = load ptr, ptr %t310
  call void @__inc_ref(ptr %t311)
  call void @__inc_ref(ptr %t311)
  call void @__inc_ref(ptr %t145)
  %t312 = call ptr @__concat(ptr %t311, ptr %t145)
  %t313 = getelementptr ptr, ptr %t312, i32 0
  %t314 = load ptr, ptr %t313
  %t315 = ptrtoint ptr %t314 to i64
  switch i64 %t315, label %case.default.316 [ i64 3, label %case.arm.3.318 i64 4, label %case.arm.4.326 ]
case.arm.3.318:
  %t320 = getelementptr ptr, ptr %t312, i32 1
  %t321 = load ptr, ptr %t320
  call void @__inc_ref(ptr %t321)
  %t322 = call ptr @__alloc(i64 16, i32 1)
  %t323 = inttoptr i64 3 to ptr
  %t324 = getelementptr ptr, ptr %t322, i32 0
  store ptr %t323, ptr %t324
  call void @__inc_ref(ptr %t321)
  %t325 = getelementptr ptr, ptr %t322, i32 1
  store ptr %t321, ptr %t325
  br label %case.end.3.319
case.end.3.319:
  br label %case.join.317
case.arm.4.326:
  %t328 = getelementptr ptr, ptr %t312, i32 1
  %t329 = load ptr, ptr %t328
  call void @__inc_ref(ptr %t329)
  call void @__inc_ref(ptr %t329)
  %t330 = call ptr @__concat(ptr %t329, ptr getelementptr inbounds (i8, ptr @.str.3, i64 12))
  %t331 = getelementptr ptr, ptr %t330, i32 0
  %t332 = load ptr, ptr %t331
  %t333 = ptrtoint ptr %t332 to i64
  switch i64 %t333, label %case.default.334 [ i64 3, label %case.arm.3.336 i64 4, label %case.arm.4.344 ]
case.arm.3.336:
  %t338 = getelementptr ptr, ptr %t330, i32 1
  %t339 = load ptr, ptr %t338
  call void @__inc_ref(ptr %t339)
  %t340 = call ptr @__alloc(i64 16, i32 1)
  %t341 = inttoptr i64 3 to ptr
  %t342 = getelementptr ptr, ptr %t340, i32 0
  store ptr %t341, ptr %t342
  call void @__inc_ref(ptr %t339)
  %t343 = getelementptr ptr, ptr %t340, i32 1
  store ptr %t339, ptr %t343
  br label %case.end.3.337
case.end.3.337:
  br label %case.join.335
case.arm.4.344:
  %t346 = getelementptr ptr, ptr %t330, i32 1
  %t347 = load ptr, ptr %t346
  call void @__inc_ref(ptr %t347)
  call void @__inc_ref(ptr %t347)
  call void @__inc_ref(ptr %t182)
  %t348 = call ptr @__concat(ptr %t347, ptr %t182)
  %t349 = getelementptr ptr, ptr %t348, i32 0
  %t350 = load ptr, ptr %t349
  %t351 = ptrtoint ptr %t350 to i64
  switch i64 %t351, label %case.default.352 [ i64 3, label %case.arm.3.354 i64 4, label %case.arm.4.362 ]
case.arm.3.354:
  %t356 = getelementptr ptr, ptr %t348, i32 1
  %t357 = load ptr, ptr %t356
  call void @__inc_ref(ptr %t357)
  %t358 = call ptr @__alloc(i64 16, i32 1)
  %t359 = inttoptr i64 3 to ptr
  %t360 = getelementptr ptr, ptr %t358, i32 0
  store ptr %t359, ptr %t360
  call void @__inc_ref(ptr %t357)
  %t361 = getelementptr ptr, ptr %t358, i32 1
  store ptr %t357, ptr %t361
  br label %case.end.3.355
case.end.3.355:
  br label %case.join.353
case.arm.4.362:
  %t364 = getelementptr ptr, ptr %t348, i32 1
  %t365 = load ptr, ptr %t364
  call void @__inc_ref(ptr %t365)
  call void @__inc_ref(ptr %t365)
  %t366 = call ptr @__concat(ptr %t365, ptr getelementptr inbounds (i8, ptr @.str.3, i64 12))
  %t367 = getelementptr ptr, ptr %t366, i32 0
  %t368 = load ptr, ptr %t367
  %t369 = ptrtoint ptr %t368 to i64
  switch i64 %t369, label %case.default.370 [ i64 3, label %case.arm.3.372 i64 4, label %case.arm.4.380 ]
case.arm.3.372:
  %t374 = getelementptr ptr, ptr %t366, i32 1
  %t375 = load ptr, ptr %t374
  call void @__inc_ref(ptr %t375)
  %t376 = call ptr @__alloc(i64 16, i32 1)
  %t377 = inttoptr i64 3 to ptr
  %t378 = getelementptr ptr, ptr %t376, i32 0
  store ptr %t377, ptr %t378
  call void @__inc_ref(ptr %t375)
  %t379 = getelementptr ptr, ptr %t376, i32 1
  store ptr %t375, ptr %t379
  br label %case.end.3.373
case.end.3.373:
  br label %case.join.371
case.arm.4.380:
  %t382 = getelementptr ptr, ptr %t366, i32 1
  %t383 = load ptr, ptr %t382
  call void @__inc_ref(ptr %t383)
  call void @__inc_ref(ptr %t383)
  call void @__inc_ref(ptr %t221)
  %t384 = call ptr @__concat(ptr %t383, ptr %t221)
  br label %case.end.4.381
case.end.4.381:
  br label %case.join.371
case.default.370:
  unreachable
case.join.371:
  %t385 = phi ptr [ %t376, %case.end.3.373 ], [ %t384, %case.end.4.381 ]
  call void @__free_recursive(ptr %t366)
  br label %case.end.4.363
case.end.4.363:
  br label %case.join.353
case.default.352:
  unreachable
case.join.353:
  %t386 = phi ptr [ %t358, %case.end.3.355 ], [ %t385, %case.end.4.363 ]
  call void @__free_recursive(ptr %t348)
  br label %case.end.4.345
case.end.4.345:
  br label %case.join.335
case.default.334:
  unreachable
case.join.335:
  %t387 = phi ptr [ %t340, %case.end.3.337 ], [ %t386, %case.end.4.345 ]
  call void @__free_recursive(ptr %t330)
  br label %case.end.4.327
case.end.4.327:
  br label %case.join.317
case.default.316:
  unreachable
case.join.317:
  %t388 = phi ptr [ %t322, %case.end.3.319 ], [ %t387, %case.end.4.327 ]
  call void @__free_recursive(ptr %t312)
  br label %case.end.4.309
case.end.4.309:
  br label %case.join.299
case.default.298:
  unreachable
case.join.299:
  %t389 = phi ptr [ %t304, %case.end.3.301 ], [ %t388, %case.end.4.309 ]
  call void @__free_recursive(ptr %t294)
  br label %case.end.4.291
case.end.4.291:
  br label %case.join.281
case.default.280:
  unreachable
case.join.281:
  %t390 = phi ptr [ %t286, %case.end.3.283 ], [ %t389, %case.end.4.291 ]
  call void @__free_recursive(ptr %t276)
  br label %case.end.4.273
case.end.4.273:
  br label %case.join.263
case.default.262:
  unreachable
case.join.263:
  %t391 = phi ptr [ %t268, %case.end.3.265 ], [ %t390, %case.end.4.273 ]
  call void @__free_recursive(ptr %t258)
  br label %case.end.4.255
case.end.4.255:
  br label %case.join.245
case.default.244:
  unreachable
case.join.245:
  %t392 = phi ptr [ %t250, %case.end.3.247 ], [ %t391, %case.end.4.255 ]
  call void @__free_recursive(ptr %t240)
  br label %case.end.4.237
case.end.4.237:
  br label %case.join.227
case.default.226:
  unreachable
case.join.227:
  %t393 = phi ptr [ %t232, %case.end.3.229 ], [ %t392, %case.end.4.237 ]
  call void @__free_recursive(ptr %t222)
  br label %case.end.4.219
case.end.4.219:
  br label %case.join.209
case.default.208:
  unreachable
case.join.209:
  %t394 = phi ptr [ %t214, %case.end.3.211 ], [ %t393, %case.end.4.219 ]
  call void @__free_recursive(ptr %t204)
  call void @__free_recursive(ptr %t183)
  br label %case.end.4.180
case.end.4.180:
  br label %case.join.170
case.default.169:
  unreachable
case.join.170:
  %t395 = phi ptr [ %t175, %case.end.3.172 ], [ %t394, %case.end.4.180 ]
  call void @__free_recursive(ptr %t165)
  call void @__free_recursive(ptr %t146)
  br label %case.end.4.143
case.end.4.143:
  br label %case.join.133
case.default.132:
  unreachable
case.join.133:
  %t396 = phi ptr [ %t138, %case.end.3.135 ], [ %t395, %case.end.4.143 ]
  call void @__free_recursive(ptr %t128)
  call void @__free_recursive(ptr %t113)
  br label %case.end.4.108
case.end.4.108:
  br label %case.join.98
case.default.97:
  unreachable
case.join.98:
  %t397 = phi ptr [ %t103, %case.end.3.100 ], [ %t396, %case.end.4.108 ]
  call void @__free_recursive(ptr %t93)
  call void @__free_recursive(ptr %t78)
  br label %case.end.4.73
case.end.4.73:
  br label %case.join.63
case.default.62:
  unreachable
case.join.63:
  %t398 = phi ptr [ %t68, %case.end.3.65 ], [ %t397, %case.end.4.73 ]
  call void @__free_recursive(ptr %t58)
  call void @__free_recursive(ptr %t37)
  br label %case.end.4.34
case.end.4.34:
  br label %case.join.24
case.default.23:
  unreachable
case.join.24:
  %t399 = phi ptr [ %t29, %case.end.3.26 ], [ %t398, %case.end.4.34 ]
  call void @__free_recursive(ptr %t19)
  call void @__free_recursive(ptr %t0)
  ret ptr %t399
}

define internal ptr @v_main() {
  %t0 = call ptr @v_res()
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 3, label %case.arm.3.6 i64 4, label %case.arm.4.14 ]
case.arm.3.6:
  %t8 = call ptr @__alloc(i64 16, i32 1)
  %t9 = inttoptr i64 6 to ptr
  %t10 = getelementptr ptr, ptr %t8, i32 0
  store ptr %t9, ptr %t10
  %t11 = getelementptr ptr, ptr %t0, i32 1
  %t12 = load ptr, ptr %t11
  call void @__inc_ref(ptr %t12)
  %t13 = getelementptr ptr, ptr %t8, i32 1
  store ptr %t12, ptr %t13
  br label %case.end.3.7
case.end.3.7:
  br label %case.join.5
case.arm.4.14:
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 5 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = getelementptr ptr, ptr %t0, i32 1
  %t20 = load ptr, ptr %t19
  call void @__inc_ref(ptr %t20)
  %t21 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t20, ptr %t21
  br label %case.end.4.15
case.end.4.15:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t22 = phi ptr [ %t8, %case.end.3.7 ], [ %t16, %case.end.4.15 ]
  call void @__free_recursive(ptr %t0)
  %t23 = call ptr @__alloc(i64 8, i32 0)
  %t24 = inttoptr i64 22 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  %t26 = call ptr @v__cps__df_andThenIO_4(ptr %t22, ptr %t23)
  %t27 = call ptr @__alloc(i64 8, i32 0)
  %t28 = inttoptr i64 20 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  %t30 = call ptr @v__cps__df_handleErrorIO_0(ptr %t26, ptr %t27)
  ret ptr %t30
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.13 i64 7, label %tco.case.arm.7.27 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t12 = call ptr @v__apply__df_handleErrorIO_0(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t12, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.13:
  call void @__inc_ref(ptr %t6)
  %t14 = call ptr @__alloc(i64 24, i32 2)
  %t15 = inttoptr i64 7 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  %t17 = getelementptr ptr, ptr %t14, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t17
  %t18 = call ptr @__alloc(i64 16, i32 1)
  %t19 = inttoptr i64 5 to ptr
  %t20 = getelementptr ptr, ptr %t18, i32 0
  store ptr %t19, ptr %t20
  %t21 = call ptr @__alloc(i64 8, i32 0)
  %t22 = inttoptr i64 0 to ptr
  %t23 = getelementptr ptr, ptr %t21, i32 0
  store ptr %t22, ptr %t23
  %t24 = getelementptr ptr, ptr %t18, i32 1
  store ptr %t21, ptr %t24
  %t25 = getelementptr ptr, ptr %t14, i32 2
  store ptr %t18, ptr %t25
  %t26 = call ptr @v__apply__df_handleErrorIO_0(ptr %t6, ptr %t14)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t26, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.27:
  %t28 = getelementptr ptr, ptr %t5, i32 1
  %t29 = load ptr, ptr %t28
  %t30 = getelementptr ptr, ptr %t5, i32 2
  %t31 = load ptr, ptr %t30
  call void @__inc_ref(ptr %t31)
  %t38 = getelementptr i8, ptr %t5, i64 -8
  %t39 = load i32, ptr %t38
  %t40 = icmp eq i32 %t39, 1
  br i1 %t40, label %reuse.in_place.41, label %reuse.copy.42
reuse.in_place.41:
  %t32 = getelementptr ptr, ptr %t5, i32 2
  %t33 = load ptr, ptr %t32
  call void @__free_recursive(ptr %t33)
  %t36 = inttoptr i64 21 to ptr
  %t37 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t36, ptr %t37
  call void @__inc_ref(ptr %t6)
  %t34 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t34
  %t35 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t29, ptr %t35
  br label %reuse.in_place.end.44
reuse.in_place.end.44:
  br label %reuse.join.43
reuse.copy.42:
  %t46 = call ptr @__alloc(i64 24, i32 2)
  %t47 = inttoptr i64 21 to ptr
  %t48 = getelementptr ptr, ptr %t46, i32 0
  store ptr %t47, ptr %t48
  call void @__inc_ref(ptr %t6)
  %t49 = getelementptr ptr, ptr %t46, i32 1
  store ptr %t6, ptr %t49
  call void @__inc_ref(ptr %t29)
  %t50 = getelementptr ptr, ptr %t46, i32 2
  store ptr %t29, ptr %t50
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.45
reuse.copy.end.45:
  br label %reuse.join.43
reuse.join.43:
  %t51 = phi ptr [ %t5, %reuse.in_place.end.44 ], [ %t46, %reuse.copy.end.45 ]
  call void @__inc_ref(ptr %t31)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t31)
  store ptr %t31, ptr %t3
  store ptr %t51, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t52 = load ptr, ptr %t2
  ret ptr %t52
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
  switch i64 %t9, label %tco.case.default.10 [ i64 20, label %tco.case.arm.20.11 i64 21, label %tco.case.arm.21.12 ]
tco.case.arm.20.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.21.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  %t15 = getelementptr ptr, ptr %t5, i32 2
  %t16 = load ptr, ptr %t15
  %t17 = getelementptr ptr, ptr %t5, i32 1
  %t18 = load ptr, ptr %t17
  call void @__free_recursive(ptr %t18)
  %t21 = inttoptr i64 7 to ptr
  %t22 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t21, ptr %t22
  %t19 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t16, ptr %t19
  call void @__inc_ref(ptr %t6)
  %t20 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t6, ptr %t20
  call void @__inc_ref(ptr %t14)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t14)
  store ptr %t14, ptr %t3
  store ptr %t5, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t23 = load ptr, ptr %t2
  ret ptr %t23
}

define internal ptr @v__cps__df_andThenIO_4(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.27 i64 7, label %tco.case.arm.7.29 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t5, i32 1
  %t16 = load ptr, ptr %t15
  call void @__inc_ref(ptr %t16)
  %t17 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t16, ptr %t17
  %t18 = call ptr @__alloc(i64 16, i32 1)
  %t19 = inttoptr i64 5 to ptr
  %t20 = getelementptr ptr, ptr %t18, i32 0
  store ptr %t19, ptr %t20
  %t21 = call ptr @__alloc(i64 8, i32 0)
  %t22 = inttoptr i64 0 to ptr
  %t23 = getelementptr ptr, ptr %t21, i32 0
  store ptr %t22, ptr %t23
  %t24 = getelementptr ptr, ptr %t18, i32 1
  store ptr %t21, ptr %t24
  %t25 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t18, ptr %t25
  %t26 = call ptr @v__apply__df_andThenIO_4(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t26, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.27:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t28 = call ptr @v__apply__df_andThenIO_4(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t28, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.29:
  %t30 = getelementptr ptr, ptr %t5, i32 1
  %t31 = load ptr, ptr %t30
  %t32 = getelementptr ptr, ptr %t5, i32 2
  %t33 = load ptr, ptr %t32
  call void @__inc_ref(ptr %t33)
  %t40 = getelementptr i8, ptr %t5, i64 -8
  %t41 = load i32, ptr %t40
  %t42 = icmp eq i32 %t41, 1
  br i1 %t42, label %reuse.in_place.43, label %reuse.copy.44
reuse.in_place.43:
  %t34 = getelementptr ptr, ptr %t5, i32 2
  %t35 = load ptr, ptr %t34
  call void @__free_recursive(ptr %t35)
  %t38 = inttoptr i64 23 to ptr
  %t39 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t38, ptr %t39
  call void @__inc_ref(ptr %t6)
  %t36 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t36
  %t37 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t31, ptr %t37
  br label %reuse.in_place.end.46
reuse.in_place.end.46:
  br label %reuse.join.45
reuse.copy.44:
  %t48 = call ptr @__alloc(i64 24, i32 2)
  %t49 = inttoptr i64 23 to ptr
  %t50 = getelementptr ptr, ptr %t48, i32 0
  store ptr %t49, ptr %t50
  call void @__inc_ref(ptr %t6)
  %t51 = getelementptr ptr, ptr %t48, i32 1
  store ptr %t6, ptr %t51
  call void @__inc_ref(ptr %t31)
  %t52 = getelementptr ptr, ptr %t48, i32 2
  store ptr %t31, ptr %t52
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.47
reuse.copy.end.47:
  br label %reuse.join.45
reuse.join.45:
  %t53 = phi ptr [ %t5, %reuse.in_place.end.46 ], [ %t48, %reuse.copy.end.47 ]
  call void @__inc_ref(ptr %t33)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t33)
  store ptr %t33, ptr %t3
  store ptr %t53, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t54 = load ptr, ptr %t2
  ret ptr %t54
}

define internal ptr @v__apply__df_andThenIO_4(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 22, label %tco.case.arm.22.11 i64 23, label %tco.case.arm.23.12 ]
tco.case.arm.22.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.23.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  %t15 = getelementptr ptr, ptr %t5, i32 2
  %t16 = load ptr, ptr %t15
  %t17 = getelementptr ptr, ptr %t5, i32 1
  %t18 = load ptr, ptr %t17
  call void @__free_recursive(ptr %t18)
  %t21 = inttoptr i64 7 to ptr
  %t22 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t21, ptr %t22
  %t19 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t16, ptr %t19
  call void @__inc_ref(ptr %t6)
  %t20 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t6, ptr %t20
  call void @__inc_ref(ptr %t14)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t14)
  store ptr %t14, ptr %t3
  store ptr %t5, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t23 = load ptr, ptr %t2
  ret ptr %t23
}

define i32 @main(i32 %argc, ptr %argv) {
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
