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
@.empty = private unnamed_addr constant {i32, i32, i32, i32, i32} { i32 0, i32 0, i32 0, i32 0, i32 0 }
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

define internal ptr @v__lam_13(ptr %v__u) {
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

define internal ptr @v__lam_14(ptr %v_act, ptr %v__u) {
  call void @__free_recursive(ptr %v__u)
  ret ptr %v_act
}

define internal ptr @v__lam_15(ptr %v__u) {
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

define internal ptr @v__lam_16(ptr %v__u) {
  %t0 = call ptr @v_remappedY()
  %t1 = call ptr @v_observeABC(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.5, i64 12), ptr %t1)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t2
}

define internal ptr @v__lam_17(ptr %v__u) {
  %t0 = call ptr @v_remappedX()
  %t1 = call ptr @v_observeABC(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.6, i64 12), ptr %t1)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t2
}

define internal ptr @v__lam_18(ptr %v__u) {
  %t0 = call ptr @v_mappedOk()
  %t1 = call ptr @v_observeAB(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.7, i64 12), ptr %t1)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t2
}

define internal ptr @v__lam_19(ptr %v__u) {
  %t0 = call ptr @v_mappedB()
  %t1 = call ptr @v_observeAB(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.8, i64 12), ptr %t1)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t2
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
  %t1 = inttoptr i64 120 to ptr
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
  %t43 = inttoptr i64 121 to ptr
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
  %t46 = inttoptr i64 121 to ptr
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
  %t58 = inttoptr i64 63 to ptr
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
  %t70 = inttoptr i64 67 to ptr
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
  %t82 = inttoptr i64 70 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 120, label %tco.case.arm.120.11 i64 121, label %tco.case.arm.121.12 ]
tco.case.arm.120.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.121.12:
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
  %t1 = inttoptr i64 122 to ptr
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
  %t43 = inttoptr i64 123 to ptr
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
  %t46 = inttoptr i64 123 to ptr
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
  %t58 = inttoptr i64 64 to ptr
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
  %t70 = inttoptr i64 68 to ptr
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
  %t82 = inttoptr i64 71 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 122, label %tco.case.arm.122.11 i64 123, label %tco.case.arm.123.12 ]
tco.case.arm.122.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.123.12:
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
  %t1 = inttoptr i64 124 to ptr
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
  %t43 = inttoptr i64 125 to ptr
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
  %t46 = inttoptr i64 125 to ptr
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
  %t58 = inttoptr i64 65 to ptr
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
  %t70 = inttoptr i64 66 to ptr
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
  %t82 = inttoptr i64 69 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 124, label %tco.case.arm.124.11 i64 125, label %tco.case.arm.125.12 ]
tco.case.arm.124.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.125.12:
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
  %t1 = inttoptr i64 126 to ptr
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
  %t39 = inttoptr i64 127 to ptr
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
  %t42 = inttoptr i64 127 to ptr
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
  %t54 = inttoptr i64 72 to ptr
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
  %t66 = inttoptr i64 43 to ptr
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
  %t78 = inttoptr i64 45 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 126, label %tco.case.arm.126.11 i64 127, label %tco.case.arm.127.12 ]
tco.case.arm.126.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.127.12:
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
  %t1 = inttoptr i64 128 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.16 i64 7, label %tco.case.arm.7.24 i64 8, label %tco.case.arm.8.47 i64 9, label %tco.case.arm.9.59 i64 10, label %tco.case.arm.10.71 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__bi_IO_Stdout_print(ptr %t13)
  %t15 = call ptr @v__apply__df__rowmono_0_andThenIO_16(ptr %t6, ptr %t14)
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
  %t23 = call ptr @v__apply__df__rowmono_0_andThenIO_16(ptr %t6, ptr %t19)
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
  %t39 = inttoptr i64 129 to ptr
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
  %t42 = inttoptr i64 129 to ptr
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
  %t54 = inttoptr i64 54 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  call void @__inc_ref(ptr %t49)
  %t56 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t49, ptr %t56
  %t57 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t53, ptr %t57
  %t58 = call ptr @v__apply__df__rowmono_0_andThenIO_16(ptr %t6, ptr %t50)
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
  %t66 = inttoptr i64 55 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  call void @__inc_ref(ptr %t61)
  %t68 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t61, ptr %t68
  %t69 = getelementptr ptr, ptr %t62, i32 1
  store ptr %t65, ptr %t69
  %t70 = call ptr @v__apply__df__rowmono_0_andThenIO_16(ptr %t6, ptr %t62)
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
  %t78 = inttoptr i64 56 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  call void @__inc_ref(ptr %t73)
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t73, ptr %t80
  %t81 = getelementptr ptr, ptr %t74, i32 1
  store ptr %t77, ptr %t81
  %t82 = call ptr @v__apply__df__rowmono_0_andThenIO_16(ptr %t6, ptr %t74)
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
  switch i64 %t9, label %tco.case.default.10 [ i64 128, label %tco.case.arm.128.11 i64 129, label %tco.case.arm.129.12 ]
tco.case.arm.128.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.129.12:
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
  %t1 = inttoptr i64 130 to ptr
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
  %t43 = inttoptr i64 131 to ptr
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
  %t46 = inttoptr i64 131 to ptr
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
  %t58 = inttoptr i64 60 to ptr
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
  %t70 = inttoptr i64 61 to ptr
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
  %t82 = inttoptr i64 62 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 130, label %tco.case.arm.130.11 i64 131, label %tco.case.arm.131.12 ]
tco.case.arm.130.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.131.12:
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
  %t1 = inttoptr i64 132 to ptr
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
  %t39 = inttoptr i64 133 to ptr
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
  %t42 = inttoptr i64 133 to ptr
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
  %t54 = inttoptr i64 73 to ptr
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
  %t66 = inttoptr i64 44 to ptr
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
  %t78 = inttoptr i64 46 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 132, label %tco.case.arm.132.11 i64 133, label %tco.case.arm.133.12 ]
tco.case.arm.132.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.133.12:
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
  %t1 = inttoptr i64 134 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.16 i64 7, label %tco.case.arm.7.24 i64 8, label %tco.case.arm.8.47 i64 9, label %tco.case.arm.9.59 i64 10, label %tco.case.arm.10.71 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__bi_IO_Stdout_print(ptr %t13)
  %t15 = call ptr @v__apply__df__rowmono_1_andThenIO_28(ptr %t6, ptr %t14)
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
  %t23 = call ptr @v__apply__df__rowmono_1_andThenIO_28(ptr %t6, ptr %t19)
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
  %t39 = inttoptr i64 135 to ptr
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
  %t42 = inttoptr i64 135 to ptr
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
  %t54 = inttoptr i64 57 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  call void @__inc_ref(ptr %t49)
  %t56 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t49, ptr %t56
  %t57 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t53, ptr %t57
  %t58 = call ptr @v__apply__df__rowmono_1_andThenIO_28(ptr %t6, ptr %t50)
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
  %t66 = inttoptr i64 58 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  call void @__inc_ref(ptr %t61)
  %t68 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t61, ptr %t68
  %t69 = getelementptr ptr, ptr %t62, i32 1
  store ptr %t65, ptr %t69
  %t70 = call ptr @v__apply__df__rowmono_1_andThenIO_28(ptr %t6, ptr %t62)
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
  %t78 = inttoptr i64 59 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  call void @__inc_ref(ptr %t73)
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t73, ptr %t80
  %t81 = getelementptr ptr, ptr %t74, i32 1
  store ptr %t77, ptr %t81
  %t82 = call ptr @v__apply__df__rowmono_1_andThenIO_28(ptr %t6, ptr %t74)
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
  switch i64 %t9, label %tco.case.default.10 [ i64 134, label %tco.case.arm.134.11 i64 135, label %tco.case.arm.135.12 ]
tco.case.arm.134.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.135.12:
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
  %t1 = inttoptr i64 136 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.16 i64 7, label %tco.case.arm.7.24 i64 8, label %tco.case.arm.8.47 i64 9, label %tco.case.arm.9.59 i64 10, label %tco.case.arm.10.71 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_13(ptr %t13)
  %t15 = call ptr @v__apply__df_andThenIO_32(ptr %t6, ptr %t14)
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
  %t23 = call ptr @v__apply__df_andThenIO_32(ptr %t6, ptr %t19)
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
  %t39 = inttoptr i64 137 to ptr
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
  %t42 = inttoptr i64 137 to ptr
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
  %t54 = inttoptr i64 29 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  call void @__inc_ref(ptr %t49)
  %t56 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t49, ptr %t56
  %t57 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t53, ptr %t57
  %t58 = call ptr @v__apply__df_andThenIO_32(ptr %t6, ptr %t50)
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
  %t66 = inttoptr i64 36 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  call void @__inc_ref(ptr %t61)
  %t68 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t61, ptr %t68
  %t69 = getelementptr ptr, ptr %t62, i32 1
  store ptr %t65, ptr %t69
  %t70 = call ptr @v__apply__df_andThenIO_32(ptr %t6, ptr %t62)
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
  %t78 = inttoptr i64 47 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  call void @__inc_ref(ptr %t73)
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t73, ptr %t80
  %t81 = getelementptr ptr, ptr %t74, i32 1
  store ptr %t77, ptr %t81
  %t82 = call ptr @v__apply__df_andThenIO_32(ptr %t6, ptr %t74)
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
  switch i64 %t9, label %tco.case.default.10 [ i64 136, label %tco.case.arm.136.11 i64 137, label %tco.case.arm.137.12 ]
tco.case.arm.136.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.137.12:
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
  %t1 = inttoptr i64 138 to ptr
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
  switch i64 %t11, label %tco.case.default.12 [ i64 5, label %tco.case.arm.5.13 i64 6, label %tco.case.arm.6.18 i64 7, label %tco.case.arm.7.26 i64 8, label %tco.case.arm.8.49 i64 9, label %tco.case.arm.9.62 i64 10, label %tco.case.arm.10.75 ]
tco.case.arm.5.13:
  %t14 = getelementptr ptr, ptr %t6, i32 1
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  call void @__inc_ref(ptr %t8)
  call void @__inc_ref(ptr %t7)
  call void @__inc_ref(ptr %t15)
  %t16 = call ptr @v__lam_14(ptr %t7, ptr %t15)
  %t17 = call ptr @v__apply__df_andThenIO_36(ptr %t8, ptr %t16)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t7)
  call void @__free_recursive(ptr %t8)
  store ptr %t17, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.18:
  %t19 = getelementptr ptr, ptr %t6, i32 1
  %t20 = load ptr, ptr %t19
  call void @__inc_ref(ptr %t20)
  call void @__inc_ref(ptr %t8)
  %t21 = call ptr @__alloc(i64 16, i32 1)
  %t22 = inttoptr i64 6 to ptr
  %t23 = getelementptr ptr, ptr %t21, i32 0
  store ptr %t22, ptr %t23
  call void @__inc_ref(ptr %t20)
  %t24 = getelementptr ptr, ptr %t21, i32 1
  store ptr %t20, ptr %t24
  %t25 = call ptr @v__apply__df_andThenIO_36(ptr %t8, ptr %t21)
  call void @__free_recursive(ptr %t20)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t7)
  call void @__free_recursive(ptr %t8)
  store ptr %t25, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.26:
  %t27 = getelementptr ptr, ptr %t6, i32 1
  %t28 = load ptr, ptr %t27
  %t29 = getelementptr ptr, ptr %t6, i32 2
  %t30 = load ptr, ptr %t29
  call void @__inc_ref(ptr %t30)
  %t31 = getelementptr i8, ptr %t6, i64 -8
  %t32 = load i32, ptr %t31
  %t33 = icmp eq i32 %t32, 1
  br i1 %t33, label %reuse.in_place.34, label %reuse.copy.35
reuse.in_place.34:
  %t37 = getelementptr ptr, ptr %t6, i32 2
  %t38 = load ptr, ptr %t37
  call void @__free_recursive(ptr %t38)
  %t41 = inttoptr i64 139 to ptr
  %t42 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t41, ptr %t42
  call void @__inc_ref(ptr %t8)
  %t39 = getelementptr ptr, ptr %t6, i32 1
  store ptr %t8, ptr %t39
  %t40 = getelementptr ptr, ptr %t6, i32 2
  store ptr %t28, ptr %t40
  br label %reuse.join.36
reuse.copy.35:
  %t43 = call ptr @__alloc(i64 24, i32 2)
  %t44 = inttoptr i64 139 to ptr
  %t45 = getelementptr ptr, ptr %t43, i32 0
  store ptr %t44, ptr %t45
  call void @__inc_ref(ptr %t8)
  %t46 = getelementptr ptr, ptr %t43, i32 1
  store ptr %t8, ptr %t46
  call void @__inc_ref(ptr %t28)
  %t47 = getelementptr ptr, ptr %t43, i32 2
  store ptr %t28, ptr %t47
  call void @__free_recursive(ptr %t6)
  br label %reuse.join.36
reuse.join.36:
  %t48 = phi ptr [ %t6, %reuse.in_place.34 ], [ %t43, %reuse.copy.35 ]
  call void @__inc_ref(ptr %t30)
  call void @__inc_ref(ptr %t7)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t7)
  call void @__free_recursive(ptr %t30)
  store ptr %t30, ptr %t3
  store ptr %t7, ptr %t4
  store ptr %t48, ptr %t5
  br label %tco.loop.0
tco.case.arm.8.49:
  %t50 = getelementptr ptr, ptr %t6, i32 1
  %t51 = load ptr, ptr %t50
  call void @__inc_ref(ptr %t51)
  call void @__inc_ref(ptr %t8)
  %t52 = call ptr @__alloc(i64 16, i32 1)
  %t53 = inttoptr i64 8 to ptr
  %t54 = getelementptr ptr, ptr %t52, i32 0
  store ptr %t53, ptr %t54
  %t55 = call ptr @__alloc(i64 24, i32 2)
  %t56 = inttoptr i64 30 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  call void @__inc_ref(ptr %t51)
  %t58 = getelementptr ptr, ptr %t55, i32 1
  store ptr %t51, ptr %t58
  call void @__inc_ref(ptr %t7)
  %t59 = getelementptr ptr, ptr %t55, i32 2
  store ptr %t7, ptr %t59
  %t60 = getelementptr ptr, ptr %t52, i32 1
  store ptr %t55, ptr %t60
  %t61 = call ptr @v__apply__df_andThenIO_36(ptr %t8, ptr %t52)
  call void @__free_recursive(ptr %t51)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t7)
  call void @__free_recursive(ptr %t8)
  store ptr %t61, ptr %t2
  br label %tco.exit.1
tco.case.arm.9.62:
  %t63 = getelementptr ptr, ptr %t6, i32 1
  %t64 = load ptr, ptr %t63
  call void @__inc_ref(ptr %t64)
  call void @__inc_ref(ptr %t8)
  %t65 = call ptr @__alloc(i64 16, i32 1)
  %t66 = inttoptr i64 9 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  %t68 = call ptr @__alloc(i64 24, i32 2)
  %t69 = inttoptr i64 37 to ptr
  %t70 = getelementptr ptr, ptr %t68, i32 0
  store ptr %t69, ptr %t70
  call void @__inc_ref(ptr %t64)
  %t71 = getelementptr ptr, ptr %t68, i32 1
  store ptr %t64, ptr %t71
  call void @__inc_ref(ptr %t7)
  %t72 = getelementptr ptr, ptr %t68, i32 2
  store ptr %t7, ptr %t72
  %t73 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t68, ptr %t73
  %t74 = call ptr @v__apply__df_andThenIO_36(ptr %t8, ptr %t65)
  call void @__free_recursive(ptr %t64)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t7)
  call void @__free_recursive(ptr %t8)
  store ptr %t74, ptr %t2
  br label %tco.exit.1
tco.case.arm.10.75:
  %t76 = getelementptr ptr, ptr %t6, i32 1
  %t77 = load ptr, ptr %t76
  call void @__inc_ref(ptr %t77)
  call void @__inc_ref(ptr %t8)
  %t78 = call ptr @__alloc(i64 16, i32 1)
  %t79 = inttoptr i64 10 to ptr
  %t80 = getelementptr ptr, ptr %t78, i32 0
  store ptr %t79, ptr %t80
  %t81 = call ptr @__alloc(i64 24, i32 2)
  %t82 = inttoptr i64 48 to ptr
  %t83 = getelementptr ptr, ptr %t81, i32 0
  store ptr %t82, ptr %t83
  call void @__inc_ref(ptr %t77)
  %t84 = getelementptr ptr, ptr %t81, i32 1
  store ptr %t77, ptr %t84
  call void @__inc_ref(ptr %t7)
  %t85 = getelementptr ptr, ptr %t81, i32 2
  store ptr %t7, ptr %t85
  %t86 = getelementptr ptr, ptr %t78, i32 1
  store ptr %t81, ptr %t86
  %t87 = call ptr @v__apply__df_andThenIO_36(ptr %t8, ptr %t78)
  call void @__free_recursive(ptr %t77)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t7)
  call void @__free_recursive(ptr %t8)
  store ptr %t87, ptr %t2
  br label %tco.exit.1
tco.case.default.12:
  unreachable
tco.exit.1:
  %t88 = load ptr, ptr %t2
  ret ptr %t88
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

