; External C declarations
declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare ptr @memcpy(ptr, ptr, i64)
declare i64 @write(i32, ptr, i64)
declare i64 @strlen(ptr)
declare i64 @read(i32, ptr, i64)

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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [7 x i8]} { i32 0, i32 0, i32 0, i32 7, i32 7, [7 x i8] c"Hello, " }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"!" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [24 x i8]} { i32 0, i32 0, i32 0, i32 24, i32 24, [24 x i8] c"UNPAIRED_UTF16_SURROGATE" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [6 x i8]} { i32 0, i32 0, i32 0, i32 6, i32 6, [6 x i8] c"NO_ARG" }

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


define internal ptr @__readStdin(ptr %len_out) {
entry:
  %cap_p = alloca i64, align 8
  store i64 4096, ptr %cap_p
  %len_p = alloca i64, align 8
  store i64 0, ptr %len_p
  %buf_p = alloca ptr, align 8
  %buf0 = call ptr @malloc(i64 4096)
  store ptr %buf0, ptr %buf_p
  br label %read_head
read_head:
  %cap = load i64, ptr %cap_p
  %len = load i64, ptr %len_p
  %remain = sub i64 %cap, %len
  %need_grow = icmp ult i64 %remain, 4096
  br i1 %need_grow, label %grow, label %do_read
grow:
  %new_cap = mul i64 %cap, 2
  %old_buf = load ptr, ptr %buf_p
  %new_buf = call ptr @realloc(ptr %old_buf, i64 %new_cap)
  store ptr %new_buf, ptr %buf_p
  store i64 %new_cap, ptr %cap_p
  br label %do_read
do_read:
  %cap2 = load i64, ptr %cap_p
  %len2 = load i64, ptr %len_p
  %buf = load ptr, ptr %buf_p
  %off_ptr = getelementptr i8, ptr %buf, i64 %len2
  %remain2 = sub i64 %cap2, %len2
  %got = call i64 @read(i32 0, ptr %off_ptr, i64 %remain2)
  %eof = icmp sle i64 %got, 0
  br i1 %eof, label %read_done, label %accumulate
accumulate:
  %len3 = load i64, ptr %len_p
  %new_len = add i64 %len3, %got
  store i64 %new_len, ptr %len_p
  br label %read_head
read_done:
  %final_len = load i64, ptr %len_p
  %buf_final = load ptr, ptr %buf_p
  store i64 %final_len, ptr %len_out
  ret ptr %buf_final
}


define internal ptr @__stdinDecodeStrict(ptr %arg, i64 %len) {
entry:
  %i_p = alloca i64, align 8
  store i64 0, ptr %i_p
  %n_p = alloca i64, align 8
  store i64 0, ptr %n_p
  br label %head
head:
  %i = load i64, ptr %i_p
  %done = icmp uge i64 %i, %len
  br i1 %done, label %valid_end, label %body
body:
  %b0p = getelementptr i8, ptr %arg, i64 %i
  %b0 = load i8, ptr %b0p
  %b0z = zext i8 %b0 to i32
  %is_ascii = icmp ult i32 %b0z, 128
  br i1 %is_ascii, label %one_byte, label %chk_lead
one_byte:
  %n_o = load i64, ptr %n_p
  %n_o1 = add i64 %n_o, 1
  store i64 %n_o1, ptr %n_p
  %i_o1 = add i64 %i, 1
  store i64 %i_o1, ptr %i_p
  br label %head
chk_lead:
  %ge_c2 = icmp uge i32 %b0z, 194
  br i1 %ge_c2, label %chk2, label %invalid
chk2:
  %lt_e0 = icmp ult i32 %b0z, 224
  br i1 %lt_e0, label %two_byte, label %chk3
chk3:
  %lt_f0 = icmp ult i32 %b0z, 240
  br i1 %lt_f0, label %three_byte, label %chk4
chk4:
  %lt_f5 = icmp ult i32 %b0z, 245
  br i1 %lt_f5, label %four_byte, label %invalid
two_byte:
  %i_2a = add i64 %i, 1
  %trunc2 = icmp uge i64 %i_2a, %len
  br i1 %trunc2, label %invalid, label %two_cont
two_cont:
  %b1_2p = getelementptr i8, ptr %arg, i64 %i_2a
  %b1_2 = load i8, ptr %b1_2p
  %b1_2z = zext i8 %b1_2 to i32
  %b1_2m = and i32 %b1_2z, 192
  %b1_2ok = icmp eq i32 %b1_2m, 128
  br i1 %b1_2ok, label %two_ok, label %invalid
two_ok:
  %n_2 = load i64, ptr %n_p
  %n_2a = add i64 %n_2, 1
  store i64 %n_2a, ptr %n_p
  %i_2b = add i64 %i, 2
  store i64 %i_2b, ptr %i_p
  br label %head
three_byte:
  %i_3c = add i64 %i, 2
  %trunc3 = icmp uge i64 %i_3c, %len
  br i1 %trunc3, label %invalid, label %three_b1
three_b1:
  %i_3b1 = add i64 %i, 1
  %b1_3p = getelementptr i8, ptr %arg, i64 %i_3b1
  %b1_3 = load i8, ptr %b1_3p
  %b1_3z = zext i8 %b1_3 to i32
  %b1_3m = and i32 %b1_3z, 192
  %b1_3ok = icmp eq i32 %b1_3m, 128
  br i1 %b1_3ok, label %three_b2, label %invalid
three_b2:
  %b2_3p = getelementptr i8, ptr %arg, i64 %i_3c
  %b2_3 = load i8, ptr %b2_3p
  %b2_3z = zext i8 %b2_3 to i32
  %b2_3m = and i32 %b2_3z, 192
  %b2_3ok = icmp eq i32 %b2_3m, 128
  br i1 %b2_3ok, label %three_range, label %invalid
three_range:
  %is_e0 = icmp eq i32 %b0z, 224
  %b1_lt_a0 = icmp ult i32 %b1_3z, 160
  %e0_overlong = and i1 %is_e0, %b1_lt_a0
  br i1 %e0_overlong, label %invalid, label %three_ed
three_ed:
  %is_ed = icmp eq i32 %b0z, 237
  %b1_ge_a0 = icmp uge i32 %b1_3z, 160
  %ed_surr = and i1 %is_ed, %b1_ge_a0
  br i1 %ed_surr, label %invalid, label %three_ok
three_ok:
  %n_3 = load i64, ptr %n_p
  %n_3a = add i64 %n_3, 1
  store i64 %n_3a, ptr %n_p
  %i_3d = add i64 %i, 3
  store i64 %i_3d, ptr %i_p
  br label %head
four_byte:
  %i_4c = add i64 %i, 3
  %trunc4 = icmp uge i64 %i_4c, %len
  br i1 %trunc4, label %invalid, label %four_b1
four_b1:
  %i_4b1 = add i64 %i, 1
  %b1_4p = getelementptr i8, ptr %arg, i64 %i_4b1
  %b1_4 = load i8, ptr %b1_4p
  %b1_4z = zext i8 %b1_4 to i32
  %b1_4m = and i32 %b1_4z, 192
  %b1_4ok = icmp eq i32 %b1_4m, 128
  br i1 %b1_4ok, label %four_b2, label %invalid
four_b2:
  %i_4b2 = add i64 %i, 2
  %b2_4p = getelementptr i8, ptr %arg, i64 %i_4b2
  %b2_4 = load i8, ptr %b2_4p
  %b2_4z = zext i8 %b2_4 to i32
  %b2_4m = and i32 %b2_4z, 192
  %b2_4ok = icmp eq i32 %b2_4m, 128
  br i1 %b2_4ok, label %four_b3, label %invalid
four_b3:
  %b3_4p = getelementptr i8, ptr %arg, i64 %i_4c
  %b3_4 = load i8, ptr %b3_4p
  %b3_4z = zext i8 %b3_4 to i32
  %b3_4m = and i32 %b3_4z, 192
  %b3_4ok = icmp eq i32 %b3_4m, 128
  br i1 %b3_4ok, label %four_range, label %invalid
four_range:
  %is_f0 = icmp eq i32 %b0z, 240
  %b1_lt_90 = icmp ult i32 %b1_4z, 144
  %f0_overlong = and i1 %is_f0, %b1_lt_90
  br i1 %f0_overlong, label %invalid, label %four_f4
four_f4:
  %is_f4 = icmp eq i32 %b0z, 244
  %b1_ge_90 = icmp uge i32 %b1_4z, 144
  %f4_over = and i1 %is_f4, %b1_ge_90
  br i1 %f4_over, label %invalid, label %four_ok
four_ok:
  %n_4 = load i64, ptr %n_p
  %n_4a = add i64 %n_4, 2
  store i64 %n_4a, ptr %n_p
  %i_4d = add i64 %i, 4
  store i64 %i_4d, ptr %i_p
  br label %head
valid_end:
  %n_final = load i64, ptr %n_p
  %over = icmp ugt i64 %n_final, 134217728
  br i1 %over, label %too_long, label %fits
fits:
  %byte_count = trunc i64 %len to i32
  %alloc_size = add i64 %len, 8
  %wrapped = call ptr @__alloc(i64 %alloc_size, i32 0)
  store i32 %byte_count, ptr %wrapped
  %n_final32 = trunc i64 %n_final to i32
  %wrapped_u16p = getelementptr i8, ptr %wrapped, i64 4
  store i32 %n_final32, ptr %wrapped_u16p
  %wrapped_payload = getelementptr i8, ptr %wrapped, i64 8
  call ptr @memcpy(ptr %wrapped_payload, ptr %arg, i64 %len)
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
invalid:
  %iu_inner = call ptr @__alloc(i64 8, i32 0)
  %iu_inner_tag = inttoptr i64 21 to ptr
  store ptr %iu_inner_tag, ptr %iu_inner
  %iu_row = call ptr @__alloc(i64 16, i32 1)
  %iu_row_tag = inttoptr i64 3239958583 to ptr
  store ptr %iu_row_tag, ptr %iu_row
  %iu_row_f = getelementptr ptr, ptr %iu_row, i32 1
  store ptr %iu_inner, ptr %iu_row_f
  %iu_left = call ptr @__alloc(i64 16, i32 1)
  %iu_left_tag = inttoptr i64 3 to ptr
  store ptr %iu_left_tag, ptr %iu_left
  %iu_left_f = getelementptr ptr, ptr %iu_left, i32 1
  store ptr %iu_row, ptr %iu_left_f
  ret ptr %iu_left
}


define internal ptr @__stdinReadAll() {
entry:
  %len_slot = alloca i64, align 8
  %buf = call ptr @__readStdin(ptr %len_slot)
  %len = load i64, ptr %len_slot
  %either = call ptr @__stdinDecodeStrict(ptr %buf, i64 %len)
  call void @free(ptr %buf)
  ret ptr %either
}


define internal ptr @__stdinReadAllBytes() {
entry:
  %len_slot = alloca i64, align 8
  %buf = call ptr @__readStdin(ptr %len_slot)
  %len = load i64, ptr %len_slot
  %i_p = alloca i64, align 8
  %acc_p = alloca ptr, align 8
  %nilC = call ptr @__alloc(i64 8, i32 0)
  %nilC_tag = inttoptr i64 13 to ptr
  store ptr %nilC_tag, ptr %nilC
  store ptr %nilC, ptr %acc_p
  store i64 %len, ptr %i_p
  br label %bytes_loop
bytes_loop:
  %i = load i64, ptr %i_p
  %at_start = icmp eq i64 %i, 0
  br i1 %at_start, label %bytes_done, label %bytes_body
bytes_body:
  %i_next = sub i64 %i, 1
  store i64 %i_next, ptr %i_p
  %byte_ptr = getelementptr i8, ptr %buf, i64 %i_next
  %byte = load i8, ptr %byte_ptr
  %u8 = call ptr @__alloc(i64 1, i32 0)
  store i8 %byte, ptr %u8
  %acc = load ptr, ptr %acc_p
  %consC = call ptr @__alloc(i64 24, i32 2)
  %consC_tag = inttoptr i64 14 to ptr
  store ptr %consC_tag, ptr %consC
  %consC_head = getelementptr ptr, ptr %consC, i32 1
  store ptr %u8, ptr %consC_head
  %consC_tail = getelementptr ptr, ptr %consC, i32 2
  store ptr %acc, ptr %consC_tail
  store ptr %consC, ptr %acc_p
  br label %bytes_loop
bytes_done:
  call void @free(ptr %buf)
  %acc_final = load ptr, ptr %acc_p
  ret ptr %acc_final
}


define internal ptr @v_nothingAsLeft(ptr %v_e, ptr %v_m) {
  %t0 = getelementptr ptr, ptr %v_m, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 11, label %case.arm.11.4 i64 12, label %case.arm.12.9 ]
case.arm.11.4:
  %t5 = call ptr @__alloc(i64 16, i32 1)
  %t6 = inttoptr i64 3 to ptr
  %t7 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t6, ptr %t7
  call void @__inc_ref(ptr %v_e)
  %t8 = getelementptr ptr, ptr %t5, i32 1
  store ptr %v_e, ptr %t8
  call void @__free_recursive(ptr %v_e)
  call void @__free_recursive(ptr %v_m)
  ret ptr %t5
case.arm.12.9:
  %t10 = getelementptr ptr, ptr %v_m, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  %t12 = call ptr @__alloc(i64 16, i32 1)
  %t13 = inttoptr i64 4 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  call void @__inc_ref(ptr %t11)
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t11, ptr %t15
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %v_e)
  call void @__free_recursive(ptr %v_m)
  ret ptr %t12
case.default.3:
  unreachable
}

define internal ptr @v_pureIO(ptr %v_x) {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 5 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  call void @__inc_ref(ptr %v_x)
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v_x, ptr %t3
  call void @__free_recursive(ptr %v_x)
  ret ptr %t0
}

define internal ptr @v_failIO(ptr %v_e) {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 6 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  call void @__inc_ref(ptr %v_e)
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v_e, ptr %t3
  call void @__free_recursive(ptr %v_e)
  ret ptr %t0
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
  switch i64 %t7, label %tco.case.default.8 [ i64 5, label %tco.case.arm.5.9 i64 7, label %tco.case.arm.7.12 i64 8, label %tco.case.arm.8.23 i64 9, label %tco.case.arm.9.28 i64 10, label %tco.case.arm.10.33 ]
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
tco.case.arm.8.23:
  %t24 = getelementptr ptr, ptr %t4, i32 1
  %t25 = load ptr, ptr %t24
  call void @__inc_ref(ptr %t25)
  call void @__inc_ref(ptr %t25)
  %t26 = call ptr @__getArgs()
  %t27 = call ptr @v__apply1(ptr %t25, ptr %t26)
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t25)
  store ptr %t27, ptr %t3
  br label %tco.loop.0
tco.case.arm.9.28:
  %t29 = getelementptr ptr, ptr %t4, i32 1
  %t30 = load ptr, ptr %t29
  call void @__inc_ref(ptr %t30)
  call void @__inc_ref(ptr %t30)
  %t31 = call ptr @__stdinReadAll()
  %t32 = call ptr @v__apply1(ptr %t30, ptr %t31)
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t30)
  store ptr %t32, ptr %t3
  br label %tco.loop.0
tco.case.arm.10.33:
  %t34 = getelementptr ptr, ptr %t4, i32 1
  %t35 = load ptr, ptr %t34
  call void @__inc_ref(ptr %t35)
  call void @__inc_ref(ptr %t35)
  %t36 = call ptr @__stdinReadAllBytes()
  %t37 = call ptr @v__apply1(ptr %t35, ptr %t36)
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t35)
  store ptr %t37, ptr %t3
  br label %tco.loop.0
tco.case.default.8:
  unreachable
tco.exit.1:
  %t38 = load ptr, ptr %t2
  ret ptr %t38
}

define internal ptr @v_eitherToIO(ptr %v_x) {
  %t0 = getelementptr ptr, ptr %v_x, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.8 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v_x, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t6)
  %t7 = call ptr @v_failIO(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t7
case.arm.4.8:
  %t9 = getelementptr ptr, ptr %v_x, i32 1
  %t10 = load ptr, ptr %t9
  call void @__inc_ref(ptr %t10)
  call void @__inc_ref(ptr %t10)
  %t11 = call ptr @v_pureIO(ptr %t10)
  call void @__free_recursive(ptr %t10)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t11
case.default.3:
  unreachable
}

