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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [10 x i8]} { i32 0, i32 0, i32 0, i32 10, i32 10, [10 x i8] c"overflow: " }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [13 x i8]} { i32 0, i32 0, i32 0, i32 13, i32 13, [13 x i8] c"OverflowError" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"ok: " }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c", " }

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

define internal ptr @v_main() {
  %v__inl22_scrut.jslot = alloca ptr
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 4 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 4, i32 0)
  store i32 -1, ptr %t3
  %t4 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t4
  %t7 = getelementptr ptr, ptr %t0, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %case.default.10 [ i64 3, label %case.arm.3.12 i64 4, label %case.arm.4.15 ]
case.arm.3.12:
  %t14 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
  br label %case.end.3.13
case.end.3.13:
  br label %case.join.11
case.arm.4.15:
  %t17 = getelementptr ptr, ptr %t0, i32 1
  %t18 = load ptr, ptr %t17
  call void @__inc_ref(ptr %t18)
  %t19 = call ptr @__showUInt32(ptr %t18)
  %t20 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t19)
  br label %case.end.4.16
case.end.4.16:
  br label %case.join.11
case.default.10:
  unreachable
case.join.11:
  %t21 = phi ptr [ %t14, %case.end.3.13 ], [ %t20, %case.end.4.16 ]
  %t22 = getelementptr ptr, ptr %t21, i32 0
  %t23 = load ptr, ptr %t22
  %t24 = ptrtoint ptr %t23 to i64
  switch i64 %t24, label %join.case.default.25 [ i64 3, label %join.case.arm.3.26 i64 4, label %join.case.arm.4.40 ]
join.case.arm.3.26:
  %t27 = call ptr @__alloc(i64 24, i32 2)
  %t28 = inttoptr i64 7 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  %t30 = getelementptr ptr, ptr %t27, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t30
  %t31 = call ptr @__alloc(i64 16, i32 1)
  %t32 = inttoptr i64 5 to ptr
  %t33 = getelementptr ptr, ptr %t31, i32 0
  store ptr %t32, ptr %t33
  %t34 = call ptr @__alloc(i64 8, i32 0)
  %t35 = inttoptr i64 0 to ptr
  %t36 = getelementptr ptr, ptr %t34, i32 0
  store ptr %t35, ptr %t36
  %t37 = getelementptr ptr, ptr %t31, i32 1
  store ptr %t34, ptr %t37
  %t38 = getelementptr ptr, ptr %t27, i32 2
  store ptr %t31, ptr %t38
  call void @__free_recursive(ptr %t21)
  br label %join.val.39
join.val.39:
  br label %join.after.6
join.case.arm.4.40:
  %t41 = getelementptr ptr, ptr %t21, i32 1
  %t42 = load ptr, ptr %t41
  call void @__inc_ref(ptr %t42)
  %t43 = call ptr @__alloc(i64 16, i32 1)
  %t44 = inttoptr i64 3 to ptr
  %t45 = getelementptr ptr, ptr %t43, i32 0
  store ptr %t44, ptr %t45
  %t46 = call ptr @__alloc(i64 8, i32 0)
  %t47 = inttoptr i64 18 to ptr
  %t48 = getelementptr ptr, ptr %t46, i32 0
  store ptr %t47, ptr %t48
  %t49 = getelementptr ptr, ptr %t43, i32 1
  store ptr %t46, ptr %t49
  %t50 = getelementptr ptr, ptr %t43, i32 0
  %t51 = load ptr, ptr %t50
  %t52 = ptrtoint ptr %t51 to i64
  switch i64 %t52, label %case.default.53 [ i64 3, label %case.arm.3.55 i64 4, label %case.arm.4.58 ]
case.arm.3.55:
  %t57 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
  br label %case.end.3.56
case.end.3.56:
  br label %case.join.54
case.arm.4.58:
  %t60 = getelementptr ptr, ptr %t43, i32 1
  %t61 = load ptr, ptr %t60
  call void @__inc_ref(ptr %t61)
  %t62 = call ptr @__showUInt32(ptr %t61)
  %t63 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t62)
  br label %case.end.4.59
case.end.4.59:
  br label %case.join.54
case.default.53:
  unreachable
