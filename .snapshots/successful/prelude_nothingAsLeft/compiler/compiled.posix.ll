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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"hi" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"first" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [6 x i8]} { i32 0, i32 0, i32 0, i32 6, i32 6, [6 x i8] c"second" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [12 x i8]} { i32 0, i32 0, i32 0, i32 12, i32 12, [12 x i8] c"Left Missing" }
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [6 x i8]} { i32 0, i32 0, i32 0, i32 6, i32 6, [6 x i8] c"Right " }
@.str.6 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"|" }

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
  %v__inl76_scrut.jslot = alloca ptr
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 3 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 8, i32 0)
  %t4 = inttoptr i64 24 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  %t7 = call ptr @__alloc(i64 16, i32 1)
  %t8 = inttoptr i64 4 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = getelementptr ptr, ptr %t7, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t10
  %t11 = call ptr @__alloc(i64 24, i32 2)
  %t12 = inttoptr i64 14 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  %t14 = getelementptr ptr, ptr %t11, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t14
  %t15 = call ptr @__alloc(i64 24, i32 2)
  %t16 = inttoptr i64 14 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = getelementptr ptr, ptr %t15, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t18
  %t19 = call ptr @__alloc(i64 8, i32 0)
  %t20 = inttoptr i64 13 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr ptr, ptr %t15, i32 2
  store ptr %t19, ptr %t22
  %t23 = getelementptr ptr, ptr %t11, i32 2
  store ptr %t15, ptr %t23
  %t24 = getelementptr ptr, ptr %t11, i32 0
  %t25 = load ptr, ptr %t24
  %t26 = ptrtoint ptr %t25 to i64
  switch i64 %t26, label %case.default.27 [ i64 13, label %case.arm.13.29 i64 14, label %case.arm.14.38 ]
case.arm.13.29:
  %t31 = call ptr @__alloc(i64 16, i32 1)
  %t32 = inttoptr i64 3 to ptr
  %t33 = getelementptr ptr, ptr %t31, i32 0
  store ptr %t32, ptr %t33
  %t34 = call ptr @__alloc(i64 8, i32 0)
  %t35 = inttoptr i64 24 to ptr
  %t36 = getelementptr ptr, ptr %t34, i32 0
  store ptr %t35, ptr %t36
  %t37 = getelementptr ptr, ptr %t31, i32 1
  store ptr %t34, ptr %t37
  br label %case.end.13.30
case.end.13.30:
  br label %case.join.28
case.arm.14.38:
  %t40 = call ptr @__alloc(i64 16, i32 1)
  %t41 = inttoptr i64 4 to ptr
  %t42 = getelementptr ptr, ptr %t40, i32 0
  store ptr %t41, ptr %t42
  %t43 = getelementptr ptr, ptr %t11, i32 1
  %t44 = load ptr, ptr %t43
  call void @__inc_ref(ptr %t44)
  %t45 = getelementptr ptr, ptr %t40, i32 1
  store ptr %t44, ptr %t45
  br label %case.end.14.39
case.end.14.39:
  br label %case.join.28
case.default.27:
  unreachable
case.join.28:
  %t46 = phi ptr [ %t31, %case.end.13.30 ], [ %t40, %case.end.14.39 ]
  call void @__free_recursive(ptr %t11)
  %t49 = getelementptr ptr, ptr %t0, i32 0
  %t50 = load ptr, ptr %t49
  %t51 = ptrtoint ptr %t50 to i64
  switch i64 %t51, label %case.default.52 [ i64 3, label %case.arm.3.54 i64 4, label %case.arm.4.60 ]
case.arm.3.54:
  %t56 = call ptr @__alloc(i64 16, i32 1)
  %t57 = inttoptr i64 4 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  %t59 = getelementptr ptr, ptr %t56, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t59
  br label %case.end.3.55
case.end.3.55:
  br label %case.join.53
