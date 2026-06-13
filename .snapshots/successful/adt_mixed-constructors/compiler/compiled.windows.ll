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
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"word:" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"num:" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"," }
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"<eof>" }
@.str.6 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"42" }
@.str.7 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c" " }

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
  %v__inl16_scrut.jslot = alloca ptr
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 24 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t3
  %t6 = getelementptr ptr, ptr %t0, i32 0
  %t7 = load ptr, ptr %t6
  %t8 = ptrtoint ptr %t7 to i64
  switch i64 %t8, label %case.default.9 [ i64 24, label %case.arm.24.11 i64 25, label %case.arm.25.16 i64 26, label %case.arm.26.21 i64 27, label %case.arm.27.27 ]
case.arm.24.11:
  %t13 = getelementptr ptr, ptr %t0, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  %t15 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t14)
  br label %case.end.24.12
case.end.24.12:
  br label %case.join.10
case.arm.25.16:
  %t18 = getelementptr ptr, ptr %t0, i32 1
  %t19 = load ptr, ptr %t18
  call void @__inc_ref(ptr %t19)
  %t20 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t19)
  br label %case.end.25.17
case.end.25.17:
  br label %case.join.10
case.arm.26.21:
  %t23 = call ptr @__alloc(i64 16, i32 1)
  %t24 = inttoptr i64 4 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  %t26 = getelementptr ptr, ptr %t23, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t26
  br label %case.end.26.22
case.end.26.22:
  br label %case.join.10
case.arm.27.27:
  %t29 = call ptr @__alloc(i64 16, i32 1)
  %t30 = inttoptr i64 4 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = getelementptr ptr, ptr %t29, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.5, i64 12), ptr %t32
  br label %case.end.27.28
case.end.27.28:
  br label %case.join.10
case.default.9:
  unreachable
case.join.10:
  %t33 = phi ptr [ %t15, %case.end.24.12 ], [ %t20, %case.end.25.17 ], [ %t23, %case.end.26.22 ], [ %t29, %case.end.27.28 ]
  %t34 = getelementptr ptr, ptr %t33, i32 0
  %t35 = load ptr, ptr %t34
  %t36 = ptrtoint ptr %t35 to i64
  switch i64 %t36, label %join.case.default.37 [ i64 3, label %join.case.arm.3.38 i64 4, label %join.case.arm.4.52 ]
join.case.arm.3.38:
  %t39 = call ptr @__alloc(i64 24, i32 2)
  %t40 = inttoptr i64 7 to ptr
  %t41 = getelementptr ptr, ptr %t39, i32 0
  store ptr %t40, ptr %t41
  %t42 = getelementptr ptr, ptr %t39, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t42
  %t43 = call ptr @__alloc(i64 16, i32 1)
  %t44 = inttoptr i64 5 to ptr
  %t45 = getelementptr ptr, ptr %t43, i32 0
  store ptr %t44, ptr %t45
  %t46 = call ptr @__alloc(i64 8, i32 0)
  %t47 = inttoptr i64 0 to ptr
  %t48 = getelementptr ptr, ptr %t46, i32 0
  store ptr %t47, ptr %t48
  %t49 = getelementptr ptr, ptr %t43, i32 1
  store ptr %t46, ptr %t49
  %t50 = getelementptr ptr, ptr %t39, i32 2
  store ptr %t43, ptr %t50
  call void @__free_recursive(ptr %t33)
  br label %join.val.51
join.val.51:
  br label %join.after.5
join.case.arm.4.52:
  %t53 = getelementptr ptr, ptr %t33, i32 1
  %t54 = load ptr, ptr %t53
  call void @__inc_ref(ptr %t54)
  %t55 = call ptr @__alloc(i64 8, i32 0)
  %t56 = inttoptr i64 26 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  %t58 = getelementptr ptr, ptr %t55, i32 0
  %t59 = load ptr, ptr %t58
  %t60 = ptrtoint ptr %t59 to i64
  switch i64 %t60, label %case.default.61 [ i64 24, label %case.arm.24.63 i64 25, label %case.arm.25.68 i64 26, label %case.arm.26.73 i64 27, label %case.arm.27.79 ]
