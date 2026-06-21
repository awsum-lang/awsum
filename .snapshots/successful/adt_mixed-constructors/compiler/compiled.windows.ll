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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"hello" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"word:" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"num:" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"," }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"<eof>" }
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"42" }
@.str.6 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c" " }
@.str.7 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }

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

define internal ptr @v_res() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 24 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t3
  %t4 = getelementptr ptr, ptr %t0, i32 0
  %t5 = load ptr, ptr %t4
  %t6 = ptrtoint ptr %t5 to i64
  switch i64 %t6, label %case.default.7 [ i64 24, label %case.arm.24.9 i64 25, label %case.arm.25.14 i64 26, label %case.arm.26.19 i64 27, label %case.arm.27.25 ]
case.arm.24.9:
  %t11 = getelementptr ptr, ptr %t0, i32 1
  %t12 = load ptr, ptr %t11
  call void @__inc_ref(ptr %t12)
  %t13 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t12)
  br label %case.end.24.10
case.end.24.10:
  br label %case.join.8
case.arm.25.14:
  %t16 = getelementptr ptr, ptr %t0, i32 1
  %t17 = load ptr, ptr %t16
  call void @__inc_ref(ptr %t17)
  %t18 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t17)
  br label %case.end.25.15
case.end.25.15:
  br label %case.join.8
case.arm.26.19:
  %t21 = call ptr @__alloc(i64 16, i32 1)
  %t22 = inttoptr i64 4 to ptr
  %t23 = getelementptr ptr, ptr %t21, i32 0
  store ptr %t22, ptr %t23
  %t24 = getelementptr ptr, ptr %t21, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t24
  br label %case.end.26.20
case.end.26.20:
  br label %case.join.8
case.arm.27.25:
  %t27 = call ptr @__alloc(i64 16, i32 1)
  %t28 = inttoptr i64 4 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  %t30 = getelementptr ptr, ptr %t27, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t30
  br label %case.end.27.26
case.end.27.26:
  br label %case.join.8
case.default.7:
  unreachable
case.join.8:
  %t31 = phi ptr [ %t13, %case.end.24.10 ], [ %t18, %case.end.25.15 ], [ %t21, %case.end.26.20 ], [ %t27, %case.end.27.26 ]
  %t32 = getelementptr ptr, ptr %t31, i32 0
  %t33 = load ptr, ptr %t32
  %t34 = ptrtoint ptr %t33 to i64
  switch i64 %t34, label %case.default.35 [ i64 3, label %case.arm.3.37 i64 4, label %case.arm.4.45 ]
case.arm.3.37:
  %t39 = getelementptr ptr, ptr %t31, i32 1
  %t40 = load ptr, ptr %t39
  call void @__inc_ref(ptr %t40)
  %t41 = call ptr @__alloc(i64 16, i32 1)
  %t42 = inttoptr i64 3 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  call void @__inc_ref(ptr %t40)
  %t44 = getelementptr ptr, ptr %t41, i32 1
  store ptr %t40, ptr %t44
  br label %case.end.3.38
case.end.3.38:
  br label %case.join.36
case.arm.4.45:
  %t47 = getelementptr ptr, ptr %t31, i32 1
  %t48 = load ptr, ptr %t47
  call void @__inc_ref(ptr %t48)
  %t49 = call ptr @__alloc(i64 8, i32 0)
  %t50 = inttoptr i64 26 to ptr
  %t51 = getelementptr ptr, ptr %t49, i32 0
  store ptr %t50, ptr %t51
  %t52 = getelementptr ptr, ptr %t49, i32 0
  %t53 = load ptr, ptr %t52
  %t54 = ptrtoint ptr %t53 to i64
  switch i64 %t54, label %case.default.55 [ i64 24, label %case.arm.24.57 i64 25, label %case.arm.25.62 i64 26, label %case.arm.26.67 i64 27, label %case.arm.27.73 ]
case.arm.24.57:
  %t59 = getelementptr ptr, ptr %t49, i32 1
  %t60 = load ptr, ptr %t59
  call void @__inc_ref(ptr %t60)
  %t61 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t60)
  br label %case.end.24.58
case.end.24.58:
  br label %case.join.56
case.arm.25.62:
  %t64 = getelementptr ptr, ptr %t49, i32 1
  %t65 = load ptr, ptr %t64
  call void @__inc_ref(ptr %t65)
  %t66 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t65)
  br label %case.end.25.63
case.end.25.63:
  br label %case.join.56