case.arm.4.60:
  %t62 = getelementptr ptr, ptr %t0, i32 1
  %t63 = load ptr, ptr %t62
  call void @__inc_ref(ptr %t63)
  %t64 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.5, i64 12), ptr %t63)
  br label %case.end.4.61
case.end.4.61:
  br label %case.join.53
case.default.52:
  unreachable
case.join.53:
  %t65 = phi ptr [ %t56, %case.end.3.55 ], [ %t64, %case.end.4.61 ]
  %t66 = getelementptr ptr, ptr %t65, i32 0
  %t67 = load ptr, ptr %t66
  %t68 = ptrtoint ptr %t67 to i64
  switch i64 %t68, label %join.case.default.69 [ i64 3, label %join.case.arm.3.70 i64 4, label %join.case.arm.4.84 ]
join.case.arm.3.70:
  %t71 = call ptr @__alloc(i64 24, i32 2)
  %t72 = inttoptr i64 7 to ptr
  %t73 = getelementptr ptr, ptr %t71, i32 0
  store ptr %t72, ptr %t73
  %t74 = getelementptr ptr, ptr %t71, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t74
  %t75 = call ptr @__alloc(i64 16, i32 1)
  %t76 = inttoptr i64 5 to ptr
  %t77 = getelementptr ptr, ptr %t75, i32 0
  store ptr %t76, ptr %t77
  %t78 = call ptr @__alloc(i64 8, i32 0)
  %t79 = inttoptr i64 0 to ptr
  %t80 = getelementptr ptr, ptr %t78, i32 0
  store ptr %t79, ptr %t80
  %t81 = getelementptr ptr, ptr %t75, i32 1
  store ptr %t78, ptr %t81
  %t82 = getelementptr ptr, ptr %t71, i32 2
  store ptr %t75, ptr %t82
  call void @__free_recursive(ptr %t65)
  br label %join.val.83
join.val.83:
  br label %join.after.48
join.case.arm.4.84:
  %t85 = getelementptr ptr, ptr %t65, i32 1
  %t86 = load ptr, ptr %t85
  call void @__inc_ref(ptr %t86)
  %t87 = getelementptr ptr, ptr %t7, i32 0
  %t88 = load ptr, ptr %t87
  %t89 = ptrtoint ptr %t88 to i64
  switch i64 %t89, label %case.default.90 [ i64 3, label %case.arm.3.92 i64 4, label %case.arm.4.98 ]
case.arm.3.92:
  %t94 = call ptr @__alloc(i64 16, i32 1)
  %t95 = inttoptr i64 4 to ptr
  %t96 = getelementptr ptr, ptr %t94, i32 0
  store ptr %t95, ptr %t96
  %t97 = getelementptr ptr, ptr %t94, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t97
  br label %case.end.3.93
case.end.3.93:
  br label %case.join.91
case.arm.4.98:
  %t100 = getelementptr ptr, ptr %t7, i32 1
  %t101 = load ptr, ptr %t100
  call void @__inc_ref(ptr %t101)
  %t102 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.5, i64 12), ptr %t101)
  br label %case.end.4.99
case.end.4.99:
  br label %case.join.91
case.default.90:
  unreachable
case.join.91:
  %t103 = phi ptr [ %t94, %case.end.3.93 ], [ %t102, %case.end.4.99 ]
  %t104 = getelementptr ptr, ptr %t103, i32 0
  %t105 = load ptr, ptr %t104
  %t106 = ptrtoint ptr %t105 to i64
  switch i64 %t106, label %case.default.107 [ i64 3, label %case.arm.3.109 i64 4, label %case.arm.4.117 ]
case.arm.3.109:
  %t111 = getelementptr ptr, ptr %t103, i32 1
  %t112 = load ptr, ptr %t111
  call void @__inc_ref(ptr %t112)
  %t113 = call ptr @__alloc(i64 16, i32 1)
  %t114 = inttoptr i64 3 to ptr
  %t115 = getelementptr ptr, ptr %t113, i32 0
  store ptr %t114, ptr %t115
  call void @__inc_ref(ptr %t112)
  %t116 = getelementptr ptr, ptr %t113, i32 1
  store ptr %t112, ptr %t116
  br label %case.end.3.110
