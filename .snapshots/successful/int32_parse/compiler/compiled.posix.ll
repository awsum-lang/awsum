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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"42" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"err" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"ok:" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"-42" }
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"0" }
@.str.6 = private unnamed_addr constant {i32, i32, i32, i32, i32, [10 x i8]} { i32 0, i32 0, i32 0, i32 10, i32 10, [10 x i8] c"2147483647" }
@.str.7 = private unnamed_addr constant {i32, i32, i32, i32, i32, [11 x i8]} { i32 0, i32 0, i32 0, i32 11, i32 11, [11 x i8] c"-2147483648" }
@.str.8 = private unnamed_addr constant {i32, i32, i32, i32, i32, [10 x i8]} { i32 0, i32 0, i32 0, i32 10, i32 10, [10 x i8] c"2147483648" }
@.str.9 = private unnamed_addr constant {i32, i32, i32, i32, i32, [11 x i8]} { i32 0, i32 0, i32 0, i32 11, i32 11, [11 x i8] c"-2147483649" }
@.str.10 = private unnamed_addr constant {i32, i32, i32, i32, i32, [0 x i8]} { i32 0, i32 0, i32 0, i32 0, i32 0, [0 x i8] zeroinitializer }
@.str.11 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"-" }
@.str.12 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"+42" }
@.str.13 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c" 42" }
@.str.14 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"12abc" }
@.str.15 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c", " }

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
  %v__inl40_scrut.jslot = alloca ptr
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
  %t150 = call ptr @__parseInt32(ptr getelementptr inbounds (i8, ptr @.str.7, i64 12))
  %t151 = getelementptr ptr, ptr %t150, i32 0
  %t152 = load ptr, ptr %t151
  %t153 = ptrtoint ptr %t152 to i64
  switch i64 %t153, label %case.default.154 [ i64 3, label %case.arm.3.156 i64 4, label %case.arm.4.162 ]
case.arm.3.156:
  %t158 = call ptr @__alloc(i64 16, i32 1)
  %t159 = inttoptr i64 4 to ptr
  %t160 = getelementptr ptr, ptr %t158, i32 0
  store ptr %t159, ptr %t160
  %t161 = getelementptr ptr, ptr %t158, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t161
  br label %case.end.3.157
case.end.3.157:
  br label %case.join.155
case.arm.4.162:
  %t164 = getelementptr ptr, ptr %t150, i32 1
  %t165 = load ptr, ptr %t164
  call void @__inc_ref(ptr %t165)
  %t166 = call ptr @__showInt32(ptr %t165)
  %t167 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t166)
  br label %case.end.4.163
case.end.4.163:
  br label %case.join.155
case.default.154:
  unreachable
case.join.155:
  %t168 = phi ptr [ %t158, %case.end.3.157 ], [ %t167, %case.end.4.163 ]
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
  %t186 = call ptr @__parseInt32(ptr getelementptr inbounds (i8, ptr @.str.8, i64 12))
  %t187 = getelementptr ptr, ptr %t186, i32 0
  %t188 = load ptr, ptr %t187
  %t189 = ptrtoint ptr %t188 to i64
  switch i64 %t189, label %case.default.190 [ i64 3, label %case.arm.3.192 i64 4, label %case.arm.4.198 ]
case.arm.3.192:
  %t194 = call ptr @__alloc(i64 16, i32 1)
  %t195 = inttoptr i64 4 to ptr
  %t196 = getelementptr ptr, ptr %t194, i32 0
  store ptr %t195, ptr %t196
  %t197 = getelementptr ptr, ptr %t194, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t197
  br label %case.end.3.193
case.end.3.193:
  br label %case.join.191
case.arm.4.198:
  %t200 = getelementptr ptr, ptr %t186, i32 1
  %t201 = load ptr, ptr %t200
  call void @__inc_ref(ptr %t201)
  %t202 = call ptr @__showInt32(ptr %t201)
  %t203 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t202)
  br label %case.end.4.199
case.end.4.199:
  br label %case.join.191
case.default.190:
  unreachable
case.join.191:
  %t204 = phi ptr [ %t194, %case.end.3.193 ], [ %t203, %case.end.4.199 ]
  %t205 = getelementptr ptr, ptr %t204, i32 0
  %t206 = load ptr, ptr %t205
  %t207 = ptrtoint ptr %t206 to i64
  switch i64 %t207, label %case.default.208 [ i64 3, label %case.arm.3.210 i64 4, label %case.arm.4.218 ]
case.arm.3.210:
  %t212 = getelementptr ptr, ptr %t204, i32 1
  %t213 = load ptr, ptr %t212
  call void @__inc_ref(ptr %t213)
  %t214 = call ptr @__alloc(i64 16, i32 1)
  %t215 = inttoptr i64 3 to ptr
  %t216 = getelementptr ptr, ptr %t214, i32 0
  store ptr %t215, ptr %t216
  call void @__inc_ref(ptr %t213)
  %t217 = getelementptr ptr, ptr %t214, i32 1
  store ptr %t213, ptr %t217
  br label %case.end.3.211
case.end.3.211:
  br label %case.join.209
case.arm.4.218:
  %t220 = getelementptr ptr, ptr %t204, i32 1
  %t221 = load ptr, ptr %t220
  call void @__inc_ref(ptr %t221)
  %t222 = call ptr @__parseInt32(ptr getelementptr inbounds (i8, ptr @.str.9, i64 12))
  %t223 = getelementptr ptr, ptr %t222, i32 0
  %t224 = load ptr, ptr %t223
  %t225 = ptrtoint ptr %t224 to i64
  switch i64 %t225, label %case.default.226 [ i64 3, label %case.arm.3.228 i64 4, label %case.arm.4.234 ]
case.arm.3.228:
  %t230 = call ptr @__alloc(i64 16, i32 1)
  %t231 = inttoptr i64 4 to ptr
  %t232 = getelementptr ptr, ptr %t230, i32 0
  store ptr %t231, ptr %t232
  %t233 = getelementptr ptr, ptr %t230, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t233
  br label %case.end.3.229
case.end.3.229:
  br label %case.join.227
case.arm.4.234:
  %t236 = getelementptr ptr, ptr %t222, i32 1
  %t237 = load ptr, ptr %t236
  call void @__inc_ref(ptr %t237)
  %t238 = call ptr @__showInt32(ptr %t237)
  %t239 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t238)
  br label %case.end.4.235
case.end.4.235:
  br label %case.join.227
case.default.226:
  unreachable
case.join.227:
  %t240 = phi ptr [ %t230, %case.end.3.229 ], [ %t239, %case.end.4.235 ]
  %t241 = getelementptr ptr, ptr %t240, i32 0
  %t242 = load ptr, ptr %t241
  %t243 = ptrtoint ptr %t242 to i64
  switch i64 %t243, label %case.default.244 [ i64 3, label %case.arm.3.246 i64 4, label %case.arm.4.254 ]
case.arm.3.246:
  %t248 = getelementptr ptr, ptr %t240, i32 1
  %t249 = load ptr, ptr %t248
  call void @__inc_ref(ptr %t249)
  %t250 = call ptr @__alloc(i64 16, i32 1)
  %t251 = inttoptr i64 3 to ptr
  %t252 = getelementptr ptr, ptr %t250, i32 0
  store ptr %t251, ptr %t252
  call void @__inc_ref(ptr %t249)
  %t253 = getelementptr ptr, ptr %t250, i32 1
  store ptr %t249, ptr %t253
  br label %case.end.3.247
case.end.3.247:
  br label %case.join.245
