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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [11 x i8]} { i32 0, i32 0, i32 0, i32 11, i32 11, [11 x i8] c"underflow: " }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [14 x i8]} { i32 0, i32 0, i32 0, i32 14, i32 14, [14 x i8] c"UnderflowError" }
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


define internal ptr @__subUInt32(ptr %pa, ptr %pb) {
  %a = load i32, ptr %pa
  %b = load i32, ptr %pb
  %unf = icmp ult i32 %a, %b
  br i1 %unf, label %err, label %ok
err:
  %ue = call ptr @__alloc(i64 8, i32 0)
  %ue_tag = inttoptr i64 17 to ptr
  store ptr %ue_tag, ptr %ue
  %left = call ptr @__alloc(i64 16, i32 1)
  %left_tag = inttoptr i64 3 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %ue, ptr %left_f
  br label %join
ok:
  %newv = sub i32 %a, %b
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
  store i32 0, ptr %t3
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
  %t37 = call ptr @v_maxUInt32()
  %t38 = call ptr @v_minUInt32()
  %t39 = call ptr @__subUInt32(ptr %t37, ptr %t38)
  %t40 = getelementptr ptr, ptr %t39, i32 0
  %t41 = load ptr, ptr %t40
  %t42 = ptrtoint ptr %t41 to i64
  switch i64 %t42, label %case.default.43 [ i64 3, label %case.arm.3.45 i64 4, label %case.arm.4.48 ]
case.arm.3.45:
  %t47 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  br label %case.end.3.46
case.end.3.46:
  br label %case.join.44
case.arm.4.48:
  %t50 = getelementptr ptr, ptr %t39, i32 1
  %t51 = load ptr, ptr %t50
  call void @__inc_ref(ptr %t51)
  %t52 = call ptr @__showUInt32(ptr %t51)
  %t53 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t52)
  br label %case.end.4.49
case.end.4.49:
  br label %case.join.44
case.default.43:
  unreachable
case.join.44:
  %t54 = phi ptr [ %t47, %case.end.3.46 ], [ %t53, %case.end.4.49 ]
  %t55 = getelementptr ptr, ptr %t54, i32 0
  %t56 = load ptr, ptr %t55
  %t57 = ptrtoint ptr %t56 to i64
  switch i64 %t57, label %case.default.58 [ i64 3, label %case.arm.3.60 i64 4, label %case.arm.4.68 ]
case.arm.3.60:
  %t62 = getelementptr ptr, ptr %t54, i32 1
  %t63 = load ptr, ptr %t62
  call void @__inc_ref(ptr %t63)
  %t64 = call ptr @__alloc(i64 16, i32 1)
  %t65 = inttoptr i64 3 to ptr
  %t66 = getelementptr ptr, ptr %t64, i32 0
  store ptr %t65, ptr %t66
  call void @__inc_ref(ptr %t63)
  %t67 = getelementptr ptr, ptr %t64, i32 1
  store ptr %t63, ptr %t67
  br label %case.end.3.61
case.end.3.61:
  br label %case.join.59
case.arm.4.68:
  %t70 = getelementptr ptr, ptr %t54, i32 1
  %t71 = load ptr, ptr %t70
  call void @__inc_ref(ptr %t71)
  %t72 = call ptr @v_minUInt32()
  %t73 = call ptr @__alloc(i64 4, i32 0)
  store i32 1, ptr %t73
  %t74 = call ptr @__subUInt32(ptr %t72, ptr %t73)
  %t75 = getelementptr ptr, ptr %t74, i32 0
  %t76 = load ptr, ptr %t75
  %t77 = ptrtoint ptr %t76 to i64
  switch i64 %t77, label %case.default.78 [ i64 3, label %case.arm.3.80 i64 4, label %case.arm.4.83 ]
case.arm.3.80:
  %t82 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  br label %case.end.3.81
case.end.3.81:
  br label %case.join.79
case.arm.4.83:
  %t85 = getelementptr ptr, ptr %t74, i32 1
  %t86 = load ptr, ptr %t85
  call void @__inc_ref(ptr %t86)
  %t87 = call ptr @__showUInt32(ptr %t86)
  %t88 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t87)
  br label %case.end.4.84
case.end.4.84:
  br label %case.join.79
case.default.78:
  unreachable