case.end.3.110:
  br label %case.join.108
case.arm.4.117:
  %t119 = getelementptr ptr, ptr %t103, i32 1
  %t120 = load ptr, ptr %t119
  call void @__inc_ref(ptr %t120)
  %t121 = getelementptr ptr, ptr %t46, i32 0
  %t122 = load ptr, ptr %t121
  %t123 = ptrtoint ptr %t122 to i64
  switch i64 %t123, label %case.default.124 [ i64 3, label %case.arm.3.126 i64 4, label %case.arm.4.132 ]
case.arm.3.126:
  %t128 = call ptr @__alloc(i64 16, i32 1)
  %t129 = inttoptr i64 4 to ptr
  %t130 = getelementptr ptr, ptr %t128, i32 0
  store ptr %t129, ptr %t130
  %t131 = getelementptr ptr, ptr %t128, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t131
  br label %case.end.3.127
case.end.3.127:
  br label %case.join.125
case.arm.4.132:
  %t134 = getelementptr ptr, ptr %t46, i32 1
  %t135 = load ptr, ptr %t134
  call void @__inc_ref(ptr %t135)
  %t136 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.5, i64 12), ptr %t135)
  br label %case.end.4.133
case.end.4.133:
  br label %case.join.125
case.default.124:
  unreachable
case.join.125:
  %t137 = phi ptr [ %t128, %case.end.3.127 ], [ %t136, %case.end.4.133 ]
  %t138 = getelementptr ptr, ptr %t137, i32 0
  %t139 = load ptr, ptr %t138
  %t140 = ptrtoint ptr %t139 to i64
  switch i64 %t140, label %case.default.141 [ i64 3, label %case.arm.3.143 i64 4, label %case.arm.4.151 ]
case.arm.3.143:
  %t145 = getelementptr ptr, ptr %t137, i32 1
  %t146 = load ptr, ptr %t145
  call void @__inc_ref(ptr %t146)
  %t147 = call ptr @__alloc(i64 16, i32 1)
  %t148 = inttoptr i64 3 to ptr
  %t149 = getelementptr ptr, ptr %t147, i32 0
  store ptr %t148, ptr %t149
  call void @__inc_ref(ptr %t146)
  %t150 = getelementptr ptr, ptr %t147, i32 1
  store ptr %t146, ptr %t150
  br label %case.end.3.144
case.end.3.144:
  br label %case.join.142
case.arm.4.151:
  %t153 = getelementptr ptr, ptr %t137, i32 1
  %t154 = load ptr, ptr %t153
  call void @__inc_ref(ptr %t154)
  call void @__inc_ref(ptr %t86)
  %t155 = call ptr @__concat(ptr %t86, ptr getelementptr inbounds (i8, ptr @.str.6, i64 12))
  %t156 = getelementptr ptr, ptr %t155, i32 0
  %t157 = load ptr, ptr %t156
  %t158 = ptrtoint ptr %t157 to i64
  switch i64 %t158, label %case.default.159 [ i64 3, label %case.arm.3.161 i64 4, label %case.arm.4.169 ]
case.arm.3.161:
  %t163 = getelementptr ptr, ptr %t155, i32 1
  %t164 = load ptr, ptr %t163
  call void @__inc_ref(ptr %t164)
  %t165 = call ptr @__alloc(i64 16, i32 1)
  %t166 = inttoptr i64 3 to ptr
  %t167 = getelementptr ptr, ptr %t165, i32 0
  store ptr %t166, ptr %t167
  call void @__inc_ref(ptr %t164)
  %t168 = getelementptr ptr, ptr %t165, i32 1
  store ptr %t164, ptr %t168
  br label %case.end.3.162
case.end.3.162:
  br label %case.join.160