case.arm.4.254:
  %t256 = getelementptr ptr, ptr %t240, i32 1
  %t257 = load ptr, ptr %t256
  call void @__inc_ref(ptr %t257)
  %t258 = call ptr @__parseInt32(ptr getelementptr inbounds (i8, ptr @.str.10, i64 12))
  %t259 = getelementptr ptr, ptr %t258, i32 0
  %t260 = load ptr, ptr %t259
  %t261 = ptrtoint ptr %t260 to i64
  switch i64 %t261, label %case.default.262 [ i64 3, label %case.arm.3.264 i64 4, label %case.arm.4.270 ]
case.arm.3.264:
  %t266 = call ptr @__alloc(i64 16, i32 1)
  %t267 = inttoptr i64 4 to ptr
  %t268 = getelementptr ptr, ptr %t266, i32 0
  store ptr %t267, ptr %t268
  %t269 = getelementptr ptr, ptr %t266, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t269
  br label %case.end.3.265
case.end.3.265:
  br label %case.join.263
case.arm.4.270:
  %t272 = getelementptr ptr, ptr %t258, i32 1
  %t273 = load ptr, ptr %t272
  call void @__inc_ref(ptr %t273)
  %t274 = call ptr @__showInt32(ptr %t273)
  %t275 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t274)
  br label %case.end.4.271
case.end.4.271:
  br label %case.join.263
case.default.262:
  unreachable
case.join.263:
  %t276 = phi ptr [ %t266, %case.end.3.265 ], [ %t275, %case.end.4.271 ]
  %t277 = getelementptr ptr, ptr %t276, i32 0
  %t278 = load ptr, ptr %t277
  %t279 = ptrtoint ptr %t278 to i64
  switch i64 %t279, label %case.default.280 [ i64 3, label %case.arm.3.282 i64 4, label %case.arm.4.290 ]
case.arm.3.282:
  %t284 = getelementptr ptr, ptr %t276, i32 1
  %t285 = load ptr, ptr %t284
  call void @__inc_ref(ptr %t285)
  %t286 = call ptr @__alloc(i64 16, i32 1)
  %t287 = inttoptr i64 3 to ptr
  %t288 = getelementptr ptr, ptr %t286, i32 0
  store ptr %t287, ptr %t288
  call void @__inc_ref(ptr %t285)
  %t289 = getelementptr ptr, ptr %t286, i32 1
  store ptr %t285, ptr %t289
  br label %case.end.3.283
case.end.3.283:
  br label %case.join.281
case.arm.4.290:
  %t292 = getelementptr ptr, ptr %t276, i32 1
  %t293 = load ptr, ptr %t292
  call void @__inc_ref(ptr %t293)
  %t294 = call ptr @__parseInt32(ptr getelementptr inbounds (i8, ptr @.str.11, i64 12))
  %t295 = getelementptr ptr, ptr %t294, i32 0
  %t296 = load ptr, ptr %t295
  %t297 = ptrtoint ptr %t296 to i64
  switch i64 %t297, label %case.default.298 [ i64 3, label %case.arm.3.300 i64 4, label %case.arm.4.306 ]
case.arm.3.300:
  %t302 = call ptr @__alloc(i64 16, i32 1)
  %t303 = inttoptr i64 4 to ptr
  %t304 = getelementptr ptr, ptr %t302, i32 0
  store ptr %t303, ptr %t304
  %t305 = getelementptr ptr, ptr %t302, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t305
  br label %case.end.3.301
case.end.3.301:
  br label %case.join.299
case.arm.4.306:
  %t308 = getelementptr ptr, ptr %t294, i32 1
  %t309 = load ptr, ptr %t308
  call void @__inc_ref(ptr %t309)
  %t310 = call ptr @__showInt32(ptr %t309)
  %t311 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t310)
  br label %case.end.4.307
case.end.4.307:
  br label %case.join.299
case.default.298:
  unreachable
case.join.299:
  %t312 = phi ptr [ %t302, %case.end.3.301 ], [ %t311, %case.end.4.307 ]
  %t313 = getelementptr ptr, ptr %t312, i32 0
  %t314 = load ptr, ptr %t313
  %t315 = ptrtoint ptr %t314 to i64
  switch i64 %t315, label %case.default.316 [ i64 3, label %case.arm.3.318 i64 4, label %case.arm.4.326 ]
case.arm.3.318:
  %t320 = getelementptr ptr, ptr %t312, i32 1
  %t321 = load ptr, ptr %t320
  call void @__inc_ref(ptr %t321)
  %t322 = call ptr @__alloc(i64 16, i32 1)
  %t323 = inttoptr i64 3 to ptr
  %t324 = getelementptr ptr, ptr %t322, i32 0
  store ptr %t323, ptr %t324
  call void @__inc_ref(ptr %t321)
  %t325 = getelementptr ptr, ptr %t322, i32 1
  store ptr %t321, ptr %t325
  br label %case.end.3.319
case.end.3.319:
  br label %case.join.317
case.arm.4.326:
  %t328 = getelementptr ptr, ptr %t312, i32 1
  %t329 = load ptr, ptr %t328
  call void @__inc_ref(ptr %t329)
  %t330 = call ptr @__parseInt32(ptr getelementptr inbounds (i8, ptr @.str.12, i64 12))
  %t331 = getelementptr ptr, ptr %t330, i32 0
  %t332 = load ptr, ptr %t331
  %t333 = ptrtoint ptr %t332 to i64
  switch i64 %t333, label %case.default.334 [ i64 3, label %case.arm.3.336 i64 4, label %case.arm.4.342 ]
case.arm.3.336:
  %t338 = call ptr @__alloc(i64 16, i32 1)
  %t339 = inttoptr i64 4 to ptr
  %t340 = getelementptr ptr, ptr %t338, i32 0
  store ptr %t339, ptr %t340
  %t341 = getelementptr ptr, ptr %t338, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t341
  br label %case.end.3.337
case.end.3.337:
  br label %case.join.335
case.arm.4.342:
  %t344 = getelementptr ptr, ptr %t330, i32 1
  %t345 = load ptr, ptr %t344
  call void @__inc_ref(ptr %t345)
  %t346 = call ptr @__showInt32(ptr %t345)
  %t347 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t346)
  br label %case.end.4.343
case.end.4.343:
  br label %case.join.335
case.default.334:
  unreachable
case.join.335:
  %t348 = phi ptr [ %t338, %case.end.3.337 ], [ %t347, %case.end.4.343 ]
  %t349 = getelementptr ptr, ptr %t348, i32 0
  %t350 = load ptr, ptr %t349
  %t351 = ptrtoint ptr %t350 to i64
  switch i64 %t351, label %case.default.352 [ i64 3, label %case.arm.3.354 i64 4, label %case.arm.4.362 ]
case.arm.3.354:
  %t356 = getelementptr ptr, ptr %t348, i32 1
  %t357 = load ptr, ptr %t356
  call void @__inc_ref(ptr %t357)
  %t358 = call ptr @__alloc(i64 16, i32 1)
  %t359 = inttoptr i64 3 to ptr
  %t360 = getelementptr ptr, ptr %t358, i32 0
  store ptr %t359, ptr %t360
  call void @__inc_ref(ptr %t357)
  %t361 = getelementptr ptr, ptr %t358, i32 1
  store ptr %t357, ptr %t361
  br label %case.end.3.355
case.end.3.355:
  br label %case.join.353