case.join.79:
  %t89 = phi ptr [ %t82, %case.end.3.81 ], [ %t88, %case.end.4.84 ]
  %t90 = getelementptr ptr, ptr %t89, i32 0
  %t91 = load ptr, ptr %t90
  %t92 = ptrtoint ptr %t91 to i64
  switch i64 %t92, label %case.default.93 [ i64 3, label %case.arm.3.95 i64 4, label %case.arm.4.103 ]
case.arm.3.95:
  %t97 = getelementptr ptr, ptr %t89, i32 1
  %t98 = load ptr, ptr %t97
  call void @__inc_ref(ptr %t98)
  %t99 = call ptr @__alloc(i64 16, i32 1)
  %t100 = inttoptr i64 3 to ptr
  %t101 = getelementptr ptr, ptr %t99, i32 0
  store ptr %t100, ptr %t101
  call void @__inc_ref(ptr %t98)
  %t102 = getelementptr ptr, ptr %t99, i32 1
  store ptr %t98, ptr %t102
  br label %case.end.3.96
case.end.3.96:
  br label %case.join.94
case.arm.4.103:
  %t105 = getelementptr ptr, ptr %t89, i32 1
  %t106 = load ptr, ptr %t105
  call void @__inc_ref(ptr %t106)
  %t107 = call ptr @v_minUInt32()
  %t108 = call ptr @__alloc(i64 4, i32 0)
  store i32 -2147483648, ptr %t108
  %t109 = call ptr @__subUInt32(ptr %t107, ptr %t108)
  %t110 = getelementptr ptr, ptr %t109, i32 0
  %t111 = load ptr, ptr %t110
  %t112 = ptrtoint ptr %t111 to i64
  switch i64 %t112, label %case.default.113 [ i64 3, label %case.arm.3.115 i64 4, label %case.arm.4.118 ]
case.arm.3.115:
  %t117 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  br label %case.end.3.116
case.end.3.116:
  br label %case.join.114
case.arm.4.118:
  %t120 = getelementptr ptr, ptr %t109, i32 1
  %t121 = load ptr, ptr %t120
  call void @__inc_ref(ptr %t121)
  %t122 = call ptr @__showUInt32(ptr %t121)
  %t123 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t122)
  br label %case.end.4.119
case.end.4.119:
  br label %case.join.114
case.default.113:
  unreachable
case.join.114:
  %t124 = phi ptr [ %t117, %case.end.3.116 ], [ %t123, %case.end.4.119 ]
  %t125 = getelementptr ptr, ptr %t124, i32 0
  %t126 = load ptr, ptr %t125
  %t127 = ptrtoint ptr %t126 to i64
  switch i64 %t127, label %case.default.128 [ i64 3, label %case.arm.3.130 i64 4, label %case.arm.4.138 ]
case.arm.3.130:
  %t132 = getelementptr ptr, ptr %t124, i32 1
  %t133 = load ptr, ptr %t132
  call void @__inc_ref(ptr %t133)
  %t134 = call ptr @__alloc(i64 16, i32 1)
  %t135 = inttoptr i64 3 to ptr
  %t136 = getelementptr ptr, ptr %t134, i32 0
  store ptr %t135, ptr %t136
  call void @__inc_ref(ptr %t133)
  %t137 = getelementptr ptr, ptr %t134, i32 1
  store ptr %t133, ptr %t137
  br label %case.end.3.131
case.end.3.131:
  br label %case.join.129
case.arm.4.138:
  %t140 = getelementptr ptr, ptr %t124, i32 1
  %t141 = load ptr, ptr %t140
  call void @__inc_ref(ptr %t141)
  %t142 = call ptr @__alloc(i64 16, i32 1)
  %t143 = inttoptr i64 4 to ptr
  %t144 = getelementptr ptr, ptr %t142, i32 0
  store ptr %t143, ptr %t144
  %t145 = call ptr @__alloc(i64 4, i32 0)
  store i32 1, ptr %t145
  %t146 = getelementptr ptr, ptr %t142, i32 1
  store ptr %t145, ptr %t146
  %t147 = getelementptr ptr, ptr %t142, i32 0
  %t148 = load ptr, ptr %t147
  %t149 = ptrtoint ptr %t148 to i64
  switch i64 %t149, label %case.default.150 [ i64 3, label %case.arm.3.152 i64 4, label %case.arm.4.155 ]
case.arm.3.152:
  %t154 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  br label %case.end.3.153
case.end.3.153:
  br label %case.join.151