case.join.54:
  %t64 = phi ptr [ %t57, %case.end.3.56 ], [ %t63, %case.end.4.59 ]
  %t65 = getelementptr ptr, ptr %t64, i32 0
  %t66 = load ptr, ptr %t65
  %t67 = ptrtoint ptr %t66 to i64
  switch i64 %t67, label %case.default.68 [ i64 3, label %case.arm.3.70 i64 4, label %case.arm.4.78 ]
case.arm.3.70:
  %t72 = getelementptr ptr, ptr %t64, i32 1
  %t73 = load ptr, ptr %t72
  call void @__inc_ref(ptr %t73)
  %t74 = call ptr @__alloc(i64 16, i32 1)
  %t75 = inttoptr i64 3 to ptr
  %t76 = getelementptr ptr, ptr %t74, i32 0
  store ptr %t75, ptr %t76
  call void @__inc_ref(ptr %t73)
  %t77 = getelementptr ptr, ptr %t74, i32 1
  store ptr %t73, ptr %t77
  br label %case.end.3.71
case.end.3.71:
  br label %case.join.69
case.arm.4.78:
  %t80 = getelementptr ptr, ptr %t64, i32 1
  %t81 = load ptr, ptr %t80
  call void @__inc_ref(ptr %t81)
  %t82 = call ptr @v_maxUInt32()
  %t83 = call ptr @v_maxUInt32()
  %t84 = call ptr @__mulUInt32(ptr %t82, ptr %t83)
  %t85 = getelementptr ptr, ptr %t84, i32 0
  %t86 = load ptr, ptr %t85
  %t87 = ptrtoint ptr %t86 to i64
  switch i64 %t87, label %case.default.88 [ i64 3, label %case.arm.3.90 i64 4, label %case.arm.4.93 ]
case.arm.3.90:
  %t92 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
  br label %case.end.3.91
case.end.3.91:
  br label %case.join.89
case.arm.4.93:
  %t95 = getelementptr ptr, ptr %t84, i32 1
  %t96 = load ptr, ptr %t95
  call void @__inc_ref(ptr %t96)
  %t97 = call ptr @__showUInt32(ptr %t96)
  %t98 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t97)
  br label %case.end.4.94
case.end.4.94:
  br label %case.join.89
case.default.88:
  unreachable
case.join.89:
  %t99 = phi ptr [ %t92, %case.end.3.91 ], [ %t98, %case.end.4.94 ]
  %t100 = getelementptr ptr, ptr %t99, i32 0
  %t101 = load ptr, ptr %t100
  %t102 = ptrtoint ptr %t101 to i64
  switch i64 %t102, label %case.default.103 [ i64 3, label %case.arm.3.105 i64 4, label %case.arm.4.113 ]
case.arm.3.105:
  %t107 = getelementptr ptr, ptr %t99, i32 1
  %t108 = load ptr, ptr %t107
  call void @__inc_ref(ptr %t108)
  %t109 = call ptr @__alloc(i64 16, i32 1)
  %t110 = inttoptr i64 3 to ptr
  %t111 = getelementptr ptr, ptr %t109, i32 0
  store ptr %t110, ptr %t111
  call void @__inc_ref(ptr %t108)
  %t112 = getelementptr ptr, ptr %t109, i32 1
  store ptr %t108, ptr %t112
  br label %case.end.3.106
case.end.3.106:
  br label %case.join.104
case.arm.4.113:
  %t115 = getelementptr ptr, ptr %t99, i32 1
  %t116 = load ptr, ptr %t115
  call void @__inc_ref(ptr %t116)
  %t117 = call ptr @v_minUInt32()
  %t118 = call ptr @v_maxUInt32()
  %t119 = call ptr @__mulUInt32(ptr %t117, ptr %t118)
  %t120 = getelementptr ptr, ptr %t119, i32 0
  %t121 = load ptr, ptr %t120
  %t122 = ptrtoint ptr %t121 to i64
  switch i64 %t122, label %case.default.123 [ i64 3, label %case.arm.3.125 i64 4, label %case.arm.4.128 ]
case.arm.3.125:
  %t127 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
  br label %case.end.3.126
case.end.3.126:
  br label %case.join.124
case.arm.4.128:
  %t130 = getelementptr ptr, ptr %t119, i32 1
  %t131 = load ptr, ptr %t130
  call void @__inc_ref(ptr %t131)
  %t132 = call ptr @__showUInt32(ptr %t131)
  %t133 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t132)
  br label %case.end.4.129
case.end.4.129:
  br label %case.join.124
