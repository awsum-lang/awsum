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

define internal ptr @v_main() {
  %v__inl4_scrut.jslot = alloca ptr
  %t2 = call ptr @__alloc(i64 16, i32 1)
  %t3 = inttoptr i64 4 to ptr
  %t4 = getelementptr ptr, ptr %t2, i32 0
  store ptr %t3, ptr %t4
  %t5 = call ptr @__alloc(i64 4, i32 0)
  store i32 42, ptr %t5
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
  store i32 -42, ptr %t32
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
  %t52 = call ptr @__alloc(i64 16, i32 1)
  %t53 = inttoptr i64 3 to ptr
  %t54 = getelementptr ptr, ptr %t52, i32 0
  store ptr %t53, ptr %t54
  %t55 = call ptr @__alloc(i64 16, i32 1)
  %t56 = inttoptr i64 882564211 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  %t58 = call ptr @__alloc(i64 8, i32 0)
  %t59 = inttoptr i64 18 to ptr
  %t60 = getelementptr ptr, ptr %t58, i32 0
  store ptr %t59, ptr %t60
  %t61 = getelementptr ptr, ptr %t55, i32 1
  store ptr %t58, ptr %t61
  %t62 = getelementptr ptr, ptr %t52, i32 1
  store ptr %t55, ptr %t62
  %t63 = call ptr @v_render(ptr %t52)
  %t64 = getelementptr ptr, ptr %t63, i32 0
  %t65 = load ptr, ptr %t64
  %t66 = ptrtoint ptr %t65 to i64
  switch i64 %t66, label %case.default.67 [ i64 3, label %case.arm.3.69 i64 4, label %case.arm.4.77 ]
case.arm.3.69:
  %t71 = getelementptr ptr, ptr %t63, i32 1
  %t72 = load ptr, ptr %t71
  call void @__inc_ref(ptr %t72)
  %t73 = call ptr @__alloc(i64 16, i32 1)
  %t74 = inttoptr i64 3 to ptr
  %t75 = getelementptr ptr, ptr %t73, i32 0
  store ptr %t74, ptr %t75
  call void @__inc_ref(ptr %t72)
  %t76 = getelementptr ptr, ptr %t73, i32 1
  store ptr %t72, ptr %t76
  br label %case.end.3.70
case.end.3.70:
  br label %case.join.68
case.arm.4.77:
  %t79 = getelementptr ptr, ptr %t63, i32 1
  %t80 = load ptr, ptr %t79
  call void @__inc_ref(ptr %t80)
  %t81 = call ptr @__alloc(i64 16, i32 1)
  %t82 = inttoptr i64 3 to ptr
  %t83 = getelementptr ptr, ptr %t81, i32 0
  store ptr %t82, ptr %t83
  %t84 = call ptr @__alloc(i64 16, i32 1)
  %t85 = inttoptr i64 3768445577 to ptr
  %t86 = getelementptr ptr, ptr %t84, i32 0
  store ptr %t85, ptr %t86
  %t87 = call ptr @__alloc(i64 8, i32 0)
  %t88 = inttoptr i64 17 to ptr
  %t89 = getelementptr ptr, ptr %t87, i32 0
  store ptr %t88, ptr %t89
  %t90 = getelementptr ptr, ptr %t84, i32 1
  store ptr %t87, ptr %t90
  %t91 = getelementptr ptr, ptr %t81, i32 1
  store ptr %t84, ptr %t91
  %t92 = call ptr @v_render(ptr %t81)
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
  %t110 = call ptr @v_minInt32()
  %t111 = call ptr @__alloc(i64 4, i32 0)
  store i32 -1, ptr %t111
  %t112 = call ptr @__mulInt32(ptr %t110, ptr %t111)
  %t113 = call ptr @v_render(ptr %t112)
  %t114 = getelementptr ptr, ptr %t113, i32 0
  %t115 = load ptr, ptr %t114
  %t116 = ptrtoint ptr %t115 to i64
  switch i64 %t116, label %case.default.117 [ i64 3, label %case.arm.3.119 i64 4, label %case.arm.4.127 ]
case.arm.3.119:
  %t121 = getelementptr ptr, ptr %t113, i32 1
  %t122 = load ptr, ptr %t121
  call void @__inc_ref(ptr %t122)
  %t123 = call ptr @__alloc(i64 16, i32 1)
  %t124 = inttoptr i64 3 to ptr
  %t125 = getelementptr ptr, ptr %t123, i32 0
  store ptr %t124, ptr %t125
  call void @__inc_ref(ptr %t122)
  %t126 = getelementptr ptr, ptr %t123, i32 1
  store ptr %t122, ptr %t126
  br label %case.end.3.120
case.end.3.120:
  br label %case.join.118
case.arm.4.127:
  %t129 = getelementptr ptr, ptr %t113, i32 1
  %t130 = load ptr, ptr %t129
  call void @__inc_ref(ptr %t130)
  %t131 = call ptr @v_minInt32()
  %t132 = call ptr @__alloc(i64 4, i32 0)
  store i32 1, ptr %t132
  %t133 = call ptr @__mulInt32(ptr %t131, ptr %t132)
  %t134 = call ptr @v_render(ptr %t133)
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
  call void @__inc_ref(ptr %t28)
  %t152 = call ptr @__concat(ptr %t28, ptr getelementptr inbounds (i8, ptr @.str.5, i64 12))
  %t153 = getelementptr ptr, ptr %t152, i32 0
  %t154 = load ptr, ptr %t153
  %t155 = ptrtoint ptr %t154 to i64
  switch i64 %t155, label %case.default.156 [ i64 3, label %case.arm.3.158 i64 4, label %case.arm.4.166 ]
case.arm.3.158:
  %t160 = getelementptr ptr, ptr %t152, i32 1
  %t161 = load ptr, ptr %t160
  call void @__inc_ref(ptr %t161)
  %t162 = call ptr @__alloc(i64 16, i32 1)
  %t163 = inttoptr i64 3 to ptr
  %t164 = getelementptr ptr, ptr %t162, i32 0
  store ptr %t163, ptr %t164
  call void @__inc_ref(ptr %t161)
  %t165 = getelementptr ptr, ptr %t162, i32 1
  store ptr %t161, ptr %t165
  br label %case.end.3.159
case.end.3.159:
  br label %case.join.157
case.arm.4.166:
  %t168 = getelementptr ptr, ptr %t152, i32 1
  %t169 = load ptr, ptr %t168
  call void @__inc_ref(ptr %t169)
  call void @__inc_ref(ptr %t169)
  call void @__inc_ref(ptr %t51)
  %t170 = call ptr @__concat(ptr %t169, ptr %t51)
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
  call void @__inc_ref(ptr %t187)
  %t188 = call ptr @__concat(ptr %t187, ptr getelementptr inbounds (i8, ptr @.str.5, i64 12))
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
  call void @__inc_ref(ptr %t80)
  %t206 = call ptr @__concat(ptr %t205, ptr %t80)
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
  call void @__inc_ref(ptr %t109)
  %t242 = call ptr @__concat(ptr %t241, ptr %t109)
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
  %t260 = call ptr @__concat(ptr %t259, ptr getelementptr inbounds (i8, ptr @.str.5, i64 12))
  %t261 = getelementptr ptr, ptr %t260, i32 0
  %t262 = load ptr, ptr %t261
  %t263 = ptrtoint ptr %t262 to i64
  switch i64 %t263, label %case.default.264 [ i64 3, label %case.arm.3.266 i64 4, label %case.arm.4.274 ]
case.arm.3.266:
  %t268 = getelementptr ptr, ptr %t260, i32 1
  %t269 = load ptr, ptr %t268
  call void @__inc_ref(ptr %t269)
  %t270 = call ptr @__alloc(i64 16, i32 1)
  %t271 = inttoptr i64 3 to ptr
  %t272 = getelementptr ptr, ptr %t270, i32 0
  store ptr %t271, ptr %t272
  call void @__inc_ref(ptr %t269)
  %t273 = getelementptr ptr, ptr %t270, i32 1
  store ptr %t269, ptr %t273
  br label %case.end.3.267
case.end.3.267:
  br label %case.join.265
case.arm.4.274:
  %t276 = getelementptr ptr, ptr %t260, i32 1
  %t277 = load ptr, ptr %t276
  call void @__inc_ref(ptr %t277)
  call void @__inc_ref(ptr %t277)
  call void @__inc_ref(ptr %t130)
  %t278 = call ptr @__concat(ptr %t277, ptr %t130)
  %t279 = getelementptr ptr, ptr %t278, i32 0
  %t280 = load ptr, ptr %t279
  %t281 = ptrtoint ptr %t280 to i64
  switch i64 %t281, label %case.default.282 [ i64 3, label %case.arm.3.284 i64 4, label %case.arm.4.292 ]
case.arm.3.284:
  %t286 = getelementptr ptr, ptr %t278, i32 1
  %t287 = load ptr, ptr %t286
  call void @__inc_ref(ptr %t287)
  %t288 = call ptr @__alloc(i64 16, i32 1)
  %t289 = inttoptr i64 3 to ptr
  %t290 = getelementptr ptr, ptr %t288, i32 0
  store ptr %t289, ptr %t290
  call void @__inc_ref(ptr %t287)
  %t291 = getelementptr ptr, ptr %t288, i32 1
  store ptr %t287, ptr %t291
  br label %case.end.3.285
case.end.3.285:
  br label %case.join.283
case.arm.4.292:
  %t294 = getelementptr ptr, ptr %t278, i32 1
  %t295 = load ptr, ptr %t294
  call void @__inc_ref(ptr %t295)
  call void @__inc_ref(ptr %t295)
  %t296 = call ptr @__concat(ptr %t295, ptr getelementptr inbounds (i8, ptr @.str.5, i64 12))
  %t297 = getelementptr ptr, ptr %t296, i32 0
  %t298 = load ptr, ptr %t297
  %t299 = ptrtoint ptr %t298 to i64
  switch i64 %t299, label %case.default.300 [ i64 3, label %case.arm.3.302 i64 4, label %case.arm.4.310 ]
case.arm.3.302:
  %t304 = getelementptr ptr, ptr %t296, i32 1
  %t305 = load ptr, ptr %t304
  call void @__inc_ref(ptr %t305)
  %t306 = call ptr @__alloc(i64 16, i32 1)
  %t307 = inttoptr i64 3 to ptr
  %t308 = getelementptr ptr, ptr %t306, i32 0
  store ptr %t307, ptr %t308
  call void @__inc_ref(ptr %t305)
  %t309 = getelementptr ptr, ptr %t306, i32 1
  store ptr %t305, ptr %t309
  br label %case.end.3.303
case.end.3.303:
  br label %case.join.301
case.arm.4.310:
  %t312 = getelementptr ptr, ptr %t296, i32 1
  %t313 = load ptr, ptr %t312
  call void @__inc_ref(ptr %t313)
  call void @__inc_ref(ptr %t313)
  call void @__inc_ref(ptr %t151)
  %t314 = call ptr @__concat(ptr %t313, ptr %t151)
  br label %case.end.4.311
case.end.4.311:
  br label %case.join.301
case.default.300:
  unreachable
case.join.301:
  %t315 = phi ptr [ %t306, %case.end.3.303 ], [ %t314, %case.end.4.311 ]
  call void @__free_recursive(ptr %t296)
  br label %case.end.4.293
case.end.4.293:
  br label %case.join.283
case.default.282:
  unreachable
case.join.283:
  %t316 = phi ptr [ %t288, %case.end.3.285 ], [ %t315, %case.end.4.293 ]
  call void @__free_recursive(ptr %t278)
  br label %case.end.4.275
case.end.4.275:
  br label %case.join.265
case.default.264:
  unreachable
case.join.265:
  %t317 = phi ptr [ %t270, %case.end.3.267 ], [ %t316, %case.end.4.275 ]
  call void @__free_recursive(ptr %t260)
  br label %case.end.4.257
case.end.4.257:
  br label %case.join.247
case.default.246:
  unreachable
case.join.247:
  %t318 = phi ptr [ %t252, %case.end.3.249 ], [ %t317, %case.end.4.257 ]
  call void @__free_recursive(ptr %t242)
  br label %case.end.4.239
case.end.4.239:
  br label %case.join.229
case.default.228:
  unreachable
case.join.229:
  %t319 = phi ptr [ %t234, %case.end.3.231 ], [ %t318, %case.end.4.239 ]
  call void @__free_recursive(ptr %t224)
  br label %case.end.4.221
case.end.4.221:
  br label %case.join.211
case.default.210:
  unreachable
case.join.211:
  %t320 = phi ptr [ %t216, %case.end.3.213 ], [ %t319, %case.end.4.221 ]
  call void @__free_recursive(ptr %t206)
  br label %case.end.4.203
case.end.4.203:
  br label %case.join.193
case.default.192:
  unreachable
case.join.193:
  %t321 = phi ptr [ %t198, %case.end.3.195 ], [ %t320, %case.end.4.203 ]
  call void @__free_recursive(ptr %t188)
  br label %case.end.4.185
case.end.4.185:
  br label %case.join.175
case.default.174:
  unreachable
case.join.175:
  %t322 = phi ptr [ %t180, %case.end.3.177 ], [ %t321, %case.end.4.185 ]
  call void @__free_recursive(ptr %t170)
  br label %case.end.4.167
case.end.4.167:
  br label %case.join.157
case.default.156:
  unreachable
case.join.157:
  %t323 = phi ptr [ %t162, %case.end.3.159 ], [ %t322, %case.end.4.167 ]
  call void @__free_recursive(ptr %t152)
  br label %case.end.4.149
case.end.4.149:
  br label %case.join.139
case.default.138:
  unreachable
case.join.139:
  %t324 = phi ptr [ %t144, %case.end.3.141 ], [ %t323, %case.end.4.149 ]
  call void @__free_recursive(ptr %t134)
  br label %case.end.4.128
case.end.4.128:
  br label %case.join.118
case.default.117:
  unreachable
case.join.118:
  %t325 = phi ptr [ %t123, %case.end.3.120 ], [ %t324, %case.end.4.128 ]
  call void @__free_recursive(ptr %t113)
  br label %case.end.4.107
case.end.4.107:
  br label %case.join.97
case.default.96:
  unreachable
case.join.97:
  %t326 = phi ptr [ %t102, %case.end.3.99 ], [ %t325, %case.end.4.107 ]
  call void @__free_recursive(ptr %t92)
  br label %case.end.4.78
case.end.4.78:
  br label %case.join.68
case.default.67:
  unreachable
case.join.68:
  %t327 = phi ptr [ %t73, %case.end.3.70 ], [ %t326, %case.end.4.78 ]
  call void @__free_recursive(ptr %t63)
  br label %case.end.4.49
case.end.4.49:
  br label %case.join.39
case.default.38:
  unreachable
case.join.39:
  %t328 = phi ptr [ %t44, %case.end.3.41 ], [ %t327, %case.end.4.49 ]
  call void @__free_recursive(ptr %t34)
  call void @__free_recursive(ptr %t7)
  store ptr %t328, ptr %v__inl4_scrut.jslot
  br label %join.0
join.case.default.11:
  unreachable
join.0:
  %t329 = load ptr, ptr %v__inl4_scrut.jslot
  %t330 = getelementptr ptr, ptr %t329, i32 0
  %t331 = load ptr, ptr %t330
  %t332 = ptrtoint ptr %t331 to i64
  switch i64 %t332, label %case.default.333 [ i64 3, label %case.arm.3.335 i64 4, label %case.arm.4.349 ]
case.arm.3.335:
  %t337 = call ptr @__alloc(i64 24, i32 2)
  %t338 = inttoptr i64 7 to ptr
  %t339 = getelementptr ptr, ptr %t337, i32 0
  store ptr %t338, ptr %t339
  %t340 = getelementptr ptr, ptr %t337, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t340
  %t341 = call ptr @__alloc(i64 16, i32 1)
  %t342 = inttoptr i64 5 to ptr
  %t343 = getelementptr ptr, ptr %t341, i32 0
  store ptr %t342, ptr %t343
  %t344 = call ptr @__alloc(i64 8, i32 0)
  %t345 = inttoptr i64 0 to ptr
  %t346 = getelementptr ptr, ptr %t344, i32 0
  store ptr %t345, ptr %t346
  %t347 = getelementptr ptr, ptr %t341, i32 1
  store ptr %t344, ptr %t347
  %t348 = getelementptr ptr, ptr %t337, i32 2
  store ptr %t341, ptr %t348
  br label %case.end.3.336
case.end.3.336:
  br label %case.join.334
case.arm.4.349:
  %t351 = call ptr @__alloc(i64 24, i32 2)
  %t352 = inttoptr i64 7 to ptr
  %t353 = getelementptr ptr, ptr %t351, i32 0
  store ptr %t352, ptr %t353
  %t354 = getelementptr ptr, ptr %t329, i32 1
  %t355 = load ptr, ptr %t354
  call void @__inc_ref(ptr %t355)
  %t356 = getelementptr ptr, ptr %t351, i32 1
  store ptr %t355, ptr %t356
  %t357 = call ptr @__alloc(i64 16, i32 1)
  %t358 = inttoptr i64 5 to ptr
  %t359 = getelementptr ptr, ptr %t357, i32 0
  store ptr %t358, ptr %t359
  %t360 = call ptr @__alloc(i64 8, i32 0)
  %t361 = inttoptr i64 0 to ptr
  %t362 = getelementptr ptr, ptr %t360, i32 0
  store ptr %t361, ptr %t362
  %t363 = getelementptr ptr, ptr %t357, i32 1
  store ptr %t360, ptr %t363
  %t364 = getelementptr ptr, ptr %t351, i32 2
  store ptr %t357, ptr %t364
  br label %case.end.4.350
case.end.4.350:
  br label %case.join.334
case.default.333:
  unreachable
case.join.334:
  %t365 = phi ptr [ %t337, %case.end.3.336 ], [ %t351, %case.end.4.350 ]
  call void @__free_recursive(ptr %t329)
  br label %join.end.366
join.end.366:
  br label %join.after.1
join.after.1:
  %t367 = phi ptr [ %t13, %join.val.25 ], [ %t365, %join.end.366 ]
  ret ptr %t367
}

define i32 @main(i32 %argc, ptr %argv) {
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
