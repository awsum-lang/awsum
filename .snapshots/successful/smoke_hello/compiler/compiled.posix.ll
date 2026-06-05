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
  %t12 = call ptr @v__lift_17(ptr %t11)
  call void @__free_recursive(ptr %t10)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t12
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
  %t4 = inttoptr i64 37 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  %t7 = call ptr @v__df__rowspec_35_8(ptr %t0)
  %t8 = call ptr @v__lift_28(ptr %t7)
  %t9 = call ptr @v__df__rowspec_23_4(ptr %t8)
  %t10 = call ptr @v__df_handleErrorIO_0(ptr %t9)
  ret ptr %t10
}

define internal ptr @v_greet(ptr %v_args) {
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 24 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  call void @__inc_ref(ptr %v_args)
  %t3 = call ptr @v_headList(ptr %v_args)
  %t4 = call ptr @v__lift_45(ptr %t3)
  %t5 = call ptr @v_nothingAsLeft(ptr %t0, ptr %t4)
  %t6 = getelementptr ptr, ptr %t5, i32 0
  %t7 = load ptr, ptr %t6
  %t8 = ptrtoint ptr %t7 to i64
  switch i64 %t8, label %case.default.9 [ i64 3, label %case.arm.3.10 i64 4, label %case.arm.4.21 ]
case.arm.3.10:
  %t11 = getelementptr ptr, ptr %t5, i32 1
  %t12 = load ptr, ptr %t11
  call void @__inc_ref(ptr %t12)
  %t13 = call ptr @__alloc(i64 16, i32 1)
  %t14 = inttoptr i64 3 to ptr
  %t15 = getelementptr ptr, ptr %t13, i32 0
  store ptr %t14, ptr %t15
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 3864168810 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  call void @__inc_ref(ptr %t12)
  %t19 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t12, ptr %t19
  %t20 = getelementptr ptr, ptr %t13, i32 1
  store ptr %t16, ptr %t20
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t12)
  call void @__free_recursive(ptr %v_args)
  ret ptr %t13
case.arm.4.21:
  %t22 = getelementptr ptr, ptr %t5, i32 1
  %t23 = load ptr, ptr %t22
  call void @__inc_ref(ptr %t23)
  call void @__inc_ref(ptr %t23)
  %t24 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t23)
  %t25 = getelementptr ptr, ptr %t24, i32 0
  %t26 = load ptr, ptr %t25
  %t27 = ptrtoint ptr %t26 to i64
  switch i64 %t27, label %case.default.28 [ i64 3, label %case.arm.3.29 i64 4, label %case.arm.4.40 ]
case.arm.3.29:
  %t30 = getelementptr ptr, ptr %t24, i32 1
  %t31 = load ptr, ptr %t30
  call void @__inc_ref(ptr %t31)
  %t32 = call ptr @__alloc(i64 16, i32 1)
  %t33 = inttoptr i64 3 to ptr
  %t34 = getelementptr ptr, ptr %t32, i32 0
  store ptr %t33, ptr %t34
  %t35 = call ptr @__alloc(i64 16, i32 1)
  %t36 = inttoptr i64 589989748 to ptr
  %t37 = getelementptr ptr, ptr %t35, i32 0
  store ptr %t36, ptr %t37
  call void @__inc_ref(ptr %t31)
  %t38 = getelementptr ptr, ptr %t35, i32 1
  store ptr %t31, ptr %t38
  %t39 = getelementptr ptr, ptr %t32, i32 1
  store ptr %t35, ptr %t39
  call void @__free_recursive(ptr %t24)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t31)
  call void @__free_recursive(ptr %t23)
  call void @__free_recursive(ptr %v_args)
  ret ptr %t32
case.arm.4.40:
  %t41 = getelementptr ptr, ptr %t24, i32 1
  %t42 = load ptr, ptr %t41
  call void @__inc_ref(ptr %t42)
  call void @__inc_ref(ptr %t42)
  %t43 = call ptr @__concat(ptr %t42, ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  call void @__free_recursive(ptr %t24)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t42)
  call void @__free_recursive(ptr %t23)
  call void @__free_recursive(ptr %v_args)
  ret ptr %t43
case.default.28:
  unreachable
case.default.9:
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

define internal ptr @v__lift_1(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 81 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__lift_1(ptr %v___input, ptr %t0)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t3
}

define internal ptr @v__cps__lift_1(ptr %v___input, ptr %v__k) {
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
  %t18 = call ptr @v__apply__lift_1(ptr %t6, ptr %t14)
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
  %t26 = call ptr @v__apply__lift_1(ptr %t6, ptr %t22)
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
  %t42 = inttoptr i64 82 to ptr
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
  %t45 = inttoptr i64 82 to ptr
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
  %t57 = inttoptr i64 40 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  call void @__inc_ref(ptr %t52)
  %t59 = getelementptr ptr, ptr %t56, i32 1
  store ptr %t52, ptr %t59
  %t60 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t56, ptr %t60
  %t61 = call ptr @v__apply__lift_1(ptr %t6, ptr %t53)
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
  %t69 = inttoptr i64 46 to ptr
  %t70 = getelementptr ptr, ptr %t68, i32 0
  store ptr %t69, ptr %t70
  call void @__inc_ref(ptr %t64)
  %t71 = getelementptr ptr, ptr %t68, i32 1
  store ptr %t64, ptr %t71
  %t72 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t68, ptr %t72
  %t73 = call ptr @v__apply__lift_1(ptr %t6, ptr %t65)
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
  %t81 = inttoptr i64 52 to ptr
  %t82 = getelementptr ptr, ptr %t80, i32 0
  store ptr %t81, ptr %t82
  call void @__inc_ref(ptr %t76)
  %t83 = getelementptr ptr, ptr %t80, i32 1
  store ptr %t76, ptr %t83
  %t84 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t80, ptr %t84
  %t85 = call ptr @v__apply__lift_1(ptr %t6, ptr %t77)
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

define internal ptr @v__apply__lift_1(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 81, label %tco.case.arm.81.11 i64 82, label %tco.case.arm.82.12 ]
tco.case.arm.81.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.82.12:
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

define internal ptr @v__lift_17(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 83 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__lift_17(ptr %v___input, ptr %t0)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t3
}

define internal ptr @v__cps__lift_17(ptr %v___input, ptr %v__k) {
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
  %t18 = call ptr @v__apply__lift_17(ptr %t6, ptr %t14)
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
  %t26 = call ptr @v__apply__lift_17(ptr %t6, ptr %t22)
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
  %t42 = inttoptr i64 84 to ptr
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
  %t45 = inttoptr i64 84 to ptr
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
  %t61 = call ptr @v__apply__lift_17(ptr %t6, ptr %t53)
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
  %t73 = call ptr @v__apply__lift_17(ptr %t6, ptr %t65)
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
  %t81 = inttoptr i64 41 to ptr
  %t82 = getelementptr ptr, ptr %t80, i32 0
  store ptr %t81, ptr %t82
  call void @__inc_ref(ptr %t76)
  %t83 = getelementptr ptr, ptr %t80, i32 1
  store ptr %t76, ptr %t83
  %t84 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t80, ptr %t84
  %t85 = call ptr @v__apply__lift_17(ptr %t6, ptr %t77)
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

define internal ptr @v__apply__lift_17(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 83, label %tco.case.arm.83.11 i64 84, label %tco.case.arm.84.12 ]
tco.case.arm.83.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.84.12:
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

define internal ptr @v__lift_24(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 85 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__lift_24(ptr %v___input, ptr %t0)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t3
}

define internal ptr @v__cps__lift_24(ptr %v___input, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.19 i64 7, label %tco.case.arm.7.31 i64 8, label %tco.case.arm.8.54 i64 9, label %tco.case.arm.9.66 i64 10, label %tco.case.arm.10.78 ]
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
  %t18 = call ptr @v__apply__lift_24(ptr %t6, ptr %t14)
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
  %t25 = call ptr @__alloc(i64 16, i32 1)
  %t26 = inttoptr i64 3801428867 to ptr
  %t27 = getelementptr ptr, ptr %t25, i32 0
  store ptr %t26, ptr %t27
  call void @__inc_ref(ptr %t21)
  %t28 = getelementptr ptr, ptr %t25, i32 1
  store ptr %t21, ptr %t28
  %t29 = getelementptr ptr, ptr %t22, i32 1
  store ptr %t25, ptr %t29
  %t30 = call ptr @v__apply__lift_24(ptr %t6, ptr %t22)
  call void @__free_recursive(ptr %t21)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t30, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.31:
  %t32 = getelementptr ptr, ptr %t5, i32 1
  %t33 = load ptr, ptr %t32
  %t34 = getelementptr ptr, ptr %t5, i32 2
  %t35 = load ptr, ptr %t34
  call void @__inc_ref(ptr %t35)
  %t36 = getelementptr i8, ptr %t5, i64 -8
  %t37 = load i32, ptr %t36
  %t38 = icmp eq i32 %t37, 1
  br i1 %t38, label %reuse.in_place.39, label %reuse.copy.40
reuse.in_place.39:
  %t42 = getelementptr ptr, ptr %t5, i32 2
  %t43 = load ptr, ptr %t42
  call void @__free_recursive(ptr %t43)
  %t46 = inttoptr i64 86 to ptr
  %t47 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t46, ptr %t47
  call void @__inc_ref(ptr %t6)
  %t44 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t44
  %t45 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t33, ptr %t45
  br label %reuse.join.41
reuse.copy.40:
  %t48 = call ptr @__alloc(i64 24, i32 2)
  %t49 = inttoptr i64 86 to ptr
  %t50 = getelementptr ptr, ptr %t48, i32 0
  store ptr %t49, ptr %t50
  call void @__inc_ref(ptr %t6)
  %t51 = getelementptr ptr, ptr %t48, i32 1
  store ptr %t6, ptr %t51
  call void @__inc_ref(ptr %t33)
  %t52 = getelementptr ptr, ptr %t48, i32 2
  store ptr %t33, ptr %t52
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.41
reuse.join.41:
  %t53 = phi ptr [ %t5, %reuse.in_place.39 ], [ %t48, %reuse.copy.40 ]
  call void @__inc_ref(ptr %t35)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t35)
  store ptr %t35, ptr %t3
  store ptr %t53, ptr %t4
  br label %tco.loop.0
tco.case.arm.8.54:
  %t55 = getelementptr ptr, ptr %t5, i32 1
  %t56 = load ptr, ptr %t55
  call void @__inc_ref(ptr %t56)
  call void @__inc_ref(ptr %t6)
  %t57 = call ptr @__alloc(i64 16, i32 1)
  %t58 = inttoptr i64 8 to ptr
  %t59 = getelementptr ptr, ptr %t57, i32 0
  store ptr %t58, ptr %t59
  %t60 = call ptr @__alloc(i64 16, i32 1)
  %t61 = inttoptr i64 42 to ptr
  %t62 = getelementptr ptr, ptr %t60, i32 0
  store ptr %t61, ptr %t62
  call void @__inc_ref(ptr %t56)
  %t63 = getelementptr ptr, ptr %t60, i32 1
  store ptr %t56, ptr %t63
  %t64 = getelementptr ptr, ptr %t57, i32 1
  store ptr %t60, ptr %t64
  %t65 = call ptr @v__apply__lift_24(ptr %t6, ptr %t57)
  call void @__free_recursive(ptr %t56)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t65, ptr %t2
  br label %tco.exit.1
tco.case.arm.9.66:
  %t67 = getelementptr ptr, ptr %t5, i32 1
  %t68 = load ptr, ptr %t67
  call void @__inc_ref(ptr %t68)
  call void @__inc_ref(ptr %t6)
  %t69 = call ptr @__alloc(i64 16, i32 1)
  %t70 = inttoptr i64 9 to ptr
  %t71 = getelementptr ptr, ptr %t69, i32 0
  store ptr %t70, ptr %t71
  %t72 = call ptr @__alloc(i64 16, i32 1)
  %t73 = inttoptr i64 43 to ptr
  %t74 = getelementptr ptr, ptr %t72, i32 0
  store ptr %t73, ptr %t74
  call void @__inc_ref(ptr %t68)
  %t75 = getelementptr ptr, ptr %t72, i32 1
  store ptr %t68, ptr %t75
  %t76 = getelementptr ptr, ptr %t69, i32 1
  store ptr %t72, ptr %t76
  %t77 = call ptr @v__apply__lift_24(ptr %t6, ptr %t69)
  call void @__free_recursive(ptr %t68)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t77, ptr %t2
  br label %tco.exit.1
tco.case.arm.10.78:
  %t79 = getelementptr ptr, ptr %t5, i32 1
  %t80 = load ptr, ptr %t79
  call void @__inc_ref(ptr %t80)
  call void @__inc_ref(ptr %t6)
  %t81 = call ptr @__alloc(i64 16, i32 1)
  %t82 = inttoptr i64 10 to ptr
  %t83 = getelementptr ptr, ptr %t81, i32 0
  store ptr %t82, ptr %t83
  %t84 = call ptr @__alloc(i64 16, i32 1)
  %t85 = inttoptr i64 44 to ptr
  %t86 = getelementptr ptr, ptr %t84, i32 0
  store ptr %t85, ptr %t86
  call void @__inc_ref(ptr %t80)
  %t87 = getelementptr ptr, ptr %t84, i32 1
  store ptr %t80, ptr %t87
  %t88 = getelementptr ptr, ptr %t81, i32 1
  store ptr %t84, ptr %t88
  %t89 = call ptr @v__apply__lift_24(ptr %t6, ptr %t81)
  call void @__free_recursive(ptr %t80)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t89, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t90 = load ptr, ptr %t2
  ret ptr %t90
}

define internal ptr @v__apply__lift_24(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 85, label %tco.case.arm.85.11 i64 86, label %tco.case.arm.86.12 ]
tco.case.arm.85.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.86.12:
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

define internal ptr @v__lift_28(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 87 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__lift_28(ptr %v___input, ptr %t0)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t3
}

