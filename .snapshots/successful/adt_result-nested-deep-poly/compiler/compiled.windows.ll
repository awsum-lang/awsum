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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"1" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"," }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"2" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"3" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"4" }
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"5" }
@.str.6 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"6" }
@.str.7 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"7" }
@.str.8 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"8" }
@.str.9 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }

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
  %t3 = call ptr @__alloc(i64 16, i32 1)
  %t4 = inttoptr i64 24 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = call ptr @__alloc(i64 16, i32 1)
  %t7 = inttoptr i64 24 to ptr
  %t8 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t7, ptr %t8
  %t9 = getelementptr ptr, ptr %t6, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t9
  %t10 = getelementptr ptr, ptr %t3, i32 1
  store ptr %t6, ptr %t10
  %t11 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t11
  %t12 = getelementptr ptr, ptr %t0, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t13, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %case.default.17 [ i64 24, label %case.arm.24.19 i64 25, label %case.arm.25.25 ]
case.arm.24.19:
  %t21 = getelementptr ptr, ptr %t13, i32 1
  %t22 = load ptr, ptr %t21
  call void @__inc_ref(ptr %t22)
  %t23 = getelementptr ptr, ptr %t22, i32 1
  %t24 = load ptr, ptr %t23
  call void @__inc_ref(ptr %t24)
  br label %case.end.24.20
case.end.24.20:
  br label %case.join.18
case.arm.25.25:
  %t27 = getelementptr ptr, ptr %t13, i32 1
  %t28 = load ptr, ptr %t27
  call void @__inc_ref(ptr %t28)
  %t29 = getelementptr ptr, ptr %t28, i32 1
  %t30 = load ptr, ptr %t29
  call void @__inc_ref(ptr %t30)
  br label %case.end.25.26
case.end.25.26:
  br label %case.join.18
case.default.17:
  unreachable