case.arm.24.63:
  %t65 = getelementptr ptr, ptr %t55, i32 1
  %t66 = load ptr, ptr %t65
  call void @__inc_ref(ptr %t66)
  %t67 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t66)
  br label %case.end.24.64
case.end.24.64:
  br label %case.join.62
case.arm.25.68:
  %t70 = getelementptr ptr, ptr %t55, i32 1
  %t71 = load ptr, ptr %t70
  call void @__inc_ref(ptr %t71)
  %t72 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t71)
  br label %case.end.25.69
case.end.25.69:
  br label %case.join.62
case.arm.26.73:
  %t75 = call ptr @__alloc(i64 16, i32 1)
  %t76 = inttoptr i64 4 to ptr
  %t77 = getelementptr ptr, ptr %t75, i32 0
  store ptr %t76, ptr %t77
  %t78 = getelementptr ptr, ptr %t75, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t78
  br label %case.end.26.74
case.end.26.74:
  br label %case.join.62
case.arm.27.79:
  %t81 = call ptr @__alloc(i64 16, i32 1)
  %t82 = inttoptr i64 4 to ptr
  %t83 = getelementptr ptr, ptr %t81, i32 0
  store ptr %t82, ptr %t83
  %t84 = getelementptr ptr, ptr %t81, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.5, i64 12), ptr %t84
  br label %case.end.27.80
case.end.27.80:
  br label %case.join.62
case.default.61:
  unreachable
case.join.62:
  %t85 = phi ptr [ %t67, %case.end.24.64 ], [ %t72, %case.end.25.69 ], [ %t75, %case.end.26.74 ], [ %t81, %case.end.27.80 ]
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
  %t103 = call ptr @__alloc(i64 16, i32 1)
  %t104 = inttoptr i64 25 to ptr
  %t105 = getelementptr ptr, ptr %t103, i32 0
  store ptr %t104, ptr %t105
  %t106 = getelementptr ptr, ptr %t103, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.6, i64 12), ptr %t106
  %t107 = getelementptr ptr, ptr %t103, i32 0
  %t108 = load ptr, ptr %t107
  %t109 = ptrtoint ptr %t108 to i64
  switch i64 %t109, label %case.default.110 [ i64 24, label %case.arm.24.112 i64 25, label %case.arm.25.117 i64 26, label %case.arm.26.122 i64 27, label %case.arm.27.128 ]
case.arm.24.112:
  %t114 = getelementptr ptr, ptr %t103, i32 1
  %t115 = load ptr, ptr %t114
  call void @__inc_ref(ptr %t115)
  %t116 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t115)
  br label %case.end.24.113
case.end.24.113:
  br label %case.join.111
case.arm.25.117:
  %t119 = getelementptr ptr, ptr %t103, i32 1
  %t120 = load ptr, ptr %t119
  call void @__inc_ref(ptr %t120)
  %t121 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t120)
  br label %case.end.25.118
case.end.25.118:
  br label %case.join.111
case.arm.26.122:
  %t124 = call ptr @__alloc(i64 16, i32 1)
  %t125 = inttoptr i64 4 to ptr
  %t126 = getelementptr ptr, ptr %t124, i32 0
  store ptr %t125, ptr %t126
  %t127 = getelementptr ptr, ptr %t124, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t127
  br label %case.end.26.123
case.end.26.123:
  br label %case.join.111
case.arm.27.128:
  %t130 = call ptr @__alloc(i64 16, i32 1)
  %t131 = inttoptr i64 4 to ptr
  %t132 = getelementptr ptr, ptr %t130, i32 0
  store ptr %t131, ptr %t132
  %t133 = getelementptr ptr, ptr %t130, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.5, i64 12), ptr %t133
  br label %case.end.27.129
case.end.27.129:
  br label %case.join.111
case.default.110:
  unreachable
case.join.111:
  %t134 = phi ptr [ %t116, %case.end.24.113 ], [ %t121, %case.end.25.118 ], [ %t124, %case.end.26.123 ], [ %t130, %case.end.27.129 ]
  %t135 = getelementptr ptr, ptr %t134, i32 0
  %t136 = load ptr, ptr %t135
  %t137 = ptrtoint ptr %t136 to i64
  switch i64 %t137, label %case.default.138 [ i64 3, label %case.arm.3.140 i64 4, label %case.arm.4.148 ]
