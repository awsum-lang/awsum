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
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }

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
  %t15 = getelementptr ptr, ptr %t4, i32 2
  %t16 = load ptr, ptr %t15
  call void @__inc_ref(ptr %t16)
  call void @__inc_ref(ptr %t14)
  %t17 = call ptr @__print(ptr %t14)
  %t18 = getelementptr ptr, ptr %t17, i32 0
  %t19 = load ptr, ptr %t18
  %t20 = ptrtoint ptr %t19 to i64
  switch i64 %t20, label %tco.case.default.21 [ i64 0, label %tco.case.arm.0.22 ]
tco.case.arm.0.22:
  call void @__inc_ref(ptr %t16)
  call void @__free_recursive(ptr %t17)
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t16)
  call void @__free_recursive(ptr %t14)
  store ptr %t16, ptr %t3
  br label %tco.loop.0
tco.case.default.21:
  unreachable
tco.case.default.8:
  unreachable
tco.exit.1:
  %t23 = load ptr, ptr %t2
  ret ptr %t23
}

define internal ptr @v_unwrap(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 24, label %case.arm.24.4 i64 25, label %case.arm.25.17 ]
case.arm.24.4:
  %t5 = getelementptr ptr, ptr %v_r, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = getelementptr ptr, ptr %t6, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %case.default.10 [ i64 24, label %case.arm.24.11 i64 25, label %case.arm.25.14 ]
case.arm.24.11:
  %t12 = getelementptr ptr, ptr %t6, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_r)
  ret ptr %t13
case.arm.25.14:
  %t15 = getelementptr ptr, ptr %t6, i32 1
  %t16 = load ptr, ptr %t15
  call void @__inc_ref(ptr %t16)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_r)
  ret ptr %t16
case.default.10:
  unreachable
case.arm.25.17:
  %t18 = getelementptr ptr, ptr %v_r, i32 1
  %t19 = load ptr, ptr %t18
  call void @__inc_ref(ptr %t19)
  %t20 = getelementptr ptr, ptr %t19, i32 0
  %t21 = load ptr, ptr %t20
  %t22 = ptrtoint ptr %t21 to i64
  switch i64 %t22, label %case.default.23 [ i64 24, label %case.arm.24.24 i64 25, label %case.arm.25.27 ]
case.arm.24.24:
  %t25 = getelementptr ptr, ptr %t19, i32 1
  %t26 = load ptr, ptr %t25
  call void @__inc_ref(ptr %t26)
  call void @__free_recursive(ptr %t19)
  call void @__free_recursive(ptr %v_r)
  ret ptr %t26
case.arm.25.27:
  %t28 = getelementptr ptr, ptr %t19, i32 1
  %t29 = load ptr, ptr %t28
  call void @__inc_ref(ptr %t29)
  call void @__free_recursive(ptr %t19)
  call void @__free_recursive(ptr %v_r)
  ret ptr %t29
case.default.23:
  unreachable
case.default.3:
  unreachable
}