case.arm.26.67:
  %t69 = call ptr @__alloc(i64 16, i32 1)
  %t70 = inttoptr i64 4 to ptr
  %t71 = getelementptr ptr, ptr %t69, i32 0
  store ptr %t70, ptr %t71
  %t72 = getelementptr ptr, ptr %t69, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t72
  br label %case.end.26.68
case.end.26.68:
  br label %case.join.56
case.arm.27.73:
  %t75 = call ptr @__alloc(i64 16, i32 1)
  %t76 = inttoptr i64 4 to ptr
  %t77 = getelementptr ptr, ptr %t75, i32 0
  store ptr %t76, ptr %t77
  %t78 = getelementptr ptr, ptr %t75, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t78
  br label %case.end.27.74
case.end.27.74:
  br label %case.join.56
case.default.55:
  unreachable
case.join.56:
  %t79 = phi ptr [ %t61, %case.end.24.58 ], [ %t66, %case.end.25.63 ], [ %t69, %case.end.26.68 ], [ %t75, %case.end.27.74 ]
  %t80 = getelementptr ptr, ptr %t79, i32 0
  %t81 = load ptr, ptr %t80
  %t82 = ptrtoint ptr %t81 to i64
  switch i64 %t82, label %case.default.83 [ i64 3, label %case.arm.3.85 i64 4, label %case.arm.4.93 ]
case.arm.3.85:
  %t87 = getelementptr ptr, ptr %t79, i32 1
  %t88 = load ptr, ptr %t87
  call void @__inc_ref(ptr %t88)
  %t89 = call ptr @__alloc(i64 16, i32 1)
  %t90 = inttoptr i64 3 to ptr
  %t91 = getelementptr ptr, ptr %t89, i32 0
  store ptr %t90, ptr %t91
  call void @__inc_ref(ptr %t88)
  %t92 = getelementptr ptr, ptr %t89, i32 1
  store ptr %t88, ptr %t92
  br label %case.end.3.86
case.end.3.86:
  br label %case.join.84
case.arm.4.93:
  %t95 = getelementptr ptr, ptr %t79, i32 1
  %t96 = load ptr, ptr %t95
  call void @__inc_ref(ptr %t96)
  %t97 = call ptr @__alloc(i64 16, i32 1)
  %t98 = inttoptr i64 25 to ptr
  %t99 = getelementptr ptr, ptr %t97, i32 0
  store ptr %t98, ptr %t99
  %t100 = getelementptr ptr, ptr %t97, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.5, i64 12), ptr %t100
  %t101 = getelementptr ptr, ptr %t97, i32 0
  %t102 = load ptr, ptr %t101
  %t103 = ptrtoint ptr %t102 to i64
  switch i64 %t103, label %case.default.104 [ i64 24, label %case.arm.24.106 i64 25, label %case.arm.25.111 i64 26, label %case.arm.26.116 i64 27, label %case.arm.27.122 ]
case.arm.24.106:
  %t108 = getelementptr ptr, ptr %t97, i32 1
  %t109 = load ptr, ptr %t108
  call void @__inc_ref(ptr %t109)
  %t110 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t109)
  br label %case.end.24.107
case.end.24.107:
  br label %case.join.105
case.arm.25.111:
  %t113 = getelementptr ptr, ptr %t97, i32 1
  %t114 = load ptr, ptr %t113
  call void @__inc_ref(ptr %t114)
  %t115 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t114)
  br label %case.end.25.112
case.end.25.112:
  br label %case.join.105
case.arm.26.116:
  %t118 = call ptr @__alloc(i64 16, i32 1)
  %t119 = inttoptr i64 4 to ptr
  %t120 = getelementptr ptr, ptr %t118, i32 0
  store ptr %t119, ptr %t120
  %t121 = getelementptr ptr, ptr %t118, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t121
  br label %case.end.26.117
case.end.26.117:
  br label %case.join.105
case.arm.27.122:
  %t124 = call ptr @__alloc(i64 16, i32 1)
  %t125 = inttoptr i64 4 to ptr
  %t126 = getelementptr ptr, ptr %t124, i32 0
  store ptr %t125, ptr %t126
  %t127 = getelementptr ptr, ptr %t124, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t127
  br label %case.end.27.123
case.end.27.123:
  br label %case.join.105
case.default.104:
  unreachable