define internal ptr @v__cps__lift_28(ptr %v___input, ptr %v__k) {
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
  %t18 = call ptr @v__apply__lift_28(ptr %t6, ptr %t14)
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
  %t26 = call ptr @v__apply__lift_28(ptr %t6, ptr %t22)
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
  %t42 = inttoptr i64 88 to ptr
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
  %t45 = inttoptr i64 88 to ptr
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
  %t57 = inttoptr i64 45 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  call void @__inc_ref(ptr %t52)
  %t59 = getelementptr ptr, ptr %t56, i32 1
  store ptr %t52, ptr %t59
  %t60 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t56, ptr %t60
  %t61 = call ptr @v__apply__lift_28(ptr %t6, ptr %t53)
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
  %t69 = inttoptr i64 47 to ptr
  %t70 = getelementptr ptr, ptr %t68, i32 0
  store ptr %t69, ptr %t70
  call void @__inc_ref(ptr %t64)
  %t71 = getelementptr ptr, ptr %t68, i32 1
  store ptr %t64, ptr %t71
  %t72 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t68, ptr %t72
  %t73 = call ptr @v__apply__lift_28(ptr %t6, ptr %t65)
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
  %t81 = inttoptr i64 48 to ptr
  %t82 = getelementptr ptr, ptr %t80, i32 0
  store ptr %t81, ptr %t82
  call void @__inc_ref(ptr %t76)
  %t83 = getelementptr ptr, ptr %t80, i32 1
  store ptr %t76, ptr %t83
  %t84 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t80, ptr %t84
  %t85 = call ptr @v__apply__lift_28(ptr %t6, ptr %t77)
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

define internal ptr @v__apply__lift_28(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 87, label %tco.case.arm.87.11 i64 88, label %tco.case.arm.88.12 ]
tco.case.arm.87.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.88.12:
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

define internal ptr @v__lift_36(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 89 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__lift_36(ptr %v___input, ptr %t0)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t3
}

define internal ptr @v__cps__lift_36(ptr %v___input, ptr %v__k) {
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
  %t18 = call ptr @v__apply__lift_36(ptr %t6, ptr %t14)
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
  %t26 = call ptr @v__apply__lift_36(ptr %t6, ptr %t22)
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
  %t42 = inttoptr i64 90 to ptr
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
  %t45 = inttoptr i64 90 to ptr
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
  %t57 = inttoptr i64 49 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  call void @__inc_ref(ptr %t52)
  %t59 = getelementptr ptr, ptr %t56, i32 1
  store ptr %t52, ptr %t59
  %t60 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t56, ptr %t60
  %t61 = call ptr @v__apply__lift_36(ptr %t6, ptr %t53)
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
  %t69 = inttoptr i64 50 to ptr
  %t70 = getelementptr ptr, ptr %t68, i32 0
  store ptr %t69, ptr %t70
  call void @__inc_ref(ptr %t64)
  %t71 = getelementptr ptr, ptr %t68, i32 1
  store ptr %t64, ptr %t71
  %t72 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t68, ptr %t72
  %t73 = call ptr @v__apply__lift_36(ptr %t6, ptr %t65)
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
  %t81 = inttoptr i64 51 to ptr
  %t82 = getelementptr ptr, ptr %t80, i32 0
  store ptr %t81, ptr %t82
  call void @__inc_ref(ptr %t76)
  %t83 = getelementptr ptr, ptr %t80, i32 1
  store ptr %t76, ptr %t83
  %t84 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t80, ptr %t84
  %t85 = call ptr @v__apply__lift_36(ptr %t6, ptr %t77)
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

define internal ptr @v__apply__lift_36(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 89, label %tco.case.arm.89.11 i64 90, label %tco.case.arm.90.12 ]
tco.case.arm.89.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.90.12:
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

define internal ptr @v__lift_43(ptr %v___input) {
  %t0 = getelementptr ptr, ptr %v___input, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.11 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v___input, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = call ptr @__alloc(i64 16, i32 1)
  %t8 = inttoptr i64 3 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  call void @__inc_ref(ptr %t6)
  %t10 = getelementptr ptr, ptr %t7, i32 1
  store ptr %t6, ptr %t10
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t7
case.arm.4.11:
  %t12 = getelementptr ptr, ptr %v___input, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @__alloc(i64 16, i32 1)
  %t15 = inttoptr i64 4 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  call void @__inc_ref(ptr %t13)
  %t17 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t13, ptr %t17
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t14
case.default.3:
  unreachable
}

define internal ptr @v__lam_44(ptr %v_args) {
  call void @__inc_ref(ptr %v_args)
  %t0 = call ptr @v_greet(ptr %v_args)
  %t1 = call ptr @v__lift_43(ptr %t0)
  %t2 = call ptr @v_eitherToIO(ptr %t1)
  call void @__free_recursive(ptr %v_args)
  ret ptr %t2
}

define internal ptr @v__lift_45(ptr %v___input) {
  %t0 = getelementptr ptr, ptr %v___input, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 11, label %case.arm.11.4 i64 12, label %case.arm.12.8 ]
case.arm.11.4:
  %t5 = call ptr @__alloc(i64 8, i32 0)
  %t6 = inttoptr i64 11 to ptr
  %t7 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t6, ptr %t7
  call void @__free_recursive(ptr %v___input)
  ret ptr %t5
case.arm.12.8:
  %t9 = getelementptr ptr, ptr %v___input, i32 1
  %t10 = load ptr, ptr %t9
  call void @__inc_ref(ptr %t10)
  %t11 = call ptr @__alloc(i64 16, i32 1)
  %t12 = inttoptr i64 12 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  call void @__inc_ref(ptr %t10)
  %t14 = getelementptr ptr, ptr %t11, i32 1
  store ptr %t10, ptr %t14
  call void @__free_recursive(ptr %t10)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t11
case.default.3:
  unreachable
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
  %t1 = inttoptr i64 91 to ptr
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
  %t39 = inttoptr i64 92 to ptr
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
  %t42 = inttoptr i64 92 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 91, label %tco.case.arm.91.11 i64 92, label %tco.case.arm.92.12 ]
tco.case.arm.91.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.92.12:
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

define internal ptr @v__df__rowspec_23_4(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 93 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df__rowspec_23_4(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df__rowspec_23_4(ptr %v_io, ptr %v__k) {
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
  %t15 = call ptr @v__lift_24(ptr %t14)
  %t16 = call ptr @v__apply__df__rowspec_23_4(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df__rowspec_23_4(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 94 to ptr
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
  %t43 = inttoptr i64 94 to ptr
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
  %t59 = call ptr @v__apply__df__rowspec_23_4(ptr %t6, ptr %t51)
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
  %t71 = call ptr @v__apply__df__rowspec_23_4(ptr %t6, ptr %t63)
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
  %t83 = call ptr @v__apply__df__rowspec_23_4(ptr %t6, ptr %t75)
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

define internal ptr @v__apply__df__rowspec_23_4(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 93, label %tco.case.arm.93.11 i64 94, label %tco.case.arm.94.12 ]
tco.case.arm.93.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.94.12:
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

define internal ptr @v__df_andThenIO_10(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 95 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_10(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_10(ptr %v_io, ptr %v__k) {
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
  %t14 = call ptr @v__lam_44(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_10(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_10(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 96 to ptr
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
  %t43 = inttoptr i64 96 to ptr
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
  %t55 = inttoptr i64 34 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df_andThenIO_10(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 35 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df_andThenIO_10(ptr %t6, ptr %t63)
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
  %t79 = inttoptr i64 36 to ptr
  %t80 = getelementptr ptr, ptr %t78, i32 0
  store ptr %t79, ptr %t80
  call void @__inc_ref(ptr %t74)
  %t81 = getelementptr ptr, ptr %t78, i32 1
  store ptr %t74, ptr %t81
  %t82 = getelementptr ptr, ptr %t75, i32 1
  store ptr %t78, ptr %t82
  %t83 = call ptr @v__apply__df_andThenIO_10(ptr %t6, ptr %t75)
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

define internal ptr @v__apply__df_andThenIO_10(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 95, label %tco.case.arm.95.11 i64 96, label %tco.case.arm.96.12 ]
tco.case.arm.95.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.96.12:
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

define internal ptr @v__df__rowspec_35_8(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 97 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df__rowspec_35_8(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df__rowspec_35_8(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.16 i64 7, label %tco.case.arm.7.24 i64 8, label %tco.case.arm.8.47 i64 9, label %tco.case.arm.9.59 i64 10, label %tco.case.arm.10.71 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_44(ptr %t13)
  %t15 = call ptr @v__apply__df__rowspec_35_8(ptr %t6, ptr %t14)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t15, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.16:
  %t17 = getelementptr ptr, ptr %t5, i32 1
  %t18 = load ptr, ptr %t17
  call void @__inc_ref(ptr %t18)
  call void @__inc_ref(ptr %t6)
  %t19 = call ptr @__alloc(i64 16, i32 1)
  %t20 = inttoptr i64 6 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  call void @__inc_ref(ptr %t18)
  %t22 = getelementptr ptr, ptr %t19, i32 1
  store ptr %t18, ptr %t22
  %t23 = call ptr @v__apply__df__rowspec_35_8(ptr %t6, ptr %t19)
  call void @__free_recursive(ptr %t18)
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
  %t39 = inttoptr i64 98 to ptr
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
  %t42 = inttoptr i64 98 to ptr
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
  %t54 = inttoptr i64 31 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  call void @__inc_ref(ptr %t49)
  %t56 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t49, ptr %t56
  %t57 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t53, ptr %t57
  %t58 = call ptr @v__apply__df__rowspec_35_8(ptr %t6, ptr %t50)
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
  %t66 = inttoptr i64 32 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  call void @__inc_ref(ptr %t61)
  %t68 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t61, ptr %t68
  %t69 = getelementptr ptr, ptr %t62, i32 1
  store ptr %t65, ptr %t69
  %t70 = call ptr @v__apply__df__rowspec_35_8(ptr %t6, ptr %t62)
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
  %t78 = inttoptr i64 33 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  call void @__inc_ref(ptr %t73)
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t73, ptr %t80
  %t81 = getelementptr ptr, ptr %t74, i32 1
  store ptr %t77, ptr %t81
  %t82 = call ptr @v__apply__df__rowspec_35_8(ptr %t6, ptr %t74)
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

define internal ptr @v__apply__df__rowspec_35_8(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 97, label %tco.case.arm.97.11 i64 98, label %tco.case.arm.98.12 ]
tco.case.arm.97.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.98.12:
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

define internal ptr @v__scc__apply1__df__lam_14_1__df__lam_15_2__df__lam_16_3__df__lam_32_5__df__lam_33_6__df__lam_34_7__df__lam_40_9__df__lam_41_14__df__lam_42_15__df__lam_5_11__df__lam_6_12__df__lam_7_13__lift_18__lift_19__lift_2__lift_20__lift_25__lift_26__lift_27__lift_29__lift_3__lift_30__lift_31__lift_37__lift_38__lift_39__lift_4(ptr %v__args) {
  call void @__inc_ref(ptr %v__args)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 99 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__scc__apply1__df__lam_14_1__df__lam_15_2__df__lam_16_3__df__lam_32_5__df__lam_33_6__df__lam_34_7__df__lam_40_9__df__lam_41_14__df__lam_42_15__df__lam_5_11__df__lam_6_12__df__lam_7_13__lift_18__lift_19__lift_2__lift_20__lift_25__lift_26__lift_27__lift_29__lift_3__lift_30__lift_31__lift_37__lift_38__lift_39__lift_4(ptr %v__args, ptr %t0)
  call void @__free_recursive(ptr %v__args)
  ret ptr %t3
}

define internal ptr @v__cps__scc__apply1__df__lam_14_1__df__lam_15_2__df__lam_16_3__df__lam_32_5__df__lam_33_6__df__lam_34_7__df__lam_40_9__df__lam_41_14__df__lam_42_15__df__lam_5_11__df__lam_6_12__df__lam_7_13__lift_18__lift_19__lift_2__lift_20__lift_25__lift_26__lift_27__lift_29__lift_3__lift_30__lift_31__lift_37__lift_38__lift_39__lift_4(ptr %v__args, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 53, label %tco.case.arm.53.11 i64 54, label %tco.case.arm.54.563 i64 55, label %tco.case.arm.55.586 i64 56, label %tco.case.arm.56.609 i64 57, label %tco.case.arm.57.632 i64 58, label %tco.case.arm.58.655 i64 59, label %tco.case.arm.59.678 i64 60, label %tco.case.arm.60.701 i64 61, label %tco.case.arm.61.724 i64 62, label %tco.case.arm.62.747 i64 63, label %tco.case.arm.63.770 i64 64, label %tco.case.arm.64.793 i64 65, label %tco.case.arm.65.816 i64 66, label %tco.case.arm.66.839 i64 67, label %tco.case.arm.67.862 i64 68, label %tco.case.arm.68.885 i64 69, label %tco.case.arm.69.908 i64 70, label %tco.case.arm.70.931 i64 71, label %tco.case.arm.71.954 i64 72, label %tco.case.arm.72.977 i64 73, label %tco.case.arm.73.1000 i64 74, label %tco.case.arm.74.1023 i64 75, label %tco.case.arm.75.1046 i64 76, label %tco.case.arm.76.1069 i64 77, label %tco.case.arm.77.1092 i64 78, label %tco.case.arm.78.1115 i64 79, label %tco.case.arm.79.1138 i64 80, label %tco.case.arm.80.1161 ]
tco.case.arm.53.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t5, i32 2
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  %t16 = getelementptr ptr, ptr %t13, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %tco.case.default.19 [ i64 25, label %tco.case.arm.25.20 i64 26, label %tco.case.arm.26.40 i64 27, label %tco.case.arm.27.60 i64 28, label %tco.case.arm.28.80 i64 29, label %tco.case.arm.29.100 i64 30, label %tco.case.arm.30.120 i64 31, label %tco.case.arm.31.140 i64 32, label %tco.case.arm.32.160 i64 33, label %tco.case.arm.33.180 i64 34, label %tco.case.arm.34.200 i64 35, label %tco.case.arm.35.220 i64 36, label %tco.case.arm.36.240 i64 37, label %tco.case.arm.37.260 i64 38, label %tco.case.arm.38.263 i64 39, label %tco.case.arm.39.283 i64 40, label %tco.case.arm.40.303 i64 41, label %tco.case.arm.41.323 i64 42, label %tco.case.arm.42.343 i64 43, label %tco.case.arm.43.363 i64 44, label %tco.case.arm.44.383 i64 45, label %tco.case.arm.45.403 i64 46, label %tco.case.arm.46.423 i64 47, label %tco.case.arm.47.443 i64 48, label %tco.case.arm.48.463 i64 49, label %tco.case.arm.49.483 i64 50, label %tco.case.arm.50.503 i64 51, label %tco.case.arm.51.523 i64 52, label %tco.case.arm.52.543 ]
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
  %t32 = inttoptr i64 54 to ptr
  %t33 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t32, ptr %t33
  call void @__inc_ref(ptr %t22)
  %t31 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t22, ptr %t31
  br label %reuse.join.28
reuse.copy.27:
  %t34 = call ptr @__alloc(i64 24, i32 2)
  %t35 = inttoptr i64 54 to ptr
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
  %t52 = inttoptr i64 55 to ptr
  %t53 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t52, ptr %t53
  call void @__inc_ref(ptr %t42)
  %t51 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t42, ptr %t51
  br label %reuse.join.48
reuse.copy.47:
  %t54 = call ptr @__alloc(i64 24, i32 2)
  %t55 = inttoptr i64 55 to ptr
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
  %t72 = inttoptr i64 56 to ptr
  %t73 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t72, ptr %t73
  call void @__inc_ref(ptr %t62)
  %t71 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t62, ptr %t71
  br label %reuse.join.68
reuse.copy.67:
  %t74 = call ptr @__alloc(i64 24, i32 2)
  %t75 = inttoptr i64 56 to ptr
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
  %t92 = inttoptr i64 57 to ptr
  %t93 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t92, ptr %t93
  call void @__inc_ref(ptr %t82)
  %t91 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t82, ptr %t91
  br label %reuse.join.88
reuse.copy.87:
  %t94 = call ptr @__alloc(i64 24, i32 2)
  %t95 = inttoptr i64 57 to ptr
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
  %t112 = inttoptr i64 58 to ptr
  %t113 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t112, ptr %t113
  call void @__inc_ref(ptr %t102)
  %t111 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t102, ptr %t111
  br label %reuse.join.108
reuse.copy.107:
  %t114 = call ptr @__alloc(i64 24, i32 2)
  %t115 = inttoptr i64 58 to ptr
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
  %t132 = inttoptr i64 59 to ptr
  %t133 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t132, ptr %t133
  call void @__inc_ref(ptr %t122)
  %t131 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t122, ptr %t131
  br label %reuse.join.128
reuse.copy.127:
  %t134 = call ptr @__alloc(i64 24, i32 2)
  %t135 = inttoptr i64 59 to ptr
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
  %t152 = inttoptr i64 60 to ptr
  %t153 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t152, ptr %t153
  call void @__inc_ref(ptr %t142)
  %t151 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t142, ptr %t151
  br label %reuse.join.148
reuse.copy.147:
  %t154 = call ptr @__alloc(i64 24, i32 2)
  %t155 = inttoptr i64 60 to ptr
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
  %t172 = inttoptr i64 61 to ptr
  %t173 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t172, ptr %t173
  call void @__inc_ref(ptr %t162)
  %t171 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t162, ptr %t171
  br label %reuse.join.168
reuse.copy.167:
  %t174 = call ptr @__alloc(i64 24, i32 2)
  %t175 = inttoptr i64 61 to ptr
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
  %t192 = inttoptr i64 62 to ptr
  %t193 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t192, ptr %t193
  call void @__inc_ref(ptr %t182)
  %t191 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t182, ptr %t191
  br label %reuse.join.188
reuse.copy.187:
  %t194 = call ptr @__alloc(i64 24, i32 2)
  %t195 = inttoptr i64 62 to ptr
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
  %t201 = getelementptr ptr, ptr %t13, i32 1
  %t202 = load ptr, ptr %t201
  call void @__inc_ref(ptr %t202)
  %t203 = getelementptr i8, ptr %t5, i64 -8
  %t204 = load i32, ptr %t203
  %t205 = icmp eq i32 %t204, 1
  br i1 %t205, label %reuse.in_place.206, label %reuse.copy.207
reuse.in_place.206:
  %t209 = getelementptr ptr, ptr %t5, i32 1
  %t210 = load ptr, ptr %t209
  call void @__free_recursive(ptr %t210)
  %t212 = inttoptr i64 63 to ptr
  %t213 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t212, ptr %t213
  call void @__inc_ref(ptr %t202)
  %t211 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t202, ptr %t211
  br label %reuse.join.208
reuse.copy.207:
  %t214 = call ptr @__alloc(i64 24, i32 2)
  %t215 = inttoptr i64 63 to ptr
  %t216 = getelementptr ptr, ptr %t214, i32 0
  store ptr %t215, ptr %t216
  call void @__inc_ref(ptr %t202)
  %t217 = getelementptr ptr, ptr %t214, i32 1
  store ptr %t202, ptr %t217
  call void @__inc_ref(ptr %t15)
  %t218 = getelementptr ptr, ptr %t214, i32 2
  store ptr %t15, ptr %t218
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.208
reuse.join.208:
  %t219 = phi ptr [ %t5, %reuse.in_place.206 ], [ %t214, %reuse.copy.207 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t202)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t219, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.35.220:
  %t221 = getelementptr ptr, ptr %t13, i32 1
  %t222 = load ptr, ptr %t221
  call void @__inc_ref(ptr %t222)
  %t223 = getelementptr i8, ptr %t5, i64 -8
  %t224 = load i32, ptr %t223
  %t225 = icmp eq i32 %t224, 1
  br i1 %t225, label %reuse.in_place.226, label %reuse.copy.227
reuse.in_place.226:
  %t229 = getelementptr ptr, ptr %t5, i32 1
  %t230 = load ptr, ptr %t229
  call void @__free_recursive(ptr %t230)
  %t232 = inttoptr i64 64 to ptr
  %t233 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t232, ptr %t233
  call void @__inc_ref(ptr %t222)
  %t231 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t222, ptr %t231
  br label %reuse.join.228
reuse.copy.227:
  %t234 = call ptr @__alloc(i64 24, i32 2)
  %t235 = inttoptr i64 64 to ptr
  %t236 = getelementptr ptr, ptr %t234, i32 0
  store ptr %t235, ptr %t236
  call void @__inc_ref(ptr %t222)
  %t237 = getelementptr ptr, ptr %t234, i32 1
  store ptr %t222, ptr %t237
  call void @__inc_ref(ptr %t15)
  %t238 = getelementptr ptr, ptr %t234, i32 2
  store ptr %t15, ptr %t238
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.228
reuse.join.228:
  %t239 = phi ptr [ %t5, %reuse.in_place.226 ], [ %t234, %reuse.copy.227 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t222)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t239, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.36.240:
  %t241 = getelementptr ptr, ptr %t13, i32 1
  %t242 = load ptr, ptr %t241
  call void @__inc_ref(ptr %t242)
  %t243 = getelementptr i8, ptr %t5, i64 -8
  %t244 = load i32, ptr %t243
  %t245 = icmp eq i32 %t244, 1
  br i1 %t245, label %reuse.in_place.246, label %reuse.copy.247
reuse.in_place.246:
  %t249 = getelementptr ptr, ptr %t5, i32 1
  %t250 = load ptr, ptr %t249
  call void @__free_recursive(ptr %t250)
  %t252 = inttoptr i64 65 to ptr
  %t253 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t252, ptr %t253
  call void @__inc_ref(ptr %t242)
  %t251 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t242, ptr %t251
  br label %reuse.join.248
reuse.copy.247:
  %t254 = call ptr @__alloc(i64 24, i32 2)
  %t255 = inttoptr i64 65 to ptr
  %t256 = getelementptr ptr, ptr %t254, i32 0
  store ptr %t255, ptr %t256
  call void @__inc_ref(ptr %t242)
  %t257 = getelementptr ptr, ptr %t254, i32 1
  store ptr %t242, ptr %t257
  call void @__inc_ref(ptr %t15)
  %t258 = getelementptr ptr, ptr %t254, i32 2
  store ptr %t15, ptr %t258
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.248
reuse.join.248:
  %t259 = phi ptr [ %t5, %reuse.in_place.246 ], [ %t254, %reuse.copy.247 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t242)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t259, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.37.260:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t15)
  %t261 = call ptr @v__io_getargs_cont(ptr %t15)
  %t262 = call ptr @v__apply__scc__apply1__df__lam_14_1__df__lam_15_2__df__lam_16_3__df__lam_32_5__df__lam_33_6__df__lam_34_7__df__lam_40_9__df__lam_41_14__df__lam_42_15__df__lam_5_11__df__lam_6_12__df__lam_7_13__lift_18__lift_19__lift_2__lift_20__lift_25__lift_26__lift_27__lift_29__lift_3__lift_30__lift_31__lift_37__lift_38__lift_39__lift_4(ptr %t6, ptr %t261)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t262, ptr %t2
  br label %tco.exit.1
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
  %t275 = inttoptr i64 66 to ptr
  %t276 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t275, ptr %t276
  call void @__inc_ref(ptr %t265)
  %t274 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t265, ptr %t274
  br label %reuse.join.271
reuse.copy.270:
  %t277 = call ptr @__alloc(i64 24, i32 2)
  %t278 = inttoptr i64 66 to ptr
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
  %t295 = inttoptr i64 67 to ptr
  %t296 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t295, ptr %t296
  call void @__inc_ref(ptr %t285)
  %t294 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t285, ptr %t294
  br label %reuse.join.291
reuse.copy.290:
  %t297 = call ptr @__alloc(i64 24, i32 2)
  %t298 = inttoptr i64 67 to ptr
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
  %t315 = inttoptr i64 68 to ptr
  %t316 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t315, ptr %t316
  call void @__inc_ref(ptr %t305)
  %t314 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t305, ptr %t314
  br label %reuse.join.311
reuse.copy.310:
  %t317 = call ptr @__alloc(i64 24, i32 2)
  %t318 = inttoptr i64 68 to ptr
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
tco.case.arm.41.323:
  %t324 = getelementptr ptr, ptr %t13, i32 1
  %t325 = load ptr, ptr %t324
  call void @__inc_ref(ptr %t325)
  %t326 = getelementptr i8, ptr %t5, i64 -8
  %t327 = load i32, ptr %t326
  %t328 = icmp eq i32 %t327, 1
  br i1 %t328, label %reuse.in_place.329, label %reuse.copy.330
reuse.in_place.329:
  %t332 = getelementptr ptr, ptr %t5, i32 1
  %t333 = load ptr, ptr %t332
  call void @__free_recursive(ptr %t333)
  %t335 = inttoptr i64 69 to ptr
  %t336 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t335, ptr %t336
  call void @__inc_ref(ptr %t325)
  %t334 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t325, ptr %t334
  br label %reuse.join.331
reuse.copy.330:
  %t337 = call ptr @__alloc(i64 24, i32 2)
  %t338 = inttoptr i64 69 to ptr
  %t339 = getelementptr ptr, ptr %t337, i32 0
  store ptr %t338, ptr %t339
  call void @__inc_ref(ptr %t325)
  %t340 = getelementptr ptr, ptr %t337, i32 1
  store ptr %t325, ptr %t340
  call void @__inc_ref(ptr %t15)
  %t341 = getelementptr ptr, ptr %t337, i32 2
  store ptr %t15, ptr %t341
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.331
reuse.join.331:
  %t342 = phi ptr [ %t5, %reuse.in_place.329 ], [ %t337, %reuse.copy.330 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t325)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t342, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.42.343:
  %t344 = getelementptr ptr, ptr %t13, i32 1
  %t345 = load ptr, ptr %t344
  call void @__inc_ref(ptr %t345)
  %t346 = getelementptr i8, ptr %t5, i64 -8
  %t347 = load i32, ptr %t346
  %t348 = icmp eq i32 %t347, 1
  br i1 %t348, label %reuse.in_place.349, label %reuse.copy.350
reuse.in_place.349:
  %t352 = getelementptr ptr, ptr %t5, i32 1
  %t353 = load ptr, ptr %t352
  call void @__free_recursive(ptr %t353)
  %t355 = inttoptr i64 70 to ptr
  %t356 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t355, ptr %t356
  call void @__inc_ref(ptr %t345)
  %t354 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t345, ptr %t354
  br label %reuse.join.351
reuse.copy.350:
  %t357 = call ptr @__alloc(i64 24, i32 2)
  %t358 = inttoptr i64 70 to ptr
  %t359 = getelementptr ptr, ptr %t357, i32 0
  store ptr %t358, ptr %t359
  call void @__inc_ref(ptr %t345)
  %t360 = getelementptr ptr, ptr %t357, i32 1
  store ptr %t345, ptr %t360
  call void @__inc_ref(ptr %t15)
  %t361 = getelementptr ptr, ptr %t357, i32 2
  store ptr %t15, ptr %t361
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.351
reuse.join.351:
  %t362 = phi ptr [ %t5, %reuse.in_place.349 ], [ %t357, %reuse.copy.350 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t345)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t362, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.43.363:
  %t364 = getelementptr ptr, ptr %t13, i32 1
  %t365 = load ptr, ptr %t364
  call void @__inc_ref(ptr %t365)
  %t366 = getelementptr i8, ptr %t5, i64 -8
  %t367 = load i32, ptr %t366
  %t368 = icmp eq i32 %t367, 1
  br i1 %t368, label %reuse.in_place.369, label %reuse.copy.370
reuse.in_place.369:
  %t372 = getelementptr ptr, ptr %t5, i32 1
  %t373 = load ptr, ptr %t372
  call void @__free_recursive(ptr %t373)
  %t375 = inttoptr i64 71 to ptr
  %t376 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t375, ptr %t376
  call void @__inc_ref(ptr %t365)
  %t374 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t365, ptr %t374
  br label %reuse.join.371
reuse.copy.370:
  %t377 = call ptr @__alloc(i64 24, i32 2)
  %t378 = inttoptr i64 71 to ptr
  %t379 = getelementptr ptr, ptr %t377, i32 0
  store ptr %t378, ptr %t379
  call void @__inc_ref(ptr %t365)
  %t380 = getelementptr ptr, ptr %t377, i32 1
  store ptr %t365, ptr %t380
  call void @__inc_ref(ptr %t15)
  %t381 = getelementptr ptr, ptr %t377, i32 2
  store ptr %t15, ptr %t381
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.371
reuse.join.371:
  %t382 = phi ptr [ %t5, %reuse.in_place.369 ], [ %t377, %reuse.copy.370 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t365)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t382, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.44.383:
  %t384 = getelementptr ptr, ptr %t13, i32 1
  %t385 = load ptr, ptr %t384
  call void @__inc_ref(ptr %t385)
  %t386 = getelementptr i8, ptr %t5, i64 -8
  %t387 = load i32, ptr %t386
  %t388 = icmp eq i32 %t387, 1
  br i1 %t388, label %reuse.in_place.389, label %reuse.copy.390
reuse.in_place.389:
  %t392 = getelementptr ptr, ptr %t5, i32 1
  %t393 = load ptr, ptr %t392
  call void @__free_recursive(ptr %t393)
  %t395 = inttoptr i64 72 to ptr
  %t396 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t395, ptr %t396
  call void @__inc_ref(ptr %t385)
  %t394 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t385, ptr %t394
  br label %reuse.join.391
reuse.copy.390:
  %t397 = call ptr @__alloc(i64 24, i32 2)
  %t398 = inttoptr i64 72 to ptr
  %t399 = getelementptr ptr, ptr %t397, i32 0
  store ptr %t398, ptr %t399
  call void @__inc_ref(ptr %t385)
  %t400 = getelementptr ptr, ptr %t397, i32 1
  store ptr %t385, ptr %t400
  call void @__inc_ref(ptr %t15)
  %t401 = getelementptr ptr, ptr %t397, i32 2
  store ptr %t15, ptr %t401
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.391
reuse.join.391:
  %t402 = phi ptr [ %t5, %reuse.in_place.389 ], [ %t397, %reuse.copy.390 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t385)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t402, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.45.403:
  %t404 = getelementptr ptr, ptr %t13, i32 1
  %t405 = load ptr, ptr %t404
  call void @__inc_ref(ptr %t405)
  %t406 = getelementptr i8, ptr %t5, i64 -8
  %t407 = load i32, ptr %t406
  %t408 = icmp eq i32 %t407, 1
  br i1 %t408, label %reuse.in_place.409, label %reuse.copy.410
reuse.in_place.409:
  %t412 = getelementptr ptr, ptr %t5, i32 1
  %t413 = load ptr, ptr %t412
  call void @__free_recursive(ptr %t413)
  %t415 = inttoptr i64 73 to ptr
  %t416 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t415, ptr %t416
  call void @__inc_ref(ptr %t405)
  %t414 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t405, ptr %t414
  br label %reuse.join.411
reuse.copy.410:
  %t417 = call ptr @__alloc(i64 24, i32 2)
  %t418 = inttoptr i64 73 to ptr
  %t419 = getelementptr ptr, ptr %t417, i32 0
  store ptr %t418, ptr %t419
  call void @__inc_ref(ptr %t405)
  %t420 = getelementptr ptr, ptr %t417, i32 1
  store ptr %t405, ptr %t420
  call void @__inc_ref(ptr %t15)
  %t421 = getelementptr ptr, ptr %t417, i32 2
  store ptr %t15, ptr %t421
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.411
reuse.join.411:
  %t422 = phi ptr [ %t5, %reuse.in_place.409 ], [ %t417, %reuse.copy.410 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t405)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t422, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.46.423:
  %t424 = getelementptr ptr, ptr %t13, i32 1
  %t425 = load ptr, ptr %t424
  call void @__inc_ref(ptr %t425)
  %t426 = getelementptr i8, ptr %t5, i64 -8
  %t427 = load i32, ptr %t426
  %t428 = icmp eq i32 %t427, 1
  br i1 %t428, label %reuse.in_place.429, label %reuse.copy.430
reuse.in_place.429:
  %t432 = getelementptr ptr, ptr %t5, i32 1
  %t433 = load ptr, ptr %t432
  call void @__free_recursive(ptr %t433)
  %t435 = inttoptr i64 74 to ptr
  %t436 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t435, ptr %t436
  call void @__inc_ref(ptr %t425)
  %t434 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t425, ptr %t434
  br label %reuse.join.431
reuse.copy.430:
  %t437 = call ptr @__alloc(i64 24, i32 2)
  %t438 = inttoptr i64 74 to ptr
  %t439 = getelementptr ptr, ptr %t437, i32 0
  store ptr %t438, ptr %t439
  call void @__inc_ref(ptr %t425)
  %t440 = getelementptr ptr, ptr %t437, i32 1
  store ptr %t425, ptr %t440
  call void @__inc_ref(ptr %t15)
  %t441 = getelementptr ptr, ptr %t437, i32 2
  store ptr %t15, ptr %t441
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.431
reuse.join.431:
  %t442 = phi ptr [ %t5, %reuse.in_place.429 ], [ %t437, %reuse.copy.430 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t425)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t442, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.47.443:
  %t444 = getelementptr ptr, ptr %t13, i32 1
  %t445 = load ptr, ptr %t444
  call void @__inc_ref(ptr %t445)
  %t446 = getelementptr i8, ptr %t5, i64 -8
  %t447 = load i32, ptr %t446
  %t448 = icmp eq i32 %t447, 1
  br i1 %t448, label %reuse.in_place.449, label %reuse.copy.450
reuse.in_place.449:
  %t452 = getelementptr ptr, ptr %t5, i32 1
  %t453 = load ptr, ptr %t452
  call void @__free_recursive(ptr %t453)
  %t455 = inttoptr i64 75 to ptr
  %t456 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t455, ptr %t456
  call void @__inc_ref(ptr %t445)
  %t454 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t445, ptr %t454
  br label %reuse.join.451
reuse.copy.450:
  %t457 = call ptr @__alloc(i64 24, i32 2)
  %t458 = inttoptr i64 75 to ptr
  %t459 = getelementptr ptr, ptr %t457, i32 0
  store ptr %t458, ptr %t459
  call void @__inc_ref(ptr %t445)
  %t460 = getelementptr ptr, ptr %t457, i32 1
  store ptr %t445, ptr %t460
  call void @__inc_ref(ptr %t15)
  %t461 = getelementptr ptr, ptr %t457, i32 2
  store ptr %t15, ptr %t461
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.451
reuse.join.451:
  %t462 = phi ptr [ %t5, %reuse.in_place.449 ], [ %t457, %reuse.copy.450 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t445)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t462, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.48.463:
  %t464 = getelementptr ptr, ptr %t13, i32 1
  %t465 = load ptr, ptr %t464
  call void @__inc_ref(ptr %t465)
  %t466 = getelementptr i8, ptr %t5, i64 -8
  %t467 = load i32, ptr %t466
  %t468 = icmp eq i32 %t467, 1
  br i1 %t468, label %reuse.in_place.469, label %reuse.copy.470
reuse.in_place.469:
  %t472 = getelementptr ptr, ptr %t5, i32 1
  %t473 = load ptr, ptr %t472
  call void @__free_recursive(ptr %t473)
  %t475 = inttoptr i64 76 to ptr
  %t476 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t475, ptr %t476
  call void @__inc_ref(ptr %t465)
  %t474 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t465, ptr %t474
  br label %reuse.join.471
reuse.copy.470:
  %t477 = call ptr @__alloc(i64 24, i32 2)
  %t478 = inttoptr i64 76 to ptr
  %t479 = getelementptr ptr, ptr %t477, i32 0
  store ptr %t478, ptr %t479
  call void @__inc_ref(ptr %t465)
  %t480 = getelementptr ptr, ptr %t477, i32 1
  store ptr %t465, ptr %t480
  call void @__inc_ref(ptr %t15)
  %t481 = getelementptr ptr, ptr %t477, i32 2
  store ptr %t15, ptr %t481
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.471
reuse.join.471:
  %t482 = phi ptr [ %t5, %reuse.in_place.469 ], [ %t477, %reuse.copy.470 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t465)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t482, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.49.483:
  %t484 = getelementptr ptr, ptr %t13, i32 1
  %t485 = load ptr, ptr %t484
  call void @__inc_ref(ptr %t485)
  %t486 = getelementptr i8, ptr %t5, i64 -8
  %t487 = load i32, ptr %t486
  %t488 = icmp eq i32 %t487, 1
  br i1 %t488, label %reuse.in_place.489, label %reuse.copy.490
reuse.in_place.489:
  %t492 = getelementptr ptr, ptr %t5, i32 1
  %t493 = load ptr, ptr %t492
  call void @__free_recursive(ptr %t493)
  %t495 = inttoptr i64 77 to ptr
  %t496 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t495, ptr %t496
  call void @__inc_ref(ptr %t485)
  %t494 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t485, ptr %t494
  br label %reuse.join.491
reuse.copy.490:
  %t497 = call ptr @__alloc(i64 24, i32 2)
  %t498 = inttoptr i64 77 to ptr
  %t499 = getelementptr ptr, ptr %t497, i32 0
  store ptr %t498, ptr %t499
  call void @__inc_ref(ptr %t485)
  %t500 = getelementptr ptr, ptr %t497, i32 1
  store ptr %t485, ptr %t500
  call void @__inc_ref(ptr %t15)
  %t501 = getelementptr ptr, ptr %t497, i32 2
  store ptr %t15, ptr %t501
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.491
reuse.join.491:
  %t502 = phi ptr [ %t5, %reuse.in_place.489 ], [ %t497, %reuse.copy.490 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t485)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t502, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.50.503:
  %t504 = getelementptr ptr, ptr %t13, i32 1
  %t505 = load ptr, ptr %t504
  call void @__inc_ref(ptr %t505)
  %t506 = getelementptr i8, ptr %t5, i64 -8
  %t507 = load i32, ptr %t506
  %t508 = icmp eq i32 %t507, 1
  br i1 %t508, label %reuse.in_place.509, label %reuse.copy.510
reuse.in_place.509:
  %t512 = getelementptr ptr, ptr %t5, i32 1
  %t513 = load ptr, ptr %t512
  call void @__free_recursive(ptr %t513)
  %t515 = inttoptr i64 78 to ptr
  %t516 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t515, ptr %t516
  call void @__inc_ref(ptr %t505)
  %t514 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t505, ptr %t514
  br label %reuse.join.511
reuse.copy.510:
  %t517 = call ptr @__alloc(i64 24, i32 2)
  %t518 = inttoptr i64 78 to ptr
  %t519 = getelementptr ptr, ptr %t517, i32 0
  store ptr %t518, ptr %t519
  call void @__inc_ref(ptr %t505)
  %t520 = getelementptr ptr, ptr %t517, i32 1
  store ptr %t505, ptr %t520
  call void @__inc_ref(ptr %t15)
  %t521 = getelementptr ptr, ptr %t517, i32 2
  store ptr %t15, ptr %t521
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.511
reuse.join.511:
  %t522 = phi ptr [ %t5, %reuse.in_place.509 ], [ %t517, %reuse.copy.510 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t505)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t522, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.51.523:
  %t524 = getelementptr ptr, ptr %t13, i32 1
  %t525 = load ptr, ptr %t524
  call void @__inc_ref(ptr %t525)
  %t526 = getelementptr i8, ptr %t5, i64 -8
  %t527 = load i32, ptr %t526
  %t528 = icmp eq i32 %t527, 1
  br i1 %t528, label %reuse.in_place.529, label %reuse.copy.530
reuse.in_place.529:
  %t532 = getelementptr ptr, ptr %t5, i32 1
  %t533 = load ptr, ptr %t532
  call void @__free_recursive(ptr %t533)
  %t535 = inttoptr i64 79 to ptr
  %t536 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t535, ptr %t536
  call void @__inc_ref(ptr %t525)
  %t534 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t525, ptr %t534
  br label %reuse.join.531
reuse.copy.530:
  %t537 = call ptr @__alloc(i64 24, i32 2)
  %t538 = inttoptr i64 79 to ptr
  %t539 = getelementptr ptr, ptr %t537, i32 0
  store ptr %t538, ptr %t539
  call void @__inc_ref(ptr %t525)
  %t540 = getelementptr ptr, ptr %t537, i32 1
  store ptr %t525, ptr %t540
  call void @__inc_ref(ptr %t15)
  %t541 = getelementptr ptr, ptr %t537, i32 2
  store ptr %t15, ptr %t541
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.531
reuse.join.531:
  %t542 = phi ptr [ %t5, %reuse.in_place.529 ], [ %t537, %reuse.copy.530 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t525)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t542, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.52.543:
  %t544 = getelementptr ptr, ptr %t13, i32 1
  %t545 = load ptr, ptr %t544
  call void @__inc_ref(ptr %t545)
  %t546 = getelementptr i8, ptr %t5, i64 -8
  %t547 = load i32, ptr %t546
  %t548 = icmp eq i32 %t547, 1
  br i1 %t548, label %reuse.in_place.549, label %reuse.copy.550
reuse.in_place.549:
  %t552 = getelementptr ptr, ptr %t5, i32 1
  %t553 = load ptr, ptr %t552
  call void @__free_recursive(ptr %t553)
  %t555 = inttoptr i64 80 to ptr
  %t556 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t555, ptr %t556
  call void @__inc_ref(ptr %t545)
  %t554 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t545, ptr %t554
  br label %reuse.join.551
reuse.copy.550:
  %t557 = call ptr @__alloc(i64 24, i32 2)
  %t558 = inttoptr i64 80 to ptr
  %t559 = getelementptr ptr, ptr %t557, i32 0
  store ptr %t558, ptr %t559
  call void @__inc_ref(ptr %t545)
  %t560 = getelementptr ptr, ptr %t557, i32 1
  store ptr %t545, ptr %t560
  call void @__inc_ref(ptr %t15)
  %t561 = getelementptr ptr, ptr %t557, i32 2
  store ptr %t15, ptr %t561
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.551
reuse.join.551:
  %t562 = phi ptr [ %t5, %reuse.in_place.549 ], [ %t557, %reuse.copy.550 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t545)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t562, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.default.19:
  unreachable
tco.case.arm.54.563:
  %t564 = getelementptr ptr, ptr %t5, i32 1
  %t565 = load ptr, ptr %t564
  %t566 = getelementptr ptr, ptr %t5, i32 2
  %t567 = load ptr, ptr %t566
  %t568 = getelementptr i8, ptr %t5, i64 -8
  %t569 = load i32, ptr %t568
  %t570 = icmp eq i32 %t569, 1
  br i1 %t570, label %reuse.in_place.571, label %reuse.copy.572
reuse.in_place.571:
  %t574 = inttoptr i64 53 to ptr
  %t575 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t574, ptr %t575
  br label %reuse.join.573
reuse.copy.572:
  %t576 = call ptr @__alloc(i64 24, i32 2)
  %t577 = inttoptr i64 53 to ptr
  %t578 = getelementptr ptr, ptr %t576, i32 0
  store ptr %t577, ptr %t578
  call void @__inc_ref(ptr %t565)
  %t579 = getelementptr ptr, ptr %t576, i32 1
  store ptr %t565, ptr %t579
  call void @__inc_ref(ptr %t567)
  %t580 = getelementptr ptr, ptr %t576, i32 2
  store ptr %t567, ptr %t580
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.573
reuse.join.573:
  %t581 = phi ptr [ %t5, %reuse.in_place.571 ], [ %t576, %reuse.copy.572 ]
  %t582 = call ptr @__alloc(i64 16, i32 1)
  %t583 = inttoptr i64 100 to ptr
  %t584 = getelementptr ptr, ptr %t582, i32 0
  store ptr %t583, ptr %t584
  call void @__inc_ref(ptr %t6)
  %t585 = getelementptr ptr, ptr %t582, i32 1
  store ptr %t6, ptr %t585
  call void @__free_recursive(ptr %t6)
  store ptr %t581, ptr %t3
  store ptr %t582, ptr %t4
  br label %tco.loop.0
tco.case.arm.55.586:
  %t587 = getelementptr ptr, ptr %t5, i32 1
  %t588 = load ptr, ptr %t587
  %t589 = getelementptr ptr, ptr %t5, i32 2
  %t590 = load ptr, ptr %t589
  %t591 = getelementptr i8, ptr %t5, i64 -8
  %t592 = load i32, ptr %t591
  %t593 = icmp eq i32 %t592, 1
  br i1 %t593, label %reuse.in_place.594, label %reuse.copy.595
reuse.in_place.594:
  %t597 = inttoptr i64 53 to ptr
  %t598 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t597, ptr %t598
  br label %reuse.join.596
reuse.copy.595:
  %t599 = call ptr @__alloc(i64 24, i32 2)
  %t600 = inttoptr i64 53 to ptr
  %t601 = getelementptr ptr, ptr %t599, i32 0
  store ptr %t600, ptr %t601
  call void @__inc_ref(ptr %t588)
  %t602 = getelementptr ptr, ptr %t599, i32 1
  store ptr %t588, ptr %t602
  call void @__inc_ref(ptr %t590)
  %t603 = getelementptr ptr, ptr %t599, i32 2
  store ptr %t590, ptr %t603
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.596
reuse.join.596:
  %t604 = phi ptr [ %t5, %reuse.in_place.594 ], [ %t599, %reuse.copy.595 ]
  %t605 = call ptr @__alloc(i64 16, i32 1)
  %t606 = inttoptr i64 101 to ptr
  %t607 = getelementptr ptr, ptr %t605, i32 0
  store ptr %t606, ptr %t607
  call void @__inc_ref(ptr %t6)
  %t608 = getelementptr ptr, ptr %t605, i32 1
  store ptr %t6, ptr %t608
  call void @__free_recursive(ptr %t6)
  store ptr %t604, ptr %t3
  store ptr %t605, ptr %t4
  br label %tco.loop.0
tco.case.arm.56.609:
  %t610 = getelementptr ptr, ptr %t5, i32 1
  %t611 = load ptr, ptr %t610
  %t612 = getelementptr ptr, ptr %t5, i32 2
  %t613 = load ptr, ptr %t612
  %t614 = getelementptr i8, ptr %t5, i64 -8
  %t615 = load i32, ptr %t614
  %t616 = icmp eq i32 %t615, 1
  br i1 %t616, label %reuse.in_place.617, label %reuse.copy.618
reuse.in_place.617:
  %t620 = inttoptr i64 53 to ptr
  %t621 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t620, ptr %t621
  br label %reuse.join.619
reuse.copy.618:
  %t622 = call ptr @__alloc(i64 24, i32 2)
  %t623 = inttoptr i64 53 to ptr
  %t624 = getelementptr ptr, ptr %t622, i32 0
  store ptr %t623, ptr %t624
  call void @__inc_ref(ptr %t611)
  %t625 = getelementptr ptr, ptr %t622, i32 1
  store ptr %t611, ptr %t625
  call void @__inc_ref(ptr %t613)
  %t626 = getelementptr ptr, ptr %t622, i32 2
  store ptr %t613, ptr %t626
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.619
reuse.join.619:
  %t627 = phi ptr [ %t5, %reuse.in_place.617 ], [ %t622, %reuse.copy.618 ]
  %t628 = call ptr @__alloc(i64 16, i32 1)
  %t629 = inttoptr i64 102 to ptr
  %t630 = getelementptr ptr, ptr %t628, i32 0
  store ptr %t629, ptr %t630
  call void @__inc_ref(ptr %t6)
  %t631 = getelementptr ptr, ptr %t628, i32 1
  store ptr %t6, ptr %t631
  call void @__free_recursive(ptr %t6)
  store ptr %t627, ptr %t3
  store ptr %t628, ptr %t4
  br label %tco.loop.0
tco.case.arm.57.632:
  %t633 = getelementptr ptr, ptr %t5, i32 1
  %t634 = load ptr, ptr %t633
  %t635 = getelementptr ptr, ptr %t5, i32 2
  %t636 = load ptr, ptr %t635
  %t637 = getelementptr i8, ptr %t5, i64 -8
  %t638 = load i32, ptr %t637
  %t639 = icmp eq i32 %t638, 1
  br i1 %t639, label %reuse.in_place.640, label %reuse.copy.641
reuse.in_place.640:
  %t643 = inttoptr i64 53 to ptr
  %t644 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t643, ptr %t644
  br label %reuse.join.642
reuse.copy.641:
  %t645 = call ptr @__alloc(i64 24, i32 2)
  %t646 = inttoptr i64 53 to ptr
  %t647 = getelementptr ptr, ptr %t645, i32 0
  store ptr %t646, ptr %t647
  call void @__inc_ref(ptr %t634)
  %t648 = getelementptr ptr, ptr %t645, i32 1
  store ptr %t634, ptr %t648
  call void @__inc_ref(ptr %t636)
  %t649 = getelementptr ptr, ptr %t645, i32 2
  store ptr %t636, ptr %t649
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.642
reuse.join.642:
  %t650 = phi ptr [ %t5, %reuse.in_place.640 ], [ %t645, %reuse.copy.641 ]
  %t651 = call ptr @__alloc(i64 16, i32 1)
  %t652 = inttoptr i64 103 to ptr
  %t653 = getelementptr ptr, ptr %t651, i32 0
  store ptr %t652, ptr %t653
  call void @__inc_ref(ptr %t6)
  %t654 = getelementptr ptr, ptr %t651, i32 1
  store ptr %t6, ptr %t654
  call void @__free_recursive(ptr %t6)
  store ptr %t650, ptr %t3
  store ptr %t651, ptr %t4
  br label %tco.loop.0
tco.case.arm.58.655:
  %t656 = getelementptr ptr, ptr %t5, i32 1
  %t657 = load ptr, ptr %t656
  %t658 = getelementptr ptr, ptr %t5, i32 2
  %t659 = load ptr, ptr %t658
  %t660 = getelementptr i8, ptr %t5, i64 -8
  %t661 = load i32, ptr %t660
  %t662 = icmp eq i32 %t661, 1
  br i1 %t662, label %reuse.in_place.663, label %reuse.copy.664
reuse.in_place.663:
  %t666 = inttoptr i64 53 to ptr
  %t667 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t666, ptr %t667
  br label %reuse.join.665
reuse.copy.664:
  %t668 = call ptr @__alloc(i64 24, i32 2)
  %t669 = inttoptr i64 53 to ptr
  %t670 = getelementptr ptr, ptr %t668, i32 0
  store ptr %t669, ptr %t670
  call void @__inc_ref(ptr %t657)
  %t671 = getelementptr ptr, ptr %t668, i32 1
  store ptr %t657, ptr %t671
  call void @__inc_ref(ptr %t659)
  %t672 = getelementptr ptr, ptr %t668, i32 2
  store ptr %t659, ptr %t672
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.665
reuse.join.665:
  %t673 = phi ptr [ %t5, %reuse.in_place.663 ], [ %t668, %reuse.copy.664 ]
  %t674 = call ptr @__alloc(i64 16, i32 1)
  %t675 = inttoptr i64 104 to ptr
  %t676 = getelementptr ptr, ptr %t674, i32 0
  store ptr %t675, ptr %t676
  call void @__inc_ref(ptr %t6)
  %t677 = getelementptr ptr, ptr %t674, i32 1
  store ptr %t6, ptr %t677
  call void @__free_recursive(ptr %t6)
  store ptr %t673, ptr %t3
  store ptr %t674, ptr %t4
  br label %tco.loop.0
tco.case.arm.59.678:
  %t679 = getelementptr ptr, ptr %t5, i32 1
  %t680 = load ptr, ptr %t679
  %t681 = getelementptr ptr, ptr %t5, i32 2
  %t682 = load ptr, ptr %t681
  %t683 = getelementptr i8, ptr %t5, i64 -8
  %t684 = load i32, ptr %t683
  %t685 = icmp eq i32 %t684, 1
  br i1 %t685, label %reuse.in_place.686, label %reuse.copy.687
reuse.in_place.686:
  %t689 = inttoptr i64 53 to ptr
  %t690 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t689, ptr %t690
  br label %reuse.join.688
reuse.copy.687:
  %t691 = call ptr @__alloc(i64 24, i32 2)
  %t692 = inttoptr i64 53 to ptr
  %t693 = getelementptr ptr, ptr %t691, i32 0
  store ptr %t692, ptr %t693
  call void @__inc_ref(ptr %t680)
  %t694 = getelementptr ptr, ptr %t691, i32 1
  store ptr %t680, ptr %t694
  call void @__inc_ref(ptr %t682)
  %t695 = getelementptr ptr, ptr %t691, i32 2
  store ptr %t682, ptr %t695
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.688
reuse.join.688:
  %t696 = phi ptr [ %t5, %reuse.in_place.686 ], [ %t691, %reuse.copy.687 ]
  %t697 = call ptr @__alloc(i64 16, i32 1)
  %t698 = inttoptr i64 105 to ptr
  %t699 = getelementptr ptr, ptr %t697, i32 0
  store ptr %t698, ptr %t699
  call void @__inc_ref(ptr %t6)
  %t700 = getelementptr ptr, ptr %t697, i32 1
  store ptr %t6, ptr %t700
  call void @__free_recursive(ptr %t6)
  store ptr %t696, ptr %t3
  store ptr %t697, ptr %t4
  br label %tco.loop.0
tco.case.arm.60.701:
  %t702 = getelementptr ptr, ptr %t5, i32 1
  %t703 = load ptr, ptr %t702
  %t704 = getelementptr ptr, ptr %t5, i32 2
  %t705 = load ptr, ptr %t704
  %t706 = getelementptr i8, ptr %t5, i64 -8
  %t707 = load i32, ptr %t706
  %t708 = icmp eq i32 %t707, 1
  br i1 %t708, label %reuse.in_place.709, label %reuse.copy.710
reuse.in_place.709:
  %t712 = inttoptr i64 53 to ptr
  %t713 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t712, ptr %t713
  br label %reuse.join.711
reuse.copy.710:
  %t714 = call ptr @__alloc(i64 24, i32 2)
  %t715 = inttoptr i64 53 to ptr
  %t716 = getelementptr ptr, ptr %t714, i32 0
  store ptr %t715, ptr %t716
  call void @__inc_ref(ptr %t703)
  %t717 = getelementptr ptr, ptr %t714, i32 1
  store ptr %t703, ptr %t717
  call void @__inc_ref(ptr %t705)
  %t718 = getelementptr ptr, ptr %t714, i32 2
  store ptr %t705, ptr %t718
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.711
reuse.join.711:
  %t719 = phi ptr [ %t5, %reuse.in_place.709 ], [ %t714, %reuse.copy.710 ]
  %t720 = call ptr @__alloc(i64 16, i32 1)
  %t721 = inttoptr i64 106 to ptr
  %t722 = getelementptr ptr, ptr %t720, i32 0
  store ptr %t721, ptr %t722
  call void @__inc_ref(ptr %t6)
  %t723 = getelementptr ptr, ptr %t720, i32 1
  store ptr %t6, ptr %t723
  call void @__free_recursive(ptr %t6)
  store ptr %t719, ptr %t3
  store ptr %t720, ptr %t4
  br label %tco.loop.0
tco.case.arm.61.724:
  %t725 = getelementptr ptr, ptr %t5, i32 1
  %t726 = load ptr, ptr %t725
  %t727 = getelementptr ptr, ptr %t5, i32 2
  %t728 = load ptr, ptr %t727
  %t729 = getelementptr i8, ptr %t5, i64 -8
  %t730 = load i32, ptr %t729
  %t731 = icmp eq i32 %t730, 1
  br i1 %t731, label %reuse.in_place.732, label %reuse.copy.733
reuse.in_place.732:
  %t735 = inttoptr i64 53 to ptr
  %t736 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t735, ptr %t736
  br label %reuse.join.734
reuse.copy.733:
  %t737 = call ptr @__alloc(i64 24, i32 2)
  %t738 = inttoptr i64 53 to ptr
  %t739 = getelementptr ptr, ptr %t737, i32 0
  store ptr %t738, ptr %t739
  call void @__inc_ref(ptr %t726)
  %t740 = getelementptr ptr, ptr %t737, i32 1
  store ptr %t726, ptr %t740
  call void @__inc_ref(ptr %t728)
  %t741 = getelementptr ptr, ptr %t737, i32 2
  store ptr %t728, ptr %t741
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.734
reuse.join.734:
  %t742 = phi ptr [ %t5, %reuse.in_place.732 ], [ %t737, %reuse.copy.733 ]
  %t743 = call ptr @__alloc(i64 16, i32 1)
  %t744 = inttoptr i64 107 to ptr
  %t745 = getelementptr ptr, ptr %t743, i32 0
  store ptr %t744, ptr %t745
  call void @__inc_ref(ptr %t6)
  %t746 = getelementptr ptr, ptr %t743, i32 1
  store ptr %t6, ptr %t746
  call void @__free_recursive(ptr %t6)
  store ptr %t742, ptr %t3
  store ptr %t743, ptr %t4
  br label %tco.loop.0
tco.case.arm.62.747:
  %t748 = getelementptr ptr, ptr %t5, i32 1
  %t749 = load ptr, ptr %t748
  %t750 = getelementptr ptr, ptr %t5, i32 2
  %t751 = load ptr, ptr %t750
  %t752 = getelementptr i8, ptr %t5, i64 -8
  %t753 = load i32, ptr %t752
  %t754 = icmp eq i32 %t753, 1
  br i1 %t754, label %reuse.in_place.755, label %reuse.copy.756
reuse.in_place.755:
  %t758 = inttoptr i64 53 to ptr
  %t759 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t758, ptr %t759
  br label %reuse.join.757
reuse.copy.756:
  %t760 = call ptr @__alloc(i64 24, i32 2)
  %t761 = inttoptr i64 53 to ptr
  %t762 = getelementptr ptr, ptr %t760, i32 0
  store ptr %t761, ptr %t762
  call void @__inc_ref(ptr %t749)
  %t763 = getelementptr ptr, ptr %t760, i32 1
  store ptr %t749, ptr %t763
  call void @__inc_ref(ptr %t751)
  %t764 = getelementptr ptr, ptr %t760, i32 2
  store ptr %t751, ptr %t764
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.757
reuse.join.757:
  %t765 = phi ptr [ %t5, %reuse.in_place.755 ], [ %t760, %reuse.copy.756 ]
  %t766 = call ptr @__alloc(i64 16, i32 1)
  %t767 = inttoptr i64 108 to ptr
  %t768 = getelementptr ptr, ptr %t766, i32 0
  store ptr %t767, ptr %t768
  call void @__inc_ref(ptr %t6)
  %t769 = getelementptr ptr, ptr %t766, i32 1
  store ptr %t6, ptr %t769
  call void @__free_recursive(ptr %t6)
  store ptr %t765, ptr %t3
  store ptr %t766, ptr %t4
  br label %tco.loop.0
tco.case.arm.63.770:
  %t771 = getelementptr ptr, ptr %t5, i32 1
  %t772 = load ptr, ptr %t771
  %t773 = getelementptr ptr, ptr %t5, i32 2
  %t774 = load ptr, ptr %t773
  %t775 = getelementptr i8, ptr %t5, i64 -8
  %t776 = load i32, ptr %t775
  %t777 = icmp eq i32 %t776, 1
  br i1 %t777, label %reuse.in_place.778, label %reuse.copy.779
reuse.in_place.778:
  %t781 = inttoptr i64 53 to ptr
  %t782 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t781, ptr %t782
  br label %reuse.join.780
reuse.copy.779:
  %t783 = call ptr @__alloc(i64 24, i32 2)
  %t784 = inttoptr i64 53 to ptr
  %t785 = getelementptr ptr, ptr %t783, i32 0
  store ptr %t784, ptr %t785
  call void @__inc_ref(ptr %t772)
  %t786 = getelementptr ptr, ptr %t783, i32 1
  store ptr %t772, ptr %t786
  call void @__inc_ref(ptr %t774)
  %t787 = getelementptr ptr, ptr %t783, i32 2
  store ptr %t774, ptr %t787
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.780
reuse.join.780:
  %t788 = phi ptr [ %t5, %reuse.in_place.778 ], [ %t783, %reuse.copy.779 ]
  %t789 = call ptr @__alloc(i64 16, i32 1)
  %t790 = inttoptr i64 109 to ptr
  %t791 = getelementptr ptr, ptr %t789, i32 0
  store ptr %t790, ptr %t791
  call void @__inc_ref(ptr %t6)
  %t792 = getelementptr ptr, ptr %t789, i32 1
  store ptr %t6, ptr %t792
  call void @__free_recursive(ptr %t6)
  store ptr %t788, ptr %t3
  store ptr %t789, ptr %t4
  br label %tco.loop.0
tco.case.arm.64.793:
  %t794 = getelementptr ptr, ptr %t5, i32 1
  %t795 = load ptr, ptr %t794
  %t796 = getelementptr ptr, ptr %t5, i32 2
  %t797 = load ptr, ptr %t796
  %t798 = getelementptr i8, ptr %t5, i64 -8
  %t799 = load i32, ptr %t798
  %t800 = icmp eq i32 %t799, 1
  br i1 %t800, label %reuse.in_place.801, label %reuse.copy.802
reuse.in_place.801:
  %t804 = inttoptr i64 53 to ptr
  %t805 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t804, ptr %t805
  br label %reuse.join.803
reuse.copy.802:
  %t806 = call ptr @__alloc(i64 24, i32 2)
  %t807 = inttoptr i64 53 to ptr
  %t808 = getelementptr ptr, ptr %t806, i32 0
  store ptr %t807, ptr %t808
  call void @__inc_ref(ptr %t795)
  %t809 = getelementptr ptr, ptr %t806, i32 1
  store ptr %t795, ptr %t809
  call void @__inc_ref(ptr %t797)
  %t810 = getelementptr ptr, ptr %t806, i32 2
  store ptr %t797, ptr %t810
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.803
reuse.join.803:
  %t811 = phi ptr [ %t5, %reuse.in_place.801 ], [ %t806, %reuse.copy.802 ]
  %t812 = call ptr @__alloc(i64 16, i32 1)
  %t813 = inttoptr i64 110 to ptr
  %t814 = getelementptr ptr, ptr %t812, i32 0
  store ptr %t813, ptr %t814
  call void @__inc_ref(ptr %t6)
  %t815 = getelementptr ptr, ptr %t812, i32 1
  store ptr %t6, ptr %t815
  call void @__free_recursive(ptr %t6)
  store ptr %t811, ptr %t3
  store ptr %t812, ptr %t4
  br label %tco.loop.0
tco.case.arm.65.816:
  %t817 = getelementptr ptr, ptr %t5, i32 1
  %t818 = load ptr, ptr %t817
  %t819 = getelementptr ptr, ptr %t5, i32 2
  %t820 = load ptr, ptr %t819
  %t821 = getelementptr i8, ptr %t5, i64 -8
  %t822 = load i32, ptr %t821
  %t823 = icmp eq i32 %t822, 1
  br i1 %t823, label %reuse.in_place.824, label %reuse.copy.825
reuse.in_place.824:
  %t827 = inttoptr i64 53 to ptr
  %t828 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t827, ptr %t828
  br label %reuse.join.826
reuse.copy.825:
  %t829 = call ptr @__alloc(i64 24, i32 2)
  %t830 = inttoptr i64 53 to ptr
  %t831 = getelementptr ptr, ptr %t829, i32 0
  store ptr %t830, ptr %t831
  call void @__inc_ref(ptr %t818)
  %t832 = getelementptr ptr, ptr %t829, i32 1
  store ptr %t818, ptr %t832
  call void @__inc_ref(ptr %t820)
  %t833 = getelementptr ptr, ptr %t829, i32 2
  store ptr %t820, ptr %t833
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.826
reuse.join.826:
  %t834 = phi ptr [ %t5, %reuse.in_place.824 ], [ %t829, %reuse.copy.825 ]
  %t835 = call ptr @__alloc(i64 16, i32 1)
  %t836 = inttoptr i64 111 to ptr
  %t837 = getelementptr ptr, ptr %t835, i32 0
  store ptr %t836, ptr %t837
  call void @__inc_ref(ptr %t6)
  %t838 = getelementptr ptr, ptr %t835, i32 1
  store ptr %t6, ptr %t838
  call void @__free_recursive(ptr %t6)
  store ptr %t834, ptr %t3
  store ptr %t835, ptr %t4
  br label %tco.loop.0
tco.case.arm.66.839:
  %t840 = getelementptr ptr, ptr %t5, i32 1
  %t841 = load ptr, ptr %t840
  %t842 = getelementptr ptr, ptr %t5, i32 2
  %t843 = load ptr, ptr %t842
  %t844 = getelementptr i8, ptr %t5, i64 -8
  %t845 = load i32, ptr %t844
  %t846 = icmp eq i32 %t845, 1
  br i1 %t846, label %reuse.in_place.847, label %reuse.copy.848
reuse.in_place.847:
  %t850 = inttoptr i64 53 to ptr
  %t851 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t850, ptr %t851
  br label %reuse.join.849
reuse.copy.848:
  %t852 = call ptr @__alloc(i64 24, i32 2)
  %t853 = inttoptr i64 53 to ptr
  %t854 = getelementptr ptr, ptr %t852, i32 0
  store ptr %t853, ptr %t854
  call void @__inc_ref(ptr %t841)
  %t855 = getelementptr ptr, ptr %t852, i32 1
  store ptr %t841, ptr %t855
  call void @__inc_ref(ptr %t843)
  %t856 = getelementptr ptr, ptr %t852, i32 2
  store ptr %t843, ptr %t856
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.849
reuse.join.849:
  %t857 = phi ptr [ %t5, %reuse.in_place.847 ], [ %t852, %reuse.copy.848 ]
  %t858 = call ptr @__alloc(i64 16, i32 1)
  %t859 = inttoptr i64 112 to ptr
  %t860 = getelementptr ptr, ptr %t858, i32 0
  store ptr %t859, ptr %t860
  call void @__inc_ref(ptr %t6)
  %t861 = getelementptr ptr, ptr %t858, i32 1
  store ptr %t6, ptr %t861
  call void @__free_recursive(ptr %t6)
  store ptr %t857, ptr %t3
  store ptr %t858, ptr %t4
  br label %tco.loop.0
tco.case.arm.67.862:
  %t863 = getelementptr ptr, ptr %t5, i32 1
  %t864 = load ptr, ptr %t863
  %t865 = getelementptr ptr, ptr %t5, i32 2
  %t866 = load ptr, ptr %t865
  %t867 = getelementptr i8, ptr %t5, i64 -8
  %t868 = load i32, ptr %t867
  %t869 = icmp eq i32 %t868, 1
  br i1 %t869, label %reuse.in_place.870, label %reuse.copy.871
reuse.in_place.870:
  %t873 = inttoptr i64 53 to ptr
  %t874 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t873, ptr %t874
  br label %reuse.join.872
reuse.copy.871:
  %t875 = call ptr @__alloc(i64 24, i32 2)
  %t876 = inttoptr i64 53 to ptr
  %t877 = getelementptr ptr, ptr %t875, i32 0
  store ptr %t876, ptr %t877
  call void @__inc_ref(ptr %t864)
  %t878 = getelementptr ptr, ptr %t875, i32 1
  store ptr %t864, ptr %t878
  call void @__inc_ref(ptr %t866)
  %t879 = getelementptr ptr, ptr %t875, i32 2
  store ptr %t866, ptr %t879
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.872
reuse.join.872:
  %t880 = phi ptr [ %t5, %reuse.in_place.870 ], [ %t875, %reuse.copy.871 ]
  %t881 = call ptr @__alloc(i64 16, i32 1)
  %t882 = inttoptr i64 113 to ptr
  %t883 = getelementptr ptr, ptr %t881, i32 0
  store ptr %t882, ptr %t883
  call void @__inc_ref(ptr %t6)
  %t884 = getelementptr ptr, ptr %t881, i32 1
  store ptr %t6, ptr %t884
  call void @__free_recursive(ptr %t6)
  store ptr %t880, ptr %t3
  store ptr %t881, ptr %t4
  br label %tco.loop.0
tco.case.arm.68.885:
  %t886 = getelementptr ptr, ptr %t5, i32 1
  %t887 = load ptr, ptr %t886
  %t888 = getelementptr ptr, ptr %t5, i32 2
  %t889 = load ptr, ptr %t888
  %t890 = getelementptr i8, ptr %t5, i64 -8
  %t891 = load i32, ptr %t890
  %t892 = icmp eq i32 %t891, 1
  br i1 %t892, label %reuse.in_place.893, label %reuse.copy.894
reuse.in_place.893:
  %t896 = inttoptr i64 53 to ptr
  %t897 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t896, ptr %t897
  br label %reuse.join.895
reuse.copy.894:
  %t898 = call ptr @__alloc(i64 24, i32 2)
  %t899 = inttoptr i64 53 to ptr
  %t900 = getelementptr ptr, ptr %t898, i32 0
  store ptr %t899, ptr %t900
  call void @__inc_ref(ptr %t887)
  %t901 = getelementptr ptr, ptr %t898, i32 1
  store ptr %t887, ptr %t901
  call void @__inc_ref(ptr %t889)
  %t902 = getelementptr ptr, ptr %t898, i32 2
  store ptr %t889, ptr %t902
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.895
reuse.join.895:
  %t903 = phi ptr [ %t5, %reuse.in_place.893 ], [ %t898, %reuse.copy.894 ]
  %t904 = call ptr @__alloc(i64 16, i32 1)
  %t905 = inttoptr i64 114 to ptr
  %t906 = getelementptr ptr, ptr %t904, i32 0
  store ptr %t905, ptr %t906
  call void @__inc_ref(ptr %t6)
  %t907 = getelementptr ptr, ptr %t904, i32 1
  store ptr %t6, ptr %t907
  call void @__free_recursive(ptr %t6)
  store ptr %t903, ptr %t3
  store ptr %t904, ptr %t4
  br label %tco.loop.0
tco.case.arm.69.908:
  %t909 = getelementptr ptr, ptr %t5, i32 1
  %t910 = load ptr, ptr %t909
  %t911 = getelementptr ptr, ptr %t5, i32 2
  %t912 = load ptr, ptr %t911
  %t913 = getelementptr i8, ptr %t5, i64 -8
  %t914 = load i32, ptr %t913
  %t915 = icmp eq i32 %t914, 1
  br i1 %t915, label %reuse.in_place.916, label %reuse.copy.917
reuse.in_place.916:
  %t919 = inttoptr i64 53 to ptr
  %t920 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t919, ptr %t920
  br label %reuse.join.918
reuse.copy.917:
  %t921 = call ptr @__alloc(i64 24, i32 2)
  %t922 = inttoptr i64 53 to ptr
  %t923 = getelementptr ptr, ptr %t921, i32 0
  store ptr %t922, ptr %t923
  call void @__inc_ref(ptr %t910)
  %t924 = getelementptr ptr, ptr %t921, i32 1
  store ptr %t910, ptr %t924
  call void @__inc_ref(ptr %t912)
  %t925 = getelementptr ptr, ptr %t921, i32 2
  store ptr %t912, ptr %t925
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.918
reuse.join.918:
  %t926 = phi ptr [ %t5, %reuse.in_place.916 ], [ %t921, %reuse.copy.917 ]
  %t927 = call ptr @__alloc(i64 16, i32 1)
  %t928 = inttoptr i64 115 to ptr
  %t929 = getelementptr ptr, ptr %t927, i32 0
  store ptr %t928, ptr %t929
  call void @__inc_ref(ptr %t6)
  %t930 = getelementptr ptr, ptr %t927, i32 1
  store ptr %t6, ptr %t930
  call void @__free_recursive(ptr %t6)
  store ptr %t926, ptr %t3
  store ptr %t927, ptr %t4
  br label %tco.loop.0
tco.case.arm.70.931:
  %t932 = getelementptr ptr, ptr %t5, i32 1
  %t933 = load ptr, ptr %t932
  %t934 = getelementptr ptr, ptr %t5, i32 2
  %t935 = load ptr, ptr %t934
  %t936 = getelementptr i8, ptr %t5, i64 -8
  %t937 = load i32, ptr %t936
  %t938 = icmp eq i32 %t937, 1
  br i1 %t938, label %reuse.in_place.939, label %reuse.copy.940
reuse.in_place.939:
  %t942 = inttoptr i64 53 to ptr
  %t943 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t942, ptr %t943
  br label %reuse.join.941
reuse.copy.940:
  %t944 = call ptr @__alloc(i64 24, i32 2)
  %t945 = inttoptr i64 53 to ptr
  %t946 = getelementptr ptr, ptr %t944, i32 0
  store ptr %t945, ptr %t946
  call void @__inc_ref(ptr %t933)
  %t947 = getelementptr ptr, ptr %t944, i32 1
  store ptr %t933, ptr %t947
  call void @__inc_ref(ptr %t935)
  %t948 = getelementptr ptr, ptr %t944, i32 2
  store ptr %t935, ptr %t948
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.941
reuse.join.941:
  %t949 = phi ptr [ %t5, %reuse.in_place.939 ], [ %t944, %reuse.copy.940 ]
  %t950 = call ptr @__alloc(i64 16, i32 1)
  %t951 = inttoptr i64 116 to ptr
  %t952 = getelementptr ptr, ptr %t950, i32 0
  store ptr %t951, ptr %t952
  call void @__inc_ref(ptr %t6)
  %t953 = getelementptr ptr, ptr %t950, i32 1
  store ptr %t6, ptr %t953
  call void @__free_recursive(ptr %t6)
  store ptr %t949, ptr %t3
  store ptr %t950, ptr %t4
  br label %tco.loop.0
tco.case.arm.71.954:
  %t955 = getelementptr ptr, ptr %t5, i32 1
  %t956 = load ptr, ptr %t955
  %t957 = getelementptr ptr, ptr %t5, i32 2
  %t958 = load ptr, ptr %t957
  %t959 = getelementptr i8, ptr %t5, i64 -8
  %t960 = load i32, ptr %t959
  %t961 = icmp eq i32 %t960, 1
  br i1 %t961, label %reuse.in_place.962, label %reuse.copy.963
reuse.in_place.962:
  %t965 = inttoptr i64 53 to ptr
  %t966 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t965, ptr %t966
  br label %reuse.join.964
reuse.copy.963:
  %t967 = call ptr @__alloc(i64 24, i32 2)
  %t968 = inttoptr i64 53 to ptr
  %t969 = getelementptr ptr, ptr %t967, i32 0
  store ptr %t968, ptr %t969
  call void @__inc_ref(ptr %t956)
  %t970 = getelementptr ptr, ptr %t967, i32 1
  store ptr %t956, ptr %t970
  call void @__inc_ref(ptr %t958)
  %t971 = getelementptr ptr, ptr %t967, i32 2
  store ptr %t958, ptr %t971
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.964
reuse.join.964:
  %t972 = phi ptr [ %t5, %reuse.in_place.962 ], [ %t967, %reuse.copy.963 ]
  %t973 = call ptr @__alloc(i64 16, i32 1)
  %t974 = inttoptr i64 117 to ptr
  %t975 = getelementptr ptr, ptr %t973, i32 0
  store ptr %t974, ptr %t975
  call void @__inc_ref(ptr %t6)
  %t976 = getelementptr ptr, ptr %t973, i32 1
  store ptr %t6, ptr %t976
  call void @__free_recursive(ptr %t6)
  store ptr %t972, ptr %t3
  store ptr %t973, ptr %t4
  br label %tco.loop.0
tco.case.arm.72.977:
  %t978 = getelementptr ptr, ptr %t5, i32 1
  %t979 = load ptr, ptr %t978
  %t980 = getelementptr ptr, ptr %t5, i32 2
  %t981 = load ptr, ptr %t980
  %t982 = getelementptr i8, ptr %t5, i64 -8
  %t983 = load i32, ptr %t982
  %t984 = icmp eq i32 %t983, 1
  br i1 %t984, label %reuse.in_place.985, label %reuse.copy.986
reuse.in_place.985:
  %t988 = inttoptr i64 53 to ptr
  %t989 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t988, ptr %t989
  br label %reuse.join.987
reuse.copy.986:
  %t990 = call ptr @__alloc(i64 24, i32 2)
  %t991 = inttoptr i64 53 to ptr
  %t992 = getelementptr ptr, ptr %t990, i32 0
  store ptr %t991, ptr %t992
  call void @__inc_ref(ptr %t979)
  %t993 = getelementptr ptr, ptr %t990, i32 1
  store ptr %t979, ptr %t993
  call void @__inc_ref(ptr %t981)
  %t994 = getelementptr ptr, ptr %t990, i32 2
  store ptr %t981, ptr %t994
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.987
reuse.join.987:
  %t995 = phi ptr [ %t5, %reuse.in_place.985 ], [ %t990, %reuse.copy.986 ]
  %t996 = call ptr @__alloc(i64 16, i32 1)
  %t997 = inttoptr i64 118 to ptr
  %t998 = getelementptr ptr, ptr %t996, i32 0
  store ptr %t997, ptr %t998
  call void @__inc_ref(ptr %t6)
  %t999 = getelementptr ptr, ptr %t996, i32 1
  store ptr %t6, ptr %t999
  call void @__free_recursive(ptr %t6)
  store ptr %t995, ptr %t3
  store ptr %t996, ptr %t4
  br label %tco.loop.0
tco.case.arm.73.1000:
  %t1001 = getelementptr ptr, ptr %t5, i32 1
  %t1002 = load ptr, ptr %t1001
  %t1003 = getelementptr ptr, ptr %t5, i32 2
  %t1004 = load ptr, ptr %t1003
  %t1005 = getelementptr i8, ptr %t5, i64 -8
  %t1006 = load i32, ptr %t1005
  %t1007 = icmp eq i32 %t1006, 1
  br i1 %t1007, label %reuse.in_place.1008, label %reuse.copy.1009
reuse.in_place.1008:
  %t1011 = inttoptr i64 53 to ptr
  %t1012 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1011, ptr %t1012
  br label %reuse.join.1010
reuse.copy.1009:
  %t1013 = call ptr @__alloc(i64 24, i32 2)
  %t1014 = inttoptr i64 53 to ptr
  %t1015 = getelementptr ptr, ptr %t1013, i32 0
  store ptr %t1014, ptr %t1015
  call void @__inc_ref(ptr %t1002)
  %t1016 = getelementptr ptr, ptr %t1013, i32 1
  store ptr %t1002, ptr %t1016
  call void @__inc_ref(ptr %t1004)
  %t1017 = getelementptr ptr, ptr %t1013, i32 2
  store ptr %t1004, ptr %t1017
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1010
reuse.join.1010:
  %t1018 = phi ptr [ %t5, %reuse.in_place.1008 ], [ %t1013, %reuse.copy.1009 ]
  %t1019 = call ptr @__alloc(i64 16, i32 1)
  %t1020 = inttoptr i64 119 to ptr
  %t1021 = getelementptr ptr, ptr %t1019, i32 0
  store ptr %t1020, ptr %t1021
  call void @__inc_ref(ptr %t6)
  %t1022 = getelementptr ptr, ptr %t1019, i32 1
  store ptr %t6, ptr %t1022
  call void @__free_recursive(ptr %t6)
  store ptr %t1018, ptr %t3
  store ptr %t1019, ptr %t4
  br label %tco.loop.0
tco.case.arm.74.1023:
  %t1024 = getelementptr ptr, ptr %t5, i32 1
  %t1025 = load ptr, ptr %t1024
  %t1026 = getelementptr ptr, ptr %t5, i32 2
  %t1027 = load ptr, ptr %t1026
  %t1028 = getelementptr i8, ptr %t5, i64 -8
  %t1029 = load i32, ptr %t1028
  %t1030 = icmp eq i32 %t1029, 1
  br i1 %t1030, label %reuse.in_place.1031, label %reuse.copy.1032
reuse.in_place.1031:
  %t1034 = inttoptr i64 53 to ptr
  %t1035 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1034, ptr %t1035
  br label %reuse.join.1033
reuse.copy.1032:
  %t1036 = call ptr @__alloc(i64 24, i32 2)
  %t1037 = inttoptr i64 53 to ptr
  %t1038 = getelementptr ptr, ptr %t1036, i32 0
  store ptr %t1037, ptr %t1038
  call void @__inc_ref(ptr %t1025)
  %t1039 = getelementptr ptr, ptr %t1036, i32 1
  store ptr %t1025, ptr %t1039
  call void @__inc_ref(ptr %t1027)
  %t1040 = getelementptr ptr, ptr %t1036, i32 2
  store ptr %t1027, ptr %t1040
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1033
reuse.join.1033:
  %t1041 = phi ptr [ %t5, %reuse.in_place.1031 ], [ %t1036, %reuse.copy.1032 ]
  %t1042 = call ptr @__alloc(i64 16, i32 1)
  %t1043 = inttoptr i64 120 to ptr
  %t1044 = getelementptr ptr, ptr %t1042, i32 0
  store ptr %t1043, ptr %t1044
  call void @__inc_ref(ptr %t6)
  %t1045 = getelementptr ptr, ptr %t1042, i32 1
  store ptr %t6, ptr %t1045
  call void @__free_recursive(ptr %t6)
  store ptr %t1041, ptr %t3
  store ptr %t1042, ptr %t4
  br label %tco.loop.0
tco.case.arm.75.1046:
  %t1047 = getelementptr ptr, ptr %t5, i32 1
  %t1048 = load ptr, ptr %t1047
  %t1049 = getelementptr ptr, ptr %t5, i32 2
  %t1050 = load ptr, ptr %t1049
  %t1051 = getelementptr i8, ptr %t5, i64 -8
  %t1052 = load i32, ptr %t1051
  %t1053 = icmp eq i32 %t1052, 1
  br i1 %t1053, label %reuse.in_place.1054, label %reuse.copy.1055
reuse.in_place.1054:
  %t1057 = inttoptr i64 53 to ptr
  %t1058 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1057, ptr %t1058
  br label %reuse.join.1056
reuse.copy.1055:
  %t1059 = call ptr @__alloc(i64 24, i32 2)
  %t1060 = inttoptr i64 53 to ptr
  %t1061 = getelementptr ptr, ptr %t1059, i32 0
  store ptr %t1060, ptr %t1061
  call void @__inc_ref(ptr %t1048)
  %t1062 = getelementptr ptr, ptr %t1059, i32 1
  store ptr %t1048, ptr %t1062
  call void @__inc_ref(ptr %t1050)
  %t1063 = getelementptr ptr, ptr %t1059, i32 2
  store ptr %t1050, ptr %t1063
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1056
reuse.join.1056:
  %t1064 = phi ptr [ %t5, %reuse.in_place.1054 ], [ %t1059, %reuse.copy.1055 ]
  %t1065 = call ptr @__alloc(i64 16, i32 1)
  %t1066 = inttoptr i64 121 to ptr
  %t1067 = getelementptr ptr, ptr %t1065, i32 0
  store ptr %t1066, ptr %t1067
  call void @__inc_ref(ptr %t6)
  %t1068 = getelementptr ptr, ptr %t1065, i32 1
  store ptr %t6, ptr %t1068
  call void @__free_recursive(ptr %t6)
  store ptr %t1064, ptr %t3
  store ptr %t1065, ptr %t4
  br label %tco.loop.0
tco.case.arm.76.1069:
  %t1070 = getelementptr ptr, ptr %t5, i32 1
  %t1071 = load ptr, ptr %t1070
  %t1072 = getelementptr ptr, ptr %t5, i32 2
  %t1073 = load ptr, ptr %t1072
  %t1074 = getelementptr i8, ptr %t5, i64 -8
  %t1075 = load i32, ptr %t1074
  %t1076 = icmp eq i32 %t1075, 1
  br i1 %t1076, label %reuse.in_place.1077, label %reuse.copy.1078
reuse.in_place.1077:
  %t1080 = inttoptr i64 53 to ptr
  %t1081 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1080, ptr %t1081
  br label %reuse.join.1079
reuse.copy.1078:
  %t1082 = call ptr @__alloc(i64 24, i32 2)
  %t1083 = inttoptr i64 53 to ptr
  %t1084 = getelementptr ptr, ptr %t1082, i32 0
  store ptr %t1083, ptr %t1084
  call void @__inc_ref(ptr %t1071)
  %t1085 = getelementptr ptr, ptr %t1082, i32 1
  store ptr %t1071, ptr %t1085
  call void @__inc_ref(ptr %t1073)
  %t1086 = getelementptr ptr, ptr %t1082, i32 2
  store ptr %t1073, ptr %t1086
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1079
reuse.join.1079:
  %t1087 = phi ptr [ %t5, %reuse.in_place.1077 ], [ %t1082, %reuse.copy.1078 ]
  %t1088 = call ptr @__alloc(i64 16, i32 1)
  %t1089 = inttoptr i64 122 to ptr
  %t1090 = getelementptr ptr, ptr %t1088, i32 0
  store ptr %t1089, ptr %t1090
  call void @__inc_ref(ptr %t6)
  %t1091 = getelementptr ptr, ptr %t1088, i32 1
  store ptr %t6, ptr %t1091
  call void @__free_recursive(ptr %t6)
  store ptr %t1087, ptr %t3
  store ptr %t1088, ptr %t4
  br label %tco.loop.0
tco.case.arm.77.1092:
  %t1093 = getelementptr ptr, ptr %t5, i32 1
  %t1094 = load ptr, ptr %t1093
  %t1095 = getelementptr ptr, ptr %t5, i32 2
  %t1096 = load ptr, ptr %t1095
  %t1097 = getelementptr i8, ptr %t5, i64 -8
  %t1098 = load i32, ptr %t1097
  %t1099 = icmp eq i32 %t1098, 1
  br i1 %t1099, label %reuse.in_place.1100, label %reuse.copy.1101
reuse.in_place.1100:
  %t1103 = inttoptr i64 53 to ptr
  %t1104 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1103, ptr %t1104
  br label %reuse.join.1102
reuse.copy.1101:
  %t1105 = call ptr @__alloc(i64 24, i32 2)
  %t1106 = inttoptr i64 53 to ptr
  %t1107 = getelementptr ptr, ptr %t1105, i32 0
  store ptr %t1106, ptr %t1107
  call void @__inc_ref(ptr %t1094)
  %t1108 = getelementptr ptr, ptr %t1105, i32 1
  store ptr %t1094, ptr %t1108
  call void @__inc_ref(ptr %t1096)
  %t1109 = getelementptr ptr, ptr %t1105, i32 2
  store ptr %t1096, ptr %t1109
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1102
reuse.join.1102:
  %t1110 = phi ptr [ %t5, %reuse.in_place.1100 ], [ %t1105, %reuse.copy.1101 ]
  %t1111 = call ptr @__alloc(i64 16, i32 1)
  %t1112 = inttoptr i64 123 to ptr
  %t1113 = getelementptr ptr, ptr %t1111, i32 0
  store ptr %t1112, ptr %t1113
  call void @__inc_ref(ptr %t6)
  %t1114 = getelementptr ptr, ptr %t1111, i32 1
  store ptr %t6, ptr %t1114
  call void @__free_recursive(ptr %t6)
  store ptr %t1110, ptr %t3
  store ptr %t1111, ptr %t4
  br label %tco.loop.0
tco.case.arm.78.1115:
  %t1116 = getelementptr ptr, ptr %t5, i32 1
  %t1117 = load ptr, ptr %t1116
  %t1118 = getelementptr ptr, ptr %t5, i32 2
  %t1119 = load ptr, ptr %t1118
  %t1120 = getelementptr i8, ptr %t5, i64 -8
  %t1121 = load i32, ptr %t1120
  %t1122 = icmp eq i32 %t1121, 1
  br i1 %t1122, label %reuse.in_place.1123, label %reuse.copy.1124
reuse.in_place.1123:
  %t1126 = inttoptr i64 53 to ptr
  %t1127 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1126, ptr %t1127
  br label %reuse.join.1125
reuse.copy.1124:
  %t1128 = call ptr @__alloc(i64 24, i32 2)
  %t1129 = inttoptr i64 53 to ptr
  %t1130 = getelementptr ptr, ptr %t1128, i32 0
  store ptr %t1129, ptr %t1130
  call void @__inc_ref(ptr %t1117)
  %t1131 = getelementptr ptr, ptr %t1128, i32 1
  store ptr %t1117, ptr %t1131
  call void @__inc_ref(ptr %t1119)
  %t1132 = getelementptr ptr, ptr %t1128, i32 2
  store ptr %t1119, ptr %t1132
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1125
reuse.join.1125:
  %t1133 = phi ptr [ %t5, %reuse.in_place.1123 ], [ %t1128, %reuse.copy.1124 ]
  %t1134 = call ptr @__alloc(i64 16, i32 1)
  %t1135 = inttoptr i64 124 to ptr
  %t1136 = getelementptr ptr, ptr %t1134, i32 0
  store ptr %t1135, ptr %t1136
  call void @__inc_ref(ptr %t6)
  %t1137 = getelementptr ptr, ptr %t1134, i32 1
  store ptr %t6, ptr %t1137
  call void @__free_recursive(ptr %t6)
  store ptr %t1133, ptr %t3
  store ptr %t1134, ptr %t4
  br label %tco.loop.0
tco.case.arm.79.1138:
  %t1139 = getelementptr ptr, ptr %t5, i32 1
  %t1140 = load ptr, ptr %t1139
  %t1141 = getelementptr ptr, ptr %t5, i32 2
  %t1142 = load ptr, ptr %t1141
  %t1143 = getelementptr i8, ptr %t5, i64 -8
  %t1144 = load i32, ptr %t1143
  %t1145 = icmp eq i32 %t1144, 1
  br i1 %t1145, label %reuse.in_place.1146, label %reuse.copy.1147
reuse.in_place.1146:
  %t1149 = inttoptr i64 53 to ptr
  %t1150 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1149, ptr %t1150
  br label %reuse.join.1148
reuse.copy.1147:
  %t1151 = call ptr @__alloc(i64 24, i32 2)
  %t1152 = inttoptr i64 53 to ptr
  %t1153 = getelementptr ptr, ptr %t1151, i32 0
  store ptr %t1152, ptr %t1153
  call void @__inc_ref(ptr %t1140)
  %t1154 = getelementptr ptr, ptr %t1151, i32 1
  store ptr %t1140, ptr %t1154
  call void @__inc_ref(ptr %t1142)
  %t1155 = getelementptr ptr, ptr %t1151, i32 2
  store ptr %t1142, ptr %t1155
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1148
reuse.join.1148:
  %t1156 = phi ptr [ %t5, %reuse.in_place.1146 ], [ %t1151, %reuse.copy.1147 ]
  %t1157 = call ptr @__alloc(i64 16, i32 1)
  %t1158 = inttoptr i64 125 to ptr
  %t1159 = getelementptr ptr, ptr %t1157, i32 0
  store ptr %t1158, ptr %t1159
  call void @__inc_ref(ptr %t6)
  %t1160 = getelementptr ptr, ptr %t1157, i32 1
  store ptr %t6, ptr %t1160
  call void @__free_recursive(ptr %t6)
  store ptr %t1156, ptr %t3
  store ptr %t1157, ptr %t4
  br label %tco.loop.0
tco.case.arm.80.1161:
  %t1162 = getelementptr ptr, ptr %t5, i32 1
  %t1163 = load ptr, ptr %t1162
  %t1164 = getelementptr ptr, ptr %t5, i32 2
  %t1165 = load ptr, ptr %t1164
  %t1166 = getelementptr i8, ptr %t5, i64 -8
  %t1167 = load i32, ptr %t1166
  %t1168 = icmp eq i32 %t1167, 1
  br i1 %t1168, label %reuse.in_place.1169, label %reuse.copy.1170
reuse.in_place.1169:
  %t1172 = inttoptr i64 53 to ptr
  %t1173 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1172, ptr %t1173
  br label %reuse.join.1171
reuse.copy.1170:
  %t1174 = call ptr @__alloc(i64 24, i32 2)
  %t1175 = inttoptr i64 53 to ptr
  %t1176 = getelementptr ptr, ptr %t1174, i32 0
  store ptr %t1175, ptr %t1176
  call void @__inc_ref(ptr %t1163)
  %t1177 = getelementptr ptr, ptr %t1174, i32 1
  store ptr %t1163, ptr %t1177
  call void @__inc_ref(ptr %t1165)
  %t1178 = getelementptr ptr, ptr %t1174, i32 2
  store ptr %t1165, ptr %t1178
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1171
reuse.join.1171:
  %t1179 = phi ptr [ %t5, %reuse.in_place.1169 ], [ %t1174, %reuse.copy.1170 ]
  %t1180 = call ptr @__alloc(i64 16, i32 1)
  %t1181 = inttoptr i64 126 to ptr
  %t1182 = getelementptr ptr, ptr %t1180, i32 0
  store ptr %t1181, ptr %t1182
  call void @__inc_ref(ptr %t6)
  %t1183 = getelementptr ptr, ptr %t1180, i32 1
  store ptr %t6, ptr %t1183
  call void @__free_recursive(ptr %t6)
  store ptr %t1179, ptr %t3
  store ptr %t1180, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t1184 = load ptr, ptr %t2
  ret ptr %t1184
}

define internal ptr @v__apply__scc__apply1__df__lam_14_1__df__lam_15_2__df__lam_16_3__df__lam_32_5__df__lam_33_6__df__lam_34_7__df__lam_40_9__df__lam_41_14__df__lam_42_15__df__lam_5_11__df__lam_6_12__df__lam_7_13__lift_18__lift_19__lift_2__lift_20__lift_25__lift_26__lift_27__lift_29__lift_3__lift_30__lift_31__lift_37__lift_38__lift_39__lift_4(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 99, label %tco.case.arm.99.11 i64 100, label %tco.case.arm.100.12 i64 101, label %tco.case.arm.101.16 i64 102, label %tco.case.arm.102.20 i64 103, label %tco.case.arm.103.24 i64 104, label %tco.case.arm.104.29 i64 105, label %tco.case.arm.105.34 i64 106, label %tco.case.arm.106.39 i64 107, label %tco.case.arm.107.44 i64 108, label %tco.case.arm.108.49 i64 109, label %tco.case.arm.109.54 i64 110, label %tco.case.arm.110.58 i64 111, label %tco.case.arm.111.62 i64 112, label %tco.case.arm.112.66 i64 113, label %tco.case.arm.113.70 i64 114, label %tco.case.arm.114.74 i64 115, label %tco.case.arm.115.78 i64 116, label %tco.case.arm.116.82 i64 117, label %tco.case.arm.117.86 i64 118, label %tco.case.arm.118.90 i64 119, label %tco.case.arm.119.94 i64 120, label %tco.case.arm.120.98 i64 121, label %tco.case.arm.121.102 i64 122, label %tco.case.arm.122.106 i64 123, label %tco.case.arm.123.110 i64 124, label %tco.case.arm.124.114 i64 125, label %tco.case.arm.125.118 i64 126, label %tco.case.arm.126.122 ]
tco.case.arm.99.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.100.12:
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
tco.case.arm.101.16:
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
tco.case.arm.102.20:
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
tco.case.arm.103.24:
  %t25 = getelementptr ptr, ptr %t5, i32 1
  %t26 = load ptr, ptr %t25
  call void @__inc_ref(ptr %t26)
  call void @__inc_ref(ptr %t6)
  %t27 = call ptr @v__lift_28(ptr %t6)
  %t28 = call ptr @v__df__rowspec_23_4(ptr %t27)
  call void @__inc_ref(ptr %t26)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t26)
  store ptr %t26, ptr %t3
  store ptr %t28, ptr %t4
  br label %tco.loop.0
tco.case.arm.104.29:
  %t30 = getelementptr ptr, ptr %t5, i32 1
  %t31 = load ptr, ptr %t30
  call void @__inc_ref(ptr %t31)
  call void @__inc_ref(ptr %t6)
  %t32 = call ptr @v__lift_28(ptr %t6)
  %t33 = call ptr @v__df__rowspec_23_4(ptr %t32)
  call void @__inc_ref(ptr %t31)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t31)
  store ptr %t31, ptr %t3
  store ptr %t33, ptr %t4
  br label %tco.loop.0
tco.case.arm.105.34:
  %t35 = getelementptr ptr, ptr %t5, i32 1
  %t36 = load ptr, ptr %t35
  call void @__inc_ref(ptr %t36)
  call void @__inc_ref(ptr %t6)
  %t37 = call ptr @v__lift_28(ptr %t6)
  %t38 = call ptr @v__df__rowspec_23_4(ptr %t37)
  call void @__inc_ref(ptr %t36)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t36)
  store ptr %t36, ptr %t3
  store ptr %t38, ptr %t4
  br label %tco.loop.0
tco.case.arm.106.39:
  %t40 = getelementptr ptr, ptr %t5, i32 1
  %t41 = load ptr, ptr %t40
  call void @__inc_ref(ptr %t41)
  call void @__inc_ref(ptr %t6)
  %t42 = call ptr @v__lift_36(ptr %t6)
  %t43 = call ptr @v__df_andThenIO_10(ptr %t42)
  call void @__inc_ref(ptr %t41)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t41)
  store ptr %t41, ptr %t3
  store ptr %t43, ptr %t4
  br label %tco.loop.0
tco.case.arm.107.44:
  %t45 = getelementptr ptr, ptr %t5, i32 1
  %t46 = load ptr, ptr %t45
  call void @__inc_ref(ptr %t46)
  call void @__inc_ref(ptr %t6)
  %t47 = call ptr @v__lift_36(ptr %t6)
  %t48 = call ptr @v__df_andThenIO_10(ptr %t47)
  call void @__inc_ref(ptr %t46)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t46)
  store ptr %t46, ptr %t3
  store ptr %t48, ptr %t4
  br label %tco.loop.0
tco.case.arm.108.49:
  %t50 = getelementptr ptr, ptr %t5, i32 1
  %t51 = load ptr, ptr %t50
  call void @__inc_ref(ptr %t51)
  call void @__inc_ref(ptr %t6)
  %t52 = call ptr @v__lift_36(ptr %t6)
  %t53 = call ptr @v__df_andThenIO_10(ptr %t52)
  call void @__inc_ref(ptr %t51)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t51)
  store ptr %t51, ptr %t3
  store ptr %t53, ptr %t4
  br label %tco.loop.0
tco.case.arm.109.54:
  %t55 = getelementptr ptr, ptr %t5, i32 1
  %t56 = load ptr, ptr %t55
  call void @__inc_ref(ptr %t56)
  call void @__inc_ref(ptr %t6)
  %t57 = call ptr @v__df_andThenIO_10(ptr %t6)
  call void @__inc_ref(ptr %t56)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t56)
  store ptr %t56, ptr %t3
  store ptr %t57, ptr %t4
  br label %tco.loop.0
tco.case.arm.110.58:
  %t59 = getelementptr ptr, ptr %t5, i32 1
  %t60 = load ptr, ptr %t59
  call void @__inc_ref(ptr %t60)
  call void @__inc_ref(ptr %t6)
  %t61 = call ptr @v__df_andThenIO_10(ptr %t6)
  call void @__inc_ref(ptr %t60)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t60)
  store ptr %t60, ptr %t3
  store ptr %t61, ptr %t4
  br label %tco.loop.0
tco.case.arm.111.62:
  %t63 = getelementptr ptr, ptr %t5, i32 1
  %t64 = load ptr, ptr %t63
  call void @__inc_ref(ptr %t64)
  call void @__inc_ref(ptr %t6)
  %t65 = call ptr @v__df_andThenIO_10(ptr %t6)
  call void @__inc_ref(ptr %t64)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t64)
  store ptr %t64, ptr %t3
  store ptr %t65, ptr %t4
  br label %tco.loop.0
tco.case.arm.112.66:
  %t67 = getelementptr ptr, ptr %t5, i32 1
  %t68 = load ptr, ptr %t67
  call void @__inc_ref(ptr %t68)
  call void @__inc_ref(ptr %t6)
  %t69 = call ptr @v__lift_17(ptr %t6)
  call void @__inc_ref(ptr %t68)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t68)
  store ptr %t68, ptr %t3
  store ptr %t69, ptr %t4
  br label %tco.loop.0
tco.case.arm.113.70:
  %t71 = getelementptr ptr, ptr %t5, i32 1
  %t72 = load ptr, ptr %t71
  call void @__inc_ref(ptr %t72)
  call void @__inc_ref(ptr %t6)
  %t73 = call ptr @v__lift_17(ptr %t6)
  call void @__inc_ref(ptr %t72)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t72)
  store ptr %t72, ptr %t3
  store ptr %t73, ptr %t4
  br label %tco.loop.0
tco.case.arm.114.74:
  %t75 = getelementptr ptr, ptr %t5, i32 1
  %t76 = load ptr, ptr %t75
  call void @__inc_ref(ptr %t76)
  call void @__inc_ref(ptr %t6)
  %t77 = call ptr @v__lift_1(ptr %t6)
  call void @__inc_ref(ptr %t76)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t76)
  store ptr %t76, ptr %t3
  store ptr %t77, ptr %t4
  br label %tco.loop.0
tco.case.arm.115.78:
  %t79 = getelementptr ptr, ptr %t5, i32 1
  %t80 = load ptr, ptr %t79
  call void @__inc_ref(ptr %t80)
  call void @__inc_ref(ptr %t6)
  %t81 = call ptr @v__lift_17(ptr %t6)
  call void @__inc_ref(ptr %t80)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t80)
  store ptr %t80, ptr %t3
  store ptr %t81, ptr %t4
  br label %tco.loop.0
tco.case.arm.116.82:
  %t83 = getelementptr ptr, ptr %t5, i32 1
  %t84 = load ptr, ptr %t83
  call void @__inc_ref(ptr %t84)
  call void @__inc_ref(ptr %t6)
  %t85 = call ptr @v__lift_24(ptr %t6)
  call void @__inc_ref(ptr %t84)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t84)
  store ptr %t84, ptr %t3
  store ptr %t85, ptr %t4
  br label %tco.loop.0