define internal ptr @v_main() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 24 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 16, i32 1)
  %t4 = inttoptr i64 24 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t3, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t6
  %t7 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t7
  %t8 = call ptr @v_unwrap(ptr %t0)
  %t9 = call ptr @__concat(ptr %t8, ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  %t10 = getelementptr ptr, ptr %t9, i32 0
  %t11 = load ptr, ptr %t10
  %t12 = ptrtoint ptr %t11 to i64
  switch i64 %t12, label %case.default.13 [ i64 3, label %case.arm.3.15 i64 4, label %case.arm.4.23 ]
case.arm.3.15:
  %t17 = getelementptr ptr, ptr %t9, i32 1
  %t18 = load ptr, ptr %t17
  call void @__inc_ref(ptr %t18)
  %t19 = call ptr @__alloc(i64 16, i32 1)
  %t20 = inttoptr i64 3 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  call void @__inc_ref(ptr %t18)
  %t22 = getelementptr ptr, ptr %t19, i32 1
  store ptr %t18, ptr %t22
  br label %case.end.3.16
case.end.3.16:
  br label %case.join.14
case.arm.4.23:
  %t25 = getelementptr ptr, ptr %t9, i32 1
  %t26 = load ptr, ptr %t25
  call void @__inc_ref(ptr %t26)
  call void @__inc_ref(ptr %t26)
  %t27 = call ptr @__alloc(i64 16, i32 1)
  %t28 = inttoptr i64 24 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  %t30 = call ptr @__alloc(i64 16, i32 1)
  %t31 = inttoptr i64 25 to ptr
  %t32 = getelementptr ptr, ptr %t30, i32 0
  store ptr %t31, ptr %t32
  %t33 = getelementptr ptr, ptr %t30, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t33
  %t34 = getelementptr ptr, ptr %t27, i32 1
  store ptr %t30, ptr %t34
  %t35 = call ptr @v_unwrap(ptr %t27)
  %t36 = call ptr @__concat(ptr %t26, ptr %t35)
  %t37 = getelementptr ptr, ptr %t36, i32 0
  %t38 = load ptr, ptr %t37
  %t39 = ptrtoint ptr %t38 to i64
  switch i64 %t39, label %case.default.40 [ i64 3, label %case.arm.3.42 i64 4, label %case.arm.4.50 ]
case.arm.3.42:
  %t44 = getelementptr ptr, ptr %t36, i32 1
  %t45 = load ptr, ptr %t44
  call void @__inc_ref(ptr %t45)
  %t46 = call ptr @__alloc(i64 16, i32 1)
  %t47 = inttoptr i64 3 to ptr
  %t48 = getelementptr ptr, ptr %t46, i32 0
  store ptr %t47, ptr %t48
  call void @__inc_ref(ptr %t45)
  %t49 = getelementptr ptr, ptr %t46, i32 1
  store ptr %t45, ptr %t49
  br label %case.end.3.43
case.end.3.43:
  br label %case.join.41
case.arm.4.50:
  %t52 = getelementptr ptr, ptr %t36, i32 1
  %t53 = load ptr, ptr %t52
  call void @__inc_ref(ptr %t53)
  call void @__inc_ref(ptr %t53)
  %t54 = call ptr @__concat(ptr %t53, ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  %t55 = getelementptr ptr, ptr %t54, i32 0
  %t56 = load ptr, ptr %t55
  %t57 = ptrtoint ptr %t56 to i64
  switch i64 %t57, label %case.default.58 [ i64 3, label %case.arm.3.60 i64 4, label %case.arm.4.68 ]
case.arm.3.60:
  %t62 = getelementptr ptr, ptr %t54, i32 1
  %t63 = load ptr, ptr %t62
  call void @__inc_ref(ptr %t63)
  %t64 = call ptr @__alloc(i64 16, i32 1)
  %t65 = inttoptr i64 3 to ptr
  %t66 = getelementptr ptr, ptr %t64, i32 0
  store ptr %t65, ptr %t66
  call void @__inc_ref(ptr %t63)
  %t67 = getelementptr ptr, ptr %t64, i32 1
  store ptr %t63, ptr %t67
  br label %case.end.3.61
case.end.3.61:
  br label %case.join.59
case.arm.4.68:
  %t70 = getelementptr ptr, ptr %t54, i32 1
  %t71 = load ptr, ptr %t70
  call void @__inc_ref(ptr %t71)
  call void @__inc_ref(ptr %t71)
  %t72 = call ptr @__alloc(i64 16, i32 1)
  %t73 = inttoptr i64 25 to ptr
  %t74 = getelementptr ptr, ptr %t72, i32 0
  store ptr %t73, ptr %t74
  %t75 = call ptr @__alloc(i64 16, i32 1)
  %t76 = inttoptr i64 24 to ptr
  %t77 = getelementptr ptr, ptr %t75, i32 0
  store ptr %t76, ptr %t77
  %t78 = getelementptr ptr, ptr %t75, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t78
  %t79 = getelementptr ptr, ptr %t72, i32 1
  store ptr %t75, ptr %t79
  %t80 = call ptr @v_unwrap(ptr %t72)
  %t81 = call ptr @__concat(ptr %t71, ptr %t80)
  %t82 = getelementptr ptr, ptr %t81, i32 0
  %t83 = load ptr, ptr %t82
  %t84 = ptrtoint ptr %t83 to i64
  switch i64 %t84, label %case.default.85 [ i64 3, label %case.arm.3.87 i64 4, label %case.arm.4.95 ]
case.arm.3.87:
  %t89 = getelementptr ptr, ptr %t81, i32 1
  %t90 = load ptr, ptr %t89
  call void @__inc_ref(ptr %t90)
  %t91 = call ptr @__alloc(i64 16, i32 1)
  %t92 = inttoptr i64 3 to ptr
  %t93 = getelementptr ptr, ptr %t91, i32 0
  store ptr %t92, ptr %t93
  call void @__inc_ref(ptr %t90)
  %t94 = getelementptr ptr, ptr %t91, i32 1
  store ptr %t90, ptr %t94
  br label %case.end.3.88
case.end.3.88:
  br label %case.join.86
case.arm.4.95:
  %t97 = getelementptr ptr, ptr %t81, i32 1
  %t98 = load ptr, ptr %t97
  call void @__inc_ref(ptr %t98)
  call void @__inc_ref(ptr %t98)
  %t99 = call ptr @__concat(ptr %t98, ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  %t100 = getelementptr ptr, ptr %t99, i32 0
  %t101 = load ptr, ptr %t100
  %t102 = ptrtoint ptr %t101 to i64
  switch i64 %t102, label %case.default.103 [ i64 3, label %case.arm.3.105 i64 4, label %case.arm.4.113 ]
case.arm.3.105:
  %t107 = getelementptr ptr, ptr %t99, i32 1
  %t108 = load ptr, ptr %t107
  call void @__inc_ref(ptr %t108)
  %t109 = call ptr @__alloc(i64 16, i32 1)
  %t110 = inttoptr i64 3 to ptr
  %t111 = getelementptr ptr, ptr %t109, i32 0
  store ptr %t110, ptr %t111
  call void @__inc_ref(ptr %t108)
  %t112 = getelementptr ptr, ptr %t109, i32 1
  store ptr %t108, ptr %t112
  br label %case.end.3.106
case.end.3.106:
  br label %case.join.104
case.arm.4.113:
  %t115 = getelementptr ptr, ptr %t99, i32 1
  %t116 = load ptr, ptr %t115
  call void @__inc_ref(ptr %t116)
  call void @__inc_ref(ptr %t116)
  %t117 = call ptr @__alloc(i64 16, i32 1)
  %t118 = inttoptr i64 25 to ptr
  %t119 = getelementptr ptr, ptr %t117, i32 0
  store ptr %t118, ptr %t119
  %t120 = call ptr @__alloc(i64 16, i32 1)
  %t121 = inttoptr i64 25 to ptr
  %t122 = getelementptr ptr, ptr %t120, i32 0
  store ptr %t121, ptr %t122
  %t123 = getelementptr ptr, ptr %t120, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t123
  %t124 = getelementptr ptr, ptr %t117, i32 1
  store ptr %t120, ptr %t124
  %t125 = call ptr @v_unwrap(ptr %t117)
  %t126 = call ptr @__concat(ptr %t116, ptr %t125)
  br label %case.end.4.114
case.end.4.114:
  br label %case.join.104
case.default.103:
  unreachable
case.join.104:
  %t127 = phi ptr [ %t109, %case.end.3.106 ], [ %t126, %case.end.4.114 ]
  call void @__free_recursive(ptr %t99)
  br label %case.end.4.96
case.end.4.96:
  br label %case.join.86
case.default.85:
  unreachable
case.join.86:
  %t128 = phi ptr [ %t91, %case.end.3.88 ], [ %t127, %case.end.4.96 ]
  call void @__free_recursive(ptr %t81)
  br label %case.end.4.69
case.end.4.69:
  br label %case.join.59
case.default.58:
  unreachable
case.join.59:
  %t129 = phi ptr [ %t64, %case.end.3.61 ], [ %t128, %case.end.4.69 ]
  call void @__free_recursive(ptr %t54)
  br label %case.end.4.51
case.end.4.51:
  br label %case.join.41
case.default.40:
  unreachable
case.join.41:
  %t130 = phi ptr [ %t46, %case.end.3.43 ], [ %t129, %case.end.4.51 ]
  call void @__free_recursive(ptr %t36)
  br label %case.end.4.24
case.end.4.24:
  br label %case.join.14
case.default.13:
  unreachable
case.join.14:
  %t131 = phi ptr [ %t19, %case.end.3.16 ], [ %t130, %case.end.4.24 ]
  call void @__free_recursive(ptr %t9)
  %t132 = call ptr @v__let_13(ptr %t131)
  ret ptr %t132
}

define internal ptr @v__let_13(ptr %v_res) {
  %t0 = getelementptr ptr, ptr %v_res, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.19 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v_res, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = call ptr @__alloc(i64 24, i32 2)
  %t8 = inttoptr i64 7 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = getelementptr ptr, ptr %t7, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.5, i64 12), ptr %t10
  %t11 = call ptr @__alloc(i64 16, i32 1)
  %t12 = inttoptr i64 5 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  %t14 = call ptr @__alloc(i64 8, i32 0)
  %t15 = inttoptr i64 0 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  %t17 = getelementptr ptr, ptr %t11, i32 1
  store ptr %t14, ptr %t17
  %t18 = getelementptr ptr, ptr %t7, i32 2
  store ptr %t11, ptr %t18
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_res)
  ret ptr %t7
case.arm.4.19:
  %t20 = getelementptr ptr, ptr %v_res, i32 1
  %t21 = load ptr, ptr %t20
  call void @__inc_ref(ptr %t21)
  %t22 = call ptr @__alloc(i64 24, i32 2)
  %t23 = inttoptr i64 7 to ptr
  %t24 = getelementptr ptr, ptr %t22, i32 0
  store ptr %t23, ptr %t24
  call void @__inc_ref(ptr %t21)
  %t25 = getelementptr ptr, ptr %t22, i32 1
  store ptr %t21, ptr %t25
  %t26 = call ptr @__alloc(i64 16, i32 1)
  %t27 = inttoptr i64 5 to ptr
  %t28 = getelementptr ptr, ptr %t26, i32 0
  store ptr %t27, ptr %t28
  %t29 = call ptr @__alloc(i64 8, i32 0)
  %t30 = inttoptr i64 0 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = getelementptr ptr, ptr %t26, i32 1
  store ptr %t29, ptr %t32
  %t33 = getelementptr ptr, ptr %t22, i32 2
  store ptr %t26, ptr %t33
  call void @__free_recursive(ptr %t21)
  call void @__free_recursive(ptr %v_res)
  ret ptr %t22
case.default.3:
  unreachable
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