case.arm.4.155:
  %t157 = getelementptr ptr, ptr %t142, i32 1
  %t158 = load ptr, ptr %t157
  call void @__inc_ref(ptr %t158)
  %t159 = call ptr @__showUInt32(ptr %t158)
  %t160 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t159)
  br label %case.end.4.156
case.end.4.156:
  br label %case.join.151
case.default.150:
  unreachable
case.join.151:
  %t161 = phi ptr [ %t154, %case.end.3.153 ], [ %t160, %case.end.4.156 ]
  %t162 = getelementptr ptr, ptr %t161, i32 0
  %t163 = load ptr, ptr %t162
  %t164 = ptrtoint ptr %t163 to i64
  switch i64 %t164, label %case.default.165 [ i64 3, label %case.arm.3.167 i64 4, label %case.arm.4.175 ]
case.arm.3.167:
  %t169 = getelementptr ptr, ptr %t161, i32 1
  %t170 = load ptr, ptr %t169
  call void @__inc_ref(ptr %t170)
  %t171 = call ptr @__alloc(i64 16, i32 1)
  %t172 = inttoptr i64 3 to ptr
  %t173 = getelementptr ptr, ptr %t171, i32 0
  store ptr %t172, ptr %t173
  call void @__inc_ref(ptr %t170)
  %t174 = getelementptr ptr, ptr %t171, i32 1
  store ptr %t170, ptr %t174
  br label %case.end.3.168
case.end.3.168:
  br label %case.join.166
case.arm.4.175:
  %t177 = getelementptr ptr, ptr %t161, i32 1
  %t178 = load ptr, ptr %t177
  call void @__inc_ref(ptr %t178)
  call void @__inc_ref(ptr %t36)
  %t179 = call ptr @__concat(ptr %t36, ptr getelementptr inbounds (i8, ptr @.str.3, i64 12))
  %t180 = getelementptr ptr, ptr %t179, i32 0
  %t181 = load ptr, ptr %t180
  %t182 = ptrtoint ptr %t181 to i64
  switch i64 %t182, label %case.default.183 [ i64 3, label %case.arm.3.185 i64 4, label %case.arm.4.193 ]
case.arm.3.185:
  %t187 = getelementptr ptr, ptr %t179, i32 1
  %t188 = load ptr, ptr %t187
  call void @__inc_ref(ptr %t188)
  %t189 = call ptr @__alloc(i64 16, i32 1)
  %t190 = inttoptr i64 3 to ptr
  %t191 = getelementptr ptr, ptr %t189, i32 0
  store ptr %t190, ptr %t191
  call void @__inc_ref(ptr %t188)
  %t192 = getelementptr ptr, ptr %t189, i32 1
  store ptr %t188, ptr %t192
  br label %case.end.3.186
case.end.3.186:
  br label %case.join.184
case.arm.4.193:
  %t195 = getelementptr ptr, ptr %t179, i32 1
  %t196 = load ptr, ptr %t195
  call void @__inc_ref(ptr %t196)
  call void @__inc_ref(ptr %t196)
  call void @__inc_ref(ptr %t71)
  %t197 = call ptr @__concat(ptr %t196, ptr %t71)
  %t198 = getelementptr ptr, ptr %t197, i32 0
  %t199 = load ptr, ptr %t198
  %t200 = ptrtoint ptr %t199 to i64
  switch i64 %t200, label %case.default.201 [ i64 3, label %case.arm.3.203 i64 4, label %case.arm.4.211 ]
case.arm.3.203:
  %t205 = getelementptr ptr, ptr %t197, i32 1
  %t206 = load ptr, ptr %t205
  call void @__inc_ref(ptr %t206)
  %t207 = call ptr @__alloc(i64 16, i32 1)
  %t208 = inttoptr i64 3 to ptr
  %t209 = getelementptr ptr, ptr %t207, i32 0
  store ptr %t208, ptr %t209
  call void @__inc_ref(ptr %t206)
  %t210 = getelementptr ptr, ptr %t207, i32 1
  store ptr %t206, ptr %t210
  br label %case.end.3.204
case.end.3.204:
  br label %case.join.202
