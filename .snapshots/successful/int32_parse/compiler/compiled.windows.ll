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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"err" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"ok:" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"42" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"-42" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"0" }
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [10 x i8]} { i32 0, i32 0, i32 0, i32 10, i32 10, [10 x i8] c"2147483647" }
@.str.6 = private unnamed_addr constant {i32, i32, i32, i32, i32, [11 x i8]} { i32 0, i32 0, i32 0, i32 11, i32 11, [11 x i8] c"-2147483648" }
@.str.7 = private unnamed_addr constant {i32, i32, i32, i32, i32, [10 x i8]} { i32 0, i32 0, i32 0, i32 10, i32 10, [10 x i8] c"2147483648" }
@.str.8 = private unnamed_addr constant {i32, i32, i32, i32, i32, [11 x i8]} { i32 0, i32 0, i32 0, i32 11, i32 11, [11 x i8] c"-2147483649" }
@.str.9 = private unnamed_addr constant {i32, i32, i32, i32, i32, [0 x i8]} { i32 0, i32 0, i32 0, i32 0, i32 0, [0 x i8] zeroinitializer }
@.str.10 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"-" }
@.str.11 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"+42" }
@.str.12 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c" 42" }
@.str.13 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"12abc" }
@.str.14 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c", " }
@.str.15 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }

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

define internal ptr @v_render(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.11 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v_r, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = call ptr @__alloc(i64 16, i32 1)
  %t8 = inttoptr i64 4 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = getelementptr ptr, ptr %t7, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t10
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_r)
  ret ptr %t7
case.arm.4.11:
  %t12 = getelementptr ptr, ptr %v_r, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @__showInt32(ptr %t13)
  %t15 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t14)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %v_r)
  ret ptr %t15
case.default.3:
  unreachable
}