case.default.123:
  unreachable
case.join.124:
  %t134 = phi ptr [ %t127, %case.end.3.126 ], [ %t133, %case.end.4.129 ]
  %t135 = getelementptr ptr, ptr %t134, i32 0
  %t136 = load ptr, ptr %t135
  %t137 = ptrtoint ptr %t136 to i64
  switch i64 %t137, label %case.default.138 [ i64 3, label %case.arm.3.140 i64 4, label %case.arm.4.148 ]
case.arm.3.140:
  %t142 = getelementptr ptr, ptr %t134, i32 1
  %t143 = load ptr, ptr %t142
  call void @__inc_ref(ptr %t143)
  %t144 = call ptr @__alloc(i64 16, i32 1)
  %t145 = inttoptr i64 3 to ptr
  %t146 = getelementptr ptr, ptr %t144, i32 0
  store ptr %t145, ptr %t146
  call void @__inc_ref(ptr %t143)
  %t147 = getelementptr ptr, ptr %t144, i32 1
  store ptr %t143, ptr %t147
  br label %case.end.3.141
case.end.3.141:
  br label %case.join.139
case.arm.4.148:
  %t150 = getelementptr ptr, ptr %t134, i32 1
  %t151 = load ptr, ptr %t150
  call void @__inc_ref(ptr %t151)
  %t152 = call ptr @__alloc(i64 16, i32 1)
  %t153 = inttoptr i64 4 to ptr
  %t154 = getelementptr ptr, ptr %t152, i32 0
  store ptr %t153, ptr %t154
  %t155 = call ptr @__alloc(i64 4, i32 0)
  store i32 -2147483648, ptr %t155
  %t156 = getelementptr ptr, ptr %t152, i32 1
  store ptr %t155, ptr %t156
  %t157 = getelementptr ptr, ptr %t152, i32 0
  %t158 = load ptr, ptr %t157
  %t159 = ptrtoint ptr %t158 to i64
  switch i64 %t159, label %case.default.160 [ i64 3, label %case.arm.3.162 i64 4, label %case.arm.4.165 ]
case.arm.3.162:
  %t164 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
  br label %case.end.3.163
case.end.3.163:
  br label %case.join.161
case.arm.4.165:
  %t167 = getelementptr ptr, ptr %t152, i32 1
  %t168 = load ptr, ptr %t167
  call void @__inc_ref(ptr %t168)
  %t169 = call ptr @__showUInt32(ptr %t168)
  %t170 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t169)
  br label %case.end.4.166
case.end.4.166:
  br label %case.join.161
case.default.160:
  unreachable
case.join.161:
  %t171 = phi ptr [ %t164, %case.end.3.163 ], [ %t170, %case.end.4.166 ]
  %t172 = getelementptr ptr, ptr %t171, i32 0
  %t173 = load ptr, ptr %t172
  %t174 = ptrtoint ptr %t173 to i64
  switch i64 %t174, label %case.default.175 [ i64 3, label %case.arm.3.177 i64 4, label %case.arm.4.185 ]
case.arm.3.177:
  %t179 = getelementptr ptr, ptr %t171, i32 1
  %t180 = load ptr, ptr %t179
  call void @__inc_ref(ptr %t180)
  %t181 = call ptr @__alloc(i64 16, i32 1)
  %t182 = inttoptr i64 3 to ptr
  %t183 = getelementptr ptr, ptr %t181, i32 0
  store ptr %t182, ptr %t183
  call void @__inc_ref(ptr %t180)
  %t184 = getelementptr ptr, ptr %t181, i32 1
  store ptr %t180, ptr %t184
  br label %case.end.3.178
case.end.3.178:
  br label %case.join.176
case.arm.4.185:
  %t187 = getelementptr ptr, ptr %t171, i32 1
  %t188 = load ptr, ptr %t187
  call void @__inc_ref(ptr %t188)
  %t189 = call ptr @__alloc(i64 16, i32 1)
  %t190 = inttoptr i64 3 to ptr
  %t191 = getelementptr ptr, ptr %t189, i32 0
  store ptr %t190, ptr %t191
  %t192 = call ptr @__alloc(i64 8, i32 0)
  %t193 = inttoptr i64 18 to ptr
  %t194 = getelementptr ptr, ptr %t192, i32 0
  store ptr %t193, ptr %t194
  %t195 = getelementptr ptr, ptr %t189, i32 1
  store ptr %t192, ptr %t195
  %t196 = getelementptr ptr, ptr %t189, i32 0
  %t197 = load ptr, ptr %t196
  %t198 = ptrtoint ptr %t197 to i64
  switch i64 %t198, label %case.default.199 [ i64 3, label %case.arm.3.201 i64 4, label %case.arm.4.204 ]