tco.case.arm.117.86:
  %t87 = getelementptr ptr, ptr %t5, i32 1
  %t88 = load ptr, ptr %t87
  call void @__inc_ref(ptr %t88)
  call void @__inc_ref(ptr %t6)
  %t89 = call ptr @v__lift_24(ptr %t6)
  call void @__inc_ref(ptr %t88)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t88)
  store ptr %t88, ptr %t3
  store ptr %t89, ptr %t4
  br label %tco.loop.0
tco.case.arm.118.90:
  %t91 = getelementptr ptr, ptr %t5, i32 1
  %t92 = load ptr, ptr %t91
  call void @__inc_ref(ptr %t92)
  call void @__inc_ref(ptr %t6)
  %t93 = call ptr @v__lift_24(ptr %t6)
  call void @__inc_ref(ptr %t92)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t92)
  store ptr %t92, ptr %t3
  store ptr %t93, ptr %t4
  br label %tco.loop.0
tco.case.arm.119.94:
  %t95 = getelementptr ptr, ptr %t5, i32 1
  %t96 = load ptr, ptr %t95
  call void @__inc_ref(ptr %t96)
  call void @__inc_ref(ptr %t6)
  %t97 = call ptr @v__lift_28(ptr %t6)
  call void @__inc_ref(ptr %t96)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t96)
  store ptr %t96, ptr %t3
  store ptr %t97, ptr %t4
  br label %tco.loop.0