case.arm.4.362:
  %t364 = getelementptr ptr, ptr %t348, i32 1
  %t365 = load ptr, ptr %t364
  call void @__inc_ref(ptr %t365)
  %t366 = call ptr @__parseInt32(ptr getelementptr inbounds (i8, ptr @.str.13, i64 12))
  %t367 = getelementptr ptr, ptr %t366, i32 0
  %t368 = load ptr, ptr %t367
  %t369 = ptrtoint ptr %t368 to i64
  switch i64 %t369, label %case.default.370 [ i64 3, label %case.arm.3.372 i64 4, label %case.arm.4.378 ]
case.arm.3.372:
  %t374 = call ptr @__alloc(i64 16, i32 1)
  %t375 = inttoptr i64 4 to ptr
  %t376 = getelementptr ptr, ptr %t374, i32 0
  store ptr %t375, ptr %t376
  %t377 = getelementptr ptr, ptr %t374, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t377
  br label %case.end.3.373
case.end.3.373:
  br label %case.join.371
case.arm.4.378:
  %t380 = getelementptr ptr, ptr %t366, i32 1
  %t381 = load ptr, ptr %t380
  call void @__inc_ref(ptr %t381)
  %t382 = call ptr @__showInt32(ptr %t381)
  %t383 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t382)
  br label %case.end.4.379
case.end.4.379:
  br label %case.join.371
case.default.370:
  unreachable
case.join.371:
  %t384 = phi ptr [ %t374, %case.end.3.373 ], [ %t383, %case.end.4.379 ]
  %t385 = getelementptr ptr, ptr %t384, i32 0
  %t386 = load ptr, ptr %t385
  %t387 = ptrtoint ptr %t386 to i64
  switch i64 %t387, label %case.default.388 [ i64 3, label %case.arm.3.390 i64 4, label %case.arm.4.398 ]
case.arm.3.390:
  %t392 = getelementptr ptr, ptr %t384, i32 1
  %t393 = load ptr, ptr %t392
  call void @__inc_ref(ptr %t393)
  %t394 = call ptr @__alloc(i64 16, i32 1)
  %t395 = inttoptr i64 3 to ptr
  %t396 = getelementptr ptr, ptr %t394, i32 0
  store ptr %t395, ptr %t396
  call void @__inc_ref(ptr %t393)
  %t397 = getelementptr ptr, ptr %t394, i32 1
  store ptr %t393, ptr %t397
  br label %case.end.3.391
case.end.3.391:
  br label %case.join.389
case.arm.4.398:
  %t400 = getelementptr ptr, ptr %t384, i32 1
  %t401 = load ptr, ptr %t400
  call void @__inc_ref(ptr %t401)
  %t402 = call ptr @__parseInt32(ptr getelementptr inbounds (i8, ptr @.str.14, i64 12))
  %t403 = getelementptr ptr, ptr %t402, i32 0
  %t404 = load ptr, ptr %t403
  %t405 = ptrtoint ptr %t404 to i64
  switch i64 %t405, label %case.default.406 [ i64 3, label %case.arm.3.408 i64 4, label %case.arm.4.414 ]
case.arm.3.408:
  %t410 = call ptr @__alloc(i64 16, i32 1)
  %t411 = inttoptr i64 4 to ptr
  %t412 = getelementptr ptr, ptr %t410, i32 0
  store ptr %t411, ptr %t412
  %t413 = getelementptr ptr, ptr %t410, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t413
  br label %case.end.3.409
case.end.3.409:
  br label %case.join.407
case.arm.4.414:
  %t416 = getelementptr ptr, ptr %t402, i32 1
  %t417 = load ptr, ptr %t416
  call void @__inc_ref(ptr %t417)
  %t418 = call ptr @__showInt32(ptr %t417)
  %t419 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t418)
  br label %case.end.4.415
case.end.4.415:
  br label %case.join.407
case.default.406:
  unreachable
case.join.407:
  %t420 = phi ptr [ %t410, %case.end.3.409 ], [ %t419, %case.end.4.415 ]
  %t421 = getelementptr ptr, ptr %t420, i32 0
  %t422 = load ptr, ptr %t421
  %t423 = ptrtoint ptr %t422 to i64
  switch i64 %t423, label %case.default.424 [ i64 3, label %case.arm.3.426 i64 4, label %case.arm.4.434 ]
case.arm.3.426:
  %t428 = getelementptr ptr, ptr %t420, i32 1
  %t429 = load ptr, ptr %t428
  call void @__inc_ref(ptr %t429)
  %t430 = call ptr @__alloc(i64 16, i32 1)
  %t431 = inttoptr i64 3 to ptr
  %t432 = getelementptr ptr, ptr %t430, i32 0
  store ptr %t431, ptr %t432
  call void @__inc_ref(ptr %t429)
  %t433 = getelementptr ptr, ptr %t430, i32 1
  store ptr %t429, ptr %t433
  br label %case.end.3.427
case.end.3.427:
  br label %case.join.425
case.arm.4.434:
  %t436 = getelementptr ptr, ptr %t420, i32 1
  %t437 = load ptr, ptr %t436
  call void @__inc_ref(ptr %t437)
  call void @__inc_ref(ptr %t41)
  %t438 = call ptr @__concat(ptr %t41, ptr getelementptr inbounds (i8, ptr @.str.15, i64 12))
  %t439 = getelementptr ptr, ptr %t438, i32 0
  %t440 = load ptr, ptr %t439
  %t441 = ptrtoint ptr %t440 to i64
  switch i64 %t441, label %case.default.442 [ i64 3, label %case.arm.3.444 i64 4, label %case.arm.4.452 ]
case.arm.3.444:
  %t446 = getelementptr ptr, ptr %t438, i32 1
  %t447 = load ptr, ptr %t446
  call void @__inc_ref(ptr %t447)
  %t448 = call ptr @__alloc(i64 16, i32 1)
  %t449 = inttoptr i64 3 to ptr
  %t450 = getelementptr ptr, ptr %t448, i32 0
  store ptr %t449, ptr %t450
  call void @__inc_ref(ptr %t447)
  %t451 = getelementptr ptr, ptr %t448, i32 1
  store ptr %t447, ptr %t451
  br label %case.end.3.445
case.end.3.445:
  br label %case.join.443
case.arm.4.452:
  %t454 = getelementptr ptr, ptr %t438, i32 1
  %t455 = load ptr, ptr %t454
  call void @__inc_ref(ptr %t455)
  call void @__inc_ref(ptr %t455)
  call void @__inc_ref(ptr %t77)
  %t456 = call ptr @__concat(ptr %t455, ptr %t77)
  %t457 = getelementptr ptr, ptr %t456, i32 0
  %t458 = load ptr, ptr %t457
  %t459 = ptrtoint ptr %t458 to i64
  switch i64 %t459, label %case.default.460 [ i64 3, label %case.arm.3.462 i64 4, label %case.arm.4.470 ]
case.arm.3.462:
  %t464 = getelementptr ptr, ptr %t456, i32 1
  %t465 = load ptr, ptr %t464
  call void @__inc_ref(ptr %t465)
  %t466 = call ptr @__alloc(i64 16, i32 1)
  %t467 = inttoptr i64 3 to ptr
  %t468 = getelementptr ptr, ptr %t466, i32 0
  store ptr %t467, ptr %t468
  call void @__inc_ref(ptr %t465)
  %t469 = getelementptr ptr, ptr %t466, i32 1
  store ptr %t465, ptr %t469
  br label %case.end.3.463
case.end.3.463:
  br label %case.join.461
case.arm.4.470:
  %t472 = getelementptr ptr, ptr %t456, i32 1
  %t473 = load ptr, ptr %t472
  call void @__inc_ref(ptr %t473)
  call void @__inc_ref(ptr %t473)
  %t474 = call ptr @__concat(ptr %t473, ptr getelementptr inbounds (i8, ptr @.str.15, i64 12))
  %t475 = getelementptr ptr, ptr %t474, i32 0
  %t476 = load ptr, ptr %t475
  %t477 = ptrtoint ptr %t476 to i64
  switch i64 %t477, label %case.default.478 [ i64 3, label %case.arm.3.480 i64 4, label %case.arm.4.488 ]