define internal ptr @v_headList(ptr %v_xs) {
  %t0 = getelementptr ptr, ptr %v_xs, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 13, label %case.arm.13.4 i64 14, label %case.arm.14.8 ]
case.arm.13.4:
  %t5 = call ptr @__alloc(i64 8, i32 0)
  %t6 = inttoptr i64 11 to ptr
  %t7 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t6, ptr %t7
  call void @__free_recursive(ptr %v_xs)
  ret ptr %t5
case.arm.14.8:
  %t9 = getelementptr ptr, ptr %v_xs, i32 1
  %t10 = load ptr, ptr %t9
  call void @__inc_ref(ptr %t10)
  %t11 = getelementptr ptr, ptr %v_xs, i32 2
  %t12 = load ptr, ptr %t11
  call void @__inc_ref(ptr %t12)
  %t13 = call ptr @__alloc(i64 16, i32 1)
  %t14 = inttoptr i64 12 to ptr
  %t15 = getelementptr ptr, ptr %t13, i32 0
  store ptr %t14, ptr %t15
  call void @__inc_ref(ptr %t10)
  %t16 = getelementptr ptr, ptr %t13, i32 1
  store ptr %t10, ptr %t16
  call void @__free_recursive(ptr %t12)
  call void @__free_recursive(ptr %t10)
  call void @__free_recursive(ptr %v_xs)
  ret ptr %t13
case.default.3:
  unreachable
}

define internal ptr @v_main() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 8 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 8, i32 0)
  %t4 = inttoptr i64 34 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  %t7 = call ptr @v__df__rowmono_1_andThenIO_8(ptr %t0)
  %t8 = call ptr @v__df__rowmono_0_andThenIO_4(ptr %t7)
  %t9 = call ptr @v__df_handleErrorIO_0(ptr %t8)
  ret ptr %t9
}

define internal ptr @v_greet(ptr %v_args) {
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 24 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  call void @__inc_ref(ptr %v_args)
  %t3 = call ptr @v_headList(ptr %v_args)
  %t4 = call ptr @v_nothingAsLeft(ptr %t0, ptr %t3)
  %t5 = getelementptr ptr, ptr %t4, i32 0
  %t6 = load ptr, ptr %t5
  %t7 = ptrtoint ptr %t6 to i64
  switch i64 %t7, label %case.default.8 [ i64 3, label %case.arm.3.9 i64 4, label %case.arm.4.20 ]
case.arm.3.9:
  %t10 = getelementptr ptr, ptr %t4, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  %t12 = call ptr @__alloc(i64 16, i32 1)
  %t13 = inttoptr i64 3 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = call ptr @__alloc(i64 16, i32 1)
  %t16 = inttoptr i64 3864168810 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  call void @__inc_ref(ptr %t11)
  %t18 = getelementptr ptr, ptr %t15, i32 1
  store ptr %t11, ptr %t18
  %t19 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t15, ptr %t19
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %v_args)
  ret ptr %t12
case.arm.4.20:
  %t21 = getelementptr ptr, ptr %t4, i32 1
  %t22 = load ptr, ptr %t21
  call void @__inc_ref(ptr %t22)
  call void @__inc_ref(ptr %t22)
  %t23 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t22)
  %t24 = getelementptr ptr, ptr %t23, i32 0
  %t25 = load ptr, ptr %t24
  %t26 = ptrtoint ptr %t25 to i64
  switch i64 %t26, label %case.default.27 [ i64 3, label %case.arm.3.28 i64 4, label %case.arm.4.39 ]
case.arm.3.28:
  %t29 = getelementptr ptr, ptr %t23, i32 1
  %t30 = load ptr, ptr %t29
  call void @__inc_ref(ptr %t30)
  %t31 = call ptr @__alloc(i64 16, i32 1)
  %t32 = inttoptr i64 3 to ptr
  %t33 = getelementptr ptr, ptr %t31, i32 0
  store ptr %t32, ptr %t33
  %t34 = call ptr @__alloc(i64 16, i32 1)
  %t35 = inttoptr i64 589989748 to ptr
  %t36 = getelementptr ptr, ptr %t34, i32 0
  store ptr %t35, ptr %t36
  call void @__inc_ref(ptr %t30)
  %t37 = getelementptr ptr, ptr %t34, i32 1
  store ptr %t30, ptr %t37
  %t38 = getelementptr ptr, ptr %t31, i32 1
  store ptr %t34, ptr %t38
  call void @__free_recursive(ptr %t23)
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t30)
  call void @__free_recursive(ptr %t22)
  call void @__free_recursive(ptr %v_args)
  ret ptr %t31
case.arm.4.39:
  %t40 = getelementptr ptr, ptr %t23, i32 1
  %t41 = load ptr, ptr %t40
  call void @__inc_ref(ptr %t41)
  call void @__inc_ref(ptr %t41)
  %t42 = call ptr @__concat(ptr %t41, ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  %t43 = call ptr @v__lift_19(ptr %t42)
  call void @__free_recursive(ptr %t23)
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t41)
  call void @__free_recursive(ptr %t22)
  call void @__free_recursive(ptr %v_args)
  ret ptr %t43
case.default.27:
  unreachable
case.default.8:
  unreachable
}

define internal ptr @v_printError(ptr %v_e) {
  %t0 = getelementptr ptr, ptr %v_e, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 502975519, label %case.arm.502975519.4 i64 589989748, label %case.arm.589989748.24 i64 3864168810, label %case.arm.3864168810.44 ]
case.arm.502975519.4:
  %t5 = getelementptr ptr, ptr %v_e, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = getelementptr ptr, ptr %t6, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %case.default.10 [ i64 20, label %case.arm.20.11 ]
case.arm.20.11:
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t15
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 5 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = call ptr @__alloc(i64 8, i32 0)
  %t20 = inttoptr i64 0 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t19, ptr %t22
  %t23 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t16, ptr %t23
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_e)
  ret ptr %t12
case.default.10:
  unreachable
case.arm.589989748.24:
  %t25 = getelementptr ptr, ptr %v_e, i32 1
  %t26 = load ptr, ptr %t25
  call void @__inc_ref(ptr %t26)
  %t27 = getelementptr ptr, ptr %t26, i32 0
  %t28 = load ptr, ptr %t27
  %t29 = ptrtoint ptr %t28 to i64
  switch i64 %t29, label %case.default.30 [ i64 19, label %case.arm.19.31 ]
case.arm.19.31:
  %t32 = call ptr @__alloc(i64 24, i32 2)
  %t33 = inttoptr i64 7 to ptr
  %t34 = getelementptr ptr, ptr %t32, i32 0
  store ptr %t33, ptr %t34
  %t35 = getelementptr ptr, ptr %t32, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t35
  %t36 = call ptr @__alloc(i64 16, i32 1)
  %t37 = inttoptr i64 5 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = call ptr @__alloc(i64 8, i32 0)
  %t40 = inttoptr i64 0 to ptr
  %t41 = getelementptr ptr, ptr %t39, i32 0
  store ptr %t40, ptr %t41
  %t42 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t39, ptr %t42
  %t43 = getelementptr ptr, ptr %t32, i32 2
  store ptr %t36, ptr %t43
  call void @__free_recursive(ptr %t26)
  call void @__free_recursive(ptr %v_e)
  ret ptr %t32
case.default.30:
  unreachable
case.arm.3864168810.44:
  %t45 = getelementptr ptr, ptr %v_e, i32 1
  %t46 = load ptr, ptr %t45
  call void @__inc_ref(ptr %t46)
  %t47 = getelementptr ptr, ptr %t46, i32 0
  %t48 = load ptr, ptr %t47
  %t49 = ptrtoint ptr %t48 to i64
  switch i64 %t49, label %case.default.50 [ i64 24, label %case.arm.24.51 ]
case.arm.24.51:
  %t52 = call ptr @__alloc(i64 24, i32 2)
  %t53 = inttoptr i64 7 to ptr
  %t54 = getelementptr ptr, ptr %t52, i32 0
  store ptr %t53, ptr %t54
  %t55 = getelementptr ptr, ptr %t52, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t55
  %t56 = call ptr @__alloc(i64 16, i32 1)
  %t57 = inttoptr i64 5 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  %t59 = call ptr @__alloc(i64 8, i32 0)
  %t60 = inttoptr i64 0 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  %t62 = getelementptr ptr, ptr %t56, i32 1
  store ptr %t59, ptr %t62
  %t63 = getelementptr ptr, ptr %t52, i32 2
  store ptr %t56, ptr %t63
  call void @__free_recursive(ptr %t46)
  call void @__free_recursive(ptr %v_e)
  ret ptr %t52
case.default.50:
  unreachable
case.default.3:
  unreachable
}

define internal ptr @v__lam_18(ptr %v_args) {
  call void @__inc_ref(ptr %v_args)
  %t0 = call ptr @v_greet(ptr %v_args)
  %t1 = call ptr @v_eitherToIO(ptr %t0)
  call void @__free_recursive(ptr %v_args)
  ret ptr %t1
}

define internal ptr @v__lift_19(ptr %v___input) {
  %t0 = getelementptr ptr, ptr %v___input, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.15 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v___input, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = call ptr @__alloc(i64 16, i32 1)
  %t8 = inttoptr i64 3 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = call ptr @__alloc(i64 16, i32 1)
  %t11 = inttoptr i64 589989748 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  call void @__inc_ref(ptr %t6)
  %t13 = getelementptr ptr, ptr %t10, i32 1
  store ptr %t6, ptr %t13
  %t14 = getelementptr ptr, ptr %t7, i32 1
  store ptr %t10, ptr %t14
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t7
case.arm.4.15:
  %t16 = getelementptr ptr, ptr %v___input, i32 1
  %t17 = load ptr, ptr %t16
  call void @__inc_ref(ptr %t17)
  %t18 = call ptr @__alloc(i64 16, i32 1)
  %t19 = inttoptr i64 4 to ptr
  %t20 = getelementptr ptr, ptr %t18, i32 0
  store ptr %t19, ptr %t20
  call void @__inc_ref(ptr %t17)
  %t21 = getelementptr ptr, ptr %t18, i32 1
  store ptr %t17, ptr %t21
  call void @__free_recursive(ptr %t17)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t18
case.default.3:
  unreachable
}

define internal ptr @v__lift_20(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 57 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__lift_20(ptr %v___input, ptr %t0)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t3
}

define internal ptr @v__cps__lift_20(ptr %v___input, ptr %v__k) {
entry:
  %t3 = alloca ptr
  store ptr %v___input, ptr %t3
  %t4 = alloca ptr
  store ptr %v__k, ptr %t4
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t5 = load ptr, ptr %t3
  %t6 = load ptr, ptr %t4
  %t7 = getelementptr ptr, ptr %t5, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.19 i64 7, label %tco.case.arm.7.27 i64 8, label %tco.case.arm.8.50 i64 9, label %tco.case.arm.9.62 i64 10, label %tco.case.arm.10.74 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  %t14 = call ptr @__alloc(i64 16, i32 1)
  %t15 = inttoptr i64 5 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  call void @__inc_ref(ptr %t13)
  %t17 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t13, ptr %t17
  %t18 = call ptr @v__apply__lift_20(ptr %t6, ptr %t14)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t18, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.19:
  %t20 = getelementptr ptr, ptr %t5, i32 1
  %t21 = load ptr, ptr %t20
  call void @__inc_ref(ptr %t21)
  call void @__inc_ref(ptr %t6)
  %t22 = call ptr @__alloc(i64 16, i32 1)
  %t23 = inttoptr i64 6 to ptr
  %t24 = getelementptr ptr, ptr %t22, i32 0
  store ptr %t23, ptr %t24
  call void @__inc_ref(ptr %t21)
  %t25 = getelementptr ptr, ptr %t22, i32 1
  store ptr %t21, ptr %t25
  %t26 = call ptr @v__apply__lift_20(ptr %t6, ptr %t22)
  call void @__free_recursive(ptr %t21)
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
  %t32 = getelementptr i8, ptr %t5, i64 -8
  %t33 = load i32, ptr %t32
  %t34 = icmp eq i32 %t33, 1
  br i1 %t34, label %reuse.in_place.35, label %reuse.copy.36
reuse.in_place.35:
  %t38 = getelementptr ptr, ptr %t5, i32 2
  %t39 = load ptr, ptr %t38
  call void @__free_recursive(ptr %t39)
  %t42 = inttoptr i64 58 to ptr
  %t43 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t42, ptr %t43
  call void @__inc_ref(ptr %t6)
  %t40 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t40
  %t41 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t29, ptr %t41
  br label %reuse.join.37
reuse.copy.36:
  %t44 = call ptr @__alloc(i64 24, i32 2)
  %t45 = inttoptr i64 58 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  call void @__inc_ref(ptr %t6)
  %t47 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t6, ptr %t47
  call void @__inc_ref(ptr %t29)
  %t48 = getelementptr ptr, ptr %t44, i32 2
  store ptr %t29, ptr %t48
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.37
reuse.join.37:
  %t49 = phi ptr [ %t5, %reuse.in_place.35 ], [ %t44, %reuse.copy.36 ]
  call void @__inc_ref(ptr %t31)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t31)
  store ptr %t31, ptr %t3
  store ptr %t49, ptr %t4
  br label %tco.loop.0
tco.case.arm.8.50:
  %t51 = getelementptr ptr, ptr %t5, i32 1
  %t52 = load ptr, ptr %t51
  call void @__inc_ref(ptr %t52)
  call void @__inc_ref(ptr %t6)
  %t53 = call ptr @__alloc(i64 16, i32 1)
  %t54 = inttoptr i64 8 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  %t56 = call ptr @__alloc(i64 16, i32 1)
  %t57 = inttoptr i64 35 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  call void @__inc_ref(ptr %t52)
  %t59 = getelementptr ptr, ptr %t56, i32 1
  store ptr %t52, ptr %t59
  %t60 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t56, ptr %t60
  %t61 = call ptr @v__apply__lift_20(ptr %t6, ptr %t53)
  call void @__free_recursive(ptr %t52)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t61, ptr %t2
  br label %tco.exit.1
tco.case.arm.9.62:
  %t63 = getelementptr ptr, ptr %t5, i32 1
  %t64 = load ptr, ptr %t63
  call void @__inc_ref(ptr %t64)
  call void @__inc_ref(ptr %t6)
  %t65 = call ptr @__alloc(i64 16, i32 1)
  %t66 = inttoptr i64 9 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  %t68 = call ptr @__alloc(i64 16, i32 1)
  %t69 = inttoptr i64 36 to ptr
  %t70 = getelementptr ptr, ptr %t68, i32 0
  store ptr %t69, ptr %t70
  call void @__inc_ref(ptr %t64)
  %t71 = getelementptr ptr, ptr %t68, i32 1
  store ptr %t64, ptr %t71
  %t72 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t68, ptr %t72
  %t73 = call ptr @v__apply__lift_20(ptr %t6, ptr %t65)
  call void @__free_recursive(ptr %t64)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t73, ptr %t2
  br label %tco.exit.1
tco.case.arm.10.74:
  %t75 = getelementptr ptr, ptr %t5, i32 1
  %t76 = load ptr, ptr %t75
  call void @__inc_ref(ptr %t76)
  call void @__inc_ref(ptr %t6)
  %t77 = call ptr @__alloc(i64 16, i32 1)
  %t78 = inttoptr i64 10 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  %t80 = call ptr @__alloc(i64 16, i32 1)
  %t81 = inttoptr i64 37 to ptr
  %t82 = getelementptr ptr, ptr %t80, i32 0
  store ptr %t81, ptr %t82
  call void @__inc_ref(ptr %t76)
  %t83 = getelementptr ptr, ptr %t80, i32 1
  store ptr %t76, ptr %t83
  %t84 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t80, ptr %t84
  %t85 = call ptr @v__apply__lift_20(ptr %t6, ptr %t77)
  call void @__free_recursive(ptr %t76)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t85, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t86 = load ptr, ptr %t2
  ret ptr %t86
}