define internal ptr @v__df_andThenIO_40(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 140 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.16 i64 7, label %tco.case.arm.7.24 i64 8, label %tco.case.arm.8.47 i64 9, label %tco.case.arm.9.59 i64 10, label %tco.case.arm.10.71 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_15(ptr %t13)
  %t15 = call ptr @v__apply__df_andThenIO_40(ptr %t6, ptr %t14)
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
  %t23 = call ptr @v__apply__df_andThenIO_40(ptr %t6, ptr %t19)
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
  %t39 = inttoptr i64 141 to ptr
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
  %t42 = inttoptr i64 141 to ptr
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
  %t58 = call ptr @v__apply__df_andThenIO_40(ptr %t6, ptr %t50)
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
  %t66 = inttoptr i64 38 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  call void @__inc_ref(ptr %t61)
  %t68 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t61, ptr %t68
  %t69 = getelementptr ptr, ptr %t62, i32 1
  store ptr %t65, ptr %t69
  %t70 = call ptr @v__apply__df_andThenIO_40(ptr %t6, ptr %t62)
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
  %t78 = inttoptr i64 49 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  call void @__inc_ref(ptr %t73)
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t73, ptr %t80
  %t81 = getelementptr ptr, ptr %t74, i32 1
  store ptr %t77, ptr %t81
  %t82 = call ptr @v__apply__df_andThenIO_40(ptr %t6, ptr %t74)
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

define internal ptr @v__df_andThenIO_44(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 142 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.16 i64 7, label %tco.case.arm.7.24 i64 8, label %tco.case.arm.8.47 i64 9, label %tco.case.arm.9.59 i64 10, label %tco.case.arm.10.71 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_16(ptr %t13)
  %t15 = call ptr @v__apply__df_andThenIO_44(ptr %t6, ptr %t14)
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
  %t23 = call ptr @v__apply__df_andThenIO_44(ptr %t6, ptr %t19)
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
  %t39 = inttoptr i64 143 to ptr
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
  %t42 = inttoptr i64 143 to ptr
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
  %t54 = inttoptr i64 32 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  call void @__inc_ref(ptr %t49)
  %t56 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t49, ptr %t56
  %t57 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t53, ptr %t57
  %t58 = call ptr @v__apply__df_andThenIO_44(ptr %t6, ptr %t50)
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
  %t66 = inttoptr i64 39 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  call void @__inc_ref(ptr %t61)
  %t68 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t61, ptr %t68
  %t69 = getelementptr ptr, ptr %t62, i32 1
  store ptr %t65, ptr %t69
  %t70 = call ptr @v__apply__df_andThenIO_44(ptr %t6, ptr %t62)
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
  %t78 = inttoptr i64 50 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  call void @__inc_ref(ptr %t73)
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t73, ptr %t80
  %t81 = getelementptr ptr, ptr %t74, i32 1
  store ptr %t77, ptr %t81
  %t82 = call ptr @v__apply__df_andThenIO_44(ptr %t6, ptr %t74)
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

define internal ptr @v__df_andThenIO_48(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 144 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.16 i64 7, label %tco.case.arm.7.24 i64 8, label %tco.case.arm.8.47 i64 9, label %tco.case.arm.9.59 i64 10, label %tco.case.arm.10.71 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_17(ptr %t13)
  %t15 = call ptr @v__apply__df_andThenIO_48(ptr %t6, ptr %t14)
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
  %t23 = call ptr @v__apply__df_andThenIO_48(ptr %t6, ptr %t19)
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
  %t39 = inttoptr i64 145 to ptr
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
  %t42 = inttoptr i64 145 to ptr
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
  %t54 = inttoptr i64 33 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  call void @__inc_ref(ptr %t49)
  %t56 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t49, ptr %t56
  %t57 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t53, ptr %t57
  %t58 = call ptr @v__apply__df_andThenIO_48(ptr %t6, ptr %t50)
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
  %t66 = inttoptr i64 40 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  call void @__inc_ref(ptr %t61)
  %t68 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t61, ptr %t68
  %t69 = getelementptr ptr, ptr %t62, i32 1
  store ptr %t65, ptr %t69
  %t70 = call ptr @v__apply__df_andThenIO_48(ptr %t6, ptr %t62)
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
  %t78 = inttoptr i64 51 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  call void @__inc_ref(ptr %t73)
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t73, ptr %t80
  %t81 = getelementptr ptr, ptr %t74, i32 1
  store ptr %t77, ptr %t81
  %t82 = call ptr @v__apply__df_andThenIO_48(ptr %t6, ptr %t74)
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

define internal ptr @v__df_andThenIO_52(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 146 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.16 i64 7, label %tco.case.arm.7.24 i64 8, label %tco.case.arm.8.47 i64 9, label %tco.case.arm.9.59 i64 10, label %tco.case.arm.10.71 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_18(ptr %t13)
  %t15 = call ptr @v__apply__df_andThenIO_52(ptr %t6, ptr %t14)
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
  %t23 = call ptr @v__apply__df_andThenIO_52(ptr %t6, ptr %t19)
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
  %t39 = inttoptr i64 147 to ptr
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
  %t42 = inttoptr i64 147 to ptr
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
  %t54 = inttoptr i64 34 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  call void @__inc_ref(ptr %t49)
  %t56 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t49, ptr %t56
  %t57 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t53, ptr %t57
  %t58 = call ptr @v__apply__df_andThenIO_52(ptr %t6, ptr %t50)
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
  %t70 = call ptr @v__apply__df_andThenIO_52(ptr %t6, ptr %t62)
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
  %t78 = inttoptr i64 52 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  call void @__inc_ref(ptr %t73)
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t73, ptr %t80
  %t81 = getelementptr ptr, ptr %t74, i32 1
  store ptr %t77, ptr %t81
  %t82 = call ptr @v__apply__df_andThenIO_52(ptr %t6, ptr %t74)
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

define internal ptr @v__df_andThenIO_56(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 148 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.16 i64 7, label %tco.case.arm.7.24 i64 8, label %tco.case.arm.8.47 i64 9, label %tco.case.arm.9.59 i64 10, label %tco.case.arm.10.71 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_19(ptr %t13)
  %t15 = call ptr @v__apply__df_andThenIO_56(ptr %t6, ptr %t14)
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
  %t23 = call ptr @v__apply__df_andThenIO_56(ptr %t6, ptr %t19)
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
  %t39 = inttoptr i64 149 to ptr
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
  %t42 = inttoptr i64 149 to ptr
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
  %t54 = inttoptr i64 35 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  call void @__inc_ref(ptr %t49)
  %t56 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t49, ptr %t56
  %t57 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t53, ptr %t57
  %t58 = call ptr @v__apply__df_andThenIO_56(ptr %t6, ptr %t50)
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
  %t70 = call ptr @v__apply__df_andThenIO_56(ptr %t6, ptr %t62)
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
  %t78 = inttoptr i64 53 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  call void @__inc_ref(ptr %t73)
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t73, ptr %t80
  %t81 = getelementptr ptr, ptr %t74, i32 1
  store ptr %t77, ptr %t81
  %t82 = call ptr @v__apply__df_andThenIO_56(ptr %t6, ptr %t74)
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

define internal ptr @v__scc__apply1__df__lam_0_33__df__lam_0_37__df__lam_0_41__df__lam_0_45__df__lam_0_49__df__lam_0_53__df__lam_0_57__df__lam_1_34__df__lam_1_38__df__lam_1_42__df__lam_1_46__df__lam_1_50__df__lam_1_54__df__lam_1_58__df__lam_10_14__df__lam_10_26__df__lam_11_15__df__lam_11_27__df__lam_2_35__df__lam_2_39__df__lam_2_43__df__lam_2_47__df__lam_2_51__df__lam_2_55__df__lam_2_59__df__lam_20_17__df__lam_21_18__df__lam_22_19__df__lam_23_29__df__lam_24_30__df__lam_25_31__df__lam_3_21__df__lam_4_22__df__lam_5_23__df__lam_6_1__df__lam_6_5__df__lam_6_9__df__lam_7_10__df__lam_7_2__df__lam_7_6__df__lam_8_11__df__lam_8_3__df__lam_8_7__df__lam_9_13__df__lam_9_25(ptr %v__args) {
  call void @__inc_ref(ptr %v__args)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 150 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__scc__apply1__df__lam_0_33__df__lam_0_37__df__lam_0_41__df__lam_0_45__df__lam_0_49__df__lam_0_53__df__lam_0_57__df__lam_1_34__df__lam_1_38__df__lam_1_42__df__lam_1_46__df__lam_1_50__df__lam_1_54__df__lam_1_58__df__lam_10_14__df__lam_10_26__df__lam_11_15__df__lam_11_27__df__lam_2_35__df__lam_2_39__df__lam_2_43__df__lam_2_47__df__lam_2_51__df__lam_2_55__df__lam_2_59__df__lam_20_17__df__lam_21_18__df__lam_22_19__df__lam_23_29__df__lam_24_30__df__lam_25_31__df__lam_3_21__df__lam_4_22__df__lam_5_23__df__lam_6_1__df__lam_6_5__df__lam_6_9__df__lam_7_10__df__lam_7_2__df__lam_7_6__df__lam_8_11__df__lam_8_3__df__lam_8_7__df__lam_9_13__df__lam_9_25(ptr %v__args, ptr %t0)
  call void @__free_recursive(ptr %v__args)
  ret ptr %t3
}

define internal ptr @v__cps__scc__apply1__df__lam_0_33__df__lam_0_37__df__lam_0_41__df__lam_0_45__df__lam_0_49__df__lam_0_53__df__lam_0_57__df__lam_1_34__df__lam_1_38__df__lam_1_42__df__lam_1_46__df__lam_1_50__df__lam_1_54__df__lam_1_58__df__lam_10_14__df__lam_10_26__df__lam_11_15__df__lam_11_27__df__lam_2_35__df__lam_2_39__df__lam_2_43__df__lam_2_47__df__lam_2_51__df__lam_2_55__df__lam_2_59__df__lam_20_17__df__lam_21_18__df__lam_22_19__df__lam_23_29__df__lam_24_30__df__lam_25_31__df__lam_3_21__df__lam_4_22__df__lam_5_23__df__lam_6_1__df__lam_6_5__df__lam_6_9__df__lam_7_10__df__lam_7_2__df__lam_7_6__df__lam_8_11__df__lam_8_3__df__lam_8_7__df__lam_9_13__df__lam_9_25(ptr %v__args, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 74, label %tco.case.arm.74.11 i64 75, label %tco.case.arm.75.893 i64 76, label %tco.case.arm.76.916 i64 77, label %tco.case.arm.77.933 i64 78, label %tco.case.arm.78.956 i64 79, label %tco.case.arm.79.979 i64 80, label %tco.case.arm.80.1002 i64 81, label %tco.case.arm.81.1025 i64 82, label %tco.case.arm.82.1048 i64 83, label %tco.case.arm.83.1071 i64 84, label %tco.case.arm.84.1088 i64 85, label %tco.case.arm.85.1111 i64 86, label %tco.case.arm.86.1134 i64 87, label %tco.case.arm.87.1157 i64 88, label %tco.case.arm.88.1180 i64 89, label %tco.case.arm.89.1203 i64 90, label %tco.case.arm.90.1226 i64 91, label %tco.case.arm.91.1249 i64 92, label %tco.case.arm.92.1272 i64 93, label %tco.case.arm.93.1295 i64 94, label %tco.case.arm.94.1318 i64 95, label %tco.case.arm.95.1335 i64 96, label %tco.case.arm.96.1358 i64 97, label %tco.case.arm.97.1381 i64 98, label %tco.case.arm.98.1404 i64 99, label %tco.case.arm.99.1427 i64 100, label %tco.case.arm.100.1450 i64 101, label %tco.case.arm.101.1473 i64 102, label %tco.case.arm.102.1496 i64 103, label %tco.case.arm.103.1519 i64 104, label %tco.case.arm.104.1542 i64 105, label %tco.case.arm.105.1565 i64 106, label %tco.case.arm.106.1588 i64 107, label %tco.case.arm.107.1611 i64 108, label %tco.case.arm.108.1634 i64 109, label %tco.case.arm.109.1657 i64 110, label %tco.case.arm.110.1680 i64 111, label %tco.case.arm.111.1703 i64 112, label %tco.case.arm.112.1726 i64 113, label %tco.case.arm.113.1749 i64 114, label %tco.case.arm.114.1772 i64 115, label %tco.case.arm.115.1795 i64 116, label %tco.case.arm.116.1818 i64 117, label %tco.case.arm.117.1841 i64 118, label %tco.case.arm.118.1864 i64 119, label %tco.case.arm.119.1887 ]
tco.case.arm.74.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t5, i32 2
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  %t16 = getelementptr ptr, ptr %t13, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %tco.case.default.19 [ i64 29, label %tco.case.arm.29.20 i64 30, label %tco.case.arm.30.40 i64 31, label %tco.case.arm.31.51 i64 32, label %tco.case.arm.32.71 i64 33, label %tco.case.arm.33.91 i64 34, label %tco.case.arm.34.111 i64 35, label %tco.case.arm.35.131 i64 36, label %tco.case.arm.36.151 i64 37, label %tco.case.arm.37.171 i64 38, label %tco.case.arm.38.182 i64 39, label %tco.case.arm.39.202 i64 40, label %tco.case.arm.40.222 i64 41, label %tco.case.arm.41.242 i64 42, label %tco.case.arm.42.262 i64 43, label %tco.case.arm.43.282 i64 44, label %tco.case.arm.44.302 i64 45, label %tco.case.arm.45.322 i64 46, label %tco.case.arm.46.342 i64 47, label %tco.case.arm.47.362 i64 48, label %tco.case.arm.48.382 i64 49, label %tco.case.arm.49.393 i64 50, label %tco.case.arm.50.413 i64 51, label %tco.case.arm.51.433 i64 52, label %tco.case.arm.52.453 i64 53, label %tco.case.arm.53.473 i64 54, label %tco.case.arm.54.493 i64 55, label %tco.case.arm.55.513 i64 56, label %tco.case.arm.56.533 i64 57, label %tco.case.arm.57.553 i64 58, label %tco.case.arm.58.573 i64 59, label %tco.case.arm.59.593 i64 60, label %tco.case.arm.60.613 i64 61, label %tco.case.arm.61.633 i64 62, label %tco.case.arm.62.653 i64 63, label %tco.case.arm.63.673 i64 64, label %tco.case.arm.64.693 i64 65, label %tco.case.arm.65.713 i64 66, label %tco.case.arm.66.733 i64 67, label %tco.case.arm.67.753 i64 68, label %tco.case.arm.68.773 i64 69, label %tco.case.arm.69.793 i64 70, label %tco.case.arm.70.813 i64 71, label %tco.case.arm.71.833 i64 72, label %tco.case.arm.72.853 i64 73, label %tco.case.arm.73.873 ]
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
  %t32 = inttoptr i64 75 to ptr
  %t33 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t32, ptr %t33
  call void @__inc_ref(ptr %t22)
  %t31 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t22, ptr %t31
  br label %reuse.join.28
reuse.copy.27:
  %t34 = call ptr @__alloc(i64 24, i32 2)
  %t35 = inttoptr i64 75 to ptr
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
  %t43 = getelementptr ptr, ptr %t13, i32 2
  %t44 = load ptr, ptr %t43
  call void @__inc_ref(ptr %t44)
  %t45 = call ptr @__alloc(i64 32, i32 3)
  %t46 = inttoptr i64 76 to ptr
  %t47 = getelementptr ptr, ptr %t45, i32 0
  store ptr %t46, ptr %t47
  call void @__inc_ref(ptr %t42)
  %t48 = getelementptr ptr, ptr %t45, i32 1
  store ptr %t42, ptr %t48
  call void @__inc_ref(ptr %t44)
  %t49 = getelementptr ptr, ptr %t45, i32 2
  store ptr %t44, ptr %t49
  call void @__inc_ref(ptr %t15)
  %t50 = getelementptr ptr, ptr %t45, i32 3
  store ptr %t15, ptr %t50
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t44)
  call void @__free_recursive(ptr %t42)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t45, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.31.51:
  %t52 = getelementptr ptr, ptr %t13, i32 1
  %t53 = load ptr, ptr %t52
  call void @__inc_ref(ptr %t53)
  %t54 = getelementptr i8, ptr %t5, i64 -8
  %t55 = load i32, ptr %t54
  %t56 = icmp eq i32 %t55, 1
  br i1 %t56, label %reuse.in_place.57, label %reuse.copy.58
reuse.in_place.57:
  %t60 = getelementptr ptr, ptr %t5, i32 1
  %t61 = load ptr, ptr %t60
  call void @__free_recursive(ptr %t61)
  %t63 = inttoptr i64 77 to ptr
  %t64 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t63, ptr %t64
  call void @__inc_ref(ptr %t53)
  %t62 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t53, ptr %t62
  br label %reuse.join.59
reuse.copy.58:
  %t65 = call ptr @__alloc(i64 24, i32 2)
  %t66 = inttoptr i64 77 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  call void @__inc_ref(ptr %t53)
  %t68 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t53, ptr %t68
  call void @__inc_ref(ptr %t15)
  %t69 = getelementptr ptr, ptr %t65, i32 2
  store ptr %t15, ptr %t69
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.59
reuse.join.59:
  %t70 = phi ptr [ %t5, %reuse.in_place.57 ], [ %t65, %reuse.copy.58 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t53)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t70, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.32.71:
  %t72 = getelementptr ptr, ptr %t13, i32 1
  %t73 = load ptr, ptr %t72
  call void @__inc_ref(ptr %t73)
  %t74 = getelementptr i8, ptr %t5, i64 -8
  %t75 = load i32, ptr %t74
  %t76 = icmp eq i32 %t75, 1
  br i1 %t76, label %reuse.in_place.77, label %reuse.copy.78
reuse.in_place.77:
  %t80 = getelementptr ptr, ptr %t5, i32 1
  %t81 = load ptr, ptr %t80
  call void @__free_recursive(ptr %t81)
  %t83 = inttoptr i64 78 to ptr
  %t84 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t83, ptr %t84
  call void @__inc_ref(ptr %t73)
  %t82 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t73, ptr %t82
  br label %reuse.join.79
reuse.copy.78:
  %t85 = call ptr @__alloc(i64 24, i32 2)
  %t86 = inttoptr i64 78 to ptr
  %t87 = getelementptr ptr, ptr %t85, i32 0
  store ptr %t86, ptr %t87
  call void @__inc_ref(ptr %t73)
  %t88 = getelementptr ptr, ptr %t85, i32 1
  store ptr %t73, ptr %t88
  call void @__inc_ref(ptr %t15)
  %t89 = getelementptr ptr, ptr %t85, i32 2
  store ptr %t15, ptr %t89
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.79
reuse.join.79:
  %t90 = phi ptr [ %t5, %reuse.in_place.77 ], [ %t85, %reuse.copy.78 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t73)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t90, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.33.91:
  %t92 = getelementptr ptr, ptr %t13, i32 1
  %t93 = load ptr, ptr %t92
  call void @__inc_ref(ptr %t93)
  %t94 = getelementptr i8, ptr %t5, i64 -8
  %t95 = load i32, ptr %t94
  %t96 = icmp eq i32 %t95, 1
  br i1 %t96, label %reuse.in_place.97, label %reuse.copy.98
reuse.in_place.97:
  %t100 = getelementptr ptr, ptr %t5, i32 1
  %t101 = load ptr, ptr %t100
  call void @__free_recursive(ptr %t101)
  %t103 = inttoptr i64 79 to ptr
  %t104 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t103, ptr %t104
  call void @__inc_ref(ptr %t93)
  %t102 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t93, ptr %t102
  br label %reuse.join.99
reuse.copy.98:
  %t105 = call ptr @__alloc(i64 24, i32 2)
  %t106 = inttoptr i64 79 to ptr
  %t107 = getelementptr ptr, ptr %t105, i32 0
  store ptr %t106, ptr %t107
  call void @__inc_ref(ptr %t93)
  %t108 = getelementptr ptr, ptr %t105, i32 1
  store ptr %t93, ptr %t108
  call void @__inc_ref(ptr %t15)
  %t109 = getelementptr ptr, ptr %t105, i32 2
  store ptr %t15, ptr %t109
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.99
reuse.join.99:
  %t110 = phi ptr [ %t5, %reuse.in_place.97 ], [ %t105, %reuse.copy.98 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t93)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t110, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.34.111:
  %t112 = getelementptr ptr, ptr %t13, i32 1
  %t113 = load ptr, ptr %t112
  call void @__inc_ref(ptr %t113)
  %t114 = getelementptr i8, ptr %t5, i64 -8
  %t115 = load i32, ptr %t114
  %t116 = icmp eq i32 %t115, 1
  br i1 %t116, label %reuse.in_place.117, label %reuse.copy.118
reuse.in_place.117:
  %t120 = getelementptr ptr, ptr %t5, i32 1
  %t121 = load ptr, ptr %t120
  call void @__free_recursive(ptr %t121)
  %t123 = inttoptr i64 80 to ptr
  %t124 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t123, ptr %t124
  call void @__inc_ref(ptr %t113)
  %t122 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t113, ptr %t122
  br label %reuse.join.119
reuse.copy.118:
  %t125 = call ptr @__alloc(i64 24, i32 2)
  %t126 = inttoptr i64 80 to ptr
  %t127 = getelementptr ptr, ptr %t125, i32 0
  store ptr %t126, ptr %t127
  call void @__inc_ref(ptr %t113)
  %t128 = getelementptr ptr, ptr %t125, i32 1
  store ptr %t113, ptr %t128
  call void @__inc_ref(ptr %t15)
  %t129 = getelementptr ptr, ptr %t125, i32 2
  store ptr %t15, ptr %t129
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.119
reuse.join.119:
  %t130 = phi ptr [ %t5, %reuse.in_place.117 ], [ %t125, %reuse.copy.118 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t113)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t130, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.35.131:
  %t132 = getelementptr ptr, ptr %t13, i32 1
  %t133 = load ptr, ptr %t132
  call void @__inc_ref(ptr %t133)
  %t134 = getelementptr i8, ptr %t5, i64 -8
  %t135 = load i32, ptr %t134
  %t136 = icmp eq i32 %t135, 1
  br i1 %t136, label %reuse.in_place.137, label %reuse.copy.138
reuse.in_place.137:
  %t140 = getelementptr ptr, ptr %t5, i32 1
  %t141 = load ptr, ptr %t140
  call void @__free_recursive(ptr %t141)
  %t143 = inttoptr i64 81 to ptr
  %t144 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t143, ptr %t144
  call void @__inc_ref(ptr %t133)
  %t142 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t133, ptr %t142
  br label %reuse.join.139
reuse.copy.138:
  %t145 = call ptr @__alloc(i64 24, i32 2)
  %t146 = inttoptr i64 81 to ptr
  %t147 = getelementptr ptr, ptr %t145, i32 0
  store ptr %t146, ptr %t147
  call void @__inc_ref(ptr %t133)
  %t148 = getelementptr ptr, ptr %t145, i32 1
  store ptr %t133, ptr %t148
  call void @__inc_ref(ptr %t15)
  %t149 = getelementptr ptr, ptr %t145, i32 2
  store ptr %t15, ptr %t149
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.139
reuse.join.139:
  %t150 = phi ptr [ %t5, %reuse.in_place.137 ], [ %t145, %reuse.copy.138 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t133)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t150, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.36.151:
  %t152 = getelementptr ptr, ptr %t13, i32 1
  %t153 = load ptr, ptr %t152
  call void @__inc_ref(ptr %t153)
  %t154 = getelementptr i8, ptr %t5, i64 -8
  %t155 = load i32, ptr %t154
  %t156 = icmp eq i32 %t155, 1
  br i1 %t156, label %reuse.in_place.157, label %reuse.copy.158
reuse.in_place.157:
  %t160 = getelementptr ptr, ptr %t5, i32 1
  %t161 = load ptr, ptr %t160
  call void @__free_recursive(ptr %t161)
  %t163 = inttoptr i64 82 to ptr
  %t164 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t163, ptr %t164
  call void @__inc_ref(ptr %t153)
  %t162 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t153, ptr %t162
  br label %reuse.join.159
reuse.copy.158:
  %t165 = call ptr @__alloc(i64 24, i32 2)
  %t166 = inttoptr i64 82 to ptr
  %t167 = getelementptr ptr, ptr %t165, i32 0
  store ptr %t166, ptr %t167
  call void @__inc_ref(ptr %t153)
  %t168 = getelementptr ptr, ptr %t165, i32 1
  store ptr %t153, ptr %t168
  call void @__inc_ref(ptr %t15)
  %t169 = getelementptr ptr, ptr %t165, i32 2
  store ptr %t15, ptr %t169
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.159
reuse.join.159:
  %t170 = phi ptr [ %t5, %reuse.in_place.157 ], [ %t165, %reuse.copy.158 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t153)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t170, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.37.171:
  %t172 = getelementptr ptr, ptr %t13, i32 1
  %t173 = load ptr, ptr %t172
  call void @__inc_ref(ptr %t173)
  %t174 = getelementptr ptr, ptr %t13, i32 2
  %t175 = load ptr, ptr %t174
  call void @__inc_ref(ptr %t175)
  %t176 = call ptr @__alloc(i64 32, i32 3)
  %t177 = inttoptr i64 83 to ptr
  %t178 = getelementptr ptr, ptr %t176, i32 0
  store ptr %t177, ptr %t178
  call void @__inc_ref(ptr %t173)
  %t179 = getelementptr ptr, ptr %t176, i32 1
  store ptr %t173, ptr %t179
  call void @__inc_ref(ptr %t175)
  %t180 = getelementptr ptr, ptr %t176, i32 2
  store ptr %t175, ptr %t180
  call void @__inc_ref(ptr %t15)
  %t181 = getelementptr ptr, ptr %t176, i32 3
  store ptr %t15, ptr %t181
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t175)
  call void @__free_recursive(ptr %t173)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t176, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.38.182:
  %t183 = getelementptr ptr, ptr %t13, i32 1
  %t184 = load ptr, ptr %t183
  call void @__inc_ref(ptr %t184)
  %t185 = getelementptr i8, ptr %t5, i64 -8
  %t186 = load i32, ptr %t185
  %t187 = icmp eq i32 %t186, 1
  br i1 %t187, label %reuse.in_place.188, label %reuse.copy.189
reuse.in_place.188:
  %t191 = getelementptr ptr, ptr %t5, i32 1
  %t192 = load ptr, ptr %t191
  call void @__free_recursive(ptr %t192)
  %t194 = inttoptr i64 84 to ptr
  %t195 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t194, ptr %t195
  call void @__inc_ref(ptr %t184)
  %t193 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t184, ptr %t193
  br label %reuse.join.190
reuse.copy.189:
  %t196 = call ptr @__alloc(i64 24, i32 2)
  %t197 = inttoptr i64 84 to ptr
  %t198 = getelementptr ptr, ptr %t196, i32 0
  store ptr %t197, ptr %t198
  call void @__inc_ref(ptr %t184)
  %t199 = getelementptr ptr, ptr %t196, i32 1
  store ptr %t184, ptr %t199
  call void @__inc_ref(ptr %t15)
  %t200 = getelementptr ptr, ptr %t196, i32 2
  store ptr %t15, ptr %t200
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.190
reuse.join.190:
  %t201 = phi ptr [ %t5, %reuse.in_place.188 ], [ %t196, %reuse.copy.189 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t184)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t201, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.39.202:
  %t203 = getelementptr ptr, ptr %t13, i32 1
  %t204 = load ptr, ptr %t203
  call void @__inc_ref(ptr %t204)
  %t205 = getelementptr i8, ptr %t5, i64 -8
  %t206 = load i32, ptr %t205
  %t207 = icmp eq i32 %t206, 1
  br i1 %t207, label %reuse.in_place.208, label %reuse.copy.209
reuse.in_place.208:
  %t211 = getelementptr ptr, ptr %t5, i32 1
  %t212 = load ptr, ptr %t211
  call void @__free_recursive(ptr %t212)
  %t214 = inttoptr i64 85 to ptr
  %t215 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t214, ptr %t215
  call void @__inc_ref(ptr %t204)
  %t213 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t204, ptr %t213
  br label %reuse.join.210
reuse.copy.209:
  %t216 = call ptr @__alloc(i64 24, i32 2)
  %t217 = inttoptr i64 85 to ptr
  %t218 = getelementptr ptr, ptr %t216, i32 0
  store ptr %t217, ptr %t218
  call void @__inc_ref(ptr %t204)
  %t219 = getelementptr ptr, ptr %t216, i32 1
  store ptr %t204, ptr %t219
  call void @__inc_ref(ptr %t15)
  %t220 = getelementptr ptr, ptr %t216, i32 2
  store ptr %t15, ptr %t220
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.210
reuse.join.210:
  %t221 = phi ptr [ %t5, %reuse.in_place.208 ], [ %t216, %reuse.copy.209 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t204)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t221, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.40.222:
  %t223 = getelementptr ptr, ptr %t13, i32 1
  %t224 = load ptr, ptr %t223
  call void @__inc_ref(ptr %t224)
  %t225 = getelementptr i8, ptr %t5, i64 -8
  %t226 = load i32, ptr %t225
  %t227 = icmp eq i32 %t226, 1
  br i1 %t227, label %reuse.in_place.228, label %reuse.copy.229
reuse.in_place.228:
  %t231 = getelementptr ptr, ptr %t5, i32 1
  %t232 = load ptr, ptr %t231
  call void @__free_recursive(ptr %t232)
  %t234 = inttoptr i64 86 to ptr
  %t235 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t234, ptr %t235
  call void @__inc_ref(ptr %t224)
  %t233 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t224, ptr %t233
  br label %reuse.join.230
reuse.copy.229:
  %t236 = call ptr @__alloc(i64 24, i32 2)
  %t237 = inttoptr i64 86 to ptr
  %t238 = getelementptr ptr, ptr %t236, i32 0
  store ptr %t237, ptr %t238
  call void @__inc_ref(ptr %t224)
  %t239 = getelementptr ptr, ptr %t236, i32 1
  store ptr %t224, ptr %t239
  call void @__inc_ref(ptr %t15)
  %t240 = getelementptr ptr, ptr %t236, i32 2
  store ptr %t15, ptr %t240
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.230
reuse.join.230:
  %t241 = phi ptr [ %t5, %reuse.in_place.228 ], [ %t236, %reuse.copy.229 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t224)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t241, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.41.242:
  %t243 = getelementptr ptr, ptr %t13, i32 1
  %t244 = load ptr, ptr %t243
  call void @__inc_ref(ptr %t244)
  %t245 = getelementptr i8, ptr %t5, i64 -8
  %t246 = load i32, ptr %t245
  %t247 = icmp eq i32 %t246, 1
  br i1 %t247, label %reuse.in_place.248, label %reuse.copy.249
reuse.in_place.248:
  %t251 = getelementptr ptr, ptr %t5, i32 1
  %t252 = load ptr, ptr %t251
  call void @__free_recursive(ptr %t252)
  %t254 = inttoptr i64 87 to ptr
  %t255 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t254, ptr %t255
  call void @__inc_ref(ptr %t244)
  %t253 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t244, ptr %t253
  br label %reuse.join.250
reuse.copy.249:
  %t256 = call ptr @__alloc(i64 24, i32 2)
  %t257 = inttoptr i64 87 to ptr
  %t258 = getelementptr ptr, ptr %t256, i32 0
  store ptr %t257, ptr %t258
  call void @__inc_ref(ptr %t244)
  %t259 = getelementptr ptr, ptr %t256, i32 1
  store ptr %t244, ptr %t259
  call void @__inc_ref(ptr %t15)
  %t260 = getelementptr ptr, ptr %t256, i32 2
  store ptr %t15, ptr %t260
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.250
reuse.join.250:
  %t261 = phi ptr [ %t5, %reuse.in_place.248 ], [ %t256, %reuse.copy.249 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t244)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t261, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.42.262:
  %t263 = getelementptr ptr, ptr %t13, i32 1
  %t264 = load ptr, ptr %t263
  call void @__inc_ref(ptr %t264)
  %t265 = getelementptr i8, ptr %t5, i64 -8
  %t266 = load i32, ptr %t265
  %t267 = icmp eq i32 %t266, 1
  br i1 %t267, label %reuse.in_place.268, label %reuse.copy.269
reuse.in_place.268:
  %t271 = getelementptr ptr, ptr %t5, i32 1
  %t272 = load ptr, ptr %t271
  call void @__free_recursive(ptr %t272)
  %t274 = inttoptr i64 88 to ptr
  %t275 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t274, ptr %t275
  call void @__inc_ref(ptr %t264)
  %t273 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t264, ptr %t273
  br label %reuse.join.270
reuse.copy.269:
  %t276 = call ptr @__alloc(i64 24, i32 2)
  %t277 = inttoptr i64 88 to ptr
  %t278 = getelementptr ptr, ptr %t276, i32 0
  store ptr %t277, ptr %t278
  call void @__inc_ref(ptr %t264)
  %t279 = getelementptr ptr, ptr %t276, i32 1
  store ptr %t264, ptr %t279
  call void @__inc_ref(ptr %t15)
  %t280 = getelementptr ptr, ptr %t276, i32 2
  store ptr %t15, ptr %t280
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.270
reuse.join.270:
  %t281 = phi ptr [ %t5, %reuse.in_place.268 ], [ %t276, %reuse.copy.269 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t264)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t281, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.43.282:
  %t283 = getelementptr ptr, ptr %t13, i32 1
  %t284 = load ptr, ptr %t283
  call void @__inc_ref(ptr %t284)
  %t285 = getelementptr i8, ptr %t5, i64 -8
  %t286 = load i32, ptr %t285
  %t287 = icmp eq i32 %t286, 1
  br i1 %t287, label %reuse.in_place.288, label %reuse.copy.289
reuse.in_place.288:
  %t291 = getelementptr ptr, ptr %t5, i32 1
  %t292 = load ptr, ptr %t291
  call void @__free_recursive(ptr %t292)
  %t294 = inttoptr i64 89 to ptr
  %t295 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t294, ptr %t295
  call void @__inc_ref(ptr %t284)
  %t293 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t284, ptr %t293
  br label %reuse.join.290
reuse.copy.289:
  %t296 = call ptr @__alloc(i64 24, i32 2)
  %t297 = inttoptr i64 89 to ptr
  %t298 = getelementptr ptr, ptr %t296, i32 0
  store ptr %t297, ptr %t298
  call void @__inc_ref(ptr %t284)
  %t299 = getelementptr ptr, ptr %t296, i32 1
  store ptr %t284, ptr %t299
  call void @__inc_ref(ptr %t15)
  %t300 = getelementptr ptr, ptr %t296, i32 2
  store ptr %t15, ptr %t300
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.290
reuse.join.290:
  %t301 = phi ptr [ %t5, %reuse.in_place.288 ], [ %t296, %reuse.copy.289 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t284)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t301, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.44.302:
  %t303 = getelementptr ptr, ptr %t13, i32 1
  %t304 = load ptr, ptr %t303
  call void @__inc_ref(ptr %t304)
  %t305 = getelementptr i8, ptr %t5, i64 -8
  %t306 = load i32, ptr %t305
  %t307 = icmp eq i32 %t306, 1
  br i1 %t307, label %reuse.in_place.308, label %reuse.copy.309
reuse.in_place.308:
  %t311 = getelementptr ptr, ptr %t5, i32 1
  %t312 = load ptr, ptr %t311
  call void @__free_recursive(ptr %t312)
  %t314 = inttoptr i64 90 to ptr
  %t315 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t314, ptr %t315
  call void @__inc_ref(ptr %t304)
  %t313 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t304, ptr %t313
  br label %reuse.join.310
reuse.copy.309:
  %t316 = call ptr @__alloc(i64 24, i32 2)
  %t317 = inttoptr i64 90 to ptr
  %t318 = getelementptr ptr, ptr %t316, i32 0
  store ptr %t317, ptr %t318
  call void @__inc_ref(ptr %t304)
  %t319 = getelementptr ptr, ptr %t316, i32 1
  store ptr %t304, ptr %t319
  call void @__inc_ref(ptr %t15)
  %t320 = getelementptr ptr, ptr %t316, i32 2
  store ptr %t15, ptr %t320
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.310
reuse.join.310:
  %t321 = phi ptr [ %t5, %reuse.in_place.308 ], [ %t316, %reuse.copy.309 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t304)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t321, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.45.322:
  %t323 = getelementptr ptr, ptr %t13, i32 1
  %t324 = load ptr, ptr %t323
  call void @__inc_ref(ptr %t324)
  %t325 = getelementptr i8, ptr %t5, i64 -8
  %t326 = load i32, ptr %t325
  %t327 = icmp eq i32 %t326, 1
  br i1 %t327, label %reuse.in_place.328, label %reuse.copy.329
reuse.in_place.328:
  %t331 = getelementptr ptr, ptr %t5, i32 1
  %t332 = load ptr, ptr %t331
  call void @__free_recursive(ptr %t332)
  %t334 = inttoptr i64 91 to ptr
  %t335 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t334, ptr %t335
  call void @__inc_ref(ptr %t324)
  %t333 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t324, ptr %t333
  br label %reuse.join.330
reuse.copy.329:
  %t336 = call ptr @__alloc(i64 24, i32 2)
  %t337 = inttoptr i64 91 to ptr
  %t338 = getelementptr ptr, ptr %t336, i32 0
  store ptr %t337, ptr %t338
  call void @__inc_ref(ptr %t324)
  %t339 = getelementptr ptr, ptr %t336, i32 1
  store ptr %t324, ptr %t339
  call void @__inc_ref(ptr %t15)
  %t340 = getelementptr ptr, ptr %t336, i32 2
  store ptr %t15, ptr %t340
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.330
reuse.join.330:
  %t341 = phi ptr [ %t5, %reuse.in_place.328 ], [ %t336, %reuse.copy.329 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t324)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t341, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.46.342:
  %t343 = getelementptr ptr, ptr %t13, i32 1
  %t344 = load ptr, ptr %t343
  call void @__inc_ref(ptr %t344)
  %t345 = getelementptr i8, ptr %t5, i64 -8
  %t346 = load i32, ptr %t345
  %t347 = icmp eq i32 %t346, 1
  br i1 %t347, label %reuse.in_place.348, label %reuse.copy.349
reuse.in_place.348:
  %t351 = getelementptr ptr, ptr %t5, i32 1
  %t352 = load ptr, ptr %t351
  call void @__free_recursive(ptr %t352)
  %t354 = inttoptr i64 92 to ptr
  %t355 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t354, ptr %t355
  call void @__inc_ref(ptr %t344)
  %t353 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t344, ptr %t353
  br label %reuse.join.350
reuse.copy.349:
  %t356 = call ptr @__alloc(i64 24, i32 2)
  %t357 = inttoptr i64 92 to ptr
  %t358 = getelementptr ptr, ptr %t356, i32 0
  store ptr %t357, ptr %t358
  call void @__inc_ref(ptr %t344)
  %t359 = getelementptr ptr, ptr %t356, i32 1
  store ptr %t344, ptr %t359
  call void @__inc_ref(ptr %t15)
  %t360 = getelementptr ptr, ptr %t356, i32 2
  store ptr %t15, ptr %t360
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.350
reuse.join.350:
  %t361 = phi ptr [ %t5, %reuse.in_place.348 ], [ %t356, %reuse.copy.349 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t344)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t361, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.47.362:
  %t363 = getelementptr ptr, ptr %t13, i32 1
  %t364 = load ptr, ptr %t363
  call void @__inc_ref(ptr %t364)
  %t365 = getelementptr i8, ptr %t5, i64 -8
  %t366 = load i32, ptr %t365
  %t367 = icmp eq i32 %t366, 1
  br i1 %t367, label %reuse.in_place.368, label %reuse.copy.369
reuse.in_place.368:
  %t371 = getelementptr ptr, ptr %t5, i32 1
  %t372 = load ptr, ptr %t371
  call void @__free_recursive(ptr %t372)
  %t374 = inttoptr i64 93 to ptr
  %t375 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t374, ptr %t375
  call void @__inc_ref(ptr %t364)
  %t373 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t364, ptr %t373
  br label %reuse.join.370
reuse.copy.369:
  %t376 = call ptr @__alloc(i64 24, i32 2)
  %t377 = inttoptr i64 93 to ptr
  %t378 = getelementptr ptr, ptr %t376, i32 0
  store ptr %t377, ptr %t378
  call void @__inc_ref(ptr %t364)
  %t379 = getelementptr ptr, ptr %t376, i32 1
  store ptr %t364, ptr %t379
  call void @__inc_ref(ptr %t15)
  %t380 = getelementptr ptr, ptr %t376, i32 2
  store ptr %t15, ptr %t380
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.370
reuse.join.370:
  %t381 = phi ptr [ %t5, %reuse.in_place.368 ], [ %t376, %reuse.copy.369 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t364)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t381, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.48.382:
  %t383 = getelementptr ptr, ptr %t13, i32 1
  %t384 = load ptr, ptr %t383
  call void @__inc_ref(ptr %t384)
  %t385 = getelementptr ptr, ptr %t13, i32 2
  %t386 = load ptr, ptr %t385
  call void @__inc_ref(ptr %t386)
  %t387 = call ptr @__alloc(i64 32, i32 3)
  %t388 = inttoptr i64 94 to ptr
  %t389 = getelementptr ptr, ptr %t387, i32 0
  store ptr %t388, ptr %t389
  call void @__inc_ref(ptr %t384)
  %t390 = getelementptr ptr, ptr %t387, i32 1
  store ptr %t384, ptr %t390
  call void @__inc_ref(ptr %t386)
  %t391 = getelementptr ptr, ptr %t387, i32 2
  store ptr %t386, ptr %t391
  call void @__inc_ref(ptr %t15)
  %t392 = getelementptr ptr, ptr %t387, i32 3
  store ptr %t15, ptr %t392
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t386)
  call void @__free_recursive(ptr %t384)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t387, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.49.393:
  %t394 = getelementptr ptr, ptr %t13, i32 1
  %t395 = load ptr, ptr %t394
  call void @__inc_ref(ptr %t395)
  %t396 = getelementptr i8, ptr %t5, i64 -8
  %t397 = load i32, ptr %t396
  %t398 = icmp eq i32 %t397, 1
  br i1 %t398, label %reuse.in_place.399, label %reuse.copy.400
reuse.in_place.399:
  %t402 = getelementptr ptr, ptr %t5, i32 1
  %t403 = load ptr, ptr %t402
  call void @__free_recursive(ptr %t403)
  %t405 = inttoptr i64 95 to ptr
  %t406 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t405, ptr %t406
  call void @__inc_ref(ptr %t395)
  %t404 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t395, ptr %t404
  br label %reuse.join.401
reuse.copy.400:
  %t407 = call ptr @__alloc(i64 24, i32 2)
  %t408 = inttoptr i64 95 to ptr
  %t409 = getelementptr ptr, ptr %t407, i32 0
  store ptr %t408, ptr %t409
  call void @__inc_ref(ptr %t395)
  %t410 = getelementptr ptr, ptr %t407, i32 1
  store ptr %t395, ptr %t410
  call void @__inc_ref(ptr %t15)
  %t411 = getelementptr ptr, ptr %t407, i32 2
  store ptr %t15, ptr %t411
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.401
reuse.join.401:
  %t412 = phi ptr [ %t5, %reuse.in_place.399 ], [ %t407, %reuse.copy.400 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t395)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t412, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.50.413:
  %t414 = getelementptr ptr, ptr %t13, i32 1
  %t415 = load ptr, ptr %t414
  call void @__inc_ref(ptr %t415)
  %t416 = getelementptr i8, ptr %t5, i64 -8
  %t417 = load i32, ptr %t416
  %t418 = icmp eq i32 %t417, 1
  br i1 %t418, label %reuse.in_place.419, label %reuse.copy.420
reuse.in_place.419:
  %t422 = getelementptr ptr, ptr %t5, i32 1
  %t423 = load ptr, ptr %t422
  call void @__free_recursive(ptr %t423)
  %t425 = inttoptr i64 96 to ptr
  %t426 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t425, ptr %t426
  call void @__inc_ref(ptr %t415)
  %t424 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t415, ptr %t424
  br label %reuse.join.421
reuse.copy.420:
  %t427 = call ptr @__alloc(i64 24, i32 2)
  %t428 = inttoptr i64 96 to ptr
  %t429 = getelementptr ptr, ptr %t427, i32 0
  store ptr %t428, ptr %t429
  call void @__inc_ref(ptr %t415)
  %t430 = getelementptr ptr, ptr %t427, i32 1
  store ptr %t415, ptr %t430
  call void @__inc_ref(ptr %t15)
  %t431 = getelementptr ptr, ptr %t427, i32 2
  store ptr %t15, ptr %t431
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.421
reuse.join.421:
  %t432 = phi ptr [ %t5, %reuse.in_place.419 ], [ %t427, %reuse.copy.420 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t415)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t432, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.51.433:
  %t434 = getelementptr ptr, ptr %t13, i32 1
  %t435 = load ptr, ptr %t434
  call void @__inc_ref(ptr %t435)
  %t436 = getelementptr i8, ptr %t5, i64 -8
  %t437 = load i32, ptr %t436
  %t438 = icmp eq i32 %t437, 1
  br i1 %t438, label %reuse.in_place.439, label %reuse.copy.440
reuse.in_place.439:
  %t442 = getelementptr ptr, ptr %t5, i32 1
  %t443 = load ptr, ptr %t442
  call void @__free_recursive(ptr %t443)
  %t445 = inttoptr i64 97 to ptr
  %t446 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t445, ptr %t446
  call void @__inc_ref(ptr %t435)
  %t444 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t435, ptr %t444
  br label %reuse.join.441
reuse.copy.440:
  %t447 = call ptr @__alloc(i64 24, i32 2)
  %t448 = inttoptr i64 97 to ptr
  %t449 = getelementptr ptr, ptr %t447, i32 0
  store ptr %t448, ptr %t449
  call void @__inc_ref(ptr %t435)
  %t450 = getelementptr ptr, ptr %t447, i32 1
  store ptr %t435, ptr %t450
  call void @__inc_ref(ptr %t15)
  %t451 = getelementptr ptr, ptr %t447, i32 2
  store ptr %t15, ptr %t451
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.441
reuse.join.441:
  %t452 = phi ptr [ %t5, %reuse.in_place.439 ], [ %t447, %reuse.copy.440 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t435)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t452, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.52.453:
  %t454 = getelementptr ptr, ptr %t13, i32 1
  %t455 = load ptr, ptr %t454
  call void @__inc_ref(ptr %t455)
  %t456 = getelementptr i8, ptr %t5, i64 -8
  %t457 = load i32, ptr %t456
  %t458 = icmp eq i32 %t457, 1
  br i1 %t458, label %reuse.in_place.459, label %reuse.copy.460
reuse.in_place.459:
  %t462 = getelementptr ptr, ptr %t5, i32 1
  %t463 = load ptr, ptr %t462
  call void @__free_recursive(ptr %t463)
  %t465 = inttoptr i64 98 to ptr
  %t466 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t465, ptr %t466
  call void @__inc_ref(ptr %t455)
  %t464 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t455, ptr %t464
  br label %reuse.join.461
reuse.copy.460:
  %t467 = call ptr @__alloc(i64 24, i32 2)
  %t468 = inttoptr i64 98 to ptr
  %t469 = getelementptr ptr, ptr %t467, i32 0
  store ptr %t468, ptr %t469
  call void @__inc_ref(ptr %t455)
  %t470 = getelementptr ptr, ptr %t467, i32 1
  store ptr %t455, ptr %t470
  call void @__inc_ref(ptr %t15)
  %t471 = getelementptr ptr, ptr %t467, i32 2
  store ptr %t15, ptr %t471
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.461
reuse.join.461:
  %t472 = phi ptr [ %t5, %reuse.in_place.459 ], [ %t467, %reuse.copy.460 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t455)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t472, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.53.473:
  %t474 = getelementptr ptr, ptr %t13, i32 1
  %t475 = load ptr, ptr %t474
  call void @__inc_ref(ptr %t475)
  %t476 = getelementptr i8, ptr %t5, i64 -8
  %t477 = load i32, ptr %t476
  %t478 = icmp eq i32 %t477, 1
  br i1 %t478, label %reuse.in_place.479, label %reuse.copy.480
reuse.in_place.479:
  %t482 = getelementptr ptr, ptr %t5, i32 1
  %t483 = load ptr, ptr %t482
  call void @__free_recursive(ptr %t483)
  %t485 = inttoptr i64 99 to ptr
  %t486 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t485, ptr %t486
  call void @__inc_ref(ptr %t475)
  %t484 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t475, ptr %t484
  br label %reuse.join.481
reuse.copy.480:
  %t487 = call ptr @__alloc(i64 24, i32 2)
  %t488 = inttoptr i64 99 to ptr
  %t489 = getelementptr ptr, ptr %t487, i32 0
  store ptr %t488, ptr %t489
  call void @__inc_ref(ptr %t475)
  %t490 = getelementptr ptr, ptr %t487, i32 1
  store ptr %t475, ptr %t490
  call void @__inc_ref(ptr %t15)
  %t491 = getelementptr ptr, ptr %t487, i32 2
  store ptr %t15, ptr %t491
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.481
reuse.join.481:
  %t492 = phi ptr [ %t5, %reuse.in_place.479 ], [ %t487, %reuse.copy.480 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t475)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t492, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.54.493:
  %t494 = getelementptr ptr, ptr %t13, i32 1
  %t495 = load ptr, ptr %t494
  call void @__inc_ref(ptr %t495)
  %t496 = getelementptr i8, ptr %t5, i64 -8
  %t497 = load i32, ptr %t496
  %t498 = icmp eq i32 %t497, 1
  br i1 %t498, label %reuse.in_place.499, label %reuse.copy.500
reuse.in_place.499:
  %t502 = getelementptr ptr, ptr %t5, i32 1
  %t503 = load ptr, ptr %t502
  call void @__free_recursive(ptr %t503)
  %t505 = inttoptr i64 100 to ptr
  %t506 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t505, ptr %t506
  call void @__inc_ref(ptr %t495)
  %t504 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t495, ptr %t504
  br label %reuse.join.501
reuse.copy.500:
  %t507 = call ptr @__alloc(i64 24, i32 2)
  %t508 = inttoptr i64 100 to ptr
  %t509 = getelementptr ptr, ptr %t507, i32 0
  store ptr %t508, ptr %t509
  call void @__inc_ref(ptr %t495)
  %t510 = getelementptr ptr, ptr %t507, i32 1
  store ptr %t495, ptr %t510
  call void @__inc_ref(ptr %t15)
  %t511 = getelementptr ptr, ptr %t507, i32 2
  store ptr %t15, ptr %t511
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.501
reuse.join.501:
  %t512 = phi ptr [ %t5, %reuse.in_place.499 ], [ %t507, %reuse.copy.500 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t495)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t512, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.55.513:
  %t514 = getelementptr ptr, ptr %t13, i32 1
  %t515 = load ptr, ptr %t514
  call void @__inc_ref(ptr %t515)
  %t516 = getelementptr i8, ptr %t5, i64 -8
  %t517 = load i32, ptr %t516
  %t518 = icmp eq i32 %t517, 1
  br i1 %t518, label %reuse.in_place.519, label %reuse.copy.520
reuse.in_place.519:
  %t522 = getelementptr ptr, ptr %t5, i32 1
  %t523 = load ptr, ptr %t522
  call void @__free_recursive(ptr %t523)
  %t525 = inttoptr i64 101 to ptr
  %t526 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t525, ptr %t526
  call void @__inc_ref(ptr %t515)
  %t524 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t515, ptr %t524
  br label %reuse.join.521
reuse.copy.520:
  %t527 = call ptr @__alloc(i64 24, i32 2)
  %t528 = inttoptr i64 101 to ptr
  %t529 = getelementptr ptr, ptr %t527, i32 0
  store ptr %t528, ptr %t529
  call void @__inc_ref(ptr %t515)
  %t530 = getelementptr ptr, ptr %t527, i32 1
  store ptr %t515, ptr %t530
  call void @__inc_ref(ptr %t15)
  %t531 = getelementptr ptr, ptr %t527, i32 2
  store ptr %t15, ptr %t531
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.521
reuse.join.521:
  %t532 = phi ptr [ %t5, %reuse.in_place.519 ], [ %t527, %reuse.copy.520 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t515)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t532, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.56.533:
  %t534 = getelementptr ptr, ptr %t13, i32 1
  %t535 = load ptr, ptr %t534
  call void @__inc_ref(ptr %t535)
  %t536 = getelementptr i8, ptr %t5, i64 -8
  %t537 = load i32, ptr %t536
  %t538 = icmp eq i32 %t537, 1
  br i1 %t538, label %reuse.in_place.539, label %reuse.copy.540
reuse.in_place.539:
  %t542 = getelementptr ptr, ptr %t5, i32 1
  %t543 = load ptr, ptr %t542
  call void @__free_recursive(ptr %t543)
  %t545 = inttoptr i64 102 to ptr
  %t546 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t545, ptr %t546
  call void @__inc_ref(ptr %t535)
  %t544 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t535, ptr %t544
  br label %reuse.join.541
reuse.copy.540:
  %t547 = call ptr @__alloc(i64 24, i32 2)
  %t548 = inttoptr i64 102 to ptr
  %t549 = getelementptr ptr, ptr %t547, i32 0
  store ptr %t548, ptr %t549
  call void @__inc_ref(ptr %t535)
  %t550 = getelementptr ptr, ptr %t547, i32 1
  store ptr %t535, ptr %t550
  call void @__inc_ref(ptr %t15)
  %t551 = getelementptr ptr, ptr %t547, i32 2
  store ptr %t15, ptr %t551
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.541
reuse.join.541:
  %t552 = phi ptr [ %t5, %reuse.in_place.539 ], [ %t547, %reuse.copy.540 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t535)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t552, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.57.553:
  %t554 = getelementptr ptr, ptr %t13, i32 1
  %t555 = load ptr, ptr %t554
  call void @__inc_ref(ptr %t555)
  %t556 = getelementptr i8, ptr %t5, i64 -8
  %t557 = load i32, ptr %t556
  %t558 = icmp eq i32 %t557, 1
  br i1 %t558, label %reuse.in_place.559, label %reuse.copy.560
reuse.in_place.559:
  %t562 = getelementptr ptr, ptr %t5, i32 1
  %t563 = load ptr, ptr %t562
  call void @__free_recursive(ptr %t563)
  %t565 = inttoptr i64 103 to ptr
  %t566 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t565, ptr %t566
  call void @__inc_ref(ptr %t555)
  %t564 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t555, ptr %t564
  br label %reuse.join.561
reuse.copy.560:
  %t567 = call ptr @__alloc(i64 24, i32 2)
  %t568 = inttoptr i64 103 to ptr
  %t569 = getelementptr ptr, ptr %t567, i32 0
  store ptr %t568, ptr %t569
  call void @__inc_ref(ptr %t555)
  %t570 = getelementptr ptr, ptr %t567, i32 1
  store ptr %t555, ptr %t570
  call void @__inc_ref(ptr %t15)
  %t571 = getelementptr ptr, ptr %t567, i32 2
  store ptr %t15, ptr %t571
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.561
reuse.join.561:
  %t572 = phi ptr [ %t5, %reuse.in_place.559 ], [ %t567, %reuse.copy.560 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t555)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t572, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.58.573:
  %t574 = getelementptr ptr, ptr %t13, i32 1
  %t575 = load ptr, ptr %t574
  call void @__inc_ref(ptr %t575)
  %t576 = getelementptr i8, ptr %t5, i64 -8
  %t577 = load i32, ptr %t576
  %t578 = icmp eq i32 %t577, 1
  br i1 %t578, label %reuse.in_place.579, label %reuse.copy.580
reuse.in_place.579:
  %t582 = getelementptr ptr, ptr %t5, i32 1
  %t583 = load ptr, ptr %t582
  call void @__free_recursive(ptr %t583)
  %t585 = inttoptr i64 104 to ptr
  %t586 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t585, ptr %t586
  call void @__inc_ref(ptr %t575)
  %t584 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t575, ptr %t584
  br label %reuse.join.581
reuse.copy.580:
  %t587 = call ptr @__alloc(i64 24, i32 2)
  %t588 = inttoptr i64 104 to ptr
  %t589 = getelementptr ptr, ptr %t587, i32 0
  store ptr %t588, ptr %t589
  call void @__inc_ref(ptr %t575)
  %t590 = getelementptr ptr, ptr %t587, i32 1
  store ptr %t575, ptr %t590
  call void @__inc_ref(ptr %t15)
  %t591 = getelementptr ptr, ptr %t587, i32 2
  store ptr %t15, ptr %t591
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.581
reuse.join.581:
  %t592 = phi ptr [ %t5, %reuse.in_place.579 ], [ %t587, %reuse.copy.580 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t575)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t592, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.59.593:
  %t594 = getelementptr ptr, ptr %t13, i32 1
  %t595 = load ptr, ptr %t594
  call void @__inc_ref(ptr %t595)
  %t596 = getelementptr i8, ptr %t5, i64 -8
  %t597 = load i32, ptr %t596
  %t598 = icmp eq i32 %t597, 1
  br i1 %t598, label %reuse.in_place.599, label %reuse.copy.600
reuse.in_place.599:
  %t602 = getelementptr ptr, ptr %t5, i32 1
  %t603 = load ptr, ptr %t602
  call void @__free_recursive(ptr %t603)
  %t605 = inttoptr i64 105 to ptr
  %t606 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t605, ptr %t606
  call void @__inc_ref(ptr %t595)
  %t604 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t595, ptr %t604
  br label %reuse.join.601
reuse.copy.600:
  %t607 = call ptr @__alloc(i64 24, i32 2)
  %t608 = inttoptr i64 105 to ptr
  %t609 = getelementptr ptr, ptr %t607, i32 0
  store ptr %t608, ptr %t609
  call void @__inc_ref(ptr %t595)
  %t610 = getelementptr ptr, ptr %t607, i32 1
  store ptr %t595, ptr %t610
  call void @__inc_ref(ptr %t15)
  %t611 = getelementptr ptr, ptr %t607, i32 2
  store ptr %t15, ptr %t611
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.601
reuse.join.601:
  %t612 = phi ptr [ %t5, %reuse.in_place.599 ], [ %t607, %reuse.copy.600 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t595)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t612, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.60.613:
  %t614 = getelementptr ptr, ptr %t13, i32 1
  %t615 = load ptr, ptr %t614
  call void @__inc_ref(ptr %t615)
  %t616 = getelementptr i8, ptr %t5, i64 -8
  %t617 = load i32, ptr %t616
  %t618 = icmp eq i32 %t617, 1
  br i1 %t618, label %reuse.in_place.619, label %reuse.copy.620
reuse.in_place.619:
  %t622 = getelementptr ptr, ptr %t5, i32 1
  %t623 = load ptr, ptr %t622
  call void @__free_recursive(ptr %t623)
  %t625 = inttoptr i64 106 to ptr
  %t626 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t625, ptr %t626
  call void @__inc_ref(ptr %t615)
  %t624 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t615, ptr %t624
  br label %reuse.join.621
reuse.copy.620:
  %t627 = call ptr @__alloc(i64 24, i32 2)
  %t628 = inttoptr i64 106 to ptr
  %t629 = getelementptr ptr, ptr %t627, i32 0
  store ptr %t628, ptr %t629
  call void @__inc_ref(ptr %t615)
  %t630 = getelementptr ptr, ptr %t627, i32 1
  store ptr %t615, ptr %t630
  call void @__inc_ref(ptr %t15)
  %t631 = getelementptr ptr, ptr %t627, i32 2
  store ptr %t15, ptr %t631
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.621
reuse.join.621:
  %t632 = phi ptr [ %t5, %reuse.in_place.619 ], [ %t627, %reuse.copy.620 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t615)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t632, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.61.633:
  %t634 = getelementptr ptr, ptr %t13, i32 1
  %t635 = load ptr, ptr %t634
  call void @__inc_ref(ptr %t635)
  %t636 = getelementptr i8, ptr %t5, i64 -8
  %t637 = load i32, ptr %t636
  %t638 = icmp eq i32 %t637, 1
  br i1 %t638, label %reuse.in_place.639, label %reuse.copy.640
reuse.in_place.639:
  %t642 = getelementptr ptr, ptr %t5, i32 1
  %t643 = load ptr, ptr %t642
  call void @__free_recursive(ptr %t643)
  %t645 = inttoptr i64 107 to ptr
  %t646 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t645, ptr %t646
  call void @__inc_ref(ptr %t635)
  %t644 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t635, ptr %t644
  br label %reuse.join.641
reuse.copy.640:
  %t647 = call ptr @__alloc(i64 24, i32 2)
  %t648 = inttoptr i64 107 to ptr
  %t649 = getelementptr ptr, ptr %t647, i32 0
  store ptr %t648, ptr %t649
  call void @__inc_ref(ptr %t635)
  %t650 = getelementptr ptr, ptr %t647, i32 1
  store ptr %t635, ptr %t650
  call void @__inc_ref(ptr %t15)
  %t651 = getelementptr ptr, ptr %t647, i32 2
  store ptr %t15, ptr %t651
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.641
reuse.join.641:
  %t652 = phi ptr [ %t5, %reuse.in_place.639 ], [ %t647, %reuse.copy.640 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t635)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t652, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.62.653:
  %t654 = getelementptr ptr, ptr %t13, i32 1
  %t655 = load ptr, ptr %t654
  call void @__inc_ref(ptr %t655)
  %t656 = getelementptr i8, ptr %t5, i64 -8
  %t657 = load i32, ptr %t656
  %t658 = icmp eq i32 %t657, 1
  br i1 %t658, label %reuse.in_place.659, label %reuse.copy.660
reuse.in_place.659:
  %t662 = getelementptr ptr, ptr %t5, i32 1
  %t663 = load ptr, ptr %t662
  call void @__free_recursive(ptr %t663)
  %t665 = inttoptr i64 108 to ptr
  %t666 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t665, ptr %t666
  call void @__inc_ref(ptr %t655)
  %t664 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t655, ptr %t664
  br label %reuse.join.661
reuse.copy.660:
  %t667 = call ptr @__alloc(i64 24, i32 2)
  %t668 = inttoptr i64 108 to ptr
  %t669 = getelementptr ptr, ptr %t667, i32 0
  store ptr %t668, ptr %t669
  call void @__inc_ref(ptr %t655)
  %t670 = getelementptr ptr, ptr %t667, i32 1
  store ptr %t655, ptr %t670
  call void @__inc_ref(ptr %t15)
  %t671 = getelementptr ptr, ptr %t667, i32 2
  store ptr %t15, ptr %t671
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.661
reuse.join.661:
  %t672 = phi ptr [ %t5, %reuse.in_place.659 ], [ %t667, %reuse.copy.660 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t655)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t672, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.63.673:
  %t674 = getelementptr ptr, ptr %t13, i32 1
  %t675 = load ptr, ptr %t674
  call void @__inc_ref(ptr %t675)
  %t676 = getelementptr i8, ptr %t5, i64 -8
  %t677 = load i32, ptr %t676
  %t678 = icmp eq i32 %t677, 1
  br i1 %t678, label %reuse.in_place.679, label %reuse.copy.680
reuse.in_place.679:
  %t682 = getelementptr ptr, ptr %t5, i32 1
  %t683 = load ptr, ptr %t682
  call void @__free_recursive(ptr %t683)
  %t685 = inttoptr i64 109 to ptr
  %t686 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t685, ptr %t686
  call void @__inc_ref(ptr %t675)
  %t684 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t675, ptr %t684
  br label %reuse.join.681
reuse.copy.680:
  %t687 = call ptr @__alloc(i64 24, i32 2)
  %t688 = inttoptr i64 109 to ptr
  %t689 = getelementptr ptr, ptr %t687, i32 0
  store ptr %t688, ptr %t689
  call void @__inc_ref(ptr %t675)
  %t690 = getelementptr ptr, ptr %t687, i32 1
  store ptr %t675, ptr %t690
  call void @__inc_ref(ptr %t15)
  %t691 = getelementptr ptr, ptr %t687, i32 2
  store ptr %t15, ptr %t691
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.681
reuse.join.681:
  %t692 = phi ptr [ %t5, %reuse.in_place.679 ], [ %t687, %reuse.copy.680 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t675)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t692, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.64.693:
  %t694 = getelementptr ptr, ptr %t13, i32 1
  %t695 = load ptr, ptr %t694
  call void @__inc_ref(ptr %t695)
  %t696 = getelementptr i8, ptr %t5, i64 -8
  %t697 = load i32, ptr %t696
  %t698 = icmp eq i32 %t697, 1
  br i1 %t698, label %reuse.in_place.699, label %reuse.copy.700
reuse.in_place.699:
  %t702 = getelementptr ptr, ptr %t5, i32 1
  %t703 = load ptr, ptr %t702
  call void @__free_recursive(ptr %t703)
  %t705 = inttoptr i64 110 to ptr
  %t706 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t705, ptr %t706
  call void @__inc_ref(ptr %t695)
  %t704 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t695, ptr %t704
  br label %reuse.join.701
reuse.copy.700:
  %t707 = call ptr @__alloc(i64 24, i32 2)
  %t708 = inttoptr i64 110 to ptr
  %t709 = getelementptr ptr, ptr %t707, i32 0
  store ptr %t708, ptr %t709
  call void @__inc_ref(ptr %t695)
  %t710 = getelementptr ptr, ptr %t707, i32 1
  store ptr %t695, ptr %t710
  call void @__inc_ref(ptr %t15)
  %t711 = getelementptr ptr, ptr %t707, i32 2
  store ptr %t15, ptr %t711
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.701
reuse.join.701:
  %t712 = phi ptr [ %t5, %reuse.in_place.699 ], [ %t707, %reuse.copy.700 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t695)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t712, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.65.713:
  %t714 = getelementptr ptr, ptr %t13, i32 1
  %t715 = load ptr, ptr %t714
  call void @__inc_ref(ptr %t715)
  %t716 = getelementptr i8, ptr %t5, i64 -8
  %t717 = load i32, ptr %t716
  %t718 = icmp eq i32 %t717, 1
  br i1 %t718, label %reuse.in_place.719, label %reuse.copy.720
reuse.in_place.719:
  %t722 = getelementptr ptr, ptr %t5, i32 1
  %t723 = load ptr, ptr %t722
  call void @__free_recursive(ptr %t723)
  %t725 = inttoptr i64 111 to ptr
  %t726 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t725, ptr %t726
  call void @__inc_ref(ptr %t715)
  %t724 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t715, ptr %t724
  br label %reuse.join.721
reuse.copy.720:
  %t727 = call ptr @__alloc(i64 24, i32 2)
  %t728 = inttoptr i64 111 to ptr
  %t729 = getelementptr ptr, ptr %t727, i32 0
  store ptr %t728, ptr %t729
  call void @__inc_ref(ptr %t715)
  %t730 = getelementptr ptr, ptr %t727, i32 1
  store ptr %t715, ptr %t730
  call void @__inc_ref(ptr %t15)
  %t731 = getelementptr ptr, ptr %t727, i32 2
  store ptr %t15, ptr %t731
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.721
reuse.join.721:
  %t732 = phi ptr [ %t5, %reuse.in_place.719 ], [ %t727, %reuse.copy.720 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t715)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t732, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.66.733:
  %t734 = getelementptr ptr, ptr %t13, i32 1
  %t735 = load ptr, ptr %t734
  call void @__inc_ref(ptr %t735)
  %t736 = getelementptr i8, ptr %t5, i64 -8
  %t737 = load i32, ptr %t736
  %t738 = icmp eq i32 %t737, 1
  br i1 %t738, label %reuse.in_place.739, label %reuse.copy.740
reuse.in_place.739:
  %t742 = getelementptr ptr, ptr %t5, i32 1
  %t743 = load ptr, ptr %t742
  call void @__free_recursive(ptr %t743)
  %t745 = inttoptr i64 112 to ptr
  %t746 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t745, ptr %t746
  call void @__inc_ref(ptr %t735)
  %t744 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t735, ptr %t744
  br label %reuse.join.741
reuse.copy.740:
  %t747 = call ptr @__alloc(i64 24, i32 2)
  %t748 = inttoptr i64 112 to ptr
  %t749 = getelementptr ptr, ptr %t747, i32 0
  store ptr %t748, ptr %t749
  call void @__inc_ref(ptr %t735)
  %t750 = getelementptr ptr, ptr %t747, i32 1
  store ptr %t735, ptr %t750
  call void @__inc_ref(ptr %t15)
  %t751 = getelementptr ptr, ptr %t747, i32 2
  store ptr %t15, ptr %t751
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.741
reuse.join.741:
  %t752 = phi ptr [ %t5, %reuse.in_place.739 ], [ %t747, %reuse.copy.740 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t735)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t752, ptr %t3
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
  %t765 = inttoptr i64 113 to ptr
  %t766 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t765, ptr %t766
  call void @__inc_ref(ptr %t755)
  %t764 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t755, ptr %t764
  br label %reuse.join.761
reuse.copy.760:
  %t767 = call ptr @__alloc(i64 24, i32 2)
  %t768 = inttoptr i64 113 to ptr
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
  %t785 = inttoptr i64 114 to ptr
  %t786 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t785, ptr %t786
  call void @__inc_ref(ptr %t775)
  %t784 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t775, ptr %t784
  br label %reuse.join.781
reuse.copy.780:
  %t787 = call ptr @__alloc(i64 24, i32 2)
  %t788 = inttoptr i64 114 to ptr
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
  %t805 = inttoptr i64 115 to ptr
  %t806 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t805, ptr %t806
  call void @__inc_ref(ptr %t795)
  %t804 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t795, ptr %t804
  br label %reuse.join.801
reuse.copy.800:
  %t807 = call ptr @__alloc(i64 24, i32 2)
  %t808 = inttoptr i64 115 to ptr
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
  %t825 = inttoptr i64 116 to ptr
  %t826 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t825, ptr %t826
  call void @__inc_ref(ptr %t815)
  %t824 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t815, ptr %t824
  br label %reuse.join.821
reuse.copy.820:
  %t827 = call ptr @__alloc(i64 24, i32 2)
  %t828 = inttoptr i64 116 to ptr
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
  %t845 = inttoptr i64 117 to ptr
  %t846 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t845, ptr %t846
  call void @__inc_ref(ptr %t835)
  %t844 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t835, ptr %t844
  br label %reuse.join.841
reuse.copy.840:
  %t847 = call ptr @__alloc(i64 24, i32 2)
  %t848 = inttoptr i64 117 to ptr
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
  %t865 = inttoptr i64 118 to ptr
  %t866 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t865, ptr %t866
  call void @__inc_ref(ptr %t855)
  %t864 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t855, ptr %t864
  br label %reuse.join.861
reuse.copy.860:
  %t867 = call ptr @__alloc(i64 24, i32 2)
  %t868 = inttoptr i64 118 to ptr
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
  %t885 = inttoptr i64 119 to ptr
  %t886 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t885, ptr %t886
  call void @__inc_ref(ptr %t875)
  %t884 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t875, ptr %t884
  br label %reuse.join.881
reuse.copy.880:
  %t887 = call ptr @__alloc(i64 24, i32 2)
  %t888 = inttoptr i64 119 to ptr
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
tco.case.default.19:
  unreachable
tco.case.arm.75.893:
  %t894 = getelementptr ptr, ptr %t5, i32 1
  %t895 = load ptr, ptr %t894
  %t896 = getelementptr ptr, ptr %t5, i32 2
  %t897 = load ptr, ptr %t896
  %t898 = getelementptr i8, ptr %t5, i64 -8
  %t899 = load i32, ptr %t898
  %t900 = icmp eq i32 %t899, 1
  br i1 %t900, label %reuse.in_place.901, label %reuse.copy.902
reuse.in_place.901:
  %t904 = inttoptr i64 74 to ptr
  %t905 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t904, ptr %t905
  br label %reuse.join.903
reuse.copy.902:
  %t906 = call ptr @__alloc(i64 24, i32 2)
  %t907 = inttoptr i64 74 to ptr
  %t908 = getelementptr ptr, ptr %t906, i32 0
  store ptr %t907, ptr %t908
  call void @__inc_ref(ptr %t895)
  %t909 = getelementptr ptr, ptr %t906, i32 1
  store ptr %t895, ptr %t909
  call void @__inc_ref(ptr %t897)
  %t910 = getelementptr ptr, ptr %t906, i32 2
  store ptr %t897, ptr %t910
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.903
reuse.join.903:
  %t911 = phi ptr [ %t5, %reuse.in_place.901 ], [ %t906, %reuse.copy.902 ]
  %t912 = call ptr @__alloc(i64 16, i32 1)
  %t913 = inttoptr i64 151 to ptr
  %t914 = getelementptr ptr, ptr %t912, i32 0
  store ptr %t913, ptr %t914
  call void @__inc_ref(ptr %t6)
  %t915 = getelementptr ptr, ptr %t912, i32 1
  store ptr %t6, ptr %t915
  call void @__free_recursive(ptr %t6)
  store ptr %t911, ptr %t3
  store ptr %t912, ptr %t4
  br label %tco.loop.0
tco.case.arm.76.916:
  %t917 = getelementptr ptr, ptr %t5, i32 1
  %t918 = load ptr, ptr %t917
  call void @__inc_ref(ptr %t918)
  %t919 = getelementptr ptr, ptr %t5, i32 2
  %t920 = load ptr, ptr %t919
  call void @__inc_ref(ptr %t920)
  %t921 = getelementptr ptr, ptr %t5, i32 3
  %t922 = load ptr, ptr %t921
  call void @__inc_ref(ptr %t922)
  %t923 = call ptr @__alloc(i64 24, i32 2)
  %t924 = inttoptr i64 74 to ptr
  %t925 = getelementptr ptr, ptr %t923, i32 0
  store ptr %t924, ptr %t925
  call void @__inc_ref(ptr %t918)
  %t926 = getelementptr ptr, ptr %t923, i32 1
  store ptr %t918, ptr %t926
  call void @__inc_ref(ptr %t920)
  %t927 = getelementptr ptr, ptr %t923, i32 2
  store ptr %t920, ptr %t927
  %t928 = call ptr @__alloc(i64 24, i32 2)
  %t929 = inttoptr i64 152 to ptr
  %t930 = getelementptr ptr, ptr %t928, i32 0
  store ptr %t929, ptr %t930
  call void @__inc_ref(ptr %t6)
  %t931 = getelementptr ptr, ptr %t928, i32 1
  store ptr %t6, ptr %t931
  call void @__inc_ref(ptr %t922)
  %t932 = getelementptr ptr, ptr %t928, i32 2
  store ptr %t922, ptr %t932
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t922)
  call void @__free_recursive(ptr %t920)
  call void @__free_recursive(ptr %t918)
  store ptr %t923, ptr %t3
  store ptr %t928, ptr %t4
  br label %tco.loop.0
tco.case.arm.77.933:
  %t934 = getelementptr ptr, ptr %t5, i32 1
  %t935 = load ptr, ptr %t934
  %t936 = getelementptr ptr, ptr %t5, i32 2
  %t937 = load ptr, ptr %t936
  %t938 = getelementptr i8, ptr %t5, i64 -8
  %t939 = load i32, ptr %t938
  %t940 = icmp eq i32 %t939, 1
  br i1 %t940, label %reuse.in_place.941, label %reuse.copy.942
reuse.in_place.941:
  %t944 = inttoptr i64 74 to ptr
  %t945 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t944, ptr %t945
  br label %reuse.join.943
reuse.copy.942:
  %t946 = call ptr @__alloc(i64 24, i32 2)
  %t947 = inttoptr i64 74 to ptr
  %t948 = getelementptr ptr, ptr %t946, i32 0
  store ptr %t947, ptr %t948
  call void @__inc_ref(ptr %t935)
  %t949 = getelementptr ptr, ptr %t946, i32 1
  store ptr %t935, ptr %t949
  call void @__inc_ref(ptr %t937)
  %t950 = getelementptr ptr, ptr %t946, i32 2
  store ptr %t937, ptr %t950
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.943
reuse.join.943:
  %t951 = phi ptr [ %t5, %reuse.in_place.941 ], [ %t946, %reuse.copy.942 ]
  %t952 = call ptr @__alloc(i64 16, i32 1)
  %t953 = inttoptr i64 153 to ptr
  %t954 = getelementptr ptr, ptr %t952, i32 0
  store ptr %t953, ptr %t954
  call void @__inc_ref(ptr %t6)
  %t955 = getelementptr ptr, ptr %t952, i32 1
  store ptr %t6, ptr %t955
  call void @__free_recursive(ptr %t6)
  store ptr %t951, ptr %t3
  store ptr %t952, ptr %t4
  br label %tco.loop.0
tco.case.arm.78.956:
  %t957 = getelementptr ptr, ptr %t5, i32 1
  %t958 = load ptr, ptr %t957
  %t959 = getelementptr ptr, ptr %t5, i32 2
  %t960 = load ptr, ptr %t959
  %t961 = getelementptr i8, ptr %t5, i64 -8
  %t962 = load i32, ptr %t961
  %t963 = icmp eq i32 %t962, 1
  br i1 %t963, label %reuse.in_place.964, label %reuse.copy.965
reuse.in_place.964:
  %t967 = inttoptr i64 74 to ptr
  %t968 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t967, ptr %t968
  br label %reuse.join.966
reuse.copy.965:
  %t969 = call ptr @__alloc(i64 24, i32 2)
  %t970 = inttoptr i64 74 to ptr
  %t971 = getelementptr ptr, ptr %t969, i32 0
  store ptr %t970, ptr %t971
  call void @__inc_ref(ptr %t958)
  %t972 = getelementptr ptr, ptr %t969, i32 1
  store ptr %t958, ptr %t972
  call void @__inc_ref(ptr %t960)
  %t973 = getelementptr ptr, ptr %t969, i32 2
  store ptr %t960, ptr %t973
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.966
reuse.join.966:
  %t974 = phi ptr [ %t5, %reuse.in_place.964 ], [ %t969, %reuse.copy.965 ]
  %t975 = call ptr @__alloc(i64 16, i32 1)
  %t976 = inttoptr i64 154 to ptr
  %t977 = getelementptr ptr, ptr %t975, i32 0
  store ptr %t976, ptr %t977
  call void @__inc_ref(ptr %t6)
  %t978 = getelementptr ptr, ptr %t975, i32 1
  store ptr %t6, ptr %t978
  call void @__free_recursive(ptr %t6)
  store ptr %t974, ptr %t3
  store ptr %t975, ptr %t4
  br label %tco.loop.0
tco.case.arm.79.979:
  %t980 = getelementptr ptr, ptr %t5, i32 1
  %t981 = load ptr, ptr %t980
  %t982 = getelementptr ptr, ptr %t5, i32 2
  %t983 = load ptr, ptr %t982
  %t984 = getelementptr i8, ptr %t5, i64 -8
  %t985 = load i32, ptr %t984
  %t986 = icmp eq i32 %t985, 1
  br i1 %t986, label %reuse.in_place.987, label %reuse.copy.988
reuse.in_place.987:
  %t990 = inttoptr i64 74 to ptr
  %t991 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t990, ptr %t991
  br label %reuse.join.989
reuse.copy.988:
  %t992 = call ptr @__alloc(i64 24, i32 2)
  %t993 = inttoptr i64 74 to ptr
  %t994 = getelementptr ptr, ptr %t992, i32 0
  store ptr %t993, ptr %t994
  call void @__inc_ref(ptr %t981)
  %t995 = getelementptr ptr, ptr %t992, i32 1
  store ptr %t981, ptr %t995
  call void @__inc_ref(ptr %t983)
  %t996 = getelementptr ptr, ptr %t992, i32 2
  store ptr %t983, ptr %t996
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.989
reuse.join.989:
  %t997 = phi ptr [ %t5, %reuse.in_place.987 ], [ %t992, %reuse.copy.988 ]
  %t998 = call ptr @__alloc(i64 16, i32 1)
  %t999 = inttoptr i64 155 to ptr
  %t1000 = getelementptr ptr, ptr %t998, i32 0
  store ptr %t999, ptr %t1000
  call void @__inc_ref(ptr %t6)
  %t1001 = getelementptr ptr, ptr %t998, i32 1
  store ptr %t6, ptr %t1001
  call void @__free_recursive(ptr %t6)
  store ptr %t997, ptr %t3
  store ptr %t998, ptr %t4
  br label %tco.loop.0
tco.case.arm.80.1002:
  %t1003 = getelementptr ptr, ptr %t5, i32 1
  %t1004 = load ptr, ptr %t1003
  %t1005 = getelementptr ptr, ptr %t5, i32 2
  %t1006 = load ptr, ptr %t1005
  %t1007 = getelementptr i8, ptr %t5, i64 -8
  %t1008 = load i32, ptr %t1007
  %t1009 = icmp eq i32 %t1008, 1
  br i1 %t1009, label %reuse.in_place.1010, label %reuse.copy.1011
reuse.in_place.1010:
  %t1013 = inttoptr i64 74 to ptr
  %t1014 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1013, ptr %t1014
  br label %reuse.join.1012
reuse.copy.1011:
  %t1015 = call ptr @__alloc(i64 24, i32 2)
  %t1016 = inttoptr i64 74 to ptr
  %t1017 = getelementptr ptr, ptr %t1015, i32 0
  store ptr %t1016, ptr %t1017
  call void @__inc_ref(ptr %t1004)
  %t1018 = getelementptr ptr, ptr %t1015, i32 1
  store ptr %t1004, ptr %t1018
  call void @__inc_ref(ptr %t1006)
  %t1019 = getelementptr ptr, ptr %t1015, i32 2
  store ptr %t1006, ptr %t1019
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1012
reuse.join.1012:
  %t1020 = phi ptr [ %t5, %reuse.in_place.1010 ], [ %t1015, %reuse.copy.1011 ]
  %t1021 = call ptr @__alloc(i64 16, i32 1)
  %t1022 = inttoptr i64 156 to ptr
  %t1023 = getelementptr ptr, ptr %t1021, i32 0
  store ptr %t1022, ptr %t1023
  call void @__inc_ref(ptr %t6)
  %t1024 = getelementptr ptr, ptr %t1021, i32 1
  store ptr %t6, ptr %t1024
  call void @__free_recursive(ptr %t6)
  store ptr %t1020, ptr %t3
  store ptr %t1021, ptr %t4
  br label %tco.loop.0
tco.case.arm.81.1025:
  %t1026 = getelementptr ptr, ptr %t5, i32 1
  %t1027 = load ptr, ptr %t1026
  %t1028 = getelementptr ptr, ptr %t5, i32 2
  %t1029 = load ptr, ptr %t1028
  %t1030 = getelementptr i8, ptr %t5, i64 -8
  %t1031 = load i32, ptr %t1030
  %t1032 = icmp eq i32 %t1031, 1
  br i1 %t1032, label %reuse.in_place.1033, label %reuse.copy.1034
reuse.in_place.1033:
  %t1036 = inttoptr i64 74 to ptr
  %t1037 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1036, ptr %t1037
  br label %reuse.join.1035
reuse.copy.1034:
  %t1038 = call ptr @__alloc(i64 24, i32 2)
  %t1039 = inttoptr i64 74 to ptr
  %t1040 = getelementptr ptr, ptr %t1038, i32 0
  store ptr %t1039, ptr %t1040
  call void @__inc_ref(ptr %t1027)
  %t1041 = getelementptr ptr, ptr %t1038, i32 1
  store ptr %t1027, ptr %t1041
  call void @__inc_ref(ptr %t1029)
  %t1042 = getelementptr ptr, ptr %t1038, i32 2
  store ptr %t1029, ptr %t1042
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1035
reuse.join.1035:
  %t1043 = phi ptr [ %t5, %reuse.in_place.1033 ], [ %t1038, %reuse.copy.1034 ]
  %t1044 = call ptr @__alloc(i64 16, i32 1)
  %t1045 = inttoptr i64 157 to ptr
  %t1046 = getelementptr ptr, ptr %t1044, i32 0
  store ptr %t1045, ptr %t1046
  call void @__inc_ref(ptr %t6)
  %t1047 = getelementptr ptr, ptr %t1044, i32 1
  store ptr %t6, ptr %t1047
  call void @__free_recursive(ptr %t6)
  store ptr %t1043, ptr %t3
  store ptr %t1044, ptr %t4
  br label %tco.loop.0
tco.case.arm.82.1048:
  %t1049 = getelementptr ptr, ptr %t5, i32 1
  %t1050 = load ptr, ptr %t1049
  %t1051 = getelementptr ptr, ptr %t5, i32 2
  %t1052 = load ptr, ptr %t1051
  %t1053 = getelementptr i8, ptr %t5, i64 -8
  %t1054 = load i32, ptr %t1053
  %t1055 = icmp eq i32 %t1054, 1
  br i1 %t1055, label %reuse.in_place.1056, label %reuse.copy.1057
reuse.in_place.1056:
  %t1059 = inttoptr i64 74 to ptr
  %t1060 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1059, ptr %t1060
  br label %reuse.join.1058
reuse.copy.1057:
  %t1061 = call ptr @__alloc(i64 24, i32 2)
  %t1062 = inttoptr i64 74 to ptr
  %t1063 = getelementptr ptr, ptr %t1061, i32 0
  store ptr %t1062, ptr %t1063
  call void @__inc_ref(ptr %t1050)
  %t1064 = getelementptr ptr, ptr %t1061, i32 1
  store ptr %t1050, ptr %t1064
  call void @__inc_ref(ptr %t1052)
  %t1065 = getelementptr ptr, ptr %t1061, i32 2
  store ptr %t1052, ptr %t1065
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1058
reuse.join.1058:
  %t1066 = phi ptr [ %t5, %reuse.in_place.1056 ], [ %t1061, %reuse.copy.1057 ]
  %t1067 = call ptr @__alloc(i64 16, i32 1)
  %t1068 = inttoptr i64 158 to ptr
  %t1069 = getelementptr ptr, ptr %t1067, i32 0
  store ptr %t1068, ptr %t1069
  call void @__inc_ref(ptr %t6)
  %t1070 = getelementptr ptr, ptr %t1067, i32 1
  store ptr %t6, ptr %t1070
  call void @__free_recursive(ptr %t6)
  store ptr %t1066, ptr %t3
  store ptr %t1067, ptr %t4
  br label %tco.loop.0
tco.case.arm.83.1071:
  %t1072 = getelementptr ptr, ptr %t5, i32 1
  %t1073 = load ptr, ptr %t1072
  call void @__inc_ref(ptr %t1073)
  %t1074 = getelementptr ptr, ptr %t5, i32 2
  %t1075 = load ptr, ptr %t1074
  call void @__inc_ref(ptr %t1075)
  %t1076 = getelementptr ptr, ptr %t5, i32 3
  %t1077 = load ptr, ptr %t1076
  call void @__inc_ref(ptr %t1077)
  %t1078 = call ptr @__alloc(i64 24, i32 2)
  %t1079 = inttoptr i64 74 to ptr
  %t1080 = getelementptr ptr, ptr %t1078, i32 0
  store ptr %t1079, ptr %t1080
  call void @__inc_ref(ptr %t1073)
  %t1081 = getelementptr ptr, ptr %t1078, i32 1
  store ptr %t1073, ptr %t1081
  call void @__inc_ref(ptr %t1075)
  %t1082 = getelementptr ptr, ptr %t1078, i32 2
  store ptr %t1075, ptr %t1082
  %t1083 = call ptr @__alloc(i64 24, i32 2)
  %t1084 = inttoptr i64 159 to ptr
  %t1085 = getelementptr ptr, ptr %t1083, i32 0
  store ptr %t1084, ptr %t1085
  call void @__inc_ref(ptr %t6)
  %t1086 = getelementptr ptr, ptr %t1083, i32 1
  store ptr %t6, ptr %t1086
  call void @__inc_ref(ptr %t1077)
  %t1087 = getelementptr ptr, ptr %t1083, i32 2
  store ptr %t1077, ptr %t1087
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t1077)
  call void @__free_recursive(ptr %t1075)
  call void @__free_recursive(ptr %t1073)
  store ptr %t1078, ptr %t3
  store ptr %t1083, ptr %t4
  br label %tco.loop.0