case.arm.3.140:
  %t142 = getelementptr ptr, ptr %t134, i32 1
  %t143 = load ptr, ptr %t142
  call void @__inc_ref(ptr %t143)
  %t144 = call ptr @__alloc(i64 16, i32 1)
  %t145 = inttoptr i64 3 to ptr
  %t146 = getelementptr ptr, ptr %t144, i32 0
  store ptr %t145, ptr %t146
  call void @__inc_ref(ptr %t143)
  %t147 = getelementptr ptr, ptr %t144, i32 1
  store ptr %t143, ptr %t147
  br label %case.end.3.141
case.end.3.141:
  br label %case.join.139
case.arm.4.148:
  %t150 = getelementptr ptr, ptr %t134, i32 1
  %t151 = load ptr, ptr %t150
  call void @__inc_ref(ptr %t151)
  %t152 = call ptr @__alloc(i64 8, i32 0)
  %t153 = inttoptr i64 27 to ptr
  %t154 = getelementptr ptr, ptr %t152, i32 0
  store ptr %t153, ptr %t154
  %t155 = getelementptr ptr, ptr %t152, i32 0
  %t156 = load ptr, ptr %t155
  %t157 = ptrtoint ptr %t156 to i64
  switch i64 %t157, label %case.default.158 [ i64 24, label %case.arm.24.160 i64 25, label %case.arm.25.165 i64 26, label %case.arm.26.170 i64 27, label %case.arm.27.176 ]
case.arm.24.160:
  %t162 = getelementptr ptr, ptr %t152, i32 1
  %t163 = load ptr, ptr %t162
  call void @__inc_ref(ptr %t163)
  %t164 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t163)
  br label %case.end.24.161
case.end.24.161:
  br label %case.join.159
case.arm.25.165:
  %t167 = getelementptr ptr, ptr %t152, i32 1
  %t168 = load ptr, ptr %t167
  call void @__inc_ref(ptr %t168)
  %t169 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t168)
  br label %case.end.25.166
case.end.25.166:
  br label %case.join.159
case.arm.26.170:
  %t172 = call ptr @__alloc(i64 16, i32 1)
  %t173 = inttoptr i64 4 to ptr
  %t174 = getelementptr ptr, ptr %t172, i32 0
  store ptr %t173, ptr %t174
  %t175 = getelementptr ptr, ptr %t172, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t175
  br label %case.end.26.171
case.end.26.171:
  br label %case.join.159
case.arm.27.176:
  %t178 = call ptr @__alloc(i64 16, i32 1)
  %t179 = inttoptr i64 4 to ptr
  %t180 = getelementptr ptr, ptr %t178, i32 0
  store ptr %t179, ptr %t180
  %t181 = getelementptr ptr, ptr %t178, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.5, i64 12), ptr %t181
  br label %case.end.27.177
case.end.27.177:
  br label %case.join.159
case.default.158:
  unreachable
case.join.159:
  %t182 = phi ptr [ %t164, %case.end.24.161 ], [ %t169, %case.end.25.166 ], [ %t172, %case.end.26.171 ], [ %t178, %case.end.27.177 ]
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
  call void @__inc_ref(ptr %t54)
  %t200 = call ptr @__concat(ptr %t54, ptr getelementptr inbounds (i8, ptr @.str.7, i64 12))
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
  call void @__inc_ref(ptr %t102)
  %t218 = call ptr @__concat(ptr %t217, ptr %t102)
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
  %t236 = call ptr @__concat(ptr %t235, ptr getelementptr inbounds (i8, ptr @.str.7, i64 12))
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
  call void @__inc_ref(ptr %t151)
  %t254 = call ptr @__concat(ptr %t253, ptr %t151)
  %t255 = getelementptr ptr, ptr %t254, i32 0
  %t256 = load ptr, ptr %t255
  %t257 = ptrtoint ptr %t256 to i64
  switch i64 %t257, label %case.default.258 [ i64 3, label %case.arm.3.260 i64 4, label %case.arm.4.268 ]
