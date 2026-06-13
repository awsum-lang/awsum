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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"a" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"b" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"c" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [7 x i8]} { i32 0, i32 0, i32 0, i32 7, i32 7, [7 x i8] c"Nothing" }
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"Just " }
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
  %v__inl73_scrut.jslot = alloca ptr
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 13 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 0
  %t4 = load ptr, ptr %t3
  %t5 = ptrtoint ptr %t4 to i64
  switch i64 %t5, label %case.default.6 [ i64 13, label %case.arm.13.8 i64 14, label %case.arm.14.13 ]
case.arm.13.8:
  %t10 = call ptr @__alloc(i64 8, i32 0)
  %t11 = inttoptr i64 11 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  br label %case.end.13.9
case.end.13.9:
  br label %case.join.7
case.arm.14.13:
  %t15 = call ptr @__alloc(i64 16, i32 1)
  %t16 = inttoptr i64 12 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = getelementptr ptr, ptr %t0, i32 1
  %t19 = load ptr, ptr %t18
  call void @__inc_ref(ptr %t19)
  %t20 = getelementptr ptr, ptr %t15, i32 1
  store ptr %t19, ptr %t20
  br label %case.end.14.14
case.end.14.14:
  br label %case.join.7
case.default.6:
  unreachable
case.join.7:
  %t21 = phi ptr [ %t10, %case.end.13.9 ], [ %t15, %case.end.14.14 ]
  call void @__free_recursive(ptr %t0)
  %t22 = call ptr @__alloc(i64 24, i32 2)
  %t23 = inttoptr i64 14 to ptr
  %t24 = getelementptr ptr, ptr %t22, i32 0
  store ptr %t23, ptr %t24
  %t25 = getelementptr ptr, ptr %t22, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t25
  %t26 = call ptr @__alloc(i64 8, i32 0)
  %t27 = inttoptr i64 13 to ptr
  %t28 = getelementptr ptr, ptr %t26, i32 0
  store ptr %t27, ptr %t28
  %t29 = getelementptr ptr, ptr %t22, i32 2
  store ptr %t26, ptr %t29
  %t30 = getelementptr ptr, ptr %t22, i32 0
  %t31 = load ptr, ptr %t30
  %t32 = ptrtoint ptr %t31 to i64
  switch i64 %t32, label %case.default.33 [ i64 13, label %case.arm.13.35 i64 14, label %case.arm.14.40 ]
case.arm.13.35:
  %t37 = call ptr @__alloc(i64 8, i32 0)
  %t38 = inttoptr i64 11 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  br label %case.end.13.36
case.end.13.36:
  br label %case.join.34
case.arm.14.40:
  %t42 = call ptr @__alloc(i64 16, i32 1)
  %t43 = inttoptr i64 12 to ptr
  %t44 = getelementptr ptr, ptr %t42, i32 0
  store ptr %t43, ptr %t44
  %t45 = getelementptr ptr, ptr %t22, i32 1
  %t46 = load ptr, ptr %t45
  call void @__inc_ref(ptr %t46)
  %t47 = getelementptr ptr, ptr %t42, i32 1
  store ptr %t46, ptr %t47
  br label %case.end.14.41
case.end.14.41:
  br label %case.join.34
case.default.33:
  unreachable
case.join.34:
  %t48 = phi ptr [ %t37, %case.end.13.36 ], [ %t42, %case.end.14.41 ]
  call void @__free_recursive(ptr %t22)
  %t49 = call ptr @__alloc(i64 24, i32 2)
  %t50 = inttoptr i64 14 to ptr
  %t51 = getelementptr ptr, ptr %t49, i32 0
  store ptr %t50, ptr %t51
  %t52 = getelementptr ptr, ptr %t49, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t52
  %t53 = call ptr @__alloc(i64 24, i32 2)
  %t54 = inttoptr i64 14 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  %t56 = getelementptr ptr, ptr %t53, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t56
  %t57 = call ptr @__alloc(i64 24, i32 2)
  %t58 = inttoptr i64 14 to ptr
  %t59 = getelementptr ptr, ptr %t57, i32 0
  store ptr %t58, ptr %t59
  %t60 = getelementptr ptr, ptr %t57, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t60
  %t61 = call ptr @__alloc(i64 8, i32 0)
  %t62 = inttoptr i64 13 to ptr
  %t63 = getelementptr ptr, ptr %t61, i32 0
  store ptr %t62, ptr %t63
  %t64 = getelementptr ptr, ptr %t57, i32 2
  store ptr %t61, ptr %t64
  %t65 = getelementptr ptr, ptr %t53, i32 2
  store ptr %t57, ptr %t65
  %t66 = getelementptr ptr, ptr %t49, i32 2
  store ptr %t53, ptr %t66
  %t67 = getelementptr ptr, ptr %t49, i32 0
  %t68 = load ptr, ptr %t67
  %t69 = ptrtoint ptr %t68 to i64
  switch i64 %t69, label %case.default.70 [ i64 13, label %case.arm.13.72 i64 14, label %case.arm.14.77 ]
