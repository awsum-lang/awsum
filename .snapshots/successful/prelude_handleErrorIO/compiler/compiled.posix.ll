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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"[R]" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"[!]" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"[X]" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"[Y]" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"ErrB" }
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"ErrC" }
@.str.6 = private unnamed_addr constant {i32, i32, i32, i32, i32, [7 x i8]} { i32 0, i32 0, i32 0, i32 7, i32 7, [7 x i8] c"recover" }
@.str.7 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"\0A" }
@.str.8 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"=" }
@.str.9 = private unnamed_addr constant {i32, i32, i32, i32, i32, [11 x i8]} { i32 0, i32 0, i32 0, i32 11, i32 11, [11 x i8] c"treeNoError" }
@.str.10 = private unnamed_addr constant {i32, i32, i32, i32, i32, [12 x i8]} { i32 0, i32 0, i32 0, i32 12, i32 12, [12 x i8] c"treePreserve" }
@.str.11 = private unnamed_addr constant {i32, i32, i32, i32, i32, [9 x i8]} { i32 0, i32 0, i32 0, i32 9, i32 9, [9 x i8] c"refailRow" }
@.str.12 = private unnamed_addr constant {i32, i32, i32, i32, i32, [12 x i8]} { i32 0, i32 0, i32 0, i32 12, i32 12, [12 x i8] c"refailNarrow" }
@.str.13 = private unnamed_addr constant {i32, i32, i32, i32, i32, [6 x i8]} { i32 0, i32 0, i32 0, i32 6, i32 6, [6 x i8] c"nested" }
@.str.14 = private unnamed_addr constant {i32, i32, i32, i32, i32, [11 x i8]} { i32 0, i32 0, i32 0, i32 11, i32 11, [11 x i8] c"passthrough" }
@.str.15 = private unnamed_addr constant {i32, i32, i32, i32, i32, [9 x i8]} { i32 0, i32 0, i32 0, i32 9, i32 9, [9 x i8] c"dispatchB" }
@.str.16 = private unnamed_addr constant {i32, i32, i32, i32, i32, [9 x i8]} { i32 0, i32 0, i32 0, i32 9, i32 9, [9 x i8] c"dispatchA" }

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

define internal ptr @v_recoverH(ptr %v__e) {
  %t0 = call ptr @__alloc(i64 4, i32 0)
  store i32 11, ptr %t0
  %t1 = call ptr @v_pureIO(ptr %t0)
  call void @__free_recursive(ptr %v__e)
  ret ptr %t1
}

define internal ptr @v_dispatchH(ptr %v_e) {
  %t0 = getelementptr ptr, ptr %v_e, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 2252990199, label %case.arm.2252990199.4 i64 2269767818, label %case.arm.2269767818.9 ]
case.arm.2252990199.4:
  %t5 = getelementptr ptr, ptr %v_e, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = call ptr @__alloc(i64 4, i32 0)
  store i32 21, ptr %t7
  %t8 = call ptr @v_pureIO(ptr %t7)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_e)
  ret ptr %t8
case.arm.2269767818.9:
  %t10 = getelementptr ptr, ptr %v_e, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  %t12 = call ptr @__alloc(i64 4, i32 0)
  store i32 22, ptr %t12
  %t13 = call ptr @v_pureIO(ptr %t12)
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %v_e)
  ret ptr %t13
case.default.3:
  unreachable
}

define internal ptr @v_refailNarrowH(ptr %v__e) {
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 25 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_failIO(ptr %t0)
  call void @__free_recursive(ptr %v__e)
  ret ptr %t3
}

define internal ptr @v_reFailC() {
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 26 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_failIO(ptr %t0)
  %t4 = call ptr @v__lift_18(ptr %t3)
  ret ptr %t4
}

define internal ptr @v_refailRowH(ptr %v__e) {
  %t0 = call ptr @v_reFailC()
  call void @__free_recursive(ptr %v__e)
  ret ptr %t0
}

define internal ptr @v_nestedRecoverH(ptr %v__e) {
  %t0 = call ptr @__alloc(i64 4, i32 0)
  store i32 55, ptr %t0
  %t1 = call ptr @v_pureIO(ptr %t0)
  call void @__free_recursive(ptr %v__e)
  ret ptr %t1
}

define internal ptr @v_treePreserveH(ptr %v__e) {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 7 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t3
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
  call void @__free_recursive(ptr %v__e)
  ret ptr %t0
}

define internal ptr @v_treeNoErrorH(ptr %v__e) {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 7 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t3
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
  call void @__free_recursive(ptr %v__e)
  ret ptr %t0
}

define internal ptr @v_inErrA() {
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 24 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_failIO(ptr %t0)
  %t4 = call ptr @v__lift_22(ptr %t3)
  ret ptr %t4
}

define internal ptr @v_inErrB() {
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 25 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_failIO(ptr %t0)
  %t4 = call ptr @v__lift_26(ptr %t3)
  ret ptr %t4
}

define internal ptr @v_recover() {
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 24 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_failIO(ptr %t0)
  %t4 = call ptr @v__df_handleErrorIO_0(ptr %t3)
  ret ptr %t4
}

define internal ptr @v_dispatchA() {
  %t0 = call ptr @v_inErrA()
  %t1 = call ptr @v__df_handleErrorIO_4(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_dispatchB() {
  %t0 = call ptr @v_inErrB()
  %t1 = call ptr @v__df_handleErrorIO_4(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_passthrough() {
  %t0 = call ptr @__alloc(i64 4, i32 0)
  store i32 33, ptr %t0
  %t1 = call ptr @v_pureIO(ptr %t0)
  %t2 = call ptr @v__df_handleErrorIO_0(ptr %t1)
  ret ptr %t2
}

define internal ptr @v_nested() {
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 24 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_failIO(ptr %t0)
  %t4 = call ptr @v__df_handleErrorIO_12(ptr %t3)
  %t5 = call ptr @v__df_handleErrorIO_8(ptr %t4)
  ret ptr %t5
}

define internal ptr @v_refailNarrow() {
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 24 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_failIO(ptr %t0)
  %t4 = call ptr @v__df_handleErrorIO_12(ptr %t3)
  ret ptr %t4
}

define internal ptr @v_refailRow() {
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 24 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_failIO(ptr %t0)
  %t4 = call ptr @v__df_handleErrorIO_16(ptr %t3)
  ret ptr %t4
}

define internal ptr @v_treePreserve() {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 7 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t3
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
  %t12 = call ptr @v__df_andThenIO_24(ptr %t0)
  %t13 = call ptr @v__df_handleErrorIO_20(ptr %t12)
  ret ptr %t13
}

define internal ptr @v_treeNoError() {
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
  %t12 = call ptr @v__df_handleErrorIO_28(ptr %t0)
  ret ptr %t12
}

define internal ptr @v_observeNever(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @v__df_mapIO_36(ptr %v_io)
  %t1 = call ptr @v__df_andThenIO_32(ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t1
}

define internal ptr @v_handlerB(ptr %v_e) {
  %t0 = getelementptr ptr, ptr %v_e, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 25, label %case.arm.25.4 ]
case.arm.25.4:
  %t5 = call ptr @__alloc(i64 24, i32 2)
  %t6 = inttoptr i64 7 to ptr
  %t7 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t6, ptr %t7
  %t8 = getelementptr ptr, ptr %t5, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t8
  %t9 = call ptr @__alloc(i64 16, i32 1)
  %t10 = inttoptr i64 5 to ptr
  %t11 = getelementptr ptr, ptr %t9, i32 0
  store ptr %t10, ptr %t11
  %t12 = call ptr @__alloc(i64 8, i32 0)
  %t13 = inttoptr i64 0 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t9, i32 1
  store ptr %t12, ptr %t15
  %t16 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t9, ptr %t16
  call void @__free_recursive(ptr %v_e)
  ret ptr %t5
case.default.3:
  unreachable
}

define internal ptr @v_observeB(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @v__df_mapIO_36(ptr %v_io)
  %t1 = call ptr @v__df_andThenIO_32(ptr %t0)
  %t2 = call ptr @v__df_handleErrorIO_40(ptr %t1)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t2
}

define internal ptr @v_handlerBC(ptr %v_e) {
  %t0 = getelementptr ptr, ptr %v_e, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 2269767818, label %case.arm.2269767818.4 i64 2286545437, label %case.arm.2286545437.19 ]
case.arm.2269767818.4:
  %t5 = getelementptr ptr, ptr %v_e, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = call ptr @__alloc(i64 24, i32 2)
  %t8 = inttoptr i64 7 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = getelementptr ptr, ptr %t7, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t10
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
case.arm.2286545437.19:
  %t20 = getelementptr ptr, ptr %v_e, i32 1
  %t21 = load ptr, ptr %t20
  call void @__inc_ref(ptr %t21)
  %t22 = call ptr @__alloc(i64 24, i32 2)
  %t23 = inttoptr i64 7 to ptr
  %t24 = getelementptr ptr, ptr %t22, i32 0
  store ptr %t23, ptr %t24
  %t25 = getelementptr ptr, ptr %t22, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.5, i64 12), ptr %t25
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

define internal ptr @v_observeBC(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @v__df_mapIO_36(ptr %v_io)
  %t1 = call ptr @v__df__rowmono_0_andThenIO_48(ptr %t0)
  %t2 = call ptr @v__df_handleErrorIO_44(ptr %t1)
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
  %t12 = call ptr @v__df_andThenIO_60(ptr %t0)
  call void @__inc_ref(ptr %v_act)
  %t13 = call ptr @v__df_andThenIO_56(ptr %t12, ptr %v_act)
  %t14 = call ptr @v__df_andThenIO_52(ptr %t13)
  call void @__free_recursive(ptr %v_label)
  call void @__free_recursive(ptr %v_act)
  ret ptr %t14
}

define internal ptr @v_main() {
  %t0 = call ptr @v_recover()
  %t1 = call ptr @v_observeNever(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.6, i64 12), ptr %t1)
  %t3 = call ptr @v__df_andThenIO_92(ptr %t2)
  %t4 = call ptr @v__df_andThenIO_88(ptr %t3)
  %t5 = call ptr @v__df_andThenIO_84(ptr %t4)
  %t6 = call ptr @v__df_andThenIO_80(ptr %t5)
  %t7 = call ptr @v__df_andThenIO_76(ptr %t6)
  %t8 = call ptr @v__df_andThenIO_72(ptr %t7)
  %t9 = call ptr @v__df_andThenIO_68(ptr %t8)
  %t10 = call ptr @v__df_andThenIO_64(ptr %t9)
  ret ptr %t10
}

define internal ptr @v__lift_1(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 202 to ptr
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
  %t42 = inttoptr i64 203 to ptr
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
  %t45 = inttoptr i64 203 to ptr
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
  %t57 = inttoptr i64 100 to ptr
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
  %t69 = inttoptr i64 109 to ptr
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
  %t81 = inttoptr i64 110 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 202, label %tco.case.arm.202.11 i64 203, label %tco.case.arm.203.12 ]
tco.case.arm.202.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.203.12:
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

define internal ptr @v__lift_18(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 204 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__lift_18(ptr %v___input, ptr %t0)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t3
}

define internal ptr @v__cps__lift_18(ptr %v___input, ptr %v__k) {
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
  %t18 = call ptr @v__apply__lift_18(ptr %t6, ptr %t14)
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
  %t26 = inttoptr i64 2286545437 to ptr
  %t27 = getelementptr ptr, ptr %t25, i32 0
  store ptr %t26, ptr %t27
  call void @__inc_ref(ptr %t21)
  %t28 = getelementptr ptr, ptr %t25, i32 1
  store ptr %t21, ptr %t28
  %t29 = getelementptr ptr, ptr %t22, i32 1
  store ptr %t25, ptr %t29
  %t30 = call ptr @v__apply__lift_18(ptr %t6, ptr %t22)
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
  %t46 = inttoptr i64 205 to ptr
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
  %t49 = inttoptr i64 205 to ptr
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
  %t61 = inttoptr i64 99 to ptr
  %t62 = getelementptr ptr, ptr %t60, i32 0
  store ptr %t61, ptr %t62
  call void @__inc_ref(ptr %t56)
  %t63 = getelementptr ptr, ptr %t60, i32 1
  store ptr %t56, ptr %t63
  %t64 = getelementptr ptr, ptr %t57, i32 1
  store ptr %t60, ptr %t64
  %t65 = call ptr @v__apply__lift_18(ptr %t6, ptr %t57)
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
  %t73 = inttoptr i64 101 to ptr
  %t74 = getelementptr ptr, ptr %t72, i32 0
  store ptr %t73, ptr %t74
  call void @__inc_ref(ptr %t68)
  %t75 = getelementptr ptr, ptr %t72, i32 1
  store ptr %t68, ptr %t75
  %t76 = getelementptr ptr, ptr %t69, i32 1
  store ptr %t72, ptr %t76
  %t77 = call ptr @v__apply__lift_18(ptr %t6, ptr %t69)
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
  %t85 = inttoptr i64 102 to ptr
  %t86 = getelementptr ptr, ptr %t84, i32 0
  store ptr %t85, ptr %t86
  call void @__inc_ref(ptr %t80)
  %t87 = getelementptr ptr, ptr %t84, i32 1
  store ptr %t80, ptr %t87
  %t88 = getelementptr ptr, ptr %t81, i32 1
  store ptr %t84, ptr %t88
  %t89 = call ptr @v__apply__lift_18(ptr %t6, ptr %t81)
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

define internal ptr @v__apply__lift_18(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 204, label %tco.case.arm.204.11 i64 205, label %tco.case.arm.205.12 ]
tco.case.arm.204.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.205.12:
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

define internal ptr @v__lift_22(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 206 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__lift_22(ptr %v___input, ptr %t0)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t3
}

define internal ptr @v__cps__lift_22(ptr %v___input, ptr %v__k) {
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
  %t18 = call ptr @v__apply__lift_22(ptr %t6, ptr %t14)
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
  %t26 = inttoptr i64 2252990199 to ptr
  %t27 = getelementptr ptr, ptr %t25, i32 0
  store ptr %t26, ptr %t27
  call void @__inc_ref(ptr %t21)
  %t28 = getelementptr ptr, ptr %t25, i32 1
  store ptr %t21, ptr %t28
  %t29 = getelementptr ptr, ptr %t22, i32 1
  store ptr %t25, ptr %t29
  %t30 = call ptr @v__apply__lift_22(ptr %t6, ptr %t22)
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
  %t46 = inttoptr i64 207 to ptr
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
  %t49 = inttoptr i64 207 to ptr
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
  %t61 = inttoptr i64 103 to ptr
  %t62 = getelementptr ptr, ptr %t60, i32 0
  store ptr %t61, ptr %t62
  call void @__inc_ref(ptr %t56)
  %t63 = getelementptr ptr, ptr %t60, i32 1
  store ptr %t56, ptr %t63
  %t64 = getelementptr ptr, ptr %t57, i32 1
  store ptr %t60, ptr %t64
  %t65 = call ptr @v__apply__lift_22(ptr %t6, ptr %t57)
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
  %t73 = inttoptr i64 104 to ptr
  %t74 = getelementptr ptr, ptr %t72, i32 0
  store ptr %t73, ptr %t74
  call void @__inc_ref(ptr %t68)
  %t75 = getelementptr ptr, ptr %t72, i32 1
  store ptr %t68, ptr %t75
  %t76 = getelementptr ptr, ptr %t69, i32 1
  store ptr %t72, ptr %t76
  %t77 = call ptr @v__apply__lift_22(ptr %t6, ptr %t69)
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
  %t85 = inttoptr i64 105 to ptr
  %t86 = getelementptr ptr, ptr %t84, i32 0
  store ptr %t85, ptr %t86
  call void @__inc_ref(ptr %t80)
  %t87 = getelementptr ptr, ptr %t84, i32 1
  store ptr %t80, ptr %t87
  %t88 = getelementptr ptr, ptr %t81, i32 1
  store ptr %t84, ptr %t88
  %t89 = call ptr @v__apply__lift_22(ptr %t6, ptr %t81)
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

define internal ptr @v__apply__lift_22(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 206, label %tco.case.arm.206.11 i64 207, label %tco.case.arm.207.12 ]
tco.case.arm.206.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.207.12:
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

define internal ptr @v__lift_26(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 208 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__lift_26(ptr %v___input, ptr %t0)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t3
}

define internal ptr @v__cps__lift_26(ptr %v___input, ptr %v__k) {
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
  %t18 = call ptr @v__apply__lift_26(ptr %t6, ptr %t14)
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
  %t26 = inttoptr i64 2269767818 to ptr
  %t27 = getelementptr ptr, ptr %t25, i32 0
  store ptr %t26, ptr %t27
  call void @__inc_ref(ptr %t21)
  %t28 = getelementptr ptr, ptr %t25, i32 1
  store ptr %t21, ptr %t28
  %t29 = getelementptr ptr, ptr %t22, i32 1
  store ptr %t25, ptr %t29
  %t30 = call ptr @v__apply__lift_26(ptr %t6, ptr %t22)
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
  %t46 = inttoptr i64 209 to ptr
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
  %t49 = inttoptr i64 209 to ptr
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
  %t61 = inttoptr i64 106 to ptr
  %t62 = getelementptr ptr, ptr %t60, i32 0
  store ptr %t61, ptr %t62
  call void @__inc_ref(ptr %t56)
  %t63 = getelementptr ptr, ptr %t60, i32 1
  store ptr %t56, ptr %t63
  %t64 = getelementptr ptr, ptr %t57, i32 1
  store ptr %t60, ptr %t64
  %t65 = call ptr @v__apply__lift_26(ptr %t6, ptr %t57)
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
  %t73 = inttoptr i64 107 to ptr
  %t74 = getelementptr ptr, ptr %t72, i32 0
  store ptr %t73, ptr %t74
  call void @__inc_ref(ptr %t68)
  %t75 = getelementptr ptr, ptr %t72, i32 1
  store ptr %t68, ptr %t75
  %t76 = getelementptr ptr, ptr %t69, i32 1
  store ptr %t72, ptr %t76
  %t77 = call ptr @v__apply__lift_26(ptr %t6, ptr %t69)
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
  %t85 = inttoptr i64 108 to ptr
  %t86 = getelementptr ptr, ptr %t84, i32 0
  store ptr %t85, ptr %t86
  call void @__inc_ref(ptr %t80)
  %t87 = getelementptr ptr, ptr %t84, i32 1
  store ptr %t80, ptr %t87
  %t88 = getelementptr ptr, ptr %t81, i32 1
  store ptr %t84, ptr %t88
  %t89 = call ptr @v__apply__lift_26(ptr %t6, ptr %t81)
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

define internal ptr @v__apply__lift_26(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 208, label %tco.case.arm.208.11 i64 209, label %tco.case.arm.209.12 ]
tco.case.arm.208.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.209.12:
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

define internal ptr @v__lam_30(ptr %v__u) {
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 24 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_failIO(ptr %t0)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t3
}

define internal ptr @v__lam_31(ptr %v__u) {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 7 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.7, i64 12), ptr %t3
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

define internal ptr @v__lam_32(ptr %v_act, ptr %v__u) {
  call void @__free_recursive(ptr %v__u)
  ret ptr %v_act
}

define internal ptr @v__lam_33(ptr %v__u) {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 7 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.8, i64 12), ptr %t3
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

define internal ptr @v__lam_34(ptr %v__u) {
  %t0 = call ptr @v_treeNoError()
  %t1 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.9, i64 12), ptr %t0)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t1
}

define internal ptr @v__lam_35(ptr %v__u) {
  %t0 = call ptr @v_treePreserve()
  %t1 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.10, i64 12), ptr %t0)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t1
}

define internal ptr @v__lam_36(ptr %v__u) {
  %t0 = call ptr @v_refailRow()
  %t1 = call ptr @v_observeBC(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.11, i64 12), ptr %t1)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t2
}

define internal ptr @v__lam_37(ptr %v__u) {
  %t0 = call ptr @v_refailNarrow()
  %t1 = call ptr @v_observeB(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.12, i64 12), ptr %t1)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t2
}

define internal ptr @v__lam_38(ptr %v__u) {
  %t0 = call ptr @v_nested()
  %t1 = call ptr @v_observeNever(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.13, i64 12), ptr %t1)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t2
}

define internal ptr @v__lam_39(ptr %v__u) {
  %t0 = call ptr @v_passthrough()
  %t1 = call ptr @v_observeNever(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.14, i64 12), ptr %t1)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t2
}

define internal ptr @v__lam_40(ptr %v__u) {
  %t0 = call ptr @v_dispatchB()
  %t1 = call ptr @v_observeNever(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.15, i64 12), ptr %t1)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t2
}

define internal ptr @v__lam_41(ptr %v__u) {
  %t0 = call ptr @v_dispatchA()
  %t1 = call ptr @v_observeNever(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.16, i64 12), ptr %t1)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t2
}

define internal ptr @v__lift_42(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 210 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__lift_42(ptr %v___input, ptr %t0)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t3
}

define internal ptr @v__cps__lift_42(ptr %v___input, ptr %v__k) {
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
  %t18 = call ptr @v__apply__lift_42(ptr %t6, ptr %t14)
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
  %t26 = call ptr @v__apply__lift_42(ptr %t6, ptr %t22)
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
  %t42 = inttoptr i64 211 to ptr
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
  %t45 = inttoptr i64 211 to ptr
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
  %t57 = inttoptr i64 111 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  call void @__inc_ref(ptr %t52)
  %t59 = getelementptr ptr, ptr %t56, i32 1
  store ptr %t52, ptr %t59
  %t60 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t56, ptr %t60
  %t61 = call ptr @v__apply__lift_42(ptr %t6, ptr %t53)
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
  %t69 = inttoptr i64 112 to ptr
  %t70 = getelementptr ptr, ptr %t68, i32 0
  store ptr %t69, ptr %t70
  call void @__inc_ref(ptr %t64)
  %t71 = getelementptr ptr, ptr %t68, i32 1
  store ptr %t64, ptr %t71
  %t72 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t68, ptr %t72
  %t73 = call ptr @v__apply__lift_42(ptr %t6, ptr %t65)
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
  %t81 = inttoptr i64 113 to ptr
  %t82 = getelementptr ptr, ptr %t80, i32 0
  store ptr %t81, ptr %t82
  call void @__inc_ref(ptr %t76)
  %t83 = getelementptr ptr, ptr %t80, i32 1
  store ptr %t76, ptr %t83
  %t84 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t80, ptr %t84
  %t85 = call ptr @v__apply__lift_42(ptr %t6, ptr %t77)
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

define internal ptr @v__apply__lift_42(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 210, label %tco.case.arm.210.11 i64 211, label %tco.case.arm.211.12 ]
tco.case.arm.210.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.211.12:
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

define internal ptr @v__df_handleErrorIO_0(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 212 to ptr
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
  %t22 = call ptr @v_recoverH(ptr %t21)
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
  %t39 = inttoptr i64 213 to ptr
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
  %t42 = inttoptr i64 213 to ptr
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
  %t54 = inttoptr i64 28 to ptr
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
  %t66 = inttoptr i64 40 to ptr
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
  %t78 = inttoptr i64 50 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 212, label %tco.case.arm.212.11 i64 213, label %tco.case.arm.213.12 ]
tco.case.arm.212.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.213.12:
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

define internal ptr @v__df_handleErrorIO_4(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 214 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_handleErrorIO_4(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_handleErrorIO_4(ptr %v_io, ptr %v__k) {
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
  %t18 = call ptr @v__apply__df_handleErrorIO_4(ptr %t6, ptr %t14)
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
  %t22 = call ptr @v_dispatchH(ptr %t21)
  %t23 = call ptr @v__apply__df_handleErrorIO_4(ptr %t6, ptr %t22)
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
  %t39 = inttoptr i64 215 to ptr
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
  %t42 = inttoptr i64 215 to ptr
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
  %t58 = call ptr @v__apply__df_handleErrorIO_4(ptr %t6, ptr %t50)
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
  %t66 = inttoptr i64 45 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  call void @__inc_ref(ptr %t61)
  %t68 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t61, ptr %t68
  %t69 = getelementptr ptr, ptr %t62, i32 1
  store ptr %t65, ptr %t69
  %t70 = call ptr @v__apply__df_handleErrorIO_4(ptr %t6, ptr %t62)
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
  %t78 = inttoptr i64 54 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  call void @__inc_ref(ptr %t73)
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t73, ptr %t80
  %t81 = getelementptr ptr, ptr %t74, i32 1
  store ptr %t77, ptr %t81
  %t82 = call ptr @v__apply__df_handleErrorIO_4(ptr %t6, ptr %t74)
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

define internal ptr @v__apply__df_handleErrorIO_4(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 214, label %tco.case.arm.214.11 i64 215, label %tco.case.arm.215.12 ]
tco.case.arm.214.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.215.12:
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

define internal ptr @v__df_handleErrorIO_8(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 216 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_handleErrorIO_8(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_handleErrorIO_8(ptr %v_io, ptr %v__k) {
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
  %t18 = call ptr @v__apply__df_handleErrorIO_8(ptr %t6, ptr %t14)
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
  %t22 = call ptr @v_nestedRecoverH(ptr %t21)
  %t23 = call ptr @v__apply__df_handleErrorIO_8(ptr %t6, ptr %t22)
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
  %t39 = inttoptr i64 217 to ptr
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
  %t42 = inttoptr i64 217 to ptr
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
  %t54 = inttoptr i64 36 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  call void @__inc_ref(ptr %t49)
  %t56 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t49, ptr %t56
  %t57 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t53, ptr %t57
  %t58 = call ptr @v__apply__df_handleErrorIO_8(ptr %t6, ptr %t50)
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
  %t66 = inttoptr i64 37 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  call void @__inc_ref(ptr %t61)
  %t68 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t61, ptr %t68
  %t69 = getelementptr ptr, ptr %t62, i32 1
  store ptr %t65, ptr %t69
  %t70 = call ptr @v__apply__df_handleErrorIO_8(ptr %t6, ptr %t62)
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
  %t82 = call ptr @v__apply__df_handleErrorIO_8(ptr %t6, ptr %t74)
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

define internal ptr @v__apply__df_handleErrorIO_8(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 216, label %tco.case.arm.216.11 i64 217, label %tco.case.arm.217.12 ]
tco.case.arm.216.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.217.12:
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
  %t1 = inttoptr i64 218 to ptr
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
  %t22 = call ptr @v_refailNarrowH(ptr %t21)
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
  %t39 = inttoptr i64 219 to ptr
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
  %t42 = inttoptr i64 219 to ptr
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
  %t66 = inttoptr i64 38 to ptr
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
  %t78 = inttoptr i64 47 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 218, label %tco.case.arm.218.11 i64 219, label %tco.case.arm.219.12 ]
tco.case.arm.218.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.219.12:
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

define internal ptr @v__df_handleErrorIO_16(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 220 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_handleErrorIO_16(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_handleErrorIO_16(ptr %v_io, ptr %v__k) {
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
  %t18 = call ptr @v__apply__df_handleErrorIO_16(ptr %t6, ptr %t14)
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
  %t22 = call ptr @v_refailRowH(ptr %t21)
  %t23 = call ptr @v__apply__df_handleErrorIO_16(ptr %t6, ptr %t22)
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
  %t39 = inttoptr i64 221 to ptr
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
  %t42 = inttoptr i64 221 to ptr
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
  %t54 = inttoptr i64 30 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  call void @__inc_ref(ptr %t49)
  %t56 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t49, ptr %t56
  %t57 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t53, ptr %t57
  %t58 = call ptr @v__apply__df_handleErrorIO_16(ptr %t6, ptr %t50)
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
  %t70 = call ptr @v__apply__df_handleErrorIO_16(ptr %t6, ptr %t62)
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
  %t78 = inttoptr i64 48 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  call void @__inc_ref(ptr %t73)
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t73, ptr %t80
  %t81 = getelementptr ptr, ptr %t74, i32 1
  store ptr %t77, ptr %t81
  %t82 = call ptr @v__apply__df_handleErrorIO_16(ptr %t6, ptr %t74)
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

define internal ptr @v__apply__df_handleErrorIO_16(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 220, label %tco.case.arm.220.11 i64 221, label %tco.case.arm.221.12 ]
tco.case.arm.220.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.221.12:
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

define internal ptr @v__df_handleErrorIO_20(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 222 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_handleErrorIO_20(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_handleErrorIO_20(ptr %v_io, ptr %v__k) {
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
  %t18 = call ptr @v__apply__df_handleErrorIO_20(ptr %t6, ptr %t14)
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
  %t22 = call ptr @v_treePreserveH(ptr %t21)
  %t23 = call ptr @v__apply__df_handleErrorIO_20(ptr %t6, ptr %t22)
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
  %t39 = inttoptr i64 223 to ptr
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
  %t42 = inttoptr i64 223 to ptr
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
  %t58 = call ptr @v__apply__df_handleErrorIO_20(ptr %t6, ptr %t50)
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
  %t70 = call ptr @v__apply__df_handleErrorIO_20(ptr %t6, ptr %t62)
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
  %t82 = call ptr @v__apply__df_handleErrorIO_20(ptr %t6, ptr %t74)
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

define internal ptr @v__apply__df_handleErrorIO_20(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 222, label %tco.case.arm.222.11 i64 223, label %tco.case.arm.223.12 ]
tco.case.arm.222.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.223.12:
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

define internal ptr @v__df_andThenIO_24(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 224 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_24(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_24(ptr %v_io, ptr %v__k) {
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
  %t14 = call ptr @v__lam_30(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_24(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_24(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 225 to ptr
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
  %t43 = inttoptr i64 225 to ptr
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
  %t55 = inttoptr i64 58 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df_andThenIO_24(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 71 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df_andThenIO_24(ptr %t6, ptr %t63)
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
  %t79 = inttoptr i64 84 to ptr
  %t80 = getelementptr ptr, ptr %t78, i32 0
  store ptr %t79, ptr %t80
  call void @__inc_ref(ptr %t74)
  %t81 = getelementptr ptr, ptr %t78, i32 1
  store ptr %t74, ptr %t81
  %t82 = getelementptr ptr, ptr %t75, i32 1
  store ptr %t78, ptr %t82
  %t83 = call ptr @v__apply__df_andThenIO_24(ptr %t6, ptr %t75)
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

define internal ptr @v__apply__df_andThenIO_24(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 224, label %tco.case.arm.224.11 i64 225, label %tco.case.arm.225.12 ]
tco.case.arm.224.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.225.12:
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

define internal ptr @v__df_handleErrorIO_28(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 226 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_handleErrorIO_28(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_handleErrorIO_28(ptr %v_io, ptr %v__k) {
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
  %t18 = call ptr @v__apply__df_handleErrorIO_28(ptr %t6, ptr %t14)
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
  %t22 = call ptr @v_treeNoErrorH(ptr %t21)
  %t23 = call ptr @v__apply__df_handleErrorIO_28(ptr %t6, ptr %t22)
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
  %t39 = inttoptr i64 227 to ptr
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
  %t42 = inttoptr i64 227 to ptr
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
  %t58 = call ptr @v__apply__df_handleErrorIO_28(ptr %t6, ptr %t50)
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
  %t70 = call ptr @v__apply__df_handleErrorIO_28(ptr %t6, ptr %t62)
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
  %t82 = call ptr @v__apply__df_handleErrorIO_28(ptr %t6, ptr %t74)
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

define internal ptr @v__apply__df_handleErrorIO_28(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 226, label %tco.case.arm.226.11 i64 227, label %tco.case.arm.227.12 ]
tco.case.arm.226.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.227.12:
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
  %t1 = inttoptr i64 228 to ptr
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
  %t14 = call ptr @v__bi_IO_Stdout_print(ptr %t13)
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
  %t40 = inttoptr i64 229 to ptr
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
  %t43 = inttoptr i64 229 to ptr
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
  %t55 = inttoptr i64 59 to ptr
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
  %t67 = inttoptr i64 72 to ptr
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
  %t79 = inttoptr i64 85 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 228, label %tco.case.arm.228.11 i64 229, label %tco.case.arm.229.12 ]
tco.case.arm.228.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.229.12:
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

define internal ptr @v__df_mapIO_36(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 230 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_mapIO_36(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_mapIO_36(ptr %v_io, ptr %v__k) {
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
  %t19 = call ptr @v__apply__df_mapIO_36(ptr %t6, ptr %t14)
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
  %t27 = call ptr @v__apply__df_mapIO_36(ptr %t6, ptr %t23)
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
  %t43 = inttoptr i64 231 to ptr
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
  %t46 = inttoptr i64 231 to ptr
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
  %t58 = inttoptr i64 97 to ptr
  %t59 = getelementptr ptr, ptr %t57, i32 0
  store ptr %t58, ptr %t59
  call void @__inc_ref(ptr %t53)
  %t60 = getelementptr ptr, ptr %t57, i32 1
  store ptr %t53, ptr %t60
  %t61 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t57, ptr %t61
  %t62 = call ptr @v__apply__df_mapIO_36(ptr %t6, ptr %t54)
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
  %t70 = inttoptr i64 98 to ptr
  %t71 = getelementptr ptr, ptr %t69, i32 0
  store ptr %t70, ptr %t71
  call void @__inc_ref(ptr %t65)
  %t72 = getelementptr ptr, ptr %t69, i32 1
  store ptr %t65, ptr %t72
  %t73 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t69, ptr %t73
  %t74 = call ptr @v__apply__df_mapIO_36(ptr %t6, ptr %t66)
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
  %t82 = inttoptr i64 27 to ptr
  %t83 = getelementptr ptr, ptr %t81, i32 0
  store ptr %t82, ptr %t83
  call void @__inc_ref(ptr %t77)
  %t84 = getelementptr ptr, ptr %t81, i32 1
  store ptr %t77, ptr %t84
  %t85 = getelementptr ptr, ptr %t78, i32 1
  store ptr %t81, ptr %t85
  %t86 = call ptr @v__apply__df_mapIO_36(ptr %t6, ptr %t78)
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

define internal ptr @v__apply__df_mapIO_36(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 230, label %tco.case.arm.230.11 i64 231, label %tco.case.arm.231.12 ]
tco.case.arm.230.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.231.12:
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

define internal ptr @v__df_handleErrorIO_40(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 232 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_handleErrorIO_40(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_handleErrorIO_40(ptr %v_io, ptr %v__k) {
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
  %t18 = call ptr @v__apply__df_handleErrorIO_40(ptr %t6, ptr %t14)
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
  %t22 = call ptr @v_handlerB(ptr %t21)
  %t23 = call ptr @v__apply__df_handleErrorIO_40(ptr %t6, ptr %t22)
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
  %t39 = inttoptr i64 233 to ptr
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
  %t42 = inttoptr i64 233 to ptr
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
  %t58 = call ptr @v__apply__df_handleErrorIO_40(ptr %t6, ptr %t50)
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
  %t70 = call ptr @v__apply__df_handleErrorIO_40(ptr %t6, ptr %t62)
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
  %t82 = call ptr @v__apply__df_handleErrorIO_40(ptr %t6, ptr %t74)
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

define internal ptr @v__apply__df_handleErrorIO_40(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 232, label %tco.case.arm.232.11 i64 233, label %tco.case.arm.233.12 ]
tco.case.arm.232.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.233.12:
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

define internal ptr @v__df_handleErrorIO_44(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 234 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_handleErrorIO_44(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_handleErrorIO_44(ptr %v_io, ptr %v__k) {
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
  %t18 = call ptr @v__apply__df_handleErrorIO_44(ptr %t6, ptr %t14)
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
  %t22 = call ptr @v_handlerBC(ptr %t21)
  %t23 = call ptr @v__apply__df_handleErrorIO_44(ptr %t6, ptr %t22)
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
  %t39 = inttoptr i64 235 to ptr
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
  %t42 = inttoptr i64 235 to ptr
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
  %t58 = call ptr @v__apply__df_handleErrorIO_44(ptr %t6, ptr %t50)
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
  %t70 = call ptr @v__apply__df_handleErrorIO_44(ptr %t6, ptr %t62)
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
  %t82 = call ptr @v__apply__df_handleErrorIO_44(ptr %t6, ptr %t74)
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

define internal ptr @v__apply__df_handleErrorIO_44(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 234, label %tco.case.arm.234.11 i64 235, label %tco.case.arm.235.12 ]
tco.case.arm.234.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.235.12:
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

define internal ptr @v__df__rowmono_0_andThenIO_48(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 236 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df__rowmono_0_andThenIO_48(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df__rowmono_0_andThenIO_48(ptr %v_io, ptr %v__k) {
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
  %t15 = call ptr @v__lift_42(ptr %t14)
  %t16 = call ptr @v__apply__df__rowmono_0_andThenIO_48(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df__rowmono_0_andThenIO_48(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 237 to ptr
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
  %t43 = inttoptr i64 237 to ptr
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
  %t59 = call ptr @v__apply__df__rowmono_0_andThenIO_48(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 56 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df__rowmono_0_andThenIO_48(ptr %t6, ptr %t63)
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
  %t79 = inttoptr i64 57 to ptr
  %t80 = getelementptr ptr, ptr %t78, i32 0
  store ptr %t79, ptr %t80
  call void @__inc_ref(ptr %t74)
  %t81 = getelementptr ptr, ptr %t78, i32 1
  store ptr %t74, ptr %t81
  %t82 = getelementptr ptr, ptr %t75, i32 1
  store ptr %t78, ptr %t82
  %t83 = call ptr @v__apply__df__rowmono_0_andThenIO_48(ptr %t6, ptr %t75)
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

define internal ptr @v__apply__df__rowmono_0_andThenIO_48(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 236, label %tco.case.arm.236.11 i64 237, label %tco.case.arm.237.12 ]
tco.case.arm.236.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.237.12:
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
  %t1 = inttoptr i64 238 to ptr
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
  %t14 = call ptr @v__lam_31(ptr %t13)
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
  %t40 = inttoptr i64 239 to ptr
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
  %t43 = inttoptr i64 239 to ptr
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
  %t55 = inttoptr i64 60 to ptr
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
  %t67 = inttoptr i64 73 to ptr
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
  %t79 = inttoptr i64 86 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 238, label %tco.case.arm.238.11 i64 239, label %tco.case.arm.239.12 ]
tco.case.arm.238.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.239.12:
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

define internal ptr @v__df_andThenIO_56(ptr %v_io, ptr %v__df_andThenIO_56_cap0_0) {
  call void @__inc_ref(ptr %v_io)
  call void @__inc_ref(ptr %v__df_andThenIO_56_cap0_0)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 240 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_56(ptr %v_io, ptr %v__df_andThenIO_56_cap0_0, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  call void @__free_recursive(ptr %v__df_andThenIO_56_cap0_0)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_56(ptr %v_io, ptr %v__df_andThenIO_56_cap0_0, ptr %v__k) {
entry:
  %t3 = alloca ptr
  store ptr %v_io, ptr %t3
  %t4 = alloca ptr
  store ptr %v__df_andThenIO_56_cap0_0, ptr %t4
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
  %t16 = call ptr @v__lam_32(ptr %t7, ptr %t15)
  %t17 = call ptr @v__lift_1(ptr %t16)
  %t18 = call ptr @v__apply__df_andThenIO_56(ptr %t8, ptr %t17)
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
  %t26 = call ptr @v__apply__df_andThenIO_56(ptr %t8, ptr %t22)
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
  %t42 = inttoptr i64 241 to ptr
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
  %t45 = inttoptr i64 241 to ptr
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
  %t57 = inttoptr i64 61 to ptr
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
  %t62 = call ptr @v__apply__df_andThenIO_56(ptr %t8, ptr %t53)
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
  %t70 = inttoptr i64 74 to ptr
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
  %t75 = call ptr @v__apply__df_andThenIO_56(ptr %t8, ptr %t66)
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
  %t83 = inttoptr i64 87 to ptr
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
  %t88 = call ptr @v__apply__df_andThenIO_56(ptr %t8, ptr %t79)
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
  switch i64 %t9, label %tco.case.default.10 [ i64 240, label %tco.case.arm.240.11 i64 241, label %tco.case.arm.241.12 ]
tco.case.arm.240.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.241.12:
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

define internal ptr @v__df_andThenIO_60(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 242 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_60(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_60(ptr %v_io, ptr %v__k) {
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
  %t14 = call ptr @v__lam_33(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_60(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_60(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 243 to ptr
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
  %t43 = inttoptr i64 243 to ptr
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
  %t55 = inttoptr i64 62 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df_andThenIO_60(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 75 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df_andThenIO_60(ptr %t6, ptr %t63)
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
  %t79 = inttoptr i64 88 to ptr
  %t80 = getelementptr ptr, ptr %t78, i32 0
  store ptr %t79, ptr %t80
  call void @__inc_ref(ptr %t74)
  %t81 = getelementptr ptr, ptr %t78, i32 1
  store ptr %t74, ptr %t81
  %t82 = getelementptr ptr, ptr %t75, i32 1
  store ptr %t78, ptr %t82
  %t83 = call ptr @v__apply__df_andThenIO_60(ptr %t6, ptr %t75)
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

define internal ptr @v__apply__df_andThenIO_60(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 242, label %tco.case.arm.242.11 i64 243, label %tco.case.arm.243.12 ]
tco.case.arm.242.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.243.12:
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

define internal ptr @v__df_andThenIO_64(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 244 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_64(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_64(ptr %v_io, ptr %v__k) {
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
  %t14 = call ptr @v__lam_34(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_64(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_64(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 245 to ptr
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
  %t43 = inttoptr i64 245 to ptr
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
  %t55 = inttoptr i64 63 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df_andThenIO_64(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 76 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df_andThenIO_64(ptr %t6, ptr %t63)
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
  %t79 = inttoptr i64 89 to ptr
  %t80 = getelementptr ptr, ptr %t78, i32 0
  store ptr %t79, ptr %t80
  call void @__inc_ref(ptr %t74)
  %t81 = getelementptr ptr, ptr %t78, i32 1
  store ptr %t74, ptr %t81
  %t82 = getelementptr ptr, ptr %t75, i32 1
  store ptr %t78, ptr %t82
  %t83 = call ptr @v__apply__df_andThenIO_64(ptr %t6, ptr %t75)
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

define internal ptr @v__apply__df_andThenIO_64(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 244, label %tco.case.arm.244.11 i64 245, label %tco.case.arm.245.12 ]
tco.case.arm.244.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.245.12:
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

define internal ptr @v__df_andThenIO_68(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 246 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_68(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_68(ptr %v_io, ptr %v__k) {
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
  %t14 = call ptr @v__lam_35(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_68(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_68(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 247 to ptr
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
  %t43 = inttoptr i64 247 to ptr
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
  %t55 = inttoptr i64 64 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df_andThenIO_68(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 77 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df_andThenIO_68(ptr %t6, ptr %t63)
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
  %t79 = inttoptr i64 90 to ptr
  %t80 = getelementptr ptr, ptr %t78, i32 0
  store ptr %t79, ptr %t80
  call void @__inc_ref(ptr %t74)
  %t81 = getelementptr ptr, ptr %t78, i32 1
  store ptr %t74, ptr %t81
  %t82 = getelementptr ptr, ptr %t75, i32 1
  store ptr %t78, ptr %t82
  %t83 = call ptr @v__apply__df_andThenIO_68(ptr %t6, ptr %t75)
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

define internal ptr @v__apply__df_andThenIO_68(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 246, label %tco.case.arm.246.11 i64 247, label %tco.case.arm.247.12 ]
tco.case.arm.246.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.247.12:
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

define internal ptr @v__df_andThenIO_72(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 248 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_72(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_72(ptr %v_io, ptr %v__k) {
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
  %t14 = call ptr @v__lam_36(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_72(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_72(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 249 to ptr
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
  %t43 = inttoptr i64 249 to ptr
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
  %t55 = inttoptr i64 65 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df_andThenIO_72(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 78 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df_andThenIO_72(ptr %t6, ptr %t63)
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
  %t79 = inttoptr i64 91 to ptr
  %t80 = getelementptr ptr, ptr %t78, i32 0
  store ptr %t79, ptr %t80
  call void @__inc_ref(ptr %t74)
  %t81 = getelementptr ptr, ptr %t78, i32 1
  store ptr %t74, ptr %t81
  %t82 = getelementptr ptr, ptr %t75, i32 1
  store ptr %t78, ptr %t82
  %t83 = call ptr @v__apply__df_andThenIO_72(ptr %t6, ptr %t75)
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

define internal ptr @v__apply__df_andThenIO_72(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 248, label %tco.case.arm.248.11 i64 249, label %tco.case.arm.249.12 ]
tco.case.arm.248.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.249.12:
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

define internal ptr @v__df_andThenIO_76(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 250 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_76(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_76(ptr %v_io, ptr %v__k) {
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
  %t14 = call ptr @v__lam_37(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_76(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_76(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 251 to ptr
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
  %t43 = inttoptr i64 251 to ptr
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
  %t55 = inttoptr i64 66 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df_andThenIO_76(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 79 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df_andThenIO_76(ptr %t6, ptr %t63)
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
  %t79 = inttoptr i64 92 to ptr
  %t80 = getelementptr ptr, ptr %t78, i32 0
  store ptr %t79, ptr %t80
  call void @__inc_ref(ptr %t74)
  %t81 = getelementptr ptr, ptr %t78, i32 1
  store ptr %t74, ptr %t81
  %t82 = getelementptr ptr, ptr %t75, i32 1
  store ptr %t78, ptr %t82
  %t83 = call ptr @v__apply__df_andThenIO_76(ptr %t6, ptr %t75)
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

define internal ptr @v__apply__df_andThenIO_76(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 250, label %tco.case.arm.250.11 i64 251, label %tco.case.arm.251.12 ]
tco.case.arm.250.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.251.12:
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

define internal ptr @v__df_andThenIO_80(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 252 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_80(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_80(ptr %v_io, ptr %v__k) {
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
  %t14 = call ptr @v__lam_38(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_80(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_80(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 253 to ptr
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
  %t43 = inttoptr i64 253 to ptr
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
  %t55 = inttoptr i64 67 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df_andThenIO_80(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 80 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df_andThenIO_80(ptr %t6, ptr %t63)
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
  %t79 = inttoptr i64 93 to ptr
  %t80 = getelementptr ptr, ptr %t78, i32 0
  store ptr %t79, ptr %t80
  call void @__inc_ref(ptr %t74)
  %t81 = getelementptr ptr, ptr %t78, i32 1
  store ptr %t74, ptr %t81
  %t82 = getelementptr ptr, ptr %t75, i32 1
  store ptr %t78, ptr %t82
  %t83 = call ptr @v__apply__df_andThenIO_80(ptr %t6, ptr %t75)
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

define internal ptr @v__apply__df_andThenIO_80(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 252, label %tco.case.arm.252.11 i64 253, label %tco.case.arm.253.12 ]
tco.case.arm.252.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.253.12:
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

define internal ptr @v__df_andThenIO_84(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 254 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_84(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_84(ptr %v_io, ptr %v__k) {
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
  %t14 = call ptr @v__lam_39(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_84(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_84(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 255 to ptr
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
  %t43 = inttoptr i64 255 to ptr
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
  %t55 = inttoptr i64 68 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df_andThenIO_84(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 81 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df_andThenIO_84(ptr %t6, ptr %t63)
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
  %t79 = inttoptr i64 94 to ptr
  %t80 = getelementptr ptr, ptr %t78, i32 0
  store ptr %t79, ptr %t80
  call void @__inc_ref(ptr %t74)
  %t81 = getelementptr ptr, ptr %t78, i32 1
  store ptr %t74, ptr %t81
  %t82 = getelementptr ptr, ptr %t75, i32 1
  store ptr %t78, ptr %t82
  %t83 = call ptr @v__apply__df_andThenIO_84(ptr %t6, ptr %t75)
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

define internal ptr @v__apply__df_andThenIO_84(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 254, label %tco.case.arm.254.11 i64 255, label %tco.case.arm.255.12 ]
tco.case.arm.254.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.255.12:
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

define internal ptr @v__df_andThenIO_88(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 256 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_88(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_88(ptr %v_io, ptr %v__k) {
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
  %t14 = call ptr @v__lam_40(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_88(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_88(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 257 to ptr
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
  %t43 = inttoptr i64 257 to ptr
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
  %t55 = inttoptr i64 69 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df_andThenIO_88(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 82 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df_andThenIO_88(ptr %t6, ptr %t63)
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
  %t79 = inttoptr i64 95 to ptr
  %t80 = getelementptr ptr, ptr %t78, i32 0
  store ptr %t79, ptr %t80
  call void @__inc_ref(ptr %t74)
  %t81 = getelementptr ptr, ptr %t78, i32 1
  store ptr %t74, ptr %t81
  %t82 = getelementptr ptr, ptr %t75, i32 1
  store ptr %t78, ptr %t82
  %t83 = call ptr @v__apply__df_andThenIO_88(ptr %t6, ptr %t75)
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

define internal ptr @v__apply__df_andThenIO_88(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 256, label %tco.case.arm.256.11 i64 257, label %tco.case.arm.257.12 ]
tco.case.arm.256.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.257.12:
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

define internal ptr @v__df_andThenIO_92(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 258 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_92(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_92(ptr %v_io, ptr %v__k) {
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
  %t14 = call ptr @v__lam_41(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_92(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_92(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 259 to ptr
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
  %t43 = inttoptr i64 259 to ptr
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
  %t55 = inttoptr i64 70 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df_andThenIO_92(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 83 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df_andThenIO_92(ptr %t6, ptr %t63)
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
  %t79 = inttoptr i64 96 to ptr
  %t80 = getelementptr ptr, ptr %t78, i32 0
  store ptr %t79, ptr %t80
  call void @__inc_ref(ptr %t74)
  %t81 = getelementptr ptr, ptr %t78, i32 1
  store ptr %t74, ptr %t81
  %t82 = getelementptr ptr, ptr %t75, i32 1
  store ptr %t78, ptr %t82
  %t83 = call ptr @v__apply__df_andThenIO_92(ptr %t6, ptr %t75)
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

define internal ptr @v__apply__df_andThenIO_92(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 258, label %tco.case.arm.258.11 i64 259, label %tco.case.arm.259.12 ]
tco.case.arm.258.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.259.12:
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

define internal ptr @v__scc__apply1__df__lam_10_39__df__lam_14_1__df__lam_14_13__df__lam_14_17__df__lam_14_21__df__lam_14_29__df__lam_14_41__df__lam_14_45__df__lam_14_5__df__lam_14_9__df__lam_15_10__df__lam_15_14__df__lam_15_18__df__lam_15_2__df__lam_15_22__df__lam_15_30__df__lam_15_42__df__lam_15_46__df__lam_15_6__df__lam_16_11__df__lam_16_15__df__lam_16_19__df__lam_16_23__df__lam_16_3__df__lam_16_31__df__lam_16_43__df__lam_16_47__df__lam_16_7__df__lam_46_49__df__lam_47_50__df__lam_48_51__df__lam_5_25__df__lam_5_33__df__lam_5_53__df__lam_5_57__df__lam_5_61__df__lam_5_65__df__lam_5_69__df__lam_5_73__df__lam_5_77__df__lam_5_81__df__lam_5_85__df__lam_5_89__df__lam_5_93__df__lam_6_26__df__lam_6_34__df__lam_6_54__df__lam_6_58__df__lam_6_62__df__lam_6_66__df__lam_6_70__df__lam_6_74__df__lam_6_78__df__lam_6_82__df__lam_6_86__df__lam_6_90__df__lam_6_94__df__lam_7_27__df__lam_7_35__df__lam_7_55__df__lam_7_59__df__lam_7_63__df__lam_7_67__df__lam_7_71__df__lam_7_75__df__lam_7_79__df__lam_7_83__df__lam_7_87__df__lam_7_91__df__lam_7_95__df__lam_8_37__df__lam_9_38__lift_19__lift_2__lift_20__lift_21__lift_23__lift_24__lift_25__lift_27__lift_28__lift_29__lift_3__lift_4__lift_43__lift_44__lift_45(ptr %v__args) {
  call void @__inc_ref(ptr %v__args)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 260 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__scc__apply1__df__lam_10_39__df__lam_14_1__df__lam_14_13__df__lam_14_17__df__lam_14_21__df__lam_14_29__df__lam_14_41__df__lam_14_45__df__lam_14_5__df__lam_14_9__df__lam_15_10__df__lam_15_14__df__lam_15_18__df__lam_15_2__df__lam_15_22__df__lam_15_30__df__lam_15_42__df__lam_15_46__df__lam_15_6__df__lam_16_11__df__lam_16_15__df__lam_16_19__df__lam_16_23__df__lam_16_3__df__lam_16_31__df__lam_16_43__df__lam_16_47__df__lam_16_7__df__lam_46_49__df__lam_47_50__df__lam_48_51__df__lam_5_25__df__lam_5_33__df__lam_5_53__df__lam_5_57__df__lam_5_61__df__lam_5_65__df__lam_5_69__df__lam_5_73__df__lam_5_77__df__lam_5_81__df__lam_5_85__df__lam_5_89__df__lam_5_93__df__lam_6_26__df__lam_6_34__df__lam_6_54__df__lam_6_58__df__lam_6_62__df__lam_6_66__df__lam_6_70__df__lam_6_74__df__lam_6_78__df__lam_6_82__df__lam_6_86__df__lam_6_90__df__lam_6_94__df__lam_7_27__df__lam_7_35__df__lam_7_55__df__lam_7_59__df__lam_7_63__df__lam_7_67__df__lam_7_71__df__lam_7_75__df__lam_7_79__df__lam_7_83__df__lam_7_87__df__lam_7_91__df__lam_7_95__df__lam_8_37__df__lam_9_38__lift_19__lift_2__lift_20__lift_21__lift_23__lift_24__lift_25__lift_27__lift_28__lift_29__lift_3__lift_4__lift_43__lift_44__lift_45(ptr %v__args, ptr %t0)
  call void @__free_recursive(ptr %v__args)
  ret ptr %t3
}

define internal ptr @v__cps__scc__apply1__df__lam_10_39__df__lam_14_1__df__lam_14_13__df__lam_14_17__df__lam_14_21__df__lam_14_29__df__lam_14_41__df__lam_14_45__df__lam_14_5__df__lam_14_9__df__lam_15_10__df__lam_15_14__df__lam_15_18__df__lam_15_2__df__lam_15_22__df__lam_15_30__df__lam_15_42__df__lam_15_46__df__lam_15_6__df__lam_16_11__df__lam_16_15__df__lam_16_19__df__lam_16_23__df__lam_16_3__df__lam_16_31__df__lam_16_43__df__lam_16_47__df__lam_16_7__df__lam_46_49__df__lam_47_50__df__lam_48_51__df__lam_5_25__df__lam_5_33__df__lam_5_53__df__lam_5_57__df__lam_5_61__df__lam_5_65__df__lam_5_69__df__lam_5_73__df__lam_5_77__df__lam_5_81__df__lam_5_85__df__lam_5_89__df__lam_5_93__df__lam_6_26__df__lam_6_34__df__lam_6_54__df__lam_6_58__df__lam_6_62__df__lam_6_66__df__lam_6_70__df__lam_6_74__df__lam_6_78__df__lam_6_82__df__lam_6_86__df__lam_6_90__df__lam_6_94__df__lam_7_27__df__lam_7_35__df__lam_7_55__df__lam_7_59__df__lam_7_63__df__lam_7_67__df__lam_7_71__df__lam_7_75__df__lam_7_79__df__lam_7_83__df__lam_7_87__df__lam_7_91__df__lam_7_95__df__lam_8_37__df__lam_9_38__lift_19__lift_2__lift_20__lift_21__lift_23__lift_24__lift_25__lift_27__lift_28__lift_29__lift_3__lift_4__lift_43__lift_44__lift_45(ptr %v__args, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 114, label %tco.case.arm.114.11 i64 115, label %tco.case.arm.115.1733 i64 116, label %tco.case.arm.116.1756 i64 117, label %tco.case.arm.117.1779 i64 118, label %tco.case.arm.118.1802 i64 119, label %tco.case.arm.119.1825 i64 120, label %tco.case.arm.120.1848 i64 121, label %tco.case.arm.121.1871 i64 122, label %tco.case.arm.122.1894 i64 123, label %tco.case.arm.123.1917 i64 124, label %tco.case.arm.124.1940 i64 125, label %tco.case.arm.125.1963 i64 126, label %tco.case.arm.126.1986 i64 127, label %tco.case.arm.127.2009 i64 128, label %tco.case.arm.128.2032 i64 129, label %tco.case.arm.129.2055 i64 130, label %tco.case.arm.130.2078 i64 131, label %tco.case.arm.131.2101 i64 132, label %tco.case.arm.132.2124 i64 133, label %tco.case.arm.133.2147 i64 134, label %tco.case.arm.134.2170 i64 135, label %tco.case.arm.135.2193 i64 136, label %tco.case.arm.136.2216 i64 137, label %tco.case.arm.137.2239 i64 138, label %tco.case.arm.138.2262 i64 139, label %tco.case.arm.139.2285 i64 140, label %tco.case.arm.140.2308 i64 141, label %tco.case.arm.141.2331 i64 142, label %tco.case.arm.142.2354 i64 143, label %tco.case.arm.143.2377 i64 144, label %tco.case.arm.144.2400 i64 145, label %tco.case.arm.145.2423 i64 146, label %tco.case.arm.146.2446 i64 147, label %tco.case.arm.147.2469 i64 148, label %tco.case.arm.148.2492 i64 149, label %tco.case.arm.149.2515 i64 150, label %tco.case.arm.150.2532 i64 151, label %tco.case.arm.151.2555 i64 152, label %tco.case.arm.152.2578 i64 153, label %tco.case.arm.153.2601 i64 154, label %tco.case.arm.154.2624 i64 155, label %tco.case.arm.155.2647 i64 156, label %tco.case.arm.156.2670 i64 157, label %tco.case.arm.157.2693 i64 158, label %tco.case.arm.158.2716 i64 159, label %tco.case.arm.159.2739 i64 160, label %tco.case.arm.160.2762 i64 161, label %tco.case.arm.161.2785 i64 162, label %tco.case.arm.162.2808 i64 163, label %tco.case.arm.163.2825 i64 164, label %tco.case.arm.164.2848 i64 165, label %tco.case.arm.165.2871 i64 166, label %tco.case.arm.166.2894 i64 167, label %tco.case.arm.167.2917 i64 168, label %tco.case.arm.168.2940 i64 169, label %tco.case.arm.169.2963 i64 170, label %tco.case.arm.170.2986 i64 171, label %tco.case.arm.171.3009 i64 172, label %tco.case.arm.172.3032 i64 173, label %tco.case.arm.173.3055 i64 174, label %tco.case.arm.174.3078 i64 175, label %tco.case.arm.175.3101 i64 176, label %tco.case.arm.176.3118 i64 177, label %tco.case.arm.177.3141 i64 178, label %tco.case.arm.178.3164 i64 179, label %tco.case.arm.179.3187 i64 180, label %tco.case.arm.180.3210 i64 181, label %tco.case.arm.181.3233 i64 182, label %tco.case.arm.182.3256 i64 183, label %tco.case.arm.183.3279 i64 184, label %tco.case.arm.184.3302 i64 185, label %tco.case.arm.185.3325 i64 186, label %tco.case.arm.186.3348 i64 187, label %tco.case.arm.187.3371 i64 188, label %tco.case.arm.188.3394 i64 189, label %tco.case.arm.189.3417 i64 190, label %tco.case.arm.190.3440 i64 191, label %tco.case.arm.191.3463 i64 192, label %tco.case.arm.192.3486 i64 193, label %tco.case.arm.193.3509 i64 194, label %tco.case.arm.194.3532 i64 195, label %tco.case.arm.195.3555 i64 196, label %tco.case.arm.196.3578 i64 197, label %tco.case.arm.197.3601 i64 198, label %tco.case.arm.198.3624 i64 199, label %tco.case.arm.199.3647 i64 200, label %tco.case.arm.200.3670 i64 201, label %tco.case.arm.201.3693 ]
tco.case.arm.114.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t5, i32 2
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  %t16 = getelementptr ptr, ptr %t13, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %tco.case.default.19 [ i64 27, label %tco.case.arm.27.20 i64 28, label %tco.case.arm.28.40 i64 29, label %tco.case.arm.29.60 i64 30, label %tco.case.arm.30.80 i64 31, label %tco.case.arm.31.100 i64 32, label %tco.case.arm.32.120 i64 33, label %tco.case.arm.33.140 i64 34, label %tco.case.arm.34.160 i64 35, label %tco.case.arm.35.180 i64 36, label %tco.case.arm.36.200 i64 37, label %tco.case.arm.37.220 i64 38, label %tco.case.arm.38.240 i64 39, label %tco.case.arm.39.260 i64 40, label %tco.case.arm.40.280 i64 41, label %tco.case.arm.41.300 i64 42, label %tco.case.arm.42.320 i64 43, label %tco.case.arm.43.340 i64 44, label %tco.case.arm.44.360 i64 45, label %tco.case.arm.45.380 i64 46, label %tco.case.arm.46.400 i64 47, label %tco.case.arm.47.420 i64 48, label %tco.case.arm.48.440 i64 49, label %tco.case.arm.49.460 i64 50, label %tco.case.arm.50.480 i64 51, label %tco.case.arm.51.500 i64 52, label %tco.case.arm.52.520 i64 53, label %tco.case.arm.53.540 i64 54, label %tco.case.arm.54.560 i64 55, label %tco.case.arm.55.580 i64 56, label %tco.case.arm.56.600 i64 57, label %tco.case.arm.57.620 i64 58, label %tco.case.arm.58.640 i64 59, label %tco.case.arm.59.660 i64 60, label %tco.case.arm.60.680 i64 61, label %tco.case.arm.61.700 i64 62, label %tco.case.arm.62.711 i64 63, label %tco.case.arm.63.731 i64 64, label %tco.case.arm.64.751 i64 65, label %tco.case.arm.65.771 i64 66, label %tco.case.arm.66.791 i64 67, label %tco.case.arm.67.811 i64 68, label %tco.case.arm.68.831 i64 69, label %tco.case.arm.69.851 i64 70, label %tco.case.arm.70.871 i64 71, label %tco.case.arm.71.891 i64 72, label %tco.case.arm.72.911 i64 73, label %tco.case.arm.73.931 i64 74, label %tco.case.arm.74.951 i64 75, label %tco.case.arm.75.962 i64 76, label %tco.case.arm.76.982 i64 77, label %tco.case.arm.77.1002 i64 78, label %tco.case.arm.78.1022 i64 79, label %tco.case.arm.79.1042 i64 80, label %tco.case.arm.80.1062 i64 81, label %tco.case.arm.81.1082 i64 82, label %tco.case.arm.82.1102 i64 83, label %tco.case.arm.83.1122 i64 84, label %tco.case.arm.84.1142 i64 85, label %tco.case.arm.85.1162 i64 86, label %tco.case.arm.86.1182 i64 87, label %tco.case.arm.87.1202 i64 88, label %tco.case.arm.88.1213 i64 89, label %tco.case.arm.89.1233 i64 90, label %tco.case.arm.90.1253 i64 91, label %tco.case.arm.91.1273 i64 92, label %tco.case.arm.92.1293 i64 93, label %tco.case.arm.93.1313 i64 94, label %tco.case.arm.94.1333 i64 95, label %tco.case.arm.95.1353 i64 96, label %tco.case.arm.96.1373 i64 97, label %tco.case.arm.97.1393 i64 98, label %tco.case.arm.98.1413 i64 99, label %tco.case.arm.99.1433 i64 100, label %tco.case.arm.100.1453 i64 101, label %tco.case.arm.101.1473 i64 102, label %tco.case.arm.102.1493 i64 103, label %tco.case.arm.103.1513 i64 104, label %tco.case.arm.104.1533 i64 105, label %tco.case.arm.105.1553 i64 106, label %tco.case.arm.106.1573 i64 107, label %tco.case.arm.107.1593 i64 108, label %tco.case.arm.108.1613 i64 109, label %tco.case.arm.109.1633 i64 110, label %tco.case.arm.110.1653 i64 111, label %tco.case.arm.111.1673 i64 112, label %tco.case.arm.112.1693 i64 113, label %tco.case.arm.113.1713 ]
tco.case.arm.27.20:
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
  %t32 = inttoptr i64 115 to ptr
  %t33 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t32, ptr %t33
  call void @__inc_ref(ptr %t22)
  %t31 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t22, ptr %t31
  br label %reuse.join.28
reuse.copy.27:
  %t34 = call ptr @__alloc(i64 24, i32 2)
  %t35 = inttoptr i64 115 to ptr
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
tco.case.arm.28.40:
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
  %t52 = inttoptr i64 116 to ptr
  %t53 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t52, ptr %t53
  call void @__inc_ref(ptr %t42)
  %t51 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t42, ptr %t51
  br label %reuse.join.48
reuse.copy.47:
  %t54 = call ptr @__alloc(i64 24, i32 2)
  %t55 = inttoptr i64 116 to ptr
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
tco.case.arm.29.60:
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
  %t72 = inttoptr i64 117 to ptr
  %t73 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t72, ptr %t73
  call void @__inc_ref(ptr %t62)
  %t71 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t62, ptr %t71
  br label %reuse.join.68
reuse.copy.67:
  %t74 = call ptr @__alloc(i64 24, i32 2)
  %t75 = inttoptr i64 117 to ptr
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
tco.case.arm.30.80:
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
  %t92 = inttoptr i64 118 to ptr
  %t93 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t92, ptr %t93
  call void @__inc_ref(ptr %t82)
  %t91 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t82, ptr %t91
  br label %reuse.join.88
reuse.copy.87:
  %t94 = call ptr @__alloc(i64 24, i32 2)
  %t95 = inttoptr i64 118 to ptr
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
tco.case.arm.31.100:
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
  %t112 = inttoptr i64 119 to ptr
  %t113 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t112, ptr %t113
  call void @__inc_ref(ptr %t102)
  %t111 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t102, ptr %t111
  br label %reuse.join.108
reuse.copy.107:
  %t114 = call ptr @__alloc(i64 24, i32 2)
  %t115 = inttoptr i64 119 to ptr
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
tco.case.arm.32.120:
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
  %t132 = inttoptr i64 120 to ptr
  %t133 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t132, ptr %t133
  call void @__inc_ref(ptr %t122)
  %t131 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t122, ptr %t131
  br label %reuse.join.128
reuse.copy.127:
  %t134 = call ptr @__alloc(i64 24, i32 2)
  %t135 = inttoptr i64 120 to ptr
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
tco.case.arm.33.140:
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
  %t152 = inttoptr i64 121 to ptr
  %t153 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t152, ptr %t153
  call void @__inc_ref(ptr %t142)
  %t151 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t142, ptr %t151
  br label %reuse.join.148
reuse.copy.147:
  %t154 = call ptr @__alloc(i64 24, i32 2)
  %t155 = inttoptr i64 121 to ptr
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
tco.case.arm.34.160:
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
  %t172 = inttoptr i64 122 to ptr
  %t173 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t172, ptr %t173
  call void @__inc_ref(ptr %t162)
  %t171 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t162, ptr %t171
  br label %reuse.join.168
reuse.copy.167:
  %t174 = call ptr @__alloc(i64 24, i32 2)
  %t175 = inttoptr i64 122 to ptr
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
tco.case.arm.35.180:
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
  %t192 = inttoptr i64 123 to ptr
  %t193 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t192, ptr %t193
  call void @__inc_ref(ptr %t182)
  %t191 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t182, ptr %t191
  br label %reuse.join.188
reuse.copy.187:
  %t194 = call ptr @__alloc(i64 24, i32 2)
  %t195 = inttoptr i64 123 to ptr
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
tco.case.arm.36.200:
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
  %t212 = inttoptr i64 124 to ptr
  %t213 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t212, ptr %t213
  call void @__inc_ref(ptr %t202)
  %t211 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t202, ptr %t211
  br label %reuse.join.208
reuse.copy.207:
  %t214 = call ptr @__alloc(i64 24, i32 2)
  %t215 = inttoptr i64 124 to ptr
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
tco.case.arm.37.220:
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
  %t232 = inttoptr i64 125 to ptr
  %t233 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t232, ptr %t233
  call void @__inc_ref(ptr %t222)
  %t231 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t222, ptr %t231
  br label %reuse.join.228
reuse.copy.227:
  %t234 = call ptr @__alloc(i64 24, i32 2)
  %t235 = inttoptr i64 125 to ptr
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
tco.case.arm.38.240:
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
  %t252 = inttoptr i64 126 to ptr
  %t253 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t252, ptr %t253
  call void @__inc_ref(ptr %t242)
  %t251 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t242, ptr %t251
  br label %reuse.join.248
reuse.copy.247:
  %t254 = call ptr @__alloc(i64 24, i32 2)
  %t255 = inttoptr i64 126 to ptr
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
tco.case.arm.39.260:
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
  %t272 = inttoptr i64 127 to ptr
  %t273 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t272, ptr %t273
  call void @__inc_ref(ptr %t262)
  %t271 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t262, ptr %t271
  br label %reuse.join.268
reuse.copy.267:
  %t274 = call ptr @__alloc(i64 24, i32 2)
  %t275 = inttoptr i64 127 to ptr
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
tco.case.arm.40.280:
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
  %t292 = inttoptr i64 128 to ptr
  %t293 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t292, ptr %t293
  call void @__inc_ref(ptr %t282)
  %t291 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t282, ptr %t291
  br label %reuse.join.288
reuse.copy.287:
  %t294 = call ptr @__alloc(i64 24, i32 2)
  %t295 = inttoptr i64 128 to ptr
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
tco.case.arm.41.300:
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
  %t312 = inttoptr i64 129 to ptr
  %t313 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t312, ptr %t313
  call void @__inc_ref(ptr %t302)
  %t311 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t302, ptr %t311
  br label %reuse.join.308
reuse.copy.307:
  %t314 = call ptr @__alloc(i64 24, i32 2)
  %t315 = inttoptr i64 129 to ptr
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
tco.case.arm.42.320:
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
  %t332 = inttoptr i64 130 to ptr
  %t333 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t332, ptr %t333
  call void @__inc_ref(ptr %t322)
  %t331 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t322, ptr %t331
  br label %reuse.join.328
reuse.copy.327:
  %t334 = call ptr @__alloc(i64 24, i32 2)
  %t335 = inttoptr i64 130 to ptr
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
tco.case.arm.43.340:
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
  %t352 = inttoptr i64 131 to ptr
  %t353 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t352, ptr %t353
  call void @__inc_ref(ptr %t342)
  %t351 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t342, ptr %t351
  br label %reuse.join.348
reuse.copy.347:
  %t354 = call ptr @__alloc(i64 24, i32 2)
  %t355 = inttoptr i64 131 to ptr
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
tco.case.arm.44.360:
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
  %t372 = inttoptr i64 132 to ptr
  %t373 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t372, ptr %t373
  call void @__inc_ref(ptr %t362)
  %t371 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t362, ptr %t371
  br label %reuse.join.368
reuse.copy.367:
  %t374 = call ptr @__alloc(i64 24, i32 2)
  %t375 = inttoptr i64 132 to ptr
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
tco.case.arm.45.380:
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
  %t392 = inttoptr i64 133 to ptr
  %t393 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t392, ptr %t393
  call void @__inc_ref(ptr %t382)
  %t391 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t382, ptr %t391
  br label %reuse.join.388
reuse.copy.387:
  %t394 = call ptr @__alloc(i64 24, i32 2)
  %t395 = inttoptr i64 133 to ptr
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
tco.case.arm.46.400:
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
  %t412 = inttoptr i64 134 to ptr
  %t413 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t412, ptr %t413
  call void @__inc_ref(ptr %t402)
  %t411 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t402, ptr %t411
  br label %reuse.join.408
reuse.copy.407:
  %t414 = call ptr @__alloc(i64 24, i32 2)
  %t415 = inttoptr i64 134 to ptr
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
tco.case.arm.47.420:
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
  %t432 = inttoptr i64 135 to ptr
  %t433 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t432, ptr %t433
  call void @__inc_ref(ptr %t422)
  %t431 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t422, ptr %t431
  br label %reuse.join.428
reuse.copy.427:
  %t434 = call ptr @__alloc(i64 24, i32 2)
  %t435 = inttoptr i64 135 to ptr
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
tco.case.arm.48.440:
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
  %t452 = inttoptr i64 136 to ptr
  %t453 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t452, ptr %t453
  call void @__inc_ref(ptr %t442)
  %t451 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t442, ptr %t451
  br label %reuse.join.448
reuse.copy.447:
  %t454 = call ptr @__alloc(i64 24, i32 2)
  %t455 = inttoptr i64 136 to ptr
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
tco.case.arm.49.460:
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
  %t472 = inttoptr i64 137 to ptr
  %t473 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t472, ptr %t473
  call void @__inc_ref(ptr %t462)
  %t471 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t462, ptr %t471
  br label %reuse.join.468
reuse.copy.467:
  %t474 = call ptr @__alloc(i64 24, i32 2)
  %t475 = inttoptr i64 137 to ptr
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
tco.case.arm.50.480:
  %t481 = getelementptr ptr, ptr %t13, i32 1
  %t482 = load ptr, ptr %t481
  call void @__inc_ref(ptr %t482)
  %t483 = getelementptr i8, ptr %t5, i64 -8
  %t484 = load i32, ptr %t483
  %t485 = icmp eq i32 %t484, 1
  br i1 %t485, label %reuse.in_place.486, label %reuse.copy.487
reuse.in_place.486:
  %t489 = getelementptr ptr, ptr %t5, i32 1
  %t490 = load ptr, ptr %t489
  call void @__free_recursive(ptr %t490)
  %t492 = inttoptr i64 138 to ptr
  %t493 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t492, ptr %t493
  call void @__inc_ref(ptr %t482)
  %t491 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t482, ptr %t491
  br label %reuse.join.488
reuse.copy.487:
  %t494 = call ptr @__alloc(i64 24, i32 2)
  %t495 = inttoptr i64 138 to ptr
  %t496 = getelementptr ptr, ptr %t494, i32 0
  store ptr %t495, ptr %t496
  call void @__inc_ref(ptr %t482)
  %t497 = getelementptr ptr, ptr %t494, i32 1
  store ptr %t482, ptr %t497
  call void @__inc_ref(ptr %t15)
  %t498 = getelementptr ptr, ptr %t494, i32 2
  store ptr %t15, ptr %t498
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.488
reuse.join.488:
  %t499 = phi ptr [ %t5, %reuse.in_place.486 ], [ %t494, %reuse.copy.487 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t482)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t499, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.51.500:
  %t501 = getelementptr ptr, ptr %t13, i32 1
  %t502 = load ptr, ptr %t501
  call void @__inc_ref(ptr %t502)
  %t503 = getelementptr i8, ptr %t5, i64 -8
  %t504 = load i32, ptr %t503
  %t505 = icmp eq i32 %t504, 1
  br i1 %t505, label %reuse.in_place.506, label %reuse.copy.507
reuse.in_place.506:
  %t509 = getelementptr ptr, ptr %t5, i32 1
  %t510 = load ptr, ptr %t509
  call void @__free_recursive(ptr %t510)
  %t512 = inttoptr i64 139 to ptr
  %t513 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t512, ptr %t513
  call void @__inc_ref(ptr %t502)
  %t511 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t502, ptr %t511
  br label %reuse.join.508
reuse.copy.507:
  %t514 = call ptr @__alloc(i64 24, i32 2)
  %t515 = inttoptr i64 139 to ptr
  %t516 = getelementptr ptr, ptr %t514, i32 0
  store ptr %t515, ptr %t516
  call void @__inc_ref(ptr %t502)
  %t517 = getelementptr ptr, ptr %t514, i32 1
  store ptr %t502, ptr %t517
  call void @__inc_ref(ptr %t15)
  %t518 = getelementptr ptr, ptr %t514, i32 2
  store ptr %t15, ptr %t518
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.508
reuse.join.508:
  %t519 = phi ptr [ %t5, %reuse.in_place.506 ], [ %t514, %reuse.copy.507 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t502)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t519, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.52.520:
  %t521 = getelementptr ptr, ptr %t13, i32 1
  %t522 = load ptr, ptr %t521
  call void @__inc_ref(ptr %t522)
  %t523 = getelementptr i8, ptr %t5, i64 -8
  %t524 = load i32, ptr %t523
  %t525 = icmp eq i32 %t524, 1
  br i1 %t525, label %reuse.in_place.526, label %reuse.copy.527
reuse.in_place.526:
  %t529 = getelementptr ptr, ptr %t5, i32 1
  %t530 = load ptr, ptr %t529
  call void @__free_recursive(ptr %t530)
  %t532 = inttoptr i64 140 to ptr
  %t533 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t532, ptr %t533
  call void @__inc_ref(ptr %t522)
  %t531 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t522, ptr %t531
  br label %reuse.join.528
reuse.copy.527:
  %t534 = call ptr @__alloc(i64 24, i32 2)
  %t535 = inttoptr i64 140 to ptr
  %t536 = getelementptr ptr, ptr %t534, i32 0
  store ptr %t535, ptr %t536
  call void @__inc_ref(ptr %t522)
  %t537 = getelementptr ptr, ptr %t534, i32 1
  store ptr %t522, ptr %t537
  call void @__inc_ref(ptr %t15)
  %t538 = getelementptr ptr, ptr %t534, i32 2
  store ptr %t15, ptr %t538
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.528
reuse.join.528:
  %t539 = phi ptr [ %t5, %reuse.in_place.526 ], [ %t534, %reuse.copy.527 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t522)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t539, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.53.540:
  %t541 = getelementptr ptr, ptr %t13, i32 1
  %t542 = load ptr, ptr %t541
  call void @__inc_ref(ptr %t542)
  %t543 = getelementptr i8, ptr %t5, i64 -8
  %t544 = load i32, ptr %t543
  %t545 = icmp eq i32 %t544, 1
  br i1 %t545, label %reuse.in_place.546, label %reuse.copy.547
reuse.in_place.546:
  %t549 = getelementptr ptr, ptr %t5, i32 1
  %t550 = load ptr, ptr %t549
  call void @__free_recursive(ptr %t550)
  %t552 = inttoptr i64 141 to ptr
  %t553 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t552, ptr %t553
  call void @__inc_ref(ptr %t542)
  %t551 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t542, ptr %t551
  br label %reuse.join.548
reuse.copy.547:
  %t554 = call ptr @__alloc(i64 24, i32 2)
  %t555 = inttoptr i64 141 to ptr
  %t556 = getelementptr ptr, ptr %t554, i32 0
  store ptr %t555, ptr %t556
  call void @__inc_ref(ptr %t542)
  %t557 = getelementptr ptr, ptr %t554, i32 1
  store ptr %t542, ptr %t557
  call void @__inc_ref(ptr %t15)
  %t558 = getelementptr ptr, ptr %t554, i32 2
  store ptr %t15, ptr %t558
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.548
reuse.join.548:
  %t559 = phi ptr [ %t5, %reuse.in_place.546 ], [ %t554, %reuse.copy.547 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t542)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t559, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.54.560:
  %t561 = getelementptr ptr, ptr %t13, i32 1
  %t562 = load ptr, ptr %t561
  call void @__inc_ref(ptr %t562)
  %t563 = getelementptr i8, ptr %t5, i64 -8
  %t564 = load i32, ptr %t563
  %t565 = icmp eq i32 %t564, 1
  br i1 %t565, label %reuse.in_place.566, label %reuse.copy.567
reuse.in_place.566:
  %t569 = getelementptr ptr, ptr %t5, i32 1
  %t570 = load ptr, ptr %t569
  call void @__free_recursive(ptr %t570)
  %t572 = inttoptr i64 142 to ptr
  %t573 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t572, ptr %t573
  call void @__inc_ref(ptr %t562)
  %t571 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t562, ptr %t571
  br label %reuse.join.568
reuse.copy.567:
  %t574 = call ptr @__alloc(i64 24, i32 2)
  %t575 = inttoptr i64 142 to ptr
  %t576 = getelementptr ptr, ptr %t574, i32 0
  store ptr %t575, ptr %t576
  call void @__inc_ref(ptr %t562)
  %t577 = getelementptr ptr, ptr %t574, i32 1
  store ptr %t562, ptr %t577
  call void @__inc_ref(ptr %t15)
  %t578 = getelementptr ptr, ptr %t574, i32 2
  store ptr %t15, ptr %t578
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.568
reuse.join.568:
  %t579 = phi ptr [ %t5, %reuse.in_place.566 ], [ %t574, %reuse.copy.567 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t562)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t579, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.55.580:
  %t581 = getelementptr ptr, ptr %t13, i32 1
  %t582 = load ptr, ptr %t581
  call void @__inc_ref(ptr %t582)
  %t583 = getelementptr i8, ptr %t5, i64 -8
  %t584 = load i32, ptr %t583
  %t585 = icmp eq i32 %t584, 1
  br i1 %t585, label %reuse.in_place.586, label %reuse.copy.587
reuse.in_place.586:
  %t589 = getelementptr ptr, ptr %t5, i32 1
  %t590 = load ptr, ptr %t589
  call void @__free_recursive(ptr %t590)
  %t592 = inttoptr i64 143 to ptr
  %t593 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t592, ptr %t593
  call void @__inc_ref(ptr %t582)
  %t591 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t582, ptr %t591
  br label %reuse.join.588
reuse.copy.587:
  %t594 = call ptr @__alloc(i64 24, i32 2)
  %t595 = inttoptr i64 143 to ptr
  %t596 = getelementptr ptr, ptr %t594, i32 0
  store ptr %t595, ptr %t596
  call void @__inc_ref(ptr %t582)
  %t597 = getelementptr ptr, ptr %t594, i32 1
  store ptr %t582, ptr %t597
  call void @__inc_ref(ptr %t15)
  %t598 = getelementptr ptr, ptr %t594, i32 2
  store ptr %t15, ptr %t598
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.588
reuse.join.588:
  %t599 = phi ptr [ %t5, %reuse.in_place.586 ], [ %t594, %reuse.copy.587 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t582)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t599, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.56.600:
  %t601 = getelementptr ptr, ptr %t13, i32 1
  %t602 = load ptr, ptr %t601
  call void @__inc_ref(ptr %t602)
  %t603 = getelementptr i8, ptr %t5, i64 -8
  %t604 = load i32, ptr %t603
  %t605 = icmp eq i32 %t604, 1
  br i1 %t605, label %reuse.in_place.606, label %reuse.copy.607
reuse.in_place.606:
  %t609 = getelementptr ptr, ptr %t5, i32 1
  %t610 = load ptr, ptr %t609
  call void @__free_recursive(ptr %t610)
  %t612 = inttoptr i64 144 to ptr
  %t613 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t612, ptr %t613
  call void @__inc_ref(ptr %t602)
  %t611 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t602, ptr %t611
  br label %reuse.join.608
reuse.copy.607:
  %t614 = call ptr @__alloc(i64 24, i32 2)
  %t615 = inttoptr i64 144 to ptr
  %t616 = getelementptr ptr, ptr %t614, i32 0
  store ptr %t615, ptr %t616
  call void @__inc_ref(ptr %t602)
  %t617 = getelementptr ptr, ptr %t614, i32 1
  store ptr %t602, ptr %t617
  call void @__inc_ref(ptr %t15)
  %t618 = getelementptr ptr, ptr %t614, i32 2
  store ptr %t15, ptr %t618
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.608
reuse.join.608:
  %t619 = phi ptr [ %t5, %reuse.in_place.606 ], [ %t614, %reuse.copy.607 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t602)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t619, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.57.620:
  %t621 = getelementptr ptr, ptr %t13, i32 1
  %t622 = load ptr, ptr %t621
  call void @__inc_ref(ptr %t622)
  %t623 = getelementptr i8, ptr %t5, i64 -8
  %t624 = load i32, ptr %t623
  %t625 = icmp eq i32 %t624, 1
  br i1 %t625, label %reuse.in_place.626, label %reuse.copy.627
reuse.in_place.626:
  %t629 = getelementptr ptr, ptr %t5, i32 1
  %t630 = load ptr, ptr %t629
  call void @__free_recursive(ptr %t630)
  %t632 = inttoptr i64 145 to ptr
  %t633 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t632, ptr %t633
  call void @__inc_ref(ptr %t622)
  %t631 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t622, ptr %t631
  br label %reuse.join.628
reuse.copy.627:
  %t634 = call ptr @__alloc(i64 24, i32 2)
  %t635 = inttoptr i64 145 to ptr
  %t636 = getelementptr ptr, ptr %t634, i32 0
  store ptr %t635, ptr %t636
  call void @__inc_ref(ptr %t622)
  %t637 = getelementptr ptr, ptr %t634, i32 1
  store ptr %t622, ptr %t637
  call void @__inc_ref(ptr %t15)
  %t638 = getelementptr ptr, ptr %t634, i32 2
  store ptr %t15, ptr %t638
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.628
reuse.join.628:
  %t639 = phi ptr [ %t5, %reuse.in_place.626 ], [ %t634, %reuse.copy.627 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t622)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t639, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.58.640:
  %t641 = getelementptr ptr, ptr %t13, i32 1
  %t642 = load ptr, ptr %t641
  call void @__inc_ref(ptr %t642)
  %t643 = getelementptr i8, ptr %t5, i64 -8
  %t644 = load i32, ptr %t643
  %t645 = icmp eq i32 %t644, 1
  br i1 %t645, label %reuse.in_place.646, label %reuse.copy.647
reuse.in_place.646:
  %t649 = getelementptr ptr, ptr %t5, i32 1
  %t650 = load ptr, ptr %t649
  call void @__free_recursive(ptr %t650)
  %t652 = inttoptr i64 146 to ptr
  %t653 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t652, ptr %t653
  call void @__inc_ref(ptr %t642)
  %t651 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t642, ptr %t651
  br label %reuse.join.648
reuse.copy.647:
  %t654 = call ptr @__alloc(i64 24, i32 2)
  %t655 = inttoptr i64 146 to ptr
  %t656 = getelementptr ptr, ptr %t654, i32 0
  store ptr %t655, ptr %t656
  call void @__inc_ref(ptr %t642)
  %t657 = getelementptr ptr, ptr %t654, i32 1
  store ptr %t642, ptr %t657
  call void @__inc_ref(ptr %t15)
  %t658 = getelementptr ptr, ptr %t654, i32 2
  store ptr %t15, ptr %t658
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.648
reuse.join.648:
  %t659 = phi ptr [ %t5, %reuse.in_place.646 ], [ %t654, %reuse.copy.647 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t642)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t659, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.59.660:
  %t661 = getelementptr ptr, ptr %t13, i32 1
  %t662 = load ptr, ptr %t661
  call void @__inc_ref(ptr %t662)
  %t663 = getelementptr i8, ptr %t5, i64 -8
  %t664 = load i32, ptr %t663
  %t665 = icmp eq i32 %t664, 1
  br i1 %t665, label %reuse.in_place.666, label %reuse.copy.667
reuse.in_place.666:
  %t669 = getelementptr ptr, ptr %t5, i32 1
  %t670 = load ptr, ptr %t669
  call void @__free_recursive(ptr %t670)
  %t672 = inttoptr i64 147 to ptr
  %t673 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t672, ptr %t673
  call void @__inc_ref(ptr %t662)
  %t671 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t662, ptr %t671
  br label %reuse.join.668
reuse.copy.667:
  %t674 = call ptr @__alloc(i64 24, i32 2)
  %t675 = inttoptr i64 147 to ptr
  %t676 = getelementptr ptr, ptr %t674, i32 0
  store ptr %t675, ptr %t676
  call void @__inc_ref(ptr %t662)
  %t677 = getelementptr ptr, ptr %t674, i32 1
  store ptr %t662, ptr %t677
  call void @__inc_ref(ptr %t15)
  %t678 = getelementptr ptr, ptr %t674, i32 2
  store ptr %t15, ptr %t678
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.668
reuse.join.668:
  %t679 = phi ptr [ %t5, %reuse.in_place.666 ], [ %t674, %reuse.copy.667 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t662)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t679, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.60.680:
  %t681 = getelementptr ptr, ptr %t13, i32 1
  %t682 = load ptr, ptr %t681
  call void @__inc_ref(ptr %t682)
  %t683 = getelementptr i8, ptr %t5, i64 -8
  %t684 = load i32, ptr %t683
  %t685 = icmp eq i32 %t684, 1
  br i1 %t685, label %reuse.in_place.686, label %reuse.copy.687
reuse.in_place.686:
  %t689 = getelementptr ptr, ptr %t5, i32 1
  %t690 = load ptr, ptr %t689
  call void @__free_recursive(ptr %t690)
  %t692 = inttoptr i64 148 to ptr
  %t693 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t692, ptr %t693
  call void @__inc_ref(ptr %t682)
  %t691 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t682, ptr %t691
  br label %reuse.join.688
reuse.copy.687:
  %t694 = call ptr @__alloc(i64 24, i32 2)
  %t695 = inttoptr i64 148 to ptr
  %t696 = getelementptr ptr, ptr %t694, i32 0
  store ptr %t695, ptr %t696
  call void @__inc_ref(ptr %t682)
  %t697 = getelementptr ptr, ptr %t694, i32 1
  store ptr %t682, ptr %t697
  call void @__inc_ref(ptr %t15)
  %t698 = getelementptr ptr, ptr %t694, i32 2
  store ptr %t15, ptr %t698
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.688
reuse.join.688:
  %t699 = phi ptr [ %t5, %reuse.in_place.686 ], [ %t694, %reuse.copy.687 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t682)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t699, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.61.700:
  %t701 = getelementptr ptr, ptr %t13, i32 1
  %t702 = load ptr, ptr %t701
  call void @__inc_ref(ptr %t702)
  %t703 = getelementptr ptr, ptr %t13, i32 2
  %t704 = load ptr, ptr %t703
  call void @__inc_ref(ptr %t704)
  %t705 = call ptr @__alloc(i64 32, i32 3)
  %t706 = inttoptr i64 149 to ptr
  %t707 = getelementptr ptr, ptr %t705, i32 0
  store ptr %t706, ptr %t707
  call void @__inc_ref(ptr %t702)
  %t708 = getelementptr ptr, ptr %t705, i32 1
  store ptr %t702, ptr %t708
  call void @__inc_ref(ptr %t704)
  %t709 = getelementptr ptr, ptr %t705, i32 2
  store ptr %t704, ptr %t709
  call void @__inc_ref(ptr %t15)
  %t710 = getelementptr ptr, ptr %t705, i32 3
  store ptr %t15, ptr %t710
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t704)
  call void @__free_recursive(ptr %t702)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t705, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.62.711:
  %t712 = getelementptr ptr, ptr %t13, i32 1
  %t713 = load ptr, ptr %t712
  call void @__inc_ref(ptr %t713)
  %t714 = getelementptr i8, ptr %t5, i64 -8
  %t715 = load i32, ptr %t714
  %t716 = icmp eq i32 %t715, 1
  br i1 %t716, label %reuse.in_place.717, label %reuse.copy.718
reuse.in_place.717:
  %t720 = getelementptr ptr, ptr %t5, i32 1
  %t721 = load ptr, ptr %t720
  call void @__free_recursive(ptr %t721)
  %t723 = inttoptr i64 150 to ptr
  %t724 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t723, ptr %t724
  call void @__inc_ref(ptr %t713)
  %t722 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t713, ptr %t722
  br label %reuse.join.719
reuse.copy.718:
  %t725 = call ptr @__alloc(i64 24, i32 2)
  %t726 = inttoptr i64 150 to ptr
  %t727 = getelementptr ptr, ptr %t725, i32 0
  store ptr %t726, ptr %t727
  call void @__inc_ref(ptr %t713)
  %t728 = getelementptr ptr, ptr %t725, i32 1
  store ptr %t713, ptr %t728
  call void @__inc_ref(ptr %t15)
  %t729 = getelementptr ptr, ptr %t725, i32 2
  store ptr %t15, ptr %t729
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.719
reuse.join.719:
  %t730 = phi ptr [ %t5, %reuse.in_place.717 ], [ %t725, %reuse.copy.718 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t713)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t730, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.63.731:
  %t732 = getelementptr ptr, ptr %t13, i32 1
  %t733 = load ptr, ptr %t732
  call void @__inc_ref(ptr %t733)
  %t734 = getelementptr i8, ptr %t5, i64 -8
  %t735 = load i32, ptr %t734
  %t736 = icmp eq i32 %t735, 1
  br i1 %t736, label %reuse.in_place.737, label %reuse.copy.738
reuse.in_place.737:
  %t740 = getelementptr ptr, ptr %t5, i32 1
  %t741 = load ptr, ptr %t740
  call void @__free_recursive(ptr %t741)
  %t743 = inttoptr i64 151 to ptr
  %t744 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t743, ptr %t744
  call void @__inc_ref(ptr %t733)
  %t742 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t733, ptr %t742
  br label %reuse.join.739
reuse.copy.738:
  %t745 = call ptr @__alloc(i64 24, i32 2)
  %t746 = inttoptr i64 151 to ptr
  %t747 = getelementptr ptr, ptr %t745, i32 0
  store ptr %t746, ptr %t747
  call void @__inc_ref(ptr %t733)
  %t748 = getelementptr ptr, ptr %t745, i32 1
  store ptr %t733, ptr %t748
  call void @__inc_ref(ptr %t15)
  %t749 = getelementptr ptr, ptr %t745, i32 2
  store ptr %t15, ptr %t749
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.739
reuse.join.739:
  %t750 = phi ptr [ %t5, %reuse.in_place.737 ], [ %t745, %reuse.copy.738 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t733)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t750, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.64.751:
  %t752 = getelementptr ptr, ptr %t13, i32 1
  %t753 = load ptr, ptr %t752
  call void @__inc_ref(ptr %t753)
  %t754 = getelementptr i8, ptr %t5, i64 -8
  %t755 = load i32, ptr %t754
  %t756 = icmp eq i32 %t755, 1
  br i1 %t756, label %reuse.in_place.757, label %reuse.copy.758
reuse.in_place.757:
  %t760 = getelementptr ptr, ptr %t5, i32 1
  %t761 = load ptr, ptr %t760
  call void @__free_recursive(ptr %t761)
  %t763 = inttoptr i64 152 to ptr
  %t764 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t763, ptr %t764
  call void @__inc_ref(ptr %t753)
  %t762 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t753, ptr %t762
  br label %reuse.join.759
reuse.copy.758:
  %t765 = call ptr @__alloc(i64 24, i32 2)
  %t766 = inttoptr i64 152 to ptr
  %t767 = getelementptr ptr, ptr %t765, i32 0
  store ptr %t766, ptr %t767
  call void @__inc_ref(ptr %t753)
  %t768 = getelementptr ptr, ptr %t765, i32 1
  store ptr %t753, ptr %t768
  call void @__inc_ref(ptr %t15)
  %t769 = getelementptr ptr, ptr %t765, i32 2
  store ptr %t15, ptr %t769
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.759
reuse.join.759:
  %t770 = phi ptr [ %t5, %reuse.in_place.757 ], [ %t765, %reuse.copy.758 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t753)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t770, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.65.771:
  %t772 = getelementptr ptr, ptr %t13, i32 1
  %t773 = load ptr, ptr %t772
  call void @__inc_ref(ptr %t773)
  %t774 = getelementptr i8, ptr %t5, i64 -8
  %t775 = load i32, ptr %t774
  %t776 = icmp eq i32 %t775, 1
  br i1 %t776, label %reuse.in_place.777, label %reuse.copy.778
reuse.in_place.777:
  %t780 = getelementptr ptr, ptr %t5, i32 1
  %t781 = load ptr, ptr %t780
  call void @__free_recursive(ptr %t781)
  %t783 = inttoptr i64 153 to ptr
  %t784 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t783, ptr %t784
  call void @__inc_ref(ptr %t773)
  %t782 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t773, ptr %t782
  br label %reuse.join.779
reuse.copy.778:
  %t785 = call ptr @__alloc(i64 24, i32 2)
  %t786 = inttoptr i64 153 to ptr
  %t787 = getelementptr ptr, ptr %t785, i32 0
  store ptr %t786, ptr %t787
  call void @__inc_ref(ptr %t773)
  %t788 = getelementptr ptr, ptr %t785, i32 1
  store ptr %t773, ptr %t788
  call void @__inc_ref(ptr %t15)
  %t789 = getelementptr ptr, ptr %t785, i32 2
  store ptr %t15, ptr %t789
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.779
reuse.join.779:
  %t790 = phi ptr [ %t5, %reuse.in_place.777 ], [ %t785, %reuse.copy.778 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t773)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t790, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.66.791:
  %t792 = getelementptr ptr, ptr %t13, i32 1
  %t793 = load ptr, ptr %t792
  call void @__inc_ref(ptr %t793)
  %t794 = getelementptr i8, ptr %t5, i64 -8
  %t795 = load i32, ptr %t794
  %t796 = icmp eq i32 %t795, 1
  br i1 %t796, label %reuse.in_place.797, label %reuse.copy.798
reuse.in_place.797:
  %t800 = getelementptr ptr, ptr %t5, i32 1
  %t801 = load ptr, ptr %t800
  call void @__free_recursive(ptr %t801)
  %t803 = inttoptr i64 154 to ptr
  %t804 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t803, ptr %t804
  call void @__inc_ref(ptr %t793)
  %t802 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t793, ptr %t802
  br label %reuse.join.799
reuse.copy.798:
  %t805 = call ptr @__alloc(i64 24, i32 2)
  %t806 = inttoptr i64 154 to ptr
  %t807 = getelementptr ptr, ptr %t805, i32 0
  store ptr %t806, ptr %t807
  call void @__inc_ref(ptr %t793)
  %t808 = getelementptr ptr, ptr %t805, i32 1
  store ptr %t793, ptr %t808
  call void @__inc_ref(ptr %t15)
  %t809 = getelementptr ptr, ptr %t805, i32 2
  store ptr %t15, ptr %t809
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.799
reuse.join.799:
  %t810 = phi ptr [ %t5, %reuse.in_place.797 ], [ %t805, %reuse.copy.798 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t793)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t810, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.67.811:
  %t812 = getelementptr ptr, ptr %t13, i32 1
  %t813 = load ptr, ptr %t812
  call void @__inc_ref(ptr %t813)
  %t814 = getelementptr i8, ptr %t5, i64 -8
  %t815 = load i32, ptr %t814
  %t816 = icmp eq i32 %t815, 1
  br i1 %t816, label %reuse.in_place.817, label %reuse.copy.818
reuse.in_place.817:
  %t820 = getelementptr ptr, ptr %t5, i32 1
  %t821 = load ptr, ptr %t820
  call void @__free_recursive(ptr %t821)
  %t823 = inttoptr i64 155 to ptr
  %t824 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t823, ptr %t824
  call void @__inc_ref(ptr %t813)
  %t822 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t813, ptr %t822
  br label %reuse.join.819
reuse.copy.818:
  %t825 = call ptr @__alloc(i64 24, i32 2)
  %t826 = inttoptr i64 155 to ptr
  %t827 = getelementptr ptr, ptr %t825, i32 0
  store ptr %t826, ptr %t827
  call void @__inc_ref(ptr %t813)
  %t828 = getelementptr ptr, ptr %t825, i32 1
  store ptr %t813, ptr %t828
  call void @__inc_ref(ptr %t15)
  %t829 = getelementptr ptr, ptr %t825, i32 2
  store ptr %t15, ptr %t829
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.819
reuse.join.819:
  %t830 = phi ptr [ %t5, %reuse.in_place.817 ], [ %t825, %reuse.copy.818 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t813)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t830, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.68.831:
  %t832 = getelementptr ptr, ptr %t13, i32 1
  %t833 = load ptr, ptr %t832
  call void @__inc_ref(ptr %t833)
  %t834 = getelementptr i8, ptr %t5, i64 -8
  %t835 = load i32, ptr %t834
  %t836 = icmp eq i32 %t835, 1
  br i1 %t836, label %reuse.in_place.837, label %reuse.copy.838
reuse.in_place.837:
  %t840 = getelementptr ptr, ptr %t5, i32 1
  %t841 = load ptr, ptr %t840
  call void @__free_recursive(ptr %t841)
  %t843 = inttoptr i64 156 to ptr
  %t844 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t843, ptr %t844
  call void @__inc_ref(ptr %t833)
  %t842 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t833, ptr %t842
  br label %reuse.join.839
reuse.copy.838:
  %t845 = call ptr @__alloc(i64 24, i32 2)
  %t846 = inttoptr i64 156 to ptr
  %t847 = getelementptr ptr, ptr %t845, i32 0
  store ptr %t846, ptr %t847
  call void @__inc_ref(ptr %t833)
  %t848 = getelementptr ptr, ptr %t845, i32 1
  store ptr %t833, ptr %t848
  call void @__inc_ref(ptr %t15)
  %t849 = getelementptr ptr, ptr %t845, i32 2
  store ptr %t15, ptr %t849
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.839
reuse.join.839:
  %t850 = phi ptr [ %t5, %reuse.in_place.837 ], [ %t845, %reuse.copy.838 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t833)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t850, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.69.851:
  %t852 = getelementptr ptr, ptr %t13, i32 1
  %t853 = load ptr, ptr %t852
  call void @__inc_ref(ptr %t853)
  %t854 = getelementptr i8, ptr %t5, i64 -8
  %t855 = load i32, ptr %t854
  %t856 = icmp eq i32 %t855, 1
  br i1 %t856, label %reuse.in_place.857, label %reuse.copy.858
reuse.in_place.857:
  %t860 = getelementptr ptr, ptr %t5, i32 1
  %t861 = load ptr, ptr %t860
  call void @__free_recursive(ptr %t861)
  %t863 = inttoptr i64 157 to ptr
  %t864 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t863, ptr %t864
  call void @__inc_ref(ptr %t853)
  %t862 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t853, ptr %t862
  br label %reuse.join.859
reuse.copy.858:
  %t865 = call ptr @__alloc(i64 24, i32 2)
  %t866 = inttoptr i64 157 to ptr
  %t867 = getelementptr ptr, ptr %t865, i32 0
  store ptr %t866, ptr %t867
  call void @__inc_ref(ptr %t853)
  %t868 = getelementptr ptr, ptr %t865, i32 1
  store ptr %t853, ptr %t868
  call void @__inc_ref(ptr %t15)
  %t869 = getelementptr ptr, ptr %t865, i32 2
  store ptr %t15, ptr %t869
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.859
reuse.join.859:
  %t870 = phi ptr [ %t5, %reuse.in_place.857 ], [ %t865, %reuse.copy.858 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t853)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t870, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.70.871:
  %t872 = getelementptr ptr, ptr %t13, i32 1
  %t873 = load ptr, ptr %t872
  call void @__inc_ref(ptr %t873)
  %t874 = getelementptr i8, ptr %t5, i64 -8
  %t875 = load i32, ptr %t874
  %t876 = icmp eq i32 %t875, 1
  br i1 %t876, label %reuse.in_place.877, label %reuse.copy.878
reuse.in_place.877:
  %t880 = getelementptr ptr, ptr %t5, i32 1
  %t881 = load ptr, ptr %t880
  call void @__free_recursive(ptr %t881)
  %t883 = inttoptr i64 158 to ptr
  %t884 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t883, ptr %t884
  call void @__inc_ref(ptr %t873)
  %t882 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t873, ptr %t882
  br label %reuse.join.879
reuse.copy.878:
  %t885 = call ptr @__alloc(i64 24, i32 2)
  %t886 = inttoptr i64 158 to ptr
  %t887 = getelementptr ptr, ptr %t885, i32 0
  store ptr %t886, ptr %t887
  call void @__inc_ref(ptr %t873)
  %t888 = getelementptr ptr, ptr %t885, i32 1
  store ptr %t873, ptr %t888
  call void @__inc_ref(ptr %t15)
  %t889 = getelementptr ptr, ptr %t885, i32 2
  store ptr %t15, ptr %t889
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.879
reuse.join.879:
  %t890 = phi ptr [ %t5, %reuse.in_place.877 ], [ %t885, %reuse.copy.878 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t873)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t890, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.71.891:
  %t892 = getelementptr ptr, ptr %t13, i32 1
  %t893 = load ptr, ptr %t892
  call void @__inc_ref(ptr %t893)
  %t894 = getelementptr i8, ptr %t5, i64 -8
  %t895 = load i32, ptr %t894
  %t896 = icmp eq i32 %t895, 1
  br i1 %t896, label %reuse.in_place.897, label %reuse.copy.898
reuse.in_place.897:
  %t900 = getelementptr ptr, ptr %t5, i32 1
  %t901 = load ptr, ptr %t900
  call void @__free_recursive(ptr %t901)
  %t903 = inttoptr i64 159 to ptr
  %t904 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t903, ptr %t904
  call void @__inc_ref(ptr %t893)
  %t902 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t893, ptr %t902
  br label %reuse.join.899
reuse.copy.898:
  %t905 = call ptr @__alloc(i64 24, i32 2)
  %t906 = inttoptr i64 159 to ptr
  %t907 = getelementptr ptr, ptr %t905, i32 0
  store ptr %t906, ptr %t907
  call void @__inc_ref(ptr %t893)
  %t908 = getelementptr ptr, ptr %t905, i32 1
  store ptr %t893, ptr %t908
  call void @__inc_ref(ptr %t15)
  %t909 = getelementptr ptr, ptr %t905, i32 2
  store ptr %t15, ptr %t909
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.899
reuse.join.899:
  %t910 = phi ptr [ %t5, %reuse.in_place.897 ], [ %t905, %reuse.copy.898 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t893)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t910, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.72.911:
  %t912 = getelementptr ptr, ptr %t13, i32 1
  %t913 = load ptr, ptr %t912
  call void @__inc_ref(ptr %t913)
  %t914 = getelementptr i8, ptr %t5, i64 -8
  %t915 = load i32, ptr %t914
  %t916 = icmp eq i32 %t915, 1
  br i1 %t916, label %reuse.in_place.917, label %reuse.copy.918
reuse.in_place.917:
  %t920 = getelementptr ptr, ptr %t5, i32 1
  %t921 = load ptr, ptr %t920
  call void @__free_recursive(ptr %t921)
  %t923 = inttoptr i64 160 to ptr
  %t924 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t923, ptr %t924
  call void @__inc_ref(ptr %t913)
  %t922 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t913, ptr %t922
  br label %reuse.join.919
reuse.copy.918:
  %t925 = call ptr @__alloc(i64 24, i32 2)
  %t926 = inttoptr i64 160 to ptr
  %t927 = getelementptr ptr, ptr %t925, i32 0
  store ptr %t926, ptr %t927
  call void @__inc_ref(ptr %t913)
  %t928 = getelementptr ptr, ptr %t925, i32 1
  store ptr %t913, ptr %t928
  call void @__inc_ref(ptr %t15)
  %t929 = getelementptr ptr, ptr %t925, i32 2
  store ptr %t15, ptr %t929
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.919
reuse.join.919:
  %t930 = phi ptr [ %t5, %reuse.in_place.917 ], [ %t925, %reuse.copy.918 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t913)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t930, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.73.931:
  %t932 = getelementptr ptr, ptr %t13, i32 1
  %t933 = load ptr, ptr %t932
  call void @__inc_ref(ptr %t933)
  %t934 = getelementptr i8, ptr %t5, i64 -8
  %t935 = load i32, ptr %t934
  %t936 = icmp eq i32 %t935, 1
  br i1 %t936, label %reuse.in_place.937, label %reuse.copy.938
reuse.in_place.937:
  %t940 = getelementptr ptr, ptr %t5, i32 1
  %t941 = load ptr, ptr %t940
  call void @__free_recursive(ptr %t941)
  %t943 = inttoptr i64 161 to ptr
  %t944 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t943, ptr %t944
  call void @__inc_ref(ptr %t933)
  %t942 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t933, ptr %t942
  br label %reuse.join.939
reuse.copy.938:
  %t945 = call ptr @__alloc(i64 24, i32 2)
  %t946 = inttoptr i64 161 to ptr
  %t947 = getelementptr ptr, ptr %t945, i32 0
  store ptr %t946, ptr %t947
  call void @__inc_ref(ptr %t933)
  %t948 = getelementptr ptr, ptr %t945, i32 1
  store ptr %t933, ptr %t948
  call void @__inc_ref(ptr %t15)
  %t949 = getelementptr ptr, ptr %t945, i32 2
  store ptr %t15, ptr %t949
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.939
reuse.join.939:
  %t950 = phi ptr [ %t5, %reuse.in_place.937 ], [ %t945, %reuse.copy.938 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t933)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t950, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.74.951:
  %t952 = getelementptr ptr, ptr %t13, i32 1
  %t953 = load ptr, ptr %t952
  call void @__inc_ref(ptr %t953)
  %t954 = getelementptr ptr, ptr %t13, i32 2
  %t955 = load ptr, ptr %t954
  call void @__inc_ref(ptr %t955)
  %t956 = call ptr @__alloc(i64 32, i32 3)
  %t957 = inttoptr i64 162 to ptr
  %t958 = getelementptr ptr, ptr %t956, i32 0
  store ptr %t957, ptr %t958
  call void @__inc_ref(ptr %t953)
  %t959 = getelementptr ptr, ptr %t956, i32 1
  store ptr %t953, ptr %t959
  call void @__inc_ref(ptr %t955)
  %t960 = getelementptr ptr, ptr %t956, i32 2
  store ptr %t955, ptr %t960
  call void @__inc_ref(ptr %t15)
  %t961 = getelementptr ptr, ptr %t956, i32 3
  store ptr %t15, ptr %t961
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t955)
  call void @__free_recursive(ptr %t953)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t956, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.75.962:
  %t963 = getelementptr ptr, ptr %t13, i32 1
  %t964 = load ptr, ptr %t963
  call void @__inc_ref(ptr %t964)
  %t965 = getelementptr i8, ptr %t5, i64 -8
  %t966 = load i32, ptr %t965
  %t967 = icmp eq i32 %t966, 1
  br i1 %t967, label %reuse.in_place.968, label %reuse.copy.969
reuse.in_place.968:
  %t971 = getelementptr ptr, ptr %t5, i32 1
  %t972 = load ptr, ptr %t971
  call void @__free_recursive(ptr %t972)
  %t974 = inttoptr i64 163 to ptr
  %t975 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t974, ptr %t975
  call void @__inc_ref(ptr %t964)
  %t973 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t964, ptr %t973
  br label %reuse.join.970
reuse.copy.969:
  %t976 = call ptr @__alloc(i64 24, i32 2)
  %t977 = inttoptr i64 163 to ptr
  %t978 = getelementptr ptr, ptr %t976, i32 0
  store ptr %t977, ptr %t978
  call void @__inc_ref(ptr %t964)
  %t979 = getelementptr ptr, ptr %t976, i32 1
  store ptr %t964, ptr %t979
  call void @__inc_ref(ptr %t15)
  %t980 = getelementptr ptr, ptr %t976, i32 2
  store ptr %t15, ptr %t980
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.970
reuse.join.970:
  %t981 = phi ptr [ %t5, %reuse.in_place.968 ], [ %t976, %reuse.copy.969 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t964)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t981, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.76.982:
  %t983 = getelementptr ptr, ptr %t13, i32 1
  %t984 = load ptr, ptr %t983
  call void @__inc_ref(ptr %t984)
  %t985 = getelementptr i8, ptr %t5, i64 -8
  %t986 = load i32, ptr %t985
  %t987 = icmp eq i32 %t986, 1
  br i1 %t987, label %reuse.in_place.988, label %reuse.copy.989
reuse.in_place.988:
  %t991 = getelementptr ptr, ptr %t5, i32 1
  %t992 = load ptr, ptr %t991
  call void @__free_recursive(ptr %t992)
  %t994 = inttoptr i64 164 to ptr
  %t995 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t994, ptr %t995
  call void @__inc_ref(ptr %t984)
  %t993 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t984, ptr %t993
  br label %reuse.join.990
reuse.copy.989:
  %t996 = call ptr @__alloc(i64 24, i32 2)
  %t997 = inttoptr i64 164 to ptr
  %t998 = getelementptr ptr, ptr %t996, i32 0
  store ptr %t997, ptr %t998
  call void @__inc_ref(ptr %t984)
  %t999 = getelementptr ptr, ptr %t996, i32 1
  store ptr %t984, ptr %t999
  call void @__inc_ref(ptr %t15)
  %t1000 = getelementptr ptr, ptr %t996, i32 2
  store ptr %t15, ptr %t1000
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.990
reuse.join.990:
  %t1001 = phi ptr [ %t5, %reuse.in_place.988 ], [ %t996, %reuse.copy.989 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t984)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1001, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.77.1002:
  %t1003 = getelementptr ptr, ptr %t13, i32 1
  %t1004 = load ptr, ptr %t1003
  call void @__inc_ref(ptr %t1004)
  %t1005 = getelementptr i8, ptr %t5, i64 -8
  %t1006 = load i32, ptr %t1005
  %t1007 = icmp eq i32 %t1006, 1
  br i1 %t1007, label %reuse.in_place.1008, label %reuse.copy.1009
reuse.in_place.1008:
  %t1011 = getelementptr ptr, ptr %t5, i32 1
  %t1012 = load ptr, ptr %t1011
  call void @__free_recursive(ptr %t1012)
  %t1014 = inttoptr i64 165 to ptr
  %t1015 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1014, ptr %t1015
  call void @__inc_ref(ptr %t1004)
  %t1013 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1004, ptr %t1013
  br label %reuse.join.1010
reuse.copy.1009:
  %t1016 = call ptr @__alloc(i64 24, i32 2)
  %t1017 = inttoptr i64 165 to ptr
  %t1018 = getelementptr ptr, ptr %t1016, i32 0
  store ptr %t1017, ptr %t1018
  call void @__inc_ref(ptr %t1004)
  %t1019 = getelementptr ptr, ptr %t1016, i32 1
  store ptr %t1004, ptr %t1019
  call void @__inc_ref(ptr %t15)
  %t1020 = getelementptr ptr, ptr %t1016, i32 2
  store ptr %t15, ptr %t1020
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1010
reuse.join.1010:
  %t1021 = phi ptr [ %t5, %reuse.in_place.1008 ], [ %t1016, %reuse.copy.1009 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1004)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1021, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.78.1022:
  %t1023 = getelementptr ptr, ptr %t13, i32 1
  %t1024 = load ptr, ptr %t1023
  call void @__inc_ref(ptr %t1024)
  %t1025 = getelementptr i8, ptr %t5, i64 -8
  %t1026 = load i32, ptr %t1025
  %t1027 = icmp eq i32 %t1026, 1
  br i1 %t1027, label %reuse.in_place.1028, label %reuse.copy.1029
reuse.in_place.1028:
  %t1031 = getelementptr ptr, ptr %t5, i32 1
  %t1032 = load ptr, ptr %t1031
  call void @__free_recursive(ptr %t1032)
  %t1034 = inttoptr i64 166 to ptr
  %t1035 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1034, ptr %t1035
  call void @__inc_ref(ptr %t1024)
  %t1033 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1024, ptr %t1033
  br label %reuse.join.1030
reuse.copy.1029:
  %t1036 = call ptr @__alloc(i64 24, i32 2)
  %t1037 = inttoptr i64 166 to ptr
  %t1038 = getelementptr ptr, ptr %t1036, i32 0
  store ptr %t1037, ptr %t1038
  call void @__inc_ref(ptr %t1024)
  %t1039 = getelementptr ptr, ptr %t1036, i32 1
  store ptr %t1024, ptr %t1039
  call void @__inc_ref(ptr %t15)
  %t1040 = getelementptr ptr, ptr %t1036, i32 2
  store ptr %t15, ptr %t1040
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1030
reuse.join.1030:
  %t1041 = phi ptr [ %t5, %reuse.in_place.1028 ], [ %t1036, %reuse.copy.1029 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1024)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1041, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.79.1042:
  %t1043 = getelementptr ptr, ptr %t13, i32 1
  %t1044 = load ptr, ptr %t1043
  call void @__inc_ref(ptr %t1044)
  %t1045 = getelementptr i8, ptr %t5, i64 -8
  %t1046 = load i32, ptr %t1045
  %t1047 = icmp eq i32 %t1046, 1
  br i1 %t1047, label %reuse.in_place.1048, label %reuse.copy.1049
reuse.in_place.1048:
  %t1051 = getelementptr ptr, ptr %t5, i32 1
  %t1052 = load ptr, ptr %t1051
  call void @__free_recursive(ptr %t1052)
  %t1054 = inttoptr i64 167 to ptr
  %t1055 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1054, ptr %t1055
  call void @__inc_ref(ptr %t1044)
  %t1053 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1044, ptr %t1053
  br label %reuse.join.1050
reuse.copy.1049:
  %t1056 = call ptr @__alloc(i64 24, i32 2)
  %t1057 = inttoptr i64 167 to ptr
  %t1058 = getelementptr ptr, ptr %t1056, i32 0
  store ptr %t1057, ptr %t1058
  call void @__inc_ref(ptr %t1044)
  %t1059 = getelementptr ptr, ptr %t1056, i32 1
  store ptr %t1044, ptr %t1059
  call void @__inc_ref(ptr %t15)
  %t1060 = getelementptr ptr, ptr %t1056, i32 2
  store ptr %t15, ptr %t1060
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1050
reuse.join.1050:
  %t1061 = phi ptr [ %t5, %reuse.in_place.1048 ], [ %t1056, %reuse.copy.1049 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1044)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1061, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.80.1062:
  %t1063 = getelementptr ptr, ptr %t13, i32 1
  %t1064 = load ptr, ptr %t1063
  call void @__inc_ref(ptr %t1064)
  %t1065 = getelementptr i8, ptr %t5, i64 -8
  %t1066 = load i32, ptr %t1065
  %t1067 = icmp eq i32 %t1066, 1
  br i1 %t1067, label %reuse.in_place.1068, label %reuse.copy.1069
reuse.in_place.1068:
  %t1071 = getelementptr ptr, ptr %t5, i32 1
  %t1072 = load ptr, ptr %t1071
  call void @__free_recursive(ptr %t1072)
  %t1074 = inttoptr i64 168 to ptr
  %t1075 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1074, ptr %t1075
  call void @__inc_ref(ptr %t1064)
  %t1073 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1064, ptr %t1073
  br label %reuse.join.1070
reuse.copy.1069:
  %t1076 = call ptr @__alloc(i64 24, i32 2)
  %t1077 = inttoptr i64 168 to ptr
  %t1078 = getelementptr ptr, ptr %t1076, i32 0
  store ptr %t1077, ptr %t1078
  call void @__inc_ref(ptr %t1064)
  %t1079 = getelementptr ptr, ptr %t1076, i32 1
  store ptr %t1064, ptr %t1079
  call void @__inc_ref(ptr %t15)
  %t1080 = getelementptr ptr, ptr %t1076, i32 2
  store ptr %t15, ptr %t1080
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1070
reuse.join.1070:
  %t1081 = phi ptr [ %t5, %reuse.in_place.1068 ], [ %t1076, %reuse.copy.1069 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1064)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1081, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.81.1082:
  %t1083 = getelementptr ptr, ptr %t13, i32 1
  %t1084 = load ptr, ptr %t1083
  call void @__inc_ref(ptr %t1084)
  %t1085 = getelementptr i8, ptr %t5, i64 -8
  %t1086 = load i32, ptr %t1085
  %t1087 = icmp eq i32 %t1086, 1
  br i1 %t1087, label %reuse.in_place.1088, label %reuse.copy.1089
reuse.in_place.1088:
  %t1091 = getelementptr ptr, ptr %t5, i32 1
  %t1092 = load ptr, ptr %t1091
  call void @__free_recursive(ptr %t1092)
  %t1094 = inttoptr i64 169 to ptr
  %t1095 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1094, ptr %t1095
  call void @__inc_ref(ptr %t1084)
  %t1093 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1084, ptr %t1093
  br label %reuse.join.1090
reuse.copy.1089:
  %t1096 = call ptr @__alloc(i64 24, i32 2)
  %t1097 = inttoptr i64 169 to ptr
  %t1098 = getelementptr ptr, ptr %t1096, i32 0
  store ptr %t1097, ptr %t1098
  call void @__inc_ref(ptr %t1084)
  %t1099 = getelementptr ptr, ptr %t1096, i32 1
  store ptr %t1084, ptr %t1099
  call void @__inc_ref(ptr %t15)
  %t1100 = getelementptr ptr, ptr %t1096, i32 2
  store ptr %t15, ptr %t1100
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1090
reuse.join.1090:
  %t1101 = phi ptr [ %t5, %reuse.in_place.1088 ], [ %t1096, %reuse.copy.1089 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1084)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1101, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.82.1102:
  %t1103 = getelementptr ptr, ptr %t13, i32 1
  %t1104 = load ptr, ptr %t1103
  call void @__inc_ref(ptr %t1104)
  %t1105 = getelementptr i8, ptr %t5, i64 -8
  %t1106 = load i32, ptr %t1105
  %t1107 = icmp eq i32 %t1106, 1
  br i1 %t1107, label %reuse.in_place.1108, label %reuse.copy.1109
reuse.in_place.1108:
  %t1111 = getelementptr ptr, ptr %t5, i32 1
  %t1112 = load ptr, ptr %t1111
  call void @__free_recursive(ptr %t1112)
  %t1114 = inttoptr i64 170 to ptr
  %t1115 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1114, ptr %t1115
  call void @__inc_ref(ptr %t1104)
  %t1113 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1104, ptr %t1113
  br label %reuse.join.1110
reuse.copy.1109:
  %t1116 = call ptr @__alloc(i64 24, i32 2)
  %t1117 = inttoptr i64 170 to ptr
  %t1118 = getelementptr ptr, ptr %t1116, i32 0
  store ptr %t1117, ptr %t1118
  call void @__inc_ref(ptr %t1104)
  %t1119 = getelementptr ptr, ptr %t1116, i32 1
  store ptr %t1104, ptr %t1119
  call void @__inc_ref(ptr %t15)
  %t1120 = getelementptr ptr, ptr %t1116, i32 2
  store ptr %t15, ptr %t1120
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1110
reuse.join.1110:
  %t1121 = phi ptr [ %t5, %reuse.in_place.1108 ], [ %t1116, %reuse.copy.1109 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1104)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1121, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.83.1122:
  %t1123 = getelementptr ptr, ptr %t13, i32 1
  %t1124 = load ptr, ptr %t1123
  call void @__inc_ref(ptr %t1124)
  %t1125 = getelementptr i8, ptr %t5, i64 -8
  %t1126 = load i32, ptr %t1125
  %t1127 = icmp eq i32 %t1126, 1
  br i1 %t1127, label %reuse.in_place.1128, label %reuse.copy.1129
reuse.in_place.1128:
  %t1131 = getelementptr ptr, ptr %t5, i32 1
  %t1132 = load ptr, ptr %t1131
  call void @__free_recursive(ptr %t1132)
  %t1134 = inttoptr i64 171 to ptr
  %t1135 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1134, ptr %t1135
  call void @__inc_ref(ptr %t1124)
  %t1133 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1124, ptr %t1133
  br label %reuse.join.1130
reuse.copy.1129:
  %t1136 = call ptr @__alloc(i64 24, i32 2)
  %t1137 = inttoptr i64 171 to ptr
  %t1138 = getelementptr ptr, ptr %t1136, i32 0
  store ptr %t1137, ptr %t1138
  call void @__inc_ref(ptr %t1124)
  %t1139 = getelementptr ptr, ptr %t1136, i32 1
  store ptr %t1124, ptr %t1139
  call void @__inc_ref(ptr %t15)
  %t1140 = getelementptr ptr, ptr %t1136, i32 2
  store ptr %t15, ptr %t1140
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1130
reuse.join.1130:
  %t1141 = phi ptr [ %t5, %reuse.in_place.1128 ], [ %t1136, %reuse.copy.1129 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1124)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1141, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.84.1142:
  %t1143 = getelementptr ptr, ptr %t13, i32 1
  %t1144 = load ptr, ptr %t1143
  call void @__inc_ref(ptr %t1144)
  %t1145 = getelementptr i8, ptr %t5, i64 -8
  %t1146 = load i32, ptr %t1145
  %t1147 = icmp eq i32 %t1146, 1
  br i1 %t1147, label %reuse.in_place.1148, label %reuse.copy.1149
reuse.in_place.1148:
  %t1151 = getelementptr ptr, ptr %t5, i32 1
  %t1152 = load ptr, ptr %t1151
  call void @__free_recursive(ptr %t1152)
  %t1154 = inttoptr i64 172 to ptr
  %t1155 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1154, ptr %t1155
  call void @__inc_ref(ptr %t1144)
  %t1153 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1144, ptr %t1153
  br label %reuse.join.1150
reuse.copy.1149:
  %t1156 = call ptr @__alloc(i64 24, i32 2)
  %t1157 = inttoptr i64 172 to ptr
  %t1158 = getelementptr ptr, ptr %t1156, i32 0
  store ptr %t1157, ptr %t1158
  call void @__inc_ref(ptr %t1144)
  %t1159 = getelementptr ptr, ptr %t1156, i32 1
  store ptr %t1144, ptr %t1159
  call void @__inc_ref(ptr %t15)
  %t1160 = getelementptr ptr, ptr %t1156, i32 2
  store ptr %t15, ptr %t1160
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1150
reuse.join.1150:
  %t1161 = phi ptr [ %t5, %reuse.in_place.1148 ], [ %t1156, %reuse.copy.1149 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1144)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1161, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.85.1162:
  %t1163 = getelementptr ptr, ptr %t13, i32 1
  %t1164 = load ptr, ptr %t1163
  call void @__inc_ref(ptr %t1164)
  %t1165 = getelementptr i8, ptr %t5, i64 -8
  %t1166 = load i32, ptr %t1165
  %t1167 = icmp eq i32 %t1166, 1
  br i1 %t1167, label %reuse.in_place.1168, label %reuse.copy.1169
reuse.in_place.1168:
  %t1171 = getelementptr ptr, ptr %t5, i32 1
  %t1172 = load ptr, ptr %t1171
  call void @__free_recursive(ptr %t1172)
  %t1174 = inttoptr i64 173 to ptr
  %t1175 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1174, ptr %t1175
  call void @__inc_ref(ptr %t1164)
  %t1173 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1164, ptr %t1173
  br label %reuse.join.1170
reuse.copy.1169:
  %t1176 = call ptr @__alloc(i64 24, i32 2)
  %t1177 = inttoptr i64 173 to ptr
  %t1178 = getelementptr ptr, ptr %t1176, i32 0
  store ptr %t1177, ptr %t1178
  call void @__inc_ref(ptr %t1164)
  %t1179 = getelementptr ptr, ptr %t1176, i32 1
  store ptr %t1164, ptr %t1179
  call void @__inc_ref(ptr %t15)
  %t1180 = getelementptr ptr, ptr %t1176, i32 2
  store ptr %t15, ptr %t1180
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1170
reuse.join.1170:
  %t1181 = phi ptr [ %t5, %reuse.in_place.1168 ], [ %t1176, %reuse.copy.1169 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1164)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1181, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.86.1182:
  %t1183 = getelementptr ptr, ptr %t13, i32 1
  %t1184 = load ptr, ptr %t1183
  call void @__inc_ref(ptr %t1184)
  %t1185 = getelementptr i8, ptr %t5, i64 -8
  %t1186 = load i32, ptr %t1185
  %t1187 = icmp eq i32 %t1186, 1
  br i1 %t1187, label %reuse.in_place.1188, label %reuse.copy.1189
reuse.in_place.1188:
  %t1191 = getelementptr ptr, ptr %t5, i32 1
  %t1192 = load ptr, ptr %t1191
  call void @__free_recursive(ptr %t1192)
  %t1194 = inttoptr i64 174 to ptr
  %t1195 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1194, ptr %t1195
  call void @__inc_ref(ptr %t1184)
  %t1193 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1184, ptr %t1193
  br label %reuse.join.1190
reuse.copy.1189:
  %t1196 = call ptr @__alloc(i64 24, i32 2)
  %t1197 = inttoptr i64 174 to ptr
  %t1198 = getelementptr ptr, ptr %t1196, i32 0
  store ptr %t1197, ptr %t1198
  call void @__inc_ref(ptr %t1184)
  %t1199 = getelementptr ptr, ptr %t1196, i32 1
  store ptr %t1184, ptr %t1199
  call void @__inc_ref(ptr %t15)
  %t1200 = getelementptr ptr, ptr %t1196, i32 2
  store ptr %t15, ptr %t1200
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1190
reuse.join.1190:
  %t1201 = phi ptr [ %t5, %reuse.in_place.1188 ], [ %t1196, %reuse.copy.1189 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1184)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1201, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.87.1202:
  %t1203 = getelementptr ptr, ptr %t13, i32 1
  %t1204 = load ptr, ptr %t1203
  call void @__inc_ref(ptr %t1204)
  %t1205 = getelementptr ptr, ptr %t13, i32 2
  %t1206 = load ptr, ptr %t1205
  call void @__inc_ref(ptr %t1206)
  %t1207 = call ptr @__alloc(i64 32, i32 3)
  %t1208 = inttoptr i64 175 to ptr
  %t1209 = getelementptr ptr, ptr %t1207, i32 0
  store ptr %t1208, ptr %t1209
  call void @__inc_ref(ptr %t1204)
  %t1210 = getelementptr ptr, ptr %t1207, i32 1
  store ptr %t1204, ptr %t1210
  call void @__inc_ref(ptr %t1206)
  %t1211 = getelementptr ptr, ptr %t1207, i32 2
  store ptr %t1206, ptr %t1211
  call void @__inc_ref(ptr %t15)
  %t1212 = getelementptr ptr, ptr %t1207, i32 3
  store ptr %t15, ptr %t1212
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t1206)
  call void @__free_recursive(ptr %t1204)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1207, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.88.1213:
  %t1214 = getelementptr ptr, ptr %t13, i32 1
  %t1215 = load ptr, ptr %t1214
  call void @__inc_ref(ptr %t1215)
  %t1216 = getelementptr i8, ptr %t5, i64 -8
  %t1217 = load i32, ptr %t1216
  %t1218 = icmp eq i32 %t1217, 1
  br i1 %t1218, label %reuse.in_place.1219, label %reuse.copy.1220
reuse.in_place.1219:
  %t1222 = getelementptr ptr, ptr %t5, i32 1
  %t1223 = load ptr, ptr %t1222
  call void @__free_recursive(ptr %t1223)
  %t1225 = inttoptr i64 176 to ptr
  %t1226 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1225, ptr %t1226
  call void @__inc_ref(ptr %t1215)
  %t1224 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1215, ptr %t1224
  br label %reuse.join.1221
reuse.copy.1220:
  %t1227 = call ptr @__alloc(i64 24, i32 2)
  %t1228 = inttoptr i64 176 to ptr
  %t1229 = getelementptr ptr, ptr %t1227, i32 0
  store ptr %t1228, ptr %t1229
  call void @__inc_ref(ptr %t1215)
  %t1230 = getelementptr ptr, ptr %t1227, i32 1
  store ptr %t1215, ptr %t1230
  call void @__inc_ref(ptr %t15)
  %t1231 = getelementptr ptr, ptr %t1227, i32 2
  store ptr %t15, ptr %t1231
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1221
reuse.join.1221:
  %t1232 = phi ptr [ %t5, %reuse.in_place.1219 ], [ %t1227, %reuse.copy.1220 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1215)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1232, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.89.1233:
  %t1234 = getelementptr ptr, ptr %t13, i32 1
  %t1235 = load ptr, ptr %t1234
  call void @__inc_ref(ptr %t1235)
  %t1236 = getelementptr i8, ptr %t5, i64 -8
  %t1237 = load i32, ptr %t1236
  %t1238 = icmp eq i32 %t1237, 1
  br i1 %t1238, label %reuse.in_place.1239, label %reuse.copy.1240
reuse.in_place.1239:
  %t1242 = getelementptr ptr, ptr %t5, i32 1
  %t1243 = load ptr, ptr %t1242
  call void @__free_recursive(ptr %t1243)
  %t1245 = inttoptr i64 177 to ptr
  %t1246 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1245, ptr %t1246
  call void @__inc_ref(ptr %t1235)
  %t1244 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1235, ptr %t1244
  br label %reuse.join.1241
reuse.copy.1240:
  %t1247 = call ptr @__alloc(i64 24, i32 2)
  %t1248 = inttoptr i64 177 to ptr
  %t1249 = getelementptr ptr, ptr %t1247, i32 0
  store ptr %t1248, ptr %t1249
  call void @__inc_ref(ptr %t1235)
  %t1250 = getelementptr ptr, ptr %t1247, i32 1
  store ptr %t1235, ptr %t1250
  call void @__inc_ref(ptr %t15)
  %t1251 = getelementptr ptr, ptr %t1247, i32 2
  store ptr %t15, ptr %t1251
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1241
reuse.join.1241:
  %t1252 = phi ptr [ %t5, %reuse.in_place.1239 ], [ %t1247, %reuse.copy.1240 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1235)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1252, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.90.1253:
  %t1254 = getelementptr ptr, ptr %t13, i32 1
  %t1255 = load ptr, ptr %t1254
  call void @__inc_ref(ptr %t1255)
  %t1256 = getelementptr i8, ptr %t5, i64 -8
  %t1257 = load i32, ptr %t1256
  %t1258 = icmp eq i32 %t1257, 1
  br i1 %t1258, label %reuse.in_place.1259, label %reuse.copy.1260
reuse.in_place.1259:
  %t1262 = getelementptr ptr, ptr %t5, i32 1
  %t1263 = load ptr, ptr %t1262
  call void @__free_recursive(ptr %t1263)
  %t1265 = inttoptr i64 178 to ptr
  %t1266 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1265, ptr %t1266
  call void @__inc_ref(ptr %t1255)
  %t1264 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1255, ptr %t1264
  br label %reuse.join.1261
reuse.copy.1260:
  %t1267 = call ptr @__alloc(i64 24, i32 2)
  %t1268 = inttoptr i64 178 to ptr
  %t1269 = getelementptr ptr, ptr %t1267, i32 0
  store ptr %t1268, ptr %t1269
  call void @__inc_ref(ptr %t1255)
  %t1270 = getelementptr ptr, ptr %t1267, i32 1
  store ptr %t1255, ptr %t1270
  call void @__inc_ref(ptr %t15)
  %t1271 = getelementptr ptr, ptr %t1267, i32 2
  store ptr %t15, ptr %t1271
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1261
reuse.join.1261:
  %t1272 = phi ptr [ %t5, %reuse.in_place.1259 ], [ %t1267, %reuse.copy.1260 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1255)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1272, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.91.1273:
  %t1274 = getelementptr ptr, ptr %t13, i32 1
  %t1275 = load ptr, ptr %t1274
  call void @__inc_ref(ptr %t1275)
  %t1276 = getelementptr i8, ptr %t5, i64 -8
  %t1277 = load i32, ptr %t1276
  %t1278 = icmp eq i32 %t1277, 1
  br i1 %t1278, label %reuse.in_place.1279, label %reuse.copy.1280
reuse.in_place.1279:
  %t1282 = getelementptr ptr, ptr %t5, i32 1
  %t1283 = load ptr, ptr %t1282
  call void @__free_recursive(ptr %t1283)
  %t1285 = inttoptr i64 179 to ptr
  %t1286 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1285, ptr %t1286
  call void @__inc_ref(ptr %t1275)
  %t1284 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1275, ptr %t1284
  br label %reuse.join.1281
reuse.copy.1280:
  %t1287 = call ptr @__alloc(i64 24, i32 2)
  %t1288 = inttoptr i64 179 to ptr
  %t1289 = getelementptr ptr, ptr %t1287, i32 0
  store ptr %t1288, ptr %t1289
  call void @__inc_ref(ptr %t1275)
  %t1290 = getelementptr ptr, ptr %t1287, i32 1
  store ptr %t1275, ptr %t1290
  call void @__inc_ref(ptr %t15)
  %t1291 = getelementptr ptr, ptr %t1287, i32 2
  store ptr %t15, ptr %t1291
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1281
reuse.join.1281:
  %t1292 = phi ptr [ %t5, %reuse.in_place.1279 ], [ %t1287, %reuse.copy.1280 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1275)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1292, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.92.1293:
  %t1294 = getelementptr ptr, ptr %t13, i32 1
  %t1295 = load ptr, ptr %t1294
  call void @__inc_ref(ptr %t1295)
  %t1296 = getelementptr i8, ptr %t5, i64 -8
  %t1297 = load i32, ptr %t1296
  %t1298 = icmp eq i32 %t1297, 1
  br i1 %t1298, label %reuse.in_place.1299, label %reuse.copy.1300
reuse.in_place.1299:
  %t1302 = getelementptr ptr, ptr %t5, i32 1
  %t1303 = load ptr, ptr %t1302
  call void @__free_recursive(ptr %t1303)
  %t1305 = inttoptr i64 180 to ptr
  %t1306 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1305, ptr %t1306
  call void @__inc_ref(ptr %t1295)
  %t1304 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1295, ptr %t1304
  br label %reuse.join.1301
reuse.copy.1300:
  %t1307 = call ptr @__alloc(i64 24, i32 2)
  %t1308 = inttoptr i64 180 to ptr
  %t1309 = getelementptr ptr, ptr %t1307, i32 0
  store ptr %t1308, ptr %t1309
  call void @__inc_ref(ptr %t1295)
  %t1310 = getelementptr ptr, ptr %t1307, i32 1
  store ptr %t1295, ptr %t1310
  call void @__inc_ref(ptr %t15)
  %t1311 = getelementptr ptr, ptr %t1307, i32 2
  store ptr %t15, ptr %t1311
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1301
reuse.join.1301:
  %t1312 = phi ptr [ %t5, %reuse.in_place.1299 ], [ %t1307, %reuse.copy.1300 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1295)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1312, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.93.1313:
  %t1314 = getelementptr ptr, ptr %t13, i32 1
  %t1315 = load ptr, ptr %t1314
  call void @__inc_ref(ptr %t1315)
  %t1316 = getelementptr i8, ptr %t5, i64 -8
  %t1317 = load i32, ptr %t1316
  %t1318 = icmp eq i32 %t1317, 1
  br i1 %t1318, label %reuse.in_place.1319, label %reuse.copy.1320
reuse.in_place.1319:
  %t1322 = getelementptr ptr, ptr %t5, i32 1
  %t1323 = load ptr, ptr %t1322
  call void @__free_recursive(ptr %t1323)
  %t1325 = inttoptr i64 181 to ptr
  %t1326 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1325, ptr %t1326
  call void @__inc_ref(ptr %t1315)
  %t1324 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1315, ptr %t1324
  br label %reuse.join.1321
reuse.copy.1320:
  %t1327 = call ptr @__alloc(i64 24, i32 2)
  %t1328 = inttoptr i64 181 to ptr
  %t1329 = getelementptr ptr, ptr %t1327, i32 0
  store ptr %t1328, ptr %t1329
  call void @__inc_ref(ptr %t1315)
  %t1330 = getelementptr ptr, ptr %t1327, i32 1
  store ptr %t1315, ptr %t1330
  call void @__inc_ref(ptr %t15)
  %t1331 = getelementptr ptr, ptr %t1327, i32 2
  store ptr %t15, ptr %t1331
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1321
reuse.join.1321:
  %t1332 = phi ptr [ %t5, %reuse.in_place.1319 ], [ %t1327, %reuse.copy.1320 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1315)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1332, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.94.1333:
  %t1334 = getelementptr ptr, ptr %t13, i32 1
  %t1335 = load ptr, ptr %t1334
  call void @__inc_ref(ptr %t1335)
  %t1336 = getelementptr i8, ptr %t5, i64 -8
  %t1337 = load i32, ptr %t1336
  %t1338 = icmp eq i32 %t1337, 1
  br i1 %t1338, label %reuse.in_place.1339, label %reuse.copy.1340
reuse.in_place.1339:
  %t1342 = getelementptr ptr, ptr %t5, i32 1
  %t1343 = load ptr, ptr %t1342
  call void @__free_recursive(ptr %t1343)
  %t1345 = inttoptr i64 182 to ptr
  %t1346 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1345, ptr %t1346
  call void @__inc_ref(ptr %t1335)
  %t1344 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1335, ptr %t1344
  br label %reuse.join.1341
reuse.copy.1340:
  %t1347 = call ptr @__alloc(i64 24, i32 2)
  %t1348 = inttoptr i64 182 to ptr
  %t1349 = getelementptr ptr, ptr %t1347, i32 0
  store ptr %t1348, ptr %t1349
  call void @__inc_ref(ptr %t1335)
  %t1350 = getelementptr ptr, ptr %t1347, i32 1
  store ptr %t1335, ptr %t1350
  call void @__inc_ref(ptr %t15)
  %t1351 = getelementptr ptr, ptr %t1347, i32 2
  store ptr %t15, ptr %t1351
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1341
reuse.join.1341:
  %t1352 = phi ptr [ %t5, %reuse.in_place.1339 ], [ %t1347, %reuse.copy.1340 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1335)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1352, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.95.1353:
  %t1354 = getelementptr ptr, ptr %t13, i32 1
  %t1355 = load ptr, ptr %t1354
  call void @__inc_ref(ptr %t1355)
  %t1356 = getelementptr i8, ptr %t5, i64 -8
  %t1357 = load i32, ptr %t1356
  %t1358 = icmp eq i32 %t1357, 1
  br i1 %t1358, label %reuse.in_place.1359, label %reuse.copy.1360
reuse.in_place.1359:
  %t1362 = getelementptr ptr, ptr %t5, i32 1
  %t1363 = load ptr, ptr %t1362
  call void @__free_recursive(ptr %t1363)
  %t1365 = inttoptr i64 183 to ptr
  %t1366 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1365, ptr %t1366
  call void @__inc_ref(ptr %t1355)
  %t1364 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1355, ptr %t1364
  br label %reuse.join.1361
reuse.copy.1360:
  %t1367 = call ptr @__alloc(i64 24, i32 2)
  %t1368 = inttoptr i64 183 to ptr
  %t1369 = getelementptr ptr, ptr %t1367, i32 0
  store ptr %t1368, ptr %t1369
  call void @__inc_ref(ptr %t1355)
  %t1370 = getelementptr ptr, ptr %t1367, i32 1
  store ptr %t1355, ptr %t1370
  call void @__inc_ref(ptr %t15)
  %t1371 = getelementptr ptr, ptr %t1367, i32 2
  store ptr %t15, ptr %t1371
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1361
reuse.join.1361:
  %t1372 = phi ptr [ %t5, %reuse.in_place.1359 ], [ %t1367, %reuse.copy.1360 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1355)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1372, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.96.1373:
  %t1374 = getelementptr ptr, ptr %t13, i32 1
  %t1375 = load ptr, ptr %t1374
  call void @__inc_ref(ptr %t1375)
  %t1376 = getelementptr i8, ptr %t5, i64 -8
  %t1377 = load i32, ptr %t1376
  %t1378 = icmp eq i32 %t1377, 1
  br i1 %t1378, label %reuse.in_place.1379, label %reuse.copy.1380
reuse.in_place.1379:
  %t1382 = getelementptr ptr, ptr %t5, i32 1
  %t1383 = load ptr, ptr %t1382
  call void @__free_recursive(ptr %t1383)
  %t1385 = inttoptr i64 184 to ptr
  %t1386 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1385, ptr %t1386
  call void @__inc_ref(ptr %t1375)
  %t1384 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1375, ptr %t1384
  br label %reuse.join.1381
reuse.copy.1380:
  %t1387 = call ptr @__alloc(i64 24, i32 2)
  %t1388 = inttoptr i64 184 to ptr
  %t1389 = getelementptr ptr, ptr %t1387, i32 0
  store ptr %t1388, ptr %t1389
  call void @__inc_ref(ptr %t1375)
  %t1390 = getelementptr ptr, ptr %t1387, i32 1
  store ptr %t1375, ptr %t1390
  call void @__inc_ref(ptr %t15)
  %t1391 = getelementptr ptr, ptr %t1387, i32 2
  store ptr %t15, ptr %t1391
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1381
reuse.join.1381:
  %t1392 = phi ptr [ %t5, %reuse.in_place.1379 ], [ %t1387, %reuse.copy.1380 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1375)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1392, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.97.1393:
  %t1394 = getelementptr ptr, ptr %t13, i32 1
  %t1395 = load ptr, ptr %t1394
  call void @__inc_ref(ptr %t1395)
  %t1396 = getelementptr i8, ptr %t5, i64 -8
  %t1397 = load i32, ptr %t1396
  %t1398 = icmp eq i32 %t1397, 1
  br i1 %t1398, label %reuse.in_place.1399, label %reuse.copy.1400
reuse.in_place.1399:
  %t1402 = getelementptr ptr, ptr %t5, i32 1
  %t1403 = load ptr, ptr %t1402
  call void @__free_recursive(ptr %t1403)
  %t1405 = inttoptr i64 185 to ptr
  %t1406 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1405, ptr %t1406
  call void @__inc_ref(ptr %t1395)
  %t1404 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1395, ptr %t1404
  br label %reuse.join.1401
reuse.copy.1400:
  %t1407 = call ptr @__alloc(i64 24, i32 2)
  %t1408 = inttoptr i64 185 to ptr
  %t1409 = getelementptr ptr, ptr %t1407, i32 0
  store ptr %t1408, ptr %t1409
  call void @__inc_ref(ptr %t1395)
  %t1410 = getelementptr ptr, ptr %t1407, i32 1
  store ptr %t1395, ptr %t1410
  call void @__inc_ref(ptr %t15)
  %t1411 = getelementptr ptr, ptr %t1407, i32 2
  store ptr %t15, ptr %t1411
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1401
reuse.join.1401:
  %t1412 = phi ptr [ %t5, %reuse.in_place.1399 ], [ %t1407, %reuse.copy.1400 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1395)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1412, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.98.1413:
  %t1414 = getelementptr ptr, ptr %t13, i32 1
  %t1415 = load ptr, ptr %t1414
  call void @__inc_ref(ptr %t1415)
  %t1416 = getelementptr i8, ptr %t5, i64 -8
  %t1417 = load i32, ptr %t1416
  %t1418 = icmp eq i32 %t1417, 1
  br i1 %t1418, label %reuse.in_place.1419, label %reuse.copy.1420
reuse.in_place.1419:
  %t1422 = getelementptr ptr, ptr %t5, i32 1
  %t1423 = load ptr, ptr %t1422
  call void @__free_recursive(ptr %t1423)
  %t1425 = inttoptr i64 186 to ptr
  %t1426 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1425, ptr %t1426
  call void @__inc_ref(ptr %t1415)
  %t1424 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1415, ptr %t1424
  br label %reuse.join.1421
reuse.copy.1420:
  %t1427 = call ptr @__alloc(i64 24, i32 2)
  %t1428 = inttoptr i64 186 to ptr
  %t1429 = getelementptr ptr, ptr %t1427, i32 0
  store ptr %t1428, ptr %t1429
  call void @__inc_ref(ptr %t1415)
  %t1430 = getelementptr ptr, ptr %t1427, i32 1
  store ptr %t1415, ptr %t1430
  call void @__inc_ref(ptr %t15)
  %t1431 = getelementptr ptr, ptr %t1427, i32 2
  store ptr %t15, ptr %t1431
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1421
reuse.join.1421:
  %t1432 = phi ptr [ %t5, %reuse.in_place.1419 ], [ %t1427, %reuse.copy.1420 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1415)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1432, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.99.1433:
  %t1434 = getelementptr ptr, ptr %t13, i32 1
  %t1435 = load ptr, ptr %t1434
  call void @__inc_ref(ptr %t1435)
  %t1436 = getelementptr i8, ptr %t5, i64 -8
  %t1437 = load i32, ptr %t1436
  %t1438 = icmp eq i32 %t1437, 1
  br i1 %t1438, label %reuse.in_place.1439, label %reuse.copy.1440
reuse.in_place.1439:
  %t1442 = getelementptr ptr, ptr %t5, i32 1
  %t1443 = load ptr, ptr %t1442
  call void @__free_recursive(ptr %t1443)
  %t1445 = inttoptr i64 187 to ptr
  %t1446 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1445, ptr %t1446
  call void @__inc_ref(ptr %t1435)
  %t1444 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1435, ptr %t1444
  br label %reuse.join.1441
reuse.copy.1440:
  %t1447 = call ptr @__alloc(i64 24, i32 2)
  %t1448 = inttoptr i64 187 to ptr
  %t1449 = getelementptr ptr, ptr %t1447, i32 0
  store ptr %t1448, ptr %t1449
  call void @__inc_ref(ptr %t1435)
  %t1450 = getelementptr ptr, ptr %t1447, i32 1
  store ptr %t1435, ptr %t1450
  call void @__inc_ref(ptr %t15)
  %t1451 = getelementptr ptr, ptr %t1447, i32 2
  store ptr %t15, ptr %t1451
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1441
reuse.join.1441:
  %t1452 = phi ptr [ %t5, %reuse.in_place.1439 ], [ %t1447, %reuse.copy.1440 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1435)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1452, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.100.1453:
  %t1454 = getelementptr ptr, ptr %t13, i32 1
  %t1455 = load ptr, ptr %t1454
  call void @__inc_ref(ptr %t1455)
  %t1456 = getelementptr i8, ptr %t5, i64 -8
  %t1457 = load i32, ptr %t1456
  %t1458 = icmp eq i32 %t1457, 1
  br i1 %t1458, label %reuse.in_place.1459, label %reuse.copy.1460
reuse.in_place.1459:
  %t1462 = getelementptr ptr, ptr %t5, i32 1
  %t1463 = load ptr, ptr %t1462
  call void @__free_recursive(ptr %t1463)
  %t1465 = inttoptr i64 188 to ptr
  %t1466 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1465, ptr %t1466
  call void @__inc_ref(ptr %t1455)
  %t1464 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1455, ptr %t1464
  br label %reuse.join.1461
reuse.copy.1460:
  %t1467 = call ptr @__alloc(i64 24, i32 2)
  %t1468 = inttoptr i64 188 to ptr
  %t1469 = getelementptr ptr, ptr %t1467, i32 0
  store ptr %t1468, ptr %t1469
  call void @__inc_ref(ptr %t1455)
  %t1470 = getelementptr ptr, ptr %t1467, i32 1
  store ptr %t1455, ptr %t1470
  call void @__inc_ref(ptr %t15)
  %t1471 = getelementptr ptr, ptr %t1467, i32 2
  store ptr %t15, ptr %t1471
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1461
reuse.join.1461:
  %t1472 = phi ptr [ %t5, %reuse.in_place.1459 ], [ %t1467, %reuse.copy.1460 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1455)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1472, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.101.1473:
  %t1474 = getelementptr ptr, ptr %t13, i32 1
  %t1475 = load ptr, ptr %t1474
  call void @__inc_ref(ptr %t1475)
  %t1476 = getelementptr i8, ptr %t5, i64 -8
  %t1477 = load i32, ptr %t1476
  %t1478 = icmp eq i32 %t1477, 1
  br i1 %t1478, label %reuse.in_place.1479, label %reuse.copy.1480
reuse.in_place.1479:
  %t1482 = getelementptr ptr, ptr %t5, i32 1
  %t1483 = load ptr, ptr %t1482
  call void @__free_recursive(ptr %t1483)
  %t1485 = inttoptr i64 189 to ptr
  %t1486 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1485, ptr %t1486
  call void @__inc_ref(ptr %t1475)
  %t1484 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1475, ptr %t1484
  br label %reuse.join.1481
reuse.copy.1480:
  %t1487 = call ptr @__alloc(i64 24, i32 2)
  %t1488 = inttoptr i64 189 to ptr
  %t1489 = getelementptr ptr, ptr %t1487, i32 0
  store ptr %t1488, ptr %t1489
  call void @__inc_ref(ptr %t1475)
  %t1490 = getelementptr ptr, ptr %t1487, i32 1
  store ptr %t1475, ptr %t1490
  call void @__inc_ref(ptr %t15)
  %t1491 = getelementptr ptr, ptr %t1487, i32 2
  store ptr %t15, ptr %t1491
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1481
reuse.join.1481:
  %t1492 = phi ptr [ %t5, %reuse.in_place.1479 ], [ %t1487, %reuse.copy.1480 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1475)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1492, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.102.1493:
  %t1494 = getelementptr ptr, ptr %t13, i32 1
  %t1495 = load ptr, ptr %t1494
  call void @__inc_ref(ptr %t1495)
  %t1496 = getelementptr i8, ptr %t5, i64 -8
  %t1497 = load i32, ptr %t1496
  %t1498 = icmp eq i32 %t1497, 1
  br i1 %t1498, label %reuse.in_place.1499, label %reuse.copy.1500
reuse.in_place.1499:
  %t1502 = getelementptr ptr, ptr %t5, i32 1
  %t1503 = load ptr, ptr %t1502
  call void @__free_recursive(ptr %t1503)
  %t1505 = inttoptr i64 190 to ptr
  %t1506 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1505, ptr %t1506
  call void @__inc_ref(ptr %t1495)
  %t1504 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1495, ptr %t1504
  br label %reuse.join.1501
reuse.copy.1500:
  %t1507 = call ptr @__alloc(i64 24, i32 2)
  %t1508 = inttoptr i64 190 to ptr
  %t1509 = getelementptr ptr, ptr %t1507, i32 0
  store ptr %t1508, ptr %t1509
  call void @__inc_ref(ptr %t1495)
  %t1510 = getelementptr ptr, ptr %t1507, i32 1
  store ptr %t1495, ptr %t1510
  call void @__inc_ref(ptr %t15)
  %t1511 = getelementptr ptr, ptr %t1507, i32 2
  store ptr %t15, ptr %t1511
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1501
reuse.join.1501:
  %t1512 = phi ptr [ %t5, %reuse.in_place.1499 ], [ %t1507, %reuse.copy.1500 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1495)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1512, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.103.1513:
  %t1514 = getelementptr ptr, ptr %t13, i32 1
  %t1515 = load ptr, ptr %t1514
  call void @__inc_ref(ptr %t1515)
  %t1516 = getelementptr i8, ptr %t5, i64 -8
  %t1517 = load i32, ptr %t1516
  %t1518 = icmp eq i32 %t1517, 1
  br i1 %t1518, label %reuse.in_place.1519, label %reuse.copy.1520
reuse.in_place.1519:
  %t1522 = getelementptr ptr, ptr %t5, i32 1
  %t1523 = load ptr, ptr %t1522
  call void @__free_recursive(ptr %t1523)
  %t1525 = inttoptr i64 191 to ptr
  %t1526 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1525, ptr %t1526
  call void @__inc_ref(ptr %t1515)
  %t1524 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1515, ptr %t1524
  br label %reuse.join.1521
reuse.copy.1520:
  %t1527 = call ptr @__alloc(i64 24, i32 2)
  %t1528 = inttoptr i64 191 to ptr
  %t1529 = getelementptr ptr, ptr %t1527, i32 0
  store ptr %t1528, ptr %t1529
  call void @__inc_ref(ptr %t1515)
  %t1530 = getelementptr ptr, ptr %t1527, i32 1
  store ptr %t1515, ptr %t1530
  call void @__inc_ref(ptr %t15)
  %t1531 = getelementptr ptr, ptr %t1527, i32 2
  store ptr %t15, ptr %t1531
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1521
reuse.join.1521:
  %t1532 = phi ptr [ %t5, %reuse.in_place.1519 ], [ %t1527, %reuse.copy.1520 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1515)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1532, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.104.1533:
  %t1534 = getelementptr ptr, ptr %t13, i32 1
  %t1535 = load ptr, ptr %t1534
  call void @__inc_ref(ptr %t1535)
  %t1536 = getelementptr i8, ptr %t5, i64 -8
  %t1537 = load i32, ptr %t1536
  %t1538 = icmp eq i32 %t1537, 1
  br i1 %t1538, label %reuse.in_place.1539, label %reuse.copy.1540
reuse.in_place.1539:
  %t1542 = getelementptr ptr, ptr %t5, i32 1
  %t1543 = load ptr, ptr %t1542
  call void @__free_recursive(ptr %t1543)
  %t1545 = inttoptr i64 192 to ptr
  %t1546 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1545, ptr %t1546
  call void @__inc_ref(ptr %t1535)
  %t1544 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1535, ptr %t1544
  br label %reuse.join.1541
reuse.copy.1540:
  %t1547 = call ptr @__alloc(i64 24, i32 2)
  %t1548 = inttoptr i64 192 to ptr
  %t1549 = getelementptr ptr, ptr %t1547, i32 0
  store ptr %t1548, ptr %t1549
  call void @__inc_ref(ptr %t1535)
  %t1550 = getelementptr ptr, ptr %t1547, i32 1
  store ptr %t1535, ptr %t1550
  call void @__inc_ref(ptr %t15)
  %t1551 = getelementptr ptr, ptr %t1547, i32 2
  store ptr %t15, ptr %t1551
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1541
reuse.join.1541:
  %t1552 = phi ptr [ %t5, %reuse.in_place.1539 ], [ %t1547, %reuse.copy.1540 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1535)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1552, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.105.1553:
  %t1554 = getelementptr ptr, ptr %t13, i32 1
  %t1555 = load ptr, ptr %t1554
  call void @__inc_ref(ptr %t1555)
  %t1556 = getelementptr i8, ptr %t5, i64 -8
  %t1557 = load i32, ptr %t1556
  %t1558 = icmp eq i32 %t1557, 1
  br i1 %t1558, label %reuse.in_place.1559, label %reuse.copy.1560
reuse.in_place.1559:
  %t1562 = getelementptr ptr, ptr %t5, i32 1
  %t1563 = load ptr, ptr %t1562
  call void @__free_recursive(ptr %t1563)
  %t1565 = inttoptr i64 193 to ptr
  %t1566 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1565, ptr %t1566
  call void @__inc_ref(ptr %t1555)
  %t1564 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1555, ptr %t1564
  br label %reuse.join.1561
reuse.copy.1560:
  %t1567 = call ptr @__alloc(i64 24, i32 2)
  %t1568 = inttoptr i64 193 to ptr
  %t1569 = getelementptr ptr, ptr %t1567, i32 0
  store ptr %t1568, ptr %t1569
  call void @__inc_ref(ptr %t1555)
  %t1570 = getelementptr ptr, ptr %t1567, i32 1
  store ptr %t1555, ptr %t1570
  call void @__inc_ref(ptr %t15)
  %t1571 = getelementptr ptr, ptr %t1567, i32 2
  store ptr %t15, ptr %t1571
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1561
reuse.join.1561:
  %t1572 = phi ptr [ %t5, %reuse.in_place.1559 ], [ %t1567, %reuse.copy.1560 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1555)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1572, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.106.1573:
  %t1574 = getelementptr ptr, ptr %t13, i32 1
  %t1575 = load ptr, ptr %t1574
  call void @__inc_ref(ptr %t1575)
  %t1576 = getelementptr i8, ptr %t5, i64 -8
  %t1577 = load i32, ptr %t1576
  %t1578 = icmp eq i32 %t1577, 1
  br i1 %t1578, label %reuse.in_place.1579, label %reuse.copy.1580
reuse.in_place.1579:
  %t1582 = getelementptr ptr, ptr %t5, i32 1
  %t1583 = load ptr, ptr %t1582
  call void @__free_recursive(ptr %t1583)
  %t1585 = inttoptr i64 194 to ptr
  %t1586 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1585, ptr %t1586
  call void @__inc_ref(ptr %t1575)
  %t1584 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1575, ptr %t1584
  br label %reuse.join.1581
reuse.copy.1580:
  %t1587 = call ptr @__alloc(i64 24, i32 2)
  %t1588 = inttoptr i64 194 to ptr
  %t1589 = getelementptr ptr, ptr %t1587, i32 0
  store ptr %t1588, ptr %t1589
  call void @__inc_ref(ptr %t1575)
  %t1590 = getelementptr ptr, ptr %t1587, i32 1
  store ptr %t1575, ptr %t1590
  call void @__inc_ref(ptr %t15)
  %t1591 = getelementptr ptr, ptr %t1587, i32 2
  store ptr %t15, ptr %t1591
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1581
reuse.join.1581:
  %t1592 = phi ptr [ %t5, %reuse.in_place.1579 ], [ %t1587, %reuse.copy.1580 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1575)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1592, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.107.1593:
  %t1594 = getelementptr ptr, ptr %t13, i32 1
  %t1595 = load ptr, ptr %t1594
  call void @__inc_ref(ptr %t1595)
  %t1596 = getelementptr i8, ptr %t5, i64 -8
  %t1597 = load i32, ptr %t1596
  %t1598 = icmp eq i32 %t1597, 1
  br i1 %t1598, label %reuse.in_place.1599, label %reuse.copy.1600
reuse.in_place.1599:
  %t1602 = getelementptr ptr, ptr %t5, i32 1
  %t1603 = load ptr, ptr %t1602
  call void @__free_recursive(ptr %t1603)
  %t1605 = inttoptr i64 195 to ptr
  %t1606 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1605, ptr %t1606
  call void @__inc_ref(ptr %t1595)
  %t1604 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1595, ptr %t1604
  br label %reuse.join.1601
reuse.copy.1600:
  %t1607 = call ptr @__alloc(i64 24, i32 2)
  %t1608 = inttoptr i64 195 to ptr
  %t1609 = getelementptr ptr, ptr %t1607, i32 0
  store ptr %t1608, ptr %t1609
  call void @__inc_ref(ptr %t1595)
  %t1610 = getelementptr ptr, ptr %t1607, i32 1
  store ptr %t1595, ptr %t1610
  call void @__inc_ref(ptr %t15)
  %t1611 = getelementptr ptr, ptr %t1607, i32 2
  store ptr %t15, ptr %t1611
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1601
reuse.join.1601:
  %t1612 = phi ptr [ %t5, %reuse.in_place.1599 ], [ %t1607, %reuse.copy.1600 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1595)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1612, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.108.1613:
  %t1614 = getelementptr ptr, ptr %t13, i32 1
  %t1615 = load ptr, ptr %t1614
  call void @__inc_ref(ptr %t1615)
  %t1616 = getelementptr i8, ptr %t5, i64 -8
  %t1617 = load i32, ptr %t1616
  %t1618 = icmp eq i32 %t1617, 1
  br i1 %t1618, label %reuse.in_place.1619, label %reuse.copy.1620
reuse.in_place.1619:
  %t1622 = getelementptr ptr, ptr %t5, i32 1
  %t1623 = load ptr, ptr %t1622
  call void @__free_recursive(ptr %t1623)
  %t1625 = inttoptr i64 196 to ptr
  %t1626 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1625, ptr %t1626
  call void @__inc_ref(ptr %t1615)
  %t1624 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1615, ptr %t1624
  br label %reuse.join.1621
reuse.copy.1620:
  %t1627 = call ptr @__alloc(i64 24, i32 2)
  %t1628 = inttoptr i64 196 to ptr
  %t1629 = getelementptr ptr, ptr %t1627, i32 0
  store ptr %t1628, ptr %t1629
  call void @__inc_ref(ptr %t1615)
  %t1630 = getelementptr ptr, ptr %t1627, i32 1
  store ptr %t1615, ptr %t1630
  call void @__inc_ref(ptr %t15)
  %t1631 = getelementptr ptr, ptr %t1627, i32 2
  store ptr %t15, ptr %t1631
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1621
reuse.join.1621:
  %t1632 = phi ptr [ %t5, %reuse.in_place.1619 ], [ %t1627, %reuse.copy.1620 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1615)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1632, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.109.1633:
  %t1634 = getelementptr ptr, ptr %t13, i32 1
  %t1635 = load ptr, ptr %t1634
  call void @__inc_ref(ptr %t1635)
  %t1636 = getelementptr i8, ptr %t5, i64 -8
  %t1637 = load i32, ptr %t1636
  %t1638 = icmp eq i32 %t1637, 1
  br i1 %t1638, label %reuse.in_place.1639, label %reuse.copy.1640
reuse.in_place.1639:
  %t1642 = getelementptr ptr, ptr %t5, i32 1
  %t1643 = load ptr, ptr %t1642
  call void @__free_recursive(ptr %t1643)
  %t1645 = inttoptr i64 197 to ptr
  %t1646 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1645, ptr %t1646
  call void @__inc_ref(ptr %t1635)
  %t1644 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1635, ptr %t1644
  br label %reuse.join.1641
reuse.copy.1640:
  %t1647 = call ptr @__alloc(i64 24, i32 2)
  %t1648 = inttoptr i64 197 to ptr
  %t1649 = getelementptr ptr, ptr %t1647, i32 0
  store ptr %t1648, ptr %t1649
  call void @__inc_ref(ptr %t1635)
  %t1650 = getelementptr ptr, ptr %t1647, i32 1
  store ptr %t1635, ptr %t1650
  call void @__inc_ref(ptr %t15)
  %t1651 = getelementptr ptr, ptr %t1647, i32 2
  store ptr %t15, ptr %t1651
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1641
reuse.join.1641:
  %t1652 = phi ptr [ %t5, %reuse.in_place.1639 ], [ %t1647, %reuse.copy.1640 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1635)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1652, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.110.1653:
  %t1654 = getelementptr ptr, ptr %t13, i32 1
  %t1655 = load ptr, ptr %t1654
  call void @__inc_ref(ptr %t1655)
  %t1656 = getelementptr i8, ptr %t5, i64 -8
  %t1657 = load i32, ptr %t1656
  %t1658 = icmp eq i32 %t1657, 1
  br i1 %t1658, label %reuse.in_place.1659, label %reuse.copy.1660
reuse.in_place.1659:
  %t1662 = getelementptr ptr, ptr %t5, i32 1
  %t1663 = load ptr, ptr %t1662
  call void @__free_recursive(ptr %t1663)
  %t1665 = inttoptr i64 198 to ptr
  %t1666 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1665, ptr %t1666
  call void @__inc_ref(ptr %t1655)
  %t1664 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1655, ptr %t1664
  br label %reuse.join.1661
reuse.copy.1660:
  %t1667 = call ptr @__alloc(i64 24, i32 2)
  %t1668 = inttoptr i64 198 to ptr
  %t1669 = getelementptr ptr, ptr %t1667, i32 0
  store ptr %t1668, ptr %t1669
  call void @__inc_ref(ptr %t1655)
  %t1670 = getelementptr ptr, ptr %t1667, i32 1
  store ptr %t1655, ptr %t1670
  call void @__inc_ref(ptr %t15)
  %t1671 = getelementptr ptr, ptr %t1667, i32 2
  store ptr %t15, ptr %t1671
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1661
reuse.join.1661:
  %t1672 = phi ptr [ %t5, %reuse.in_place.1659 ], [ %t1667, %reuse.copy.1660 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1655)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1672, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.111.1673:
  %t1674 = getelementptr ptr, ptr %t13, i32 1
  %t1675 = load ptr, ptr %t1674
  call void @__inc_ref(ptr %t1675)
  %t1676 = getelementptr i8, ptr %t5, i64 -8
  %t1677 = load i32, ptr %t1676
  %t1678 = icmp eq i32 %t1677, 1
  br i1 %t1678, label %reuse.in_place.1679, label %reuse.copy.1680
reuse.in_place.1679:
  %t1682 = getelementptr ptr, ptr %t5, i32 1
  %t1683 = load ptr, ptr %t1682
  call void @__free_recursive(ptr %t1683)
  %t1685 = inttoptr i64 199 to ptr
  %t1686 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1685, ptr %t1686
  call void @__inc_ref(ptr %t1675)
  %t1684 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1675, ptr %t1684
  br label %reuse.join.1681
reuse.copy.1680:
  %t1687 = call ptr @__alloc(i64 24, i32 2)
  %t1688 = inttoptr i64 199 to ptr
  %t1689 = getelementptr ptr, ptr %t1687, i32 0
  store ptr %t1688, ptr %t1689
  call void @__inc_ref(ptr %t1675)
  %t1690 = getelementptr ptr, ptr %t1687, i32 1
  store ptr %t1675, ptr %t1690
  call void @__inc_ref(ptr %t15)
  %t1691 = getelementptr ptr, ptr %t1687, i32 2
  store ptr %t15, ptr %t1691
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1681
reuse.join.1681:
  %t1692 = phi ptr [ %t5, %reuse.in_place.1679 ], [ %t1687, %reuse.copy.1680 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1675)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1692, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.112.1693:
  %t1694 = getelementptr ptr, ptr %t13, i32 1
  %t1695 = load ptr, ptr %t1694
  call void @__inc_ref(ptr %t1695)
  %t1696 = getelementptr i8, ptr %t5, i64 -8
  %t1697 = load i32, ptr %t1696
  %t1698 = icmp eq i32 %t1697, 1
  br i1 %t1698, label %reuse.in_place.1699, label %reuse.copy.1700
reuse.in_place.1699:
  %t1702 = getelementptr ptr, ptr %t5, i32 1
  %t1703 = load ptr, ptr %t1702
  call void @__free_recursive(ptr %t1703)
  %t1705 = inttoptr i64 200 to ptr
  %t1706 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1705, ptr %t1706
  call void @__inc_ref(ptr %t1695)
  %t1704 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1695, ptr %t1704
  br label %reuse.join.1701
reuse.copy.1700:
  %t1707 = call ptr @__alloc(i64 24, i32 2)
  %t1708 = inttoptr i64 200 to ptr
  %t1709 = getelementptr ptr, ptr %t1707, i32 0
  store ptr %t1708, ptr %t1709
  call void @__inc_ref(ptr %t1695)
  %t1710 = getelementptr ptr, ptr %t1707, i32 1
  store ptr %t1695, ptr %t1710
  call void @__inc_ref(ptr %t15)
  %t1711 = getelementptr ptr, ptr %t1707, i32 2
  store ptr %t15, ptr %t1711
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1701
reuse.join.1701:
  %t1712 = phi ptr [ %t5, %reuse.in_place.1699 ], [ %t1707, %reuse.copy.1700 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1695)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1712, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.113.1713:
  %t1714 = getelementptr ptr, ptr %t13, i32 1
  %t1715 = load ptr, ptr %t1714
  call void @__inc_ref(ptr %t1715)
  %t1716 = getelementptr i8, ptr %t5, i64 -8
  %t1717 = load i32, ptr %t1716
  %t1718 = icmp eq i32 %t1717, 1
  br i1 %t1718, label %reuse.in_place.1719, label %reuse.copy.1720
reuse.in_place.1719:
  %t1722 = getelementptr ptr, ptr %t5, i32 1
  %t1723 = load ptr, ptr %t1722
  call void @__free_recursive(ptr %t1723)
  %t1725 = inttoptr i64 201 to ptr
  %t1726 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1725, ptr %t1726
  call void @__inc_ref(ptr %t1715)
  %t1724 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1715, ptr %t1724
  br label %reuse.join.1721
reuse.copy.1720:
  %t1727 = call ptr @__alloc(i64 24, i32 2)
  %t1728 = inttoptr i64 201 to ptr
  %t1729 = getelementptr ptr, ptr %t1727, i32 0
  store ptr %t1728, ptr %t1729
  call void @__inc_ref(ptr %t1715)
  %t1730 = getelementptr ptr, ptr %t1727, i32 1
  store ptr %t1715, ptr %t1730
  call void @__inc_ref(ptr %t15)
  %t1731 = getelementptr ptr, ptr %t1727, i32 2
  store ptr %t15, ptr %t1731
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1721
reuse.join.1721:
  %t1732 = phi ptr [ %t5, %reuse.in_place.1719 ], [ %t1727, %reuse.copy.1720 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1715)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1732, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.default.19:
  unreachable
tco.case.arm.115.1733:
  %t1734 = getelementptr ptr, ptr %t5, i32 1
  %t1735 = load ptr, ptr %t1734
  %t1736 = getelementptr ptr, ptr %t5, i32 2
  %t1737 = load ptr, ptr %t1736
  %t1738 = getelementptr i8, ptr %t5, i64 -8
  %t1739 = load i32, ptr %t1738
  %t1740 = icmp eq i32 %t1739, 1
  br i1 %t1740, label %reuse.in_place.1741, label %reuse.copy.1742
reuse.in_place.1741:
  %t1744 = inttoptr i64 114 to ptr
  %t1745 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1744, ptr %t1745
  br label %reuse.join.1743
reuse.copy.1742:
  %t1746 = call ptr @__alloc(i64 24, i32 2)
  %t1747 = inttoptr i64 114 to ptr
  %t1748 = getelementptr ptr, ptr %t1746, i32 0
  store ptr %t1747, ptr %t1748
  call void @__inc_ref(ptr %t1735)
  %t1749 = getelementptr ptr, ptr %t1746, i32 1
  store ptr %t1735, ptr %t1749
  call void @__inc_ref(ptr %t1737)
  %t1750 = getelementptr ptr, ptr %t1746, i32 2
  store ptr %t1737, ptr %t1750
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1743
reuse.join.1743:
  %t1751 = phi ptr [ %t5, %reuse.in_place.1741 ], [ %t1746, %reuse.copy.1742 ]
  %t1752 = call ptr @__alloc(i64 16, i32 1)
  %t1753 = inttoptr i64 261 to ptr
  %t1754 = getelementptr ptr, ptr %t1752, i32 0
  store ptr %t1753, ptr %t1754
  call void @__inc_ref(ptr %t6)
  %t1755 = getelementptr ptr, ptr %t1752, i32 1
  store ptr %t6, ptr %t1755
  call void @__free_recursive(ptr %t6)
  store ptr %t1751, ptr %t3
  store ptr %t1752, ptr %t4
  br label %tco.loop.0
tco.case.arm.116.1756:
  %t1757 = getelementptr ptr, ptr %t5, i32 1
  %t1758 = load ptr, ptr %t1757
  %t1759 = getelementptr ptr, ptr %t5, i32 2
  %t1760 = load ptr, ptr %t1759
  %t1761 = getelementptr i8, ptr %t5, i64 -8
  %t1762 = load i32, ptr %t1761
  %t1763 = icmp eq i32 %t1762, 1
  br i1 %t1763, label %reuse.in_place.1764, label %reuse.copy.1765
reuse.in_place.1764:
  %t1767 = inttoptr i64 114 to ptr
  %t1768 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1767, ptr %t1768
  br label %reuse.join.1766
reuse.copy.1765:
  %t1769 = call ptr @__alloc(i64 24, i32 2)
  %t1770 = inttoptr i64 114 to ptr
  %t1771 = getelementptr ptr, ptr %t1769, i32 0
  store ptr %t1770, ptr %t1771
  call void @__inc_ref(ptr %t1758)
  %t1772 = getelementptr ptr, ptr %t1769, i32 1
  store ptr %t1758, ptr %t1772
  call void @__inc_ref(ptr %t1760)
  %t1773 = getelementptr ptr, ptr %t1769, i32 2
  store ptr %t1760, ptr %t1773
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1766
reuse.join.1766:
  %t1774 = phi ptr [ %t5, %reuse.in_place.1764 ], [ %t1769, %reuse.copy.1765 ]
  %t1775 = call ptr @__alloc(i64 16, i32 1)
  %t1776 = inttoptr i64 262 to ptr
  %t1777 = getelementptr ptr, ptr %t1775, i32 0
  store ptr %t1776, ptr %t1777
  call void @__inc_ref(ptr %t6)
  %t1778 = getelementptr ptr, ptr %t1775, i32 1
  store ptr %t6, ptr %t1778
  call void @__free_recursive(ptr %t6)
  store ptr %t1774, ptr %t3
  store ptr %t1775, ptr %t4
  br label %tco.loop.0
tco.case.arm.117.1779:
  %t1780 = getelementptr ptr, ptr %t5, i32 1
  %t1781 = load ptr, ptr %t1780
  %t1782 = getelementptr ptr, ptr %t5, i32 2
  %t1783 = load ptr, ptr %t1782
  %t1784 = getelementptr i8, ptr %t5, i64 -8
  %t1785 = load i32, ptr %t1784
  %t1786 = icmp eq i32 %t1785, 1
  br i1 %t1786, label %reuse.in_place.1787, label %reuse.copy.1788
reuse.in_place.1787:
  %t1790 = inttoptr i64 114 to ptr
  %t1791 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1790, ptr %t1791
  br label %reuse.join.1789
reuse.copy.1788:
  %t1792 = call ptr @__alloc(i64 24, i32 2)
  %t1793 = inttoptr i64 114 to ptr
  %t1794 = getelementptr ptr, ptr %t1792, i32 0
  store ptr %t1793, ptr %t1794
  call void @__inc_ref(ptr %t1781)
  %t1795 = getelementptr ptr, ptr %t1792, i32 1
  store ptr %t1781, ptr %t1795
  call void @__inc_ref(ptr %t1783)
  %t1796 = getelementptr ptr, ptr %t1792, i32 2
  store ptr %t1783, ptr %t1796
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1789
reuse.join.1789:
  %t1797 = phi ptr [ %t5, %reuse.in_place.1787 ], [ %t1792, %reuse.copy.1788 ]
  %t1798 = call ptr @__alloc(i64 16, i32 1)
  %t1799 = inttoptr i64 263 to ptr
  %t1800 = getelementptr ptr, ptr %t1798, i32 0
  store ptr %t1799, ptr %t1800
  call void @__inc_ref(ptr %t6)
  %t1801 = getelementptr ptr, ptr %t1798, i32 1
  store ptr %t6, ptr %t1801
  call void @__free_recursive(ptr %t6)
  store ptr %t1797, ptr %t3
  store ptr %t1798, ptr %t4
  br label %tco.loop.0
tco.case.arm.118.1802:
  %t1803 = getelementptr ptr, ptr %t5, i32 1
  %t1804 = load ptr, ptr %t1803
  %t1805 = getelementptr ptr, ptr %t5, i32 2
  %t1806 = load ptr, ptr %t1805
  %t1807 = getelementptr i8, ptr %t5, i64 -8
  %t1808 = load i32, ptr %t1807
  %t1809 = icmp eq i32 %t1808, 1
  br i1 %t1809, label %reuse.in_place.1810, label %reuse.copy.1811
reuse.in_place.1810:
  %t1813 = inttoptr i64 114 to ptr
  %t1814 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1813, ptr %t1814
  br label %reuse.join.1812
reuse.copy.1811:
  %t1815 = call ptr @__alloc(i64 24, i32 2)
  %t1816 = inttoptr i64 114 to ptr
  %t1817 = getelementptr ptr, ptr %t1815, i32 0
  store ptr %t1816, ptr %t1817
  call void @__inc_ref(ptr %t1804)
  %t1818 = getelementptr ptr, ptr %t1815, i32 1
  store ptr %t1804, ptr %t1818
  call void @__inc_ref(ptr %t1806)
  %t1819 = getelementptr ptr, ptr %t1815, i32 2
  store ptr %t1806, ptr %t1819
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1812
reuse.join.1812:
  %t1820 = phi ptr [ %t5, %reuse.in_place.1810 ], [ %t1815, %reuse.copy.1811 ]
  %t1821 = call ptr @__alloc(i64 16, i32 1)
  %t1822 = inttoptr i64 264 to ptr
  %t1823 = getelementptr ptr, ptr %t1821, i32 0
  store ptr %t1822, ptr %t1823
  call void @__inc_ref(ptr %t6)
  %t1824 = getelementptr ptr, ptr %t1821, i32 1
  store ptr %t6, ptr %t1824
  call void @__free_recursive(ptr %t6)
  store ptr %t1820, ptr %t3
  store ptr %t1821, ptr %t4
  br label %tco.loop.0
tco.case.arm.119.1825:
  %t1826 = getelementptr ptr, ptr %t5, i32 1
  %t1827 = load ptr, ptr %t1826
  %t1828 = getelementptr ptr, ptr %t5, i32 2
  %t1829 = load ptr, ptr %t1828
  %t1830 = getelementptr i8, ptr %t5, i64 -8
  %t1831 = load i32, ptr %t1830
  %t1832 = icmp eq i32 %t1831, 1
  br i1 %t1832, label %reuse.in_place.1833, label %reuse.copy.1834
reuse.in_place.1833:
  %t1836 = inttoptr i64 114 to ptr
  %t1837 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1836, ptr %t1837
  br label %reuse.join.1835
reuse.copy.1834:
  %t1838 = call ptr @__alloc(i64 24, i32 2)
  %t1839 = inttoptr i64 114 to ptr
  %t1840 = getelementptr ptr, ptr %t1838, i32 0
  store ptr %t1839, ptr %t1840
  call void @__inc_ref(ptr %t1827)
  %t1841 = getelementptr ptr, ptr %t1838, i32 1
  store ptr %t1827, ptr %t1841
  call void @__inc_ref(ptr %t1829)
  %t1842 = getelementptr ptr, ptr %t1838, i32 2
  store ptr %t1829, ptr %t1842
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1835
reuse.join.1835:
  %t1843 = phi ptr [ %t5, %reuse.in_place.1833 ], [ %t1838, %reuse.copy.1834 ]
  %t1844 = call ptr @__alloc(i64 16, i32 1)
  %t1845 = inttoptr i64 265 to ptr
  %t1846 = getelementptr ptr, ptr %t1844, i32 0
  store ptr %t1845, ptr %t1846
  call void @__inc_ref(ptr %t6)
  %t1847 = getelementptr ptr, ptr %t1844, i32 1
  store ptr %t6, ptr %t1847
  call void @__free_recursive(ptr %t6)
  store ptr %t1843, ptr %t3
  store ptr %t1844, ptr %t4
  br label %tco.loop.0
tco.case.arm.120.1848:
  %t1849 = getelementptr ptr, ptr %t5, i32 1
  %t1850 = load ptr, ptr %t1849
  %t1851 = getelementptr ptr, ptr %t5, i32 2
  %t1852 = load ptr, ptr %t1851
  %t1853 = getelementptr i8, ptr %t5, i64 -8
  %t1854 = load i32, ptr %t1853
  %t1855 = icmp eq i32 %t1854, 1
  br i1 %t1855, label %reuse.in_place.1856, label %reuse.copy.1857
reuse.in_place.1856:
  %t1859 = inttoptr i64 114 to ptr
  %t1860 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1859, ptr %t1860
  br label %reuse.join.1858
reuse.copy.1857:
  %t1861 = call ptr @__alloc(i64 24, i32 2)
  %t1862 = inttoptr i64 114 to ptr
  %t1863 = getelementptr ptr, ptr %t1861, i32 0
  store ptr %t1862, ptr %t1863
  call void @__inc_ref(ptr %t1850)
  %t1864 = getelementptr ptr, ptr %t1861, i32 1
  store ptr %t1850, ptr %t1864
  call void @__inc_ref(ptr %t1852)
  %t1865 = getelementptr ptr, ptr %t1861, i32 2
  store ptr %t1852, ptr %t1865
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1858
reuse.join.1858:
  %t1866 = phi ptr [ %t5, %reuse.in_place.1856 ], [ %t1861, %reuse.copy.1857 ]
  %t1867 = call ptr @__alloc(i64 16, i32 1)
  %t1868 = inttoptr i64 266 to ptr
  %t1869 = getelementptr ptr, ptr %t1867, i32 0
  store ptr %t1868, ptr %t1869
  call void @__inc_ref(ptr %t6)
  %t1870 = getelementptr ptr, ptr %t1867, i32 1
  store ptr %t6, ptr %t1870
  call void @__free_recursive(ptr %t6)
  store ptr %t1866, ptr %t3
  store ptr %t1867, ptr %t4
  br label %tco.loop.0
tco.case.arm.121.1871:
  %t1872 = getelementptr ptr, ptr %t5, i32 1
  %t1873 = load ptr, ptr %t1872
  %t1874 = getelementptr ptr, ptr %t5, i32 2
  %t1875 = load ptr, ptr %t1874
  %t1876 = getelementptr i8, ptr %t5, i64 -8
  %t1877 = load i32, ptr %t1876
  %t1878 = icmp eq i32 %t1877, 1
  br i1 %t1878, label %reuse.in_place.1879, label %reuse.copy.1880
reuse.in_place.1879:
  %t1882 = inttoptr i64 114 to ptr
  %t1883 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1882, ptr %t1883
  br label %reuse.join.1881
reuse.copy.1880:
  %t1884 = call ptr @__alloc(i64 24, i32 2)
  %t1885 = inttoptr i64 114 to ptr
  %t1886 = getelementptr ptr, ptr %t1884, i32 0
  store ptr %t1885, ptr %t1886
  call void @__inc_ref(ptr %t1873)
  %t1887 = getelementptr ptr, ptr %t1884, i32 1
  store ptr %t1873, ptr %t1887
  call void @__inc_ref(ptr %t1875)
  %t1888 = getelementptr ptr, ptr %t1884, i32 2
  store ptr %t1875, ptr %t1888
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1881
reuse.join.1881:
  %t1889 = phi ptr [ %t5, %reuse.in_place.1879 ], [ %t1884, %reuse.copy.1880 ]
  %t1890 = call ptr @__alloc(i64 16, i32 1)
  %t1891 = inttoptr i64 267 to ptr
  %t1892 = getelementptr ptr, ptr %t1890, i32 0
  store ptr %t1891, ptr %t1892
  call void @__inc_ref(ptr %t6)
  %t1893 = getelementptr ptr, ptr %t1890, i32 1
  store ptr %t6, ptr %t1893
  call void @__free_recursive(ptr %t6)
  store ptr %t1889, ptr %t3
  store ptr %t1890, ptr %t4
  br label %tco.loop.0
tco.case.arm.122.1894:
  %t1895 = getelementptr ptr, ptr %t5, i32 1
  %t1896 = load ptr, ptr %t1895
  %t1897 = getelementptr ptr, ptr %t5, i32 2
  %t1898 = load ptr, ptr %t1897
  %t1899 = getelementptr i8, ptr %t5, i64 -8
  %t1900 = load i32, ptr %t1899
  %t1901 = icmp eq i32 %t1900, 1
  br i1 %t1901, label %reuse.in_place.1902, label %reuse.copy.1903
reuse.in_place.1902:
  %t1905 = inttoptr i64 114 to ptr
  %t1906 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1905, ptr %t1906
  br label %reuse.join.1904
reuse.copy.1903:
  %t1907 = call ptr @__alloc(i64 24, i32 2)
  %t1908 = inttoptr i64 114 to ptr
  %t1909 = getelementptr ptr, ptr %t1907, i32 0
  store ptr %t1908, ptr %t1909
  call void @__inc_ref(ptr %t1896)
  %t1910 = getelementptr ptr, ptr %t1907, i32 1
  store ptr %t1896, ptr %t1910
  call void @__inc_ref(ptr %t1898)
  %t1911 = getelementptr ptr, ptr %t1907, i32 2
  store ptr %t1898, ptr %t1911
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1904
reuse.join.1904:
  %t1912 = phi ptr [ %t5, %reuse.in_place.1902 ], [ %t1907, %reuse.copy.1903 ]
  %t1913 = call ptr @__alloc(i64 16, i32 1)
  %t1914 = inttoptr i64 268 to ptr
  %t1915 = getelementptr ptr, ptr %t1913, i32 0
  store ptr %t1914, ptr %t1915
  call void @__inc_ref(ptr %t6)
  %t1916 = getelementptr ptr, ptr %t1913, i32 1
  store ptr %t6, ptr %t1916
  call void @__free_recursive(ptr %t6)
  store ptr %t1912, ptr %t3
  store ptr %t1913, ptr %t4
  br label %tco.loop.0
tco.case.arm.123.1917:
  %t1918 = getelementptr ptr, ptr %t5, i32 1
  %t1919 = load ptr, ptr %t1918
  %t1920 = getelementptr ptr, ptr %t5, i32 2
  %t1921 = load ptr, ptr %t1920
  %t1922 = getelementptr i8, ptr %t5, i64 -8
  %t1923 = load i32, ptr %t1922
  %t1924 = icmp eq i32 %t1923, 1
  br i1 %t1924, label %reuse.in_place.1925, label %reuse.copy.1926
reuse.in_place.1925:
  %t1928 = inttoptr i64 114 to ptr
  %t1929 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1928, ptr %t1929
  br label %reuse.join.1927
reuse.copy.1926:
  %t1930 = call ptr @__alloc(i64 24, i32 2)
  %t1931 = inttoptr i64 114 to ptr
  %t1932 = getelementptr ptr, ptr %t1930, i32 0
  store ptr %t1931, ptr %t1932
  call void @__inc_ref(ptr %t1919)
  %t1933 = getelementptr ptr, ptr %t1930, i32 1
  store ptr %t1919, ptr %t1933
  call void @__inc_ref(ptr %t1921)
  %t1934 = getelementptr ptr, ptr %t1930, i32 2
  store ptr %t1921, ptr %t1934
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1927
reuse.join.1927:
  %t1935 = phi ptr [ %t5, %reuse.in_place.1925 ], [ %t1930, %reuse.copy.1926 ]
  %t1936 = call ptr @__alloc(i64 16, i32 1)
  %t1937 = inttoptr i64 269 to ptr
  %t1938 = getelementptr ptr, ptr %t1936, i32 0
  store ptr %t1937, ptr %t1938
  call void @__inc_ref(ptr %t6)
  %t1939 = getelementptr ptr, ptr %t1936, i32 1
  store ptr %t6, ptr %t1939
  call void @__free_recursive(ptr %t6)
  store ptr %t1935, ptr %t3
  store ptr %t1936, ptr %t4
  br label %tco.loop.0
tco.case.arm.124.1940:
  %t1941 = getelementptr ptr, ptr %t5, i32 1
  %t1942 = load ptr, ptr %t1941
  %t1943 = getelementptr ptr, ptr %t5, i32 2
  %t1944 = load ptr, ptr %t1943
  %t1945 = getelementptr i8, ptr %t5, i64 -8
  %t1946 = load i32, ptr %t1945
  %t1947 = icmp eq i32 %t1946, 1
  br i1 %t1947, label %reuse.in_place.1948, label %reuse.copy.1949
reuse.in_place.1948:
  %t1951 = inttoptr i64 114 to ptr
  %t1952 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1951, ptr %t1952
  br label %reuse.join.1950
reuse.copy.1949:
  %t1953 = call ptr @__alloc(i64 24, i32 2)
  %t1954 = inttoptr i64 114 to ptr
  %t1955 = getelementptr ptr, ptr %t1953, i32 0
  store ptr %t1954, ptr %t1955
  call void @__inc_ref(ptr %t1942)
  %t1956 = getelementptr ptr, ptr %t1953, i32 1
  store ptr %t1942, ptr %t1956
  call void @__inc_ref(ptr %t1944)
  %t1957 = getelementptr ptr, ptr %t1953, i32 2
  store ptr %t1944, ptr %t1957
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1950
reuse.join.1950:
  %t1958 = phi ptr [ %t5, %reuse.in_place.1948 ], [ %t1953, %reuse.copy.1949 ]
  %t1959 = call ptr @__alloc(i64 16, i32 1)
  %t1960 = inttoptr i64 270 to ptr
  %t1961 = getelementptr ptr, ptr %t1959, i32 0
  store ptr %t1960, ptr %t1961
  call void @__inc_ref(ptr %t6)
  %t1962 = getelementptr ptr, ptr %t1959, i32 1
  store ptr %t6, ptr %t1962
  call void @__free_recursive(ptr %t6)
  store ptr %t1958, ptr %t3
  store ptr %t1959, ptr %t4
  br label %tco.loop.0
tco.case.arm.125.1963:
  %t1964 = getelementptr ptr, ptr %t5, i32 1
  %t1965 = load ptr, ptr %t1964
  %t1966 = getelementptr ptr, ptr %t5, i32 2
  %t1967 = load ptr, ptr %t1966
  %t1968 = getelementptr i8, ptr %t5, i64 -8
  %t1969 = load i32, ptr %t1968
  %t1970 = icmp eq i32 %t1969, 1
  br i1 %t1970, label %reuse.in_place.1971, label %reuse.copy.1972
reuse.in_place.1971:
  %t1974 = inttoptr i64 114 to ptr
  %t1975 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1974, ptr %t1975
  br label %reuse.join.1973
reuse.copy.1972:
  %t1976 = call ptr @__alloc(i64 24, i32 2)
  %t1977 = inttoptr i64 114 to ptr
  %t1978 = getelementptr ptr, ptr %t1976, i32 0
  store ptr %t1977, ptr %t1978
  call void @__inc_ref(ptr %t1965)
  %t1979 = getelementptr ptr, ptr %t1976, i32 1
  store ptr %t1965, ptr %t1979
  call void @__inc_ref(ptr %t1967)
  %t1980 = getelementptr ptr, ptr %t1976, i32 2
  store ptr %t1967, ptr %t1980
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1973
reuse.join.1973:
  %t1981 = phi ptr [ %t5, %reuse.in_place.1971 ], [ %t1976, %reuse.copy.1972 ]
  %t1982 = call ptr @__alloc(i64 16, i32 1)
  %t1983 = inttoptr i64 271 to ptr
  %t1984 = getelementptr ptr, ptr %t1982, i32 0
  store ptr %t1983, ptr %t1984
  call void @__inc_ref(ptr %t6)
  %t1985 = getelementptr ptr, ptr %t1982, i32 1
  store ptr %t6, ptr %t1985
  call void @__free_recursive(ptr %t6)
  store ptr %t1981, ptr %t3
  store ptr %t1982, ptr %t4
  br label %tco.loop.0
tco.case.arm.126.1986:
  %t1987 = getelementptr ptr, ptr %t5, i32 1
  %t1988 = load ptr, ptr %t1987
  %t1989 = getelementptr ptr, ptr %t5, i32 2
  %t1990 = load ptr, ptr %t1989
  %t1991 = getelementptr i8, ptr %t5, i64 -8
  %t1992 = load i32, ptr %t1991
  %t1993 = icmp eq i32 %t1992, 1
  br i1 %t1993, label %reuse.in_place.1994, label %reuse.copy.1995
reuse.in_place.1994:
  %t1997 = inttoptr i64 114 to ptr
  %t1998 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1997, ptr %t1998
  br label %reuse.join.1996
reuse.copy.1995:
  %t1999 = call ptr @__alloc(i64 24, i32 2)
  %t2000 = inttoptr i64 114 to ptr
  %t2001 = getelementptr ptr, ptr %t1999, i32 0
  store ptr %t2000, ptr %t2001
  call void @__inc_ref(ptr %t1988)
  %t2002 = getelementptr ptr, ptr %t1999, i32 1
  store ptr %t1988, ptr %t2002
  call void @__inc_ref(ptr %t1990)
  %t2003 = getelementptr ptr, ptr %t1999, i32 2
  store ptr %t1990, ptr %t2003
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1996
reuse.join.1996:
  %t2004 = phi ptr [ %t5, %reuse.in_place.1994 ], [ %t1999, %reuse.copy.1995 ]
  %t2005 = call ptr @__alloc(i64 16, i32 1)
  %t2006 = inttoptr i64 272 to ptr
  %t2007 = getelementptr ptr, ptr %t2005, i32 0
  store ptr %t2006, ptr %t2007
  call void @__inc_ref(ptr %t6)
  %t2008 = getelementptr ptr, ptr %t2005, i32 1
  store ptr %t6, ptr %t2008
  call void @__free_recursive(ptr %t6)
  store ptr %t2004, ptr %t3
  store ptr %t2005, ptr %t4
  br label %tco.loop.0
tco.case.arm.127.2009:
  %t2010 = getelementptr ptr, ptr %t5, i32 1
  %t2011 = load ptr, ptr %t2010
  %t2012 = getelementptr ptr, ptr %t5, i32 2
  %t2013 = load ptr, ptr %t2012
  %t2014 = getelementptr i8, ptr %t5, i64 -8
  %t2015 = load i32, ptr %t2014
  %t2016 = icmp eq i32 %t2015, 1
  br i1 %t2016, label %reuse.in_place.2017, label %reuse.copy.2018
reuse.in_place.2017:
  %t2020 = inttoptr i64 114 to ptr
  %t2021 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2020, ptr %t2021
  br label %reuse.join.2019
reuse.copy.2018:
  %t2022 = call ptr @__alloc(i64 24, i32 2)
  %t2023 = inttoptr i64 114 to ptr
  %t2024 = getelementptr ptr, ptr %t2022, i32 0
  store ptr %t2023, ptr %t2024
  call void @__inc_ref(ptr %t2011)
  %t2025 = getelementptr ptr, ptr %t2022, i32 1
  store ptr %t2011, ptr %t2025
  call void @__inc_ref(ptr %t2013)
  %t2026 = getelementptr ptr, ptr %t2022, i32 2
  store ptr %t2013, ptr %t2026
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2019
reuse.join.2019:
  %t2027 = phi ptr [ %t5, %reuse.in_place.2017 ], [ %t2022, %reuse.copy.2018 ]
  %t2028 = call ptr @__alloc(i64 16, i32 1)
  %t2029 = inttoptr i64 273 to ptr
  %t2030 = getelementptr ptr, ptr %t2028, i32 0
  store ptr %t2029, ptr %t2030
  call void @__inc_ref(ptr %t6)
  %t2031 = getelementptr ptr, ptr %t2028, i32 1
  store ptr %t6, ptr %t2031
  call void @__free_recursive(ptr %t6)
  store ptr %t2027, ptr %t3
  store ptr %t2028, ptr %t4
  br label %tco.loop.0
tco.case.arm.128.2032:
  %t2033 = getelementptr ptr, ptr %t5, i32 1
  %t2034 = load ptr, ptr %t2033
  %t2035 = getelementptr ptr, ptr %t5, i32 2
  %t2036 = load ptr, ptr %t2035
  %t2037 = getelementptr i8, ptr %t5, i64 -8
  %t2038 = load i32, ptr %t2037
  %t2039 = icmp eq i32 %t2038, 1
  br i1 %t2039, label %reuse.in_place.2040, label %reuse.copy.2041
reuse.in_place.2040:
  %t2043 = inttoptr i64 114 to ptr
  %t2044 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2043, ptr %t2044
  br label %reuse.join.2042
reuse.copy.2041:
  %t2045 = call ptr @__alloc(i64 24, i32 2)
  %t2046 = inttoptr i64 114 to ptr
  %t2047 = getelementptr ptr, ptr %t2045, i32 0
  store ptr %t2046, ptr %t2047
  call void @__inc_ref(ptr %t2034)
  %t2048 = getelementptr ptr, ptr %t2045, i32 1
  store ptr %t2034, ptr %t2048
  call void @__inc_ref(ptr %t2036)
  %t2049 = getelementptr ptr, ptr %t2045, i32 2
  store ptr %t2036, ptr %t2049
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2042
reuse.join.2042:
  %t2050 = phi ptr [ %t5, %reuse.in_place.2040 ], [ %t2045, %reuse.copy.2041 ]
  %t2051 = call ptr @__alloc(i64 16, i32 1)
  %t2052 = inttoptr i64 274 to ptr
  %t2053 = getelementptr ptr, ptr %t2051, i32 0
  store ptr %t2052, ptr %t2053
  call void @__inc_ref(ptr %t6)
  %t2054 = getelementptr ptr, ptr %t2051, i32 1
  store ptr %t6, ptr %t2054
  call void @__free_recursive(ptr %t6)
  store ptr %t2050, ptr %t3
  store ptr %t2051, ptr %t4
  br label %tco.loop.0
tco.case.arm.129.2055:
  %t2056 = getelementptr ptr, ptr %t5, i32 1
  %t2057 = load ptr, ptr %t2056
  %t2058 = getelementptr ptr, ptr %t5, i32 2
  %t2059 = load ptr, ptr %t2058
  %t2060 = getelementptr i8, ptr %t5, i64 -8
  %t2061 = load i32, ptr %t2060
  %t2062 = icmp eq i32 %t2061, 1
  br i1 %t2062, label %reuse.in_place.2063, label %reuse.copy.2064
reuse.in_place.2063:
  %t2066 = inttoptr i64 114 to ptr
  %t2067 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2066, ptr %t2067
  br label %reuse.join.2065
reuse.copy.2064:
  %t2068 = call ptr @__alloc(i64 24, i32 2)
  %t2069 = inttoptr i64 114 to ptr
  %t2070 = getelementptr ptr, ptr %t2068, i32 0
  store ptr %t2069, ptr %t2070
  call void @__inc_ref(ptr %t2057)
  %t2071 = getelementptr ptr, ptr %t2068, i32 1
  store ptr %t2057, ptr %t2071
  call void @__inc_ref(ptr %t2059)
  %t2072 = getelementptr ptr, ptr %t2068, i32 2
  store ptr %t2059, ptr %t2072
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2065
reuse.join.2065:
  %t2073 = phi ptr [ %t5, %reuse.in_place.2063 ], [ %t2068, %reuse.copy.2064 ]
  %t2074 = call ptr @__alloc(i64 16, i32 1)
  %t2075 = inttoptr i64 275 to ptr
  %t2076 = getelementptr ptr, ptr %t2074, i32 0
  store ptr %t2075, ptr %t2076
  call void @__inc_ref(ptr %t6)
  %t2077 = getelementptr ptr, ptr %t2074, i32 1
  store ptr %t6, ptr %t2077
  call void @__free_recursive(ptr %t6)
  store ptr %t2073, ptr %t3
  store ptr %t2074, ptr %t4
  br label %tco.loop.0
tco.case.arm.130.2078:
  %t2079 = getelementptr ptr, ptr %t5, i32 1
  %t2080 = load ptr, ptr %t2079
  %t2081 = getelementptr ptr, ptr %t5, i32 2
  %t2082 = load ptr, ptr %t2081
  %t2083 = getelementptr i8, ptr %t5, i64 -8
  %t2084 = load i32, ptr %t2083
  %t2085 = icmp eq i32 %t2084, 1
  br i1 %t2085, label %reuse.in_place.2086, label %reuse.copy.2087
reuse.in_place.2086:
  %t2089 = inttoptr i64 114 to ptr
  %t2090 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2089, ptr %t2090
  br label %reuse.join.2088
reuse.copy.2087:
  %t2091 = call ptr @__alloc(i64 24, i32 2)
  %t2092 = inttoptr i64 114 to ptr
  %t2093 = getelementptr ptr, ptr %t2091, i32 0
  store ptr %t2092, ptr %t2093
  call void @__inc_ref(ptr %t2080)
  %t2094 = getelementptr ptr, ptr %t2091, i32 1
  store ptr %t2080, ptr %t2094
  call void @__inc_ref(ptr %t2082)
  %t2095 = getelementptr ptr, ptr %t2091, i32 2
  store ptr %t2082, ptr %t2095
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2088
reuse.join.2088:
  %t2096 = phi ptr [ %t5, %reuse.in_place.2086 ], [ %t2091, %reuse.copy.2087 ]
  %t2097 = call ptr @__alloc(i64 16, i32 1)
  %t2098 = inttoptr i64 276 to ptr
  %t2099 = getelementptr ptr, ptr %t2097, i32 0
  store ptr %t2098, ptr %t2099
  call void @__inc_ref(ptr %t6)
  %t2100 = getelementptr ptr, ptr %t2097, i32 1
  store ptr %t6, ptr %t2100
  call void @__free_recursive(ptr %t6)
  store ptr %t2096, ptr %t3
  store ptr %t2097, ptr %t4
  br label %tco.loop.0
tco.case.arm.131.2101:
  %t2102 = getelementptr ptr, ptr %t5, i32 1
  %t2103 = load ptr, ptr %t2102
  %t2104 = getelementptr ptr, ptr %t5, i32 2
  %t2105 = load ptr, ptr %t2104
  %t2106 = getelementptr i8, ptr %t5, i64 -8
  %t2107 = load i32, ptr %t2106
  %t2108 = icmp eq i32 %t2107, 1
  br i1 %t2108, label %reuse.in_place.2109, label %reuse.copy.2110
reuse.in_place.2109:
  %t2112 = inttoptr i64 114 to ptr
  %t2113 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2112, ptr %t2113
  br label %reuse.join.2111
reuse.copy.2110:
  %t2114 = call ptr @__alloc(i64 24, i32 2)
  %t2115 = inttoptr i64 114 to ptr
  %t2116 = getelementptr ptr, ptr %t2114, i32 0
  store ptr %t2115, ptr %t2116
  call void @__inc_ref(ptr %t2103)
  %t2117 = getelementptr ptr, ptr %t2114, i32 1
  store ptr %t2103, ptr %t2117
  call void @__inc_ref(ptr %t2105)
  %t2118 = getelementptr ptr, ptr %t2114, i32 2
  store ptr %t2105, ptr %t2118
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2111
reuse.join.2111:
  %t2119 = phi ptr [ %t5, %reuse.in_place.2109 ], [ %t2114, %reuse.copy.2110 ]
  %t2120 = call ptr @__alloc(i64 16, i32 1)
  %t2121 = inttoptr i64 277 to ptr
  %t2122 = getelementptr ptr, ptr %t2120, i32 0
  store ptr %t2121, ptr %t2122
  call void @__inc_ref(ptr %t6)
  %t2123 = getelementptr ptr, ptr %t2120, i32 1
  store ptr %t6, ptr %t2123
  call void @__free_recursive(ptr %t6)
  store ptr %t2119, ptr %t3
  store ptr %t2120, ptr %t4
  br label %tco.loop.0
tco.case.arm.132.2124:
  %t2125 = getelementptr ptr, ptr %t5, i32 1
  %t2126 = load ptr, ptr %t2125
  %t2127 = getelementptr ptr, ptr %t5, i32 2
  %t2128 = load ptr, ptr %t2127
  %t2129 = getelementptr i8, ptr %t5, i64 -8
  %t2130 = load i32, ptr %t2129
  %t2131 = icmp eq i32 %t2130, 1
  br i1 %t2131, label %reuse.in_place.2132, label %reuse.copy.2133
reuse.in_place.2132:
  %t2135 = inttoptr i64 114 to ptr
  %t2136 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2135, ptr %t2136
  br label %reuse.join.2134
reuse.copy.2133:
  %t2137 = call ptr @__alloc(i64 24, i32 2)
  %t2138 = inttoptr i64 114 to ptr
  %t2139 = getelementptr ptr, ptr %t2137, i32 0
  store ptr %t2138, ptr %t2139
  call void @__inc_ref(ptr %t2126)
  %t2140 = getelementptr ptr, ptr %t2137, i32 1
  store ptr %t2126, ptr %t2140
  call void @__inc_ref(ptr %t2128)
  %t2141 = getelementptr ptr, ptr %t2137, i32 2
  store ptr %t2128, ptr %t2141
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2134
reuse.join.2134:
  %t2142 = phi ptr [ %t5, %reuse.in_place.2132 ], [ %t2137, %reuse.copy.2133 ]
  %t2143 = call ptr @__alloc(i64 16, i32 1)
  %t2144 = inttoptr i64 278 to ptr
  %t2145 = getelementptr ptr, ptr %t2143, i32 0
  store ptr %t2144, ptr %t2145
  call void @__inc_ref(ptr %t6)
  %t2146 = getelementptr ptr, ptr %t2143, i32 1
  store ptr %t6, ptr %t2146
  call void @__free_recursive(ptr %t6)
  store ptr %t2142, ptr %t3
  store ptr %t2143, ptr %t4
  br label %tco.loop.0
tco.case.arm.133.2147:
  %t2148 = getelementptr ptr, ptr %t5, i32 1
  %t2149 = load ptr, ptr %t2148
  %t2150 = getelementptr ptr, ptr %t5, i32 2
  %t2151 = load ptr, ptr %t2150
  %t2152 = getelementptr i8, ptr %t5, i64 -8
  %t2153 = load i32, ptr %t2152
  %t2154 = icmp eq i32 %t2153, 1
  br i1 %t2154, label %reuse.in_place.2155, label %reuse.copy.2156
reuse.in_place.2155:
  %t2158 = inttoptr i64 114 to ptr
  %t2159 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2158, ptr %t2159
  br label %reuse.join.2157
reuse.copy.2156:
  %t2160 = call ptr @__alloc(i64 24, i32 2)
  %t2161 = inttoptr i64 114 to ptr
  %t2162 = getelementptr ptr, ptr %t2160, i32 0
  store ptr %t2161, ptr %t2162
  call void @__inc_ref(ptr %t2149)
  %t2163 = getelementptr ptr, ptr %t2160, i32 1
  store ptr %t2149, ptr %t2163
  call void @__inc_ref(ptr %t2151)
  %t2164 = getelementptr ptr, ptr %t2160, i32 2
  store ptr %t2151, ptr %t2164
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2157
reuse.join.2157:
  %t2165 = phi ptr [ %t5, %reuse.in_place.2155 ], [ %t2160, %reuse.copy.2156 ]
  %t2166 = call ptr @__alloc(i64 16, i32 1)
  %t2167 = inttoptr i64 279 to ptr
  %t2168 = getelementptr ptr, ptr %t2166, i32 0
  store ptr %t2167, ptr %t2168
  call void @__inc_ref(ptr %t6)
  %t2169 = getelementptr ptr, ptr %t2166, i32 1
  store ptr %t6, ptr %t2169
  call void @__free_recursive(ptr %t6)
  store ptr %t2165, ptr %t3
  store ptr %t2166, ptr %t4
  br label %tco.loop.0
tco.case.arm.134.2170:
  %t2171 = getelementptr ptr, ptr %t5, i32 1
  %t2172 = load ptr, ptr %t2171
  %t2173 = getelementptr ptr, ptr %t5, i32 2
  %t2174 = load ptr, ptr %t2173
  %t2175 = getelementptr i8, ptr %t5, i64 -8
  %t2176 = load i32, ptr %t2175
  %t2177 = icmp eq i32 %t2176, 1
  br i1 %t2177, label %reuse.in_place.2178, label %reuse.copy.2179
reuse.in_place.2178:
  %t2181 = inttoptr i64 114 to ptr
  %t2182 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2181, ptr %t2182
  br label %reuse.join.2180
reuse.copy.2179:
  %t2183 = call ptr @__alloc(i64 24, i32 2)
  %t2184 = inttoptr i64 114 to ptr
  %t2185 = getelementptr ptr, ptr %t2183, i32 0
  store ptr %t2184, ptr %t2185
  call void @__inc_ref(ptr %t2172)
  %t2186 = getelementptr ptr, ptr %t2183, i32 1
  store ptr %t2172, ptr %t2186
  call void @__inc_ref(ptr %t2174)
  %t2187 = getelementptr ptr, ptr %t2183, i32 2
  store ptr %t2174, ptr %t2187
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2180
reuse.join.2180:
  %t2188 = phi ptr [ %t5, %reuse.in_place.2178 ], [ %t2183, %reuse.copy.2179 ]
  %t2189 = call ptr @__alloc(i64 16, i32 1)
  %t2190 = inttoptr i64 280 to ptr
  %t2191 = getelementptr ptr, ptr %t2189, i32 0
  store ptr %t2190, ptr %t2191
  call void @__inc_ref(ptr %t6)
  %t2192 = getelementptr ptr, ptr %t2189, i32 1
  store ptr %t6, ptr %t2192
  call void @__free_recursive(ptr %t6)
  store ptr %t2188, ptr %t3
  store ptr %t2189, ptr %t4
  br label %tco.loop.0
tco.case.arm.135.2193:
  %t2194 = getelementptr ptr, ptr %t5, i32 1
  %t2195 = load ptr, ptr %t2194
  %t2196 = getelementptr ptr, ptr %t5, i32 2
  %t2197 = load ptr, ptr %t2196
  %t2198 = getelementptr i8, ptr %t5, i64 -8
  %t2199 = load i32, ptr %t2198
  %t2200 = icmp eq i32 %t2199, 1
  br i1 %t2200, label %reuse.in_place.2201, label %reuse.copy.2202
reuse.in_place.2201:
  %t2204 = inttoptr i64 114 to ptr
  %t2205 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2204, ptr %t2205
  br label %reuse.join.2203
reuse.copy.2202:
  %t2206 = call ptr @__alloc(i64 24, i32 2)
  %t2207 = inttoptr i64 114 to ptr
  %t2208 = getelementptr ptr, ptr %t2206, i32 0
  store ptr %t2207, ptr %t2208
  call void @__inc_ref(ptr %t2195)
  %t2209 = getelementptr ptr, ptr %t2206, i32 1
  store ptr %t2195, ptr %t2209
  call void @__inc_ref(ptr %t2197)
  %t2210 = getelementptr ptr, ptr %t2206, i32 2
  store ptr %t2197, ptr %t2210
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2203
reuse.join.2203:
  %t2211 = phi ptr [ %t5, %reuse.in_place.2201 ], [ %t2206, %reuse.copy.2202 ]
  %t2212 = call ptr @__alloc(i64 16, i32 1)
  %t2213 = inttoptr i64 281 to ptr
  %t2214 = getelementptr ptr, ptr %t2212, i32 0
  store ptr %t2213, ptr %t2214
  call void @__inc_ref(ptr %t6)
  %t2215 = getelementptr ptr, ptr %t2212, i32 1
  store ptr %t6, ptr %t2215
  call void @__free_recursive(ptr %t6)
  store ptr %t2211, ptr %t3
  store ptr %t2212, ptr %t4
  br label %tco.loop.0
tco.case.arm.136.2216:
  %t2217 = getelementptr ptr, ptr %t5, i32 1
  %t2218 = load ptr, ptr %t2217
  %t2219 = getelementptr ptr, ptr %t5, i32 2
  %t2220 = load ptr, ptr %t2219
  %t2221 = getelementptr i8, ptr %t5, i64 -8
  %t2222 = load i32, ptr %t2221
  %t2223 = icmp eq i32 %t2222, 1
  br i1 %t2223, label %reuse.in_place.2224, label %reuse.copy.2225
reuse.in_place.2224:
  %t2227 = inttoptr i64 114 to ptr
  %t2228 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2227, ptr %t2228
  br label %reuse.join.2226
reuse.copy.2225:
  %t2229 = call ptr @__alloc(i64 24, i32 2)
  %t2230 = inttoptr i64 114 to ptr
  %t2231 = getelementptr ptr, ptr %t2229, i32 0
  store ptr %t2230, ptr %t2231
  call void @__inc_ref(ptr %t2218)
  %t2232 = getelementptr ptr, ptr %t2229, i32 1
  store ptr %t2218, ptr %t2232
  call void @__inc_ref(ptr %t2220)
  %t2233 = getelementptr ptr, ptr %t2229, i32 2
  store ptr %t2220, ptr %t2233
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2226
reuse.join.2226:
  %t2234 = phi ptr [ %t5, %reuse.in_place.2224 ], [ %t2229, %reuse.copy.2225 ]
  %t2235 = call ptr @__alloc(i64 16, i32 1)
  %t2236 = inttoptr i64 282 to ptr
  %t2237 = getelementptr ptr, ptr %t2235, i32 0
  store ptr %t2236, ptr %t2237
  call void @__inc_ref(ptr %t6)
  %t2238 = getelementptr ptr, ptr %t2235, i32 1
  store ptr %t6, ptr %t2238
  call void @__free_recursive(ptr %t6)
  store ptr %t2234, ptr %t3
  store ptr %t2235, ptr %t4
  br label %tco.loop.0
tco.case.arm.137.2239:
  %t2240 = getelementptr ptr, ptr %t5, i32 1
  %t2241 = load ptr, ptr %t2240
  %t2242 = getelementptr ptr, ptr %t5, i32 2
  %t2243 = load ptr, ptr %t2242
  %t2244 = getelementptr i8, ptr %t5, i64 -8
  %t2245 = load i32, ptr %t2244
  %t2246 = icmp eq i32 %t2245, 1
  br i1 %t2246, label %reuse.in_place.2247, label %reuse.copy.2248
reuse.in_place.2247:
  %t2250 = inttoptr i64 114 to ptr
  %t2251 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2250, ptr %t2251
  br label %reuse.join.2249
reuse.copy.2248:
  %t2252 = call ptr @__alloc(i64 24, i32 2)
  %t2253 = inttoptr i64 114 to ptr
  %t2254 = getelementptr ptr, ptr %t2252, i32 0
  store ptr %t2253, ptr %t2254
  call void @__inc_ref(ptr %t2241)
  %t2255 = getelementptr ptr, ptr %t2252, i32 1
  store ptr %t2241, ptr %t2255
  call void @__inc_ref(ptr %t2243)
  %t2256 = getelementptr ptr, ptr %t2252, i32 2
  store ptr %t2243, ptr %t2256
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2249
reuse.join.2249:
  %t2257 = phi ptr [ %t5, %reuse.in_place.2247 ], [ %t2252, %reuse.copy.2248 ]
  %t2258 = call ptr @__alloc(i64 16, i32 1)
  %t2259 = inttoptr i64 283 to ptr
  %t2260 = getelementptr ptr, ptr %t2258, i32 0
  store ptr %t2259, ptr %t2260
  call void @__inc_ref(ptr %t6)
  %t2261 = getelementptr ptr, ptr %t2258, i32 1
  store ptr %t6, ptr %t2261
  call void @__free_recursive(ptr %t6)
  store ptr %t2257, ptr %t3
  store ptr %t2258, ptr %t4
  br label %tco.loop.0
tco.case.arm.138.2262:
  %t2263 = getelementptr ptr, ptr %t5, i32 1
  %t2264 = load ptr, ptr %t2263
  %t2265 = getelementptr ptr, ptr %t5, i32 2
  %t2266 = load ptr, ptr %t2265
  %t2267 = getelementptr i8, ptr %t5, i64 -8
  %t2268 = load i32, ptr %t2267
  %t2269 = icmp eq i32 %t2268, 1
  br i1 %t2269, label %reuse.in_place.2270, label %reuse.copy.2271
reuse.in_place.2270:
  %t2273 = inttoptr i64 114 to ptr
  %t2274 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2273, ptr %t2274
  br label %reuse.join.2272
reuse.copy.2271:
  %t2275 = call ptr @__alloc(i64 24, i32 2)
  %t2276 = inttoptr i64 114 to ptr
  %t2277 = getelementptr ptr, ptr %t2275, i32 0
  store ptr %t2276, ptr %t2277
  call void @__inc_ref(ptr %t2264)
  %t2278 = getelementptr ptr, ptr %t2275, i32 1
  store ptr %t2264, ptr %t2278
  call void @__inc_ref(ptr %t2266)
  %t2279 = getelementptr ptr, ptr %t2275, i32 2
  store ptr %t2266, ptr %t2279
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2272
reuse.join.2272:
  %t2280 = phi ptr [ %t5, %reuse.in_place.2270 ], [ %t2275, %reuse.copy.2271 ]
  %t2281 = call ptr @__alloc(i64 16, i32 1)
  %t2282 = inttoptr i64 284 to ptr
  %t2283 = getelementptr ptr, ptr %t2281, i32 0
  store ptr %t2282, ptr %t2283
  call void @__inc_ref(ptr %t6)
  %t2284 = getelementptr ptr, ptr %t2281, i32 1
  store ptr %t6, ptr %t2284
  call void @__free_recursive(ptr %t6)
  store ptr %t2280, ptr %t3
  store ptr %t2281, ptr %t4
  br label %tco.loop.0
tco.case.arm.139.2285:
  %t2286 = getelementptr ptr, ptr %t5, i32 1
  %t2287 = load ptr, ptr %t2286
  %t2288 = getelementptr ptr, ptr %t5, i32 2
  %t2289 = load ptr, ptr %t2288
  %t2290 = getelementptr i8, ptr %t5, i64 -8
  %t2291 = load i32, ptr %t2290
  %t2292 = icmp eq i32 %t2291, 1
  br i1 %t2292, label %reuse.in_place.2293, label %reuse.copy.2294
reuse.in_place.2293:
  %t2296 = inttoptr i64 114 to ptr
  %t2297 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2296, ptr %t2297
  br label %reuse.join.2295
reuse.copy.2294:
  %t2298 = call ptr @__alloc(i64 24, i32 2)
  %t2299 = inttoptr i64 114 to ptr
  %t2300 = getelementptr ptr, ptr %t2298, i32 0
  store ptr %t2299, ptr %t2300
  call void @__inc_ref(ptr %t2287)
  %t2301 = getelementptr ptr, ptr %t2298, i32 1
  store ptr %t2287, ptr %t2301
  call void @__inc_ref(ptr %t2289)
  %t2302 = getelementptr ptr, ptr %t2298, i32 2
  store ptr %t2289, ptr %t2302
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2295
reuse.join.2295:
  %t2303 = phi ptr [ %t5, %reuse.in_place.2293 ], [ %t2298, %reuse.copy.2294 ]
  %t2304 = call ptr @__alloc(i64 16, i32 1)
  %t2305 = inttoptr i64 285 to ptr
  %t2306 = getelementptr ptr, ptr %t2304, i32 0
  store ptr %t2305, ptr %t2306
  call void @__inc_ref(ptr %t6)
  %t2307 = getelementptr ptr, ptr %t2304, i32 1
  store ptr %t6, ptr %t2307
  call void @__free_recursive(ptr %t6)
  store ptr %t2303, ptr %t3
  store ptr %t2304, ptr %t4
  br label %tco.loop.0
tco.case.arm.140.2308:
  %t2309 = getelementptr ptr, ptr %t5, i32 1
  %t2310 = load ptr, ptr %t2309
  %t2311 = getelementptr ptr, ptr %t5, i32 2
  %t2312 = load ptr, ptr %t2311
  %t2313 = getelementptr i8, ptr %t5, i64 -8
  %t2314 = load i32, ptr %t2313
  %t2315 = icmp eq i32 %t2314, 1
  br i1 %t2315, label %reuse.in_place.2316, label %reuse.copy.2317
reuse.in_place.2316:
  %t2319 = inttoptr i64 114 to ptr
  %t2320 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2319, ptr %t2320
  br label %reuse.join.2318
reuse.copy.2317:
  %t2321 = call ptr @__alloc(i64 24, i32 2)
  %t2322 = inttoptr i64 114 to ptr
  %t2323 = getelementptr ptr, ptr %t2321, i32 0
  store ptr %t2322, ptr %t2323
  call void @__inc_ref(ptr %t2310)
  %t2324 = getelementptr ptr, ptr %t2321, i32 1
  store ptr %t2310, ptr %t2324
  call void @__inc_ref(ptr %t2312)
  %t2325 = getelementptr ptr, ptr %t2321, i32 2
  store ptr %t2312, ptr %t2325
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2318
reuse.join.2318:
  %t2326 = phi ptr [ %t5, %reuse.in_place.2316 ], [ %t2321, %reuse.copy.2317 ]
  %t2327 = call ptr @__alloc(i64 16, i32 1)
  %t2328 = inttoptr i64 286 to ptr
  %t2329 = getelementptr ptr, ptr %t2327, i32 0
  store ptr %t2328, ptr %t2329
  call void @__inc_ref(ptr %t6)
  %t2330 = getelementptr ptr, ptr %t2327, i32 1
  store ptr %t6, ptr %t2330
  call void @__free_recursive(ptr %t6)
  store ptr %t2326, ptr %t3
  store ptr %t2327, ptr %t4
  br label %tco.loop.0
tco.case.arm.141.2331:
  %t2332 = getelementptr ptr, ptr %t5, i32 1
  %t2333 = load ptr, ptr %t2332
  %t2334 = getelementptr ptr, ptr %t5, i32 2
  %t2335 = load ptr, ptr %t2334
  %t2336 = getelementptr i8, ptr %t5, i64 -8
  %t2337 = load i32, ptr %t2336
  %t2338 = icmp eq i32 %t2337, 1
  br i1 %t2338, label %reuse.in_place.2339, label %reuse.copy.2340
reuse.in_place.2339:
  %t2342 = inttoptr i64 114 to ptr
  %t2343 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2342, ptr %t2343
  br label %reuse.join.2341
reuse.copy.2340:
  %t2344 = call ptr @__alloc(i64 24, i32 2)
  %t2345 = inttoptr i64 114 to ptr
  %t2346 = getelementptr ptr, ptr %t2344, i32 0
  store ptr %t2345, ptr %t2346
  call void @__inc_ref(ptr %t2333)
  %t2347 = getelementptr ptr, ptr %t2344, i32 1
  store ptr %t2333, ptr %t2347
  call void @__inc_ref(ptr %t2335)
  %t2348 = getelementptr ptr, ptr %t2344, i32 2
  store ptr %t2335, ptr %t2348
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2341
reuse.join.2341:
  %t2349 = phi ptr [ %t5, %reuse.in_place.2339 ], [ %t2344, %reuse.copy.2340 ]
  %t2350 = call ptr @__alloc(i64 16, i32 1)
  %t2351 = inttoptr i64 287 to ptr
  %t2352 = getelementptr ptr, ptr %t2350, i32 0
  store ptr %t2351, ptr %t2352
  call void @__inc_ref(ptr %t6)
  %t2353 = getelementptr ptr, ptr %t2350, i32 1
  store ptr %t6, ptr %t2353
  call void @__free_recursive(ptr %t6)
  store ptr %t2349, ptr %t3
  store ptr %t2350, ptr %t4
  br label %tco.loop.0
tco.case.arm.142.2354:
  %t2355 = getelementptr ptr, ptr %t5, i32 1
  %t2356 = load ptr, ptr %t2355
  %t2357 = getelementptr ptr, ptr %t5, i32 2
  %t2358 = load ptr, ptr %t2357
  %t2359 = getelementptr i8, ptr %t5, i64 -8
  %t2360 = load i32, ptr %t2359
  %t2361 = icmp eq i32 %t2360, 1
  br i1 %t2361, label %reuse.in_place.2362, label %reuse.copy.2363
reuse.in_place.2362:
  %t2365 = inttoptr i64 114 to ptr
  %t2366 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2365, ptr %t2366
  br label %reuse.join.2364
reuse.copy.2363:
  %t2367 = call ptr @__alloc(i64 24, i32 2)
  %t2368 = inttoptr i64 114 to ptr
  %t2369 = getelementptr ptr, ptr %t2367, i32 0
  store ptr %t2368, ptr %t2369
  call void @__inc_ref(ptr %t2356)
  %t2370 = getelementptr ptr, ptr %t2367, i32 1
  store ptr %t2356, ptr %t2370
  call void @__inc_ref(ptr %t2358)
  %t2371 = getelementptr ptr, ptr %t2367, i32 2
  store ptr %t2358, ptr %t2371
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2364
reuse.join.2364:
  %t2372 = phi ptr [ %t5, %reuse.in_place.2362 ], [ %t2367, %reuse.copy.2363 ]
  %t2373 = call ptr @__alloc(i64 16, i32 1)
  %t2374 = inttoptr i64 288 to ptr
  %t2375 = getelementptr ptr, ptr %t2373, i32 0
  store ptr %t2374, ptr %t2375
  call void @__inc_ref(ptr %t6)
  %t2376 = getelementptr ptr, ptr %t2373, i32 1
  store ptr %t6, ptr %t2376
  call void @__free_recursive(ptr %t6)
  store ptr %t2372, ptr %t3
  store ptr %t2373, ptr %t4
  br label %tco.loop.0
tco.case.arm.143.2377:
  %t2378 = getelementptr ptr, ptr %t5, i32 1
  %t2379 = load ptr, ptr %t2378
  %t2380 = getelementptr ptr, ptr %t5, i32 2
  %t2381 = load ptr, ptr %t2380
  %t2382 = getelementptr i8, ptr %t5, i64 -8
  %t2383 = load i32, ptr %t2382
  %t2384 = icmp eq i32 %t2383, 1
  br i1 %t2384, label %reuse.in_place.2385, label %reuse.copy.2386
reuse.in_place.2385:
  %t2388 = inttoptr i64 114 to ptr
  %t2389 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2388, ptr %t2389
  br label %reuse.join.2387
reuse.copy.2386:
  %t2390 = call ptr @__alloc(i64 24, i32 2)
  %t2391 = inttoptr i64 114 to ptr
  %t2392 = getelementptr ptr, ptr %t2390, i32 0
  store ptr %t2391, ptr %t2392
  call void @__inc_ref(ptr %t2379)
  %t2393 = getelementptr ptr, ptr %t2390, i32 1
  store ptr %t2379, ptr %t2393
  call void @__inc_ref(ptr %t2381)
  %t2394 = getelementptr ptr, ptr %t2390, i32 2
  store ptr %t2381, ptr %t2394
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2387
reuse.join.2387:
  %t2395 = phi ptr [ %t5, %reuse.in_place.2385 ], [ %t2390, %reuse.copy.2386 ]
  %t2396 = call ptr @__alloc(i64 16, i32 1)
  %t2397 = inttoptr i64 289 to ptr
  %t2398 = getelementptr ptr, ptr %t2396, i32 0
  store ptr %t2397, ptr %t2398
  call void @__inc_ref(ptr %t6)
  %t2399 = getelementptr ptr, ptr %t2396, i32 1
  store ptr %t6, ptr %t2399
  call void @__free_recursive(ptr %t6)
  store ptr %t2395, ptr %t3
  store ptr %t2396, ptr %t4
  br label %tco.loop.0
tco.case.arm.144.2400:
  %t2401 = getelementptr ptr, ptr %t5, i32 1
  %t2402 = load ptr, ptr %t2401
  %t2403 = getelementptr ptr, ptr %t5, i32 2
  %t2404 = load ptr, ptr %t2403
  %t2405 = getelementptr i8, ptr %t5, i64 -8
  %t2406 = load i32, ptr %t2405
  %t2407 = icmp eq i32 %t2406, 1
  br i1 %t2407, label %reuse.in_place.2408, label %reuse.copy.2409
reuse.in_place.2408:
  %t2411 = inttoptr i64 114 to ptr
  %t2412 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2411, ptr %t2412
  br label %reuse.join.2410
reuse.copy.2409:
  %t2413 = call ptr @__alloc(i64 24, i32 2)
  %t2414 = inttoptr i64 114 to ptr
  %t2415 = getelementptr ptr, ptr %t2413, i32 0
  store ptr %t2414, ptr %t2415
  call void @__inc_ref(ptr %t2402)
  %t2416 = getelementptr ptr, ptr %t2413, i32 1
  store ptr %t2402, ptr %t2416
  call void @__inc_ref(ptr %t2404)
  %t2417 = getelementptr ptr, ptr %t2413, i32 2
  store ptr %t2404, ptr %t2417
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2410
reuse.join.2410:
  %t2418 = phi ptr [ %t5, %reuse.in_place.2408 ], [ %t2413, %reuse.copy.2409 ]
  %t2419 = call ptr @__alloc(i64 16, i32 1)
  %t2420 = inttoptr i64 290 to ptr
  %t2421 = getelementptr ptr, ptr %t2419, i32 0
  store ptr %t2420, ptr %t2421
  call void @__inc_ref(ptr %t6)
  %t2422 = getelementptr ptr, ptr %t2419, i32 1
  store ptr %t6, ptr %t2422
  call void @__free_recursive(ptr %t6)
  store ptr %t2418, ptr %t3
  store ptr %t2419, ptr %t4
  br label %tco.loop.0
tco.case.arm.145.2423:
  %t2424 = getelementptr ptr, ptr %t5, i32 1
  %t2425 = load ptr, ptr %t2424
  %t2426 = getelementptr ptr, ptr %t5, i32 2
  %t2427 = load ptr, ptr %t2426
  %t2428 = getelementptr i8, ptr %t5, i64 -8
  %t2429 = load i32, ptr %t2428
  %t2430 = icmp eq i32 %t2429, 1
  br i1 %t2430, label %reuse.in_place.2431, label %reuse.copy.2432
reuse.in_place.2431:
  %t2434 = inttoptr i64 114 to ptr
  %t2435 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2434, ptr %t2435
  br label %reuse.join.2433
reuse.copy.2432:
  %t2436 = call ptr @__alloc(i64 24, i32 2)
  %t2437 = inttoptr i64 114 to ptr
  %t2438 = getelementptr ptr, ptr %t2436, i32 0
  store ptr %t2437, ptr %t2438
  call void @__inc_ref(ptr %t2425)
  %t2439 = getelementptr ptr, ptr %t2436, i32 1
  store ptr %t2425, ptr %t2439
  call void @__inc_ref(ptr %t2427)
  %t2440 = getelementptr ptr, ptr %t2436, i32 2
  store ptr %t2427, ptr %t2440
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2433
reuse.join.2433:
  %t2441 = phi ptr [ %t5, %reuse.in_place.2431 ], [ %t2436, %reuse.copy.2432 ]
  %t2442 = call ptr @__alloc(i64 16, i32 1)
  %t2443 = inttoptr i64 291 to ptr
  %t2444 = getelementptr ptr, ptr %t2442, i32 0
  store ptr %t2443, ptr %t2444
  call void @__inc_ref(ptr %t6)
  %t2445 = getelementptr ptr, ptr %t2442, i32 1
  store ptr %t6, ptr %t2445
  call void @__free_recursive(ptr %t6)
  store ptr %t2441, ptr %t3
  store ptr %t2442, ptr %t4
  br label %tco.loop.0
tco.case.arm.146.2446:
  %t2447 = getelementptr ptr, ptr %t5, i32 1
  %t2448 = load ptr, ptr %t2447
  %t2449 = getelementptr ptr, ptr %t5, i32 2
  %t2450 = load ptr, ptr %t2449
  %t2451 = getelementptr i8, ptr %t5, i64 -8
  %t2452 = load i32, ptr %t2451
  %t2453 = icmp eq i32 %t2452, 1
  br i1 %t2453, label %reuse.in_place.2454, label %reuse.copy.2455
reuse.in_place.2454:
  %t2457 = inttoptr i64 114 to ptr
  %t2458 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2457, ptr %t2458
  br label %reuse.join.2456
reuse.copy.2455:
  %t2459 = call ptr @__alloc(i64 24, i32 2)
  %t2460 = inttoptr i64 114 to ptr
  %t2461 = getelementptr ptr, ptr %t2459, i32 0
  store ptr %t2460, ptr %t2461
  call void @__inc_ref(ptr %t2448)
  %t2462 = getelementptr ptr, ptr %t2459, i32 1
  store ptr %t2448, ptr %t2462
  call void @__inc_ref(ptr %t2450)
  %t2463 = getelementptr ptr, ptr %t2459, i32 2
  store ptr %t2450, ptr %t2463
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2456
reuse.join.2456:
  %t2464 = phi ptr [ %t5, %reuse.in_place.2454 ], [ %t2459, %reuse.copy.2455 ]
  %t2465 = call ptr @__alloc(i64 16, i32 1)
  %t2466 = inttoptr i64 292 to ptr
  %t2467 = getelementptr ptr, ptr %t2465, i32 0
  store ptr %t2466, ptr %t2467
  call void @__inc_ref(ptr %t6)
  %t2468 = getelementptr ptr, ptr %t2465, i32 1
  store ptr %t6, ptr %t2468
  call void @__free_recursive(ptr %t6)
  store ptr %t2464, ptr %t3
  store ptr %t2465, ptr %t4
  br label %tco.loop.0
tco.case.arm.147.2469:
  %t2470 = getelementptr ptr, ptr %t5, i32 1
  %t2471 = load ptr, ptr %t2470
  %t2472 = getelementptr ptr, ptr %t5, i32 2
  %t2473 = load ptr, ptr %t2472
  %t2474 = getelementptr i8, ptr %t5, i64 -8
  %t2475 = load i32, ptr %t2474
  %t2476 = icmp eq i32 %t2475, 1
  br i1 %t2476, label %reuse.in_place.2477, label %reuse.copy.2478
reuse.in_place.2477:
  %t2480 = inttoptr i64 114 to ptr
  %t2481 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2480, ptr %t2481
  br label %reuse.join.2479
reuse.copy.2478:
  %t2482 = call ptr @__alloc(i64 24, i32 2)
  %t2483 = inttoptr i64 114 to ptr
  %t2484 = getelementptr ptr, ptr %t2482, i32 0
  store ptr %t2483, ptr %t2484
  call void @__inc_ref(ptr %t2471)
  %t2485 = getelementptr ptr, ptr %t2482, i32 1
  store ptr %t2471, ptr %t2485
  call void @__inc_ref(ptr %t2473)
  %t2486 = getelementptr ptr, ptr %t2482, i32 2
  store ptr %t2473, ptr %t2486
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2479
reuse.join.2479:
  %t2487 = phi ptr [ %t5, %reuse.in_place.2477 ], [ %t2482, %reuse.copy.2478 ]
  %t2488 = call ptr @__alloc(i64 16, i32 1)
  %t2489 = inttoptr i64 293 to ptr
  %t2490 = getelementptr ptr, ptr %t2488, i32 0
  store ptr %t2489, ptr %t2490
  call void @__inc_ref(ptr %t6)
  %t2491 = getelementptr ptr, ptr %t2488, i32 1
  store ptr %t6, ptr %t2491
  call void @__free_recursive(ptr %t6)
  store ptr %t2487, ptr %t3
  store ptr %t2488, ptr %t4
  br label %tco.loop.0
tco.case.arm.148.2492:
  %t2493 = getelementptr ptr, ptr %t5, i32 1
  %t2494 = load ptr, ptr %t2493
  %t2495 = getelementptr ptr, ptr %t5, i32 2
  %t2496 = load ptr, ptr %t2495
  %t2497 = getelementptr i8, ptr %t5, i64 -8
  %t2498 = load i32, ptr %t2497
  %t2499 = icmp eq i32 %t2498, 1
  br i1 %t2499, label %reuse.in_place.2500, label %reuse.copy.2501
reuse.in_place.2500:
  %t2503 = inttoptr i64 114 to ptr
  %t2504 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2503, ptr %t2504
  br label %reuse.join.2502
reuse.copy.2501:
  %t2505 = call ptr @__alloc(i64 24, i32 2)
  %t2506 = inttoptr i64 114 to ptr
  %t2507 = getelementptr ptr, ptr %t2505, i32 0
  store ptr %t2506, ptr %t2507
  call void @__inc_ref(ptr %t2494)
  %t2508 = getelementptr ptr, ptr %t2505, i32 1
  store ptr %t2494, ptr %t2508
  call void @__inc_ref(ptr %t2496)
  %t2509 = getelementptr ptr, ptr %t2505, i32 2
  store ptr %t2496, ptr %t2509
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2502
reuse.join.2502:
  %t2510 = phi ptr [ %t5, %reuse.in_place.2500 ], [ %t2505, %reuse.copy.2501 ]
  %t2511 = call ptr @__alloc(i64 16, i32 1)
  %t2512 = inttoptr i64 294 to ptr
  %t2513 = getelementptr ptr, ptr %t2511, i32 0
  store ptr %t2512, ptr %t2513
  call void @__inc_ref(ptr %t6)
  %t2514 = getelementptr ptr, ptr %t2511, i32 1
  store ptr %t6, ptr %t2514
  call void @__free_recursive(ptr %t6)
  store ptr %t2510, ptr %t3
  store ptr %t2511, ptr %t4
  br label %tco.loop.0
tco.case.arm.149.2515:
  %t2516 = getelementptr ptr, ptr %t5, i32 1
  %t2517 = load ptr, ptr %t2516
  call void @__inc_ref(ptr %t2517)
  %t2518 = getelementptr ptr, ptr %t5, i32 2
  %t2519 = load ptr, ptr %t2518
  call void @__inc_ref(ptr %t2519)
  %t2520 = getelementptr ptr, ptr %t5, i32 3
  %t2521 = load ptr, ptr %t2520
  call void @__inc_ref(ptr %t2521)
  %t2522 = call ptr @__alloc(i64 24, i32 2)
  %t2523 = inttoptr i64 114 to ptr
  %t2524 = getelementptr ptr, ptr %t2522, i32 0
  store ptr %t2523, ptr %t2524
  call void @__inc_ref(ptr %t2517)
  %t2525 = getelementptr ptr, ptr %t2522, i32 1
  store ptr %t2517, ptr %t2525
  call void @__inc_ref(ptr %t2519)
  %t2526 = getelementptr ptr, ptr %t2522, i32 2
  store ptr %t2519, ptr %t2526
  %t2527 = call ptr @__alloc(i64 24, i32 2)
  %t2528 = inttoptr i64 295 to ptr
  %t2529 = getelementptr ptr, ptr %t2527, i32 0
  store ptr %t2528, ptr %t2529
  call void @__inc_ref(ptr %t6)
  %t2530 = getelementptr ptr, ptr %t2527, i32 1
  store ptr %t6, ptr %t2530
  call void @__inc_ref(ptr %t2521)
  %t2531 = getelementptr ptr, ptr %t2527, i32 2
  store ptr %t2521, ptr %t2531
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t2521)
  call void @__free_recursive(ptr %t2519)
  call void @__free_recursive(ptr %t2517)
  store ptr %t2522, ptr %t3
  store ptr %t2527, ptr %t4
  br label %tco.loop.0
tco.case.arm.150.2532:
  %t2533 = getelementptr ptr, ptr %t5, i32 1
  %t2534 = load ptr, ptr %t2533
  %t2535 = getelementptr ptr, ptr %t5, i32 2
  %t2536 = load ptr, ptr %t2535
  %t2537 = getelementptr i8, ptr %t5, i64 -8
  %t2538 = load i32, ptr %t2537
  %t2539 = icmp eq i32 %t2538, 1
  br i1 %t2539, label %reuse.in_place.2540, label %reuse.copy.2541
reuse.in_place.2540:
  %t2543 = inttoptr i64 114 to ptr
  %t2544 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2543, ptr %t2544
  br label %reuse.join.2542
reuse.copy.2541:
  %t2545 = call ptr @__alloc(i64 24, i32 2)
  %t2546 = inttoptr i64 114 to ptr
  %t2547 = getelementptr ptr, ptr %t2545, i32 0
  store ptr %t2546, ptr %t2547
  call void @__inc_ref(ptr %t2534)
  %t2548 = getelementptr ptr, ptr %t2545, i32 1
  store ptr %t2534, ptr %t2548
  call void @__inc_ref(ptr %t2536)
  %t2549 = getelementptr ptr, ptr %t2545, i32 2
  store ptr %t2536, ptr %t2549
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2542
reuse.join.2542:
  %t2550 = phi ptr [ %t5, %reuse.in_place.2540 ], [ %t2545, %reuse.copy.2541 ]
  %t2551 = call ptr @__alloc(i64 16, i32 1)
  %t2552 = inttoptr i64 296 to ptr
  %t2553 = getelementptr ptr, ptr %t2551, i32 0
  store ptr %t2552, ptr %t2553
  call void @__inc_ref(ptr %t6)
  %t2554 = getelementptr ptr, ptr %t2551, i32 1
  store ptr %t6, ptr %t2554
  call void @__free_recursive(ptr %t6)
  store ptr %t2550, ptr %t3
  store ptr %t2551, ptr %t4
  br label %tco.loop.0
tco.case.arm.151.2555:
  %t2556 = getelementptr ptr, ptr %t5, i32 1
  %t2557 = load ptr, ptr %t2556
  %t2558 = getelementptr ptr, ptr %t5, i32 2
  %t2559 = load ptr, ptr %t2558
  %t2560 = getelementptr i8, ptr %t5, i64 -8
  %t2561 = load i32, ptr %t2560
  %t2562 = icmp eq i32 %t2561, 1
  br i1 %t2562, label %reuse.in_place.2563, label %reuse.copy.2564
reuse.in_place.2563:
  %t2566 = inttoptr i64 114 to ptr
  %t2567 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2566, ptr %t2567
  br label %reuse.join.2565
reuse.copy.2564:
  %t2568 = call ptr @__alloc(i64 24, i32 2)
  %t2569 = inttoptr i64 114 to ptr
  %t2570 = getelementptr ptr, ptr %t2568, i32 0
  store ptr %t2569, ptr %t2570
  call void @__inc_ref(ptr %t2557)
  %t2571 = getelementptr ptr, ptr %t2568, i32 1
  store ptr %t2557, ptr %t2571
  call void @__inc_ref(ptr %t2559)
  %t2572 = getelementptr ptr, ptr %t2568, i32 2
  store ptr %t2559, ptr %t2572
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2565
reuse.join.2565:
  %t2573 = phi ptr [ %t5, %reuse.in_place.2563 ], [ %t2568, %reuse.copy.2564 ]
  %t2574 = call ptr @__alloc(i64 16, i32 1)
  %t2575 = inttoptr i64 297 to ptr
  %t2576 = getelementptr ptr, ptr %t2574, i32 0
  store ptr %t2575, ptr %t2576
  call void @__inc_ref(ptr %t6)
  %t2577 = getelementptr ptr, ptr %t2574, i32 1
  store ptr %t6, ptr %t2577
  call void @__free_recursive(ptr %t6)
  store ptr %t2573, ptr %t3
  store ptr %t2574, ptr %t4
  br label %tco.loop.0
tco.case.arm.152.2578:
  %t2579 = getelementptr ptr, ptr %t5, i32 1
  %t2580 = load ptr, ptr %t2579
  %t2581 = getelementptr ptr, ptr %t5, i32 2
  %t2582 = load ptr, ptr %t2581
  %t2583 = getelementptr i8, ptr %t5, i64 -8
  %t2584 = load i32, ptr %t2583
  %t2585 = icmp eq i32 %t2584, 1
  br i1 %t2585, label %reuse.in_place.2586, label %reuse.copy.2587
reuse.in_place.2586:
  %t2589 = inttoptr i64 114 to ptr
  %t2590 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2589, ptr %t2590
  br label %reuse.join.2588
reuse.copy.2587:
  %t2591 = call ptr @__alloc(i64 24, i32 2)
  %t2592 = inttoptr i64 114 to ptr
  %t2593 = getelementptr ptr, ptr %t2591, i32 0
  store ptr %t2592, ptr %t2593
  call void @__inc_ref(ptr %t2580)
  %t2594 = getelementptr ptr, ptr %t2591, i32 1
  store ptr %t2580, ptr %t2594
  call void @__inc_ref(ptr %t2582)
  %t2595 = getelementptr ptr, ptr %t2591, i32 2
  store ptr %t2582, ptr %t2595
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2588
reuse.join.2588:
  %t2596 = phi ptr [ %t5, %reuse.in_place.2586 ], [ %t2591, %reuse.copy.2587 ]
  %t2597 = call ptr @__alloc(i64 16, i32 1)
  %t2598 = inttoptr i64 298 to ptr
  %t2599 = getelementptr ptr, ptr %t2597, i32 0
  store ptr %t2598, ptr %t2599
  call void @__inc_ref(ptr %t6)
  %t2600 = getelementptr ptr, ptr %t2597, i32 1
  store ptr %t6, ptr %t2600
  call void @__free_recursive(ptr %t6)
  store ptr %t2596, ptr %t3
  store ptr %t2597, ptr %t4
  br label %tco.loop.0
tco.case.arm.153.2601:
  %t2602 = getelementptr ptr, ptr %t5, i32 1
  %t2603 = load ptr, ptr %t2602
  %t2604 = getelementptr ptr, ptr %t5, i32 2
  %t2605 = load ptr, ptr %t2604
  %t2606 = getelementptr i8, ptr %t5, i64 -8
  %t2607 = load i32, ptr %t2606
  %t2608 = icmp eq i32 %t2607, 1
  br i1 %t2608, label %reuse.in_place.2609, label %reuse.copy.2610
reuse.in_place.2609:
  %t2612 = inttoptr i64 114 to ptr
  %t2613 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2612, ptr %t2613
  br label %reuse.join.2611
reuse.copy.2610:
  %t2614 = call ptr @__alloc(i64 24, i32 2)
  %t2615 = inttoptr i64 114 to ptr
  %t2616 = getelementptr ptr, ptr %t2614, i32 0
  store ptr %t2615, ptr %t2616
  call void @__inc_ref(ptr %t2603)
  %t2617 = getelementptr ptr, ptr %t2614, i32 1
  store ptr %t2603, ptr %t2617
  call void @__inc_ref(ptr %t2605)
  %t2618 = getelementptr ptr, ptr %t2614, i32 2
  store ptr %t2605, ptr %t2618
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2611
reuse.join.2611:
  %t2619 = phi ptr [ %t5, %reuse.in_place.2609 ], [ %t2614, %reuse.copy.2610 ]
  %t2620 = call ptr @__alloc(i64 16, i32 1)
  %t2621 = inttoptr i64 299 to ptr
  %t2622 = getelementptr ptr, ptr %t2620, i32 0
  store ptr %t2621, ptr %t2622
  call void @__inc_ref(ptr %t6)
  %t2623 = getelementptr ptr, ptr %t2620, i32 1
  store ptr %t6, ptr %t2623
  call void @__free_recursive(ptr %t6)
  store ptr %t2619, ptr %t3
  store ptr %t2620, ptr %t4
  br label %tco.loop.0
tco.case.arm.154.2624:
  %t2625 = getelementptr ptr, ptr %t5, i32 1
  %t2626 = load ptr, ptr %t2625
  %t2627 = getelementptr ptr, ptr %t5, i32 2
  %t2628 = load ptr, ptr %t2627
  %t2629 = getelementptr i8, ptr %t5, i64 -8
  %t2630 = load i32, ptr %t2629
  %t2631 = icmp eq i32 %t2630, 1
  br i1 %t2631, label %reuse.in_place.2632, label %reuse.copy.2633
reuse.in_place.2632:
  %t2635 = inttoptr i64 114 to ptr
  %t2636 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2635, ptr %t2636
  br label %reuse.join.2634
reuse.copy.2633:
  %t2637 = call ptr @__alloc(i64 24, i32 2)
  %t2638 = inttoptr i64 114 to ptr
  %t2639 = getelementptr ptr, ptr %t2637, i32 0
  store ptr %t2638, ptr %t2639
  call void @__inc_ref(ptr %t2626)
  %t2640 = getelementptr ptr, ptr %t2637, i32 1
  store ptr %t2626, ptr %t2640
  call void @__inc_ref(ptr %t2628)
  %t2641 = getelementptr ptr, ptr %t2637, i32 2
  store ptr %t2628, ptr %t2641
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2634
reuse.join.2634:
  %t2642 = phi ptr [ %t5, %reuse.in_place.2632 ], [ %t2637, %reuse.copy.2633 ]
  %t2643 = call ptr @__alloc(i64 16, i32 1)
  %t2644 = inttoptr i64 300 to ptr
  %t2645 = getelementptr ptr, ptr %t2643, i32 0
  store ptr %t2644, ptr %t2645
  call void @__inc_ref(ptr %t6)
  %t2646 = getelementptr ptr, ptr %t2643, i32 1
  store ptr %t6, ptr %t2646
  call void @__free_recursive(ptr %t6)
  store ptr %t2642, ptr %t3
  store ptr %t2643, ptr %t4
  br label %tco.loop.0
tco.case.arm.155.2647:
  %t2648 = getelementptr ptr, ptr %t5, i32 1
  %t2649 = load ptr, ptr %t2648
  %t2650 = getelementptr ptr, ptr %t5, i32 2
  %t2651 = load ptr, ptr %t2650
  %t2652 = getelementptr i8, ptr %t5, i64 -8
  %t2653 = load i32, ptr %t2652
  %t2654 = icmp eq i32 %t2653, 1
  br i1 %t2654, label %reuse.in_place.2655, label %reuse.copy.2656
reuse.in_place.2655:
  %t2658 = inttoptr i64 114 to ptr
  %t2659 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2658, ptr %t2659
  br label %reuse.join.2657
reuse.copy.2656:
  %t2660 = call ptr @__alloc(i64 24, i32 2)
  %t2661 = inttoptr i64 114 to ptr
  %t2662 = getelementptr ptr, ptr %t2660, i32 0
  store ptr %t2661, ptr %t2662
  call void @__inc_ref(ptr %t2649)
  %t2663 = getelementptr ptr, ptr %t2660, i32 1
  store ptr %t2649, ptr %t2663
  call void @__inc_ref(ptr %t2651)
  %t2664 = getelementptr ptr, ptr %t2660, i32 2
  store ptr %t2651, ptr %t2664
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2657
reuse.join.2657:
  %t2665 = phi ptr [ %t5, %reuse.in_place.2655 ], [ %t2660, %reuse.copy.2656 ]
  %t2666 = call ptr @__alloc(i64 16, i32 1)
  %t2667 = inttoptr i64 301 to ptr
  %t2668 = getelementptr ptr, ptr %t2666, i32 0
  store ptr %t2667, ptr %t2668
  call void @__inc_ref(ptr %t6)
  %t2669 = getelementptr ptr, ptr %t2666, i32 1
  store ptr %t6, ptr %t2669
  call void @__free_recursive(ptr %t6)
  store ptr %t2665, ptr %t3
  store ptr %t2666, ptr %t4
  br label %tco.loop.0
tco.case.arm.156.2670:
  %t2671 = getelementptr ptr, ptr %t5, i32 1
  %t2672 = load ptr, ptr %t2671
  %t2673 = getelementptr ptr, ptr %t5, i32 2
  %t2674 = load ptr, ptr %t2673
  %t2675 = getelementptr i8, ptr %t5, i64 -8
  %t2676 = load i32, ptr %t2675
  %t2677 = icmp eq i32 %t2676, 1
  br i1 %t2677, label %reuse.in_place.2678, label %reuse.copy.2679
reuse.in_place.2678:
  %t2681 = inttoptr i64 114 to ptr
  %t2682 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2681, ptr %t2682
  br label %reuse.join.2680
reuse.copy.2679:
  %t2683 = call ptr @__alloc(i64 24, i32 2)
  %t2684 = inttoptr i64 114 to ptr
  %t2685 = getelementptr ptr, ptr %t2683, i32 0
  store ptr %t2684, ptr %t2685
  call void @__inc_ref(ptr %t2672)
  %t2686 = getelementptr ptr, ptr %t2683, i32 1
  store ptr %t2672, ptr %t2686
  call void @__inc_ref(ptr %t2674)
  %t2687 = getelementptr ptr, ptr %t2683, i32 2
  store ptr %t2674, ptr %t2687
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2680
reuse.join.2680:
  %t2688 = phi ptr [ %t5, %reuse.in_place.2678 ], [ %t2683, %reuse.copy.2679 ]
  %t2689 = call ptr @__alloc(i64 16, i32 1)
  %t2690 = inttoptr i64 302 to ptr
  %t2691 = getelementptr ptr, ptr %t2689, i32 0
  store ptr %t2690, ptr %t2691
  call void @__inc_ref(ptr %t6)
  %t2692 = getelementptr ptr, ptr %t2689, i32 1
  store ptr %t6, ptr %t2692
  call void @__free_recursive(ptr %t6)
  store ptr %t2688, ptr %t3
  store ptr %t2689, ptr %t4
  br label %tco.loop.0
tco.case.arm.157.2693:
  %t2694 = getelementptr ptr, ptr %t5, i32 1
  %t2695 = load ptr, ptr %t2694
  %t2696 = getelementptr ptr, ptr %t5, i32 2
  %t2697 = load ptr, ptr %t2696
  %t2698 = getelementptr i8, ptr %t5, i64 -8
  %t2699 = load i32, ptr %t2698
  %t2700 = icmp eq i32 %t2699, 1
  br i1 %t2700, label %reuse.in_place.2701, label %reuse.copy.2702
reuse.in_place.2701:
  %t2704 = inttoptr i64 114 to ptr
  %t2705 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2704, ptr %t2705
  br label %reuse.join.2703
reuse.copy.2702:
  %t2706 = call ptr @__alloc(i64 24, i32 2)
  %t2707 = inttoptr i64 114 to ptr
  %t2708 = getelementptr ptr, ptr %t2706, i32 0
  store ptr %t2707, ptr %t2708
  call void @__inc_ref(ptr %t2695)
  %t2709 = getelementptr ptr, ptr %t2706, i32 1
  store ptr %t2695, ptr %t2709
  call void @__inc_ref(ptr %t2697)
  %t2710 = getelementptr ptr, ptr %t2706, i32 2
  store ptr %t2697, ptr %t2710
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2703
reuse.join.2703:
  %t2711 = phi ptr [ %t5, %reuse.in_place.2701 ], [ %t2706, %reuse.copy.2702 ]
  %t2712 = call ptr @__alloc(i64 16, i32 1)
  %t2713 = inttoptr i64 303 to ptr
  %t2714 = getelementptr ptr, ptr %t2712, i32 0
  store ptr %t2713, ptr %t2714
  call void @__inc_ref(ptr %t6)
  %t2715 = getelementptr ptr, ptr %t2712, i32 1
  store ptr %t6, ptr %t2715
  call void @__free_recursive(ptr %t6)
  store ptr %t2711, ptr %t3
  store ptr %t2712, ptr %t4
  br label %tco.loop.0
tco.case.arm.158.2716:
  %t2717 = getelementptr ptr, ptr %t5, i32 1
  %t2718 = load ptr, ptr %t2717
  %t2719 = getelementptr ptr, ptr %t5, i32 2
  %t2720 = load ptr, ptr %t2719
  %t2721 = getelementptr i8, ptr %t5, i64 -8
  %t2722 = load i32, ptr %t2721
  %t2723 = icmp eq i32 %t2722, 1
  br i1 %t2723, label %reuse.in_place.2724, label %reuse.copy.2725
reuse.in_place.2724:
  %t2727 = inttoptr i64 114 to ptr
  %t2728 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2727, ptr %t2728
  br label %reuse.join.2726
reuse.copy.2725:
  %t2729 = call ptr @__alloc(i64 24, i32 2)
  %t2730 = inttoptr i64 114 to ptr
  %t2731 = getelementptr ptr, ptr %t2729, i32 0
  store ptr %t2730, ptr %t2731
  call void @__inc_ref(ptr %t2718)
  %t2732 = getelementptr ptr, ptr %t2729, i32 1
  store ptr %t2718, ptr %t2732
  call void @__inc_ref(ptr %t2720)
  %t2733 = getelementptr ptr, ptr %t2729, i32 2
  store ptr %t2720, ptr %t2733
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2726
reuse.join.2726:
  %t2734 = phi ptr [ %t5, %reuse.in_place.2724 ], [ %t2729, %reuse.copy.2725 ]
  %t2735 = call ptr @__alloc(i64 16, i32 1)
  %t2736 = inttoptr i64 304 to ptr
  %t2737 = getelementptr ptr, ptr %t2735, i32 0
  store ptr %t2736, ptr %t2737
  call void @__inc_ref(ptr %t6)
  %t2738 = getelementptr ptr, ptr %t2735, i32 1
  store ptr %t6, ptr %t2738
  call void @__free_recursive(ptr %t6)
  store ptr %t2734, ptr %t3
  store ptr %t2735, ptr %t4
  br label %tco.loop.0
tco.case.arm.159.2739:
  %t2740 = getelementptr ptr, ptr %t5, i32 1
  %t2741 = load ptr, ptr %t2740
  %t2742 = getelementptr ptr, ptr %t5, i32 2
  %t2743 = load ptr, ptr %t2742
  %t2744 = getelementptr i8, ptr %t5, i64 -8
  %t2745 = load i32, ptr %t2744
  %t2746 = icmp eq i32 %t2745, 1
  br i1 %t2746, label %reuse.in_place.2747, label %reuse.copy.2748
reuse.in_place.2747:
  %t2750 = inttoptr i64 114 to ptr
  %t2751 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2750, ptr %t2751
  br label %reuse.join.2749
reuse.copy.2748:
  %t2752 = call ptr @__alloc(i64 24, i32 2)
  %t2753 = inttoptr i64 114 to ptr
  %t2754 = getelementptr ptr, ptr %t2752, i32 0
  store ptr %t2753, ptr %t2754
  call void @__inc_ref(ptr %t2741)
  %t2755 = getelementptr ptr, ptr %t2752, i32 1
  store ptr %t2741, ptr %t2755
  call void @__inc_ref(ptr %t2743)
  %t2756 = getelementptr ptr, ptr %t2752, i32 2
  store ptr %t2743, ptr %t2756
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2749
reuse.join.2749:
  %t2757 = phi ptr [ %t5, %reuse.in_place.2747 ], [ %t2752, %reuse.copy.2748 ]
  %t2758 = call ptr @__alloc(i64 16, i32 1)
  %t2759 = inttoptr i64 305 to ptr
  %t2760 = getelementptr ptr, ptr %t2758, i32 0
  store ptr %t2759, ptr %t2760
  call void @__inc_ref(ptr %t6)
  %t2761 = getelementptr ptr, ptr %t2758, i32 1
  store ptr %t6, ptr %t2761
  call void @__free_recursive(ptr %t6)
  store ptr %t2757, ptr %t3
  store ptr %t2758, ptr %t4
  br label %tco.loop.0
tco.case.arm.160.2762:
  %t2763 = getelementptr ptr, ptr %t5, i32 1
  %t2764 = load ptr, ptr %t2763
  %t2765 = getelementptr ptr, ptr %t5, i32 2
  %t2766 = load ptr, ptr %t2765
  %t2767 = getelementptr i8, ptr %t5, i64 -8
  %t2768 = load i32, ptr %t2767
  %t2769 = icmp eq i32 %t2768, 1
  br i1 %t2769, label %reuse.in_place.2770, label %reuse.copy.2771
reuse.in_place.2770:
  %t2773 = inttoptr i64 114 to ptr
  %t2774 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2773, ptr %t2774
  br label %reuse.join.2772
reuse.copy.2771:
  %t2775 = call ptr @__alloc(i64 24, i32 2)
  %t2776 = inttoptr i64 114 to ptr
  %t2777 = getelementptr ptr, ptr %t2775, i32 0
  store ptr %t2776, ptr %t2777
  call void @__inc_ref(ptr %t2764)
  %t2778 = getelementptr ptr, ptr %t2775, i32 1
  store ptr %t2764, ptr %t2778
  call void @__inc_ref(ptr %t2766)
  %t2779 = getelementptr ptr, ptr %t2775, i32 2
  store ptr %t2766, ptr %t2779
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2772
reuse.join.2772:
  %t2780 = phi ptr [ %t5, %reuse.in_place.2770 ], [ %t2775, %reuse.copy.2771 ]
  %t2781 = call ptr @__alloc(i64 16, i32 1)
  %t2782 = inttoptr i64 306 to ptr
  %t2783 = getelementptr ptr, ptr %t2781, i32 0
  store ptr %t2782, ptr %t2783
  call void @__inc_ref(ptr %t6)
  %t2784 = getelementptr ptr, ptr %t2781, i32 1
  store ptr %t6, ptr %t2784
  call void @__free_recursive(ptr %t6)
  store ptr %t2780, ptr %t3
  store ptr %t2781, ptr %t4
  br label %tco.loop.0
tco.case.arm.161.2785:
  %t2786 = getelementptr ptr, ptr %t5, i32 1
  %t2787 = load ptr, ptr %t2786
  %t2788 = getelementptr ptr, ptr %t5, i32 2
  %t2789 = load ptr, ptr %t2788
  %t2790 = getelementptr i8, ptr %t5, i64 -8
  %t2791 = load i32, ptr %t2790
  %t2792 = icmp eq i32 %t2791, 1
  br i1 %t2792, label %reuse.in_place.2793, label %reuse.copy.2794
reuse.in_place.2793:
  %t2796 = inttoptr i64 114 to ptr
  %t2797 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2796, ptr %t2797
  br label %reuse.join.2795
reuse.copy.2794:
  %t2798 = call ptr @__alloc(i64 24, i32 2)
  %t2799 = inttoptr i64 114 to ptr
  %t2800 = getelementptr ptr, ptr %t2798, i32 0
  store ptr %t2799, ptr %t2800
  call void @__inc_ref(ptr %t2787)
  %t2801 = getelementptr ptr, ptr %t2798, i32 1
  store ptr %t2787, ptr %t2801
  call void @__inc_ref(ptr %t2789)
  %t2802 = getelementptr ptr, ptr %t2798, i32 2
  store ptr %t2789, ptr %t2802
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2795
reuse.join.2795:
  %t2803 = phi ptr [ %t5, %reuse.in_place.2793 ], [ %t2798, %reuse.copy.2794 ]
  %t2804 = call ptr @__alloc(i64 16, i32 1)
  %t2805 = inttoptr i64 307 to ptr
  %t2806 = getelementptr ptr, ptr %t2804, i32 0
  store ptr %t2805, ptr %t2806
  call void @__inc_ref(ptr %t6)
  %t2807 = getelementptr ptr, ptr %t2804, i32 1
  store ptr %t6, ptr %t2807
  call void @__free_recursive(ptr %t6)
  store ptr %t2803, ptr %t3
  store ptr %t2804, ptr %t4
  br label %tco.loop.0
tco.case.arm.162.2808:
  %t2809 = getelementptr ptr, ptr %t5, i32 1
  %t2810 = load ptr, ptr %t2809
  call void @__inc_ref(ptr %t2810)
  %t2811 = getelementptr ptr, ptr %t5, i32 2
  %t2812 = load ptr, ptr %t2811
  call void @__inc_ref(ptr %t2812)
  %t2813 = getelementptr ptr, ptr %t5, i32 3
  %t2814 = load ptr, ptr %t2813
  call void @__inc_ref(ptr %t2814)
  %t2815 = call ptr @__alloc(i64 24, i32 2)
  %t2816 = inttoptr i64 114 to ptr
  %t2817 = getelementptr ptr, ptr %t2815, i32 0
  store ptr %t2816, ptr %t2817
  call void @__inc_ref(ptr %t2810)
  %t2818 = getelementptr ptr, ptr %t2815, i32 1
  store ptr %t2810, ptr %t2818
  call void @__inc_ref(ptr %t2812)
  %t2819 = getelementptr ptr, ptr %t2815, i32 2
  store ptr %t2812, ptr %t2819
  %t2820 = call ptr @__alloc(i64 24, i32 2)
  %t2821 = inttoptr i64 308 to ptr
  %t2822 = getelementptr ptr, ptr %t2820, i32 0
  store ptr %t2821, ptr %t2822
  call void @__inc_ref(ptr %t6)
  %t2823 = getelementptr ptr, ptr %t2820, i32 1
  store ptr %t6, ptr %t2823
  call void @__inc_ref(ptr %t2814)
  %t2824 = getelementptr ptr, ptr %t2820, i32 2
  store ptr %t2814, ptr %t2824
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t2814)
  call void @__free_recursive(ptr %t2812)
  call void @__free_recursive(ptr %t2810)
  store ptr %t2815, ptr %t3
  store ptr %t2820, ptr %t4
  br label %tco.loop.0
tco.case.arm.163.2825:
  %t2826 = getelementptr ptr, ptr %t5, i32 1
  %t2827 = load ptr, ptr %t2826
  %t2828 = getelementptr ptr, ptr %t5, i32 2
  %t2829 = load ptr, ptr %t2828
  %t2830 = getelementptr i8, ptr %t5, i64 -8
  %t2831 = load i32, ptr %t2830
  %t2832 = icmp eq i32 %t2831, 1
  br i1 %t2832, label %reuse.in_place.2833, label %reuse.copy.2834
reuse.in_place.2833:
  %t2836 = inttoptr i64 114 to ptr
  %t2837 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2836, ptr %t2837
  br label %reuse.join.2835
reuse.copy.2834:
  %t2838 = call ptr @__alloc(i64 24, i32 2)
  %t2839 = inttoptr i64 114 to ptr
  %t2840 = getelementptr ptr, ptr %t2838, i32 0
  store ptr %t2839, ptr %t2840
  call void @__inc_ref(ptr %t2827)
  %t2841 = getelementptr ptr, ptr %t2838, i32 1
  store ptr %t2827, ptr %t2841
  call void @__inc_ref(ptr %t2829)
  %t2842 = getelementptr ptr, ptr %t2838, i32 2
  store ptr %t2829, ptr %t2842
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2835
reuse.join.2835:
  %t2843 = phi ptr [ %t5, %reuse.in_place.2833 ], [ %t2838, %reuse.copy.2834 ]
  %t2844 = call ptr @__alloc(i64 16, i32 1)
  %t2845 = inttoptr i64 309 to ptr
  %t2846 = getelementptr ptr, ptr %t2844, i32 0
  store ptr %t2845, ptr %t2846
  call void @__inc_ref(ptr %t6)
  %t2847 = getelementptr ptr, ptr %t2844, i32 1
  store ptr %t6, ptr %t2847
  call void @__free_recursive(ptr %t6)
  store ptr %t2843, ptr %t3
  store ptr %t2844, ptr %t4
  br label %tco.loop.0
tco.case.arm.164.2848:
  %t2849 = getelementptr ptr, ptr %t5, i32 1
  %t2850 = load ptr, ptr %t2849
  %t2851 = getelementptr ptr, ptr %t5, i32 2
  %t2852 = load ptr, ptr %t2851
  %t2853 = getelementptr i8, ptr %t5, i64 -8
  %t2854 = load i32, ptr %t2853
  %t2855 = icmp eq i32 %t2854, 1
  br i1 %t2855, label %reuse.in_place.2856, label %reuse.copy.2857
reuse.in_place.2856:
  %t2859 = inttoptr i64 114 to ptr
  %t2860 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2859, ptr %t2860
  br label %reuse.join.2858
reuse.copy.2857:
  %t2861 = call ptr @__alloc(i64 24, i32 2)
  %t2862 = inttoptr i64 114 to ptr
  %t2863 = getelementptr ptr, ptr %t2861, i32 0
  store ptr %t2862, ptr %t2863
  call void @__inc_ref(ptr %t2850)
  %t2864 = getelementptr ptr, ptr %t2861, i32 1
  store ptr %t2850, ptr %t2864
  call void @__inc_ref(ptr %t2852)
  %t2865 = getelementptr ptr, ptr %t2861, i32 2
  store ptr %t2852, ptr %t2865
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2858
reuse.join.2858:
  %t2866 = phi ptr [ %t5, %reuse.in_place.2856 ], [ %t2861, %reuse.copy.2857 ]
  %t2867 = call ptr @__alloc(i64 16, i32 1)
  %t2868 = inttoptr i64 310 to ptr
  %t2869 = getelementptr ptr, ptr %t2867, i32 0
  store ptr %t2868, ptr %t2869
  call void @__inc_ref(ptr %t6)
  %t2870 = getelementptr ptr, ptr %t2867, i32 1
  store ptr %t6, ptr %t2870
  call void @__free_recursive(ptr %t6)
  store ptr %t2866, ptr %t3
  store ptr %t2867, ptr %t4
  br label %tco.loop.0
tco.case.arm.165.2871:
  %t2872 = getelementptr ptr, ptr %t5, i32 1
  %t2873 = load ptr, ptr %t2872
  %t2874 = getelementptr ptr, ptr %t5, i32 2
  %t2875 = load ptr, ptr %t2874
  %t2876 = getelementptr i8, ptr %t5, i64 -8
  %t2877 = load i32, ptr %t2876
  %t2878 = icmp eq i32 %t2877, 1
  br i1 %t2878, label %reuse.in_place.2879, label %reuse.copy.2880
reuse.in_place.2879:
  %t2882 = inttoptr i64 114 to ptr
  %t2883 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2882, ptr %t2883
  br label %reuse.join.2881
reuse.copy.2880:
  %t2884 = call ptr @__alloc(i64 24, i32 2)
  %t2885 = inttoptr i64 114 to ptr
  %t2886 = getelementptr ptr, ptr %t2884, i32 0
  store ptr %t2885, ptr %t2886
  call void @__inc_ref(ptr %t2873)
  %t2887 = getelementptr ptr, ptr %t2884, i32 1
  store ptr %t2873, ptr %t2887
  call void @__inc_ref(ptr %t2875)
  %t2888 = getelementptr ptr, ptr %t2884, i32 2
  store ptr %t2875, ptr %t2888
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2881
reuse.join.2881:
  %t2889 = phi ptr [ %t5, %reuse.in_place.2879 ], [ %t2884, %reuse.copy.2880 ]
  %t2890 = call ptr @__alloc(i64 16, i32 1)
  %t2891 = inttoptr i64 311 to ptr
  %t2892 = getelementptr ptr, ptr %t2890, i32 0
  store ptr %t2891, ptr %t2892
  call void @__inc_ref(ptr %t6)
  %t2893 = getelementptr ptr, ptr %t2890, i32 1
  store ptr %t6, ptr %t2893
  call void @__free_recursive(ptr %t6)
  store ptr %t2889, ptr %t3
  store ptr %t2890, ptr %t4
  br label %tco.loop.0
tco.case.arm.166.2894:
  %t2895 = getelementptr ptr, ptr %t5, i32 1
  %t2896 = load ptr, ptr %t2895
  %t2897 = getelementptr ptr, ptr %t5, i32 2
  %t2898 = load ptr, ptr %t2897
  %t2899 = getelementptr i8, ptr %t5, i64 -8
  %t2900 = load i32, ptr %t2899
  %t2901 = icmp eq i32 %t2900, 1
  br i1 %t2901, label %reuse.in_place.2902, label %reuse.copy.2903
reuse.in_place.2902:
  %t2905 = inttoptr i64 114 to ptr
  %t2906 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2905, ptr %t2906
  br label %reuse.join.2904
reuse.copy.2903:
  %t2907 = call ptr @__alloc(i64 24, i32 2)
  %t2908 = inttoptr i64 114 to ptr
  %t2909 = getelementptr ptr, ptr %t2907, i32 0
  store ptr %t2908, ptr %t2909
  call void @__inc_ref(ptr %t2896)
  %t2910 = getelementptr ptr, ptr %t2907, i32 1
  store ptr %t2896, ptr %t2910
  call void @__inc_ref(ptr %t2898)
  %t2911 = getelementptr ptr, ptr %t2907, i32 2
  store ptr %t2898, ptr %t2911
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2904
reuse.join.2904:
  %t2912 = phi ptr [ %t5, %reuse.in_place.2902 ], [ %t2907, %reuse.copy.2903 ]
  %t2913 = call ptr @__alloc(i64 16, i32 1)
  %t2914 = inttoptr i64 312 to ptr
  %t2915 = getelementptr ptr, ptr %t2913, i32 0
  store ptr %t2914, ptr %t2915
  call void @__inc_ref(ptr %t6)
  %t2916 = getelementptr ptr, ptr %t2913, i32 1
  store ptr %t6, ptr %t2916
  call void @__free_recursive(ptr %t6)
  store ptr %t2912, ptr %t3
  store ptr %t2913, ptr %t4
  br label %tco.loop.0
tco.case.arm.167.2917:
  %t2918 = getelementptr ptr, ptr %t5, i32 1
  %t2919 = load ptr, ptr %t2918
  %t2920 = getelementptr ptr, ptr %t5, i32 2
  %t2921 = load ptr, ptr %t2920
  %t2922 = getelementptr i8, ptr %t5, i64 -8
  %t2923 = load i32, ptr %t2922
  %t2924 = icmp eq i32 %t2923, 1
  br i1 %t2924, label %reuse.in_place.2925, label %reuse.copy.2926
reuse.in_place.2925:
  %t2928 = inttoptr i64 114 to ptr
  %t2929 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2928, ptr %t2929
  br label %reuse.join.2927
reuse.copy.2926:
  %t2930 = call ptr @__alloc(i64 24, i32 2)
  %t2931 = inttoptr i64 114 to ptr
  %t2932 = getelementptr ptr, ptr %t2930, i32 0
  store ptr %t2931, ptr %t2932
  call void @__inc_ref(ptr %t2919)
  %t2933 = getelementptr ptr, ptr %t2930, i32 1
  store ptr %t2919, ptr %t2933
  call void @__inc_ref(ptr %t2921)
  %t2934 = getelementptr ptr, ptr %t2930, i32 2
  store ptr %t2921, ptr %t2934
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2927
reuse.join.2927:
  %t2935 = phi ptr [ %t5, %reuse.in_place.2925 ], [ %t2930, %reuse.copy.2926 ]
  %t2936 = call ptr @__alloc(i64 16, i32 1)
  %t2937 = inttoptr i64 313 to ptr
  %t2938 = getelementptr ptr, ptr %t2936, i32 0
  store ptr %t2937, ptr %t2938
  call void @__inc_ref(ptr %t6)
  %t2939 = getelementptr ptr, ptr %t2936, i32 1
  store ptr %t6, ptr %t2939
  call void @__free_recursive(ptr %t6)
  store ptr %t2935, ptr %t3
  store ptr %t2936, ptr %t4
  br label %tco.loop.0
tco.case.arm.168.2940:
  %t2941 = getelementptr ptr, ptr %t5, i32 1
  %t2942 = load ptr, ptr %t2941
  %t2943 = getelementptr ptr, ptr %t5, i32 2
  %t2944 = load ptr, ptr %t2943
  %t2945 = getelementptr i8, ptr %t5, i64 -8
  %t2946 = load i32, ptr %t2945
  %t2947 = icmp eq i32 %t2946, 1
  br i1 %t2947, label %reuse.in_place.2948, label %reuse.copy.2949
reuse.in_place.2948:
  %t2951 = inttoptr i64 114 to ptr
  %t2952 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2951, ptr %t2952
  br label %reuse.join.2950
reuse.copy.2949:
  %t2953 = call ptr @__alloc(i64 24, i32 2)
  %t2954 = inttoptr i64 114 to ptr
  %t2955 = getelementptr ptr, ptr %t2953, i32 0
  store ptr %t2954, ptr %t2955
  call void @__inc_ref(ptr %t2942)
  %t2956 = getelementptr ptr, ptr %t2953, i32 1
  store ptr %t2942, ptr %t2956
  call void @__inc_ref(ptr %t2944)
  %t2957 = getelementptr ptr, ptr %t2953, i32 2
  store ptr %t2944, ptr %t2957
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2950
reuse.join.2950:
  %t2958 = phi ptr [ %t5, %reuse.in_place.2948 ], [ %t2953, %reuse.copy.2949 ]
  %t2959 = call ptr @__alloc(i64 16, i32 1)
  %t2960 = inttoptr i64 314 to ptr
  %t2961 = getelementptr ptr, ptr %t2959, i32 0
  store ptr %t2960, ptr %t2961
  call void @__inc_ref(ptr %t6)
  %t2962 = getelementptr ptr, ptr %t2959, i32 1
  store ptr %t6, ptr %t2962
  call void @__free_recursive(ptr %t6)
  store ptr %t2958, ptr %t3
  store ptr %t2959, ptr %t4
  br label %tco.loop.0
tco.case.arm.169.2963:
  %t2964 = getelementptr ptr, ptr %t5, i32 1
  %t2965 = load ptr, ptr %t2964
  %t2966 = getelementptr ptr, ptr %t5, i32 2
  %t2967 = load ptr, ptr %t2966
  %t2968 = getelementptr i8, ptr %t5, i64 -8
  %t2969 = load i32, ptr %t2968
  %t2970 = icmp eq i32 %t2969, 1
  br i1 %t2970, label %reuse.in_place.2971, label %reuse.copy.2972
reuse.in_place.2971:
  %t2974 = inttoptr i64 114 to ptr
  %t2975 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2974, ptr %t2975
  br label %reuse.join.2973
reuse.copy.2972:
  %t2976 = call ptr @__alloc(i64 24, i32 2)
  %t2977 = inttoptr i64 114 to ptr
  %t2978 = getelementptr ptr, ptr %t2976, i32 0
  store ptr %t2977, ptr %t2978
  call void @__inc_ref(ptr %t2965)
  %t2979 = getelementptr ptr, ptr %t2976, i32 1
  store ptr %t2965, ptr %t2979
  call void @__inc_ref(ptr %t2967)
  %t2980 = getelementptr ptr, ptr %t2976, i32 2
  store ptr %t2967, ptr %t2980
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2973
reuse.join.2973:
  %t2981 = phi ptr [ %t5, %reuse.in_place.2971 ], [ %t2976, %reuse.copy.2972 ]
  %t2982 = call ptr @__alloc(i64 16, i32 1)
  %t2983 = inttoptr i64 315 to ptr
  %t2984 = getelementptr ptr, ptr %t2982, i32 0
  store ptr %t2983, ptr %t2984
  call void @__inc_ref(ptr %t6)
  %t2985 = getelementptr ptr, ptr %t2982, i32 1
  store ptr %t6, ptr %t2985
  call void @__free_recursive(ptr %t6)
  store ptr %t2981, ptr %t3
  store ptr %t2982, ptr %t4
  br label %tco.loop.0
tco.case.arm.170.2986:
  %t2987 = getelementptr ptr, ptr %t5, i32 1
  %t2988 = load ptr, ptr %t2987
  %t2989 = getelementptr ptr, ptr %t5, i32 2
  %t2990 = load ptr, ptr %t2989
  %t2991 = getelementptr i8, ptr %t5, i64 -8
  %t2992 = load i32, ptr %t2991
  %t2993 = icmp eq i32 %t2992, 1
  br i1 %t2993, label %reuse.in_place.2994, label %reuse.copy.2995
reuse.in_place.2994:
  %t2997 = inttoptr i64 114 to ptr
  %t2998 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2997, ptr %t2998
  br label %reuse.join.2996
reuse.copy.2995:
  %t2999 = call ptr @__alloc(i64 24, i32 2)
  %t3000 = inttoptr i64 114 to ptr
  %t3001 = getelementptr ptr, ptr %t2999, i32 0
  store ptr %t3000, ptr %t3001
  call void @__inc_ref(ptr %t2988)
  %t3002 = getelementptr ptr, ptr %t2999, i32 1
  store ptr %t2988, ptr %t3002
  call void @__inc_ref(ptr %t2990)
  %t3003 = getelementptr ptr, ptr %t2999, i32 2
  store ptr %t2990, ptr %t3003
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2996
reuse.join.2996:
  %t3004 = phi ptr [ %t5, %reuse.in_place.2994 ], [ %t2999, %reuse.copy.2995 ]
  %t3005 = call ptr @__alloc(i64 16, i32 1)
  %t3006 = inttoptr i64 316 to ptr
  %t3007 = getelementptr ptr, ptr %t3005, i32 0
  store ptr %t3006, ptr %t3007
  call void @__inc_ref(ptr %t6)
  %t3008 = getelementptr ptr, ptr %t3005, i32 1
  store ptr %t6, ptr %t3008
  call void @__free_recursive(ptr %t6)
  store ptr %t3004, ptr %t3
  store ptr %t3005, ptr %t4
  br label %tco.loop.0
tco.case.arm.171.3009:
  %t3010 = getelementptr ptr, ptr %t5, i32 1
  %t3011 = load ptr, ptr %t3010
  %t3012 = getelementptr ptr, ptr %t5, i32 2
  %t3013 = load ptr, ptr %t3012
  %t3014 = getelementptr i8, ptr %t5, i64 -8
  %t3015 = load i32, ptr %t3014
  %t3016 = icmp eq i32 %t3015, 1
  br i1 %t3016, label %reuse.in_place.3017, label %reuse.copy.3018
reuse.in_place.3017:
  %t3020 = inttoptr i64 114 to ptr
  %t3021 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3020, ptr %t3021
  br label %reuse.join.3019
reuse.copy.3018:
  %t3022 = call ptr @__alloc(i64 24, i32 2)
  %t3023 = inttoptr i64 114 to ptr
  %t3024 = getelementptr ptr, ptr %t3022, i32 0
  store ptr %t3023, ptr %t3024
  call void @__inc_ref(ptr %t3011)
  %t3025 = getelementptr ptr, ptr %t3022, i32 1
  store ptr %t3011, ptr %t3025
  call void @__inc_ref(ptr %t3013)
  %t3026 = getelementptr ptr, ptr %t3022, i32 2
  store ptr %t3013, ptr %t3026
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3019
reuse.join.3019:
  %t3027 = phi ptr [ %t5, %reuse.in_place.3017 ], [ %t3022, %reuse.copy.3018 ]
  %t3028 = call ptr @__alloc(i64 16, i32 1)
  %t3029 = inttoptr i64 317 to ptr
  %t3030 = getelementptr ptr, ptr %t3028, i32 0
  store ptr %t3029, ptr %t3030
  call void @__inc_ref(ptr %t6)
  %t3031 = getelementptr ptr, ptr %t3028, i32 1
  store ptr %t6, ptr %t3031
  call void @__free_recursive(ptr %t6)
  store ptr %t3027, ptr %t3
  store ptr %t3028, ptr %t4
  br label %tco.loop.0
tco.case.arm.172.3032:
  %t3033 = getelementptr ptr, ptr %t5, i32 1
  %t3034 = load ptr, ptr %t3033
  %t3035 = getelementptr ptr, ptr %t5, i32 2
  %t3036 = load ptr, ptr %t3035
  %t3037 = getelementptr i8, ptr %t5, i64 -8
  %t3038 = load i32, ptr %t3037
  %t3039 = icmp eq i32 %t3038, 1
  br i1 %t3039, label %reuse.in_place.3040, label %reuse.copy.3041
reuse.in_place.3040:
  %t3043 = inttoptr i64 114 to ptr
  %t3044 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3043, ptr %t3044
  br label %reuse.join.3042
reuse.copy.3041:
  %t3045 = call ptr @__alloc(i64 24, i32 2)
  %t3046 = inttoptr i64 114 to ptr
  %t3047 = getelementptr ptr, ptr %t3045, i32 0
  store ptr %t3046, ptr %t3047
  call void @__inc_ref(ptr %t3034)
  %t3048 = getelementptr ptr, ptr %t3045, i32 1
  store ptr %t3034, ptr %t3048
  call void @__inc_ref(ptr %t3036)
  %t3049 = getelementptr ptr, ptr %t3045, i32 2
  store ptr %t3036, ptr %t3049
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3042
reuse.join.3042:
  %t3050 = phi ptr [ %t5, %reuse.in_place.3040 ], [ %t3045, %reuse.copy.3041 ]
  %t3051 = call ptr @__alloc(i64 16, i32 1)
  %t3052 = inttoptr i64 318 to ptr
  %t3053 = getelementptr ptr, ptr %t3051, i32 0
  store ptr %t3052, ptr %t3053
  call void @__inc_ref(ptr %t6)
  %t3054 = getelementptr ptr, ptr %t3051, i32 1
  store ptr %t6, ptr %t3054
  call void @__free_recursive(ptr %t6)
  store ptr %t3050, ptr %t3
  store ptr %t3051, ptr %t4
  br label %tco.loop.0
tco.case.arm.173.3055:
  %t3056 = getelementptr ptr, ptr %t5, i32 1
  %t3057 = load ptr, ptr %t3056
  %t3058 = getelementptr ptr, ptr %t5, i32 2
  %t3059 = load ptr, ptr %t3058
  %t3060 = getelementptr i8, ptr %t5, i64 -8
  %t3061 = load i32, ptr %t3060
  %t3062 = icmp eq i32 %t3061, 1
  br i1 %t3062, label %reuse.in_place.3063, label %reuse.copy.3064
reuse.in_place.3063:
  %t3066 = inttoptr i64 114 to ptr
  %t3067 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3066, ptr %t3067
  br label %reuse.join.3065
reuse.copy.3064:
  %t3068 = call ptr @__alloc(i64 24, i32 2)
  %t3069 = inttoptr i64 114 to ptr
  %t3070 = getelementptr ptr, ptr %t3068, i32 0
  store ptr %t3069, ptr %t3070
  call void @__inc_ref(ptr %t3057)
  %t3071 = getelementptr ptr, ptr %t3068, i32 1
  store ptr %t3057, ptr %t3071
  call void @__inc_ref(ptr %t3059)
  %t3072 = getelementptr ptr, ptr %t3068, i32 2
  store ptr %t3059, ptr %t3072
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3065
reuse.join.3065:
  %t3073 = phi ptr [ %t5, %reuse.in_place.3063 ], [ %t3068, %reuse.copy.3064 ]
  %t3074 = call ptr @__alloc(i64 16, i32 1)
  %t3075 = inttoptr i64 319 to ptr
  %t3076 = getelementptr ptr, ptr %t3074, i32 0
  store ptr %t3075, ptr %t3076
  call void @__inc_ref(ptr %t6)
  %t3077 = getelementptr ptr, ptr %t3074, i32 1
  store ptr %t6, ptr %t3077
  call void @__free_recursive(ptr %t6)
  store ptr %t3073, ptr %t3
  store ptr %t3074, ptr %t4
  br label %tco.loop.0
tco.case.arm.174.3078:
  %t3079 = getelementptr ptr, ptr %t5, i32 1
  %t3080 = load ptr, ptr %t3079
  %t3081 = getelementptr ptr, ptr %t5, i32 2
  %t3082 = load ptr, ptr %t3081
  %t3083 = getelementptr i8, ptr %t5, i64 -8
  %t3084 = load i32, ptr %t3083
  %t3085 = icmp eq i32 %t3084, 1
  br i1 %t3085, label %reuse.in_place.3086, label %reuse.copy.3087
reuse.in_place.3086:
  %t3089 = inttoptr i64 114 to ptr
  %t3090 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3089, ptr %t3090
  br label %reuse.join.3088
reuse.copy.3087:
  %t3091 = call ptr @__alloc(i64 24, i32 2)
  %t3092 = inttoptr i64 114 to ptr
  %t3093 = getelementptr ptr, ptr %t3091, i32 0
  store ptr %t3092, ptr %t3093
  call void @__inc_ref(ptr %t3080)
  %t3094 = getelementptr ptr, ptr %t3091, i32 1
  store ptr %t3080, ptr %t3094
  call void @__inc_ref(ptr %t3082)
  %t3095 = getelementptr ptr, ptr %t3091, i32 2
  store ptr %t3082, ptr %t3095
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3088
reuse.join.3088:
  %t3096 = phi ptr [ %t5, %reuse.in_place.3086 ], [ %t3091, %reuse.copy.3087 ]
  %t3097 = call ptr @__alloc(i64 16, i32 1)
  %t3098 = inttoptr i64 320 to ptr
  %t3099 = getelementptr ptr, ptr %t3097, i32 0
  store ptr %t3098, ptr %t3099
  call void @__inc_ref(ptr %t6)
  %t3100 = getelementptr ptr, ptr %t3097, i32 1
  store ptr %t6, ptr %t3100
  call void @__free_recursive(ptr %t6)
  store ptr %t3096, ptr %t3
  store ptr %t3097, ptr %t4
  br label %tco.loop.0
tco.case.arm.175.3101:
  %t3102 = getelementptr ptr, ptr %t5, i32 1
  %t3103 = load ptr, ptr %t3102
  call void @__inc_ref(ptr %t3103)
  %t3104 = getelementptr ptr, ptr %t5, i32 2
  %t3105 = load ptr, ptr %t3104
  call void @__inc_ref(ptr %t3105)
  %t3106 = getelementptr ptr, ptr %t5, i32 3
  %t3107 = load ptr, ptr %t3106
  call void @__inc_ref(ptr %t3107)
  %t3108 = call ptr @__alloc(i64 24, i32 2)
  %t3109 = inttoptr i64 114 to ptr
  %t3110 = getelementptr ptr, ptr %t3108, i32 0
  store ptr %t3109, ptr %t3110
  call void @__inc_ref(ptr %t3103)
  %t3111 = getelementptr ptr, ptr %t3108, i32 1
  store ptr %t3103, ptr %t3111
  call void @__inc_ref(ptr %t3105)
  %t3112 = getelementptr ptr, ptr %t3108, i32 2
  store ptr %t3105, ptr %t3112
  %t3113 = call ptr @__alloc(i64 24, i32 2)
  %t3114 = inttoptr i64 321 to ptr
  %t3115 = getelementptr ptr, ptr %t3113, i32 0
  store ptr %t3114, ptr %t3115
  call void @__inc_ref(ptr %t6)
  %t3116 = getelementptr ptr, ptr %t3113, i32 1
  store ptr %t6, ptr %t3116
  call void @__inc_ref(ptr %t3107)
  %t3117 = getelementptr ptr, ptr %t3113, i32 2
  store ptr %t3107, ptr %t3117
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t3107)
  call void @__free_recursive(ptr %t3105)
  call void @__free_recursive(ptr %t3103)
  store ptr %t3108, ptr %t3
  store ptr %t3113, ptr %t4
  br label %tco.loop.0
tco.case.arm.176.3118:
  %t3119 = getelementptr ptr, ptr %t5, i32 1
  %t3120 = load ptr, ptr %t3119
  %t3121 = getelementptr ptr, ptr %t5, i32 2
  %t3122 = load ptr, ptr %t3121
  %t3123 = getelementptr i8, ptr %t5, i64 -8
  %t3124 = load i32, ptr %t3123
  %t3125 = icmp eq i32 %t3124, 1
  br i1 %t3125, label %reuse.in_place.3126, label %reuse.copy.3127
reuse.in_place.3126:
  %t3129 = inttoptr i64 114 to ptr
  %t3130 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3129, ptr %t3130
  br label %reuse.join.3128
reuse.copy.3127:
  %t3131 = call ptr @__alloc(i64 24, i32 2)
  %t3132 = inttoptr i64 114 to ptr
  %t3133 = getelementptr ptr, ptr %t3131, i32 0
  store ptr %t3132, ptr %t3133
  call void @__inc_ref(ptr %t3120)
  %t3134 = getelementptr ptr, ptr %t3131, i32 1
  store ptr %t3120, ptr %t3134
  call void @__inc_ref(ptr %t3122)
  %t3135 = getelementptr ptr, ptr %t3131, i32 2
  store ptr %t3122, ptr %t3135
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3128
reuse.join.3128:
  %t3136 = phi ptr [ %t5, %reuse.in_place.3126 ], [ %t3131, %reuse.copy.3127 ]
  %t3137 = call ptr @__alloc(i64 16, i32 1)
  %t3138 = inttoptr i64 322 to ptr
  %t3139 = getelementptr ptr, ptr %t3137, i32 0
  store ptr %t3138, ptr %t3139
  call void @__inc_ref(ptr %t6)
  %t3140 = getelementptr ptr, ptr %t3137, i32 1
  store ptr %t6, ptr %t3140
  call void @__free_recursive(ptr %t6)
  store ptr %t3136, ptr %t3
  store ptr %t3137, ptr %t4
  br label %tco.loop.0
tco.case.arm.177.3141:
  %t3142 = getelementptr ptr, ptr %t5, i32 1
  %t3143 = load ptr, ptr %t3142
  %t3144 = getelementptr ptr, ptr %t5, i32 2
  %t3145 = load ptr, ptr %t3144
  %t3146 = getelementptr i8, ptr %t5, i64 -8
  %t3147 = load i32, ptr %t3146
  %t3148 = icmp eq i32 %t3147, 1
  br i1 %t3148, label %reuse.in_place.3149, label %reuse.copy.3150
reuse.in_place.3149:
  %t3152 = inttoptr i64 114 to ptr
  %t3153 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3152, ptr %t3153
  br label %reuse.join.3151
reuse.copy.3150:
  %t3154 = call ptr @__alloc(i64 24, i32 2)
  %t3155 = inttoptr i64 114 to ptr
  %t3156 = getelementptr ptr, ptr %t3154, i32 0
  store ptr %t3155, ptr %t3156
  call void @__inc_ref(ptr %t3143)
  %t3157 = getelementptr ptr, ptr %t3154, i32 1
  store ptr %t3143, ptr %t3157
  call void @__inc_ref(ptr %t3145)
  %t3158 = getelementptr ptr, ptr %t3154, i32 2
  store ptr %t3145, ptr %t3158
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3151
reuse.join.3151:
  %t3159 = phi ptr [ %t5, %reuse.in_place.3149 ], [ %t3154, %reuse.copy.3150 ]
  %t3160 = call ptr @__alloc(i64 16, i32 1)
  %t3161 = inttoptr i64 323 to ptr
  %t3162 = getelementptr ptr, ptr %t3160, i32 0
  store ptr %t3161, ptr %t3162
  call void @__inc_ref(ptr %t6)
  %t3163 = getelementptr ptr, ptr %t3160, i32 1
  store ptr %t6, ptr %t3163
  call void @__free_recursive(ptr %t6)
  store ptr %t3159, ptr %t3
  store ptr %t3160, ptr %t4
  br label %tco.loop.0
tco.case.arm.178.3164:
  %t3165 = getelementptr ptr, ptr %t5, i32 1
  %t3166 = load ptr, ptr %t3165
  %t3167 = getelementptr ptr, ptr %t5, i32 2
  %t3168 = load ptr, ptr %t3167
  %t3169 = getelementptr i8, ptr %t5, i64 -8
  %t3170 = load i32, ptr %t3169
  %t3171 = icmp eq i32 %t3170, 1
  br i1 %t3171, label %reuse.in_place.3172, label %reuse.copy.3173
reuse.in_place.3172:
  %t3175 = inttoptr i64 114 to ptr
  %t3176 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3175, ptr %t3176
  br label %reuse.join.3174
reuse.copy.3173:
  %t3177 = call ptr @__alloc(i64 24, i32 2)
  %t3178 = inttoptr i64 114 to ptr
  %t3179 = getelementptr ptr, ptr %t3177, i32 0
  store ptr %t3178, ptr %t3179
  call void @__inc_ref(ptr %t3166)
  %t3180 = getelementptr ptr, ptr %t3177, i32 1
  store ptr %t3166, ptr %t3180
  call void @__inc_ref(ptr %t3168)
  %t3181 = getelementptr ptr, ptr %t3177, i32 2
  store ptr %t3168, ptr %t3181
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3174
reuse.join.3174:
  %t3182 = phi ptr [ %t5, %reuse.in_place.3172 ], [ %t3177, %reuse.copy.3173 ]
  %t3183 = call ptr @__alloc(i64 16, i32 1)
  %t3184 = inttoptr i64 324 to ptr
  %t3185 = getelementptr ptr, ptr %t3183, i32 0
  store ptr %t3184, ptr %t3185
  call void @__inc_ref(ptr %t6)
  %t3186 = getelementptr ptr, ptr %t3183, i32 1
  store ptr %t6, ptr %t3186
  call void @__free_recursive(ptr %t6)
  store ptr %t3182, ptr %t3
  store ptr %t3183, ptr %t4
  br label %tco.loop.0
tco.case.arm.179.3187:
  %t3188 = getelementptr ptr, ptr %t5, i32 1
  %t3189 = load ptr, ptr %t3188
  %t3190 = getelementptr ptr, ptr %t5, i32 2
  %t3191 = load ptr, ptr %t3190
  %t3192 = getelementptr i8, ptr %t5, i64 -8
  %t3193 = load i32, ptr %t3192
  %t3194 = icmp eq i32 %t3193, 1
  br i1 %t3194, label %reuse.in_place.3195, label %reuse.copy.3196
reuse.in_place.3195:
  %t3198 = inttoptr i64 114 to ptr
  %t3199 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3198, ptr %t3199
  br label %reuse.join.3197
reuse.copy.3196:
  %t3200 = call ptr @__alloc(i64 24, i32 2)
  %t3201 = inttoptr i64 114 to ptr
  %t3202 = getelementptr ptr, ptr %t3200, i32 0
  store ptr %t3201, ptr %t3202
  call void @__inc_ref(ptr %t3189)
  %t3203 = getelementptr ptr, ptr %t3200, i32 1
  store ptr %t3189, ptr %t3203
  call void @__inc_ref(ptr %t3191)
  %t3204 = getelementptr ptr, ptr %t3200, i32 2
  store ptr %t3191, ptr %t3204
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3197
reuse.join.3197:
  %t3205 = phi ptr [ %t5, %reuse.in_place.3195 ], [ %t3200, %reuse.copy.3196 ]
  %t3206 = call ptr @__alloc(i64 16, i32 1)
  %t3207 = inttoptr i64 325 to ptr
  %t3208 = getelementptr ptr, ptr %t3206, i32 0
  store ptr %t3207, ptr %t3208
  call void @__inc_ref(ptr %t6)
  %t3209 = getelementptr ptr, ptr %t3206, i32 1
  store ptr %t6, ptr %t3209
  call void @__free_recursive(ptr %t6)
  store ptr %t3205, ptr %t3
  store ptr %t3206, ptr %t4
  br label %tco.loop.0
tco.case.arm.180.3210:
  %t3211 = getelementptr ptr, ptr %t5, i32 1
  %t3212 = load ptr, ptr %t3211
  %t3213 = getelementptr ptr, ptr %t5, i32 2
  %t3214 = load ptr, ptr %t3213
  %t3215 = getelementptr i8, ptr %t5, i64 -8
  %t3216 = load i32, ptr %t3215
  %t3217 = icmp eq i32 %t3216, 1
  br i1 %t3217, label %reuse.in_place.3218, label %reuse.copy.3219
reuse.in_place.3218:
  %t3221 = inttoptr i64 114 to ptr
  %t3222 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3221, ptr %t3222
  br label %reuse.join.3220
reuse.copy.3219:
  %t3223 = call ptr @__alloc(i64 24, i32 2)
  %t3224 = inttoptr i64 114 to ptr
  %t3225 = getelementptr ptr, ptr %t3223, i32 0
  store ptr %t3224, ptr %t3225
  call void @__inc_ref(ptr %t3212)
  %t3226 = getelementptr ptr, ptr %t3223, i32 1
  store ptr %t3212, ptr %t3226
  call void @__inc_ref(ptr %t3214)
  %t3227 = getelementptr ptr, ptr %t3223, i32 2
  store ptr %t3214, ptr %t3227
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3220
reuse.join.3220:
  %t3228 = phi ptr [ %t5, %reuse.in_place.3218 ], [ %t3223, %reuse.copy.3219 ]
  %t3229 = call ptr @__alloc(i64 16, i32 1)
  %t3230 = inttoptr i64 326 to ptr
  %t3231 = getelementptr ptr, ptr %t3229, i32 0
  store ptr %t3230, ptr %t3231
  call void @__inc_ref(ptr %t6)
  %t3232 = getelementptr ptr, ptr %t3229, i32 1
  store ptr %t6, ptr %t3232
  call void @__free_recursive(ptr %t6)
  store ptr %t3228, ptr %t3
  store ptr %t3229, ptr %t4
  br label %tco.loop.0
tco.case.arm.181.3233:
  %t3234 = getelementptr ptr, ptr %t5, i32 1
  %t3235 = load ptr, ptr %t3234
  %t3236 = getelementptr ptr, ptr %t5, i32 2
  %t3237 = load ptr, ptr %t3236
  %t3238 = getelementptr i8, ptr %t5, i64 -8
  %t3239 = load i32, ptr %t3238
  %t3240 = icmp eq i32 %t3239, 1
  br i1 %t3240, label %reuse.in_place.3241, label %reuse.copy.3242
reuse.in_place.3241:
  %t3244 = inttoptr i64 114 to ptr
  %t3245 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3244, ptr %t3245
  br label %reuse.join.3243
reuse.copy.3242:
  %t3246 = call ptr @__alloc(i64 24, i32 2)
  %t3247 = inttoptr i64 114 to ptr
  %t3248 = getelementptr ptr, ptr %t3246, i32 0
  store ptr %t3247, ptr %t3248
  call void @__inc_ref(ptr %t3235)
  %t3249 = getelementptr ptr, ptr %t3246, i32 1
  store ptr %t3235, ptr %t3249
  call void @__inc_ref(ptr %t3237)
  %t3250 = getelementptr ptr, ptr %t3246, i32 2
  store ptr %t3237, ptr %t3250
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3243
reuse.join.3243:
  %t3251 = phi ptr [ %t5, %reuse.in_place.3241 ], [ %t3246, %reuse.copy.3242 ]
  %t3252 = call ptr @__alloc(i64 16, i32 1)
  %t3253 = inttoptr i64 327 to ptr
  %t3254 = getelementptr ptr, ptr %t3252, i32 0
  store ptr %t3253, ptr %t3254
  call void @__inc_ref(ptr %t6)
  %t3255 = getelementptr ptr, ptr %t3252, i32 1
  store ptr %t6, ptr %t3255
  call void @__free_recursive(ptr %t6)
  store ptr %t3251, ptr %t3
  store ptr %t3252, ptr %t4
  br label %tco.loop.0
tco.case.arm.182.3256:
  %t3257 = getelementptr ptr, ptr %t5, i32 1
  %t3258 = load ptr, ptr %t3257
  %t3259 = getelementptr ptr, ptr %t5, i32 2
  %t3260 = load ptr, ptr %t3259
  %t3261 = getelementptr i8, ptr %t5, i64 -8
  %t3262 = load i32, ptr %t3261
  %t3263 = icmp eq i32 %t3262, 1
  br i1 %t3263, label %reuse.in_place.3264, label %reuse.copy.3265
reuse.in_place.3264:
  %t3267 = inttoptr i64 114 to ptr
  %t3268 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3267, ptr %t3268
  br label %reuse.join.3266
reuse.copy.3265:
  %t3269 = call ptr @__alloc(i64 24, i32 2)
  %t3270 = inttoptr i64 114 to ptr
  %t3271 = getelementptr ptr, ptr %t3269, i32 0
  store ptr %t3270, ptr %t3271
  call void @__inc_ref(ptr %t3258)
  %t3272 = getelementptr ptr, ptr %t3269, i32 1
  store ptr %t3258, ptr %t3272
  call void @__inc_ref(ptr %t3260)
  %t3273 = getelementptr ptr, ptr %t3269, i32 2
  store ptr %t3260, ptr %t3273
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3266
reuse.join.3266:
  %t3274 = phi ptr [ %t5, %reuse.in_place.3264 ], [ %t3269, %reuse.copy.3265 ]
  %t3275 = call ptr @__alloc(i64 16, i32 1)
  %t3276 = inttoptr i64 328 to ptr
  %t3277 = getelementptr ptr, ptr %t3275, i32 0
  store ptr %t3276, ptr %t3277
  call void @__inc_ref(ptr %t6)
  %t3278 = getelementptr ptr, ptr %t3275, i32 1
  store ptr %t6, ptr %t3278
  call void @__free_recursive(ptr %t6)
  store ptr %t3274, ptr %t3
  store ptr %t3275, ptr %t4
  br label %tco.loop.0
tco.case.arm.183.3279:
  %t3280 = getelementptr ptr, ptr %t5, i32 1
  %t3281 = load ptr, ptr %t3280
  %t3282 = getelementptr ptr, ptr %t5, i32 2
  %t3283 = load ptr, ptr %t3282
  %t3284 = getelementptr i8, ptr %t5, i64 -8
  %t3285 = load i32, ptr %t3284
  %t3286 = icmp eq i32 %t3285, 1
  br i1 %t3286, label %reuse.in_place.3287, label %reuse.copy.3288
reuse.in_place.3287:
  %t3290 = inttoptr i64 114 to ptr
  %t3291 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3290, ptr %t3291
  br label %reuse.join.3289
reuse.copy.3288:
  %t3292 = call ptr @__alloc(i64 24, i32 2)
  %t3293 = inttoptr i64 114 to ptr
  %t3294 = getelementptr ptr, ptr %t3292, i32 0
  store ptr %t3293, ptr %t3294
  call void @__inc_ref(ptr %t3281)
  %t3295 = getelementptr ptr, ptr %t3292, i32 1
  store ptr %t3281, ptr %t3295
  call void @__inc_ref(ptr %t3283)
  %t3296 = getelementptr ptr, ptr %t3292, i32 2
  store ptr %t3283, ptr %t3296
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3289
reuse.join.3289:
  %t3297 = phi ptr [ %t5, %reuse.in_place.3287 ], [ %t3292, %reuse.copy.3288 ]
  %t3298 = call ptr @__alloc(i64 16, i32 1)
  %t3299 = inttoptr i64 329 to ptr
  %t3300 = getelementptr ptr, ptr %t3298, i32 0
  store ptr %t3299, ptr %t3300
  call void @__inc_ref(ptr %t6)
  %t3301 = getelementptr ptr, ptr %t3298, i32 1
  store ptr %t6, ptr %t3301
  call void @__free_recursive(ptr %t6)
  store ptr %t3297, ptr %t3
  store ptr %t3298, ptr %t4
  br label %tco.loop.0
tco.case.arm.184.3302:
  %t3303 = getelementptr ptr, ptr %t5, i32 1
  %t3304 = load ptr, ptr %t3303
  %t3305 = getelementptr ptr, ptr %t5, i32 2
  %t3306 = load ptr, ptr %t3305
  %t3307 = getelementptr i8, ptr %t5, i64 -8
  %t3308 = load i32, ptr %t3307
  %t3309 = icmp eq i32 %t3308, 1
  br i1 %t3309, label %reuse.in_place.3310, label %reuse.copy.3311
reuse.in_place.3310:
  %t3313 = inttoptr i64 114 to ptr
  %t3314 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3313, ptr %t3314
  br label %reuse.join.3312
reuse.copy.3311:
  %t3315 = call ptr @__alloc(i64 24, i32 2)
  %t3316 = inttoptr i64 114 to ptr
  %t3317 = getelementptr ptr, ptr %t3315, i32 0
  store ptr %t3316, ptr %t3317
  call void @__inc_ref(ptr %t3304)
  %t3318 = getelementptr ptr, ptr %t3315, i32 1
  store ptr %t3304, ptr %t3318
  call void @__inc_ref(ptr %t3306)
  %t3319 = getelementptr ptr, ptr %t3315, i32 2
  store ptr %t3306, ptr %t3319
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3312
reuse.join.3312:
  %t3320 = phi ptr [ %t5, %reuse.in_place.3310 ], [ %t3315, %reuse.copy.3311 ]
  %t3321 = call ptr @__alloc(i64 16, i32 1)
  %t3322 = inttoptr i64 330 to ptr
  %t3323 = getelementptr ptr, ptr %t3321, i32 0
  store ptr %t3322, ptr %t3323
  call void @__inc_ref(ptr %t6)
  %t3324 = getelementptr ptr, ptr %t3321, i32 1
  store ptr %t6, ptr %t3324
  call void @__free_recursive(ptr %t6)
  store ptr %t3320, ptr %t3
  store ptr %t3321, ptr %t4
  br label %tco.loop.0
tco.case.arm.185.3325:
  %t3326 = getelementptr ptr, ptr %t5, i32 1
  %t3327 = load ptr, ptr %t3326
  %t3328 = getelementptr ptr, ptr %t5, i32 2
  %t3329 = load ptr, ptr %t3328
  %t3330 = getelementptr i8, ptr %t5, i64 -8
  %t3331 = load i32, ptr %t3330
  %t3332 = icmp eq i32 %t3331, 1
  br i1 %t3332, label %reuse.in_place.3333, label %reuse.copy.3334
reuse.in_place.3333:
  %t3336 = inttoptr i64 114 to ptr
  %t3337 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3336, ptr %t3337
  br label %reuse.join.3335
reuse.copy.3334:
  %t3338 = call ptr @__alloc(i64 24, i32 2)
  %t3339 = inttoptr i64 114 to ptr
  %t3340 = getelementptr ptr, ptr %t3338, i32 0
  store ptr %t3339, ptr %t3340
  call void @__inc_ref(ptr %t3327)
  %t3341 = getelementptr ptr, ptr %t3338, i32 1
  store ptr %t3327, ptr %t3341
  call void @__inc_ref(ptr %t3329)
  %t3342 = getelementptr ptr, ptr %t3338, i32 2
  store ptr %t3329, ptr %t3342
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3335
reuse.join.3335:
  %t3343 = phi ptr [ %t5, %reuse.in_place.3333 ], [ %t3338, %reuse.copy.3334 ]
  %t3344 = call ptr @__alloc(i64 16, i32 1)
  %t3345 = inttoptr i64 331 to ptr
  %t3346 = getelementptr ptr, ptr %t3344, i32 0
  store ptr %t3345, ptr %t3346
  call void @__inc_ref(ptr %t6)
  %t3347 = getelementptr ptr, ptr %t3344, i32 1
  store ptr %t6, ptr %t3347
  call void @__free_recursive(ptr %t6)
  store ptr %t3343, ptr %t3
  store ptr %t3344, ptr %t4
  br label %tco.loop.0
tco.case.arm.186.3348:
  %t3349 = getelementptr ptr, ptr %t5, i32 1
  %t3350 = load ptr, ptr %t3349
  %t3351 = getelementptr ptr, ptr %t5, i32 2
  %t3352 = load ptr, ptr %t3351
  %t3353 = getelementptr i8, ptr %t5, i64 -8
  %t3354 = load i32, ptr %t3353
  %t3355 = icmp eq i32 %t3354, 1
  br i1 %t3355, label %reuse.in_place.3356, label %reuse.copy.3357
reuse.in_place.3356:
  %t3359 = inttoptr i64 114 to ptr
  %t3360 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3359, ptr %t3360
  br label %reuse.join.3358
reuse.copy.3357:
  %t3361 = call ptr @__alloc(i64 24, i32 2)
  %t3362 = inttoptr i64 114 to ptr
  %t3363 = getelementptr ptr, ptr %t3361, i32 0
  store ptr %t3362, ptr %t3363
  call void @__inc_ref(ptr %t3350)
  %t3364 = getelementptr ptr, ptr %t3361, i32 1
  store ptr %t3350, ptr %t3364
  call void @__inc_ref(ptr %t3352)
  %t3365 = getelementptr ptr, ptr %t3361, i32 2
  store ptr %t3352, ptr %t3365
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3358
reuse.join.3358:
  %t3366 = phi ptr [ %t5, %reuse.in_place.3356 ], [ %t3361, %reuse.copy.3357 ]
  %t3367 = call ptr @__alloc(i64 16, i32 1)
  %t3368 = inttoptr i64 332 to ptr
  %t3369 = getelementptr ptr, ptr %t3367, i32 0
  store ptr %t3368, ptr %t3369
  call void @__inc_ref(ptr %t6)
  %t3370 = getelementptr ptr, ptr %t3367, i32 1
  store ptr %t6, ptr %t3370
  call void @__free_recursive(ptr %t6)
  store ptr %t3366, ptr %t3
  store ptr %t3367, ptr %t4
  br label %tco.loop.0
tco.case.arm.187.3371:
  %t3372 = getelementptr ptr, ptr %t5, i32 1
  %t3373 = load ptr, ptr %t3372
  %t3374 = getelementptr ptr, ptr %t5, i32 2
  %t3375 = load ptr, ptr %t3374
  %t3376 = getelementptr i8, ptr %t5, i64 -8
  %t3377 = load i32, ptr %t3376
  %t3378 = icmp eq i32 %t3377, 1
  br i1 %t3378, label %reuse.in_place.3379, label %reuse.copy.3380
reuse.in_place.3379:
  %t3382 = inttoptr i64 114 to ptr
  %t3383 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3382, ptr %t3383
  br label %reuse.join.3381
reuse.copy.3380:
  %t3384 = call ptr @__alloc(i64 24, i32 2)
  %t3385 = inttoptr i64 114 to ptr
  %t3386 = getelementptr ptr, ptr %t3384, i32 0
  store ptr %t3385, ptr %t3386
  call void @__inc_ref(ptr %t3373)
  %t3387 = getelementptr ptr, ptr %t3384, i32 1
  store ptr %t3373, ptr %t3387
  call void @__inc_ref(ptr %t3375)
  %t3388 = getelementptr ptr, ptr %t3384, i32 2
  store ptr %t3375, ptr %t3388
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3381
reuse.join.3381:
  %t3389 = phi ptr [ %t5, %reuse.in_place.3379 ], [ %t3384, %reuse.copy.3380 ]
  %t3390 = call ptr @__alloc(i64 16, i32 1)
  %t3391 = inttoptr i64 333 to ptr
  %t3392 = getelementptr ptr, ptr %t3390, i32 0
  store ptr %t3391, ptr %t3392
  call void @__inc_ref(ptr %t6)
  %t3393 = getelementptr ptr, ptr %t3390, i32 1
  store ptr %t6, ptr %t3393
  call void @__free_recursive(ptr %t6)
  store ptr %t3389, ptr %t3
  store ptr %t3390, ptr %t4
  br label %tco.loop.0
tco.case.arm.188.3394:
  %t3395 = getelementptr ptr, ptr %t5, i32 1
  %t3396 = load ptr, ptr %t3395
  %t3397 = getelementptr ptr, ptr %t5, i32 2
  %t3398 = load ptr, ptr %t3397
  %t3399 = getelementptr i8, ptr %t5, i64 -8
  %t3400 = load i32, ptr %t3399
  %t3401 = icmp eq i32 %t3400, 1
  br i1 %t3401, label %reuse.in_place.3402, label %reuse.copy.3403
reuse.in_place.3402:
  %t3405 = inttoptr i64 114 to ptr
  %t3406 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3405, ptr %t3406
  br label %reuse.join.3404
reuse.copy.3403:
  %t3407 = call ptr @__alloc(i64 24, i32 2)
  %t3408 = inttoptr i64 114 to ptr
  %t3409 = getelementptr ptr, ptr %t3407, i32 0
  store ptr %t3408, ptr %t3409
  call void @__inc_ref(ptr %t3396)
  %t3410 = getelementptr ptr, ptr %t3407, i32 1
  store ptr %t3396, ptr %t3410
  call void @__inc_ref(ptr %t3398)
  %t3411 = getelementptr ptr, ptr %t3407, i32 2
  store ptr %t3398, ptr %t3411
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3404
reuse.join.3404:
  %t3412 = phi ptr [ %t5, %reuse.in_place.3402 ], [ %t3407, %reuse.copy.3403 ]
  %t3413 = call ptr @__alloc(i64 16, i32 1)
  %t3414 = inttoptr i64 334 to ptr
  %t3415 = getelementptr ptr, ptr %t3413, i32 0
  store ptr %t3414, ptr %t3415
  call void @__inc_ref(ptr %t6)
  %t3416 = getelementptr ptr, ptr %t3413, i32 1
  store ptr %t6, ptr %t3416
  call void @__free_recursive(ptr %t6)
  store ptr %t3412, ptr %t3
  store ptr %t3413, ptr %t4
  br label %tco.loop.0
tco.case.arm.189.3417:
  %t3418 = getelementptr ptr, ptr %t5, i32 1
  %t3419 = load ptr, ptr %t3418
  %t3420 = getelementptr ptr, ptr %t5, i32 2
  %t3421 = load ptr, ptr %t3420
  %t3422 = getelementptr i8, ptr %t5, i64 -8
  %t3423 = load i32, ptr %t3422
  %t3424 = icmp eq i32 %t3423, 1
  br i1 %t3424, label %reuse.in_place.3425, label %reuse.copy.3426
reuse.in_place.3425:
  %t3428 = inttoptr i64 114 to ptr
  %t3429 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3428, ptr %t3429
  br label %reuse.join.3427
reuse.copy.3426:
  %t3430 = call ptr @__alloc(i64 24, i32 2)
  %t3431 = inttoptr i64 114 to ptr
  %t3432 = getelementptr ptr, ptr %t3430, i32 0
  store ptr %t3431, ptr %t3432
  call void @__inc_ref(ptr %t3419)
  %t3433 = getelementptr ptr, ptr %t3430, i32 1
  store ptr %t3419, ptr %t3433
  call void @__inc_ref(ptr %t3421)
  %t3434 = getelementptr ptr, ptr %t3430, i32 2
  store ptr %t3421, ptr %t3434
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3427
reuse.join.3427:
  %t3435 = phi ptr [ %t5, %reuse.in_place.3425 ], [ %t3430, %reuse.copy.3426 ]
  %t3436 = call ptr @__alloc(i64 16, i32 1)
  %t3437 = inttoptr i64 335 to ptr
  %t3438 = getelementptr ptr, ptr %t3436, i32 0
  store ptr %t3437, ptr %t3438
  call void @__inc_ref(ptr %t6)
  %t3439 = getelementptr ptr, ptr %t3436, i32 1
  store ptr %t6, ptr %t3439
  call void @__free_recursive(ptr %t6)
  store ptr %t3435, ptr %t3
  store ptr %t3436, ptr %t4
  br label %tco.loop.0
tco.case.arm.190.3440:
  %t3441 = getelementptr ptr, ptr %t5, i32 1
  %t3442 = load ptr, ptr %t3441
  %t3443 = getelementptr ptr, ptr %t5, i32 2
  %t3444 = load ptr, ptr %t3443
  %t3445 = getelementptr i8, ptr %t5, i64 -8
  %t3446 = load i32, ptr %t3445
  %t3447 = icmp eq i32 %t3446, 1
  br i1 %t3447, label %reuse.in_place.3448, label %reuse.copy.3449
reuse.in_place.3448:
  %t3451 = inttoptr i64 114 to ptr
  %t3452 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3451, ptr %t3452
  br label %reuse.join.3450
reuse.copy.3449:
  %t3453 = call ptr @__alloc(i64 24, i32 2)
  %t3454 = inttoptr i64 114 to ptr
  %t3455 = getelementptr ptr, ptr %t3453, i32 0
  store ptr %t3454, ptr %t3455
  call void @__inc_ref(ptr %t3442)
  %t3456 = getelementptr ptr, ptr %t3453, i32 1
  store ptr %t3442, ptr %t3456
  call void @__inc_ref(ptr %t3444)
  %t3457 = getelementptr ptr, ptr %t3453, i32 2
  store ptr %t3444, ptr %t3457
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3450
reuse.join.3450:
  %t3458 = phi ptr [ %t5, %reuse.in_place.3448 ], [ %t3453, %reuse.copy.3449 ]
  %t3459 = call ptr @__alloc(i64 16, i32 1)
  %t3460 = inttoptr i64 336 to ptr
  %t3461 = getelementptr ptr, ptr %t3459, i32 0
  store ptr %t3460, ptr %t3461
  call void @__inc_ref(ptr %t6)
  %t3462 = getelementptr ptr, ptr %t3459, i32 1
  store ptr %t6, ptr %t3462
  call void @__free_recursive(ptr %t6)
  store ptr %t3458, ptr %t3
  store ptr %t3459, ptr %t4
  br label %tco.loop.0
tco.case.arm.191.3463:
  %t3464 = getelementptr ptr, ptr %t5, i32 1
  %t3465 = load ptr, ptr %t3464
  %t3466 = getelementptr ptr, ptr %t5, i32 2
  %t3467 = load ptr, ptr %t3466
  %t3468 = getelementptr i8, ptr %t5, i64 -8
  %t3469 = load i32, ptr %t3468
  %t3470 = icmp eq i32 %t3469, 1
  br i1 %t3470, label %reuse.in_place.3471, label %reuse.copy.3472
reuse.in_place.3471:
  %t3474 = inttoptr i64 114 to ptr
  %t3475 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3474, ptr %t3475
  br label %reuse.join.3473
reuse.copy.3472:
  %t3476 = call ptr @__alloc(i64 24, i32 2)
  %t3477 = inttoptr i64 114 to ptr
  %t3478 = getelementptr ptr, ptr %t3476, i32 0
  store ptr %t3477, ptr %t3478
  call void @__inc_ref(ptr %t3465)
  %t3479 = getelementptr ptr, ptr %t3476, i32 1
  store ptr %t3465, ptr %t3479
  call void @__inc_ref(ptr %t3467)
  %t3480 = getelementptr ptr, ptr %t3476, i32 2
  store ptr %t3467, ptr %t3480
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3473
reuse.join.3473:
  %t3481 = phi ptr [ %t5, %reuse.in_place.3471 ], [ %t3476, %reuse.copy.3472 ]
  %t3482 = call ptr @__alloc(i64 16, i32 1)
  %t3483 = inttoptr i64 337 to ptr
  %t3484 = getelementptr ptr, ptr %t3482, i32 0
  store ptr %t3483, ptr %t3484
  call void @__inc_ref(ptr %t6)
  %t3485 = getelementptr ptr, ptr %t3482, i32 1
  store ptr %t6, ptr %t3485
  call void @__free_recursive(ptr %t6)
  store ptr %t3481, ptr %t3
  store ptr %t3482, ptr %t4
  br label %tco.loop.0
tco.case.arm.192.3486:
  %t3487 = getelementptr ptr, ptr %t5, i32 1
  %t3488 = load ptr, ptr %t3487
  %t3489 = getelementptr ptr, ptr %t5, i32 2
  %t3490 = load ptr, ptr %t3489
  %t3491 = getelementptr i8, ptr %t5, i64 -8
  %t3492 = load i32, ptr %t3491
  %t3493 = icmp eq i32 %t3492, 1
  br i1 %t3493, label %reuse.in_place.3494, label %reuse.copy.3495
reuse.in_place.3494:
  %t3497 = inttoptr i64 114 to ptr
  %t3498 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3497, ptr %t3498
  br label %reuse.join.3496
reuse.copy.3495:
  %t3499 = call ptr @__alloc(i64 24, i32 2)
  %t3500 = inttoptr i64 114 to ptr
  %t3501 = getelementptr ptr, ptr %t3499, i32 0
  store ptr %t3500, ptr %t3501
  call void @__inc_ref(ptr %t3488)
  %t3502 = getelementptr ptr, ptr %t3499, i32 1
  store ptr %t3488, ptr %t3502
  call void @__inc_ref(ptr %t3490)
  %t3503 = getelementptr ptr, ptr %t3499, i32 2
  store ptr %t3490, ptr %t3503
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3496
reuse.join.3496:
  %t3504 = phi ptr [ %t5, %reuse.in_place.3494 ], [ %t3499, %reuse.copy.3495 ]
  %t3505 = call ptr @__alloc(i64 16, i32 1)
  %t3506 = inttoptr i64 338 to ptr
  %t3507 = getelementptr ptr, ptr %t3505, i32 0
  store ptr %t3506, ptr %t3507
  call void @__inc_ref(ptr %t6)
  %t3508 = getelementptr ptr, ptr %t3505, i32 1
  store ptr %t6, ptr %t3508
  call void @__free_recursive(ptr %t6)
  store ptr %t3504, ptr %t3
  store ptr %t3505, ptr %t4
  br label %tco.loop.0
tco.case.arm.193.3509:
  %t3510 = getelementptr ptr, ptr %t5, i32 1
  %t3511 = load ptr, ptr %t3510
  %t3512 = getelementptr ptr, ptr %t5, i32 2
  %t3513 = load ptr, ptr %t3512
  %t3514 = getelementptr i8, ptr %t5, i64 -8
  %t3515 = load i32, ptr %t3514
  %t3516 = icmp eq i32 %t3515, 1
  br i1 %t3516, label %reuse.in_place.3517, label %reuse.copy.3518
reuse.in_place.3517:
  %t3520 = inttoptr i64 114 to ptr
  %t3521 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3520, ptr %t3521
  br label %reuse.join.3519
reuse.copy.3518:
  %t3522 = call ptr @__alloc(i64 24, i32 2)
  %t3523 = inttoptr i64 114 to ptr
  %t3524 = getelementptr ptr, ptr %t3522, i32 0
  store ptr %t3523, ptr %t3524
  call void @__inc_ref(ptr %t3511)
  %t3525 = getelementptr ptr, ptr %t3522, i32 1
  store ptr %t3511, ptr %t3525
  call void @__inc_ref(ptr %t3513)
  %t3526 = getelementptr ptr, ptr %t3522, i32 2
  store ptr %t3513, ptr %t3526
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3519
reuse.join.3519:
  %t3527 = phi ptr [ %t5, %reuse.in_place.3517 ], [ %t3522, %reuse.copy.3518 ]
  %t3528 = call ptr @__alloc(i64 16, i32 1)
  %t3529 = inttoptr i64 339 to ptr
  %t3530 = getelementptr ptr, ptr %t3528, i32 0
  store ptr %t3529, ptr %t3530
  call void @__inc_ref(ptr %t6)
  %t3531 = getelementptr ptr, ptr %t3528, i32 1
  store ptr %t6, ptr %t3531
  call void @__free_recursive(ptr %t6)
  store ptr %t3527, ptr %t3
  store ptr %t3528, ptr %t4
  br label %tco.loop.0
tco.case.arm.194.3532:
  %t3533 = getelementptr ptr, ptr %t5, i32 1
  %t3534 = load ptr, ptr %t3533
  %t3535 = getelementptr ptr, ptr %t5, i32 2
  %t3536 = load ptr, ptr %t3535
  %t3537 = getelementptr i8, ptr %t5, i64 -8
  %t3538 = load i32, ptr %t3537
  %t3539 = icmp eq i32 %t3538, 1
  br i1 %t3539, label %reuse.in_place.3540, label %reuse.copy.3541
reuse.in_place.3540:
  %t3543 = inttoptr i64 114 to ptr
  %t3544 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3543, ptr %t3544
  br label %reuse.join.3542
reuse.copy.3541:
  %t3545 = call ptr @__alloc(i64 24, i32 2)
  %t3546 = inttoptr i64 114 to ptr
  %t3547 = getelementptr ptr, ptr %t3545, i32 0
  store ptr %t3546, ptr %t3547
  call void @__inc_ref(ptr %t3534)
  %t3548 = getelementptr ptr, ptr %t3545, i32 1
  store ptr %t3534, ptr %t3548
  call void @__inc_ref(ptr %t3536)
  %t3549 = getelementptr ptr, ptr %t3545, i32 2
  store ptr %t3536, ptr %t3549
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3542
reuse.join.3542:
  %t3550 = phi ptr [ %t5, %reuse.in_place.3540 ], [ %t3545, %reuse.copy.3541 ]
  %t3551 = call ptr @__alloc(i64 16, i32 1)
  %t3552 = inttoptr i64 340 to ptr
  %t3553 = getelementptr ptr, ptr %t3551, i32 0
  store ptr %t3552, ptr %t3553
  call void @__inc_ref(ptr %t6)
  %t3554 = getelementptr ptr, ptr %t3551, i32 1
  store ptr %t6, ptr %t3554
  call void @__free_recursive(ptr %t6)
  store ptr %t3550, ptr %t3
  store ptr %t3551, ptr %t4
  br label %tco.loop.0
tco.case.arm.195.3555:
  %t3556 = getelementptr ptr, ptr %t5, i32 1
  %t3557 = load ptr, ptr %t3556
  %t3558 = getelementptr ptr, ptr %t5, i32 2
  %t3559 = load ptr, ptr %t3558
  %t3560 = getelementptr i8, ptr %t5, i64 -8
  %t3561 = load i32, ptr %t3560
  %t3562 = icmp eq i32 %t3561, 1
  br i1 %t3562, label %reuse.in_place.3563, label %reuse.copy.3564
reuse.in_place.3563:
  %t3566 = inttoptr i64 114 to ptr
  %t3567 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3566, ptr %t3567
  br label %reuse.join.3565
reuse.copy.3564:
  %t3568 = call ptr @__alloc(i64 24, i32 2)
  %t3569 = inttoptr i64 114 to ptr
  %t3570 = getelementptr ptr, ptr %t3568, i32 0
  store ptr %t3569, ptr %t3570
  call void @__inc_ref(ptr %t3557)
  %t3571 = getelementptr ptr, ptr %t3568, i32 1
  store ptr %t3557, ptr %t3571
  call void @__inc_ref(ptr %t3559)
  %t3572 = getelementptr ptr, ptr %t3568, i32 2
  store ptr %t3559, ptr %t3572
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3565
reuse.join.3565:
  %t3573 = phi ptr [ %t5, %reuse.in_place.3563 ], [ %t3568, %reuse.copy.3564 ]
  %t3574 = call ptr @__alloc(i64 16, i32 1)
  %t3575 = inttoptr i64 341 to ptr
  %t3576 = getelementptr ptr, ptr %t3574, i32 0
  store ptr %t3575, ptr %t3576
  call void @__inc_ref(ptr %t6)
  %t3577 = getelementptr ptr, ptr %t3574, i32 1
  store ptr %t6, ptr %t3577
  call void @__free_recursive(ptr %t6)
  store ptr %t3573, ptr %t3
  store ptr %t3574, ptr %t4
  br label %tco.loop.0
tco.case.arm.196.3578:
  %t3579 = getelementptr ptr, ptr %t5, i32 1
  %t3580 = load ptr, ptr %t3579
  %t3581 = getelementptr ptr, ptr %t5, i32 2
  %t3582 = load ptr, ptr %t3581
  %t3583 = getelementptr i8, ptr %t5, i64 -8
  %t3584 = load i32, ptr %t3583
  %t3585 = icmp eq i32 %t3584, 1
  br i1 %t3585, label %reuse.in_place.3586, label %reuse.copy.3587
reuse.in_place.3586:
  %t3589 = inttoptr i64 114 to ptr
  %t3590 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3589, ptr %t3590
  br label %reuse.join.3588
reuse.copy.3587:
  %t3591 = call ptr @__alloc(i64 24, i32 2)
  %t3592 = inttoptr i64 114 to ptr
  %t3593 = getelementptr ptr, ptr %t3591, i32 0
  store ptr %t3592, ptr %t3593
  call void @__inc_ref(ptr %t3580)
  %t3594 = getelementptr ptr, ptr %t3591, i32 1
  store ptr %t3580, ptr %t3594
  call void @__inc_ref(ptr %t3582)
  %t3595 = getelementptr ptr, ptr %t3591, i32 2
  store ptr %t3582, ptr %t3595
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3588
reuse.join.3588:
  %t3596 = phi ptr [ %t5, %reuse.in_place.3586 ], [ %t3591, %reuse.copy.3587 ]
  %t3597 = call ptr @__alloc(i64 16, i32 1)
  %t3598 = inttoptr i64 342 to ptr
  %t3599 = getelementptr ptr, ptr %t3597, i32 0
  store ptr %t3598, ptr %t3599
  call void @__inc_ref(ptr %t6)
  %t3600 = getelementptr ptr, ptr %t3597, i32 1
  store ptr %t6, ptr %t3600
  call void @__free_recursive(ptr %t6)
  store ptr %t3596, ptr %t3
  store ptr %t3597, ptr %t4
  br label %tco.loop.0
tco.case.arm.197.3601:
  %t3602 = getelementptr ptr, ptr %t5, i32 1
  %t3603 = load ptr, ptr %t3602
  %t3604 = getelementptr ptr, ptr %t5, i32 2
  %t3605 = load ptr, ptr %t3604
  %t3606 = getelementptr i8, ptr %t5, i64 -8
  %t3607 = load i32, ptr %t3606
  %t3608 = icmp eq i32 %t3607, 1
  br i1 %t3608, label %reuse.in_place.3609, label %reuse.copy.3610
reuse.in_place.3609:
  %t3612 = inttoptr i64 114 to ptr
  %t3613 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3612, ptr %t3613
  br label %reuse.join.3611
reuse.copy.3610:
  %t3614 = call ptr @__alloc(i64 24, i32 2)
  %t3615 = inttoptr i64 114 to ptr
  %t3616 = getelementptr ptr, ptr %t3614, i32 0
  store ptr %t3615, ptr %t3616
  call void @__inc_ref(ptr %t3603)
  %t3617 = getelementptr ptr, ptr %t3614, i32 1
  store ptr %t3603, ptr %t3617
  call void @__inc_ref(ptr %t3605)
  %t3618 = getelementptr ptr, ptr %t3614, i32 2
  store ptr %t3605, ptr %t3618
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3611
reuse.join.3611:
  %t3619 = phi ptr [ %t5, %reuse.in_place.3609 ], [ %t3614, %reuse.copy.3610 ]
  %t3620 = call ptr @__alloc(i64 16, i32 1)
  %t3621 = inttoptr i64 343 to ptr
  %t3622 = getelementptr ptr, ptr %t3620, i32 0
  store ptr %t3621, ptr %t3622
  call void @__inc_ref(ptr %t6)
  %t3623 = getelementptr ptr, ptr %t3620, i32 1
  store ptr %t6, ptr %t3623
  call void @__free_recursive(ptr %t6)
  store ptr %t3619, ptr %t3
  store ptr %t3620, ptr %t4
  br label %tco.loop.0
tco.case.arm.198.3624:
  %t3625 = getelementptr ptr, ptr %t5, i32 1
  %t3626 = load ptr, ptr %t3625
  %t3627 = getelementptr ptr, ptr %t5, i32 2
  %t3628 = load ptr, ptr %t3627
  %t3629 = getelementptr i8, ptr %t5, i64 -8
  %t3630 = load i32, ptr %t3629
  %t3631 = icmp eq i32 %t3630, 1
  br i1 %t3631, label %reuse.in_place.3632, label %reuse.copy.3633
reuse.in_place.3632:
  %t3635 = inttoptr i64 114 to ptr
  %t3636 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3635, ptr %t3636
  br label %reuse.join.3634
reuse.copy.3633:
  %t3637 = call ptr @__alloc(i64 24, i32 2)
  %t3638 = inttoptr i64 114 to ptr
  %t3639 = getelementptr ptr, ptr %t3637, i32 0
  store ptr %t3638, ptr %t3639
  call void @__inc_ref(ptr %t3626)
  %t3640 = getelementptr ptr, ptr %t3637, i32 1
  store ptr %t3626, ptr %t3640
  call void @__inc_ref(ptr %t3628)
  %t3641 = getelementptr ptr, ptr %t3637, i32 2
  store ptr %t3628, ptr %t3641
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3634
reuse.join.3634:
  %t3642 = phi ptr [ %t5, %reuse.in_place.3632 ], [ %t3637, %reuse.copy.3633 ]
  %t3643 = call ptr @__alloc(i64 16, i32 1)
  %t3644 = inttoptr i64 344 to ptr
  %t3645 = getelementptr ptr, ptr %t3643, i32 0
  store ptr %t3644, ptr %t3645
  call void @__inc_ref(ptr %t6)
  %t3646 = getelementptr ptr, ptr %t3643, i32 1
  store ptr %t6, ptr %t3646
  call void @__free_recursive(ptr %t6)
  store ptr %t3642, ptr %t3
  store ptr %t3643, ptr %t4
  br label %tco.loop.0
tco.case.arm.199.3647:
  %t3648 = getelementptr ptr, ptr %t5, i32 1
  %t3649 = load ptr, ptr %t3648
  %t3650 = getelementptr ptr, ptr %t5, i32 2
  %t3651 = load ptr, ptr %t3650
  %t3652 = getelementptr i8, ptr %t5, i64 -8
  %t3653 = load i32, ptr %t3652
  %t3654 = icmp eq i32 %t3653, 1
  br i1 %t3654, label %reuse.in_place.3655, label %reuse.copy.3656
reuse.in_place.3655:
  %t3658 = inttoptr i64 114 to ptr
  %t3659 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3658, ptr %t3659
  br label %reuse.join.3657
reuse.copy.3656:
  %t3660 = call ptr @__alloc(i64 24, i32 2)
  %t3661 = inttoptr i64 114 to ptr
  %t3662 = getelementptr ptr, ptr %t3660, i32 0
  store ptr %t3661, ptr %t3662
  call void @__inc_ref(ptr %t3649)
  %t3663 = getelementptr ptr, ptr %t3660, i32 1
  store ptr %t3649, ptr %t3663
  call void @__inc_ref(ptr %t3651)
  %t3664 = getelementptr ptr, ptr %t3660, i32 2
  store ptr %t3651, ptr %t3664
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3657
reuse.join.3657:
  %t3665 = phi ptr [ %t5, %reuse.in_place.3655 ], [ %t3660, %reuse.copy.3656 ]
  %t3666 = call ptr @__alloc(i64 16, i32 1)
  %t3667 = inttoptr i64 345 to ptr
  %t3668 = getelementptr ptr, ptr %t3666, i32 0
  store ptr %t3667, ptr %t3668
  call void @__inc_ref(ptr %t6)
  %t3669 = getelementptr ptr, ptr %t3666, i32 1
  store ptr %t6, ptr %t3669
  call void @__free_recursive(ptr %t6)
  store ptr %t3665, ptr %t3
  store ptr %t3666, ptr %t4
  br label %tco.loop.0
tco.case.arm.200.3670:
  %t3671 = getelementptr ptr, ptr %t5, i32 1
  %t3672 = load ptr, ptr %t3671
  %t3673 = getelementptr ptr, ptr %t5, i32 2
  %t3674 = load ptr, ptr %t3673
  %t3675 = getelementptr i8, ptr %t5, i64 -8
  %t3676 = load i32, ptr %t3675
  %t3677 = icmp eq i32 %t3676, 1
  br i1 %t3677, label %reuse.in_place.3678, label %reuse.copy.3679
reuse.in_place.3678:
  %t3681 = inttoptr i64 114 to ptr
  %t3682 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3681, ptr %t3682
  br label %reuse.join.3680
reuse.copy.3679:
  %t3683 = call ptr @__alloc(i64 24, i32 2)
  %t3684 = inttoptr i64 114 to ptr
  %t3685 = getelementptr ptr, ptr %t3683, i32 0
  store ptr %t3684, ptr %t3685
  call void @__inc_ref(ptr %t3672)
  %t3686 = getelementptr ptr, ptr %t3683, i32 1
  store ptr %t3672, ptr %t3686
  call void @__inc_ref(ptr %t3674)
  %t3687 = getelementptr ptr, ptr %t3683, i32 2
  store ptr %t3674, ptr %t3687
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3680
reuse.join.3680:
  %t3688 = phi ptr [ %t5, %reuse.in_place.3678 ], [ %t3683, %reuse.copy.3679 ]
  %t3689 = call ptr @__alloc(i64 16, i32 1)
  %t3690 = inttoptr i64 346 to ptr
  %t3691 = getelementptr ptr, ptr %t3689, i32 0
  store ptr %t3690, ptr %t3691
  call void @__inc_ref(ptr %t6)
  %t3692 = getelementptr ptr, ptr %t3689, i32 1
  store ptr %t6, ptr %t3692
  call void @__free_recursive(ptr %t6)
  store ptr %t3688, ptr %t3
  store ptr %t3689, ptr %t4
  br label %tco.loop.0
tco.case.arm.201.3693:
  %t3694 = getelementptr ptr, ptr %t5, i32 1
  %t3695 = load ptr, ptr %t3694
  %t3696 = getelementptr ptr, ptr %t5, i32 2
  %t3697 = load ptr, ptr %t3696
  %t3698 = getelementptr i8, ptr %t5, i64 -8
  %t3699 = load i32, ptr %t3698
  %t3700 = icmp eq i32 %t3699, 1
  br i1 %t3700, label %reuse.in_place.3701, label %reuse.copy.3702
reuse.in_place.3701:
  %t3704 = inttoptr i64 114 to ptr
  %t3705 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3704, ptr %t3705
  br label %reuse.join.3703
reuse.copy.3702:
  %t3706 = call ptr @__alloc(i64 24, i32 2)
  %t3707 = inttoptr i64 114 to ptr
  %t3708 = getelementptr ptr, ptr %t3706, i32 0
  store ptr %t3707, ptr %t3708
  call void @__inc_ref(ptr %t3695)
  %t3709 = getelementptr ptr, ptr %t3706, i32 1
  store ptr %t3695, ptr %t3709
  call void @__inc_ref(ptr %t3697)
  %t3710 = getelementptr ptr, ptr %t3706, i32 2
  store ptr %t3697, ptr %t3710
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3703
reuse.join.3703:
  %t3711 = phi ptr [ %t5, %reuse.in_place.3701 ], [ %t3706, %reuse.copy.3702 ]
  %t3712 = call ptr @__alloc(i64 16, i32 1)
  %t3713 = inttoptr i64 347 to ptr
  %t3714 = getelementptr ptr, ptr %t3712, i32 0
  store ptr %t3713, ptr %t3714
  call void @__inc_ref(ptr %t6)
  %t3715 = getelementptr ptr, ptr %t3712, i32 1
  store ptr %t6, ptr %t3715
  call void @__free_recursive(ptr %t6)
  store ptr %t3711, ptr %t3
  store ptr %t3712, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t3716 = load ptr, ptr %t2
  ret ptr %t3716
}

define internal ptr @v__apply1(ptr %v__cl, ptr %v__arg0) {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 114 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  call void @__inc_ref(ptr %v__cl)
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v__cl, ptr %t3
  call void @__inc_ref(ptr %v__arg0)
  %t4 = getelementptr ptr, ptr %t0, i32 2
  store ptr %v__arg0, ptr %t4
  %t5 = call ptr @v__scc__apply1__df__lam_10_39__df__lam_14_1__df__lam_14_13__df__lam_14_17__df__lam_14_21__df__lam_14_29__df__lam_14_41__df__lam_14_45__df__lam_14_5__df__lam_14_9__df__lam_15_10__df__lam_15_14__df__lam_15_18__df__lam_15_2__df__lam_15_22__df__lam_15_30__df__lam_15_42__df__lam_15_46__df__lam_15_6__df__lam_16_11__df__lam_16_15__df__lam_16_19__df__lam_16_23__df__lam_16_3__df__lam_16_31__df__lam_16_43__df__lam_16_47__df__lam_16_7__df__lam_46_49__df__lam_47_50__df__lam_48_51__df__lam_5_25__df__lam_5_33__df__lam_5_53__df__lam_5_57__df__lam_5_61__df__lam_5_65__df__lam_5_69__df__lam_5_73__df__lam_5_77__df__lam_5_81__df__lam_5_85__df__lam_5_89__df__lam_5_93__df__lam_6_26__df__lam_6_34__df__lam_6_54__df__lam_6_58__df__lam_6_62__df__lam_6_66__df__lam_6_70__df__lam_6_74__df__lam_6_78__df__lam_6_82__df__lam_6_86__df__lam_6_90__df__lam_6_94__df__lam_7_27__df__lam_7_35__df__lam_7_55__df__lam_7_59__df__lam_7_63__df__lam_7_67__df__lam_7_71__df__lam_7_75__df__lam_7_79__df__lam_7_83__df__lam_7_87__df__lam_7_91__df__lam_7_95__df__lam_8_37__df__lam_9_38__lift_19__lift_2__lift_20__lift_21__lift_23__lift_24__lift_25__lift_27__lift_28__lift_29__lift_3__lift_4__lift_43__lift_44__lift_45(ptr %t0)
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
