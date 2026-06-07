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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [14 x i8]} { i32 0, i32 0, i32 0, i32 14, i32 14, [14 x i8] c"UnderflowError" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [13 x i8]} { i32 0, i32 0, i32 0, i32 13, i32 13, [13 x i8] c"OverflowError" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"err: " }
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

define internal ptr @v_showUnderflowError(ptr %v__wild0) {
  call void @__free_recursive(ptr %v__wild0)
  ret ptr getelementptr inbounds (i8, ptr @.str.0, i64 12)
}

define internal ptr @v_showOverflowError(ptr %v__wild0) {
  call void @__free_recursive(ptr %v__wild0)
  ret ptr getelementptr inbounds (i8, ptr @.str.1, i64 12)
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
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.21 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v_r, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = getelementptr ptr, ptr %t6, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %case.default.10 [ i64 882564211, label %case.arm.882564211.11 i64 3768445577, label %case.arm.3768445577.16 ]
case.arm.882564211.11:
  %t12 = getelementptr ptr, ptr %t6, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v_showOverflowError(ptr %t13)
  %t15 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t14)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_r)
  ret ptr %t15
case.arm.3768445577.16:
  %t17 = getelementptr ptr, ptr %t6, i32 1
  %t18 = load ptr, ptr %t17
  call void @__inc_ref(ptr %t18)
  call void @__inc_ref(ptr %t18)
  %t19 = call ptr @v_showUnderflowError(ptr %t18)
  %t20 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t19)
  call void @__free_recursive(ptr %t18)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_r)
  ret ptr %t20
case.default.10:
  unreachable
case.arm.4.21:
  %t22 = getelementptr ptr, ptr %v_r, i32 1
  %t23 = load ptr, ptr %t22
  call void @__inc_ref(ptr %t23)
  call void @__inc_ref(ptr %t23)
  %t24 = call ptr @__showInt32(ptr %t23)
  %t25 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t24)
  call void @__free_recursive(ptr %t23)
  call void @__free_recursive(ptr %v_r)
  ret ptr %t25
case.default.3:
  unreachable
}

