; External C declarations
declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare ptr @memcpy(ptr, ptr, i64)
declare i64 @write(i32, ptr, i64)
declare i32 @snprintf(ptr, i64, ptr, ...)

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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"41" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"err" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"ok:" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"x" }
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"43" }
@.str.6 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"44" }

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


define internal ptr @__parseInt32(ptr %s) {
entry:
  %neg_alloca = alloca i32, align 4
  store i32 0, ptr %neg_alloca
  %i_alloca = alloca i64, align 8
  store i64 0, ptr %i_alloca
  %acc_alloca = alloca i64, align 8
  store i64 0, ptr %acc_alloca
  %len32 = load i32, ptr %s
  %len = zext i32 %len32 to i64
  %payload = getelementptr i8, ptr %s, i64 8
  %is_empty = icmp eq i64 %len, 0
  br i1 %is_empty, label %fail, label %check_sign
check_sign:
  %first = load i8, ptr %payload
  %first_i32 = zext i8 %first to i32
  %is_neg = icmp eq i32 %first_i32, 45
  br i1 %is_neg, label %sign_minus, label %loop_head
sign_minus:
  %is_lone = icmp eq i64 %len, 1
  br i1 %is_lone, label %fail, label %sign_setup
sign_setup:
  store i32 1, ptr %neg_alloca
  store i64 1, ptr %i_alloca
  br label %loop_head
loop_head:
  %i = load i64, ptr %i_alloca
  %acc = load i64, ptr %acc_alloca
  %cond = icmp ult i64 %i, %len
  br i1 %cond, label %body, label %after
body:
  %ptr_c = getelementptr i8, ptr %payload, i64 %i
  %c = load i8, ptr %ptr_c
  %c_i32 = zext i8 %c to i32
  %low = icmp ult i32 %c_i32, 48
  %high = icmp ugt i32 %c_i32, 57
  %bad = or i1 %low, %high
  br i1 %bad, label %fail, label %parse
parse:
  %d = sub i32 %c_i32, 48
  %d_i64 = zext i32 %d to i64
  %x10 = mul i64 %acc, 10
  %acc_next = add i64 %x10, %d_i64
  %big = icmp ugt i64 %acc_next, 2147483648
  br i1 %big, label %fail, label %body_end
body_end:
  store i64 %acc_next, ptr %acc_alloca
  %i_next = add i64 %i, 1
  store i64 %i_next, ptr %i_alloca
  br label %loop_head
after:
  %neg_val = load i32, ptr %neg_alloca
  %is_neg2 = icmp ne i32 %neg_val, 0
  br i1 %is_neg2, label %finalize_neg, label %finalize_pos
finalize_pos:
  %big_pos = icmp ugt i64 %acc, 2147483647
  br i1 %big_pos, label %fail, label %ok_pos
finalize_neg:
  %acc_neg = sub i64 0, %acc
  br label %ok_neg
ok_pos:
  %result_pos = trunc i64 %acc to i32
  br label %build_right
ok_neg:
  %result_neg = trunc i64 %acc_neg to i32
  br label %build_right
build_right:
  %result = phi i32 [ %result_pos, %ok_pos ], [ %result_neg, %ok_neg ]
  %box = call ptr @__alloc(i64 4, i32 0)
  store i32 %result, ptr %box
  %right = call ptr @__alloc(i64 16, i32 1)
  %right_tag = inttoptr i64 4 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %box, ptr %right_f
  br label %join
fail:
  %pe = call ptr @__alloc(i64 8, i32 0)
  %pe_tag = inttoptr i64 22 to ptr
  store ptr %pe_tag, ptr %pe
  %left = call ptr @__alloc(i64 16, i32 1)
  %left_tag = inttoptr i64 3 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %pe, ptr %left_f
  br label %join
join:
  %res = phi ptr [ %right, %build_right ], [ %left, %fail ]
  call void @__free_recursive(ptr %s)
  ret ptr %res
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
  %v_$inl16$scrut.jslot = alloca ptr
  %t0 = call ptr @__parseInt32(ptr getelementptr inbounds (i8, ptr @.str.0, i64 12))
  %t3 = getelementptr ptr, ptr %t0, i32 0
  %t4 = load ptr, ptr %t3
  %t5 = ptrtoint ptr %t4 to i64
  switch i64 %t5, label %case.default.6 [ i64 3, label %case.arm.3.8 i64 4, label %case.arm.4.14 ]
case.arm.3.8:
  %t10 = call ptr @__alloc(i64 16, i32 1)
  %t11 = inttoptr i64 4 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  %t13 = getelementptr ptr, ptr %t10, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t13
  br label %case.end.3.9
case.end.3.9:
  br label %case.join.7
case.arm.4.14:
  %t16 = getelementptr ptr, ptr %t0, i32 1
  %t17 = load ptr, ptr %t16
  call void @__inc_ref(ptr %t17)
  %t18 = call ptr @__showInt32(ptr %t17)
  %t19 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t18)
  br label %case.end.4.15
