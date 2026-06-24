; External C declarations
declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare ptr @memcpy(ptr, ptr, i64)
declare i64 @write(i32, ptr, i64)
declare i32 @snprintf(ptr, i64, ptr, ...)
declare {i32, i1} @llvm.smul.with.overflow.i32(i32, i32)

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


define internal ptr @__mulInt32(ptr %pa, ptr %pb) {
  %a = load i32, ptr %pa
  %b = load i32, ptr %pb
  %res = call {i32, i1} @llvm.smul.with.overflow.i32(i32 %a, i32 %b)
  %prod = extractvalue {i32, i1} %res, 0
  %ovf = extractvalue {i32, i1} %res, 1
  br i1 %ovf, label %err, label %ok
err:
  %xor_ab = xor i32 %a, %b
  %same_sign = icmp sge i32 %xor_ab, 0
  %row_tag_idx = select i1 %same_sign, i64 882564211, i64 3768445577
  %inner = call ptr @__alloc(i64 8, i32 0)
  %inner_tag = inttoptr i64 0 to ptr
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
  store i32 %prod, ptr %box
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

define internal ptr @v_res() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 4 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 4, i32 0)
  store i32 42, ptr %t3
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
  store i32 -42, ptr %t26
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
  %t46 = call ptr @__alloc(i64 16, i32 1)
  %t47 = inttoptr i64 3 to ptr
  %t48 = getelementptr ptr, ptr %t46, i32 0
  store ptr %t47, ptr %t48
  %t49 = call ptr @__alloc(i64 16, i32 1)
  %t50 = inttoptr i64 882564211 to ptr
  %t51 = getelementptr ptr, ptr %t49, i32 0
  store ptr %t50, ptr %t51
  %t52 = call ptr @__alloc(i64 8, i32 0)
  %t53 = inttoptr i64 18 to ptr
  %t54 = getelementptr ptr, ptr %t52, i32 0
  store ptr %t53, ptr %t54
  %t55 = getelementptr ptr, ptr %t49, i32 1
  store ptr %t52, ptr %t55
  %t56 = getelementptr ptr, ptr %t46, i32 1
  store ptr %t49, ptr %t56
  %t57 = call ptr @v_render(ptr %t46)
  %t58 = getelementptr ptr, ptr %t57, i32 0
  %t59 = load ptr, ptr %t58
  %t60 = ptrtoint ptr %t59 to i64
  switch i64 %t60, label %case.default.61 [ i64 3, label %case.arm.3.63 i64 4, label %case.arm.4.71 ]
case.arm.3.63:
  %t65 = getelementptr ptr, ptr %t57, i32 1
  %t66 = load ptr, ptr %t65
  call void @__inc_ref(ptr %t66)
  %t67 = call ptr @__alloc(i64 16, i32 1)
  %t68 = inttoptr i64 3 to ptr
  %t69 = getelementptr ptr, ptr %t67, i32 0
  store ptr %t68, ptr %t69
  call void @__inc_ref(ptr %t66)
  %t70 = getelementptr ptr, ptr %t67, i32 1
  store ptr %t66, ptr %t70
  br label %case.end.3.64
case.end.3.64:
  br label %case.join.62
case.arm.4.71:
  %t73 = getelementptr ptr, ptr %t57, i32 1
  %t74 = load ptr, ptr %t73
  call void @__inc_ref(ptr %t74)
  %t75 = call ptr @__alloc(i64 16, i32 1)
  %t76 = inttoptr i64 3 to ptr
  %t77 = getelementptr ptr, ptr %t75, i32 0
  store ptr %t76, ptr %t77
  %t78 = call ptr @__alloc(i64 16, i32 1)
  %t79 = inttoptr i64 3768445577 to ptr
  %t80 = getelementptr ptr, ptr %t78, i32 0
  store ptr %t79, ptr %t80
  %t81 = call ptr @__alloc(i64 8, i32 0)
  %t82 = inttoptr i64 17 to ptr
  %t83 = getelementptr ptr, ptr %t81, i32 0
  store ptr %t82, ptr %t83
  %t84 = getelementptr ptr, ptr %t78, i32 1
  store ptr %t81, ptr %t84
  %t85 = getelementptr ptr, ptr %t75, i32 1
  store ptr %t78, ptr %t85
  %t86 = call ptr @v_render(ptr %t75)
  %t87 = getelementptr ptr, ptr %t86, i32 0
  %t88 = load ptr, ptr %t87
  %t89 = ptrtoint ptr %t88 to i64
  switch i64 %t89, label %case.default.90 [ i64 3, label %case.arm.3.92 i64 4, label %case.arm.4.100 ]