case.arm.13.72:
  %t74 = call ptr @__alloc(i64 8, i32 0)
  %t75 = inttoptr i64 11 to ptr
  %t76 = getelementptr ptr, ptr %t74, i32 0
  store ptr %t75, ptr %t76
  br label %case.end.13.73
case.end.13.73:
  br label %case.join.71
case.arm.14.77:
  %t79 = call ptr @__alloc(i64 16, i32 1)
  %t80 = inttoptr i64 12 to ptr
  %t81 = getelementptr ptr, ptr %t79, i32 0
  store ptr %t80, ptr %t81
  %t82 = getelementptr ptr, ptr %t49, i32 1
  %t83 = load ptr, ptr %t82
  call void @__inc_ref(ptr %t83)
  %t84 = getelementptr ptr, ptr %t79, i32 1
  store ptr %t83, ptr %t84
  br label %case.end.14.78
case.end.14.78:
  br label %case.join.71
case.default.70:
  unreachable
case.join.71:
  %t85 = phi ptr [ %t74, %case.end.13.73 ], [ %t79, %case.end.14.78 ]
  call void @__free_recursive(ptr %t49)
  %t88 = getelementptr ptr, ptr %t21, i32 0
  %t89 = load ptr, ptr %t88
  %t90 = ptrtoint ptr %t89 to i64
  switch i64 %t90, label %case.default.91 [ i64 11, label %case.arm.11.93 i64 12, label %case.arm.12.99 ]
case.arm.11.93:
  %t95 = call ptr @__alloc(i64 16, i32 1)
  %t96 = inttoptr i64 4 to ptr
  %t97 = getelementptr ptr, ptr %t95, i32 0
  store ptr %t96, ptr %t97
  %t98 = getelementptr ptr, ptr %t95, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t98
  br label %case.end.11.94
case.end.11.94:
  br label %case.join.92
case.arm.12.99:
  %t101 = getelementptr ptr, ptr %t21, i32 1
  %t102 = load ptr, ptr %t101
  call void @__inc_ref(ptr %t102)
  %t103 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.5, i64 12), ptr %t102)
  br label %case.end.12.100
case.end.12.100:
  br label %case.join.92
case.default.91:
  unreachable
case.join.92:
  %t104 = phi ptr [ %t95, %case.end.11.94 ], [ %t103, %case.end.12.100 ]
  %t105 = getelementptr ptr, ptr %t104, i32 0
  %t106 = load ptr, ptr %t105
  %t107 = ptrtoint ptr %t106 to i64
  switch i64 %t107, label %join.case.default.108 [ i64 3, label %join.case.arm.3.109 i64 4, label %join.case.arm.4.123 ]
join.case.arm.3.109:
  %t110 = call ptr @__alloc(i64 24, i32 2)
  %t111 = inttoptr i64 7 to ptr
  %t112 = getelementptr ptr, ptr %t110, i32 0
  store ptr %t111, ptr %t112
  %t113 = getelementptr ptr, ptr %t110, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t113
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
  call void @__free_recursive(ptr %t104)
  br label %join.val.122
join.val.122:
  br label %join.after.87
join.case.arm.4.123:
  %t124 = getelementptr ptr, ptr %t104, i32 1
  %t125 = load ptr, ptr %t124
  call void @__inc_ref(ptr %t125)
  %t126 = getelementptr ptr, ptr %t48, i32 0
  %t127 = load ptr, ptr %t126
  %t128 = ptrtoint ptr %t127 to i64
  switch i64 %t128, label %case.default.129 [ i64 11, label %case.arm.11.131 i64 12, label %case.arm.12.137 ]
