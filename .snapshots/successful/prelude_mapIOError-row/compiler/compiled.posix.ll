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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"ErrA" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"ErrB" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [7 x i8]} { i32 0, i32 0, i32 0, i32 7, i32 7, [7 x i8] c"mappedA" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"\0A" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"=" }
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [9 x i8]} { i32 0, i32 0, i32 0, i32 9, i32 9, [9 x i8] c"remappedY" }
@.str.6 = private unnamed_addr constant {i32, i32, i32, i32, i32, [9 x i8]} { i32 0, i32 0, i32 0, i32 9, i32 9, [9 x i8] c"remappedX" }
@.str.7 = private unnamed_addr constant {i32, i32, i32, i32, i32, [8 x i8]} { i32 0, i32 0, i32 0, i32 8, i32 8, [8 x i8] c"mappedOk" }
@.str.8 = private unnamed_addr constant {i32, i32, i32, i32, i32, [7 x i8]} { i32 0, i32 0, i32 0, i32 7, i32 7, [7 x i8] c"mappedB" }

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

define internal ptr @v_toRowA(ptr %v__s) {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 2252990199 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 8, i32 0)
  %t4 = inttoptr i64 27 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  call void @__free_recursive(ptr %v__s)
  ret ptr %t0
}

define internal ptr @v_toRowB(ptr %v__s) {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 2269767818 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 8, i32 0)
  %t4 = inttoptr i64 28 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  call void @__free_recursive(ptr %v__s)
  ret ptr %t0
}

define internal ptr @v_failSrc() {
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 24 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_failIO(ptr %t0)
  ret ptr %t3
}

define internal ptr @v_okSrc() {
  %t0 = call ptr @__alloc(i64 4, i32 0)
  store i32 5, ptr %t0
  %t1 = call ptr @v_pureIO(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_mappedA() {
  %t0 = call ptr @v_failSrc()
  %t1 = call ptr @v__df_mapIOError_0(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_mappedB() {
  %t0 = call ptr @v_failSrc()
  %t1 = call ptr @v__df_mapIOError_4(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_mappedOk() {
  %t0 = call ptr @v_okSrc()
  %t1 = call ptr @v__df_mapIOError_0(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_remap(ptr %v_e) {
  %t0 = getelementptr ptr, ptr %v_e, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3640903312, label %case.arm.3640903312.4 i64 3657680931, label %case.arm.3657680931.14 ]
case.arm.3640903312.4:
  %t5 = getelementptr ptr, ptr %v_e, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = call ptr @__alloc(i64 16, i32 1)
  %t8 = inttoptr i64 2269767818 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = call ptr @__alloc(i64 8, i32 0)
  %t11 = inttoptr i64 28 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  %t13 = getelementptr ptr, ptr %t7, i32 1
  store ptr %t10, ptr %t13
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_e)
  ret ptr %t7
case.arm.3657680931.14:
  %t15 = getelementptr ptr, ptr %v_e, i32 1
  %t16 = load ptr, ptr %t15
  call void @__inc_ref(ptr %t16)
  %t17 = call ptr @__alloc(i64 16, i32 1)
  %t18 = inttoptr i64 2252990199 to ptr
  %t19 = getelementptr ptr, ptr %t17, i32 0
  store ptr %t18, ptr %t19
  %t20 = call ptr @__alloc(i64 8, i32 0)
  %t21 = inttoptr i64 27 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = getelementptr ptr, ptr %t17, i32 1
  store ptr %t20, ptr %t23
  call void @__free_recursive(ptr %t16)
  call void @__free_recursive(ptr %v_e)
  ret ptr %t17
case.default.3:
  unreachable
}

define internal ptr @v_failX() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 3657680931 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 8, i32 0)
  %t4 = inttoptr i64 25 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  %t7 = call ptr @v_failIO(ptr %t0)
  ret ptr %t7
}

define internal ptr @v_failY() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 3640903312 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 8, i32 0)
  %t4 = inttoptr i64 26 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  %t7 = call ptr @v_failIO(ptr %t0)
  ret ptr %t7
}

define internal ptr @v_remappedX() {
  %t0 = call ptr @v_failX()
  %t1 = call ptr @v__df_mapIOError_8(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_remappedY() {
  %t0 = call ptr @v_failY()
  %t1 = call ptr @v__df_mapIOError_8(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_handlerAB(ptr %v_e) {
  %t0 = getelementptr ptr, ptr %v_e, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 2252990199, label %case.arm.2252990199.4 i64 2269767818, label %case.arm.2269767818.19 ]
case.arm.2252990199.4:
  %t5 = getelementptr ptr, ptr %v_e, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = call ptr @__alloc(i64 24, i32 2)
  %t8 = inttoptr i64 7 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = getelementptr ptr, ptr %t7, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t10
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
  call void @__free_recursive(ptr %v_e)
  ret ptr %t7
case.arm.2269767818.19:
  %t20 = getelementptr ptr, ptr %v_e, i32 1
  %t21 = load ptr, ptr %t20
  call void @__inc_ref(ptr %t21)
  %t22 = call ptr @__alloc(i64 24, i32 2)
  %t23 = inttoptr i64 7 to ptr
  %t24 = getelementptr ptr, ptr %t22, i32 0
  store ptr %t23, ptr %t24
  %t25 = getelementptr ptr, ptr %t22, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t25
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
  call void @__free_recursive(ptr %v_e)
  ret ptr %t22
case.default.3:
  unreachable
}

define internal ptr @v_observeAB(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @v__df_mapIO_20(ptr %v_io)
  %t1 = call ptr @v__df__rowmono_0_andThenIO_16(ptr %t0)
  %t2 = call ptr @v__df_handleErrorIO_12(ptr %t1)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t2
}

define internal ptr @v_handlerABC(ptr %v_e) {
  %t0 = getelementptr ptr, ptr %v_e, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 2252990199, label %case.arm.2252990199.4 i64 2269767818, label %case.arm.2269767818.19 ]
case.arm.2252990199.4:
  %t5 = getelementptr ptr, ptr %v_e, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = call ptr @__alloc(i64 24, i32 2)
  %t8 = inttoptr i64 7 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = getelementptr ptr, ptr %t7, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t10
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
  call void @__free_recursive(ptr %v_e)
  ret ptr %t7
case.arm.2269767818.19:
  %t20 = getelementptr ptr, ptr %v_e, i32 1
  %t21 = load ptr, ptr %t20
  call void @__inc_ref(ptr %t21)
  %t22 = call ptr @__alloc(i64 24, i32 2)
  %t23 = inttoptr i64 7 to ptr
  %t24 = getelementptr ptr, ptr %t22, i32 0
  store ptr %t23, ptr %t24
  %t25 = getelementptr ptr, ptr %t22, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t25
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
  call void @__free_recursive(ptr %v_e)
  ret ptr %t22
case.default.3:
  unreachable
}

define internal ptr @v_observeABC(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @v__df_mapIO_20(ptr %v_io)
  %t1 = call ptr @v__df__rowmono_1_andThenIO_28(ptr %t0)
  %t2 = call ptr @v__df_handleErrorIO_24(ptr %t1)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t2
}

define internal ptr @v_line(ptr %v_label, ptr %v_act) {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 7 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  call void @__inc_ref(ptr %v_label)
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v_label, ptr %t3
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
  %t12 = call ptr @v__df_andThenIO_40(ptr %t0)
  call void @__inc_ref(ptr %v_act)
  %t13 = call ptr @v__df_andThenIO_36(ptr %t12, ptr %v_act)
  %t14 = call ptr @v__df_andThenIO_32(ptr %t13)
  call void @__free_recursive(ptr %v_label)
  call void @__free_recursive(ptr %v_act)
  ret ptr %t14
}

define internal ptr @v_main() {
  %t0 = call ptr @v_mappedA()
  %t1 = call ptr @v_observeAB(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t1)
  %t3 = call ptr @v__df_andThenIO_56(ptr %t2)
  %t4 = call ptr @v__df_andThenIO_52(ptr %t3)
  %t5 = call ptr @v__df_andThenIO_48(ptr %t4)
  %t6 = call ptr @v__df_andThenIO_44(ptr %t5)
  ret ptr %t6
}

define internal ptr @v__lift_1(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 138 to ptr
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
  %t42 = inttoptr i64 139 to ptr
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
  %t45 = inttoptr i64 139 to ptr
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
  %t57 = inttoptr i64 74 to ptr
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
  %t69 = inttoptr i64 78 to ptr
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
  %t81 = inttoptr i64 82 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 138, label %tco.case.arm.138.11 i64 139, label %tco.case.arm.139.12 ]
tco.case.arm.138.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.139.12:
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

define internal ptr @v__lam_18(ptr %v__u) {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 7 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t3
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
  call void @__free_recursive(ptr %v__u)
  ret ptr %t0
}

define internal ptr @v__lam_19(ptr %v_act, ptr %v__u) {
  call void @__free_recursive(ptr %v__u)
  ret ptr %v_act
}

define internal ptr @v__lam_20(ptr %v__u) {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 7 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t3
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
  call void @__free_recursive(ptr %v__u)
  ret ptr %t0
}

define internal ptr @v__lam_21(ptr %v__u) {
  %t0 = call ptr @v_remappedY()
  %t1 = call ptr @v_observeABC(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.5, i64 12), ptr %t1)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t2
}

define internal ptr @v__lam_22(ptr %v__u) {
  %t0 = call ptr @v_remappedX()
  %t1 = call ptr @v_observeABC(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.6, i64 12), ptr %t1)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t2
}

define internal ptr @v__lam_23(ptr %v__u) {
  %t0 = call ptr @v_mappedOk()
  %t1 = call ptr @v_observeAB(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.7, i64 12), ptr %t1)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t2
}

define internal ptr @v__lam_24(ptr %v__u) {
  %t0 = call ptr @v_mappedB()
  %t1 = call ptr @v_observeAB(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.8, i64 12), ptr %t1)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t2
}

define internal ptr @v__lift_25(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 140 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__lift_25(ptr %v___input, ptr %t0)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t3
}