define internal ptr @v_main() {
  %t0 = call ptr @__parseInt32(ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
  %t1 = call ptr @v_render(ptr %t0)
  %t2 = getelementptr ptr, ptr %t1, i32 0
  %t3 = load ptr, ptr %t2
  %t4 = ptrtoint ptr %t3 to i64
  switch i64 %t4, label %case.default.5 [ i64 3, label %case.arm.3.7 i64 4, label %case.arm.4.15 ]
case.arm.3.7:
  %t9 = getelementptr ptr, ptr %t1, i32 1
  %t10 = load ptr, ptr %t9
  call void @__inc_ref(ptr %t10)
  %t11 = call ptr @__alloc(i64 16, i32 1)
  %t12 = inttoptr i64 3 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  call void @__inc_ref(ptr %t10)
  %t14 = getelementptr ptr, ptr %t11, i32 1
  store ptr %t10, ptr %t14
  br label %case.end.3.8
case.end.3.8:
  br label %case.join.6
case.arm.4.15:
  %t17 = getelementptr ptr, ptr %t1, i32 1
  %t18 = load ptr, ptr %t17
  call void @__inc_ref(ptr %t18)
  %t19 = call ptr @__parseInt32(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12))
  %t20 = call ptr @v_render(ptr %t19)
  %t21 = getelementptr ptr, ptr %t20, i32 0
  %t22 = load ptr, ptr %t21
  %t23 = ptrtoint ptr %t22 to i64
  switch i64 %t23, label %case.default.24 [ i64 3, label %case.arm.3.26 i64 4, label %case.arm.4.34 ]
case.arm.3.26:
  %t28 = getelementptr ptr, ptr %t20, i32 1
  %t29 = load ptr, ptr %t28
  call void @__inc_ref(ptr %t29)
  %t30 = call ptr @__alloc(i64 16, i32 1)
  %t31 = inttoptr i64 3 to ptr
  %t32 = getelementptr ptr, ptr %t30, i32 0
  store ptr %t31, ptr %t32
  call void @__inc_ref(ptr %t29)
  %t33 = getelementptr ptr, ptr %t30, i32 1
  store ptr %t29, ptr %t33
  br label %case.end.3.27
case.end.3.27:
  br label %case.join.25
case.arm.4.34:
  %t36 = getelementptr ptr, ptr %t20, i32 1
  %t37 = load ptr, ptr %t36
  call void @__inc_ref(ptr %t37)
  %t38 = call ptr @__parseInt32(ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  %t39 = call ptr @v_render(ptr %t38)
  %t40 = getelementptr ptr, ptr %t39, i32 0
  %t41 = load ptr, ptr %t40
  %t42 = ptrtoint ptr %t41 to i64
  switch i64 %t42, label %case.default.43 [ i64 3, label %case.arm.3.45 i64 4, label %case.arm.4.53 ]
case.arm.3.45:
  %t47 = getelementptr ptr, ptr %t39, i32 1
  %t48 = load ptr, ptr %t47
  call void @__inc_ref(ptr %t48)
  %t49 = call ptr @__alloc(i64 16, i32 1)
  %t50 = inttoptr i64 3 to ptr
  %t51 = getelementptr ptr, ptr %t49, i32 0
  store ptr %t50, ptr %t51
  call void @__inc_ref(ptr %t48)
  %t52 = getelementptr ptr, ptr %t49, i32 1
  store ptr %t48, ptr %t52
  br label %case.end.3.46
case.end.3.46:
  br label %case.join.44
case.arm.4.53:
  %t55 = getelementptr ptr, ptr %t39, i32 1
  %t56 = load ptr, ptr %t55
  call void @__inc_ref(ptr %t56)
  %t57 = call ptr @__parseInt32(ptr getelementptr inbounds (i8, ptr @.str.5, i64 12))
  %t58 = call ptr @v_render(ptr %t57)
  %t59 = getelementptr ptr, ptr %t58, i32 0
  %t60 = load ptr, ptr %t59
  %t61 = ptrtoint ptr %t60 to i64
  switch i64 %t61, label %case.default.62 [ i64 3, label %case.arm.3.64 i64 4, label %case.arm.4.72 ]
case.arm.3.64:
  %t66 = getelementptr ptr, ptr %t58, i32 1
  %t67 = load ptr, ptr %t66
  call void @__inc_ref(ptr %t67)
  %t68 = call ptr @__alloc(i64 16, i32 1)
  %t69 = inttoptr i64 3 to ptr
  %t70 = getelementptr ptr, ptr %t68, i32 0
  store ptr %t69, ptr %t70
  call void @__inc_ref(ptr %t67)
  %t71 = getelementptr ptr, ptr %t68, i32 1
  store ptr %t67, ptr %t71
  br label %case.end.3.65
case.end.3.65:
  br label %case.join.63
case.arm.4.72:
  %t74 = getelementptr ptr, ptr %t58, i32 1
  %t75 = load ptr, ptr %t74
  call void @__inc_ref(ptr %t75)
  %t76 = call ptr @__parseInt32(ptr getelementptr inbounds (i8, ptr @.str.6, i64 12))
  %t77 = call ptr @v_render(ptr %t76)
  %t78 = getelementptr ptr, ptr %t77, i32 0
  %t79 = load ptr, ptr %t78
  %t80 = ptrtoint ptr %t79 to i64
  switch i64 %t80, label %case.default.81 [ i64 3, label %case.arm.3.83 i64 4, label %case.arm.4.91 ]
case.arm.3.83:
  %t85 = getelementptr ptr, ptr %t77, i32 1
  %t86 = load ptr, ptr %t85
  call void @__inc_ref(ptr %t86)
  %t87 = call ptr @__alloc(i64 16, i32 1)
  %t88 = inttoptr i64 3 to ptr
  %t89 = getelementptr ptr, ptr %t87, i32 0
  store ptr %t88, ptr %t89
  call void @__inc_ref(ptr %t86)
  %t90 = getelementptr ptr, ptr %t87, i32 1
  store ptr %t86, ptr %t90
  br label %case.end.3.84
case.end.3.84:
  br label %case.join.82
case.arm.4.91:
  %t93 = getelementptr ptr, ptr %t77, i32 1
  %t94 = load ptr, ptr %t93
  call void @__inc_ref(ptr %t94)
  %t95 = call ptr @__parseInt32(ptr getelementptr inbounds (i8, ptr @.str.7, i64 12))
  %t96 = call ptr @v_render(ptr %t95)
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
  %t114 = call ptr @__parseInt32(ptr getelementptr inbounds (i8, ptr @.str.8, i64 12))
  %t115 = call ptr @v_render(ptr %t114)
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
  %t133 = call ptr @__parseInt32(ptr getelementptr inbounds (i8, ptr @.str.9, i64 12))
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
  %t152 = call ptr @__parseInt32(ptr getelementptr inbounds (i8, ptr @.str.10, i64 12))
  %t153 = call ptr @v_render(ptr %t152)
  %t154 = getelementptr ptr, ptr %t153, i32 0
  %t155 = load ptr, ptr %t154
  %t156 = ptrtoint ptr %t155 to i64
  switch i64 %t156, label %case.default.157 [ i64 3, label %case.arm.3.159 i64 4, label %case.arm.4.167 ]
case.arm.3.159:
  %t161 = getelementptr ptr, ptr %t153, i32 1
  %t162 = load ptr, ptr %t161
  call void @__inc_ref(ptr %t162)
  %t163 = call ptr @__alloc(i64 16, i32 1)
  %t164 = inttoptr i64 3 to ptr
  %t165 = getelementptr ptr, ptr %t163, i32 0
  store ptr %t164, ptr %t165
  call void @__inc_ref(ptr %t162)
  %t166 = getelementptr ptr, ptr %t163, i32 1
  store ptr %t162, ptr %t166
  br label %case.end.3.160
case.end.3.160:
  br label %case.join.158
case.arm.4.167:
  %t169 = getelementptr ptr, ptr %t153, i32 1
  %t170 = load ptr, ptr %t169
  call void @__inc_ref(ptr %t170)
  %t171 = call ptr @__parseInt32(ptr getelementptr inbounds (i8, ptr @.str.11, i64 12))
  %t172 = call ptr @v_render(ptr %t171)
  %t173 = getelementptr ptr, ptr %t172, i32 0
  %t174 = load ptr, ptr %t173
  %t175 = ptrtoint ptr %t174 to i64
  switch i64 %t175, label %case.default.176 [ i64 3, label %case.arm.3.178 i64 4, label %case.arm.4.186 ]
case.arm.3.178:
  %t180 = getelementptr ptr, ptr %t172, i32 1
  %t181 = load ptr, ptr %t180
  call void @__inc_ref(ptr %t181)
  %t182 = call ptr @__alloc(i64 16, i32 1)
  %t183 = inttoptr i64 3 to ptr
  %t184 = getelementptr ptr, ptr %t182, i32 0
  store ptr %t183, ptr %t184
  call void @__inc_ref(ptr %t181)
  %t185 = getelementptr ptr, ptr %t182, i32 1
  store ptr %t181, ptr %t185
  br label %case.end.3.179
case.end.3.179:
  br label %case.join.177
case.arm.4.186:
  %t188 = getelementptr ptr, ptr %t172, i32 1
  %t189 = load ptr, ptr %t188
  call void @__inc_ref(ptr %t189)
  %t190 = call ptr @__parseInt32(ptr getelementptr inbounds (i8, ptr @.str.12, i64 12))
  %t191 = call ptr @v_render(ptr %t190)
  %t192 = getelementptr ptr, ptr %t191, i32 0
  %t193 = load ptr, ptr %t192
  %t194 = ptrtoint ptr %t193 to i64
  switch i64 %t194, label %case.default.195 [ i64 3, label %case.arm.3.197 i64 4, label %case.arm.4.205 ]
case.arm.3.197:
  %t199 = getelementptr ptr, ptr %t191, i32 1
  %t200 = load ptr, ptr %t199
  call void @__inc_ref(ptr %t200)
  %t201 = call ptr @__alloc(i64 16, i32 1)
  %t202 = inttoptr i64 3 to ptr
  %t203 = getelementptr ptr, ptr %t201, i32 0
  store ptr %t202, ptr %t203
  call void @__inc_ref(ptr %t200)
  %t204 = getelementptr ptr, ptr %t201, i32 1
  store ptr %t200, ptr %t204
  br label %case.end.3.198
case.end.3.198:
  br label %case.join.196
case.arm.4.205:
  %t207 = getelementptr ptr, ptr %t191, i32 1
  %t208 = load ptr, ptr %t207
  call void @__inc_ref(ptr %t208)
  %t209 = call ptr @__parseInt32(ptr getelementptr inbounds (i8, ptr @.str.13, i64 12))
  %t210 = call ptr @v_render(ptr %t209)
  %t211 = getelementptr ptr, ptr %t210, i32 0
  %t212 = load ptr, ptr %t211
  %t213 = ptrtoint ptr %t212 to i64
  switch i64 %t213, label %case.default.214 [ i64 3, label %case.arm.3.216 i64 4, label %case.arm.4.224 ]
case.arm.3.216:
  %t218 = getelementptr ptr, ptr %t210, i32 1
  %t219 = load ptr, ptr %t218
  call void @__inc_ref(ptr %t219)
  %t220 = call ptr @__alloc(i64 16, i32 1)
  %t221 = inttoptr i64 3 to ptr
  %t222 = getelementptr ptr, ptr %t220, i32 0
  store ptr %t221, ptr %t222
  call void @__inc_ref(ptr %t219)
  %t223 = getelementptr ptr, ptr %t220, i32 1
  store ptr %t219, ptr %t223
  br label %case.end.3.217
case.end.3.217:
  br label %case.join.215
case.arm.4.224:
  %t226 = getelementptr ptr, ptr %t210, i32 1
  %t227 = load ptr, ptr %t226
  call void @__inc_ref(ptr %t227)
  call void @__inc_ref(ptr %t18)
  %t228 = call ptr @__concat(ptr %t18, ptr getelementptr inbounds (i8, ptr @.str.14, i64 12))
  %t229 = getelementptr ptr, ptr %t228, i32 0
  %t230 = load ptr, ptr %t229
  %t231 = ptrtoint ptr %t230 to i64
  switch i64 %t231, label %case.default.232 [ i64 3, label %case.arm.3.234 i64 4, label %case.arm.4.242 ]
case.arm.3.234:
  %t236 = getelementptr ptr, ptr %t228, i32 1
  %t237 = load ptr, ptr %t236
  call void @__inc_ref(ptr %t237)
  %t238 = call ptr @__alloc(i64 16, i32 1)
  %t239 = inttoptr i64 3 to ptr
  %t240 = getelementptr ptr, ptr %t238, i32 0
  store ptr %t239, ptr %t240
  call void @__inc_ref(ptr %t237)
  %t241 = getelementptr ptr, ptr %t238, i32 1
  store ptr %t237, ptr %t241
  br label %case.end.3.235
case.end.3.235:
  br label %case.join.233
case.arm.4.242:
  %t244 = getelementptr ptr, ptr %t228, i32 1
  %t245 = load ptr, ptr %t244
  call void @__inc_ref(ptr %t245)
  call void @__inc_ref(ptr %t245)
  call void @__inc_ref(ptr %t37)
  %t246 = call ptr @__concat(ptr %t245, ptr %t37)
  %t247 = getelementptr ptr, ptr %t246, i32 0
  %t248 = load ptr, ptr %t247
  %t249 = ptrtoint ptr %t248 to i64
  switch i64 %t249, label %case.default.250 [ i64 3, label %case.arm.3.252 i64 4, label %case.arm.4.260 ]
case.arm.3.252:
  %t254 = getelementptr ptr, ptr %t246, i32 1
  %t255 = load ptr, ptr %t254
  call void @__inc_ref(ptr %t255)
  %t256 = call ptr @__alloc(i64 16, i32 1)
  %t257 = inttoptr i64 3 to ptr
  %t258 = getelementptr ptr, ptr %t256, i32 0
  store ptr %t257, ptr %t258
  call void @__inc_ref(ptr %t255)
  %t259 = getelementptr ptr, ptr %t256, i32 1
  store ptr %t255, ptr %t259
  br label %case.end.3.253
case.end.3.253:
  br label %case.join.251
case.arm.4.260:
  %t262 = getelementptr ptr, ptr %t246, i32 1
  %t263 = load ptr, ptr %t262
  call void @__inc_ref(ptr %t263)
  call void @__inc_ref(ptr %t263)
  %t264 = call ptr @__concat(ptr %t263, ptr getelementptr inbounds (i8, ptr @.str.14, i64 12))
  %t265 = getelementptr ptr, ptr %t264, i32 0
  %t266 = load ptr, ptr %t265
  %t267 = ptrtoint ptr %t266 to i64
  switch i64 %t267, label %case.default.268 [ i64 3, label %case.arm.3.270 i64 4, label %case.arm.4.278 ]
case.arm.3.270:
  %t272 = getelementptr ptr, ptr %t264, i32 1
  %t273 = load ptr, ptr %t272
  call void @__inc_ref(ptr %t273)
  %t274 = call ptr @__alloc(i64 16, i32 1)
  %t275 = inttoptr i64 3 to ptr
  %t276 = getelementptr ptr, ptr %t274, i32 0
  store ptr %t275, ptr %t276
  call void @__inc_ref(ptr %t273)
  %t277 = getelementptr ptr, ptr %t274, i32 1
  store ptr %t273, ptr %t277
  br label %case.end.3.271
case.end.3.271:
  br label %case.join.269
case.arm.4.278:
  %t280 = getelementptr ptr, ptr %t264, i32 1
  %t281 = load ptr, ptr %t280
  call void @__inc_ref(ptr %t281)
  call void @__inc_ref(ptr %t281)
  call void @__inc_ref(ptr %t56)
  %t282 = call ptr @__concat(ptr %t281, ptr %t56)
  %t283 = getelementptr ptr, ptr %t282, i32 0
  %t284 = load ptr, ptr %t283
  %t285 = ptrtoint ptr %t284 to i64
  switch i64 %t285, label %case.default.286 [ i64 3, label %case.arm.3.288 i64 4, label %case.arm.4.296 ]
case.arm.3.288:
  %t290 = getelementptr ptr, ptr %t282, i32 1
  %t291 = load ptr, ptr %t290
  call void @__inc_ref(ptr %t291)
  %t292 = call ptr @__alloc(i64 16, i32 1)
  %t293 = inttoptr i64 3 to ptr
  %t294 = getelementptr ptr, ptr %t292, i32 0
  store ptr %t293, ptr %t294
  call void @__inc_ref(ptr %t291)
  %t295 = getelementptr ptr, ptr %t292, i32 1
  store ptr %t291, ptr %t295
  br label %case.end.3.289
case.end.3.289:
  br label %case.join.287
case.arm.4.296:
  %t298 = getelementptr ptr, ptr %t282, i32 1
  %t299 = load ptr, ptr %t298
  call void @__inc_ref(ptr %t299)
  call void @__inc_ref(ptr %t299)
  %t300 = call ptr @__concat(ptr %t299, ptr getelementptr inbounds (i8, ptr @.str.14, i64 12))
  %t301 = getelementptr ptr, ptr %t300, i32 0
  %t302 = load ptr, ptr %t301
  %t303 = ptrtoint ptr %t302 to i64
  switch i64 %t303, label %case.default.304 [ i64 3, label %case.arm.3.306 i64 4, label %case.arm.4.314 ]
case.arm.3.306:
  %t308 = getelementptr ptr, ptr %t300, i32 1
  %t309 = load ptr, ptr %t308
  call void @__inc_ref(ptr %t309)
  %t310 = call ptr @__alloc(i64 16, i32 1)
  %t311 = inttoptr i64 3 to ptr
  %t312 = getelementptr ptr, ptr %t310, i32 0
  store ptr %t311, ptr %t312
  call void @__inc_ref(ptr %t309)
  %t313 = getelementptr ptr, ptr %t310, i32 1
  store ptr %t309, ptr %t313
  br label %case.end.3.307
case.end.3.307:
  br label %case.join.305
case.arm.4.314:
  %t316 = getelementptr ptr, ptr %t300, i32 1
  %t317 = load ptr, ptr %t316
  call void @__inc_ref(ptr %t317)
  call void @__inc_ref(ptr %t317)
  call void @__inc_ref(ptr %t75)
  %t318 = call ptr @__concat(ptr %t317, ptr %t75)
  %t319 = getelementptr ptr, ptr %t318, i32 0
  %t320 = load ptr, ptr %t319
  %t321 = ptrtoint ptr %t320 to i64
  switch i64 %t321, label %case.default.322 [ i64 3, label %case.arm.3.324 i64 4, label %case.arm.4.332 ]
case.arm.3.324:
  %t326 = getelementptr ptr, ptr %t318, i32 1
  %t327 = load ptr, ptr %t326
  call void @__inc_ref(ptr %t327)
  %t328 = call ptr @__alloc(i64 16, i32 1)
  %t329 = inttoptr i64 3 to ptr
  %t330 = getelementptr ptr, ptr %t328, i32 0
  store ptr %t329, ptr %t330
  call void @__inc_ref(ptr %t327)
  %t331 = getelementptr ptr, ptr %t328, i32 1
  store ptr %t327, ptr %t331
  br label %case.end.3.325
case.end.3.325:
  br label %case.join.323
case.arm.4.332:
  %t334 = getelementptr ptr, ptr %t318, i32 1
  %t335 = load ptr, ptr %t334
  call void @__inc_ref(ptr %t335)
  call void @__inc_ref(ptr %t335)
  %t336 = call ptr @__concat(ptr %t335, ptr getelementptr inbounds (i8, ptr @.str.14, i64 12))
  %t337 = getelementptr ptr, ptr %t336, i32 0
  %t338 = load ptr, ptr %t337
  %t339 = ptrtoint ptr %t338 to i64
  switch i64 %t339, label %case.default.340 [ i64 3, label %case.arm.3.342 i64 4, label %case.arm.4.350 ]
case.arm.3.342:
  %t344 = getelementptr ptr, ptr %t336, i32 1
  %t345 = load ptr, ptr %t344
  call void @__inc_ref(ptr %t345)
  %t346 = call ptr @__alloc(i64 16, i32 1)
  %t347 = inttoptr i64 3 to ptr
  %t348 = getelementptr ptr, ptr %t346, i32 0
  store ptr %t347, ptr %t348
  call void @__inc_ref(ptr %t345)
  %t349 = getelementptr ptr, ptr %t346, i32 1
  store ptr %t345, ptr %t349
  br label %case.end.3.343
case.end.3.343:
  br label %case.join.341
case.arm.4.350:
  %t352 = getelementptr ptr, ptr %t336, i32 1
  %t353 = load ptr, ptr %t352
  call void @__inc_ref(ptr %t353)
  call void @__inc_ref(ptr %t353)
  call void @__inc_ref(ptr %t94)
  %t354 = call ptr @__concat(ptr %t353, ptr %t94)
  %t355 = getelementptr ptr, ptr %t354, i32 0
  %t356 = load ptr, ptr %t355
  %t357 = ptrtoint ptr %t356 to i64
  switch i64 %t357, label %case.default.358 [ i64 3, label %case.arm.3.360 i64 4, label %case.arm.4.368 ]
case.arm.3.360:
  %t362 = getelementptr ptr, ptr %t354, i32 1
  %t363 = load ptr, ptr %t362
  call void @__inc_ref(ptr %t363)
  %t364 = call ptr @__alloc(i64 16, i32 1)
  %t365 = inttoptr i64 3 to ptr
  %t366 = getelementptr ptr, ptr %t364, i32 0
  store ptr %t365, ptr %t366
  call void @__inc_ref(ptr %t363)
  %t367 = getelementptr ptr, ptr %t364, i32 1
  store ptr %t363, ptr %t367
  br label %case.end.3.361
case.end.3.361:
  br label %case.join.359
case.arm.4.368:
  %t370 = getelementptr ptr, ptr %t354, i32 1
  %t371 = load ptr, ptr %t370
  call void @__inc_ref(ptr %t371)
  call void @__inc_ref(ptr %t371)
  %t372 = call ptr @__concat(ptr %t371, ptr getelementptr inbounds (i8, ptr @.str.14, i64 12))
  %t373 = getelementptr ptr, ptr %t372, i32 0
  %t374 = load ptr, ptr %t373
  %t375 = ptrtoint ptr %t374 to i64
  switch i64 %t375, label %case.default.376 [ i64 3, label %case.arm.3.378 i64 4, label %case.arm.4.386 ]
case.arm.3.378:
  %t380 = getelementptr ptr, ptr %t372, i32 1
  %t381 = load ptr, ptr %t380
  call void @__inc_ref(ptr %t381)
  %t382 = call ptr @__alloc(i64 16, i32 1)
  %t383 = inttoptr i64 3 to ptr
  %t384 = getelementptr ptr, ptr %t382, i32 0
  store ptr %t383, ptr %t384
  call void @__inc_ref(ptr %t381)
  %t385 = getelementptr ptr, ptr %t382, i32 1
  store ptr %t381, ptr %t385
  br label %case.end.3.379
case.end.3.379:
  br label %case.join.377
case.arm.4.386:
  %t388 = getelementptr ptr, ptr %t372, i32 1
  %t389 = load ptr, ptr %t388
  call void @__inc_ref(ptr %t389)
  call void @__inc_ref(ptr %t389)
  call void @__inc_ref(ptr %t113)
  %t390 = call ptr @__concat(ptr %t389, ptr %t113)
  %t391 = getelementptr ptr, ptr %t390, i32 0
  %t392 = load ptr, ptr %t391
  %t393 = ptrtoint ptr %t392 to i64
  switch i64 %t393, label %case.default.394 [ i64 3, label %case.arm.3.396 i64 4, label %case.arm.4.404 ]
case.arm.3.396:
  %t398 = getelementptr ptr, ptr %t390, i32 1
  %t399 = load ptr, ptr %t398
  call void @__inc_ref(ptr %t399)
  %t400 = call ptr @__alloc(i64 16, i32 1)
  %t401 = inttoptr i64 3 to ptr
  %t402 = getelementptr ptr, ptr %t400, i32 0
  store ptr %t401, ptr %t402
  call void @__inc_ref(ptr %t399)
  %t403 = getelementptr ptr, ptr %t400, i32 1
  store ptr %t399, ptr %t403
  br label %case.end.3.397
case.end.3.397:
  br label %case.join.395
case.arm.4.404:
  %t406 = getelementptr ptr, ptr %t390, i32 1
  %t407 = load ptr, ptr %t406
  call void @__inc_ref(ptr %t407)
  call void @__inc_ref(ptr %t407)
  %t408 = call ptr @__concat(ptr %t407, ptr getelementptr inbounds (i8, ptr @.str.14, i64 12))
  %t409 = getelementptr ptr, ptr %t408, i32 0
  %t410 = load ptr, ptr %t409
  %t411 = ptrtoint ptr %t410 to i64
  switch i64 %t411, label %case.default.412 [ i64 3, label %case.arm.3.414 i64 4, label %case.arm.4.422 ]
case.arm.3.414:
  %t416 = getelementptr ptr, ptr %t408, i32 1
  %t417 = load ptr, ptr %t416
  call void @__inc_ref(ptr %t417)
  %t418 = call ptr @__alloc(i64 16, i32 1)
  %t419 = inttoptr i64 3 to ptr
  %t420 = getelementptr ptr, ptr %t418, i32 0
  store ptr %t419, ptr %t420
  call void @__inc_ref(ptr %t417)
  %t421 = getelementptr ptr, ptr %t418, i32 1
  store ptr %t417, ptr %t421
  br label %case.end.3.415
case.end.3.415:
  br label %case.join.413
case.arm.4.422:
  %t424 = getelementptr ptr, ptr %t408, i32 1
  %t425 = load ptr, ptr %t424
  call void @__inc_ref(ptr %t425)
  call void @__inc_ref(ptr %t425)
  call void @__inc_ref(ptr %t132)
  %t426 = call ptr @__concat(ptr %t425, ptr %t132)
  %t427 = getelementptr ptr, ptr %t426, i32 0
  %t428 = load ptr, ptr %t427
  %t429 = ptrtoint ptr %t428 to i64
  switch i64 %t429, label %case.default.430 [ i64 3, label %case.arm.3.432 i64 4, label %case.arm.4.440 ]
case.arm.3.432:
  %t434 = getelementptr ptr, ptr %t426, i32 1
  %t435 = load ptr, ptr %t434
  call void @__inc_ref(ptr %t435)
  %t436 = call ptr @__alloc(i64 16, i32 1)
  %t437 = inttoptr i64 3 to ptr
  %t438 = getelementptr ptr, ptr %t436, i32 0
  store ptr %t437, ptr %t438
  call void @__inc_ref(ptr %t435)
  %t439 = getelementptr ptr, ptr %t436, i32 1
  store ptr %t435, ptr %t439
  br label %case.end.3.433
case.end.3.433:
  br label %case.join.431
case.arm.4.440:
  %t442 = getelementptr ptr, ptr %t426, i32 1
  %t443 = load ptr, ptr %t442
  call void @__inc_ref(ptr %t443)
  call void @__inc_ref(ptr %t443)
  %t444 = call ptr @__concat(ptr %t443, ptr getelementptr inbounds (i8, ptr @.str.14, i64 12))
  %t445 = getelementptr ptr, ptr %t444, i32 0
  %t446 = load ptr, ptr %t445
  %t447 = ptrtoint ptr %t446 to i64
  switch i64 %t447, label %case.default.448 [ i64 3, label %case.arm.3.450 i64 4, label %case.arm.4.458 ]
case.arm.3.450:
  %t452 = getelementptr ptr, ptr %t444, i32 1
  %t453 = load ptr, ptr %t452
  call void @__inc_ref(ptr %t453)
  %t454 = call ptr @__alloc(i64 16, i32 1)
  %t455 = inttoptr i64 3 to ptr
  %t456 = getelementptr ptr, ptr %t454, i32 0
  store ptr %t455, ptr %t456
  call void @__inc_ref(ptr %t453)
  %t457 = getelementptr ptr, ptr %t454, i32 1
  store ptr %t453, ptr %t457
  br label %case.end.3.451
case.end.3.451:
  br label %case.join.449
case.arm.4.458:
  %t460 = getelementptr ptr, ptr %t444, i32 1
  %t461 = load ptr, ptr %t460
  call void @__inc_ref(ptr %t461)
  call void @__inc_ref(ptr %t461)
  call void @__inc_ref(ptr %t151)
  %t462 = call ptr @__concat(ptr %t461, ptr %t151)
  %t463 = getelementptr ptr, ptr %t462, i32 0
  %t464 = load ptr, ptr %t463
  %t465 = ptrtoint ptr %t464 to i64
  switch i64 %t465, label %case.default.466 [ i64 3, label %case.arm.3.468 i64 4, label %case.arm.4.476 ]
case.arm.3.468:
  %t470 = getelementptr ptr, ptr %t462, i32 1
  %t471 = load ptr, ptr %t470
  call void @__inc_ref(ptr %t471)
  %t472 = call ptr @__alloc(i64 16, i32 1)
  %t473 = inttoptr i64 3 to ptr
  %t474 = getelementptr ptr, ptr %t472, i32 0
  store ptr %t473, ptr %t474
  call void @__inc_ref(ptr %t471)
  %t475 = getelementptr ptr, ptr %t472, i32 1
  store ptr %t471, ptr %t475
  br label %case.end.3.469
case.end.3.469:
  br label %case.join.467
case.arm.4.476:
  %t478 = getelementptr ptr, ptr %t462, i32 1
  %t479 = load ptr, ptr %t478
  call void @__inc_ref(ptr %t479)
  call void @__inc_ref(ptr %t479)
  %t480 = call ptr @__concat(ptr %t479, ptr getelementptr inbounds (i8, ptr @.str.14, i64 12))
  %t481 = getelementptr ptr, ptr %t480, i32 0
  %t482 = load ptr, ptr %t481
  %t483 = ptrtoint ptr %t482 to i64
  switch i64 %t483, label %case.default.484 [ i64 3, label %case.arm.3.486 i64 4, label %case.arm.4.494 ]
case.arm.3.486:
  %t488 = getelementptr ptr, ptr %t480, i32 1
  %t489 = load ptr, ptr %t488
  call void @__inc_ref(ptr %t489)
  %t490 = call ptr @__alloc(i64 16, i32 1)
  %t491 = inttoptr i64 3 to ptr
  %t492 = getelementptr ptr, ptr %t490, i32 0
  store ptr %t491, ptr %t492
  call void @__inc_ref(ptr %t489)
  %t493 = getelementptr ptr, ptr %t490, i32 1
  store ptr %t489, ptr %t493
  br label %case.end.3.487
case.end.3.487:
  br label %case.join.485
case.arm.4.494:
  %t496 = getelementptr ptr, ptr %t480, i32 1
  %t497 = load ptr, ptr %t496
  call void @__inc_ref(ptr %t497)
  call void @__inc_ref(ptr %t497)
  call void @__inc_ref(ptr %t170)
  %t498 = call ptr @__concat(ptr %t497, ptr %t170)
  %t499 = getelementptr ptr, ptr %t498, i32 0
  %t500 = load ptr, ptr %t499
  %t501 = ptrtoint ptr %t500 to i64
  switch i64 %t501, label %case.default.502 [ i64 3, label %case.arm.3.504 i64 4, label %case.arm.4.512 ]
case.arm.3.504:
  %t506 = getelementptr ptr, ptr %t498, i32 1
  %t507 = load ptr, ptr %t506
  call void @__inc_ref(ptr %t507)
  %t508 = call ptr @__alloc(i64 16, i32 1)
  %t509 = inttoptr i64 3 to ptr
  %t510 = getelementptr ptr, ptr %t508, i32 0
  store ptr %t509, ptr %t510
  call void @__inc_ref(ptr %t507)
  %t511 = getelementptr ptr, ptr %t508, i32 1
  store ptr %t507, ptr %t511
  br label %case.end.3.505
case.end.3.505:
  br label %case.join.503
case.arm.4.512:
  %t514 = getelementptr ptr, ptr %t498, i32 1
  %t515 = load ptr, ptr %t514
  call void @__inc_ref(ptr %t515)
  call void @__inc_ref(ptr %t515)
  %t516 = call ptr @__concat(ptr %t515, ptr getelementptr inbounds (i8, ptr @.str.14, i64 12))
  %t517 = getelementptr ptr, ptr %t516, i32 0
  %t518 = load ptr, ptr %t517
  %t519 = ptrtoint ptr %t518 to i64
  switch i64 %t519, label %case.default.520 [ i64 3, label %case.arm.3.522 i64 4, label %case.arm.4.530 ]
case.arm.3.522:
  %t524 = getelementptr ptr, ptr %t516, i32 1
  %t525 = load ptr, ptr %t524
  call void @__inc_ref(ptr %t525)
  %t526 = call ptr @__alloc(i64 16, i32 1)
  %t527 = inttoptr i64 3 to ptr
  %t528 = getelementptr ptr, ptr %t526, i32 0
  store ptr %t527, ptr %t528
  call void @__inc_ref(ptr %t525)
  %t529 = getelementptr ptr, ptr %t526, i32 1
  store ptr %t525, ptr %t529
  br label %case.end.3.523
case.end.3.523:
  br label %case.join.521
case.arm.4.530:
  %t532 = getelementptr ptr, ptr %t516, i32 1
  %t533 = load ptr, ptr %t532
  call void @__inc_ref(ptr %t533)
  call void @__inc_ref(ptr %t533)
  call void @__inc_ref(ptr %t189)
  %t534 = call ptr @__concat(ptr %t533, ptr %t189)
  %t535 = getelementptr ptr, ptr %t534, i32 0
  %t536 = load ptr, ptr %t535
  %t537 = ptrtoint ptr %t536 to i64
  switch i64 %t537, label %case.default.538 [ i64 3, label %case.arm.3.540 i64 4, label %case.arm.4.548 ]
case.arm.3.540:
  %t542 = getelementptr ptr, ptr %t534, i32 1
  %t543 = load ptr, ptr %t542
  call void @__inc_ref(ptr %t543)
  %t544 = call ptr @__alloc(i64 16, i32 1)
  %t545 = inttoptr i64 3 to ptr
  %t546 = getelementptr ptr, ptr %t544, i32 0
  store ptr %t545, ptr %t546
  call void @__inc_ref(ptr %t543)
  %t547 = getelementptr ptr, ptr %t544, i32 1
  store ptr %t543, ptr %t547
  br label %case.end.3.541
case.end.3.541:
  br label %case.join.539
case.arm.4.548:
  %t550 = getelementptr ptr, ptr %t534, i32 1
  %t551 = load ptr, ptr %t550
  call void @__inc_ref(ptr %t551)
  call void @__inc_ref(ptr %t551)
  %t552 = call ptr @__concat(ptr %t551, ptr getelementptr inbounds (i8, ptr @.str.14, i64 12))
  %t553 = getelementptr ptr, ptr %t552, i32 0
  %t554 = load ptr, ptr %t553
  %t555 = ptrtoint ptr %t554 to i64
  switch i64 %t555, label %case.default.556 [ i64 3, label %case.arm.3.558 i64 4, label %case.arm.4.566 ]
case.arm.3.558:
  %t560 = getelementptr ptr, ptr %t552, i32 1
  %t561 = load ptr, ptr %t560
  call void @__inc_ref(ptr %t561)
  %t562 = call ptr @__alloc(i64 16, i32 1)
  %t563 = inttoptr i64 3 to ptr
  %t564 = getelementptr ptr, ptr %t562, i32 0
  store ptr %t563, ptr %t564
  call void @__inc_ref(ptr %t561)
  %t565 = getelementptr ptr, ptr %t562, i32 1
  store ptr %t561, ptr %t565
  br label %case.end.3.559
case.end.3.559:
  br label %case.join.557
case.arm.4.566:
  %t568 = getelementptr ptr, ptr %t552, i32 1
  %t569 = load ptr, ptr %t568
  call void @__inc_ref(ptr %t569)
  call void @__inc_ref(ptr %t569)
  call void @__inc_ref(ptr %t208)
  %t570 = call ptr @__concat(ptr %t569, ptr %t208)
  %t571 = getelementptr ptr, ptr %t570, i32 0
  %t572 = load ptr, ptr %t571
  %t573 = ptrtoint ptr %t572 to i64
  switch i64 %t573, label %case.default.574 [ i64 3, label %case.arm.3.576 i64 4, label %case.arm.4.584 ]
case.arm.3.576:
  %t578 = getelementptr ptr, ptr %t570, i32 1
  %t579 = load ptr, ptr %t578
  call void @__inc_ref(ptr %t579)
  %t580 = call ptr @__alloc(i64 16, i32 1)
  %t581 = inttoptr i64 3 to ptr
  %t582 = getelementptr ptr, ptr %t580, i32 0
  store ptr %t581, ptr %t582
  call void @__inc_ref(ptr %t579)
  %t583 = getelementptr ptr, ptr %t580, i32 1
  store ptr %t579, ptr %t583
  br label %case.end.3.577
case.end.3.577:
  br label %case.join.575
case.arm.4.584:
  %t586 = getelementptr ptr, ptr %t570, i32 1
  %t587 = load ptr, ptr %t586
  call void @__inc_ref(ptr %t587)
  call void @__inc_ref(ptr %t587)
  %t588 = call ptr @__concat(ptr %t587, ptr getelementptr inbounds (i8, ptr @.str.14, i64 12))
  %t589 = getelementptr ptr, ptr %t588, i32 0
  %t590 = load ptr, ptr %t589
  %t591 = ptrtoint ptr %t590 to i64
  switch i64 %t591, label %case.default.592 [ i64 3, label %case.arm.3.594 i64 4, label %case.arm.4.602 ]
case.arm.3.594:
  %t596 = getelementptr ptr, ptr %t588, i32 1
  %t597 = load ptr, ptr %t596
  call void @__inc_ref(ptr %t597)
  %t598 = call ptr @__alloc(i64 16, i32 1)
  %t599 = inttoptr i64 3 to ptr
  %t600 = getelementptr ptr, ptr %t598, i32 0
  store ptr %t599, ptr %t600
  call void @__inc_ref(ptr %t597)
  %t601 = getelementptr ptr, ptr %t598, i32 1
  store ptr %t597, ptr %t601
  br label %case.end.3.595
case.end.3.595:
  br label %case.join.593
case.arm.4.602:
  %t604 = getelementptr ptr, ptr %t588, i32 1
  %t605 = load ptr, ptr %t604
  call void @__inc_ref(ptr %t605)
  call void @__inc_ref(ptr %t605)
  call void @__inc_ref(ptr %t227)
  %t606 = call ptr @__concat(ptr %t605, ptr %t227)
  br label %case.end.4.603
case.end.4.603:
  br label %case.join.593
case.default.592:
  unreachable
case.join.593:
  %t607 = phi ptr [ %t598, %case.end.3.595 ], [ %t606, %case.end.4.603 ]
  call void @__free_recursive(ptr %t588)
  br label %case.end.4.585
case.end.4.585:
  br label %case.join.575
case.default.574:
  unreachable
case.join.575:
  %t608 = phi ptr [ %t580, %case.end.3.577 ], [ %t607, %case.end.4.585 ]
  call void @__free_recursive(ptr %t570)
  br label %case.end.4.567
case.end.4.567:
  br label %case.join.557
case.default.556:
  unreachable
case.join.557:
  %t609 = phi ptr [ %t562, %case.end.3.559 ], [ %t608, %case.end.4.567 ]
  call void @__free_recursive(ptr %t552)
  br label %case.end.4.549
case.end.4.549:
  br label %case.join.539
case.default.538:
  unreachable
case.join.539:
  %t610 = phi ptr [ %t544, %case.end.3.541 ], [ %t609, %case.end.4.549 ]
  call void @__free_recursive(ptr %t534)
  br label %case.end.4.531
case.end.4.531:
  br label %case.join.521
case.default.520:
  unreachable
case.join.521:
  %t611 = phi ptr [ %t526, %case.end.3.523 ], [ %t610, %case.end.4.531 ]
  call void @__free_recursive(ptr %t516)
  br label %case.end.4.513
case.end.4.513:
  br label %case.join.503
case.default.502:
  unreachable
case.join.503:
  %t612 = phi ptr [ %t508, %case.end.3.505 ], [ %t611, %case.end.4.513 ]
  call void @__free_recursive(ptr %t498)
  br label %case.end.4.495
case.end.4.495:
  br label %case.join.485
case.default.484:
  unreachable
case.join.485:
  %t613 = phi ptr [ %t490, %case.end.3.487 ], [ %t612, %case.end.4.495 ]
  call void @__free_recursive(ptr %t480)
  br label %case.end.4.477
case.end.4.477:
  br label %case.join.467
case.default.466:
  unreachable
case.join.467:
  %t614 = phi ptr [ %t472, %case.end.3.469 ], [ %t613, %case.end.4.477 ]
  call void @__free_recursive(ptr %t462)
  br label %case.end.4.459
case.end.4.459:
  br label %case.join.449
case.default.448:
  unreachable
case.join.449:
  %t615 = phi ptr [ %t454, %case.end.3.451 ], [ %t614, %case.end.4.459 ]
  call void @__free_recursive(ptr %t444)
  br label %case.end.4.441
case.end.4.441:
  br label %case.join.431
case.default.430:
  unreachable
case.join.431:
  %t616 = phi ptr [ %t436, %case.end.3.433 ], [ %t615, %case.end.4.441 ]
  call void @__free_recursive(ptr %t426)
  br label %case.end.4.423
case.end.4.423:
  br label %case.join.413
case.default.412:
  unreachable
case.join.413:
  %t617 = phi ptr [ %t418, %case.end.3.415 ], [ %t616, %case.end.4.423 ]
  call void @__free_recursive(ptr %t408)
  br label %case.end.4.405
case.end.4.405:
  br label %case.join.395
case.default.394:
  unreachable
case.join.395:
  %t618 = phi ptr [ %t400, %case.end.3.397 ], [ %t617, %case.end.4.405 ]
  call void @__free_recursive(ptr %t390)
  br label %case.end.4.387
case.end.4.387:
  br label %case.join.377
case.default.376:
  unreachable
case.join.377:
  %t619 = phi ptr [ %t382, %case.end.3.379 ], [ %t618, %case.end.4.387 ]
  call void @__free_recursive(ptr %t372)
  br label %case.end.4.369
case.end.4.369:
  br label %case.join.359
case.default.358:
  unreachable
case.join.359:
  %t620 = phi ptr [ %t364, %case.end.3.361 ], [ %t619, %case.end.4.369 ]
  call void @__free_recursive(ptr %t354)
  br label %case.end.4.351
case.end.4.351:
  br label %case.join.341
case.default.340:
  unreachable
case.join.341:
  %t621 = phi ptr [ %t346, %case.end.3.343 ], [ %t620, %case.end.4.351 ]
  call void @__free_recursive(ptr %t336)
  br label %case.end.4.333
case.end.4.333:
  br label %case.join.323
case.default.322:
  unreachable
case.join.323:
  %t622 = phi ptr [ %t328, %case.end.3.325 ], [ %t621, %case.end.4.333 ]
  call void @__free_recursive(ptr %t318)
  br label %case.end.4.315
case.end.4.315:
  br label %case.join.305
case.default.304:
  unreachable
case.join.305:
  %t623 = phi ptr [ %t310, %case.end.3.307 ], [ %t622, %case.end.4.315 ]
  call void @__free_recursive(ptr %t300)
  br label %case.end.4.297
case.end.4.297:
  br label %case.join.287
case.default.286:
  unreachable
case.join.287:
  %t624 = phi ptr [ %t292, %case.end.3.289 ], [ %t623, %case.end.4.297 ]
  call void @__free_recursive(ptr %t282)
  br label %case.end.4.279
case.end.4.279:
  br label %case.join.269
case.default.268:
  unreachable
case.join.269:
  %t625 = phi ptr [ %t274, %case.end.3.271 ], [ %t624, %case.end.4.279 ]
  call void @__free_recursive(ptr %t264)
  br label %case.end.4.261
case.end.4.261:
  br label %case.join.251
case.default.250:
  unreachable
case.join.251:
  %t626 = phi ptr [ %t256, %case.end.3.253 ], [ %t625, %case.end.4.261 ]
  call void @__free_recursive(ptr %t246)
  br label %case.end.4.243
case.end.4.243:
  br label %case.join.233
case.default.232:
  unreachable
case.join.233:
  %t627 = phi ptr [ %t238, %case.end.3.235 ], [ %t626, %case.end.4.243 ]
  call void @__free_recursive(ptr %t228)
  br label %case.end.4.225
case.end.4.225:
  br label %case.join.215
case.default.214:
  unreachable
case.join.215:
  %t628 = phi ptr [ %t220, %case.end.3.217 ], [ %t627, %case.end.4.225 ]
  call void @__free_recursive(ptr %t210)
  br label %case.end.4.206
case.end.4.206:
  br label %case.join.196
case.default.195:
  unreachable
case.join.196:
  %t629 = phi ptr [ %t201, %case.end.3.198 ], [ %t628, %case.end.4.206 ]
  call void @__free_recursive(ptr %t191)
  br label %case.end.4.187
case.end.4.187:
  br label %case.join.177
case.default.176:
  unreachable
case.join.177:
  %t630 = phi ptr [ %t182, %case.end.3.179 ], [ %t629, %case.end.4.187 ]
  call void @__free_recursive(ptr %t172)
  br label %case.end.4.168
case.end.4.168:
  br label %case.join.158
case.default.157:
  unreachable
case.join.158:
  %t631 = phi ptr [ %t163, %case.end.3.160 ], [ %t630, %case.end.4.168 ]
  call void @__free_recursive(ptr %t153)
  br label %case.end.4.149
case.end.4.149:
  br label %case.join.139
case.default.138:
  unreachable
case.join.139:
  %t632 = phi ptr [ %t144, %case.end.3.141 ], [ %t631, %case.end.4.149 ]
  call void @__free_recursive(ptr %t134)
  br label %case.end.4.130
case.end.4.130:
  br label %case.join.120
case.default.119:
  unreachable
case.join.120:
  %t633 = phi ptr [ %t125, %case.end.3.122 ], [ %t632, %case.end.4.130 ]
  call void @__free_recursive(ptr %t115)
  br label %case.end.4.111
case.end.4.111:
  br label %case.join.101
case.default.100:
  unreachable
case.join.101:
  %t634 = phi ptr [ %t106, %case.end.3.103 ], [ %t633, %case.end.4.111 ]
  call void @__free_recursive(ptr %t96)
  br label %case.end.4.92
case.end.4.92:
  br label %case.join.82
case.default.81:
  unreachable
case.join.82:
  %t635 = phi ptr [ %t87, %case.end.3.84 ], [ %t634, %case.end.4.92 ]
  call void @__free_recursive(ptr %t77)
  br label %case.end.4.73
case.end.4.73:
  br label %case.join.63
case.default.62:
  unreachable
case.join.63:
  %t636 = phi ptr [ %t68, %case.end.3.65 ], [ %t635, %case.end.4.73 ]
  call void @__free_recursive(ptr %t58)
  br label %case.end.4.54
case.end.4.54:
  br label %case.join.44
case.default.43:
  unreachable
case.join.44:
  %t637 = phi ptr [ %t49, %case.end.3.46 ], [ %t636, %case.end.4.54 ]
  call void @__free_recursive(ptr %t39)
  br label %case.end.4.35
case.end.4.35:
  br label %case.join.25
case.default.24:
  unreachable
case.join.25:
  %t638 = phi ptr [ %t30, %case.end.3.27 ], [ %t637, %case.end.4.35 ]
  call void @__free_recursive(ptr %t20)
  br label %case.end.4.16
case.end.4.16:
  br label %case.join.6
case.default.5:
  unreachable
case.join.6:
  %t639 = phi ptr [ %t11, %case.end.3.8 ], [ %t638, %case.end.4.16 ]
  call void @__free_recursive(ptr %t1)
  %t640 = call ptr @v__let_23(ptr %t639)
  ret ptr %t640
}

define internal ptr @v__let_23(ptr %v_res) {
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
  store ptr getelementptr inbounds (i8, ptr @.str.15, i64 12), ptr %t10
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