case.arm.3.92:
  %t94 = getelementptr ptr, ptr %t86, i32 1
  %t95 = load ptr, ptr %t94
  call void @__inc_ref(ptr %t95)
  %t96 = call ptr @__alloc(i64 16, i32 1)
  %t97 = inttoptr i64 3 to ptr
  %t98 = getelementptr ptr, ptr %t96, i32 0
  store ptr %t97, ptr %t98
  call void @__inc_ref(ptr %t95)
  %t99 = getelementptr ptr, ptr %t96, i32 1
  store ptr %t95, ptr %t99
  br label %case.end.3.93
case.end.3.93:
  br label %case.join.91
case.arm.4.100:
  %t102 = getelementptr ptr, ptr %t86, i32 1
  %t103 = load ptr, ptr %t102
  call void @__inc_ref(ptr %t103)
  %t104 = call ptr @v_minInt32()
  %t105 = call ptr @__alloc(i64 4, i32 0)
  store i32 -1, ptr %t105
  %t106 = call ptr @__mulInt32(ptr %t104, ptr %t105)
  %t107 = call ptr @v_render(ptr %t106)
  %t108 = getelementptr ptr, ptr %t107, i32 0
  %t109 = load ptr, ptr %t108
  %t110 = ptrtoint ptr %t109 to i64
  switch i64 %t110, label %case.default.111 [ i64 3, label %case.arm.3.113 i64 4, label %case.arm.4.121 ]
case.arm.3.113:
  %t115 = getelementptr ptr, ptr %t107, i32 1
  %t116 = load ptr, ptr %t115
  call void @__inc_ref(ptr %t116)
  %t117 = call ptr @__alloc(i64 16, i32 1)
  %t118 = inttoptr i64 3 to ptr
  %t119 = getelementptr ptr, ptr %t117, i32 0
  store ptr %t118, ptr %t119
  call void @__inc_ref(ptr %t116)
  %t120 = getelementptr ptr, ptr %t117, i32 1
  store ptr %t116, ptr %t120
  br label %case.end.3.114
case.end.3.114:
  br label %case.join.112
case.arm.4.121:
  %t123 = getelementptr ptr, ptr %t107, i32 1
  %t124 = load ptr, ptr %t123
  call void @__inc_ref(ptr %t124)
  %t125 = call ptr @v_minInt32()
  %t126 = call ptr @__alloc(i64 4, i32 0)
  store i32 1, ptr %t126
  %t127 = call ptr @__mulInt32(ptr %t125, ptr %t126)
  %t128 = call ptr @v_render(ptr %t127)
  %t129 = getelementptr ptr, ptr %t128, i32 0
  %t130 = load ptr, ptr %t129
  %t131 = ptrtoint ptr %t130 to i64
  switch i64 %t131, label %case.default.132 [ i64 3, label %case.arm.3.134 i64 4, label %case.arm.4.142 ]
case.arm.3.134:
  %t136 = getelementptr ptr, ptr %t128, i32 1
  %t137 = load ptr, ptr %t136
  call void @__inc_ref(ptr %t137)
  %t138 = call ptr @__alloc(i64 16, i32 1)
  %t139 = inttoptr i64 3 to ptr
  %t140 = getelementptr ptr, ptr %t138, i32 0
  store ptr %t139, ptr %t140
  call void @__inc_ref(ptr %t137)
  %t141 = getelementptr ptr, ptr %t138, i32 1
  store ptr %t137, ptr %t141
  br label %case.end.3.135