tco.case.arm.84.1088:
  %t1089 = getelementptr ptr, ptr %t5, i32 1
  %t1090 = load ptr, ptr %t1089
  %t1091 = getelementptr ptr, ptr %t5, i32 2
  %t1092 = load ptr, ptr %t1091
  %t1093 = getelementptr i8, ptr %t5, i64 -8
  %t1094 = load i32, ptr %t1093
  %t1095 = icmp eq i32 %t1094, 1
  br i1 %t1095, label %reuse.in_place.1096, label %reuse.copy.1097
reuse.in_place.1096:
  %t1099 = inttoptr i64 74 to ptr
  %t1100 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1099, ptr %t1100
  br label %reuse.join.1098
reuse.copy.1097:
  %t1101 = call ptr @__alloc(i64 24, i32 2)
  %t1102 = inttoptr i64 74 to ptr
  %t1103 = getelementptr ptr, ptr %t1101, i32 0
  store ptr %t1102, ptr %t1103
  call void @__inc_ref(ptr %t1090)
  %t1104 = getelementptr ptr, ptr %t1101, i32 1
  store ptr %t1090, ptr %t1104
  call void @__inc_ref(ptr %t1092)
  %t1105 = getelementptr ptr, ptr %t1101, i32 2
  store ptr %t1092, ptr %t1105
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1098
reuse.join.1098:
  %t1106 = phi ptr [ %t5, %reuse.in_place.1096 ], [ %t1101, %reuse.copy.1097 ]
  %t1107 = call ptr @__alloc(i64 16, i32 1)
  %t1108 = inttoptr i64 160 to ptr
  %t1109 = getelementptr ptr, ptr %t1107, i32 0
  store ptr %t1108, ptr %t1109
  call void @__inc_ref(ptr %t6)
  %t1110 = getelementptr ptr, ptr %t1107, i32 1
  store ptr %t6, ptr %t1110
  call void @__free_recursive(ptr %t6)
  store ptr %t1106, ptr %t3
  store ptr %t1107, ptr %t4
  br label %tco.loop.0