define internal ptr @v__apply__lift_20(ptr %v__k, ptr %v__x) {
entry:
  %t3 = alloca ptr
  store ptr %v__k, ptr %t3
  %t4 = alloca ptr
  store ptr %v__x, ptr %t4
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t5 = load ptr, ptr %t3
  %t6 = load ptr, ptr %t4
  %t7 = getelementptr ptr, ptr %t5, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %tco.case.default.10 [ i64 57, label %tco.case.arm.57.11 i64 58, label %tco.case.arm.58.12 ]
tco.case.arm.57.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.58.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  %t15 = getelementptr ptr, ptr %t5, i32 2
  %t16 = load ptr, ptr %t15
  %t17 = getelementptr i8, ptr %t5, i64 -8
  %t18 = load i32, ptr %t17
  %t19 = icmp eq i32 %t18, 1
  br i1 %t19, label %reuse.in_place.20, label %reuse.copy.21
reuse.in_place.20:
  %t23 = getelementptr ptr, ptr %t5, i32 1
  %t24 = load ptr, ptr %t23
  call void @__free_recursive(ptr %t24)
  %t27 = inttoptr i64 7 to ptr
  %t28 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t27, ptr %t28
  %t25 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t16, ptr %t25
  call void @__inc_ref(ptr %t6)
  %t26 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t6, ptr %t26
  br label %reuse.join.22
reuse.copy.21:
  %t29 = call ptr @__alloc(i64 24, i32 2)
  %t30 = inttoptr i64 7 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  call void @__inc_ref(ptr %t16)
  %t32 = getelementptr ptr, ptr %t29, i32 1
  store ptr %t16, ptr %t32
  call void @__inc_ref(ptr %t6)
  %t33 = getelementptr ptr, ptr %t29, i32 2
  store ptr %t6, ptr %t33
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.22
reuse.join.22:
  %t34 = phi ptr [ %t5, %reuse.in_place.20 ], [ %t29, %reuse.copy.21 ]
  call void @__inc_ref(ptr %t14)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t14)
  store ptr %t14, ptr %t3
  store ptr %t34, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t35 = load ptr, ptr %t2
  ret ptr %t35
}

define internal ptr @v__lift_27(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 59 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__lift_27(ptr %v___input, ptr %t0)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t3
}

define internal ptr @v__cps__lift_27(ptr %v___input, ptr %v__k) {
entry:
  %t3 = alloca ptr
  store ptr %v___input, ptr %t3
  %t4 = alloca ptr
  store ptr %v__k, ptr %t4
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t5 = load ptr, ptr %t3
  %t6 = load ptr, ptr %t4
  %t7 = getelementptr ptr, ptr %t5, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.19 i64 7, label %tco.case.arm.7.27 i64 8, label %tco.case.arm.8.50 i64 9, label %tco.case.arm.9.62 i64 10, label %tco.case.arm.10.74 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  %t14 = call ptr @__alloc(i64 16, i32 1)
  %t15 = inttoptr i64 5 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  call void @__inc_ref(ptr %t13)
  %t17 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t13, ptr %t17
  %t18 = call ptr @v__apply__lift_27(ptr %t6, ptr %t14)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t18, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.19:
  %t20 = getelementptr ptr, ptr %t5, i32 1
  %t21 = load ptr, ptr %t20
  call void @__inc_ref(ptr %t21)
  call void @__inc_ref(ptr %t6)
  %t22 = call ptr @__alloc(i64 16, i32 1)
  %t23 = inttoptr i64 6 to ptr
  %t24 = getelementptr ptr, ptr %t22, i32 0
  store ptr %t23, ptr %t24
  call void @__inc_ref(ptr %t21)
  %t25 = getelementptr ptr, ptr %t22, i32 1
  store ptr %t21, ptr %t25
  %t26 = call ptr @v__apply__lift_27(ptr %t6, ptr %t22)
  call void @__free_recursive(ptr %t21)
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
  %t32 = getelementptr i8, ptr %t5, i64 -8
  %t33 = load i32, ptr %t32
  %t34 = icmp eq i32 %t33, 1
  br i1 %t34, label %reuse.in_place.35, label %reuse.copy.36
reuse.in_place.35:
  %t38 = getelementptr ptr, ptr %t5, i32 2
  %t39 = load ptr, ptr %t38
  call void @__free_recursive(ptr %t39)
  %t42 = inttoptr i64 60 to ptr
  %t43 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t42, ptr %t43
  call void @__inc_ref(ptr %t6)
  %t40 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t40
  %t41 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t29, ptr %t41
  br label %reuse.join.37
reuse.copy.36:
  %t44 = call ptr @__alloc(i64 24, i32 2)
  %t45 = inttoptr i64 60 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  call void @__inc_ref(ptr %t6)
  %t47 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t6, ptr %t47
  call void @__inc_ref(ptr %t29)
  %t48 = getelementptr ptr, ptr %t44, i32 2
  store ptr %t29, ptr %t48
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.37
reuse.join.37:
  %t49 = phi ptr [ %t5, %reuse.in_place.35 ], [ %t44, %reuse.copy.36 ]
  call void @__inc_ref(ptr %t31)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t31)
  store ptr %t31, ptr %t3
  store ptr %t49, ptr %t4
  br label %tco.loop.0
tco.case.arm.8.50:
  %t51 = getelementptr ptr, ptr %t5, i32 1
  %t52 = load ptr, ptr %t51
  call void @__inc_ref(ptr %t52)
  call void @__inc_ref(ptr %t6)
  %t53 = call ptr @__alloc(i64 16, i32 1)
  %t54 = inttoptr i64 8 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  %t56 = call ptr @__alloc(i64 16, i32 1)
  %t57 = inttoptr i64 38 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  call void @__inc_ref(ptr %t52)
  %t59 = getelementptr ptr, ptr %t56, i32 1
  store ptr %t52, ptr %t59
  %t60 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t56, ptr %t60
  %t61 = call ptr @v__apply__lift_27(ptr %t6, ptr %t53)
  call void @__free_recursive(ptr %t52)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t61, ptr %t2
  br label %tco.exit.1
tco.case.arm.9.62:
  %t63 = getelementptr ptr, ptr %t5, i32 1
  %t64 = load ptr, ptr %t63
  call void @__inc_ref(ptr %t64)
  call void @__inc_ref(ptr %t6)
  %t65 = call ptr @__alloc(i64 16, i32 1)
  %t66 = inttoptr i64 9 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  %t68 = call ptr @__alloc(i64 16, i32 1)
  %t69 = inttoptr i64 39 to ptr
  %t70 = getelementptr ptr, ptr %t68, i32 0
  store ptr %t69, ptr %t70
  call void @__inc_ref(ptr %t64)
  %t71 = getelementptr ptr, ptr %t68, i32 1
  store ptr %t64, ptr %t71
  %t72 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t68, ptr %t72
  %t73 = call ptr @v__apply__lift_27(ptr %t6, ptr %t65)
  call void @__free_recursive(ptr %t64)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t73, ptr %t2
  br label %tco.exit.1
tco.case.arm.10.74:
  %t75 = getelementptr ptr, ptr %t5, i32 1
  %t76 = load ptr, ptr %t75
  call void @__inc_ref(ptr %t76)
  call void @__inc_ref(ptr %t6)
  %t77 = call ptr @__alloc(i64 16, i32 1)
  %t78 = inttoptr i64 10 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  %t80 = call ptr @__alloc(i64 16, i32 1)
  %t81 = inttoptr i64 40 to ptr
  %t82 = getelementptr ptr, ptr %t80, i32 0
  store ptr %t81, ptr %t82
  call void @__inc_ref(ptr %t76)
  %t83 = getelementptr ptr, ptr %t80, i32 1
  store ptr %t76, ptr %t83
  %t84 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t80, ptr %t84
  %t85 = call ptr @v__apply__lift_27(ptr %t6, ptr %t77)
  call void @__free_recursive(ptr %t76)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t85, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t86 = load ptr, ptr %t2
  ret ptr %t86
}

define internal ptr @v__apply__lift_27(ptr %v__k, ptr %v__x) {
entry:
  %t3 = alloca ptr
  store ptr %v__k, ptr %t3
  %t4 = alloca ptr
  store ptr %v__x, ptr %t4
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t5 = load ptr, ptr %t3
  %t6 = load ptr, ptr %t4
  %t7 = getelementptr ptr, ptr %t5, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %tco.case.default.10 [ i64 59, label %tco.case.arm.59.11 i64 60, label %tco.case.arm.60.12 ]
tco.case.arm.59.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.60.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  %t15 = getelementptr ptr, ptr %t5, i32 2
  %t16 = load ptr, ptr %t15
  %t17 = getelementptr i8, ptr %t5, i64 -8
  %t18 = load i32, ptr %t17
  %t19 = icmp eq i32 %t18, 1
  br i1 %t19, label %reuse.in_place.20, label %reuse.copy.21
reuse.in_place.20:
  %t23 = getelementptr ptr, ptr %t5, i32 1
  %t24 = load ptr, ptr %t23
  call void @__free_recursive(ptr %t24)
  %t27 = inttoptr i64 7 to ptr
  %t28 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t27, ptr %t28
  %t25 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t16, ptr %t25
  call void @__inc_ref(ptr %t6)
  %t26 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t6, ptr %t26
  br label %reuse.join.22
reuse.copy.21:
  %t29 = call ptr @__alloc(i64 24, i32 2)
  %t30 = inttoptr i64 7 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  call void @__inc_ref(ptr %t16)
  %t32 = getelementptr ptr, ptr %t29, i32 1
  store ptr %t16, ptr %t32
  call void @__inc_ref(ptr %t6)
  %t33 = getelementptr ptr, ptr %t29, i32 2
  store ptr %t6, ptr %t33
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.22
reuse.join.22:
  %t34 = phi ptr [ %t5, %reuse.in_place.20 ], [ %t29, %reuse.copy.21 ]
  call void @__inc_ref(ptr %t14)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t14)
  store ptr %t14, ptr %t3
  store ptr %t34, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t35 = load ptr, ptr %t2
  ret ptr %t35
}

define internal ptr @v__io_getargs_cont(ptr %v_result) {
  %t0 = getelementptr ptr, ptr %v_result, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.11 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v_result, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = call ptr @__alloc(i64 16, i32 1)
  %t8 = inttoptr i64 6 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  call void @__inc_ref(ptr %t6)
  %t10 = getelementptr ptr, ptr %t7, i32 1
  store ptr %t6, ptr %t10
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_result)
  ret ptr %t7
case.arm.4.11:
  %t12 = getelementptr ptr, ptr %v_result, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @__alloc(i64 16, i32 1)
  %t15 = inttoptr i64 5 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  call void @__inc_ref(ptr %t13)
  %t17 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t13, ptr %t17
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %v_result)
  ret ptr %t14
case.default.3:
  unreachable
}

define internal ptr @v__bi_IO_Stdout_print(ptr %v__x0) {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 7 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  call void @__inc_ref(ptr %v__x0)
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v__x0, ptr %t3
  %t4 = call ptr @__alloc(i64 16, i32 1)
  %t5 = inttoptr i64 5 to ptr
  %t6 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5, ptr %t6
  %t7 = call ptr @__alloc(i64 8, i32 0)
  %t8 = inttoptr i64 0 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t7, ptr %t10
  %t11 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t4, ptr %t11
  call void @__free_recursive(ptr %v__x0)
  ret ptr %t0
}

define internal ptr @v__df_handleErrorIO_0(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 61 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_handleErrorIO_0(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_handleErrorIO_0(ptr %v_io, ptr %v__k) {
entry:
  %t3 = alloca ptr
  store ptr %v_io, ptr %t3
  %t4 = alloca ptr
  store ptr %v__k, ptr %t4
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t5 = load ptr, ptr %t3
  %t6 = load ptr, ptr %t4
  %t7 = getelementptr ptr, ptr %t5, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.19 i64 7, label %tco.case.arm.7.24 i64 8, label %tco.case.arm.8.47 i64 9, label %tco.case.arm.9.59 i64 10, label %tco.case.arm.10.71 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  %t14 = call ptr @__alloc(i64 16, i32 1)
  %t15 = inttoptr i64 5 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  call void @__inc_ref(ptr %t13)
  %t17 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t13, ptr %t17
  %t18 = call ptr @v__apply__df_handleErrorIO_0(ptr %t6, ptr %t14)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t18, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.19:
  %t20 = getelementptr ptr, ptr %t5, i32 1
  %t21 = load ptr, ptr %t20
  call void @__inc_ref(ptr %t21)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t21)
  %t22 = call ptr @v_printError(ptr %t21)
  %t23 = call ptr @v__apply__df_handleErrorIO_0(ptr %t6, ptr %t22)
  call void @__free_recursive(ptr %t21)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t23, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.24:
  %t25 = getelementptr ptr, ptr %t5, i32 1
  %t26 = load ptr, ptr %t25
  %t27 = getelementptr ptr, ptr %t5, i32 2
  %t28 = load ptr, ptr %t27
  call void @__inc_ref(ptr %t28)
  %t29 = getelementptr i8, ptr %t5, i64 -8
  %t30 = load i32, ptr %t29
  %t31 = icmp eq i32 %t30, 1
  br i1 %t31, label %reuse.in_place.32, label %reuse.copy.33
reuse.in_place.32:
  %t35 = getelementptr ptr, ptr %t5, i32 2
  %t36 = load ptr, ptr %t35
  call void @__free_recursive(ptr %t36)
  %t39 = inttoptr i64 62 to ptr
  %t40 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t39, ptr %t40
  call void @__inc_ref(ptr %t6)
  %t37 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t37
  %t38 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t26, ptr %t38
  br label %reuse.join.34
reuse.copy.33:
  %t41 = call ptr @__alloc(i64 24, i32 2)
  %t42 = inttoptr i64 62 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  call void @__inc_ref(ptr %t6)
  %t44 = getelementptr ptr, ptr %t41, i32 1
  store ptr %t6, ptr %t44
  call void @__inc_ref(ptr %t26)
  %t45 = getelementptr ptr, ptr %t41, i32 2
  store ptr %t26, ptr %t45
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.34
reuse.join.34:
  %t46 = phi ptr [ %t5, %reuse.in_place.32 ], [ %t41, %reuse.copy.33 ]
  call void @__inc_ref(ptr %t28)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t28)
  store ptr %t28, ptr %t3
  store ptr %t46, ptr %t4
  br label %tco.loop.0
tco.case.arm.8.47:
  %t48 = getelementptr ptr, ptr %t5, i32 1
  %t49 = load ptr, ptr %t48
  call void @__inc_ref(ptr %t49)
  call void @__inc_ref(ptr %t6)
  %t50 = call ptr @__alloc(i64 16, i32 1)
  %t51 = inttoptr i64 8 to ptr
  %t52 = getelementptr ptr, ptr %t50, i32 0
  store ptr %t51, ptr %t52
  %t53 = call ptr @__alloc(i64 16, i32 1)
  %t54 = inttoptr i64 25 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  call void @__inc_ref(ptr %t49)
  %t56 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t49, ptr %t56
  %t57 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t53, ptr %t57
  %t58 = call ptr @v__apply__df_handleErrorIO_0(ptr %t6, ptr %t50)
  call void @__free_recursive(ptr %t49)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t58, ptr %t2
  br label %tco.exit.1
tco.case.arm.9.59:
  %t60 = getelementptr ptr, ptr %t5, i32 1
  %t61 = load ptr, ptr %t60
  call void @__inc_ref(ptr %t61)
  call void @__inc_ref(ptr %t6)
  %t62 = call ptr @__alloc(i64 16, i32 1)
  %t63 = inttoptr i64 9 to ptr
  %t64 = getelementptr ptr, ptr %t62, i32 0
  store ptr %t63, ptr %t64
  %t65 = call ptr @__alloc(i64 16, i32 1)
  %t66 = inttoptr i64 26 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  call void @__inc_ref(ptr %t61)
  %t68 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t61, ptr %t68
  %t69 = getelementptr ptr, ptr %t62, i32 1
  store ptr %t65, ptr %t69
  %t70 = call ptr @v__apply__df_handleErrorIO_0(ptr %t6, ptr %t62)
  call void @__free_recursive(ptr %t61)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t70, ptr %t2
  br label %tco.exit.1
tco.case.arm.10.71:
  %t72 = getelementptr ptr, ptr %t5, i32 1
  %t73 = load ptr, ptr %t72
  call void @__inc_ref(ptr %t73)
  call void @__inc_ref(ptr %t6)
  %t74 = call ptr @__alloc(i64 16, i32 1)
  %t75 = inttoptr i64 10 to ptr
  %t76 = getelementptr ptr, ptr %t74, i32 0
  store ptr %t75, ptr %t76
  %t77 = call ptr @__alloc(i64 16, i32 1)
  %t78 = inttoptr i64 27 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  call void @__inc_ref(ptr %t73)
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t73, ptr %t80
  %t81 = getelementptr ptr, ptr %t74, i32 1
  store ptr %t77, ptr %t81
  %t82 = call ptr @v__apply__df_handleErrorIO_0(ptr %t6, ptr %t74)
  call void @__free_recursive(ptr %t73)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t82, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t83 = load ptr, ptr %t2
  ret ptr %t83
}

