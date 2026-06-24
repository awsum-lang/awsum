; External C declarations
declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare ptr @memcpy(ptr, ptr, i64)
declare i64 @write(i32, ptr, i64)
declare i64 @strlen(ptr)

@.cli_argc = internal global i64 0
@.cli_argv = internal global ptr null

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

define internal void @__free(ptr %p) {
  %hdr_ptr = getelementptr i8, ptr %p, i64 -12
  %flag = load i32, ptr %hdr_ptr
  %is_heap = icmp eq i32 %flag, 1
  br i1 %is_heap, label %do_free, label %skip
do_free:
  call void @free(ptr %hdr_ptr)
  br label %skip
skip:
  ret void
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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"x" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"y" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"z" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"UPS" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"STL" }
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"PARSE" }

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


define internal ptr @__predInt32(ptr %p) {
  %v = load i32, ptr %p
  %is_min = icmp eq i32 %v, -2147483648
  br i1 %is_min, label %overflow, label %ok
overflow:
  %oe = call ptr @__alloc(i64 8, i32 0)
  %oe_tag = inttoptr i64 17 to ptr
  store ptr %oe_tag, ptr %oe
  %left = call ptr @__alloc(i64 16, i32 1)
  %left_tag = inttoptr i64 3 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %oe, ptr %left_f
  call void @__free_recursive(ptr %p)
  ret ptr %left
ok:
  %newv = sub i32 %v, 1
  %box = call ptr @__alloc(i64 4, i32 0)
  store i32 %newv, ptr %box
  %right = call ptr @__alloc(i64 16, i32 1)
  %right_tag = inttoptr i64 4 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %box, ptr %right_f
  call void @__free_recursive(ptr %p)
  ret ptr %right
}


