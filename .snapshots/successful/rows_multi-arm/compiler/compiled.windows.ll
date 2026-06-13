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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [7 x i8]} { i32 0, i32 0, i32 0, i32 7, i32 7, [7 x i8] c"Nothing" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [9 x i8]} { i32 0, i32 0, i32 0, i32 9, i32 9, [9 x i8] c"Just True" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [10 x i8]} { i32 0, i32 0, i32 0, i32 10, i32 10, [10 x i8] c"Just False" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"Just " }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"Unit" }
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"; " }
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

define internal ptr @v_summary() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 12 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 8, i32 0)
  %t4 = inttoptr i64 1 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  %t7 = getelementptr ptr, ptr %t0, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %case.default.10 [ i64 11, label %case.arm.11.12 i64 12, label %case.arm.12.14 ]
case.arm.11.12:
  call void @__inc_ref(ptr %t0)
  br label %case.end.11.13
case.end.11.13:
  br label %case.join.11
case.arm.12.14:
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 12 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = call ptr @__alloc(i64 16, i32 1)
  %t20 = inttoptr i64 796142685 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr ptr, ptr %t0, i32 1
  %t23 = load ptr, ptr %t22
  call void @__inc_ref(ptr %t23)
  %t24 = getelementptr ptr, ptr %t19, i32 1
  store ptr %t23, ptr %t24
  %t25 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t19, ptr %t25
  br label %case.end.12.15
case.end.12.15:
  br label %case.join.11
case.default.10:
  unreachable
case.join.11:
  %t26 = phi ptr [ %t0, %case.end.11.13 ], [ %t16, %case.end.12.15 ]
  %t27 = getelementptr ptr, ptr %t26, i32 0
  %t28 = load ptr, ptr %t27
  %t29 = ptrtoint ptr %t28 to i64
  switch i64 %t29, label %case.default.30 [ i64 11, label %case.arm.11.32 i64 12, label %case.arm.12.38 ]
case.arm.11.32:
  %t34 = call ptr @__alloc(i64 16, i32 1)
  %t35 = inttoptr i64 4 to ptr
  %t36 = getelementptr ptr, ptr %t34, i32 0
  store ptr %t35, ptr %t36
  %t37 = getelementptr ptr, ptr %t34, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t37
  br label %case.end.11.33
case.end.11.33:
  br label %case.join.31
case.arm.12.38:
  %t40 = getelementptr ptr, ptr %t26, i32 1
  %t41 = load ptr, ptr %t40
  call void @__inc_ref(ptr %t41)
  %t42 = getelementptr ptr, ptr %t41, i32 0
  %t43 = load ptr, ptr %t42
  %t44 = ptrtoint ptr %t43 to i64
  switch i64 %t44, label %case.default.45 [ i64 796142685, label %case.arm.796142685.47 i64 1759602215, label %case.arm.1759602215.69 ]
case.arm.796142685.47:
  %t49 = getelementptr ptr, ptr %t41, i32 1
  %t50 = load ptr, ptr %t49
  call void @__inc_ref(ptr %t50)
  %t51 = getelementptr ptr, ptr %t50, i32 0
  %t52 = load ptr, ptr %t51
  %t53 = ptrtoint ptr %t52 to i64
  switch i64 %t53, label %case.default.54 [ i64 1, label %case.arm.1.56 i64 2, label %case.arm.2.62 ]
case.arm.1.56:
  %t58 = call ptr @__alloc(i64 16, i32 1)
  %t59 = inttoptr i64 4 to ptr
  %t60 = getelementptr ptr, ptr %t58, i32 0
  store ptr %t59, ptr %t60
  %t61 = getelementptr ptr, ptr %t58, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t61
  br label %case.end.1.57
case.end.1.57:
  br label %case.join.55