case.join.18:
  %t31 = phi ptr [ %t24, %case.end.24.20 ], [ %t30, %case.end.25.26 ]
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t0)
  %t32 = call ptr @__concat(ptr %t31, ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  %t33 = getelementptr ptr, ptr %t32, i32 0
  %t34 = load ptr, ptr %t33
  %t35 = ptrtoint ptr %t34 to i64
  switch i64 %t35, label %case.default.36 [ i64 3, label %case.arm.3.38 i64 4, label %case.arm.4.46 ]
case.arm.3.38:
  %t40 = getelementptr ptr, ptr %t32, i32 1
  %t41 = load ptr, ptr %t40
  call void @__inc_ref(ptr %t41)
  %t42 = call ptr @__alloc(i64 16, i32 1)
  %t43 = inttoptr i64 3 to ptr
  %t44 = getelementptr ptr, ptr %t42, i32 0
  store ptr %t43, ptr %t44
  call void @__inc_ref(ptr %t41)
  %t45 = getelementptr ptr, ptr %t42, i32 1
  store ptr %t41, ptr %t45
  br label %case.end.3.39
case.end.3.39:
  br label %case.join.37
case.arm.4.46:
  %t48 = getelementptr ptr, ptr %t32, i32 1
  %t49 = load ptr, ptr %t48
  call void @__inc_ref(ptr %t49)
  call void @__inc_ref(ptr %t49)
  %t50 = call ptr @__alloc(i64 16, i32 1)
  %t51 = inttoptr i64 24 to ptr
  %t52 = getelementptr ptr, ptr %t50, i32 0
  store ptr %t51, ptr %t52
  %t53 = call ptr @__alloc(i64 16, i32 1)
  %t54 = inttoptr i64 24 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  %t56 = call ptr @__alloc(i64 16, i32 1)
  %t57 = inttoptr i64 25 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  %t59 = getelementptr ptr, ptr %t56, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t59
  %t60 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t56, ptr %t60
  %t61 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t53, ptr %t61
  %t62 = getelementptr ptr, ptr %t50, i32 1
  %t63 = load ptr, ptr %t62
  call void @__inc_ref(ptr %t63)
  %t64 = getelementptr ptr, ptr %t63, i32 0
  %t65 = load ptr, ptr %t64
  %t66 = ptrtoint ptr %t65 to i64
  switch i64 %t66, label %case.default.67 [ i64 24, label %case.arm.24.69 i64 25, label %case.arm.25.75 ]
case.arm.24.69:
  %t71 = getelementptr ptr, ptr %t63, i32 1
  %t72 = load ptr, ptr %t71
  call void @__inc_ref(ptr %t72)
  %t73 = getelementptr ptr, ptr %t72, i32 1
  %t74 = load ptr, ptr %t73
  call void @__inc_ref(ptr %t74)
  br label %case.end.24.70
case.end.24.70:
  br label %case.join.68
case.arm.25.75:
  %t77 = getelementptr ptr, ptr %t63, i32 1
  %t78 = load ptr, ptr %t77
  call void @__inc_ref(ptr %t78)
  %t79 = getelementptr ptr, ptr %t78, i32 1
  %t80 = load ptr, ptr %t79
  call void @__inc_ref(ptr %t80)
  br label %case.end.25.76
case.end.25.76:
  br label %case.join.68
case.default.67:
  unreachable
case.join.68:
  %t81 = phi ptr [ %t74, %case.end.24.70 ], [ %t80, %case.end.25.76 ]
  call void @__free_recursive(ptr %t63)
  call void @__free_recursive(ptr %t50)
  %t82 = call ptr @__concat(ptr %t49, ptr %t81)
  %t83 = getelementptr ptr, ptr %t82, i32 0
  %t84 = load ptr, ptr %t83
  %t85 = ptrtoint ptr %t84 to i64
  switch i64 %t85, label %case.default.86 [ i64 3, label %case.arm.3.88 i64 4, label %case.arm.4.96 ]
case.arm.3.88:
  %t90 = getelementptr ptr, ptr %t82, i32 1
  %t91 = load ptr, ptr %t90
  call void @__inc_ref(ptr %t91)
  %t92 = call ptr @__alloc(i64 16, i32 1)
  %t93 = inttoptr i64 3 to ptr
  %t94 = getelementptr ptr, ptr %t92, i32 0
  store ptr %t93, ptr %t94
  call void @__inc_ref(ptr %t91)
  %t95 = getelementptr ptr, ptr %t92, i32 1
  store ptr %t91, ptr %t95
  br label %case.end.3.89
case.end.3.89:
  br label %case.join.87
case.arm.4.96:
  %t98 = getelementptr ptr, ptr %t82, i32 1
  %t99 = load ptr, ptr %t98
  call void @__inc_ref(ptr %t99)
  call void @__inc_ref(ptr %t99)
  %t100 = call ptr @__concat(ptr %t99, ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  %t101 = getelementptr ptr, ptr %t100, i32 0
  %t102 = load ptr, ptr %t101
  %t103 = ptrtoint ptr %t102 to i64
  switch i64 %t103, label %case.default.104 [ i64 3, label %case.arm.3.106 i64 4, label %case.arm.4.114 ]
case.arm.3.106:
  %t108 = getelementptr ptr, ptr %t100, i32 1
  %t109 = load ptr, ptr %t108
  call void @__inc_ref(ptr %t109)
  %t110 = call ptr @__alloc(i64 16, i32 1)
  %t111 = inttoptr i64 3 to ptr
  %t112 = getelementptr ptr, ptr %t110, i32 0
  store ptr %t111, ptr %t112
  call void @__inc_ref(ptr %t109)
  %t113 = getelementptr ptr, ptr %t110, i32 1
  store ptr %t109, ptr %t113
  br label %case.end.3.107
case.end.3.107:
  br label %case.join.105
case.arm.4.114:
  %t116 = getelementptr ptr, ptr %t100, i32 1
  %t117 = load ptr, ptr %t116
  call void @__inc_ref(ptr %t117)
  call void @__inc_ref(ptr %t117)
  %t118 = call ptr @__alloc(i64 16, i32 1)
  %t119 = inttoptr i64 24 to ptr
  %t120 = getelementptr ptr, ptr %t118, i32 0
  store ptr %t119, ptr %t120
  %t121 = call ptr @__alloc(i64 16, i32 1)
  %t122 = inttoptr i64 25 to ptr
  %t123 = getelementptr ptr, ptr %t121, i32 0
  store ptr %t122, ptr %t123
  %t124 = call ptr @__alloc(i64 16, i32 1)
  %t125 = inttoptr i64 24 to ptr
  %t126 = getelementptr ptr, ptr %t124, i32 0
  store ptr %t125, ptr %t126
  %t127 = getelementptr ptr, ptr %t124, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t127
  %t128 = getelementptr ptr, ptr %t121, i32 1
  store ptr %t124, ptr %t128
  %t129 = getelementptr ptr, ptr %t118, i32 1
  store ptr %t121, ptr %t129
  %t130 = getelementptr ptr, ptr %t118, i32 1
  %t131 = load ptr, ptr %t130
  call void @__inc_ref(ptr %t131)
  %t132 = getelementptr ptr, ptr %t131, i32 0
  %t133 = load ptr, ptr %t132
  %t134 = ptrtoint ptr %t133 to i64
  switch i64 %t134, label %case.default.135 [ i64 24, label %case.arm.24.137 i64 25, label %case.arm.25.143 ]
case.arm.24.137:
  %t139 = getelementptr ptr, ptr %t131, i32 1
  %t140 = load ptr, ptr %t139
  call void @__inc_ref(ptr %t140)
  %t141 = getelementptr ptr, ptr %t140, i32 1
  %t142 = load ptr, ptr %t141
  call void @__inc_ref(ptr %t142)
  br label %case.end.24.138
case.end.24.138:
  br label %case.join.136
case.arm.25.143:
  %t145 = getelementptr ptr, ptr %t131, i32 1
  %t146 = load ptr, ptr %t145
  call void @__inc_ref(ptr %t146)
  %t147 = getelementptr ptr, ptr %t146, i32 1
  %t148 = load ptr, ptr %t147
  call void @__inc_ref(ptr %t148)
  br label %case.end.25.144
case.end.25.144:
  br label %case.join.136
case.default.135:
  unreachable
case.join.136:
  %t149 = phi ptr [ %t142, %case.end.24.138 ], [ %t148, %case.end.25.144 ]
  call void @__free_recursive(ptr %t131)
  call void @__free_recursive(ptr %t118)
  %t150 = call ptr @__concat(ptr %t117, ptr %t149)
  %t151 = getelementptr ptr, ptr %t150, i32 0
  %t152 = load ptr, ptr %t151
  %t153 = ptrtoint ptr %t152 to i64
  switch i64 %t153, label %case.default.154 [ i64 3, label %case.arm.3.156 i64 4, label %case.arm.4.164 ]
case.arm.3.156:
  %t158 = getelementptr ptr, ptr %t150, i32 1
  %t159 = load ptr, ptr %t158
  call void @__inc_ref(ptr %t159)
  %t160 = call ptr @__alloc(i64 16, i32 1)
  %t161 = inttoptr i64 3 to ptr
  %t162 = getelementptr ptr, ptr %t160, i32 0
  store ptr %t161, ptr %t162
  call void @__inc_ref(ptr %t159)
  %t163 = getelementptr ptr, ptr %t160, i32 1
  store ptr %t159, ptr %t163
  br label %case.end.3.157
case.end.3.157:
  br label %case.join.155
case.arm.4.164:
  %t166 = getelementptr ptr, ptr %t150, i32 1
  %t167 = load ptr, ptr %t166
  call void @__inc_ref(ptr %t167)
  call void @__inc_ref(ptr %t167)
  %t168 = call ptr @__concat(ptr %t167, ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  %t169 = getelementptr ptr, ptr %t168, i32 0
  %t170 = load ptr, ptr %t169
  %t171 = ptrtoint ptr %t170 to i64
  switch i64 %t171, label %case.default.172 [ i64 3, label %case.arm.3.174 i64 4, label %case.arm.4.182 ]
case.arm.3.174:
  %t176 = getelementptr ptr, ptr %t168, i32 1
  %t177 = load ptr, ptr %t176
  call void @__inc_ref(ptr %t177)
  %t178 = call ptr @__alloc(i64 16, i32 1)
  %t179 = inttoptr i64 3 to ptr
  %t180 = getelementptr ptr, ptr %t178, i32 0
  store ptr %t179, ptr %t180
  call void @__inc_ref(ptr %t177)
  %t181 = getelementptr ptr, ptr %t178, i32 1
  store ptr %t177, ptr %t181
  br label %case.end.3.175
case.end.3.175:
  br label %case.join.173
case.arm.4.182:
  %t184 = getelementptr ptr, ptr %t168, i32 1
  %t185 = load ptr, ptr %t184
  call void @__inc_ref(ptr %t185)
  call void @__inc_ref(ptr %t185)
  %t186 = call ptr @__alloc(i64 16, i32 1)
  %t187 = inttoptr i64 24 to ptr
  %t188 = getelementptr ptr, ptr %t186, i32 0
  store ptr %t187, ptr %t188
  %t189 = call ptr @__alloc(i64 16, i32 1)
  %t190 = inttoptr i64 25 to ptr
  %t191 = getelementptr ptr, ptr %t189, i32 0
  store ptr %t190, ptr %t191
  %t192 = call ptr @__alloc(i64 16, i32 1)
  %t193 = inttoptr i64 25 to ptr
  %t194 = getelementptr ptr, ptr %t192, i32 0
  store ptr %t193, ptr %t194
  %t195 = getelementptr ptr, ptr %t192, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t195
  %t196 = getelementptr ptr, ptr %t189, i32 1
  store ptr %t192, ptr %t196
  %t197 = getelementptr ptr, ptr %t186, i32 1
  store ptr %t189, ptr %t197
  %t198 = getelementptr ptr, ptr %t186, i32 1
  %t199 = load ptr, ptr %t198
  call void @__inc_ref(ptr %t199)
  %t200 = getelementptr ptr, ptr %t199, i32 0
  %t201 = load ptr, ptr %t200
  %t202 = ptrtoint ptr %t201 to i64
  switch i64 %t202, label %case.default.203 [ i64 24, label %case.arm.24.205 i64 25, label %case.arm.25.211 ]
case.arm.24.205:
  %t207 = getelementptr ptr, ptr %t199, i32 1
  %t208 = load ptr, ptr %t207
  call void @__inc_ref(ptr %t208)
  %t209 = getelementptr ptr, ptr %t208, i32 1
  %t210 = load ptr, ptr %t209
  call void @__inc_ref(ptr %t210)
  br label %case.end.24.206
case.end.24.206:
  br label %case.join.204
case.arm.25.211:
  %t213 = getelementptr ptr, ptr %t199, i32 1
  %t214 = load ptr, ptr %t213
  call void @__inc_ref(ptr %t214)
  %t215 = getelementptr ptr, ptr %t214, i32 1
  %t216 = load ptr, ptr %t215
  call void @__inc_ref(ptr %t216)
  br label %case.end.25.212
case.end.25.212:
  br label %case.join.204
case.default.203:
  unreachable
case.join.204:
  %t217 = phi ptr [ %t210, %case.end.24.206 ], [ %t216, %case.end.25.212 ]
  call void @__free_recursive(ptr %t199)
  call void @__free_recursive(ptr %t186)
  %t218 = call ptr @__concat(ptr %t185, ptr %t217)
  %t219 = getelementptr ptr, ptr %t218, i32 0
  %t220 = load ptr, ptr %t219
  %t221 = ptrtoint ptr %t220 to i64
  switch i64 %t221, label %case.default.222 [ i64 3, label %case.arm.3.224 i64 4, label %case.arm.4.232 ]
case.arm.3.224:
  %t226 = getelementptr ptr, ptr %t218, i32 1
  %t227 = load ptr, ptr %t226
  call void @__inc_ref(ptr %t227)
  %t228 = call ptr @__alloc(i64 16, i32 1)
  %t229 = inttoptr i64 3 to ptr
  %t230 = getelementptr ptr, ptr %t228, i32 0
  store ptr %t229, ptr %t230
  call void @__inc_ref(ptr %t227)
  %t231 = getelementptr ptr, ptr %t228, i32 1
  store ptr %t227, ptr %t231
  br label %case.end.3.225
case.end.3.225:
  br label %case.join.223
case.arm.4.232:
  %t234 = getelementptr ptr, ptr %t218, i32 1
  %t235 = load ptr, ptr %t234
  call void @__inc_ref(ptr %t235)
  call void @__inc_ref(ptr %t235)
  %t236 = call ptr @__concat(ptr %t235, ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  %t237 = getelementptr ptr, ptr %t236, i32 0
  %t238 = load ptr, ptr %t237
  %t239 = ptrtoint ptr %t238 to i64
  switch i64 %t239, label %case.default.240 [ i64 3, label %case.arm.3.242 i64 4, label %case.arm.4.250 ]
case.arm.3.242:
  %t244 = getelementptr ptr, ptr %t236, i32 1
  %t245 = load ptr, ptr %t244
  call void @__inc_ref(ptr %t245)
  %t246 = call ptr @__alloc(i64 16, i32 1)
  %t247 = inttoptr i64 3 to ptr
  %t248 = getelementptr ptr, ptr %t246, i32 0
  store ptr %t247, ptr %t248
  call void @__inc_ref(ptr %t245)
  %t249 = getelementptr ptr, ptr %t246, i32 1
  store ptr %t245, ptr %t249
  br label %case.end.3.243
case.end.3.243:
  br label %case.join.241
case.arm.4.250:
  %t252 = getelementptr ptr, ptr %t236, i32 1
  %t253 = load ptr, ptr %t252
  call void @__inc_ref(ptr %t253)
  call void @__inc_ref(ptr %t253)
  %t254 = call ptr @__alloc(i64 16, i32 1)
  %t255 = inttoptr i64 25 to ptr
  %t256 = getelementptr ptr, ptr %t254, i32 0
  store ptr %t255, ptr %t256
  %t257 = call ptr @__alloc(i64 16, i32 1)
  %t258 = inttoptr i64 24 to ptr
  %t259 = getelementptr ptr, ptr %t257, i32 0
  store ptr %t258, ptr %t259
  %t260 = call ptr @__alloc(i64 16, i32 1)
  %t261 = inttoptr i64 24 to ptr
  %t262 = getelementptr ptr, ptr %t260, i32 0
  store ptr %t261, ptr %t262
  %t263 = getelementptr ptr, ptr %t260, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.5, i64 12), ptr %t263
  %t264 = getelementptr ptr, ptr %t257, i32 1
  store ptr %t260, ptr %t264
  %t265 = getelementptr ptr, ptr %t254, i32 1
  store ptr %t257, ptr %t265
  %t266 = getelementptr ptr, ptr %t254, i32 1
  %t267 = load ptr, ptr %t266
  call void @__inc_ref(ptr %t267)
  %t268 = getelementptr ptr, ptr %t267, i32 0
  %t269 = load ptr, ptr %t268
  %t270 = ptrtoint ptr %t269 to i64
  switch i64 %t270, label %case.default.271 [ i64 24, label %case.arm.24.273 i64 25, label %case.arm.25.279 ]
case.arm.24.273:
  %t275 = getelementptr ptr, ptr %t267, i32 1
  %t276 = load ptr, ptr %t275
  call void @__inc_ref(ptr %t276)
  %t277 = getelementptr ptr, ptr %t276, i32 1
  %t278 = load ptr, ptr %t277
  call void @__inc_ref(ptr %t278)
  br label %case.end.24.274
case.end.24.274:
  br label %case.join.272
case.arm.25.279:
  %t281 = getelementptr ptr, ptr %t267, i32 1
  %t282 = load ptr, ptr %t281
  call void @__inc_ref(ptr %t282)
  %t283 = getelementptr ptr, ptr %t282, i32 1
  %t284 = load ptr, ptr %t283
  call void @__inc_ref(ptr %t284)
  br label %case.end.25.280
case.end.25.280:
  br label %case.join.272
case.default.271:
  unreachable
case.join.272:
  %t285 = phi ptr [ %t278, %case.end.24.274 ], [ %t284, %case.end.25.280 ]
  call void @__free_recursive(ptr %t267)
  call void @__free_recursive(ptr %t254)
  %t286 = call ptr @__concat(ptr %t253, ptr %t285)
  %t287 = getelementptr ptr, ptr %t286, i32 0
  %t288 = load ptr, ptr %t287
  %t289 = ptrtoint ptr %t288 to i64
  switch i64 %t289, label %case.default.290 [ i64 3, label %case.arm.3.292 i64 4, label %case.arm.4.300 ]
case.arm.3.292:
  %t294 = getelementptr ptr, ptr %t286, i32 1
  %t295 = load ptr, ptr %t294
  call void @__inc_ref(ptr %t295)
  %t296 = call ptr @__alloc(i64 16, i32 1)
  %t297 = inttoptr i64 3 to ptr
  %t298 = getelementptr ptr, ptr %t296, i32 0
  store ptr %t297, ptr %t298
  call void @__inc_ref(ptr %t295)
  %t299 = getelementptr ptr, ptr %t296, i32 1
  store ptr %t295, ptr %t299
  br label %case.end.3.293
case.end.3.293:
  br label %case.join.291
case.arm.4.300:
  %t302 = getelementptr ptr, ptr %t286, i32 1
  %t303 = load ptr, ptr %t302
  call void @__inc_ref(ptr %t303)
  call void @__inc_ref(ptr %t303)
  %t304 = call ptr @__concat(ptr %t303, ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  %t305 = getelementptr ptr, ptr %t304, i32 0
  %t306 = load ptr, ptr %t305
  %t307 = ptrtoint ptr %t306 to i64
  switch i64 %t307, label %case.default.308 [ i64 3, label %case.arm.3.310 i64 4, label %case.arm.4.318 ]
case.arm.3.310:
  %t312 = getelementptr ptr, ptr %t304, i32 1
  %t313 = load ptr, ptr %t312
  call void @__inc_ref(ptr %t313)
  %t314 = call ptr @__alloc(i64 16, i32 1)
  %t315 = inttoptr i64 3 to ptr
  %t316 = getelementptr ptr, ptr %t314, i32 0
  store ptr %t315, ptr %t316
  call void @__inc_ref(ptr %t313)
  %t317 = getelementptr ptr, ptr %t314, i32 1
  store ptr %t313, ptr %t317
  br label %case.end.3.311
case.end.3.311:
  br label %case.join.309
case.arm.4.318:
  %t320 = getelementptr ptr, ptr %t304, i32 1
  %t321 = load ptr, ptr %t320
  call void @__inc_ref(ptr %t321)
  call void @__inc_ref(ptr %t321)
  %t322 = call ptr @__alloc(i64 16, i32 1)
  %t323 = inttoptr i64 25 to ptr
  %t324 = getelementptr ptr, ptr %t322, i32 0
  store ptr %t323, ptr %t324
  %t325 = call ptr @__alloc(i64 16, i32 1)
  %t326 = inttoptr i64 24 to ptr
  %t327 = getelementptr ptr, ptr %t325, i32 0
  store ptr %t326, ptr %t327
  %t328 = call ptr @__alloc(i64 16, i32 1)
  %t329 = inttoptr i64 25 to ptr
  %t330 = getelementptr ptr, ptr %t328, i32 0
  store ptr %t329, ptr %t330
  %t331 = getelementptr ptr, ptr %t328, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.6, i64 12), ptr %t331
  %t332 = getelementptr ptr, ptr %t325, i32 1
  store ptr %t328, ptr %t332
  %t333 = getelementptr ptr, ptr %t322, i32 1
  store ptr %t325, ptr %t333
  %t334 = getelementptr ptr, ptr %t322, i32 1
  %t335 = load ptr, ptr %t334
  call void @__inc_ref(ptr %t335)
  %t336 = getelementptr ptr, ptr %t335, i32 0
  %t337 = load ptr, ptr %t336
  %t338 = ptrtoint ptr %t337 to i64
  switch i64 %t338, label %case.default.339 [ i64 24, label %case.arm.24.341 i64 25, label %case.arm.25.347 ]
case.arm.24.341:
  %t343 = getelementptr ptr, ptr %t335, i32 1
  %t344 = load ptr, ptr %t343
  call void @__inc_ref(ptr %t344)
  %t345 = getelementptr ptr, ptr %t344, i32 1
  %t346 = load ptr, ptr %t345
  call void @__inc_ref(ptr %t346)
  br label %case.end.24.342
case.end.24.342:
  br label %case.join.340
case.arm.25.347:
  %t349 = getelementptr ptr, ptr %t335, i32 1
  %t350 = load ptr, ptr %t349
  call void @__inc_ref(ptr %t350)
  %t351 = getelementptr ptr, ptr %t350, i32 1
  %t352 = load ptr, ptr %t351
  call void @__inc_ref(ptr %t352)
  br label %case.end.25.348
case.end.25.348:
  br label %case.join.340
case.default.339:
  unreachable
case.join.340:
  %t353 = phi ptr [ %t346, %case.end.24.342 ], [ %t352, %case.end.25.348 ]
  call void @__free_recursive(ptr %t335)
  call void @__free_recursive(ptr %t322)
  %t354 = call ptr @__concat(ptr %t321, ptr %t353)
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
  %t372 = call ptr @__concat(ptr %t371, ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
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
  %t390 = call ptr @__alloc(i64 16, i32 1)
  %t391 = inttoptr i64 25 to ptr
  %t392 = getelementptr ptr, ptr %t390, i32 0
  store ptr %t391, ptr %t392
  %t393 = call ptr @__alloc(i64 16, i32 1)
  %t394 = inttoptr i64 25 to ptr
  %t395 = getelementptr ptr, ptr %t393, i32 0
  store ptr %t394, ptr %t395
  %t396 = call ptr @__alloc(i64 16, i32 1)
  %t397 = inttoptr i64 24 to ptr
  %t398 = getelementptr ptr, ptr %t396, i32 0
  store ptr %t397, ptr %t398
  %t399 = getelementptr ptr, ptr %t396, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.7, i64 12), ptr %t399
  %t400 = getelementptr ptr, ptr %t393, i32 1
  store ptr %t396, ptr %t400
  %t401 = getelementptr ptr, ptr %t390, i32 1
  store ptr %t393, ptr %t401
  %t402 = getelementptr ptr, ptr %t390, i32 1
  %t403 = load ptr, ptr %t402
  call void @__inc_ref(ptr %t403)
  %t404 = getelementptr ptr, ptr %t403, i32 0
  %t405 = load ptr, ptr %t404
  %t406 = ptrtoint ptr %t405 to i64
  switch i64 %t406, label %case.default.407 [ i64 24, label %case.arm.24.409 i64 25, label %case.arm.25.415 ]
case.arm.24.409:
  %t411 = getelementptr ptr, ptr %t403, i32 1
  %t412 = load ptr, ptr %t411
  call void @__inc_ref(ptr %t412)
  %t413 = getelementptr ptr, ptr %t412, i32 1
  %t414 = load ptr, ptr %t413
  call void @__inc_ref(ptr %t414)
  br label %case.end.24.410
case.end.24.410:
  br label %case.join.408
case.arm.25.415:
  %t417 = getelementptr ptr, ptr %t403, i32 1
  %t418 = load ptr, ptr %t417
  call void @__inc_ref(ptr %t418)
  %t419 = getelementptr ptr, ptr %t418, i32 1
  %t420 = load ptr, ptr %t419
  call void @__inc_ref(ptr %t420)
  br label %case.end.25.416
case.end.25.416:
  br label %case.join.408
case.default.407:
  unreachable
case.join.408:
  %t421 = phi ptr [ %t414, %case.end.24.410 ], [ %t420, %case.end.25.416 ]
  call void @__free_recursive(ptr %t403)
  call void @__free_recursive(ptr %t390)
  %t422 = call ptr @__concat(ptr %t389, ptr %t421)
  %t423 = getelementptr ptr, ptr %t422, i32 0
  %t424 = load ptr, ptr %t423
  %t425 = ptrtoint ptr %t424 to i64
  switch i64 %t425, label %case.default.426 [ i64 3, label %case.arm.3.428 i64 4, label %case.arm.4.436 ]
case.arm.3.428:
  %t430 = getelementptr ptr, ptr %t422, i32 1
  %t431 = load ptr, ptr %t430
  call void @__inc_ref(ptr %t431)
  %t432 = call ptr @__alloc(i64 16, i32 1)
  %t433 = inttoptr i64 3 to ptr
  %t434 = getelementptr ptr, ptr %t432, i32 0
  store ptr %t433, ptr %t434
  call void @__inc_ref(ptr %t431)
  %t435 = getelementptr ptr, ptr %t432, i32 1
  store ptr %t431, ptr %t435
  br label %case.end.3.429
case.end.3.429:
  br label %case.join.427
case.arm.4.436:
  %t438 = getelementptr ptr, ptr %t422, i32 1
  %t439 = load ptr, ptr %t438
  call void @__inc_ref(ptr %t439)
  call void @__inc_ref(ptr %t439)
  %t440 = call ptr @__concat(ptr %t439, ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  %t441 = getelementptr ptr, ptr %t440, i32 0
  %t442 = load ptr, ptr %t441
  %t443 = ptrtoint ptr %t442 to i64
  switch i64 %t443, label %case.default.444 [ i64 3, label %case.arm.3.446 i64 4, label %case.arm.4.454 ]
case.arm.3.446:
  %t448 = getelementptr ptr, ptr %t440, i32 1
  %t449 = load ptr, ptr %t448
  call void @__inc_ref(ptr %t449)
  %t450 = call ptr @__alloc(i64 16, i32 1)
  %t451 = inttoptr i64 3 to ptr
  %t452 = getelementptr ptr, ptr %t450, i32 0
  store ptr %t451, ptr %t452
  call void @__inc_ref(ptr %t449)
  %t453 = getelementptr ptr, ptr %t450, i32 1
  store ptr %t449, ptr %t453
  br label %case.end.3.447
case.end.3.447:
  br label %case.join.445
case.arm.4.454:
  %t456 = getelementptr ptr, ptr %t440, i32 1
  %t457 = load ptr, ptr %t456
  call void @__inc_ref(ptr %t457)
  call void @__inc_ref(ptr %t457)
  %t458 = call ptr @__alloc(i64 16, i32 1)
  %t459 = inttoptr i64 25 to ptr
  %t460 = getelementptr ptr, ptr %t458, i32 0
  store ptr %t459, ptr %t460
  %t461 = call ptr @__alloc(i64 16, i32 1)
  %t462 = inttoptr i64 25 to ptr
  %t463 = getelementptr ptr, ptr %t461, i32 0
  store ptr %t462, ptr %t463
  %t464 = call ptr @__alloc(i64 16, i32 1)
  %t465 = inttoptr i64 25 to ptr
  %t466 = getelementptr ptr, ptr %t464, i32 0
  store ptr %t465, ptr %t466
  %t467 = getelementptr ptr, ptr %t464, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.8, i64 12), ptr %t467
  %t468 = getelementptr ptr, ptr %t461, i32 1
  store ptr %t464, ptr %t468
  %t469 = getelementptr ptr, ptr %t458, i32 1
  store ptr %t461, ptr %t469
  %t470 = getelementptr ptr, ptr %t458, i32 1
  %t471 = load ptr, ptr %t470
  call void @__inc_ref(ptr %t471)
  %t472 = getelementptr ptr, ptr %t471, i32 0
  %t473 = load ptr, ptr %t472
  %t474 = ptrtoint ptr %t473 to i64
  switch i64 %t474, label %case.default.475 [ i64 24, label %case.arm.24.477 i64 25, label %case.arm.25.483 ]
case.arm.24.477:
  %t479 = getelementptr ptr, ptr %t471, i32 1
  %t480 = load ptr, ptr %t479
  call void @__inc_ref(ptr %t480)
  %t481 = getelementptr ptr, ptr %t480, i32 1
  %t482 = load ptr, ptr %t481
  call void @__inc_ref(ptr %t482)
  br label %case.end.24.478
case.end.24.478:
  br label %case.join.476
case.arm.25.483:
  %t485 = getelementptr ptr, ptr %t471, i32 1
  %t486 = load ptr, ptr %t485
  call void @__inc_ref(ptr %t486)
  %t487 = getelementptr ptr, ptr %t486, i32 1
  %t488 = load ptr, ptr %t487
  call void @__inc_ref(ptr %t488)
  br label %case.end.25.484
case.end.25.484:
  br label %case.join.476
case.default.475:
  unreachable
case.join.476:
  %t489 = phi ptr [ %t482, %case.end.24.478 ], [ %t488, %case.end.25.484 ]
  call void @__free_recursive(ptr %t471)
  call void @__free_recursive(ptr %t458)
  %t490 = call ptr @__concat(ptr %t457, ptr %t489)
  br label %case.end.4.455
case.end.4.455:
  br label %case.join.445
case.default.444:
  unreachable
case.join.445:
  %t491 = phi ptr [ %t450, %case.end.3.447 ], [ %t490, %case.end.4.455 ]
  call void @__free_recursive(ptr %t440)
  br label %case.end.4.437
case.end.4.437:
  br label %case.join.427
case.default.426:
  unreachable
case.join.427:
  %t492 = phi ptr [ %t432, %case.end.3.429 ], [ %t491, %case.end.4.437 ]
  call void @__free_recursive(ptr %t422)
  br label %case.end.4.387
case.end.4.387:
  br label %case.join.377
case.default.376:
  unreachable
case.join.377:
  %t493 = phi ptr [ %t382, %case.end.3.379 ], [ %t492, %case.end.4.387 ]
  call void @__free_recursive(ptr %t372)
  br label %case.end.4.369
case.end.4.369:
  br label %case.join.359
case.default.358:
  unreachable
case.join.359:
  %t494 = phi ptr [ %t364, %case.end.3.361 ], [ %t493, %case.end.4.369 ]
  call void @__free_recursive(ptr %t354)
  br label %case.end.4.319
case.end.4.319:
  br label %case.join.309
case.default.308:
  unreachable
case.join.309:
  %t495 = phi ptr [ %t314, %case.end.3.311 ], [ %t494, %case.end.4.319 ]
  call void @__free_recursive(ptr %t304)
  br label %case.end.4.301
case.end.4.301:
  br label %case.join.291
case.default.290:
  unreachable
case.join.291:
  %t496 = phi ptr [ %t296, %case.end.3.293 ], [ %t495, %case.end.4.301 ]
  call void @__free_recursive(ptr %t286)
  br label %case.end.4.251
case.end.4.251:
  br label %case.join.241
case.default.240:
  unreachable
case.join.241:
  %t497 = phi ptr [ %t246, %case.end.3.243 ], [ %t496, %case.end.4.251 ]
  call void @__free_recursive(ptr %t236)
  br label %case.end.4.233
case.end.4.233:
  br label %case.join.223
case.default.222:
  unreachable
case.join.223:
  %t498 = phi ptr [ %t228, %case.end.3.225 ], [ %t497, %case.end.4.233 ]
  call void @__free_recursive(ptr %t218)
  br label %case.end.4.183
case.end.4.183:
  br label %case.join.173
case.default.172:
  unreachable
case.join.173:
  %t499 = phi ptr [ %t178, %case.end.3.175 ], [ %t498, %case.end.4.183 ]
  call void @__free_recursive(ptr %t168)
  br label %case.end.4.165
case.end.4.165:
  br label %case.join.155
case.default.154:
  unreachable
case.join.155:
  %t500 = phi ptr [ %t160, %case.end.3.157 ], [ %t499, %case.end.4.165 ]
  call void @__free_recursive(ptr %t150)
  br label %case.end.4.115
case.end.4.115:
  br label %case.join.105
case.default.104:
  unreachable
case.join.105:
  %t501 = phi ptr [ %t110, %case.end.3.107 ], [ %t500, %case.end.4.115 ]
  call void @__free_recursive(ptr %t100)
  br label %case.end.4.97
case.end.4.97:
  br label %case.join.87
case.default.86:
  unreachable
case.join.87:
  %t502 = phi ptr [ %t92, %case.end.3.89 ], [ %t501, %case.end.4.97 ]
  call void @__free_recursive(ptr %t82)
  br label %case.end.4.47
case.end.4.47:
  br label %case.join.37
case.default.36:
  unreachable
case.join.37:
  %t503 = phi ptr [ %t42, %case.end.3.39 ], [ %t502, %case.end.4.47 ]
  call void @__free_recursive(ptr %t32)
  ret ptr %t503
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
  %t24 = inttoptr i64 28 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  %t26 = call ptr @v__cps__df_andThenIO_4(ptr %t22, ptr %t23)
  %t27 = call ptr @__alloc(i64 8, i32 0)
  %t28 = inttoptr i64 26 to ptr
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
  store ptr getelementptr inbounds (i8, ptr @.str.9, i64 12), ptr %t17
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
  %t36 = inttoptr i64 27 to ptr
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
  %t47 = inttoptr i64 27 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 26, label %tco.case.arm.26.11 i64 27, label %tco.case.arm.27.12 ]
tco.case.arm.26.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.27.12:
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
  %t38 = inttoptr i64 29 to ptr
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
  %t49 = inttoptr i64 29 to ptr
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

declare i32 @_setmode(i32, i32)

define i32 @main(i32 %argc_posix, ptr %argv_posix) {
entry:
  call i32 @_setmode(i32 1, i32 32768)
  call i32 @_setmode(i32 0, i32 32768)
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
