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
  %t1 = call ptr @v__lift_24(ptr %t0)
  %t2 = call ptr @v__df_andThenIO_32(ptr %t1)
  %t3 = call ptr @v__df_handleErrorIO_40(ptr %t2)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
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
  %t1 = call ptr @v__df__rowspec_28_48(ptr %t0)
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
  %t12 = call ptr @v__lift_43(ptr %t0)
  %t13 = call ptr @v__df_andThenIO_60(ptr %t12)
  call void @__inc_ref(ptr %v_act)
  %t14 = call ptr @v__df_andThenIO_56(ptr %t13, ptr %v_act)
  %t15 = call ptr @v__df_andThenIO_52(ptr %t14)
  call void @__free_recursive(ptr %v_label)
  call void @__free_recursive(ptr %v_act)
  ret ptr %t15
}

define internal ptr @v_main() {
  %t0 = call ptr @v_recover()
  %t1 = call ptr @v_observeNever(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.6, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_43(ptr %t2)
  %t4 = call ptr @v__df_andThenIO_92(ptr %t3)
  %t5 = call ptr @v__df_andThenIO_88(ptr %t4)
  %t6 = call ptr @v__df_andThenIO_84(ptr %t5)
  %t7 = call ptr @v__df_andThenIO_80(ptr %t6)
  %t8 = call ptr @v__df_andThenIO_76(ptr %t7)
  %t9 = call ptr @v__df_andThenIO_72(ptr %t8)
  %t10 = call ptr @v__df_andThenIO_68(ptr %t9)
  %t11 = call ptr @v__df_andThenIO_64(ptr %t10)
  ret ptr %t11
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
  %t69 = inttoptr i64 103 to ptr
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

define internal ptr @v__lam_23(ptr %v__u) {
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 24 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_failIO(ptr %t0)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t3
}

define internal ptr @v__lift_24(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 204 to ptr
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
  call void @__inc_ref(ptr %t21)
  %t25 = getelementptr ptr, ptr %t22, i32 1
  store ptr %t21, ptr %t25
  %t26 = call ptr @v__apply__lift_24(ptr %t6, ptr %t22)
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
  %t42 = inttoptr i64 205 to ptr
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
  %t45 = inttoptr i64 205 to ptr
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
  %t61 = call ptr @v__apply__lift_24(ptr %t6, ptr %t53)
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
  %t69 = inttoptr i64 101 to ptr
  %t70 = getelementptr ptr, ptr %t68, i32 0
  store ptr %t69, ptr %t70
  call void @__inc_ref(ptr %t64)
  %t71 = getelementptr ptr, ptr %t68, i32 1
  store ptr %t64, ptr %t71
  %t72 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t68, ptr %t72
  %t73 = call ptr @v__apply__lift_24(ptr %t6, ptr %t65)
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
  %t81 = inttoptr i64 102 to ptr
  %t82 = getelementptr ptr, ptr %t80, i32 0
  store ptr %t81, ptr %t82
  call void @__inc_ref(ptr %t76)
  %t83 = getelementptr ptr, ptr %t80, i32 1
  store ptr %t76, ptr %t83
  %t84 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t80, ptr %t84
  %t85 = call ptr @v__apply__lift_24(ptr %t6, ptr %t77)
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

define internal ptr @v__lift_29(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 206 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__lift_29(ptr %v___input, ptr %t0)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t3
}

define internal ptr @v__cps__lift_29(ptr %v___input, ptr %v__k) {
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
  %t18 = call ptr @v__apply__lift_29(ptr %t6, ptr %t14)
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
  %t30 = call ptr @v__apply__lift_29(ptr %t6, ptr %t22)
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
  %t61 = inttoptr i64 104 to ptr
  %t62 = getelementptr ptr, ptr %t60, i32 0
  store ptr %t61, ptr %t62
  call void @__inc_ref(ptr %t56)
  %t63 = getelementptr ptr, ptr %t60, i32 1
  store ptr %t56, ptr %t63
  %t64 = getelementptr ptr, ptr %t57, i32 1
  store ptr %t60, ptr %t64
  %t65 = call ptr @v__apply__lift_29(ptr %t6, ptr %t57)
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
  %t73 = inttoptr i64 105 to ptr
  %t74 = getelementptr ptr, ptr %t72, i32 0
  store ptr %t73, ptr %t74
  call void @__inc_ref(ptr %t68)
  %t75 = getelementptr ptr, ptr %t72, i32 1
  store ptr %t68, ptr %t75
  %t76 = getelementptr ptr, ptr %t69, i32 1
  store ptr %t72, ptr %t76
  %t77 = call ptr @v__apply__lift_29(ptr %t6, ptr %t69)
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
  %t85 = inttoptr i64 106 to ptr
  %t86 = getelementptr ptr, ptr %t84, i32 0
  store ptr %t85, ptr %t86
  call void @__inc_ref(ptr %t80)
  %t87 = getelementptr ptr, ptr %t84, i32 1
  store ptr %t80, ptr %t87
  %t88 = getelementptr ptr, ptr %t81, i32 1
  store ptr %t84, ptr %t88
  %t89 = call ptr @v__apply__lift_29(ptr %t6, ptr %t81)
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

define internal ptr @v__apply__lift_29(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__lam_40(ptr %v__u) {
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

define internal ptr @v__lam_41(ptr %v_act, ptr %v__u) {
  call void @__free_recursive(ptr %v__u)
  ret ptr %v_act
}

define internal ptr @v__lam_42(ptr %v__u) {
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

define internal ptr @v__lift_43(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 210 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__lift_43(ptr %v___input, ptr %t0)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t3
}

define internal ptr @v__cps__lift_43(ptr %v___input, ptr %v__k) {
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
  %t18 = call ptr @v__apply__lift_43(ptr %t6, ptr %t14)
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
  %t26 = call ptr @v__apply__lift_43(ptr %t6, ptr %t22)
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
  %t61 = call ptr @v__apply__lift_43(ptr %t6, ptr %t53)
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
  %t73 = call ptr @v__apply__lift_43(ptr %t6, ptr %t65)
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
  %t85 = call ptr @v__apply__lift_43(ptr %t6, ptr %t77)
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

define internal ptr @v__apply__lift_43(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__lam_47(ptr %v__u) {
  %t0 = call ptr @v_treeNoError()
  %t1 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.9, i64 12), ptr %t0)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t1
}

define internal ptr @v__lam_48(ptr %v__u) {
  %t0 = call ptr @v_treePreserve()
  %t1 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.10, i64 12), ptr %t0)
  %t2 = call ptr @v__lift_43(ptr %t1)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t2
}

define internal ptr @v__lam_49(ptr %v__u) {
  %t0 = call ptr @v_refailRow()
  %t1 = call ptr @v_observeBC(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.11, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_43(ptr %t2)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t3
}

define internal ptr @v__lam_50(ptr %v__u) {
  %t0 = call ptr @v_refailNarrow()
  %t1 = call ptr @v_observeB(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.12, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_43(ptr %t2)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t3
}

define internal ptr @v__lam_51(ptr %v__u) {
  %t0 = call ptr @v_nested()
  %t1 = call ptr @v_observeNever(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.13, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_43(ptr %t2)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t3
}

define internal ptr @v__lam_52(ptr %v__u) {
  %t0 = call ptr @v_passthrough()
  %t1 = call ptr @v_observeNever(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.14, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_43(ptr %t2)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t3
}

define internal ptr @v__lam_53(ptr %v__u) {
  %t0 = call ptr @v_dispatchB()
  %t1 = call ptr @v_observeNever(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.15, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_43(ptr %t2)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t3
}

define internal ptr @v__lam_54(ptr %v__u) {
  %t0 = call ptr @v_dispatchA()
  %t1 = call ptr @v_observeNever(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.16, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_43(ptr %t2)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t3
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
  %t14 = call ptr @v__lam_23(ptr %t13)
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

define internal ptr @v__df__rowspec_28_48(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 236 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df__rowspec_28_48(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df__rowspec_28_48(ptr %v_io, ptr %v__k) {
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
  %t15 = call ptr @v__lift_29(ptr %t14)
  %t16 = call ptr @v__apply__df__rowspec_28_48(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df__rowspec_28_48(ptr %t6, ptr %t20)
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
  %t59 = call ptr @v__apply__df__rowspec_28_48(ptr %t6, ptr %t51)
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
  %t71 = call ptr @v__apply__df__rowspec_28_48(ptr %t6, ptr %t63)
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
  %t83 = call ptr @v__apply__df__rowspec_28_48(ptr %t6, ptr %t75)
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

define internal ptr @v__apply__df__rowspec_28_48(ptr %v__k, ptr %v__x) {
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
  %t14 = call ptr @v__lam_40(ptr %t13)
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
  %t16 = call ptr @v__lam_41(ptr %t7, ptr %t15)
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
  %t14 = call ptr @v__lam_42(ptr %t13)
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
  %t14 = call ptr @v__lam_47(ptr %t13)
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
  %t14 = call ptr @v__lam_48(ptr %t13)
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
  %t14 = call ptr @v__lam_49(ptr %t13)
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
  %t14 = call ptr @v__lam_50(ptr %t13)
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
  %t14 = call ptr @v__lam_51(ptr %t13)
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
  %t14 = call ptr @v__lam_52(ptr %t13)
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
  %t14 = call ptr @v__lam_53(ptr %t13)
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
  %t14 = call ptr @v__lam_54(ptr %t13)
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

define internal ptr @v__scc__apply1__df__lam_10_39__df__lam_14_1__df__lam_14_13__df__lam_14_17__df__lam_14_21__df__lam_14_29__df__lam_14_41__df__lam_14_45__df__lam_14_5__df__lam_14_9__df__lam_15_10__df__lam_15_14__df__lam_15_18__df__lam_15_2__df__lam_15_22__df__lam_15_30__df__lam_15_42__df__lam_15_46__df__lam_15_6__df__lam_16_11__df__lam_16_15__df__lam_16_19__df__lam_16_23__df__lam_16_3__df__lam_16_31__df__lam_16_43__df__lam_16_47__df__lam_16_7__df__lam_37_49__df__lam_38_50__df__lam_39_51__df__lam_5_25__df__lam_5_33__df__lam_5_53__df__lam_5_57__df__lam_5_61__df__lam_5_65__df__lam_5_69__df__lam_5_73__df__lam_5_77__df__lam_5_81__df__lam_5_85__df__lam_5_89__df__lam_5_93__df__lam_6_26__df__lam_6_34__df__lam_6_54__df__lam_6_58__df__lam_6_62__df__lam_6_66__df__lam_6_70__df__lam_6_74__df__lam_6_78__df__lam_6_82__df__lam_6_86__df__lam_6_90__df__lam_6_94__df__lam_7_27__df__lam_7_35__df__lam_7_55__df__lam_7_59__df__lam_7_63__df__lam_7_67__df__lam_7_71__df__lam_7_75__df__lam_7_79__df__lam_7_83__df__lam_7_87__df__lam_7_91__df__lam_7_95__df__lam_8_37__df__lam_9_38__lift_2__lift_25__lift_26__lift_27__lift_3__lift_30__lift_31__lift_32__lift_34__lift_35__lift_36__lift_4__lift_44__lift_45__lift_46(ptr %v__args) {
  call void @__inc_ref(ptr %v__args)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 260 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__scc__apply1__df__lam_10_39__df__lam_14_1__df__lam_14_13__df__lam_14_17__df__lam_14_21__df__lam_14_29__df__lam_14_41__df__lam_14_45__df__lam_14_5__df__lam_14_9__df__lam_15_10__df__lam_15_14__df__lam_15_18__df__lam_15_2__df__lam_15_22__df__lam_15_30__df__lam_15_42__df__lam_15_46__df__lam_15_6__df__lam_16_11__df__lam_16_15__df__lam_16_19__df__lam_16_23__df__lam_16_3__df__lam_16_31__df__lam_16_43__df__lam_16_47__df__lam_16_7__df__lam_37_49__df__lam_38_50__df__lam_39_51__df__lam_5_25__df__lam_5_33__df__lam_5_53__df__lam_5_57__df__lam_5_61__df__lam_5_65__df__lam_5_69__df__lam_5_73__df__lam_5_77__df__lam_5_81__df__lam_5_85__df__lam_5_89__df__lam_5_93__df__lam_6_26__df__lam_6_34__df__lam_6_54__df__lam_6_58__df__lam_6_62__df__lam_6_66__df__lam_6_70__df__lam_6_74__df__lam_6_78__df__lam_6_82__df__lam_6_86__df__lam_6_90__df__lam_6_94__df__lam_7_27__df__lam_7_35__df__lam_7_55__df__lam_7_59__df__lam_7_63__df__lam_7_67__df__lam_7_71__df__lam_7_75__df__lam_7_79__df__lam_7_83__df__lam_7_87__df__lam_7_91__df__lam_7_95__df__lam_8_37__df__lam_9_38__lift_2__lift_25__lift_26__lift_27__lift_3__lift_30__lift_31__lift_32__lift_34__lift_35__lift_36__lift_4__lift_44__lift_45__lift_46(ptr %v__args, ptr %t0)
  call void @__free_recursive(ptr %v__args)
  ret ptr %t3
}

define internal ptr @v__cps__scc__apply1__df__lam_10_39__df__lam_14_1__df__lam_14_13__df__lam_14_17__df__lam_14_21__df__lam_14_29__df__lam_14_41__df__lam_14_45__df__lam_14_5__df__lam_14_9__df__lam_15_10__df__lam_15_14__df__lam_15_18__df__lam_15_2__df__lam_15_22__df__lam_15_30__df__lam_15_42__df__lam_15_46__df__lam_15_6__df__lam_16_11__df__lam_16_15__df__lam_16_19__df__lam_16_23__df__lam_16_3__df__lam_16_31__df__lam_16_43__df__lam_16_47__df__lam_16_7__df__lam_37_49__df__lam_38_50__df__lam_39_51__df__lam_5_25__df__lam_5_33__df__lam_5_53__df__lam_5_57__df__lam_5_61__df__lam_5_65__df__lam_5_69__df__lam_5_73__df__lam_5_77__df__lam_5_81__df__lam_5_85__df__lam_5_89__df__lam_5_93__df__lam_6_26__df__lam_6_34__df__lam_6_54__df__lam_6_58__df__lam_6_62__df__lam_6_66__df__lam_6_70__df__lam_6_74__df__lam_6_78__df__lam_6_82__df__lam_6_86__df__lam_6_90__df__lam_6_94__df__lam_7_27__df__lam_7_35__df__lam_7_55__df__lam_7_59__df__lam_7_63__df__lam_7_67__df__lam_7_71__df__lam_7_75__df__lam_7_79__df__lam_7_83__df__lam_7_87__df__lam_7_91__df__lam_7_95__df__lam_8_37__df__lam_9_38__lift_2__lift_25__lift_26__lift_27__lift_3__lift_30__lift_31__lift_32__lift_34__lift_35__lift_36__lift_4__lift_44__lift_45__lift_46(ptr %v__args, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 114, label %tco.case.arm.114.11 i64 115, label %tco.case.arm.115.1673 i64 116, label %tco.case.arm.116.1696 i64 117, label %tco.case.arm.117.1719 i64 118, label %tco.case.arm.118.1742 i64 119, label %tco.case.arm.119.1765 i64 120, label %tco.case.arm.120.1788 i64 121, label %tco.case.arm.121.1811 i64 122, label %tco.case.arm.122.1834 i64 123, label %tco.case.arm.123.1857 i64 124, label %tco.case.arm.124.1880 i64 125, label %tco.case.arm.125.1903 i64 126, label %tco.case.arm.126.1926 i64 127, label %tco.case.arm.127.1949 i64 128, label %tco.case.arm.128.1972 i64 129, label %tco.case.arm.129.1995 i64 130, label %tco.case.arm.130.2018 i64 131, label %tco.case.arm.131.2041 i64 132, label %tco.case.arm.132.2064 i64 133, label %tco.case.arm.133.2087 i64 134, label %tco.case.arm.134.2110 i64 135, label %tco.case.arm.135.2133 i64 136, label %tco.case.arm.136.2156 i64 137, label %tco.case.arm.137.2179 i64 138, label %tco.case.arm.138.2202 i64 139, label %tco.case.arm.139.2225 i64 140, label %tco.case.arm.140.2248 i64 141, label %tco.case.arm.141.2271 i64 142, label %tco.case.arm.142.2294 i64 143, label %tco.case.arm.143.2317 i64 144, label %tco.case.arm.144.2340 i64 145, label %tco.case.arm.145.2363 i64 146, label %tco.case.arm.146.2386 i64 147, label %tco.case.arm.147.2409 i64 148, label %tco.case.arm.148.2432 i64 149, label %tco.case.arm.149.2455 i64 150, label %tco.case.arm.150.2472 i64 151, label %tco.case.arm.151.2495 i64 152, label %tco.case.arm.152.2518 i64 153, label %tco.case.arm.153.2541 i64 154, label %tco.case.arm.154.2564 i64 155, label %tco.case.arm.155.2587 i64 156, label %tco.case.arm.156.2610 i64 157, label %tco.case.arm.157.2633 i64 158, label %tco.case.arm.158.2656 i64 159, label %tco.case.arm.159.2679 i64 160, label %tco.case.arm.160.2702 i64 161, label %tco.case.arm.161.2725 i64 162, label %tco.case.arm.162.2748 i64 163, label %tco.case.arm.163.2765 i64 164, label %tco.case.arm.164.2788 i64 165, label %tco.case.arm.165.2811 i64 166, label %tco.case.arm.166.2834 i64 167, label %tco.case.arm.167.2857 i64 168, label %tco.case.arm.168.2880 i64 169, label %tco.case.arm.169.2903 i64 170, label %tco.case.arm.170.2926 i64 171, label %tco.case.arm.171.2949 i64 172, label %tco.case.arm.172.2972 i64 173, label %tco.case.arm.173.2995 i64 174, label %tco.case.arm.174.3018 i64 175, label %tco.case.arm.175.3041 i64 176, label %tco.case.arm.176.3058 i64 177, label %tco.case.arm.177.3081 i64 178, label %tco.case.arm.178.3104 i64 179, label %tco.case.arm.179.3127 i64 180, label %tco.case.arm.180.3150 i64 181, label %tco.case.arm.181.3173 i64 182, label %tco.case.arm.182.3196 i64 183, label %tco.case.arm.183.3219 i64 184, label %tco.case.arm.184.3242 i64 185, label %tco.case.arm.185.3265 i64 186, label %tco.case.arm.186.3288 i64 187, label %tco.case.arm.187.3311 i64 188, label %tco.case.arm.188.3334 i64 189, label %tco.case.arm.189.3357 i64 190, label %tco.case.arm.190.3380 i64 191, label %tco.case.arm.191.3403 i64 192, label %tco.case.arm.192.3426 i64 193, label %tco.case.arm.193.3449 i64 194, label %tco.case.arm.194.3472 i64 198, label %tco.case.arm.198.3495 i64 199, label %tco.case.arm.199.3518 i64 200, label %tco.case.arm.200.3541 i64 201, label %tco.case.arm.201.3564 ]
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
  switch i64 %t18, label %tco.case.default.19 [ i64 27, label %tco.case.arm.27.20 i64 28, label %tco.case.arm.28.40 i64 29, label %tco.case.arm.29.60 i64 30, label %tco.case.arm.30.80 i64 31, label %tco.case.arm.31.100 i64 32, label %tco.case.arm.32.120 i64 33, label %tco.case.arm.33.140 i64 34, label %tco.case.arm.34.160 i64 35, label %tco.case.arm.35.180 i64 36, label %tco.case.arm.36.200 i64 37, label %tco.case.arm.37.220 i64 38, label %tco.case.arm.38.240 i64 39, label %tco.case.arm.39.260 i64 40, label %tco.case.arm.40.280 i64 41, label %tco.case.arm.41.300 i64 42, label %tco.case.arm.42.320 i64 43, label %tco.case.arm.43.340 i64 44, label %tco.case.arm.44.360 i64 45, label %tco.case.arm.45.380 i64 46, label %tco.case.arm.46.400 i64 47, label %tco.case.arm.47.420 i64 48, label %tco.case.arm.48.440 i64 49, label %tco.case.arm.49.460 i64 50, label %tco.case.arm.50.480 i64 51, label %tco.case.arm.51.500 i64 52, label %tco.case.arm.52.520 i64 53, label %tco.case.arm.53.540 i64 54, label %tco.case.arm.54.560 i64 55, label %tco.case.arm.55.580 i64 56, label %tco.case.arm.56.600 i64 57, label %tco.case.arm.57.620 i64 58, label %tco.case.arm.58.640 i64 59, label %tco.case.arm.59.660 i64 60, label %tco.case.arm.60.680 i64 61, label %tco.case.arm.61.700 i64 62, label %tco.case.arm.62.711 i64 63, label %tco.case.arm.63.731 i64 64, label %tco.case.arm.64.751 i64 65, label %tco.case.arm.65.771 i64 66, label %tco.case.arm.66.791 i64 67, label %tco.case.arm.67.811 i64 68, label %tco.case.arm.68.831 i64 69, label %tco.case.arm.69.851 i64 70, label %tco.case.arm.70.871 i64 71, label %tco.case.arm.71.891 i64 72, label %tco.case.arm.72.911 i64 73, label %tco.case.arm.73.931 i64 74, label %tco.case.arm.74.951 i64 75, label %tco.case.arm.75.962 i64 76, label %tco.case.arm.76.982 i64 77, label %tco.case.arm.77.1002 i64 78, label %tco.case.arm.78.1022 i64 79, label %tco.case.arm.79.1042 i64 80, label %tco.case.arm.80.1062 i64 81, label %tco.case.arm.81.1082 i64 82, label %tco.case.arm.82.1102 i64 83, label %tco.case.arm.83.1122 i64 84, label %tco.case.arm.84.1142 i64 85, label %tco.case.arm.85.1162 i64 86, label %tco.case.arm.86.1182 i64 87, label %tco.case.arm.87.1202 i64 88, label %tco.case.arm.88.1213 i64 89, label %tco.case.arm.89.1233 i64 90, label %tco.case.arm.90.1253 i64 91, label %tco.case.arm.91.1273 i64 92, label %tco.case.arm.92.1293 i64 93, label %tco.case.arm.93.1313 i64 94, label %tco.case.arm.94.1333 i64 95, label %tco.case.arm.95.1353 i64 96, label %tco.case.arm.96.1373 i64 97, label %tco.case.arm.97.1393 i64 98, label %tco.case.arm.98.1413 i64 99, label %tco.case.arm.99.1433 i64 100, label %tco.case.arm.100.1453 i64 101, label %tco.case.arm.101.1473 i64 102, label %tco.case.arm.102.1493 i64 103, label %tco.case.arm.103.1513 i64 104, label %tco.case.arm.104.1533 i64 105, label %tco.case.arm.105.1553 i64 106, label %tco.case.arm.106.1573 i64 110, label %tco.case.arm.110.1593 i64 111, label %tco.case.arm.111.1613 i64 112, label %tco.case.arm.112.1633 i64 113, label %tco.case.arm.113.1653 ]
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
tco.case.arm.110.1593:
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
  %t1605 = inttoptr i64 198 to ptr
  %t1606 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1605, ptr %t1606
  call void @__inc_ref(ptr %t1595)
  %t1604 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1595, ptr %t1604
  br label %reuse.join.1601
reuse.copy.1600:
  %t1607 = call ptr @__alloc(i64 24, i32 2)
  %t1608 = inttoptr i64 198 to ptr
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
tco.case.arm.111.1613:
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
  %t1625 = inttoptr i64 199 to ptr
  %t1626 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1625, ptr %t1626
  call void @__inc_ref(ptr %t1615)
  %t1624 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1615, ptr %t1624
  br label %reuse.join.1621
reuse.copy.1620:
  %t1627 = call ptr @__alloc(i64 24, i32 2)
  %t1628 = inttoptr i64 199 to ptr
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
tco.case.arm.112.1633:
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
  %t1645 = inttoptr i64 200 to ptr
  %t1646 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1645, ptr %t1646
  call void @__inc_ref(ptr %t1635)
  %t1644 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1635, ptr %t1644
  br label %reuse.join.1641
reuse.copy.1640:
  %t1647 = call ptr @__alloc(i64 24, i32 2)
  %t1648 = inttoptr i64 200 to ptr
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
tco.case.arm.113.1653:
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
  %t1665 = inttoptr i64 201 to ptr
  %t1666 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1665, ptr %t1666
  call void @__inc_ref(ptr %t1655)
  %t1664 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1655, ptr %t1664
  br label %reuse.join.1661
reuse.copy.1660:
  %t1667 = call ptr @__alloc(i64 24, i32 2)
  %t1668 = inttoptr i64 201 to ptr
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
tco.case.default.19:
  unreachable
tco.case.arm.115.1673:
  %t1674 = getelementptr ptr, ptr %t5, i32 1
  %t1675 = load ptr, ptr %t1674
  %t1676 = getelementptr ptr, ptr %t5, i32 2
  %t1677 = load ptr, ptr %t1676
  %t1678 = getelementptr i8, ptr %t5, i64 -8
  %t1679 = load i32, ptr %t1678
  %t1680 = icmp eq i32 %t1679, 1
  br i1 %t1680, label %reuse.in_place.1681, label %reuse.copy.1682
reuse.in_place.1681:
  %t1684 = inttoptr i64 114 to ptr
  %t1685 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1684, ptr %t1685
  br label %reuse.join.1683
reuse.copy.1682:
  %t1686 = call ptr @__alloc(i64 24, i32 2)
  %t1687 = inttoptr i64 114 to ptr
  %t1688 = getelementptr ptr, ptr %t1686, i32 0
  store ptr %t1687, ptr %t1688
  call void @__inc_ref(ptr %t1675)
  %t1689 = getelementptr ptr, ptr %t1686, i32 1
  store ptr %t1675, ptr %t1689
  call void @__inc_ref(ptr %t1677)
  %t1690 = getelementptr ptr, ptr %t1686, i32 2
  store ptr %t1677, ptr %t1690
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1683
reuse.join.1683:
  %t1691 = phi ptr [ %t5, %reuse.in_place.1681 ], [ %t1686, %reuse.copy.1682 ]
  %t1692 = call ptr @__alloc(i64 16, i32 1)
  %t1693 = inttoptr i64 261 to ptr
  %t1694 = getelementptr ptr, ptr %t1692, i32 0
  store ptr %t1693, ptr %t1694
  call void @__inc_ref(ptr %t6)
  %t1695 = getelementptr ptr, ptr %t1692, i32 1
  store ptr %t6, ptr %t1695
  call void @__free_recursive(ptr %t6)
  store ptr %t1691, ptr %t3
  store ptr %t1692, ptr %t4
  br label %tco.loop.0
tco.case.arm.116.1696:
  %t1697 = getelementptr ptr, ptr %t5, i32 1
  %t1698 = load ptr, ptr %t1697
  %t1699 = getelementptr ptr, ptr %t5, i32 2
  %t1700 = load ptr, ptr %t1699
  %t1701 = getelementptr i8, ptr %t5, i64 -8
  %t1702 = load i32, ptr %t1701
  %t1703 = icmp eq i32 %t1702, 1
  br i1 %t1703, label %reuse.in_place.1704, label %reuse.copy.1705
reuse.in_place.1704:
  %t1707 = inttoptr i64 114 to ptr
  %t1708 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1707, ptr %t1708
  br label %reuse.join.1706
reuse.copy.1705:
  %t1709 = call ptr @__alloc(i64 24, i32 2)
  %t1710 = inttoptr i64 114 to ptr
  %t1711 = getelementptr ptr, ptr %t1709, i32 0
  store ptr %t1710, ptr %t1711
  call void @__inc_ref(ptr %t1698)
  %t1712 = getelementptr ptr, ptr %t1709, i32 1
  store ptr %t1698, ptr %t1712
  call void @__inc_ref(ptr %t1700)
  %t1713 = getelementptr ptr, ptr %t1709, i32 2
  store ptr %t1700, ptr %t1713
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1706
reuse.join.1706:
  %t1714 = phi ptr [ %t5, %reuse.in_place.1704 ], [ %t1709, %reuse.copy.1705 ]
  %t1715 = call ptr @__alloc(i64 16, i32 1)
  %t1716 = inttoptr i64 262 to ptr
  %t1717 = getelementptr ptr, ptr %t1715, i32 0
  store ptr %t1716, ptr %t1717
  call void @__inc_ref(ptr %t6)
  %t1718 = getelementptr ptr, ptr %t1715, i32 1
  store ptr %t6, ptr %t1718
  call void @__free_recursive(ptr %t6)
  store ptr %t1714, ptr %t3
  store ptr %t1715, ptr %t4
  br label %tco.loop.0
tco.case.arm.117.1719:
  %t1720 = getelementptr ptr, ptr %t5, i32 1
  %t1721 = load ptr, ptr %t1720
  %t1722 = getelementptr ptr, ptr %t5, i32 2
  %t1723 = load ptr, ptr %t1722
  %t1724 = getelementptr i8, ptr %t5, i64 -8
  %t1725 = load i32, ptr %t1724
  %t1726 = icmp eq i32 %t1725, 1
  br i1 %t1726, label %reuse.in_place.1727, label %reuse.copy.1728
reuse.in_place.1727:
  %t1730 = inttoptr i64 114 to ptr
  %t1731 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1730, ptr %t1731
  br label %reuse.join.1729
reuse.copy.1728:
  %t1732 = call ptr @__alloc(i64 24, i32 2)
  %t1733 = inttoptr i64 114 to ptr
  %t1734 = getelementptr ptr, ptr %t1732, i32 0
  store ptr %t1733, ptr %t1734
  call void @__inc_ref(ptr %t1721)
  %t1735 = getelementptr ptr, ptr %t1732, i32 1
  store ptr %t1721, ptr %t1735
  call void @__inc_ref(ptr %t1723)
  %t1736 = getelementptr ptr, ptr %t1732, i32 2
  store ptr %t1723, ptr %t1736
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1729
reuse.join.1729:
  %t1737 = phi ptr [ %t5, %reuse.in_place.1727 ], [ %t1732, %reuse.copy.1728 ]
  %t1738 = call ptr @__alloc(i64 16, i32 1)
  %t1739 = inttoptr i64 263 to ptr
  %t1740 = getelementptr ptr, ptr %t1738, i32 0
  store ptr %t1739, ptr %t1740
  call void @__inc_ref(ptr %t6)
  %t1741 = getelementptr ptr, ptr %t1738, i32 1
  store ptr %t6, ptr %t1741
  call void @__free_recursive(ptr %t6)
  store ptr %t1737, ptr %t3
  store ptr %t1738, ptr %t4
  br label %tco.loop.0
tco.case.arm.118.1742:
  %t1743 = getelementptr ptr, ptr %t5, i32 1
  %t1744 = load ptr, ptr %t1743
  %t1745 = getelementptr ptr, ptr %t5, i32 2
  %t1746 = load ptr, ptr %t1745
  %t1747 = getelementptr i8, ptr %t5, i64 -8
  %t1748 = load i32, ptr %t1747
  %t1749 = icmp eq i32 %t1748, 1
  br i1 %t1749, label %reuse.in_place.1750, label %reuse.copy.1751
reuse.in_place.1750:
  %t1753 = inttoptr i64 114 to ptr
  %t1754 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1753, ptr %t1754
  br label %reuse.join.1752
reuse.copy.1751:
  %t1755 = call ptr @__alloc(i64 24, i32 2)
  %t1756 = inttoptr i64 114 to ptr
  %t1757 = getelementptr ptr, ptr %t1755, i32 0
  store ptr %t1756, ptr %t1757
  call void @__inc_ref(ptr %t1744)
  %t1758 = getelementptr ptr, ptr %t1755, i32 1
  store ptr %t1744, ptr %t1758
  call void @__inc_ref(ptr %t1746)
  %t1759 = getelementptr ptr, ptr %t1755, i32 2
  store ptr %t1746, ptr %t1759
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1752
reuse.join.1752:
  %t1760 = phi ptr [ %t5, %reuse.in_place.1750 ], [ %t1755, %reuse.copy.1751 ]
  %t1761 = call ptr @__alloc(i64 16, i32 1)
  %t1762 = inttoptr i64 264 to ptr
  %t1763 = getelementptr ptr, ptr %t1761, i32 0
  store ptr %t1762, ptr %t1763
  call void @__inc_ref(ptr %t6)
  %t1764 = getelementptr ptr, ptr %t1761, i32 1
  store ptr %t6, ptr %t1764
  call void @__free_recursive(ptr %t6)
  store ptr %t1760, ptr %t3
  store ptr %t1761, ptr %t4
  br label %tco.loop.0
tco.case.arm.119.1765:
  %t1766 = getelementptr ptr, ptr %t5, i32 1
  %t1767 = load ptr, ptr %t1766
  %t1768 = getelementptr ptr, ptr %t5, i32 2
  %t1769 = load ptr, ptr %t1768
  %t1770 = getelementptr i8, ptr %t5, i64 -8
  %t1771 = load i32, ptr %t1770
  %t1772 = icmp eq i32 %t1771, 1
  br i1 %t1772, label %reuse.in_place.1773, label %reuse.copy.1774
reuse.in_place.1773:
  %t1776 = inttoptr i64 114 to ptr
  %t1777 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1776, ptr %t1777
  br label %reuse.join.1775
reuse.copy.1774:
  %t1778 = call ptr @__alloc(i64 24, i32 2)
  %t1779 = inttoptr i64 114 to ptr
  %t1780 = getelementptr ptr, ptr %t1778, i32 0
  store ptr %t1779, ptr %t1780
  call void @__inc_ref(ptr %t1767)
  %t1781 = getelementptr ptr, ptr %t1778, i32 1
  store ptr %t1767, ptr %t1781
  call void @__inc_ref(ptr %t1769)
  %t1782 = getelementptr ptr, ptr %t1778, i32 2
  store ptr %t1769, ptr %t1782
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1775
reuse.join.1775:
  %t1783 = phi ptr [ %t5, %reuse.in_place.1773 ], [ %t1778, %reuse.copy.1774 ]
  %t1784 = call ptr @__alloc(i64 16, i32 1)
  %t1785 = inttoptr i64 265 to ptr
  %t1786 = getelementptr ptr, ptr %t1784, i32 0
  store ptr %t1785, ptr %t1786
  call void @__inc_ref(ptr %t6)
  %t1787 = getelementptr ptr, ptr %t1784, i32 1
  store ptr %t6, ptr %t1787
  call void @__free_recursive(ptr %t6)
  store ptr %t1783, ptr %t3
  store ptr %t1784, ptr %t4
  br label %tco.loop.0
tco.case.arm.120.1788:
  %t1789 = getelementptr ptr, ptr %t5, i32 1
  %t1790 = load ptr, ptr %t1789
  %t1791 = getelementptr ptr, ptr %t5, i32 2
  %t1792 = load ptr, ptr %t1791
  %t1793 = getelementptr i8, ptr %t5, i64 -8
  %t1794 = load i32, ptr %t1793
  %t1795 = icmp eq i32 %t1794, 1
  br i1 %t1795, label %reuse.in_place.1796, label %reuse.copy.1797
reuse.in_place.1796:
  %t1799 = inttoptr i64 114 to ptr
  %t1800 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1799, ptr %t1800
  br label %reuse.join.1798
reuse.copy.1797:
  %t1801 = call ptr @__alloc(i64 24, i32 2)
  %t1802 = inttoptr i64 114 to ptr
  %t1803 = getelementptr ptr, ptr %t1801, i32 0
  store ptr %t1802, ptr %t1803
  call void @__inc_ref(ptr %t1790)
  %t1804 = getelementptr ptr, ptr %t1801, i32 1
  store ptr %t1790, ptr %t1804
  call void @__inc_ref(ptr %t1792)
  %t1805 = getelementptr ptr, ptr %t1801, i32 2
  store ptr %t1792, ptr %t1805
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1798
reuse.join.1798:
  %t1806 = phi ptr [ %t5, %reuse.in_place.1796 ], [ %t1801, %reuse.copy.1797 ]
  %t1807 = call ptr @__alloc(i64 16, i32 1)
  %t1808 = inttoptr i64 266 to ptr
  %t1809 = getelementptr ptr, ptr %t1807, i32 0
  store ptr %t1808, ptr %t1809
  call void @__inc_ref(ptr %t6)
  %t1810 = getelementptr ptr, ptr %t1807, i32 1
  store ptr %t6, ptr %t1810
  call void @__free_recursive(ptr %t6)
  store ptr %t1806, ptr %t3
  store ptr %t1807, ptr %t4
  br label %tco.loop.0
tco.case.arm.121.1811:
  %t1812 = getelementptr ptr, ptr %t5, i32 1
  %t1813 = load ptr, ptr %t1812
  %t1814 = getelementptr ptr, ptr %t5, i32 2
  %t1815 = load ptr, ptr %t1814
  %t1816 = getelementptr i8, ptr %t5, i64 -8
  %t1817 = load i32, ptr %t1816
  %t1818 = icmp eq i32 %t1817, 1
  br i1 %t1818, label %reuse.in_place.1819, label %reuse.copy.1820
reuse.in_place.1819:
  %t1822 = inttoptr i64 114 to ptr
  %t1823 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1822, ptr %t1823
  br label %reuse.join.1821
reuse.copy.1820:
  %t1824 = call ptr @__alloc(i64 24, i32 2)
  %t1825 = inttoptr i64 114 to ptr
  %t1826 = getelementptr ptr, ptr %t1824, i32 0
  store ptr %t1825, ptr %t1826
  call void @__inc_ref(ptr %t1813)
  %t1827 = getelementptr ptr, ptr %t1824, i32 1
  store ptr %t1813, ptr %t1827
  call void @__inc_ref(ptr %t1815)
  %t1828 = getelementptr ptr, ptr %t1824, i32 2
  store ptr %t1815, ptr %t1828
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1821
reuse.join.1821:
  %t1829 = phi ptr [ %t5, %reuse.in_place.1819 ], [ %t1824, %reuse.copy.1820 ]
  %t1830 = call ptr @__alloc(i64 16, i32 1)
  %t1831 = inttoptr i64 267 to ptr
  %t1832 = getelementptr ptr, ptr %t1830, i32 0
  store ptr %t1831, ptr %t1832
  call void @__inc_ref(ptr %t6)
  %t1833 = getelementptr ptr, ptr %t1830, i32 1
  store ptr %t6, ptr %t1833
  call void @__free_recursive(ptr %t6)
  store ptr %t1829, ptr %t3
  store ptr %t1830, ptr %t4
  br label %tco.loop.0
tco.case.arm.122.1834:
  %t1835 = getelementptr ptr, ptr %t5, i32 1
  %t1836 = load ptr, ptr %t1835
  %t1837 = getelementptr ptr, ptr %t5, i32 2
  %t1838 = load ptr, ptr %t1837
  %t1839 = getelementptr i8, ptr %t5, i64 -8
  %t1840 = load i32, ptr %t1839
  %t1841 = icmp eq i32 %t1840, 1
  br i1 %t1841, label %reuse.in_place.1842, label %reuse.copy.1843
reuse.in_place.1842:
  %t1845 = inttoptr i64 114 to ptr
  %t1846 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1845, ptr %t1846
  br label %reuse.join.1844
reuse.copy.1843:
  %t1847 = call ptr @__alloc(i64 24, i32 2)
  %t1848 = inttoptr i64 114 to ptr
  %t1849 = getelementptr ptr, ptr %t1847, i32 0
  store ptr %t1848, ptr %t1849
  call void @__inc_ref(ptr %t1836)
  %t1850 = getelementptr ptr, ptr %t1847, i32 1
  store ptr %t1836, ptr %t1850
  call void @__inc_ref(ptr %t1838)
  %t1851 = getelementptr ptr, ptr %t1847, i32 2
  store ptr %t1838, ptr %t1851
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1844
reuse.join.1844:
  %t1852 = phi ptr [ %t5, %reuse.in_place.1842 ], [ %t1847, %reuse.copy.1843 ]
  %t1853 = call ptr @__alloc(i64 16, i32 1)
  %t1854 = inttoptr i64 268 to ptr
  %t1855 = getelementptr ptr, ptr %t1853, i32 0
  store ptr %t1854, ptr %t1855
  call void @__inc_ref(ptr %t6)
  %t1856 = getelementptr ptr, ptr %t1853, i32 1
  store ptr %t6, ptr %t1856
  call void @__free_recursive(ptr %t6)
  store ptr %t1852, ptr %t3
  store ptr %t1853, ptr %t4
  br label %tco.loop.0
tco.case.arm.123.1857:
  %t1858 = getelementptr ptr, ptr %t5, i32 1
  %t1859 = load ptr, ptr %t1858
  %t1860 = getelementptr ptr, ptr %t5, i32 2
  %t1861 = load ptr, ptr %t1860
  %t1862 = getelementptr i8, ptr %t5, i64 -8
  %t1863 = load i32, ptr %t1862
  %t1864 = icmp eq i32 %t1863, 1
  br i1 %t1864, label %reuse.in_place.1865, label %reuse.copy.1866
reuse.in_place.1865:
  %t1868 = inttoptr i64 114 to ptr
  %t1869 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1868, ptr %t1869
  br label %reuse.join.1867
reuse.copy.1866:
  %t1870 = call ptr @__alloc(i64 24, i32 2)
  %t1871 = inttoptr i64 114 to ptr
  %t1872 = getelementptr ptr, ptr %t1870, i32 0
  store ptr %t1871, ptr %t1872
  call void @__inc_ref(ptr %t1859)
  %t1873 = getelementptr ptr, ptr %t1870, i32 1
  store ptr %t1859, ptr %t1873
  call void @__inc_ref(ptr %t1861)
  %t1874 = getelementptr ptr, ptr %t1870, i32 2
  store ptr %t1861, ptr %t1874
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1867
reuse.join.1867:
  %t1875 = phi ptr [ %t5, %reuse.in_place.1865 ], [ %t1870, %reuse.copy.1866 ]
  %t1876 = call ptr @__alloc(i64 16, i32 1)
  %t1877 = inttoptr i64 269 to ptr
  %t1878 = getelementptr ptr, ptr %t1876, i32 0
  store ptr %t1877, ptr %t1878
  call void @__inc_ref(ptr %t6)
  %t1879 = getelementptr ptr, ptr %t1876, i32 1
  store ptr %t6, ptr %t1879
  call void @__free_recursive(ptr %t6)
  store ptr %t1875, ptr %t3
  store ptr %t1876, ptr %t4
  br label %tco.loop.0
tco.case.arm.124.1880:
  %t1881 = getelementptr ptr, ptr %t5, i32 1
  %t1882 = load ptr, ptr %t1881
  %t1883 = getelementptr ptr, ptr %t5, i32 2
  %t1884 = load ptr, ptr %t1883
  %t1885 = getelementptr i8, ptr %t5, i64 -8
  %t1886 = load i32, ptr %t1885
  %t1887 = icmp eq i32 %t1886, 1
  br i1 %t1887, label %reuse.in_place.1888, label %reuse.copy.1889
reuse.in_place.1888:
  %t1891 = inttoptr i64 114 to ptr
  %t1892 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1891, ptr %t1892
  br label %reuse.join.1890
reuse.copy.1889:
  %t1893 = call ptr @__alloc(i64 24, i32 2)
  %t1894 = inttoptr i64 114 to ptr
  %t1895 = getelementptr ptr, ptr %t1893, i32 0
  store ptr %t1894, ptr %t1895
  call void @__inc_ref(ptr %t1882)
  %t1896 = getelementptr ptr, ptr %t1893, i32 1
  store ptr %t1882, ptr %t1896
  call void @__inc_ref(ptr %t1884)
  %t1897 = getelementptr ptr, ptr %t1893, i32 2
  store ptr %t1884, ptr %t1897
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1890
reuse.join.1890:
  %t1898 = phi ptr [ %t5, %reuse.in_place.1888 ], [ %t1893, %reuse.copy.1889 ]
  %t1899 = call ptr @__alloc(i64 16, i32 1)
  %t1900 = inttoptr i64 270 to ptr
  %t1901 = getelementptr ptr, ptr %t1899, i32 0
  store ptr %t1900, ptr %t1901
  call void @__inc_ref(ptr %t6)
  %t1902 = getelementptr ptr, ptr %t1899, i32 1
  store ptr %t6, ptr %t1902
  call void @__free_recursive(ptr %t6)
  store ptr %t1898, ptr %t3
  store ptr %t1899, ptr %t4
  br label %tco.loop.0
tco.case.arm.125.1903:
  %t1904 = getelementptr ptr, ptr %t5, i32 1
  %t1905 = load ptr, ptr %t1904
  %t1906 = getelementptr ptr, ptr %t5, i32 2
  %t1907 = load ptr, ptr %t1906
  %t1908 = getelementptr i8, ptr %t5, i64 -8
  %t1909 = load i32, ptr %t1908
  %t1910 = icmp eq i32 %t1909, 1
  br i1 %t1910, label %reuse.in_place.1911, label %reuse.copy.1912
reuse.in_place.1911:
  %t1914 = inttoptr i64 114 to ptr
  %t1915 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1914, ptr %t1915
  br label %reuse.join.1913
reuse.copy.1912:
  %t1916 = call ptr @__alloc(i64 24, i32 2)
  %t1917 = inttoptr i64 114 to ptr
  %t1918 = getelementptr ptr, ptr %t1916, i32 0
  store ptr %t1917, ptr %t1918
  call void @__inc_ref(ptr %t1905)
  %t1919 = getelementptr ptr, ptr %t1916, i32 1
  store ptr %t1905, ptr %t1919
  call void @__inc_ref(ptr %t1907)
  %t1920 = getelementptr ptr, ptr %t1916, i32 2
  store ptr %t1907, ptr %t1920
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1913
reuse.join.1913:
  %t1921 = phi ptr [ %t5, %reuse.in_place.1911 ], [ %t1916, %reuse.copy.1912 ]
  %t1922 = call ptr @__alloc(i64 16, i32 1)
  %t1923 = inttoptr i64 271 to ptr
  %t1924 = getelementptr ptr, ptr %t1922, i32 0
  store ptr %t1923, ptr %t1924
  call void @__inc_ref(ptr %t6)
  %t1925 = getelementptr ptr, ptr %t1922, i32 1
  store ptr %t6, ptr %t1925
  call void @__free_recursive(ptr %t6)
  store ptr %t1921, ptr %t3
  store ptr %t1922, ptr %t4
  br label %tco.loop.0
tco.case.arm.126.1926:
  %t1927 = getelementptr ptr, ptr %t5, i32 1
  %t1928 = load ptr, ptr %t1927
  %t1929 = getelementptr ptr, ptr %t5, i32 2
  %t1930 = load ptr, ptr %t1929
  %t1931 = getelementptr i8, ptr %t5, i64 -8
  %t1932 = load i32, ptr %t1931
  %t1933 = icmp eq i32 %t1932, 1
  br i1 %t1933, label %reuse.in_place.1934, label %reuse.copy.1935
reuse.in_place.1934:
  %t1937 = inttoptr i64 114 to ptr
  %t1938 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1937, ptr %t1938
  br label %reuse.join.1936
reuse.copy.1935:
  %t1939 = call ptr @__alloc(i64 24, i32 2)
  %t1940 = inttoptr i64 114 to ptr
  %t1941 = getelementptr ptr, ptr %t1939, i32 0
  store ptr %t1940, ptr %t1941
  call void @__inc_ref(ptr %t1928)
  %t1942 = getelementptr ptr, ptr %t1939, i32 1
  store ptr %t1928, ptr %t1942
  call void @__inc_ref(ptr %t1930)
  %t1943 = getelementptr ptr, ptr %t1939, i32 2
  store ptr %t1930, ptr %t1943
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1936
reuse.join.1936:
  %t1944 = phi ptr [ %t5, %reuse.in_place.1934 ], [ %t1939, %reuse.copy.1935 ]
  %t1945 = call ptr @__alloc(i64 16, i32 1)
  %t1946 = inttoptr i64 272 to ptr
  %t1947 = getelementptr ptr, ptr %t1945, i32 0
  store ptr %t1946, ptr %t1947
  call void @__inc_ref(ptr %t6)
  %t1948 = getelementptr ptr, ptr %t1945, i32 1
  store ptr %t6, ptr %t1948
  call void @__free_recursive(ptr %t6)
  store ptr %t1944, ptr %t3
  store ptr %t1945, ptr %t4
  br label %tco.loop.0
tco.case.arm.127.1949:
  %t1950 = getelementptr ptr, ptr %t5, i32 1
  %t1951 = load ptr, ptr %t1950
  %t1952 = getelementptr ptr, ptr %t5, i32 2
  %t1953 = load ptr, ptr %t1952
  %t1954 = getelementptr i8, ptr %t5, i64 -8
  %t1955 = load i32, ptr %t1954
  %t1956 = icmp eq i32 %t1955, 1
  br i1 %t1956, label %reuse.in_place.1957, label %reuse.copy.1958
reuse.in_place.1957:
  %t1960 = inttoptr i64 114 to ptr
  %t1961 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1960, ptr %t1961
  br label %reuse.join.1959
reuse.copy.1958:
  %t1962 = call ptr @__alloc(i64 24, i32 2)
  %t1963 = inttoptr i64 114 to ptr
  %t1964 = getelementptr ptr, ptr %t1962, i32 0
  store ptr %t1963, ptr %t1964
  call void @__inc_ref(ptr %t1951)
  %t1965 = getelementptr ptr, ptr %t1962, i32 1
  store ptr %t1951, ptr %t1965
  call void @__inc_ref(ptr %t1953)
  %t1966 = getelementptr ptr, ptr %t1962, i32 2
  store ptr %t1953, ptr %t1966
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1959
reuse.join.1959:
  %t1967 = phi ptr [ %t5, %reuse.in_place.1957 ], [ %t1962, %reuse.copy.1958 ]
  %t1968 = call ptr @__alloc(i64 16, i32 1)
  %t1969 = inttoptr i64 273 to ptr
  %t1970 = getelementptr ptr, ptr %t1968, i32 0
  store ptr %t1969, ptr %t1970
  call void @__inc_ref(ptr %t6)
  %t1971 = getelementptr ptr, ptr %t1968, i32 1
  store ptr %t6, ptr %t1971
  call void @__free_recursive(ptr %t6)
  store ptr %t1967, ptr %t3
  store ptr %t1968, ptr %t4
  br label %tco.loop.0
tco.case.arm.128.1972:
  %t1973 = getelementptr ptr, ptr %t5, i32 1
  %t1974 = load ptr, ptr %t1973
  %t1975 = getelementptr ptr, ptr %t5, i32 2
  %t1976 = load ptr, ptr %t1975
  %t1977 = getelementptr i8, ptr %t5, i64 -8
  %t1978 = load i32, ptr %t1977
  %t1979 = icmp eq i32 %t1978, 1
  br i1 %t1979, label %reuse.in_place.1980, label %reuse.copy.1981
reuse.in_place.1980:
  %t1983 = inttoptr i64 114 to ptr
  %t1984 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1983, ptr %t1984
  br label %reuse.join.1982
reuse.copy.1981:
  %t1985 = call ptr @__alloc(i64 24, i32 2)
  %t1986 = inttoptr i64 114 to ptr
  %t1987 = getelementptr ptr, ptr %t1985, i32 0
  store ptr %t1986, ptr %t1987
  call void @__inc_ref(ptr %t1974)
  %t1988 = getelementptr ptr, ptr %t1985, i32 1
  store ptr %t1974, ptr %t1988
  call void @__inc_ref(ptr %t1976)
  %t1989 = getelementptr ptr, ptr %t1985, i32 2
  store ptr %t1976, ptr %t1989
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1982
reuse.join.1982:
  %t1990 = phi ptr [ %t5, %reuse.in_place.1980 ], [ %t1985, %reuse.copy.1981 ]
  %t1991 = call ptr @__alloc(i64 16, i32 1)
  %t1992 = inttoptr i64 274 to ptr
  %t1993 = getelementptr ptr, ptr %t1991, i32 0
  store ptr %t1992, ptr %t1993
  call void @__inc_ref(ptr %t6)
  %t1994 = getelementptr ptr, ptr %t1991, i32 1
  store ptr %t6, ptr %t1994
  call void @__free_recursive(ptr %t6)
  store ptr %t1990, ptr %t3
  store ptr %t1991, ptr %t4
  br label %tco.loop.0
tco.case.arm.129.1995:
  %t1996 = getelementptr ptr, ptr %t5, i32 1
  %t1997 = load ptr, ptr %t1996
  %t1998 = getelementptr ptr, ptr %t5, i32 2
  %t1999 = load ptr, ptr %t1998
  %t2000 = getelementptr i8, ptr %t5, i64 -8
  %t2001 = load i32, ptr %t2000
  %t2002 = icmp eq i32 %t2001, 1
  br i1 %t2002, label %reuse.in_place.2003, label %reuse.copy.2004
reuse.in_place.2003:
  %t2006 = inttoptr i64 114 to ptr
  %t2007 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2006, ptr %t2007
  br label %reuse.join.2005
reuse.copy.2004:
  %t2008 = call ptr @__alloc(i64 24, i32 2)
  %t2009 = inttoptr i64 114 to ptr
  %t2010 = getelementptr ptr, ptr %t2008, i32 0
  store ptr %t2009, ptr %t2010
  call void @__inc_ref(ptr %t1997)
  %t2011 = getelementptr ptr, ptr %t2008, i32 1
  store ptr %t1997, ptr %t2011
  call void @__inc_ref(ptr %t1999)
  %t2012 = getelementptr ptr, ptr %t2008, i32 2
  store ptr %t1999, ptr %t2012
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2005
reuse.join.2005:
  %t2013 = phi ptr [ %t5, %reuse.in_place.2003 ], [ %t2008, %reuse.copy.2004 ]
  %t2014 = call ptr @__alloc(i64 16, i32 1)
  %t2015 = inttoptr i64 275 to ptr
  %t2016 = getelementptr ptr, ptr %t2014, i32 0
  store ptr %t2015, ptr %t2016
  call void @__inc_ref(ptr %t6)
  %t2017 = getelementptr ptr, ptr %t2014, i32 1
  store ptr %t6, ptr %t2017
  call void @__free_recursive(ptr %t6)
  store ptr %t2013, ptr %t3
  store ptr %t2014, ptr %t4
  br label %tco.loop.0
tco.case.arm.130.2018:
  %t2019 = getelementptr ptr, ptr %t5, i32 1
  %t2020 = load ptr, ptr %t2019
  %t2021 = getelementptr ptr, ptr %t5, i32 2
  %t2022 = load ptr, ptr %t2021
  %t2023 = getelementptr i8, ptr %t5, i64 -8
  %t2024 = load i32, ptr %t2023
  %t2025 = icmp eq i32 %t2024, 1
  br i1 %t2025, label %reuse.in_place.2026, label %reuse.copy.2027
reuse.in_place.2026:
  %t2029 = inttoptr i64 114 to ptr
  %t2030 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2029, ptr %t2030
  br label %reuse.join.2028
reuse.copy.2027:
  %t2031 = call ptr @__alloc(i64 24, i32 2)
  %t2032 = inttoptr i64 114 to ptr
  %t2033 = getelementptr ptr, ptr %t2031, i32 0
  store ptr %t2032, ptr %t2033
  call void @__inc_ref(ptr %t2020)
  %t2034 = getelementptr ptr, ptr %t2031, i32 1
  store ptr %t2020, ptr %t2034
  call void @__inc_ref(ptr %t2022)
  %t2035 = getelementptr ptr, ptr %t2031, i32 2
  store ptr %t2022, ptr %t2035
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2028
reuse.join.2028:
  %t2036 = phi ptr [ %t5, %reuse.in_place.2026 ], [ %t2031, %reuse.copy.2027 ]
  %t2037 = call ptr @__alloc(i64 16, i32 1)
  %t2038 = inttoptr i64 276 to ptr
  %t2039 = getelementptr ptr, ptr %t2037, i32 0
  store ptr %t2038, ptr %t2039
  call void @__inc_ref(ptr %t6)
  %t2040 = getelementptr ptr, ptr %t2037, i32 1
  store ptr %t6, ptr %t2040
  call void @__free_recursive(ptr %t6)
  store ptr %t2036, ptr %t3
  store ptr %t2037, ptr %t4
  br label %tco.loop.0
tco.case.arm.131.2041:
  %t2042 = getelementptr ptr, ptr %t5, i32 1
  %t2043 = load ptr, ptr %t2042
  %t2044 = getelementptr ptr, ptr %t5, i32 2
  %t2045 = load ptr, ptr %t2044
  %t2046 = getelementptr i8, ptr %t5, i64 -8
  %t2047 = load i32, ptr %t2046
  %t2048 = icmp eq i32 %t2047, 1
  br i1 %t2048, label %reuse.in_place.2049, label %reuse.copy.2050
reuse.in_place.2049:
  %t2052 = inttoptr i64 114 to ptr
  %t2053 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2052, ptr %t2053
  br label %reuse.join.2051
reuse.copy.2050:
  %t2054 = call ptr @__alloc(i64 24, i32 2)
  %t2055 = inttoptr i64 114 to ptr
  %t2056 = getelementptr ptr, ptr %t2054, i32 0
  store ptr %t2055, ptr %t2056
  call void @__inc_ref(ptr %t2043)
  %t2057 = getelementptr ptr, ptr %t2054, i32 1
  store ptr %t2043, ptr %t2057
  call void @__inc_ref(ptr %t2045)
  %t2058 = getelementptr ptr, ptr %t2054, i32 2
  store ptr %t2045, ptr %t2058
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2051
reuse.join.2051:
  %t2059 = phi ptr [ %t5, %reuse.in_place.2049 ], [ %t2054, %reuse.copy.2050 ]
  %t2060 = call ptr @__alloc(i64 16, i32 1)
  %t2061 = inttoptr i64 277 to ptr
  %t2062 = getelementptr ptr, ptr %t2060, i32 0
  store ptr %t2061, ptr %t2062
  call void @__inc_ref(ptr %t6)
  %t2063 = getelementptr ptr, ptr %t2060, i32 1
  store ptr %t6, ptr %t2063
  call void @__free_recursive(ptr %t6)
  store ptr %t2059, ptr %t3
  store ptr %t2060, ptr %t4
  br label %tco.loop.0
tco.case.arm.132.2064:
  %t2065 = getelementptr ptr, ptr %t5, i32 1
  %t2066 = load ptr, ptr %t2065
  %t2067 = getelementptr ptr, ptr %t5, i32 2
  %t2068 = load ptr, ptr %t2067
  %t2069 = getelementptr i8, ptr %t5, i64 -8
  %t2070 = load i32, ptr %t2069
  %t2071 = icmp eq i32 %t2070, 1
  br i1 %t2071, label %reuse.in_place.2072, label %reuse.copy.2073
reuse.in_place.2072:
  %t2075 = inttoptr i64 114 to ptr
  %t2076 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2075, ptr %t2076
  br label %reuse.join.2074
reuse.copy.2073:
  %t2077 = call ptr @__alloc(i64 24, i32 2)
  %t2078 = inttoptr i64 114 to ptr
  %t2079 = getelementptr ptr, ptr %t2077, i32 0
  store ptr %t2078, ptr %t2079
  call void @__inc_ref(ptr %t2066)
  %t2080 = getelementptr ptr, ptr %t2077, i32 1
  store ptr %t2066, ptr %t2080
  call void @__inc_ref(ptr %t2068)
  %t2081 = getelementptr ptr, ptr %t2077, i32 2
  store ptr %t2068, ptr %t2081
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2074
reuse.join.2074:
  %t2082 = phi ptr [ %t5, %reuse.in_place.2072 ], [ %t2077, %reuse.copy.2073 ]
  %t2083 = call ptr @__alloc(i64 16, i32 1)
  %t2084 = inttoptr i64 278 to ptr
  %t2085 = getelementptr ptr, ptr %t2083, i32 0
  store ptr %t2084, ptr %t2085
  call void @__inc_ref(ptr %t6)
  %t2086 = getelementptr ptr, ptr %t2083, i32 1
  store ptr %t6, ptr %t2086
  call void @__free_recursive(ptr %t6)
  store ptr %t2082, ptr %t3
  store ptr %t2083, ptr %t4
  br label %tco.loop.0
tco.case.arm.133.2087:
  %t2088 = getelementptr ptr, ptr %t5, i32 1
  %t2089 = load ptr, ptr %t2088
  %t2090 = getelementptr ptr, ptr %t5, i32 2
  %t2091 = load ptr, ptr %t2090
  %t2092 = getelementptr i8, ptr %t5, i64 -8
  %t2093 = load i32, ptr %t2092
  %t2094 = icmp eq i32 %t2093, 1
  br i1 %t2094, label %reuse.in_place.2095, label %reuse.copy.2096
reuse.in_place.2095:
  %t2098 = inttoptr i64 114 to ptr
  %t2099 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2098, ptr %t2099
  br label %reuse.join.2097
reuse.copy.2096:
  %t2100 = call ptr @__alloc(i64 24, i32 2)
  %t2101 = inttoptr i64 114 to ptr
  %t2102 = getelementptr ptr, ptr %t2100, i32 0
  store ptr %t2101, ptr %t2102
  call void @__inc_ref(ptr %t2089)
  %t2103 = getelementptr ptr, ptr %t2100, i32 1
  store ptr %t2089, ptr %t2103
  call void @__inc_ref(ptr %t2091)
  %t2104 = getelementptr ptr, ptr %t2100, i32 2
  store ptr %t2091, ptr %t2104
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2097
reuse.join.2097:
  %t2105 = phi ptr [ %t5, %reuse.in_place.2095 ], [ %t2100, %reuse.copy.2096 ]
  %t2106 = call ptr @__alloc(i64 16, i32 1)
  %t2107 = inttoptr i64 279 to ptr
  %t2108 = getelementptr ptr, ptr %t2106, i32 0
  store ptr %t2107, ptr %t2108
  call void @__inc_ref(ptr %t6)
  %t2109 = getelementptr ptr, ptr %t2106, i32 1
  store ptr %t6, ptr %t2109
  call void @__free_recursive(ptr %t6)
  store ptr %t2105, ptr %t3
  store ptr %t2106, ptr %t4
  br label %tco.loop.0
tco.case.arm.134.2110:
  %t2111 = getelementptr ptr, ptr %t5, i32 1
  %t2112 = load ptr, ptr %t2111
  %t2113 = getelementptr ptr, ptr %t5, i32 2
  %t2114 = load ptr, ptr %t2113
  %t2115 = getelementptr i8, ptr %t5, i64 -8
  %t2116 = load i32, ptr %t2115
  %t2117 = icmp eq i32 %t2116, 1
  br i1 %t2117, label %reuse.in_place.2118, label %reuse.copy.2119
reuse.in_place.2118:
  %t2121 = inttoptr i64 114 to ptr
  %t2122 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2121, ptr %t2122
  br label %reuse.join.2120
reuse.copy.2119:
  %t2123 = call ptr @__alloc(i64 24, i32 2)
  %t2124 = inttoptr i64 114 to ptr
  %t2125 = getelementptr ptr, ptr %t2123, i32 0
  store ptr %t2124, ptr %t2125
  call void @__inc_ref(ptr %t2112)
  %t2126 = getelementptr ptr, ptr %t2123, i32 1
  store ptr %t2112, ptr %t2126
  call void @__inc_ref(ptr %t2114)
  %t2127 = getelementptr ptr, ptr %t2123, i32 2
  store ptr %t2114, ptr %t2127
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2120
reuse.join.2120:
  %t2128 = phi ptr [ %t5, %reuse.in_place.2118 ], [ %t2123, %reuse.copy.2119 ]
  %t2129 = call ptr @__alloc(i64 16, i32 1)
  %t2130 = inttoptr i64 280 to ptr
  %t2131 = getelementptr ptr, ptr %t2129, i32 0
  store ptr %t2130, ptr %t2131
  call void @__inc_ref(ptr %t6)
  %t2132 = getelementptr ptr, ptr %t2129, i32 1
  store ptr %t6, ptr %t2132
  call void @__free_recursive(ptr %t6)
  store ptr %t2128, ptr %t3
  store ptr %t2129, ptr %t4
  br label %tco.loop.0
tco.case.arm.135.2133:
  %t2134 = getelementptr ptr, ptr %t5, i32 1
  %t2135 = load ptr, ptr %t2134
  %t2136 = getelementptr ptr, ptr %t5, i32 2
  %t2137 = load ptr, ptr %t2136
  %t2138 = getelementptr i8, ptr %t5, i64 -8
  %t2139 = load i32, ptr %t2138
  %t2140 = icmp eq i32 %t2139, 1
  br i1 %t2140, label %reuse.in_place.2141, label %reuse.copy.2142
reuse.in_place.2141:
  %t2144 = inttoptr i64 114 to ptr
  %t2145 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2144, ptr %t2145
  br label %reuse.join.2143
reuse.copy.2142:
  %t2146 = call ptr @__alloc(i64 24, i32 2)
  %t2147 = inttoptr i64 114 to ptr
  %t2148 = getelementptr ptr, ptr %t2146, i32 0
  store ptr %t2147, ptr %t2148
  call void @__inc_ref(ptr %t2135)
  %t2149 = getelementptr ptr, ptr %t2146, i32 1
  store ptr %t2135, ptr %t2149
  call void @__inc_ref(ptr %t2137)
  %t2150 = getelementptr ptr, ptr %t2146, i32 2
  store ptr %t2137, ptr %t2150
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2143
reuse.join.2143:
  %t2151 = phi ptr [ %t5, %reuse.in_place.2141 ], [ %t2146, %reuse.copy.2142 ]
  %t2152 = call ptr @__alloc(i64 16, i32 1)
  %t2153 = inttoptr i64 281 to ptr
  %t2154 = getelementptr ptr, ptr %t2152, i32 0
  store ptr %t2153, ptr %t2154
  call void @__inc_ref(ptr %t6)
  %t2155 = getelementptr ptr, ptr %t2152, i32 1
  store ptr %t6, ptr %t2155
  call void @__free_recursive(ptr %t6)
  store ptr %t2151, ptr %t3
  store ptr %t2152, ptr %t4
  br label %tco.loop.0
tco.case.arm.136.2156:
  %t2157 = getelementptr ptr, ptr %t5, i32 1
  %t2158 = load ptr, ptr %t2157
  %t2159 = getelementptr ptr, ptr %t5, i32 2
  %t2160 = load ptr, ptr %t2159
  %t2161 = getelementptr i8, ptr %t5, i64 -8
  %t2162 = load i32, ptr %t2161
  %t2163 = icmp eq i32 %t2162, 1
  br i1 %t2163, label %reuse.in_place.2164, label %reuse.copy.2165
reuse.in_place.2164:
  %t2167 = inttoptr i64 114 to ptr
  %t2168 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2167, ptr %t2168
  br label %reuse.join.2166
reuse.copy.2165:
  %t2169 = call ptr @__alloc(i64 24, i32 2)
  %t2170 = inttoptr i64 114 to ptr
  %t2171 = getelementptr ptr, ptr %t2169, i32 0
  store ptr %t2170, ptr %t2171
  call void @__inc_ref(ptr %t2158)
  %t2172 = getelementptr ptr, ptr %t2169, i32 1
  store ptr %t2158, ptr %t2172
  call void @__inc_ref(ptr %t2160)
  %t2173 = getelementptr ptr, ptr %t2169, i32 2
  store ptr %t2160, ptr %t2173
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2166
reuse.join.2166:
  %t2174 = phi ptr [ %t5, %reuse.in_place.2164 ], [ %t2169, %reuse.copy.2165 ]
  %t2175 = call ptr @__alloc(i64 16, i32 1)
  %t2176 = inttoptr i64 282 to ptr
  %t2177 = getelementptr ptr, ptr %t2175, i32 0
  store ptr %t2176, ptr %t2177
  call void @__inc_ref(ptr %t6)
  %t2178 = getelementptr ptr, ptr %t2175, i32 1
  store ptr %t6, ptr %t2178
  call void @__free_recursive(ptr %t6)
  store ptr %t2174, ptr %t3
  store ptr %t2175, ptr %t4
  br label %tco.loop.0
tco.case.arm.137.2179:
  %t2180 = getelementptr ptr, ptr %t5, i32 1
  %t2181 = load ptr, ptr %t2180
  %t2182 = getelementptr ptr, ptr %t5, i32 2
  %t2183 = load ptr, ptr %t2182
  %t2184 = getelementptr i8, ptr %t5, i64 -8
  %t2185 = load i32, ptr %t2184
  %t2186 = icmp eq i32 %t2185, 1
  br i1 %t2186, label %reuse.in_place.2187, label %reuse.copy.2188
reuse.in_place.2187:
  %t2190 = inttoptr i64 114 to ptr
  %t2191 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2190, ptr %t2191
  br label %reuse.join.2189
reuse.copy.2188:
  %t2192 = call ptr @__alloc(i64 24, i32 2)
  %t2193 = inttoptr i64 114 to ptr
  %t2194 = getelementptr ptr, ptr %t2192, i32 0
  store ptr %t2193, ptr %t2194
  call void @__inc_ref(ptr %t2181)
  %t2195 = getelementptr ptr, ptr %t2192, i32 1
  store ptr %t2181, ptr %t2195
  call void @__inc_ref(ptr %t2183)
  %t2196 = getelementptr ptr, ptr %t2192, i32 2
  store ptr %t2183, ptr %t2196
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2189
reuse.join.2189:
  %t2197 = phi ptr [ %t5, %reuse.in_place.2187 ], [ %t2192, %reuse.copy.2188 ]
  %t2198 = call ptr @__alloc(i64 16, i32 1)
  %t2199 = inttoptr i64 283 to ptr
  %t2200 = getelementptr ptr, ptr %t2198, i32 0
  store ptr %t2199, ptr %t2200
  call void @__inc_ref(ptr %t6)
  %t2201 = getelementptr ptr, ptr %t2198, i32 1
  store ptr %t6, ptr %t2201
  call void @__free_recursive(ptr %t6)
  store ptr %t2197, ptr %t3
  store ptr %t2198, ptr %t4
  br label %tco.loop.0
tco.case.arm.138.2202:
  %t2203 = getelementptr ptr, ptr %t5, i32 1
  %t2204 = load ptr, ptr %t2203
  %t2205 = getelementptr ptr, ptr %t5, i32 2
  %t2206 = load ptr, ptr %t2205
  %t2207 = getelementptr i8, ptr %t5, i64 -8
  %t2208 = load i32, ptr %t2207
  %t2209 = icmp eq i32 %t2208, 1
  br i1 %t2209, label %reuse.in_place.2210, label %reuse.copy.2211
reuse.in_place.2210:
  %t2213 = inttoptr i64 114 to ptr
  %t2214 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2213, ptr %t2214
  br label %reuse.join.2212
reuse.copy.2211:
  %t2215 = call ptr @__alloc(i64 24, i32 2)
  %t2216 = inttoptr i64 114 to ptr
  %t2217 = getelementptr ptr, ptr %t2215, i32 0
  store ptr %t2216, ptr %t2217
  call void @__inc_ref(ptr %t2204)
  %t2218 = getelementptr ptr, ptr %t2215, i32 1
  store ptr %t2204, ptr %t2218
  call void @__inc_ref(ptr %t2206)
  %t2219 = getelementptr ptr, ptr %t2215, i32 2
  store ptr %t2206, ptr %t2219
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2212
reuse.join.2212:
  %t2220 = phi ptr [ %t5, %reuse.in_place.2210 ], [ %t2215, %reuse.copy.2211 ]
  %t2221 = call ptr @__alloc(i64 16, i32 1)
  %t2222 = inttoptr i64 284 to ptr
  %t2223 = getelementptr ptr, ptr %t2221, i32 0
  store ptr %t2222, ptr %t2223
  call void @__inc_ref(ptr %t6)
  %t2224 = getelementptr ptr, ptr %t2221, i32 1
  store ptr %t6, ptr %t2224
  call void @__free_recursive(ptr %t6)
  store ptr %t2220, ptr %t3
  store ptr %t2221, ptr %t4
  br label %tco.loop.0
tco.case.arm.139.2225:
  %t2226 = getelementptr ptr, ptr %t5, i32 1
  %t2227 = load ptr, ptr %t2226
  %t2228 = getelementptr ptr, ptr %t5, i32 2
  %t2229 = load ptr, ptr %t2228
  %t2230 = getelementptr i8, ptr %t5, i64 -8
  %t2231 = load i32, ptr %t2230
  %t2232 = icmp eq i32 %t2231, 1
  br i1 %t2232, label %reuse.in_place.2233, label %reuse.copy.2234
reuse.in_place.2233:
  %t2236 = inttoptr i64 114 to ptr
  %t2237 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2236, ptr %t2237
  br label %reuse.join.2235
reuse.copy.2234:
  %t2238 = call ptr @__alloc(i64 24, i32 2)
  %t2239 = inttoptr i64 114 to ptr
  %t2240 = getelementptr ptr, ptr %t2238, i32 0
  store ptr %t2239, ptr %t2240
  call void @__inc_ref(ptr %t2227)
  %t2241 = getelementptr ptr, ptr %t2238, i32 1
  store ptr %t2227, ptr %t2241
  call void @__inc_ref(ptr %t2229)
  %t2242 = getelementptr ptr, ptr %t2238, i32 2
  store ptr %t2229, ptr %t2242
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2235
reuse.join.2235:
  %t2243 = phi ptr [ %t5, %reuse.in_place.2233 ], [ %t2238, %reuse.copy.2234 ]
  %t2244 = call ptr @__alloc(i64 16, i32 1)
  %t2245 = inttoptr i64 285 to ptr
  %t2246 = getelementptr ptr, ptr %t2244, i32 0
  store ptr %t2245, ptr %t2246
  call void @__inc_ref(ptr %t6)
  %t2247 = getelementptr ptr, ptr %t2244, i32 1
  store ptr %t6, ptr %t2247
  call void @__free_recursive(ptr %t6)
  store ptr %t2243, ptr %t3
  store ptr %t2244, ptr %t4
  br label %tco.loop.0
tco.case.arm.140.2248:
  %t2249 = getelementptr ptr, ptr %t5, i32 1
  %t2250 = load ptr, ptr %t2249
  %t2251 = getelementptr ptr, ptr %t5, i32 2
  %t2252 = load ptr, ptr %t2251
  %t2253 = getelementptr i8, ptr %t5, i64 -8
  %t2254 = load i32, ptr %t2253
  %t2255 = icmp eq i32 %t2254, 1
  br i1 %t2255, label %reuse.in_place.2256, label %reuse.copy.2257
reuse.in_place.2256:
  %t2259 = inttoptr i64 114 to ptr
  %t2260 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2259, ptr %t2260
  br label %reuse.join.2258
reuse.copy.2257:
  %t2261 = call ptr @__alloc(i64 24, i32 2)
  %t2262 = inttoptr i64 114 to ptr
  %t2263 = getelementptr ptr, ptr %t2261, i32 0
  store ptr %t2262, ptr %t2263
  call void @__inc_ref(ptr %t2250)
  %t2264 = getelementptr ptr, ptr %t2261, i32 1
  store ptr %t2250, ptr %t2264
  call void @__inc_ref(ptr %t2252)
  %t2265 = getelementptr ptr, ptr %t2261, i32 2
  store ptr %t2252, ptr %t2265
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2258
reuse.join.2258:
  %t2266 = phi ptr [ %t5, %reuse.in_place.2256 ], [ %t2261, %reuse.copy.2257 ]
  %t2267 = call ptr @__alloc(i64 16, i32 1)
  %t2268 = inttoptr i64 286 to ptr
  %t2269 = getelementptr ptr, ptr %t2267, i32 0
  store ptr %t2268, ptr %t2269
  call void @__inc_ref(ptr %t6)
  %t2270 = getelementptr ptr, ptr %t2267, i32 1
  store ptr %t6, ptr %t2270
  call void @__free_recursive(ptr %t6)
  store ptr %t2266, ptr %t3
  store ptr %t2267, ptr %t4
  br label %tco.loop.0
tco.case.arm.141.2271:
  %t2272 = getelementptr ptr, ptr %t5, i32 1
  %t2273 = load ptr, ptr %t2272
  %t2274 = getelementptr ptr, ptr %t5, i32 2
  %t2275 = load ptr, ptr %t2274
  %t2276 = getelementptr i8, ptr %t5, i64 -8
  %t2277 = load i32, ptr %t2276
  %t2278 = icmp eq i32 %t2277, 1
  br i1 %t2278, label %reuse.in_place.2279, label %reuse.copy.2280
reuse.in_place.2279:
  %t2282 = inttoptr i64 114 to ptr
  %t2283 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2282, ptr %t2283
  br label %reuse.join.2281
reuse.copy.2280:
  %t2284 = call ptr @__alloc(i64 24, i32 2)
  %t2285 = inttoptr i64 114 to ptr
  %t2286 = getelementptr ptr, ptr %t2284, i32 0
  store ptr %t2285, ptr %t2286
  call void @__inc_ref(ptr %t2273)
  %t2287 = getelementptr ptr, ptr %t2284, i32 1
  store ptr %t2273, ptr %t2287
  call void @__inc_ref(ptr %t2275)
  %t2288 = getelementptr ptr, ptr %t2284, i32 2
  store ptr %t2275, ptr %t2288
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2281
reuse.join.2281:
  %t2289 = phi ptr [ %t5, %reuse.in_place.2279 ], [ %t2284, %reuse.copy.2280 ]
  %t2290 = call ptr @__alloc(i64 16, i32 1)
  %t2291 = inttoptr i64 287 to ptr
  %t2292 = getelementptr ptr, ptr %t2290, i32 0
  store ptr %t2291, ptr %t2292
  call void @__inc_ref(ptr %t6)
  %t2293 = getelementptr ptr, ptr %t2290, i32 1
  store ptr %t6, ptr %t2293
  call void @__free_recursive(ptr %t6)
  store ptr %t2289, ptr %t3
  store ptr %t2290, ptr %t4
  br label %tco.loop.0
tco.case.arm.142.2294:
  %t2295 = getelementptr ptr, ptr %t5, i32 1
  %t2296 = load ptr, ptr %t2295
  %t2297 = getelementptr ptr, ptr %t5, i32 2
  %t2298 = load ptr, ptr %t2297
  %t2299 = getelementptr i8, ptr %t5, i64 -8
  %t2300 = load i32, ptr %t2299
  %t2301 = icmp eq i32 %t2300, 1
  br i1 %t2301, label %reuse.in_place.2302, label %reuse.copy.2303
reuse.in_place.2302:
  %t2305 = inttoptr i64 114 to ptr
  %t2306 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2305, ptr %t2306
  br label %reuse.join.2304
reuse.copy.2303:
  %t2307 = call ptr @__alloc(i64 24, i32 2)
  %t2308 = inttoptr i64 114 to ptr
  %t2309 = getelementptr ptr, ptr %t2307, i32 0
  store ptr %t2308, ptr %t2309
  call void @__inc_ref(ptr %t2296)
  %t2310 = getelementptr ptr, ptr %t2307, i32 1
  store ptr %t2296, ptr %t2310
  call void @__inc_ref(ptr %t2298)
  %t2311 = getelementptr ptr, ptr %t2307, i32 2
  store ptr %t2298, ptr %t2311
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2304
reuse.join.2304:
  %t2312 = phi ptr [ %t5, %reuse.in_place.2302 ], [ %t2307, %reuse.copy.2303 ]
  %t2313 = call ptr @__alloc(i64 16, i32 1)
  %t2314 = inttoptr i64 288 to ptr
  %t2315 = getelementptr ptr, ptr %t2313, i32 0
  store ptr %t2314, ptr %t2315
  call void @__inc_ref(ptr %t6)
  %t2316 = getelementptr ptr, ptr %t2313, i32 1
  store ptr %t6, ptr %t2316
  call void @__free_recursive(ptr %t6)
  store ptr %t2312, ptr %t3
  store ptr %t2313, ptr %t4
  br label %tco.loop.0
tco.case.arm.143.2317:
  %t2318 = getelementptr ptr, ptr %t5, i32 1
  %t2319 = load ptr, ptr %t2318
  %t2320 = getelementptr ptr, ptr %t5, i32 2
  %t2321 = load ptr, ptr %t2320
  %t2322 = getelementptr i8, ptr %t5, i64 -8
  %t2323 = load i32, ptr %t2322
  %t2324 = icmp eq i32 %t2323, 1
  br i1 %t2324, label %reuse.in_place.2325, label %reuse.copy.2326
reuse.in_place.2325:
  %t2328 = inttoptr i64 114 to ptr
  %t2329 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2328, ptr %t2329
  br label %reuse.join.2327
reuse.copy.2326:
  %t2330 = call ptr @__alloc(i64 24, i32 2)
  %t2331 = inttoptr i64 114 to ptr
  %t2332 = getelementptr ptr, ptr %t2330, i32 0
  store ptr %t2331, ptr %t2332
  call void @__inc_ref(ptr %t2319)
  %t2333 = getelementptr ptr, ptr %t2330, i32 1
  store ptr %t2319, ptr %t2333
  call void @__inc_ref(ptr %t2321)
  %t2334 = getelementptr ptr, ptr %t2330, i32 2
  store ptr %t2321, ptr %t2334
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2327
reuse.join.2327:
  %t2335 = phi ptr [ %t5, %reuse.in_place.2325 ], [ %t2330, %reuse.copy.2326 ]
  %t2336 = call ptr @__alloc(i64 16, i32 1)
  %t2337 = inttoptr i64 289 to ptr
  %t2338 = getelementptr ptr, ptr %t2336, i32 0
  store ptr %t2337, ptr %t2338
  call void @__inc_ref(ptr %t6)
  %t2339 = getelementptr ptr, ptr %t2336, i32 1
  store ptr %t6, ptr %t2339
  call void @__free_recursive(ptr %t6)
  store ptr %t2335, ptr %t3
  store ptr %t2336, ptr %t4
  br label %tco.loop.0
tco.case.arm.144.2340:
  %t2341 = getelementptr ptr, ptr %t5, i32 1
  %t2342 = load ptr, ptr %t2341
  %t2343 = getelementptr ptr, ptr %t5, i32 2
  %t2344 = load ptr, ptr %t2343
  %t2345 = getelementptr i8, ptr %t5, i64 -8
  %t2346 = load i32, ptr %t2345
  %t2347 = icmp eq i32 %t2346, 1
  br i1 %t2347, label %reuse.in_place.2348, label %reuse.copy.2349
reuse.in_place.2348:
  %t2351 = inttoptr i64 114 to ptr
  %t2352 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2351, ptr %t2352
  br label %reuse.join.2350
reuse.copy.2349:
  %t2353 = call ptr @__alloc(i64 24, i32 2)
  %t2354 = inttoptr i64 114 to ptr
  %t2355 = getelementptr ptr, ptr %t2353, i32 0
  store ptr %t2354, ptr %t2355
  call void @__inc_ref(ptr %t2342)
  %t2356 = getelementptr ptr, ptr %t2353, i32 1
  store ptr %t2342, ptr %t2356
  call void @__inc_ref(ptr %t2344)
  %t2357 = getelementptr ptr, ptr %t2353, i32 2
  store ptr %t2344, ptr %t2357
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2350
reuse.join.2350:
  %t2358 = phi ptr [ %t5, %reuse.in_place.2348 ], [ %t2353, %reuse.copy.2349 ]
  %t2359 = call ptr @__alloc(i64 16, i32 1)
  %t2360 = inttoptr i64 290 to ptr
  %t2361 = getelementptr ptr, ptr %t2359, i32 0
  store ptr %t2360, ptr %t2361
  call void @__inc_ref(ptr %t6)
  %t2362 = getelementptr ptr, ptr %t2359, i32 1
  store ptr %t6, ptr %t2362
  call void @__free_recursive(ptr %t6)
  store ptr %t2358, ptr %t3
  store ptr %t2359, ptr %t4
  br label %tco.loop.0
tco.case.arm.145.2363:
  %t2364 = getelementptr ptr, ptr %t5, i32 1
  %t2365 = load ptr, ptr %t2364
  %t2366 = getelementptr ptr, ptr %t5, i32 2
  %t2367 = load ptr, ptr %t2366
  %t2368 = getelementptr i8, ptr %t5, i64 -8
  %t2369 = load i32, ptr %t2368
  %t2370 = icmp eq i32 %t2369, 1
  br i1 %t2370, label %reuse.in_place.2371, label %reuse.copy.2372
reuse.in_place.2371:
  %t2374 = inttoptr i64 114 to ptr
  %t2375 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2374, ptr %t2375
  br label %reuse.join.2373
reuse.copy.2372:
  %t2376 = call ptr @__alloc(i64 24, i32 2)
  %t2377 = inttoptr i64 114 to ptr
  %t2378 = getelementptr ptr, ptr %t2376, i32 0
  store ptr %t2377, ptr %t2378
  call void @__inc_ref(ptr %t2365)
  %t2379 = getelementptr ptr, ptr %t2376, i32 1
  store ptr %t2365, ptr %t2379
  call void @__inc_ref(ptr %t2367)
  %t2380 = getelementptr ptr, ptr %t2376, i32 2
  store ptr %t2367, ptr %t2380
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2373
reuse.join.2373:
  %t2381 = phi ptr [ %t5, %reuse.in_place.2371 ], [ %t2376, %reuse.copy.2372 ]
  %t2382 = call ptr @__alloc(i64 16, i32 1)
  %t2383 = inttoptr i64 291 to ptr
  %t2384 = getelementptr ptr, ptr %t2382, i32 0
  store ptr %t2383, ptr %t2384
  call void @__inc_ref(ptr %t6)
  %t2385 = getelementptr ptr, ptr %t2382, i32 1
  store ptr %t6, ptr %t2385
  call void @__free_recursive(ptr %t6)
  store ptr %t2381, ptr %t3
  store ptr %t2382, ptr %t4
  br label %tco.loop.0
tco.case.arm.146.2386:
  %t2387 = getelementptr ptr, ptr %t5, i32 1
  %t2388 = load ptr, ptr %t2387
  %t2389 = getelementptr ptr, ptr %t5, i32 2
  %t2390 = load ptr, ptr %t2389
  %t2391 = getelementptr i8, ptr %t5, i64 -8
  %t2392 = load i32, ptr %t2391
  %t2393 = icmp eq i32 %t2392, 1
  br i1 %t2393, label %reuse.in_place.2394, label %reuse.copy.2395
reuse.in_place.2394:
  %t2397 = inttoptr i64 114 to ptr
  %t2398 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2397, ptr %t2398
  br label %reuse.join.2396
reuse.copy.2395:
  %t2399 = call ptr @__alloc(i64 24, i32 2)
  %t2400 = inttoptr i64 114 to ptr
  %t2401 = getelementptr ptr, ptr %t2399, i32 0
  store ptr %t2400, ptr %t2401
  call void @__inc_ref(ptr %t2388)
  %t2402 = getelementptr ptr, ptr %t2399, i32 1
  store ptr %t2388, ptr %t2402
  call void @__inc_ref(ptr %t2390)
  %t2403 = getelementptr ptr, ptr %t2399, i32 2
  store ptr %t2390, ptr %t2403
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2396
reuse.join.2396:
  %t2404 = phi ptr [ %t5, %reuse.in_place.2394 ], [ %t2399, %reuse.copy.2395 ]
  %t2405 = call ptr @__alloc(i64 16, i32 1)
  %t2406 = inttoptr i64 292 to ptr
  %t2407 = getelementptr ptr, ptr %t2405, i32 0
  store ptr %t2406, ptr %t2407
  call void @__inc_ref(ptr %t6)
  %t2408 = getelementptr ptr, ptr %t2405, i32 1
  store ptr %t6, ptr %t2408
  call void @__free_recursive(ptr %t6)
  store ptr %t2404, ptr %t3
  store ptr %t2405, ptr %t4
  br label %tco.loop.0
tco.case.arm.147.2409:
  %t2410 = getelementptr ptr, ptr %t5, i32 1
  %t2411 = load ptr, ptr %t2410
  %t2412 = getelementptr ptr, ptr %t5, i32 2
  %t2413 = load ptr, ptr %t2412
  %t2414 = getelementptr i8, ptr %t5, i64 -8
  %t2415 = load i32, ptr %t2414
  %t2416 = icmp eq i32 %t2415, 1
  br i1 %t2416, label %reuse.in_place.2417, label %reuse.copy.2418
reuse.in_place.2417:
  %t2420 = inttoptr i64 114 to ptr
  %t2421 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2420, ptr %t2421
  br label %reuse.join.2419
reuse.copy.2418:
  %t2422 = call ptr @__alloc(i64 24, i32 2)
  %t2423 = inttoptr i64 114 to ptr
  %t2424 = getelementptr ptr, ptr %t2422, i32 0
  store ptr %t2423, ptr %t2424
  call void @__inc_ref(ptr %t2411)
  %t2425 = getelementptr ptr, ptr %t2422, i32 1
  store ptr %t2411, ptr %t2425
  call void @__inc_ref(ptr %t2413)
  %t2426 = getelementptr ptr, ptr %t2422, i32 2
  store ptr %t2413, ptr %t2426
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2419
reuse.join.2419:
  %t2427 = phi ptr [ %t5, %reuse.in_place.2417 ], [ %t2422, %reuse.copy.2418 ]
  %t2428 = call ptr @__alloc(i64 16, i32 1)
  %t2429 = inttoptr i64 293 to ptr
  %t2430 = getelementptr ptr, ptr %t2428, i32 0
  store ptr %t2429, ptr %t2430
  call void @__inc_ref(ptr %t6)
  %t2431 = getelementptr ptr, ptr %t2428, i32 1
  store ptr %t6, ptr %t2431
  call void @__free_recursive(ptr %t6)
  store ptr %t2427, ptr %t3
  store ptr %t2428, ptr %t4
  br label %tco.loop.0
tco.case.arm.148.2432:
  %t2433 = getelementptr ptr, ptr %t5, i32 1
  %t2434 = load ptr, ptr %t2433
  %t2435 = getelementptr ptr, ptr %t5, i32 2
  %t2436 = load ptr, ptr %t2435
  %t2437 = getelementptr i8, ptr %t5, i64 -8
  %t2438 = load i32, ptr %t2437
  %t2439 = icmp eq i32 %t2438, 1
  br i1 %t2439, label %reuse.in_place.2440, label %reuse.copy.2441
reuse.in_place.2440:
  %t2443 = inttoptr i64 114 to ptr
  %t2444 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2443, ptr %t2444
  br label %reuse.join.2442
reuse.copy.2441:
  %t2445 = call ptr @__alloc(i64 24, i32 2)
  %t2446 = inttoptr i64 114 to ptr
  %t2447 = getelementptr ptr, ptr %t2445, i32 0
  store ptr %t2446, ptr %t2447
  call void @__inc_ref(ptr %t2434)
  %t2448 = getelementptr ptr, ptr %t2445, i32 1
  store ptr %t2434, ptr %t2448
  call void @__inc_ref(ptr %t2436)
  %t2449 = getelementptr ptr, ptr %t2445, i32 2
  store ptr %t2436, ptr %t2449
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2442
reuse.join.2442:
  %t2450 = phi ptr [ %t5, %reuse.in_place.2440 ], [ %t2445, %reuse.copy.2441 ]
  %t2451 = call ptr @__alloc(i64 16, i32 1)
  %t2452 = inttoptr i64 294 to ptr
  %t2453 = getelementptr ptr, ptr %t2451, i32 0
  store ptr %t2452, ptr %t2453
  call void @__inc_ref(ptr %t6)
  %t2454 = getelementptr ptr, ptr %t2451, i32 1
  store ptr %t6, ptr %t2454
  call void @__free_recursive(ptr %t6)
  store ptr %t2450, ptr %t3
  store ptr %t2451, ptr %t4
  br label %tco.loop.0
tco.case.arm.149.2455:
  %t2456 = getelementptr ptr, ptr %t5, i32 1
  %t2457 = load ptr, ptr %t2456
  call void @__inc_ref(ptr %t2457)
  %t2458 = getelementptr ptr, ptr %t5, i32 2
  %t2459 = load ptr, ptr %t2458
  call void @__inc_ref(ptr %t2459)
  %t2460 = getelementptr ptr, ptr %t5, i32 3
  %t2461 = load ptr, ptr %t2460
  call void @__inc_ref(ptr %t2461)
  %t2462 = call ptr @__alloc(i64 24, i32 2)
  %t2463 = inttoptr i64 114 to ptr
  %t2464 = getelementptr ptr, ptr %t2462, i32 0
  store ptr %t2463, ptr %t2464
  call void @__inc_ref(ptr %t2457)
  %t2465 = getelementptr ptr, ptr %t2462, i32 1
  store ptr %t2457, ptr %t2465
  call void @__inc_ref(ptr %t2459)
  %t2466 = getelementptr ptr, ptr %t2462, i32 2
  store ptr %t2459, ptr %t2466
  %t2467 = call ptr @__alloc(i64 24, i32 2)
  %t2468 = inttoptr i64 295 to ptr
  %t2469 = getelementptr ptr, ptr %t2467, i32 0
  store ptr %t2468, ptr %t2469
  call void @__inc_ref(ptr %t6)
  %t2470 = getelementptr ptr, ptr %t2467, i32 1
  store ptr %t6, ptr %t2470
  call void @__inc_ref(ptr %t2461)
  %t2471 = getelementptr ptr, ptr %t2467, i32 2
  store ptr %t2461, ptr %t2471
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t2461)
  call void @__free_recursive(ptr %t2459)
  call void @__free_recursive(ptr %t2457)
  store ptr %t2462, ptr %t3
  store ptr %t2467, ptr %t4
  br label %tco.loop.0
tco.case.arm.150.2472:
  %t2473 = getelementptr ptr, ptr %t5, i32 1
  %t2474 = load ptr, ptr %t2473
  %t2475 = getelementptr ptr, ptr %t5, i32 2
  %t2476 = load ptr, ptr %t2475
  %t2477 = getelementptr i8, ptr %t5, i64 -8
  %t2478 = load i32, ptr %t2477
  %t2479 = icmp eq i32 %t2478, 1
  br i1 %t2479, label %reuse.in_place.2480, label %reuse.copy.2481
reuse.in_place.2480:
  %t2483 = inttoptr i64 114 to ptr
  %t2484 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2483, ptr %t2484
  br label %reuse.join.2482
reuse.copy.2481:
  %t2485 = call ptr @__alloc(i64 24, i32 2)
  %t2486 = inttoptr i64 114 to ptr
  %t2487 = getelementptr ptr, ptr %t2485, i32 0
  store ptr %t2486, ptr %t2487
  call void @__inc_ref(ptr %t2474)
  %t2488 = getelementptr ptr, ptr %t2485, i32 1
  store ptr %t2474, ptr %t2488
  call void @__inc_ref(ptr %t2476)
  %t2489 = getelementptr ptr, ptr %t2485, i32 2
  store ptr %t2476, ptr %t2489
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2482
reuse.join.2482:
  %t2490 = phi ptr [ %t5, %reuse.in_place.2480 ], [ %t2485, %reuse.copy.2481 ]
  %t2491 = call ptr @__alloc(i64 16, i32 1)
  %t2492 = inttoptr i64 296 to ptr
  %t2493 = getelementptr ptr, ptr %t2491, i32 0
  store ptr %t2492, ptr %t2493
  call void @__inc_ref(ptr %t6)
  %t2494 = getelementptr ptr, ptr %t2491, i32 1
  store ptr %t6, ptr %t2494
  call void @__free_recursive(ptr %t6)
  store ptr %t2490, ptr %t3
  store ptr %t2491, ptr %t4
  br label %tco.loop.0
tco.case.arm.151.2495:
  %t2496 = getelementptr ptr, ptr %t5, i32 1
  %t2497 = load ptr, ptr %t2496
  %t2498 = getelementptr ptr, ptr %t5, i32 2
  %t2499 = load ptr, ptr %t2498
  %t2500 = getelementptr i8, ptr %t5, i64 -8
  %t2501 = load i32, ptr %t2500
  %t2502 = icmp eq i32 %t2501, 1
  br i1 %t2502, label %reuse.in_place.2503, label %reuse.copy.2504
reuse.in_place.2503:
  %t2506 = inttoptr i64 114 to ptr
  %t2507 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2506, ptr %t2507
  br label %reuse.join.2505
reuse.copy.2504:
  %t2508 = call ptr @__alloc(i64 24, i32 2)
  %t2509 = inttoptr i64 114 to ptr
  %t2510 = getelementptr ptr, ptr %t2508, i32 0
  store ptr %t2509, ptr %t2510
  call void @__inc_ref(ptr %t2497)
  %t2511 = getelementptr ptr, ptr %t2508, i32 1
  store ptr %t2497, ptr %t2511
  call void @__inc_ref(ptr %t2499)
  %t2512 = getelementptr ptr, ptr %t2508, i32 2
  store ptr %t2499, ptr %t2512
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2505
reuse.join.2505:
  %t2513 = phi ptr [ %t5, %reuse.in_place.2503 ], [ %t2508, %reuse.copy.2504 ]
  %t2514 = call ptr @__alloc(i64 16, i32 1)
  %t2515 = inttoptr i64 297 to ptr
  %t2516 = getelementptr ptr, ptr %t2514, i32 0
  store ptr %t2515, ptr %t2516
  call void @__inc_ref(ptr %t6)
  %t2517 = getelementptr ptr, ptr %t2514, i32 1
  store ptr %t6, ptr %t2517
  call void @__free_recursive(ptr %t6)
  store ptr %t2513, ptr %t3
  store ptr %t2514, ptr %t4
  br label %tco.loop.0
tco.case.arm.152.2518:
  %t2519 = getelementptr ptr, ptr %t5, i32 1
  %t2520 = load ptr, ptr %t2519
  %t2521 = getelementptr ptr, ptr %t5, i32 2
  %t2522 = load ptr, ptr %t2521
  %t2523 = getelementptr i8, ptr %t5, i64 -8
  %t2524 = load i32, ptr %t2523
  %t2525 = icmp eq i32 %t2524, 1
  br i1 %t2525, label %reuse.in_place.2526, label %reuse.copy.2527
reuse.in_place.2526:
  %t2529 = inttoptr i64 114 to ptr
  %t2530 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2529, ptr %t2530
  br label %reuse.join.2528
reuse.copy.2527:
  %t2531 = call ptr @__alloc(i64 24, i32 2)
  %t2532 = inttoptr i64 114 to ptr
  %t2533 = getelementptr ptr, ptr %t2531, i32 0
  store ptr %t2532, ptr %t2533
  call void @__inc_ref(ptr %t2520)
  %t2534 = getelementptr ptr, ptr %t2531, i32 1
  store ptr %t2520, ptr %t2534
  call void @__inc_ref(ptr %t2522)
  %t2535 = getelementptr ptr, ptr %t2531, i32 2
  store ptr %t2522, ptr %t2535
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2528
reuse.join.2528:
  %t2536 = phi ptr [ %t5, %reuse.in_place.2526 ], [ %t2531, %reuse.copy.2527 ]
  %t2537 = call ptr @__alloc(i64 16, i32 1)
  %t2538 = inttoptr i64 298 to ptr
  %t2539 = getelementptr ptr, ptr %t2537, i32 0
  store ptr %t2538, ptr %t2539
  call void @__inc_ref(ptr %t6)
  %t2540 = getelementptr ptr, ptr %t2537, i32 1
  store ptr %t6, ptr %t2540
  call void @__free_recursive(ptr %t6)
  store ptr %t2536, ptr %t3
  store ptr %t2537, ptr %t4
  br label %tco.loop.0
tco.case.arm.153.2541:
  %t2542 = getelementptr ptr, ptr %t5, i32 1
  %t2543 = load ptr, ptr %t2542
  %t2544 = getelementptr ptr, ptr %t5, i32 2
  %t2545 = load ptr, ptr %t2544
  %t2546 = getelementptr i8, ptr %t5, i64 -8
  %t2547 = load i32, ptr %t2546
  %t2548 = icmp eq i32 %t2547, 1
  br i1 %t2548, label %reuse.in_place.2549, label %reuse.copy.2550
reuse.in_place.2549:
  %t2552 = inttoptr i64 114 to ptr
  %t2553 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2552, ptr %t2553
  br label %reuse.join.2551
reuse.copy.2550:
  %t2554 = call ptr @__alloc(i64 24, i32 2)
  %t2555 = inttoptr i64 114 to ptr
  %t2556 = getelementptr ptr, ptr %t2554, i32 0
  store ptr %t2555, ptr %t2556
  call void @__inc_ref(ptr %t2543)
  %t2557 = getelementptr ptr, ptr %t2554, i32 1
  store ptr %t2543, ptr %t2557
  call void @__inc_ref(ptr %t2545)
  %t2558 = getelementptr ptr, ptr %t2554, i32 2
  store ptr %t2545, ptr %t2558
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2551
reuse.join.2551:
  %t2559 = phi ptr [ %t5, %reuse.in_place.2549 ], [ %t2554, %reuse.copy.2550 ]
  %t2560 = call ptr @__alloc(i64 16, i32 1)
  %t2561 = inttoptr i64 299 to ptr
  %t2562 = getelementptr ptr, ptr %t2560, i32 0
  store ptr %t2561, ptr %t2562
  call void @__inc_ref(ptr %t6)
  %t2563 = getelementptr ptr, ptr %t2560, i32 1
  store ptr %t6, ptr %t2563
  call void @__free_recursive(ptr %t6)
  store ptr %t2559, ptr %t3
  store ptr %t2560, ptr %t4
  br label %tco.loop.0
tco.case.arm.154.2564:
  %t2565 = getelementptr ptr, ptr %t5, i32 1
  %t2566 = load ptr, ptr %t2565
  %t2567 = getelementptr ptr, ptr %t5, i32 2
  %t2568 = load ptr, ptr %t2567
  %t2569 = getelementptr i8, ptr %t5, i64 -8
  %t2570 = load i32, ptr %t2569
  %t2571 = icmp eq i32 %t2570, 1
  br i1 %t2571, label %reuse.in_place.2572, label %reuse.copy.2573
reuse.in_place.2572:
  %t2575 = inttoptr i64 114 to ptr
  %t2576 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2575, ptr %t2576
  br label %reuse.join.2574
reuse.copy.2573:
  %t2577 = call ptr @__alloc(i64 24, i32 2)
  %t2578 = inttoptr i64 114 to ptr
  %t2579 = getelementptr ptr, ptr %t2577, i32 0
  store ptr %t2578, ptr %t2579
  call void @__inc_ref(ptr %t2566)
  %t2580 = getelementptr ptr, ptr %t2577, i32 1
  store ptr %t2566, ptr %t2580
  call void @__inc_ref(ptr %t2568)
  %t2581 = getelementptr ptr, ptr %t2577, i32 2
  store ptr %t2568, ptr %t2581
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2574
reuse.join.2574:
  %t2582 = phi ptr [ %t5, %reuse.in_place.2572 ], [ %t2577, %reuse.copy.2573 ]
  %t2583 = call ptr @__alloc(i64 16, i32 1)
  %t2584 = inttoptr i64 300 to ptr
  %t2585 = getelementptr ptr, ptr %t2583, i32 0
  store ptr %t2584, ptr %t2585
  call void @__inc_ref(ptr %t6)
  %t2586 = getelementptr ptr, ptr %t2583, i32 1
  store ptr %t6, ptr %t2586
  call void @__free_recursive(ptr %t6)
  store ptr %t2582, ptr %t3
  store ptr %t2583, ptr %t4
  br label %tco.loop.0
tco.case.arm.155.2587:
  %t2588 = getelementptr ptr, ptr %t5, i32 1
  %t2589 = load ptr, ptr %t2588
  %t2590 = getelementptr ptr, ptr %t5, i32 2
  %t2591 = load ptr, ptr %t2590
  %t2592 = getelementptr i8, ptr %t5, i64 -8
  %t2593 = load i32, ptr %t2592
  %t2594 = icmp eq i32 %t2593, 1
  br i1 %t2594, label %reuse.in_place.2595, label %reuse.copy.2596
reuse.in_place.2595:
  %t2598 = inttoptr i64 114 to ptr
  %t2599 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2598, ptr %t2599
  br label %reuse.join.2597
reuse.copy.2596:
  %t2600 = call ptr @__alloc(i64 24, i32 2)
  %t2601 = inttoptr i64 114 to ptr
  %t2602 = getelementptr ptr, ptr %t2600, i32 0
  store ptr %t2601, ptr %t2602
  call void @__inc_ref(ptr %t2589)
  %t2603 = getelementptr ptr, ptr %t2600, i32 1
  store ptr %t2589, ptr %t2603
  call void @__inc_ref(ptr %t2591)
  %t2604 = getelementptr ptr, ptr %t2600, i32 2
  store ptr %t2591, ptr %t2604
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2597
reuse.join.2597:
  %t2605 = phi ptr [ %t5, %reuse.in_place.2595 ], [ %t2600, %reuse.copy.2596 ]
  %t2606 = call ptr @__alloc(i64 16, i32 1)
  %t2607 = inttoptr i64 301 to ptr
  %t2608 = getelementptr ptr, ptr %t2606, i32 0
  store ptr %t2607, ptr %t2608
  call void @__inc_ref(ptr %t6)
  %t2609 = getelementptr ptr, ptr %t2606, i32 1
  store ptr %t6, ptr %t2609
  call void @__free_recursive(ptr %t6)
  store ptr %t2605, ptr %t3
  store ptr %t2606, ptr %t4
  br label %tco.loop.0
tco.case.arm.156.2610:
  %t2611 = getelementptr ptr, ptr %t5, i32 1
  %t2612 = load ptr, ptr %t2611
  %t2613 = getelementptr ptr, ptr %t5, i32 2
  %t2614 = load ptr, ptr %t2613
  %t2615 = getelementptr i8, ptr %t5, i64 -8
  %t2616 = load i32, ptr %t2615
  %t2617 = icmp eq i32 %t2616, 1
  br i1 %t2617, label %reuse.in_place.2618, label %reuse.copy.2619
reuse.in_place.2618:
  %t2621 = inttoptr i64 114 to ptr
  %t2622 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2621, ptr %t2622
  br label %reuse.join.2620
reuse.copy.2619:
  %t2623 = call ptr @__alloc(i64 24, i32 2)
  %t2624 = inttoptr i64 114 to ptr
  %t2625 = getelementptr ptr, ptr %t2623, i32 0
  store ptr %t2624, ptr %t2625
  call void @__inc_ref(ptr %t2612)
  %t2626 = getelementptr ptr, ptr %t2623, i32 1
  store ptr %t2612, ptr %t2626
  call void @__inc_ref(ptr %t2614)
  %t2627 = getelementptr ptr, ptr %t2623, i32 2
  store ptr %t2614, ptr %t2627
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2620
reuse.join.2620:
  %t2628 = phi ptr [ %t5, %reuse.in_place.2618 ], [ %t2623, %reuse.copy.2619 ]
  %t2629 = call ptr @__alloc(i64 16, i32 1)
  %t2630 = inttoptr i64 302 to ptr
  %t2631 = getelementptr ptr, ptr %t2629, i32 0
  store ptr %t2630, ptr %t2631
  call void @__inc_ref(ptr %t6)
  %t2632 = getelementptr ptr, ptr %t2629, i32 1
  store ptr %t6, ptr %t2632
  call void @__free_recursive(ptr %t6)
  store ptr %t2628, ptr %t3
  store ptr %t2629, ptr %t4
  br label %tco.loop.0
tco.case.arm.157.2633:
  %t2634 = getelementptr ptr, ptr %t5, i32 1
  %t2635 = load ptr, ptr %t2634
  %t2636 = getelementptr ptr, ptr %t5, i32 2
  %t2637 = load ptr, ptr %t2636
  %t2638 = getelementptr i8, ptr %t5, i64 -8
  %t2639 = load i32, ptr %t2638
  %t2640 = icmp eq i32 %t2639, 1
  br i1 %t2640, label %reuse.in_place.2641, label %reuse.copy.2642
reuse.in_place.2641:
  %t2644 = inttoptr i64 114 to ptr
  %t2645 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2644, ptr %t2645
  br label %reuse.join.2643
reuse.copy.2642:
  %t2646 = call ptr @__alloc(i64 24, i32 2)
  %t2647 = inttoptr i64 114 to ptr
  %t2648 = getelementptr ptr, ptr %t2646, i32 0
  store ptr %t2647, ptr %t2648
  call void @__inc_ref(ptr %t2635)
  %t2649 = getelementptr ptr, ptr %t2646, i32 1
  store ptr %t2635, ptr %t2649
  call void @__inc_ref(ptr %t2637)
  %t2650 = getelementptr ptr, ptr %t2646, i32 2
  store ptr %t2637, ptr %t2650
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2643
reuse.join.2643:
  %t2651 = phi ptr [ %t5, %reuse.in_place.2641 ], [ %t2646, %reuse.copy.2642 ]
  %t2652 = call ptr @__alloc(i64 16, i32 1)
  %t2653 = inttoptr i64 303 to ptr
  %t2654 = getelementptr ptr, ptr %t2652, i32 0
  store ptr %t2653, ptr %t2654
  call void @__inc_ref(ptr %t6)
  %t2655 = getelementptr ptr, ptr %t2652, i32 1
  store ptr %t6, ptr %t2655
  call void @__free_recursive(ptr %t6)
  store ptr %t2651, ptr %t3
  store ptr %t2652, ptr %t4
  br label %tco.loop.0
tco.case.arm.158.2656:
  %t2657 = getelementptr ptr, ptr %t5, i32 1
  %t2658 = load ptr, ptr %t2657
  %t2659 = getelementptr ptr, ptr %t5, i32 2
  %t2660 = load ptr, ptr %t2659
  %t2661 = getelementptr i8, ptr %t5, i64 -8
  %t2662 = load i32, ptr %t2661
  %t2663 = icmp eq i32 %t2662, 1
  br i1 %t2663, label %reuse.in_place.2664, label %reuse.copy.2665
reuse.in_place.2664:
  %t2667 = inttoptr i64 114 to ptr
  %t2668 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2667, ptr %t2668
  br label %reuse.join.2666
reuse.copy.2665:
  %t2669 = call ptr @__alloc(i64 24, i32 2)
  %t2670 = inttoptr i64 114 to ptr
  %t2671 = getelementptr ptr, ptr %t2669, i32 0
  store ptr %t2670, ptr %t2671
  call void @__inc_ref(ptr %t2658)
  %t2672 = getelementptr ptr, ptr %t2669, i32 1
  store ptr %t2658, ptr %t2672
  call void @__inc_ref(ptr %t2660)
  %t2673 = getelementptr ptr, ptr %t2669, i32 2
  store ptr %t2660, ptr %t2673
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2666
reuse.join.2666:
  %t2674 = phi ptr [ %t5, %reuse.in_place.2664 ], [ %t2669, %reuse.copy.2665 ]
  %t2675 = call ptr @__alloc(i64 16, i32 1)
  %t2676 = inttoptr i64 304 to ptr
  %t2677 = getelementptr ptr, ptr %t2675, i32 0
  store ptr %t2676, ptr %t2677
  call void @__inc_ref(ptr %t6)
  %t2678 = getelementptr ptr, ptr %t2675, i32 1
  store ptr %t6, ptr %t2678
  call void @__free_recursive(ptr %t6)
  store ptr %t2674, ptr %t3
  store ptr %t2675, ptr %t4
  br label %tco.loop.0
tco.case.arm.159.2679:
  %t2680 = getelementptr ptr, ptr %t5, i32 1
  %t2681 = load ptr, ptr %t2680
  %t2682 = getelementptr ptr, ptr %t5, i32 2
  %t2683 = load ptr, ptr %t2682
  %t2684 = getelementptr i8, ptr %t5, i64 -8
  %t2685 = load i32, ptr %t2684
  %t2686 = icmp eq i32 %t2685, 1
  br i1 %t2686, label %reuse.in_place.2687, label %reuse.copy.2688
reuse.in_place.2687:
  %t2690 = inttoptr i64 114 to ptr
  %t2691 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2690, ptr %t2691
  br label %reuse.join.2689
reuse.copy.2688:
  %t2692 = call ptr @__alloc(i64 24, i32 2)
  %t2693 = inttoptr i64 114 to ptr
  %t2694 = getelementptr ptr, ptr %t2692, i32 0
  store ptr %t2693, ptr %t2694
  call void @__inc_ref(ptr %t2681)
  %t2695 = getelementptr ptr, ptr %t2692, i32 1
  store ptr %t2681, ptr %t2695
  call void @__inc_ref(ptr %t2683)
  %t2696 = getelementptr ptr, ptr %t2692, i32 2
  store ptr %t2683, ptr %t2696
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2689
reuse.join.2689:
  %t2697 = phi ptr [ %t5, %reuse.in_place.2687 ], [ %t2692, %reuse.copy.2688 ]
  %t2698 = call ptr @__alloc(i64 16, i32 1)
  %t2699 = inttoptr i64 305 to ptr
  %t2700 = getelementptr ptr, ptr %t2698, i32 0
  store ptr %t2699, ptr %t2700
  call void @__inc_ref(ptr %t6)
  %t2701 = getelementptr ptr, ptr %t2698, i32 1
  store ptr %t6, ptr %t2701
  call void @__free_recursive(ptr %t6)
  store ptr %t2697, ptr %t3
  store ptr %t2698, ptr %t4
  br label %tco.loop.0
tco.case.arm.160.2702:
  %t2703 = getelementptr ptr, ptr %t5, i32 1
  %t2704 = load ptr, ptr %t2703
  %t2705 = getelementptr ptr, ptr %t5, i32 2
  %t2706 = load ptr, ptr %t2705
  %t2707 = getelementptr i8, ptr %t5, i64 -8
  %t2708 = load i32, ptr %t2707
  %t2709 = icmp eq i32 %t2708, 1
  br i1 %t2709, label %reuse.in_place.2710, label %reuse.copy.2711
reuse.in_place.2710:
  %t2713 = inttoptr i64 114 to ptr
  %t2714 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2713, ptr %t2714
  br label %reuse.join.2712
reuse.copy.2711:
  %t2715 = call ptr @__alloc(i64 24, i32 2)
  %t2716 = inttoptr i64 114 to ptr
  %t2717 = getelementptr ptr, ptr %t2715, i32 0
  store ptr %t2716, ptr %t2717
  call void @__inc_ref(ptr %t2704)
  %t2718 = getelementptr ptr, ptr %t2715, i32 1
  store ptr %t2704, ptr %t2718
  call void @__inc_ref(ptr %t2706)
  %t2719 = getelementptr ptr, ptr %t2715, i32 2
  store ptr %t2706, ptr %t2719
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2712
reuse.join.2712:
  %t2720 = phi ptr [ %t5, %reuse.in_place.2710 ], [ %t2715, %reuse.copy.2711 ]
  %t2721 = call ptr @__alloc(i64 16, i32 1)
  %t2722 = inttoptr i64 306 to ptr
  %t2723 = getelementptr ptr, ptr %t2721, i32 0
  store ptr %t2722, ptr %t2723
  call void @__inc_ref(ptr %t6)
  %t2724 = getelementptr ptr, ptr %t2721, i32 1
  store ptr %t6, ptr %t2724
  call void @__free_recursive(ptr %t6)
  store ptr %t2720, ptr %t3
  store ptr %t2721, ptr %t4
  br label %tco.loop.0
tco.case.arm.161.2725:
  %t2726 = getelementptr ptr, ptr %t5, i32 1
  %t2727 = load ptr, ptr %t2726
  %t2728 = getelementptr ptr, ptr %t5, i32 2
  %t2729 = load ptr, ptr %t2728
  %t2730 = getelementptr i8, ptr %t5, i64 -8
  %t2731 = load i32, ptr %t2730
  %t2732 = icmp eq i32 %t2731, 1
  br i1 %t2732, label %reuse.in_place.2733, label %reuse.copy.2734
reuse.in_place.2733:
  %t2736 = inttoptr i64 114 to ptr
  %t2737 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2736, ptr %t2737
  br label %reuse.join.2735
reuse.copy.2734:
  %t2738 = call ptr @__alloc(i64 24, i32 2)
  %t2739 = inttoptr i64 114 to ptr
  %t2740 = getelementptr ptr, ptr %t2738, i32 0
  store ptr %t2739, ptr %t2740
  call void @__inc_ref(ptr %t2727)
  %t2741 = getelementptr ptr, ptr %t2738, i32 1
  store ptr %t2727, ptr %t2741
  call void @__inc_ref(ptr %t2729)
  %t2742 = getelementptr ptr, ptr %t2738, i32 2
  store ptr %t2729, ptr %t2742
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2735
reuse.join.2735:
  %t2743 = phi ptr [ %t5, %reuse.in_place.2733 ], [ %t2738, %reuse.copy.2734 ]
  %t2744 = call ptr @__alloc(i64 16, i32 1)
  %t2745 = inttoptr i64 307 to ptr
  %t2746 = getelementptr ptr, ptr %t2744, i32 0
  store ptr %t2745, ptr %t2746
  call void @__inc_ref(ptr %t6)
  %t2747 = getelementptr ptr, ptr %t2744, i32 1
  store ptr %t6, ptr %t2747
  call void @__free_recursive(ptr %t6)
  store ptr %t2743, ptr %t3
  store ptr %t2744, ptr %t4
  br label %tco.loop.0
tco.case.arm.162.2748:
  %t2749 = getelementptr ptr, ptr %t5, i32 1
  %t2750 = load ptr, ptr %t2749
  call void @__inc_ref(ptr %t2750)
  %t2751 = getelementptr ptr, ptr %t5, i32 2
  %t2752 = load ptr, ptr %t2751
  call void @__inc_ref(ptr %t2752)
  %t2753 = getelementptr ptr, ptr %t5, i32 3
  %t2754 = load ptr, ptr %t2753
  call void @__inc_ref(ptr %t2754)
  %t2755 = call ptr @__alloc(i64 24, i32 2)
  %t2756 = inttoptr i64 114 to ptr
  %t2757 = getelementptr ptr, ptr %t2755, i32 0
  store ptr %t2756, ptr %t2757
  call void @__inc_ref(ptr %t2750)
  %t2758 = getelementptr ptr, ptr %t2755, i32 1
  store ptr %t2750, ptr %t2758
  call void @__inc_ref(ptr %t2752)
  %t2759 = getelementptr ptr, ptr %t2755, i32 2
  store ptr %t2752, ptr %t2759
  %t2760 = call ptr @__alloc(i64 24, i32 2)
  %t2761 = inttoptr i64 308 to ptr
  %t2762 = getelementptr ptr, ptr %t2760, i32 0
  store ptr %t2761, ptr %t2762
  call void @__inc_ref(ptr %t6)
  %t2763 = getelementptr ptr, ptr %t2760, i32 1
  store ptr %t6, ptr %t2763
  call void @__inc_ref(ptr %t2754)
  %t2764 = getelementptr ptr, ptr %t2760, i32 2
  store ptr %t2754, ptr %t2764
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t2754)
  call void @__free_recursive(ptr %t2752)
  call void @__free_recursive(ptr %t2750)
  store ptr %t2755, ptr %t3
  store ptr %t2760, ptr %t4
  br label %tco.loop.0
tco.case.arm.163.2765:
  %t2766 = getelementptr ptr, ptr %t5, i32 1
  %t2767 = load ptr, ptr %t2766
  %t2768 = getelementptr ptr, ptr %t5, i32 2
  %t2769 = load ptr, ptr %t2768
  %t2770 = getelementptr i8, ptr %t5, i64 -8
  %t2771 = load i32, ptr %t2770
  %t2772 = icmp eq i32 %t2771, 1
  br i1 %t2772, label %reuse.in_place.2773, label %reuse.copy.2774
reuse.in_place.2773:
  %t2776 = inttoptr i64 114 to ptr
  %t2777 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2776, ptr %t2777
  br label %reuse.join.2775
reuse.copy.2774:
  %t2778 = call ptr @__alloc(i64 24, i32 2)
  %t2779 = inttoptr i64 114 to ptr
  %t2780 = getelementptr ptr, ptr %t2778, i32 0
  store ptr %t2779, ptr %t2780
  call void @__inc_ref(ptr %t2767)
  %t2781 = getelementptr ptr, ptr %t2778, i32 1
  store ptr %t2767, ptr %t2781
  call void @__inc_ref(ptr %t2769)
  %t2782 = getelementptr ptr, ptr %t2778, i32 2
  store ptr %t2769, ptr %t2782
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2775
reuse.join.2775:
  %t2783 = phi ptr [ %t5, %reuse.in_place.2773 ], [ %t2778, %reuse.copy.2774 ]
  %t2784 = call ptr @__alloc(i64 16, i32 1)
  %t2785 = inttoptr i64 309 to ptr
  %t2786 = getelementptr ptr, ptr %t2784, i32 0
  store ptr %t2785, ptr %t2786
  call void @__inc_ref(ptr %t6)
  %t2787 = getelementptr ptr, ptr %t2784, i32 1
  store ptr %t6, ptr %t2787
  call void @__free_recursive(ptr %t6)
  store ptr %t2783, ptr %t3
  store ptr %t2784, ptr %t4
  br label %tco.loop.0
tco.case.arm.164.2788:
  %t2789 = getelementptr ptr, ptr %t5, i32 1
  %t2790 = load ptr, ptr %t2789
  %t2791 = getelementptr ptr, ptr %t5, i32 2
  %t2792 = load ptr, ptr %t2791
  %t2793 = getelementptr i8, ptr %t5, i64 -8
  %t2794 = load i32, ptr %t2793
  %t2795 = icmp eq i32 %t2794, 1
  br i1 %t2795, label %reuse.in_place.2796, label %reuse.copy.2797
reuse.in_place.2796:
  %t2799 = inttoptr i64 114 to ptr
  %t2800 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2799, ptr %t2800
  br label %reuse.join.2798
reuse.copy.2797:
  %t2801 = call ptr @__alloc(i64 24, i32 2)
  %t2802 = inttoptr i64 114 to ptr
  %t2803 = getelementptr ptr, ptr %t2801, i32 0
  store ptr %t2802, ptr %t2803
  call void @__inc_ref(ptr %t2790)
  %t2804 = getelementptr ptr, ptr %t2801, i32 1
  store ptr %t2790, ptr %t2804
  call void @__inc_ref(ptr %t2792)
  %t2805 = getelementptr ptr, ptr %t2801, i32 2
  store ptr %t2792, ptr %t2805
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2798
reuse.join.2798:
  %t2806 = phi ptr [ %t5, %reuse.in_place.2796 ], [ %t2801, %reuse.copy.2797 ]
  %t2807 = call ptr @__alloc(i64 16, i32 1)
  %t2808 = inttoptr i64 310 to ptr
  %t2809 = getelementptr ptr, ptr %t2807, i32 0
  store ptr %t2808, ptr %t2809
  call void @__inc_ref(ptr %t6)
  %t2810 = getelementptr ptr, ptr %t2807, i32 1
  store ptr %t6, ptr %t2810
  call void @__free_recursive(ptr %t6)
  store ptr %t2806, ptr %t3
  store ptr %t2807, ptr %t4
  br label %tco.loop.0
tco.case.arm.165.2811:
  %t2812 = getelementptr ptr, ptr %t5, i32 1
  %t2813 = load ptr, ptr %t2812
  %t2814 = getelementptr ptr, ptr %t5, i32 2
  %t2815 = load ptr, ptr %t2814
  %t2816 = getelementptr i8, ptr %t5, i64 -8
  %t2817 = load i32, ptr %t2816
  %t2818 = icmp eq i32 %t2817, 1
  br i1 %t2818, label %reuse.in_place.2819, label %reuse.copy.2820
reuse.in_place.2819:
  %t2822 = inttoptr i64 114 to ptr
  %t2823 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2822, ptr %t2823
  br label %reuse.join.2821
reuse.copy.2820:
  %t2824 = call ptr @__alloc(i64 24, i32 2)
  %t2825 = inttoptr i64 114 to ptr
  %t2826 = getelementptr ptr, ptr %t2824, i32 0
  store ptr %t2825, ptr %t2826
  call void @__inc_ref(ptr %t2813)
  %t2827 = getelementptr ptr, ptr %t2824, i32 1
  store ptr %t2813, ptr %t2827
  call void @__inc_ref(ptr %t2815)
  %t2828 = getelementptr ptr, ptr %t2824, i32 2
  store ptr %t2815, ptr %t2828
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2821
reuse.join.2821:
  %t2829 = phi ptr [ %t5, %reuse.in_place.2819 ], [ %t2824, %reuse.copy.2820 ]
  %t2830 = call ptr @__alloc(i64 16, i32 1)
  %t2831 = inttoptr i64 311 to ptr
  %t2832 = getelementptr ptr, ptr %t2830, i32 0
  store ptr %t2831, ptr %t2832
  call void @__inc_ref(ptr %t6)
  %t2833 = getelementptr ptr, ptr %t2830, i32 1
  store ptr %t6, ptr %t2833
  call void @__free_recursive(ptr %t6)
  store ptr %t2829, ptr %t3
  store ptr %t2830, ptr %t4
  br label %tco.loop.0
tco.case.arm.166.2834:
  %t2835 = getelementptr ptr, ptr %t5, i32 1
  %t2836 = load ptr, ptr %t2835
  %t2837 = getelementptr ptr, ptr %t5, i32 2
  %t2838 = load ptr, ptr %t2837
  %t2839 = getelementptr i8, ptr %t5, i64 -8
  %t2840 = load i32, ptr %t2839
  %t2841 = icmp eq i32 %t2840, 1
  br i1 %t2841, label %reuse.in_place.2842, label %reuse.copy.2843
reuse.in_place.2842:
  %t2845 = inttoptr i64 114 to ptr
  %t2846 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2845, ptr %t2846
  br label %reuse.join.2844
reuse.copy.2843:
  %t2847 = call ptr @__alloc(i64 24, i32 2)
  %t2848 = inttoptr i64 114 to ptr
  %t2849 = getelementptr ptr, ptr %t2847, i32 0
  store ptr %t2848, ptr %t2849
  call void @__inc_ref(ptr %t2836)
  %t2850 = getelementptr ptr, ptr %t2847, i32 1
  store ptr %t2836, ptr %t2850
  call void @__inc_ref(ptr %t2838)
  %t2851 = getelementptr ptr, ptr %t2847, i32 2
  store ptr %t2838, ptr %t2851
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2844
reuse.join.2844:
  %t2852 = phi ptr [ %t5, %reuse.in_place.2842 ], [ %t2847, %reuse.copy.2843 ]
  %t2853 = call ptr @__alloc(i64 16, i32 1)
  %t2854 = inttoptr i64 312 to ptr
  %t2855 = getelementptr ptr, ptr %t2853, i32 0
  store ptr %t2854, ptr %t2855
  call void @__inc_ref(ptr %t6)
  %t2856 = getelementptr ptr, ptr %t2853, i32 1
  store ptr %t6, ptr %t2856
  call void @__free_recursive(ptr %t6)
  store ptr %t2852, ptr %t3
  store ptr %t2853, ptr %t4
  br label %tco.loop.0
tco.case.arm.167.2857:
  %t2858 = getelementptr ptr, ptr %t5, i32 1
  %t2859 = load ptr, ptr %t2858
  %t2860 = getelementptr ptr, ptr %t5, i32 2
  %t2861 = load ptr, ptr %t2860
  %t2862 = getelementptr i8, ptr %t5, i64 -8
  %t2863 = load i32, ptr %t2862
  %t2864 = icmp eq i32 %t2863, 1
  br i1 %t2864, label %reuse.in_place.2865, label %reuse.copy.2866
reuse.in_place.2865:
  %t2868 = inttoptr i64 114 to ptr
  %t2869 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2868, ptr %t2869
  br label %reuse.join.2867
reuse.copy.2866:
  %t2870 = call ptr @__alloc(i64 24, i32 2)
  %t2871 = inttoptr i64 114 to ptr
  %t2872 = getelementptr ptr, ptr %t2870, i32 0
  store ptr %t2871, ptr %t2872
  call void @__inc_ref(ptr %t2859)
  %t2873 = getelementptr ptr, ptr %t2870, i32 1
  store ptr %t2859, ptr %t2873
  call void @__inc_ref(ptr %t2861)
  %t2874 = getelementptr ptr, ptr %t2870, i32 2
  store ptr %t2861, ptr %t2874
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2867
reuse.join.2867:
  %t2875 = phi ptr [ %t5, %reuse.in_place.2865 ], [ %t2870, %reuse.copy.2866 ]
  %t2876 = call ptr @__alloc(i64 16, i32 1)
  %t2877 = inttoptr i64 313 to ptr
  %t2878 = getelementptr ptr, ptr %t2876, i32 0
  store ptr %t2877, ptr %t2878
  call void @__inc_ref(ptr %t6)
  %t2879 = getelementptr ptr, ptr %t2876, i32 1
  store ptr %t6, ptr %t2879
  call void @__free_recursive(ptr %t6)
  store ptr %t2875, ptr %t3
  store ptr %t2876, ptr %t4
  br label %tco.loop.0
tco.case.arm.168.2880:
  %t2881 = getelementptr ptr, ptr %t5, i32 1
  %t2882 = load ptr, ptr %t2881
  %t2883 = getelementptr ptr, ptr %t5, i32 2
  %t2884 = load ptr, ptr %t2883
  %t2885 = getelementptr i8, ptr %t5, i64 -8
  %t2886 = load i32, ptr %t2885
  %t2887 = icmp eq i32 %t2886, 1
  br i1 %t2887, label %reuse.in_place.2888, label %reuse.copy.2889
reuse.in_place.2888:
  %t2891 = inttoptr i64 114 to ptr
  %t2892 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2891, ptr %t2892
  br label %reuse.join.2890
reuse.copy.2889:
  %t2893 = call ptr @__alloc(i64 24, i32 2)
  %t2894 = inttoptr i64 114 to ptr
  %t2895 = getelementptr ptr, ptr %t2893, i32 0
  store ptr %t2894, ptr %t2895
  call void @__inc_ref(ptr %t2882)
  %t2896 = getelementptr ptr, ptr %t2893, i32 1
  store ptr %t2882, ptr %t2896
  call void @__inc_ref(ptr %t2884)
  %t2897 = getelementptr ptr, ptr %t2893, i32 2
  store ptr %t2884, ptr %t2897
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2890
reuse.join.2890:
  %t2898 = phi ptr [ %t5, %reuse.in_place.2888 ], [ %t2893, %reuse.copy.2889 ]
  %t2899 = call ptr @__alloc(i64 16, i32 1)
  %t2900 = inttoptr i64 314 to ptr
  %t2901 = getelementptr ptr, ptr %t2899, i32 0
  store ptr %t2900, ptr %t2901
  call void @__inc_ref(ptr %t6)
  %t2902 = getelementptr ptr, ptr %t2899, i32 1
  store ptr %t6, ptr %t2902
  call void @__free_recursive(ptr %t6)
  store ptr %t2898, ptr %t3
  store ptr %t2899, ptr %t4
  br label %tco.loop.0
tco.case.arm.169.2903:
  %t2904 = getelementptr ptr, ptr %t5, i32 1
  %t2905 = load ptr, ptr %t2904
  %t2906 = getelementptr ptr, ptr %t5, i32 2
  %t2907 = load ptr, ptr %t2906
  %t2908 = getelementptr i8, ptr %t5, i64 -8
  %t2909 = load i32, ptr %t2908
  %t2910 = icmp eq i32 %t2909, 1
  br i1 %t2910, label %reuse.in_place.2911, label %reuse.copy.2912
reuse.in_place.2911:
  %t2914 = inttoptr i64 114 to ptr
  %t2915 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2914, ptr %t2915
  br label %reuse.join.2913
reuse.copy.2912:
  %t2916 = call ptr @__alloc(i64 24, i32 2)
  %t2917 = inttoptr i64 114 to ptr
  %t2918 = getelementptr ptr, ptr %t2916, i32 0
  store ptr %t2917, ptr %t2918
  call void @__inc_ref(ptr %t2905)
  %t2919 = getelementptr ptr, ptr %t2916, i32 1
  store ptr %t2905, ptr %t2919
  call void @__inc_ref(ptr %t2907)
  %t2920 = getelementptr ptr, ptr %t2916, i32 2
  store ptr %t2907, ptr %t2920
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2913
reuse.join.2913:
  %t2921 = phi ptr [ %t5, %reuse.in_place.2911 ], [ %t2916, %reuse.copy.2912 ]
  %t2922 = call ptr @__alloc(i64 16, i32 1)
  %t2923 = inttoptr i64 315 to ptr
  %t2924 = getelementptr ptr, ptr %t2922, i32 0
  store ptr %t2923, ptr %t2924
  call void @__inc_ref(ptr %t6)
  %t2925 = getelementptr ptr, ptr %t2922, i32 1
  store ptr %t6, ptr %t2925
  call void @__free_recursive(ptr %t6)
  store ptr %t2921, ptr %t3
  store ptr %t2922, ptr %t4
  br label %tco.loop.0
tco.case.arm.170.2926:
  %t2927 = getelementptr ptr, ptr %t5, i32 1
  %t2928 = load ptr, ptr %t2927
  %t2929 = getelementptr ptr, ptr %t5, i32 2
  %t2930 = load ptr, ptr %t2929
  %t2931 = getelementptr i8, ptr %t5, i64 -8
  %t2932 = load i32, ptr %t2931
  %t2933 = icmp eq i32 %t2932, 1
  br i1 %t2933, label %reuse.in_place.2934, label %reuse.copy.2935
reuse.in_place.2934:
  %t2937 = inttoptr i64 114 to ptr
  %t2938 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2937, ptr %t2938
  br label %reuse.join.2936
reuse.copy.2935:
  %t2939 = call ptr @__alloc(i64 24, i32 2)
  %t2940 = inttoptr i64 114 to ptr
  %t2941 = getelementptr ptr, ptr %t2939, i32 0
  store ptr %t2940, ptr %t2941
  call void @__inc_ref(ptr %t2928)
  %t2942 = getelementptr ptr, ptr %t2939, i32 1
  store ptr %t2928, ptr %t2942
  call void @__inc_ref(ptr %t2930)
  %t2943 = getelementptr ptr, ptr %t2939, i32 2
  store ptr %t2930, ptr %t2943
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2936
reuse.join.2936:
  %t2944 = phi ptr [ %t5, %reuse.in_place.2934 ], [ %t2939, %reuse.copy.2935 ]
  %t2945 = call ptr @__alloc(i64 16, i32 1)
  %t2946 = inttoptr i64 316 to ptr
  %t2947 = getelementptr ptr, ptr %t2945, i32 0
  store ptr %t2946, ptr %t2947
  call void @__inc_ref(ptr %t6)
  %t2948 = getelementptr ptr, ptr %t2945, i32 1
  store ptr %t6, ptr %t2948
  call void @__free_recursive(ptr %t6)
  store ptr %t2944, ptr %t3
  store ptr %t2945, ptr %t4
  br label %tco.loop.0
tco.case.arm.171.2949:
  %t2950 = getelementptr ptr, ptr %t5, i32 1
  %t2951 = load ptr, ptr %t2950
  %t2952 = getelementptr ptr, ptr %t5, i32 2
  %t2953 = load ptr, ptr %t2952
  %t2954 = getelementptr i8, ptr %t5, i64 -8
  %t2955 = load i32, ptr %t2954
  %t2956 = icmp eq i32 %t2955, 1
  br i1 %t2956, label %reuse.in_place.2957, label %reuse.copy.2958
reuse.in_place.2957:
  %t2960 = inttoptr i64 114 to ptr
  %t2961 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2960, ptr %t2961
  br label %reuse.join.2959
reuse.copy.2958:
  %t2962 = call ptr @__alloc(i64 24, i32 2)
  %t2963 = inttoptr i64 114 to ptr
  %t2964 = getelementptr ptr, ptr %t2962, i32 0
  store ptr %t2963, ptr %t2964
  call void @__inc_ref(ptr %t2951)
  %t2965 = getelementptr ptr, ptr %t2962, i32 1
  store ptr %t2951, ptr %t2965
  call void @__inc_ref(ptr %t2953)
  %t2966 = getelementptr ptr, ptr %t2962, i32 2
  store ptr %t2953, ptr %t2966
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2959
reuse.join.2959:
  %t2967 = phi ptr [ %t5, %reuse.in_place.2957 ], [ %t2962, %reuse.copy.2958 ]
  %t2968 = call ptr @__alloc(i64 16, i32 1)
  %t2969 = inttoptr i64 317 to ptr
  %t2970 = getelementptr ptr, ptr %t2968, i32 0
  store ptr %t2969, ptr %t2970
  call void @__inc_ref(ptr %t6)
  %t2971 = getelementptr ptr, ptr %t2968, i32 1
  store ptr %t6, ptr %t2971
  call void @__free_recursive(ptr %t6)
  store ptr %t2967, ptr %t3
  store ptr %t2968, ptr %t4
  br label %tco.loop.0
tco.case.arm.172.2972:
  %t2973 = getelementptr ptr, ptr %t5, i32 1
  %t2974 = load ptr, ptr %t2973
  %t2975 = getelementptr ptr, ptr %t5, i32 2
  %t2976 = load ptr, ptr %t2975
  %t2977 = getelementptr i8, ptr %t5, i64 -8
  %t2978 = load i32, ptr %t2977
  %t2979 = icmp eq i32 %t2978, 1
  br i1 %t2979, label %reuse.in_place.2980, label %reuse.copy.2981
reuse.in_place.2980:
  %t2983 = inttoptr i64 114 to ptr
  %t2984 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2983, ptr %t2984
  br label %reuse.join.2982
reuse.copy.2981:
  %t2985 = call ptr @__alloc(i64 24, i32 2)
  %t2986 = inttoptr i64 114 to ptr
  %t2987 = getelementptr ptr, ptr %t2985, i32 0
  store ptr %t2986, ptr %t2987
  call void @__inc_ref(ptr %t2974)
  %t2988 = getelementptr ptr, ptr %t2985, i32 1
  store ptr %t2974, ptr %t2988
  call void @__inc_ref(ptr %t2976)
  %t2989 = getelementptr ptr, ptr %t2985, i32 2
  store ptr %t2976, ptr %t2989
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2982
reuse.join.2982:
  %t2990 = phi ptr [ %t5, %reuse.in_place.2980 ], [ %t2985, %reuse.copy.2981 ]
  %t2991 = call ptr @__alloc(i64 16, i32 1)
  %t2992 = inttoptr i64 318 to ptr
  %t2993 = getelementptr ptr, ptr %t2991, i32 0
  store ptr %t2992, ptr %t2993
  call void @__inc_ref(ptr %t6)
  %t2994 = getelementptr ptr, ptr %t2991, i32 1
  store ptr %t6, ptr %t2994
  call void @__free_recursive(ptr %t6)
  store ptr %t2990, ptr %t3
  store ptr %t2991, ptr %t4
  br label %tco.loop.0
tco.case.arm.173.2995:
  %t2996 = getelementptr ptr, ptr %t5, i32 1
  %t2997 = load ptr, ptr %t2996
  %t2998 = getelementptr ptr, ptr %t5, i32 2
  %t2999 = load ptr, ptr %t2998
  %t3000 = getelementptr i8, ptr %t5, i64 -8
  %t3001 = load i32, ptr %t3000
  %t3002 = icmp eq i32 %t3001, 1
  br i1 %t3002, label %reuse.in_place.3003, label %reuse.copy.3004
reuse.in_place.3003:
  %t3006 = inttoptr i64 114 to ptr
  %t3007 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3006, ptr %t3007
  br label %reuse.join.3005
reuse.copy.3004:
  %t3008 = call ptr @__alloc(i64 24, i32 2)
  %t3009 = inttoptr i64 114 to ptr
  %t3010 = getelementptr ptr, ptr %t3008, i32 0
  store ptr %t3009, ptr %t3010
  call void @__inc_ref(ptr %t2997)
  %t3011 = getelementptr ptr, ptr %t3008, i32 1
  store ptr %t2997, ptr %t3011
  call void @__inc_ref(ptr %t2999)
  %t3012 = getelementptr ptr, ptr %t3008, i32 2
  store ptr %t2999, ptr %t3012
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3005
reuse.join.3005:
  %t3013 = phi ptr [ %t5, %reuse.in_place.3003 ], [ %t3008, %reuse.copy.3004 ]
  %t3014 = call ptr @__alloc(i64 16, i32 1)
  %t3015 = inttoptr i64 319 to ptr
  %t3016 = getelementptr ptr, ptr %t3014, i32 0
  store ptr %t3015, ptr %t3016
  call void @__inc_ref(ptr %t6)
  %t3017 = getelementptr ptr, ptr %t3014, i32 1
  store ptr %t6, ptr %t3017
  call void @__free_recursive(ptr %t6)
  store ptr %t3013, ptr %t3
  store ptr %t3014, ptr %t4
  br label %tco.loop.0
tco.case.arm.174.3018:
  %t3019 = getelementptr ptr, ptr %t5, i32 1
  %t3020 = load ptr, ptr %t3019
  %t3021 = getelementptr ptr, ptr %t5, i32 2
  %t3022 = load ptr, ptr %t3021
  %t3023 = getelementptr i8, ptr %t5, i64 -8
  %t3024 = load i32, ptr %t3023
  %t3025 = icmp eq i32 %t3024, 1
  br i1 %t3025, label %reuse.in_place.3026, label %reuse.copy.3027
reuse.in_place.3026:
  %t3029 = inttoptr i64 114 to ptr
  %t3030 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3029, ptr %t3030
  br label %reuse.join.3028
reuse.copy.3027:
  %t3031 = call ptr @__alloc(i64 24, i32 2)
  %t3032 = inttoptr i64 114 to ptr
  %t3033 = getelementptr ptr, ptr %t3031, i32 0
  store ptr %t3032, ptr %t3033
  call void @__inc_ref(ptr %t3020)
  %t3034 = getelementptr ptr, ptr %t3031, i32 1
  store ptr %t3020, ptr %t3034
  call void @__inc_ref(ptr %t3022)
  %t3035 = getelementptr ptr, ptr %t3031, i32 2
  store ptr %t3022, ptr %t3035
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3028
reuse.join.3028:
  %t3036 = phi ptr [ %t5, %reuse.in_place.3026 ], [ %t3031, %reuse.copy.3027 ]
  %t3037 = call ptr @__alloc(i64 16, i32 1)
  %t3038 = inttoptr i64 320 to ptr
  %t3039 = getelementptr ptr, ptr %t3037, i32 0
  store ptr %t3038, ptr %t3039
  call void @__inc_ref(ptr %t6)
  %t3040 = getelementptr ptr, ptr %t3037, i32 1
  store ptr %t6, ptr %t3040
  call void @__free_recursive(ptr %t6)
  store ptr %t3036, ptr %t3
  store ptr %t3037, ptr %t4
  br label %tco.loop.0
tco.case.arm.175.3041:
  %t3042 = getelementptr ptr, ptr %t5, i32 1
  %t3043 = load ptr, ptr %t3042
  call void @__inc_ref(ptr %t3043)
  %t3044 = getelementptr ptr, ptr %t5, i32 2
  %t3045 = load ptr, ptr %t3044
  call void @__inc_ref(ptr %t3045)
  %t3046 = getelementptr ptr, ptr %t5, i32 3
  %t3047 = load ptr, ptr %t3046
  call void @__inc_ref(ptr %t3047)
  %t3048 = call ptr @__alloc(i64 24, i32 2)
  %t3049 = inttoptr i64 114 to ptr
  %t3050 = getelementptr ptr, ptr %t3048, i32 0
  store ptr %t3049, ptr %t3050
  call void @__inc_ref(ptr %t3043)
  %t3051 = getelementptr ptr, ptr %t3048, i32 1
  store ptr %t3043, ptr %t3051
  call void @__inc_ref(ptr %t3045)
  %t3052 = getelementptr ptr, ptr %t3048, i32 2
  store ptr %t3045, ptr %t3052
  %t3053 = call ptr @__alloc(i64 24, i32 2)
  %t3054 = inttoptr i64 321 to ptr
  %t3055 = getelementptr ptr, ptr %t3053, i32 0
  store ptr %t3054, ptr %t3055
  call void @__inc_ref(ptr %t6)
  %t3056 = getelementptr ptr, ptr %t3053, i32 1
  store ptr %t6, ptr %t3056
  call void @__inc_ref(ptr %t3047)
  %t3057 = getelementptr ptr, ptr %t3053, i32 2
  store ptr %t3047, ptr %t3057
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t3047)
  call void @__free_recursive(ptr %t3045)
  call void @__free_recursive(ptr %t3043)
  store ptr %t3048, ptr %t3
  store ptr %t3053, ptr %t4
  br label %tco.loop.0
tco.case.arm.176.3058:
  %t3059 = getelementptr ptr, ptr %t5, i32 1
  %t3060 = load ptr, ptr %t3059
  %t3061 = getelementptr ptr, ptr %t5, i32 2
  %t3062 = load ptr, ptr %t3061
  %t3063 = getelementptr i8, ptr %t5, i64 -8
  %t3064 = load i32, ptr %t3063
  %t3065 = icmp eq i32 %t3064, 1
  br i1 %t3065, label %reuse.in_place.3066, label %reuse.copy.3067
reuse.in_place.3066:
  %t3069 = inttoptr i64 114 to ptr
  %t3070 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3069, ptr %t3070
  br label %reuse.join.3068
reuse.copy.3067:
  %t3071 = call ptr @__alloc(i64 24, i32 2)
  %t3072 = inttoptr i64 114 to ptr
  %t3073 = getelementptr ptr, ptr %t3071, i32 0
  store ptr %t3072, ptr %t3073
  call void @__inc_ref(ptr %t3060)
  %t3074 = getelementptr ptr, ptr %t3071, i32 1
  store ptr %t3060, ptr %t3074
  call void @__inc_ref(ptr %t3062)
  %t3075 = getelementptr ptr, ptr %t3071, i32 2
  store ptr %t3062, ptr %t3075
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3068
reuse.join.3068:
  %t3076 = phi ptr [ %t5, %reuse.in_place.3066 ], [ %t3071, %reuse.copy.3067 ]
  %t3077 = call ptr @__alloc(i64 16, i32 1)
  %t3078 = inttoptr i64 322 to ptr
  %t3079 = getelementptr ptr, ptr %t3077, i32 0
  store ptr %t3078, ptr %t3079
  call void @__inc_ref(ptr %t6)
  %t3080 = getelementptr ptr, ptr %t3077, i32 1
  store ptr %t6, ptr %t3080
  call void @__free_recursive(ptr %t6)
  store ptr %t3076, ptr %t3
  store ptr %t3077, ptr %t4
  br label %tco.loop.0
tco.case.arm.177.3081:
  %t3082 = getelementptr ptr, ptr %t5, i32 1
  %t3083 = load ptr, ptr %t3082
  %t3084 = getelementptr ptr, ptr %t5, i32 2
  %t3085 = load ptr, ptr %t3084
  %t3086 = getelementptr i8, ptr %t5, i64 -8
  %t3087 = load i32, ptr %t3086
  %t3088 = icmp eq i32 %t3087, 1
  br i1 %t3088, label %reuse.in_place.3089, label %reuse.copy.3090
reuse.in_place.3089:
  %t3092 = inttoptr i64 114 to ptr
  %t3093 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3092, ptr %t3093
  br label %reuse.join.3091
reuse.copy.3090:
  %t3094 = call ptr @__alloc(i64 24, i32 2)
  %t3095 = inttoptr i64 114 to ptr
  %t3096 = getelementptr ptr, ptr %t3094, i32 0
  store ptr %t3095, ptr %t3096
  call void @__inc_ref(ptr %t3083)
  %t3097 = getelementptr ptr, ptr %t3094, i32 1
  store ptr %t3083, ptr %t3097
  call void @__inc_ref(ptr %t3085)
  %t3098 = getelementptr ptr, ptr %t3094, i32 2
  store ptr %t3085, ptr %t3098
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3091
reuse.join.3091:
  %t3099 = phi ptr [ %t5, %reuse.in_place.3089 ], [ %t3094, %reuse.copy.3090 ]
  %t3100 = call ptr @__alloc(i64 16, i32 1)
  %t3101 = inttoptr i64 323 to ptr
  %t3102 = getelementptr ptr, ptr %t3100, i32 0
  store ptr %t3101, ptr %t3102
  call void @__inc_ref(ptr %t6)
  %t3103 = getelementptr ptr, ptr %t3100, i32 1
  store ptr %t6, ptr %t3103
  call void @__free_recursive(ptr %t6)
  store ptr %t3099, ptr %t3
  store ptr %t3100, ptr %t4
  br label %tco.loop.0
tco.case.arm.178.3104:
  %t3105 = getelementptr ptr, ptr %t5, i32 1
  %t3106 = load ptr, ptr %t3105
  %t3107 = getelementptr ptr, ptr %t5, i32 2
  %t3108 = load ptr, ptr %t3107
  %t3109 = getelementptr i8, ptr %t5, i64 -8
  %t3110 = load i32, ptr %t3109
  %t3111 = icmp eq i32 %t3110, 1
  br i1 %t3111, label %reuse.in_place.3112, label %reuse.copy.3113
reuse.in_place.3112:
  %t3115 = inttoptr i64 114 to ptr
  %t3116 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3115, ptr %t3116
  br label %reuse.join.3114
reuse.copy.3113:
  %t3117 = call ptr @__alloc(i64 24, i32 2)
  %t3118 = inttoptr i64 114 to ptr
  %t3119 = getelementptr ptr, ptr %t3117, i32 0
  store ptr %t3118, ptr %t3119
  call void @__inc_ref(ptr %t3106)
  %t3120 = getelementptr ptr, ptr %t3117, i32 1
  store ptr %t3106, ptr %t3120
  call void @__inc_ref(ptr %t3108)
  %t3121 = getelementptr ptr, ptr %t3117, i32 2
  store ptr %t3108, ptr %t3121
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3114
reuse.join.3114:
  %t3122 = phi ptr [ %t5, %reuse.in_place.3112 ], [ %t3117, %reuse.copy.3113 ]
  %t3123 = call ptr @__alloc(i64 16, i32 1)
  %t3124 = inttoptr i64 324 to ptr
  %t3125 = getelementptr ptr, ptr %t3123, i32 0
  store ptr %t3124, ptr %t3125
  call void @__inc_ref(ptr %t6)
  %t3126 = getelementptr ptr, ptr %t3123, i32 1
  store ptr %t6, ptr %t3126
  call void @__free_recursive(ptr %t6)
  store ptr %t3122, ptr %t3
  store ptr %t3123, ptr %t4
  br label %tco.loop.0
tco.case.arm.179.3127:
  %t3128 = getelementptr ptr, ptr %t5, i32 1
  %t3129 = load ptr, ptr %t3128
  %t3130 = getelementptr ptr, ptr %t5, i32 2
  %t3131 = load ptr, ptr %t3130
  %t3132 = getelementptr i8, ptr %t5, i64 -8
  %t3133 = load i32, ptr %t3132
  %t3134 = icmp eq i32 %t3133, 1
  br i1 %t3134, label %reuse.in_place.3135, label %reuse.copy.3136
reuse.in_place.3135:
  %t3138 = inttoptr i64 114 to ptr
  %t3139 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3138, ptr %t3139
  br label %reuse.join.3137
reuse.copy.3136:
  %t3140 = call ptr @__alloc(i64 24, i32 2)
  %t3141 = inttoptr i64 114 to ptr
  %t3142 = getelementptr ptr, ptr %t3140, i32 0
  store ptr %t3141, ptr %t3142
  call void @__inc_ref(ptr %t3129)
  %t3143 = getelementptr ptr, ptr %t3140, i32 1
  store ptr %t3129, ptr %t3143
  call void @__inc_ref(ptr %t3131)
  %t3144 = getelementptr ptr, ptr %t3140, i32 2
  store ptr %t3131, ptr %t3144
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3137
reuse.join.3137:
  %t3145 = phi ptr [ %t5, %reuse.in_place.3135 ], [ %t3140, %reuse.copy.3136 ]
  %t3146 = call ptr @__alloc(i64 16, i32 1)
  %t3147 = inttoptr i64 325 to ptr
  %t3148 = getelementptr ptr, ptr %t3146, i32 0
  store ptr %t3147, ptr %t3148
  call void @__inc_ref(ptr %t6)
  %t3149 = getelementptr ptr, ptr %t3146, i32 1
  store ptr %t6, ptr %t3149
  call void @__free_recursive(ptr %t6)
  store ptr %t3145, ptr %t3
  store ptr %t3146, ptr %t4
  br label %tco.loop.0
tco.case.arm.180.3150:
  %t3151 = getelementptr ptr, ptr %t5, i32 1
  %t3152 = load ptr, ptr %t3151
  %t3153 = getelementptr ptr, ptr %t5, i32 2
  %t3154 = load ptr, ptr %t3153
  %t3155 = getelementptr i8, ptr %t5, i64 -8
  %t3156 = load i32, ptr %t3155
  %t3157 = icmp eq i32 %t3156, 1
  br i1 %t3157, label %reuse.in_place.3158, label %reuse.copy.3159
reuse.in_place.3158:
  %t3161 = inttoptr i64 114 to ptr
  %t3162 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3161, ptr %t3162
  br label %reuse.join.3160
reuse.copy.3159:
  %t3163 = call ptr @__alloc(i64 24, i32 2)
  %t3164 = inttoptr i64 114 to ptr
  %t3165 = getelementptr ptr, ptr %t3163, i32 0
  store ptr %t3164, ptr %t3165
  call void @__inc_ref(ptr %t3152)
  %t3166 = getelementptr ptr, ptr %t3163, i32 1
  store ptr %t3152, ptr %t3166
  call void @__inc_ref(ptr %t3154)
  %t3167 = getelementptr ptr, ptr %t3163, i32 2
  store ptr %t3154, ptr %t3167
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3160
reuse.join.3160:
  %t3168 = phi ptr [ %t5, %reuse.in_place.3158 ], [ %t3163, %reuse.copy.3159 ]
  %t3169 = call ptr @__alloc(i64 16, i32 1)
  %t3170 = inttoptr i64 326 to ptr
  %t3171 = getelementptr ptr, ptr %t3169, i32 0
  store ptr %t3170, ptr %t3171
  call void @__inc_ref(ptr %t6)
  %t3172 = getelementptr ptr, ptr %t3169, i32 1
  store ptr %t6, ptr %t3172
  call void @__free_recursive(ptr %t6)
  store ptr %t3168, ptr %t3
  store ptr %t3169, ptr %t4
  br label %tco.loop.0
tco.case.arm.181.3173:
  %t3174 = getelementptr ptr, ptr %t5, i32 1
  %t3175 = load ptr, ptr %t3174
  %t3176 = getelementptr ptr, ptr %t5, i32 2
  %t3177 = load ptr, ptr %t3176
  %t3178 = getelementptr i8, ptr %t5, i64 -8
  %t3179 = load i32, ptr %t3178
  %t3180 = icmp eq i32 %t3179, 1
  br i1 %t3180, label %reuse.in_place.3181, label %reuse.copy.3182
reuse.in_place.3181:
  %t3184 = inttoptr i64 114 to ptr
  %t3185 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3184, ptr %t3185
  br label %reuse.join.3183
reuse.copy.3182:
  %t3186 = call ptr @__alloc(i64 24, i32 2)
  %t3187 = inttoptr i64 114 to ptr
  %t3188 = getelementptr ptr, ptr %t3186, i32 0
  store ptr %t3187, ptr %t3188
  call void @__inc_ref(ptr %t3175)
  %t3189 = getelementptr ptr, ptr %t3186, i32 1
  store ptr %t3175, ptr %t3189
  call void @__inc_ref(ptr %t3177)
  %t3190 = getelementptr ptr, ptr %t3186, i32 2
  store ptr %t3177, ptr %t3190
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3183
reuse.join.3183:
  %t3191 = phi ptr [ %t5, %reuse.in_place.3181 ], [ %t3186, %reuse.copy.3182 ]
  %t3192 = call ptr @__alloc(i64 16, i32 1)
  %t3193 = inttoptr i64 327 to ptr
  %t3194 = getelementptr ptr, ptr %t3192, i32 0
  store ptr %t3193, ptr %t3194
  call void @__inc_ref(ptr %t6)
  %t3195 = getelementptr ptr, ptr %t3192, i32 1
  store ptr %t6, ptr %t3195
  call void @__free_recursive(ptr %t6)
  store ptr %t3191, ptr %t3
  store ptr %t3192, ptr %t4
  br label %tco.loop.0
tco.case.arm.182.3196:
  %t3197 = getelementptr ptr, ptr %t5, i32 1
  %t3198 = load ptr, ptr %t3197
  %t3199 = getelementptr ptr, ptr %t5, i32 2
  %t3200 = load ptr, ptr %t3199
  %t3201 = getelementptr i8, ptr %t5, i64 -8
  %t3202 = load i32, ptr %t3201
  %t3203 = icmp eq i32 %t3202, 1
  br i1 %t3203, label %reuse.in_place.3204, label %reuse.copy.3205
reuse.in_place.3204:
  %t3207 = inttoptr i64 114 to ptr
  %t3208 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3207, ptr %t3208
  br label %reuse.join.3206
reuse.copy.3205:
  %t3209 = call ptr @__alloc(i64 24, i32 2)
  %t3210 = inttoptr i64 114 to ptr
  %t3211 = getelementptr ptr, ptr %t3209, i32 0
  store ptr %t3210, ptr %t3211
  call void @__inc_ref(ptr %t3198)
  %t3212 = getelementptr ptr, ptr %t3209, i32 1
  store ptr %t3198, ptr %t3212
  call void @__inc_ref(ptr %t3200)
  %t3213 = getelementptr ptr, ptr %t3209, i32 2
  store ptr %t3200, ptr %t3213
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3206
reuse.join.3206:
  %t3214 = phi ptr [ %t5, %reuse.in_place.3204 ], [ %t3209, %reuse.copy.3205 ]
  %t3215 = call ptr @__alloc(i64 16, i32 1)
  %t3216 = inttoptr i64 328 to ptr
  %t3217 = getelementptr ptr, ptr %t3215, i32 0
  store ptr %t3216, ptr %t3217
  call void @__inc_ref(ptr %t6)
  %t3218 = getelementptr ptr, ptr %t3215, i32 1
  store ptr %t6, ptr %t3218
  call void @__free_recursive(ptr %t6)
  store ptr %t3214, ptr %t3
  store ptr %t3215, ptr %t4
  br label %tco.loop.0
tco.case.arm.183.3219:
  %t3220 = getelementptr ptr, ptr %t5, i32 1
  %t3221 = load ptr, ptr %t3220
  %t3222 = getelementptr ptr, ptr %t5, i32 2
  %t3223 = load ptr, ptr %t3222
  %t3224 = getelementptr i8, ptr %t5, i64 -8
  %t3225 = load i32, ptr %t3224
  %t3226 = icmp eq i32 %t3225, 1
  br i1 %t3226, label %reuse.in_place.3227, label %reuse.copy.3228
reuse.in_place.3227:
  %t3230 = inttoptr i64 114 to ptr
  %t3231 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3230, ptr %t3231
  br label %reuse.join.3229
reuse.copy.3228:
  %t3232 = call ptr @__alloc(i64 24, i32 2)
  %t3233 = inttoptr i64 114 to ptr
  %t3234 = getelementptr ptr, ptr %t3232, i32 0
  store ptr %t3233, ptr %t3234
  call void @__inc_ref(ptr %t3221)
  %t3235 = getelementptr ptr, ptr %t3232, i32 1
  store ptr %t3221, ptr %t3235
  call void @__inc_ref(ptr %t3223)
  %t3236 = getelementptr ptr, ptr %t3232, i32 2
  store ptr %t3223, ptr %t3236
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3229
reuse.join.3229:
  %t3237 = phi ptr [ %t5, %reuse.in_place.3227 ], [ %t3232, %reuse.copy.3228 ]
  %t3238 = call ptr @__alloc(i64 16, i32 1)
  %t3239 = inttoptr i64 329 to ptr
  %t3240 = getelementptr ptr, ptr %t3238, i32 0
  store ptr %t3239, ptr %t3240
  call void @__inc_ref(ptr %t6)
  %t3241 = getelementptr ptr, ptr %t3238, i32 1
  store ptr %t6, ptr %t3241
  call void @__free_recursive(ptr %t6)
  store ptr %t3237, ptr %t3
  store ptr %t3238, ptr %t4
  br label %tco.loop.0
tco.case.arm.184.3242:
  %t3243 = getelementptr ptr, ptr %t5, i32 1
  %t3244 = load ptr, ptr %t3243
  %t3245 = getelementptr ptr, ptr %t5, i32 2
  %t3246 = load ptr, ptr %t3245
  %t3247 = getelementptr i8, ptr %t5, i64 -8
  %t3248 = load i32, ptr %t3247
  %t3249 = icmp eq i32 %t3248, 1
  br i1 %t3249, label %reuse.in_place.3250, label %reuse.copy.3251
reuse.in_place.3250:
  %t3253 = inttoptr i64 114 to ptr
  %t3254 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3253, ptr %t3254
  br label %reuse.join.3252
reuse.copy.3251:
  %t3255 = call ptr @__alloc(i64 24, i32 2)
  %t3256 = inttoptr i64 114 to ptr
  %t3257 = getelementptr ptr, ptr %t3255, i32 0
  store ptr %t3256, ptr %t3257
  call void @__inc_ref(ptr %t3244)
  %t3258 = getelementptr ptr, ptr %t3255, i32 1
  store ptr %t3244, ptr %t3258
  call void @__inc_ref(ptr %t3246)
  %t3259 = getelementptr ptr, ptr %t3255, i32 2
  store ptr %t3246, ptr %t3259
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3252
reuse.join.3252:
  %t3260 = phi ptr [ %t5, %reuse.in_place.3250 ], [ %t3255, %reuse.copy.3251 ]
  %t3261 = call ptr @__alloc(i64 16, i32 1)
  %t3262 = inttoptr i64 330 to ptr
  %t3263 = getelementptr ptr, ptr %t3261, i32 0
  store ptr %t3262, ptr %t3263
  call void @__inc_ref(ptr %t6)
  %t3264 = getelementptr ptr, ptr %t3261, i32 1
  store ptr %t6, ptr %t3264
  call void @__free_recursive(ptr %t6)
  store ptr %t3260, ptr %t3
  store ptr %t3261, ptr %t4
  br label %tco.loop.0
tco.case.arm.185.3265:
  %t3266 = getelementptr ptr, ptr %t5, i32 1
  %t3267 = load ptr, ptr %t3266
  %t3268 = getelementptr ptr, ptr %t5, i32 2
  %t3269 = load ptr, ptr %t3268
  %t3270 = getelementptr i8, ptr %t5, i64 -8
  %t3271 = load i32, ptr %t3270
  %t3272 = icmp eq i32 %t3271, 1
  br i1 %t3272, label %reuse.in_place.3273, label %reuse.copy.3274
reuse.in_place.3273:
  %t3276 = inttoptr i64 114 to ptr
  %t3277 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3276, ptr %t3277
  br label %reuse.join.3275
reuse.copy.3274:
  %t3278 = call ptr @__alloc(i64 24, i32 2)
  %t3279 = inttoptr i64 114 to ptr
  %t3280 = getelementptr ptr, ptr %t3278, i32 0
  store ptr %t3279, ptr %t3280
  call void @__inc_ref(ptr %t3267)
  %t3281 = getelementptr ptr, ptr %t3278, i32 1
  store ptr %t3267, ptr %t3281
  call void @__inc_ref(ptr %t3269)
  %t3282 = getelementptr ptr, ptr %t3278, i32 2
  store ptr %t3269, ptr %t3282
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3275
reuse.join.3275:
  %t3283 = phi ptr [ %t5, %reuse.in_place.3273 ], [ %t3278, %reuse.copy.3274 ]
  %t3284 = call ptr @__alloc(i64 16, i32 1)
  %t3285 = inttoptr i64 331 to ptr
  %t3286 = getelementptr ptr, ptr %t3284, i32 0
  store ptr %t3285, ptr %t3286
  call void @__inc_ref(ptr %t6)
  %t3287 = getelementptr ptr, ptr %t3284, i32 1
  store ptr %t6, ptr %t3287
  call void @__free_recursive(ptr %t6)
  store ptr %t3283, ptr %t3
  store ptr %t3284, ptr %t4
  br label %tco.loop.0
tco.case.arm.186.3288:
  %t3289 = getelementptr ptr, ptr %t5, i32 1
  %t3290 = load ptr, ptr %t3289
  %t3291 = getelementptr ptr, ptr %t5, i32 2
  %t3292 = load ptr, ptr %t3291
  %t3293 = getelementptr i8, ptr %t5, i64 -8
  %t3294 = load i32, ptr %t3293
  %t3295 = icmp eq i32 %t3294, 1
  br i1 %t3295, label %reuse.in_place.3296, label %reuse.copy.3297
reuse.in_place.3296:
  %t3299 = inttoptr i64 114 to ptr
  %t3300 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3299, ptr %t3300
  br label %reuse.join.3298
reuse.copy.3297:
  %t3301 = call ptr @__alloc(i64 24, i32 2)
  %t3302 = inttoptr i64 114 to ptr
  %t3303 = getelementptr ptr, ptr %t3301, i32 0
  store ptr %t3302, ptr %t3303
  call void @__inc_ref(ptr %t3290)
  %t3304 = getelementptr ptr, ptr %t3301, i32 1
  store ptr %t3290, ptr %t3304
  call void @__inc_ref(ptr %t3292)
  %t3305 = getelementptr ptr, ptr %t3301, i32 2
  store ptr %t3292, ptr %t3305
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3298
reuse.join.3298:
  %t3306 = phi ptr [ %t5, %reuse.in_place.3296 ], [ %t3301, %reuse.copy.3297 ]
  %t3307 = call ptr @__alloc(i64 16, i32 1)
  %t3308 = inttoptr i64 332 to ptr
  %t3309 = getelementptr ptr, ptr %t3307, i32 0
  store ptr %t3308, ptr %t3309
  call void @__inc_ref(ptr %t6)
  %t3310 = getelementptr ptr, ptr %t3307, i32 1
  store ptr %t6, ptr %t3310
  call void @__free_recursive(ptr %t6)
  store ptr %t3306, ptr %t3
  store ptr %t3307, ptr %t4
  br label %tco.loop.0
tco.case.arm.187.3311:
  %t3312 = getelementptr ptr, ptr %t5, i32 1
  %t3313 = load ptr, ptr %t3312
  %t3314 = getelementptr ptr, ptr %t5, i32 2
  %t3315 = load ptr, ptr %t3314
  %t3316 = getelementptr i8, ptr %t5, i64 -8
  %t3317 = load i32, ptr %t3316
  %t3318 = icmp eq i32 %t3317, 1
  br i1 %t3318, label %reuse.in_place.3319, label %reuse.copy.3320
reuse.in_place.3319:
  %t3322 = inttoptr i64 114 to ptr
  %t3323 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3322, ptr %t3323
  br label %reuse.join.3321
reuse.copy.3320:
  %t3324 = call ptr @__alloc(i64 24, i32 2)
  %t3325 = inttoptr i64 114 to ptr
  %t3326 = getelementptr ptr, ptr %t3324, i32 0
  store ptr %t3325, ptr %t3326
  call void @__inc_ref(ptr %t3313)
  %t3327 = getelementptr ptr, ptr %t3324, i32 1
  store ptr %t3313, ptr %t3327
  call void @__inc_ref(ptr %t3315)
  %t3328 = getelementptr ptr, ptr %t3324, i32 2
  store ptr %t3315, ptr %t3328
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3321
reuse.join.3321:
  %t3329 = phi ptr [ %t5, %reuse.in_place.3319 ], [ %t3324, %reuse.copy.3320 ]
  %t3330 = call ptr @__alloc(i64 16, i32 1)
  %t3331 = inttoptr i64 333 to ptr
  %t3332 = getelementptr ptr, ptr %t3330, i32 0
  store ptr %t3331, ptr %t3332
  call void @__inc_ref(ptr %t6)
  %t3333 = getelementptr ptr, ptr %t3330, i32 1
  store ptr %t6, ptr %t3333
  call void @__free_recursive(ptr %t6)
  store ptr %t3329, ptr %t3
  store ptr %t3330, ptr %t4
  br label %tco.loop.0
tco.case.arm.188.3334:
  %t3335 = getelementptr ptr, ptr %t5, i32 1
  %t3336 = load ptr, ptr %t3335
  %t3337 = getelementptr ptr, ptr %t5, i32 2
  %t3338 = load ptr, ptr %t3337
  %t3339 = getelementptr i8, ptr %t5, i64 -8
  %t3340 = load i32, ptr %t3339
  %t3341 = icmp eq i32 %t3340, 1
  br i1 %t3341, label %reuse.in_place.3342, label %reuse.copy.3343
reuse.in_place.3342:
  %t3345 = inttoptr i64 114 to ptr
  %t3346 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3345, ptr %t3346
  br label %reuse.join.3344
reuse.copy.3343:
  %t3347 = call ptr @__alloc(i64 24, i32 2)
  %t3348 = inttoptr i64 114 to ptr
  %t3349 = getelementptr ptr, ptr %t3347, i32 0
  store ptr %t3348, ptr %t3349
  call void @__inc_ref(ptr %t3336)
  %t3350 = getelementptr ptr, ptr %t3347, i32 1
  store ptr %t3336, ptr %t3350
  call void @__inc_ref(ptr %t3338)
  %t3351 = getelementptr ptr, ptr %t3347, i32 2
  store ptr %t3338, ptr %t3351
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3344
reuse.join.3344:
  %t3352 = phi ptr [ %t5, %reuse.in_place.3342 ], [ %t3347, %reuse.copy.3343 ]
  %t3353 = call ptr @__alloc(i64 16, i32 1)
  %t3354 = inttoptr i64 334 to ptr
  %t3355 = getelementptr ptr, ptr %t3353, i32 0
  store ptr %t3354, ptr %t3355
  call void @__inc_ref(ptr %t6)
  %t3356 = getelementptr ptr, ptr %t3353, i32 1
  store ptr %t6, ptr %t3356
  call void @__free_recursive(ptr %t6)
  store ptr %t3352, ptr %t3
  store ptr %t3353, ptr %t4
  br label %tco.loop.0
tco.case.arm.189.3357:
  %t3358 = getelementptr ptr, ptr %t5, i32 1
  %t3359 = load ptr, ptr %t3358
  %t3360 = getelementptr ptr, ptr %t5, i32 2
  %t3361 = load ptr, ptr %t3360
  %t3362 = getelementptr i8, ptr %t5, i64 -8
  %t3363 = load i32, ptr %t3362
  %t3364 = icmp eq i32 %t3363, 1
  br i1 %t3364, label %reuse.in_place.3365, label %reuse.copy.3366
reuse.in_place.3365:
  %t3368 = inttoptr i64 114 to ptr
  %t3369 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3368, ptr %t3369
  br label %reuse.join.3367
reuse.copy.3366:
  %t3370 = call ptr @__alloc(i64 24, i32 2)
  %t3371 = inttoptr i64 114 to ptr
  %t3372 = getelementptr ptr, ptr %t3370, i32 0
  store ptr %t3371, ptr %t3372
  call void @__inc_ref(ptr %t3359)
  %t3373 = getelementptr ptr, ptr %t3370, i32 1
  store ptr %t3359, ptr %t3373
  call void @__inc_ref(ptr %t3361)
  %t3374 = getelementptr ptr, ptr %t3370, i32 2
  store ptr %t3361, ptr %t3374
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3367
reuse.join.3367:
  %t3375 = phi ptr [ %t5, %reuse.in_place.3365 ], [ %t3370, %reuse.copy.3366 ]
  %t3376 = call ptr @__alloc(i64 16, i32 1)
  %t3377 = inttoptr i64 335 to ptr
  %t3378 = getelementptr ptr, ptr %t3376, i32 0
  store ptr %t3377, ptr %t3378
  call void @__inc_ref(ptr %t6)
  %t3379 = getelementptr ptr, ptr %t3376, i32 1
  store ptr %t6, ptr %t3379
  call void @__free_recursive(ptr %t6)
  store ptr %t3375, ptr %t3
  store ptr %t3376, ptr %t4
  br label %tco.loop.0
tco.case.arm.190.3380:
  %t3381 = getelementptr ptr, ptr %t5, i32 1
  %t3382 = load ptr, ptr %t3381
  %t3383 = getelementptr ptr, ptr %t5, i32 2
  %t3384 = load ptr, ptr %t3383
  %t3385 = getelementptr i8, ptr %t5, i64 -8
  %t3386 = load i32, ptr %t3385
  %t3387 = icmp eq i32 %t3386, 1
  br i1 %t3387, label %reuse.in_place.3388, label %reuse.copy.3389
reuse.in_place.3388:
  %t3391 = inttoptr i64 114 to ptr
  %t3392 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3391, ptr %t3392
  br label %reuse.join.3390
reuse.copy.3389:
  %t3393 = call ptr @__alloc(i64 24, i32 2)
  %t3394 = inttoptr i64 114 to ptr
  %t3395 = getelementptr ptr, ptr %t3393, i32 0
  store ptr %t3394, ptr %t3395
  call void @__inc_ref(ptr %t3382)
  %t3396 = getelementptr ptr, ptr %t3393, i32 1
  store ptr %t3382, ptr %t3396
  call void @__inc_ref(ptr %t3384)
  %t3397 = getelementptr ptr, ptr %t3393, i32 2
  store ptr %t3384, ptr %t3397
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3390
reuse.join.3390:
  %t3398 = phi ptr [ %t5, %reuse.in_place.3388 ], [ %t3393, %reuse.copy.3389 ]
  %t3399 = call ptr @__alloc(i64 16, i32 1)
  %t3400 = inttoptr i64 336 to ptr
  %t3401 = getelementptr ptr, ptr %t3399, i32 0
  store ptr %t3400, ptr %t3401
  call void @__inc_ref(ptr %t6)
  %t3402 = getelementptr ptr, ptr %t3399, i32 1
  store ptr %t6, ptr %t3402
  call void @__free_recursive(ptr %t6)
  store ptr %t3398, ptr %t3
  store ptr %t3399, ptr %t4
  br label %tco.loop.0
tco.case.arm.191.3403:
  %t3404 = getelementptr ptr, ptr %t5, i32 1
  %t3405 = load ptr, ptr %t3404
  %t3406 = getelementptr ptr, ptr %t5, i32 2
  %t3407 = load ptr, ptr %t3406
  %t3408 = getelementptr i8, ptr %t5, i64 -8
  %t3409 = load i32, ptr %t3408
  %t3410 = icmp eq i32 %t3409, 1
  br i1 %t3410, label %reuse.in_place.3411, label %reuse.copy.3412
reuse.in_place.3411:
  %t3414 = inttoptr i64 114 to ptr
  %t3415 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3414, ptr %t3415
  br label %reuse.join.3413
reuse.copy.3412:
  %t3416 = call ptr @__alloc(i64 24, i32 2)
  %t3417 = inttoptr i64 114 to ptr
  %t3418 = getelementptr ptr, ptr %t3416, i32 0
  store ptr %t3417, ptr %t3418
  call void @__inc_ref(ptr %t3405)
  %t3419 = getelementptr ptr, ptr %t3416, i32 1
  store ptr %t3405, ptr %t3419
  call void @__inc_ref(ptr %t3407)
  %t3420 = getelementptr ptr, ptr %t3416, i32 2
  store ptr %t3407, ptr %t3420
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3413
reuse.join.3413:
  %t3421 = phi ptr [ %t5, %reuse.in_place.3411 ], [ %t3416, %reuse.copy.3412 ]
  %t3422 = call ptr @__alloc(i64 16, i32 1)
  %t3423 = inttoptr i64 337 to ptr
  %t3424 = getelementptr ptr, ptr %t3422, i32 0
  store ptr %t3423, ptr %t3424
  call void @__inc_ref(ptr %t6)
  %t3425 = getelementptr ptr, ptr %t3422, i32 1
  store ptr %t6, ptr %t3425
  call void @__free_recursive(ptr %t6)
  store ptr %t3421, ptr %t3
  store ptr %t3422, ptr %t4
  br label %tco.loop.0
tco.case.arm.192.3426:
  %t3427 = getelementptr ptr, ptr %t5, i32 1
  %t3428 = load ptr, ptr %t3427
  %t3429 = getelementptr ptr, ptr %t5, i32 2
  %t3430 = load ptr, ptr %t3429
  %t3431 = getelementptr i8, ptr %t5, i64 -8
  %t3432 = load i32, ptr %t3431
  %t3433 = icmp eq i32 %t3432, 1
  br i1 %t3433, label %reuse.in_place.3434, label %reuse.copy.3435
reuse.in_place.3434:
  %t3437 = inttoptr i64 114 to ptr
  %t3438 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3437, ptr %t3438
  br label %reuse.join.3436
reuse.copy.3435:
  %t3439 = call ptr @__alloc(i64 24, i32 2)
  %t3440 = inttoptr i64 114 to ptr
  %t3441 = getelementptr ptr, ptr %t3439, i32 0
  store ptr %t3440, ptr %t3441
  call void @__inc_ref(ptr %t3428)
  %t3442 = getelementptr ptr, ptr %t3439, i32 1
  store ptr %t3428, ptr %t3442
  call void @__inc_ref(ptr %t3430)
  %t3443 = getelementptr ptr, ptr %t3439, i32 2
  store ptr %t3430, ptr %t3443
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3436
reuse.join.3436:
  %t3444 = phi ptr [ %t5, %reuse.in_place.3434 ], [ %t3439, %reuse.copy.3435 ]
  %t3445 = call ptr @__alloc(i64 16, i32 1)
  %t3446 = inttoptr i64 338 to ptr
  %t3447 = getelementptr ptr, ptr %t3445, i32 0
  store ptr %t3446, ptr %t3447
  call void @__inc_ref(ptr %t6)
  %t3448 = getelementptr ptr, ptr %t3445, i32 1
  store ptr %t6, ptr %t3448
  call void @__free_recursive(ptr %t6)
  store ptr %t3444, ptr %t3
  store ptr %t3445, ptr %t4
  br label %tco.loop.0
tco.case.arm.193.3449:
  %t3450 = getelementptr ptr, ptr %t5, i32 1
  %t3451 = load ptr, ptr %t3450
  %t3452 = getelementptr ptr, ptr %t5, i32 2
  %t3453 = load ptr, ptr %t3452
  %t3454 = getelementptr i8, ptr %t5, i64 -8
  %t3455 = load i32, ptr %t3454
  %t3456 = icmp eq i32 %t3455, 1
  br i1 %t3456, label %reuse.in_place.3457, label %reuse.copy.3458
reuse.in_place.3457:
  %t3460 = inttoptr i64 114 to ptr
  %t3461 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3460, ptr %t3461
  br label %reuse.join.3459
reuse.copy.3458:
  %t3462 = call ptr @__alloc(i64 24, i32 2)
  %t3463 = inttoptr i64 114 to ptr
  %t3464 = getelementptr ptr, ptr %t3462, i32 0
  store ptr %t3463, ptr %t3464
  call void @__inc_ref(ptr %t3451)
  %t3465 = getelementptr ptr, ptr %t3462, i32 1
  store ptr %t3451, ptr %t3465
  call void @__inc_ref(ptr %t3453)
  %t3466 = getelementptr ptr, ptr %t3462, i32 2
  store ptr %t3453, ptr %t3466
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3459
reuse.join.3459:
  %t3467 = phi ptr [ %t5, %reuse.in_place.3457 ], [ %t3462, %reuse.copy.3458 ]
  %t3468 = call ptr @__alloc(i64 16, i32 1)
  %t3469 = inttoptr i64 339 to ptr
  %t3470 = getelementptr ptr, ptr %t3468, i32 0
  store ptr %t3469, ptr %t3470
  call void @__inc_ref(ptr %t6)
  %t3471 = getelementptr ptr, ptr %t3468, i32 1
  store ptr %t6, ptr %t3471
  call void @__free_recursive(ptr %t6)
  store ptr %t3467, ptr %t3
  store ptr %t3468, ptr %t4
  br label %tco.loop.0
tco.case.arm.194.3472:
  %t3473 = getelementptr ptr, ptr %t5, i32 1
  %t3474 = load ptr, ptr %t3473
  %t3475 = getelementptr ptr, ptr %t5, i32 2
  %t3476 = load ptr, ptr %t3475
  %t3477 = getelementptr i8, ptr %t5, i64 -8
  %t3478 = load i32, ptr %t3477
  %t3479 = icmp eq i32 %t3478, 1
  br i1 %t3479, label %reuse.in_place.3480, label %reuse.copy.3481
reuse.in_place.3480:
  %t3483 = inttoptr i64 114 to ptr
  %t3484 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3483, ptr %t3484
  br label %reuse.join.3482
reuse.copy.3481:
  %t3485 = call ptr @__alloc(i64 24, i32 2)
  %t3486 = inttoptr i64 114 to ptr
  %t3487 = getelementptr ptr, ptr %t3485, i32 0
  store ptr %t3486, ptr %t3487
  call void @__inc_ref(ptr %t3474)
  %t3488 = getelementptr ptr, ptr %t3485, i32 1
  store ptr %t3474, ptr %t3488
  call void @__inc_ref(ptr %t3476)
  %t3489 = getelementptr ptr, ptr %t3485, i32 2
  store ptr %t3476, ptr %t3489
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3482
reuse.join.3482:
  %t3490 = phi ptr [ %t5, %reuse.in_place.3480 ], [ %t3485, %reuse.copy.3481 ]
  %t3491 = call ptr @__alloc(i64 16, i32 1)
  %t3492 = inttoptr i64 340 to ptr
  %t3493 = getelementptr ptr, ptr %t3491, i32 0
  store ptr %t3492, ptr %t3493
  call void @__inc_ref(ptr %t6)
  %t3494 = getelementptr ptr, ptr %t3491, i32 1
  store ptr %t6, ptr %t3494
  call void @__free_recursive(ptr %t6)
  store ptr %t3490, ptr %t3
  store ptr %t3491, ptr %t4
  br label %tco.loop.0
tco.case.arm.198.3495:
  %t3496 = getelementptr ptr, ptr %t5, i32 1
  %t3497 = load ptr, ptr %t3496
  %t3498 = getelementptr ptr, ptr %t5, i32 2
  %t3499 = load ptr, ptr %t3498
  %t3500 = getelementptr i8, ptr %t5, i64 -8
  %t3501 = load i32, ptr %t3500
  %t3502 = icmp eq i32 %t3501, 1
  br i1 %t3502, label %reuse.in_place.3503, label %reuse.copy.3504
reuse.in_place.3503:
  %t3506 = inttoptr i64 114 to ptr
  %t3507 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3506, ptr %t3507
  br label %reuse.join.3505
reuse.copy.3504:
  %t3508 = call ptr @__alloc(i64 24, i32 2)
  %t3509 = inttoptr i64 114 to ptr
  %t3510 = getelementptr ptr, ptr %t3508, i32 0
  store ptr %t3509, ptr %t3510
  call void @__inc_ref(ptr %t3497)
  %t3511 = getelementptr ptr, ptr %t3508, i32 1
  store ptr %t3497, ptr %t3511
  call void @__inc_ref(ptr %t3499)
  %t3512 = getelementptr ptr, ptr %t3508, i32 2
  store ptr %t3499, ptr %t3512
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3505
reuse.join.3505:
  %t3513 = phi ptr [ %t5, %reuse.in_place.3503 ], [ %t3508, %reuse.copy.3504 ]
  %t3514 = call ptr @__alloc(i64 16, i32 1)
  %t3515 = inttoptr i64 344 to ptr
  %t3516 = getelementptr ptr, ptr %t3514, i32 0
  store ptr %t3515, ptr %t3516
  call void @__inc_ref(ptr %t6)
  %t3517 = getelementptr ptr, ptr %t3514, i32 1
  store ptr %t6, ptr %t3517
  call void @__free_recursive(ptr %t6)
  store ptr %t3513, ptr %t3
  store ptr %t3514, ptr %t4
  br label %tco.loop.0
tco.case.arm.199.3518:
  %t3519 = getelementptr ptr, ptr %t5, i32 1
  %t3520 = load ptr, ptr %t3519
  %t3521 = getelementptr ptr, ptr %t5, i32 2
  %t3522 = load ptr, ptr %t3521
  %t3523 = getelementptr i8, ptr %t5, i64 -8
  %t3524 = load i32, ptr %t3523
  %t3525 = icmp eq i32 %t3524, 1
  br i1 %t3525, label %reuse.in_place.3526, label %reuse.copy.3527
reuse.in_place.3526:
  %t3529 = inttoptr i64 114 to ptr
  %t3530 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3529, ptr %t3530
  br label %reuse.join.3528
reuse.copy.3527:
  %t3531 = call ptr @__alloc(i64 24, i32 2)
  %t3532 = inttoptr i64 114 to ptr
  %t3533 = getelementptr ptr, ptr %t3531, i32 0
  store ptr %t3532, ptr %t3533
  call void @__inc_ref(ptr %t3520)
  %t3534 = getelementptr ptr, ptr %t3531, i32 1
  store ptr %t3520, ptr %t3534
  call void @__inc_ref(ptr %t3522)
  %t3535 = getelementptr ptr, ptr %t3531, i32 2
  store ptr %t3522, ptr %t3535
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3528
reuse.join.3528:
  %t3536 = phi ptr [ %t5, %reuse.in_place.3526 ], [ %t3531, %reuse.copy.3527 ]
  %t3537 = call ptr @__alloc(i64 16, i32 1)
  %t3538 = inttoptr i64 345 to ptr
  %t3539 = getelementptr ptr, ptr %t3537, i32 0
  store ptr %t3538, ptr %t3539
  call void @__inc_ref(ptr %t6)
  %t3540 = getelementptr ptr, ptr %t3537, i32 1
  store ptr %t6, ptr %t3540
  call void @__free_recursive(ptr %t6)
  store ptr %t3536, ptr %t3
  store ptr %t3537, ptr %t4
  br label %tco.loop.0
tco.case.arm.200.3541:
  %t3542 = getelementptr ptr, ptr %t5, i32 1
  %t3543 = load ptr, ptr %t3542
  %t3544 = getelementptr ptr, ptr %t5, i32 2
  %t3545 = load ptr, ptr %t3544
  %t3546 = getelementptr i8, ptr %t5, i64 -8
  %t3547 = load i32, ptr %t3546
  %t3548 = icmp eq i32 %t3547, 1
  br i1 %t3548, label %reuse.in_place.3549, label %reuse.copy.3550
reuse.in_place.3549:
  %t3552 = inttoptr i64 114 to ptr
  %t3553 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3552, ptr %t3553
  br label %reuse.join.3551
reuse.copy.3550:
  %t3554 = call ptr @__alloc(i64 24, i32 2)
  %t3555 = inttoptr i64 114 to ptr
  %t3556 = getelementptr ptr, ptr %t3554, i32 0
  store ptr %t3555, ptr %t3556
  call void @__inc_ref(ptr %t3543)
  %t3557 = getelementptr ptr, ptr %t3554, i32 1
  store ptr %t3543, ptr %t3557
  call void @__inc_ref(ptr %t3545)
  %t3558 = getelementptr ptr, ptr %t3554, i32 2
  store ptr %t3545, ptr %t3558
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3551
reuse.join.3551:
  %t3559 = phi ptr [ %t5, %reuse.in_place.3549 ], [ %t3554, %reuse.copy.3550 ]
  %t3560 = call ptr @__alloc(i64 16, i32 1)
  %t3561 = inttoptr i64 346 to ptr
  %t3562 = getelementptr ptr, ptr %t3560, i32 0
  store ptr %t3561, ptr %t3562
  call void @__inc_ref(ptr %t6)
  %t3563 = getelementptr ptr, ptr %t3560, i32 1
  store ptr %t6, ptr %t3563
  call void @__free_recursive(ptr %t6)
  store ptr %t3559, ptr %t3
  store ptr %t3560, ptr %t4
  br label %tco.loop.0
tco.case.arm.201.3564:
  %t3565 = getelementptr ptr, ptr %t5, i32 1
  %t3566 = load ptr, ptr %t3565
  %t3567 = getelementptr ptr, ptr %t5, i32 2
  %t3568 = load ptr, ptr %t3567
  %t3569 = getelementptr i8, ptr %t5, i64 -8
  %t3570 = load i32, ptr %t3569
  %t3571 = icmp eq i32 %t3570, 1
  br i1 %t3571, label %reuse.in_place.3572, label %reuse.copy.3573
reuse.in_place.3572:
  %t3575 = inttoptr i64 114 to ptr
  %t3576 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3575, ptr %t3576
  br label %reuse.join.3574
reuse.copy.3573:
  %t3577 = call ptr @__alloc(i64 24, i32 2)
  %t3578 = inttoptr i64 114 to ptr
  %t3579 = getelementptr ptr, ptr %t3577, i32 0
  store ptr %t3578, ptr %t3579
  call void @__inc_ref(ptr %t3566)
  %t3580 = getelementptr ptr, ptr %t3577, i32 1
  store ptr %t3566, ptr %t3580
  call void @__inc_ref(ptr %t3568)
  %t3581 = getelementptr ptr, ptr %t3577, i32 2
  store ptr %t3568, ptr %t3581
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3574
reuse.join.3574:
  %t3582 = phi ptr [ %t5, %reuse.in_place.3572 ], [ %t3577, %reuse.copy.3573 ]
  %t3583 = call ptr @__alloc(i64 16, i32 1)
  %t3584 = inttoptr i64 347 to ptr
  %t3585 = getelementptr ptr, ptr %t3583, i32 0
  store ptr %t3584, ptr %t3585
  call void @__inc_ref(ptr %t6)
  %t3586 = getelementptr ptr, ptr %t3583, i32 1
  store ptr %t6, ptr %t3586
  call void @__free_recursive(ptr %t6)
  store ptr %t3582, ptr %t3
  store ptr %t3583, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t3587 = load ptr, ptr %t2
  ret ptr %t3587
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
  %t5 = call ptr @v__scc__apply1__df__lam_10_39__df__lam_14_1__df__lam_14_13__df__lam_14_17__df__lam_14_21__df__lam_14_29__df__lam_14_41__df__lam_14_45__df__lam_14_5__df__lam_14_9__df__lam_15_10__df__lam_15_14__df__lam_15_18__df__lam_15_2__df__lam_15_22__df__lam_15_30__df__lam_15_42__df__lam_15_46__df__lam_15_6__df__lam_16_11__df__lam_16_15__df__lam_16_19__df__lam_16_23__df__lam_16_3__df__lam_16_31__df__lam_16_43__df__lam_16_47__df__lam_16_7__df__lam_37_49__df__lam_38_50__df__lam_39_51__df__lam_5_25__df__lam_5_33__df__lam_5_53__df__lam_5_57__df__lam_5_61__df__lam_5_65__df__lam_5_69__df__lam_5_73__df__lam_5_77__df__lam_5_81__df__lam_5_85__df__lam_5_89__df__lam_5_93__df__lam_6_26__df__lam_6_34__df__lam_6_54__df__lam_6_58__df__lam_6_62__df__lam_6_66__df__lam_6_70__df__lam_6_74__df__lam_6_78__df__lam_6_82__df__lam_6_86__df__lam_6_90__df__lam_6_94__df__lam_7_27__df__lam_7_35__df__lam_7_55__df__lam_7_59__df__lam_7_63__df__lam_7_67__df__lam_7_71__df__lam_7_75__df__lam_7_79__df__lam_7_83__df__lam_7_87__df__lam_7_91__df__lam_7_95__df__lam_8_37__df__lam_9_38__lift_2__lift_25__lift_26__lift_27__lift_3__lift_30__lift_31__lift_32__lift_34__lift_35__lift_36__lift_4__lift_44__lift_45__lift_46(ptr %t0)
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