case.arm.2.62:
  %t64 = call ptr @__alloc(i64 16, i32 1)
  %t65 = inttoptr i64 4 to ptr
  %t66 = getelementptr ptr, ptr %t64, i32 0
  store ptr %t65, ptr %t66
  %t67 = getelementptr ptr, ptr %t64, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t67
  br label %case.end.2.63
case.end.2.63:
  br label %case.join.55
case.default.54:
  unreachable
case.join.55:
  %t68 = phi ptr [ %t58, %case.end.1.57 ], [ %t64, %case.end.2.63 ]
  call void @__free_recursive(ptr %t50)
  br label %case.end.796142685.48
case.end.796142685.48:
  br label %case.join.46
case.arm.1759602215.69:
  %t71 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  br label %case.end.1759602215.70
case.end.1759602215.70:
  br label %case.join.46
case.default.45:
  unreachable
case.join.46:
  %t72 = phi ptr [ %t68, %case.end.796142685.48 ], [ %t71, %case.end.1759602215.70 ]
  br label %case.end.12.39
case.end.12.39:
  br label %case.join.31
case.default.30:
  unreachable
case.join.31:
  %t73 = phi ptr [ %t34, %case.end.11.33 ], [ %t72, %case.end.12.39 ]
  call void @__free_recursive(ptr %t26)
  %t74 = getelementptr ptr, ptr %t73, i32 0
  %t75 = load ptr, ptr %t74
  %t76 = ptrtoint ptr %t75 to i64
  switch i64 %t76, label %case.default.77 [ i64 3, label %case.arm.3.79 i64 4, label %case.arm.4.87 ]
case.arm.3.79:
  %t81 = getelementptr ptr, ptr %t73, i32 1
  %t82 = load ptr, ptr %t81
  call void @__inc_ref(ptr %t82)
  %t83 = call ptr @__alloc(i64 16, i32 1)
  %t84 = inttoptr i64 3 to ptr
  %t85 = getelementptr ptr, ptr %t83, i32 0
  store ptr %t84, ptr %t85
  call void @__inc_ref(ptr %t82)
  %t86 = getelementptr ptr, ptr %t83, i32 1
  store ptr %t82, ptr %t86
  br label %case.end.3.80
case.end.3.80:
  br label %case.join.78
case.arm.4.87:
  %t89 = getelementptr ptr, ptr %t73, i32 1
  %t90 = load ptr, ptr %t89
  call void @__inc_ref(ptr %t90)
  %t91 = call ptr @__alloc(i64 16, i32 1)
  %t92 = inttoptr i64 12 to ptr
  %t93 = getelementptr ptr, ptr %t91, i32 0
  store ptr %t92, ptr %t93
  %t94 = call ptr @__alloc(i64 8, i32 0)
  %t95 = inttoptr i64 0 to ptr
  %t96 = getelementptr ptr, ptr %t94, i32 0
  store ptr %t95, ptr %t96
  %t97 = getelementptr ptr, ptr %t91, i32 1
  store ptr %t94, ptr %t97
  %t98 = getelementptr ptr, ptr %t91, i32 0
  %t99 = load ptr, ptr %t98
  %t100 = ptrtoint ptr %t99 to i64
  switch i64 %t100, label %case.default.101 [ i64 11, label %case.arm.11.103 i64 12, label %case.arm.12.105 ]
case.arm.11.103:
  call void @__inc_ref(ptr %t91)
  br label %case.end.11.104
case.end.11.104:
  br label %case.join.102
case.arm.12.105:
  %t107 = call ptr @__alloc(i64 16, i32 1)
  %t108 = inttoptr i64 12 to ptr
  %t109 = getelementptr ptr, ptr %t107, i32 0
  store ptr %t108, ptr %t109
  %t110 = call ptr @__alloc(i64 16, i32 1)
  %t111 = inttoptr i64 1759602215 to ptr
  %t112 = getelementptr ptr, ptr %t110, i32 0
  store ptr %t111, ptr %t112
  %t113 = getelementptr ptr, ptr %t91, i32 1
  %t114 = load ptr, ptr %t113
  call void @__inc_ref(ptr %t114)
  %t115 = getelementptr ptr, ptr %t110, i32 1
  store ptr %t114, ptr %t115
  %t116 = getelementptr ptr, ptr %t107, i32 1
  store ptr %t110, ptr %t116
  br label %case.end.12.106