case.arm.3.201:
  %t203 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
  br label %case.end.3.202
case.end.3.202:
  br label %case.join.200
case.arm.4.204:
  %t206 = getelementptr ptr, ptr %t189, i32 1
  %t207 = load ptr, ptr %t206
  call void @__inc_ref(ptr %t207)
  %t208 = call ptr @__showUInt32(ptr %t207)
  %t209 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t208)
  br label %case.end.4.205
case.end.4.205:
  br label %case.join.200
case.default.199:
  unreachable
case.join.200:
  %t210 = phi ptr [ %t203, %case.end.3.202 ], [ %t209, %case.end.4.205 ]
  %t211 = getelementptr ptr, ptr %t210, i32 0
  %t212 = load ptr, ptr %t211
  %t213 = ptrtoint ptr %t212 to i64
  switch i64 %t213, label %case.default.214 [ i64 3, label %case.arm.3.216 i64 4, label %case.arm.4.224 ]
case.arm.3.216:
  %t218 = getelementptr ptr, ptr %t210, i32 1
  %t219 = load ptr, ptr %t218
  call void @__inc_ref(ptr %t219)
  %t220 = call ptr @__alloc(i64 16, i32 1)
  %t221 = inttoptr i64 3 to ptr
  %t222 = getelementptr ptr, ptr %t220, i32 0
  store ptr %t221, ptr %t222
  call void @__inc_ref(ptr %t219)
  %t223 = getelementptr ptr, ptr %t220, i32 1
  store ptr %t219, ptr %t223
  br label %case.end.3.217
case.end.3.217:
  br label %case.join.215