tco.case.arm.120.98:
  %t99 = getelementptr ptr, ptr %t5, i32 1
  %t100 = load ptr, ptr %t99
  call void @__inc_ref(ptr %t100)
  call void @__inc_ref(ptr %t6)
  %t101 = call ptr @v__lift_1(ptr %t6)
  call void @__inc_ref(ptr %t100)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t100)
  store ptr %t100, ptr %t3
  store ptr %t101, ptr %t4
  br label %tco.loop.0
tco.case.arm.121.102:
  %t103 = getelementptr ptr, ptr %t5, i32 1
  %t104 = load ptr, ptr %t103
  call void @__inc_ref(ptr %t104)
  call void @__inc_ref(ptr %t6)
  %t105 = call ptr @v__lift_28(ptr %t6)
  call void @__inc_ref(ptr %t104)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t104)
  store ptr %t104, ptr %t3
  store ptr %t105, ptr %t4
  br label %tco.loop.0
tco.case.arm.122.106:
  %t107 = getelementptr ptr, ptr %t5, i32 1
  %t108 = load ptr, ptr %t107
  call void @__inc_ref(ptr %t108)
  call void @__inc_ref(ptr %t6)
  %t109 = call ptr @v__lift_28(ptr %t6)
  call void @__inc_ref(ptr %t108)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t108)
  store ptr %t108, ptr %t3
  store ptr %t109, ptr %t4
  br label %tco.loop.0
