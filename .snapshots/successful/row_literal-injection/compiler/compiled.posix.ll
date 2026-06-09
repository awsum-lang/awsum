; External C declarations
declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare ptr @memcpy(ptr, ptr, i64)
declare i64 @write(i32, ptr, i64)
declare i64 @strlen(ptr)
declare i32 @snprintf(ptr, i64, ptr, ...)
declare i64 @read(i32, ptr, i64)

@.fmt_i32 = private unnamed_addr constant [3 x i8] c"%d\00"
@.fmt_u8 = private unnamed_addr constant [3 x i8] c"%u\00"
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


define internal ptr @__showUInt32(ptr %p) {
  %v = load i32, ptr %p
  %buf = call ptr @__alloc(i64 24, i32 0)
  %payload = getelementptr i8, ptr %buf, i64 8
  %n = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %payload, i64 16, ptr @.fmt_u8, i32 %v)
  store i32 %n, ptr %buf
  %u16p = getelementptr i8, ptr %buf, i64 4
  store i32 %n, ptr %u16p
  call void @__free_recursive(ptr %p)
  ret ptr %buf
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

define internal ptr @v_extract(ptr %v_x) {
  %t0 = getelementptr ptr, ptr %v_x, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 2711245919, label %case.arm.2711245919.4 ]
case.arm.2711245919.4:
  %t5 = getelementptr ptr, ptr %v_x, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t6
case.default.3:
  unreachable
}

define internal ptr @v_extractU(ptr %v_x) {
  %t0 = getelementptr ptr, ptr %v_x, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3538687084, label %case.arm.3538687084.4 ]
case.arm.3538687084.4:
  %t5 = getelementptr ptr, ptr %v_x, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t6
case.default.3:
  unreachable
}

define internal ptr @v_gAsc(ptr %v_n) {
  call void @__inc_ref(ptr %v_n)
  %t0 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t0
  %t1 = call ptr @__eqInt32(ptr %v_n, ptr %t0)
  %t2 = getelementptr ptr, ptr %t1, i32 0
  %t3 = load ptr, ptr %t2
  %t4 = ptrtoint ptr %t3 to i64
  switch i64 %t4, label %case.default.5 [ i64 1, label %case.arm.1.6 i64 2, label %case.arm.2.12 ]
case.arm.1.6:
  %t7 = call ptr @__alloc(i64 16, i32 1)
  %t8 = inttoptr i64 2711245919 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = call ptr @__alloc(i64 4, i32 0)
  store i32 7, ptr %t10
  %t11 = getelementptr ptr, ptr %t7, i32 1
  store ptr %t10, ptr %t11
  call void @__free_recursive(ptr %t1)
  call void @__free_recursive(ptr %v_n)
  ret ptr %t7
case.arm.2.12:
  %t13 = call ptr @__alloc(i64 16, i32 1)
  %t14 = inttoptr i64 2711245919 to ptr
  %t15 = getelementptr ptr, ptr %t13, i32 0
  store ptr %t14, ptr %t15
  %t16 = call ptr @__alloc(i64 4, i32 0)
  store i32 9, ptr %t16
  %t17 = getelementptr ptr, ptr %t13, i32 1
  store ptr %t16, ptr %t17
  call void @__free_recursive(ptr %t1)
  call void @__free_recursive(ptr %v_n)
  ret ptr %t13
case.default.5:
  unreachable
}

define internal ptr @v_gBare(ptr %v_n) {
  call void @__inc_ref(ptr %v_n)
  %t0 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t0
  %t1 = call ptr @__eqInt32(ptr %v_n, ptr %t0)
  %t2 = getelementptr ptr, ptr %t1, i32 0
  %t3 = load ptr, ptr %t2
  %t4 = ptrtoint ptr %t3 to i64
  switch i64 %t4, label %case.default.5 [ i64 1, label %case.arm.1.6 i64 2, label %case.arm.2.12 ]
case.arm.1.6:
  %t7 = call ptr @__alloc(i64 16, i32 1)
  %t8 = inttoptr i64 2711245919 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = call ptr @__alloc(i64 4, i32 0)
  store i32 7, ptr %t10
  %t11 = getelementptr ptr, ptr %t7, i32 1
  store ptr %t10, ptr %t11
  call void @__free_recursive(ptr %t1)
  call void @__free_recursive(ptr %v_n)
  ret ptr %t7
case.arm.2.12:
  %t13 = call ptr @__alloc(i64 16, i32 1)
  %t14 = inttoptr i64 2711245919 to ptr
  %t15 = getelementptr ptr, ptr %t13, i32 0
  store ptr %t14, ptr %t15
  %t16 = call ptr @__alloc(i64 4, i32 0)
  store i32 9, ptr %t16
  %t17 = getelementptr ptr, ptr %t13, i32 1
  store ptr %t16, ptr %t17
  call void @__free_recursive(ptr %t1)
  call void @__free_recursive(ptr %v_n)
  ret ptr %t13
case.default.5:
  unreachable
}

define internal ptr @v_gU(ptr %v_n) {
  call void @__inc_ref(ptr %v_n)
  %t0 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t0
  %t1 = call ptr @__eqInt32(ptr %v_n, ptr %t0)
  %t2 = getelementptr ptr, ptr %t1, i32 0
  %t3 = load ptr, ptr %t2
  %t4 = ptrtoint ptr %t3 to i64
  switch i64 %t4, label %case.default.5 [ i64 1, label %case.arm.1.6 i64 2, label %case.arm.2.12 ]
case.arm.1.6:
  %t7 = call ptr @__alloc(i64 16, i32 1)
  %t8 = inttoptr i64 3538687084 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = call ptr @__alloc(i64 4, i32 0)
  store i32 11, ptr %t10
  %t11 = getelementptr ptr, ptr %t7, i32 1
  store ptr %t10, ptr %t11
  call void @__free_recursive(ptr %t1)
  call void @__free_recursive(ptr %v_n)
  ret ptr %t7
case.arm.2.12:
  %t13 = call ptr @__alloc(i64 16, i32 1)
  %t14 = inttoptr i64 3538687084 to ptr
  %t15 = getelementptr ptr, ptr %t13, i32 0
  store ptr %t14, ptr %t15
  %t16 = call ptr @__alloc(i64 4, i32 0)
  store i32 13, ptr %t16
  %t17 = getelementptr ptr, ptr %t13, i32 1
  store ptr %t16, ptr %t17
  call void @__free_recursive(ptr %t1)
  call void @__free_recursive(ptr %v_n)
  ret ptr %t13
case.default.5:
  unreachable
}

define internal ptr @v_main() {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 7 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t3
  %t4 = call ptr @v_gAsc(ptr %t3)
  %t5 = call ptr @v_extract(ptr %t4)
  %t6 = call ptr @__showInt32(ptr %t5)
  %t7 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t6, ptr %t7
  %t8 = call ptr @__alloc(i64 16, i32 1)
  %t9 = inttoptr i64 5 to ptr
  %t10 = getelementptr ptr, ptr %t8, i32 0
  store ptr %t9, ptr %t10
  %t11 = call ptr @__alloc(i64 8, i32 0)
  %t12 = inttoptr i64 0 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  %t14 = getelementptr ptr, ptr %t8, i32 1
  store ptr %t11, ptr %t14
  %t15 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t8, ptr %t15
  %t16 = call ptr @v__df_andThenIO_16(ptr %t0)
  %t17 = call ptr @v__df_andThenIO_12(ptr %t16)
  %t18 = call ptr @v__df_andThenIO_8(ptr %t17)
  %t19 = call ptr @v__df_andThenIO_4(ptr %t18)
  %t20 = call ptr @v__df_andThenIO_0(ptr %t19)
  ret ptr %t20
}

