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
  %oe_tag = inttoptr i64 18 to ptr
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

define internal ptr @v_main() {
  %v__inl19_scrut.jslot = alloca ptr
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 4 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 1, i32 0)
  store i8 255, ptr %t3
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
  %t19 = call ptr @__showUInt8(ptr %t18)
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
  %t62 = call ptr @__showUInt8(ptr %t61)
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
  %t82 = call ptr @v_maxUInt8()
  %t83 = call ptr @v_maxUInt8()
  %t84 = call ptr @__mulUInt8(ptr %t82, ptr %t83)
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
  %t97 = call ptr @__showUInt8(ptr %t96)
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
  %t117 = call ptr @v_minUInt8()
  %t118 = call ptr @__alloc(i64 1, i32 0)
  store i8 200, ptr %t118
  %t119 = call ptr @__mulUInt8(ptr %t117, ptr %t118)
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
  %t132 = call ptr @__showUInt8(ptr %t131)
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
  %t155 = call ptr @__alloc(i64 1, i32 0)
  store i8 200, ptr %t155
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
  %t169 = call ptr @__showUInt8(ptr %t168)
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
  call void @__inc_ref(ptr %t42)
  %t189 = call ptr @__concat(ptr %t42, ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  %t190 = getelementptr ptr, ptr %t189, i32 0
  %t191 = load ptr, ptr %t190
  %t192 = ptrtoint ptr %t191 to i64
  switch i64 %t192, label %case.default.193 [ i64 3, label %case.arm.3.195 i64 4, label %case.arm.4.203 ]
case.arm.3.195:
  %t197 = getelementptr ptr, ptr %t189, i32 1
  %t198 = load ptr, ptr %t197
  call void @__inc_ref(ptr %t198)
  %t199 = call ptr @__alloc(i64 16, i32 1)
  %t200 = inttoptr i64 3 to ptr
  %t201 = getelementptr ptr, ptr %t199, i32 0
  store ptr %t200, ptr %t201
  call void @__inc_ref(ptr %t198)
  %t202 = getelementptr ptr, ptr %t199, i32 1
  store ptr %t198, ptr %t202
  br label %case.end.3.196
case.end.3.196:
  br label %case.join.194
case.arm.4.203:
  %t205 = getelementptr ptr, ptr %t189, i32 1
  %t206 = load ptr, ptr %t205
  call void @__inc_ref(ptr %t206)
  call void @__inc_ref(ptr %t206)
  call void @__inc_ref(ptr %t81)
  %t207 = call ptr @__concat(ptr %t206, ptr %t81)
  %t208 = getelementptr ptr, ptr %t207, i32 0
  %t209 = load ptr, ptr %t208
  %t210 = ptrtoint ptr %t209 to i64
  switch i64 %t210, label %case.default.211 [ i64 3, label %case.arm.3.213 i64 4, label %case.arm.4.221 ]
case.arm.3.213:
  %t215 = getelementptr ptr, ptr %t207, i32 1
  %t216 = load ptr, ptr %t215
  call void @__inc_ref(ptr %t216)
  %t217 = call ptr @__alloc(i64 16, i32 1)
  %t218 = inttoptr i64 3 to ptr
  %t219 = getelementptr ptr, ptr %t217, i32 0
  store ptr %t218, ptr %t219
  call void @__inc_ref(ptr %t216)
  %t220 = getelementptr ptr, ptr %t217, i32 1
  store ptr %t216, ptr %t220
  br label %case.end.3.214
case.end.3.214:
  br label %case.join.212
case.arm.4.221:
  %t223 = getelementptr ptr, ptr %t207, i32 1
  %t224 = load ptr, ptr %t223
  call void @__inc_ref(ptr %t224)
  call void @__inc_ref(ptr %t224)
  %t225 = call ptr @__concat(ptr %t224, ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  %t226 = getelementptr ptr, ptr %t225, i32 0
  %t227 = load ptr, ptr %t226
  %t228 = ptrtoint ptr %t227 to i64
  switch i64 %t228, label %case.default.229 [ i64 3, label %case.arm.3.231 i64 4, label %case.arm.4.239 ]
case.arm.3.231:
  %t233 = getelementptr ptr, ptr %t225, i32 1
  %t234 = load ptr, ptr %t233
  call void @__inc_ref(ptr %t234)
  %t235 = call ptr @__alloc(i64 16, i32 1)
  %t236 = inttoptr i64 3 to ptr
  %t237 = getelementptr ptr, ptr %t235, i32 0
  store ptr %t236, ptr %t237
  call void @__inc_ref(ptr %t234)
  %t238 = getelementptr ptr, ptr %t235, i32 1
  store ptr %t234, ptr %t238
  br label %case.end.3.232
case.end.3.232:
  br label %case.join.230
case.arm.4.239:
  %t241 = getelementptr ptr, ptr %t225, i32 1
  %t242 = load ptr, ptr %t241
  call void @__inc_ref(ptr %t242)
  call void @__inc_ref(ptr %t242)
  call void @__inc_ref(ptr %t116)
  %t243 = call ptr @__concat(ptr %t242, ptr %t116)
  %t244 = getelementptr ptr, ptr %t243, i32 0
  %t245 = load ptr, ptr %t244
  %t246 = ptrtoint ptr %t245 to i64
  switch i64 %t246, label %case.default.247 [ i64 3, label %case.arm.3.249 i64 4, label %case.arm.4.257 ]
case.arm.3.249:
  %t251 = getelementptr ptr, ptr %t243, i32 1
  %t252 = load ptr, ptr %t251
  call void @__inc_ref(ptr %t252)
  %t253 = call ptr @__alloc(i64 16, i32 1)
  %t254 = inttoptr i64 3 to ptr
  %t255 = getelementptr ptr, ptr %t253, i32 0
  store ptr %t254, ptr %t255
  call void @__inc_ref(ptr %t252)
  %t256 = getelementptr ptr, ptr %t253, i32 1
  store ptr %t252, ptr %t256
  br label %case.end.3.250
case.end.3.250:
  br label %case.join.248
case.arm.4.257:
  %t259 = getelementptr ptr, ptr %t243, i32 1
  %t260 = load ptr, ptr %t259
  call void @__inc_ref(ptr %t260)
  call void @__inc_ref(ptr %t260)
  %t261 = call ptr @__concat(ptr %t260, ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  %t262 = getelementptr ptr, ptr %t261, i32 0
  %t263 = load ptr, ptr %t262
  %t264 = ptrtoint ptr %t263 to i64
  switch i64 %t264, label %case.default.265 [ i64 3, label %case.arm.3.267 i64 4, label %case.arm.4.275 ]
case.arm.3.267:
  %t269 = getelementptr ptr, ptr %t261, i32 1
  %t270 = load ptr, ptr %t269
  call void @__inc_ref(ptr %t270)
  %t271 = call ptr @__alloc(i64 16, i32 1)
  %t272 = inttoptr i64 3 to ptr
  %t273 = getelementptr ptr, ptr %t271, i32 0
  store ptr %t272, ptr %t273
  call void @__inc_ref(ptr %t270)
  %t274 = getelementptr ptr, ptr %t271, i32 1
  store ptr %t270, ptr %t274
  br label %case.end.3.268
case.end.3.268:
  br label %case.join.266
case.arm.4.275:
  %t277 = getelementptr ptr, ptr %t261, i32 1
  %t278 = load ptr, ptr %t277
  call void @__inc_ref(ptr %t278)
  call void @__inc_ref(ptr %t278)
  call void @__inc_ref(ptr %t151)
  %t279 = call ptr @__concat(ptr %t278, ptr %t151)
  %t280 = getelementptr ptr, ptr %t279, i32 0
  %t281 = load ptr, ptr %t280
  %t282 = ptrtoint ptr %t281 to i64
  switch i64 %t282, label %case.default.283 [ i64 3, label %case.arm.3.285 i64 4, label %case.arm.4.293 ]
case.arm.3.285:
  %t287 = getelementptr ptr, ptr %t279, i32 1
  %t288 = load ptr, ptr %t287
  call void @__inc_ref(ptr %t288)
  %t289 = call ptr @__alloc(i64 16, i32 1)
  %t290 = inttoptr i64 3 to ptr
  %t291 = getelementptr ptr, ptr %t289, i32 0
  store ptr %t290, ptr %t291
  call void @__inc_ref(ptr %t288)
  %t292 = getelementptr ptr, ptr %t289, i32 1
  store ptr %t288, ptr %t292
  br label %case.end.3.286
case.end.3.286:
  br label %case.join.284
case.arm.4.293:
  %t295 = getelementptr ptr, ptr %t279, i32 1
  %t296 = load ptr, ptr %t295
  call void @__inc_ref(ptr %t296)
  call void @__inc_ref(ptr %t296)
  %t297 = call ptr @__concat(ptr %t296, ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  %t298 = getelementptr ptr, ptr %t297, i32 0
  %t299 = load ptr, ptr %t298
  %t300 = ptrtoint ptr %t299 to i64
  switch i64 %t300, label %case.default.301 [ i64 3, label %case.arm.3.303 i64 4, label %case.arm.4.311 ]
case.arm.3.303:
  %t305 = getelementptr ptr, ptr %t297, i32 1
  %t306 = load ptr, ptr %t305
  call void @__inc_ref(ptr %t306)
  %t307 = call ptr @__alloc(i64 16, i32 1)
  %t308 = inttoptr i64 3 to ptr
  %t309 = getelementptr ptr, ptr %t307, i32 0
  store ptr %t308, ptr %t309
  call void @__inc_ref(ptr %t306)
  %t310 = getelementptr ptr, ptr %t307, i32 1
  store ptr %t306, ptr %t310
  br label %case.end.3.304
case.end.3.304:
  br label %case.join.302
case.arm.4.311:
  %t313 = getelementptr ptr, ptr %t297, i32 1
  %t314 = load ptr, ptr %t313
  call void @__inc_ref(ptr %t314)
  call void @__inc_ref(ptr %t314)
  call void @__inc_ref(ptr %t188)
  %t315 = call ptr @__concat(ptr %t314, ptr %t188)
  br label %case.end.4.312
case.end.4.312:
  br label %case.join.302
case.default.301:
  unreachable
case.join.302:
  %t316 = phi ptr [ %t307, %case.end.3.304 ], [ %t315, %case.end.4.312 ]
  call void @__free_recursive(ptr %t297)
  br label %case.end.4.294
case.end.4.294:
  br label %case.join.284
case.default.283:
  unreachable
case.join.284:
  %t317 = phi ptr [ %t289, %case.end.3.286 ], [ %t316, %case.end.4.294 ]
  call void @__free_recursive(ptr %t279)
  br label %case.end.4.276
case.end.4.276:
  br label %case.join.266
case.default.265:
  unreachable
case.join.266:
  %t318 = phi ptr [ %t271, %case.end.3.268 ], [ %t317, %case.end.4.276 ]
  call void @__free_recursive(ptr %t261)
  br label %case.end.4.258
case.end.4.258:
  br label %case.join.248
case.default.247:
  unreachable
case.join.248:
  %t319 = phi ptr [ %t253, %case.end.3.250 ], [ %t318, %case.end.4.258 ]
  call void @__free_recursive(ptr %t243)
  br label %case.end.4.240
case.end.4.240:
  br label %case.join.230
case.default.229:
  unreachable
case.join.230:
  %t320 = phi ptr [ %t235, %case.end.3.232 ], [ %t319, %case.end.4.240 ]
  call void @__free_recursive(ptr %t225)
  br label %case.end.4.222
case.end.4.222:
  br label %case.join.212
case.default.211:
  unreachable
case.join.212:
  %t321 = phi ptr [ %t217, %case.end.3.214 ], [ %t320, %case.end.4.222 ]
  call void @__free_recursive(ptr %t207)
  br label %case.end.4.204
case.end.4.204:
  br label %case.join.194
case.default.193:
  unreachable
case.join.194:
  %t322 = phi ptr [ %t199, %case.end.3.196 ], [ %t321, %case.end.4.204 ]
  call void @__free_recursive(ptr %t189)
  br label %case.end.4.186
case.end.4.186:
  br label %case.join.176
case.default.175:
  unreachable
case.join.176:
  %t323 = phi ptr [ %t181, %case.end.3.178 ], [ %t322, %case.end.4.186 ]
  call void @__free_recursive(ptr %t171)
  call void @__free_recursive(ptr %t152)
  br label %case.end.4.149
case.end.4.149:
  br label %case.join.139
case.default.138:
  unreachable
case.join.139:
  %t324 = phi ptr [ %t144, %case.end.3.141 ], [ %t323, %case.end.4.149 ]
  call void @__free_recursive(ptr %t134)
  call void @__free_recursive(ptr %t119)
  br label %case.end.4.114
case.end.4.114:
  br label %case.join.104
case.default.103:
  unreachable
case.join.104:
  %t325 = phi ptr [ %t109, %case.end.3.106 ], [ %t324, %case.end.4.114 ]
  call void @__free_recursive(ptr %t99)
  call void @__free_recursive(ptr %t84)
  br label %case.end.4.79
case.end.4.79:
  br label %case.join.69
case.default.68:
  unreachable
case.join.69:
  %t326 = phi ptr [ %t74, %case.end.3.71 ], [ %t325, %case.end.4.79 ]
  call void @__free_recursive(ptr %t64)
  call void @__free_recursive(ptr %t43)
  call void @__free_recursive(ptr %t21)
  store ptr %t326, ptr %v__inl19_scrut.jslot
  br label %join.5
join.case.default.25:
  unreachable
join.5:
  %t327 = load ptr, ptr %v__inl19_scrut.jslot
  %t328 = getelementptr ptr, ptr %t327, i32 0
  %t329 = load ptr, ptr %t328
  %t330 = ptrtoint ptr %t329 to i64
  switch i64 %t330, label %case.default.331 [ i64 3, label %case.arm.3.333 i64 4, label %case.arm.4.347 ]
case.arm.3.333:
  %t335 = call ptr @__alloc(i64 24, i32 2)
  %t336 = inttoptr i64 7 to ptr
  %t337 = getelementptr ptr, ptr %t335, i32 0
  store ptr %t336, ptr %t337
  %t338 = getelementptr ptr, ptr %t335, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t338
  %t339 = call ptr @__alloc(i64 16, i32 1)
  %t340 = inttoptr i64 5 to ptr
  %t341 = getelementptr ptr, ptr %t339, i32 0
  store ptr %t340, ptr %t341
  %t342 = call ptr @__alloc(i64 8, i32 0)
  %t343 = inttoptr i64 0 to ptr
  %t344 = getelementptr ptr, ptr %t342, i32 0
  store ptr %t343, ptr %t344
  %t345 = getelementptr ptr, ptr %t339, i32 1
  store ptr %t342, ptr %t345
  %t346 = getelementptr ptr, ptr %t335, i32 2
  store ptr %t339, ptr %t346
  br label %case.end.3.334
case.end.3.334:
  br label %case.join.332
case.arm.4.347:
  %t349 = call ptr @__alloc(i64 24, i32 2)
  %t350 = inttoptr i64 7 to ptr
  %t351 = getelementptr ptr, ptr %t349, i32 0
  store ptr %t350, ptr %t351
  %t352 = getelementptr ptr, ptr %t327, i32 1
  %t353 = load ptr, ptr %t352
  call void @__inc_ref(ptr %t353)
  %t354 = getelementptr ptr, ptr %t349, i32 1
  store ptr %t353, ptr %t354
  %t355 = call ptr @__alloc(i64 16, i32 1)
  %t356 = inttoptr i64 5 to ptr
  %t357 = getelementptr ptr, ptr %t355, i32 0
  store ptr %t356, ptr %t357
  %t358 = call ptr @__alloc(i64 8, i32 0)
  %t359 = inttoptr i64 0 to ptr
  %t360 = getelementptr ptr, ptr %t358, i32 0
  store ptr %t359, ptr %t360
  %t361 = getelementptr ptr, ptr %t355, i32 1
  store ptr %t358, ptr %t361
  %t362 = getelementptr ptr, ptr %t349, i32 2
  store ptr %t355, ptr %t362
  br label %case.end.4.348
case.end.4.348:
  br label %case.join.332
case.default.331:
  unreachable
case.join.332:
  %t363 = phi ptr [ %t335, %case.end.3.334 ], [ %t349, %case.end.4.348 ]
  call void @__free_recursive(ptr %t327)
  br label %join.end.364
join.end.364:
  br label %join.after.6
join.after.6:
  %t365 = phi ptr [ %t27, %join.val.39 ], [ %t363, %join.end.364 ]
  call void @__free_recursive(ptr %t0)
  ret ptr %t365
}

define i32 @main(i32 %argc, ptr %argv) {
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