define internal ptr @v__apply__df_handleErrorIO_0(ptr %v__k, ptr %v__x) {
entry:
  %t3 = alloca ptr
  store ptr %v__k, ptr %t3
  %t4 = alloca ptr
  store ptr %v__x, ptr %t4
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t5 = load ptr, ptr %t3
  %t6 = load ptr, ptr %t4
  %t7 = getelementptr ptr, ptr %t5, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %tco.case.default.10 [ i64 61, label %tco.case.arm.61.11 i64 62, label %tco.case.arm.62.12 ]
tco.case.arm.61.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.62.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  %t15 = getelementptr ptr, ptr %t5, i32 2
  %t16 = load ptr, ptr %t15
  %t17 = getelementptr i8, ptr %t5, i64 -8
  %t18 = load i32, ptr %t17
  %t19 = icmp eq i32 %t18, 1
  br i1 %t19, label %reuse.in_place.20, label %reuse.copy.21
reuse.in_place.20:
  %t23 = getelementptr ptr, ptr %t5, i32 1
  %t24 = load ptr, ptr %t23
  call void @__free_recursive(ptr %t24)
  %t27 = inttoptr i64 7 to ptr
  %t28 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t27, ptr %t28
  %t25 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t16, ptr %t25
  call void @__inc_ref(ptr %t6)
  %t26 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t6, ptr %t26
  br label %reuse.join.22
reuse.copy.21:
  %t29 = call ptr @__alloc(i64 24, i32 2)
  %t30 = inttoptr i64 7 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  call void @__inc_ref(ptr %t16)
  %t32 = getelementptr ptr, ptr %t29, i32 1
  store ptr %t16, ptr %t32
  call void @__inc_ref(ptr %t6)
  %t33 = getelementptr ptr, ptr %t29, i32 2
  store ptr %t6, ptr %t33
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.22
reuse.join.22:
  %t34 = phi ptr [ %t5, %reuse.in_place.20 ], [ %t29, %reuse.copy.21 ]
  call void @__inc_ref(ptr %t14)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t14)
  store ptr %t14, ptr %t3
  store ptr %t34, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t35 = load ptr, ptr %t2
  ret ptr %t35
}

define internal ptr @v__df__rowmono_0_andThenIO_4(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 63 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df__rowmono_0_andThenIO_4(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df__rowmono_0_andThenIO_4(ptr %v_io, ptr %v__k) {
entry:
  %t3 = alloca ptr
  store ptr %v_io, ptr %t3
  %t4 = alloca ptr
  store ptr %v__k, ptr %t4
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t5 = load ptr, ptr %t3
  %t6 = load ptr, ptr %t4
  %t7 = getelementptr ptr, ptr %t5, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.17 i64 7, label %tco.case.arm.7.25 i64 8, label %tco.case.arm.8.48 i64 9, label %tco.case.arm.9.60 i64 10, label %tco.case.arm.10.72 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__bi_IO_Stdout_print(ptr %t13)
  %t15 = call ptr @v__lift_20(ptr %t14)
  %t16 = call ptr @v__apply__df__rowmono_0_andThenIO_4(ptr %t6, ptr %t15)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t16, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.17:
  %t18 = getelementptr ptr, ptr %t5, i32 1
  %t19 = load ptr, ptr %t18
  call void @__inc_ref(ptr %t19)
  call void @__inc_ref(ptr %t6)
  %t20 = call ptr @__alloc(i64 16, i32 1)
  %t21 = inttoptr i64 6 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  call void @__inc_ref(ptr %t19)
  %t23 = getelementptr ptr, ptr %t20, i32 1
  store ptr %t19, ptr %t23
  %t24 = call ptr @v__apply__df__rowmono_0_andThenIO_4(ptr %t6, ptr %t20)
  call void @__free_recursive(ptr %t19)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t24, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.25:
  %t26 = getelementptr ptr, ptr %t5, i32 1
  %t27 = load ptr, ptr %t26
  %t28 = getelementptr ptr, ptr %t5, i32 2
  %t29 = load ptr, ptr %t28
  call void @__inc_ref(ptr %t29)
  %t30 = getelementptr i8, ptr %t5, i64 -8
  %t31 = load i32, ptr %t30
  %t32 = icmp eq i32 %t31, 1
  br i1 %t32, label %reuse.in_place.33, label %reuse.copy.34
reuse.in_place.33:
  %t36 = getelementptr ptr, ptr %t5, i32 2
  %t37 = load ptr, ptr %t36
  call void @__free_recursive(ptr %t37)
  %t40 = inttoptr i64 64 to ptr
  %t41 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t40, ptr %t41
  call void @__inc_ref(ptr %t6)
  %t38 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t38
  %t39 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t27, ptr %t39
  br label %reuse.join.35
reuse.copy.34:
  %t42 = call ptr @__alloc(i64 24, i32 2)
  %t43 = inttoptr i64 64 to ptr
  %t44 = getelementptr ptr, ptr %t42, i32 0
  store ptr %t43, ptr %t44
  call void @__inc_ref(ptr %t6)
  %t45 = getelementptr ptr, ptr %t42, i32 1
  store ptr %t6, ptr %t45
  call void @__inc_ref(ptr %t27)
  %t46 = getelementptr ptr, ptr %t42, i32 2
  store ptr %t27, ptr %t46
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.35
reuse.join.35:
  %t47 = phi ptr [ %t5, %reuse.in_place.33 ], [ %t42, %reuse.copy.34 ]
  call void @__inc_ref(ptr %t29)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t29)
  store ptr %t29, ptr %t3
  store ptr %t47, ptr %t4
  br label %tco.loop.0
tco.case.arm.8.48:
  %t49 = getelementptr ptr, ptr %t5, i32 1
  %t50 = load ptr, ptr %t49
  call void @__inc_ref(ptr %t50)
  call void @__inc_ref(ptr %t6)
  %t51 = call ptr @__alloc(i64 16, i32 1)
  %t52 = inttoptr i64 8 to ptr
  %t53 = getelementptr ptr, ptr %t51, i32 0
  store ptr %t52, ptr %t53
  %t54 = call ptr @__alloc(i64 16, i32 1)
  %t55 = inttoptr i64 28 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df__rowmono_0_andThenIO_4(ptr %t6, ptr %t51)
  call void @__free_recursive(ptr %t50)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t59, ptr %t2
  br label %tco.exit.1
tco.case.arm.9.60:
  %t61 = getelementptr ptr, ptr %t5, i32 1
  %t62 = load ptr, ptr %t61
  call void @__inc_ref(ptr %t62)
  call void @__inc_ref(ptr %t6)
  %t63 = call ptr @__alloc(i64 16, i32 1)
  %t64 = inttoptr i64 9 to ptr
  %t65 = getelementptr ptr, ptr %t63, i32 0
  store ptr %t64, ptr %t65
  %t66 = call ptr @__alloc(i64 16, i32 1)
  %t67 = inttoptr i64 29 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df__rowmono_0_andThenIO_4(ptr %t6, ptr %t63)
  call void @__free_recursive(ptr %t62)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.arm.10.72:
  %t73 = getelementptr ptr, ptr %t5, i32 1
  %t74 = load ptr, ptr %t73
  call void @__inc_ref(ptr %t74)
  call void @__inc_ref(ptr %t6)
  %t75 = call ptr @__alloc(i64 16, i32 1)
  %t76 = inttoptr i64 10 to ptr
  %t77 = getelementptr ptr, ptr %t75, i32 0
  store ptr %t76, ptr %t77
  %t78 = call ptr @__alloc(i64 16, i32 1)
  %t79 = inttoptr i64 30 to ptr
  %t80 = getelementptr ptr, ptr %t78, i32 0
  store ptr %t79, ptr %t80
  call void @__inc_ref(ptr %t74)
  %t81 = getelementptr ptr, ptr %t78, i32 1
  store ptr %t74, ptr %t81
  %t82 = getelementptr ptr, ptr %t75, i32 1
  store ptr %t78, ptr %t82
  %t83 = call ptr @v__apply__df__rowmono_0_andThenIO_4(ptr %t6, ptr %t75)
  call void @__free_recursive(ptr %t74)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t83, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t84 = load ptr, ptr %t2
  ret ptr %t84
}

define internal ptr @v__apply__df__rowmono_0_andThenIO_4(ptr %v__k, ptr %v__x) {
entry:
  %t3 = alloca ptr
  store ptr %v__k, ptr %t3
  %t4 = alloca ptr
  store ptr %v__x, ptr %t4
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t5 = load ptr, ptr %t3
  %t6 = load ptr, ptr %t4
  %t7 = getelementptr ptr, ptr %t5, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %tco.case.default.10 [ i64 63, label %tco.case.arm.63.11 i64 64, label %tco.case.arm.64.12 ]
tco.case.arm.63.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.64.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  %t15 = getelementptr ptr, ptr %t5, i32 2
  %t16 = load ptr, ptr %t15
  %t17 = getelementptr i8, ptr %t5, i64 -8
  %t18 = load i32, ptr %t17
  %t19 = icmp eq i32 %t18, 1
  br i1 %t19, label %reuse.in_place.20, label %reuse.copy.21
reuse.in_place.20:
  %t23 = getelementptr ptr, ptr %t5, i32 1
  %t24 = load ptr, ptr %t23
  call void @__free_recursive(ptr %t24)
  %t27 = inttoptr i64 7 to ptr
  %t28 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t27, ptr %t28
  %t25 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t16, ptr %t25
  call void @__inc_ref(ptr %t6)
  %t26 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t6, ptr %t26
  br label %reuse.join.22
reuse.copy.21:
  %t29 = call ptr @__alloc(i64 24, i32 2)
  %t30 = inttoptr i64 7 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  call void @__inc_ref(ptr %t16)
  %t32 = getelementptr ptr, ptr %t29, i32 1
  store ptr %t16, ptr %t32
  call void @__inc_ref(ptr %t6)
  %t33 = getelementptr ptr, ptr %t29, i32 2
  store ptr %t6, ptr %t33
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.22
reuse.join.22:
  %t34 = phi ptr [ %t5, %reuse.in_place.20 ], [ %t29, %reuse.copy.21 ]
  call void @__inc_ref(ptr %t14)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t14)
  store ptr %t14, ptr %t3
  store ptr %t34, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t35 = load ptr, ptr %t2
  ret ptr %t35
}

define internal ptr @v__df__rowmono_1_andThenIO_8(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 65 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df__rowmono_1_andThenIO_8(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df__rowmono_1_andThenIO_8(ptr %v_io, ptr %v__k) {
entry:
  %t3 = alloca ptr
  store ptr %v_io, ptr %t3
  %t4 = alloca ptr
  store ptr %v__k, ptr %t4
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t5 = load ptr, ptr %t3
  %t6 = load ptr, ptr %t4
  %t7 = getelementptr ptr, ptr %t5, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.17 i64 7, label %tco.case.arm.7.25 i64 8, label %tco.case.arm.8.48 i64 9, label %tco.case.arm.9.60 i64 10, label %tco.case.arm.10.72 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_18(ptr %t13)
  %t15 = call ptr @v__lift_27(ptr %t14)
  %t16 = call ptr @v__apply__df__rowmono_1_andThenIO_8(ptr %t6, ptr %t15)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t16, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.17:
  %t18 = getelementptr ptr, ptr %t5, i32 1
  %t19 = load ptr, ptr %t18
  call void @__inc_ref(ptr %t19)
  call void @__inc_ref(ptr %t6)
  %t20 = call ptr @__alloc(i64 16, i32 1)
  %t21 = inttoptr i64 6 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  call void @__inc_ref(ptr %t19)
  %t23 = getelementptr ptr, ptr %t20, i32 1
  store ptr %t19, ptr %t23
  %t24 = call ptr @v__apply__df__rowmono_1_andThenIO_8(ptr %t6, ptr %t20)
  call void @__free_recursive(ptr %t19)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t24, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.25:
  %t26 = getelementptr ptr, ptr %t5, i32 1
  %t27 = load ptr, ptr %t26
  %t28 = getelementptr ptr, ptr %t5, i32 2
  %t29 = load ptr, ptr %t28
  call void @__inc_ref(ptr %t29)
  %t30 = getelementptr i8, ptr %t5, i64 -8
  %t31 = load i32, ptr %t30
  %t32 = icmp eq i32 %t31, 1
  br i1 %t32, label %reuse.in_place.33, label %reuse.copy.34
reuse.in_place.33:
  %t36 = getelementptr ptr, ptr %t5, i32 2
  %t37 = load ptr, ptr %t36
  call void @__free_recursive(ptr %t37)
  %t40 = inttoptr i64 66 to ptr
  %t41 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t40, ptr %t41
  call void @__inc_ref(ptr %t6)
  %t38 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t38
  %t39 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t27, ptr %t39
  br label %reuse.join.35
reuse.copy.34:
  %t42 = call ptr @__alloc(i64 24, i32 2)
  %t43 = inttoptr i64 66 to ptr
  %t44 = getelementptr ptr, ptr %t42, i32 0
  store ptr %t43, ptr %t44
  call void @__inc_ref(ptr %t6)
  %t45 = getelementptr ptr, ptr %t42, i32 1
  store ptr %t6, ptr %t45
  call void @__inc_ref(ptr %t27)
  %t46 = getelementptr ptr, ptr %t42, i32 2
  store ptr %t27, ptr %t46
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.35
reuse.join.35:
  %t47 = phi ptr [ %t5, %reuse.in_place.33 ], [ %t42, %reuse.copy.34 ]
  call void @__inc_ref(ptr %t29)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t29)
  store ptr %t29, ptr %t3
  store ptr %t47, ptr %t4
  br label %tco.loop.0
tco.case.arm.8.48:
  %t49 = getelementptr ptr, ptr %t5, i32 1
  %t50 = load ptr, ptr %t49
  call void @__inc_ref(ptr %t50)
  call void @__inc_ref(ptr %t6)
  %t51 = call ptr @__alloc(i64 16, i32 1)
  %t52 = inttoptr i64 8 to ptr
  %t53 = getelementptr ptr, ptr %t51, i32 0
  store ptr %t52, ptr %t53
  %t54 = call ptr @__alloc(i64 16, i32 1)
  %t55 = inttoptr i64 31 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df__rowmono_1_andThenIO_8(ptr %t6, ptr %t51)
  call void @__free_recursive(ptr %t50)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t59, ptr %t2
  br label %tco.exit.1
tco.case.arm.9.60:
  %t61 = getelementptr ptr, ptr %t5, i32 1
  %t62 = load ptr, ptr %t61
  call void @__inc_ref(ptr %t62)
  call void @__inc_ref(ptr %t6)
  %t63 = call ptr @__alloc(i64 16, i32 1)
  %t64 = inttoptr i64 9 to ptr
  %t65 = getelementptr ptr, ptr %t63, i32 0
  store ptr %t64, ptr %t65
  %t66 = call ptr @__alloc(i64 16, i32 1)
  %t67 = inttoptr i64 32 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df__rowmono_1_andThenIO_8(ptr %t6, ptr %t63)
  call void @__free_recursive(ptr %t62)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.arm.10.72:
  %t73 = getelementptr ptr, ptr %t5, i32 1
  %t74 = load ptr, ptr %t73
  call void @__inc_ref(ptr %t74)
  call void @__inc_ref(ptr %t6)
  %t75 = call ptr @__alloc(i64 16, i32 1)
  %t76 = inttoptr i64 10 to ptr
  %t77 = getelementptr ptr, ptr %t75, i32 0
  store ptr %t76, ptr %t77
  %t78 = call ptr @__alloc(i64 16, i32 1)
  %t79 = inttoptr i64 33 to ptr
  %t80 = getelementptr ptr, ptr %t78, i32 0
  store ptr %t79, ptr %t80
  call void @__inc_ref(ptr %t74)
  %t81 = getelementptr ptr, ptr %t78, i32 1
  store ptr %t74, ptr %t81
  %t82 = getelementptr ptr, ptr %t75, i32 1
  store ptr %t78, ptr %t82
  %t83 = call ptr @v__apply__df__rowmono_1_andThenIO_8(ptr %t6, ptr %t75)
  call void @__free_recursive(ptr %t74)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t83, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t84 = load ptr, ptr %t2
  ret ptr %t84
}

define internal ptr @v__apply__df__rowmono_1_andThenIO_8(ptr %v__k, ptr %v__x) {
entry:
  %t3 = alloca ptr
  store ptr %v__k, ptr %t3
  %t4 = alloca ptr
  store ptr %v__x, ptr %t4
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t5 = load ptr, ptr %t3
  %t6 = load ptr, ptr %t4
  %t7 = getelementptr ptr, ptr %t5, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %tco.case.default.10 [ i64 65, label %tco.case.arm.65.11 i64 66, label %tco.case.arm.66.12 ]
tco.case.arm.65.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.66.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  %t15 = getelementptr ptr, ptr %t5, i32 2
  %t16 = load ptr, ptr %t15
  %t17 = getelementptr i8, ptr %t5, i64 -8
  %t18 = load i32, ptr %t17
  %t19 = icmp eq i32 %t18, 1
  br i1 %t19, label %reuse.in_place.20, label %reuse.copy.21
reuse.in_place.20:
  %t23 = getelementptr ptr, ptr %t5, i32 1
  %t24 = load ptr, ptr %t23
  call void @__free_recursive(ptr %t24)
  %t27 = inttoptr i64 7 to ptr
  %t28 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t27, ptr %t28
  %t25 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t16, ptr %t25
  call void @__inc_ref(ptr %t6)
  %t26 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t6, ptr %t26
  br label %reuse.join.22
reuse.copy.21:
  %t29 = call ptr @__alloc(i64 24, i32 2)
  %t30 = inttoptr i64 7 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  call void @__inc_ref(ptr %t16)
  %t32 = getelementptr ptr, ptr %t29, i32 1
  store ptr %t16, ptr %t32
  call void @__inc_ref(ptr %t6)
  %t33 = getelementptr ptr, ptr %t29, i32 2
  store ptr %t6, ptr %t33
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.22
reuse.join.22:
  %t34 = phi ptr [ %t5, %reuse.in_place.20 ], [ %t29, %reuse.copy.21 ]
  call void @__inc_ref(ptr %t14)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t14)
  store ptr %t14, ptr %t3
  store ptr %t34, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t35 = load ptr, ptr %t2
  ret ptr %t35
}

