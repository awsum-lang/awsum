; External C declarations
declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare ptr @memcpy(ptr, ptr, i64)
declare i64 @write(i32, ptr, i64)
declare i32 @snprintf(ptr, i64, ptr, ...)
declare {i32, i1} @llvm.sadd.with.overflow.i32(i32, i32)

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
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c", " }
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


define internal ptr @__addInt32(ptr %pa, ptr %pb) {
  %a = load i32, ptr %pa
  %b = load i32, ptr %pb
  %res = call {i32, i1} @llvm.sadd.with.overflow.i32(i32 %a, i32 %b)
  %sum = extractvalue {i32, i1} %res, 0
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
  store i32 %sum, ptr %box
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
  call void @__free_recursive(ptr %t6)
  %t12 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  call void @__free_recursive(ptr %v_r)
  ret ptr %t12
case.arm.3768445577.13:
  call void @__free_recursive(ptr %t6)
  %t14 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
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

define internal ptr @v_res() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 4 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 4, i32 0)
  store i32 123, ptr %t3
  %t4 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t4
  %t5 = call ptr @v_render(ptr %t0)
  %t6 = getelementptr ptr, ptr %t5, i32 0
  %t7 = load ptr, ptr %t6
  %t8 = ptrtoint ptr %t7 to i64
  switch i64 %t8, label %case.default.9 [ i64 3, label %case.arm.3.11 i64 4, label %case.arm.4.19 ]
case.arm.3.11:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  %t15 = call ptr @__alloc(i64 16, i32 1)
  %t16 = inttoptr i64 3 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  call void @__inc_ref(ptr %t14)
  %t18 = getelementptr ptr, ptr %t15, i32 1
  store ptr %t14, ptr %t18
  br label %case.end.3.12
case.end.3.12:
  br label %case.join.10
case.arm.4.19:
  %t21 = getelementptr ptr, ptr %t5, i32 1
  %t22 = load ptr, ptr %t21
  call void @__inc_ref(ptr %t22)
  %t23 = call ptr @__alloc(i64 16, i32 1)
  %t24 = inttoptr i64 4 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  %t26 = call ptr @__alloc(i64 4, i32 0)
  store i32 50, ptr %t26
  %t27 = getelementptr ptr, ptr %t23, i32 1
  store ptr %t26, ptr %t27
  %t28 = call ptr @v_render(ptr %t23)
  %t29 = getelementptr ptr, ptr %t28, i32 0
  %t30 = load ptr, ptr %t29
  %t31 = ptrtoint ptr %t30 to i64
  switch i64 %t31, label %case.default.32 [ i64 3, label %case.arm.3.34 i64 4, label %case.arm.4.42 ]
case.arm.3.34:
  %t36 = getelementptr ptr, ptr %t28, i32 1
  %t37 = load ptr, ptr %t36
  call void @__inc_ref(ptr %t37)
  %t38 = call ptr @__alloc(i64 16, i32 1)
  %t39 = inttoptr i64 3 to ptr
  %t40 = getelementptr ptr, ptr %t38, i32 0
  store ptr %t39, ptr %t40
  call void @__inc_ref(ptr %t37)
  %t41 = getelementptr ptr, ptr %t38, i32 1
  store ptr %t37, ptr %t41
  br label %case.end.3.35
case.end.3.35:
  br label %case.join.33
case.arm.4.42:
  %t44 = getelementptr ptr, ptr %t28, i32 1
  %t45 = load ptr, ptr %t44
  call void @__inc_ref(ptr %t45)
  %t46 = call ptr @v_maxInt32()
  %t47 = call ptr @__alloc(i64 4, i32 0)
  store i32 1, ptr %t47
  %t48 = call ptr @__addInt32(ptr %t46, ptr %t47)
  %t49 = call ptr @v_render(ptr %t48)
  %t50 = getelementptr ptr, ptr %t49, i32 0
  %t51 = load ptr, ptr %t50
  %t52 = ptrtoint ptr %t51 to i64
  switch i64 %t52, label %case.default.53 [ i64 3, label %case.arm.3.55 i64 4, label %case.arm.4.63 ]
case.arm.3.55:
  %t57 = getelementptr ptr, ptr %t49, i32 1
  %t58 = load ptr, ptr %t57
  call void @__inc_ref(ptr %t58)
  %t59 = call ptr @__alloc(i64 16, i32 1)
  %t60 = inttoptr i64 3 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  call void @__inc_ref(ptr %t58)
  %t62 = getelementptr ptr, ptr %t59, i32 1
  store ptr %t58, ptr %t62
  br label %case.end.3.56
