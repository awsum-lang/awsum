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
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 2286545437 to ptr
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
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 2252990199 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 8, i32 0)
  %t4 = inttoptr i64 24 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  %t7 = call ptr @v_failIO(ptr %t0)
  ret ptr %t7
}

define internal ptr @v_inErrB() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 2269767818 to ptr
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
  %t1 = inttoptr i64 184 to ptr
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
  %t42 = inttoptr i64 185 to ptr
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
  %t45 = inttoptr i64 185 to ptr
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
  %t57 = inttoptr i64 99 to ptr
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
  %t69 = inttoptr i64 100 to ptr
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
  %t81 = inttoptr i64 104 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 184, label %tco.case.arm.184.11 i64 185, label %tco.case.arm.185.12 ]
tco.case.arm.184.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.185.12:
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
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 24 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_failIO(ptr %t0)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t3
}

define internal ptr @v__lam_19(ptr %v__u) {
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

define internal ptr @v__lam_20(ptr %v_act, ptr %v__u) {
  call void @__free_recursive(ptr %v__u)
  ret ptr %v_act
}

define internal ptr @v__lam_21(ptr %v__u) {
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

define internal ptr @v__lam_22(ptr %v__u) {
  %t0 = call ptr @v_treeNoError()
  %t1 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.9, i64 12), ptr %t0)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t1
}

define internal ptr @v__lam_23(ptr %v__u) {
  %t0 = call ptr @v_treePreserve()
  %t1 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.10, i64 12), ptr %t0)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t1
}

define internal ptr @v__lam_24(ptr %v__u) {
  %t0 = call ptr @v_refailRow()
  %t1 = call ptr @v_observeBC(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.11, i64 12), ptr %t1)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t2
}

define internal ptr @v__lam_25(ptr %v__u) {
  %t0 = call ptr @v_refailNarrow()
  %t1 = call ptr @v_observeB(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.12, i64 12), ptr %t1)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t2
}

define internal ptr @v__lam_26(ptr %v__u) {
  %t0 = call ptr @v_nested()
  %t1 = call ptr @v_observeNever(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.13, i64 12), ptr %t1)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t2
}

define internal ptr @v__lam_27(ptr %v__u) {
  %t0 = call ptr @v_passthrough()
  %t1 = call ptr @v_observeNever(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.14, i64 12), ptr %t1)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t2
}

define internal ptr @v__lam_28(ptr %v__u) {
  %t0 = call ptr @v_dispatchB()
  %t1 = call ptr @v_observeNever(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.15, i64 12), ptr %t1)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t2
}

define internal ptr @v__lam_29(ptr %v__u) {
  %t0 = call ptr @v_dispatchA()
  %t1 = call ptr @v_observeNever(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.16, i64 12), ptr %t1)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t2
}

define internal ptr @v__lift_30(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 186 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__lift_30(ptr %v___input, ptr %t0)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t3
}

define internal ptr @v__cps__lift_30(ptr %v___input, ptr %v__k) {
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
  %t18 = call ptr @v__apply__lift_30(ptr %t6, ptr %t14)
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
  %t26 = call ptr @v__apply__lift_30(ptr %t6, ptr %t22)
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
  %t42 = inttoptr i64 187 to ptr
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
  %t45 = inttoptr i64 187 to ptr
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
  %t57 = inttoptr i64 101 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  call void @__inc_ref(ptr %t52)
  %t59 = getelementptr ptr, ptr %t56, i32 1
  store ptr %t52, ptr %t59
  %t60 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t56, ptr %t60
  %t61 = call ptr @v__apply__lift_30(ptr %t6, ptr %t53)
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
  %t69 = inttoptr i64 102 to ptr
  %t70 = getelementptr ptr, ptr %t68, i32 0
  store ptr %t69, ptr %t70
  call void @__inc_ref(ptr %t64)
  %t71 = getelementptr ptr, ptr %t68, i32 1
  store ptr %t64, ptr %t71
  %t72 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t68, ptr %t72
  %t73 = call ptr @v__apply__lift_30(ptr %t6, ptr %t65)
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
  %t81 = inttoptr i64 103 to ptr
  %t82 = getelementptr ptr, ptr %t80, i32 0
  store ptr %t81, ptr %t82
  call void @__inc_ref(ptr %t76)
  %t83 = getelementptr ptr, ptr %t80, i32 1
  store ptr %t76, ptr %t83
  %t84 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t80, ptr %t84
  %t85 = call ptr @v__apply__lift_30(ptr %t6, ptr %t77)
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

define internal ptr @v__apply__lift_30(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 186, label %tco.case.arm.186.11 i64 187, label %tco.case.arm.187.12 ]
tco.case.arm.186.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.187.12:
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
  %t1 = inttoptr i64 188 to ptr
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
  %t39 = inttoptr i64 189 to ptr
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
  %t42 = inttoptr i64 189 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 188, label %tco.case.arm.188.11 i64 189, label %tco.case.arm.189.12 ]
tco.case.arm.188.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.189.12:
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
  %t1 = inttoptr i64 190 to ptr
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
  %t39 = inttoptr i64 191 to ptr
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
  %t42 = inttoptr i64 191 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 190, label %tco.case.arm.190.11 i64 191, label %tco.case.arm.191.12 ]
tco.case.arm.190.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.191.12:
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
  %t1 = inttoptr i64 192 to ptr
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
  %t39 = inttoptr i64 193 to ptr
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
  %t42 = inttoptr i64 193 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 192, label %tco.case.arm.192.11 i64 193, label %tco.case.arm.193.12 ]
tco.case.arm.192.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.193.12:
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
  %t1 = inttoptr i64 194 to ptr
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
  %t39 = inttoptr i64 195 to ptr
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
  %t42 = inttoptr i64 195 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 194, label %tco.case.arm.194.11 i64 195, label %tco.case.arm.195.12 ]
tco.case.arm.194.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.195.12:
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
  %t1 = inttoptr i64 196 to ptr
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
  %t39 = inttoptr i64 197 to ptr
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
  %t42 = inttoptr i64 197 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 196, label %tco.case.arm.196.11 i64 197, label %tco.case.arm.197.12 ]
tco.case.arm.196.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.197.12:
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
  %t1 = inttoptr i64 198 to ptr
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
  %t39 = inttoptr i64 199 to ptr
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
  %t42 = inttoptr i64 199 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 198, label %tco.case.arm.198.11 i64 199, label %tco.case.arm.199.12 ]
tco.case.arm.198.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.199.12:
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
  %t1 = inttoptr i64 200 to ptr
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
  %t14 = call ptr @v__lam_18(ptr %t13)
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
  %t40 = inttoptr i64 201 to ptr
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
  %t43 = inttoptr i64 201 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 200, label %tco.case.arm.200.11 i64 201, label %tco.case.arm.201.12 ]
tco.case.arm.200.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.201.12:
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
  %t1 = inttoptr i64 202 to ptr
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
  %t39 = inttoptr i64 203 to ptr
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
  %t42 = inttoptr i64 203 to ptr
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

