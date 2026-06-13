; External C declarations
declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare ptr @memcpy(ptr, ptr, i64)
declare i64 @write(i32, ptr, i64)
declare i32 @snprintf(ptr, i64, ptr, ...)
declare {i32, i1} @llvm.ssub.with.overflow.i32(i32, i32)

@.fmt_i32 = private unnamed_addr constant [3 x i8] c"%d\00"

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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"err: " }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [13 x i8]} { i32 0, i32 0, i32 0, i32 13, i32 13, [13 x i8] c"OverflowError" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [14 x i8]} { i32 0, i32 0, i32 0, i32 14, i32 14, [14 x i8] c"UnderflowError" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"ok: " }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c", " }

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


define internal ptr @__showInt32(ptr %p) {
  %v = load i32, ptr %p
  %buf = call ptr @__alloc(i64 24, i32 0)
  %payload = getelementptr i8, ptr %buf, i64 8
  %n = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %payload, i64 16, ptr @.fmt_i32, i32 %v)
  store i32 %n, ptr %buf
  %u16p = getelementptr i8, ptr %buf, i64 4
  store i32 %n, ptr %u16p
  call void @__free_recursive(ptr %p)
  ret ptr %buf
}


define internal ptr @__subInt32(ptr %pa, ptr %pb) {
  %a = load i32, ptr %pa
  %b = load i32, ptr %pb
  %res = call {i32, i1} @llvm.ssub.with.overflow.i32(i32 %a, i32 %b)
  %diff = extractvalue {i32, i1} %res, 0
  %ovf = extractvalue {i32, i1} %res, 1
  br i1 %ovf, label %err, label %ok
err:
  %is_pos = icmp sge i32 %a, 0
  %row_tag_idx = select i1 %is_pos, i64 882564211, i64 3768445577
  %inner_tag_idx = select i1 %is_pos, i64 18, i64 17
  %inner = call ptr @__alloc(i64 8, i32 0)
  %inner_tag = inttoptr i64 %inner_tag_idx to ptr
  store ptr %inner_tag, ptr %inner
  %row = call ptr @__alloc(i64 16, i32 1)
  %row_tag = inttoptr i64 %row_tag_idx to ptr
  store ptr %row_tag, ptr %row
  %row_f = getelementptr ptr, ptr %row, i32 1
  store ptr %inner, ptr %row_f
  %left = call ptr @__alloc(i64 16, i32 1)
  %left_tag = inttoptr i64 3 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %row, ptr %left_f
  br label %join
ok:
  %box = call ptr @__alloc(i64 4, i32 0)
  store i32 %diff, ptr %box
  %right = call ptr @__alloc(i64 16, i32 1)
  %right_tag = inttoptr i64 4 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %box, ptr %right_f
  br label %join
join:
  %result = phi ptr [ %left, %err ], [ %right, %ok ]
  call void @__free_recursive(ptr %pa)
  call void @__free_recursive(ptr %pb)
  ret ptr %result
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

define internal ptr @v_minInt32() {
  %t0 = call ptr @__alloc(i64 4, i32 0)
  store i32 -2147483648, ptr %t0
  ret ptr %t0
}

define internal ptr @v_maxInt32() {
  %t0 = call ptr @__alloc(i64 4, i32 0)
  store i32 2147483647, ptr %t0
  ret ptr %t0
}

define internal ptr @v_render(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.15 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v_r, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = getelementptr ptr, ptr %t6, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %case.default.10 [ i64 882564211, label %case.arm.882564211.11 i64 3768445577, label %case.arm.3768445577.13 ]
case.arm.882564211.11:
  %t12 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_r)
  ret ptr %t12
case.arm.3768445577.13:
  %t14 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_r)
  ret ptr %t14
case.default.10:
  unreachable
case.arm.4.15:
  %t16 = getelementptr ptr, ptr %v_r, i32 1
  %t17 = load ptr, ptr %t16
  call void @__inc_ref(ptr %t17)
  %t18 = call ptr @__showInt32(ptr %t17)
  %t19 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t18)
  call void @__free_recursive(ptr %v_r)
  ret ptr %t19
case.default.3:
  unreachable
}