case.arm.11.131:
  %t133 = call ptr @__alloc(i64 16, i32 1)
  %t134 = inttoptr i64 4 to ptr
  %t135 = getelementptr ptr, ptr %t133, i32 0
  store ptr %t134, ptr %t135
  %t136 = getelementptr ptr, ptr %t133, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t136
  br label %case.end.11.132
case.end.11.132:
  br label %case.join.130
case.arm.12.137:
  %t139 = getelementptr ptr, ptr %t48, i32 1
  %t140 = load ptr, ptr %t139
  call void @__inc_ref(ptr %t140)
  %t141 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.5, i64 12), ptr %t140)
  br label %case.end.12.138
case.end.12.138:
  br label %case.join.130
case.default.129:
  unreachable
case.join.130:
  %t142 = phi ptr [ %t133, %case.end.11.132 ], [ %t141, %case.end.12.138 ]
  %t143 = getelementptr ptr, ptr %t142, i32 0
  %t144 = load ptr, ptr %t143
  %t145 = ptrtoint ptr %t144 to i64
  switch i64 %t145, label %case.default.146 [ i64 3, label %case.arm.3.148 i64 4, label %case.arm.4.156 ]
case.arm.3.148:
  %t150 = getelementptr ptr, ptr %t142, i32 1
  %t151 = load ptr, ptr %t150
  call void @__inc_ref(ptr %t151)
  %t152 = call ptr @__alloc(i64 16, i32 1)
  %t153 = inttoptr i64 3 to ptr
  %t154 = getelementptr ptr, ptr %t152, i32 0
  store ptr %t153, ptr %t154
  call void @__inc_ref(ptr %t151)
  %t155 = getelementptr ptr, ptr %t152, i32 1
  store ptr %t151, ptr %t155
  br label %case.end.3.149
case.end.3.149:
  br label %case.join.147
case.arm.4.156:
  %t158 = getelementptr ptr, ptr %t142, i32 1
  %t159 = load ptr, ptr %t158
  call void @__inc_ref(ptr %t159)
  %t160 = getelementptr ptr, ptr %t85, i32 0
  %t161 = load ptr, ptr %t160
  %t162 = ptrtoint ptr %t161 to i64
  switch i64 %t162, label %case.default.163 [ i64 11, label %case.arm.11.165 i64 12, label %case.arm.12.171 ]
case.arm.11.165:
  %t167 = call ptr @__alloc(i64 16, i32 1)
  %t168 = inttoptr i64 4 to ptr
  %t169 = getelementptr ptr, ptr %t167, i32 0
  store ptr %t168, ptr %t169
  %t170 = getelementptr ptr, ptr %t167, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t170
  br label %case.end.11.166
case.end.11.166:
  br label %case.join.164
case.arm.12.171:
  %t173 = getelementptr ptr, ptr %t85, i32 1
  %t174 = load ptr, ptr %t173
  call void @__inc_ref(ptr %t174)
  %t175 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.5, i64 12), ptr %t174)
  br label %case.end.12.172
case.end.12.172:
  br label %case.join.164
case.default.163:
  unreachable
case.join.164:
  %t176 = phi ptr [ %t167, %case.end.11.166 ], [ %t175, %case.end.12.172 ]
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
  call void @__inc_ref(ptr %t125)
  %t194 = call ptr @__concat(ptr %t125, ptr getelementptr inbounds (i8, ptr @.str.6, i64 12))
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
  call void @__inc_ref(ptr %t159)
  %t212 = call ptr @__concat(ptr %t211, ptr %t159)
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
  call void @__inc_ref(ptr %t193)
  %t248 = call ptr @__concat(ptr %t247, ptr %t193)
  br label %case.end.4.245
case.end.4.245:
  br label %case.join.235
case.default.234:
  unreachable
case.join.235:
  %t249 = phi ptr [ %t240, %case.end.3.237 ], [ %t248, %case.end.4.245 ]
  call void @__free_recursive(ptr %t230)
  br label %case.end.4.227
case.end.4.227:
  br label %case.join.217
case.default.216:
  unreachable
case.join.217:
  %t250 = phi ptr [ %t222, %case.end.3.219 ], [ %t249, %case.end.4.227 ]
  call void @__free_recursive(ptr %t212)
  br label %case.end.4.209
