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
@.str.6 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"5" }
@.str.7 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"6" }
@.str.8 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"7" }
@.str.9 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"8" }

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
  %v__inl28_scrut.jslot = alloca ptr
  %t2 = call ptr @__alloc(i64 16, i32 1)
  %t3 = inttoptr i64 24 to ptr
  %t4 = getelementptr ptr, ptr %t2, i32 0
  store ptr %t3, ptr %t4
  %t5 = call ptr @__alloc(i64 16, i32 1)
  %t6 = inttoptr i64 24 to ptr
  %t7 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t6, ptr %t7
  %t8 = call ptr @__alloc(i64 16, i32 1)
  %t9 = inttoptr i64 24 to ptr
  %t10 = getelementptr ptr, ptr %t8, i32 0
  store ptr %t9, ptr %t10
  %t11 = getelementptr ptr, ptr %t8, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t11
  %t12 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t8, ptr %t12
  %t13 = getelementptr ptr, ptr %t2, i32 1
  store ptr %t5, ptr %t13
  %t14 = getelementptr ptr, ptr %t2, i32 1
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  %t16 = getelementptr ptr, ptr %t15, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %case.default.19 [ i64 24, label %case.arm.24.21 i64 25, label %case.arm.25.27 ]
case.arm.24.21:
  %t23 = getelementptr ptr, ptr %t15, i32 1
  %t24 = load ptr, ptr %t23
  call void @__inc_ref(ptr %t24)
  %t25 = getelementptr ptr, ptr %t24, i32 1
  %t26 = load ptr, ptr %t25
  call void @__inc_ref(ptr %t26)
  br label %case.end.24.22
case.end.24.22:
  br label %case.join.20
case.arm.25.27:
  %t29 = getelementptr ptr, ptr %t15, i32 1
  %t30 = load ptr, ptr %t29
  call void @__inc_ref(ptr %t30)
  %t31 = getelementptr ptr, ptr %t30, i32 1
  %t32 = load ptr, ptr %t31
  call void @__inc_ref(ptr %t32)
  br label %case.end.25.28
case.end.25.28:
  br label %case.join.20
case.default.19:
  unreachable
