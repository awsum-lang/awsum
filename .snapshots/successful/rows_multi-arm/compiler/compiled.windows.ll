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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"Unit" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [7 x i8]} { i32 0, i32 0, i32 0, i32 7, i32 7, [7 x i8] c"Nothing" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [9 x i8]} { i32 0, i32 0, i32 0, i32 9, i32 9, [9 x i8] c"Just True" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [10 x i8]} { i32 0, i32 0, i32 0, i32 10, i32 10, [10 x i8] c"Just False" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"Just " }
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
  %stl_tag = inttoptr i64 18 to ptr
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
  %result = phi ptr [%left, %too_long], [%right, %ok]
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


define internal ptr @v_showUnit(ptr %v__wild0) {
  call void @__free_recursive(ptr %v__wild0)
  ret ptr getelementptr inbounds (i8, ptr @.str.0, i64 12)
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

define internal ptr @v_whatsInside(ptr %v_x) {
  %t0 = getelementptr ptr, ptr %v_x, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 10, label %case.arm.10.4 i64 11, label %case.arm.11.9 ]
case.arm.10.4:
  %t5 = call ptr @__alloc(i64 16, i32 1)
  %t6 = inttoptr i64 4 to ptr
  %t7 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t6, ptr %t7
  %t8 = getelementptr ptr, ptr %t5, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t8
  call void @__free_recursive(ptr %v_x)
  ret ptr %t5
case.arm.11.9:
  %t10 = getelementptr ptr, ptr %v_x, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  %t12 = getelementptr ptr, ptr %t11, i32 0
  %t13 = load ptr, ptr %t12
  %t14 = ptrtoint ptr %t13 to i64
  switch i64 %t14, label %case.default.15 [ i64 796142685, label %case.arm.796142685.16 i64 1759602215, label %case.arm.1759602215.33 ]
case.arm.796142685.16:
  %t17 = getelementptr ptr, ptr %t11, i32 1
  %t18 = load ptr, ptr %t17
  call void @__inc_ref(ptr %t18)
  %t19 = getelementptr ptr, ptr %t18, i32 0
  %t20 = load ptr, ptr %t19
  %t21 = ptrtoint ptr %t20 to i64
  switch i64 %t21, label %case.default.22 [ i64 1, label %case.arm.1.23 i64 2, label %case.arm.2.28 ]
case.arm.1.23:
  %t24 = call ptr @__alloc(i64 16, i32 1)
  %t25 = inttoptr i64 4 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = getelementptr ptr, ptr %t24, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t27
  call void @__free_recursive(ptr %t18)
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t24
case.arm.2.28:
  %t29 = call ptr @__alloc(i64 16, i32 1)
  %t30 = inttoptr i64 4 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = getelementptr ptr, ptr %t29, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t32
  call void @__free_recursive(ptr %t18)
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t29
case.default.22:
  unreachable
case.arm.1759602215.33:
  %t34 = getelementptr ptr, ptr %t11, i32 1
  %t35 = load ptr, ptr %t34
  call void @__inc_ref(ptr %t35)
  call void @__inc_ref(ptr %t35)
  %t36 = call ptr @v_showUnit(ptr %t35)
  %t37 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t36)
  call void @__free_recursive(ptr %t35)
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t37
case.default.15:
  unreachable
case.default.3:
  unreachable
}

define internal ptr @v_summary() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 11 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 8, i32 0)
  %t4 = inttoptr i64 1 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  %t7 = call ptr @v__lift_15(ptr %t0)
  %t8 = call ptr @v_whatsInside(ptr %t7)
  %t9 = getelementptr ptr, ptr %t8, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %case.default.12 [ i64 3, label %case.arm.3.14 i64 4, label %case.arm.4.22 ]
case.arm.3.14:
  %t16 = getelementptr ptr, ptr %t8, i32 1
  %t17 = load ptr, ptr %t16
  call void @__inc_ref(ptr %t17)
  %t18 = call ptr @__alloc(i64 16, i32 1)
  %t19 = inttoptr i64 3 to ptr
  %t20 = getelementptr ptr, ptr %t18, i32 0
  store ptr %t19, ptr %t20
  call void @__inc_ref(ptr %t17)
  %t21 = getelementptr ptr, ptr %t18, i32 1
  store ptr %t17, ptr %t21
  br label %case.end.3.15