define internal ptr @v__lam_13(ptr %v__u) {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 7 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 4, i32 0)
  store i32 1, ptr %t3
  %t4 = call ptr @v_gU(ptr %t3)
  %t5 = call ptr @v_extractU(ptr %t4)
  %t6 = call ptr @__showUInt32(ptr %t5)
  %t7 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t6, ptr %t7
  %t8 = call ptr @__alloc(i64 16, i32 1)
  %t9 = inttoptr i64 5 to ptr
  %t10 = getelementptr ptr, ptr %t8, i32 0
  store ptr %t9, ptr %t10
  %t11 = call ptr @__alloc(i64 8, i32 0)
  %t12 = inttoptr i64 0 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  %t14 = getelementptr ptr, ptr %t8, i32 1
  store ptr %t11, ptr %t14
  %t15 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t8, ptr %t15
  call void @__free_recursive(ptr %v__u)
  ret ptr %t0
}

define internal ptr @v__lam_14(ptr %v__u) {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 7 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t3
  %t4 = call ptr @v_gU(ptr %t3)
  %t5 = call ptr @v_extractU(ptr %t4)
  %t6 = call ptr @__showUInt32(ptr %t5)
  %t7 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t6, ptr %t7
  %t8 = call ptr @__alloc(i64 16, i32 1)
  %t9 = inttoptr i64 5 to ptr
  %t10 = getelementptr ptr, ptr %t8, i32 0
  store ptr %t9, ptr %t10
  %t11 = call ptr @__alloc(i64 8, i32 0)
  %t12 = inttoptr i64 0 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  %t14 = getelementptr ptr, ptr %t8, i32 1
  store ptr %t11, ptr %t14
  %t15 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t8, ptr %t15
  call void @__free_recursive(ptr %v__u)
  ret ptr %t0
}

define internal ptr @v__lam_15(ptr %v__u) {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 7 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 4, i32 0)
  store i32 1, ptr %t3
  %t4 = call ptr @v_gBare(ptr %t3)
  %t5 = call ptr @v_extract(ptr %t4)
  %t6 = call ptr @__showInt32(ptr %t5)
  %t7 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t6, ptr %t7
  %t8 = call ptr @__alloc(i64 16, i32 1)
  %t9 = inttoptr i64 5 to ptr
  %t10 = getelementptr ptr, ptr %t8, i32 0
  store ptr %t9, ptr %t10
  %t11 = call ptr @__alloc(i64 8, i32 0)
  %t12 = inttoptr i64 0 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  %t14 = getelementptr ptr, ptr %t8, i32 1
  store ptr %t11, ptr %t14
  %t15 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t8, ptr %t15
  call void @__free_recursive(ptr %v__u)
  ret ptr %t0
}

define internal ptr @v__lam_16(ptr %v__u) {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 7 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t3
  %t4 = call ptr @v_gBare(ptr %t3)
  %t5 = call ptr @v_extract(ptr %t4)
  %t6 = call ptr @__showInt32(ptr %t5)
  %t7 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t6, ptr %t7
  %t8 = call ptr @__alloc(i64 16, i32 1)
  %t9 = inttoptr i64 5 to ptr
  %t10 = getelementptr ptr, ptr %t8, i32 0
  store ptr %t9, ptr %t10
  %t11 = call ptr @__alloc(i64 8, i32 0)
  %t12 = inttoptr i64 0 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  %t14 = getelementptr ptr, ptr %t8, i32 1
  store ptr %t11, ptr %t14
  %t15 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t8, ptr %t15
  call void @__free_recursive(ptr %v__u)
  ret ptr %t0
}

define internal ptr @v__lam_17(ptr %v__u) {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 7 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 4, i32 0)
  store i32 1, ptr %t3
  %t4 = call ptr @v_gAsc(ptr %t3)
  %t5 = call ptr @v_extract(ptr %t4)
  %t6 = call ptr @__showInt32(ptr %t5)
  %t7 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t6, ptr %t7
  %t8 = call ptr @__alloc(i64 16, i32 1)
  %t9 = inttoptr i64 5 to ptr
  %t10 = getelementptr ptr, ptr %t8, i32 0
  store ptr %t9, ptr %t10
  %t11 = call ptr @__alloc(i64 8, i32 0)
  %t12 = inttoptr i64 0 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  %t14 = getelementptr ptr, ptr %t8, i32 1
  store ptr %t11, ptr %t14
  %t15 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t8, ptr %t15
  call void @__free_recursive(ptr %v__u)
  ret ptr %t0
}