case.arm.3.480:
  %t482 = getelementptr ptr, ptr %t474, i32 1
  %t483 = load ptr, ptr %t482
  call void @__inc_ref(ptr %t483)
  %t484 = call ptr @__alloc(i64 16, i32 1)
  %t485 = inttoptr i64 3 to ptr
  %t486 = getelementptr ptr, ptr %t484, i32 0
  store ptr %t485, ptr %t486
  call void @__inc_ref(ptr %t483)
  %t487 = getelementptr ptr, ptr %t484, i32 1
  store ptr %t483, ptr %t487
  br label %case.end.3.481
case.end.3.481:
  br label %case.join.479
case.arm.4.488:
  %t490 = getelementptr ptr, ptr %t474, i32 1
  %t491 = load ptr, ptr %t490
  call void @__inc_ref(ptr %t491)
  call void @__inc_ref(ptr %t491)
  call void @__inc_ref(ptr %t113)
  %t492 = call ptr @__concat(ptr %t491, ptr %t113)
  %t493 = getelementptr ptr, ptr %t492, i32 0
  %t494 = load ptr, ptr %t493
  %t495 = ptrtoint ptr %t494 to i64
  switch i64 %t495, label %case.default.496 [ i64 3, label %case.arm.3.498 i64 4, label %case.arm.4.506 ]
case.arm.3.498:
  %t500 = getelementptr ptr, ptr %t492, i32 1
  %t501 = load ptr, ptr %t500
  call void @__inc_ref(ptr %t501)
  %t502 = call ptr @__alloc(i64 16, i32 1)
  %t503 = inttoptr i64 3 to ptr
  %t504 = getelementptr ptr, ptr %t502, i32 0
  store ptr %t503, ptr %t504
  call void @__inc_ref(ptr %t501)
  %t505 = getelementptr ptr, ptr %t502, i32 1
  store ptr %t501, ptr %t505
  br label %case.end.3.499
case.end.3.499:
  br label %case.join.497
case.arm.4.506:
  %t508 = getelementptr ptr, ptr %t492, i32 1
  %t509 = load ptr, ptr %t508
  call void @__inc_ref(ptr %t509)
  call void @__inc_ref(ptr %t509)
  %t510 = call ptr @__concat(ptr %t509, ptr getelementptr inbounds (i8, ptr @.str.15, i64 12))
  %t511 = getelementptr ptr, ptr %t510, i32 0
  %t512 = load ptr, ptr %t511
  %t513 = ptrtoint ptr %t512 to i64
  switch i64 %t513, label %case.default.514 [ i64 3, label %case.arm.3.516 i64 4, label %case.arm.4.524 ]
case.arm.3.516:
  %t518 = getelementptr ptr, ptr %t510, i32 1
  %t519 = load ptr, ptr %t518
  call void @__inc_ref(ptr %t519)
  %t520 = call ptr @__alloc(i64 16, i32 1)
  %t521 = inttoptr i64 3 to ptr
  %t522 = getelementptr ptr, ptr %t520, i32 0
  store ptr %t521, ptr %t522
  call void @__inc_ref(ptr %t519)
  %t523 = getelementptr ptr, ptr %t520, i32 1
  store ptr %t519, ptr %t523
  br label %case.end.3.517
case.end.3.517:
  br label %case.join.515
case.arm.4.524:
  %t526 = getelementptr ptr, ptr %t510, i32 1
  %t527 = load ptr, ptr %t526
  call void @__inc_ref(ptr %t527)
  call void @__inc_ref(ptr %t527)
  call void @__inc_ref(ptr %t149)
  %t528 = call ptr @__concat(ptr %t527, ptr %t149)
  %t529 = getelementptr ptr, ptr %t528, i32 0
  %t530 = load ptr, ptr %t529
  %t531 = ptrtoint ptr %t530 to i64
  switch i64 %t531, label %case.default.532 [ i64 3, label %case.arm.3.534 i64 4, label %case.arm.4.542 ]
case.arm.3.534:
  %t536 = getelementptr ptr, ptr %t528, i32 1
  %t537 = load ptr, ptr %t536
  call void @__inc_ref(ptr %t537)
  %t538 = call ptr @__alloc(i64 16, i32 1)
  %t539 = inttoptr i64 3 to ptr
  %t540 = getelementptr ptr, ptr %t538, i32 0
  store ptr %t539, ptr %t540
  call void @__inc_ref(ptr %t537)
  %t541 = getelementptr ptr, ptr %t538, i32 1
  store ptr %t537, ptr %t541
  br label %case.end.3.535
case.end.3.535:
  br label %case.join.533
case.arm.4.542:
  %t544 = getelementptr ptr, ptr %t528, i32 1
  %t545 = load ptr, ptr %t544
  call void @__inc_ref(ptr %t545)
  call void @__inc_ref(ptr %t545)
  %t546 = call ptr @__concat(ptr %t545, ptr getelementptr inbounds (i8, ptr @.str.15, i64 12))
  %t547 = getelementptr ptr, ptr %t546, i32 0
  %t548 = load ptr, ptr %t547
  %t549 = ptrtoint ptr %t548 to i64
  switch i64 %t549, label %case.default.550 [ i64 3, label %case.arm.3.552 i64 4, label %case.arm.4.560 ]
case.arm.3.552:
  %t554 = getelementptr ptr, ptr %t546, i32 1
  %t555 = load ptr, ptr %t554
  call void @__inc_ref(ptr %t555)
  %t556 = call ptr @__alloc(i64 16, i32 1)
  %t557 = inttoptr i64 3 to ptr
  %t558 = getelementptr ptr, ptr %t556, i32 0
  store ptr %t557, ptr %t558
  call void @__inc_ref(ptr %t555)
  %t559 = getelementptr ptr, ptr %t556, i32 1
  store ptr %t555, ptr %t559
  br label %case.end.3.553
case.end.3.553:
  br label %case.join.551
case.arm.4.560:
  %t562 = getelementptr ptr, ptr %t546, i32 1
  %t563 = load ptr, ptr %t562
  call void @__inc_ref(ptr %t563)
  call void @__inc_ref(ptr %t563)
  call void @__inc_ref(ptr %t185)
  %t564 = call ptr @__concat(ptr %t563, ptr %t185)
  %t565 = getelementptr ptr, ptr %t564, i32 0
  %t566 = load ptr, ptr %t565
  %t567 = ptrtoint ptr %t566 to i64
  switch i64 %t567, label %case.default.568 [ i64 3, label %case.arm.3.570 i64 4, label %case.arm.4.578 ]
case.arm.3.570:
  %t572 = getelementptr ptr, ptr %t564, i32 1
  %t573 = load ptr, ptr %t572
  call void @__inc_ref(ptr %t573)
  %t574 = call ptr @__alloc(i64 16, i32 1)
  %t575 = inttoptr i64 3 to ptr
  %t576 = getelementptr ptr, ptr %t574, i32 0
  store ptr %t575, ptr %t576
  call void @__inc_ref(ptr %t573)
  %t577 = getelementptr ptr, ptr %t574, i32 1
  store ptr %t573, ptr %t577
  br label %case.end.3.571
case.end.3.571:
  br label %case.join.569
