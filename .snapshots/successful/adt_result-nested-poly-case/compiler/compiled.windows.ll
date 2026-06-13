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
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"1" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"," }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"2" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"3" }
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"4" }

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
  %v__inl12_scrut.jslot = alloca ptr
  %t2 = call ptr @__alloc(i64 16, i32 1)
  %t3 = inttoptr i64 24 to ptr
  %t4 = getelementptr ptr, ptr %t2, i32 0
  store ptr %t3, ptr %t4
  %t5 = call ptr @__alloc(i64 16, i32 1)
  %t6 = inttoptr i64 24 to ptr
  %t7 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t6, ptr %t7
  %t8 = getelementptr ptr, ptr %t5, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t8
  %t9 = getelementptr ptr, ptr %t2, i32 1
  store ptr %t5, ptr %t9
  %t10 = getelementptr ptr, ptr %t2, i32 0
  %t11 = load ptr, ptr %t10
  %t12 = ptrtoint ptr %t11 to i64
  switch i64 %t12, label %case.default.13 [ i64 24, label %case.arm.24.15 i64 25, label %case.arm.25.21 ]
case.arm.24.15:
  %t17 = getelementptr ptr, ptr %t2, i32 1
  %t18 = load ptr, ptr %t17
  call void @__inc_ref(ptr %t18)
  %t19 = getelementptr ptr, ptr %t18, i32 1
  %t20 = load ptr, ptr %t19
  call void @__inc_ref(ptr %t20)
  br label %case.end.24.16
case.end.24.16:
  br label %case.join.14
case.arm.25.21:
  %t23 = getelementptr ptr, ptr %t2, i32 1
  %t24 = load ptr, ptr %t23
  call void @__inc_ref(ptr %t24)
  %t25 = getelementptr ptr, ptr %t24, i32 1
  %t26 = load ptr, ptr %t25
  call void @__inc_ref(ptr %t26)
  br label %case.end.25.22
case.end.25.22:
  br label %case.join.14
case.default.13:
  unreachable