case.end.4.209:
  br label %case.join.199
case.default.198:
  unreachable
case.join.199:
  %t251 = phi ptr [ %t204, %case.end.3.201 ], [ %t250, %case.end.4.209 ]
  call void @__free_recursive(ptr %t194)
  br label %case.end.4.191
case.end.4.191:
  br label %case.join.181
case.default.180:
  unreachable
case.join.181:
  %t252 = phi ptr [ %t186, %case.end.3.183 ], [ %t251, %case.end.4.191 ]
  call void @__free_recursive(ptr %t176)
  br label %case.end.4.157
case.end.4.157:
  br label %case.join.147
case.default.146:
  unreachable
case.join.147:
  %t253 = phi ptr [ %t152, %case.end.3.149 ], [ %t252, %case.end.4.157 ]
  call void @__free_recursive(ptr %t142)
  call void @__free_recursive(ptr %t104)
  store ptr %t253, ptr %v__inl73_scrut.jslot
  br label %join.86
join.case.default.108:
  unreachable
join.86:
  %t254 = load ptr, ptr %v__inl73_scrut.jslot
  %t255 = getelementptr ptr, ptr %t254, i32 0
  %t256 = load ptr, ptr %t255
  %t257 = ptrtoint ptr %t256 to i64
  switch i64 %t257, label %case.default.258 [ i64 3, label %case.arm.3.260 i64 4, label %case.arm.4.274 ]
case.arm.3.260:
  %t262 = call ptr @__alloc(i64 24, i32 2)
  %t263 = inttoptr i64 7 to ptr
  %t264 = getelementptr ptr, ptr %t262, i32 0
  store ptr %t263, ptr %t264
  %t265 = getelementptr ptr, ptr %t262, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t265
  %t266 = call ptr @__alloc(i64 16, i32 1)
  %t267 = inttoptr i64 5 to ptr
  %t268 = getelementptr ptr, ptr %t266, i32 0
  store ptr %t267, ptr %t268
  %t269 = call ptr @__alloc(i64 8, i32 0)
  %t270 = inttoptr i64 0 to ptr
  %t271 = getelementptr ptr, ptr %t269, i32 0
  store ptr %t270, ptr %t271
  %t272 = getelementptr ptr, ptr %t266, i32 1
  store ptr %t269, ptr %t272
  %t273 = getelementptr ptr, ptr %t262, i32 2
  store ptr %t266, ptr %t273
  br label %case.end.3.261
case.end.3.261:
  br label %case.join.259
case.arm.4.274:
  %t276 = call ptr @__alloc(i64 24, i32 2)
  %t277 = inttoptr i64 7 to ptr
  %t278 = getelementptr ptr, ptr %t276, i32 0
  store ptr %t277, ptr %t278
  %t279 = getelementptr ptr, ptr %t254, i32 1
  %t280 = load ptr, ptr %t279
  call void @__inc_ref(ptr %t280)
  %t281 = getelementptr ptr, ptr %t276, i32 1
  store ptr %t280, ptr %t281
  %t282 = call ptr @__alloc(i64 16, i32 1)
  %t283 = inttoptr i64 5 to ptr
  %t284 = getelementptr ptr, ptr %t282, i32 0
  store ptr %t283, ptr %t284
  %t285 = call ptr @__alloc(i64 8, i32 0)
  %t286 = inttoptr i64 0 to ptr
  %t287 = getelementptr ptr, ptr %t285, i32 0
  store ptr %t286, ptr %t287
  %t288 = getelementptr ptr, ptr %t282, i32 1
  store ptr %t285, ptr %t288
  %t289 = getelementptr ptr, ptr %t276, i32 2
  store ptr %t282, ptr %t289
  br label %case.end.4.275
case.end.4.275:
  br label %case.join.259
case.default.258:
  unreachable
case.join.259:
  %t290 = phi ptr [ %t262, %case.end.3.261 ], [ %t276, %case.end.4.275 ]
  call void @__free_recursive(ptr %t254)
  br label %join.end.291
join.end.291:
  br label %join.after.87
join.after.87:
  %t292 = phi ptr [ %t110, %join.val.122 ], [ %t290, %join.end.291 ]
  call void @__free_recursive(ptr %t85)
  call void @__free_recursive(ptr %t48)
  call void @__free_recursive(ptr %t21)
  ret ptr %t292
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
