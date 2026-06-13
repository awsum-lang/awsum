; External C declarations
declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare ptr @memcpy(ptr, ptr, i64)
declare i64 @write(i32, ptr, i64)
declare i32 @snprintf(ptr, i64, ptr, ...)

@.fmt_i32 = private unnamed_addr constant [3 x i8] c"%d\00"

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


define internal ptr @__showInt32(ptr %p) {
  %v = load i32, ptr %p
  %buf = call ptr @__alloc(i64 24, i32 0)
  %payload = getelementptr i8, ptr %buf, i64 8
  %n = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %payload, i64 16, ptr @.fmt_i32, i32 %v)
  store i32 %n, ptr %buf
  %u16p = getelementptr i8, ptr %buf, i64 4
  store i32 %n, ptr %u16p
  call void @__free_recursive(ptr %p)
  ret ptr %buf
}


define internal ptr @__negInt32(ptr %p) {
  %v = load i32, ptr %p
  %is_min = icmp eq i32 %v, -2147483648
  br i1 %is_min, label %overflow, label %ok
overflow:
  %oe = call ptr @__alloc(i64 8, i32 0)
  %oe_tag = inttoptr i64 18 to ptr
  store ptr %oe_tag, ptr %oe
  %left = call ptr @__alloc(i64 16, i32 1)
  %left_tag = inttoptr i64 3 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %oe, ptr %left_f
  call void @__free_recursive(ptr %p)
  ret ptr %left
ok:
  %newv = sub i32 0, %v
  %box = call ptr @__alloc(i64 4, i32 0)
  store i32 %newv, ptr %box
  %right = call ptr @__alloc(i64 16, i32 1)
  %right_tag = inttoptr i64 4 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %box, ptr %right_f
  call void @__free_recursive(ptr %p)
  ret ptr %right
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

define internal ptr @v_minInt32() {
  %t0 = call ptr @__alloc(i64 4, i32 0)
  store i32 -2147483648, ptr %t0
  ret ptr %t0
}

define internal ptr @v_maxInt32() {
  %t0 = call ptr @__alloc(i64 4, i32 0)
  store i32 2147483647, ptr %t0
  ret ptr %t0
}

define internal ptr @v_main() {
  %v__inl19_scrut.jslot = alloca ptr
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 4 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 4, i32 0)
  store i32 -5, ptr %t3
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
  %t19 = call ptr @__showInt32(ptr %t18)
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
  %t44 = inttoptr i64 4 to ptr
  %t45 = getelementptr ptr, ptr %t43, i32 0
  store ptr %t44, ptr %t45
  %t46 = call ptr @__alloc(i64 4, i32 0)
  store i32 5, ptr %t46
  %t47 = getelementptr ptr, ptr %t43, i32 1
  store ptr %t46, ptr %t47
  %t48 = getelementptr ptr, ptr %t43, i32 0
  %t49 = load ptr, ptr %t48
  %t50 = ptrtoint ptr %t49 to i64
  switch i64 %t50, label %case.default.51 [ i64 3, label %case.arm.3.53 i64 4, label %case.arm.4.56 ]
case.arm.3.53:
  %t55 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
  br label %case.end.3.54
case.end.3.54:
  br label %case.join.52
case.arm.4.56:
  %t58 = getelementptr ptr, ptr %t43, i32 1
  %t59 = load ptr, ptr %t58
  call void @__inc_ref(ptr %t59)
  %t60 = call ptr @__showInt32(ptr %t59)
  %t61 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t60)
  br label %case.end.4.57
case.end.4.57:
  br label %case.join.52
case.default.51:
  unreachable
case.join.52:
  %t62 = phi ptr [ %t55, %case.end.3.54 ], [ %t61, %case.end.4.57 ]
  %t63 = getelementptr ptr, ptr %t62, i32 0
  %t64 = load ptr, ptr %t63
  %t65 = ptrtoint ptr %t64 to i64
  switch i64 %t65, label %case.default.66 [ i64 3, label %case.arm.3.68 i64 4, label %case.arm.4.76 ]
case.arm.3.68:
  %t70 = getelementptr ptr, ptr %t62, i32 1
  %t71 = load ptr, ptr %t70
  call void @__inc_ref(ptr %t71)
  %t72 = call ptr @__alloc(i64 16, i32 1)
  %t73 = inttoptr i64 3 to ptr
  %t74 = getelementptr ptr, ptr %t72, i32 0
  store ptr %t73, ptr %t74
  call void @__inc_ref(ptr %t71)
  %t75 = getelementptr ptr, ptr %t72, i32 1
  store ptr %t71, ptr %t75
  br label %case.end.3.69