case.join.105:
  %t128 = phi ptr [ %t110, %case.end.24.107 ], [ %t115, %case.end.25.112 ], [ %t118, %case.end.26.117 ], [ %t124, %case.end.27.123 ]
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
  %t146 = call ptr @__alloc(i64 8, i32 0)
  %t147 = inttoptr i64 27 to ptr
  %t148 = getelementptr ptr, ptr %t146, i32 0
  store ptr %t147, ptr %t148
  %t149 = getelementptr ptr, ptr %t146, i32 0
  %t150 = load ptr, ptr %t149
  %t151 = ptrtoint ptr %t150 to i64
  switch i64 %t151, label %case.default.152 [ i64 24, label %case.arm.24.154 i64 25, label %case.arm.25.159 i64 26, label %case.arm.26.164 i64 27, label %case.arm.27.170 ]
case.arm.24.154:
  %t156 = getelementptr ptr, ptr %t146, i32 1
  %t157 = load ptr, ptr %t156
  call void @__inc_ref(ptr %t157)
  %t158 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t157)
  br label %case.end.24.155
case.end.24.155:
  br label %case.join.153
case.arm.25.159:
  %t161 = getelementptr ptr, ptr %t146, i32 1
  %t162 = load ptr, ptr %t161
  call void @__inc_ref(ptr %t162)
  %t163 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t162)
  br label %case.end.25.160
case.end.25.160:
  br label %case.join.153
case.arm.26.164:
  %t166 = call ptr @__alloc(i64 16, i32 1)
  %t167 = inttoptr i64 4 to ptr
  %t168 = getelementptr ptr, ptr %t166, i32 0
  store ptr %t167, ptr %t168
  %t169 = getelementptr ptr, ptr %t166, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t169
  br label %case.end.26.165
case.end.26.165:
  br label %case.join.153
case.arm.27.170:
  %t172 = call ptr @__alloc(i64 16, i32 1)
  %t173 = inttoptr i64 4 to ptr
  %t174 = getelementptr ptr, ptr %t172, i32 0
  store ptr %t173, ptr %t174
  %t175 = getelementptr ptr, ptr %t172, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t175
  br label %case.end.27.171
case.end.27.171:
  br label %case.join.153
case.default.152:
  unreachable
case.join.153:
  %t176 = phi ptr [ %t158, %case.end.24.155 ], [ %t163, %case.end.25.160 ], [ %t166, %case.end.26.165 ], [ %t172, %case.end.27.171 ]
  %t177 = getelementptr ptr, ptr %t176, i32 0
  %t178 = load ptr, ptr %t177
  %t179 = ptrtoint ptr %t178 to i64
  switch i64 %t179, label %case.default.180 [ i64 3, label %case.arm.3.182 i64 4, label %case.arm.4.190 ]
case.arm.3.182:
  %t184 = getelementptr ptr, ptr %t176, i32 1
  %t185 = load ptr, ptr %t184
  call void @__inc_ref(ptr %t185)
  %t186 = call ptr @__alloc(i64 16, i32 1)
  %t187 = inttoptr i64 3 to ptr
  %t188 = getelementptr ptr, ptr %t186, i32 0
  store ptr %t187, ptr %t188
  call void @__inc_ref(ptr %t185)
  %t189 = getelementptr ptr, ptr %t186, i32 1
  store ptr %t185, ptr %t189
  br label %case.end.3.183
case.end.3.183:
  br label %case.join.181
case.arm.4.190:
  %t192 = getelementptr ptr, ptr %t176, i32 1
  %t193 = load ptr, ptr %t192
  call void @__inc_ref(ptr %t193)
  call void @__inc_ref(ptr %t48)
  %t194 = call ptr @__concat(ptr %t48, ptr getelementptr inbounds (i8, ptr @.str.6, i64 12))
  %t195 = getelementptr ptr, ptr %t194, i32 0
  %t196 = load ptr, ptr %t195
  %t197 = ptrtoint ptr %t196 to i64
  switch i64 %t197, label %case.default.198 [ i64 3, label %case.arm.3.200 i64 4, label %case.arm.4.208 ]
case.arm.3.200:
  %t202 = getelementptr ptr, ptr %t194, i32 1
  %t203 = load ptr, ptr %t202
  call void @__inc_ref(ptr %t203)
  %t204 = call ptr @__alloc(i64 16, i32 1)
  %t205 = inttoptr i64 3 to ptr
  %t206 = getelementptr ptr, ptr %t204, i32 0
  store ptr %t205, ptr %t206
  call void @__inc_ref(ptr %t203)
  %t207 = getelementptr ptr, ptr %t204, i32 1
  store ptr %t203, ptr %t207
  br label %case.end.3.201
case.end.3.201:
  br label %case.join.199