define internal ptr @__eqInt32(ptr %a, ptr %b) {
  %va = load i32, ptr %a
  %vb = load i32, ptr %b
  %eq = icmp eq i32 %va, %vb
  %tag = select i1 %eq, i64 1, i64 2
  %box = call ptr @__alloc(i64 8, i32 0)
  %tag_ptr = inttoptr i64 %tag to ptr
  store ptr %tag_ptr, ptr %box
  call void @__free_recursive(ptr %a)
  call void @__free_recursive(ptr %b)
  ret ptr %box
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


define internal ptr @__entryArgEither(ptr %arg, i64 %len) {
entry:
  %i_p = alloca i64, align 8
  store i64 0, ptr %i_p
  %n_p = alloca i32, align 4
  store i32 0, ptr %n_p
  %surr_p = alloca i32, align 4
  store i32 0, ptr %surr_p
  br label %head
head:
  %i = load i64, ptr %i_p
  %done = icmp uge i64 %i, %len
  br i1 %done, label %scan_done, label %body
body:
  %bp = getelementptr i8, ptr %arg, i64 %i
  %b = load i8, ptr %bp
  %bz = zext i8 %b to i32
  %top2 = and i32 %bz, 192
  %is_cont = icmp eq i32 %top2, 128
  br i1 %is_cont, label %step, label %surrogate_check
surrogate_check:
  %is_ED = icmp eq i32 %bz, 237
  br i1 %is_ED, label %peek_next, label %check4
peek_next:
  %i_next = add i64 %i, 1
  %bp_next = getelementptr i8, ptr %arg, i64 %i_next
  %nxt = load i8, ptr %bp_next
  %nxt_z = zext i8 %nxt to i32
  %nxt_top3 = and i32 %nxt_z, 224
  %is_surr = icmp eq i32 %nxt_top3, 160
  br i1 %is_surr, label %set_surr, label %check4
set_surr:
  store i32 1, ptr %surr_p
  br label %check4
check4:
  %top5 = and i32 %bz, 248
  %is_4 = icmp eq i32 %top5, 240
  br i1 %is_4, label %add2, label %add1
add2:
  %n2 = load i32, ptr %n_p
  %n2_new = add i32 %n2, 2
  store i32 %n2_new, ptr %n_p
  %over2 = icmp ugt i32 %n2_new, 134217728
  br i1 %over2, label %scan_done, label %step
add1:
  %n1 = load i32, ptr %n_p
  %n1_new = add i32 %n1, 1
  store i32 %n1_new, ptr %n_p
  %over1 = icmp ugt i32 %n1_new, 134217728
  br i1 %over1, label %scan_done, label %step
step:
  %i1 = add i64 %i, 1
  store i64 %i1, ptr %i_p
  br label %head
scan_done:
  %n_final = load i32, ptr %n_p
  %over_final = icmp ugt i32 %n_final, 134217728
  br i1 %over_final, label %too_long, label %check_surr
check_surr:
  %surr_final = load i32, ptr %surr_p
  %is_surr_set = icmp ne i32 %surr_final, 0
  br i1 %is_surr_set, label %unpaired, label %fits
fits:
  %byte_count_64 = load i64, ptr %i_p
  %byte_count_32 = trunc i64 %byte_count_64 to i32
  %alloc_size_64 = add i64 %byte_count_64, 8
  %wrapped = call ptr @__alloc(i64 %alloc_size_64, i32 0)
  store i32 %byte_count_32, ptr %wrapped
  %wrapped_u16p = getelementptr i8, ptr %wrapped, i64 4
  store i32 %n_final, ptr %wrapped_u16p
  %wrapped_payload = getelementptr i8, ptr %wrapped, i64 8
  call ptr @memcpy(ptr %wrapped_payload, ptr %arg, i64 %byte_count_64)
  %right = call ptr @__alloc(i64 16, i32 1)
  %right_tag = inttoptr i64 4 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %wrapped, ptr %right_f
  ret ptr %right
too_long:
  %tl_inner = call ptr @__alloc(i64 8, i32 0)
  %tl_inner_tag = inttoptr i64 19 to ptr
  store ptr %tl_inner_tag, ptr %tl_inner
  %tl_row = call ptr @__alloc(i64 16, i32 1)
  %tl_row_tag = inttoptr i64 589989748 to ptr
  store ptr %tl_row_tag, ptr %tl_row
  %tl_row_f = getelementptr ptr, ptr %tl_row, i32 1
  store ptr %tl_inner, ptr %tl_row_f
  %tl_left = call ptr @__alloc(i64 16, i32 1)
  %tl_left_tag = inttoptr i64 3 to ptr
  store ptr %tl_left_tag, ptr %tl_left
  %tl_left_f = getelementptr ptr, ptr %tl_left, i32 1
  store ptr %tl_row, ptr %tl_left_f
  ret ptr %tl_left
unpaired:
  %us_inner = call ptr @__alloc(i64 8, i32 0)
  %us_inner_tag = inttoptr i64 20 to ptr
  store ptr %us_inner_tag, ptr %us_inner
  %us_row = call ptr @__alloc(i64 16, i32 1)
  %us_row_tag = inttoptr i64 502975519 to ptr
  store ptr %us_row_tag, ptr %us_row
  %us_row_f = getelementptr ptr, ptr %us_row, i32 1
  store ptr %us_inner, ptr %us_row_f
  %us_left = call ptr @__alloc(i64 16, i32 1)
  %us_left_tag = inttoptr i64 3 to ptr
  store ptr %us_left_tag, ptr %us_left
  %us_left_f = getelementptr ptr, ptr %us_left, i32 1
  store ptr %us_row, ptr %us_left_f
  ret ptr %us_left
}


define internal ptr @__getArgs() {
  %argc = load i64, ptr @.cli_argc
  %argv = load ptr, ptr @.cli_argv
  %i.slot = alloca i64
  %acc.slot = alloca ptr
  %nilC = call ptr @__alloc(i64 8, i32 0)
  %nilC_tag = inttoptr i64 13 to ptr
  store ptr %nilC_tag, ptr %nilC
  store ptr %nilC, ptr %acc.slot
  store i64 %argc, ptr %i.slot
  br label %getargs_loop
getargs_loop:
  %i = load i64, ptr %i.slot
  %at_end = icmp sle i64 %i, 1
  br i1 %at_end, label %getargs_done, label %getargs_body
getargs_body:
  %i.next = sub i64 %i, 1
  store i64 %i.next, ptr %i.slot
  %arg_slot = getelementptr ptr, ptr %argv, i64 %i.next
  %arg = load ptr, ptr %arg_slot
  %len = call i64 @strlen(ptr %arg)
  %either = call ptr @__entryArgEither(ptr %arg, i64 %len)
  %either_tag_ptr = load ptr, ptr %either
  %either_tag = ptrtoint ptr %either_tag_ptr to i64
  %is_left = icmp eq i64 %either_tag, 3
  br i1 %is_left, label %getargs_left, label %getargs_cons
getargs_cons:
  %head_slot = getelementptr ptr, ptr %either, i32 1
  %head = load ptr, ptr %head_slot
  call void @__free(ptr %either)
  %acc = load ptr, ptr %acc.slot
  %consC = call ptr @__alloc(i64 24, i32 2)
  %consC_tag = inttoptr i64 14 to ptr
  store ptr %consC_tag, ptr %consC
  %consC_head_slot = getelementptr ptr, ptr %consC, i32 1
  store ptr %head, ptr %consC_head_slot
  %consC_tail_slot = getelementptr ptr, ptr %consC, i32 2
  store ptr %acc, ptr %consC_tail_slot
  store ptr %consC, ptr %acc.slot
  br label %getargs_loop
getargs_left:
  ret ptr %either
getargs_done:
  %acc.final = load ptr, ptr %acc.slot
  %rightC = call ptr @__alloc(i64 16, i32 1)
  %rightC_tag = inttoptr i64 4 to ptr
  store ptr %rightC_tag, ptr %rightC
  %rightC_field = getelementptr ptr, ptr %rightC, i32 1
  store ptr %acc.final, ptr %rightC_field
  ret ptr %rightC
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
  switch i64 %t7, label %tco.case.default.8 [ i64 5, label %tco.case.arm.5.9 i64 7, label %tco.case.arm.7.12 i64 8, label %tco.case.arm.8.18 ]
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
tco.case.arm.8.18:
  %t19 = call ptr @__getArgs()
  %t20 = call ptr @__alloc(i64 24, i32 2)
  %t21 = inttoptr i64 33 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = getelementptr ptr, ptr %t4, i32 1
  %t24 = load ptr, ptr %t23
  call void @__inc_ref(ptr %t24)
  %t25 = getelementptr ptr, ptr %t20, i32 1
  store ptr %t24, ptr %t25
  call void @__inc_ref(ptr %t19)
  %t26 = getelementptr ptr, ptr %t20, i32 2
  store ptr %t19, ptr %t26
  %t27 = call ptr @__alloc(i64 8, i32 0)
  %t28 = inttoptr i64 40 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  %t30 = call ptr @v_$cps$$scc$$apply1__$df$$lam$13$5__$df$$lam$9$1(ptr %t20, ptr %t27)
  call void @__free_recursive(ptr %t19)
  call void @__free_recursive(ptr %t4)
  store ptr %t30, ptr %t3
  br label %tco.loop.0
tco.case.default.8:
  unreachable
tco.exit.1:
  %t31 = load ptr, ptr %t2
  ret ptr %t31
}

define internal ptr @v_spin(ptr %v_n) {
entry:
  %t3 = alloca ptr
  store ptr %v_n, ptr %t3
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t4 = load ptr, ptr %t3
  call void @__inc_ref(ptr %t4)
  %t5 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t5
  %t6 = call ptr @__eqInt32(ptr %t4, ptr %t5)
  %t7 = getelementptr ptr, ptr %t6, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %tco.case.default.10 [ i64 1, label %tco.case.arm.1.11 i64 2, label %tco.case.arm.2.15 ]
tco.case.arm.1.11:
  call void @__free_recursive(ptr %t6)
  %t12 = call ptr @__alloc(i64 8, i32 0)
  %t13 = inttoptr i64 28 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  call void @__free_recursive(ptr %t4)
  store ptr %t12, ptr %t2
  br label %tco.exit.1
tco.case.arm.2.15:
  call void @__free_recursive(ptr %t6)
  call void @__inc_ref(ptr %t4)
  %t16 = call ptr @__predInt32(ptr %t4)
  %t17 = getelementptr ptr, ptr %t16, i32 0
  %t18 = load ptr, ptr %t17
  %t19 = ptrtoint ptr %t18 to i64
  switch i64 %t19, label %tco.case.default.20 [ i64 3, label %tco.case.arm.3.21 i64 4, label %tco.case.arm.4.25 ]
tco.case.arm.3.21:
  call void @__free_recursive(ptr %t16)
  %t22 = call ptr @__alloc(i64 8, i32 0)
  %t23 = inttoptr i64 28 to ptr
  %t24 = getelementptr ptr, ptr %t22, i32 0
  store ptr %t23, ptr %t24
  call void @__free_recursive(ptr %t4)
  store ptr %t22, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.25:
  %t26 = getelementptr ptr, ptr %t16, i32 1
  %t27 = load ptr, ptr %t26
  call void @__inc_ref(ptr %t27)
  call void @__free_recursive(ptr %t16)
  call void @__free_recursive(ptr %t4)
  store ptr %t27, ptr %t3
  br label %tco.loop.0
tco.case.default.20:
  unreachable
tco.case.default.10:
  unreachable
tco.exit.1:
  %t28 = load ptr, ptr %t2
  ret ptr %t28
}

define internal ptr @v_label(ptr %v_k) {
  %v_$inl1$scrut.jslot = alloca ptr
  call void @__inc_ref(ptr %v_k)
  %t2 = call ptr @__alloc(i64 4, i32 0)
  store i32 7, ptr %t2
  %t3 = call ptr @__eqInt32(ptr %v_k, ptr %t2)
  %t4 = getelementptr ptr, ptr %t3, i32 0
  %t5 = load ptr, ptr %t4
  %t6 = ptrtoint ptr %t5 to i64
  switch i64 %t6, label %join.case.default.7 [ i64 1, label %join.case.arm.1.8 i64 2, label %join.case.arm.2.13 ]
join.case.arm.1.8:
  %t9 = call ptr @__alloc(i64 8, i32 0)
  %t10 = inttoptr i64 27 to ptr
  %t11 = getelementptr ptr, ptr %t9, i32 0
  store ptr %t10, ptr %t11
  call void @__free_recursive(ptr %t3)
  br label %join.val.12
join.val.12:
  br label %join.after.1
join.case.arm.2.13:
  call void @__inc_ref(ptr %v_k)
  %t14 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t14
  %t15 = call ptr @__eqInt32(ptr %v_k, ptr %t14)
  %t16 = getelementptr ptr, ptr %t15, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %case.default.19 [ i64 1, label %case.arm.1.21 i64 2, label %case.arm.2.26 ]
case.arm.1.21:
  %t23 = call ptr @__alloc(i64 8, i32 0)
  %t24 = inttoptr i64 24 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  br label %case.end.1.22
case.end.1.22:
  br label %case.join.20
case.arm.2.26:
  call void @__inc_ref(ptr %v_k)
  %t28 = call ptr @__alloc(i64 4, i32 0)
  store i32 1, ptr %t28
  %t29 = call ptr @__eqInt32(ptr %v_k, ptr %t28)
  %t30 = getelementptr ptr, ptr %t29, i32 0
  %t31 = load ptr, ptr %t30
  %t32 = ptrtoint ptr %t31 to i64
  switch i64 %t32, label %case.default.33 [ i64 1, label %case.arm.1.35 i64 2, label %case.arm.2.40 ]
case.arm.1.35:
  %t37 = call ptr @__alloc(i64 8, i32 0)
  %t38 = inttoptr i64 25 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  br label %case.end.1.36
case.end.1.36:
  br label %case.join.34
case.arm.2.40:
  %t42 = call ptr @__alloc(i64 8, i32 0)
  %t43 = inttoptr i64 26 to ptr
  %t44 = getelementptr ptr, ptr %t42, i32 0
  store ptr %t43, ptr %t44
  br label %case.end.2.41
case.end.2.41:
  br label %case.join.34
case.default.33:
  unreachable
case.join.34:
  %t45 = phi ptr [ %t37, %case.end.1.36 ], [ %t42, %case.end.2.41 ]
  call void @__free_recursive(ptr %t29)
  br label %case.end.2.27
case.end.2.27:
  br label %case.join.20
case.default.19:
  unreachable
case.join.20:
  %t46 = phi ptr [ %t23, %case.end.1.22 ], [ %t45, %case.end.2.27 ]
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t3)
  store ptr %t46, ptr %v_$inl1$scrut.jslot
  br label %join.0
join.case.default.7:
  unreachable
join.0:
  %t47 = load ptr, ptr %v_$inl1$scrut.jslot
  %t48 = getelementptr ptr, ptr %t47, i32 0
  %t49 = load ptr, ptr %t48
  %t50 = ptrtoint ptr %t49 to i64
  switch i64 %t50, label %case.default.51 [ i64 24, label %case.arm.24.53 i64 25, label %case.arm.25.58 i64 26, label %case.arm.26.61 ]
case.arm.24.53:
  %t55 = call ptr @__alloc(i64 8, i32 0)
  %t56 = inttoptr i64 27 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  br label %case.end.24.54
case.end.24.54:
  br label %case.join.52
case.arm.25.58:
  call void @__inc_ref(ptr %v_k)
  %t60 = call ptr @v_spin(ptr %v_k)
  br label %case.end.25.59
case.end.25.59:
  br label %case.join.52
case.arm.26.61:
  %t63 = call ptr @__alloc(i64 8, i32 0)
  %t64 = inttoptr i64 29 to ptr
  %t65 = getelementptr ptr, ptr %t63, i32 0
  store ptr %t64, ptr %t65
  br label %case.end.26.62
case.end.26.62:
  br label %case.join.52
case.default.51:
  unreachable
case.join.52:
  %t66 = phi ptr [ %t55, %case.end.24.54 ], [ %t60, %case.end.25.59 ], [ %t63, %case.end.26.62 ]
  call void @__free_recursive(ptr %t47)
  br label %join.end.67
join.end.67:
  br label %join.after.1
join.after.1:
  %t68 = phi ptr [ %t9, %join.val.12 ], [ %t66, %join.end.67 ]
  %t69 = getelementptr ptr, ptr %t68, i32 0
  %t70 = load ptr, ptr %t69
  %t71 = ptrtoint ptr %t70 to i64
  switch i64 %t71, label %case.default.72 [ i64 27, label %case.arm.27.73 i64 28, label %case.arm.28.74 i64 29, label %case.arm.29.75 ]
case.arm.27.73:
  call void @__free_recursive(ptr %t68)
  call void @__free_recursive(ptr %v_k)
  ret ptr getelementptr inbounds (i8, ptr @.str.0, i64 12)
case.arm.28.74:
  call void @__free_recursive(ptr %t68)
  call void @__free_recursive(ptr %v_k)
  ret ptr getelementptr inbounds (i8, ptr @.str.1, i64 12)
case.arm.29.75:
  call void @__free_recursive(ptr %t68)
  call void @__free_recursive(ptr %v_k)
  ret ptr getelementptr inbounds (i8, ptr @.str.2, i64 12)
case.default.72:
  unreachable
}