case.end.4.15:
  br label %case.join.7
case.default.6:
  unreachable
case.join.7:
  %t20 = phi ptr [ %t10, %case.end.3.9 ], [ %t19, %case.end.4.15 ]
  %t21 = getelementptr ptr, ptr %t20, i32 0
  %t22 = load ptr, ptr %t21
  %t23 = ptrtoint ptr %t22 to i64
  switch i64 %t23, label %join.case.default.24 [ i64 3, label %join.case.arm.3.25 i64 4, label %join.case.arm.4.39 ]
join.case.arm.3.25:
  %t26 = call ptr @__alloc(i64 24, i32 2)
  %t27 = inttoptr i64 7 to ptr
  %t28 = getelementptr ptr, ptr %t26, i32 0
  store ptr %t27, ptr %t28
  %t29 = getelementptr ptr, ptr %t26, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t29
  %t30 = call ptr @__alloc(i64 16, i32 1)
  %t31 = inttoptr i64 5 to ptr
  %t32 = getelementptr ptr, ptr %t30, i32 0
  store ptr %t31, ptr %t32
  %t33 = call ptr @__alloc(i64 8, i32 0)
  %t34 = inttoptr i64 0 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = getelementptr ptr, ptr %t30, i32 1
  store ptr %t33, ptr %t36
  %t37 = getelementptr ptr, ptr %t26, i32 2
  store ptr %t30, ptr %t37
  call void @__free_recursive(ptr %t20)
  br label %join.val.38
join.val.38:
  br label %join.after.2
join.case.arm.4.39:
  %t40 = getelementptr ptr, ptr %t20, i32 1
  %t41 = load ptr, ptr %t40
  call void @__inc_ref(ptr %t41)
  %t42 = call ptr @__parseInt32(ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  %t43 = getelementptr ptr, ptr %t42, i32 0
  %t44 = load ptr, ptr %t43
  %t45 = ptrtoint ptr %t44 to i64
  switch i64 %t45, label %case.default.46 [ i64 3, label %case.arm.3.48 i64 4, label %case.arm.4.54 ]
case.arm.3.48:
  %t50 = call ptr @__alloc(i64 16, i32 1)
  %t51 = inttoptr i64 4 to ptr
  %t52 = getelementptr ptr, ptr %t50, i32 0
  store ptr %t51, ptr %t52
  %t53 = getelementptr ptr, ptr %t50, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t53
  br label %case.end.3.49
case.end.3.49:
  br label %case.join.47
case.arm.4.54:
  %t56 = getelementptr ptr, ptr %t42, i32 1
  %t57 = load ptr, ptr %t56
  call void @__inc_ref(ptr %t57)
  %t58 = call ptr @__showInt32(ptr %t57)
  %t59 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t58)
  br label %case.end.4.55
case.end.4.55:
  br label %case.join.47
case.default.46:
  unreachable