tco.case.arm.123.110:
  %t111 = getelementptr ptr, ptr %t5, i32 1
  %t112 = load ptr, ptr %t111
  call void @__inc_ref(ptr %t112)
  call void @__inc_ref(ptr %t6)
  %t113 = call ptr @v__lift_36(ptr %t6)
  call void @__inc_ref(ptr %t112)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t112)
  store ptr %t112, ptr %t3
  store ptr %t113, ptr %t4
  br label %tco.loop.0
tco.case.arm.124.114:
  %t115 = getelementptr ptr, ptr %t5, i32 1
  %t116 = load ptr, ptr %t115
  call void @__inc_ref(ptr %t116)
  call void @__inc_ref(ptr %t6)
  %t117 = call ptr @v__lift_36(ptr %t6)
  call void @__inc_ref(ptr %t116)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t116)
  store ptr %t116, ptr %t3
  store ptr %t117, ptr %t4
  br label %tco.loop.0
tco.case.arm.125.118:
  %t119 = getelementptr ptr, ptr %t5, i32 1
  %t120 = load ptr, ptr %t119
  call void @__inc_ref(ptr %t120)
  call void @__inc_ref(ptr %t6)
  %t121 = call ptr @v__lift_36(ptr %t6)
  call void @__inc_ref(ptr %t120)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t120)
  store ptr %t120, ptr %t3
  store ptr %t121, ptr %t4
  br label %tco.loop.0