define internal ptr @v__cps__lift_25(ptr %v___input, ptr %v__k) {
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
  %t18 = call ptr @v__apply__lift_25(ptr %t6, ptr %t14)
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
  %t26 = call ptr @v__apply__lift_25(ptr %t6, ptr %t22)
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
  %t42 = inttoptr i64 141 to ptr
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
  %t45 = inttoptr i64 141 to ptr
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
  %t57 = inttoptr i64 75 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  call void @__inc_ref(ptr %t52)
  %t59 = getelementptr ptr, ptr %t56, i32 1
  store ptr %t52, ptr %t59
  %t60 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t56, ptr %t60
  %t61 = call ptr @v__apply__lift_25(ptr %t6, ptr %t53)
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
  %t69 = inttoptr i64 76 to ptr
  %t70 = getelementptr ptr, ptr %t68, i32 0
  store ptr %t69, ptr %t70
  call void @__inc_ref(ptr %t64)
  %t71 = getelementptr ptr, ptr %t68, i32 1
  store ptr %t64, ptr %t71
  %t72 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t68, ptr %t72
  %t73 = call ptr @v__apply__lift_25(ptr %t6, ptr %t65)
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
  %t81 = inttoptr i64 77 to ptr
  %t82 = getelementptr ptr, ptr %t80, i32 0
  store ptr %t81, ptr %t82
  call void @__inc_ref(ptr %t76)
  %t83 = getelementptr ptr, ptr %t80, i32 1
  store ptr %t76, ptr %t83
  %t84 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t80, ptr %t84
  %t85 = call ptr @v__apply__lift_25(ptr %t6, ptr %t77)
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

define internal ptr @v__apply__lift_25(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 140, label %tco.case.arm.140.11 i64 141, label %tco.case.arm.141.12 ]
tco.case.arm.140.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.141.12:
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

define internal ptr @v__lift_32(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 142 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__lift_32(ptr %v___input, ptr %t0)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t3
}

define internal ptr @v__cps__lift_32(ptr %v___input, ptr %v__k) {
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
  %t18 = call ptr @v__apply__lift_32(ptr %t6, ptr %t14)
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
  %t26 = call ptr @v__apply__lift_32(ptr %t6, ptr %t22)
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
  %t42 = inttoptr i64 143 to ptr
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
  %t45 = inttoptr i64 143 to ptr
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
  %t57 = inttoptr i64 79 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  call void @__inc_ref(ptr %t52)
  %t59 = getelementptr ptr, ptr %t56, i32 1
  store ptr %t52, ptr %t59
  %t60 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t56, ptr %t60
  %t61 = call ptr @v__apply__lift_32(ptr %t6, ptr %t53)
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
  %t69 = inttoptr i64 80 to ptr
  %t70 = getelementptr ptr, ptr %t68, i32 0
  store ptr %t69, ptr %t70
  call void @__inc_ref(ptr %t64)
  %t71 = getelementptr ptr, ptr %t68, i32 1
  store ptr %t64, ptr %t71
  %t72 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t68, ptr %t72
  %t73 = call ptr @v__apply__lift_32(ptr %t6, ptr %t65)
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
  %t81 = inttoptr i64 81 to ptr
  %t82 = getelementptr ptr, ptr %t80, i32 0
  store ptr %t81, ptr %t82
  call void @__inc_ref(ptr %t76)
  %t83 = getelementptr ptr, ptr %t80, i32 1
  store ptr %t76, ptr %t83
  %t84 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t80, ptr %t84
  %t85 = call ptr @v__apply__lift_32(ptr %t6, ptr %t77)
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

define internal ptr @v__apply__lift_32(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 142, label %tco.case.arm.142.11 i64 143, label %tco.case.arm.143.12 ]
tco.case.arm.142.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.143.12:
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

define internal ptr @v__bi_showInt32(ptr %v__x0) {
  call void @__inc_ref(ptr %v__x0)
  %t0 = call ptr @__showInt32(ptr %v__x0)
  call void @__free_recursive(ptr %v__x0)
  ret ptr %t0
}

define internal ptr @v__df_mapIOError_0(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 144 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_mapIOError_0(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_mapIOError_0(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.19 i64 7, label %tco.case.arm.7.28 i64 8, label %tco.case.arm.8.51 i64 9, label %tco.case.arm.9.63 i64 10, label %tco.case.arm.10.75 ]
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
  %t18 = call ptr @v__apply__df_mapIOError_0(ptr %t6, ptr %t14)
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
  %t25 = call ptr @v_toRowA(ptr %t21)
  %t26 = getelementptr ptr, ptr %t22, i32 1
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__apply__df_mapIOError_0(ptr %t6, ptr %t22)
  call void @__free_recursive(ptr %t21)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t27, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.28:
  %t29 = getelementptr ptr, ptr %t5, i32 1
  %t30 = load ptr, ptr %t29
  %t31 = getelementptr ptr, ptr %t5, i32 2
  %t32 = load ptr, ptr %t31
  call void @__inc_ref(ptr %t32)
  %t33 = getelementptr i8, ptr %t5, i64 -8
  %t34 = load i32, ptr %t33
  %t35 = icmp eq i32 %t34, 1
  br i1 %t35, label %reuse.in_place.36, label %reuse.copy.37
reuse.in_place.36:
  %t39 = getelementptr ptr, ptr %t5, i32 2
  %t40 = load ptr, ptr %t39
  call void @__free_recursive(ptr %t40)
  %t43 = inttoptr i64 145 to ptr
  %t44 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t43, ptr %t44
  call void @__inc_ref(ptr %t6)
  %t41 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t41
  %t42 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t30, ptr %t42
  br label %reuse.join.38
reuse.copy.37:
  %t45 = call ptr @__alloc(i64 24, i32 2)
  %t46 = inttoptr i64 145 to ptr
  %t47 = getelementptr ptr, ptr %t45, i32 0
  store ptr %t46, ptr %t47
  call void @__inc_ref(ptr %t6)
  %t48 = getelementptr ptr, ptr %t45, i32 1
  store ptr %t6, ptr %t48
  call void @__inc_ref(ptr %t30)
  %t49 = getelementptr ptr, ptr %t45, i32 2
  store ptr %t30, ptr %t49
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.38
reuse.join.38:
  %t50 = phi ptr [ %t5, %reuse.in_place.36 ], [ %t45, %reuse.copy.37 ]
  call void @__inc_ref(ptr %t32)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t32)
  store ptr %t32, ptr %t3
  store ptr %t50, ptr %t4
  br label %tco.loop.0
tco.case.arm.8.51:
  %t52 = getelementptr ptr, ptr %t5, i32 1
  %t53 = load ptr, ptr %t52
  call void @__inc_ref(ptr %t53)
  call void @__inc_ref(ptr %t6)
  %t54 = call ptr @__alloc(i64 16, i32 1)
  %t55 = inttoptr i64 8 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  %t57 = call ptr @__alloc(i64 16, i32 1)
  %t58 = inttoptr i64 30 to ptr
  %t59 = getelementptr ptr, ptr %t57, i32 0
  store ptr %t58, ptr %t59
  call void @__inc_ref(ptr %t53)
  %t60 = getelementptr ptr, ptr %t57, i32 1
  store ptr %t53, ptr %t60
  %t61 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t57, ptr %t61
  %t62 = call ptr @v__apply__df_mapIOError_0(ptr %t6, ptr %t54)
  call void @__free_recursive(ptr %t53)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t62, ptr %t2
  br label %tco.exit.1
tco.case.arm.9.63:
  %t64 = getelementptr ptr, ptr %t5, i32 1
  %t65 = load ptr, ptr %t64
  call void @__inc_ref(ptr %t65)
  call void @__inc_ref(ptr %t6)
  %t66 = call ptr @__alloc(i64 16, i32 1)
  %t67 = inttoptr i64 9 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  %t69 = call ptr @__alloc(i64 16, i32 1)
  %t70 = inttoptr i64 34 to ptr
  %t71 = getelementptr ptr, ptr %t69, i32 0
  store ptr %t70, ptr %t71
  call void @__inc_ref(ptr %t65)
  %t72 = getelementptr ptr, ptr %t69, i32 1
  store ptr %t65, ptr %t72
  %t73 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t69, ptr %t73
  %t74 = call ptr @v__apply__df_mapIOError_0(ptr %t6, ptr %t66)
  call void @__free_recursive(ptr %t65)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t74, ptr %t2
  br label %tco.exit.1
tco.case.arm.10.75:
  %t76 = getelementptr ptr, ptr %t5, i32 1
  %t77 = load ptr, ptr %t76
  call void @__inc_ref(ptr %t77)
  call void @__inc_ref(ptr %t6)
  %t78 = call ptr @__alloc(i64 16, i32 1)
  %t79 = inttoptr i64 10 to ptr
  %t80 = getelementptr ptr, ptr %t78, i32 0
  store ptr %t79, ptr %t80
  %t81 = call ptr @__alloc(i64 16, i32 1)
  %t82 = inttoptr i64 37 to ptr
  %t83 = getelementptr ptr, ptr %t81, i32 0
  store ptr %t82, ptr %t83
  call void @__inc_ref(ptr %t77)
  %t84 = getelementptr ptr, ptr %t81, i32 1
  store ptr %t77, ptr %t84
  %t85 = getelementptr ptr, ptr %t78, i32 1
  store ptr %t81, ptr %t85
  %t86 = call ptr @v__apply__df_mapIOError_0(ptr %t6, ptr %t78)
  call void @__free_recursive(ptr %t77)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t86, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t87 = load ptr, ptr %t2
  ret ptr %t87
}

define internal ptr @v__apply__df_mapIOError_0(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 144, label %tco.case.arm.144.11 i64 145, label %tco.case.arm.145.12 ]
tco.case.arm.144.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.145.12:
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

define internal ptr @v__df_mapIOError_4(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 146 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_mapIOError_4(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_mapIOError_4(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.19 i64 7, label %tco.case.arm.7.28 i64 8, label %tco.case.arm.8.51 i64 9, label %tco.case.arm.9.63 i64 10, label %tco.case.arm.10.75 ]
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
  %t18 = call ptr @v__apply__df_mapIOError_4(ptr %t6, ptr %t14)
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
  %t25 = call ptr @v_toRowB(ptr %t21)
  %t26 = getelementptr ptr, ptr %t22, i32 1
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__apply__df_mapIOError_4(ptr %t6, ptr %t22)
  call void @__free_recursive(ptr %t21)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t27, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.28:
  %t29 = getelementptr ptr, ptr %t5, i32 1
  %t30 = load ptr, ptr %t29
  %t31 = getelementptr ptr, ptr %t5, i32 2
  %t32 = load ptr, ptr %t31
  call void @__inc_ref(ptr %t32)
  %t33 = getelementptr i8, ptr %t5, i64 -8
  %t34 = load i32, ptr %t33
  %t35 = icmp eq i32 %t34, 1
  br i1 %t35, label %reuse.in_place.36, label %reuse.copy.37
reuse.in_place.36:
  %t39 = getelementptr ptr, ptr %t5, i32 2
  %t40 = load ptr, ptr %t39
  call void @__free_recursive(ptr %t40)
  %t43 = inttoptr i64 147 to ptr
  %t44 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t43, ptr %t44
  call void @__inc_ref(ptr %t6)
  %t41 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t41
  %t42 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t30, ptr %t42
  br label %reuse.join.38
reuse.copy.37:
  %t45 = call ptr @__alloc(i64 24, i32 2)
  %t46 = inttoptr i64 147 to ptr
  %t47 = getelementptr ptr, ptr %t45, i32 0
  store ptr %t46, ptr %t47
  call void @__inc_ref(ptr %t6)
  %t48 = getelementptr ptr, ptr %t45, i32 1
  store ptr %t6, ptr %t48
  call void @__inc_ref(ptr %t30)
  %t49 = getelementptr ptr, ptr %t45, i32 2
  store ptr %t30, ptr %t49
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.38
reuse.join.38:
  %t50 = phi ptr [ %t5, %reuse.in_place.36 ], [ %t45, %reuse.copy.37 ]
  call void @__inc_ref(ptr %t32)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t32)
  store ptr %t32, ptr %t3
  store ptr %t50, ptr %t4
  br label %tco.loop.0
tco.case.arm.8.51:
  %t52 = getelementptr ptr, ptr %t5, i32 1
  %t53 = load ptr, ptr %t52
  call void @__inc_ref(ptr %t53)
  call void @__inc_ref(ptr %t6)
  %t54 = call ptr @__alloc(i64 16, i32 1)
  %t55 = inttoptr i64 8 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  %t57 = call ptr @__alloc(i64 16, i32 1)
  %t58 = inttoptr i64 31 to ptr
  %t59 = getelementptr ptr, ptr %t57, i32 0
  store ptr %t58, ptr %t59
  call void @__inc_ref(ptr %t53)
  %t60 = getelementptr ptr, ptr %t57, i32 1
  store ptr %t53, ptr %t60
  %t61 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t57, ptr %t61
  %t62 = call ptr @v__apply__df_mapIOError_4(ptr %t6, ptr %t54)
  call void @__free_recursive(ptr %t53)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t62, ptr %t2
  br label %tco.exit.1
tco.case.arm.9.63:
  %t64 = getelementptr ptr, ptr %t5, i32 1
  %t65 = load ptr, ptr %t64
  call void @__inc_ref(ptr %t65)
  call void @__inc_ref(ptr %t6)
  %t66 = call ptr @__alloc(i64 16, i32 1)
  %t67 = inttoptr i64 9 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  %t69 = call ptr @__alloc(i64 16, i32 1)
  %t70 = inttoptr i64 35 to ptr
  %t71 = getelementptr ptr, ptr %t69, i32 0
  store ptr %t70, ptr %t71
  call void @__inc_ref(ptr %t65)
  %t72 = getelementptr ptr, ptr %t69, i32 1
  store ptr %t65, ptr %t72
  %t73 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t69, ptr %t73
  %t74 = call ptr @v__apply__df_mapIOError_4(ptr %t6, ptr %t66)
  call void @__free_recursive(ptr %t65)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t74, ptr %t2
  br label %tco.exit.1
tco.case.arm.10.75:
  %t76 = getelementptr ptr, ptr %t5, i32 1
  %t77 = load ptr, ptr %t76
  call void @__inc_ref(ptr %t77)
  call void @__inc_ref(ptr %t6)
  %t78 = call ptr @__alloc(i64 16, i32 1)
  %t79 = inttoptr i64 10 to ptr
  %t80 = getelementptr ptr, ptr %t78, i32 0
  store ptr %t79, ptr %t80
  %t81 = call ptr @__alloc(i64 16, i32 1)
  %t82 = inttoptr i64 38 to ptr
  %t83 = getelementptr ptr, ptr %t81, i32 0
  store ptr %t82, ptr %t83
  call void @__inc_ref(ptr %t77)
  %t84 = getelementptr ptr, ptr %t81, i32 1
  store ptr %t77, ptr %t84
  %t85 = getelementptr ptr, ptr %t78, i32 1
  store ptr %t81, ptr %t85
  %t86 = call ptr @v__apply__df_mapIOError_4(ptr %t6, ptr %t78)
  call void @__free_recursive(ptr %t77)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t86, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t87 = load ptr, ptr %t2
  ret ptr %t87
}

define internal ptr @v__apply__df_mapIOError_4(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 146, label %tco.case.arm.146.11 i64 147, label %tco.case.arm.147.12 ]
tco.case.arm.146.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.147.12:
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

define internal ptr @v__df_mapIOError_8(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 148 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_mapIOError_8(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_mapIOError_8(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.19 i64 7, label %tco.case.arm.7.28 i64 8, label %tco.case.arm.8.51 i64 9, label %tco.case.arm.9.63 i64 10, label %tco.case.arm.10.75 ]
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
  %t18 = call ptr @v__apply__df_mapIOError_8(ptr %t6, ptr %t14)
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
  %t25 = call ptr @v_remap(ptr %t21)
  %t26 = getelementptr ptr, ptr %t22, i32 1
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__apply__df_mapIOError_8(ptr %t6, ptr %t22)
  call void @__free_recursive(ptr %t21)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t27, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.28:
  %t29 = getelementptr ptr, ptr %t5, i32 1
  %t30 = load ptr, ptr %t29
  %t31 = getelementptr ptr, ptr %t5, i32 2
  %t32 = load ptr, ptr %t31
  call void @__inc_ref(ptr %t32)
  %t33 = getelementptr i8, ptr %t5, i64 -8
  %t34 = load i32, ptr %t33
  %t35 = icmp eq i32 %t34, 1
  br i1 %t35, label %reuse.in_place.36, label %reuse.copy.37
reuse.in_place.36:
  %t39 = getelementptr ptr, ptr %t5, i32 2
  %t40 = load ptr, ptr %t39
  call void @__free_recursive(ptr %t40)
  %t43 = inttoptr i64 149 to ptr
  %t44 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t43, ptr %t44
  call void @__inc_ref(ptr %t6)
  %t41 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t41
  %t42 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t30, ptr %t42
  br label %reuse.join.38
reuse.copy.37:
  %t45 = call ptr @__alloc(i64 24, i32 2)
  %t46 = inttoptr i64 149 to ptr
  %t47 = getelementptr ptr, ptr %t45, i32 0
  store ptr %t46, ptr %t47
  call void @__inc_ref(ptr %t6)
  %t48 = getelementptr ptr, ptr %t45, i32 1
  store ptr %t6, ptr %t48
  call void @__inc_ref(ptr %t30)
  %t49 = getelementptr ptr, ptr %t45, i32 2
  store ptr %t30, ptr %t49
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.38
reuse.join.38:
  %t50 = phi ptr [ %t5, %reuse.in_place.36 ], [ %t45, %reuse.copy.37 ]
  call void @__inc_ref(ptr %t32)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t32)
  store ptr %t32, ptr %t3
  store ptr %t50, ptr %t4
  br label %tco.loop.0
tco.case.arm.8.51:
  %t52 = getelementptr ptr, ptr %t5, i32 1
  %t53 = load ptr, ptr %t52
  call void @__inc_ref(ptr %t53)
  call void @__inc_ref(ptr %t6)
  %t54 = call ptr @__alloc(i64 16, i32 1)
  %t55 = inttoptr i64 8 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  %t57 = call ptr @__alloc(i64 16, i32 1)
  %t58 = inttoptr i64 32 to ptr
  %t59 = getelementptr ptr, ptr %t57, i32 0
  store ptr %t58, ptr %t59
  call void @__inc_ref(ptr %t53)
  %t60 = getelementptr ptr, ptr %t57, i32 1
  store ptr %t53, ptr %t60
  %t61 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t57, ptr %t61
  %t62 = call ptr @v__apply__df_mapIOError_8(ptr %t6, ptr %t54)
  call void @__free_recursive(ptr %t53)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t62, ptr %t2
  br label %tco.exit.1
tco.case.arm.9.63:
  %t64 = getelementptr ptr, ptr %t5, i32 1
  %t65 = load ptr, ptr %t64
  call void @__inc_ref(ptr %t65)
  call void @__inc_ref(ptr %t6)
  %t66 = call ptr @__alloc(i64 16, i32 1)
  %t67 = inttoptr i64 9 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  %t69 = call ptr @__alloc(i64 16, i32 1)
  %t70 = inttoptr i64 33 to ptr
  %t71 = getelementptr ptr, ptr %t69, i32 0
  store ptr %t70, ptr %t71
  call void @__inc_ref(ptr %t65)
  %t72 = getelementptr ptr, ptr %t69, i32 1
  store ptr %t65, ptr %t72
  %t73 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t69, ptr %t73
  %t74 = call ptr @v__apply__df_mapIOError_8(ptr %t6, ptr %t66)
  call void @__free_recursive(ptr %t65)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t74, ptr %t2
  br label %tco.exit.1
tco.case.arm.10.75:
  %t76 = getelementptr ptr, ptr %t5, i32 1
  %t77 = load ptr, ptr %t76
  call void @__inc_ref(ptr %t77)
  call void @__inc_ref(ptr %t6)
  %t78 = call ptr @__alloc(i64 16, i32 1)
  %t79 = inttoptr i64 10 to ptr
  %t80 = getelementptr ptr, ptr %t78, i32 0
  store ptr %t79, ptr %t80
  %t81 = call ptr @__alloc(i64 16, i32 1)
  %t82 = inttoptr i64 36 to ptr
  %t83 = getelementptr ptr, ptr %t81, i32 0
  store ptr %t82, ptr %t83
  call void @__inc_ref(ptr %t77)
  %t84 = getelementptr ptr, ptr %t81, i32 1
  store ptr %t77, ptr %t84
  %t85 = getelementptr ptr, ptr %t78, i32 1
  store ptr %t81, ptr %t85
  %t86 = call ptr @v__apply__df_mapIOError_8(ptr %t6, ptr %t78)
  call void @__free_recursive(ptr %t77)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t86, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t87 = load ptr, ptr %t2
  ret ptr %t87
}

define internal ptr @v__apply__df_mapIOError_8(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 148, label %tco.case.arm.148.11 i64 149, label %tco.case.arm.149.12 ]
tco.case.arm.148.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.149.12:
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

define internal ptr @v__df_handleErrorIO_12(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 150 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_handleErrorIO_12(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_handleErrorIO_12(ptr %v_io, ptr %v__k) {
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
  %t18 = call ptr @v__apply__df_handleErrorIO_12(ptr %t6, ptr %t14)
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
  %t22 = call ptr @v_handlerAB(ptr %t21)
  %t23 = call ptr @v__apply__df_handleErrorIO_12(ptr %t6, ptr %t22)
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
  %t39 = inttoptr i64 151 to ptr
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
  %t42 = inttoptr i64 151 to ptr
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
  %t54 = inttoptr i64 39 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  call void @__inc_ref(ptr %t49)
  %t56 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t49, ptr %t56
  %t57 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t53, ptr %t57
  %t58 = call ptr @v__apply__df_handleErrorIO_12(ptr %t6, ptr %t50)
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
  %t66 = inttoptr i64 41 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  call void @__inc_ref(ptr %t61)
  %t68 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t61, ptr %t68
  %t69 = getelementptr ptr, ptr %t62, i32 1
  store ptr %t65, ptr %t69
  %t70 = call ptr @v__apply__df_handleErrorIO_12(ptr %t6, ptr %t62)
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
  %t78 = inttoptr i64 43 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  call void @__inc_ref(ptr %t73)
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t73, ptr %t80
  %t81 = getelementptr ptr, ptr %t74, i32 1
  store ptr %t77, ptr %t81
  %t82 = call ptr @v__apply__df_handleErrorIO_12(ptr %t6, ptr %t74)
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

define internal ptr @v__apply__df_handleErrorIO_12(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 150, label %tco.case.arm.150.11 i64 151, label %tco.case.arm.151.12 ]
tco.case.arm.150.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.151.12:
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

define internal ptr @v__df__rowmono_0_andThenIO_16(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 152 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df__rowmono_0_andThenIO_16(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df__rowmono_0_andThenIO_16(ptr %v_io, ptr %v__k) {
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
  %t15 = call ptr @v__lift_25(ptr %t14)
  %t16 = call ptr @v__apply__df__rowmono_0_andThenIO_16(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df__rowmono_0_andThenIO_16(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 153 to ptr
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
  %t43 = inttoptr i64 153 to ptr
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
  %t55 = inttoptr i64 45 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df__rowmono_0_andThenIO_16(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 46 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df__rowmono_0_andThenIO_16(ptr %t6, ptr %t63)
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
  %t79 = inttoptr i64 47 to ptr
  %t80 = getelementptr ptr, ptr %t78, i32 0
  store ptr %t79, ptr %t80
  call void @__inc_ref(ptr %t74)
  %t81 = getelementptr ptr, ptr %t78, i32 1
  store ptr %t74, ptr %t81
  %t82 = getelementptr ptr, ptr %t75, i32 1
  store ptr %t78, ptr %t82
  %t83 = call ptr @v__apply__df__rowmono_0_andThenIO_16(ptr %t6, ptr %t75)
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

define internal ptr @v__apply__df__rowmono_0_andThenIO_16(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 152, label %tco.case.arm.152.11 i64 153, label %tco.case.arm.153.12 ]
tco.case.arm.152.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.153.12:
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

define internal ptr @v__df_mapIO_20(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 154 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_mapIO_20(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_mapIO_20(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.20 i64 7, label %tco.case.arm.7.28 i64 8, label %tco.case.arm.8.51 i64 9, label %tco.case.arm.9.63 i64 10, label %tco.case.arm.10.75 ]
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
  %t17 = call ptr @v__bi_showInt32(ptr %t13)
  %t18 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t17, ptr %t18
  %t19 = call ptr @v__apply__df_mapIO_20(ptr %t6, ptr %t14)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t19, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.20:
  %t21 = getelementptr ptr, ptr %t5, i32 1
  %t22 = load ptr, ptr %t21
  call void @__inc_ref(ptr %t22)
  call void @__inc_ref(ptr %t6)
  %t23 = call ptr @__alloc(i64 16, i32 1)
  %t24 = inttoptr i64 6 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  call void @__inc_ref(ptr %t22)
  %t26 = getelementptr ptr, ptr %t23, i32 1
  store ptr %t22, ptr %t26
  %t27 = call ptr @v__apply__df_mapIO_20(ptr %t6, ptr %t23)
  call void @__free_recursive(ptr %t22)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t27, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.28:
  %t29 = getelementptr ptr, ptr %t5, i32 1
  %t30 = load ptr, ptr %t29
  %t31 = getelementptr ptr, ptr %t5, i32 2
  %t32 = load ptr, ptr %t31
  call void @__inc_ref(ptr %t32)
  %t33 = getelementptr i8, ptr %t5, i64 -8
  %t34 = load i32, ptr %t33
  %t35 = icmp eq i32 %t34, 1
  br i1 %t35, label %reuse.in_place.36, label %reuse.copy.37
reuse.in_place.36:
  %t39 = getelementptr ptr, ptr %t5, i32 2
  %t40 = load ptr, ptr %t39
  call void @__free_recursive(ptr %t40)
  %t43 = inttoptr i64 155 to ptr
  %t44 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t43, ptr %t44
  call void @__inc_ref(ptr %t6)
  %t41 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t41
  %t42 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t30, ptr %t42
  br label %reuse.join.38
reuse.copy.37:
  %t45 = call ptr @__alloc(i64 24, i32 2)
  %t46 = inttoptr i64 155 to ptr
  %t47 = getelementptr ptr, ptr %t45, i32 0
  store ptr %t46, ptr %t47
  call void @__inc_ref(ptr %t6)
  %t48 = getelementptr ptr, ptr %t45, i32 1
  store ptr %t6, ptr %t48
  call void @__inc_ref(ptr %t30)
  %t49 = getelementptr ptr, ptr %t45, i32 2
  store ptr %t30, ptr %t49
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.38
reuse.join.38:
  %t50 = phi ptr [ %t5, %reuse.in_place.36 ], [ %t45, %reuse.copy.37 ]
  call void @__inc_ref(ptr %t32)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t32)
  store ptr %t32, ptr %t3
  store ptr %t50, ptr %t4
  br label %tco.loop.0
tco.case.arm.8.51:
  %t52 = getelementptr ptr, ptr %t5, i32 1
  %t53 = load ptr, ptr %t52
  call void @__inc_ref(ptr %t53)
  call void @__inc_ref(ptr %t6)
  %t54 = call ptr @__alloc(i64 16, i32 1)
  %t55 = inttoptr i64 8 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  %t57 = call ptr @__alloc(i64 16, i32 1)
  %t58 = inttoptr i64 72 to ptr
  %t59 = getelementptr ptr, ptr %t57, i32 0
  store ptr %t58, ptr %t59
  call void @__inc_ref(ptr %t53)
  %t60 = getelementptr ptr, ptr %t57, i32 1
  store ptr %t53, ptr %t60
  %t61 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t57, ptr %t61
  %t62 = call ptr @v__apply__df_mapIO_20(ptr %t6, ptr %t54)
  call void @__free_recursive(ptr %t53)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t62, ptr %t2
  br label %tco.exit.1
tco.case.arm.9.63:
  %t64 = getelementptr ptr, ptr %t5, i32 1
  %t65 = load ptr, ptr %t64
  call void @__inc_ref(ptr %t65)
  call void @__inc_ref(ptr %t6)
  %t66 = call ptr @__alloc(i64 16, i32 1)
  %t67 = inttoptr i64 9 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  %t69 = call ptr @__alloc(i64 16, i32 1)
  %t70 = inttoptr i64 73 to ptr
  %t71 = getelementptr ptr, ptr %t69, i32 0
  store ptr %t70, ptr %t71
  call void @__inc_ref(ptr %t65)
  %t72 = getelementptr ptr, ptr %t69, i32 1
  store ptr %t65, ptr %t72
  %t73 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t69, ptr %t73
  %t74 = call ptr @v__apply__df_mapIO_20(ptr %t6, ptr %t66)
  call void @__free_recursive(ptr %t65)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t74, ptr %t2
  br label %tco.exit.1
tco.case.arm.10.75:
  %t76 = getelementptr ptr, ptr %t5, i32 1
  %t77 = load ptr, ptr %t76
  call void @__inc_ref(ptr %t77)
  call void @__inc_ref(ptr %t6)
  %t78 = call ptr @__alloc(i64 16, i32 1)
  %t79 = inttoptr i64 10 to ptr
  %t80 = getelementptr ptr, ptr %t78, i32 0
  store ptr %t79, ptr %t80
  %t81 = call ptr @__alloc(i64 16, i32 1)
  %t82 = inttoptr i64 29 to ptr
  %t83 = getelementptr ptr, ptr %t81, i32 0
  store ptr %t82, ptr %t83
  call void @__inc_ref(ptr %t77)
  %t84 = getelementptr ptr, ptr %t81, i32 1
  store ptr %t77, ptr %t84
  %t85 = getelementptr ptr, ptr %t78, i32 1
  store ptr %t81, ptr %t85
  %t86 = call ptr @v__apply__df_mapIO_20(ptr %t6, ptr %t78)
  call void @__free_recursive(ptr %t77)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t86, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t87 = load ptr, ptr %t2
  ret ptr %t87
}

define internal ptr @v__apply__df_mapIO_20(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 154, label %tco.case.arm.154.11 i64 155, label %tco.case.arm.155.12 ]
tco.case.arm.154.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.155.12:
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

define internal ptr @v__df_handleErrorIO_24(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 156 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_handleErrorIO_24(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_handleErrorIO_24(ptr %v_io, ptr %v__k) {
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
  %t18 = call ptr @v__apply__df_handleErrorIO_24(ptr %t6, ptr %t14)
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
  %t22 = call ptr @v_handlerABC(ptr %t21)
  %t23 = call ptr @v__apply__df_handleErrorIO_24(ptr %t6, ptr %t22)
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
  %t39 = inttoptr i64 157 to ptr
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
  %t42 = inttoptr i64 157 to ptr
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
  %t54 = inttoptr i64 40 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  call void @__inc_ref(ptr %t49)
  %t56 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t49, ptr %t56
  %t57 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t53, ptr %t57
  %t58 = call ptr @v__apply__df_handleErrorIO_24(ptr %t6, ptr %t50)
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
  %t66 = inttoptr i64 42 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  call void @__inc_ref(ptr %t61)
  %t68 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t61, ptr %t68
  %t69 = getelementptr ptr, ptr %t62, i32 1
  store ptr %t65, ptr %t69
  %t70 = call ptr @v__apply__df_handleErrorIO_24(ptr %t6, ptr %t62)
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
  %t78 = inttoptr i64 44 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  call void @__inc_ref(ptr %t73)
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t73, ptr %t80
  %t81 = getelementptr ptr, ptr %t74, i32 1
  store ptr %t77, ptr %t81
  %t82 = call ptr @v__apply__df_handleErrorIO_24(ptr %t6, ptr %t74)
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

define internal ptr @v__apply__df_handleErrorIO_24(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 156, label %tco.case.arm.156.11 i64 157, label %tco.case.arm.157.12 ]
tco.case.arm.156.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.157.12:
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

define internal ptr @v__df__rowmono_1_andThenIO_28(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 158 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df__rowmono_1_andThenIO_28(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df__rowmono_1_andThenIO_28(ptr %v_io, ptr %v__k) {
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
  %t15 = call ptr @v__lift_32(ptr %t14)
  %t16 = call ptr @v__apply__df__rowmono_1_andThenIO_28(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df__rowmono_1_andThenIO_28(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 159 to ptr
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
  %t43 = inttoptr i64 159 to ptr
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
  %t55 = inttoptr i64 48 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df__rowmono_1_andThenIO_28(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 49 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df__rowmono_1_andThenIO_28(ptr %t6, ptr %t63)
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
  %t79 = inttoptr i64 50 to ptr
  %t80 = getelementptr ptr, ptr %t78, i32 0
  store ptr %t79, ptr %t80
  call void @__inc_ref(ptr %t74)
  %t81 = getelementptr ptr, ptr %t78, i32 1
  store ptr %t74, ptr %t81
  %t82 = getelementptr ptr, ptr %t75, i32 1
  store ptr %t78, ptr %t82
  %t83 = call ptr @v__apply__df__rowmono_1_andThenIO_28(ptr %t6, ptr %t75)
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

define internal ptr @v__apply__df__rowmono_1_andThenIO_28(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 158, label %tco.case.arm.158.11 i64 159, label %tco.case.arm.159.12 ]
tco.case.arm.158.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.159.12:
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

define internal ptr @v__df_andThenIO_32(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 160 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_32(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_32(ptr %v_io, ptr %v__k) {
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
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_32(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_32(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 161 to ptr
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
  %t43 = inttoptr i64 161 to ptr
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
  %t55 = inttoptr i64 51 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df_andThenIO_32(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 58 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df_andThenIO_32(ptr %t6, ptr %t63)
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
  %t79 = inttoptr i64 65 to ptr
  %t80 = getelementptr ptr, ptr %t78, i32 0
  store ptr %t79, ptr %t80
  call void @__inc_ref(ptr %t74)
  %t81 = getelementptr ptr, ptr %t78, i32 1
  store ptr %t74, ptr %t81
  %t82 = getelementptr ptr, ptr %t75, i32 1
  store ptr %t78, ptr %t82
  %t83 = call ptr @v__apply__df_andThenIO_32(ptr %t6, ptr %t75)
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

define internal ptr @v__apply__df_andThenIO_32(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 160, label %tco.case.arm.160.11 i64 161, label %tco.case.arm.161.12 ]
tco.case.arm.160.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.161.12:
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

define internal ptr @v__df_andThenIO_36(ptr %v_io, ptr %v__df_andThenIO_36_cap0_0) {
  call void @__inc_ref(ptr %v_io)
  call void @__inc_ref(ptr %v__df_andThenIO_36_cap0_0)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 162 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_36(ptr %v_io, ptr %v__df_andThenIO_36_cap0_0, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  call void @__free_recursive(ptr %v__df_andThenIO_36_cap0_0)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_36(ptr %v_io, ptr %v__df_andThenIO_36_cap0_0, ptr %v__k) {
entry:
  %t3 = alloca ptr
  store ptr %v_io, ptr %t3
  %t4 = alloca ptr
  store ptr %v__df_andThenIO_36_cap0_0, ptr %t4
  %t5 = alloca ptr
  store ptr %v__k, ptr %t5
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t6 = load ptr, ptr %t3
  %t7 = load ptr, ptr %t4
  %t8 = load ptr, ptr %t5
  %t9 = getelementptr ptr, ptr %t6, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %tco.case.default.12 [ i64 5, label %tco.case.arm.5.13 i64 6, label %tco.case.arm.6.19 i64 7, label %tco.case.arm.7.27 i64 8, label %tco.case.arm.8.50 i64 9, label %tco.case.arm.9.63 i64 10, label %tco.case.arm.10.76 ]
tco.case.arm.5.13:
  %t14 = getelementptr ptr, ptr %t6, i32 1
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  call void @__inc_ref(ptr %t8)
  call void @__inc_ref(ptr %t7)
  call void @__inc_ref(ptr %t15)
  %t16 = call ptr @v__lam_19(ptr %t7, ptr %t15)
  %t17 = call ptr @v__lift_1(ptr %t16)
  %t18 = call ptr @v__apply__df_andThenIO_36(ptr %t8, ptr %t17)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t7)
  call void @__free_recursive(ptr %t8)
  store ptr %t18, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.19:
  %t20 = getelementptr ptr, ptr %t6, i32 1
  %t21 = load ptr, ptr %t20
  call void @__inc_ref(ptr %t21)
  call void @__inc_ref(ptr %t8)
  %t22 = call ptr @__alloc(i64 16, i32 1)
  %t23 = inttoptr i64 6 to ptr
  %t24 = getelementptr ptr, ptr %t22, i32 0
  store ptr %t23, ptr %t24
  call void @__inc_ref(ptr %t21)
  %t25 = getelementptr ptr, ptr %t22, i32 1
  store ptr %t21, ptr %t25
  %t26 = call ptr @v__apply__df_andThenIO_36(ptr %t8, ptr %t22)
  call void @__free_recursive(ptr %t21)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t7)
  call void @__free_recursive(ptr %t8)
  store ptr %t26, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.27:
  %t28 = getelementptr ptr, ptr %t6, i32 1
  %t29 = load ptr, ptr %t28
  %t30 = getelementptr ptr, ptr %t6, i32 2
  %t31 = load ptr, ptr %t30
  call void @__inc_ref(ptr %t31)
  %t32 = getelementptr i8, ptr %t6, i64 -8
  %t33 = load i32, ptr %t32
  %t34 = icmp eq i32 %t33, 1
  br i1 %t34, label %reuse.in_place.35, label %reuse.copy.36
reuse.in_place.35:
  %t38 = getelementptr ptr, ptr %t6, i32 2
  %t39 = load ptr, ptr %t38
  call void @__free_recursive(ptr %t39)
  %t42 = inttoptr i64 163 to ptr
  %t43 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t42, ptr %t43
  call void @__inc_ref(ptr %t8)
  %t40 = getelementptr ptr, ptr %t6, i32 1
  store ptr %t8, ptr %t40
  %t41 = getelementptr ptr, ptr %t6, i32 2
  store ptr %t29, ptr %t41
  br label %reuse.join.37
reuse.copy.36:
  %t44 = call ptr @__alloc(i64 24, i32 2)
  %t45 = inttoptr i64 163 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  call void @__inc_ref(ptr %t8)
  %t47 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t8, ptr %t47
  call void @__inc_ref(ptr %t29)
  %t48 = getelementptr ptr, ptr %t44, i32 2
  store ptr %t29, ptr %t48
  call void @__free_recursive(ptr %t6)
  br label %reuse.join.37
reuse.join.37:
  %t49 = phi ptr [ %t6, %reuse.in_place.35 ], [ %t44, %reuse.copy.36 ]
  call void @__inc_ref(ptr %t31)
  call void @__inc_ref(ptr %t7)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t7)
  call void @__free_recursive(ptr %t31)
  store ptr %t31, ptr %t3
  store ptr %t7, ptr %t4
  store ptr %t49, ptr %t5
  br label %tco.loop.0
tco.case.arm.8.50:
  %t51 = getelementptr ptr, ptr %t6, i32 1
  %t52 = load ptr, ptr %t51
  call void @__inc_ref(ptr %t52)
  call void @__inc_ref(ptr %t8)
  %t53 = call ptr @__alloc(i64 16, i32 1)
  %t54 = inttoptr i64 8 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  %t56 = call ptr @__alloc(i64 24, i32 2)
  %t57 = inttoptr i64 52 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  call void @__inc_ref(ptr %t52)
  %t59 = getelementptr ptr, ptr %t56, i32 1
  store ptr %t52, ptr %t59
  call void @__inc_ref(ptr %t7)
  %t60 = getelementptr ptr, ptr %t56, i32 2
  store ptr %t7, ptr %t60
  %t61 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t56, ptr %t61
  %t62 = call ptr @v__apply__df_andThenIO_36(ptr %t8, ptr %t53)
  call void @__free_recursive(ptr %t52)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t7)
  call void @__free_recursive(ptr %t8)
  store ptr %t62, ptr %t2
  br label %tco.exit.1
tco.case.arm.9.63:
  %t64 = getelementptr ptr, ptr %t6, i32 1
  %t65 = load ptr, ptr %t64
  call void @__inc_ref(ptr %t65)
  call void @__inc_ref(ptr %t8)
  %t66 = call ptr @__alloc(i64 16, i32 1)
  %t67 = inttoptr i64 9 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  %t69 = call ptr @__alloc(i64 24, i32 2)
  %t70 = inttoptr i64 59 to ptr
  %t71 = getelementptr ptr, ptr %t69, i32 0
  store ptr %t70, ptr %t71
  call void @__inc_ref(ptr %t65)
  %t72 = getelementptr ptr, ptr %t69, i32 1
  store ptr %t65, ptr %t72
  call void @__inc_ref(ptr %t7)
  %t73 = getelementptr ptr, ptr %t69, i32 2
  store ptr %t7, ptr %t73
  %t74 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t69, ptr %t74
  %t75 = call ptr @v__apply__df_andThenIO_36(ptr %t8, ptr %t66)
  call void @__free_recursive(ptr %t65)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t7)
  call void @__free_recursive(ptr %t8)
  store ptr %t75, ptr %t2
  br label %tco.exit.1
tco.case.arm.10.76:
  %t77 = getelementptr ptr, ptr %t6, i32 1
  %t78 = load ptr, ptr %t77
  call void @__inc_ref(ptr %t78)
  call void @__inc_ref(ptr %t8)
  %t79 = call ptr @__alloc(i64 16, i32 1)
  %t80 = inttoptr i64 10 to ptr
  %t81 = getelementptr ptr, ptr %t79, i32 0
  store ptr %t80, ptr %t81
  %t82 = call ptr @__alloc(i64 24, i32 2)
  %t83 = inttoptr i64 66 to ptr
  %t84 = getelementptr ptr, ptr %t82, i32 0
  store ptr %t83, ptr %t84
  call void @__inc_ref(ptr %t78)
  %t85 = getelementptr ptr, ptr %t82, i32 1
  store ptr %t78, ptr %t85
  call void @__inc_ref(ptr %t7)
  %t86 = getelementptr ptr, ptr %t82, i32 2
  store ptr %t7, ptr %t86
  %t87 = getelementptr ptr, ptr %t79, i32 1
  store ptr %t82, ptr %t87
  %t88 = call ptr @v__apply__df_andThenIO_36(ptr %t8, ptr %t79)
  call void @__free_recursive(ptr %t78)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t7)
  call void @__free_recursive(ptr %t8)
  store ptr %t88, ptr %t2
  br label %tco.exit.1
tco.case.default.12:
  unreachable
tco.exit.1:
  %t89 = load ptr, ptr %t2
  ret ptr %t89
}

define internal ptr @v__apply__df_andThenIO_36(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 162, label %tco.case.arm.162.11 i64 163, label %tco.case.arm.163.12 ]
tco.case.arm.162.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.163.12:
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

define internal ptr @v__df_andThenIO_40(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 164 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_40(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_40(ptr %v_io, ptr %v__k) {
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
  %t14 = call ptr @v__lam_20(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_40(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_40(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 165 to ptr
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
  %t43 = inttoptr i64 165 to ptr
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
  %t55 = inttoptr i64 53 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df_andThenIO_40(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 60 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df_andThenIO_40(ptr %t6, ptr %t63)
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
  %t79 = inttoptr i64 67 to ptr
  %t80 = getelementptr ptr, ptr %t78, i32 0
  store ptr %t79, ptr %t80
  call void @__inc_ref(ptr %t74)
  %t81 = getelementptr ptr, ptr %t78, i32 1
  store ptr %t74, ptr %t81
  %t82 = getelementptr ptr, ptr %t75, i32 1
  store ptr %t78, ptr %t82
  %t83 = call ptr @v__apply__df_andThenIO_40(ptr %t6, ptr %t75)
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

define internal ptr @v__apply__df_andThenIO_40(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 164, label %tco.case.arm.164.11 i64 165, label %tco.case.arm.165.12 ]
tco.case.arm.164.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.165.12:
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

define internal ptr @v__df_andThenIO_44(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 166 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_44(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_44(ptr %v_io, ptr %v__k) {
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
  %t14 = call ptr @v__lam_21(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_44(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_44(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 167 to ptr
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
  %t43 = inttoptr i64 167 to ptr
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
  %t55 = inttoptr i64 54 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df_andThenIO_44(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 61 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df_andThenIO_44(ptr %t6, ptr %t63)
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
  %t79 = inttoptr i64 68 to ptr
  %t80 = getelementptr ptr, ptr %t78, i32 0
  store ptr %t79, ptr %t80
  call void @__inc_ref(ptr %t74)
  %t81 = getelementptr ptr, ptr %t78, i32 1
  store ptr %t74, ptr %t81
  %t82 = getelementptr ptr, ptr %t75, i32 1
  store ptr %t78, ptr %t82
  %t83 = call ptr @v__apply__df_andThenIO_44(ptr %t6, ptr %t75)
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

define internal ptr @v__apply__df_andThenIO_44(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 166, label %tco.case.arm.166.11 i64 167, label %tco.case.arm.167.12 ]
tco.case.arm.166.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.167.12:
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

define internal ptr @v__df_andThenIO_48(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 168 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_48(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_48(ptr %v_io, ptr %v__k) {
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
  %t14 = call ptr @v__lam_22(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_48(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_48(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 169 to ptr
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
  %t43 = inttoptr i64 169 to ptr
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
  %t55 = inttoptr i64 55 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df_andThenIO_48(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 62 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df_andThenIO_48(ptr %t6, ptr %t63)
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
  %t79 = inttoptr i64 69 to ptr
  %t80 = getelementptr ptr, ptr %t78, i32 0
  store ptr %t79, ptr %t80
  call void @__inc_ref(ptr %t74)
  %t81 = getelementptr ptr, ptr %t78, i32 1
  store ptr %t74, ptr %t81
  %t82 = getelementptr ptr, ptr %t75, i32 1
  store ptr %t78, ptr %t82
  %t83 = call ptr @v__apply__df_andThenIO_48(ptr %t6, ptr %t75)
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

define internal ptr @v__apply__df_andThenIO_48(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 168, label %tco.case.arm.168.11 i64 169, label %tco.case.arm.169.12 ]
tco.case.arm.168.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.169.12:
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

define internal ptr @v__df_andThenIO_52(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 170 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_52(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_52(ptr %v_io, ptr %v__k) {
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
  %t14 = call ptr @v__lam_23(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_52(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_52(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 171 to ptr
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
  %t43 = inttoptr i64 171 to ptr
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
  %t55 = inttoptr i64 56 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df_andThenIO_52(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 63 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df_andThenIO_52(ptr %t6, ptr %t63)
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
  %t79 = inttoptr i64 70 to ptr
  %t80 = getelementptr ptr, ptr %t78, i32 0
  store ptr %t79, ptr %t80
  call void @__inc_ref(ptr %t74)
  %t81 = getelementptr ptr, ptr %t78, i32 1
  store ptr %t74, ptr %t81
  %t82 = getelementptr ptr, ptr %t75, i32 1
  store ptr %t78, ptr %t82
  %t83 = call ptr @v__apply__df_andThenIO_52(ptr %t6, ptr %t75)
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

define internal ptr @v__apply__df_andThenIO_52(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 170, label %tco.case.arm.170.11 i64 171, label %tco.case.arm.171.12 ]
tco.case.arm.170.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.171.12:
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

define internal ptr @v__df_andThenIO_56(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 172 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_56(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_56(ptr %v_io, ptr %v__k) {
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
  %t14 = call ptr @v__lam_24(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_56(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_56(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 173 to ptr
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
  %t43 = inttoptr i64 173 to ptr
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
  %t55 = inttoptr i64 57 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df_andThenIO_56(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 64 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df_andThenIO_56(ptr %t6, ptr %t63)
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
  %t79 = inttoptr i64 71 to ptr
  %t80 = getelementptr ptr, ptr %t78, i32 0
  store ptr %t79, ptr %t80
  call void @__inc_ref(ptr %t74)
  %t81 = getelementptr ptr, ptr %t78, i32 1
  store ptr %t74, ptr %t81
  %t82 = getelementptr ptr, ptr %t75, i32 1
  store ptr %t78, ptr %t82
  %t83 = call ptr @v__apply__df_andThenIO_56(ptr %t6, ptr %t75)
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

define internal ptr @v__apply__df_andThenIO_56(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 172, label %tco.case.arm.172.11 i64 173, label %tco.case.arm.173.12 ]
tco.case.arm.172.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.173.12:
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

define internal ptr @v__scc__apply1__df__lam_10_23__df__lam_11_1__df__lam_11_5__df__lam_11_9__df__lam_12_10__df__lam_12_2__df__lam_12_6__df__lam_13_11__df__lam_13_3__df__lam_13_7__df__lam_14_13__df__lam_14_25__df__lam_15_14__df__lam_15_26__df__lam_16_15__df__lam_16_27__df__lam_29_17__df__lam_30_18__df__lam_31_19__df__lam_36_29__df__lam_37_30__df__lam_38_31__df__lam_5_33__df__lam_5_37__df__lam_5_41__df__lam_5_45__df__lam_5_49__df__lam_5_53__df__lam_5_57__df__lam_6_34__df__lam_6_38__df__lam_6_42__df__lam_6_46__df__lam_6_50__df__lam_6_54__df__lam_6_58__df__lam_7_35__df__lam_7_39__df__lam_7_43__df__lam_7_47__df__lam_7_51__df__lam_7_55__df__lam_7_59__df__lam_8_21__df__lam_9_22__lift_2__lift_26__lift_27__lift_28__lift_3__lift_33__lift_34__lift_35__lift_4(ptr %v__args) {
  call void @__inc_ref(ptr %v__args)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 174 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__scc__apply1__df__lam_10_23__df__lam_11_1__df__lam_11_5__df__lam_11_9__df__lam_12_10__df__lam_12_2__df__lam_12_6__df__lam_13_11__df__lam_13_3__df__lam_13_7__df__lam_14_13__df__lam_14_25__df__lam_15_14__df__lam_15_26__df__lam_16_15__df__lam_16_27__df__lam_29_17__df__lam_30_18__df__lam_31_19__df__lam_36_29__df__lam_37_30__df__lam_38_31__df__lam_5_33__df__lam_5_37__df__lam_5_41__df__lam_5_45__df__lam_5_49__df__lam_5_53__df__lam_5_57__df__lam_6_34__df__lam_6_38__df__lam_6_42__df__lam_6_46__df__lam_6_50__df__lam_6_54__df__lam_6_58__df__lam_7_35__df__lam_7_39__df__lam_7_43__df__lam_7_47__df__lam_7_51__df__lam_7_55__df__lam_7_59__df__lam_8_21__df__lam_9_22__lift_2__lift_26__lift_27__lift_28__lift_3__lift_33__lift_34__lift_35__lift_4(ptr %v__args, ptr %t0)
  call void @__free_recursive(ptr %v__args)
  ret ptr %t3
}

define internal ptr @v__cps__scc__apply1__df__lam_10_23__df__lam_11_1__df__lam_11_5__df__lam_11_9__df__lam_12_10__df__lam_12_2__df__lam_12_6__df__lam_13_11__df__lam_13_3__df__lam_13_7__df__lam_14_13__df__lam_14_25__df__lam_15_14__df__lam_15_26__df__lam_16_15__df__lam_16_27__df__lam_29_17__df__lam_30_18__df__lam_31_19__df__lam_36_29__df__lam_37_30__df__lam_38_31__df__lam_5_33__df__lam_5_37__df__lam_5_41__df__lam_5_45__df__lam_5_49__df__lam_5_53__df__lam_5_57__df__lam_6_34__df__lam_6_38__df__lam_6_42__df__lam_6_46__df__lam_6_50__df__lam_6_54__df__lam_6_58__df__lam_7_35__df__lam_7_39__df__lam_7_43__df__lam_7_47__df__lam_7_51__df__lam_7_55__df__lam_7_59__df__lam_8_21__df__lam_9_22__lift_2__lift_26__lift_27__lift_28__lift_3__lift_33__lift_34__lift_35__lift_4(ptr %v__args, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 83, label %tco.case.arm.83.11 i64 84, label %tco.case.arm.84.1073 i64 85, label %tco.case.arm.85.1096 i64 86, label %tco.case.arm.86.1119 i64 87, label %tco.case.arm.87.1142 i64 88, label %tco.case.arm.88.1165 i64 89, label %tco.case.arm.89.1188 i64 90, label %tco.case.arm.90.1211 i64 91, label %tco.case.arm.91.1234 i64 92, label %tco.case.arm.92.1257 i64 93, label %tco.case.arm.93.1280 i64 94, label %tco.case.arm.94.1303 i64 95, label %tco.case.arm.95.1326 i64 96, label %tco.case.arm.96.1349 i64 97, label %tco.case.arm.97.1372 i64 98, label %tco.case.arm.98.1395 i64 99, label %tco.case.arm.99.1418 i64 100, label %tco.case.arm.100.1441 i64 101, label %tco.case.arm.101.1464 i64 102, label %tco.case.arm.102.1487 i64 103, label %tco.case.arm.103.1510 i64 104, label %tco.case.arm.104.1533 i64 105, label %tco.case.arm.105.1556 i64 106, label %tco.case.arm.106.1579 i64 107, label %tco.case.arm.107.1602 i64 108, label %tco.case.arm.108.1619 i64 109, label %tco.case.arm.109.1642 i64 110, label %tco.case.arm.110.1665 i64 111, label %tco.case.arm.111.1688 i64 112, label %tco.case.arm.112.1711 i64 113, label %tco.case.arm.113.1734 i64 114, label %tco.case.arm.114.1757 i64 115, label %tco.case.arm.115.1774 i64 116, label %tco.case.arm.116.1797 i64 117, label %tco.case.arm.117.1820 i64 118, label %tco.case.arm.118.1843 i64 119, label %tco.case.arm.119.1866 i64 120, label %tco.case.arm.120.1889 i64 121, label %tco.case.arm.121.1912 i64 122, label %tco.case.arm.122.1929 i64 123, label %tco.case.arm.123.1952 i64 124, label %tco.case.arm.124.1975 i64 125, label %tco.case.arm.125.1998 i64 126, label %tco.case.arm.126.2021 i64 127, label %tco.case.arm.127.2044 i64 128, label %tco.case.arm.128.2067 i64 129, label %tco.case.arm.129.2090 i64 130, label %tco.case.arm.130.2113 i64 131, label %tco.case.arm.131.2136 i64 132, label %tco.case.arm.132.2159 i64 133, label %tco.case.arm.133.2182 i64 134, label %tco.case.arm.134.2205 i64 135, label %tco.case.arm.135.2228 i64 136, label %tco.case.arm.136.2251 i64 137, label %tco.case.arm.137.2274 ]
tco.case.arm.83.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t5, i32 2
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  %t16 = getelementptr ptr, ptr %t13, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %tco.case.default.19 [ i64 29, label %tco.case.arm.29.20 i64 30, label %tco.case.arm.30.40 i64 31, label %tco.case.arm.31.60 i64 32, label %tco.case.arm.32.80 i64 33, label %tco.case.arm.33.100 i64 34, label %tco.case.arm.34.120 i64 35, label %tco.case.arm.35.140 i64 36, label %tco.case.arm.36.160 i64 37, label %tco.case.arm.37.180 i64 38, label %tco.case.arm.38.200 i64 39, label %tco.case.arm.39.220 i64 40, label %tco.case.arm.40.240 i64 41, label %tco.case.arm.41.260 i64 42, label %tco.case.arm.42.280 i64 43, label %tco.case.arm.43.300 i64 44, label %tco.case.arm.44.320 i64 45, label %tco.case.arm.45.340 i64 46, label %tco.case.arm.46.360 i64 47, label %tco.case.arm.47.380 i64 48, label %tco.case.arm.48.400 i64 49, label %tco.case.arm.49.420 i64 50, label %tco.case.arm.50.440 i64 51, label %tco.case.arm.51.460 i64 52, label %tco.case.arm.52.480 i64 53, label %tco.case.arm.53.491 i64 54, label %tco.case.arm.54.511 i64 55, label %tco.case.arm.55.531 i64 56, label %tco.case.arm.56.551 i64 57, label %tco.case.arm.57.571 i64 58, label %tco.case.arm.58.591 i64 59, label %tco.case.arm.59.611 i64 60, label %tco.case.arm.60.622 i64 61, label %tco.case.arm.61.642 i64 62, label %tco.case.arm.62.662 i64 63, label %tco.case.arm.63.682 i64 64, label %tco.case.arm.64.702 i64 65, label %tco.case.arm.65.722 i64 66, label %tco.case.arm.66.742 i64 67, label %tco.case.arm.67.753 i64 68, label %tco.case.arm.68.773 i64 69, label %tco.case.arm.69.793 i64 70, label %tco.case.arm.70.813 i64 71, label %tco.case.arm.71.833 i64 72, label %tco.case.arm.72.853 i64 73, label %tco.case.arm.73.873 i64 74, label %tco.case.arm.74.893 i64 75, label %tco.case.arm.75.913 i64 76, label %tco.case.arm.76.933 i64 77, label %tco.case.arm.77.953 i64 78, label %tco.case.arm.78.973 i64 79, label %tco.case.arm.79.993 i64 80, label %tco.case.arm.80.1013 i64 81, label %tco.case.arm.81.1033 i64 82, label %tco.case.arm.82.1053 ]
tco.case.arm.29.20:
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
  %t32 = inttoptr i64 84 to ptr
  %t33 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t32, ptr %t33
  call void @__inc_ref(ptr %t22)
  %t31 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t22, ptr %t31
  br label %reuse.join.28
reuse.copy.27:
  %t34 = call ptr @__alloc(i64 24, i32 2)
  %t35 = inttoptr i64 84 to ptr
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
tco.case.arm.30.40:
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
  %t52 = inttoptr i64 85 to ptr
  %t53 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t52, ptr %t53
  call void @__inc_ref(ptr %t42)
  %t51 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t42, ptr %t51
  br label %reuse.join.48
reuse.copy.47:
  %t54 = call ptr @__alloc(i64 24, i32 2)
  %t55 = inttoptr i64 85 to ptr
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
tco.case.arm.31.60:
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
  %t72 = inttoptr i64 86 to ptr
  %t73 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t72, ptr %t73
  call void @__inc_ref(ptr %t62)
  %t71 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t62, ptr %t71
  br label %reuse.join.68
reuse.copy.67:
  %t74 = call ptr @__alloc(i64 24, i32 2)
  %t75 = inttoptr i64 86 to ptr
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
tco.case.arm.32.80:
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
  %t92 = inttoptr i64 87 to ptr
  %t93 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t92, ptr %t93
  call void @__inc_ref(ptr %t82)
  %t91 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t82, ptr %t91
  br label %reuse.join.88
reuse.copy.87:
  %t94 = call ptr @__alloc(i64 24, i32 2)
  %t95 = inttoptr i64 87 to ptr
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
tco.case.arm.33.100:
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
  %t112 = inttoptr i64 88 to ptr
  %t113 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t112, ptr %t113
  call void @__inc_ref(ptr %t102)
  %t111 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t102, ptr %t111
  br label %reuse.join.108
reuse.copy.107:
  %t114 = call ptr @__alloc(i64 24, i32 2)
  %t115 = inttoptr i64 88 to ptr
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
tco.case.arm.34.120:
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
  %t132 = inttoptr i64 89 to ptr
  %t133 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t132, ptr %t133
  call void @__inc_ref(ptr %t122)
  %t131 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t122, ptr %t131
  br label %reuse.join.128
reuse.copy.127:
  %t134 = call ptr @__alloc(i64 24, i32 2)
  %t135 = inttoptr i64 89 to ptr
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
tco.case.arm.35.140:
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
  %t152 = inttoptr i64 90 to ptr
  %t153 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t152, ptr %t153
  call void @__inc_ref(ptr %t142)
  %t151 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t142, ptr %t151
  br label %reuse.join.148
reuse.copy.147:
  %t154 = call ptr @__alloc(i64 24, i32 2)
  %t155 = inttoptr i64 90 to ptr
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
tco.case.arm.36.160:
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
  %t172 = inttoptr i64 91 to ptr
  %t173 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t172, ptr %t173
  call void @__inc_ref(ptr %t162)
  %t171 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t162, ptr %t171
  br label %reuse.join.168
reuse.copy.167:
  %t174 = call ptr @__alloc(i64 24, i32 2)
  %t175 = inttoptr i64 91 to ptr
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
tco.case.arm.37.180:
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
  %t192 = inttoptr i64 92 to ptr
  %t193 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t192, ptr %t193
  call void @__inc_ref(ptr %t182)
  %t191 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t182, ptr %t191
  br label %reuse.join.188
reuse.copy.187:
  %t194 = call ptr @__alloc(i64 24, i32 2)
  %t195 = inttoptr i64 92 to ptr
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
tco.case.arm.38.200:
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
  %t212 = inttoptr i64 93 to ptr
  %t213 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t212, ptr %t213
  call void @__inc_ref(ptr %t202)
  %t211 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t202, ptr %t211
  br label %reuse.join.208
reuse.copy.207:
  %t214 = call ptr @__alloc(i64 24, i32 2)
  %t215 = inttoptr i64 93 to ptr
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
tco.case.arm.39.220:
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
  %t232 = inttoptr i64 94 to ptr
  %t233 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t232, ptr %t233
  call void @__inc_ref(ptr %t222)
  %t231 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t222, ptr %t231
  br label %reuse.join.228
reuse.copy.227:
  %t234 = call ptr @__alloc(i64 24, i32 2)
  %t235 = inttoptr i64 94 to ptr
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
tco.case.arm.40.240:
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
  %t252 = inttoptr i64 95 to ptr
  %t253 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t252, ptr %t253
  call void @__inc_ref(ptr %t242)
  %t251 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t242, ptr %t251
  br label %reuse.join.248
reuse.copy.247:
  %t254 = call ptr @__alloc(i64 24, i32 2)
  %t255 = inttoptr i64 95 to ptr
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
tco.case.arm.41.260:
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
  %t272 = inttoptr i64 96 to ptr
  %t273 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t272, ptr %t273
  call void @__inc_ref(ptr %t262)
  %t271 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t262, ptr %t271
  br label %reuse.join.268
reuse.copy.267:
  %t274 = call ptr @__alloc(i64 24, i32 2)
  %t275 = inttoptr i64 96 to ptr
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
tco.case.arm.42.280:
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
  %t292 = inttoptr i64 97 to ptr
  %t293 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t292, ptr %t293
  call void @__inc_ref(ptr %t282)
  %t291 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t282, ptr %t291
  br label %reuse.join.288
reuse.copy.287:
  %t294 = call ptr @__alloc(i64 24, i32 2)
  %t295 = inttoptr i64 97 to ptr
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
tco.case.arm.43.300:
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
  %t312 = inttoptr i64 98 to ptr
  %t313 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t312, ptr %t313
  call void @__inc_ref(ptr %t302)
  %t311 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t302, ptr %t311
  br label %reuse.join.308
reuse.copy.307:
  %t314 = call ptr @__alloc(i64 24, i32 2)
  %t315 = inttoptr i64 98 to ptr
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
tco.case.arm.44.320:
  %t321 = getelementptr ptr, ptr %t13, i32 1
  %t322 = load ptr, ptr %t321
  call void @__inc_ref(ptr %t322)
  %t323 = getelementptr i8, ptr %t5, i64 -8
  %t324 = load i32, ptr %t323
  %t325 = icmp eq i32 %t324, 1
  br i1 %t325, label %reuse.in_place.326, label %reuse.copy.327
reuse.in_place.326:
  %t329 = getelementptr ptr, ptr %t5, i32 1
  %t330 = load ptr, ptr %t329
  call void @__free_recursive(ptr %t330)
  %t332 = inttoptr i64 99 to ptr
  %t333 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t332, ptr %t333
  call void @__inc_ref(ptr %t322)
  %t331 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t322, ptr %t331
  br label %reuse.join.328
reuse.copy.327:
  %t334 = call ptr @__alloc(i64 24, i32 2)
  %t335 = inttoptr i64 99 to ptr
  %t336 = getelementptr ptr, ptr %t334, i32 0
  store ptr %t335, ptr %t336
  call void @__inc_ref(ptr %t322)
  %t337 = getelementptr ptr, ptr %t334, i32 1
  store ptr %t322, ptr %t337
  call void @__inc_ref(ptr %t15)
  %t338 = getelementptr ptr, ptr %t334, i32 2
  store ptr %t15, ptr %t338
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.328
reuse.join.328:
  %t339 = phi ptr [ %t5, %reuse.in_place.326 ], [ %t334, %reuse.copy.327 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t322)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t339, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.45.340:
  %t341 = getelementptr ptr, ptr %t13, i32 1
  %t342 = load ptr, ptr %t341
  call void @__inc_ref(ptr %t342)
  %t343 = getelementptr i8, ptr %t5, i64 -8
  %t344 = load i32, ptr %t343
  %t345 = icmp eq i32 %t344, 1
  br i1 %t345, label %reuse.in_place.346, label %reuse.copy.347
reuse.in_place.346:
  %t349 = getelementptr ptr, ptr %t5, i32 1
  %t350 = load ptr, ptr %t349
  call void @__free_recursive(ptr %t350)
  %t352 = inttoptr i64 100 to ptr
  %t353 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t352, ptr %t353
  call void @__inc_ref(ptr %t342)
  %t351 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t342, ptr %t351
  br label %reuse.join.348
reuse.copy.347:
  %t354 = call ptr @__alloc(i64 24, i32 2)
  %t355 = inttoptr i64 100 to ptr
  %t356 = getelementptr ptr, ptr %t354, i32 0
  store ptr %t355, ptr %t356
  call void @__inc_ref(ptr %t342)
  %t357 = getelementptr ptr, ptr %t354, i32 1
  store ptr %t342, ptr %t357
  call void @__inc_ref(ptr %t15)
  %t358 = getelementptr ptr, ptr %t354, i32 2
  store ptr %t15, ptr %t358
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.348
reuse.join.348:
  %t359 = phi ptr [ %t5, %reuse.in_place.346 ], [ %t354, %reuse.copy.347 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t342)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t359, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.46.360:
  %t361 = getelementptr ptr, ptr %t13, i32 1
  %t362 = load ptr, ptr %t361
  call void @__inc_ref(ptr %t362)
  %t363 = getelementptr i8, ptr %t5, i64 -8
  %t364 = load i32, ptr %t363
  %t365 = icmp eq i32 %t364, 1
  br i1 %t365, label %reuse.in_place.366, label %reuse.copy.367
reuse.in_place.366:
  %t369 = getelementptr ptr, ptr %t5, i32 1
  %t370 = load ptr, ptr %t369
  call void @__free_recursive(ptr %t370)
  %t372 = inttoptr i64 101 to ptr
  %t373 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t372, ptr %t373
  call void @__inc_ref(ptr %t362)
  %t371 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t362, ptr %t371
  br label %reuse.join.368
reuse.copy.367:
  %t374 = call ptr @__alloc(i64 24, i32 2)
  %t375 = inttoptr i64 101 to ptr
  %t376 = getelementptr ptr, ptr %t374, i32 0
  store ptr %t375, ptr %t376
  call void @__inc_ref(ptr %t362)
  %t377 = getelementptr ptr, ptr %t374, i32 1
  store ptr %t362, ptr %t377
  call void @__inc_ref(ptr %t15)
  %t378 = getelementptr ptr, ptr %t374, i32 2
  store ptr %t15, ptr %t378
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.368
reuse.join.368:
  %t379 = phi ptr [ %t5, %reuse.in_place.366 ], [ %t374, %reuse.copy.367 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t362)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t379, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.47.380:
  %t381 = getelementptr ptr, ptr %t13, i32 1
  %t382 = load ptr, ptr %t381
  call void @__inc_ref(ptr %t382)
  %t383 = getelementptr i8, ptr %t5, i64 -8
  %t384 = load i32, ptr %t383
  %t385 = icmp eq i32 %t384, 1
  br i1 %t385, label %reuse.in_place.386, label %reuse.copy.387
reuse.in_place.386:
  %t389 = getelementptr ptr, ptr %t5, i32 1
  %t390 = load ptr, ptr %t389
  call void @__free_recursive(ptr %t390)
  %t392 = inttoptr i64 102 to ptr
  %t393 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t392, ptr %t393
  call void @__inc_ref(ptr %t382)
  %t391 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t382, ptr %t391
  br label %reuse.join.388
reuse.copy.387:
  %t394 = call ptr @__alloc(i64 24, i32 2)
  %t395 = inttoptr i64 102 to ptr
  %t396 = getelementptr ptr, ptr %t394, i32 0
  store ptr %t395, ptr %t396
  call void @__inc_ref(ptr %t382)
  %t397 = getelementptr ptr, ptr %t394, i32 1
  store ptr %t382, ptr %t397
  call void @__inc_ref(ptr %t15)
  %t398 = getelementptr ptr, ptr %t394, i32 2
  store ptr %t15, ptr %t398
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.388
reuse.join.388:
  %t399 = phi ptr [ %t5, %reuse.in_place.386 ], [ %t394, %reuse.copy.387 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t382)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t399, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.48.400:
  %t401 = getelementptr ptr, ptr %t13, i32 1
  %t402 = load ptr, ptr %t401
  call void @__inc_ref(ptr %t402)
  %t403 = getelementptr i8, ptr %t5, i64 -8
  %t404 = load i32, ptr %t403
  %t405 = icmp eq i32 %t404, 1
  br i1 %t405, label %reuse.in_place.406, label %reuse.copy.407
reuse.in_place.406:
  %t409 = getelementptr ptr, ptr %t5, i32 1
  %t410 = load ptr, ptr %t409
  call void @__free_recursive(ptr %t410)
  %t412 = inttoptr i64 103 to ptr
  %t413 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t412, ptr %t413
  call void @__inc_ref(ptr %t402)
  %t411 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t402, ptr %t411
  br label %reuse.join.408
reuse.copy.407:
  %t414 = call ptr @__alloc(i64 24, i32 2)
  %t415 = inttoptr i64 103 to ptr
  %t416 = getelementptr ptr, ptr %t414, i32 0
  store ptr %t415, ptr %t416
  call void @__inc_ref(ptr %t402)
  %t417 = getelementptr ptr, ptr %t414, i32 1
  store ptr %t402, ptr %t417
  call void @__inc_ref(ptr %t15)
  %t418 = getelementptr ptr, ptr %t414, i32 2
  store ptr %t15, ptr %t418
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.408
reuse.join.408:
  %t419 = phi ptr [ %t5, %reuse.in_place.406 ], [ %t414, %reuse.copy.407 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t402)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t419, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.49.420:
  %t421 = getelementptr ptr, ptr %t13, i32 1
  %t422 = load ptr, ptr %t421
  call void @__inc_ref(ptr %t422)
  %t423 = getelementptr i8, ptr %t5, i64 -8
  %t424 = load i32, ptr %t423
  %t425 = icmp eq i32 %t424, 1
  br i1 %t425, label %reuse.in_place.426, label %reuse.copy.427
reuse.in_place.426:
  %t429 = getelementptr ptr, ptr %t5, i32 1
  %t430 = load ptr, ptr %t429
  call void @__free_recursive(ptr %t430)
  %t432 = inttoptr i64 104 to ptr
  %t433 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t432, ptr %t433
  call void @__inc_ref(ptr %t422)
  %t431 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t422, ptr %t431
  br label %reuse.join.428
reuse.copy.427:
  %t434 = call ptr @__alloc(i64 24, i32 2)
  %t435 = inttoptr i64 104 to ptr
  %t436 = getelementptr ptr, ptr %t434, i32 0
  store ptr %t435, ptr %t436
  call void @__inc_ref(ptr %t422)
  %t437 = getelementptr ptr, ptr %t434, i32 1
  store ptr %t422, ptr %t437
  call void @__inc_ref(ptr %t15)
  %t438 = getelementptr ptr, ptr %t434, i32 2
  store ptr %t15, ptr %t438
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.428
reuse.join.428:
  %t439 = phi ptr [ %t5, %reuse.in_place.426 ], [ %t434, %reuse.copy.427 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t422)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t439, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.50.440:
  %t441 = getelementptr ptr, ptr %t13, i32 1
  %t442 = load ptr, ptr %t441
  call void @__inc_ref(ptr %t442)
  %t443 = getelementptr i8, ptr %t5, i64 -8
  %t444 = load i32, ptr %t443
  %t445 = icmp eq i32 %t444, 1
  br i1 %t445, label %reuse.in_place.446, label %reuse.copy.447
reuse.in_place.446:
  %t449 = getelementptr ptr, ptr %t5, i32 1
  %t450 = load ptr, ptr %t449
  call void @__free_recursive(ptr %t450)
  %t452 = inttoptr i64 105 to ptr
  %t453 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t452, ptr %t453
  call void @__inc_ref(ptr %t442)
  %t451 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t442, ptr %t451
  br label %reuse.join.448
reuse.copy.447:
  %t454 = call ptr @__alloc(i64 24, i32 2)
  %t455 = inttoptr i64 105 to ptr
  %t456 = getelementptr ptr, ptr %t454, i32 0
  store ptr %t455, ptr %t456
  call void @__inc_ref(ptr %t442)
  %t457 = getelementptr ptr, ptr %t454, i32 1
  store ptr %t442, ptr %t457
  call void @__inc_ref(ptr %t15)
  %t458 = getelementptr ptr, ptr %t454, i32 2
  store ptr %t15, ptr %t458
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.448
reuse.join.448:
  %t459 = phi ptr [ %t5, %reuse.in_place.446 ], [ %t454, %reuse.copy.447 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t442)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t459, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.51.460:
  %t461 = getelementptr ptr, ptr %t13, i32 1
  %t462 = load ptr, ptr %t461
  call void @__inc_ref(ptr %t462)
  %t463 = getelementptr i8, ptr %t5, i64 -8
  %t464 = load i32, ptr %t463
  %t465 = icmp eq i32 %t464, 1
  br i1 %t465, label %reuse.in_place.466, label %reuse.copy.467
reuse.in_place.466:
  %t469 = getelementptr ptr, ptr %t5, i32 1
  %t470 = load ptr, ptr %t469
  call void @__free_recursive(ptr %t470)
  %t472 = inttoptr i64 106 to ptr
  %t473 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t472, ptr %t473
  call void @__inc_ref(ptr %t462)
  %t471 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t462, ptr %t471
  br label %reuse.join.468
reuse.copy.467:
  %t474 = call ptr @__alloc(i64 24, i32 2)
  %t475 = inttoptr i64 106 to ptr
  %t476 = getelementptr ptr, ptr %t474, i32 0
  store ptr %t475, ptr %t476
  call void @__inc_ref(ptr %t462)
  %t477 = getelementptr ptr, ptr %t474, i32 1
  store ptr %t462, ptr %t477
  call void @__inc_ref(ptr %t15)
  %t478 = getelementptr ptr, ptr %t474, i32 2
  store ptr %t15, ptr %t478
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.468
reuse.join.468:
  %t479 = phi ptr [ %t5, %reuse.in_place.466 ], [ %t474, %reuse.copy.467 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t462)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t479, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.52.480:
  %t481 = getelementptr ptr, ptr %t13, i32 1
  %t482 = load ptr, ptr %t481
  call void @__inc_ref(ptr %t482)
  %t483 = getelementptr ptr, ptr %t13, i32 2
  %t484 = load ptr, ptr %t483
  call void @__inc_ref(ptr %t484)
  %t485 = call ptr @__alloc(i64 32, i32 3)
  %t486 = inttoptr i64 107 to ptr
  %t487 = getelementptr ptr, ptr %t485, i32 0
  store ptr %t486, ptr %t487
  call void @__inc_ref(ptr %t482)
  %t488 = getelementptr ptr, ptr %t485, i32 1
  store ptr %t482, ptr %t488
  call void @__inc_ref(ptr %t484)
  %t489 = getelementptr ptr, ptr %t485, i32 2
  store ptr %t484, ptr %t489
  call void @__inc_ref(ptr %t15)
  %t490 = getelementptr ptr, ptr %t485, i32 3
  store ptr %t15, ptr %t490
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t484)
  call void @__free_recursive(ptr %t482)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t485, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.53.491:
  %t492 = getelementptr ptr, ptr %t13, i32 1
  %t493 = load ptr, ptr %t492
  call void @__inc_ref(ptr %t493)
  %t494 = getelementptr i8, ptr %t5, i64 -8
  %t495 = load i32, ptr %t494
  %t496 = icmp eq i32 %t495, 1
  br i1 %t496, label %reuse.in_place.497, label %reuse.copy.498
reuse.in_place.497:
  %t500 = getelementptr ptr, ptr %t5, i32 1
  %t501 = load ptr, ptr %t500
  call void @__free_recursive(ptr %t501)
  %t503 = inttoptr i64 108 to ptr
  %t504 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t503, ptr %t504
  call void @__inc_ref(ptr %t493)
  %t502 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t493, ptr %t502
  br label %reuse.join.499
reuse.copy.498:
  %t505 = call ptr @__alloc(i64 24, i32 2)
  %t506 = inttoptr i64 108 to ptr
  %t507 = getelementptr ptr, ptr %t505, i32 0
  store ptr %t506, ptr %t507
  call void @__inc_ref(ptr %t493)
  %t508 = getelementptr ptr, ptr %t505, i32 1
  store ptr %t493, ptr %t508
  call void @__inc_ref(ptr %t15)
  %t509 = getelementptr ptr, ptr %t505, i32 2
  store ptr %t15, ptr %t509
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.499
reuse.join.499:
  %t510 = phi ptr [ %t5, %reuse.in_place.497 ], [ %t505, %reuse.copy.498 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t493)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t510, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.54.511:
  %t512 = getelementptr ptr, ptr %t13, i32 1
  %t513 = load ptr, ptr %t512
  call void @__inc_ref(ptr %t513)
  %t514 = getelementptr i8, ptr %t5, i64 -8
  %t515 = load i32, ptr %t514
  %t516 = icmp eq i32 %t515, 1
  br i1 %t516, label %reuse.in_place.517, label %reuse.copy.518
reuse.in_place.517:
  %t520 = getelementptr ptr, ptr %t5, i32 1
  %t521 = load ptr, ptr %t520
  call void @__free_recursive(ptr %t521)
  %t523 = inttoptr i64 109 to ptr
  %t524 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t523, ptr %t524
  call void @__inc_ref(ptr %t513)
  %t522 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t513, ptr %t522
  br label %reuse.join.519
reuse.copy.518:
  %t525 = call ptr @__alloc(i64 24, i32 2)
  %t526 = inttoptr i64 109 to ptr
  %t527 = getelementptr ptr, ptr %t525, i32 0
  store ptr %t526, ptr %t527
  call void @__inc_ref(ptr %t513)
  %t528 = getelementptr ptr, ptr %t525, i32 1
  store ptr %t513, ptr %t528
  call void @__inc_ref(ptr %t15)
  %t529 = getelementptr ptr, ptr %t525, i32 2
  store ptr %t15, ptr %t529
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.519
reuse.join.519:
  %t530 = phi ptr [ %t5, %reuse.in_place.517 ], [ %t525, %reuse.copy.518 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t513)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t530, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.55.531:
  %t532 = getelementptr ptr, ptr %t13, i32 1
  %t533 = load ptr, ptr %t532
  call void @__inc_ref(ptr %t533)
  %t534 = getelementptr i8, ptr %t5, i64 -8
  %t535 = load i32, ptr %t534
  %t536 = icmp eq i32 %t535, 1
  br i1 %t536, label %reuse.in_place.537, label %reuse.copy.538
reuse.in_place.537:
  %t540 = getelementptr ptr, ptr %t5, i32 1
  %t541 = load ptr, ptr %t540
  call void @__free_recursive(ptr %t541)
  %t543 = inttoptr i64 110 to ptr
  %t544 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t543, ptr %t544
  call void @__inc_ref(ptr %t533)
  %t542 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t533, ptr %t542
  br label %reuse.join.539
reuse.copy.538:
  %t545 = call ptr @__alloc(i64 24, i32 2)
  %t546 = inttoptr i64 110 to ptr
  %t547 = getelementptr ptr, ptr %t545, i32 0
  store ptr %t546, ptr %t547
  call void @__inc_ref(ptr %t533)
  %t548 = getelementptr ptr, ptr %t545, i32 1
  store ptr %t533, ptr %t548
  call void @__inc_ref(ptr %t15)
  %t549 = getelementptr ptr, ptr %t545, i32 2
  store ptr %t15, ptr %t549
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.539
reuse.join.539:
  %t550 = phi ptr [ %t5, %reuse.in_place.537 ], [ %t545, %reuse.copy.538 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t533)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t550, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.56.551:
  %t552 = getelementptr ptr, ptr %t13, i32 1
  %t553 = load ptr, ptr %t552
  call void @__inc_ref(ptr %t553)
  %t554 = getelementptr i8, ptr %t5, i64 -8
  %t555 = load i32, ptr %t554
  %t556 = icmp eq i32 %t555, 1
  br i1 %t556, label %reuse.in_place.557, label %reuse.copy.558
reuse.in_place.557:
  %t560 = getelementptr ptr, ptr %t5, i32 1
  %t561 = load ptr, ptr %t560
  call void @__free_recursive(ptr %t561)
  %t563 = inttoptr i64 111 to ptr
  %t564 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t563, ptr %t564
  call void @__inc_ref(ptr %t553)
  %t562 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t553, ptr %t562
  br label %reuse.join.559
reuse.copy.558:
  %t565 = call ptr @__alloc(i64 24, i32 2)
  %t566 = inttoptr i64 111 to ptr
  %t567 = getelementptr ptr, ptr %t565, i32 0
  store ptr %t566, ptr %t567
  call void @__inc_ref(ptr %t553)
  %t568 = getelementptr ptr, ptr %t565, i32 1
  store ptr %t553, ptr %t568
  call void @__inc_ref(ptr %t15)
  %t569 = getelementptr ptr, ptr %t565, i32 2
  store ptr %t15, ptr %t569
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.559
reuse.join.559:
  %t570 = phi ptr [ %t5, %reuse.in_place.557 ], [ %t565, %reuse.copy.558 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t553)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t570, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.57.571:
  %t572 = getelementptr ptr, ptr %t13, i32 1
  %t573 = load ptr, ptr %t572
  call void @__inc_ref(ptr %t573)
  %t574 = getelementptr i8, ptr %t5, i64 -8
  %t575 = load i32, ptr %t574
  %t576 = icmp eq i32 %t575, 1
  br i1 %t576, label %reuse.in_place.577, label %reuse.copy.578
reuse.in_place.577:
  %t580 = getelementptr ptr, ptr %t5, i32 1
  %t581 = load ptr, ptr %t580
  call void @__free_recursive(ptr %t581)
  %t583 = inttoptr i64 112 to ptr
  %t584 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t583, ptr %t584
  call void @__inc_ref(ptr %t573)
  %t582 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t573, ptr %t582
  br label %reuse.join.579
reuse.copy.578:
  %t585 = call ptr @__alloc(i64 24, i32 2)
  %t586 = inttoptr i64 112 to ptr
  %t587 = getelementptr ptr, ptr %t585, i32 0
  store ptr %t586, ptr %t587
  call void @__inc_ref(ptr %t573)
  %t588 = getelementptr ptr, ptr %t585, i32 1
  store ptr %t573, ptr %t588
  call void @__inc_ref(ptr %t15)
  %t589 = getelementptr ptr, ptr %t585, i32 2
  store ptr %t15, ptr %t589
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.579
reuse.join.579:
  %t590 = phi ptr [ %t5, %reuse.in_place.577 ], [ %t585, %reuse.copy.578 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t573)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t590, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.58.591:
  %t592 = getelementptr ptr, ptr %t13, i32 1
  %t593 = load ptr, ptr %t592
  call void @__inc_ref(ptr %t593)
  %t594 = getelementptr i8, ptr %t5, i64 -8
  %t595 = load i32, ptr %t594
  %t596 = icmp eq i32 %t595, 1
  br i1 %t596, label %reuse.in_place.597, label %reuse.copy.598
reuse.in_place.597:
  %t600 = getelementptr ptr, ptr %t5, i32 1
  %t601 = load ptr, ptr %t600
  call void @__free_recursive(ptr %t601)
  %t603 = inttoptr i64 113 to ptr
  %t604 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t603, ptr %t604
  call void @__inc_ref(ptr %t593)
  %t602 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t593, ptr %t602
  br label %reuse.join.599
reuse.copy.598:
  %t605 = call ptr @__alloc(i64 24, i32 2)
  %t606 = inttoptr i64 113 to ptr
  %t607 = getelementptr ptr, ptr %t605, i32 0
  store ptr %t606, ptr %t607
  call void @__inc_ref(ptr %t593)
  %t608 = getelementptr ptr, ptr %t605, i32 1
  store ptr %t593, ptr %t608
  call void @__inc_ref(ptr %t15)
  %t609 = getelementptr ptr, ptr %t605, i32 2
  store ptr %t15, ptr %t609
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.599
reuse.join.599:
  %t610 = phi ptr [ %t5, %reuse.in_place.597 ], [ %t605, %reuse.copy.598 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t593)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t610, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.59.611:
  %t612 = getelementptr ptr, ptr %t13, i32 1
  %t613 = load ptr, ptr %t612
  call void @__inc_ref(ptr %t613)
  %t614 = getelementptr ptr, ptr %t13, i32 2
  %t615 = load ptr, ptr %t614
  call void @__inc_ref(ptr %t615)
  %t616 = call ptr @__alloc(i64 32, i32 3)
  %t617 = inttoptr i64 114 to ptr
  %t618 = getelementptr ptr, ptr %t616, i32 0
  store ptr %t617, ptr %t618
  call void @__inc_ref(ptr %t613)
  %t619 = getelementptr ptr, ptr %t616, i32 1
  store ptr %t613, ptr %t619
  call void @__inc_ref(ptr %t615)
  %t620 = getelementptr ptr, ptr %t616, i32 2
  store ptr %t615, ptr %t620
  call void @__inc_ref(ptr %t15)
  %t621 = getelementptr ptr, ptr %t616, i32 3
  store ptr %t15, ptr %t621
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t615)
  call void @__free_recursive(ptr %t613)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t616, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.60.622:
  %t623 = getelementptr ptr, ptr %t13, i32 1
  %t624 = load ptr, ptr %t623
  call void @__inc_ref(ptr %t624)
  %t625 = getelementptr i8, ptr %t5, i64 -8
  %t626 = load i32, ptr %t625
  %t627 = icmp eq i32 %t626, 1
  br i1 %t627, label %reuse.in_place.628, label %reuse.copy.629
reuse.in_place.628:
  %t631 = getelementptr ptr, ptr %t5, i32 1
  %t632 = load ptr, ptr %t631
  call void @__free_recursive(ptr %t632)
  %t634 = inttoptr i64 115 to ptr
  %t635 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t634, ptr %t635
  call void @__inc_ref(ptr %t624)
  %t633 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t624, ptr %t633
  br label %reuse.join.630
reuse.copy.629:
  %t636 = call ptr @__alloc(i64 24, i32 2)
  %t637 = inttoptr i64 115 to ptr
  %t638 = getelementptr ptr, ptr %t636, i32 0
  store ptr %t637, ptr %t638
  call void @__inc_ref(ptr %t624)
  %t639 = getelementptr ptr, ptr %t636, i32 1
  store ptr %t624, ptr %t639
  call void @__inc_ref(ptr %t15)
  %t640 = getelementptr ptr, ptr %t636, i32 2
  store ptr %t15, ptr %t640
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.630
reuse.join.630:
  %t641 = phi ptr [ %t5, %reuse.in_place.628 ], [ %t636, %reuse.copy.629 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t624)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t641, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.61.642:
  %t643 = getelementptr ptr, ptr %t13, i32 1
  %t644 = load ptr, ptr %t643
  call void @__inc_ref(ptr %t644)
  %t645 = getelementptr i8, ptr %t5, i64 -8
  %t646 = load i32, ptr %t645
  %t647 = icmp eq i32 %t646, 1
  br i1 %t647, label %reuse.in_place.648, label %reuse.copy.649
reuse.in_place.648:
  %t651 = getelementptr ptr, ptr %t5, i32 1
  %t652 = load ptr, ptr %t651
  call void @__free_recursive(ptr %t652)
  %t654 = inttoptr i64 116 to ptr
  %t655 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t654, ptr %t655
  call void @__inc_ref(ptr %t644)
  %t653 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t644, ptr %t653
  br label %reuse.join.650
reuse.copy.649:
  %t656 = call ptr @__alloc(i64 24, i32 2)
  %t657 = inttoptr i64 116 to ptr
  %t658 = getelementptr ptr, ptr %t656, i32 0
  store ptr %t657, ptr %t658
  call void @__inc_ref(ptr %t644)
  %t659 = getelementptr ptr, ptr %t656, i32 1
  store ptr %t644, ptr %t659
  call void @__inc_ref(ptr %t15)
  %t660 = getelementptr ptr, ptr %t656, i32 2
  store ptr %t15, ptr %t660
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.650
reuse.join.650:
  %t661 = phi ptr [ %t5, %reuse.in_place.648 ], [ %t656, %reuse.copy.649 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t644)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t661, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.62.662:
  %t663 = getelementptr ptr, ptr %t13, i32 1
  %t664 = load ptr, ptr %t663
  call void @__inc_ref(ptr %t664)
  %t665 = getelementptr i8, ptr %t5, i64 -8
  %t666 = load i32, ptr %t665
  %t667 = icmp eq i32 %t666, 1
  br i1 %t667, label %reuse.in_place.668, label %reuse.copy.669
reuse.in_place.668:
  %t671 = getelementptr ptr, ptr %t5, i32 1
  %t672 = load ptr, ptr %t671
  call void @__free_recursive(ptr %t672)
  %t674 = inttoptr i64 117 to ptr
  %t675 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t674, ptr %t675
  call void @__inc_ref(ptr %t664)
  %t673 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t664, ptr %t673
  br label %reuse.join.670
reuse.copy.669:
  %t676 = call ptr @__alloc(i64 24, i32 2)
  %t677 = inttoptr i64 117 to ptr
  %t678 = getelementptr ptr, ptr %t676, i32 0
  store ptr %t677, ptr %t678
  call void @__inc_ref(ptr %t664)
  %t679 = getelementptr ptr, ptr %t676, i32 1
  store ptr %t664, ptr %t679
  call void @__inc_ref(ptr %t15)
  %t680 = getelementptr ptr, ptr %t676, i32 2
  store ptr %t15, ptr %t680
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.670
reuse.join.670:
  %t681 = phi ptr [ %t5, %reuse.in_place.668 ], [ %t676, %reuse.copy.669 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t664)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t681, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.63.682:
  %t683 = getelementptr ptr, ptr %t13, i32 1
  %t684 = load ptr, ptr %t683
  call void @__inc_ref(ptr %t684)
  %t685 = getelementptr i8, ptr %t5, i64 -8
  %t686 = load i32, ptr %t685
  %t687 = icmp eq i32 %t686, 1
  br i1 %t687, label %reuse.in_place.688, label %reuse.copy.689
reuse.in_place.688:
  %t691 = getelementptr ptr, ptr %t5, i32 1
  %t692 = load ptr, ptr %t691
  call void @__free_recursive(ptr %t692)
  %t694 = inttoptr i64 118 to ptr
  %t695 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t694, ptr %t695
  call void @__inc_ref(ptr %t684)
  %t693 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t684, ptr %t693
  br label %reuse.join.690
reuse.copy.689:
  %t696 = call ptr @__alloc(i64 24, i32 2)
  %t697 = inttoptr i64 118 to ptr
  %t698 = getelementptr ptr, ptr %t696, i32 0
  store ptr %t697, ptr %t698
  call void @__inc_ref(ptr %t684)
  %t699 = getelementptr ptr, ptr %t696, i32 1
  store ptr %t684, ptr %t699
  call void @__inc_ref(ptr %t15)
  %t700 = getelementptr ptr, ptr %t696, i32 2
  store ptr %t15, ptr %t700
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.690
reuse.join.690:
  %t701 = phi ptr [ %t5, %reuse.in_place.688 ], [ %t696, %reuse.copy.689 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t684)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t701, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.64.702:
  %t703 = getelementptr ptr, ptr %t13, i32 1
  %t704 = load ptr, ptr %t703
  call void @__inc_ref(ptr %t704)
  %t705 = getelementptr i8, ptr %t5, i64 -8
  %t706 = load i32, ptr %t705
  %t707 = icmp eq i32 %t706, 1
  br i1 %t707, label %reuse.in_place.708, label %reuse.copy.709
reuse.in_place.708:
  %t711 = getelementptr ptr, ptr %t5, i32 1
  %t712 = load ptr, ptr %t711
  call void @__free_recursive(ptr %t712)
  %t714 = inttoptr i64 119 to ptr
  %t715 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t714, ptr %t715
  call void @__inc_ref(ptr %t704)
  %t713 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t704, ptr %t713
  br label %reuse.join.710
reuse.copy.709:
  %t716 = call ptr @__alloc(i64 24, i32 2)
  %t717 = inttoptr i64 119 to ptr
  %t718 = getelementptr ptr, ptr %t716, i32 0
  store ptr %t717, ptr %t718
  call void @__inc_ref(ptr %t704)
  %t719 = getelementptr ptr, ptr %t716, i32 1
  store ptr %t704, ptr %t719
  call void @__inc_ref(ptr %t15)
  %t720 = getelementptr ptr, ptr %t716, i32 2
  store ptr %t15, ptr %t720
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.710
reuse.join.710:
  %t721 = phi ptr [ %t5, %reuse.in_place.708 ], [ %t716, %reuse.copy.709 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t704)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t721, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.65.722:
  %t723 = getelementptr ptr, ptr %t13, i32 1
  %t724 = load ptr, ptr %t723
  call void @__inc_ref(ptr %t724)
  %t725 = getelementptr i8, ptr %t5, i64 -8
  %t726 = load i32, ptr %t725
  %t727 = icmp eq i32 %t726, 1
  br i1 %t727, label %reuse.in_place.728, label %reuse.copy.729
reuse.in_place.728:
  %t731 = getelementptr ptr, ptr %t5, i32 1
  %t732 = load ptr, ptr %t731
  call void @__free_recursive(ptr %t732)
  %t734 = inttoptr i64 120 to ptr
  %t735 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t734, ptr %t735
  call void @__inc_ref(ptr %t724)
  %t733 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t724, ptr %t733
  br label %reuse.join.730
reuse.copy.729:
  %t736 = call ptr @__alloc(i64 24, i32 2)
  %t737 = inttoptr i64 120 to ptr
  %t738 = getelementptr ptr, ptr %t736, i32 0
  store ptr %t737, ptr %t738
  call void @__inc_ref(ptr %t724)
  %t739 = getelementptr ptr, ptr %t736, i32 1
  store ptr %t724, ptr %t739
  call void @__inc_ref(ptr %t15)
  %t740 = getelementptr ptr, ptr %t736, i32 2
  store ptr %t15, ptr %t740
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.730
reuse.join.730:
  %t741 = phi ptr [ %t5, %reuse.in_place.728 ], [ %t736, %reuse.copy.729 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t724)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t741, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.66.742:
  %t743 = getelementptr ptr, ptr %t13, i32 1
  %t744 = load ptr, ptr %t743
  call void @__inc_ref(ptr %t744)
  %t745 = getelementptr ptr, ptr %t13, i32 2
  %t746 = load ptr, ptr %t745
  call void @__inc_ref(ptr %t746)
  %t747 = call ptr @__alloc(i64 32, i32 3)
  %t748 = inttoptr i64 121 to ptr
  %t749 = getelementptr ptr, ptr %t747, i32 0
  store ptr %t748, ptr %t749
  call void @__inc_ref(ptr %t744)
  %t750 = getelementptr ptr, ptr %t747, i32 1
  store ptr %t744, ptr %t750
  call void @__inc_ref(ptr %t746)
  %t751 = getelementptr ptr, ptr %t747, i32 2
  store ptr %t746, ptr %t751
  call void @__inc_ref(ptr %t15)
  %t752 = getelementptr ptr, ptr %t747, i32 3
  store ptr %t15, ptr %t752
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t746)
  call void @__free_recursive(ptr %t744)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t747, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.67.753:
  %t754 = getelementptr ptr, ptr %t13, i32 1
  %t755 = load ptr, ptr %t754
  call void @__inc_ref(ptr %t755)
  %t756 = getelementptr i8, ptr %t5, i64 -8
  %t757 = load i32, ptr %t756
  %t758 = icmp eq i32 %t757, 1
  br i1 %t758, label %reuse.in_place.759, label %reuse.copy.760
reuse.in_place.759:
  %t762 = getelementptr ptr, ptr %t5, i32 1
  %t763 = load ptr, ptr %t762
  call void @__free_recursive(ptr %t763)
  %t765 = inttoptr i64 122 to ptr
  %t766 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t765, ptr %t766
  call void @__inc_ref(ptr %t755)
  %t764 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t755, ptr %t764
  br label %reuse.join.761
reuse.copy.760:
  %t767 = call ptr @__alloc(i64 24, i32 2)
  %t768 = inttoptr i64 122 to ptr
  %t769 = getelementptr ptr, ptr %t767, i32 0
  store ptr %t768, ptr %t769
  call void @__inc_ref(ptr %t755)
  %t770 = getelementptr ptr, ptr %t767, i32 1
  store ptr %t755, ptr %t770
  call void @__inc_ref(ptr %t15)
  %t771 = getelementptr ptr, ptr %t767, i32 2
  store ptr %t15, ptr %t771
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.761
reuse.join.761:
  %t772 = phi ptr [ %t5, %reuse.in_place.759 ], [ %t767, %reuse.copy.760 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t755)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t772, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.68.773:
  %t774 = getelementptr ptr, ptr %t13, i32 1
  %t775 = load ptr, ptr %t774
  call void @__inc_ref(ptr %t775)
  %t776 = getelementptr i8, ptr %t5, i64 -8
  %t777 = load i32, ptr %t776
  %t778 = icmp eq i32 %t777, 1
  br i1 %t778, label %reuse.in_place.779, label %reuse.copy.780
reuse.in_place.779:
  %t782 = getelementptr ptr, ptr %t5, i32 1
  %t783 = load ptr, ptr %t782
  call void @__free_recursive(ptr %t783)
  %t785 = inttoptr i64 123 to ptr
  %t786 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t785, ptr %t786
  call void @__inc_ref(ptr %t775)
  %t784 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t775, ptr %t784
  br label %reuse.join.781
reuse.copy.780:
  %t787 = call ptr @__alloc(i64 24, i32 2)
  %t788 = inttoptr i64 123 to ptr
  %t789 = getelementptr ptr, ptr %t787, i32 0
  store ptr %t788, ptr %t789
  call void @__inc_ref(ptr %t775)
  %t790 = getelementptr ptr, ptr %t787, i32 1
  store ptr %t775, ptr %t790
  call void @__inc_ref(ptr %t15)
  %t791 = getelementptr ptr, ptr %t787, i32 2
  store ptr %t15, ptr %t791
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.781
reuse.join.781:
  %t792 = phi ptr [ %t5, %reuse.in_place.779 ], [ %t787, %reuse.copy.780 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t775)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t792, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.69.793:
  %t794 = getelementptr ptr, ptr %t13, i32 1
  %t795 = load ptr, ptr %t794
  call void @__inc_ref(ptr %t795)
  %t796 = getelementptr i8, ptr %t5, i64 -8
  %t797 = load i32, ptr %t796
  %t798 = icmp eq i32 %t797, 1
  br i1 %t798, label %reuse.in_place.799, label %reuse.copy.800
reuse.in_place.799:
  %t802 = getelementptr ptr, ptr %t5, i32 1
  %t803 = load ptr, ptr %t802
  call void @__free_recursive(ptr %t803)
  %t805 = inttoptr i64 124 to ptr
  %t806 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t805, ptr %t806
  call void @__inc_ref(ptr %t795)
  %t804 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t795, ptr %t804
  br label %reuse.join.801
reuse.copy.800:
  %t807 = call ptr @__alloc(i64 24, i32 2)
  %t808 = inttoptr i64 124 to ptr
  %t809 = getelementptr ptr, ptr %t807, i32 0
  store ptr %t808, ptr %t809
  call void @__inc_ref(ptr %t795)
  %t810 = getelementptr ptr, ptr %t807, i32 1
  store ptr %t795, ptr %t810
  call void @__inc_ref(ptr %t15)
  %t811 = getelementptr ptr, ptr %t807, i32 2
  store ptr %t15, ptr %t811
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.801
reuse.join.801:
  %t812 = phi ptr [ %t5, %reuse.in_place.799 ], [ %t807, %reuse.copy.800 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t795)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t812, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.70.813:
  %t814 = getelementptr ptr, ptr %t13, i32 1
  %t815 = load ptr, ptr %t814
  call void @__inc_ref(ptr %t815)
  %t816 = getelementptr i8, ptr %t5, i64 -8
  %t817 = load i32, ptr %t816
  %t818 = icmp eq i32 %t817, 1
  br i1 %t818, label %reuse.in_place.819, label %reuse.copy.820
reuse.in_place.819:
  %t822 = getelementptr ptr, ptr %t5, i32 1
  %t823 = load ptr, ptr %t822
  call void @__free_recursive(ptr %t823)
  %t825 = inttoptr i64 125 to ptr
  %t826 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t825, ptr %t826
  call void @__inc_ref(ptr %t815)
  %t824 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t815, ptr %t824
  br label %reuse.join.821
reuse.copy.820:
  %t827 = call ptr @__alloc(i64 24, i32 2)
  %t828 = inttoptr i64 125 to ptr
  %t829 = getelementptr ptr, ptr %t827, i32 0
  store ptr %t828, ptr %t829
  call void @__inc_ref(ptr %t815)
  %t830 = getelementptr ptr, ptr %t827, i32 1
  store ptr %t815, ptr %t830
  call void @__inc_ref(ptr %t15)
  %t831 = getelementptr ptr, ptr %t827, i32 2
  store ptr %t15, ptr %t831
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.821
reuse.join.821:
  %t832 = phi ptr [ %t5, %reuse.in_place.819 ], [ %t827, %reuse.copy.820 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t815)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t832, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.71.833:
  %t834 = getelementptr ptr, ptr %t13, i32 1
  %t835 = load ptr, ptr %t834
  call void @__inc_ref(ptr %t835)
  %t836 = getelementptr i8, ptr %t5, i64 -8
  %t837 = load i32, ptr %t836
  %t838 = icmp eq i32 %t837, 1
  br i1 %t838, label %reuse.in_place.839, label %reuse.copy.840
reuse.in_place.839:
  %t842 = getelementptr ptr, ptr %t5, i32 1
  %t843 = load ptr, ptr %t842
  call void @__free_recursive(ptr %t843)
  %t845 = inttoptr i64 126 to ptr
  %t846 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t845, ptr %t846
  call void @__inc_ref(ptr %t835)
  %t844 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t835, ptr %t844
  br label %reuse.join.841
reuse.copy.840:
  %t847 = call ptr @__alloc(i64 24, i32 2)
  %t848 = inttoptr i64 126 to ptr
  %t849 = getelementptr ptr, ptr %t847, i32 0
  store ptr %t848, ptr %t849
  call void @__inc_ref(ptr %t835)
  %t850 = getelementptr ptr, ptr %t847, i32 1
  store ptr %t835, ptr %t850
  call void @__inc_ref(ptr %t15)
  %t851 = getelementptr ptr, ptr %t847, i32 2
  store ptr %t15, ptr %t851
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.841
reuse.join.841:
  %t852 = phi ptr [ %t5, %reuse.in_place.839 ], [ %t847, %reuse.copy.840 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t835)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t852, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.72.853:
  %t854 = getelementptr ptr, ptr %t13, i32 1
  %t855 = load ptr, ptr %t854
  call void @__inc_ref(ptr %t855)
  %t856 = getelementptr i8, ptr %t5, i64 -8
  %t857 = load i32, ptr %t856
  %t858 = icmp eq i32 %t857, 1
  br i1 %t858, label %reuse.in_place.859, label %reuse.copy.860
reuse.in_place.859:
  %t862 = getelementptr ptr, ptr %t5, i32 1
  %t863 = load ptr, ptr %t862
  call void @__free_recursive(ptr %t863)
  %t865 = inttoptr i64 127 to ptr
  %t866 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t865, ptr %t866
  call void @__inc_ref(ptr %t855)
  %t864 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t855, ptr %t864
  br label %reuse.join.861
reuse.copy.860:
  %t867 = call ptr @__alloc(i64 24, i32 2)
  %t868 = inttoptr i64 127 to ptr
  %t869 = getelementptr ptr, ptr %t867, i32 0
  store ptr %t868, ptr %t869
  call void @__inc_ref(ptr %t855)
  %t870 = getelementptr ptr, ptr %t867, i32 1
  store ptr %t855, ptr %t870
  call void @__inc_ref(ptr %t15)
  %t871 = getelementptr ptr, ptr %t867, i32 2
  store ptr %t15, ptr %t871
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.861
reuse.join.861:
  %t872 = phi ptr [ %t5, %reuse.in_place.859 ], [ %t867, %reuse.copy.860 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t855)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t872, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.73.873:
  %t874 = getelementptr ptr, ptr %t13, i32 1
  %t875 = load ptr, ptr %t874
  call void @__inc_ref(ptr %t875)
  %t876 = getelementptr i8, ptr %t5, i64 -8
  %t877 = load i32, ptr %t876
  %t878 = icmp eq i32 %t877, 1
  br i1 %t878, label %reuse.in_place.879, label %reuse.copy.880
reuse.in_place.879:
  %t882 = getelementptr ptr, ptr %t5, i32 1
  %t883 = load ptr, ptr %t882
  call void @__free_recursive(ptr %t883)
  %t885 = inttoptr i64 128 to ptr
  %t886 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t885, ptr %t886
  call void @__inc_ref(ptr %t875)
  %t884 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t875, ptr %t884
  br label %reuse.join.881
reuse.copy.880:
  %t887 = call ptr @__alloc(i64 24, i32 2)
  %t888 = inttoptr i64 128 to ptr
  %t889 = getelementptr ptr, ptr %t887, i32 0
  store ptr %t888, ptr %t889
  call void @__inc_ref(ptr %t875)
  %t890 = getelementptr ptr, ptr %t887, i32 1
  store ptr %t875, ptr %t890
  call void @__inc_ref(ptr %t15)
  %t891 = getelementptr ptr, ptr %t887, i32 2
  store ptr %t15, ptr %t891
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.881
reuse.join.881:
  %t892 = phi ptr [ %t5, %reuse.in_place.879 ], [ %t887, %reuse.copy.880 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t875)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t892, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.74.893:
  %t894 = getelementptr ptr, ptr %t13, i32 1
  %t895 = load ptr, ptr %t894
  call void @__inc_ref(ptr %t895)
  %t896 = getelementptr i8, ptr %t5, i64 -8
  %t897 = load i32, ptr %t896
  %t898 = icmp eq i32 %t897, 1
  br i1 %t898, label %reuse.in_place.899, label %reuse.copy.900
reuse.in_place.899:
  %t902 = getelementptr ptr, ptr %t5, i32 1
  %t903 = load ptr, ptr %t902
  call void @__free_recursive(ptr %t903)
  %t905 = inttoptr i64 129 to ptr
  %t906 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t905, ptr %t906
  call void @__inc_ref(ptr %t895)
  %t904 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t895, ptr %t904
  br label %reuse.join.901
reuse.copy.900:
  %t907 = call ptr @__alloc(i64 24, i32 2)
  %t908 = inttoptr i64 129 to ptr
  %t909 = getelementptr ptr, ptr %t907, i32 0
  store ptr %t908, ptr %t909
  call void @__inc_ref(ptr %t895)
  %t910 = getelementptr ptr, ptr %t907, i32 1
  store ptr %t895, ptr %t910
  call void @__inc_ref(ptr %t15)
  %t911 = getelementptr ptr, ptr %t907, i32 2
  store ptr %t15, ptr %t911
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.901
reuse.join.901:
  %t912 = phi ptr [ %t5, %reuse.in_place.899 ], [ %t907, %reuse.copy.900 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t895)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t912, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.75.913:
  %t914 = getelementptr ptr, ptr %t13, i32 1
  %t915 = load ptr, ptr %t914
  call void @__inc_ref(ptr %t915)
  %t916 = getelementptr i8, ptr %t5, i64 -8
  %t917 = load i32, ptr %t916
  %t918 = icmp eq i32 %t917, 1
  br i1 %t918, label %reuse.in_place.919, label %reuse.copy.920
reuse.in_place.919:
  %t922 = getelementptr ptr, ptr %t5, i32 1
  %t923 = load ptr, ptr %t922
  call void @__free_recursive(ptr %t923)
  %t925 = inttoptr i64 130 to ptr
  %t926 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t925, ptr %t926
  call void @__inc_ref(ptr %t915)
  %t924 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t915, ptr %t924
  br label %reuse.join.921
reuse.copy.920:
  %t927 = call ptr @__alloc(i64 24, i32 2)
  %t928 = inttoptr i64 130 to ptr
  %t929 = getelementptr ptr, ptr %t927, i32 0
  store ptr %t928, ptr %t929
  call void @__inc_ref(ptr %t915)
  %t930 = getelementptr ptr, ptr %t927, i32 1
  store ptr %t915, ptr %t930
  call void @__inc_ref(ptr %t15)
  %t931 = getelementptr ptr, ptr %t927, i32 2
  store ptr %t15, ptr %t931
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.921
reuse.join.921:
  %t932 = phi ptr [ %t5, %reuse.in_place.919 ], [ %t927, %reuse.copy.920 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t915)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t932, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.76.933:
  %t934 = getelementptr ptr, ptr %t13, i32 1
  %t935 = load ptr, ptr %t934
  call void @__inc_ref(ptr %t935)
  %t936 = getelementptr i8, ptr %t5, i64 -8
  %t937 = load i32, ptr %t936
  %t938 = icmp eq i32 %t937, 1
  br i1 %t938, label %reuse.in_place.939, label %reuse.copy.940
reuse.in_place.939:
  %t942 = getelementptr ptr, ptr %t5, i32 1
  %t943 = load ptr, ptr %t942
  call void @__free_recursive(ptr %t943)
  %t945 = inttoptr i64 131 to ptr
  %t946 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t945, ptr %t946
  call void @__inc_ref(ptr %t935)
  %t944 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t935, ptr %t944
  br label %reuse.join.941
reuse.copy.940:
  %t947 = call ptr @__alloc(i64 24, i32 2)
  %t948 = inttoptr i64 131 to ptr
  %t949 = getelementptr ptr, ptr %t947, i32 0
  store ptr %t948, ptr %t949
  call void @__inc_ref(ptr %t935)
  %t950 = getelementptr ptr, ptr %t947, i32 1
  store ptr %t935, ptr %t950
  call void @__inc_ref(ptr %t15)
  %t951 = getelementptr ptr, ptr %t947, i32 2
  store ptr %t15, ptr %t951
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.941
reuse.join.941:
  %t952 = phi ptr [ %t5, %reuse.in_place.939 ], [ %t947, %reuse.copy.940 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t935)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t952, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.77.953:
  %t954 = getelementptr ptr, ptr %t13, i32 1
  %t955 = load ptr, ptr %t954
  call void @__inc_ref(ptr %t955)
  %t956 = getelementptr i8, ptr %t5, i64 -8
  %t957 = load i32, ptr %t956
  %t958 = icmp eq i32 %t957, 1
  br i1 %t958, label %reuse.in_place.959, label %reuse.copy.960
reuse.in_place.959:
  %t962 = getelementptr ptr, ptr %t5, i32 1
  %t963 = load ptr, ptr %t962
  call void @__free_recursive(ptr %t963)
  %t965 = inttoptr i64 132 to ptr
  %t966 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t965, ptr %t966
  call void @__inc_ref(ptr %t955)
  %t964 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t955, ptr %t964
  br label %reuse.join.961
reuse.copy.960:
  %t967 = call ptr @__alloc(i64 24, i32 2)
  %t968 = inttoptr i64 132 to ptr
  %t969 = getelementptr ptr, ptr %t967, i32 0
  store ptr %t968, ptr %t969
  call void @__inc_ref(ptr %t955)
  %t970 = getelementptr ptr, ptr %t967, i32 1
  store ptr %t955, ptr %t970
  call void @__inc_ref(ptr %t15)
  %t971 = getelementptr ptr, ptr %t967, i32 2
  store ptr %t15, ptr %t971
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.961
reuse.join.961:
  %t972 = phi ptr [ %t5, %reuse.in_place.959 ], [ %t967, %reuse.copy.960 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t955)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t972, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.78.973:
  %t974 = getelementptr ptr, ptr %t13, i32 1
  %t975 = load ptr, ptr %t974
  call void @__inc_ref(ptr %t975)
  %t976 = getelementptr i8, ptr %t5, i64 -8
  %t977 = load i32, ptr %t976
  %t978 = icmp eq i32 %t977, 1
  br i1 %t978, label %reuse.in_place.979, label %reuse.copy.980
reuse.in_place.979:
  %t982 = getelementptr ptr, ptr %t5, i32 1
  %t983 = load ptr, ptr %t982
  call void @__free_recursive(ptr %t983)
  %t985 = inttoptr i64 133 to ptr
  %t986 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t985, ptr %t986
  call void @__inc_ref(ptr %t975)
  %t984 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t975, ptr %t984
  br label %reuse.join.981
reuse.copy.980:
  %t987 = call ptr @__alloc(i64 24, i32 2)
  %t988 = inttoptr i64 133 to ptr
  %t989 = getelementptr ptr, ptr %t987, i32 0
  store ptr %t988, ptr %t989
  call void @__inc_ref(ptr %t975)
  %t990 = getelementptr ptr, ptr %t987, i32 1
  store ptr %t975, ptr %t990
  call void @__inc_ref(ptr %t15)
  %t991 = getelementptr ptr, ptr %t987, i32 2
  store ptr %t15, ptr %t991
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.981
reuse.join.981:
  %t992 = phi ptr [ %t5, %reuse.in_place.979 ], [ %t987, %reuse.copy.980 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t975)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t992, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.79.993:
  %t994 = getelementptr ptr, ptr %t13, i32 1
  %t995 = load ptr, ptr %t994
  call void @__inc_ref(ptr %t995)
  %t996 = getelementptr i8, ptr %t5, i64 -8
  %t997 = load i32, ptr %t996
  %t998 = icmp eq i32 %t997, 1
  br i1 %t998, label %reuse.in_place.999, label %reuse.copy.1000
reuse.in_place.999:
  %t1002 = getelementptr ptr, ptr %t5, i32 1
  %t1003 = load ptr, ptr %t1002
  call void @__free_recursive(ptr %t1003)
  %t1005 = inttoptr i64 134 to ptr
  %t1006 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1005, ptr %t1006
  call void @__inc_ref(ptr %t995)
  %t1004 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t995, ptr %t1004
  br label %reuse.join.1001
reuse.copy.1000:
  %t1007 = call ptr @__alloc(i64 24, i32 2)
  %t1008 = inttoptr i64 134 to ptr
  %t1009 = getelementptr ptr, ptr %t1007, i32 0
  store ptr %t1008, ptr %t1009
  call void @__inc_ref(ptr %t995)
  %t1010 = getelementptr ptr, ptr %t1007, i32 1
  store ptr %t995, ptr %t1010
  call void @__inc_ref(ptr %t15)
  %t1011 = getelementptr ptr, ptr %t1007, i32 2
  store ptr %t15, ptr %t1011
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1001
reuse.join.1001:
  %t1012 = phi ptr [ %t5, %reuse.in_place.999 ], [ %t1007, %reuse.copy.1000 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t995)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1012, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.80.1013:
  %t1014 = getelementptr ptr, ptr %t13, i32 1
  %t1015 = load ptr, ptr %t1014
  call void @__inc_ref(ptr %t1015)
  %t1016 = getelementptr i8, ptr %t5, i64 -8
  %t1017 = load i32, ptr %t1016
  %t1018 = icmp eq i32 %t1017, 1
  br i1 %t1018, label %reuse.in_place.1019, label %reuse.copy.1020
reuse.in_place.1019:
  %t1022 = getelementptr ptr, ptr %t5, i32 1
  %t1023 = load ptr, ptr %t1022
  call void @__free_recursive(ptr %t1023)
  %t1025 = inttoptr i64 135 to ptr
  %t1026 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1025, ptr %t1026
  call void @__inc_ref(ptr %t1015)
  %t1024 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1015, ptr %t1024
  br label %reuse.join.1021
reuse.copy.1020:
  %t1027 = call ptr @__alloc(i64 24, i32 2)
  %t1028 = inttoptr i64 135 to ptr
  %t1029 = getelementptr ptr, ptr %t1027, i32 0
  store ptr %t1028, ptr %t1029
  call void @__inc_ref(ptr %t1015)
  %t1030 = getelementptr ptr, ptr %t1027, i32 1
  store ptr %t1015, ptr %t1030
  call void @__inc_ref(ptr %t15)
  %t1031 = getelementptr ptr, ptr %t1027, i32 2
  store ptr %t15, ptr %t1031
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1021
reuse.join.1021:
  %t1032 = phi ptr [ %t5, %reuse.in_place.1019 ], [ %t1027, %reuse.copy.1020 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1015)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1032, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.81.1033:
  %t1034 = getelementptr ptr, ptr %t13, i32 1
  %t1035 = load ptr, ptr %t1034
  call void @__inc_ref(ptr %t1035)
  %t1036 = getelementptr i8, ptr %t5, i64 -8
  %t1037 = load i32, ptr %t1036
  %t1038 = icmp eq i32 %t1037, 1
  br i1 %t1038, label %reuse.in_place.1039, label %reuse.copy.1040
reuse.in_place.1039:
  %t1042 = getelementptr ptr, ptr %t5, i32 1
  %t1043 = load ptr, ptr %t1042
  call void @__free_recursive(ptr %t1043)
  %t1045 = inttoptr i64 136 to ptr
  %t1046 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1045, ptr %t1046
  call void @__inc_ref(ptr %t1035)
  %t1044 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1035, ptr %t1044
  br label %reuse.join.1041
reuse.copy.1040:
  %t1047 = call ptr @__alloc(i64 24, i32 2)
  %t1048 = inttoptr i64 136 to ptr
  %t1049 = getelementptr ptr, ptr %t1047, i32 0
  store ptr %t1048, ptr %t1049
  call void @__inc_ref(ptr %t1035)
  %t1050 = getelementptr ptr, ptr %t1047, i32 1
  store ptr %t1035, ptr %t1050
  call void @__inc_ref(ptr %t15)
  %t1051 = getelementptr ptr, ptr %t1047, i32 2
  store ptr %t15, ptr %t1051
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1041
reuse.join.1041:
  %t1052 = phi ptr [ %t5, %reuse.in_place.1039 ], [ %t1047, %reuse.copy.1040 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1035)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1052, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.82.1053:
  %t1054 = getelementptr ptr, ptr %t13, i32 1
  %t1055 = load ptr, ptr %t1054
  call void @__inc_ref(ptr %t1055)
  %t1056 = getelementptr i8, ptr %t5, i64 -8
  %t1057 = load i32, ptr %t1056
  %t1058 = icmp eq i32 %t1057, 1
  br i1 %t1058, label %reuse.in_place.1059, label %reuse.copy.1060
reuse.in_place.1059:
  %t1062 = getelementptr ptr, ptr %t5, i32 1
  %t1063 = load ptr, ptr %t1062
  call void @__free_recursive(ptr %t1063)
  %t1065 = inttoptr i64 137 to ptr
  %t1066 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1065, ptr %t1066
  call void @__inc_ref(ptr %t1055)
  %t1064 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1055, ptr %t1064
  br label %reuse.join.1061
reuse.copy.1060:
  %t1067 = call ptr @__alloc(i64 24, i32 2)
  %t1068 = inttoptr i64 137 to ptr
  %t1069 = getelementptr ptr, ptr %t1067, i32 0
  store ptr %t1068, ptr %t1069
  call void @__inc_ref(ptr %t1055)
  %t1070 = getelementptr ptr, ptr %t1067, i32 1
  store ptr %t1055, ptr %t1070
  call void @__inc_ref(ptr %t15)
  %t1071 = getelementptr ptr, ptr %t1067, i32 2
  store ptr %t15, ptr %t1071
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1061
reuse.join.1061:
  %t1072 = phi ptr [ %t5, %reuse.in_place.1059 ], [ %t1067, %reuse.copy.1060 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1055)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1072, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.default.19:
  unreachable
tco.case.arm.84.1073:
  %t1074 = getelementptr ptr, ptr %t5, i32 1
  %t1075 = load ptr, ptr %t1074
  %t1076 = getelementptr ptr, ptr %t5, i32 2
  %t1077 = load ptr, ptr %t1076
  %t1078 = getelementptr i8, ptr %t5, i64 -8
  %t1079 = load i32, ptr %t1078
  %t1080 = icmp eq i32 %t1079, 1
  br i1 %t1080, label %reuse.in_place.1081, label %reuse.copy.1082
reuse.in_place.1081:
  %t1084 = inttoptr i64 83 to ptr
  %t1085 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1084, ptr %t1085
  br label %reuse.join.1083
reuse.copy.1082:
  %t1086 = call ptr @__alloc(i64 24, i32 2)
  %t1087 = inttoptr i64 83 to ptr
  %t1088 = getelementptr ptr, ptr %t1086, i32 0
  store ptr %t1087, ptr %t1088
  call void @__inc_ref(ptr %t1075)
  %t1089 = getelementptr ptr, ptr %t1086, i32 1
  store ptr %t1075, ptr %t1089
  call void @__inc_ref(ptr %t1077)
  %t1090 = getelementptr ptr, ptr %t1086, i32 2
  store ptr %t1077, ptr %t1090
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1083
reuse.join.1083:
  %t1091 = phi ptr [ %t5, %reuse.in_place.1081 ], [ %t1086, %reuse.copy.1082 ]
  %t1092 = call ptr @__alloc(i64 16, i32 1)
  %t1093 = inttoptr i64 175 to ptr
  %t1094 = getelementptr ptr, ptr %t1092, i32 0
  store ptr %t1093, ptr %t1094
  call void @__inc_ref(ptr %t6)
  %t1095 = getelementptr ptr, ptr %t1092, i32 1
  store ptr %t6, ptr %t1095
  call void @__free_recursive(ptr %t6)
  store ptr %t1091, ptr %t3
  store ptr %t1092, ptr %t4
  br label %tco.loop.0
tco.case.arm.85.1096:
  %t1097 = getelementptr ptr, ptr %t5, i32 1
  %t1098 = load ptr, ptr %t1097
  %t1099 = getelementptr ptr, ptr %t5, i32 2
  %t1100 = load ptr, ptr %t1099
  %t1101 = getelementptr i8, ptr %t5, i64 -8
  %t1102 = load i32, ptr %t1101
  %t1103 = icmp eq i32 %t1102, 1
  br i1 %t1103, label %reuse.in_place.1104, label %reuse.copy.1105
reuse.in_place.1104:
  %t1107 = inttoptr i64 83 to ptr
  %t1108 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1107, ptr %t1108
  br label %reuse.join.1106
reuse.copy.1105:
  %t1109 = call ptr @__alloc(i64 24, i32 2)
  %t1110 = inttoptr i64 83 to ptr
  %t1111 = getelementptr ptr, ptr %t1109, i32 0
  store ptr %t1110, ptr %t1111
  call void @__inc_ref(ptr %t1098)
  %t1112 = getelementptr ptr, ptr %t1109, i32 1
  store ptr %t1098, ptr %t1112
  call void @__inc_ref(ptr %t1100)
  %t1113 = getelementptr ptr, ptr %t1109, i32 2
  store ptr %t1100, ptr %t1113
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1106
reuse.join.1106:
  %t1114 = phi ptr [ %t5, %reuse.in_place.1104 ], [ %t1109, %reuse.copy.1105 ]
  %t1115 = call ptr @__alloc(i64 16, i32 1)
  %t1116 = inttoptr i64 176 to ptr
  %t1117 = getelementptr ptr, ptr %t1115, i32 0
  store ptr %t1116, ptr %t1117
  call void @__inc_ref(ptr %t6)
  %t1118 = getelementptr ptr, ptr %t1115, i32 1
  store ptr %t6, ptr %t1118
  call void @__free_recursive(ptr %t6)
  store ptr %t1114, ptr %t3
  store ptr %t1115, ptr %t4
  br label %tco.loop.0
tco.case.arm.86.1119:
  %t1120 = getelementptr ptr, ptr %t5, i32 1
  %t1121 = load ptr, ptr %t1120
  %t1122 = getelementptr ptr, ptr %t5, i32 2
  %t1123 = load ptr, ptr %t1122
  %t1124 = getelementptr i8, ptr %t5, i64 -8
  %t1125 = load i32, ptr %t1124
  %t1126 = icmp eq i32 %t1125, 1
  br i1 %t1126, label %reuse.in_place.1127, label %reuse.copy.1128
reuse.in_place.1127:
  %t1130 = inttoptr i64 83 to ptr
  %t1131 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1130, ptr %t1131
  br label %reuse.join.1129
reuse.copy.1128:
  %t1132 = call ptr @__alloc(i64 24, i32 2)
  %t1133 = inttoptr i64 83 to ptr
  %t1134 = getelementptr ptr, ptr %t1132, i32 0
  store ptr %t1133, ptr %t1134
  call void @__inc_ref(ptr %t1121)
  %t1135 = getelementptr ptr, ptr %t1132, i32 1
  store ptr %t1121, ptr %t1135
  call void @__inc_ref(ptr %t1123)
  %t1136 = getelementptr ptr, ptr %t1132, i32 2
  store ptr %t1123, ptr %t1136
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1129
reuse.join.1129:
  %t1137 = phi ptr [ %t5, %reuse.in_place.1127 ], [ %t1132, %reuse.copy.1128 ]
  %t1138 = call ptr @__alloc(i64 16, i32 1)
  %t1139 = inttoptr i64 177 to ptr
  %t1140 = getelementptr ptr, ptr %t1138, i32 0
  store ptr %t1139, ptr %t1140
  call void @__inc_ref(ptr %t6)
  %t1141 = getelementptr ptr, ptr %t1138, i32 1
  store ptr %t6, ptr %t1141
  call void @__free_recursive(ptr %t6)
  store ptr %t1137, ptr %t3
  store ptr %t1138, ptr %t4
  br label %tco.loop.0
tco.case.arm.87.1142:
  %t1143 = getelementptr ptr, ptr %t5, i32 1
  %t1144 = load ptr, ptr %t1143
  %t1145 = getelementptr ptr, ptr %t5, i32 2
  %t1146 = load ptr, ptr %t1145
  %t1147 = getelementptr i8, ptr %t5, i64 -8
  %t1148 = load i32, ptr %t1147
  %t1149 = icmp eq i32 %t1148, 1
  br i1 %t1149, label %reuse.in_place.1150, label %reuse.copy.1151
reuse.in_place.1150:
  %t1153 = inttoptr i64 83 to ptr
  %t1154 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1153, ptr %t1154
  br label %reuse.join.1152
reuse.copy.1151:
  %t1155 = call ptr @__alloc(i64 24, i32 2)
  %t1156 = inttoptr i64 83 to ptr
  %t1157 = getelementptr ptr, ptr %t1155, i32 0
  store ptr %t1156, ptr %t1157
  call void @__inc_ref(ptr %t1144)
  %t1158 = getelementptr ptr, ptr %t1155, i32 1
  store ptr %t1144, ptr %t1158
  call void @__inc_ref(ptr %t1146)
  %t1159 = getelementptr ptr, ptr %t1155, i32 2
  store ptr %t1146, ptr %t1159
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1152
reuse.join.1152:
  %t1160 = phi ptr [ %t5, %reuse.in_place.1150 ], [ %t1155, %reuse.copy.1151 ]
  %t1161 = call ptr @__alloc(i64 16, i32 1)
  %t1162 = inttoptr i64 178 to ptr
  %t1163 = getelementptr ptr, ptr %t1161, i32 0
  store ptr %t1162, ptr %t1163
  call void @__inc_ref(ptr %t6)
  %t1164 = getelementptr ptr, ptr %t1161, i32 1
  store ptr %t6, ptr %t1164
  call void @__free_recursive(ptr %t6)
  store ptr %t1160, ptr %t3
  store ptr %t1161, ptr %t4
  br label %tco.loop.0
tco.case.arm.88.1165:
  %t1166 = getelementptr ptr, ptr %t5, i32 1
  %t1167 = load ptr, ptr %t1166
  %t1168 = getelementptr ptr, ptr %t5, i32 2
  %t1169 = load ptr, ptr %t1168
  %t1170 = getelementptr i8, ptr %t5, i64 -8
  %t1171 = load i32, ptr %t1170
  %t1172 = icmp eq i32 %t1171, 1
  br i1 %t1172, label %reuse.in_place.1173, label %reuse.copy.1174
reuse.in_place.1173:
  %t1176 = inttoptr i64 83 to ptr
  %t1177 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1176, ptr %t1177
  br label %reuse.join.1175
reuse.copy.1174:
  %t1178 = call ptr @__alloc(i64 24, i32 2)
  %t1179 = inttoptr i64 83 to ptr
  %t1180 = getelementptr ptr, ptr %t1178, i32 0
  store ptr %t1179, ptr %t1180
  call void @__inc_ref(ptr %t1167)
  %t1181 = getelementptr ptr, ptr %t1178, i32 1
  store ptr %t1167, ptr %t1181
  call void @__inc_ref(ptr %t1169)
  %t1182 = getelementptr ptr, ptr %t1178, i32 2
  store ptr %t1169, ptr %t1182
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1175
reuse.join.1175:
  %t1183 = phi ptr [ %t5, %reuse.in_place.1173 ], [ %t1178, %reuse.copy.1174 ]
  %t1184 = call ptr @__alloc(i64 16, i32 1)
  %t1185 = inttoptr i64 179 to ptr
  %t1186 = getelementptr ptr, ptr %t1184, i32 0
  store ptr %t1185, ptr %t1186
  call void @__inc_ref(ptr %t6)
  %t1187 = getelementptr ptr, ptr %t1184, i32 1
  store ptr %t6, ptr %t1187
  call void @__free_recursive(ptr %t6)
  store ptr %t1183, ptr %t3
  store ptr %t1184, ptr %t4
  br label %tco.loop.0
tco.case.arm.89.1188:
  %t1189 = getelementptr ptr, ptr %t5, i32 1
  %t1190 = load ptr, ptr %t1189
  %t1191 = getelementptr ptr, ptr %t5, i32 2
  %t1192 = load ptr, ptr %t1191
  %t1193 = getelementptr i8, ptr %t5, i64 -8
  %t1194 = load i32, ptr %t1193
  %t1195 = icmp eq i32 %t1194, 1
  br i1 %t1195, label %reuse.in_place.1196, label %reuse.copy.1197
reuse.in_place.1196:
  %t1199 = inttoptr i64 83 to ptr
  %t1200 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1199, ptr %t1200
  br label %reuse.join.1198
reuse.copy.1197:
  %t1201 = call ptr @__alloc(i64 24, i32 2)
  %t1202 = inttoptr i64 83 to ptr
  %t1203 = getelementptr ptr, ptr %t1201, i32 0
  store ptr %t1202, ptr %t1203
  call void @__inc_ref(ptr %t1190)
  %t1204 = getelementptr ptr, ptr %t1201, i32 1
  store ptr %t1190, ptr %t1204
  call void @__inc_ref(ptr %t1192)
  %t1205 = getelementptr ptr, ptr %t1201, i32 2
  store ptr %t1192, ptr %t1205
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1198
reuse.join.1198:
  %t1206 = phi ptr [ %t5, %reuse.in_place.1196 ], [ %t1201, %reuse.copy.1197 ]
  %t1207 = call ptr @__alloc(i64 16, i32 1)
  %t1208 = inttoptr i64 180 to ptr
  %t1209 = getelementptr ptr, ptr %t1207, i32 0
  store ptr %t1208, ptr %t1209
  call void @__inc_ref(ptr %t6)
  %t1210 = getelementptr ptr, ptr %t1207, i32 1
  store ptr %t6, ptr %t1210
  call void @__free_recursive(ptr %t6)
  store ptr %t1206, ptr %t3
  store ptr %t1207, ptr %t4
  br label %tco.loop.0
tco.case.arm.90.1211:
  %t1212 = getelementptr ptr, ptr %t5, i32 1
  %t1213 = load ptr, ptr %t1212
  %t1214 = getelementptr ptr, ptr %t5, i32 2
  %t1215 = load ptr, ptr %t1214
  %t1216 = getelementptr i8, ptr %t5, i64 -8
  %t1217 = load i32, ptr %t1216
  %t1218 = icmp eq i32 %t1217, 1
  br i1 %t1218, label %reuse.in_place.1219, label %reuse.copy.1220
reuse.in_place.1219:
  %t1222 = inttoptr i64 83 to ptr
  %t1223 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1222, ptr %t1223
  br label %reuse.join.1221
reuse.copy.1220:
  %t1224 = call ptr @__alloc(i64 24, i32 2)
  %t1225 = inttoptr i64 83 to ptr
  %t1226 = getelementptr ptr, ptr %t1224, i32 0
  store ptr %t1225, ptr %t1226
  call void @__inc_ref(ptr %t1213)
  %t1227 = getelementptr ptr, ptr %t1224, i32 1
  store ptr %t1213, ptr %t1227
  call void @__inc_ref(ptr %t1215)
  %t1228 = getelementptr ptr, ptr %t1224, i32 2
  store ptr %t1215, ptr %t1228
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1221
reuse.join.1221:
  %t1229 = phi ptr [ %t5, %reuse.in_place.1219 ], [ %t1224, %reuse.copy.1220 ]
  %t1230 = call ptr @__alloc(i64 16, i32 1)
  %t1231 = inttoptr i64 181 to ptr
  %t1232 = getelementptr ptr, ptr %t1230, i32 0
  store ptr %t1231, ptr %t1232
  call void @__inc_ref(ptr %t6)
  %t1233 = getelementptr ptr, ptr %t1230, i32 1
  store ptr %t6, ptr %t1233
  call void @__free_recursive(ptr %t6)
  store ptr %t1229, ptr %t3
  store ptr %t1230, ptr %t4
  br label %tco.loop.0
tco.case.arm.91.1234:
  %t1235 = getelementptr ptr, ptr %t5, i32 1
  %t1236 = load ptr, ptr %t1235
  %t1237 = getelementptr ptr, ptr %t5, i32 2
  %t1238 = load ptr, ptr %t1237
  %t1239 = getelementptr i8, ptr %t5, i64 -8
  %t1240 = load i32, ptr %t1239
  %t1241 = icmp eq i32 %t1240, 1
  br i1 %t1241, label %reuse.in_place.1242, label %reuse.copy.1243
reuse.in_place.1242:
  %t1245 = inttoptr i64 83 to ptr
  %t1246 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1245, ptr %t1246
  br label %reuse.join.1244
reuse.copy.1243:
  %t1247 = call ptr @__alloc(i64 24, i32 2)
  %t1248 = inttoptr i64 83 to ptr
  %t1249 = getelementptr ptr, ptr %t1247, i32 0
  store ptr %t1248, ptr %t1249
  call void @__inc_ref(ptr %t1236)
  %t1250 = getelementptr ptr, ptr %t1247, i32 1
  store ptr %t1236, ptr %t1250
  call void @__inc_ref(ptr %t1238)
  %t1251 = getelementptr ptr, ptr %t1247, i32 2
  store ptr %t1238, ptr %t1251
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1244
reuse.join.1244:
  %t1252 = phi ptr [ %t5, %reuse.in_place.1242 ], [ %t1247, %reuse.copy.1243 ]
  %t1253 = call ptr @__alloc(i64 16, i32 1)
  %t1254 = inttoptr i64 182 to ptr
  %t1255 = getelementptr ptr, ptr %t1253, i32 0
  store ptr %t1254, ptr %t1255
  call void @__inc_ref(ptr %t6)
  %t1256 = getelementptr ptr, ptr %t1253, i32 1
  store ptr %t6, ptr %t1256
  call void @__free_recursive(ptr %t6)
  store ptr %t1252, ptr %t3
  store ptr %t1253, ptr %t4
  br label %tco.loop.0
tco.case.arm.92.1257:
  %t1258 = getelementptr ptr, ptr %t5, i32 1
  %t1259 = load ptr, ptr %t1258
  %t1260 = getelementptr ptr, ptr %t5, i32 2
  %t1261 = load ptr, ptr %t1260
  %t1262 = getelementptr i8, ptr %t5, i64 -8
  %t1263 = load i32, ptr %t1262
  %t1264 = icmp eq i32 %t1263, 1
  br i1 %t1264, label %reuse.in_place.1265, label %reuse.copy.1266
reuse.in_place.1265:
  %t1268 = inttoptr i64 83 to ptr
  %t1269 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1268, ptr %t1269
  br label %reuse.join.1267
reuse.copy.1266:
  %t1270 = call ptr @__alloc(i64 24, i32 2)
  %t1271 = inttoptr i64 83 to ptr
  %t1272 = getelementptr ptr, ptr %t1270, i32 0
  store ptr %t1271, ptr %t1272
  call void @__inc_ref(ptr %t1259)
  %t1273 = getelementptr ptr, ptr %t1270, i32 1
  store ptr %t1259, ptr %t1273
  call void @__inc_ref(ptr %t1261)
  %t1274 = getelementptr ptr, ptr %t1270, i32 2
  store ptr %t1261, ptr %t1274
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1267
reuse.join.1267:
  %t1275 = phi ptr [ %t5, %reuse.in_place.1265 ], [ %t1270, %reuse.copy.1266 ]
  %t1276 = call ptr @__alloc(i64 16, i32 1)
  %t1277 = inttoptr i64 183 to ptr
  %t1278 = getelementptr ptr, ptr %t1276, i32 0
  store ptr %t1277, ptr %t1278
  call void @__inc_ref(ptr %t6)
  %t1279 = getelementptr ptr, ptr %t1276, i32 1
  store ptr %t6, ptr %t1279
  call void @__free_recursive(ptr %t6)
  store ptr %t1275, ptr %t3
  store ptr %t1276, ptr %t4
  br label %tco.loop.0
tco.case.arm.93.1280:
  %t1281 = getelementptr ptr, ptr %t5, i32 1
  %t1282 = load ptr, ptr %t1281
  %t1283 = getelementptr ptr, ptr %t5, i32 2
  %t1284 = load ptr, ptr %t1283
  %t1285 = getelementptr i8, ptr %t5, i64 -8
  %t1286 = load i32, ptr %t1285
  %t1287 = icmp eq i32 %t1286, 1
  br i1 %t1287, label %reuse.in_place.1288, label %reuse.copy.1289
reuse.in_place.1288:
  %t1291 = inttoptr i64 83 to ptr
  %t1292 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1291, ptr %t1292
  br label %reuse.join.1290
reuse.copy.1289:
  %t1293 = call ptr @__alloc(i64 24, i32 2)
  %t1294 = inttoptr i64 83 to ptr
  %t1295 = getelementptr ptr, ptr %t1293, i32 0
  store ptr %t1294, ptr %t1295
  call void @__inc_ref(ptr %t1282)
  %t1296 = getelementptr ptr, ptr %t1293, i32 1
  store ptr %t1282, ptr %t1296
  call void @__inc_ref(ptr %t1284)
  %t1297 = getelementptr ptr, ptr %t1293, i32 2
  store ptr %t1284, ptr %t1297
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1290
reuse.join.1290:
  %t1298 = phi ptr [ %t5, %reuse.in_place.1288 ], [ %t1293, %reuse.copy.1289 ]
  %t1299 = call ptr @__alloc(i64 16, i32 1)
  %t1300 = inttoptr i64 184 to ptr
  %t1301 = getelementptr ptr, ptr %t1299, i32 0
  store ptr %t1300, ptr %t1301
  call void @__inc_ref(ptr %t6)
  %t1302 = getelementptr ptr, ptr %t1299, i32 1
  store ptr %t6, ptr %t1302
  call void @__free_recursive(ptr %t6)
  store ptr %t1298, ptr %t3
  store ptr %t1299, ptr %t4
  br label %tco.loop.0
tco.case.arm.94.1303:
  %t1304 = getelementptr ptr, ptr %t5, i32 1
  %t1305 = load ptr, ptr %t1304
  %t1306 = getelementptr ptr, ptr %t5, i32 2
  %t1307 = load ptr, ptr %t1306
  %t1308 = getelementptr i8, ptr %t5, i64 -8
  %t1309 = load i32, ptr %t1308
  %t1310 = icmp eq i32 %t1309, 1
  br i1 %t1310, label %reuse.in_place.1311, label %reuse.copy.1312
reuse.in_place.1311:
  %t1314 = inttoptr i64 83 to ptr
  %t1315 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1314, ptr %t1315
  br label %reuse.join.1313
reuse.copy.1312:
  %t1316 = call ptr @__alloc(i64 24, i32 2)
  %t1317 = inttoptr i64 83 to ptr
  %t1318 = getelementptr ptr, ptr %t1316, i32 0
  store ptr %t1317, ptr %t1318
  call void @__inc_ref(ptr %t1305)
  %t1319 = getelementptr ptr, ptr %t1316, i32 1
  store ptr %t1305, ptr %t1319
  call void @__inc_ref(ptr %t1307)
  %t1320 = getelementptr ptr, ptr %t1316, i32 2
  store ptr %t1307, ptr %t1320
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1313
reuse.join.1313:
  %t1321 = phi ptr [ %t5, %reuse.in_place.1311 ], [ %t1316, %reuse.copy.1312 ]
  %t1322 = call ptr @__alloc(i64 16, i32 1)
  %t1323 = inttoptr i64 185 to ptr
  %t1324 = getelementptr ptr, ptr %t1322, i32 0
  store ptr %t1323, ptr %t1324
  call void @__inc_ref(ptr %t6)
  %t1325 = getelementptr ptr, ptr %t1322, i32 1
  store ptr %t6, ptr %t1325
  call void @__free_recursive(ptr %t6)
  store ptr %t1321, ptr %t3
  store ptr %t1322, ptr %t4
  br label %tco.loop.0
tco.case.arm.95.1326:
  %t1327 = getelementptr ptr, ptr %t5, i32 1
  %t1328 = load ptr, ptr %t1327
  %t1329 = getelementptr ptr, ptr %t5, i32 2
  %t1330 = load ptr, ptr %t1329
  %t1331 = getelementptr i8, ptr %t5, i64 -8
  %t1332 = load i32, ptr %t1331
  %t1333 = icmp eq i32 %t1332, 1
  br i1 %t1333, label %reuse.in_place.1334, label %reuse.copy.1335
reuse.in_place.1334:
  %t1337 = inttoptr i64 83 to ptr
  %t1338 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1337, ptr %t1338
  br label %reuse.join.1336
reuse.copy.1335:
  %t1339 = call ptr @__alloc(i64 24, i32 2)
  %t1340 = inttoptr i64 83 to ptr
  %t1341 = getelementptr ptr, ptr %t1339, i32 0
  store ptr %t1340, ptr %t1341
  call void @__inc_ref(ptr %t1328)
  %t1342 = getelementptr ptr, ptr %t1339, i32 1
  store ptr %t1328, ptr %t1342
  call void @__inc_ref(ptr %t1330)
  %t1343 = getelementptr ptr, ptr %t1339, i32 2
  store ptr %t1330, ptr %t1343
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1336
reuse.join.1336:
  %t1344 = phi ptr [ %t5, %reuse.in_place.1334 ], [ %t1339, %reuse.copy.1335 ]
  %t1345 = call ptr @__alloc(i64 16, i32 1)
  %t1346 = inttoptr i64 186 to ptr
  %t1347 = getelementptr ptr, ptr %t1345, i32 0
  store ptr %t1346, ptr %t1347
  call void @__inc_ref(ptr %t6)
  %t1348 = getelementptr ptr, ptr %t1345, i32 1
  store ptr %t6, ptr %t1348
  call void @__free_recursive(ptr %t6)
  store ptr %t1344, ptr %t3
  store ptr %t1345, ptr %t4
  br label %tco.loop.0
tco.case.arm.96.1349:
  %t1350 = getelementptr ptr, ptr %t5, i32 1
  %t1351 = load ptr, ptr %t1350
  %t1352 = getelementptr ptr, ptr %t5, i32 2
  %t1353 = load ptr, ptr %t1352
  %t1354 = getelementptr i8, ptr %t5, i64 -8
  %t1355 = load i32, ptr %t1354
  %t1356 = icmp eq i32 %t1355, 1
  br i1 %t1356, label %reuse.in_place.1357, label %reuse.copy.1358
reuse.in_place.1357:
  %t1360 = inttoptr i64 83 to ptr
  %t1361 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1360, ptr %t1361
  br label %reuse.join.1359
reuse.copy.1358:
  %t1362 = call ptr @__alloc(i64 24, i32 2)
  %t1363 = inttoptr i64 83 to ptr
  %t1364 = getelementptr ptr, ptr %t1362, i32 0
  store ptr %t1363, ptr %t1364
  call void @__inc_ref(ptr %t1351)
  %t1365 = getelementptr ptr, ptr %t1362, i32 1
  store ptr %t1351, ptr %t1365
  call void @__inc_ref(ptr %t1353)
  %t1366 = getelementptr ptr, ptr %t1362, i32 2
  store ptr %t1353, ptr %t1366
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1359
reuse.join.1359:
  %t1367 = phi ptr [ %t5, %reuse.in_place.1357 ], [ %t1362, %reuse.copy.1358 ]
  %t1368 = call ptr @__alloc(i64 16, i32 1)
  %t1369 = inttoptr i64 187 to ptr
  %t1370 = getelementptr ptr, ptr %t1368, i32 0
  store ptr %t1369, ptr %t1370
  call void @__inc_ref(ptr %t6)
  %t1371 = getelementptr ptr, ptr %t1368, i32 1
  store ptr %t6, ptr %t1371
  call void @__free_recursive(ptr %t6)
  store ptr %t1367, ptr %t3
  store ptr %t1368, ptr %t4
  br label %tco.loop.0
tco.case.arm.97.1372:
  %t1373 = getelementptr ptr, ptr %t5, i32 1
  %t1374 = load ptr, ptr %t1373
  %t1375 = getelementptr ptr, ptr %t5, i32 2
  %t1376 = load ptr, ptr %t1375
  %t1377 = getelementptr i8, ptr %t5, i64 -8
  %t1378 = load i32, ptr %t1377
  %t1379 = icmp eq i32 %t1378, 1
  br i1 %t1379, label %reuse.in_place.1380, label %reuse.copy.1381
reuse.in_place.1380:
  %t1383 = inttoptr i64 83 to ptr
  %t1384 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1383, ptr %t1384
  br label %reuse.join.1382
reuse.copy.1381:
  %t1385 = call ptr @__alloc(i64 24, i32 2)
  %t1386 = inttoptr i64 83 to ptr
  %t1387 = getelementptr ptr, ptr %t1385, i32 0
  store ptr %t1386, ptr %t1387
  call void @__inc_ref(ptr %t1374)
  %t1388 = getelementptr ptr, ptr %t1385, i32 1
  store ptr %t1374, ptr %t1388
  call void @__inc_ref(ptr %t1376)
  %t1389 = getelementptr ptr, ptr %t1385, i32 2
  store ptr %t1376, ptr %t1389
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1382
reuse.join.1382:
  %t1390 = phi ptr [ %t5, %reuse.in_place.1380 ], [ %t1385, %reuse.copy.1381 ]
  %t1391 = call ptr @__alloc(i64 16, i32 1)
  %t1392 = inttoptr i64 188 to ptr
  %t1393 = getelementptr ptr, ptr %t1391, i32 0
  store ptr %t1392, ptr %t1393
  call void @__inc_ref(ptr %t6)
  %t1394 = getelementptr ptr, ptr %t1391, i32 1
  store ptr %t6, ptr %t1394
  call void @__free_recursive(ptr %t6)
  store ptr %t1390, ptr %t3
  store ptr %t1391, ptr %t4
  br label %tco.loop.0
tco.case.arm.98.1395:
  %t1396 = getelementptr ptr, ptr %t5, i32 1
  %t1397 = load ptr, ptr %t1396
  %t1398 = getelementptr ptr, ptr %t5, i32 2
  %t1399 = load ptr, ptr %t1398
  %t1400 = getelementptr i8, ptr %t5, i64 -8
  %t1401 = load i32, ptr %t1400
  %t1402 = icmp eq i32 %t1401, 1
  br i1 %t1402, label %reuse.in_place.1403, label %reuse.copy.1404
reuse.in_place.1403:
  %t1406 = inttoptr i64 83 to ptr
  %t1407 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1406, ptr %t1407
  br label %reuse.join.1405
reuse.copy.1404:
  %t1408 = call ptr @__alloc(i64 24, i32 2)
  %t1409 = inttoptr i64 83 to ptr
  %t1410 = getelementptr ptr, ptr %t1408, i32 0
  store ptr %t1409, ptr %t1410
  call void @__inc_ref(ptr %t1397)
  %t1411 = getelementptr ptr, ptr %t1408, i32 1
  store ptr %t1397, ptr %t1411
  call void @__inc_ref(ptr %t1399)
  %t1412 = getelementptr ptr, ptr %t1408, i32 2
  store ptr %t1399, ptr %t1412
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1405
reuse.join.1405:
  %t1413 = phi ptr [ %t5, %reuse.in_place.1403 ], [ %t1408, %reuse.copy.1404 ]
  %t1414 = call ptr @__alloc(i64 16, i32 1)
  %t1415 = inttoptr i64 189 to ptr
  %t1416 = getelementptr ptr, ptr %t1414, i32 0
  store ptr %t1415, ptr %t1416
  call void @__inc_ref(ptr %t6)
  %t1417 = getelementptr ptr, ptr %t1414, i32 1
  store ptr %t6, ptr %t1417
  call void @__free_recursive(ptr %t6)
  store ptr %t1413, ptr %t3
  store ptr %t1414, ptr %t4
  br label %tco.loop.0
tco.case.arm.99.1418:
  %t1419 = getelementptr ptr, ptr %t5, i32 1
  %t1420 = load ptr, ptr %t1419
  %t1421 = getelementptr ptr, ptr %t5, i32 2
  %t1422 = load ptr, ptr %t1421
  %t1423 = getelementptr i8, ptr %t5, i64 -8
  %t1424 = load i32, ptr %t1423
  %t1425 = icmp eq i32 %t1424, 1
  br i1 %t1425, label %reuse.in_place.1426, label %reuse.copy.1427
reuse.in_place.1426:
  %t1429 = inttoptr i64 83 to ptr
  %t1430 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1429, ptr %t1430
  br label %reuse.join.1428
reuse.copy.1427:
  %t1431 = call ptr @__alloc(i64 24, i32 2)
  %t1432 = inttoptr i64 83 to ptr
  %t1433 = getelementptr ptr, ptr %t1431, i32 0
  store ptr %t1432, ptr %t1433
  call void @__inc_ref(ptr %t1420)
  %t1434 = getelementptr ptr, ptr %t1431, i32 1
  store ptr %t1420, ptr %t1434
  call void @__inc_ref(ptr %t1422)
  %t1435 = getelementptr ptr, ptr %t1431, i32 2
  store ptr %t1422, ptr %t1435
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1428
reuse.join.1428:
  %t1436 = phi ptr [ %t5, %reuse.in_place.1426 ], [ %t1431, %reuse.copy.1427 ]
  %t1437 = call ptr @__alloc(i64 16, i32 1)
  %t1438 = inttoptr i64 190 to ptr
  %t1439 = getelementptr ptr, ptr %t1437, i32 0
  store ptr %t1438, ptr %t1439
  call void @__inc_ref(ptr %t6)
  %t1440 = getelementptr ptr, ptr %t1437, i32 1
  store ptr %t6, ptr %t1440
  call void @__free_recursive(ptr %t6)
  store ptr %t1436, ptr %t3
  store ptr %t1437, ptr %t4
  br label %tco.loop.0
tco.case.arm.100.1441:
  %t1442 = getelementptr ptr, ptr %t5, i32 1
  %t1443 = load ptr, ptr %t1442
  %t1444 = getelementptr ptr, ptr %t5, i32 2
  %t1445 = load ptr, ptr %t1444
  %t1446 = getelementptr i8, ptr %t5, i64 -8
  %t1447 = load i32, ptr %t1446
  %t1448 = icmp eq i32 %t1447, 1
  br i1 %t1448, label %reuse.in_place.1449, label %reuse.copy.1450
reuse.in_place.1449:
  %t1452 = inttoptr i64 83 to ptr
  %t1453 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1452, ptr %t1453
  br label %reuse.join.1451
reuse.copy.1450:
  %t1454 = call ptr @__alloc(i64 24, i32 2)
  %t1455 = inttoptr i64 83 to ptr
  %t1456 = getelementptr ptr, ptr %t1454, i32 0
  store ptr %t1455, ptr %t1456
  call void @__inc_ref(ptr %t1443)
  %t1457 = getelementptr ptr, ptr %t1454, i32 1
  store ptr %t1443, ptr %t1457
  call void @__inc_ref(ptr %t1445)
  %t1458 = getelementptr ptr, ptr %t1454, i32 2
  store ptr %t1445, ptr %t1458
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1451
reuse.join.1451:
  %t1459 = phi ptr [ %t5, %reuse.in_place.1449 ], [ %t1454, %reuse.copy.1450 ]
  %t1460 = call ptr @__alloc(i64 16, i32 1)
  %t1461 = inttoptr i64 191 to ptr
  %t1462 = getelementptr ptr, ptr %t1460, i32 0
  store ptr %t1461, ptr %t1462
  call void @__inc_ref(ptr %t6)
  %t1463 = getelementptr ptr, ptr %t1460, i32 1
  store ptr %t6, ptr %t1463
  call void @__free_recursive(ptr %t6)
  store ptr %t1459, ptr %t3
  store ptr %t1460, ptr %t4
  br label %tco.loop.0
tco.case.arm.101.1464:
  %t1465 = getelementptr ptr, ptr %t5, i32 1
  %t1466 = load ptr, ptr %t1465
  %t1467 = getelementptr ptr, ptr %t5, i32 2
  %t1468 = load ptr, ptr %t1467
  %t1469 = getelementptr i8, ptr %t5, i64 -8
  %t1470 = load i32, ptr %t1469
  %t1471 = icmp eq i32 %t1470, 1
  br i1 %t1471, label %reuse.in_place.1472, label %reuse.copy.1473
reuse.in_place.1472:
  %t1475 = inttoptr i64 83 to ptr
  %t1476 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1475, ptr %t1476
  br label %reuse.join.1474
reuse.copy.1473:
  %t1477 = call ptr @__alloc(i64 24, i32 2)
  %t1478 = inttoptr i64 83 to ptr
  %t1479 = getelementptr ptr, ptr %t1477, i32 0
  store ptr %t1478, ptr %t1479
  call void @__inc_ref(ptr %t1466)
  %t1480 = getelementptr ptr, ptr %t1477, i32 1
  store ptr %t1466, ptr %t1480
  call void @__inc_ref(ptr %t1468)
  %t1481 = getelementptr ptr, ptr %t1477, i32 2
  store ptr %t1468, ptr %t1481
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1474
reuse.join.1474:
  %t1482 = phi ptr [ %t5, %reuse.in_place.1472 ], [ %t1477, %reuse.copy.1473 ]
  %t1483 = call ptr @__alloc(i64 16, i32 1)
  %t1484 = inttoptr i64 192 to ptr
  %t1485 = getelementptr ptr, ptr %t1483, i32 0
  store ptr %t1484, ptr %t1485
  call void @__inc_ref(ptr %t6)
  %t1486 = getelementptr ptr, ptr %t1483, i32 1
  store ptr %t6, ptr %t1486
  call void @__free_recursive(ptr %t6)
  store ptr %t1482, ptr %t3
  store ptr %t1483, ptr %t4
  br label %tco.loop.0
tco.case.arm.102.1487:
  %t1488 = getelementptr ptr, ptr %t5, i32 1
  %t1489 = load ptr, ptr %t1488
  %t1490 = getelementptr ptr, ptr %t5, i32 2
  %t1491 = load ptr, ptr %t1490
  %t1492 = getelementptr i8, ptr %t5, i64 -8
  %t1493 = load i32, ptr %t1492
  %t1494 = icmp eq i32 %t1493, 1
  br i1 %t1494, label %reuse.in_place.1495, label %reuse.copy.1496
reuse.in_place.1495:
  %t1498 = inttoptr i64 83 to ptr
  %t1499 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1498, ptr %t1499
  br label %reuse.join.1497
reuse.copy.1496:
  %t1500 = call ptr @__alloc(i64 24, i32 2)
  %t1501 = inttoptr i64 83 to ptr
  %t1502 = getelementptr ptr, ptr %t1500, i32 0
  store ptr %t1501, ptr %t1502
  call void @__inc_ref(ptr %t1489)
  %t1503 = getelementptr ptr, ptr %t1500, i32 1
  store ptr %t1489, ptr %t1503
  call void @__inc_ref(ptr %t1491)
  %t1504 = getelementptr ptr, ptr %t1500, i32 2
  store ptr %t1491, ptr %t1504
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1497
reuse.join.1497:
  %t1505 = phi ptr [ %t5, %reuse.in_place.1495 ], [ %t1500, %reuse.copy.1496 ]
  %t1506 = call ptr @__alloc(i64 16, i32 1)
  %t1507 = inttoptr i64 193 to ptr
  %t1508 = getelementptr ptr, ptr %t1506, i32 0
  store ptr %t1507, ptr %t1508
  call void @__inc_ref(ptr %t6)
  %t1509 = getelementptr ptr, ptr %t1506, i32 1
  store ptr %t6, ptr %t1509
  call void @__free_recursive(ptr %t6)
  store ptr %t1505, ptr %t3
  store ptr %t1506, ptr %t4
  br label %tco.loop.0
tco.case.arm.103.1510:
  %t1511 = getelementptr ptr, ptr %t5, i32 1
  %t1512 = load ptr, ptr %t1511
  %t1513 = getelementptr ptr, ptr %t5, i32 2
  %t1514 = load ptr, ptr %t1513
  %t1515 = getelementptr i8, ptr %t5, i64 -8
  %t1516 = load i32, ptr %t1515
  %t1517 = icmp eq i32 %t1516, 1
  br i1 %t1517, label %reuse.in_place.1518, label %reuse.copy.1519
reuse.in_place.1518:
  %t1521 = inttoptr i64 83 to ptr
  %t1522 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1521, ptr %t1522
  br label %reuse.join.1520
reuse.copy.1519:
  %t1523 = call ptr @__alloc(i64 24, i32 2)
  %t1524 = inttoptr i64 83 to ptr
  %t1525 = getelementptr ptr, ptr %t1523, i32 0
  store ptr %t1524, ptr %t1525
  call void @__inc_ref(ptr %t1512)
  %t1526 = getelementptr ptr, ptr %t1523, i32 1
  store ptr %t1512, ptr %t1526
  call void @__inc_ref(ptr %t1514)
  %t1527 = getelementptr ptr, ptr %t1523, i32 2
  store ptr %t1514, ptr %t1527
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1520
reuse.join.1520:
  %t1528 = phi ptr [ %t5, %reuse.in_place.1518 ], [ %t1523, %reuse.copy.1519 ]
  %t1529 = call ptr @__alloc(i64 16, i32 1)
  %t1530 = inttoptr i64 194 to ptr
  %t1531 = getelementptr ptr, ptr %t1529, i32 0
  store ptr %t1530, ptr %t1531
  call void @__inc_ref(ptr %t6)
  %t1532 = getelementptr ptr, ptr %t1529, i32 1
  store ptr %t6, ptr %t1532
  call void @__free_recursive(ptr %t6)
  store ptr %t1528, ptr %t3
  store ptr %t1529, ptr %t4
  br label %tco.loop.0
tco.case.arm.104.1533:
  %t1534 = getelementptr ptr, ptr %t5, i32 1
  %t1535 = load ptr, ptr %t1534
  %t1536 = getelementptr ptr, ptr %t5, i32 2
  %t1537 = load ptr, ptr %t1536
  %t1538 = getelementptr i8, ptr %t5, i64 -8
  %t1539 = load i32, ptr %t1538
  %t1540 = icmp eq i32 %t1539, 1
  br i1 %t1540, label %reuse.in_place.1541, label %reuse.copy.1542
reuse.in_place.1541:
  %t1544 = inttoptr i64 83 to ptr
  %t1545 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1544, ptr %t1545
  br label %reuse.join.1543
reuse.copy.1542:
  %t1546 = call ptr @__alloc(i64 24, i32 2)
  %t1547 = inttoptr i64 83 to ptr
  %t1548 = getelementptr ptr, ptr %t1546, i32 0
  store ptr %t1547, ptr %t1548
  call void @__inc_ref(ptr %t1535)
  %t1549 = getelementptr ptr, ptr %t1546, i32 1
  store ptr %t1535, ptr %t1549
  call void @__inc_ref(ptr %t1537)
  %t1550 = getelementptr ptr, ptr %t1546, i32 2
  store ptr %t1537, ptr %t1550
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1543
reuse.join.1543:
  %t1551 = phi ptr [ %t5, %reuse.in_place.1541 ], [ %t1546, %reuse.copy.1542 ]
  %t1552 = call ptr @__alloc(i64 16, i32 1)
  %t1553 = inttoptr i64 195 to ptr
  %t1554 = getelementptr ptr, ptr %t1552, i32 0
  store ptr %t1553, ptr %t1554
  call void @__inc_ref(ptr %t6)
  %t1555 = getelementptr ptr, ptr %t1552, i32 1
  store ptr %t6, ptr %t1555
  call void @__free_recursive(ptr %t6)
  store ptr %t1551, ptr %t3
  store ptr %t1552, ptr %t4
  br label %tco.loop.0
tco.case.arm.105.1556:
  %t1557 = getelementptr ptr, ptr %t5, i32 1
  %t1558 = load ptr, ptr %t1557
  %t1559 = getelementptr ptr, ptr %t5, i32 2
  %t1560 = load ptr, ptr %t1559
  %t1561 = getelementptr i8, ptr %t5, i64 -8
  %t1562 = load i32, ptr %t1561
  %t1563 = icmp eq i32 %t1562, 1
  br i1 %t1563, label %reuse.in_place.1564, label %reuse.copy.1565
reuse.in_place.1564:
  %t1567 = inttoptr i64 83 to ptr
  %t1568 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1567, ptr %t1568
  br label %reuse.join.1566
reuse.copy.1565:
  %t1569 = call ptr @__alloc(i64 24, i32 2)
  %t1570 = inttoptr i64 83 to ptr
  %t1571 = getelementptr ptr, ptr %t1569, i32 0
  store ptr %t1570, ptr %t1571
  call void @__inc_ref(ptr %t1558)
  %t1572 = getelementptr ptr, ptr %t1569, i32 1
  store ptr %t1558, ptr %t1572
  call void @__inc_ref(ptr %t1560)
  %t1573 = getelementptr ptr, ptr %t1569, i32 2
  store ptr %t1560, ptr %t1573
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1566
reuse.join.1566:
  %t1574 = phi ptr [ %t5, %reuse.in_place.1564 ], [ %t1569, %reuse.copy.1565 ]
  %t1575 = call ptr @__alloc(i64 16, i32 1)
  %t1576 = inttoptr i64 196 to ptr
  %t1577 = getelementptr ptr, ptr %t1575, i32 0
  store ptr %t1576, ptr %t1577
  call void @__inc_ref(ptr %t6)
  %t1578 = getelementptr ptr, ptr %t1575, i32 1
  store ptr %t6, ptr %t1578
  call void @__free_recursive(ptr %t6)
  store ptr %t1574, ptr %t3
  store ptr %t1575, ptr %t4
  br label %tco.loop.0
tco.case.arm.106.1579:
  %t1580 = getelementptr ptr, ptr %t5, i32 1
  %t1581 = load ptr, ptr %t1580
  %t1582 = getelementptr ptr, ptr %t5, i32 2
  %t1583 = load ptr, ptr %t1582
  %t1584 = getelementptr i8, ptr %t5, i64 -8
  %t1585 = load i32, ptr %t1584
  %t1586 = icmp eq i32 %t1585, 1
  br i1 %t1586, label %reuse.in_place.1587, label %reuse.copy.1588
reuse.in_place.1587:
  %t1590 = inttoptr i64 83 to ptr
  %t1591 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1590, ptr %t1591
  br label %reuse.join.1589
reuse.copy.1588:
  %t1592 = call ptr @__alloc(i64 24, i32 2)
  %t1593 = inttoptr i64 83 to ptr
  %t1594 = getelementptr ptr, ptr %t1592, i32 0
  store ptr %t1593, ptr %t1594
  call void @__inc_ref(ptr %t1581)
  %t1595 = getelementptr ptr, ptr %t1592, i32 1
  store ptr %t1581, ptr %t1595
  call void @__inc_ref(ptr %t1583)
  %t1596 = getelementptr ptr, ptr %t1592, i32 2
  store ptr %t1583, ptr %t1596
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1589
reuse.join.1589:
  %t1597 = phi ptr [ %t5, %reuse.in_place.1587 ], [ %t1592, %reuse.copy.1588 ]
  %t1598 = call ptr @__alloc(i64 16, i32 1)
  %t1599 = inttoptr i64 197 to ptr
  %t1600 = getelementptr ptr, ptr %t1598, i32 0
  store ptr %t1599, ptr %t1600
  call void @__inc_ref(ptr %t6)
  %t1601 = getelementptr ptr, ptr %t1598, i32 1
  store ptr %t6, ptr %t1601
  call void @__free_recursive(ptr %t6)
  store ptr %t1597, ptr %t3
  store ptr %t1598, ptr %t4
  br label %tco.loop.0
tco.case.arm.107.1602:
  %t1603 = getelementptr ptr, ptr %t5, i32 1
  %t1604 = load ptr, ptr %t1603
  call void @__inc_ref(ptr %t1604)
  %t1605 = getelementptr ptr, ptr %t5, i32 2
  %t1606 = load ptr, ptr %t1605
  call void @__inc_ref(ptr %t1606)
  %t1607 = getelementptr ptr, ptr %t5, i32 3
  %t1608 = load ptr, ptr %t1607
  call void @__inc_ref(ptr %t1608)
  %t1609 = call ptr @__alloc(i64 24, i32 2)
  %t1610 = inttoptr i64 83 to ptr
  %t1611 = getelementptr ptr, ptr %t1609, i32 0
  store ptr %t1610, ptr %t1611
  call void @__inc_ref(ptr %t1604)
  %t1612 = getelementptr ptr, ptr %t1609, i32 1
  store ptr %t1604, ptr %t1612
  call void @__inc_ref(ptr %t1606)
  %t1613 = getelementptr ptr, ptr %t1609, i32 2
  store ptr %t1606, ptr %t1613
  %t1614 = call ptr @__alloc(i64 24, i32 2)
  %t1615 = inttoptr i64 198 to ptr
  %t1616 = getelementptr ptr, ptr %t1614, i32 0
  store ptr %t1615, ptr %t1616
  call void @__inc_ref(ptr %t6)
  %t1617 = getelementptr ptr, ptr %t1614, i32 1
  store ptr %t6, ptr %t1617
  call void @__inc_ref(ptr %t1608)
  %t1618 = getelementptr ptr, ptr %t1614, i32 2
  store ptr %t1608, ptr %t1618
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t1608)
  call void @__free_recursive(ptr %t1606)
  call void @__free_recursive(ptr %t1604)
  store ptr %t1609, ptr %t3
  store ptr %t1614, ptr %t4
  br label %tco.loop.0
tco.case.arm.108.1619:
  %t1620 = getelementptr ptr, ptr %t5, i32 1
  %t1621 = load ptr, ptr %t1620
  %t1622 = getelementptr ptr, ptr %t5, i32 2
  %t1623 = load ptr, ptr %t1622
  %t1624 = getelementptr i8, ptr %t5, i64 -8
  %t1625 = load i32, ptr %t1624
  %t1626 = icmp eq i32 %t1625, 1
  br i1 %t1626, label %reuse.in_place.1627, label %reuse.copy.1628
reuse.in_place.1627:
  %t1630 = inttoptr i64 83 to ptr
  %t1631 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1630, ptr %t1631
  br label %reuse.join.1629
reuse.copy.1628:
  %t1632 = call ptr @__alloc(i64 24, i32 2)
  %t1633 = inttoptr i64 83 to ptr
  %t1634 = getelementptr ptr, ptr %t1632, i32 0
  store ptr %t1633, ptr %t1634
  call void @__inc_ref(ptr %t1621)
  %t1635 = getelementptr ptr, ptr %t1632, i32 1
  store ptr %t1621, ptr %t1635
  call void @__inc_ref(ptr %t1623)
  %t1636 = getelementptr ptr, ptr %t1632, i32 2
  store ptr %t1623, ptr %t1636
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1629
reuse.join.1629:
  %t1637 = phi ptr [ %t5, %reuse.in_place.1627 ], [ %t1632, %reuse.copy.1628 ]
  %t1638 = call ptr @__alloc(i64 16, i32 1)
  %t1639 = inttoptr i64 199 to ptr
  %t1640 = getelementptr ptr, ptr %t1638, i32 0
  store ptr %t1639, ptr %t1640
  call void @__inc_ref(ptr %t6)
  %t1641 = getelementptr ptr, ptr %t1638, i32 1
  store ptr %t6, ptr %t1641
  call void @__free_recursive(ptr %t6)
  store ptr %t1637, ptr %t3
  store ptr %t1638, ptr %t4
  br label %tco.loop.0
tco.case.arm.109.1642:
  %t1643 = getelementptr ptr, ptr %t5, i32 1
  %t1644 = load ptr, ptr %t1643
  %t1645 = getelementptr ptr, ptr %t5, i32 2
  %t1646 = load ptr, ptr %t1645
  %t1647 = getelementptr i8, ptr %t5, i64 -8
  %t1648 = load i32, ptr %t1647
  %t1649 = icmp eq i32 %t1648, 1
  br i1 %t1649, label %reuse.in_place.1650, label %reuse.copy.1651
reuse.in_place.1650:
  %t1653 = inttoptr i64 83 to ptr
  %t1654 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1653, ptr %t1654
  br label %reuse.join.1652
reuse.copy.1651:
  %t1655 = call ptr @__alloc(i64 24, i32 2)
  %t1656 = inttoptr i64 83 to ptr
  %t1657 = getelementptr ptr, ptr %t1655, i32 0
  store ptr %t1656, ptr %t1657
  call void @__inc_ref(ptr %t1644)
  %t1658 = getelementptr ptr, ptr %t1655, i32 1
  store ptr %t1644, ptr %t1658
  call void @__inc_ref(ptr %t1646)
  %t1659 = getelementptr ptr, ptr %t1655, i32 2
  store ptr %t1646, ptr %t1659
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1652
reuse.join.1652:
  %t1660 = phi ptr [ %t5, %reuse.in_place.1650 ], [ %t1655, %reuse.copy.1651 ]
  %t1661 = call ptr @__alloc(i64 16, i32 1)
  %t1662 = inttoptr i64 200 to ptr
  %t1663 = getelementptr ptr, ptr %t1661, i32 0
  store ptr %t1662, ptr %t1663
  call void @__inc_ref(ptr %t6)
  %t1664 = getelementptr ptr, ptr %t1661, i32 1
  store ptr %t6, ptr %t1664
  call void @__free_recursive(ptr %t6)
  store ptr %t1660, ptr %t3
  store ptr %t1661, ptr %t4
  br label %tco.loop.0
tco.case.arm.110.1665:
  %t1666 = getelementptr ptr, ptr %t5, i32 1
  %t1667 = load ptr, ptr %t1666
  %t1668 = getelementptr ptr, ptr %t5, i32 2
  %t1669 = load ptr, ptr %t1668
  %t1670 = getelementptr i8, ptr %t5, i64 -8
  %t1671 = load i32, ptr %t1670
  %t1672 = icmp eq i32 %t1671, 1
  br i1 %t1672, label %reuse.in_place.1673, label %reuse.copy.1674
reuse.in_place.1673:
  %t1676 = inttoptr i64 83 to ptr
  %t1677 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1676, ptr %t1677
  br label %reuse.join.1675
reuse.copy.1674:
  %t1678 = call ptr @__alloc(i64 24, i32 2)
  %t1679 = inttoptr i64 83 to ptr
  %t1680 = getelementptr ptr, ptr %t1678, i32 0
  store ptr %t1679, ptr %t1680
  call void @__inc_ref(ptr %t1667)
  %t1681 = getelementptr ptr, ptr %t1678, i32 1
  store ptr %t1667, ptr %t1681
  call void @__inc_ref(ptr %t1669)
  %t1682 = getelementptr ptr, ptr %t1678, i32 2
  store ptr %t1669, ptr %t1682
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1675
reuse.join.1675:
  %t1683 = phi ptr [ %t5, %reuse.in_place.1673 ], [ %t1678, %reuse.copy.1674 ]
  %t1684 = call ptr @__alloc(i64 16, i32 1)
  %t1685 = inttoptr i64 201 to ptr
  %t1686 = getelementptr ptr, ptr %t1684, i32 0
  store ptr %t1685, ptr %t1686
  call void @__inc_ref(ptr %t6)
  %t1687 = getelementptr ptr, ptr %t1684, i32 1
  store ptr %t6, ptr %t1687
  call void @__free_recursive(ptr %t6)
  store ptr %t1683, ptr %t3
  store ptr %t1684, ptr %t4
  br label %tco.loop.0
tco.case.arm.111.1688:
  %t1689 = getelementptr ptr, ptr %t5, i32 1
  %t1690 = load ptr, ptr %t1689
  %t1691 = getelementptr ptr, ptr %t5, i32 2
  %t1692 = load ptr, ptr %t1691
  %t1693 = getelementptr i8, ptr %t5, i64 -8
  %t1694 = load i32, ptr %t1693
  %t1695 = icmp eq i32 %t1694, 1
  br i1 %t1695, label %reuse.in_place.1696, label %reuse.copy.1697
reuse.in_place.1696:
  %t1699 = inttoptr i64 83 to ptr
  %t1700 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1699, ptr %t1700
  br label %reuse.join.1698
reuse.copy.1697:
  %t1701 = call ptr @__alloc(i64 24, i32 2)
  %t1702 = inttoptr i64 83 to ptr
  %t1703 = getelementptr ptr, ptr %t1701, i32 0
  store ptr %t1702, ptr %t1703
  call void @__inc_ref(ptr %t1690)
  %t1704 = getelementptr ptr, ptr %t1701, i32 1
  store ptr %t1690, ptr %t1704
  call void @__inc_ref(ptr %t1692)
  %t1705 = getelementptr ptr, ptr %t1701, i32 2
  store ptr %t1692, ptr %t1705
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1698
reuse.join.1698:
  %t1706 = phi ptr [ %t5, %reuse.in_place.1696 ], [ %t1701, %reuse.copy.1697 ]
  %t1707 = call ptr @__alloc(i64 16, i32 1)
  %t1708 = inttoptr i64 202 to ptr
  %t1709 = getelementptr ptr, ptr %t1707, i32 0
  store ptr %t1708, ptr %t1709
  call void @__inc_ref(ptr %t6)
  %t1710 = getelementptr ptr, ptr %t1707, i32 1
  store ptr %t6, ptr %t1710
  call void @__free_recursive(ptr %t6)
  store ptr %t1706, ptr %t3
  store ptr %t1707, ptr %t4
  br label %tco.loop.0
tco.case.arm.112.1711:
  %t1712 = getelementptr ptr, ptr %t5, i32 1
  %t1713 = load ptr, ptr %t1712
  %t1714 = getelementptr ptr, ptr %t5, i32 2
  %t1715 = load ptr, ptr %t1714
  %t1716 = getelementptr i8, ptr %t5, i64 -8
  %t1717 = load i32, ptr %t1716
  %t1718 = icmp eq i32 %t1717, 1
  br i1 %t1718, label %reuse.in_place.1719, label %reuse.copy.1720
reuse.in_place.1719:
  %t1722 = inttoptr i64 83 to ptr
  %t1723 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1722, ptr %t1723
  br label %reuse.join.1721
reuse.copy.1720:
  %t1724 = call ptr @__alloc(i64 24, i32 2)
  %t1725 = inttoptr i64 83 to ptr
  %t1726 = getelementptr ptr, ptr %t1724, i32 0
  store ptr %t1725, ptr %t1726
  call void @__inc_ref(ptr %t1713)
  %t1727 = getelementptr ptr, ptr %t1724, i32 1
  store ptr %t1713, ptr %t1727
  call void @__inc_ref(ptr %t1715)
  %t1728 = getelementptr ptr, ptr %t1724, i32 2
  store ptr %t1715, ptr %t1728
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1721
reuse.join.1721:
  %t1729 = phi ptr [ %t5, %reuse.in_place.1719 ], [ %t1724, %reuse.copy.1720 ]
  %t1730 = call ptr @__alloc(i64 16, i32 1)
  %t1731 = inttoptr i64 203 to ptr
  %t1732 = getelementptr ptr, ptr %t1730, i32 0
  store ptr %t1731, ptr %t1732
  call void @__inc_ref(ptr %t6)
  %t1733 = getelementptr ptr, ptr %t1730, i32 1
  store ptr %t6, ptr %t1733
  call void @__free_recursive(ptr %t6)
  store ptr %t1729, ptr %t3
  store ptr %t1730, ptr %t4
  br label %tco.loop.0
tco.case.arm.113.1734:
  %t1735 = getelementptr ptr, ptr %t5, i32 1
  %t1736 = load ptr, ptr %t1735
  %t1737 = getelementptr ptr, ptr %t5, i32 2
  %t1738 = load ptr, ptr %t1737
  %t1739 = getelementptr i8, ptr %t5, i64 -8
  %t1740 = load i32, ptr %t1739
  %t1741 = icmp eq i32 %t1740, 1
  br i1 %t1741, label %reuse.in_place.1742, label %reuse.copy.1743
reuse.in_place.1742:
  %t1745 = inttoptr i64 83 to ptr
  %t1746 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1745, ptr %t1746
  br label %reuse.join.1744
reuse.copy.1743:
  %t1747 = call ptr @__alloc(i64 24, i32 2)
  %t1748 = inttoptr i64 83 to ptr
  %t1749 = getelementptr ptr, ptr %t1747, i32 0
  store ptr %t1748, ptr %t1749
  call void @__inc_ref(ptr %t1736)
  %t1750 = getelementptr ptr, ptr %t1747, i32 1
  store ptr %t1736, ptr %t1750
  call void @__inc_ref(ptr %t1738)
  %t1751 = getelementptr ptr, ptr %t1747, i32 2
  store ptr %t1738, ptr %t1751
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1744
reuse.join.1744:
  %t1752 = phi ptr [ %t5, %reuse.in_place.1742 ], [ %t1747, %reuse.copy.1743 ]
  %t1753 = call ptr @__alloc(i64 16, i32 1)
  %t1754 = inttoptr i64 204 to ptr
  %t1755 = getelementptr ptr, ptr %t1753, i32 0
  store ptr %t1754, ptr %t1755
  call void @__inc_ref(ptr %t6)
  %t1756 = getelementptr ptr, ptr %t1753, i32 1
  store ptr %t6, ptr %t1756
  call void @__free_recursive(ptr %t6)
  store ptr %t1752, ptr %t3
  store ptr %t1753, ptr %t4
  br label %tco.loop.0
tco.case.arm.114.1757:
  %t1758 = getelementptr ptr, ptr %t5, i32 1
  %t1759 = load ptr, ptr %t1758
  call void @__inc_ref(ptr %t1759)
  %t1760 = getelementptr ptr, ptr %t5, i32 2
  %t1761 = load ptr, ptr %t1760
  call void @__inc_ref(ptr %t1761)
  %t1762 = getelementptr ptr, ptr %t5, i32 3
  %t1763 = load ptr, ptr %t1762
  call void @__inc_ref(ptr %t1763)
  %t1764 = call ptr @__alloc(i64 24, i32 2)
  %t1765 = inttoptr i64 83 to ptr
  %t1766 = getelementptr ptr, ptr %t1764, i32 0
  store ptr %t1765, ptr %t1766
  call void @__inc_ref(ptr %t1759)
  %t1767 = getelementptr ptr, ptr %t1764, i32 1
  store ptr %t1759, ptr %t1767
  call void @__inc_ref(ptr %t1761)
  %t1768 = getelementptr ptr, ptr %t1764, i32 2
  store ptr %t1761, ptr %t1768
  %t1769 = call ptr @__alloc(i64 24, i32 2)
  %t1770 = inttoptr i64 205 to ptr
  %t1771 = getelementptr ptr, ptr %t1769, i32 0
  store ptr %t1770, ptr %t1771
  call void @__inc_ref(ptr %t6)
  %t1772 = getelementptr ptr, ptr %t1769, i32 1
  store ptr %t6, ptr %t1772
  call void @__inc_ref(ptr %t1763)
  %t1773 = getelementptr ptr, ptr %t1769, i32 2
  store ptr %t1763, ptr %t1773
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t1763)
  call void @__free_recursive(ptr %t1761)
  call void @__free_recursive(ptr %t1759)
  store ptr %t1764, ptr %t3
  store ptr %t1769, ptr %t4
  br label %tco.loop.0
tco.case.arm.115.1774:
  %t1775 = getelementptr ptr, ptr %t5, i32 1
  %t1776 = load ptr, ptr %t1775
  %t1777 = getelementptr ptr, ptr %t5, i32 2
  %t1778 = load ptr, ptr %t1777
  %t1779 = getelementptr i8, ptr %t5, i64 -8
  %t1780 = load i32, ptr %t1779
  %t1781 = icmp eq i32 %t1780, 1
  br i1 %t1781, label %reuse.in_place.1782, label %reuse.copy.1783
reuse.in_place.1782:
  %t1785 = inttoptr i64 83 to ptr
  %t1786 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1785, ptr %t1786
  br label %reuse.join.1784
reuse.copy.1783:
  %t1787 = call ptr @__alloc(i64 24, i32 2)
  %t1788 = inttoptr i64 83 to ptr
  %t1789 = getelementptr ptr, ptr %t1787, i32 0
  store ptr %t1788, ptr %t1789
  call void @__inc_ref(ptr %t1776)
  %t1790 = getelementptr ptr, ptr %t1787, i32 1
  store ptr %t1776, ptr %t1790
  call void @__inc_ref(ptr %t1778)
  %t1791 = getelementptr ptr, ptr %t1787, i32 2
  store ptr %t1778, ptr %t1791
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1784
reuse.join.1784:
  %t1792 = phi ptr [ %t5, %reuse.in_place.1782 ], [ %t1787, %reuse.copy.1783 ]
  %t1793 = call ptr @__alloc(i64 16, i32 1)
  %t1794 = inttoptr i64 206 to ptr
  %t1795 = getelementptr ptr, ptr %t1793, i32 0
  store ptr %t1794, ptr %t1795
  call void @__inc_ref(ptr %t6)
  %t1796 = getelementptr ptr, ptr %t1793, i32 1
  store ptr %t6, ptr %t1796
  call void @__free_recursive(ptr %t6)
  store ptr %t1792, ptr %t3
  store ptr %t1793, ptr %t4
  br label %tco.loop.0
tco.case.arm.116.1797:
  %t1798 = getelementptr ptr, ptr %t5, i32 1
  %t1799 = load ptr, ptr %t1798
  %t1800 = getelementptr ptr, ptr %t5, i32 2
  %t1801 = load ptr, ptr %t1800
  %t1802 = getelementptr i8, ptr %t5, i64 -8
  %t1803 = load i32, ptr %t1802
  %t1804 = icmp eq i32 %t1803, 1
  br i1 %t1804, label %reuse.in_place.1805, label %reuse.copy.1806
reuse.in_place.1805:
  %t1808 = inttoptr i64 83 to ptr
  %t1809 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1808, ptr %t1809
  br label %reuse.join.1807
reuse.copy.1806:
  %t1810 = call ptr @__alloc(i64 24, i32 2)
  %t1811 = inttoptr i64 83 to ptr
  %t1812 = getelementptr ptr, ptr %t1810, i32 0
  store ptr %t1811, ptr %t1812
  call void @__inc_ref(ptr %t1799)
  %t1813 = getelementptr ptr, ptr %t1810, i32 1
  store ptr %t1799, ptr %t1813
  call void @__inc_ref(ptr %t1801)
  %t1814 = getelementptr ptr, ptr %t1810, i32 2
  store ptr %t1801, ptr %t1814
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1807
reuse.join.1807:
  %t1815 = phi ptr [ %t5, %reuse.in_place.1805 ], [ %t1810, %reuse.copy.1806 ]
  %t1816 = call ptr @__alloc(i64 16, i32 1)
  %t1817 = inttoptr i64 207 to ptr
  %t1818 = getelementptr ptr, ptr %t1816, i32 0
  store ptr %t1817, ptr %t1818
  call void @__inc_ref(ptr %t6)
  %t1819 = getelementptr ptr, ptr %t1816, i32 1
  store ptr %t6, ptr %t1819
  call void @__free_recursive(ptr %t6)
  store ptr %t1815, ptr %t3
  store ptr %t1816, ptr %t4
  br label %tco.loop.0
tco.case.arm.117.1820:
  %t1821 = getelementptr ptr, ptr %t5, i32 1
  %t1822 = load ptr, ptr %t1821
  %t1823 = getelementptr ptr, ptr %t5, i32 2
  %t1824 = load ptr, ptr %t1823
  %t1825 = getelementptr i8, ptr %t5, i64 -8
  %t1826 = load i32, ptr %t1825
  %t1827 = icmp eq i32 %t1826, 1
  br i1 %t1827, label %reuse.in_place.1828, label %reuse.copy.1829
reuse.in_place.1828:
  %t1831 = inttoptr i64 83 to ptr
  %t1832 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1831, ptr %t1832
  br label %reuse.join.1830
reuse.copy.1829:
  %t1833 = call ptr @__alloc(i64 24, i32 2)
  %t1834 = inttoptr i64 83 to ptr
  %t1835 = getelementptr ptr, ptr %t1833, i32 0
  store ptr %t1834, ptr %t1835
  call void @__inc_ref(ptr %t1822)
  %t1836 = getelementptr ptr, ptr %t1833, i32 1
  store ptr %t1822, ptr %t1836
  call void @__inc_ref(ptr %t1824)
  %t1837 = getelementptr ptr, ptr %t1833, i32 2
  store ptr %t1824, ptr %t1837
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1830
reuse.join.1830:
  %t1838 = phi ptr [ %t5, %reuse.in_place.1828 ], [ %t1833, %reuse.copy.1829 ]
  %t1839 = call ptr @__alloc(i64 16, i32 1)
  %t1840 = inttoptr i64 208 to ptr
  %t1841 = getelementptr ptr, ptr %t1839, i32 0
  store ptr %t1840, ptr %t1841
  call void @__inc_ref(ptr %t6)
  %t1842 = getelementptr ptr, ptr %t1839, i32 1
  store ptr %t6, ptr %t1842
  call void @__free_recursive(ptr %t6)
  store ptr %t1838, ptr %t3
  store ptr %t1839, ptr %t4
  br label %tco.loop.0
tco.case.arm.118.1843:
  %t1844 = getelementptr ptr, ptr %t5, i32 1
  %t1845 = load ptr, ptr %t1844
  %t1846 = getelementptr ptr, ptr %t5, i32 2
  %t1847 = load ptr, ptr %t1846
  %t1848 = getelementptr i8, ptr %t5, i64 -8
  %t1849 = load i32, ptr %t1848
  %t1850 = icmp eq i32 %t1849, 1
  br i1 %t1850, label %reuse.in_place.1851, label %reuse.copy.1852
reuse.in_place.1851:
  %t1854 = inttoptr i64 83 to ptr
  %t1855 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1854, ptr %t1855
  br label %reuse.join.1853
reuse.copy.1852:
  %t1856 = call ptr @__alloc(i64 24, i32 2)
  %t1857 = inttoptr i64 83 to ptr
  %t1858 = getelementptr ptr, ptr %t1856, i32 0
  store ptr %t1857, ptr %t1858
  call void @__inc_ref(ptr %t1845)
  %t1859 = getelementptr ptr, ptr %t1856, i32 1
  store ptr %t1845, ptr %t1859
  call void @__inc_ref(ptr %t1847)
  %t1860 = getelementptr ptr, ptr %t1856, i32 2
  store ptr %t1847, ptr %t1860
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1853
reuse.join.1853:
  %t1861 = phi ptr [ %t5, %reuse.in_place.1851 ], [ %t1856, %reuse.copy.1852 ]
  %t1862 = call ptr @__alloc(i64 16, i32 1)
  %t1863 = inttoptr i64 209 to ptr
  %t1864 = getelementptr ptr, ptr %t1862, i32 0
  store ptr %t1863, ptr %t1864
  call void @__inc_ref(ptr %t6)
  %t1865 = getelementptr ptr, ptr %t1862, i32 1
  store ptr %t6, ptr %t1865
  call void @__free_recursive(ptr %t6)
  store ptr %t1861, ptr %t3
  store ptr %t1862, ptr %t4
  br label %tco.loop.0
tco.case.arm.119.1866:
  %t1867 = getelementptr ptr, ptr %t5, i32 1
  %t1868 = load ptr, ptr %t1867
  %t1869 = getelementptr ptr, ptr %t5, i32 2
  %t1870 = load ptr, ptr %t1869
  %t1871 = getelementptr i8, ptr %t5, i64 -8
  %t1872 = load i32, ptr %t1871
  %t1873 = icmp eq i32 %t1872, 1
  br i1 %t1873, label %reuse.in_place.1874, label %reuse.copy.1875
reuse.in_place.1874:
  %t1877 = inttoptr i64 83 to ptr
  %t1878 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1877, ptr %t1878
  br label %reuse.join.1876
reuse.copy.1875:
  %t1879 = call ptr @__alloc(i64 24, i32 2)
  %t1880 = inttoptr i64 83 to ptr
  %t1881 = getelementptr ptr, ptr %t1879, i32 0
  store ptr %t1880, ptr %t1881
  call void @__inc_ref(ptr %t1868)
  %t1882 = getelementptr ptr, ptr %t1879, i32 1
  store ptr %t1868, ptr %t1882
  call void @__inc_ref(ptr %t1870)
  %t1883 = getelementptr ptr, ptr %t1879, i32 2
  store ptr %t1870, ptr %t1883
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1876
reuse.join.1876:
  %t1884 = phi ptr [ %t5, %reuse.in_place.1874 ], [ %t1879, %reuse.copy.1875 ]
  %t1885 = call ptr @__alloc(i64 16, i32 1)
  %t1886 = inttoptr i64 210 to ptr
  %t1887 = getelementptr ptr, ptr %t1885, i32 0
  store ptr %t1886, ptr %t1887
  call void @__inc_ref(ptr %t6)
  %t1888 = getelementptr ptr, ptr %t1885, i32 1
  store ptr %t6, ptr %t1888
  call void @__free_recursive(ptr %t6)
  store ptr %t1884, ptr %t3
  store ptr %t1885, ptr %t4
  br label %tco.loop.0
tco.case.arm.120.1889:
  %t1890 = getelementptr ptr, ptr %t5, i32 1
  %t1891 = load ptr, ptr %t1890
  %t1892 = getelementptr ptr, ptr %t5, i32 2
  %t1893 = load ptr, ptr %t1892
  %t1894 = getelementptr i8, ptr %t5, i64 -8
  %t1895 = load i32, ptr %t1894
  %t1896 = icmp eq i32 %t1895, 1
  br i1 %t1896, label %reuse.in_place.1897, label %reuse.copy.1898
reuse.in_place.1897:
  %t1900 = inttoptr i64 83 to ptr
  %t1901 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1900, ptr %t1901
  br label %reuse.join.1899
reuse.copy.1898:
  %t1902 = call ptr @__alloc(i64 24, i32 2)
  %t1903 = inttoptr i64 83 to ptr
  %t1904 = getelementptr ptr, ptr %t1902, i32 0
  store ptr %t1903, ptr %t1904
  call void @__inc_ref(ptr %t1891)
  %t1905 = getelementptr ptr, ptr %t1902, i32 1
  store ptr %t1891, ptr %t1905
  call void @__inc_ref(ptr %t1893)
  %t1906 = getelementptr ptr, ptr %t1902, i32 2
  store ptr %t1893, ptr %t1906
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1899
reuse.join.1899:
  %t1907 = phi ptr [ %t5, %reuse.in_place.1897 ], [ %t1902, %reuse.copy.1898 ]
  %t1908 = call ptr @__alloc(i64 16, i32 1)
  %t1909 = inttoptr i64 211 to ptr
  %t1910 = getelementptr ptr, ptr %t1908, i32 0
  store ptr %t1909, ptr %t1910
  call void @__inc_ref(ptr %t6)
  %t1911 = getelementptr ptr, ptr %t1908, i32 1
  store ptr %t6, ptr %t1911
  call void @__free_recursive(ptr %t6)
  store ptr %t1907, ptr %t3
  store ptr %t1908, ptr %t4
  br label %tco.loop.0
tco.case.arm.121.1912:
  %t1913 = getelementptr ptr, ptr %t5, i32 1
  %t1914 = load ptr, ptr %t1913
  call void @__inc_ref(ptr %t1914)
  %t1915 = getelementptr ptr, ptr %t5, i32 2
  %t1916 = load ptr, ptr %t1915
  call void @__inc_ref(ptr %t1916)
  %t1917 = getelementptr ptr, ptr %t5, i32 3
  %t1918 = load ptr, ptr %t1917
  call void @__inc_ref(ptr %t1918)
  %t1919 = call ptr @__alloc(i64 24, i32 2)
  %t1920 = inttoptr i64 83 to ptr
  %t1921 = getelementptr ptr, ptr %t1919, i32 0
  store ptr %t1920, ptr %t1921
  call void @__inc_ref(ptr %t1914)
  %t1922 = getelementptr ptr, ptr %t1919, i32 1
  store ptr %t1914, ptr %t1922
  call void @__inc_ref(ptr %t1916)
  %t1923 = getelementptr ptr, ptr %t1919, i32 2
  store ptr %t1916, ptr %t1923
  %t1924 = call ptr @__alloc(i64 24, i32 2)
  %t1925 = inttoptr i64 212 to ptr
  %t1926 = getelementptr ptr, ptr %t1924, i32 0
  store ptr %t1925, ptr %t1926
  call void @__inc_ref(ptr %t6)
  %t1927 = getelementptr ptr, ptr %t1924, i32 1
  store ptr %t6, ptr %t1927
  call void @__inc_ref(ptr %t1918)
  %t1928 = getelementptr ptr, ptr %t1924, i32 2
  store ptr %t1918, ptr %t1928
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t1918)
  call void @__free_recursive(ptr %t1916)
  call void @__free_recursive(ptr %t1914)
  store ptr %t1919, ptr %t3
  store ptr %t1924, ptr %t4
  br label %tco.loop.0
tco.case.arm.122.1929:
  %t1930 = getelementptr ptr, ptr %t5, i32 1
  %t1931 = load ptr, ptr %t1930
  %t1932 = getelementptr ptr, ptr %t5, i32 2
  %t1933 = load ptr, ptr %t1932
  %t1934 = getelementptr i8, ptr %t5, i64 -8
  %t1935 = load i32, ptr %t1934
  %t1936 = icmp eq i32 %t1935, 1
  br i1 %t1936, label %reuse.in_place.1937, label %reuse.copy.1938
reuse.in_place.1937:
  %t1940 = inttoptr i64 83 to ptr
  %t1941 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1940, ptr %t1941
  br label %reuse.join.1939
reuse.copy.1938:
  %t1942 = call ptr @__alloc(i64 24, i32 2)
  %t1943 = inttoptr i64 83 to ptr
  %t1944 = getelementptr ptr, ptr %t1942, i32 0
  store ptr %t1943, ptr %t1944
  call void @__inc_ref(ptr %t1931)
  %t1945 = getelementptr ptr, ptr %t1942, i32 1
  store ptr %t1931, ptr %t1945
  call void @__inc_ref(ptr %t1933)
  %t1946 = getelementptr ptr, ptr %t1942, i32 2
  store ptr %t1933, ptr %t1946
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1939
reuse.join.1939:
  %t1947 = phi ptr [ %t5, %reuse.in_place.1937 ], [ %t1942, %reuse.copy.1938 ]
  %t1948 = call ptr @__alloc(i64 16, i32 1)
  %t1949 = inttoptr i64 213 to ptr
  %t1950 = getelementptr ptr, ptr %t1948, i32 0
  store ptr %t1949, ptr %t1950
  call void @__inc_ref(ptr %t6)
  %t1951 = getelementptr ptr, ptr %t1948, i32 1
  store ptr %t6, ptr %t1951
  call void @__free_recursive(ptr %t6)
  store ptr %t1947, ptr %t3
  store ptr %t1948, ptr %t4
  br label %tco.loop.0
tco.case.arm.123.1952:
  %t1953 = getelementptr ptr, ptr %t5, i32 1
  %t1954 = load ptr, ptr %t1953
  %t1955 = getelementptr ptr, ptr %t5, i32 2
  %t1956 = load ptr, ptr %t1955
  %t1957 = getelementptr i8, ptr %t5, i64 -8
  %t1958 = load i32, ptr %t1957
  %t1959 = icmp eq i32 %t1958, 1
  br i1 %t1959, label %reuse.in_place.1960, label %reuse.copy.1961
reuse.in_place.1960:
  %t1963 = inttoptr i64 83 to ptr
  %t1964 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1963, ptr %t1964
  br label %reuse.join.1962
reuse.copy.1961:
  %t1965 = call ptr @__alloc(i64 24, i32 2)
  %t1966 = inttoptr i64 83 to ptr
  %t1967 = getelementptr ptr, ptr %t1965, i32 0
  store ptr %t1966, ptr %t1967
  call void @__inc_ref(ptr %t1954)
  %t1968 = getelementptr ptr, ptr %t1965, i32 1
  store ptr %t1954, ptr %t1968
  call void @__inc_ref(ptr %t1956)
  %t1969 = getelementptr ptr, ptr %t1965, i32 2
  store ptr %t1956, ptr %t1969
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1962
reuse.join.1962:
  %t1970 = phi ptr [ %t5, %reuse.in_place.1960 ], [ %t1965, %reuse.copy.1961 ]
  %t1971 = call ptr @__alloc(i64 16, i32 1)
  %t1972 = inttoptr i64 214 to ptr
  %t1973 = getelementptr ptr, ptr %t1971, i32 0
  store ptr %t1972, ptr %t1973
  call void @__inc_ref(ptr %t6)
  %t1974 = getelementptr ptr, ptr %t1971, i32 1
  store ptr %t6, ptr %t1974
  call void @__free_recursive(ptr %t6)
  store ptr %t1970, ptr %t3
  store ptr %t1971, ptr %t4
  br label %tco.loop.0
tco.case.arm.124.1975:
  %t1976 = getelementptr ptr, ptr %t5, i32 1
  %t1977 = load ptr, ptr %t1976
  %t1978 = getelementptr ptr, ptr %t5, i32 2
  %t1979 = load ptr, ptr %t1978
  %t1980 = getelementptr i8, ptr %t5, i64 -8
  %t1981 = load i32, ptr %t1980
  %t1982 = icmp eq i32 %t1981, 1
  br i1 %t1982, label %reuse.in_place.1983, label %reuse.copy.1984
reuse.in_place.1983:
  %t1986 = inttoptr i64 83 to ptr
  %t1987 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1986, ptr %t1987
  br label %reuse.join.1985
reuse.copy.1984:
  %t1988 = call ptr @__alloc(i64 24, i32 2)
  %t1989 = inttoptr i64 83 to ptr
  %t1990 = getelementptr ptr, ptr %t1988, i32 0
  store ptr %t1989, ptr %t1990
  call void @__inc_ref(ptr %t1977)
  %t1991 = getelementptr ptr, ptr %t1988, i32 1
  store ptr %t1977, ptr %t1991
  call void @__inc_ref(ptr %t1979)
  %t1992 = getelementptr ptr, ptr %t1988, i32 2
  store ptr %t1979, ptr %t1992
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1985
reuse.join.1985:
  %t1993 = phi ptr [ %t5, %reuse.in_place.1983 ], [ %t1988, %reuse.copy.1984 ]
  %t1994 = call ptr @__alloc(i64 16, i32 1)
  %t1995 = inttoptr i64 215 to ptr
  %t1996 = getelementptr ptr, ptr %t1994, i32 0
  store ptr %t1995, ptr %t1996
  call void @__inc_ref(ptr %t6)
  %t1997 = getelementptr ptr, ptr %t1994, i32 1
  store ptr %t6, ptr %t1997
  call void @__free_recursive(ptr %t6)
  store ptr %t1993, ptr %t3
  store ptr %t1994, ptr %t4
  br label %tco.loop.0
tco.case.arm.125.1998:
  %t1999 = getelementptr ptr, ptr %t5, i32 1
  %t2000 = load ptr, ptr %t1999
  %t2001 = getelementptr ptr, ptr %t5, i32 2
  %t2002 = load ptr, ptr %t2001
  %t2003 = getelementptr i8, ptr %t5, i64 -8
  %t2004 = load i32, ptr %t2003
  %t2005 = icmp eq i32 %t2004, 1
  br i1 %t2005, label %reuse.in_place.2006, label %reuse.copy.2007
reuse.in_place.2006:
  %t2009 = inttoptr i64 83 to ptr
  %t2010 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2009, ptr %t2010
  br label %reuse.join.2008
reuse.copy.2007:
  %t2011 = call ptr @__alloc(i64 24, i32 2)
  %t2012 = inttoptr i64 83 to ptr
  %t2013 = getelementptr ptr, ptr %t2011, i32 0
  store ptr %t2012, ptr %t2013
  call void @__inc_ref(ptr %t2000)
  %t2014 = getelementptr ptr, ptr %t2011, i32 1
  store ptr %t2000, ptr %t2014
  call void @__inc_ref(ptr %t2002)
  %t2015 = getelementptr ptr, ptr %t2011, i32 2
  store ptr %t2002, ptr %t2015
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2008
reuse.join.2008:
  %t2016 = phi ptr [ %t5, %reuse.in_place.2006 ], [ %t2011, %reuse.copy.2007 ]
  %t2017 = call ptr @__alloc(i64 16, i32 1)
  %t2018 = inttoptr i64 216 to ptr
  %t2019 = getelementptr ptr, ptr %t2017, i32 0
  store ptr %t2018, ptr %t2019
  call void @__inc_ref(ptr %t6)
  %t2020 = getelementptr ptr, ptr %t2017, i32 1
  store ptr %t6, ptr %t2020
  call void @__free_recursive(ptr %t6)
  store ptr %t2016, ptr %t3
  store ptr %t2017, ptr %t4
  br label %tco.loop.0
tco.case.arm.126.2021:
  %t2022 = getelementptr ptr, ptr %t5, i32 1
  %t2023 = load ptr, ptr %t2022
  %t2024 = getelementptr ptr, ptr %t5, i32 2
  %t2025 = load ptr, ptr %t2024
  %t2026 = getelementptr i8, ptr %t5, i64 -8
  %t2027 = load i32, ptr %t2026
  %t2028 = icmp eq i32 %t2027, 1
  br i1 %t2028, label %reuse.in_place.2029, label %reuse.copy.2030
reuse.in_place.2029:
  %t2032 = inttoptr i64 83 to ptr
  %t2033 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2032, ptr %t2033
  br label %reuse.join.2031
reuse.copy.2030:
  %t2034 = call ptr @__alloc(i64 24, i32 2)
  %t2035 = inttoptr i64 83 to ptr
  %t2036 = getelementptr ptr, ptr %t2034, i32 0
  store ptr %t2035, ptr %t2036
  call void @__inc_ref(ptr %t2023)
  %t2037 = getelementptr ptr, ptr %t2034, i32 1
  store ptr %t2023, ptr %t2037
  call void @__inc_ref(ptr %t2025)
  %t2038 = getelementptr ptr, ptr %t2034, i32 2
  store ptr %t2025, ptr %t2038
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2031
reuse.join.2031:
  %t2039 = phi ptr [ %t5, %reuse.in_place.2029 ], [ %t2034, %reuse.copy.2030 ]
  %t2040 = call ptr @__alloc(i64 16, i32 1)
  %t2041 = inttoptr i64 217 to ptr
  %t2042 = getelementptr ptr, ptr %t2040, i32 0
  store ptr %t2041, ptr %t2042
  call void @__inc_ref(ptr %t6)
  %t2043 = getelementptr ptr, ptr %t2040, i32 1
  store ptr %t6, ptr %t2043
  call void @__free_recursive(ptr %t6)
  store ptr %t2039, ptr %t3
  store ptr %t2040, ptr %t4
  br label %tco.loop.0
tco.case.arm.127.2044:
  %t2045 = getelementptr ptr, ptr %t5, i32 1
  %t2046 = load ptr, ptr %t2045
  %t2047 = getelementptr ptr, ptr %t5, i32 2
  %t2048 = load ptr, ptr %t2047
  %t2049 = getelementptr i8, ptr %t5, i64 -8
  %t2050 = load i32, ptr %t2049
  %t2051 = icmp eq i32 %t2050, 1
  br i1 %t2051, label %reuse.in_place.2052, label %reuse.copy.2053
reuse.in_place.2052:
  %t2055 = inttoptr i64 83 to ptr
  %t2056 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2055, ptr %t2056
  br label %reuse.join.2054
reuse.copy.2053:
  %t2057 = call ptr @__alloc(i64 24, i32 2)
  %t2058 = inttoptr i64 83 to ptr
  %t2059 = getelementptr ptr, ptr %t2057, i32 0
  store ptr %t2058, ptr %t2059
  call void @__inc_ref(ptr %t2046)
  %t2060 = getelementptr ptr, ptr %t2057, i32 1
  store ptr %t2046, ptr %t2060
  call void @__inc_ref(ptr %t2048)
  %t2061 = getelementptr ptr, ptr %t2057, i32 2
  store ptr %t2048, ptr %t2061
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2054
reuse.join.2054:
  %t2062 = phi ptr [ %t5, %reuse.in_place.2052 ], [ %t2057, %reuse.copy.2053 ]
  %t2063 = call ptr @__alloc(i64 16, i32 1)
  %t2064 = inttoptr i64 218 to ptr
  %t2065 = getelementptr ptr, ptr %t2063, i32 0
  store ptr %t2064, ptr %t2065
  call void @__inc_ref(ptr %t6)
  %t2066 = getelementptr ptr, ptr %t2063, i32 1
  store ptr %t6, ptr %t2066
  call void @__free_recursive(ptr %t6)
  store ptr %t2062, ptr %t3
  store ptr %t2063, ptr %t4
  br label %tco.loop.0
tco.case.arm.128.2067:
  %t2068 = getelementptr ptr, ptr %t5, i32 1
  %t2069 = load ptr, ptr %t2068
  %t2070 = getelementptr ptr, ptr %t5, i32 2
  %t2071 = load ptr, ptr %t2070
  %t2072 = getelementptr i8, ptr %t5, i64 -8
  %t2073 = load i32, ptr %t2072
  %t2074 = icmp eq i32 %t2073, 1
  br i1 %t2074, label %reuse.in_place.2075, label %reuse.copy.2076
reuse.in_place.2075:
  %t2078 = inttoptr i64 83 to ptr
  %t2079 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2078, ptr %t2079
  br label %reuse.join.2077
reuse.copy.2076:
  %t2080 = call ptr @__alloc(i64 24, i32 2)
  %t2081 = inttoptr i64 83 to ptr
  %t2082 = getelementptr ptr, ptr %t2080, i32 0
  store ptr %t2081, ptr %t2082
  call void @__inc_ref(ptr %t2069)
  %t2083 = getelementptr ptr, ptr %t2080, i32 1
  store ptr %t2069, ptr %t2083
  call void @__inc_ref(ptr %t2071)
  %t2084 = getelementptr ptr, ptr %t2080, i32 2
  store ptr %t2071, ptr %t2084
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2077
reuse.join.2077:
  %t2085 = phi ptr [ %t5, %reuse.in_place.2075 ], [ %t2080, %reuse.copy.2076 ]
  %t2086 = call ptr @__alloc(i64 16, i32 1)
  %t2087 = inttoptr i64 219 to ptr
  %t2088 = getelementptr ptr, ptr %t2086, i32 0
  store ptr %t2087, ptr %t2088
  call void @__inc_ref(ptr %t6)
  %t2089 = getelementptr ptr, ptr %t2086, i32 1
  store ptr %t6, ptr %t2089
  call void @__free_recursive(ptr %t6)
  store ptr %t2085, ptr %t3
  store ptr %t2086, ptr %t4
  br label %tco.loop.0
tco.case.arm.129.2090:
  %t2091 = getelementptr ptr, ptr %t5, i32 1
  %t2092 = load ptr, ptr %t2091
  %t2093 = getelementptr ptr, ptr %t5, i32 2
  %t2094 = load ptr, ptr %t2093
  %t2095 = getelementptr i8, ptr %t5, i64 -8
  %t2096 = load i32, ptr %t2095
  %t2097 = icmp eq i32 %t2096, 1
  br i1 %t2097, label %reuse.in_place.2098, label %reuse.copy.2099
reuse.in_place.2098:
  %t2101 = inttoptr i64 83 to ptr
  %t2102 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2101, ptr %t2102
  br label %reuse.join.2100
reuse.copy.2099:
  %t2103 = call ptr @__alloc(i64 24, i32 2)
  %t2104 = inttoptr i64 83 to ptr
  %t2105 = getelementptr ptr, ptr %t2103, i32 0
  store ptr %t2104, ptr %t2105
  call void @__inc_ref(ptr %t2092)
  %t2106 = getelementptr ptr, ptr %t2103, i32 1
  store ptr %t2092, ptr %t2106
  call void @__inc_ref(ptr %t2094)
  %t2107 = getelementptr ptr, ptr %t2103, i32 2
  store ptr %t2094, ptr %t2107
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2100
reuse.join.2100:
  %t2108 = phi ptr [ %t5, %reuse.in_place.2098 ], [ %t2103, %reuse.copy.2099 ]
  %t2109 = call ptr @__alloc(i64 16, i32 1)
  %t2110 = inttoptr i64 220 to ptr
  %t2111 = getelementptr ptr, ptr %t2109, i32 0
  store ptr %t2110, ptr %t2111
  call void @__inc_ref(ptr %t6)
  %t2112 = getelementptr ptr, ptr %t2109, i32 1
  store ptr %t6, ptr %t2112
  call void @__free_recursive(ptr %t6)
  store ptr %t2108, ptr %t3
  store ptr %t2109, ptr %t4
  br label %tco.loop.0
tco.case.arm.130.2113:
  %t2114 = getelementptr ptr, ptr %t5, i32 1
  %t2115 = load ptr, ptr %t2114
  %t2116 = getelementptr ptr, ptr %t5, i32 2
  %t2117 = load ptr, ptr %t2116
  %t2118 = getelementptr i8, ptr %t5, i64 -8
  %t2119 = load i32, ptr %t2118
  %t2120 = icmp eq i32 %t2119, 1
  br i1 %t2120, label %reuse.in_place.2121, label %reuse.copy.2122
reuse.in_place.2121:
  %t2124 = inttoptr i64 83 to ptr
  %t2125 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2124, ptr %t2125
  br label %reuse.join.2123
reuse.copy.2122:
  %t2126 = call ptr @__alloc(i64 24, i32 2)
  %t2127 = inttoptr i64 83 to ptr
  %t2128 = getelementptr ptr, ptr %t2126, i32 0
  store ptr %t2127, ptr %t2128
  call void @__inc_ref(ptr %t2115)
  %t2129 = getelementptr ptr, ptr %t2126, i32 1
  store ptr %t2115, ptr %t2129
  call void @__inc_ref(ptr %t2117)
  %t2130 = getelementptr ptr, ptr %t2126, i32 2
  store ptr %t2117, ptr %t2130
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2123
reuse.join.2123:
  %t2131 = phi ptr [ %t5, %reuse.in_place.2121 ], [ %t2126, %reuse.copy.2122 ]
  %t2132 = call ptr @__alloc(i64 16, i32 1)
  %t2133 = inttoptr i64 221 to ptr
  %t2134 = getelementptr ptr, ptr %t2132, i32 0
  store ptr %t2133, ptr %t2134
  call void @__inc_ref(ptr %t6)
  %t2135 = getelementptr ptr, ptr %t2132, i32 1
  store ptr %t6, ptr %t2135
  call void @__free_recursive(ptr %t6)
  store ptr %t2131, ptr %t3
  store ptr %t2132, ptr %t4
  br label %tco.loop.0
tco.case.arm.131.2136:
  %t2137 = getelementptr ptr, ptr %t5, i32 1
  %t2138 = load ptr, ptr %t2137
  %t2139 = getelementptr ptr, ptr %t5, i32 2
  %t2140 = load ptr, ptr %t2139
  %t2141 = getelementptr i8, ptr %t5, i64 -8
  %t2142 = load i32, ptr %t2141
  %t2143 = icmp eq i32 %t2142, 1
  br i1 %t2143, label %reuse.in_place.2144, label %reuse.copy.2145
reuse.in_place.2144:
  %t2147 = inttoptr i64 83 to ptr
  %t2148 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2147, ptr %t2148
  br label %reuse.join.2146
reuse.copy.2145:
  %t2149 = call ptr @__alloc(i64 24, i32 2)
  %t2150 = inttoptr i64 83 to ptr
  %t2151 = getelementptr ptr, ptr %t2149, i32 0
  store ptr %t2150, ptr %t2151
  call void @__inc_ref(ptr %t2138)
  %t2152 = getelementptr ptr, ptr %t2149, i32 1
  store ptr %t2138, ptr %t2152
  call void @__inc_ref(ptr %t2140)
  %t2153 = getelementptr ptr, ptr %t2149, i32 2
  store ptr %t2140, ptr %t2153
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2146
reuse.join.2146:
  %t2154 = phi ptr [ %t5, %reuse.in_place.2144 ], [ %t2149, %reuse.copy.2145 ]
  %t2155 = call ptr @__alloc(i64 16, i32 1)
  %t2156 = inttoptr i64 222 to ptr
  %t2157 = getelementptr ptr, ptr %t2155, i32 0
  store ptr %t2156, ptr %t2157
  call void @__inc_ref(ptr %t6)
  %t2158 = getelementptr ptr, ptr %t2155, i32 1
  store ptr %t6, ptr %t2158
  call void @__free_recursive(ptr %t6)
  store ptr %t2154, ptr %t3
  store ptr %t2155, ptr %t4
  br label %tco.loop.0
tco.case.arm.132.2159:
  %t2160 = getelementptr ptr, ptr %t5, i32 1
  %t2161 = load ptr, ptr %t2160
  %t2162 = getelementptr ptr, ptr %t5, i32 2
  %t2163 = load ptr, ptr %t2162
  %t2164 = getelementptr i8, ptr %t5, i64 -8
  %t2165 = load i32, ptr %t2164
  %t2166 = icmp eq i32 %t2165, 1
  br i1 %t2166, label %reuse.in_place.2167, label %reuse.copy.2168
reuse.in_place.2167:
  %t2170 = inttoptr i64 83 to ptr
  %t2171 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2170, ptr %t2171
  br label %reuse.join.2169
reuse.copy.2168:
  %t2172 = call ptr @__alloc(i64 24, i32 2)
  %t2173 = inttoptr i64 83 to ptr
  %t2174 = getelementptr ptr, ptr %t2172, i32 0
  store ptr %t2173, ptr %t2174
  call void @__inc_ref(ptr %t2161)
  %t2175 = getelementptr ptr, ptr %t2172, i32 1
  store ptr %t2161, ptr %t2175
  call void @__inc_ref(ptr %t2163)
  %t2176 = getelementptr ptr, ptr %t2172, i32 2
  store ptr %t2163, ptr %t2176
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2169
reuse.join.2169:
  %t2177 = phi ptr [ %t5, %reuse.in_place.2167 ], [ %t2172, %reuse.copy.2168 ]
  %t2178 = call ptr @__alloc(i64 16, i32 1)
  %t2179 = inttoptr i64 223 to ptr
  %t2180 = getelementptr ptr, ptr %t2178, i32 0
  store ptr %t2179, ptr %t2180
  call void @__inc_ref(ptr %t6)
  %t2181 = getelementptr ptr, ptr %t2178, i32 1
  store ptr %t6, ptr %t2181
  call void @__free_recursive(ptr %t6)
  store ptr %t2177, ptr %t3
  store ptr %t2178, ptr %t4
  br label %tco.loop.0
tco.case.arm.133.2182:
  %t2183 = getelementptr ptr, ptr %t5, i32 1
  %t2184 = load ptr, ptr %t2183
  %t2185 = getelementptr ptr, ptr %t5, i32 2
  %t2186 = load ptr, ptr %t2185
  %t2187 = getelementptr i8, ptr %t5, i64 -8
  %t2188 = load i32, ptr %t2187
  %t2189 = icmp eq i32 %t2188, 1
  br i1 %t2189, label %reuse.in_place.2190, label %reuse.copy.2191
reuse.in_place.2190:
  %t2193 = inttoptr i64 83 to ptr
  %t2194 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2193, ptr %t2194
  br label %reuse.join.2192
reuse.copy.2191:
  %t2195 = call ptr @__alloc(i64 24, i32 2)
  %t2196 = inttoptr i64 83 to ptr
  %t2197 = getelementptr ptr, ptr %t2195, i32 0
  store ptr %t2196, ptr %t2197
  call void @__inc_ref(ptr %t2184)
  %t2198 = getelementptr ptr, ptr %t2195, i32 1
  store ptr %t2184, ptr %t2198
  call void @__inc_ref(ptr %t2186)
  %t2199 = getelementptr ptr, ptr %t2195, i32 2
  store ptr %t2186, ptr %t2199
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2192
reuse.join.2192:
  %t2200 = phi ptr [ %t5, %reuse.in_place.2190 ], [ %t2195, %reuse.copy.2191 ]
  %t2201 = call ptr @__alloc(i64 16, i32 1)
  %t2202 = inttoptr i64 224 to ptr
  %t2203 = getelementptr ptr, ptr %t2201, i32 0
  store ptr %t2202, ptr %t2203
  call void @__inc_ref(ptr %t6)
  %t2204 = getelementptr ptr, ptr %t2201, i32 1
  store ptr %t6, ptr %t2204
  call void @__free_recursive(ptr %t6)
  store ptr %t2200, ptr %t3
  store ptr %t2201, ptr %t4
  br label %tco.loop.0
tco.case.arm.134.2205:
  %t2206 = getelementptr ptr, ptr %t5, i32 1
  %t2207 = load ptr, ptr %t2206
  %t2208 = getelementptr ptr, ptr %t5, i32 2
  %t2209 = load ptr, ptr %t2208
  %t2210 = getelementptr i8, ptr %t5, i64 -8
  %t2211 = load i32, ptr %t2210
  %t2212 = icmp eq i32 %t2211, 1
  br i1 %t2212, label %reuse.in_place.2213, label %reuse.copy.2214
reuse.in_place.2213:
  %t2216 = inttoptr i64 83 to ptr
  %t2217 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2216, ptr %t2217
  br label %reuse.join.2215
reuse.copy.2214:
  %t2218 = call ptr @__alloc(i64 24, i32 2)
  %t2219 = inttoptr i64 83 to ptr
  %t2220 = getelementptr ptr, ptr %t2218, i32 0
  store ptr %t2219, ptr %t2220
  call void @__inc_ref(ptr %t2207)
  %t2221 = getelementptr ptr, ptr %t2218, i32 1
  store ptr %t2207, ptr %t2221
  call void @__inc_ref(ptr %t2209)
  %t2222 = getelementptr ptr, ptr %t2218, i32 2
  store ptr %t2209, ptr %t2222
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2215
reuse.join.2215:
  %t2223 = phi ptr [ %t5, %reuse.in_place.2213 ], [ %t2218, %reuse.copy.2214 ]
  %t2224 = call ptr @__alloc(i64 16, i32 1)
  %t2225 = inttoptr i64 225 to ptr
  %t2226 = getelementptr ptr, ptr %t2224, i32 0
  store ptr %t2225, ptr %t2226
  call void @__inc_ref(ptr %t6)
  %t2227 = getelementptr ptr, ptr %t2224, i32 1
  store ptr %t6, ptr %t2227
  call void @__free_recursive(ptr %t6)
  store ptr %t2223, ptr %t3
  store ptr %t2224, ptr %t4
  br label %tco.loop.0
tco.case.arm.135.2228:
  %t2229 = getelementptr ptr, ptr %t5, i32 1
  %t2230 = load ptr, ptr %t2229
  %t2231 = getelementptr ptr, ptr %t5, i32 2
  %t2232 = load ptr, ptr %t2231
  %t2233 = getelementptr i8, ptr %t5, i64 -8
  %t2234 = load i32, ptr %t2233
  %t2235 = icmp eq i32 %t2234, 1
  br i1 %t2235, label %reuse.in_place.2236, label %reuse.copy.2237
reuse.in_place.2236:
  %t2239 = inttoptr i64 83 to ptr
  %t2240 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2239, ptr %t2240
  br label %reuse.join.2238
reuse.copy.2237:
  %t2241 = call ptr @__alloc(i64 24, i32 2)
  %t2242 = inttoptr i64 83 to ptr
  %t2243 = getelementptr ptr, ptr %t2241, i32 0
  store ptr %t2242, ptr %t2243
  call void @__inc_ref(ptr %t2230)
  %t2244 = getelementptr ptr, ptr %t2241, i32 1
  store ptr %t2230, ptr %t2244
  call void @__inc_ref(ptr %t2232)
  %t2245 = getelementptr ptr, ptr %t2241, i32 2
  store ptr %t2232, ptr %t2245
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2238
reuse.join.2238:
  %t2246 = phi ptr [ %t5, %reuse.in_place.2236 ], [ %t2241, %reuse.copy.2237 ]
  %t2247 = call ptr @__alloc(i64 16, i32 1)
  %t2248 = inttoptr i64 226 to ptr
  %t2249 = getelementptr ptr, ptr %t2247, i32 0
  store ptr %t2248, ptr %t2249
  call void @__inc_ref(ptr %t6)
  %t2250 = getelementptr ptr, ptr %t2247, i32 1
  store ptr %t6, ptr %t2250
  call void @__free_recursive(ptr %t6)
  store ptr %t2246, ptr %t3
  store ptr %t2247, ptr %t4
  br label %tco.loop.0
tco.case.arm.136.2251:
  %t2252 = getelementptr ptr, ptr %t5, i32 1
  %t2253 = load ptr, ptr %t2252
  %t2254 = getelementptr ptr, ptr %t5, i32 2
  %t2255 = load ptr, ptr %t2254
  %t2256 = getelementptr i8, ptr %t5, i64 -8
  %t2257 = load i32, ptr %t2256
  %t2258 = icmp eq i32 %t2257, 1
  br i1 %t2258, label %reuse.in_place.2259, label %reuse.copy.2260
reuse.in_place.2259:
  %t2262 = inttoptr i64 83 to ptr
  %t2263 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2262, ptr %t2263
  br label %reuse.join.2261
reuse.copy.2260:
  %t2264 = call ptr @__alloc(i64 24, i32 2)
  %t2265 = inttoptr i64 83 to ptr
  %t2266 = getelementptr ptr, ptr %t2264, i32 0
  store ptr %t2265, ptr %t2266
  call void @__inc_ref(ptr %t2253)
  %t2267 = getelementptr ptr, ptr %t2264, i32 1
  store ptr %t2253, ptr %t2267
  call void @__inc_ref(ptr %t2255)
  %t2268 = getelementptr ptr, ptr %t2264, i32 2
  store ptr %t2255, ptr %t2268
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2261
reuse.join.2261:
  %t2269 = phi ptr [ %t5, %reuse.in_place.2259 ], [ %t2264, %reuse.copy.2260 ]
  %t2270 = call ptr @__alloc(i64 16, i32 1)
  %t2271 = inttoptr i64 227 to ptr
  %t2272 = getelementptr ptr, ptr %t2270, i32 0
  store ptr %t2271, ptr %t2272
  call void @__inc_ref(ptr %t6)
  %t2273 = getelementptr ptr, ptr %t2270, i32 1
  store ptr %t6, ptr %t2273
  call void @__free_recursive(ptr %t6)
  store ptr %t2269, ptr %t3
  store ptr %t2270, ptr %t4
  br label %tco.loop.0
tco.case.arm.137.2274:
  %t2275 = getelementptr ptr, ptr %t5, i32 1
  %t2276 = load ptr, ptr %t2275
  %t2277 = getelementptr ptr, ptr %t5, i32 2
  %t2278 = load ptr, ptr %t2277
  %t2279 = getelementptr i8, ptr %t5, i64 -8
  %t2280 = load i32, ptr %t2279
  %t2281 = icmp eq i32 %t2280, 1
  br i1 %t2281, label %reuse.in_place.2282, label %reuse.copy.2283
reuse.in_place.2282:
  %t2285 = inttoptr i64 83 to ptr
  %t2286 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2285, ptr %t2286
  br label %reuse.join.2284
reuse.copy.2283:
  %t2287 = call ptr @__alloc(i64 24, i32 2)
  %t2288 = inttoptr i64 83 to ptr
  %t2289 = getelementptr ptr, ptr %t2287, i32 0
  store ptr %t2288, ptr %t2289
  call void @__inc_ref(ptr %t2276)
  %t2290 = getelementptr ptr, ptr %t2287, i32 1
  store ptr %t2276, ptr %t2290
  call void @__inc_ref(ptr %t2278)
  %t2291 = getelementptr ptr, ptr %t2287, i32 2
  store ptr %t2278, ptr %t2291
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2284
reuse.join.2284:
  %t2292 = phi ptr [ %t5, %reuse.in_place.2282 ], [ %t2287, %reuse.copy.2283 ]
  %t2293 = call ptr @__alloc(i64 16, i32 1)
  %t2294 = inttoptr i64 228 to ptr
  %t2295 = getelementptr ptr, ptr %t2293, i32 0
  store ptr %t2294, ptr %t2295
  call void @__inc_ref(ptr %t6)
  %t2296 = getelementptr ptr, ptr %t2293, i32 1
  store ptr %t6, ptr %t2296
  call void @__free_recursive(ptr %t6)
  store ptr %t2292, ptr %t3
  store ptr %t2293, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t2297 = load ptr, ptr %t2
  ret ptr %t2297
}

define internal ptr @v__apply1(ptr %v__cl, ptr %v__arg0) {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 83 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  call void @__inc_ref(ptr %v__cl)
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v__cl, ptr %t3
  call void @__inc_ref(ptr %v__arg0)
  %t4 = getelementptr ptr, ptr %t0, i32 2
  store ptr %v__arg0, ptr %t4
  %t5 = call ptr @v__scc__apply1__df__lam_10_23__df__lam_11_1__df__lam_11_5__df__lam_11_9__df__lam_12_10__df__lam_12_2__df__lam_12_6__df__lam_13_11__df__lam_13_3__df__lam_13_7__df__lam_14_13__df__lam_14_25__df__lam_15_14__df__lam_15_26__df__lam_16_15__df__lam_16_27__df__lam_29_17__df__lam_30_18__df__lam_31_19__df__lam_36_29__df__lam_37_30__df__lam_38_31__df__lam_5_33__df__lam_5_37__df__lam_5_41__df__lam_5_45__df__lam_5_49__df__lam_5_53__df__lam_5_57__df__lam_6_34__df__lam_6_38__df__lam_6_42__df__lam_6_46__df__lam_6_50__df__lam_6_54__df__lam_6_58__df__lam_7_35__df__lam_7_39__df__lam_7_43__df__lam_7_47__df__lam_7_51__df__lam_7_55__df__lam_7_59__df__lam_8_21__df__lam_9_22__lift_2__lift_26__lift_27__lift_28__lift_3__lift_33__lift_34__lift_35__lift_4(ptr %t0)
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
