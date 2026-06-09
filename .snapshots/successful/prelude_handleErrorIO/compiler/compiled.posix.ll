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

define internal ptr @v__lam_13(ptr %v__u) {
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 24 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_failIO(ptr %t0)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t3
}

define internal ptr @v__lam_14(ptr %v__u) {
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

define internal ptr @v__lam_15(ptr %v_act, ptr %v__u) {
  call void @__free_recursive(ptr %v__u)
  ret ptr %v_act
}

define internal ptr @v__lam_16(ptr %v__u) {
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

define internal ptr @v__lam_17(ptr %v__u) {
  %t0 = call ptr @v_treeNoError()
  %t1 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.9, i64 12), ptr %t0)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t1
}

define internal ptr @v__lam_18(ptr %v__u) {
  %t0 = call ptr @v_treePreserve()
  %t1 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.10, i64 12), ptr %t0)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t1
}

define internal ptr @v__lam_19(ptr %v__u) {
  %t0 = call ptr @v_refailRow()
  %t1 = call ptr @v_observeBC(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.11, i64 12), ptr %t1)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t2
}

define internal ptr @v__lam_20(ptr %v__u) {
  %t0 = call ptr @v_refailNarrow()
  %t1 = call ptr @v_observeB(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.12, i64 12), ptr %t1)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t2
}

define internal ptr @v__lam_21(ptr %v__u) {
  %t0 = call ptr @v_nested()
  %t1 = call ptr @v_observeNever(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.13, i64 12), ptr %t1)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t2
}

define internal ptr @v__lam_22(ptr %v__u) {
  %t0 = call ptr @v_passthrough()
  %t1 = call ptr @v_observeNever(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.14, i64 12), ptr %t1)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t2
}

define internal ptr @v__lam_23(ptr %v__u) {
  %t0 = call ptr @v_dispatchB()
  %t1 = call ptr @v_observeNever(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.15, i64 12), ptr %t1)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t2
}

define internal ptr @v__lam_24(ptr %v__u) {
  %t0 = call ptr @v_dispatchA()
  %t1 = call ptr @v_observeNever(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.16, i64 12), ptr %t1)
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

define internal ptr @v__df_handleErrorIO_0(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 172 to ptr
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
  %t39 = inttoptr i64 173 to ptr
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
  %t42 = inttoptr i64 173 to ptr
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
  %t54 = inttoptr i64 90 to ptr
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
  %t66 = inttoptr i64 56 to ptr
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
  %t78 = inttoptr i64 66 to ptr
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

define internal ptr @v__df_handleErrorIO_4(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 174 to ptr
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
  %t39 = inttoptr i64 175 to ptr
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
  %t42 = inttoptr i64 175 to ptr
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
  %t54 = inttoptr i64 97 to ptr
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
  %t66 = inttoptr i64 61 to ptr
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
  %t78 = inttoptr i64 70 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 174, label %tco.case.arm.174.11 i64 175, label %tco.case.arm.175.12 ]
tco.case.arm.174.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.175.12:
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
  %t1 = inttoptr i64 176 to ptr
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
  %t39 = inttoptr i64 177 to ptr
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
  %t42 = inttoptr i64 177 to ptr
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
  %t54 = inttoptr i64 98 to ptr
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
  %t66 = inttoptr i64 53 to ptr
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
  %t78 = inttoptr i64 62 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 176, label %tco.case.arm.176.11 i64 177, label %tco.case.arm.177.12 ]
tco.case.arm.176.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.177.12:
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
  %t1 = inttoptr i64 178 to ptr
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
  %t39 = inttoptr i64 179 to ptr
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
  %t42 = inttoptr i64 179 to ptr
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
  %t54 = inttoptr i64 91 to ptr
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
  %t66 = inttoptr i64 54 to ptr
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
  %t78 = inttoptr i64 63 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 178, label %tco.case.arm.178.11 i64 179, label %tco.case.arm.179.12 ]
tco.case.arm.178.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.179.12:
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
  %t1 = inttoptr i64 180 to ptr
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
  %t39 = inttoptr i64 181 to ptr
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
  %t42 = inttoptr i64 181 to ptr
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
  %t54 = inttoptr i64 92 to ptr
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
  %t66 = inttoptr i64 55 to ptr
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
  %t78 = inttoptr i64 64 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 180, label %tco.case.arm.180.11 i64 181, label %tco.case.arm.181.12 ]
tco.case.arm.180.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.181.12:
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
  %t1 = inttoptr i64 182 to ptr
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
  %t39 = inttoptr i64 183 to ptr
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
  %t42 = inttoptr i64 183 to ptr
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
  %t54 = inttoptr i64 93 to ptr
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
  %t66 = inttoptr i64 57 to ptr
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
  %t78 = inttoptr i64 65 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 182, label %tco.case.arm.182.11 i64 183, label %tco.case.arm.183.12 ]
tco.case.arm.182.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.183.12:
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
  %t1 = inttoptr i64 184 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.16 i64 7, label %tco.case.arm.7.24 i64 8, label %tco.case.arm.8.47 i64 9, label %tco.case.arm.9.59 i64 10, label %tco.case.arm.10.71 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_13(ptr %t13)
  %t15 = call ptr @v__apply__df_andThenIO_24(ptr %t6, ptr %t14)
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
  %t23 = call ptr @v__apply__df_andThenIO_24(ptr %t6, ptr %t19)
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
  %t39 = inttoptr i64 185 to ptr
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
  %t42 = inttoptr i64 185 to ptr
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
  %t54 = inttoptr i64 27 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  call void @__inc_ref(ptr %t49)
  %t56 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t49, ptr %t56
  %t57 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t53, ptr %t57
  %t58 = call ptr @v__apply__df_andThenIO_24(ptr %t6, ptr %t50)
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
  %t70 = call ptr @v__apply__df_andThenIO_24(ptr %t6, ptr %t62)
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
  %t78 = inttoptr i64 71 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  call void @__inc_ref(ptr %t73)
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t73, ptr %t80
  %t81 = getelementptr ptr, ptr %t74, i32 1
  store ptr %t77, ptr %t81
  %t82 = call ptr @v__apply__df_andThenIO_24(ptr %t6, ptr %t74)
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