define internal ptr @v_main() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 8 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 8, i32 0)
  %t4 = inttoptr i64 32 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  %t7 = call ptr @__alloc(i64 8, i32 0)
  %t8 = inttoptr i64 38 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = call ptr @v_$cps$$df$$rowmono$0$andThenIO$4(ptr %t0, ptr %t7)
  %t11 = call ptr @__alloc(i64 8, i32 0)
  %t12 = inttoptr i64 36 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  %t14 = call ptr @v_$cps$$df$handleErrorIO$0(ptr %t10, ptr %t11)
  ret ptr %t14
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.13 i64 7, label %tco.case.arm.7.51 i64 8, label %tco.case.arm.8.76 ]
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
  %t14 = getelementptr ptr, ptr %t5, i32 1
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  %t16 = getelementptr ptr, ptr %t15, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %case.default.19 [ i64 502975519, label %case.arm.502975519.21 i64 589989748, label %case.arm.589989748.35 ]
case.arm.502975519.21:
  %t23 = call ptr @__alloc(i64 24, i32 2)
  %t24 = inttoptr i64 7 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  %t26 = getelementptr ptr, ptr %t23, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t26
  %t27 = call ptr @__alloc(i64 16, i32 1)
  %t28 = inttoptr i64 5 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  %t30 = call ptr @__alloc(i64 8, i32 0)
  %t31 = inttoptr i64 0 to ptr
  %t32 = getelementptr ptr, ptr %t30, i32 0
  store ptr %t31, ptr %t32
  %t33 = getelementptr ptr, ptr %t27, i32 1
  store ptr %t30, ptr %t33
  %t34 = getelementptr ptr, ptr %t23, i32 2
  store ptr %t27, ptr %t34
  br label %case.end.502975519.22