case.arm.4.208:
  %t210 = getelementptr ptr, ptr %t194, i32 1
  %t211 = load ptr, ptr %t210
  call void @__inc_ref(ptr %t211)
  call void @__inc_ref(ptr %t211)
  call void @__inc_ref(ptr %t96)
  %t212 = call ptr @__concat(ptr %t211, ptr %t96)
  %t213 = getelementptr ptr, ptr %t212, i32 0
  %t214 = load ptr, ptr %t213
  %t215 = ptrtoint ptr %t214 to i64
  switch i64 %t215, label %case.default.216 [ i64 3, label %case.arm.3.218 i64 4, label %case.arm.4.226 ]
case.arm.3.218:
  %t220 = getelementptr ptr, ptr %t212, i32 1
  %t221 = load ptr, ptr %t220
  call void @__inc_ref(ptr %t221)
  %t222 = call ptr @__alloc(i64 16, i32 1)
  %t223 = inttoptr i64 3 to ptr
  %t224 = getelementptr ptr, ptr %t222, i32 0
  store ptr %t223, ptr %t224
  call void @__inc_ref(ptr %t221)
  %t225 = getelementptr ptr, ptr %t222, i32 1
  store ptr %t221, ptr %t225
  br label %case.end.3.219
case.end.3.219:
  br label %case.join.217
case.arm.4.226:
  %t228 = getelementptr ptr, ptr %t212, i32 1
  %t229 = load ptr, ptr %t228
  call void @__inc_ref(ptr %t229)
  call void @__inc_ref(ptr %t229)
  %t230 = call ptr @__concat(ptr %t229, ptr getelementptr inbounds (i8, ptr @.str.6, i64 12))
  %t231 = getelementptr ptr, ptr %t230, i32 0
  %t232 = load ptr, ptr %t231
  %t233 = ptrtoint ptr %t232 to i64
  switch i64 %t233, label %case.default.234 [ i64 3, label %case.arm.3.236 i64 4, label %case.arm.4.244 ]
case.arm.3.236:
  %t238 = getelementptr ptr, ptr %t230, i32 1
  %t239 = load ptr, ptr %t238
  call void @__inc_ref(ptr %t239)
  %t240 = call ptr @__alloc(i64 16, i32 1)
  %t241 = inttoptr i64 3 to ptr
  %t242 = getelementptr ptr, ptr %t240, i32 0
  store ptr %t241, ptr %t242
  call void @__inc_ref(ptr %t239)
  %t243 = getelementptr ptr, ptr %t240, i32 1
  store ptr %t239, ptr %t243
  br label %case.end.3.237
case.end.3.237:
  br label %case.join.235
case.arm.4.244:
  %t246 = getelementptr ptr, ptr %t230, i32 1
  %t247 = load ptr, ptr %t246
  call void @__inc_ref(ptr %t247)
  call void @__inc_ref(ptr %t247)
  call void @__inc_ref(ptr %t145)
  %t248 = call ptr @__concat(ptr %t247, ptr %t145)
  %t249 = getelementptr ptr, ptr %t248, i32 0
  %t250 = load ptr, ptr %t249
  %t251 = ptrtoint ptr %t250 to i64
  switch i64 %t251, label %case.default.252 [ i64 3, label %case.arm.3.254 i64 4, label %case.arm.4.262 ]
case.arm.3.254:
  %t256 = getelementptr ptr, ptr %t248, i32 1
  %t257 = load ptr, ptr %t256
  call void @__inc_ref(ptr %t257)
  %t258 = call ptr @__alloc(i64 16, i32 1)
  %t259 = inttoptr i64 3 to ptr
  %t260 = getelementptr ptr, ptr %t258, i32 0
  store ptr %t259, ptr %t260
  call void @__inc_ref(ptr %t257)
  %t261 = getelementptr ptr, ptr %t258, i32 1
  store ptr %t257, ptr %t261
  br label %case.end.3.255
case.end.3.255:
  br label %case.join.253
case.arm.4.262:
  %t264 = getelementptr ptr, ptr %t248, i32 1
  %t265 = load ptr, ptr %t264
  call void @__inc_ref(ptr %t265)
  call void @__inc_ref(ptr %t265)
  %t266 = call ptr @__concat(ptr %t265, ptr getelementptr inbounds (i8, ptr @.str.6, i64 12))
  %t267 = getelementptr ptr, ptr %t266, i32 0
  %t268 = load ptr, ptr %t267
  %t269 = ptrtoint ptr %t268 to i64
  switch i64 %t269, label %case.default.270 [ i64 3, label %case.arm.3.272 i64 4, label %case.arm.4.280 ]