case.end.3.135:
  br label %case.join.133
case.arm.4.142:
  %t144 = getelementptr ptr, ptr %t128, i32 1
  %t145 = load ptr, ptr %t144
  call void @__inc_ref(ptr %t145)
  call void @__inc_ref(ptr %t22)
  %t146 = call ptr @__concat(ptr %t22, ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  %t147 = getelementptr ptr, ptr %t146, i32 0
  %t148 = load ptr, ptr %t147
  %t149 = ptrtoint ptr %t148 to i64
  switch i64 %t149, label %case.default.150 [ i64 3, label %case.arm.3.152 i64 4, label %case.arm.4.160 ]
case.arm.3.152:
  %t154 = getelementptr ptr, ptr %t146, i32 1
  %t155 = load ptr, ptr %t154
  call void @__inc_ref(ptr %t155)
  %t156 = call ptr @__alloc(i64 16, i32 1)
  %t157 = inttoptr i64 3 to ptr
  %t158 = getelementptr ptr, ptr %t156, i32 0
  store ptr %t157, ptr %t158
  call void @__inc_ref(ptr %t155)
  %t159 = getelementptr ptr, ptr %t156, i32 1
  store ptr %t155, ptr %t159
  br label %case.end.3.153
case.end.3.153:
  br label %case.join.151
case.arm.4.160:
  %t162 = getelementptr ptr, ptr %t146, i32 1
  %t163 = load ptr, ptr %t162
  call void @__inc_ref(ptr %t163)
  call void @__inc_ref(ptr %t163)
  call void @__inc_ref(ptr %t45)
  %t164 = call ptr @__concat(ptr %t163, ptr %t45)
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
  call void @__inc_ref(ptr %t181)
  %t182 = call ptr @__concat(ptr %t181, ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
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
  call void @__inc_ref(ptr %t74)
  %t200 = call ptr @__concat(ptr %t199, ptr %t74)
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
  %t218 = call ptr @__concat(ptr %t217, ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
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
  call void @__inc_ref(ptr %t103)
  %t236 = call ptr @__concat(ptr %t235, ptr %t103)
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
  %t254 = call ptr @__concat(ptr %t253, ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
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
  call void @__inc_ref(ptr %t124)
  %t272 = call ptr @__concat(ptr %t271, ptr %t124)
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
  %t290 = call ptr @__concat(ptr %t289, ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  %t291 = getelementptr ptr, ptr %t290, i32 0
  %t292 = load ptr, ptr %t291
  %t293 = ptrtoint ptr %t292 to i64
  switch i64 %t293, label %case.default.294 [ i64 3, label %case.arm.3.296 i64 4, label %case.arm.4.304 ]
case.arm.3.296:
  %t298 = getelementptr ptr, ptr %t290, i32 1
  %t299 = load ptr, ptr %t298
  call void @__inc_ref(ptr %t299)
  %t300 = call ptr @__alloc(i64 16, i32 1)
  %t301 = inttoptr i64 3 to ptr
  %t302 = getelementptr ptr, ptr %t300, i32 0
  store ptr %t301, ptr %t302
  call void @__inc_ref(ptr %t299)
  %t303 = getelementptr ptr, ptr %t300, i32 1
  store ptr %t299, ptr %t303
  br label %case.end.3.297
case.end.3.297:
  br label %case.join.295
case.arm.4.304:
  %t306 = getelementptr ptr, ptr %t290, i32 1
  %t307 = load ptr, ptr %t306
  call void @__inc_ref(ptr %t307)
  call void @__inc_ref(ptr %t307)
  call void @__inc_ref(ptr %t145)
  %t308 = call ptr @__concat(ptr %t307, ptr %t145)
  br label %case.end.4.305
case.end.4.305:
  br label %case.join.295
case.default.294:
  unreachable
case.join.295:
  %t309 = phi ptr [ %t300, %case.end.3.297 ], [ %t308, %case.end.4.305 ]
  call void @__free_recursive(ptr %t290)
  br label %case.end.4.287
case.end.4.287:
  br label %case.join.277
case.default.276:
  unreachable
case.join.277:
  %t310 = phi ptr [ %t282, %case.end.3.279 ], [ %t309, %case.end.4.287 ]
  call void @__free_recursive(ptr %t272)
  br label %case.end.4.269
case.end.4.269:
  br label %case.join.259
case.default.258:
  unreachable
case.join.259:
  %t311 = phi ptr [ %t264, %case.end.3.261 ], [ %t310, %case.end.4.269 ]
  call void @__free_recursive(ptr %t254)
  br label %case.end.4.251
case.end.4.251:
  br label %case.join.241
case.default.240:
  unreachable
case.join.241:
  %t312 = phi ptr [ %t246, %case.end.3.243 ], [ %t311, %case.end.4.251 ]
  call void @__free_recursive(ptr %t236)
  br label %case.end.4.233
case.end.4.233:
  br label %case.join.223
case.default.222:
  unreachable
case.join.223:
  %t313 = phi ptr [ %t228, %case.end.3.225 ], [ %t312, %case.end.4.233 ]
  call void @__free_recursive(ptr %t218)
  br label %case.end.4.215
case.end.4.215:
  br label %case.join.205
case.default.204:
  unreachable
case.join.205:
  %t314 = phi ptr [ %t210, %case.end.3.207 ], [ %t313, %case.end.4.215 ]
  call void @__free_recursive(ptr %t200)
  br label %case.end.4.197
case.end.4.197:
  br label %case.join.187
case.default.186:
  unreachable
case.join.187:
  %t315 = phi ptr [ %t192, %case.end.3.189 ], [ %t314, %case.end.4.197 ]
  call void @__free_recursive(ptr %t182)
  br label %case.end.4.179
case.end.4.179:
  br label %case.join.169
case.default.168:
  unreachable
case.join.169:
  %t316 = phi ptr [ %t174, %case.end.3.171 ], [ %t315, %case.end.4.179 ]
  call void @__free_recursive(ptr %t164)
  br label %case.end.4.161
case.end.4.161:
  br label %case.join.151
case.default.150:
  unreachable
case.join.151:
  %t317 = phi ptr [ %t156, %case.end.3.153 ], [ %t316, %case.end.4.161 ]
  call void @__free_recursive(ptr %t146)
  br label %case.end.4.143
case.end.4.143:
  br label %case.join.133
case.default.132:
  unreachable
case.join.133:
  %t318 = phi ptr [ %t138, %case.end.3.135 ], [ %t317, %case.end.4.143 ]
  call void @__free_recursive(ptr %t128)
  br label %case.end.4.122
case.end.4.122:
  br label %case.join.112
case.default.111:
  unreachable
case.join.112:
  %t319 = phi ptr [ %t117, %case.end.3.114 ], [ %t318, %case.end.4.122 ]
  call void @__free_recursive(ptr %t107)
  br label %case.end.4.101
case.end.4.101:
  br label %case.join.91
case.default.90:
  unreachable
case.join.91:
  %t320 = phi ptr [ %t96, %case.end.3.93 ], [ %t319, %case.end.4.101 ]
  call void @__free_recursive(ptr %t86)
  br label %case.end.4.72
case.end.4.72:
  br label %case.join.62
case.default.61:
  unreachable
case.join.62:
  %t321 = phi ptr [ %t67, %case.end.3.64 ], [ %t320, %case.end.4.72 ]
  call void @__free_recursive(ptr %t57)
  br label %case.end.4.43
case.end.4.43:
  br label %case.join.33
case.default.32:
  unreachable
case.join.33:
  %t322 = phi ptr [ %t38, %case.end.3.35 ], [ %t321, %case.end.4.43 ]
  call void @__free_recursive(ptr %t28)
  br label %case.end.4.20
case.end.4.20:
  br label %case.join.10
case.default.9:
  unreachable
case.join.10:
  %t323 = phi ptr [ %t15, %case.end.3.12 ], [ %t322, %case.end.4.20 ]
  call void @__free_recursive(ptr %t5)
  ret ptr %t323
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