case.arm.3.260:
  %t262 = getelementptr ptr, ptr %t254, i32 1
  %t263 = load ptr, ptr %t262
  call void @__inc_ref(ptr %t263)
  %t264 = call ptr @__alloc(i64 16, i32 1)
  %t265 = inttoptr i64 3 to ptr
  %t266 = getelementptr ptr, ptr %t264, i32 0
  store ptr %t265, ptr %t266
  call void @__inc_ref(ptr %t263)
  %t267 = getelementptr ptr, ptr %t264, i32 1
  store ptr %t263, ptr %t267
  br label %case.end.3.261
case.end.3.261:
  br label %case.join.259
case.arm.4.268:
  %t270 = getelementptr ptr, ptr %t254, i32 1
  %t271 = load ptr, ptr %t270
  call void @__inc_ref(ptr %t271)
  call void @__inc_ref(ptr %t271)
  %t272 = call ptr @__concat(ptr %t271, ptr getelementptr inbounds (i8, ptr @.str.7, i64 12))
  %t273 = getelementptr ptr, ptr %t272, i32 0
  %t274 = load ptr, ptr %t273
  %t275 = ptrtoint ptr %t274 to i64
  switch i64 %t275, label %case.default.276 [ i64 3, label %case.arm.3.278 i64 4, label %case.arm.4.286 ]
case.arm.3.278:
  %t280 = getelementptr ptr, ptr %t272, i32 1
  %t281 = load ptr, ptr %t280
  call void @__inc_ref(ptr %t281)
  %t282 = call ptr @__alloc(i64 16, i32 1)
  %t283 = inttoptr i64 3 to ptr
  %t284 = getelementptr ptr, ptr %t282, i32 0
  store ptr %t283, ptr %t284
  call void @__inc_ref(ptr %t281)
  %t285 = getelementptr ptr, ptr %t282, i32 1
  store ptr %t281, ptr %t285
  br label %case.end.3.279
case.end.3.279:
  br label %case.join.277
case.arm.4.286:
  %t288 = getelementptr ptr, ptr %t272, i32 1
  %t289 = load ptr, ptr %t288
  call void @__inc_ref(ptr %t289)
  call void @__inc_ref(ptr %t289)
  call void @__inc_ref(ptr %t199)
  %t290 = call ptr @__concat(ptr %t289, ptr %t199)
  br label %case.end.4.287
case.end.4.287:
  br label %case.join.277
case.default.276:
  unreachable
case.join.277:
  %t291 = phi ptr [ %t282, %case.end.3.279 ], [ %t290, %case.end.4.287 ]
  call void @__free_recursive(ptr %t272)
  br label %case.end.4.269
case.end.4.269:
  br label %case.join.259
case.default.258:
  unreachable
case.join.259:
  %t292 = phi ptr [ %t264, %case.end.3.261 ], [ %t291, %case.end.4.269 ]
  call void @__free_recursive(ptr %t254)
  br label %case.end.4.251
case.end.4.251:
  br label %case.join.241
case.default.240:
  unreachable
case.join.241:
  %t293 = phi ptr [ %t246, %case.end.3.243 ], [ %t292, %case.end.4.251 ]
  call void @__free_recursive(ptr %t236)
  br label %case.end.4.233
case.end.4.233:
  br label %case.join.223
case.default.222:
  unreachable
case.join.223:
  %t294 = phi ptr [ %t228, %case.end.3.225 ], [ %t293, %case.end.4.233 ]
  call void @__free_recursive(ptr %t218)
  br label %case.end.4.215
case.end.4.215:
  br label %case.join.205
case.default.204:
  unreachable
case.join.205:
  %t295 = phi ptr [ %t210, %case.end.3.207 ], [ %t294, %case.end.4.215 ]
  call void @__free_recursive(ptr %t200)
  br label %case.end.4.197
case.end.4.197:
  br label %case.join.187
case.default.186:
  unreachable
case.join.187:
  %t296 = phi ptr [ %t192, %case.end.3.189 ], [ %t295, %case.end.4.197 ]
  call void @__free_recursive(ptr %t182)
  call void @__free_recursive(ptr %t152)
  br label %case.end.4.149