define internal ptr @v__df_handleErrorIO_28(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 186 to ptr
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
  %t39 = inttoptr i64 187 to ptr
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
  %t42 = inttoptr i64 187 to ptr
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
  %t54 = inttoptr i64 94 to ptr
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
  %t66 = inttoptr i64 58 to ptr
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
  %t78 = inttoptr i64 67 to ptr
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

define internal ptr @v__df_andThenIO_32(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 188 to ptr
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
  %t14 = call ptr @v__bi_IO_Stdout_print(ptr %t13)
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
  %t66 = inttoptr i64 41 to ptr
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
  %t78 = inttoptr i64 72 to ptr
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

define internal ptr @v__df_mapIO_36(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 190 to ptr
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
  %t43 = inttoptr i64 191 to ptr
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
  %t46 = inttoptr i64 191 to ptr
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
  %t58 = inttoptr i64 87 to ptr
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
  %t70 = inttoptr i64 88 to ptr
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
  %t82 = inttoptr i64 89 to ptr
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

define internal ptr @v__df_handleErrorIO_40(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 192 to ptr
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
  %t54 = inttoptr i64 95 to ptr
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
  %t66 = inttoptr i64 59 to ptr
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
  %t78 = inttoptr i64 68 to ptr
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

define internal ptr @v__df_handleErrorIO_44(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 194 to ptr
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
  %t54 = inttoptr i64 96 to ptr
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
  %t66 = inttoptr i64 60 to ptr
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
  %t78 = inttoptr i64 69 to ptr
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

define internal ptr @v__df__rowmono_0_andThenIO_48(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 196 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.16 i64 7, label %tco.case.arm.7.24 i64 8, label %tco.case.arm.8.47 i64 9, label %tco.case.arm.9.59 i64 10, label %tco.case.arm.10.71 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__bi_IO_Stdout_print(ptr %t13)
  %t15 = call ptr @v__apply__df__rowmono_0_andThenIO_48(ptr %t6, ptr %t14)
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
  %t23 = call ptr @v__apply__df__rowmono_0_andThenIO_48(ptr %t6, ptr %t19)
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
  %t54 = inttoptr i64 84 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  call void @__inc_ref(ptr %t49)
  %t56 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t49, ptr %t56
  %t57 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t53, ptr %t57
  %t58 = call ptr @v__apply__df__rowmono_0_andThenIO_48(ptr %t6, ptr %t50)
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
  %t66 = inttoptr i64 85 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  call void @__inc_ref(ptr %t61)
  %t68 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t61, ptr %t68
  %t69 = getelementptr ptr, ptr %t62, i32 1
  store ptr %t65, ptr %t69
  %t70 = call ptr @v__apply__df__rowmono_0_andThenIO_48(ptr %t6, ptr %t62)
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
  %t78 = inttoptr i64 86 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  call void @__inc_ref(ptr %t73)
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t73, ptr %t80
  %t81 = getelementptr ptr, ptr %t74, i32 1
  store ptr %t77, ptr %t81
  %t82 = call ptr @v__apply__df__rowmono_0_andThenIO_48(ptr %t6, ptr %t74)
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

define internal ptr @v__df_andThenIO_52(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 198 to ptr
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
  %t14 = call ptr @v__lam_14(ptr %t13)
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
  %t54 = inttoptr i64 29 to ptr
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
  %t66 = inttoptr i64 42 to ptr
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
  %t78 = inttoptr i64 73 to ptr
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

define internal ptr @v__df_andThenIO_56(ptr %v_io, ptr %v__df_andThenIO_56_cap0_0) {
  call void @__inc_ref(ptr %v_io)
  call void @__inc_ref(ptr %v__df_andThenIO_56_cap0_0)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 200 to ptr
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
  switch i64 %t11, label %tco.case.default.12 [ i64 5, label %tco.case.arm.5.13 i64 6, label %tco.case.arm.6.18 i64 7, label %tco.case.arm.7.26 i64 8, label %tco.case.arm.8.49 i64 9, label %tco.case.arm.9.62 i64 10, label %tco.case.arm.10.75 ]
tco.case.arm.5.13:
  %t14 = getelementptr ptr, ptr %t6, i32 1
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  call void @__inc_ref(ptr %t8)
  call void @__inc_ref(ptr %t7)
  call void @__inc_ref(ptr %t15)
  %t16 = call ptr @v__lam_15(ptr %t7, ptr %t15)
  %t17 = call ptr @v__apply__df_andThenIO_56(ptr %t8, ptr %t16)
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
  %t25 = call ptr @v__apply__df_andThenIO_56(ptr %t8, ptr %t21)
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
  %t41 = inttoptr i64 201 to ptr
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
  %t44 = inttoptr i64 201 to ptr
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
  %t61 = call ptr @v__apply__df_andThenIO_56(ptr %t8, ptr %t52)
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
  %t69 = inttoptr i64 43 to ptr
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
  %t74 = call ptr @v__apply__df_andThenIO_56(ptr %t8, ptr %t65)
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
  %t82 = inttoptr i64 74 to ptr
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
  %t87 = call ptr @v__apply__df_andThenIO_56(ptr %t8, ptr %t78)
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

define internal ptr @v__df_andThenIO_60(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 202 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.16 i64 7, label %tco.case.arm.7.24 i64 8, label %tco.case.arm.8.47 i64 9, label %tco.case.arm.9.59 i64 10, label %tco.case.arm.10.71 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_16(ptr %t13)
  %t15 = call ptr @v__apply__df_andThenIO_60(ptr %t6, ptr %t14)
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
  %t23 = call ptr @v__apply__df_andThenIO_60(ptr %t6, ptr %t19)
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
  %t54 = inttoptr i64 31 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  call void @__inc_ref(ptr %t49)
  %t56 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t49, ptr %t56
  %t57 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t53, ptr %t57
  %t58 = call ptr @v__apply__df_andThenIO_60(ptr %t6, ptr %t50)
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
  %t70 = call ptr @v__apply__df_andThenIO_60(ptr %t6, ptr %t62)
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
  %t78 = inttoptr i64 75 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  call void @__inc_ref(ptr %t73)
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t73, ptr %t80
  %t81 = getelementptr ptr, ptr %t74, i32 1
  store ptr %t77, ptr %t81
  %t82 = call ptr @v__apply__df_andThenIO_60(ptr %t6, ptr %t74)
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

define internal ptr @v__df_andThenIO_64(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 204 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.16 i64 7, label %tco.case.arm.7.24 i64 8, label %tco.case.arm.8.47 i64 9, label %tco.case.arm.9.59 i64 10, label %tco.case.arm.10.71 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_17(ptr %t13)
  %t15 = call ptr @v__apply__df_andThenIO_64(ptr %t6, ptr %t14)
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
  %t23 = call ptr @v__apply__df_andThenIO_64(ptr %t6, ptr %t19)
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
  %t39 = inttoptr i64 205 to ptr
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
  %t42 = inttoptr i64 205 to ptr
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
  %t58 = call ptr @v__apply__df_andThenIO_64(ptr %t6, ptr %t50)
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
  %t70 = call ptr @v__apply__df_andThenIO_64(ptr %t6, ptr %t62)
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
  %t78 = inttoptr i64 76 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  call void @__inc_ref(ptr %t73)
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t73, ptr %t80
  %t81 = getelementptr ptr, ptr %t74, i32 1
  store ptr %t77, ptr %t81
  %t82 = call ptr @v__apply__df_andThenIO_64(ptr %t6, ptr %t74)
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

define internal ptr @v__df_andThenIO_68(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 206 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.16 i64 7, label %tco.case.arm.7.24 i64 8, label %tco.case.arm.8.47 i64 9, label %tco.case.arm.9.59 i64 10, label %tco.case.arm.10.71 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_18(ptr %t13)
  %t15 = call ptr @v__apply__df_andThenIO_68(ptr %t6, ptr %t14)
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
  %t23 = call ptr @v__apply__df_andThenIO_68(ptr %t6, ptr %t19)
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
  %t39 = inttoptr i64 207 to ptr
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
  %t42 = inttoptr i64 207 to ptr
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
  %t58 = call ptr @v__apply__df_andThenIO_68(ptr %t6, ptr %t50)
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
  %t66 = inttoptr i64 46 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  call void @__inc_ref(ptr %t61)
  %t68 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t61, ptr %t68
  %t69 = getelementptr ptr, ptr %t62, i32 1
  store ptr %t65, ptr %t69
  %t70 = call ptr @v__apply__df_andThenIO_68(ptr %t6, ptr %t62)
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
  %t78 = inttoptr i64 77 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  call void @__inc_ref(ptr %t73)
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t73, ptr %t80
  %t81 = getelementptr ptr, ptr %t74, i32 1
  store ptr %t77, ptr %t81
  %t82 = call ptr @v__apply__df_andThenIO_68(ptr %t6, ptr %t74)
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

define internal ptr @v__df_andThenIO_72(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 208 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.16 i64 7, label %tco.case.arm.7.24 i64 8, label %tco.case.arm.8.47 i64 9, label %tco.case.arm.9.59 i64 10, label %tco.case.arm.10.71 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_19(ptr %t13)
  %t15 = call ptr @v__apply__df_andThenIO_72(ptr %t6, ptr %t14)
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
  %t23 = call ptr @v__apply__df_andThenIO_72(ptr %t6, ptr %t19)
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
  %t54 = inttoptr i64 34 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  call void @__inc_ref(ptr %t49)
  %t56 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t49, ptr %t56
  %t57 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t53, ptr %t57
  %t58 = call ptr @v__apply__df_andThenIO_72(ptr %t6, ptr %t50)
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
  %t66 = inttoptr i64 47 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  call void @__inc_ref(ptr %t61)
  %t68 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t61, ptr %t68
  %t69 = getelementptr ptr, ptr %t62, i32 1
  store ptr %t65, ptr %t69
  %t70 = call ptr @v__apply__df_andThenIO_72(ptr %t6, ptr %t62)
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
  %t78 = inttoptr i64 78 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  call void @__inc_ref(ptr %t73)
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t73, ptr %t80
  %t81 = getelementptr ptr, ptr %t74, i32 1
  store ptr %t77, ptr %t81
  %t82 = call ptr @v__apply__df_andThenIO_72(ptr %t6, ptr %t74)
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

define internal ptr @v__df_andThenIO_76(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 210 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.16 i64 7, label %tco.case.arm.7.24 i64 8, label %tco.case.arm.8.47 i64 9, label %tco.case.arm.9.59 i64 10, label %tco.case.arm.10.71 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_20(ptr %t13)
  %t15 = call ptr @v__apply__df_andThenIO_76(ptr %t6, ptr %t14)
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
  %t23 = call ptr @v__apply__df_andThenIO_76(ptr %t6, ptr %t19)
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
  %t54 = inttoptr i64 35 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  call void @__inc_ref(ptr %t49)
  %t56 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t49, ptr %t56
  %t57 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t53, ptr %t57
  %t58 = call ptr @v__apply__df_andThenIO_76(ptr %t6, ptr %t50)
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
  %t66 = inttoptr i64 48 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  call void @__inc_ref(ptr %t61)
  %t68 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t61, ptr %t68
  %t69 = getelementptr ptr, ptr %t62, i32 1
  store ptr %t65, ptr %t69
  %t70 = call ptr @v__apply__df_andThenIO_76(ptr %t6, ptr %t62)
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
  %t78 = inttoptr i64 79 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  call void @__inc_ref(ptr %t73)
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t73, ptr %t80
  %t81 = getelementptr ptr, ptr %t74, i32 1
  store ptr %t77, ptr %t81
  %t82 = call ptr @v__apply__df_andThenIO_76(ptr %t6, ptr %t74)
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

define internal ptr @v__df_andThenIO_80(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 212 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.16 i64 7, label %tco.case.arm.7.24 i64 8, label %tco.case.arm.8.47 i64 9, label %tco.case.arm.9.59 i64 10, label %tco.case.arm.10.71 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_21(ptr %t13)
  %t15 = call ptr @v__apply__df_andThenIO_80(ptr %t6, ptr %t14)
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
  %t23 = call ptr @v__apply__df_andThenIO_80(ptr %t6, ptr %t19)
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
  %t54 = inttoptr i64 36 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  call void @__inc_ref(ptr %t49)
  %t56 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t49, ptr %t56
  %t57 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t53, ptr %t57
  %t58 = call ptr @v__apply__df_andThenIO_80(ptr %t6, ptr %t50)
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
  %t66 = inttoptr i64 49 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  call void @__inc_ref(ptr %t61)
  %t68 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t61, ptr %t68
  %t69 = getelementptr ptr, ptr %t62, i32 1
  store ptr %t65, ptr %t69
  %t70 = call ptr @v__apply__df_andThenIO_80(ptr %t6, ptr %t62)
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
  %t78 = inttoptr i64 80 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  call void @__inc_ref(ptr %t73)
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t73, ptr %t80
  %t81 = getelementptr ptr, ptr %t74, i32 1
  store ptr %t77, ptr %t81
  %t82 = call ptr @v__apply__df_andThenIO_80(ptr %t6, ptr %t74)
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

define internal ptr @v__df_andThenIO_84(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 214 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.16 i64 7, label %tco.case.arm.7.24 i64 8, label %tco.case.arm.8.47 i64 9, label %tco.case.arm.9.59 i64 10, label %tco.case.arm.10.71 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_22(ptr %t13)
  %t15 = call ptr @v__apply__df_andThenIO_84(ptr %t6, ptr %t14)
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
  %t23 = call ptr @v__apply__df_andThenIO_84(ptr %t6, ptr %t19)
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
  %t54 = inttoptr i64 37 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  call void @__inc_ref(ptr %t49)
  %t56 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t49, ptr %t56
  %t57 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t53, ptr %t57
  %t58 = call ptr @v__apply__df_andThenIO_84(ptr %t6, ptr %t50)
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
  %t66 = inttoptr i64 50 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  call void @__inc_ref(ptr %t61)
  %t68 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t61, ptr %t68
  %t69 = getelementptr ptr, ptr %t62, i32 1
  store ptr %t65, ptr %t69
  %t70 = call ptr @v__apply__df_andThenIO_84(ptr %t6, ptr %t62)
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
  %t78 = inttoptr i64 81 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  call void @__inc_ref(ptr %t73)
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t73, ptr %t80
  %t81 = getelementptr ptr, ptr %t74, i32 1
  store ptr %t77, ptr %t81
  %t82 = call ptr @v__apply__df_andThenIO_84(ptr %t6, ptr %t74)
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

define internal ptr @v__df_andThenIO_88(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 216 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.16 i64 7, label %tco.case.arm.7.24 i64 8, label %tco.case.arm.8.47 i64 9, label %tco.case.arm.9.59 i64 10, label %tco.case.arm.10.71 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_23(ptr %t13)
  %t15 = call ptr @v__apply__df_andThenIO_88(ptr %t6, ptr %t14)
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
  %t23 = call ptr @v__apply__df_andThenIO_88(ptr %t6, ptr %t19)
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
  %t54 = inttoptr i64 38 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  call void @__inc_ref(ptr %t49)
  %t56 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t49, ptr %t56
  %t57 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t53, ptr %t57
  %t58 = call ptr @v__apply__df_andThenIO_88(ptr %t6, ptr %t50)
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
  %t66 = inttoptr i64 51 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  call void @__inc_ref(ptr %t61)
  %t68 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t61, ptr %t68
  %t69 = getelementptr ptr, ptr %t62, i32 1
  store ptr %t65, ptr %t69
  %t70 = call ptr @v__apply__df_andThenIO_88(ptr %t6, ptr %t62)
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
  %t78 = inttoptr i64 82 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  call void @__inc_ref(ptr %t73)
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t73, ptr %t80
  %t81 = getelementptr ptr, ptr %t74, i32 1
  store ptr %t77, ptr %t81
  %t82 = call ptr @v__apply__df_andThenIO_88(ptr %t6, ptr %t74)
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

define internal ptr @v__df_andThenIO_92(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 218 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.16 i64 7, label %tco.case.arm.7.24 i64 8, label %tco.case.arm.8.47 i64 9, label %tco.case.arm.9.59 i64 10, label %tco.case.arm.10.71 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_24(ptr %t13)
  %t15 = call ptr @v__apply__df_andThenIO_92(ptr %t6, ptr %t14)
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
  %t23 = call ptr @v__apply__df_andThenIO_92(ptr %t6, ptr %t19)
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
  %t54 = inttoptr i64 39 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  call void @__inc_ref(ptr %t49)
  %t56 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t49, ptr %t56
  %t57 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t53, ptr %t57
  %t58 = call ptr @v__apply__df_andThenIO_92(ptr %t6, ptr %t50)
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
  %t66 = inttoptr i64 52 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  call void @__inc_ref(ptr %t61)
  %t68 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t61, ptr %t68
  %t69 = getelementptr ptr, ptr %t62, i32 1
  store ptr %t65, ptr %t69
  %t70 = call ptr @v__apply__df_andThenIO_92(ptr %t6, ptr %t62)
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
  %t78 = inttoptr i64 83 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  call void @__inc_ref(ptr %t73)
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t73, ptr %t80
  %t81 = getelementptr ptr, ptr %t74, i32 1
  store ptr %t77, ptr %t81
  %t82 = call ptr @v__apply__df_andThenIO_92(ptr %t6, ptr %t74)
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

define internal ptr @v__scc__apply1__df__lam_0_25__df__lam_0_33__df__lam_0_53__df__lam_0_57__df__lam_0_61__df__lam_0_65__df__lam_0_69__df__lam_0_73__df__lam_0_77__df__lam_0_81__df__lam_0_85__df__lam_0_89__df__lam_0_93__df__lam_1_26__df__lam_1_34__df__lam_1_54__df__lam_1_58__df__lam_1_62__df__lam_1_66__df__lam_1_70__df__lam_1_74__df__lam_1_78__df__lam_1_82__df__lam_1_86__df__lam_1_90__df__lam_1_94__df__lam_10_10__df__lam_10_14__df__lam_10_18__df__lam_10_2__df__lam_10_22__df__lam_10_30__df__lam_10_42__df__lam_10_46__df__lam_10_6__df__lam_11_11__df__lam_11_15__df__lam_11_19__df__lam_11_23__df__lam_11_3__df__lam_11_31__df__lam_11_43__df__lam_11_47__df__lam_11_7__df__lam_2_27__df__lam_2_35__df__lam_2_55__df__lam_2_59__df__lam_2_63__df__lam_2_67__df__lam_2_71__df__lam_2_75__df__lam_2_79__df__lam_2_83__df__lam_2_87__df__lam_2_91__df__lam_2_95__df__lam_25_49__df__lam_26_50__df__lam_27_51__df__lam_3_37__df__lam_4_38__df__lam_5_39__df__lam_9_1__df__lam_9_13__df__lam_9_17__df__lam_9_21__df__lam_9_29__df__lam_9_41__df__lam_9_45__df__lam_9_5__df__lam_9_9(ptr %v__args) {
  call void @__inc_ref(ptr %v__args)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 220 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__scc__apply1__df__lam_0_25__df__lam_0_33__df__lam_0_53__df__lam_0_57__df__lam_0_61__df__lam_0_65__df__lam_0_69__df__lam_0_73__df__lam_0_77__df__lam_0_81__df__lam_0_85__df__lam_0_89__df__lam_0_93__df__lam_1_26__df__lam_1_34__df__lam_1_54__df__lam_1_58__df__lam_1_62__df__lam_1_66__df__lam_1_70__df__lam_1_74__df__lam_1_78__df__lam_1_82__df__lam_1_86__df__lam_1_90__df__lam_1_94__df__lam_10_10__df__lam_10_14__df__lam_10_18__df__lam_10_2__df__lam_10_22__df__lam_10_30__df__lam_10_42__df__lam_10_46__df__lam_10_6__df__lam_11_11__df__lam_11_15__df__lam_11_19__df__lam_11_23__df__lam_11_3__df__lam_11_31__df__lam_11_43__df__lam_11_47__df__lam_11_7__df__lam_2_27__df__lam_2_35__df__lam_2_55__df__lam_2_59__df__lam_2_63__df__lam_2_67__df__lam_2_71__df__lam_2_75__df__lam_2_79__df__lam_2_83__df__lam_2_87__df__lam_2_91__df__lam_2_95__df__lam_25_49__df__lam_26_50__df__lam_27_51__df__lam_3_37__df__lam_4_38__df__lam_5_39__df__lam_9_1__df__lam_9_13__df__lam_9_17__df__lam_9_21__df__lam_9_29__df__lam_9_41__df__lam_9_45__df__lam_9_5__df__lam_9_9(ptr %v__args, ptr %t0)
  call void @__free_recursive(ptr %v__args)
  ret ptr %t3
}

define internal ptr @v__cps__scc__apply1__df__lam_0_25__df__lam_0_33__df__lam_0_53__df__lam_0_57__df__lam_0_61__df__lam_0_65__df__lam_0_69__df__lam_0_73__df__lam_0_77__df__lam_0_81__df__lam_0_85__df__lam_0_89__df__lam_0_93__df__lam_1_26__df__lam_1_34__df__lam_1_54__df__lam_1_58__df__lam_1_62__df__lam_1_66__df__lam_1_70__df__lam_1_74__df__lam_1_78__df__lam_1_82__df__lam_1_86__df__lam_1_90__df__lam_1_94__df__lam_10_10__df__lam_10_14__df__lam_10_18__df__lam_10_2__df__lam_10_22__df__lam_10_30__df__lam_10_42__df__lam_10_46__df__lam_10_6__df__lam_11_11__df__lam_11_15__df__lam_11_19__df__lam_11_23__df__lam_11_3__df__lam_11_31__df__lam_11_43__df__lam_11_47__df__lam_11_7__df__lam_2_27__df__lam_2_35__df__lam_2_55__df__lam_2_59__df__lam_2_63__df__lam_2_67__df__lam_2_71__df__lam_2_75__df__lam_2_79__df__lam_2_83__df__lam_2_87__df__lam_2_91__df__lam_2_95__df__lam_25_49__df__lam_26_50__df__lam_27_51__df__lam_3_37__df__lam_4_38__df__lam_5_39__df__lam_9_1__df__lam_9_13__df__lam_9_17__df__lam_9_21__df__lam_9_29__df__lam_9_41__df__lam_9_45__df__lam_9_5__df__lam_9_9(ptr %v__args, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 99, label %tco.case.arm.99.11 i64 100, label %tco.case.arm.100.1433 i64 101, label %tco.case.arm.101.1456 i64 102, label %tco.case.arm.102.1479 i64 103, label %tco.case.arm.103.1502 i64 104, label %tco.case.arm.104.1519 i64 105, label %tco.case.arm.105.1542 i64 106, label %tco.case.arm.106.1565 i64 107, label %tco.case.arm.107.1588 i64 108, label %tco.case.arm.108.1611 i64 109, label %tco.case.arm.109.1634 i64 110, label %tco.case.arm.110.1657 i64 111, label %tco.case.arm.111.1680 i64 112, label %tco.case.arm.112.1703 i64 113, label %tco.case.arm.113.1726 i64 114, label %tco.case.arm.114.1749 i64 115, label %tco.case.arm.115.1772 i64 116, label %tco.case.arm.116.1795 i64 117, label %tco.case.arm.117.1812 i64 118, label %tco.case.arm.118.1835 i64 119, label %tco.case.arm.119.1858 i64 120, label %tco.case.arm.120.1881 i64 121, label %tco.case.arm.121.1904 i64 122, label %tco.case.arm.122.1927 i64 123, label %tco.case.arm.123.1950 i64 124, label %tco.case.arm.124.1973 i64 125, label %tco.case.arm.125.1996 i64 126, label %tco.case.arm.126.2019 i64 127, label %tco.case.arm.127.2042 i64 128, label %tco.case.arm.128.2065 i64 129, label %tco.case.arm.129.2088 i64 130, label %tco.case.arm.130.2111 i64 131, label %tco.case.arm.131.2134 i64 132, label %tco.case.arm.132.2157 i64 133, label %tco.case.arm.133.2180 i64 134, label %tco.case.arm.134.2203 i64 135, label %tco.case.arm.135.2226 i64 136, label %tco.case.arm.136.2249 i64 137, label %tco.case.arm.137.2272 i64 138, label %tco.case.arm.138.2295 i64 139, label %tco.case.arm.139.2318 i64 140, label %tco.case.arm.140.2341 i64 141, label %tco.case.arm.141.2364 i64 142, label %tco.case.arm.142.2387 i64 143, label %tco.case.arm.143.2410 i64 144, label %tco.case.arm.144.2433 i64 145, label %tco.case.arm.145.2456 i64 146, label %tco.case.arm.146.2479 i64 147, label %tco.case.arm.147.2502 i64 148, label %tco.case.arm.148.2519 i64 149, label %tco.case.arm.149.2542 i64 150, label %tco.case.arm.150.2565 i64 151, label %tco.case.arm.151.2588 i64 152, label %tco.case.arm.152.2611 i64 153, label %tco.case.arm.153.2634 i64 154, label %tco.case.arm.154.2657 i64 155, label %tco.case.arm.155.2680 i64 156, label %tco.case.arm.156.2703 i64 157, label %tco.case.arm.157.2726 i64 158, label %tco.case.arm.158.2749 i64 159, label %tco.case.arm.159.2772 i64 160, label %tco.case.arm.160.2795 i64 161, label %tco.case.arm.161.2818 i64 162, label %tco.case.arm.162.2841 i64 163, label %tco.case.arm.163.2864 i64 164, label %tco.case.arm.164.2887 i64 165, label %tco.case.arm.165.2910 i64 166, label %tco.case.arm.166.2933 i64 167, label %tco.case.arm.167.2956 i64 168, label %tco.case.arm.168.2979 i64 169, label %tco.case.arm.169.3002 i64 170, label %tco.case.arm.170.3025 i64 171, label %tco.case.arm.171.3048 ]
tco.case.arm.99.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t5, i32 2
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  %t16 = getelementptr ptr, ptr %t13, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %tco.case.default.19 [ i64 27, label %tco.case.arm.27.20 i64 28, label %tco.case.arm.28.40 i64 29, label %tco.case.arm.29.60 i64 30, label %tco.case.arm.30.80 i64 31, label %tco.case.arm.31.91 i64 32, label %tco.case.arm.32.111 i64 33, label %tco.case.arm.33.131 i64 34, label %tco.case.arm.34.151 i64 35, label %tco.case.arm.35.171 i64 36, label %tco.case.arm.36.191 i64 37, label %tco.case.arm.37.211 i64 38, label %tco.case.arm.38.231 i64 39, label %tco.case.arm.39.251 i64 40, label %tco.case.arm.40.271 i64 41, label %tco.case.arm.41.291 i64 42, label %tco.case.arm.42.311 i64 43, label %tco.case.arm.43.331 i64 44, label %tco.case.arm.44.342 i64 45, label %tco.case.arm.45.362 i64 46, label %tco.case.arm.46.382 i64 47, label %tco.case.arm.47.402 i64 48, label %tco.case.arm.48.422 i64 49, label %tco.case.arm.49.442 i64 50, label %tco.case.arm.50.462 i64 51, label %tco.case.arm.51.482 i64 52, label %tco.case.arm.52.502 i64 53, label %tco.case.arm.53.522 i64 54, label %tco.case.arm.54.542 i64 55, label %tco.case.arm.55.562 i64 56, label %tco.case.arm.56.582 i64 57, label %tco.case.arm.57.602 i64 58, label %tco.case.arm.58.622 i64 59, label %tco.case.arm.59.642 i64 60, label %tco.case.arm.60.662 i64 61, label %tco.case.arm.61.682 i64 62, label %tco.case.arm.62.702 i64 63, label %tco.case.arm.63.722 i64 64, label %tco.case.arm.64.742 i64 65, label %tco.case.arm.65.762 i64 66, label %tco.case.arm.66.782 i64 67, label %tco.case.arm.67.802 i64 68, label %tco.case.arm.68.822 i64 69, label %tco.case.arm.69.842 i64 70, label %tco.case.arm.70.862 i64 71, label %tco.case.arm.71.882 i64 72, label %tco.case.arm.72.902 i64 73, label %tco.case.arm.73.922 i64 74, label %tco.case.arm.74.942 i64 75, label %tco.case.arm.75.953 i64 76, label %tco.case.arm.76.973 i64 77, label %tco.case.arm.77.993 i64 78, label %tco.case.arm.78.1013 i64 79, label %tco.case.arm.79.1033 i64 80, label %tco.case.arm.80.1053 i64 81, label %tco.case.arm.81.1073 i64 82, label %tco.case.arm.82.1093 i64 83, label %tco.case.arm.83.1113 i64 84, label %tco.case.arm.84.1133 i64 85, label %tco.case.arm.85.1153 i64 86, label %tco.case.arm.86.1173 i64 87, label %tco.case.arm.87.1193 i64 88, label %tco.case.arm.88.1213 i64 89, label %tco.case.arm.89.1233 i64 90, label %tco.case.arm.90.1253 i64 91, label %tco.case.arm.91.1273 i64 92, label %tco.case.arm.92.1293 i64 93, label %tco.case.arm.93.1313 i64 94, label %tco.case.arm.94.1333 i64 95, label %tco.case.arm.95.1353 i64 96, label %tco.case.arm.96.1373 i64 97, label %tco.case.arm.97.1393 i64 98, label %tco.case.arm.98.1413 ]
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
  %t32 = inttoptr i64 100 to ptr
  %t33 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t32, ptr %t33
  call void @__inc_ref(ptr %t22)
  %t31 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t22, ptr %t31
  br label %reuse.join.28
reuse.copy.27:
  %t34 = call ptr @__alloc(i64 24, i32 2)
  %t35 = inttoptr i64 100 to ptr
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
  %t52 = inttoptr i64 101 to ptr
  %t53 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t52, ptr %t53
  call void @__inc_ref(ptr %t42)
  %t51 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t42, ptr %t51
  br label %reuse.join.48
reuse.copy.47:
  %t54 = call ptr @__alloc(i64 24, i32 2)
  %t55 = inttoptr i64 101 to ptr
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
  %t72 = inttoptr i64 102 to ptr
  %t73 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t72, ptr %t73
  call void @__inc_ref(ptr %t62)
  %t71 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t62, ptr %t71
  br label %reuse.join.68
reuse.copy.67:
  %t74 = call ptr @__alloc(i64 24, i32 2)
  %t75 = inttoptr i64 102 to ptr
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
  %t83 = getelementptr ptr, ptr %t13, i32 2
  %t84 = load ptr, ptr %t83
  call void @__inc_ref(ptr %t84)
  %t85 = call ptr @__alloc(i64 32, i32 3)
  %t86 = inttoptr i64 103 to ptr
  %t87 = getelementptr ptr, ptr %t85, i32 0
  store ptr %t86, ptr %t87
  call void @__inc_ref(ptr %t82)
  %t88 = getelementptr ptr, ptr %t85, i32 1
  store ptr %t82, ptr %t88
  call void @__inc_ref(ptr %t84)
  %t89 = getelementptr ptr, ptr %t85, i32 2
  store ptr %t84, ptr %t89
  call void @__inc_ref(ptr %t15)
  %t90 = getelementptr ptr, ptr %t85, i32 3
  store ptr %t15, ptr %t90
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t84)
  call void @__free_recursive(ptr %t82)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t85, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.31.91:
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
  %t103 = inttoptr i64 104 to ptr
  %t104 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t103, ptr %t104
  call void @__inc_ref(ptr %t93)
  %t102 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t93, ptr %t102
  br label %reuse.join.99
reuse.copy.98:
  %t105 = call ptr @__alloc(i64 24, i32 2)
  %t106 = inttoptr i64 104 to ptr
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
tco.case.arm.32.111:
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
  %t123 = inttoptr i64 105 to ptr
  %t124 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t123, ptr %t124
  call void @__inc_ref(ptr %t113)
  %t122 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t113, ptr %t122
  br label %reuse.join.119
reuse.copy.118:
  %t125 = call ptr @__alloc(i64 24, i32 2)
  %t126 = inttoptr i64 105 to ptr
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
tco.case.arm.33.131:
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
  %t143 = inttoptr i64 106 to ptr
  %t144 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t143, ptr %t144
  call void @__inc_ref(ptr %t133)
  %t142 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t133, ptr %t142
  br label %reuse.join.139
reuse.copy.138:
  %t145 = call ptr @__alloc(i64 24, i32 2)
  %t146 = inttoptr i64 106 to ptr
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
tco.case.arm.34.151:
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
  %t163 = inttoptr i64 107 to ptr
  %t164 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t163, ptr %t164
  call void @__inc_ref(ptr %t153)
  %t162 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t153, ptr %t162
  br label %reuse.join.159
reuse.copy.158:
  %t165 = call ptr @__alloc(i64 24, i32 2)
  %t166 = inttoptr i64 107 to ptr
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
tco.case.arm.35.171:
  %t172 = getelementptr ptr, ptr %t13, i32 1
  %t173 = load ptr, ptr %t172
  call void @__inc_ref(ptr %t173)
  %t174 = getelementptr i8, ptr %t5, i64 -8
  %t175 = load i32, ptr %t174
  %t176 = icmp eq i32 %t175, 1
  br i1 %t176, label %reuse.in_place.177, label %reuse.copy.178
reuse.in_place.177:
  %t180 = getelementptr ptr, ptr %t5, i32 1
  %t181 = load ptr, ptr %t180
  call void @__free_recursive(ptr %t181)
  %t183 = inttoptr i64 108 to ptr
  %t184 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t183, ptr %t184
  call void @__inc_ref(ptr %t173)
  %t182 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t173, ptr %t182
  br label %reuse.join.179
reuse.copy.178:
  %t185 = call ptr @__alloc(i64 24, i32 2)
  %t186 = inttoptr i64 108 to ptr
  %t187 = getelementptr ptr, ptr %t185, i32 0
  store ptr %t186, ptr %t187
  call void @__inc_ref(ptr %t173)
  %t188 = getelementptr ptr, ptr %t185, i32 1
  store ptr %t173, ptr %t188
  call void @__inc_ref(ptr %t15)
  %t189 = getelementptr ptr, ptr %t185, i32 2
  store ptr %t15, ptr %t189
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.179
reuse.join.179:
  %t190 = phi ptr [ %t5, %reuse.in_place.177 ], [ %t185, %reuse.copy.178 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t173)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t190, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.36.191:
  %t192 = getelementptr ptr, ptr %t13, i32 1
  %t193 = load ptr, ptr %t192
  call void @__inc_ref(ptr %t193)
  %t194 = getelementptr i8, ptr %t5, i64 -8
  %t195 = load i32, ptr %t194
  %t196 = icmp eq i32 %t195, 1
  br i1 %t196, label %reuse.in_place.197, label %reuse.copy.198
reuse.in_place.197:
  %t200 = getelementptr ptr, ptr %t5, i32 1
  %t201 = load ptr, ptr %t200
  call void @__free_recursive(ptr %t201)
  %t203 = inttoptr i64 109 to ptr
  %t204 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t203, ptr %t204
  call void @__inc_ref(ptr %t193)
  %t202 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t193, ptr %t202
  br label %reuse.join.199
reuse.copy.198:
  %t205 = call ptr @__alloc(i64 24, i32 2)
  %t206 = inttoptr i64 109 to ptr
  %t207 = getelementptr ptr, ptr %t205, i32 0
  store ptr %t206, ptr %t207
  call void @__inc_ref(ptr %t193)
  %t208 = getelementptr ptr, ptr %t205, i32 1
  store ptr %t193, ptr %t208
  call void @__inc_ref(ptr %t15)
  %t209 = getelementptr ptr, ptr %t205, i32 2
  store ptr %t15, ptr %t209
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.199
reuse.join.199:
  %t210 = phi ptr [ %t5, %reuse.in_place.197 ], [ %t205, %reuse.copy.198 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t193)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t210, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.37.211:
  %t212 = getelementptr ptr, ptr %t13, i32 1
  %t213 = load ptr, ptr %t212
  call void @__inc_ref(ptr %t213)
  %t214 = getelementptr i8, ptr %t5, i64 -8
  %t215 = load i32, ptr %t214
  %t216 = icmp eq i32 %t215, 1
  br i1 %t216, label %reuse.in_place.217, label %reuse.copy.218
reuse.in_place.217:
  %t220 = getelementptr ptr, ptr %t5, i32 1
  %t221 = load ptr, ptr %t220
  call void @__free_recursive(ptr %t221)
  %t223 = inttoptr i64 110 to ptr
  %t224 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t223, ptr %t224
  call void @__inc_ref(ptr %t213)
  %t222 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t213, ptr %t222
  br label %reuse.join.219
reuse.copy.218:
  %t225 = call ptr @__alloc(i64 24, i32 2)
  %t226 = inttoptr i64 110 to ptr
  %t227 = getelementptr ptr, ptr %t225, i32 0
  store ptr %t226, ptr %t227
  call void @__inc_ref(ptr %t213)
  %t228 = getelementptr ptr, ptr %t225, i32 1
  store ptr %t213, ptr %t228
  call void @__inc_ref(ptr %t15)
  %t229 = getelementptr ptr, ptr %t225, i32 2
  store ptr %t15, ptr %t229
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.219
reuse.join.219:
  %t230 = phi ptr [ %t5, %reuse.in_place.217 ], [ %t225, %reuse.copy.218 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t213)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t230, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.38.231:
  %t232 = getelementptr ptr, ptr %t13, i32 1
  %t233 = load ptr, ptr %t232
  call void @__inc_ref(ptr %t233)
  %t234 = getelementptr i8, ptr %t5, i64 -8
  %t235 = load i32, ptr %t234
  %t236 = icmp eq i32 %t235, 1
  br i1 %t236, label %reuse.in_place.237, label %reuse.copy.238
reuse.in_place.237:
  %t240 = getelementptr ptr, ptr %t5, i32 1
  %t241 = load ptr, ptr %t240
  call void @__free_recursive(ptr %t241)
  %t243 = inttoptr i64 111 to ptr
  %t244 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t243, ptr %t244
  call void @__inc_ref(ptr %t233)
  %t242 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t233, ptr %t242
  br label %reuse.join.239
reuse.copy.238:
  %t245 = call ptr @__alloc(i64 24, i32 2)
  %t246 = inttoptr i64 111 to ptr
  %t247 = getelementptr ptr, ptr %t245, i32 0
  store ptr %t246, ptr %t247
  call void @__inc_ref(ptr %t233)
  %t248 = getelementptr ptr, ptr %t245, i32 1
  store ptr %t233, ptr %t248
  call void @__inc_ref(ptr %t15)
  %t249 = getelementptr ptr, ptr %t245, i32 2
  store ptr %t15, ptr %t249
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.239
reuse.join.239:
  %t250 = phi ptr [ %t5, %reuse.in_place.237 ], [ %t245, %reuse.copy.238 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t233)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t250, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.39.251:
  %t252 = getelementptr ptr, ptr %t13, i32 1
  %t253 = load ptr, ptr %t252
  call void @__inc_ref(ptr %t253)
  %t254 = getelementptr i8, ptr %t5, i64 -8
  %t255 = load i32, ptr %t254
  %t256 = icmp eq i32 %t255, 1
  br i1 %t256, label %reuse.in_place.257, label %reuse.copy.258
reuse.in_place.257:
  %t260 = getelementptr ptr, ptr %t5, i32 1
  %t261 = load ptr, ptr %t260
  call void @__free_recursive(ptr %t261)
  %t263 = inttoptr i64 112 to ptr
  %t264 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t263, ptr %t264
  call void @__inc_ref(ptr %t253)
  %t262 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t253, ptr %t262
  br label %reuse.join.259
reuse.copy.258:
  %t265 = call ptr @__alloc(i64 24, i32 2)
  %t266 = inttoptr i64 112 to ptr
  %t267 = getelementptr ptr, ptr %t265, i32 0
  store ptr %t266, ptr %t267
  call void @__inc_ref(ptr %t253)
  %t268 = getelementptr ptr, ptr %t265, i32 1
  store ptr %t253, ptr %t268
  call void @__inc_ref(ptr %t15)
  %t269 = getelementptr ptr, ptr %t265, i32 2
  store ptr %t15, ptr %t269
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.259
reuse.join.259:
  %t270 = phi ptr [ %t5, %reuse.in_place.257 ], [ %t265, %reuse.copy.258 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t253)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t270, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.40.271:
  %t272 = getelementptr ptr, ptr %t13, i32 1
  %t273 = load ptr, ptr %t272
  call void @__inc_ref(ptr %t273)
  %t274 = getelementptr i8, ptr %t5, i64 -8
  %t275 = load i32, ptr %t274
  %t276 = icmp eq i32 %t275, 1
  br i1 %t276, label %reuse.in_place.277, label %reuse.copy.278
reuse.in_place.277:
  %t280 = getelementptr ptr, ptr %t5, i32 1
  %t281 = load ptr, ptr %t280
  call void @__free_recursive(ptr %t281)
  %t283 = inttoptr i64 113 to ptr
  %t284 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t283, ptr %t284
  call void @__inc_ref(ptr %t273)
  %t282 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t273, ptr %t282
  br label %reuse.join.279
reuse.copy.278:
  %t285 = call ptr @__alloc(i64 24, i32 2)
  %t286 = inttoptr i64 113 to ptr
  %t287 = getelementptr ptr, ptr %t285, i32 0
  store ptr %t286, ptr %t287
  call void @__inc_ref(ptr %t273)
  %t288 = getelementptr ptr, ptr %t285, i32 1
  store ptr %t273, ptr %t288
  call void @__inc_ref(ptr %t15)
  %t289 = getelementptr ptr, ptr %t285, i32 2
  store ptr %t15, ptr %t289
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.279
reuse.join.279:
  %t290 = phi ptr [ %t5, %reuse.in_place.277 ], [ %t285, %reuse.copy.278 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t273)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t290, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.41.291:
  %t292 = getelementptr ptr, ptr %t13, i32 1
  %t293 = load ptr, ptr %t292
  call void @__inc_ref(ptr %t293)
  %t294 = getelementptr i8, ptr %t5, i64 -8
  %t295 = load i32, ptr %t294
  %t296 = icmp eq i32 %t295, 1
  br i1 %t296, label %reuse.in_place.297, label %reuse.copy.298
reuse.in_place.297:
  %t300 = getelementptr ptr, ptr %t5, i32 1
  %t301 = load ptr, ptr %t300
  call void @__free_recursive(ptr %t301)
  %t303 = inttoptr i64 114 to ptr
  %t304 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t303, ptr %t304
  call void @__inc_ref(ptr %t293)
  %t302 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t293, ptr %t302
  br label %reuse.join.299
reuse.copy.298:
  %t305 = call ptr @__alloc(i64 24, i32 2)
  %t306 = inttoptr i64 114 to ptr
  %t307 = getelementptr ptr, ptr %t305, i32 0
  store ptr %t306, ptr %t307
  call void @__inc_ref(ptr %t293)
  %t308 = getelementptr ptr, ptr %t305, i32 1
  store ptr %t293, ptr %t308
  call void @__inc_ref(ptr %t15)
  %t309 = getelementptr ptr, ptr %t305, i32 2
  store ptr %t15, ptr %t309
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.299
reuse.join.299:
  %t310 = phi ptr [ %t5, %reuse.in_place.297 ], [ %t305, %reuse.copy.298 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t293)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t310, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.42.311:
  %t312 = getelementptr ptr, ptr %t13, i32 1
  %t313 = load ptr, ptr %t312
  call void @__inc_ref(ptr %t313)
  %t314 = getelementptr i8, ptr %t5, i64 -8
  %t315 = load i32, ptr %t314
  %t316 = icmp eq i32 %t315, 1
  br i1 %t316, label %reuse.in_place.317, label %reuse.copy.318
reuse.in_place.317:
  %t320 = getelementptr ptr, ptr %t5, i32 1
  %t321 = load ptr, ptr %t320
  call void @__free_recursive(ptr %t321)
  %t323 = inttoptr i64 115 to ptr
  %t324 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t323, ptr %t324
  call void @__inc_ref(ptr %t313)
  %t322 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t313, ptr %t322
  br label %reuse.join.319
reuse.copy.318:
  %t325 = call ptr @__alloc(i64 24, i32 2)
  %t326 = inttoptr i64 115 to ptr
  %t327 = getelementptr ptr, ptr %t325, i32 0
  store ptr %t326, ptr %t327
  call void @__inc_ref(ptr %t313)
  %t328 = getelementptr ptr, ptr %t325, i32 1
  store ptr %t313, ptr %t328
  call void @__inc_ref(ptr %t15)
  %t329 = getelementptr ptr, ptr %t325, i32 2
  store ptr %t15, ptr %t329
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.319
reuse.join.319:
  %t330 = phi ptr [ %t5, %reuse.in_place.317 ], [ %t325, %reuse.copy.318 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t313)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t330, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.43.331:
  %t332 = getelementptr ptr, ptr %t13, i32 1
  %t333 = load ptr, ptr %t332
  call void @__inc_ref(ptr %t333)
  %t334 = getelementptr ptr, ptr %t13, i32 2
  %t335 = load ptr, ptr %t334
  call void @__inc_ref(ptr %t335)
  %t336 = call ptr @__alloc(i64 32, i32 3)
  %t337 = inttoptr i64 116 to ptr
  %t338 = getelementptr ptr, ptr %t336, i32 0
  store ptr %t337, ptr %t338
  call void @__inc_ref(ptr %t333)
  %t339 = getelementptr ptr, ptr %t336, i32 1
  store ptr %t333, ptr %t339
  call void @__inc_ref(ptr %t335)
  %t340 = getelementptr ptr, ptr %t336, i32 2
  store ptr %t335, ptr %t340
  call void @__inc_ref(ptr %t15)
  %t341 = getelementptr ptr, ptr %t336, i32 3
  store ptr %t15, ptr %t341
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t335)
  call void @__free_recursive(ptr %t333)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t336, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.44.342:
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
  %t354 = inttoptr i64 117 to ptr
  %t355 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t354, ptr %t355
  call void @__inc_ref(ptr %t344)
  %t353 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t344, ptr %t353
  br label %reuse.join.350
reuse.copy.349:
  %t356 = call ptr @__alloc(i64 24, i32 2)
  %t357 = inttoptr i64 117 to ptr
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
tco.case.arm.45.362:
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
  %t374 = inttoptr i64 118 to ptr
  %t375 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t374, ptr %t375
  call void @__inc_ref(ptr %t364)
  %t373 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t364, ptr %t373
  br label %reuse.join.370
reuse.copy.369:
  %t376 = call ptr @__alloc(i64 24, i32 2)
  %t377 = inttoptr i64 118 to ptr
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
tco.case.arm.46.382:
  %t383 = getelementptr ptr, ptr %t13, i32 1
  %t384 = load ptr, ptr %t383
  call void @__inc_ref(ptr %t384)
  %t385 = getelementptr i8, ptr %t5, i64 -8
  %t386 = load i32, ptr %t385
  %t387 = icmp eq i32 %t386, 1
  br i1 %t387, label %reuse.in_place.388, label %reuse.copy.389
reuse.in_place.388:
  %t391 = getelementptr ptr, ptr %t5, i32 1
  %t392 = load ptr, ptr %t391
  call void @__free_recursive(ptr %t392)
  %t394 = inttoptr i64 119 to ptr
  %t395 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t394, ptr %t395
  call void @__inc_ref(ptr %t384)
  %t393 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t384, ptr %t393
  br label %reuse.join.390
reuse.copy.389:
  %t396 = call ptr @__alloc(i64 24, i32 2)
  %t397 = inttoptr i64 119 to ptr
  %t398 = getelementptr ptr, ptr %t396, i32 0
  store ptr %t397, ptr %t398
  call void @__inc_ref(ptr %t384)
  %t399 = getelementptr ptr, ptr %t396, i32 1
  store ptr %t384, ptr %t399
  call void @__inc_ref(ptr %t15)
  %t400 = getelementptr ptr, ptr %t396, i32 2
  store ptr %t15, ptr %t400
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.390
reuse.join.390:
  %t401 = phi ptr [ %t5, %reuse.in_place.388 ], [ %t396, %reuse.copy.389 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t384)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t401, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.47.402:
  %t403 = getelementptr ptr, ptr %t13, i32 1
  %t404 = load ptr, ptr %t403
  call void @__inc_ref(ptr %t404)
  %t405 = getelementptr i8, ptr %t5, i64 -8
  %t406 = load i32, ptr %t405
  %t407 = icmp eq i32 %t406, 1
  br i1 %t407, label %reuse.in_place.408, label %reuse.copy.409
reuse.in_place.408:
  %t411 = getelementptr ptr, ptr %t5, i32 1
  %t412 = load ptr, ptr %t411
  call void @__free_recursive(ptr %t412)
  %t414 = inttoptr i64 120 to ptr
  %t415 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t414, ptr %t415
  call void @__inc_ref(ptr %t404)
  %t413 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t404, ptr %t413
  br label %reuse.join.410
reuse.copy.409:
  %t416 = call ptr @__alloc(i64 24, i32 2)
  %t417 = inttoptr i64 120 to ptr
  %t418 = getelementptr ptr, ptr %t416, i32 0
  store ptr %t417, ptr %t418
  call void @__inc_ref(ptr %t404)
  %t419 = getelementptr ptr, ptr %t416, i32 1
  store ptr %t404, ptr %t419
  call void @__inc_ref(ptr %t15)
  %t420 = getelementptr ptr, ptr %t416, i32 2
  store ptr %t15, ptr %t420
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.410
reuse.join.410:
  %t421 = phi ptr [ %t5, %reuse.in_place.408 ], [ %t416, %reuse.copy.409 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t404)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t421, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.48.422:
  %t423 = getelementptr ptr, ptr %t13, i32 1
  %t424 = load ptr, ptr %t423
  call void @__inc_ref(ptr %t424)
  %t425 = getelementptr i8, ptr %t5, i64 -8
  %t426 = load i32, ptr %t425
  %t427 = icmp eq i32 %t426, 1
  br i1 %t427, label %reuse.in_place.428, label %reuse.copy.429
reuse.in_place.428:
  %t431 = getelementptr ptr, ptr %t5, i32 1
  %t432 = load ptr, ptr %t431
  call void @__free_recursive(ptr %t432)
  %t434 = inttoptr i64 121 to ptr
  %t435 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t434, ptr %t435
  call void @__inc_ref(ptr %t424)
  %t433 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t424, ptr %t433
  br label %reuse.join.430
reuse.copy.429:
  %t436 = call ptr @__alloc(i64 24, i32 2)
  %t437 = inttoptr i64 121 to ptr
  %t438 = getelementptr ptr, ptr %t436, i32 0
  store ptr %t437, ptr %t438
  call void @__inc_ref(ptr %t424)
  %t439 = getelementptr ptr, ptr %t436, i32 1
  store ptr %t424, ptr %t439
  call void @__inc_ref(ptr %t15)
  %t440 = getelementptr ptr, ptr %t436, i32 2
  store ptr %t15, ptr %t440
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.430
reuse.join.430:
  %t441 = phi ptr [ %t5, %reuse.in_place.428 ], [ %t436, %reuse.copy.429 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t424)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t441, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.49.442:
  %t443 = getelementptr ptr, ptr %t13, i32 1
  %t444 = load ptr, ptr %t443
  call void @__inc_ref(ptr %t444)
  %t445 = getelementptr i8, ptr %t5, i64 -8
  %t446 = load i32, ptr %t445
  %t447 = icmp eq i32 %t446, 1
  br i1 %t447, label %reuse.in_place.448, label %reuse.copy.449
reuse.in_place.448:
  %t451 = getelementptr ptr, ptr %t5, i32 1
  %t452 = load ptr, ptr %t451
  call void @__free_recursive(ptr %t452)
  %t454 = inttoptr i64 122 to ptr
  %t455 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t454, ptr %t455
  call void @__inc_ref(ptr %t444)
  %t453 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t444, ptr %t453
  br label %reuse.join.450
reuse.copy.449:
  %t456 = call ptr @__alloc(i64 24, i32 2)
  %t457 = inttoptr i64 122 to ptr
  %t458 = getelementptr ptr, ptr %t456, i32 0
  store ptr %t457, ptr %t458
  call void @__inc_ref(ptr %t444)
  %t459 = getelementptr ptr, ptr %t456, i32 1
  store ptr %t444, ptr %t459
  call void @__inc_ref(ptr %t15)
  %t460 = getelementptr ptr, ptr %t456, i32 2
  store ptr %t15, ptr %t460
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.450
reuse.join.450:
  %t461 = phi ptr [ %t5, %reuse.in_place.448 ], [ %t456, %reuse.copy.449 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t444)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t461, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.50.462:
  %t463 = getelementptr ptr, ptr %t13, i32 1
  %t464 = load ptr, ptr %t463
  call void @__inc_ref(ptr %t464)
  %t465 = getelementptr i8, ptr %t5, i64 -8
  %t466 = load i32, ptr %t465
  %t467 = icmp eq i32 %t466, 1
  br i1 %t467, label %reuse.in_place.468, label %reuse.copy.469
reuse.in_place.468:
  %t471 = getelementptr ptr, ptr %t5, i32 1
  %t472 = load ptr, ptr %t471
  call void @__free_recursive(ptr %t472)
  %t474 = inttoptr i64 123 to ptr
  %t475 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t474, ptr %t475
  call void @__inc_ref(ptr %t464)
  %t473 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t464, ptr %t473
  br label %reuse.join.470
reuse.copy.469:
  %t476 = call ptr @__alloc(i64 24, i32 2)
  %t477 = inttoptr i64 123 to ptr
  %t478 = getelementptr ptr, ptr %t476, i32 0
  store ptr %t477, ptr %t478
  call void @__inc_ref(ptr %t464)
  %t479 = getelementptr ptr, ptr %t476, i32 1
  store ptr %t464, ptr %t479
  call void @__inc_ref(ptr %t15)
  %t480 = getelementptr ptr, ptr %t476, i32 2
  store ptr %t15, ptr %t480
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.470
reuse.join.470:
  %t481 = phi ptr [ %t5, %reuse.in_place.468 ], [ %t476, %reuse.copy.469 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t464)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t481, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.51.482:
  %t483 = getelementptr ptr, ptr %t13, i32 1
  %t484 = load ptr, ptr %t483
  call void @__inc_ref(ptr %t484)
  %t485 = getelementptr i8, ptr %t5, i64 -8
  %t486 = load i32, ptr %t485
  %t487 = icmp eq i32 %t486, 1
  br i1 %t487, label %reuse.in_place.488, label %reuse.copy.489
reuse.in_place.488:
  %t491 = getelementptr ptr, ptr %t5, i32 1
  %t492 = load ptr, ptr %t491
  call void @__free_recursive(ptr %t492)
  %t494 = inttoptr i64 124 to ptr
  %t495 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t494, ptr %t495
  call void @__inc_ref(ptr %t484)
  %t493 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t484, ptr %t493
  br label %reuse.join.490
reuse.copy.489:
  %t496 = call ptr @__alloc(i64 24, i32 2)
  %t497 = inttoptr i64 124 to ptr
  %t498 = getelementptr ptr, ptr %t496, i32 0
  store ptr %t497, ptr %t498
  call void @__inc_ref(ptr %t484)
  %t499 = getelementptr ptr, ptr %t496, i32 1
  store ptr %t484, ptr %t499
  call void @__inc_ref(ptr %t15)
  %t500 = getelementptr ptr, ptr %t496, i32 2
  store ptr %t15, ptr %t500
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.490
reuse.join.490:
  %t501 = phi ptr [ %t5, %reuse.in_place.488 ], [ %t496, %reuse.copy.489 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t484)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t501, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.52.502:
  %t503 = getelementptr ptr, ptr %t13, i32 1
  %t504 = load ptr, ptr %t503
  call void @__inc_ref(ptr %t504)
  %t505 = getelementptr i8, ptr %t5, i64 -8
  %t506 = load i32, ptr %t505
  %t507 = icmp eq i32 %t506, 1
  br i1 %t507, label %reuse.in_place.508, label %reuse.copy.509
reuse.in_place.508:
  %t511 = getelementptr ptr, ptr %t5, i32 1
  %t512 = load ptr, ptr %t511
  call void @__free_recursive(ptr %t512)
  %t514 = inttoptr i64 125 to ptr
  %t515 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t514, ptr %t515
  call void @__inc_ref(ptr %t504)
  %t513 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t504, ptr %t513
  br label %reuse.join.510
reuse.copy.509:
  %t516 = call ptr @__alloc(i64 24, i32 2)
  %t517 = inttoptr i64 125 to ptr
  %t518 = getelementptr ptr, ptr %t516, i32 0
  store ptr %t517, ptr %t518
  call void @__inc_ref(ptr %t504)
  %t519 = getelementptr ptr, ptr %t516, i32 1
  store ptr %t504, ptr %t519
  call void @__inc_ref(ptr %t15)
  %t520 = getelementptr ptr, ptr %t516, i32 2
  store ptr %t15, ptr %t520
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.510
reuse.join.510:
  %t521 = phi ptr [ %t5, %reuse.in_place.508 ], [ %t516, %reuse.copy.509 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t504)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t521, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.53.522:
  %t523 = getelementptr ptr, ptr %t13, i32 1
  %t524 = load ptr, ptr %t523
  call void @__inc_ref(ptr %t524)
  %t525 = getelementptr i8, ptr %t5, i64 -8
  %t526 = load i32, ptr %t525
  %t527 = icmp eq i32 %t526, 1
  br i1 %t527, label %reuse.in_place.528, label %reuse.copy.529
reuse.in_place.528:
  %t531 = getelementptr ptr, ptr %t5, i32 1
  %t532 = load ptr, ptr %t531
  call void @__free_recursive(ptr %t532)
  %t534 = inttoptr i64 126 to ptr
  %t535 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t534, ptr %t535
  call void @__inc_ref(ptr %t524)
  %t533 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t524, ptr %t533
  br label %reuse.join.530
reuse.copy.529:
  %t536 = call ptr @__alloc(i64 24, i32 2)
  %t537 = inttoptr i64 126 to ptr
  %t538 = getelementptr ptr, ptr %t536, i32 0
  store ptr %t537, ptr %t538
  call void @__inc_ref(ptr %t524)
  %t539 = getelementptr ptr, ptr %t536, i32 1
  store ptr %t524, ptr %t539
  call void @__inc_ref(ptr %t15)
  %t540 = getelementptr ptr, ptr %t536, i32 2
  store ptr %t15, ptr %t540
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.530
reuse.join.530:
  %t541 = phi ptr [ %t5, %reuse.in_place.528 ], [ %t536, %reuse.copy.529 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t524)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t541, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.54.542:
  %t543 = getelementptr ptr, ptr %t13, i32 1
  %t544 = load ptr, ptr %t543
  call void @__inc_ref(ptr %t544)
  %t545 = getelementptr i8, ptr %t5, i64 -8
  %t546 = load i32, ptr %t545
  %t547 = icmp eq i32 %t546, 1
  br i1 %t547, label %reuse.in_place.548, label %reuse.copy.549
reuse.in_place.548:
  %t551 = getelementptr ptr, ptr %t5, i32 1
  %t552 = load ptr, ptr %t551
  call void @__free_recursive(ptr %t552)
  %t554 = inttoptr i64 127 to ptr
  %t555 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t554, ptr %t555
  call void @__inc_ref(ptr %t544)
  %t553 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t544, ptr %t553
  br label %reuse.join.550
reuse.copy.549:
  %t556 = call ptr @__alloc(i64 24, i32 2)
  %t557 = inttoptr i64 127 to ptr
  %t558 = getelementptr ptr, ptr %t556, i32 0
  store ptr %t557, ptr %t558
  call void @__inc_ref(ptr %t544)
  %t559 = getelementptr ptr, ptr %t556, i32 1
  store ptr %t544, ptr %t559
  call void @__inc_ref(ptr %t15)
  %t560 = getelementptr ptr, ptr %t556, i32 2
  store ptr %t15, ptr %t560
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.550
reuse.join.550:
  %t561 = phi ptr [ %t5, %reuse.in_place.548 ], [ %t556, %reuse.copy.549 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t544)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t561, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.55.562:
  %t563 = getelementptr ptr, ptr %t13, i32 1
  %t564 = load ptr, ptr %t563
  call void @__inc_ref(ptr %t564)
  %t565 = getelementptr i8, ptr %t5, i64 -8
  %t566 = load i32, ptr %t565
  %t567 = icmp eq i32 %t566, 1
  br i1 %t567, label %reuse.in_place.568, label %reuse.copy.569
reuse.in_place.568:
  %t571 = getelementptr ptr, ptr %t5, i32 1
  %t572 = load ptr, ptr %t571
  call void @__free_recursive(ptr %t572)
  %t574 = inttoptr i64 128 to ptr
  %t575 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t574, ptr %t575
  call void @__inc_ref(ptr %t564)
  %t573 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t564, ptr %t573
  br label %reuse.join.570
reuse.copy.569:
  %t576 = call ptr @__alloc(i64 24, i32 2)
  %t577 = inttoptr i64 128 to ptr
  %t578 = getelementptr ptr, ptr %t576, i32 0
  store ptr %t577, ptr %t578
  call void @__inc_ref(ptr %t564)
  %t579 = getelementptr ptr, ptr %t576, i32 1
  store ptr %t564, ptr %t579
  call void @__inc_ref(ptr %t15)
  %t580 = getelementptr ptr, ptr %t576, i32 2
  store ptr %t15, ptr %t580
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.570
reuse.join.570:
  %t581 = phi ptr [ %t5, %reuse.in_place.568 ], [ %t576, %reuse.copy.569 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t564)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t581, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.56.582:
  %t583 = getelementptr ptr, ptr %t13, i32 1
  %t584 = load ptr, ptr %t583
  call void @__inc_ref(ptr %t584)
  %t585 = getelementptr i8, ptr %t5, i64 -8
  %t586 = load i32, ptr %t585
  %t587 = icmp eq i32 %t586, 1
  br i1 %t587, label %reuse.in_place.588, label %reuse.copy.589
reuse.in_place.588:
  %t591 = getelementptr ptr, ptr %t5, i32 1
  %t592 = load ptr, ptr %t591
  call void @__free_recursive(ptr %t592)
  %t594 = inttoptr i64 129 to ptr
  %t595 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t594, ptr %t595
  call void @__inc_ref(ptr %t584)
  %t593 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t584, ptr %t593
  br label %reuse.join.590
reuse.copy.589:
  %t596 = call ptr @__alloc(i64 24, i32 2)
  %t597 = inttoptr i64 129 to ptr
  %t598 = getelementptr ptr, ptr %t596, i32 0
  store ptr %t597, ptr %t598
  call void @__inc_ref(ptr %t584)
  %t599 = getelementptr ptr, ptr %t596, i32 1
  store ptr %t584, ptr %t599
  call void @__inc_ref(ptr %t15)
  %t600 = getelementptr ptr, ptr %t596, i32 2
  store ptr %t15, ptr %t600
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.590
reuse.join.590:
  %t601 = phi ptr [ %t5, %reuse.in_place.588 ], [ %t596, %reuse.copy.589 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t584)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t601, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.57.602:
  %t603 = getelementptr ptr, ptr %t13, i32 1
  %t604 = load ptr, ptr %t603
  call void @__inc_ref(ptr %t604)
  %t605 = getelementptr i8, ptr %t5, i64 -8
  %t606 = load i32, ptr %t605
  %t607 = icmp eq i32 %t606, 1
  br i1 %t607, label %reuse.in_place.608, label %reuse.copy.609
reuse.in_place.608:
  %t611 = getelementptr ptr, ptr %t5, i32 1
  %t612 = load ptr, ptr %t611
  call void @__free_recursive(ptr %t612)
  %t614 = inttoptr i64 130 to ptr
  %t615 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t614, ptr %t615
  call void @__inc_ref(ptr %t604)
  %t613 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t604, ptr %t613
  br label %reuse.join.610
reuse.copy.609:
  %t616 = call ptr @__alloc(i64 24, i32 2)
  %t617 = inttoptr i64 130 to ptr
  %t618 = getelementptr ptr, ptr %t616, i32 0
  store ptr %t617, ptr %t618
  call void @__inc_ref(ptr %t604)
  %t619 = getelementptr ptr, ptr %t616, i32 1
  store ptr %t604, ptr %t619
  call void @__inc_ref(ptr %t15)
  %t620 = getelementptr ptr, ptr %t616, i32 2
  store ptr %t15, ptr %t620
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.610
reuse.join.610:
  %t621 = phi ptr [ %t5, %reuse.in_place.608 ], [ %t616, %reuse.copy.609 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t604)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t621, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.58.622:
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
  %t634 = inttoptr i64 131 to ptr
  %t635 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t634, ptr %t635
  call void @__inc_ref(ptr %t624)
  %t633 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t624, ptr %t633
  br label %reuse.join.630
reuse.copy.629:
  %t636 = call ptr @__alloc(i64 24, i32 2)
  %t637 = inttoptr i64 131 to ptr
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
tco.case.arm.59.642:
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
  %t654 = inttoptr i64 132 to ptr
  %t655 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t654, ptr %t655
  call void @__inc_ref(ptr %t644)
  %t653 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t644, ptr %t653
  br label %reuse.join.650
reuse.copy.649:
  %t656 = call ptr @__alloc(i64 24, i32 2)
  %t657 = inttoptr i64 132 to ptr
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
tco.case.arm.60.662:
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
  %t674 = inttoptr i64 133 to ptr
  %t675 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t674, ptr %t675
  call void @__inc_ref(ptr %t664)
  %t673 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t664, ptr %t673
  br label %reuse.join.670
reuse.copy.669:
  %t676 = call ptr @__alloc(i64 24, i32 2)
  %t677 = inttoptr i64 133 to ptr
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
tco.case.arm.61.682:
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
  %t694 = inttoptr i64 134 to ptr
  %t695 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t694, ptr %t695
  call void @__inc_ref(ptr %t684)
  %t693 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t684, ptr %t693
  br label %reuse.join.690
reuse.copy.689:
  %t696 = call ptr @__alloc(i64 24, i32 2)
  %t697 = inttoptr i64 134 to ptr
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
tco.case.arm.62.702:
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
  %t714 = inttoptr i64 135 to ptr
  %t715 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t714, ptr %t715
  call void @__inc_ref(ptr %t704)
  %t713 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t704, ptr %t713
  br label %reuse.join.710
reuse.copy.709:
  %t716 = call ptr @__alloc(i64 24, i32 2)
  %t717 = inttoptr i64 135 to ptr
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
tco.case.arm.63.722:
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
  %t734 = inttoptr i64 136 to ptr
  %t735 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t734, ptr %t735
  call void @__inc_ref(ptr %t724)
  %t733 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t724, ptr %t733
  br label %reuse.join.730
reuse.copy.729:
  %t736 = call ptr @__alloc(i64 24, i32 2)
  %t737 = inttoptr i64 136 to ptr
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
tco.case.arm.64.742:
  %t743 = getelementptr ptr, ptr %t13, i32 1
  %t744 = load ptr, ptr %t743
  call void @__inc_ref(ptr %t744)
  %t745 = getelementptr i8, ptr %t5, i64 -8
  %t746 = load i32, ptr %t745
  %t747 = icmp eq i32 %t746, 1
  br i1 %t747, label %reuse.in_place.748, label %reuse.copy.749
reuse.in_place.748:
  %t751 = getelementptr ptr, ptr %t5, i32 1
  %t752 = load ptr, ptr %t751
  call void @__free_recursive(ptr %t752)
  %t754 = inttoptr i64 137 to ptr
  %t755 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t754, ptr %t755
  call void @__inc_ref(ptr %t744)
  %t753 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t744, ptr %t753
  br label %reuse.join.750
reuse.copy.749:
  %t756 = call ptr @__alloc(i64 24, i32 2)
  %t757 = inttoptr i64 137 to ptr
  %t758 = getelementptr ptr, ptr %t756, i32 0
  store ptr %t757, ptr %t758
  call void @__inc_ref(ptr %t744)
  %t759 = getelementptr ptr, ptr %t756, i32 1
  store ptr %t744, ptr %t759
  call void @__inc_ref(ptr %t15)
  %t760 = getelementptr ptr, ptr %t756, i32 2
  store ptr %t15, ptr %t760
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.750
reuse.join.750:
  %t761 = phi ptr [ %t5, %reuse.in_place.748 ], [ %t756, %reuse.copy.749 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t744)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t761, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.65.762:
  %t763 = getelementptr ptr, ptr %t13, i32 1
  %t764 = load ptr, ptr %t763
  call void @__inc_ref(ptr %t764)
  %t765 = getelementptr i8, ptr %t5, i64 -8
  %t766 = load i32, ptr %t765
  %t767 = icmp eq i32 %t766, 1
  br i1 %t767, label %reuse.in_place.768, label %reuse.copy.769
reuse.in_place.768:
  %t771 = getelementptr ptr, ptr %t5, i32 1
  %t772 = load ptr, ptr %t771
  call void @__free_recursive(ptr %t772)
  %t774 = inttoptr i64 138 to ptr
  %t775 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t774, ptr %t775
  call void @__inc_ref(ptr %t764)
  %t773 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t764, ptr %t773
  br label %reuse.join.770
reuse.copy.769:
  %t776 = call ptr @__alloc(i64 24, i32 2)
  %t777 = inttoptr i64 138 to ptr
  %t778 = getelementptr ptr, ptr %t776, i32 0
  store ptr %t777, ptr %t778
  call void @__inc_ref(ptr %t764)
  %t779 = getelementptr ptr, ptr %t776, i32 1
  store ptr %t764, ptr %t779
  call void @__inc_ref(ptr %t15)
  %t780 = getelementptr ptr, ptr %t776, i32 2
  store ptr %t15, ptr %t780
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.770
reuse.join.770:
  %t781 = phi ptr [ %t5, %reuse.in_place.768 ], [ %t776, %reuse.copy.769 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t764)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t781, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.66.782:
  %t783 = getelementptr ptr, ptr %t13, i32 1
  %t784 = load ptr, ptr %t783
  call void @__inc_ref(ptr %t784)
  %t785 = getelementptr i8, ptr %t5, i64 -8
  %t786 = load i32, ptr %t785
  %t787 = icmp eq i32 %t786, 1
  br i1 %t787, label %reuse.in_place.788, label %reuse.copy.789
reuse.in_place.788:
  %t791 = getelementptr ptr, ptr %t5, i32 1
  %t792 = load ptr, ptr %t791
  call void @__free_recursive(ptr %t792)
  %t794 = inttoptr i64 139 to ptr
  %t795 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t794, ptr %t795
  call void @__inc_ref(ptr %t784)
  %t793 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t784, ptr %t793
  br label %reuse.join.790
reuse.copy.789:
  %t796 = call ptr @__alloc(i64 24, i32 2)
  %t797 = inttoptr i64 139 to ptr
  %t798 = getelementptr ptr, ptr %t796, i32 0
  store ptr %t797, ptr %t798
  call void @__inc_ref(ptr %t784)
  %t799 = getelementptr ptr, ptr %t796, i32 1
  store ptr %t784, ptr %t799
  call void @__inc_ref(ptr %t15)
  %t800 = getelementptr ptr, ptr %t796, i32 2
  store ptr %t15, ptr %t800
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.790
reuse.join.790:
  %t801 = phi ptr [ %t5, %reuse.in_place.788 ], [ %t796, %reuse.copy.789 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t784)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t801, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.67.802:
  %t803 = getelementptr ptr, ptr %t13, i32 1
  %t804 = load ptr, ptr %t803
  call void @__inc_ref(ptr %t804)
  %t805 = getelementptr i8, ptr %t5, i64 -8
  %t806 = load i32, ptr %t805
  %t807 = icmp eq i32 %t806, 1
  br i1 %t807, label %reuse.in_place.808, label %reuse.copy.809
reuse.in_place.808:
  %t811 = getelementptr ptr, ptr %t5, i32 1
  %t812 = load ptr, ptr %t811
  call void @__free_recursive(ptr %t812)
  %t814 = inttoptr i64 140 to ptr
  %t815 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t814, ptr %t815
  call void @__inc_ref(ptr %t804)
  %t813 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t804, ptr %t813
  br label %reuse.join.810
reuse.copy.809:
  %t816 = call ptr @__alloc(i64 24, i32 2)
  %t817 = inttoptr i64 140 to ptr
  %t818 = getelementptr ptr, ptr %t816, i32 0
  store ptr %t817, ptr %t818
  call void @__inc_ref(ptr %t804)
  %t819 = getelementptr ptr, ptr %t816, i32 1
  store ptr %t804, ptr %t819
  call void @__inc_ref(ptr %t15)
  %t820 = getelementptr ptr, ptr %t816, i32 2
  store ptr %t15, ptr %t820
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.810
reuse.join.810:
  %t821 = phi ptr [ %t5, %reuse.in_place.808 ], [ %t816, %reuse.copy.809 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t804)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t821, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.68.822:
  %t823 = getelementptr ptr, ptr %t13, i32 1
  %t824 = load ptr, ptr %t823
  call void @__inc_ref(ptr %t824)
  %t825 = getelementptr i8, ptr %t5, i64 -8
  %t826 = load i32, ptr %t825
  %t827 = icmp eq i32 %t826, 1
  br i1 %t827, label %reuse.in_place.828, label %reuse.copy.829
reuse.in_place.828:
  %t831 = getelementptr ptr, ptr %t5, i32 1
  %t832 = load ptr, ptr %t831
  call void @__free_recursive(ptr %t832)
  %t834 = inttoptr i64 141 to ptr
  %t835 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t834, ptr %t835
  call void @__inc_ref(ptr %t824)
  %t833 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t824, ptr %t833
  br label %reuse.join.830
reuse.copy.829:
  %t836 = call ptr @__alloc(i64 24, i32 2)
  %t837 = inttoptr i64 141 to ptr
  %t838 = getelementptr ptr, ptr %t836, i32 0
  store ptr %t837, ptr %t838
  call void @__inc_ref(ptr %t824)
  %t839 = getelementptr ptr, ptr %t836, i32 1
  store ptr %t824, ptr %t839
  call void @__inc_ref(ptr %t15)
  %t840 = getelementptr ptr, ptr %t836, i32 2
  store ptr %t15, ptr %t840
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.830
reuse.join.830:
  %t841 = phi ptr [ %t5, %reuse.in_place.828 ], [ %t836, %reuse.copy.829 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t824)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t841, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.69.842:
  %t843 = getelementptr ptr, ptr %t13, i32 1
  %t844 = load ptr, ptr %t843
  call void @__inc_ref(ptr %t844)
  %t845 = getelementptr i8, ptr %t5, i64 -8
  %t846 = load i32, ptr %t845
  %t847 = icmp eq i32 %t846, 1
  br i1 %t847, label %reuse.in_place.848, label %reuse.copy.849
reuse.in_place.848:
  %t851 = getelementptr ptr, ptr %t5, i32 1
  %t852 = load ptr, ptr %t851
  call void @__free_recursive(ptr %t852)
  %t854 = inttoptr i64 142 to ptr
  %t855 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t854, ptr %t855
  call void @__inc_ref(ptr %t844)
  %t853 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t844, ptr %t853
  br label %reuse.join.850
reuse.copy.849:
  %t856 = call ptr @__alloc(i64 24, i32 2)
  %t857 = inttoptr i64 142 to ptr
  %t858 = getelementptr ptr, ptr %t856, i32 0
  store ptr %t857, ptr %t858
  call void @__inc_ref(ptr %t844)
  %t859 = getelementptr ptr, ptr %t856, i32 1
  store ptr %t844, ptr %t859
  call void @__inc_ref(ptr %t15)
  %t860 = getelementptr ptr, ptr %t856, i32 2
  store ptr %t15, ptr %t860
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.850
reuse.join.850:
  %t861 = phi ptr [ %t5, %reuse.in_place.848 ], [ %t856, %reuse.copy.849 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t844)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t861, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.70.862:
  %t863 = getelementptr ptr, ptr %t13, i32 1
  %t864 = load ptr, ptr %t863
  call void @__inc_ref(ptr %t864)
  %t865 = getelementptr i8, ptr %t5, i64 -8
  %t866 = load i32, ptr %t865
  %t867 = icmp eq i32 %t866, 1
  br i1 %t867, label %reuse.in_place.868, label %reuse.copy.869
reuse.in_place.868:
  %t871 = getelementptr ptr, ptr %t5, i32 1
  %t872 = load ptr, ptr %t871
  call void @__free_recursive(ptr %t872)
  %t874 = inttoptr i64 143 to ptr
  %t875 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t874, ptr %t875
  call void @__inc_ref(ptr %t864)
  %t873 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t864, ptr %t873
  br label %reuse.join.870
reuse.copy.869:
  %t876 = call ptr @__alloc(i64 24, i32 2)
  %t877 = inttoptr i64 143 to ptr
  %t878 = getelementptr ptr, ptr %t876, i32 0
  store ptr %t877, ptr %t878
  call void @__inc_ref(ptr %t864)
  %t879 = getelementptr ptr, ptr %t876, i32 1
  store ptr %t864, ptr %t879
  call void @__inc_ref(ptr %t15)
  %t880 = getelementptr ptr, ptr %t876, i32 2
  store ptr %t15, ptr %t880
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.870
reuse.join.870:
  %t881 = phi ptr [ %t5, %reuse.in_place.868 ], [ %t876, %reuse.copy.869 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t864)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t881, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.71.882:
  %t883 = getelementptr ptr, ptr %t13, i32 1
  %t884 = load ptr, ptr %t883
  call void @__inc_ref(ptr %t884)
  %t885 = getelementptr i8, ptr %t5, i64 -8
  %t886 = load i32, ptr %t885
  %t887 = icmp eq i32 %t886, 1
  br i1 %t887, label %reuse.in_place.888, label %reuse.copy.889
reuse.in_place.888:
  %t891 = getelementptr ptr, ptr %t5, i32 1
  %t892 = load ptr, ptr %t891
  call void @__free_recursive(ptr %t892)
  %t894 = inttoptr i64 144 to ptr
  %t895 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t894, ptr %t895
  call void @__inc_ref(ptr %t884)
  %t893 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t884, ptr %t893
  br label %reuse.join.890
reuse.copy.889:
  %t896 = call ptr @__alloc(i64 24, i32 2)
  %t897 = inttoptr i64 144 to ptr
  %t898 = getelementptr ptr, ptr %t896, i32 0
  store ptr %t897, ptr %t898
  call void @__inc_ref(ptr %t884)
  %t899 = getelementptr ptr, ptr %t896, i32 1
  store ptr %t884, ptr %t899
  call void @__inc_ref(ptr %t15)
  %t900 = getelementptr ptr, ptr %t896, i32 2
  store ptr %t15, ptr %t900
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.890
reuse.join.890:
  %t901 = phi ptr [ %t5, %reuse.in_place.888 ], [ %t896, %reuse.copy.889 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t884)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t901, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.72.902:
  %t903 = getelementptr ptr, ptr %t13, i32 1
  %t904 = load ptr, ptr %t903
  call void @__inc_ref(ptr %t904)
  %t905 = getelementptr i8, ptr %t5, i64 -8
  %t906 = load i32, ptr %t905
  %t907 = icmp eq i32 %t906, 1
  br i1 %t907, label %reuse.in_place.908, label %reuse.copy.909
reuse.in_place.908:
  %t911 = getelementptr ptr, ptr %t5, i32 1
  %t912 = load ptr, ptr %t911
  call void @__free_recursive(ptr %t912)
  %t914 = inttoptr i64 145 to ptr
  %t915 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t914, ptr %t915
  call void @__inc_ref(ptr %t904)
  %t913 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t904, ptr %t913
  br label %reuse.join.910
reuse.copy.909:
  %t916 = call ptr @__alloc(i64 24, i32 2)
  %t917 = inttoptr i64 145 to ptr
  %t918 = getelementptr ptr, ptr %t916, i32 0
  store ptr %t917, ptr %t918
  call void @__inc_ref(ptr %t904)
  %t919 = getelementptr ptr, ptr %t916, i32 1
  store ptr %t904, ptr %t919
  call void @__inc_ref(ptr %t15)
  %t920 = getelementptr ptr, ptr %t916, i32 2
  store ptr %t15, ptr %t920
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.910
reuse.join.910:
  %t921 = phi ptr [ %t5, %reuse.in_place.908 ], [ %t916, %reuse.copy.909 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t904)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t921, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.73.922:
  %t923 = getelementptr ptr, ptr %t13, i32 1
  %t924 = load ptr, ptr %t923
  call void @__inc_ref(ptr %t924)
  %t925 = getelementptr i8, ptr %t5, i64 -8
  %t926 = load i32, ptr %t925
  %t927 = icmp eq i32 %t926, 1
  br i1 %t927, label %reuse.in_place.928, label %reuse.copy.929
reuse.in_place.928:
  %t931 = getelementptr ptr, ptr %t5, i32 1
  %t932 = load ptr, ptr %t931
  call void @__free_recursive(ptr %t932)
  %t934 = inttoptr i64 146 to ptr
  %t935 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t934, ptr %t935
  call void @__inc_ref(ptr %t924)
  %t933 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t924, ptr %t933
  br label %reuse.join.930
reuse.copy.929:
  %t936 = call ptr @__alloc(i64 24, i32 2)
  %t937 = inttoptr i64 146 to ptr
  %t938 = getelementptr ptr, ptr %t936, i32 0
  store ptr %t937, ptr %t938
  call void @__inc_ref(ptr %t924)
  %t939 = getelementptr ptr, ptr %t936, i32 1
  store ptr %t924, ptr %t939
  call void @__inc_ref(ptr %t15)
  %t940 = getelementptr ptr, ptr %t936, i32 2
  store ptr %t15, ptr %t940
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.930
reuse.join.930:
  %t941 = phi ptr [ %t5, %reuse.in_place.928 ], [ %t936, %reuse.copy.929 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t924)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t941, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.74.942:
  %t943 = getelementptr ptr, ptr %t13, i32 1
  %t944 = load ptr, ptr %t943
  call void @__inc_ref(ptr %t944)
  %t945 = getelementptr ptr, ptr %t13, i32 2
  %t946 = load ptr, ptr %t945
  call void @__inc_ref(ptr %t946)
  %t947 = call ptr @__alloc(i64 32, i32 3)
  %t948 = inttoptr i64 147 to ptr
  %t949 = getelementptr ptr, ptr %t947, i32 0
  store ptr %t948, ptr %t949
  call void @__inc_ref(ptr %t944)
  %t950 = getelementptr ptr, ptr %t947, i32 1
  store ptr %t944, ptr %t950
  call void @__inc_ref(ptr %t946)
  %t951 = getelementptr ptr, ptr %t947, i32 2
  store ptr %t946, ptr %t951
  call void @__inc_ref(ptr %t15)
  %t952 = getelementptr ptr, ptr %t947, i32 3
  store ptr %t15, ptr %t952
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t946)
  call void @__free_recursive(ptr %t944)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t947, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.75.953:
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
  %t965 = inttoptr i64 148 to ptr
  %t966 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t965, ptr %t966
  call void @__inc_ref(ptr %t955)
  %t964 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t955, ptr %t964
  br label %reuse.join.961
reuse.copy.960:
  %t967 = call ptr @__alloc(i64 24, i32 2)
  %t968 = inttoptr i64 148 to ptr
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
tco.case.arm.76.973:
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
  %t985 = inttoptr i64 149 to ptr
  %t986 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t985, ptr %t986
  call void @__inc_ref(ptr %t975)
  %t984 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t975, ptr %t984
  br label %reuse.join.981
reuse.copy.980:
  %t987 = call ptr @__alloc(i64 24, i32 2)
  %t988 = inttoptr i64 149 to ptr
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
tco.case.arm.77.993:
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
  %t1005 = inttoptr i64 150 to ptr
  %t1006 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1005, ptr %t1006
  call void @__inc_ref(ptr %t995)
  %t1004 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t995, ptr %t1004
  br label %reuse.join.1001
reuse.copy.1000:
  %t1007 = call ptr @__alloc(i64 24, i32 2)
  %t1008 = inttoptr i64 150 to ptr
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
tco.case.arm.78.1013:
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
  %t1025 = inttoptr i64 151 to ptr
  %t1026 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1025, ptr %t1026
  call void @__inc_ref(ptr %t1015)
  %t1024 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1015, ptr %t1024
  br label %reuse.join.1021
reuse.copy.1020:
  %t1027 = call ptr @__alloc(i64 24, i32 2)
  %t1028 = inttoptr i64 151 to ptr
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
tco.case.arm.79.1033:
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
  %t1045 = inttoptr i64 152 to ptr
  %t1046 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1045, ptr %t1046
  call void @__inc_ref(ptr %t1035)
  %t1044 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1035, ptr %t1044
  br label %reuse.join.1041
reuse.copy.1040:
  %t1047 = call ptr @__alloc(i64 24, i32 2)
  %t1048 = inttoptr i64 152 to ptr
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
tco.case.arm.80.1053:
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
  %t1065 = inttoptr i64 153 to ptr
  %t1066 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1065, ptr %t1066
  call void @__inc_ref(ptr %t1055)
  %t1064 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1055, ptr %t1064
  br label %reuse.join.1061
reuse.copy.1060:
  %t1067 = call ptr @__alloc(i64 24, i32 2)
  %t1068 = inttoptr i64 153 to ptr
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
tco.case.arm.81.1073:
  %t1074 = getelementptr ptr, ptr %t13, i32 1
  %t1075 = load ptr, ptr %t1074
  call void @__inc_ref(ptr %t1075)
  %t1076 = getelementptr i8, ptr %t5, i64 -8
  %t1077 = load i32, ptr %t1076
  %t1078 = icmp eq i32 %t1077, 1
  br i1 %t1078, label %reuse.in_place.1079, label %reuse.copy.1080
reuse.in_place.1079:
  %t1082 = getelementptr ptr, ptr %t5, i32 1
  %t1083 = load ptr, ptr %t1082
  call void @__free_recursive(ptr %t1083)
  %t1085 = inttoptr i64 154 to ptr
  %t1086 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1085, ptr %t1086
  call void @__inc_ref(ptr %t1075)
  %t1084 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1075, ptr %t1084
  br label %reuse.join.1081
reuse.copy.1080:
  %t1087 = call ptr @__alloc(i64 24, i32 2)
  %t1088 = inttoptr i64 154 to ptr
  %t1089 = getelementptr ptr, ptr %t1087, i32 0
  store ptr %t1088, ptr %t1089
  call void @__inc_ref(ptr %t1075)
  %t1090 = getelementptr ptr, ptr %t1087, i32 1
  store ptr %t1075, ptr %t1090
  call void @__inc_ref(ptr %t15)
  %t1091 = getelementptr ptr, ptr %t1087, i32 2
  store ptr %t15, ptr %t1091
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1081
reuse.join.1081:
  %t1092 = phi ptr [ %t5, %reuse.in_place.1079 ], [ %t1087, %reuse.copy.1080 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1075)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1092, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.82.1093:
  %t1094 = getelementptr ptr, ptr %t13, i32 1
  %t1095 = load ptr, ptr %t1094
  call void @__inc_ref(ptr %t1095)
  %t1096 = getelementptr i8, ptr %t5, i64 -8
  %t1097 = load i32, ptr %t1096
  %t1098 = icmp eq i32 %t1097, 1
  br i1 %t1098, label %reuse.in_place.1099, label %reuse.copy.1100
reuse.in_place.1099:
  %t1102 = getelementptr ptr, ptr %t5, i32 1
  %t1103 = load ptr, ptr %t1102
  call void @__free_recursive(ptr %t1103)
  %t1105 = inttoptr i64 155 to ptr
  %t1106 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1105, ptr %t1106
  call void @__inc_ref(ptr %t1095)
  %t1104 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1095, ptr %t1104
  br label %reuse.join.1101
reuse.copy.1100:
  %t1107 = call ptr @__alloc(i64 24, i32 2)
  %t1108 = inttoptr i64 155 to ptr
  %t1109 = getelementptr ptr, ptr %t1107, i32 0
  store ptr %t1108, ptr %t1109
  call void @__inc_ref(ptr %t1095)
  %t1110 = getelementptr ptr, ptr %t1107, i32 1
  store ptr %t1095, ptr %t1110
  call void @__inc_ref(ptr %t15)
  %t1111 = getelementptr ptr, ptr %t1107, i32 2
  store ptr %t15, ptr %t1111
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1101
reuse.join.1101:
  %t1112 = phi ptr [ %t5, %reuse.in_place.1099 ], [ %t1107, %reuse.copy.1100 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1095)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1112, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.83.1113:
  %t1114 = getelementptr ptr, ptr %t13, i32 1
  %t1115 = load ptr, ptr %t1114
  call void @__inc_ref(ptr %t1115)
  %t1116 = getelementptr i8, ptr %t5, i64 -8
  %t1117 = load i32, ptr %t1116
  %t1118 = icmp eq i32 %t1117, 1
  br i1 %t1118, label %reuse.in_place.1119, label %reuse.copy.1120
reuse.in_place.1119:
  %t1122 = getelementptr ptr, ptr %t5, i32 1
  %t1123 = load ptr, ptr %t1122
  call void @__free_recursive(ptr %t1123)
  %t1125 = inttoptr i64 156 to ptr
  %t1126 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1125, ptr %t1126
  call void @__inc_ref(ptr %t1115)
  %t1124 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1115, ptr %t1124
  br label %reuse.join.1121
reuse.copy.1120:
  %t1127 = call ptr @__alloc(i64 24, i32 2)
  %t1128 = inttoptr i64 156 to ptr
  %t1129 = getelementptr ptr, ptr %t1127, i32 0
  store ptr %t1128, ptr %t1129
  call void @__inc_ref(ptr %t1115)
  %t1130 = getelementptr ptr, ptr %t1127, i32 1
  store ptr %t1115, ptr %t1130
  call void @__inc_ref(ptr %t15)
  %t1131 = getelementptr ptr, ptr %t1127, i32 2
  store ptr %t15, ptr %t1131
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1121
reuse.join.1121:
  %t1132 = phi ptr [ %t5, %reuse.in_place.1119 ], [ %t1127, %reuse.copy.1120 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1115)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1132, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.84.1133:
  %t1134 = getelementptr ptr, ptr %t13, i32 1
  %t1135 = load ptr, ptr %t1134
  call void @__inc_ref(ptr %t1135)
  %t1136 = getelementptr i8, ptr %t5, i64 -8
  %t1137 = load i32, ptr %t1136
  %t1138 = icmp eq i32 %t1137, 1
  br i1 %t1138, label %reuse.in_place.1139, label %reuse.copy.1140
reuse.in_place.1139:
  %t1142 = getelementptr ptr, ptr %t5, i32 1
  %t1143 = load ptr, ptr %t1142
  call void @__free_recursive(ptr %t1143)
  %t1145 = inttoptr i64 157 to ptr
  %t1146 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1145, ptr %t1146
  call void @__inc_ref(ptr %t1135)
  %t1144 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1135, ptr %t1144
  br label %reuse.join.1141
reuse.copy.1140:
  %t1147 = call ptr @__alloc(i64 24, i32 2)
  %t1148 = inttoptr i64 157 to ptr
  %t1149 = getelementptr ptr, ptr %t1147, i32 0
  store ptr %t1148, ptr %t1149
  call void @__inc_ref(ptr %t1135)
  %t1150 = getelementptr ptr, ptr %t1147, i32 1
  store ptr %t1135, ptr %t1150
  call void @__inc_ref(ptr %t15)
  %t1151 = getelementptr ptr, ptr %t1147, i32 2
  store ptr %t15, ptr %t1151
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1141
reuse.join.1141:
  %t1152 = phi ptr [ %t5, %reuse.in_place.1139 ], [ %t1147, %reuse.copy.1140 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1135)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1152, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.85.1153:
  %t1154 = getelementptr ptr, ptr %t13, i32 1
  %t1155 = load ptr, ptr %t1154
  call void @__inc_ref(ptr %t1155)
  %t1156 = getelementptr i8, ptr %t5, i64 -8
  %t1157 = load i32, ptr %t1156
  %t1158 = icmp eq i32 %t1157, 1
  br i1 %t1158, label %reuse.in_place.1159, label %reuse.copy.1160
reuse.in_place.1159:
  %t1162 = getelementptr ptr, ptr %t5, i32 1
  %t1163 = load ptr, ptr %t1162
  call void @__free_recursive(ptr %t1163)
  %t1165 = inttoptr i64 158 to ptr
  %t1166 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1165, ptr %t1166
  call void @__inc_ref(ptr %t1155)
  %t1164 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1155, ptr %t1164
  br label %reuse.join.1161
reuse.copy.1160:
  %t1167 = call ptr @__alloc(i64 24, i32 2)
  %t1168 = inttoptr i64 158 to ptr
  %t1169 = getelementptr ptr, ptr %t1167, i32 0
  store ptr %t1168, ptr %t1169
  call void @__inc_ref(ptr %t1155)
  %t1170 = getelementptr ptr, ptr %t1167, i32 1
  store ptr %t1155, ptr %t1170
  call void @__inc_ref(ptr %t15)
  %t1171 = getelementptr ptr, ptr %t1167, i32 2
  store ptr %t15, ptr %t1171
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1161
reuse.join.1161:
  %t1172 = phi ptr [ %t5, %reuse.in_place.1159 ], [ %t1167, %reuse.copy.1160 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1155)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1172, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.86.1173:
  %t1174 = getelementptr ptr, ptr %t13, i32 1
  %t1175 = load ptr, ptr %t1174
  call void @__inc_ref(ptr %t1175)
  %t1176 = getelementptr i8, ptr %t5, i64 -8
  %t1177 = load i32, ptr %t1176
  %t1178 = icmp eq i32 %t1177, 1
  br i1 %t1178, label %reuse.in_place.1179, label %reuse.copy.1180
reuse.in_place.1179:
  %t1182 = getelementptr ptr, ptr %t5, i32 1
  %t1183 = load ptr, ptr %t1182
  call void @__free_recursive(ptr %t1183)
  %t1185 = inttoptr i64 159 to ptr
  %t1186 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1185, ptr %t1186
  call void @__inc_ref(ptr %t1175)
  %t1184 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1175, ptr %t1184
  br label %reuse.join.1181
reuse.copy.1180:
  %t1187 = call ptr @__alloc(i64 24, i32 2)
  %t1188 = inttoptr i64 159 to ptr
  %t1189 = getelementptr ptr, ptr %t1187, i32 0
  store ptr %t1188, ptr %t1189
  call void @__inc_ref(ptr %t1175)
  %t1190 = getelementptr ptr, ptr %t1187, i32 1
  store ptr %t1175, ptr %t1190
  call void @__inc_ref(ptr %t15)
  %t1191 = getelementptr ptr, ptr %t1187, i32 2
  store ptr %t15, ptr %t1191
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1181
reuse.join.1181:
  %t1192 = phi ptr [ %t5, %reuse.in_place.1179 ], [ %t1187, %reuse.copy.1180 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1175)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1192, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.87.1193:
  %t1194 = getelementptr ptr, ptr %t13, i32 1
  %t1195 = load ptr, ptr %t1194
  call void @__inc_ref(ptr %t1195)
  %t1196 = getelementptr i8, ptr %t5, i64 -8
  %t1197 = load i32, ptr %t1196
  %t1198 = icmp eq i32 %t1197, 1
  br i1 %t1198, label %reuse.in_place.1199, label %reuse.copy.1200
reuse.in_place.1199:
  %t1202 = getelementptr ptr, ptr %t5, i32 1
  %t1203 = load ptr, ptr %t1202
  call void @__free_recursive(ptr %t1203)
  %t1205 = inttoptr i64 160 to ptr
  %t1206 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1205, ptr %t1206
  call void @__inc_ref(ptr %t1195)
  %t1204 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1195, ptr %t1204
  br label %reuse.join.1201
reuse.copy.1200:
  %t1207 = call ptr @__alloc(i64 24, i32 2)
  %t1208 = inttoptr i64 160 to ptr
  %t1209 = getelementptr ptr, ptr %t1207, i32 0
  store ptr %t1208, ptr %t1209
  call void @__inc_ref(ptr %t1195)
  %t1210 = getelementptr ptr, ptr %t1207, i32 1
  store ptr %t1195, ptr %t1210
  call void @__inc_ref(ptr %t15)
  %t1211 = getelementptr ptr, ptr %t1207, i32 2
  store ptr %t15, ptr %t1211
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1201
reuse.join.1201:
  %t1212 = phi ptr [ %t5, %reuse.in_place.1199 ], [ %t1207, %reuse.copy.1200 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1195)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1212, ptr %t3
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
  %t1225 = inttoptr i64 161 to ptr
  %t1226 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1225, ptr %t1226
  call void @__inc_ref(ptr %t1215)
  %t1224 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1215, ptr %t1224
  br label %reuse.join.1221
reuse.copy.1220:
  %t1227 = call ptr @__alloc(i64 24, i32 2)
  %t1228 = inttoptr i64 161 to ptr
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
  %t1245 = inttoptr i64 162 to ptr
  %t1246 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1245, ptr %t1246
  call void @__inc_ref(ptr %t1235)
  %t1244 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1235, ptr %t1244
  br label %reuse.join.1241
reuse.copy.1240:
  %t1247 = call ptr @__alloc(i64 24, i32 2)
  %t1248 = inttoptr i64 162 to ptr
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
  %t1265 = inttoptr i64 163 to ptr
  %t1266 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1265, ptr %t1266
  call void @__inc_ref(ptr %t1255)
  %t1264 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1255, ptr %t1264
  br label %reuse.join.1261
reuse.copy.1260:
  %t1267 = call ptr @__alloc(i64 24, i32 2)
  %t1268 = inttoptr i64 163 to ptr
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
  %t1285 = inttoptr i64 164 to ptr
  %t1286 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1285, ptr %t1286
  call void @__inc_ref(ptr %t1275)
  %t1284 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1275, ptr %t1284
  br label %reuse.join.1281
reuse.copy.1280:
  %t1287 = call ptr @__alloc(i64 24, i32 2)
  %t1288 = inttoptr i64 164 to ptr
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
  %t1305 = inttoptr i64 165 to ptr
  %t1306 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1305, ptr %t1306
  call void @__inc_ref(ptr %t1295)
  %t1304 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1295, ptr %t1304
  br label %reuse.join.1301
reuse.copy.1300:
  %t1307 = call ptr @__alloc(i64 24, i32 2)
  %t1308 = inttoptr i64 165 to ptr
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
  %t1325 = inttoptr i64 166 to ptr
  %t1326 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1325, ptr %t1326
  call void @__inc_ref(ptr %t1315)
  %t1324 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1315, ptr %t1324
  br label %reuse.join.1321
reuse.copy.1320:
  %t1327 = call ptr @__alloc(i64 24, i32 2)
  %t1328 = inttoptr i64 166 to ptr
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
  %t1345 = inttoptr i64 167 to ptr
  %t1346 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1345, ptr %t1346
  call void @__inc_ref(ptr %t1335)
  %t1344 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1335, ptr %t1344
  br label %reuse.join.1341
reuse.copy.1340:
  %t1347 = call ptr @__alloc(i64 24, i32 2)
  %t1348 = inttoptr i64 167 to ptr
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
  %t1365 = inttoptr i64 168 to ptr
  %t1366 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1365, ptr %t1366
  call void @__inc_ref(ptr %t1355)
  %t1364 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1355, ptr %t1364
  br label %reuse.join.1361
reuse.copy.1360:
  %t1367 = call ptr @__alloc(i64 24, i32 2)
  %t1368 = inttoptr i64 168 to ptr
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
  %t1385 = inttoptr i64 169 to ptr
  %t1386 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1385, ptr %t1386
  call void @__inc_ref(ptr %t1375)
  %t1384 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1375, ptr %t1384
  br label %reuse.join.1381
reuse.copy.1380:
  %t1387 = call ptr @__alloc(i64 24, i32 2)
  %t1388 = inttoptr i64 169 to ptr
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
  %t1405 = inttoptr i64 170 to ptr
  %t1406 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1405, ptr %t1406
  call void @__inc_ref(ptr %t1395)
  %t1404 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1395, ptr %t1404
  br label %reuse.join.1401
reuse.copy.1400:
  %t1407 = call ptr @__alloc(i64 24, i32 2)
  %t1408 = inttoptr i64 170 to ptr
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
  %t1425 = inttoptr i64 171 to ptr
  %t1426 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1425, ptr %t1426
  call void @__inc_ref(ptr %t1415)
  %t1424 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1415, ptr %t1424
  br label %reuse.join.1421
reuse.copy.1420:
  %t1427 = call ptr @__alloc(i64 24, i32 2)
  %t1428 = inttoptr i64 171 to ptr
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
tco.case.default.19:
  unreachable
tco.case.arm.100.1433:
  %t1434 = getelementptr ptr, ptr %t5, i32 1
  %t1435 = load ptr, ptr %t1434
  %t1436 = getelementptr ptr, ptr %t5, i32 2
  %t1437 = load ptr, ptr %t1436
  %t1438 = getelementptr i8, ptr %t5, i64 -8
  %t1439 = load i32, ptr %t1438
  %t1440 = icmp eq i32 %t1439, 1
  br i1 %t1440, label %reuse.in_place.1441, label %reuse.copy.1442
reuse.in_place.1441:
  %t1444 = inttoptr i64 99 to ptr
  %t1445 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1444, ptr %t1445
  br label %reuse.join.1443
reuse.copy.1442:
  %t1446 = call ptr @__alloc(i64 24, i32 2)
  %t1447 = inttoptr i64 99 to ptr
  %t1448 = getelementptr ptr, ptr %t1446, i32 0
  store ptr %t1447, ptr %t1448
  call void @__inc_ref(ptr %t1435)
  %t1449 = getelementptr ptr, ptr %t1446, i32 1
  store ptr %t1435, ptr %t1449
  call void @__inc_ref(ptr %t1437)
  %t1450 = getelementptr ptr, ptr %t1446, i32 2
  store ptr %t1437, ptr %t1450
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1443
reuse.join.1443:
  %t1451 = phi ptr [ %t5, %reuse.in_place.1441 ], [ %t1446, %reuse.copy.1442 ]
  %t1452 = call ptr @__alloc(i64 16, i32 1)
  %t1453 = inttoptr i64 221 to ptr
  %t1454 = getelementptr ptr, ptr %t1452, i32 0
  store ptr %t1453, ptr %t1454
  call void @__inc_ref(ptr %t6)
  %t1455 = getelementptr ptr, ptr %t1452, i32 1
  store ptr %t6, ptr %t1455
  call void @__free_recursive(ptr %t6)
  store ptr %t1451, ptr %t3
  store ptr %t1452, ptr %t4
  br label %tco.loop.0
tco.case.arm.101.1456:
  %t1457 = getelementptr ptr, ptr %t5, i32 1
  %t1458 = load ptr, ptr %t1457
  %t1459 = getelementptr ptr, ptr %t5, i32 2
  %t1460 = load ptr, ptr %t1459
  %t1461 = getelementptr i8, ptr %t5, i64 -8
  %t1462 = load i32, ptr %t1461
  %t1463 = icmp eq i32 %t1462, 1
  br i1 %t1463, label %reuse.in_place.1464, label %reuse.copy.1465
reuse.in_place.1464:
  %t1467 = inttoptr i64 99 to ptr
  %t1468 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1467, ptr %t1468
  br label %reuse.join.1466
reuse.copy.1465:
  %t1469 = call ptr @__alloc(i64 24, i32 2)
  %t1470 = inttoptr i64 99 to ptr
  %t1471 = getelementptr ptr, ptr %t1469, i32 0
  store ptr %t1470, ptr %t1471
  call void @__inc_ref(ptr %t1458)
  %t1472 = getelementptr ptr, ptr %t1469, i32 1
  store ptr %t1458, ptr %t1472
  call void @__inc_ref(ptr %t1460)
  %t1473 = getelementptr ptr, ptr %t1469, i32 2
  store ptr %t1460, ptr %t1473
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1466
reuse.join.1466:
  %t1474 = phi ptr [ %t5, %reuse.in_place.1464 ], [ %t1469, %reuse.copy.1465 ]
  %t1475 = call ptr @__alloc(i64 16, i32 1)
  %t1476 = inttoptr i64 222 to ptr
  %t1477 = getelementptr ptr, ptr %t1475, i32 0
  store ptr %t1476, ptr %t1477
  call void @__inc_ref(ptr %t6)
  %t1478 = getelementptr ptr, ptr %t1475, i32 1
  store ptr %t6, ptr %t1478
  call void @__free_recursive(ptr %t6)
  store ptr %t1474, ptr %t3
  store ptr %t1475, ptr %t4
  br label %tco.loop.0
tco.case.arm.102.1479:
  %t1480 = getelementptr ptr, ptr %t5, i32 1
  %t1481 = load ptr, ptr %t1480
  %t1482 = getelementptr ptr, ptr %t5, i32 2
  %t1483 = load ptr, ptr %t1482
  %t1484 = getelementptr i8, ptr %t5, i64 -8
  %t1485 = load i32, ptr %t1484
  %t1486 = icmp eq i32 %t1485, 1
  br i1 %t1486, label %reuse.in_place.1487, label %reuse.copy.1488
reuse.in_place.1487:
  %t1490 = inttoptr i64 99 to ptr
  %t1491 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1490, ptr %t1491
  br label %reuse.join.1489
reuse.copy.1488:
  %t1492 = call ptr @__alloc(i64 24, i32 2)
  %t1493 = inttoptr i64 99 to ptr
  %t1494 = getelementptr ptr, ptr %t1492, i32 0
  store ptr %t1493, ptr %t1494
  call void @__inc_ref(ptr %t1481)
  %t1495 = getelementptr ptr, ptr %t1492, i32 1
  store ptr %t1481, ptr %t1495
  call void @__inc_ref(ptr %t1483)
  %t1496 = getelementptr ptr, ptr %t1492, i32 2
  store ptr %t1483, ptr %t1496
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1489
reuse.join.1489:
  %t1497 = phi ptr [ %t5, %reuse.in_place.1487 ], [ %t1492, %reuse.copy.1488 ]
  %t1498 = call ptr @__alloc(i64 16, i32 1)
  %t1499 = inttoptr i64 223 to ptr
  %t1500 = getelementptr ptr, ptr %t1498, i32 0
  store ptr %t1499, ptr %t1500
  call void @__inc_ref(ptr %t6)
  %t1501 = getelementptr ptr, ptr %t1498, i32 1
  store ptr %t6, ptr %t1501
  call void @__free_recursive(ptr %t6)
  store ptr %t1497, ptr %t3
  store ptr %t1498, ptr %t4
  br label %tco.loop.0
tco.case.arm.103.1502:
  %t1503 = getelementptr ptr, ptr %t5, i32 1
  %t1504 = load ptr, ptr %t1503
  call void @__inc_ref(ptr %t1504)
  %t1505 = getelementptr ptr, ptr %t5, i32 2
  %t1506 = load ptr, ptr %t1505
  call void @__inc_ref(ptr %t1506)
  %t1507 = getelementptr ptr, ptr %t5, i32 3
  %t1508 = load ptr, ptr %t1507
  call void @__inc_ref(ptr %t1508)
  %t1509 = call ptr @__alloc(i64 24, i32 2)
  %t1510 = inttoptr i64 99 to ptr
  %t1511 = getelementptr ptr, ptr %t1509, i32 0
  store ptr %t1510, ptr %t1511
  call void @__inc_ref(ptr %t1504)
  %t1512 = getelementptr ptr, ptr %t1509, i32 1
  store ptr %t1504, ptr %t1512
  call void @__inc_ref(ptr %t1506)
  %t1513 = getelementptr ptr, ptr %t1509, i32 2
  store ptr %t1506, ptr %t1513
  %t1514 = call ptr @__alloc(i64 24, i32 2)
  %t1515 = inttoptr i64 224 to ptr
  %t1516 = getelementptr ptr, ptr %t1514, i32 0
  store ptr %t1515, ptr %t1516
  call void @__inc_ref(ptr %t6)
  %t1517 = getelementptr ptr, ptr %t1514, i32 1
  store ptr %t6, ptr %t1517
  call void @__inc_ref(ptr %t1508)
  %t1518 = getelementptr ptr, ptr %t1514, i32 2
  store ptr %t1508, ptr %t1518
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t1508)
  call void @__free_recursive(ptr %t1506)
  call void @__free_recursive(ptr %t1504)
  store ptr %t1509, ptr %t3
  store ptr %t1514, ptr %t4
  br label %tco.loop.0
tco.case.arm.104.1519:
  %t1520 = getelementptr ptr, ptr %t5, i32 1
  %t1521 = load ptr, ptr %t1520
  %t1522 = getelementptr ptr, ptr %t5, i32 2
  %t1523 = load ptr, ptr %t1522
  %t1524 = getelementptr i8, ptr %t5, i64 -8
  %t1525 = load i32, ptr %t1524
  %t1526 = icmp eq i32 %t1525, 1
  br i1 %t1526, label %reuse.in_place.1527, label %reuse.copy.1528
reuse.in_place.1527:
  %t1530 = inttoptr i64 99 to ptr
  %t1531 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1530, ptr %t1531
  br label %reuse.join.1529
reuse.copy.1528:
  %t1532 = call ptr @__alloc(i64 24, i32 2)
  %t1533 = inttoptr i64 99 to ptr
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
  %t1539 = inttoptr i64 225 to ptr
  %t1540 = getelementptr ptr, ptr %t1538, i32 0
  store ptr %t1539, ptr %t1540
  call void @__inc_ref(ptr %t6)
  %t1541 = getelementptr ptr, ptr %t1538, i32 1
  store ptr %t6, ptr %t1541
  call void @__free_recursive(ptr %t6)
  store ptr %t1537, ptr %t3
  store ptr %t1538, ptr %t4
  br label %tco.loop.0
tco.case.arm.105.1542:
  %t1543 = getelementptr ptr, ptr %t5, i32 1
  %t1544 = load ptr, ptr %t1543
  %t1545 = getelementptr ptr, ptr %t5, i32 2
  %t1546 = load ptr, ptr %t1545
  %t1547 = getelementptr i8, ptr %t5, i64 -8
  %t1548 = load i32, ptr %t1547
  %t1549 = icmp eq i32 %t1548, 1
  br i1 %t1549, label %reuse.in_place.1550, label %reuse.copy.1551
reuse.in_place.1550:
  %t1553 = inttoptr i64 99 to ptr
  %t1554 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1553, ptr %t1554
  br label %reuse.join.1552
reuse.copy.1551:
  %t1555 = call ptr @__alloc(i64 24, i32 2)
  %t1556 = inttoptr i64 99 to ptr
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
  %t1562 = inttoptr i64 226 to ptr
  %t1563 = getelementptr ptr, ptr %t1561, i32 0
  store ptr %t1562, ptr %t1563
  call void @__inc_ref(ptr %t6)
  %t1564 = getelementptr ptr, ptr %t1561, i32 1
  store ptr %t6, ptr %t1564
  call void @__free_recursive(ptr %t6)
  store ptr %t1560, ptr %t3
  store ptr %t1561, ptr %t4
  br label %tco.loop.0
tco.case.arm.106.1565:
  %t1566 = getelementptr ptr, ptr %t5, i32 1
  %t1567 = load ptr, ptr %t1566
  %t1568 = getelementptr ptr, ptr %t5, i32 2
  %t1569 = load ptr, ptr %t1568
  %t1570 = getelementptr i8, ptr %t5, i64 -8
  %t1571 = load i32, ptr %t1570
  %t1572 = icmp eq i32 %t1571, 1
  br i1 %t1572, label %reuse.in_place.1573, label %reuse.copy.1574
reuse.in_place.1573:
  %t1576 = inttoptr i64 99 to ptr
  %t1577 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1576, ptr %t1577
  br label %reuse.join.1575
reuse.copy.1574:
  %t1578 = call ptr @__alloc(i64 24, i32 2)
  %t1579 = inttoptr i64 99 to ptr
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
  %t1585 = inttoptr i64 227 to ptr
  %t1586 = getelementptr ptr, ptr %t1584, i32 0
  store ptr %t1585, ptr %t1586
  call void @__inc_ref(ptr %t6)
  %t1587 = getelementptr ptr, ptr %t1584, i32 1
  store ptr %t6, ptr %t1587
  call void @__free_recursive(ptr %t6)
  store ptr %t1583, ptr %t3
  store ptr %t1584, ptr %t4
  br label %tco.loop.0
tco.case.arm.107.1588:
  %t1589 = getelementptr ptr, ptr %t5, i32 1
  %t1590 = load ptr, ptr %t1589
  %t1591 = getelementptr ptr, ptr %t5, i32 2
  %t1592 = load ptr, ptr %t1591
  %t1593 = getelementptr i8, ptr %t5, i64 -8
  %t1594 = load i32, ptr %t1593
  %t1595 = icmp eq i32 %t1594, 1
  br i1 %t1595, label %reuse.in_place.1596, label %reuse.copy.1597
reuse.in_place.1596:
  %t1599 = inttoptr i64 99 to ptr
  %t1600 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1599, ptr %t1600
  br label %reuse.join.1598
reuse.copy.1597:
  %t1601 = call ptr @__alloc(i64 24, i32 2)
  %t1602 = inttoptr i64 99 to ptr
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
  %t1608 = inttoptr i64 228 to ptr
  %t1609 = getelementptr ptr, ptr %t1607, i32 0
  store ptr %t1608, ptr %t1609
  call void @__inc_ref(ptr %t6)
  %t1610 = getelementptr ptr, ptr %t1607, i32 1
  store ptr %t6, ptr %t1610
  call void @__free_recursive(ptr %t6)
  store ptr %t1606, ptr %t3
  store ptr %t1607, ptr %t4
  br label %tco.loop.0
tco.case.arm.108.1611:
  %t1612 = getelementptr ptr, ptr %t5, i32 1
  %t1613 = load ptr, ptr %t1612
  %t1614 = getelementptr ptr, ptr %t5, i32 2
  %t1615 = load ptr, ptr %t1614
  %t1616 = getelementptr i8, ptr %t5, i64 -8
  %t1617 = load i32, ptr %t1616
  %t1618 = icmp eq i32 %t1617, 1
  br i1 %t1618, label %reuse.in_place.1619, label %reuse.copy.1620
reuse.in_place.1619:
  %t1622 = inttoptr i64 99 to ptr
  %t1623 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1622, ptr %t1623
  br label %reuse.join.1621
reuse.copy.1620:
  %t1624 = call ptr @__alloc(i64 24, i32 2)
  %t1625 = inttoptr i64 99 to ptr
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
  %t1631 = inttoptr i64 229 to ptr
  %t1632 = getelementptr ptr, ptr %t1630, i32 0
  store ptr %t1631, ptr %t1632
  call void @__inc_ref(ptr %t6)
  %t1633 = getelementptr ptr, ptr %t1630, i32 1
  store ptr %t6, ptr %t1633
  call void @__free_recursive(ptr %t6)
  store ptr %t1629, ptr %t3
  store ptr %t1630, ptr %t4
  br label %tco.loop.0
tco.case.arm.109.1634:
  %t1635 = getelementptr ptr, ptr %t5, i32 1
  %t1636 = load ptr, ptr %t1635
  %t1637 = getelementptr ptr, ptr %t5, i32 2
  %t1638 = load ptr, ptr %t1637
  %t1639 = getelementptr i8, ptr %t5, i64 -8
  %t1640 = load i32, ptr %t1639
  %t1641 = icmp eq i32 %t1640, 1
  br i1 %t1641, label %reuse.in_place.1642, label %reuse.copy.1643
reuse.in_place.1642:
  %t1645 = inttoptr i64 99 to ptr
  %t1646 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1645, ptr %t1646
  br label %reuse.join.1644
reuse.copy.1643:
  %t1647 = call ptr @__alloc(i64 24, i32 2)
  %t1648 = inttoptr i64 99 to ptr
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
  %t1654 = inttoptr i64 230 to ptr
  %t1655 = getelementptr ptr, ptr %t1653, i32 0
  store ptr %t1654, ptr %t1655
  call void @__inc_ref(ptr %t6)
  %t1656 = getelementptr ptr, ptr %t1653, i32 1
  store ptr %t6, ptr %t1656
  call void @__free_recursive(ptr %t6)
  store ptr %t1652, ptr %t3
  store ptr %t1653, ptr %t4
  br label %tco.loop.0
tco.case.arm.110.1657:
  %t1658 = getelementptr ptr, ptr %t5, i32 1
  %t1659 = load ptr, ptr %t1658
  %t1660 = getelementptr ptr, ptr %t5, i32 2
  %t1661 = load ptr, ptr %t1660
  %t1662 = getelementptr i8, ptr %t5, i64 -8
  %t1663 = load i32, ptr %t1662
  %t1664 = icmp eq i32 %t1663, 1
  br i1 %t1664, label %reuse.in_place.1665, label %reuse.copy.1666
reuse.in_place.1665:
  %t1668 = inttoptr i64 99 to ptr
  %t1669 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1668, ptr %t1669
  br label %reuse.join.1667
reuse.copy.1666:
  %t1670 = call ptr @__alloc(i64 24, i32 2)
  %t1671 = inttoptr i64 99 to ptr
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
  %t1677 = inttoptr i64 231 to ptr
  %t1678 = getelementptr ptr, ptr %t1676, i32 0
  store ptr %t1677, ptr %t1678
  call void @__inc_ref(ptr %t6)
  %t1679 = getelementptr ptr, ptr %t1676, i32 1
  store ptr %t6, ptr %t1679
  call void @__free_recursive(ptr %t6)
  store ptr %t1675, ptr %t3
  store ptr %t1676, ptr %t4
  br label %tco.loop.0
tco.case.arm.111.1680:
  %t1681 = getelementptr ptr, ptr %t5, i32 1
  %t1682 = load ptr, ptr %t1681
  %t1683 = getelementptr ptr, ptr %t5, i32 2
  %t1684 = load ptr, ptr %t1683
  %t1685 = getelementptr i8, ptr %t5, i64 -8
  %t1686 = load i32, ptr %t1685
  %t1687 = icmp eq i32 %t1686, 1
  br i1 %t1687, label %reuse.in_place.1688, label %reuse.copy.1689
reuse.in_place.1688:
  %t1691 = inttoptr i64 99 to ptr
  %t1692 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1691, ptr %t1692
  br label %reuse.join.1690
reuse.copy.1689:
  %t1693 = call ptr @__alloc(i64 24, i32 2)
  %t1694 = inttoptr i64 99 to ptr
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
  %t1700 = inttoptr i64 232 to ptr
  %t1701 = getelementptr ptr, ptr %t1699, i32 0
  store ptr %t1700, ptr %t1701
  call void @__inc_ref(ptr %t6)
  %t1702 = getelementptr ptr, ptr %t1699, i32 1
  store ptr %t6, ptr %t1702
  call void @__free_recursive(ptr %t6)
  store ptr %t1698, ptr %t3
  store ptr %t1699, ptr %t4
  br label %tco.loop.0
tco.case.arm.112.1703:
  %t1704 = getelementptr ptr, ptr %t5, i32 1
  %t1705 = load ptr, ptr %t1704
  %t1706 = getelementptr ptr, ptr %t5, i32 2
  %t1707 = load ptr, ptr %t1706
  %t1708 = getelementptr i8, ptr %t5, i64 -8
  %t1709 = load i32, ptr %t1708
  %t1710 = icmp eq i32 %t1709, 1
  br i1 %t1710, label %reuse.in_place.1711, label %reuse.copy.1712
reuse.in_place.1711:
  %t1714 = inttoptr i64 99 to ptr
  %t1715 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1714, ptr %t1715
  br label %reuse.join.1713
reuse.copy.1712:
  %t1716 = call ptr @__alloc(i64 24, i32 2)
  %t1717 = inttoptr i64 99 to ptr
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
  %t1723 = inttoptr i64 233 to ptr
  %t1724 = getelementptr ptr, ptr %t1722, i32 0
  store ptr %t1723, ptr %t1724
  call void @__inc_ref(ptr %t6)
  %t1725 = getelementptr ptr, ptr %t1722, i32 1
  store ptr %t6, ptr %t1725
  call void @__free_recursive(ptr %t6)
  store ptr %t1721, ptr %t3
  store ptr %t1722, ptr %t4
  br label %tco.loop.0
tco.case.arm.113.1726:
  %t1727 = getelementptr ptr, ptr %t5, i32 1
  %t1728 = load ptr, ptr %t1727
  %t1729 = getelementptr ptr, ptr %t5, i32 2
  %t1730 = load ptr, ptr %t1729
  %t1731 = getelementptr i8, ptr %t5, i64 -8
  %t1732 = load i32, ptr %t1731
  %t1733 = icmp eq i32 %t1732, 1
  br i1 %t1733, label %reuse.in_place.1734, label %reuse.copy.1735
reuse.in_place.1734:
  %t1737 = inttoptr i64 99 to ptr
  %t1738 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1737, ptr %t1738
  br label %reuse.join.1736
reuse.copy.1735:
  %t1739 = call ptr @__alloc(i64 24, i32 2)
  %t1740 = inttoptr i64 99 to ptr
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
  %t1746 = inttoptr i64 234 to ptr
  %t1747 = getelementptr ptr, ptr %t1745, i32 0
  store ptr %t1746, ptr %t1747
  call void @__inc_ref(ptr %t6)
  %t1748 = getelementptr ptr, ptr %t1745, i32 1
  store ptr %t6, ptr %t1748
  call void @__free_recursive(ptr %t6)
  store ptr %t1744, ptr %t3
  store ptr %t1745, ptr %t4
  br label %tco.loop.0
tco.case.arm.114.1749:
  %t1750 = getelementptr ptr, ptr %t5, i32 1
  %t1751 = load ptr, ptr %t1750
  %t1752 = getelementptr ptr, ptr %t5, i32 2
  %t1753 = load ptr, ptr %t1752
  %t1754 = getelementptr i8, ptr %t5, i64 -8
  %t1755 = load i32, ptr %t1754
  %t1756 = icmp eq i32 %t1755, 1
  br i1 %t1756, label %reuse.in_place.1757, label %reuse.copy.1758
reuse.in_place.1757:
  %t1760 = inttoptr i64 99 to ptr
  %t1761 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1760, ptr %t1761
  br label %reuse.join.1759
reuse.copy.1758:
  %t1762 = call ptr @__alloc(i64 24, i32 2)
  %t1763 = inttoptr i64 99 to ptr
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
  %t1769 = inttoptr i64 235 to ptr
  %t1770 = getelementptr ptr, ptr %t1768, i32 0
  store ptr %t1769, ptr %t1770
  call void @__inc_ref(ptr %t6)
  %t1771 = getelementptr ptr, ptr %t1768, i32 1
  store ptr %t6, ptr %t1771
  call void @__free_recursive(ptr %t6)
  store ptr %t1767, ptr %t3
  store ptr %t1768, ptr %t4
  br label %tco.loop.0
tco.case.arm.115.1772:
  %t1773 = getelementptr ptr, ptr %t5, i32 1
  %t1774 = load ptr, ptr %t1773
  %t1775 = getelementptr ptr, ptr %t5, i32 2
  %t1776 = load ptr, ptr %t1775
  %t1777 = getelementptr i8, ptr %t5, i64 -8
  %t1778 = load i32, ptr %t1777
  %t1779 = icmp eq i32 %t1778, 1
  br i1 %t1779, label %reuse.in_place.1780, label %reuse.copy.1781
reuse.in_place.1780:
  %t1783 = inttoptr i64 99 to ptr
  %t1784 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1783, ptr %t1784
  br label %reuse.join.1782
reuse.copy.1781:
  %t1785 = call ptr @__alloc(i64 24, i32 2)
  %t1786 = inttoptr i64 99 to ptr
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
  %t1792 = inttoptr i64 236 to ptr
  %t1793 = getelementptr ptr, ptr %t1791, i32 0
  store ptr %t1792, ptr %t1793
  call void @__inc_ref(ptr %t6)
  %t1794 = getelementptr ptr, ptr %t1791, i32 1
  store ptr %t6, ptr %t1794
  call void @__free_recursive(ptr %t6)
  store ptr %t1790, ptr %t3
  store ptr %t1791, ptr %t4
  br label %tco.loop.0
tco.case.arm.116.1795:
  %t1796 = getelementptr ptr, ptr %t5, i32 1
  %t1797 = load ptr, ptr %t1796
  call void @__inc_ref(ptr %t1797)
  %t1798 = getelementptr ptr, ptr %t5, i32 2
  %t1799 = load ptr, ptr %t1798
  call void @__inc_ref(ptr %t1799)
  %t1800 = getelementptr ptr, ptr %t5, i32 3
  %t1801 = load ptr, ptr %t1800
  call void @__inc_ref(ptr %t1801)
  %t1802 = call ptr @__alloc(i64 24, i32 2)
  %t1803 = inttoptr i64 99 to ptr
  %t1804 = getelementptr ptr, ptr %t1802, i32 0
  store ptr %t1803, ptr %t1804
  call void @__inc_ref(ptr %t1797)
  %t1805 = getelementptr ptr, ptr %t1802, i32 1
  store ptr %t1797, ptr %t1805
  call void @__inc_ref(ptr %t1799)
  %t1806 = getelementptr ptr, ptr %t1802, i32 2
  store ptr %t1799, ptr %t1806
  %t1807 = call ptr @__alloc(i64 24, i32 2)
  %t1808 = inttoptr i64 237 to ptr
  %t1809 = getelementptr ptr, ptr %t1807, i32 0
  store ptr %t1808, ptr %t1809
  call void @__inc_ref(ptr %t6)
  %t1810 = getelementptr ptr, ptr %t1807, i32 1
  store ptr %t6, ptr %t1810
  call void @__inc_ref(ptr %t1801)
  %t1811 = getelementptr ptr, ptr %t1807, i32 2
  store ptr %t1801, ptr %t1811
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t1801)
  call void @__free_recursive(ptr %t1799)
  call void @__free_recursive(ptr %t1797)
  store ptr %t1802, ptr %t3
  store ptr %t1807, ptr %t4
  br label %tco.loop.0
tco.case.arm.117.1812:
  %t1813 = getelementptr ptr, ptr %t5, i32 1
  %t1814 = load ptr, ptr %t1813
  %t1815 = getelementptr ptr, ptr %t5, i32 2
  %t1816 = load ptr, ptr %t1815
  %t1817 = getelementptr i8, ptr %t5, i64 -8
  %t1818 = load i32, ptr %t1817
  %t1819 = icmp eq i32 %t1818, 1
  br i1 %t1819, label %reuse.in_place.1820, label %reuse.copy.1821
reuse.in_place.1820:
  %t1823 = inttoptr i64 99 to ptr
  %t1824 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1823, ptr %t1824
  br label %reuse.join.1822
reuse.copy.1821:
  %t1825 = call ptr @__alloc(i64 24, i32 2)
  %t1826 = inttoptr i64 99 to ptr
  %t1827 = getelementptr ptr, ptr %t1825, i32 0
  store ptr %t1826, ptr %t1827
  call void @__inc_ref(ptr %t1814)
  %t1828 = getelementptr ptr, ptr %t1825, i32 1
  store ptr %t1814, ptr %t1828
  call void @__inc_ref(ptr %t1816)
  %t1829 = getelementptr ptr, ptr %t1825, i32 2
  store ptr %t1816, ptr %t1829
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1822
reuse.join.1822:
  %t1830 = phi ptr [ %t5, %reuse.in_place.1820 ], [ %t1825, %reuse.copy.1821 ]
  %t1831 = call ptr @__alloc(i64 16, i32 1)
  %t1832 = inttoptr i64 238 to ptr
  %t1833 = getelementptr ptr, ptr %t1831, i32 0
  store ptr %t1832, ptr %t1833
  call void @__inc_ref(ptr %t6)
  %t1834 = getelementptr ptr, ptr %t1831, i32 1
  store ptr %t6, ptr %t1834
  call void @__free_recursive(ptr %t6)
  store ptr %t1830, ptr %t3
  store ptr %t1831, ptr %t4
  br label %tco.loop.0
tco.case.arm.118.1835:
  %t1836 = getelementptr ptr, ptr %t5, i32 1
  %t1837 = load ptr, ptr %t1836
  %t1838 = getelementptr ptr, ptr %t5, i32 2
  %t1839 = load ptr, ptr %t1838
  %t1840 = getelementptr i8, ptr %t5, i64 -8
  %t1841 = load i32, ptr %t1840
  %t1842 = icmp eq i32 %t1841, 1
  br i1 %t1842, label %reuse.in_place.1843, label %reuse.copy.1844
reuse.in_place.1843:
  %t1846 = inttoptr i64 99 to ptr
  %t1847 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1846, ptr %t1847
  br label %reuse.join.1845
reuse.copy.1844:
  %t1848 = call ptr @__alloc(i64 24, i32 2)
  %t1849 = inttoptr i64 99 to ptr
  %t1850 = getelementptr ptr, ptr %t1848, i32 0
  store ptr %t1849, ptr %t1850
  call void @__inc_ref(ptr %t1837)
  %t1851 = getelementptr ptr, ptr %t1848, i32 1
  store ptr %t1837, ptr %t1851
  call void @__inc_ref(ptr %t1839)
  %t1852 = getelementptr ptr, ptr %t1848, i32 2
  store ptr %t1839, ptr %t1852
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1845
reuse.join.1845:
  %t1853 = phi ptr [ %t5, %reuse.in_place.1843 ], [ %t1848, %reuse.copy.1844 ]
  %t1854 = call ptr @__alloc(i64 16, i32 1)
  %t1855 = inttoptr i64 239 to ptr
  %t1856 = getelementptr ptr, ptr %t1854, i32 0
  store ptr %t1855, ptr %t1856
  call void @__inc_ref(ptr %t6)
  %t1857 = getelementptr ptr, ptr %t1854, i32 1
  store ptr %t6, ptr %t1857
  call void @__free_recursive(ptr %t6)
  store ptr %t1853, ptr %t3
  store ptr %t1854, ptr %t4
  br label %tco.loop.0
tco.case.arm.119.1858:
  %t1859 = getelementptr ptr, ptr %t5, i32 1
  %t1860 = load ptr, ptr %t1859
  %t1861 = getelementptr ptr, ptr %t5, i32 2
  %t1862 = load ptr, ptr %t1861
  %t1863 = getelementptr i8, ptr %t5, i64 -8
  %t1864 = load i32, ptr %t1863
  %t1865 = icmp eq i32 %t1864, 1
  br i1 %t1865, label %reuse.in_place.1866, label %reuse.copy.1867
reuse.in_place.1866:
  %t1869 = inttoptr i64 99 to ptr
  %t1870 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1869, ptr %t1870
  br label %reuse.join.1868
reuse.copy.1867:
  %t1871 = call ptr @__alloc(i64 24, i32 2)
  %t1872 = inttoptr i64 99 to ptr
  %t1873 = getelementptr ptr, ptr %t1871, i32 0
  store ptr %t1872, ptr %t1873
  call void @__inc_ref(ptr %t1860)
  %t1874 = getelementptr ptr, ptr %t1871, i32 1
  store ptr %t1860, ptr %t1874
  call void @__inc_ref(ptr %t1862)
  %t1875 = getelementptr ptr, ptr %t1871, i32 2
  store ptr %t1862, ptr %t1875
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1868
reuse.join.1868:
  %t1876 = phi ptr [ %t5, %reuse.in_place.1866 ], [ %t1871, %reuse.copy.1867 ]
  %t1877 = call ptr @__alloc(i64 16, i32 1)
  %t1878 = inttoptr i64 240 to ptr
  %t1879 = getelementptr ptr, ptr %t1877, i32 0
  store ptr %t1878, ptr %t1879
  call void @__inc_ref(ptr %t6)
  %t1880 = getelementptr ptr, ptr %t1877, i32 1
  store ptr %t6, ptr %t1880
  call void @__free_recursive(ptr %t6)
  store ptr %t1876, ptr %t3
  store ptr %t1877, ptr %t4
  br label %tco.loop.0
tco.case.arm.120.1881:
  %t1882 = getelementptr ptr, ptr %t5, i32 1
  %t1883 = load ptr, ptr %t1882
  %t1884 = getelementptr ptr, ptr %t5, i32 2
  %t1885 = load ptr, ptr %t1884
  %t1886 = getelementptr i8, ptr %t5, i64 -8
  %t1887 = load i32, ptr %t1886
  %t1888 = icmp eq i32 %t1887, 1
  br i1 %t1888, label %reuse.in_place.1889, label %reuse.copy.1890
reuse.in_place.1889:
  %t1892 = inttoptr i64 99 to ptr
  %t1893 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1892, ptr %t1893
  br label %reuse.join.1891
reuse.copy.1890:
  %t1894 = call ptr @__alloc(i64 24, i32 2)
  %t1895 = inttoptr i64 99 to ptr
  %t1896 = getelementptr ptr, ptr %t1894, i32 0
  store ptr %t1895, ptr %t1896
  call void @__inc_ref(ptr %t1883)
  %t1897 = getelementptr ptr, ptr %t1894, i32 1
  store ptr %t1883, ptr %t1897
  call void @__inc_ref(ptr %t1885)
  %t1898 = getelementptr ptr, ptr %t1894, i32 2
  store ptr %t1885, ptr %t1898
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1891
reuse.join.1891:
  %t1899 = phi ptr [ %t5, %reuse.in_place.1889 ], [ %t1894, %reuse.copy.1890 ]
  %t1900 = call ptr @__alloc(i64 16, i32 1)
  %t1901 = inttoptr i64 241 to ptr
  %t1902 = getelementptr ptr, ptr %t1900, i32 0
  store ptr %t1901, ptr %t1902
  call void @__inc_ref(ptr %t6)
  %t1903 = getelementptr ptr, ptr %t1900, i32 1
  store ptr %t6, ptr %t1903
  call void @__free_recursive(ptr %t6)
  store ptr %t1899, ptr %t3
  store ptr %t1900, ptr %t4
  br label %tco.loop.0
tco.case.arm.121.1904:
  %t1905 = getelementptr ptr, ptr %t5, i32 1
  %t1906 = load ptr, ptr %t1905
  %t1907 = getelementptr ptr, ptr %t5, i32 2
  %t1908 = load ptr, ptr %t1907
  %t1909 = getelementptr i8, ptr %t5, i64 -8
  %t1910 = load i32, ptr %t1909
  %t1911 = icmp eq i32 %t1910, 1
  br i1 %t1911, label %reuse.in_place.1912, label %reuse.copy.1913
reuse.in_place.1912:
  %t1915 = inttoptr i64 99 to ptr
  %t1916 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1915, ptr %t1916
  br label %reuse.join.1914
reuse.copy.1913:
  %t1917 = call ptr @__alloc(i64 24, i32 2)
  %t1918 = inttoptr i64 99 to ptr
  %t1919 = getelementptr ptr, ptr %t1917, i32 0
  store ptr %t1918, ptr %t1919
  call void @__inc_ref(ptr %t1906)
  %t1920 = getelementptr ptr, ptr %t1917, i32 1
  store ptr %t1906, ptr %t1920
  call void @__inc_ref(ptr %t1908)
  %t1921 = getelementptr ptr, ptr %t1917, i32 2
  store ptr %t1908, ptr %t1921
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1914
reuse.join.1914:
  %t1922 = phi ptr [ %t5, %reuse.in_place.1912 ], [ %t1917, %reuse.copy.1913 ]
  %t1923 = call ptr @__alloc(i64 16, i32 1)
  %t1924 = inttoptr i64 242 to ptr
  %t1925 = getelementptr ptr, ptr %t1923, i32 0
  store ptr %t1924, ptr %t1925
  call void @__inc_ref(ptr %t6)
  %t1926 = getelementptr ptr, ptr %t1923, i32 1
  store ptr %t6, ptr %t1926
  call void @__free_recursive(ptr %t6)
  store ptr %t1922, ptr %t3
  store ptr %t1923, ptr %t4
  br label %tco.loop.0
tco.case.arm.122.1927:
  %t1928 = getelementptr ptr, ptr %t5, i32 1
  %t1929 = load ptr, ptr %t1928
  %t1930 = getelementptr ptr, ptr %t5, i32 2
  %t1931 = load ptr, ptr %t1930
  %t1932 = getelementptr i8, ptr %t5, i64 -8
  %t1933 = load i32, ptr %t1932
  %t1934 = icmp eq i32 %t1933, 1
  br i1 %t1934, label %reuse.in_place.1935, label %reuse.copy.1936
reuse.in_place.1935:
  %t1938 = inttoptr i64 99 to ptr
  %t1939 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1938, ptr %t1939
  br label %reuse.join.1937
reuse.copy.1936:
  %t1940 = call ptr @__alloc(i64 24, i32 2)
  %t1941 = inttoptr i64 99 to ptr
  %t1942 = getelementptr ptr, ptr %t1940, i32 0
  store ptr %t1941, ptr %t1942
  call void @__inc_ref(ptr %t1929)
  %t1943 = getelementptr ptr, ptr %t1940, i32 1
  store ptr %t1929, ptr %t1943
  call void @__inc_ref(ptr %t1931)
  %t1944 = getelementptr ptr, ptr %t1940, i32 2
  store ptr %t1931, ptr %t1944
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1937
reuse.join.1937:
  %t1945 = phi ptr [ %t5, %reuse.in_place.1935 ], [ %t1940, %reuse.copy.1936 ]
  %t1946 = call ptr @__alloc(i64 16, i32 1)
  %t1947 = inttoptr i64 243 to ptr
  %t1948 = getelementptr ptr, ptr %t1946, i32 0
  store ptr %t1947, ptr %t1948
  call void @__inc_ref(ptr %t6)
  %t1949 = getelementptr ptr, ptr %t1946, i32 1
  store ptr %t6, ptr %t1949
  call void @__free_recursive(ptr %t6)
  store ptr %t1945, ptr %t3
  store ptr %t1946, ptr %t4
  br label %tco.loop.0
tco.case.arm.123.1950:
  %t1951 = getelementptr ptr, ptr %t5, i32 1
  %t1952 = load ptr, ptr %t1951
  %t1953 = getelementptr ptr, ptr %t5, i32 2
  %t1954 = load ptr, ptr %t1953
  %t1955 = getelementptr i8, ptr %t5, i64 -8
  %t1956 = load i32, ptr %t1955
  %t1957 = icmp eq i32 %t1956, 1
  br i1 %t1957, label %reuse.in_place.1958, label %reuse.copy.1959
reuse.in_place.1958:
  %t1961 = inttoptr i64 99 to ptr
  %t1962 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1961, ptr %t1962
  br label %reuse.join.1960
reuse.copy.1959:
  %t1963 = call ptr @__alloc(i64 24, i32 2)
  %t1964 = inttoptr i64 99 to ptr
  %t1965 = getelementptr ptr, ptr %t1963, i32 0
  store ptr %t1964, ptr %t1965
  call void @__inc_ref(ptr %t1952)
  %t1966 = getelementptr ptr, ptr %t1963, i32 1
  store ptr %t1952, ptr %t1966
  call void @__inc_ref(ptr %t1954)
  %t1967 = getelementptr ptr, ptr %t1963, i32 2
  store ptr %t1954, ptr %t1967
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1960
reuse.join.1960:
  %t1968 = phi ptr [ %t5, %reuse.in_place.1958 ], [ %t1963, %reuse.copy.1959 ]
  %t1969 = call ptr @__alloc(i64 16, i32 1)
  %t1970 = inttoptr i64 244 to ptr
  %t1971 = getelementptr ptr, ptr %t1969, i32 0
  store ptr %t1970, ptr %t1971
  call void @__inc_ref(ptr %t6)
  %t1972 = getelementptr ptr, ptr %t1969, i32 1
  store ptr %t6, ptr %t1972
  call void @__free_recursive(ptr %t6)
  store ptr %t1968, ptr %t3
  store ptr %t1969, ptr %t4
  br label %tco.loop.0
tco.case.arm.124.1973:
  %t1974 = getelementptr ptr, ptr %t5, i32 1
  %t1975 = load ptr, ptr %t1974
  %t1976 = getelementptr ptr, ptr %t5, i32 2
  %t1977 = load ptr, ptr %t1976
  %t1978 = getelementptr i8, ptr %t5, i64 -8
  %t1979 = load i32, ptr %t1978
  %t1980 = icmp eq i32 %t1979, 1
  br i1 %t1980, label %reuse.in_place.1981, label %reuse.copy.1982
reuse.in_place.1981:
  %t1984 = inttoptr i64 99 to ptr
  %t1985 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1984, ptr %t1985
  br label %reuse.join.1983
reuse.copy.1982:
  %t1986 = call ptr @__alloc(i64 24, i32 2)
  %t1987 = inttoptr i64 99 to ptr
  %t1988 = getelementptr ptr, ptr %t1986, i32 0
  store ptr %t1987, ptr %t1988
  call void @__inc_ref(ptr %t1975)
  %t1989 = getelementptr ptr, ptr %t1986, i32 1
  store ptr %t1975, ptr %t1989
  call void @__inc_ref(ptr %t1977)
  %t1990 = getelementptr ptr, ptr %t1986, i32 2
  store ptr %t1977, ptr %t1990
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1983
reuse.join.1983:
  %t1991 = phi ptr [ %t5, %reuse.in_place.1981 ], [ %t1986, %reuse.copy.1982 ]
  %t1992 = call ptr @__alloc(i64 16, i32 1)
  %t1993 = inttoptr i64 245 to ptr
  %t1994 = getelementptr ptr, ptr %t1992, i32 0
  store ptr %t1993, ptr %t1994
  call void @__inc_ref(ptr %t6)
  %t1995 = getelementptr ptr, ptr %t1992, i32 1
  store ptr %t6, ptr %t1995
  call void @__free_recursive(ptr %t6)
  store ptr %t1991, ptr %t3
  store ptr %t1992, ptr %t4
  br label %tco.loop.0
tco.case.arm.125.1996:
  %t1997 = getelementptr ptr, ptr %t5, i32 1
  %t1998 = load ptr, ptr %t1997
  %t1999 = getelementptr ptr, ptr %t5, i32 2
  %t2000 = load ptr, ptr %t1999
  %t2001 = getelementptr i8, ptr %t5, i64 -8
  %t2002 = load i32, ptr %t2001
  %t2003 = icmp eq i32 %t2002, 1
  br i1 %t2003, label %reuse.in_place.2004, label %reuse.copy.2005
reuse.in_place.2004:
  %t2007 = inttoptr i64 99 to ptr
  %t2008 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2007, ptr %t2008
  br label %reuse.join.2006
reuse.copy.2005:
  %t2009 = call ptr @__alloc(i64 24, i32 2)
  %t2010 = inttoptr i64 99 to ptr
  %t2011 = getelementptr ptr, ptr %t2009, i32 0
  store ptr %t2010, ptr %t2011
  call void @__inc_ref(ptr %t1998)
  %t2012 = getelementptr ptr, ptr %t2009, i32 1
  store ptr %t1998, ptr %t2012
  call void @__inc_ref(ptr %t2000)
  %t2013 = getelementptr ptr, ptr %t2009, i32 2
  store ptr %t2000, ptr %t2013
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2006
reuse.join.2006:
  %t2014 = phi ptr [ %t5, %reuse.in_place.2004 ], [ %t2009, %reuse.copy.2005 ]
  %t2015 = call ptr @__alloc(i64 16, i32 1)
  %t2016 = inttoptr i64 246 to ptr
  %t2017 = getelementptr ptr, ptr %t2015, i32 0
  store ptr %t2016, ptr %t2017
  call void @__inc_ref(ptr %t6)
  %t2018 = getelementptr ptr, ptr %t2015, i32 1
  store ptr %t6, ptr %t2018
  call void @__free_recursive(ptr %t6)
  store ptr %t2014, ptr %t3
  store ptr %t2015, ptr %t4
  br label %tco.loop.0
tco.case.arm.126.2019:
  %t2020 = getelementptr ptr, ptr %t5, i32 1
  %t2021 = load ptr, ptr %t2020
  %t2022 = getelementptr ptr, ptr %t5, i32 2
  %t2023 = load ptr, ptr %t2022
  %t2024 = getelementptr i8, ptr %t5, i64 -8
  %t2025 = load i32, ptr %t2024
  %t2026 = icmp eq i32 %t2025, 1
  br i1 %t2026, label %reuse.in_place.2027, label %reuse.copy.2028
reuse.in_place.2027:
  %t2030 = inttoptr i64 99 to ptr
  %t2031 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2030, ptr %t2031
  br label %reuse.join.2029
reuse.copy.2028:
  %t2032 = call ptr @__alloc(i64 24, i32 2)
  %t2033 = inttoptr i64 99 to ptr
  %t2034 = getelementptr ptr, ptr %t2032, i32 0
  store ptr %t2033, ptr %t2034
  call void @__inc_ref(ptr %t2021)
  %t2035 = getelementptr ptr, ptr %t2032, i32 1
  store ptr %t2021, ptr %t2035
  call void @__inc_ref(ptr %t2023)
  %t2036 = getelementptr ptr, ptr %t2032, i32 2
  store ptr %t2023, ptr %t2036
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2029
reuse.join.2029:
  %t2037 = phi ptr [ %t5, %reuse.in_place.2027 ], [ %t2032, %reuse.copy.2028 ]
  %t2038 = call ptr @__alloc(i64 16, i32 1)
  %t2039 = inttoptr i64 247 to ptr
  %t2040 = getelementptr ptr, ptr %t2038, i32 0
  store ptr %t2039, ptr %t2040
  call void @__inc_ref(ptr %t6)
  %t2041 = getelementptr ptr, ptr %t2038, i32 1
  store ptr %t6, ptr %t2041
  call void @__free_recursive(ptr %t6)
  store ptr %t2037, ptr %t3
  store ptr %t2038, ptr %t4
  br label %tco.loop.0
tco.case.arm.127.2042:
  %t2043 = getelementptr ptr, ptr %t5, i32 1
  %t2044 = load ptr, ptr %t2043
  %t2045 = getelementptr ptr, ptr %t5, i32 2
  %t2046 = load ptr, ptr %t2045
  %t2047 = getelementptr i8, ptr %t5, i64 -8
  %t2048 = load i32, ptr %t2047
  %t2049 = icmp eq i32 %t2048, 1
  br i1 %t2049, label %reuse.in_place.2050, label %reuse.copy.2051
reuse.in_place.2050:
  %t2053 = inttoptr i64 99 to ptr
  %t2054 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2053, ptr %t2054
  br label %reuse.join.2052
reuse.copy.2051:
  %t2055 = call ptr @__alloc(i64 24, i32 2)
  %t2056 = inttoptr i64 99 to ptr
  %t2057 = getelementptr ptr, ptr %t2055, i32 0
  store ptr %t2056, ptr %t2057
  call void @__inc_ref(ptr %t2044)
  %t2058 = getelementptr ptr, ptr %t2055, i32 1
  store ptr %t2044, ptr %t2058
  call void @__inc_ref(ptr %t2046)
  %t2059 = getelementptr ptr, ptr %t2055, i32 2
  store ptr %t2046, ptr %t2059
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2052
reuse.join.2052:
  %t2060 = phi ptr [ %t5, %reuse.in_place.2050 ], [ %t2055, %reuse.copy.2051 ]
  %t2061 = call ptr @__alloc(i64 16, i32 1)
  %t2062 = inttoptr i64 248 to ptr
  %t2063 = getelementptr ptr, ptr %t2061, i32 0
  store ptr %t2062, ptr %t2063
  call void @__inc_ref(ptr %t6)
  %t2064 = getelementptr ptr, ptr %t2061, i32 1
  store ptr %t6, ptr %t2064
  call void @__free_recursive(ptr %t6)
  store ptr %t2060, ptr %t3
  store ptr %t2061, ptr %t4
  br label %tco.loop.0
tco.case.arm.128.2065:
  %t2066 = getelementptr ptr, ptr %t5, i32 1
  %t2067 = load ptr, ptr %t2066
  %t2068 = getelementptr ptr, ptr %t5, i32 2
  %t2069 = load ptr, ptr %t2068
  %t2070 = getelementptr i8, ptr %t5, i64 -8
  %t2071 = load i32, ptr %t2070
  %t2072 = icmp eq i32 %t2071, 1
  br i1 %t2072, label %reuse.in_place.2073, label %reuse.copy.2074
reuse.in_place.2073:
  %t2076 = inttoptr i64 99 to ptr
  %t2077 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2076, ptr %t2077
  br label %reuse.join.2075
reuse.copy.2074:
  %t2078 = call ptr @__alloc(i64 24, i32 2)
  %t2079 = inttoptr i64 99 to ptr
  %t2080 = getelementptr ptr, ptr %t2078, i32 0
  store ptr %t2079, ptr %t2080
  call void @__inc_ref(ptr %t2067)
  %t2081 = getelementptr ptr, ptr %t2078, i32 1
  store ptr %t2067, ptr %t2081
  call void @__inc_ref(ptr %t2069)
  %t2082 = getelementptr ptr, ptr %t2078, i32 2
  store ptr %t2069, ptr %t2082
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2075
reuse.join.2075:
  %t2083 = phi ptr [ %t5, %reuse.in_place.2073 ], [ %t2078, %reuse.copy.2074 ]
  %t2084 = call ptr @__alloc(i64 16, i32 1)
  %t2085 = inttoptr i64 249 to ptr
  %t2086 = getelementptr ptr, ptr %t2084, i32 0
  store ptr %t2085, ptr %t2086
  call void @__inc_ref(ptr %t6)
  %t2087 = getelementptr ptr, ptr %t2084, i32 1
  store ptr %t6, ptr %t2087
  call void @__free_recursive(ptr %t6)
  store ptr %t2083, ptr %t3
  store ptr %t2084, ptr %t4
  br label %tco.loop.0
tco.case.arm.129.2088:
  %t2089 = getelementptr ptr, ptr %t5, i32 1
  %t2090 = load ptr, ptr %t2089
  %t2091 = getelementptr ptr, ptr %t5, i32 2
  %t2092 = load ptr, ptr %t2091
  %t2093 = getelementptr i8, ptr %t5, i64 -8
  %t2094 = load i32, ptr %t2093
  %t2095 = icmp eq i32 %t2094, 1
  br i1 %t2095, label %reuse.in_place.2096, label %reuse.copy.2097
reuse.in_place.2096:
  %t2099 = inttoptr i64 99 to ptr
  %t2100 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2099, ptr %t2100
  br label %reuse.join.2098
reuse.copy.2097:
  %t2101 = call ptr @__alloc(i64 24, i32 2)
  %t2102 = inttoptr i64 99 to ptr
  %t2103 = getelementptr ptr, ptr %t2101, i32 0
  store ptr %t2102, ptr %t2103
  call void @__inc_ref(ptr %t2090)
  %t2104 = getelementptr ptr, ptr %t2101, i32 1
  store ptr %t2090, ptr %t2104
  call void @__inc_ref(ptr %t2092)
  %t2105 = getelementptr ptr, ptr %t2101, i32 2
  store ptr %t2092, ptr %t2105
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2098
reuse.join.2098:
  %t2106 = phi ptr [ %t5, %reuse.in_place.2096 ], [ %t2101, %reuse.copy.2097 ]
  %t2107 = call ptr @__alloc(i64 16, i32 1)
  %t2108 = inttoptr i64 250 to ptr
  %t2109 = getelementptr ptr, ptr %t2107, i32 0
  store ptr %t2108, ptr %t2109
  call void @__inc_ref(ptr %t6)
  %t2110 = getelementptr ptr, ptr %t2107, i32 1
  store ptr %t6, ptr %t2110
  call void @__free_recursive(ptr %t6)
  store ptr %t2106, ptr %t3
  store ptr %t2107, ptr %t4
  br label %tco.loop.0
tco.case.arm.130.2111:
  %t2112 = getelementptr ptr, ptr %t5, i32 1
  %t2113 = load ptr, ptr %t2112
  %t2114 = getelementptr ptr, ptr %t5, i32 2
  %t2115 = load ptr, ptr %t2114
  %t2116 = getelementptr i8, ptr %t5, i64 -8
  %t2117 = load i32, ptr %t2116
  %t2118 = icmp eq i32 %t2117, 1
  br i1 %t2118, label %reuse.in_place.2119, label %reuse.copy.2120
reuse.in_place.2119:
  %t2122 = inttoptr i64 99 to ptr
  %t2123 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2122, ptr %t2123
  br label %reuse.join.2121
reuse.copy.2120:
  %t2124 = call ptr @__alloc(i64 24, i32 2)
  %t2125 = inttoptr i64 99 to ptr
  %t2126 = getelementptr ptr, ptr %t2124, i32 0
  store ptr %t2125, ptr %t2126
  call void @__inc_ref(ptr %t2113)
  %t2127 = getelementptr ptr, ptr %t2124, i32 1
  store ptr %t2113, ptr %t2127
  call void @__inc_ref(ptr %t2115)
  %t2128 = getelementptr ptr, ptr %t2124, i32 2
  store ptr %t2115, ptr %t2128
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2121
reuse.join.2121:
  %t2129 = phi ptr [ %t5, %reuse.in_place.2119 ], [ %t2124, %reuse.copy.2120 ]
  %t2130 = call ptr @__alloc(i64 16, i32 1)
  %t2131 = inttoptr i64 251 to ptr
  %t2132 = getelementptr ptr, ptr %t2130, i32 0
  store ptr %t2131, ptr %t2132
  call void @__inc_ref(ptr %t6)
  %t2133 = getelementptr ptr, ptr %t2130, i32 1
  store ptr %t6, ptr %t2133
  call void @__free_recursive(ptr %t6)
  store ptr %t2129, ptr %t3
  store ptr %t2130, ptr %t4
  br label %tco.loop.0
tco.case.arm.131.2134:
  %t2135 = getelementptr ptr, ptr %t5, i32 1
  %t2136 = load ptr, ptr %t2135
  %t2137 = getelementptr ptr, ptr %t5, i32 2
  %t2138 = load ptr, ptr %t2137
  %t2139 = getelementptr i8, ptr %t5, i64 -8
  %t2140 = load i32, ptr %t2139
  %t2141 = icmp eq i32 %t2140, 1
  br i1 %t2141, label %reuse.in_place.2142, label %reuse.copy.2143
reuse.in_place.2142:
  %t2145 = inttoptr i64 99 to ptr
  %t2146 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2145, ptr %t2146
  br label %reuse.join.2144
reuse.copy.2143:
  %t2147 = call ptr @__alloc(i64 24, i32 2)
  %t2148 = inttoptr i64 99 to ptr
  %t2149 = getelementptr ptr, ptr %t2147, i32 0
  store ptr %t2148, ptr %t2149
  call void @__inc_ref(ptr %t2136)
  %t2150 = getelementptr ptr, ptr %t2147, i32 1
  store ptr %t2136, ptr %t2150
  call void @__inc_ref(ptr %t2138)
  %t2151 = getelementptr ptr, ptr %t2147, i32 2
  store ptr %t2138, ptr %t2151
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2144
reuse.join.2144:
  %t2152 = phi ptr [ %t5, %reuse.in_place.2142 ], [ %t2147, %reuse.copy.2143 ]
  %t2153 = call ptr @__alloc(i64 16, i32 1)
  %t2154 = inttoptr i64 252 to ptr
  %t2155 = getelementptr ptr, ptr %t2153, i32 0
  store ptr %t2154, ptr %t2155
  call void @__inc_ref(ptr %t6)
  %t2156 = getelementptr ptr, ptr %t2153, i32 1
  store ptr %t6, ptr %t2156
  call void @__free_recursive(ptr %t6)
  store ptr %t2152, ptr %t3
  store ptr %t2153, ptr %t4
  br label %tco.loop.0
tco.case.arm.132.2157:
  %t2158 = getelementptr ptr, ptr %t5, i32 1
  %t2159 = load ptr, ptr %t2158
  %t2160 = getelementptr ptr, ptr %t5, i32 2
  %t2161 = load ptr, ptr %t2160
  %t2162 = getelementptr i8, ptr %t5, i64 -8
  %t2163 = load i32, ptr %t2162
  %t2164 = icmp eq i32 %t2163, 1
  br i1 %t2164, label %reuse.in_place.2165, label %reuse.copy.2166
reuse.in_place.2165:
  %t2168 = inttoptr i64 99 to ptr
  %t2169 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2168, ptr %t2169
  br label %reuse.join.2167
reuse.copy.2166:
  %t2170 = call ptr @__alloc(i64 24, i32 2)
  %t2171 = inttoptr i64 99 to ptr
  %t2172 = getelementptr ptr, ptr %t2170, i32 0
  store ptr %t2171, ptr %t2172
  call void @__inc_ref(ptr %t2159)
  %t2173 = getelementptr ptr, ptr %t2170, i32 1
  store ptr %t2159, ptr %t2173
  call void @__inc_ref(ptr %t2161)
  %t2174 = getelementptr ptr, ptr %t2170, i32 2
  store ptr %t2161, ptr %t2174
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2167
reuse.join.2167:
  %t2175 = phi ptr [ %t5, %reuse.in_place.2165 ], [ %t2170, %reuse.copy.2166 ]
  %t2176 = call ptr @__alloc(i64 16, i32 1)
  %t2177 = inttoptr i64 253 to ptr
  %t2178 = getelementptr ptr, ptr %t2176, i32 0
  store ptr %t2177, ptr %t2178
  call void @__inc_ref(ptr %t6)
  %t2179 = getelementptr ptr, ptr %t2176, i32 1
  store ptr %t6, ptr %t2179
  call void @__free_recursive(ptr %t6)
  store ptr %t2175, ptr %t3
  store ptr %t2176, ptr %t4
  br label %tco.loop.0
tco.case.arm.133.2180:
  %t2181 = getelementptr ptr, ptr %t5, i32 1
  %t2182 = load ptr, ptr %t2181
  %t2183 = getelementptr ptr, ptr %t5, i32 2
  %t2184 = load ptr, ptr %t2183
  %t2185 = getelementptr i8, ptr %t5, i64 -8
  %t2186 = load i32, ptr %t2185
  %t2187 = icmp eq i32 %t2186, 1
  br i1 %t2187, label %reuse.in_place.2188, label %reuse.copy.2189
reuse.in_place.2188:
  %t2191 = inttoptr i64 99 to ptr
  %t2192 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2191, ptr %t2192
  br label %reuse.join.2190
reuse.copy.2189:
  %t2193 = call ptr @__alloc(i64 24, i32 2)
  %t2194 = inttoptr i64 99 to ptr
  %t2195 = getelementptr ptr, ptr %t2193, i32 0
  store ptr %t2194, ptr %t2195
  call void @__inc_ref(ptr %t2182)
  %t2196 = getelementptr ptr, ptr %t2193, i32 1
  store ptr %t2182, ptr %t2196
  call void @__inc_ref(ptr %t2184)
  %t2197 = getelementptr ptr, ptr %t2193, i32 2
  store ptr %t2184, ptr %t2197
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2190
reuse.join.2190:
  %t2198 = phi ptr [ %t5, %reuse.in_place.2188 ], [ %t2193, %reuse.copy.2189 ]
  %t2199 = call ptr @__alloc(i64 16, i32 1)
  %t2200 = inttoptr i64 254 to ptr
  %t2201 = getelementptr ptr, ptr %t2199, i32 0
  store ptr %t2200, ptr %t2201
  call void @__inc_ref(ptr %t6)
  %t2202 = getelementptr ptr, ptr %t2199, i32 1
  store ptr %t6, ptr %t2202
  call void @__free_recursive(ptr %t6)
  store ptr %t2198, ptr %t3
  store ptr %t2199, ptr %t4
  br label %tco.loop.0
tco.case.arm.134.2203:
  %t2204 = getelementptr ptr, ptr %t5, i32 1
  %t2205 = load ptr, ptr %t2204
  %t2206 = getelementptr ptr, ptr %t5, i32 2
  %t2207 = load ptr, ptr %t2206
  %t2208 = getelementptr i8, ptr %t5, i64 -8
  %t2209 = load i32, ptr %t2208
  %t2210 = icmp eq i32 %t2209, 1
  br i1 %t2210, label %reuse.in_place.2211, label %reuse.copy.2212
reuse.in_place.2211:
  %t2214 = inttoptr i64 99 to ptr
  %t2215 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2214, ptr %t2215
  br label %reuse.join.2213
reuse.copy.2212:
  %t2216 = call ptr @__alloc(i64 24, i32 2)
  %t2217 = inttoptr i64 99 to ptr
  %t2218 = getelementptr ptr, ptr %t2216, i32 0
  store ptr %t2217, ptr %t2218
  call void @__inc_ref(ptr %t2205)
  %t2219 = getelementptr ptr, ptr %t2216, i32 1
  store ptr %t2205, ptr %t2219
  call void @__inc_ref(ptr %t2207)
  %t2220 = getelementptr ptr, ptr %t2216, i32 2
  store ptr %t2207, ptr %t2220
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2213
reuse.join.2213:
  %t2221 = phi ptr [ %t5, %reuse.in_place.2211 ], [ %t2216, %reuse.copy.2212 ]
  %t2222 = call ptr @__alloc(i64 16, i32 1)
  %t2223 = inttoptr i64 255 to ptr
  %t2224 = getelementptr ptr, ptr %t2222, i32 0
  store ptr %t2223, ptr %t2224
  call void @__inc_ref(ptr %t6)
  %t2225 = getelementptr ptr, ptr %t2222, i32 1
  store ptr %t6, ptr %t2225
  call void @__free_recursive(ptr %t6)
  store ptr %t2221, ptr %t3
  store ptr %t2222, ptr %t4
  br label %tco.loop.0
tco.case.arm.135.2226:
  %t2227 = getelementptr ptr, ptr %t5, i32 1
  %t2228 = load ptr, ptr %t2227
  %t2229 = getelementptr ptr, ptr %t5, i32 2
  %t2230 = load ptr, ptr %t2229
  %t2231 = getelementptr i8, ptr %t5, i64 -8
  %t2232 = load i32, ptr %t2231
  %t2233 = icmp eq i32 %t2232, 1
  br i1 %t2233, label %reuse.in_place.2234, label %reuse.copy.2235
reuse.in_place.2234:
  %t2237 = inttoptr i64 99 to ptr
  %t2238 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2237, ptr %t2238
  br label %reuse.join.2236
reuse.copy.2235:
  %t2239 = call ptr @__alloc(i64 24, i32 2)
  %t2240 = inttoptr i64 99 to ptr
  %t2241 = getelementptr ptr, ptr %t2239, i32 0
  store ptr %t2240, ptr %t2241
  call void @__inc_ref(ptr %t2228)
  %t2242 = getelementptr ptr, ptr %t2239, i32 1
  store ptr %t2228, ptr %t2242
  call void @__inc_ref(ptr %t2230)
  %t2243 = getelementptr ptr, ptr %t2239, i32 2
  store ptr %t2230, ptr %t2243
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2236
reuse.join.2236:
  %t2244 = phi ptr [ %t5, %reuse.in_place.2234 ], [ %t2239, %reuse.copy.2235 ]
  %t2245 = call ptr @__alloc(i64 16, i32 1)
  %t2246 = inttoptr i64 256 to ptr
  %t2247 = getelementptr ptr, ptr %t2245, i32 0
  store ptr %t2246, ptr %t2247
  call void @__inc_ref(ptr %t6)
  %t2248 = getelementptr ptr, ptr %t2245, i32 1
  store ptr %t6, ptr %t2248
  call void @__free_recursive(ptr %t6)
  store ptr %t2244, ptr %t3
  store ptr %t2245, ptr %t4
  br label %tco.loop.0
tco.case.arm.136.2249:
  %t2250 = getelementptr ptr, ptr %t5, i32 1
  %t2251 = load ptr, ptr %t2250
  %t2252 = getelementptr ptr, ptr %t5, i32 2
  %t2253 = load ptr, ptr %t2252
  %t2254 = getelementptr i8, ptr %t5, i64 -8
  %t2255 = load i32, ptr %t2254
  %t2256 = icmp eq i32 %t2255, 1
  br i1 %t2256, label %reuse.in_place.2257, label %reuse.copy.2258
reuse.in_place.2257:
  %t2260 = inttoptr i64 99 to ptr
  %t2261 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2260, ptr %t2261
  br label %reuse.join.2259
reuse.copy.2258:
  %t2262 = call ptr @__alloc(i64 24, i32 2)
  %t2263 = inttoptr i64 99 to ptr
  %t2264 = getelementptr ptr, ptr %t2262, i32 0
  store ptr %t2263, ptr %t2264
  call void @__inc_ref(ptr %t2251)
  %t2265 = getelementptr ptr, ptr %t2262, i32 1
  store ptr %t2251, ptr %t2265
  call void @__inc_ref(ptr %t2253)
  %t2266 = getelementptr ptr, ptr %t2262, i32 2
  store ptr %t2253, ptr %t2266
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2259
reuse.join.2259:
  %t2267 = phi ptr [ %t5, %reuse.in_place.2257 ], [ %t2262, %reuse.copy.2258 ]
  %t2268 = call ptr @__alloc(i64 16, i32 1)
  %t2269 = inttoptr i64 257 to ptr
  %t2270 = getelementptr ptr, ptr %t2268, i32 0
  store ptr %t2269, ptr %t2270
  call void @__inc_ref(ptr %t6)
  %t2271 = getelementptr ptr, ptr %t2268, i32 1
  store ptr %t6, ptr %t2271
  call void @__free_recursive(ptr %t6)
  store ptr %t2267, ptr %t3
  store ptr %t2268, ptr %t4
  br label %tco.loop.0
tco.case.arm.137.2272:
  %t2273 = getelementptr ptr, ptr %t5, i32 1
  %t2274 = load ptr, ptr %t2273
  %t2275 = getelementptr ptr, ptr %t5, i32 2
  %t2276 = load ptr, ptr %t2275
  %t2277 = getelementptr i8, ptr %t5, i64 -8
  %t2278 = load i32, ptr %t2277
  %t2279 = icmp eq i32 %t2278, 1
  br i1 %t2279, label %reuse.in_place.2280, label %reuse.copy.2281
reuse.in_place.2280:
  %t2283 = inttoptr i64 99 to ptr
  %t2284 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2283, ptr %t2284
  br label %reuse.join.2282
reuse.copy.2281:
  %t2285 = call ptr @__alloc(i64 24, i32 2)
  %t2286 = inttoptr i64 99 to ptr
  %t2287 = getelementptr ptr, ptr %t2285, i32 0
  store ptr %t2286, ptr %t2287
  call void @__inc_ref(ptr %t2274)
  %t2288 = getelementptr ptr, ptr %t2285, i32 1
  store ptr %t2274, ptr %t2288
  call void @__inc_ref(ptr %t2276)
  %t2289 = getelementptr ptr, ptr %t2285, i32 2
  store ptr %t2276, ptr %t2289
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2282
reuse.join.2282:
  %t2290 = phi ptr [ %t5, %reuse.in_place.2280 ], [ %t2285, %reuse.copy.2281 ]
  %t2291 = call ptr @__alloc(i64 16, i32 1)
  %t2292 = inttoptr i64 258 to ptr
  %t2293 = getelementptr ptr, ptr %t2291, i32 0
  store ptr %t2292, ptr %t2293
  call void @__inc_ref(ptr %t6)
  %t2294 = getelementptr ptr, ptr %t2291, i32 1
  store ptr %t6, ptr %t2294
  call void @__free_recursive(ptr %t6)
  store ptr %t2290, ptr %t3
  store ptr %t2291, ptr %t4
  br label %tco.loop.0
tco.case.arm.138.2295:
  %t2296 = getelementptr ptr, ptr %t5, i32 1
  %t2297 = load ptr, ptr %t2296
  %t2298 = getelementptr ptr, ptr %t5, i32 2
  %t2299 = load ptr, ptr %t2298
  %t2300 = getelementptr i8, ptr %t5, i64 -8
  %t2301 = load i32, ptr %t2300
  %t2302 = icmp eq i32 %t2301, 1
  br i1 %t2302, label %reuse.in_place.2303, label %reuse.copy.2304
reuse.in_place.2303:
  %t2306 = inttoptr i64 99 to ptr
  %t2307 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2306, ptr %t2307
  br label %reuse.join.2305
reuse.copy.2304:
  %t2308 = call ptr @__alloc(i64 24, i32 2)
  %t2309 = inttoptr i64 99 to ptr
  %t2310 = getelementptr ptr, ptr %t2308, i32 0
  store ptr %t2309, ptr %t2310
  call void @__inc_ref(ptr %t2297)
  %t2311 = getelementptr ptr, ptr %t2308, i32 1
  store ptr %t2297, ptr %t2311
  call void @__inc_ref(ptr %t2299)
  %t2312 = getelementptr ptr, ptr %t2308, i32 2
  store ptr %t2299, ptr %t2312
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2305
reuse.join.2305:
  %t2313 = phi ptr [ %t5, %reuse.in_place.2303 ], [ %t2308, %reuse.copy.2304 ]
  %t2314 = call ptr @__alloc(i64 16, i32 1)
  %t2315 = inttoptr i64 259 to ptr
  %t2316 = getelementptr ptr, ptr %t2314, i32 0
  store ptr %t2315, ptr %t2316
  call void @__inc_ref(ptr %t6)
  %t2317 = getelementptr ptr, ptr %t2314, i32 1
  store ptr %t6, ptr %t2317
  call void @__free_recursive(ptr %t6)
  store ptr %t2313, ptr %t3
  store ptr %t2314, ptr %t4
  br label %tco.loop.0
tco.case.arm.139.2318:
  %t2319 = getelementptr ptr, ptr %t5, i32 1
  %t2320 = load ptr, ptr %t2319
  %t2321 = getelementptr ptr, ptr %t5, i32 2
  %t2322 = load ptr, ptr %t2321
  %t2323 = getelementptr i8, ptr %t5, i64 -8
  %t2324 = load i32, ptr %t2323
  %t2325 = icmp eq i32 %t2324, 1
  br i1 %t2325, label %reuse.in_place.2326, label %reuse.copy.2327
reuse.in_place.2326:
  %t2329 = inttoptr i64 99 to ptr
  %t2330 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2329, ptr %t2330
  br label %reuse.join.2328
reuse.copy.2327:
  %t2331 = call ptr @__alloc(i64 24, i32 2)
  %t2332 = inttoptr i64 99 to ptr
  %t2333 = getelementptr ptr, ptr %t2331, i32 0
  store ptr %t2332, ptr %t2333
  call void @__inc_ref(ptr %t2320)
  %t2334 = getelementptr ptr, ptr %t2331, i32 1
  store ptr %t2320, ptr %t2334
  call void @__inc_ref(ptr %t2322)
  %t2335 = getelementptr ptr, ptr %t2331, i32 2
  store ptr %t2322, ptr %t2335
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2328
reuse.join.2328:
  %t2336 = phi ptr [ %t5, %reuse.in_place.2326 ], [ %t2331, %reuse.copy.2327 ]
  %t2337 = call ptr @__alloc(i64 16, i32 1)
  %t2338 = inttoptr i64 260 to ptr
  %t2339 = getelementptr ptr, ptr %t2337, i32 0
  store ptr %t2338, ptr %t2339
  call void @__inc_ref(ptr %t6)
  %t2340 = getelementptr ptr, ptr %t2337, i32 1
  store ptr %t6, ptr %t2340
  call void @__free_recursive(ptr %t6)
  store ptr %t2336, ptr %t3
  store ptr %t2337, ptr %t4
  br label %tco.loop.0
tco.case.arm.140.2341:
  %t2342 = getelementptr ptr, ptr %t5, i32 1
  %t2343 = load ptr, ptr %t2342
  %t2344 = getelementptr ptr, ptr %t5, i32 2
  %t2345 = load ptr, ptr %t2344
  %t2346 = getelementptr i8, ptr %t5, i64 -8
  %t2347 = load i32, ptr %t2346
  %t2348 = icmp eq i32 %t2347, 1
  br i1 %t2348, label %reuse.in_place.2349, label %reuse.copy.2350
reuse.in_place.2349:
  %t2352 = inttoptr i64 99 to ptr
  %t2353 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2352, ptr %t2353
  br label %reuse.join.2351
reuse.copy.2350:
  %t2354 = call ptr @__alloc(i64 24, i32 2)
  %t2355 = inttoptr i64 99 to ptr
  %t2356 = getelementptr ptr, ptr %t2354, i32 0
  store ptr %t2355, ptr %t2356
  call void @__inc_ref(ptr %t2343)
  %t2357 = getelementptr ptr, ptr %t2354, i32 1
  store ptr %t2343, ptr %t2357
  call void @__inc_ref(ptr %t2345)
  %t2358 = getelementptr ptr, ptr %t2354, i32 2
  store ptr %t2345, ptr %t2358
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2351
reuse.join.2351:
  %t2359 = phi ptr [ %t5, %reuse.in_place.2349 ], [ %t2354, %reuse.copy.2350 ]
  %t2360 = call ptr @__alloc(i64 16, i32 1)
  %t2361 = inttoptr i64 261 to ptr
  %t2362 = getelementptr ptr, ptr %t2360, i32 0
  store ptr %t2361, ptr %t2362
  call void @__inc_ref(ptr %t6)
  %t2363 = getelementptr ptr, ptr %t2360, i32 1
  store ptr %t6, ptr %t2363
  call void @__free_recursive(ptr %t6)
  store ptr %t2359, ptr %t3
  store ptr %t2360, ptr %t4
  br label %tco.loop.0
tco.case.arm.141.2364:
  %t2365 = getelementptr ptr, ptr %t5, i32 1
  %t2366 = load ptr, ptr %t2365
  %t2367 = getelementptr ptr, ptr %t5, i32 2
  %t2368 = load ptr, ptr %t2367
  %t2369 = getelementptr i8, ptr %t5, i64 -8
  %t2370 = load i32, ptr %t2369
  %t2371 = icmp eq i32 %t2370, 1
  br i1 %t2371, label %reuse.in_place.2372, label %reuse.copy.2373
reuse.in_place.2372:
  %t2375 = inttoptr i64 99 to ptr
  %t2376 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2375, ptr %t2376
  br label %reuse.join.2374
reuse.copy.2373:
  %t2377 = call ptr @__alloc(i64 24, i32 2)
  %t2378 = inttoptr i64 99 to ptr
  %t2379 = getelementptr ptr, ptr %t2377, i32 0
  store ptr %t2378, ptr %t2379
  call void @__inc_ref(ptr %t2366)
  %t2380 = getelementptr ptr, ptr %t2377, i32 1
  store ptr %t2366, ptr %t2380
  call void @__inc_ref(ptr %t2368)
  %t2381 = getelementptr ptr, ptr %t2377, i32 2
  store ptr %t2368, ptr %t2381
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2374
reuse.join.2374:
  %t2382 = phi ptr [ %t5, %reuse.in_place.2372 ], [ %t2377, %reuse.copy.2373 ]
  %t2383 = call ptr @__alloc(i64 16, i32 1)
  %t2384 = inttoptr i64 262 to ptr
  %t2385 = getelementptr ptr, ptr %t2383, i32 0
  store ptr %t2384, ptr %t2385
  call void @__inc_ref(ptr %t6)
  %t2386 = getelementptr ptr, ptr %t2383, i32 1
  store ptr %t6, ptr %t2386
  call void @__free_recursive(ptr %t6)
  store ptr %t2382, ptr %t3
  store ptr %t2383, ptr %t4
  br label %tco.loop.0
tco.case.arm.142.2387:
  %t2388 = getelementptr ptr, ptr %t5, i32 1
  %t2389 = load ptr, ptr %t2388
  %t2390 = getelementptr ptr, ptr %t5, i32 2
  %t2391 = load ptr, ptr %t2390
  %t2392 = getelementptr i8, ptr %t5, i64 -8
  %t2393 = load i32, ptr %t2392
  %t2394 = icmp eq i32 %t2393, 1
  br i1 %t2394, label %reuse.in_place.2395, label %reuse.copy.2396
reuse.in_place.2395:
  %t2398 = inttoptr i64 99 to ptr
  %t2399 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2398, ptr %t2399
  br label %reuse.join.2397
reuse.copy.2396:
  %t2400 = call ptr @__alloc(i64 24, i32 2)
  %t2401 = inttoptr i64 99 to ptr
  %t2402 = getelementptr ptr, ptr %t2400, i32 0
  store ptr %t2401, ptr %t2402
  call void @__inc_ref(ptr %t2389)
  %t2403 = getelementptr ptr, ptr %t2400, i32 1
  store ptr %t2389, ptr %t2403
  call void @__inc_ref(ptr %t2391)
  %t2404 = getelementptr ptr, ptr %t2400, i32 2
  store ptr %t2391, ptr %t2404
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2397
reuse.join.2397:
  %t2405 = phi ptr [ %t5, %reuse.in_place.2395 ], [ %t2400, %reuse.copy.2396 ]
  %t2406 = call ptr @__alloc(i64 16, i32 1)
  %t2407 = inttoptr i64 263 to ptr
  %t2408 = getelementptr ptr, ptr %t2406, i32 0
  store ptr %t2407, ptr %t2408
  call void @__inc_ref(ptr %t6)
  %t2409 = getelementptr ptr, ptr %t2406, i32 1
  store ptr %t6, ptr %t2409
  call void @__free_recursive(ptr %t6)
  store ptr %t2405, ptr %t3
  store ptr %t2406, ptr %t4
  br label %tco.loop.0
tco.case.arm.143.2410:
  %t2411 = getelementptr ptr, ptr %t5, i32 1
  %t2412 = load ptr, ptr %t2411
  %t2413 = getelementptr ptr, ptr %t5, i32 2
  %t2414 = load ptr, ptr %t2413
  %t2415 = getelementptr i8, ptr %t5, i64 -8
  %t2416 = load i32, ptr %t2415
  %t2417 = icmp eq i32 %t2416, 1
  br i1 %t2417, label %reuse.in_place.2418, label %reuse.copy.2419
reuse.in_place.2418:
  %t2421 = inttoptr i64 99 to ptr
  %t2422 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2421, ptr %t2422
  br label %reuse.join.2420
reuse.copy.2419:
  %t2423 = call ptr @__alloc(i64 24, i32 2)
  %t2424 = inttoptr i64 99 to ptr
  %t2425 = getelementptr ptr, ptr %t2423, i32 0
  store ptr %t2424, ptr %t2425
  call void @__inc_ref(ptr %t2412)
  %t2426 = getelementptr ptr, ptr %t2423, i32 1
  store ptr %t2412, ptr %t2426
  call void @__inc_ref(ptr %t2414)
  %t2427 = getelementptr ptr, ptr %t2423, i32 2
  store ptr %t2414, ptr %t2427
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2420
reuse.join.2420:
  %t2428 = phi ptr [ %t5, %reuse.in_place.2418 ], [ %t2423, %reuse.copy.2419 ]
  %t2429 = call ptr @__alloc(i64 16, i32 1)
  %t2430 = inttoptr i64 264 to ptr
  %t2431 = getelementptr ptr, ptr %t2429, i32 0
  store ptr %t2430, ptr %t2431
  call void @__inc_ref(ptr %t6)
  %t2432 = getelementptr ptr, ptr %t2429, i32 1
  store ptr %t6, ptr %t2432
  call void @__free_recursive(ptr %t6)
  store ptr %t2428, ptr %t3
  store ptr %t2429, ptr %t4
  br label %tco.loop.0
tco.case.arm.144.2433:
  %t2434 = getelementptr ptr, ptr %t5, i32 1
  %t2435 = load ptr, ptr %t2434
  %t2436 = getelementptr ptr, ptr %t5, i32 2
  %t2437 = load ptr, ptr %t2436
  %t2438 = getelementptr i8, ptr %t5, i64 -8
  %t2439 = load i32, ptr %t2438
  %t2440 = icmp eq i32 %t2439, 1
  br i1 %t2440, label %reuse.in_place.2441, label %reuse.copy.2442
reuse.in_place.2441:
  %t2444 = inttoptr i64 99 to ptr
  %t2445 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2444, ptr %t2445
  br label %reuse.join.2443
reuse.copy.2442:
  %t2446 = call ptr @__alloc(i64 24, i32 2)
  %t2447 = inttoptr i64 99 to ptr
  %t2448 = getelementptr ptr, ptr %t2446, i32 0
  store ptr %t2447, ptr %t2448
  call void @__inc_ref(ptr %t2435)
  %t2449 = getelementptr ptr, ptr %t2446, i32 1
  store ptr %t2435, ptr %t2449
  call void @__inc_ref(ptr %t2437)
  %t2450 = getelementptr ptr, ptr %t2446, i32 2
  store ptr %t2437, ptr %t2450
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2443
reuse.join.2443:
  %t2451 = phi ptr [ %t5, %reuse.in_place.2441 ], [ %t2446, %reuse.copy.2442 ]
  %t2452 = call ptr @__alloc(i64 16, i32 1)
  %t2453 = inttoptr i64 265 to ptr
  %t2454 = getelementptr ptr, ptr %t2452, i32 0
  store ptr %t2453, ptr %t2454
  call void @__inc_ref(ptr %t6)
  %t2455 = getelementptr ptr, ptr %t2452, i32 1
  store ptr %t6, ptr %t2455
  call void @__free_recursive(ptr %t6)
  store ptr %t2451, ptr %t3
  store ptr %t2452, ptr %t4
  br label %tco.loop.0
tco.case.arm.145.2456:
  %t2457 = getelementptr ptr, ptr %t5, i32 1
  %t2458 = load ptr, ptr %t2457
  %t2459 = getelementptr ptr, ptr %t5, i32 2
  %t2460 = load ptr, ptr %t2459
  %t2461 = getelementptr i8, ptr %t5, i64 -8
  %t2462 = load i32, ptr %t2461
  %t2463 = icmp eq i32 %t2462, 1
  br i1 %t2463, label %reuse.in_place.2464, label %reuse.copy.2465
reuse.in_place.2464:
  %t2467 = inttoptr i64 99 to ptr
  %t2468 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2467, ptr %t2468
  br label %reuse.join.2466
reuse.copy.2465:
  %t2469 = call ptr @__alloc(i64 24, i32 2)
  %t2470 = inttoptr i64 99 to ptr
  %t2471 = getelementptr ptr, ptr %t2469, i32 0
  store ptr %t2470, ptr %t2471
  call void @__inc_ref(ptr %t2458)
  %t2472 = getelementptr ptr, ptr %t2469, i32 1
  store ptr %t2458, ptr %t2472
  call void @__inc_ref(ptr %t2460)
  %t2473 = getelementptr ptr, ptr %t2469, i32 2
  store ptr %t2460, ptr %t2473
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2466
reuse.join.2466:
  %t2474 = phi ptr [ %t5, %reuse.in_place.2464 ], [ %t2469, %reuse.copy.2465 ]
  %t2475 = call ptr @__alloc(i64 16, i32 1)
  %t2476 = inttoptr i64 266 to ptr
  %t2477 = getelementptr ptr, ptr %t2475, i32 0
  store ptr %t2476, ptr %t2477
  call void @__inc_ref(ptr %t6)
  %t2478 = getelementptr ptr, ptr %t2475, i32 1
  store ptr %t6, ptr %t2478
  call void @__free_recursive(ptr %t6)
  store ptr %t2474, ptr %t3
  store ptr %t2475, ptr %t4
  br label %tco.loop.0
tco.case.arm.146.2479:
  %t2480 = getelementptr ptr, ptr %t5, i32 1
  %t2481 = load ptr, ptr %t2480
  %t2482 = getelementptr ptr, ptr %t5, i32 2
  %t2483 = load ptr, ptr %t2482
  %t2484 = getelementptr i8, ptr %t5, i64 -8
  %t2485 = load i32, ptr %t2484
  %t2486 = icmp eq i32 %t2485, 1
  br i1 %t2486, label %reuse.in_place.2487, label %reuse.copy.2488
reuse.in_place.2487:
  %t2490 = inttoptr i64 99 to ptr
  %t2491 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2490, ptr %t2491
  br label %reuse.join.2489
reuse.copy.2488:
  %t2492 = call ptr @__alloc(i64 24, i32 2)
  %t2493 = inttoptr i64 99 to ptr
  %t2494 = getelementptr ptr, ptr %t2492, i32 0
  store ptr %t2493, ptr %t2494
  call void @__inc_ref(ptr %t2481)
  %t2495 = getelementptr ptr, ptr %t2492, i32 1
  store ptr %t2481, ptr %t2495
  call void @__inc_ref(ptr %t2483)
  %t2496 = getelementptr ptr, ptr %t2492, i32 2
  store ptr %t2483, ptr %t2496
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2489
reuse.join.2489:
  %t2497 = phi ptr [ %t5, %reuse.in_place.2487 ], [ %t2492, %reuse.copy.2488 ]
  %t2498 = call ptr @__alloc(i64 16, i32 1)
  %t2499 = inttoptr i64 267 to ptr
  %t2500 = getelementptr ptr, ptr %t2498, i32 0
  store ptr %t2499, ptr %t2500
  call void @__inc_ref(ptr %t6)
  %t2501 = getelementptr ptr, ptr %t2498, i32 1
  store ptr %t6, ptr %t2501
  call void @__free_recursive(ptr %t6)
  store ptr %t2497, ptr %t3
  store ptr %t2498, ptr %t4
  br label %tco.loop.0
tco.case.arm.147.2502:
  %t2503 = getelementptr ptr, ptr %t5, i32 1
  %t2504 = load ptr, ptr %t2503
  call void @__inc_ref(ptr %t2504)
  %t2505 = getelementptr ptr, ptr %t5, i32 2
  %t2506 = load ptr, ptr %t2505
  call void @__inc_ref(ptr %t2506)
  %t2507 = getelementptr ptr, ptr %t5, i32 3
  %t2508 = load ptr, ptr %t2507
  call void @__inc_ref(ptr %t2508)
  %t2509 = call ptr @__alloc(i64 24, i32 2)
  %t2510 = inttoptr i64 99 to ptr
  %t2511 = getelementptr ptr, ptr %t2509, i32 0
  store ptr %t2510, ptr %t2511
  call void @__inc_ref(ptr %t2504)
  %t2512 = getelementptr ptr, ptr %t2509, i32 1
  store ptr %t2504, ptr %t2512
  call void @__inc_ref(ptr %t2506)
  %t2513 = getelementptr ptr, ptr %t2509, i32 2
  store ptr %t2506, ptr %t2513
  %t2514 = call ptr @__alloc(i64 24, i32 2)
  %t2515 = inttoptr i64 268 to ptr
  %t2516 = getelementptr ptr, ptr %t2514, i32 0
  store ptr %t2515, ptr %t2516
  call void @__inc_ref(ptr %t6)
  %t2517 = getelementptr ptr, ptr %t2514, i32 1
  store ptr %t6, ptr %t2517
  call void @__inc_ref(ptr %t2508)
  %t2518 = getelementptr ptr, ptr %t2514, i32 2
  store ptr %t2508, ptr %t2518
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t2508)
  call void @__free_recursive(ptr %t2506)
  call void @__free_recursive(ptr %t2504)
  store ptr %t2509, ptr %t3
  store ptr %t2514, ptr %t4
  br label %tco.loop.0
tco.case.arm.148.2519:
  %t2520 = getelementptr ptr, ptr %t5, i32 1
  %t2521 = load ptr, ptr %t2520
  %t2522 = getelementptr ptr, ptr %t5, i32 2
  %t2523 = load ptr, ptr %t2522
  %t2524 = getelementptr i8, ptr %t5, i64 -8
  %t2525 = load i32, ptr %t2524
  %t2526 = icmp eq i32 %t2525, 1
  br i1 %t2526, label %reuse.in_place.2527, label %reuse.copy.2528
reuse.in_place.2527:
  %t2530 = inttoptr i64 99 to ptr
  %t2531 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2530, ptr %t2531
  br label %reuse.join.2529
reuse.copy.2528:
  %t2532 = call ptr @__alloc(i64 24, i32 2)
  %t2533 = inttoptr i64 99 to ptr
  %t2534 = getelementptr ptr, ptr %t2532, i32 0
  store ptr %t2533, ptr %t2534
  call void @__inc_ref(ptr %t2521)
  %t2535 = getelementptr ptr, ptr %t2532, i32 1
  store ptr %t2521, ptr %t2535
  call void @__inc_ref(ptr %t2523)
  %t2536 = getelementptr ptr, ptr %t2532, i32 2
  store ptr %t2523, ptr %t2536
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2529
reuse.join.2529:
  %t2537 = phi ptr [ %t5, %reuse.in_place.2527 ], [ %t2532, %reuse.copy.2528 ]
  %t2538 = call ptr @__alloc(i64 16, i32 1)
  %t2539 = inttoptr i64 269 to ptr
  %t2540 = getelementptr ptr, ptr %t2538, i32 0
  store ptr %t2539, ptr %t2540
  call void @__inc_ref(ptr %t6)
  %t2541 = getelementptr ptr, ptr %t2538, i32 1
  store ptr %t6, ptr %t2541
  call void @__free_recursive(ptr %t6)
  store ptr %t2537, ptr %t3
  store ptr %t2538, ptr %t4
  br label %tco.loop.0
tco.case.arm.149.2542:
  %t2543 = getelementptr ptr, ptr %t5, i32 1
  %t2544 = load ptr, ptr %t2543
  %t2545 = getelementptr ptr, ptr %t5, i32 2
  %t2546 = load ptr, ptr %t2545
  %t2547 = getelementptr i8, ptr %t5, i64 -8
  %t2548 = load i32, ptr %t2547
  %t2549 = icmp eq i32 %t2548, 1
  br i1 %t2549, label %reuse.in_place.2550, label %reuse.copy.2551
reuse.in_place.2550:
  %t2553 = inttoptr i64 99 to ptr
  %t2554 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2553, ptr %t2554
  br label %reuse.join.2552
reuse.copy.2551:
  %t2555 = call ptr @__alloc(i64 24, i32 2)
  %t2556 = inttoptr i64 99 to ptr
  %t2557 = getelementptr ptr, ptr %t2555, i32 0
  store ptr %t2556, ptr %t2557
  call void @__inc_ref(ptr %t2544)
  %t2558 = getelementptr ptr, ptr %t2555, i32 1
  store ptr %t2544, ptr %t2558
  call void @__inc_ref(ptr %t2546)
  %t2559 = getelementptr ptr, ptr %t2555, i32 2
  store ptr %t2546, ptr %t2559
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2552
reuse.join.2552:
  %t2560 = phi ptr [ %t5, %reuse.in_place.2550 ], [ %t2555, %reuse.copy.2551 ]
  %t2561 = call ptr @__alloc(i64 16, i32 1)
  %t2562 = inttoptr i64 270 to ptr
  %t2563 = getelementptr ptr, ptr %t2561, i32 0
  store ptr %t2562, ptr %t2563
  call void @__inc_ref(ptr %t6)
  %t2564 = getelementptr ptr, ptr %t2561, i32 1
  store ptr %t6, ptr %t2564
  call void @__free_recursive(ptr %t6)
  store ptr %t2560, ptr %t3
  store ptr %t2561, ptr %t4
  br label %tco.loop.0
tco.case.arm.150.2565:
  %t2566 = getelementptr ptr, ptr %t5, i32 1
  %t2567 = load ptr, ptr %t2566
  %t2568 = getelementptr ptr, ptr %t5, i32 2
  %t2569 = load ptr, ptr %t2568
  %t2570 = getelementptr i8, ptr %t5, i64 -8
  %t2571 = load i32, ptr %t2570
  %t2572 = icmp eq i32 %t2571, 1
  br i1 %t2572, label %reuse.in_place.2573, label %reuse.copy.2574
reuse.in_place.2573:
  %t2576 = inttoptr i64 99 to ptr
  %t2577 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2576, ptr %t2577
  br label %reuse.join.2575
reuse.copy.2574:
  %t2578 = call ptr @__alloc(i64 24, i32 2)
  %t2579 = inttoptr i64 99 to ptr
  %t2580 = getelementptr ptr, ptr %t2578, i32 0
  store ptr %t2579, ptr %t2580
  call void @__inc_ref(ptr %t2567)
  %t2581 = getelementptr ptr, ptr %t2578, i32 1
  store ptr %t2567, ptr %t2581
  call void @__inc_ref(ptr %t2569)
  %t2582 = getelementptr ptr, ptr %t2578, i32 2
  store ptr %t2569, ptr %t2582
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2575
reuse.join.2575:
  %t2583 = phi ptr [ %t5, %reuse.in_place.2573 ], [ %t2578, %reuse.copy.2574 ]
  %t2584 = call ptr @__alloc(i64 16, i32 1)
  %t2585 = inttoptr i64 271 to ptr
  %t2586 = getelementptr ptr, ptr %t2584, i32 0
  store ptr %t2585, ptr %t2586
  call void @__inc_ref(ptr %t6)
  %t2587 = getelementptr ptr, ptr %t2584, i32 1
  store ptr %t6, ptr %t2587
  call void @__free_recursive(ptr %t6)
  store ptr %t2583, ptr %t3
  store ptr %t2584, ptr %t4
  br label %tco.loop.0
tco.case.arm.151.2588:
  %t2589 = getelementptr ptr, ptr %t5, i32 1
  %t2590 = load ptr, ptr %t2589
  %t2591 = getelementptr ptr, ptr %t5, i32 2
  %t2592 = load ptr, ptr %t2591
  %t2593 = getelementptr i8, ptr %t5, i64 -8
  %t2594 = load i32, ptr %t2593
  %t2595 = icmp eq i32 %t2594, 1
  br i1 %t2595, label %reuse.in_place.2596, label %reuse.copy.2597
reuse.in_place.2596:
  %t2599 = inttoptr i64 99 to ptr
  %t2600 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2599, ptr %t2600
  br label %reuse.join.2598
reuse.copy.2597:
  %t2601 = call ptr @__alloc(i64 24, i32 2)
  %t2602 = inttoptr i64 99 to ptr
  %t2603 = getelementptr ptr, ptr %t2601, i32 0
  store ptr %t2602, ptr %t2603
  call void @__inc_ref(ptr %t2590)
  %t2604 = getelementptr ptr, ptr %t2601, i32 1
  store ptr %t2590, ptr %t2604
  call void @__inc_ref(ptr %t2592)
  %t2605 = getelementptr ptr, ptr %t2601, i32 2
  store ptr %t2592, ptr %t2605
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2598
reuse.join.2598:
  %t2606 = phi ptr [ %t5, %reuse.in_place.2596 ], [ %t2601, %reuse.copy.2597 ]
  %t2607 = call ptr @__alloc(i64 16, i32 1)
  %t2608 = inttoptr i64 272 to ptr
  %t2609 = getelementptr ptr, ptr %t2607, i32 0
  store ptr %t2608, ptr %t2609
  call void @__inc_ref(ptr %t6)
  %t2610 = getelementptr ptr, ptr %t2607, i32 1
  store ptr %t6, ptr %t2610
  call void @__free_recursive(ptr %t6)
  store ptr %t2606, ptr %t3
  store ptr %t2607, ptr %t4
  br label %tco.loop.0
tco.case.arm.152.2611:
  %t2612 = getelementptr ptr, ptr %t5, i32 1
  %t2613 = load ptr, ptr %t2612
  %t2614 = getelementptr ptr, ptr %t5, i32 2
  %t2615 = load ptr, ptr %t2614
  %t2616 = getelementptr i8, ptr %t5, i64 -8
  %t2617 = load i32, ptr %t2616
  %t2618 = icmp eq i32 %t2617, 1
  br i1 %t2618, label %reuse.in_place.2619, label %reuse.copy.2620
reuse.in_place.2619:
  %t2622 = inttoptr i64 99 to ptr
  %t2623 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2622, ptr %t2623
  br label %reuse.join.2621
reuse.copy.2620:
  %t2624 = call ptr @__alloc(i64 24, i32 2)
  %t2625 = inttoptr i64 99 to ptr
  %t2626 = getelementptr ptr, ptr %t2624, i32 0
  store ptr %t2625, ptr %t2626
  call void @__inc_ref(ptr %t2613)
  %t2627 = getelementptr ptr, ptr %t2624, i32 1
  store ptr %t2613, ptr %t2627
  call void @__inc_ref(ptr %t2615)
  %t2628 = getelementptr ptr, ptr %t2624, i32 2
  store ptr %t2615, ptr %t2628
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2621
reuse.join.2621:
  %t2629 = phi ptr [ %t5, %reuse.in_place.2619 ], [ %t2624, %reuse.copy.2620 ]
  %t2630 = call ptr @__alloc(i64 16, i32 1)
  %t2631 = inttoptr i64 273 to ptr
  %t2632 = getelementptr ptr, ptr %t2630, i32 0
  store ptr %t2631, ptr %t2632
  call void @__inc_ref(ptr %t6)
  %t2633 = getelementptr ptr, ptr %t2630, i32 1
  store ptr %t6, ptr %t2633
  call void @__free_recursive(ptr %t6)
  store ptr %t2629, ptr %t3
  store ptr %t2630, ptr %t4
  br label %tco.loop.0
tco.case.arm.153.2634:
  %t2635 = getelementptr ptr, ptr %t5, i32 1
  %t2636 = load ptr, ptr %t2635
  %t2637 = getelementptr ptr, ptr %t5, i32 2
  %t2638 = load ptr, ptr %t2637
  %t2639 = getelementptr i8, ptr %t5, i64 -8
  %t2640 = load i32, ptr %t2639
  %t2641 = icmp eq i32 %t2640, 1
  br i1 %t2641, label %reuse.in_place.2642, label %reuse.copy.2643
reuse.in_place.2642:
  %t2645 = inttoptr i64 99 to ptr
  %t2646 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2645, ptr %t2646
  br label %reuse.join.2644
reuse.copy.2643:
  %t2647 = call ptr @__alloc(i64 24, i32 2)
  %t2648 = inttoptr i64 99 to ptr
  %t2649 = getelementptr ptr, ptr %t2647, i32 0
  store ptr %t2648, ptr %t2649
  call void @__inc_ref(ptr %t2636)
  %t2650 = getelementptr ptr, ptr %t2647, i32 1
  store ptr %t2636, ptr %t2650
  call void @__inc_ref(ptr %t2638)
  %t2651 = getelementptr ptr, ptr %t2647, i32 2
  store ptr %t2638, ptr %t2651
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2644
reuse.join.2644:
  %t2652 = phi ptr [ %t5, %reuse.in_place.2642 ], [ %t2647, %reuse.copy.2643 ]
  %t2653 = call ptr @__alloc(i64 16, i32 1)
  %t2654 = inttoptr i64 274 to ptr
  %t2655 = getelementptr ptr, ptr %t2653, i32 0
  store ptr %t2654, ptr %t2655
  call void @__inc_ref(ptr %t6)
  %t2656 = getelementptr ptr, ptr %t2653, i32 1
  store ptr %t6, ptr %t2656
  call void @__free_recursive(ptr %t6)
  store ptr %t2652, ptr %t3
  store ptr %t2653, ptr %t4
  br label %tco.loop.0
tco.case.arm.154.2657:
  %t2658 = getelementptr ptr, ptr %t5, i32 1
  %t2659 = load ptr, ptr %t2658
  %t2660 = getelementptr ptr, ptr %t5, i32 2
  %t2661 = load ptr, ptr %t2660
  %t2662 = getelementptr i8, ptr %t5, i64 -8
  %t2663 = load i32, ptr %t2662
  %t2664 = icmp eq i32 %t2663, 1
  br i1 %t2664, label %reuse.in_place.2665, label %reuse.copy.2666
reuse.in_place.2665:
  %t2668 = inttoptr i64 99 to ptr
  %t2669 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2668, ptr %t2669
  br label %reuse.join.2667
reuse.copy.2666:
  %t2670 = call ptr @__alloc(i64 24, i32 2)
  %t2671 = inttoptr i64 99 to ptr
  %t2672 = getelementptr ptr, ptr %t2670, i32 0
  store ptr %t2671, ptr %t2672
  call void @__inc_ref(ptr %t2659)
  %t2673 = getelementptr ptr, ptr %t2670, i32 1
  store ptr %t2659, ptr %t2673
  call void @__inc_ref(ptr %t2661)
  %t2674 = getelementptr ptr, ptr %t2670, i32 2
  store ptr %t2661, ptr %t2674
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2667
reuse.join.2667:
  %t2675 = phi ptr [ %t5, %reuse.in_place.2665 ], [ %t2670, %reuse.copy.2666 ]
  %t2676 = call ptr @__alloc(i64 16, i32 1)
  %t2677 = inttoptr i64 275 to ptr
  %t2678 = getelementptr ptr, ptr %t2676, i32 0
  store ptr %t2677, ptr %t2678
  call void @__inc_ref(ptr %t6)
  %t2679 = getelementptr ptr, ptr %t2676, i32 1
  store ptr %t6, ptr %t2679
  call void @__free_recursive(ptr %t6)
  store ptr %t2675, ptr %t3
  store ptr %t2676, ptr %t4
  br label %tco.loop.0
tco.case.arm.155.2680:
  %t2681 = getelementptr ptr, ptr %t5, i32 1
  %t2682 = load ptr, ptr %t2681
  %t2683 = getelementptr ptr, ptr %t5, i32 2
  %t2684 = load ptr, ptr %t2683
  %t2685 = getelementptr i8, ptr %t5, i64 -8
  %t2686 = load i32, ptr %t2685
  %t2687 = icmp eq i32 %t2686, 1
  br i1 %t2687, label %reuse.in_place.2688, label %reuse.copy.2689
reuse.in_place.2688:
  %t2691 = inttoptr i64 99 to ptr
  %t2692 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2691, ptr %t2692
  br label %reuse.join.2690
reuse.copy.2689:
  %t2693 = call ptr @__alloc(i64 24, i32 2)
  %t2694 = inttoptr i64 99 to ptr
  %t2695 = getelementptr ptr, ptr %t2693, i32 0
  store ptr %t2694, ptr %t2695
  call void @__inc_ref(ptr %t2682)
  %t2696 = getelementptr ptr, ptr %t2693, i32 1
  store ptr %t2682, ptr %t2696
  call void @__inc_ref(ptr %t2684)
  %t2697 = getelementptr ptr, ptr %t2693, i32 2
  store ptr %t2684, ptr %t2697
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2690
reuse.join.2690:
  %t2698 = phi ptr [ %t5, %reuse.in_place.2688 ], [ %t2693, %reuse.copy.2689 ]
  %t2699 = call ptr @__alloc(i64 16, i32 1)
  %t2700 = inttoptr i64 276 to ptr
  %t2701 = getelementptr ptr, ptr %t2699, i32 0
  store ptr %t2700, ptr %t2701
  call void @__inc_ref(ptr %t6)
  %t2702 = getelementptr ptr, ptr %t2699, i32 1
  store ptr %t6, ptr %t2702
  call void @__free_recursive(ptr %t6)
  store ptr %t2698, ptr %t3
  store ptr %t2699, ptr %t4
  br label %tco.loop.0
tco.case.arm.156.2703:
  %t2704 = getelementptr ptr, ptr %t5, i32 1
  %t2705 = load ptr, ptr %t2704
  %t2706 = getelementptr ptr, ptr %t5, i32 2
  %t2707 = load ptr, ptr %t2706
  %t2708 = getelementptr i8, ptr %t5, i64 -8
  %t2709 = load i32, ptr %t2708
  %t2710 = icmp eq i32 %t2709, 1
  br i1 %t2710, label %reuse.in_place.2711, label %reuse.copy.2712
reuse.in_place.2711:
  %t2714 = inttoptr i64 99 to ptr
  %t2715 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2714, ptr %t2715
  br label %reuse.join.2713
reuse.copy.2712:
  %t2716 = call ptr @__alloc(i64 24, i32 2)
  %t2717 = inttoptr i64 99 to ptr
  %t2718 = getelementptr ptr, ptr %t2716, i32 0
  store ptr %t2717, ptr %t2718
  call void @__inc_ref(ptr %t2705)
  %t2719 = getelementptr ptr, ptr %t2716, i32 1
  store ptr %t2705, ptr %t2719
  call void @__inc_ref(ptr %t2707)
  %t2720 = getelementptr ptr, ptr %t2716, i32 2
  store ptr %t2707, ptr %t2720
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2713
reuse.join.2713:
  %t2721 = phi ptr [ %t5, %reuse.in_place.2711 ], [ %t2716, %reuse.copy.2712 ]
  %t2722 = call ptr @__alloc(i64 16, i32 1)
  %t2723 = inttoptr i64 277 to ptr
  %t2724 = getelementptr ptr, ptr %t2722, i32 0
  store ptr %t2723, ptr %t2724
  call void @__inc_ref(ptr %t6)
  %t2725 = getelementptr ptr, ptr %t2722, i32 1
  store ptr %t6, ptr %t2725
  call void @__free_recursive(ptr %t6)
  store ptr %t2721, ptr %t3
  store ptr %t2722, ptr %t4
  br label %tco.loop.0
tco.case.arm.157.2726:
  %t2727 = getelementptr ptr, ptr %t5, i32 1
  %t2728 = load ptr, ptr %t2727
  %t2729 = getelementptr ptr, ptr %t5, i32 2
  %t2730 = load ptr, ptr %t2729
  %t2731 = getelementptr i8, ptr %t5, i64 -8
  %t2732 = load i32, ptr %t2731
  %t2733 = icmp eq i32 %t2732, 1
  br i1 %t2733, label %reuse.in_place.2734, label %reuse.copy.2735
reuse.in_place.2734:
  %t2737 = inttoptr i64 99 to ptr
  %t2738 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2737, ptr %t2738
  br label %reuse.join.2736
reuse.copy.2735:
  %t2739 = call ptr @__alloc(i64 24, i32 2)
  %t2740 = inttoptr i64 99 to ptr
  %t2741 = getelementptr ptr, ptr %t2739, i32 0
  store ptr %t2740, ptr %t2741
  call void @__inc_ref(ptr %t2728)
  %t2742 = getelementptr ptr, ptr %t2739, i32 1
  store ptr %t2728, ptr %t2742
  call void @__inc_ref(ptr %t2730)
  %t2743 = getelementptr ptr, ptr %t2739, i32 2
  store ptr %t2730, ptr %t2743
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2736
reuse.join.2736:
  %t2744 = phi ptr [ %t5, %reuse.in_place.2734 ], [ %t2739, %reuse.copy.2735 ]
  %t2745 = call ptr @__alloc(i64 16, i32 1)
  %t2746 = inttoptr i64 278 to ptr
  %t2747 = getelementptr ptr, ptr %t2745, i32 0
  store ptr %t2746, ptr %t2747
  call void @__inc_ref(ptr %t6)
  %t2748 = getelementptr ptr, ptr %t2745, i32 1
  store ptr %t6, ptr %t2748
  call void @__free_recursive(ptr %t6)
  store ptr %t2744, ptr %t3
  store ptr %t2745, ptr %t4
  br label %tco.loop.0
tco.case.arm.158.2749:
  %t2750 = getelementptr ptr, ptr %t5, i32 1
  %t2751 = load ptr, ptr %t2750
  %t2752 = getelementptr ptr, ptr %t5, i32 2
  %t2753 = load ptr, ptr %t2752
  %t2754 = getelementptr i8, ptr %t5, i64 -8
  %t2755 = load i32, ptr %t2754
  %t2756 = icmp eq i32 %t2755, 1
  br i1 %t2756, label %reuse.in_place.2757, label %reuse.copy.2758
reuse.in_place.2757:
  %t2760 = inttoptr i64 99 to ptr
  %t2761 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2760, ptr %t2761
  br label %reuse.join.2759
reuse.copy.2758:
  %t2762 = call ptr @__alloc(i64 24, i32 2)
  %t2763 = inttoptr i64 99 to ptr
  %t2764 = getelementptr ptr, ptr %t2762, i32 0
  store ptr %t2763, ptr %t2764
  call void @__inc_ref(ptr %t2751)
  %t2765 = getelementptr ptr, ptr %t2762, i32 1
  store ptr %t2751, ptr %t2765
  call void @__inc_ref(ptr %t2753)
  %t2766 = getelementptr ptr, ptr %t2762, i32 2
  store ptr %t2753, ptr %t2766
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2759
reuse.join.2759:
  %t2767 = phi ptr [ %t5, %reuse.in_place.2757 ], [ %t2762, %reuse.copy.2758 ]
  %t2768 = call ptr @__alloc(i64 16, i32 1)
  %t2769 = inttoptr i64 279 to ptr
  %t2770 = getelementptr ptr, ptr %t2768, i32 0
  store ptr %t2769, ptr %t2770
  call void @__inc_ref(ptr %t6)
  %t2771 = getelementptr ptr, ptr %t2768, i32 1
  store ptr %t6, ptr %t2771
  call void @__free_recursive(ptr %t6)
  store ptr %t2767, ptr %t3
  store ptr %t2768, ptr %t4
  br label %tco.loop.0
tco.case.arm.159.2772:
  %t2773 = getelementptr ptr, ptr %t5, i32 1
  %t2774 = load ptr, ptr %t2773
  %t2775 = getelementptr ptr, ptr %t5, i32 2
  %t2776 = load ptr, ptr %t2775
  %t2777 = getelementptr i8, ptr %t5, i64 -8
  %t2778 = load i32, ptr %t2777
  %t2779 = icmp eq i32 %t2778, 1
  br i1 %t2779, label %reuse.in_place.2780, label %reuse.copy.2781
reuse.in_place.2780:
  %t2783 = inttoptr i64 99 to ptr
  %t2784 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2783, ptr %t2784
  br label %reuse.join.2782
reuse.copy.2781:
  %t2785 = call ptr @__alloc(i64 24, i32 2)
  %t2786 = inttoptr i64 99 to ptr
  %t2787 = getelementptr ptr, ptr %t2785, i32 0
  store ptr %t2786, ptr %t2787
  call void @__inc_ref(ptr %t2774)
  %t2788 = getelementptr ptr, ptr %t2785, i32 1
  store ptr %t2774, ptr %t2788
  call void @__inc_ref(ptr %t2776)
  %t2789 = getelementptr ptr, ptr %t2785, i32 2
  store ptr %t2776, ptr %t2789
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2782
reuse.join.2782:
  %t2790 = phi ptr [ %t5, %reuse.in_place.2780 ], [ %t2785, %reuse.copy.2781 ]
  %t2791 = call ptr @__alloc(i64 16, i32 1)
  %t2792 = inttoptr i64 280 to ptr
  %t2793 = getelementptr ptr, ptr %t2791, i32 0
  store ptr %t2792, ptr %t2793
  call void @__inc_ref(ptr %t6)
  %t2794 = getelementptr ptr, ptr %t2791, i32 1
  store ptr %t6, ptr %t2794
  call void @__free_recursive(ptr %t6)
  store ptr %t2790, ptr %t3
  store ptr %t2791, ptr %t4
  br label %tco.loop.0
tco.case.arm.160.2795:
  %t2796 = getelementptr ptr, ptr %t5, i32 1
  %t2797 = load ptr, ptr %t2796
  %t2798 = getelementptr ptr, ptr %t5, i32 2
  %t2799 = load ptr, ptr %t2798
  %t2800 = getelementptr i8, ptr %t5, i64 -8
  %t2801 = load i32, ptr %t2800
  %t2802 = icmp eq i32 %t2801, 1
  br i1 %t2802, label %reuse.in_place.2803, label %reuse.copy.2804
reuse.in_place.2803:
  %t2806 = inttoptr i64 99 to ptr
  %t2807 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2806, ptr %t2807
  br label %reuse.join.2805
reuse.copy.2804:
  %t2808 = call ptr @__alloc(i64 24, i32 2)
  %t2809 = inttoptr i64 99 to ptr
  %t2810 = getelementptr ptr, ptr %t2808, i32 0
  store ptr %t2809, ptr %t2810
  call void @__inc_ref(ptr %t2797)
  %t2811 = getelementptr ptr, ptr %t2808, i32 1
  store ptr %t2797, ptr %t2811
  call void @__inc_ref(ptr %t2799)
  %t2812 = getelementptr ptr, ptr %t2808, i32 2
  store ptr %t2799, ptr %t2812
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2805
reuse.join.2805:
  %t2813 = phi ptr [ %t5, %reuse.in_place.2803 ], [ %t2808, %reuse.copy.2804 ]
  %t2814 = call ptr @__alloc(i64 16, i32 1)
  %t2815 = inttoptr i64 281 to ptr
  %t2816 = getelementptr ptr, ptr %t2814, i32 0
  store ptr %t2815, ptr %t2816
  call void @__inc_ref(ptr %t6)
  %t2817 = getelementptr ptr, ptr %t2814, i32 1
  store ptr %t6, ptr %t2817
  call void @__free_recursive(ptr %t6)
  store ptr %t2813, ptr %t3
  store ptr %t2814, ptr %t4
  br label %tco.loop.0
tco.case.arm.161.2818:
  %t2819 = getelementptr ptr, ptr %t5, i32 1
  %t2820 = load ptr, ptr %t2819
  %t2821 = getelementptr ptr, ptr %t5, i32 2
  %t2822 = load ptr, ptr %t2821
  %t2823 = getelementptr i8, ptr %t5, i64 -8
  %t2824 = load i32, ptr %t2823
  %t2825 = icmp eq i32 %t2824, 1
  br i1 %t2825, label %reuse.in_place.2826, label %reuse.copy.2827
reuse.in_place.2826:
  %t2829 = inttoptr i64 99 to ptr
  %t2830 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2829, ptr %t2830
  br label %reuse.join.2828
reuse.copy.2827:
  %t2831 = call ptr @__alloc(i64 24, i32 2)
  %t2832 = inttoptr i64 99 to ptr
  %t2833 = getelementptr ptr, ptr %t2831, i32 0
  store ptr %t2832, ptr %t2833
  call void @__inc_ref(ptr %t2820)
  %t2834 = getelementptr ptr, ptr %t2831, i32 1
  store ptr %t2820, ptr %t2834
  call void @__inc_ref(ptr %t2822)
  %t2835 = getelementptr ptr, ptr %t2831, i32 2
  store ptr %t2822, ptr %t2835
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2828
reuse.join.2828:
  %t2836 = phi ptr [ %t5, %reuse.in_place.2826 ], [ %t2831, %reuse.copy.2827 ]
  %t2837 = call ptr @__alloc(i64 16, i32 1)
  %t2838 = inttoptr i64 282 to ptr
  %t2839 = getelementptr ptr, ptr %t2837, i32 0
  store ptr %t2838, ptr %t2839
  call void @__inc_ref(ptr %t6)
  %t2840 = getelementptr ptr, ptr %t2837, i32 1
  store ptr %t6, ptr %t2840
  call void @__free_recursive(ptr %t6)
  store ptr %t2836, ptr %t3
  store ptr %t2837, ptr %t4
  br label %tco.loop.0
tco.case.arm.162.2841:
  %t2842 = getelementptr ptr, ptr %t5, i32 1
  %t2843 = load ptr, ptr %t2842
  %t2844 = getelementptr ptr, ptr %t5, i32 2
  %t2845 = load ptr, ptr %t2844
  %t2846 = getelementptr i8, ptr %t5, i64 -8
  %t2847 = load i32, ptr %t2846
  %t2848 = icmp eq i32 %t2847, 1
  br i1 %t2848, label %reuse.in_place.2849, label %reuse.copy.2850
reuse.in_place.2849:
  %t2852 = inttoptr i64 99 to ptr
  %t2853 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2852, ptr %t2853
  br label %reuse.join.2851
reuse.copy.2850:
  %t2854 = call ptr @__alloc(i64 24, i32 2)
  %t2855 = inttoptr i64 99 to ptr
  %t2856 = getelementptr ptr, ptr %t2854, i32 0
  store ptr %t2855, ptr %t2856
  call void @__inc_ref(ptr %t2843)
  %t2857 = getelementptr ptr, ptr %t2854, i32 1
  store ptr %t2843, ptr %t2857
  call void @__inc_ref(ptr %t2845)
  %t2858 = getelementptr ptr, ptr %t2854, i32 2
  store ptr %t2845, ptr %t2858
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2851
reuse.join.2851:
  %t2859 = phi ptr [ %t5, %reuse.in_place.2849 ], [ %t2854, %reuse.copy.2850 ]
  %t2860 = call ptr @__alloc(i64 16, i32 1)
  %t2861 = inttoptr i64 283 to ptr
  %t2862 = getelementptr ptr, ptr %t2860, i32 0
  store ptr %t2861, ptr %t2862
  call void @__inc_ref(ptr %t6)
  %t2863 = getelementptr ptr, ptr %t2860, i32 1
  store ptr %t6, ptr %t2863
  call void @__free_recursive(ptr %t6)
  store ptr %t2859, ptr %t3
  store ptr %t2860, ptr %t4
  br label %tco.loop.0
tco.case.arm.163.2864:
  %t2865 = getelementptr ptr, ptr %t5, i32 1
  %t2866 = load ptr, ptr %t2865
  %t2867 = getelementptr ptr, ptr %t5, i32 2
  %t2868 = load ptr, ptr %t2867
  %t2869 = getelementptr i8, ptr %t5, i64 -8
  %t2870 = load i32, ptr %t2869
  %t2871 = icmp eq i32 %t2870, 1
  br i1 %t2871, label %reuse.in_place.2872, label %reuse.copy.2873
reuse.in_place.2872:
  %t2875 = inttoptr i64 99 to ptr
  %t2876 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2875, ptr %t2876
  br label %reuse.join.2874
reuse.copy.2873:
  %t2877 = call ptr @__alloc(i64 24, i32 2)
  %t2878 = inttoptr i64 99 to ptr
  %t2879 = getelementptr ptr, ptr %t2877, i32 0
  store ptr %t2878, ptr %t2879
  call void @__inc_ref(ptr %t2866)
  %t2880 = getelementptr ptr, ptr %t2877, i32 1
  store ptr %t2866, ptr %t2880
  call void @__inc_ref(ptr %t2868)
  %t2881 = getelementptr ptr, ptr %t2877, i32 2
  store ptr %t2868, ptr %t2881
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2874
reuse.join.2874:
  %t2882 = phi ptr [ %t5, %reuse.in_place.2872 ], [ %t2877, %reuse.copy.2873 ]
  %t2883 = call ptr @__alloc(i64 16, i32 1)
  %t2884 = inttoptr i64 284 to ptr
  %t2885 = getelementptr ptr, ptr %t2883, i32 0
  store ptr %t2884, ptr %t2885
  call void @__inc_ref(ptr %t6)
  %t2886 = getelementptr ptr, ptr %t2883, i32 1
  store ptr %t6, ptr %t2886
  call void @__free_recursive(ptr %t6)
  store ptr %t2882, ptr %t3
  store ptr %t2883, ptr %t4
  br label %tco.loop.0
tco.case.arm.164.2887:
  %t2888 = getelementptr ptr, ptr %t5, i32 1
  %t2889 = load ptr, ptr %t2888
  %t2890 = getelementptr ptr, ptr %t5, i32 2
  %t2891 = load ptr, ptr %t2890
  %t2892 = getelementptr i8, ptr %t5, i64 -8
  %t2893 = load i32, ptr %t2892
  %t2894 = icmp eq i32 %t2893, 1
  br i1 %t2894, label %reuse.in_place.2895, label %reuse.copy.2896
reuse.in_place.2895:
  %t2898 = inttoptr i64 99 to ptr
  %t2899 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2898, ptr %t2899
  br label %reuse.join.2897
reuse.copy.2896:
  %t2900 = call ptr @__alloc(i64 24, i32 2)
  %t2901 = inttoptr i64 99 to ptr
  %t2902 = getelementptr ptr, ptr %t2900, i32 0
  store ptr %t2901, ptr %t2902
  call void @__inc_ref(ptr %t2889)
  %t2903 = getelementptr ptr, ptr %t2900, i32 1
  store ptr %t2889, ptr %t2903
  call void @__inc_ref(ptr %t2891)
  %t2904 = getelementptr ptr, ptr %t2900, i32 2
  store ptr %t2891, ptr %t2904
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2897
reuse.join.2897:
  %t2905 = phi ptr [ %t5, %reuse.in_place.2895 ], [ %t2900, %reuse.copy.2896 ]
  %t2906 = call ptr @__alloc(i64 16, i32 1)
  %t2907 = inttoptr i64 285 to ptr
  %t2908 = getelementptr ptr, ptr %t2906, i32 0
  store ptr %t2907, ptr %t2908
  call void @__inc_ref(ptr %t6)
  %t2909 = getelementptr ptr, ptr %t2906, i32 1
  store ptr %t6, ptr %t2909
  call void @__free_recursive(ptr %t6)
  store ptr %t2905, ptr %t3
  store ptr %t2906, ptr %t4
  br label %tco.loop.0
tco.case.arm.165.2910:
  %t2911 = getelementptr ptr, ptr %t5, i32 1
  %t2912 = load ptr, ptr %t2911
  %t2913 = getelementptr ptr, ptr %t5, i32 2
  %t2914 = load ptr, ptr %t2913
  %t2915 = getelementptr i8, ptr %t5, i64 -8
  %t2916 = load i32, ptr %t2915
  %t2917 = icmp eq i32 %t2916, 1
  br i1 %t2917, label %reuse.in_place.2918, label %reuse.copy.2919
reuse.in_place.2918:
  %t2921 = inttoptr i64 99 to ptr
  %t2922 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2921, ptr %t2922
  br label %reuse.join.2920
reuse.copy.2919:
  %t2923 = call ptr @__alloc(i64 24, i32 2)
  %t2924 = inttoptr i64 99 to ptr
  %t2925 = getelementptr ptr, ptr %t2923, i32 0
  store ptr %t2924, ptr %t2925
  call void @__inc_ref(ptr %t2912)
  %t2926 = getelementptr ptr, ptr %t2923, i32 1
  store ptr %t2912, ptr %t2926
  call void @__inc_ref(ptr %t2914)
  %t2927 = getelementptr ptr, ptr %t2923, i32 2
  store ptr %t2914, ptr %t2927
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2920
reuse.join.2920:
  %t2928 = phi ptr [ %t5, %reuse.in_place.2918 ], [ %t2923, %reuse.copy.2919 ]
  %t2929 = call ptr @__alloc(i64 16, i32 1)
  %t2930 = inttoptr i64 286 to ptr
  %t2931 = getelementptr ptr, ptr %t2929, i32 0
  store ptr %t2930, ptr %t2931
  call void @__inc_ref(ptr %t6)
  %t2932 = getelementptr ptr, ptr %t2929, i32 1
  store ptr %t6, ptr %t2932
  call void @__free_recursive(ptr %t6)
  store ptr %t2928, ptr %t3
  store ptr %t2929, ptr %t4
  br label %tco.loop.0
tco.case.arm.166.2933:
  %t2934 = getelementptr ptr, ptr %t5, i32 1
  %t2935 = load ptr, ptr %t2934
  %t2936 = getelementptr ptr, ptr %t5, i32 2
  %t2937 = load ptr, ptr %t2936
  %t2938 = getelementptr i8, ptr %t5, i64 -8
  %t2939 = load i32, ptr %t2938
  %t2940 = icmp eq i32 %t2939, 1
  br i1 %t2940, label %reuse.in_place.2941, label %reuse.copy.2942
reuse.in_place.2941:
  %t2944 = inttoptr i64 99 to ptr
  %t2945 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2944, ptr %t2945
  br label %reuse.join.2943
reuse.copy.2942:
  %t2946 = call ptr @__alloc(i64 24, i32 2)
  %t2947 = inttoptr i64 99 to ptr
  %t2948 = getelementptr ptr, ptr %t2946, i32 0
  store ptr %t2947, ptr %t2948
  call void @__inc_ref(ptr %t2935)
  %t2949 = getelementptr ptr, ptr %t2946, i32 1
  store ptr %t2935, ptr %t2949
  call void @__inc_ref(ptr %t2937)
  %t2950 = getelementptr ptr, ptr %t2946, i32 2
  store ptr %t2937, ptr %t2950
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2943
reuse.join.2943:
  %t2951 = phi ptr [ %t5, %reuse.in_place.2941 ], [ %t2946, %reuse.copy.2942 ]
  %t2952 = call ptr @__alloc(i64 16, i32 1)
  %t2953 = inttoptr i64 287 to ptr
  %t2954 = getelementptr ptr, ptr %t2952, i32 0
  store ptr %t2953, ptr %t2954
  call void @__inc_ref(ptr %t6)
  %t2955 = getelementptr ptr, ptr %t2952, i32 1
  store ptr %t6, ptr %t2955
  call void @__free_recursive(ptr %t6)
  store ptr %t2951, ptr %t3
  store ptr %t2952, ptr %t4
  br label %tco.loop.0
tco.case.arm.167.2956:
  %t2957 = getelementptr ptr, ptr %t5, i32 1
  %t2958 = load ptr, ptr %t2957
  %t2959 = getelementptr ptr, ptr %t5, i32 2
  %t2960 = load ptr, ptr %t2959
  %t2961 = getelementptr i8, ptr %t5, i64 -8
  %t2962 = load i32, ptr %t2961
  %t2963 = icmp eq i32 %t2962, 1
  br i1 %t2963, label %reuse.in_place.2964, label %reuse.copy.2965
reuse.in_place.2964:
  %t2967 = inttoptr i64 99 to ptr
  %t2968 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2967, ptr %t2968
  br label %reuse.join.2966
reuse.copy.2965:
  %t2969 = call ptr @__alloc(i64 24, i32 2)
  %t2970 = inttoptr i64 99 to ptr
  %t2971 = getelementptr ptr, ptr %t2969, i32 0
  store ptr %t2970, ptr %t2971
  call void @__inc_ref(ptr %t2958)
  %t2972 = getelementptr ptr, ptr %t2969, i32 1
  store ptr %t2958, ptr %t2972
  call void @__inc_ref(ptr %t2960)
  %t2973 = getelementptr ptr, ptr %t2969, i32 2
  store ptr %t2960, ptr %t2973
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2966
reuse.join.2966:
  %t2974 = phi ptr [ %t5, %reuse.in_place.2964 ], [ %t2969, %reuse.copy.2965 ]
  %t2975 = call ptr @__alloc(i64 16, i32 1)
  %t2976 = inttoptr i64 288 to ptr
  %t2977 = getelementptr ptr, ptr %t2975, i32 0
  store ptr %t2976, ptr %t2977
  call void @__inc_ref(ptr %t6)
  %t2978 = getelementptr ptr, ptr %t2975, i32 1
  store ptr %t6, ptr %t2978
  call void @__free_recursive(ptr %t6)
  store ptr %t2974, ptr %t3
  store ptr %t2975, ptr %t4
  br label %tco.loop.0
tco.case.arm.168.2979:
  %t2980 = getelementptr ptr, ptr %t5, i32 1
  %t2981 = load ptr, ptr %t2980
  %t2982 = getelementptr ptr, ptr %t5, i32 2
  %t2983 = load ptr, ptr %t2982
  %t2984 = getelementptr i8, ptr %t5, i64 -8
  %t2985 = load i32, ptr %t2984
  %t2986 = icmp eq i32 %t2985, 1
  br i1 %t2986, label %reuse.in_place.2987, label %reuse.copy.2988
reuse.in_place.2987:
  %t2990 = inttoptr i64 99 to ptr
  %t2991 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2990, ptr %t2991
  br label %reuse.join.2989
reuse.copy.2988:
  %t2992 = call ptr @__alloc(i64 24, i32 2)
  %t2993 = inttoptr i64 99 to ptr
  %t2994 = getelementptr ptr, ptr %t2992, i32 0
  store ptr %t2993, ptr %t2994
  call void @__inc_ref(ptr %t2981)
  %t2995 = getelementptr ptr, ptr %t2992, i32 1
  store ptr %t2981, ptr %t2995
  call void @__inc_ref(ptr %t2983)
  %t2996 = getelementptr ptr, ptr %t2992, i32 2
  store ptr %t2983, ptr %t2996
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2989
reuse.join.2989:
  %t2997 = phi ptr [ %t5, %reuse.in_place.2987 ], [ %t2992, %reuse.copy.2988 ]
  %t2998 = call ptr @__alloc(i64 16, i32 1)
  %t2999 = inttoptr i64 289 to ptr
  %t3000 = getelementptr ptr, ptr %t2998, i32 0
  store ptr %t2999, ptr %t3000
  call void @__inc_ref(ptr %t6)
  %t3001 = getelementptr ptr, ptr %t2998, i32 1
  store ptr %t6, ptr %t3001
  call void @__free_recursive(ptr %t6)
  store ptr %t2997, ptr %t3
  store ptr %t2998, ptr %t4
  br label %tco.loop.0
tco.case.arm.169.3002:
  %t3003 = getelementptr ptr, ptr %t5, i32 1
  %t3004 = load ptr, ptr %t3003
  %t3005 = getelementptr ptr, ptr %t5, i32 2
  %t3006 = load ptr, ptr %t3005
  %t3007 = getelementptr i8, ptr %t5, i64 -8
  %t3008 = load i32, ptr %t3007
  %t3009 = icmp eq i32 %t3008, 1
  br i1 %t3009, label %reuse.in_place.3010, label %reuse.copy.3011
reuse.in_place.3010:
  %t3013 = inttoptr i64 99 to ptr
  %t3014 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3013, ptr %t3014
  br label %reuse.join.3012
reuse.copy.3011:
  %t3015 = call ptr @__alloc(i64 24, i32 2)
  %t3016 = inttoptr i64 99 to ptr
  %t3017 = getelementptr ptr, ptr %t3015, i32 0
  store ptr %t3016, ptr %t3017
  call void @__inc_ref(ptr %t3004)
  %t3018 = getelementptr ptr, ptr %t3015, i32 1
  store ptr %t3004, ptr %t3018
  call void @__inc_ref(ptr %t3006)
  %t3019 = getelementptr ptr, ptr %t3015, i32 2
  store ptr %t3006, ptr %t3019
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3012
reuse.join.3012:
  %t3020 = phi ptr [ %t5, %reuse.in_place.3010 ], [ %t3015, %reuse.copy.3011 ]
  %t3021 = call ptr @__alloc(i64 16, i32 1)
  %t3022 = inttoptr i64 290 to ptr
  %t3023 = getelementptr ptr, ptr %t3021, i32 0
  store ptr %t3022, ptr %t3023
  call void @__inc_ref(ptr %t6)
  %t3024 = getelementptr ptr, ptr %t3021, i32 1
  store ptr %t6, ptr %t3024
  call void @__free_recursive(ptr %t6)
  store ptr %t3020, ptr %t3
  store ptr %t3021, ptr %t4
  br label %tco.loop.0
tco.case.arm.170.3025:
  %t3026 = getelementptr ptr, ptr %t5, i32 1
  %t3027 = load ptr, ptr %t3026
  %t3028 = getelementptr ptr, ptr %t5, i32 2
  %t3029 = load ptr, ptr %t3028
  %t3030 = getelementptr i8, ptr %t5, i64 -8
  %t3031 = load i32, ptr %t3030
  %t3032 = icmp eq i32 %t3031, 1
  br i1 %t3032, label %reuse.in_place.3033, label %reuse.copy.3034
reuse.in_place.3033:
  %t3036 = inttoptr i64 99 to ptr
  %t3037 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3036, ptr %t3037
  br label %reuse.join.3035
reuse.copy.3034:
  %t3038 = call ptr @__alloc(i64 24, i32 2)
  %t3039 = inttoptr i64 99 to ptr
  %t3040 = getelementptr ptr, ptr %t3038, i32 0
  store ptr %t3039, ptr %t3040
  call void @__inc_ref(ptr %t3027)
  %t3041 = getelementptr ptr, ptr %t3038, i32 1
  store ptr %t3027, ptr %t3041
  call void @__inc_ref(ptr %t3029)
  %t3042 = getelementptr ptr, ptr %t3038, i32 2
  store ptr %t3029, ptr %t3042
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3035
reuse.join.3035:
  %t3043 = phi ptr [ %t5, %reuse.in_place.3033 ], [ %t3038, %reuse.copy.3034 ]
  %t3044 = call ptr @__alloc(i64 16, i32 1)
  %t3045 = inttoptr i64 291 to ptr
  %t3046 = getelementptr ptr, ptr %t3044, i32 0
  store ptr %t3045, ptr %t3046
  call void @__inc_ref(ptr %t6)
  %t3047 = getelementptr ptr, ptr %t3044, i32 1
  store ptr %t6, ptr %t3047
  call void @__free_recursive(ptr %t6)
  store ptr %t3043, ptr %t3
  store ptr %t3044, ptr %t4
  br label %tco.loop.0
tco.case.arm.171.3048:
  %t3049 = getelementptr ptr, ptr %t5, i32 1
  %t3050 = load ptr, ptr %t3049
  %t3051 = getelementptr ptr, ptr %t5, i32 2
  %t3052 = load ptr, ptr %t3051
  %t3053 = getelementptr i8, ptr %t5, i64 -8
  %t3054 = load i32, ptr %t3053
  %t3055 = icmp eq i32 %t3054, 1
  br i1 %t3055, label %reuse.in_place.3056, label %reuse.copy.3057
reuse.in_place.3056:
  %t3059 = inttoptr i64 99 to ptr
  %t3060 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3059, ptr %t3060
  br label %reuse.join.3058
reuse.copy.3057:
  %t3061 = call ptr @__alloc(i64 24, i32 2)
  %t3062 = inttoptr i64 99 to ptr
  %t3063 = getelementptr ptr, ptr %t3061, i32 0
  store ptr %t3062, ptr %t3063
  call void @__inc_ref(ptr %t3050)
  %t3064 = getelementptr ptr, ptr %t3061, i32 1
  store ptr %t3050, ptr %t3064
  call void @__inc_ref(ptr %t3052)
  %t3065 = getelementptr ptr, ptr %t3061, i32 2
  store ptr %t3052, ptr %t3065
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3058
reuse.join.3058:
  %t3066 = phi ptr [ %t5, %reuse.in_place.3056 ], [ %t3061, %reuse.copy.3057 ]
  %t3067 = call ptr @__alloc(i64 16, i32 1)
  %t3068 = inttoptr i64 292 to ptr
  %t3069 = getelementptr ptr, ptr %t3067, i32 0
  store ptr %t3068, ptr %t3069
  call void @__inc_ref(ptr %t6)
  %t3070 = getelementptr ptr, ptr %t3067, i32 1
  store ptr %t6, ptr %t3070
  call void @__free_recursive(ptr %t6)
  store ptr %t3066, ptr %t3
  store ptr %t3067, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t3071 = load ptr, ptr %t2
  ret ptr %t3071
}

define internal ptr @v__apply1(ptr %v__cl, ptr %v__arg0) {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 99 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  call void @__inc_ref(ptr %v__cl)
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v__cl, ptr %t3
  call void @__inc_ref(ptr %v__arg0)
  %t4 = getelementptr ptr, ptr %t0, i32 2
  store ptr %v__arg0, ptr %t4
  %t5 = call ptr @v__scc__apply1__df__lam_0_25__df__lam_0_33__df__lam_0_53__df__lam_0_57__df__lam_0_61__df__lam_0_65__df__lam_0_69__df__lam_0_73__df__lam_0_77__df__lam_0_81__df__lam_0_85__df__lam_0_89__df__lam_0_93__df__lam_1_26__df__lam_1_34__df__lam_1_54__df__lam_1_58__df__lam_1_62__df__lam_1_66__df__lam_1_70__df__lam_1_74__df__lam_1_78__df__lam_1_82__df__lam_1_86__df__lam_1_90__df__lam_1_94__df__lam_10_10__df__lam_10_14__df__lam_10_18__df__lam_10_2__df__lam_10_22__df__lam_10_30__df__lam_10_42__df__lam_10_46__df__lam_10_6__df__lam_11_11__df__lam_11_15__df__lam_11_19__df__lam_11_23__df__lam_11_3__df__lam_11_31__df__lam_11_43__df__lam_11_47__df__lam_11_7__df__lam_2_27__df__lam_2_35__df__lam_2_55__df__lam_2_59__df__lam_2_63__df__lam_2_67__df__lam_2_71__df__lam_2_75__df__lam_2_79__df__lam_2_83__df__lam_2_87__df__lam_2_91__df__lam_2_95__df__lam_25_49__df__lam_26_50__df__lam_27_51__df__lam_3_37__df__lam_4_38__df__lam_5_39__df__lam_9_1__df__lam_9_13__df__lam_9_17__df__lam_9_21__df__lam_9_29__df__lam_9_41__df__lam_9_45__df__lam_9_5__df__lam_9_9(ptr %t0)
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