case.join.47:
  %t60 = phi ptr [ %t50, %case.end.3.49 ], [ %t59, %case.end.4.55 ]
  %t61 = getelementptr ptr, ptr %t60, i32 0
  %t62 = load ptr, ptr %t61
  %t63 = ptrtoint ptr %t62 to i64
  switch i64 %t63, label %case.default.64 [ i64 3, label %case.arm.3.66 i64 4, label %case.arm.4.74 ]
case.arm.3.66:
  %t68 = getelementptr ptr, ptr %t60, i32 1
  %t69 = load ptr, ptr %t68
  call void @__inc_ref(ptr %t69)
  %t70 = call ptr @__alloc(i64 16, i32 1)
  %t71 = inttoptr i64 3 to ptr
  %t72 = getelementptr ptr, ptr %t70, i32 0
  store ptr %t71, ptr %t72
  call void @__inc_ref(ptr %t69)
  %t73 = getelementptr ptr, ptr %t70, i32 1
  store ptr %t69, ptr %t73
  br label %case.end.3.67
case.end.3.67:
  br label %case.join.65
case.arm.4.74:
  %t76 = getelementptr ptr, ptr %t60, i32 1
  %t77 = load ptr, ptr %t76
  call void @__inc_ref(ptr %t77)
  %t78 = call ptr @__parseInt32(ptr getelementptr inbounds (i8, ptr @.str.5, i64 12))
  %t79 = getelementptr ptr, ptr %t78, i32 0
  %t80 = load ptr, ptr %t79
  %t81 = ptrtoint ptr %t80 to i64
  switch i64 %t81, label %case.default.82 [ i64 3, label %case.arm.3.84 i64 4, label %case.arm.4.90 ]
case.arm.3.84:
  %t86 = call ptr @__alloc(i64 16, i32 1)
  %t87 = inttoptr i64 4 to ptr
  %t88 = getelementptr ptr, ptr %t86, i32 0
  store ptr %t87, ptr %t88
  %t89 = getelementptr ptr, ptr %t86, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t89
  br label %case.end.3.85
case.end.3.85:
  br label %case.join.83
case.arm.4.90:
  %t92 = getelementptr ptr, ptr %t78, i32 1
  %t93 = load ptr, ptr %t92
  call void @__inc_ref(ptr %t93)
  %t94 = call ptr @__showInt32(ptr %t93)
  %t95 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t94)
  br label %case.end.4.91
case.end.4.91:
  br label %case.join.83
case.default.82:
  unreachable
case.join.83:
  %t96 = phi ptr [ %t86, %case.end.3.85 ], [ %t95, %case.end.4.91 ]
  %t97 = getelementptr ptr, ptr %t96, i32 0
  %t98 = load ptr, ptr %t97
  %t99 = ptrtoint ptr %t98 to i64
  switch i64 %t99, label %case.default.100 [ i64 3, label %case.arm.3.102 i64 4, label %case.arm.4.110 ]
case.arm.3.102:
  %t104 = getelementptr ptr, ptr %t96, i32 1
  %t105 = load ptr, ptr %t104
  call void @__inc_ref(ptr %t105)
  %t106 = call ptr @__alloc(i64 16, i32 1)
  %t107 = inttoptr i64 3 to ptr
  %t108 = getelementptr ptr, ptr %t106, i32 0
  store ptr %t107, ptr %t108
  call void @__inc_ref(ptr %t105)
  %t109 = getelementptr ptr, ptr %t106, i32 1
  store ptr %t105, ptr %t109
  br label %case.end.3.103
case.end.3.103:
  br label %case.join.101
case.arm.4.110:
  %t112 = getelementptr ptr, ptr %t96, i32 1
  %t113 = load ptr, ptr %t112
  call void @__inc_ref(ptr %t113)
  %t114 = call ptr @__parseInt32(ptr getelementptr inbounds (i8, ptr @.str.6, i64 12))
  %t115 = getelementptr ptr, ptr %t114, i32 0
  %t116 = load ptr, ptr %t115
  %t117 = ptrtoint ptr %t116 to i64
  switch i64 %t117, label %case.default.118 [ i64 3, label %case.arm.3.120 i64 4, label %case.arm.4.126 ]