case.end.502975519.22:
  br label %case.join.20
case.arm.589989748.35:
  %t37 = call ptr @__alloc(i64 24, i32 2)
  %t38 = inttoptr i64 7 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = getelementptr ptr, ptr %t37, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t40
  %t41 = call ptr @__alloc(i64 16, i32 1)
  %t42 = inttoptr i64 5 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = call ptr @__alloc(i64 8, i32 0)
  %t45 = inttoptr i64 0 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  %t47 = getelementptr ptr, ptr %t41, i32 1
  store ptr %t44, ptr %t47
  %t48 = getelementptr ptr, ptr %t37, i32 2
  store ptr %t41, ptr %t48
  br label %case.end.589989748.36
case.end.589989748.36:
  br label %case.join.20
case.default.19:
  unreachable
case.join.20:
  %t49 = phi ptr [ %t23, %case.end.502975519.22 ], [ %t37, %case.end.589989748.36 ]
  call void @__free_recursive(ptr %t15)
  %t50 = call ptr @v_$apply$$df$handleErrorIO$0(ptr %t6, ptr %t49)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t50, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.51:
  %t52 = getelementptr ptr, ptr %t5, i32 1
  %t53 = load ptr, ptr %t52
  %t54 = getelementptr ptr, ptr %t5, i32 2
  %t55 = load ptr, ptr %t54
  call void @__inc_ref(ptr %t55)
  %t62 = getelementptr i8, ptr %t5, i64 -8
  %t63 = load i32, ptr %t62
  %t64 = icmp eq i32 %t63, 1
  br i1 %t64, label %reuse.in_place.65, label %reuse.copy.66