define internal ptr @v__scc__apply1__df__lam_14_1__df__lam_15_2__df__lam_16_3__df__lam_24_5__df__lam_25_6__df__lam_26_7__df__lam_31_9__df__lam_32_10__df__lam_33_11__lift_21__lift_22__lift_23__lift_28__lift_29__lift_30(ptr %v__args) {
  call void @__inc_ref(ptr %v__args)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 67 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__scc__apply1__df__lam_14_1__df__lam_15_2__df__lam_16_3__df__lam_24_5__df__lam_25_6__df__lam_26_7__df__lam_31_9__df__lam_32_10__df__lam_33_11__lift_21__lift_22__lift_23__lift_28__lift_29__lift_30(ptr %v__args, ptr %t0)
  call void @__free_recursive(ptr %v__args)
  ret ptr %t3
}

define internal ptr @v__cps__scc__apply1__df__lam_14_1__df__lam_15_2__df__lam_16_3__df__lam_24_5__df__lam_25_6__df__lam_26_7__df__lam_31_9__df__lam_32_10__df__lam_33_11__lift_21__lift_22__lift_23__lift_28__lift_29__lift_30(ptr %v__args, ptr %v__k) {
entry:
  %t3 = alloca ptr
  store ptr %v__args, ptr %t3
  %t4 = alloca ptr
  store ptr %v__k, ptr %t4
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t5 = load ptr, ptr %t3
  %t6 = load ptr, ptr %t4
  %t7 = getelementptr ptr, ptr %t5, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %tco.case.default.10 [ i64 41, label %tco.case.arm.41.11 i64 42, label %tco.case.arm.42.323 i64 43, label %tco.case.arm.43.346 i64 44, label %tco.case.arm.44.369 i64 45, label %tco.case.arm.45.392 i64 46, label %tco.case.arm.46.415 i64 47, label %tco.case.arm.47.438 i64 48, label %tco.case.arm.48.461 i64 49, label %tco.case.arm.49.484 i64 50, label %tco.case.arm.50.507 i64 51, label %tco.case.arm.51.530 i64 52, label %tco.case.arm.52.553 i64 53, label %tco.case.arm.53.576 i64 54, label %tco.case.arm.54.599 i64 55, label %tco.case.arm.55.622 i64 56, label %tco.case.arm.56.645 ]
tco.case.arm.41.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t5, i32 2
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  %t16 = getelementptr ptr, ptr %t13, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %tco.case.default.19 [ i64 25, label %tco.case.arm.25.20 i64 26, label %tco.case.arm.26.40 i64 27, label %tco.case.arm.27.60 i64 28, label %tco.case.arm.28.80 i64 29, label %tco.case.arm.29.100 i64 30, label %tco.case.arm.30.120 i64 31, label %tco.case.arm.31.140 i64 32, label %tco.case.arm.32.160 i64 33, label %tco.case.arm.33.180 i64 34, label %tco.case.arm.34.200 i64 35, label %tco.case.arm.35.203 i64 36, label %tco.case.arm.36.223 i64 37, label %tco.case.arm.37.243 i64 38, label %tco.case.arm.38.263 i64 39, label %tco.case.arm.39.283 i64 40, label %tco.case.arm.40.303 ]
tco.case.arm.25.20:
  %t21 = getelementptr ptr, ptr %t13, i32 1
  %t22 = load ptr, ptr %t21
  call void @__inc_ref(ptr %t22)
  %t23 = getelementptr i8, ptr %t5, i64 -8
  %t24 = load i32, ptr %t23
  %t25 = icmp eq i32 %t24, 1
  br i1 %t25, label %reuse.in_place.26, label %reuse.copy.27
reuse.in_place.26:
  %t29 = getelementptr ptr, ptr %t5, i32 1
  %t30 = load ptr, ptr %t29
  call void @__free_recursive(ptr %t30)
  %t32 = inttoptr i64 42 to ptr
  %t33 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t32, ptr %t33
  call void @__inc_ref(ptr %t22)
  %t31 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t22, ptr %t31
  br label %reuse.join.28
reuse.copy.27:
  %t34 = call ptr @__alloc(i64 24, i32 2)
  %t35 = inttoptr i64 42 to ptr
  %t36 = getelementptr ptr, ptr %t34, i32 0
  store ptr %t35, ptr %t36
  call void @__inc_ref(ptr %t22)
  %t37 = getelementptr ptr, ptr %t34, i32 1
  store ptr %t22, ptr %t37
  call void @__inc_ref(ptr %t15)
  %t38 = getelementptr ptr, ptr %t34, i32 2
  store ptr %t15, ptr %t38
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.28
reuse.join.28:
  %t39 = phi ptr [ %t5, %reuse.in_place.26 ], [ %t34, %reuse.copy.27 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t22)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t39, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.26.40:
  %t41 = getelementptr ptr, ptr %t13, i32 1
  %t42 = load ptr, ptr %t41
  call void @__inc_ref(ptr %t42)
  %t43 = getelementptr i8, ptr %t5, i64 -8
  %t44 = load i32, ptr %t43
  %t45 = icmp eq i32 %t44, 1
  br i1 %t45, label %reuse.in_place.46, label %reuse.copy.47
reuse.in_place.46:
  %t49 = getelementptr ptr, ptr %t5, i32 1
  %t50 = load ptr, ptr %t49
  call void @__free_recursive(ptr %t50)
  %t52 = inttoptr i64 43 to ptr
  %t53 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t52, ptr %t53
  call void @__inc_ref(ptr %t42)
  %t51 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t42, ptr %t51
  br label %reuse.join.48
reuse.copy.47:
  %t54 = call ptr @__alloc(i64 24, i32 2)
  %t55 = inttoptr i64 43 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t42)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t42, ptr %t57
  call void @__inc_ref(ptr %t15)
  %t58 = getelementptr ptr, ptr %t54, i32 2
  store ptr %t15, ptr %t58
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.48
reuse.join.48:
  %t59 = phi ptr [ %t5, %reuse.in_place.46 ], [ %t54, %reuse.copy.47 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t42)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t59, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.27.60:
  %t61 = getelementptr ptr, ptr %t13, i32 1
  %t62 = load ptr, ptr %t61
  call void @__inc_ref(ptr %t62)
  %t63 = getelementptr i8, ptr %t5, i64 -8
  %t64 = load i32, ptr %t63
  %t65 = icmp eq i32 %t64, 1
  br i1 %t65, label %reuse.in_place.66, label %reuse.copy.67
reuse.in_place.66:
  %t69 = getelementptr ptr, ptr %t5, i32 1
  %t70 = load ptr, ptr %t69
  call void @__free_recursive(ptr %t70)
  %t72 = inttoptr i64 44 to ptr
  %t73 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t72, ptr %t73
  call void @__inc_ref(ptr %t62)
  %t71 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t62, ptr %t71
  br label %reuse.join.68
reuse.copy.67:
  %t74 = call ptr @__alloc(i64 24, i32 2)
  %t75 = inttoptr i64 44 to ptr
  %t76 = getelementptr ptr, ptr %t74, i32 0
  store ptr %t75, ptr %t76
  call void @__inc_ref(ptr %t62)
  %t77 = getelementptr ptr, ptr %t74, i32 1
  store ptr %t62, ptr %t77
  call void @__inc_ref(ptr %t15)
  %t78 = getelementptr ptr, ptr %t74, i32 2
  store ptr %t15, ptr %t78
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.68
reuse.join.68:
  %t79 = phi ptr [ %t5, %reuse.in_place.66 ], [ %t74, %reuse.copy.67 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t62)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t79, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.28.80:
  %t81 = getelementptr ptr, ptr %t13, i32 1
  %t82 = load ptr, ptr %t81
  call void @__inc_ref(ptr %t82)
  %t83 = getelementptr i8, ptr %t5, i64 -8
  %t84 = load i32, ptr %t83
  %t85 = icmp eq i32 %t84, 1
  br i1 %t85, label %reuse.in_place.86, label %reuse.copy.87
reuse.in_place.86:
  %t89 = getelementptr ptr, ptr %t5, i32 1
  %t90 = load ptr, ptr %t89
  call void @__free_recursive(ptr %t90)
  %t92 = inttoptr i64 45 to ptr
  %t93 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t92, ptr %t93
  call void @__inc_ref(ptr %t82)
  %t91 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t82, ptr %t91
  br label %reuse.join.88
reuse.copy.87:
  %t94 = call ptr @__alloc(i64 24, i32 2)
  %t95 = inttoptr i64 45 to ptr
  %t96 = getelementptr ptr, ptr %t94, i32 0
  store ptr %t95, ptr %t96
  call void @__inc_ref(ptr %t82)
  %t97 = getelementptr ptr, ptr %t94, i32 1
  store ptr %t82, ptr %t97
  call void @__inc_ref(ptr %t15)
  %t98 = getelementptr ptr, ptr %t94, i32 2
  store ptr %t15, ptr %t98
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.88
reuse.join.88:
  %t99 = phi ptr [ %t5, %reuse.in_place.86 ], [ %t94, %reuse.copy.87 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t82)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t99, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.29.100:
  %t101 = getelementptr ptr, ptr %t13, i32 1
  %t102 = load ptr, ptr %t101
  call void @__inc_ref(ptr %t102)
  %t103 = getelementptr i8, ptr %t5, i64 -8
  %t104 = load i32, ptr %t103
  %t105 = icmp eq i32 %t104, 1
  br i1 %t105, label %reuse.in_place.106, label %reuse.copy.107
reuse.in_place.106:
  %t109 = getelementptr ptr, ptr %t5, i32 1
  %t110 = load ptr, ptr %t109
  call void @__free_recursive(ptr %t110)
  %t112 = inttoptr i64 46 to ptr
  %t113 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t112, ptr %t113
  call void @__inc_ref(ptr %t102)
  %t111 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t102, ptr %t111
  br label %reuse.join.108
reuse.copy.107:
  %t114 = call ptr @__alloc(i64 24, i32 2)
  %t115 = inttoptr i64 46 to ptr
  %t116 = getelementptr ptr, ptr %t114, i32 0
  store ptr %t115, ptr %t116
  call void @__inc_ref(ptr %t102)
  %t117 = getelementptr ptr, ptr %t114, i32 1
  store ptr %t102, ptr %t117
  call void @__inc_ref(ptr %t15)
  %t118 = getelementptr ptr, ptr %t114, i32 2
  store ptr %t15, ptr %t118
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.108
reuse.join.108:
  %t119 = phi ptr [ %t5, %reuse.in_place.106 ], [ %t114, %reuse.copy.107 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t102)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t119, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.30.120:
  %t121 = getelementptr ptr, ptr %t13, i32 1
  %t122 = load ptr, ptr %t121
  call void @__inc_ref(ptr %t122)
  %t123 = getelementptr i8, ptr %t5, i64 -8
  %t124 = load i32, ptr %t123
  %t125 = icmp eq i32 %t124, 1
  br i1 %t125, label %reuse.in_place.126, label %reuse.copy.127
reuse.in_place.126:
  %t129 = getelementptr ptr, ptr %t5, i32 1
  %t130 = load ptr, ptr %t129
  call void @__free_recursive(ptr %t130)
  %t132 = inttoptr i64 47 to ptr
  %t133 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t132, ptr %t133
  call void @__inc_ref(ptr %t122)
  %t131 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t122, ptr %t131
  br label %reuse.join.128
reuse.copy.127:
  %t134 = call ptr @__alloc(i64 24, i32 2)
  %t135 = inttoptr i64 47 to ptr
  %t136 = getelementptr ptr, ptr %t134, i32 0
  store ptr %t135, ptr %t136
  call void @__inc_ref(ptr %t122)
  %t137 = getelementptr ptr, ptr %t134, i32 1
  store ptr %t122, ptr %t137
  call void @__inc_ref(ptr %t15)
  %t138 = getelementptr ptr, ptr %t134, i32 2
  store ptr %t15, ptr %t138
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.128
reuse.join.128:
  %t139 = phi ptr [ %t5, %reuse.in_place.126 ], [ %t134, %reuse.copy.127 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t122)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t139, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.31.140:
  %t141 = getelementptr ptr, ptr %t13, i32 1
  %t142 = load ptr, ptr %t141
  call void @__inc_ref(ptr %t142)
  %t143 = getelementptr i8, ptr %t5, i64 -8
  %t144 = load i32, ptr %t143
  %t145 = icmp eq i32 %t144, 1
  br i1 %t145, label %reuse.in_place.146, label %reuse.copy.147
reuse.in_place.146:
  %t149 = getelementptr ptr, ptr %t5, i32 1
  %t150 = load ptr, ptr %t149
  call void @__free_recursive(ptr %t150)
  %t152 = inttoptr i64 48 to ptr
  %t153 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t152, ptr %t153
  call void @__inc_ref(ptr %t142)
  %t151 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t142, ptr %t151
  br label %reuse.join.148
reuse.copy.147:
  %t154 = call ptr @__alloc(i64 24, i32 2)
  %t155 = inttoptr i64 48 to ptr
  %t156 = getelementptr ptr, ptr %t154, i32 0
  store ptr %t155, ptr %t156
  call void @__inc_ref(ptr %t142)
  %t157 = getelementptr ptr, ptr %t154, i32 1
  store ptr %t142, ptr %t157
  call void @__inc_ref(ptr %t15)
  %t158 = getelementptr ptr, ptr %t154, i32 2
  store ptr %t15, ptr %t158
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.148
reuse.join.148:
  %t159 = phi ptr [ %t5, %reuse.in_place.146 ], [ %t154, %reuse.copy.147 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t142)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t159, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.32.160:
  %t161 = getelementptr ptr, ptr %t13, i32 1
  %t162 = load ptr, ptr %t161
  call void @__inc_ref(ptr %t162)
  %t163 = getelementptr i8, ptr %t5, i64 -8
  %t164 = load i32, ptr %t163
  %t165 = icmp eq i32 %t164, 1
  br i1 %t165, label %reuse.in_place.166, label %reuse.copy.167
reuse.in_place.166:
  %t169 = getelementptr ptr, ptr %t5, i32 1
  %t170 = load ptr, ptr %t169
  call void @__free_recursive(ptr %t170)
  %t172 = inttoptr i64 49 to ptr
  %t173 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t172, ptr %t173
  call void @__inc_ref(ptr %t162)
  %t171 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t162, ptr %t171
  br label %reuse.join.168
