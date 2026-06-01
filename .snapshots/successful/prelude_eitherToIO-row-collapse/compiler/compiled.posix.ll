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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"kS" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"seedS" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"ErrA" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"First" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [6 x i8]} { i32 0, i32 0, i32 0, i32 6, i32 6, [6 x i8] c"Second" }
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"ErrB" }
@.str.6 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"nevOk" }
@.str.7 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"\0A" }
@.str.8 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"=" }
@.str.9 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"wOk" }
@.str.10 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"wE3" }
@.str.11 = private unnamed_addr constant {i32, i32, i32, i32, i32, [6 x i8]} { i32 0, i32 0, i32 0, i32 6, i32 6, [6 x i8] c"wE2str" }
@.str.12 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"wE1" }
@.str.13 = private unnamed_addr constant {i32, i32, i32, i32, i32, [11 x i8]} { i32 0, i32 0, i32 0, i32 11, i32 11, [11 x i8] c"idem2Second" }
@.str.14 = private unnamed_addr constant {i32, i32, i32, i32, i32, [10 x i8]} { i32 0, i32 0, i32 0, i32 10, i32 10, [10 x i8] c"idem2First" }
@.str.15 = private unnamed_addr constant {i32, i32, i32, i32, i32, [6 x i8]} { i32 0, i32 0, i32 0, i32 6, i32 6, [6 x i8] c"idemE2" }
@.str.16 = private unnamed_addr constant {i32, i32, i32, i32, i32, [6 x i8]} { i32 0, i32 0, i32 0, i32 6, i32 6, [6 x i8] c"idemE1" }
@.str.17 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"twoOk" }
@.str.18 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"twoE2" }
@.str.19 = private unnamed_addr constant {i32, i32, i32, i32, i32, [9 x i8]} { i32 0, i32 0, i32 0, i32 9, i32 9, [9 x i8] c"twoSecond" }
@.str.20 = private unnamed_addr constant {i32, i32, i32, i32, i32, [8 x i8]} { i32 0, i32 0, i32 0, i32 8, i32 8, [8 x i8] c"twoFirst" }
@.str.21 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"abE2" }
@.str.22 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"abE1" }
@.str.23 = private unnamed_addr constant {i32, i32, i32, i32, i32, [7 x i8]} { i32 0, i32 0, i32 0, i32 7, i32 7, [7 x i8] c"strIdem" }
@.str.24 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"strE2" }
@.str.25 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"strE1" }
@.str.26 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"strOk" }
@.str.27 = private unnamed_addr constant {i32, i32, i32, i32, i32, [9 x i8]} { i32 0, i32 0, i32 0, i32 9, i32 9, [9 x i8] c"pureNever" }
@.str.28 = private unnamed_addr constant {i32, i32, i32, i32, i32, [10 x i8]} { i32 0, i32 0, i32 0, i32 10, i32 10, [10 x i8] c"nevRightE1" }
@.str.29 = private unnamed_addr constant {i32, i32, i32, i32, i32, [10 x i8]} { i32 0, i32 0, i32 0, i32 10, i32 10, [10 x i8] c"nevRightOk" }
@.str.30 = private unnamed_addr constant {i32, i32, i32, i32, i32, [7 x i8]} { i32 0, i32 0, i32 0, i32 7, i32 7, [7 x i8] c"nevFail" }

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
  %tl_inner_tag = inttoptr i64 18 to ptr
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
  %us_inner_tag = inttoptr i64 19 to ptr
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
  %nilC_tag = inttoptr i64 12 to ptr
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
  %consC_tag = inttoptr i64 13 to ptr
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


define internal ptr @__stdinReadAll() {
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
  %final_cap = load i64, ptr %cap_p
  %final_len = load i64, ptr %len_p
  %is_full = icmp eq i64 %final_cap, %final_len
  br i1 %is_full, label %pad_grow, label %pad_write
pad_grow:
  %pad_old = load ptr, ptr %buf_p
  %pad_cap = add i64 %final_cap, 1
  %pad_new = call ptr @realloc(ptr %pad_old, i64 %pad_cap)
  store ptr %pad_new, ptr %buf_p
  br label %pad_write
pad_write:
  %buf_final = load ptr, ptr %buf_p
  %past_end = getelementptr i8, ptr %buf_final, i64 %final_len
  store i8 0, ptr %past_end
  %either = call ptr @__entryArgEither(ptr %buf_final, i64 %final_len)
  call void @free(ptr %buf_final)
  ret ptr %either
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
  switch i64 %t7, label %tco.case.default.8 [ i64 5, label %tco.case.arm.5.9 i64 7, label %tco.case.arm.7.12 i64 8, label %tco.case.arm.8.23 i64 9, label %tco.case.arm.9.28 ]
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
tco.case.default.8:
  unreachable
tco.exit.1:
  %t33 = load ptr, ptr %t2
  ret ptr %t33
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
  %t12 = call ptr @v__lift_12(ptr %t11)
  call void @__free_recursive(ptr %t10)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t12
case.default.3:
  unreachable
}

define internal ptr @v_kNever(ptr %v_n) {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 4 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  call void @__inc_ref(ptr %v_n)
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v_n, ptr %t3
  call void @__free_recursive(ptr %v_n)
  ret ptr %t0
}

define internal ptr @v_kAOk(ptr %v_n) {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 4 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  call void @__inc_ref(ptr %v_n)
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v_n, ptr %t3
  call void @__free_recursive(ptr %v_n)
  ret ptr %t0
}

define internal ptr @v_kAFail(ptr %v__n) {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 3 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 8, i32 0)
  %t4 = inttoptr i64 22 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  call void @__free_recursive(ptr %v__n)
  ret ptr %t0
}

define internal ptr @v_kBFail(ptr %v__n) {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 3 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 8, i32 0)
  %t4 = inttoptr i64 23 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  call void @__free_recursive(ptr %v__n)
  ret ptr %t0
}

define internal ptr @v_kSOk(ptr %v_n) {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 4 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  call void @__inc_ref(ptr %v_n)
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v_n, ptr %t3
  call void @__free_recursive(ptr %v_n)
  ret ptr %t0
}

define internal ptr @v_kSFail(ptr %v__n) {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 3 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t3
  call void @__free_recursive(ptr %v__n)
  ret ptr %t0
}

define internal ptr @v_kSecond(ptr %v__n) {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 3 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 8, i32 0)
  %t4 = inttoptr i64 25 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  call void @__free_recursive(ptr %v__n)
  ret ptr %t0
}

define internal ptr @v_seedNever() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 4 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 4, i32 0)
  store i32 1, ptr %t3
  %t4 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t4
  ret ptr %t0
}

define internal ptr @v_seedA() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 4 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 4, i32 0)
  store i32 2, ptr %t3
  %t4 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t4
  ret ptr %t0
}

define internal ptr @v_seedLeftA() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 3 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 8, i32 0)
  %t4 = inttoptr i64 22 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  ret ptr %t0
}

define internal ptr @v_seedS() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 4 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 4, i32 0)
  store i32 3, ptr %t3
  %t4 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t4
  ret ptr %t0
}

define internal ptr @v_seedLeftS() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 3 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t3
  ret ptr %t0
}

define internal ptr @v_seedT() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 4 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 4, i32 0)
  store i32 4, ptr %t3
  %t4 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t4
  ret ptr %t0
}

define internal ptr @v_seedFirst() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 3 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 8, i32 0)
  %t4 = inttoptr i64 24 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  ret ptr %t0
}

define internal ptr @v_seedSecond() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 3 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 8, i32 0)
  %t4 = inttoptr i64 25 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  ret ptr %t0
}

define internal ptr @v_nevOk() {
  %t0 = call ptr @v_seedNever()
  %t1 = call ptr @v__df_bindEither_0(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_nevFail() {
  %t0 = call ptr @v_seedNever()
  %t1 = call ptr @v__df_bindEither_1(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_nevRightOk() {
  %t0 = call ptr @v_seedA()
  %t1 = call ptr @v__df_bindEither_2(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_nevRightE1() {
  %t0 = call ptr @v_seedLeftA()
  %t1 = call ptr @v__df_bindEither_2(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_pureNever() {
  %t0 = call ptr @v_seedNever()
  %t1 = call ptr @v__df_bindEither_2(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_strOk() {
  %t0 = call ptr @v_seedS()
  %t1 = call ptr @v__df__rowspec_15_3(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_strE1() {
  %t0 = call ptr @v_seedLeftS()
  %t1 = call ptr @v__df__rowspec_15_3(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_strE2() {
  %t0 = call ptr @v_seedS()
  %t1 = call ptr @v__df__rowspec_15_4(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_strIdem() {
  %t0 = call ptr @v_seedS()
  %t1 = call ptr @v__df_bindEither_5(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_abE1() {
  %t0 = call ptr @v_seedLeftA()
  %t1 = call ptr @v__df__rowspec_17_6(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_abE2() {
  %t0 = call ptr @v_seedA()
  %t1 = call ptr @v__df__rowspec_17_6(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_twoFirst() {
  %t0 = call ptr @v_seedFirst()
  %t1 = call ptr @v__df__rowspec_19_7(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_twoSecond() {
  %t0 = call ptr @v_seedSecond()
  %t1 = call ptr @v__df__rowspec_19_7(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_twoE2() {
  %t0 = call ptr @v_seedT()
  %t1 = call ptr @v__df__rowspec_19_8(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_twoOk() {
  %t0 = call ptr @v_seedT()
  %t1 = call ptr @v__df__rowspec_19_7(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_idemE1() {
  %t0 = call ptr @v_seedLeftA()
  %t1 = call ptr @v__df_bindEither_1(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_idemE2() {
  %t0 = call ptr @v_seedA()
  %t1 = call ptr @v__df_bindEither_1(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_idem2First() {
  %t0 = call ptr @v_seedFirst()
  %t1 = call ptr @v__df_bindEither_9(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_idem2Second() {
  %t0 = call ptr @v_seedT()
  %t1 = call ptr @v__df_bindEither_9(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_wE1() {
  %t0 = call ptr @v_seedFirst()
  %t1 = call ptr @v__df__rowspec_23_11(ptr %t0)
  %t2 = call ptr @v__lift_25(ptr %t1)
  %t3 = call ptr @v__df__rowspec_21_10(ptr %t2)
  ret ptr %t3
}

define internal ptr @v_wE2str() {
  %t0 = call ptr @v_seedT()
  %t1 = call ptr @v__df__rowspec_23_12(ptr %t0)
  %t2 = call ptr @v__lift_25(ptr %t1)
  %t3 = call ptr @v__df__rowspec_21_10(ptr %t2)
  ret ptr %t3
}

define internal ptr @v_wE3() {
  %t0 = call ptr @v_seedT()
  %t1 = call ptr @v__df__rowspec_23_11(ptr %t0)
  %t2 = call ptr @v__lift_25(ptr %t1)
  %t3 = call ptr @v__df__rowspec_21_13(ptr %t2)
  ret ptr %t3
}

define internal ptr @v_wOk() {
  %t0 = call ptr @v_seedT()
  %t1 = call ptr @v__df__rowspec_23_11(ptr %t0)
  %t2 = call ptr @v__lift_25(ptr %t1)
  %t3 = call ptr @v__df__rowspec_21_10(ptr %t2)
  ret ptr %t3
}

define internal ptr @v_handlerA(ptr %v_e) {
  %t0 = getelementptr ptr, ptr %v_e, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 22, label %case.arm.22.4 ]
case.arm.22.4:
  %t5 = call ptr @__alloc(i64 24, i32 2)
  %t6 = inttoptr i64 7 to ptr
  %t7 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t6, ptr %t7
  %t8 = getelementptr ptr, ptr %t5, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t8
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

define internal ptr @v_observeA(ptr %v_e) {
  call void @__inc_ref(ptr %v_e)
  %t0 = call ptr @v_eitherToIO(ptr %v_e)
  %t1 = call ptr @v__df_mapIO_20(ptr %t0)
  %t2 = call ptr @v__lift_26(ptr %t1)
  %t3 = call ptr @v__df_andThenIO_17(ptr %t2)
  %t4 = call ptr @v__df_handleErrorIO_14(ptr %t3)
  call void @__free_recursive(ptr %v_e)
  ret ptr %t4
}

define internal ptr @v_observeNever(ptr %v_e) {
  call void @__inc_ref(ptr %v_e)
  %t0 = call ptr @v_eitherToIO(ptr %v_e)
  %t1 = call ptr @v__df_mapIO_20(ptr %t0)
  %t2 = call ptr @v__df_andThenIO_17(ptr %t1)
  call void @__free_recursive(ptr %v_e)
  ret ptr %t2
}

define internal ptr @v_handlerTwo(ptr %v_e) {
  %t0 = getelementptr ptr, ptr %v_e, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 24, label %case.arm.24.4 i64 25, label %case.arm.25.17 ]
case.arm.24.4:
  %t5 = call ptr @__alloc(i64 24, i32 2)
  %t6 = inttoptr i64 7 to ptr
  %t7 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t6, ptr %t7
  %t8 = getelementptr ptr, ptr %t5, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t8
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
case.arm.25.17:
  %t18 = call ptr @__alloc(i64 24, i32 2)
  %t19 = inttoptr i64 7 to ptr
  %t20 = getelementptr ptr, ptr %t18, i32 0
  store ptr %t19, ptr %t20
  %t21 = getelementptr ptr, ptr %t18, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t21
  %t22 = call ptr @__alloc(i64 16, i32 1)
  %t23 = inttoptr i64 5 to ptr
  %t24 = getelementptr ptr, ptr %t22, i32 0
  store ptr %t23, ptr %t24
  %t25 = call ptr @__alloc(i64 8, i32 0)
  %t26 = inttoptr i64 0 to ptr
  %t27 = getelementptr ptr, ptr %t25, i32 0
  store ptr %t26, ptr %t27
  %t28 = getelementptr ptr, ptr %t22, i32 1
  store ptr %t25, ptr %t28
  %t29 = getelementptr ptr, ptr %t18, i32 2
  store ptr %t22, ptr %t29
  call void @__free_recursive(ptr %v_e)
  ret ptr %t18
case.default.3:
  unreachable
}

define internal ptr @v_observeTwo(ptr %v_e) {
  call void @__inc_ref(ptr %v_e)
  %t0 = call ptr @v_eitherToIO(ptr %v_e)
  %t1 = call ptr @v__df_mapIO_20(ptr %t0)
  %t2 = call ptr @v__lift_29(ptr %t1)
  %t3 = call ptr @v__df_andThenIO_17(ptr %t2)
  %t4 = call ptr @v__df_handleErrorIO_23(ptr %t3)
  call void @__free_recursive(ptr %v_e)
  ret ptr %t4
}

define internal ptr @v_handlerStr(ptr %v_e) {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 7 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  call void @__inc_ref(ptr %v_e)
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v_e, ptr %t3
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
  call void @__free_recursive(ptr %v_e)
  ret ptr %t0
}

define internal ptr @v_observeStr(ptr %v_e) {
  call void @__inc_ref(ptr %v_e)
  %t0 = call ptr @v_eitherToIO(ptr %v_e)
  %t1 = call ptr @v__df_mapIO_20(ptr %t0)
  %t2 = call ptr @v__lift_32(ptr %t1)
  %t3 = call ptr @v__df_andThenIO_17(ptr %t2)
  %t4 = call ptr @v__df_handleErrorIO_26(ptr %t3)
  call void @__free_recursive(ptr %v_e)
  ret ptr %t4
}

define internal ptr @v_handlerStrA(ptr %v_e) {
  %t0 = getelementptr ptr, ptr %v_e, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 1615808600, label %case.arm.1615808600.4 i64 2252990199, label %case.arm.2252990199.19 ]
case.arm.1615808600.4:
  %t5 = getelementptr ptr, ptr %v_e, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = call ptr @__alloc(i64 24, i32 2)
  %t8 = inttoptr i64 7 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  call void @__inc_ref(ptr %t6)
  %t10 = getelementptr ptr, ptr %t7, i32 1
  store ptr %t6, ptr %t10
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
case.arm.2252990199.19:
  %t20 = getelementptr ptr, ptr %v_e, i32 1
  %t21 = load ptr, ptr %t20
  call void @__inc_ref(ptr %t21)
  %t22 = call ptr @__alloc(i64 24, i32 2)
  %t23 = inttoptr i64 7 to ptr
  %t24 = getelementptr ptr, ptr %t22, i32 0
  store ptr %t23, ptr %t24
  %t25 = getelementptr ptr, ptr %t22, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t25
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

define internal ptr @v_observeStrA(ptr %v_e) {
  call void @__inc_ref(ptr %v_e)
  %t0 = call ptr @v_eitherToIO(ptr %v_e)
  %t1 = call ptr @v__df_mapIO_20(ptr %t0)
  %t2 = call ptr @v__df__rowspec_35_32(ptr %t1)
  %t3 = call ptr @v__df_handleErrorIO_29(ptr %t2)
  call void @__free_recursive(ptr %v_e)
  ret ptr %t3
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
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t10
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

define internal ptr @v_observeAB(ptr %v_e) {
  call void @__inc_ref(ptr %v_e)
  %t0 = call ptr @v_eitherToIO(ptr %v_e)
  %t1 = call ptr @v__df_mapIO_20(ptr %t0)
  %t2 = call ptr @v__df__rowspec_44_38(ptr %t1)
  %t3 = call ptr @v__df_handleErrorIO_35(ptr %t2)
  call void @__free_recursive(ptr %v_e)
  ret ptr %t3
}

define internal ptr @v_handlerTwoA(ptr %v_e) {
  %t0 = getelementptr ptr, ptr %v_e, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 925038822, label %case.arm.925038822.4 i64 2252990199, label %case.arm.2252990199.37 ]
case.arm.925038822.4:
  %t5 = getelementptr ptr, ptr %v_e, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = getelementptr ptr, ptr %t6, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %case.default.10 [ i64 24, label %case.arm.24.11 i64 25, label %case.arm.25.24 ]
case.arm.24.11:
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t15
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
case.arm.25.24:
  %t25 = call ptr @__alloc(i64 24, i32 2)
  %t26 = inttoptr i64 7 to ptr
  %t27 = getelementptr ptr, ptr %t25, i32 0
  store ptr %t26, ptr %t27
  %t28 = getelementptr ptr, ptr %t25, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t28
  %t29 = call ptr @__alloc(i64 16, i32 1)
  %t30 = inttoptr i64 5 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = call ptr @__alloc(i64 8, i32 0)
  %t33 = inttoptr i64 0 to ptr
  %t34 = getelementptr ptr, ptr %t32, i32 0
  store ptr %t33, ptr %t34
  %t35 = getelementptr ptr, ptr %t29, i32 1
  store ptr %t32, ptr %t35
  %t36 = getelementptr ptr, ptr %t25, i32 2
  store ptr %t29, ptr %t36
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_e)
  ret ptr %t25
case.default.10:
  unreachable
case.arm.2252990199.37:
  %t38 = getelementptr ptr, ptr %v_e, i32 1
  %t39 = load ptr, ptr %t38
  call void @__inc_ref(ptr %t39)
  %t40 = call ptr @__alloc(i64 24, i32 2)
  %t41 = inttoptr i64 7 to ptr
  %t42 = getelementptr ptr, ptr %t40, i32 0
  store ptr %t41, ptr %t42
  %t43 = getelementptr ptr, ptr %t40, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t43
  %t44 = call ptr @__alloc(i64 16, i32 1)
  %t45 = inttoptr i64 5 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  %t47 = call ptr @__alloc(i64 8, i32 0)
  %t48 = inttoptr i64 0 to ptr
  %t49 = getelementptr ptr, ptr %t47, i32 0
  store ptr %t48, ptr %t49
  %t50 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t47, ptr %t50
  %t51 = getelementptr ptr, ptr %t40, i32 2
  store ptr %t44, ptr %t51
  call void @__free_recursive(ptr %t39)
  call void @__free_recursive(ptr %v_e)
  ret ptr %t40
case.default.3:
  unreachable
}

define internal ptr @v_observeTwoA(ptr %v_e) {
  call void @__inc_ref(ptr %v_e)
  %t0 = call ptr @v_eitherToIO(ptr %v_e)
  %t1 = call ptr @v__df_mapIO_20(ptr %t0)
  %t2 = call ptr @v__df__rowspec_53_44(ptr %t1)
  %t3 = call ptr @v__df_handleErrorIO_41(ptr %t2)
  call void @__free_recursive(ptr %v_e)
  ret ptr %t3
}

define internal ptr @v_handlerThree(ptr %v_e) {
  %t0 = getelementptr ptr, ptr %v_e, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 925038822, label %case.arm.925038822.4 i64 1615808600, label %case.arm.1615808600.37 i64 2252990199, label %case.arm.2252990199.52 ]
case.arm.925038822.4:
  %t5 = getelementptr ptr, ptr %v_e, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = getelementptr ptr, ptr %t6, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %case.default.10 [ i64 24, label %case.arm.24.11 i64 25, label %case.arm.25.24 ]
case.arm.24.11:
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t15
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
case.arm.25.24:
  %t25 = call ptr @__alloc(i64 24, i32 2)
  %t26 = inttoptr i64 7 to ptr
  %t27 = getelementptr ptr, ptr %t25, i32 0
  store ptr %t26, ptr %t27
  %t28 = getelementptr ptr, ptr %t25, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t28
  %t29 = call ptr @__alloc(i64 16, i32 1)
  %t30 = inttoptr i64 5 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = call ptr @__alloc(i64 8, i32 0)
  %t33 = inttoptr i64 0 to ptr
  %t34 = getelementptr ptr, ptr %t32, i32 0
  store ptr %t33, ptr %t34
  %t35 = getelementptr ptr, ptr %t29, i32 1
  store ptr %t32, ptr %t35
  %t36 = getelementptr ptr, ptr %t25, i32 2
  store ptr %t29, ptr %t36
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_e)
  ret ptr %t25
case.default.10:
  unreachable
case.arm.1615808600.37:
  %t38 = getelementptr ptr, ptr %v_e, i32 1
  %t39 = load ptr, ptr %t38
  call void @__inc_ref(ptr %t39)
  %t40 = call ptr @__alloc(i64 24, i32 2)
  %t41 = inttoptr i64 7 to ptr
  %t42 = getelementptr ptr, ptr %t40, i32 0
  store ptr %t41, ptr %t42
  call void @__inc_ref(ptr %t39)
  %t43 = getelementptr ptr, ptr %t40, i32 1
  store ptr %t39, ptr %t43
  %t44 = call ptr @__alloc(i64 16, i32 1)
  %t45 = inttoptr i64 5 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  %t47 = call ptr @__alloc(i64 8, i32 0)
  %t48 = inttoptr i64 0 to ptr
  %t49 = getelementptr ptr, ptr %t47, i32 0
  store ptr %t48, ptr %t49
  %t50 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t47, ptr %t50
  %t51 = getelementptr ptr, ptr %t40, i32 2
  store ptr %t44, ptr %t51
  call void @__free_recursive(ptr %t39)
  call void @__free_recursive(ptr %v_e)
  ret ptr %t40
case.arm.2252990199.52:
  %t53 = getelementptr ptr, ptr %v_e, i32 1
  %t54 = load ptr, ptr %t53
  call void @__inc_ref(ptr %t54)
  %t55 = call ptr @__alloc(i64 24, i32 2)
  %t56 = inttoptr i64 7 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  %t58 = getelementptr ptr, ptr %t55, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t58
  %t59 = call ptr @__alloc(i64 16, i32 1)
  %t60 = inttoptr i64 5 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  %t62 = call ptr @__alloc(i64 8, i32 0)
  %t63 = inttoptr i64 0 to ptr
  %t64 = getelementptr ptr, ptr %t62, i32 0
  store ptr %t63, ptr %t64
  %t65 = getelementptr ptr, ptr %t59, i32 1
  store ptr %t62, ptr %t65
  %t66 = getelementptr ptr, ptr %t55, i32 2
  store ptr %t59, ptr %t66
  call void @__free_recursive(ptr %t54)
  call void @__free_recursive(ptr %v_e)
  ret ptr %t55
case.default.3:
  unreachable
}

define internal ptr @v_observeThree(ptr %v_e) {
  call void @__inc_ref(ptr %v_e)
  %t0 = call ptr @v_eitherToIO(ptr %v_e)
  %t1 = call ptr @v__df_mapIO_20(ptr %t0)
  %t2 = call ptr @v__lift_66(ptr %t1)
  %t3 = call ptr @v__df__rowspec_62_50(ptr %t2)
  %t4 = call ptr @v__df_handleErrorIO_47(ptr %t3)
  call void @__free_recursive(ptr %v_e)
  ret ptr %t4
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
  %t12 = call ptr @v__lift_74(ptr %t0)
  %t13 = call ptr @v__df_andThenIO_59(ptr %t12)
  call void @__inc_ref(ptr %v_act)
  %t14 = call ptr @v__df_andThenIO_56(ptr %t13, ptr %v_act)
  %t15 = call ptr @v__df_andThenIO_53(ptr %t14)
  call void @__free_recursive(ptr %v_label)
  call void @__free_recursive(ptr %v_act)
  ret ptr %t15
}

define internal ptr @v_main() {
  %t0 = call ptr @v_nevOk()
  %t1 = call ptr @v_observeA(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.6, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_74(ptr %t2)
  %t4 = call ptr @v__df_andThenIO_125(ptr %t3)
  %t5 = call ptr @v__df_andThenIO_122(ptr %t4)
  %t6 = call ptr @v__df_andThenIO_119(ptr %t5)
  %t7 = call ptr @v__df_andThenIO_116(ptr %t6)
  %t8 = call ptr @v__df_andThenIO_113(ptr %t7)
  %t9 = call ptr @v__df_andThenIO_110(ptr %t8)
  %t10 = call ptr @v__df_andThenIO_107(ptr %t9)
  %t11 = call ptr @v__df_andThenIO_104(ptr %t10)
  %t12 = call ptr @v__df_andThenIO_101(ptr %t11)
  %t13 = call ptr @v__df_andThenIO_98(ptr %t12)
  %t14 = call ptr @v__df_andThenIO_95(ptr %t13)
  %t15 = call ptr @v__df_andThenIO_92(ptr %t14)
  %t16 = call ptr @v__df_andThenIO_89(ptr %t15)
  %t17 = call ptr @v__df_andThenIO_86(ptr %t16)
  %t18 = call ptr @v__df_andThenIO_83(ptr %t17)
  %t19 = call ptr @v__df_andThenIO_80(ptr %t18)
  %t20 = call ptr @v__df_andThenIO_77(ptr %t19)
  %t21 = call ptr @v__df_andThenIO_74(ptr %t20)
  %t22 = call ptr @v__df_andThenIO_71(ptr %t21)
  %t23 = call ptr @v__df_andThenIO_68(ptr %t22)
  %t24 = call ptr @v__df_andThenIO_65(ptr %t23)
  %t25 = call ptr @v__df_andThenIO_62(ptr %t24)
  ret ptr %t25
}

define internal ptr @v__lift_0(ptr %v___input) {
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

define internal ptr @v__lift_1(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 235 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.19 i64 7, label %tco.case.arm.7.27 i64 8, label %tco.case.arm.8.50 i64 9, label %tco.case.arm.9.62 ]
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
  %t42 = inttoptr i64 236 to ptr
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
  %t45 = inttoptr i64 236 to ptr
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
  %t57 = inttoptr i64 104 to ptr
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
  %t69 = inttoptr i64 107 to ptr
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
tco.case.default.10:
  unreachable
tco.exit.1:
  %t74 = load ptr, ptr %t2
  ret ptr %t74
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
  switch i64 %t9, label %tco.case.default.10 [ i64 235, label %tco.case.arm.235.11 i64 236, label %tco.case.arm.236.12 ]
tco.case.arm.235.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.236.12:
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

define internal ptr @v__lift_12(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 237 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__lift_12(ptr %v___input, ptr %t0)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t3
}

define internal ptr @v__cps__lift_12(ptr %v___input, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.19 i64 7, label %tco.case.arm.7.27 i64 8, label %tco.case.arm.8.50 i64 9, label %tco.case.arm.9.62 ]
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
  %t18 = call ptr @v__apply__lift_12(ptr %t6, ptr %t14)
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
  %t26 = call ptr @v__apply__lift_12(ptr %t6, ptr %t22)
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
  %t42 = inttoptr i64 238 to ptr
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
  %t45 = inttoptr i64 238 to ptr
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
  %t57 = inttoptr i64 102 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  call void @__inc_ref(ptr %t52)
  %t59 = getelementptr ptr, ptr %t56, i32 1
  store ptr %t52, ptr %t59
  %t60 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t56, ptr %t60
  %t61 = call ptr @v__apply__lift_12(ptr %t6, ptr %t53)
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
  %t73 = call ptr @v__apply__lift_12(ptr %t6, ptr %t65)
  call void @__free_recursive(ptr %t64)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t73, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t74 = load ptr, ptr %t2
  ret ptr %t74
}

define internal ptr @v__apply__lift_12(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 237, label %tco.case.arm.237.11 i64 238, label %tco.case.arm.238.12 ]
tco.case.arm.237.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.238.12:
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

define internal ptr @v__lift_16(ptr %v___input) {
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
  %t11 = inttoptr i64 2252990199 to ptr
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

define internal ptr @v__lift_18(ptr %v___input) {
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
  %t11 = inttoptr i64 2269767818 to ptr
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
  %t11 = inttoptr i64 2252990199 to ptr
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

define internal ptr @v__lift_22(ptr %v___input) {
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
  %t11 = inttoptr i64 2252990199 to ptr
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

define internal ptr @v__lift_24(ptr %v___input) {
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
  %t11 = inttoptr i64 1615808600 to ptr
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

define internal ptr @v__lift_25(ptr %v___input) {
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

define internal ptr @v__lift_26(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 239 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.19 i64 7, label %tco.case.arm.7.27 i64 8, label %tco.case.arm.8.50 i64 9, label %tco.case.arm.9.62 ]
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
  call void @__inc_ref(ptr %t21)
  %t25 = getelementptr ptr, ptr %t22, i32 1
  store ptr %t21, ptr %t25
  %t26 = call ptr @v__apply__lift_26(ptr %t6, ptr %t22)
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
  %t42 = inttoptr i64 240 to ptr
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
  %t45 = inttoptr i64 240 to ptr
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
  %t57 = inttoptr i64 105 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  call void @__inc_ref(ptr %t52)
  %t59 = getelementptr ptr, ptr %t56, i32 1
  store ptr %t52, ptr %t59
  %t60 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t56, ptr %t60
  %t61 = call ptr @v__apply__lift_26(ptr %t6, ptr %t53)
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
  %t69 = inttoptr i64 106 to ptr
  %t70 = getelementptr ptr, ptr %t68, i32 0
  store ptr %t69, ptr %t70
  call void @__inc_ref(ptr %t64)
  %t71 = getelementptr ptr, ptr %t68, i32 1
  store ptr %t64, ptr %t71
  %t72 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t68, ptr %t72
  %t73 = call ptr @v__apply__lift_26(ptr %t6, ptr %t65)
  call void @__free_recursive(ptr %t64)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t73, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t74 = load ptr, ptr %t2
  ret ptr %t74
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
  switch i64 %t9, label %tco.case.default.10 [ i64 239, label %tco.case.arm.239.11 i64 240, label %tco.case.arm.240.12 ]
tco.case.arm.239.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.240.12:
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
  %t1 = inttoptr i64 241 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.19 i64 7, label %tco.case.arm.7.27 i64 8, label %tco.case.arm.8.50 i64 9, label %tco.case.arm.9.62 ]
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
  call void @__inc_ref(ptr %t21)
  %t25 = getelementptr ptr, ptr %t22, i32 1
  store ptr %t21, ptr %t25
  %t26 = call ptr @v__apply__lift_29(ptr %t6, ptr %t22)
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
  %t42 = inttoptr i64 242 to ptr
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
  %t45 = inttoptr i64 242 to ptr
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
  %t57 = inttoptr i64 108 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  call void @__inc_ref(ptr %t52)
  %t59 = getelementptr ptr, ptr %t56, i32 1
  store ptr %t52, ptr %t59
  %t60 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t56, ptr %t60
  %t61 = call ptr @v__apply__lift_29(ptr %t6, ptr %t53)
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
  %t73 = call ptr @v__apply__lift_29(ptr %t6, ptr %t65)
  call void @__free_recursive(ptr %t64)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t73, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t74 = load ptr, ptr %t2
  ret ptr %t74
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
  switch i64 %t9, label %tco.case.default.10 [ i64 241, label %tco.case.arm.241.11 i64 242, label %tco.case.arm.242.12 ]
tco.case.arm.241.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.242.12:
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
  %t1 = inttoptr i64 243 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.19 i64 7, label %tco.case.arm.7.27 i64 8, label %tco.case.arm.8.50 i64 9, label %tco.case.arm.9.62 ]
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
  %t42 = inttoptr i64 244 to ptr
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
  %t45 = inttoptr i64 244 to ptr
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
  %t57 = inttoptr i64 110 to ptr
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
  %t69 = inttoptr i64 111 to ptr
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
tco.case.default.10:
  unreachable
tco.exit.1:
  %t74 = load ptr, ptr %t2
  ret ptr %t74
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
  switch i64 %t9, label %tco.case.default.10 [ i64 243, label %tco.case.arm.243.11 i64 244, label %tco.case.arm.244.12 ]
tco.case.arm.243.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.244.12:
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
  %t1 = inttoptr i64 245 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.19 i64 7, label %tco.case.arm.7.31 i64 8, label %tco.case.arm.8.54 i64 9, label %tco.case.arm.9.66 ]
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
  %t25 = call ptr @__alloc(i64 16, i32 1)
  %t26 = inttoptr i64 3801428867 to ptr
  %t27 = getelementptr ptr, ptr %t25, i32 0
  store ptr %t26, ptr %t27
  call void @__inc_ref(ptr %t21)
  %t28 = getelementptr ptr, ptr %t25, i32 1
  store ptr %t21, ptr %t28
  %t29 = getelementptr ptr, ptr %t22, i32 1
  store ptr %t25, ptr %t29
  %t30 = call ptr @v__apply__lift_36(ptr %t6, ptr %t22)
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
  %t46 = inttoptr i64 246 to ptr
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
  %t49 = inttoptr i64 246 to ptr
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
  %t61 = inttoptr i64 112 to ptr
  %t62 = getelementptr ptr, ptr %t60, i32 0
  store ptr %t61, ptr %t62
  call void @__inc_ref(ptr %t56)
  %t63 = getelementptr ptr, ptr %t60, i32 1
  store ptr %t56, ptr %t63
  %t64 = getelementptr ptr, ptr %t57, i32 1
  store ptr %t60, ptr %t64
  %t65 = call ptr @v__apply__lift_36(ptr %t6, ptr %t57)
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
  %t73 = inttoptr i64 113 to ptr
  %t74 = getelementptr ptr, ptr %t72, i32 0
  store ptr %t73, ptr %t74
  call void @__inc_ref(ptr %t68)
  %t75 = getelementptr ptr, ptr %t72, i32 1
  store ptr %t68, ptr %t75
  %t76 = getelementptr ptr, ptr %t69, i32 1
  store ptr %t72, ptr %t76
  %t77 = call ptr @v__apply__lift_36(ptr %t6, ptr %t69)
  call void @__free_recursive(ptr %t68)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t77, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t78 = load ptr, ptr %t2
  ret ptr %t78
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
  switch i64 %t9, label %tco.case.default.10 [ i64 245, label %tco.case.arm.245.11 i64 246, label %tco.case.arm.246.12 ]
tco.case.arm.245.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.246.12:
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

define internal ptr @v__lift_45(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 249 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__lift_45(ptr %v___input, ptr %t0)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t3
}

define internal ptr @v__cps__lift_45(ptr %v___input, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.19 i64 7, label %tco.case.arm.7.31 i64 8, label %tco.case.arm.8.54 i64 9, label %tco.case.arm.9.66 ]
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
  %t18 = call ptr @v__apply__lift_45(ptr %t6, ptr %t14)
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
  %t30 = call ptr @v__apply__lift_45(ptr %t6, ptr %t22)
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
  %t46 = inttoptr i64 250 to ptr
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
  %t49 = inttoptr i64 250 to ptr
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
  %t61 = inttoptr i64 116 to ptr
  %t62 = getelementptr ptr, ptr %t60, i32 0
  store ptr %t61, ptr %t62
  call void @__inc_ref(ptr %t56)
  %t63 = getelementptr ptr, ptr %t60, i32 1
  store ptr %t56, ptr %t63
  %t64 = getelementptr ptr, ptr %t57, i32 1
  store ptr %t60, ptr %t64
  %t65 = call ptr @v__apply__lift_45(ptr %t6, ptr %t57)
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
  %t73 = inttoptr i64 117 to ptr
  %t74 = getelementptr ptr, ptr %t72, i32 0
  store ptr %t73, ptr %t74
  call void @__inc_ref(ptr %t68)
  %t75 = getelementptr ptr, ptr %t72, i32 1
  store ptr %t68, ptr %t75
  %t76 = getelementptr ptr, ptr %t69, i32 1
  store ptr %t72, ptr %t76
  %t77 = call ptr @v__apply__lift_45(ptr %t6, ptr %t69)
  call void @__free_recursive(ptr %t68)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t77, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t78 = load ptr, ptr %t2
  ret ptr %t78
}

define internal ptr @v__apply__lift_45(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 249, label %tco.case.arm.249.11 i64 250, label %tco.case.arm.250.12 ]
tco.case.arm.249.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.250.12:
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

define internal ptr @v__lift_54(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 253 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__lift_54(ptr %v___input, ptr %t0)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t3
}

define internal ptr @v__cps__lift_54(ptr %v___input, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.19 i64 7, label %tco.case.arm.7.31 i64 8, label %tco.case.arm.8.54 i64 9, label %tco.case.arm.9.66 ]
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
  %t18 = call ptr @v__apply__lift_54(ptr %t6, ptr %t14)
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
  %t30 = call ptr @v__apply__lift_54(ptr %t6, ptr %t22)
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
  %t46 = inttoptr i64 254 to ptr
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
  %t49 = inttoptr i64 254 to ptr
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
  %t61 = inttoptr i64 120 to ptr
  %t62 = getelementptr ptr, ptr %t60, i32 0
  store ptr %t61, ptr %t62
  call void @__inc_ref(ptr %t56)
  %t63 = getelementptr ptr, ptr %t60, i32 1
  store ptr %t56, ptr %t63
  %t64 = getelementptr ptr, ptr %t57, i32 1
  store ptr %t60, ptr %t64
  %t65 = call ptr @v__apply__lift_54(ptr %t6, ptr %t57)
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
  %t73 = inttoptr i64 121 to ptr
  %t74 = getelementptr ptr, ptr %t72, i32 0
  store ptr %t73, ptr %t74
  call void @__inc_ref(ptr %t68)
  %t75 = getelementptr ptr, ptr %t72, i32 1
  store ptr %t68, ptr %t75
  %t76 = getelementptr ptr, ptr %t69, i32 1
  store ptr %t72, ptr %t76
  %t77 = call ptr @v__apply__lift_54(ptr %t6, ptr %t69)
  call void @__free_recursive(ptr %t68)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t77, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t78 = load ptr, ptr %t2
  ret ptr %t78
}

define internal ptr @v__apply__lift_54(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 253, label %tco.case.arm.253.11 i64 254, label %tco.case.arm.254.12 ]
tco.case.arm.253.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.254.12:
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

define internal ptr @v__lift_63(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 257 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__lift_63(ptr %v___input, ptr %t0)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t3
}

define internal ptr @v__cps__lift_63(ptr %v___input, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.19 i64 7, label %tco.case.arm.7.31 i64 8, label %tco.case.arm.8.54 i64 9, label %tco.case.arm.9.66 ]
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
  %t18 = call ptr @v__apply__lift_63(ptr %t6, ptr %t14)
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
  %t30 = call ptr @v__apply__lift_63(ptr %t6, ptr %t22)
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
  %t46 = inttoptr i64 258 to ptr
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
  %t49 = inttoptr i64 258 to ptr
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
  %t61 = inttoptr i64 124 to ptr
  %t62 = getelementptr ptr, ptr %t60, i32 0
  store ptr %t61, ptr %t62
  call void @__inc_ref(ptr %t56)
  %t63 = getelementptr ptr, ptr %t60, i32 1
  store ptr %t56, ptr %t63
  %t64 = getelementptr ptr, ptr %t57, i32 1
  store ptr %t60, ptr %t64
  %t65 = call ptr @v__apply__lift_63(ptr %t6, ptr %t57)
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
  %t73 = inttoptr i64 125 to ptr
  %t74 = getelementptr ptr, ptr %t72, i32 0
  store ptr %t73, ptr %t74
  call void @__inc_ref(ptr %t68)
  %t75 = getelementptr ptr, ptr %t72, i32 1
  store ptr %t68, ptr %t75
  %t76 = getelementptr ptr, ptr %t69, i32 1
  store ptr %t72, ptr %t76
  %t77 = call ptr @v__apply__lift_63(ptr %t6, ptr %t69)
  call void @__free_recursive(ptr %t68)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t77, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t78 = load ptr, ptr %t2
  ret ptr %t78
}

define internal ptr @v__apply__lift_63(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 257, label %tco.case.arm.257.11 i64 258, label %tco.case.arm.258.12 ]
tco.case.arm.257.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.258.12:
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

define internal ptr @v__lift_66(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 259 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__lift_66(ptr %v___input, ptr %t0)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t3
}

define internal ptr @v__cps__lift_66(ptr %v___input, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.19 i64 7, label %tco.case.arm.7.27 i64 8, label %tco.case.arm.8.50 i64 9, label %tco.case.arm.9.62 ]
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
  %t18 = call ptr @v__apply__lift_66(ptr %t6, ptr %t14)
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
  %t26 = call ptr @v__apply__lift_66(ptr %t6, ptr %t22)
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
  %t42 = inttoptr i64 260 to ptr
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
  %t45 = inttoptr i64 260 to ptr
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
  %t57 = inttoptr i64 126 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  call void @__inc_ref(ptr %t52)
  %t59 = getelementptr ptr, ptr %t56, i32 1
  store ptr %t52, ptr %t59
  %t60 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t56, ptr %t60
  %t61 = call ptr @v__apply__lift_66(ptr %t6, ptr %t53)
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
  %t69 = inttoptr i64 127 to ptr
  %t70 = getelementptr ptr, ptr %t68, i32 0
  store ptr %t69, ptr %t70
  call void @__inc_ref(ptr %t64)
  %t71 = getelementptr ptr, ptr %t68, i32 1
  store ptr %t64, ptr %t71
  %t72 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t68, ptr %t72
  %t73 = call ptr @v__apply__lift_66(ptr %t6, ptr %t65)
  call void @__free_recursive(ptr %t64)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t73, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t74 = load ptr, ptr %t2
  ret ptr %t74
}

define internal ptr @v__apply__lift_66(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 259, label %tco.case.arm.259.11 i64 260, label %tco.case.arm.260.12 ]
tco.case.arm.259.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.260.12:
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

define internal ptr @v__lam_71(ptr %v__u) {
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

define internal ptr @v__lam_72(ptr %v_act, ptr %v__u) {
  call void @__free_recursive(ptr %v__u)
  ret ptr %v_act
}

define internal ptr @v__lam_73(ptr %v__u) {
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

define internal ptr @v__lift_74(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 261 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__lift_74(ptr %v___input, ptr %t0)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t3
}

define internal ptr @v__cps__lift_74(ptr %v___input, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.19 i64 7, label %tco.case.arm.7.27 i64 8, label %tco.case.arm.8.50 i64 9, label %tco.case.arm.9.62 ]
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
  %t18 = call ptr @v__apply__lift_74(ptr %t6, ptr %t14)
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
  %t26 = call ptr @v__apply__lift_74(ptr %t6, ptr %t22)
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
  %t42 = inttoptr i64 262 to ptr
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
  %t45 = inttoptr i64 262 to ptr
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
  %t57 = inttoptr i64 128 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  call void @__inc_ref(ptr %t52)
  %t59 = getelementptr ptr, ptr %t56, i32 1
  store ptr %t52, ptr %t59
  %t60 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t56, ptr %t60
  %t61 = call ptr @v__apply__lift_74(ptr %t6, ptr %t53)
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
  %t69 = inttoptr i64 129 to ptr
  %t70 = getelementptr ptr, ptr %t68, i32 0
  store ptr %t69, ptr %t70
  call void @__inc_ref(ptr %t64)
  %t71 = getelementptr ptr, ptr %t68, i32 1
  store ptr %t64, ptr %t71
  %t72 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t68, ptr %t72
  %t73 = call ptr @v__apply__lift_74(ptr %t6, ptr %t65)
  call void @__free_recursive(ptr %t64)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t73, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t74 = load ptr, ptr %t2
  ret ptr %t74
}

define internal ptr @v__apply__lift_74(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 261, label %tco.case.arm.261.11 i64 262, label %tco.case.arm.262.12 ]
tco.case.arm.261.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.262.12:
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

define internal ptr @v__lam_77(ptr %v__u) {
  %t0 = call ptr @v_wOk()
  %t1 = call ptr @v_observeThree(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.9, i64 12), ptr %t1)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t2
}

define internal ptr @v__lam_78(ptr %v__u) {
  %t0 = call ptr @v_wE3()
  %t1 = call ptr @v_observeThree(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.10, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_74(ptr %t2)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t3
}

define internal ptr @v__lam_79(ptr %v__u) {
  %t0 = call ptr @v_wE2str()
  %t1 = call ptr @v_observeThree(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.11, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_74(ptr %t2)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t3
}

define internal ptr @v__lam_80(ptr %v__u) {
  %t0 = call ptr @v_wE1()
  %t1 = call ptr @v_observeThree(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.12, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_74(ptr %t2)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t3
}

define internal ptr @v__lam_81(ptr %v__u) {
  %t0 = call ptr @v_idem2Second()
  %t1 = call ptr @v_observeTwo(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.13, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_74(ptr %t2)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t3
}

define internal ptr @v__lam_82(ptr %v__u) {
  %t0 = call ptr @v_idem2First()
  %t1 = call ptr @v_observeTwo(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.14, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_74(ptr %t2)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t3
}

define internal ptr @v__lam_83(ptr %v__u) {
  %t0 = call ptr @v_idemE2()
  %t1 = call ptr @v_observeA(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.15, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_74(ptr %t2)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t3
}

define internal ptr @v__lam_84(ptr %v__u) {
  %t0 = call ptr @v_idemE1()
  %t1 = call ptr @v_observeA(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.16, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_74(ptr %t2)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t3
}

define internal ptr @v__lam_85(ptr %v__u) {
  %t0 = call ptr @v_twoOk()
  %t1 = call ptr @v_observeTwoA(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.17, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_74(ptr %t2)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t3
}

define internal ptr @v__lam_86(ptr %v__u) {
  %t0 = call ptr @v_twoE2()
  %t1 = call ptr @v_observeTwoA(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.18, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_74(ptr %t2)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t3
}

define internal ptr @v__lam_87(ptr %v__u) {
  %t0 = call ptr @v_twoSecond()
  %t1 = call ptr @v_observeTwoA(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.19, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_74(ptr %t2)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t3
}

define internal ptr @v__lam_88(ptr %v__u) {
  %t0 = call ptr @v_twoFirst()
  %t1 = call ptr @v_observeTwoA(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.20, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_74(ptr %t2)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t3
}

define internal ptr @v__lam_89(ptr %v__u) {
  %t0 = call ptr @v_abE2()
  %t1 = call ptr @v_observeAB(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.21, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_74(ptr %t2)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t3
}

define internal ptr @v__lam_90(ptr %v__u) {
  %t0 = call ptr @v_abE1()
  %t1 = call ptr @v_observeAB(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.22, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_74(ptr %t2)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t3
}

define internal ptr @v__lam_91(ptr %v__u) {
  %t0 = call ptr @v_strIdem()
  %t1 = call ptr @v_observeStr(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.23, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_74(ptr %t2)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t3
}

define internal ptr @v__lam_92(ptr %v__u) {
  %t0 = call ptr @v_strE2()
  %t1 = call ptr @v_observeStrA(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.24, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_74(ptr %t2)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t3
}

define internal ptr @v__lam_93(ptr %v__u) {
  %t0 = call ptr @v_strE1()
  %t1 = call ptr @v_observeStrA(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.25, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_74(ptr %t2)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t3
}

define internal ptr @v__lam_94(ptr %v__u) {
  %t0 = call ptr @v_strOk()
  %t1 = call ptr @v_observeStrA(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.26, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_74(ptr %t2)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t3
}

define internal ptr @v__lam_95(ptr %v__u) {
  %t0 = call ptr @v_pureNever()
  %t1 = call ptr @v_observeNever(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.27, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_74(ptr %t2)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t3
}

define internal ptr @v__lam_96(ptr %v__u) {
  %t0 = call ptr @v_nevRightE1()
  %t1 = call ptr @v_observeA(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.28, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_74(ptr %t2)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t3
}

define internal ptr @v__lam_97(ptr %v__u) {
  %t0 = call ptr @v_nevRightOk()
  %t1 = call ptr @v_observeA(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.29, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_74(ptr %t2)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t3
}

define internal ptr @v__lam_98(ptr %v__u) {
  %t0 = call ptr @v_nevFail()
  %t1 = call ptr @v_observeA(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.30, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_74(ptr %t2)
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

define internal ptr @v__df_bindEither_0(ptr %v_x) {
  %t0 = getelementptr ptr, ptr %v_x, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.11 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v_x, i32 1
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
  call void @__free_recursive(ptr %v_x)
  ret ptr %t7
case.arm.4.11:
  %t12 = getelementptr ptr, ptr %v_x, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v_kAOk(ptr %t13)
  %t15 = call ptr @v__lift_0(ptr %t14)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t15
case.default.3:
  unreachable
}

define internal ptr @v__df_bindEither_1(ptr %v_x) {
  %t0 = getelementptr ptr, ptr %v_x, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.11 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v_x, i32 1
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
  call void @__free_recursive(ptr %v_x)
  ret ptr %t7
case.arm.4.11:
  %t12 = getelementptr ptr, ptr %v_x, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v_kAFail(ptr %t13)
  %t15 = call ptr @v__lift_0(ptr %t14)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t15
case.default.3:
  unreachable
}

define internal ptr @v__df_bindEither_2(ptr %v_x) {
  %t0 = getelementptr ptr, ptr %v_x, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.11 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v_x, i32 1
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
  call void @__free_recursive(ptr %v_x)
  ret ptr %t7
case.arm.4.11:
  %t12 = getelementptr ptr, ptr %v_x, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v_kNever(ptr %t13)
  %t15 = call ptr @v__lift_0(ptr %t14)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t15
case.default.3:
  unreachable
}

define internal ptr @v__df__rowspec_15_3(ptr %v_x) {
  %t0 = getelementptr ptr, ptr %v_x, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.15 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v_x, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = call ptr @__alloc(i64 16, i32 1)
  %t8 = inttoptr i64 3 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = call ptr @__alloc(i64 16, i32 1)
  %t11 = inttoptr i64 1615808600 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  call void @__inc_ref(ptr %t6)
  %t13 = getelementptr ptr, ptr %t10, i32 1
  store ptr %t6, ptr %t13
  %t14 = getelementptr ptr, ptr %t7, i32 1
  store ptr %t10, ptr %t14
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t7
case.arm.4.15:
  %t16 = getelementptr ptr, ptr %v_x, i32 1
  %t17 = load ptr, ptr %t16
  call void @__inc_ref(ptr %t17)
  call void @__inc_ref(ptr %t17)
  %t18 = call ptr @v_kAOk(ptr %t17)
  %t19 = call ptr @v__lift_16(ptr %t18)
  call void @__free_recursive(ptr %t17)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t19
case.default.3:
  unreachable
}

define internal ptr @v__df__rowspec_15_4(ptr %v_x) {
  %t0 = getelementptr ptr, ptr %v_x, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.15 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v_x, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = call ptr @__alloc(i64 16, i32 1)
  %t8 = inttoptr i64 3 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = call ptr @__alloc(i64 16, i32 1)
  %t11 = inttoptr i64 1615808600 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  call void @__inc_ref(ptr %t6)
  %t13 = getelementptr ptr, ptr %t10, i32 1
  store ptr %t6, ptr %t13
  %t14 = getelementptr ptr, ptr %t7, i32 1
  store ptr %t10, ptr %t14
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t7
case.arm.4.15:
  %t16 = getelementptr ptr, ptr %v_x, i32 1
  %t17 = load ptr, ptr %t16
  call void @__inc_ref(ptr %t17)
  call void @__inc_ref(ptr %t17)
  %t18 = call ptr @v_kAFail(ptr %t17)
  %t19 = call ptr @v__lift_16(ptr %t18)
  call void @__free_recursive(ptr %t17)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t19
case.default.3:
  unreachable
}

define internal ptr @v__df_bindEither_5(ptr %v_x) {
  %t0 = getelementptr ptr, ptr %v_x, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.11 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v_x, i32 1
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
  call void @__free_recursive(ptr %v_x)
  ret ptr %t7
case.arm.4.11:
  %t12 = getelementptr ptr, ptr %v_x, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v_kSFail(ptr %t13)
  %t15 = call ptr @v__lift_0(ptr %t14)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t15
case.default.3:
  unreachable
}

define internal ptr @v__df__rowspec_17_6(ptr %v_x) {
  %t0 = getelementptr ptr, ptr %v_x, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.15 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v_x, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = call ptr @__alloc(i64 16, i32 1)
  %t8 = inttoptr i64 3 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = call ptr @__alloc(i64 16, i32 1)
  %t11 = inttoptr i64 2252990199 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  call void @__inc_ref(ptr %t6)
  %t13 = getelementptr ptr, ptr %t10, i32 1
  store ptr %t6, ptr %t13
  %t14 = getelementptr ptr, ptr %t7, i32 1
  store ptr %t10, ptr %t14
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t7
case.arm.4.15:
  %t16 = getelementptr ptr, ptr %v_x, i32 1
  %t17 = load ptr, ptr %t16
  call void @__inc_ref(ptr %t17)
  call void @__inc_ref(ptr %t17)
  %t18 = call ptr @v_kBFail(ptr %t17)
  %t19 = call ptr @v__lift_18(ptr %t18)
  call void @__free_recursive(ptr %t17)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t19
case.default.3:
  unreachable
}

define internal ptr @v__df__rowspec_19_7(ptr %v_x) {
  %t0 = getelementptr ptr, ptr %v_x, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.15 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v_x, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = call ptr @__alloc(i64 16, i32 1)
  %t8 = inttoptr i64 3 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = call ptr @__alloc(i64 16, i32 1)
  %t11 = inttoptr i64 925038822 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  call void @__inc_ref(ptr %t6)
  %t13 = getelementptr ptr, ptr %t10, i32 1
  store ptr %t6, ptr %t13
  %t14 = getelementptr ptr, ptr %t7, i32 1
  store ptr %t10, ptr %t14
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t7
case.arm.4.15:
  %t16 = getelementptr ptr, ptr %v_x, i32 1
  %t17 = load ptr, ptr %t16
  call void @__inc_ref(ptr %t17)
  call void @__inc_ref(ptr %t17)
  %t18 = call ptr @v_kAOk(ptr %t17)
  %t19 = call ptr @v__lift_20(ptr %t18)
  call void @__free_recursive(ptr %t17)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t19
case.default.3:
  unreachable
}

define internal ptr @v__df__rowspec_19_8(ptr %v_x) {
  %t0 = getelementptr ptr, ptr %v_x, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.15 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v_x, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = call ptr @__alloc(i64 16, i32 1)
  %t8 = inttoptr i64 3 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = call ptr @__alloc(i64 16, i32 1)
  %t11 = inttoptr i64 925038822 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  call void @__inc_ref(ptr %t6)
  %t13 = getelementptr ptr, ptr %t10, i32 1
  store ptr %t6, ptr %t13
  %t14 = getelementptr ptr, ptr %t7, i32 1
  store ptr %t10, ptr %t14
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t7
case.arm.4.15:
  %t16 = getelementptr ptr, ptr %v_x, i32 1
  %t17 = load ptr, ptr %t16
  call void @__inc_ref(ptr %t17)
  call void @__inc_ref(ptr %t17)
  %t18 = call ptr @v_kAFail(ptr %t17)
  %t19 = call ptr @v__lift_20(ptr %t18)
  call void @__free_recursive(ptr %t17)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t19
case.default.3:
  unreachable
}

define internal ptr @v__df_bindEither_9(ptr %v_x) {
  %t0 = getelementptr ptr, ptr %v_x, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.11 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v_x, i32 1
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
  call void @__free_recursive(ptr %v_x)
  ret ptr %t7
case.arm.4.11:
  %t12 = getelementptr ptr, ptr %v_x, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v_kSecond(ptr %t13)
  %t15 = call ptr @v__lift_0(ptr %t14)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t15
case.default.3:
  unreachable
}

define internal ptr @v__df__rowspec_21_10(ptr %v_x) {
  %t0 = getelementptr ptr, ptr %v_x, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.11 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v_x, i32 1
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
  call void @__free_recursive(ptr %v_x)
  ret ptr %t7
case.arm.4.11:
  %t12 = getelementptr ptr, ptr %v_x, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v_kAOk(ptr %t13)
  %t15 = call ptr @v__lift_22(ptr %t14)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t15
case.default.3:
  unreachable
}

define internal ptr @v__df__rowspec_23_11(ptr %v_x) {
  %t0 = getelementptr ptr, ptr %v_x, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.15 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v_x, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = call ptr @__alloc(i64 16, i32 1)
  %t8 = inttoptr i64 3 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = call ptr @__alloc(i64 16, i32 1)
  %t11 = inttoptr i64 925038822 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  call void @__inc_ref(ptr %t6)
  %t13 = getelementptr ptr, ptr %t10, i32 1
  store ptr %t6, ptr %t13
  %t14 = getelementptr ptr, ptr %t7, i32 1
  store ptr %t10, ptr %t14
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t7
case.arm.4.15:
  %t16 = getelementptr ptr, ptr %v_x, i32 1
  %t17 = load ptr, ptr %t16
  call void @__inc_ref(ptr %t17)
  call void @__inc_ref(ptr %t17)
  %t18 = call ptr @v_kSOk(ptr %t17)
  %t19 = call ptr @v__lift_24(ptr %t18)
  call void @__free_recursive(ptr %t17)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t19
case.default.3:
  unreachable
}

define internal ptr @v__df__rowspec_23_12(ptr %v_x) {
  %t0 = getelementptr ptr, ptr %v_x, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.15 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v_x, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = call ptr @__alloc(i64 16, i32 1)
  %t8 = inttoptr i64 3 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = call ptr @__alloc(i64 16, i32 1)
  %t11 = inttoptr i64 925038822 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  call void @__inc_ref(ptr %t6)
  %t13 = getelementptr ptr, ptr %t10, i32 1
  store ptr %t6, ptr %t13
  %t14 = getelementptr ptr, ptr %t7, i32 1
  store ptr %t10, ptr %t14
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t7
case.arm.4.15:
  %t16 = getelementptr ptr, ptr %v_x, i32 1
  %t17 = load ptr, ptr %t16
  call void @__inc_ref(ptr %t17)
  call void @__inc_ref(ptr %t17)
  %t18 = call ptr @v_kSFail(ptr %t17)
  %t19 = call ptr @v__lift_24(ptr %t18)
  call void @__free_recursive(ptr %t17)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t19
case.default.3:
  unreachable
}

define internal ptr @v__df__rowspec_21_13(ptr %v_x) {
  %t0 = getelementptr ptr, ptr %v_x, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.11 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v_x, i32 1
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
  call void @__free_recursive(ptr %v_x)
  ret ptr %t7
case.arm.4.11:
  %t12 = getelementptr ptr, ptr %v_x, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v_kAFail(ptr %t13)
  %t15 = call ptr @v__lift_22(ptr %t14)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t15
case.default.3:
  unreachable
}

define internal ptr @v__df_handleErrorIO_14(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 263 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_handleErrorIO_14(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_handleErrorIO_14(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.19 i64 7, label %tco.case.arm.7.24 i64 8, label %tco.case.arm.8.47 i64 9, label %tco.case.arm.9.59 ]
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
  %t18 = call ptr @v__apply__df_handleErrorIO_14(ptr %t6, ptr %t14)
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
  %t22 = call ptr @v_handlerA(ptr %t21)
  %t23 = call ptr @v__apply__df_handleErrorIO_14(ptr %t6, ptr %t22)
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
  %t39 = inttoptr i64 264 to ptr
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
  %t42 = inttoptr i64 264 to ptr
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
  %t54 = inttoptr i64 26 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  call void @__inc_ref(ptr %t49)
  %t56 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t49, ptr %t56
  %t57 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t53, ptr %t57
  %t58 = call ptr @v__apply__df_handleErrorIO_14(ptr %t6, ptr %t50)
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
  %t66 = inttoptr i64 33 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  call void @__inc_ref(ptr %t61)
  %t68 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t61, ptr %t68
  %t69 = getelementptr ptr, ptr %t62, i32 1
  store ptr %t65, ptr %t69
  %t70 = call ptr @v__apply__df_handleErrorIO_14(ptr %t6, ptr %t62)
  call void @__free_recursive(ptr %t61)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t70, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t71 = load ptr, ptr %t2
  ret ptr %t71
}

define internal ptr @v__apply__df_handleErrorIO_14(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 263, label %tco.case.arm.263.11 i64 264, label %tco.case.arm.264.12 ]
tco.case.arm.263.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.264.12:
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

define internal ptr @v__df_andThenIO_17(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 265 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_17(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_17(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.17 i64 7, label %tco.case.arm.7.25 i64 8, label %tco.case.arm.8.48 i64 9, label %tco.case.arm.9.60 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__bi_IO_Stdout_print(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_17(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_17(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 266 to ptr
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
  %t43 = inttoptr i64 266 to ptr
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
  %t55 = inttoptr i64 49 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df_andThenIO_17(ptr %t6, ptr %t51)
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
  %t71 = call ptr @v__apply__df_andThenIO_17(ptr %t6, ptr %t63)
  call void @__free_recursive(ptr %t62)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t72 = load ptr, ptr %t2
  ret ptr %t72
}

define internal ptr @v__apply__df_andThenIO_17(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 265, label %tco.case.arm.265.11 i64 266, label %tco.case.arm.266.12 ]
tco.case.arm.265.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.266.12:
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
  %t1 = inttoptr i64 267 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.20 i64 7, label %tco.case.arm.7.28 i64 8, label %tco.case.arm.8.51 i64 9, label %tco.case.arm.9.63 ]
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
  %t43 = inttoptr i64 268 to ptr
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
  %t46 = inttoptr i64 268 to ptr
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
  %t58 = inttoptr i64 96 to ptr
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
  %t70 = inttoptr i64 100 to ptr
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
tco.case.default.10:
  unreachable
tco.exit.1:
  %t75 = load ptr, ptr %t2
  ret ptr %t75
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
  switch i64 %t9, label %tco.case.default.10 [ i64 267, label %tco.case.arm.267.11 i64 268, label %tco.case.arm.268.12 ]
tco.case.arm.267.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.268.12:
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

define internal ptr @v__df_handleErrorIO_23(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 269 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_handleErrorIO_23(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_handleErrorIO_23(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.19 i64 7, label %tco.case.arm.7.24 i64 8, label %tco.case.arm.8.47 i64 9, label %tco.case.arm.9.59 ]
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
  %t18 = call ptr @v__apply__df_handleErrorIO_23(ptr %t6, ptr %t14)
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
  %t22 = call ptr @v_handlerTwo(ptr %t21)
  %t23 = call ptr @v__apply__df_handleErrorIO_23(ptr %t6, ptr %t22)
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
  %t39 = inttoptr i64 270 to ptr
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
  %t42 = inttoptr i64 270 to ptr
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
  %t58 = call ptr @v__apply__df_handleErrorIO_23(ptr %t6, ptr %t50)
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
  %t66 = inttoptr i64 34 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  call void @__inc_ref(ptr %t61)
  %t68 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t61, ptr %t68
  %t69 = getelementptr ptr, ptr %t62, i32 1
  store ptr %t65, ptr %t69
  %t70 = call ptr @v__apply__df_handleErrorIO_23(ptr %t6, ptr %t62)
  call void @__free_recursive(ptr %t61)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t70, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t71 = load ptr, ptr %t2
  ret ptr %t71
}

define internal ptr @v__apply__df_handleErrorIO_23(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 269, label %tco.case.arm.269.11 i64 270, label %tco.case.arm.270.12 ]
tco.case.arm.269.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.270.12:
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

define internal ptr @v__df_handleErrorIO_26(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 271 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_handleErrorIO_26(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_handleErrorIO_26(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.19 i64 7, label %tco.case.arm.7.24 i64 8, label %tco.case.arm.8.47 i64 9, label %tco.case.arm.9.59 ]
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
  %t18 = call ptr @v__apply__df_handleErrorIO_26(ptr %t6, ptr %t14)
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
  %t22 = call ptr @v_handlerStr(ptr %t21)
  %t23 = call ptr @v__apply__df_handleErrorIO_26(ptr %t6, ptr %t22)
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
  %t39 = inttoptr i64 272 to ptr
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
  %t42 = inttoptr i64 272 to ptr
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
  %t58 = call ptr @v__apply__df_handleErrorIO_26(ptr %t6, ptr %t50)
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
  %t66 = inttoptr i64 35 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  call void @__inc_ref(ptr %t61)
  %t68 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t61, ptr %t68
  %t69 = getelementptr ptr, ptr %t62, i32 1
  store ptr %t65, ptr %t69
  %t70 = call ptr @v__apply__df_handleErrorIO_26(ptr %t6, ptr %t62)
  call void @__free_recursive(ptr %t61)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t70, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t71 = load ptr, ptr %t2
  ret ptr %t71
}

define internal ptr @v__apply__df_handleErrorIO_26(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 271, label %tco.case.arm.271.11 i64 272, label %tco.case.arm.272.12 ]
tco.case.arm.271.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.272.12:
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

define internal ptr @v__df_handleErrorIO_29(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 273 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_handleErrorIO_29(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_handleErrorIO_29(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.19 i64 7, label %tco.case.arm.7.24 i64 8, label %tco.case.arm.8.47 i64 9, label %tco.case.arm.9.59 ]
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
  %t18 = call ptr @v__apply__df_handleErrorIO_29(ptr %t6, ptr %t14)
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
  %t22 = call ptr @v_handlerStrA(ptr %t21)
  %t23 = call ptr @v__apply__df_handleErrorIO_29(ptr %t6, ptr %t22)
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
  %t39 = inttoptr i64 274 to ptr
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
  %t42 = inttoptr i64 274 to ptr
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
  %t58 = call ptr @v__apply__df_handleErrorIO_29(ptr %t6, ptr %t50)
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
  %t70 = call ptr @v__apply__df_handleErrorIO_29(ptr %t6, ptr %t62)
  call void @__free_recursive(ptr %t61)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t70, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t71 = load ptr, ptr %t2
  ret ptr %t71
}

define internal ptr @v__apply__df_handleErrorIO_29(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 273, label %tco.case.arm.273.11 i64 274, label %tco.case.arm.274.12 ]
tco.case.arm.273.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.274.12:
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

define internal ptr @v__df__rowspec_35_32(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 275 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df__rowspec_35_32(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df__rowspec_35_32(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.17 i64 7, label %tco.case.arm.7.25 i64 8, label %tco.case.arm.8.48 i64 9, label %tco.case.arm.9.60 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__bi_IO_Stdout_print(ptr %t13)
  %t15 = call ptr @v__lift_36(ptr %t14)
  %t16 = call ptr @v__apply__df__rowspec_35_32(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df__rowspec_35_32(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 276 to ptr
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
  %t43 = inttoptr i64 276 to ptr
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
  %t59 = call ptr @v__apply__df__rowspec_35_32(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 67 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df__rowspec_35_32(ptr %t6, ptr %t63)
  call void @__free_recursive(ptr %t62)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t72 = load ptr, ptr %t2
  ret ptr %t72
}

define internal ptr @v__apply__df__rowspec_35_32(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 275, label %tco.case.arm.275.11 i64 276, label %tco.case.arm.276.12 ]
tco.case.arm.275.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.276.12:
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

define internal ptr @v__df_handleErrorIO_35(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 277 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_handleErrorIO_35(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_handleErrorIO_35(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.19 i64 7, label %tco.case.arm.7.24 i64 8, label %tco.case.arm.8.47 i64 9, label %tco.case.arm.9.59 ]
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
  %t18 = call ptr @v__apply__df_handleErrorIO_35(ptr %t6, ptr %t14)
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
  %t23 = call ptr @v__apply__df_handleErrorIO_35(ptr %t6, ptr %t22)
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
  %t39 = inttoptr i64 278 to ptr
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
  %t42 = inttoptr i64 278 to ptr
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
  %t58 = call ptr @v__apply__df_handleErrorIO_35(ptr %t6, ptr %t50)
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
  %t70 = call ptr @v__apply__df_handleErrorIO_35(ptr %t6, ptr %t62)
  call void @__free_recursive(ptr %t61)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t70, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t71 = load ptr, ptr %t2
  ret ptr %t71
}

define internal ptr @v__apply__df_handleErrorIO_35(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 277, label %tco.case.arm.277.11 i64 278, label %tco.case.arm.278.12 ]
tco.case.arm.277.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.278.12:
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

define internal ptr @v__df__rowspec_44_38(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 279 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df__rowspec_44_38(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df__rowspec_44_38(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.17 i64 7, label %tco.case.arm.7.25 i64 8, label %tco.case.arm.8.48 i64 9, label %tco.case.arm.9.60 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__bi_IO_Stdout_print(ptr %t13)
  %t15 = call ptr @v__lift_45(ptr %t14)
  %t16 = call ptr @v__apply__df__rowspec_44_38(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df__rowspec_44_38(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 280 to ptr
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
  %t43 = inttoptr i64 280 to ptr
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
  %t55 = inttoptr i64 94 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df__rowspec_44_38(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 95 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df__rowspec_44_38(ptr %t6, ptr %t63)
  call void @__free_recursive(ptr %t62)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t72 = load ptr, ptr %t2
  ret ptr %t72
}

define internal ptr @v__apply__df__rowspec_44_38(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 279, label %tco.case.arm.279.11 i64 280, label %tco.case.arm.280.12 ]
tco.case.arm.279.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.280.12:
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

define internal ptr @v__df_handleErrorIO_41(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 281 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_handleErrorIO_41(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_handleErrorIO_41(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.19 i64 7, label %tco.case.arm.7.24 i64 8, label %tco.case.arm.8.47 i64 9, label %tco.case.arm.9.59 ]
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
  %t18 = call ptr @v__apply__df_handleErrorIO_41(ptr %t6, ptr %t14)
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
  %t22 = call ptr @v_handlerTwoA(ptr %t21)
  %t23 = call ptr @v__apply__df_handleErrorIO_41(ptr %t6, ptr %t22)
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
  %t39 = inttoptr i64 282 to ptr
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
  %t42 = inttoptr i64 282 to ptr
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
  %t58 = call ptr @v__apply__df_handleErrorIO_41(ptr %t6, ptr %t50)
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
  %t70 = call ptr @v__apply__df_handleErrorIO_41(ptr %t6, ptr %t62)
  call void @__free_recursive(ptr %t61)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t70, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t71 = load ptr, ptr %t2
  ret ptr %t71
}

define internal ptr @v__apply__df_handleErrorIO_41(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 281, label %tco.case.arm.281.11 i64 282, label %tco.case.arm.282.12 ]
tco.case.arm.281.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.282.12:
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

define internal ptr @v__df__rowspec_53_44(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 283 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df__rowspec_53_44(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df__rowspec_53_44(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.17 i64 7, label %tco.case.arm.7.25 i64 8, label %tco.case.arm.8.48 i64 9, label %tco.case.arm.9.60 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__bi_IO_Stdout_print(ptr %t13)
  %t15 = call ptr @v__lift_54(ptr %t14)
  %t16 = call ptr @v__apply__df__rowspec_53_44(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df__rowspec_53_44(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 284 to ptr
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
  %t43 = inttoptr i64 284 to ptr
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
  %t55 = inttoptr i64 97 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df__rowspec_53_44(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 98 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df__rowspec_53_44(ptr %t6, ptr %t63)
  call void @__free_recursive(ptr %t62)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t72 = load ptr, ptr %t2
  ret ptr %t72
}

define internal ptr @v__apply__df__rowspec_53_44(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 283, label %tco.case.arm.283.11 i64 284, label %tco.case.arm.284.12 ]
tco.case.arm.283.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.284.12:
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

define internal ptr @v__df_handleErrorIO_47(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 285 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_handleErrorIO_47(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_handleErrorIO_47(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.19 i64 7, label %tco.case.arm.7.24 i64 8, label %tco.case.arm.8.47 i64 9, label %tco.case.arm.9.59 ]
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
  %t18 = call ptr @v__apply__df_handleErrorIO_47(ptr %t6, ptr %t14)
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
  %t22 = call ptr @v_handlerThree(ptr %t21)
  %t23 = call ptr @v__apply__df_handleErrorIO_47(ptr %t6, ptr %t22)
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
  %t39 = inttoptr i64 286 to ptr
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
  %t42 = inttoptr i64 286 to ptr
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
  %t58 = call ptr @v__apply__df_handleErrorIO_47(ptr %t6, ptr %t50)
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
  %t70 = call ptr @v__apply__df_handleErrorIO_47(ptr %t6, ptr %t62)
  call void @__free_recursive(ptr %t61)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t70, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t71 = load ptr, ptr %t2
  ret ptr %t71
}

define internal ptr @v__apply__df_handleErrorIO_47(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 285, label %tco.case.arm.285.11 i64 286, label %tco.case.arm.286.12 ]
tco.case.arm.285.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.286.12:
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

define internal ptr @v__df__rowspec_62_50(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 287 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df__rowspec_62_50(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df__rowspec_62_50(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.17 i64 7, label %tco.case.arm.7.25 i64 8, label %tco.case.arm.8.48 i64 9, label %tco.case.arm.9.60 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__bi_IO_Stdout_print(ptr %t13)
  %t15 = call ptr @v__lift_63(ptr %t14)
  %t16 = call ptr @v__apply__df__rowspec_62_50(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df__rowspec_62_50(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 288 to ptr
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
  %t43 = inttoptr i64 288 to ptr
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
  %t55 = inttoptr i64 99 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df__rowspec_62_50(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 101 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df__rowspec_62_50(ptr %t6, ptr %t63)
  call void @__free_recursive(ptr %t62)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t72 = load ptr, ptr %t2
  ret ptr %t72
}

define internal ptr @v__apply__df__rowspec_62_50(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 287, label %tco.case.arm.287.11 i64 288, label %tco.case.arm.288.12 ]
tco.case.arm.287.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.288.12:
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

define internal ptr @v__df_andThenIO_53(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 289 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_53(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_53(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.17 i64 7, label %tco.case.arm.7.25 i64 8, label %tco.case.arm.8.48 i64 9, label %tco.case.arm.9.60 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_71(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_53(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_53(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 290 to ptr
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
  %t43 = inttoptr i64 290 to ptr
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
  %t55 = inttoptr i64 50 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df_andThenIO_53(ptr %t6, ptr %t51)
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
  %t71 = call ptr @v__apply__df_andThenIO_53(ptr %t6, ptr %t63)
  call void @__free_recursive(ptr %t62)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t72 = load ptr, ptr %t2
  ret ptr %t72
}

define internal ptr @v__apply__df_andThenIO_53(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 289, label %tco.case.arm.289.11 i64 290, label %tco.case.arm.290.12 ]
tco.case.arm.289.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.290.12:
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
  %t1 = inttoptr i64 291 to ptr
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
  switch i64 %t11, label %tco.case.default.12 [ i64 5, label %tco.case.arm.5.13 i64 6, label %tco.case.arm.6.19 i64 7, label %tco.case.arm.7.27 i64 8, label %tco.case.arm.8.50 i64 9, label %tco.case.arm.9.63 ]
tco.case.arm.5.13:
  %t14 = getelementptr ptr, ptr %t6, i32 1
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  call void @__inc_ref(ptr %t8)
  call void @__inc_ref(ptr %t7)
  call void @__inc_ref(ptr %t15)
  %t16 = call ptr @v__lam_72(ptr %t7, ptr %t15)
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
  %t42 = inttoptr i64 292 to ptr
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
  %t45 = inttoptr i64 292 to ptr
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
  %t57 = inttoptr i64 51 to ptr
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
  %t70 = inttoptr i64 80 to ptr
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
tco.case.default.12:
  unreachable
tco.exit.1:
  %t76 = load ptr, ptr %t2
  ret ptr %t76
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
  switch i64 %t9, label %tco.case.default.10 [ i64 291, label %tco.case.arm.291.11 i64 292, label %tco.case.arm.292.12 ]
tco.case.arm.291.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.292.12:
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

define internal ptr @v__df_andThenIO_59(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 293 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_59(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_59(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.17 i64 7, label %tco.case.arm.7.25 i64 8, label %tco.case.arm.8.48 i64 9, label %tco.case.arm.9.60 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_73(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_59(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_59(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 294 to ptr
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
  %t43 = inttoptr i64 294 to ptr
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
  %t55 = inttoptr i64 52 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df_andThenIO_59(ptr %t6, ptr %t51)
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
  %t71 = call ptr @v__apply__df_andThenIO_59(ptr %t6, ptr %t63)
  call void @__free_recursive(ptr %t62)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t72 = load ptr, ptr %t2
  ret ptr %t72
}

define internal ptr @v__apply__df_andThenIO_59(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 293, label %tco.case.arm.293.11 i64 294, label %tco.case.arm.294.12 ]
tco.case.arm.293.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.294.12:
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

define internal ptr @v__df_andThenIO_62(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 295 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_62(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_62(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.17 i64 7, label %tco.case.arm.7.25 i64 8, label %tco.case.arm.8.48 i64 9, label %tco.case.arm.9.60 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_77(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_62(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_62(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 296 to ptr
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
  %t43 = inttoptr i64 296 to ptr
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
  %t59 = call ptr @v__apply__df_andThenIO_62(ptr %t6, ptr %t51)
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
  %t71 = call ptr @v__apply__df_andThenIO_62(ptr %t6, ptr %t63)
  call void @__free_recursive(ptr %t62)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t72 = load ptr, ptr %t2
  ret ptr %t72
}

define internal ptr @v__apply__df_andThenIO_62(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 295, label %tco.case.arm.295.11 i64 296, label %tco.case.arm.296.12 ]
tco.case.arm.295.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.296.12:
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

define internal ptr @v__df_andThenIO_65(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 297 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_65(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_65(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.17 i64 7, label %tco.case.arm.7.25 i64 8, label %tco.case.arm.8.48 i64 9, label %tco.case.arm.9.60 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_78(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_65(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_65(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 298 to ptr
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
  %t43 = inttoptr i64 298 to ptr
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
  %t59 = call ptr @v__apply__df_andThenIO_65(ptr %t6, ptr %t51)
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
  %t71 = call ptr @v__apply__df_andThenIO_65(ptr %t6, ptr %t63)
  call void @__free_recursive(ptr %t62)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t72 = load ptr, ptr %t2
  ret ptr %t72
}

define internal ptr @v__apply__df_andThenIO_65(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 297, label %tco.case.arm.297.11 i64 298, label %tco.case.arm.298.12 ]
tco.case.arm.297.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.298.12:
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
  %t1 = inttoptr i64 299 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.17 i64 7, label %tco.case.arm.7.25 i64 8, label %tco.case.arm.8.48 i64 9, label %tco.case.arm.9.60 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_79(ptr %t13)
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
  %t40 = inttoptr i64 300 to ptr
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
  %t43 = inttoptr i64 300 to ptr
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
  %t67 = inttoptr i64 84 to ptr
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
tco.case.default.10:
  unreachable
tco.exit.1:
  %t72 = load ptr, ptr %t2
  ret ptr %t72
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
  switch i64 %t9, label %tco.case.default.10 [ i64 299, label %tco.case.arm.299.11 i64 300, label %tco.case.arm.300.12 ]
tco.case.arm.299.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.300.12:
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

define internal ptr @v__df_andThenIO_71(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 301 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_71(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_71(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.17 i64 7, label %tco.case.arm.7.25 i64 8, label %tco.case.arm.8.48 i64 9, label %tco.case.arm.9.60 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_80(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_71(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_71(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 302 to ptr
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
  %t43 = inttoptr i64 302 to ptr
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
  %t59 = call ptr @v__apply__df_andThenIO_71(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 85 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df_andThenIO_71(ptr %t6, ptr %t63)
  call void @__free_recursive(ptr %t62)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t72 = load ptr, ptr %t2
  ret ptr %t72
}

define internal ptr @v__apply__df_andThenIO_71(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 301, label %tco.case.arm.301.11 i64 302, label %tco.case.arm.302.12 ]
tco.case.arm.301.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.302.12:
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

define internal ptr @v__df_andThenIO_74(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 303 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_74(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_74(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.17 i64 7, label %tco.case.arm.7.25 i64 8, label %tco.case.arm.8.48 i64 9, label %tco.case.arm.9.60 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_81(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_74(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_74(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 304 to ptr
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
  %t43 = inttoptr i64 304 to ptr
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
  %t59 = call ptr @v__apply__df_andThenIO_74(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 86 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df_andThenIO_74(ptr %t6, ptr %t63)
  call void @__free_recursive(ptr %t62)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t72 = load ptr, ptr %t2
  ret ptr %t72
}

define internal ptr @v__apply__df_andThenIO_74(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 303, label %tco.case.arm.303.11 i64 304, label %tco.case.arm.304.12 ]
tco.case.arm.303.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.304.12:
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

define internal ptr @v__df_andThenIO_77(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 305 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_77(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_77(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.17 i64 7, label %tco.case.arm.7.25 i64 8, label %tco.case.arm.8.48 i64 9, label %tco.case.arm.9.60 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_82(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_77(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_77(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 306 to ptr
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
  %t43 = inttoptr i64 306 to ptr
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
  %t59 = call ptr @v__apply__df_andThenIO_77(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 87 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df_andThenIO_77(ptr %t6, ptr %t63)
  call void @__free_recursive(ptr %t62)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t72 = load ptr, ptr %t2
  ret ptr %t72
}

define internal ptr @v__apply__df_andThenIO_77(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 305, label %tco.case.arm.305.11 i64 306, label %tco.case.arm.306.12 ]
tco.case.arm.305.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.306.12:
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
  %t1 = inttoptr i64 307 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.17 i64 7, label %tco.case.arm.7.25 i64 8, label %tco.case.arm.8.48 i64 9, label %tco.case.arm.9.60 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_83(ptr %t13)
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
  %t40 = inttoptr i64 308 to ptr
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
  %t43 = inttoptr i64 308 to ptr
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
  %t67 = inttoptr i64 88 to ptr
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
tco.case.default.10:
  unreachable
tco.exit.1:
  %t72 = load ptr, ptr %t2
  ret ptr %t72
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
  switch i64 %t9, label %tco.case.default.10 [ i64 307, label %tco.case.arm.307.11 i64 308, label %tco.case.arm.308.12 ]
tco.case.arm.307.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.308.12:
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

define internal ptr @v__df_andThenIO_83(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 309 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_83(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_83(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.17 i64 7, label %tco.case.arm.7.25 i64 8, label %tco.case.arm.8.48 i64 9, label %tco.case.arm.9.60 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_84(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_83(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_83(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 310 to ptr
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
  %t43 = inttoptr i64 310 to ptr
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
  %t59 = call ptr @v__apply__df_andThenIO_83(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 89 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df_andThenIO_83(ptr %t6, ptr %t63)
  call void @__free_recursive(ptr %t62)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t72 = load ptr, ptr %t2
  ret ptr %t72
}

define internal ptr @v__apply__df_andThenIO_83(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 309, label %tco.case.arm.309.11 i64 310, label %tco.case.arm.310.12 ]
tco.case.arm.309.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.310.12:
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

define internal ptr @v__df_andThenIO_86(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 311 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_86(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_86(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.17 i64 7, label %tco.case.arm.7.25 i64 8, label %tco.case.arm.8.48 i64 9, label %tco.case.arm.9.60 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_85(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_86(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_86(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 312 to ptr
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
  %t43 = inttoptr i64 312 to ptr
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
  %t55 = inttoptr i64 61 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df_andThenIO_86(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 90 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df_andThenIO_86(ptr %t6, ptr %t63)
  call void @__free_recursive(ptr %t62)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t72 = load ptr, ptr %t2
  ret ptr %t72
}

define internal ptr @v__apply__df_andThenIO_86(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 311, label %tco.case.arm.311.11 i64 312, label %tco.case.arm.312.12 ]
tco.case.arm.311.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.312.12:
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

define internal ptr @v__df_andThenIO_89(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 313 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_89(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_89(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.17 i64 7, label %tco.case.arm.7.25 i64 8, label %tco.case.arm.8.48 i64 9, label %tco.case.arm.9.60 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_86(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_89(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_89(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 314 to ptr
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
  %t43 = inttoptr i64 314 to ptr
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
  %t59 = call ptr @v__apply__df_andThenIO_89(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 91 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df_andThenIO_89(ptr %t6, ptr %t63)
  call void @__free_recursive(ptr %t62)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t72 = load ptr, ptr %t2
  ret ptr %t72
}

define internal ptr @v__apply__df_andThenIO_89(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 313, label %tco.case.arm.313.11 i64 314, label %tco.case.arm.314.12 ]
tco.case.arm.313.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.314.12:
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
  %t1 = inttoptr i64 315 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.17 i64 7, label %tco.case.arm.7.25 i64 8, label %tco.case.arm.8.48 i64 9, label %tco.case.arm.9.60 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_87(ptr %t13)
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
  %t40 = inttoptr i64 316 to ptr
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
  %t43 = inttoptr i64 316 to ptr
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
  %t67 = inttoptr i64 92 to ptr
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
tco.case.default.10:
  unreachable
tco.exit.1:
  %t72 = load ptr, ptr %t2
  ret ptr %t72
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
  switch i64 %t9, label %tco.case.default.10 [ i64 315, label %tco.case.arm.315.11 i64 316, label %tco.case.arm.316.12 ]
tco.case.arm.315.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.316.12:
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

define internal ptr @v__df_andThenIO_95(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 317 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_95(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_95(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.17 i64 7, label %tco.case.arm.7.25 i64 8, label %tco.case.arm.8.48 i64 9, label %tco.case.arm.9.60 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_88(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_95(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_95(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 318 to ptr
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
  %t43 = inttoptr i64 318 to ptr
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
  %t59 = call ptr @v__apply__df_andThenIO_95(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 93 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df_andThenIO_95(ptr %t6, ptr %t63)
  call void @__free_recursive(ptr %t62)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t72 = load ptr, ptr %t2
  ret ptr %t72
}

define internal ptr @v__apply__df_andThenIO_95(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 317, label %tco.case.arm.317.11 i64 318, label %tco.case.arm.318.12 ]
tco.case.arm.317.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.318.12:
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

define internal ptr @v__df_andThenIO_98(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 319 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_98(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_98(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.17 i64 7, label %tco.case.arm.7.25 i64 8, label %tco.case.arm.8.48 i64 9, label %tco.case.arm.9.60 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_89(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_98(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_98(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 320 to ptr
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
  %t43 = inttoptr i64 320 to ptr
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
  %t59 = call ptr @v__apply__df_andThenIO_98(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 68 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df_andThenIO_98(ptr %t6, ptr %t63)
  call void @__free_recursive(ptr %t62)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t72 = load ptr, ptr %t2
  ret ptr %t72
}

define internal ptr @v__apply__df_andThenIO_98(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 319, label %tco.case.arm.319.11 i64 320, label %tco.case.arm.320.12 ]
tco.case.arm.319.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.320.12:
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

define internal ptr @v__df_andThenIO_101(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 321 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_101(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_101(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.17 i64 7, label %tco.case.arm.7.25 i64 8, label %tco.case.arm.8.48 i64 9, label %tco.case.arm.9.60 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_90(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_101(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_101(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 322 to ptr
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
  %t43 = inttoptr i64 322 to ptr
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
  %t55 = inttoptr i64 40 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df_andThenIO_101(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 69 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df_andThenIO_101(ptr %t6, ptr %t63)
  call void @__free_recursive(ptr %t62)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t72 = load ptr, ptr %t2
  ret ptr %t72
}

define internal ptr @v__apply__df_andThenIO_101(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 321, label %tco.case.arm.321.11 i64 322, label %tco.case.arm.322.12 ]
tco.case.arm.321.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.322.12:
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

define internal ptr @v__df_andThenIO_104(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 323 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_104(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_104(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.17 i64 7, label %tco.case.arm.7.25 i64 8, label %tco.case.arm.8.48 i64 9, label %tco.case.arm.9.60 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_91(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_104(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_104(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 324 to ptr
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
  %t43 = inttoptr i64 324 to ptr
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
  %t55 = inttoptr i64 41 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df_andThenIO_104(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 70 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df_andThenIO_104(ptr %t6, ptr %t63)
  call void @__free_recursive(ptr %t62)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t72 = load ptr, ptr %t2
  ret ptr %t72
}

define internal ptr @v__apply__df_andThenIO_104(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 323, label %tco.case.arm.323.11 i64 324, label %tco.case.arm.324.12 ]
tco.case.arm.323.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.324.12:
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

define internal ptr @v__df_andThenIO_107(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 325 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_107(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_107(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.17 i64 7, label %tco.case.arm.7.25 i64 8, label %tco.case.arm.8.48 i64 9, label %tco.case.arm.9.60 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_92(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_107(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_107(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 326 to ptr
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
  %t43 = inttoptr i64 326 to ptr
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
  %t55 = inttoptr i64 42 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df_andThenIO_107(ptr %t6, ptr %t51)
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
  %t71 = call ptr @v__apply__df_andThenIO_107(ptr %t6, ptr %t63)
  call void @__free_recursive(ptr %t62)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t72 = load ptr, ptr %t2
  ret ptr %t72
}

define internal ptr @v__apply__df_andThenIO_107(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 325, label %tco.case.arm.325.11 i64 326, label %tco.case.arm.326.12 ]
tco.case.arm.325.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.326.12:
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

define internal ptr @v__df_andThenIO_110(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 327 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_110(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_110(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.17 i64 7, label %tco.case.arm.7.25 i64 8, label %tco.case.arm.8.48 i64 9, label %tco.case.arm.9.60 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_93(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_110(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_110(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 328 to ptr
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
  %t43 = inttoptr i64 328 to ptr
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
  %t55 = inttoptr i64 43 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df_andThenIO_110(ptr %t6, ptr %t51)
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
  %t71 = call ptr @v__apply__df_andThenIO_110(ptr %t6, ptr %t63)
  call void @__free_recursive(ptr %t62)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t72 = load ptr, ptr %t2
  ret ptr %t72
}

define internal ptr @v__apply__df_andThenIO_110(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 327, label %tco.case.arm.327.11 i64 328, label %tco.case.arm.328.12 ]
tco.case.arm.327.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.328.12:
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

define internal ptr @v__df_andThenIO_113(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 329 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_113(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_113(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.17 i64 7, label %tco.case.arm.7.25 i64 8, label %tco.case.arm.8.48 i64 9, label %tco.case.arm.9.60 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_94(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_113(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_113(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 330 to ptr
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
  %t43 = inttoptr i64 330 to ptr
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
  %t55 = inttoptr i64 44 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df_andThenIO_113(ptr %t6, ptr %t51)
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
  %t71 = call ptr @v__apply__df_andThenIO_113(ptr %t6, ptr %t63)
  call void @__free_recursive(ptr %t62)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t72 = load ptr, ptr %t2
  ret ptr %t72
}

define internal ptr @v__apply__df_andThenIO_113(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 329, label %tco.case.arm.329.11 i64 330, label %tco.case.arm.330.12 ]
tco.case.arm.329.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.330.12:
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

define internal ptr @v__df_andThenIO_116(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 331 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_116(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_116(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.17 i64 7, label %tco.case.arm.7.25 i64 8, label %tco.case.arm.8.48 i64 9, label %tco.case.arm.9.60 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_95(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_116(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_116(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 332 to ptr
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
  %t43 = inttoptr i64 332 to ptr
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
  %t59 = call ptr @v__apply__df_andThenIO_116(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 74 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df_andThenIO_116(ptr %t6, ptr %t63)
  call void @__free_recursive(ptr %t62)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t72 = load ptr, ptr %t2
  ret ptr %t72
}

define internal ptr @v__apply__df_andThenIO_116(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 331, label %tco.case.arm.331.11 i64 332, label %tco.case.arm.332.12 ]
tco.case.arm.331.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.332.12:
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

define internal ptr @v__df_andThenIO_119(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 333 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_119(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_119(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.17 i64 7, label %tco.case.arm.7.25 i64 8, label %tco.case.arm.8.48 i64 9, label %tco.case.arm.9.60 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_96(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_119(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_119(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 334 to ptr
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
  %t43 = inttoptr i64 334 to ptr
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
  %t55 = inttoptr i64 46 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df_andThenIO_119(ptr %t6, ptr %t51)
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
  %t71 = call ptr @v__apply__df_andThenIO_119(ptr %t6, ptr %t63)
  call void @__free_recursive(ptr %t62)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t72 = load ptr, ptr %t2
  ret ptr %t72
}

define internal ptr @v__apply__df_andThenIO_119(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 333, label %tco.case.arm.333.11 i64 334, label %tco.case.arm.334.12 ]
tco.case.arm.333.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.334.12:
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

define internal ptr @v__df_andThenIO_122(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 335 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_122(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_122(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.17 i64 7, label %tco.case.arm.7.25 i64 8, label %tco.case.arm.8.48 i64 9, label %tco.case.arm.9.60 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_97(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_122(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_122(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 336 to ptr
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
  %t43 = inttoptr i64 336 to ptr
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
  %t55 = inttoptr i64 47 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df_andThenIO_122(ptr %t6, ptr %t51)
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
  %t71 = call ptr @v__apply__df_andThenIO_122(ptr %t6, ptr %t63)
  call void @__free_recursive(ptr %t62)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t72 = load ptr, ptr %t2
  ret ptr %t72
}

define internal ptr @v__apply__df_andThenIO_122(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 335, label %tco.case.arm.335.11 i64 336, label %tco.case.arm.336.12 ]
tco.case.arm.335.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.336.12:
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

define internal ptr @v__df_andThenIO_125(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 337 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_125(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_125(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.17 i64 7, label %tco.case.arm.7.25 i64 8, label %tco.case.arm.8.48 i64 9, label %tco.case.arm.9.60 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_98(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_125(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_125(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 338 to ptr
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
  %t43 = inttoptr i64 338 to ptr
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
  %t59 = call ptr @v__apply__df_andThenIO_125(ptr %t6, ptr %t51)
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
  %t71 = call ptr @v__apply__df_andThenIO_125(ptr %t6, ptr %t63)
  call void @__free_recursive(ptr %t62)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t72 = load ptr, ptr %t2
  ret ptr %t72
}

define internal ptr @v__apply__df_andThenIO_125(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 337, label %tco.case.arm.337.11 i64 338, label %tco.case.arm.338.12 ]
tco.case.arm.337.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.338.12:
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

define internal ptr @v__scc__apply1__df__lam_10_15__df__lam_10_24__df__lam_10_27__df__lam_10_30__df__lam_10_36__df__lam_10_42__df__lam_10_48__df__lam_11_16__df__lam_11_25__df__lam_11_28__df__lam_11_31__df__lam_11_37__df__lam_11_43__df__lam_11_49__df__lam_4_102__df__lam_4_105__df__lam_4_108__df__lam_4_111__df__lam_4_114__df__lam_4_117__df__lam_4_120__df__lam_4_123__df__lam_4_126__df__lam_4_18__df__lam_4_54__df__lam_4_57__df__lam_4_60__df__lam_4_63__df__lam_4_66__df__lam_4_69__df__lam_4_72__df__lam_4_75__df__lam_4_78__df__lam_4_81__df__lam_4_84__df__lam_4_87__df__lam_4_90__df__lam_4_93__df__lam_4_96__df__lam_4_99__df__lam_42_33__df__lam_43_34__df__lam_5_100__df__lam_5_103__df__lam_5_106__df__lam_5_109__df__lam_5_112__df__lam_5_115__df__lam_5_118__df__lam_5_121__df__lam_5_124__df__lam_5_127__df__lam_5_19__df__lam_5_55__df__lam_5_58__df__lam_5_61__df__lam_5_64__df__lam_5_67__df__lam_5_70__df__lam_5_73__df__lam_5_76__df__lam_5_79__df__lam_5_82__df__lam_5_85__df__lam_5_88__df__lam_5_91__df__lam_5_94__df__lam_5_97__df__lam_51_39__df__lam_52_40__df__lam_6_21__df__lam_60_45__df__lam_61_46__df__lam_69_51__df__lam_7_22__df__lam_70_52__lift_13__lift_14__lift_2__lift_27__lift_28__lift_3__lift_30__lift_31__lift_33__lift_34__lift_37__lift_38__lift_40__lift_41__lift_46__lift_47__lift_49__lift_50__lift_55__lift_56__lift_58__lift_59__lift_64__lift_65__lift_67__lift_68__lift_75__lift_76(ptr %v__args) {
  call void @__inc_ref(ptr %v__args)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 339 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__scc__apply1__df__lam_10_15__df__lam_10_24__df__lam_10_27__df__lam_10_30__df__lam_10_36__df__lam_10_42__df__lam_10_48__df__lam_11_16__df__lam_11_25__df__lam_11_28__df__lam_11_31__df__lam_11_37__df__lam_11_43__df__lam_11_49__df__lam_4_102__df__lam_4_105__df__lam_4_108__df__lam_4_111__df__lam_4_114__df__lam_4_117__df__lam_4_120__df__lam_4_123__df__lam_4_126__df__lam_4_18__df__lam_4_54__df__lam_4_57__df__lam_4_60__df__lam_4_63__df__lam_4_66__df__lam_4_69__df__lam_4_72__df__lam_4_75__df__lam_4_78__df__lam_4_81__df__lam_4_84__df__lam_4_87__df__lam_4_90__df__lam_4_93__df__lam_4_96__df__lam_4_99__df__lam_42_33__df__lam_43_34__df__lam_5_100__df__lam_5_103__df__lam_5_106__df__lam_5_109__df__lam_5_112__df__lam_5_115__df__lam_5_118__df__lam_5_121__df__lam_5_124__df__lam_5_127__df__lam_5_19__df__lam_5_55__df__lam_5_58__df__lam_5_61__df__lam_5_64__df__lam_5_67__df__lam_5_70__df__lam_5_73__df__lam_5_76__df__lam_5_79__df__lam_5_82__df__lam_5_85__df__lam_5_88__df__lam_5_91__df__lam_5_94__df__lam_5_97__df__lam_51_39__df__lam_52_40__df__lam_6_21__df__lam_60_45__df__lam_61_46__df__lam_69_51__df__lam_7_22__df__lam_70_52__lift_13__lift_14__lift_2__lift_27__lift_28__lift_3__lift_30__lift_31__lift_33__lift_34__lift_37__lift_38__lift_40__lift_41__lift_46__lift_47__lift_49__lift_50__lift_55__lift_56__lift_58__lift_59__lift_64__lift_65__lift_67__lift_68__lift_75__lift_76(ptr %v__args, ptr %t0)
  call void @__free_recursive(ptr %v__args)
  ret ptr %t3
}

define internal ptr @v__cps__scc__apply1__df__lam_10_15__df__lam_10_24__df__lam_10_27__df__lam_10_30__df__lam_10_36__df__lam_10_42__df__lam_10_48__df__lam_11_16__df__lam_11_25__df__lam_11_28__df__lam_11_31__df__lam_11_37__df__lam_11_43__df__lam_11_49__df__lam_4_102__df__lam_4_105__df__lam_4_108__df__lam_4_111__df__lam_4_114__df__lam_4_117__df__lam_4_120__df__lam_4_123__df__lam_4_126__df__lam_4_18__df__lam_4_54__df__lam_4_57__df__lam_4_60__df__lam_4_63__df__lam_4_66__df__lam_4_69__df__lam_4_72__df__lam_4_75__df__lam_4_78__df__lam_4_81__df__lam_4_84__df__lam_4_87__df__lam_4_90__df__lam_4_93__df__lam_4_96__df__lam_4_99__df__lam_42_33__df__lam_43_34__df__lam_5_100__df__lam_5_103__df__lam_5_106__df__lam_5_109__df__lam_5_112__df__lam_5_115__df__lam_5_118__df__lam_5_121__df__lam_5_124__df__lam_5_127__df__lam_5_19__df__lam_5_55__df__lam_5_58__df__lam_5_61__df__lam_5_64__df__lam_5_67__df__lam_5_70__df__lam_5_73__df__lam_5_76__df__lam_5_79__df__lam_5_82__df__lam_5_85__df__lam_5_88__df__lam_5_91__df__lam_5_94__df__lam_5_97__df__lam_51_39__df__lam_52_40__df__lam_6_21__df__lam_60_45__df__lam_61_46__df__lam_69_51__df__lam_7_22__df__lam_70_52__lift_13__lift_14__lift_2__lift_27__lift_28__lift_3__lift_30__lift_31__lift_33__lift_34__lift_37__lift_38__lift_40__lift_41__lift_46__lift_47__lift_49__lift_50__lift_55__lift_56__lift_58__lift_59__lift_64__lift_65__lift_67__lift_68__lift_75__lift_76(ptr %v__args, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 130, label %tco.case.arm.130.11 i64 131, label %tco.case.arm.131.1962 i64 132, label %tco.case.arm.132.1985 i64 133, label %tco.case.arm.133.2008 i64 134, label %tco.case.arm.134.2031 i64 135, label %tco.case.arm.135.2054 i64 136, label %tco.case.arm.136.2077 i64 137, label %tco.case.arm.137.2100 i64 138, label %tco.case.arm.138.2123 i64 139, label %tco.case.arm.139.2146 i64 140, label %tco.case.arm.140.2169 i64 141, label %tco.case.arm.141.2192 i64 142, label %tco.case.arm.142.2215 i64 143, label %tco.case.arm.143.2238 i64 144, label %tco.case.arm.144.2261 i64 145, label %tco.case.arm.145.2284 i64 146, label %tco.case.arm.146.2307 i64 147, label %tco.case.arm.147.2330 i64 148, label %tco.case.arm.148.2353 i64 149, label %tco.case.arm.149.2376 i64 150, label %tco.case.arm.150.2399 i64 151, label %tco.case.arm.151.2422 i64 152, label %tco.case.arm.152.2445 i64 153, label %tco.case.arm.153.2468 i64 154, label %tco.case.arm.154.2491 i64 155, label %tco.case.arm.155.2514 i64 156, label %tco.case.arm.156.2537 i64 157, label %tco.case.arm.157.2554 i64 158, label %tco.case.arm.158.2577 i64 159, label %tco.case.arm.159.2600 i64 160, label %tco.case.arm.160.2623 i64 161, label %tco.case.arm.161.2646 i64 162, label %tco.case.arm.162.2669 i64 163, label %tco.case.arm.163.2692 i64 164, label %tco.case.arm.164.2715 i64 165, label %tco.case.arm.165.2738 i64 166, label %tco.case.arm.166.2761 i64 167, label %tco.case.arm.167.2784 i64 168, label %tco.case.arm.168.2807 i64 169, label %tco.case.arm.169.2830 i64 170, label %tco.case.arm.170.2853 i64 171, label %tco.case.arm.171.2876 i64 172, label %tco.case.arm.172.2899 i64 173, label %tco.case.arm.173.2922 i64 174, label %tco.case.arm.174.2945 i64 175, label %tco.case.arm.175.2968 i64 176, label %tco.case.arm.176.2991 i64 177, label %tco.case.arm.177.3014 i64 178, label %tco.case.arm.178.3037 i64 179, label %tco.case.arm.179.3060 i64 180, label %tco.case.arm.180.3083 i64 181, label %tco.case.arm.181.3106 i64 182, label %tco.case.arm.182.3129 i64 183, label %tco.case.arm.183.3152 i64 184, label %tco.case.arm.184.3175 i64 185, label %tco.case.arm.185.3198 i64 186, label %tco.case.arm.186.3215 i64 187, label %tco.case.arm.187.3238 i64 188, label %tco.case.arm.188.3261 i64 189, label %tco.case.arm.189.3284 i64 190, label %tco.case.arm.190.3307 i64 191, label %tco.case.arm.191.3330 i64 192, label %tco.case.arm.192.3353 i64 193, label %tco.case.arm.193.3376 i64 194, label %tco.case.arm.194.3399 i64 195, label %tco.case.arm.195.3422 i64 196, label %tco.case.arm.196.3445 i64 197, label %tco.case.arm.197.3468 i64 198, label %tco.case.arm.198.3491 i64 199, label %tco.case.arm.199.3514 i64 200, label %tco.case.arm.200.3537 i64 201, label %tco.case.arm.201.3560 i64 202, label %tco.case.arm.202.3583 i64 203, label %tco.case.arm.203.3606 i64 204, label %tco.case.arm.204.3629 i64 205, label %tco.case.arm.205.3652 i64 206, label %tco.case.arm.206.3675 i64 207, label %tco.case.arm.207.3698 i64 208, label %tco.case.arm.208.3721 i64 209, label %tco.case.arm.209.3744 i64 210, label %tco.case.arm.210.3767 i64 211, label %tco.case.arm.211.3790 i64 212, label %tco.case.arm.212.3813 i64 213, label %tco.case.arm.213.3836 i64 214, label %tco.case.arm.214.3859 i64 215, label %tco.case.arm.215.3882 i64 216, label %tco.case.arm.216.3905 i64 217, label %tco.case.arm.217.3928 i64 218, label %tco.case.arm.218.3951 i64 221, label %tco.case.arm.221.3974 i64 222, label %tco.case.arm.222.3997 i64 225, label %tco.case.arm.225.4020 i64 226, label %tco.case.arm.226.4043 i64 229, label %tco.case.arm.229.4066 i64 230, label %tco.case.arm.230.4089 i64 231, label %tco.case.arm.231.4112 i64 232, label %tco.case.arm.232.4135 i64 233, label %tco.case.arm.233.4158 i64 234, label %tco.case.arm.234.4181 ]
tco.case.arm.130.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t5, i32 2
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  %t16 = getelementptr ptr, ptr %t13, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %tco.case.default.19 [ i64 26, label %tco.case.arm.26.20 i64 27, label %tco.case.arm.27.40 i64 28, label %tco.case.arm.28.60 i64 29, label %tco.case.arm.29.80 i64 30, label %tco.case.arm.30.100 i64 31, label %tco.case.arm.31.120 i64 32, label %tco.case.arm.32.140 i64 33, label %tco.case.arm.33.160 i64 34, label %tco.case.arm.34.180 i64 35, label %tco.case.arm.35.200 i64 36, label %tco.case.arm.36.220 i64 37, label %tco.case.arm.37.240 i64 38, label %tco.case.arm.38.260 i64 39, label %tco.case.arm.39.280 i64 40, label %tco.case.arm.40.300 i64 41, label %tco.case.arm.41.320 i64 42, label %tco.case.arm.42.340 i64 43, label %tco.case.arm.43.360 i64 44, label %tco.case.arm.44.380 i64 45, label %tco.case.arm.45.400 i64 46, label %tco.case.arm.46.420 i64 47, label %tco.case.arm.47.440 i64 48, label %tco.case.arm.48.460 i64 49, label %tco.case.arm.49.480 i64 50, label %tco.case.arm.50.500 i64 51, label %tco.case.arm.51.520 i64 52, label %tco.case.arm.52.531 i64 53, label %tco.case.arm.53.551 i64 54, label %tco.case.arm.54.571 i64 55, label %tco.case.arm.55.591 i64 56, label %tco.case.arm.56.611 i64 57, label %tco.case.arm.57.631 i64 58, label %tco.case.arm.58.651 i64 59, label %tco.case.arm.59.671 i64 60, label %tco.case.arm.60.691 i64 61, label %tco.case.arm.61.711 i64 62, label %tco.case.arm.62.731 i64 63, label %tco.case.arm.63.751 i64 64, label %tco.case.arm.64.771 i64 65, label %tco.case.arm.65.791 i64 66, label %tco.case.arm.66.811 i64 67, label %tco.case.arm.67.831 i64 68, label %tco.case.arm.68.851 i64 69, label %tco.case.arm.69.871 i64 70, label %tco.case.arm.70.891 i64 71, label %tco.case.arm.71.911 i64 72, label %tco.case.arm.72.931 i64 73, label %tco.case.arm.73.951 i64 74, label %tco.case.arm.74.971 i64 75, label %tco.case.arm.75.991 i64 76, label %tco.case.arm.76.1011 i64 77, label %tco.case.arm.77.1031 i64 78, label %tco.case.arm.78.1051 i64 79, label %tco.case.arm.79.1071 i64 80, label %tco.case.arm.80.1091 i64 81, label %tco.case.arm.81.1102 i64 82, label %tco.case.arm.82.1122 i64 83, label %tco.case.arm.83.1142 i64 84, label %tco.case.arm.84.1162 i64 85, label %tco.case.arm.85.1182 i64 86, label %tco.case.arm.86.1202 i64 87, label %tco.case.arm.87.1222 i64 88, label %tco.case.arm.88.1242 i64 89, label %tco.case.arm.89.1262 i64 90, label %tco.case.arm.90.1282 i64 91, label %tco.case.arm.91.1302 i64 92, label %tco.case.arm.92.1322 i64 93, label %tco.case.arm.93.1342 i64 94, label %tco.case.arm.94.1362 i64 95, label %tco.case.arm.95.1382 i64 96, label %tco.case.arm.96.1402 i64 97, label %tco.case.arm.97.1422 i64 98, label %tco.case.arm.98.1442 i64 99, label %tco.case.arm.99.1462 i64 100, label %tco.case.arm.100.1482 i64 101, label %tco.case.arm.101.1502 i64 102, label %tco.case.arm.102.1522 i64 103, label %tco.case.arm.103.1542 i64 104, label %tco.case.arm.104.1562 i64 105, label %tco.case.arm.105.1582 i64 106, label %tco.case.arm.106.1602 i64 107, label %tco.case.arm.107.1622 i64 108, label %tco.case.arm.108.1642 i64 109, label %tco.case.arm.109.1662 i64 110, label %tco.case.arm.110.1682 i64 111, label %tco.case.arm.111.1702 i64 112, label %tco.case.arm.112.1722 i64 113, label %tco.case.arm.113.1742 i64 116, label %tco.case.arm.116.1762 i64 117, label %tco.case.arm.117.1782 i64 120, label %tco.case.arm.120.1802 i64 121, label %tco.case.arm.121.1822 i64 124, label %tco.case.arm.124.1842 i64 125, label %tco.case.arm.125.1862 i64 126, label %tco.case.arm.126.1882 i64 127, label %tco.case.arm.127.1902 i64 128, label %tco.case.arm.128.1922 i64 129, label %tco.case.arm.129.1942 ]
tco.case.arm.26.20:
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
  %t32 = inttoptr i64 131 to ptr
  %t33 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t32, ptr %t33
  call void @__inc_ref(ptr %t22)
  %t31 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t22, ptr %t31
  br label %reuse.join.28
reuse.copy.27:
  %t34 = call ptr @__alloc(i64 24, i32 2)
  %t35 = inttoptr i64 131 to ptr
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
tco.case.arm.27.40:
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
  %t52 = inttoptr i64 132 to ptr
  %t53 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t52, ptr %t53
  call void @__inc_ref(ptr %t42)
  %t51 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t42, ptr %t51
  br label %reuse.join.48
reuse.copy.47:
  %t54 = call ptr @__alloc(i64 24, i32 2)
  %t55 = inttoptr i64 132 to ptr
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
tco.case.arm.28.60:
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
  %t72 = inttoptr i64 133 to ptr
  %t73 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t72, ptr %t73
  call void @__inc_ref(ptr %t62)
  %t71 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t62, ptr %t71
  br label %reuse.join.68
reuse.copy.67:
  %t74 = call ptr @__alloc(i64 24, i32 2)
  %t75 = inttoptr i64 133 to ptr
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
tco.case.arm.29.80:
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
  %t92 = inttoptr i64 134 to ptr
  %t93 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t92, ptr %t93
  call void @__inc_ref(ptr %t82)
  %t91 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t82, ptr %t91
  br label %reuse.join.88
reuse.copy.87:
  %t94 = call ptr @__alloc(i64 24, i32 2)
  %t95 = inttoptr i64 134 to ptr
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
tco.case.arm.30.100:
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
  %t112 = inttoptr i64 135 to ptr
  %t113 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t112, ptr %t113
  call void @__inc_ref(ptr %t102)
  %t111 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t102, ptr %t111
  br label %reuse.join.108
reuse.copy.107:
  %t114 = call ptr @__alloc(i64 24, i32 2)
  %t115 = inttoptr i64 135 to ptr
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
tco.case.arm.31.120:
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
  %t132 = inttoptr i64 136 to ptr
  %t133 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t132, ptr %t133
  call void @__inc_ref(ptr %t122)
  %t131 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t122, ptr %t131
  br label %reuse.join.128
reuse.copy.127:
  %t134 = call ptr @__alloc(i64 24, i32 2)
  %t135 = inttoptr i64 136 to ptr
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
tco.case.arm.32.140:
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
  %t152 = inttoptr i64 137 to ptr
  %t153 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t152, ptr %t153
  call void @__inc_ref(ptr %t142)
  %t151 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t142, ptr %t151
  br label %reuse.join.148
reuse.copy.147:
  %t154 = call ptr @__alloc(i64 24, i32 2)
  %t155 = inttoptr i64 137 to ptr
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
tco.case.arm.33.160:
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
  %t172 = inttoptr i64 138 to ptr
  %t173 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t172, ptr %t173
  call void @__inc_ref(ptr %t162)
  %t171 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t162, ptr %t171
  br label %reuse.join.168
reuse.copy.167:
  %t174 = call ptr @__alloc(i64 24, i32 2)
  %t175 = inttoptr i64 138 to ptr
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
tco.case.arm.34.180:
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
  %t192 = inttoptr i64 139 to ptr
  %t193 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t192, ptr %t193
  call void @__inc_ref(ptr %t182)
  %t191 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t182, ptr %t191
  br label %reuse.join.188
reuse.copy.187:
  %t194 = call ptr @__alloc(i64 24, i32 2)
  %t195 = inttoptr i64 139 to ptr
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
tco.case.arm.35.200:
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
  %t212 = inttoptr i64 140 to ptr
  %t213 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t212, ptr %t213
  call void @__inc_ref(ptr %t202)
  %t211 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t202, ptr %t211
  br label %reuse.join.208
reuse.copy.207:
  %t214 = call ptr @__alloc(i64 24, i32 2)
  %t215 = inttoptr i64 140 to ptr
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
tco.case.arm.36.220:
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
  %t232 = inttoptr i64 141 to ptr
  %t233 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t232, ptr %t233
  call void @__inc_ref(ptr %t222)
  %t231 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t222, ptr %t231
  br label %reuse.join.228
reuse.copy.227:
  %t234 = call ptr @__alloc(i64 24, i32 2)
  %t235 = inttoptr i64 141 to ptr
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
tco.case.arm.37.240:
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
  %t252 = inttoptr i64 142 to ptr
  %t253 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t252, ptr %t253
  call void @__inc_ref(ptr %t242)
  %t251 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t242, ptr %t251
  br label %reuse.join.248
reuse.copy.247:
  %t254 = call ptr @__alloc(i64 24, i32 2)
  %t255 = inttoptr i64 142 to ptr
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
tco.case.arm.38.260:
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
  %t272 = inttoptr i64 143 to ptr
  %t273 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t272, ptr %t273
  call void @__inc_ref(ptr %t262)
  %t271 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t262, ptr %t271
  br label %reuse.join.268
reuse.copy.267:
  %t274 = call ptr @__alloc(i64 24, i32 2)
  %t275 = inttoptr i64 143 to ptr
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
tco.case.arm.39.280:
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
  %t292 = inttoptr i64 144 to ptr
  %t293 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t292, ptr %t293
  call void @__inc_ref(ptr %t282)
  %t291 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t282, ptr %t291
  br label %reuse.join.288
reuse.copy.287:
  %t294 = call ptr @__alloc(i64 24, i32 2)
  %t295 = inttoptr i64 144 to ptr
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
tco.case.arm.40.300:
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
  %t312 = inttoptr i64 145 to ptr
  %t313 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t312, ptr %t313
  call void @__inc_ref(ptr %t302)
  %t311 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t302, ptr %t311
  br label %reuse.join.308
reuse.copy.307:
  %t314 = call ptr @__alloc(i64 24, i32 2)
  %t315 = inttoptr i64 145 to ptr
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
tco.case.arm.41.320:
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
  %t332 = inttoptr i64 146 to ptr
  %t333 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t332, ptr %t333
  call void @__inc_ref(ptr %t322)
  %t331 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t322, ptr %t331
  br label %reuse.join.328
reuse.copy.327:
  %t334 = call ptr @__alloc(i64 24, i32 2)
  %t335 = inttoptr i64 146 to ptr
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
tco.case.arm.42.340:
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
  %t352 = inttoptr i64 147 to ptr
  %t353 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t352, ptr %t353
  call void @__inc_ref(ptr %t342)
  %t351 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t342, ptr %t351
  br label %reuse.join.348
reuse.copy.347:
  %t354 = call ptr @__alloc(i64 24, i32 2)
  %t355 = inttoptr i64 147 to ptr
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
tco.case.arm.43.360:
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
  %t372 = inttoptr i64 148 to ptr
  %t373 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t372, ptr %t373
  call void @__inc_ref(ptr %t362)
  %t371 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t362, ptr %t371
  br label %reuse.join.368
reuse.copy.367:
  %t374 = call ptr @__alloc(i64 24, i32 2)
  %t375 = inttoptr i64 148 to ptr
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
tco.case.arm.44.380:
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
  %t392 = inttoptr i64 149 to ptr
  %t393 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t392, ptr %t393
  call void @__inc_ref(ptr %t382)
  %t391 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t382, ptr %t391
  br label %reuse.join.388
reuse.copy.387:
  %t394 = call ptr @__alloc(i64 24, i32 2)
  %t395 = inttoptr i64 149 to ptr
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
tco.case.arm.45.400:
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
  %t412 = inttoptr i64 150 to ptr
  %t413 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t412, ptr %t413
  call void @__inc_ref(ptr %t402)
  %t411 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t402, ptr %t411
  br label %reuse.join.408
reuse.copy.407:
  %t414 = call ptr @__alloc(i64 24, i32 2)
  %t415 = inttoptr i64 150 to ptr
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
tco.case.arm.46.420:
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
  %t432 = inttoptr i64 151 to ptr
  %t433 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t432, ptr %t433
  call void @__inc_ref(ptr %t422)
  %t431 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t422, ptr %t431
  br label %reuse.join.428
reuse.copy.427:
  %t434 = call ptr @__alloc(i64 24, i32 2)
  %t435 = inttoptr i64 151 to ptr
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
tco.case.arm.47.440:
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
  %t452 = inttoptr i64 152 to ptr
  %t453 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t452, ptr %t453
  call void @__inc_ref(ptr %t442)
  %t451 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t442, ptr %t451
  br label %reuse.join.448
reuse.copy.447:
  %t454 = call ptr @__alloc(i64 24, i32 2)
  %t455 = inttoptr i64 152 to ptr
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
tco.case.arm.48.460:
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
  %t472 = inttoptr i64 153 to ptr
  %t473 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t472, ptr %t473
  call void @__inc_ref(ptr %t462)
  %t471 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t462, ptr %t471
  br label %reuse.join.468
reuse.copy.467:
  %t474 = call ptr @__alloc(i64 24, i32 2)
  %t475 = inttoptr i64 153 to ptr
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
tco.case.arm.49.480:
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
  %t492 = inttoptr i64 154 to ptr
  %t493 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t492, ptr %t493
  call void @__inc_ref(ptr %t482)
  %t491 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t482, ptr %t491
  br label %reuse.join.488
reuse.copy.487:
  %t494 = call ptr @__alloc(i64 24, i32 2)
  %t495 = inttoptr i64 154 to ptr
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
tco.case.arm.50.500:
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
  %t512 = inttoptr i64 155 to ptr
  %t513 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t512, ptr %t513
  call void @__inc_ref(ptr %t502)
  %t511 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t502, ptr %t511
  br label %reuse.join.508
reuse.copy.507:
  %t514 = call ptr @__alloc(i64 24, i32 2)
  %t515 = inttoptr i64 155 to ptr
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
tco.case.arm.51.520:
  %t521 = getelementptr ptr, ptr %t13, i32 1
  %t522 = load ptr, ptr %t521
  call void @__inc_ref(ptr %t522)
  %t523 = getelementptr ptr, ptr %t13, i32 2
  %t524 = load ptr, ptr %t523
  call void @__inc_ref(ptr %t524)
  %t525 = call ptr @__alloc(i64 32, i32 3)
  %t526 = inttoptr i64 156 to ptr
  %t527 = getelementptr ptr, ptr %t525, i32 0
  store ptr %t526, ptr %t527
  call void @__inc_ref(ptr %t522)
  %t528 = getelementptr ptr, ptr %t525, i32 1
  store ptr %t522, ptr %t528
  call void @__inc_ref(ptr %t524)
  %t529 = getelementptr ptr, ptr %t525, i32 2
  store ptr %t524, ptr %t529
  call void @__inc_ref(ptr %t15)
  %t530 = getelementptr ptr, ptr %t525, i32 3
  store ptr %t15, ptr %t530
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t524)
  call void @__free_recursive(ptr %t522)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t525, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.52.531:
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
  %t543 = inttoptr i64 157 to ptr
  %t544 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t543, ptr %t544
  call void @__inc_ref(ptr %t533)
  %t542 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t533, ptr %t542
  br label %reuse.join.539
reuse.copy.538:
  %t545 = call ptr @__alloc(i64 24, i32 2)
  %t546 = inttoptr i64 157 to ptr
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
tco.case.arm.53.551:
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
  %t563 = inttoptr i64 158 to ptr
  %t564 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t563, ptr %t564
  call void @__inc_ref(ptr %t553)
  %t562 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t553, ptr %t562
  br label %reuse.join.559
reuse.copy.558:
  %t565 = call ptr @__alloc(i64 24, i32 2)
  %t566 = inttoptr i64 158 to ptr
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
tco.case.arm.54.571:
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
  %t583 = inttoptr i64 159 to ptr
  %t584 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t583, ptr %t584
  call void @__inc_ref(ptr %t573)
  %t582 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t573, ptr %t582
  br label %reuse.join.579
reuse.copy.578:
  %t585 = call ptr @__alloc(i64 24, i32 2)
  %t586 = inttoptr i64 159 to ptr
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
tco.case.arm.55.591:
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
  %t603 = inttoptr i64 160 to ptr
  %t604 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t603, ptr %t604
  call void @__inc_ref(ptr %t593)
  %t602 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t593, ptr %t602
  br label %reuse.join.599
reuse.copy.598:
  %t605 = call ptr @__alloc(i64 24, i32 2)
  %t606 = inttoptr i64 160 to ptr
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
tco.case.arm.56.611:
  %t612 = getelementptr ptr, ptr %t13, i32 1
  %t613 = load ptr, ptr %t612
  call void @__inc_ref(ptr %t613)
  %t614 = getelementptr i8, ptr %t5, i64 -8
  %t615 = load i32, ptr %t614
  %t616 = icmp eq i32 %t615, 1
  br i1 %t616, label %reuse.in_place.617, label %reuse.copy.618
reuse.in_place.617:
  %t620 = getelementptr ptr, ptr %t5, i32 1
  %t621 = load ptr, ptr %t620
  call void @__free_recursive(ptr %t621)
  %t623 = inttoptr i64 161 to ptr
  %t624 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t623, ptr %t624
  call void @__inc_ref(ptr %t613)
  %t622 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t613, ptr %t622
  br label %reuse.join.619
reuse.copy.618:
  %t625 = call ptr @__alloc(i64 24, i32 2)
  %t626 = inttoptr i64 161 to ptr
  %t627 = getelementptr ptr, ptr %t625, i32 0
  store ptr %t626, ptr %t627
  call void @__inc_ref(ptr %t613)
  %t628 = getelementptr ptr, ptr %t625, i32 1
  store ptr %t613, ptr %t628
  call void @__inc_ref(ptr %t15)
  %t629 = getelementptr ptr, ptr %t625, i32 2
  store ptr %t15, ptr %t629
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.619
reuse.join.619:
  %t630 = phi ptr [ %t5, %reuse.in_place.617 ], [ %t625, %reuse.copy.618 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t613)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t630, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.57.631:
  %t632 = getelementptr ptr, ptr %t13, i32 1
  %t633 = load ptr, ptr %t632
  call void @__inc_ref(ptr %t633)
  %t634 = getelementptr i8, ptr %t5, i64 -8
  %t635 = load i32, ptr %t634
  %t636 = icmp eq i32 %t635, 1
  br i1 %t636, label %reuse.in_place.637, label %reuse.copy.638
reuse.in_place.637:
  %t640 = getelementptr ptr, ptr %t5, i32 1
  %t641 = load ptr, ptr %t640
  call void @__free_recursive(ptr %t641)
  %t643 = inttoptr i64 162 to ptr
  %t644 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t643, ptr %t644
  call void @__inc_ref(ptr %t633)
  %t642 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t633, ptr %t642
  br label %reuse.join.639
reuse.copy.638:
  %t645 = call ptr @__alloc(i64 24, i32 2)
  %t646 = inttoptr i64 162 to ptr
  %t647 = getelementptr ptr, ptr %t645, i32 0
  store ptr %t646, ptr %t647
  call void @__inc_ref(ptr %t633)
  %t648 = getelementptr ptr, ptr %t645, i32 1
  store ptr %t633, ptr %t648
  call void @__inc_ref(ptr %t15)
  %t649 = getelementptr ptr, ptr %t645, i32 2
  store ptr %t15, ptr %t649
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.639
reuse.join.639:
  %t650 = phi ptr [ %t5, %reuse.in_place.637 ], [ %t645, %reuse.copy.638 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t633)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t650, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.58.651:
  %t652 = getelementptr ptr, ptr %t13, i32 1
  %t653 = load ptr, ptr %t652
  call void @__inc_ref(ptr %t653)
  %t654 = getelementptr i8, ptr %t5, i64 -8
  %t655 = load i32, ptr %t654
  %t656 = icmp eq i32 %t655, 1
  br i1 %t656, label %reuse.in_place.657, label %reuse.copy.658
reuse.in_place.657:
  %t660 = getelementptr ptr, ptr %t5, i32 1
  %t661 = load ptr, ptr %t660
  call void @__free_recursive(ptr %t661)
  %t663 = inttoptr i64 163 to ptr
  %t664 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t663, ptr %t664
  call void @__inc_ref(ptr %t653)
  %t662 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t653, ptr %t662
  br label %reuse.join.659
reuse.copy.658:
  %t665 = call ptr @__alloc(i64 24, i32 2)
  %t666 = inttoptr i64 163 to ptr
  %t667 = getelementptr ptr, ptr %t665, i32 0
  store ptr %t666, ptr %t667
  call void @__inc_ref(ptr %t653)
  %t668 = getelementptr ptr, ptr %t665, i32 1
  store ptr %t653, ptr %t668
  call void @__inc_ref(ptr %t15)
  %t669 = getelementptr ptr, ptr %t665, i32 2
  store ptr %t15, ptr %t669
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.659
reuse.join.659:
  %t670 = phi ptr [ %t5, %reuse.in_place.657 ], [ %t665, %reuse.copy.658 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t653)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t670, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.59.671:
  %t672 = getelementptr ptr, ptr %t13, i32 1
  %t673 = load ptr, ptr %t672
  call void @__inc_ref(ptr %t673)
  %t674 = getelementptr i8, ptr %t5, i64 -8
  %t675 = load i32, ptr %t674
  %t676 = icmp eq i32 %t675, 1
  br i1 %t676, label %reuse.in_place.677, label %reuse.copy.678
reuse.in_place.677:
  %t680 = getelementptr ptr, ptr %t5, i32 1
  %t681 = load ptr, ptr %t680
  call void @__free_recursive(ptr %t681)
  %t683 = inttoptr i64 164 to ptr
  %t684 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t683, ptr %t684
  call void @__inc_ref(ptr %t673)
  %t682 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t673, ptr %t682
  br label %reuse.join.679
reuse.copy.678:
  %t685 = call ptr @__alloc(i64 24, i32 2)
  %t686 = inttoptr i64 164 to ptr
  %t687 = getelementptr ptr, ptr %t685, i32 0
  store ptr %t686, ptr %t687
  call void @__inc_ref(ptr %t673)
  %t688 = getelementptr ptr, ptr %t685, i32 1
  store ptr %t673, ptr %t688
  call void @__inc_ref(ptr %t15)
  %t689 = getelementptr ptr, ptr %t685, i32 2
  store ptr %t15, ptr %t689
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.679
reuse.join.679:
  %t690 = phi ptr [ %t5, %reuse.in_place.677 ], [ %t685, %reuse.copy.678 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t673)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t690, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.60.691:
  %t692 = getelementptr ptr, ptr %t13, i32 1
  %t693 = load ptr, ptr %t692
  call void @__inc_ref(ptr %t693)
  %t694 = getelementptr i8, ptr %t5, i64 -8
  %t695 = load i32, ptr %t694
  %t696 = icmp eq i32 %t695, 1
  br i1 %t696, label %reuse.in_place.697, label %reuse.copy.698
reuse.in_place.697:
  %t700 = getelementptr ptr, ptr %t5, i32 1
  %t701 = load ptr, ptr %t700
  call void @__free_recursive(ptr %t701)
  %t703 = inttoptr i64 165 to ptr
  %t704 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t703, ptr %t704
  call void @__inc_ref(ptr %t693)
  %t702 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t693, ptr %t702
  br label %reuse.join.699
reuse.copy.698:
  %t705 = call ptr @__alloc(i64 24, i32 2)
  %t706 = inttoptr i64 165 to ptr
  %t707 = getelementptr ptr, ptr %t705, i32 0
  store ptr %t706, ptr %t707
  call void @__inc_ref(ptr %t693)
  %t708 = getelementptr ptr, ptr %t705, i32 1
  store ptr %t693, ptr %t708
  call void @__inc_ref(ptr %t15)
  %t709 = getelementptr ptr, ptr %t705, i32 2
  store ptr %t15, ptr %t709
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.699
reuse.join.699:
  %t710 = phi ptr [ %t5, %reuse.in_place.697 ], [ %t705, %reuse.copy.698 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t693)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t710, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.61.711:
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
  %t723 = inttoptr i64 166 to ptr
  %t724 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t723, ptr %t724
  call void @__inc_ref(ptr %t713)
  %t722 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t713, ptr %t722
  br label %reuse.join.719
reuse.copy.718:
  %t725 = call ptr @__alloc(i64 24, i32 2)
  %t726 = inttoptr i64 166 to ptr
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
tco.case.arm.62.731:
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
  %t743 = inttoptr i64 167 to ptr
  %t744 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t743, ptr %t744
  call void @__inc_ref(ptr %t733)
  %t742 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t733, ptr %t742
  br label %reuse.join.739
reuse.copy.738:
  %t745 = call ptr @__alloc(i64 24, i32 2)
  %t746 = inttoptr i64 167 to ptr
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
tco.case.arm.63.751:
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
  %t763 = inttoptr i64 168 to ptr
  %t764 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t763, ptr %t764
  call void @__inc_ref(ptr %t753)
  %t762 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t753, ptr %t762
  br label %reuse.join.759
reuse.copy.758:
  %t765 = call ptr @__alloc(i64 24, i32 2)
  %t766 = inttoptr i64 168 to ptr
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
tco.case.arm.64.771:
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
  %t783 = inttoptr i64 169 to ptr
  %t784 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t783, ptr %t784
  call void @__inc_ref(ptr %t773)
  %t782 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t773, ptr %t782
  br label %reuse.join.779
reuse.copy.778:
  %t785 = call ptr @__alloc(i64 24, i32 2)
  %t786 = inttoptr i64 169 to ptr
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
tco.case.arm.65.791:
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
  %t803 = inttoptr i64 170 to ptr
  %t804 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t803, ptr %t804
  call void @__inc_ref(ptr %t793)
  %t802 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t793, ptr %t802
  br label %reuse.join.799
reuse.copy.798:
  %t805 = call ptr @__alloc(i64 24, i32 2)
  %t806 = inttoptr i64 170 to ptr
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
tco.case.arm.66.811:
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
  %t823 = inttoptr i64 171 to ptr
  %t824 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t823, ptr %t824
  call void @__inc_ref(ptr %t813)
  %t822 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t813, ptr %t822
  br label %reuse.join.819
reuse.copy.818:
  %t825 = call ptr @__alloc(i64 24, i32 2)
  %t826 = inttoptr i64 171 to ptr
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
tco.case.arm.67.831:
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
  %t843 = inttoptr i64 172 to ptr
  %t844 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t843, ptr %t844
  call void @__inc_ref(ptr %t833)
  %t842 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t833, ptr %t842
  br label %reuse.join.839
reuse.copy.838:
  %t845 = call ptr @__alloc(i64 24, i32 2)
  %t846 = inttoptr i64 172 to ptr
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
tco.case.arm.68.851:
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
  %t863 = inttoptr i64 173 to ptr
  %t864 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t863, ptr %t864
  call void @__inc_ref(ptr %t853)
  %t862 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t853, ptr %t862
  br label %reuse.join.859
reuse.copy.858:
  %t865 = call ptr @__alloc(i64 24, i32 2)
  %t866 = inttoptr i64 173 to ptr
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
tco.case.arm.69.871:
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
  %t883 = inttoptr i64 174 to ptr
  %t884 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t883, ptr %t884
  call void @__inc_ref(ptr %t873)
  %t882 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t873, ptr %t882
  br label %reuse.join.879
reuse.copy.878:
  %t885 = call ptr @__alloc(i64 24, i32 2)
  %t886 = inttoptr i64 174 to ptr
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
tco.case.arm.70.891:
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
  %t903 = inttoptr i64 175 to ptr
  %t904 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t903, ptr %t904
  call void @__inc_ref(ptr %t893)
  %t902 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t893, ptr %t902
  br label %reuse.join.899
reuse.copy.898:
  %t905 = call ptr @__alloc(i64 24, i32 2)
  %t906 = inttoptr i64 175 to ptr
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
tco.case.arm.71.911:
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
  %t923 = inttoptr i64 176 to ptr
  %t924 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t923, ptr %t924
  call void @__inc_ref(ptr %t913)
  %t922 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t913, ptr %t922
  br label %reuse.join.919
reuse.copy.918:
  %t925 = call ptr @__alloc(i64 24, i32 2)
  %t926 = inttoptr i64 176 to ptr
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
tco.case.arm.72.931:
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
  %t943 = inttoptr i64 177 to ptr
  %t944 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t943, ptr %t944
  call void @__inc_ref(ptr %t933)
  %t942 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t933, ptr %t942
  br label %reuse.join.939
reuse.copy.938:
  %t945 = call ptr @__alloc(i64 24, i32 2)
  %t946 = inttoptr i64 177 to ptr
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
tco.case.arm.73.951:
  %t952 = getelementptr ptr, ptr %t13, i32 1
  %t953 = load ptr, ptr %t952
  call void @__inc_ref(ptr %t953)
  %t954 = getelementptr i8, ptr %t5, i64 -8
  %t955 = load i32, ptr %t954
  %t956 = icmp eq i32 %t955, 1
  br i1 %t956, label %reuse.in_place.957, label %reuse.copy.958
reuse.in_place.957:
  %t960 = getelementptr ptr, ptr %t5, i32 1
  %t961 = load ptr, ptr %t960
  call void @__free_recursive(ptr %t961)
  %t963 = inttoptr i64 178 to ptr
  %t964 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t963, ptr %t964
  call void @__inc_ref(ptr %t953)
  %t962 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t953, ptr %t962
  br label %reuse.join.959
reuse.copy.958:
  %t965 = call ptr @__alloc(i64 24, i32 2)
  %t966 = inttoptr i64 178 to ptr
  %t967 = getelementptr ptr, ptr %t965, i32 0
  store ptr %t966, ptr %t967
  call void @__inc_ref(ptr %t953)
  %t968 = getelementptr ptr, ptr %t965, i32 1
  store ptr %t953, ptr %t968
  call void @__inc_ref(ptr %t15)
  %t969 = getelementptr ptr, ptr %t965, i32 2
  store ptr %t15, ptr %t969
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.959
reuse.join.959:
  %t970 = phi ptr [ %t5, %reuse.in_place.957 ], [ %t965, %reuse.copy.958 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t953)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t970, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.74.971:
  %t972 = getelementptr ptr, ptr %t13, i32 1
  %t973 = load ptr, ptr %t972
  call void @__inc_ref(ptr %t973)
  %t974 = getelementptr i8, ptr %t5, i64 -8
  %t975 = load i32, ptr %t974
  %t976 = icmp eq i32 %t975, 1
  br i1 %t976, label %reuse.in_place.977, label %reuse.copy.978
reuse.in_place.977:
  %t980 = getelementptr ptr, ptr %t5, i32 1
  %t981 = load ptr, ptr %t980
  call void @__free_recursive(ptr %t981)
  %t983 = inttoptr i64 179 to ptr
  %t984 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t983, ptr %t984
  call void @__inc_ref(ptr %t973)
  %t982 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t973, ptr %t982
  br label %reuse.join.979
reuse.copy.978:
  %t985 = call ptr @__alloc(i64 24, i32 2)
  %t986 = inttoptr i64 179 to ptr
  %t987 = getelementptr ptr, ptr %t985, i32 0
  store ptr %t986, ptr %t987
  call void @__inc_ref(ptr %t973)
  %t988 = getelementptr ptr, ptr %t985, i32 1
  store ptr %t973, ptr %t988
  call void @__inc_ref(ptr %t15)
  %t989 = getelementptr ptr, ptr %t985, i32 2
  store ptr %t15, ptr %t989
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.979
reuse.join.979:
  %t990 = phi ptr [ %t5, %reuse.in_place.977 ], [ %t985, %reuse.copy.978 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t973)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t990, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.75.991:
  %t992 = getelementptr ptr, ptr %t13, i32 1
  %t993 = load ptr, ptr %t992
  call void @__inc_ref(ptr %t993)
  %t994 = getelementptr i8, ptr %t5, i64 -8
  %t995 = load i32, ptr %t994
  %t996 = icmp eq i32 %t995, 1
  br i1 %t996, label %reuse.in_place.997, label %reuse.copy.998
reuse.in_place.997:
  %t1000 = getelementptr ptr, ptr %t5, i32 1
  %t1001 = load ptr, ptr %t1000
  call void @__free_recursive(ptr %t1001)
  %t1003 = inttoptr i64 180 to ptr
  %t1004 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1003, ptr %t1004
  call void @__inc_ref(ptr %t993)
  %t1002 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t993, ptr %t1002
  br label %reuse.join.999
reuse.copy.998:
  %t1005 = call ptr @__alloc(i64 24, i32 2)
  %t1006 = inttoptr i64 180 to ptr
  %t1007 = getelementptr ptr, ptr %t1005, i32 0
  store ptr %t1006, ptr %t1007
  call void @__inc_ref(ptr %t993)
  %t1008 = getelementptr ptr, ptr %t1005, i32 1
  store ptr %t993, ptr %t1008
  call void @__inc_ref(ptr %t15)
  %t1009 = getelementptr ptr, ptr %t1005, i32 2
  store ptr %t15, ptr %t1009
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.999
reuse.join.999:
  %t1010 = phi ptr [ %t5, %reuse.in_place.997 ], [ %t1005, %reuse.copy.998 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t993)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1010, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.76.1011:
  %t1012 = getelementptr ptr, ptr %t13, i32 1
  %t1013 = load ptr, ptr %t1012
  call void @__inc_ref(ptr %t1013)
  %t1014 = getelementptr i8, ptr %t5, i64 -8
  %t1015 = load i32, ptr %t1014
  %t1016 = icmp eq i32 %t1015, 1
  br i1 %t1016, label %reuse.in_place.1017, label %reuse.copy.1018
reuse.in_place.1017:
  %t1020 = getelementptr ptr, ptr %t5, i32 1
  %t1021 = load ptr, ptr %t1020
  call void @__free_recursive(ptr %t1021)
  %t1023 = inttoptr i64 181 to ptr
  %t1024 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1023, ptr %t1024
  call void @__inc_ref(ptr %t1013)
  %t1022 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1013, ptr %t1022
  br label %reuse.join.1019
reuse.copy.1018:
  %t1025 = call ptr @__alloc(i64 24, i32 2)
  %t1026 = inttoptr i64 181 to ptr
  %t1027 = getelementptr ptr, ptr %t1025, i32 0
  store ptr %t1026, ptr %t1027
  call void @__inc_ref(ptr %t1013)
  %t1028 = getelementptr ptr, ptr %t1025, i32 1
  store ptr %t1013, ptr %t1028
  call void @__inc_ref(ptr %t15)
  %t1029 = getelementptr ptr, ptr %t1025, i32 2
  store ptr %t15, ptr %t1029
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1019
reuse.join.1019:
  %t1030 = phi ptr [ %t5, %reuse.in_place.1017 ], [ %t1025, %reuse.copy.1018 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1013)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1030, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.77.1031:
  %t1032 = getelementptr ptr, ptr %t13, i32 1
  %t1033 = load ptr, ptr %t1032
  call void @__inc_ref(ptr %t1033)
  %t1034 = getelementptr i8, ptr %t5, i64 -8
  %t1035 = load i32, ptr %t1034
  %t1036 = icmp eq i32 %t1035, 1
  br i1 %t1036, label %reuse.in_place.1037, label %reuse.copy.1038
reuse.in_place.1037:
  %t1040 = getelementptr ptr, ptr %t5, i32 1
  %t1041 = load ptr, ptr %t1040
  call void @__free_recursive(ptr %t1041)
  %t1043 = inttoptr i64 182 to ptr
  %t1044 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1043, ptr %t1044
  call void @__inc_ref(ptr %t1033)
  %t1042 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1033, ptr %t1042
  br label %reuse.join.1039
reuse.copy.1038:
  %t1045 = call ptr @__alloc(i64 24, i32 2)
  %t1046 = inttoptr i64 182 to ptr
  %t1047 = getelementptr ptr, ptr %t1045, i32 0
  store ptr %t1046, ptr %t1047
  call void @__inc_ref(ptr %t1033)
  %t1048 = getelementptr ptr, ptr %t1045, i32 1
  store ptr %t1033, ptr %t1048
  call void @__inc_ref(ptr %t15)
  %t1049 = getelementptr ptr, ptr %t1045, i32 2
  store ptr %t15, ptr %t1049
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1039
reuse.join.1039:
  %t1050 = phi ptr [ %t5, %reuse.in_place.1037 ], [ %t1045, %reuse.copy.1038 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1033)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1050, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.78.1051:
  %t1052 = getelementptr ptr, ptr %t13, i32 1
  %t1053 = load ptr, ptr %t1052
  call void @__inc_ref(ptr %t1053)
  %t1054 = getelementptr i8, ptr %t5, i64 -8
  %t1055 = load i32, ptr %t1054
  %t1056 = icmp eq i32 %t1055, 1
  br i1 %t1056, label %reuse.in_place.1057, label %reuse.copy.1058
reuse.in_place.1057:
  %t1060 = getelementptr ptr, ptr %t5, i32 1
  %t1061 = load ptr, ptr %t1060
  call void @__free_recursive(ptr %t1061)
  %t1063 = inttoptr i64 183 to ptr
  %t1064 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1063, ptr %t1064
  call void @__inc_ref(ptr %t1053)
  %t1062 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1053, ptr %t1062
  br label %reuse.join.1059
reuse.copy.1058:
  %t1065 = call ptr @__alloc(i64 24, i32 2)
  %t1066 = inttoptr i64 183 to ptr
  %t1067 = getelementptr ptr, ptr %t1065, i32 0
  store ptr %t1066, ptr %t1067
  call void @__inc_ref(ptr %t1053)
  %t1068 = getelementptr ptr, ptr %t1065, i32 1
  store ptr %t1053, ptr %t1068
  call void @__inc_ref(ptr %t15)
  %t1069 = getelementptr ptr, ptr %t1065, i32 2
  store ptr %t15, ptr %t1069
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1059
reuse.join.1059:
  %t1070 = phi ptr [ %t5, %reuse.in_place.1057 ], [ %t1065, %reuse.copy.1058 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1053)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1070, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.79.1071:
  %t1072 = getelementptr ptr, ptr %t13, i32 1
  %t1073 = load ptr, ptr %t1072
  call void @__inc_ref(ptr %t1073)
  %t1074 = getelementptr i8, ptr %t5, i64 -8
  %t1075 = load i32, ptr %t1074
  %t1076 = icmp eq i32 %t1075, 1
  br i1 %t1076, label %reuse.in_place.1077, label %reuse.copy.1078
reuse.in_place.1077:
  %t1080 = getelementptr ptr, ptr %t5, i32 1
  %t1081 = load ptr, ptr %t1080
  call void @__free_recursive(ptr %t1081)
  %t1083 = inttoptr i64 184 to ptr
  %t1084 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1083, ptr %t1084
  call void @__inc_ref(ptr %t1073)
  %t1082 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1073, ptr %t1082
  br label %reuse.join.1079
reuse.copy.1078:
  %t1085 = call ptr @__alloc(i64 24, i32 2)
  %t1086 = inttoptr i64 184 to ptr
  %t1087 = getelementptr ptr, ptr %t1085, i32 0
  store ptr %t1086, ptr %t1087
  call void @__inc_ref(ptr %t1073)
  %t1088 = getelementptr ptr, ptr %t1085, i32 1
  store ptr %t1073, ptr %t1088
  call void @__inc_ref(ptr %t15)
  %t1089 = getelementptr ptr, ptr %t1085, i32 2
  store ptr %t15, ptr %t1089
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1079
reuse.join.1079:
  %t1090 = phi ptr [ %t5, %reuse.in_place.1077 ], [ %t1085, %reuse.copy.1078 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1073)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1090, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.80.1091:
  %t1092 = getelementptr ptr, ptr %t13, i32 1
  %t1093 = load ptr, ptr %t1092
  call void @__inc_ref(ptr %t1093)
  %t1094 = getelementptr ptr, ptr %t13, i32 2
  %t1095 = load ptr, ptr %t1094
  call void @__inc_ref(ptr %t1095)
  %t1096 = call ptr @__alloc(i64 32, i32 3)
  %t1097 = inttoptr i64 185 to ptr
  %t1098 = getelementptr ptr, ptr %t1096, i32 0
  store ptr %t1097, ptr %t1098
  call void @__inc_ref(ptr %t1093)
  %t1099 = getelementptr ptr, ptr %t1096, i32 1
  store ptr %t1093, ptr %t1099
  call void @__inc_ref(ptr %t1095)
  %t1100 = getelementptr ptr, ptr %t1096, i32 2
  store ptr %t1095, ptr %t1100
  call void @__inc_ref(ptr %t15)
  %t1101 = getelementptr ptr, ptr %t1096, i32 3
  store ptr %t15, ptr %t1101
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t1095)
  call void @__free_recursive(ptr %t1093)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1096, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.81.1102:
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
  %t1114 = inttoptr i64 186 to ptr
  %t1115 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1114, ptr %t1115
  call void @__inc_ref(ptr %t1104)
  %t1113 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1104, ptr %t1113
  br label %reuse.join.1110
reuse.copy.1109:
  %t1116 = call ptr @__alloc(i64 24, i32 2)
  %t1117 = inttoptr i64 186 to ptr
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
tco.case.arm.82.1122:
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
  %t1134 = inttoptr i64 187 to ptr
  %t1135 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1134, ptr %t1135
  call void @__inc_ref(ptr %t1124)
  %t1133 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1124, ptr %t1133
  br label %reuse.join.1130
reuse.copy.1129:
  %t1136 = call ptr @__alloc(i64 24, i32 2)
  %t1137 = inttoptr i64 187 to ptr
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
tco.case.arm.83.1142:
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
  %t1154 = inttoptr i64 188 to ptr
  %t1155 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1154, ptr %t1155
  call void @__inc_ref(ptr %t1144)
  %t1153 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1144, ptr %t1153
  br label %reuse.join.1150
reuse.copy.1149:
  %t1156 = call ptr @__alloc(i64 24, i32 2)
  %t1157 = inttoptr i64 188 to ptr
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
tco.case.arm.84.1162:
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
  %t1174 = inttoptr i64 189 to ptr
  %t1175 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1174, ptr %t1175
  call void @__inc_ref(ptr %t1164)
  %t1173 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1164, ptr %t1173
  br label %reuse.join.1170
reuse.copy.1169:
  %t1176 = call ptr @__alloc(i64 24, i32 2)
  %t1177 = inttoptr i64 189 to ptr
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
tco.case.arm.85.1182:
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
  %t1194 = inttoptr i64 190 to ptr
  %t1195 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1194, ptr %t1195
  call void @__inc_ref(ptr %t1184)
  %t1193 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1184, ptr %t1193
  br label %reuse.join.1190
reuse.copy.1189:
  %t1196 = call ptr @__alloc(i64 24, i32 2)
  %t1197 = inttoptr i64 190 to ptr
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
tco.case.arm.86.1202:
  %t1203 = getelementptr ptr, ptr %t13, i32 1
  %t1204 = load ptr, ptr %t1203
  call void @__inc_ref(ptr %t1204)
  %t1205 = getelementptr i8, ptr %t5, i64 -8
  %t1206 = load i32, ptr %t1205
  %t1207 = icmp eq i32 %t1206, 1
  br i1 %t1207, label %reuse.in_place.1208, label %reuse.copy.1209
reuse.in_place.1208:
  %t1211 = getelementptr ptr, ptr %t5, i32 1
  %t1212 = load ptr, ptr %t1211
  call void @__free_recursive(ptr %t1212)
  %t1214 = inttoptr i64 191 to ptr
  %t1215 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1214, ptr %t1215
  call void @__inc_ref(ptr %t1204)
  %t1213 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1204, ptr %t1213
  br label %reuse.join.1210
reuse.copy.1209:
  %t1216 = call ptr @__alloc(i64 24, i32 2)
  %t1217 = inttoptr i64 191 to ptr
  %t1218 = getelementptr ptr, ptr %t1216, i32 0
  store ptr %t1217, ptr %t1218
  call void @__inc_ref(ptr %t1204)
  %t1219 = getelementptr ptr, ptr %t1216, i32 1
  store ptr %t1204, ptr %t1219
  call void @__inc_ref(ptr %t15)
  %t1220 = getelementptr ptr, ptr %t1216, i32 2
  store ptr %t15, ptr %t1220
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1210
reuse.join.1210:
  %t1221 = phi ptr [ %t5, %reuse.in_place.1208 ], [ %t1216, %reuse.copy.1209 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1204)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1221, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.87.1222:
  %t1223 = getelementptr ptr, ptr %t13, i32 1
  %t1224 = load ptr, ptr %t1223
  call void @__inc_ref(ptr %t1224)
  %t1225 = getelementptr i8, ptr %t5, i64 -8
  %t1226 = load i32, ptr %t1225
  %t1227 = icmp eq i32 %t1226, 1
  br i1 %t1227, label %reuse.in_place.1228, label %reuse.copy.1229
reuse.in_place.1228:
  %t1231 = getelementptr ptr, ptr %t5, i32 1
  %t1232 = load ptr, ptr %t1231
  call void @__free_recursive(ptr %t1232)
  %t1234 = inttoptr i64 192 to ptr
  %t1235 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1234, ptr %t1235
  call void @__inc_ref(ptr %t1224)
  %t1233 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1224, ptr %t1233
  br label %reuse.join.1230
reuse.copy.1229:
  %t1236 = call ptr @__alloc(i64 24, i32 2)
  %t1237 = inttoptr i64 192 to ptr
  %t1238 = getelementptr ptr, ptr %t1236, i32 0
  store ptr %t1237, ptr %t1238
  call void @__inc_ref(ptr %t1224)
  %t1239 = getelementptr ptr, ptr %t1236, i32 1
  store ptr %t1224, ptr %t1239
  call void @__inc_ref(ptr %t15)
  %t1240 = getelementptr ptr, ptr %t1236, i32 2
  store ptr %t15, ptr %t1240
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1230
reuse.join.1230:
  %t1241 = phi ptr [ %t5, %reuse.in_place.1228 ], [ %t1236, %reuse.copy.1229 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1224)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1241, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.88.1242:
  %t1243 = getelementptr ptr, ptr %t13, i32 1
  %t1244 = load ptr, ptr %t1243
  call void @__inc_ref(ptr %t1244)
  %t1245 = getelementptr i8, ptr %t5, i64 -8
  %t1246 = load i32, ptr %t1245
  %t1247 = icmp eq i32 %t1246, 1
  br i1 %t1247, label %reuse.in_place.1248, label %reuse.copy.1249
reuse.in_place.1248:
  %t1251 = getelementptr ptr, ptr %t5, i32 1
  %t1252 = load ptr, ptr %t1251
  call void @__free_recursive(ptr %t1252)
  %t1254 = inttoptr i64 193 to ptr
  %t1255 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1254, ptr %t1255
  call void @__inc_ref(ptr %t1244)
  %t1253 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1244, ptr %t1253
  br label %reuse.join.1250
reuse.copy.1249:
  %t1256 = call ptr @__alloc(i64 24, i32 2)
  %t1257 = inttoptr i64 193 to ptr
  %t1258 = getelementptr ptr, ptr %t1256, i32 0
  store ptr %t1257, ptr %t1258
  call void @__inc_ref(ptr %t1244)
  %t1259 = getelementptr ptr, ptr %t1256, i32 1
  store ptr %t1244, ptr %t1259
  call void @__inc_ref(ptr %t15)
  %t1260 = getelementptr ptr, ptr %t1256, i32 2
  store ptr %t15, ptr %t1260
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1250
reuse.join.1250:
  %t1261 = phi ptr [ %t5, %reuse.in_place.1248 ], [ %t1256, %reuse.copy.1249 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1244)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1261, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.89.1262:
  %t1263 = getelementptr ptr, ptr %t13, i32 1
  %t1264 = load ptr, ptr %t1263
  call void @__inc_ref(ptr %t1264)
  %t1265 = getelementptr i8, ptr %t5, i64 -8
  %t1266 = load i32, ptr %t1265
  %t1267 = icmp eq i32 %t1266, 1
  br i1 %t1267, label %reuse.in_place.1268, label %reuse.copy.1269
reuse.in_place.1268:
  %t1271 = getelementptr ptr, ptr %t5, i32 1
  %t1272 = load ptr, ptr %t1271
  call void @__free_recursive(ptr %t1272)
  %t1274 = inttoptr i64 194 to ptr
  %t1275 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1274, ptr %t1275
  call void @__inc_ref(ptr %t1264)
  %t1273 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1264, ptr %t1273
  br label %reuse.join.1270
reuse.copy.1269:
  %t1276 = call ptr @__alloc(i64 24, i32 2)
  %t1277 = inttoptr i64 194 to ptr
  %t1278 = getelementptr ptr, ptr %t1276, i32 0
  store ptr %t1277, ptr %t1278
  call void @__inc_ref(ptr %t1264)
  %t1279 = getelementptr ptr, ptr %t1276, i32 1
  store ptr %t1264, ptr %t1279
  call void @__inc_ref(ptr %t15)
  %t1280 = getelementptr ptr, ptr %t1276, i32 2
  store ptr %t15, ptr %t1280
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1270
reuse.join.1270:
  %t1281 = phi ptr [ %t5, %reuse.in_place.1268 ], [ %t1276, %reuse.copy.1269 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1264)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1281, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.90.1282:
  %t1283 = getelementptr ptr, ptr %t13, i32 1
  %t1284 = load ptr, ptr %t1283
  call void @__inc_ref(ptr %t1284)
  %t1285 = getelementptr i8, ptr %t5, i64 -8
  %t1286 = load i32, ptr %t1285
  %t1287 = icmp eq i32 %t1286, 1
  br i1 %t1287, label %reuse.in_place.1288, label %reuse.copy.1289
reuse.in_place.1288:
  %t1291 = getelementptr ptr, ptr %t5, i32 1
  %t1292 = load ptr, ptr %t1291
  call void @__free_recursive(ptr %t1292)
  %t1294 = inttoptr i64 195 to ptr
  %t1295 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1294, ptr %t1295
  call void @__inc_ref(ptr %t1284)
  %t1293 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1284, ptr %t1293
  br label %reuse.join.1290
reuse.copy.1289:
  %t1296 = call ptr @__alloc(i64 24, i32 2)
  %t1297 = inttoptr i64 195 to ptr
  %t1298 = getelementptr ptr, ptr %t1296, i32 0
  store ptr %t1297, ptr %t1298
  call void @__inc_ref(ptr %t1284)
  %t1299 = getelementptr ptr, ptr %t1296, i32 1
  store ptr %t1284, ptr %t1299
  call void @__inc_ref(ptr %t15)
  %t1300 = getelementptr ptr, ptr %t1296, i32 2
  store ptr %t15, ptr %t1300
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1290
reuse.join.1290:
  %t1301 = phi ptr [ %t5, %reuse.in_place.1288 ], [ %t1296, %reuse.copy.1289 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1284)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1301, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.91.1302:
  %t1303 = getelementptr ptr, ptr %t13, i32 1
  %t1304 = load ptr, ptr %t1303
  call void @__inc_ref(ptr %t1304)
  %t1305 = getelementptr i8, ptr %t5, i64 -8
  %t1306 = load i32, ptr %t1305
  %t1307 = icmp eq i32 %t1306, 1
  br i1 %t1307, label %reuse.in_place.1308, label %reuse.copy.1309
reuse.in_place.1308:
  %t1311 = getelementptr ptr, ptr %t5, i32 1
  %t1312 = load ptr, ptr %t1311
  call void @__free_recursive(ptr %t1312)
  %t1314 = inttoptr i64 196 to ptr
  %t1315 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1314, ptr %t1315
  call void @__inc_ref(ptr %t1304)
  %t1313 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1304, ptr %t1313
  br label %reuse.join.1310
reuse.copy.1309:
  %t1316 = call ptr @__alloc(i64 24, i32 2)
  %t1317 = inttoptr i64 196 to ptr
  %t1318 = getelementptr ptr, ptr %t1316, i32 0
  store ptr %t1317, ptr %t1318
  call void @__inc_ref(ptr %t1304)
  %t1319 = getelementptr ptr, ptr %t1316, i32 1
  store ptr %t1304, ptr %t1319
  call void @__inc_ref(ptr %t15)
  %t1320 = getelementptr ptr, ptr %t1316, i32 2
  store ptr %t15, ptr %t1320
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1310
reuse.join.1310:
  %t1321 = phi ptr [ %t5, %reuse.in_place.1308 ], [ %t1316, %reuse.copy.1309 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1304)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1321, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.92.1322:
  %t1323 = getelementptr ptr, ptr %t13, i32 1
  %t1324 = load ptr, ptr %t1323
  call void @__inc_ref(ptr %t1324)
  %t1325 = getelementptr i8, ptr %t5, i64 -8
  %t1326 = load i32, ptr %t1325
  %t1327 = icmp eq i32 %t1326, 1
  br i1 %t1327, label %reuse.in_place.1328, label %reuse.copy.1329
reuse.in_place.1328:
  %t1331 = getelementptr ptr, ptr %t5, i32 1
  %t1332 = load ptr, ptr %t1331
  call void @__free_recursive(ptr %t1332)
  %t1334 = inttoptr i64 197 to ptr
  %t1335 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1334, ptr %t1335
  call void @__inc_ref(ptr %t1324)
  %t1333 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1324, ptr %t1333
  br label %reuse.join.1330
reuse.copy.1329:
  %t1336 = call ptr @__alloc(i64 24, i32 2)
  %t1337 = inttoptr i64 197 to ptr
  %t1338 = getelementptr ptr, ptr %t1336, i32 0
  store ptr %t1337, ptr %t1338
  call void @__inc_ref(ptr %t1324)
  %t1339 = getelementptr ptr, ptr %t1336, i32 1
  store ptr %t1324, ptr %t1339
  call void @__inc_ref(ptr %t15)
  %t1340 = getelementptr ptr, ptr %t1336, i32 2
  store ptr %t15, ptr %t1340
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1330
reuse.join.1330:
  %t1341 = phi ptr [ %t5, %reuse.in_place.1328 ], [ %t1336, %reuse.copy.1329 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1324)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1341, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.93.1342:
  %t1343 = getelementptr ptr, ptr %t13, i32 1
  %t1344 = load ptr, ptr %t1343
  call void @__inc_ref(ptr %t1344)
  %t1345 = getelementptr i8, ptr %t5, i64 -8
  %t1346 = load i32, ptr %t1345
  %t1347 = icmp eq i32 %t1346, 1
  br i1 %t1347, label %reuse.in_place.1348, label %reuse.copy.1349
reuse.in_place.1348:
  %t1351 = getelementptr ptr, ptr %t5, i32 1
  %t1352 = load ptr, ptr %t1351
  call void @__free_recursive(ptr %t1352)
  %t1354 = inttoptr i64 198 to ptr
  %t1355 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1354, ptr %t1355
  call void @__inc_ref(ptr %t1344)
  %t1353 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1344, ptr %t1353
  br label %reuse.join.1350
reuse.copy.1349:
  %t1356 = call ptr @__alloc(i64 24, i32 2)
  %t1357 = inttoptr i64 198 to ptr
  %t1358 = getelementptr ptr, ptr %t1356, i32 0
  store ptr %t1357, ptr %t1358
  call void @__inc_ref(ptr %t1344)
  %t1359 = getelementptr ptr, ptr %t1356, i32 1
  store ptr %t1344, ptr %t1359
  call void @__inc_ref(ptr %t15)
  %t1360 = getelementptr ptr, ptr %t1356, i32 2
  store ptr %t15, ptr %t1360
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1350
reuse.join.1350:
  %t1361 = phi ptr [ %t5, %reuse.in_place.1348 ], [ %t1356, %reuse.copy.1349 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1344)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1361, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.94.1362:
  %t1363 = getelementptr ptr, ptr %t13, i32 1
  %t1364 = load ptr, ptr %t1363
  call void @__inc_ref(ptr %t1364)
  %t1365 = getelementptr i8, ptr %t5, i64 -8
  %t1366 = load i32, ptr %t1365
  %t1367 = icmp eq i32 %t1366, 1
  br i1 %t1367, label %reuse.in_place.1368, label %reuse.copy.1369
reuse.in_place.1368:
  %t1371 = getelementptr ptr, ptr %t5, i32 1
  %t1372 = load ptr, ptr %t1371
  call void @__free_recursive(ptr %t1372)
  %t1374 = inttoptr i64 199 to ptr
  %t1375 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1374, ptr %t1375
  call void @__inc_ref(ptr %t1364)
  %t1373 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1364, ptr %t1373
  br label %reuse.join.1370
reuse.copy.1369:
  %t1376 = call ptr @__alloc(i64 24, i32 2)
  %t1377 = inttoptr i64 199 to ptr
  %t1378 = getelementptr ptr, ptr %t1376, i32 0
  store ptr %t1377, ptr %t1378
  call void @__inc_ref(ptr %t1364)
  %t1379 = getelementptr ptr, ptr %t1376, i32 1
  store ptr %t1364, ptr %t1379
  call void @__inc_ref(ptr %t15)
  %t1380 = getelementptr ptr, ptr %t1376, i32 2
  store ptr %t15, ptr %t1380
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1370
reuse.join.1370:
  %t1381 = phi ptr [ %t5, %reuse.in_place.1368 ], [ %t1376, %reuse.copy.1369 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1364)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1381, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.95.1382:
  %t1383 = getelementptr ptr, ptr %t13, i32 1
  %t1384 = load ptr, ptr %t1383
  call void @__inc_ref(ptr %t1384)
  %t1385 = getelementptr i8, ptr %t5, i64 -8
  %t1386 = load i32, ptr %t1385
  %t1387 = icmp eq i32 %t1386, 1
  br i1 %t1387, label %reuse.in_place.1388, label %reuse.copy.1389
reuse.in_place.1388:
  %t1391 = getelementptr ptr, ptr %t5, i32 1
  %t1392 = load ptr, ptr %t1391
  call void @__free_recursive(ptr %t1392)
  %t1394 = inttoptr i64 200 to ptr
  %t1395 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1394, ptr %t1395
  call void @__inc_ref(ptr %t1384)
  %t1393 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1384, ptr %t1393
  br label %reuse.join.1390
reuse.copy.1389:
  %t1396 = call ptr @__alloc(i64 24, i32 2)
  %t1397 = inttoptr i64 200 to ptr
  %t1398 = getelementptr ptr, ptr %t1396, i32 0
  store ptr %t1397, ptr %t1398
  call void @__inc_ref(ptr %t1384)
  %t1399 = getelementptr ptr, ptr %t1396, i32 1
  store ptr %t1384, ptr %t1399
  call void @__inc_ref(ptr %t15)
  %t1400 = getelementptr ptr, ptr %t1396, i32 2
  store ptr %t15, ptr %t1400
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1390
reuse.join.1390:
  %t1401 = phi ptr [ %t5, %reuse.in_place.1388 ], [ %t1396, %reuse.copy.1389 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1384)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1401, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.96.1402:
  %t1403 = getelementptr ptr, ptr %t13, i32 1
  %t1404 = load ptr, ptr %t1403
  call void @__inc_ref(ptr %t1404)
  %t1405 = getelementptr i8, ptr %t5, i64 -8
  %t1406 = load i32, ptr %t1405
  %t1407 = icmp eq i32 %t1406, 1
  br i1 %t1407, label %reuse.in_place.1408, label %reuse.copy.1409
reuse.in_place.1408:
  %t1411 = getelementptr ptr, ptr %t5, i32 1
  %t1412 = load ptr, ptr %t1411
  call void @__free_recursive(ptr %t1412)
  %t1414 = inttoptr i64 201 to ptr
  %t1415 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1414, ptr %t1415
  call void @__inc_ref(ptr %t1404)
  %t1413 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1404, ptr %t1413
  br label %reuse.join.1410
reuse.copy.1409:
  %t1416 = call ptr @__alloc(i64 24, i32 2)
  %t1417 = inttoptr i64 201 to ptr
  %t1418 = getelementptr ptr, ptr %t1416, i32 0
  store ptr %t1417, ptr %t1418
  call void @__inc_ref(ptr %t1404)
  %t1419 = getelementptr ptr, ptr %t1416, i32 1
  store ptr %t1404, ptr %t1419
  call void @__inc_ref(ptr %t15)
  %t1420 = getelementptr ptr, ptr %t1416, i32 2
  store ptr %t15, ptr %t1420
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1410
reuse.join.1410:
  %t1421 = phi ptr [ %t5, %reuse.in_place.1408 ], [ %t1416, %reuse.copy.1409 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1404)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1421, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.97.1422:
  %t1423 = getelementptr ptr, ptr %t13, i32 1
  %t1424 = load ptr, ptr %t1423
  call void @__inc_ref(ptr %t1424)
  %t1425 = getelementptr i8, ptr %t5, i64 -8
  %t1426 = load i32, ptr %t1425
  %t1427 = icmp eq i32 %t1426, 1
  br i1 %t1427, label %reuse.in_place.1428, label %reuse.copy.1429
reuse.in_place.1428:
  %t1431 = getelementptr ptr, ptr %t5, i32 1
  %t1432 = load ptr, ptr %t1431
  call void @__free_recursive(ptr %t1432)
  %t1434 = inttoptr i64 202 to ptr
  %t1435 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1434, ptr %t1435
  call void @__inc_ref(ptr %t1424)
  %t1433 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1424, ptr %t1433
  br label %reuse.join.1430
reuse.copy.1429:
  %t1436 = call ptr @__alloc(i64 24, i32 2)
  %t1437 = inttoptr i64 202 to ptr
  %t1438 = getelementptr ptr, ptr %t1436, i32 0
  store ptr %t1437, ptr %t1438
  call void @__inc_ref(ptr %t1424)
  %t1439 = getelementptr ptr, ptr %t1436, i32 1
  store ptr %t1424, ptr %t1439
  call void @__inc_ref(ptr %t15)
  %t1440 = getelementptr ptr, ptr %t1436, i32 2
  store ptr %t15, ptr %t1440
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1430
reuse.join.1430:
  %t1441 = phi ptr [ %t5, %reuse.in_place.1428 ], [ %t1436, %reuse.copy.1429 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1424)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1441, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.98.1442:
  %t1443 = getelementptr ptr, ptr %t13, i32 1
  %t1444 = load ptr, ptr %t1443
  call void @__inc_ref(ptr %t1444)
  %t1445 = getelementptr i8, ptr %t5, i64 -8
  %t1446 = load i32, ptr %t1445
  %t1447 = icmp eq i32 %t1446, 1
  br i1 %t1447, label %reuse.in_place.1448, label %reuse.copy.1449
reuse.in_place.1448:
  %t1451 = getelementptr ptr, ptr %t5, i32 1
  %t1452 = load ptr, ptr %t1451
  call void @__free_recursive(ptr %t1452)
  %t1454 = inttoptr i64 203 to ptr
  %t1455 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1454, ptr %t1455
  call void @__inc_ref(ptr %t1444)
  %t1453 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1444, ptr %t1453
  br label %reuse.join.1450
reuse.copy.1449:
  %t1456 = call ptr @__alloc(i64 24, i32 2)
  %t1457 = inttoptr i64 203 to ptr
  %t1458 = getelementptr ptr, ptr %t1456, i32 0
  store ptr %t1457, ptr %t1458
  call void @__inc_ref(ptr %t1444)
  %t1459 = getelementptr ptr, ptr %t1456, i32 1
  store ptr %t1444, ptr %t1459
  call void @__inc_ref(ptr %t15)
  %t1460 = getelementptr ptr, ptr %t1456, i32 2
  store ptr %t15, ptr %t1460
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1450
reuse.join.1450:
  %t1461 = phi ptr [ %t5, %reuse.in_place.1448 ], [ %t1456, %reuse.copy.1449 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1444)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1461, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.99.1462:
  %t1463 = getelementptr ptr, ptr %t13, i32 1
  %t1464 = load ptr, ptr %t1463
  call void @__inc_ref(ptr %t1464)
  %t1465 = getelementptr i8, ptr %t5, i64 -8
  %t1466 = load i32, ptr %t1465
  %t1467 = icmp eq i32 %t1466, 1
  br i1 %t1467, label %reuse.in_place.1468, label %reuse.copy.1469
reuse.in_place.1468:
  %t1471 = getelementptr ptr, ptr %t5, i32 1
  %t1472 = load ptr, ptr %t1471
  call void @__free_recursive(ptr %t1472)
  %t1474 = inttoptr i64 204 to ptr
  %t1475 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1474, ptr %t1475
  call void @__inc_ref(ptr %t1464)
  %t1473 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1464, ptr %t1473
  br label %reuse.join.1470
reuse.copy.1469:
  %t1476 = call ptr @__alloc(i64 24, i32 2)
  %t1477 = inttoptr i64 204 to ptr
  %t1478 = getelementptr ptr, ptr %t1476, i32 0
  store ptr %t1477, ptr %t1478
  call void @__inc_ref(ptr %t1464)
  %t1479 = getelementptr ptr, ptr %t1476, i32 1
  store ptr %t1464, ptr %t1479
  call void @__inc_ref(ptr %t15)
  %t1480 = getelementptr ptr, ptr %t1476, i32 2
  store ptr %t15, ptr %t1480
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1470
reuse.join.1470:
  %t1481 = phi ptr [ %t5, %reuse.in_place.1468 ], [ %t1476, %reuse.copy.1469 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1464)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1481, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.100.1482:
  %t1483 = getelementptr ptr, ptr %t13, i32 1
  %t1484 = load ptr, ptr %t1483
  call void @__inc_ref(ptr %t1484)
  %t1485 = getelementptr i8, ptr %t5, i64 -8
  %t1486 = load i32, ptr %t1485
  %t1487 = icmp eq i32 %t1486, 1
  br i1 %t1487, label %reuse.in_place.1488, label %reuse.copy.1489
reuse.in_place.1488:
  %t1491 = getelementptr ptr, ptr %t5, i32 1
  %t1492 = load ptr, ptr %t1491
  call void @__free_recursive(ptr %t1492)
  %t1494 = inttoptr i64 205 to ptr
  %t1495 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1494, ptr %t1495
  call void @__inc_ref(ptr %t1484)
  %t1493 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1484, ptr %t1493
  br label %reuse.join.1490
reuse.copy.1489:
  %t1496 = call ptr @__alloc(i64 24, i32 2)
  %t1497 = inttoptr i64 205 to ptr
  %t1498 = getelementptr ptr, ptr %t1496, i32 0
  store ptr %t1497, ptr %t1498
  call void @__inc_ref(ptr %t1484)
  %t1499 = getelementptr ptr, ptr %t1496, i32 1
  store ptr %t1484, ptr %t1499
  call void @__inc_ref(ptr %t15)
  %t1500 = getelementptr ptr, ptr %t1496, i32 2
  store ptr %t15, ptr %t1500
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1490
reuse.join.1490:
  %t1501 = phi ptr [ %t5, %reuse.in_place.1488 ], [ %t1496, %reuse.copy.1489 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1484)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1501, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.101.1502:
  %t1503 = getelementptr ptr, ptr %t13, i32 1
  %t1504 = load ptr, ptr %t1503
  call void @__inc_ref(ptr %t1504)
  %t1505 = getelementptr i8, ptr %t5, i64 -8
  %t1506 = load i32, ptr %t1505
  %t1507 = icmp eq i32 %t1506, 1
  br i1 %t1507, label %reuse.in_place.1508, label %reuse.copy.1509
reuse.in_place.1508:
  %t1511 = getelementptr ptr, ptr %t5, i32 1
  %t1512 = load ptr, ptr %t1511
  call void @__free_recursive(ptr %t1512)
  %t1514 = inttoptr i64 206 to ptr
  %t1515 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1514, ptr %t1515
  call void @__inc_ref(ptr %t1504)
  %t1513 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1504, ptr %t1513
  br label %reuse.join.1510
reuse.copy.1509:
  %t1516 = call ptr @__alloc(i64 24, i32 2)
  %t1517 = inttoptr i64 206 to ptr
  %t1518 = getelementptr ptr, ptr %t1516, i32 0
  store ptr %t1517, ptr %t1518
  call void @__inc_ref(ptr %t1504)
  %t1519 = getelementptr ptr, ptr %t1516, i32 1
  store ptr %t1504, ptr %t1519
  call void @__inc_ref(ptr %t15)
  %t1520 = getelementptr ptr, ptr %t1516, i32 2
  store ptr %t15, ptr %t1520
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1510
reuse.join.1510:
  %t1521 = phi ptr [ %t5, %reuse.in_place.1508 ], [ %t1516, %reuse.copy.1509 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1504)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1521, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.102.1522:
  %t1523 = getelementptr ptr, ptr %t13, i32 1
  %t1524 = load ptr, ptr %t1523
  call void @__inc_ref(ptr %t1524)
  %t1525 = getelementptr i8, ptr %t5, i64 -8
  %t1526 = load i32, ptr %t1525
  %t1527 = icmp eq i32 %t1526, 1
  br i1 %t1527, label %reuse.in_place.1528, label %reuse.copy.1529
reuse.in_place.1528:
  %t1531 = getelementptr ptr, ptr %t5, i32 1
  %t1532 = load ptr, ptr %t1531
  call void @__free_recursive(ptr %t1532)
  %t1534 = inttoptr i64 207 to ptr
  %t1535 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1534, ptr %t1535
  call void @__inc_ref(ptr %t1524)
  %t1533 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1524, ptr %t1533
  br label %reuse.join.1530
reuse.copy.1529:
  %t1536 = call ptr @__alloc(i64 24, i32 2)
  %t1537 = inttoptr i64 207 to ptr
  %t1538 = getelementptr ptr, ptr %t1536, i32 0
  store ptr %t1537, ptr %t1538
  call void @__inc_ref(ptr %t1524)
  %t1539 = getelementptr ptr, ptr %t1536, i32 1
  store ptr %t1524, ptr %t1539
  call void @__inc_ref(ptr %t15)
  %t1540 = getelementptr ptr, ptr %t1536, i32 2
  store ptr %t15, ptr %t1540
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1530
reuse.join.1530:
  %t1541 = phi ptr [ %t5, %reuse.in_place.1528 ], [ %t1536, %reuse.copy.1529 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1524)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1541, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.103.1542:
  %t1543 = getelementptr ptr, ptr %t13, i32 1
  %t1544 = load ptr, ptr %t1543
  call void @__inc_ref(ptr %t1544)
  %t1545 = getelementptr i8, ptr %t5, i64 -8
  %t1546 = load i32, ptr %t1545
  %t1547 = icmp eq i32 %t1546, 1
  br i1 %t1547, label %reuse.in_place.1548, label %reuse.copy.1549
reuse.in_place.1548:
  %t1551 = getelementptr ptr, ptr %t5, i32 1
  %t1552 = load ptr, ptr %t1551
  call void @__free_recursive(ptr %t1552)
  %t1554 = inttoptr i64 208 to ptr
  %t1555 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1554, ptr %t1555
  call void @__inc_ref(ptr %t1544)
  %t1553 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1544, ptr %t1553
  br label %reuse.join.1550
reuse.copy.1549:
  %t1556 = call ptr @__alloc(i64 24, i32 2)
  %t1557 = inttoptr i64 208 to ptr
  %t1558 = getelementptr ptr, ptr %t1556, i32 0
  store ptr %t1557, ptr %t1558
  call void @__inc_ref(ptr %t1544)
  %t1559 = getelementptr ptr, ptr %t1556, i32 1
  store ptr %t1544, ptr %t1559
  call void @__inc_ref(ptr %t15)
  %t1560 = getelementptr ptr, ptr %t1556, i32 2
  store ptr %t15, ptr %t1560
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1550
reuse.join.1550:
  %t1561 = phi ptr [ %t5, %reuse.in_place.1548 ], [ %t1556, %reuse.copy.1549 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1544)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1561, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.104.1562:
  %t1563 = getelementptr ptr, ptr %t13, i32 1
  %t1564 = load ptr, ptr %t1563
  call void @__inc_ref(ptr %t1564)
  %t1565 = getelementptr i8, ptr %t5, i64 -8
  %t1566 = load i32, ptr %t1565
  %t1567 = icmp eq i32 %t1566, 1
  br i1 %t1567, label %reuse.in_place.1568, label %reuse.copy.1569
reuse.in_place.1568:
  %t1571 = getelementptr ptr, ptr %t5, i32 1
  %t1572 = load ptr, ptr %t1571
  call void @__free_recursive(ptr %t1572)
  %t1574 = inttoptr i64 209 to ptr
  %t1575 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1574, ptr %t1575
  call void @__inc_ref(ptr %t1564)
  %t1573 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1564, ptr %t1573
  br label %reuse.join.1570
reuse.copy.1569:
  %t1576 = call ptr @__alloc(i64 24, i32 2)
  %t1577 = inttoptr i64 209 to ptr
  %t1578 = getelementptr ptr, ptr %t1576, i32 0
  store ptr %t1577, ptr %t1578
  call void @__inc_ref(ptr %t1564)
  %t1579 = getelementptr ptr, ptr %t1576, i32 1
  store ptr %t1564, ptr %t1579
  call void @__inc_ref(ptr %t15)
  %t1580 = getelementptr ptr, ptr %t1576, i32 2
  store ptr %t15, ptr %t1580
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1570
reuse.join.1570:
  %t1581 = phi ptr [ %t5, %reuse.in_place.1568 ], [ %t1576, %reuse.copy.1569 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1564)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1581, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.105.1582:
  %t1583 = getelementptr ptr, ptr %t13, i32 1
  %t1584 = load ptr, ptr %t1583
  call void @__inc_ref(ptr %t1584)
  %t1585 = getelementptr i8, ptr %t5, i64 -8
  %t1586 = load i32, ptr %t1585
  %t1587 = icmp eq i32 %t1586, 1
  br i1 %t1587, label %reuse.in_place.1588, label %reuse.copy.1589
reuse.in_place.1588:
  %t1591 = getelementptr ptr, ptr %t5, i32 1
  %t1592 = load ptr, ptr %t1591
  call void @__free_recursive(ptr %t1592)
  %t1594 = inttoptr i64 210 to ptr
  %t1595 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1594, ptr %t1595
  call void @__inc_ref(ptr %t1584)
  %t1593 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1584, ptr %t1593
  br label %reuse.join.1590
reuse.copy.1589:
  %t1596 = call ptr @__alloc(i64 24, i32 2)
  %t1597 = inttoptr i64 210 to ptr
  %t1598 = getelementptr ptr, ptr %t1596, i32 0
  store ptr %t1597, ptr %t1598
  call void @__inc_ref(ptr %t1584)
  %t1599 = getelementptr ptr, ptr %t1596, i32 1
  store ptr %t1584, ptr %t1599
  call void @__inc_ref(ptr %t15)
  %t1600 = getelementptr ptr, ptr %t1596, i32 2
  store ptr %t15, ptr %t1600
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1590
reuse.join.1590:
  %t1601 = phi ptr [ %t5, %reuse.in_place.1588 ], [ %t1596, %reuse.copy.1589 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1584)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1601, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.106.1602:
  %t1603 = getelementptr ptr, ptr %t13, i32 1
  %t1604 = load ptr, ptr %t1603
  call void @__inc_ref(ptr %t1604)
  %t1605 = getelementptr i8, ptr %t5, i64 -8
  %t1606 = load i32, ptr %t1605
  %t1607 = icmp eq i32 %t1606, 1
  br i1 %t1607, label %reuse.in_place.1608, label %reuse.copy.1609
reuse.in_place.1608:
  %t1611 = getelementptr ptr, ptr %t5, i32 1
  %t1612 = load ptr, ptr %t1611
  call void @__free_recursive(ptr %t1612)
  %t1614 = inttoptr i64 211 to ptr
  %t1615 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1614, ptr %t1615
  call void @__inc_ref(ptr %t1604)
  %t1613 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1604, ptr %t1613
  br label %reuse.join.1610
reuse.copy.1609:
  %t1616 = call ptr @__alloc(i64 24, i32 2)
  %t1617 = inttoptr i64 211 to ptr
  %t1618 = getelementptr ptr, ptr %t1616, i32 0
  store ptr %t1617, ptr %t1618
  call void @__inc_ref(ptr %t1604)
  %t1619 = getelementptr ptr, ptr %t1616, i32 1
  store ptr %t1604, ptr %t1619
  call void @__inc_ref(ptr %t15)
  %t1620 = getelementptr ptr, ptr %t1616, i32 2
  store ptr %t15, ptr %t1620
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1610
reuse.join.1610:
  %t1621 = phi ptr [ %t5, %reuse.in_place.1608 ], [ %t1616, %reuse.copy.1609 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1604)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1621, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.107.1622:
  %t1623 = getelementptr ptr, ptr %t13, i32 1
  %t1624 = load ptr, ptr %t1623
  call void @__inc_ref(ptr %t1624)
  %t1625 = getelementptr i8, ptr %t5, i64 -8
  %t1626 = load i32, ptr %t1625
  %t1627 = icmp eq i32 %t1626, 1
  br i1 %t1627, label %reuse.in_place.1628, label %reuse.copy.1629
reuse.in_place.1628:
  %t1631 = getelementptr ptr, ptr %t5, i32 1
  %t1632 = load ptr, ptr %t1631
  call void @__free_recursive(ptr %t1632)
  %t1634 = inttoptr i64 212 to ptr
  %t1635 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1634, ptr %t1635
  call void @__inc_ref(ptr %t1624)
  %t1633 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1624, ptr %t1633
  br label %reuse.join.1630
reuse.copy.1629:
  %t1636 = call ptr @__alloc(i64 24, i32 2)
  %t1637 = inttoptr i64 212 to ptr
  %t1638 = getelementptr ptr, ptr %t1636, i32 0
  store ptr %t1637, ptr %t1638
  call void @__inc_ref(ptr %t1624)
  %t1639 = getelementptr ptr, ptr %t1636, i32 1
  store ptr %t1624, ptr %t1639
  call void @__inc_ref(ptr %t15)
  %t1640 = getelementptr ptr, ptr %t1636, i32 2
  store ptr %t15, ptr %t1640
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1630
reuse.join.1630:
  %t1641 = phi ptr [ %t5, %reuse.in_place.1628 ], [ %t1636, %reuse.copy.1629 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1624)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1641, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.108.1642:
  %t1643 = getelementptr ptr, ptr %t13, i32 1
  %t1644 = load ptr, ptr %t1643
  call void @__inc_ref(ptr %t1644)
  %t1645 = getelementptr i8, ptr %t5, i64 -8
  %t1646 = load i32, ptr %t1645
  %t1647 = icmp eq i32 %t1646, 1
  br i1 %t1647, label %reuse.in_place.1648, label %reuse.copy.1649
reuse.in_place.1648:
  %t1651 = getelementptr ptr, ptr %t5, i32 1
  %t1652 = load ptr, ptr %t1651
  call void @__free_recursive(ptr %t1652)
  %t1654 = inttoptr i64 213 to ptr
  %t1655 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1654, ptr %t1655
  call void @__inc_ref(ptr %t1644)
  %t1653 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1644, ptr %t1653
  br label %reuse.join.1650
reuse.copy.1649:
  %t1656 = call ptr @__alloc(i64 24, i32 2)
  %t1657 = inttoptr i64 213 to ptr
  %t1658 = getelementptr ptr, ptr %t1656, i32 0
  store ptr %t1657, ptr %t1658
  call void @__inc_ref(ptr %t1644)
  %t1659 = getelementptr ptr, ptr %t1656, i32 1
  store ptr %t1644, ptr %t1659
  call void @__inc_ref(ptr %t15)
  %t1660 = getelementptr ptr, ptr %t1656, i32 2
  store ptr %t15, ptr %t1660
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1650
reuse.join.1650:
  %t1661 = phi ptr [ %t5, %reuse.in_place.1648 ], [ %t1656, %reuse.copy.1649 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1644)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1661, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.109.1662:
  %t1663 = getelementptr ptr, ptr %t13, i32 1
  %t1664 = load ptr, ptr %t1663
  call void @__inc_ref(ptr %t1664)
  %t1665 = getelementptr i8, ptr %t5, i64 -8
  %t1666 = load i32, ptr %t1665
  %t1667 = icmp eq i32 %t1666, 1
  br i1 %t1667, label %reuse.in_place.1668, label %reuse.copy.1669
reuse.in_place.1668:
  %t1671 = getelementptr ptr, ptr %t5, i32 1
  %t1672 = load ptr, ptr %t1671
  call void @__free_recursive(ptr %t1672)
  %t1674 = inttoptr i64 214 to ptr
  %t1675 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1674, ptr %t1675
  call void @__inc_ref(ptr %t1664)
  %t1673 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1664, ptr %t1673
  br label %reuse.join.1670
reuse.copy.1669:
  %t1676 = call ptr @__alloc(i64 24, i32 2)
  %t1677 = inttoptr i64 214 to ptr
  %t1678 = getelementptr ptr, ptr %t1676, i32 0
  store ptr %t1677, ptr %t1678
  call void @__inc_ref(ptr %t1664)
  %t1679 = getelementptr ptr, ptr %t1676, i32 1
  store ptr %t1664, ptr %t1679
  call void @__inc_ref(ptr %t15)
  %t1680 = getelementptr ptr, ptr %t1676, i32 2
  store ptr %t15, ptr %t1680
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1670
reuse.join.1670:
  %t1681 = phi ptr [ %t5, %reuse.in_place.1668 ], [ %t1676, %reuse.copy.1669 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1664)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1681, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.110.1682:
  %t1683 = getelementptr ptr, ptr %t13, i32 1
  %t1684 = load ptr, ptr %t1683
  call void @__inc_ref(ptr %t1684)
  %t1685 = getelementptr i8, ptr %t5, i64 -8
  %t1686 = load i32, ptr %t1685
  %t1687 = icmp eq i32 %t1686, 1
  br i1 %t1687, label %reuse.in_place.1688, label %reuse.copy.1689
reuse.in_place.1688:
  %t1691 = getelementptr ptr, ptr %t5, i32 1
  %t1692 = load ptr, ptr %t1691
  call void @__free_recursive(ptr %t1692)
  %t1694 = inttoptr i64 215 to ptr
  %t1695 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1694, ptr %t1695
  call void @__inc_ref(ptr %t1684)
  %t1693 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1684, ptr %t1693
  br label %reuse.join.1690
reuse.copy.1689:
  %t1696 = call ptr @__alloc(i64 24, i32 2)
  %t1697 = inttoptr i64 215 to ptr
  %t1698 = getelementptr ptr, ptr %t1696, i32 0
  store ptr %t1697, ptr %t1698
  call void @__inc_ref(ptr %t1684)
  %t1699 = getelementptr ptr, ptr %t1696, i32 1
  store ptr %t1684, ptr %t1699
  call void @__inc_ref(ptr %t15)
  %t1700 = getelementptr ptr, ptr %t1696, i32 2
  store ptr %t15, ptr %t1700
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1690
reuse.join.1690:
  %t1701 = phi ptr [ %t5, %reuse.in_place.1688 ], [ %t1696, %reuse.copy.1689 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1684)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1701, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.111.1702:
  %t1703 = getelementptr ptr, ptr %t13, i32 1
  %t1704 = load ptr, ptr %t1703
  call void @__inc_ref(ptr %t1704)
  %t1705 = getelementptr i8, ptr %t5, i64 -8
  %t1706 = load i32, ptr %t1705
  %t1707 = icmp eq i32 %t1706, 1
  br i1 %t1707, label %reuse.in_place.1708, label %reuse.copy.1709
reuse.in_place.1708:
  %t1711 = getelementptr ptr, ptr %t5, i32 1
  %t1712 = load ptr, ptr %t1711
  call void @__free_recursive(ptr %t1712)
  %t1714 = inttoptr i64 216 to ptr
  %t1715 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1714, ptr %t1715
  call void @__inc_ref(ptr %t1704)
  %t1713 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1704, ptr %t1713
  br label %reuse.join.1710
reuse.copy.1709:
  %t1716 = call ptr @__alloc(i64 24, i32 2)
  %t1717 = inttoptr i64 216 to ptr
  %t1718 = getelementptr ptr, ptr %t1716, i32 0
  store ptr %t1717, ptr %t1718
  call void @__inc_ref(ptr %t1704)
  %t1719 = getelementptr ptr, ptr %t1716, i32 1
  store ptr %t1704, ptr %t1719
  call void @__inc_ref(ptr %t15)
  %t1720 = getelementptr ptr, ptr %t1716, i32 2
  store ptr %t15, ptr %t1720
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1710
reuse.join.1710:
  %t1721 = phi ptr [ %t5, %reuse.in_place.1708 ], [ %t1716, %reuse.copy.1709 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1704)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1721, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.112.1722:
  %t1723 = getelementptr ptr, ptr %t13, i32 1
  %t1724 = load ptr, ptr %t1723
  call void @__inc_ref(ptr %t1724)
  %t1725 = getelementptr i8, ptr %t5, i64 -8
  %t1726 = load i32, ptr %t1725
  %t1727 = icmp eq i32 %t1726, 1
  br i1 %t1727, label %reuse.in_place.1728, label %reuse.copy.1729
reuse.in_place.1728:
  %t1731 = getelementptr ptr, ptr %t5, i32 1
  %t1732 = load ptr, ptr %t1731
  call void @__free_recursive(ptr %t1732)
  %t1734 = inttoptr i64 217 to ptr
  %t1735 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1734, ptr %t1735
  call void @__inc_ref(ptr %t1724)
  %t1733 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1724, ptr %t1733
  br label %reuse.join.1730
reuse.copy.1729:
  %t1736 = call ptr @__alloc(i64 24, i32 2)
  %t1737 = inttoptr i64 217 to ptr
  %t1738 = getelementptr ptr, ptr %t1736, i32 0
  store ptr %t1737, ptr %t1738
  call void @__inc_ref(ptr %t1724)
  %t1739 = getelementptr ptr, ptr %t1736, i32 1
  store ptr %t1724, ptr %t1739
  call void @__inc_ref(ptr %t15)
  %t1740 = getelementptr ptr, ptr %t1736, i32 2
  store ptr %t15, ptr %t1740
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1730
reuse.join.1730:
  %t1741 = phi ptr [ %t5, %reuse.in_place.1728 ], [ %t1736, %reuse.copy.1729 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1724)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1741, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.113.1742:
  %t1743 = getelementptr ptr, ptr %t13, i32 1
  %t1744 = load ptr, ptr %t1743
  call void @__inc_ref(ptr %t1744)
  %t1745 = getelementptr i8, ptr %t5, i64 -8
  %t1746 = load i32, ptr %t1745
  %t1747 = icmp eq i32 %t1746, 1
  br i1 %t1747, label %reuse.in_place.1748, label %reuse.copy.1749
reuse.in_place.1748:
  %t1751 = getelementptr ptr, ptr %t5, i32 1
  %t1752 = load ptr, ptr %t1751
  call void @__free_recursive(ptr %t1752)
  %t1754 = inttoptr i64 218 to ptr
  %t1755 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1754, ptr %t1755
  call void @__inc_ref(ptr %t1744)
  %t1753 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1744, ptr %t1753
  br label %reuse.join.1750
reuse.copy.1749:
  %t1756 = call ptr @__alloc(i64 24, i32 2)
  %t1757 = inttoptr i64 218 to ptr
  %t1758 = getelementptr ptr, ptr %t1756, i32 0
  store ptr %t1757, ptr %t1758
  call void @__inc_ref(ptr %t1744)
  %t1759 = getelementptr ptr, ptr %t1756, i32 1
  store ptr %t1744, ptr %t1759
  call void @__inc_ref(ptr %t15)
  %t1760 = getelementptr ptr, ptr %t1756, i32 2
  store ptr %t15, ptr %t1760
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1750
reuse.join.1750:
  %t1761 = phi ptr [ %t5, %reuse.in_place.1748 ], [ %t1756, %reuse.copy.1749 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1744)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1761, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.116.1762:
  %t1763 = getelementptr ptr, ptr %t13, i32 1
  %t1764 = load ptr, ptr %t1763
  call void @__inc_ref(ptr %t1764)
  %t1765 = getelementptr i8, ptr %t5, i64 -8
  %t1766 = load i32, ptr %t1765
  %t1767 = icmp eq i32 %t1766, 1
  br i1 %t1767, label %reuse.in_place.1768, label %reuse.copy.1769
reuse.in_place.1768:
  %t1771 = getelementptr ptr, ptr %t5, i32 1
  %t1772 = load ptr, ptr %t1771
  call void @__free_recursive(ptr %t1772)
  %t1774 = inttoptr i64 221 to ptr
  %t1775 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1774, ptr %t1775
  call void @__inc_ref(ptr %t1764)
  %t1773 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1764, ptr %t1773
  br label %reuse.join.1770
reuse.copy.1769:
  %t1776 = call ptr @__alloc(i64 24, i32 2)
  %t1777 = inttoptr i64 221 to ptr
  %t1778 = getelementptr ptr, ptr %t1776, i32 0
  store ptr %t1777, ptr %t1778
  call void @__inc_ref(ptr %t1764)
  %t1779 = getelementptr ptr, ptr %t1776, i32 1
  store ptr %t1764, ptr %t1779
  call void @__inc_ref(ptr %t15)
  %t1780 = getelementptr ptr, ptr %t1776, i32 2
  store ptr %t15, ptr %t1780
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1770
reuse.join.1770:
  %t1781 = phi ptr [ %t5, %reuse.in_place.1768 ], [ %t1776, %reuse.copy.1769 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1764)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1781, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.117.1782:
  %t1783 = getelementptr ptr, ptr %t13, i32 1
  %t1784 = load ptr, ptr %t1783
  call void @__inc_ref(ptr %t1784)
  %t1785 = getelementptr i8, ptr %t5, i64 -8
  %t1786 = load i32, ptr %t1785
  %t1787 = icmp eq i32 %t1786, 1
  br i1 %t1787, label %reuse.in_place.1788, label %reuse.copy.1789
reuse.in_place.1788:
  %t1791 = getelementptr ptr, ptr %t5, i32 1
  %t1792 = load ptr, ptr %t1791
  call void @__free_recursive(ptr %t1792)
  %t1794 = inttoptr i64 222 to ptr
  %t1795 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1794, ptr %t1795
  call void @__inc_ref(ptr %t1784)
  %t1793 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1784, ptr %t1793
  br label %reuse.join.1790
reuse.copy.1789:
  %t1796 = call ptr @__alloc(i64 24, i32 2)
  %t1797 = inttoptr i64 222 to ptr
  %t1798 = getelementptr ptr, ptr %t1796, i32 0
  store ptr %t1797, ptr %t1798
  call void @__inc_ref(ptr %t1784)
  %t1799 = getelementptr ptr, ptr %t1796, i32 1
  store ptr %t1784, ptr %t1799
  call void @__inc_ref(ptr %t15)
  %t1800 = getelementptr ptr, ptr %t1796, i32 2
  store ptr %t15, ptr %t1800
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1790
reuse.join.1790:
  %t1801 = phi ptr [ %t5, %reuse.in_place.1788 ], [ %t1796, %reuse.copy.1789 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1784)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1801, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.120.1802:
  %t1803 = getelementptr ptr, ptr %t13, i32 1
  %t1804 = load ptr, ptr %t1803
  call void @__inc_ref(ptr %t1804)
  %t1805 = getelementptr i8, ptr %t5, i64 -8
  %t1806 = load i32, ptr %t1805
  %t1807 = icmp eq i32 %t1806, 1
  br i1 %t1807, label %reuse.in_place.1808, label %reuse.copy.1809
reuse.in_place.1808:
  %t1811 = getelementptr ptr, ptr %t5, i32 1
  %t1812 = load ptr, ptr %t1811
  call void @__free_recursive(ptr %t1812)
  %t1814 = inttoptr i64 225 to ptr
  %t1815 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1814, ptr %t1815
  call void @__inc_ref(ptr %t1804)
  %t1813 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1804, ptr %t1813
  br label %reuse.join.1810
reuse.copy.1809:
  %t1816 = call ptr @__alloc(i64 24, i32 2)
  %t1817 = inttoptr i64 225 to ptr
  %t1818 = getelementptr ptr, ptr %t1816, i32 0
  store ptr %t1817, ptr %t1818
  call void @__inc_ref(ptr %t1804)
  %t1819 = getelementptr ptr, ptr %t1816, i32 1
  store ptr %t1804, ptr %t1819
  call void @__inc_ref(ptr %t15)
  %t1820 = getelementptr ptr, ptr %t1816, i32 2
  store ptr %t15, ptr %t1820
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1810
reuse.join.1810:
  %t1821 = phi ptr [ %t5, %reuse.in_place.1808 ], [ %t1816, %reuse.copy.1809 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1804)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1821, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.121.1822:
  %t1823 = getelementptr ptr, ptr %t13, i32 1
  %t1824 = load ptr, ptr %t1823
  call void @__inc_ref(ptr %t1824)
  %t1825 = getelementptr i8, ptr %t5, i64 -8
  %t1826 = load i32, ptr %t1825
  %t1827 = icmp eq i32 %t1826, 1
  br i1 %t1827, label %reuse.in_place.1828, label %reuse.copy.1829
reuse.in_place.1828:
  %t1831 = getelementptr ptr, ptr %t5, i32 1
  %t1832 = load ptr, ptr %t1831
  call void @__free_recursive(ptr %t1832)
  %t1834 = inttoptr i64 226 to ptr
  %t1835 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1834, ptr %t1835
  call void @__inc_ref(ptr %t1824)
  %t1833 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1824, ptr %t1833
  br label %reuse.join.1830
reuse.copy.1829:
  %t1836 = call ptr @__alloc(i64 24, i32 2)
  %t1837 = inttoptr i64 226 to ptr
  %t1838 = getelementptr ptr, ptr %t1836, i32 0
  store ptr %t1837, ptr %t1838
  call void @__inc_ref(ptr %t1824)
  %t1839 = getelementptr ptr, ptr %t1836, i32 1
  store ptr %t1824, ptr %t1839
  call void @__inc_ref(ptr %t15)
  %t1840 = getelementptr ptr, ptr %t1836, i32 2
  store ptr %t15, ptr %t1840
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1830
reuse.join.1830:
  %t1841 = phi ptr [ %t5, %reuse.in_place.1828 ], [ %t1836, %reuse.copy.1829 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1824)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1841, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.124.1842:
  %t1843 = getelementptr ptr, ptr %t13, i32 1
  %t1844 = load ptr, ptr %t1843
  call void @__inc_ref(ptr %t1844)
  %t1845 = getelementptr i8, ptr %t5, i64 -8
  %t1846 = load i32, ptr %t1845
  %t1847 = icmp eq i32 %t1846, 1
  br i1 %t1847, label %reuse.in_place.1848, label %reuse.copy.1849
reuse.in_place.1848:
  %t1851 = getelementptr ptr, ptr %t5, i32 1
  %t1852 = load ptr, ptr %t1851
  call void @__free_recursive(ptr %t1852)
  %t1854 = inttoptr i64 229 to ptr
  %t1855 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1854, ptr %t1855
  call void @__inc_ref(ptr %t1844)
  %t1853 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1844, ptr %t1853
  br label %reuse.join.1850
reuse.copy.1849:
  %t1856 = call ptr @__alloc(i64 24, i32 2)
  %t1857 = inttoptr i64 229 to ptr
  %t1858 = getelementptr ptr, ptr %t1856, i32 0
  store ptr %t1857, ptr %t1858
  call void @__inc_ref(ptr %t1844)
  %t1859 = getelementptr ptr, ptr %t1856, i32 1
  store ptr %t1844, ptr %t1859
  call void @__inc_ref(ptr %t15)
  %t1860 = getelementptr ptr, ptr %t1856, i32 2
  store ptr %t15, ptr %t1860
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1850
reuse.join.1850:
  %t1861 = phi ptr [ %t5, %reuse.in_place.1848 ], [ %t1856, %reuse.copy.1849 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1844)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1861, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.125.1862:
  %t1863 = getelementptr ptr, ptr %t13, i32 1
  %t1864 = load ptr, ptr %t1863
  call void @__inc_ref(ptr %t1864)
  %t1865 = getelementptr i8, ptr %t5, i64 -8
  %t1866 = load i32, ptr %t1865
  %t1867 = icmp eq i32 %t1866, 1
  br i1 %t1867, label %reuse.in_place.1868, label %reuse.copy.1869
reuse.in_place.1868:
  %t1871 = getelementptr ptr, ptr %t5, i32 1
  %t1872 = load ptr, ptr %t1871
  call void @__free_recursive(ptr %t1872)
  %t1874 = inttoptr i64 230 to ptr
  %t1875 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1874, ptr %t1875
  call void @__inc_ref(ptr %t1864)
  %t1873 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1864, ptr %t1873
  br label %reuse.join.1870
reuse.copy.1869:
  %t1876 = call ptr @__alloc(i64 24, i32 2)
  %t1877 = inttoptr i64 230 to ptr
  %t1878 = getelementptr ptr, ptr %t1876, i32 0
  store ptr %t1877, ptr %t1878
  call void @__inc_ref(ptr %t1864)
  %t1879 = getelementptr ptr, ptr %t1876, i32 1
  store ptr %t1864, ptr %t1879
  call void @__inc_ref(ptr %t15)
  %t1880 = getelementptr ptr, ptr %t1876, i32 2
  store ptr %t15, ptr %t1880
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1870
reuse.join.1870:
  %t1881 = phi ptr [ %t5, %reuse.in_place.1868 ], [ %t1876, %reuse.copy.1869 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1864)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1881, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.126.1882:
  %t1883 = getelementptr ptr, ptr %t13, i32 1
  %t1884 = load ptr, ptr %t1883
  call void @__inc_ref(ptr %t1884)
  %t1885 = getelementptr i8, ptr %t5, i64 -8
  %t1886 = load i32, ptr %t1885
  %t1887 = icmp eq i32 %t1886, 1
  br i1 %t1887, label %reuse.in_place.1888, label %reuse.copy.1889
reuse.in_place.1888:
  %t1891 = getelementptr ptr, ptr %t5, i32 1
  %t1892 = load ptr, ptr %t1891
  call void @__free_recursive(ptr %t1892)
  %t1894 = inttoptr i64 231 to ptr
  %t1895 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1894, ptr %t1895
  call void @__inc_ref(ptr %t1884)
  %t1893 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1884, ptr %t1893
  br label %reuse.join.1890
reuse.copy.1889:
  %t1896 = call ptr @__alloc(i64 24, i32 2)
  %t1897 = inttoptr i64 231 to ptr
  %t1898 = getelementptr ptr, ptr %t1896, i32 0
  store ptr %t1897, ptr %t1898
  call void @__inc_ref(ptr %t1884)
  %t1899 = getelementptr ptr, ptr %t1896, i32 1
  store ptr %t1884, ptr %t1899
  call void @__inc_ref(ptr %t15)
  %t1900 = getelementptr ptr, ptr %t1896, i32 2
  store ptr %t15, ptr %t1900
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1890
reuse.join.1890:
  %t1901 = phi ptr [ %t5, %reuse.in_place.1888 ], [ %t1896, %reuse.copy.1889 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1884)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1901, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.127.1902:
  %t1903 = getelementptr ptr, ptr %t13, i32 1
  %t1904 = load ptr, ptr %t1903
  call void @__inc_ref(ptr %t1904)
  %t1905 = getelementptr i8, ptr %t5, i64 -8
  %t1906 = load i32, ptr %t1905
  %t1907 = icmp eq i32 %t1906, 1
  br i1 %t1907, label %reuse.in_place.1908, label %reuse.copy.1909
reuse.in_place.1908:
  %t1911 = getelementptr ptr, ptr %t5, i32 1
  %t1912 = load ptr, ptr %t1911
  call void @__free_recursive(ptr %t1912)
  %t1914 = inttoptr i64 232 to ptr
  %t1915 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1914, ptr %t1915
  call void @__inc_ref(ptr %t1904)
  %t1913 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1904, ptr %t1913
  br label %reuse.join.1910
reuse.copy.1909:
  %t1916 = call ptr @__alloc(i64 24, i32 2)
  %t1917 = inttoptr i64 232 to ptr
  %t1918 = getelementptr ptr, ptr %t1916, i32 0
  store ptr %t1917, ptr %t1918
  call void @__inc_ref(ptr %t1904)
  %t1919 = getelementptr ptr, ptr %t1916, i32 1
  store ptr %t1904, ptr %t1919
  call void @__inc_ref(ptr %t15)
  %t1920 = getelementptr ptr, ptr %t1916, i32 2
  store ptr %t15, ptr %t1920
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1910
reuse.join.1910:
  %t1921 = phi ptr [ %t5, %reuse.in_place.1908 ], [ %t1916, %reuse.copy.1909 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1904)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1921, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.128.1922:
  %t1923 = getelementptr ptr, ptr %t13, i32 1
  %t1924 = load ptr, ptr %t1923
  call void @__inc_ref(ptr %t1924)
  %t1925 = getelementptr i8, ptr %t5, i64 -8
  %t1926 = load i32, ptr %t1925
  %t1927 = icmp eq i32 %t1926, 1
  br i1 %t1927, label %reuse.in_place.1928, label %reuse.copy.1929
reuse.in_place.1928:
  %t1931 = getelementptr ptr, ptr %t5, i32 1
  %t1932 = load ptr, ptr %t1931
  call void @__free_recursive(ptr %t1932)
  %t1934 = inttoptr i64 233 to ptr
  %t1935 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1934, ptr %t1935
  call void @__inc_ref(ptr %t1924)
  %t1933 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1924, ptr %t1933
  br label %reuse.join.1930
reuse.copy.1929:
  %t1936 = call ptr @__alloc(i64 24, i32 2)
  %t1937 = inttoptr i64 233 to ptr
  %t1938 = getelementptr ptr, ptr %t1936, i32 0
  store ptr %t1937, ptr %t1938
  call void @__inc_ref(ptr %t1924)
  %t1939 = getelementptr ptr, ptr %t1936, i32 1
  store ptr %t1924, ptr %t1939
  call void @__inc_ref(ptr %t15)
  %t1940 = getelementptr ptr, ptr %t1936, i32 2
  store ptr %t15, ptr %t1940
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1930
reuse.join.1930:
  %t1941 = phi ptr [ %t5, %reuse.in_place.1928 ], [ %t1936, %reuse.copy.1929 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1924)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1941, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.129.1942:
  %t1943 = getelementptr ptr, ptr %t13, i32 1
  %t1944 = load ptr, ptr %t1943
  call void @__inc_ref(ptr %t1944)
  %t1945 = getelementptr i8, ptr %t5, i64 -8
  %t1946 = load i32, ptr %t1945
  %t1947 = icmp eq i32 %t1946, 1
  br i1 %t1947, label %reuse.in_place.1948, label %reuse.copy.1949
reuse.in_place.1948:
  %t1951 = getelementptr ptr, ptr %t5, i32 1
  %t1952 = load ptr, ptr %t1951
  call void @__free_recursive(ptr %t1952)
  %t1954 = inttoptr i64 234 to ptr
  %t1955 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1954, ptr %t1955
  call void @__inc_ref(ptr %t1944)
  %t1953 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1944, ptr %t1953
  br label %reuse.join.1950
reuse.copy.1949:
  %t1956 = call ptr @__alloc(i64 24, i32 2)
  %t1957 = inttoptr i64 234 to ptr
  %t1958 = getelementptr ptr, ptr %t1956, i32 0
  store ptr %t1957, ptr %t1958
  call void @__inc_ref(ptr %t1944)
  %t1959 = getelementptr ptr, ptr %t1956, i32 1
  store ptr %t1944, ptr %t1959
  call void @__inc_ref(ptr %t15)
  %t1960 = getelementptr ptr, ptr %t1956, i32 2
  store ptr %t15, ptr %t1960
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1950
reuse.join.1950:
  %t1961 = phi ptr [ %t5, %reuse.in_place.1948 ], [ %t1956, %reuse.copy.1949 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t1944)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t1961, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.default.19:
  unreachable
tco.case.arm.131.1962:
  %t1963 = getelementptr ptr, ptr %t5, i32 1
  %t1964 = load ptr, ptr %t1963
  %t1965 = getelementptr ptr, ptr %t5, i32 2
  %t1966 = load ptr, ptr %t1965
  %t1967 = getelementptr i8, ptr %t5, i64 -8
  %t1968 = load i32, ptr %t1967
  %t1969 = icmp eq i32 %t1968, 1
  br i1 %t1969, label %reuse.in_place.1970, label %reuse.copy.1971
reuse.in_place.1970:
  %t1973 = inttoptr i64 130 to ptr
  %t1974 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1973, ptr %t1974
  br label %reuse.join.1972
reuse.copy.1971:
  %t1975 = call ptr @__alloc(i64 24, i32 2)
  %t1976 = inttoptr i64 130 to ptr
  %t1977 = getelementptr ptr, ptr %t1975, i32 0
  store ptr %t1976, ptr %t1977
  call void @__inc_ref(ptr %t1964)
  %t1978 = getelementptr ptr, ptr %t1975, i32 1
  store ptr %t1964, ptr %t1978
  call void @__inc_ref(ptr %t1966)
  %t1979 = getelementptr ptr, ptr %t1975, i32 2
  store ptr %t1966, ptr %t1979
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1972
reuse.join.1972:
  %t1980 = phi ptr [ %t5, %reuse.in_place.1970 ], [ %t1975, %reuse.copy.1971 ]
  %t1981 = call ptr @__alloc(i64 16, i32 1)
  %t1982 = inttoptr i64 340 to ptr
  %t1983 = getelementptr ptr, ptr %t1981, i32 0
  store ptr %t1982, ptr %t1983
  call void @__inc_ref(ptr %t6)
  %t1984 = getelementptr ptr, ptr %t1981, i32 1
  store ptr %t6, ptr %t1984
  call void @__free_recursive(ptr %t6)
  store ptr %t1980, ptr %t3
  store ptr %t1981, ptr %t4
  br label %tco.loop.0
tco.case.arm.132.1985:
  %t1986 = getelementptr ptr, ptr %t5, i32 1
  %t1987 = load ptr, ptr %t1986
  %t1988 = getelementptr ptr, ptr %t5, i32 2
  %t1989 = load ptr, ptr %t1988
  %t1990 = getelementptr i8, ptr %t5, i64 -8
  %t1991 = load i32, ptr %t1990
  %t1992 = icmp eq i32 %t1991, 1
  br i1 %t1992, label %reuse.in_place.1993, label %reuse.copy.1994
reuse.in_place.1993:
  %t1996 = inttoptr i64 130 to ptr
  %t1997 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1996, ptr %t1997
  br label %reuse.join.1995
reuse.copy.1994:
  %t1998 = call ptr @__alloc(i64 24, i32 2)
  %t1999 = inttoptr i64 130 to ptr
  %t2000 = getelementptr ptr, ptr %t1998, i32 0
  store ptr %t1999, ptr %t2000
  call void @__inc_ref(ptr %t1987)
  %t2001 = getelementptr ptr, ptr %t1998, i32 1
  store ptr %t1987, ptr %t2001
  call void @__inc_ref(ptr %t1989)
  %t2002 = getelementptr ptr, ptr %t1998, i32 2
  store ptr %t1989, ptr %t2002
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1995
reuse.join.1995:
  %t2003 = phi ptr [ %t5, %reuse.in_place.1993 ], [ %t1998, %reuse.copy.1994 ]
  %t2004 = call ptr @__alloc(i64 16, i32 1)
  %t2005 = inttoptr i64 341 to ptr
  %t2006 = getelementptr ptr, ptr %t2004, i32 0
  store ptr %t2005, ptr %t2006
  call void @__inc_ref(ptr %t6)
  %t2007 = getelementptr ptr, ptr %t2004, i32 1
  store ptr %t6, ptr %t2007
  call void @__free_recursive(ptr %t6)
  store ptr %t2003, ptr %t3
  store ptr %t2004, ptr %t4
  br label %tco.loop.0
tco.case.arm.133.2008:
  %t2009 = getelementptr ptr, ptr %t5, i32 1
  %t2010 = load ptr, ptr %t2009
  %t2011 = getelementptr ptr, ptr %t5, i32 2
  %t2012 = load ptr, ptr %t2011
  %t2013 = getelementptr i8, ptr %t5, i64 -8
  %t2014 = load i32, ptr %t2013
  %t2015 = icmp eq i32 %t2014, 1
  br i1 %t2015, label %reuse.in_place.2016, label %reuse.copy.2017
reuse.in_place.2016:
  %t2019 = inttoptr i64 130 to ptr
  %t2020 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2019, ptr %t2020
  br label %reuse.join.2018
reuse.copy.2017:
  %t2021 = call ptr @__alloc(i64 24, i32 2)
  %t2022 = inttoptr i64 130 to ptr
  %t2023 = getelementptr ptr, ptr %t2021, i32 0
  store ptr %t2022, ptr %t2023
  call void @__inc_ref(ptr %t2010)
  %t2024 = getelementptr ptr, ptr %t2021, i32 1
  store ptr %t2010, ptr %t2024
  call void @__inc_ref(ptr %t2012)
  %t2025 = getelementptr ptr, ptr %t2021, i32 2
  store ptr %t2012, ptr %t2025
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2018
reuse.join.2018:
  %t2026 = phi ptr [ %t5, %reuse.in_place.2016 ], [ %t2021, %reuse.copy.2017 ]
  %t2027 = call ptr @__alloc(i64 16, i32 1)
  %t2028 = inttoptr i64 342 to ptr
  %t2029 = getelementptr ptr, ptr %t2027, i32 0
  store ptr %t2028, ptr %t2029
  call void @__inc_ref(ptr %t6)
  %t2030 = getelementptr ptr, ptr %t2027, i32 1
  store ptr %t6, ptr %t2030
  call void @__free_recursive(ptr %t6)
  store ptr %t2026, ptr %t3
  store ptr %t2027, ptr %t4
  br label %tco.loop.0
tco.case.arm.134.2031:
  %t2032 = getelementptr ptr, ptr %t5, i32 1
  %t2033 = load ptr, ptr %t2032
  %t2034 = getelementptr ptr, ptr %t5, i32 2
  %t2035 = load ptr, ptr %t2034
  %t2036 = getelementptr i8, ptr %t5, i64 -8
  %t2037 = load i32, ptr %t2036
  %t2038 = icmp eq i32 %t2037, 1
  br i1 %t2038, label %reuse.in_place.2039, label %reuse.copy.2040
reuse.in_place.2039:
  %t2042 = inttoptr i64 130 to ptr
  %t2043 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2042, ptr %t2043
  br label %reuse.join.2041
reuse.copy.2040:
  %t2044 = call ptr @__alloc(i64 24, i32 2)
  %t2045 = inttoptr i64 130 to ptr
  %t2046 = getelementptr ptr, ptr %t2044, i32 0
  store ptr %t2045, ptr %t2046
  call void @__inc_ref(ptr %t2033)
  %t2047 = getelementptr ptr, ptr %t2044, i32 1
  store ptr %t2033, ptr %t2047
  call void @__inc_ref(ptr %t2035)
  %t2048 = getelementptr ptr, ptr %t2044, i32 2
  store ptr %t2035, ptr %t2048
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2041
reuse.join.2041:
  %t2049 = phi ptr [ %t5, %reuse.in_place.2039 ], [ %t2044, %reuse.copy.2040 ]
  %t2050 = call ptr @__alloc(i64 16, i32 1)
  %t2051 = inttoptr i64 343 to ptr
  %t2052 = getelementptr ptr, ptr %t2050, i32 0
  store ptr %t2051, ptr %t2052
  call void @__inc_ref(ptr %t6)
  %t2053 = getelementptr ptr, ptr %t2050, i32 1
  store ptr %t6, ptr %t2053
  call void @__free_recursive(ptr %t6)
  store ptr %t2049, ptr %t3
  store ptr %t2050, ptr %t4
  br label %tco.loop.0
tco.case.arm.135.2054:
  %t2055 = getelementptr ptr, ptr %t5, i32 1
  %t2056 = load ptr, ptr %t2055
  %t2057 = getelementptr ptr, ptr %t5, i32 2
  %t2058 = load ptr, ptr %t2057
  %t2059 = getelementptr i8, ptr %t5, i64 -8
  %t2060 = load i32, ptr %t2059
  %t2061 = icmp eq i32 %t2060, 1
  br i1 %t2061, label %reuse.in_place.2062, label %reuse.copy.2063
reuse.in_place.2062:
  %t2065 = inttoptr i64 130 to ptr
  %t2066 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2065, ptr %t2066
  br label %reuse.join.2064
reuse.copy.2063:
  %t2067 = call ptr @__alloc(i64 24, i32 2)
  %t2068 = inttoptr i64 130 to ptr
  %t2069 = getelementptr ptr, ptr %t2067, i32 0
  store ptr %t2068, ptr %t2069
  call void @__inc_ref(ptr %t2056)
  %t2070 = getelementptr ptr, ptr %t2067, i32 1
  store ptr %t2056, ptr %t2070
  call void @__inc_ref(ptr %t2058)
  %t2071 = getelementptr ptr, ptr %t2067, i32 2
  store ptr %t2058, ptr %t2071
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2064
reuse.join.2064:
  %t2072 = phi ptr [ %t5, %reuse.in_place.2062 ], [ %t2067, %reuse.copy.2063 ]
  %t2073 = call ptr @__alloc(i64 16, i32 1)
  %t2074 = inttoptr i64 344 to ptr
  %t2075 = getelementptr ptr, ptr %t2073, i32 0
  store ptr %t2074, ptr %t2075
  call void @__inc_ref(ptr %t6)
  %t2076 = getelementptr ptr, ptr %t2073, i32 1
  store ptr %t6, ptr %t2076
  call void @__free_recursive(ptr %t6)
  store ptr %t2072, ptr %t3
  store ptr %t2073, ptr %t4
  br label %tco.loop.0
tco.case.arm.136.2077:
  %t2078 = getelementptr ptr, ptr %t5, i32 1
  %t2079 = load ptr, ptr %t2078
  %t2080 = getelementptr ptr, ptr %t5, i32 2
  %t2081 = load ptr, ptr %t2080
  %t2082 = getelementptr i8, ptr %t5, i64 -8
  %t2083 = load i32, ptr %t2082
  %t2084 = icmp eq i32 %t2083, 1
  br i1 %t2084, label %reuse.in_place.2085, label %reuse.copy.2086
reuse.in_place.2085:
  %t2088 = inttoptr i64 130 to ptr
  %t2089 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2088, ptr %t2089
  br label %reuse.join.2087
reuse.copy.2086:
  %t2090 = call ptr @__alloc(i64 24, i32 2)
  %t2091 = inttoptr i64 130 to ptr
  %t2092 = getelementptr ptr, ptr %t2090, i32 0
  store ptr %t2091, ptr %t2092
  call void @__inc_ref(ptr %t2079)
  %t2093 = getelementptr ptr, ptr %t2090, i32 1
  store ptr %t2079, ptr %t2093
  call void @__inc_ref(ptr %t2081)
  %t2094 = getelementptr ptr, ptr %t2090, i32 2
  store ptr %t2081, ptr %t2094
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2087
reuse.join.2087:
  %t2095 = phi ptr [ %t5, %reuse.in_place.2085 ], [ %t2090, %reuse.copy.2086 ]
  %t2096 = call ptr @__alloc(i64 16, i32 1)
  %t2097 = inttoptr i64 345 to ptr
  %t2098 = getelementptr ptr, ptr %t2096, i32 0
  store ptr %t2097, ptr %t2098
  call void @__inc_ref(ptr %t6)
  %t2099 = getelementptr ptr, ptr %t2096, i32 1
  store ptr %t6, ptr %t2099
  call void @__free_recursive(ptr %t6)
  store ptr %t2095, ptr %t3
  store ptr %t2096, ptr %t4
  br label %tco.loop.0
tco.case.arm.137.2100:
  %t2101 = getelementptr ptr, ptr %t5, i32 1
  %t2102 = load ptr, ptr %t2101
  %t2103 = getelementptr ptr, ptr %t5, i32 2
  %t2104 = load ptr, ptr %t2103
  %t2105 = getelementptr i8, ptr %t5, i64 -8
  %t2106 = load i32, ptr %t2105
  %t2107 = icmp eq i32 %t2106, 1
  br i1 %t2107, label %reuse.in_place.2108, label %reuse.copy.2109
reuse.in_place.2108:
  %t2111 = inttoptr i64 130 to ptr
  %t2112 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2111, ptr %t2112
  br label %reuse.join.2110
reuse.copy.2109:
  %t2113 = call ptr @__alloc(i64 24, i32 2)
  %t2114 = inttoptr i64 130 to ptr
  %t2115 = getelementptr ptr, ptr %t2113, i32 0
  store ptr %t2114, ptr %t2115
  call void @__inc_ref(ptr %t2102)
  %t2116 = getelementptr ptr, ptr %t2113, i32 1
  store ptr %t2102, ptr %t2116
  call void @__inc_ref(ptr %t2104)
  %t2117 = getelementptr ptr, ptr %t2113, i32 2
  store ptr %t2104, ptr %t2117
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2110
reuse.join.2110:
  %t2118 = phi ptr [ %t5, %reuse.in_place.2108 ], [ %t2113, %reuse.copy.2109 ]
  %t2119 = call ptr @__alloc(i64 16, i32 1)
  %t2120 = inttoptr i64 346 to ptr
  %t2121 = getelementptr ptr, ptr %t2119, i32 0
  store ptr %t2120, ptr %t2121
  call void @__inc_ref(ptr %t6)
  %t2122 = getelementptr ptr, ptr %t2119, i32 1
  store ptr %t6, ptr %t2122
  call void @__free_recursive(ptr %t6)
  store ptr %t2118, ptr %t3
  store ptr %t2119, ptr %t4
  br label %tco.loop.0
tco.case.arm.138.2123:
  %t2124 = getelementptr ptr, ptr %t5, i32 1
  %t2125 = load ptr, ptr %t2124
  %t2126 = getelementptr ptr, ptr %t5, i32 2
  %t2127 = load ptr, ptr %t2126
  %t2128 = getelementptr i8, ptr %t5, i64 -8
  %t2129 = load i32, ptr %t2128
  %t2130 = icmp eq i32 %t2129, 1
  br i1 %t2130, label %reuse.in_place.2131, label %reuse.copy.2132
reuse.in_place.2131:
  %t2134 = inttoptr i64 130 to ptr
  %t2135 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2134, ptr %t2135
  br label %reuse.join.2133
reuse.copy.2132:
  %t2136 = call ptr @__alloc(i64 24, i32 2)
  %t2137 = inttoptr i64 130 to ptr
  %t2138 = getelementptr ptr, ptr %t2136, i32 0
  store ptr %t2137, ptr %t2138
  call void @__inc_ref(ptr %t2125)
  %t2139 = getelementptr ptr, ptr %t2136, i32 1
  store ptr %t2125, ptr %t2139
  call void @__inc_ref(ptr %t2127)
  %t2140 = getelementptr ptr, ptr %t2136, i32 2
  store ptr %t2127, ptr %t2140
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2133
reuse.join.2133:
  %t2141 = phi ptr [ %t5, %reuse.in_place.2131 ], [ %t2136, %reuse.copy.2132 ]
  %t2142 = call ptr @__alloc(i64 16, i32 1)
  %t2143 = inttoptr i64 347 to ptr
  %t2144 = getelementptr ptr, ptr %t2142, i32 0
  store ptr %t2143, ptr %t2144
  call void @__inc_ref(ptr %t6)
  %t2145 = getelementptr ptr, ptr %t2142, i32 1
  store ptr %t6, ptr %t2145
  call void @__free_recursive(ptr %t6)
  store ptr %t2141, ptr %t3
  store ptr %t2142, ptr %t4
  br label %tco.loop.0
tco.case.arm.139.2146:
  %t2147 = getelementptr ptr, ptr %t5, i32 1
  %t2148 = load ptr, ptr %t2147
  %t2149 = getelementptr ptr, ptr %t5, i32 2
  %t2150 = load ptr, ptr %t2149
  %t2151 = getelementptr i8, ptr %t5, i64 -8
  %t2152 = load i32, ptr %t2151
  %t2153 = icmp eq i32 %t2152, 1
  br i1 %t2153, label %reuse.in_place.2154, label %reuse.copy.2155
reuse.in_place.2154:
  %t2157 = inttoptr i64 130 to ptr
  %t2158 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2157, ptr %t2158
  br label %reuse.join.2156
reuse.copy.2155:
  %t2159 = call ptr @__alloc(i64 24, i32 2)
  %t2160 = inttoptr i64 130 to ptr
  %t2161 = getelementptr ptr, ptr %t2159, i32 0
  store ptr %t2160, ptr %t2161
  call void @__inc_ref(ptr %t2148)
  %t2162 = getelementptr ptr, ptr %t2159, i32 1
  store ptr %t2148, ptr %t2162
  call void @__inc_ref(ptr %t2150)
  %t2163 = getelementptr ptr, ptr %t2159, i32 2
  store ptr %t2150, ptr %t2163
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2156
reuse.join.2156:
  %t2164 = phi ptr [ %t5, %reuse.in_place.2154 ], [ %t2159, %reuse.copy.2155 ]
  %t2165 = call ptr @__alloc(i64 16, i32 1)
  %t2166 = inttoptr i64 348 to ptr
  %t2167 = getelementptr ptr, ptr %t2165, i32 0
  store ptr %t2166, ptr %t2167
  call void @__inc_ref(ptr %t6)
  %t2168 = getelementptr ptr, ptr %t2165, i32 1
  store ptr %t6, ptr %t2168
  call void @__free_recursive(ptr %t6)
  store ptr %t2164, ptr %t3
  store ptr %t2165, ptr %t4
  br label %tco.loop.0
tco.case.arm.140.2169:
  %t2170 = getelementptr ptr, ptr %t5, i32 1
  %t2171 = load ptr, ptr %t2170
  %t2172 = getelementptr ptr, ptr %t5, i32 2
  %t2173 = load ptr, ptr %t2172
  %t2174 = getelementptr i8, ptr %t5, i64 -8
  %t2175 = load i32, ptr %t2174
  %t2176 = icmp eq i32 %t2175, 1
  br i1 %t2176, label %reuse.in_place.2177, label %reuse.copy.2178
reuse.in_place.2177:
  %t2180 = inttoptr i64 130 to ptr
  %t2181 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2180, ptr %t2181
  br label %reuse.join.2179
reuse.copy.2178:
  %t2182 = call ptr @__alloc(i64 24, i32 2)
  %t2183 = inttoptr i64 130 to ptr
  %t2184 = getelementptr ptr, ptr %t2182, i32 0
  store ptr %t2183, ptr %t2184
  call void @__inc_ref(ptr %t2171)
  %t2185 = getelementptr ptr, ptr %t2182, i32 1
  store ptr %t2171, ptr %t2185
  call void @__inc_ref(ptr %t2173)
  %t2186 = getelementptr ptr, ptr %t2182, i32 2
  store ptr %t2173, ptr %t2186
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2179
reuse.join.2179:
  %t2187 = phi ptr [ %t5, %reuse.in_place.2177 ], [ %t2182, %reuse.copy.2178 ]
  %t2188 = call ptr @__alloc(i64 16, i32 1)
  %t2189 = inttoptr i64 349 to ptr
  %t2190 = getelementptr ptr, ptr %t2188, i32 0
  store ptr %t2189, ptr %t2190
  call void @__inc_ref(ptr %t6)
  %t2191 = getelementptr ptr, ptr %t2188, i32 1
  store ptr %t6, ptr %t2191
  call void @__free_recursive(ptr %t6)
  store ptr %t2187, ptr %t3
  store ptr %t2188, ptr %t4
  br label %tco.loop.0
tco.case.arm.141.2192:
  %t2193 = getelementptr ptr, ptr %t5, i32 1
  %t2194 = load ptr, ptr %t2193
  %t2195 = getelementptr ptr, ptr %t5, i32 2
  %t2196 = load ptr, ptr %t2195
  %t2197 = getelementptr i8, ptr %t5, i64 -8
  %t2198 = load i32, ptr %t2197
  %t2199 = icmp eq i32 %t2198, 1
  br i1 %t2199, label %reuse.in_place.2200, label %reuse.copy.2201
reuse.in_place.2200:
  %t2203 = inttoptr i64 130 to ptr
  %t2204 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2203, ptr %t2204
  br label %reuse.join.2202
reuse.copy.2201:
  %t2205 = call ptr @__alloc(i64 24, i32 2)
  %t2206 = inttoptr i64 130 to ptr
  %t2207 = getelementptr ptr, ptr %t2205, i32 0
  store ptr %t2206, ptr %t2207
  call void @__inc_ref(ptr %t2194)
  %t2208 = getelementptr ptr, ptr %t2205, i32 1
  store ptr %t2194, ptr %t2208
  call void @__inc_ref(ptr %t2196)
  %t2209 = getelementptr ptr, ptr %t2205, i32 2
  store ptr %t2196, ptr %t2209
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2202
reuse.join.2202:
  %t2210 = phi ptr [ %t5, %reuse.in_place.2200 ], [ %t2205, %reuse.copy.2201 ]
  %t2211 = call ptr @__alloc(i64 16, i32 1)
  %t2212 = inttoptr i64 350 to ptr
  %t2213 = getelementptr ptr, ptr %t2211, i32 0
  store ptr %t2212, ptr %t2213
  call void @__inc_ref(ptr %t6)
  %t2214 = getelementptr ptr, ptr %t2211, i32 1
  store ptr %t6, ptr %t2214
  call void @__free_recursive(ptr %t6)
  store ptr %t2210, ptr %t3
  store ptr %t2211, ptr %t4
  br label %tco.loop.0
tco.case.arm.142.2215:
  %t2216 = getelementptr ptr, ptr %t5, i32 1
  %t2217 = load ptr, ptr %t2216
  %t2218 = getelementptr ptr, ptr %t5, i32 2
  %t2219 = load ptr, ptr %t2218
  %t2220 = getelementptr i8, ptr %t5, i64 -8
  %t2221 = load i32, ptr %t2220
  %t2222 = icmp eq i32 %t2221, 1
  br i1 %t2222, label %reuse.in_place.2223, label %reuse.copy.2224
reuse.in_place.2223:
  %t2226 = inttoptr i64 130 to ptr
  %t2227 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2226, ptr %t2227
  br label %reuse.join.2225
reuse.copy.2224:
  %t2228 = call ptr @__alloc(i64 24, i32 2)
  %t2229 = inttoptr i64 130 to ptr
  %t2230 = getelementptr ptr, ptr %t2228, i32 0
  store ptr %t2229, ptr %t2230
  call void @__inc_ref(ptr %t2217)
  %t2231 = getelementptr ptr, ptr %t2228, i32 1
  store ptr %t2217, ptr %t2231
  call void @__inc_ref(ptr %t2219)
  %t2232 = getelementptr ptr, ptr %t2228, i32 2
  store ptr %t2219, ptr %t2232
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2225
reuse.join.2225:
  %t2233 = phi ptr [ %t5, %reuse.in_place.2223 ], [ %t2228, %reuse.copy.2224 ]
  %t2234 = call ptr @__alloc(i64 16, i32 1)
  %t2235 = inttoptr i64 351 to ptr
  %t2236 = getelementptr ptr, ptr %t2234, i32 0
  store ptr %t2235, ptr %t2236
  call void @__inc_ref(ptr %t6)
  %t2237 = getelementptr ptr, ptr %t2234, i32 1
  store ptr %t6, ptr %t2237
  call void @__free_recursive(ptr %t6)
  store ptr %t2233, ptr %t3
  store ptr %t2234, ptr %t4
  br label %tco.loop.0
tco.case.arm.143.2238:
  %t2239 = getelementptr ptr, ptr %t5, i32 1
  %t2240 = load ptr, ptr %t2239
  %t2241 = getelementptr ptr, ptr %t5, i32 2
  %t2242 = load ptr, ptr %t2241
  %t2243 = getelementptr i8, ptr %t5, i64 -8
  %t2244 = load i32, ptr %t2243
  %t2245 = icmp eq i32 %t2244, 1
  br i1 %t2245, label %reuse.in_place.2246, label %reuse.copy.2247
reuse.in_place.2246:
  %t2249 = inttoptr i64 130 to ptr
  %t2250 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2249, ptr %t2250
  br label %reuse.join.2248
reuse.copy.2247:
  %t2251 = call ptr @__alloc(i64 24, i32 2)
  %t2252 = inttoptr i64 130 to ptr
  %t2253 = getelementptr ptr, ptr %t2251, i32 0
  store ptr %t2252, ptr %t2253
  call void @__inc_ref(ptr %t2240)
  %t2254 = getelementptr ptr, ptr %t2251, i32 1
  store ptr %t2240, ptr %t2254
  call void @__inc_ref(ptr %t2242)
  %t2255 = getelementptr ptr, ptr %t2251, i32 2
  store ptr %t2242, ptr %t2255
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2248
reuse.join.2248:
  %t2256 = phi ptr [ %t5, %reuse.in_place.2246 ], [ %t2251, %reuse.copy.2247 ]
  %t2257 = call ptr @__alloc(i64 16, i32 1)
  %t2258 = inttoptr i64 352 to ptr
  %t2259 = getelementptr ptr, ptr %t2257, i32 0
  store ptr %t2258, ptr %t2259
  call void @__inc_ref(ptr %t6)
  %t2260 = getelementptr ptr, ptr %t2257, i32 1
  store ptr %t6, ptr %t2260
  call void @__free_recursive(ptr %t6)
  store ptr %t2256, ptr %t3
  store ptr %t2257, ptr %t4
  br label %tco.loop.0
tco.case.arm.144.2261:
  %t2262 = getelementptr ptr, ptr %t5, i32 1
  %t2263 = load ptr, ptr %t2262
  %t2264 = getelementptr ptr, ptr %t5, i32 2
  %t2265 = load ptr, ptr %t2264
  %t2266 = getelementptr i8, ptr %t5, i64 -8
  %t2267 = load i32, ptr %t2266
  %t2268 = icmp eq i32 %t2267, 1
  br i1 %t2268, label %reuse.in_place.2269, label %reuse.copy.2270
reuse.in_place.2269:
  %t2272 = inttoptr i64 130 to ptr
  %t2273 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2272, ptr %t2273
  br label %reuse.join.2271
reuse.copy.2270:
  %t2274 = call ptr @__alloc(i64 24, i32 2)
  %t2275 = inttoptr i64 130 to ptr
  %t2276 = getelementptr ptr, ptr %t2274, i32 0
  store ptr %t2275, ptr %t2276
  call void @__inc_ref(ptr %t2263)
  %t2277 = getelementptr ptr, ptr %t2274, i32 1
  store ptr %t2263, ptr %t2277
  call void @__inc_ref(ptr %t2265)
  %t2278 = getelementptr ptr, ptr %t2274, i32 2
  store ptr %t2265, ptr %t2278
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2271
reuse.join.2271:
  %t2279 = phi ptr [ %t5, %reuse.in_place.2269 ], [ %t2274, %reuse.copy.2270 ]
  %t2280 = call ptr @__alloc(i64 16, i32 1)
  %t2281 = inttoptr i64 353 to ptr
  %t2282 = getelementptr ptr, ptr %t2280, i32 0
  store ptr %t2281, ptr %t2282
  call void @__inc_ref(ptr %t6)
  %t2283 = getelementptr ptr, ptr %t2280, i32 1
  store ptr %t6, ptr %t2283
  call void @__free_recursive(ptr %t6)
  store ptr %t2279, ptr %t3
  store ptr %t2280, ptr %t4
  br label %tco.loop.0
tco.case.arm.145.2284:
  %t2285 = getelementptr ptr, ptr %t5, i32 1
  %t2286 = load ptr, ptr %t2285
  %t2287 = getelementptr ptr, ptr %t5, i32 2
  %t2288 = load ptr, ptr %t2287
  %t2289 = getelementptr i8, ptr %t5, i64 -8
  %t2290 = load i32, ptr %t2289
  %t2291 = icmp eq i32 %t2290, 1
  br i1 %t2291, label %reuse.in_place.2292, label %reuse.copy.2293
reuse.in_place.2292:
  %t2295 = inttoptr i64 130 to ptr
  %t2296 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2295, ptr %t2296
  br label %reuse.join.2294
reuse.copy.2293:
  %t2297 = call ptr @__alloc(i64 24, i32 2)
  %t2298 = inttoptr i64 130 to ptr
  %t2299 = getelementptr ptr, ptr %t2297, i32 0
  store ptr %t2298, ptr %t2299
  call void @__inc_ref(ptr %t2286)
  %t2300 = getelementptr ptr, ptr %t2297, i32 1
  store ptr %t2286, ptr %t2300
  call void @__inc_ref(ptr %t2288)
  %t2301 = getelementptr ptr, ptr %t2297, i32 2
  store ptr %t2288, ptr %t2301
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2294
reuse.join.2294:
  %t2302 = phi ptr [ %t5, %reuse.in_place.2292 ], [ %t2297, %reuse.copy.2293 ]
  %t2303 = call ptr @__alloc(i64 16, i32 1)
  %t2304 = inttoptr i64 354 to ptr
  %t2305 = getelementptr ptr, ptr %t2303, i32 0
  store ptr %t2304, ptr %t2305
  call void @__inc_ref(ptr %t6)
  %t2306 = getelementptr ptr, ptr %t2303, i32 1
  store ptr %t6, ptr %t2306
  call void @__free_recursive(ptr %t6)
  store ptr %t2302, ptr %t3
  store ptr %t2303, ptr %t4
  br label %tco.loop.0
tco.case.arm.146.2307:
  %t2308 = getelementptr ptr, ptr %t5, i32 1
  %t2309 = load ptr, ptr %t2308
  %t2310 = getelementptr ptr, ptr %t5, i32 2
  %t2311 = load ptr, ptr %t2310
  %t2312 = getelementptr i8, ptr %t5, i64 -8
  %t2313 = load i32, ptr %t2312
  %t2314 = icmp eq i32 %t2313, 1
  br i1 %t2314, label %reuse.in_place.2315, label %reuse.copy.2316
reuse.in_place.2315:
  %t2318 = inttoptr i64 130 to ptr
  %t2319 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2318, ptr %t2319
  br label %reuse.join.2317
reuse.copy.2316:
  %t2320 = call ptr @__alloc(i64 24, i32 2)
  %t2321 = inttoptr i64 130 to ptr
  %t2322 = getelementptr ptr, ptr %t2320, i32 0
  store ptr %t2321, ptr %t2322
  call void @__inc_ref(ptr %t2309)
  %t2323 = getelementptr ptr, ptr %t2320, i32 1
  store ptr %t2309, ptr %t2323
  call void @__inc_ref(ptr %t2311)
  %t2324 = getelementptr ptr, ptr %t2320, i32 2
  store ptr %t2311, ptr %t2324
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2317
reuse.join.2317:
  %t2325 = phi ptr [ %t5, %reuse.in_place.2315 ], [ %t2320, %reuse.copy.2316 ]
  %t2326 = call ptr @__alloc(i64 16, i32 1)
  %t2327 = inttoptr i64 355 to ptr
  %t2328 = getelementptr ptr, ptr %t2326, i32 0
  store ptr %t2327, ptr %t2328
  call void @__inc_ref(ptr %t6)
  %t2329 = getelementptr ptr, ptr %t2326, i32 1
  store ptr %t6, ptr %t2329
  call void @__free_recursive(ptr %t6)
  store ptr %t2325, ptr %t3
  store ptr %t2326, ptr %t4
  br label %tco.loop.0
tco.case.arm.147.2330:
  %t2331 = getelementptr ptr, ptr %t5, i32 1
  %t2332 = load ptr, ptr %t2331
  %t2333 = getelementptr ptr, ptr %t5, i32 2
  %t2334 = load ptr, ptr %t2333
  %t2335 = getelementptr i8, ptr %t5, i64 -8
  %t2336 = load i32, ptr %t2335
  %t2337 = icmp eq i32 %t2336, 1
  br i1 %t2337, label %reuse.in_place.2338, label %reuse.copy.2339
reuse.in_place.2338:
  %t2341 = inttoptr i64 130 to ptr
  %t2342 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2341, ptr %t2342
  br label %reuse.join.2340
reuse.copy.2339:
  %t2343 = call ptr @__alloc(i64 24, i32 2)
  %t2344 = inttoptr i64 130 to ptr
  %t2345 = getelementptr ptr, ptr %t2343, i32 0
  store ptr %t2344, ptr %t2345
  call void @__inc_ref(ptr %t2332)
  %t2346 = getelementptr ptr, ptr %t2343, i32 1
  store ptr %t2332, ptr %t2346
  call void @__inc_ref(ptr %t2334)
  %t2347 = getelementptr ptr, ptr %t2343, i32 2
  store ptr %t2334, ptr %t2347
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2340
reuse.join.2340:
  %t2348 = phi ptr [ %t5, %reuse.in_place.2338 ], [ %t2343, %reuse.copy.2339 ]
  %t2349 = call ptr @__alloc(i64 16, i32 1)
  %t2350 = inttoptr i64 356 to ptr
  %t2351 = getelementptr ptr, ptr %t2349, i32 0
  store ptr %t2350, ptr %t2351
  call void @__inc_ref(ptr %t6)
  %t2352 = getelementptr ptr, ptr %t2349, i32 1
  store ptr %t6, ptr %t2352
  call void @__free_recursive(ptr %t6)
  store ptr %t2348, ptr %t3
  store ptr %t2349, ptr %t4
  br label %tco.loop.0
tco.case.arm.148.2353:
  %t2354 = getelementptr ptr, ptr %t5, i32 1
  %t2355 = load ptr, ptr %t2354
  %t2356 = getelementptr ptr, ptr %t5, i32 2
  %t2357 = load ptr, ptr %t2356
  %t2358 = getelementptr i8, ptr %t5, i64 -8
  %t2359 = load i32, ptr %t2358
  %t2360 = icmp eq i32 %t2359, 1
  br i1 %t2360, label %reuse.in_place.2361, label %reuse.copy.2362
reuse.in_place.2361:
  %t2364 = inttoptr i64 130 to ptr
  %t2365 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2364, ptr %t2365
  br label %reuse.join.2363
reuse.copy.2362:
  %t2366 = call ptr @__alloc(i64 24, i32 2)
  %t2367 = inttoptr i64 130 to ptr
  %t2368 = getelementptr ptr, ptr %t2366, i32 0
  store ptr %t2367, ptr %t2368
  call void @__inc_ref(ptr %t2355)
  %t2369 = getelementptr ptr, ptr %t2366, i32 1
  store ptr %t2355, ptr %t2369
  call void @__inc_ref(ptr %t2357)
  %t2370 = getelementptr ptr, ptr %t2366, i32 2
  store ptr %t2357, ptr %t2370
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2363
reuse.join.2363:
  %t2371 = phi ptr [ %t5, %reuse.in_place.2361 ], [ %t2366, %reuse.copy.2362 ]
  %t2372 = call ptr @__alloc(i64 16, i32 1)
  %t2373 = inttoptr i64 357 to ptr
  %t2374 = getelementptr ptr, ptr %t2372, i32 0
  store ptr %t2373, ptr %t2374
  call void @__inc_ref(ptr %t6)
  %t2375 = getelementptr ptr, ptr %t2372, i32 1
  store ptr %t6, ptr %t2375
  call void @__free_recursive(ptr %t6)
  store ptr %t2371, ptr %t3
  store ptr %t2372, ptr %t4
  br label %tco.loop.0
tco.case.arm.149.2376:
  %t2377 = getelementptr ptr, ptr %t5, i32 1
  %t2378 = load ptr, ptr %t2377
  %t2379 = getelementptr ptr, ptr %t5, i32 2
  %t2380 = load ptr, ptr %t2379
  %t2381 = getelementptr i8, ptr %t5, i64 -8
  %t2382 = load i32, ptr %t2381
  %t2383 = icmp eq i32 %t2382, 1
  br i1 %t2383, label %reuse.in_place.2384, label %reuse.copy.2385
reuse.in_place.2384:
  %t2387 = inttoptr i64 130 to ptr
  %t2388 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2387, ptr %t2388
  br label %reuse.join.2386
reuse.copy.2385:
  %t2389 = call ptr @__alloc(i64 24, i32 2)
  %t2390 = inttoptr i64 130 to ptr
  %t2391 = getelementptr ptr, ptr %t2389, i32 0
  store ptr %t2390, ptr %t2391
  call void @__inc_ref(ptr %t2378)
  %t2392 = getelementptr ptr, ptr %t2389, i32 1
  store ptr %t2378, ptr %t2392
  call void @__inc_ref(ptr %t2380)
  %t2393 = getelementptr ptr, ptr %t2389, i32 2
  store ptr %t2380, ptr %t2393
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2386
reuse.join.2386:
  %t2394 = phi ptr [ %t5, %reuse.in_place.2384 ], [ %t2389, %reuse.copy.2385 ]
  %t2395 = call ptr @__alloc(i64 16, i32 1)
  %t2396 = inttoptr i64 358 to ptr
  %t2397 = getelementptr ptr, ptr %t2395, i32 0
  store ptr %t2396, ptr %t2397
  call void @__inc_ref(ptr %t6)
  %t2398 = getelementptr ptr, ptr %t2395, i32 1
  store ptr %t6, ptr %t2398
  call void @__free_recursive(ptr %t6)
  store ptr %t2394, ptr %t3
  store ptr %t2395, ptr %t4
  br label %tco.loop.0
tco.case.arm.150.2399:
  %t2400 = getelementptr ptr, ptr %t5, i32 1
  %t2401 = load ptr, ptr %t2400
  %t2402 = getelementptr ptr, ptr %t5, i32 2
  %t2403 = load ptr, ptr %t2402
  %t2404 = getelementptr i8, ptr %t5, i64 -8
  %t2405 = load i32, ptr %t2404
  %t2406 = icmp eq i32 %t2405, 1
  br i1 %t2406, label %reuse.in_place.2407, label %reuse.copy.2408
reuse.in_place.2407:
  %t2410 = inttoptr i64 130 to ptr
  %t2411 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2410, ptr %t2411
  br label %reuse.join.2409
reuse.copy.2408:
  %t2412 = call ptr @__alloc(i64 24, i32 2)
  %t2413 = inttoptr i64 130 to ptr
  %t2414 = getelementptr ptr, ptr %t2412, i32 0
  store ptr %t2413, ptr %t2414
  call void @__inc_ref(ptr %t2401)
  %t2415 = getelementptr ptr, ptr %t2412, i32 1
  store ptr %t2401, ptr %t2415
  call void @__inc_ref(ptr %t2403)
  %t2416 = getelementptr ptr, ptr %t2412, i32 2
  store ptr %t2403, ptr %t2416
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2409
reuse.join.2409:
  %t2417 = phi ptr [ %t5, %reuse.in_place.2407 ], [ %t2412, %reuse.copy.2408 ]
  %t2418 = call ptr @__alloc(i64 16, i32 1)
  %t2419 = inttoptr i64 359 to ptr
  %t2420 = getelementptr ptr, ptr %t2418, i32 0
  store ptr %t2419, ptr %t2420
  call void @__inc_ref(ptr %t6)
  %t2421 = getelementptr ptr, ptr %t2418, i32 1
  store ptr %t6, ptr %t2421
  call void @__free_recursive(ptr %t6)
  store ptr %t2417, ptr %t3
  store ptr %t2418, ptr %t4
  br label %tco.loop.0
tco.case.arm.151.2422:
  %t2423 = getelementptr ptr, ptr %t5, i32 1
  %t2424 = load ptr, ptr %t2423
  %t2425 = getelementptr ptr, ptr %t5, i32 2
  %t2426 = load ptr, ptr %t2425
  %t2427 = getelementptr i8, ptr %t5, i64 -8
  %t2428 = load i32, ptr %t2427
  %t2429 = icmp eq i32 %t2428, 1
  br i1 %t2429, label %reuse.in_place.2430, label %reuse.copy.2431
reuse.in_place.2430:
  %t2433 = inttoptr i64 130 to ptr
  %t2434 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2433, ptr %t2434
  br label %reuse.join.2432
reuse.copy.2431:
  %t2435 = call ptr @__alloc(i64 24, i32 2)
  %t2436 = inttoptr i64 130 to ptr
  %t2437 = getelementptr ptr, ptr %t2435, i32 0
  store ptr %t2436, ptr %t2437
  call void @__inc_ref(ptr %t2424)
  %t2438 = getelementptr ptr, ptr %t2435, i32 1
  store ptr %t2424, ptr %t2438
  call void @__inc_ref(ptr %t2426)
  %t2439 = getelementptr ptr, ptr %t2435, i32 2
  store ptr %t2426, ptr %t2439
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2432
reuse.join.2432:
  %t2440 = phi ptr [ %t5, %reuse.in_place.2430 ], [ %t2435, %reuse.copy.2431 ]
  %t2441 = call ptr @__alloc(i64 16, i32 1)
  %t2442 = inttoptr i64 360 to ptr
  %t2443 = getelementptr ptr, ptr %t2441, i32 0
  store ptr %t2442, ptr %t2443
  call void @__inc_ref(ptr %t6)
  %t2444 = getelementptr ptr, ptr %t2441, i32 1
  store ptr %t6, ptr %t2444
  call void @__free_recursive(ptr %t6)
  store ptr %t2440, ptr %t3
  store ptr %t2441, ptr %t4
  br label %tco.loop.0
tco.case.arm.152.2445:
  %t2446 = getelementptr ptr, ptr %t5, i32 1
  %t2447 = load ptr, ptr %t2446
  %t2448 = getelementptr ptr, ptr %t5, i32 2
  %t2449 = load ptr, ptr %t2448
  %t2450 = getelementptr i8, ptr %t5, i64 -8
  %t2451 = load i32, ptr %t2450
  %t2452 = icmp eq i32 %t2451, 1
  br i1 %t2452, label %reuse.in_place.2453, label %reuse.copy.2454
reuse.in_place.2453:
  %t2456 = inttoptr i64 130 to ptr
  %t2457 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2456, ptr %t2457
  br label %reuse.join.2455
reuse.copy.2454:
  %t2458 = call ptr @__alloc(i64 24, i32 2)
  %t2459 = inttoptr i64 130 to ptr
  %t2460 = getelementptr ptr, ptr %t2458, i32 0
  store ptr %t2459, ptr %t2460
  call void @__inc_ref(ptr %t2447)
  %t2461 = getelementptr ptr, ptr %t2458, i32 1
  store ptr %t2447, ptr %t2461
  call void @__inc_ref(ptr %t2449)
  %t2462 = getelementptr ptr, ptr %t2458, i32 2
  store ptr %t2449, ptr %t2462
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2455
reuse.join.2455:
  %t2463 = phi ptr [ %t5, %reuse.in_place.2453 ], [ %t2458, %reuse.copy.2454 ]
  %t2464 = call ptr @__alloc(i64 16, i32 1)
  %t2465 = inttoptr i64 361 to ptr
  %t2466 = getelementptr ptr, ptr %t2464, i32 0
  store ptr %t2465, ptr %t2466
  call void @__inc_ref(ptr %t6)
  %t2467 = getelementptr ptr, ptr %t2464, i32 1
  store ptr %t6, ptr %t2467
  call void @__free_recursive(ptr %t6)
  store ptr %t2463, ptr %t3
  store ptr %t2464, ptr %t4
  br label %tco.loop.0
tco.case.arm.153.2468:
  %t2469 = getelementptr ptr, ptr %t5, i32 1
  %t2470 = load ptr, ptr %t2469
  %t2471 = getelementptr ptr, ptr %t5, i32 2
  %t2472 = load ptr, ptr %t2471
  %t2473 = getelementptr i8, ptr %t5, i64 -8
  %t2474 = load i32, ptr %t2473
  %t2475 = icmp eq i32 %t2474, 1
  br i1 %t2475, label %reuse.in_place.2476, label %reuse.copy.2477
reuse.in_place.2476:
  %t2479 = inttoptr i64 130 to ptr
  %t2480 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2479, ptr %t2480
  br label %reuse.join.2478
reuse.copy.2477:
  %t2481 = call ptr @__alloc(i64 24, i32 2)
  %t2482 = inttoptr i64 130 to ptr
  %t2483 = getelementptr ptr, ptr %t2481, i32 0
  store ptr %t2482, ptr %t2483
  call void @__inc_ref(ptr %t2470)
  %t2484 = getelementptr ptr, ptr %t2481, i32 1
  store ptr %t2470, ptr %t2484
  call void @__inc_ref(ptr %t2472)
  %t2485 = getelementptr ptr, ptr %t2481, i32 2
  store ptr %t2472, ptr %t2485
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2478
reuse.join.2478:
  %t2486 = phi ptr [ %t5, %reuse.in_place.2476 ], [ %t2481, %reuse.copy.2477 ]
  %t2487 = call ptr @__alloc(i64 16, i32 1)
  %t2488 = inttoptr i64 362 to ptr
  %t2489 = getelementptr ptr, ptr %t2487, i32 0
  store ptr %t2488, ptr %t2489
  call void @__inc_ref(ptr %t6)
  %t2490 = getelementptr ptr, ptr %t2487, i32 1
  store ptr %t6, ptr %t2490
  call void @__free_recursive(ptr %t6)
  store ptr %t2486, ptr %t3
  store ptr %t2487, ptr %t4
  br label %tco.loop.0
tco.case.arm.154.2491:
  %t2492 = getelementptr ptr, ptr %t5, i32 1
  %t2493 = load ptr, ptr %t2492
  %t2494 = getelementptr ptr, ptr %t5, i32 2
  %t2495 = load ptr, ptr %t2494
  %t2496 = getelementptr i8, ptr %t5, i64 -8
  %t2497 = load i32, ptr %t2496
  %t2498 = icmp eq i32 %t2497, 1
  br i1 %t2498, label %reuse.in_place.2499, label %reuse.copy.2500
reuse.in_place.2499:
  %t2502 = inttoptr i64 130 to ptr
  %t2503 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2502, ptr %t2503
  br label %reuse.join.2501
reuse.copy.2500:
  %t2504 = call ptr @__alloc(i64 24, i32 2)
  %t2505 = inttoptr i64 130 to ptr
  %t2506 = getelementptr ptr, ptr %t2504, i32 0
  store ptr %t2505, ptr %t2506
  call void @__inc_ref(ptr %t2493)
  %t2507 = getelementptr ptr, ptr %t2504, i32 1
  store ptr %t2493, ptr %t2507
  call void @__inc_ref(ptr %t2495)
  %t2508 = getelementptr ptr, ptr %t2504, i32 2
  store ptr %t2495, ptr %t2508
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2501
reuse.join.2501:
  %t2509 = phi ptr [ %t5, %reuse.in_place.2499 ], [ %t2504, %reuse.copy.2500 ]
  %t2510 = call ptr @__alloc(i64 16, i32 1)
  %t2511 = inttoptr i64 363 to ptr
  %t2512 = getelementptr ptr, ptr %t2510, i32 0
  store ptr %t2511, ptr %t2512
  call void @__inc_ref(ptr %t6)
  %t2513 = getelementptr ptr, ptr %t2510, i32 1
  store ptr %t6, ptr %t2513
  call void @__free_recursive(ptr %t6)
  store ptr %t2509, ptr %t3
  store ptr %t2510, ptr %t4
  br label %tco.loop.0
tco.case.arm.155.2514:
  %t2515 = getelementptr ptr, ptr %t5, i32 1
  %t2516 = load ptr, ptr %t2515
  %t2517 = getelementptr ptr, ptr %t5, i32 2
  %t2518 = load ptr, ptr %t2517
  %t2519 = getelementptr i8, ptr %t5, i64 -8
  %t2520 = load i32, ptr %t2519
  %t2521 = icmp eq i32 %t2520, 1
  br i1 %t2521, label %reuse.in_place.2522, label %reuse.copy.2523
reuse.in_place.2522:
  %t2525 = inttoptr i64 130 to ptr
  %t2526 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2525, ptr %t2526
  br label %reuse.join.2524
reuse.copy.2523:
  %t2527 = call ptr @__alloc(i64 24, i32 2)
  %t2528 = inttoptr i64 130 to ptr
  %t2529 = getelementptr ptr, ptr %t2527, i32 0
  store ptr %t2528, ptr %t2529
  call void @__inc_ref(ptr %t2516)
  %t2530 = getelementptr ptr, ptr %t2527, i32 1
  store ptr %t2516, ptr %t2530
  call void @__inc_ref(ptr %t2518)
  %t2531 = getelementptr ptr, ptr %t2527, i32 2
  store ptr %t2518, ptr %t2531
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2524
reuse.join.2524:
  %t2532 = phi ptr [ %t5, %reuse.in_place.2522 ], [ %t2527, %reuse.copy.2523 ]
  %t2533 = call ptr @__alloc(i64 16, i32 1)
  %t2534 = inttoptr i64 364 to ptr
  %t2535 = getelementptr ptr, ptr %t2533, i32 0
  store ptr %t2534, ptr %t2535
  call void @__inc_ref(ptr %t6)
  %t2536 = getelementptr ptr, ptr %t2533, i32 1
  store ptr %t6, ptr %t2536
  call void @__free_recursive(ptr %t6)
  store ptr %t2532, ptr %t3
  store ptr %t2533, ptr %t4
  br label %tco.loop.0
tco.case.arm.156.2537:
  %t2538 = getelementptr ptr, ptr %t5, i32 1
  %t2539 = load ptr, ptr %t2538
  call void @__inc_ref(ptr %t2539)
  %t2540 = getelementptr ptr, ptr %t5, i32 2
  %t2541 = load ptr, ptr %t2540
  call void @__inc_ref(ptr %t2541)
  %t2542 = getelementptr ptr, ptr %t5, i32 3
  %t2543 = load ptr, ptr %t2542
  call void @__inc_ref(ptr %t2543)
  %t2544 = call ptr @__alloc(i64 24, i32 2)
  %t2545 = inttoptr i64 130 to ptr
  %t2546 = getelementptr ptr, ptr %t2544, i32 0
  store ptr %t2545, ptr %t2546
  call void @__inc_ref(ptr %t2539)
  %t2547 = getelementptr ptr, ptr %t2544, i32 1
  store ptr %t2539, ptr %t2547
  call void @__inc_ref(ptr %t2541)
  %t2548 = getelementptr ptr, ptr %t2544, i32 2
  store ptr %t2541, ptr %t2548
  %t2549 = call ptr @__alloc(i64 24, i32 2)
  %t2550 = inttoptr i64 365 to ptr
  %t2551 = getelementptr ptr, ptr %t2549, i32 0
  store ptr %t2550, ptr %t2551
  call void @__inc_ref(ptr %t6)
  %t2552 = getelementptr ptr, ptr %t2549, i32 1
  store ptr %t6, ptr %t2552
  call void @__inc_ref(ptr %t2543)
  %t2553 = getelementptr ptr, ptr %t2549, i32 2
  store ptr %t2543, ptr %t2553
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t2543)
  call void @__free_recursive(ptr %t2541)
  call void @__free_recursive(ptr %t2539)
  store ptr %t2544, ptr %t3
  store ptr %t2549, ptr %t4
  br label %tco.loop.0
tco.case.arm.157.2554:
  %t2555 = getelementptr ptr, ptr %t5, i32 1
  %t2556 = load ptr, ptr %t2555
  %t2557 = getelementptr ptr, ptr %t5, i32 2
  %t2558 = load ptr, ptr %t2557
  %t2559 = getelementptr i8, ptr %t5, i64 -8
  %t2560 = load i32, ptr %t2559
  %t2561 = icmp eq i32 %t2560, 1
  br i1 %t2561, label %reuse.in_place.2562, label %reuse.copy.2563
reuse.in_place.2562:
  %t2565 = inttoptr i64 130 to ptr
  %t2566 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2565, ptr %t2566
  br label %reuse.join.2564
reuse.copy.2563:
  %t2567 = call ptr @__alloc(i64 24, i32 2)
  %t2568 = inttoptr i64 130 to ptr
  %t2569 = getelementptr ptr, ptr %t2567, i32 0
  store ptr %t2568, ptr %t2569
  call void @__inc_ref(ptr %t2556)
  %t2570 = getelementptr ptr, ptr %t2567, i32 1
  store ptr %t2556, ptr %t2570
  call void @__inc_ref(ptr %t2558)
  %t2571 = getelementptr ptr, ptr %t2567, i32 2
  store ptr %t2558, ptr %t2571
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2564
reuse.join.2564:
  %t2572 = phi ptr [ %t5, %reuse.in_place.2562 ], [ %t2567, %reuse.copy.2563 ]
  %t2573 = call ptr @__alloc(i64 16, i32 1)
  %t2574 = inttoptr i64 366 to ptr
  %t2575 = getelementptr ptr, ptr %t2573, i32 0
  store ptr %t2574, ptr %t2575
  call void @__inc_ref(ptr %t6)
  %t2576 = getelementptr ptr, ptr %t2573, i32 1
  store ptr %t6, ptr %t2576
  call void @__free_recursive(ptr %t6)
  store ptr %t2572, ptr %t3
  store ptr %t2573, ptr %t4
  br label %tco.loop.0
tco.case.arm.158.2577:
  %t2578 = getelementptr ptr, ptr %t5, i32 1
  %t2579 = load ptr, ptr %t2578
  %t2580 = getelementptr ptr, ptr %t5, i32 2
  %t2581 = load ptr, ptr %t2580
  %t2582 = getelementptr i8, ptr %t5, i64 -8
  %t2583 = load i32, ptr %t2582
  %t2584 = icmp eq i32 %t2583, 1
  br i1 %t2584, label %reuse.in_place.2585, label %reuse.copy.2586
reuse.in_place.2585:
  %t2588 = inttoptr i64 130 to ptr
  %t2589 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2588, ptr %t2589
  br label %reuse.join.2587
reuse.copy.2586:
  %t2590 = call ptr @__alloc(i64 24, i32 2)
  %t2591 = inttoptr i64 130 to ptr
  %t2592 = getelementptr ptr, ptr %t2590, i32 0
  store ptr %t2591, ptr %t2592
  call void @__inc_ref(ptr %t2579)
  %t2593 = getelementptr ptr, ptr %t2590, i32 1
  store ptr %t2579, ptr %t2593
  call void @__inc_ref(ptr %t2581)
  %t2594 = getelementptr ptr, ptr %t2590, i32 2
  store ptr %t2581, ptr %t2594
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2587
reuse.join.2587:
  %t2595 = phi ptr [ %t5, %reuse.in_place.2585 ], [ %t2590, %reuse.copy.2586 ]
  %t2596 = call ptr @__alloc(i64 16, i32 1)
  %t2597 = inttoptr i64 367 to ptr
  %t2598 = getelementptr ptr, ptr %t2596, i32 0
  store ptr %t2597, ptr %t2598
  call void @__inc_ref(ptr %t6)
  %t2599 = getelementptr ptr, ptr %t2596, i32 1
  store ptr %t6, ptr %t2599
  call void @__free_recursive(ptr %t6)
  store ptr %t2595, ptr %t3
  store ptr %t2596, ptr %t4
  br label %tco.loop.0
tco.case.arm.159.2600:
  %t2601 = getelementptr ptr, ptr %t5, i32 1
  %t2602 = load ptr, ptr %t2601
  %t2603 = getelementptr ptr, ptr %t5, i32 2
  %t2604 = load ptr, ptr %t2603
  %t2605 = getelementptr i8, ptr %t5, i64 -8
  %t2606 = load i32, ptr %t2605
  %t2607 = icmp eq i32 %t2606, 1
  br i1 %t2607, label %reuse.in_place.2608, label %reuse.copy.2609
reuse.in_place.2608:
  %t2611 = inttoptr i64 130 to ptr
  %t2612 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2611, ptr %t2612
  br label %reuse.join.2610
reuse.copy.2609:
  %t2613 = call ptr @__alloc(i64 24, i32 2)
  %t2614 = inttoptr i64 130 to ptr
  %t2615 = getelementptr ptr, ptr %t2613, i32 0
  store ptr %t2614, ptr %t2615
  call void @__inc_ref(ptr %t2602)
  %t2616 = getelementptr ptr, ptr %t2613, i32 1
  store ptr %t2602, ptr %t2616
  call void @__inc_ref(ptr %t2604)
  %t2617 = getelementptr ptr, ptr %t2613, i32 2
  store ptr %t2604, ptr %t2617
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2610
reuse.join.2610:
  %t2618 = phi ptr [ %t5, %reuse.in_place.2608 ], [ %t2613, %reuse.copy.2609 ]
  %t2619 = call ptr @__alloc(i64 16, i32 1)
  %t2620 = inttoptr i64 368 to ptr
  %t2621 = getelementptr ptr, ptr %t2619, i32 0
  store ptr %t2620, ptr %t2621
  call void @__inc_ref(ptr %t6)
  %t2622 = getelementptr ptr, ptr %t2619, i32 1
  store ptr %t6, ptr %t2622
  call void @__free_recursive(ptr %t6)
  store ptr %t2618, ptr %t3
  store ptr %t2619, ptr %t4
  br label %tco.loop.0
tco.case.arm.160.2623:
  %t2624 = getelementptr ptr, ptr %t5, i32 1
  %t2625 = load ptr, ptr %t2624
  %t2626 = getelementptr ptr, ptr %t5, i32 2
  %t2627 = load ptr, ptr %t2626
  %t2628 = getelementptr i8, ptr %t5, i64 -8
  %t2629 = load i32, ptr %t2628
  %t2630 = icmp eq i32 %t2629, 1
  br i1 %t2630, label %reuse.in_place.2631, label %reuse.copy.2632
reuse.in_place.2631:
  %t2634 = inttoptr i64 130 to ptr
  %t2635 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2634, ptr %t2635
  br label %reuse.join.2633
reuse.copy.2632:
  %t2636 = call ptr @__alloc(i64 24, i32 2)
  %t2637 = inttoptr i64 130 to ptr
  %t2638 = getelementptr ptr, ptr %t2636, i32 0
  store ptr %t2637, ptr %t2638
  call void @__inc_ref(ptr %t2625)
  %t2639 = getelementptr ptr, ptr %t2636, i32 1
  store ptr %t2625, ptr %t2639
  call void @__inc_ref(ptr %t2627)
  %t2640 = getelementptr ptr, ptr %t2636, i32 2
  store ptr %t2627, ptr %t2640
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2633
reuse.join.2633:
  %t2641 = phi ptr [ %t5, %reuse.in_place.2631 ], [ %t2636, %reuse.copy.2632 ]
  %t2642 = call ptr @__alloc(i64 16, i32 1)
  %t2643 = inttoptr i64 369 to ptr
  %t2644 = getelementptr ptr, ptr %t2642, i32 0
  store ptr %t2643, ptr %t2644
  call void @__inc_ref(ptr %t6)
  %t2645 = getelementptr ptr, ptr %t2642, i32 1
  store ptr %t6, ptr %t2645
  call void @__free_recursive(ptr %t6)
  store ptr %t2641, ptr %t3
  store ptr %t2642, ptr %t4
  br label %tco.loop.0
tco.case.arm.161.2646:
  %t2647 = getelementptr ptr, ptr %t5, i32 1
  %t2648 = load ptr, ptr %t2647
  %t2649 = getelementptr ptr, ptr %t5, i32 2
  %t2650 = load ptr, ptr %t2649
  %t2651 = getelementptr i8, ptr %t5, i64 -8
  %t2652 = load i32, ptr %t2651
  %t2653 = icmp eq i32 %t2652, 1
  br i1 %t2653, label %reuse.in_place.2654, label %reuse.copy.2655
reuse.in_place.2654:
  %t2657 = inttoptr i64 130 to ptr
  %t2658 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2657, ptr %t2658
  br label %reuse.join.2656
reuse.copy.2655:
  %t2659 = call ptr @__alloc(i64 24, i32 2)
  %t2660 = inttoptr i64 130 to ptr
  %t2661 = getelementptr ptr, ptr %t2659, i32 0
  store ptr %t2660, ptr %t2661
  call void @__inc_ref(ptr %t2648)
  %t2662 = getelementptr ptr, ptr %t2659, i32 1
  store ptr %t2648, ptr %t2662
  call void @__inc_ref(ptr %t2650)
  %t2663 = getelementptr ptr, ptr %t2659, i32 2
  store ptr %t2650, ptr %t2663
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2656
reuse.join.2656:
  %t2664 = phi ptr [ %t5, %reuse.in_place.2654 ], [ %t2659, %reuse.copy.2655 ]
  %t2665 = call ptr @__alloc(i64 16, i32 1)
  %t2666 = inttoptr i64 370 to ptr
  %t2667 = getelementptr ptr, ptr %t2665, i32 0
  store ptr %t2666, ptr %t2667
  call void @__inc_ref(ptr %t6)
  %t2668 = getelementptr ptr, ptr %t2665, i32 1
  store ptr %t6, ptr %t2668
  call void @__free_recursive(ptr %t6)
  store ptr %t2664, ptr %t3
  store ptr %t2665, ptr %t4
  br label %tco.loop.0
tco.case.arm.162.2669:
  %t2670 = getelementptr ptr, ptr %t5, i32 1
  %t2671 = load ptr, ptr %t2670
  %t2672 = getelementptr ptr, ptr %t5, i32 2
  %t2673 = load ptr, ptr %t2672
  %t2674 = getelementptr i8, ptr %t5, i64 -8
  %t2675 = load i32, ptr %t2674
  %t2676 = icmp eq i32 %t2675, 1
  br i1 %t2676, label %reuse.in_place.2677, label %reuse.copy.2678
reuse.in_place.2677:
  %t2680 = inttoptr i64 130 to ptr
  %t2681 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2680, ptr %t2681
  br label %reuse.join.2679
reuse.copy.2678:
  %t2682 = call ptr @__alloc(i64 24, i32 2)
  %t2683 = inttoptr i64 130 to ptr
  %t2684 = getelementptr ptr, ptr %t2682, i32 0
  store ptr %t2683, ptr %t2684
  call void @__inc_ref(ptr %t2671)
  %t2685 = getelementptr ptr, ptr %t2682, i32 1
  store ptr %t2671, ptr %t2685
  call void @__inc_ref(ptr %t2673)
  %t2686 = getelementptr ptr, ptr %t2682, i32 2
  store ptr %t2673, ptr %t2686
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2679
reuse.join.2679:
  %t2687 = phi ptr [ %t5, %reuse.in_place.2677 ], [ %t2682, %reuse.copy.2678 ]
  %t2688 = call ptr @__alloc(i64 16, i32 1)
  %t2689 = inttoptr i64 371 to ptr
  %t2690 = getelementptr ptr, ptr %t2688, i32 0
  store ptr %t2689, ptr %t2690
  call void @__inc_ref(ptr %t6)
  %t2691 = getelementptr ptr, ptr %t2688, i32 1
  store ptr %t6, ptr %t2691
  call void @__free_recursive(ptr %t6)
  store ptr %t2687, ptr %t3
  store ptr %t2688, ptr %t4
  br label %tco.loop.0
tco.case.arm.163.2692:
  %t2693 = getelementptr ptr, ptr %t5, i32 1
  %t2694 = load ptr, ptr %t2693
  %t2695 = getelementptr ptr, ptr %t5, i32 2
  %t2696 = load ptr, ptr %t2695
  %t2697 = getelementptr i8, ptr %t5, i64 -8
  %t2698 = load i32, ptr %t2697
  %t2699 = icmp eq i32 %t2698, 1
  br i1 %t2699, label %reuse.in_place.2700, label %reuse.copy.2701
reuse.in_place.2700:
  %t2703 = inttoptr i64 130 to ptr
  %t2704 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2703, ptr %t2704
  br label %reuse.join.2702
reuse.copy.2701:
  %t2705 = call ptr @__alloc(i64 24, i32 2)
  %t2706 = inttoptr i64 130 to ptr
  %t2707 = getelementptr ptr, ptr %t2705, i32 0
  store ptr %t2706, ptr %t2707
  call void @__inc_ref(ptr %t2694)
  %t2708 = getelementptr ptr, ptr %t2705, i32 1
  store ptr %t2694, ptr %t2708
  call void @__inc_ref(ptr %t2696)
  %t2709 = getelementptr ptr, ptr %t2705, i32 2
  store ptr %t2696, ptr %t2709
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2702
reuse.join.2702:
  %t2710 = phi ptr [ %t5, %reuse.in_place.2700 ], [ %t2705, %reuse.copy.2701 ]
  %t2711 = call ptr @__alloc(i64 16, i32 1)
  %t2712 = inttoptr i64 372 to ptr
  %t2713 = getelementptr ptr, ptr %t2711, i32 0
  store ptr %t2712, ptr %t2713
  call void @__inc_ref(ptr %t6)
  %t2714 = getelementptr ptr, ptr %t2711, i32 1
  store ptr %t6, ptr %t2714
  call void @__free_recursive(ptr %t6)
  store ptr %t2710, ptr %t3
  store ptr %t2711, ptr %t4
  br label %tco.loop.0
tco.case.arm.164.2715:
  %t2716 = getelementptr ptr, ptr %t5, i32 1
  %t2717 = load ptr, ptr %t2716
  %t2718 = getelementptr ptr, ptr %t5, i32 2
  %t2719 = load ptr, ptr %t2718
  %t2720 = getelementptr i8, ptr %t5, i64 -8
  %t2721 = load i32, ptr %t2720
  %t2722 = icmp eq i32 %t2721, 1
  br i1 %t2722, label %reuse.in_place.2723, label %reuse.copy.2724
reuse.in_place.2723:
  %t2726 = inttoptr i64 130 to ptr
  %t2727 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2726, ptr %t2727
  br label %reuse.join.2725
reuse.copy.2724:
  %t2728 = call ptr @__alloc(i64 24, i32 2)
  %t2729 = inttoptr i64 130 to ptr
  %t2730 = getelementptr ptr, ptr %t2728, i32 0
  store ptr %t2729, ptr %t2730
  call void @__inc_ref(ptr %t2717)
  %t2731 = getelementptr ptr, ptr %t2728, i32 1
  store ptr %t2717, ptr %t2731
  call void @__inc_ref(ptr %t2719)
  %t2732 = getelementptr ptr, ptr %t2728, i32 2
  store ptr %t2719, ptr %t2732
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2725
reuse.join.2725:
  %t2733 = phi ptr [ %t5, %reuse.in_place.2723 ], [ %t2728, %reuse.copy.2724 ]
  %t2734 = call ptr @__alloc(i64 16, i32 1)
  %t2735 = inttoptr i64 373 to ptr
  %t2736 = getelementptr ptr, ptr %t2734, i32 0
  store ptr %t2735, ptr %t2736
  call void @__inc_ref(ptr %t6)
  %t2737 = getelementptr ptr, ptr %t2734, i32 1
  store ptr %t6, ptr %t2737
  call void @__free_recursive(ptr %t6)
  store ptr %t2733, ptr %t3
  store ptr %t2734, ptr %t4
  br label %tco.loop.0
tco.case.arm.165.2738:
  %t2739 = getelementptr ptr, ptr %t5, i32 1
  %t2740 = load ptr, ptr %t2739
  %t2741 = getelementptr ptr, ptr %t5, i32 2
  %t2742 = load ptr, ptr %t2741
  %t2743 = getelementptr i8, ptr %t5, i64 -8
  %t2744 = load i32, ptr %t2743
  %t2745 = icmp eq i32 %t2744, 1
  br i1 %t2745, label %reuse.in_place.2746, label %reuse.copy.2747
reuse.in_place.2746:
  %t2749 = inttoptr i64 130 to ptr
  %t2750 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2749, ptr %t2750
  br label %reuse.join.2748
reuse.copy.2747:
  %t2751 = call ptr @__alloc(i64 24, i32 2)
  %t2752 = inttoptr i64 130 to ptr
  %t2753 = getelementptr ptr, ptr %t2751, i32 0
  store ptr %t2752, ptr %t2753
  call void @__inc_ref(ptr %t2740)
  %t2754 = getelementptr ptr, ptr %t2751, i32 1
  store ptr %t2740, ptr %t2754
  call void @__inc_ref(ptr %t2742)
  %t2755 = getelementptr ptr, ptr %t2751, i32 2
  store ptr %t2742, ptr %t2755
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2748
reuse.join.2748:
  %t2756 = phi ptr [ %t5, %reuse.in_place.2746 ], [ %t2751, %reuse.copy.2747 ]
  %t2757 = call ptr @__alloc(i64 16, i32 1)
  %t2758 = inttoptr i64 374 to ptr
  %t2759 = getelementptr ptr, ptr %t2757, i32 0
  store ptr %t2758, ptr %t2759
  call void @__inc_ref(ptr %t6)
  %t2760 = getelementptr ptr, ptr %t2757, i32 1
  store ptr %t6, ptr %t2760
  call void @__free_recursive(ptr %t6)
  store ptr %t2756, ptr %t3
  store ptr %t2757, ptr %t4
  br label %tco.loop.0
tco.case.arm.166.2761:
  %t2762 = getelementptr ptr, ptr %t5, i32 1
  %t2763 = load ptr, ptr %t2762
  %t2764 = getelementptr ptr, ptr %t5, i32 2
  %t2765 = load ptr, ptr %t2764
  %t2766 = getelementptr i8, ptr %t5, i64 -8
  %t2767 = load i32, ptr %t2766
  %t2768 = icmp eq i32 %t2767, 1
  br i1 %t2768, label %reuse.in_place.2769, label %reuse.copy.2770
reuse.in_place.2769:
  %t2772 = inttoptr i64 130 to ptr
  %t2773 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2772, ptr %t2773
  br label %reuse.join.2771
reuse.copy.2770:
  %t2774 = call ptr @__alloc(i64 24, i32 2)
  %t2775 = inttoptr i64 130 to ptr
  %t2776 = getelementptr ptr, ptr %t2774, i32 0
  store ptr %t2775, ptr %t2776
  call void @__inc_ref(ptr %t2763)
  %t2777 = getelementptr ptr, ptr %t2774, i32 1
  store ptr %t2763, ptr %t2777
  call void @__inc_ref(ptr %t2765)
  %t2778 = getelementptr ptr, ptr %t2774, i32 2
  store ptr %t2765, ptr %t2778
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2771
reuse.join.2771:
  %t2779 = phi ptr [ %t5, %reuse.in_place.2769 ], [ %t2774, %reuse.copy.2770 ]
  %t2780 = call ptr @__alloc(i64 16, i32 1)
  %t2781 = inttoptr i64 375 to ptr
  %t2782 = getelementptr ptr, ptr %t2780, i32 0
  store ptr %t2781, ptr %t2782
  call void @__inc_ref(ptr %t6)
  %t2783 = getelementptr ptr, ptr %t2780, i32 1
  store ptr %t6, ptr %t2783
  call void @__free_recursive(ptr %t6)
  store ptr %t2779, ptr %t3
  store ptr %t2780, ptr %t4
  br label %tco.loop.0
tco.case.arm.167.2784:
  %t2785 = getelementptr ptr, ptr %t5, i32 1
  %t2786 = load ptr, ptr %t2785
  %t2787 = getelementptr ptr, ptr %t5, i32 2
  %t2788 = load ptr, ptr %t2787
  %t2789 = getelementptr i8, ptr %t5, i64 -8
  %t2790 = load i32, ptr %t2789
  %t2791 = icmp eq i32 %t2790, 1
  br i1 %t2791, label %reuse.in_place.2792, label %reuse.copy.2793
reuse.in_place.2792:
  %t2795 = inttoptr i64 130 to ptr
  %t2796 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2795, ptr %t2796
  br label %reuse.join.2794
reuse.copy.2793:
  %t2797 = call ptr @__alloc(i64 24, i32 2)
  %t2798 = inttoptr i64 130 to ptr
  %t2799 = getelementptr ptr, ptr %t2797, i32 0
  store ptr %t2798, ptr %t2799
  call void @__inc_ref(ptr %t2786)
  %t2800 = getelementptr ptr, ptr %t2797, i32 1
  store ptr %t2786, ptr %t2800
  call void @__inc_ref(ptr %t2788)
  %t2801 = getelementptr ptr, ptr %t2797, i32 2
  store ptr %t2788, ptr %t2801
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2794
reuse.join.2794:
  %t2802 = phi ptr [ %t5, %reuse.in_place.2792 ], [ %t2797, %reuse.copy.2793 ]
  %t2803 = call ptr @__alloc(i64 16, i32 1)
  %t2804 = inttoptr i64 376 to ptr
  %t2805 = getelementptr ptr, ptr %t2803, i32 0
  store ptr %t2804, ptr %t2805
  call void @__inc_ref(ptr %t6)
  %t2806 = getelementptr ptr, ptr %t2803, i32 1
  store ptr %t6, ptr %t2806
  call void @__free_recursive(ptr %t6)
  store ptr %t2802, ptr %t3
  store ptr %t2803, ptr %t4
  br label %tco.loop.0
tco.case.arm.168.2807:
  %t2808 = getelementptr ptr, ptr %t5, i32 1
  %t2809 = load ptr, ptr %t2808
  %t2810 = getelementptr ptr, ptr %t5, i32 2
  %t2811 = load ptr, ptr %t2810
  %t2812 = getelementptr i8, ptr %t5, i64 -8
  %t2813 = load i32, ptr %t2812
  %t2814 = icmp eq i32 %t2813, 1
  br i1 %t2814, label %reuse.in_place.2815, label %reuse.copy.2816
reuse.in_place.2815:
  %t2818 = inttoptr i64 130 to ptr
  %t2819 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2818, ptr %t2819
  br label %reuse.join.2817
reuse.copy.2816:
  %t2820 = call ptr @__alloc(i64 24, i32 2)
  %t2821 = inttoptr i64 130 to ptr
  %t2822 = getelementptr ptr, ptr %t2820, i32 0
  store ptr %t2821, ptr %t2822
  call void @__inc_ref(ptr %t2809)
  %t2823 = getelementptr ptr, ptr %t2820, i32 1
  store ptr %t2809, ptr %t2823
  call void @__inc_ref(ptr %t2811)
  %t2824 = getelementptr ptr, ptr %t2820, i32 2
  store ptr %t2811, ptr %t2824
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2817
reuse.join.2817:
  %t2825 = phi ptr [ %t5, %reuse.in_place.2815 ], [ %t2820, %reuse.copy.2816 ]
  %t2826 = call ptr @__alloc(i64 16, i32 1)
  %t2827 = inttoptr i64 377 to ptr
  %t2828 = getelementptr ptr, ptr %t2826, i32 0
  store ptr %t2827, ptr %t2828
  call void @__inc_ref(ptr %t6)
  %t2829 = getelementptr ptr, ptr %t2826, i32 1
  store ptr %t6, ptr %t2829
  call void @__free_recursive(ptr %t6)
  store ptr %t2825, ptr %t3
  store ptr %t2826, ptr %t4
  br label %tco.loop.0
tco.case.arm.169.2830:
  %t2831 = getelementptr ptr, ptr %t5, i32 1
  %t2832 = load ptr, ptr %t2831
  %t2833 = getelementptr ptr, ptr %t5, i32 2
  %t2834 = load ptr, ptr %t2833
  %t2835 = getelementptr i8, ptr %t5, i64 -8
  %t2836 = load i32, ptr %t2835
  %t2837 = icmp eq i32 %t2836, 1
  br i1 %t2837, label %reuse.in_place.2838, label %reuse.copy.2839
reuse.in_place.2838:
  %t2841 = inttoptr i64 130 to ptr
  %t2842 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2841, ptr %t2842
  br label %reuse.join.2840
reuse.copy.2839:
  %t2843 = call ptr @__alloc(i64 24, i32 2)
  %t2844 = inttoptr i64 130 to ptr
  %t2845 = getelementptr ptr, ptr %t2843, i32 0
  store ptr %t2844, ptr %t2845
  call void @__inc_ref(ptr %t2832)
  %t2846 = getelementptr ptr, ptr %t2843, i32 1
  store ptr %t2832, ptr %t2846
  call void @__inc_ref(ptr %t2834)
  %t2847 = getelementptr ptr, ptr %t2843, i32 2
  store ptr %t2834, ptr %t2847
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2840
reuse.join.2840:
  %t2848 = phi ptr [ %t5, %reuse.in_place.2838 ], [ %t2843, %reuse.copy.2839 ]
  %t2849 = call ptr @__alloc(i64 16, i32 1)
  %t2850 = inttoptr i64 378 to ptr
  %t2851 = getelementptr ptr, ptr %t2849, i32 0
  store ptr %t2850, ptr %t2851
  call void @__inc_ref(ptr %t6)
  %t2852 = getelementptr ptr, ptr %t2849, i32 1
  store ptr %t6, ptr %t2852
  call void @__free_recursive(ptr %t6)
  store ptr %t2848, ptr %t3
  store ptr %t2849, ptr %t4
  br label %tco.loop.0
tco.case.arm.170.2853:
  %t2854 = getelementptr ptr, ptr %t5, i32 1
  %t2855 = load ptr, ptr %t2854
  %t2856 = getelementptr ptr, ptr %t5, i32 2
  %t2857 = load ptr, ptr %t2856
  %t2858 = getelementptr i8, ptr %t5, i64 -8
  %t2859 = load i32, ptr %t2858
  %t2860 = icmp eq i32 %t2859, 1
  br i1 %t2860, label %reuse.in_place.2861, label %reuse.copy.2862
reuse.in_place.2861:
  %t2864 = inttoptr i64 130 to ptr
  %t2865 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2864, ptr %t2865
  br label %reuse.join.2863
reuse.copy.2862:
  %t2866 = call ptr @__alloc(i64 24, i32 2)
  %t2867 = inttoptr i64 130 to ptr
  %t2868 = getelementptr ptr, ptr %t2866, i32 0
  store ptr %t2867, ptr %t2868
  call void @__inc_ref(ptr %t2855)
  %t2869 = getelementptr ptr, ptr %t2866, i32 1
  store ptr %t2855, ptr %t2869
  call void @__inc_ref(ptr %t2857)
  %t2870 = getelementptr ptr, ptr %t2866, i32 2
  store ptr %t2857, ptr %t2870
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2863
reuse.join.2863:
  %t2871 = phi ptr [ %t5, %reuse.in_place.2861 ], [ %t2866, %reuse.copy.2862 ]
  %t2872 = call ptr @__alloc(i64 16, i32 1)
  %t2873 = inttoptr i64 379 to ptr
  %t2874 = getelementptr ptr, ptr %t2872, i32 0
  store ptr %t2873, ptr %t2874
  call void @__inc_ref(ptr %t6)
  %t2875 = getelementptr ptr, ptr %t2872, i32 1
  store ptr %t6, ptr %t2875
  call void @__free_recursive(ptr %t6)
  store ptr %t2871, ptr %t3
  store ptr %t2872, ptr %t4
  br label %tco.loop.0
tco.case.arm.171.2876:
  %t2877 = getelementptr ptr, ptr %t5, i32 1
  %t2878 = load ptr, ptr %t2877
  %t2879 = getelementptr ptr, ptr %t5, i32 2
  %t2880 = load ptr, ptr %t2879
  %t2881 = getelementptr i8, ptr %t5, i64 -8
  %t2882 = load i32, ptr %t2881
  %t2883 = icmp eq i32 %t2882, 1
  br i1 %t2883, label %reuse.in_place.2884, label %reuse.copy.2885
reuse.in_place.2884:
  %t2887 = inttoptr i64 130 to ptr
  %t2888 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2887, ptr %t2888
  br label %reuse.join.2886
reuse.copy.2885:
  %t2889 = call ptr @__alloc(i64 24, i32 2)
  %t2890 = inttoptr i64 130 to ptr
  %t2891 = getelementptr ptr, ptr %t2889, i32 0
  store ptr %t2890, ptr %t2891
  call void @__inc_ref(ptr %t2878)
  %t2892 = getelementptr ptr, ptr %t2889, i32 1
  store ptr %t2878, ptr %t2892
  call void @__inc_ref(ptr %t2880)
  %t2893 = getelementptr ptr, ptr %t2889, i32 2
  store ptr %t2880, ptr %t2893
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2886
reuse.join.2886:
  %t2894 = phi ptr [ %t5, %reuse.in_place.2884 ], [ %t2889, %reuse.copy.2885 ]
  %t2895 = call ptr @__alloc(i64 16, i32 1)
  %t2896 = inttoptr i64 380 to ptr
  %t2897 = getelementptr ptr, ptr %t2895, i32 0
  store ptr %t2896, ptr %t2897
  call void @__inc_ref(ptr %t6)
  %t2898 = getelementptr ptr, ptr %t2895, i32 1
  store ptr %t6, ptr %t2898
  call void @__free_recursive(ptr %t6)
  store ptr %t2894, ptr %t3
  store ptr %t2895, ptr %t4
  br label %tco.loop.0
tco.case.arm.172.2899:
  %t2900 = getelementptr ptr, ptr %t5, i32 1
  %t2901 = load ptr, ptr %t2900
  %t2902 = getelementptr ptr, ptr %t5, i32 2
  %t2903 = load ptr, ptr %t2902
  %t2904 = getelementptr i8, ptr %t5, i64 -8
  %t2905 = load i32, ptr %t2904
  %t2906 = icmp eq i32 %t2905, 1
  br i1 %t2906, label %reuse.in_place.2907, label %reuse.copy.2908
reuse.in_place.2907:
  %t2910 = inttoptr i64 130 to ptr
  %t2911 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2910, ptr %t2911
  br label %reuse.join.2909
reuse.copy.2908:
  %t2912 = call ptr @__alloc(i64 24, i32 2)
  %t2913 = inttoptr i64 130 to ptr
  %t2914 = getelementptr ptr, ptr %t2912, i32 0
  store ptr %t2913, ptr %t2914
  call void @__inc_ref(ptr %t2901)
  %t2915 = getelementptr ptr, ptr %t2912, i32 1
  store ptr %t2901, ptr %t2915
  call void @__inc_ref(ptr %t2903)
  %t2916 = getelementptr ptr, ptr %t2912, i32 2
  store ptr %t2903, ptr %t2916
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2909
reuse.join.2909:
  %t2917 = phi ptr [ %t5, %reuse.in_place.2907 ], [ %t2912, %reuse.copy.2908 ]
  %t2918 = call ptr @__alloc(i64 16, i32 1)
  %t2919 = inttoptr i64 381 to ptr
  %t2920 = getelementptr ptr, ptr %t2918, i32 0
  store ptr %t2919, ptr %t2920
  call void @__inc_ref(ptr %t6)
  %t2921 = getelementptr ptr, ptr %t2918, i32 1
  store ptr %t6, ptr %t2921
  call void @__free_recursive(ptr %t6)
  store ptr %t2917, ptr %t3
  store ptr %t2918, ptr %t4
  br label %tco.loop.0
tco.case.arm.173.2922:
  %t2923 = getelementptr ptr, ptr %t5, i32 1
  %t2924 = load ptr, ptr %t2923
  %t2925 = getelementptr ptr, ptr %t5, i32 2
  %t2926 = load ptr, ptr %t2925
  %t2927 = getelementptr i8, ptr %t5, i64 -8
  %t2928 = load i32, ptr %t2927
  %t2929 = icmp eq i32 %t2928, 1
  br i1 %t2929, label %reuse.in_place.2930, label %reuse.copy.2931
reuse.in_place.2930:
  %t2933 = inttoptr i64 130 to ptr
  %t2934 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2933, ptr %t2934
  br label %reuse.join.2932
reuse.copy.2931:
  %t2935 = call ptr @__alloc(i64 24, i32 2)
  %t2936 = inttoptr i64 130 to ptr
  %t2937 = getelementptr ptr, ptr %t2935, i32 0
  store ptr %t2936, ptr %t2937
  call void @__inc_ref(ptr %t2924)
  %t2938 = getelementptr ptr, ptr %t2935, i32 1
  store ptr %t2924, ptr %t2938
  call void @__inc_ref(ptr %t2926)
  %t2939 = getelementptr ptr, ptr %t2935, i32 2
  store ptr %t2926, ptr %t2939
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2932
reuse.join.2932:
  %t2940 = phi ptr [ %t5, %reuse.in_place.2930 ], [ %t2935, %reuse.copy.2931 ]
  %t2941 = call ptr @__alloc(i64 16, i32 1)
  %t2942 = inttoptr i64 382 to ptr
  %t2943 = getelementptr ptr, ptr %t2941, i32 0
  store ptr %t2942, ptr %t2943
  call void @__inc_ref(ptr %t6)
  %t2944 = getelementptr ptr, ptr %t2941, i32 1
  store ptr %t6, ptr %t2944
  call void @__free_recursive(ptr %t6)
  store ptr %t2940, ptr %t3
  store ptr %t2941, ptr %t4
  br label %tco.loop.0
tco.case.arm.174.2945:
  %t2946 = getelementptr ptr, ptr %t5, i32 1
  %t2947 = load ptr, ptr %t2946
  %t2948 = getelementptr ptr, ptr %t5, i32 2
  %t2949 = load ptr, ptr %t2948
  %t2950 = getelementptr i8, ptr %t5, i64 -8
  %t2951 = load i32, ptr %t2950
  %t2952 = icmp eq i32 %t2951, 1
  br i1 %t2952, label %reuse.in_place.2953, label %reuse.copy.2954
reuse.in_place.2953:
  %t2956 = inttoptr i64 130 to ptr
  %t2957 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2956, ptr %t2957
  br label %reuse.join.2955
reuse.copy.2954:
  %t2958 = call ptr @__alloc(i64 24, i32 2)
  %t2959 = inttoptr i64 130 to ptr
  %t2960 = getelementptr ptr, ptr %t2958, i32 0
  store ptr %t2959, ptr %t2960
  call void @__inc_ref(ptr %t2947)
  %t2961 = getelementptr ptr, ptr %t2958, i32 1
  store ptr %t2947, ptr %t2961
  call void @__inc_ref(ptr %t2949)
  %t2962 = getelementptr ptr, ptr %t2958, i32 2
  store ptr %t2949, ptr %t2962
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2955
reuse.join.2955:
  %t2963 = phi ptr [ %t5, %reuse.in_place.2953 ], [ %t2958, %reuse.copy.2954 ]
  %t2964 = call ptr @__alloc(i64 16, i32 1)
  %t2965 = inttoptr i64 383 to ptr
  %t2966 = getelementptr ptr, ptr %t2964, i32 0
  store ptr %t2965, ptr %t2966
  call void @__inc_ref(ptr %t6)
  %t2967 = getelementptr ptr, ptr %t2964, i32 1
  store ptr %t6, ptr %t2967
  call void @__free_recursive(ptr %t6)
  store ptr %t2963, ptr %t3
  store ptr %t2964, ptr %t4
  br label %tco.loop.0
tco.case.arm.175.2968:
  %t2969 = getelementptr ptr, ptr %t5, i32 1
  %t2970 = load ptr, ptr %t2969
  %t2971 = getelementptr ptr, ptr %t5, i32 2
  %t2972 = load ptr, ptr %t2971
  %t2973 = getelementptr i8, ptr %t5, i64 -8
  %t2974 = load i32, ptr %t2973
  %t2975 = icmp eq i32 %t2974, 1
  br i1 %t2975, label %reuse.in_place.2976, label %reuse.copy.2977
reuse.in_place.2976:
  %t2979 = inttoptr i64 130 to ptr
  %t2980 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2979, ptr %t2980
  br label %reuse.join.2978
reuse.copy.2977:
  %t2981 = call ptr @__alloc(i64 24, i32 2)
  %t2982 = inttoptr i64 130 to ptr
  %t2983 = getelementptr ptr, ptr %t2981, i32 0
  store ptr %t2982, ptr %t2983
  call void @__inc_ref(ptr %t2970)
  %t2984 = getelementptr ptr, ptr %t2981, i32 1
  store ptr %t2970, ptr %t2984
  call void @__inc_ref(ptr %t2972)
  %t2985 = getelementptr ptr, ptr %t2981, i32 2
  store ptr %t2972, ptr %t2985
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2978
reuse.join.2978:
  %t2986 = phi ptr [ %t5, %reuse.in_place.2976 ], [ %t2981, %reuse.copy.2977 ]
  %t2987 = call ptr @__alloc(i64 16, i32 1)
  %t2988 = inttoptr i64 384 to ptr
  %t2989 = getelementptr ptr, ptr %t2987, i32 0
  store ptr %t2988, ptr %t2989
  call void @__inc_ref(ptr %t6)
  %t2990 = getelementptr ptr, ptr %t2987, i32 1
  store ptr %t6, ptr %t2990
  call void @__free_recursive(ptr %t6)
  store ptr %t2986, ptr %t3
  store ptr %t2987, ptr %t4
  br label %tco.loop.0
tco.case.arm.176.2991:
  %t2992 = getelementptr ptr, ptr %t5, i32 1
  %t2993 = load ptr, ptr %t2992
  %t2994 = getelementptr ptr, ptr %t5, i32 2
  %t2995 = load ptr, ptr %t2994
  %t2996 = getelementptr i8, ptr %t5, i64 -8
  %t2997 = load i32, ptr %t2996
  %t2998 = icmp eq i32 %t2997, 1
  br i1 %t2998, label %reuse.in_place.2999, label %reuse.copy.3000
reuse.in_place.2999:
  %t3002 = inttoptr i64 130 to ptr
  %t3003 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3002, ptr %t3003
  br label %reuse.join.3001
reuse.copy.3000:
  %t3004 = call ptr @__alloc(i64 24, i32 2)
  %t3005 = inttoptr i64 130 to ptr
  %t3006 = getelementptr ptr, ptr %t3004, i32 0
  store ptr %t3005, ptr %t3006
  call void @__inc_ref(ptr %t2993)
  %t3007 = getelementptr ptr, ptr %t3004, i32 1
  store ptr %t2993, ptr %t3007
  call void @__inc_ref(ptr %t2995)
  %t3008 = getelementptr ptr, ptr %t3004, i32 2
  store ptr %t2995, ptr %t3008
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3001
reuse.join.3001:
  %t3009 = phi ptr [ %t5, %reuse.in_place.2999 ], [ %t3004, %reuse.copy.3000 ]
  %t3010 = call ptr @__alloc(i64 16, i32 1)
  %t3011 = inttoptr i64 385 to ptr
  %t3012 = getelementptr ptr, ptr %t3010, i32 0
  store ptr %t3011, ptr %t3012
  call void @__inc_ref(ptr %t6)
  %t3013 = getelementptr ptr, ptr %t3010, i32 1
  store ptr %t6, ptr %t3013
  call void @__free_recursive(ptr %t6)
  store ptr %t3009, ptr %t3
  store ptr %t3010, ptr %t4
  br label %tco.loop.0
tco.case.arm.177.3014:
  %t3015 = getelementptr ptr, ptr %t5, i32 1
  %t3016 = load ptr, ptr %t3015
  %t3017 = getelementptr ptr, ptr %t5, i32 2
  %t3018 = load ptr, ptr %t3017
  %t3019 = getelementptr i8, ptr %t5, i64 -8
  %t3020 = load i32, ptr %t3019
  %t3021 = icmp eq i32 %t3020, 1
  br i1 %t3021, label %reuse.in_place.3022, label %reuse.copy.3023
reuse.in_place.3022:
  %t3025 = inttoptr i64 130 to ptr
  %t3026 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3025, ptr %t3026
  br label %reuse.join.3024
reuse.copy.3023:
  %t3027 = call ptr @__alloc(i64 24, i32 2)
  %t3028 = inttoptr i64 130 to ptr
  %t3029 = getelementptr ptr, ptr %t3027, i32 0
  store ptr %t3028, ptr %t3029
  call void @__inc_ref(ptr %t3016)
  %t3030 = getelementptr ptr, ptr %t3027, i32 1
  store ptr %t3016, ptr %t3030
  call void @__inc_ref(ptr %t3018)
  %t3031 = getelementptr ptr, ptr %t3027, i32 2
  store ptr %t3018, ptr %t3031
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3024
reuse.join.3024:
  %t3032 = phi ptr [ %t5, %reuse.in_place.3022 ], [ %t3027, %reuse.copy.3023 ]
  %t3033 = call ptr @__alloc(i64 16, i32 1)
  %t3034 = inttoptr i64 386 to ptr
  %t3035 = getelementptr ptr, ptr %t3033, i32 0
  store ptr %t3034, ptr %t3035
  call void @__inc_ref(ptr %t6)
  %t3036 = getelementptr ptr, ptr %t3033, i32 1
  store ptr %t6, ptr %t3036
  call void @__free_recursive(ptr %t6)
  store ptr %t3032, ptr %t3
  store ptr %t3033, ptr %t4
  br label %tco.loop.0
tco.case.arm.178.3037:
  %t3038 = getelementptr ptr, ptr %t5, i32 1
  %t3039 = load ptr, ptr %t3038
  %t3040 = getelementptr ptr, ptr %t5, i32 2
  %t3041 = load ptr, ptr %t3040
  %t3042 = getelementptr i8, ptr %t5, i64 -8
  %t3043 = load i32, ptr %t3042
  %t3044 = icmp eq i32 %t3043, 1
  br i1 %t3044, label %reuse.in_place.3045, label %reuse.copy.3046
reuse.in_place.3045:
  %t3048 = inttoptr i64 130 to ptr
  %t3049 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3048, ptr %t3049
  br label %reuse.join.3047
reuse.copy.3046:
  %t3050 = call ptr @__alloc(i64 24, i32 2)
  %t3051 = inttoptr i64 130 to ptr
  %t3052 = getelementptr ptr, ptr %t3050, i32 0
  store ptr %t3051, ptr %t3052
  call void @__inc_ref(ptr %t3039)
  %t3053 = getelementptr ptr, ptr %t3050, i32 1
  store ptr %t3039, ptr %t3053
  call void @__inc_ref(ptr %t3041)
  %t3054 = getelementptr ptr, ptr %t3050, i32 2
  store ptr %t3041, ptr %t3054
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3047
reuse.join.3047:
  %t3055 = phi ptr [ %t5, %reuse.in_place.3045 ], [ %t3050, %reuse.copy.3046 ]
  %t3056 = call ptr @__alloc(i64 16, i32 1)
  %t3057 = inttoptr i64 387 to ptr
  %t3058 = getelementptr ptr, ptr %t3056, i32 0
  store ptr %t3057, ptr %t3058
  call void @__inc_ref(ptr %t6)
  %t3059 = getelementptr ptr, ptr %t3056, i32 1
  store ptr %t6, ptr %t3059
  call void @__free_recursive(ptr %t6)
  store ptr %t3055, ptr %t3
  store ptr %t3056, ptr %t4
  br label %tco.loop.0
tco.case.arm.179.3060:
  %t3061 = getelementptr ptr, ptr %t5, i32 1
  %t3062 = load ptr, ptr %t3061
  %t3063 = getelementptr ptr, ptr %t5, i32 2
  %t3064 = load ptr, ptr %t3063
  %t3065 = getelementptr i8, ptr %t5, i64 -8
  %t3066 = load i32, ptr %t3065
  %t3067 = icmp eq i32 %t3066, 1
  br i1 %t3067, label %reuse.in_place.3068, label %reuse.copy.3069
reuse.in_place.3068:
  %t3071 = inttoptr i64 130 to ptr
  %t3072 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3071, ptr %t3072
  br label %reuse.join.3070
reuse.copy.3069:
  %t3073 = call ptr @__alloc(i64 24, i32 2)
  %t3074 = inttoptr i64 130 to ptr
  %t3075 = getelementptr ptr, ptr %t3073, i32 0
  store ptr %t3074, ptr %t3075
  call void @__inc_ref(ptr %t3062)
  %t3076 = getelementptr ptr, ptr %t3073, i32 1
  store ptr %t3062, ptr %t3076
  call void @__inc_ref(ptr %t3064)
  %t3077 = getelementptr ptr, ptr %t3073, i32 2
  store ptr %t3064, ptr %t3077
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3070
reuse.join.3070:
  %t3078 = phi ptr [ %t5, %reuse.in_place.3068 ], [ %t3073, %reuse.copy.3069 ]
  %t3079 = call ptr @__alloc(i64 16, i32 1)
  %t3080 = inttoptr i64 388 to ptr
  %t3081 = getelementptr ptr, ptr %t3079, i32 0
  store ptr %t3080, ptr %t3081
  call void @__inc_ref(ptr %t6)
  %t3082 = getelementptr ptr, ptr %t3079, i32 1
  store ptr %t6, ptr %t3082
  call void @__free_recursive(ptr %t6)
  store ptr %t3078, ptr %t3
  store ptr %t3079, ptr %t4
  br label %tco.loop.0
tco.case.arm.180.3083:
  %t3084 = getelementptr ptr, ptr %t5, i32 1
  %t3085 = load ptr, ptr %t3084
  %t3086 = getelementptr ptr, ptr %t5, i32 2
  %t3087 = load ptr, ptr %t3086
  %t3088 = getelementptr i8, ptr %t5, i64 -8
  %t3089 = load i32, ptr %t3088
  %t3090 = icmp eq i32 %t3089, 1
  br i1 %t3090, label %reuse.in_place.3091, label %reuse.copy.3092
reuse.in_place.3091:
  %t3094 = inttoptr i64 130 to ptr
  %t3095 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3094, ptr %t3095
  br label %reuse.join.3093
reuse.copy.3092:
  %t3096 = call ptr @__alloc(i64 24, i32 2)
  %t3097 = inttoptr i64 130 to ptr
  %t3098 = getelementptr ptr, ptr %t3096, i32 0
  store ptr %t3097, ptr %t3098
  call void @__inc_ref(ptr %t3085)
  %t3099 = getelementptr ptr, ptr %t3096, i32 1
  store ptr %t3085, ptr %t3099
  call void @__inc_ref(ptr %t3087)
  %t3100 = getelementptr ptr, ptr %t3096, i32 2
  store ptr %t3087, ptr %t3100
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3093
reuse.join.3093:
  %t3101 = phi ptr [ %t5, %reuse.in_place.3091 ], [ %t3096, %reuse.copy.3092 ]
  %t3102 = call ptr @__alloc(i64 16, i32 1)
  %t3103 = inttoptr i64 389 to ptr
  %t3104 = getelementptr ptr, ptr %t3102, i32 0
  store ptr %t3103, ptr %t3104
  call void @__inc_ref(ptr %t6)
  %t3105 = getelementptr ptr, ptr %t3102, i32 1
  store ptr %t6, ptr %t3105
  call void @__free_recursive(ptr %t6)
  store ptr %t3101, ptr %t3
  store ptr %t3102, ptr %t4
  br label %tco.loop.0
tco.case.arm.181.3106:
  %t3107 = getelementptr ptr, ptr %t5, i32 1
  %t3108 = load ptr, ptr %t3107
  %t3109 = getelementptr ptr, ptr %t5, i32 2
  %t3110 = load ptr, ptr %t3109
  %t3111 = getelementptr i8, ptr %t5, i64 -8
  %t3112 = load i32, ptr %t3111
  %t3113 = icmp eq i32 %t3112, 1
  br i1 %t3113, label %reuse.in_place.3114, label %reuse.copy.3115
reuse.in_place.3114:
  %t3117 = inttoptr i64 130 to ptr
  %t3118 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3117, ptr %t3118
  br label %reuse.join.3116
reuse.copy.3115:
  %t3119 = call ptr @__alloc(i64 24, i32 2)
  %t3120 = inttoptr i64 130 to ptr
  %t3121 = getelementptr ptr, ptr %t3119, i32 0
  store ptr %t3120, ptr %t3121
  call void @__inc_ref(ptr %t3108)
  %t3122 = getelementptr ptr, ptr %t3119, i32 1
  store ptr %t3108, ptr %t3122
  call void @__inc_ref(ptr %t3110)
  %t3123 = getelementptr ptr, ptr %t3119, i32 2
  store ptr %t3110, ptr %t3123
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3116
reuse.join.3116:
  %t3124 = phi ptr [ %t5, %reuse.in_place.3114 ], [ %t3119, %reuse.copy.3115 ]
  %t3125 = call ptr @__alloc(i64 16, i32 1)
  %t3126 = inttoptr i64 390 to ptr
  %t3127 = getelementptr ptr, ptr %t3125, i32 0
  store ptr %t3126, ptr %t3127
  call void @__inc_ref(ptr %t6)
  %t3128 = getelementptr ptr, ptr %t3125, i32 1
  store ptr %t6, ptr %t3128
  call void @__free_recursive(ptr %t6)
  store ptr %t3124, ptr %t3
  store ptr %t3125, ptr %t4
  br label %tco.loop.0
tco.case.arm.182.3129:
  %t3130 = getelementptr ptr, ptr %t5, i32 1
  %t3131 = load ptr, ptr %t3130
  %t3132 = getelementptr ptr, ptr %t5, i32 2
  %t3133 = load ptr, ptr %t3132
  %t3134 = getelementptr i8, ptr %t5, i64 -8
  %t3135 = load i32, ptr %t3134
  %t3136 = icmp eq i32 %t3135, 1
  br i1 %t3136, label %reuse.in_place.3137, label %reuse.copy.3138
reuse.in_place.3137:
  %t3140 = inttoptr i64 130 to ptr
  %t3141 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3140, ptr %t3141
  br label %reuse.join.3139
reuse.copy.3138:
  %t3142 = call ptr @__alloc(i64 24, i32 2)
  %t3143 = inttoptr i64 130 to ptr
  %t3144 = getelementptr ptr, ptr %t3142, i32 0
  store ptr %t3143, ptr %t3144
  call void @__inc_ref(ptr %t3131)
  %t3145 = getelementptr ptr, ptr %t3142, i32 1
  store ptr %t3131, ptr %t3145
  call void @__inc_ref(ptr %t3133)
  %t3146 = getelementptr ptr, ptr %t3142, i32 2
  store ptr %t3133, ptr %t3146
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3139
reuse.join.3139:
  %t3147 = phi ptr [ %t5, %reuse.in_place.3137 ], [ %t3142, %reuse.copy.3138 ]
  %t3148 = call ptr @__alloc(i64 16, i32 1)
  %t3149 = inttoptr i64 391 to ptr
  %t3150 = getelementptr ptr, ptr %t3148, i32 0
  store ptr %t3149, ptr %t3150
  call void @__inc_ref(ptr %t6)
  %t3151 = getelementptr ptr, ptr %t3148, i32 1
  store ptr %t6, ptr %t3151
  call void @__free_recursive(ptr %t6)
  store ptr %t3147, ptr %t3
  store ptr %t3148, ptr %t4
  br label %tco.loop.0
tco.case.arm.183.3152:
  %t3153 = getelementptr ptr, ptr %t5, i32 1
  %t3154 = load ptr, ptr %t3153
  %t3155 = getelementptr ptr, ptr %t5, i32 2
  %t3156 = load ptr, ptr %t3155
  %t3157 = getelementptr i8, ptr %t5, i64 -8
  %t3158 = load i32, ptr %t3157
  %t3159 = icmp eq i32 %t3158, 1
  br i1 %t3159, label %reuse.in_place.3160, label %reuse.copy.3161
reuse.in_place.3160:
  %t3163 = inttoptr i64 130 to ptr
  %t3164 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3163, ptr %t3164
  br label %reuse.join.3162
reuse.copy.3161:
  %t3165 = call ptr @__alloc(i64 24, i32 2)
  %t3166 = inttoptr i64 130 to ptr
  %t3167 = getelementptr ptr, ptr %t3165, i32 0
  store ptr %t3166, ptr %t3167
  call void @__inc_ref(ptr %t3154)
  %t3168 = getelementptr ptr, ptr %t3165, i32 1
  store ptr %t3154, ptr %t3168
  call void @__inc_ref(ptr %t3156)
  %t3169 = getelementptr ptr, ptr %t3165, i32 2
  store ptr %t3156, ptr %t3169
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3162
reuse.join.3162:
  %t3170 = phi ptr [ %t5, %reuse.in_place.3160 ], [ %t3165, %reuse.copy.3161 ]
  %t3171 = call ptr @__alloc(i64 16, i32 1)
  %t3172 = inttoptr i64 392 to ptr
  %t3173 = getelementptr ptr, ptr %t3171, i32 0
  store ptr %t3172, ptr %t3173
  call void @__inc_ref(ptr %t6)
  %t3174 = getelementptr ptr, ptr %t3171, i32 1
  store ptr %t6, ptr %t3174
  call void @__free_recursive(ptr %t6)
  store ptr %t3170, ptr %t3
  store ptr %t3171, ptr %t4
  br label %tco.loop.0
tco.case.arm.184.3175:
  %t3176 = getelementptr ptr, ptr %t5, i32 1
  %t3177 = load ptr, ptr %t3176
  %t3178 = getelementptr ptr, ptr %t5, i32 2
  %t3179 = load ptr, ptr %t3178
  %t3180 = getelementptr i8, ptr %t5, i64 -8
  %t3181 = load i32, ptr %t3180
  %t3182 = icmp eq i32 %t3181, 1
  br i1 %t3182, label %reuse.in_place.3183, label %reuse.copy.3184
reuse.in_place.3183:
  %t3186 = inttoptr i64 130 to ptr
  %t3187 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3186, ptr %t3187
  br label %reuse.join.3185
reuse.copy.3184:
  %t3188 = call ptr @__alloc(i64 24, i32 2)
  %t3189 = inttoptr i64 130 to ptr
  %t3190 = getelementptr ptr, ptr %t3188, i32 0
  store ptr %t3189, ptr %t3190
  call void @__inc_ref(ptr %t3177)
  %t3191 = getelementptr ptr, ptr %t3188, i32 1
  store ptr %t3177, ptr %t3191
  call void @__inc_ref(ptr %t3179)
  %t3192 = getelementptr ptr, ptr %t3188, i32 2
  store ptr %t3179, ptr %t3192
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3185
reuse.join.3185:
  %t3193 = phi ptr [ %t5, %reuse.in_place.3183 ], [ %t3188, %reuse.copy.3184 ]
  %t3194 = call ptr @__alloc(i64 16, i32 1)
  %t3195 = inttoptr i64 393 to ptr
  %t3196 = getelementptr ptr, ptr %t3194, i32 0
  store ptr %t3195, ptr %t3196
  call void @__inc_ref(ptr %t6)
  %t3197 = getelementptr ptr, ptr %t3194, i32 1
  store ptr %t6, ptr %t3197
  call void @__free_recursive(ptr %t6)
  store ptr %t3193, ptr %t3
  store ptr %t3194, ptr %t4
  br label %tco.loop.0
tco.case.arm.185.3198:
  %t3199 = getelementptr ptr, ptr %t5, i32 1
  %t3200 = load ptr, ptr %t3199
  call void @__inc_ref(ptr %t3200)
  %t3201 = getelementptr ptr, ptr %t5, i32 2
  %t3202 = load ptr, ptr %t3201
  call void @__inc_ref(ptr %t3202)
  %t3203 = getelementptr ptr, ptr %t5, i32 3
  %t3204 = load ptr, ptr %t3203
  call void @__inc_ref(ptr %t3204)
  %t3205 = call ptr @__alloc(i64 24, i32 2)
  %t3206 = inttoptr i64 130 to ptr
  %t3207 = getelementptr ptr, ptr %t3205, i32 0
  store ptr %t3206, ptr %t3207
  call void @__inc_ref(ptr %t3200)
  %t3208 = getelementptr ptr, ptr %t3205, i32 1
  store ptr %t3200, ptr %t3208
  call void @__inc_ref(ptr %t3202)
  %t3209 = getelementptr ptr, ptr %t3205, i32 2
  store ptr %t3202, ptr %t3209
  %t3210 = call ptr @__alloc(i64 24, i32 2)
  %t3211 = inttoptr i64 394 to ptr
  %t3212 = getelementptr ptr, ptr %t3210, i32 0
  store ptr %t3211, ptr %t3212
  call void @__inc_ref(ptr %t6)
  %t3213 = getelementptr ptr, ptr %t3210, i32 1
  store ptr %t6, ptr %t3213
  call void @__inc_ref(ptr %t3204)
  %t3214 = getelementptr ptr, ptr %t3210, i32 2
  store ptr %t3204, ptr %t3214
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t3204)
  call void @__free_recursive(ptr %t3202)
  call void @__free_recursive(ptr %t3200)
  store ptr %t3205, ptr %t3
  store ptr %t3210, ptr %t4
  br label %tco.loop.0
tco.case.arm.186.3215:
  %t3216 = getelementptr ptr, ptr %t5, i32 1
  %t3217 = load ptr, ptr %t3216
  %t3218 = getelementptr ptr, ptr %t5, i32 2
  %t3219 = load ptr, ptr %t3218
  %t3220 = getelementptr i8, ptr %t5, i64 -8
  %t3221 = load i32, ptr %t3220
  %t3222 = icmp eq i32 %t3221, 1
  br i1 %t3222, label %reuse.in_place.3223, label %reuse.copy.3224
reuse.in_place.3223:
  %t3226 = inttoptr i64 130 to ptr
  %t3227 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3226, ptr %t3227
  br label %reuse.join.3225
reuse.copy.3224:
  %t3228 = call ptr @__alloc(i64 24, i32 2)
  %t3229 = inttoptr i64 130 to ptr
  %t3230 = getelementptr ptr, ptr %t3228, i32 0
  store ptr %t3229, ptr %t3230
  call void @__inc_ref(ptr %t3217)
  %t3231 = getelementptr ptr, ptr %t3228, i32 1
  store ptr %t3217, ptr %t3231
  call void @__inc_ref(ptr %t3219)
  %t3232 = getelementptr ptr, ptr %t3228, i32 2
  store ptr %t3219, ptr %t3232
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3225
reuse.join.3225:
  %t3233 = phi ptr [ %t5, %reuse.in_place.3223 ], [ %t3228, %reuse.copy.3224 ]
  %t3234 = call ptr @__alloc(i64 16, i32 1)
  %t3235 = inttoptr i64 395 to ptr
  %t3236 = getelementptr ptr, ptr %t3234, i32 0
  store ptr %t3235, ptr %t3236
  call void @__inc_ref(ptr %t6)
  %t3237 = getelementptr ptr, ptr %t3234, i32 1
  store ptr %t6, ptr %t3237
  call void @__free_recursive(ptr %t6)
  store ptr %t3233, ptr %t3
  store ptr %t3234, ptr %t4
  br label %tco.loop.0
tco.case.arm.187.3238:
  %t3239 = getelementptr ptr, ptr %t5, i32 1
  %t3240 = load ptr, ptr %t3239
  %t3241 = getelementptr ptr, ptr %t5, i32 2
  %t3242 = load ptr, ptr %t3241
  %t3243 = getelementptr i8, ptr %t5, i64 -8
  %t3244 = load i32, ptr %t3243
  %t3245 = icmp eq i32 %t3244, 1
  br i1 %t3245, label %reuse.in_place.3246, label %reuse.copy.3247
reuse.in_place.3246:
  %t3249 = inttoptr i64 130 to ptr
  %t3250 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3249, ptr %t3250
  br label %reuse.join.3248
reuse.copy.3247:
  %t3251 = call ptr @__alloc(i64 24, i32 2)
  %t3252 = inttoptr i64 130 to ptr
  %t3253 = getelementptr ptr, ptr %t3251, i32 0
  store ptr %t3252, ptr %t3253
  call void @__inc_ref(ptr %t3240)
  %t3254 = getelementptr ptr, ptr %t3251, i32 1
  store ptr %t3240, ptr %t3254
  call void @__inc_ref(ptr %t3242)
  %t3255 = getelementptr ptr, ptr %t3251, i32 2
  store ptr %t3242, ptr %t3255
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3248
reuse.join.3248:
  %t3256 = phi ptr [ %t5, %reuse.in_place.3246 ], [ %t3251, %reuse.copy.3247 ]
  %t3257 = call ptr @__alloc(i64 16, i32 1)
  %t3258 = inttoptr i64 396 to ptr
  %t3259 = getelementptr ptr, ptr %t3257, i32 0
  store ptr %t3258, ptr %t3259
  call void @__inc_ref(ptr %t6)
  %t3260 = getelementptr ptr, ptr %t3257, i32 1
  store ptr %t6, ptr %t3260
  call void @__free_recursive(ptr %t6)
  store ptr %t3256, ptr %t3
  store ptr %t3257, ptr %t4
  br label %tco.loop.0
tco.case.arm.188.3261:
  %t3262 = getelementptr ptr, ptr %t5, i32 1
  %t3263 = load ptr, ptr %t3262
  %t3264 = getelementptr ptr, ptr %t5, i32 2
  %t3265 = load ptr, ptr %t3264
  %t3266 = getelementptr i8, ptr %t5, i64 -8
  %t3267 = load i32, ptr %t3266
  %t3268 = icmp eq i32 %t3267, 1
  br i1 %t3268, label %reuse.in_place.3269, label %reuse.copy.3270
reuse.in_place.3269:
  %t3272 = inttoptr i64 130 to ptr
  %t3273 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3272, ptr %t3273
  br label %reuse.join.3271
reuse.copy.3270:
  %t3274 = call ptr @__alloc(i64 24, i32 2)
  %t3275 = inttoptr i64 130 to ptr
  %t3276 = getelementptr ptr, ptr %t3274, i32 0
  store ptr %t3275, ptr %t3276
  call void @__inc_ref(ptr %t3263)
  %t3277 = getelementptr ptr, ptr %t3274, i32 1
  store ptr %t3263, ptr %t3277
  call void @__inc_ref(ptr %t3265)
  %t3278 = getelementptr ptr, ptr %t3274, i32 2
  store ptr %t3265, ptr %t3278
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3271
reuse.join.3271:
  %t3279 = phi ptr [ %t5, %reuse.in_place.3269 ], [ %t3274, %reuse.copy.3270 ]
  %t3280 = call ptr @__alloc(i64 16, i32 1)
  %t3281 = inttoptr i64 397 to ptr
  %t3282 = getelementptr ptr, ptr %t3280, i32 0
  store ptr %t3281, ptr %t3282
  call void @__inc_ref(ptr %t6)
  %t3283 = getelementptr ptr, ptr %t3280, i32 1
  store ptr %t6, ptr %t3283
  call void @__free_recursive(ptr %t6)
  store ptr %t3279, ptr %t3
  store ptr %t3280, ptr %t4
  br label %tco.loop.0
tco.case.arm.189.3284:
  %t3285 = getelementptr ptr, ptr %t5, i32 1
  %t3286 = load ptr, ptr %t3285
  %t3287 = getelementptr ptr, ptr %t5, i32 2
  %t3288 = load ptr, ptr %t3287
  %t3289 = getelementptr i8, ptr %t5, i64 -8
  %t3290 = load i32, ptr %t3289
  %t3291 = icmp eq i32 %t3290, 1
  br i1 %t3291, label %reuse.in_place.3292, label %reuse.copy.3293
reuse.in_place.3292:
  %t3295 = inttoptr i64 130 to ptr
  %t3296 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3295, ptr %t3296
  br label %reuse.join.3294
reuse.copy.3293:
  %t3297 = call ptr @__alloc(i64 24, i32 2)
  %t3298 = inttoptr i64 130 to ptr
  %t3299 = getelementptr ptr, ptr %t3297, i32 0
  store ptr %t3298, ptr %t3299
  call void @__inc_ref(ptr %t3286)
  %t3300 = getelementptr ptr, ptr %t3297, i32 1
  store ptr %t3286, ptr %t3300
  call void @__inc_ref(ptr %t3288)
  %t3301 = getelementptr ptr, ptr %t3297, i32 2
  store ptr %t3288, ptr %t3301
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3294
reuse.join.3294:
  %t3302 = phi ptr [ %t5, %reuse.in_place.3292 ], [ %t3297, %reuse.copy.3293 ]
  %t3303 = call ptr @__alloc(i64 16, i32 1)
  %t3304 = inttoptr i64 398 to ptr
  %t3305 = getelementptr ptr, ptr %t3303, i32 0
  store ptr %t3304, ptr %t3305
  call void @__inc_ref(ptr %t6)
  %t3306 = getelementptr ptr, ptr %t3303, i32 1
  store ptr %t6, ptr %t3306
  call void @__free_recursive(ptr %t6)
  store ptr %t3302, ptr %t3
  store ptr %t3303, ptr %t4
  br label %tco.loop.0
tco.case.arm.190.3307:
  %t3308 = getelementptr ptr, ptr %t5, i32 1
  %t3309 = load ptr, ptr %t3308
  %t3310 = getelementptr ptr, ptr %t5, i32 2
  %t3311 = load ptr, ptr %t3310
  %t3312 = getelementptr i8, ptr %t5, i64 -8
  %t3313 = load i32, ptr %t3312
  %t3314 = icmp eq i32 %t3313, 1
  br i1 %t3314, label %reuse.in_place.3315, label %reuse.copy.3316
reuse.in_place.3315:
  %t3318 = inttoptr i64 130 to ptr
  %t3319 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3318, ptr %t3319
  br label %reuse.join.3317
reuse.copy.3316:
  %t3320 = call ptr @__alloc(i64 24, i32 2)
  %t3321 = inttoptr i64 130 to ptr
  %t3322 = getelementptr ptr, ptr %t3320, i32 0
  store ptr %t3321, ptr %t3322
  call void @__inc_ref(ptr %t3309)
  %t3323 = getelementptr ptr, ptr %t3320, i32 1
  store ptr %t3309, ptr %t3323
  call void @__inc_ref(ptr %t3311)
  %t3324 = getelementptr ptr, ptr %t3320, i32 2
  store ptr %t3311, ptr %t3324
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3317
reuse.join.3317:
  %t3325 = phi ptr [ %t5, %reuse.in_place.3315 ], [ %t3320, %reuse.copy.3316 ]
  %t3326 = call ptr @__alloc(i64 16, i32 1)
  %t3327 = inttoptr i64 399 to ptr
  %t3328 = getelementptr ptr, ptr %t3326, i32 0
  store ptr %t3327, ptr %t3328
  call void @__inc_ref(ptr %t6)
  %t3329 = getelementptr ptr, ptr %t3326, i32 1
  store ptr %t6, ptr %t3329
  call void @__free_recursive(ptr %t6)
  store ptr %t3325, ptr %t3
  store ptr %t3326, ptr %t4
  br label %tco.loop.0
tco.case.arm.191.3330:
  %t3331 = getelementptr ptr, ptr %t5, i32 1
  %t3332 = load ptr, ptr %t3331
  %t3333 = getelementptr ptr, ptr %t5, i32 2
  %t3334 = load ptr, ptr %t3333
  %t3335 = getelementptr i8, ptr %t5, i64 -8
  %t3336 = load i32, ptr %t3335
  %t3337 = icmp eq i32 %t3336, 1
  br i1 %t3337, label %reuse.in_place.3338, label %reuse.copy.3339
reuse.in_place.3338:
  %t3341 = inttoptr i64 130 to ptr
  %t3342 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3341, ptr %t3342
  br label %reuse.join.3340
reuse.copy.3339:
  %t3343 = call ptr @__alloc(i64 24, i32 2)
  %t3344 = inttoptr i64 130 to ptr
  %t3345 = getelementptr ptr, ptr %t3343, i32 0
  store ptr %t3344, ptr %t3345
  call void @__inc_ref(ptr %t3332)
  %t3346 = getelementptr ptr, ptr %t3343, i32 1
  store ptr %t3332, ptr %t3346
  call void @__inc_ref(ptr %t3334)
  %t3347 = getelementptr ptr, ptr %t3343, i32 2
  store ptr %t3334, ptr %t3347
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3340
reuse.join.3340:
  %t3348 = phi ptr [ %t5, %reuse.in_place.3338 ], [ %t3343, %reuse.copy.3339 ]
  %t3349 = call ptr @__alloc(i64 16, i32 1)
  %t3350 = inttoptr i64 400 to ptr
  %t3351 = getelementptr ptr, ptr %t3349, i32 0
  store ptr %t3350, ptr %t3351
  call void @__inc_ref(ptr %t6)
  %t3352 = getelementptr ptr, ptr %t3349, i32 1
  store ptr %t6, ptr %t3352
  call void @__free_recursive(ptr %t6)
  store ptr %t3348, ptr %t3
  store ptr %t3349, ptr %t4
  br label %tco.loop.0
tco.case.arm.192.3353:
  %t3354 = getelementptr ptr, ptr %t5, i32 1
  %t3355 = load ptr, ptr %t3354
  %t3356 = getelementptr ptr, ptr %t5, i32 2
  %t3357 = load ptr, ptr %t3356
  %t3358 = getelementptr i8, ptr %t5, i64 -8
  %t3359 = load i32, ptr %t3358
  %t3360 = icmp eq i32 %t3359, 1
  br i1 %t3360, label %reuse.in_place.3361, label %reuse.copy.3362
reuse.in_place.3361:
  %t3364 = inttoptr i64 130 to ptr
  %t3365 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3364, ptr %t3365
  br label %reuse.join.3363
reuse.copy.3362:
  %t3366 = call ptr @__alloc(i64 24, i32 2)
  %t3367 = inttoptr i64 130 to ptr
  %t3368 = getelementptr ptr, ptr %t3366, i32 0
  store ptr %t3367, ptr %t3368
  call void @__inc_ref(ptr %t3355)
  %t3369 = getelementptr ptr, ptr %t3366, i32 1
  store ptr %t3355, ptr %t3369
  call void @__inc_ref(ptr %t3357)
  %t3370 = getelementptr ptr, ptr %t3366, i32 2
  store ptr %t3357, ptr %t3370
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3363
reuse.join.3363:
  %t3371 = phi ptr [ %t5, %reuse.in_place.3361 ], [ %t3366, %reuse.copy.3362 ]
  %t3372 = call ptr @__alloc(i64 16, i32 1)
  %t3373 = inttoptr i64 401 to ptr
  %t3374 = getelementptr ptr, ptr %t3372, i32 0
  store ptr %t3373, ptr %t3374
  call void @__inc_ref(ptr %t6)
  %t3375 = getelementptr ptr, ptr %t3372, i32 1
  store ptr %t6, ptr %t3375
  call void @__free_recursive(ptr %t6)
  store ptr %t3371, ptr %t3
  store ptr %t3372, ptr %t4
  br label %tco.loop.0
tco.case.arm.193.3376:
  %t3377 = getelementptr ptr, ptr %t5, i32 1
  %t3378 = load ptr, ptr %t3377
  %t3379 = getelementptr ptr, ptr %t5, i32 2
  %t3380 = load ptr, ptr %t3379
  %t3381 = getelementptr i8, ptr %t5, i64 -8
  %t3382 = load i32, ptr %t3381
  %t3383 = icmp eq i32 %t3382, 1
  br i1 %t3383, label %reuse.in_place.3384, label %reuse.copy.3385
reuse.in_place.3384:
  %t3387 = inttoptr i64 130 to ptr
  %t3388 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3387, ptr %t3388
  br label %reuse.join.3386
reuse.copy.3385:
  %t3389 = call ptr @__alloc(i64 24, i32 2)
  %t3390 = inttoptr i64 130 to ptr
  %t3391 = getelementptr ptr, ptr %t3389, i32 0
  store ptr %t3390, ptr %t3391
  call void @__inc_ref(ptr %t3378)
  %t3392 = getelementptr ptr, ptr %t3389, i32 1
  store ptr %t3378, ptr %t3392
  call void @__inc_ref(ptr %t3380)
  %t3393 = getelementptr ptr, ptr %t3389, i32 2
  store ptr %t3380, ptr %t3393
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3386
reuse.join.3386:
  %t3394 = phi ptr [ %t5, %reuse.in_place.3384 ], [ %t3389, %reuse.copy.3385 ]
  %t3395 = call ptr @__alloc(i64 16, i32 1)
  %t3396 = inttoptr i64 402 to ptr
  %t3397 = getelementptr ptr, ptr %t3395, i32 0
  store ptr %t3396, ptr %t3397
  call void @__inc_ref(ptr %t6)
  %t3398 = getelementptr ptr, ptr %t3395, i32 1
  store ptr %t6, ptr %t3398
  call void @__free_recursive(ptr %t6)
  store ptr %t3394, ptr %t3
  store ptr %t3395, ptr %t4
  br label %tco.loop.0
tco.case.arm.194.3399:
  %t3400 = getelementptr ptr, ptr %t5, i32 1
  %t3401 = load ptr, ptr %t3400
  %t3402 = getelementptr ptr, ptr %t5, i32 2
  %t3403 = load ptr, ptr %t3402
  %t3404 = getelementptr i8, ptr %t5, i64 -8
  %t3405 = load i32, ptr %t3404
  %t3406 = icmp eq i32 %t3405, 1
  br i1 %t3406, label %reuse.in_place.3407, label %reuse.copy.3408
reuse.in_place.3407:
  %t3410 = inttoptr i64 130 to ptr
  %t3411 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3410, ptr %t3411
  br label %reuse.join.3409
reuse.copy.3408:
  %t3412 = call ptr @__alloc(i64 24, i32 2)
  %t3413 = inttoptr i64 130 to ptr
  %t3414 = getelementptr ptr, ptr %t3412, i32 0
  store ptr %t3413, ptr %t3414
  call void @__inc_ref(ptr %t3401)
  %t3415 = getelementptr ptr, ptr %t3412, i32 1
  store ptr %t3401, ptr %t3415
  call void @__inc_ref(ptr %t3403)
  %t3416 = getelementptr ptr, ptr %t3412, i32 2
  store ptr %t3403, ptr %t3416
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3409
reuse.join.3409:
  %t3417 = phi ptr [ %t5, %reuse.in_place.3407 ], [ %t3412, %reuse.copy.3408 ]
  %t3418 = call ptr @__alloc(i64 16, i32 1)
  %t3419 = inttoptr i64 403 to ptr
  %t3420 = getelementptr ptr, ptr %t3418, i32 0
  store ptr %t3419, ptr %t3420
  call void @__inc_ref(ptr %t6)
  %t3421 = getelementptr ptr, ptr %t3418, i32 1
  store ptr %t6, ptr %t3421
  call void @__free_recursive(ptr %t6)
  store ptr %t3417, ptr %t3
  store ptr %t3418, ptr %t4
  br label %tco.loop.0
tco.case.arm.195.3422:
  %t3423 = getelementptr ptr, ptr %t5, i32 1
  %t3424 = load ptr, ptr %t3423
  %t3425 = getelementptr ptr, ptr %t5, i32 2
  %t3426 = load ptr, ptr %t3425
  %t3427 = getelementptr i8, ptr %t5, i64 -8
  %t3428 = load i32, ptr %t3427
  %t3429 = icmp eq i32 %t3428, 1
  br i1 %t3429, label %reuse.in_place.3430, label %reuse.copy.3431
reuse.in_place.3430:
  %t3433 = inttoptr i64 130 to ptr
  %t3434 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3433, ptr %t3434
  br label %reuse.join.3432
reuse.copy.3431:
  %t3435 = call ptr @__alloc(i64 24, i32 2)
  %t3436 = inttoptr i64 130 to ptr
  %t3437 = getelementptr ptr, ptr %t3435, i32 0
  store ptr %t3436, ptr %t3437
  call void @__inc_ref(ptr %t3424)
  %t3438 = getelementptr ptr, ptr %t3435, i32 1
  store ptr %t3424, ptr %t3438
  call void @__inc_ref(ptr %t3426)
  %t3439 = getelementptr ptr, ptr %t3435, i32 2
  store ptr %t3426, ptr %t3439
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3432
reuse.join.3432:
  %t3440 = phi ptr [ %t5, %reuse.in_place.3430 ], [ %t3435, %reuse.copy.3431 ]
  %t3441 = call ptr @__alloc(i64 16, i32 1)
  %t3442 = inttoptr i64 404 to ptr
  %t3443 = getelementptr ptr, ptr %t3441, i32 0
  store ptr %t3442, ptr %t3443
  call void @__inc_ref(ptr %t6)
  %t3444 = getelementptr ptr, ptr %t3441, i32 1
  store ptr %t6, ptr %t3444
  call void @__free_recursive(ptr %t6)
  store ptr %t3440, ptr %t3
  store ptr %t3441, ptr %t4
  br label %tco.loop.0
tco.case.arm.196.3445:
  %t3446 = getelementptr ptr, ptr %t5, i32 1
  %t3447 = load ptr, ptr %t3446
  %t3448 = getelementptr ptr, ptr %t5, i32 2
  %t3449 = load ptr, ptr %t3448
  %t3450 = getelementptr i8, ptr %t5, i64 -8
  %t3451 = load i32, ptr %t3450
  %t3452 = icmp eq i32 %t3451, 1
  br i1 %t3452, label %reuse.in_place.3453, label %reuse.copy.3454
reuse.in_place.3453:
  %t3456 = inttoptr i64 130 to ptr
  %t3457 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3456, ptr %t3457
  br label %reuse.join.3455
reuse.copy.3454:
  %t3458 = call ptr @__alloc(i64 24, i32 2)
  %t3459 = inttoptr i64 130 to ptr
  %t3460 = getelementptr ptr, ptr %t3458, i32 0
  store ptr %t3459, ptr %t3460
  call void @__inc_ref(ptr %t3447)
  %t3461 = getelementptr ptr, ptr %t3458, i32 1
  store ptr %t3447, ptr %t3461
  call void @__inc_ref(ptr %t3449)
  %t3462 = getelementptr ptr, ptr %t3458, i32 2
  store ptr %t3449, ptr %t3462
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3455
reuse.join.3455:
  %t3463 = phi ptr [ %t5, %reuse.in_place.3453 ], [ %t3458, %reuse.copy.3454 ]
  %t3464 = call ptr @__alloc(i64 16, i32 1)
  %t3465 = inttoptr i64 405 to ptr
  %t3466 = getelementptr ptr, ptr %t3464, i32 0
  store ptr %t3465, ptr %t3466
  call void @__inc_ref(ptr %t6)
  %t3467 = getelementptr ptr, ptr %t3464, i32 1
  store ptr %t6, ptr %t3467
  call void @__free_recursive(ptr %t6)
  store ptr %t3463, ptr %t3
  store ptr %t3464, ptr %t4
  br label %tco.loop.0
tco.case.arm.197.3468:
  %t3469 = getelementptr ptr, ptr %t5, i32 1
  %t3470 = load ptr, ptr %t3469
  %t3471 = getelementptr ptr, ptr %t5, i32 2
  %t3472 = load ptr, ptr %t3471
  %t3473 = getelementptr i8, ptr %t5, i64 -8
  %t3474 = load i32, ptr %t3473
  %t3475 = icmp eq i32 %t3474, 1
  br i1 %t3475, label %reuse.in_place.3476, label %reuse.copy.3477
reuse.in_place.3476:
  %t3479 = inttoptr i64 130 to ptr
  %t3480 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3479, ptr %t3480
  br label %reuse.join.3478
reuse.copy.3477:
  %t3481 = call ptr @__alloc(i64 24, i32 2)
  %t3482 = inttoptr i64 130 to ptr
  %t3483 = getelementptr ptr, ptr %t3481, i32 0
  store ptr %t3482, ptr %t3483
  call void @__inc_ref(ptr %t3470)
  %t3484 = getelementptr ptr, ptr %t3481, i32 1
  store ptr %t3470, ptr %t3484
  call void @__inc_ref(ptr %t3472)
  %t3485 = getelementptr ptr, ptr %t3481, i32 2
  store ptr %t3472, ptr %t3485
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3478
reuse.join.3478:
  %t3486 = phi ptr [ %t5, %reuse.in_place.3476 ], [ %t3481, %reuse.copy.3477 ]
  %t3487 = call ptr @__alloc(i64 16, i32 1)
  %t3488 = inttoptr i64 406 to ptr
  %t3489 = getelementptr ptr, ptr %t3487, i32 0
  store ptr %t3488, ptr %t3489
  call void @__inc_ref(ptr %t6)
  %t3490 = getelementptr ptr, ptr %t3487, i32 1
  store ptr %t6, ptr %t3490
  call void @__free_recursive(ptr %t6)
  store ptr %t3486, ptr %t3
  store ptr %t3487, ptr %t4
  br label %tco.loop.0
tco.case.arm.198.3491:
  %t3492 = getelementptr ptr, ptr %t5, i32 1
  %t3493 = load ptr, ptr %t3492
  %t3494 = getelementptr ptr, ptr %t5, i32 2
  %t3495 = load ptr, ptr %t3494
  %t3496 = getelementptr i8, ptr %t5, i64 -8
  %t3497 = load i32, ptr %t3496
  %t3498 = icmp eq i32 %t3497, 1
  br i1 %t3498, label %reuse.in_place.3499, label %reuse.copy.3500
reuse.in_place.3499:
  %t3502 = inttoptr i64 130 to ptr
  %t3503 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3502, ptr %t3503
  br label %reuse.join.3501
reuse.copy.3500:
  %t3504 = call ptr @__alloc(i64 24, i32 2)
  %t3505 = inttoptr i64 130 to ptr
  %t3506 = getelementptr ptr, ptr %t3504, i32 0
  store ptr %t3505, ptr %t3506
  call void @__inc_ref(ptr %t3493)
  %t3507 = getelementptr ptr, ptr %t3504, i32 1
  store ptr %t3493, ptr %t3507
  call void @__inc_ref(ptr %t3495)
  %t3508 = getelementptr ptr, ptr %t3504, i32 2
  store ptr %t3495, ptr %t3508
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3501
reuse.join.3501:
  %t3509 = phi ptr [ %t5, %reuse.in_place.3499 ], [ %t3504, %reuse.copy.3500 ]
  %t3510 = call ptr @__alloc(i64 16, i32 1)
  %t3511 = inttoptr i64 407 to ptr
  %t3512 = getelementptr ptr, ptr %t3510, i32 0
  store ptr %t3511, ptr %t3512
  call void @__inc_ref(ptr %t6)
  %t3513 = getelementptr ptr, ptr %t3510, i32 1
  store ptr %t6, ptr %t3513
  call void @__free_recursive(ptr %t6)
  store ptr %t3509, ptr %t3
  store ptr %t3510, ptr %t4
  br label %tco.loop.0
tco.case.arm.199.3514:
  %t3515 = getelementptr ptr, ptr %t5, i32 1
  %t3516 = load ptr, ptr %t3515
  %t3517 = getelementptr ptr, ptr %t5, i32 2
  %t3518 = load ptr, ptr %t3517
  %t3519 = getelementptr i8, ptr %t5, i64 -8
  %t3520 = load i32, ptr %t3519
  %t3521 = icmp eq i32 %t3520, 1
  br i1 %t3521, label %reuse.in_place.3522, label %reuse.copy.3523
reuse.in_place.3522:
  %t3525 = inttoptr i64 130 to ptr
  %t3526 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3525, ptr %t3526
  br label %reuse.join.3524
reuse.copy.3523:
  %t3527 = call ptr @__alloc(i64 24, i32 2)
  %t3528 = inttoptr i64 130 to ptr
  %t3529 = getelementptr ptr, ptr %t3527, i32 0
  store ptr %t3528, ptr %t3529
  call void @__inc_ref(ptr %t3516)
  %t3530 = getelementptr ptr, ptr %t3527, i32 1
  store ptr %t3516, ptr %t3530
  call void @__inc_ref(ptr %t3518)
  %t3531 = getelementptr ptr, ptr %t3527, i32 2
  store ptr %t3518, ptr %t3531
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3524
reuse.join.3524:
  %t3532 = phi ptr [ %t5, %reuse.in_place.3522 ], [ %t3527, %reuse.copy.3523 ]
  %t3533 = call ptr @__alloc(i64 16, i32 1)
  %t3534 = inttoptr i64 408 to ptr
  %t3535 = getelementptr ptr, ptr %t3533, i32 0
  store ptr %t3534, ptr %t3535
  call void @__inc_ref(ptr %t6)
  %t3536 = getelementptr ptr, ptr %t3533, i32 1
  store ptr %t6, ptr %t3536
  call void @__free_recursive(ptr %t6)
  store ptr %t3532, ptr %t3
  store ptr %t3533, ptr %t4
  br label %tco.loop.0
tco.case.arm.200.3537:
  %t3538 = getelementptr ptr, ptr %t5, i32 1
  %t3539 = load ptr, ptr %t3538
  %t3540 = getelementptr ptr, ptr %t5, i32 2
  %t3541 = load ptr, ptr %t3540
  %t3542 = getelementptr i8, ptr %t5, i64 -8
  %t3543 = load i32, ptr %t3542
  %t3544 = icmp eq i32 %t3543, 1
  br i1 %t3544, label %reuse.in_place.3545, label %reuse.copy.3546
reuse.in_place.3545:
  %t3548 = inttoptr i64 130 to ptr
  %t3549 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3548, ptr %t3549
  br label %reuse.join.3547
reuse.copy.3546:
  %t3550 = call ptr @__alloc(i64 24, i32 2)
  %t3551 = inttoptr i64 130 to ptr
  %t3552 = getelementptr ptr, ptr %t3550, i32 0
  store ptr %t3551, ptr %t3552
  call void @__inc_ref(ptr %t3539)
  %t3553 = getelementptr ptr, ptr %t3550, i32 1
  store ptr %t3539, ptr %t3553
  call void @__inc_ref(ptr %t3541)
  %t3554 = getelementptr ptr, ptr %t3550, i32 2
  store ptr %t3541, ptr %t3554
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3547
reuse.join.3547:
  %t3555 = phi ptr [ %t5, %reuse.in_place.3545 ], [ %t3550, %reuse.copy.3546 ]
  %t3556 = call ptr @__alloc(i64 16, i32 1)
  %t3557 = inttoptr i64 409 to ptr
  %t3558 = getelementptr ptr, ptr %t3556, i32 0
  store ptr %t3557, ptr %t3558
  call void @__inc_ref(ptr %t6)
  %t3559 = getelementptr ptr, ptr %t3556, i32 1
  store ptr %t6, ptr %t3559
  call void @__free_recursive(ptr %t6)
  store ptr %t3555, ptr %t3
  store ptr %t3556, ptr %t4
  br label %tco.loop.0
tco.case.arm.201.3560:
  %t3561 = getelementptr ptr, ptr %t5, i32 1
  %t3562 = load ptr, ptr %t3561
  %t3563 = getelementptr ptr, ptr %t5, i32 2
  %t3564 = load ptr, ptr %t3563
  %t3565 = getelementptr i8, ptr %t5, i64 -8
  %t3566 = load i32, ptr %t3565
  %t3567 = icmp eq i32 %t3566, 1
  br i1 %t3567, label %reuse.in_place.3568, label %reuse.copy.3569
reuse.in_place.3568:
  %t3571 = inttoptr i64 130 to ptr
  %t3572 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3571, ptr %t3572
  br label %reuse.join.3570
reuse.copy.3569:
  %t3573 = call ptr @__alloc(i64 24, i32 2)
  %t3574 = inttoptr i64 130 to ptr
  %t3575 = getelementptr ptr, ptr %t3573, i32 0
  store ptr %t3574, ptr %t3575
  call void @__inc_ref(ptr %t3562)
  %t3576 = getelementptr ptr, ptr %t3573, i32 1
  store ptr %t3562, ptr %t3576
  call void @__inc_ref(ptr %t3564)
  %t3577 = getelementptr ptr, ptr %t3573, i32 2
  store ptr %t3564, ptr %t3577
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3570
reuse.join.3570:
  %t3578 = phi ptr [ %t5, %reuse.in_place.3568 ], [ %t3573, %reuse.copy.3569 ]
  %t3579 = call ptr @__alloc(i64 16, i32 1)
  %t3580 = inttoptr i64 410 to ptr
  %t3581 = getelementptr ptr, ptr %t3579, i32 0
  store ptr %t3580, ptr %t3581
  call void @__inc_ref(ptr %t6)
  %t3582 = getelementptr ptr, ptr %t3579, i32 1
  store ptr %t6, ptr %t3582
  call void @__free_recursive(ptr %t6)
  store ptr %t3578, ptr %t3
  store ptr %t3579, ptr %t4
  br label %tco.loop.0
tco.case.arm.202.3583:
  %t3584 = getelementptr ptr, ptr %t5, i32 1
  %t3585 = load ptr, ptr %t3584
  %t3586 = getelementptr ptr, ptr %t5, i32 2
  %t3587 = load ptr, ptr %t3586
  %t3588 = getelementptr i8, ptr %t5, i64 -8
  %t3589 = load i32, ptr %t3588
  %t3590 = icmp eq i32 %t3589, 1
  br i1 %t3590, label %reuse.in_place.3591, label %reuse.copy.3592
reuse.in_place.3591:
  %t3594 = inttoptr i64 130 to ptr
  %t3595 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3594, ptr %t3595
  br label %reuse.join.3593
reuse.copy.3592:
  %t3596 = call ptr @__alloc(i64 24, i32 2)
  %t3597 = inttoptr i64 130 to ptr
  %t3598 = getelementptr ptr, ptr %t3596, i32 0
  store ptr %t3597, ptr %t3598
  call void @__inc_ref(ptr %t3585)
  %t3599 = getelementptr ptr, ptr %t3596, i32 1
  store ptr %t3585, ptr %t3599
  call void @__inc_ref(ptr %t3587)
  %t3600 = getelementptr ptr, ptr %t3596, i32 2
  store ptr %t3587, ptr %t3600
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3593
reuse.join.3593:
  %t3601 = phi ptr [ %t5, %reuse.in_place.3591 ], [ %t3596, %reuse.copy.3592 ]
  %t3602 = call ptr @__alloc(i64 16, i32 1)
  %t3603 = inttoptr i64 411 to ptr
  %t3604 = getelementptr ptr, ptr %t3602, i32 0
  store ptr %t3603, ptr %t3604
  call void @__inc_ref(ptr %t6)
  %t3605 = getelementptr ptr, ptr %t3602, i32 1
  store ptr %t6, ptr %t3605
  call void @__free_recursive(ptr %t6)
  store ptr %t3601, ptr %t3
  store ptr %t3602, ptr %t4
  br label %tco.loop.0
tco.case.arm.203.3606:
  %t3607 = getelementptr ptr, ptr %t5, i32 1
  %t3608 = load ptr, ptr %t3607
  %t3609 = getelementptr ptr, ptr %t5, i32 2
  %t3610 = load ptr, ptr %t3609
  %t3611 = getelementptr i8, ptr %t5, i64 -8
  %t3612 = load i32, ptr %t3611
  %t3613 = icmp eq i32 %t3612, 1
  br i1 %t3613, label %reuse.in_place.3614, label %reuse.copy.3615
reuse.in_place.3614:
  %t3617 = inttoptr i64 130 to ptr
  %t3618 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3617, ptr %t3618
  br label %reuse.join.3616
reuse.copy.3615:
  %t3619 = call ptr @__alloc(i64 24, i32 2)
  %t3620 = inttoptr i64 130 to ptr
  %t3621 = getelementptr ptr, ptr %t3619, i32 0
  store ptr %t3620, ptr %t3621
  call void @__inc_ref(ptr %t3608)
  %t3622 = getelementptr ptr, ptr %t3619, i32 1
  store ptr %t3608, ptr %t3622
  call void @__inc_ref(ptr %t3610)
  %t3623 = getelementptr ptr, ptr %t3619, i32 2
  store ptr %t3610, ptr %t3623
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3616
reuse.join.3616:
  %t3624 = phi ptr [ %t5, %reuse.in_place.3614 ], [ %t3619, %reuse.copy.3615 ]
  %t3625 = call ptr @__alloc(i64 16, i32 1)
  %t3626 = inttoptr i64 412 to ptr
  %t3627 = getelementptr ptr, ptr %t3625, i32 0
  store ptr %t3626, ptr %t3627
  call void @__inc_ref(ptr %t6)
  %t3628 = getelementptr ptr, ptr %t3625, i32 1
  store ptr %t6, ptr %t3628
  call void @__free_recursive(ptr %t6)
  store ptr %t3624, ptr %t3
  store ptr %t3625, ptr %t4
  br label %tco.loop.0
tco.case.arm.204.3629:
  %t3630 = getelementptr ptr, ptr %t5, i32 1
  %t3631 = load ptr, ptr %t3630
  %t3632 = getelementptr ptr, ptr %t5, i32 2
  %t3633 = load ptr, ptr %t3632
  %t3634 = getelementptr i8, ptr %t5, i64 -8
  %t3635 = load i32, ptr %t3634
  %t3636 = icmp eq i32 %t3635, 1
  br i1 %t3636, label %reuse.in_place.3637, label %reuse.copy.3638
reuse.in_place.3637:
  %t3640 = inttoptr i64 130 to ptr
  %t3641 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3640, ptr %t3641
  br label %reuse.join.3639
reuse.copy.3638:
  %t3642 = call ptr @__alloc(i64 24, i32 2)
  %t3643 = inttoptr i64 130 to ptr
  %t3644 = getelementptr ptr, ptr %t3642, i32 0
  store ptr %t3643, ptr %t3644
  call void @__inc_ref(ptr %t3631)
  %t3645 = getelementptr ptr, ptr %t3642, i32 1
  store ptr %t3631, ptr %t3645
  call void @__inc_ref(ptr %t3633)
  %t3646 = getelementptr ptr, ptr %t3642, i32 2
  store ptr %t3633, ptr %t3646
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3639
reuse.join.3639:
  %t3647 = phi ptr [ %t5, %reuse.in_place.3637 ], [ %t3642, %reuse.copy.3638 ]
  %t3648 = call ptr @__alloc(i64 16, i32 1)
  %t3649 = inttoptr i64 413 to ptr
  %t3650 = getelementptr ptr, ptr %t3648, i32 0
  store ptr %t3649, ptr %t3650
  call void @__inc_ref(ptr %t6)
  %t3651 = getelementptr ptr, ptr %t3648, i32 1
  store ptr %t6, ptr %t3651
  call void @__free_recursive(ptr %t6)
  store ptr %t3647, ptr %t3
  store ptr %t3648, ptr %t4
  br label %tco.loop.0
tco.case.arm.205.3652:
  %t3653 = getelementptr ptr, ptr %t5, i32 1
  %t3654 = load ptr, ptr %t3653
  %t3655 = getelementptr ptr, ptr %t5, i32 2
  %t3656 = load ptr, ptr %t3655
  %t3657 = getelementptr i8, ptr %t5, i64 -8
  %t3658 = load i32, ptr %t3657
  %t3659 = icmp eq i32 %t3658, 1
  br i1 %t3659, label %reuse.in_place.3660, label %reuse.copy.3661
reuse.in_place.3660:
  %t3663 = inttoptr i64 130 to ptr
  %t3664 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3663, ptr %t3664
  br label %reuse.join.3662
reuse.copy.3661:
  %t3665 = call ptr @__alloc(i64 24, i32 2)
  %t3666 = inttoptr i64 130 to ptr
  %t3667 = getelementptr ptr, ptr %t3665, i32 0
  store ptr %t3666, ptr %t3667
  call void @__inc_ref(ptr %t3654)
  %t3668 = getelementptr ptr, ptr %t3665, i32 1
  store ptr %t3654, ptr %t3668
  call void @__inc_ref(ptr %t3656)
  %t3669 = getelementptr ptr, ptr %t3665, i32 2
  store ptr %t3656, ptr %t3669
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3662
reuse.join.3662:
  %t3670 = phi ptr [ %t5, %reuse.in_place.3660 ], [ %t3665, %reuse.copy.3661 ]
  %t3671 = call ptr @__alloc(i64 16, i32 1)
  %t3672 = inttoptr i64 414 to ptr
  %t3673 = getelementptr ptr, ptr %t3671, i32 0
  store ptr %t3672, ptr %t3673
  call void @__inc_ref(ptr %t6)
  %t3674 = getelementptr ptr, ptr %t3671, i32 1
  store ptr %t6, ptr %t3674
  call void @__free_recursive(ptr %t6)
  store ptr %t3670, ptr %t3
  store ptr %t3671, ptr %t4
  br label %tco.loop.0
tco.case.arm.206.3675:
  %t3676 = getelementptr ptr, ptr %t5, i32 1
  %t3677 = load ptr, ptr %t3676
  %t3678 = getelementptr ptr, ptr %t5, i32 2
  %t3679 = load ptr, ptr %t3678
  %t3680 = getelementptr i8, ptr %t5, i64 -8
  %t3681 = load i32, ptr %t3680
  %t3682 = icmp eq i32 %t3681, 1
  br i1 %t3682, label %reuse.in_place.3683, label %reuse.copy.3684
reuse.in_place.3683:
  %t3686 = inttoptr i64 130 to ptr
  %t3687 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3686, ptr %t3687
  br label %reuse.join.3685
reuse.copy.3684:
  %t3688 = call ptr @__alloc(i64 24, i32 2)
  %t3689 = inttoptr i64 130 to ptr
  %t3690 = getelementptr ptr, ptr %t3688, i32 0
  store ptr %t3689, ptr %t3690
  call void @__inc_ref(ptr %t3677)
  %t3691 = getelementptr ptr, ptr %t3688, i32 1
  store ptr %t3677, ptr %t3691
  call void @__inc_ref(ptr %t3679)
  %t3692 = getelementptr ptr, ptr %t3688, i32 2
  store ptr %t3679, ptr %t3692
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3685
reuse.join.3685:
  %t3693 = phi ptr [ %t5, %reuse.in_place.3683 ], [ %t3688, %reuse.copy.3684 ]
  %t3694 = call ptr @__alloc(i64 16, i32 1)
  %t3695 = inttoptr i64 415 to ptr
  %t3696 = getelementptr ptr, ptr %t3694, i32 0
  store ptr %t3695, ptr %t3696
  call void @__inc_ref(ptr %t6)
  %t3697 = getelementptr ptr, ptr %t3694, i32 1
  store ptr %t6, ptr %t3697
  call void @__free_recursive(ptr %t6)
  store ptr %t3693, ptr %t3
  store ptr %t3694, ptr %t4
  br label %tco.loop.0
tco.case.arm.207.3698:
  %t3699 = getelementptr ptr, ptr %t5, i32 1
  %t3700 = load ptr, ptr %t3699
  %t3701 = getelementptr ptr, ptr %t5, i32 2
  %t3702 = load ptr, ptr %t3701
  %t3703 = getelementptr i8, ptr %t5, i64 -8
  %t3704 = load i32, ptr %t3703
  %t3705 = icmp eq i32 %t3704, 1
  br i1 %t3705, label %reuse.in_place.3706, label %reuse.copy.3707
reuse.in_place.3706:
  %t3709 = inttoptr i64 130 to ptr
  %t3710 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3709, ptr %t3710
  br label %reuse.join.3708
reuse.copy.3707:
  %t3711 = call ptr @__alloc(i64 24, i32 2)
  %t3712 = inttoptr i64 130 to ptr
  %t3713 = getelementptr ptr, ptr %t3711, i32 0
  store ptr %t3712, ptr %t3713
  call void @__inc_ref(ptr %t3700)
  %t3714 = getelementptr ptr, ptr %t3711, i32 1
  store ptr %t3700, ptr %t3714
  call void @__inc_ref(ptr %t3702)
  %t3715 = getelementptr ptr, ptr %t3711, i32 2
  store ptr %t3702, ptr %t3715
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3708
reuse.join.3708:
  %t3716 = phi ptr [ %t5, %reuse.in_place.3706 ], [ %t3711, %reuse.copy.3707 ]
  %t3717 = call ptr @__alloc(i64 16, i32 1)
  %t3718 = inttoptr i64 416 to ptr
  %t3719 = getelementptr ptr, ptr %t3717, i32 0
  store ptr %t3718, ptr %t3719
  call void @__inc_ref(ptr %t6)
  %t3720 = getelementptr ptr, ptr %t3717, i32 1
  store ptr %t6, ptr %t3720
  call void @__free_recursive(ptr %t6)
  store ptr %t3716, ptr %t3
  store ptr %t3717, ptr %t4
  br label %tco.loop.0
tco.case.arm.208.3721:
  %t3722 = getelementptr ptr, ptr %t5, i32 1
  %t3723 = load ptr, ptr %t3722
  %t3724 = getelementptr ptr, ptr %t5, i32 2
  %t3725 = load ptr, ptr %t3724
  %t3726 = getelementptr i8, ptr %t5, i64 -8
  %t3727 = load i32, ptr %t3726
  %t3728 = icmp eq i32 %t3727, 1
  br i1 %t3728, label %reuse.in_place.3729, label %reuse.copy.3730
reuse.in_place.3729:
  %t3732 = inttoptr i64 130 to ptr
  %t3733 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3732, ptr %t3733
  br label %reuse.join.3731
reuse.copy.3730:
  %t3734 = call ptr @__alloc(i64 24, i32 2)
  %t3735 = inttoptr i64 130 to ptr
  %t3736 = getelementptr ptr, ptr %t3734, i32 0
  store ptr %t3735, ptr %t3736
  call void @__inc_ref(ptr %t3723)
  %t3737 = getelementptr ptr, ptr %t3734, i32 1
  store ptr %t3723, ptr %t3737
  call void @__inc_ref(ptr %t3725)
  %t3738 = getelementptr ptr, ptr %t3734, i32 2
  store ptr %t3725, ptr %t3738
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3731
reuse.join.3731:
  %t3739 = phi ptr [ %t5, %reuse.in_place.3729 ], [ %t3734, %reuse.copy.3730 ]
  %t3740 = call ptr @__alloc(i64 16, i32 1)
  %t3741 = inttoptr i64 417 to ptr
  %t3742 = getelementptr ptr, ptr %t3740, i32 0
  store ptr %t3741, ptr %t3742
  call void @__inc_ref(ptr %t6)
  %t3743 = getelementptr ptr, ptr %t3740, i32 1
  store ptr %t6, ptr %t3743
  call void @__free_recursive(ptr %t6)
  store ptr %t3739, ptr %t3
  store ptr %t3740, ptr %t4
  br label %tco.loop.0
tco.case.arm.209.3744:
  %t3745 = getelementptr ptr, ptr %t5, i32 1
  %t3746 = load ptr, ptr %t3745
  %t3747 = getelementptr ptr, ptr %t5, i32 2
  %t3748 = load ptr, ptr %t3747
  %t3749 = getelementptr i8, ptr %t5, i64 -8
  %t3750 = load i32, ptr %t3749
  %t3751 = icmp eq i32 %t3750, 1
  br i1 %t3751, label %reuse.in_place.3752, label %reuse.copy.3753
reuse.in_place.3752:
  %t3755 = inttoptr i64 130 to ptr
  %t3756 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3755, ptr %t3756
  br label %reuse.join.3754
reuse.copy.3753:
  %t3757 = call ptr @__alloc(i64 24, i32 2)
  %t3758 = inttoptr i64 130 to ptr
  %t3759 = getelementptr ptr, ptr %t3757, i32 0
  store ptr %t3758, ptr %t3759
  call void @__inc_ref(ptr %t3746)
  %t3760 = getelementptr ptr, ptr %t3757, i32 1
  store ptr %t3746, ptr %t3760
  call void @__inc_ref(ptr %t3748)
  %t3761 = getelementptr ptr, ptr %t3757, i32 2
  store ptr %t3748, ptr %t3761
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3754
reuse.join.3754:
  %t3762 = phi ptr [ %t5, %reuse.in_place.3752 ], [ %t3757, %reuse.copy.3753 ]
  %t3763 = call ptr @__alloc(i64 16, i32 1)
  %t3764 = inttoptr i64 418 to ptr
  %t3765 = getelementptr ptr, ptr %t3763, i32 0
  store ptr %t3764, ptr %t3765
  call void @__inc_ref(ptr %t6)
  %t3766 = getelementptr ptr, ptr %t3763, i32 1
  store ptr %t6, ptr %t3766
  call void @__free_recursive(ptr %t6)
  store ptr %t3762, ptr %t3
  store ptr %t3763, ptr %t4
  br label %tco.loop.0
tco.case.arm.210.3767:
  %t3768 = getelementptr ptr, ptr %t5, i32 1
  %t3769 = load ptr, ptr %t3768
  %t3770 = getelementptr ptr, ptr %t5, i32 2
  %t3771 = load ptr, ptr %t3770
  %t3772 = getelementptr i8, ptr %t5, i64 -8
  %t3773 = load i32, ptr %t3772
  %t3774 = icmp eq i32 %t3773, 1
  br i1 %t3774, label %reuse.in_place.3775, label %reuse.copy.3776
reuse.in_place.3775:
  %t3778 = inttoptr i64 130 to ptr
  %t3779 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3778, ptr %t3779
  br label %reuse.join.3777
reuse.copy.3776:
  %t3780 = call ptr @__alloc(i64 24, i32 2)
  %t3781 = inttoptr i64 130 to ptr
  %t3782 = getelementptr ptr, ptr %t3780, i32 0
  store ptr %t3781, ptr %t3782
  call void @__inc_ref(ptr %t3769)
  %t3783 = getelementptr ptr, ptr %t3780, i32 1
  store ptr %t3769, ptr %t3783
  call void @__inc_ref(ptr %t3771)
  %t3784 = getelementptr ptr, ptr %t3780, i32 2
  store ptr %t3771, ptr %t3784
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3777
reuse.join.3777:
  %t3785 = phi ptr [ %t5, %reuse.in_place.3775 ], [ %t3780, %reuse.copy.3776 ]
  %t3786 = call ptr @__alloc(i64 16, i32 1)
  %t3787 = inttoptr i64 419 to ptr
  %t3788 = getelementptr ptr, ptr %t3786, i32 0
  store ptr %t3787, ptr %t3788
  call void @__inc_ref(ptr %t6)
  %t3789 = getelementptr ptr, ptr %t3786, i32 1
  store ptr %t6, ptr %t3789
  call void @__free_recursive(ptr %t6)
  store ptr %t3785, ptr %t3
  store ptr %t3786, ptr %t4
  br label %tco.loop.0
tco.case.arm.211.3790:
  %t3791 = getelementptr ptr, ptr %t5, i32 1
  %t3792 = load ptr, ptr %t3791
  %t3793 = getelementptr ptr, ptr %t5, i32 2
  %t3794 = load ptr, ptr %t3793
  %t3795 = getelementptr i8, ptr %t5, i64 -8
  %t3796 = load i32, ptr %t3795
  %t3797 = icmp eq i32 %t3796, 1
  br i1 %t3797, label %reuse.in_place.3798, label %reuse.copy.3799
reuse.in_place.3798:
  %t3801 = inttoptr i64 130 to ptr
  %t3802 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3801, ptr %t3802
  br label %reuse.join.3800
reuse.copy.3799:
  %t3803 = call ptr @__alloc(i64 24, i32 2)
  %t3804 = inttoptr i64 130 to ptr
  %t3805 = getelementptr ptr, ptr %t3803, i32 0
  store ptr %t3804, ptr %t3805
  call void @__inc_ref(ptr %t3792)
  %t3806 = getelementptr ptr, ptr %t3803, i32 1
  store ptr %t3792, ptr %t3806
  call void @__inc_ref(ptr %t3794)
  %t3807 = getelementptr ptr, ptr %t3803, i32 2
  store ptr %t3794, ptr %t3807
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3800
reuse.join.3800:
  %t3808 = phi ptr [ %t5, %reuse.in_place.3798 ], [ %t3803, %reuse.copy.3799 ]
  %t3809 = call ptr @__alloc(i64 16, i32 1)
  %t3810 = inttoptr i64 420 to ptr
  %t3811 = getelementptr ptr, ptr %t3809, i32 0
  store ptr %t3810, ptr %t3811
  call void @__inc_ref(ptr %t6)
  %t3812 = getelementptr ptr, ptr %t3809, i32 1
  store ptr %t6, ptr %t3812
  call void @__free_recursive(ptr %t6)
  store ptr %t3808, ptr %t3
  store ptr %t3809, ptr %t4
  br label %tco.loop.0
tco.case.arm.212.3813:
  %t3814 = getelementptr ptr, ptr %t5, i32 1
  %t3815 = load ptr, ptr %t3814
  %t3816 = getelementptr ptr, ptr %t5, i32 2
  %t3817 = load ptr, ptr %t3816
  %t3818 = getelementptr i8, ptr %t5, i64 -8
  %t3819 = load i32, ptr %t3818
  %t3820 = icmp eq i32 %t3819, 1
  br i1 %t3820, label %reuse.in_place.3821, label %reuse.copy.3822
reuse.in_place.3821:
  %t3824 = inttoptr i64 130 to ptr
  %t3825 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3824, ptr %t3825
  br label %reuse.join.3823
reuse.copy.3822:
  %t3826 = call ptr @__alloc(i64 24, i32 2)
  %t3827 = inttoptr i64 130 to ptr
  %t3828 = getelementptr ptr, ptr %t3826, i32 0
  store ptr %t3827, ptr %t3828
  call void @__inc_ref(ptr %t3815)
  %t3829 = getelementptr ptr, ptr %t3826, i32 1
  store ptr %t3815, ptr %t3829
  call void @__inc_ref(ptr %t3817)
  %t3830 = getelementptr ptr, ptr %t3826, i32 2
  store ptr %t3817, ptr %t3830
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3823
reuse.join.3823:
  %t3831 = phi ptr [ %t5, %reuse.in_place.3821 ], [ %t3826, %reuse.copy.3822 ]
  %t3832 = call ptr @__alloc(i64 16, i32 1)
  %t3833 = inttoptr i64 421 to ptr
  %t3834 = getelementptr ptr, ptr %t3832, i32 0
  store ptr %t3833, ptr %t3834
  call void @__inc_ref(ptr %t6)
  %t3835 = getelementptr ptr, ptr %t3832, i32 1
  store ptr %t6, ptr %t3835
  call void @__free_recursive(ptr %t6)
  store ptr %t3831, ptr %t3
  store ptr %t3832, ptr %t4
  br label %tco.loop.0
tco.case.arm.213.3836:
  %t3837 = getelementptr ptr, ptr %t5, i32 1
  %t3838 = load ptr, ptr %t3837
  %t3839 = getelementptr ptr, ptr %t5, i32 2
  %t3840 = load ptr, ptr %t3839
  %t3841 = getelementptr i8, ptr %t5, i64 -8
  %t3842 = load i32, ptr %t3841
  %t3843 = icmp eq i32 %t3842, 1
  br i1 %t3843, label %reuse.in_place.3844, label %reuse.copy.3845
reuse.in_place.3844:
  %t3847 = inttoptr i64 130 to ptr
  %t3848 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3847, ptr %t3848
  br label %reuse.join.3846
reuse.copy.3845:
  %t3849 = call ptr @__alloc(i64 24, i32 2)
  %t3850 = inttoptr i64 130 to ptr
  %t3851 = getelementptr ptr, ptr %t3849, i32 0
  store ptr %t3850, ptr %t3851
  call void @__inc_ref(ptr %t3838)
  %t3852 = getelementptr ptr, ptr %t3849, i32 1
  store ptr %t3838, ptr %t3852
  call void @__inc_ref(ptr %t3840)
  %t3853 = getelementptr ptr, ptr %t3849, i32 2
  store ptr %t3840, ptr %t3853
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3846
reuse.join.3846:
  %t3854 = phi ptr [ %t5, %reuse.in_place.3844 ], [ %t3849, %reuse.copy.3845 ]
  %t3855 = call ptr @__alloc(i64 16, i32 1)
  %t3856 = inttoptr i64 422 to ptr
  %t3857 = getelementptr ptr, ptr %t3855, i32 0
  store ptr %t3856, ptr %t3857
  call void @__inc_ref(ptr %t6)
  %t3858 = getelementptr ptr, ptr %t3855, i32 1
  store ptr %t6, ptr %t3858
  call void @__free_recursive(ptr %t6)
  store ptr %t3854, ptr %t3
  store ptr %t3855, ptr %t4
  br label %tco.loop.0
tco.case.arm.214.3859:
  %t3860 = getelementptr ptr, ptr %t5, i32 1
  %t3861 = load ptr, ptr %t3860
  %t3862 = getelementptr ptr, ptr %t5, i32 2
  %t3863 = load ptr, ptr %t3862
  %t3864 = getelementptr i8, ptr %t5, i64 -8
  %t3865 = load i32, ptr %t3864
  %t3866 = icmp eq i32 %t3865, 1
  br i1 %t3866, label %reuse.in_place.3867, label %reuse.copy.3868
reuse.in_place.3867:
  %t3870 = inttoptr i64 130 to ptr
  %t3871 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3870, ptr %t3871
  br label %reuse.join.3869
reuse.copy.3868:
  %t3872 = call ptr @__alloc(i64 24, i32 2)
  %t3873 = inttoptr i64 130 to ptr
  %t3874 = getelementptr ptr, ptr %t3872, i32 0
  store ptr %t3873, ptr %t3874
  call void @__inc_ref(ptr %t3861)
  %t3875 = getelementptr ptr, ptr %t3872, i32 1
  store ptr %t3861, ptr %t3875
  call void @__inc_ref(ptr %t3863)
  %t3876 = getelementptr ptr, ptr %t3872, i32 2
  store ptr %t3863, ptr %t3876
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3869
reuse.join.3869:
  %t3877 = phi ptr [ %t5, %reuse.in_place.3867 ], [ %t3872, %reuse.copy.3868 ]
  %t3878 = call ptr @__alloc(i64 16, i32 1)
  %t3879 = inttoptr i64 423 to ptr
  %t3880 = getelementptr ptr, ptr %t3878, i32 0
  store ptr %t3879, ptr %t3880
  call void @__inc_ref(ptr %t6)
  %t3881 = getelementptr ptr, ptr %t3878, i32 1
  store ptr %t6, ptr %t3881
  call void @__free_recursive(ptr %t6)
  store ptr %t3877, ptr %t3
  store ptr %t3878, ptr %t4
  br label %tco.loop.0
tco.case.arm.215.3882:
  %t3883 = getelementptr ptr, ptr %t5, i32 1
  %t3884 = load ptr, ptr %t3883
  %t3885 = getelementptr ptr, ptr %t5, i32 2
  %t3886 = load ptr, ptr %t3885
  %t3887 = getelementptr i8, ptr %t5, i64 -8
  %t3888 = load i32, ptr %t3887
  %t3889 = icmp eq i32 %t3888, 1
  br i1 %t3889, label %reuse.in_place.3890, label %reuse.copy.3891
reuse.in_place.3890:
  %t3893 = inttoptr i64 130 to ptr
  %t3894 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3893, ptr %t3894
  br label %reuse.join.3892
reuse.copy.3891:
  %t3895 = call ptr @__alloc(i64 24, i32 2)
  %t3896 = inttoptr i64 130 to ptr
  %t3897 = getelementptr ptr, ptr %t3895, i32 0
  store ptr %t3896, ptr %t3897
  call void @__inc_ref(ptr %t3884)
  %t3898 = getelementptr ptr, ptr %t3895, i32 1
  store ptr %t3884, ptr %t3898
  call void @__inc_ref(ptr %t3886)
  %t3899 = getelementptr ptr, ptr %t3895, i32 2
  store ptr %t3886, ptr %t3899
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3892
reuse.join.3892:
  %t3900 = phi ptr [ %t5, %reuse.in_place.3890 ], [ %t3895, %reuse.copy.3891 ]
  %t3901 = call ptr @__alloc(i64 16, i32 1)
  %t3902 = inttoptr i64 424 to ptr
  %t3903 = getelementptr ptr, ptr %t3901, i32 0
  store ptr %t3902, ptr %t3903
  call void @__inc_ref(ptr %t6)
  %t3904 = getelementptr ptr, ptr %t3901, i32 1
  store ptr %t6, ptr %t3904
  call void @__free_recursive(ptr %t6)
  store ptr %t3900, ptr %t3
  store ptr %t3901, ptr %t4
  br label %tco.loop.0
tco.case.arm.216.3905:
  %t3906 = getelementptr ptr, ptr %t5, i32 1
  %t3907 = load ptr, ptr %t3906
  %t3908 = getelementptr ptr, ptr %t5, i32 2
  %t3909 = load ptr, ptr %t3908
  %t3910 = getelementptr i8, ptr %t5, i64 -8
  %t3911 = load i32, ptr %t3910
  %t3912 = icmp eq i32 %t3911, 1
  br i1 %t3912, label %reuse.in_place.3913, label %reuse.copy.3914
reuse.in_place.3913:
  %t3916 = inttoptr i64 130 to ptr
  %t3917 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3916, ptr %t3917
  br label %reuse.join.3915
reuse.copy.3914:
  %t3918 = call ptr @__alloc(i64 24, i32 2)
  %t3919 = inttoptr i64 130 to ptr
  %t3920 = getelementptr ptr, ptr %t3918, i32 0
  store ptr %t3919, ptr %t3920
  call void @__inc_ref(ptr %t3907)
  %t3921 = getelementptr ptr, ptr %t3918, i32 1
  store ptr %t3907, ptr %t3921
  call void @__inc_ref(ptr %t3909)
  %t3922 = getelementptr ptr, ptr %t3918, i32 2
  store ptr %t3909, ptr %t3922
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3915
reuse.join.3915:
  %t3923 = phi ptr [ %t5, %reuse.in_place.3913 ], [ %t3918, %reuse.copy.3914 ]
  %t3924 = call ptr @__alloc(i64 16, i32 1)
  %t3925 = inttoptr i64 425 to ptr
  %t3926 = getelementptr ptr, ptr %t3924, i32 0
  store ptr %t3925, ptr %t3926
  call void @__inc_ref(ptr %t6)
  %t3927 = getelementptr ptr, ptr %t3924, i32 1
  store ptr %t6, ptr %t3927
  call void @__free_recursive(ptr %t6)
  store ptr %t3923, ptr %t3
  store ptr %t3924, ptr %t4
  br label %tco.loop.0
tco.case.arm.217.3928:
  %t3929 = getelementptr ptr, ptr %t5, i32 1
  %t3930 = load ptr, ptr %t3929
  %t3931 = getelementptr ptr, ptr %t5, i32 2
  %t3932 = load ptr, ptr %t3931
  %t3933 = getelementptr i8, ptr %t5, i64 -8
  %t3934 = load i32, ptr %t3933
  %t3935 = icmp eq i32 %t3934, 1
  br i1 %t3935, label %reuse.in_place.3936, label %reuse.copy.3937
reuse.in_place.3936:
  %t3939 = inttoptr i64 130 to ptr
  %t3940 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3939, ptr %t3940
  br label %reuse.join.3938
reuse.copy.3937:
  %t3941 = call ptr @__alloc(i64 24, i32 2)
  %t3942 = inttoptr i64 130 to ptr
  %t3943 = getelementptr ptr, ptr %t3941, i32 0
  store ptr %t3942, ptr %t3943
  call void @__inc_ref(ptr %t3930)
  %t3944 = getelementptr ptr, ptr %t3941, i32 1
  store ptr %t3930, ptr %t3944
  call void @__inc_ref(ptr %t3932)
  %t3945 = getelementptr ptr, ptr %t3941, i32 2
  store ptr %t3932, ptr %t3945
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3938
reuse.join.3938:
  %t3946 = phi ptr [ %t5, %reuse.in_place.3936 ], [ %t3941, %reuse.copy.3937 ]
  %t3947 = call ptr @__alloc(i64 16, i32 1)
  %t3948 = inttoptr i64 426 to ptr
  %t3949 = getelementptr ptr, ptr %t3947, i32 0
  store ptr %t3948, ptr %t3949
  call void @__inc_ref(ptr %t6)
  %t3950 = getelementptr ptr, ptr %t3947, i32 1
  store ptr %t6, ptr %t3950
  call void @__free_recursive(ptr %t6)
  store ptr %t3946, ptr %t3
  store ptr %t3947, ptr %t4
  br label %tco.loop.0
tco.case.arm.218.3951:
  %t3952 = getelementptr ptr, ptr %t5, i32 1
  %t3953 = load ptr, ptr %t3952
  %t3954 = getelementptr ptr, ptr %t5, i32 2
  %t3955 = load ptr, ptr %t3954
  %t3956 = getelementptr i8, ptr %t5, i64 -8
  %t3957 = load i32, ptr %t3956
  %t3958 = icmp eq i32 %t3957, 1
  br i1 %t3958, label %reuse.in_place.3959, label %reuse.copy.3960
reuse.in_place.3959:
  %t3962 = inttoptr i64 130 to ptr
  %t3963 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3962, ptr %t3963
  br label %reuse.join.3961
reuse.copy.3960:
  %t3964 = call ptr @__alloc(i64 24, i32 2)
  %t3965 = inttoptr i64 130 to ptr
  %t3966 = getelementptr ptr, ptr %t3964, i32 0
  store ptr %t3965, ptr %t3966
  call void @__inc_ref(ptr %t3953)
  %t3967 = getelementptr ptr, ptr %t3964, i32 1
  store ptr %t3953, ptr %t3967
  call void @__inc_ref(ptr %t3955)
  %t3968 = getelementptr ptr, ptr %t3964, i32 2
  store ptr %t3955, ptr %t3968
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3961
reuse.join.3961:
  %t3969 = phi ptr [ %t5, %reuse.in_place.3959 ], [ %t3964, %reuse.copy.3960 ]
  %t3970 = call ptr @__alloc(i64 16, i32 1)
  %t3971 = inttoptr i64 427 to ptr
  %t3972 = getelementptr ptr, ptr %t3970, i32 0
  store ptr %t3971, ptr %t3972
  call void @__inc_ref(ptr %t6)
  %t3973 = getelementptr ptr, ptr %t3970, i32 1
  store ptr %t6, ptr %t3973
  call void @__free_recursive(ptr %t6)
  store ptr %t3969, ptr %t3
  store ptr %t3970, ptr %t4
  br label %tco.loop.0
tco.case.arm.221.3974:
  %t3975 = getelementptr ptr, ptr %t5, i32 1
  %t3976 = load ptr, ptr %t3975
  %t3977 = getelementptr ptr, ptr %t5, i32 2
  %t3978 = load ptr, ptr %t3977
  %t3979 = getelementptr i8, ptr %t5, i64 -8
  %t3980 = load i32, ptr %t3979
  %t3981 = icmp eq i32 %t3980, 1
  br i1 %t3981, label %reuse.in_place.3982, label %reuse.copy.3983
reuse.in_place.3982:
  %t3985 = inttoptr i64 130 to ptr
  %t3986 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t3985, ptr %t3986
  br label %reuse.join.3984
reuse.copy.3983:
  %t3987 = call ptr @__alloc(i64 24, i32 2)
  %t3988 = inttoptr i64 130 to ptr
  %t3989 = getelementptr ptr, ptr %t3987, i32 0
  store ptr %t3988, ptr %t3989
  call void @__inc_ref(ptr %t3976)
  %t3990 = getelementptr ptr, ptr %t3987, i32 1
  store ptr %t3976, ptr %t3990
  call void @__inc_ref(ptr %t3978)
  %t3991 = getelementptr ptr, ptr %t3987, i32 2
  store ptr %t3978, ptr %t3991
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.3984
reuse.join.3984:
  %t3992 = phi ptr [ %t5, %reuse.in_place.3982 ], [ %t3987, %reuse.copy.3983 ]
  %t3993 = call ptr @__alloc(i64 16, i32 1)
  %t3994 = inttoptr i64 430 to ptr
  %t3995 = getelementptr ptr, ptr %t3993, i32 0
  store ptr %t3994, ptr %t3995
  call void @__inc_ref(ptr %t6)
  %t3996 = getelementptr ptr, ptr %t3993, i32 1
  store ptr %t6, ptr %t3996
  call void @__free_recursive(ptr %t6)
  store ptr %t3992, ptr %t3
  store ptr %t3993, ptr %t4
  br label %tco.loop.0
tco.case.arm.222.3997:
  %t3998 = getelementptr ptr, ptr %t5, i32 1
  %t3999 = load ptr, ptr %t3998
  %t4000 = getelementptr ptr, ptr %t5, i32 2
  %t4001 = load ptr, ptr %t4000
  %t4002 = getelementptr i8, ptr %t5, i64 -8
  %t4003 = load i32, ptr %t4002
  %t4004 = icmp eq i32 %t4003, 1
  br i1 %t4004, label %reuse.in_place.4005, label %reuse.copy.4006
reuse.in_place.4005:
  %t4008 = inttoptr i64 130 to ptr
  %t4009 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t4008, ptr %t4009
  br label %reuse.join.4007
reuse.copy.4006:
  %t4010 = call ptr @__alloc(i64 24, i32 2)
  %t4011 = inttoptr i64 130 to ptr
  %t4012 = getelementptr ptr, ptr %t4010, i32 0
  store ptr %t4011, ptr %t4012
  call void @__inc_ref(ptr %t3999)
  %t4013 = getelementptr ptr, ptr %t4010, i32 1
  store ptr %t3999, ptr %t4013
  call void @__inc_ref(ptr %t4001)
  %t4014 = getelementptr ptr, ptr %t4010, i32 2
  store ptr %t4001, ptr %t4014
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.4007
reuse.join.4007:
  %t4015 = phi ptr [ %t5, %reuse.in_place.4005 ], [ %t4010, %reuse.copy.4006 ]
  %t4016 = call ptr @__alloc(i64 16, i32 1)
  %t4017 = inttoptr i64 431 to ptr
  %t4018 = getelementptr ptr, ptr %t4016, i32 0
  store ptr %t4017, ptr %t4018
  call void @__inc_ref(ptr %t6)
  %t4019 = getelementptr ptr, ptr %t4016, i32 1
  store ptr %t6, ptr %t4019
  call void @__free_recursive(ptr %t6)
  store ptr %t4015, ptr %t3
  store ptr %t4016, ptr %t4
  br label %tco.loop.0
tco.case.arm.225.4020:
  %t4021 = getelementptr ptr, ptr %t5, i32 1
  %t4022 = load ptr, ptr %t4021
  %t4023 = getelementptr ptr, ptr %t5, i32 2
  %t4024 = load ptr, ptr %t4023
  %t4025 = getelementptr i8, ptr %t5, i64 -8
  %t4026 = load i32, ptr %t4025
  %t4027 = icmp eq i32 %t4026, 1
  br i1 %t4027, label %reuse.in_place.4028, label %reuse.copy.4029
reuse.in_place.4028:
  %t4031 = inttoptr i64 130 to ptr
  %t4032 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t4031, ptr %t4032
  br label %reuse.join.4030
reuse.copy.4029:
  %t4033 = call ptr @__alloc(i64 24, i32 2)
  %t4034 = inttoptr i64 130 to ptr
  %t4035 = getelementptr ptr, ptr %t4033, i32 0
  store ptr %t4034, ptr %t4035
  call void @__inc_ref(ptr %t4022)
  %t4036 = getelementptr ptr, ptr %t4033, i32 1
  store ptr %t4022, ptr %t4036
  call void @__inc_ref(ptr %t4024)
  %t4037 = getelementptr ptr, ptr %t4033, i32 2
  store ptr %t4024, ptr %t4037
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.4030
reuse.join.4030:
  %t4038 = phi ptr [ %t5, %reuse.in_place.4028 ], [ %t4033, %reuse.copy.4029 ]
  %t4039 = call ptr @__alloc(i64 16, i32 1)
  %t4040 = inttoptr i64 434 to ptr
  %t4041 = getelementptr ptr, ptr %t4039, i32 0
  store ptr %t4040, ptr %t4041
  call void @__inc_ref(ptr %t6)
  %t4042 = getelementptr ptr, ptr %t4039, i32 1
  store ptr %t6, ptr %t4042
  call void @__free_recursive(ptr %t6)
  store ptr %t4038, ptr %t3
  store ptr %t4039, ptr %t4
  br label %tco.loop.0
tco.case.arm.226.4043:
  %t4044 = getelementptr ptr, ptr %t5, i32 1
  %t4045 = load ptr, ptr %t4044
  %t4046 = getelementptr ptr, ptr %t5, i32 2
  %t4047 = load ptr, ptr %t4046
  %t4048 = getelementptr i8, ptr %t5, i64 -8
  %t4049 = load i32, ptr %t4048
  %t4050 = icmp eq i32 %t4049, 1
  br i1 %t4050, label %reuse.in_place.4051, label %reuse.copy.4052
reuse.in_place.4051:
  %t4054 = inttoptr i64 130 to ptr
  %t4055 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t4054, ptr %t4055
  br label %reuse.join.4053
reuse.copy.4052:
  %t4056 = call ptr @__alloc(i64 24, i32 2)
  %t4057 = inttoptr i64 130 to ptr
  %t4058 = getelementptr ptr, ptr %t4056, i32 0
  store ptr %t4057, ptr %t4058
  call void @__inc_ref(ptr %t4045)
  %t4059 = getelementptr ptr, ptr %t4056, i32 1
  store ptr %t4045, ptr %t4059
  call void @__inc_ref(ptr %t4047)
  %t4060 = getelementptr ptr, ptr %t4056, i32 2
  store ptr %t4047, ptr %t4060
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.4053
reuse.join.4053:
  %t4061 = phi ptr [ %t5, %reuse.in_place.4051 ], [ %t4056, %reuse.copy.4052 ]
  %t4062 = call ptr @__alloc(i64 16, i32 1)
  %t4063 = inttoptr i64 435 to ptr
  %t4064 = getelementptr ptr, ptr %t4062, i32 0
  store ptr %t4063, ptr %t4064
  call void @__inc_ref(ptr %t6)
  %t4065 = getelementptr ptr, ptr %t4062, i32 1
  store ptr %t6, ptr %t4065
  call void @__free_recursive(ptr %t6)
  store ptr %t4061, ptr %t3
  store ptr %t4062, ptr %t4
  br label %tco.loop.0
tco.case.arm.229.4066:
  %t4067 = getelementptr ptr, ptr %t5, i32 1
  %t4068 = load ptr, ptr %t4067
  %t4069 = getelementptr ptr, ptr %t5, i32 2
  %t4070 = load ptr, ptr %t4069
  %t4071 = getelementptr i8, ptr %t5, i64 -8
  %t4072 = load i32, ptr %t4071
  %t4073 = icmp eq i32 %t4072, 1
  br i1 %t4073, label %reuse.in_place.4074, label %reuse.copy.4075
reuse.in_place.4074:
  %t4077 = inttoptr i64 130 to ptr
  %t4078 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t4077, ptr %t4078
  br label %reuse.join.4076
reuse.copy.4075:
  %t4079 = call ptr @__alloc(i64 24, i32 2)
  %t4080 = inttoptr i64 130 to ptr
  %t4081 = getelementptr ptr, ptr %t4079, i32 0
  store ptr %t4080, ptr %t4081
  call void @__inc_ref(ptr %t4068)
  %t4082 = getelementptr ptr, ptr %t4079, i32 1
  store ptr %t4068, ptr %t4082
  call void @__inc_ref(ptr %t4070)
  %t4083 = getelementptr ptr, ptr %t4079, i32 2
  store ptr %t4070, ptr %t4083
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.4076
reuse.join.4076:
  %t4084 = phi ptr [ %t5, %reuse.in_place.4074 ], [ %t4079, %reuse.copy.4075 ]
  %t4085 = call ptr @__alloc(i64 16, i32 1)
  %t4086 = inttoptr i64 438 to ptr
  %t4087 = getelementptr ptr, ptr %t4085, i32 0
  store ptr %t4086, ptr %t4087
  call void @__inc_ref(ptr %t6)
  %t4088 = getelementptr ptr, ptr %t4085, i32 1
  store ptr %t6, ptr %t4088
  call void @__free_recursive(ptr %t6)
  store ptr %t4084, ptr %t3
  store ptr %t4085, ptr %t4
  br label %tco.loop.0
tco.case.arm.230.4089:
  %t4090 = getelementptr ptr, ptr %t5, i32 1
  %t4091 = load ptr, ptr %t4090
  %t4092 = getelementptr ptr, ptr %t5, i32 2
  %t4093 = load ptr, ptr %t4092
  %t4094 = getelementptr i8, ptr %t5, i64 -8
  %t4095 = load i32, ptr %t4094
  %t4096 = icmp eq i32 %t4095, 1
  br i1 %t4096, label %reuse.in_place.4097, label %reuse.copy.4098
reuse.in_place.4097:
  %t4100 = inttoptr i64 130 to ptr
  %t4101 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t4100, ptr %t4101
  br label %reuse.join.4099
reuse.copy.4098:
  %t4102 = call ptr @__alloc(i64 24, i32 2)
  %t4103 = inttoptr i64 130 to ptr
  %t4104 = getelementptr ptr, ptr %t4102, i32 0
  store ptr %t4103, ptr %t4104
  call void @__inc_ref(ptr %t4091)
  %t4105 = getelementptr ptr, ptr %t4102, i32 1
  store ptr %t4091, ptr %t4105
  call void @__inc_ref(ptr %t4093)
  %t4106 = getelementptr ptr, ptr %t4102, i32 2
  store ptr %t4093, ptr %t4106
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.4099
reuse.join.4099:
  %t4107 = phi ptr [ %t5, %reuse.in_place.4097 ], [ %t4102, %reuse.copy.4098 ]
  %t4108 = call ptr @__alloc(i64 16, i32 1)
  %t4109 = inttoptr i64 439 to ptr
  %t4110 = getelementptr ptr, ptr %t4108, i32 0
  store ptr %t4109, ptr %t4110
  call void @__inc_ref(ptr %t6)
  %t4111 = getelementptr ptr, ptr %t4108, i32 1
  store ptr %t6, ptr %t4111
  call void @__free_recursive(ptr %t6)
  store ptr %t4107, ptr %t3
  store ptr %t4108, ptr %t4
  br label %tco.loop.0
tco.case.arm.231.4112:
  %t4113 = getelementptr ptr, ptr %t5, i32 1
  %t4114 = load ptr, ptr %t4113
  %t4115 = getelementptr ptr, ptr %t5, i32 2
  %t4116 = load ptr, ptr %t4115
  %t4117 = getelementptr i8, ptr %t5, i64 -8
  %t4118 = load i32, ptr %t4117
  %t4119 = icmp eq i32 %t4118, 1
  br i1 %t4119, label %reuse.in_place.4120, label %reuse.copy.4121
reuse.in_place.4120:
  %t4123 = inttoptr i64 130 to ptr
  %t4124 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t4123, ptr %t4124
  br label %reuse.join.4122
reuse.copy.4121:
  %t4125 = call ptr @__alloc(i64 24, i32 2)
  %t4126 = inttoptr i64 130 to ptr
  %t4127 = getelementptr ptr, ptr %t4125, i32 0
  store ptr %t4126, ptr %t4127
  call void @__inc_ref(ptr %t4114)
  %t4128 = getelementptr ptr, ptr %t4125, i32 1
  store ptr %t4114, ptr %t4128
  call void @__inc_ref(ptr %t4116)
  %t4129 = getelementptr ptr, ptr %t4125, i32 2
  store ptr %t4116, ptr %t4129
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.4122
reuse.join.4122:
  %t4130 = phi ptr [ %t5, %reuse.in_place.4120 ], [ %t4125, %reuse.copy.4121 ]
  %t4131 = call ptr @__alloc(i64 16, i32 1)
  %t4132 = inttoptr i64 440 to ptr
  %t4133 = getelementptr ptr, ptr %t4131, i32 0
  store ptr %t4132, ptr %t4133
  call void @__inc_ref(ptr %t6)
  %t4134 = getelementptr ptr, ptr %t4131, i32 1
  store ptr %t6, ptr %t4134
  call void @__free_recursive(ptr %t6)
  store ptr %t4130, ptr %t3
  store ptr %t4131, ptr %t4
  br label %tco.loop.0
tco.case.arm.232.4135:
  %t4136 = getelementptr ptr, ptr %t5, i32 1
  %t4137 = load ptr, ptr %t4136
  %t4138 = getelementptr ptr, ptr %t5, i32 2
  %t4139 = load ptr, ptr %t4138
  %t4140 = getelementptr i8, ptr %t5, i64 -8
  %t4141 = load i32, ptr %t4140
  %t4142 = icmp eq i32 %t4141, 1
  br i1 %t4142, label %reuse.in_place.4143, label %reuse.copy.4144
reuse.in_place.4143:
  %t4146 = inttoptr i64 130 to ptr
  %t4147 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t4146, ptr %t4147
  br label %reuse.join.4145
reuse.copy.4144:
  %t4148 = call ptr @__alloc(i64 24, i32 2)
  %t4149 = inttoptr i64 130 to ptr
  %t4150 = getelementptr ptr, ptr %t4148, i32 0
  store ptr %t4149, ptr %t4150
  call void @__inc_ref(ptr %t4137)
  %t4151 = getelementptr ptr, ptr %t4148, i32 1
  store ptr %t4137, ptr %t4151
  call void @__inc_ref(ptr %t4139)
  %t4152 = getelementptr ptr, ptr %t4148, i32 2
  store ptr %t4139, ptr %t4152
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.4145
reuse.join.4145:
  %t4153 = phi ptr [ %t5, %reuse.in_place.4143 ], [ %t4148, %reuse.copy.4144 ]
  %t4154 = call ptr @__alloc(i64 16, i32 1)
  %t4155 = inttoptr i64 441 to ptr
  %t4156 = getelementptr ptr, ptr %t4154, i32 0
  store ptr %t4155, ptr %t4156
  call void @__inc_ref(ptr %t6)
  %t4157 = getelementptr ptr, ptr %t4154, i32 1
  store ptr %t6, ptr %t4157
  call void @__free_recursive(ptr %t6)
  store ptr %t4153, ptr %t3
  store ptr %t4154, ptr %t4
  br label %tco.loop.0
tco.case.arm.233.4158:
  %t4159 = getelementptr ptr, ptr %t5, i32 1
  %t4160 = load ptr, ptr %t4159
  %t4161 = getelementptr ptr, ptr %t5, i32 2
  %t4162 = load ptr, ptr %t4161
  %t4163 = getelementptr i8, ptr %t5, i64 -8
  %t4164 = load i32, ptr %t4163
  %t4165 = icmp eq i32 %t4164, 1
  br i1 %t4165, label %reuse.in_place.4166, label %reuse.copy.4167
reuse.in_place.4166:
  %t4169 = inttoptr i64 130 to ptr
  %t4170 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t4169, ptr %t4170
  br label %reuse.join.4168
reuse.copy.4167:
  %t4171 = call ptr @__alloc(i64 24, i32 2)
  %t4172 = inttoptr i64 130 to ptr
  %t4173 = getelementptr ptr, ptr %t4171, i32 0
  store ptr %t4172, ptr %t4173
  call void @__inc_ref(ptr %t4160)
  %t4174 = getelementptr ptr, ptr %t4171, i32 1
  store ptr %t4160, ptr %t4174
  call void @__inc_ref(ptr %t4162)
  %t4175 = getelementptr ptr, ptr %t4171, i32 2
  store ptr %t4162, ptr %t4175
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.4168
reuse.join.4168:
  %t4176 = phi ptr [ %t5, %reuse.in_place.4166 ], [ %t4171, %reuse.copy.4167 ]
  %t4177 = call ptr @__alloc(i64 16, i32 1)
  %t4178 = inttoptr i64 442 to ptr
  %t4179 = getelementptr ptr, ptr %t4177, i32 0
  store ptr %t4178, ptr %t4179
  call void @__inc_ref(ptr %t6)
  %t4180 = getelementptr ptr, ptr %t4177, i32 1
  store ptr %t6, ptr %t4180
  call void @__free_recursive(ptr %t6)
  store ptr %t4176, ptr %t3
  store ptr %t4177, ptr %t4
  br label %tco.loop.0
tco.case.arm.234.4181:
  %t4182 = getelementptr ptr, ptr %t5, i32 1
  %t4183 = load ptr, ptr %t4182
  %t4184 = getelementptr ptr, ptr %t5, i32 2
  %t4185 = load ptr, ptr %t4184
  %t4186 = getelementptr i8, ptr %t5, i64 -8
  %t4187 = load i32, ptr %t4186
  %t4188 = icmp eq i32 %t4187, 1
  br i1 %t4188, label %reuse.in_place.4189, label %reuse.copy.4190
reuse.in_place.4189:
  %t4192 = inttoptr i64 130 to ptr
  %t4193 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t4192, ptr %t4193
  br label %reuse.join.4191
reuse.copy.4190:
  %t4194 = call ptr @__alloc(i64 24, i32 2)
  %t4195 = inttoptr i64 130 to ptr
  %t4196 = getelementptr ptr, ptr %t4194, i32 0
  store ptr %t4195, ptr %t4196
  call void @__inc_ref(ptr %t4183)
  %t4197 = getelementptr ptr, ptr %t4194, i32 1
  store ptr %t4183, ptr %t4197
  call void @__inc_ref(ptr %t4185)
  %t4198 = getelementptr ptr, ptr %t4194, i32 2
  store ptr %t4185, ptr %t4198
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.4191
reuse.join.4191:
  %t4199 = phi ptr [ %t5, %reuse.in_place.4189 ], [ %t4194, %reuse.copy.4190 ]
  %t4200 = call ptr @__alloc(i64 16, i32 1)
  %t4201 = inttoptr i64 443 to ptr
  %t4202 = getelementptr ptr, ptr %t4200, i32 0
  store ptr %t4201, ptr %t4202
  call void @__inc_ref(ptr %t6)
  %t4203 = getelementptr ptr, ptr %t4200, i32 1
  store ptr %t6, ptr %t4203
  call void @__free_recursive(ptr %t6)
  store ptr %t4199, ptr %t3
  store ptr %t4200, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t4204 = load ptr, ptr %t2
  ret ptr %t4204
}

define internal ptr @v__apply1(ptr %v__cl, ptr %v__arg0) {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 130 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  call void @__inc_ref(ptr %v__cl)
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v__cl, ptr %t3
  call void @__inc_ref(ptr %v__arg0)
  %t4 = getelementptr ptr, ptr %t0, i32 2
  store ptr %v__arg0, ptr %t4
  %t5 = call ptr @v__scc__apply1__df__lam_10_15__df__lam_10_24__df__lam_10_27__df__lam_10_30__df__lam_10_36__df__lam_10_42__df__lam_10_48__df__lam_11_16__df__lam_11_25__df__lam_11_28__df__lam_11_31__df__lam_11_37__df__lam_11_43__df__lam_11_49__df__lam_4_102__df__lam_4_105__df__lam_4_108__df__lam_4_111__df__lam_4_114__df__lam_4_117__df__lam_4_120__df__lam_4_123__df__lam_4_126__df__lam_4_18__df__lam_4_54__df__lam_4_57__df__lam_4_60__df__lam_4_63__df__lam_4_66__df__lam_4_69__df__lam_4_72__df__lam_4_75__df__lam_4_78__df__lam_4_81__df__lam_4_84__df__lam_4_87__df__lam_4_90__df__lam_4_93__df__lam_4_96__df__lam_4_99__df__lam_42_33__df__lam_43_34__df__lam_5_100__df__lam_5_103__df__lam_5_106__df__lam_5_109__df__lam_5_112__df__lam_5_115__df__lam_5_118__df__lam_5_121__df__lam_5_124__df__lam_5_127__df__lam_5_19__df__lam_5_55__df__lam_5_58__df__lam_5_61__df__lam_5_64__df__lam_5_67__df__lam_5_70__df__lam_5_73__df__lam_5_76__df__lam_5_79__df__lam_5_82__df__lam_5_85__df__lam_5_88__df__lam_5_91__df__lam_5_94__df__lam_5_97__df__lam_51_39__df__lam_52_40__df__lam_6_21__df__lam_60_45__df__lam_61_46__df__lam_69_51__df__lam_7_22__df__lam_70_52__lift_13__lift_14__lift_2__lift_27__lift_28__lift_3__lift_30__lift_31__lift_33__lift_34__lift_37__lift_38__lift_40__lift_41__lift_46__lift_47__lift_49__lift_50__lift_55__lift_56__lift_58__lift_59__lift_64__lift_65__lift_67__lift_68__lift_75__lift_76(ptr %t0)
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