case.end.3.69:
  br label %case.join.67
case.arm.4.76:
  %t78 = getelementptr ptr, ptr %t62, i32 1
  %t79 = load ptr, ptr %t78
  call void @__inc_ref(ptr %t79)
  %t80 = call ptr @__alloc(i64 16, i32 1)
  %t81 = inttoptr i64 4 to ptr
  %t82 = getelementptr ptr, ptr %t80, i32 0
  store ptr %t81, ptr %t82
  %t83 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t83
  %t84 = getelementptr ptr, ptr %t80, i32 1
  store ptr %t83, ptr %t84
  %t85 = getelementptr ptr, ptr %t80, i32 0
  %t86 = load ptr, ptr %t85
  %t87 = ptrtoint ptr %t86 to i64
  switch i64 %t87, label %case.default.88 [ i64 3, label %case.arm.3.90 i64 4, label %case.arm.4.93 ]
case.arm.3.90:
  %t92 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
  br label %case.end.3.91
case.end.3.91:
  br label %case.join.89
case.arm.4.93:
  %t95 = getelementptr ptr, ptr %t80, i32 1
  %t96 = load ptr, ptr %t95
  call void @__inc_ref(ptr %t96)
  %t97 = call ptr @__showInt32(ptr %t96)
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
  %t117 = call ptr @v_maxInt32()
  %t118 = call ptr @__negInt32(ptr %t117)
  %t119 = getelementptr ptr, ptr %t118, i32 0
  %t120 = load ptr, ptr %t119
  %t121 = ptrtoint ptr %t120 to i64
  switch i64 %t121, label %case.default.122 [ i64 3, label %case.arm.3.124 i64 4, label %case.arm.4.127 ]
case.arm.3.124:
  %t126 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
  br label %case.end.3.125
case.end.3.125:
  br label %case.join.123
case.arm.4.127:
  %t129 = getelementptr ptr, ptr %t118, i32 1
  %t130 = load ptr, ptr %t129
  call void @__inc_ref(ptr %t130)
  %t131 = call ptr @__showInt32(ptr %t130)
  %t132 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t131)
  br label %case.end.4.128
case.end.4.128:
  br label %case.join.123
case.default.122:
  unreachable
case.join.123:
  %t133 = phi ptr [ %t126, %case.end.3.125 ], [ %t132, %case.end.4.128 ]
  %t134 = getelementptr ptr, ptr %t133, i32 0
  %t135 = load ptr, ptr %t134
  %t136 = ptrtoint ptr %t135 to i64
  switch i64 %t136, label %case.default.137 [ i64 3, label %case.arm.3.139 i64 4, label %case.arm.4.147 ]
case.arm.3.139:
  %t141 = getelementptr ptr, ptr %t133, i32 1
  %t142 = load ptr, ptr %t141
  call void @__inc_ref(ptr %t142)
  %t143 = call ptr @__alloc(i64 16, i32 1)
  %t144 = inttoptr i64 3 to ptr
  %t145 = getelementptr ptr, ptr %t143, i32 0
  store ptr %t144, ptr %t145
  call void @__inc_ref(ptr %t142)
  %t146 = getelementptr ptr, ptr %t143, i32 1
  store ptr %t142, ptr %t146
  br label %case.end.3.140
case.end.3.140:
  br label %case.join.138
case.arm.4.147:
  %t149 = getelementptr ptr, ptr %t133, i32 1
  %t150 = load ptr, ptr %t149
  call void @__inc_ref(ptr %t150)
  %t151 = call ptr @v_minInt32()
  %t152 = call ptr @__negInt32(ptr %t151)
  %t153 = getelementptr ptr, ptr %t152, i32 0
  %t154 = load ptr, ptr %t153
  %t155 = ptrtoint ptr %t154 to i64
  switch i64 %t155, label %case.default.156 [ i64 3, label %case.arm.3.158 i64 4, label %case.arm.4.161 ]
case.arm.3.158:
  %t160 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
  br label %case.end.3.159
case.end.3.159:
  br label %case.join.157