case.arm.4.578:
  %t580 = getelementptr ptr, ptr %t564, i32 1
  %t581 = load ptr, ptr %t580
  call void @__inc_ref(ptr %t581)
  call void @__inc_ref(ptr %t581)
  %t582 = call ptr @__concat(ptr %t581, ptr getelementptr inbounds (i8, ptr @.str.15, i64 12))
  %t583 = getelementptr ptr, ptr %t582, i32 0
  %t584 = load ptr, ptr %t583
  %t585 = ptrtoint ptr %t584 to i64
  switch i64 %t585, label %case.default.586 [ i64 3, label %case.arm.3.588 i64 4, label %case.arm.4.596 ]
case.arm.3.588:
  %t590 = getelementptr ptr, ptr %t582, i32 1
  %t591 = load ptr, ptr %t590
  call void @__inc_ref(ptr %t591)
  %t592 = call ptr @__alloc(i64 16, i32 1)
  %t593 = inttoptr i64 3 to ptr
  %t594 = getelementptr ptr, ptr %t592, i32 0
  store ptr %t593, ptr %t594
  call void @__inc_ref(ptr %t591)
  %t595 = getelementptr ptr, ptr %t592, i32 1
  store ptr %t591, ptr %t595
  br label %case.end.3.589
case.end.3.589:
  br label %case.join.587
case.arm.4.596:
  %t598 = getelementptr ptr, ptr %t582, i32 1
  %t599 = load ptr, ptr %t598
  call void @__inc_ref(ptr %t599)
  call void @__inc_ref(ptr %t599)
  call void @__inc_ref(ptr %t221)
  %t600 = call ptr @__concat(ptr %t599, ptr %t221)
  %t601 = getelementptr ptr, ptr %t600, i32 0
  %t602 = load ptr, ptr %t601
  %t603 = ptrtoint ptr %t602 to i64
  switch i64 %t603, label %case.default.604 [ i64 3, label %case.arm.3.606 i64 4, label %case.arm.4.614 ]
case.arm.3.606:
  %t608 = getelementptr ptr, ptr %t600, i32 1
  %t609 = load ptr, ptr %t608
  call void @__inc_ref(ptr %t609)
  %t610 = call ptr @__alloc(i64 16, i32 1)
  %t611 = inttoptr i64 3 to ptr
  %t612 = getelementptr ptr, ptr %t610, i32 0
  store ptr %t611, ptr %t612
  call void @__inc_ref(ptr %t609)
  %t613 = getelementptr ptr, ptr %t610, i32 1
  store ptr %t609, ptr %t613
  br label %case.end.3.607
case.end.3.607:
  br label %case.join.605
case.arm.4.614:
  %t616 = getelementptr ptr, ptr %t600, i32 1
  %t617 = load ptr, ptr %t616
  call void @__inc_ref(ptr %t617)
  call void @__inc_ref(ptr %t617)
  %t618 = call ptr @__concat(ptr %t617, ptr getelementptr inbounds (i8, ptr @.str.15, i64 12))
  %t619 = getelementptr ptr, ptr %t618, i32 0
  %t620 = load ptr, ptr %t619
  %t621 = ptrtoint ptr %t620 to i64
  switch i64 %t621, label %case.default.622 [ i64 3, label %case.arm.3.624 i64 4, label %case.arm.4.632 ]
case.arm.3.624:
  %t626 = getelementptr ptr, ptr %t618, i32 1
  %t627 = load ptr, ptr %t626
  call void @__inc_ref(ptr %t627)
  %t628 = call ptr @__alloc(i64 16, i32 1)
  %t629 = inttoptr i64 3 to ptr
  %t630 = getelementptr ptr, ptr %t628, i32 0
  store ptr %t629, ptr %t630
  call void @__inc_ref(ptr %t627)
  %t631 = getelementptr ptr, ptr %t628, i32 1
  store ptr %t627, ptr %t631
  br label %case.end.3.625
case.end.3.625:
  br label %case.join.623
case.arm.4.632:
  %t634 = getelementptr ptr, ptr %t618, i32 1
  %t635 = load ptr, ptr %t634
  call void @__inc_ref(ptr %t635)
  call void @__inc_ref(ptr %t635)
  call void @__inc_ref(ptr %t257)
  %t636 = call ptr @__concat(ptr %t635, ptr %t257)
  %t637 = getelementptr ptr, ptr %t636, i32 0
  %t638 = load ptr, ptr %t637
  %t639 = ptrtoint ptr %t638 to i64
  switch i64 %t639, label %case.default.640 [ i64 3, label %case.arm.3.642 i64 4, label %case.arm.4.650 ]
case.arm.3.642:
  %t644 = getelementptr ptr, ptr %t636, i32 1
  %t645 = load ptr, ptr %t644
  call void @__inc_ref(ptr %t645)
  %t646 = call ptr @__alloc(i64 16, i32 1)
  %t647 = inttoptr i64 3 to ptr
  %t648 = getelementptr ptr, ptr %t646, i32 0
  store ptr %t647, ptr %t648
  call void @__inc_ref(ptr %t645)
  %t649 = getelementptr ptr, ptr %t646, i32 1
  store ptr %t645, ptr %t649
  br label %case.end.3.643
case.end.3.643:
  br label %case.join.641
case.arm.4.650:
  %t652 = getelementptr ptr, ptr %t636, i32 1
  %t653 = load ptr, ptr %t652
  call void @__inc_ref(ptr %t653)
  call void @__inc_ref(ptr %t653)
  %t654 = call ptr @__concat(ptr %t653, ptr getelementptr inbounds (i8, ptr @.str.15, i64 12))
  %t655 = getelementptr ptr, ptr %t654, i32 0
  %t656 = load ptr, ptr %t655
  %t657 = ptrtoint ptr %t656 to i64
  switch i64 %t657, label %case.default.658 [ i64 3, label %case.arm.3.660 i64 4, label %case.arm.4.668 ]
case.arm.3.660:
  %t662 = getelementptr ptr, ptr %t654, i32 1
  %t663 = load ptr, ptr %t662
  call void @__inc_ref(ptr %t663)
  %t664 = call ptr @__alloc(i64 16, i32 1)
  %t665 = inttoptr i64 3 to ptr
  %t666 = getelementptr ptr, ptr %t664, i32 0
  store ptr %t665, ptr %t666
  call void @__inc_ref(ptr %t663)
  %t667 = getelementptr ptr, ptr %t664, i32 1
  store ptr %t663, ptr %t667
  br label %case.end.3.661
case.end.3.661:
  br label %case.join.659
case.arm.4.668:
  %t670 = getelementptr ptr, ptr %t654, i32 1
  %t671 = load ptr, ptr %t670
  call void @__inc_ref(ptr %t671)
  call void @__inc_ref(ptr %t671)
  call void @__inc_ref(ptr %t293)
  %t672 = call ptr @__concat(ptr %t671, ptr %t293)
  %t673 = getelementptr ptr, ptr %t672, i32 0
  %t674 = load ptr, ptr %t673
  %t675 = ptrtoint ptr %t674 to i64
  switch i64 %t675, label %case.default.676 [ i64 3, label %case.arm.3.678 i64 4, label %case.arm.4.686 ]
case.arm.3.678:
  %t680 = getelementptr ptr, ptr %t672, i32 1
  %t681 = load ptr, ptr %t680
  call void @__inc_ref(ptr %t681)
  %t682 = call ptr @__alloc(i64 16, i32 1)
  %t683 = inttoptr i64 3 to ptr
  %t684 = getelementptr ptr, ptr %t682, i32 0
  store ptr %t683, ptr %t684
  call void @__inc_ref(ptr %t681)
  %t685 = getelementptr ptr, ptr %t682, i32 1
  store ptr %t681, ptr %t685
  br label %case.end.3.679