define internal ptr @v_main() {
  %t0 = call ptr @__alloc(i64 4, i32 0)
  store i32 6, ptr %t0
  %t1 = call ptr @__alloc(i64 4, i32 0)
  store i32 7, ptr %t1
  %t2 = call ptr @__mulInt32(ptr %t0, ptr %t1)
  %t3 = call ptr @v_render(ptr %t2)
  %t4 = getelementptr ptr, ptr %t3, i32 0
  %t5 = load ptr, ptr %t4
  %t6 = ptrtoint ptr %t5 to i64
  switch i64 %t6, label %case.default.7 [ i64 3, label %case.arm.3.9 i64 4, label %case.arm.4.17 ]
case.arm.3.9:
  %t11 = getelementptr ptr, ptr %t3, i32 1
  %t12 = load ptr, ptr %t11
  call void @__inc_ref(ptr %t12)
  %t13 = call ptr @__alloc(i64 16, i32 1)
  %t14 = inttoptr i64 3 to ptr
  %t15 = getelementptr ptr, ptr %t13, i32 0
  store ptr %t14, ptr %t15
  call void @__inc_ref(ptr %t12)
  %t16 = getelementptr ptr, ptr %t13, i32 1
  store ptr %t12, ptr %t16
  br label %case.end.3.10
case.end.3.10:
  br label %case.join.8
case.arm.4.17:
  %t19 = getelementptr ptr, ptr %t3, i32 1
  %t20 = load ptr, ptr %t19
  call void @__inc_ref(ptr %t20)
  %t21 = call ptr @__alloc(i64 4, i32 0)
  store i32 -6, ptr %t21
  %t22 = call ptr @__alloc(i64 4, i32 0)
  store i32 7, ptr %t22
  %t23 = call ptr @__mulInt32(ptr %t21, ptr %t22)
  %t24 = call ptr @v_render(ptr %t23)
  %t25 = getelementptr ptr, ptr %t24, i32 0
  %t26 = load ptr, ptr %t25
  %t27 = ptrtoint ptr %t26 to i64
  switch i64 %t27, label %case.default.28 [ i64 3, label %case.arm.3.30 i64 4, label %case.arm.4.38 ]
case.arm.3.30:
  %t32 = getelementptr ptr, ptr %t24, i32 1
  %t33 = load ptr, ptr %t32
  call void @__inc_ref(ptr %t33)
  %t34 = call ptr @__alloc(i64 16, i32 1)
  %t35 = inttoptr i64 3 to ptr
  %t36 = getelementptr ptr, ptr %t34, i32 0
  store ptr %t35, ptr %t36
  call void @__inc_ref(ptr %t33)
  %t37 = getelementptr ptr, ptr %t34, i32 1
  store ptr %t33, ptr %t37
  br label %case.end.3.31
case.end.3.31:
  br label %case.join.29
case.arm.4.38:
  %t40 = getelementptr ptr, ptr %t24, i32 1
  %t41 = load ptr, ptr %t40
  call void @__inc_ref(ptr %t41)
  %t42 = call ptr @__alloc(i64 4, i32 0)
  store i32 100000, ptr %t42
  %t43 = call ptr @__alloc(i64 4, i32 0)
  store i32 100000, ptr %t43
  %t44 = call ptr @__mulInt32(ptr %t42, ptr %t43)
  %t45 = call ptr @v_render(ptr %t44)
  %t46 = getelementptr ptr, ptr %t45, i32 0
  %t47 = load ptr, ptr %t46
  %t48 = ptrtoint ptr %t47 to i64
  switch i64 %t48, label %case.default.49 [ i64 3, label %case.arm.3.51 i64 4, label %case.arm.4.59 ]
case.arm.3.51:
  %t53 = getelementptr ptr, ptr %t45, i32 1
  %t54 = load ptr, ptr %t53
  call void @__inc_ref(ptr %t54)
  %t55 = call ptr @__alloc(i64 16, i32 1)
  %t56 = inttoptr i64 3 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  call void @__inc_ref(ptr %t54)
  %t58 = getelementptr ptr, ptr %t55, i32 1
  store ptr %t54, ptr %t58
  br label %case.end.3.52
case.end.3.52:
  br label %case.join.50
case.arm.4.59:
  %t61 = getelementptr ptr, ptr %t45, i32 1
  %t62 = load ptr, ptr %t61
  call void @__inc_ref(ptr %t62)
  %t63 = call ptr @__alloc(i64 4, i32 0)
  store i32 -100000, ptr %t63
  %t64 = call ptr @__alloc(i64 4, i32 0)
  store i32 100000, ptr %t64
  %t65 = call ptr @__mulInt32(ptr %t63, ptr %t64)
  %t66 = call ptr @v_render(ptr %t65)
  %t67 = getelementptr ptr, ptr %t66, i32 0
  %t68 = load ptr, ptr %t67
  %t69 = ptrtoint ptr %t68 to i64
  switch i64 %t69, label %case.default.70 [ i64 3, label %case.arm.3.72 i64 4, label %case.arm.4.80 ]
case.arm.3.72:
  %t74 = getelementptr ptr, ptr %t66, i32 1
  %t75 = load ptr, ptr %t74
  call void @__inc_ref(ptr %t75)
  %t76 = call ptr @__alloc(i64 16, i32 1)
  %t77 = inttoptr i64 3 to ptr
  %t78 = getelementptr ptr, ptr %t76, i32 0
  store ptr %t77, ptr %t78
  call void @__inc_ref(ptr %t75)
  %t79 = getelementptr ptr, ptr %t76, i32 1
  store ptr %t75, ptr %t79
  br label %case.end.3.73
case.end.3.73:
  br label %case.join.71
case.arm.4.80:
  %t82 = getelementptr ptr, ptr %t66, i32 1
  %t83 = load ptr, ptr %t82
  call void @__inc_ref(ptr %t83)
  %t84 = call ptr @v_minInt32()
  %t85 = call ptr @__alloc(i64 4, i32 0)
  store i32 -1, ptr %t85
  %t86 = call ptr @__mulInt32(ptr %t84, ptr %t85)
  %t87 = call ptr @v_render(ptr %t86)
  %t88 = getelementptr ptr, ptr %t87, i32 0
  %t89 = load ptr, ptr %t88
  %t90 = ptrtoint ptr %t89 to i64
  switch i64 %t90, label %case.default.91 [ i64 3, label %case.arm.3.93 i64 4, label %case.arm.4.101 ]
case.arm.3.93:
  %t95 = getelementptr ptr, ptr %t87, i32 1
  %t96 = load ptr, ptr %t95
  call void @__inc_ref(ptr %t96)
  %t97 = call ptr @__alloc(i64 16, i32 1)
  %t98 = inttoptr i64 3 to ptr
  %t99 = getelementptr ptr, ptr %t97, i32 0
  store ptr %t98, ptr %t99
  call void @__inc_ref(ptr %t96)
  %t100 = getelementptr ptr, ptr %t97, i32 1
  store ptr %t96, ptr %t100
  br label %case.end.3.94
case.end.3.94:
  br label %case.join.92
case.arm.4.101:
  %t103 = getelementptr ptr, ptr %t87, i32 1
  %t104 = load ptr, ptr %t103
  call void @__inc_ref(ptr %t104)
  %t105 = call ptr @v_minInt32()
  %t106 = call ptr @__alloc(i64 4, i32 0)
  store i32 1, ptr %t106
  %t107 = call ptr @__mulInt32(ptr %t105, ptr %t106)
  %t108 = call ptr @v_render(ptr %t107)
  %t109 = getelementptr ptr, ptr %t108, i32 0
  %t110 = load ptr, ptr %t109
  %t111 = ptrtoint ptr %t110 to i64
  switch i64 %t111, label %case.default.112 [ i64 3, label %case.arm.3.114 i64 4, label %case.arm.4.122 ]
case.arm.3.114:
  %t116 = getelementptr ptr, ptr %t108, i32 1
  %t117 = load ptr, ptr %t116
  call void @__inc_ref(ptr %t117)
  %t118 = call ptr @__alloc(i64 16, i32 1)
  %t119 = inttoptr i64 3 to ptr
  %t120 = getelementptr ptr, ptr %t118, i32 0
  store ptr %t119, ptr %t120
  call void @__inc_ref(ptr %t117)
  %t121 = getelementptr ptr, ptr %t118, i32 1
  store ptr %t117, ptr %t121
  br label %case.end.3.115
case.end.3.115:
  br label %case.join.113
case.arm.4.122:
  %t124 = getelementptr ptr, ptr %t108, i32 1
  %t125 = load ptr, ptr %t124
  call void @__inc_ref(ptr %t125)
  call void @__inc_ref(ptr %t20)
  %t126 = call ptr @__concat(ptr %t20, ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  %t127 = getelementptr ptr, ptr %t126, i32 0
  %t128 = load ptr, ptr %t127
  %t129 = ptrtoint ptr %t128 to i64
  switch i64 %t129, label %case.default.130 [ i64 3, label %case.arm.3.132 i64 4, label %case.arm.4.140 ]
case.arm.3.132:
  %t134 = getelementptr ptr, ptr %t126, i32 1
  %t135 = load ptr, ptr %t134
  call void @__inc_ref(ptr %t135)
  %t136 = call ptr @__alloc(i64 16, i32 1)
  %t137 = inttoptr i64 3 to ptr
  %t138 = getelementptr ptr, ptr %t136, i32 0
  store ptr %t137, ptr %t138
  call void @__inc_ref(ptr %t135)
  %t139 = getelementptr ptr, ptr %t136, i32 1
  store ptr %t135, ptr %t139
  br label %case.end.3.133
case.end.3.133:
  br label %case.join.131
case.arm.4.140:
  %t142 = getelementptr ptr, ptr %t126, i32 1
  %t143 = load ptr, ptr %t142
  call void @__inc_ref(ptr %t143)
  call void @__inc_ref(ptr %t143)
  call void @__inc_ref(ptr %t41)
  %t144 = call ptr @__concat(ptr %t143, ptr %t41)
  %t145 = getelementptr ptr, ptr %t144, i32 0
  %t146 = load ptr, ptr %t145
  %t147 = ptrtoint ptr %t146 to i64
  switch i64 %t147, label %case.default.148 [ i64 3, label %case.arm.3.150 i64 4, label %case.arm.4.158 ]
case.arm.3.150:
  %t152 = getelementptr ptr, ptr %t144, i32 1
  %t153 = load ptr, ptr %t152
  call void @__inc_ref(ptr %t153)
  %t154 = call ptr @__alloc(i64 16, i32 1)
  %t155 = inttoptr i64 3 to ptr
  %t156 = getelementptr ptr, ptr %t154, i32 0
  store ptr %t155, ptr %t156
  call void @__inc_ref(ptr %t153)
  %t157 = getelementptr ptr, ptr %t154, i32 1
  store ptr %t153, ptr %t157
  br label %case.end.3.151
case.end.3.151:
  br label %case.join.149
case.arm.4.158:
  %t160 = getelementptr ptr, ptr %t144, i32 1
  %t161 = load ptr, ptr %t160
  call void @__inc_ref(ptr %t161)
  call void @__inc_ref(ptr %t161)
  %t162 = call ptr @__concat(ptr %t161, ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  %t163 = getelementptr ptr, ptr %t162, i32 0
  %t164 = load ptr, ptr %t163
  %t165 = ptrtoint ptr %t164 to i64
  switch i64 %t165, label %case.default.166 [ i64 3, label %case.arm.3.168 i64 4, label %case.arm.4.176 ]
case.arm.3.168:
  %t170 = getelementptr ptr, ptr %t162, i32 1
  %t171 = load ptr, ptr %t170
  call void @__inc_ref(ptr %t171)
  %t172 = call ptr @__alloc(i64 16, i32 1)
  %t173 = inttoptr i64 3 to ptr
  %t174 = getelementptr ptr, ptr %t172, i32 0
  store ptr %t173, ptr %t174
  call void @__inc_ref(ptr %t171)
  %t175 = getelementptr ptr, ptr %t172, i32 1
  store ptr %t171, ptr %t175
  br label %case.end.3.169
case.end.3.169:
  br label %case.join.167
case.arm.4.176:
  %t178 = getelementptr ptr, ptr %t162, i32 1
  %t179 = load ptr, ptr %t178
  call void @__inc_ref(ptr %t179)
  call void @__inc_ref(ptr %t179)
  call void @__inc_ref(ptr %t62)
  %t180 = call ptr @__concat(ptr %t179, ptr %t62)
  %t181 = getelementptr ptr, ptr %t180, i32 0
  %t182 = load ptr, ptr %t181
  %t183 = ptrtoint ptr %t182 to i64
  switch i64 %t183, label %case.default.184 [ i64 3, label %case.arm.3.186 i64 4, label %case.arm.4.194 ]
case.arm.3.186:
  %t188 = getelementptr ptr, ptr %t180, i32 1
  %t189 = load ptr, ptr %t188
  call void @__inc_ref(ptr %t189)
  %t190 = call ptr @__alloc(i64 16, i32 1)
  %t191 = inttoptr i64 3 to ptr
  %t192 = getelementptr ptr, ptr %t190, i32 0
  store ptr %t191, ptr %t192
  call void @__inc_ref(ptr %t189)
  %t193 = getelementptr ptr, ptr %t190, i32 1
  store ptr %t189, ptr %t193
  br label %case.end.3.187
case.end.3.187:
  br label %case.join.185
case.arm.4.194:
  %t196 = getelementptr ptr, ptr %t180, i32 1
  %t197 = load ptr, ptr %t196
  call void @__inc_ref(ptr %t197)
  call void @__inc_ref(ptr %t197)
  %t198 = call ptr @__concat(ptr %t197, ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  %t199 = getelementptr ptr, ptr %t198, i32 0
  %t200 = load ptr, ptr %t199
  %t201 = ptrtoint ptr %t200 to i64
  switch i64 %t201, label %case.default.202 [ i64 3, label %case.arm.3.204 i64 4, label %case.arm.4.212 ]
case.arm.3.204:
  %t206 = getelementptr ptr, ptr %t198, i32 1
  %t207 = load ptr, ptr %t206
  call void @__inc_ref(ptr %t207)
  %t208 = call ptr @__alloc(i64 16, i32 1)
  %t209 = inttoptr i64 3 to ptr
  %t210 = getelementptr ptr, ptr %t208, i32 0
  store ptr %t209, ptr %t210
  call void @__inc_ref(ptr %t207)
  %t211 = getelementptr ptr, ptr %t208, i32 1
  store ptr %t207, ptr %t211
  br label %case.end.3.205
case.end.3.205:
  br label %case.join.203
case.arm.4.212:
  %t214 = getelementptr ptr, ptr %t198, i32 1
  %t215 = load ptr, ptr %t214
  call void @__inc_ref(ptr %t215)
  call void @__inc_ref(ptr %t215)
  call void @__inc_ref(ptr %t83)
  %t216 = call ptr @__concat(ptr %t215, ptr %t83)
  %t217 = getelementptr ptr, ptr %t216, i32 0
  %t218 = load ptr, ptr %t217
  %t219 = ptrtoint ptr %t218 to i64
  switch i64 %t219, label %case.default.220 [ i64 3, label %case.arm.3.222 i64 4, label %case.arm.4.230 ]
case.arm.3.222:
  %t224 = getelementptr ptr, ptr %t216, i32 1
  %t225 = load ptr, ptr %t224
  call void @__inc_ref(ptr %t225)
  %t226 = call ptr @__alloc(i64 16, i32 1)
  %t227 = inttoptr i64 3 to ptr
  %t228 = getelementptr ptr, ptr %t226, i32 0
  store ptr %t227, ptr %t228
  call void @__inc_ref(ptr %t225)
  %t229 = getelementptr ptr, ptr %t226, i32 1
  store ptr %t225, ptr %t229
  br label %case.end.3.223
case.end.3.223:
  br label %case.join.221
case.arm.4.230:
  %t232 = getelementptr ptr, ptr %t216, i32 1
  %t233 = load ptr, ptr %t232
  call void @__inc_ref(ptr %t233)
  call void @__inc_ref(ptr %t233)
  %t234 = call ptr @__concat(ptr %t233, ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  %t235 = getelementptr ptr, ptr %t234, i32 0
  %t236 = load ptr, ptr %t235
  %t237 = ptrtoint ptr %t236 to i64
  switch i64 %t237, label %case.default.238 [ i64 3, label %case.arm.3.240 i64 4, label %case.arm.4.248 ]
case.arm.3.240:
  %t242 = getelementptr ptr, ptr %t234, i32 1
  %t243 = load ptr, ptr %t242
  call void @__inc_ref(ptr %t243)
  %t244 = call ptr @__alloc(i64 16, i32 1)
  %t245 = inttoptr i64 3 to ptr
  %t246 = getelementptr ptr, ptr %t244, i32 0
  store ptr %t245, ptr %t246
  call void @__inc_ref(ptr %t243)
  %t247 = getelementptr ptr, ptr %t244, i32 1
  store ptr %t243, ptr %t247
  br label %case.end.3.241
case.end.3.241:
  br label %case.join.239
case.arm.4.248:
  %t250 = getelementptr ptr, ptr %t234, i32 1
  %t251 = load ptr, ptr %t250
  call void @__inc_ref(ptr %t251)
  call void @__inc_ref(ptr %t251)
  call void @__inc_ref(ptr %t104)
  %t252 = call ptr @__concat(ptr %t251, ptr %t104)
  %t253 = getelementptr ptr, ptr %t252, i32 0
  %t254 = load ptr, ptr %t253
  %t255 = ptrtoint ptr %t254 to i64
  switch i64 %t255, label %case.default.256 [ i64 3, label %case.arm.3.258 i64 4, label %case.arm.4.266 ]
case.arm.3.258:
  %t260 = getelementptr ptr, ptr %t252, i32 1
  %t261 = load ptr, ptr %t260
  call void @__inc_ref(ptr %t261)
  %t262 = call ptr @__alloc(i64 16, i32 1)
  %t263 = inttoptr i64 3 to ptr
  %t264 = getelementptr ptr, ptr %t262, i32 0
  store ptr %t263, ptr %t264
  call void @__inc_ref(ptr %t261)
  %t265 = getelementptr ptr, ptr %t262, i32 1
  store ptr %t261, ptr %t265
  br label %case.end.3.259
case.end.3.259:
  br label %case.join.257
case.arm.4.266:
  %t268 = getelementptr ptr, ptr %t252, i32 1
  %t269 = load ptr, ptr %t268
  call void @__inc_ref(ptr %t269)
  call void @__inc_ref(ptr %t269)
  %t270 = call ptr @__concat(ptr %t269, ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  %t271 = getelementptr ptr, ptr %t270, i32 0
  %t272 = load ptr, ptr %t271
  %t273 = ptrtoint ptr %t272 to i64
  switch i64 %t273, label %case.default.274 [ i64 3, label %case.arm.3.276 i64 4, label %case.arm.4.284 ]
case.arm.3.276:
  %t278 = getelementptr ptr, ptr %t270, i32 1
  %t279 = load ptr, ptr %t278
  call void @__inc_ref(ptr %t279)
  %t280 = call ptr @__alloc(i64 16, i32 1)
  %t281 = inttoptr i64 3 to ptr
  %t282 = getelementptr ptr, ptr %t280, i32 0
  store ptr %t281, ptr %t282
  call void @__inc_ref(ptr %t279)
  %t283 = getelementptr ptr, ptr %t280, i32 1
  store ptr %t279, ptr %t283
  br label %case.end.3.277
case.end.3.277:
  br label %case.join.275
case.arm.4.284:
  %t286 = getelementptr ptr, ptr %t270, i32 1
  %t287 = load ptr, ptr %t286
  call void @__inc_ref(ptr %t287)
  call void @__inc_ref(ptr %t287)
  call void @__inc_ref(ptr %t125)
  %t288 = call ptr @__concat(ptr %t287, ptr %t125)
  br label %case.end.4.285
case.end.4.285:
  br label %case.join.275
case.default.274:
  unreachable
case.join.275:
  %t289 = phi ptr [ %t280, %case.end.3.277 ], [ %t288, %case.end.4.285 ]
  call void @__free_recursive(ptr %t270)
  br label %case.end.4.267
case.end.4.267:
  br label %case.join.257
case.default.256:
  unreachable
case.join.257:
  %t290 = phi ptr [ %t262, %case.end.3.259 ], [ %t289, %case.end.4.267 ]
  call void @__free_recursive(ptr %t252)
  br label %case.end.4.249
case.end.4.249:
  br label %case.join.239
case.default.238:
  unreachable
case.join.239:
  %t291 = phi ptr [ %t244, %case.end.3.241 ], [ %t290, %case.end.4.249 ]
  call void @__free_recursive(ptr %t234)
  br label %case.end.4.231
case.end.4.231:
  br label %case.join.221
case.default.220:
  unreachable
case.join.221:
  %t292 = phi ptr [ %t226, %case.end.3.223 ], [ %t291, %case.end.4.231 ]
  call void @__free_recursive(ptr %t216)
  br label %case.end.4.213
case.end.4.213:
  br label %case.join.203
case.default.202:
  unreachable
case.join.203:
  %t293 = phi ptr [ %t208, %case.end.3.205 ], [ %t292, %case.end.4.213 ]
  call void @__free_recursive(ptr %t198)
  br label %case.end.4.195
case.end.4.195:
  br label %case.join.185
case.default.184:
  unreachable
case.join.185:
  %t294 = phi ptr [ %t190, %case.end.3.187 ], [ %t293, %case.end.4.195 ]
  call void @__free_recursive(ptr %t180)
  br label %case.end.4.177
case.end.4.177:
  br label %case.join.167
case.default.166:
  unreachable
case.join.167:
  %t295 = phi ptr [ %t172, %case.end.3.169 ], [ %t294, %case.end.4.177 ]
  call void @__free_recursive(ptr %t162)
  br label %case.end.4.159
case.end.4.159:
  br label %case.join.149
case.default.148:
  unreachable
case.join.149:
  %t296 = phi ptr [ %t154, %case.end.3.151 ], [ %t295, %case.end.4.159 ]
  call void @__free_recursive(ptr %t144)
  br label %case.end.4.141
case.end.4.141:
  br label %case.join.131
case.default.130:
  unreachable
case.join.131:
  %t297 = phi ptr [ %t136, %case.end.3.133 ], [ %t296, %case.end.4.141 ]
  call void @__free_recursive(ptr %t126)
  br label %case.end.4.123
case.end.4.123:
  br label %case.join.113
case.default.112:
  unreachable
case.join.113:
  %t298 = phi ptr [ %t118, %case.end.3.115 ], [ %t297, %case.end.4.123 ]
  call void @__free_recursive(ptr %t108)
  br label %case.end.4.102
case.end.4.102:
  br label %case.join.92
case.default.91:
  unreachable
case.join.92:
  %t299 = phi ptr [ %t97, %case.end.3.94 ], [ %t298, %case.end.4.102 ]
  call void @__free_recursive(ptr %t87)
  br label %case.end.4.81
case.end.4.81:
  br label %case.join.71
case.default.70:
  unreachable
case.join.71:
  %t300 = phi ptr [ %t76, %case.end.3.73 ], [ %t299, %case.end.4.81 ]
  call void @__free_recursive(ptr %t66)
  br label %case.end.4.60
case.end.4.60:
  br label %case.join.50
case.default.49:
  unreachable
case.join.50:
  %t301 = phi ptr [ %t55, %case.end.3.52 ], [ %t300, %case.end.4.60 ]
  call void @__free_recursive(ptr %t45)
  br label %case.end.4.39
case.end.4.39:
  br label %case.join.29
case.default.28:
  unreachable
case.join.29:
  %t302 = phi ptr [ %t34, %case.end.3.31 ], [ %t301, %case.end.4.39 ]
  call void @__free_recursive(ptr %t24)
  br label %case.end.4.18
case.end.4.18:
  br label %case.join.8
case.default.7:
  unreachable
case.join.8:
  %t303 = phi ptr [ %t13, %case.end.3.10 ], [ %t302, %case.end.4.18 ]
  call void @__free_recursive(ptr %t3)
  %t304 = call ptr @v__let_18(ptr %t303)
  ret ptr %t304
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
