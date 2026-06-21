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
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [7 x i8]} { i32 0, i32 0, i32 0, i32 7, i32 7, [7 x i8] c"Nothing" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"Just " }
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"|" }
@.str.6 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }

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
  %t86 = getelementptr ptr, ptr %t21, i32 0
  %t87 = load ptr, ptr %t86
  %t88 = ptrtoint ptr %t87 to i64
  switch i64 %t88, label %case.default.89 [ i64 11, label %case.arm.11.91 i64 12, label %case.arm.12.97 ]
case.arm.11.91:
  %t93 = call ptr @__alloc(i64 16, i32 1)
  %t94 = inttoptr i64 4 to ptr
  %t95 = getelementptr ptr, ptr %t93, i32 0
  store ptr %t94, ptr %t95
  %t96 = getelementptr ptr, ptr %t93, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t96
  br label %case.end.11.92
case.end.11.92:
  br label %case.join.90
case.arm.12.97:
  %t99 = getelementptr ptr, ptr %t21, i32 1
  %t100 = load ptr, ptr %t99
  call void @__inc_ref(ptr %t100)
  %t101 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t100)
  br label %case.end.12.98
case.end.12.98:
  br label %case.join.90
case.default.89:
  unreachable
case.join.90:
  %t102 = phi ptr [ %t93, %case.end.11.92 ], [ %t101, %case.end.12.98 ]
  %t103 = getelementptr ptr, ptr %t102, i32 0
  %t104 = load ptr, ptr %t103
  %t105 = ptrtoint ptr %t104 to i64
  switch i64 %t105, label %case.default.106 [ i64 3, label %case.arm.3.108 i64 4, label %case.arm.4.116 ]
case.arm.3.108:
  %t110 = getelementptr ptr, ptr %t102, i32 1
  %t111 = load ptr, ptr %t110
  call void @__inc_ref(ptr %t111)
  %t112 = call ptr @__alloc(i64 16, i32 1)
  %t113 = inttoptr i64 3 to ptr
  %t114 = getelementptr ptr, ptr %t112, i32 0
  store ptr %t113, ptr %t114
  call void @__inc_ref(ptr %t111)
  %t115 = getelementptr ptr, ptr %t112, i32 1
  store ptr %t111, ptr %t115
  br label %case.end.3.109
case.end.3.109:
  br label %case.join.107
case.arm.4.116:
  %t118 = getelementptr ptr, ptr %t102, i32 1
  %t119 = load ptr, ptr %t118
  call void @__inc_ref(ptr %t119)
  %t120 = getelementptr ptr, ptr %t48, i32 0
  %t121 = load ptr, ptr %t120
  %t122 = ptrtoint ptr %t121 to i64
  switch i64 %t122, label %case.default.123 [ i64 11, label %case.arm.11.125 i64 12, label %case.arm.12.131 ]
case.arm.11.125:
  %t127 = call ptr @__alloc(i64 16, i32 1)
  %t128 = inttoptr i64 4 to ptr
  %t129 = getelementptr ptr, ptr %t127, i32 0
  store ptr %t128, ptr %t129
  %t130 = getelementptr ptr, ptr %t127, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t130
  br label %case.end.11.126
case.end.11.126:
  br label %case.join.124
case.arm.12.131:
  %t133 = getelementptr ptr, ptr %t48, i32 1
  %t134 = load ptr, ptr %t133
  call void @__inc_ref(ptr %t134)
  %t135 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t134)
  br label %case.end.12.132
case.end.12.132:
  br label %case.join.124
case.default.123:
  unreachable
case.join.124:
  %t136 = phi ptr [ %t127, %case.end.11.126 ], [ %t135, %case.end.12.132 ]
  %t137 = getelementptr ptr, ptr %t136, i32 0
  %t138 = load ptr, ptr %t137
  %t139 = ptrtoint ptr %t138 to i64
  switch i64 %t139, label %case.default.140 [ i64 3, label %case.arm.3.142 i64 4, label %case.arm.4.150 ]
case.arm.3.142:
  %t144 = getelementptr ptr, ptr %t136, i32 1
  %t145 = load ptr, ptr %t144
  call void @__inc_ref(ptr %t145)
  %t146 = call ptr @__alloc(i64 16, i32 1)
  %t147 = inttoptr i64 3 to ptr
  %t148 = getelementptr ptr, ptr %t146, i32 0
  store ptr %t147, ptr %t148
  call void @__inc_ref(ptr %t145)
  %t149 = getelementptr ptr, ptr %t146, i32 1
  store ptr %t145, ptr %t149
  br label %case.end.3.143
