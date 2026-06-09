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
@.str.6 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"=" }
@.str.7 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"\0A" }
@.str.8 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"nevOk" }
@.str.9 = private unnamed_addr constant {i32, i32, i32, i32, i32, [7 x i8]} { i32 0, i32 0, i32 0, i32 7, i32 7, [7 x i8] c"nevFail" }
@.str.10 = private unnamed_addr constant {i32, i32, i32, i32, i32, [10 x i8]} { i32 0, i32 0, i32 0, i32 10, i32 10, [10 x i8] c"nevRightOk" }
@.str.11 = private unnamed_addr constant {i32, i32, i32, i32, i32, [10 x i8]} { i32 0, i32 0, i32 0, i32 10, i32 10, [10 x i8] c"nevRightE1" }
@.str.12 = private unnamed_addr constant {i32, i32, i32, i32, i32, [9 x i8]} { i32 0, i32 0, i32 0, i32 9, i32 9, [9 x i8] c"pureNever" }
@.str.13 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"strOk" }
@.str.14 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"strE1" }
@.str.15 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"strE2" }
@.str.16 = private unnamed_addr constant {i32, i32, i32, i32, i32, [7 x i8]} { i32 0, i32 0, i32 0, i32 7, i32 7, [7 x i8] c"strIdem" }
@.str.17 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"abE1" }
@.str.18 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"abE2" }
@.str.19 = private unnamed_addr constant {i32, i32, i32, i32, i32, [8 x i8]} { i32 0, i32 0, i32 0, i32 8, i32 8, [8 x i8] c"twoFirst" }
@.str.20 = private unnamed_addr constant {i32, i32, i32, i32, i32, [9 x i8]} { i32 0, i32 0, i32 0, i32 9, i32 9, [9 x i8] c"twoSecond" }
@.str.21 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"twoE2" }
@.str.22 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"twoOk" }
@.str.23 = private unnamed_addr constant {i32, i32, i32, i32, i32, [6 x i8]} { i32 0, i32 0, i32 0, i32 6, i32 6, [6 x i8] c"idemE1" }
@.str.24 = private unnamed_addr constant {i32, i32, i32, i32, i32, [6 x i8]} { i32 0, i32 0, i32 0, i32 6, i32 6, [6 x i8] c"idemE2" }
@.str.25 = private unnamed_addr constant {i32, i32, i32, i32, i32, [10 x i8]} { i32 0, i32 0, i32 0, i32 10, i32 10, [10 x i8] c"idem2First" }
@.str.26 = private unnamed_addr constant {i32, i32, i32, i32, i32, [11 x i8]} { i32 0, i32 0, i32 0, i32 11, i32 11, [11 x i8] c"idem2Second" }
@.str.27 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"wE1" }
@.str.28 = private unnamed_addr constant {i32, i32, i32, i32, i32, [6 x i8]} { i32 0, i32 0, i32 0, i32 6, i32 6, [6 x i8] c"wE2str" }
@.str.29 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"wE3" }
@.str.30 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"wOk" }
@.str.31 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }

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
  %t4 = inttoptr i64 24 to ptr
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
  %t4 = inttoptr i64 25 to ptr
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
  %t4 = inttoptr i64 27 to ptr
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
  %t4 = inttoptr i64 24 to ptr
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
  %t4 = inttoptr i64 26 to ptr
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
  %t4 = inttoptr i64 27 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  ret ptr %t0
}