tco.case.arm.126.122:
  %t123 = getelementptr ptr, ptr %t5, i32 1
  %t124 = load ptr, ptr %t123
  call void @__inc_ref(ptr %t124)
  call void @__inc_ref(ptr %t6)
  %t125 = call ptr @v__lift_1(ptr %t6)
  call void @__inc_ref(ptr %t124)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t124)
  store ptr %t124, ptr %t3
  store ptr %t125, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t126 = load ptr, ptr %t2
  ret ptr %t126
}

define internal ptr @v__apply1(ptr %v__cl, ptr %v__arg0) {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 53 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  call void @__inc_ref(ptr %v__cl)
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v__cl, ptr %t3
  call void @__inc_ref(ptr %v__arg0)
  %t4 = getelementptr ptr, ptr %t0, i32 2
  store ptr %v__arg0, ptr %t4
  %t5 = call ptr @v__scc__apply1__df__lam_14_1__df__lam_15_2__df__lam_16_3__df__lam_32_5__df__lam_33_6__df__lam_34_7__df__lam_40_9__df__lam_41_14__df__lam_42_15__df__lam_5_11__df__lam_6_12__df__lam_7_13__lift_18__lift_19__lift_2__lift_20__lift_25__lift_26__lift_27__lift_29__lift_3__lift_30__lift_31__lift_37__lift_38__lift_39__lift_4(ptr %t0)
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