case.end.3.143:
  br label %case.join.141
case.arm.4.150:
  %t152 = getelementptr ptr, ptr %t136, i32 1
  %t153 = load ptr, ptr %t152
  call void @__inc_ref(ptr %t153)
  %t154 = getelementptr ptr, ptr %t85, i32 0
  %t155 = load ptr, ptr %t154
  %t156 = ptrtoint ptr %t155 to i64
  switch i64 %t156, label %case.default.157 [ i64 11, label %case.arm.11.159 i64 12, label %case.arm.12.165 ]
case.arm.11.159:
  %t161 = call ptr @__alloc(i64 16, i32 1)
  %t162 = inttoptr i64 4 to ptr
  %t163 = getelementptr ptr, ptr %t161, i32 0
  store ptr %t162, ptr %t163
  %t164 = getelementptr ptr, ptr %t161, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t164
  br label %case.end.11.160
case.end.11.160:
  br label %case.join.158
case.arm.12.165:
  %t167 = getelementptr ptr, ptr %t85, i32 1
  %t168 = load ptr, ptr %t167
  call void @__inc_ref(ptr %t168)
  %t169 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t168)
  br label %case.end.12.166
case.end.12.166:
  br label %case.join.158
case.default.157:
  unreachable
case.join.158:
  %t170 = phi ptr [ %t161, %case.end.11.160 ], [ %t169, %case.end.12.166 ]
  %t171 = getelementptr ptr, ptr %t170, i32 0
  %t172 = load ptr, ptr %t171
  %t173 = ptrtoint ptr %t172 to i64
  switch i64 %t173, label %case.default.174 [ i64 3, label %case.arm.3.176 i64 4, label %case.arm.4.184 ]
case.arm.3.176:
  %t178 = getelementptr ptr, ptr %t170, i32 1
  %t179 = load ptr, ptr %t178
  call void @__inc_ref(ptr %t179)
  %t180 = call ptr @__alloc(i64 16, i32 1)
  %t181 = inttoptr i64 3 to ptr
  %t182 = getelementptr ptr, ptr %t180, i32 0
  store ptr %t181, ptr %t182
  call void @__inc_ref(ptr %t179)
  %t183 = getelementptr ptr, ptr %t180, i32 1
  store ptr %t179, ptr %t183
  br label %case.end.3.177
case.end.3.177:
  br label %case.join.175
case.arm.4.184:
  %t186 = getelementptr ptr, ptr %t170, i32 1
  %t187 = load ptr, ptr %t186
  call void @__inc_ref(ptr %t187)
  call void @__inc_ref(ptr %t119)
  %t188 = call ptr @__concat(ptr %t119, ptr getelementptr inbounds (i8, ptr @.str.5, i64 12))
  %t189 = getelementptr ptr, ptr %t188, i32 0
  %t190 = load ptr, ptr %t189
  %t191 = ptrtoint ptr %t190 to i64
  switch i64 %t191, label %case.default.192 [ i64 3, label %case.arm.3.194 i64 4, label %case.arm.4.202 ]
case.arm.3.194:
  %t196 = getelementptr ptr, ptr %t188, i32 1
  %t197 = load ptr, ptr %t196
  call void @__inc_ref(ptr %t197)
  %t198 = call ptr @__alloc(i64 16, i32 1)
  %t199 = inttoptr i64 3 to ptr
  %t200 = getelementptr ptr, ptr %t198, i32 0
  store ptr %t199, ptr %t200
  call void @__inc_ref(ptr %t197)
  %t201 = getelementptr ptr, ptr %t198, i32 1
  store ptr %t197, ptr %t201
  br label %case.end.3.195
case.end.3.195:
  br label %case.join.193
case.arm.4.202:
  %t204 = getelementptr ptr, ptr %t188, i32 1
  %t205 = load ptr, ptr %t204
  call void @__inc_ref(ptr %t205)
  call void @__inc_ref(ptr %t205)
  call void @__inc_ref(ptr %t153)
  %t206 = call ptr @__concat(ptr %t205, ptr %t153)
  %t207 = getelementptr ptr, ptr %t206, i32 0
  %t208 = load ptr, ptr %t207
  %t209 = ptrtoint ptr %t208 to i64
  switch i64 %t209, label %case.default.210 [ i64 3, label %case.arm.3.212 i64 4, label %case.arm.4.220 ]