case.end.12.106:
  br label %case.join.102
case.default.101:
  unreachable
case.join.102:
  %t117 = phi ptr [ %t91, %case.end.11.104 ], [ %t107, %case.end.12.106 ]
  %t118 = getelementptr ptr, ptr %t117, i32 0
  %t119 = load ptr, ptr %t118
  %t120 = ptrtoint ptr %t119 to i64
  switch i64 %t120, label %case.default.121 [ i64 11, label %case.arm.11.123 i64 12, label %case.arm.12.129 ]
case.arm.11.123:
  %t125 = call ptr @__alloc(i64 16, i32 1)
  %t126 = inttoptr i64 4 to ptr
  %t127 = getelementptr ptr, ptr %t125, i32 0
  store ptr %t126, ptr %t127
  %t128 = getelementptr ptr, ptr %t125, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t128
  br label %case.end.11.124
case.end.11.124:
  br label %case.join.122
case.arm.12.129:
  %t131 = getelementptr ptr, ptr %t117, i32 1
  %t132 = load ptr, ptr %t131
  call void @__inc_ref(ptr %t132)
  %t133 = getelementptr ptr, ptr %t132, i32 0
  %t134 = load ptr, ptr %t133
  %t135 = ptrtoint ptr %t134 to i64
  switch i64 %t135, label %case.default.136 [ i64 796142685, label %case.arm.796142685.138 i64 1759602215, label %case.arm.1759602215.160 ]
case.arm.796142685.138:
  %t140 = getelementptr ptr, ptr %t132, i32 1
  %t141 = load ptr, ptr %t140
  call void @__inc_ref(ptr %t141)
  %t142 = getelementptr ptr, ptr %t141, i32 0
  %t143 = load ptr, ptr %t142
  %t144 = ptrtoint ptr %t143 to i64
  switch i64 %t144, label %case.default.145 [ i64 1, label %case.arm.1.147 i64 2, label %case.arm.2.153 ]
case.arm.1.147:
  %t149 = call ptr @__alloc(i64 16, i32 1)
  %t150 = inttoptr i64 4 to ptr
  %t151 = getelementptr ptr, ptr %t149, i32 0
  store ptr %t150, ptr %t151
  %t152 = getelementptr ptr, ptr %t149, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t152
  br label %case.end.1.148
case.end.1.148:
  br label %case.join.146
case.arm.2.153:
  %t155 = call ptr @__alloc(i64 16, i32 1)
  %t156 = inttoptr i64 4 to ptr
  %t157 = getelementptr ptr, ptr %t155, i32 0
  store ptr %t156, ptr %t157
  %t158 = getelementptr ptr, ptr %t155, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t158
  br label %case.end.2.154
case.end.2.154:
  br label %case.join.146
case.default.145:
  unreachable
case.join.146:
  %t159 = phi ptr [ %t149, %case.end.1.148 ], [ %t155, %case.end.2.154 ]
  call void @__free_recursive(ptr %t141)
  br label %case.end.796142685.139
case.end.796142685.139:
  br label %case.join.137
case.arm.1759602215.160:
  %t162 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  br label %case.end.1759602215.161
case.end.1759602215.161:
  br label %case.join.137
case.default.136:
  unreachable
case.join.137:
  %t163 = phi ptr [ %t159, %case.end.796142685.139 ], [ %t162, %case.end.1759602215.161 ]
  br label %case.end.12.130
case.end.12.130:
  br label %case.join.122
case.default.121:
  unreachable