case.arm.4.211:
  %t213 = getelementptr ptr, ptr %t197, i32 1
  %t214 = load ptr, ptr %t213
  call void @__inc_ref(ptr %t214)
  call void @__inc_ref(ptr %t214)
  %t215 = call ptr @__concat(ptr %t214, ptr getelementptr inbounds (i8, ptr @.str.3, i64 12))
  %t216 = getelementptr ptr, ptr %t215, i32 0
  %t217 = load ptr, ptr %t216
  %t218 = ptrtoint ptr %t217 to i64
  switch i64 %t218, label %case.default.219 [ i64 3, label %case.arm.3.221 i64 4, label %case.arm.4.229 ]
case.arm.3.221:
  %t223 = getelementptr ptr, ptr %t215, i32 1
  %t224 = load ptr, ptr %t223
  call void @__inc_ref(ptr %t224)
  %t225 = call ptr @__alloc(i64 16, i32 1)
  %t226 = inttoptr i64 3 to ptr
  %t227 = getelementptr ptr, ptr %t225, i32 0
  store ptr %t226, ptr %t227
  call void @__inc_ref(ptr %t224)
  %t228 = getelementptr ptr, ptr %t225, i32 1
  store ptr %t224, ptr %t228
  br label %case.end.3.222
case.end.3.222:
  br label %case.join.220
case.arm.4.229:
  %t231 = getelementptr ptr, ptr %t215, i32 1
  %t232 = load ptr, ptr %t231
  call void @__inc_ref(ptr %t232)
  call void @__inc_ref(ptr %t232)
  call void @__inc_ref(ptr %t106)
  %t233 = call ptr @__concat(ptr %t232, ptr %t106)
  %t234 = getelementptr ptr, ptr %t233, i32 0
  %t235 = load ptr, ptr %t234
  %t236 = ptrtoint ptr %t235 to i64
  switch i64 %t236, label %case.default.237 [ i64 3, label %case.arm.3.239 i64 4, label %case.arm.4.247 ]
case.arm.3.239:
  %t241 = getelementptr ptr, ptr %t233, i32 1
  %t242 = load ptr, ptr %t241
  call void @__inc_ref(ptr %t242)
  %t243 = call ptr @__alloc(i64 16, i32 1)
  %t244 = inttoptr i64 3 to ptr
  %t245 = getelementptr ptr, ptr %t243, i32 0
  store ptr %t244, ptr %t245
  call void @__inc_ref(ptr %t242)
  %t246 = getelementptr ptr, ptr %t243, i32 1
  store ptr %t242, ptr %t246
  br label %case.end.3.240
case.end.3.240:
  br label %case.join.238
case.arm.4.247:
  %t249 = getelementptr ptr, ptr %t233, i32 1
  %t250 = load ptr, ptr %t249
  call void @__inc_ref(ptr %t250)
  call void @__inc_ref(ptr %t250)
  %t251 = call ptr @__concat(ptr %t250, ptr getelementptr inbounds (i8, ptr @.str.3, i64 12))
  %t252 = getelementptr ptr, ptr %t251, i32 0
  %t253 = load ptr, ptr %t252
  %t254 = ptrtoint ptr %t253 to i64
  switch i64 %t254, label %case.default.255 [ i64 3, label %case.arm.3.257 i64 4, label %case.arm.4.265 ]
case.arm.3.257:
  %t259 = getelementptr ptr, ptr %t251, i32 1
  %t260 = load ptr, ptr %t259
  call void @__inc_ref(ptr %t260)
  %t261 = call ptr @__alloc(i64 16, i32 1)
  %t262 = inttoptr i64 3 to ptr
  %t263 = getelementptr ptr, ptr %t261, i32 0
  store ptr %t262, ptr %t263
  call void @__inc_ref(ptr %t260)
  %t264 = getelementptr ptr, ptr %t261, i32 1
  store ptr %t260, ptr %t264
  br label %case.end.3.258
case.end.3.258:
  br label %case.join.256
case.arm.4.265:
  %t267 = getelementptr ptr, ptr %t251, i32 1
  %t268 = load ptr, ptr %t267
  call void @__inc_ref(ptr %t268)
  call void @__inc_ref(ptr %t268)
  call void @__inc_ref(ptr %t141)
  %t269 = call ptr @__concat(ptr %t268, ptr %t141)
  %t270 = getelementptr ptr, ptr %t269, i32 0
  %t271 = load ptr, ptr %t270
  %t272 = ptrtoint ptr %t271 to i64
  switch i64 %t272, label %case.default.273 [ i64 3, label %case.arm.3.275 i64 4, label %case.arm.4.283 ]