case.arm.4.161:
  %t163 = getelementptr ptr, ptr %t152, i32 1
  %t164 = load ptr, ptr %t163
  call void @__inc_ref(ptr %t164)
  %t165 = call ptr @__showInt32(ptr %t164)
  %t166 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t165)
  br label %case.end.4.162
case.end.4.162:
  br label %case.join.157
case.default.156:
  unreachable
case.join.157:
  %t167 = phi ptr [ %t160, %case.end.3.159 ], [ %t166, %case.end.4.162 ]
  %t168 = getelementptr ptr, ptr %t167, i32 0
  %t169 = load ptr, ptr %t168
  %t170 = ptrtoint ptr %t169 to i64
  switch i64 %t170, label %case.default.171 [ i64 3, label %case.arm.3.173 i64 4, label %case.arm.4.181 ]
case.arm.3.173:
  %t175 = getelementptr ptr, ptr %t167, i32 1
  %t176 = load ptr, ptr %t175
  call void @__inc_ref(ptr %t176)
  %t177 = call ptr @__alloc(i64 16, i32 1)
  %t178 = inttoptr i64 3 to ptr
  %t179 = getelementptr ptr, ptr %t177, i32 0
  store ptr %t178, ptr %t179
  call void @__inc_ref(ptr %t176)
  %t180 = getelementptr ptr, ptr %t177, i32 1
  store ptr %t176, ptr %t180
  br label %case.end.3.174
case.end.3.174:
  br label %case.join.172