reuse.copy.167:
  %t174 = call ptr @__alloc(i64 24, i32 2)
  %t175 = inttoptr i64 49 to ptr
  %t176 = getelementptr ptr, ptr %t174, i32 0
  store ptr %t175, ptr %t176
  call void @__inc_ref(ptr %t162)
  %t177 = getelementptr ptr, ptr %t174, i32 1
  store ptr %t162, ptr %t177
  call void @__inc_ref(ptr %t15)
  %t178 = getelementptr ptr, ptr %t174, i32 2
  store ptr %t15, ptr %t178
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.168
reuse.join.168:
  %t179 = phi ptr [ %t5, %reuse.in_place.166 ], [ %t174, %reuse.copy.167 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t162)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t179, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.33.180:
  %t181 = getelementptr ptr, ptr %t13, i32 1
  %t182 = load ptr, ptr %t181
  call void @__inc_ref(ptr %t182)
  %t183 = getelementptr i8, ptr %t5, i64 -8
  %t184 = load i32, ptr %t183
  %t185 = icmp eq i32 %t184, 1
  br i1 %t185, label %reuse.in_place.186, label %reuse.copy.187
reuse.in_place.186:
  %t189 = getelementptr ptr, ptr %t5, i32 1
  %t190 = load ptr, ptr %t189
  call void @__free_recursive(ptr %t190)
  %t192 = inttoptr i64 50 to ptr
  %t193 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t192, ptr %t193
  call void @__inc_ref(ptr %t182)
  %t191 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t182, ptr %t191
  br label %reuse.join.188
reuse.copy.187:
  %t194 = call ptr @__alloc(i64 24, i32 2)
  %t195 = inttoptr i64 50 to ptr
  %t196 = getelementptr ptr, ptr %t194, i32 0
  store ptr %t195, ptr %t196
  call void @__inc_ref(ptr %t182)
  %t197 = getelementptr ptr, ptr %t194, i32 1
  store ptr %t182, ptr %t197
  call void @__inc_ref(ptr %t15)
  %t198 = getelementptr ptr, ptr %t194, i32 2
  store ptr %t15, ptr %t198
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.188
reuse.join.188:
  %t199 = phi ptr [ %t5, %reuse.in_place.186 ], [ %t194, %reuse.copy.187 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t182)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t199, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.34.200:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t15)
  %t201 = call ptr @v__io_getargs_cont(ptr %t15)
  %t202 = call ptr @v__apply__scc__apply1__df__lam_14_1__df__lam_15_2__df__lam_16_3__df__lam_24_5__df__lam_25_6__df__lam_26_7__df__lam_31_9__df__lam_32_10__df__lam_33_11__lift_21__lift_22__lift_23__lift_28__lift_29__lift_30(ptr %t6, ptr %t201)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t202, ptr %t2
  br label %tco.exit.1
tco.case.arm.35.203:
  %t204 = getelementptr ptr, ptr %t13, i32 1
  %t205 = load ptr, ptr %t204
  call void @__inc_ref(ptr %t205)
  %t206 = getelementptr i8, ptr %t5, i64 -8
  %t207 = load i32, ptr %t206
  %t208 = icmp eq i32 %t207, 1
  br i1 %t208, label %reuse.in_place.209, label %reuse.copy.210
reuse.in_place.209:
  %t212 = getelementptr ptr, ptr %t5, i32 1
  %t213 = load ptr, ptr %t212
  call void @__free_recursive(ptr %t213)
  %t215 = inttoptr i64 51 to ptr
  %t216 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t215, ptr %t216
  call void @__inc_ref(ptr %t205)
  %t214 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t205, ptr %t214
  br label %reuse.join.211
reuse.copy.210:
  %t217 = call ptr @__alloc(i64 24, i32 2)
  %t218 = inttoptr i64 51 to ptr
  %t219 = getelementptr ptr, ptr %t217, i32 0
  store ptr %t218, ptr %t219
  call void @__inc_ref(ptr %t205)
  %t220 = getelementptr ptr, ptr %t217, i32 1
  store ptr %t205, ptr %t220
  call void @__inc_ref(ptr %t15)
  %t221 = getelementptr ptr, ptr %t217, i32 2
  store ptr %t15, ptr %t221
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.211
reuse.join.211:
  %t222 = phi ptr [ %t5, %reuse.in_place.209 ], [ %t217, %reuse.copy.210 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t205)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t222, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.36.223:
  %t224 = getelementptr ptr, ptr %t13, i32 1
  %t225 = load ptr, ptr %t224
  call void @__inc_ref(ptr %t225)
  %t226 = getelementptr i8, ptr %t5, i64 -8
  %t227 = load i32, ptr %t226
  %t228 = icmp eq i32 %t227, 1
  br i1 %t228, label %reuse.in_place.229, label %reuse.copy.230
reuse.in_place.229:
  %t232 = getelementptr ptr, ptr %t5, i32 1
  %t233 = load ptr, ptr %t232
  call void @__free_recursive(ptr %t233)
  %t235 = inttoptr i64 52 to ptr
  %t236 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t235, ptr %t236
  call void @__inc_ref(ptr %t225)
  %t234 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t225, ptr %t234
  br label %reuse.join.231
reuse.copy.230:
  %t237 = call ptr @__alloc(i64 24, i32 2)
  %t238 = inttoptr i64 52 to ptr
  %t239 = getelementptr ptr, ptr %t237, i32 0
  store ptr %t238, ptr %t239
  call void @__inc_ref(ptr %t225)
  %t240 = getelementptr ptr, ptr %t237, i32 1
  store ptr %t225, ptr %t240
  call void @__inc_ref(ptr %t15)
  %t241 = getelementptr ptr, ptr %t237, i32 2
  store ptr %t15, ptr %t241
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.231
reuse.join.231:
  %t242 = phi ptr [ %t5, %reuse.in_place.229 ], [ %t237, %reuse.copy.230 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t225)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t242, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.37.243:
  %t244 = getelementptr ptr, ptr %t13, i32 1
  %t245 = load ptr, ptr %t244
  call void @__inc_ref(ptr %t245)
  %t246 = getelementptr i8, ptr %t5, i64 -8
  %t247 = load i32, ptr %t246
  %t248 = icmp eq i32 %t247, 1
  br i1 %t248, label %reuse.in_place.249, label %reuse.copy.250
reuse.in_place.249:
  %t252 = getelementptr ptr, ptr %t5, i32 1
  %t253 = load ptr, ptr %t252
  call void @__free_recursive(ptr %t253)
  %t255 = inttoptr i64 53 to ptr
  %t256 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t255, ptr %t256
  call void @__inc_ref(ptr %t245)
  %t254 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t245, ptr %t254
  br label %reuse.join.251
reuse.copy.250:
  %t257 = call ptr @__alloc(i64 24, i32 2)
  %t258 = inttoptr i64 53 to ptr
  %t259 = getelementptr ptr, ptr %t257, i32 0
  store ptr %t258, ptr %t259
  call void @__inc_ref(ptr %t245)
  %t260 = getelementptr ptr, ptr %t257, i32 1
  store ptr %t245, ptr %t260
  call void @__inc_ref(ptr %t15)
  %t261 = getelementptr ptr, ptr %t257, i32 2
  store ptr %t15, ptr %t261
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.251
reuse.join.251:
  %t262 = phi ptr [ %t5, %reuse.in_place.249 ], [ %t257, %reuse.copy.250 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t245)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t262, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.38.263:
  %t264 = getelementptr ptr, ptr %t13, i32 1
  %t265 = load ptr, ptr %t264
  call void @__inc_ref(ptr %t265)
  %t266 = getelementptr i8, ptr %t5, i64 -8
  %t267 = load i32, ptr %t266
  %t268 = icmp eq i32 %t267, 1
  br i1 %t268, label %reuse.in_place.269, label %reuse.copy.270
reuse.in_place.269:
  %t272 = getelementptr ptr, ptr %t5, i32 1
  %t273 = load ptr, ptr %t272
  call void @__free_recursive(ptr %t273)
  %t275 = inttoptr i64 54 to ptr
  %t276 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t275, ptr %t276
  call void @__inc_ref(ptr %t265)
  %t274 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t265, ptr %t274
  br label %reuse.join.271
reuse.copy.270:
  %t277 = call ptr @__alloc(i64 24, i32 2)
  %t278 = inttoptr i64 54 to ptr
  %t279 = getelementptr ptr, ptr %t277, i32 0
  store ptr %t278, ptr %t279
  call void @__inc_ref(ptr %t265)
  %t280 = getelementptr ptr, ptr %t277, i32 1
  store ptr %t265, ptr %t280
  call void @__inc_ref(ptr %t15)
  %t281 = getelementptr ptr, ptr %t277, i32 2
  store ptr %t15, ptr %t281
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.271
reuse.join.271:
  %t282 = phi ptr [ %t5, %reuse.in_place.269 ], [ %t277, %reuse.copy.270 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t265)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t282, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.39.283:
  %t284 = getelementptr ptr, ptr %t13, i32 1
  %t285 = load ptr, ptr %t284
  call void @__inc_ref(ptr %t285)
  %t286 = getelementptr i8, ptr %t5, i64 -8
  %t287 = load i32, ptr %t286
  %t288 = icmp eq i32 %t287, 1
  br i1 %t288, label %reuse.in_place.289, label %reuse.copy.290
reuse.in_place.289:
  %t292 = getelementptr ptr, ptr %t5, i32 1
  %t293 = load ptr, ptr %t292
  call void @__free_recursive(ptr %t293)
  %t295 = inttoptr i64 55 to ptr
  %t296 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t295, ptr %t296
  call void @__inc_ref(ptr %t285)
  %t294 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t285, ptr %t294
  br label %reuse.join.291
reuse.copy.290:
  %t297 = call ptr @__alloc(i64 24, i32 2)
  %t298 = inttoptr i64 55 to ptr
  %t299 = getelementptr ptr, ptr %t297, i32 0
  store ptr %t298, ptr %t299
  call void @__inc_ref(ptr %t285)
  %t300 = getelementptr ptr, ptr %t297, i32 1
  store ptr %t285, ptr %t300
  call void @__inc_ref(ptr %t15)
  %t301 = getelementptr ptr, ptr %t297, i32 2
  store ptr %t15, ptr %t301
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.291
reuse.join.291:
  %t302 = phi ptr [ %t5, %reuse.in_place.289 ], [ %t297, %reuse.copy.290 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t285)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t302, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.40.303:
  %t304 = getelementptr ptr, ptr %t13, i32 1
  %t305 = load ptr, ptr %t304
  call void @__inc_ref(ptr %t305)
  %t306 = getelementptr i8, ptr %t5, i64 -8
  %t307 = load i32, ptr %t306
  %t308 = icmp eq i32 %t307, 1
  br i1 %t308, label %reuse.in_place.309, label %reuse.copy.310
reuse.in_place.309:
  %t312 = getelementptr ptr, ptr %t5, i32 1
  %t313 = load ptr, ptr %t312
  call void @__free_recursive(ptr %t313)
  %t315 = inttoptr i64 56 to ptr
  %t316 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t315, ptr %t316
  call void @__inc_ref(ptr %t305)
  %t314 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t305, ptr %t314
  br label %reuse.join.311
reuse.copy.310:
  %t317 = call ptr @__alloc(i64 24, i32 2)
  %t318 = inttoptr i64 56 to ptr
  %t319 = getelementptr ptr, ptr %t317, i32 0
  store ptr %t318, ptr %t319
  call void @__inc_ref(ptr %t305)
  %t320 = getelementptr ptr, ptr %t317, i32 1
  store ptr %t305, ptr %t320
  call void @__inc_ref(ptr %t15)
  %t321 = getelementptr ptr, ptr %t317, i32 2
  store ptr %t15, ptr %t321
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.311
reuse.join.311:
  %t322 = phi ptr [ %t5, %reuse.in_place.309 ], [ %t317, %reuse.copy.310 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t305)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t322, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.default.19:
  unreachable
tco.case.arm.42.323:
  %t324 = getelementptr ptr, ptr %t5, i32 1
  %t325 = load ptr, ptr %t324
  %t326 = getelementptr ptr, ptr %t5, i32 2
  %t327 = load ptr, ptr %t326
  %t328 = getelementptr i8, ptr %t5, i64 -8
  %t329 = load i32, ptr %t328
  %t330 = icmp eq i32 %t329, 1
  br i1 %t330, label %reuse.in_place.331, label %reuse.copy.332
reuse.in_place.331:
  %t334 = inttoptr i64 41 to ptr
  %t335 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t334, ptr %t335
  br label %reuse.join.333
reuse.copy.332:
  %t336 = call ptr @__alloc(i64 24, i32 2)
  %t337 = inttoptr i64 41 to ptr
  %t338 = getelementptr ptr, ptr %t336, i32 0
  store ptr %t337, ptr %t338
  call void @__inc_ref(ptr %t325)
  %t339 = getelementptr ptr, ptr %t336, i32 1
  store ptr %t325, ptr %t339
  call void @__inc_ref(ptr %t327)
  %t340 = getelementptr ptr, ptr %t336, i32 2
  store ptr %t327, ptr %t340
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.333
reuse.join.333:
  %t341 = phi ptr [ %t5, %reuse.in_place.331 ], [ %t336, %reuse.copy.332 ]
  %t342 = call ptr @__alloc(i64 16, i32 1)
  %t343 = inttoptr i64 68 to ptr
  %t344 = getelementptr ptr, ptr %t342, i32 0
  store ptr %t343, ptr %t344
  call void @__inc_ref(ptr %t6)
  %t345 = getelementptr ptr, ptr %t342, i32 1
  store ptr %t6, ptr %t345
  call void @__free_recursive(ptr %t6)
  store ptr %t341, ptr %t3
  store ptr %t342, ptr %t4
  br label %tco.loop.0
tco.case.arm.43.346:
  %t347 = getelementptr ptr, ptr %t5, i32 1
  %t348 = load ptr, ptr %t347
  %t349 = getelementptr ptr, ptr %t5, i32 2
  %t350 = load ptr, ptr %t349
  %t351 = getelementptr i8, ptr %t5, i64 -8
  %t352 = load i32, ptr %t351
  %t353 = icmp eq i32 %t352, 1
  br i1 %t353, label %reuse.in_place.354, label %reuse.copy.355
reuse.in_place.354:
  %t357 = inttoptr i64 41 to ptr
  %t358 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t357, ptr %t358
  br label %reuse.join.356
reuse.copy.355:
  %t359 = call ptr @__alloc(i64 24, i32 2)
  %t360 = inttoptr i64 41 to ptr
  %t361 = getelementptr ptr, ptr %t359, i32 0
  store ptr %t360, ptr %t361
  call void @__inc_ref(ptr %t348)
  %t362 = getelementptr ptr, ptr %t359, i32 1
  store ptr %t348, ptr %t362
  call void @__inc_ref(ptr %t350)
  %t363 = getelementptr ptr, ptr %t359, i32 2
  store ptr %t350, ptr %t363
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.356
reuse.join.356:
  %t364 = phi ptr [ %t5, %reuse.in_place.354 ], [ %t359, %reuse.copy.355 ]
  %t365 = call ptr @__alloc(i64 16, i32 1)
  %t366 = inttoptr i64 69 to ptr
  %t367 = getelementptr ptr, ptr %t365, i32 0
  store ptr %t366, ptr %t367
  call void @__inc_ref(ptr %t6)
  %t368 = getelementptr ptr, ptr %t365, i32 1
  store ptr %t6, ptr %t368
  call void @__free_recursive(ptr %t6)
  store ptr %t364, ptr %t3
  store ptr %t365, ptr %t4
  br label %tco.loop.0
tco.case.arm.44.369:
  %t370 = getelementptr ptr, ptr %t5, i32 1
  %t371 = load ptr, ptr %t370
  %t372 = getelementptr ptr, ptr %t5, i32 2
  %t373 = load ptr, ptr %t372
  %t374 = getelementptr i8, ptr %t5, i64 -8
  %t375 = load i32, ptr %t374
  %t376 = icmp eq i32 %t375, 1
  br i1 %t376, label %reuse.in_place.377, label %reuse.copy.378
reuse.in_place.377:
  %t380 = inttoptr i64 41 to ptr
  %t381 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t380, ptr %t381
  br label %reuse.join.379