case.end.3.679:
  br label %case.join.677
case.arm.4.686:
  %t688 = getelementptr ptr, ptr %t672, i32 1
  %t689 = load ptr, ptr %t688
  call void @__inc_ref(ptr %t689)
  call void @__inc_ref(ptr %t689)
  %t690 = call ptr @__concat(ptr %t689, ptr getelementptr inbounds (i8, ptr @.str.15, i64 12))
  %t691 = getelementptr ptr, ptr %t690, i32 0
  %t692 = load ptr, ptr %t691
  %t693 = ptrtoint ptr %t692 to i64
  switch i64 %t693, label %case.default.694 [ i64 3, label %case.arm.3.696 i64 4, label %case.arm.4.704 ]
case.arm.3.696:
  %t698 = getelementptr ptr, ptr %t690, i32 1
  %t699 = load ptr, ptr %t698
  call void @__inc_ref(ptr %t699)
  %t700 = call ptr @__alloc(i64 16, i32 1)
  %t701 = inttoptr i64 3 to ptr
  %t702 = getelementptr ptr, ptr %t700, i32 0
  store ptr %t701, ptr %t702
  call void @__inc_ref(ptr %t699)
  %t703 = getelementptr ptr, ptr %t700, i32 1
  store ptr %t699, ptr %t703
  br label %case.end.3.697
case.end.3.697:
  br label %case.join.695
case.arm.4.704:
  %t706 = getelementptr ptr, ptr %t690, i32 1
  %t707 = load ptr, ptr %t706
  call void @__inc_ref(ptr %t707)
  call void @__inc_ref(ptr %t707)
  call void @__inc_ref(ptr %t329)
  %t708 = call ptr @__concat(ptr %t707, ptr %t329)
  %t709 = getelementptr ptr, ptr %t708, i32 0
  %t710 = load ptr, ptr %t709
  %t711 = ptrtoint ptr %t710 to i64
  switch i64 %t711, label %case.default.712 [ i64 3, label %case.arm.3.714 i64 4, label %case.arm.4.722 ]
case.arm.3.714:
  %t716 = getelementptr ptr, ptr %t708, i32 1
  %t717 = load ptr, ptr %t716
  call void @__inc_ref(ptr %t717)
  %t718 = call ptr @__alloc(i64 16, i32 1)
  %t719 = inttoptr i64 3 to ptr
  %t720 = getelementptr ptr, ptr %t718, i32 0
  store ptr %t719, ptr %t720
  call void @__inc_ref(ptr %t717)
  %t721 = getelementptr ptr, ptr %t718, i32 1
  store ptr %t717, ptr %t721
  br label %case.end.3.715
case.end.3.715:
  br label %case.join.713
case.arm.4.722:
  %t724 = getelementptr ptr, ptr %t708, i32 1
  %t725 = load ptr, ptr %t724
  call void @__inc_ref(ptr %t725)
  call void @__inc_ref(ptr %t725)
  %t726 = call ptr @__concat(ptr %t725, ptr getelementptr inbounds (i8, ptr @.str.15, i64 12))
  %t727 = getelementptr ptr, ptr %t726, i32 0
  %t728 = load ptr, ptr %t727
  %t729 = ptrtoint ptr %t728 to i64
  switch i64 %t729, label %case.default.730 [ i64 3, label %case.arm.3.732 i64 4, label %case.arm.4.740 ]
case.arm.3.732:
  %t734 = getelementptr ptr, ptr %t726, i32 1
  %t735 = load ptr, ptr %t734
  call void @__inc_ref(ptr %t735)
  %t736 = call ptr @__alloc(i64 16, i32 1)
  %t737 = inttoptr i64 3 to ptr
  %t738 = getelementptr ptr, ptr %t736, i32 0
  store ptr %t737, ptr %t738
  call void @__inc_ref(ptr %t735)
  %t739 = getelementptr ptr, ptr %t736, i32 1
  store ptr %t735, ptr %t739
  br label %case.end.3.733
case.end.3.733:
  br label %case.join.731
case.arm.4.740:
  %t742 = getelementptr ptr, ptr %t726, i32 1
  %t743 = load ptr, ptr %t742
  call void @__inc_ref(ptr %t743)
  call void @__inc_ref(ptr %t743)
  call void @__inc_ref(ptr %t365)
  %t744 = call ptr @__concat(ptr %t743, ptr %t365)
  %t745 = getelementptr ptr, ptr %t744, i32 0
  %t746 = load ptr, ptr %t745
  %t747 = ptrtoint ptr %t746 to i64
  switch i64 %t747, label %case.default.748 [ i64 3, label %case.arm.3.750 i64 4, label %case.arm.4.758 ]
case.arm.3.750:
  %t752 = getelementptr ptr, ptr %t744, i32 1
  %t753 = load ptr, ptr %t752
  call void @__inc_ref(ptr %t753)
  %t754 = call ptr @__alloc(i64 16, i32 1)
  %t755 = inttoptr i64 3 to ptr
  %t756 = getelementptr ptr, ptr %t754, i32 0
  store ptr %t755, ptr %t756
  call void @__inc_ref(ptr %t753)
  %t757 = getelementptr ptr, ptr %t754, i32 1
  store ptr %t753, ptr %t757
  br label %case.end.3.751
case.end.3.751:
  br label %case.join.749
case.arm.4.758:
  %t760 = getelementptr ptr, ptr %t744, i32 1
  %t761 = load ptr, ptr %t760
  call void @__inc_ref(ptr %t761)
  call void @__inc_ref(ptr %t761)
  %t762 = call ptr @__concat(ptr %t761, ptr getelementptr inbounds (i8, ptr @.str.15, i64 12))
  %t763 = getelementptr ptr, ptr %t762, i32 0
  %t764 = load ptr, ptr %t763
  %t765 = ptrtoint ptr %t764 to i64
  switch i64 %t765, label %case.default.766 [ i64 3, label %case.arm.3.768 i64 4, label %case.arm.4.776 ]
case.arm.3.768:
  %t770 = getelementptr ptr, ptr %t762, i32 1
  %t771 = load ptr, ptr %t770
  call void @__inc_ref(ptr %t771)
  %t772 = call ptr @__alloc(i64 16, i32 1)
  %t773 = inttoptr i64 3 to ptr
  %t774 = getelementptr ptr, ptr %t772, i32 0
  store ptr %t773, ptr %t774
  call void @__inc_ref(ptr %t771)
  %t775 = getelementptr ptr, ptr %t772, i32 1
  store ptr %t771, ptr %t775
  br label %case.end.3.769
case.end.3.769:
  br label %case.join.767
case.arm.4.776:
  %t778 = getelementptr ptr, ptr %t762, i32 1
  %t779 = load ptr, ptr %t778
  call void @__inc_ref(ptr %t779)
  call void @__inc_ref(ptr %t779)
  call void @__inc_ref(ptr %t401)
  %t780 = call ptr @__concat(ptr %t779, ptr %t401)
  %t781 = getelementptr ptr, ptr %t780, i32 0
  %t782 = load ptr, ptr %t781
  %t783 = ptrtoint ptr %t782 to i64
  switch i64 %t783, label %case.default.784 [ i64 3, label %case.arm.3.786 i64 4, label %case.arm.4.794 ]