case.arm.4.169:
  %t171 = getelementptr ptr, ptr %t155, i32 1
  %t172 = load ptr, ptr %t171
  call void @__inc_ref(ptr %t172)
  call void @__inc_ref(ptr %t172)
  call void @__inc_ref(ptr %t120)
  %t173 = call ptr @__concat(ptr %t172, ptr %t120)
  %t174 = getelementptr ptr, ptr %t173, i32 0
  %t175 = load ptr, ptr %t174
  %t176 = ptrtoint ptr %t175 to i64
  switch i64 %t176, label %case.default.177 [ i64 3, label %case.arm.3.179 i64 4, label %case.arm.4.187 ]
case.arm.3.179:
  %t181 = getelementptr ptr, ptr %t173, i32 1
  %t182 = load ptr, ptr %t181
  call void @__inc_ref(ptr %t182)
  %t183 = call ptr @__alloc(i64 16, i32 1)
  %t184 = inttoptr i64 3 to ptr
  %t185 = getelementptr ptr, ptr %t183, i32 0
  store ptr %t184, ptr %t185
  call void @__inc_ref(ptr %t182)
  %t186 = getelementptr ptr, ptr %t183, i32 1
  store ptr %t182, ptr %t186
  br label %case.end.3.180
case.end.3.180:
  br label %case.join.178
case.arm.4.187:
  %t189 = getelementptr ptr, ptr %t173, i32 1
  %t190 = load ptr, ptr %t189
  call void @__inc_ref(ptr %t190)
  call void @__inc_ref(ptr %t190)
  %t191 = call ptr @__concat(ptr %t190, ptr getelementptr inbounds (i8, ptr @.str.6, i64 12))
  %t192 = getelementptr ptr, ptr %t191, i32 0
  %t193 = load ptr, ptr %t192
  %t194 = ptrtoint ptr %t193 to i64
  switch i64 %t194, label %case.default.195 [ i64 3, label %case.arm.3.197 i64 4, label %case.arm.4.205 ]
case.arm.3.197:
  %t199 = getelementptr ptr, ptr %t191, i32 1
  %t200 = load ptr, ptr %t199
  call void @__inc_ref(ptr %t200)
  %t201 = call ptr @__alloc(i64 16, i32 1)
  %t202 = inttoptr i64 3 to ptr
  %t203 = getelementptr ptr, ptr %t201, i32 0
  store ptr %t202, ptr %t203
  call void @__inc_ref(ptr %t200)
  %t204 = getelementptr ptr, ptr %t201, i32 1
  store ptr %t200, ptr %t204
  br label %case.end.3.198
case.end.3.198:
  br label %case.join.196
case.arm.4.205:
  %t207 = getelementptr ptr, ptr %t191, i32 1
  %t208 = load ptr, ptr %t207
  call void @__inc_ref(ptr %t208)
  call void @__inc_ref(ptr %t208)
  call void @__inc_ref(ptr %t154)
  %t209 = call ptr @__concat(ptr %t208, ptr %t154)
  br label %case.end.4.206
case.end.4.206:
  br label %case.join.196
case.default.195:
  unreachable
case.join.196:
  %t210 = phi ptr [ %t201, %case.end.3.198 ], [ %t209, %case.end.4.206 ]
  call void @__free_recursive(ptr %t191)
  br label %case.end.4.188
case.end.4.188:
  br label %case.join.178
case.default.177:
  unreachable
case.join.178:
  %t211 = phi ptr [ %t183, %case.end.3.180 ], [ %t210, %case.end.4.188 ]
  call void @__free_recursive(ptr %t173)
  br label %case.end.4.170
case.end.4.170:
  br label %case.join.160
case.default.159:
  unreachable
case.join.160:
  %t212 = phi ptr [ %t165, %case.end.3.162 ], [ %t211, %case.end.4.170 ]
  call void @__free_recursive(ptr %t155)
  br label %case.end.4.152
case.end.4.152:
  br label %case.join.142
case.default.141:
  unreachable