case.join.14:
  %t27 = phi ptr [ %t20, %case.end.24.16 ], [ %t26, %case.end.25.22 ]
  call void @__free_recursive(ptr %t2)
  %t28 = call ptr @__concat(ptr %t27, ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
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
  %t50 = call ptr @__alloc(i64 16, i32 1)
  %t51 = inttoptr i64 24 to ptr
  %t52 = getelementptr ptr, ptr %t50, i32 0
  store ptr %t51, ptr %t52
  %t53 = call ptr @__alloc(i64 16, i32 1)
  %t54 = inttoptr i64 25 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  %t56 = getelementptr ptr, ptr %t53, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t56
  %t57 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t53, ptr %t57
  %t58 = getelementptr ptr, ptr %t50, i32 0
  %t59 = load ptr, ptr %t58
  %t60 = ptrtoint ptr %t59 to i64
  switch i64 %t60, label %case.default.61 [ i64 24, label %case.arm.24.63 i64 25, label %case.arm.25.69 ]
case.arm.24.63:
  %t65 = getelementptr ptr, ptr %t50, i32 1
  %t66 = load ptr, ptr %t65
  call void @__inc_ref(ptr %t66)
  %t67 = getelementptr ptr, ptr %t66, i32 1
  %t68 = load ptr, ptr %t67
  call void @__inc_ref(ptr %t68)
  br label %case.end.24.64
case.end.24.64:
  br label %case.join.62
case.arm.25.69:
  %t71 = getelementptr ptr, ptr %t50, i32 1
  %t72 = load ptr, ptr %t71
  call void @__inc_ref(ptr %t72)
  %t73 = getelementptr ptr, ptr %t72, i32 1
  %t74 = load ptr, ptr %t73
  call void @__inc_ref(ptr %t74)
  br label %case.end.25.70
case.end.25.70:
  br label %case.join.62
case.default.61:
  unreachable
case.join.62:
  %t75 = phi ptr [ %t68, %case.end.24.64 ], [ %t74, %case.end.25.70 ]
  call void @__free_recursive(ptr %t50)
  %t76 = call ptr @__concat(ptr %t49, ptr %t75)
  %t77 = getelementptr ptr, ptr %t76, i32 0
  %t78 = load ptr, ptr %t77
  %t79 = ptrtoint ptr %t78 to i64
  switch i64 %t79, label %case.default.80 [ i64 3, label %case.arm.3.82 i64 4, label %case.arm.4.90 ]
case.arm.3.82:
  %t84 = getelementptr ptr, ptr %t76, i32 1
  %t85 = load ptr, ptr %t84
  call void @__inc_ref(ptr %t85)
  %t86 = call ptr @__alloc(i64 16, i32 1)
  %t87 = inttoptr i64 3 to ptr
  %t88 = getelementptr ptr, ptr %t86, i32 0
  store ptr %t87, ptr %t88
  call void @__inc_ref(ptr %t85)
  %t89 = getelementptr ptr, ptr %t86, i32 1
  store ptr %t85, ptr %t89
  br label %case.end.3.83
case.end.3.83:
  br label %case.join.81
case.arm.4.90:
  %t92 = getelementptr ptr, ptr %t76, i32 1
  %t93 = load ptr, ptr %t92
  call void @__inc_ref(ptr %t93)
  call void @__inc_ref(ptr %t93)
  %t94 = call ptr @__concat(ptr %t93, ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
  %t95 = getelementptr ptr, ptr %t94, i32 0
  %t96 = load ptr, ptr %t95
  %t97 = ptrtoint ptr %t96 to i64
  switch i64 %t97, label %case.default.98 [ i64 3, label %case.arm.3.100 i64 4, label %case.arm.4.108 ]
case.arm.3.100:
  %t102 = getelementptr ptr, ptr %t94, i32 1
  %t103 = load ptr, ptr %t102
  call void @__inc_ref(ptr %t103)
  %t104 = call ptr @__alloc(i64 16, i32 1)
  %t105 = inttoptr i64 3 to ptr
  %t106 = getelementptr ptr, ptr %t104, i32 0
  store ptr %t105, ptr %t106
  call void @__inc_ref(ptr %t103)
  %t107 = getelementptr ptr, ptr %t104, i32 1
  store ptr %t103, ptr %t107
  br label %case.end.3.101
case.end.3.101:
  br label %case.join.99
case.arm.4.108:
  %t110 = getelementptr ptr, ptr %t94, i32 1
  %t111 = load ptr, ptr %t110
  call void @__inc_ref(ptr %t111)
  call void @__inc_ref(ptr %t111)
  %t112 = call ptr @__alloc(i64 16, i32 1)
  %t113 = inttoptr i64 25 to ptr
  %t114 = getelementptr ptr, ptr %t112, i32 0
  store ptr %t113, ptr %t114
  %t115 = call ptr @__alloc(i64 16, i32 1)
  %t116 = inttoptr i64 24 to ptr
  %t117 = getelementptr ptr, ptr %t115, i32 0
  store ptr %t116, ptr %t117
  %t118 = getelementptr ptr, ptr %t115, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t118
  %t119 = getelementptr ptr, ptr %t112, i32 1
  store ptr %t115, ptr %t119
  %t120 = getelementptr ptr, ptr %t112, i32 0
  %t121 = load ptr, ptr %t120
  %t122 = ptrtoint ptr %t121 to i64
  switch i64 %t122, label %case.default.123 [ i64 24, label %case.arm.24.125 i64 25, label %case.arm.25.131 ]
case.arm.24.125:
  %t127 = getelementptr ptr, ptr %t112, i32 1
  %t128 = load ptr, ptr %t127
  call void @__inc_ref(ptr %t128)
  %t129 = getelementptr ptr, ptr %t128, i32 1
  %t130 = load ptr, ptr %t129
  call void @__inc_ref(ptr %t130)
  br label %case.end.24.126
case.end.24.126:
  br label %case.join.124
case.arm.25.131:
  %t133 = getelementptr ptr, ptr %t112, i32 1
  %t134 = load ptr, ptr %t133
  call void @__inc_ref(ptr %t134)
  %t135 = getelementptr ptr, ptr %t134, i32 1
  %t136 = load ptr, ptr %t135
  call void @__inc_ref(ptr %t136)
  br label %case.end.25.132
case.end.25.132:
  br label %case.join.124
case.default.123:
  unreachable
case.join.124:
  %t137 = phi ptr [ %t130, %case.end.24.126 ], [ %t136, %case.end.25.132 ]
  call void @__free_recursive(ptr %t112)
  %t138 = call ptr @__concat(ptr %t111, ptr %t137)
  %t139 = getelementptr ptr, ptr %t138, i32 0
  %t140 = load ptr, ptr %t139
  %t141 = ptrtoint ptr %t140 to i64
  switch i64 %t141, label %case.default.142 [ i64 3, label %case.arm.3.144 i64 4, label %case.arm.4.152 ]
case.arm.3.144:
  %t146 = getelementptr ptr, ptr %t138, i32 1
  %t147 = load ptr, ptr %t146
  call void @__inc_ref(ptr %t147)
  %t148 = call ptr @__alloc(i64 16, i32 1)
  %t149 = inttoptr i64 3 to ptr
  %t150 = getelementptr ptr, ptr %t148, i32 0
  store ptr %t149, ptr %t150
  call void @__inc_ref(ptr %t147)
  %t151 = getelementptr ptr, ptr %t148, i32 1
  store ptr %t147, ptr %t151
  br label %case.end.3.145
case.end.3.145:
  br label %case.join.143
case.arm.4.152:
  %t154 = getelementptr ptr, ptr %t138, i32 1
  %t155 = load ptr, ptr %t154
  call void @__inc_ref(ptr %t155)
  call void @__inc_ref(ptr %t155)
  %t156 = call ptr @__concat(ptr %t155, ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
  %t157 = getelementptr ptr, ptr %t156, i32 0
  %t158 = load ptr, ptr %t157
  %t159 = ptrtoint ptr %t158 to i64
  switch i64 %t159, label %case.default.160 [ i64 3, label %case.arm.3.162 i64 4, label %case.arm.4.170 ]
case.arm.3.162:
  %t164 = getelementptr ptr, ptr %t156, i32 1
  %t165 = load ptr, ptr %t164
  call void @__inc_ref(ptr %t165)
  %t166 = call ptr @__alloc(i64 16, i32 1)
  %t167 = inttoptr i64 3 to ptr
  %t168 = getelementptr ptr, ptr %t166, i32 0
  store ptr %t167, ptr %t168
  call void @__inc_ref(ptr %t165)
  %t169 = getelementptr ptr, ptr %t166, i32 1
  store ptr %t165, ptr %t169
  br label %case.end.3.163
case.end.3.163:
  br label %case.join.161
case.arm.4.170:
  %t172 = getelementptr ptr, ptr %t156, i32 1
  %t173 = load ptr, ptr %t172
  call void @__inc_ref(ptr %t173)
  call void @__inc_ref(ptr %t173)
  %t174 = call ptr @__alloc(i64 16, i32 1)
  %t175 = inttoptr i64 25 to ptr
  %t176 = getelementptr ptr, ptr %t174, i32 0
  store ptr %t175, ptr %t176
  %t177 = call ptr @__alloc(i64 16, i32 1)
  %t178 = inttoptr i64 25 to ptr
  %t179 = getelementptr ptr, ptr %t177, i32 0
  store ptr %t178, ptr %t179
  %t180 = getelementptr ptr, ptr %t177, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.5, i64 12), ptr %t180
  %t181 = getelementptr ptr, ptr %t174, i32 1
  store ptr %t177, ptr %t181
  %t182 = getelementptr ptr, ptr %t174, i32 0
  %t183 = load ptr, ptr %t182
  %t184 = ptrtoint ptr %t183 to i64
  switch i64 %t184, label %case.default.185 [ i64 24, label %case.arm.24.187 i64 25, label %case.arm.25.193 ]
case.arm.24.187:
  %t189 = getelementptr ptr, ptr %t174, i32 1
  %t190 = load ptr, ptr %t189
  call void @__inc_ref(ptr %t190)
  %t191 = getelementptr ptr, ptr %t190, i32 1
  %t192 = load ptr, ptr %t191
  call void @__inc_ref(ptr %t192)
  br label %case.end.24.188
case.end.24.188:
  br label %case.join.186
case.arm.25.193:
  %t195 = getelementptr ptr, ptr %t174, i32 1
  %t196 = load ptr, ptr %t195
  call void @__inc_ref(ptr %t196)
  %t197 = getelementptr ptr, ptr %t196, i32 1
  %t198 = load ptr, ptr %t197
  call void @__inc_ref(ptr %t198)
  br label %case.end.25.194
case.end.25.194:
  br label %case.join.186
case.default.185:
  unreachable
case.join.186:
  %t199 = phi ptr [ %t192, %case.end.24.188 ], [ %t198, %case.end.25.194 ]
  call void @__free_recursive(ptr %t174)
  %t200 = call ptr @__concat(ptr %t173, ptr %t199)
  br label %case.end.4.171
case.end.4.171:
  br label %case.join.161
case.default.160:
  unreachable
case.join.161:
  %t201 = phi ptr [ %t166, %case.end.3.163 ], [ %t200, %case.end.4.171 ]
  call void @__free_recursive(ptr %t156)
  br label %case.end.4.153
case.end.4.153:
  br label %case.join.143
case.default.142:
  unreachable
case.join.143:
  %t202 = phi ptr [ %t148, %case.end.3.145 ], [ %t201, %case.end.4.153 ]
  call void @__free_recursive(ptr %t138)
  br label %case.end.4.109
case.end.4.109:
  br label %case.join.99
case.default.98:
  unreachable
case.join.99:
  %t203 = phi ptr [ %t104, %case.end.3.101 ], [ %t202, %case.end.4.109 ]
  call void @__free_recursive(ptr %t94)
  br label %case.end.4.91
case.end.4.91:
  br label %case.join.81
case.default.80:
  unreachable
case.join.81:
  %t204 = phi ptr [ %t86, %case.end.3.83 ], [ %t203, %case.end.4.91 ]
  call void @__free_recursive(ptr %t76)
  call void @__free_recursive(ptr %t28)
  store ptr %t204, ptr %v__inl12_scrut.jslot
  br label %join.0
join.case.default.32:
  unreachable
join.0:
  %t205 = load ptr, ptr %v__inl12_scrut.jslot
  %t206 = getelementptr ptr, ptr %t205, i32 0
  %t207 = load ptr, ptr %t206
  %t208 = ptrtoint ptr %t207 to i64
  switch i64 %t208, label %case.default.209 [ i64 3, label %case.arm.3.211 i64 4, label %case.arm.4.225 ]
case.arm.3.211:
  %t213 = call ptr @__alloc(i64 24, i32 2)
  %t214 = inttoptr i64 7 to ptr
  %t215 = getelementptr ptr, ptr %t213, i32 0
  store ptr %t214, ptr %t215
  %t216 = getelementptr ptr, ptr %t213, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t216
  %t217 = call ptr @__alloc(i64 16, i32 1)
  %t218 = inttoptr i64 5 to ptr
  %t219 = getelementptr ptr, ptr %t217, i32 0
  store ptr %t218, ptr %t219
  %t220 = call ptr @__alloc(i64 8, i32 0)
  %t221 = inttoptr i64 0 to ptr
  %t222 = getelementptr ptr, ptr %t220, i32 0
  store ptr %t221, ptr %t222
  %t223 = getelementptr ptr, ptr %t217, i32 1
  store ptr %t220, ptr %t223
  %t224 = getelementptr ptr, ptr %t213, i32 2
  store ptr %t217, ptr %t224
  br label %case.end.3.212
case.end.3.212:
  br label %case.join.210
case.arm.4.225:
  %t227 = call ptr @__alloc(i64 24, i32 2)
  %t228 = inttoptr i64 7 to ptr
  %t229 = getelementptr ptr, ptr %t227, i32 0
  store ptr %t228, ptr %t229
  %t230 = getelementptr ptr, ptr %t205, i32 1
  %t231 = load ptr, ptr %t230
  call void @__inc_ref(ptr %t231)
  %t232 = getelementptr ptr, ptr %t227, i32 1
  store ptr %t231, ptr %t232
  %t233 = call ptr @__alloc(i64 16, i32 1)
  %t234 = inttoptr i64 5 to ptr
  %t235 = getelementptr ptr, ptr %t233, i32 0
  store ptr %t234, ptr %t235
  %t236 = call ptr @__alloc(i64 8, i32 0)
  %t237 = inttoptr i64 0 to ptr
  %t238 = getelementptr ptr, ptr %t236, i32 0
  store ptr %t237, ptr %t238
  %t239 = getelementptr ptr, ptr %t233, i32 1
  store ptr %t236, ptr %t239
  %t240 = getelementptr ptr, ptr %t227, i32 2
  store ptr %t233, ptr %t240
  br label %case.end.4.226
case.end.4.226:
  br label %case.join.210
case.default.209:
  unreachable
case.join.210:
  %t241 = phi ptr [ %t213, %case.end.3.212 ], [ %t227, %case.end.4.226 ]
  call void @__free_recursive(ptr %t205)
  br label %join.end.242
join.end.242:
  br label %join.after.1
join.after.1:
  %t243 = phi ptr [ %t34, %join.val.46 ], [ %t241, %join.end.242 ]
  ret ptr %t243
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