case.end.3.56:
  br label %case.join.54
case.arm.4.63:
  %t65 = getelementptr ptr, ptr %t49, i32 1
  %t66 = load ptr, ptr %t65
  call void @__inc_ref(ptr %t66)
  %t67 = call ptr @v_minInt32()
  %t68 = call ptr @__alloc(i64 4, i32 0)
  store i32 -1, ptr %t68
  %t69 = call ptr @__addInt32(ptr %t67, ptr %t68)
  %t70 = call ptr @v_render(ptr %t69)
  %t71 = getelementptr ptr, ptr %t70, i32 0
  %t72 = load ptr, ptr %t71
  %t73 = ptrtoint ptr %t72 to i64
  switch i64 %t73, label %case.default.74 [ i64 3, label %case.arm.3.76 i64 4, label %case.arm.4.84 ]
case.arm.3.76:
  %t78 = getelementptr ptr, ptr %t70, i32 1
  %t79 = load ptr, ptr %t78
  call void @__inc_ref(ptr %t79)
  %t80 = call ptr @__alloc(i64 16, i32 1)
  %t81 = inttoptr i64 3 to ptr
  %t82 = getelementptr ptr, ptr %t80, i32 0
  store ptr %t81, ptr %t82
  call void @__inc_ref(ptr %t79)
  %t83 = getelementptr ptr, ptr %t80, i32 1
  store ptr %t79, ptr %t83
  br label %case.end.3.77
case.end.3.77:
  br label %case.join.75
case.arm.4.84:
  %t86 = getelementptr ptr, ptr %t70, i32 1
  %t87 = load ptr, ptr %t86
  call void @__inc_ref(ptr %t87)
  %t88 = call ptr @v_maxInt32()
  %t89 = call ptr @v_minInt32()
  %t90 = call ptr @__addInt32(ptr %t88, ptr %t89)
  %t91 = call ptr @v_render(ptr %t90)
  %t92 = getelementptr ptr, ptr %t91, i32 0
  %t93 = load ptr, ptr %t92
  %t94 = ptrtoint ptr %t93 to i64
  switch i64 %t94, label %case.default.95 [ i64 3, label %case.arm.3.97 i64 4, label %case.arm.4.105 ]
case.arm.3.97:
  %t99 = getelementptr ptr, ptr %t91, i32 1
  %t100 = load ptr, ptr %t99
  call void @__inc_ref(ptr %t100)
  %t101 = call ptr @__alloc(i64 16, i32 1)
  %t102 = inttoptr i64 3 to ptr
  %t103 = getelementptr ptr, ptr %t101, i32 0
  store ptr %t102, ptr %t103
  call void @__inc_ref(ptr %t100)
  %t104 = getelementptr ptr, ptr %t101, i32 1
  store ptr %t100, ptr %t104
  br label %case.end.3.98
case.end.3.98:
  br label %case.join.96