tco.case.arm.85.1111:
  %t1112 = getelementptr ptr, ptr %t5, i32 1
  %t1113 = load ptr, ptr %t1112
  %t1114 = getelementptr ptr, ptr %t5, i32 2
  %t1115 = load ptr, ptr %t1114
  %t1116 = getelementptr i8, ptr %t5, i64 -8
  %t1117 = load i32, ptr %t1116
  %t1118 = icmp eq i32 %t1117, 1
  br i1 %t1118, label %reuse.in_place.1119, label %reuse.copy.1120
reuse.in_place.1119:
  %t1122 = inttoptr i64 74 to ptr
  %t1123 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1122, ptr %t1123
  br label %reuse.join.1121
reuse.copy.1120:
  %t1124 = call ptr @__alloc(i64 24, i32 2)
  %t1125 = inttoptr i64 74 to ptr
  %t1126 = getelementptr ptr, ptr %t1124, i32 0
  store ptr %t1125, ptr %t1126
  call void @__inc_ref(ptr %t1113)
  %t1127 = getelementptr ptr, ptr %t1124, i32 1
  store ptr %t1113, ptr %t1127
  call void @__inc_ref(ptr %t1115)
  %t1128 = getelementptr ptr, ptr %t1124, i32 2
  store ptr %t1115, ptr %t1128
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1121
reuse.join.1121:
  %t1129 = phi ptr [ %t5, %reuse.in_place.1119 ], [ %t1124, %reuse.copy.1120 ]
  %t1130 = call ptr @__alloc(i64 16, i32 1)
  %t1131 = inttoptr i64 161 to ptr
  %t1132 = getelementptr ptr, ptr %t1130, i32 0
  store ptr %t1131, ptr %t1132
  call void @__inc_ref(ptr %t6)
  %t1133 = getelementptr ptr, ptr %t1130, i32 1
  store ptr %t6, ptr %t1133
  call void @__free_recursive(ptr %t6)
  store ptr %t1129, ptr %t3
  store ptr %t1130, ptr %t4
  br label %tco.loop.0