reuse.in_place.65:
  %t56 = getelementptr ptr, ptr %t5, i32 2
  %t57 = load ptr, ptr %t56
  call void @__free_recursive(ptr %t57)
  %t60 = inttoptr i64 37 to ptr
  %t61 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t60, ptr %t61
  call void @__inc_ref(ptr %t6)
  %t58 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t58
  %t59 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t53, ptr %t59
  br label %reuse.in_place.end.68
reuse.in_place.end.68:
  br label %reuse.join.67
reuse.copy.66:
  %t70 = call ptr @__alloc(i64 24, i32 2)
  %t71 = inttoptr i64 37 to ptr
  %t72 = getelementptr ptr, ptr %t70, i32 0
  store ptr %t71, ptr %t72
  call void @__inc_ref(ptr %t6)
  %t73 = getelementptr ptr, ptr %t70, i32 1
  store ptr %t6, ptr %t73
  call void @__inc_ref(ptr %t53)
  %t74 = getelementptr ptr, ptr %t70, i32 2
  store ptr %t53, ptr %t74
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.69
reuse.copy.end.69:
  br label %reuse.join.67
reuse.join.67:
  %t75 = phi ptr [ %t5, %reuse.in_place.end.68 ], [ %t70, %reuse.copy.end.69 ]
  call void @__free_recursive(ptr %t6)
  store ptr %t55, ptr %t3
  store ptr %t75, ptr %t4
  br label %tco.loop.0
tco.case.arm.8.76:
  %t77 = getelementptr ptr, ptr %t5, i32 1
  %t78 = load ptr, ptr %t77
  call void @__inc_ref(ptr %t78)
  call void @__inc_ref(ptr %t6)
  %t79 = call ptr @__alloc(i64 16, i32 1)
  %t80 = inttoptr i64 8 to ptr
  %t81 = getelementptr ptr, ptr %t79, i32 0
  store ptr %t80, ptr %t81
  %t82 = call ptr @__alloc(i64 16, i32 1)
  %t83 = inttoptr i64 31 to ptr
  %t84 = getelementptr ptr, ptr %t82, i32 0
  store ptr %t83, ptr %t84
  call void @__inc_ref(ptr %t78)
  %t85 = getelementptr ptr, ptr %t82, i32 1
  store ptr %t78, ptr %t85
  %t86 = getelementptr ptr, ptr %t79, i32 1
  store ptr %t82, ptr %t86
  %t87 = call ptr @v_$apply$$df$handleErrorIO$0(ptr %t6, ptr %t79)
  call void @__free_recursive(ptr %t78)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t87, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t88 = load ptr, ptr %t2
  ret ptr %t88
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
  switch i64 %t9, label %tco.case.default.10 [ i64 36, label %tco.case.arm.36.11 i64 37, label %tco.case.arm.37.12 ]
tco.case.arm.36.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.37.12:
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

