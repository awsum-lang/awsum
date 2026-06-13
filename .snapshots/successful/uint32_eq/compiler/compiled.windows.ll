; External C declarations
declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare ptr @memcpy(ptr, ptr, i64)
declare i64 @write(i32, ptr, i64)


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
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"T" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"F" }

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


define internal ptr @__eqUInt32(ptr %a, ptr %b) {
  %va = load i32, ptr %a
  %vb = load i32, ptr %b
  %eq = icmp eq i32 %va, %vb
  %tag = select i1 %eq, i64 1, i64 2
  %box = call ptr @__alloc(i64 8, i32 0)
  %tag_ptr = inttoptr i64 %tag to ptr
  store ptr %tag_ptr, ptr %box
  call void @__free_recursive(ptr %a)
  call void @__free_recursive(ptr %b)
  ret ptr %box
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
  %v__inl4_scrut.jslot = alloca ptr
  %t2 = call ptr @v_minUInt32()
  %t3 = call ptr @v_minUInt32()
  %t4 = call ptr @__eqUInt32(ptr %t2, ptr %t3)
  %t5 = getelementptr ptr, ptr %t4, i32 0
  %t6 = load ptr, ptr %t5
  %t7 = ptrtoint ptr %t6 to i64
  switch i64 %t7, label %case.default.8 [ i64 1, label %case.arm.1.10 i64 2, label %case.arm.2.12 ]
case.arm.1.10:
  br label %case.end.1.11
case.end.1.11:
  br label %case.join.9
case.arm.2.12:
  br label %case.end.2.13
case.end.2.13:
  br label %case.join.9
case.default.8:
  unreachable
case.join.9:
  %t14 = phi ptr [ getelementptr inbounds (i8, ptr @.str.1, i64 12), %case.end.1.11 ], [ getelementptr inbounds (i8, ptr @.str.2, i64 12), %case.end.2.13 ]
  call void @__free_recursive(ptr %t4)
  %t15 = call ptr @v_maxUInt32()
  %t16 = call ptr @v_maxUInt32()
  %t17 = call ptr @__eqUInt32(ptr %t15, ptr %t16)
  %t18 = getelementptr ptr, ptr %t17, i32 0
  %t19 = load ptr, ptr %t18
  %t20 = ptrtoint ptr %t19 to i64
  switch i64 %t20, label %case.default.21 [ i64 1, label %case.arm.1.23 i64 2, label %case.arm.2.25 ]
case.arm.1.23:
  br label %case.end.1.24
case.end.1.24:
  br label %case.join.22
case.arm.2.25:
  br label %case.end.2.26
case.end.2.26:
  br label %case.join.22
case.default.21:
  unreachable
case.join.22:
  %t27 = phi ptr [ getelementptr inbounds (i8, ptr @.str.1, i64 12), %case.end.1.24 ], [ getelementptr inbounds (i8, ptr @.str.2, i64 12), %case.end.2.26 ]
  call void @__free_recursive(ptr %t17)
  %t28 = call ptr @__concat(ptr %t14, ptr %t27)
  %t29 = getelementptr ptr, ptr %t28, i32 0
  %t30 = load ptr, ptr %t29
  %t31 = ptrtoint ptr %t30 to i64
  switch i64 %t31, label %join.case.default.32 [ i64 3, label %join.case.arm.3.33 i64 4, label %join.case.arm.4.47 ]
join.case.arm.3.33:
  %t34 = call ptr @__alloc(i64 24, i32 2)
  %t35 = inttoptr i64 7 to ptr
  %t36 = getelementptr ptr, ptr %t34, i32 0
  store ptr %t35, ptr %t36
  %t37 = getelementptr ptr, ptr %t34, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t37
  %t38 = call ptr @__alloc(i64 16, i32 1)
  %t39 = inttoptr i64 5 to ptr
  %t40 = getelementptr ptr, ptr %t38, i32 0
  store ptr %t39, ptr %t40
  %t41 = call ptr @__alloc(i64 8, i32 0)
  %t42 = inttoptr i64 0 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = getelementptr ptr, ptr %t38, i32 1
  store ptr %t41, ptr %t44
  %t45 = getelementptr ptr, ptr %t34, i32 2
  store ptr %t38, ptr %t45
  call void @__free_recursive(ptr %t28)
  br label %join.val.46
join.val.46:
  br label %join.after.1
join.case.arm.4.47:
  %t48 = getelementptr ptr, ptr %t28, i32 1
  %t49 = load ptr, ptr %t48
  call void @__inc_ref(ptr %t49)
  call void @__inc_ref(ptr %t49)
  %t50 = call ptr @v_maxUInt32()
  %t51 = call ptr @v_minUInt32()
  %t52 = call ptr @__eqUInt32(ptr %t50, ptr %t51)
  %t53 = getelementptr ptr, ptr %t52, i32 0
  %t54 = load ptr, ptr %t53
  %t55 = ptrtoint ptr %t54 to i64
  switch i64 %t55, label %case.default.56 [ i64 1, label %case.arm.1.58 i64 2, label %case.arm.2.60 ]
case.arm.1.58:
  br label %case.end.1.59
case.end.1.59:
  br label %case.join.57
case.arm.2.60:
  br label %case.end.2.61
case.end.2.61:
  br label %case.join.57
case.default.56:
  unreachable
case.join.57:
  %t62 = phi ptr [ getelementptr inbounds (i8, ptr @.str.1, i64 12), %case.end.1.59 ], [ getelementptr inbounds (i8, ptr @.str.2, i64 12), %case.end.2.61 ]
  call void @__free_recursive(ptr %t52)
  %t63 = call ptr @__concat(ptr %t49, ptr %t62)
  %t64 = getelementptr ptr, ptr %t63, i32 0
  %t65 = load ptr, ptr %t64
  %t66 = ptrtoint ptr %t65 to i64
  switch i64 %t66, label %case.default.67 [ i64 3, label %case.arm.3.69 i64 4, label %case.arm.4.77 ]
case.arm.3.69:
  %t71 = getelementptr ptr, ptr %t63, i32 1
  %t72 = load ptr, ptr %t71
  call void @__inc_ref(ptr %t72)
  %t73 = call ptr @__alloc(i64 16, i32 1)
  %t74 = inttoptr i64 3 to ptr
  %t75 = getelementptr ptr, ptr %t73, i32 0
  store ptr %t74, ptr %t75
  call void @__inc_ref(ptr %t72)
  %t76 = getelementptr ptr, ptr %t73, i32 1
  store ptr %t72, ptr %t76
  br label %case.end.3.70
case.end.3.70:
  br label %case.join.68
case.arm.4.77:
  %t79 = getelementptr ptr, ptr %t63, i32 1
  %t80 = load ptr, ptr %t79
  call void @__inc_ref(ptr %t80)
  call void @__inc_ref(ptr %t80)
  %t81 = call ptr @__concat(ptr %t80, ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  %t82 = getelementptr ptr, ptr %t81, i32 0
  %t83 = load ptr, ptr %t82
  %t84 = ptrtoint ptr %t83 to i64
  switch i64 %t84, label %case.default.85 [ i64 3, label %case.arm.3.87 i64 4, label %case.arm.4.95 ]
case.arm.3.87:
  %t89 = getelementptr ptr, ptr %t81, i32 1
  %t90 = load ptr, ptr %t89
  call void @__inc_ref(ptr %t90)
  %t91 = call ptr @__alloc(i64 16, i32 1)
  %t92 = inttoptr i64 3 to ptr
  %t93 = getelementptr ptr, ptr %t91, i32 0
  store ptr %t92, ptr %t93
  call void @__inc_ref(ptr %t90)
  %t94 = getelementptr ptr, ptr %t91, i32 1
  store ptr %t90, ptr %t94
  br label %case.end.3.88
case.end.3.88:
  br label %case.join.86
case.arm.4.95:
  %t97 = getelementptr ptr, ptr %t81, i32 1
  %t98 = load ptr, ptr %t97
  call void @__inc_ref(ptr %t98)
  call void @__inc_ref(ptr %t98)
  %t99 = call ptr @__concat(ptr %t98, ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
  br label %case.end.4.96
case.end.4.96:
  br label %case.join.86
case.default.85:
  unreachable
case.join.86:
  %t100 = phi ptr [ %t91, %case.end.3.88 ], [ %t99, %case.end.4.96 ]
  call void @__free_recursive(ptr %t81)
  br label %case.end.4.78
case.end.4.78:
  br label %case.join.68
case.default.67:
  unreachable
case.join.68:
  %t101 = phi ptr [ %t73, %case.end.3.70 ], [ %t100, %case.end.4.78 ]
  call void @__free_recursive(ptr %t63)
  call void @__free_recursive(ptr %t28)
  store ptr %t101, ptr %v__inl4_scrut.jslot
  br label %join.0
join.case.default.32:
  unreachable
join.0:
  %t102 = load ptr, ptr %v__inl4_scrut.jslot
  %t103 = getelementptr ptr, ptr %t102, i32 0
  %t104 = load ptr, ptr %t103
  %t105 = ptrtoint ptr %t104 to i64
  switch i64 %t105, label %case.default.106 [ i64 3, label %case.arm.3.108 i64 4, label %case.arm.4.122 ]
case.arm.3.108:
  %t110 = call ptr @__alloc(i64 24, i32 2)
  %t111 = inttoptr i64 7 to ptr
  %t112 = getelementptr ptr, ptr %t110, i32 0
  store ptr %t111, ptr %t112
  %t113 = getelementptr ptr, ptr %t110, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t113
  %t114 = call ptr @__alloc(i64 16, i32 1)
  %t115 = inttoptr i64 5 to ptr
  %t116 = getelementptr ptr, ptr %t114, i32 0
  store ptr %t115, ptr %t116
  %t117 = call ptr @__alloc(i64 8, i32 0)
  %t118 = inttoptr i64 0 to ptr
  %t119 = getelementptr ptr, ptr %t117, i32 0
  store ptr %t118, ptr %t119
  %t120 = getelementptr ptr, ptr %t114, i32 1
  store ptr %t117, ptr %t120
  %t121 = getelementptr ptr, ptr %t110, i32 2
  store ptr %t114, ptr %t121
  br label %case.end.3.109
case.end.3.109:
  br label %case.join.107
case.arm.4.122:
  %t124 = call ptr @__alloc(i64 24, i32 2)
  %t125 = inttoptr i64 7 to ptr
  %t126 = getelementptr ptr, ptr %t124, i32 0
  store ptr %t125, ptr %t126
  %t127 = getelementptr ptr, ptr %t102, i32 1
  %t128 = load ptr, ptr %t127
  call void @__inc_ref(ptr %t128)
  %t129 = getelementptr ptr, ptr %t124, i32 1
  store ptr %t128, ptr %t129
  %t130 = call ptr @__alloc(i64 16, i32 1)
  %t131 = inttoptr i64 5 to ptr
  %t132 = getelementptr ptr, ptr %t130, i32 0
  store ptr %t131, ptr %t132
  %t133 = call ptr @__alloc(i64 8, i32 0)
  %t134 = inttoptr i64 0 to ptr
  %t135 = getelementptr ptr, ptr %t133, i32 0
  store ptr %t134, ptr %t135
  %t136 = getelementptr ptr, ptr %t130, i32 1
  store ptr %t133, ptr %t136
  %t137 = getelementptr ptr, ptr %t124, i32 2
  store ptr %t130, ptr %t137
  br label %case.end.4.123
case.end.4.123:
  br label %case.join.107
case.default.106:
  unreachable
case.join.107:
  %t138 = phi ptr [ %t110, %case.end.3.109 ], [ %t124, %case.end.4.123 ]
  call void @__free_recursive(ptr %t102)
  br label %join.end.139
join.end.139:
  br label %join.after.1
join.after.1:
  %t140 = phi ptr [ %t34, %join.val.46 ], [ %t138, %join.end.139 ]
  ret ptr %t140
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