tco.case.arm.86.1134:
  %t1135 = getelementptr ptr, ptr %t5, i32 1
  %t1136 = load ptr, ptr %t1135
  %t1137 = getelementptr ptr, ptr %t5, i32 2
  %t1138 = load ptr, ptr %t1137
  %t1139 = getelementptr i8, ptr %t5, i64 -8
  %t1140 = load i32, ptr %t1139
  %t1141 = icmp eq i32 %t1140, 1
  br i1 %t1141, label %reuse.in_place.1142, label %reuse.copy.1143
reuse.in_place.1142:
  %t1145 = inttoptr i64 74 to ptr
  %t1146 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1145, ptr %t1146
  br label %reuse.join.1144
reuse.copy.1143:
  %t1147 = call ptr @__alloc(i64 24, i32 2)
  %t1148 = inttoptr i64 74 to ptr
  %t1149 = getelementptr ptr, ptr %t1147, i32 0
  store ptr %t1148, ptr %t1149
  call void @__inc_ref(ptr %t1136)
  %t1150 = getelementptr ptr, ptr %t1147, i32 1
  store ptr %t1136, ptr %t1150
  call void @__inc_ref(ptr %t1138)
  %t1151 = getelementptr ptr, ptr %t1147, i32 2
  store ptr %t1138, ptr %t1151
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1144
reuse.join.1144:
  %t1152 = phi ptr [ %t5, %reuse.in_place.1142 ], [ %t1147, %reuse.copy.1143 ]
  %t1153 = call ptr @__alloc(i64 16, i32 1)
  %t1154 = inttoptr i64 162 to ptr
  %t1155 = getelementptr ptr, ptr %t1153, i32 0
  store ptr %t1154, ptr %t1155
  call void @__inc_ref(ptr %t6)
  %t1156 = getelementptr ptr, ptr %t1153, i32 1
  store ptr %t6, ptr %t1156
  call void @__free_recursive(ptr %t6)
  store ptr %t1152, ptr %t3
  store ptr %t1153, ptr %t4
  br label %tco.loop.0
tco.case.arm.87.1157:
  %t1158 = getelementptr ptr, ptr %t5, i32 1
  %t1159 = load ptr, ptr %t1158
  %t1160 = getelementptr ptr, ptr %t5, i32 2
  %t1161 = load ptr, ptr %t1160
  %t1162 = getelementptr i8, ptr %t5, i64 -8
  %t1163 = load i32, ptr %t1162
  %t1164 = icmp eq i32 %t1163, 1
  br i1 %t1164, label %reuse.in_place.1165, label %reuse.copy.1166
reuse.in_place.1165:
  %t1168 = inttoptr i64 74 to ptr
  %t1169 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1168, ptr %t1169
  br label %reuse.join.1167
reuse.copy.1166:
  %t1170 = call ptr @__alloc(i64 24, i32 2)
  %t1171 = inttoptr i64 74 to ptr
  %t1172 = getelementptr ptr, ptr %t1170, i32 0
  store ptr %t1171, ptr %t1172
  call void @__inc_ref(ptr %t1159)
  %t1173 = getelementptr ptr, ptr %t1170, i32 1
  store ptr %t1159, ptr %t1173
  call void @__inc_ref(ptr %t1161)
  %t1174 = getelementptr ptr, ptr %t1170, i32 2
  store ptr %t1161, ptr %t1174
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1167
reuse.join.1167:
  %t1175 = phi ptr [ %t5, %reuse.in_place.1165 ], [ %t1170, %reuse.copy.1166 ]
  %t1176 = call ptr @__alloc(i64 16, i32 1)
  %t1177 = inttoptr i64 163 to ptr
  %t1178 = getelementptr ptr, ptr %t1176, i32 0
  store ptr %t1177, ptr %t1178
  call void @__inc_ref(ptr %t6)
  %t1179 = getelementptr ptr, ptr %t1176, i32 1
  store ptr %t6, ptr %t1179
  call void @__free_recursive(ptr %t6)
  store ptr %t1175, ptr %t3
  store ptr %t1176, ptr %t4
  br label %tco.loop.0