define internal ptr @v__df_andThenIO_0(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 42 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_0(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_0(ptr %v_io, ptr %v__k) {
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
  %t14 = call ptr @v__lam_13(ptr %t13)
  %t15 = call ptr @v__apply__df_andThenIO_0(ptr %t6, ptr %t14)
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
  %t23 = call ptr @v__apply__df_andThenIO_0(ptr %t6, ptr %t19)
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
  %t39 = inttoptr i64 43 to ptr
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
  %t42 = inttoptr i64 43 to ptr
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
  %t54 = inttoptr i64 11 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  call void @__inc_ref(ptr %t49)
  %t56 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t49, ptr %t56
  %t57 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t53, ptr %t57
  %t58 = call ptr @v__apply__df_andThenIO_0(ptr %t6, ptr %t50)
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
  %t66 = inttoptr i64 19 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  call void @__inc_ref(ptr %t61)
  %t68 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t61, ptr %t68
  %t69 = getelementptr ptr, ptr %t62, i32 1
  store ptr %t65, ptr %t69
  %t70 = call ptr @v__apply__df_andThenIO_0(ptr %t6, ptr %t62)
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
  %t78 = inttoptr i64 24 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  call void @__inc_ref(ptr %t73)
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t73, ptr %t80
  %t81 = getelementptr ptr, ptr %t74, i32 1
  store ptr %t77, ptr %t81
  %t82 = call ptr @v__apply__df_andThenIO_0(ptr %t6, ptr %t74)
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

define internal ptr @v__apply__df_andThenIO_0(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 42, label %tco.case.arm.42.11 i64 43, label %tco.case.arm.43.12 ]
tco.case.arm.42.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.43.12:
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

define internal ptr @v__df_andThenIO_4(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 44 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_4(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_4(ptr %v_io, ptr %v__k) {
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
  %t14 = call ptr @v__lam_14(ptr %t13)
  %t15 = call ptr @v__apply__df_andThenIO_4(ptr %t6, ptr %t14)
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
  %t23 = call ptr @v__apply__df_andThenIO_4(ptr %t6, ptr %t19)
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
  %t39 = inttoptr i64 45 to ptr
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
  %t42 = inttoptr i64 45 to ptr
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
  %t54 = inttoptr i64 14 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  call void @__inc_ref(ptr %t49)
  %t56 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t49, ptr %t56
  %t57 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t53, ptr %t57
  %t58 = call ptr @v__apply__df_andThenIO_4(ptr %t6, ptr %t50)
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
  %t66 = inttoptr i64 20 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  call void @__inc_ref(ptr %t61)
  %t68 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t61, ptr %t68
  %t69 = getelementptr ptr, ptr %t62, i32 1
  store ptr %t65, ptr %t69
  %t70 = call ptr @v__apply__df_andThenIO_4(ptr %t6, ptr %t62)
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
  %t78 = inttoptr i64 25 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  call void @__inc_ref(ptr %t73)
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t73, ptr %t80
  %t81 = getelementptr ptr, ptr %t74, i32 1
  store ptr %t77, ptr %t81
  %t82 = call ptr @v__apply__df_andThenIO_4(ptr %t6, ptr %t74)
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

define internal ptr @v__apply__df_andThenIO_4(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 44, label %tco.case.arm.44.11 i64 45, label %tco.case.arm.45.12 ]
tco.case.arm.44.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.45.12:
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

define internal ptr @v__df_andThenIO_8(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 46 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_8(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_8(ptr %v_io, ptr %v__k) {
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
  %t14 = call ptr @v__lam_15(ptr %t13)
  %t15 = call ptr @v__apply__df_andThenIO_8(ptr %t6, ptr %t14)
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
  %t23 = call ptr @v__apply__df_andThenIO_8(ptr %t6, ptr %t19)
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
  %t39 = inttoptr i64 47 to ptr
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
  %t42 = inttoptr i64 47 to ptr
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
  %t54 = inttoptr i64 15 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  call void @__inc_ref(ptr %t49)
  %t56 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t49, ptr %t56
  %t57 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t53, ptr %t57
  %t58 = call ptr @v__apply__df_andThenIO_8(ptr %t6, ptr %t50)
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
  %t66 = inttoptr i64 16 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  call void @__inc_ref(ptr %t61)
  %t68 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t61, ptr %t68
  %t69 = getelementptr ptr, ptr %t62, i32 1
  store ptr %t65, ptr %t69
  %t70 = call ptr @v__apply__df_andThenIO_8(ptr %t6, ptr %t62)
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
  %t78 = inttoptr i64 21 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  call void @__inc_ref(ptr %t73)
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t73, ptr %t80
  %t81 = getelementptr ptr, ptr %t74, i32 1
  store ptr %t77, ptr %t81
  %t82 = call ptr @v__apply__df_andThenIO_8(ptr %t6, ptr %t74)
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

define internal ptr @v__apply__df_andThenIO_8(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 46, label %tco.case.arm.46.11 i64 47, label %tco.case.arm.47.12 ]
tco.case.arm.46.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.47.12:
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

define internal ptr @v__df_andThenIO_12(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 48 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_12(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_12(ptr %v_io, ptr %v__k) {
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
  %t14 = call ptr @v__lam_16(ptr %t13)
  %t15 = call ptr @v__apply__df_andThenIO_12(ptr %t6, ptr %t14)
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
  %t23 = call ptr @v__apply__df_andThenIO_12(ptr %t6, ptr %t19)
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
  %t39 = inttoptr i64 49 to ptr
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
  %t42 = inttoptr i64 49 to ptr
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
  %t54 = inttoptr i64 12 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  call void @__inc_ref(ptr %t49)
  %t56 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t49, ptr %t56
  %t57 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t53, ptr %t57
  %t58 = call ptr @v__apply__df_andThenIO_12(ptr %t6, ptr %t50)
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
  %t66 = inttoptr i64 17 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  call void @__inc_ref(ptr %t61)
  %t68 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t61, ptr %t68
  %t69 = getelementptr ptr, ptr %t62, i32 1
  store ptr %t65, ptr %t69
  %t70 = call ptr @v__apply__df_andThenIO_12(ptr %t6, ptr %t62)
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
  %t78 = inttoptr i64 22 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  call void @__inc_ref(ptr %t73)
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t73, ptr %t80
  %t81 = getelementptr ptr, ptr %t74, i32 1
  store ptr %t77, ptr %t81
  %t82 = call ptr @v__apply__df_andThenIO_12(ptr %t6, ptr %t74)
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

define internal ptr @v__apply__df_andThenIO_12(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 48, label %tco.case.arm.48.11 i64 49, label %tco.case.arm.49.12 ]
tco.case.arm.48.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.49.12:
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

define internal ptr @v__df_andThenIO_16(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 50 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_16(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_16(ptr %v_io, ptr %v__k) {
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
  %t14 = call ptr @v__lam_17(ptr %t13)
  %t15 = call ptr @v__apply__df_andThenIO_16(ptr %t6, ptr %t14)
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
  %t23 = call ptr @v__apply__df_andThenIO_16(ptr %t6, ptr %t19)
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
  %t39 = inttoptr i64 51 to ptr
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
  %t42 = inttoptr i64 51 to ptr
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
  %t54 = inttoptr i64 13 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  call void @__inc_ref(ptr %t49)
  %t56 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t49, ptr %t56
  %t57 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t53, ptr %t57
  %t58 = call ptr @v__apply__df_andThenIO_16(ptr %t6, ptr %t50)
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
  %t66 = inttoptr i64 18 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  call void @__inc_ref(ptr %t61)
  %t68 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t61, ptr %t68
  %t69 = getelementptr ptr, ptr %t62, i32 1
  store ptr %t65, ptr %t69
  %t70 = call ptr @v__apply__df_andThenIO_16(ptr %t6, ptr %t62)
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
  %t78 = inttoptr i64 23 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  call void @__inc_ref(ptr %t73)
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t73, ptr %t80
  %t81 = getelementptr ptr, ptr %t74, i32 1
  store ptr %t77, ptr %t81
  %t82 = call ptr @v__apply__df_andThenIO_16(ptr %t6, ptr %t74)
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

define internal ptr @v__apply__df_andThenIO_16(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 50, label %tco.case.arm.50.11 i64 51, label %tco.case.arm.51.12 ]
tco.case.arm.50.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.51.12:
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

define internal ptr @v__scc__apply1__df__lam_0_1__df__lam_0_13__df__lam_0_17__df__lam_0_5__df__lam_0_9__df__lam_1_10__df__lam_1_14__df__lam_1_18__df__lam_1_2__df__lam_1_6__df__lam_2_11__df__lam_2_15__df__lam_2_19__df__lam_2_3__df__lam_2_7(ptr %v__args) {
  call void @__inc_ref(ptr %v__args)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 52 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__scc__apply1__df__lam_0_1__df__lam_0_13__df__lam_0_17__df__lam_0_5__df__lam_0_9__df__lam_1_10__df__lam_1_14__df__lam_1_18__df__lam_1_2__df__lam_1_6__df__lam_2_11__df__lam_2_15__df__lam_2_19__df__lam_2_3__df__lam_2_7(ptr %v__args, ptr %t0)
  call void @__free_recursive(ptr %v__args)
  ret ptr %t3
}

define internal ptr @v__cps__scc__apply1__df__lam_0_1__df__lam_0_13__df__lam_0_17__df__lam_0_5__df__lam_0_9__df__lam_1_10__df__lam_1_14__df__lam_1_18__df__lam_1_2__df__lam_1_6__df__lam_2_11__df__lam_2_15__df__lam_2_19__df__lam_2_3__df__lam_2_7(ptr %v__args, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 26, label %tco.case.arm.26.11 i64 27, label %tco.case.arm.27.320 i64 28, label %tco.case.arm.28.343 i64 29, label %tco.case.arm.29.366 i64 30, label %tco.case.arm.30.389 i64 31, label %tco.case.arm.31.412 i64 32, label %tco.case.arm.32.435 i64 33, label %tco.case.arm.33.458 i64 34, label %tco.case.arm.34.481 i64 35, label %tco.case.arm.35.504 i64 36, label %tco.case.arm.36.527 i64 37, label %tco.case.arm.37.550 i64 38, label %tco.case.arm.38.573 i64 39, label %tco.case.arm.39.596 i64 40, label %tco.case.arm.40.619 i64 41, label %tco.case.arm.41.642 ]
tco.case.arm.26.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t5, i32 2
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  %t16 = getelementptr ptr, ptr %t13, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %tco.case.default.19 [ i64 11, label %tco.case.arm.11.20 i64 12, label %tco.case.arm.12.40 i64 13, label %tco.case.arm.13.60 i64 14, label %tco.case.arm.14.80 i64 15, label %tco.case.arm.15.100 i64 16, label %tco.case.arm.16.120 i64 17, label %tco.case.arm.17.140 i64 18, label %tco.case.arm.18.160 i64 19, label %tco.case.arm.19.180 i64 20, label %tco.case.arm.20.200 i64 21, label %tco.case.arm.21.220 i64 22, label %tco.case.arm.22.240 i64 23, label %tco.case.arm.23.260 i64 24, label %tco.case.arm.24.280 i64 25, label %tco.case.arm.25.300 ]
tco.case.arm.11.20:
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
  %t32 = inttoptr i64 27 to ptr
  %t33 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t32, ptr %t33
  call void @__inc_ref(ptr %t22)
  %t31 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t22, ptr %t31
  br label %reuse.join.28
reuse.copy.27:
  %t34 = call ptr @__alloc(i64 24, i32 2)
  %t35 = inttoptr i64 27 to ptr
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
tco.case.arm.12.40:
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
  %t52 = inttoptr i64 28 to ptr
  %t53 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t52, ptr %t53
  call void @__inc_ref(ptr %t42)
  %t51 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t42, ptr %t51
  br label %reuse.join.48
reuse.copy.47:
  %t54 = call ptr @__alloc(i64 24, i32 2)
  %t55 = inttoptr i64 28 to ptr
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
tco.case.arm.13.60:
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
  %t72 = inttoptr i64 29 to ptr
  %t73 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t72, ptr %t73
  call void @__inc_ref(ptr %t62)
  %t71 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t62, ptr %t71
  br label %reuse.join.68
reuse.copy.67:
  %t74 = call ptr @__alloc(i64 24, i32 2)
  %t75 = inttoptr i64 29 to ptr
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
tco.case.arm.14.80:
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
  %t92 = inttoptr i64 30 to ptr
  %t93 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t92, ptr %t93
  call void @__inc_ref(ptr %t82)
  %t91 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t82, ptr %t91
  br label %reuse.join.88
reuse.copy.87:
  %t94 = call ptr @__alloc(i64 24, i32 2)
  %t95 = inttoptr i64 30 to ptr
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
tco.case.arm.15.100:
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
  %t112 = inttoptr i64 31 to ptr
  %t113 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t112, ptr %t113
  call void @__inc_ref(ptr %t102)
  %t111 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t102, ptr %t111
  br label %reuse.join.108
reuse.copy.107:
  %t114 = call ptr @__alloc(i64 24, i32 2)
  %t115 = inttoptr i64 31 to ptr
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
tco.case.arm.16.120:
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
  %t132 = inttoptr i64 32 to ptr
  %t133 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t132, ptr %t133
  call void @__inc_ref(ptr %t122)
  %t131 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t122, ptr %t131
  br label %reuse.join.128
reuse.copy.127:
  %t134 = call ptr @__alloc(i64 24, i32 2)
  %t135 = inttoptr i64 32 to ptr
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
tco.case.arm.17.140:
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
  %t152 = inttoptr i64 33 to ptr
  %t153 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t152, ptr %t153
  call void @__inc_ref(ptr %t142)
  %t151 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t142, ptr %t151
  br label %reuse.join.148
reuse.copy.147:
  %t154 = call ptr @__alloc(i64 24, i32 2)
  %t155 = inttoptr i64 33 to ptr
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
tco.case.arm.18.160:
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
  %t172 = inttoptr i64 34 to ptr
  %t173 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t172, ptr %t173
  call void @__inc_ref(ptr %t162)
  %t171 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t162, ptr %t171
  br label %reuse.join.168
reuse.copy.167:
  %t174 = call ptr @__alloc(i64 24, i32 2)
  %t175 = inttoptr i64 34 to ptr
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
tco.case.arm.19.180:
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
  %t192 = inttoptr i64 35 to ptr
  %t193 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t192, ptr %t193
  call void @__inc_ref(ptr %t182)
  %t191 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t182, ptr %t191
  br label %reuse.join.188
reuse.copy.187:
  %t194 = call ptr @__alloc(i64 24, i32 2)
  %t195 = inttoptr i64 35 to ptr
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
tco.case.arm.20.200:
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
  %t212 = inttoptr i64 36 to ptr
  %t213 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t212, ptr %t213
  call void @__inc_ref(ptr %t202)
  %t211 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t202, ptr %t211
  br label %reuse.join.208
reuse.copy.207:
  %t214 = call ptr @__alloc(i64 24, i32 2)
  %t215 = inttoptr i64 36 to ptr
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
tco.case.arm.21.220:
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
  %t232 = inttoptr i64 37 to ptr
  %t233 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t232, ptr %t233
  call void @__inc_ref(ptr %t222)
  %t231 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t222, ptr %t231
  br label %reuse.join.228
reuse.copy.227:
  %t234 = call ptr @__alloc(i64 24, i32 2)
  %t235 = inttoptr i64 37 to ptr
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
tco.case.arm.22.240:
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
  %t252 = inttoptr i64 38 to ptr
  %t253 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t252, ptr %t253
  call void @__inc_ref(ptr %t242)
  %t251 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t242, ptr %t251
  br label %reuse.join.248
reuse.copy.247:
  %t254 = call ptr @__alloc(i64 24, i32 2)
  %t255 = inttoptr i64 38 to ptr
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
tco.case.arm.23.260:
  %t261 = getelementptr ptr, ptr %t13, i32 1
  %t262 = load ptr, ptr %t261
  call void @__inc_ref(ptr %t262)
  %t263 = getelementptr i8, ptr %t5, i64 -8
  %t264 = load i32, ptr %t263
  %t265 = icmp eq i32 %t264, 1
  br i1 %t265, label %reuse.in_place.266, label %reuse.copy.267
reuse.in_place.266:
  %t269 = getelementptr ptr, ptr %t5, i32 1
  %t270 = load ptr, ptr %t269
  call void @__free_recursive(ptr %t270)
  %t272 = inttoptr i64 39 to ptr
  %t273 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t272, ptr %t273
  call void @__inc_ref(ptr %t262)
  %t271 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t262, ptr %t271
  br label %reuse.join.268
reuse.copy.267:
  %t274 = call ptr @__alloc(i64 24, i32 2)
  %t275 = inttoptr i64 39 to ptr
  %t276 = getelementptr ptr, ptr %t274, i32 0
  store ptr %t275, ptr %t276
  call void @__inc_ref(ptr %t262)
  %t277 = getelementptr ptr, ptr %t274, i32 1
  store ptr %t262, ptr %t277
  call void @__inc_ref(ptr %t15)
  %t278 = getelementptr ptr, ptr %t274, i32 2
  store ptr %t15, ptr %t278
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.268
reuse.join.268:
  %t279 = phi ptr [ %t5, %reuse.in_place.266 ], [ %t274, %reuse.copy.267 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t262)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t279, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.24.280:
  %t281 = getelementptr ptr, ptr %t13, i32 1
  %t282 = load ptr, ptr %t281
  call void @__inc_ref(ptr %t282)
  %t283 = getelementptr i8, ptr %t5, i64 -8
  %t284 = load i32, ptr %t283
  %t285 = icmp eq i32 %t284, 1
  br i1 %t285, label %reuse.in_place.286, label %reuse.copy.287
reuse.in_place.286:
  %t289 = getelementptr ptr, ptr %t5, i32 1
  %t290 = load ptr, ptr %t289
  call void @__free_recursive(ptr %t290)
  %t292 = inttoptr i64 40 to ptr
  %t293 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t292, ptr %t293
  call void @__inc_ref(ptr %t282)
  %t291 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t282, ptr %t291
  br label %reuse.join.288
reuse.copy.287:
  %t294 = call ptr @__alloc(i64 24, i32 2)
  %t295 = inttoptr i64 40 to ptr
  %t296 = getelementptr ptr, ptr %t294, i32 0
  store ptr %t295, ptr %t296
  call void @__inc_ref(ptr %t282)
  %t297 = getelementptr ptr, ptr %t294, i32 1
  store ptr %t282, ptr %t297
  call void @__inc_ref(ptr %t15)
  %t298 = getelementptr ptr, ptr %t294, i32 2
  store ptr %t15, ptr %t298
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.288
reuse.join.288:
  %t299 = phi ptr [ %t5, %reuse.in_place.286 ], [ %t294, %reuse.copy.287 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t282)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t299, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.25.300:
  %t301 = getelementptr ptr, ptr %t13, i32 1
  %t302 = load ptr, ptr %t301
  call void @__inc_ref(ptr %t302)
  %t303 = getelementptr i8, ptr %t5, i64 -8
  %t304 = load i32, ptr %t303
  %t305 = icmp eq i32 %t304, 1
  br i1 %t305, label %reuse.in_place.306, label %reuse.copy.307
reuse.in_place.306:
  %t309 = getelementptr ptr, ptr %t5, i32 1
  %t310 = load ptr, ptr %t309
  call void @__free_recursive(ptr %t310)
  %t312 = inttoptr i64 41 to ptr
  %t313 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t312, ptr %t313
  call void @__inc_ref(ptr %t302)
  %t311 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t302, ptr %t311
  br label %reuse.join.308
reuse.copy.307:
  %t314 = call ptr @__alloc(i64 24, i32 2)
  %t315 = inttoptr i64 41 to ptr
  %t316 = getelementptr ptr, ptr %t314, i32 0
  store ptr %t315, ptr %t316
  call void @__inc_ref(ptr %t302)
  %t317 = getelementptr ptr, ptr %t314, i32 1
  store ptr %t302, ptr %t317
  call void @__inc_ref(ptr %t15)
  %t318 = getelementptr ptr, ptr %t314, i32 2
  store ptr %t15, ptr %t318
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.308
reuse.join.308:
  %t319 = phi ptr [ %t5, %reuse.in_place.306 ], [ %t314, %reuse.copy.307 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t302)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t319, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.default.19:
  unreachable
tco.case.arm.27.320:
  %t321 = getelementptr ptr, ptr %t5, i32 1
  %t322 = load ptr, ptr %t321
  %t323 = getelementptr ptr, ptr %t5, i32 2
  %t324 = load ptr, ptr %t323
  %t325 = getelementptr i8, ptr %t5, i64 -8
  %t326 = load i32, ptr %t325
  %t327 = icmp eq i32 %t326, 1
  br i1 %t327, label %reuse.in_place.328, label %reuse.copy.329
reuse.in_place.328:
  %t331 = inttoptr i64 26 to ptr
  %t332 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t331, ptr %t332
  br label %reuse.join.330
reuse.copy.329:
  %t333 = call ptr @__alloc(i64 24, i32 2)
  %t334 = inttoptr i64 26 to ptr
  %t335 = getelementptr ptr, ptr %t333, i32 0
  store ptr %t334, ptr %t335
  call void @__inc_ref(ptr %t322)
  %t336 = getelementptr ptr, ptr %t333, i32 1
  store ptr %t322, ptr %t336
  call void @__inc_ref(ptr %t324)
  %t337 = getelementptr ptr, ptr %t333, i32 2
  store ptr %t324, ptr %t337
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.330
reuse.join.330:
  %t338 = phi ptr [ %t5, %reuse.in_place.328 ], [ %t333, %reuse.copy.329 ]
  %t339 = call ptr @__alloc(i64 16, i32 1)
  %t340 = inttoptr i64 53 to ptr
  %t341 = getelementptr ptr, ptr %t339, i32 0
  store ptr %t340, ptr %t341
  call void @__inc_ref(ptr %t6)
  %t342 = getelementptr ptr, ptr %t339, i32 1
  store ptr %t6, ptr %t342
  call void @__free_recursive(ptr %t6)
  store ptr %t338, ptr %t3
  store ptr %t339, ptr %t4
  br label %tco.loop.0
tco.case.arm.28.343:
  %t344 = getelementptr ptr, ptr %t5, i32 1
  %t345 = load ptr, ptr %t344
  %t346 = getelementptr ptr, ptr %t5, i32 2
  %t347 = load ptr, ptr %t346
  %t348 = getelementptr i8, ptr %t5, i64 -8
  %t349 = load i32, ptr %t348
  %t350 = icmp eq i32 %t349, 1
  br i1 %t350, label %reuse.in_place.351, label %reuse.copy.352
reuse.in_place.351:
  %t354 = inttoptr i64 26 to ptr
  %t355 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t354, ptr %t355
  br label %reuse.join.353
reuse.copy.352:
  %t356 = call ptr @__alloc(i64 24, i32 2)
  %t357 = inttoptr i64 26 to ptr
  %t358 = getelementptr ptr, ptr %t356, i32 0
  store ptr %t357, ptr %t358
  call void @__inc_ref(ptr %t345)
  %t359 = getelementptr ptr, ptr %t356, i32 1
  store ptr %t345, ptr %t359
  call void @__inc_ref(ptr %t347)
  %t360 = getelementptr ptr, ptr %t356, i32 2
  store ptr %t347, ptr %t360
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.353
reuse.join.353:
  %t361 = phi ptr [ %t5, %reuse.in_place.351 ], [ %t356, %reuse.copy.352 ]
  %t362 = call ptr @__alloc(i64 16, i32 1)
  %t363 = inttoptr i64 54 to ptr
  %t364 = getelementptr ptr, ptr %t362, i32 0
  store ptr %t363, ptr %t364
  call void @__inc_ref(ptr %t6)
  %t365 = getelementptr ptr, ptr %t362, i32 1
  store ptr %t6, ptr %t365
  call void @__free_recursive(ptr %t6)
  store ptr %t361, ptr %t3
  store ptr %t362, ptr %t4
  br label %tco.loop.0
tco.case.arm.29.366:
  %t367 = getelementptr ptr, ptr %t5, i32 1
  %t368 = load ptr, ptr %t367
  %t369 = getelementptr ptr, ptr %t5, i32 2
  %t370 = load ptr, ptr %t369
  %t371 = getelementptr i8, ptr %t5, i64 -8
  %t372 = load i32, ptr %t371
  %t373 = icmp eq i32 %t372, 1
  br i1 %t373, label %reuse.in_place.374, label %reuse.copy.375
reuse.in_place.374:
  %t377 = inttoptr i64 26 to ptr
  %t378 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t377, ptr %t378
  br label %reuse.join.376
reuse.copy.375:
  %t379 = call ptr @__alloc(i64 24, i32 2)
  %t380 = inttoptr i64 26 to ptr
  %t381 = getelementptr ptr, ptr %t379, i32 0
  store ptr %t380, ptr %t381
  call void @__inc_ref(ptr %t368)
  %t382 = getelementptr ptr, ptr %t379, i32 1
  store ptr %t368, ptr %t382
  call void @__inc_ref(ptr %t370)
  %t383 = getelementptr ptr, ptr %t379, i32 2
  store ptr %t370, ptr %t383
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.376
reuse.join.376:
  %t384 = phi ptr [ %t5, %reuse.in_place.374 ], [ %t379, %reuse.copy.375 ]
  %t385 = call ptr @__alloc(i64 16, i32 1)
  %t386 = inttoptr i64 55 to ptr
  %t387 = getelementptr ptr, ptr %t385, i32 0
  store ptr %t386, ptr %t387
  call void @__inc_ref(ptr %t6)
  %t388 = getelementptr ptr, ptr %t385, i32 1
  store ptr %t6, ptr %t388
  call void @__free_recursive(ptr %t6)
  store ptr %t384, ptr %t3
  store ptr %t385, ptr %t4
  br label %tco.loop.0
tco.case.arm.30.389:
  %t390 = getelementptr ptr, ptr %t5, i32 1
  %t391 = load ptr, ptr %t390
  %t392 = getelementptr ptr, ptr %t5, i32 2
  %t393 = load ptr, ptr %t392
  %t394 = getelementptr i8, ptr %t5, i64 -8
  %t395 = load i32, ptr %t394
  %t396 = icmp eq i32 %t395, 1
  br i1 %t396, label %reuse.in_place.397, label %reuse.copy.398
reuse.in_place.397:
  %t400 = inttoptr i64 26 to ptr
  %t401 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t400, ptr %t401
  br label %reuse.join.399
reuse.copy.398:
  %t402 = call ptr @__alloc(i64 24, i32 2)
  %t403 = inttoptr i64 26 to ptr
  %t404 = getelementptr ptr, ptr %t402, i32 0
  store ptr %t403, ptr %t404
  call void @__inc_ref(ptr %t391)
  %t405 = getelementptr ptr, ptr %t402, i32 1
  store ptr %t391, ptr %t405
  call void @__inc_ref(ptr %t393)
  %t406 = getelementptr ptr, ptr %t402, i32 2
  store ptr %t393, ptr %t406
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.399
reuse.join.399:
  %t407 = phi ptr [ %t5, %reuse.in_place.397 ], [ %t402, %reuse.copy.398 ]
  %t408 = call ptr @__alloc(i64 16, i32 1)
  %t409 = inttoptr i64 56 to ptr
  %t410 = getelementptr ptr, ptr %t408, i32 0
  store ptr %t409, ptr %t410
  call void @__inc_ref(ptr %t6)
  %t411 = getelementptr ptr, ptr %t408, i32 1
  store ptr %t6, ptr %t411
  call void @__free_recursive(ptr %t6)
  store ptr %t407, ptr %t3
  store ptr %t408, ptr %t4
  br label %tco.loop.0
tco.case.arm.31.412:
  %t413 = getelementptr ptr, ptr %t5, i32 1
  %t414 = load ptr, ptr %t413
  %t415 = getelementptr ptr, ptr %t5, i32 2
  %t416 = load ptr, ptr %t415
  %t417 = getelementptr i8, ptr %t5, i64 -8
  %t418 = load i32, ptr %t417
  %t419 = icmp eq i32 %t418, 1
  br i1 %t419, label %reuse.in_place.420, label %reuse.copy.421
reuse.in_place.420:
  %t423 = inttoptr i64 26 to ptr
  %t424 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t423, ptr %t424
  br label %reuse.join.422
reuse.copy.421:
  %t425 = call ptr @__alloc(i64 24, i32 2)
  %t426 = inttoptr i64 26 to ptr
  %t427 = getelementptr ptr, ptr %t425, i32 0
  store ptr %t426, ptr %t427
  call void @__inc_ref(ptr %t414)
  %t428 = getelementptr ptr, ptr %t425, i32 1
  store ptr %t414, ptr %t428
  call void @__inc_ref(ptr %t416)
  %t429 = getelementptr ptr, ptr %t425, i32 2
  store ptr %t416, ptr %t429
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.422
reuse.join.422:
  %t430 = phi ptr [ %t5, %reuse.in_place.420 ], [ %t425, %reuse.copy.421 ]
  %t431 = call ptr @__alloc(i64 16, i32 1)
  %t432 = inttoptr i64 57 to ptr
  %t433 = getelementptr ptr, ptr %t431, i32 0
  store ptr %t432, ptr %t433
  call void @__inc_ref(ptr %t6)
  %t434 = getelementptr ptr, ptr %t431, i32 1
  store ptr %t6, ptr %t434
  call void @__free_recursive(ptr %t6)
  store ptr %t430, ptr %t3
  store ptr %t431, ptr %t4
  br label %tco.loop.0
tco.case.arm.32.435:
  %t436 = getelementptr ptr, ptr %t5, i32 1
  %t437 = load ptr, ptr %t436
  %t438 = getelementptr ptr, ptr %t5, i32 2
  %t439 = load ptr, ptr %t438
  %t440 = getelementptr i8, ptr %t5, i64 -8
  %t441 = load i32, ptr %t440
  %t442 = icmp eq i32 %t441, 1
  br i1 %t442, label %reuse.in_place.443, label %reuse.copy.444
reuse.in_place.443:
  %t446 = inttoptr i64 26 to ptr
  %t447 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t446, ptr %t447
  br label %reuse.join.445
reuse.copy.444:
  %t448 = call ptr @__alloc(i64 24, i32 2)
  %t449 = inttoptr i64 26 to ptr
  %t450 = getelementptr ptr, ptr %t448, i32 0
  store ptr %t449, ptr %t450
  call void @__inc_ref(ptr %t437)
  %t451 = getelementptr ptr, ptr %t448, i32 1
  store ptr %t437, ptr %t451
  call void @__inc_ref(ptr %t439)
  %t452 = getelementptr ptr, ptr %t448, i32 2
  store ptr %t439, ptr %t452
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.445
reuse.join.445:
  %t453 = phi ptr [ %t5, %reuse.in_place.443 ], [ %t448, %reuse.copy.444 ]
  %t454 = call ptr @__alloc(i64 16, i32 1)
  %t455 = inttoptr i64 58 to ptr
  %t456 = getelementptr ptr, ptr %t454, i32 0
  store ptr %t455, ptr %t456
  call void @__inc_ref(ptr %t6)
  %t457 = getelementptr ptr, ptr %t454, i32 1
  store ptr %t6, ptr %t457
  call void @__free_recursive(ptr %t6)
  store ptr %t453, ptr %t3
  store ptr %t454, ptr %t4
  br label %tco.loop.0
tco.case.arm.33.458:
  %t459 = getelementptr ptr, ptr %t5, i32 1
  %t460 = load ptr, ptr %t459
  %t461 = getelementptr ptr, ptr %t5, i32 2
  %t462 = load ptr, ptr %t461
  %t463 = getelementptr i8, ptr %t5, i64 -8
  %t464 = load i32, ptr %t463
  %t465 = icmp eq i32 %t464, 1
  br i1 %t465, label %reuse.in_place.466, label %reuse.copy.467
reuse.in_place.466:
  %t469 = inttoptr i64 26 to ptr
  %t470 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t469, ptr %t470
  br label %reuse.join.468
reuse.copy.467:
  %t471 = call ptr @__alloc(i64 24, i32 2)
  %t472 = inttoptr i64 26 to ptr
  %t473 = getelementptr ptr, ptr %t471, i32 0
  store ptr %t472, ptr %t473
  call void @__inc_ref(ptr %t460)
  %t474 = getelementptr ptr, ptr %t471, i32 1
  store ptr %t460, ptr %t474
  call void @__inc_ref(ptr %t462)
  %t475 = getelementptr ptr, ptr %t471, i32 2
  store ptr %t462, ptr %t475
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.468
reuse.join.468:
  %t476 = phi ptr [ %t5, %reuse.in_place.466 ], [ %t471, %reuse.copy.467 ]
  %t477 = call ptr @__alloc(i64 16, i32 1)
  %t478 = inttoptr i64 59 to ptr
  %t479 = getelementptr ptr, ptr %t477, i32 0
  store ptr %t478, ptr %t479
  call void @__inc_ref(ptr %t6)
  %t480 = getelementptr ptr, ptr %t477, i32 1
  store ptr %t6, ptr %t480
  call void @__free_recursive(ptr %t6)
  store ptr %t476, ptr %t3
  store ptr %t477, ptr %t4
  br label %tco.loop.0
tco.case.arm.34.481:
  %t482 = getelementptr ptr, ptr %t5, i32 1
  %t483 = load ptr, ptr %t482
  %t484 = getelementptr ptr, ptr %t5, i32 2
  %t485 = load ptr, ptr %t484
  %t486 = getelementptr i8, ptr %t5, i64 -8
  %t487 = load i32, ptr %t486
  %t488 = icmp eq i32 %t487, 1
  br i1 %t488, label %reuse.in_place.489, label %reuse.copy.490
reuse.in_place.489:
  %t492 = inttoptr i64 26 to ptr
  %t493 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t492, ptr %t493
  br label %reuse.join.491
reuse.copy.490:
  %t494 = call ptr @__alloc(i64 24, i32 2)
  %t495 = inttoptr i64 26 to ptr
  %t496 = getelementptr ptr, ptr %t494, i32 0
  store ptr %t495, ptr %t496
  call void @__inc_ref(ptr %t483)
  %t497 = getelementptr ptr, ptr %t494, i32 1
  store ptr %t483, ptr %t497
  call void @__inc_ref(ptr %t485)
  %t498 = getelementptr ptr, ptr %t494, i32 2
  store ptr %t485, ptr %t498
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.491
reuse.join.491:
  %t499 = phi ptr [ %t5, %reuse.in_place.489 ], [ %t494, %reuse.copy.490 ]
  %t500 = call ptr @__alloc(i64 16, i32 1)
  %t501 = inttoptr i64 60 to ptr
  %t502 = getelementptr ptr, ptr %t500, i32 0
  store ptr %t501, ptr %t502
  call void @__inc_ref(ptr %t6)
  %t503 = getelementptr ptr, ptr %t500, i32 1
  store ptr %t6, ptr %t503
  call void @__free_recursive(ptr %t6)
  store ptr %t499, ptr %t3
  store ptr %t500, ptr %t4
  br label %tco.loop.0
tco.case.arm.35.504:
  %t505 = getelementptr ptr, ptr %t5, i32 1
  %t506 = load ptr, ptr %t505
  %t507 = getelementptr ptr, ptr %t5, i32 2
  %t508 = load ptr, ptr %t507
  %t509 = getelementptr i8, ptr %t5, i64 -8
  %t510 = load i32, ptr %t509
  %t511 = icmp eq i32 %t510, 1
  br i1 %t511, label %reuse.in_place.512, label %reuse.copy.513
reuse.in_place.512:
  %t515 = inttoptr i64 26 to ptr
  %t516 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t515, ptr %t516
  br label %reuse.join.514
reuse.copy.513:
  %t517 = call ptr @__alloc(i64 24, i32 2)
  %t518 = inttoptr i64 26 to ptr
  %t519 = getelementptr ptr, ptr %t517, i32 0
  store ptr %t518, ptr %t519
  call void @__inc_ref(ptr %t506)
  %t520 = getelementptr ptr, ptr %t517, i32 1
  store ptr %t506, ptr %t520
  call void @__inc_ref(ptr %t508)
  %t521 = getelementptr ptr, ptr %t517, i32 2
  store ptr %t508, ptr %t521
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.514
reuse.join.514:
  %t522 = phi ptr [ %t5, %reuse.in_place.512 ], [ %t517, %reuse.copy.513 ]
  %t523 = call ptr @__alloc(i64 16, i32 1)
  %t524 = inttoptr i64 61 to ptr
  %t525 = getelementptr ptr, ptr %t523, i32 0
  store ptr %t524, ptr %t525
  call void @__inc_ref(ptr %t6)
  %t526 = getelementptr ptr, ptr %t523, i32 1
  store ptr %t6, ptr %t526
  call void @__free_recursive(ptr %t6)
  store ptr %t522, ptr %t3
  store ptr %t523, ptr %t4
  br label %tco.loop.0
tco.case.arm.36.527:
  %t528 = getelementptr ptr, ptr %t5, i32 1
  %t529 = load ptr, ptr %t528
  %t530 = getelementptr ptr, ptr %t5, i32 2
  %t531 = load ptr, ptr %t530
  %t532 = getelementptr i8, ptr %t5, i64 -8
  %t533 = load i32, ptr %t532
  %t534 = icmp eq i32 %t533, 1
  br i1 %t534, label %reuse.in_place.535, label %reuse.copy.536
reuse.in_place.535:
  %t538 = inttoptr i64 26 to ptr
  %t539 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t538, ptr %t539
  br label %reuse.join.537
reuse.copy.536:
  %t540 = call ptr @__alloc(i64 24, i32 2)
  %t541 = inttoptr i64 26 to ptr
  %t542 = getelementptr ptr, ptr %t540, i32 0
  store ptr %t541, ptr %t542
  call void @__inc_ref(ptr %t529)
  %t543 = getelementptr ptr, ptr %t540, i32 1
  store ptr %t529, ptr %t543
  call void @__inc_ref(ptr %t531)
  %t544 = getelementptr ptr, ptr %t540, i32 2
  store ptr %t531, ptr %t544
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.537
reuse.join.537:
  %t545 = phi ptr [ %t5, %reuse.in_place.535 ], [ %t540, %reuse.copy.536 ]
  %t546 = call ptr @__alloc(i64 16, i32 1)
  %t547 = inttoptr i64 62 to ptr
  %t548 = getelementptr ptr, ptr %t546, i32 0
  store ptr %t547, ptr %t548
  call void @__inc_ref(ptr %t6)
  %t549 = getelementptr ptr, ptr %t546, i32 1
  store ptr %t6, ptr %t549
  call void @__free_recursive(ptr %t6)
  store ptr %t545, ptr %t3
  store ptr %t546, ptr %t4
  br label %tco.loop.0
tco.case.arm.37.550:
  %t551 = getelementptr ptr, ptr %t5, i32 1
  %t552 = load ptr, ptr %t551
  %t553 = getelementptr ptr, ptr %t5, i32 2
  %t554 = load ptr, ptr %t553
  %t555 = getelementptr i8, ptr %t5, i64 -8
  %t556 = load i32, ptr %t555
  %t557 = icmp eq i32 %t556, 1
  br i1 %t557, label %reuse.in_place.558, label %reuse.copy.559
reuse.in_place.558:
  %t561 = inttoptr i64 26 to ptr
  %t562 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t561, ptr %t562
  br label %reuse.join.560
reuse.copy.559:
  %t563 = call ptr @__alloc(i64 24, i32 2)
  %t564 = inttoptr i64 26 to ptr
  %t565 = getelementptr ptr, ptr %t563, i32 0
  store ptr %t564, ptr %t565
  call void @__inc_ref(ptr %t552)
  %t566 = getelementptr ptr, ptr %t563, i32 1
  store ptr %t552, ptr %t566
  call void @__inc_ref(ptr %t554)
  %t567 = getelementptr ptr, ptr %t563, i32 2
  store ptr %t554, ptr %t567
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.560
reuse.join.560:
  %t568 = phi ptr [ %t5, %reuse.in_place.558 ], [ %t563, %reuse.copy.559 ]
  %t569 = call ptr @__alloc(i64 16, i32 1)
  %t570 = inttoptr i64 63 to ptr
  %t571 = getelementptr ptr, ptr %t569, i32 0
  store ptr %t570, ptr %t571
  call void @__inc_ref(ptr %t6)
  %t572 = getelementptr ptr, ptr %t569, i32 1
  store ptr %t6, ptr %t572
  call void @__free_recursive(ptr %t6)
  store ptr %t568, ptr %t3
  store ptr %t569, ptr %t4
  br label %tco.loop.0
tco.case.arm.38.573:
  %t574 = getelementptr ptr, ptr %t5, i32 1
  %t575 = load ptr, ptr %t574
  %t576 = getelementptr ptr, ptr %t5, i32 2
  %t577 = load ptr, ptr %t576
  %t578 = getelementptr i8, ptr %t5, i64 -8
  %t579 = load i32, ptr %t578
  %t580 = icmp eq i32 %t579, 1
  br i1 %t580, label %reuse.in_place.581, label %reuse.copy.582
reuse.in_place.581:
  %t584 = inttoptr i64 26 to ptr
  %t585 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t584, ptr %t585
  br label %reuse.join.583
reuse.copy.582:
  %t586 = call ptr @__alloc(i64 24, i32 2)
  %t587 = inttoptr i64 26 to ptr
  %t588 = getelementptr ptr, ptr %t586, i32 0
  store ptr %t587, ptr %t588
  call void @__inc_ref(ptr %t575)
  %t589 = getelementptr ptr, ptr %t586, i32 1
  store ptr %t575, ptr %t589
  call void @__inc_ref(ptr %t577)
  %t590 = getelementptr ptr, ptr %t586, i32 2
  store ptr %t577, ptr %t590
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.583
reuse.join.583:
  %t591 = phi ptr [ %t5, %reuse.in_place.581 ], [ %t586, %reuse.copy.582 ]
  %t592 = call ptr @__alloc(i64 16, i32 1)
  %t593 = inttoptr i64 64 to ptr
  %t594 = getelementptr ptr, ptr %t592, i32 0
  store ptr %t593, ptr %t594
  call void @__inc_ref(ptr %t6)
  %t595 = getelementptr ptr, ptr %t592, i32 1
  store ptr %t6, ptr %t595
  call void @__free_recursive(ptr %t6)
  store ptr %t591, ptr %t3
  store ptr %t592, ptr %t4
  br label %tco.loop.0
tco.case.arm.39.596:
  %t597 = getelementptr ptr, ptr %t5, i32 1
  %t598 = load ptr, ptr %t597
  %t599 = getelementptr ptr, ptr %t5, i32 2
  %t600 = load ptr, ptr %t599
  %t601 = getelementptr i8, ptr %t5, i64 -8
  %t602 = load i32, ptr %t601
  %t603 = icmp eq i32 %t602, 1
  br i1 %t603, label %reuse.in_place.604, label %reuse.copy.605
reuse.in_place.604:
  %t607 = inttoptr i64 26 to ptr
  %t608 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t607, ptr %t608
  br label %reuse.join.606
reuse.copy.605:
  %t609 = call ptr @__alloc(i64 24, i32 2)
  %t610 = inttoptr i64 26 to ptr
  %t611 = getelementptr ptr, ptr %t609, i32 0
  store ptr %t610, ptr %t611
  call void @__inc_ref(ptr %t598)
  %t612 = getelementptr ptr, ptr %t609, i32 1
  store ptr %t598, ptr %t612
  call void @__inc_ref(ptr %t600)
  %t613 = getelementptr ptr, ptr %t609, i32 2
  store ptr %t600, ptr %t613
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.606
reuse.join.606:
  %t614 = phi ptr [ %t5, %reuse.in_place.604 ], [ %t609, %reuse.copy.605 ]
  %t615 = call ptr @__alloc(i64 16, i32 1)
  %t616 = inttoptr i64 65 to ptr
  %t617 = getelementptr ptr, ptr %t615, i32 0
  store ptr %t616, ptr %t617
  call void @__inc_ref(ptr %t6)
  %t618 = getelementptr ptr, ptr %t615, i32 1
  store ptr %t6, ptr %t618
  call void @__free_recursive(ptr %t6)
  store ptr %t614, ptr %t3
  store ptr %t615, ptr %t4
  br label %tco.loop.0
tco.case.arm.40.619:
  %t620 = getelementptr ptr, ptr %t5, i32 1
  %t621 = load ptr, ptr %t620
  %t622 = getelementptr ptr, ptr %t5, i32 2
  %t623 = load ptr, ptr %t622
  %t624 = getelementptr i8, ptr %t5, i64 -8
  %t625 = load i32, ptr %t624
  %t626 = icmp eq i32 %t625, 1
  br i1 %t626, label %reuse.in_place.627, label %reuse.copy.628
reuse.in_place.627:
  %t630 = inttoptr i64 26 to ptr
  %t631 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t630, ptr %t631
  br label %reuse.join.629
reuse.copy.628:
  %t632 = call ptr @__alloc(i64 24, i32 2)
  %t633 = inttoptr i64 26 to ptr
  %t634 = getelementptr ptr, ptr %t632, i32 0
  store ptr %t633, ptr %t634
  call void @__inc_ref(ptr %t621)
  %t635 = getelementptr ptr, ptr %t632, i32 1
  store ptr %t621, ptr %t635
  call void @__inc_ref(ptr %t623)
  %t636 = getelementptr ptr, ptr %t632, i32 2
  store ptr %t623, ptr %t636
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.629
reuse.join.629:
  %t637 = phi ptr [ %t5, %reuse.in_place.627 ], [ %t632, %reuse.copy.628 ]
  %t638 = call ptr @__alloc(i64 16, i32 1)
  %t639 = inttoptr i64 66 to ptr
  %t640 = getelementptr ptr, ptr %t638, i32 0
  store ptr %t639, ptr %t640
  call void @__inc_ref(ptr %t6)
  %t641 = getelementptr ptr, ptr %t638, i32 1
  store ptr %t6, ptr %t641
  call void @__free_recursive(ptr %t6)
  store ptr %t637, ptr %t3
  store ptr %t638, ptr %t4
  br label %tco.loop.0
tco.case.arm.41.642:
  %t643 = getelementptr ptr, ptr %t5, i32 1
  %t644 = load ptr, ptr %t643
  %t645 = getelementptr ptr, ptr %t5, i32 2
  %t646 = load ptr, ptr %t645
  %t647 = getelementptr i8, ptr %t5, i64 -8
  %t648 = load i32, ptr %t647
  %t649 = icmp eq i32 %t648, 1
  br i1 %t649, label %reuse.in_place.650, label %reuse.copy.651
reuse.in_place.650:
  %t653 = inttoptr i64 26 to ptr
  %t654 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t653, ptr %t654
  br label %reuse.join.652
reuse.copy.651:
  %t655 = call ptr @__alloc(i64 24, i32 2)
  %t656 = inttoptr i64 26 to ptr
  %t657 = getelementptr ptr, ptr %t655, i32 0
  store ptr %t656, ptr %t657
  call void @__inc_ref(ptr %t644)
  %t658 = getelementptr ptr, ptr %t655, i32 1
  store ptr %t644, ptr %t658
  call void @__inc_ref(ptr %t646)
  %t659 = getelementptr ptr, ptr %t655, i32 2
  store ptr %t646, ptr %t659
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.652
reuse.join.652:
  %t660 = phi ptr [ %t5, %reuse.in_place.650 ], [ %t655, %reuse.copy.651 ]
  %t661 = call ptr @__alloc(i64 16, i32 1)
  %t662 = inttoptr i64 67 to ptr
  %t663 = getelementptr ptr, ptr %t661, i32 0
  store ptr %t662, ptr %t663
  call void @__inc_ref(ptr %t6)
  %t664 = getelementptr ptr, ptr %t661, i32 1
  store ptr %t6, ptr %t664
  call void @__free_recursive(ptr %t6)
  store ptr %t660, ptr %t3
  store ptr %t661, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t665 = load ptr, ptr %t2
  ret ptr %t665
}

define internal ptr @v__apply1(ptr %v__cl, ptr %v__arg0) {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 26 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  call void @__inc_ref(ptr %v__cl)
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v__cl, ptr %t3
  call void @__inc_ref(ptr %v__arg0)
  %t4 = getelementptr ptr, ptr %t0, i32 2
  store ptr %v__arg0, ptr %t4
  %t5 = call ptr @v__scc__apply1__df__lam_0_1__df__lam_0_13__df__lam_0_17__df__lam_0_5__df__lam_0_9__df__lam_1_10__df__lam_1_14__df__lam_1_18__df__lam_1_2__df__lam_1_6__df__lam_2_11__df__lam_2_15__df__lam_2_19__df__lam_2_3__df__lam_2_7(ptr %t0)
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