define internal ptr @v_main() {
  %v__inl4_scrut.jslot = alloca ptr
  %t2 = call ptr @__alloc(i64 16, i32 1)
  %t3 = inttoptr i64 4 to ptr
  %t4 = getelementptr ptr, ptr %t2, i32 0
  store ptr %t3, ptr %t4
  %t5 = call ptr @__alloc(i64 4, i32 0)
  store i32 77, ptr %t5
  %t6 = getelementptr ptr, ptr %t2, i32 1
  store ptr %t5, ptr %t6
  %t7 = call ptr @v_render(ptr %t2)
  %t8 = getelementptr ptr, ptr %t7, i32 0
  %t9 = load ptr, ptr %t8
  %t10 = ptrtoint ptr %t9 to i64
  switch i64 %t10, label %join.case.default.11 [ i64 3, label %join.case.arm.3.12 i64 4, label %join.case.arm.4.26 ]
join.case.arm.3.12:
  %t13 = call ptr @__alloc(i64 24, i32 2)
  %t14 = inttoptr i64 7 to ptr
  %t15 = getelementptr ptr, ptr %t13, i32 0
  store ptr %t14, ptr %t15
  %t16 = getelementptr ptr, ptr %t13, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t16
  %t17 = call ptr @__alloc(i64 16, i32 1)
  %t18 = inttoptr i64 5 to ptr
  %t19 = getelementptr ptr, ptr %t17, i32 0
  store ptr %t18, ptr %t19
  %t20 = call ptr @__alloc(i64 8, i32 0)
  %t21 = inttoptr i64 0 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = getelementptr ptr, ptr %t17, i32 1
  store ptr %t20, ptr %t23
  %t24 = getelementptr ptr, ptr %t13, i32 2
  store ptr %t17, ptr %t24
  call void @__free_recursive(ptr %t7)
  br label %join.val.25
join.val.25:
  br label %join.after.1
join.case.arm.4.26:
  %t27 = getelementptr ptr, ptr %t7, i32 1
  %t28 = load ptr, ptr %t27
  call void @__inc_ref(ptr %t28)
  %t29 = call ptr @__alloc(i64 16, i32 1)
  %t30 = inttoptr i64 4 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = call ptr @__alloc(i64 4, i32 0)
  store i32 150, ptr %t32
  %t33 = getelementptr ptr, ptr %t29, i32 1
  store ptr %t32, ptr %t33
  %t34 = call ptr @v_render(ptr %t29)
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
  %t52 = call ptr @v_maxInt32()
  %t53 = call ptr @__alloc(i64 4, i32 0)
  store i32 -1, ptr %t53
  %t54 = call ptr @__subInt32(ptr %t52, ptr %t53)
  %t55 = call ptr @v_render(ptr %t54)
  %t56 = getelementptr ptr, ptr %t55, i32 0
  %t57 = load ptr, ptr %t56
  %t58 = ptrtoint ptr %t57 to i64
  switch i64 %t58, label %case.default.59 [ i64 3, label %case.arm.3.61 i64 4, label %case.arm.4.69 ]
case.arm.3.61:
  %t63 = getelementptr ptr, ptr %t55, i32 1
  %t64 = load ptr, ptr %t63
  call void @__inc_ref(ptr %t64)
  %t65 = call ptr @__alloc(i64 16, i32 1)
  %t66 = inttoptr i64 3 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  call void @__inc_ref(ptr %t64)
  %t68 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t64, ptr %t68
  br label %case.end.3.62
case.end.3.62:
  br label %case.join.60
case.arm.4.69:
  %t71 = getelementptr ptr, ptr %t55, i32 1
  %t72 = load ptr, ptr %t71
  call void @__inc_ref(ptr %t72)
  %t73 = call ptr @v_minInt32()
  %t74 = call ptr @__alloc(i64 4, i32 0)
  store i32 1, ptr %t74
  %t75 = call ptr @__subInt32(ptr %t73, ptr %t74)
  %t76 = call ptr @v_render(ptr %t75)
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
  %t94 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t94
  %t95 = call ptr @v_minInt32()
  %t96 = call ptr @__subInt32(ptr %t94, ptr %t95)
  %t97 = call ptr @v_render(ptr %t96)
  %t98 = getelementptr ptr, ptr %t97, i32 0
  %t99 = load ptr, ptr %t98
  %t100 = ptrtoint ptr %t99 to i64
  switch i64 %t100, label %case.default.101 [ i64 3, label %case.arm.3.103 i64 4, label %case.arm.4.111 ]
case.arm.3.103:
  %t105 = getelementptr ptr, ptr %t97, i32 1
  %t106 = load ptr, ptr %t105
  call void @__inc_ref(ptr %t106)
  %t107 = call ptr @__alloc(i64 16, i32 1)
  %t108 = inttoptr i64 3 to ptr
  %t109 = getelementptr ptr, ptr %t107, i32 0
  store ptr %t108, ptr %t109
  call void @__inc_ref(ptr %t106)
  %t110 = getelementptr ptr, ptr %t107, i32 1
  store ptr %t106, ptr %t110
  br label %case.end.3.104
case.end.3.104:
  br label %case.join.102
case.arm.4.111:
  %t113 = getelementptr ptr, ptr %t97, i32 1
  %t114 = load ptr, ptr %t113
  call void @__inc_ref(ptr %t114)
  call void @__inc_ref(ptr %t28)
  %t115 = call ptr @__concat(ptr %t28, ptr getelementptr inbounds (i8, ptr @.str.5, i64 12))
  %t116 = getelementptr ptr, ptr %t115, i32 0
  %t117 = load ptr, ptr %t116
  %t118 = ptrtoint ptr %t117 to i64
  switch i64 %t118, label %case.default.119 [ i64 3, label %case.arm.3.121 i64 4, label %case.arm.4.129 ]
case.arm.3.121:
  %t123 = getelementptr ptr, ptr %t115, i32 1
  %t124 = load ptr, ptr %t123
  call void @__inc_ref(ptr %t124)
  %t125 = call ptr @__alloc(i64 16, i32 1)
  %t126 = inttoptr i64 3 to ptr
  %t127 = getelementptr ptr, ptr %t125, i32 0
  store ptr %t126, ptr %t127
  call void @__inc_ref(ptr %t124)
  %t128 = getelementptr ptr, ptr %t125, i32 1
  store ptr %t124, ptr %t128
  br label %case.end.3.122
case.end.3.122:
  br label %case.join.120
case.arm.4.129:
  %t131 = getelementptr ptr, ptr %t115, i32 1
  %t132 = load ptr, ptr %t131
  call void @__inc_ref(ptr %t132)
  call void @__inc_ref(ptr %t132)
  call void @__inc_ref(ptr %t51)
  %t133 = call ptr @__concat(ptr %t132, ptr %t51)
  %t134 = getelementptr ptr, ptr %t133, i32 0
  %t135 = load ptr, ptr %t134
  %t136 = ptrtoint ptr %t135 to i64
  switch i64 %t136, label %case.default.137 [ i64 3, label %case.arm.3.139 i64 4, label %case.arm.4.147 ]
case.arm.3.139:
  %t141 = getelementptr ptr, ptr %t133, i32 1
  %t142 = load ptr, ptr %t141
  call void @__inc_ref(ptr %t142)
  %t143 = call ptr @__alloc(i64 16, i32 1)
  %t144 = inttoptr i64 3 to ptr
  %t145 = getelementptr ptr, ptr %t143, i32 0
  store ptr %t144, ptr %t145
  call void @__inc_ref(ptr %t142)
  %t146 = getelementptr ptr, ptr %t143, i32 1
  store ptr %t142, ptr %t146
  br label %case.end.3.140
case.end.3.140:
  br label %case.join.138
case.arm.4.147:
  %t149 = getelementptr ptr, ptr %t133, i32 1
  %t150 = load ptr, ptr %t149
  call void @__inc_ref(ptr %t150)
  call void @__inc_ref(ptr %t150)
  %t151 = call ptr @__concat(ptr %t150, ptr getelementptr inbounds (i8, ptr @.str.5, i64 12))
  %t152 = getelementptr ptr, ptr %t151, i32 0
  %t153 = load ptr, ptr %t152
  %t154 = ptrtoint ptr %t153 to i64
  switch i64 %t154, label %case.default.155 [ i64 3, label %case.arm.3.157 i64 4, label %case.arm.4.165 ]
case.arm.3.157:
  %t159 = getelementptr ptr, ptr %t151, i32 1
  %t160 = load ptr, ptr %t159
  call void @__inc_ref(ptr %t160)
  %t161 = call ptr @__alloc(i64 16, i32 1)
  %t162 = inttoptr i64 3 to ptr
  %t163 = getelementptr ptr, ptr %t161, i32 0
  store ptr %t162, ptr %t163
  call void @__inc_ref(ptr %t160)
  %t164 = getelementptr ptr, ptr %t161, i32 1
  store ptr %t160, ptr %t164
  br label %case.end.3.158
case.end.3.158:
  br label %case.join.156
case.arm.4.165:
  %t167 = getelementptr ptr, ptr %t151, i32 1
  %t168 = load ptr, ptr %t167
  call void @__inc_ref(ptr %t168)
  call void @__inc_ref(ptr %t168)
  call void @__inc_ref(ptr %t72)
  %t169 = call ptr @__concat(ptr %t168, ptr %t72)
  %t170 = getelementptr ptr, ptr %t169, i32 0
  %t171 = load ptr, ptr %t170
  %t172 = ptrtoint ptr %t171 to i64
  switch i64 %t172, label %case.default.173 [ i64 3, label %case.arm.3.175 i64 4, label %case.arm.4.183 ]
case.arm.3.175:
  %t177 = getelementptr ptr, ptr %t169, i32 1
  %t178 = load ptr, ptr %t177
  call void @__inc_ref(ptr %t178)
  %t179 = call ptr @__alloc(i64 16, i32 1)
  %t180 = inttoptr i64 3 to ptr
  %t181 = getelementptr ptr, ptr %t179, i32 0
  store ptr %t180, ptr %t181
  call void @__inc_ref(ptr %t178)
  %t182 = getelementptr ptr, ptr %t179, i32 1
  store ptr %t178, ptr %t182
  br label %case.end.3.176
case.end.3.176:
  br label %case.join.174
case.arm.4.183:
  %t185 = getelementptr ptr, ptr %t169, i32 1
  %t186 = load ptr, ptr %t185
  call void @__inc_ref(ptr %t186)
  call void @__inc_ref(ptr %t186)
  %t187 = call ptr @__concat(ptr %t186, ptr getelementptr inbounds (i8, ptr @.str.5, i64 12))
  %t188 = getelementptr ptr, ptr %t187, i32 0
  %t189 = load ptr, ptr %t188
  %t190 = ptrtoint ptr %t189 to i64
  switch i64 %t190, label %case.default.191 [ i64 3, label %case.arm.3.193 i64 4, label %case.arm.4.201 ]
case.arm.3.193:
  %t195 = getelementptr ptr, ptr %t187, i32 1
  %t196 = load ptr, ptr %t195
  call void @__inc_ref(ptr %t196)
  %t197 = call ptr @__alloc(i64 16, i32 1)
  %t198 = inttoptr i64 3 to ptr
  %t199 = getelementptr ptr, ptr %t197, i32 0
  store ptr %t198, ptr %t199
  call void @__inc_ref(ptr %t196)
  %t200 = getelementptr ptr, ptr %t197, i32 1
  store ptr %t196, ptr %t200
  br label %case.end.3.194
case.end.3.194:
  br label %case.join.192
case.arm.4.201:
  %t203 = getelementptr ptr, ptr %t187, i32 1
  %t204 = load ptr, ptr %t203
  call void @__inc_ref(ptr %t204)
  call void @__inc_ref(ptr %t204)
  call void @__inc_ref(ptr %t93)
  %t205 = call ptr @__concat(ptr %t204, ptr %t93)
  %t206 = getelementptr ptr, ptr %t205, i32 0
  %t207 = load ptr, ptr %t206
  %t208 = ptrtoint ptr %t207 to i64
  switch i64 %t208, label %case.default.209 [ i64 3, label %case.arm.3.211 i64 4, label %case.arm.4.219 ]
case.arm.3.211:
  %t213 = getelementptr ptr, ptr %t205, i32 1
  %t214 = load ptr, ptr %t213
  call void @__inc_ref(ptr %t214)
  %t215 = call ptr @__alloc(i64 16, i32 1)
  %t216 = inttoptr i64 3 to ptr
  %t217 = getelementptr ptr, ptr %t215, i32 0
  store ptr %t216, ptr %t217
  call void @__inc_ref(ptr %t214)
  %t218 = getelementptr ptr, ptr %t215, i32 1
  store ptr %t214, ptr %t218
  br label %case.end.3.212
case.end.3.212:
  br label %case.join.210
case.arm.4.219:
  %t221 = getelementptr ptr, ptr %t205, i32 1
  %t222 = load ptr, ptr %t221
  call void @__inc_ref(ptr %t222)
  call void @__inc_ref(ptr %t222)
  %t223 = call ptr @__concat(ptr %t222, ptr getelementptr inbounds (i8, ptr @.str.5, i64 12))
  %t224 = getelementptr ptr, ptr %t223, i32 0
  %t225 = load ptr, ptr %t224
  %t226 = ptrtoint ptr %t225 to i64
  switch i64 %t226, label %case.default.227 [ i64 3, label %case.arm.3.229 i64 4, label %case.arm.4.237 ]
case.arm.3.229:
  %t231 = getelementptr ptr, ptr %t223, i32 1
  %t232 = load ptr, ptr %t231
  call void @__inc_ref(ptr %t232)
  %t233 = call ptr @__alloc(i64 16, i32 1)
  %t234 = inttoptr i64 3 to ptr
  %t235 = getelementptr ptr, ptr %t233, i32 0
  store ptr %t234, ptr %t235
  call void @__inc_ref(ptr %t232)
  %t236 = getelementptr ptr, ptr %t233, i32 1
  store ptr %t232, ptr %t236
  br label %case.end.3.230
case.end.3.230:
  br label %case.join.228
case.arm.4.237:
  %t239 = getelementptr ptr, ptr %t223, i32 1
  %t240 = load ptr, ptr %t239
  call void @__inc_ref(ptr %t240)
  call void @__inc_ref(ptr %t240)
  call void @__inc_ref(ptr %t114)
  %t241 = call ptr @__concat(ptr %t240, ptr %t114)
  br label %case.end.4.238
case.end.4.238:
  br label %case.join.228
case.default.227:
  unreachable
case.join.228:
  %t242 = phi ptr [ %t233, %case.end.3.230 ], [ %t241, %case.end.4.238 ]
  call void @__free_recursive(ptr %t223)
  br label %case.end.4.220
case.end.4.220:
  br label %case.join.210
case.default.209:
  unreachable
case.join.210:
  %t243 = phi ptr [ %t215, %case.end.3.212 ], [ %t242, %case.end.4.220 ]
  call void @__free_recursive(ptr %t205)
  br label %case.end.4.202
case.end.4.202:
  br label %case.join.192
case.default.191:
  unreachable
case.join.192:
  %t244 = phi ptr [ %t197, %case.end.3.194 ], [ %t243, %case.end.4.202 ]
  call void @__free_recursive(ptr %t187)
  br label %case.end.4.184
case.end.4.184:
  br label %case.join.174
case.default.173:
  unreachable
case.join.174:
  %t245 = phi ptr [ %t179, %case.end.3.176 ], [ %t244, %case.end.4.184 ]
  call void @__free_recursive(ptr %t169)
  br label %case.end.4.166
case.end.4.166:
  br label %case.join.156
case.default.155:
  unreachable
case.join.156:
  %t246 = phi ptr [ %t161, %case.end.3.158 ], [ %t245, %case.end.4.166 ]
  call void @__free_recursive(ptr %t151)
  br label %case.end.4.148
case.end.4.148:
  br label %case.join.138
case.default.137:
  unreachable
case.join.138:
  %t247 = phi ptr [ %t143, %case.end.3.140 ], [ %t246, %case.end.4.148 ]
  call void @__free_recursive(ptr %t133)
  br label %case.end.4.130
case.end.4.130:
  br label %case.join.120
case.default.119:
  unreachable
case.join.120:
  %t248 = phi ptr [ %t125, %case.end.3.122 ], [ %t247, %case.end.4.130 ]
  call void @__free_recursive(ptr %t115)
  br label %case.end.4.112
case.end.4.112:
  br label %case.join.102
case.default.101:
  unreachable
case.join.102:
  %t249 = phi ptr [ %t107, %case.end.3.104 ], [ %t248, %case.end.4.112 ]
  call void @__free_recursive(ptr %t97)
  br label %case.end.4.91
case.end.4.91:
  br label %case.join.81
case.default.80:
  unreachable
case.join.81:
  %t250 = phi ptr [ %t86, %case.end.3.83 ], [ %t249, %case.end.4.91 ]
  call void @__free_recursive(ptr %t76)
  br label %case.end.4.70
case.end.4.70:
  br label %case.join.60
case.default.59:
  unreachable
case.join.60:
  %t251 = phi ptr [ %t65, %case.end.3.62 ], [ %t250, %case.end.4.70 ]
  call void @__free_recursive(ptr %t55)
  br label %case.end.4.49
case.end.4.49:
  br label %case.join.39
case.default.38:
  unreachable
case.join.39:
  %t252 = phi ptr [ %t44, %case.end.3.41 ], [ %t251, %case.end.4.49 ]
  call void @__free_recursive(ptr %t34)
  call void @__free_recursive(ptr %t7)
  store ptr %t252, ptr %v__inl4_scrut.jslot
  br label %join.0
join.case.default.11:
  unreachable
join.0:
  %t253 = load ptr, ptr %v__inl4_scrut.jslot
  %t254 = getelementptr ptr, ptr %t253, i32 0
  %t255 = load ptr, ptr %t254
  %t256 = ptrtoint ptr %t255 to i64
  switch i64 %t256, label %case.default.257 [ i64 3, label %case.arm.3.259 i64 4, label %case.arm.4.273 ]
case.arm.3.259:
  %t261 = call ptr @__alloc(i64 24, i32 2)
  %t262 = inttoptr i64 7 to ptr
  %t263 = getelementptr ptr, ptr %t261, i32 0
  store ptr %t262, ptr %t263
  %t264 = getelementptr ptr, ptr %t261, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t264
  %t265 = call ptr @__alloc(i64 16, i32 1)
  %t266 = inttoptr i64 5 to ptr
  %t267 = getelementptr ptr, ptr %t265, i32 0
  store ptr %t266, ptr %t267
  %t268 = call ptr @__alloc(i64 8, i32 0)
  %t269 = inttoptr i64 0 to ptr
  %t270 = getelementptr ptr, ptr %t268, i32 0
  store ptr %t269, ptr %t270
  %t271 = getelementptr ptr, ptr %t265, i32 1
  store ptr %t268, ptr %t271
  %t272 = getelementptr ptr, ptr %t261, i32 2
  store ptr %t265, ptr %t272
  br label %case.end.3.260
case.end.3.260:
  br label %case.join.258
case.arm.4.273:
  %t275 = call ptr @__alloc(i64 24, i32 2)
  %t276 = inttoptr i64 7 to ptr
  %t277 = getelementptr ptr, ptr %t275, i32 0
  store ptr %t276, ptr %t277
  %t278 = getelementptr ptr, ptr %t253, i32 1
  %t279 = load ptr, ptr %t278
  call void @__inc_ref(ptr %t279)
  %t280 = getelementptr ptr, ptr %t275, i32 1
  store ptr %t279, ptr %t280
  %t281 = call ptr @__alloc(i64 16, i32 1)
  %t282 = inttoptr i64 5 to ptr
  %t283 = getelementptr ptr, ptr %t281, i32 0
  store ptr %t282, ptr %t283
  %t284 = call ptr @__alloc(i64 8, i32 0)
  %t285 = inttoptr i64 0 to ptr
  %t286 = getelementptr ptr, ptr %t284, i32 0
  store ptr %t285, ptr %t286
  %t287 = getelementptr ptr, ptr %t281, i32 1
  store ptr %t284, ptr %t287
  %t288 = getelementptr ptr, ptr %t275, i32 2
  store ptr %t281, ptr %t288
  br label %case.end.4.274
case.end.4.274:
  br label %case.join.258
case.default.257:
  unreachable
case.join.258:
  %t289 = phi ptr [ %t261, %case.end.3.260 ], [ %t275, %case.end.4.274 ]
  call void @__free_recursive(ptr %t253)
  br label %join.end.290
join.end.290:
  br label %join.after.1
join.after.1:
  %t291 = phi ptr [ %t13, %join.val.25 ], [ %t289, %join.end.290 ]
  ret ptr %t291
}

define i32 @main(i32 %argc, ptr %argv) {
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