case.arm.3.120:
  %t122 = call ptr @__alloc(i64 16, i32 1)
  %t123 = inttoptr i64 4 to ptr
  %t124 = getelementptr ptr, ptr %t122, i32 0
  store ptr %t123, ptr %t124
  %t125 = getelementptr ptr, ptr %t122, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t125
  br label %case.end.3.121
case.end.3.121:
  br label %case.join.119
case.arm.4.126:
  %t128 = getelementptr ptr, ptr %t114, i32 1
  %t129 = load ptr, ptr %t128
  call void @__inc_ref(ptr %t129)
  %t130 = call ptr @__showInt32(ptr %t129)
  %t131 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t130)
  br label %case.end.4.127
case.end.4.127:
  br label %case.join.119
case.default.118:
  unreachable
case.join.119:
  %t132 = phi ptr [ %t122, %case.end.3.121 ], [ %t131, %case.end.4.127 ]
  %t133 = getelementptr ptr, ptr %t132, i32 0
  %t134 = load ptr, ptr %t133
  %t135 = ptrtoint ptr %t134 to i64
  switch i64 %t135, label %case.default.136 [ i64 3, label %case.arm.3.138 i64 4, label %case.arm.4.146 ]
case.arm.3.138:
  %t140 = getelementptr ptr, ptr %t132, i32 1
  %t141 = load ptr, ptr %t140
  call void @__inc_ref(ptr %t141)
  %t142 = call ptr @__alloc(i64 16, i32 1)
  %t143 = inttoptr i64 3 to ptr
  %t144 = getelementptr ptr, ptr %t142, i32 0
  store ptr %t143, ptr %t144
  call void @__inc_ref(ptr %t141)
  %t145 = getelementptr ptr, ptr %t142, i32 1
  store ptr %t141, ptr %t145
  br label %case.end.3.139
case.end.3.139:
  br label %case.join.137
case.arm.4.146:
  %t148 = getelementptr ptr, ptr %t132, i32 1
  %t149 = load ptr, ptr %t148
  call void @__inc_ref(ptr %t149)
  call void @__inc_ref(ptr %t41)
  call void @__inc_ref(ptr %t77)
  %t150 = call ptr @__concat(ptr %t41, ptr %t77)
  %t151 = getelementptr ptr, ptr %t150, i32 0
  %t152 = load ptr, ptr %t151
  %t153 = ptrtoint ptr %t152 to i64
  switch i64 %t153, label %case.default.154 [ i64 3, label %case.arm.3.156 i64 4, label %case.arm.4.164 ]
case.arm.3.156:
  %t158 = getelementptr ptr, ptr %t150, i32 1
  %t159 = load ptr, ptr %t158
  call void @__inc_ref(ptr %t159)
  %t160 = call ptr @__alloc(i64 16, i32 1)
  %t161 = inttoptr i64 3 to ptr
  %t162 = getelementptr ptr, ptr %t160, i32 0
  store ptr %t161, ptr %t162
  call void @__inc_ref(ptr %t159)
  %t163 = getelementptr ptr, ptr %t160, i32 1
  store ptr %t159, ptr %t163
  br label %case.end.3.157
case.end.3.157:
  br label %case.join.155
case.arm.4.164:
  %t166 = getelementptr ptr, ptr %t150, i32 1
  %t167 = load ptr, ptr %t166
  call void @__inc_ref(ptr %t167)
  call void @__inc_ref(ptr %t167)
  call void @__inc_ref(ptr %t113)
  %t168 = call ptr @__concat(ptr %t167, ptr %t113)
  %t169 = getelementptr ptr, ptr %t168, i32 0
  %t170 = load ptr, ptr %t169
  %t171 = ptrtoint ptr %t170 to i64
  switch i64 %t171, label %case.default.172 [ i64 3, label %case.arm.3.174 i64 4, label %case.arm.4.182 ]