case.arm.3.212:
  %t214 = getelementptr ptr, ptr %t206, i32 1
  %t215 = load ptr, ptr %t214
  call void @__inc_ref(ptr %t215)
  %t216 = call ptr @__alloc(i64 16, i32 1)
  %t217 = inttoptr i64 3 to ptr
  %t218 = getelementptr ptr, ptr %t216, i32 0
  store ptr %t217, ptr %t218
  call void @__inc_ref(ptr %t215)
  %t219 = getelementptr ptr, ptr %t216, i32 1
  store ptr %t215, ptr %t219
  br label %case.end.3.213
case.end.3.213:
  br label %case.join.211
case.arm.4.220:
  %t222 = getelementptr ptr, ptr %t206, i32 1
  %t223 = load ptr, ptr %t222
  call void @__inc_ref(ptr %t223)
  call void @__inc_ref(ptr %t223)
  %t224 = call ptr @__concat(ptr %t223, ptr getelementptr inbounds (i8, ptr @.str.5, i64 12))
  %t225 = getelementptr ptr, ptr %t224, i32 0
  %t226 = load ptr, ptr %t225
  %t227 = ptrtoint ptr %t226 to i64
  switch i64 %t227, label %case.default.228 [ i64 3, label %case.arm.3.230 i64 4, label %case.arm.4.238 ]
case.arm.3.230:
  %t232 = getelementptr ptr, ptr %t224, i32 1
  %t233 = load ptr, ptr %t232
  call void @__inc_ref(ptr %t233)
  %t234 = call ptr @__alloc(i64 16, i32 1)
  %t235 = inttoptr i64 3 to ptr
  %t236 = getelementptr ptr, ptr %t234, i32 0
  store ptr %t235, ptr %t236
  call void @__inc_ref(ptr %t233)
  %t237 = getelementptr ptr, ptr %t234, i32 1
  store ptr %t233, ptr %t237
  br label %case.end.3.231
case.end.3.231:
  br label %case.join.229
case.arm.4.238:
  %t240 = getelementptr ptr, ptr %t224, i32 1
  %t241 = load ptr, ptr %t240
  call void @__inc_ref(ptr %t241)
  call void @__inc_ref(ptr %t241)
  call void @__inc_ref(ptr %t187)
  %t242 = call ptr @__concat(ptr %t241, ptr %t187)
  br label %case.end.4.239
case.end.4.239:
  br label %case.join.229
case.default.228:
  unreachable
case.join.229:
  %t243 = phi ptr [ %t234, %case.end.3.231 ], [ %t242, %case.end.4.239 ]
  call void @__free_recursive(ptr %t224)
  br label %case.end.4.221
case.end.4.221:
  br label %case.join.211
case.default.210:
  unreachable
case.join.211:
  %t244 = phi ptr [ %t216, %case.end.3.213 ], [ %t243, %case.end.4.221 ]
  call void @__free_recursive(ptr %t206)
  br label %case.end.4.203
case.end.4.203:
  br label %case.join.193
case.default.192:
  unreachable
case.join.193:
  %t245 = phi ptr [ %t198, %case.end.3.195 ], [ %t244, %case.end.4.203 ]
  call void @__free_recursive(ptr %t188)
  br label %case.end.4.185
case.end.4.185:
  br label %case.join.175
case.default.174:
  unreachable
case.join.175:
  %t246 = phi ptr [ %t180, %case.end.3.177 ], [ %t245, %case.end.4.185 ]
  call void @__free_recursive(ptr %t170)
  br label %case.end.4.151
case.end.4.151:
  br label %case.join.141
case.default.140:
  unreachable
case.join.141:
  %t247 = phi ptr [ %t146, %case.end.3.143 ], [ %t246, %case.end.4.151 ]
  call void @__free_recursive(ptr %t136)
  br label %case.end.4.117
case.end.4.117:
  br label %case.join.107
case.default.106:
  unreachable
case.join.107:
  %t248 = phi ptr [ %t112, %case.end.3.109 ], [ %t247, %case.end.4.117 ]
  call void @__free_recursive(ptr %t102)
  call void @__free_recursive(ptr %t85)
  call void @__free_recursive(ptr %t48)
  call void @__free_recursive(ptr %t21)
  ret ptr %t248
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
  %t26 = call ptr @v__cps__df_andThenIO_4(ptr %t22, ptr %t23)
  %t27 = call ptr @__alloc(i64 8, i32 0)
  %t28 = inttoptr i64 20 to ptr
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
  store ptr getelementptr inbounds (i8, ptr @.str.6, i64 12), ptr %t17
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