case.arm.4.105:
  %t107 = getelementptr ptr, ptr %t91, i32 1
  %t108 = load ptr, ptr %t107
  call void @__inc_ref(ptr %t108)
  call void @__inc_ref(ptr %t22)
  %t109 = call ptr @__concat(ptr %t22, ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  %t110 = getelementptr ptr, ptr %t109, i32 0
  %t111 = load ptr, ptr %t110
  %t112 = ptrtoint ptr %t111 to i64
  switch i64 %t112, label %case.default.113 [ i64 3, label %case.arm.3.115 i64 4, label %case.arm.4.123 ]
case.arm.3.115:
  %t117 = getelementptr ptr, ptr %t109, i32 1
  %t118 = load ptr, ptr %t117
  call void @__inc_ref(ptr %t118)
  %t119 = call ptr @__alloc(i64 16, i32 1)
  %t120 = inttoptr i64 3 to ptr
  %t121 = getelementptr ptr, ptr %t119, i32 0
  store ptr %t120, ptr %t121
  call void @__inc_ref(ptr %t118)
  %t122 = getelementptr ptr, ptr %t119, i32 1
  store ptr %t118, ptr %t122
  br label %case.end.3.116
case.end.3.116:
  br label %case.join.114
case.arm.4.123:
  %t125 = getelementptr ptr, ptr %t109, i32 1
  %t126 = load ptr, ptr %t125
  call void @__inc_ref(ptr %t126)
  call void @__inc_ref(ptr %t126)
  call void @__inc_ref(ptr %t45)
  %t127 = call ptr @__concat(ptr %t126, ptr %t45)
  %t128 = getelementptr ptr, ptr %t127, i32 0
  %t129 = load ptr, ptr %t128
  %t130 = ptrtoint ptr %t129 to i64
  switch i64 %t130, label %case.default.131 [ i64 3, label %case.arm.3.133 i64 4, label %case.arm.4.141 ]
case.arm.3.133:
  %t135 = getelementptr ptr, ptr %t127, i32 1
  %t136 = load ptr, ptr %t135
  call void @__inc_ref(ptr %t136)
  %t137 = call ptr @__alloc(i64 16, i32 1)
  %t138 = inttoptr i64 3 to ptr
  %t139 = getelementptr ptr, ptr %t137, i32 0
  store ptr %t138, ptr %t139
  call void @__inc_ref(ptr %t136)
  %t140 = getelementptr ptr, ptr %t137, i32 1
  store ptr %t136, ptr %t140
  br label %case.end.3.134
case.end.3.134:
  br label %case.join.132
case.arm.4.141:
  %t143 = getelementptr ptr, ptr %t127, i32 1
  %t144 = load ptr, ptr %t143
  call void @__inc_ref(ptr %t144)
  call void @__inc_ref(ptr %t144)
  %t145 = call ptr @__concat(ptr %t144, ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  %t146 = getelementptr ptr, ptr %t145, i32 0
  %t147 = load ptr, ptr %t146
  %t148 = ptrtoint ptr %t147 to i64
  switch i64 %t148, label %case.default.149 [ i64 3, label %case.arm.3.151 i64 4, label %case.arm.4.159 ]
case.arm.3.151:
  %t153 = getelementptr ptr, ptr %t145, i32 1
  %t154 = load ptr, ptr %t153
  call void @__inc_ref(ptr %t154)
  %t155 = call ptr @__alloc(i64 16, i32 1)
  %t156 = inttoptr i64 3 to ptr
  %t157 = getelementptr ptr, ptr %t155, i32 0
  store ptr %t156, ptr %t157
  call void @__inc_ref(ptr %t154)
  %t158 = getelementptr ptr, ptr %t155, i32 1
  store ptr %t154, ptr %t158
  br label %case.end.3.152
case.end.3.152:
  br label %case.join.150
case.arm.4.159:
  %t161 = getelementptr ptr, ptr %t145, i32 1
  %t162 = load ptr, ptr %t161
  call void @__inc_ref(ptr %t162)
  call void @__inc_ref(ptr %t162)
  call void @__inc_ref(ptr %t66)
  %t163 = call ptr @__concat(ptr %t162, ptr %t66)
  %t164 = getelementptr ptr, ptr %t163, i32 0
  %t165 = load ptr, ptr %t164
  %t166 = ptrtoint ptr %t165 to i64
  switch i64 %t166, label %case.default.167 [ i64 3, label %case.arm.3.169 i64 4, label %case.arm.4.177 ]
case.arm.3.169:
  %t171 = getelementptr ptr, ptr %t163, i32 1
  %t172 = load ptr, ptr %t171
  call void @__inc_ref(ptr %t172)
  %t173 = call ptr @__alloc(i64 16, i32 1)
  %t174 = inttoptr i64 3 to ptr
  %t175 = getelementptr ptr, ptr %t173, i32 0
  store ptr %t174, ptr %t175
  call void @__inc_ref(ptr %t172)
  %t176 = getelementptr ptr, ptr %t173, i32 1
  store ptr %t172, ptr %t176
  br label %case.end.3.170
case.end.3.170:
  br label %case.join.168
case.arm.4.177:
  %t179 = getelementptr ptr, ptr %t163, i32 1
  %t180 = load ptr, ptr %t179
  call void @__inc_ref(ptr %t180)
  call void @__inc_ref(ptr %t180)
  %t181 = call ptr @__concat(ptr %t180, ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  %t182 = getelementptr ptr, ptr %t181, i32 0
  %t183 = load ptr, ptr %t182
  %t184 = ptrtoint ptr %t183 to i64
  switch i64 %t184, label %case.default.185 [ i64 3, label %case.arm.3.187 i64 4, label %case.arm.4.195 ]
case.arm.3.187:
  %t189 = getelementptr ptr, ptr %t181, i32 1
  %t190 = load ptr, ptr %t189
  call void @__inc_ref(ptr %t190)
  %t191 = call ptr @__alloc(i64 16, i32 1)
  %t192 = inttoptr i64 3 to ptr
  %t193 = getelementptr ptr, ptr %t191, i32 0
  store ptr %t192, ptr %t193
  call void @__inc_ref(ptr %t190)
  %t194 = getelementptr ptr, ptr %t191, i32 1
  store ptr %t190, ptr %t194
  br label %case.end.3.188
case.end.3.188:
  br label %case.join.186
case.arm.4.195:
  %t197 = getelementptr ptr, ptr %t181, i32 1
  %t198 = load ptr, ptr %t197
  call void @__inc_ref(ptr %t198)
  call void @__inc_ref(ptr %t198)
  call void @__inc_ref(ptr %t87)
  %t199 = call ptr @__concat(ptr %t198, ptr %t87)
  %t200 = getelementptr ptr, ptr %t199, i32 0
  %t201 = load ptr, ptr %t200
  %t202 = ptrtoint ptr %t201 to i64
  switch i64 %t202, label %case.default.203 [ i64 3, label %case.arm.3.205 i64 4, label %case.arm.4.213 ]
case.arm.3.205:
  %t207 = getelementptr ptr, ptr %t199, i32 1
  %t208 = load ptr, ptr %t207
  call void @__inc_ref(ptr %t208)
  %t209 = call ptr @__alloc(i64 16, i32 1)
  %t210 = inttoptr i64 3 to ptr
  %t211 = getelementptr ptr, ptr %t209, i32 0
  store ptr %t210, ptr %t211
  call void @__inc_ref(ptr %t208)
  %t212 = getelementptr ptr, ptr %t209, i32 1
  store ptr %t208, ptr %t212
  br label %case.end.3.206
case.end.3.206:
  br label %case.join.204
case.arm.4.213:
  %t215 = getelementptr ptr, ptr %t199, i32 1
  %t216 = load ptr, ptr %t215
  call void @__inc_ref(ptr %t216)
  call void @__inc_ref(ptr %t216)
  %t217 = call ptr @__concat(ptr %t216, ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  %t218 = getelementptr ptr, ptr %t217, i32 0
  %t219 = load ptr, ptr %t218
  %t220 = ptrtoint ptr %t219 to i64
  switch i64 %t220, label %case.default.221 [ i64 3, label %case.arm.3.223 i64 4, label %case.arm.4.231 ]
case.arm.3.223:
  %t225 = getelementptr ptr, ptr %t217, i32 1
  %t226 = load ptr, ptr %t225
  call void @__inc_ref(ptr %t226)
  %t227 = call ptr @__alloc(i64 16, i32 1)
  %t228 = inttoptr i64 3 to ptr
  %t229 = getelementptr ptr, ptr %t227, i32 0
  store ptr %t228, ptr %t229
  call void @__inc_ref(ptr %t226)
  %t230 = getelementptr ptr, ptr %t227, i32 1
  store ptr %t226, ptr %t230
  br label %case.end.3.224
case.end.3.224:
  br label %case.join.222
case.arm.4.231:
  %t233 = getelementptr ptr, ptr %t217, i32 1
  %t234 = load ptr, ptr %t233
  call void @__inc_ref(ptr %t234)
  call void @__inc_ref(ptr %t234)
  call void @__inc_ref(ptr %t108)
  %t235 = call ptr @__concat(ptr %t234, ptr %t108)
  br label %case.end.4.232
case.end.4.232:
  br label %case.join.222
case.default.221:
  unreachable
case.join.222:
  %t236 = phi ptr [ %t227, %case.end.3.224 ], [ %t235, %case.end.4.232 ]
  call void @__free_recursive(ptr %t217)
  br label %case.end.4.214
case.end.4.214:
  br label %case.join.204
case.default.203:
  unreachable
case.join.204:
  %t237 = phi ptr [ %t209, %case.end.3.206 ], [ %t236, %case.end.4.214 ]
  call void @__free_recursive(ptr %t199)
  br label %case.end.4.196
case.end.4.196:
  br label %case.join.186
case.default.185:
  unreachable
case.join.186:
  %t238 = phi ptr [ %t191, %case.end.3.188 ], [ %t237, %case.end.4.196 ]
  call void @__free_recursive(ptr %t181)
  br label %case.end.4.178
case.end.4.178:
  br label %case.join.168
case.default.167:
  unreachable
case.join.168:
  %t239 = phi ptr [ %t173, %case.end.3.170 ], [ %t238, %case.end.4.178 ]
  call void @__free_recursive(ptr %t163)
  br label %case.end.4.160
case.end.4.160:
  br label %case.join.150
case.default.149:
  unreachable
case.join.150:
  %t240 = phi ptr [ %t155, %case.end.3.152 ], [ %t239, %case.end.4.160 ]
  call void @__free_recursive(ptr %t145)
  br label %case.end.4.142
case.end.4.142:
  br label %case.join.132
case.default.131:
  unreachable
case.join.132:
  %t241 = phi ptr [ %t137, %case.end.3.134 ], [ %t240, %case.end.4.142 ]
  call void @__free_recursive(ptr %t127)
  br label %case.end.4.124
case.end.4.124:
  br label %case.join.114
case.default.113:
  unreachable
case.join.114:
  %t242 = phi ptr [ %t119, %case.end.3.116 ], [ %t241, %case.end.4.124 ]
  call void @__free_recursive(ptr %t109)
  br label %case.end.4.106
case.end.4.106:
  br label %case.join.96
case.default.95:
  unreachable
case.join.96:
  %t243 = phi ptr [ %t101, %case.end.3.98 ], [ %t242, %case.end.4.106 ]
  call void @__free_recursive(ptr %t91)
  br label %case.end.4.85
case.end.4.85:
  br label %case.join.75
case.default.74:
  unreachable
case.join.75:
  %t244 = phi ptr [ %t80, %case.end.3.77 ], [ %t243, %case.end.4.85 ]
  call void @__free_recursive(ptr %t70)
  br label %case.end.4.64
case.end.4.64:
  br label %case.join.54
case.default.53:
  unreachable
case.join.54:
  %t245 = phi ptr [ %t59, %case.end.3.56 ], [ %t244, %case.end.4.64 ]
  call void @__free_recursive(ptr %t49)
  br label %case.end.4.43
case.end.4.43:
  br label %case.join.33
case.default.32:
  unreachable
case.join.33:
  %t246 = phi ptr [ %t38, %case.end.3.35 ], [ %t245, %case.end.4.43 ]
  call void @__free_recursive(ptr %t28)
  br label %case.end.4.20
case.end.4.20:
  br label %case.join.10
case.default.9:
  unreachable
case.join.10:
  %t247 = phi ptr [ %t15, %case.end.3.12 ], [ %t246, %case.end.4.20 ]
  call void @__free_recursive(ptr %t5)
  ret ptr %t247
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
  %t26 = call ptr @v_$cps$$df$andThenIO$4(ptr %t22, ptr %t23)
  %t27 = call ptr @__alloc(i64 8, i32 0)
  %t28 = inttoptr i64 20 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  %t30 = call ptr @v_$cps$$df$handleErrorIO$0(ptr %t26, ptr %t27)
  ret ptr %t30
}

define internal ptr @v_$cps$$df$handleErrorIO$0(ptr %v_io, ptr %v_$k) {
entry:
  %t3 = alloca ptr
  store ptr %v_io, ptr %t3
  %t4 = alloca ptr
  store ptr %v_$k, ptr %t4
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
  %t12 = call ptr @v_$apply$$df$handleErrorIO$0(ptr %t6, ptr %t5)
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
  store ptr getelementptr inbounds (i8, ptr @.str.5, i64 12), ptr %t17
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
  %t26 = call ptr @v_$apply$$df$handleErrorIO$0(ptr %t6, ptr %t14)
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

define internal ptr @v_$apply$$df$handleErrorIO$0(ptr %v_$k, ptr %v_$x) {
entry:
  %t3 = alloca ptr
  store ptr %v_$k, ptr %t3
  %t4 = alloca ptr
  store ptr %v_$x, ptr %t4
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

define internal ptr @v_$cps$$df$andThenIO$4(ptr %v_io, ptr %v_$k) {
entry:
  %t3 = alloca ptr
  store ptr %v_io, ptr %t3
  %t4 = alloca ptr
  store ptr %v_$k, ptr %t4
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
  %t26 = call ptr @v_$apply$$df$andThenIO$4(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t26, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.27:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t28 = call ptr @v_$apply$$df$andThenIO$4(ptr %t6, ptr %t5)
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

define internal ptr @v_$apply$$df$andThenIO$4(ptr %v_$k, ptr %v_$x) {
entry:
  %t3 = alloca ptr
  store ptr %v_$k, ptr %t3
  %t4 = alloca ptr
  store ptr %v_$x, ptr %t4
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

define i32 @main(i32 %argc, ptr %argv) {
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