case.join.20:
  %t33 = phi ptr [ %t26, %case.end.24.22 ], [ %t32, %case.end.25.28 ]
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t2)
  %t34 = call ptr @__concat(ptr %t33, ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
  %t35 = getelementptr ptr, ptr %t34, i32 0
  %t36 = load ptr, ptr %t35
  %t37 = ptrtoint ptr %t36 to i64
  switch i64 %t37, label %join.case.default.38 [ i64 3, label %join.case.arm.3.39 i64 4, label %join.case.arm.4.53 ]
join.case.arm.3.39:
  %t40 = call ptr @__alloc(i64 24, i32 2)
  %t41 = inttoptr i64 7 to ptr
  %t42 = getelementptr ptr, ptr %t40, i32 0
  store ptr %t41, ptr %t42
  %t43 = getelementptr ptr, ptr %t40, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t43
  %t44 = call ptr @__alloc(i64 16, i32 1)
  %t45 = inttoptr i64 5 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  %t47 = call ptr @__alloc(i64 8, i32 0)
  %t48 = inttoptr i64 0 to ptr
  %t49 = getelementptr ptr, ptr %t47, i32 0
  store ptr %t48, ptr %t49
  %t50 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t47, ptr %t50
  %t51 = getelementptr ptr, ptr %t40, i32 2
  store ptr %t44, ptr %t51
  call void @__free_recursive(ptr %t34)
  br label %join.val.52
join.val.52:
  br label %join.after.1
join.case.arm.4.53:
  %t54 = getelementptr ptr, ptr %t34, i32 1
  %t55 = load ptr, ptr %t54
  call void @__inc_ref(ptr %t55)
  call void @__inc_ref(ptr %t55)
  %t56 = call ptr @__alloc(i64 16, i32 1)
  %t57 = inttoptr i64 24 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  %t59 = call ptr @__alloc(i64 16, i32 1)
  %t60 = inttoptr i64 24 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  %t62 = call ptr @__alloc(i64 16, i32 1)
  %t63 = inttoptr i64 25 to ptr
  %t64 = getelementptr ptr, ptr %t62, i32 0
  store ptr %t63, ptr %t64
  %t65 = getelementptr ptr, ptr %t62, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t65
  %t66 = getelementptr ptr, ptr %t59, i32 1
  store ptr %t62, ptr %t66
  %t67 = getelementptr ptr, ptr %t56, i32 1
  store ptr %t59, ptr %t67
  %t68 = getelementptr ptr, ptr %t56, i32 1
  %t69 = load ptr, ptr %t68
  call void @__inc_ref(ptr %t69)
  %t70 = getelementptr ptr, ptr %t69, i32 0
  %t71 = load ptr, ptr %t70
  %t72 = ptrtoint ptr %t71 to i64
  switch i64 %t72, label %case.default.73 [ i64 24, label %case.arm.24.75 i64 25, label %case.arm.25.81 ]
case.arm.24.75:
  %t77 = getelementptr ptr, ptr %t69, i32 1
  %t78 = load ptr, ptr %t77
  call void @__inc_ref(ptr %t78)
  %t79 = getelementptr ptr, ptr %t78, i32 1
  %t80 = load ptr, ptr %t79
  call void @__inc_ref(ptr %t80)
  br label %case.end.24.76
case.end.24.76:
  br label %case.join.74
case.arm.25.81:
  %t83 = getelementptr ptr, ptr %t69, i32 1
  %t84 = load ptr, ptr %t83
  call void @__inc_ref(ptr %t84)
  %t85 = getelementptr ptr, ptr %t84, i32 1
  %t86 = load ptr, ptr %t85
  call void @__inc_ref(ptr %t86)
  br label %case.end.25.82
case.end.25.82:
  br label %case.join.74
case.default.73:
  unreachable
case.join.74:
  %t87 = phi ptr [ %t80, %case.end.24.76 ], [ %t86, %case.end.25.82 ]
  call void @__free_recursive(ptr %t69)
  call void @__free_recursive(ptr %t56)
  %t88 = call ptr @__concat(ptr %t55, ptr %t87)
  %t89 = getelementptr ptr, ptr %t88, i32 0
  %t90 = load ptr, ptr %t89
  %t91 = ptrtoint ptr %t90 to i64
  switch i64 %t91, label %case.default.92 [ i64 3, label %case.arm.3.94 i64 4, label %case.arm.4.102 ]
case.arm.3.94:
  %t96 = getelementptr ptr, ptr %t88, i32 1
  %t97 = load ptr, ptr %t96
  call void @__inc_ref(ptr %t97)
  %t98 = call ptr @__alloc(i64 16, i32 1)
  %t99 = inttoptr i64 3 to ptr
  %t100 = getelementptr ptr, ptr %t98, i32 0
  store ptr %t99, ptr %t100
  call void @__inc_ref(ptr %t97)
  %t101 = getelementptr ptr, ptr %t98, i32 1
  store ptr %t97, ptr %t101
  br label %case.end.3.95
case.end.3.95:
  br label %case.join.93
case.arm.4.102:
  %t104 = getelementptr ptr, ptr %t88, i32 1
  %t105 = load ptr, ptr %t104
  call void @__inc_ref(ptr %t105)
  call void @__inc_ref(ptr %t105)
  %t106 = call ptr @__concat(ptr %t105, ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
  %t107 = getelementptr ptr, ptr %t106, i32 0
  %t108 = load ptr, ptr %t107
  %t109 = ptrtoint ptr %t108 to i64
  switch i64 %t109, label %case.default.110 [ i64 3, label %case.arm.3.112 i64 4, label %case.arm.4.120 ]
case.arm.3.112:
  %t114 = getelementptr ptr, ptr %t106, i32 1
  %t115 = load ptr, ptr %t114
  call void @__inc_ref(ptr %t115)
  %t116 = call ptr @__alloc(i64 16, i32 1)
  %t117 = inttoptr i64 3 to ptr
  %t118 = getelementptr ptr, ptr %t116, i32 0
  store ptr %t117, ptr %t118
  call void @__inc_ref(ptr %t115)
  %t119 = getelementptr ptr, ptr %t116, i32 1
  store ptr %t115, ptr %t119
  br label %case.end.3.113
case.end.3.113:
  br label %case.join.111
case.arm.4.120:
  %t122 = getelementptr ptr, ptr %t106, i32 1
  %t123 = load ptr, ptr %t122
  call void @__inc_ref(ptr %t123)
  call void @__inc_ref(ptr %t123)
  %t124 = call ptr @__alloc(i64 16, i32 1)
  %t125 = inttoptr i64 24 to ptr
  %t126 = getelementptr ptr, ptr %t124, i32 0
  store ptr %t125, ptr %t126
  %t127 = call ptr @__alloc(i64 16, i32 1)
  %t128 = inttoptr i64 25 to ptr
  %t129 = getelementptr ptr, ptr %t127, i32 0
  store ptr %t128, ptr %t129
  %t130 = call ptr @__alloc(i64 16, i32 1)
  %t131 = inttoptr i64 24 to ptr
  %t132 = getelementptr ptr, ptr %t130, i32 0
  store ptr %t131, ptr %t132
  %t133 = getelementptr ptr, ptr %t130, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t133
  %t134 = getelementptr ptr, ptr %t127, i32 1
  store ptr %t130, ptr %t134
  %t135 = getelementptr ptr, ptr %t124, i32 1
  store ptr %t127, ptr %t135
  %t136 = getelementptr ptr, ptr %t124, i32 1
  %t137 = load ptr, ptr %t136
  call void @__inc_ref(ptr %t137)
  %t138 = getelementptr ptr, ptr %t137, i32 0
  %t139 = load ptr, ptr %t138
  %t140 = ptrtoint ptr %t139 to i64
  switch i64 %t140, label %case.default.141 [ i64 24, label %case.arm.24.143 i64 25, label %case.arm.25.149 ]
case.arm.24.143:
  %t145 = getelementptr ptr, ptr %t137, i32 1
  %t146 = load ptr, ptr %t145
  call void @__inc_ref(ptr %t146)
  %t147 = getelementptr ptr, ptr %t146, i32 1
  %t148 = load ptr, ptr %t147
  call void @__inc_ref(ptr %t148)
  br label %case.end.24.144
case.end.24.144:
  br label %case.join.142
case.arm.25.149:
  %t151 = getelementptr ptr, ptr %t137, i32 1
  %t152 = load ptr, ptr %t151
  call void @__inc_ref(ptr %t152)
  %t153 = getelementptr ptr, ptr %t152, i32 1
  %t154 = load ptr, ptr %t153
  call void @__inc_ref(ptr %t154)
  br label %case.end.25.150
case.end.25.150:
  br label %case.join.142
case.default.141:
  unreachable
case.join.142:
  %t155 = phi ptr [ %t148, %case.end.24.144 ], [ %t154, %case.end.25.150 ]
  call void @__free_recursive(ptr %t137)
  call void @__free_recursive(ptr %t124)
  %t156 = call ptr @__concat(ptr %t123, ptr %t155)
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
  %t174 = call ptr @__concat(ptr %t173, ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
  %t175 = getelementptr ptr, ptr %t174, i32 0
  %t176 = load ptr, ptr %t175
  %t177 = ptrtoint ptr %t176 to i64
  switch i64 %t177, label %case.default.178 [ i64 3, label %case.arm.3.180 i64 4, label %case.arm.4.188 ]
case.arm.3.180:
  %t182 = getelementptr ptr, ptr %t174, i32 1
  %t183 = load ptr, ptr %t182
  call void @__inc_ref(ptr %t183)
  %t184 = call ptr @__alloc(i64 16, i32 1)
  %t185 = inttoptr i64 3 to ptr
  %t186 = getelementptr ptr, ptr %t184, i32 0
  store ptr %t185, ptr %t186
  call void @__inc_ref(ptr %t183)
  %t187 = getelementptr ptr, ptr %t184, i32 1
  store ptr %t183, ptr %t187
  br label %case.end.3.181
case.end.3.181:
  br label %case.join.179
case.arm.4.188:
  %t190 = getelementptr ptr, ptr %t174, i32 1
  %t191 = load ptr, ptr %t190
  call void @__inc_ref(ptr %t191)
  call void @__inc_ref(ptr %t191)
  %t192 = call ptr @__alloc(i64 16, i32 1)
  %t193 = inttoptr i64 24 to ptr
  %t194 = getelementptr ptr, ptr %t192, i32 0
  store ptr %t193, ptr %t194
  %t195 = call ptr @__alloc(i64 16, i32 1)
  %t196 = inttoptr i64 25 to ptr
  %t197 = getelementptr ptr, ptr %t195, i32 0
  store ptr %t196, ptr %t197
  %t198 = call ptr @__alloc(i64 16, i32 1)
  %t199 = inttoptr i64 25 to ptr
  %t200 = getelementptr ptr, ptr %t198, i32 0
  store ptr %t199, ptr %t200
  %t201 = getelementptr ptr, ptr %t198, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.5, i64 12), ptr %t201
  %t202 = getelementptr ptr, ptr %t195, i32 1
  store ptr %t198, ptr %t202
  %t203 = getelementptr ptr, ptr %t192, i32 1
  store ptr %t195, ptr %t203
  %t204 = getelementptr ptr, ptr %t192, i32 1
  %t205 = load ptr, ptr %t204
  call void @__inc_ref(ptr %t205)
  %t206 = getelementptr ptr, ptr %t205, i32 0
  %t207 = load ptr, ptr %t206
  %t208 = ptrtoint ptr %t207 to i64
  switch i64 %t208, label %case.default.209 [ i64 24, label %case.arm.24.211 i64 25, label %case.arm.25.217 ]
case.arm.24.211:
  %t213 = getelementptr ptr, ptr %t205, i32 1
  %t214 = load ptr, ptr %t213
  call void @__inc_ref(ptr %t214)
  %t215 = getelementptr ptr, ptr %t214, i32 1
  %t216 = load ptr, ptr %t215
  call void @__inc_ref(ptr %t216)
  br label %case.end.24.212
case.end.24.212:
  br label %case.join.210
case.arm.25.217:
  %t219 = getelementptr ptr, ptr %t205, i32 1
  %t220 = load ptr, ptr %t219
  call void @__inc_ref(ptr %t220)
  %t221 = getelementptr ptr, ptr %t220, i32 1
  %t222 = load ptr, ptr %t221
  call void @__inc_ref(ptr %t222)
  br label %case.end.25.218
case.end.25.218:
  br label %case.join.210
case.default.209:
  unreachable
case.join.210:
  %t223 = phi ptr [ %t216, %case.end.24.212 ], [ %t222, %case.end.25.218 ]
  call void @__free_recursive(ptr %t205)
  call void @__free_recursive(ptr %t192)
  %t224 = call ptr @__concat(ptr %t191, ptr %t223)
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
  %t242 = call ptr @__concat(ptr %t241, ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
  %t243 = getelementptr ptr, ptr %t242, i32 0
  %t244 = load ptr, ptr %t243
  %t245 = ptrtoint ptr %t244 to i64
  switch i64 %t245, label %case.default.246 [ i64 3, label %case.arm.3.248 i64 4, label %case.arm.4.256 ]
case.arm.3.248:
  %t250 = getelementptr ptr, ptr %t242, i32 1
  %t251 = load ptr, ptr %t250
  call void @__inc_ref(ptr %t251)
  %t252 = call ptr @__alloc(i64 16, i32 1)
  %t253 = inttoptr i64 3 to ptr
  %t254 = getelementptr ptr, ptr %t252, i32 0
  store ptr %t253, ptr %t254
  call void @__inc_ref(ptr %t251)
  %t255 = getelementptr ptr, ptr %t252, i32 1
  store ptr %t251, ptr %t255
  br label %case.end.3.249
case.end.3.249:
  br label %case.join.247
case.arm.4.256:
  %t258 = getelementptr ptr, ptr %t242, i32 1
  %t259 = load ptr, ptr %t258
  call void @__inc_ref(ptr %t259)
  call void @__inc_ref(ptr %t259)
  %t260 = call ptr @__alloc(i64 16, i32 1)
  %t261 = inttoptr i64 25 to ptr
  %t262 = getelementptr ptr, ptr %t260, i32 0
  store ptr %t261, ptr %t262
  %t263 = call ptr @__alloc(i64 16, i32 1)
  %t264 = inttoptr i64 24 to ptr
  %t265 = getelementptr ptr, ptr %t263, i32 0
  store ptr %t264, ptr %t265
  %t266 = call ptr @__alloc(i64 16, i32 1)
  %t267 = inttoptr i64 24 to ptr
  %t268 = getelementptr ptr, ptr %t266, i32 0
  store ptr %t267, ptr %t268
  %t269 = getelementptr ptr, ptr %t266, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.6, i64 12), ptr %t269
  %t270 = getelementptr ptr, ptr %t263, i32 1
  store ptr %t266, ptr %t270
  %t271 = getelementptr ptr, ptr %t260, i32 1
  store ptr %t263, ptr %t271
  %t272 = getelementptr ptr, ptr %t260, i32 1
  %t273 = load ptr, ptr %t272
  call void @__inc_ref(ptr %t273)
  %t274 = getelementptr ptr, ptr %t273, i32 0
  %t275 = load ptr, ptr %t274
  %t276 = ptrtoint ptr %t275 to i64
  switch i64 %t276, label %case.default.277 [ i64 24, label %case.arm.24.279 i64 25, label %case.arm.25.285 ]
case.arm.24.279:
  %t281 = getelementptr ptr, ptr %t273, i32 1
  %t282 = load ptr, ptr %t281
  call void @__inc_ref(ptr %t282)
  %t283 = getelementptr ptr, ptr %t282, i32 1
  %t284 = load ptr, ptr %t283
  call void @__inc_ref(ptr %t284)
  br label %case.end.24.280
case.end.24.280:
  br label %case.join.278
case.arm.25.285:
  %t287 = getelementptr ptr, ptr %t273, i32 1
  %t288 = load ptr, ptr %t287
  call void @__inc_ref(ptr %t288)
  %t289 = getelementptr ptr, ptr %t288, i32 1
  %t290 = load ptr, ptr %t289
  call void @__inc_ref(ptr %t290)
  br label %case.end.25.286
case.end.25.286:
  br label %case.join.278
case.default.277:
  unreachable
case.join.278:
  %t291 = phi ptr [ %t284, %case.end.24.280 ], [ %t290, %case.end.25.286 ]
  call void @__free_recursive(ptr %t273)
  call void @__free_recursive(ptr %t260)
  %t292 = call ptr @__concat(ptr %t259, ptr %t291)
  %t293 = getelementptr ptr, ptr %t292, i32 0
  %t294 = load ptr, ptr %t293
  %t295 = ptrtoint ptr %t294 to i64
  switch i64 %t295, label %case.default.296 [ i64 3, label %case.arm.3.298 i64 4, label %case.arm.4.306 ]
case.arm.3.298:
  %t300 = getelementptr ptr, ptr %t292, i32 1
  %t301 = load ptr, ptr %t300
  call void @__inc_ref(ptr %t301)
  %t302 = call ptr @__alloc(i64 16, i32 1)
  %t303 = inttoptr i64 3 to ptr
  %t304 = getelementptr ptr, ptr %t302, i32 0
  store ptr %t303, ptr %t304
  call void @__inc_ref(ptr %t301)
  %t305 = getelementptr ptr, ptr %t302, i32 1
  store ptr %t301, ptr %t305
  br label %case.end.3.299
case.end.3.299:
  br label %case.join.297
case.arm.4.306:
  %t308 = getelementptr ptr, ptr %t292, i32 1
  %t309 = load ptr, ptr %t308
  call void @__inc_ref(ptr %t309)
  call void @__inc_ref(ptr %t309)
  %t310 = call ptr @__concat(ptr %t309, ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
  %t311 = getelementptr ptr, ptr %t310, i32 0
  %t312 = load ptr, ptr %t311
  %t313 = ptrtoint ptr %t312 to i64
  switch i64 %t313, label %case.default.314 [ i64 3, label %case.arm.3.316 i64 4, label %case.arm.4.324 ]
case.arm.3.316:
  %t318 = getelementptr ptr, ptr %t310, i32 1
  %t319 = load ptr, ptr %t318
  call void @__inc_ref(ptr %t319)
  %t320 = call ptr @__alloc(i64 16, i32 1)
  %t321 = inttoptr i64 3 to ptr
  %t322 = getelementptr ptr, ptr %t320, i32 0
  store ptr %t321, ptr %t322
  call void @__inc_ref(ptr %t319)
  %t323 = getelementptr ptr, ptr %t320, i32 1
  store ptr %t319, ptr %t323
  br label %case.end.3.317
case.end.3.317:
  br label %case.join.315
case.arm.4.324:
  %t326 = getelementptr ptr, ptr %t310, i32 1
  %t327 = load ptr, ptr %t326
  call void @__inc_ref(ptr %t327)
  call void @__inc_ref(ptr %t327)
  %t328 = call ptr @__alloc(i64 16, i32 1)
  %t329 = inttoptr i64 25 to ptr
  %t330 = getelementptr ptr, ptr %t328, i32 0
  store ptr %t329, ptr %t330
  %t331 = call ptr @__alloc(i64 16, i32 1)
  %t332 = inttoptr i64 24 to ptr
  %t333 = getelementptr ptr, ptr %t331, i32 0
  store ptr %t332, ptr %t333
  %t334 = call ptr @__alloc(i64 16, i32 1)
  %t335 = inttoptr i64 25 to ptr
  %t336 = getelementptr ptr, ptr %t334, i32 0
  store ptr %t335, ptr %t336
  %t337 = getelementptr ptr, ptr %t334, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.7, i64 12), ptr %t337
  %t338 = getelementptr ptr, ptr %t331, i32 1
  store ptr %t334, ptr %t338
  %t339 = getelementptr ptr, ptr %t328, i32 1
  store ptr %t331, ptr %t339
  %t340 = getelementptr ptr, ptr %t328, i32 1
  %t341 = load ptr, ptr %t340
  call void @__inc_ref(ptr %t341)
  %t342 = getelementptr ptr, ptr %t341, i32 0
  %t343 = load ptr, ptr %t342
  %t344 = ptrtoint ptr %t343 to i64
  switch i64 %t344, label %case.default.345 [ i64 24, label %case.arm.24.347 i64 25, label %case.arm.25.353 ]
case.arm.24.347:
  %t349 = getelementptr ptr, ptr %t341, i32 1
  %t350 = load ptr, ptr %t349
  call void @__inc_ref(ptr %t350)
  %t351 = getelementptr ptr, ptr %t350, i32 1
  %t352 = load ptr, ptr %t351
  call void @__inc_ref(ptr %t352)
  br label %case.end.24.348
case.end.24.348:
  br label %case.join.346
case.arm.25.353:
  %t355 = getelementptr ptr, ptr %t341, i32 1
  %t356 = load ptr, ptr %t355
  call void @__inc_ref(ptr %t356)
  %t357 = getelementptr ptr, ptr %t356, i32 1
  %t358 = load ptr, ptr %t357
  call void @__inc_ref(ptr %t358)
  br label %case.end.25.354
case.end.25.354:
  br label %case.join.346
case.default.345:
  unreachable
case.join.346:
  %t359 = phi ptr [ %t352, %case.end.24.348 ], [ %t358, %case.end.25.354 ]
  call void @__free_recursive(ptr %t341)
  call void @__free_recursive(ptr %t328)
  %t360 = call ptr @__concat(ptr %t327, ptr %t359)
  %t361 = getelementptr ptr, ptr %t360, i32 0
  %t362 = load ptr, ptr %t361
  %t363 = ptrtoint ptr %t362 to i64
  switch i64 %t363, label %case.default.364 [ i64 3, label %case.arm.3.366 i64 4, label %case.arm.4.374 ]
case.arm.3.366:
  %t368 = getelementptr ptr, ptr %t360, i32 1
  %t369 = load ptr, ptr %t368
  call void @__inc_ref(ptr %t369)
  %t370 = call ptr @__alloc(i64 16, i32 1)
  %t371 = inttoptr i64 3 to ptr
  %t372 = getelementptr ptr, ptr %t370, i32 0
  store ptr %t371, ptr %t372
  call void @__inc_ref(ptr %t369)
  %t373 = getelementptr ptr, ptr %t370, i32 1
  store ptr %t369, ptr %t373
  br label %case.end.3.367
case.end.3.367:
  br label %case.join.365
case.arm.4.374:
  %t376 = getelementptr ptr, ptr %t360, i32 1
  %t377 = load ptr, ptr %t376
  call void @__inc_ref(ptr %t377)
  call void @__inc_ref(ptr %t377)
  %t378 = call ptr @__concat(ptr %t377, ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
  %t379 = getelementptr ptr, ptr %t378, i32 0
  %t380 = load ptr, ptr %t379
  %t381 = ptrtoint ptr %t380 to i64
  switch i64 %t381, label %case.default.382 [ i64 3, label %case.arm.3.384 i64 4, label %case.arm.4.392 ]
case.arm.3.384:
  %t386 = getelementptr ptr, ptr %t378, i32 1
  %t387 = load ptr, ptr %t386
  call void @__inc_ref(ptr %t387)
  %t388 = call ptr @__alloc(i64 16, i32 1)
  %t389 = inttoptr i64 3 to ptr
  %t390 = getelementptr ptr, ptr %t388, i32 0
  store ptr %t389, ptr %t390
  call void @__inc_ref(ptr %t387)
  %t391 = getelementptr ptr, ptr %t388, i32 1
  store ptr %t387, ptr %t391
  br label %case.end.3.385
case.end.3.385:
  br label %case.join.383
case.arm.4.392:
  %t394 = getelementptr ptr, ptr %t378, i32 1
  %t395 = load ptr, ptr %t394
  call void @__inc_ref(ptr %t395)
  call void @__inc_ref(ptr %t395)
  %t396 = call ptr @__alloc(i64 16, i32 1)
  %t397 = inttoptr i64 25 to ptr
  %t398 = getelementptr ptr, ptr %t396, i32 0
  store ptr %t397, ptr %t398
  %t399 = call ptr @__alloc(i64 16, i32 1)
  %t400 = inttoptr i64 25 to ptr
  %t401 = getelementptr ptr, ptr %t399, i32 0
  store ptr %t400, ptr %t401
  %t402 = call ptr @__alloc(i64 16, i32 1)
  %t403 = inttoptr i64 24 to ptr
  %t404 = getelementptr ptr, ptr %t402, i32 0
  store ptr %t403, ptr %t404
  %t405 = getelementptr ptr, ptr %t402, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.8, i64 12), ptr %t405
  %t406 = getelementptr ptr, ptr %t399, i32 1
  store ptr %t402, ptr %t406
  %t407 = getelementptr ptr, ptr %t396, i32 1
  store ptr %t399, ptr %t407
  %t408 = getelementptr ptr, ptr %t396, i32 1
  %t409 = load ptr, ptr %t408
  call void @__inc_ref(ptr %t409)
  %t410 = getelementptr ptr, ptr %t409, i32 0
  %t411 = load ptr, ptr %t410
  %t412 = ptrtoint ptr %t411 to i64
  switch i64 %t412, label %case.default.413 [ i64 24, label %case.arm.24.415 i64 25, label %case.arm.25.421 ]
case.arm.24.415:
  %t417 = getelementptr ptr, ptr %t409, i32 1
  %t418 = load ptr, ptr %t417
  call void @__inc_ref(ptr %t418)
  %t419 = getelementptr ptr, ptr %t418, i32 1
  %t420 = load ptr, ptr %t419
  call void @__inc_ref(ptr %t420)
  br label %case.end.24.416
case.end.24.416:
  br label %case.join.414
case.arm.25.421:
  %t423 = getelementptr ptr, ptr %t409, i32 1
  %t424 = load ptr, ptr %t423
  call void @__inc_ref(ptr %t424)
  %t425 = getelementptr ptr, ptr %t424, i32 1
  %t426 = load ptr, ptr %t425
  call void @__inc_ref(ptr %t426)
  br label %case.end.25.422
case.end.25.422:
  br label %case.join.414
case.default.413:
  unreachable
case.join.414:
  %t427 = phi ptr [ %t420, %case.end.24.416 ], [ %t426, %case.end.25.422 ]
  call void @__free_recursive(ptr %t409)
  call void @__free_recursive(ptr %t396)
  %t428 = call ptr @__concat(ptr %t395, ptr %t427)
  %t429 = getelementptr ptr, ptr %t428, i32 0
  %t430 = load ptr, ptr %t429
  %t431 = ptrtoint ptr %t430 to i64
  switch i64 %t431, label %case.default.432 [ i64 3, label %case.arm.3.434 i64 4, label %case.arm.4.442 ]
case.arm.3.434:
  %t436 = getelementptr ptr, ptr %t428, i32 1
  %t437 = load ptr, ptr %t436
  call void @__inc_ref(ptr %t437)
  %t438 = call ptr @__alloc(i64 16, i32 1)
  %t439 = inttoptr i64 3 to ptr
  %t440 = getelementptr ptr, ptr %t438, i32 0
  store ptr %t439, ptr %t440
  call void @__inc_ref(ptr %t437)
  %t441 = getelementptr ptr, ptr %t438, i32 1
  store ptr %t437, ptr %t441
  br label %case.end.3.435
case.end.3.435:
  br label %case.join.433
case.arm.4.442:
  %t444 = getelementptr ptr, ptr %t428, i32 1
  %t445 = load ptr, ptr %t444
  call void @__inc_ref(ptr %t445)
  call void @__inc_ref(ptr %t445)
  %t446 = call ptr @__concat(ptr %t445, ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
  %t447 = getelementptr ptr, ptr %t446, i32 0
  %t448 = load ptr, ptr %t447
  %t449 = ptrtoint ptr %t448 to i64
  switch i64 %t449, label %case.default.450 [ i64 3, label %case.arm.3.452 i64 4, label %case.arm.4.460 ]
case.arm.3.452:
  %t454 = getelementptr ptr, ptr %t446, i32 1
  %t455 = load ptr, ptr %t454
  call void @__inc_ref(ptr %t455)
  %t456 = call ptr @__alloc(i64 16, i32 1)
  %t457 = inttoptr i64 3 to ptr
  %t458 = getelementptr ptr, ptr %t456, i32 0
  store ptr %t457, ptr %t458
  call void @__inc_ref(ptr %t455)
  %t459 = getelementptr ptr, ptr %t456, i32 1
  store ptr %t455, ptr %t459
  br label %case.end.3.453
case.end.3.453:
  br label %case.join.451
case.arm.4.460:
  %t462 = getelementptr ptr, ptr %t446, i32 1
  %t463 = load ptr, ptr %t462
  call void @__inc_ref(ptr %t463)
  call void @__inc_ref(ptr %t463)
  %t464 = call ptr @__alloc(i64 16, i32 1)
  %t465 = inttoptr i64 25 to ptr
  %t466 = getelementptr ptr, ptr %t464, i32 0
  store ptr %t465, ptr %t466
  %t467 = call ptr @__alloc(i64 16, i32 1)
  %t468 = inttoptr i64 25 to ptr
  %t469 = getelementptr ptr, ptr %t467, i32 0
  store ptr %t468, ptr %t469
  %t470 = call ptr @__alloc(i64 16, i32 1)
  %t471 = inttoptr i64 25 to ptr
  %t472 = getelementptr ptr, ptr %t470, i32 0
  store ptr %t471, ptr %t472
  %t473 = getelementptr ptr, ptr %t470, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.9, i64 12), ptr %t473
  %t474 = getelementptr ptr, ptr %t467, i32 1
  store ptr %t470, ptr %t474
  %t475 = getelementptr ptr, ptr %t464, i32 1
  store ptr %t467, ptr %t475
  %t476 = getelementptr ptr, ptr %t464, i32 1
  %t477 = load ptr, ptr %t476
  call void @__inc_ref(ptr %t477)
  %t478 = getelementptr ptr, ptr %t477, i32 0
  %t479 = load ptr, ptr %t478
  %t480 = ptrtoint ptr %t479 to i64
  switch i64 %t480, label %case.default.481 [ i64 24, label %case.arm.24.483 i64 25, label %case.arm.25.489 ]
case.arm.24.483:
  %t485 = getelementptr ptr, ptr %t477, i32 1
  %t486 = load ptr, ptr %t485
  call void @__inc_ref(ptr %t486)
  %t487 = getelementptr ptr, ptr %t486, i32 1
  %t488 = load ptr, ptr %t487
  call void @__inc_ref(ptr %t488)
  br label %case.end.24.484
case.end.24.484:
  br label %case.join.482
case.arm.25.489:
  %t491 = getelementptr ptr, ptr %t477, i32 1
  %t492 = load ptr, ptr %t491
  call void @__inc_ref(ptr %t492)
  %t493 = getelementptr ptr, ptr %t492, i32 1
  %t494 = load ptr, ptr %t493
  call void @__inc_ref(ptr %t494)
  br label %case.end.25.490
case.end.25.490:
  br label %case.join.482
case.default.481:
  unreachable
case.join.482:
  %t495 = phi ptr [ %t488, %case.end.24.484 ], [ %t494, %case.end.25.490 ]
  call void @__free_recursive(ptr %t477)
  call void @__free_recursive(ptr %t464)
  %t496 = call ptr @__concat(ptr %t463, ptr %t495)
  br label %case.end.4.461
case.end.4.461:
  br label %case.join.451
case.default.450:
  unreachable
case.join.451:
  %t497 = phi ptr [ %t456, %case.end.3.453 ], [ %t496, %case.end.4.461 ]
  call void @__free_recursive(ptr %t446)
  br label %case.end.4.443
case.end.4.443:
  br label %case.join.433
case.default.432:
  unreachable
case.join.433:
  %t498 = phi ptr [ %t438, %case.end.3.435 ], [ %t497, %case.end.4.443 ]
  call void @__free_recursive(ptr %t428)
  br label %case.end.4.393
case.end.4.393:
  br label %case.join.383
case.default.382:
  unreachable
case.join.383:
  %t499 = phi ptr [ %t388, %case.end.3.385 ], [ %t498, %case.end.4.393 ]
  call void @__free_recursive(ptr %t378)
  br label %case.end.4.375
case.end.4.375:
  br label %case.join.365
case.default.364:
  unreachable
case.join.365:
  %t500 = phi ptr [ %t370, %case.end.3.367 ], [ %t499, %case.end.4.375 ]
  call void @__free_recursive(ptr %t360)
  br label %case.end.4.325
case.end.4.325:
  br label %case.join.315
case.default.314:
  unreachable
case.join.315:
  %t501 = phi ptr [ %t320, %case.end.3.317 ], [ %t500, %case.end.4.325 ]
  call void @__free_recursive(ptr %t310)
  br label %case.end.4.307
case.end.4.307:
  br label %case.join.297
case.default.296:
  unreachable
case.join.297:
  %t502 = phi ptr [ %t302, %case.end.3.299 ], [ %t501, %case.end.4.307 ]
  call void @__free_recursive(ptr %t292)
  br label %case.end.4.257
case.end.4.257:
  br label %case.join.247
case.default.246:
  unreachable
case.join.247:
  %t503 = phi ptr [ %t252, %case.end.3.249 ], [ %t502, %case.end.4.257 ]
  call void @__free_recursive(ptr %t242)
  br label %case.end.4.239
case.end.4.239:
  br label %case.join.229
case.default.228:
  unreachable
case.join.229:
  %t504 = phi ptr [ %t234, %case.end.3.231 ], [ %t503, %case.end.4.239 ]
  call void @__free_recursive(ptr %t224)
  br label %case.end.4.189
case.end.4.189:
  br label %case.join.179
case.default.178:
  unreachable
case.join.179:
  %t505 = phi ptr [ %t184, %case.end.3.181 ], [ %t504, %case.end.4.189 ]
  call void @__free_recursive(ptr %t174)
  br label %case.end.4.171
case.end.4.171:
  br label %case.join.161
case.default.160:
  unreachable
case.join.161:
  %t506 = phi ptr [ %t166, %case.end.3.163 ], [ %t505, %case.end.4.171 ]
  call void @__free_recursive(ptr %t156)
  br label %case.end.4.121
case.end.4.121:
  br label %case.join.111
case.default.110:
  unreachable
case.join.111:
  %t507 = phi ptr [ %t116, %case.end.3.113 ], [ %t506, %case.end.4.121 ]
  call void @__free_recursive(ptr %t106)
  br label %case.end.4.103
case.end.4.103:
  br label %case.join.93
case.default.92:
  unreachable
case.join.93:
  %t508 = phi ptr [ %t98, %case.end.3.95 ], [ %t507, %case.end.4.103 ]
  call void @__free_recursive(ptr %t88)
  call void @__free_recursive(ptr %t34)
  store ptr %t508, ptr %v__inl28_scrut.jslot
  br label %join.0
join.case.default.38:
  unreachable
join.0:
  %t509 = load ptr, ptr %v__inl28_scrut.jslot
  %t510 = getelementptr ptr, ptr %t509, i32 0
  %t511 = load ptr, ptr %t510
  %t512 = ptrtoint ptr %t511 to i64
  switch i64 %t512, label %case.default.513 [ i64 3, label %case.arm.3.515 i64 4, label %case.arm.4.529 ]
case.arm.3.515:
  %t517 = call ptr @__alloc(i64 24, i32 2)
  %t518 = inttoptr i64 7 to ptr
  %t519 = getelementptr ptr, ptr %t517, i32 0
  store ptr %t518, ptr %t519
  %t520 = getelementptr ptr, ptr %t517, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t520
  %t521 = call ptr @__alloc(i64 16, i32 1)
  %t522 = inttoptr i64 5 to ptr
  %t523 = getelementptr ptr, ptr %t521, i32 0
  store ptr %t522, ptr %t523
  %t524 = call ptr @__alloc(i64 8, i32 0)
  %t525 = inttoptr i64 0 to ptr
  %t526 = getelementptr ptr, ptr %t524, i32 0
  store ptr %t525, ptr %t526
  %t527 = getelementptr ptr, ptr %t521, i32 1
  store ptr %t524, ptr %t527
  %t528 = getelementptr ptr, ptr %t517, i32 2
  store ptr %t521, ptr %t528
  br label %case.end.3.516
case.end.3.516:
  br label %case.join.514
case.arm.4.529:
  %t531 = call ptr @__alloc(i64 24, i32 2)
  %t532 = inttoptr i64 7 to ptr
  %t533 = getelementptr ptr, ptr %t531, i32 0
  store ptr %t532, ptr %t533
  %t534 = getelementptr ptr, ptr %t509, i32 1
  %t535 = load ptr, ptr %t534
  call void @__inc_ref(ptr %t535)
  %t536 = getelementptr ptr, ptr %t531, i32 1
  store ptr %t535, ptr %t536
  %t537 = call ptr @__alloc(i64 16, i32 1)
  %t538 = inttoptr i64 5 to ptr
  %t539 = getelementptr ptr, ptr %t537, i32 0
  store ptr %t538, ptr %t539
  %t540 = call ptr @__alloc(i64 8, i32 0)
  %t541 = inttoptr i64 0 to ptr
  %t542 = getelementptr ptr, ptr %t540, i32 0
  store ptr %t541, ptr %t542
  %t543 = getelementptr ptr, ptr %t537, i32 1
  store ptr %t540, ptr %t543
  %t544 = getelementptr ptr, ptr %t531, i32 2
  store ptr %t537, ptr %t544
  br label %case.end.4.530
case.end.4.530:
  br label %case.join.514
case.default.513:
  unreachable
case.join.514:
  %t545 = phi ptr [ %t517, %case.end.3.516 ], [ %t531, %case.end.4.530 ]
  call void @__free_recursive(ptr %t509)
  br label %join.end.546
join.end.546:
  br label %join.after.1
join.after.1:
  %t547 = phi ptr [ %t40, %join.val.52 ], [ %t545, %join.end.546 ]
  ret ptr %t547
}

define i32 @main(i32 %argc, ptr %argv) {
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