case.arm.3.275:
  %t277 = getelementptr ptr, ptr %t269, i32 1
  %t278 = load ptr, ptr %t277
  call void @__inc_ref(ptr %t278)
  %t279 = call ptr @__alloc(i64 16, i32 1)
  %t280 = inttoptr i64 3 to ptr
  %t281 = getelementptr ptr, ptr %t279, i32 0
  store ptr %t280, ptr %t281
  call void @__inc_ref(ptr %t278)
  %t282 = getelementptr ptr, ptr %t279, i32 1
  store ptr %t278, ptr %t282
  br label %case.end.3.276
case.end.3.276:
  br label %case.join.274
case.arm.4.283:
  %t285 = getelementptr ptr, ptr %t269, i32 1
  %t286 = load ptr, ptr %t285
  call void @__inc_ref(ptr %t286)
  call void @__inc_ref(ptr %t286)
  %t287 = call ptr @__concat(ptr %t286, ptr getelementptr inbounds (i8, ptr @.str.3, i64 12))
  %t288 = getelementptr ptr, ptr %t287, i32 0
  %t289 = load ptr, ptr %t288
  %t290 = ptrtoint ptr %t289 to i64
  switch i64 %t290, label %case.default.291 [ i64 3, label %case.arm.3.293 i64 4, label %case.arm.4.301 ]
case.arm.3.293:
  %t295 = getelementptr ptr, ptr %t287, i32 1
  %t296 = load ptr, ptr %t295
  call void @__inc_ref(ptr %t296)
  %t297 = call ptr @__alloc(i64 16, i32 1)
  %t298 = inttoptr i64 3 to ptr
  %t299 = getelementptr ptr, ptr %t297, i32 0
  store ptr %t298, ptr %t299
  call void @__inc_ref(ptr %t296)
  %t300 = getelementptr ptr, ptr %t297, i32 1
  store ptr %t296, ptr %t300
  br label %case.end.3.294
case.end.3.294:
  br label %case.join.292
case.arm.4.301:
  %t303 = getelementptr ptr, ptr %t287, i32 1
  %t304 = load ptr, ptr %t303
  call void @__inc_ref(ptr %t304)
  call void @__inc_ref(ptr %t304)
  call void @__inc_ref(ptr %t178)
  %t305 = call ptr @__concat(ptr %t304, ptr %t178)
  br label %case.end.4.302
case.end.4.302:
  br label %case.join.292
case.default.291:
  unreachable
case.join.292:
  %t306 = phi ptr [ %t297, %case.end.3.294 ], [ %t305, %case.end.4.302 ]
  call void @__free_recursive(ptr %t287)
  br label %case.end.4.284
case.end.4.284:
  br label %case.join.274
case.default.273:
  unreachable
case.join.274:
  %t307 = phi ptr [ %t279, %case.end.3.276 ], [ %t306, %case.end.4.284 ]
  call void @__free_recursive(ptr %t269)
  br label %case.end.4.266
case.end.4.266:
  br label %case.join.256
case.default.255:
  unreachable
case.join.256:
  %t308 = phi ptr [ %t261, %case.end.3.258 ], [ %t307, %case.end.4.266 ]
  call void @__free_recursive(ptr %t251)
  br label %case.end.4.248
case.end.4.248:
  br label %case.join.238
case.default.237:
  unreachable
case.join.238:
  %t309 = phi ptr [ %t243, %case.end.3.240 ], [ %t308, %case.end.4.248 ]
  call void @__free_recursive(ptr %t233)
  br label %case.end.4.230
case.end.4.230:
  br label %case.join.220
case.default.219:
  unreachable
case.join.220:
  %t310 = phi ptr [ %t225, %case.end.3.222 ], [ %t309, %case.end.4.230 ]
  call void @__free_recursive(ptr %t215)
  br label %case.end.4.212
case.end.4.212:
  br label %case.join.202
case.default.201:
  unreachable
case.join.202:
  %t311 = phi ptr [ %t207, %case.end.3.204 ], [ %t310, %case.end.4.212 ]
  call void @__free_recursive(ptr %t197)
  br label %case.end.4.194
case.end.4.194:
  br label %case.join.184
case.default.183:
  unreachable
case.join.184:
  %t312 = phi ptr [ %t189, %case.end.3.186 ], [ %t311, %case.end.4.194 ]
  call void @__free_recursive(ptr %t179)
  br label %case.end.4.176