case.end.3.15:
  br label %case.join.13
case.arm.4.22:
  %t24 = getelementptr ptr, ptr %t8, i32 1
  %t25 = load ptr, ptr %t24
  call void @__inc_ref(ptr %t25)
  %t26 = call ptr @__alloc(i64 16, i32 1)
  %t27 = inttoptr i64 11 to ptr
  %t28 = getelementptr ptr, ptr %t26, i32 0
  store ptr %t27, ptr %t28
  %t29 = call ptr @__alloc(i64 8, i32 0)
  %t30 = inttoptr i64 0 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = getelementptr ptr, ptr %t26, i32 1
  store ptr %t29, ptr %t32
  %t33 = call ptr @v__lift_16(ptr %t26)
  %t34 = call ptr @v_whatsInside(ptr %t33)
  %t35 = getelementptr ptr, ptr %t34, i32 0
  %t36 = load ptr, ptr %t35
  %t37 = ptrtoint ptr %t36 to i64
  switch i64 %t37, label %case.default.38 [ i64 3, label %case.arm.3.40 i64 4, label %case.arm.4.48 ]
case.arm.3.40:
  %t42 = getelementptr ptr, ptr %t34, i32 1
  %t43 = load ptr, ptr %t42
  call void @__inc_ref(ptr %t43)
  %t44 = call ptr @__alloc(i64 16, i32 1)
  %t45 = inttoptr i64 3 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  call void @__inc_ref(ptr %t43)
  %t47 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t43, ptr %t47
  br label %case.end.3.41
case.end.3.41:
  br label %case.join.39
case.arm.4.48:
  %t50 = getelementptr ptr, ptr %t34, i32 1
  %t51 = load ptr, ptr %t50
  call void @__inc_ref(ptr %t51)
  %t52 = call ptr @__alloc(i64 8, i32 0)
  %t53 = inttoptr i64 10 to ptr
  %t54 = getelementptr ptr, ptr %t52, i32 0
  store ptr %t53, ptr %t54
  %t55 = call ptr @v__lift_17(ptr %t52)
  %t56 = call ptr @v_whatsInside(ptr %t55)
  %t57 = getelementptr ptr, ptr %t56, i32 0
  %t58 = load ptr, ptr %t57
  %t59 = ptrtoint ptr %t58 to i64
  switch i64 %t59, label %case.default.60 [ i64 3, label %case.arm.3.62 i64 4, label %case.arm.4.70 ]
case.arm.3.62:
  %t64 = getelementptr ptr, ptr %t56, i32 1
  %t65 = load ptr, ptr %t64
  call void @__inc_ref(ptr %t65)
  %t66 = call ptr @__alloc(i64 16, i32 1)
  %t67 = inttoptr i64 3 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t65)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t65, ptr %t69
  br label %case.end.3.63
case.end.3.63:
  br label %case.join.61
case.arm.4.70:
  %t72 = getelementptr ptr, ptr %t56, i32 1
  %t73 = load ptr, ptr %t72
  call void @__inc_ref(ptr %t73)
  call void @__inc_ref(ptr %t25)
  %t74 = call ptr @__concat(ptr %t25, ptr getelementptr inbounds (i8, ptr @.str.5, i64 12))
  %t75 = getelementptr ptr, ptr %t74, i32 0
  %t76 = load ptr, ptr %t75
  %t77 = ptrtoint ptr %t76 to i64
  switch i64 %t77, label %case.default.78 [ i64 3, label %case.arm.3.80 i64 4, label %case.arm.4.88 ]
case.arm.3.80:
  %t82 = getelementptr ptr, ptr %t74, i32 1
  %t83 = load ptr, ptr %t82
  call void @__inc_ref(ptr %t83)
  %t84 = call ptr @__alloc(i64 16, i32 1)
  %t85 = inttoptr i64 3 to ptr
  %t86 = getelementptr ptr, ptr %t84, i32 0
  store ptr %t85, ptr %t86
  call void @__inc_ref(ptr %t83)
  %t87 = getelementptr ptr, ptr %t84, i32 1
  store ptr %t83, ptr %t87
  br label %case.end.3.81