define internal ptr @v_$cps$$df$$rowmono$0$andThenIO$4(ptr %v_io, ptr %v_$k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.79 i64 7, label %tco.case.arm.7.81 i64 8, label %tco.case.arm.8.106 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t13, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %case.default.17 [ i64 13, label %case.arm.13.19 i64 14, label %case.arm.14.35 ]
case.arm.13.19:
  %t21 = call ptr @__alloc(i64 24, i32 2)
  %t22 = inttoptr i64 7 to ptr
  %t23 = getelementptr ptr, ptr %t21, i32 0
  store ptr %t22, ptr %t23
  %t24 = call ptr @__alloc(i64 4, i32 0)
  store i32 3, ptr %t24
  %t25 = call ptr @v_label(ptr %t24)
  %t26 = getelementptr ptr, ptr %t21, i32 1
  store ptr %t25, ptr %t26
  %t27 = call ptr @__alloc(i64 16, i32 1)
  %t28 = inttoptr i64 5 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  %t30 = call ptr @__alloc(i64 8, i32 0)
  %t31 = inttoptr i64 0 to ptr
  %t32 = getelementptr ptr, ptr %t30, i32 0
  store ptr %t31, ptr %t32
  %t33 = getelementptr ptr, ptr %t27, i32 1
  store ptr %t30, ptr %t33
  %t34 = getelementptr ptr, ptr %t21, i32 2
  store ptr %t27, ptr %t34
  br label %case.end.13.20
case.end.13.20:
  br label %case.join.18
case.arm.14.35:
  %t37 = getelementptr ptr, ptr %t13, i32 1
  %t38 = load ptr, ptr %t37
  call void @__inc_ref(ptr %t38)
  %t39 = call ptr @__parseInt32(ptr %t38)
  %t40 = getelementptr ptr, ptr %t39, i32 0
  %t41 = load ptr, ptr %t40
  %t42 = ptrtoint ptr %t41 to i64
  switch i64 %t42, label %case.default.43 [ i64 3, label %case.arm.3.45 i64 4, label %case.arm.4.59 ]
case.arm.3.45:
  %t47 = call ptr @__alloc(i64 24, i32 2)
  %t48 = inttoptr i64 7 to ptr
  %t49 = getelementptr ptr, ptr %t47, i32 0
  store ptr %t48, ptr %t49
  %t50 = getelementptr ptr, ptr %t47, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.5, i64 12), ptr %t50
  %t51 = call ptr @__alloc(i64 16, i32 1)
  %t52 = inttoptr i64 5 to ptr
  %t53 = getelementptr ptr, ptr %t51, i32 0
  store ptr %t52, ptr %t53
  %t54 = call ptr @__alloc(i64 8, i32 0)
  %t55 = inttoptr i64 0 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  %t57 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t57
  %t58 = getelementptr ptr, ptr %t47, i32 2
  store ptr %t51, ptr %t58
  br label %case.end.3.46
case.end.3.46:
  br label %case.join.44
case.arm.4.59:
  %t61 = getelementptr ptr, ptr %t39, i32 1
  %t62 = load ptr, ptr %t61
  call void @__inc_ref(ptr %t62)
  %t63 = call ptr @__alloc(i64 24, i32 2)
  %t64 = inttoptr i64 7 to ptr
  %t65 = getelementptr ptr, ptr %t63, i32 0
  store ptr %t64, ptr %t65
  call void @__inc_ref(ptr %t62)
  %t66 = call ptr @v_label(ptr %t62)
  %t67 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t67
  %t68 = call ptr @__alloc(i64 16, i32 1)
  %t69 = inttoptr i64 5 to ptr
  %t70 = getelementptr ptr, ptr %t68, i32 0
  store ptr %t69, ptr %t70
  %t71 = call ptr @__alloc(i64 8, i32 0)
  %t72 = inttoptr i64 0 to ptr
  %t73 = getelementptr ptr, ptr %t71, i32 0
  store ptr %t72, ptr %t73
  %t74 = getelementptr ptr, ptr %t68, i32 1
  store ptr %t71, ptr %t74
  %t75 = getelementptr ptr, ptr %t63, i32 2
  store ptr %t68, ptr %t75
  call void @__free_recursive(ptr %t62)
  br label %case.end.4.60
case.end.4.60:
  br label %case.join.44
case.default.43:
  unreachable
case.join.44:
  %t76 = phi ptr [ %t47, %case.end.3.46 ], [ %t63, %case.end.4.60 ]
  call void @__free_recursive(ptr %t39)
  br label %case.end.14.36
case.end.14.36:
  br label %case.join.18
case.default.17:
  unreachable