tco.case.arm.88.1180:
  %t1181 = getelementptr ptr, ptr %t5, i32 1
  %t1182 = load ptr, ptr %t1181
  %t1183 = getelementptr ptr, ptr %t5, i32 2
  %t1184 = load ptr, ptr %t1183
  %t1185 = getelementptr i8, ptr %t5, i64 -8
  %t1186 = load i32, ptr %t1185
  %t1187 = icmp eq i32 %t1186, 1
  br i1 %t1187, label %reuse.in_place.1188, label %reuse.copy.1189
reuse.in_place.1188:
  %t1191 = inttoptr i64 74 to ptr
  %t1192 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1191, ptr %t1192
  br label %reuse.join.1190
reuse.copy.1189:
  %t1193 = call ptr @__alloc(i64 24, i32 2)
  %t1194 = inttoptr i64 74 to ptr
  %t1195 = getelementptr ptr, ptr %t1193, i32 0
  store ptr %t1194, ptr %t1195
  call void @__inc_ref(ptr %t1182)
  %t1196 = getelementptr ptr, ptr %t1193, i32 1
  store ptr %t1182, ptr %t1196
  call void @__inc_ref(ptr %t1184)
  %t1197 = getelementptr ptr, ptr %t1193, i32 2
  store ptr %t1184, ptr %t1197
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1190
reuse.join.1190:
  %t1198 = phi ptr [ %t5, %reuse.in_place.1188 ], [ %t1193, %reuse.copy.1189 ]
  %t1199 = call ptr @__alloc(i64 16, i32 1)
  %t1200 = inttoptr i64 164 to ptr
  %t1201 = getelementptr ptr, ptr %t1199, i32 0
  store ptr %t1200, ptr %t1201
  call void @__inc_ref(ptr %t6)
  %t1202 = getelementptr ptr, ptr %t1199, i32 1
  store ptr %t6, ptr %t1202
  call void @__free_recursive(ptr %t6)
  store ptr %t1198, ptr %t3
  store ptr %t1199, ptr %t4
  br label %tco.loop.0
tco.case.arm.89.1203:
  %t1204 = getelementptr ptr, ptr %t5, i32 1
  %t1205 = load ptr, ptr %t1204
  %t1206 = getelementptr ptr, ptr %t5, i32 2
  %t1207 = load ptr, ptr %t1206
  %t1208 = getelementptr i8, ptr %t5, i64 -8
  %t1209 = load i32, ptr %t1208
  %t1210 = icmp eq i32 %t1209, 1
  br i1 %t1210, label %reuse.in_place.1211, label %reuse.copy.1212
reuse.in_place.1211:
  %t1214 = inttoptr i64 74 to ptr
  %t1215 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1214, ptr %t1215
  br label %reuse.join.1213
reuse.copy.1212:
  %t1216 = call ptr @__alloc(i64 24, i32 2)
  %t1217 = inttoptr i64 74 to ptr
  %t1218 = getelementptr ptr, ptr %t1216, i32 0
  store ptr %t1217, ptr %t1218
  call void @__inc_ref(ptr %t1205)
  %t1219 = getelementptr ptr, ptr %t1216, i32 1
  store ptr %t1205, ptr %t1219
  call void @__inc_ref(ptr %t1207)
  %t1220 = getelementptr ptr, ptr %t1216, i32 2
  store ptr %t1207, ptr %t1220
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1213
reuse.join.1213:
  %t1221 = phi ptr [ %t5, %reuse.in_place.1211 ], [ %t1216, %reuse.copy.1212 ]
  %t1222 = call ptr @__alloc(i64 16, i32 1)
  %t1223 = inttoptr i64 165 to ptr
  %t1224 = getelementptr ptr, ptr %t1222, i32 0
  store ptr %t1223, ptr %t1224
  call void @__inc_ref(ptr %t6)
  %t1225 = getelementptr ptr, ptr %t1222, i32 1
  store ptr %t6, ptr %t1225
  call void @__free_recursive(ptr %t6)
  store ptr %t1221, ptr %t3
  store ptr %t1222, ptr %t4
  br label %tco.loop.0
tco.case.arm.90.1226:
  %t1227 = getelementptr ptr, ptr %t5, i32 1
  %t1228 = load ptr, ptr %t1227
  %t1229 = getelementptr ptr, ptr %t5, i32 2
  %t1230 = load ptr, ptr %t1229
  %t1231 = getelementptr i8, ptr %t5, i64 -8
  %t1232 = load i32, ptr %t1231
  %t1233 = icmp eq i32 %t1232, 1
  br i1 %t1233, label %reuse.in_place.1234, label %reuse.copy.1235
reuse.in_place.1234:
  %t1237 = inttoptr i64 74 to ptr
  %t1238 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1237, ptr %t1238
  br label %reuse.join.1236
reuse.copy.1235:
  %t1239 = call ptr @__alloc(i64 24, i32 2)
  %t1240 = inttoptr i64 74 to ptr
  %t1241 = getelementptr ptr, ptr %t1239, i32 0
  store ptr %t1240, ptr %t1241
  call void @__inc_ref(ptr %t1228)
  %t1242 = getelementptr ptr, ptr %t1239, i32 1
  store ptr %t1228, ptr %t1242
  call void @__inc_ref(ptr %t1230)
  %t1243 = getelementptr ptr, ptr %t1239, i32 2
  store ptr %t1230, ptr %t1243
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1236
reuse.join.1236:
  %t1244 = phi ptr [ %t5, %reuse.in_place.1234 ], [ %t1239, %reuse.copy.1235 ]
  %t1245 = call ptr @__alloc(i64 16, i32 1)
  %t1246 = inttoptr i64 166 to ptr
  %t1247 = getelementptr ptr, ptr %t1245, i32 0
  store ptr %t1246, ptr %t1247
  call void @__inc_ref(ptr %t6)
  %t1248 = getelementptr ptr, ptr %t1245, i32 1
  store ptr %t6, ptr %t1248
  call void @__free_recursive(ptr %t6)
  store ptr %t1244, ptr %t3
  store ptr %t1245, ptr %t4
  br label %tco.loop.0
tco.case.arm.91.1249:
  %t1250 = getelementptr ptr, ptr %t5, i32 1
  %t1251 = load ptr, ptr %t1250
  %t1252 = getelementptr ptr, ptr %t5, i32 2
  %t1253 = load ptr, ptr %t1252
  %t1254 = getelementptr i8, ptr %t5, i64 -8
  %t1255 = load i32, ptr %t1254
  %t1256 = icmp eq i32 %t1255, 1
  br i1 %t1256, label %reuse.in_place.1257, label %reuse.copy.1258
reuse.in_place.1257:
  %t1260 = inttoptr i64 74 to ptr
  %t1261 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1260, ptr %t1261
  br label %reuse.join.1259
reuse.copy.1258:
  %t1262 = call ptr @__alloc(i64 24, i32 2)
  %t1263 = inttoptr i64 74 to ptr
  %t1264 = getelementptr ptr, ptr %t1262, i32 0
  store ptr %t1263, ptr %t1264
  call void @__inc_ref(ptr %t1251)
  %t1265 = getelementptr ptr, ptr %t1262, i32 1
  store ptr %t1251, ptr %t1265
  call void @__inc_ref(ptr %t1253)
  %t1266 = getelementptr ptr, ptr %t1262, i32 2
  store ptr %t1253, ptr %t1266
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1259
reuse.join.1259:
  %t1267 = phi ptr [ %t5, %reuse.in_place.1257 ], [ %t1262, %reuse.copy.1258 ]
  %t1268 = call ptr @__alloc(i64 16, i32 1)
  %t1269 = inttoptr i64 167 to ptr
  %t1270 = getelementptr ptr, ptr %t1268, i32 0
  store ptr %t1269, ptr %t1270
  call void @__inc_ref(ptr %t6)
  %t1271 = getelementptr ptr, ptr %t1268, i32 1
  store ptr %t6, ptr %t1271
  call void @__free_recursive(ptr %t6)
  store ptr %t1267, ptr %t3
  store ptr %t1268, ptr %t4
  br label %tco.loop.0
tco.case.arm.92.1272:
  %t1273 = getelementptr ptr, ptr %t5, i32 1
  %t1274 = load ptr, ptr %t1273
  %t1275 = getelementptr ptr, ptr %t5, i32 2
  %t1276 = load ptr, ptr %t1275
  %t1277 = getelementptr i8, ptr %t5, i64 -8
  %t1278 = load i32, ptr %t1277
  %t1279 = icmp eq i32 %t1278, 1
  br i1 %t1279, label %reuse.in_place.1280, label %reuse.copy.1281
reuse.in_place.1280:
  %t1283 = inttoptr i64 74 to ptr
  %t1284 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1283, ptr %t1284
  br label %reuse.join.1282
reuse.copy.1281:
  %t1285 = call ptr @__alloc(i64 24, i32 2)
  %t1286 = inttoptr i64 74 to ptr
  %t1287 = getelementptr ptr, ptr %t1285, i32 0
  store ptr %t1286, ptr %t1287
  call void @__inc_ref(ptr %t1274)
  %t1288 = getelementptr ptr, ptr %t1285, i32 1
  store ptr %t1274, ptr %t1288
  call void @__inc_ref(ptr %t1276)
  %t1289 = getelementptr ptr, ptr %t1285, i32 2
  store ptr %t1276, ptr %t1289
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1282
reuse.join.1282:
  %t1290 = phi ptr [ %t5, %reuse.in_place.1280 ], [ %t1285, %reuse.copy.1281 ]
  %t1291 = call ptr @__alloc(i64 16, i32 1)
  %t1292 = inttoptr i64 168 to ptr
  %t1293 = getelementptr ptr, ptr %t1291, i32 0
  store ptr %t1292, ptr %t1293
  call void @__inc_ref(ptr %t6)
  %t1294 = getelementptr ptr, ptr %t1291, i32 1
  store ptr %t6, ptr %t1294
  call void @__free_recursive(ptr %t6)
  store ptr %t1290, ptr %t3
  store ptr %t1291, ptr %t4
  br label %tco.loop.0
tco.case.arm.93.1295:
  %t1296 = getelementptr ptr, ptr %t5, i32 1
  %t1297 = load ptr, ptr %t1296
  %t1298 = getelementptr ptr, ptr %t5, i32 2
  %t1299 = load ptr, ptr %t1298
  %t1300 = getelementptr i8, ptr %t5, i64 -8
  %t1301 = load i32, ptr %t1300
  %t1302 = icmp eq i32 %t1301, 1
  br i1 %t1302, label %reuse.in_place.1303, label %reuse.copy.1304
reuse.in_place.1303:
  %t1306 = inttoptr i64 74 to ptr
  %t1307 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1306, ptr %t1307
  br label %reuse.join.1305
reuse.copy.1304:
  %t1308 = call ptr @__alloc(i64 24, i32 2)
  %t1309 = inttoptr i64 74 to ptr
  %t1310 = getelementptr ptr, ptr %t1308, i32 0
  store ptr %t1309, ptr %t1310
  call void @__inc_ref(ptr %t1297)
  %t1311 = getelementptr ptr, ptr %t1308, i32 1
  store ptr %t1297, ptr %t1311
  call void @__inc_ref(ptr %t1299)
  %t1312 = getelementptr ptr, ptr %t1308, i32 2
  store ptr %t1299, ptr %t1312
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1305
reuse.join.1305:
  %t1313 = phi ptr [ %t5, %reuse.in_place.1303 ], [ %t1308, %reuse.copy.1304 ]
  %t1314 = call ptr @__alloc(i64 16, i32 1)
  %t1315 = inttoptr i64 169 to ptr
  %t1316 = getelementptr ptr, ptr %t1314, i32 0
  store ptr %t1315, ptr %t1316
  call void @__inc_ref(ptr %t6)
  %t1317 = getelementptr ptr, ptr %t1314, i32 1
  store ptr %t6, ptr %t1317
  call void @__free_recursive(ptr %t6)
  store ptr %t1313, ptr %t3
  store ptr %t1314, ptr %t4
  br label %tco.loop.0
tco.case.arm.94.1318:
  %t1319 = getelementptr ptr, ptr %t5, i32 1
  %t1320 = load ptr, ptr %t1319
  call void @__inc_ref(ptr %t1320)
  %t1321 = getelementptr ptr, ptr %t5, i32 2
  %t1322 = load ptr, ptr %t1321
  call void @__inc_ref(ptr %t1322)
  %t1323 = getelementptr ptr, ptr %t5, i32 3
  %t1324 = load ptr, ptr %t1323
  call void @__inc_ref(ptr %t1324)
  %t1325 = call ptr @__alloc(i64 24, i32 2)
  %t1326 = inttoptr i64 74 to ptr
  %t1327 = getelementptr ptr, ptr %t1325, i32 0
  store ptr %t1326, ptr %t1327
  call void @__inc_ref(ptr %t1320)
  %t1328 = getelementptr ptr, ptr %t1325, i32 1
  store ptr %t1320, ptr %t1328
  call void @__inc_ref(ptr %t1322)
  %t1329 = getelementptr ptr, ptr %t1325, i32 2
  store ptr %t1322, ptr %t1329
  %t1330 = call ptr @__alloc(i64 24, i32 2)
  %t1331 = inttoptr i64 170 to ptr
  %t1332 = getelementptr ptr, ptr %t1330, i32 0
  store ptr %t1331, ptr %t1332
  call void @__inc_ref(ptr %t6)
  %t1333 = getelementptr ptr, ptr %t1330, i32 1
  store ptr %t6, ptr %t1333
  call void @__inc_ref(ptr %t1324)
  %t1334 = getelementptr ptr, ptr %t1330, i32 2
  store ptr %t1324, ptr %t1334
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t1324)
  call void @__free_recursive(ptr %t1322)
  call void @__free_recursive(ptr %t1320)
  store ptr %t1325, ptr %t3
  store ptr %t1330, ptr %t4
  br label %tco.loop.0
tco.case.arm.95.1335:
  %t1336 = getelementptr ptr, ptr %t5, i32 1
  %t1337 = load ptr, ptr %t1336
  %t1338 = getelementptr ptr, ptr %t5, i32 2
  %t1339 = load ptr, ptr %t1338
  %t1340 = getelementptr i8, ptr %t5, i64 -8
  %t1341 = load i32, ptr %t1340
  %t1342 = icmp eq i32 %t1341, 1
  br i1 %t1342, label %reuse.in_place.1343, label %reuse.copy.1344
reuse.in_place.1343:
  %t1346 = inttoptr i64 74 to ptr
  %t1347 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1346, ptr %t1347
  br label %reuse.join.1345
reuse.copy.1344:
  %t1348 = call ptr @__alloc(i64 24, i32 2)
  %t1349 = inttoptr i64 74 to ptr
  %t1350 = getelementptr ptr, ptr %t1348, i32 0
  store ptr %t1349, ptr %t1350
  call void @__inc_ref(ptr %t1337)
  %t1351 = getelementptr ptr, ptr %t1348, i32 1
  store ptr %t1337, ptr %t1351
  call void @__inc_ref(ptr %t1339)
  %t1352 = getelementptr ptr, ptr %t1348, i32 2
  store ptr %t1339, ptr %t1352
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1345
reuse.join.1345:
  %t1353 = phi ptr [ %t5, %reuse.in_place.1343 ], [ %t1348, %reuse.copy.1344 ]
  %t1354 = call ptr @__alloc(i64 16, i32 1)
  %t1355 = inttoptr i64 171 to ptr
  %t1356 = getelementptr ptr, ptr %t1354, i32 0
  store ptr %t1355, ptr %t1356
  call void @__inc_ref(ptr %t6)
  %t1357 = getelementptr ptr, ptr %t1354, i32 1
  store ptr %t6, ptr %t1357
  call void @__free_recursive(ptr %t6)
  store ptr %t1353, ptr %t3
  store ptr %t1354, ptr %t4
  br label %tco.loop.0
tco.case.arm.96.1358:
  %t1359 = getelementptr ptr, ptr %t5, i32 1
  %t1360 = load ptr, ptr %t1359
  %t1361 = getelementptr ptr, ptr %t5, i32 2
  %t1362 = load ptr, ptr %t1361
  %t1363 = getelementptr i8, ptr %t5, i64 -8
  %t1364 = load i32, ptr %t1363
  %t1365 = icmp eq i32 %t1364, 1
  br i1 %t1365, label %reuse.in_place.1366, label %reuse.copy.1367
reuse.in_place.1366:
  %t1369 = inttoptr i64 74 to ptr
  %t1370 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1369, ptr %t1370
  br label %reuse.join.1368
reuse.copy.1367:
  %t1371 = call ptr @__alloc(i64 24, i32 2)
  %t1372 = inttoptr i64 74 to ptr
  %t1373 = getelementptr ptr, ptr %t1371, i32 0
  store ptr %t1372, ptr %t1373
  call void @__inc_ref(ptr %t1360)
  %t1374 = getelementptr ptr, ptr %t1371, i32 1
  store ptr %t1360, ptr %t1374
  call void @__inc_ref(ptr %t1362)
  %t1375 = getelementptr ptr, ptr %t1371, i32 2
  store ptr %t1362, ptr %t1375
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1368
reuse.join.1368:
  %t1376 = phi ptr [ %t5, %reuse.in_place.1366 ], [ %t1371, %reuse.copy.1367 ]
  %t1377 = call ptr @__alloc(i64 16, i32 1)
  %t1378 = inttoptr i64 172 to ptr
  %t1379 = getelementptr ptr, ptr %t1377, i32 0
  store ptr %t1378, ptr %t1379
  call void @__inc_ref(ptr %t6)
  %t1380 = getelementptr ptr, ptr %t1377, i32 1
  store ptr %t6, ptr %t1380
  call void @__free_recursive(ptr %t6)
  store ptr %t1376, ptr %t3
  store ptr %t1377, ptr %t4
  br label %tco.loop.0
tco.case.arm.97.1381:
  %t1382 = getelementptr ptr, ptr %t5, i32 1
  %t1383 = load ptr, ptr %t1382
  %t1384 = getelementptr ptr, ptr %t5, i32 2
  %t1385 = load ptr, ptr %t1384
  %t1386 = getelementptr i8, ptr %t5, i64 -8
  %t1387 = load i32, ptr %t1386
  %t1388 = icmp eq i32 %t1387, 1
  br i1 %t1388, label %reuse.in_place.1389, label %reuse.copy.1390
reuse.in_place.1389:
  %t1392 = inttoptr i64 74 to ptr
  %t1393 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1392, ptr %t1393
  br label %reuse.join.1391
reuse.copy.1390:
  %t1394 = call ptr @__alloc(i64 24, i32 2)
  %t1395 = inttoptr i64 74 to ptr
  %t1396 = getelementptr ptr, ptr %t1394, i32 0
  store ptr %t1395, ptr %t1396
  call void @__inc_ref(ptr %t1383)
  %t1397 = getelementptr ptr, ptr %t1394, i32 1
  store ptr %t1383, ptr %t1397
  call void @__inc_ref(ptr %t1385)
  %t1398 = getelementptr ptr, ptr %t1394, i32 2
  store ptr %t1385, ptr %t1398
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1391
reuse.join.1391:
  %t1399 = phi ptr [ %t5, %reuse.in_place.1389 ], [ %t1394, %reuse.copy.1390 ]
  %t1400 = call ptr @__alloc(i64 16, i32 1)
  %t1401 = inttoptr i64 173 to ptr
  %t1402 = getelementptr ptr, ptr %t1400, i32 0
  store ptr %t1401, ptr %t1402
  call void @__inc_ref(ptr %t6)
  %t1403 = getelementptr ptr, ptr %t1400, i32 1
  store ptr %t6, ptr %t1403
  call void @__free_recursive(ptr %t6)
  store ptr %t1399, ptr %t3
  store ptr %t1400, ptr %t4
  br label %tco.loop.0
tco.case.arm.98.1404:
  %t1405 = getelementptr ptr, ptr %t5, i32 1
  %t1406 = load ptr, ptr %t1405
  %t1407 = getelementptr ptr, ptr %t5, i32 2
  %t1408 = load ptr, ptr %t1407
  %t1409 = getelementptr i8, ptr %t5, i64 -8
  %t1410 = load i32, ptr %t1409
  %t1411 = icmp eq i32 %t1410, 1
  br i1 %t1411, label %reuse.in_place.1412, label %reuse.copy.1413
reuse.in_place.1412:
  %t1415 = inttoptr i64 74 to ptr
  %t1416 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1415, ptr %t1416
  br label %reuse.join.1414
reuse.copy.1413:
  %t1417 = call ptr @__alloc(i64 24, i32 2)
  %t1418 = inttoptr i64 74 to ptr
  %t1419 = getelementptr ptr, ptr %t1417, i32 0
  store ptr %t1418, ptr %t1419
  call void @__inc_ref(ptr %t1406)
  %t1420 = getelementptr ptr, ptr %t1417, i32 1
  store ptr %t1406, ptr %t1420
  call void @__inc_ref(ptr %t1408)
  %t1421 = getelementptr ptr, ptr %t1417, i32 2
  store ptr %t1408, ptr %t1421
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1414
reuse.join.1414:
  %t1422 = phi ptr [ %t5, %reuse.in_place.1412 ], [ %t1417, %reuse.copy.1413 ]
  %t1423 = call ptr @__alloc(i64 16, i32 1)
  %t1424 = inttoptr i64 174 to ptr
  %t1425 = getelementptr ptr, ptr %t1423, i32 0
  store ptr %t1424, ptr %t1425
  call void @__inc_ref(ptr %t6)
  %t1426 = getelementptr ptr, ptr %t1423, i32 1
  store ptr %t6, ptr %t1426
  call void @__free_recursive(ptr %t6)
  store ptr %t1422, ptr %t3
  store ptr %t1423, ptr %t4
  br label %tco.loop.0
tco.case.arm.99.1427:
  %t1428 = getelementptr ptr, ptr %t5, i32 1
  %t1429 = load ptr, ptr %t1428
  %t1430 = getelementptr ptr, ptr %t5, i32 2
  %t1431 = load ptr, ptr %t1430
  %t1432 = getelementptr i8, ptr %t5, i64 -8
  %t1433 = load i32, ptr %t1432
  %t1434 = icmp eq i32 %t1433, 1
  br i1 %t1434, label %reuse.in_place.1435, label %reuse.copy.1436