case.join.142:
  %t213 = phi ptr [ %t147, %case.end.3.144 ], [ %t212, %case.end.4.152 ]
  call void @__free_recursive(ptr %t137)
  br label %case.end.4.118
case.end.4.118:
  br label %case.join.108
case.default.107:
  unreachable
case.join.108:
  %t214 = phi ptr [ %t113, %case.end.3.110 ], [ %t213, %case.end.4.118 ]
  call void @__free_recursive(ptr %t103)
  call void @__free_recursive(ptr %t65)
  store ptr %t214, ptr %v__inl76_scrut.jslot
  br label %join.47
join.case.default.69:
  unreachable
join.47:
  %t215 = load ptr, ptr %v__inl76_scrut.jslot
  %t216 = getelementptr ptr, ptr %t215, i32 0
  %t217 = load ptr, ptr %t216
  %t218 = ptrtoint ptr %t217 to i64
  switch i64 %t218, label %case.default.219 [ i64 3, label %case.arm.3.221 i64 4, label %case.arm.4.235 ]
case.arm.3.221:
  %t223 = call ptr @__alloc(i64 24, i32 2)
  %t224 = inttoptr i64 7 to ptr
  %t225 = getelementptr ptr, ptr %t223, i32 0
  store ptr %t224, ptr %t225
  %t226 = getelementptr ptr, ptr %t223, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t226
  %t227 = call ptr @__alloc(i64 16, i32 1)
  %t228 = inttoptr i64 5 to ptr
  %t229 = getelementptr ptr, ptr %t227, i32 0
  store ptr %t228, ptr %t229
  %t230 = call ptr @__alloc(i64 8, i32 0)
  %t231 = inttoptr i64 0 to ptr
  %t232 = getelementptr ptr, ptr %t230, i32 0
  store ptr %t231, ptr %t232
  %t233 = getelementptr ptr, ptr %t227, i32 1
  store ptr %t230, ptr %t233
  %t234 = getelementptr ptr, ptr %t223, i32 2
  store ptr %t227, ptr %t234
  br label %case.end.3.222
case.end.3.222:
  br label %case.join.220
case.arm.4.235:
  %t237 = call ptr @__alloc(i64 24, i32 2)
  %t238 = inttoptr i64 7 to ptr
  %t239 = getelementptr ptr, ptr %t237, i32 0
  store ptr %t238, ptr %t239
  %t240 = getelementptr ptr, ptr %t215, i32 1
  %t241 = load ptr, ptr %t240
  call void @__inc_ref(ptr %t241)
  %t242 = getelementptr ptr, ptr %t237, i32 1
  store ptr %t241, ptr %t242
  %t243 = call ptr @__alloc(i64 16, i32 1)
  %t244 = inttoptr i64 5 to ptr
  %t245 = getelementptr ptr, ptr %t243, i32 0
  store ptr %t244, ptr %t245
  %t246 = call ptr @__alloc(i64 8, i32 0)
  %t247 = inttoptr i64 0 to ptr
  %t248 = getelementptr ptr, ptr %t246, i32 0
  store ptr %t247, ptr %t248
  %t249 = getelementptr ptr, ptr %t243, i32 1
  store ptr %t246, ptr %t249
  %t250 = getelementptr ptr, ptr %t237, i32 2
  store ptr %t243, ptr %t250
  br label %case.end.4.236
case.end.4.236:
  br label %case.join.220
case.default.219:
  unreachable
case.join.220:
  %t251 = phi ptr [ %t223, %case.end.3.222 ], [ %t237, %case.end.4.236 ]
  call void @__free_recursive(ptr %t215)
  br label %join.end.252
join.end.252:
  br label %join.after.48
join.after.48:
  %t253 = phi ptr [ %t71, %join.val.83 ], [ %t251, %join.end.252 ]
  call void @__free_recursive(ptr %t46)
  call void @__free_recursive(ptr %t7)
  call void @__free_recursive(ptr %t0)
  ret ptr %t253
}

define i32 @main(i32 %argc, ptr %argv) {
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
