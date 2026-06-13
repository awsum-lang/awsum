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
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"False" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"True" }

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

define internal ptr @v_main() {
  %v__inl10_scrut.jslot = alloca ptr
  %v__inl8_scrut.jslot = alloca ptr
  %t2 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
  %t3 = getelementptr ptr, ptr %t2, i32 0
  %t4 = load ptr, ptr %t3
  %t5 = ptrtoint ptr %t4 to i64
  switch i64 %t5, label %join.case.default.6 [ i64 3, label %join.case.arm.3.7 i64 4, label %join.case.arm.4.21 ]
join.case.arm.3.7:
  %t8 = call ptr @__alloc(i64 24, i32 2)
  %t9 = inttoptr i64 7 to ptr
  %t10 = getelementptr ptr, ptr %t8, i32 0
  store ptr %t9, ptr %t10
  %t11 = getelementptr ptr, ptr %t8, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t11
  %t12 = call ptr @__alloc(i64 16, i32 1)
  %t13 = inttoptr i64 5 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = call ptr @__alloc(i64 8, i32 0)
  %t16 = inttoptr i64 0 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t15, ptr %t18
  %t19 = getelementptr ptr, ptr %t8, i32 2
  store ptr %t12, ptr %t19
  call void @__free_recursive(ptr %t2)
  br label %join.val.20
join.val.20:
  br label %join.after.1
join.case.arm.4.21:
  %t22 = getelementptr ptr, ptr %t2, i32 1
  %t23 = load ptr, ptr %t22
  call void @__inc_ref(ptr %t23)
  call void @__inc_ref(ptr %t23)
  %t24 = call ptr @__alloc(i64 8, i32 0)
  %t25 = inttoptr i64 1 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t29 = getelementptr ptr, ptr %t24, i32 0
  %t30 = load ptr, ptr %t29
  %t31 = ptrtoint ptr %t30 to i64
  switch i64 %t31, label %join.case.default.32 [ i64 1, label %join.case.arm.1.33 i64 2, label %join.case.arm.2.35 ]
join.case.arm.1.33:
  br label %join.val.34
join.val.34:
  br label %join.after.28
join.case.arm.2.35:
  call void @__inc_ref(ptr %t24)
  store ptr %t24, ptr %v__inl8_scrut.jslot
  br label %join.27
join.case.default.32:
  unreachable
join.27:
  %t36 = load ptr, ptr %v__inl8_scrut.jslot
  %t37 = getelementptr ptr, ptr %t36, i32 0
  %t38 = load ptr, ptr %t37
  %t39 = ptrtoint ptr %t38 to i64
  switch i64 %t39, label %case.default.40 [ i64 1, label %case.arm.1.42 i64 2, label %case.arm.2.44 ]
case.arm.1.42:
  br label %case.end.1.43
case.end.1.43:
  br label %case.join.41
case.arm.2.44:
  br label %case.end.2.45
case.end.2.45:
  br label %case.join.41
case.default.40:
  unreachable
case.join.41:
  %t46 = phi ptr [ getelementptr inbounds (i8, ptr @.str.2, i64 12), %case.end.1.43 ], [ getelementptr inbounds (i8, ptr @.str.1, i64 12), %case.end.2.45 ]
  call void @__free_recursive(ptr %t36)
  br label %join.end.47
join.end.47:
  br label %join.after.28
join.after.28:
  %t48 = phi ptr [ getelementptr inbounds (i8, ptr @.str.1, i64 12), %join.val.34 ], [ %t46, %join.end.47 ]
  call void @__free_recursive(ptr %t24)
  %t49 = call ptr @__concat(ptr %t23, ptr %t48)
  %t50 = getelementptr ptr, ptr %t49, i32 0
  %t51 = load ptr, ptr %t50
  %t52 = ptrtoint ptr %t51 to i64
  switch i64 %t52, label %case.default.53 [ i64 3, label %case.arm.3.55 i64 4, label %case.arm.4.63 ]
case.arm.3.55:
  %t57 = getelementptr ptr, ptr %t49, i32 1
  %t58 = load ptr, ptr %t57
  call void @__inc_ref(ptr %t58)
  %t59 = call ptr @__alloc(i64 16, i32 1)
  %t60 = inttoptr i64 3 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  call void @__inc_ref(ptr %t58)
  %t62 = getelementptr ptr, ptr %t59, i32 1
  store ptr %t58, ptr %t62
  br label %case.end.3.56
case.end.3.56:
  br label %case.join.54
case.arm.4.63:
  %t65 = getelementptr ptr, ptr %t49, i32 1
  %t66 = load ptr, ptr %t65
  call void @__inc_ref(ptr %t66)
  call void @__inc_ref(ptr %t66)
  %t67 = call ptr @__concat(ptr %t66, ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
  %t68 = getelementptr ptr, ptr %t67, i32 0
  %t69 = load ptr, ptr %t68
  %t70 = ptrtoint ptr %t69 to i64
  switch i64 %t70, label %case.default.71 [ i64 3, label %case.arm.3.73 i64 4, label %case.arm.4.81 ]
case.arm.3.73:
  %t75 = getelementptr ptr, ptr %t67, i32 1
  %t76 = load ptr, ptr %t75
  call void @__inc_ref(ptr %t76)
  %t77 = call ptr @__alloc(i64 16, i32 1)
  %t78 = inttoptr i64 3 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  call void @__inc_ref(ptr %t76)
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t76, ptr %t80
  br label %case.end.3.74
case.end.3.74:
  br label %case.join.72
case.arm.4.81:
  %t83 = getelementptr ptr, ptr %t67, i32 1
  %t84 = load ptr, ptr %t83
  call void @__inc_ref(ptr %t84)
  call void @__inc_ref(ptr %t84)
  %t85 = call ptr @__concat(ptr %t84, ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  %t86 = getelementptr ptr, ptr %t85, i32 0
  %t87 = load ptr, ptr %t86
  %t88 = ptrtoint ptr %t87 to i64
  switch i64 %t88, label %case.default.89 [ i64 3, label %case.arm.3.91 i64 4, label %case.arm.4.99 ]
case.arm.3.91:
  %t93 = getelementptr ptr, ptr %t85, i32 1
  %t94 = load ptr, ptr %t93
  call void @__inc_ref(ptr %t94)
  %t95 = call ptr @__alloc(i64 16, i32 1)
  %t96 = inttoptr i64 3 to ptr
  %t97 = getelementptr ptr, ptr %t95, i32 0
  store ptr %t96, ptr %t97
  call void @__inc_ref(ptr %t94)
  %t98 = getelementptr ptr, ptr %t95, i32 1
  store ptr %t94, ptr %t98
  br label %case.end.3.92
case.end.3.92:
  br label %case.join.90
case.arm.4.99:
  %t101 = getelementptr ptr, ptr %t85, i32 1
  %t102 = load ptr, ptr %t101
  call void @__inc_ref(ptr %t102)
  call void @__inc_ref(ptr %t102)
  %t103 = call ptr @__concat(ptr %t102, ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
  br label %case.end.4.100
case.end.4.100:
  br label %case.join.90
case.default.89:
  unreachable
case.join.90:
  %t104 = phi ptr [ %t95, %case.end.3.92 ], [ %t103, %case.end.4.100 ]
  call void @__free_recursive(ptr %t85)
  br label %case.end.4.82
case.end.4.82:
  br label %case.join.72
case.default.71:
  unreachable
case.join.72:
  %t105 = phi ptr [ %t77, %case.end.3.74 ], [ %t104, %case.end.4.82 ]
  call void @__free_recursive(ptr %t67)
  br label %case.end.4.64
case.end.4.64:
  br label %case.join.54
case.default.53:
  unreachable
case.join.54:
  %t106 = phi ptr [ %t59, %case.end.3.56 ], [ %t105, %case.end.4.64 ]
  call void @__free_recursive(ptr %t49)
  call void @__free_recursive(ptr %t2)
  store ptr %t106, ptr %v__inl10_scrut.jslot
  br label %join.0
join.case.default.6:
  unreachable
join.0:
  %t107 = load ptr, ptr %v__inl10_scrut.jslot
  %t108 = getelementptr ptr, ptr %t107, i32 0
  %t109 = load ptr, ptr %t108
  %t110 = ptrtoint ptr %t109 to i64
  switch i64 %t110, label %case.default.111 [ i64 3, label %case.arm.3.113 i64 4, label %case.arm.4.127 ]
case.arm.3.113:
  %t115 = call ptr @__alloc(i64 24, i32 2)
  %t116 = inttoptr i64 7 to ptr
  %t117 = getelementptr ptr, ptr %t115, i32 0
  store ptr %t116, ptr %t117
  %t118 = getelementptr ptr, ptr %t115, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t118
  %t119 = call ptr @__alloc(i64 16, i32 1)
  %t120 = inttoptr i64 5 to ptr
  %t121 = getelementptr ptr, ptr %t119, i32 0
  store ptr %t120, ptr %t121
  %t122 = call ptr @__alloc(i64 8, i32 0)
  %t123 = inttoptr i64 0 to ptr
  %t124 = getelementptr ptr, ptr %t122, i32 0
  store ptr %t123, ptr %t124
  %t125 = getelementptr ptr, ptr %t119, i32 1
  store ptr %t122, ptr %t125
  %t126 = getelementptr ptr, ptr %t115, i32 2
  store ptr %t119, ptr %t126
  br label %case.end.3.114
case.end.3.114:
  br label %case.join.112
case.arm.4.127:
  %t129 = call ptr @__alloc(i64 24, i32 2)
  %t130 = inttoptr i64 7 to ptr
  %t131 = getelementptr ptr, ptr %t129, i32 0
  store ptr %t130, ptr %t131
  %t132 = getelementptr ptr, ptr %t107, i32 1
  %t133 = load ptr, ptr %t132
  call void @__inc_ref(ptr %t133)
  %t134 = getelementptr ptr, ptr %t129, i32 1
  store ptr %t133, ptr %t134
  %t135 = call ptr @__alloc(i64 16, i32 1)
  %t136 = inttoptr i64 5 to ptr
  %t137 = getelementptr ptr, ptr %t135, i32 0
  store ptr %t136, ptr %t137
  %t138 = call ptr @__alloc(i64 8, i32 0)
  %t139 = inttoptr i64 0 to ptr
  %t140 = getelementptr ptr, ptr %t138, i32 0
  store ptr %t139, ptr %t140
  %t141 = getelementptr ptr, ptr %t135, i32 1
  store ptr %t138, ptr %t141
  %t142 = getelementptr ptr, ptr %t129, i32 2
  store ptr %t135, ptr %t142
  br label %case.end.4.128
case.end.4.128:
  br label %case.join.112
case.default.111:
  unreachable
case.join.112:
  %t143 = phi ptr [ %t115, %case.end.3.114 ], [ %t129, %case.end.4.128 ]
  call void @__free_recursive(ptr %t107)
  br label %join.end.144
join.end.144:
  br label %join.after.1
join.after.1:
  %t145 = phi ptr [ %t8, %join.val.20 ], [ %t143, %join.end.144 ]
  ret ptr %t145
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