case.join.122:
  %t164 = phi ptr [ %t125, %case.end.11.124 ], [ %t163, %case.end.12.130 ]
  call void @__free_recursive(ptr %t117)
  %t165 = getelementptr ptr, ptr %t164, i32 0
  %t166 = load ptr, ptr %t165
  %t167 = ptrtoint ptr %t166 to i64
  switch i64 %t167, label %case.default.168 [ i64 3, label %case.arm.3.170 i64 4, label %case.arm.4.178 ]
case.arm.3.170:
  %t172 = getelementptr ptr, ptr %t164, i32 1
  %t173 = load ptr, ptr %t172
  call void @__inc_ref(ptr %t173)
  %t174 = call ptr @__alloc(i64 16, i32 1)
  %t175 = inttoptr i64 3 to ptr
  %t176 = getelementptr ptr, ptr %t174, i32 0
  store ptr %t175, ptr %t176
  call void @__inc_ref(ptr %t173)
  %t177 = getelementptr ptr, ptr %t174, i32 1
  store ptr %t173, ptr %t177
  br label %case.end.3.171
case.end.3.171:
  br label %case.join.169
case.arm.4.178:
  %t180 = getelementptr ptr, ptr %t164, i32 1
  %t181 = load ptr, ptr %t180
  call void @__inc_ref(ptr %t181)
  call void @__inc_ref(ptr %t90)
  %t182 = call ptr @__concat(ptr %t90, ptr getelementptr inbounds (i8, ptr @.str.5, i64 12))
  %t183 = getelementptr ptr, ptr %t182, i32 0
  %t184 = load ptr, ptr %t183
  %t185 = ptrtoint ptr %t184 to i64
  switch i64 %t185, label %case.default.186 [ i64 3, label %case.arm.3.188 i64 4, label %case.arm.4.196 ]
case.arm.3.188:
  %t190 = getelementptr ptr, ptr %t182, i32 1
  %t191 = load ptr, ptr %t190
  call void @__inc_ref(ptr %t191)
  %t192 = call ptr @__alloc(i64 16, i32 1)
  %t193 = inttoptr i64 3 to ptr
  %t194 = getelementptr ptr, ptr %t192, i32 0
  store ptr %t193, ptr %t194
  call void @__inc_ref(ptr %t191)
  %t195 = getelementptr ptr, ptr %t192, i32 1
  store ptr %t191, ptr %t195
  br label %case.end.3.189
case.end.3.189:
  br label %case.join.187
case.arm.4.196:
  %t198 = getelementptr ptr, ptr %t182, i32 1
  %t199 = load ptr, ptr %t198
  call void @__inc_ref(ptr %t199)
  call void @__inc_ref(ptr %t199)
  call void @__inc_ref(ptr %t181)
  %t200 = call ptr @__concat(ptr %t199, ptr %t181)
  %t201 = getelementptr ptr, ptr %t200, i32 0
  %t202 = load ptr, ptr %t201
  %t203 = ptrtoint ptr %t202 to i64
  switch i64 %t203, label %case.default.204 [ i64 3, label %case.arm.3.206 i64 4, label %case.arm.4.214 ]
case.arm.3.206:
  %t208 = getelementptr ptr, ptr %t200, i32 1
  %t209 = load ptr, ptr %t208
  call void @__inc_ref(ptr %t209)
  %t210 = call ptr @__alloc(i64 16, i32 1)
  %t211 = inttoptr i64 3 to ptr
  %t212 = getelementptr ptr, ptr %t210, i32 0
  store ptr %t211, ptr %t212
  call void @__inc_ref(ptr %t209)
  %t213 = getelementptr ptr, ptr %t210, i32 1
  store ptr %t209, ptr %t213
  br label %case.end.3.207
case.end.3.207:
  br label %case.join.205