case.arm.4.224:
  %t226 = getelementptr ptr, ptr %t210, i32 1
  %t227 = load ptr, ptr %t226
  call void @__inc_ref(ptr %t227)
  call void @__inc_ref(ptr %t42)
  %t228 = call ptr @__concat(ptr %t42, ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  %t229 = getelementptr ptr, ptr %t228, i32 0
  %t230 = load ptr, ptr %t229
  %t231 = ptrtoint ptr %t230 to i64
  switch i64 %t231, label %case.default.232 [ i64 3, label %case.arm.3.234 i64 4, label %case.arm.4.242 ]
case.arm.3.234:
  %t236 = getelementptr ptr, ptr %t228, i32 1
  %t237 = load ptr, ptr %t236
  call void @__inc_ref(ptr %t237)
  %t238 = call ptr @__alloc(i64 16, i32 1)
  %t239 = inttoptr i64 3 to ptr
  %t240 = getelementptr ptr, ptr %t238, i32 0
  store ptr %t239, ptr %t240
  call void @__inc_ref(ptr %t237)
  %t241 = getelementptr ptr, ptr %t238, i32 1
  store ptr %t237, ptr %t241
  br label %case.end.3.235
case.end.3.235:
  br label %case.join.233
case.arm.4.242:
  %t244 = getelementptr ptr, ptr %t228, i32 1
  %t245 = load ptr, ptr %t244
  call void @__inc_ref(ptr %t245)
  call void @__inc_ref(ptr %t245)
  call void @__inc_ref(ptr %t81)
  %t246 = call ptr @__concat(ptr %t245, ptr %t81)
  %t247 = getelementptr ptr, ptr %t246, i32 0
  %t248 = load ptr, ptr %t247
  %t249 = ptrtoint ptr %t248 to i64
  switch i64 %t249, label %case.default.250 [ i64 3, label %case.arm.3.252 i64 4, label %case.arm.4.260 ]
case.arm.3.252:
  %t254 = getelementptr ptr, ptr %t246, i32 1
  %t255 = load ptr, ptr %t254
  call void @__inc_ref(ptr %t255)
  %t256 = call ptr @__alloc(i64 16, i32 1)
  %t257 = inttoptr i64 3 to ptr
  %t258 = getelementptr ptr, ptr %t256, i32 0
  store ptr %t257, ptr %t258
  call void @__inc_ref(ptr %t255)
  %t259 = getelementptr ptr, ptr %t256, i32 1
  store ptr %t255, ptr %t259
  br label %case.end.3.253
case.end.3.253:
  br label %case.join.251
case.arm.4.260:
  %t262 = getelementptr ptr, ptr %t246, i32 1
  %t263 = load ptr, ptr %t262
  call void @__inc_ref(ptr %t263)
  call void @__inc_ref(ptr %t263)
  %t264 = call ptr @__concat(ptr %t263, ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  %t265 = getelementptr ptr, ptr %t264, i32 0
  %t266 = load ptr, ptr %t265
  %t267 = ptrtoint ptr %t266 to i64
  switch i64 %t267, label %case.default.268 [ i64 3, label %case.arm.3.270 i64 4, label %case.arm.4.278 ]
case.arm.3.270:
  %t272 = getelementptr ptr, ptr %t264, i32 1
  %t273 = load ptr, ptr %t272
  call void @__inc_ref(ptr %t273)
  %t274 = call ptr @__alloc(i64 16, i32 1)
  %t275 = inttoptr i64 3 to ptr
  %t276 = getelementptr ptr, ptr %t274, i32 0
  store ptr %t275, ptr %t276
  call void @__inc_ref(ptr %t273)
  %t277 = getelementptr ptr, ptr %t274, i32 1
  store ptr %t273, ptr %t277
  br label %case.end.3.271
case.end.3.271:
  br label %case.join.269
case.arm.4.278:
  %t280 = getelementptr ptr, ptr %t264, i32 1
  %t281 = load ptr, ptr %t280
  call void @__inc_ref(ptr %t281)
  call void @__inc_ref(ptr %t281)
  call void @__inc_ref(ptr %t116)
  %t282 = call ptr @__concat(ptr %t281, ptr %t116)
  %t283 = getelementptr ptr, ptr %t282, i32 0
  %t284 = load ptr, ptr %t283
  %t285 = ptrtoint ptr %t284 to i64
  switch i64 %t285, label %case.default.286 [ i64 3, label %case.arm.3.288 i64 4, label %case.arm.4.296 ]
case.arm.3.288:
  %t290 = getelementptr ptr, ptr %t282, i32 1
  %t291 = load ptr, ptr %t290
  call void @__inc_ref(ptr %t291)
  %t292 = call ptr @__alloc(i64 16, i32 1)
  %t293 = inttoptr i64 3 to ptr
  %t294 = getelementptr ptr, ptr %t292, i32 0
  store ptr %t293, ptr %t294
  call void @__inc_ref(ptr %t291)
  %t295 = getelementptr ptr, ptr %t292, i32 1
  store ptr %t291, ptr %t295
  br label %case.end.3.289
case.end.3.289:
  br label %case.join.287
case.arm.4.296:
  %t298 = getelementptr ptr, ptr %t282, i32 1
  %t299 = load ptr, ptr %t298
  call void @__inc_ref(ptr %t299)
  call void @__inc_ref(ptr %t299)
  %t300 = call ptr @__concat(ptr %t299, ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  %t301 = getelementptr ptr, ptr %t300, i32 0
  %t302 = load ptr, ptr %t301
  %t303 = ptrtoint ptr %t302 to i64
  switch i64 %t303, label %case.default.304 [ i64 3, label %case.arm.3.306 i64 4, label %case.arm.4.314 ]
case.arm.3.306:
  %t308 = getelementptr ptr, ptr %t300, i32 1
  %t309 = load ptr, ptr %t308
  call void @__inc_ref(ptr %t309)
  %t310 = call ptr @__alloc(i64 16, i32 1)
  %t311 = inttoptr i64 3 to ptr
  %t312 = getelementptr ptr, ptr %t310, i32 0
  store ptr %t311, ptr %t312
  call void @__inc_ref(ptr %t309)
  %t313 = getelementptr ptr, ptr %t310, i32 1
  store ptr %t309, ptr %t313
  br label %case.end.3.307
case.end.3.307:
  br label %case.join.305
case.arm.4.314:
  %t316 = getelementptr ptr, ptr %t300, i32 1
  %t317 = load ptr, ptr %t316
  call void @__inc_ref(ptr %t317)
  call void @__inc_ref(ptr %t317)
  call void @__inc_ref(ptr %t151)
  %t318 = call ptr @__concat(ptr %t317, ptr %t151)
  %t319 = getelementptr ptr, ptr %t318, i32 0
  %t320 = load ptr, ptr %t319
  %t321 = ptrtoint ptr %t320 to i64
  switch i64 %t321, label %case.default.322 [ i64 3, label %case.arm.3.324 i64 4, label %case.arm.4.332 ]
case.arm.3.324:
  %t326 = getelementptr ptr, ptr %t318, i32 1
  %t327 = load ptr, ptr %t326
  call void @__inc_ref(ptr %t327)
  %t328 = call ptr @__alloc(i64 16, i32 1)
  %t329 = inttoptr i64 3 to ptr
  %t330 = getelementptr ptr, ptr %t328, i32 0
  store ptr %t329, ptr %t330
  call void @__inc_ref(ptr %t327)
  %t331 = getelementptr ptr, ptr %t328, i32 1
  store ptr %t327, ptr %t331
  br label %case.end.3.325
case.end.3.325:
  br label %case.join.323
case.arm.4.332:
  %t334 = getelementptr ptr, ptr %t318, i32 1
  %t335 = load ptr, ptr %t334
  call void @__inc_ref(ptr %t335)
  call void @__inc_ref(ptr %t335)
  %t336 = call ptr @__concat(ptr %t335, ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  %t337 = getelementptr ptr, ptr %t336, i32 0
  %t338 = load ptr, ptr %t337
  %t339 = ptrtoint ptr %t338 to i64
  switch i64 %t339, label %case.default.340 [ i64 3, label %case.arm.3.342 i64 4, label %case.arm.4.350 ]
case.arm.3.342:
  %t344 = getelementptr ptr, ptr %t336, i32 1
  %t345 = load ptr, ptr %t344
  call void @__inc_ref(ptr %t345)
  %t346 = call ptr @__alloc(i64 16, i32 1)
  %t347 = inttoptr i64 3 to ptr
  %t348 = getelementptr ptr, ptr %t346, i32 0
  store ptr %t347, ptr %t348
  call void @__inc_ref(ptr %t345)
  %t349 = getelementptr ptr, ptr %t346, i32 1
  store ptr %t345, ptr %t349
  br label %case.end.3.343
case.end.3.343:
  br label %case.join.341
case.arm.4.350:
  %t352 = getelementptr ptr, ptr %t336, i32 1
  %t353 = load ptr, ptr %t352
  call void @__inc_ref(ptr %t353)
  call void @__inc_ref(ptr %t353)
  call void @__inc_ref(ptr %t188)
  %t354 = call ptr @__concat(ptr %t353, ptr %t188)
  %t355 = getelementptr ptr, ptr %t354, i32 0
  %t356 = load ptr, ptr %t355
  %t357 = ptrtoint ptr %t356 to i64
  switch i64 %t357, label %case.default.358 [ i64 3, label %case.arm.3.360 i64 4, label %case.arm.4.368 ]
case.arm.3.360:
  %t362 = getelementptr ptr, ptr %t354, i32 1
  %t363 = load ptr, ptr %t362
  call void @__inc_ref(ptr %t363)
  %t364 = call ptr @__alloc(i64 16, i32 1)
  %t365 = inttoptr i64 3 to ptr
  %t366 = getelementptr ptr, ptr %t364, i32 0
  store ptr %t365, ptr %t366
  call void @__inc_ref(ptr %t363)
  %t367 = getelementptr ptr, ptr %t364, i32 1
  store ptr %t363, ptr %t367
  br label %case.end.3.361
case.end.3.361:
  br label %case.join.359
case.arm.4.368:
  %t370 = getelementptr ptr, ptr %t354, i32 1
  %t371 = load ptr, ptr %t370
  call void @__inc_ref(ptr %t371)
  call void @__inc_ref(ptr %t371)
  %t372 = call ptr @__concat(ptr %t371, ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  %t373 = getelementptr ptr, ptr %t372, i32 0
  %t374 = load ptr, ptr %t373
  %t375 = ptrtoint ptr %t374 to i64
  switch i64 %t375, label %case.default.376 [ i64 3, label %case.arm.3.378 i64 4, label %case.arm.4.386 ]
case.arm.3.378:
  %t380 = getelementptr ptr, ptr %t372, i32 1
  %t381 = load ptr, ptr %t380
  call void @__inc_ref(ptr %t381)
  %t382 = call ptr @__alloc(i64 16, i32 1)
  %t383 = inttoptr i64 3 to ptr
  %t384 = getelementptr ptr, ptr %t382, i32 0
  store ptr %t383, ptr %t384
  call void @__inc_ref(ptr %t381)
  %t385 = getelementptr ptr, ptr %t382, i32 1
  store ptr %t381, ptr %t385
  br label %case.end.3.379
case.end.3.379:
  br label %case.join.377
case.arm.4.386:
  %t388 = getelementptr ptr, ptr %t372, i32 1
  %t389 = load ptr, ptr %t388
  call void @__inc_ref(ptr %t389)
  call void @__inc_ref(ptr %t389)
  call void @__inc_ref(ptr %t227)
  %t390 = call ptr @__concat(ptr %t389, ptr %t227)
  br label %case.end.4.387
case.end.4.387:
  br label %case.join.377
case.default.376:
  unreachable
case.join.377:
  %t391 = phi ptr [ %t382, %case.end.3.379 ], [ %t390, %case.end.4.387 ]
  call void @__free_recursive(ptr %t372)
  br label %case.end.4.369
case.end.4.369:
  br label %case.join.359
case.default.358:
  unreachable
case.join.359:
  %t392 = phi ptr [ %t364, %case.end.3.361 ], [ %t391, %case.end.4.369 ]
  call void @__free_recursive(ptr %t354)
  br label %case.end.4.351
case.end.4.351:
  br label %case.join.341
case.default.340:
  unreachable
case.join.341:
  %t393 = phi ptr [ %t346, %case.end.3.343 ], [ %t392, %case.end.4.351 ]
  call void @__free_recursive(ptr %t336)
  br label %case.end.4.333
case.end.4.333:
  br label %case.join.323
case.default.322:
  unreachable
case.join.323:
  %t394 = phi ptr [ %t328, %case.end.3.325 ], [ %t393, %case.end.4.333 ]
  call void @__free_recursive(ptr %t318)
  br label %case.end.4.315
case.end.4.315:
  br label %case.join.305
case.default.304:
  unreachable
case.join.305:
  %t395 = phi ptr [ %t310, %case.end.3.307 ], [ %t394, %case.end.4.315 ]
  call void @__free_recursive(ptr %t300)
  br label %case.end.4.297
case.end.4.297:
  br label %case.join.287
case.default.286:
  unreachable
case.join.287:
  %t396 = phi ptr [ %t292, %case.end.3.289 ], [ %t395, %case.end.4.297 ]
  call void @__free_recursive(ptr %t282)
  br label %case.end.4.279
case.end.4.279:
  br label %case.join.269
case.default.268:
  unreachable
case.join.269:
  %t397 = phi ptr [ %t274, %case.end.3.271 ], [ %t396, %case.end.4.279 ]
  call void @__free_recursive(ptr %t264)
  br label %case.end.4.261
case.end.4.261:
  br label %case.join.251
case.default.250:
  unreachable
case.join.251:
  %t398 = phi ptr [ %t256, %case.end.3.253 ], [ %t397, %case.end.4.261 ]
  call void @__free_recursive(ptr %t246)
  br label %case.end.4.243
case.end.4.243:
  br label %case.join.233
case.default.232:
  unreachable
case.join.233:
  %t399 = phi ptr [ %t238, %case.end.3.235 ], [ %t398, %case.end.4.243 ]
  call void @__free_recursive(ptr %t228)
  br label %case.end.4.225
case.end.4.225:
  br label %case.join.215
case.default.214:
  unreachable
case.join.215:
  %t400 = phi ptr [ %t220, %case.end.3.217 ], [ %t399, %case.end.4.225 ]
  call void @__free_recursive(ptr %t210)
  call void @__free_recursive(ptr %t189)
  br label %case.end.4.186
case.end.4.186:
  br label %case.join.176
case.default.175:
  unreachable
case.join.176:
  %t401 = phi ptr [ %t181, %case.end.3.178 ], [ %t400, %case.end.4.186 ]
  call void @__free_recursive(ptr %t171)
  call void @__free_recursive(ptr %t152)
  br label %case.end.4.149
case.end.4.149:
  br label %case.join.139
case.default.138:
  unreachable
case.join.139:
  %t402 = phi ptr [ %t144, %case.end.3.141 ], [ %t401, %case.end.4.149 ]
  call void @__free_recursive(ptr %t134)
  call void @__free_recursive(ptr %t119)
  br label %case.end.4.114
case.end.4.114:
  br label %case.join.104
case.default.103:
  unreachable
case.join.104:
  %t403 = phi ptr [ %t109, %case.end.3.106 ], [ %t402, %case.end.4.114 ]
  call void @__free_recursive(ptr %t99)
  call void @__free_recursive(ptr %t84)
  br label %case.end.4.79
case.end.4.79:
  br label %case.join.69
case.default.68:
  unreachable
case.join.69:
  %t404 = phi ptr [ %t74, %case.end.3.71 ], [ %t403, %case.end.4.79 ]
  call void @__free_recursive(ptr %t64)
  call void @__free_recursive(ptr %t43)
  call void @__free_recursive(ptr %t21)
  store ptr %t404, ptr %v__inl22_scrut.jslot
  br label %join.5
join.case.default.25:
  unreachable
join.5:
  %t405 = load ptr, ptr %v__inl22_scrut.jslot
  %t406 = getelementptr ptr, ptr %t405, i32 0
  %t407 = load ptr, ptr %t406
  %t408 = ptrtoint ptr %t407 to i64
  switch i64 %t408, label %case.default.409 [ i64 3, label %case.arm.3.411 i64 4, label %case.arm.4.425 ]
case.arm.3.411:
  %t413 = call ptr @__alloc(i64 24, i32 2)
  %t414 = inttoptr i64 7 to ptr
  %t415 = getelementptr ptr, ptr %t413, i32 0
  store ptr %t414, ptr %t415
  %t416 = getelementptr ptr, ptr %t413, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t416
  %t417 = call ptr @__alloc(i64 16, i32 1)
  %t418 = inttoptr i64 5 to ptr
  %t419 = getelementptr ptr, ptr %t417, i32 0
  store ptr %t418, ptr %t419
  %t420 = call ptr @__alloc(i64 8, i32 0)
  %t421 = inttoptr i64 0 to ptr
  %t422 = getelementptr ptr, ptr %t420, i32 0
  store ptr %t421, ptr %t422
  %t423 = getelementptr ptr, ptr %t417, i32 1
  store ptr %t420, ptr %t423
  %t424 = getelementptr ptr, ptr %t413, i32 2
  store ptr %t417, ptr %t424
  br label %case.end.3.412
case.end.3.412:
  br label %case.join.410
case.arm.4.425:
  %t427 = call ptr @__alloc(i64 24, i32 2)
  %t428 = inttoptr i64 7 to ptr
  %t429 = getelementptr ptr, ptr %t427, i32 0
  store ptr %t428, ptr %t429
  %t430 = getelementptr ptr, ptr %t405, i32 1
  %t431 = load ptr, ptr %t430
  call void @__inc_ref(ptr %t431)
  %t432 = getelementptr ptr, ptr %t427, i32 1
  store ptr %t431, ptr %t432
  %t433 = call ptr @__alloc(i64 16, i32 1)
  %t434 = inttoptr i64 5 to ptr
  %t435 = getelementptr ptr, ptr %t433, i32 0
  store ptr %t434, ptr %t435
  %t436 = call ptr @__alloc(i64 8, i32 0)
  %t437 = inttoptr i64 0 to ptr
  %t438 = getelementptr ptr, ptr %t436, i32 0
  store ptr %t437, ptr %t438
  %t439 = getelementptr ptr, ptr %t433, i32 1
  store ptr %t436, ptr %t439
  %t440 = getelementptr ptr, ptr %t427, i32 2
  store ptr %t433, ptr %t440
  br label %case.end.4.426
case.end.4.426:
  br label %case.join.410
case.default.409:
  unreachable
case.join.410:
  %t441 = phi ptr [ %t413, %case.end.3.412 ], [ %t427, %case.end.4.426 ]
  call void @__free_recursive(ptr %t405)
  br label %join.end.442
join.end.442:
  br label %join.after.6
join.after.6:
  %t443 = phi ptr [ %t27, %join.val.39 ], [ %t441, %join.end.442 ]
  call void @__free_recursive(ptr %t0)
  ret ptr %t443
}

declare i32 @_setmode(i32, i32)

define i32 @main(i32 %argc_posix, ptr %argv_posix) {
entry:
  call i32 @_setmode(i32 1, i32 32768)
  call i32 @_setmode(i32 0, i32 32768)
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