case.arm.4.181:
  %t183 = getelementptr ptr, ptr %t167, i32 1
  %t184 = load ptr, ptr %t183
  call void @__inc_ref(ptr %t184)
  call void @__inc_ref(ptr %t42)
  %t185 = call ptr @__concat(ptr %t42, ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  %t186 = getelementptr ptr, ptr %t185, i32 0
  %t187 = load ptr, ptr %t186
  %t188 = ptrtoint ptr %t187 to i64
  switch i64 %t188, label %case.default.189 [ i64 3, label %case.arm.3.191 i64 4, label %case.arm.4.199 ]
case.arm.3.191:
  %t193 = getelementptr ptr, ptr %t185, i32 1
  %t194 = load ptr, ptr %t193
  call void @__inc_ref(ptr %t194)
  %t195 = call ptr @__alloc(i64 16, i32 1)
  %t196 = inttoptr i64 3 to ptr
  %t197 = getelementptr ptr, ptr %t195, i32 0
  store ptr %t196, ptr %t197
  call void @__inc_ref(ptr %t194)
  %t198 = getelementptr ptr, ptr %t195, i32 1
  store ptr %t194, ptr %t198
  br label %case.end.3.192
case.end.3.192:
  br label %case.join.190
case.arm.4.199:
  %t201 = getelementptr ptr, ptr %t185, i32 1
  %t202 = load ptr, ptr %t201
  call void @__inc_ref(ptr %t202)
  call void @__inc_ref(ptr %t202)
  call void @__inc_ref(ptr %t79)
  %t203 = call ptr @__concat(ptr %t202, ptr %t79)
  %t204 = getelementptr ptr, ptr %t203, i32 0
  %t205 = load ptr, ptr %t204
  %t206 = ptrtoint ptr %t205 to i64
  switch i64 %t206, label %case.default.207 [ i64 3, label %case.arm.3.209 i64 4, label %case.arm.4.217 ]
case.arm.3.209:
  %t211 = getelementptr ptr, ptr %t203, i32 1
  %t212 = load ptr, ptr %t211
  call void @__inc_ref(ptr %t212)
  %t213 = call ptr @__alloc(i64 16, i32 1)
  %t214 = inttoptr i64 3 to ptr
  %t215 = getelementptr ptr, ptr %t213, i32 0
  store ptr %t214, ptr %t215
  call void @__inc_ref(ptr %t212)
  %t216 = getelementptr ptr, ptr %t213, i32 1
  store ptr %t212, ptr %t216
  br label %case.end.3.210
case.end.3.210:
  br label %case.join.208
case.arm.4.217:
  %t219 = getelementptr ptr, ptr %t203, i32 1
  %t220 = load ptr, ptr %t219
  call void @__inc_ref(ptr %t220)
  call void @__inc_ref(ptr %t220)
  %t221 = call ptr @__concat(ptr %t220, ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  %t222 = getelementptr ptr, ptr %t221, i32 0
  %t223 = load ptr, ptr %t222
  %t224 = ptrtoint ptr %t223 to i64
  switch i64 %t224, label %case.default.225 [ i64 3, label %case.arm.3.227 i64 4, label %case.arm.4.235 ]
case.arm.3.227:
  %t229 = getelementptr ptr, ptr %t221, i32 1
  %t230 = load ptr, ptr %t229
  call void @__inc_ref(ptr %t230)
  %t231 = call ptr @__alloc(i64 16, i32 1)
  %t232 = inttoptr i64 3 to ptr
  %t233 = getelementptr ptr, ptr %t231, i32 0
  store ptr %t232, ptr %t233
  call void @__inc_ref(ptr %t230)
  %t234 = getelementptr ptr, ptr %t231, i32 1
  store ptr %t230, ptr %t234
  br label %case.end.3.228
case.end.3.228:
  br label %case.join.226
case.arm.4.235:
  %t237 = getelementptr ptr, ptr %t221, i32 1
  %t238 = load ptr, ptr %t237
  call void @__inc_ref(ptr %t238)
  call void @__inc_ref(ptr %t238)
  call void @__inc_ref(ptr %t116)
  %t239 = call ptr @__concat(ptr %t238, ptr %t116)
  %t240 = getelementptr ptr, ptr %t239, i32 0
  %t241 = load ptr, ptr %t240
  %t242 = ptrtoint ptr %t241 to i64
  switch i64 %t242, label %case.default.243 [ i64 3, label %case.arm.3.245 i64 4, label %case.arm.4.253 ]
case.arm.3.245:
  %t247 = getelementptr ptr, ptr %t239, i32 1
  %t248 = load ptr, ptr %t247
  call void @__inc_ref(ptr %t248)
  %t249 = call ptr @__alloc(i64 16, i32 1)
  %t250 = inttoptr i64 3 to ptr
  %t251 = getelementptr ptr, ptr %t249, i32 0
  store ptr %t250, ptr %t251
  call void @__inc_ref(ptr %t248)
  %t252 = getelementptr ptr, ptr %t249, i32 1
  store ptr %t248, ptr %t252
  br label %case.end.3.246
case.end.3.246:
  br label %case.join.244
case.arm.4.253:
  %t255 = getelementptr ptr, ptr %t239, i32 1
  %t256 = load ptr, ptr %t255
  call void @__inc_ref(ptr %t256)
  call void @__inc_ref(ptr %t256)
  %t257 = call ptr @__concat(ptr %t256, ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  %t258 = getelementptr ptr, ptr %t257, i32 0
  %t259 = load ptr, ptr %t258
  %t260 = ptrtoint ptr %t259 to i64
  switch i64 %t260, label %case.default.261 [ i64 3, label %case.arm.3.263 i64 4, label %case.arm.4.271 ]
case.arm.3.263:
  %t265 = getelementptr ptr, ptr %t257, i32 1
  %t266 = load ptr, ptr %t265
  call void @__inc_ref(ptr %t266)
  %t267 = call ptr @__alloc(i64 16, i32 1)
  %t268 = inttoptr i64 3 to ptr
  %t269 = getelementptr ptr, ptr %t267, i32 0
  store ptr %t268, ptr %t269
  call void @__inc_ref(ptr %t266)
  %t270 = getelementptr ptr, ptr %t267, i32 1
  store ptr %t266, ptr %t270
  br label %case.end.3.264
case.end.3.264:
  br label %case.join.262
case.arm.4.271:
  %t273 = getelementptr ptr, ptr %t257, i32 1
  %t274 = load ptr, ptr %t273
  call void @__inc_ref(ptr %t274)
  call void @__inc_ref(ptr %t274)
  call void @__inc_ref(ptr %t150)
  %t275 = call ptr @__concat(ptr %t274, ptr %t150)
  %t276 = getelementptr ptr, ptr %t275, i32 0
  %t277 = load ptr, ptr %t276
  %t278 = ptrtoint ptr %t277 to i64
  switch i64 %t278, label %case.default.279 [ i64 3, label %case.arm.3.281 i64 4, label %case.arm.4.289 ]
case.arm.3.281:
  %t283 = getelementptr ptr, ptr %t275, i32 1
  %t284 = load ptr, ptr %t283
  call void @__inc_ref(ptr %t284)
  %t285 = call ptr @__alloc(i64 16, i32 1)
  %t286 = inttoptr i64 3 to ptr
  %t287 = getelementptr ptr, ptr %t285, i32 0
  store ptr %t286, ptr %t287
  call void @__inc_ref(ptr %t284)
  %t288 = getelementptr ptr, ptr %t285, i32 1
  store ptr %t284, ptr %t288
  br label %case.end.3.282
case.end.3.282:
  br label %case.join.280
case.arm.4.289:
  %t291 = getelementptr ptr, ptr %t275, i32 1
  %t292 = load ptr, ptr %t291
  call void @__inc_ref(ptr %t292)
  call void @__inc_ref(ptr %t292)
  %t293 = call ptr @__concat(ptr %t292, ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  %t294 = getelementptr ptr, ptr %t293, i32 0
  %t295 = load ptr, ptr %t294
  %t296 = ptrtoint ptr %t295 to i64
  switch i64 %t296, label %case.default.297 [ i64 3, label %case.arm.3.299 i64 4, label %case.arm.4.307 ]
case.arm.3.299:
  %t301 = getelementptr ptr, ptr %t293, i32 1
  %t302 = load ptr, ptr %t301
  call void @__inc_ref(ptr %t302)
  %t303 = call ptr @__alloc(i64 16, i32 1)
  %t304 = inttoptr i64 3 to ptr
  %t305 = getelementptr ptr, ptr %t303, i32 0
  store ptr %t304, ptr %t305
  call void @__inc_ref(ptr %t302)
  %t306 = getelementptr ptr, ptr %t303, i32 1
  store ptr %t302, ptr %t306
  br label %case.end.3.300
case.end.3.300:
  br label %case.join.298
case.arm.4.307:
  %t309 = getelementptr ptr, ptr %t293, i32 1
  %t310 = load ptr, ptr %t309
  call void @__inc_ref(ptr %t310)
  call void @__inc_ref(ptr %t310)
  call void @__inc_ref(ptr %t184)
  %t311 = call ptr @__concat(ptr %t310, ptr %t184)
  br label %case.end.4.308
case.end.4.308:
  br label %case.join.298
case.default.297:
  unreachable
case.join.298:
  %t312 = phi ptr [ %t303, %case.end.3.300 ], [ %t311, %case.end.4.308 ]
  call void @__free_recursive(ptr %t293)
  br label %case.end.4.290
case.end.4.290:
  br label %case.join.280
case.default.279:
  unreachable
case.join.280:
  %t313 = phi ptr [ %t285, %case.end.3.282 ], [ %t312, %case.end.4.290 ]
  call void @__free_recursive(ptr %t275)
  br label %case.end.4.272
case.end.4.272:
  br label %case.join.262
case.default.261:
  unreachable
case.join.262:
  %t314 = phi ptr [ %t267, %case.end.3.264 ], [ %t313, %case.end.4.272 ]
  call void @__free_recursive(ptr %t257)
  br label %case.end.4.254
case.end.4.254:
  br label %case.join.244
case.default.243:
  unreachable
case.join.244:
  %t315 = phi ptr [ %t249, %case.end.3.246 ], [ %t314, %case.end.4.254 ]
  call void @__free_recursive(ptr %t239)
  br label %case.end.4.236
case.end.4.236:
  br label %case.join.226
case.default.225:
  unreachable
case.join.226:
  %t316 = phi ptr [ %t231, %case.end.3.228 ], [ %t315, %case.end.4.236 ]
  call void @__free_recursive(ptr %t221)
  br label %case.end.4.218
case.end.4.218:
  br label %case.join.208
case.default.207:
  unreachable
case.join.208:
  %t317 = phi ptr [ %t213, %case.end.3.210 ], [ %t316, %case.end.4.218 ]
  call void @__free_recursive(ptr %t203)
  br label %case.end.4.200
case.end.4.200:
  br label %case.join.190
case.default.189:
  unreachable
case.join.190:
  %t318 = phi ptr [ %t195, %case.end.3.192 ], [ %t317, %case.end.4.200 ]
  call void @__free_recursive(ptr %t185)
  br label %case.end.4.182
case.end.4.182:
  br label %case.join.172
case.default.171:
  unreachable
case.join.172:
  %t319 = phi ptr [ %t177, %case.end.3.174 ], [ %t318, %case.end.4.182 ]
  call void @__free_recursive(ptr %t167)
  call void @__free_recursive(ptr %t152)
  br label %case.end.4.148
case.end.4.148:
  br label %case.join.138
case.default.137:
  unreachable
case.join.138:
  %t320 = phi ptr [ %t143, %case.end.3.140 ], [ %t319, %case.end.4.148 ]
  call void @__free_recursive(ptr %t133)
  call void @__free_recursive(ptr %t118)
  br label %case.end.4.114
case.end.4.114:
  br label %case.join.104
case.default.103:
  unreachable
case.join.104:
  %t321 = phi ptr [ %t109, %case.end.3.106 ], [ %t320, %case.end.4.114 ]
  call void @__free_recursive(ptr %t99)
  call void @__free_recursive(ptr %t80)
  br label %case.end.4.77
case.end.4.77:
  br label %case.join.67
case.default.66:
  unreachable
case.join.67:
  %t322 = phi ptr [ %t72, %case.end.3.69 ], [ %t321, %case.end.4.77 ]
  call void @__free_recursive(ptr %t62)
  call void @__free_recursive(ptr %t43)
  call void @__free_recursive(ptr %t21)
  store ptr %t322, ptr %v__inl19_scrut.jslot
  br label %join.5
join.case.default.25:
  unreachable
join.5:
  %t323 = load ptr, ptr %v__inl19_scrut.jslot
  %t324 = getelementptr ptr, ptr %t323, i32 0
  %t325 = load ptr, ptr %t324
  %t326 = ptrtoint ptr %t325 to i64
  switch i64 %t326, label %case.default.327 [ i64 3, label %case.arm.3.329 i64 4, label %case.arm.4.343 ]
case.arm.3.329:
  %t331 = call ptr @__alloc(i64 24, i32 2)
  %t332 = inttoptr i64 7 to ptr
  %t333 = getelementptr ptr, ptr %t331, i32 0
  store ptr %t332, ptr %t333
  %t334 = getelementptr ptr, ptr %t331, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t334
  %t335 = call ptr @__alloc(i64 16, i32 1)
  %t336 = inttoptr i64 5 to ptr
  %t337 = getelementptr ptr, ptr %t335, i32 0
  store ptr %t336, ptr %t337
  %t338 = call ptr @__alloc(i64 8, i32 0)
  %t339 = inttoptr i64 0 to ptr
  %t340 = getelementptr ptr, ptr %t338, i32 0
  store ptr %t339, ptr %t340
  %t341 = getelementptr ptr, ptr %t335, i32 1
  store ptr %t338, ptr %t341
  %t342 = getelementptr ptr, ptr %t331, i32 2
  store ptr %t335, ptr %t342
  br label %case.end.3.330
case.end.3.330:
  br label %case.join.328
case.arm.4.343:
  %t345 = call ptr @__alloc(i64 24, i32 2)
  %t346 = inttoptr i64 7 to ptr
  %t347 = getelementptr ptr, ptr %t345, i32 0
  store ptr %t346, ptr %t347
  %t348 = getelementptr ptr, ptr %t323, i32 1
  %t349 = load ptr, ptr %t348
  call void @__inc_ref(ptr %t349)
  %t350 = getelementptr ptr, ptr %t345, i32 1
  store ptr %t349, ptr %t350
  %t351 = call ptr @__alloc(i64 16, i32 1)
  %t352 = inttoptr i64 5 to ptr
  %t353 = getelementptr ptr, ptr %t351, i32 0
  store ptr %t352, ptr %t353
  %t354 = call ptr @__alloc(i64 8, i32 0)
  %t355 = inttoptr i64 0 to ptr
  %t356 = getelementptr ptr, ptr %t354, i32 0
  store ptr %t355, ptr %t356
  %t357 = getelementptr ptr, ptr %t351, i32 1
  store ptr %t354, ptr %t357
  %t358 = getelementptr ptr, ptr %t345, i32 2
  store ptr %t351, ptr %t358
  br label %case.end.4.344
case.end.4.344:
  br label %case.join.328
case.default.327:
  unreachable
case.join.328:
  %t359 = phi ptr [ %t331, %case.end.3.330 ], [ %t345, %case.end.4.344 ]
  call void @__free_recursive(ptr %t323)
  br label %join.end.360
join.end.360:
  br label %join.after.6
join.after.6:
  %t361 = phi ptr [ %t27, %join.val.39 ], [ %t359, %join.end.360 ]
  call void @__free_recursive(ptr %t0)
  ret ptr %t361
}

define i32 @main(i32 %argc, ptr %argv) {
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