case.arm.3.272:
  %t274 = getelementptr ptr, ptr %t266, i32 1
  %t275 = load ptr, ptr %t274
  call void @__inc_ref(ptr %t275)
  %t276 = call ptr @__alloc(i64 16, i32 1)
  %t277 = inttoptr i64 3 to ptr
  %t278 = getelementptr ptr, ptr %t276, i32 0
  store ptr %t277, ptr %t278
  call void @__inc_ref(ptr %t275)
  %t279 = getelementptr ptr, ptr %t276, i32 1
  store ptr %t275, ptr %t279
  br label %case.end.3.273
case.end.3.273:
  br label %case.join.271
case.arm.4.280:
  %t282 = getelementptr ptr, ptr %t266, i32 1
  %t283 = load ptr, ptr %t282
  call void @__inc_ref(ptr %t283)
  call void @__inc_ref(ptr %t283)
  call void @__inc_ref(ptr %t193)
  %t284 = call ptr @__concat(ptr %t283, ptr %t193)
  br label %case.end.4.281
case.end.4.281:
  br label %case.join.271
case.default.270:
  unreachable
case.join.271:
  %t285 = phi ptr [ %t276, %case.end.3.273 ], [ %t284, %case.end.4.281 ]
  call void @__free_recursive(ptr %t266)
  br label %case.end.4.263
case.end.4.263:
  br label %case.join.253
case.default.252:
  unreachable
case.join.253:
  %t286 = phi ptr [ %t258, %case.end.3.255 ], [ %t285, %case.end.4.263 ]
  call void @__free_recursive(ptr %t248)
  br label %case.end.4.245
case.end.4.245:
  br label %case.join.235
case.default.234:
  unreachable
case.join.235:
  %t287 = phi ptr [ %t240, %case.end.3.237 ], [ %t286, %case.end.4.245 ]
  call void @__free_recursive(ptr %t230)
  br label %case.end.4.227
case.end.4.227:
  br label %case.join.217
case.default.216:
  unreachable
case.join.217:
  %t288 = phi ptr [ %t222, %case.end.3.219 ], [ %t287, %case.end.4.227 ]
  call void @__free_recursive(ptr %t212)
  br label %case.end.4.209
case.end.4.209:
  br label %case.join.199
case.default.198:
  unreachable
case.join.199:
  %t289 = phi ptr [ %t204, %case.end.3.201 ], [ %t288, %case.end.4.209 ]
  call void @__free_recursive(ptr %t194)
  br label %case.end.4.191
case.end.4.191:
  br label %case.join.181
case.default.180:
  unreachable
case.join.181:
  %t290 = phi ptr [ %t186, %case.end.3.183 ], [ %t289, %case.end.4.191 ]
  call void @__free_recursive(ptr %t176)
  call void @__free_recursive(ptr %t146)
  br label %case.end.4.143
case.end.4.143:
  br label %case.join.133
case.default.132:
  unreachable
case.join.133:
  %t291 = phi ptr [ %t138, %case.end.3.135 ], [ %t290, %case.end.4.143 ]
  call void @__free_recursive(ptr %t128)
  call void @__free_recursive(ptr %t97)
  br label %case.end.4.94
case.end.4.94:
  br label %case.join.84
case.default.83:
  unreachable
case.join.84:
  %t292 = phi ptr [ %t89, %case.end.3.86 ], [ %t291, %case.end.4.94 ]
  call void @__free_recursive(ptr %t79)
  call void @__free_recursive(ptr %t49)
  br label %case.end.4.46
case.end.4.46:
  br label %case.join.36
case.default.35:
  unreachable
case.join.36:
  %t293 = phi ptr [ %t41, %case.end.3.38 ], [ %t292, %case.end.4.46 ]
  call void @__free_recursive(ptr %t31)
  call void @__free_recursive(ptr %t0)
  ret ptr %t293
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
  %t24 = inttoptr i64 30 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  %t26 = call ptr @v__cps__df_andThenIO_4(ptr %t22, ptr %t23)
  %t27 = call ptr @__alloc(i64 8, i32 0)
  %t28 = inttoptr i64 28 to ptr
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
  store ptr getelementptr inbounds (i8, ptr @.str.7, i64 12), ptr %t17
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
  %t36 = inttoptr i64 29 to ptr
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
  %t47 = inttoptr i64 29 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 28, label %tco.case.arm.28.11 i64 29, label %tco.case.arm.29.12 ]
tco.case.arm.28.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.29.12:
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
  %t38 = inttoptr i64 31 to ptr
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
  %t49 = inttoptr i64 31 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 30, label %tco.case.arm.30.11 i64 31, label %tco.case.arm.31.12 ]
tco.case.arm.30.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.31.12:
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