case.arm.3.786:
  %t788 = getelementptr ptr, ptr %t780, i32 1
  %t789 = load ptr, ptr %t788
  call void @__inc_ref(ptr %t789)
  %t790 = call ptr @__alloc(i64 16, i32 1)
  %t791 = inttoptr i64 3 to ptr
  %t792 = getelementptr ptr, ptr %t790, i32 0
  store ptr %t791, ptr %t792
  call void @__inc_ref(ptr %t789)
  %t793 = getelementptr ptr, ptr %t790, i32 1
  store ptr %t789, ptr %t793
  br label %case.end.3.787
case.end.3.787:
  br label %case.join.785
case.arm.4.794:
  %t796 = getelementptr ptr, ptr %t780, i32 1
  %t797 = load ptr, ptr %t796
  call void @__inc_ref(ptr %t797)
  call void @__inc_ref(ptr %t797)
  %t798 = call ptr @__concat(ptr %t797, ptr getelementptr inbounds (i8, ptr @.str.15, i64 12))
  %t799 = getelementptr ptr, ptr %t798, i32 0
  %t800 = load ptr, ptr %t799
  %t801 = ptrtoint ptr %t800 to i64
  switch i64 %t801, label %case.default.802 [ i64 3, label %case.arm.3.804 i64 4, label %case.arm.4.812 ]
case.arm.3.804:
  %t806 = getelementptr ptr, ptr %t798, i32 1
  %t807 = load ptr, ptr %t806
  call void @__inc_ref(ptr %t807)
  %t808 = call ptr @__alloc(i64 16, i32 1)
  %t809 = inttoptr i64 3 to ptr
  %t810 = getelementptr ptr, ptr %t808, i32 0
  store ptr %t809, ptr %t810
  call void @__inc_ref(ptr %t807)
  %t811 = getelementptr ptr, ptr %t808, i32 1
  store ptr %t807, ptr %t811
  br label %case.end.3.805
case.end.3.805:
  br label %case.join.803
case.arm.4.812:
  %t814 = getelementptr ptr, ptr %t798, i32 1
  %t815 = load ptr, ptr %t814
  call void @__inc_ref(ptr %t815)
  call void @__inc_ref(ptr %t815)
  call void @__inc_ref(ptr %t437)
  %t816 = call ptr @__concat(ptr %t815, ptr %t437)
  br label %case.end.4.813
case.end.4.813:
  br label %case.join.803
case.default.802:
  unreachable
case.join.803:
  %t817 = phi ptr [ %t808, %case.end.3.805 ], [ %t816, %case.end.4.813 ]
  call void @__free_recursive(ptr %t798)
  br label %case.end.4.795
case.end.4.795:
  br label %case.join.785
case.default.784:
  unreachable
case.join.785:
  %t818 = phi ptr [ %t790, %case.end.3.787 ], [ %t817, %case.end.4.795 ]
  call void @__free_recursive(ptr %t780)
  br label %case.end.4.777
case.end.4.777:
  br label %case.join.767
case.default.766:
  unreachable
case.join.767:
  %t819 = phi ptr [ %t772, %case.end.3.769 ], [ %t818, %case.end.4.777 ]
  call void @__free_recursive(ptr %t762)
  br label %case.end.4.759
case.end.4.759:
  br label %case.join.749
case.default.748:
  unreachable
case.join.749:
  %t820 = phi ptr [ %t754, %case.end.3.751 ], [ %t819, %case.end.4.759 ]
  call void @__free_recursive(ptr %t744)
  br label %case.end.4.741
case.end.4.741:
  br label %case.join.731
case.default.730:
  unreachable
case.join.731:
  %t821 = phi ptr [ %t736, %case.end.3.733 ], [ %t820, %case.end.4.741 ]
  call void @__free_recursive(ptr %t726)
  br label %case.end.4.723
case.end.4.723:
  br label %case.join.713
case.default.712:
  unreachable
case.join.713:
  %t822 = phi ptr [ %t718, %case.end.3.715 ], [ %t821, %case.end.4.723 ]
  call void @__free_recursive(ptr %t708)
  br label %case.end.4.705
case.end.4.705:
  br label %case.join.695
case.default.694:
  unreachable
case.join.695:
  %t823 = phi ptr [ %t700, %case.end.3.697 ], [ %t822, %case.end.4.705 ]
  call void @__free_recursive(ptr %t690)
  br label %case.end.4.687
case.end.4.687:
  br label %case.join.677
case.default.676:
  unreachable
case.join.677:
  %t824 = phi ptr [ %t682, %case.end.3.679 ], [ %t823, %case.end.4.687 ]
  call void @__free_recursive(ptr %t672)
  br label %case.end.4.669
case.end.4.669:
  br label %case.join.659
case.default.658:
  unreachable
case.join.659:
  %t825 = phi ptr [ %t664, %case.end.3.661 ], [ %t824, %case.end.4.669 ]
  call void @__free_recursive(ptr %t654)
  br label %case.end.4.651
case.end.4.651:
  br label %case.join.641
case.default.640:
  unreachable
case.join.641:
  %t826 = phi ptr [ %t646, %case.end.3.643 ], [ %t825, %case.end.4.651 ]
  call void @__free_recursive(ptr %t636)
  br label %case.end.4.633
case.end.4.633:
  br label %case.join.623
case.default.622:
  unreachable
case.join.623:
  %t827 = phi ptr [ %t628, %case.end.3.625 ], [ %t826, %case.end.4.633 ]
  call void @__free_recursive(ptr %t618)
  br label %case.end.4.615
case.end.4.615:
  br label %case.join.605
case.default.604:
  unreachable
case.join.605:
  %t828 = phi ptr [ %t610, %case.end.3.607 ], [ %t827, %case.end.4.615 ]
  call void @__free_recursive(ptr %t600)
  br label %case.end.4.597
case.end.4.597:
  br label %case.join.587
case.default.586:
  unreachable
case.join.587:
  %t829 = phi ptr [ %t592, %case.end.3.589 ], [ %t828, %case.end.4.597 ]
  call void @__free_recursive(ptr %t582)
  br label %case.end.4.579
case.end.4.579:
  br label %case.join.569
case.default.568:
  unreachable
case.join.569:
  %t830 = phi ptr [ %t574, %case.end.3.571 ], [ %t829, %case.end.4.579 ]
  call void @__free_recursive(ptr %t564)
  br label %case.end.4.561
case.end.4.561:
  br label %case.join.551
case.default.550:
  unreachable
case.join.551:
  %t831 = phi ptr [ %t556, %case.end.3.553 ], [ %t830, %case.end.4.561 ]
  call void @__free_recursive(ptr %t546)
  br label %case.end.4.543
case.end.4.543:
  br label %case.join.533
case.default.532:
  unreachable
case.join.533:
  %t832 = phi ptr [ %t538, %case.end.3.535 ], [ %t831, %case.end.4.543 ]
  call void @__free_recursive(ptr %t528)
  br label %case.end.4.525
case.end.4.525:
  br label %case.join.515
case.default.514:
  unreachable
case.join.515:
  %t833 = phi ptr [ %t520, %case.end.3.517 ], [ %t832, %case.end.4.525 ]
  call void @__free_recursive(ptr %t510)
  br label %case.end.4.507
case.end.4.507:
  br label %case.join.497
case.default.496:
  unreachable
case.join.497:
  %t834 = phi ptr [ %t502, %case.end.3.499 ], [ %t833, %case.end.4.507 ]
  call void @__free_recursive(ptr %t492)
  br label %case.end.4.489
case.end.4.489:
  br label %case.join.479
case.default.478:
  unreachable
case.join.479:
  %t835 = phi ptr [ %t484, %case.end.3.481 ], [ %t834, %case.end.4.489 ]
  call void @__free_recursive(ptr %t474)
  br label %case.end.4.471
case.end.4.471:
  br label %case.join.461