case.join.18:
  %t77 = phi ptr [ %t21, %case.end.13.20 ], [ %t76, %case.end.14.36 ]
  call void @__free_recursive(ptr %t13)
  %t78 = call ptr @v_$apply$$df$$rowmono$0$andThenIO$4(ptr %t6, ptr %t77)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t78, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.79:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t80 = call ptr @v_$apply$$df$$rowmono$0$andThenIO$4(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t80, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.81:
  %t82 = getelementptr ptr, ptr %t5, i32 1
  %t83 = load ptr, ptr %t82
  %t84 = getelementptr ptr, ptr %t5, i32 2
  %t85 = load ptr, ptr %t84
  call void @__inc_ref(ptr %t85)
  %t92 = getelementptr i8, ptr %t5, i64 -8
  %t93 = load i32, ptr %t92
  %t94 = icmp eq i32 %t93, 1
  br i1 %t94, label %reuse.in_place.95, label %reuse.copy.96
reuse.in_place.95:
  %t86 = getelementptr ptr, ptr %t5, i32 2
  %t87 = load ptr, ptr %t86
  call void @__free_recursive(ptr %t87)
  %t90 = inttoptr i64 39 to ptr
  %t91 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t90, ptr %t91
  call void @__inc_ref(ptr %t6)
  %t88 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t88
  %t89 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t83, ptr %t89
  br label %reuse.in_place.end.98
reuse.in_place.end.98:
  br label %reuse.join.97
reuse.copy.96:
  %t100 = call ptr @__alloc(i64 24, i32 2)
  %t101 = inttoptr i64 39 to ptr
  %t102 = getelementptr ptr, ptr %t100, i32 0
  store ptr %t101, ptr %t102
  call void @__inc_ref(ptr %t6)
  %t103 = getelementptr ptr, ptr %t100, i32 1
  store ptr %t6, ptr %t103
  call void @__inc_ref(ptr %t83)
  %t104 = getelementptr ptr, ptr %t100, i32 2
  store ptr %t83, ptr %t104
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.99
reuse.copy.end.99:
  br label %reuse.join.97
reuse.join.97:
  %t105 = phi ptr [ %t5, %reuse.in_place.end.98 ], [ %t100, %reuse.copy.end.99 ]
  call void @__free_recursive(ptr %t6)
  store ptr %t85, ptr %t3
  store ptr %t105, ptr %t4
  br label %tco.loop.0
tco.case.arm.8.106:
  %t107 = getelementptr ptr, ptr %t5, i32 1
  %t108 = load ptr, ptr %t107
  call void @__inc_ref(ptr %t108)
  call void @__inc_ref(ptr %t6)
  %t109 = call ptr @__alloc(i64 16, i32 1)
  %t110 = inttoptr i64 8 to ptr
  %t111 = getelementptr ptr, ptr %t109, i32 0
  store ptr %t110, ptr %t111
  %t112 = call ptr @__alloc(i64 16, i32 1)
  %t113 = inttoptr i64 30 to ptr
  %t114 = getelementptr ptr, ptr %t112, i32 0
  store ptr %t113, ptr %t114
  call void @__inc_ref(ptr %t108)
  %t115 = getelementptr ptr, ptr %t112, i32 1
  store ptr %t108, ptr %t115
  %t116 = getelementptr ptr, ptr %t109, i32 1
  store ptr %t112, ptr %t116
  %t117 = call ptr @v_$apply$$df$$rowmono$0$andThenIO$4(ptr %t6, ptr %t109)
  call void @__free_recursive(ptr %t108)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t117, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t118 = load ptr, ptr %t2
  ret ptr %t118
}

define internal ptr @v_$apply$$df$$rowmono$0$andThenIO$4(ptr %v_$k, ptr %v_$x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 38, label %tco.case.arm.38.11 i64 39, label %tco.case.arm.39.12 ]
tco.case.arm.38.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.39.12:
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