case.end.4.149:
  br label %case.join.139
case.default.138:
  unreachable
case.join.139:
  %t297 = phi ptr [ %t144, %case.end.3.141 ], [ %t296, %case.end.4.149 ]
  call void @__free_recursive(ptr %t134)
  call void @__free_recursive(ptr %t103)
  br label %case.end.4.100
case.end.4.100:
  br label %case.join.90
case.default.89:
  unreachable
case.join.90:
  %t298 = phi ptr [ %t95, %case.end.3.92 ], [ %t297, %case.end.4.100 ]
  call void @__free_recursive(ptr %t85)
  call void @__free_recursive(ptr %t55)
  call void @__free_recursive(ptr %t33)
  store ptr %t298, ptr %v__inl16_scrut.jslot
  br label %join.4
join.case.default.37:
  unreachable
join.4:
  %t299 = load ptr, ptr %v__inl16_scrut.jslot
  %t300 = getelementptr ptr, ptr %t299, i32 0
  %t301 = load ptr, ptr %t300
  %t302 = ptrtoint ptr %t301 to i64
  switch i64 %t302, label %case.default.303 [ i64 3, label %case.arm.3.305 i64 4, label %case.arm.4.319 ]
case.arm.3.305:
  %t307 = call ptr @__alloc(i64 24, i32 2)
  %t308 = inttoptr i64 7 to ptr
  %t309 = getelementptr ptr, ptr %t307, i32 0
  store ptr %t308, ptr %t309
  %t310 = getelementptr ptr, ptr %t307, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t310
  %t311 = call ptr @__alloc(i64 16, i32 1)
  %t312 = inttoptr i64 5 to ptr
  %t313 = getelementptr ptr, ptr %t311, i32 0
  store ptr %t312, ptr %t313
  %t314 = call ptr @__alloc(i64 8, i32 0)
  %t315 = inttoptr i64 0 to ptr
  %t316 = getelementptr ptr, ptr %t314, i32 0
  store ptr %t315, ptr %t316
  %t317 = getelementptr ptr, ptr %t311, i32 1
  store ptr %t314, ptr %t317
  %t318 = getelementptr ptr, ptr %t307, i32 2
  store ptr %t311, ptr %t318
  br label %case.end.3.306
case.end.3.306:
  br label %case.join.304
case.arm.4.319:
  %t321 = call ptr @__alloc(i64 24, i32 2)
  %t322 = inttoptr i64 7 to ptr
  %t323 = getelementptr ptr, ptr %t321, i32 0
  store ptr %t322, ptr %t323
  %t324 = getelementptr ptr, ptr %t299, i32 1
  %t325 = load ptr, ptr %t324
  call void @__inc_ref(ptr %t325)
  %t326 = getelementptr ptr, ptr %t321, i32 1
  store ptr %t325, ptr %t326
  %t327 = call ptr @__alloc(i64 16, i32 1)
  %t328 = inttoptr i64 5 to ptr
  %t329 = getelementptr ptr, ptr %t327, i32 0
  store ptr %t328, ptr %t329
  %t330 = call ptr @__alloc(i64 8, i32 0)
  %t331 = inttoptr i64 0 to ptr
  %t332 = getelementptr ptr, ptr %t330, i32 0
  store ptr %t331, ptr %t332
  %t333 = getelementptr ptr, ptr %t327, i32 1
  store ptr %t330, ptr %t333
  %t334 = getelementptr ptr, ptr %t321, i32 2
  store ptr %t327, ptr %t334
  br label %case.end.4.320
case.end.4.320:
  br label %case.join.304
case.default.303:
  unreachable
case.join.304:
  %t335 = phi ptr [ %t307, %case.end.3.306 ], [ %t321, %case.end.4.320 ]
  call void @__free_recursive(ptr %t299)
  br label %join.end.336
join.end.336:
  br label %join.after.5
join.after.5:
  %t337 = phi ptr [ %t39, %join.val.51 ], [ %t335, %join.end.336 ]
  call void @__free_recursive(ptr %t0)
  ret ptr %t337
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