case.arm.4.214:
  %t216 = getelementptr ptr, ptr %t200, i32 1
  %t217 = load ptr, ptr %t216
  call void @__inc_ref(ptr %t217)
  call void @__inc_ref(ptr %t217)
  %t218 = call ptr @__concat(ptr %t217, ptr getelementptr inbounds (i8, ptr @.str.5, i64 12))
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
  %t236 = call ptr @__concat(ptr %t235, ptr getelementptr inbounds (i8, ptr @.str.0, i64 12))
  br label %case.end.4.233
case.end.4.233:
  br label %case.join.223
case.default.222:
  unreachable
case.join.223:
  %t237 = phi ptr [ %t228, %case.end.3.225 ], [ %t236, %case.end.4.233 ]
  call void @__free_recursive(ptr %t218)
  br label %case.end.4.215
case.end.4.215:
  br label %case.join.205
case.default.204:
  unreachable
case.join.205:
  %t238 = phi ptr [ %t210, %case.end.3.207 ], [ %t237, %case.end.4.215 ]
  call void @__free_recursive(ptr %t200)
  br label %case.end.4.197
case.end.4.197:
  br label %case.join.187
case.default.186:
  unreachable
case.join.187:
  %t239 = phi ptr [ %t192, %case.end.3.189 ], [ %t238, %case.end.4.197 ]
  call void @__free_recursive(ptr %t182)
  br label %case.end.4.179
case.end.4.179:
  br label %case.join.169
case.default.168:
  unreachable
case.join.169:
  %t240 = phi ptr [ %t174, %case.end.3.171 ], [ %t239, %case.end.4.179 ]
  call void @__free_recursive(ptr %t164)
  call void @__free_recursive(ptr %t91)
  br label %case.end.4.88
case.end.4.88:
  br label %case.join.78
case.default.77:
  unreachable
case.join.78:
  %t241 = phi ptr [ %t83, %case.end.3.80 ], [ %t240, %case.end.4.88 ]
  call void @__free_recursive(ptr %t73)
  call void @__free_recursive(ptr %t0)
  ret ptr %t241
}

define internal ptr @v_main() {
  %t0 = call ptr @v_summary()
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 3, label %case.arm.3.6 i64 4, label %case.arm.4.20 ]
case.arm.3.6:
  %t8 = call ptr @__alloc(i64 24, i32 2)
  %t9 = inttoptr i64 7 to ptr
  %t10 = getelementptr ptr, ptr %t8, i32 0
  store ptr %t9, ptr %t10
  %t11 = getelementptr ptr, ptr %t8, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.6, i64 12), ptr %t11
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
  br label %case.end.3.7
case.end.3.7:
  br label %case.join.5
case.arm.4.20:
  %t22 = getelementptr ptr, ptr %t0, i32 1
  %t23 = load ptr, ptr %t22
  call void @__inc_ref(ptr %t23)
  %t24 = call ptr @__alloc(i64 24, i32 2)
  %t25 = inttoptr i64 7 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  call void @__inc_ref(ptr %t23)
  %t27 = getelementptr ptr, ptr %t24, i32 1
  store ptr %t23, ptr %t27
  %t28 = call ptr @__alloc(i64 16, i32 1)
  %t29 = inttoptr i64 5 to ptr
  %t30 = getelementptr ptr, ptr %t28, i32 0
  store ptr %t29, ptr %t30
  %t31 = call ptr @__alloc(i64 8, i32 0)
  %t32 = inttoptr i64 0 to ptr
  %t33 = getelementptr ptr, ptr %t31, i32 0
  store ptr %t32, ptr %t33
  %t34 = getelementptr ptr, ptr %t28, i32 1
  store ptr %t31, ptr %t34
  %t35 = getelementptr ptr, ptr %t24, i32 2
  store ptr %t28, ptr %t35
  br label %case.end.4.21
case.end.4.21:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t36 = phi ptr [ %t8, %case.end.3.7 ], [ %t24, %case.end.4.21 ]
  call void @__free_recursive(ptr %t0)
  ret ptr %t36
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