case.end.3.81:
  br label %case.join.79
case.arm.4.88:
  %t90 = getelementptr ptr, ptr %t74, i32 1
  %t91 = load ptr, ptr %t90
  call void @__inc_ref(ptr %t91)
  call void @__inc_ref(ptr %t91)
  call void @__inc_ref(ptr %t51)
  %t92 = call ptr @__concat(ptr %t91, ptr %t51)
  %t93 = getelementptr ptr, ptr %t92, i32 0
  %t94 = load ptr, ptr %t93
  %t95 = ptrtoint ptr %t94 to i64
  switch i64 %t95, label %case.default.96 [ i64 3, label %case.arm.3.98 i64 4, label %case.arm.4.106 ]
case.arm.3.98:
  %t100 = getelementptr ptr, ptr %t92, i32 1
  %t101 = load ptr, ptr %t100
  call void @__inc_ref(ptr %t101)
  %t102 = call ptr @__alloc(i64 16, i32 1)
  %t103 = inttoptr i64 3 to ptr
  %t104 = getelementptr ptr, ptr %t102, i32 0
  store ptr %t103, ptr %t104
  call void @__inc_ref(ptr %t101)
  %t105 = getelementptr ptr, ptr %t102, i32 1
  store ptr %t101, ptr %t105
  br label %case.end.3.99
case.end.3.99:
  br label %case.join.97
case.arm.4.106:
  %t108 = getelementptr ptr, ptr %t92, i32 1
  %t109 = load ptr, ptr %t108
  call void @__inc_ref(ptr %t109)
  call void @__inc_ref(ptr %t109)
  %t110 = call ptr @__concat(ptr %t109, ptr getelementptr inbounds (i8, ptr @.str.5, i64 12))
  %t111 = getelementptr ptr, ptr %t110, i32 0
  %t112 = load ptr, ptr %t111
  %t113 = ptrtoint ptr %t112 to i64
  switch i64 %t113, label %case.default.114 [ i64 3, label %case.arm.3.116 i64 4, label %case.arm.4.124 ]
case.arm.3.116:
  %t118 = getelementptr ptr, ptr %t110, i32 1
  %t119 = load ptr, ptr %t118
  call void @__inc_ref(ptr %t119)
  %t120 = call ptr @__alloc(i64 16, i32 1)
  %t121 = inttoptr i64 3 to ptr
  %t122 = getelementptr ptr, ptr %t120, i32 0
  store ptr %t121, ptr %t122
  call void @__inc_ref(ptr %t119)
  %t123 = getelementptr ptr, ptr %t120, i32 1
  store ptr %t119, ptr %t123
  br label %case.end.3.117
case.end.3.117:
  br label %case.join.115
case.arm.4.124:
  %t126 = getelementptr ptr, ptr %t110, i32 1
  %t127 = load ptr, ptr %t126
  call void @__inc_ref(ptr %t127)
  call void @__inc_ref(ptr %t127)
  call void @__inc_ref(ptr %t73)
  %t128 = call ptr @__concat(ptr %t127, ptr %t73)
  br label %case.end.4.125
case.end.4.125:
  br label %case.join.115
case.default.114:
  unreachable
case.join.115:
  %t129 = phi ptr [%t120, %case.end.3.117], [%t128, %case.end.4.125]
  call void @__free_recursive(ptr %t110)
  br label %case.end.4.107
case.end.4.107:
  br label %case.join.97
case.default.96:
  unreachable
case.join.97:
  %t130 = phi ptr [%t102, %case.end.3.99], [%t129, %case.end.4.107]
  call void @__free_recursive(ptr %t92)
  br label %case.end.4.89
case.end.4.89:
  br label %case.join.79
case.default.78:
  unreachable
case.join.79:
  %t131 = phi ptr [%t84, %case.end.3.81], [%t130, %case.end.4.89]
  call void @__free_recursive(ptr %t74)
  br label %case.end.4.71
case.end.4.71:
  br label %case.join.61
case.default.60:
  unreachable
case.join.61:
  %t132 = phi ptr [%t66, %case.end.3.63], [%t131, %case.end.4.71]
  call void @__free_recursive(ptr %t56)
  br label %case.end.4.49
case.end.4.49:
  br label %case.join.39