case.end.4.176:
  br label %case.join.166
case.default.165:
  unreachable
case.join.166:
  %t313 = phi ptr [ %t171, %case.end.3.168 ], [ %t312, %case.end.4.176 ]
  call void @__free_recursive(ptr %t161)
  call void @__free_recursive(ptr %t142)
  br label %case.end.4.139
case.end.4.139:
  br label %case.join.129
case.default.128:
  unreachable
case.join.129:
  %t314 = phi ptr [ %t134, %case.end.3.131 ], [ %t313, %case.end.4.139 ]
  call void @__free_recursive(ptr %t124)
  call void @__free_recursive(ptr %t109)
  br label %case.end.4.104
case.end.4.104:
  br label %case.join.94
case.default.93:
  unreachable
case.join.94:
  %t315 = phi ptr [ %t99, %case.end.3.96 ], [ %t314, %case.end.4.104 ]
  call void @__free_recursive(ptr %t89)
  call void @__free_recursive(ptr %t74)
  br label %case.end.4.69
case.end.4.69:
  br label %case.join.59
case.default.58:
  unreachable
case.join.59:
  %t316 = phi ptr [ %t64, %case.end.3.61 ], [ %t315, %case.end.4.69 ]
  call void @__free_recursive(ptr %t54)
  call void @__free_recursive(ptr %t39)
  br label %case.end.4.34
case.end.4.34:
  br label %case.join.24
case.default.23:
  unreachable
case.join.24:
  %t317 = phi ptr [ %t29, %case.end.3.26 ], [ %t316, %case.end.4.34 ]
  call void @__free_recursive(ptr %t19)
  call void @__free_recursive(ptr %t0)
  ret ptr %t317
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
  %t26 = call ptr @v_$cps$$df$andThenIO$4(ptr %t22, ptr %t23)
  %t27 = call ptr @__alloc(i64 8, i32 0)
  %t28 = inttoptr i64 20 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  %t30 = call ptr @v_$cps$$df$handleErrorIO$0(ptr %t26, ptr %t27)
  ret ptr %t30
}

define internal ptr @v_$cps$$df$handleErrorIO$0(ptr %v_io, ptr %v_$k) {
entry:
  %t3 = alloca ptr
  store ptr %v_io, ptr %t3
  %t4 = alloca ptr
  store ptr %v_$k, ptr %t4
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
  %t12 = call ptr @v_$apply$$df$handleErrorIO$0(ptr %t6, ptr %t5)
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
  %t26 = call ptr @v_$apply$$df$handleErrorIO$0(ptr %t6, ptr %t14)
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
  call void @__free_recursive(ptr %t6)
  store ptr %t31, ptr %t3
  store ptr %t51, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t52 = load ptr, ptr %t2
  ret ptr %t52
}

define internal ptr @v_$apply$$df$handleErrorIO$0(ptr %v_$k, ptr %v_$x) {
entry:
  %t3 = alloca ptr
  store ptr %v_$k, ptr %t3
  %t4 = alloca ptr
  store ptr %v_$x, ptr %t4
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
  call void @__free_recursive(ptr %t6)
  store ptr %t14, ptr %t3
  store ptr %t5, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t23 = load ptr, ptr %t2
  ret ptr %t23
}

define internal ptr @v_$cps$$df$andThenIO$4(ptr %v_io, ptr %v_$k) {
entry:
  %t3 = alloca ptr
  store ptr %v_io, ptr %t3
  %t4 = alloca ptr
  store ptr %v_$k, ptr %t4
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
  %t26 = call ptr @v_$apply$$df$andThenIO$4(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t26, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.27:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t28 = call ptr @v_$apply$$df$andThenIO$4(ptr %t6, ptr %t5)
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
  call void @__free_recursive(ptr %t6)
  store ptr %t33, ptr %t3
  store ptr %t53, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t54 = load ptr, ptr %t2
  ret ptr %t54
}

define internal ptr @v_$apply$$df$andThenIO$4(ptr %v_$k, ptr %v_$x) {
entry:
  %t3 = alloca ptr
  store ptr %v_$k, ptr %t3
  %t4 = alloca ptr
  store ptr %v_$x, ptr %t4
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
  call void @__free_recursive(ptr %t6)
  store ptr %t14, ptr %t3
  store ptr %t5, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t23 = load ptr, ptr %t2
  ret ptr %t23
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