case.arm.3.174:
  %t176 = getelementptr ptr, ptr %t168, i32 1
  %t177 = load ptr, ptr %t176
  call void @__inc_ref(ptr %t177)
  %t178 = call ptr @__alloc(i64 16, i32 1)
  %t179 = inttoptr i64 3 to ptr
  %t180 = getelementptr ptr, ptr %t178, i32 0
  store ptr %t179, ptr %t180
  call void @__inc_ref(ptr %t177)
  %t181 = getelementptr ptr, ptr %t178, i32 1
  store ptr %t177, ptr %t181
  br label %case.end.3.175
case.end.3.175:
  br label %case.join.173
case.arm.4.182:
  %t184 = getelementptr ptr, ptr %t168, i32 1
  %t185 = load ptr, ptr %t184
  call void @__inc_ref(ptr %t185)
  call void @__inc_ref(ptr %t185)
  call void @__inc_ref(ptr %t149)
  %t186 = call ptr @__concat(ptr %t185, ptr %t149)
  %t187 = getelementptr ptr, ptr %t186, i32 0
  %t188 = load ptr, ptr %t187
  %t189 = ptrtoint ptr %t188 to i64
  switch i64 %t189, label %case.default.190 [ i64 3, label %case.arm.3.192 i64 4, label %case.arm.4.200 ]
case.arm.3.192:
  %t194 = getelementptr ptr, ptr %t186, i32 1
  %t195 = load ptr, ptr %t194
  call void @__inc_ref(ptr %t195)
  %t196 = call ptr @__alloc(i64 16, i32 1)
  %t197 = inttoptr i64 3 to ptr
  %t198 = getelementptr ptr, ptr %t196, i32 0
  store ptr %t197, ptr %t198
  call void @__inc_ref(ptr %t195)
  %t199 = getelementptr ptr, ptr %t196, i32 1
  store ptr %t195, ptr %t199
  br label %case.end.3.193
case.end.3.193:
  br label %case.join.191
case.arm.4.200:
  %t202 = getelementptr ptr, ptr %t186, i32 1
  %t203 = load ptr, ptr %t202
  call void @__inc_ref(ptr %t203)
  %t204 = call ptr @__alloc(i64 16, i32 1)
  %t205 = inttoptr i64 4 to ptr
  %t206 = getelementptr ptr, ptr %t204, i32 0
  store ptr %t205, ptr %t206
  call void @__inc_ref(ptr %t203)
  %t207 = getelementptr ptr, ptr %t204, i32 1
  store ptr %t203, ptr %t207
  br label %case.end.4.201
case.end.4.201:
  br label %case.join.191
case.default.190:
  unreachable
case.join.191:
  %t208 = phi ptr [ %t196, %case.end.3.193 ], [ %t204, %case.end.4.201 ]
  call void @__free_recursive(ptr %t186)
  br label %case.end.4.183
case.end.4.183:
  br label %case.join.173
case.default.172:
  unreachable
case.join.173:
  %t209 = phi ptr [ %t178, %case.end.3.175 ], [ %t208, %case.end.4.183 ]
  call void @__free_recursive(ptr %t168)
  br label %case.end.4.165
case.end.4.165:
  br label %case.join.155
case.default.154:
  unreachable
case.join.155:
  %t210 = phi ptr [ %t160, %case.end.3.157 ], [ %t209, %case.end.4.165 ]
  call void @__free_recursive(ptr %t150)
  br label %case.end.4.147
case.end.4.147:
  br label %case.join.137
case.default.136:
  unreachable
case.join.137:
  %t211 = phi ptr [ %t142, %case.end.3.139 ], [ %t210, %case.end.4.147 ]
  call void @__free_recursive(ptr %t132)
  call void @__free_recursive(ptr %t114)
  br label %case.end.4.111
case.end.4.111:
  br label %case.join.101
case.default.100:
  unreachable