define internal ptr @v_$cps$$scc$$apply1__$df$$lam$13$5__$df$$lam$9$1(ptr %v_$args, ptr %v_$k) {
entry:
  %t3 = alloca ptr
  store ptr %v_$args, ptr %t3
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
  switch i64 %t9, label %tco.case.default.10 [ i64 33, label %tco.case.arm.33.11 i64 34, label %tco.case.arm.34.60 i64 35, label %tco.case.arm.35.71 ]
tco.case.arm.33.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t5, i32 2
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  %t16 = getelementptr ptr, ptr %t13, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %tco.case.default.19 [ i64 30, label %tco.case.arm.30.20 i64 31, label %tco.case.arm.31.28 i64 32, label %tco.case.arm.32.36 ]
tco.case.arm.30.20:
  %t21 = getelementptr ptr, ptr %t13, i32 1
  %t22 = load ptr, ptr %t21
  call void @__inc_ref(ptr %t22)
  %t23 = getelementptr ptr, ptr %t5, i32 1
  %t24 = load ptr, ptr %t23
  call void @__free_recursive(ptr %t24)
  %t26 = inttoptr i64 34 to ptr
  %t27 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t26, ptr %t27
  %t25 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t22, ptr %t25
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t5, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.31.28:
  %t29 = getelementptr ptr, ptr %t13, i32 1
  %t30 = load ptr, ptr %t29
  call void @__inc_ref(ptr %t30)
  %t31 = getelementptr ptr, ptr %t5, i32 1
  %t32 = load ptr, ptr %t31
  call void @__free_recursive(ptr %t32)
  %t34 = inttoptr i64 35 to ptr
  %t35 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t34, ptr %t35
  %t33 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t30, ptr %t33
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t5, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.32.36:
  call void @__inc_ref(ptr %t6)
  %t37 = getelementptr ptr, ptr %t15, i32 0
  %t38 = load ptr, ptr %t37
  %t39 = ptrtoint ptr %t38 to i64
  switch i64 %t39, label %case.default.40 [ i64 3, label %case.arm.3.42 i64 4, label %case.arm.4.50 ]
case.arm.3.42:
  %t44 = call ptr @__alloc(i64 16, i32 1)
  %t45 = inttoptr i64 6 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  %t47 = getelementptr ptr, ptr %t15, i32 1
  %t48 = load ptr, ptr %t47
  call void @__inc_ref(ptr %t48)
  %t49 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t48, ptr %t49
  br label %case.end.3.43
case.end.3.43:
  br label %case.join.41
case.arm.4.50:
  %t52 = call ptr @__alloc(i64 16, i32 1)
  %t53 = inttoptr i64 5 to ptr
  %t54 = getelementptr ptr, ptr %t52, i32 0
  store ptr %t53, ptr %t54
  %t55 = getelementptr ptr, ptr %t15, i32 1
  %t56 = load ptr, ptr %t55
  call void @__inc_ref(ptr %t56)
  %t57 = getelementptr ptr, ptr %t52, i32 1
  store ptr %t56, ptr %t57
  br label %case.end.4.51
case.end.4.51:
  br label %case.join.41
case.default.40:
  unreachable
case.join.41:
  %t58 = phi ptr [ %t44, %case.end.3.43 ], [ %t52, %case.end.4.51 ]
  %t59 = call ptr @v_$apply$$scc$$apply1__$df$$lam$13$5__$df$$lam$9$1(ptr %t6, ptr %t58)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t59, ptr %t2
  br label %tco.exit.1
tco.case.default.19:
  unreachable
tco.case.arm.34.60:
  %t61 = getelementptr ptr, ptr %t5, i32 1
  %t62 = load ptr, ptr %t61
  %t63 = getelementptr ptr, ptr %t5, i32 2
  %t64 = load ptr, ptr %t63
  %t65 = inttoptr i64 33 to ptr
  %t66 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t65, ptr %t66
  %t67 = call ptr @__alloc(i64 16, i32 1)
  %t68 = inttoptr i64 41 to ptr
  %t69 = getelementptr ptr, ptr %t67, i32 0
  store ptr %t68, ptr %t69
  call void @__inc_ref(ptr %t6)
  %t70 = getelementptr ptr, ptr %t67, i32 1
  store ptr %t6, ptr %t70
  call void @__free_recursive(ptr %t6)
  store ptr %t5, ptr %t3
  store ptr %t67, ptr %t4
  br label %tco.loop.0
tco.case.arm.35.71:
  %t72 = getelementptr ptr, ptr %t5, i32 1
  %t73 = load ptr, ptr %t72
  %t74 = getelementptr ptr, ptr %t5, i32 2
  %t75 = load ptr, ptr %t74
  %t76 = inttoptr i64 33 to ptr
  %t77 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t76, ptr %t77
  %t78 = call ptr @__alloc(i64 16, i32 1)
  %t79 = inttoptr i64 42 to ptr
  %t80 = getelementptr ptr, ptr %t78, i32 0
  store ptr %t79, ptr %t80
  call void @__inc_ref(ptr %t6)
  %t81 = getelementptr ptr, ptr %t78, i32 1
  store ptr %t6, ptr %t81
  call void @__free_recursive(ptr %t6)
  store ptr %t5, ptr %t3
  store ptr %t78, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t82 = load ptr, ptr %t2
  ret ptr %t82
}

define internal ptr @v_$apply$$scc$$apply1__$df$$lam$13$5__$df$$lam$9$1(ptr %v_$k, ptr %v_$x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 40, label %tco.case.arm.40.11 i64 41, label %tco.case.arm.41.12 i64 42, label %tco.case.arm.42.19 ]
tco.case.arm.40.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.41.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  call void @__inc_ref(ptr %t6)
  %t15 = call ptr @__alloc(i64 8, i32 0)
  %t16 = inttoptr i64 38 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = call ptr @v_$cps$$df$$rowmono$0$andThenIO$4(ptr %t6, ptr %t15)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  store ptr %t14, ptr %t3
  store ptr %t18, ptr %t4
  br label %tco.loop.0
tco.case.arm.42.19:
  %t20 = getelementptr ptr, ptr %t5, i32 1
  %t21 = load ptr, ptr %t20
  call void @__inc_ref(ptr %t21)
  call void @__inc_ref(ptr %t6)
  %t22 = call ptr @__alloc(i64 8, i32 0)
  %t23 = inttoptr i64 36 to ptr
  %t24 = getelementptr ptr, ptr %t22, i32 0
  store ptr %t23, ptr %t24
  %t25 = call ptr @v_$cps$$df$handleErrorIO$0(ptr %t6, ptr %t22)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  store ptr %t21, ptr %t3
  store ptr %t25, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t26 = load ptr, ptr %t2
  ret ptr %t26
}

define i32 @main(i32 %argc, ptr %argv) {
  %argc64 = sext i32 %argc to i64
  store i64 %argc64, ptr @.cli_argc
  store ptr %argv, ptr @.cli_argv
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