reuse.copy.378:
  %t382 = call ptr @__alloc(i64 24, i32 2)
  %t383 = inttoptr i64 41 to ptr
  %t384 = getelementptr ptr, ptr %t382, i32 0
  store ptr %t383, ptr %t384
  call void @__inc_ref(ptr %t371)
  %t385 = getelementptr ptr, ptr %t382, i32 1
  store ptr %t371, ptr %t385
  call void @__inc_ref(ptr %t373)
  %t386 = getelementptr ptr, ptr %t382, i32 2
  store ptr %t373, ptr %t386
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.379
reuse.join.379:
  %t387 = phi ptr [ %t5, %reuse.in_place.377 ], [ %t382, %reuse.copy.378 ]
  %t388 = call ptr @__alloc(i64 16, i32 1)
  %t389 = inttoptr i64 70 to ptr
  %t390 = getelementptr ptr, ptr %t388, i32 0
  store ptr %t389, ptr %t390
  call void @__inc_ref(ptr %t6)
  %t391 = getelementptr ptr, ptr %t388, i32 1
  store ptr %t6, ptr %t391
  call void @__free_recursive(ptr %t6)
  store ptr %t387, ptr %t3
  store ptr %t388, ptr %t4
  br label %tco.loop.0
tco.case.arm.45.392:
  %t393 = getelementptr ptr, ptr %t5, i32 1
  %t394 = load ptr, ptr %t393
  %t395 = getelementptr ptr, ptr %t5, i32 2
  %t396 = load ptr, ptr %t395
  %t397 = getelementptr i8, ptr %t5, i64 -8
  %t398 = load i32, ptr %t397
  %t399 = icmp eq i32 %t398, 1
  br i1 %t399, label %reuse.in_place.400, label %reuse.copy.401
reuse.in_place.400:
  %t403 = inttoptr i64 41 to ptr
  %t404 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t403, ptr %t404
  br label %reuse.join.402
reuse.copy.401:
  %t405 = call ptr @__alloc(i64 24, i32 2)
  %t406 = inttoptr i64 41 to ptr
  %t407 = getelementptr ptr, ptr %t405, i32 0
  store ptr %t406, ptr %t407
  call void @__inc_ref(ptr %t394)
  %t408 = getelementptr ptr, ptr %t405, i32 1
  store ptr %t394, ptr %t408
  call void @__inc_ref(ptr %t396)
  %t409 = getelementptr ptr, ptr %t405, i32 2
  store ptr %t396, ptr %t409
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.402
reuse.join.402:
  %t410 = phi ptr [ %t5, %reuse.in_place.400 ], [ %t405, %reuse.copy.401 ]
  %t411 = call ptr @__alloc(i64 16, i32 1)
  %t412 = inttoptr i64 71 to ptr
  %t413 = getelementptr ptr, ptr %t411, i32 0
  store ptr %t412, ptr %t413
  call void @__inc_ref(ptr %t6)
  %t414 = getelementptr ptr, ptr %t411, i32 1
  store ptr %t6, ptr %t414
  call void @__free_recursive(ptr %t6)
  store ptr %t410, ptr %t3
  store ptr %t411, ptr %t4
  br label %tco.loop.0
tco.case.arm.46.415:
  %t416 = getelementptr ptr, ptr %t5, i32 1
  %t417 = load ptr, ptr %t416
  %t418 = getelementptr ptr, ptr %t5, i32 2
  %t419 = load ptr, ptr %t418
  %t420 = getelementptr i8, ptr %t5, i64 -8
  %t421 = load i32, ptr %t420
  %t422 = icmp eq i32 %t421, 1
  br i1 %t422, label %reuse.in_place.423, label %reuse.copy.424
reuse.in_place.423:
  %t426 = inttoptr i64 41 to ptr
  %t427 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t426, ptr %t427
  br label %reuse.join.425
reuse.copy.424:
  %t428 = call ptr @__alloc(i64 24, i32 2)
  %t429 = inttoptr i64 41 to ptr
  %t430 = getelementptr ptr, ptr %t428, i32 0
  store ptr %t429, ptr %t430
  call void @__inc_ref(ptr %t417)
  %t431 = getelementptr ptr, ptr %t428, i32 1
  store ptr %t417, ptr %t431
  call void @__inc_ref(ptr %t419)
  %t432 = getelementptr ptr, ptr %t428, i32 2
  store ptr %t419, ptr %t432
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.425
reuse.join.425:
  %t433 = phi ptr [ %t5, %reuse.in_place.423 ], [ %t428, %reuse.copy.424 ]
  %t434 = call ptr @__alloc(i64 16, i32 1)
  %t435 = inttoptr i64 72 to ptr
  %t436 = getelementptr ptr, ptr %t434, i32 0
  store ptr %t435, ptr %t436
  call void @__inc_ref(ptr %t6)
  %t437 = getelementptr ptr, ptr %t434, i32 1
  store ptr %t6, ptr %t437
  call void @__free_recursive(ptr %t6)
  store ptr %t433, ptr %t3
  store ptr %t434, ptr %t4
  br label %tco.loop.0
tco.case.arm.47.438:
  %t439 = getelementptr ptr, ptr %t5, i32 1
  %t440 = load ptr, ptr %t439
  %t441 = getelementptr ptr, ptr %t5, i32 2
  %t442 = load ptr, ptr %t441
  %t443 = getelementptr i8, ptr %t5, i64 -8
  %t444 = load i32, ptr %t443
  %t445 = icmp eq i32 %t444, 1
  br i1 %t445, label %reuse.in_place.446, label %reuse.copy.447
reuse.in_place.446:
  %t449 = inttoptr i64 41 to ptr
  %t450 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t449, ptr %t450
  br label %reuse.join.448
reuse.copy.447:
  %t451 = call ptr @__alloc(i64 24, i32 2)
  %t452 = inttoptr i64 41 to ptr
  %t453 = getelementptr ptr, ptr %t451, i32 0
  store ptr %t452, ptr %t453
  call void @__inc_ref(ptr %t440)
  %t454 = getelementptr ptr, ptr %t451, i32 1
  store ptr %t440, ptr %t454
  call void @__inc_ref(ptr %t442)
  %t455 = getelementptr ptr, ptr %t451, i32 2
  store ptr %t442, ptr %t455
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.448
reuse.join.448:
  %t456 = phi ptr [ %t5, %reuse.in_place.446 ], [ %t451, %reuse.copy.447 ]
  %t457 = call ptr @__alloc(i64 16, i32 1)
  %t458 = inttoptr i64 73 to ptr
  %t459 = getelementptr ptr, ptr %t457, i32 0
  store ptr %t458, ptr %t459
  call void @__inc_ref(ptr %t6)
  %t460 = getelementptr ptr, ptr %t457, i32 1
  store ptr %t6, ptr %t460
  call void @__free_recursive(ptr %t6)
  store ptr %t456, ptr %t3
  store ptr %t457, ptr %t4
  br label %tco.loop.0
tco.case.arm.48.461:
  %t462 = getelementptr ptr, ptr %t5, i32 1
  %t463 = load ptr, ptr %t462
  %t464 = getelementptr ptr, ptr %t5, i32 2
  %t465 = load ptr, ptr %t464
  %t466 = getelementptr i8, ptr %t5, i64 -8
  %t467 = load i32, ptr %t466
  %t468 = icmp eq i32 %t467, 1
  br i1 %t468, label %reuse.in_place.469, label %reuse.copy.470
reuse.in_place.469:
  %t472 = inttoptr i64 41 to ptr
  %t473 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t472, ptr %t473
  br label %reuse.join.471
reuse.copy.470:
  %t474 = call ptr @__alloc(i64 24, i32 2)
  %t475 = inttoptr i64 41 to ptr
  %t476 = getelementptr ptr, ptr %t474, i32 0
  store ptr %t475, ptr %t476
  call void @__inc_ref(ptr %t463)
  %t477 = getelementptr ptr, ptr %t474, i32 1
  store ptr %t463, ptr %t477
  call void @__inc_ref(ptr %t465)
  %t478 = getelementptr ptr, ptr %t474, i32 2
  store ptr %t465, ptr %t478
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.471
reuse.join.471:
  %t479 = phi ptr [ %t5, %reuse.in_place.469 ], [ %t474, %reuse.copy.470 ]
  %t480 = call ptr @__alloc(i64 16, i32 1)
  %t481 = inttoptr i64 74 to ptr
  %t482 = getelementptr ptr, ptr %t480, i32 0
  store ptr %t481, ptr %t482
  call void @__inc_ref(ptr %t6)
  %t483 = getelementptr ptr, ptr %t480, i32 1
  store ptr %t6, ptr %t483
  call void @__free_recursive(ptr %t6)
  store ptr %t479, ptr %t3
  store ptr %t480, ptr %t4
  br label %tco.loop.0
tco.case.arm.49.484:
  %t485 = getelementptr ptr, ptr %t5, i32 1
  %t486 = load ptr, ptr %t485
  %t487 = getelementptr ptr, ptr %t5, i32 2
  %t488 = load ptr, ptr %t487
  %t489 = getelementptr i8, ptr %t5, i64 -8
  %t490 = load i32, ptr %t489
  %t491 = icmp eq i32 %t490, 1
  br i1 %t491, label %reuse.in_place.492, label %reuse.copy.493
reuse.in_place.492:
  %t495 = inttoptr i64 41 to ptr
  %t496 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t495, ptr %t496
  br label %reuse.join.494
reuse.copy.493:
  %t497 = call ptr @__alloc(i64 24, i32 2)
  %t498 = inttoptr i64 41 to ptr
  %t499 = getelementptr ptr, ptr %t497, i32 0
  store ptr %t498, ptr %t499
  call void @__inc_ref(ptr %t486)
  %t500 = getelementptr ptr, ptr %t497, i32 1
  store ptr %t486, ptr %t500
  call void @__inc_ref(ptr %t488)
  %t501 = getelementptr ptr, ptr %t497, i32 2
  store ptr %t488, ptr %t501
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.494
reuse.join.494:
  %t502 = phi ptr [ %t5, %reuse.in_place.492 ], [ %t497, %reuse.copy.493 ]
  %t503 = call ptr @__alloc(i64 16, i32 1)
  %t504 = inttoptr i64 75 to ptr
  %t505 = getelementptr ptr, ptr %t503, i32 0
  store ptr %t504, ptr %t505
  call void @__inc_ref(ptr %t6)
  %t506 = getelementptr ptr, ptr %t503, i32 1
  store ptr %t6, ptr %t506
  call void @__free_recursive(ptr %t6)
  store ptr %t502, ptr %t3
  store ptr %t503, ptr %t4
  br label %tco.loop.0
tco.case.arm.50.507:
  %t508 = getelementptr ptr, ptr %t5, i32 1
  %t509 = load ptr, ptr %t508
  %t510 = getelementptr ptr, ptr %t5, i32 2
  %t511 = load ptr, ptr %t510
  %t512 = getelementptr i8, ptr %t5, i64 -8
  %t513 = load i32, ptr %t512
  %t514 = icmp eq i32 %t513, 1
  br i1 %t514, label %reuse.in_place.515, label %reuse.copy.516
reuse.in_place.515:
  %t518 = inttoptr i64 41 to ptr
  %t519 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t518, ptr %t519
  br label %reuse.join.517
reuse.copy.516:
  %t520 = call ptr @__alloc(i64 24, i32 2)
  %t521 = inttoptr i64 41 to ptr
  %t522 = getelementptr ptr, ptr %t520, i32 0
  store ptr %t521, ptr %t522
  call void @__inc_ref(ptr %t509)
  %t523 = getelementptr ptr, ptr %t520, i32 1
  store ptr %t509, ptr %t523
  call void @__inc_ref(ptr %t511)
  %t524 = getelementptr ptr, ptr %t520, i32 2
  store ptr %t511, ptr %t524
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.517
reuse.join.517:
  %t525 = phi ptr [ %t5, %reuse.in_place.515 ], [ %t520, %reuse.copy.516 ]
  %t526 = call ptr @__alloc(i64 16, i32 1)
  %t527 = inttoptr i64 76 to ptr
  %t528 = getelementptr ptr, ptr %t526, i32 0
  store ptr %t527, ptr %t528
  call void @__inc_ref(ptr %t6)
  %t529 = getelementptr ptr, ptr %t526, i32 1
  store ptr %t6, ptr %t529
  call void @__free_recursive(ptr %t6)
  store ptr %t525, ptr %t3
  store ptr %t526, ptr %t4
  br label %tco.loop.0
tco.case.arm.51.530:
  %t531 = getelementptr ptr, ptr %t5, i32 1
  %t532 = load ptr, ptr %t531
  %t533 = getelementptr ptr, ptr %t5, i32 2
  %t534 = load ptr, ptr %t533
  %t535 = getelementptr i8, ptr %t5, i64 -8
  %t536 = load i32, ptr %t535
  %t537 = icmp eq i32 %t536, 1
  br i1 %t537, label %reuse.in_place.538, label %reuse.copy.539
reuse.in_place.538:
  %t541 = inttoptr i64 41 to ptr
  %t542 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t541, ptr %t542
  br label %reuse.join.540
reuse.copy.539:
  %t543 = call ptr @__alloc(i64 24, i32 2)
  %t544 = inttoptr i64 41 to ptr
  %t545 = getelementptr ptr, ptr %t543, i32 0
  store ptr %t544, ptr %t545
  call void @__inc_ref(ptr %t532)
  %t546 = getelementptr ptr, ptr %t543, i32 1
  store ptr %t532, ptr %t546
  call void @__inc_ref(ptr %t534)
  %t547 = getelementptr ptr, ptr %t543, i32 2
  store ptr %t534, ptr %t547
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.540
reuse.join.540:
  %t548 = phi ptr [ %t5, %reuse.in_place.538 ], [ %t543, %reuse.copy.539 ]
  %t549 = call ptr @__alloc(i64 16, i32 1)
  %t550 = inttoptr i64 77 to ptr
  %t551 = getelementptr ptr, ptr %t549, i32 0
  store ptr %t550, ptr %t551
  call void @__inc_ref(ptr %t6)
  %t552 = getelementptr ptr, ptr %t549, i32 1
  store ptr %t6, ptr %t552
  call void @__free_recursive(ptr %t6)
  store ptr %t548, ptr %t3
  store ptr %t549, ptr %t4
  br label %tco.loop.0
tco.case.arm.52.553:
  %t554 = getelementptr ptr, ptr %t5, i32 1
  %t555 = load ptr, ptr %t554
  %t556 = getelementptr ptr, ptr %t5, i32 2
  %t557 = load ptr, ptr %t556
  %t558 = getelementptr i8, ptr %t5, i64 -8
  %t559 = load i32, ptr %t558
  %t560 = icmp eq i32 %t559, 1
  br i1 %t560, label %reuse.in_place.561, label %reuse.copy.562
reuse.in_place.561:
  %t564 = inttoptr i64 41 to ptr
  %t565 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t564, ptr %t565
  br label %reuse.join.563
reuse.copy.562:
  %t566 = call ptr @__alloc(i64 24, i32 2)
  %t567 = inttoptr i64 41 to ptr
  %t568 = getelementptr ptr, ptr %t566, i32 0
  store ptr %t567, ptr %t568
  call void @__inc_ref(ptr %t555)
  %t569 = getelementptr ptr, ptr %t566, i32 1
  store ptr %t555, ptr %t569
  call void @__inc_ref(ptr %t557)
  %t570 = getelementptr ptr, ptr %t566, i32 2
  store ptr %t557, ptr %t570
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.563
reuse.join.563:
  %t571 = phi ptr [ %t5, %reuse.in_place.561 ], [ %t566, %reuse.copy.562 ]
  %t572 = call ptr @__alloc(i64 16, i32 1)
  %t573 = inttoptr i64 78 to ptr
  %t574 = getelementptr ptr, ptr %t572, i32 0
  store ptr %t573, ptr %t574
  call void @__inc_ref(ptr %t6)
  %t575 = getelementptr ptr, ptr %t572, i32 1
  store ptr %t6, ptr %t575
  call void @__free_recursive(ptr %t6)
  store ptr %t571, ptr %t3
  store ptr %t572, ptr %t4
  br label %tco.loop.0
tco.case.arm.53.576:
  %t577 = getelementptr ptr, ptr %t5, i32 1
  %t578 = load ptr, ptr %t577
  %t579 = getelementptr ptr, ptr %t5, i32 2
  %t580 = load ptr, ptr %t579
  %t581 = getelementptr i8, ptr %t5, i64 -8
  %t582 = load i32, ptr %t581
  %t583 = icmp eq i32 %t582, 1
  br i1 %t583, label %reuse.in_place.584, label %reuse.copy.585