case.join.101:
  %t212 = phi ptr [ %t106, %case.end.3.103 ], [ %t211, %case.end.4.111 ]
  call void @__free_recursive(ptr %t96)
  call void @__free_recursive(ptr %t78)
  br label %case.end.4.75
case.end.4.75:
  br label %case.join.65
case.default.64:
  unreachable
case.join.65:
  %t213 = phi ptr [ %t70, %case.end.3.67 ], [ %t212, %case.end.4.75 ]
  call void @__free_recursive(ptr %t60)
  call void @__free_recursive(ptr %t42)
  call void @__free_recursive(ptr %t20)
  store ptr %t213, ptr %v_$inl16$scrut.jslot
  br label %join.1
join.case.default.24:
  unreachable
join.1:
  %t214 = load ptr, ptr %v_$inl16$scrut.jslot
  %t215 = getelementptr ptr, ptr %t214, i32 0
  %t216 = load ptr, ptr %t215
  %t217 = ptrtoint ptr %t216 to i64
  switch i64 %t217, label %case.default.218 [ i64 3, label %case.arm.3.220 i64 4, label %case.arm.4.234 ]
case.arm.3.220:
  %t222 = call ptr @__alloc(i64 24, i32 2)
  %t223 = inttoptr i64 7 to ptr
  %t224 = getelementptr ptr, ptr %t222, i32 0
  store ptr %t223, ptr %t224
  %t225 = getelementptr ptr, ptr %t222, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t225
  %t226 = call ptr @__alloc(i64 16, i32 1)
  %t227 = inttoptr i64 5 to ptr
  %t228 = getelementptr ptr, ptr %t226, i32 0
  store ptr %t227, ptr %t228
  %t229 = call ptr @__alloc(i64 8, i32 0)
  %t230 = inttoptr i64 0 to ptr
  %t231 = getelementptr ptr, ptr %t229, i32 0
  store ptr %t230, ptr %t231
  %t232 = getelementptr ptr, ptr %t226, i32 1
  store ptr %t229, ptr %t232
  %t233 = getelementptr ptr, ptr %t222, i32 2
  store ptr %t226, ptr %t233
  br label %case.end.3.221
case.end.3.221:
  br label %case.join.219
case.arm.4.234:
  %t236 = call ptr @__alloc(i64 24, i32 2)
  %t237 = inttoptr i64 7 to ptr
  %t238 = getelementptr ptr, ptr %t236, i32 0
  store ptr %t237, ptr %t238
  %t239 = getelementptr ptr, ptr %t214, i32 1
  %t240 = load ptr, ptr %t239
  call void @__inc_ref(ptr %t240)
  %t241 = getelementptr ptr, ptr %t236, i32 1
  store ptr %t240, ptr %t241
  %t242 = call ptr @__alloc(i64 16, i32 1)
  %t243 = inttoptr i64 5 to ptr
  %t244 = getelementptr ptr, ptr %t242, i32 0
  store ptr %t243, ptr %t244
  %t245 = call ptr @__alloc(i64 8, i32 0)
  %t246 = inttoptr i64 0 to ptr
  %t247 = getelementptr ptr, ptr %t245, i32 0
  store ptr %t246, ptr %t247
  %t248 = getelementptr ptr, ptr %t242, i32 1
  store ptr %t245, ptr %t248
  %t249 = getelementptr ptr, ptr %t236, i32 2
  store ptr %t242, ptr %t249
  br label %case.end.4.235
case.end.4.235:
  br label %case.join.219
case.default.218:
  unreachable
case.join.219:
  %t250 = phi ptr [ %t222, %case.end.3.221 ], [ %t236, %case.end.4.235 ]
  call void @__free_recursive(ptr %t214)
  br label %join.end.251
join.end.251:
  br label %join.after.2
join.after.2:
  %t252 = phi ptr [ %t26, %join.val.38 ], [ %t250, %join.end.251 ]
  call void @__free_recursive(ptr %t0)
  ret ptr %t252
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