case.default.460:
  unreachable
case.join.461:
  %t836 = phi ptr [ %t466, %case.end.3.463 ], [ %t835, %case.end.4.471 ]
  call void @__free_recursive(ptr %t456)
  br label %case.end.4.453
case.end.4.453:
  br label %case.join.443
case.default.442:
  unreachable
case.join.443:
  %t837 = phi ptr [ %t448, %case.end.3.445 ], [ %t836, %case.end.4.453 ]
  call void @__free_recursive(ptr %t438)
  br label %case.end.4.435
case.end.4.435:
  br label %case.join.425
case.default.424:
  unreachable
case.join.425:
  %t838 = phi ptr [ %t430, %case.end.3.427 ], [ %t837, %case.end.4.435 ]
  call void @__free_recursive(ptr %t420)
  call void @__free_recursive(ptr %t402)
  br label %case.end.4.399
case.end.4.399:
  br label %case.join.389
case.default.388:
  unreachable
case.join.389:
  %t839 = phi ptr [ %t394, %case.end.3.391 ], [ %t838, %case.end.4.399 ]
  call void @__free_recursive(ptr %t384)
  call void @__free_recursive(ptr %t366)
  br label %case.end.4.363
case.end.4.363:
  br label %case.join.353
case.default.352:
  unreachable
case.join.353:
  %t840 = phi ptr [ %t358, %case.end.3.355 ], [ %t839, %case.end.4.363 ]
  call void @__free_recursive(ptr %t348)
  call void @__free_recursive(ptr %t330)
  br label %case.end.4.327
case.end.4.327:
  br label %case.join.317
case.default.316:
  unreachable
case.join.317:
  %t841 = phi ptr [ %t322, %case.end.3.319 ], [ %t840, %case.end.4.327 ]
  call void @__free_recursive(ptr %t312)
  call void @__free_recursive(ptr %t294)
  br label %case.end.4.291
case.end.4.291:
  br label %case.join.281
case.default.280:
  unreachable
case.join.281:
  %t842 = phi ptr [ %t286, %case.end.3.283 ], [ %t841, %case.end.4.291 ]
  call void @__free_recursive(ptr %t276)
  call void @__free_recursive(ptr %t258)
  br label %case.end.4.255
case.end.4.255:
  br label %case.join.245
case.default.244:
  unreachable
case.join.245:
  %t843 = phi ptr [ %t250, %case.end.3.247 ], [ %t842, %case.end.4.255 ]
  call void @__free_recursive(ptr %t240)
  call void @__free_recursive(ptr %t222)
  br label %case.end.4.219
case.end.4.219:
  br label %case.join.209
case.default.208:
  unreachable
case.join.209:
  %t844 = phi ptr [ %t214, %case.end.3.211 ], [ %t843, %case.end.4.219 ]
  call void @__free_recursive(ptr %t204)
  call void @__free_recursive(ptr %t186)
  br label %case.end.4.183
case.end.4.183:
  br label %case.join.173
case.default.172:
  unreachable
case.join.173:
  %t845 = phi ptr [ %t178, %case.end.3.175 ], [ %t844, %case.end.4.183 ]
  call void @__free_recursive(ptr %t168)
  call void @__free_recursive(ptr %t150)
  br label %case.end.4.147
case.end.4.147:
  br label %case.join.137
case.default.136:
  unreachable
case.join.137:
  %t846 = phi ptr [ %t142, %case.end.3.139 ], [ %t845, %case.end.4.147 ]
  call void @__free_recursive(ptr %t132)
  call void @__free_recursive(ptr %t114)
  br label %case.end.4.111
case.end.4.111:
  br label %case.join.101
case.default.100:
  unreachable
case.join.101:
  %t847 = phi ptr [ %t106, %case.end.3.103 ], [ %t846, %case.end.4.111 ]
  call void @__free_recursive(ptr %t96)
  call void @__free_recursive(ptr %t78)
  br label %case.end.4.75
case.end.4.75:
  br label %case.join.65
case.default.64:
  unreachable
case.join.65:
  %t848 = phi ptr [ %t70, %case.end.3.67 ], [ %t847, %case.end.4.75 ]
  call void @__free_recursive(ptr %t60)
  call void @__free_recursive(ptr %t42)
  call void @__free_recursive(ptr %t20)
  store ptr %t848, ptr %v__inl40_scrut.jslot
  br label %join.1
join.case.default.24:
  unreachable
join.1:
  %t849 = load ptr, ptr %v__inl40_scrut.jslot
  %t850 = getelementptr ptr, ptr %t849, i32 0
  %t851 = load ptr, ptr %t850
  %t852 = ptrtoint ptr %t851 to i64
  switch i64 %t852, label %case.default.853 [ i64 3, label %case.arm.3.855 i64 4, label %case.arm.4.869 ]
case.arm.3.855:
  %t857 = call ptr @__alloc(i64 24, i32 2)
  %t858 = inttoptr i64 7 to ptr
  %t859 = getelementptr ptr, ptr %t857, i32 0
  store ptr %t858, ptr %t859
  %t860 = getelementptr ptr, ptr %t857, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t860
  %t861 = call ptr @__alloc(i64 16, i32 1)
  %t862 = inttoptr i64 5 to ptr
  %t863 = getelementptr ptr, ptr %t861, i32 0
  store ptr %t862, ptr %t863
  %t864 = call ptr @__alloc(i64 8, i32 0)
  %t865 = inttoptr i64 0 to ptr
  %t866 = getelementptr ptr, ptr %t864, i32 0
  store ptr %t865, ptr %t866
  %t867 = getelementptr ptr, ptr %t861, i32 1
  store ptr %t864, ptr %t867
  %t868 = getelementptr ptr, ptr %t857, i32 2
  store ptr %t861, ptr %t868
  br label %case.end.3.856
case.end.3.856:
  br label %case.join.854
case.arm.4.869:
  %t871 = call ptr @__alloc(i64 24, i32 2)
  %t872 = inttoptr i64 7 to ptr
  %t873 = getelementptr ptr, ptr %t871, i32 0
  store ptr %t872, ptr %t873
  %t874 = getelementptr ptr, ptr %t849, i32 1
  %t875 = load ptr, ptr %t874
  call void @__inc_ref(ptr %t875)
  %t876 = getelementptr ptr, ptr %t871, i32 1
  store ptr %t875, ptr %t876
  %t877 = call ptr @__alloc(i64 16, i32 1)
  %t878 = inttoptr i64 5 to ptr
  %t879 = getelementptr ptr, ptr %t877, i32 0
  store ptr %t878, ptr %t879
  %t880 = call ptr @__alloc(i64 8, i32 0)
  %t881 = inttoptr i64 0 to ptr
  %t882 = getelementptr ptr, ptr %t880, i32 0
  store ptr %t881, ptr %t882
  %t883 = getelementptr ptr, ptr %t877, i32 1
  store ptr %t880, ptr %t883
  %t884 = getelementptr ptr, ptr %t871, i32 2
  store ptr %t877, ptr %t884
  br label %case.end.4.870
case.end.4.870:
  br label %case.join.854
case.default.853:
  unreachable
case.join.854:
  %t885 = phi ptr [ %t857, %case.end.3.856 ], [ %t871, %case.end.4.870 ]
  call void @__free_recursive(ptr %t849)
  br label %join.end.886
join.end.886:
  br label %join.after.2
join.after.2:
  %t887 = phi ptr [ %t26, %join.val.38 ], [ %t885, %join.end.886 ]
  call void @__free_recursive(ptr %t0)
  ret ptr %t887
}

define i32 @main(i32 %argc, ptr %argv) {
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