reuse.in_place.1435:
  %t1438 = inttoptr i64 74 to ptr
  %t1439 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1438, ptr %t1439
  br label %reuse.join.1437
reuse.copy.1436:
  %t1440 = call ptr @__alloc(i64 24, i32 2)
  %t1441 = inttoptr i64 74 to ptr
  %t1442 = getelementptr ptr, ptr %t1440, i32 0
  store ptr %t1441, ptr %t1442
  call void @__inc_ref(ptr %t1429)
  %t1443 = getelementptr ptr, ptr %t1440, i32 1
  store ptr %t1429, ptr %t1443
  call void @__inc_ref(ptr %t1431)
  %t1444 = getelementptr ptr, ptr %t1440, i32 2
  store ptr %t1431, ptr %t1444
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1437
reuse.join.1437:
  %t1445 = phi ptr [ %t5, %reuse.in_place.1435 ], [ %t1440, %reuse.copy.1436 ]
  %t1446 = call ptr @__alloc(i64 16, i32 1)
  %t1447 = inttoptr i64 175 to ptr
  %t1448 = getelementptr ptr, ptr %t1446, i32 0
  store ptr %t1447, ptr %t1448
  call void @__inc_ref(ptr %t6)
  %t1449 = getelementptr ptr, ptr %t1446, i32 1
  store ptr %t6, ptr %t1449
  call void @__free_recursive(ptr %t6)
  store ptr %t1445, ptr %t3
  store ptr %t1446, ptr %t4
  br label %tco.loop.0
tco.case.arm.100.1450:
  %t1451 = getelementptr ptr, ptr %t5, i32 1
  %t1452 = load ptr, ptr %t1451
  %t1453 = getelementptr ptr, ptr %t5, i32 2
  %t1454 = load ptr, ptr %t1453
  %t1455 = getelementptr i8, ptr %t5, i64 -8
  %t1456 = load i32, ptr %t1455
  %t1457 = icmp eq i32 %t1456, 1
  br i1 %t1457, label %reuse.in_place.1458, label %reuse.copy.1459
reuse.in_place.1458:
  %t1461 = inttoptr i64 74 to ptr
  %t1462 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1461, ptr %t1462
  br label %reuse.join.1460
reuse.copy.1459:
  %t1463 = call ptr @__alloc(i64 24, i32 2)
  %t1464 = inttoptr i64 74 to ptr
  %t1465 = getelementptr ptr, ptr %t1463, i32 0
  store ptr %t1464, ptr %t1465
  call void @__inc_ref(ptr %t1452)
  %t1466 = getelementptr ptr, ptr %t1463, i32 1
  store ptr %t1452, ptr %t1466
  call void @__inc_ref(ptr %t1454)
  %t1467 = getelementptr ptr, ptr %t1463, i32 2
  store ptr %t1454, ptr %t1467
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1460
reuse.join.1460:
  %t1468 = phi ptr [ %t5, %reuse.in_place.1458 ], [ %t1463, %reuse.copy.1459 ]
  %t1469 = call ptr @__alloc(i64 16, i32 1)
  %t1470 = inttoptr i64 176 to ptr
  %t1471 = getelementptr ptr, ptr %t1469, i32 0
  store ptr %t1470, ptr %t1471
  call void @__inc_ref(ptr %t6)
  %t1472 = getelementptr ptr, ptr %t1469, i32 1
  store ptr %t6, ptr %t1472
  call void @__free_recursive(ptr %t6)
  store ptr %t1468, ptr %t3
  store ptr %t1469, ptr %t4
  br label %tco.loop.0
tco.case.arm.101.1473:
  %t1474 = getelementptr ptr, ptr %t5, i32 1
  %t1475 = load ptr, ptr %t1474
  %t1476 = getelementptr ptr, ptr %t5, i32 2
  %t1477 = load ptr, ptr %t1476
  %t1478 = getelementptr i8, ptr %t5, i64 -8
  %t1479 = load i32, ptr %t1478
  %t1480 = icmp eq i32 %t1479, 1
  br i1 %t1480, label %reuse.in_place.1481, label %reuse.copy.1482
reuse.in_place.1481:
  %t1484 = inttoptr i64 74 to ptr
  %t1485 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1484, ptr %t1485
  br label %reuse.join.1483
reuse.copy.1482:
  %t1486 = call ptr @__alloc(i64 24, i32 2)
  %t1487 = inttoptr i64 74 to ptr
  %t1488 = getelementptr ptr, ptr %t1486, i32 0
  store ptr %t1487, ptr %t1488
  call void @__inc_ref(ptr %t1475)
  %t1489 = getelementptr ptr, ptr %t1486, i32 1
  store ptr %t1475, ptr %t1489
  call void @__inc_ref(ptr %t1477)
  %t1490 = getelementptr ptr, ptr %t1486, i32 2
  store ptr %t1477, ptr %t1490
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1483
reuse.join.1483:
  %t1491 = phi ptr [ %t5, %reuse.in_place.1481 ], [ %t1486, %reuse.copy.1482 ]
  %t1492 = call ptr @__alloc(i64 16, i32 1)
  %t1493 = inttoptr i64 177 to ptr
  %t1494 = getelementptr ptr, ptr %t1492, i32 0
  store ptr %t1493, ptr %t1494
  call void @__inc_ref(ptr %t6)
  %t1495 = getelementptr ptr, ptr %t1492, i32 1
  store ptr %t6, ptr %t1495
  call void @__free_recursive(ptr %t6)
  store ptr %t1491, ptr %t3
  store ptr %t1492, ptr %t4
  br label %tco.loop.0
tco.case.arm.102.1496:
  %t1497 = getelementptr ptr, ptr %t5, i32 1
  %t1498 = load ptr, ptr %t1497
  %t1499 = getelementptr ptr, ptr %t5, i32 2
  %t1500 = load ptr, ptr %t1499
  %t1501 = getelementptr i8, ptr %t5, i64 -8
  %t1502 = load i32, ptr %t1501
  %t1503 = icmp eq i32 %t1502, 1
  br i1 %t1503, label %reuse.in_place.1504, label %reuse.copy.1505
reuse.in_place.1504:
  %t1507 = inttoptr i64 74 to ptr
  %t1508 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1507, ptr %t1508
  br label %reuse.join.1506
reuse.copy.1505:
  %t1509 = call ptr @__alloc(i64 24, i32 2)
  %t1510 = inttoptr i64 74 to ptr
  %t1511 = getelementptr ptr, ptr %t1509, i32 0
  store ptr %t1510, ptr %t1511
  call void @__inc_ref(ptr %t1498)
  %t1512 = getelementptr ptr, ptr %t1509, i32 1
  store ptr %t1498, ptr %t1512
  call void @__inc_ref(ptr %t1500)
  %t1513 = getelementptr ptr, ptr %t1509, i32 2
  store ptr %t1500, ptr %t1513
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1506
reuse.join.1506:
  %t1514 = phi ptr [ %t5, %reuse.in_place.1504 ], [ %t1509, %reuse.copy.1505 ]
  %t1515 = call ptr @__alloc(i64 16, i32 1)
  %t1516 = inttoptr i64 178 to ptr
  %t1517 = getelementptr ptr, ptr %t1515, i32 0
  store ptr %t1516, ptr %t1517
  call void @__inc_ref(ptr %t6)
  %t1518 = getelementptr ptr, ptr %t1515, i32 1
  store ptr %t6, ptr %t1518
  call void @__free_recursive(ptr %t6)
  store ptr %t1514, ptr %t3
  store ptr %t1515, ptr %t4
  br label %tco.loop.0
tco.case.arm.103.1519:
  %t1520 = getelementptr ptr, ptr %t5, i32 1
  %t1521 = load ptr, ptr %t1520
  %t1522 = getelementptr ptr, ptr %t5, i32 2
  %t1523 = load ptr, ptr %t1522
  %t1524 = getelementptr i8, ptr %t5, i64 -8
  %t1525 = load i32, ptr %t1524
  %t1526 = icmp eq i32 %t1525, 1
  br i1 %t1526, label %reuse.in_place.1527, label %reuse.copy.1528
reuse.in_place.1527:
  %t1530 = inttoptr i64 74 to ptr
  %t1531 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1530, ptr %t1531
  br label %reuse.join.1529
reuse.copy.1528:
  %t1532 = call ptr @__alloc(i64 24, i32 2)
  %t1533 = inttoptr i64 74 to ptr
  %t1534 = getelementptr ptr, ptr %t1532, i32 0
  store ptr %t1533, ptr %t1534
  call void @__inc_ref(ptr %t1521)
  %t1535 = getelementptr ptr, ptr %t1532, i32 1
  store ptr %t1521, ptr %t1535
  call void @__inc_ref(ptr %t1523)
  %t1536 = getelementptr ptr, ptr %t1532, i32 2
  store ptr %t1523, ptr %t1536
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1529
reuse.join.1529:
  %t1537 = phi ptr [ %t5, %reuse.in_place.1527 ], [ %t1532, %reuse.copy.1528 ]
  %t1538 = call ptr @__alloc(i64 16, i32 1)
  %t1539 = inttoptr i64 179 to ptr
  %t1540 = getelementptr ptr, ptr %t1538, i32 0
  store ptr %t1539, ptr %t1540
  call void @__inc_ref(ptr %t6)
  %t1541 = getelementptr ptr, ptr %t1538, i32 1
  store ptr %t6, ptr %t1541
  call void @__free_recursive(ptr %t6)
  store ptr %t1537, ptr %t3
  store ptr %t1538, ptr %t4
  br label %tco.loop.0
tco.case.arm.104.1542:
  %t1543 = getelementptr ptr, ptr %t5, i32 1
  %t1544 = load ptr, ptr %t1543
  %t1545 = getelementptr ptr, ptr %t5, i32 2
  %t1546 = load ptr, ptr %t1545
  %t1547 = getelementptr i8, ptr %t5, i64 -8
  %t1548 = load i32, ptr %t1547
  %t1549 = icmp eq i32 %t1548, 1
  br i1 %t1549, label %reuse.in_place.1550, label %reuse.copy.1551
reuse.in_place.1550:
  %t1553 = inttoptr i64 74 to ptr
  %t1554 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1553, ptr %t1554
  br label %reuse.join.1552
reuse.copy.1551:
  %t1555 = call ptr @__alloc(i64 24, i32 2)
  %t1556 = inttoptr i64 74 to ptr
  %t1557 = getelementptr ptr, ptr %t1555, i32 0
  store ptr %t1556, ptr %t1557
  call void @__inc_ref(ptr %t1544)
  %t1558 = getelementptr ptr, ptr %t1555, i32 1
  store ptr %t1544, ptr %t1558
  call void @__inc_ref(ptr %t1546)
  %t1559 = getelementptr ptr, ptr %t1555, i32 2
  store ptr %t1546, ptr %t1559
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1552
reuse.join.1552:
  %t1560 = phi ptr [ %t5, %reuse.in_place.1550 ], [ %t1555, %reuse.copy.1551 ]
  %t1561 = call ptr @__alloc(i64 16, i32 1)
  %t1562 = inttoptr i64 180 to ptr
  %t1563 = getelementptr ptr, ptr %t1561, i32 0
  store ptr %t1562, ptr %t1563
  call void @__inc_ref(ptr %t6)
  %t1564 = getelementptr ptr, ptr %t1561, i32 1
  store ptr %t6, ptr %t1564
  call void @__free_recursive(ptr %t6)
  store ptr %t1560, ptr %t3
  store ptr %t1561, ptr %t4
  br label %tco.loop.0
tco.case.arm.105.1565:
  %t1566 = getelementptr ptr, ptr %t5, i32 1
  %t1567 = load ptr, ptr %t1566
  %t1568 = getelementptr ptr, ptr %t5, i32 2
  %t1569 = load ptr, ptr %t1568
  %t1570 = getelementptr i8, ptr %t5, i64 -8
  %t1571 = load i32, ptr %t1570
  %t1572 = icmp eq i32 %t1571, 1
  br i1 %t1572, label %reuse.in_place.1573, label %reuse.copy.1574
reuse.in_place.1573:
  %t1576 = inttoptr i64 74 to ptr
  %t1577 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1576, ptr %t1577
  br label %reuse.join.1575
reuse.copy.1574:
  %t1578 = call ptr @__alloc(i64 24, i32 2)
  %t1579 = inttoptr i64 74 to ptr
  %t1580 = getelementptr ptr, ptr %t1578, i32 0
  store ptr %t1579, ptr %t1580
  call void @__inc_ref(ptr %t1567)
  %t1581 = getelementptr ptr, ptr %t1578, i32 1
  store ptr %t1567, ptr %t1581
  call void @__inc_ref(ptr %t1569)
  %t1582 = getelementptr ptr, ptr %t1578, i32 2
  store ptr %t1569, ptr %t1582
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1575
reuse.join.1575:
  %t1583 = phi ptr [ %t5, %reuse.in_place.1573 ], [ %t1578, %reuse.copy.1574 ]
  %t1584 = call ptr @__alloc(i64 16, i32 1)
  %t1585 = inttoptr i64 181 to ptr
  %t1586 = getelementptr ptr, ptr %t1584, i32 0
  store ptr %t1585, ptr %t1586
  call void @__inc_ref(ptr %t6)
  %t1587 = getelementptr ptr, ptr %t1584, i32 1
  store ptr %t6, ptr %t1587
  call void @__free_recursive(ptr %t6)
  store ptr %t1583, ptr %t3
  store ptr %t1584, ptr %t4
  br label %tco.loop.0
tco.case.arm.106.1588:
  %t1589 = getelementptr ptr, ptr %t5, i32 1
  %t1590 = load ptr, ptr %t1589
  %t1591 = getelementptr ptr, ptr %t5, i32 2
  %t1592 = load ptr, ptr %t1591
  %t1593 = getelementptr i8, ptr %t5, i64 -8
  %t1594 = load i32, ptr %t1593
  %t1595 = icmp eq i32 %t1594, 1
  br i1 %t1595, label %reuse.in_place.1596, label %reuse.copy.1597
reuse.in_place.1596:
  %t1599 = inttoptr i64 74 to ptr
  %t1600 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1599, ptr %t1600
  br label %reuse.join.1598
reuse.copy.1597:
  %t1601 = call ptr @__alloc(i64 24, i32 2)
  %t1602 = inttoptr i64 74 to ptr
  %t1603 = getelementptr ptr, ptr %t1601, i32 0
  store ptr %t1602, ptr %t1603
  call void @__inc_ref(ptr %t1590)
  %t1604 = getelementptr ptr, ptr %t1601, i32 1
  store ptr %t1590, ptr %t1604
  call void @__inc_ref(ptr %t1592)
  %t1605 = getelementptr ptr, ptr %t1601, i32 2
  store ptr %t1592, ptr %t1605
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1598
reuse.join.1598:
  %t1606 = phi ptr [ %t5, %reuse.in_place.1596 ], [ %t1601, %reuse.copy.1597 ]
  %t1607 = call ptr @__alloc(i64 16, i32 1)
  %t1608 = inttoptr i64 182 to ptr
  %t1609 = getelementptr ptr, ptr %t1607, i32 0
  store ptr %t1608, ptr %t1609
  call void @__inc_ref(ptr %t6)
  %t1610 = getelementptr ptr, ptr %t1607, i32 1
  store ptr %t6, ptr %t1610
  call void @__free_recursive(ptr %t6)
  store ptr %t1606, ptr %t3
  store ptr %t1607, ptr %t4
  br label %tco.loop.0
tco.case.arm.107.1611:
  %t1612 = getelementptr ptr, ptr %t5, i32 1
  %t1613 = load ptr, ptr %t1612
  %t1614 = getelementptr ptr, ptr %t5, i32 2
  %t1615 = load ptr, ptr %t1614
  %t1616 = getelementptr i8, ptr %t5, i64 -8
  %t1617 = load i32, ptr %t1616
  %t1618 = icmp eq i32 %t1617, 1
  br i1 %t1618, label %reuse.in_place.1619, label %reuse.copy.1620
reuse.in_place.1619:
  %t1622 = inttoptr i64 74 to ptr
  %t1623 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1622, ptr %t1623
  br label %reuse.join.1621
reuse.copy.1620:
  %t1624 = call ptr @__alloc(i64 24, i32 2)
  %t1625 = inttoptr i64 74 to ptr
  %t1626 = getelementptr ptr, ptr %t1624, i32 0
  store ptr %t1625, ptr %t1626
  call void @__inc_ref(ptr %t1613)
  %t1627 = getelementptr ptr, ptr %t1624, i32 1
  store ptr %t1613, ptr %t1627
  call void @__inc_ref(ptr %t1615)
  %t1628 = getelementptr ptr, ptr %t1624, i32 2
  store ptr %t1615, ptr %t1628
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1621
reuse.join.1621:
  %t1629 = phi ptr [ %t5, %reuse.in_place.1619 ], [ %t1624, %reuse.copy.1620 ]
  %t1630 = call ptr @__alloc(i64 16, i32 1)
  %t1631 = inttoptr i64 183 to ptr
  %t1632 = getelementptr ptr, ptr %t1630, i32 0
  store ptr %t1631, ptr %t1632
  call void @__inc_ref(ptr %t6)
  %t1633 = getelementptr ptr, ptr %t1630, i32 1
  store ptr %t6, ptr %t1633
  call void @__free_recursive(ptr %t6)
  store ptr %t1629, ptr %t3
  store ptr %t1630, ptr %t4
  br label %tco.loop.0
tco.case.arm.108.1634:
  %t1635 = getelementptr ptr, ptr %t5, i32 1
  %t1636 = load ptr, ptr %t1635
  %t1637 = getelementptr ptr, ptr %t5, i32 2
  %t1638 = load ptr, ptr %t1637
  %t1639 = getelementptr i8, ptr %t5, i64 -8
  %t1640 = load i32, ptr %t1639
  %t1641 = icmp eq i32 %t1640, 1
  br i1 %t1641, label %reuse.in_place.1642, label %reuse.copy.1643
reuse.in_place.1642:
  %t1645 = inttoptr i64 74 to ptr
  %t1646 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1645, ptr %t1646
  br label %reuse.join.1644
reuse.copy.1643:
  %t1647 = call ptr @__alloc(i64 24, i32 2)
  %t1648 = inttoptr i64 74 to ptr
  %t1649 = getelementptr ptr, ptr %t1647, i32 0
  store ptr %t1648, ptr %t1649
  call void @__inc_ref(ptr %t1636)
  %t1650 = getelementptr ptr, ptr %t1647, i32 1
  store ptr %t1636, ptr %t1650
  call void @__inc_ref(ptr %t1638)
  %t1651 = getelementptr ptr, ptr %t1647, i32 2
  store ptr %t1638, ptr %t1651
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1644
reuse.join.1644:
  %t1652 = phi ptr [ %t5, %reuse.in_place.1642 ], [ %t1647, %reuse.copy.1643 ]
  %t1653 = call ptr @__alloc(i64 16, i32 1)
  %t1654 = inttoptr i64 184 to ptr
  %t1655 = getelementptr ptr, ptr %t1653, i32 0
  store ptr %t1654, ptr %t1655
  call void @__inc_ref(ptr %t6)
  %t1656 = getelementptr ptr, ptr %t1653, i32 1
  store ptr %t6, ptr %t1656
  call void @__free_recursive(ptr %t6)
  store ptr %t1652, ptr %t3
  store ptr %t1653, ptr %t4
  br label %tco.loop.0
tco.case.arm.109.1657:
  %t1658 = getelementptr ptr, ptr %t5, i32 1
  %t1659 = load ptr, ptr %t1658
  %t1660 = getelementptr ptr, ptr %t5, i32 2
  %t1661 = load ptr, ptr %t1660
  %t1662 = getelementptr i8, ptr %t5, i64 -8
  %t1663 = load i32, ptr %t1662
  %t1664 = icmp eq i32 %t1663, 1
  br i1 %t1664, label %reuse.in_place.1665, label %reuse.copy.1666
reuse.in_place.1665:
  %t1668 = inttoptr i64 74 to ptr
  %t1669 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1668, ptr %t1669
  br label %reuse.join.1667
reuse.copy.1666:
  %t1670 = call ptr @__alloc(i64 24, i32 2)
  %t1671 = inttoptr i64 74 to ptr
  %t1672 = getelementptr ptr, ptr %t1670, i32 0
  store ptr %t1671, ptr %t1672
  call void @__inc_ref(ptr %t1659)
  %t1673 = getelementptr ptr, ptr %t1670, i32 1
  store ptr %t1659, ptr %t1673
  call void @__inc_ref(ptr %t1661)
  %t1674 = getelementptr ptr, ptr %t1670, i32 2
  store ptr %t1661, ptr %t1674
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1667
reuse.join.1667:
  %t1675 = phi ptr [ %t5, %reuse.in_place.1665 ], [ %t1670, %reuse.copy.1666 ]
  %t1676 = call ptr @__alloc(i64 16, i32 1)
  %t1677 = inttoptr i64 185 to ptr
  %t1678 = getelementptr ptr, ptr %t1676, i32 0
  store ptr %t1677, ptr %t1678
  call void @__inc_ref(ptr %t6)
  %t1679 = getelementptr ptr, ptr %t1676, i32 1
  store ptr %t6, ptr %t1679
  call void @__free_recursive(ptr %t6)
  store ptr %t1675, ptr %t3
  store ptr %t1676, ptr %t4
  br label %tco.loop.0
tco.case.arm.110.1680:
  %t1681 = getelementptr ptr, ptr %t5, i32 1
  %t1682 = load ptr, ptr %t1681
  %t1683 = getelementptr ptr, ptr %t5, i32 2
  %t1684 = load ptr, ptr %t1683
  %t1685 = getelementptr i8, ptr %t5, i64 -8
  %t1686 = load i32, ptr %t1685
  %t1687 = icmp eq i32 %t1686, 1
  br i1 %t1687, label %reuse.in_place.1688, label %reuse.copy.1689
reuse.in_place.1688:
  %t1691 = inttoptr i64 74 to ptr
  %t1692 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1691, ptr %t1692
  br label %reuse.join.1690
reuse.copy.1689:
  %t1693 = call ptr @__alloc(i64 24, i32 2)
  %t1694 = inttoptr i64 74 to ptr
  %t1695 = getelementptr ptr, ptr %t1693, i32 0
  store ptr %t1694, ptr %t1695
  call void @__inc_ref(ptr %t1682)
  %t1696 = getelementptr ptr, ptr %t1693, i32 1
  store ptr %t1682, ptr %t1696
  call void @__inc_ref(ptr %t1684)
  %t1697 = getelementptr ptr, ptr %t1693, i32 2
  store ptr %t1684, ptr %t1697
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1690
reuse.join.1690:
  %t1698 = phi ptr [ %t5, %reuse.in_place.1688 ], [ %t1693, %reuse.copy.1689 ]
  %t1699 = call ptr @__alloc(i64 16, i32 1)
  %t1700 = inttoptr i64 186 to ptr
  %t1701 = getelementptr ptr, ptr %t1699, i32 0
  store ptr %t1700, ptr %t1701
  call void @__inc_ref(ptr %t6)
  %t1702 = getelementptr ptr, ptr %t1699, i32 1
  store ptr %t6, ptr %t1702
  call void @__free_recursive(ptr %t6)
  store ptr %t1698, ptr %t3
  store ptr %t1699, ptr %t4
  br label %tco.loop.0