reuse.in_place.584:
  %t587 = inttoptr i64 41 to ptr
  %t588 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t587, ptr %t588
  br label %reuse.join.586
reuse.copy.585:
  %t589 = call ptr @__alloc(i64 24, i32 2)
  %t590 = inttoptr i64 41 to ptr
  %t591 = getelementptr ptr, ptr %t589, i32 0
  store ptr %t590, ptr %t591
  call void @__inc_ref(ptr %t578)
  %t592 = getelementptr ptr, ptr %t589, i32 1
  store ptr %t578, ptr %t592
  call void @__inc_ref(ptr %t580)
  %t593 = getelementptr ptr, ptr %t589, i32 2
  store ptr %t580, ptr %t593
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.586
reuse.join.586:
  %t594 = phi ptr [ %t5, %reuse.in_place.584 ], [ %t589, %reuse.copy.585 ]
  %t595 = call ptr @__alloc(i64 16, i32 1)
  %t596 = inttoptr i64 79 to ptr
  %t597 = getelementptr ptr, ptr %t595, i32 0
  store ptr %t596, ptr %t597
  call void @__inc_ref(ptr %t6)
  %t598 = getelementptr ptr, ptr %t595, i32 1
  store ptr %t6, ptr %t598
  call void @__free_recursive(ptr %t6)
  store ptr %t594, ptr %t3
  store ptr %t595, ptr %t4
  br label %tco.loop.0
tco.case.arm.54.599:
  %t600 = getelementptr ptr, ptr %t5, i32 1
  %t601 = load ptr, ptr %t600
  %t602 = getelementptr ptr, ptr %t5, i32 2
  %t603 = load ptr, ptr %t602
  %t604 = getelementptr i8, ptr %t5, i64 -8
  %t605 = load i32, ptr %t604
  %t606 = icmp eq i32 %t605, 1
  br i1 %t606, label %reuse.in_place.607, label %reuse.copy.608
reuse.in_place.607:
  %t610 = inttoptr i64 41 to ptr
  %t611 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t610, ptr %t611
  br label %reuse.join.609
reuse.copy.608:
  %t612 = call ptr @__alloc(i64 24, i32 2)
  %t613 = inttoptr i64 41 to ptr
  %t614 = getelementptr ptr, ptr %t612, i32 0
  store ptr %t613, ptr %t614
  call void @__inc_ref(ptr %t601)
  %t615 = getelementptr ptr, ptr %t612, i32 1
  store ptr %t601, ptr %t615
  call void @__inc_ref(ptr %t603)
  %t616 = getelementptr ptr, ptr %t612, i32 2
  store ptr %t603, ptr %t616
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.609
reuse.join.609:
  %t617 = phi ptr [ %t5, %reuse.in_place.607 ], [ %t612, %reuse.copy.608 ]
  %t618 = call ptr @__alloc(i64 16, i32 1)
  %t619 = inttoptr i64 80 to ptr
  %t620 = getelementptr ptr, ptr %t618, i32 0
  store ptr %t619, ptr %t620
  call void @__inc_ref(ptr %t6)
  %t621 = getelementptr ptr, ptr %t618, i32 1
  store ptr %t6, ptr %t621
  call void @__free_recursive(ptr %t6)
  store ptr %t617, ptr %t3
  store ptr %t618, ptr %t4
  br label %tco.loop.0
tco.case.arm.55.622:
  %t623 = getelementptr ptr, ptr %t5, i32 1
  %t624 = load ptr, ptr %t623
  %t625 = getelementptr ptr, ptr %t5, i32 2
  %t626 = load ptr, ptr %t625
  %t627 = getelementptr i8, ptr %t5, i64 -8
  %t628 = load i32, ptr %t627
  %t629 = icmp eq i32 %t628, 1
  br i1 %t629, label %reuse.in_place.630, label %reuse.copy.631
reuse.in_place.630:
  %t633 = inttoptr i64 41 to ptr
  %t634 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t633, ptr %t634
  br label %reuse.join.632
reuse.copy.631:
  %t635 = call ptr @__alloc(i64 24, i32 2)
  %t636 = inttoptr i64 41 to ptr
  %t637 = getelementptr ptr, ptr %t635, i32 0
  store ptr %t636, ptr %t637
  call void @__inc_ref(ptr %t624)
  %t638 = getelementptr ptr, ptr %t635, i32 1
  store ptr %t624, ptr %t638
  call void @__inc_ref(ptr %t626)
  %t639 = getelementptr ptr, ptr %t635, i32 2
  store ptr %t626, ptr %t639
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.632
reuse.join.632:
  %t640 = phi ptr [ %t5, %reuse.in_place.630 ], [ %t635, %reuse.copy.631 ]
  %t641 = call ptr @__alloc(i64 16, i32 1)
  %t642 = inttoptr i64 81 to ptr
  %t643 = getelementptr ptr, ptr %t641, i32 0
  store ptr %t642, ptr %t643
  call void @__inc_ref(ptr %t6)
  %t644 = getelementptr ptr, ptr %t641, i32 1
  store ptr %t6, ptr %t644
  call void @__free_recursive(ptr %t6)
  store ptr %t640, ptr %t3
  store ptr %t641, ptr %t4
  br label %tco.loop.0
tco.case.arm.56.645:
  %t646 = getelementptr ptr, ptr %t5, i32 1
  %t647 = load ptr, ptr %t646
  %t648 = getelementptr ptr, ptr %t5, i32 2
  %t649 = load ptr, ptr %t648
  %t650 = getelementptr i8, ptr %t5, i64 -8
  %t651 = load i32, ptr %t650
  %t652 = icmp eq i32 %t651, 1
  br i1 %t652, label %reuse.in_place.653, label %reuse.copy.654
reuse.in_place.653:
  %t656 = inttoptr i64 41 to ptr
  %t657 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t656, ptr %t657
  br label %reuse.join.655
reuse.copy.654:
  %t658 = call ptr @__alloc(i64 24, i32 2)
  %t659 = inttoptr i64 41 to ptr
  %t660 = getelementptr ptr, ptr %t658, i32 0
  store ptr %t659, ptr %t660
  call void @__inc_ref(ptr %t647)
  %t661 = getelementptr ptr, ptr %t658, i32 1
  store ptr %t647, ptr %t661
  call void @__inc_ref(ptr %t649)
  %t662 = getelementptr ptr, ptr %t658, i32 2
  store ptr %t649, ptr %t662
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.655
reuse.join.655:
  %t663 = phi ptr [ %t5, %reuse.in_place.653 ], [ %t658, %reuse.copy.654 ]
  %t664 = call ptr @__alloc(i64 16, i32 1)
  %t665 = inttoptr i64 82 to ptr
  %t666 = getelementptr ptr, ptr %t664, i32 0
  store ptr %t665, ptr %t666
  call void @__inc_ref(ptr %t6)
  %t667 = getelementptr ptr, ptr %t664, i32 1
  store ptr %t6, ptr %t667
  call void @__free_recursive(ptr %t6)
  store ptr %t663, ptr %t3
  store ptr %t664, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t668 = load ptr, ptr %t2
  ret ptr %t668
}

define internal ptr @v__apply__scc__apply1__df__lam_14_1__df__lam_15_2__df__lam_16_3__df__lam_24_5__df__lam_25_6__df__lam_26_7__df__lam_31_9__df__lam_32_10__df__lam_33_11__lift_21__lift_22__lift_23__lift_28__lift_29__lift_30(ptr %v__k, ptr %v__x) {
entry:
  %t3 = alloca ptr
  store ptr %v__k, ptr %t3
  %t4 = alloca ptr
  store ptr %v__x, ptr %t4
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t5 = load ptr, ptr %t3
  %t6 = load ptr, ptr %t4
  %t7 = getelementptr ptr, ptr %t5, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %tco.case.default.10 [ i64 67, label %tco.case.arm.67.11 i64 68, label %tco.case.arm.68.12 i64 69, label %tco.case.arm.69.16 i64 70, label %tco.case.arm.70.20 i64 71, label %tco.case.arm.71.24 i64 72, label %tco.case.arm.72.28 i64 73, label %tco.case.arm.73.32 i64 74, label %tco.case.arm.74.36 i64 75, label %tco.case.arm.75.40 i64 76, label %tco.case.arm.76.44 i64 77, label %tco.case.arm.77.48 i64 78, label %tco.case.arm.78.52 i64 79, label %tco.case.arm.79.56 i64 80, label %tco.case.arm.80.60 i64 81, label %tco.case.arm.81.64 i64 82, label %tco.case.arm.82.68 ]
tco.case.arm.67.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.68.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  call void @__inc_ref(ptr %t6)
  %t15 = call ptr @v__df_handleErrorIO_0(ptr %t6)
  call void @__inc_ref(ptr %t14)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t14)
  store ptr %t14, ptr %t3
  store ptr %t15, ptr %t4
  br label %tco.loop.0
tco.case.arm.69.16:
  %t17 = getelementptr ptr, ptr %t5, i32 1
  %t18 = load ptr, ptr %t17
  call void @__inc_ref(ptr %t18)
  call void @__inc_ref(ptr %t6)
  %t19 = call ptr @v__df_handleErrorIO_0(ptr %t6)
  call void @__inc_ref(ptr %t18)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t18)
  store ptr %t18, ptr %t3
  store ptr %t19, ptr %t4
  br label %tco.loop.0
tco.case.arm.70.20:
  %t21 = getelementptr ptr, ptr %t5, i32 1
  %t22 = load ptr, ptr %t21
  call void @__inc_ref(ptr %t22)
  call void @__inc_ref(ptr %t6)
  %t23 = call ptr @v__df_handleErrorIO_0(ptr %t6)
  call void @__inc_ref(ptr %t22)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t22)
  store ptr %t22, ptr %t3
  store ptr %t23, ptr %t4
  br label %tco.loop.0
tco.case.arm.71.24:
  %t25 = getelementptr ptr, ptr %t5, i32 1
  %t26 = load ptr, ptr %t25
  call void @__inc_ref(ptr %t26)
  call void @__inc_ref(ptr %t6)
  %t27 = call ptr @v__df__rowmono_0_andThenIO_4(ptr %t6)
  call void @__inc_ref(ptr %t26)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t26)
  store ptr %t26, ptr %t3
  store ptr %t27, ptr %t4
  br label %tco.loop.0
tco.case.arm.72.28:
  %t29 = getelementptr ptr, ptr %t5, i32 1
  %t30 = load ptr, ptr %t29
  call void @__inc_ref(ptr %t30)
  call void @__inc_ref(ptr %t6)
  %t31 = call ptr @v__df__rowmono_0_andThenIO_4(ptr %t6)
  call void @__inc_ref(ptr %t30)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t30)
  store ptr %t30, ptr %t3
  store ptr %t31, ptr %t4
  br label %tco.loop.0
tco.case.arm.73.32:
  %t33 = getelementptr ptr, ptr %t5, i32 1
  %t34 = load ptr, ptr %t33
  call void @__inc_ref(ptr %t34)
  call void @__inc_ref(ptr %t6)
  %t35 = call ptr @v__df__rowmono_0_andThenIO_4(ptr %t6)
  call void @__inc_ref(ptr %t34)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t34)
  store ptr %t34, ptr %t3
  store ptr %t35, ptr %t4
  br label %tco.loop.0
tco.case.arm.74.36:
  %t37 = getelementptr ptr, ptr %t5, i32 1
  %t38 = load ptr, ptr %t37
  call void @__inc_ref(ptr %t38)
  call void @__inc_ref(ptr %t6)
  %t39 = call ptr @v__df__rowmono_1_andThenIO_8(ptr %t6)
  call void @__inc_ref(ptr %t38)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t38)
  store ptr %t38, ptr %t3
  store ptr %t39, ptr %t4
  br label %tco.loop.0
tco.case.arm.75.40:
  %t41 = getelementptr ptr, ptr %t5, i32 1
  %t42 = load ptr, ptr %t41
  call void @__inc_ref(ptr %t42)
  call void @__inc_ref(ptr %t6)
  %t43 = call ptr @v__df__rowmono_1_andThenIO_8(ptr %t6)
  call void @__inc_ref(ptr %t42)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t42)
  store ptr %t42, ptr %t3
  store ptr %t43, ptr %t4
  br label %tco.loop.0
tco.case.arm.76.44:
  %t45 = getelementptr ptr, ptr %t5, i32 1
  %t46 = load ptr, ptr %t45
  call void @__inc_ref(ptr %t46)
  call void @__inc_ref(ptr %t6)
  %t47 = call ptr @v__df__rowmono_1_andThenIO_8(ptr %t6)
  call void @__inc_ref(ptr %t46)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t46)
  store ptr %t46, ptr %t3
  store ptr %t47, ptr %t4
  br label %tco.loop.0
tco.case.arm.77.48:
  %t49 = getelementptr ptr, ptr %t5, i32 1
  %t50 = load ptr, ptr %t49
  call void @__inc_ref(ptr %t50)
  call void @__inc_ref(ptr %t6)
  %t51 = call ptr @v__lift_20(ptr %t6)
  call void @__inc_ref(ptr %t50)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t50)
  store ptr %t50, ptr %t3
  store ptr %t51, ptr %t4
  br label %tco.loop.0
tco.case.arm.78.52:
  %t53 = getelementptr ptr, ptr %t5, i32 1
  %t54 = load ptr, ptr %t53
  call void @__inc_ref(ptr %t54)
  call void @__inc_ref(ptr %t6)
  %t55 = call ptr @v__lift_20(ptr %t6)
  call void @__inc_ref(ptr %t54)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t54)
  store ptr %t54, ptr %t3
  store ptr %t55, ptr %t4
  br label %tco.loop.0
tco.case.arm.79.56:
  %t57 = getelementptr ptr, ptr %t5, i32 1
  %t58 = load ptr, ptr %t57
  call void @__inc_ref(ptr %t58)
  call void @__inc_ref(ptr %t6)
  %t59 = call ptr @v__lift_20(ptr %t6)
  call void @__inc_ref(ptr %t58)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t58)
  store ptr %t58, ptr %t3
  store ptr %t59, ptr %t4
  br label %tco.loop.0
tco.case.arm.80.60:
  %t61 = getelementptr ptr, ptr %t5, i32 1
  %t62 = load ptr, ptr %t61
  call void @__inc_ref(ptr %t62)
  call void @__inc_ref(ptr %t6)
  %t63 = call ptr @v__lift_27(ptr %t6)
  call void @__inc_ref(ptr %t62)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t62)
  store ptr %t62, ptr %t3
  store ptr %t63, ptr %t4
  br label %tco.loop.0
tco.case.arm.81.64:
  %t65 = getelementptr ptr, ptr %t5, i32 1
  %t66 = load ptr, ptr %t65
  call void @__inc_ref(ptr %t66)
  call void @__inc_ref(ptr %t6)
  %t67 = call ptr @v__lift_27(ptr %t6)
  call void @__inc_ref(ptr %t66)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t66)
  store ptr %t66, ptr %t3
  store ptr %t67, ptr %t4
  br label %tco.loop.0
tco.case.arm.82.68:
  %t69 = getelementptr ptr, ptr %t5, i32 1
  %t70 = load ptr, ptr %t69
  call void @__inc_ref(ptr %t70)
  call void @__inc_ref(ptr %t6)
  %t71 = call ptr @v__lift_27(ptr %t6)
  call void @__inc_ref(ptr %t70)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t70)
  store ptr %t70, ptr %t3
  store ptr %t71, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t72 = load ptr, ptr %t2
  ret ptr %t72
}

define internal ptr @v__apply1(ptr %v__cl, ptr %v__arg0) {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 41 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  call void @__inc_ref(ptr %v__cl)
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v__cl, ptr %t3
  call void @__inc_ref(ptr %v__arg0)
  %t4 = getelementptr ptr, ptr %t0, i32 2
  store ptr %v__arg0, ptr %t4
  %t5 = call ptr @v__scc__apply1__df__lam_14_1__df__lam_15_2__df__lam_16_3__df__lam_24_5__df__lam_25_6__df__lam_26_7__df__lam_31_9__df__lam_32_10__df__lam_33_11__lift_21__lift_22__lift_23__lift_28__lift_29__lift_30(ptr %t0)
  call void @__free_recursive(ptr %v__cl)
  call void @__free_recursive(ptr %v__arg0)
  ret ptr %t5
}

define i32 @main(i32 %argc, ptr %argv) {
  %argc64 = sext i32 %argc to i64
  store i64 %argc64, ptr @.cli_argc
  store ptr %argv, ptr @.cli_argv
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