define internal ptr @v_nevOk() {
  %t0 = call ptr @v_seedNever()
  %t1 = call ptr @v__df_andThenEither_0(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_nevFail() {
  %t0 = call ptr @v_seedNever()
  %t1 = call ptr @v__df_andThenEither_1(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_nevRightOk() {
  %t0 = call ptr @v_seedA()
  %t1 = call ptr @v__df_andThenEither_2(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_nevRightE1() {
  %t0 = call ptr @v_seedLeftA()
  %t1 = call ptr @v__df_andThenEither_2(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_pureNever() {
  %t0 = call ptr @v_seedNever()
  %t1 = call ptr @v__df_andThenEither_2(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_strOk() {
  %t0 = call ptr @v_seedS()
  %t1 = call ptr @v__df__rowmono_0_andThenEither_3(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_strE1() {
  %t0 = call ptr @v_seedLeftS()
  %t1 = call ptr @v__df__rowmono_0_andThenEither_3(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_strE2() {
  %t0 = call ptr @v_seedS()
  %t1 = call ptr @v__df__rowmono_0_andThenEither_4(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_strIdem() {
  %t0 = call ptr @v_seedS()
  %t1 = call ptr @v__df_andThenEither_5(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_abE1() {
  %t0 = call ptr @v_seedLeftA()
  %t1 = call ptr @v__df__rowmono_1_andThenEither_6(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_abE2() {
  %t0 = call ptr @v_seedA()
  %t1 = call ptr @v__df__rowmono_1_andThenEither_6(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_twoFirst() {
  %t0 = call ptr @v_seedFirst()
  %t1 = call ptr @v__df__rowmono_2_andThenEither_7(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_twoSecond() {
  %t0 = call ptr @v_seedSecond()
  %t1 = call ptr @v__df__rowmono_2_andThenEither_7(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_twoE2() {
  %t0 = call ptr @v_seedT()
  %t1 = call ptr @v__df__rowmono_2_andThenEither_8(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_twoOk() {
  %t0 = call ptr @v_seedT()
  %t1 = call ptr @v__df__rowmono_2_andThenEither_7(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_idemE1() {
  %t0 = call ptr @v_seedLeftA()
  %t1 = call ptr @v__df_andThenEither_1(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_idemE2() {
  %t0 = call ptr @v_seedA()
  %t1 = call ptr @v__df_andThenEither_1(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_idem2First() {
  %t0 = call ptr @v_seedFirst()
  %t1 = call ptr @v__df_andThenEither_9(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_idem2Second() {
  %t0 = call ptr @v_seedT()
  %t1 = call ptr @v__df_andThenEither_9(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_wE1() {
  %t0 = call ptr @v_seedFirst()
  %t1 = call ptr @v__df__rowmono_4_andThenEither_11(ptr %t0)
  %t2 = call ptr @v__df__rowmono_3_andThenEither_10(ptr %t1)
  ret ptr %t2
}

define internal ptr @v_wE2str() {
  %t0 = call ptr @v_seedT()
  %t1 = call ptr @v__df__rowmono_4_andThenEither_12(ptr %t0)
  %t2 = call ptr @v__df__rowmono_3_andThenEither_10(ptr %t1)
  ret ptr %t2
}

define internal ptr @v_wE3() {
  %t0 = call ptr @v_seedT()
  %t1 = call ptr @v__df__rowmono_4_andThenEither_11(ptr %t0)
  %t2 = call ptr @v__df__rowmono_3_andThenEither_13(ptr %t1)
  ret ptr %t2
}

define internal ptr @v_wOk() {
  %t0 = call ptr @v_seedT()
  %t1 = call ptr @v__df__rowmono_4_andThenEither_11(ptr %t0)
  %t2 = call ptr @v__df__rowmono_3_andThenEither_10(ptr %t1)
  ret ptr %t2
}

define internal ptr @v_showA(ptr %v_e) {
  %t0 = getelementptr ptr, ptr %v_e, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.12 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v_e, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = getelementptr ptr, ptr %t6, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %case.default.10 [ i64 24, label %case.arm.24.11 ]
case.arm.24.11:
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_e)
  ret ptr getelementptr inbounds (i8, ptr @.str.2, i64 12)
case.default.10:
  unreachable
case.arm.4.12:
  %t13 = getelementptr ptr, ptr %v_e, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  call void @__inc_ref(ptr %t14)
  %t15 = call ptr @__showInt32(ptr %t14)
  call void @__free_recursive(ptr %t14)
  call void @__free_recursive(ptr %v_e)
  ret ptr %t15
case.default.3:
  unreachable
}

define internal ptr @v_showNever(ptr %v_e) {
  %t0 = getelementptr ptr, ptr %v_e, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 4, label %case.arm.4.4 ]
case.arm.4.4:
  %t5 = getelementptr ptr, ptr %v_e, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t6)
  %t7 = call ptr @__showInt32(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_e)
  ret ptr %t7
case.default.3:
  unreachable
}

define internal ptr @v_showTwo(ptr %v_e) {
  %t0 = getelementptr ptr, ptr %v_e, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.13 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v_e, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = getelementptr ptr, ptr %t6, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %case.default.10 [ i64 26, label %case.arm.26.11 i64 27, label %case.arm.27.12 ]
case.arm.26.11:
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_e)
  ret ptr getelementptr inbounds (i8, ptr @.str.3, i64 12)
case.arm.27.12:
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_e)
  ret ptr getelementptr inbounds (i8, ptr @.str.4, i64 12)
case.default.10:
  unreachable
case.arm.4.13:
  %t14 = getelementptr ptr, ptr %v_e, i32 1
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  call void @__inc_ref(ptr %t15)
  %t16 = call ptr @__showInt32(ptr %t15)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %v_e)
  ret ptr %t16
case.default.3:
  unreachable
}

define internal ptr @v_showStr(ptr %v_e) {
  %t0 = getelementptr ptr, ptr %v_e, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.7 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v_e, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %v_e)
  ret ptr %t6
case.arm.4.7:
  %t8 = getelementptr ptr, ptr %v_e, i32 1
  %t9 = load ptr, ptr %t8
  call void @__inc_ref(ptr %t9)
  call void @__inc_ref(ptr %t9)
  %t10 = call ptr @__showInt32(ptr %t9)
  call void @__free_recursive(ptr %t9)
  call void @__free_recursive(ptr %v_e)
  ret ptr %t10
case.default.3:
  unreachable
}

define internal ptr @v_showStrA(ptr %v_e) {
  %t0 = getelementptr ptr, ptr %v_e, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.17 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v_e, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = getelementptr ptr, ptr %t6, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %case.default.10 [ i64 1615808600, label %case.arm.1615808600.11 i64 2252990199, label %case.arm.2252990199.14 ]
case.arm.1615808600.11:
  %t12 = getelementptr ptr, ptr %t6, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_e)
  ret ptr %t13
case.arm.2252990199.14:
  %t15 = getelementptr ptr, ptr %t6, i32 1
  %t16 = load ptr, ptr %t15
  call void @__inc_ref(ptr %t16)
  call void @__free_recursive(ptr %t16)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_e)
  ret ptr getelementptr inbounds (i8, ptr @.str.2, i64 12)
case.default.10:
  unreachable
case.arm.4.17:
  %t18 = getelementptr ptr, ptr %v_e, i32 1
  %t19 = load ptr, ptr %t18
  call void @__inc_ref(ptr %t19)
  call void @__inc_ref(ptr %t19)
  %t20 = call ptr @__showInt32(ptr %t19)
  call void @__free_recursive(ptr %t19)
  call void @__free_recursive(ptr %v_e)
  ret ptr %t20
case.default.3:
  unreachable
}

define internal ptr @v_showAB(ptr %v_e) {
  %t0 = getelementptr ptr, ptr %v_e, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.17 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v_e, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = getelementptr ptr, ptr %t6, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %case.default.10 [ i64 2252990199, label %case.arm.2252990199.11 i64 2269767818, label %case.arm.2269767818.14 ]
case.arm.2252990199.11:
  %t12 = getelementptr ptr, ptr %t6, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_e)
  ret ptr getelementptr inbounds (i8, ptr @.str.2, i64 12)
case.arm.2269767818.14:
  %t15 = getelementptr ptr, ptr %t6, i32 1
  %t16 = load ptr, ptr %t15
  call void @__inc_ref(ptr %t16)
  call void @__free_recursive(ptr %t16)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_e)
  ret ptr getelementptr inbounds (i8, ptr @.str.5, i64 12)
case.default.10:
  unreachable
case.arm.4.17:
  %t18 = getelementptr ptr, ptr %v_e, i32 1
  %t19 = load ptr, ptr %t18
  call void @__inc_ref(ptr %t19)
  call void @__inc_ref(ptr %t19)
  %t20 = call ptr @__showInt32(ptr %t19)
  call void @__free_recursive(ptr %t19)
  call void @__free_recursive(ptr %v_e)
  ret ptr %t20
case.default.3:
  unreachable
}

define internal ptr @v_showTwoA(ptr %v_e) {
  %t0 = getelementptr ptr, ptr %v_e, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.23 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v_e, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = getelementptr ptr, ptr %t6, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %case.default.10 [ i64 925038822, label %case.arm.925038822.11 i64 2252990199, label %case.arm.2252990199.20 ]
case.arm.925038822.11:
  %t12 = getelementptr ptr, ptr %t6, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t13, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %case.default.17 [ i64 26, label %case.arm.26.18 i64 27, label %case.arm.27.19 ]
case.arm.26.18:
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_e)
  ret ptr getelementptr inbounds (i8, ptr @.str.3, i64 12)
case.arm.27.19:
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_e)
  ret ptr getelementptr inbounds (i8, ptr @.str.4, i64 12)
case.default.17:
  unreachable
case.arm.2252990199.20:
  %t21 = getelementptr ptr, ptr %t6, i32 1
  %t22 = load ptr, ptr %t21
  call void @__inc_ref(ptr %t22)
  call void @__free_recursive(ptr %t22)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_e)
  ret ptr getelementptr inbounds (i8, ptr @.str.2, i64 12)
case.default.10:
  unreachable
case.arm.4.23:
  %t24 = getelementptr ptr, ptr %v_e, i32 1
  %t25 = load ptr, ptr %t24
  call void @__inc_ref(ptr %t25)
  call void @__inc_ref(ptr %t25)
  %t26 = call ptr @__showInt32(ptr %t25)
  call void @__free_recursive(ptr %t25)
  call void @__free_recursive(ptr %v_e)
  ret ptr %t26
case.default.3:
  unreachable
}

define internal ptr @v_showThree(ptr %v_e) {
  %t0 = getelementptr ptr, ptr %v_e, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.26 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v_e, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = getelementptr ptr, ptr %t6, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %case.default.10 [ i64 925038822, label %case.arm.925038822.11 i64 1615808600, label %case.arm.1615808600.20 i64 2252990199, label %case.arm.2252990199.23 ]
case.arm.925038822.11:
  %t12 = getelementptr ptr, ptr %t6, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t13, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %case.default.17 [ i64 26, label %case.arm.26.18 i64 27, label %case.arm.27.19 ]
case.arm.26.18:
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_e)
  ret ptr getelementptr inbounds (i8, ptr @.str.3, i64 12)
case.arm.27.19:
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_e)
  ret ptr getelementptr inbounds (i8, ptr @.str.4, i64 12)
case.default.17:
  unreachable
case.arm.1615808600.20:
  %t21 = getelementptr ptr, ptr %t6, i32 1
  %t22 = load ptr, ptr %t21
  call void @__inc_ref(ptr %t22)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_e)
  ret ptr %t22
case.arm.2252990199.23:
  %t24 = getelementptr ptr, ptr %t6, i32 1
  %t25 = load ptr, ptr %t24
  call void @__inc_ref(ptr %t25)
  call void @__free_recursive(ptr %t25)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_e)
  ret ptr getelementptr inbounds (i8, ptr @.str.2, i64 12)
case.default.10:
  unreachable
case.arm.4.26:
  %t27 = getelementptr ptr, ptr %v_e, i32 1
  %t28 = load ptr, ptr %t27
  call void @__inc_ref(ptr %t28)
  call void @__inc_ref(ptr %t28)
  %t29 = call ptr @__showInt32(ptr %t28)
  call void @__free_recursive(ptr %t28)
  call void @__free_recursive(ptr %v_e)
  ret ptr %t29
case.default.3:
  unreachable
}

define internal ptr @v_tagged(ptr %v_label, ptr %v_val) {
  call void @__inc_ref(ptr %v_label)
  %t0 = call ptr @__concat(ptr %v_label, ptr getelementptr inbounds (i8, ptr @.str.6, i64 12))
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 3, label %case.arm.3.5 i64 4, label %case.arm.4.12 ]
case.arm.3.5:
  %t6 = getelementptr ptr, ptr %t0, i32 1
  %t7 = load ptr, ptr %t6
  call void @__inc_ref(ptr %t7)
  %t8 = call ptr @__alloc(i64 16, i32 1)
  %t9 = inttoptr i64 3 to ptr
  %t10 = getelementptr ptr, ptr %t8, i32 0
  store ptr %t9, ptr %t10
  call void @__inc_ref(ptr %t7)
  %t11 = getelementptr ptr, ptr %t8, i32 1
  store ptr %t7, ptr %t11
  call void @__free_recursive(ptr %t0)
  call void @__free_recursive(ptr %t7)
  call void @__free_recursive(ptr %v_label)
  call void @__free_recursive(ptr %v_val)
  ret ptr %t8
case.arm.4.12:
  %t13 = getelementptr ptr, ptr %t0, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  call void @__inc_ref(ptr %t14)
  call void @__inc_ref(ptr %v_val)
  %t15 = call ptr @__concat(ptr %t14, ptr %v_val)
  %t16 = getelementptr ptr, ptr %t15, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %case.default.19 [ i64 3, label %case.arm.3.20 i64 4, label %case.arm.4.27 ]
case.arm.3.20:
  %t21 = getelementptr ptr, ptr %t15, i32 1
  %t22 = load ptr, ptr %t21
  call void @__inc_ref(ptr %t22)
  %t23 = call ptr @__alloc(i64 16, i32 1)
  %t24 = inttoptr i64 3 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  call void @__inc_ref(ptr %t22)
  %t26 = getelementptr ptr, ptr %t23, i32 1
  store ptr %t22, ptr %t26
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t0)
  call void @__free_recursive(ptr %t22)
  call void @__free_recursive(ptr %t14)
  call void @__free_recursive(ptr %v_label)
  call void @__free_recursive(ptr %v_val)
  ret ptr %t23
case.arm.4.27:
  %t28 = getelementptr ptr, ptr %t15, i32 1
  %t29 = load ptr, ptr %t28
  call void @__inc_ref(ptr %t29)
  call void @__inc_ref(ptr %t29)
  %t30 = call ptr @__concat(ptr %t29, ptr getelementptr inbounds (i8, ptr @.str.7, i64 12))
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t0)
  call void @__free_recursive(ptr %t29)
  call void @__free_recursive(ptr %t14)
  call void @__free_recursive(ptr %v_label)
  call void @__free_recursive(ptr %v_val)
  ret ptr %t30
case.default.19:
  unreachable
case.default.4:
  unreachable
}

define internal ptr @v_appendTagged(ptr %v_acc, ptr %v_label, ptr %v_val) {
  call void @__inc_ref(ptr %v_label)
  call void @__inc_ref(ptr %v_val)
  %t0 = call ptr @v_tagged(ptr %v_label, ptr %v_val)
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 3, label %case.arm.3.5 i64 4, label %case.arm.4.12 ]
case.arm.3.5:
  %t6 = getelementptr ptr, ptr %t0, i32 1
  %t7 = load ptr, ptr %t6
  call void @__inc_ref(ptr %t7)
  %t8 = call ptr @__alloc(i64 16, i32 1)
  %t9 = inttoptr i64 3 to ptr
  %t10 = getelementptr ptr, ptr %t8, i32 0
  store ptr %t9, ptr %t10
  call void @__inc_ref(ptr %t7)
  %t11 = getelementptr ptr, ptr %t8, i32 1
  store ptr %t7, ptr %t11
  call void @__free_recursive(ptr %t0)
  call void @__free_recursive(ptr %t7)
  call void @__free_recursive(ptr %v_acc)
  call void @__free_recursive(ptr %v_label)
  call void @__free_recursive(ptr %v_val)
  ret ptr %t8
case.arm.4.12:
  %t13 = getelementptr ptr, ptr %t0, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  call void @__inc_ref(ptr %v_acc)
  call void @__inc_ref(ptr %t14)
  %t15 = call ptr @__concat(ptr %v_acc, ptr %t14)
  call void @__free_recursive(ptr %t0)
  call void @__free_recursive(ptr %t14)
  call void @__free_recursive(ptr %v_acc)
  call void @__free_recursive(ptr %v_label)
  call void @__free_recursive(ptr %v_val)
  ret ptr %t15
case.default.4:
  unreachable
}

define internal ptr @v_render() {
  %t0 = call ptr @v_nevOk()
  %t1 = call ptr @v_showA(ptr %t0)
  %t2 = call ptr @v_tagged(ptr getelementptr inbounds (i8, ptr @.str.8, i64 12), ptr %t1)
  %t3 = getelementptr ptr, ptr %t2, i32 0
  %t4 = load ptr, ptr %t3
  %t5 = ptrtoint ptr %t4 to i64
  switch i64 %t5, label %case.default.6 [ i64 3, label %case.arm.3.8 i64 4, label %case.arm.4.16 ]
case.arm.3.8:
  %t10 = getelementptr ptr, ptr %t2, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  %t12 = call ptr @__alloc(i64 16, i32 1)
  %t13 = inttoptr i64 3 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  call void @__inc_ref(ptr %t11)
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t11, ptr %t15
  br label %case.end.3.9
case.end.3.9:
  br label %case.join.7
case.arm.4.16:
  %t18 = getelementptr ptr, ptr %t2, i32 1
  %t19 = load ptr, ptr %t18
  call void @__inc_ref(ptr %t19)
  call void @__inc_ref(ptr %t19)
  %t20 = call ptr @v_nevFail()
  %t21 = call ptr @v_showA(ptr %t20)
  %t22 = call ptr @v_appendTagged(ptr %t19, ptr getelementptr inbounds (i8, ptr @.str.9, i64 12), ptr %t21)
  %t23 = getelementptr ptr, ptr %t22, i32 0
  %t24 = load ptr, ptr %t23
  %t25 = ptrtoint ptr %t24 to i64
  switch i64 %t25, label %case.default.26 [ i64 3, label %case.arm.3.28 i64 4, label %case.arm.4.36 ]
case.arm.3.28:
  %t30 = getelementptr ptr, ptr %t22, i32 1
  %t31 = load ptr, ptr %t30
  call void @__inc_ref(ptr %t31)
  %t32 = call ptr @__alloc(i64 16, i32 1)
  %t33 = inttoptr i64 3 to ptr
  %t34 = getelementptr ptr, ptr %t32, i32 0
  store ptr %t33, ptr %t34
  call void @__inc_ref(ptr %t31)
  %t35 = getelementptr ptr, ptr %t32, i32 1
  store ptr %t31, ptr %t35
  br label %case.end.3.29
case.end.3.29:
  br label %case.join.27
case.arm.4.36:
  %t38 = getelementptr ptr, ptr %t22, i32 1
  %t39 = load ptr, ptr %t38
  call void @__inc_ref(ptr %t39)
  call void @__inc_ref(ptr %t39)
  %t40 = call ptr @v_nevRightOk()
  %t41 = call ptr @v_showA(ptr %t40)
  %t42 = call ptr @v_appendTagged(ptr %t39, ptr getelementptr inbounds (i8, ptr @.str.10, i64 12), ptr %t41)
  %t43 = getelementptr ptr, ptr %t42, i32 0
  %t44 = load ptr, ptr %t43
  %t45 = ptrtoint ptr %t44 to i64
  switch i64 %t45, label %case.default.46 [ i64 3, label %case.arm.3.48 i64 4, label %case.arm.4.56 ]
case.arm.3.48:
  %t50 = getelementptr ptr, ptr %t42, i32 1
  %t51 = load ptr, ptr %t50
  call void @__inc_ref(ptr %t51)
  %t52 = call ptr @__alloc(i64 16, i32 1)
  %t53 = inttoptr i64 3 to ptr
  %t54 = getelementptr ptr, ptr %t52, i32 0
  store ptr %t53, ptr %t54
  call void @__inc_ref(ptr %t51)
  %t55 = getelementptr ptr, ptr %t52, i32 1
  store ptr %t51, ptr %t55
  br label %case.end.3.49
case.end.3.49:
  br label %case.join.47
case.arm.4.56:
  %t58 = getelementptr ptr, ptr %t42, i32 1
  %t59 = load ptr, ptr %t58
  call void @__inc_ref(ptr %t59)
  call void @__inc_ref(ptr %t59)
  %t60 = call ptr @v_nevRightE1()
  %t61 = call ptr @v_showA(ptr %t60)
  %t62 = call ptr @v_appendTagged(ptr %t59, ptr getelementptr inbounds (i8, ptr @.str.11, i64 12), ptr %t61)
  %t63 = getelementptr ptr, ptr %t62, i32 0
  %t64 = load ptr, ptr %t63
  %t65 = ptrtoint ptr %t64 to i64
  switch i64 %t65, label %case.default.66 [ i64 3, label %case.arm.3.68 i64 4, label %case.arm.4.76 ]
case.arm.3.68:
  %t70 = getelementptr ptr, ptr %t62, i32 1
  %t71 = load ptr, ptr %t70
  call void @__inc_ref(ptr %t71)
  %t72 = call ptr @__alloc(i64 16, i32 1)
  %t73 = inttoptr i64 3 to ptr
  %t74 = getelementptr ptr, ptr %t72, i32 0
  store ptr %t73, ptr %t74
  call void @__inc_ref(ptr %t71)
  %t75 = getelementptr ptr, ptr %t72, i32 1
  store ptr %t71, ptr %t75
  br label %case.end.3.69
case.end.3.69:
  br label %case.join.67
case.arm.4.76:
  %t78 = getelementptr ptr, ptr %t62, i32 1
  %t79 = load ptr, ptr %t78
  call void @__inc_ref(ptr %t79)
  call void @__inc_ref(ptr %t79)
  %t80 = call ptr @v_pureNever()
  %t81 = call ptr @v_showNever(ptr %t80)
  %t82 = call ptr @v_appendTagged(ptr %t79, ptr getelementptr inbounds (i8, ptr @.str.12, i64 12), ptr %t81)
  %t83 = getelementptr ptr, ptr %t82, i32 0
  %t84 = load ptr, ptr %t83
  %t85 = ptrtoint ptr %t84 to i64
  switch i64 %t85, label %case.default.86 [ i64 3, label %case.arm.3.88 i64 4, label %case.arm.4.96 ]
case.arm.3.88:
  %t90 = getelementptr ptr, ptr %t82, i32 1
  %t91 = load ptr, ptr %t90
  call void @__inc_ref(ptr %t91)
  %t92 = call ptr @__alloc(i64 16, i32 1)
  %t93 = inttoptr i64 3 to ptr
  %t94 = getelementptr ptr, ptr %t92, i32 0
  store ptr %t93, ptr %t94
  call void @__inc_ref(ptr %t91)
  %t95 = getelementptr ptr, ptr %t92, i32 1
  store ptr %t91, ptr %t95
  br label %case.end.3.89
case.end.3.89:
  br label %case.join.87
case.arm.4.96:
  %t98 = getelementptr ptr, ptr %t82, i32 1
  %t99 = load ptr, ptr %t98
  call void @__inc_ref(ptr %t99)
  call void @__inc_ref(ptr %t99)
  %t100 = call ptr @v_strOk()
  %t101 = call ptr @v_showStrA(ptr %t100)
  %t102 = call ptr @v_appendTagged(ptr %t99, ptr getelementptr inbounds (i8, ptr @.str.13, i64 12), ptr %t101)
  %t103 = getelementptr ptr, ptr %t102, i32 0
  %t104 = load ptr, ptr %t103
  %t105 = ptrtoint ptr %t104 to i64
  switch i64 %t105, label %case.default.106 [ i64 3, label %case.arm.3.108 i64 4, label %case.arm.4.116 ]
case.arm.3.108:
  %t110 = getelementptr ptr, ptr %t102, i32 1
  %t111 = load ptr, ptr %t110
  call void @__inc_ref(ptr %t111)
  %t112 = call ptr @__alloc(i64 16, i32 1)
  %t113 = inttoptr i64 3 to ptr
  %t114 = getelementptr ptr, ptr %t112, i32 0
  store ptr %t113, ptr %t114
  call void @__inc_ref(ptr %t111)
  %t115 = getelementptr ptr, ptr %t112, i32 1
  store ptr %t111, ptr %t115
  br label %case.end.3.109
case.end.3.109:
  br label %case.join.107
case.arm.4.116:
  %t118 = getelementptr ptr, ptr %t102, i32 1
  %t119 = load ptr, ptr %t118
  call void @__inc_ref(ptr %t119)
  call void @__inc_ref(ptr %t119)
  %t120 = call ptr @v_strE1()
  %t121 = call ptr @v_showStrA(ptr %t120)
  %t122 = call ptr @v_appendTagged(ptr %t119, ptr getelementptr inbounds (i8, ptr @.str.14, i64 12), ptr %t121)
  %t123 = getelementptr ptr, ptr %t122, i32 0
  %t124 = load ptr, ptr %t123
  %t125 = ptrtoint ptr %t124 to i64
  switch i64 %t125, label %case.default.126 [ i64 3, label %case.arm.3.128 i64 4, label %case.arm.4.136 ]
case.arm.3.128:
  %t130 = getelementptr ptr, ptr %t122, i32 1
  %t131 = load ptr, ptr %t130
  call void @__inc_ref(ptr %t131)
  %t132 = call ptr @__alloc(i64 16, i32 1)
  %t133 = inttoptr i64 3 to ptr
  %t134 = getelementptr ptr, ptr %t132, i32 0
  store ptr %t133, ptr %t134
  call void @__inc_ref(ptr %t131)
  %t135 = getelementptr ptr, ptr %t132, i32 1
  store ptr %t131, ptr %t135
  br label %case.end.3.129
case.end.3.129:
  br label %case.join.127
case.arm.4.136:
  %t138 = getelementptr ptr, ptr %t122, i32 1
  %t139 = load ptr, ptr %t138
  call void @__inc_ref(ptr %t139)
  call void @__inc_ref(ptr %t139)
  %t140 = call ptr @v_strE2()
  %t141 = call ptr @v_showStrA(ptr %t140)
  %t142 = call ptr @v_appendTagged(ptr %t139, ptr getelementptr inbounds (i8, ptr @.str.15, i64 12), ptr %t141)
  %t143 = getelementptr ptr, ptr %t142, i32 0
  %t144 = load ptr, ptr %t143
  %t145 = ptrtoint ptr %t144 to i64
  switch i64 %t145, label %case.default.146 [ i64 3, label %case.arm.3.148 i64 4, label %case.arm.4.156 ]
case.arm.3.148:
  %t150 = getelementptr ptr, ptr %t142, i32 1
  %t151 = load ptr, ptr %t150
  call void @__inc_ref(ptr %t151)
  %t152 = call ptr @__alloc(i64 16, i32 1)
  %t153 = inttoptr i64 3 to ptr
  %t154 = getelementptr ptr, ptr %t152, i32 0
  store ptr %t153, ptr %t154
  call void @__inc_ref(ptr %t151)
  %t155 = getelementptr ptr, ptr %t152, i32 1
  store ptr %t151, ptr %t155
  br label %case.end.3.149
case.end.3.149:
  br label %case.join.147
case.arm.4.156:
  %t158 = getelementptr ptr, ptr %t142, i32 1
  %t159 = load ptr, ptr %t158
  call void @__inc_ref(ptr %t159)
  call void @__inc_ref(ptr %t159)
  %t160 = call ptr @v_strIdem()
  %t161 = call ptr @v_showStr(ptr %t160)
  %t162 = call ptr @v_appendTagged(ptr %t159, ptr getelementptr inbounds (i8, ptr @.str.16, i64 12), ptr %t161)
  %t163 = getelementptr ptr, ptr %t162, i32 0
  %t164 = load ptr, ptr %t163
  %t165 = ptrtoint ptr %t164 to i64
  switch i64 %t165, label %case.default.166 [ i64 3, label %case.arm.3.168 i64 4, label %case.arm.4.176 ]
case.arm.3.168:
  %t170 = getelementptr ptr, ptr %t162, i32 1
  %t171 = load ptr, ptr %t170
  call void @__inc_ref(ptr %t171)
  %t172 = call ptr @__alloc(i64 16, i32 1)
  %t173 = inttoptr i64 3 to ptr
  %t174 = getelementptr ptr, ptr %t172, i32 0
  store ptr %t173, ptr %t174
  call void @__inc_ref(ptr %t171)
  %t175 = getelementptr ptr, ptr %t172, i32 1
  store ptr %t171, ptr %t175
  br label %case.end.3.169
case.end.3.169:
  br label %case.join.167
case.arm.4.176:
  %t178 = getelementptr ptr, ptr %t162, i32 1
  %t179 = load ptr, ptr %t178
  call void @__inc_ref(ptr %t179)
  call void @__inc_ref(ptr %t179)
  %t180 = call ptr @v_abE1()
  %t181 = call ptr @v_showAB(ptr %t180)
  %t182 = call ptr @v_appendTagged(ptr %t179, ptr getelementptr inbounds (i8, ptr @.str.17, i64 12), ptr %t181)
  %t183 = getelementptr ptr, ptr %t182, i32 0
  %t184 = load ptr, ptr %t183
  %t185 = ptrtoint ptr %t184 to i64
  switch i64 %t185, label %case.default.186 [ i64 3, label %case.arm.3.188 i64 4, label %case.arm.4.196 ]
case.arm.3.188:
  %t190 = getelementptr ptr, ptr %t182, i32 1
  %t191 = load ptr, ptr %t190
  call void @__inc_ref(ptr %t191)
  %t192 = call ptr @__alloc(i64 16, i32 1)
  %t193 = inttoptr i64 3 to ptr
  %t194 = getelementptr ptr, ptr %t192, i32 0
  store ptr %t193, ptr %t194
  call void @__inc_ref(ptr %t191)
  %t195 = getelementptr ptr, ptr %t192, i32 1
  store ptr %t191, ptr %t195
  br label %case.end.3.189
case.end.3.189:
  br label %case.join.187
case.arm.4.196:
  %t198 = getelementptr ptr, ptr %t182, i32 1
  %t199 = load ptr, ptr %t198
  call void @__inc_ref(ptr %t199)
  call void @__inc_ref(ptr %t199)
  %t200 = call ptr @v_abE2()
  %t201 = call ptr @v_showAB(ptr %t200)
  %t202 = call ptr @v_appendTagged(ptr %t199, ptr getelementptr inbounds (i8, ptr @.str.18, i64 12), ptr %t201)
  %t203 = getelementptr ptr, ptr %t202, i32 0
  %t204 = load ptr, ptr %t203
  %t205 = ptrtoint ptr %t204 to i64
  switch i64 %t205, label %case.default.206 [ i64 3, label %case.arm.3.208 i64 4, label %case.arm.4.216 ]
case.arm.3.208:
  %t210 = getelementptr ptr, ptr %t202, i32 1
  %t211 = load ptr, ptr %t210
  call void @__inc_ref(ptr %t211)
  %t212 = call ptr @__alloc(i64 16, i32 1)
  %t213 = inttoptr i64 3 to ptr
  %t214 = getelementptr ptr, ptr %t212, i32 0
  store ptr %t213, ptr %t214
  call void @__inc_ref(ptr %t211)
  %t215 = getelementptr ptr, ptr %t212, i32 1
  store ptr %t211, ptr %t215
  br label %case.end.3.209
case.end.3.209:
  br label %case.join.207
case.arm.4.216:
  %t218 = getelementptr ptr, ptr %t202, i32 1
  %t219 = load ptr, ptr %t218
  call void @__inc_ref(ptr %t219)
  call void @__inc_ref(ptr %t219)
  %t220 = call ptr @v_twoFirst()
  %t221 = call ptr @v_showTwoA(ptr %t220)
  %t222 = call ptr @v_appendTagged(ptr %t219, ptr getelementptr inbounds (i8, ptr @.str.19, i64 12), ptr %t221)
  %t223 = getelementptr ptr, ptr %t222, i32 0
  %t224 = load ptr, ptr %t223
  %t225 = ptrtoint ptr %t224 to i64
  switch i64 %t225, label %case.default.226 [ i64 3, label %case.arm.3.228 i64 4, label %case.arm.4.236 ]
case.arm.3.228:
  %t230 = getelementptr ptr, ptr %t222, i32 1
  %t231 = load ptr, ptr %t230
  call void @__inc_ref(ptr %t231)
  %t232 = call ptr @__alloc(i64 16, i32 1)
  %t233 = inttoptr i64 3 to ptr
  %t234 = getelementptr ptr, ptr %t232, i32 0
  store ptr %t233, ptr %t234
  call void @__inc_ref(ptr %t231)
  %t235 = getelementptr ptr, ptr %t232, i32 1
  store ptr %t231, ptr %t235
  br label %case.end.3.229
case.end.3.229:
  br label %case.join.227
case.arm.4.236:
  %t238 = getelementptr ptr, ptr %t222, i32 1
  %t239 = load ptr, ptr %t238
  call void @__inc_ref(ptr %t239)
  call void @__inc_ref(ptr %t239)
  %t240 = call ptr @v_twoSecond()
  %t241 = call ptr @v_showTwoA(ptr %t240)
  %t242 = call ptr @v_appendTagged(ptr %t239, ptr getelementptr inbounds (i8, ptr @.str.20, i64 12), ptr %t241)
  %t243 = getelementptr ptr, ptr %t242, i32 0
  %t244 = load ptr, ptr %t243
  %t245 = ptrtoint ptr %t244 to i64
  switch i64 %t245, label %case.default.246 [ i64 3, label %case.arm.3.248 i64 4, label %case.arm.4.256 ]
case.arm.3.248:
  %t250 = getelementptr ptr, ptr %t242, i32 1
  %t251 = load ptr, ptr %t250
  call void @__inc_ref(ptr %t251)
  %t252 = call ptr @__alloc(i64 16, i32 1)
  %t253 = inttoptr i64 3 to ptr
  %t254 = getelementptr ptr, ptr %t252, i32 0
  store ptr %t253, ptr %t254
  call void @__inc_ref(ptr %t251)
  %t255 = getelementptr ptr, ptr %t252, i32 1
  store ptr %t251, ptr %t255
  br label %case.end.3.249
case.end.3.249:
  br label %case.join.247
case.arm.4.256:
  %t258 = getelementptr ptr, ptr %t242, i32 1
  %t259 = load ptr, ptr %t258
  call void @__inc_ref(ptr %t259)
  call void @__inc_ref(ptr %t259)
  %t260 = call ptr @v_twoE2()
  %t261 = call ptr @v_showTwoA(ptr %t260)
  %t262 = call ptr @v_appendTagged(ptr %t259, ptr getelementptr inbounds (i8, ptr @.str.21, i64 12), ptr %t261)
  %t263 = getelementptr ptr, ptr %t262, i32 0
  %t264 = load ptr, ptr %t263
  %t265 = ptrtoint ptr %t264 to i64
  switch i64 %t265, label %case.default.266 [ i64 3, label %case.arm.3.268 i64 4, label %case.arm.4.276 ]
case.arm.3.268:
  %t270 = getelementptr ptr, ptr %t262, i32 1
  %t271 = load ptr, ptr %t270
  call void @__inc_ref(ptr %t271)
  %t272 = call ptr @__alloc(i64 16, i32 1)
  %t273 = inttoptr i64 3 to ptr
  %t274 = getelementptr ptr, ptr %t272, i32 0
  store ptr %t273, ptr %t274
  call void @__inc_ref(ptr %t271)
  %t275 = getelementptr ptr, ptr %t272, i32 1
  store ptr %t271, ptr %t275
  br label %case.end.3.269
case.end.3.269:
  br label %case.join.267
case.arm.4.276:
  %t278 = getelementptr ptr, ptr %t262, i32 1
  %t279 = load ptr, ptr %t278
  call void @__inc_ref(ptr %t279)
  call void @__inc_ref(ptr %t279)
  %t280 = call ptr @v_twoOk()
  %t281 = call ptr @v_showTwoA(ptr %t280)
  %t282 = call ptr @v_appendTagged(ptr %t279, ptr getelementptr inbounds (i8, ptr @.str.22, i64 12), ptr %t281)
  %t283 = getelementptr ptr, ptr %t282, i32 0
  %t284 = load ptr, ptr %t283
  %t285 = ptrtoint ptr %t284 to i64
  switch i64 %t285, label %case.default.286 [ i64 3, label %case.arm.3.288 i64 4, label %case.arm.4.296 ]
case.arm.3.288:
  %t290 = getelementptr ptr, ptr %t282, i32 1
  %t291 = load ptr, ptr %t290
  call void @__inc_ref(ptr %t291)
  %t292 = call ptr @__alloc(i64 16, i32 1)
  %t293 = inttoptr i64 3 to ptr
  %t294 = getelementptr ptr, ptr %t292, i32 0
  store ptr %t293, ptr %t294
  call void @__inc_ref(ptr %t291)
  %t295 = getelementptr ptr, ptr %t292, i32 1
  store ptr %t291, ptr %t295
  br label %case.end.3.289
case.end.3.289:
  br label %case.join.287
case.arm.4.296:
  %t298 = getelementptr ptr, ptr %t282, i32 1
  %t299 = load ptr, ptr %t298
  call void @__inc_ref(ptr %t299)
  call void @__inc_ref(ptr %t299)
  %t300 = call ptr @v_idemE1()
  %t301 = call ptr @v_showA(ptr %t300)
  %t302 = call ptr @v_appendTagged(ptr %t299, ptr getelementptr inbounds (i8, ptr @.str.23, i64 12), ptr %t301)
  %t303 = getelementptr ptr, ptr %t302, i32 0
  %t304 = load ptr, ptr %t303
  %t305 = ptrtoint ptr %t304 to i64
  switch i64 %t305, label %case.default.306 [ i64 3, label %case.arm.3.308 i64 4, label %case.arm.4.316 ]
case.arm.3.308:
  %t310 = getelementptr ptr, ptr %t302, i32 1
  %t311 = load ptr, ptr %t310
  call void @__inc_ref(ptr %t311)
  %t312 = call ptr @__alloc(i64 16, i32 1)
  %t313 = inttoptr i64 3 to ptr
  %t314 = getelementptr ptr, ptr %t312, i32 0
  store ptr %t313, ptr %t314
  call void @__inc_ref(ptr %t311)
  %t315 = getelementptr ptr, ptr %t312, i32 1
  store ptr %t311, ptr %t315
  br label %case.end.3.309
case.end.3.309:
  br label %case.join.307
case.arm.4.316:
  %t318 = getelementptr ptr, ptr %t302, i32 1
  %t319 = load ptr, ptr %t318
  call void @__inc_ref(ptr %t319)
  call void @__inc_ref(ptr %t319)
  %t320 = call ptr @v_idemE2()
  %t321 = call ptr @v_showA(ptr %t320)
  %t322 = call ptr @v_appendTagged(ptr %t319, ptr getelementptr inbounds (i8, ptr @.str.24, i64 12), ptr %t321)
  %t323 = getelementptr ptr, ptr %t322, i32 0
  %t324 = load ptr, ptr %t323
  %t325 = ptrtoint ptr %t324 to i64
  switch i64 %t325, label %case.default.326 [ i64 3, label %case.arm.3.328 i64 4, label %case.arm.4.336 ]
case.arm.3.328:
  %t330 = getelementptr ptr, ptr %t322, i32 1
  %t331 = load ptr, ptr %t330
  call void @__inc_ref(ptr %t331)
  %t332 = call ptr @__alloc(i64 16, i32 1)
  %t333 = inttoptr i64 3 to ptr
  %t334 = getelementptr ptr, ptr %t332, i32 0
  store ptr %t333, ptr %t334
  call void @__inc_ref(ptr %t331)
  %t335 = getelementptr ptr, ptr %t332, i32 1
  store ptr %t331, ptr %t335
  br label %case.end.3.329
case.end.3.329:
  br label %case.join.327
case.arm.4.336:
  %t338 = getelementptr ptr, ptr %t322, i32 1
  %t339 = load ptr, ptr %t338
  call void @__inc_ref(ptr %t339)
  call void @__inc_ref(ptr %t339)
  %t340 = call ptr @v_idem2First()
  %t341 = call ptr @v_showTwo(ptr %t340)
  %t342 = call ptr @v_appendTagged(ptr %t339, ptr getelementptr inbounds (i8, ptr @.str.25, i64 12), ptr %t341)
  %t343 = getelementptr ptr, ptr %t342, i32 0
  %t344 = load ptr, ptr %t343
  %t345 = ptrtoint ptr %t344 to i64
  switch i64 %t345, label %case.default.346 [ i64 3, label %case.arm.3.348 i64 4, label %case.arm.4.356 ]
case.arm.3.348:
  %t350 = getelementptr ptr, ptr %t342, i32 1
  %t351 = load ptr, ptr %t350
  call void @__inc_ref(ptr %t351)
  %t352 = call ptr @__alloc(i64 16, i32 1)
  %t353 = inttoptr i64 3 to ptr
  %t354 = getelementptr ptr, ptr %t352, i32 0
  store ptr %t353, ptr %t354
  call void @__inc_ref(ptr %t351)
  %t355 = getelementptr ptr, ptr %t352, i32 1
  store ptr %t351, ptr %t355
  br label %case.end.3.349
case.end.3.349:
  br label %case.join.347
case.arm.4.356:
  %t358 = getelementptr ptr, ptr %t342, i32 1
  %t359 = load ptr, ptr %t358
  call void @__inc_ref(ptr %t359)
  call void @__inc_ref(ptr %t359)
  %t360 = call ptr @v_idem2Second()
  %t361 = call ptr @v_showTwo(ptr %t360)
  %t362 = call ptr @v_appendTagged(ptr %t359, ptr getelementptr inbounds (i8, ptr @.str.26, i64 12), ptr %t361)
  %t363 = getelementptr ptr, ptr %t362, i32 0
  %t364 = load ptr, ptr %t363
  %t365 = ptrtoint ptr %t364 to i64
  switch i64 %t365, label %case.default.366 [ i64 3, label %case.arm.3.368 i64 4, label %case.arm.4.376 ]
case.arm.3.368:
  %t370 = getelementptr ptr, ptr %t362, i32 1
  %t371 = load ptr, ptr %t370
  call void @__inc_ref(ptr %t371)
  %t372 = call ptr @__alloc(i64 16, i32 1)
  %t373 = inttoptr i64 3 to ptr
  %t374 = getelementptr ptr, ptr %t372, i32 0
  store ptr %t373, ptr %t374
  call void @__inc_ref(ptr %t371)
  %t375 = getelementptr ptr, ptr %t372, i32 1
  store ptr %t371, ptr %t375
  br label %case.end.3.369
case.end.3.369:
  br label %case.join.367
case.arm.4.376:
  %t378 = getelementptr ptr, ptr %t362, i32 1
  %t379 = load ptr, ptr %t378
  call void @__inc_ref(ptr %t379)
  call void @__inc_ref(ptr %t379)
  %t380 = call ptr @v_wE1()
  %t381 = call ptr @v_showThree(ptr %t380)
  %t382 = call ptr @v_appendTagged(ptr %t379, ptr getelementptr inbounds (i8, ptr @.str.27, i64 12), ptr %t381)
  %t383 = getelementptr ptr, ptr %t382, i32 0
  %t384 = load ptr, ptr %t383
  %t385 = ptrtoint ptr %t384 to i64
  switch i64 %t385, label %case.default.386 [ i64 3, label %case.arm.3.388 i64 4, label %case.arm.4.396 ]
case.arm.3.388:
  %t390 = getelementptr ptr, ptr %t382, i32 1
  %t391 = load ptr, ptr %t390
  call void @__inc_ref(ptr %t391)
  %t392 = call ptr @__alloc(i64 16, i32 1)
  %t393 = inttoptr i64 3 to ptr
  %t394 = getelementptr ptr, ptr %t392, i32 0
  store ptr %t393, ptr %t394
  call void @__inc_ref(ptr %t391)
  %t395 = getelementptr ptr, ptr %t392, i32 1
  store ptr %t391, ptr %t395
  br label %case.end.3.389
case.end.3.389:
  br label %case.join.387
case.arm.4.396:
  %t398 = getelementptr ptr, ptr %t382, i32 1
  %t399 = load ptr, ptr %t398
  call void @__inc_ref(ptr %t399)
  call void @__inc_ref(ptr %t399)
  %t400 = call ptr @v_wE2str()
  %t401 = call ptr @v_showThree(ptr %t400)
  %t402 = call ptr @v_appendTagged(ptr %t399, ptr getelementptr inbounds (i8, ptr @.str.28, i64 12), ptr %t401)
  %t403 = getelementptr ptr, ptr %t402, i32 0
  %t404 = load ptr, ptr %t403
  %t405 = ptrtoint ptr %t404 to i64
  switch i64 %t405, label %case.default.406 [ i64 3, label %case.arm.3.408 i64 4, label %case.arm.4.416 ]
case.arm.3.408:
  %t410 = getelementptr ptr, ptr %t402, i32 1
  %t411 = load ptr, ptr %t410
  call void @__inc_ref(ptr %t411)
  %t412 = call ptr @__alloc(i64 16, i32 1)
  %t413 = inttoptr i64 3 to ptr
  %t414 = getelementptr ptr, ptr %t412, i32 0
  store ptr %t413, ptr %t414
  call void @__inc_ref(ptr %t411)
  %t415 = getelementptr ptr, ptr %t412, i32 1
  store ptr %t411, ptr %t415
  br label %case.end.3.409
case.end.3.409:
  br label %case.join.407
case.arm.4.416:
  %t418 = getelementptr ptr, ptr %t402, i32 1
  %t419 = load ptr, ptr %t418
  call void @__inc_ref(ptr %t419)
  call void @__inc_ref(ptr %t419)
  %t420 = call ptr @v_wE3()
  %t421 = call ptr @v_showThree(ptr %t420)
  %t422 = call ptr @v_appendTagged(ptr %t419, ptr getelementptr inbounds (i8, ptr @.str.29, i64 12), ptr %t421)
  %t423 = getelementptr ptr, ptr %t422, i32 0
  %t424 = load ptr, ptr %t423
  %t425 = ptrtoint ptr %t424 to i64
  switch i64 %t425, label %case.default.426 [ i64 3, label %case.arm.3.428 i64 4, label %case.arm.4.436 ]
case.arm.3.428:
  %t430 = getelementptr ptr, ptr %t422, i32 1
  %t431 = load ptr, ptr %t430
  call void @__inc_ref(ptr %t431)
  %t432 = call ptr @__alloc(i64 16, i32 1)
  %t433 = inttoptr i64 3 to ptr
  %t434 = getelementptr ptr, ptr %t432, i32 0
  store ptr %t433, ptr %t434
  call void @__inc_ref(ptr %t431)
  %t435 = getelementptr ptr, ptr %t432, i32 1
  store ptr %t431, ptr %t435
  br label %case.end.3.429
case.end.3.429:
  br label %case.join.427
case.arm.4.436:
  %t438 = getelementptr ptr, ptr %t422, i32 1
  %t439 = load ptr, ptr %t438
  call void @__inc_ref(ptr %t439)
  call void @__inc_ref(ptr %t439)
  %t440 = call ptr @v_wOk()
  %t441 = call ptr @v_showThree(ptr %t440)
  %t442 = call ptr @v_appendTagged(ptr %t439, ptr getelementptr inbounds (i8, ptr @.str.30, i64 12), ptr %t441)
  br label %case.end.4.437
case.end.4.437:
  br label %case.join.427
case.default.426:
  unreachable
case.join.427:
  %t443 = phi ptr [ %t432, %case.end.3.429 ], [ %t442, %case.end.4.437 ]
  call void @__free_recursive(ptr %t422)
  br label %case.end.4.417
case.end.4.417:
  br label %case.join.407
case.default.406:
  unreachable
case.join.407:
  %t444 = phi ptr [ %t412, %case.end.3.409 ], [ %t443, %case.end.4.417 ]
  call void @__free_recursive(ptr %t402)
  br label %case.end.4.397
case.end.4.397:
  br label %case.join.387
case.default.386:
  unreachable
case.join.387:
  %t445 = phi ptr [ %t392, %case.end.3.389 ], [ %t444, %case.end.4.397 ]
  call void @__free_recursive(ptr %t382)
  br label %case.end.4.377
case.end.4.377:
  br label %case.join.367
case.default.366:
  unreachable
case.join.367:
  %t446 = phi ptr [ %t372, %case.end.3.369 ], [ %t445, %case.end.4.377 ]
  call void @__free_recursive(ptr %t362)
  br label %case.end.4.357
case.end.4.357:
  br label %case.join.347
case.default.346:
  unreachable
case.join.347:
  %t447 = phi ptr [ %t352, %case.end.3.349 ], [ %t446, %case.end.4.357 ]
  call void @__free_recursive(ptr %t342)
  br label %case.end.4.337
case.end.4.337:
  br label %case.join.327
case.default.326:
  unreachable
case.join.327:
  %t448 = phi ptr [ %t332, %case.end.3.329 ], [ %t447, %case.end.4.337 ]
  call void @__free_recursive(ptr %t322)
  br label %case.end.4.317
case.end.4.317:
  br label %case.join.307
case.default.306:
  unreachable
case.join.307:
  %t449 = phi ptr [ %t312, %case.end.3.309 ], [ %t448, %case.end.4.317 ]
  call void @__free_recursive(ptr %t302)
  br label %case.end.4.297
case.end.4.297:
  br label %case.join.287
case.default.286:
  unreachable
case.join.287:
  %t450 = phi ptr [ %t292, %case.end.3.289 ], [ %t449, %case.end.4.297 ]
  call void @__free_recursive(ptr %t282)
  br label %case.end.4.277
case.end.4.277:
  br label %case.join.267
case.default.266:
  unreachable
case.join.267:
  %t451 = phi ptr [ %t272, %case.end.3.269 ], [ %t450, %case.end.4.277 ]
  call void @__free_recursive(ptr %t262)
  br label %case.end.4.257
case.end.4.257:
  br label %case.join.247
case.default.246:
  unreachable
case.join.247:
  %t452 = phi ptr [ %t252, %case.end.3.249 ], [ %t451, %case.end.4.257 ]
  call void @__free_recursive(ptr %t242)
  br label %case.end.4.237
case.end.4.237:
  br label %case.join.227
case.default.226:
  unreachable
case.join.227:
  %t453 = phi ptr [ %t232, %case.end.3.229 ], [ %t452, %case.end.4.237 ]
  call void @__free_recursive(ptr %t222)
  br label %case.end.4.217
case.end.4.217:
  br label %case.join.207
case.default.206:
  unreachable
case.join.207:
  %t454 = phi ptr [ %t212, %case.end.3.209 ], [ %t453, %case.end.4.217 ]
  call void @__free_recursive(ptr %t202)
  br label %case.end.4.197
case.end.4.197:
  br label %case.join.187
case.default.186:
  unreachable
case.join.187:
  %t455 = phi ptr [ %t192, %case.end.3.189 ], [ %t454, %case.end.4.197 ]
  call void @__free_recursive(ptr %t182)
  br label %case.end.4.177
case.end.4.177:
  br label %case.join.167
case.default.166:
  unreachable
case.join.167:
  %t456 = phi ptr [ %t172, %case.end.3.169 ], [ %t455, %case.end.4.177 ]
  call void @__free_recursive(ptr %t162)
  br label %case.end.4.157
case.end.4.157:
  br label %case.join.147
case.default.146:
  unreachable
case.join.147:
  %t457 = phi ptr [ %t152, %case.end.3.149 ], [ %t456, %case.end.4.157 ]
  call void @__free_recursive(ptr %t142)
  br label %case.end.4.137
case.end.4.137:
  br label %case.join.127
case.default.126:
  unreachable
case.join.127:
  %t458 = phi ptr [ %t132, %case.end.3.129 ], [ %t457, %case.end.4.137 ]
  call void @__free_recursive(ptr %t122)
  br label %case.end.4.117
case.end.4.117:
  br label %case.join.107
case.default.106:
  unreachable
case.join.107:
  %t459 = phi ptr [ %t112, %case.end.3.109 ], [ %t458, %case.end.4.117 ]
  call void @__free_recursive(ptr %t102)
  br label %case.end.4.97
case.end.4.97:
  br label %case.join.87
case.default.86:
  unreachable
case.join.87:
  %t460 = phi ptr [ %t92, %case.end.3.89 ], [ %t459, %case.end.4.97 ]
  call void @__free_recursive(ptr %t82)
  br label %case.end.4.77
case.end.4.77:
  br label %case.join.67
case.default.66:
  unreachable
case.join.67:
  %t461 = phi ptr [ %t72, %case.end.3.69 ], [ %t460, %case.end.4.77 ]
  call void @__free_recursive(ptr %t62)
  br label %case.end.4.57
case.end.4.57:
  br label %case.join.47
case.default.46:
  unreachable
case.join.47:
  %t462 = phi ptr [ %t52, %case.end.3.49 ], [ %t461, %case.end.4.57 ]
  call void @__free_recursive(ptr %t42)
  br label %case.end.4.37
case.end.4.37:
  br label %case.join.27
case.default.26:
  unreachable
case.join.27:
  %t463 = phi ptr [ %t32, %case.end.3.29 ], [ %t462, %case.end.4.37 ]
  call void @__free_recursive(ptr %t22)
  br label %case.end.4.17
case.end.4.17:
  br label %case.join.7
case.default.6:
  unreachable
case.join.7:
  %t464 = phi ptr [ %t12, %case.end.3.9 ], [ %t463, %case.end.4.17 ]
  call void @__free_recursive(ptr %t2)
  ret ptr %t464
}

define internal ptr @v_printErr(ptr %v_e) {
  %t0 = getelementptr ptr, ptr %v_e, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 19, label %case.arm.19.4 ]
case.arm.19.4:
  %t5 = call ptr @__alloc(i64 24, i32 2)
  %t6 = inttoptr i64 7 to ptr
  %t7 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t6, ptr %t7
  %t8 = getelementptr ptr, ptr %t5, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.31, i64 12), ptr %t8
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

define internal ptr @v_main() {
  %t0 = call ptr @v_render()
  %t1 = call ptr @v_eitherToIO(ptr %t0)
  %t2 = call ptr @v__df_andThenIO_18(ptr %t1)
  %t3 = call ptr @v__df_handleErrorIO_14(ptr %t2)
  ret ptr %t3
}

define internal ptr @v__lift_13(ptr %v___input) {
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

define internal ptr @v__lift_14(ptr %v___input) {
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

define internal ptr @v__lift_15(ptr %v___input) {
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

define internal ptr @v__lift_17(ptr %v___input) {
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

define internal ptr @v__df_andThenEither_0(ptr %v_x) {
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
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t14
case.default.3:
  unreachable
}

define internal ptr @v__df_andThenEither_1(ptr %v_x) {
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
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t14
case.default.3:
  unreachable
}

define internal ptr @v__df_andThenEither_2(ptr %v_x) {
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
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t14
case.default.3:
  unreachable
}

define internal ptr @v__df__rowmono_0_andThenEither_3(ptr %v_x) {
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
  %t19 = call ptr @v__lift_13(ptr %t18)
  call void @__free_recursive(ptr %t17)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t19
case.default.3:
  unreachable
}

define internal ptr @v__df__rowmono_0_andThenEither_4(ptr %v_x) {
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
  %t19 = call ptr @v__lift_13(ptr %t18)
  call void @__free_recursive(ptr %t17)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t19
case.default.3:
  unreachable
}

define internal ptr @v__df_andThenEither_5(ptr %v_x) {
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
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t14
case.default.3:
  unreachable
}

define internal ptr @v__df__rowmono_1_andThenEither_6(ptr %v_x) {
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
  %t19 = call ptr @v__lift_14(ptr %t18)
  call void @__free_recursive(ptr %t17)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t19
case.default.3:
  unreachable
}

define internal ptr @v__df__rowmono_2_andThenEither_7(ptr %v_x) {
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
  %t19 = call ptr @v__lift_15(ptr %t18)
  call void @__free_recursive(ptr %t17)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t19
case.default.3:
  unreachable
}

define internal ptr @v__df__rowmono_2_andThenEither_8(ptr %v_x) {
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
  %t19 = call ptr @v__lift_15(ptr %t18)
  call void @__free_recursive(ptr %t17)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t19
case.default.3:
  unreachable
}

define internal ptr @v__df_andThenEither_9(ptr %v_x) {
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
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t14
case.default.3:
  unreachable
}

define internal ptr @v__df__rowmono_3_andThenEither_10(ptr %v_x) {
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
  %t15 = call ptr @v__lift_16(ptr %t14)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t15
case.default.3:
  unreachable
}

define internal ptr @v__df__rowmono_4_andThenEither_11(ptr %v_x) {
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
  %t19 = call ptr @v__lift_17(ptr %t18)
  call void @__free_recursive(ptr %t17)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t19
case.default.3:
  unreachable
}

define internal ptr @v__df__rowmono_4_andThenEither_12(ptr %v_x) {
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
  %t19 = call ptr @v__lift_17(ptr %t18)
  call void @__free_recursive(ptr %t17)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t19
case.default.3:
  unreachable
}

define internal ptr @v__df__rowmono_3_andThenEither_13(ptr %v_x) {
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
  %t15 = call ptr @v__lift_16(ptr %t14)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t15
case.default.3:
  unreachable
}

define internal ptr @v__df_handleErrorIO_14(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 41 to ptr
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
  %t22 = call ptr @v_printErr(ptr %t21)
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
  %t39 = inttoptr i64 42 to ptr
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
  %t42 = inttoptr i64 42 to ptr
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
  %t66 = inttoptr i64 30 to ptr
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
  %t78 = inttoptr i64 31 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  call void @__inc_ref(ptr %t73)
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t73, ptr %t80
  %t81 = getelementptr ptr, ptr %t74, i32 1
  store ptr %t77, ptr %t81
  %t82 = call ptr @v__apply__df_handleErrorIO_14(ptr %t6, ptr %t74)
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
  switch i64 %t9, label %tco.case.default.10 [ i64 41, label %tco.case.arm.41.11 i64 42, label %tco.case.arm.42.12 ]
tco.case.arm.41.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.42.12:
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

define internal ptr @v__df_andThenIO_18(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 43 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_18(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_18(ptr %v_io, ptr %v__k) {
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
  %t15 = call ptr @v__apply__df_andThenIO_18(ptr %t6, ptr %t14)
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
  %t23 = call ptr @v__apply__df_andThenIO_18(ptr %t6, ptr %t19)
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
  %t39 = inttoptr i64 44 to ptr
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
  %t42 = inttoptr i64 44 to ptr
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
  %t58 = call ptr @v__apply__df_andThenIO_18(ptr %t6, ptr %t50)
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
  %t66 = inttoptr i64 29 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  call void @__inc_ref(ptr %t61)
  %t68 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t61, ptr %t68
  %t69 = getelementptr ptr, ptr %t62, i32 1
  store ptr %t65, ptr %t69
  %t70 = call ptr @v__apply__df_andThenIO_18(ptr %t6, ptr %t62)
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
  %t78 = inttoptr i64 32 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  call void @__inc_ref(ptr %t73)
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t73, ptr %t80
  %t81 = getelementptr ptr, ptr %t74, i32 1
  store ptr %t77, ptr %t81
  %t82 = call ptr @v__apply__df_andThenIO_18(ptr %t6, ptr %t74)
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

define internal ptr @v__apply__df_andThenIO_18(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 43, label %tco.case.arm.43.11 i64 44, label %tco.case.arm.44.12 ]
tco.case.arm.43.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.44.12:
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

define internal ptr @v__scc__apply1__df__lam_0_19__df__lam_1_20__df__lam_10_16__df__lam_11_17__df__lam_2_21__df__lam_9_15(ptr %v__args) {
  call void @__inc_ref(ptr %v__args)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 45 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__scc__apply1__df__lam_0_19__df__lam_1_20__df__lam_10_16__df__lam_11_17__df__lam_2_21__df__lam_9_15(ptr %v__args, ptr %t0)
  call void @__free_recursive(ptr %v__args)
  ret ptr %t3
}

define internal ptr @v__cps__scc__apply1__df__lam_0_19__df__lam_1_20__df__lam_10_16__df__lam_11_17__df__lam_2_21__df__lam_9_15(ptr %v__args, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 34, label %tco.case.arm.34.11 i64 35, label %tco.case.arm.35.140 i64 36, label %tco.case.arm.36.163 i64 37, label %tco.case.arm.37.186 i64 38, label %tco.case.arm.38.209 i64 39, label %tco.case.arm.39.232 i64 40, label %tco.case.arm.40.255 ]
tco.case.arm.34.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t5, i32 2
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  %t16 = getelementptr ptr, ptr %t13, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %tco.case.default.19 [ i64 28, label %tco.case.arm.28.20 i64 29, label %tco.case.arm.29.40 i64 30, label %tco.case.arm.30.60 i64 31, label %tco.case.arm.31.80 i64 32, label %tco.case.arm.32.100 i64 33, label %tco.case.arm.33.120 ]
tco.case.arm.28.20:
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
  %t32 = inttoptr i64 35 to ptr
  %t33 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t32, ptr %t33
  call void @__inc_ref(ptr %t22)
  %t31 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t22, ptr %t31
  br label %reuse.join.28
reuse.copy.27:
  %t34 = call ptr @__alloc(i64 24, i32 2)
  %t35 = inttoptr i64 35 to ptr
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
tco.case.arm.29.40:
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
  %t52 = inttoptr i64 36 to ptr
  %t53 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t52, ptr %t53
  call void @__inc_ref(ptr %t42)
  %t51 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t42, ptr %t51
  br label %reuse.join.48
reuse.copy.47:
  %t54 = call ptr @__alloc(i64 24, i32 2)
  %t55 = inttoptr i64 36 to ptr
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
tco.case.arm.30.60:
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
  %t72 = inttoptr i64 37 to ptr
  %t73 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t72, ptr %t73
  call void @__inc_ref(ptr %t62)
  %t71 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t62, ptr %t71
  br label %reuse.join.68
reuse.copy.67:
  %t74 = call ptr @__alloc(i64 24, i32 2)
  %t75 = inttoptr i64 37 to ptr
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
tco.case.arm.31.80:
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
  %t92 = inttoptr i64 38 to ptr
  %t93 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t92, ptr %t93
  call void @__inc_ref(ptr %t82)
  %t91 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t82, ptr %t91
  br label %reuse.join.88
reuse.copy.87:
  %t94 = call ptr @__alloc(i64 24, i32 2)
  %t95 = inttoptr i64 38 to ptr
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
tco.case.arm.32.100:
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
  %t112 = inttoptr i64 39 to ptr
  %t113 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t112, ptr %t113
  call void @__inc_ref(ptr %t102)
  %t111 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t102, ptr %t111
  br label %reuse.join.108
reuse.copy.107:
  %t114 = call ptr @__alloc(i64 24, i32 2)
  %t115 = inttoptr i64 39 to ptr
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
tco.case.arm.33.120:
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
  %t132 = inttoptr i64 40 to ptr
  %t133 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t132, ptr %t133
  call void @__inc_ref(ptr %t122)
  %t131 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t122, ptr %t131
  br label %reuse.join.128
reuse.copy.127:
  %t134 = call ptr @__alloc(i64 24, i32 2)
  %t135 = inttoptr i64 40 to ptr
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
tco.case.default.19:
  unreachable
tco.case.arm.35.140:
  %t141 = getelementptr ptr, ptr %t5, i32 1
  %t142 = load ptr, ptr %t141
  %t143 = getelementptr ptr, ptr %t5, i32 2
  %t144 = load ptr, ptr %t143
  %t145 = getelementptr i8, ptr %t5, i64 -8
  %t146 = load i32, ptr %t145
  %t147 = icmp eq i32 %t146, 1
  br i1 %t147, label %reuse.in_place.148, label %reuse.copy.149
reuse.in_place.148:
  %t151 = inttoptr i64 34 to ptr
  %t152 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t151, ptr %t152
  br label %reuse.join.150
reuse.copy.149:
  %t153 = call ptr @__alloc(i64 24, i32 2)
  %t154 = inttoptr i64 34 to ptr
  %t155 = getelementptr ptr, ptr %t153, i32 0
  store ptr %t154, ptr %t155
  call void @__inc_ref(ptr %t142)
  %t156 = getelementptr ptr, ptr %t153, i32 1
  store ptr %t142, ptr %t156
  call void @__inc_ref(ptr %t144)
  %t157 = getelementptr ptr, ptr %t153, i32 2
  store ptr %t144, ptr %t157
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.150
reuse.join.150:
  %t158 = phi ptr [ %t5, %reuse.in_place.148 ], [ %t153, %reuse.copy.149 ]
  %t159 = call ptr @__alloc(i64 16, i32 1)
  %t160 = inttoptr i64 46 to ptr
  %t161 = getelementptr ptr, ptr %t159, i32 0
  store ptr %t160, ptr %t161
  call void @__inc_ref(ptr %t6)
  %t162 = getelementptr ptr, ptr %t159, i32 1
  store ptr %t6, ptr %t162
  call void @__free_recursive(ptr %t6)
  store ptr %t158, ptr %t3
  store ptr %t159, ptr %t4
  br label %tco.loop.0
tco.case.arm.36.163:
  %t164 = getelementptr ptr, ptr %t5, i32 1
  %t165 = load ptr, ptr %t164
  %t166 = getelementptr ptr, ptr %t5, i32 2
  %t167 = load ptr, ptr %t166
  %t168 = getelementptr i8, ptr %t5, i64 -8
  %t169 = load i32, ptr %t168
  %t170 = icmp eq i32 %t169, 1
  br i1 %t170, label %reuse.in_place.171, label %reuse.copy.172
reuse.in_place.171:
  %t174 = inttoptr i64 34 to ptr
  %t175 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t174, ptr %t175
  br label %reuse.join.173
reuse.copy.172:
  %t176 = call ptr @__alloc(i64 24, i32 2)
  %t177 = inttoptr i64 34 to ptr
  %t178 = getelementptr ptr, ptr %t176, i32 0
  store ptr %t177, ptr %t178
  call void @__inc_ref(ptr %t165)
  %t179 = getelementptr ptr, ptr %t176, i32 1
  store ptr %t165, ptr %t179
  call void @__inc_ref(ptr %t167)
  %t180 = getelementptr ptr, ptr %t176, i32 2
  store ptr %t167, ptr %t180
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.173
reuse.join.173:
  %t181 = phi ptr [ %t5, %reuse.in_place.171 ], [ %t176, %reuse.copy.172 ]
  %t182 = call ptr @__alloc(i64 16, i32 1)
  %t183 = inttoptr i64 47 to ptr
  %t184 = getelementptr ptr, ptr %t182, i32 0
  store ptr %t183, ptr %t184
  call void @__inc_ref(ptr %t6)
  %t185 = getelementptr ptr, ptr %t182, i32 1
  store ptr %t6, ptr %t185
  call void @__free_recursive(ptr %t6)
  store ptr %t181, ptr %t3
  store ptr %t182, ptr %t4
  br label %tco.loop.0
tco.case.arm.37.186:
  %t187 = getelementptr ptr, ptr %t5, i32 1
  %t188 = load ptr, ptr %t187
  %t189 = getelementptr ptr, ptr %t5, i32 2
  %t190 = load ptr, ptr %t189
  %t191 = getelementptr i8, ptr %t5, i64 -8
  %t192 = load i32, ptr %t191
  %t193 = icmp eq i32 %t192, 1
  br i1 %t193, label %reuse.in_place.194, label %reuse.copy.195
reuse.in_place.194:
  %t197 = inttoptr i64 34 to ptr
  %t198 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t197, ptr %t198
  br label %reuse.join.196
reuse.copy.195:
  %t199 = call ptr @__alloc(i64 24, i32 2)
  %t200 = inttoptr i64 34 to ptr
  %t201 = getelementptr ptr, ptr %t199, i32 0
  store ptr %t200, ptr %t201
  call void @__inc_ref(ptr %t188)
  %t202 = getelementptr ptr, ptr %t199, i32 1
  store ptr %t188, ptr %t202
  call void @__inc_ref(ptr %t190)
  %t203 = getelementptr ptr, ptr %t199, i32 2
  store ptr %t190, ptr %t203
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.196
reuse.join.196:
  %t204 = phi ptr [ %t5, %reuse.in_place.194 ], [ %t199, %reuse.copy.195 ]
  %t205 = call ptr @__alloc(i64 16, i32 1)
  %t206 = inttoptr i64 48 to ptr
  %t207 = getelementptr ptr, ptr %t205, i32 0
  store ptr %t206, ptr %t207
  call void @__inc_ref(ptr %t6)
  %t208 = getelementptr ptr, ptr %t205, i32 1
  store ptr %t6, ptr %t208
  call void @__free_recursive(ptr %t6)
  store ptr %t204, ptr %t3
  store ptr %t205, ptr %t4
  br label %tco.loop.0
tco.case.arm.38.209:
  %t210 = getelementptr ptr, ptr %t5, i32 1
  %t211 = load ptr, ptr %t210
  %t212 = getelementptr ptr, ptr %t5, i32 2
  %t213 = load ptr, ptr %t212
  %t214 = getelementptr i8, ptr %t5, i64 -8
  %t215 = load i32, ptr %t214
  %t216 = icmp eq i32 %t215, 1
  br i1 %t216, label %reuse.in_place.217, label %reuse.copy.218
reuse.in_place.217:
  %t220 = inttoptr i64 34 to ptr
  %t221 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t220, ptr %t221
  br label %reuse.join.219
reuse.copy.218:
  %t222 = call ptr @__alloc(i64 24, i32 2)
  %t223 = inttoptr i64 34 to ptr
  %t224 = getelementptr ptr, ptr %t222, i32 0
  store ptr %t223, ptr %t224
  call void @__inc_ref(ptr %t211)
  %t225 = getelementptr ptr, ptr %t222, i32 1
  store ptr %t211, ptr %t225
  call void @__inc_ref(ptr %t213)
  %t226 = getelementptr ptr, ptr %t222, i32 2
  store ptr %t213, ptr %t226
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.219
reuse.join.219:
  %t227 = phi ptr [ %t5, %reuse.in_place.217 ], [ %t222, %reuse.copy.218 ]
  %t228 = call ptr @__alloc(i64 16, i32 1)
  %t229 = inttoptr i64 49 to ptr
  %t230 = getelementptr ptr, ptr %t228, i32 0
  store ptr %t229, ptr %t230
  call void @__inc_ref(ptr %t6)
  %t231 = getelementptr ptr, ptr %t228, i32 1
  store ptr %t6, ptr %t231
  call void @__free_recursive(ptr %t6)
  store ptr %t227, ptr %t3
  store ptr %t228, ptr %t4
  br label %tco.loop.0
tco.case.arm.39.232:
  %t233 = getelementptr ptr, ptr %t5, i32 1
  %t234 = load ptr, ptr %t233
  %t235 = getelementptr ptr, ptr %t5, i32 2
  %t236 = load ptr, ptr %t235
  %t237 = getelementptr i8, ptr %t5, i64 -8
  %t238 = load i32, ptr %t237
  %t239 = icmp eq i32 %t238, 1
  br i1 %t239, label %reuse.in_place.240, label %reuse.copy.241
reuse.in_place.240:
  %t243 = inttoptr i64 34 to ptr
  %t244 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t243, ptr %t244
  br label %reuse.join.242
reuse.copy.241:
  %t245 = call ptr @__alloc(i64 24, i32 2)
  %t246 = inttoptr i64 34 to ptr
  %t247 = getelementptr ptr, ptr %t245, i32 0
  store ptr %t246, ptr %t247
  call void @__inc_ref(ptr %t234)
  %t248 = getelementptr ptr, ptr %t245, i32 1
  store ptr %t234, ptr %t248
  call void @__inc_ref(ptr %t236)
  %t249 = getelementptr ptr, ptr %t245, i32 2
  store ptr %t236, ptr %t249
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.242
reuse.join.242:
  %t250 = phi ptr [ %t5, %reuse.in_place.240 ], [ %t245, %reuse.copy.241 ]
  %t251 = call ptr @__alloc(i64 16, i32 1)
  %t252 = inttoptr i64 50 to ptr
  %t253 = getelementptr ptr, ptr %t251, i32 0
  store ptr %t252, ptr %t253
  call void @__inc_ref(ptr %t6)
  %t254 = getelementptr ptr, ptr %t251, i32 1
  store ptr %t6, ptr %t254
  call void @__free_recursive(ptr %t6)
  store ptr %t250, ptr %t3
  store ptr %t251, ptr %t4
  br label %tco.loop.0
tco.case.arm.40.255:
  %t256 = getelementptr ptr, ptr %t5, i32 1
  %t257 = load ptr, ptr %t256
  %t258 = getelementptr ptr, ptr %t5, i32 2
  %t259 = load ptr, ptr %t258
  %t260 = getelementptr i8, ptr %t5, i64 -8
  %t261 = load i32, ptr %t260
  %t262 = icmp eq i32 %t261, 1
  br i1 %t262, label %reuse.in_place.263, label %reuse.copy.264
reuse.in_place.263:
  %t266 = inttoptr i64 34 to ptr
  %t267 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t266, ptr %t267
  br label %reuse.join.265
reuse.copy.264:
  %t268 = call ptr @__alloc(i64 24, i32 2)
  %t269 = inttoptr i64 34 to ptr
  %t270 = getelementptr ptr, ptr %t268, i32 0
  store ptr %t269, ptr %t270
  call void @__inc_ref(ptr %t257)
  %t271 = getelementptr ptr, ptr %t268, i32 1
  store ptr %t257, ptr %t271
  call void @__inc_ref(ptr %t259)
  %t272 = getelementptr ptr, ptr %t268, i32 2
  store ptr %t259, ptr %t272
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.265
reuse.join.265:
  %t273 = phi ptr [ %t5, %reuse.in_place.263 ], [ %t268, %reuse.copy.264 ]
  %t274 = call ptr @__alloc(i64 16, i32 1)
  %t275 = inttoptr i64 51 to ptr
  %t276 = getelementptr ptr, ptr %t274, i32 0
  store ptr %t275, ptr %t276
  call void @__inc_ref(ptr %t6)
  %t277 = getelementptr ptr, ptr %t274, i32 1
  store ptr %t6, ptr %t277
  call void @__free_recursive(ptr %t6)
  store ptr %t273, ptr %t3
  store ptr %t274, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t278 = load ptr, ptr %t2
  ret ptr %t278
}

define internal ptr @v__apply1(ptr %v__cl, ptr %v__arg0) {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 34 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  call void @__inc_ref(ptr %v__cl)
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v__cl, ptr %t3
  call void @__inc_ref(ptr %v__arg0)
  %t4 = getelementptr ptr, ptr %t0, i32 2
  store ptr %v__arg0, ptr %t4
  %t5 = call ptr @v__scc__apply1__df__lam_0_19__df__lam_1_20__df__lam_10_16__df__lam_11_17__df__lam_2_21__df__lam_9_15(ptr %t0)
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