tco.case.arm.111.1703:
  %t1704 = getelementptr ptr, ptr %t5, i32 1
  %t1705 = load ptr, ptr %t1704
  %t1706 = getelementptr ptr, ptr %t5, i32 2
  %t1707 = load ptr, ptr %t1706
  %t1708 = getelementptr i8, ptr %t5, i64 -8
  %t1709 = load i32, ptr %t1708
  %t1710 = icmp eq i32 %t1709, 1
  br i1 %t1710, label %reuse.in_place.1711, label %reuse.copy.1712
reuse.in_place.1711:
  %t1714 = inttoptr i64 74 to ptr
  %t1715 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1714, ptr %t1715
  br label %reuse.join.1713
reuse.copy.1712:
  %t1716 = call ptr @__alloc(i64 24, i32 2)
  %t1717 = inttoptr i64 74 to ptr
  %t1718 = getelementptr ptr, ptr %t1716, i32 0
  store ptr %t1717, ptr %t1718
  call void @__inc_ref(ptr %t1705)
  %t1719 = getelementptr ptr, ptr %t1716, i32 1
  store ptr %t1705, ptr %t1719
  call void @__inc_ref(ptr %t1707)
  %t1720 = getelementptr ptr, ptr %t1716, i32 2
  store ptr %t1707, ptr %t1720
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1713
reuse.join.1713:
  %t1721 = phi ptr [ %t5, %reuse.in_place.1711 ], [ %t1716, %reuse.copy.1712 ]
  %t1722 = call ptr @__alloc(i64 16, i32 1)
  %t1723 = inttoptr i64 187 to ptr
  %t1724 = getelementptr ptr, ptr %t1722, i32 0
  store ptr %t1723, ptr %t1724
  call void @__inc_ref(ptr %t6)
  %t1725 = getelementptr ptr, ptr %t1722, i32 1
  store ptr %t6, ptr %t1725
  call void @__free_recursive(ptr %t6)
  store ptr %t1721, ptr %t3
  store ptr %t1722, ptr %t4
  br label %tco.loop.0
tco.case.arm.112.1726:
  %t1727 = getelementptr ptr, ptr %t5, i32 1
  %t1728 = load ptr, ptr %t1727
  %t1729 = getelementptr ptr, ptr %t5, i32 2
  %t1730 = load ptr, ptr %t1729
  %t1731 = getelementptr i8, ptr %t5, i64 -8
  %t1732 = load i32, ptr %t1731
  %t1733 = icmp eq i32 %t1732, 1
  br i1 %t1733, label %reuse.in_place.1734, label %reuse.copy.1735
reuse.in_place.1734:
  %t1737 = inttoptr i64 74 to ptr
  %t1738 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1737, ptr %t1738
  br label %reuse.join.1736
reuse.copy.1735:
  %t1739 = call ptr @__alloc(i64 24, i32 2)
  %t1740 = inttoptr i64 74 to ptr
  %t1741 = getelementptr ptr, ptr %t1739, i32 0
  store ptr %t1740, ptr %t1741
  call void @__inc_ref(ptr %t1728)
  %t1742 = getelementptr ptr, ptr %t1739, i32 1
  store ptr %t1728, ptr %t1742
  call void @__inc_ref(ptr %t1730)
  %t1743 = getelementptr ptr, ptr %t1739, i32 2
  store ptr %t1730, ptr %t1743
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1736
reuse.join.1736:
  %t1744 = phi ptr [ %t5, %reuse.in_place.1734 ], [ %t1739, %reuse.copy.1735 ]
  %t1745 = call ptr @__alloc(i64 16, i32 1)
  %t1746 = inttoptr i64 188 to ptr
  %t1747 = getelementptr ptr, ptr %t1745, i32 0
  store ptr %t1746, ptr %t1747
  call void @__inc_ref(ptr %t6)
  %t1748 = getelementptr ptr, ptr %t1745, i32 1
  store ptr %t6, ptr %t1748
  call void @__free_recursive(ptr %t6)
  store ptr %t1744, ptr %t3
  store ptr %t1745, ptr %t4
  br label %tco.loop.0
tco.case.arm.113.1749:
  %t1750 = getelementptr ptr, ptr %t5, i32 1
  %t1751 = load ptr, ptr %t1750
  %t1752 = getelementptr ptr, ptr %t5, i32 2
  %t1753 = load ptr, ptr %t1752
  %t1754 = getelementptr i8, ptr %t5, i64 -8
  %t1755 = load i32, ptr %t1754
  %t1756 = icmp eq i32 %t1755, 1
  br i1 %t1756, label %reuse.in_place.1757, label %reuse.copy.1758
reuse.in_place.1757:
  %t1760 = inttoptr i64 74 to ptr
  %t1761 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1760, ptr %t1761
  br label %reuse.join.1759
reuse.copy.1758:
  %t1762 = call ptr @__alloc(i64 24, i32 2)
  %t1763 = inttoptr i64 74 to ptr
  %t1764 = getelementptr ptr, ptr %t1762, i32 0
  store ptr %t1763, ptr %t1764
  call void @__inc_ref(ptr %t1751)
  %t1765 = getelementptr ptr, ptr %t1762, i32 1
  store ptr %t1751, ptr %t1765
  call void @__inc_ref(ptr %t1753)
  %t1766 = getelementptr ptr, ptr %t1762, i32 2
  store ptr %t1753, ptr %t1766
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1759
reuse.join.1759:
  %t1767 = phi ptr [ %t5, %reuse.in_place.1757 ], [ %t1762, %reuse.copy.1758 ]
  %t1768 = call ptr @__alloc(i64 16, i32 1)
  %t1769 = inttoptr i64 189 to ptr
  %t1770 = getelementptr ptr, ptr %t1768, i32 0
  store ptr %t1769, ptr %t1770
  call void @__inc_ref(ptr %t6)
  %t1771 = getelementptr ptr, ptr %t1768, i32 1
  store ptr %t6, ptr %t1771
  call void @__free_recursive(ptr %t6)
  store ptr %t1767, ptr %t3
  store ptr %t1768, ptr %t4
  br label %tco.loop.0
tco.case.arm.114.1772:
  %t1773 = getelementptr ptr, ptr %t5, i32 1
  %t1774 = load ptr, ptr %t1773
  %t1775 = getelementptr ptr, ptr %t5, i32 2
  %t1776 = load ptr, ptr %t1775
  %t1777 = getelementptr i8, ptr %t5, i64 -8
  %t1778 = load i32, ptr %t1777
  %t1779 = icmp eq i32 %t1778, 1
  br i1 %t1779, label %reuse.in_place.1780, label %reuse.copy.1781
reuse.in_place.1780:
  %t1783 = inttoptr i64 74 to ptr
  %t1784 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1783, ptr %t1784
  br label %reuse.join.1782
reuse.copy.1781:
  %t1785 = call ptr @__alloc(i64 24, i32 2)
  %t1786 = inttoptr i64 74 to ptr
  %t1787 = getelementptr ptr, ptr %t1785, i32 0
  store ptr %t1786, ptr %t1787
  call void @__inc_ref(ptr %t1774)
  %t1788 = getelementptr ptr, ptr %t1785, i32 1
  store ptr %t1774, ptr %t1788
  call void @__inc_ref(ptr %t1776)
  %t1789 = getelementptr ptr, ptr %t1785, i32 2
  store ptr %t1776, ptr %t1789
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1782
reuse.join.1782:
  %t1790 = phi ptr [ %t5, %reuse.in_place.1780 ], [ %t1785, %reuse.copy.1781 ]
  %t1791 = call ptr @__alloc(i64 16, i32 1)
  %t1792 = inttoptr i64 190 to ptr
  %t1793 = getelementptr ptr, ptr %t1791, i32 0
  store ptr %t1792, ptr %t1793
  call void @__inc_ref(ptr %t6)
  %t1794 = getelementptr ptr, ptr %t1791, i32 1
  store ptr %t6, ptr %t1794
  call void @__free_recursive(ptr %t6)
  store ptr %t1790, ptr %t3
  store ptr %t1791, ptr %t4
  br label %tco.loop.0
tco.case.arm.115.1795:
  %t1796 = getelementptr ptr, ptr %t5, i32 1
  %t1797 = load ptr, ptr %t1796
  %t1798 = getelementptr ptr, ptr %t5, i32 2
  %t1799 = load ptr, ptr %t1798
  %t1800 = getelementptr i8, ptr %t5, i64 -8
  %t1801 = load i32, ptr %t1800
  %t1802 = icmp eq i32 %t1801, 1
  br i1 %t1802, label %reuse.in_place.1803, label %reuse.copy.1804
reuse.in_place.1803:
  %t1806 = inttoptr i64 74 to ptr
  %t1807 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1806, ptr %t1807
  br label %reuse.join.1805
reuse.copy.1804:
  %t1808 = call ptr @__alloc(i64 24, i32 2)
  %t1809 = inttoptr i64 74 to ptr
  %t1810 = getelementptr ptr, ptr %t1808, i32 0
  store ptr %t1809, ptr %t1810
  call void @__inc_ref(ptr %t1797)
  %t1811 = getelementptr ptr, ptr %t1808, i32 1
  store ptr %t1797, ptr %t1811
  call void @__inc_ref(ptr %t1799)
  %t1812 = getelementptr ptr, ptr %t1808, i32 2
  store ptr %t1799, ptr %t1812
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1805
reuse.join.1805:
  %t1813 = phi ptr [ %t5, %reuse.in_place.1803 ], [ %t1808, %reuse.copy.1804 ]
  %t1814 = call ptr @__alloc(i64 16, i32 1)
  %t1815 = inttoptr i64 191 to ptr
  %t1816 = getelementptr ptr, ptr %t1814, i32 0
  store ptr %t1815, ptr %t1816
  call void @__inc_ref(ptr %t6)
  %t1817 = getelementptr ptr, ptr %t1814, i32 1
  store ptr %t6, ptr %t1817
  call void @__free_recursive(ptr %t6)
  store ptr %t1813, ptr %t3
  store ptr %t1814, ptr %t4
  br label %tco.loop.0
tco.case.arm.116.1818:
  %t1819 = getelementptr ptr, ptr %t5, i32 1
  %t1820 = load ptr, ptr %t1819
  %t1821 = getelementptr ptr, ptr %t5, i32 2
  %t1822 = load ptr, ptr %t1821
  %t1823 = getelementptr i8, ptr %t5, i64 -8
  %t1824 = load i32, ptr %t1823
  %t1825 = icmp eq i32 %t1824, 1
  br i1 %t1825, label %reuse.in_place.1826, label %reuse.copy.1827
reuse.in_place.1826:
  %t1829 = inttoptr i64 74 to ptr
  %t1830 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1829, ptr %t1830
  br label %reuse.join.1828
reuse.copy.1827:
  %t1831 = call ptr @__alloc(i64 24, i32 2)
  %t1832 = inttoptr i64 74 to ptr
  %t1833 = getelementptr ptr, ptr %t1831, i32 0
  store ptr %t1832, ptr %t1833
  call void @__inc_ref(ptr %t1820)
  %t1834 = getelementptr ptr, ptr %t1831, i32 1
  store ptr %t1820, ptr %t1834
  call void @__inc_ref(ptr %t1822)
  %t1835 = getelementptr ptr, ptr %t1831, i32 2
  store ptr %t1822, ptr %t1835
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1828
reuse.join.1828:
  %t1836 = phi ptr [ %t5, %reuse.in_place.1826 ], [ %t1831, %reuse.copy.1827 ]
  %t1837 = call ptr @__alloc(i64 16, i32 1)
  %t1838 = inttoptr i64 192 to ptr
  %t1839 = getelementptr ptr, ptr %t1837, i32 0
  store ptr %t1838, ptr %t1839
  call void @__inc_ref(ptr %t6)
  %t1840 = getelementptr ptr, ptr %t1837, i32 1
  store ptr %t6, ptr %t1840
  call void @__free_recursive(ptr %t6)
  store ptr %t1836, ptr %t3
  store ptr %t1837, ptr %t4
  br label %tco.loop.0
tco.case.arm.117.1841:
  %t1842 = getelementptr ptr, ptr %t5, i32 1
  %t1843 = load ptr, ptr %t1842
  %t1844 = getelementptr ptr, ptr %t5, i32 2
  %t1845 = load ptr, ptr %t1844
  %t1846 = getelementptr i8, ptr %t5, i64 -8
  %t1847 = load i32, ptr %t1846
  %t1848 = icmp eq i32 %t1847, 1
  br i1 %t1848, label %reuse.in_place.1849, label %reuse.copy.1850
reuse.in_place.1849:
  %t1852 = inttoptr i64 74 to ptr
  %t1853 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1852, ptr %t1853
  br label %reuse.join.1851
reuse.copy.1850:
  %t1854 = call ptr @__alloc(i64 24, i32 2)
  %t1855 = inttoptr i64 74 to ptr
  %t1856 = getelementptr ptr, ptr %t1854, i32 0
  store ptr %t1855, ptr %t1856
  call void @__inc_ref(ptr %t1843)
  %t1857 = getelementptr ptr, ptr %t1854, i32 1
  store ptr %t1843, ptr %t1857
  call void @__inc_ref(ptr %t1845)
  %t1858 = getelementptr ptr, ptr %t1854, i32 2
  store ptr %t1845, ptr %t1858
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1851
reuse.join.1851:
  %t1859 = phi ptr [ %t5, %reuse.in_place.1849 ], [ %t1854, %reuse.copy.1850 ]
  %t1860 = call ptr @__alloc(i64 16, i32 1)
  %t1861 = inttoptr i64 193 to ptr
  %t1862 = getelementptr ptr, ptr %t1860, i32 0
  store ptr %t1861, ptr %t1862
  call void @__inc_ref(ptr %t6)
  %t1863 = getelementptr ptr, ptr %t1860, i32 1
  store ptr %t6, ptr %t1863
  call void @__free_recursive(ptr %t6)
  store ptr %t1859, ptr %t3
  store ptr %t1860, ptr %t4
  br label %tco.loop.0
tco.case.arm.118.1864:
  %t1865 = getelementptr ptr, ptr %t5, i32 1
  %t1866 = load ptr, ptr %t1865
  %t1867 = getelementptr ptr, ptr %t5, i32 2
  %t1868 = load ptr, ptr %t1867
  %t1869 = getelementptr i8, ptr %t5, i64 -8
  %t1870 = load i32, ptr %t1869
  %t1871 = icmp eq i32 %t1870, 1
  br i1 %t1871, label %reuse.in_place.1872, label %reuse.copy.1873
reuse.in_place.1872:
  %t1875 = inttoptr i64 74 to ptr
  %t1876 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1875, ptr %t1876
  br label %reuse.join.1874
reuse.copy.1873:
  %t1877 = call ptr @__alloc(i64 24, i32 2)
  %t1878 = inttoptr i64 74 to ptr
  %t1879 = getelementptr ptr, ptr %t1877, i32 0
  store ptr %t1878, ptr %t1879
  call void @__inc_ref(ptr %t1866)
  %t1880 = getelementptr ptr, ptr %t1877, i32 1
  store ptr %t1866, ptr %t1880
  call void @__inc_ref(ptr %t1868)
  %t1881 = getelementptr ptr, ptr %t1877, i32 2
  store ptr %t1868, ptr %t1881
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1874
reuse.join.1874:
  %t1882 = phi ptr [ %t5, %reuse.in_place.1872 ], [ %t1877, %reuse.copy.1873 ]
  %t1883 = call ptr @__alloc(i64 16, i32 1)
  %t1884 = inttoptr i64 194 to ptr
  %t1885 = getelementptr ptr, ptr %t1883, i32 0
  store ptr %t1884, ptr %t1885
  call void @__inc_ref(ptr %t6)
  %t1886 = getelementptr ptr, ptr %t1883, i32 1
  store ptr %t6, ptr %t1886
  call void @__free_recursive(ptr %t6)
  store ptr %t1882, ptr %t3
  store ptr %t1883, ptr %t4
  br label %tco.loop.0
tco.case.arm.119.1887:
  %t1888 = getelementptr ptr, ptr %t5, i32 1
  %t1889 = load ptr, ptr %t1888
  %t1890 = getelementptr ptr, ptr %t5, i32 2
  %t1891 = load ptr, ptr %t1890
  %t1892 = getelementptr i8, ptr %t5, i64 -8
  %t1893 = load i32, ptr %t1892
  %t1894 = icmp eq i32 %t1893, 1
  br i1 %t1894, label %reuse.in_place.1895, label %reuse.copy.1896
reuse.in_place.1895:
  %t1898 = inttoptr i64 74 to ptr
  %t1899 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1898, ptr %t1899
  br label %reuse.join.1897
reuse.copy.1896:
  %t1900 = call ptr @__alloc(i64 24, i32 2)
  %t1901 = inttoptr i64 74 to ptr
  %t1902 = getelementptr ptr, ptr %t1900, i32 0
  store ptr %t1901, ptr %t1902
  call void @__inc_ref(ptr %t1889)
  %t1903 = getelementptr ptr, ptr %t1900, i32 1
  store ptr %t1889, ptr %t1903
  call void @__inc_ref(ptr %t1891)
  %t1904 = getelementptr ptr, ptr %t1900, i32 2
  store ptr %t1891, ptr %t1904
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1897
reuse.join.1897:
  %t1905 = phi ptr [ %t5, %reuse.in_place.1895 ], [ %t1900, %reuse.copy.1896 ]
  %t1906 = call ptr @__alloc(i64 16, i32 1)
  %t1907 = inttoptr i64 195 to ptr
  %t1908 = getelementptr ptr, ptr %t1906, i32 0
  store ptr %t1907, ptr %t1908
  call void @__inc_ref(ptr %t6)
  %t1909 = getelementptr ptr, ptr %t1906, i32 1
  store ptr %t6, ptr %t1909
  call void @__free_recursive(ptr %t6)
  store ptr %t1905, ptr %t3
  store ptr %t1906, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t1910 = load ptr, ptr %t2
  ret ptr %t1910
}

define internal ptr @v__apply1(ptr %v__cl, ptr %v__arg0) {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 74 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  call void @__inc_ref(ptr %v__cl)
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v__cl, ptr %t3
  call void @__inc_ref(ptr %v__arg0)
  %t4 = getelementptr ptr, ptr %t0, i32 2
  store ptr %v__arg0, ptr %t4
  %t5 = call ptr @v__scc__apply1__df__lam_0_33__df__lam_0_37__df__lam_0_41__df__lam_0_45__df__lam_0_49__df__lam_0_53__df__lam_0_57__df__lam_1_34__df__lam_1_38__df__lam_1_42__df__lam_1_46__df__lam_1_50__df__lam_1_54__df__lam_1_58__df__lam_10_14__df__lam_10_26__df__lam_11_15__df__lam_11_27__df__lam_2_35__df__lam_2_39__df__lam_2_43__df__lam_2_47__df__lam_2_51__df__lam_2_55__df__lam_2_59__df__lam_20_17__df__lam_21_18__df__lam_22_19__df__lam_23_29__df__lam_24_30__df__lam_25_31__df__lam_3_21__df__lam_4_22__df__lam_5_23__df__lam_6_1__df__lam_6_5__df__lam_6_9__df__lam_7_10__df__lam_7_2__df__lam_7_6__df__lam_8_11__df__lam_8_3__df__lam_8_7__df__lam_9_13__df__lam_9_25(ptr %t0)
  call void @__free_recursive(ptr %v__cl)
  call void @__free_recursive(ptr %v__arg0)
  ret ptr %t5
}

declare i32 @_setmode(i32, i32)
declare ptr @GetCommandLineW()
declare ptr @CommandLineToArgvW(ptr, ptr)
declare i32 @WideCharToMultiByte(i32, i32, ptr, i32, ptr, i32, ptr, ptr)

define i32 @main(i32 %argc_posix, ptr %argv_posix) {
entry:
  call i32 @_setmode(i32 1, i32 32768)
  call i32 @_setmode(i32 0, i32 32768)
  %cmdline = call ptr @GetCommandLineW()
  %argc_slot = alloca i32
  %argv_w = call ptr @CommandLineToArgvW(ptr %cmdline, ptr %argc_slot)
  %argc_w = load i32, ptr %argc_slot
  %argc_w64 = sext i32 %argc_w to i64
  store i64 %argc_w64, ptr @.cli_argc
  %arr_bytes = mul i64 %argc_w64, 8
  %u8arr = call ptr @__alloc(i64 %arr_bytes, i32 0)
  store ptr %u8arr, ptr @.cli_argv
  store ptr getelementptr inbounds (i8, ptr @.empty, i64 12), ptr %u8arr
  %ci.slot = alloca i64
  store i64 1, ptr %ci.slot
  br label %conv_loop
conv_loop:
  %ci = load i64, ptr %ci.slot
  %conv_done = icmp sge i64 %ci, %argc_w64
  br i1 %conv_done, label %call_main, label %conv_body
conv_body:
  %argw_slot = getelementptr ptr, ptr %argv_w, i64 %ci
  %argw = load ptr, ptr %argw_slot
  %needed = call i32 @WideCharToMultiByte(i32 65001, i32 0, ptr %argw, i32 -1, ptr null, i32 0, ptr null, ptr null)
  %need_ok = icmp sgt i32 %needed, 0
  br i1 %need_ok, label %conv_do, label %conv_empty
conv_do:
  %needed64 = sext i32 %needed to i64
  %buf = call ptr @__alloc(i64 %needed64, i32 0)
  call i32 @WideCharToMultiByte(i32 65001, i32 0, ptr %argw, i32 -1, ptr %buf, i32 %needed, ptr null, ptr null)
  %dst_slot = getelementptr ptr, ptr %u8arr, i64 %ci
  store ptr %buf, ptr %dst_slot
  %ci.next = add i64 %ci, 1
  store i64 %ci.next, ptr %ci.slot
  br label %conv_loop
conv_empty:
  %dst_slot_e = getelementptr ptr, ptr %u8arr, i64 %ci
  store ptr getelementptr inbounds (i8, ptr @.empty, i64 12), ptr %dst_slot_e
  %ci.next_e = add i64 %ci, 1
  store i64 %ci.next_e, ptr %ci.slot
  br label %conv_loop
call_main:
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