case.default.38:
  unreachable
case.join.39:
  %t133 = phi ptr [%t44, %case.end.3.41], [%t132, %case.end.4.49]
  call void @__free_recursive(ptr %t34)
  br label %case.end.4.23
case.end.4.23:
  br label %case.join.13
case.default.12:
  unreachable
case.join.13:
  %t134 = phi ptr [%t18, %case.end.3.15], [%t133, %case.end.4.23]
  call void @__free_recursive(ptr %t8)
  ret ptr %t134
}

define internal ptr @v_main() {
  %t0 = call ptr @v_summary()
  %t1 = call ptr @v__let_18(ptr %t0)
  ret ptr %t1
}

define internal ptr @v__lift_15(ptr %v___input) {
  %t0 = getelementptr ptr, ptr %v___input, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 10, label %case.arm.10.4 i64 11, label %case.arm.11.8 ]
case.arm.10.4:
  %t5 = call ptr @__alloc(i64 8, i32 0)
  %t6 = inttoptr i64 10 to ptr
  %t7 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t6, ptr %t7
  call void @__free_recursive(ptr %v___input)
  ret ptr %t5
case.arm.11.8:
  %t9 = getelementptr ptr, ptr %v___input, i32 1
  %t10 = load ptr, ptr %t9
  call void @__inc_ref(ptr %t10)
  %t11 = call ptr @__alloc(i64 16, i32 1)
  %t12 = inttoptr i64 11 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  %t14 = call ptr @__alloc(i64 16, i32 1)
  %t15 = inttoptr i64 796142685 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  call void @__inc_ref(ptr %t10)
  %t17 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t10, ptr %t17
  %t18 = getelementptr ptr, ptr %t11, i32 1
  store ptr %t14, ptr %t18
  call void @__free_recursive(ptr %t10)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t11
case.default.3:
  unreachable
}

define internal ptr @v__lift_16(ptr %v___input) {
  %t0 = getelementptr ptr, ptr %v___input, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 10, label %case.arm.10.4 i64 11, label %case.arm.11.8 ]
case.arm.10.4:
  %t5 = call ptr @__alloc(i64 8, i32 0)
  %t6 = inttoptr i64 10 to ptr
  %t7 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t6, ptr %t7
  call void @__free_recursive(ptr %v___input)
  ret ptr %t5
case.arm.11.8:
  %t9 = getelementptr ptr, ptr %v___input, i32 1
  %t10 = load ptr, ptr %t9
  call void @__inc_ref(ptr %t10)
  %t11 = call ptr @__alloc(i64 16, i32 1)
  %t12 = inttoptr i64 11 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  %t14 = call ptr @__alloc(i64 16, i32 1)
  %t15 = inttoptr i64 1759602215 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  call void @__inc_ref(ptr %t10)
  %t17 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t10, ptr %t17
  %t18 = getelementptr ptr, ptr %t11, i32 1
  store ptr %t14, ptr %t18
  call void @__free_recursive(ptr %t10)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t11
case.default.3:
  unreachable
}

define internal ptr @v__lift_17(ptr %v___input) {
  %t0 = getelementptr ptr, ptr %v___input, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 10, label %case.arm.10.4 i64 11, label %case.arm.11.8 ]
case.arm.10.4:
  %t5 = call ptr @__alloc(i64 8, i32 0)
  %t6 = inttoptr i64 10 to ptr
  %t7 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t6, ptr %t7
  call void @__free_recursive(ptr %v___input)
  ret ptr %t5
case.arm.11.8:
  %t9 = getelementptr ptr, ptr %v___input, i32 1
  %t10 = load ptr, ptr %t9
  call void @__inc_ref(ptr %t10)
  %t11 = call ptr @__alloc(i64 16, i32 1)
  %t12 = inttoptr i64 11 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  call void @__inc_ref(ptr %t10)
  %t14 = getelementptr ptr, ptr %t11, i32 1
  store ptr %t10, ptr %t14
  call void @__free_recursive(ptr %t10)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t11
case.default.3:
  unreachable
}

define internal ptr @v__let_18(ptr %v_res) {
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
  store ptr getelementptr inbounds (i8, ptr @.str.6, i64 12), ptr %t10
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