define internal ptr @v__df_andThenIO_32(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 204 to ptr
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
  %t40 = inttoptr i64 205 to ptr
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
  %t43 = inttoptr i64 205 to ptr
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

define internal ptr @v__df_mapIO_36(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 206 to ptr
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
  %t43 = inttoptr i64 207 to ptr
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
  %t46 = inttoptr i64 207 to ptr
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

define internal ptr @v__df_handleErrorIO_40(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 208 to ptr
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
  %t39 = inttoptr i64 209 to ptr
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
  %t42 = inttoptr i64 209 to ptr
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

define internal ptr @v__df_handleErrorIO_44(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 210 to ptr
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
  %t39 = inttoptr i64 211 to ptr
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
  %t42 = inttoptr i64 211 to ptr
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

define internal ptr @v__df__rowmono_0_andThenIO_48(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 212 to ptr
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
  %t15 = call ptr @v__lift_30(ptr %t14)
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
  %t40 = inttoptr i64 213 to ptr
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
  %t43 = inttoptr i64 213 to ptr
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

define internal ptr @v__df_andThenIO_52(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 214 to ptr
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
  %t14 = call ptr @v__lam_19(ptr %t13)
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
  %t40 = inttoptr i64 215 to ptr
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
  %t43 = inttoptr i64 215 to ptr
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

define internal ptr @v__df_andThenIO_56(ptr %v_io, ptr %v__df_andThenIO_56_cap0_0) {
  call void @__inc_ref(ptr %v_io)
  call void @__inc_ref(ptr %v__df_andThenIO_56_cap0_0)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 216 to ptr
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
  %t16 = call ptr @v__lam_20(ptr %t7, ptr %t15)
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
  %t42 = inttoptr i64 217 to ptr
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
  %t45 = inttoptr i64 217 to ptr
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

define internal ptr @v__df_andThenIO_60(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 218 to ptr
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
  %t14 = call ptr @v__lam_21(ptr %t13)
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
  %t40 = inttoptr i64 219 to ptr
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
  %t43 = inttoptr i64 219 to ptr
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

define internal ptr @v__df_andThenIO_64(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 220 to ptr
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
  %t14 = call ptr @v__lam_22(ptr %t13)
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
  %t40 = inttoptr i64 221 to ptr
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
  %t43 = inttoptr i64 221 to ptr
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

define internal ptr @v__df_andThenIO_68(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 222 to ptr
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
  %t14 = call ptr @v__lam_23(ptr %t13)
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
  %t40 = inttoptr i64 223 to ptr
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
  %t43 = inttoptr i64 223 to ptr
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

define internal ptr @v__df_andThenIO_72(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 224 to ptr
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
  %t14 = call ptr @v__lam_24(ptr %t13)
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

define internal ptr @v__df_andThenIO_76(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 226 to ptr
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
  %t14 = call ptr @v__lam_25(ptr %t13)
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
  %t40 = inttoptr i64 227 to ptr
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
  %t43 = inttoptr i64 227 to ptr
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

define internal ptr @v__df_andThenIO_80(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 228 to ptr
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
  %t14 = call ptr @v__lam_26(ptr %t13)
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

define internal ptr @v__df_andThenIO_84(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 230 to ptr
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
  %t14 = call ptr @v__lam_27(ptr %t13)
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
  %t40 = inttoptr i64 231 to ptr
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
  %t43 = inttoptr i64 231 to ptr
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

define internal ptr @v__df_andThenIO_88(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 232 to ptr
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
  %t14 = call ptr @v__lam_28(ptr %t13)
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
  %t40 = inttoptr i64 233 to ptr
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
  %t43 = inttoptr i64 233 to ptr
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

define internal ptr @v__df_andThenIO_92(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 234 to ptr
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
  %t14 = call ptr @v__lam_29(ptr %t13)
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
  %t40 = inttoptr i64 235 to ptr
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
  %t43 = inttoptr i64 235 to ptr
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

define internal ptr @v__scc__apply1__df__lam_10_39__df__lam_14_1__df__lam_14_13__df__lam_14_17__df__lam_14_21__df__lam_14_29__df__lam_14_41__df__lam_14_45__df__lam_14_5__df__lam_14_9__df__lam_15_10__df__lam_15_14__df__lam_15_18__df__lam_15_2__df__lam_15_22__df__lam_15_30__df__lam_15_42__df__lam_15_46__df__lam_15_6__df__lam_16_11__df__lam_16_15__df__lam_16_19__df__lam_16_23__df__lam_16_3__df__lam_16_31__df__lam_16_43__df__lam_16_47__df__lam_16_7__df__lam_34_49__df__lam_35_50__df__lam_36_51__df__lam_5_25__df__lam_5_33__df__lam_5_53__df__lam_5_57__df__lam_5_61__df__lam_5_65__df__lam_5_69__df__lam_5_73__df__lam_5_77__df__lam_5_81__df__lam_5_85__df__lam_5_89__df__lam_5_93__df__lam_6_26__df__lam_6_34__df__lam_6_54__df__lam_6_58__df__lam_6_62__df__lam_6_66__df__lam_6_70__df__lam_6_74__df__lam_6_78__df__lam_6_82__df__lam_6_86__df__lam_6_90__df__lam_6_94__df__lam_7_27__df__lam_7_35__df__lam_7_55__df__lam_7_59__df__lam_7_63__df__lam_7_67__df__lam_7_71__df__lam_7_75__df__lam_7_79__df__lam_7_83__df__lam_7_87__df__lam_7_91__df__lam_7_95__df__lam_8_37__df__lam_9_38__lift_2__lift_3__lift_31__lift_32__lift_33__lift_4(ptr %v__args) {
  call void @__inc_ref(ptr %v__args)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 236 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__scc__apply1__df__lam_10_39__df__lam_14_1__df__lam_14_13__df__lam_14_17__df__lam_14_21__df__lam_14_29__df__lam_14_41__df__lam_14_45__df__lam_14_5__df__lam_14_9__df__lam_15_10__df__lam_15_14__df__lam_15_18__df__lam_15_2__df__lam_15_22__df__lam_15_30__df__lam_15_42__df__lam_15_46__df__lam_15_6__df__lam_16_11__df__lam_16_15__df__lam_16_19__df__lam_16_23__df__lam_16_3__df__lam_16_31__df__lam_16_43__df__lam_16_47__df__lam_16_7__df__lam_34_49__df__lam_35_50__df__lam_36_51__df__lam_5_25__df__lam_5_33__df__lam_5_53__df__lam_5_57__df__lam_5_61__df__lam_5_65__df__lam_5_69__df__lam_5_73__df__lam_5_77__df__lam_5_81__df__lam_5_85__df__lam_5_89__df__lam_5_93__df__lam_6_26__df__lam_6_34__df__lam_6_54__df__lam_6_58__df__lam_6_62__df__lam_6_66__df__lam_6_70__df__lam_6_74__df__lam_6_78__df__lam_6_82__df__lam_6_86__df__lam_6_90__df__lam_6_94__df__lam_7_27__df__lam_7_35__df__lam_7_55__df__lam_7_59__df__lam_7_63__df__lam_7_67__df__lam_7_71__df__lam_7_75__df__lam_7_79__df__lam_7_83__df__lam_7_87__df__lam_7_91__df__lam_7_95__df__lam_8_37__df__lam_9_38__lift_2__lift_3__lift_31__lift_32__lift_33__lift_4(ptr %v__args, ptr %t0)
  call void @__free_recursive(ptr %v__args)
  ret ptr %t3
}

define internal ptr @v__cps__scc__apply1__df__lam_10_39__df__lam_14_1__df__lam_14_13__df__lam_14_17__df__lam_14_21__df__lam_14_29__df__lam_14_41__df__lam_14_45__df__lam_14_5__df__lam_14_9__df__lam_15_10__df__lam_15_14__df__lam_15_18__df__lam_15_2__df__lam_15_22__df__lam_15_30__df__lam_15_42__df__lam_15_46__df__lam_15_6__df__lam_16_11__df__lam_16_15__df__lam_16_19__df__lam_16_23__df__lam_16_3__df__lam_16_31__df__lam_16_43__df__lam_16_47__df__lam_16_7__df__lam_34_49__df__lam_35_50__df__lam_36_51__df__lam_5_25__df__lam_5_33__df__lam_5_53__df__lam_5_57__df__lam_5_61__df__lam_5_65__df__lam_5_69__df__lam_5_73__df__lam_5_77__df__lam_5_81__df__lam_5_85__df__lam_5_89__df__lam_5_93__df__lam_6_26__df__lam_6_34__df__lam_6_54__df__lam_6_58__df__lam_6_62__df__lam_6_66__df__lam_6_70__df__lam_6_74__df__lam_6_78__df__lam_6_82__df__lam_6_86__df__lam_6_90__df__lam_6_94__df__lam_7_27__df__lam_7_35__df__lam_7_55__df__lam_7_59__df__lam_7_63__df__lam_7_67__df__lam_7_71__df__lam_7_75__df__lam_7_79__df__lam_7_83__df__lam_7_87__df__lam_7_91__df__lam_7_95__df__lam_8_37__df__lam_9_38__lift_2__lift_3__lift_31__lift_32__lift_33__lift_4(ptr %v__args, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 105, label %tco.case.arm.105.11 i64 106, label %tco.case.arm.106.1553 i64 107, label %tco.case.arm.107.1576 i64 108, label %tco.case.arm.108.1599 i64 109, label %tco.case.arm.109.1622 i64 110, label %tco.case.arm.110.1645 i64 111, label %tco.case.arm.111.1668 i64 112, label %tco.case.arm.112.1691 i64 113, label %tco.case.arm.113.1714 i64 114, label %tco.case.arm.114.1737 i64 115, label %tco.case.arm.115.1760 i64 116, label %tco.case.arm.116.1783 i64 117, label %tco.case.arm.117.1806 i64 118, label %tco.case.arm.118.1829 i64 119, label %tco.case.arm.119.1852 i64 120, label %tco.case.arm.120.1875 i64 121, label %tco.case.arm.121.1898 i64 122, label %tco.case.arm.122.1921 i64 123, label %tco.case.arm.123.1944 i64 124, label %tco.case.arm.124.1967 i64 125, label %tco.case.arm.125.1990 i64 126, label %tco.case.arm.126.2013 i64 127, label %tco.case.arm.127.2036 i64 128, label %tco.case.arm.128.2059 i64 129, label %tco.case.arm.129.2082 i64 130, label %tco.case.arm.130.2105 i64 131, label %tco.case.arm.131.2128 i64 132, label %tco.case.arm.132.2151 i64 133, label %tco.case.arm.133.2174 i64 134, label %tco.case.arm.134.2197 i64 135, label %tco.case.arm.135.2220 i64 136, label %tco.case.arm.136.2243 i64 137, label %tco.case.arm.137.2266 i64 138, label %tco.case.arm.138.2289 i64 139, label %tco.case.arm.139.2312 i64 140, label %tco.case.arm.140.2335 i64 141, label %tco.case.arm.141.2352 i64 142, label %tco.case.arm.142.2375 i64 143, label %tco.case.arm.143.2398 i64 144, label %tco.case.arm.144.2421 i64 145, label %tco.case.arm.145.2444 i64 146, label %tco.case.arm.146.2467 i64 147, label %tco.case.arm.147.2490 i64 148, label %tco.case.arm.148.2513 i64 149, label %tco.case.arm.149.2536 i64 150, label %tco.case.arm.150.2559 i64 151, label %tco.case.arm.151.2582 i64 152, label %tco.case.arm.152.2605 i64 153, label %tco.case.arm.153.2628 i64 154, label %tco.case.arm.154.2645 i64 155, label %tco.case.arm.155.2668 i64 156, label %tco.case.arm.156.2691 i64 157, label %tco.case.arm.157.2714 i64 158, label %tco.case.arm.158.2737 i64 159, label %tco.case.arm.159.2760 i64 160, label %tco.case.arm.160.2783 i64 161, label %tco.case.arm.161.2806 i64 162, label %tco.case.arm.162.2829 i64 163, label %tco.case.arm.163.2852 i64 164, label %tco.case.arm.164.2875 i64 165, label %tco.case.arm.165.2898 i64 166, label %tco.case.arm.166.2921 i64 167, label %tco.case.arm.167.2938 i64 168, label %tco.case.arm.168.2961 i64 169, label %tco.case.arm.169.2984 i64 170, label %tco.case.arm.170.3007 i64 171, label %tco.case.arm.171.3030 i64 172, label %tco.case.arm.172.3053 i64 173, label %tco.case.arm.173.3076 i64 174, label %tco.case.arm.174.3099 i64 175, label %tco.case.arm.175.3122 i64 176, label %tco.case.arm.176.3145 i64 177, label %tco.case.arm.177.3168 i64 178, label %tco.case.arm.178.3191 i64 179, label %tco.case.arm.179.3214 i64 180, label %tco.case.arm.180.3237 i64 181, label %tco.case.arm.181.3260 i64 182, label %tco.case.arm.182.3283 i64 183, label %tco.case.arm.183.3306 ]
tco.case.arm.105.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t5, i32 2
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  %t16 = getelementptr ptr, ptr %t13, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %tco.case.default.19 [ i64 27, label %tco.case.arm.27.20 i64 28, label %tco.case.arm.28.40 i64 29, label %tco.case.arm.29.60 i64 30, label %tco.case.arm.30.80 i64 31, label %tco.case.arm.31.100 i64 32, label %tco.case.arm.32.120 i64 33, label %tco.case.arm.33.140 i64 34, label %tco.case.arm.34.160 i64 35, label %tco.case.arm.35.180 i64 36, label %tco.case.arm.36.200 i64 37, label %tco.case.arm.37.220 i64 38, label %tco.case.arm.38.240 i64 39, label %tco.case.arm.39.260 i64 40, label %tco.case.arm.40.280 i64 41, label %tco.case.arm.41.300 i64 42, label %tco.case.arm.42.320 i64 43, label %tco.case.arm.43.340 i64 44, label %tco.case.arm.44.360 i64 45, label %tco.case.arm.45.380 i64 46, label %tco.case.arm.46.400 i64 47, label %tco.case.arm.47.420 i64 48, label %tco.case.arm.48.440 i64 49, label %tco.case.arm.49.460 i64 50, label %tco.case.arm.50.480 i64 51, label %tco.case.arm.51.500 i64 52, label %tco.case.arm.52.520 i64 53, label %tco.case.arm.53.540 i64 54, label %tco.case.arm.54.560 i64 55, label %tco.case.arm.55.580 i64 56, label %tco.case.arm.56.600 i64 57, label %tco.case.arm.57.620 i64 58, label %tco.case.arm.58.640 i64 59, label %tco.case.arm.59.660 i64 60, label %tco.case.arm.60.680 i64 61, label %tco.case.arm.61.700 i64 62, label %tco.case.arm.62.711 i64 63, label %tco.case.arm.63.731 i64 64, label %tco.case.arm.64.751 i64 65, label %tco.case.arm.65.771 i64 66, label %tco.case.arm.66.791 i64 67, label %tco.case.arm.67.811 i64 68, label %tco.case.arm.68.831 i64 69, label %tco.case.arm.69.851 i64 70, label %tco.case.arm.70.871 i64 71, label %tco.case.arm.71.891 i64 72, label %tco.case.arm.72.911 i64 73, label %tco.case.arm.73.931 i64 74, label %tco.case.arm.74.951 i64 75, label %tco.case.arm.75.962 i64 76, label %tco.case.arm.76.982 i64 77, label %tco.case.arm.77.1002 i64 78, label %tco.case.arm.78.1022 i64 79, label %tco.case.arm.79.1042 i64 80, label %tco.case.arm.80.1062 i64 81, label %tco.case.arm.81.1082 i64 82, label %tco.case.arm.82.1102 i64 83, label %tco.case.arm.83.1122 i64 84, label %tco.case.arm.84.1142 i64 85, label %tco.case.arm.85.1162 i64 86, label %tco.case.arm.86.1182 i64 87, label %tco.case.arm.87.1202 i64 88, label %tco.case.arm.88.1213 i64 89, label %tco.case.arm.89.1233 i64 90, label %tco.case.arm.90.1253 i64 91, label %tco.case.arm.91.1273 i64 92, label %tco.case.arm.92.1293 i64 93, label %tco.case.arm.93.1313 i64 94, label %tco.case.arm.94.1333 i64 95, label %tco.case.arm.95.1353 i64 96, label %tco.case.arm.96.1373 i64 97, label %tco.case.arm.97.1393 i64 98, label %tco.case.arm.98.1413 i64 99, label %tco.case.arm.99.1433 i64 100, label %tco.case.arm.100.1453 i64 101, label %tco.case.arm.101.1473 i64 102, label %tco.case.arm.102.1493 i64 103, label %tco.case.arm.103.1513 i64 104, label %tco.case.arm.104.1533 ]
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
  %t32 = inttoptr i64 106 to ptr
  %t33 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t32, ptr %t33
  call void @__inc_ref(ptr %t22)
  %t31 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t22, ptr %t31
  br label %reuse.join.28
reuse.copy.27:
  %t34 = call ptr @__alloc(i64 24, i32 2)
  %t35 = inttoptr i64 106 to ptr
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
  %t52 = inttoptr i64 107 to ptr
  %t53 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t52, ptr %t53
  call void @__inc_ref(ptr %t42)
  %t51 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t42, ptr %t51
  br label %reuse.join.48
reuse.copy.47:
  %t54 = call ptr @__alloc(i64 24, i32 2)
  %t55 = inttoptr i64 107 to ptr
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
  %t72 = inttoptr i64 108 to ptr
  %t73 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t72, ptr %t73
  call void @__inc_ref(ptr %t62)
  %t71 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t62, ptr %t71
  br label %reuse.join.68
reuse.copy.67:
  %t74 = call ptr @__alloc(i64 24, i32 2)
  %t75 = inttoptr i64 108 to ptr
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
  %t92 = inttoptr i64 109 to ptr
  %t93 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t92, ptr %t93
  call void @__inc_ref(ptr %t82)
  %t91 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t82, ptr %t91
  br label %reuse.join.88
reuse.copy.87:
  %t94 = call ptr @__alloc(i64 24, i32 2)
  %t95 = inttoptr i64 109 to ptr
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
  %t112 = inttoptr i64 110 to ptr
  %t113 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t112, ptr %t113
  call void @__inc_ref(ptr %t102)
  %t111 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t102, ptr %t111
  br label %reuse.join.108
reuse.copy.107:
  %t114 = call ptr @__alloc(i64 24, i32 2)
  %t115 = inttoptr i64 110 to ptr
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
  %t132 = inttoptr i64 111 to ptr
  %t133 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t132, ptr %t133
  call void @__inc_ref(ptr %t122)
  %t131 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t122, ptr %t131
  br label %reuse.join.128
reuse.copy.127:
  %t134 = call ptr @__alloc(i64 24, i32 2)
  %t135 = inttoptr i64 111 to ptr
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
  %t152 = inttoptr i64 112 to ptr
  %t153 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t152, ptr %t153
  call void @__inc_ref(ptr %t142)
  %t151 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t142, ptr %t151
  br label %reuse.join.148
reuse.copy.147:
  %t154 = call ptr @__alloc(i64 24, i32 2)
  %t155 = inttoptr i64 112 to ptr
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
  %t172 = inttoptr i64 113 to ptr
  %t173 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t172, ptr %t173
  call void @__inc_ref(ptr %t162)
  %t171 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t162, ptr %t171
  br label %reuse.join.168
reuse.copy.167:
  %t174 = call ptr @__alloc(i64 24, i32 2)
  %t175 = inttoptr i64 113 to ptr
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
  %t192 = inttoptr i64 114 to ptr
  %t193 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t192, ptr %t193
  call void @__inc_ref(ptr %t182)
  %t191 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t182, ptr %t191
  br label %reuse.join.188
reuse.copy.187:
  %t194 = call ptr @__alloc(i64 24, i32 2)
  %t195 = inttoptr i64 114 to ptr
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
  %t212 = inttoptr i64 115 to ptr
  %t213 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t212, ptr %t213
  call void @__inc_ref(ptr %t202)
  %t211 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t202, ptr %t211
  br label %reuse.join.208
reuse.copy.207:
  %t214 = call ptr @__alloc(i64 24, i32 2)
  %t215 = inttoptr i64 115 to ptr
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
  %t232 = inttoptr i64 116 to ptr
  %t233 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t232, ptr %t233
  call void @__inc_ref(ptr %t222)
  %t231 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t222, ptr %t231
  br label %reuse.join.228
reuse.copy.227:
  %t234 = call ptr @__alloc(i64 24, i32 2)
  %t235 = inttoptr i64 116 to ptr
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
  %t252 = inttoptr i64 117 to ptr
  %t253 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t252, ptr %t253
  call void @__inc_ref(ptr %t242)
  %t251 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t242, ptr %t251
  br label %reuse.join.248
reuse.copy.247:
  %t254 = call ptr @__alloc(i64 24, i32 2)
  %t255 = inttoptr i64 117 to ptr
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
  %t272 = inttoptr i64 118 to ptr
  %t273 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t272, ptr %t273
  call void @__inc_ref(ptr %t262)
  %t271 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t262, ptr %t271
  br label %reuse.join.268
reuse.copy.267:
  %t274 = call ptr @__alloc(i64 24, i32 2)
  %t275 = inttoptr i64 118 to ptr
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
  %t292 = inttoptr i64 119 to ptr
  %t293 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t292, ptr %t293
  call void @__inc_ref(ptr %t282)
  %t291 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t282, ptr %t291
  br label %reuse.join.288
reuse.copy.287:
  %t294 = call ptr @__alloc(i64 24, i32 2)
  %t295 = inttoptr i64 119 to ptr
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
  %t312 = inttoptr i64 120 to ptr
  %t313 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t312, ptr %t313
  call void @__inc_ref(ptr %t302)
  %t311 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t302, ptr %t311
  br label %reuse.join.308
reuse.copy.307:
  %t314 = call ptr @__alloc(i64 24, i32 2)
  %t315 = inttoptr i64 120 to ptr
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
  %t332 = inttoptr i64 121 to ptr
  %t333 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t332, ptr %t333
  call void @__inc_ref(ptr %t322)
  %t331 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t322, ptr %t331
  br label %reuse.join.328
reuse.copy.327:
  %t334 = call ptr @__alloc(i64 24, i32 2)
  %t335 = inttoptr i64 121 to ptr
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
  %t352 = inttoptr i64 122 to ptr
  %t353 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t352, ptr %t353
  call void @__inc_ref(ptr %t342)
  %t351 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t342, ptr %t351
  br label %reuse.join.348
reuse.copy.347:
  %t354 = call ptr @__alloc(i64 24, i32 2)
  %t355 = inttoptr i64 122 to ptr
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
  %t372 = inttoptr i64 123 to ptr
  %t373 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t372, ptr %t373
  call void @__inc_ref(ptr %t362)
  %t371 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t362, ptr %t371
  br label %reuse.join.368
reuse.copy.367:
  %t374 = call ptr @__alloc(i64 24, i32 2)
  %t375 = inttoptr i64 123 to ptr
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
  %t392 = inttoptr i64 124 to ptr
  %t393 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t392, ptr %t393
  call void @__inc_ref(ptr %t382)
  %t391 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t382, ptr %t391
  br label %reuse.join.388
reuse.copy.387:
  %t394 = call ptr @__alloc(i64 24, i32 2)
  %t395 = inttoptr i64 124 to ptr
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
  %t412 = inttoptr i64 125 to ptr
  %t413 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t412, ptr %t413
  call void @__inc_ref(ptr %t402)
  %t411 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t402, ptr %t411
  br label %reuse.join.408
reuse.copy.407:
  %t414 = call ptr @__alloc(i64 24, i32 2)
  %t415 = inttoptr i64 125 to ptr
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
  %t432 = inttoptr i64 126 to ptr
  %t433 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t432, ptr %t433
  call void @__inc_ref(ptr %t422)
  %t431 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t422, ptr %t431
  br label %reuse.join.428
reuse.copy.427:
  %t434 = call ptr @__alloc(i64 24, i32 2)
  %t435 = inttoptr i64 126 to ptr
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
  %t452 = inttoptr i64 127 to ptr
  %t453 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t452, ptr %t453
  call void @__inc_ref(ptr %t442)
  %t451 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t442, ptr %t451
  br label %reuse.join.448
reuse.copy.447:
  %t454 = call ptr @__alloc(i64 24, i32 2)
  %t455 = inttoptr i64 127 to ptr
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
  %t472 = inttoptr i64 128 to ptr
  %t473 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t472, ptr %t473
  call void @__inc_ref(ptr %t462)
  %t471 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t462, ptr %t471
  br label %reuse.join.468
reuse.copy.467:
  %t474 = call ptr @__alloc(i64 24, i32 2)
  %t475 = inttoptr i64 128 to ptr
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
  %t492 = inttoptr i64 129 to ptr
  %t493 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t492, ptr %t493
  call void @__inc_ref(ptr %t482)
  %t491 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t482, ptr %t491
  br label %reuse.join.488
reuse.copy.487:
  %t494 = call ptr @__alloc(i64 24, i32 2)
  %t495 = inttoptr i64 129 to ptr
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
  %t512 = inttoptr i64 130 to ptr
  %t513 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t512, ptr %t513
  call void @__inc_ref(ptr %t502)
  %t511 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t502, ptr %t511
  br label %reuse.join.508
reuse.copy.507:
  %t514 = call ptr @__alloc(i64 24, i32 2)
  %t515 = inttoptr i64 130 to ptr
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
  %t532 = inttoptr i64 131 to ptr
  %t533 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t532, ptr %t533
  call void @__inc_ref(ptr %t522)
  %t531 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t522, ptr %t531
  br label %reuse.join.528
reuse.copy.527:
  %t534 = call ptr @__alloc(i64 24, i32 2)
  %t535 = inttoptr i64 131 to ptr
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
  %t552 = inttoptr i64 132 to ptr
  %t553 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t552, ptr %t553
  call void @__inc_ref(ptr %t542)
  %t551 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t542, ptr %t551
  br label %reuse.join.548
reuse.copy.547:
  %t554 = call ptr @__alloc(i64 24, i32 2)
  %t555 = inttoptr i64 132 to ptr
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
  %t572 = inttoptr i64 133 to ptr
  %t573 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t572, ptr %t573
  call void @__inc_ref(ptr %t562)
  %t571 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t562, ptr %t571
  br label %reuse.join.568
reuse.copy.567:
  %t574 = call ptr @__alloc(i64 24, i32 2)
  %t575 = inttoptr i64 133 to ptr
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
  %t592 = inttoptr i64 134 to ptr
  %t593 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t592, ptr %t593
  call void @__inc_ref(ptr %t582)
  %t591 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t582, ptr %t591
  br label %reuse.join.588
reuse.copy.587:
  %t594 = call ptr @__alloc(i64 24, i32 2)
  %t595 = inttoptr i64 134 to ptr
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
  %t612 = inttoptr i64 135 to ptr
  %t613 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t612, ptr %t613
  call void @__inc_ref(ptr %t602)
  %t611 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t602, ptr %t611
  br label %reuse.join.608
reuse.copy.607:
  %t614 = call ptr @__alloc(i64 24, i32 2)
  %t615 = inttoptr i64 135 to ptr
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
  %t632 = inttoptr i64 136 to ptr
  %t633 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t632, ptr %t633
  call void @__inc_ref(ptr %t622)
  %t631 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t622, ptr %t631
  br label %reuse.join.628
reuse.copy.627:
  %t634 = call ptr @__alloc(i64 24, i32 2)
  %t635 = inttoptr i64 136 to ptr
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
  %t652 = inttoptr i64 137 to ptr
  %t653 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t652, ptr %t653
  call void @__inc_ref(ptr %t642)
  %t651 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t642, ptr %t651
  br label %reuse.join.648
reuse.copy.647:
  %t654 = call ptr @__alloc(i64 24, i32 2)
  %t655 = inttoptr i64 137 to ptr
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
  %t672 = inttoptr i64 138 to ptr
  %t673 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t672, ptr %t673
  call void @__inc_ref(ptr %t662)
  %t671 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t662, ptr %t671
  br label %reuse.join.668
reuse.copy.667:
  %t674 = call ptr @__alloc(i64 24, i32 2)
  %t675 = inttoptr i64 138 to ptr
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
  %t692 = inttoptr i64 139 to ptr
  %t693 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t692, ptr %t693
  call void @__inc_ref(ptr %t682)
  %t691 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t682, ptr %t691
  br label %reuse.join.688
reuse.copy.687:
  %t694 = call ptr @__alloc(i64 24, i32 2)
  %t695 = inttoptr i64 139 to ptr
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
  %t706 = inttoptr i64 140 to ptr
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
  %t723 = inttoptr i64 141 to ptr
  %t724 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t723, ptr %t724
  call void @__inc_ref(ptr %t713)
  %t722 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t713, ptr %t722
  br label %reuse.join.719
reuse.copy.718:
  %t725 = call ptr @__alloc(i64 24, i32 2)
  %t726 = inttoptr i64 141 to ptr
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
  %t743 = inttoptr i64 142 to ptr
  %t744 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t743, ptr %t744
  call void @__inc_ref(ptr %t733)
  %t742 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t733, ptr %t742
  br label %reuse.join.739
reuse.copy.738:
  %t745 = call ptr @__alloc(i64 24, i32 2)
  %t746 = inttoptr i64 142 to ptr
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
  %t763 = inttoptr i64 143 to ptr
  %t764 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t763, ptr %t764
  call void @__inc_ref(ptr %t753)
  %t762 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t753, ptr %t762
  br label %reuse.join.759
reuse.copy.758:
  %t765 = call ptr @__alloc(i64 24, i32 2)
  %t766 = inttoptr i64 143 to ptr
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
  %t783 = inttoptr i64 144 to ptr
  %t784 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t783, ptr %t784
  call void @__inc_ref(ptr %t773)
  %t782 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t773, ptr %t782
  br label %reuse.join.779
reuse.copy.778:
  %t785 = call ptr @__alloc(i64 24, i32 2)
  %t786 = inttoptr i64 144 to ptr
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
  %t803 = inttoptr i64 145 to ptr
  %t804 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t803, ptr %t804
  call void @__inc_ref(ptr %t793)
  %t802 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t793, ptr %t802
  br label %reuse.join.799
reuse.copy.798:
  %t805 = call ptr @__alloc(i64 24, i32 2)
  %t806 = inttoptr i64 145 to ptr
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
  %t823 = inttoptr i64 146 to ptr
  %t824 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t823, ptr %t824
  call void @__inc_ref(ptr %t813)
  %t822 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t813, ptr %t822
  br label %reuse.join.819
reuse.copy.818:
  %t825 = call ptr @__alloc(i64 24, i32 2)
  %t826 = inttoptr i64 146 to ptr
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
  %t843 = inttoptr i64 147 to ptr
  %t844 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t843, ptr %t844
  call void @__inc_ref(ptr %t833)
  %t842 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t833, ptr %t842
  br label %reuse.join.839
reuse.copy.838:
  %t845 = call ptr @__alloc(i64 24, i32 2)
  %t846 = inttoptr i64 147 to ptr
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
  %t863 = inttoptr i64 148 to ptr
  %t864 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t863, ptr %t864
  call void @__inc_ref(ptr %t853)
  %t862 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t853, ptr %t862
  br label %reuse.join.859
reuse.copy.858:
  %t865 = call ptr @__alloc(i64 24, i32 2)
  %t866 = inttoptr i64 148 to ptr
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
  %t883 = inttoptr i64 149 to ptr
  %t884 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t883, ptr %t884
  call void @__inc_ref(ptr %t873)
  %t882 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t873, ptr %t882
  br label %reuse.join.879
reuse.copy.878:
  %t885 = call ptr @__alloc(i64 24, i32 2)
  %t886 = inttoptr i64 149 to ptr
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
  %t903 = inttoptr i64 150 to ptr
  %t904 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t903, ptr %t904
  call void @__inc_ref(ptr %t893)
  %t902 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t893, ptr %t902
  br label %reuse.join.899
reuse.copy.898:
  %t905 = call ptr @__alloc(i64 24, i32 2)
  %t906 = inttoptr i64 150 to ptr
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
  %t923 = inttoptr i64 151 to ptr
  %t924 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t923, ptr %t924
  call void @__inc_ref(ptr %t913)
  %t922 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t913, ptr %t922
  br label %reuse.join.919
reuse.copy.918:
  %t925 = call ptr @__alloc(i64 24, i32 2)
  %t926 = inttoptr i64 151 to ptr
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
  %t943 = inttoptr i64 152 to ptr
  %t944 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t943, ptr %t944
  call void @__inc_ref(ptr %t933)
  %t942 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t933, ptr %t942
  br label %reuse.join.939
reuse.copy.938:
  %t945 = call ptr @__alloc(i64 24, i32 2)
  %t946 = inttoptr i64 152 to ptr
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
  %t957 = inttoptr i64 153 to ptr
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
  %t974 = inttoptr i64 154 to ptr
  %t975 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t974, ptr %t975
  call void @__inc_ref(ptr %t964)
  %t973 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t964, ptr %t973
  br label %reuse.join.970
reuse.copy.969:
  %t976 = call ptr @__alloc(i64 24, i32 2)
  %t977 = inttoptr i64 154 to ptr
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
  %t994 = inttoptr i64 155 to ptr
  %t995 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t994, ptr %t995
  call void @__inc_ref(ptr %t984)
  %t993 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t984, ptr %t993
  br label %reuse.join.990
reuse.copy.989:
  %t996 = call ptr @__alloc(i64 24, i32 2)
  %t997 = inttoptr i64 155 to ptr
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
  %t1014 = inttoptr i64 156 to ptr
  %t1015 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1014, ptr %t1015
  call void @__inc_ref(ptr %t1004)
  %t1013 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1004, ptr %t1013
  br label %reuse.join.1010
reuse.copy.1009:
  %t1016 = call ptr @__alloc(i64 24, i32 2)
  %t1017 = inttoptr i64 156 to ptr
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
  %t1034 = inttoptr i64 157 to ptr
  %t1035 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1034, ptr %t1035
  call void @__inc_ref(ptr %t1024)
  %t1033 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1024, ptr %t1033
  br label %reuse.join.1030
reuse.copy.1029:
  %t1036 = call ptr @__alloc(i64 24, i32 2)
  %t1037 = inttoptr i64 157 to ptr
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
  %t1054 = inttoptr i64 158 to ptr
  %t1055 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1054, ptr %t1055
  call void @__inc_ref(ptr %t1044)
  %t1053 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1044, ptr %t1053
  br label %reuse.join.1050
reuse.copy.1049:
  %t1056 = call ptr @__alloc(i64 24, i32 2)
  %t1057 = inttoptr i64 158 to ptr
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
  %t1074 = inttoptr i64 159 to ptr
  %t1075 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1074, ptr %t1075
  call void @__inc_ref(ptr %t1064)
  %t1073 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1064, ptr %t1073
  br label %reuse.join.1070
reuse.copy.1069:
  %t1076 = call ptr @__alloc(i64 24, i32 2)
  %t1077 = inttoptr i64 159 to ptr
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
  %t1094 = inttoptr i64 160 to ptr
  %t1095 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1094, ptr %t1095
  call void @__inc_ref(ptr %t1084)
  %t1093 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1084, ptr %t1093
  br label %reuse.join.1090
reuse.copy.1089:
  %t1096 = call ptr @__alloc(i64 24, i32 2)
  %t1097 = inttoptr i64 160 to ptr
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
  %t1114 = inttoptr i64 161 to ptr
  %t1115 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1114, ptr %t1115
  call void @__inc_ref(ptr %t1104)
  %t1113 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1104, ptr %t1113
  br label %reuse.join.1110
reuse.copy.1109:
  %t1116 = call ptr @__alloc(i64 24, i32 2)
  %t1117 = inttoptr i64 161 to ptr
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
  %t1134 = inttoptr i64 162 to ptr
  %t1135 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1134, ptr %t1135
  call void @__inc_ref(ptr %t1124)
  %t1133 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1124, ptr %t1133
  br label %reuse.join.1130
reuse.copy.1129:
  %t1136 = call ptr @__alloc(i64 24, i32 2)
  %t1137 = inttoptr i64 162 to ptr
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
  %t1154 = inttoptr i64 163 to ptr
  %t1155 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1154, ptr %t1155
  call void @__inc_ref(ptr %t1144)
  %t1153 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1144, ptr %t1153
  br label %reuse.join.1150
reuse.copy.1149:
  %t1156 = call ptr @__alloc(i64 24, i32 2)
  %t1157 = inttoptr i64 163 to ptr
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
  %t1174 = inttoptr i64 164 to ptr
  %t1175 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1174, ptr %t1175
  call void @__inc_ref(ptr %t1164)
  %t1173 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1164, ptr %t1173
  br label %reuse.join.1170
reuse.copy.1169:
  %t1176 = call ptr @__alloc(i64 24, i32 2)
  %t1177 = inttoptr i64 164 to ptr
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
  %t1194 = inttoptr i64 165 to ptr
  %t1195 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1194, ptr %t1195
  call void @__inc_ref(ptr %t1184)
  %t1193 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1184, ptr %t1193
  br label %reuse.join.1190
reuse.copy.1189:
  %t1196 = call ptr @__alloc(i64 24, i32 2)
  %t1197 = inttoptr i64 165 to ptr
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
  %t1208 = inttoptr i64 166 to ptr
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
  %t1225 = inttoptr i64 167 to ptr
  %t1226 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1225, ptr %t1226
  call void @__inc_ref(ptr %t1215)
  %t1224 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1215, ptr %t1224
  br label %reuse.join.1221
reuse.copy.1220:
  %t1227 = call ptr @__alloc(i64 24, i32 2)
  %t1228 = inttoptr i64 167 to ptr
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
  %t1245 = inttoptr i64 168 to ptr
  %t1246 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1245, ptr %t1246
  call void @__inc_ref(ptr %t1235)
  %t1244 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1235, ptr %t1244
  br label %reuse.join.1241
reuse.copy.1240:
  %t1247 = call ptr @__alloc(i64 24, i32 2)
  %t1248 = inttoptr i64 168 to ptr
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
  %t1265 = inttoptr i64 169 to ptr
  %t1266 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1265, ptr %t1266
  call void @__inc_ref(ptr %t1255)
  %t1264 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1255, ptr %t1264
  br label %reuse.join.1261
reuse.copy.1260:
  %t1267 = call ptr @__alloc(i64 24, i32 2)
  %t1268 = inttoptr i64 169 to ptr
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
  %t1285 = inttoptr i64 170 to ptr
  %t1286 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1285, ptr %t1286
  call void @__inc_ref(ptr %t1275)
  %t1284 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1275, ptr %t1284
  br label %reuse.join.1281
reuse.copy.1280:
  %t1287 = call ptr @__alloc(i64 24, i32 2)
  %t1288 = inttoptr i64 170 to ptr
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
  %t1305 = inttoptr i64 171 to ptr
  %t1306 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1305, ptr %t1306
  call void @__inc_ref(ptr %t1295)
  %t1304 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1295, ptr %t1304
  br label %reuse.join.1301
reuse.copy.1300:
  %t1307 = call ptr @__alloc(i64 24, i32 2)
  %t1308 = inttoptr i64 171 to ptr
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
  %t1325 = inttoptr i64 172 to ptr
  %t1326 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1325, ptr %t1326
  call void @__inc_ref(ptr %t1315)
  %t1324 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1315, ptr %t1324
  br label %reuse.join.1321
reuse.copy.1320:
  %t1327 = call ptr @__alloc(i64 24, i32 2)
  %t1328 = inttoptr i64 172 to ptr
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
  %t1345 = inttoptr i64 173 to ptr
  %t1346 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1345, ptr %t1346
  call void @__inc_ref(ptr %t1335)
  %t1344 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1335, ptr %t1344
  br label %reuse.join.1341
reuse.copy.1340:
  %t1347 = call ptr @__alloc(i64 24, i32 2)
  %t1348 = inttoptr i64 173 to ptr
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
  %t1365 = inttoptr i64 174 to ptr
  %t1366 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1365, ptr %t1366
  call void @__inc_ref(ptr %t1355)
  %t1364 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1355, ptr %t1364
  br label %reuse.join.1361
reuse.copy.1360:
  %t1367 = call ptr @__alloc(i64 24, i32 2)
  %t1368 = inttoptr i64 174 to ptr
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
  %t1385 = inttoptr i64 175 to ptr
  %t1386 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1385, ptr %t1386
  call void @__inc_ref(ptr %t1375)
  %t1384 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1375, ptr %t1384
  br label %reuse.join.1381
reuse.copy.1380:
  %t1387 = call ptr @__alloc(i64 24, i32 2)
  %t1388 = inttoptr i64 175 to ptr
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
  %t1405 = inttoptr i64 176 to ptr
  %t1406 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1405, ptr %t1406
  call void @__inc_ref(ptr %t1395)
  %t1404 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1395, ptr %t1404
  br label %reuse.join.1401
reuse.copy.1400:
  %t1407 = call ptr @__alloc(i64 24, i32 2)
  %t1408 = inttoptr i64 176 to ptr
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
  %t1425 = inttoptr i64 177 to ptr
  %t1426 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1425, ptr %t1426
  call void @__inc_ref(ptr %t1415)
  %t1424 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1415, ptr %t1424
  br label %reuse.join.1421
reuse.copy.1420:
  %t1427 = call ptr @__alloc(i64 24, i32 2)
  %t1428 = inttoptr i64 177 to ptr
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
  %t1445 = inttoptr i64 178 to ptr
  %t1446 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1445, ptr %t1446
  call void @__inc_ref(ptr %t1435)
  %t1444 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1435, ptr %t1444
  br label %reuse.join.1441
reuse.copy.1440:
  %t1447 = call ptr @__alloc(i64 24, i32 2)
  %t1448 = inttoptr i64 178 to ptr
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
  %t1465 = inttoptr i64 179 to ptr
  %t1466 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1465, ptr %t1466
  call void @__inc_ref(ptr %t1455)
  %t1464 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1455, ptr %t1464
  br label %reuse.join.1461
reuse.copy.1460:
  %t1467 = call ptr @__alloc(i64 24, i32 2)
  %t1468 = inttoptr i64 179 to ptr
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
  %t1485 = inttoptr i64 180 to ptr
  %t1486 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1485, ptr %t1486
  call void @__inc_ref(ptr %t1475)
  %t1484 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1475, ptr %t1484
  br label %reuse.join.1481
reuse.copy.1480:
  %t1487 = call ptr @__alloc(i64 24, i32 2)
  %t1488 = inttoptr i64 180 to ptr
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
  %t1505 = inttoptr i64 181 to ptr
  %t1506 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1505, ptr %t1506
  call void @__inc_ref(ptr %t1495)
  %t1504 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1495, ptr %t1504
  br label %reuse.join.1501
reuse.copy.1500:
  %t1507 = call ptr @__alloc(i64 24, i32 2)
  %t1508 = inttoptr i64 181 to ptr
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
  %t1525 = inttoptr i64 182 to ptr
  %t1526 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1525, ptr %t1526
  call void @__inc_ref(ptr %t1515)
  %t1524 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1515, ptr %t1524
  br label %reuse.join.1521
reuse.copy.1520:
  %t1527 = call ptr @__alloc(i64 24, i32 2)
  %t1528 = inttoptr i64 182 to ptr
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
  %t1545 = inttoptr i64 183 to ptr
  %t1546 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1545, ptr %t1546
  call void @__inc_ref(ptr %t1535)
  %t1544 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1535, ptr %t1544
  br label %reuse.join.1541
reuse.copy.1540:
  %t1547 = call ptr @__alloc(i64 24, i32 2)
  %t1548 = inttoptr i64 183 to ptr
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
tco.case.default.19:
  unreachable
tco.case.arm.106.1553:
  %t1554 = getelementptr ptr, ptr %t5, i32 1
  %t1555 = load ptr, ptr %t1554
  %t1556 = getelementptr ptr, ptr %t5, i32 2
  %t1557 = load ptr, ptr %t1556
  %t1558 = getelementptr i8, ptr %t5, i64 -8
  %t1559 = load i32, ptr %t1558
  %t1560 = icmp eq i32 %t1559, 1
  br i1 %t1560, label %reuse.in_place.1561, label %reuse.copy.1562
reuse.in_place.1561:
  %t1564 = inttoptr i64 105 to ptr
  %t1565 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1564, ptr %t1565
  br label %reuse.join.1563
reuse.copy.1562:
  %t1566 = call ptr @__alloc(i64 24, i32 2)
  %t1567 = inttoptr i64 105 to ptr
  %t1568 = getelementptr ptr, ptr %t1566, i32 0
  store ptr %t1567, ptr %t1568
  call void @__inc_ref(ptr %t1555)
  %t1569 = getelementptr ptr, ptr %t1566, i32 1
  store ptr %t1555, ptr %t1569
  call void @__inc_ref(ptr %t1557)
  %t1570 = getelementptr ptr, ptr %t1566, i32 2
  store ptr %t1557, ptr %t1570
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1563
reuse.join.1563:
  %t1571 = phi ptr [ %t5, %reuse.in_place.1561 ], [ %t1566, %reuse.copy.1562 ]
  %t1572 = call ptr @__alloc(i64 16, i32 1)
  %t1573 = inttoptr i64 237 to ptr
  %t1574 = getelementptr ptr, ptr %t1572, i32 0
  store ptr %t1573, ptr %t1574
  call void @__inc_ref(ptr %t6)
  %t1575 = getelementptr ptr, ptr %t1572, i32 1
  store ptr %t6, ptr %t1575
  call void @__free_recursive(ptr %t6)
  store ptr %t1571, ptr %t3
  store ptr %t1572, ptr %t4
  br label %tco.loop.0
tco.case.arm.107.1576:
  %t1577 = getelementptr ptr, ptr %t5, i32 1
  %t1578 = load ptr, ptr %t1577
  %t1579 = getelementptr ptr, ptr %t5, i32 2
  %t1580 = load ptr, ptr %t1579
  %t1581 = getelementptr i8, ptr %t5, i64 -8
  %t1582 = load i32, ptr %t1581
  %t1583 = icmp eq i32 %t1582, 1
  br i1 %t1583, label %reuse.in_place.1584, label %reuse.copy.1585
reuse.in_place.1584:
  %t1587 = inttoptr i64 105 to ptr
  %t1588 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1587, ptr %t1588
  br label %reuse.join.1586
reuse.copy.1585:
  %t1589 = call ptr @__alloc(i64 24, i32 2)
  %t1590 = inttoptr i64 105 to ptr
  %t1591 = getelementptr ptr, ptr %t1589, i32 0
  store ptr %t1590, ptr %t1591
  call void @__inc_ref(ptr %t1578)
  %t1592 = getelementptr ptr, ptr %t1589, i32 1
  store ptr %t1578, ptr %t1592
  call void @__inc_ref(ptr %t1580)
  %t1593 = getelementptr ptr, ptr %t1589, i32 2
  store ptr %t1580, ptr %t1593
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1586
reuse.join.1586:
  %t1594 = phi ptr [ %t5, %reuse.in_place.1584 ], [ %t1589, %reuse.copy.1585 ]
  %t1595 = call ptr @__alloc(i64 16, i32 1)
  %t1596 = inttoptr i64 238 to ptr
  %t1597 = getelementptr ptr, ptr %t1595, i32 0
  store ptr %t1596, ptr %t1597
  call void @__inc_ref(ptr %t6)
  %t1598 = getelementptr ptr, ptr %t1595, i32 1
  store ptr %t6, ptr %t1598
  call void @__free_recursive(ptr %t6)
  store ptr %t1594, ptr %t3
  store ptr %t1595, ptr %t4
  br label %tco.loop.0
tco.case.arm.108.1599:
  %t1600 = getelementptr ptr, ptr %t5, i32 1
  %t1601 = load ptr, ptr %t1600
  %t1602 = getelementptr ptr, ptr %t5, i32 2
  %t1603 = load ptr, ptr %t1602
  %t1604 = getelementptr i8, ptr %t5, i64 -8
  %t1605 = load i32, ptr %t1604
  %t1606 = icmp eq i32 %t1605, 1
  br i1 %t1606, label %reuse.in_place.1607, label %reuse.copy.1608
reuse.in_place.1607:
  %t1610 = inttoptr i64 105 to ptr
  %t1611 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1610, ptr %t1611
  br label %reuse.join.1609
reuse.copy.1608:
  %t1612 = call ptr @__alloc(i64 24, i32 2)
  %t1613 = inttoptr i64 105 to ptr
  %t1614 = getelementptr ptr, ptr %t1612, i32 0
  store ptr %t1613, ptr %t1614
  call void @__inc_ref(ptr %t1601)
  %t1615 = getelementptr ptr, ptr %t1612, i32 1
  store ptr %t1601, ptr %t1615
  call void @__inc_ref(ptr %t1603)
  %t1616 = getelementptr ptr, ptr %t1612, i32 2
  store ptr %t1603, ptr %t1616
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1609
reuse.join.1609:
  %t1617 = phi ptr [ %t5, %reuse.in_place.1607 ], [ %t1612, %reuse.copy.1608 ]
  %t1618 = call ptr @__alloc(i64 16, i32 1)
  %t1619 = inttoptr i64 239 to ptr
  %t1620 = getelementptr ptr, ptr %t1618, i32 0
  store ptr %t1619, ptr %t1620
  call void @__inc_ref(ptr %t6)
  %t1621 = getelementptr ptr, ptr %t1618, i32 1
  store ptr %t6, ptr %t1621
  call void @__free_recursive(ptr %t6)
  store ptr %t1617, ptr %t3
  store ptr %t1618, ptr %t4
  br label %tco.loop.0
tco.case.arm.109.1622:
  %t1623 = getelementptr ptr, ptr %t5, i32 1
  %t1624 = load ptr, ptr %t1623
  %t1625 = getelementptr ptr, ptr %t5, i32 2
  %t1626 = load ptr, ptr %t1625
  %t1627 = getelementptr i8, ptr %t5, i64 -8
  %t1628 = load i32, ptr %t1627
  %t1629 = icmp eq i32 %t1628, 1
  br i1 %t1629, label %reuse.in_place.1630, label %reuse.copy.1631
reuse.in_place.1630:
  %t1633 = inttoptr i64 105 to ptr
  %t1634 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1633, ptr %t1634
  br label %reuse.join.1632
reuse.copy.1631:
  %t1635 = call ptr @__alloc(i64 24, i32 2)
  %t1636 = inttoptr i64 105 to ptr
  %t1637 = getelementptr ptr, ptr %t1635, i32 0
  store ptr %t1636, ptr %t1637
  call void @__inc_ref(ptr %t1624)
  %t1638 = getelementptr ptr, ptr %t1635, i32 1
  store ptr %t1624, ptr %t1638
  call void @__inc_ref(ptr %t1626)
  %t1639 = getelementptr ptr, ptr %t1635, i32 2
  store ptr %t1626, ptr %t1639
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1632
reuse.join.1632:
  %t1640 = phi ptr [ %t5, %reuse.in_place.1630 ], [ %t1635, %reuse.copy.1631 ]
  %t1641 = call ptr @__alloc(i64 16, i32 1)
  %t1642 = inttoptr i64 240 to ptr
  %t1643 = getelementptr ptr, ptr %t1641, i32 0
  store ptr %t1642, ptr %t1643
  call void @__inc_ref(ptr %t6)
  %t1644 = getelementptr ptr, ptr %t1641, i32 1
  store ptr %t6, ptr %t1644
  call void @__free_recursive(ptr %t6)
  store ptr %t1640, ptr %t3
  store ptr %t1641, ptr %t4
  br label %tco.loop.0
tco.case.arm.110.1645:
  %t1646 = getelementptr ptr, ptr %t5, i32 1
  %t1647 = load ptr, ptr %t1646
  %t1648 = getelementptr ptr, ptr %t5, i32 2
  %t1649 = load ptr, ptr %t1648
  %t1650 = getelementptr i8, ptr %t5, i64 -8
  %t1651 = load i32, ptr %t1650
  %t1652 = icmp eq i32 %t1651, 1
  br i1 %t1652, label %reuse.in_place.1653, label %reuse.copy.1654
reuse.in_place.1653:
  %t1656 = inttoptr i64 105 to ptr
  %t1657 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1656, ptr %t1657
  br label %reuse.join.1655
reuse.copy.1654:
  %t1658 = call ptr @__alloc(i64 24, i32 2)
  %t1659 = inttoptr i64 105 to ptr
  %t1660 = getelementptr ptr, ptr %t1658, i32 0
  store ptr %t1659, ptr %t1660
  call void @__inc_ref(ptr %t1647)
  %t1661 = getelementptr ptr, ptr %t1658, i32 1
  store ptr %t1647, ptr %t1661
  call void @__inc_ref(ptr %t1649)
  %t1662 = getelementptr ptr, ptr %t1658, i32 2
  store ptr %t1649, ptr %t1662
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1655
reuse.join.1655:
  %t1663 = phi ptr [ %t5, %reuse.in_place.1653 ], [ %t1658, %reuse.copy.1654 ]
  %t1664 = call ptr @__alloc(i64 16, i32 1)
  %t1665 = inttoptr i64 241 to ptr
  %t1666 = getelementptr ptr, ptr %t1664, i32 0
  store ptr %t1665, ptr %t1666
  call void @__inc_ref(ptr %t6)
  %t1667 = getelementptr ptr, ptr %t1664, i32 1
  store ptr %t6, ptr %t1667
  call void @__free_recursive(ptr %t6)
  store ptr %t1663, ptr %t3
  store ptr %t1664, ptr %t4
  br label %tco.loop.0
tco.case.arm.111.1668:
  %t1669 = getelementptr ptr, ptr %t5, i32 1
  %t1670 = load ptr, ptr %t1669
  %t1671 = getelementptr ptr, ptr %t5, i32 2
  %t1672 = load ptr, ptr %t1671
  %t1673 = getelementptr i8, ptr %t5, i64 -8
  %t1674 = load i32, ptr %t1673
  %t1675 = icmp eq i32 %t1674, 1
  br i1 %t1675, label %reuse.in_place.1676, label %reuse.copy.1677
reuse.in_place.1676:
  %t1679 = inttoptr i64 105 to ptr
  %t1680 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1679, ptr %t1680
  br label %reuse.join.1678
reuse.copy.1677:
  %t1681 = call ptr @__alloc(i64 24, i32 2)
  %t1682 = inttoptr i64 105 to ptr
  %t1683 = getelementptr ptr, ptr %t1681, i32 0
  store ptr %t1682, ptr %t1683
  call void @__inc_ref(ptr %t1670)
  %t1684 = getelementptr ptr, ptr %t1681, i32 1
  store ptr %t1670, ptr %t1684
  call void @__inc_ref(ptr %t1672)
  %t1685 = getelementptr ptr, ptr %t1681, i32 2
  store ptr %t1672, ptr %t1685
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1678
reuse.join.1678:
  %t1686 = phi ptr [ %t5, %reuse.in_place.1676 ], [ %t1681, %reuse.copy.1677 ]
  %t1687 = call ptr @__alloc(i64 16, i32 1)
  %t1688 = inttoptr i64 242 to ptr
  %t1689 = getelementptr ptr, ptr %t1687, i32 0
  store ptr %t1688, ptr %t1689
  call void @__inc_ref(ptr %t6)
  %t1690 = getelementptr ptr, ptr %t1687, i32 1
  store ptr %t6, ptr %t1690
  call void @__free_recursive(ptr %t6)
  store ptr %t1686, ptr %t3
  store ptr %t1687, ptr %t4
  br label %tco.loop.0
tco.case.arm.112.1691:
  %t1692 = getelementptr ptr, ptr %t5, i32 1
  %t1693 = load ptr, ptr %t1692
  %t1694 = getelementptr ptr, ptr %t5, i32 2
  %t1695 = load ptr, ptr %t1694
  %t1696 = getelementptr i8, ptr %t5, i64 -8
  %t1697 = load i32, ptr %t1696
  %t1698 = icmp eq i32 %t1697, 1
  br i1 %t1698, label %reuse.in_place.1699, label %reuse.copy.1700
reuse.in_place.1699:
  %t1702 = inttoptr i64 105 to ptr
  %t1703 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1702, ptr %t1703
  br label %reuse.join.1701
reuse.copy.1700:
  %t1704 = call ptr @__alloc(i64 24, i32 2)
  %t1705 = inttoptr i64 105 to ptr
  %t1706 = getelementptr ptr, ptr %t1704, i32 0
  store ptr %t1705, ptr %t1706
  call void @__inc_ref(ptr %t1693)
  %t1707 = getelementptr ptr, ptr %t1704, i32 1
  store ptr %t1693, ptr %t1707
  call void @__inc_ref(ptr %t1695)
  %t1708 = getelementptr ptr, ptr %t1704, i32 2
  store ptr %t1695, ptr %t1708
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1701
reuse.join.1701:
  %t1709 = phi ptr [ %t5, %reuse.in_place.1699 ], [ %t1704, %reuse.copy.1700 ]
  %t1710 = call ptr @__alloc(i64 16, i32 1)
  %t1711 = inttoptr i64 243 to ptr
  %t1712 = getelementptr ptr, ptr %t1710, i32 0
  store ptr %t1711, ptr %t1712
  call void @__inc_ref(ptr %t6)
  %t1713 = getelementptr ptr, ptr %t1710, i32 1
  store ptr %t6, ptr %t1713
  call void @__free_recursive(ptr %t6)
  store ptr %t1709, ptr %t3
  store ptr %t1710, ptr %t4
  br label %tco.loop.0
tco.case.arm.113.1714:
  %t1715 = getelementptr ptr, ptr %t5, i32 1
  %t1716 = load ptr, ptr %t1715
  %t1717 = getelementptr ptr, ptr %t5, i32 2
  %t1718 = load ptr, ptr %t1717
  %t1719 = getelementptr i8, ptr %t5, i64 -8
  %t1720 = load i32, ptr %t1719
  %t1721 = icmp eq i32 %t1720, 1
  br i1 %t1721, label %reuse.in_place.1722, label %reuse.copy.1723
reuse.in_place.1722:
  %t1725 = inttoptr i64 105 to ptr
  %t1726 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1725, ptr %t1726
  br label %reuse.join.1724
reuse.copy.1723:
  %t1727 = call ptr @__alloc(i64 24, i32 2)
  %t1728 = inttoptr i64 105 to ptr
  %t1729 = getelementptr ptr, ptr %t1727, i32 0
  store ptr %t1728, ptr %t1729
  call void @__inc_ref(ptr %t1716)
  %t1730 = getelementptr ptr, ptr %t1727, i32 1
  store ptr %t1716, ptr %t1730
  call void @__inc_ref(ptr %t1718)
  %t1731 = getelementptr ptr, ptr %t1727, i32 2
  store ptr %t1718, ptr %t1731
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1724
reuse.join.1724:
  %t1732 = phi ptr [ %t5, %reuse.in_place.1722 ], [ %t1727, %reuse.copy.1723 ]
  %t1733 = call ptr @__alloc(i64 16, i32 1)
  %t1734 = inttoptr i64 244 to ptr
  %t1735 = getelementptr ptr, ptr %t1733, i32 0
  store ptr %t1734, ptr %t1735
  call void @__inc_ref(ptr %t6)
  %t1736 = getelementptr ptr, ptr %t1733, i32 1
  store ptr %t6, ptr %t1736
  call void @__free_recursive(ptr %t6)
  store ptr %t1732, ptr %t3
  store ptr %t1733, ptr %t4
  br label %tco.loop.0
tco.case.arm.114.1737:
  %t1738 = getelementptr ptr, ptr %t5, i32 1
  %t1739 = load ptr, ptr %t1738
  %t1740 = getelementptr ptr, ptr %t5, i32 2
  %t1741 = load ptr, ptr %t1740
  %t1742 = getelementptr i8, ptr %t5, i64 -8
  %t1743 = load i32, ptr %t1742
  %t1744 = icmp eq i32 %t1743, 1
  br i1 %t1744, label %reuse.in_place.1745, label %reuse.copy.1746
reuse.in_place.1745:
  %t1748 = inttoptr i64 105 to ptr
  %t1749 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1748, ptr %t1749
  br label %reuse.join.1747
reuse.copy.1746:
  %t1750 = call ptr @__alloc(i64 24, i32 2)
  %t1751 = inttoptr i64 105 to ptr
  %t1752 = getelementptr ptr, ptr %t1750, i32 0
  store ptr %t1751, ptr %t1752
  call void @__inc_ref(ptr %t1739)
  %t1753 = getelementptr ptr, ptr %t1750, i32 1
  store ptr %t1739, ptr %t1753
  call void @__inc_ref(ptr %t1741)
  %t1754 = getelementptr ptr, ptr %t1750, i32 2
  store ptr %t1741, ptr %t1754
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1747
reuse.join.1747:
  %t1755 = phi ptr [ %t5, %reuse.in_place.1745 ], [ %t1750, %reuse.copy.1746 ]
  %t1756 = call ptr @__alloc(i64 16, i32 1)
  %t1757 = inttoptr i64 245 to ptr
  %t1758 = getelementptr ptr, ptr %t1756, i32 0
  store ptr %t1757, ptr %t1758
  call void @__inc_ref(ptr %t6)
  %t1759 = getelementptr ptr, ptr %t1756, i32 1
  store ptr %t6, ptr %t1759
  call void @__free_recursive(ptr %t6)
  store ptr %t1755, ptr %t3
  store ptr %t1756, ptr %t4
  br label %tco.loop.0
tco.case.arm.115.1760:
  %t1761 = getelementptr ptr, ptr %t5, i32 1
  %t1762 = load ptr, ptr %t1761
  %t1763 = getelementptr ptr, ptr %t5, i32 2
  %t1764 = load ptr, ptr %t1763
  %t1765 = getelementptr i8, ptr %t5, i64 -8
  %t1766 = load i32, ptr %t1765
  %t1767 = icmp eq i32 %t1766, 1
  br i1 %t1767, label %reuse.in_place.1768, label %reuse.copy.1769
reuse.in_place.1768:
  %t1771 = inttoptr i64 105 to ptr
  %t1772 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1771, ptr %t1772
  br label %reuse.join.1770
reuse.copy.1769:
  %t1773 = call ptr @__alloc(i64 24, i32 2)
  %t1774 = inttoptr i64 105 to ptr
  %t1775 = getelementptr ptr, ptr %t1773, i32 0
  store ptr %t1774, ptr %t1775
  call void @__inc_ref(ptr %t1762)
  %t1776 = getelementptr ptr, ptr %t1773, i32 1
  store ptr %t1762, ptr %t1776
  call void @__inc_ref(ptr %t1764)
  %t1777 = getelementptr ptr, ptr %t1773, i32 2
  store ptr %t1764, ptr %t1777
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1770
reuse.join.1770:
  %t1778 = phi ptr [ %t5, %reuse.in_place.1768 ], [ %t1773, %reuse.copy.1769 ]
  %t1779 = call ptr @__alloc(i64 16, i32 1)
  %t1780 = inttoptr i64 246 to ptr
  %t1781 = getelementptr ptr, ptr %t1779, i32 0
  store ptr %t1780, ptr %t1781
  call void @__inc_ref(ptr %t6)
  %t1782 = getelementptr ptr, ptr %t1779, i32 1
  store ptr %t6, ptr %t1782
  call void @__free_recursive(ptr %t6)
  store ptr %t1778, ptr %t3
  store ptr %t1779, ptr %t4
  br label %tco.loop.0
tco.case.arm.116.1783:
  %t1784 = getelementptr ptr, ptr %t5, i32 1
  %t1785 = load ptr, ptr %t1784
  %t1786 = getelementptr ptr, ptr %t5, i32 2
  %t1787 = load ptr, ptr %t1786
  %t1788 = getelementptr i8, ptr %t5, i64 -8
  %t1789 = load i32, ptr %t1788
  %t1790 = icmp eq i32 %t1789, 1
  br i1 %t1790, label %reuse.in_place.1791, label %reuse.copy.1792
reuse.in_place.1791:
  %t1794 = inttoptr i64 105 to ptr
  %t1795 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1794, ptr %t1795
  br label %reuse.join.1793
reuse.copy.1792:
  %t1796 = call ptr @__alloc(i64 24, i32 2)
  %t1797 = inttoptr i64 105 to ptr
  %t1798 = getelementptr ptr, ptr %t1796, i32 0
  store ptr %t1797, ptr %t1798
  call void @__inc_ref(ptr %t1785)
  %t1799 = getelementptr ptr, ptr %t1796, i32 1
  store ptr %t1785, ptr %t1799
  call void @__inc_ref(ptr %t1787)
  %t1800 = getelementptr ptr, ptr %t1796, i32 2
  store ptr %t1787, ptr %t1800
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1793
reuse.join.1793:
  %t1801 = phi ptr [ %t5, %reuse.in_place.1791 ], [ %t1796, %reuse.copy.1792 ]
  %t1802 = call ptr @__alloc(i64 16, i32 1)
  %t1803 = inttoptr i64 247 to ptr
  %t1804 = getelementptr ptr, ptr %t1802, i32 0
  store ptr %t1803, ptr %t1804
  call void @__inc_ref(ptr %t6)
  %t1805 = getelementptr ptr, ptr %t1802, i32 1
  store ptr %t6, ptr %t1805
  call void @__free_recursive(ptr %t6)
  store ptr %t1801, ptr %t3
  store ptr %t1802, ptr %t4
  br label %tco.loop.0
tco.case.arm.117.1806:
  %t1807 = getelementptr ptr, ptr %t5, i32 1
  %t1808 = load ptr, ptr %t1807
  %t1809 = getelementptr ptr, ptr %t5, i32 2
  %t1810 = load ptr, ptr %t1809
  %t1811 = getelementptr i8, ptr %t5, i64 -8
  %t1812 = load i32, ptr %t1811
  %t1813 = icmp eq i32 %t1812, 1
  br i1 %t1813, label %reuse.in_place.1814, label %reuse.copy.1815
reuse.in_place.1814:
  %t1817 = inttoptr i64 105 to ptr
  %t1818 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1817, ptr %t1818
  br label %reuse.join.1816
reuse.copy.1815:
  %t1819 = call ptr @__alloc(i64 24, i32 2)
  %t1820 = inttoptr i64 105 to ptr
  %t1821 = getelementptr ptr, ptr %t1819, i32 0
  store ptr %t1820, ptr %t1821
  call void @__inc_ref(ptr %t1808)
  %t1822 = getelementptr ptr, ptr %t1819, i32 1
  store ptr %t1808, ptr %t1822
  call void @__inc_ref(ptr %t1810)
  %t1823 = getelementptr ptr, ptr %t1819, i32 2
  store ptr %t1810, ptr %t1823
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1816
reuse.join.1816:
  %t1824 = phi ptr [ %t5, %reuse.in_place.1814 ], [ %t1819, %reuse.copy.1815 ]
  %t1825 = call ptr @__alloc(i64 16, i32 1)
  %t1826 = inttoptr i64 248 to ptr
  %t1827 = getelementptr ptr, ptr %t1825, i32 0
  store ptr %t1826, ptr %t1827
  call void @__inc_ref(ptr %t6)
  %t1828 = getelementptr ptr, ptr %t1825, i32 1
  store ptr %t6, ptr %t1828
  call void @__free_recursive(ptr %t6)
  store ptr %t1824, ptr %t3
  store ptr %t1825, ptr %t4
  br label %tco.loop.0
tco.case.arm.118.1829:
  %t1830 = getelementptr ptr, ptr %t5, i32 1
  %t1831 = load ptr, ptr %t1830
  %t1832 = getelementptr ptr, ptr %t5, i32 2
  %t1833 = load ptr, ptr %t1832
  %t1834 = getelementptr i8, ptr %t5, i64 -8
  %t1835 = load i32, ptr %t1834
  %t1836 = icmp eq i32 %t1835, 1
  br i1 %t1836, label %reuse.in_place.1837, label %reuse.copy.1838
reuse.in_place.1837:
  %t1840 = inttoptr i64 105 to ptr
  %t1841 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1840, ptr %t1841
  br label %reuse.join.1839
reuse.copy.1838:
  %t1842 = call ptr @__alloc(i64 24, i32 2)
  %t1843 = inttoptr i64 105 to ptr
  %t1844 = getelementptr ptr, ptr %t1842, i32 0
  store ptr %t1843, ptr %t1844
  call void @__inc_ref(ptr %t1831)
  %t1845 = getelementptr ptr, ptr %t1842, i32 1
  store ptr %t1831, ptr %t1845
  call void @__inc_ref(ptr %t1833)
  %t1846 = getelementptr ptr, ptr %t1842, i32 2
  store ptr %t1833, ptr %t1846
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1839
reuse.join.1839:
  %t1847 = phi ptr [ %t5, %reuse.in_place.1837 ], [ %t1842, %reuse.copy.1838 ]
  %t1848 = call ptr @__alloc(i64 16, i32 1)
  %t1849 = inttoptr i64 249 to ptr
  %t1850 = getelementptr ptr, ptr %t1848, i32 0
  store ptr %t1849, ptr %t1850
  call void @__inc_ref(ptr %t6)
  %t1851 = getelementptr ptr, ptr %t1848, i32 1
  store ptr %t6, ptr %t1851
  call void @__free_recursive(ptr %t6)
  store ptr %t1847, ptr %t3
  store ptr %t1848, ptr %t4
  br label %tco.loop.0
tco.case.arm.119.1852:
  %t1853 = getelementptr ptr, ptr %t5, i32 1
  %t1854 = load ptr, ptr %t1853
  %t1855 = getelementptr ptr, ptr %t5, i32 2
  %t1856 = load ptr, ptr %t1855
  %t1857 = getelementptr i8, ptr %t5, i64 -8
  %t1858 = load i32, ptr %t1857
  %t1859 = icmp eq i32 %t1858, 1
  br i1 %t1859, label %reuse.in_place.1860, label %reuse.copy.1861
reuse.in_place.1860:
  %t1863 = inttoptr i64 105 to ptr
  %t1864 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1863, ptr %t1864
  br label %reuse.join.1862
reuse.copy.1861:
  %t1865 = call ptr @__alloc(i64 24, i32 2)
  %t1866 = inttoptr i64 105 to ptr
  %t1867 = getelementptr ptr, ptr %t1865, i32 0
  store ptr %t1866, ptr %t1867
  call void @__inc_ref(ptr %t1854)
  %t1868 = getelementptr ptr, ptr %t1865, i32 1
  store ptr %t1854, ptr %t1868
  call void @__inc_ref(ptr %t1856)
  %t1869 = getelementptr ptr, ptr %t1865, i32 2
  store ptr %t1856, ptr %t1869
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1862
reuse.join.1862:
  %t1870 = phi ptr [ %t5, %reuse.in_place.1860 ], [ %t1865, %reuse.copy.1861 ]
  %t1871 = call ptr @__alloc(i64 16, i32 1)
  %t1872 = inttoptr i64 250 to ptr
  %t1873 = getelementptr ptr, ptr %t1871, i32 0
  store ptr %t1872, ptr %t1873
  call void @__inc_ref(ptr %t6)
  %t1874 = getelementptr ptr, ptr %t1871, i32 1
  store ptr %t6, ptr %t1874
  call void @__free_recursive(ptr %t6)
  store ptr %t1870, ptr %t3
  store ptr %t1871, ptr %t4
  br label %tco.loop.0
tco.case.arm.120.1875:
  %t1876 = getelementptr ptr, ptr %t5, i32 1
  %t1877 = load ptr, ptr %t1876
  %t1878 = getelementptr ptr, ptr %t5, i32 2
  %t1879 = load ptr, ptr %t1878
  %t1880 = getelementptr i8, ptr %t5, i64 -8
  %t1881 = load i32, ptr %t1880
  %t1882 = icmp eq i32 %t1881, 1
  br i1 %t1882, label %reuse.in_place.1883, label %reuse.copy.1884
reuse.in_place.1883:
  %t1886 = inttoptr i64 105 to ptr
  %t1887 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1886, ptr %t1887
  br label %reuse.join.1885
reuse.copy.1884:
  %t1888 = call ptr @__alloc(i64 24, i32 2)
  %t1889 = inttoptr i64 105 to ptr
  %t1890 = getelementptr ptr, ptr %t1888, i32 0
  store ptr %t1889, ptr %t1890
  call void @__inc_ref(ptr %t1877)
  %t1891 = getelementptr ptr, ptr %t1888, i32 1
  store ptr %t1877, ptr %t1891
  call void @__inc_ref(ptr %t1879)
  %t1892 = getelementptr ptr, ptr %t1888, i32 2
  store ptr %t1879, ptr %t1892
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1885
reuse.join.1885:
  %t1893 = phi ptr [ %t5, %reuse.in_place.1883 ], [ %t1888, %reuse.copy.1884 ]
  %t1894 = call ptr @__alloc(i64 16, i32 1)
  %t1895 = inttoptr i64 251 to ptr
  %t1896 = getelementptr ptr, ptr %t1894, i32 0
  store ptr %t1895, ptr %t1896
  call void @__inc_ref(ptr %t6)
  %t1897 = getelementptr ptr, ptr %t1894, i32 1
  store ptr %t6, ptr %t1897
  call void @__free_recursive(ptr %t6)
  store ptr %t1893, ptr %t3
  store ptr %t1894, ptr %t4
  br label %tco.loop.0
tco.case.arm.121.1898:
  %t1899 = getelementptr ptr, ptr %t5, i32 1
  %t1900 = load ptr, ptr %t1899
  %t1901 = getelementptr ptr, ptr %t5, i32 2
  %t1902 = load ptr, ptr %t1901
  %t1903 = getelementptr i8, ptr %t5, i64 -8
  %t1904 = load i32, ptr %t1903
  %t1905 = icmp eq i32 %t1904, 1
  br i1 %t1905, label %reuse.in_place.1906, label %reuse.copy.1907
reuse.in_place.1906:
  %t1909 = inttoptr i64 105 to ptr
  %t1910 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1909, ptr %t1910
  br label %reuse.join.1908
reuse.copy.1907:
  %t1911 = call ptr @__alloc(i64 24, i32 2)
  %t1912 = inttoptr i64 105 to ptr
  %t1913 = getelementptr ptr, ptr %t1911, i32 0
  store ptr %t1912, ptr %t1913
  call void @__inc_ref(ptr %t1900)
  %t1914 = getelementptr ptr, ptr %t1911, i32 1
  store ptr %t1900, ptr %t1914
  call void @__inc_ref(ptr %t1902)
  %t1915 = getelementptr ptr, ptr %t1911, i32 2
  store ptr %t1902, ptr %t1915
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1908
reuse.join.1908:
  %t1916 = phi ptr [ %t5, %reuse.in_place.1906 ], [ %t1911, %reuse.copy.1907 ]
  %t1917 = call ptr @__alloc(i64 16, i32 1)
  %t1918 = inttoptr i64 252 to ptr
  %t1919 = getelementptr ptr, ptr %t1917, i32 0
  store ptr %t1918, ptr %t1919
  call void @__inc_ref(ptr %t6)
  %t1920 = getelementptr ptr, ptr %t1917, i32 1
  store ptr %t6, ptr %t1920
  call void @__free_recursive(ptr %t6)
  store ptr %t1916, ptr %t3
  store ptr %t1917, ptr %t4
  br label %tco.loop.0
tco.case.arm.122.1921:
  %t1922 = getelementptr ptr, ptr %t5, i32 1
  %t1923 = load ptr, ptr %t1922
  %t1924 = getelementptr ptr, ptr %t5, i32 2
  %t1925 = load ptr, ptr %t1924
  %t1926 = getelementptr i8, ptr %t5, i64 -8
  %t1927 = load i32, ptr %t1926
  %t1928 = icmp eq i32 %t1927, 1
  br i1 %t1928, label %reuse.in_place.1929, label %reuse.copy.1930
reuse.in_place.1929:
  %t1932 = inttoptr i64 105 to ptr
  %t1933 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1932, ptr %t1933
  br label %reuse.join.1931
reuse.copy.1930:
  %t1934 = call ptr @__alloc(i64 24, i32 2)
  %t1935 = inttoptr i64 105 to ptr
  %t1936 = getelementptr ptr, ptr %t1934, i32 0
  store ptr %t1935, ptr %t1936
  call void @__inc_ref(ptr %t1923)
  %t1937 = getelementptr ptr, ptr %t1934, i32 1
  store ptr %t1923, ptr %t1937
  call void @__inc_ref(ptr %t1925)
  %t1938 = getelementptr ptr, ptr %t1934, i32 2
  store ptr %t1925, ptr %t1938
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1931
reuse.join.1931:
  %t1939 = phi ptr [ %t5, %reuse.in_place.1929 ], [ %t1934, %reuse.copy.1930 ]
  %t1940 = call ptr @__alloc(i64 16, i32 1)
  %t1941 = inttoptr i64 253 to ptr
  %t1942 = getelementptr ptr, ptr %t1940, i32 0
  store ptr %t1941, ptr %t1942
  call void @__inc_ref(ptr %t6)
  %t1943 = getelementptr ptr, ptr %t1940, i32 1
  store ptr %t6, ptr %t1943
  call void @__free_recursive(ptr %t6)
  store ptr %t1939, ptr %t3
  store ptr %t1940, ptr %t4
  br label %tco.loop.0
tco.case.arm.123.1944:
  %t1945 = getelementptr ptr, ptr %t5, i32 1
  %t1946 = load ptr, ptr %t1945
  %t1947 = getelementptr ptr, ptr %t5, i32 2
  %t1948 = load ptr, ptr %t1947
  %t1949 = getelementptr i8, ptr %t5, i64 -8
  %t1950 = load i32, ptr %t1949
  %t1951 = icmp eq i32 %t1950, 1
  br i1 %t1951, label %reuse.in_place.1952, label %reuse.copy.1953
reuse.in_place.1952:
  %t1955 = inttoptr i64 105 to ptr
  %t1956 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1955, ptr %t1956
  br label %reuse.join.1954
reuse.copy.1953:
  %t1957 = call ptr @__alloc(i64 24, i32 2)
  %t1958 = inttoptr i64 105 to ptr
  %t1959 = getelementptr ptr, ptr %t1957, i32 0
  store ptr %t1958, ptr %t1959
  call void @__inc_ref(ptr %t1946)
  %t1960 = getelementptr ptr, ptr %t1957, i32 1
  store ptr %t1946, ptr %t1960
  call void @__inc_ref(ptr %t1948)
  %t1961 = getelementptr ptr, ptr %t1957, i32 2
  store ptr %t1948, ptr %t1961
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1954
reuse.join.1954:
  %t1962 = phi ptr [ %t5, %reuse.in_place.1952 ], [ %t1957, %reuse.copy.1953 ]
  %t1963 = call ptr @__alloc(i64 16, i32 1)
  %t1964 = inttoptr i64 254 to ptr
  %t1965 = getelementptr ptr, ptr %t1963, i32 0
  store ptr %t1964, ptr %t1965
  call void @__inc_ref(ptr %t6)
  %t1966 = getelementptr ptr, ptr %t1963, i32 1
  store ptr %t6, ptr %t1966
  call void @__free_recursive(ptr %t6)
  store ptr %t1962, ptr %t3
  store ptr %t1963, ptr %t4
  br label %tco.loop.0
tco.case.arm.124.1967:
  %t1968 = getelementptr ptr, ptr %t5, i32 1
  %t1969 = load ptr, ptr %t1968
  %t1970 = getelementptr ptr, ptr %t5, i32 2
  %t1971 = load ptr, ptr %t1970
  %t1972 = getelementptr i8, ptr %t5, i64 -8
  %t1973 = load i32, ptr %t1972
  %t1974 = icmp eq i32 %t1973, 1
  br i1 %t1974, label %reuse.in_place.1975, label %reuse.copy.1976
reuse.in_place.1975:
  %t1978 = inttoptr i64 105 to ptr
  %t1979 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1978, ptr %t1979
  br label %reuse.join.1977
reuse.copy.1976:
  %t1980 = call ptr @__alloc(i64 24, i32 2)
  %t1981 = inttoptr i64 105 to ptr
  %t1982 = getelementptr ptr, ptr %t1980, i32 0
  store ptr %t1981, ptr %t1982
  call void @__inc_ref(ptr %t1969)
  %t1983 = getelementptr ptr, ptr %t1980, i32 1
  store ptr %t1969, ptr %t1983
  call void @__inc_ref(ptr %t1971)
  %t1984 = getelementptr ptr, ptr %t1980, i32 2
  store ptr %t1971, ptr %t1984
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1977
reuse.join.1977:
  %t1985 = phi ptr [ %t5, %reuse.in_place.1975 ], [ %t1980, %reuse.copy.1976 ]
  %t1986 = call ptr @__alloc(i64 16, i32 1)
  %t1987 = inttoptr i64 255 to ptr
  %t1988 = getelementptr ptr, ptr %t1986, i32 0
  store ptr %t1987, ptr %t1988
  call void @__inc_ref(ptr %t6)
  %t1989 = getelementptr ptr, ptr %t1986, i32 1
  store ptr %t6, ptr %t1989
  call void @__free_recursive(ptr %t6)
  store ptr %t1985, ptr %t3
  store ptr %t1986, ptr %t4
  br label %tco.loop.0
tco.case.arm.125.1990:
  %t1991 = getelementptr ptr, ptr %t5, i32 1
  %t1992 = load ptr, ptr %t1991
  %t1993 = getelementptr ptr, ptr %t5, i32 2
  %t1994 = load ptr, ptr %t1993
  %t1995 = getelementptr i8, ptr %t5, i64 -8
  %t1996 = load i32, ptr %t1995
  %t1997 = icmp eq i32 %t1996, 1
  br i1 %t1997, label %reuse.in_place.1998, label %reuse.copy.1999
reuse.in_place.1998:
  %t2001 = inttoptr i64 105 to ptr
  %t2002 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2001, ptr %t2002
  br label %reuse.join.2000
reuse.copy.1999:
  %t2003 = call ptr @__alloc(i64 24, i32 2)
  %t2004 = inttoptr i64 105 to ptr
  %t2005 = getelementptr ptr, ptr %t2003, i32 0
  store ptr %t2004, ptr %t2005
  call void @__inc_ref(ptr %t1992)
  %t2006 = getelementptr ptr, ptr %t2003, i32 1
  store ptr %t1992, ptr %t2006
  call void @__inc_ref(ptr %t1994)
  %t2007 = getelementptr ptr, ptr %t2003, i32 2
  store ptr %t1994, ptr %t2007
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2000
reuse.join.2000:
  %t2008 = phi ptr [ %t5, %reuse.in_place.1998 ], [ %t2003, %reuse.copy.1999 ]
  %t2009 = call ptr @__alloc(i64 16, i32 1)
  %t2010 = inttoptr i64 256 to ptr
  %t2011 = getelementptr ptr, ptr %t2009, i32 0
  store ptr %t2010, ptr %t2011
  call void @__inc_ref(ptr %t6)
  %t2012 = getelementptr ptr, ptr %t2009, i32 1
  store ptr %t6, ptr %t2012
  call void @__free_recursive(ptr %t6)
  store ptr %t2008, ptr %t3
  store ptr %t2009, ptr %t4
  br label %tco.loop.0
tco.case.arm.126.2013:
  %t2014 = getelementptr ptr, ptr %t5, i32 1
  %t2015 = load ptr, ptr %t2014
  %t2016 = getelementptr ptr, ptr %t5, i32 2
  %t2017 = load ptr, ptr %t2016
  %t2018 = getelementptr i8, ptr %t5, i64 -8
  %t2019 = load i32, ptr %t2018
  %t2020 = icmp eq i32 %t2019, 1
  br i1 %t2020, label %reuse.in_place.2021, label %reuse.copy.2022
reuse.in_place.2021:
  %t2024 = inttoptr i64 105 to ptr
  %t2025 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2024, ptr %t2025
  br label %reuse.join.2023
reuse.copy.2022:
  %t2026 = call ptr @__alloc(i64 24, i32 2)
  %t2027 = inttoptr i64 105 to ptr
  %t2028 = getelementptr ptr, ptr %t2026, i32 0
  store ptr %t2027, ptr %t2028
  call void @__inc_ref(ptr %t2015)
  %t2029 = getelementptr ptr, ptr %t2026, i32 1
  store ptr %t2015, ptr %t2029
  call void @__inc_ref(ptr %t2017)
  %t2030 = getelementptr ptr, ptr %t2026, i32 2
  store ptr %t2017, ptr %t2030
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2023
reuse.join.2023:
  %t2031 = phi ptr [ %t5, %reuse.in_place.2021 ], [ %t2026, %reuse.copy.2022 ]
  %t2032 = call ptr @__alloc(i64 16, i32 1)
  %t2033 = inttoptr i64 257 to ptr
  %t2034 = getelementptr ptr, ptr %t2032, i32 0
  store ptr %t2033, ptr %t2034
  call void @__inc_ref(ptr %t6)
  %t2035 = getelementptr ptr, ptr %t2032, i32 1
  store ptr %t6, ptr %t2035
  call void @__free_recursive(ptr %t6)
  store ptr %t2031, ptr %t3
  store ptr %t2032, ptr %t4
  br label %tco.loop.0
tco.case.arm.127.2036:
  %t2037 = getelementptr ptr, ptr %t5, i32 1
  %t2038 = load ptr, ptr %t2037
  %t2039 = getelementptr ptr, ptr %t5, i32 2
  %t2040 = load ptr, ptr %t2039
  %t2041 = getelementptr i8, ptr %t5, i64 -8
  %t2042 = load i32, ptr %t2041
  %t2043 = icmp eq i32 %t2042, 1
  br i1 %t2043, label %reuse.in_place.2044, label %reuse.copy.2045
reuse.in_place.2044:
  %t2047 = inttoptr i64 105 to ptr
  %t2048 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2047, ptr %t2048
  br label %reuse.join.2046
reuse.copy.2045:
  %t2049 = call ptr @__alloc(i64 24, i32 2)
  %t2050 = inttoptr i64 105 to ptr
  %t2051 = getelementptr ptr, ptr %t2049, i32 0
  store ptr %t2050, ptr %t2051
  call void @__inc_ref(ptr %t2038)
  %t2052 = getelementptr ptr, ptr %t2049, i32 1
  store ptr %t2038, ptr %t2052
  call void @__inc_ref(ptr %t2040)
  %t2053 = getelementptr ptr, ptr %t2049, i32 2
  store ptr %t2040, ptr %t2053
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2046
reuse.join.2046:
  %t2054 = phi ptr [ %t5, %reuse.in_place.2044 ], [ %t2049, %reuse.copy.2045 ]
  %t2055 = call ptr @__alloc(i64 16, i32 1)
  %t2056 = inttoptr i64 258 to ptr
  %t2057 = getelementptr ptr, ptr %t2055, i32 0
  store ptr %t2056, ptr %t2057
  call void @__inc_ref(ptr %t6)
  %t2058 = getelementptr ptr, ptr %t2055, i32 1
  store ptr %t6, ptr %t2058
  call void @__free_recursive(ptr %t6)
  store ptr %t2054, ptr %t3
  store ptr %t2055, ptr %t4
  br label %tco.loop.0
tco.case.arm.128.2059:
  %t2060 = getelementptr ptr, ptr %t5, i32 1
  %t2061 = load ptr, ptr %t2060
  %t2062 = getelementptr ptr, ptr %t5, i32 2
  %t2063 = load ptr, ptr %t2062
  %t2064 = getelementptr i8, ptr %t5, i64 -8
  %t2065 = load i32, ptr %t2064
  %t2066 = icmp eq i32 %t2065, 1
  br i1 %t2066, label %reuse.in_place.2067, label %reuse.copy.2068
reuse.in_place.2067:
  %t2070 = inttoptr i64 105 to ptr
  %t2071 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2070, ptr %t2071
  br label %reuse.join.2069
reuse.copy.2068:
  %t2072 = call ptr @__alloc(i64 24, i32 2)
  %t2073 = inttoptr i64 105 to ptr
  %t2074 = getelementptr ptr, ptr %t2072, i32 0
  store ptr %t2073, ptr %t2074
  call void @__inc_ref(ptr %t2061)
  %t2075 = getelementptr ptr, ptr %t2072, i32 1
  store ptr %t2061, ptr %t2075
  call void @__inc_ref(ptr %t2063)
  %t2076 = getelementptr ptr, ptr %t2072, i32 2
  store ptr %t2063, ptr %t2076
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2069
reuse.join.2069:
  %t2077 = phi ptr [ %t5, %reuse.in_place.2067 ], [ %t2072, %reuse.copy.2068 ]
  %t2078 = call ptr @__alloc(i64 16, i32 1)
  %t2079 = inttoptr i64 259 to ptr
  %t2080 = getelementptr ptr, ptr %t2078, i32 0
  store ptr %t2079, ptr %t2080
  call void @__inc_ref(ptr %t6)
  %t2081 = getelementptr ptr, ptr %t2078, i32 1
  store ptr %t6, ptr %t2081
  call void @__free_recursive(ptr %t6)
  store ptr %t2077, ptr %t3
  store ptr %t2078, ptr %t4
  br label %tco.loop.0
tco.case.arm.129.2082:
  %t2083 = getelementptr ptr, ptr %t5, i32 1
  %t2084 = load ptr, ptr %t2083
  %t2085 = getelementptr ptr, ptr %t5, i32 2
  %t2086 = load ptr, ptr %t2085
  %t2087 = getelementptr i8, ptr %t5, i64 -8
  %t2088 = load i32, ptr %t2087
  %t2089 = icmp eq i32 %t2088, 1
  br i1 %t2089, label %reuse.in_place.2090, label %reuse.copy.2091
reuse.in_place.2090:
  %t2093 = inttoptr i64 105 to ptr
  %t2094 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2093, ptr %t2094
  br label %reuse.join.2092
reuse.copy.2091:
  %t2095 = call ptr @__alloc(i64 24, i32 2)
  %t2096 = inttoptr i64 105 to ptr
  %t2097 = getelementptr ptr, ptr %t2095, i32 0
  store ptr %t2096, ptr %t2097
  call void @__inc_ref(ptr %t2084)
  %t2098 = getelementptr ptr, ptr %t2095, i32 1
  store ptr %t2084, ptr %t2098
  call void @__inc_ref(ptr %t2086)
  %t2099 = getelementptr ptr, ptr %t2095, i32 2
  store ptr %t2086, ptr %t2099
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2092
reuse.join.2092:
  %t2100 = phi ptr [ %t5, %reuse.in_place.2090 ], [ %t2095, %reuse.copy.2091 ]
  %t2101 = call ptr @__alloc(i64 16, i32 1)
  %t2102 = inttoptr i64 260 to ptr
  %t2103 = getelementptr ptr, ptr %t2101, i32 0
  store ptr %t2102, ptr %t2103
  call void @__inc_ref(ptr %t6)
  %t2104 = getelementptr ptr, ptr %t2101, i32 1
  store ptr %t6, ptr %t2104
  call void @__free_recursive(ptr %t6)
  store ptr %t2100, ptr %t3
  store ptr %t2101, ptr %t4
  br label %tco.loop.0
tco.case.arm.130.2105:
  %t2106 = getelementptr ptr, ptr %t5, i32 1
  %t2107 = load ptr, ptr %t2106
  %t2108 = getelementptr ptr, ptr %t5, i32 2
  %t2109 = load ptr, ptr %t2108
  %t2110 = getelementptr i8, ptr %t5, i64 -8
  %t2111 = load i32, ptr %t2110
  %t2112 = icmp eq i32 %t2111, 1
  br i1 %t2112, label %reuse.in_place.2113, label %reuse.copy.2114
reuse.in_place.2113:
  %t2116 = inttoptr i64 105 to ptr
  %t2117 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2116, ptr %t2117
  br label %reuse.join.2115
reuse.copy.2114:
  %t2118 = call ptr @__alloc(i64 24, i32 2)
  %t2119 = inttoptr i64 105 to ptr
  %t2120 = getelementptr ptr, ptr %t2118, i32 0
  store ptr %t2119, ptr %t2120
  call void @__inc_ref(ptr %t2107)
  %t2121 = getelementptr ptr, ptr %t2118, i32 1
  store ptr %t2107, ptr %t2121
  call void @__inc_ref(ptr %t2109)
  %t2122 = getelementptr ptr, ptr %t2118, i32 2
  store ptr %t2109, ptr %t2122
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2115
reuse.join.2115:
  %t2123 = phi ptr [ %t5, %reuse.in_place.2113 ], [ %t2118, %reuse.copy.2114 ]
  %t2124 = call ptr @__alloc(i64 16, i32 1)
  %t2125 = inttoptr i64 261 to ptr
  %t2126 = getelementptr ptr, ptr %t2124, i32 0
  store ptr %t2125, ptr %t2126
  call void @__inc_ref(ptr %t6)
  %t2127 = getelementptr ptr, ptr %t2124, i32 1
  store ptr %t6, ptr %t2127
  call void @__free_recursive(ptr %t6)
  store ptr %t2123, ptr %t3
  store ptr %t2124, ptr %t4
  br label %tco.loop.0
tco.case.arm.131.2128:
  %t2129 = getelementptr ptr, ptr %t5, i32 1
  %t2130 = load ptr, ptr %t2129
  %t2131 = getelementptr ptr, ptr %t5, i32 2
  %t2132 = load ptr, ptr %t2131
  %t2133 = getelementptr i8, ptr %t5, i64 -8
  %t2134 = load i32, ptr %t2133
  %t2135 = icmp eq i32 %t2134, 1
  br i1 %t2135, label %reuse.in_place.2136, label %reuse.copy.2137
reuse.in_place.2136:
  %t2139 = inttoptr i64 105 to ptr
  %t2140 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2139, ptr %t2140
  br label %reuse.join.2138
reuse.copy.2137:
  %t2141 = call ptr @__alloc(i64 24, i32 2)
  %t2142 = inttoptr i64 105 to ptr
  %t2143 = getelementptr ptr, ptr %t2141, i32 0
  store ptr %t2142, ptr %t2143
  call void @__inc_ref(ptr %t2130)
  %t2144 = getelementptr ptr, ptr %t2141, i32 1
  store ptr %t2130, ptr %t2144
  call void @__inc_ref(ptr %t2132)
  %t2145 = getelementptr ptr, ptr %t2141, i32 2
  store ptr %t2132, ptr %t2145
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2138
reuse.join.2138:
  %t2146 = phi ptr [ %t5, %reuse.in_place.2136 ], [ %t2141, %reuse.copy.2137 ]
  %t2147 = call ptr @__alloc(i64 16, i32 1)
  %t2148 = inttoptr i64 262 to ptr
  %t2149 = getelementptr ptr, ptr %t2147, i32 0
  store ptr %t2148, ptr %t2149
  call void @__inc_ref(ptr %t6)
  %t2150 = getelementptr ptr, ptr %t2147, i32 1
  store ptr %t6, ptr %t2150
  call void @__free_recursive(ptr %t6)
  store ptr %t2146, ptr %t3
  store ptr %t2147, ptr %t4
  br label %tco.loop.0
tco.case.arm.132.2151:
  %t2152 = getelementptr ptr, ptr %t5, i32 1
  %t2153 = load ptr, ptr %t2152
  %t2154 = getelementptr ptr, ptr %t5, i32 2
  %t2155 = load ptr, ptr %t2154
  %t2156 = getelementptr i8, ptr %t5, i64 -8
  %t2157 = load i32, ptr %t2156
  %t2158 = icmp eq i32 %t2157, 1
  br i1 %t2158, label %reuse.in_place.2159, label %reuse.copy.2160
reuse.in_place.2159:
  %t2162 = inttoptr i64 105 to ptr
  %t2163 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2162, ptr %t2163
  br label %reuse.join.2161
reuse.copy.2160:
  %t2164 = call ptr @__alloc(i64 24, i32 2)
  %t2165 = inttoptr i64 105 to ptr
  %t2166 = getelementptr ptr, ptr %t2164, i32 0
  store ptr %t2165, ptr %t2166
  call void @__inc_ref(ptr %t2153)
  %t2167 = getelementptr ptr, ptr %t2164, i32 1
  store ptr %t2153, ptr %t2167
  call void @__inc_ref(ptr %t2155)
  %t2168 = getelementptr ptr, ptr %t2164, i32 2
  store ptr %t2155, ptr %t2168
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2161
reuse.join.2161:
  %t2169 = phi ptr [ %t5, %reuse.in_place.2159 ], [ %t2164, %reuse.copy.2160 ]
  %t2170 = call ptr @__alloc(i64 16, i32 1)
  %t2171 = inttoptr i64 263 to ptr
  %t2172 = getelementptr ptr, ptr %t2170, i32 0
  store ptr %t2171, ptr %t2172
  call void @__inc_ref(ptr %t6)
  %t2173 = getelementptr ptr, ptr %t2170, i32 1
  store ptr %t6, ptr %t2173
  call void @__free_recursive(ptr %t6)
  store ptr %t2169, ptr %t3
  store ptr %t2170, ptr %t4
  br label %tco.loop.0
tco.case.arm.133.2174:
  %t2175 = getelementptr ptr, ptr %t5, i32 1
  %t2176 = load ptr, ptr %t2175
  %t2177 = getelementptr ptr, ptr %t5, i32 2
  %t2178 = load ptr, ptr %t2177
  %t2179 = getelementptr i8, ptr %t5, i64 -8
  %t2180 = load i32, ptr %t2179
  %t2181 = icmp eq i32 %t2180, 1
  br i1 %t2181, label %reuse.in_place.2182, label %reuse.copy.2183
reuse.in_place.2182:
  %t2185 = inttoptr i64 105 to ptr
  %t2186 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2185, ptr %t2186
  br label %reuse.join.2184
reuse.copy.2183:
  %t2187 = call ptr @__alloc(i64 24, i32 2)
  %t2188 = inttoptr i64 105 to ptr
  %t2189 = getelementptr ptr, ptr %t2187, i32 0
  store ptr %t2188, ptr %t2189
  call void @__inc_ref(ptr %t2176)
  %t2190 = getelementptr ptr, ptr %t2187, i32 1
  store ptr %t2176, ptr %t2190
  call void @__inc_ref(ptr %t2178)
  %t2191 = getelementptr ptr, ptr %t2187, i32 2
  store ptr %t2178, ptr %t2191
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2184
reuse.join.2184:
  %t2192 = phi ptr [ %t5, %reuse.in_place.2182 ], [ %t2187, %reuse.copy.2183 ]
  %t2193 = call ptr @__alloc(i64 16, i32 1)
  %t2194 = inttoptr i64 264 to ptr
  %t2195 = getelementptr ptr, ptr %t2193, i32 0
  store ptr %t2194, ptr %t2195
  call void @__inc_ref(ptr %t6)
  %t2196 = getelementptr ptr, ptr %t2193, i32 1
  store ptr %t6, ptr %t2196
  call void @__free_recursive(ptr %t6)
  store ptr %t2192, ptr %t3
  store ptr %t2193, ptr %t4
  br label %tco.loop.0
tco.case.arm.134.2197:
  %t2198 = getelementptr ptr, ptr %t5, i32 1
  %t2199 = load ptr, ptr %t2198
  %t2200 = getelementptr ptr, ptr %t5, i32 2
  %t2201 = load ptr, ptr %t2200
  %t2202 = getelementptr i8, ptr %t5, i64 -8
  %t2203 = load i32, ptr %t2202
  %t2204 = icmp eq i32 %t2203, 1
  br i1 %t2204, label %reuse.in_place.2205, label %reuse.copy.2206
reuse.in_place.2205:
  %t2208 = inttoptr i64 105 to ptr
  %t2209 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2208, ptr %t2209
  br label %reuse.join.2207
reuse.copy.2206:
  %t2210 = call ptr @__alloc(i64 24, i32 2)
  %t2211 = inttoptr i64 105 to ptr
  %t2212 = getelementptr ptr, ptr %t2210, i32 0
  store ptr %t2211, ptr %t2212
  call void @__inc_ref(ptr %t2199)
  %t2213 = getelementptr ptr, ptr %t2210, i32 1
  store ptr %t2199, ptr %t2213
  call void @__inc_ref(ptr %t2201)
  %t2214 = getelementptr ptr, ptr %t2210, i32 2
  store ptr %t2201, ptr %t2214
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2207
reuse.join.2207:
  %t2215 = phi ptr [ %t5, %reuse.in_place.2205 ], [ %t2210, %reuse.copy.2206 ]
  %t2216 = call ptr @__alloc(i64 16, i32 1)
  %t2217 = inttoptr i64 265 to ptr
  %t2218 = getelementptr ptr, ptr %t2216, i32 0
  store ptr %t2217, ptr %t2218
  call void @__inc_ref(ptr %t6)
  %t2219 = getelementptr ptr, ptr %t2216, i32 1
  store ptr %t6, ptr %t2219
  call void @__free_recursive(ptr %t6)
  store ptr %t2215, ptr %t3
  store ptr %t2216, ptr %t4
  br label %tco.loop.0
tco.case.arm.135.2220:
  %t2221 = getelementptr ptr, ptr %t5, i32 1
  %t2222 = load ptr, ptr %t2221
  %t2223 = getelementptr ptr, ptr %t5, i32 2
  %t2224 = load ptr, ptr %t2223
  %t2225 = getelementptr i8, ptr %t5, i64 -8
  %t2226 = load i32, ptr %t2225
  %t2227 = icmp eq i32 %t2226, 1
  br i1 %t2227, label %reuse.in_place.2228, label %reuse.copy.2229
reuse.in_place.2228:
  %t2231 = inttoptr i64 105 to ptr
  %t2232 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2231, ptr %t2232
  br label %reuse.join.2230
reuse.copy.2229:
  %t2233 = call ptr @__alloc(i64 24, i32 2)
  %t2234 = inttoptr i64 105 to ptr
  %t2235 = getelementptr ptr, ptr %t2233, i32 0
  store ptr %t2234, ptr %t2235
  call void @__inc_ref(ptr %t2222)
  %t2236 = getelementptr ptr, ptr %t2233, i32 1
  store ptr %t2222, ptr %t2236
  call void @__inc_ref(ptr %t2224)
  %t2237 = getelementptr ptr, ptr %t2233, i32 2
  store ptr %t2224, ptr %t2237
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2230
reuse.join.2230:
  %t2238 = phi ptr [ %t5, %reuse.in_place.2228 ], [ %t2233, %reuse.copy.2229 ]
  %t2239 = call ptr @__alloc(i64 16, i32 1)
  %t2240 = inttoptr i64 266 to ptr
  %t2241 = getelementptr ptr, ptr %t2239, i32 0
  store ptr %t2240, ptr %t2241
  call void @__inc_ref(ptr %t6)
  %t2242 = getelementptr ptr, ptr %t2239, i32 1
  store ptr %t6, ptr %t2242
  call void @__free_recursive(ptr %t6)
  store ptr %t2238, ptr %t3
  store ptr %t2239, ptr %t4
  br label %tco.loop.0
tco.case.arm.136.2243:
  %t2244 = getelementptr ptr, ptr %t5, i32 1
  %t2245 = load ptr, ptr %t2244
  %t2246 = getelementptr ptr, ptr %t5, i32 2
  %t2247 = load ptr, ptr %t2246
  %t2248 = getelementptr i8, ptr %t5, i64 -8
  %t2249 = load i32, ptr %t2248
  %t2250 = icmp eq i32 %t2249, 1
  br i1 %t2250, label %reuse.in_place.2251, label %reuse.copy.2252
reuse.in_place.2251:
  %t2254 = inttoptr i64 105 to ptr
  %t2255 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2254, ptr %t2255
  br label %reuse.join.2253
reuse.copy.2252:
  %t2256 = call ptr @__alloc(i64 24, i32 2)
  %t2257 = inttoptr i64 105 to ptr
  %t2258 = getelementptr ptr, ptr %t2256, i32 0
  store ptr %t2257, ptr %t2258
  call void @__inc_ref(ptr %t2245)
  %t2259 = getelementptr ptr, ptr %t2256, i32 1
  store ptr %t2245, ptr %t2259
  call void @__inc_ref(ptr %t2247)
  %t2260 = getelementptr ptr, ptr %t2256, i32 2
  store ptr %t2247, ptr %t2260
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2253
reuse.join.2253:
  %t2261 = phi ptr [ %t5, %reuse.in_place.2251 ], [ %t2256, %reuse.copy.2252 ]
  %t2262 = call ptr @__alloc(i64 16, i32 1)
  %t2263 = inttoptr i64 267 to ptr
  %t2264 = getelementptr ptr, ptr %t2262, i32 0
  store ptr %t2263, ptr %t2264
  call void @__inc_ref(ptr %t6)
  %t2265 = getelementptr ptr, ptr %t2262, i32 1
  store ptr %t6, ptr %t2265
  call void @__free_recursive(ptr %t6)
  store ptr %t2261, ptr %t3
  store ptr %t2262, ptr %t4
  br label %tco.loop.0
tco.case.arm.137.2266:
  %t2267 = getelementptr ptr, ptr %t5, i32 1
  %t2268 = load ptr, ptr %t2267
  %t2269 = getelementptr ptr, ptr %t5, i32 2
  %t2270 = load ptr, ptr %t2269
  %t2271 = getelementptr i8, ptr %t5, i64 -8
  %t2272 = load i32, ptr %t2271
  %t2273 = icmp eq i32 %t2272, 1
  br i1 %t2273, label %reuse.in_place.2274, label %reuse.copy.2275
reuse.in_place.2274:
  %t2277 = inttoptr i64 105 to ptr
  %t2278 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2277, ptr %t2278
  br label %reuse.join.2276
reuse.copy.2275:
  %t2279 = call ptr @__alloc(i64 24, i32 2)
  %t2280 = inttoptr i64 105 to ptr
  %t2281 = getelementptr ptr, ptr %t2279, i32 0
  store ptr %t2280, ptr %t2281
  call void @__inc_ref(ptr %t2268)
  %t2282 = getelementptr ptr, ptr %t2279, i32 1
  store ptr %t2268, ptr %t2282
  call void @__inc_ref(ptr %t2270)
  %t2283 = getelementptr ptr, ptr %t2279, i32 2
  store ptr %t2270, ptr %t2283
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2276
reuse.join.2276:
  %t2284 = phi ptr [ %t5, %reuse.in_place.2274 ], [ %t2279, %reuse.copy.2275 ]
  %t2285 = call ptr @__alloc(i64 16, i32 1)
  %t2286 = inttoptr i64 268 to ptr
  %t2287 = getelementptr ptr, ptr %t2285, i32 0
  store ptr %t2286, ptr %t2287
  call void @__inc_ref(ptr %t6)
  %t2288 = getelementptr ptr, ptr %t2285, i32 1
  store ptr %t6, ptr %t2288
  call void @__free_recursive(ptr %t6)
  store ptr %t2284, ptr %t3
  store ptr %t2285, ptr %t4
  br label %tco.loop.0
tco.case.arm.138.2289:
  %t2290 = getelementptr ptr, ptr %t5, i32 1
  %t2291 = load ptr, ptr %t2290
  %t2292 = getelementptr ptr, ptr %t5, i32 2
  %t2293 = load ptr, ptr %t2292
  %t2294 = getelementptr i8, ptr %t5, i64 -8
  %t2295 = load i32, ptr %t2294
  %t2296 = icmp eq i32 %t2295, 1
  br i1 %t2296, label %reuse.in_place.2297, label %reuse.copy.2298
reuse.in_place.2297:
  %t2300 = inttoptr i64 105 to ptr
  %t2301 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2300, ptr %t2301
  br label %reuse.join.2299
reuse.copy.2298:
  %t2302 = call ptr @__alloc(i64 24, i32 2)
  %t2303 = inttoptr i64 105 to ptr
  %t2304 = getelementptr ptr, ptr %t2302, i32 0
  store ptr %t2303, ptr %t2304
  call void @__inc_ref(ptr %t2291)
  %t2305 = getelementptr ptr, ptr %t2302, i32 1
  store ptr %t2291, ptr %t2305
  call void @__inc_ref(ptr %t2293)
  %t2306 = getelementptr ptr, ptr %t2302, i32 2
  store ptr %t2293, ptr %t2306
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2299
reuse.join.2299:
  %t2307 = phi ptr [ %t5, %reuse.in_place.2297 ], [ %t2302, %reuse.copy.2298 ]
  %t2308 = call ptr @__alloc(i64 16, i32 1)
  %t2309 = inttoptr i64 269 to ptr
  %t2310 = getelementptr ptr, ptr %t2308, i32 0
  store ptr %t2309, ptr %t2310
  call void @__inc_ref(ptr %t6)
  %t2311 = getelementptr ptr, ptr %t2308, i32 1
  store ptr %t6, ptr %t2311
  call void @__free_recursive(ptr %t6)
  store ptr %t2307, ptr %t3
  store ptr %t2308, ptr %t4
  br label %tco.loop.0
tco.case.arm.139.2312:
  %t2313 = getelementptr ptr, ptr %t5, i32 1
  %t2314 = load ptr, ptr %t2313
  %t2315 = getelementptr ptr, ptr %t5, i32 2
  %t2316 = load ptr, ptr %t2315
  %t2317 = getelementptr i8, ptr %t5, i64 -8
  %t2318 = load i32, ptr %t2317
  %t2319 = icmp eq i32 %t2318, 1
  br i1 %t2319, label %reuse.in_place.2320, label %reuse.copy.2321
reuse.in_place.2320:
  %t2323 = inttoptr i64 105 to ptr
  %t2324 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2323, ptr %t2324
  br label %reuse.join.2322
reuse.copy.2321:
  %t2325 = call ptr @__alloc(i64 24, i32 2)
  %t2326 = inttoptr i64 105 to ptr
  %t2327 = getelementptr ptr, ptr %t2325, i32 0
  store ptr %t2326, ptr %t2327
  call void @__inc_ref(ptr %t2314)
  %t2328 = getelementptr ptr, ptr %t2325, i32 1
  store ptr %t2314, ptr %t2328
  call void @__inc_ref(ptr %t2316)
  %t2329 = getelementptr ptr, ptr %t2325, i32 2
  store ptr %t2316, ptr %t2329
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2322
reuse.join.2322:
  %t2330 = phi ptr [ %t5, %reuse.in_place.2320 ], [ %t2325, %reuse.copy.2321 ]
  %t2331 = call ptr @__alloc(i64 16, i32 1)
  %t2332 = inttoptr i64 270 to ptr
  %t2333 = getelementptr ptr, ptr %t2331, i32 0
  store ptr %t2332, ptr %t2333
  call void @__inc_ref(ptr %t6)
  %t2334 = getelementptr ptr, ptr %t2331, i32 1
  store ptr %t6, ptr %t2334
  call void @__free_recursive(ptr %t6)
  store ptr %t2330, ptr %t3
  store ptr %t2331, ptr %t4
  br label %tco.loop.0
tco.case.arm.140.2335:
  %t2336 = getelementptr ptr, ptr %t5, i32 1
  %t2337 = load ptr, ptr %t2336
  call void @__inc_ref(ptr %t2337)
  %t2338 = getelementptr ptr, ptr %t5, i32 2
  %t2339 = load ptr, ptr %t2338
  call void @__inc_ref(ptr %t2339)
  %t2340 = getelementptr ptr, ptr %t5, i32 3
  %t2341 = load ptr, ptr %t2340
  call void @__inc_ref(ptr %t2341)
  %t2342 = call ptr @__alloc(i64 24, i32 2)
  %t2343 = inttoptr i64 105 to ptr
  %t2344 = getelementptr ptr, ptr %t2342, i32 0
  store ptr %t2343, ptr %t2344
  call void @__inc_ref(ptr %t2337)
  %t2345 = getelementptr ptr, ptr %t2342, i32 1
  store ptr %t2337, ptr %t2345
  call void @__inc_ref(ptr %t2339)
  %t2346 = getelementptr ptr, ptr %t2342, i32 2
  store ptr %t2339, ptr %t2346
  %t2347 = call ptr @__alloc(i64 24, i32 2)
  %t2348 = inttoptr i64 271 to ptr
  %t2349 = getelementptr ptr, ptr %t2347, i32 0
  store ptr %t2348, ptr %t2349
  call void @__inc_ref(ptr %t6)
  %t2350 = getelementptr ptr, ptr %t2347, i32 1
  store ptr %t6, ptr %t2350
  call void @__inc_ref(ptr %t2341)
  %t2351 = getelementptr ptr, ptr %t2347, i32 2
  store ptr %t2341, ptr %t2351
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t2341)
  call void @__free_recursive(ptr %t2339)
  call void @__free_recursive(ptr %t2337)
  store ptr %t2342, ptr %t3
  store ptr %t2347, ptr %t4
  br label %tco.loop.0
tco.case.arm.141.2352:
  %t2353 = getelementptr ptr, ptr %t5, i32 1
  %t2354 = load ptr, ptr %t2353
  %t2355 = getelementptr ptr, ptr %t5, i32 2
  %t2356 = load ptr, ptr %t2355
  %t2357 = getelementptr i8, ptr %t5, i64 -8
  %t2358 = load i32, ptr %t2357
  %t2359 = icmp eq i32 %t2358, 1
  br i1 %t2359, label %reuse.in_place.2360, label %reuse.copy.2361
reuse.in_place.2360:
  %t2363 = inttoptr i64 105 to ptr
  %t2364 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2363, ptr %t2364
  br label %reuse.join.2362
reuse.copy.2361:
  %t2365 = call ptr @__alloc(i64 24, i32 2)
  %t2366 = inttoptr i64 105 to ptr
  %t2367 = getelementptr ptr, ptr %t2365, i32 0
  store ptr %t2366, ptr %t2367
  call void @__inc_ref(ptr %t2354)
  %t2368 = getelementptr ptr, ptr %t2365, i32 1
  store ptr %t2354, ptr %t2368
  call void @__inc_ref(ptr %t2356)
  %t2369 = getelementptr ptr, ptr %t2365, i32 2
  store ptr %t2356, ptr %t2369
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2362
reuse.join.2362:
  %t2370 = phi ptr [ %t5, %reuse.in_place.2360 ], [ %t2365, %reuse.copy.2361 ]
  %t2371 = call ptr @__alloc(i64 16, i32 1)
  %t2372 = inttoptr i64 272 to ptr
  %t2373 = getelementptr ptr, ptr %t2371, i32 0
  store ptr %t2372, ptr %t2373
  call void @__inc_ref(ptr %t6)
  %t2374 = getelementptr ptr, ptr %t2371, i32 1
  store ptr %t6, ptr %t2374
  call void @__free_recursive(ptr %t6)
  store ptr %t2370, ptr %t3
  store ptr %t2371, ptr %t4
  br label %tco.loop.0
tco.case.arm.142.2375:
  %t2376 = getelementptr ptr, ptr %t5, i32 1
  %t2377 = load ptr, ptr %t2376
  %t2378 = getelementptr ptr, ptr %t5, i32 2
  %t2379 = load ptr, ptr %t2378
  %t2380 = getelementptr i8, ptr %t5, i64 -8
  %t2381 = load i32, ptr %t2380
  %t2382 = icmp eq i32 %t2381, 1
  br i1 %t2382, label %reuse.in_place.2383, label %reuse.copy.2384
reuse.in_place.2383:
  %t2386 = inttoptr i64 105 to ptr
  %t2387 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2386, ptr %t2387
  br label %reuse.join.2385
reuse.copy.2384:
  %t2388 = call ptr @__alloc(i64 24, i32 2)
  %t2389 = inttoptr i64 105 to ptr
  %t2390 = getelementptr ptr, ptr %t2388, i32 0
  store ptr %t2389, ptr %t2390
  call void @__inc_ref(ptr %t2377)
  %t2391 = getelementptr ptr, ptr %t2388, i32 1
  store ptr %t2377, ptr %t2391
  call void @__inc_ref(ptr %t2379)
  %t2392 = getelementptr ptr, ptr %t2388, i32 2
  store ptr %t2379, ptr %t2392
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2385
reuse.join.2385:
  %t2393 = phi ptr [ %t5, %reuse.in_place.2383 ], [ %t2388, %reuse.copy.2384 ]
  %t2394 = call ptr @__alloc(i64 16, i32 1)
  %t2395 = inttoptr i64 273 to ptr
  %t2396 = getelementptr ptr, ptr %t2394, i32 0
  store ptr %t2395, ptr %t2396
  call void @__inc_ref(ptr %t6)
  %t2397 = getelementptr ptr, ptr %t2394, i32 1
  store ptr %t6, ptr %t2397
  call void @__free_recursive(ptr %t6)
  store ptr %t2393, ptr %t3
  store ptr %t2394, ptr %t4
  br label %tco.loop.0
tco.case.arm.143.2398:
  %t2399 = getelementptr ptr, ptr %t5, i32 1
  %t2400 = load ptr, ptr %t2399
  %t2401 = getelementptr ptr, ptr %t5, i32 2
  %t2402 = load ptr, ptr %t2401
  %t2403 = getelementptr i8, ptr %t5, i64 -8
  %t2404 = load i32, ptr %t2403
  %t2405 = icmp eq i32 %t2404, 1
  br i1 %t2405, label %reuse.in_place.2406, label %reuse.copy.2407
reuse.in_place.2406:
  %t2409 = inttoptr i64 105 to ptr
  %t2410 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2409, ptr %t2410
  br label %reuse.join.2408
reuse.copy.2407:
  %t2411 = call ptr @__alloc(i64 24, i32 2)
  %t2412 = inttoptr i64 105 to ptr
  %t2413 = getelementptr ptr, ptr %t2411, i32 0
  store ptr %t2412, ptr %t2413
  call void @__inc_ref(ptr %t2400)
  %t2414 = getelementptr ptr, ptr %t2411, i32 1
  store ptr %t2400, ptr %t2414
  call void @__inc_ref(ptr %t2402)
  %t2415 = getelementptr ptr, ptr %t2411, i32 2
  store ptr %t2402, ptr %t2415
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2408
reuse.join.2408:
  %t2416 = phi ptr [ %t5, %reuse.in_place.2406 ], [ %t2411, %reuse.copy.2407 ]
  %t2417 = call ptr @__alloc(i64 16, i32 1)
  %t2418 = inttoptr i64 274 to ptr
  %t2419 = getelementptr ptr, ptr %t2417, i32 0
  store ptr %t2418, ptr %t2419
  call void @__inc_ref(ptr %t6)
  %t2420 = getelementptr ptr, ptr %t2417, i32 1
  store ptr %t6, ptr %t2420
  call void @__free_recursive(ptr %t6)
  store ptr %t2416, ptr %t3
  store ptr %t2417, ptr %t4
  br label %tco.loop.0
tco.case.arm.144.2421:
  %t2422 = getelementptr ptr, ptr %t5, i32 1
  %t2423 = load ptr, ptr %t2422
  %t2424 = getelementptr ptr, ptr %t5, i32 2
  %t2425 = load ptr, ptr %t2424
  %t2426 = getelementptr i8, ptr %t5, i64 -8
  %t2427 = load i32, ptr %t2426
  %t2428 = icmp eq i32 %t2427, 1
  br i1 %t2428, label %reuse.in_place.2429, label %reuse.copy.2430
reuse.in_place.2429:
  %t2432 = inttoptr i64 105 to ptr
  %t2433 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2432, ptr %t2433
  br label %reuse.join.2431
reuse.copy.2430:
  %t2434 = call ptr @__alloc(i64 24, i32 2)
  %t2435 = inttoptr i64 105 to ptr
  %t2436 = getelementptr ptr, ptr %t2434, i32 0
  store ptr %t2435, ptr %t2436
  call void @__inc_ref(ptr %t2423)
  %t2437 = getelementptr ptr, ptr %t2434, i32 1
  store ptr %t2423, ptr %t2437
  call void @__inc_ref(ptr %t2425)
  %t2438 = getelementptr ptr, ptr %t2434, i32 2
  store ptr %t2425, ptr %t2438
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2431
reuse.join.2431:
  %t2439 = phi ptr [ %t5, %reuse.in_place.2429 ], [ %t2434, %reuse.copy.2430 ]
  %t2440 = call ptr @__alloc(i64 16, i32 1)
  %t2441 = inttoptr i64 275 to ptr
  %t2442 = getelementptr ptr, ptr %t2440, i32 0
  store ptr %t2441, ptr %t2442
  call void @__inc_ref(ptr %t6)
  %t2443 = getelementptr ptr, ptr %t2440, i32 1
  store ptr %t6, ptr %t2443
  call void @__free_recursive(ptr %t6)
  store ptr %t2439, ptr %t3
  store ptr %t2440, ptr %t4
  br label %tco.loop.0
tco.case.arm.145.2444:
  %t2445 = getelementptr ptr, ptr %t5, i32 1
  %t2446 = load ptr, ptr %t2445
  %t2447 = getelementptr ptr, ptr %t5, i32 2
  %t2448 = load ptr, ptr %t2447
  %t2449 = getelementptr i8, ptr %t5, i64 -8
  %t2450 = load i32, ptr %t2449
  %t2451 = icmp eq i32 %t2450, 1
  br i1 %t2451, label %reuse.in_place.2452, label %reuse.copy.2453
reuse.in_place.2452:
  %t2455 = inttoptr i64 105 to ptr
  %t2456 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2455, ptr %t2456
  br label %reuse.join.2454
reuse.copy.2453:
  %t2457 = call ptr @__alloc(i64 24, i32 2)
  %t2458 = inttoptr i64 105 to ptr
  %t2459 = getelementptr ptr, ptr %t2457, i32 0
  store ptr %t2458, ptr %t2459
  call void @__inc_ref(ptr %t2446)
  %t2460 = getelementptr ptr, ptr %t2457, i32 1
  store ptr %t2446, ptr %t2460
  call void @__inc_ref(ptr %t2448)
  %t2461 = getelementptr ptr, ptr %t2457, i32 2
  store ptr %t2448, ptr %t2461
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2454
reuse.join.2454:
  %t2462 = phi ptr [ %t5, %reuse.in_place.2452 ], [ %t2457, %reuse.copy.2453 ]
  %t2463 = call ptr @__alloc(i64 16, i32 1)
  %t2464 = inttoptr i64 276 to ptr
  %t2465 = getelementptr ptr, ptr %t2463, i32 0
  store ptr %t2464, ptr %t2465
  call void @__inc_ref(ptr %t6)
  %t2466 = getelementptr ptr, ptr %t2463, i32 1
  store ptr %t6, ptr %t2466
  call void @__free_recursive(ptr %t6)
  store ptr %t2462, ptr %t3
  store ptr %t2463, ptr %t4
  br label %tco.loop.0
tco.case.arm.146.2467:
  %t2468 = getelementptr ptr, ptr %t5, i32 1
  %t2469 = load ptr, ptr %t2468
  %t2470 = getelementptr ptr, ptr %t5, i32 2
  %t2471 = load ptr, ptr %t2470
  %t2472 = getelementptr i8, ptr %t5, i64 -8
  %t2473 = load i32, ptr %t2472
  %t2474 = icmp eq i32 %t2473, 1
  br i1 %t2474, label %reuse.in_place.2475, label %reuse.copy.2476
reuse.in_place.2475:
  %t2478 = inttoptr i64 105 to ptr
  %t2479 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2478, ptr %t2479
  br label %reuse.join.2477
reuse.copy.2476:
  %t2480 = call ptr @__alloc(i64 24, i32 2)
  %t2481 = inttoptr i64 105 to ptr
  %t2482 = getelementptr ptr, ptr %t2480, i32 0
  store ptr %t2481, ptr %t2482
  call void @__inc_ref(ptr %t2469)
  %t2483 = getelementptr ptr, ptr %t2480, i32 1
  store ptr %t2469, ptr %t2483
  call void @__inc_ref(ptr %t2471)
  %t2484 = getelementptr ptr, ptr %t2480, i32 2
  store ptr %t2471, ptr %t2484
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2477
reuse.join.2477:
  %t2485 = phi ptr [ %t5, %reuse.in_place.2475 ], [ %t2480, %reuse.copy.2476 ]
  %t2486 = call ptr @__alloc(i64 16, i32 1)
  %t2487 = inttoptr i64 277 to ptr
  %t2488 = getelementptr ptr, ptr %t2486, i32 0
  store ptr %t2487, ptr %t2488
  call void @__inc_ref(ptr %t6)
  %t2489 = getelementptr ptr, ptr %t2486, i32 1
  store ptr %t6, ptr %t2489
  call void @__free_recursive(ptr %t6)
  store ptr %t2485, ptr %t3
  store ptr %t2486, ptr %t4
  br label %tco.loop.0
tco.case.arm.147.2490:
  %t2491 = getelementptr ptr, ptr %t5, i32 1
  %t2492 = load ptr, ptr %t2491
  %t2493 = getelementptr ptr, ptr %t5, i32 2
  %t2494 = load ptr, ptr %t2493
  %t2495 = getelementptr i8, ptr %t5, i64 -8
  %t2496 = load i32, ptr %t2495
  %t2497 = icmp eq i32 %t2496, 1
  br i1 %t2497, label %reuse.in_place.2498, label %reuse.copy.2499
reuse.in_place.2498:
  %t2501 = inttoptr i64 105 to ptr
  %t2502 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2501, ptr %t2502
  br label %reuse.join.2500
reuse.copy.2499:
  %t2503 = call ptr @__alloc(i64 24, i32 2)
  %t2504 = inttoptr i64 105 to ptr
  %t2505 = getelementptr ptr, ptr %t2503, i32 0
  store ptr %t2504, ptr %t2505
  call void @__inc_ref(ptr %t2492)
  %t2506 = getelementptr ptr, ptr %t2503, i32 1
  store ptr %t2492, ptr %t2506
  call void @__inc_ref(ptr %t2494)
  %t2507 = getelementptr ptr, ptr %t2503, i32 2
  store ptr %t2494, ptr %t2507
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2500
reuse.join.2500:
  %t2508 = phi ptr [ %t5, %reuse.in_place.2498 ], [ %t2503, %reuse.copy.2499 ]
  %t2509 = call ptr @__alloc(i64 16, i32 1)
  %t2510 = inttoptr i64 278 to ptr
  %t2511 = getelementptr ptr, ptr %t2509, i32 0
  store ptr %t2510, ptr %t2511
  call void @__inc_ref(ptr %t6)
  %t2512 = getelementptr ptr, ptr %t2509, i32 1
  store ptr %t6, ptr %t2512
  call void @__free_recursive(ptr %t6)
  store ptr %t2508, ptr %t3
  store ptr %t2509, ptr %t4
  br label %tco.loop.0
tco.case.arm.148.2513:
  %t2514 = getelementptr ptr, ptr %t5, i32 1
  %t2515 = load ptr, ptr %t2514
  %t2516 = getelementptr ptr, ptr %t5, i32 2
  %t2517 = load ptr, ptr %t2516
  %t2518 = getelementptr i8, ptr %t5, i64 -8
  %t2519 = load i32, ptr %t2518
  %t2520 = icmp eq i32 %t2519, 1
  br i1 %t2520, label %reuse.in_place.2521, label %reuse.copy.2522
reuse.in_place.2521:
  %t2524 = inttoptr i64 105 to ptr
  %t2525 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2524, ptr %t2525
  br label %reuse.join.2523
reuse.copy.2522:
  %t2526 = call ptr @__alloc(i64 24, i32 2)
  %t2527 = inttoptr i64 105 to ptr
  %t2528 = getelementptr ptr, ptr %t2526, i32 0
  store ptr %t2527, ptr %t2528
  call void @__inc_ref(ptr %t2515)
  %t2529 = getelementptr ptr, ptr %t2526, i32 1
  store ptr %t2515, ptr %t2529
  call void @__inc_ref(ptr %t2517)
  %t2530 = getelementptr ptr, ptr %t2526, i32 2
  store ptr %t2517, ptr %t2530
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2523
reuse.join.2523:
  %t2531 = phi ptr [ %t5, %reuse.in_place.2521 ], [ %t2526, %reuse.copy.2522 ]
  %t2532 = call ptr @__alloc(i64 16, i32 1)
  %t2533 = inttoptr i64 279 to ptr
  %t2534 = getelementptr ptr, ptr %t2532, i32 0
  store ptr %t2533, ptr %t2534
  call void @__inc_ref(ptr %t6)
  %t2535 = getelementptr ptr, ptr %t2532, i32 1
  store ptr %t6, ptr %t2535
  call void @__free_recursive(ptr %t6)
  store ptr %t2531, ptr %t3
  store ptr %t2532, ptr %t4
  br label %tco.loop.0
tco.case.arm.149.2536:
  %t2537 = getelementptr ptr, ptr %t5, i32 1
  %t2538 = load ptr, ptr %t2537
  %t2539 = getelementptr ptr, ptr %t5, i32 2
  %t2540 = load ptr, ptr %t2539
  %t2541 = getelementptr i8, ptr %t5, i64 -8
  %t2542 = load i32, ptr %t2541
  %t2543 = icmp eq i32 %t2542, 1
  br i1 %t2543, label %reuse.in_place.2544, label %reuse.copy.2545
reuse.in_place.2544:
  %t2547 = inttoptr i64 105 to ptr
  %t2548 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2547, ptr %t2548
  br label %reuse.join.2546
reuse.copy.2545:
  %t2549 = call ptr @__alloc(i64 24, i32 2)
  %t2550 = inttoptr i64 105 to ptr
  %t2551 = getelementptr ptr, ptr %t2549, i32 0
  store ptr %t2550, ptr %t2551
  call void @__inc_ref(ptr %t2538)
  %t2552 = getelementptr ptr, ptr %t2549, i32 1
  store ptr %t2538, ptr %t2552
  call void @__inc_ref(ptr %t2540)
  %t2553 = getelementptr ptr, ptr %t2549, i32 2
  store ptr %t2540, ptr %t2553
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2546
reuse.join.2546:
  %t2554 = phi ptr [ %t5, %reuse.in_place.2544 ], [ %t2549, %reuse.copy.2545 ]
  %t2555 = call ptr @__alloc(i64 16, i32 1)
  %t2556 = inttoptr i64 280 to ptr
  %t2557 = getelementptr ptr, ptr %t2555, i32 0
  store ptr %t2556, ptr %t2557
  call void @__inc_ref(ptr %t6)
  %t2558 = getelementptr ptr, ptr %t2555, i32 1
  store ptr %t6, ptr %t2558
  call void @__free_recursive(ptr %t6)
  store ptr %t2554, ptr %t3
  store ptr %t2555, ptr %t4
  br label %tco.loop.0
tco.case.arm.150.2559:
  %t2560 = getelementptr ptr, ptr %t5, i32 1
  %t2561 = load ptr, ptr %t2560
  %t2562 = getelementptr ptr, ptr %t5, i32 2
  %t2563 = load ptr, ptr %t2562
  %t2564 = getelementptr i8, ptr %t5, i64 -8
  %t2565 = load i32, ptr %t2564
  %t2566 = icmp eq i32 %t2565, 1
  br i1 %t2566, label %reuse.in_place.2567, label %reuse.copy.2568
reuse.in_place.2567:
  %t2570 = inttoptr i64 105 to ptr
  %t2571 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2570, ptr %t2571
  br label %reuse.join.2569
reuse.copy.2568:
  %t2572 = call ptr @__alloc(i64 24, i32 2)
  %t2573 = inttoptr i64 105 to ptr
  %t2574 = getelementptr ptr, ptr %t2572, i32 0
  store ptr %t2573, ptr %t2574
  call void @__inc_ref(ptr %t2561)
  %t2575 = getelementptr ptr, ptr %t2572, i32 1
  store ptr %t2561, ptr %t2575
  call void @__inc_ref(ptr %t2563)
  %t2576 = getelementptr ptr, ptr %t2572, i32 2
  store ptr %t2563, ptr %t2576
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2569
reuse.join.2569:
  %t2577 = phi ptr [ %t5, %reuse.in_place.2567 ], [ %t2572, %reuse.copy.2568 ]
  %t2578 = call ptr @__alloc(i64 16, i32 1)
  %t2579 = inttoptr i64 281 to ptr
  %t2580 = getelementptr ptr, ptr %t2578, i32 0
  store ptr %t2579, ptr %t2580
  call void @__inc_ref(ptr %t6)
  %t2581 = getelementptr ptr, ptr %t2578, i32 1
  store ptr %t6, ptr %t2581
  call void @__free_recursive(ptr %t6)
  store ptr %t2577, ptr %t3
  store ptr %t2578, ptr %t4
  br label %tco.loop.0
tco.case.arm.151.2582:
  %t2583 = getelementptr ptr, ptr %t5, i32 1
  %t2584 = load ptr, ptr %t2583
  %t2585 = getelementptr ptr, ptr %t5, i32 2
  %t2586 = load ptr, ptr %t2585
  %t2587 = getelementptr i8, ptr %t5, i64 -8
  %t2588 = load i32, ptr %t2587
  %t2589 = icmp eq i32 %t2588, 1
  br i1 %t2589, label %reuse.in_place.2590, label %reuse.copy.2591
reuse.in_place.2590:
  %t2593 = inttoptr i64 105 to ptr
  %t2594 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2593, ptr %t2594
  br label %reuse.join.2592
reuse.copy.2591:
  %t2595 = call ptr @__alloc(i64 24, i32 2)
  %t2596 = inttoptr i64 105 to ptr
  %t2597 = getelementptr ptr, ptr %t2595, i32 0
  store ptr %t2596, ptr %t2597
  call void @__inc_ref(ptr %t2584)
  %t2598 = getelementptr ptr, ptr %t2595, i32 1
  store ptr %t2584, ptr %t2598
  call void @__inc_ref(ptr %t2586)
  %t2599 = getelementptr ptr, ptr %t2595, i32 2
  store ptr %t2586, ptr %t2599
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2592
reuse.join.2592:
  %t2600 = phi ptr [ %t5, %reuse.in_place.2590 ], [ %t2595, %reuse.copy.2591 ]
  %t2601 = call ptr @__alloc(i64 16, i32 1)
  %t2602 = inttoptr i64 282 to ptr
  %t2603 = getelementptr ptr, ptr %t2601, i32 0
  store ptr %t2602, ptr %t2603
  call void @__inc_ref(ptr %t6)
  %t2604 = getelementptr ptr, ptr %t2601, i32 1
  store ptr %t6, ptr %t2604
  call void @__free_recursive(ptr %t6)
  store ptr %t2600, ptr %t3
  store ptr %t2601, ptr %t4
  br label %tco.loop.0
tco.case.arm.152.2605:
  %t2606 = getelementptr ptr, ptr %t5, i32 1
  %t2607 = load ptr, ptr %t2606
  %t2608 = getelementptr ptr, ptr %t5, i32 2
  %t2609 = load ptr, ptr %t2608
  %t2610 = getelementptr i8, ptr %t5, i64 -8
  %t2611 = load i32, ptr %t2610
  %t2612 = icmp eq i32 %t2611, 1
  br i1 %t2612, label %reuse.in_place.2613, label %reuse.copy.2614
reuse.in_place.2613:
  %t2616 = inttoptr i64 105 to ptr
  %t2617 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2616, ptr %t2617
  br label %reuse.join.2615
reuse.copy.2614:
  %t2618 = call ptr @__alloc(i64 24, i32 2)
  %t2619 = inttoptr i64 105 to ptr
  %t2620 = getelementptr ptr, ptr %t2618, i32 0
  store ptr %t2619, ptr %t2620
  call void @__inc_ref(ptr %t2607)
  %t2621 = getelementptr ptr, ptr %t2618, i32 1
  store ptr %t2607, ptr %t2621
  call void @__inc_ref(ptr %t2609)
  %t2622 = getelementptr ptr, ptr %t2618, i32 2
  store ptr %t2609, ptr %t2622
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2615
reuse.join.2615:
  %t2623 = phi ptr [ %t5, %reuse.in_place.2613 ], [ %t2618, %reuse.copy.2614 ]
  %t2624 = call ptr @__alloc(i64 16, i32 1)
  %t2625 = inttoptr i64 283 to ptr
  %t2626 = getelementptr ptr, ptr %t2624, i32 0
  store ptr %t2625, ptr %t2626
  call void @__inc_ref(ptr %t6)
  %t2627 = getelementptr ptr, ptr %t2624, i32 1
  store ptr %t6, ptr %t2627
  call void @__free_recursive(ptr %t6)
  store ptr %t2623, ptr %t3
  store ptr %t2624, ptr %t4
  br label %tco.loop.0
tco.case.arm.153.2628:
  %t2629 = getelementptr ptr, ptr %t5, i32 1
  %t2630 = load ptr, ptr %t2629
  call void @__inc_ref(ptr %t2630)
  %t2631 = getelementptr ptr, ptr %t5, i32 2
  %t2632 = load ptr, ptr %t2631
  call void @__inc_ref(ptr %t2632)
  %t2633 = getelementptr ptr, ptr %t5, i32 3
  %t2634 = load ptr, ptr %t2633
  call void @__inc_ref(ptr %t2634)
  %t2635 = call ptr @__alloc(i64 24, i32 2)
  %t2636 = inttoptr i64 105 to ptr
  %t2637 = getelementptr ptr, ptr %t2635, i32 0
  store ptr %t2636, ptr %t2637
  call void @__inc_ref(ptr %t2630)
  %t2638 = getelementptr ptr, ptr %t2635, i32 1
  store ptr %t2630, ptr %t2638
  call void @__inc_ref(ptr %t2632)
  %t2639 = getelementptr ptr, ptr %t2635, i32 2
  store ptr %t2632, ptr %t2639
  %t2640 = call ptr @__alloc(i64 24, i32 2)
  %t2641 = inttoptr i64 284 to ptr
  %t2642 = getelementptr ptr, ptr %t2640, i32 0
  store ptr %t2641, ptr %t2642
  call void @__inc_ref(ptr %t6)
  %t2643 = getelementptr ptr, ptr %t2640, i32 1
  store ptr %t6, ptr %t2643
  call void @__inc_ref(ptr %t2634)
  %t2644 = getelementptr ptr, ptr %t2640, i32 2
  store ptr %t2634, ptr %t2644
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t2634)
  call void @__free_recursive(ptr %t2632)
  call void @__free_recursive(ptr %t2630)
  store ptr %t2635, ptr %t3
  store ptr %t2640, ptr %t4
  br label %tco.loop.0
tco.case.arm.154.2645:
  %t2646 = getelementptr ptr, ptr %t5, i32 1
  %t2647 = load ptr, ptr %t2646
  %t2648 = getelementptr ptr, ptr %t5, i32 2
  %t2649 = load ptr, ptr %t2648
  %t2650 = getelementptr i8, ptr %t5, i64 -8
  %t2651 = load i32, ptr %t2650
  %t2652 = icmp eq i32 %t2651, 1
  br i1 %t2652, label %reuse.in_place.2653, label %reuse.copy.2654
reuse.in_place.2653:
  %t2656 = inttoptr i64 105 to ptr
  %t2657 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2656, ptr %t2657
  br label %reuse.join.2655
reuse.copy.2654:
  %t2658 = call ptr @__alloc(i64 24, i32 2)
  %t2659 = inttoptr i64 105 to ptr
  %t2660 = getelementptr ptr, ptr %t2658, i32 0
  store ptr %t2659, ptr %t2660
  call void @__inc_ref(ptr %t2647)
  %t2661 = getelementptr ptr, ptr %t2658, i32 1
  store ptr %t2647, ptr %t2661
  call void @__inc_ref(ptr %t2649)
  %t2662 = getelementptr ptr, ptr %t2658, i32 2
  store ptr %t2649, ptr %t2662
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2655
reuse.join.2655:
  %t2663 = phi ptr [ %t5, %reuse.in_place.2653 ], [ %t2658, %reuse.copy.2654 ]
  %t2664 = call ptr @__alloc(i64 16, i32 1)
  %t2665 = inttoptr i64 285 to ptr
  %t2666 = getelementptr ptr, ptr %t2664, i32 0
  store ptr %t2665, ptr %t2666
  call void @__inc_ref(ptr %t6)
  %t2667 = getelementptr ptr, ptr %t2664, i32 1
  store ptr %t6, ptr %t2667
  call void @__free_recursive(ptr %t6)
  store ptr %t2663, ptr %t3
  store ptr %t2664, ptr %t4
  br label %tco.loop.0
tco.case.arm.155.2668:
  %t2669 = getelementptr ptr, ptr %t5, i32 1
  %t2670 = load ptr, ptr %t2669
  %t2671 = getelementptr ptr, ptr %t5, i32 2
  %t2672 = load ptr, ptr %t2671
  %t2673 = getelementptr i8, ptr %t5, i64 -8
  %t2674 = load i32, ptr %t2673
  %t2675 = icmp eq i32 %t2674, 1
  br i1 %t2675, label %reuse.in_place.2676, label %reuse.copy.2677
reuse.in_place.2676:
  %t2679 = inttoptr i64 105 to ptr
  %t2680 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2679, ptr %t2680
  br label %reuse.join.2678
reuse.copy.2677:
  %t2681 = call ptr @__alloc(i64 24, i32 2)
  %t2682 = inttoptr i64 105 to ptr
  %t2683 = getelementptr ptr, ptr %t2681, i32 0
  store ptr %t2682, ptr %t2683
  call void @__inc_ref(ptr %t2670)
  %t2684 = getelementptr ptr, ptr %t2681, i32 1
  store ptr %t2670, ptr %t2684
  call void @__inc_ref(ptr %t2672)
  %t2685 = getelementptr ptr, ptr %t2681, i32 2
  store ptr %t2672, ptr %t2685
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2678
reuse.join.2678:
  %t2686 = phi ptr [ %t5, %reuse.in_place.2676 ], [ %t2681, %reuse.copy.2677 ]
  %t2687 = call ptr @__alloc(i64 16, i32 1)
  %t2688 = inttoptr i64 286 to ptr
  %t2689 = getelementptr ptr, ptr %t2687, i32 0
  store ptr %t2688, ptr %t2689
  call void @__inc_ref(ptr %t6)
  %t2690 = getelementptr ptr, ptr %t2687, i32 1
  store ptr %t6, ptr %t2690
  call void @__free_recursive(ptr %t6)
  store ptr %t2686, ptr %t3
  store ptr %t2687, ptr %t4
  br label %tco.loop.0
tco.case.arm.156.2691:
  %t2692 = getelementptr ptr, ptr %t5, i32 1
  %t2693 = load ptr, ptr %t2692
  %t2694 = getelementptr ptr, ptr %t5, i32 2
  %t2695 = load ptr, ptr %t2694
  %t2696 = getelementptr i8, ptr %t5, i64 -8
  %t2697 = load i32, ptr %t2696
  %t2698 = icmp eq i32 %t2697, 1
  br i1 %t2698, label %reuse.in_place.2699, label %reuse.copy.2700
reuse.in_place.2699:
  %t2702 = inttoptr i64 105 to ptr
  %t2703 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2702, ptr %t2703
  br label %reuse.join.2701
reuse.copy.2700:
  %t2704 = call ptr @__alloc(i64 24, i32 2)
  %t2705 = inttoptr i64 105 to ptr
  %t2706 = getelementptr ptr, ptr %t2704, i32 0
  store ptr %t2705, ptr %t2706
  call void @__inc_ref(ptr %t2693)
  %t2707 = getelementptr ptr, ptr %t2704, i32 1
  store ptr %t2693, ptr %t2707
  call void @__inc_ref(ptr %t2695)
  %t2708 = getelementptr ptr, ptr %t2704, i32 2
  store ptr %t2695, ptr %t2708
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2701
reuse.join.2701:
  %t2709 = phi ptr [ %t5, %reuse.in_place.2699 ], [ %t2704, %reuse.copy.2700 ]
  %t2710 = call ptr @__alloc(i64 16, i32 1)
  %t2711 = inttoptr i64 287 to ptr
  %t2712 = getelementptr ptr, ptr %t2710, i32 0
  store ptr %t2711, ptr %t2712
  call void @__inc_ref(ptr %t6)
  %t2713 = getelementptr ptr, ptr %t2710, i32 1
  store ptr %t6, ptr %t2713
  call void @__free_recursive(ptr %t6)
  store ptr %t2709, ptr %t3
  store ptr %t2710, ptr %t4
  br label %tco.loop.0
tco.case.arm.157.2714:
  %t2715 = getelementptr ptr, ptr %t5, i32 1
  %t2716 = load ptr, ptr %t2715
  %t2717 = getelementptr ptr, ptr %t5, i32 2
  %t2718 = load ptr, ptr %t2717
  %t2719 = getelementptr i8, ptr %t5, i64 -8
  %t2720 = load i32, ptr %t2719
  %t2721 = icmp eq i32 %t2720, 1
  br i1 %t2721, label %reuse.in_place.2722, label %reuse.copy.2723
reuse.in_place.2722:
  %t2725 = inttoptr i64 105 to ptr
  %t2726 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2725, ptr %t2726
  br label %reuse.join.2724
reuse.copy.2723:
  %t2727 = call ptr @__alloc(i64 24, i32 2)
  %t2728 = inttoptr i64 105 to ptr
  %t2729 = getelementptr ptr, ptr %t2727, i32 0
  store ptr %t2728, ptr %t2729
  call void @__inc_ref(ptr %t2716)
  %t2730 = getelementptr ptr, ptr %t2727, i32 1
  store ptr %t2716, ptr %t2730
  call void @__inc_ref(ptr %t2718)
  %t2731 = getelementptr ptr, ptr %t2727, i32 2
  store ptr %t2718, ptr %t2731
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2724
reuse.join.2724:
  %t2732 = phi ptr [ %t5, %reuse.in_place.2722 ], [ %t2727, %reuse.copy.2723 ]
  %t2733 = call ptr @__alloc(i64 16, i32 1)
  %t2734 = inttoptr i64 288 to ptr
  %t2735 = getelementptr ptr, ptr %t2733, i32 0
  store ptr %t2734, ptr %t2735
  call void @__inc_ref(ptr %t6)
  %t2736 = getelementptr ptr, ptr %t2733, i32 1
  store ptr %t6, ptr %t2736
  call void @__free_recursive(ptr %t6)
  store ptr %t2732, ptr %t3
  store ptr %t2733, ptr %t4
  br label %tco.loop.0
tco.case.arm.158.2737:
  %t2738 = getelementptr ptr, ptr %t5, i32 1
  %t2739 = load ptr, ptr %t2738
  %t2740 = getelementptr ptr, ptr %t5, i32 2
  %t2741 = load ptr, ptr %t2740
  %t2742 = getelementptr i8, ptr %t5, i64 -8
  %t2743 = load i32, ptr %t2742
  %t2744 = icmp eq i32 %t2743, 1
  br i1 %t2744, label %reuse.in_place.2745, label %reuse.copy.2746
reuse.in_place.2745:
  %t2748 = inttoptr i64 105 to ptr
  %t2749 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2748, ptr %t2749
  br label %reuse.join.2747
reuse.copy.2746:
  %t2750 = call ptr @__alloc(i64 24, i32 2)
  %t2751 = inttoptr i64 105 to ptr
  %t2752 = getelementptr ptr, ptr %t2750, i32 0
  store ptr %t2751, ptr %t2752
  call void @__inc_ref(ptr %t2739)
  %t2753 = getelementptr ptr, ptr %t2750, i32 1
  store ptr %t2739, ptr %t2753
  call void @__inc_ref(ptr %t2741)
  %t2754 = getelementptr ptr, ptr %t2750, i32 2
  store ptr %t2741, ptr %t2754
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2747
reuse.join.2747:
  %t2755 = phi ptr [ %t5, %reuse.in_place.2745 ], [ %t2750, %reuse.copy.2746 ]
  %t2756 = call ptr @__alloc(i64 16, i32 1)
  %t2757 = inttoptr i64 289 to ptr
  %t2758 = getelementptr ptr, ptr %t2756, i32 0
  store ptr %t2757, ptr %t2758
  call void @__inc_ref(ptr %t6)
  %t2759 = getelementptr ptr, ptr %t2756, i32 1
  store ptr %t6, ptr %t2759
  call void @__free_recursive(ptr %t6)
  store ptr %t2755, ptr %t3
  store ptr %t2756, ptr %t4
  br label %tco.loop.0
tco.case.arm.159.2760:
  %t2761 = getelementptr ptr, ptr %t5, i32 1
  %t2762 = load ptr, ptr %t2761
  %t2763 = getelementptr ptr, ptr %t5, i32 2
  %t2764 = load ptr, ptr %t2763
  %t2765 = getelementptr i8, ptr %t5, i64 -8
  %t2766 = load i32, ptr %t2765
  %t2767 = icmp eq i32 %t2766, 1
  br i1 %t2767, label %reuse.in_place.2768, label %reuse.copy.2769
reuse.in_place.2768:
  %t2771 = inttoptr i64 105 to ptr
  %t2772 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2771, ptr %t2772
  br label %reuse.join.2770
reuse.copy.2769:
  %t2773 = call ptr @__alloc(i64 24, i32 2)
  %t2774 = inttoptr i64 105 to ptr
  %t2775 = getelementptr ptr, ptr %t2773, i32 0
  store ptr %t2774, ptr %t2775
  call void @__inc_ref(ptr %t2762)
  %t2776 = getelementptr ptr, ptr %t2773, i32 1
  store ptr %t2762, ptr %t2776
  call void @__inc_ref(ptr %t2764)
  %t2777 = getelementptr ptr, ptr %t2773, i32 2
  store ptr %t2764, ptr %t2777
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2770
reuse.join.2770:
  %t2778 = phi ptr [ %t5, %reuse.in_place.2768 ], [ %t2773, %reuse.copy.2769 ]
  %t2779 = call ptr @__alloc(i64 16, i32 1)
  %t2780 = inttoptr i64 290 to ptr
  %t2781 = getelementptr ptr, ptr %t2779, i32 0
  store ptr %t2780, ptr %t2781
  call void @__inc_ref(ptr %t6)
  %t2782 = getelementptr ptr, ptr %t2779, i32 1
  store ptr %t6, ptr %t2782
  call void @__free_recursive(ptr %t6)
  store ptr %t2778, ptr %t3
  store ptr %t2779, ptr %t4
  br label %tco.loop.0
tco.case.arm.160.2783:
  %t2784 = getelementptr ptr, ptr %t5, i32 1
  %t2785 = load ptr, ptr %t2784
  %t2786 = getelementptr ptr, ptr %t5, i32 2
  %t2787 = load ptr, ptr %t2786
  %t2788 = getelementptr i8, ptr %t5, i64 -8
  %t2789 = load i32, ptr %t2788
  %t2790 = icmp eq i32 %t2789, 1
  br i1 %t2790, label %reuse.in_place.2791, label %reuse.copy.2792
reuse.in_place.2791:
  %t2794 = inttoptr i64 105 to ptr
  %t2795 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2794, ptr %t2795
  br label %reuse.join.2793
reuse.copy.2792:
  %t2796 = call ptr @__alloc(i64 24, i32 2)
  %t2797 = inttoptr i64 105 to ptr
  %t2798 = getelementptr ptr, ptr %t2796, i32 0
  store ptr %t2797, ptr %t2798
  call void @__inc_ref(ptr %t2785)
  %t2799 = getelementptr ptr, ptr %t2796, i32 1
  store ptr %t2785, ptr %t2799
  call void @__inc_ref(ptr %t2787)
  %t2800 = getelementptr ptr, ptr %t2796, i32 2
  store ptr %t2787, ptr %t2800
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2793
reuse.join.2793:
  %t2801 = phi ptr [ %t5, %reuse.in_place.2791 ], [ %t2796, %reuse.copy.2792 ]
  %t2802 = call ptr @__alloc(i64 16, i32 1)
  %t2803 = inttoptr i64 291 to ptr
  %t2804 = getelementptr ptr, ptr %t2802, i32 0
  store ptr %t2803, ptr %t2804
  call void @__inc_ref(ptr %t6)
  %t2805 = getelementptr ptr, ptr %t2802, i32 1
  store ptr %t6, ptr %t2805
  call void @__free_recursive(ptr %t6)
  store ptr %t2801, ptr %t3
  store ptr %t2802, ptr %t4
  br label %tco.loop.0
tco.case.arm.161.2806:
  %t2807 = getelementptr ptr, ptr %t5, i32 1
  %t2808 = load ptr, ptr %t2807
  %t2809 = getelementptr ptr, ptr %t5, i32 2
  %t2810 = load ptr, ptr %t2809
  %t2811 = getelementptr i8, ptr %t5, i64 -8
  %t2812 = load i32, ptr %t2811
  %t2813 = icmp eq i32 %t2812, 1
  br i1 %t2813, label %reuse.in_place.2814, label %reuse.copy.2815
reuse.in_place.2814:
  %t2817 = inttoptr i64 105 to ptr
  %t2818 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2817, ptr %t2818
  br label %reuse.join.2816
reuse.copy.2815:
  %t2819 = call ptr @__alloc(i64 24, i32 2)
  %t2820 = inttoptr i64 105 to ptr
  %t2821 = getelementptr ptr, ptr %t2819, i32 0
  store ptr %t2820, ptr %t2821
  call void @__inc_ref(ptr %t2808)
  %t2822 = getelementptr ptr, ptr %t2819, i32 1
  store ptr %t2808, ptr %t2822
  call void @__inc_ref(ptr %t2810)
  %t2823 = getelementptr ptr, ptr %t2819, i32 2
  store ptr %t2810, ptr %t2823
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2816
reuse.join.2816:
  %t2824 = phi ptr [ %t5, %reuse.in_place.2814 ], [ %t2819, %reuse.copy.2815 ]
  %t2825 = call ptr @__alloc(i64 16, i32 1)
  %t2826 = inttoptr i64 292 to ptr
  %t2827 = getelementptr ptr, ptr %t2825, i32 0
  store ptr %t2826, ptr %t2827
  call void @__inc_ref(ptr %t6)
  %t2828 = getelementptr ptr, ptr %t2825, i32 1
  store ptr %t6, ptr %t2828
  call void @__free_recursive(ptr %t6)
  store ptr %t2824, ptr %t3
  store ptr %t2825, ptr %t4
  br label %tco.loop.0
tco.case.arm.162.2829:
  %t2830 = getelementptr ptr, ptr %t5, i32 1
  %t2831 = load ptr, ptr %t2830
  %t2832 = getelementptr ptr, ptr %t5, i32 2
  %t2833 = load ptr, ptr %t2832
  %t2834 = getelementptr i8, ptr %t5, i64 -8
  %t2835 = load i32, ptr %t2834
  %t2836 = icmp eq i32 %t2835, 1
  br i1 %t2836, label %reuse.in_place.2837, label %reuse.copy.2838
reuse.in_place.2837:
  %t2840 = inttoptr i64 105 to ptr
  %t2841 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2840, ptr %t2841
  br label %reuse.join.2839
reuse.copy.2838:
  %t2842 = call ptr @__alloc(i64 24, i32 2)
  %t2843 = inttoptr i64 105 to ptr
  %t2844 = getelementptr ptr, ptr %t2842, i32 0
  store ptr %t2843, ptr %t2844
  call void @__inc_ref(ptr %t2831)
  %t2845 = getelementptr ptr, ptr %t2842, i32 1
  store ptr %t2831, ptr %t2845
  call void @__inc_ref(ptr %t2833)
  %t2846 = getelementptr ptr, ptr %t2842, i32 2
  store ptr %t2833, ptr %t2846
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2839
reuse.join.2839:
  %t2847 = phi ptr [ %t5, %reuse.in_place.2837 ], [ %t2842, %reuse.copy.2838 ]
  %t2848 = call ptr @__alloc(i64 16, i32 1)
  %t2849 = inttoptr i64 293 to ptr
  %t2850 = getelementptr ptr, ptr %t2848, i32 0
  store ptr %t2849, ptr %t2850
  call void @__inc_ref(ptr %t6)
  %t2851 = getelementptr ptr, ptr %t2848, i32 1
  store ptr %t6, ptr %t2851
  call void @__free_recursive(ptr %t6)
  store ptr %t2847, ptr %t3
  store ptr %t2848, ptr %t4
  br label %tco.loop.0
tco.case.arm.163.2852:
  %t2853 = getelementptr ptr, ptr %t5, i32 1
  %t2854 = load ptr, ptr %t2853
  %t2855 = getelementptr ptr, ptr %t5, i32 2
  %t2856 = load ptr, ptr %t2855
  %t2857 = getelementptr i8, ptr %t5, i64 -8
  %t2858 = load i32, ptr %t2857
  %t2859 = icmp eq i32 %t2858, 1
  br i1 %t2859, label %reuse.in_place.2860, label %reuse.copy.2861
reuse.in_place.2860:
  %t2863 = inttoptr i64 105 to ptr
  %t2864 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2863, ptr %t2864
  br label %reuse.join.2862
reuse.copy.2861:
  %t2865 = call ptr @__alloc(i64 24, i32 2)
  %t2866 = inttoptr i64 105 to ptr
  %t2867 = getelementptr ptr, ptr %t2865, i32 0
  store ptr %t2866, ptr %t2867
  call void @__inc_ref(ptr %t2854)
  %t2868 = getelementptr ptr, ptr %t2865, i32 1
  store ptr %t2854, ptr %t2868
  call void @__inc_ref(ptr %t2856)
  %t2869 = getelementptr ptr, ptr %t2865, i32 2
  store ptr %t2856, ptr %t2869
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2862
reuse.join.2862:
  %t2870 = phi ptr [ %t5, %reuse.in_place.2860 ], [ %t2865, %reuse.copy.2861 ]
  %t2871 = call ptr @__alloc(i64 16, i32 1)
  %t2872 = inttoptr i64 294 to ptr
  %t2873 = getelementptr ptr, ptr %t2871, i32 0
  store ptr %t2872, ptr %t2873
  call void @__inc_ref(ptr %t6)
  %t2874 = getelementptr ptr, ptr %t2871, i32 1
  store ptr %t6, ptr %t2874
  call void @__free_recursive(ptr %t6)
  store ptr %t2870, ptr %t3
  store ptr %t2871, ptr %t4
  br label %tco.loop.0
tco.case.arm.164.2875:
  %t2876 = getelementptr ptr, ptr %t5, i32 1
  %t2877 = load ptr, ptr %t2876
  %t2878 = getelementptr ptr, ptr %t5, i32 2
  %t2879 = load ptr, ptr %t2878
  %t2880 = getelementptr i8, ptr %t5, i64 -8
  %t2881 = load i32, ptr %t2880
  %t2882 = icmp eq i32 %t2881, 1
  br i1 %t2882, label %reuse.in_place.2883, label %reuse.copy.2884
reuse.in_place.2883:
  %t2886 = inttoptr i64 105 to ptr
  %t2887 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2886, ptr %t2887
  br label %reuse.join.2885
reuse.copy.2884:
  %t2888 = call ptr @__alloc(i64 24, i32 2)
  %t2889 = inttoptr i64 105 to ptr
  %t2890 = getelementptr ptr, ptr %t2888, i32 0
  store ptr %t2889, ptr %t2890
  call void @__inc_ref(ptr %t2877)
  %t2891 = getelementptr ptr, ptr %t2888, i32 1
  store ptr %t2877, ptr %t2891
  call void @__inc_ref(ptr %t2879)
  %t2892 = getelementptr ptr, ptr %t2888, i32 2
  store ptr %t2879, ptr %t2892
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2885
reuse.join.2885:
  %t2893 = phi ptr [ %t5, %reuse.in_place.2883 ], [ %t2888, %reuse.copy.2884 ]
  %t2894 = call ptr @__alloc(i64 16, i32 1)
  %t2895 = inttoptr i64 295 to ptr
  %t2896 = getelementptr ptr, ptr %t2894, i32 0
  store ptr %t2895, ptr %t2896
  call void @__inc_ref(ptr %t6)
  %t2897 = getelementptr ptr, ptr %t2894, i32 1
  store ptr %t6, ptr %t2897
  call void @__free_recursive(ptr %t6)
  store ptr %t2893, ptr %t3
  store ptr %t2894, ptr %t4
  br label %tco.loop.0
tco.case.arm.165.2898:
  %t2899 = getelementptr ptr, ptr %t5, i32 1
  %t2900 = load ptr, ptr %t2899
  %t2901 = getelementptr ptr, ptr %t5, i32 2
  %t2902 = load ptr, ptr %t2901
  %t2903 = getelementptr i8, ptr %t5, i64 -8
  %t2904 = load i32, ptr %t2903
  %t2905 = icmp eq i32 %t2904, 1
  br i1 %t2905, label %reuse.in_place.2906, label %reuse.copy.2907
reuse.in_place.2906:
  %t2909 = inttoptr i64 105 to ptr
  %t2910 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2909, ptr %t2910
  br label %reuse.join.2908
reuse.copy.2907:
  %t2911 = call ptr @__alloc(i64 24, i32 2)
  %t2912 = inttoptr i64 105 to ptr
  %t2913 = getelementptr ptr, ptr %t2911, i32 0
  store ptr %t2912, ptr %t2913
  call void @__inc_ref(ptr %t2900)
  %t2914 = getelementptr ptr, ptr %t2911, i32 1
  store ptr %t2900, ptr %t2914
  call void @__inc_ref(ptr %t2902)
  %t2915 = getelementptr ptr, ptr %t2911, i32 2
  store ptr %t2902, ptr %t2915
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2908
reuse.join.2908:
  %t2916 = phi ptr [ %t5, %reuse.in_place.2906 ], [ %t2911, %reuse.copy.2907 ]
  %t2917 = call ptr @__alloc(i64 16, i32 1)
  %t2918 = inttoptr i64 296 to ptr
  %t2919 = getelementptr ptr, ptr %t2917, i32 0
  store ptr %t2918, ptr %t2919
  call void @__inc_ref(ptr %t6)
  %t2920 = getelementptr ptr, ptr %t2917, i32 1
  store ptr %t6, ptr %t2920
  call void @__free_recursive(ptr %t6)
  store ptr %t2916, ptr %t3
  store ptr %t2917, ptr %t4
  br label %tco.loop.0
tco.case.arm.166.2921:
  %t2922 = getelementptr ptr, ptr %t5, i32 1
  %t2923 = load ptr, ptr %t2922
  call void @__inc_ref(ptr %t2923)
  %t2924 = getelementptr ptr, ptr %t5, i32 2
  %t2925 = load ptr, ptr %t2924
  call void @__inc_ref(ptr %t2925)
  %t2926 = getelementptr ptr, ptr %t5, i32 3
  %t2927 = load ptr, ptr %t2926
  call void @__inc_ref(ptr %t2927)
  %t2928 = call ptr @__alloc(i64 24, i32 2)
  %t2929 = inttoptr i64 105 to ptr
  %t2930 = getelementptr ptr, ptr %t2928, i32 0
  store ptr %t2929, ptr %t2930
  call void @__inc_ref(ptr %t2923)
  %t2931 = getelementptr ptr, ptr %t2928, i32 1
  store ptr %t2923, ptr %t2931
  call void @__inc_ref(ptr %t2925)
  %t2932 = getelementptr ptr, ptr %t2928, i32 2
  store ptr %t2925, ptr %t2932
  %t2933 = call ptr @__alloc(i64 24, i32 2)
  %t2934 = inttoptr i64 297 to ptr
  %t2935 = getelementptr ptr, ptr %t2933, i32 0
  store ptr %t2934, ptr %t2935
  call void @__inc_ref(ptr %t6)
  %t2936 = getelementptr ptr, ptr %t2933, i32 1
  store ptr %t6, ptr %t2936
  call void @__inc_ref(ptr %t2927)
  %t2937 = getelementptr ptr, ptr %t2933, i32 2
  store ptr %t2927, ptr %t2937
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t2927)
  call void @__free_recursive(ptr %t2925)
  call void @__free_recursive(ptr %t2923)
  store ptr %t2928, ptr %t3
  store ptr %t2933, ptr %t4
  br label %tco.loop.0
tco.case.arm.167.2938:
  %t2939 = getelementptr ptr, ptr %t5, i32 1
  %t2940 = load ptr, ptr %t2939
  %t2941 = getelementptr ptr, ptr %t5, i32 2
  %t2942 = load ptr, ptr %t2941
  %t2943 = getelementptr i8, ptr %t5, i64 -8
  %t2944 = load i32, ptr %t2943
  %t2945 = icmp eq i32 %t2944, 1
  br i1 %t2945, label %reuse.in_place.2946, label %reuse.copy.2947
reuse.in_place.2946:
  %t2949 = inttoptr i64 105 to ptr
  %t2950 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2949, ptr %t2950
  br label %reuse.join.2948
reuse.copy.2947:
  %t2951 = call ptr @__alloc(i64 24, i32 2)
  %t2952 = inttoptr i64 105 to ptr
  %t2953 = getelementptr ptr, ptr %t2951, i32 0
  store ptr %t2952, ptr %t2953
  call void @__inc_ref(ptr %t2940)
  %t2954 = getelementptr ptr, ptr %t2951, i32 1
  store ptr %t2940, ptr %t2954
  call void @__inc_ref(ptr %t2942)
  %t2955 = getelementptr ptr, ptr %t2951, i32 2
  store ptr %t2942, ptr %t2955
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2948
reuse.join.2948:
  %t2956 = phi ptr [ %t5, %reuse.in_place.2946 ], [ %t2951, %reuse.copy.2947 ]
  %t2957 = call ptr @__alloc(i64 16, i32 1)
  %t2958 = inttoptr i64 298 to ptr
  %t2959 = getelementptr ptr, ptr %t2957, i32 0
  store ptr %t2958, ptr %t2959
  call void @__inc_ref(ptr %t6)
  %t2960 = getelementptr ptr, ptr %t2957, i32 1
  store ptr %t6, ptr %t2960
  call void @__free_recursive(ptr %t6)
  store ptr %t2956, ptr %t3
  store ptr %t2957, ptr %t4
  br label %tco.loop.0
tco.case.arm.168.2961:
  %t2962 = getelementptr ptr, ptr %t5, i32 1
  %t2963 = load ptr, ptr %t2962
  %t2964 = getelementptr ptr, ptr %t5, i32 2
  %t2965 = load ptr, ptr %t2964
  %t2966 = getelementptr i8, ptr %t5, i64 -8
  %t2967 = load i32, ptr %t2966
  %t2968 = icmp eq i32 %t2967, 1
  br i1 %t2968, label %reuse.in_place.2969, label %reuse.copy.2970
reuse.in_place.2969:
  %t2972 = inttoptr i64 105 to ptr
  %t2973 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2972, ptr %t2973
  br label %reuse.join.2971
reuse.copy.2970:
  %t2974 = call ptr @__alloc(i64 24, i32 2)
  %t2975 = inttoptr i64 105 to ptr
  %t2976 = getelementptr ptr, ptr %t2974, i32 0
  store ptr %t2975, ptr %t2976
  call void @__inc_ref(ptr %t2963)
  %t2977 = getelementptr ptr, ptr %t2974, i32 1
  store ptr %t2963, ptr %t2977
  call void @__inc_ref(ptr %t2965)
  %t2978 = getelementptr ptr, ptr %t2974, i32 2
  store ptr %t2965, ptr %t2978
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2971
reuse.join.2971:
  %t2979 = phi ptr [ %t5, %reuse.in_place.2969 ], [ %t2974, %reuse.copy.2970 ]
  %t2980 = call ptr @__alloc(i64 16, i32 1)
  %t2981 = inttoptr i64 299 to ptr
  %t2982 = getelementptr ptr, ptr %t2980, i32 0
  store ptr %t2981, ptr %t2982
  call void @__inc_ref(ptr %t6)
  %t2983 = getelementptr ptr, ptr %t2980, i32 1
  store ptr %t6, ptr %t2983
  call void @__free_recursive(ptr %t6)
  store ptr %t2979, ptr %t3
  store ptr %t2980, ptr %t4
  br label %tco.loop.0
tco.case.arm.169.2984:
  %t2985 = getelementptr ptr, ptr %t5, i32 1
  %t2986 = load ptr, ptr %t2985
  %t2987 = getelementptr ptr, ptr %t5, i32 2
  %t2988 = load ptr, ptr %t2987
  %t2989 = getelementptr i8, ptr %t5, i64 -8
  %t2990 = load i32, ptr %t2989
  %t2991 = icmp eq i32 %t2990, 1
  br i1 %t2991, label %reuse.in_place.2992, label %reuse.copy.2993
reuse.in_place.2992:
  %t2995 = inttoptr i64 105 to ptr
  %t2996 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2995, ptr %t2996
  br label %reuse.join.2994
reuse.copy.2993:
  %t2997 = call ptr @__alloc(i64 24, i32 2)
  %t2998 = inttoptr i64 105 to ptr
  %t2999 = getelementptr ptr, ptr %t2997, i32 0
  store ptr %t2998, ptr %t2999
  call void @__inc_ref(ptr %t2986)
  %t3000 = getelementptr ptr, ptr %t2997, i32 1
  store ptr %t2986, ptr %t3000
  call void @__inc_ref(ptr %t2988)
  %t3001 = getelementptr ptr, ptr %t2997, i32 2
  store ptr %t2988, ptr %t3001
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2994
reuse.join.2994:
  %t3002 = phi ptr [ %t5, %reuse.in_place.2992 ], [ %t2997, %reuse.copy.2993 ]
  %t3003 = call ptr @__alloc(i64 16, i32 1)
  %t3004 = inttoptr i64 300 to ptr
  %t3005 = getelementptr ptr, ptr %t3003, i32 0
  store ptr %t3004, ptr %t3005
  call void @__inc_ref(ptr %t6)
  %t3006 = getelementptr ptr, ptr %t3003, i32 1
  store ptr %t6, ptr %t3006
  call void @__free_recursive(ptr %t6)
  store ptr %t3002, ptr %t3
  store ptr %t3003, ptr %t4
  br label %tco.loop.0
tco.case.arm.170.3007:
  %t3008 = getelementptr ptr, ptr %t5, i32 1
  %t3009 = load ptr, ptr %t3008
  %t3010 = getelementptr ptr, ptr %t5, i32 2
  %t3011 = load ptr, ptr %t3010
  %t3012 = getelementptr i8, ptr %t5, i64 -8
  %t3013 = load i32, ptr %t3012
  %t3014 = icmp eq i32 %t3013, 1
  br i1 %t3014, label %reuse.in_place.3015, label %reuse.copy.3016
reuse.in_place.3015:
  %t3018 = inttoptr i64 105 to ptr
  %t3019 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3018, ptr %t3019
  br label %reuse.join.3017
reuse.copy.3016:
  %t3020 = call ptr @__alloc(i64 24, i32 2)
  %t3021 = inttoptr i64 105 to ptr
  %t3022 = getelementptr ptr, ptr %t3020, i32 0
  store ptr %t3021, ptr %t3022
  call void @__inc_ref(ptr %t3009)
  %t3023 = getelementptr ptr, ptr %t3020, i32 1
  store ptr %t3009, ptr %t3023
  call void @__inc_ref(ptr %t3011)
  %t3024 = getelementptr ptr, ptr %t3020, i32 2
  store ptr %t3011, ptr %t3024
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3017
reuse.join.3017:
  %t3025 = phi ptr [ %t5, %reuse.in_place.3015 ], [ %t3020, %reuse.copy.3016 ]
  %t3026 = call ptr @__alloc(i64 16, i32 1)
  %t3027 = inttoptr i64 301 to ptr
  %t3028 = getelementptr ptr, ptr %t3026, i32 0
  store ptr %t3027, ptr %t3028
  call void @__inc_ref(ptr %t6)
  %t3029 = getelementptr ptr, ptr %t3026, i32 1
  store ptr %t6, ptr %t3029
  call void @__free_recursive(ptr %t6)
  store ptr %t3025, ptr %t3
  store ptr %t3026, ptr %t4
  br label %tco.loop.0
tco.case.arm.171.3030:
  %t3031 = getelementptr ptr, ptr %t5, i32 1
  %t3032 = load ptr, ptr %t3031
  %t3033 = getelementptr ptr, ptr %t5, i32 2
  %t3034 = load ptr, ptr %t3033
  %t3035 = getelementptr i8, ptr %t5, i64 -8
  %t3036 = load i32, ptr %t3035
  %t3037 = icmp eq i32 %t3036, 1
  br i1 %t3037, label %reuse.in_place.3038, label %reuse.copy.3039
reuse.in_place.3038:
  %t3041 = inttoptr i64 105 to ptr
  %t3042 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3041, ptr %t3042
  br label %reuse.join.3040
reuse.copy.3039:
  %t3043 = call ptr @__alloc(i64 24, i32 2)
  %t3044 = inttoptr i64 105 to ptr
  %t3045 = getelementptr ptr, ptr %t3043, i32 0
  store ptr %t3044, ptr %t3045
  call void @__inc_ref(ptr %t3032)
  %t3046 = getelementptr ptr, ptr %t3043, i32 1
  store ptr %t3032, ptr %t3046
  call void @__inc_ref(ptr %t3034)
  %t3047 = getelementptr ptr, ptr %t3043, i32 2
  store ptr %t3034, ptr %t3047
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3040
reuse.join.3040:
  %t3048 = phi ptr [ %t5, %reuse.in_place.3038 ], [ %t3043, %reuse.copy.3039 ]
  %t3049 = call ptr @__alloc(i64 16, i32 1)
  %t3050 = inttoptr i64 302 to ptr
  %t3051 = getelementptr ptr, ptr %t3049, i32 0
  store ptr %t3050, ptr %t3051
  call void @__inc_ref(ptr %t6)
  %t3052 = getelementptr ptr, ptr %t3049, i32 1
  store ptr %t6, ptr %t3052
  call void @__free_recursive(ptr %t6)
  store ptr %t3048, ptr %t3
  store ptr %t3049, ptr %t4
  br label %tco.loop.0
tco.case.arm.172.3053:
  %t3054 = getelementptr ptr, ptr %t5, i32 1
  %t3055 = load ptr, ptr %t3054
  %t3056 = getelementptr ptr, ptr %t5, i32 2
  %t3057 = load ptr, ptr %t3056
  %t3058 = getelementptr i8, ptr %t5, i64 -8
  %t3059 = load i32, ptr %t3058
  %t3060 = icmp eq i32 %t3059, 1
  br i1 %t3060, label %reuse.in_place.3061, label %reuse.copy.3062
reuse.in_place.3061:
  %t3064 = inttoptr i64 105 to ptr
  %t3065 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3064, ptr %t3065
  br label %reuse.join.3063
reuse.copy.3062:
  %t3066 = call ptr @__alloc(i64 24, i32 2)
  %t3067 = inttoptr i64 105 to ptr
  %t3068 = getelementptr ptr, ptr %t3066, i32 0
  store ptr %t3067, ptr %t3068
  call void @__inc_ref(ptr %t3055)
  %t3069 = getelementptr ptr, ptr %t3066, i32 1
  store ptr %t3055, ptr %t3069
  call void @__inc_ref(ptr %t3057)
  %t3070 = getelementptr ptr, ptr %t3066, i32 2
  store ptr %t3057, ptr %t3070
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3063
reuse.join.3063:
  %t3071 = phi ptr [ %t5, %reuse.in_place.3061 ], [ %t3066, %reuse.copy.3062 ]
  %t3072 = call ptr @__alloc(i64 16, i32 1)
  %t3073 = inttoptr i64 303 to ptr
  %t3074 = getelementptr ptr, ptr %t3072, i32 0
  store ptr %t3073, ptr %t3074
  call void @__inc_ref(ptr %t6)
  %t3075 = getelementptr ptr, ptr %t3072, i32 1
  store ptr %t6, ptr %t3075
  call void @__free_recursive(ptr %t6)
  store ptr %t3071, ptr %t3
  store ptr %t3072, ptr %t4
  br label %tco.loop.0
tco.case.arm.173.3076:
  %t3077 = getelementptr ptr, ptr %t5, i32 1
  %t3078 = load ptr, ptr %t3077
  %t3079 = getelementptr ptr, ptr %t5, i32 2
  %t3080 = load ptr, ptr %t3079
  %t3081 = getelementptr i8, ptr %t5, i64 -8
  %t3082 = load i32, ptr %t3081
  %t3083 = icmp eq i32 %t3082, 1
  br i1 %t3083, label %reuse.in_place.3084, label %reuse.copy.3085
reuse.in_place.3084:
  %t3087 = inttoptr i64 105 to ptr
  %t3088 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3087, ptr %t3088
  br label %reuse.join.3086
reuse.copy.3085:
  %t3089 = call ptr @__alloc(i64 24, i32 2)
  %t3090 = inttoptr i64 105 to ptr
  %t3091 = getelementptr ptr, ptr %t3089, i32 0
  store ptr %t3090, ptr %t3091
  call void @__inc_ref(ptr %t3078)
  %t3092 = getelementptr ptr, ptr %t3089, i32 1
  store ptr %t3078, ptr %t3092
  call void @__inc_ref(ptr %t3080)
  %t3093 = getelementptr ptr, ptr %t3089, i32 2
  store ptr %t3080, ptr %t3093
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3086
reuse.join.3086:
  %t3094 = phi ptr [ %t5, %reuse.in_place.3084 ], [ %t3089, %reuse.copy.3085 ]
  %t3095 = call ptr @__alloc(i64 16, i32 1)
  %t3096 = inttoptr i64 304 to ptr
  %t3097 = getelementptr ptr, ptr %t3095, i32 0
  store ptr %t3096, ptr %t3097
  call void @__inc_ref(ptr %t6)
  %t3098 = getelementptr ptr, ptr %t3095, i32 1
  store ptr %t6, ptr %t3098
  call void @__free_recursive(ptr %t6)
  store ptr %t3094, ptr %t3
  store ptr %t3095, ptr %t4
  br label %tco.loop.0
tco.case.arm.174.3099:
  %t3100 = getelementptr ptr, ptr %t5, i32 1
  %t3101 = load ptr, ptr %t3100
  %t3102 = getelementptr ptr, ptr %t5, i32 2
  %t3103 = load ptr, ptr %t3102
  %t3104 = getelementptr i8, ptr %t5, i64 -8
  %t3105 = load i32, ptr %t3104
  %t3106 = icmp eq i32 %t3105, 1
  br i1 %t3106, label %reuse.in_place.3107, label %reuse.copy.3108
reuse.in_place.3107:
  %t3110 = inttoptr i64 105 to ptr
  %t3111 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3110, ptr %t3111
  br label %reuse.join.3109
reuse.copy.3108:
  %t3112 = call ptr @__alloc(i64 24, i32 2)
  %t3113 = inttoptr i64 105 to ptr
  %t3114 = getelementptr ptr, ptr %t3112, i32 0
  store ptr %t3113, ptr %t3114
  call void @__inc_ref(ptr %t3101)
  %t3115 = getelementptr ptr, ptr %t3112, i32 1
  store ptr %t3101, ptr %t3115
  call void @__inc_ref(ptr %t3103)
  %t3116 = getelementptr ptr, ptr %t3112, i32 2
  store ptr %t3103, ptr %t3116
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3109
reuse.join.3109:
  %t3117 = phi ptr [ %t5, %reuse.in_place.3107 ], [ %t3112, %reuse.copy.3108 ]
  %t3118 = call ptr @__alloc(i64 16, i32 1)
  %t3119 = inttoptr i64 305 to ptr
  %t3120 = getelementptr ptr, ptr %t3118, i32 0
  store ptr %t3119, ptr %t3120
  call void @__inc_ref(ptr %t6)
  %t3121 = getelementptr ptr, ptr %t3118, i32 1
  store ptr %t6, ptr %t3121
  call void @__free_recursive(ptr %t6)
  store ptr %t3117, ptr %t3
  store ptr %t3118, ptr %t4
  br label %tco.loop.0
tco.case.arm.175.3122:
  %t3123 = getelementptr ptr, ptr %t5, i32 1
  %t3124 = load ptr, ptr %t3123
  %t3125 = getelementptr ptr, ptr %t5, i32 2
  %t3126 = load ptr, ptr %t3125
  %t3127 = getelementptr i8, ptr %t5, i64 -8
  %t3128 = load i32, ptr %t3127
  %t3129 = icmp eq i32 %t3128, 1
  br i1 %t3129, label %reuse.in_place.3130, label %reuse.copy.3131
reuse.in_place.3130:
  %t3133 = inttoptr i64 105 to ptr
  %t3134 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3133, ptr %t3134
  br label %reuse.join.3132
reuse.copy.3131:
  %t3135 = call ptr @__alloc(i64 24, i32 2)
  %t3136 = inttoptr i64 105 to ptr
  %t3137 = getelementptr ptr, ptr %t3135, i32 0
  store ptr %t3136, ptr %t3137
  call void @__inc_ref(ptr %t3124)
  %t3138 = getelementptr ptr, ptr %t3135, i32 1
  store ptr %t3124, ptr %t3138
  call void @__inc_ref(ptr %t3126)
  %t3139 = getelementptr ptr, ptr %t3135, i32 2
  store ptr %t3126, ptr %t3139
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3132
reuse.join.3132:
  %t3140 = phi ptr [ %t5, %reuse.in_place.3130 ], [ %t3135, %reuse.copy.3131 ]
  %t3141 = call ptr @__alloc(i64 16, i32 1)
  %t3142 = inttoptr i64 306 to ptr
  %t3143 = getelementptr ptr, ptr %t3141, i32 0
  store ptr %t3142, ptr %t3143
  call void @__inc_ref(ptr %t6)
  %t3144 = getelementptr ptr, ptr %t3141, i32 1
  store ptr %t6, ptr %t3144
  call void @__free_recursive(ptr %t6)
  store ptr %t3140, ptr %t3
  store ptr %t3141, ptr %t4
  br label %tco.loop.0
tco.case.arm.176.3145:
  %t3146 = getelementptr ptr, ptr %t5, i32 1
  %t3147 = load ptr, ptr %t3146
  %t3148 = getelementptr ptr, ptr %t5, i32 2
  %t3149 = load ptr, ptr %t3148
  %t3150 = getelementptr i8, ptr %t5, i64 -8
  %t3151 = load i32, ptr %t3150
  %t3152 = icmp eq i32 %t3151, 1
  br i1 %t3152, label %reuse.in_place.3153, label %reuse.copy.3154
reuse.in_place.3153:
  %t3156 = inttoptr i64 105 to ptr
  %t3157 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3156, ptr %t3157
  br label %reuse.join.3155
reuse.copy.3154:
  %t3158 = call ptr @__alloc(i64 24, i32 2)
  %t3159 = inttoptr i64 105 to ptr
  %t3160 = getelementptr ptr, ptr %t3158, i32 0
  store ptr %t3159, ptr %t3160
  call void @__inc_ref(ptr %t3147)
  %t3161 = getelementptr ptr, ptr %t3158, i32 1
  store ptr %t3147, ptr %t3161
  call void @__inc_ref(ptr %t3149)
  %t3162 = getelementptr ptr, ptr %t3158, i32 2
  store ptr %t3149, ptr %t3162
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3155
reuse.join.3155:
  %t3163 = phi ptr [ %t5, %reuse.in_place.3153 ], [ %t3158, %reuse.copy.3154 ]
  %t3164 = call ptr @__alloc(i64 16, i32 1)
  %t3165 = inttoptr i64 307 to ptr
  %t3166 = getelementptr ptr, ptr %t3164, i32 0
  store ptr %t3165, ptr %t3166
  call void @__inc_ref(ptr %t6)
  %t3167 = getelementptr ptr, ptr %t3164, i32 1
  store ptr %t6, ptr %t3167
  call void @__free_recursive(ptr %t6)
  store ptr %t3163, ptr %t3
  store ptr %t3164, ptr %t4
  br label %tco.loop.0
tco.case.arm.177.3168:
  %t3169 = getelementptr ptr, ptr %t5, i32 1
  %t3170 = load ptr, ptr %t3169
  %t3171 = getelementptr ptr, ptr %t5, i32 2
  %t3172 = load ptr, ptr %t3171
  %t3173 = getelementptr i8, ptr %t5, i64 -8
  %t3174 = load i32, ptr %t3173
  %t3175 = icmp eq i32 %t3174, 1
  br i1 %t3175, label %reuse.in_place.3176, label %reuse.copy.3177
reuse.in_place.3176:
  %t3179 = inttoptr i64 105 to ptr
  %t3180 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3179, ptr %t3180
  br label %reuse.join.3178
reuse.copy.3177:
  %t3181 = call ptr @__alloc(i64 24, i32 2)
  %t3182 = inttoptr i64 105 to ptr
  %t3183 = getelementptr ptr, ptr %t3181, i32 0
  store ptr %t3182, ptr %t3183
  call void @__inc_ref(ptr %t3170)
  %t3184 = getelementptr ptr, ptr %t3181, i32 1
  store ptr %t3170, ptr %t3184
  call void @__inc_ref(ptr %t3172)
  %t3185 = getelementptr ptr, ptr %t3181, i32 2
  store ptr %t3172, ptr %t3185
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3178
reuse.join.3178:
  %t3186 = phi ptr [ %t5, %reuse.in_place.3176 ], [ %t3181, %reuse.copy.3177 ]
  %t3187 = call ptr @__alloc(i64 16, i32 1)
  %t3188 = inttoptr i64 308 to ptr
  %t3189 = getelementptr ptr, ptr %t3187, i32 0
  store ptr %t3188, ptr %t3189
  call void @__inc_ref(ptr %t6)
  %t3190 = getelementptr ptr, ptr %t3187, i32 1
  store ptr %t6, ptr %t3190
  call void @__free_recursive(ptr %t6)
  store ptr %t3186, ptr %t3
  store ptr %t3187, ptr %t4
  br label %tco.loop.0
tco.case.arm.178.3191:
  %t3192 = getelementptr ptr, ptr %t5, i32 1
  %t3193 = load ptr, ptr %t3192
  %t3194 = getelementptr ptr, ptr %t5, i32 2
  %t3195 = load ptr, ptr %t3194
  %t3196 = getelementptr i8, ptr %t5, i64 -8
  %t3197 = load i32, ptr %t3196
  %t3198 = icmp eq i32 %t3197, 1
  br i1 %t3198, label %reuse.in_place.3199, label %reuse.copy.3200
reuse.in_place.3199:
  %t3202 = inttoptr i64 105 to ptr
  %t3203 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3202, ptr %t3203
  br label %reuse.join.3201
reuse.copy.3200:
  %t3204 = call ptr @__alloc(i64 24, i32 2)
  %t3205 = inttoptr i64 105 to ptr
  %t3206 = getelementptr ptr, ptr %t3204, i32 0
  store ptr %t3205, ptr %t3206
  call void @__inc_ref(ptr %t3193)
  %t3207 = getelementptr ptr, ptr %t3204, i32 1
  store ptr %t3193, ptr %t3207
  call void @__inc_ref(ptr %t3195)
  %t3208 = getelementptr ptr, ptr %t3204, i32 2
  store ptr %t3195, ptr %t3208
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3201
reuse.join.3201:
  %t3209 = phi ptr [ %t5, %reuse.in_place.3199 ], [ %t3204, %reuse.copy.3200 ]
  %t3210 = call ptr @__alloc(i64 16, i32 1)
  %t3211 = inttoptr i64 309 to ptr
  %t3212 = getelementptr ptr, ptr %t3210, i32 0
  store ptr %t3211, ptr %t3212
  call void @__inc_ref(ptr %t6)
  %t3213 = getelementptr ptr, ptr %t3210, i32 1
  store ptr %t6, ptr %t3213
  call void @__free_recursive(ptr %t6)
  store ptr %t3209, ptr %t3
  store ptr %t3210, ptr %t4
  br label %tco.loop.0
tco.case.arm.179.3214:
  %t3215 = getelementptr ptr, ptr %t5, i32 1
  %t3216 = load ptr, ptr %t3215
  %t3217 = getelementptr ptr, ptr %t5, i32 2
  %t3218 = load ptr, ptr %t3217
  %t3219 = getelementptr i8, ptr %t5, i64 -8
  %t3220 = load i32, ptr %t3219
  %t3221 = icmp eq i32 %t3220, 1
  br i1 %t3221, label %reuse.in_place.3222, label %reuse.copy.3223
reuse.in_place.3222:
  %t3225 = inttoptr i64 105 to ptr
  %t3226 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3225, ptr %t3226
  br label %reuse.join.3224
reuse.copy.3223:
  %t3227 = call ptr @__alloc(i64 24, i32 2)
  %t3228 = inttoptr i64 105 to ptr
  %t3229 = getelementptr ptr, ptr %t3227, i32 0
  store ptr %t3228, ptr %t3229
  call void @__inc_ref(ptr %t3216)
  %t3230 = getelementptr ptr, ptr %t3227, i32 1
  store ptr %t3216, ptr %t3230
  call void @__inc_ref(ptr %t3218)
  %t3231 = getelementptr ptr, ptr %t3227, i32 2
  store ptr %t3218, ptr %t3231
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3224
reuse.join.3224:
  %t3232 = phi ptr [ %t5, %reuse.in_place.3222 ], [ %t3227, %reuse.copy.3223 ]
  %t3233 = call ptr @__alloc(i64 16, i32 1)
  %t3234 = inttoptr i64 310 to ptr
  %t3235 = getelementptr ptr, ptr %t3233, i32 0
  store ptr %t3234, ptr %t3235
  call void @__inc_ref(ptr %t6)
  %t3236 = getelementptr ptr, ptr %t3233, i32 1
  store ptr %t6, ptr %t3236
  call void @__free_recursive(ptr %t6)
  store ptr %t3232, ptr %t3
  store ptr %t3233, ptr %t4
  br label %tco.loop.0
tco.case.arm.180.3237:
  %t3238 = getelementptr ptr, ptr %t5, i32 1
  %t3239 = load ptr, ptr %t3238
  %t3240 = getelementptr ptr, ptr %t5, i32 2
  %t3241 = load ptr, ptr %t3240
  %t3242 = getelementptr i8, ptr %t5, i64 -8
  %t3243 = load i32, ptr %t3242
  %t3244 = icmp eq i32 %t3243, 1
  br i1 %t3244, label %reuse.in_place.3245, label %reuse.copy.3246
reuse.in_place.3245:
  %t3248 = inttoptr i64 105 to ptr
  %t3249 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3248, ptr %t3249
  br label %reuse.join.3247
reuse.copy.3246:
  %t3250 = call ptr @__alloc(i64 24, i32 2)
  %t3251 = inttoptr i64 105 to ptr
  %t3252 = getelementptr ptr, ptr %t3250, i32 0
  store ptr %t3251, ptr %t3252
  call void @__inc_ref(ptr %t3239)
  %t3253 = getelementptr ptr, ptr %t3250, i32 1
  store ptr %t3239, ptr %t3253
  call void @__inc_ref(ptr %t3241)
  %t3254 = getelementptr ptr, ptr %t3250, i32 2
  store ptr %t3241, ptr %t3254
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3247
reuse.join.3247:
  %t3255 = phi ptr [ %t5, %reuse.in_place.3245 ], [ %t3250, %reuse.copy.3246 ]
  %t3256 = call ptr @__alloc(i64 16, i32 1)
  %t3257 = inttoptr i64 311 to ptr
  %t3258 = getelementptr ptr, ptr %t3256, i32 0
  store ptr %t3257, ptr %t3258
  call void @__inc_ref(ptr %t6)
  %t3259 = getelementptr ptr, ptr %t3256, i32 1
  store ptr %t6, ptr %t3259
  call void @__free_recursive(ptr %t6)
  store ptr %t3255, ptr %t3
  store ptr %t3256, ptr %t4
  br label %tco.loop.0
tco.case.arm.181.3260:
  %t3261 = getelementptr ptr, ptr %t5, i32 1
  %t3262 = load ptr, ptr %t3261
  %t3263 = getelementptr ptr, ptr %t5, i32 2
  %t3264 = load ptr, ptr %t3263
  %t3265 = getelementptr i8, ptr %t5, i64 -8
  %t3266 = load i32, ptr %t3265
  %t3267 = icmp eq i32 %t3266, 1
  br i1 %t3267, label %reuse.in_place.3268, label %reuse.copy.3269
reuse.in_place.3268:
  %t3271 = inttoptr i64 105 to ptr
  %t3272 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3271, ptr %t3272
  br label %reuse.join.3270
reuse.copy.3269:
  %t3273 = call ptr @__alloc(i64 24, i32 2)
  %t3274 = inttoptr i64 105 to ptr
  %t3275 = getelementptr ptr, ptr %t3273, i32 0
  store ptr %t3274, ptr %t3275
  call void @__inc_ref(ptr %t3262)
  %t3276 = getelementptr ptr, ptr %t3273, i32 1
  store ptr %t3262, ptr %t3276
  call void @__inc_ref(ptr %t3264)
  %t3277 = getelementptr ptr, ptr %t3273, i32 2
  store ptr %t3264, ptr %t3277
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3270
reuse.join.3270:
  %t3278 = phi ptr [ %t5, %reuse.in_place.3268 ], [ %t3273, %reuse.copy.3269 ]
  %t3279 = call ptr @__alloc(i64 16, i32 1)
  %t3280 = inttoptr i64 312 to ptr
  %t3281 = getelementptr ptr, ptr %t3279, i32 0
  store ptr %t3280, ptr %t3281
  call void @__inc_ref(ptr %t6)
  %t3282 = getelementptr ptr, ptr %t3279, i32 1
  store ptr %t6, ptr %t3282
  call void @__free_recursive(ptr %t6)
  store ptr %t3278, ptr %t3
  store ptr %t3279, ptr %t4
  br label %tco.loop.0
tco.case.arm.182.3283:
  %t3284 = getelementptr ptr, ptr %t5, i32 1
  %t3285 = load ptr, ptr %t3284
  %t3286 = getelementptr ptr, ptr %t5, i32 2
  %t3287 = load ptr, ptr %t3286
  %t3288 = getelementptr i8, ptr %t5, i64 -8
  %t3289 = load i32, ptr %t3288
  %t3290 = icmp eq i32 %t3289, 1
  br i1 %t3290, label %reuse.in_place.3291, label %reuse.copy.3292
reuse.in_place.3291:
  %t3294 = inttoptr i64 105 to ptr
  %t3295 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3294, ptr %t3295
  br label %reuse.join.3293
reuse.copy.3292:
  %t3296 = call ptr @__alloc(i64 24, i32 2)
  %t3297 = inttoptr i64 105 to ptr
  %t3298 = getelementptr ptr, ptr %t3296, i32 0
  store ptr %t3297, ptr %t3298
  call void @__inc_ref(ptr %t3285)
  %t3299 = getelementptr ptr, ptr %t3296, i32 1
  store ptr %t3285, ptr %t3299
  call void @__inc_ref(ptr %t3287)
  %t3300 = getelementptr ptr, ptr %t3296, i32 2
  store ptr %t3287, ptr %t3300
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3293
reuse.join.3293:
  %t3301 = phi ptr [ %t5, %reuse.in_place.3291 ], [ %t3296, %reuse.copy.3292 ]
  %t3302 = call ptr @__alloc(i64 16, i32 1)
  %t3303 = inttoptr i64 313 to ptr
  %t3304 = getelementptr ptr, ptr %t3302, i32 0
  store ptr %t3303, ptr %t3304
  call void @__inc_ref(ptr %t6)
  %t3305 = getelementptr ptr, ptr %t3302, i32 1
  store ptr %t6, ptr %t3305
  call void @__free_recursive(ptr %t6)
  store ptr %t3301, ptr %t3
  store ptr %t3302, ptr %t4
  br label %tco.loop.0
tco.case.arm.183.3306:
  %t3307 = getelementptr ptr, ptr %t5, i32 1
  %t3308 = load ptr, ptr %t3307
  %t3309 = getelementptr ptr, ptr %t5, i32 2
  %t3310 = load ptr, ptr %t3309
  %t3311 = getelementptr i8, ptr %t5, i64 -8
  %t3312 = load i32, ptr %t3311
  %t3313 = icmp eq i32 %t3312, 1
  br i1 %t3313, label %reuse.in_place.3314, label %reuse.copy.3315
reuse.in_place.3314:
  %t3317 = inttoptr i64 105 to ptr
  %t3318 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3317, ptr %t3318
  br label %reuse.join.3316
reuse.copy.3315:
  %t3319 = call ptr @__alloc(i64 24, i32 2)
  %t3320 = inttoptr i64 105 to ptr
  %t3321 = getelementptr ptr, ptr %t3319, i32 0
  store ptr %t3320, ptr %t3321
  call void @__inc_ref(ptr %t3308)
  %t3322 = getelementptr ptr, ptr %t3319, i32 1
  store ptr %t3308, ptr %t3322
  call void @__inc_ref(ptr %t3310)
  %t3323 = getelementptr ptr, ptr %t3319, i32 2
  store ptr %t3310, ptr %t3323
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3316
reuse.join.3316:
  %t3324 = phi ptr [ %t5, %reuse.in_place.3314 ], [ %t3319, %reuse.copy.3315 ]
  %t3325 = call ptr @__alloc(i64 16, i32 1)
  %t3326 = inttoptr i64 314 to ptr
  %t3327 = getelementptr ptr, ptr %t3325, i32 0
  store ptr %t3326, ptr %t3327
  call void @__inc_ref(ptr %t6)
  %t3328 = getelementptr ptr, ptr %t3325, i32 1
  store ptr %t6, ptr %t3328
  call void @__free_recursive(ptr %t6)
  store ptr %t3324, ptr %t3
  store ptr %t3325, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t3329 = load ptr, ptr %t2
  ret ptr %t3329
}

define internal ptr @v__apply1(ptr %v__cl, ptr %v__arg0) {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 105 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  call void @__inc_ref(ptr %v__cl)
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v__cl, ptr %t3
  call void @__inc_ref(ptr %v__arg0)
  %t4 = getelementptr ptr, ptr %t0, i32 2
  store ptr %v__arg0, ptr %t4
  %t5 = call ptr @v__scc__apply1__df__lam_10_39__df__lam_14_1__df__lam_14_13__df__lam_14_17__df__lam_14_21__df__lam_14_29__df__lam_14_41__df__lam_14_45__df__lam_14_5__df__lam_14_9__df__lam_15_10__df__lam_15_14__df__lam_15_18__df__lam_15_2__df__lam_15_22__df__lam_15_30__df__lam_15_42__df__lam_15_46__df__lam_15_6__df__lam_16_11__df__lam_16_15__df__lam_16_19__df__lam_16_23__df__lam_16_3__df__lam_16_31__df__lam_16_43__df__lam_16_47__df__lam_16_7__df__lam_34_49__df__lam_35_50__df__lam_36_51__df__lam_5_25__df__lam_5_33__df__lam_5_53__df__lam_5_57__df__lam_5_61__df__lam_5_65__df__lam_5_69__df__lam_5_73__df__lam_5_77__df__lam_5_81__df__lam_5_85__df__lam_5_89__df__lam_5_93__df__lam_6_26__df__lam_6_34__df__lam_6_54__df__lam_6_58__df__lam_6_62__df__lam_6_66__df__lam_6_70__df__lam_6_74__df__lam_6_78__df__lam_6_82__df__lam_6_86__df__lam_6_90__df__lam_6_94__df__lam_7_27__df__lam_7_35__df__lam_7_55__df__lam_7_59__df__lam_7_63__df__lam_7_67__df__lam_7_71__df__lam_7_75__df__lam_7_79__df__lam_7_83__df__lam_7_87__df__lam_7_91__df__lam_7_95__df__lam_8_37__df__lam_9_38__lift_2__lift_3__lift_31__lift_32__lift_33__lift_4(ptr %t0)
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
