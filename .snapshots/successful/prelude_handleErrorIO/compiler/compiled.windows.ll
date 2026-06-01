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
  %t1 = inttoptr i64 23 to ptr
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
  %t4 = inttoptr i64 24 to ptr
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
  %t4 = inttoptr i64 22 to ptr
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
  %t4 = inttoptr i64 23 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  %t7 = call ptr @v_failIO(ptr %t0)
  ret ptr %t7
}

define internal ptr @v_recover() {
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 22 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_failIO(ptr %t0)
  %t4 = call ptr @v__df_handleErrorIO_0(ptr %t3)
  ret ptr %t4
}

define internal ptr @v_dispatchA() {
  %t0 = call ptr @v_inErrA()
  %t1 = call ptr @v__df_handleErrorIO_3(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_dispatchB() {
  %t0 = call ptr @v_inErrB()
  %t1 = call ptr @v__df_handleErrorIO_3(ptr %t0)
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
  %t1 = inttoptr i64 22 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_failIO(ptr %t0)
  %t4 = call ptr @v__df_handleErrorIO_9(ptr %t3)
  %t5 = call ptr @v__df_handleErrorIO_6(ptr %t4)
  ret ptr %t5
}

define internal ptr @v_refailNarrow() {
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 22 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_failIO(ptr %t0)
  %t4 = call ptr @v__df_handleErrorIO_9(ptr %t3)
  ret ptr %t4
}

define internal ptr @v_refailRow() {
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 22 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_failIO(ptr %t0)
  %t4 = call ptr @v__df_handleErrorIO_12(ptr %t3)
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
  %t12 = call ptr @v__df_andThenIO_18(ptr %t0)
  %t13 = call ptr @v__df_handleErrorIO_15(ptr %t12)
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
  %t12 = call ptr @v__df_handleErrorIO_21(ptr %t0)
  ret ptr %t12
}

define internal ptr @v_observeNever(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @v__df_mapIO_27(ptr %v_io)
  %t1 = call ptr @v__df_andThenIO_24(ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t1
}

define internal ptr @v_handlerB(ptr %v_e) {
  %t0 = getelementptr ptr, ptr %v_e, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 23, label %case.arm.23.4 ]
case.arm.23.4:
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
  %t0 = call ptr @v__df_mapIO_27(ptr %v_io)
  %t1 = call ptr @v__lift_16(ptr %t0)
  %t2 = call ptr @v__df_andThenIO_24(ptr %t1)
  %t3 = call ptr @v__df_handleErrorIO_30(ptr %t2)
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
  %t0 = call ptr @v__df_mapIO_27(ptr %v_io)
  %t1 = call ptr @v__df__rowspec_19_36(ptr %t0)
  %t2 = call ptr @v__df_handleErrorIO_33(ptr %t1)
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
  %t12 = call ptr @v__lift_31(ptr %t0)
  %t13 = call ptr @v__df_andThenIO_45(ptr %t12)
  call void @__inc_ref(ptr %v_act)
  %t14 = call ptr @v__df_andThenIO_42(ptr %t13, ptr %v_act)
  %t15 = call ptr @v__df_andThenIO_39(ptr %t14)
  call void @__free_recursive(ptr %v_label)
  call void @__free_recursive(ptr %v_act)
  ret ptr %t15
}

define internal ptr @v_main() {
  %t0 = call ptr @v_recover()
  %t1 = call ptr @v_observeNever(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.6, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_31(ptr %t2)
  %t4 = call ptr @v__df_andThenIO_69(ptr %t3)
  %t5 = call ptr @v__df_andThenIO_66(ptr %t4)
  %t6 = call ptr @v__df_andThenIO_63(ptr %t5)
  %t7 = call ptr @v__df_andThenIO_60(ptr %t6)
  %t8 = call ptr @v__df_andThenIO_57(ptr %t7)
  %t9 = call ptr @v__df_andThenIO_54(ptr %t8)
  %t10 = call ptr @v__df_andThenIO_51(ptr %t9)
  %t11 = call ptr @v__df_andThenIO_48(ptr %t10)
  ret ptr %t11
}

define internal ptr @v__lift_1(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 142 to ptr
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
  %t57 = inttoptr i64 75 to ptr
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
  %t69 = inttoptr i64 80 to ptr
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

define internal ptr @v__lam_15(ptr %v__u) {
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 22 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_failIO(ptr %t0)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t3
}

define internal ptr @v__lift_16(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 144 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__lift_16(ptr %v___input, ptr %t0)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t3
}

define internal ptr @v__cps__lift_16(ptr %v___input, ptr %v__k) {
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
  %t18 = call ptr @v__apply__lift_16(ptr %t6, ptr %t14)
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
  %t26 = call ptr @v__apply__lift_16(ptr %t6, ptr %t22)
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
  %t42 = inttoptr i64 145 to ptr
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
  %t45 = inttoptr i64 145 to ptr
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
  %t57 = inttoptr i64 73 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  call void @__inc_ref(ptr %t52)
  %t59 = getelementptr ptr, ptr %t56, i32 1
  store ptr %t52, ptr %t59
  %t60 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t56, ptr %t60
  %t61 = call ptr @v__apply__lift_16(ptr %t6, ptr %t53)
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
  %t69 = inttoptr i64 74 to ptr
  %t70 = getelementptr ptr, ptr %t68, i32 0
  store ptr %t69, ptr %t70
  call void @__inc_ref(ptr %t64)
  %t71 = getelementptr ptr, ptr %t68, i32 1
  store ptr %t64, ptr %t71
  %t72 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t68, ptr %t72
  %t73 = call ptr @v__apply__lift_16(ptr %t6, ptr %t65)
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

define internal ptr @v__apply__lift_16(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__lift_20(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 146 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__lift_20(ptr %v___input, ptr %t0)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t3
}

define internal ptr @v__cps__lift_20(ptr %v___input, ptr %v__k) {
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
  %t18 = call ptr @v__apply__lift_20(ptr %t6, ptr %t14)
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
  %t30 = call ptr @v__apply__lift_20(ptr %t6, ptr %t22)
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
  %t46 = inttoptr i64 147 to ptr
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
  %t49 = inttoptr i64 147 to ptr
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
  %t61 = inttoptr i64 76 to ptr
  %t62 = getelementptr ptr, ptr %t60, i32 0
  store ptr %t61, ptr %t62
  call void @__inc_ref(ptr %t56)
  %t63 = getelementptr ptr, ptr %t60, i32 1
  store ptr %t56, ptr %t63
  %t64 = getelementptr ptr, ptr %t57, i32 1
  store ptr %t60, ptr %t64
  %t65 = call ptr @v__apply__lift_20(ptr %t6, ptr %t57)
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
  %t73 = inttoptr i64 77 to ptr
  %t74 = getelementptr ptr, ptr %t72, i32 0
  store ptr %t73, ptr %t74
  call void @__inc_ref(ptr %t68)
  %t75 = getelementptr ptr, ptr %t72, i32 1
  store ptr %t68, ptr %t75
  %t76 = getelementptr ptr, ptr %t69, i32 1
  store ptr %t72, ptr %t76
  %t77 = call ptr @v__apply__lift_20(ptr %t6, ptr %t69)
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

define internal ptr @v__apply__lift_20(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__lam_28(ptr %v__u) {
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

define internal ptr @v__lam_29(ptr %v_act, ptr %v__u) {
  call void @__free_recursive(ptr %v__u)
  ret ptr %v_act
}

define internal ptr @v__lam_30(ptr %v__u) {
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

define internal ptr @v__lift_31(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 150 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__lift_31(ptr %v___input, ptr %t0)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t3
}

define internal ptr @v__cps__lift_31(ptr %v___input, ptr %v__k) {
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
  %t18 = call ptr @v__apply__lift_31(ptr %t6, ptr %t14)
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
  %t26 = call ptr @v__apply__lift_31(ptr %t6, ptr %t22)
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
  %t42 = inttoptr i64 151 to ptr
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
  %t45 = inttoptr i64 151 to ptr
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
  %t57 = inttoptr i64 81 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  call void @__inc_ref(ptr %t52)
  %t59 = getelementptr ptr, ptr %t56, i32 1
  store ptr %t52, ptr %t59
  %t60 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t56, ptr %t60
  %t61 = call ptr @v__apply__lift_31(ptr %t6, ptr %t53)
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
  %t69 = inttoptr i64 82 to ptr
  %t70 = getelementptr ptr, ptr %t68, i32 0
  store ptr %t69, ptr %t70
  call void @__inc_ref(ptr %t64)
  %t71 = getelementptr ptr, ptr %t68, i32 1
  store ptr %t64, ptr %t71
  %t72 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t68, ptr %t72
  %t73 = call ptr @v__apply__lift_31(ptr %t6, ptr %t65)
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

define internal ptr @v__apply__lift_31(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__lam_34(ptr %v__u) {
  %t0 = call ptr @v_treeNoError()
  %t1 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.9, i64 12), ptr %t0)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t1
}

define internal ptr @v__lam_35(ptr %v__u) {
  %t0 = call ptr @v_treePreserve()
  %t1 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.10, i64 12), ptr %t0)
  %t2 = call ptr @v__lift_31(ptr %t1)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t2
}

define internal ptr @v__lam_36(ptr %v__u) {
  %t0 = call ptr @v_refailRow()
  %t1 = call ptr @v_observeBC(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.11, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_31(ptr %t2)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t3
}

define internal ptr @v__lam_37(ptr %v__u) {
  %t0 = call ptr @v_refailNarrow()
  %t1 = call ptr @v_observeB(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.12, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_31(ptr %t2)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t3
}

define internal ptr @v__lam_38(ptr %v__u) {
  %t0 = call ptr @v_nested()
  %t1 = call ptr @v_observeNever(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.13, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_31(ptr %t2)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t3
}

define internal ptr @v__lam_39(ptr %v__u) {
  %t0 = call ptr @v_passthrough()
  %t1 = call ptr @v_observeNever(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.14, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_31(ptr %t2)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t3
}

define internal ptr @v__lam_40(ptr %v__u) {
  %t0 = call ptr @v_dispatchB()
  %t1 = call ptr @v_observeNever(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.15, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_31(ptr %t2)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t3
}

define internal ptr @v__lam_41(ptr %v__u) {
  %t0 = call ptr @v_dispatchA()
  %t1 = call ptr @v_observeNever(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.16, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_31(ptr %t2)
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
  %t1 = inttoptr i64 152 to ptr
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
  %t39 = inttoptr i64 153 to ptr
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
  %t42 = inttoptr i64 153 to ptr
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
  %t66 = inttoptr i64 37 to ptr
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
tco.case.default.10:
  unreachable
tco.exit.1:
  %t71 = load ptr, ptr %t2
  ret ptr %t71
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

define internal ptr @v__df_handleErrorIO_3(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 154 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_handleErrorIO_3(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_handleErrorIO_3(ptr %v_io, ptr %v__k) {
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
  %t18 = call ptr @v__apply__df_handleErrorIO_3(ptr %t6, ptr %t14)
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
  %t23 = call ptr @v__apply__df_handleErrorIO_3(ptr %t6, ptr %t22)
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
  %t39 = inttoptr i64 155 to ptr
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
  %t42 = inttoptr i64 155 to ptr
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
  %t58 = call ptr @v__apply__df_handleErrorIO_3(ptr %t6, ptr %t50)
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
  %t70 = call ptr @v__apply__df_handleErrorIO_3(ptr %t6, ptr %t62)
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

define internal ptr @v__apply__df_handleErrorIO_3(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__df_handleErrorIO_6(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 156 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_handleErrorIO_6(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_handleErrorIO_6(ptr %v_io, ptr %v__k) {
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
  %t18 = call ptr @v__apply__df_handleErrorIO_6(ptr %t6, ptr %t14)
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
  %t23 = call ptr @v__apply__df_handleErrorIO_6(ptr %t6, ptr %t22)
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
  %t54 = inttoptr i64 33 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  call void @__inc_ref(ptr %t49)
  %t56 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t49, ptr %t56
  %t57 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t53, ptr %t57
  %t58 = call ptr @v__apply__df_handleErrorIO_6(ptr %t6, ptr %t50)
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
  %t70 = call ptr @v__apply__df_handleErrorIO_6(ptr %t6, ptr %t62)
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

define internal ptr @v__apply__df_handleErrorIO_6(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__df_handleErrorIO_9(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 158 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_handleErrorIO_9(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_handleErrorIO_9(ptr %v_io, ptr %v__k) {
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
  %t18 = call ptr @v__apply__df_handleErrorIO_9(ptr %t6, ptr %t14)
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
  %t23 = call ptr @v__apply__df_handleErrorIO_9(ptr %t6, ptr %t22)
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
  %t39 = inttoptr i64 159 to ptr
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
  %t42 = inttoptr i64 159 to ptr
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
  %t58 = call ptr @v__apply__df_handleErrorIO_9(ptr %t6, ptr %t50)
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
  %t70 = call ptr @v__apply__df_handleErrorIO_9(ptr %t6, ptr %t62)
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

define internal ptr @v__apply__df_handleErrorIO_9(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__df_handleErrorIO_12(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 160 to ptr
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
  %t22 = call ptr @v_refailRowH(ptr %t21)
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
  %t39 = inttoptr i64 161 to ptr
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
  %t42 = inttoptr i64 161 to ptr
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
  %t66 = inttoptr i64 35 to ptr
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
tco.case.default.10:
  unreachable
tco.exit.1:
  %t71 = load ptr, ptr %t2
  ret ptr %t71
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

define internal ptr @v__df_handleErrorIO_15(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 162 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_handleErrorIO_15(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_handleErrorIO_15(ptr %v_io, ptr %v__k) {
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
  %t18 = call ptr @v__apply__df_handleErrorIO_15(ptr %t6, ptr %t14)
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
  %t23 = call ptr @v__apply__df_handleErrorIO_15(ptr %t6, ptr %t22)
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
  %t39 = inttoptr i64 163 to ptr
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
  %t42 = inttoptr i64 163 to ptr
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
  %t58 = call ptr @v__apply__df_handleErrorIO_15(ptr %t6, ptr %t50)
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
  %t70 = call ptr @v__apply__df_handleErrorIO_15(ptr %t6, ptr %t62)
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

define internal ptr @v__apply__df_handleErrorIO_15(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__df_andThenIO_18(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 164 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.17 i64 7, label %tco.case.arm.7.25 i64 8, label %tco.case.arm.8.48 i64 9, label %tco.case.arm.9.60 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_15(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_18(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_18(ptr %t6, ptr %t20)
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
  %t55 = inttoptr i64 45 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df_andThenIO_18(ptr %t6, ptr %t51)
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
  %t71 = call ptr @v__apply__df_andThenIO_18(ptr %t6, ptr %t63)
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

define internal ptr @v__df_handleErrorIO_21(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 166 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_handleErrorIO_21(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_handleErrorIO_21(ptr %v_io, ptr %v__k) {
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
  %t18 = call ptr @v__apply__df_handleErrorIO_21(ptr %t6, ptr %t14)
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
  %t23 = call ptr @v__apply__df_handleErrorIO_21(ptr %t6, ptr %t22)
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
  %t39 = inttoptr i64 167 to ptr
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
  %t42 = inttoptr i64 167 to ptr
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
  %t58 = call ptr @v__apply__df_handleErrorIO_21(ptr %t6, ptr %t50)
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
  %t70 = call ptr @v__apply__df_handleErrorIO_21(ptr %t6, ptr %t62)
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

define internal ptr @v__apply__df_handleErrorIO_21(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__df_andThenIO_24(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 168 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.17 i64 7, label %tco.case.arm.7.25 i64 8, label %tco.case.arm.8.48 i64 9, label %tco.case.arm.9.60 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__bi_IO_Stdout_print(ptr %t13)
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
  %t55 = inttoptr i64 46 to ptr
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
  %t67 = inttoptr i64 59 to ptr
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
tco.case.default.10:
  unreachable
tco.exit.1:
  %t72 = load ptr, ptr %t2
  ret ptr %t72
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

define internal ptr @v__df_mapIO_27(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 170 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_mapIO_27(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_mapIO_27(ptr %v_io, ptr %v__k) {
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
  %t19 = call ptr @v__apply__df_mapIO_27(ptr %t6, ptr %t14)
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
  %t27 = call ptr @v__apply__df_mapIO_27(ptr %t6, ptr %t23)
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
  %t43 = inttoptr i64 171 to ptr
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
  %t46 = inttoptr i64 171 to ptr
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
  %t58 = inttoptr i64 71 to ptr
  %t59 = getelementptr ptr, ptr %t57, i32 0
  store ptr %t58, ptr %t59
  call void @__inc_ref(ptr %t53)
  %t60 = getelementptr ptr, ptr %t57, i32 1
  store ptr %t53, ptr %t60
  %t61 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t57, ptr %t61
  %t62 = call ptr @v__apply__df_mapIO_27(ptr %t6, ptr %t54)
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
  %t70 = inttoptr i64 72 to ptr
  %t71 = getelementptr ptr, ptr %t69, i32 0
  store ptr %t70, ptr %t71
  call void @__inc_ref(ptr %t65)
  %t72 = getelementptr ptr, ptr %t69, i32 1
  store ptr %t65, ptr %t72
  %t73 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t69, ptr %t73
  %t74 = call ptr @v__apply__df_mapIO_27(ptr %t6, ptr %t66)
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

define internal ptr @v__apply__df_mapIO_27(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__df_handleErrorIO_30(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 172 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_handleErrorIO_30(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_handleErrorIO_30(ptr %v_io, ptr %v__k) {
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
  %t18 = call ptr @v__apply__df_handleErrorIO_30(ptr %t6, ptr %t14)
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
  %t23 = call ptr @v__apply__df_handleErrorIO_30(ptr %t6, ptr %t22)
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
  %t54 = inttoptr i64 30 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  call void @__inc_ref(ptr %t49)
  %t56 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t49, ptr %t56
  %t57 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t53, ptr %t57
  %t58 = call ptr @v__apply__df_handleErrorIO_30(ptr %t6, ptr %t50)
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
  %t70 = call ptr @v__apply__df_handleErrorIO_30(ptr %t6, ptr %t62)
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

define internal ptr @v__apply__df_handleErrorIO_30(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__df_handleErrorIO_33(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 174 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_handleErrorIO_33(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_handleErrorIO_33(ptr %v_io, ptr %v__k) {
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
  %t18 = call ptr @v__apply__df_handleErrorIO_33(ptr %t6, ptr %t14)
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
  %t23 = call ptr @v__apply__df_handleErrorIO_33(ptr %t6, ptr %t22)
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
  %t54 = inttoptr i64 31 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  call void @__inc_ref(ptr %t49)
  %t56 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t49, ptr %t56
  %t57 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t53, ptr %t57
  %t58 = call ptr @v__apply__df_handleErrorIO_33(ptr %t6, ptr %t50)
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
  %t70 = call ptr @v__apply__df_handleErrorIO_33(ptr %t6, ptr %t62)
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

define internal ptr @v__apply__df_handleErrorIO_33(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__df__rowspec_19_36(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 176 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df__rowspec_19_36(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df__rowspec_19_36(ptr %v_io, ptr %v__k) {
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
  %t15 = call ptr @v__lift_20(ptr %t14)
  %t16 = call ptr @v__apply__df__rowspec_19_36(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df__rowspec_19_36(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 177 to ptr
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
  %t43 = inttoptr i64 177 to ptr
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
  %t59 = call ptr @v__apply__df__rowspec_19_36(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 44 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df__rowspec_19_36(ptr %t6, ptr %t63)
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

define internal ptr @v__apply__df__rowspec_19_36(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__df_andThenIO_39(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 178 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_39(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_39(ptr %v_io, ptr %v__k) {
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
  %t14 = call ptr @v__lam_28(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_39(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_39(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 179 to ptr
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
  %t43 = inttoptr i64 179 to ptr
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
  %t59 = call ptr @v__apply__df_andThenIO_39(ptr %t6, ptr %t51)
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
  %t71 = call ptr @v__apply__df_andThenIO_39(ptr %t6, ptr %t63)
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

define internal ptr @v__apply__df_andThenIO_39(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__df_andThenIO_42(ptr %v_io, ptr %v__df_andThenIO_42_cap0_0) {
  call void @__inc_ref(ptr %v_io)
  call void @__inc_ref(ptr %v__df_andThenIO_42_cap0_0)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 180 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_42(ptr %v_io, ptr %v__df_andThenIO_42_cap0_0, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  call void @__free_recursive(ptr %v__df_andThenIO_42_cap0_0)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_42(ptr %v_io, ptr %v__df_andThenIO_42_cap0_0, ptr %v__k) {
entry:
  %t3 = alloca ptr
  store ptr %v_io, ptr %t3
  %t4 = alloca ptr
  store ptr %v__df_andThenIO_42_cap0_0, ptr %t4
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
  %t16 = call ptr @v__lam_29(ptr %t7, ptr %t15)
  %t17 = call ptr @v__lift_1(ptr %t16)
  %t18 = call ptr @v__apply__df_andThenIO_42(ptr %t8, ptr %t17)
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
  %t26 = call ptr @v__apply__df_andThenIO_42(ptr %t8, ptr %t22)
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
  %t42 = inttoptr i64 181 to ptr
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
  %t45 = inttoptr i64 181 to ptr
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
  %t57 = inttoptr i64 48 to ptr
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
  %t62 = call ptr @v__apply__df_andThenIO_42(ptr %t8, ptr %t53)
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
  %t70 = inttoptr i64 61 to ptr
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
  %t75 = call ptr @v__apply__df_andThenIO_42(ptr %t8, ptr %t66)
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

define internal ptr @v__apply__df_andThenIO_42(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__df_andThenIO_45(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 182 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_45(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_45(ptr %v_io, ptr %v__k) {
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
  %t14 = call ptr @v__lam_30(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_45(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_45(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 183 to ptr
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
  %t43 = inttoptr i64 183 to ptr
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
  %t59 = call ptr @v__apply__df_andThenIO_45(ptr %t6, ptr %t51)
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
  %t71 = call ptr @v__apply__df_andThenIO_45(ptr %t6, ptr %t63)
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

define internal ptr @v__apply__df_andThenIO_45(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__df_andThenIO_48(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 184 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.17 i64 7, label %tco.case.arm.7.25 i64 8, label %tco.case.arm.8.48 i64 9, label %tco.case.arm.9.60 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_34(ptr %t13)
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
  %t40 = inttoptr i64 185 to ptr
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
  %t43 = inttoptr i64 185 to ptr
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
  %t67 = inttoptr i64 63 to ptr
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
tco.case.default.10:
  unreachable
tco.exit.1:
  %t72 = load ptr, ptr %t2
  ret ptr %t72
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

define internal ptr @v__df_andThenIO_51(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 186 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_51(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_51(ptr %v_io, ptr %v__k) {
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
  %t14 = call ptr @v__lam_35(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_51(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_51(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 187 to ptr
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
  %t43 = inttoptr i64 187 to ptr
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
  %t59 = call ptr @v__apply__df_andThenIO_51(ptr %t6, ptr %t51)
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
  %t71 = call ptr @v__apply__df_andThenIO_51(ptr %t6, ptr %t63)
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

define internal ptr @v__apply__df_andThenIO_51(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__df_andThenIO_54(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 188 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_54(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_54(ptr %v_io, ptr %v__k) {
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
  %t14 = call ptr @v__lam_36(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_54(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_54(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 189 to ptr
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
  %t43 = inttoptr i64 189 to ptr
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
  %t59 = call ptr @v__apply__df_andThenIO_54(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 65 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df_andThenIO_54(ptr %t6, ptr %t63)
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

define internal ptr @v__apply__df_andThenIO_54(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__df_andThenIO_57(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 190 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_57(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_57(ptr %v_io, ptr %v__k) {
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
  %t14 = call ptr @v__lam_37(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_57(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_57(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 191 to ptr
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
  %t43 = inttoptr i64 191 to ptr
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
  %t59 = call ptr @v__apply__df_andThenIO_57(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 66 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df_andThenIO_57(ptr %t6, ptr %t63)
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

define internal ptr @v__apply__df_andThenIO_57(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__df_andThenIO_60(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 192 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.17 i64 7, label %tco.case.arm.7.25 i64 8, label %tco.case.arm.8.48 i64 9, label %tco.case.arm.9.60 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_38(ptr %t13)
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
  %t40 = inttoptr i64 193 to ptr
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
  %t43 = inttoptr i64 193 to ptr
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
  %t67 = inttoptr i64 67 to ptr
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
tco.case.default.10:
  unreachable
tco.exit.1:
  %t72 = load ptr, ptr %t2
  ret ptr %t72
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

define internal ptr @v__df_andThenIO_63(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 194 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_63(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_63(ptr %v_io, ptr %v__k) {
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
  %t14 = call ptr @v__lam_39(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_63(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_63(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 195 to ptr
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
  %t43 = inttoptr i64 195 to ptr
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
  %t59 = call ptr @v__apply__df_andThenIO_63(ptr %t6, ptr %t51)
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
  %t71 = call ptr @v__apply__df_andThenIO_63(ptr %t6, ptr %t63)
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

define internal ptr @v__apply__df_andThenIO_63(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__df_andThenIO_66(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 196 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_66(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_66(ptr %v_io, ptr %v__k) {
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
  %t14 = call ptr @v__lam_40(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_66(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_66(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 197 to ptr
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
  %t43 = inttoptr i64 197 to ptr
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
  %t59 = call ptr @v__apply__df_andThenIO_66(ptr %t6, ptr %t51)
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
  %t71 = call ptr @v__apply__df_andThenIO_66(ptr %t6, ptr %t63)
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

define internal ptr @v__apply__df_andThenIO_66(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__df_andThenIO_69(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 198 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_69(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_69(ptr %v_io, ptr %v__k) {
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
  %t14 = call ptr @v__lam_41(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_69(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_69(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 199 to ptr
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
  %t43 = inttoptr i64 199 to ptr
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
  %t59 = call ptr @v__apply__df_andThenIO_69(ptr %t6, ptr %t51)
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
  %t71 = call ptr @v__apply__df_andThenIO_69(ptr %t6, ptr %t63)
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

define internal ptr @v__apply__df_andThenIO_69(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__scc__apply1__df__lam_10_1__df__lam_10_10__df__lam_10_13__df__lam_10_16__df__lam_10_22__df__lam_10_31__df__lam_10_34__df__lam_10_4__df__lam_10_7__df__lam_11_11__df__lam_11_14__df__lam_11_17__df__lam_11_2__df__lam_11_23__df__lam_11_32__df__lam_11_35__df__lam_11_5__df__lam_11_8__df__lam_26_37__df__lam_27_38__df__lam_4_19__df__lam_4_25__df__lam_4_40__df__lam_4_43__df__lam_4_46__df__lam_4_49__df__lam_4_52__df__lam_4_55__df__lam_4_58__df__lam_4_61__df__lam_4_64__df__lam_4_67__df__lam_4_70__df__lam_5_20__df__lam_5_26__df__lam_5_41__df__lam_5_44__df__lam_5_47__df__lam_5_50__df__lam_5_53__df__lam_5_56__df__lam_5_59__df__lam_5_62__df__lam_5_65__df__lam_5_68__df__lam_5_71__df__lam_6_28__df__lam_7_29__lift_17__lift_18__lift_2__lift_21__lift_22__lift_24__lift_25__lift_3__lift_32__lift_33(ptr %v__args) {
  call void @__inc_ref(ptr %v__args)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 200 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__scc__apply1__df__lam_10_1__df__lam_10_10__df__lam_10_13__df__lam_10_16__df__lam_10_22__df__lam_10_31__df__lam_10_34__df__lam_10_4__df__lam_10_7__df__lam_11_11__df__lam_11_14__df__lam_11_17__df__lam_11_2__df__lam_11_23__df__lam_11_32__df__lam_11_35__df__lam_11_5__df__lam_11_8__df__lam_26_37__df__lam_27_38__df__lam_4_19__df__lam_4_25__df__lam_4_40__df__lam_4_43__df__lam_4_46__df__lam_4_49__df__lam_4_52__df__lam_4_55__df__lam_4_58__df__lam_4_61__df__lam_4_64__df__lam_4_67__df__lam_4_70__df__lam_5_20__df__lam_5_26__df__lam_5_41__df__lam_5_44__df__lam_5_47__df__lam_5_50__df__lam_5_53__df__lam_5_56__df__lam_5_59__df__lam_5_62__df__lam_5_65__df__lam_5_68__df__lam_5_71__df__lam_6_28__df__lam_7_29__lift_17__lift_18__lift_2__lift_21__lift_22__lift_24__lift_25__lift_3__lift_32__lift_33(ptr %v__args, ptr %t0)
  call void @__free_recursive(ptr %v__args)
  ret ptr %t3
}

define internal ptr @v__cps__scc__apply1__df__lam_10_1__df__lam_10_10__df__lam_10_13__df__lam_10_16__df__lam_10_22__df__lam_10_31__df__lam_10_34__df__lam_10_4__df__lam_10_7__df__lam_11_11__df__lam_11_14__df__lam_11_17__df__lam_11_2__df__lam_11_23__df__lam_11_32__df__lam_11_35__df__lam_11_5__df__lam_11_8__df__lam_26_37__df__lam_27_38__df__lam_4_19__df__lam_4_25__df__lam_4_40__df__lam_4_43__df__lam_4_46__df__lam_4_49__df__lam_4_52__df__lam_4_55__df__lam_4_58__df__lam_4_61__df__lam_4_64__df__lam_4_67__df__lam_4_70__df__lam_5_20__df__lam_5_26__df__lam_5_41__df__lam_5_44__df__lam_5_47__df__lam_5_50__df__lam_5_53__df__lam_5_56__df__lam_5_59__df__lam_5_62__df__lam_5_65__df__lam_5_68__df__lam_5_71__df__lam_6_28__df__lam_7_29__lift_17__lift_18__lift_2__lift_21__lift_22__lift_24__lift_25__lift_3__lift_32__lift_33(ptr %v__args, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 83, label %tco.case.arm.83.11 i64 84, label %tco.case.arm.84.1122 i64 85, label %tco.case.arm.85.1145 i64 86, label %tco.case.arm.86.1168 i64 87, label %tco.case.arm.87.1191 i64 88, label %tco.case.arm.88.1214 i64 89, label %tco.case.arm.89.1237 i64 90, label %tco.case.arm.90.1260 i64 91, label %tco.case.arm.91.1283 i64 92, label %tco.case.arm.92.1306 i64 93, label %tco.case.arm.93.1329 i64 94, label %tco.case.arm.94.1352 i64 95, label %tco.case.arm.95.1375 i64 96, label %tco.case.arm.96.1398 i64 97, label %tco.case.arm.97.1421 i64 98, label %tco.case.arm.98.1444 i64 99, label %tco.case.arm.99.1467 i64 100, label %tco.case.arm.100.1490 i64 101, label %tco.case.arm.101.1513 i64 102, label %tco.case.arm.102.1536 i64 103, label %tco.case.arm.103.1559 i64 104, label %tco.case.arm.104.1582 i64 105, label %tco.case.arm.105.1605 i64 106, label %tco.case.arm.106.1628 i64 107, label %tco.case.arm.107.1651 i64 108, label %tco.case.arm.108.1668 i64 109, label %tco.case.arm.109.1691 i64 110, label %tco.case.arm.110.1714 i64 111, label %tco.case.arm.111.1737 i64 112, label %tco.case.arm.112.1760 i64 113, label %tco.case.arm.113.1783 i64 114, label %tco.case.arm.114.1806 i64 115, label %tco.case.arm.115.1829 i64 116, label %tco.case.arm.116.1852 i64 117, label %tco.case.arm.117.1875 i64 118, label %tco.case.arm.118.1898 i64 119, label %tco.case.arm.119.1921 i64 120, label %tco.case.arm.120.1944 i64 121, label %tco.case.arm.121.1961 i64 122, label %tco.case.arm.122.1984 i64 123, label %tco.case.arm.123.2007 i64 124, label %tco.case.arm.124.2030 i64 125, label %tco.case.arm.125.2053 i64 126, label %tco.case.arm.126.2076 i64 127, label %tco.case.arm.127.2099 i64 128, label %tco.case.arm.128.2122 i64 129, label %tco.case.arm.129.2145 i64 130, label %tco.case.arm.130.2168 i64 131, label %tco.case.arm.131.2191 i64 132, label %tco.case.arm.132.2214 i64 133, label %tco.case.arm.133.2237 i64 134, label %tco.case.arm.134.2260 i64 135, label %tco.case.arm.135.2283 i64 136, label %tco.case.arm.136.2306 i64 139, label %tco.case.arm.139.2329 i64 140, label %tco.case.arm.140.2352 i64 141, label %tco.case.arm.141.2375 ]
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
  switch i64 %t18, label %tco.case.default.19 [ i64 25, label %tco.case.arm.25.20 i64 26, label %tco.case.arm.26.40 i64 27, label %tco.case.arm.27.60 i64 28, label %tco.case.arm.28.80 i64 29, label %tco.case.arm.29.100 i64 30, label %tco.case.arm.30.120 i64 31, label %tco.case.arm.31.140 i64 32, label %tco.case.arm.32.160 i64 33, label %tco.case.arm.33.180 i64 34, label %tco.case.arm.34.200 i64 35, label %tco.case.arm.35.220 i64 36, label %tco.case.arm.36.240 i64 37, label %tco.case.arm.37.260 i64 38, label %tco.case.arm.38.280 i64 39, label %tco.case.arm.39.300 i64 40, label %tco.case.arm.40.320 i64 41, label %tco.case.arm.41.340 i64 42, label %tco.case.arm.42.360 i64 43, label %tco.case.arm.43.380 i64 44, label %tco.case.arm.44.400 i64 45, label %tco.case.arm.45.420 i64 46, label %tco.case.arm.46.440 i64 47, label %tco.case.arm.47.460 i64 48, label %tco.case.arm.48.480 i64 49, label %tco.case.arm.49.491 i64 50, label %tco.case.arm.50.511 i64 51, label %tco.case.arm.51.531 i64 52, label %tco.case.arm.52.551 i64 53, label %tco.case.arm.53.571 i64 54, label %tco.case.arm.54.591 i64 55, label %tco.case.arm.55.611 i64 56, label %tco.case.arm.56.631 i64 57, label %tco.case.arm.57.651 i64 58, label %tco.case.arm.58.671 i64 59, label %tco.case.arm.59.691 i64 60, label %tco.case.arm.60.711 i64 61, label %tco.case.arm.61.731 i64 62, label %tco.case.arm.62.742 i64 63, label %tco.case.arm.63.762 i64 64, label %tco.case.arm.64.782 i64 65, label %tco.case.arm.65.802 i64 66, label %tco.case.arm.66.822 i64 67, label %tco.case.arm.67.842 i64 68, label %tco.case.arm.68.862 i64 69, label %tco.case.arm.69.882 i64 70, label %tco.case.arm.70.902 i64 71, label %tco.case.arm.71.922 i64 72, label %tco.case.arm.72.942 i64 73, label %tco.case.arm.73.962 i64 74, label %tco.case.arm.74.982 i64 75, label %tco.case.arm.75.1002 i64 76, label %tco.case.arm.76.1022 i64 77, label %tco.case.arm.77.1042 i64 80, label %tco.case.arm.80.1062 i64 81, label %tco.case.arm.81.1082 i64 82, label %tco.case.arm.82.1102 ]
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
tco.case.arm.37.260:
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
tco.case.arm.38.280:
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
tco.case.arm.39.300:
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
tco.case.arm.40.320:
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
tco.case.arm.41.340:
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
tco.case.arm.42.360:
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
tco.case.arm.43.380:
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
tco.case.arm.44.400:
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
tco.case.arm.45.420:
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
tco.case.arm.46.440:
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
tco.case.arm.47.460:
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
tco.case.arm.48.480:
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
tco.case.arm.49.491:
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
tco.case.arm.50.511:
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
tco.case.arm.51.531:
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
tco.case.arm.52.551:
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
tco.case.arm.53.571:
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
tco.case.arm.54.591:
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
tco.case.arm.55.611:
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
  %t623 = inttoptr i64 114 to ptr
  %t624 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t623, ptr %t624
  call void @__inc_ref(ptr %t613)
  %t622 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t613, ptr %t622
  br label %reuse.join.619
reuse.copy.618:
  %t625 = call ptr @__alloc(i64 24, i32 2)
  %t626 = inttoptr i64 114 to ptr
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
tco.case.arm.56.631:
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
  %t643 = inttoptr i64 115 to ptr
  %t644 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t643, ptr %t644
  call void @__inc_ref(ptr %t633)
  %t642 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t633, ptr %t642
  br label %reuse.join.639
reuse.copy.638:
  %t645 = call ptr @__alloc(i64 24, i32 2)
  %t646 = inttoptr i64 115 to ptr
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
tco.case.arm.57.651:
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
  %t663 = inttoptr i64 116 to ptr
  %t664 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t663, ptr %t664
  call void @__inc_ref(ptr %t653)
  %t662 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t653, ptr %t662
  br label %reuse.join.659
reuse.copy.658:
  %t665 = call ptr @__alloc(i64 24, i32 2)
  %t666 = inttoptr i64 116 to ptr
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
tco.case.arm.58.671:
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
  %t683 = inttoptr i64 117 to ptr
  %t684 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t683, ptr %t684
  call void @__inc_ref(ptr %t673)
  %t682 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t673, ptr %t682
  br label %reuse.join.679
reuse.copy.678:
  %t685 = call ptr @__alloc(i64 24, i32 2)
  %t686 = inttoptr i64 117 to ptr
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
tco.case.arm.59.691:
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
  %t703 = inttoptr i64 118 to ptr
  %t704 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t703, ptr %t704
  call void @__inc_ref(ptr %t693)
  %t702 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t693, ptr %t702
  br label %reuse.join.699
reuse.copy.698:
  %t705 = call ptr @__alloc(i64 24, i32 2)
  %t706 = inttoptr i64 118 to ptr
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
tco.case.arm.60.711:
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
  %t723 = inttoptr i64 119 to ptr
  %t724 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t723, ptr %t724
  call void @__inc_ref(ptr %t713)
  %t722 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t713, ptr %t722
  br label %reuse.join.719
reuse.copy.718:
  %t725 = call ptr @__alloc(i64 24, i32 2)
  %t726 = inttoptr i64 119 to ptr
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
tco.case.arm.61.731:
  %t732 = getelementptr ptr, ptr %t13, i32 1
  %t733 = load ptr, ptr %t732
  call void @__inc_ref(ptr %t733)
  %t734 = getelementptr ptr, ptr %t13, i32 2
  %t735 = load ptr, ptr %t734
  call void @__inc_ref(ptr %t735)
  %t736 = call ptr @__alloc(i64 32, i32 3)
  %t737 = inttoptr i64 120 to ptr
  %t738 = getelementptr ptr, ptr %t736, i32 0
  store ptr %t737, ptr %t738
  call void @__inc_ref(ptr %t733)
  %t739 = getelementptr ptr, ptr %t736, i32 1
  store ptr %t733, ptr %t739
  call void @__inc_ref(ptr %t735)
  %t740 = getelementptr ptr, ptr %t736, i32 2
  store ptr %t735, ptr %t740
  call void @__inc_ref(ptr %t15)
  %t741 = getelementptr ptr, ptr %t736, i32 3
  store ptr %t15, ptr %t741
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t735)
  call void @__free_recursive(ptr %t733)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t736, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.62.742:
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
  %t754 = inttoptr i64 121 to ptr
  %t755 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t754, ptr %t755
  call void @__inc_ref(ptr %t744)
  %t753 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t744, ptr %t753
  br label %reuse.join.750
reuse.copy.749:
  %t756 = call ptr @__alloc(i64 24, i32 2)
  %t757 = inttoptr i64 121 to ptr
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
tco.case.arm.63.762:
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
  %t774 = inttoptr i64 122 to ptr
  %t775 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t774, ptr %t775
  call void @__inc_ref(ptr %t764)
  %t773 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t764, ptr %t773
  br label %reuse.join.770
reuse.copy.769:
  %t776 = call ptr @__alloc(i64 24, i32 2)
  %t777 = inttoptr i64 122 to ptr
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
tco.case.arm.64.782:
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
  %t794 = inttoptr i64 123 to ptr
  %t795 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t794, ptr %t795
  call void @__inc_ref(ptr %t784)
  %t793 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t784, ptr %t793
  br label %reuse.join.790
reuse.copy.789:
  %t796 = call ptr @__alloc(i64 24, i32 2)
  %t797 = inttoptr i64 123 to ptr
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
tco.case.arm.65.802:
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
  %t814 = inttoptr i64 124 to ptr
  %t815 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t814, ptr %t815
  call void @__inc_ref(ptr %t804)
  %t813 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t804, ptr %t813
  br label %reuse.join.810
reuse.copy.809:
  %t816 = call ptr @__alloc(i64 24, i32 2)
  %t817 = inttoptr i64 124 to ptr
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
tco.case.arm.66.822:
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
  %t834 = inttoptr i64 125 to ptr
  %t835 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t834, ptr %t835
  call void @__inc_ref(ptr %t824)
  %t833 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t824, ptr %t833
  br label %reuse.join.830
reuse.copy.829:
  %t836 = call ptr @__alloc(i64 24, i32 2)
  %t837 = inttoptr i64 125 to ptr
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
tco.case.arm.67.842:
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
  %t854 = inttoptr i64 126 to ptr
  %t855 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t854, ptr %t855
  call void @__inc_ref(ptr %t844)
  %t853 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t844, ptr %t853
  br label %reuse.join.850
reuse.copy.849:
  %t856 = call ptr @__alloc(i64 24, i32 2)
  %t857 = inttoptr i64 126 to ptr
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
tco.case.arm.68.862:
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
  %t874 = inttoptr i64 127 to ptr
  %t875 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t874, ptr %t875
  call void @__inc_ref(ptr %t864)
  %t873 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t864, ptr %t873
  br label %reuse.join.870
reuse.copy.869:
  %t876 = call ptr @__alloc(i64 24, i32 2)
  %t877 = inttoptr i64 127 to ptr
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
tco.case.arm.69.882:
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
  %t894 = inttoptr i64 128 to ptr
  %t895 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t894, ptr %t895
  call void @__inc_ref(ptr %t884)
  %t893 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t884, ptr %t893
  br label %reuse.join.890
reuse.copy.889:
  %t896 = call ptr @__alloc(i64 24, i32 2)
  %t897 = inttoptr i64 128 to ptr
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
tco.case.arm.70.902:
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
  %t914 = inttoptr i64 129 to ptr
  %t915 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t914, ptr %t915
  call void @__inc_ref(ptr %t904)
  %t913 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t904, ptr %t913
  br label %reuse.join.910
reuse.copy.909:
  %t916 = call ptr @__alloc(i64 24, i32 2)
  %t917 = inttoptr i64 129 to ptr
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
tco.case.arm.71.922:
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
  %t934 = inttoptr i64 130 to ptr
  %t935 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t934, ptr %t935
  call void @__inc_ref(ptr %t924)
  %t933 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t924, ptr %t933
  br label %reuse.join.930
reuse.copy.929:
  %t936 = call ptr @__alloc(i64 24, i32 2)
  %t937 = inttoptr i64 130 to ptr
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
tco.case.arm.72.942:
  %t943 = getelementptr ptr, ptr %t13, i32 1
  %t944 = load ptr, ptr %t943
  call void @__inc_ref(ptr %t944)
  %t945 = getelementptr i8, ptr %t5, i64 -8
  %t946 = load i32, ptr %t945
  %t947 = icmp eq i32 %t946, 1
  br i1 %t947, label %reuse.in_place.948, label %reuse.copy.949
reuse.in_place.948:
  %t951 = getelementptr ptr, ptr %t5, i32 1
  %t952 = load ptr, ptr %t951
  call void @__free_recursive(ptr %t952)
  %t954 = inttoptr i64 131 to ptr
  %t955 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t954, ptr %t955
  call void @__inc_ref(ptr %t944)
  %t953 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t944, ptr %t953
  br label %reuse.join.950
reuse.copy.949:
  %t956 = call ptr @__alloc(i64 24, i32 2)
  %t957 = inttoptr i64 131 to ptr
  %t958 = getelementptr ptr, ptr %t956, i32 0
  store ptr %t957, ptr %t958
  call void @__inc_ref(ptr %t944)
  %t959 = getelementptr ptr, ptr %t956, i32 1
  store ptr %t944, ptr %t959
  call void @__inc_ref(ptr %t15)
  %t960 = getelementptr ptr, ptr %t956, i32 2
  store ptr %t15, ptr %t960
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.950
reuse.join.950:
  %t961 = phi ptr [ %t5, %reuse.in_place.948 ], [ %t956, %reuse.copy.949 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t944)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t961, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.73.962:
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
  %t974 = inttoptr i64 132 to ptr
  %t975 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t974, ptr %t975
  call void @__inc_ref(ptr %t964)
  %t973 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t964, ptr %t973
  br label %reuse.join.970
reuse.copy.969:
  %t976 = call ptr @__alloc(i64 24, i32 2)
  %t977 = inttoptr i64 132 to ptr
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
tco.case.arm.74.982:
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
  %t994 = inttoptr i64 133 to ptr
  %t995 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t994, ptr %t995
  call void @__inc_ref(ptr %t984)
  %t993 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t984, ptr %t993
  br label %reuse.join.990
reuse.copy.989:
  %t996 = call ptr @__alloc(i64 24, i32 2)
  %t997 = inttoptr i64 133 to ptr
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
tco.case.arm.75.1002:
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
  %t1014 = inttoptr i64 134 to ptr
  %t1015 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1014, ptr %t1015
  call void @__inc_ref(ptr %t1004)
  %t1013 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1004, ptr %t1013
  br label %reuse.join.1010
reuse.copy.1009:
  %t1016 = call ptr @__alloc(i64 24, i32 2)
  %t1017 = inttoptr i64 134 to ptr
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
tco.case.arm.76.1022:
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
  %t1034 = inttoptr i64 135 to ptr
  %t1035 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1034, ptr %t1035
  call void @__inc_ref(ptr %t1024)
  %t1033 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1024, ptr %t1033
  br label %reuse.join.1030
reuse.copy.1029:
  %t1036 = call ptr @__alloc(i64 24, i32 2)
  %t1037 = inttoptr i64 135 to ptr
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
tco.case.arm.77.1042:
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
  %t1054 = inttoptr i64 136 to ptr
  %t1055 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1054, ptr %t1055
  call void @__inc_ref(ptr %t1044)
  %t1053 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1044, ptr %t1053
  br label %reuse.join.1050
reuse.copy.1049:
  %t1056 = call ptr @__alloc(i64 24, i32 2)
  %t1057 = inttoptr i64 136 to ptr
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
  %t1074 = inttoptr i64 139 to ptr
  %t1075 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1074, ptr %t1075
  call void @__inc_ref(ptr %t1064)
  %t1073 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1064, ptr %t1073
  br label %reuse.join.1070
reuse.copy.1069:
  %t1076 = call ptr @__alloc(i64 24, i32 2)
  %t1077 = inttoptr i64 139 to ptr
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
  %t1094 = inttoptr i64 140 to ptr
  %t1095 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1094, ptr %t1095
  call void @__inc_ref(ptr %t1084)
  %t1093 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1084, ptr %t1093
  br label %reuse.join.1090
reuse.copy.1089:
  %t1096 = call ptr @__alloc(i64 24, i32 2)
  %t1097 = inttoptr i64 140 to ptr
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
  %t1114 = inttoptr i64 141 to ptr
  %t1115 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1114, ptr %t1115
  call void @__inc_ref(ptr %t1104)
  %t1113 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t1104, ptr %t1113
  br label %reuse.join.1110
reuse.copy.1109:
  %t1116 = call ptr @__alloc(i64 24, i32 2)
  %t1117 = inttoptr i64 141 to ptr
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
tco.case.default.19:
  unreachable
tco.case.arm.84.1122:
  %t1123 = getelementptr ptr, ptr %t5, i32 1
  %t1124 = load ptr, ptr %t1123
  %t1125 = getelementptr ptr, ptr %t5, i32 2
  %t1126 = load ptr, ptr %t1125
  %t1127 = getelementptr i8, ptr %t5, i64 -8
  %t1128 = load i32, ptr %t1127
  %t1129 = icmp eq i32 %t1128, 1
  br i1 %t1129, label %reuse.in_place.1130, label %reuse.copy.1131
reuse.in_place.1130:
  %t1133 = inttoptr i64 83 to ptr
  %t1134 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1133, ptr %t1134
  br label %reuse.join.1132
reuse.copy.1131:
  %t1135 = call ptr @__alloc(i64 24, i32 2)
  %t1136 = inttoptr i64 83 to ptr
  %t1137 = getelementptr ptr, ptr %t1135, i32 0
  store ptr %t1136, ptr %t1137
  call void @__inc_ref(ptr %t1124)
  %t1138 = getelementptr ptr, ptr %t1135, i32 1
  store ptr %t1124, ptr %t1138
  call void @__inc_ref(ptr %t1126)
  %t1139 = getelementptr ptr, ptr %t1135, i32 2
  store ptr %t1126, ptr %t1139
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1132
reuse.join.1132:
  %t1140 = phi ptr [ %t5, %reuse.in_place.1130 ], [ %t1135, %reuse.copy.1131 ]
  %t1141 = call ptr @__alloc(i64 16, i32 1)
  %t1142 = inttoptr i64 201 to ptr
  %t1143 = getelementptr ptr, ptr %t1141, i32 0
  store ptr %t1142, ptr %t1143
  call void @__inc_ref(ptr %t6)
  %t1144 = getelementptr ptr, ptr %t1141, i32 1
  store ptr %t6, ptr %t1144
  call void @__free_recursive(ptr %t6)
  store ptr %t1140, ptr %t3
  store ptr %t1141, ptr %t4
  br label %tco.loop.0
tco.case.arm.85.1145:
  %t1146 = getelementptr ptr, ptr %t5, i32 1
  %t1147 = load ptr, ptr %t1146
  %t1148 = getelementptr ptr, ptr %t5, i32 2
  %t1149 = load ptr, ptr %t1148
  %t1150 = getelementptr i8, ptr %t5, i64 -8
  %t1151 = load i32, ptr %t1150
  %t1152 = icmp eq i32 %t1151, 1
  br i1 %t1152, label %reuse.in_place.1153, label %reuse.copy.1154
reuse.in_place.1153:
  %t1156 = inttoptr i64 83 to ptr
  %t1157 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1156, ptr %t1157
  br label %reuse.join.1155
reuse.copy.1154:
  %t1158 = call ptr @__alloc(i64 24, i32 2)
  %t1159 = inttoptr i64 83 to ptr
  %t1160 = getelementptr ptr, ptr %t1158, i32 0
  store ptr %t1159, ptr %t1160
  call void @__inc_ref(ptr %t1147)
  %t1161 = getelementptr ptr, ptr %t1158, i32 1
  store ptr %t1147, ptr %t1161
  call void @__inc_ref(ptr %t1149)
  %t1162 = getelementptr ptr, ptr %t1158, i32 2
  store ptr %t1149, ptr %t1162
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1155
reuse.join.1155:
  %t1163 = phi ptr [ %t5, %reuse.in_place.1153 ], [ %t1158, %reuse.copy.1154 ]
  %t1164 = call ptr @__alloc(i64 16, i32 1)
  %t1165 = inttoptr i64 202 to ptr
  %t1166 = getelementptr ptr, ptr %t1164, i32 0
  store ptr %t1165, ptr %t1166
  call void @__inc_ref(ptr %t6)
  %t1167 = getelementptr ptr, ptr %t1164, i32 1
  store ptr %t6, ptr %t1167
  call void @__free_recursive(ptr %t6)
  store ptr %t1163, ptr %t3
  store ptr %t1164, ptr %t4
  br label %tco.loop.0
tco.case.arm.86.1168:
  %t1169 = getelementptr ptr, ptr %t5, i32 1
  %t1170 = load ptr, ptr %t1169
  %t1171 = getelementptr ptr, ptr %t5, i32 2
  %t1172 = load ptr, ptr %t1171
  %t1173 = getelementptr i8, ptr %t5, i64 -8
  %t1174 = load i32, ptr %t1173
  %t1175 = icmp eq i32 %t1174, 1
  br i1 %t1175, label %reuse.in_place.1176, label %reuse.copy.1177
reuse.in_place.1176:
  %t1179 = inttoptr i64 83 to ptr
  %t1180 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1179, ptr %t1180
  br label %reuse.join.1178
reuse.copy.1177:
  %t1181 = call ptr @__alloc(i64 24, i32 2)
  %t1182 = inttoptr i64 83 to ptr
  %t1183 = getelementptr ptr, ptr %t1181, i32 0
  store ptr %t1182, ptr %t1183
  call void @__inc_ref(ptr %t1170)
  %t1184 = getelementptr ptr, ptr %t1181, i32 1
  store ptr %t1170, ptr %t1184
  call void @__inc_ref(ptr %t1172)
  %t1185 = getelementptr ptr, ptr %t1181, i32 2
  store ptr %t1172, ptr %t1185
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1178
reuse.join.1178:
  %t1186 = phi ptr [ %t5, %reuse.in_place.1176 ], [ %t1181, %reuse.copy.1177 ]
  %t1187 = call ptr @__alloc(i64 16, i32 1)
  %t1188 = inttoptr i64 203 to ptr
  %t1189 = getelementptr ptr, ptr %t1187, i32 0
  store ptr %t1188, ptr %t1189
  call void @__inc_ref(ptr %t6)
  %t1190 = getelementptr ptr, ptr %t1187, i32 1
  store ptr %t6, ptr %t1190
  call void @__free_recursive(ptr %t6)
  store ptr %t1186, ptr %t3
  store ptr %t1187, ptr %t4
  br label %tco.loop.0
tco.case.arm.87.1191:
  %t1192 = getelementptr ptr, ptr %t5, i32 1
  %t1193 = load ptr, ptr %t1192
  %t1194 = getelementptr ptr, ptr %t5, i32 2
  %t1195 = load ptr, ptr %t1194
  %t1196 = getelementptr i8, ptr %t5, i64 -8
  %t1197 = load i32, ptr %t1196
  %t1198 = icmp eq i32 %t1197, 1
  br i1 %t1198, label %reuse.in_place.1199, label %reuse.copy.1200
reuse.in_place.1199:
  %t1202 = inttoptr i64 83 to ptr
  %t1203 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1202, ptr %t1203
  br label %reuse.join.1201
reuse.copy.1200:
  %t1204 = call ptr @__alloc(i64 24, i32 2)
  %t1205 = inttoptr i64 83 to ptr
  %t1206 = getelementptr ptr, ptr %t1204, i32 0
  store ptr %t1205, ptr %t1206
  call void @__inc_ref(ptr %t1193)
  %t1207 = getelementptr ptr, ptr %t1204, i32 1
  store ptr %t1193, ptr %t1207
  call void @__inc_ref(ptr %t1195)
  %t1208 = getelementptr ptr, ptr %t1204, i32 2
  store ptr %t1195, ptr %t1208
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1201
reuse.join.1201:
  %t1209 = phi ptr [ %t5, %reuse.in_place.1199 ], [ %t1204, %reuse.copy.1200 ]
  %t1210 = call ptr @__alloc(i64 16, i32 1)
  %t1211 = inttoptr i64 204 to ptr
  %t1212 = getelementptr ptr, ptr %t1210, i32 0
  store ptr %t1211, ptr %t1212
  call void @__inc_ref(ptr %t6)
  %t1213 = getelementptr ptr, ptr %t1210, i32 1
  store ptr %t6, ptr %t1213
  call void @__free_recursive(ptr %t6)
  store ptr %t1209, ptr %t3
  store ptr %t1210, ptr %t4
  br label %tco.loop.0
tco.case.arm.88.1214:
  %t1215 = getelementptr ptr, ptr %t5, i32 1
  %t1216 = load ptr, ptr %t1215
  %t1217 = getelementptr ptr, ptr %t5, i32 2
  %t1218 = load ptr, ptr %t1217
  %t1219 = getelementptr i8, ptr %t5, i64 -8
  %t1220 = load i32, ptr %t1219
  %t1221 = icmp eq i32 %t1220, 1
  br i1 %t1221, label %reuse.in_place.1222, label %reuse.copy.1223
reuse.in_place.1222:
  %t1225 = inttoptr i64 83 to ptr
  %t1226 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1225, ptr %t1226
  br label %reuse.join.1224
reuse.copy.1223:
  %t1227 = call ptr @__alloc(i64 24, i32 2)
  %t1228 = inttoptr i64 83 to ptr
  %t1229 = getelementptr ptr, ptr %t1227, i32 0
  store ptr %t1228, ptr %t1229
  call void @__inc_ref(ptr %t1216)
  %t1230 = getelementptr ptr, ptr %t1227, i32 1
  store ptr %t1216, ptr %t1230
  call void @__inc_ref(ptr %t1218)
  %t1231 = getelementptr ptr, ptr %t1227, i32 2
  store ptr %t1218, ptr %t1231
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1224
reuse.join.1224:
  %t1232 = phi ptr [ %t5, %reuse.in_place.1222 ], [ %t1227, %reuse.copy.1223 ]
  %t1233 = call ptr @__alloc(i64 16, i32 1)
  %t1234 = inttoptr i64 205 to ptr
  %t1235 = getelementptr ptr, ptr %t1233, i32 0
  store ptr %t1234, ptr %t1235
  call void @__inc_ref(ptr %t6)
  %t1236 = getelementptr ptr, ptr %t1233, i32 1
  store ptr %t6, ptr %t1236
  call void @__free_recursive(ptr %t6)
  store ptr %t1232, ptr %t3
  store ptr %t1233, ptr %t4
  br label %tco.loop.0
tco.case.arm.89.1237:
  %t1238 = getelementptr ptr, ptr %t5, i32 1
  %t1239 = load ptr, ptr %t1238
  %t1240 = getelementptr ptr, ptr %t5, i32 2
  %t1241 = load ptr, ptr %t1240
  %t1242 = getelementptr i8, ptr %t5, i64 -8
  %t1243 = load i32, ptr %t1242
  %t1244 = icmp eq i32 %t1243, 1
  br i1 %t1244, label %reuse.in_place.1245, label %reuse.copy.1246
reuse.in_place.1245:
  %t1248 = inttoptr i64 83 to ptr
  %t1249 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1248, ptr %t1249
  br label %reuse.join.1247
reuse.copy.1246:
  %t1250 = call ptr @__alloc(i64 24, i32 2)
  %t1251 = inttoptr i64 83 to ptr
  %t1252 = getelementptr ptr, ptr %t1250, i32 0
  store ptr %t1251, ptr %t1252
  call void @__inc_ref(ptr %t1239)
  %t1253 = getelementptr ptr, ptr %t1250, i32 1
  store ptr %t1239, ptr %t1253
  call void @__inc_ref(ptr %t1241)
  %t1254 = getelementptr ptr, ptr %t1250, i32 2
  store ptr %t1241, ptr %t1254
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1247
reuse.join.1247:
  %t1255 = phi ptr [ %t5, %reuse.in_place.1245 ], [ %t1250, %reuse.copy.1246 ]
  %t1256 = call ptr @__alloc(i64 16, i32 1)
  %t1257 = inttoptr i64 206 to ptr
  %t1258 = getelementptr ptr, ptr %t1256, i32 0
  store ptr %t1257, ptr %t1258
  call void @__inc_ref(ptr %t6)
  %t1259 = getelementptr ptr, ptr %t1256, i32 1
  store ptr %t6, ptr %t1259
  call void @__free_recursive(ptr %t6)
  store ptr %t1255, ptr %t3
  store ptr %t1256, ptr %t4
  br label %tco.loop.0
tco.case.arm.90.1260:
  %t1261 = getelementptr ptr, ptr %t5, i32 1
  %t1262 = load ptr, ptr %t1261
  %t1263 = getelementptr ptr, ptr %t5, i32 2
  %t1264 = load ptr, ptr %t1263
  %t1265 = getelementptr i8, ptr %t5, i64 -8
  %t1266 = load i32, ptr %t1265
  %t1267 = icmp eq i32 %t1266, 1
  br i1 %t1267, label %reuse.in_place.1268, label %reuse.copy.1269
reuse.in_place.1268:
  %t1271 = inttoptr i64 83 to ptr
  %t1272 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1271, ptr %t1272
  br label %reuse.join.1270
reuse.copy.1269:
  %t1273 = call ptr @__alloc(i64 24, i32 2)
  %t1274 = inttoptr i64 83 to ptr
  %t1275 = getelementptr ptr, ptr %t1273, i32 0
  store ptr %t1274, ptr %t1275
  call void @__inc_ref(ptr %t1262)
  %t1276 = getelementptr ptr, ptr %t1273, i32 1
  store ptr %t1262, ptr %t1276
  call void @__inc_ref(ptr %t1264)
  %t1277 = getelementptr ptr, ptr %t1273, i32 2
  store ptr %t1264, ptr %t1277
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1270
reuse.join.1270:
  %t1278 = phi ptr [ %t5, %reuse.in_place.1268 ], [ %t1273, %reuse.copy.1269 ]
  %t1279 = call ptr @__alloc(i64 16, i32 1)
  %t1280 = inttoptr i64 207 to ptr
  %t1281 = getelementptr ptr, ptr %t1279, i32 0
  store ptr %t1280, ptr %t1281
  call void @__inc_ref(ptr %t6)
  %t1282 = getelementptr ptr, ptr %t1279, i32 1
  store ptr %t6, ptr %t1282
  call void @__free_recursive(ptr %t6)
  store ptr %t1278, ptr %t3
  store ptr %t1279, ptr %t4
  br label %tco.loop.0
tco.case.arm.91.1283:
  %t1284 = getelementptr ptr, ptr %t5, i32 1
  %t1285 = load ptr, ptr %t1284
  %t1286 = getelementptr ptr, ptr %t5, i32 2
  %t1287 = load ptr, ptr %t1286
  %t1288 = getelementptr i8, ptr %t5, i64 -8
  %t1289 = load i32, ptr %t1288
  %t1290 = icmp eq i32 %t1289, 1
  br i1 %t1290, label %reuse.in_place.1291, label %reuse.copy.1292
reuse.in_place.1291:
  %t1294 = inttoptr i64 83 to ptr
  %t1295 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1294, ptr %t1295
  br label %reuse.join.1293
reuse.copy.1292:
  %t1296 = call ptr @__alloc(i64 24, i32 2)
  %t1297 = inttoptr i64 83 to ptr
  %t1298 = getelementptr ptr, ptr %t1296, i32 0
  store ptr %t1297, ptr %t1298
  call void @__inc_ref(ptr %t1285)
  %t1299 = getelementptr ptr, ptr %t1296, i32 1
  store ptr %t1285, ptr %t1299
  call void @__inc_ref(ptr %t1287)
  %t1300 = getelementptr ptr, ptr %t1296, i32 2
  store ptr %t1287, ptr %t1300
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1293
reuse.join.1293:
  %t1301 = phi ptr [ %t5, %reuse.in_place.1291 ], [ %t1296, %reuse.copy.1292 ]
  %t1302 = call ptr @__alloc(i64 16, i32 1)
  %t1303 = inttoptr i64 208 to ptr
  %t1304 = getelementptr ptr, ptr %t1302, i32 0
  store ptr %t1303, ptr %t1304
  call void @__inc_ref(ptr %t6)
  %t1305 = getelementptr ptr, ptr %t1302, i32 1
  store ptr %t6, ptr %t1305
  call void @__free_recursive(ptr %t6)
  store ptr %t1301, ptr %t3
  store ptr %t1302, ptr %t4
  br label %tco.loop.0
tco.case.arm.92.1306:
  %t1307 = getelementptr ptr, ptr %t5, i32 1
  %t1308 = load ptr, ptr %t1307
  %t1309 = getelementptr ptr, ptr %t5, i32 2
  %t1310 = load ptr, ptr %t1309
  %t1311 = getelementptr i8, ptr %t5, i64 -8
  %t1312 = load i32, ptr %t1311
  %t1313 = icmp eq i32 %t1312, 1
  br i1 %t1313, label %reuse.in_place.1314, label %reuse.copy.1315
reuse.in_place.1314:
  %t1317 = inttoptr i64 83 to ptr
  %t1318 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1317, ptr %t1318
  br label %reuse.join.1316
reuse.copy.1315:
  %t1319 = call ptr @__alloc(i64 24, i32 2)
  %t1320 = inttoptr i64 83 to ptr
  %t1321 = getelementptr ptr, ptr %t1319, i32 0
  store ptr %t1320, ptr %t1321
  call void @__inc_ref(ptr %t1308)
  %t1322 = getelementptr ptr, ptr %t1319, i32 1
  store ptr %t1308, ptr %t1322
  call void @__inc_ref(ptr %t1310)
  %t1323 = getelementptr ptr, ptr %t1319, i32 2
  store ptr %t1310, ptr %t1323
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1316
reuse.join.1316:
  %t1324 = phi ptr [ %t5, %reuse.in_place.1314 ], [ %t1319, %reuse.copy.1315 ]
  %t1325 = call ptr @__alloc(i64 16, i32 1)
  %t1326 = inttoptr i64 209 to ptr
  %t1327 = getelementptr ptr, ptr %t1325, i32 0
  store ptr %t1326, ptr %t1327
  call void @__inc_ref(ptr %t6)
  %t1328 = getelementptr ptr, ptr %t1325, i32 1
  store ptr %t6, ptr %t1328
  call void @__free_recursive(ptr %t6)
  store ptr %t1324, ptr %t3
  store ptr %t1325, ptr %t4
  br label %tco.loop.0
tco.case.arm.93.1329:
  %t1330 = getelementptr ptr, ptr %t5, i32 1
  %t1331 = load ptr, ptr %t1330
  %t1332 = getelementptr ptr, ptr %t5, i32 2
  %t1333 = load ptr, ptr %t1332
  %t1334 = getelementptr i8, ptr %t5, i64 -8
  %t1335 = load i32, ptr %t1334
  %t1336 = icmp eq i32 %t1335, 1
  br i1 %t1336, label %reuse.in_place.1337, label %reuse.copy.1338
reuse.in_place.1337:
  %t1340 = inttoptr i64 83 to ptr
  %t1341 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1340, ptr %t1341
  br label %reuse.join.1339
reuse.copy.1338:
  %t1342 = call ptr @__alloc(i64 24, i32 2)
  %t1343 = inttoptr i64 83 to ptr
  %t1344 = getelementptr ptr, ptr %t1342, i32 0
  store ptr %t1343, ptr %t1344
  call void @__inc_ref(ptr %t1331)
  %t1345 = getelementptr ptr, ptr %t1342, i32 1
  store ptr %t1331, ptr %t1345
  call void @__inc_ref(ptr %t1333)
  %t1346 = getelementptr ptr, ptr %t1342, i32 2
  store ptr %t1333, ptr %t1346
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1339
reuse.join.1339:
  %t1347 = phi ptr [ %t5, %reuse.in_place.1337 ], [ %t1342, %reuse.copy.1338 ]
  %t1348 = call ptr @__alloc(i64 16, i32 1)
  %t1349 = inttoptr i64 210 to ptr
  %t1350 = getelementptr ptr, ptr %t1348, i32 0
  store ptr %t1349, ptr %t1350
  call void @__inc_ref(ptr %t6)
  %t1351 = getelementptr ptr, ptr %t1348, i32 1
  store ptr %t6, ptr %t1351
  call void @__free_recursive(ptr %t6)
  store ptr %t1347, ptr %t3
  store ptr %t1348, ptr %t4
  br label %tco.loop.0
tco.case.arm.94.1352:
  %t1353 = getelementptr ptr, ptr %t5, i32 1
  %t1354 = load ptr, ptr %t1353
  %t1355 = getelementptr ptr, ptr %t5, i32 2
  %t1356 = load ptr, ptr %t1355
  %t1357 = getelementptr i8, ptr %t5, i64 -8
  %t1358 = load i32, ptr %t1357
  %t1359 = icmp eq i32 %t1358, 1
  br i1 %t1359, label %reuse.in_place.1360, label %reuse.copy.1361
reuse.in_place.1360:
  %t1363 = inttoptr i64 83 to ptr
  %t1364 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1363, ptr %t1364
  br label %reuse.join.1362
reuse.copy.1361:
  %t1365 = call ptr @__alloc(i64 24, i32 2)
  %t1366 = inttoptr i64 83 to ptr
  %t1367 = getelementptr ptr, ptr %t1365, i32 0
  store ptr %t1366, ptr %t1367
  call void @__inc_ref(ptr %t1354)
  %t1368 = getelementptr ptr, ptr %t1365, i32 1
  store ptr %t1354, ptr %t1368
  call void @__inc_ref(ptr %t1356)
  %t1369 = getelementptr ptr, ptr %t1365, i32 2
  store ptr %t1356, ptr %t1369
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1362
reuse.join.1362:
  %t1370 = phi ptr [ %t5, %reuse.in_place.1360 ], [ %t1365, %reuse.copy.1361 ]
  %t1371 = call ptr @__alloc(i64 16, i32 1)
  %t1372 = inttoptr i64 211 to ptr
  %t1373 = getelementptr ptr, ptr %t1371, i32 0
  store ptr %t1372, ptr %t1373
  call void @__inc_ref(ptr %t6)
  %t1374 = getelementptr ptr, ptr %t1371, i32 1
  store ptr %t6, ptr %t1374
  call void @__free_recursive(ptr %t6)
  store ptr %t1370, ptr %t3
  store ptr %t1371, ptr %t4
  br label %tco.loop.0
tco.case.arm.95.1375:
  %t1376 = getelementptr ptr, ptr %t5, i32 1
  %t1377 = load ptr, ptr %t1376
  %t1378 = getelementptr ptr, ptr %t5, i32 2
  %t1379 = load ptr, ptr %t1378
  %t1380 = getelementptr i8, ptr %t5, i64 -8
  %t1381 = load i32, ptr %t1380
  %t1382 = icmp eq i32 %t1381, 1
  br i1 %t1382, label %reuse.in_place.1383, label %reuse.copy.1384
reuse.in_place.1383:
  %t1386 = inttoptr i64 83 to ptr
  %t1387 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1386, ptr %t1387
  br label %reuse.join.1385
reuse.copy.1384:
  %t1388 = call ptr @__alloc(i64 24, i32 2)
  %t1389 = inttoptr i64 83 to ptr
  %t1390 = getelementptr ptr, ptr %t1388, i32 0
  store ptr %t1389, ptr %t1390
  call void @__inc_ref(ptr %t1377)
  %t1391 = getelementptr ptr, ptr %t1388, i32 1
  store ptr %t1377, ptr %t1391
  call void @__inc_ref(ptr %t1379)
  %t1392 = getelementptr ptr, ptr %t1388, i32 2
  store ptr %t1379, ptr %t1392
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1385
reuse.join.1385:
  %t1393 = phi ptr [ %t5, %reuse.in_place.1383 ], [ %t1388, %reuse.copy.1384 ]
  %t1394 = call ptr @__alloc(i64 16, i32 1)
  %t1395 = inttoptr i64 212 to ptr
  %t1396 = getelementptr ptr, ptr %t1394, i32 0
  store ptr %t1395, ptr %t1396
  call void @__inc_ref(ptr %t6)
  %t1397 = getelementptr ptr, ptr %t1394, i32 1
  store ptr %t6, ptr %t1397
  call void @__free_recursive(ptr %t6)
  store ptr %t1393, ptr %t3
  store ptr %t1394, ptr %t4
  br label %tco.loop.0
tco.case.arm.96.1398:
  %t1399 = getelementptr ptr, ptr %t5, i32 1
  %t1400 = load ptr, ptr %t1399
  %t1401 = getelementptr ptr, ptr %t5, i32 2
  %t1402 = load ptr, ptr %t1401
  %t1403 = getelementptr i8, ptr %t5, i64 -8
  %t1404 = load i32, ptr %t1403
  %t1405 = icmp eq i32 %t1404, 1
  br i1 %t1405, label %reuse.in_place.1406, label %reuse.copy.1407
reuse.in_place.1406:
  %t1409 = inttoptr i64 83 to ptr
  %t1410 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1409, ptr %t1410
  br label %reuse.join.1408
reuse.copy.1407:
  %t1411 = call ptr @__alloc(i64 24, i32 2)
  %t1412 = inttoptr i64 83 to ptr
  %t1413 = getelementptr ptr, ptr %t1411, i32 0
  store ptr %t1412, ptr %t1413
  call void @__inc_ref(ptr %t1400)
  %t1414 = getelementptr ptr, ptr %t1411, i32 1
  store ptr %t1400, ptr %t1414
  call void @__inc_ref(ptr %t1402)
  %t1415 = getelementptr ptr, ptr %t1411, i32 2
  store ptr %t1402, ptr %t1415
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1408
reuse.join.1408:
  %t1416 = phi ptr [ %t5, %reuse.in_place.1406 ], [ %t1411, %reuse.copy.1407 ]
  %t1417 = call ptr @__alloc(i64 16, i32 1)
  %t1418 = inttoptr i64 213 to ptr
  %t1419 = getelementptr ptr, ptr %t1417, i32 0
  store ptr %t1418, ptr %t1419
  call void @__inc_ref(ptr %t6)
  %t1420 = getelementptr ptr, ptr %t1417, i32 1
  store ptr %t6, ptr %t1420
  call void @__free_recursive(ptr %t6)
  store ptr %t1416, ptr %t3
  store ptr %t1417, ptr %t4
  br label %tco.loop.0
tco.case.arm.97.1421:
  %t1422 = getelementptr ptr, ptr %t5, i32 1
  %t1423 = load ptr, ptr %t1422
  %t1424 = getelementptr ptr, ptr %t5, i32 2
  %t1425 = load ptr, ptr %t1424
  %t1426 = getelementptr i8, ptr %t5, i64 -8
  %t1427 = load i32, ptr %t1426
  %t1428 = icmp eq i32 %t1427, 1
  br i1 %t1428, label %reuse.in_place.1429, label %reuse.copy.1430
reuse.in_place.1429:
  %t1432 = inttoptr i64 83 to ptr
  %t1433 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1432, ptr %t1433
  br label %reuse.join.1431
reuse.copy.1430:
  %t1434 = call ptr @__alloc(i64 24, i32 2)
  %t1435 = inttoptr i64 83 to ptr
  %t1436 = getelementptr ptr, ptr %t1434, i32 0
  store ptr %t1435, ptr %t1436
  call void @__inc_ref(ptr %t1423)
  %t1437 = getelementptr ptr, ptr %t1434, i32 1
  store ptr %t1423, ptr %t1437
  call void @__inc_ref(ptr %t1425)
  %t1438 = getelementptr ptr, ptr %t1434, i32 2
  store ptr %t1425, ptr %t1438
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1431
reuse.join.1431:
  %t1439 = phi ptr [ %t5, %reuse.in_place.1429 ], [ %t1434, %reuse.copy.1430 ]
  %t1440 = call ptr @__alloc(i64 16, i32 1)
  %t1441 = inttoptr i64 214 to ptr
  %t1442 = getelementptr ptr, ptr %t1440, i32 0
  store ptr %t1441, ptr %t1442
  call void @__inc_ref(ptr %t6)
  %t1443 = getelementptr ptr, ptr %t1440, i32 1
  store ptr %t6, ptr %t1443
  call void @__free_recursive(ptr %t6)
  store ptr %t1439, ptr %t3
  store ptr %t1440, ptr %t4
  br label %tco.loop.0
tco.case.arm.98.1444:
  %t1445 = getelementptr ptr, ptr %t5, i32 1
  %t1446 = load ptr, ptr %t1445
  %t1447 = getelementptr ptr, ptr %t5, i32 2
  %t1448 = load ptr, ptr %t1447
  %t1449 = getelementptr i8, ptr %t5, i64 -8
  %t1450 = load i32, ptr %t1449
  %t1451 = icmp eq i32 %t1450, 1
  br i1 %t1451, label %reuse.in_place.1452, label %reuse.copy.1453
reuse.in_place.1452:
  %t1455 = inttoptr i64 83 to ptr
  %t1456 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1455, ptr %t1456
  br label %reuse.join.1454
reuse.copy.1453:
  %t1457 = call ptr @__alloc(i64 24, i32 2)
  %t1458 = inttoptr i64 83 to ptr
  %t1459 = getelementptr ptr, ptr %t1457, i32 0
  store ptr %t1458, ptr %t1459
  call void @__inc_ref(ptr %t1446)
  %t1460 = getelementptr ptr, ptr %t1457, i32 1
  store ptr %t1446, ptr %t1460
  call void @__inc_ref(ptr %t1448)
  %t1461 = getelementptr ptr, ptr %t1457, i32 2
  store ptr %t1448, ptr %t1461
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1454
reuse.join.1454:
  %t1462 = phi ptr [ %t5, %reuse.in_place.1452 ], [ %t1457, %reuse.copy.1453 ]
  %t1463 = call ptr @__alloc(i64 16, i32 1)
  %t1464 = inttoptr i64 215 to ptr
  %t1465 = getelementptr ptr, ptr %t1463, i32 0
  store ptr %t1464, ptr %t1465
  call void @__inc_ref(ptr %t6)
  %t1466 = getelementptr ptr, ptr %t1463, i32 1
  store ptr %t6, ptr %t1466
  call void @__free_recursive(ptr %t6)
  store ptr %t1462, ptr %t3
  store ptr %t1463, ptr %t4
  br label %tco.loop.0
tco.case.arm.99.1467:
  %t1468 = getelementptr ptr, ptr %t5, i32 1
  %t1469 = load ptr, ptr %t1468
  %t1470 = getelementptr ptr, ptr %t5, i32 2
  %t1471 = load ptr, ptr %t1470
  %t1472 = getelementptr i8, ptr %t5, i64 -8
  %t1473 = load i32, ptr %t1472
  %t1474 = icmp eq i32 %t1473, 1
  br i1 %t1474, label %reuse.in_place.1475, label %reuse.copy.1476
reuse.in_place.1475:
  %t1478 = inttoptr i64 83 to ptr
  %t1479 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1478, ptr %t1479
  br label %reuse.join.1477
reuse.copy.1476:
  %t1480 = call ptr @__alloc(i64 24, i32 2)
  %t1481 = inttoptr i64 83 to ptr
  %t1482 = getelementptr ptr, ptr %t1480, i32 0
  store ptr %t1481, ptr %t1482
  call void @__inc_ref(ptr %t1469)
  %t1483 = getelementptr ptr, ptr %t1480, i32 1
  store ptr %t1469, ptr %t1483
  call void @__inc_ref(ptr %t1471)
  %t1484 = getelementptr ptr, ptr %t1480, i32 2
  store ptr %t1471, ptr %t1484
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1477
reuse.join.1477:
  %t1485 = phi ptr [ %t5, %reuse.in_place.1475 ], [ %t1480, %reuse.copy.1476 ]
  %t1486 = call ptr @__alloc(i64 16, i32 1)
  %t1487 = inttoptr i64 216 to ptr
  %t1488 = getelementptr ptr, ptr %t1486, i32 0
  store ptr %t1487, ptr %t1488
  call void @__inc_ref(ptr %t6)
  %t1489 = getelementptr ptr, ptr %t1486, i32 1
  store ptr %t6, ptr %t1489
  call void @__free_recursive(ptr %t6)
  store ptr %t1485, ptr %t3
  store ptr %t1486, ptr %t4
  br label %tco.loop.0
tco.case.arm.100.1490:
  %t1491 = getelementptr ptr, ptr %t5, i32 1
  %t1492 = load ptr, ptr %t1491
  %t1493 = getelementptr ptr, ptr %t5, i32 2
  %t1494 = load ptr, ptr %t1493
  %t1495 = getelementptr i8, ptr %t5, i64 -8
  %t1496 = load i32, ptr %t1495
  %t1497 = icmp eq i32 %t1496, 1
  br i1 %t1497, label %reuse.in_place.1498, label %reuse.copy.1499
reuse.in_place.1498:
  %t1501 = inttoptr i64 83 to ptr
  %t1502 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1501, ptr %t1502
  br label %reuse.join.1500
reuse.copy.1499:
  %t1503 = call ptr @__alloc(i64 24, i32 2)
  %t1504 = inttoptr i64 83 to ptr
  %t1505 = getelementptr ptr, ptr %t1503, i32 0
  store ptr %t1504, ptr %t1505
  call void @__inc_ref(ptr %t1492)
  %t1506 = getelementptr ptr, ptr %t1503, i32 1
  store ptr %t1492, ptr %t1506
  call void @__inc_ref(ptr %t1494)
  %t1507 = getelementptr ptr, ptr %t1503, i32 2
  store ptr %t1494, ptr %t1507
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1500
reuse.join.1500:
  %t1508 = phi ptr [ %t5, %reuse.in_place.1498 ], [ %t1503, %reuse.copy.1499 ]
  %t1509 = call ptr @__alloc(i64 16, i32 1)
  %t1510 = inttoptr i64 217 to ptr
  %t1511 = getelementptr ptr, ptr %t1509, i32 0
  store ptr %t1510, ptr %t1511
  call void @__inc_ref(ptr %t6)
  %t1512 = getelementptr ptr, ptr %t1509, i32 1
  store ptr %t6, ptr %t1512
  call void @__free_recursive(ptr %t6)
  store ptr %t1508, ptr %t3
  store ptr %t1509, ptr %t4
  br label %tco.loop.0
tco.case.arm.101.1513:
  %t1514 = getelementptr ptr, ptr %t5, i32 1
  %t1515 = load ptr, ptr %t1514
  %t1516 = getelementptr ptr, ptr %t5, i32 2
  %t1517 = load ptr, ptr %t1516
  %t1518 = getelementptr i8, ptr %t5, i64 -8
  %t1519 = load i32, ptr %t1518
  %t1520 = icmp eq i32 %t1519, 1
  br i1 %t1520, label %reuse.in_place.1521, label %reuse.copy.1522
reuse.in_place.1521:
  %t1524 = inttoptr i64 83 to ptr
  %t1525 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1524, ptr %t1525
  br label %reuse.join.1523
reuse.copy.1522:
  %t1526 = call ptr @__alloc(i64 24, i32 2)
  %t1527 = inttoptr i64 83 to ptr
  %t1528 = getelementptr ptr, ptr %t1526, i32 0
  store ptr %t1527, ptr %t1528
  call void @__inc_ref(ptr %t1515)
  %t1529 = getelementptr ptr, ptr %t1526, i32 1
  store ptr %t1515, ptr %t1529
  call void @__inc_ref(ptr %t1517)
  %t1530 = getelementptr ptr, ptr %t1526, i32 2
  store ptr %t1517, ptr %t1530
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1523
reuse.join.1523:
  %t1531 = phi ptr [ %t5, %reuse.in_place.1521 ], [ %t1526, %reuse.copy.1522 ]
  %t1532 = call ptr @__alloc(i64 16, i32 1)
  %t1533 = inttoptr i64 218 to ptr
  %t1534 = getelementptr ptr, ptr %t1532, i32 0
  store ptr %t1533, ptr %t1534
  call void @__inc_ref(ptr %t6)
  %t1535 = getelementptr ptr, ptr %t1532, i32 1
  store ptr %t6, ptr %t1535
  call void @__free_recursive(ptr %t6)
  store ptr %t1531, ptr %t3
  store ptr %t1532, ptr %t4
  br label %tco.loop.0
tco.case.arm.102.1536:
  %t1537 = getelementptr ptr, ptr %t5, i32 1
  %t1538 = load ptr, ptr %t1537
  %t1539 = getelementptr ptr, ptr %t5, i32 2
  %t1540 = load ptr, ptr %t1539
  %t1541 = getelementptr i8, ptr %t5, i64 -8
  %t1542 = load i32, ptr %t1541
  %t1543 = icmp eq i32 %t1542, 1
  br i1 %t1543, label %reuse.in_place.1544, label %reuse.copy.1545
reuse.in_place.1544:
  %t1547 = inttoptr i64 83 to ptr
  %t1548 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1547, ptr %t1548
  br label %reuse.join.1546
reuse.copy.1545:
  %t1549 = call ptr @__alloc(i64 24, i32 2)
  %t1550 = inttoptr i64 83 to ptr
  %t1551 = getelementptr ptr, ptr %t1549, i32 0
  store ptr %t1550, ptr %t1551
  call void @__inc_ref(ptr %t1538)
  %t1552 = getelementptr ptr, ptr %t1549, i32 1
  store ptr %t1538, ptr %t1552
  call void @__inc_ref(ptr %t1540)
  %t1553 = getelementptr ptr, ptr %t1549, i32 2
  store ptr %t1540, ptr %t1553
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1546
reuse.join.1546:
  %t1554 = phi ptr [ %t5, %reuse.in_place.1544 ], [ %t1549, %reuse.copy.1545 ]
  %t1555 = call ptr @__alloc(i64 16, i32 1)
  %t1556 = inttoptr i64 219 to ptr
  %t1557 = getelementptr ptr, ptr %t1555, i32 0
  store ptr %t1556, ptr %t1557
  call void @__inc_ref(ptr %t6)
  %t1558 = getelementptr ptr, ptr %t1555, i32 1
  store ptr %t6, ptr %t1558
  call void @__free_recursive(ptr %t6)
  store ptr %t1554, ptr %t3
  store ptr %t1555, ptr %t4
  br label %tco.loop.0
tco.case.arm.103.1559:
  %t1560 = getelementptr ptr, ptr %t5, i32 1
  %t1561 = load ptr, ptr %t1560
  %t1562 = getelementptr ptr, ptr %t5, i32 2
  %t1563 = load ptr, ptr %t1562
  %t1564 = getelementptr i8, ptr %t5, i64 -8
  %t1565 = load i32, ptr %t1564
  %t1566 = icmp eq i32 %t1565, 1
  br i1 %t1566, label %reuse.in_place.1567, label %reuse.copy.1568
reuse.in_place.1567:
  %t1570 = inttoptr i64 83 to ptr
  %t1571 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1570, ptr %t1571
  br label %reuse.join.1569
reuse.copy.1568:
  %t1572 = call ptr @__alloc(i64 24, i32 2)
  %t1573 = inttoptr i64 83 to ptr
  %t1574 = getelementptr ptr, ptr %t1572, i32 0
  store ptr %t1573, ptr %t1574
  call void @__inc_ref(ptr %t1561)
  %t1575 = getelementptr ptr, ptr %t1572, i32 1
  store ptr %t1561, ptr %t1575
  call void @__inc_ref(ptr %t1563)
  %t1576 = getelementptr ptr, ptr %t1572, i32 2
  store ptr %t1563, ptr %t1576
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1569
reuse.join.1569:
  %t1577 = phi ptr [ %t5, %reuse.in_place.1567 ], [ %t1572, %reuse.copy.1568 ]
  %t1578 = call ptr @__alloc(i64 16, i32 1)
  %t1579 = inttoptr i64 220 to ptr
  %t1580 = getelementptr ptr, ptr %t1578, i32 0
  store ptr %t1579, ptr %t1580
  call void @__inc_ref(ptr %t6)
  %t1581 = getelementptr ptr, ptr %t1578, i32 1
  store ptr %t6, ptr %t1581
  call void @__free_recursive(ptr %t6)
  store ptr %t1577, ptr %t3
  store ptr %t1578, ptr %t4
  br label %tco.loop.0
tco.case.arm.104.1582:
  %t1583 = getelementptr ptr, ptr %t5, i32 1
  %t1584 = load ptr, ptr %t1583
  %t1585 = getelementptr ptr, ptr %t5, i32 2
  %t1586 = load ptr, ptr %t1585
  %t1587 = getelementptr i8, ptr %t5, i64 -8
  %t1588 = load i32, ptr %t1587
  %t1589 = icmp eq i32 %t1588, 1
  br i1 %t1589, label %reuse.in_place.1590, label %reuse.copy.1591
reuse.in_place.1590:
  %t1593 = inttoptr i64 83 to ptr
  %t1594 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1593, ptr %t1594
  br label %reuse.join.1592
reuse.copy.1591:
  %t1595 = call ptr @__alloc(i64 24, i32 2)
  %t1596 = inttoptr i64 83 to ptr
  %t1597 = getelementptr ptr, ptr %t1595, i32 0
  store ptr %t1596, ptr %t1597
  call void @__inc_ref(ptr %t1584)
  %t1598 = getelementptr ptr, ptr %t1595, i32 1
  store ptr %t1584, ptr %t1598
  call void @__inc_ref(ptr %t1586)
  %t1599 = getelementptr ptr, ptr %t1595, i32 2
  store ptr %t1586, ptr %t1599
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1592
reuse.join.1592:
  %t1600 = phi ptr [ %t5, %reuse.in_place.1590 ], [ %t1595, %reuse.copy.1591 ]
  %t1601 = call ptr @__alloc(i64 16, i32 1)
  %t1602 = inttoptr i64 221 to ptr
  %t1603 = getelementptr ptr, ptr %t1601, i32 0
  store ptr %t1602, ptr %t1603
  call void @__inc_ref(ptr %t6)
  %t1604 = getelementptr ptr, ptr %t1601, i32 1
  store ptr %t6, ptr %t1604
  call void @__free_recursive(ptr %t6)
  store ptr %t1600, ptr %t3
  store ptr %t1601, ptr %t4
  br label %tco.loop.0
tco.case.arm.105.1605:
  %t1606 = getelementptr ptr, ptr %t5, i32 1
  %t1607 = load ptr, ptr %t1606
  %t1608 = getelementptr ptr, ptr %t5, i32 2
  %t1609 = load ptr, ptr %t1608
  %t1610 = getelementptr i8, ptr %t5, i64 -8
  %t1611 = load i32, ptr %t1610
  %t1612 = icmp eq i32 %t1611, 1
  br i1 %t1612, label %reuse.in_place.1613, label %reuse.copy.1614
reuse.in_place.1613:
  %t1616 = inttoptr i64 83 to ptr
  %t1617 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1616, ptr %t1617
  br label %reuse.join.1615
reuse.copy.1614:
  %t1618 = call ptr @__alloc(i64 24, i32 2)
  %t1619 = inttoptr i64 83 to ptr
  %t1620 = getelementptr ptr, ptr %t1618, i32 0
  store ptr %t1619, ptr %t1620
  call void @__inc_ref(ptr %t1607)
  %t1621 = getelementptr ptr, ptr %t1618, i32 1
  store ptr %t1607, ptr %t1621
  call void @__inc_ref(ptr %t1609)
  %t1622 = getelementptr ptr, ptr %t1618, i32 2
  store ptr %t1609, ptr %t1622
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1615
reuse.join.1615:
  %t1623 = phi ptr [ %t5, %reuse.in_place.1613 ], [ %t1618, %reuse.copy.1614 ]
  %t1624 = call ptr @__alloc(i64 16, i32 1)
  %t1625 = inttoptr i64 222 to ptr
  %t1626 = getelementptr ptr, ptr %t1624, i32 0
  store ptr %t1625, ptr %t1626
  call void @__inc_ref(ptr %t6)
  %t1627 = getelementptr ptr, ptr %t1624, i32 1
  store ptr %t6, ptr %t1627
  call void @__free_recursive(ptr %t6)
  store ptr %t1623, ptr %t3
  store ptr %t1624, ptr %t4
  br label %tco.loop.0
tco.case.arm.106.1628:
  %t1629 = getelementptr ptr, ptr %t5, i32 1
  %t1630 = load ptr, ptr %t1629
  %t1631 = getelementptr ptr, ptr %t5, i32 2
  %t1632 = load ptr, ptr %t1631
  %t1633 = getelementptr i8, ptr %t5, i64 -8
  %t1634 = load i32, ptr %t1633
  %t1635 = icmp eq i32 %t1634, 1
  br i1 %t1635, label %reuse.in_place.1636, label %reuse.copy.1637
reuse.in_place.1636:
  %t1639 = inttoptr i64 83 to ptr
  %t1640 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1639, ptr %t1640
  br label %reuse.join.1638
reuse.copy.1637:
  %t1641 = call ptr @__alloc(i64 24, i32 2)
  %t1642 = inttoptr i64 83 to ptr
  %t1643 = getelementptr ptr, ptr %t1641, i32 0
  store ptr %t1642, ptr %t1643
  call void @__inc_ref(ptr %t1630)
  %t1644 = getelementptr ptr, ptr %t1641, i32 1
  store ptr %t1630, ptr %t1644
  call void @__inc_ref(ptr %t1632)
  %t1645 = getelementptr ptr, ptr %t1641, i32 2
  store ptr %t1632, ptr %t1645
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1638
reuse.join.1638:
  %t1646 = phi ptr [ %t5, %reuse.in_place.1636 ], [ %t1641, %reuse.copy.1637 ]
  %t1647 = call ptr @__alloc(i64 16, i32 1)
  %t1648 = inttoptr i64 223 to ptr
  %t1649 = getelementptr ptr, ptr %t1647, i32 0
  store ptr %t1648, ptr %t1649
  call void @__inc_ref(ptr %t6)
  %t1650 = getelementptr ptr, ptr %t1647, i32 1
  store ptr %t6, ptr %t1650
  call void @__free_recursive(ptr %t6)
  store ptr %t1646, ptr %t3
  store ptr %t1647, ptr %t4
  br label %tco.loop.0
tco.case.arm.107.1651:
  %t1652 = getelementptr ptr, ptr %t5, i32 1
  %t1653 = load ptr, ptr %t1652
  call void @__inc_ref(ptr %t1653)
  %t1654 = getelementptr ptr, ptr %t5, i32 2
  %t1655 = load ptr, ptr %t1654
  call void @__inc_ref(ptr %t1655)
  %t1656 = getelementptr ptr, ptr %t5, i32 3
  %t1657 = load ptr, ptr %t1656
  call void @__inc_ref(ptr %t1657)
  %t1658 = call ptr @__alloc(i64 24, i32 2)
  %t1659 = inttoptr i64 83 to ptr
  %t1660 = getelementptr ptr, ptr %t1658, i32 0
  store ptr %t1659, ptr %t1660
  call void @__inc_ref(ptr %t1653)
  %t1661 = getelementptr ptr, ptr %t1658, i32 1
  store ptr %t1653, ptr %t1661
  call void @__inc_ref(ptr %t1655)
  %t1662 = getelementptr ptr, ptr %t1658, i32 2
  store ptr %t1655, ptr %t1662
  %t1663 = call ptr @__alloc(i64 24, i32 2)
  %t1664 = inttoptr i64 224 to ptr
  %t1665 = getelementptr ptr, ptr %t1663, i32 0
  store ptr %t1664, ptr %t1665
  call void @__inc_ref(ptr %t6)
  %t1666 = getelementptr ptr, ptr %t1663, i32 1
  store ptr %t6, ptr %t1666
  call void @__inc_ref(ptr %t1657)
  %t1667 = getelementptr ptr, ptr %t1663, i32 2
  store ptr %t1657, ptr %t1667
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t1657)
  call void @__free_recursive(ptr %t1655)
  call void @__free_recursive(ptr %t1653)
  store ptr %t1658, ptr %t3
  store ptr %t1663, ptr %t4
  br label %tco.loop.0
tco.case.arm.108.1668:
  %t1669 = getelementptr ptr, ptr %t5, i32 1
  %t1670 = load ptr, ptr %t1669
  %t1671 = getelementptr ptr, ptr %t5, i32 2
  %t1672 = load ptr, ptr %t1671
  %t1673 = getelementptr i8, ptr %t5, i64 -8
  %t1674 = load i32, ptr %t1673
  %t1675 = icmp eq i32 %t1674, 1
  br i1 %t1675, label %reuse.in_place.1676, label %reuse.copy.1677
reuse.in_place.1676:
  %t1679 = inttoptr i64 83 to ptr
  %t1680 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1679, ptr %t1680
  br label %reuse.join.1678
reuse.copy.1677:
  %t1681 = call ptr @__alloc(i64 24, i32 2)
  %t1682 = inttoptr i64 83 to ptr
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
  %t1688 = inttoptr i64 225 to ptr
  %t1689 = getelementptr ptr, ptr %t1687, i32 0
  store ptr %t1688, ptr %t1689
  call void @__inc_ref(ptr %t6)
  %t1690 = getelementptr ptr, ptr %t1687, i32 1
  store ptr %t6, ptr %t1690
  call void @__free_recursive(ptr %t6)
  store ptr %t1686, ptr %t3
  store ptr %t1687, ptr %t4
  br label %tco.loop.0
tco.case.arm.109.1691:
  %t1692 = getelementptr ptr, ptr %t5, i32 1
  %t1693 = load ptr, ptr %t1692
  %t1694 = getelementptr ptr, ptr %t5, i32 2
  %t1695 = load ptr, ptr %t1694
  %t1696 = getelementptr i8, ptr %t5, i64 -8
  %t1697 = load i32, ptr %t1696
  %t1698 = icmp eq i32 %t1697, 1
  br i1 %t1698, label %reuse.in_place.1699, label %reuse.copy.1700
reuse.in_place.1699:
  %t1702 = inttoptr i64 83 to ptr
  %t1703 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1702, ptr %t1703
  br label %reuse.join.1701
reuse.copy.1700:
  %t1704 = call ptr @__alloc(i64 24, i32 2)
  %t1705 = inttoptr i64 83 to ptr
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
  %t1711 = inttoptr i64 226 to ptr
  %t1712 = getelementptr ptr, ptr %t1710, i32 0
  store ptr %t1711, ptr %t1712
  call void @__inc_ref(ptr %t6)
  %t1713 = getelementptr ptr, ptr %t1710, i32 1
  store ptr %t6, ptr %t1713
  call void @__free_recursive(ptr %t6)
  store ptr %t1709, ptr %t3
  store ptr %t1710, ptr %t4
  br label %tco.loop.0
tco.case.arm.110.1714:
  %t1715 = getelementptr ptr, ptr %t5, i32 1
  %t1716 = load ptr, ptr %t1715
  %t1717 = getelementptr ptr, ptr %t5, i32 2
  %t1718 = load ptr, ptr %t1717
  %t1719 = getelementptr i8, ptr %t5, i64 -8
  %t1720 = load i32, ptr %t1719
  %t1721 = icmp eq i32 %t1720, 1
  br i1 %t1721, label %reuse.in_place.1722, label %reuse.copy.1723
reuse.in_place.1722:
  %t1725 = inttoptr i64 83 to ptr
  %t1726 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1725, ptr %t1726
  br label %reuse.join.1724
reuse.copy.1723:
  %t1727 = call ptr @__alloc(i64 24, i32 2)
  %t1728 = inttoptr i64 83 to ptr
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
  %t1734 = inttoptr i64 227 to ptr
  %t1735 = getelementptr ptr, ptr %t1733, i32 0
  store ptr %t1734, ptr %t1735
  call void @__inc_ref(ptr %t6)
  %t1736 = getelementptr ptr, ptr %t1733, i32 1
  store ptr %t6, ptr %t1736
  call void @__free_recursive(ptr %t6)
  store ptr %t1732, ptr %t3
  store ptr %t1733, ptr %t4
  br label %tco.loop.0
tco.case.arm.111.1737:
  %t1738 = getelementptr ptr, ptr %t5, i32 1
  %t1739 = load ptr, ptr %t1738
  %t1740 = getelementptr ptr, ptr %t5, i32 2
  %t1741 = load ptr, ptr %t1740
  %t1742 = getelementptr i8, ptr %t5, i64 -8
  %t1743 = load i32, ptr %t1742
  %t1744 = icmp eq i32 %t1743, 1
  br i1 %t1744, label %reuse.in_place.1745, label %reuse.copy.1746
reuse.in_place.1745:
  %t1748 = inttoptr i64 83 to ptr
  %t1749 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1748, ptr %t1749
  br label %reuse.join.1747
reuse.copy.1746:
  %t1750 = call ptr @__alloc(i64 24, i32 2)
  %t1751 = inttoptr i64 83 to ptr
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
  %t1757 = inttoptr i64 228 to ptr
  %t1758 = getelementptr ptr, ptr %t1756, i32 0
  store ptr %t1757, ptr %t1758
  call void @__inc_ref(ptr %t6)
  %t1759 = getelementptr ptr, ptr %t1756, i32 1
  store ptr %t6, ptr %t1759
  call void @__free_recursive(ptr %t6)
  store ptr %t1755, ptr %t3
  store ptr %t1756, ptr %t4
  br label %tco.loop.0
tco.case.arm.112.1760:
  %t1761 = getelementptr ptr, ptr %t5, i32 1
  %t1762 = load ptr, ptr %t1761
  %t1763 = getelementptr ptr, ptr %t5, i32 2
  %t1764 = load ptr, ptr %t1763
  %t1765 = getelementptr i8, ptr %t5, i64 -8
  %t1766 = load i32, ptr %t1765
  %t1767 = icmp eq i32 %t1766, 1
  br i1 %t1767, label %reuse.in_place.1768, label %reuse.copy.1769
reuse.in_place.1768:
  %t1771 = inttoptr i64 83 to ptr
  %t1772 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1771, ptr %t1772
  br label %reuse.join.1770
reuse.copy.1769:
  %t1773 = call ptr @__alloc(i64 24, i32 2)
  %t1774 = inttoptr i64 83 to ptr
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
  %t1780 = inttoptr i64 229 to ptr
  %t1781 = getelementptr ptr, ptr %t1779, i32 0
  store ptr %t1780, ptr %t1781
  call void @__inc_ref(ptr %t6)
  %t1782 = getelementptr ptr, ptr %t1779, i32 1
  store ptr %t6, ptr %t1782
  call void @__free_recursive(ptr %t6)
  store ptr %t1778, ptr %t3
  store ptr %t1779, ptr %t4
  br label %tco.loop.0
tco.case.arm.113.1783:
  %t1784 = getelementptr ptr, ptr %t5, i32 1
  %t1785 = load ptr, ptr %t1784
  %t1786 = getelementptr ptr, ptr %t5, i32 2
  %t1787 = load ptr, ptr %t1786
  %t1788 = getelementptr i8, ptr %t5, i64 -8
  %t1789 = load i32, ptr %t1788
  %t1790 = icmp eq i32 %t1789, 1
  br i1 %t1790, label %reuse.in_place.1791, label %reuse.copy.1792
reuse.in_place.1791:
  %t1794 = inttoptr i64 83 to ptr
  %t1795 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1794, ptr %t1795
  br label %reuse.join.1793
reuse.copy.1792:
  %t1796 = call ptr @__alloc(i64 24, i32 2)
  %t1797 = inttoptr i64 83 to ptr
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
  %t1803 = inttoptr i64 230 to ptr
  %t1804 = getelementptr ptr, ptr %t1802, i32 0
  store ptr %t1803, ptr %t1804
  call void @__inc_ref(ptr %t6)
  %t1805 = getelementptr ptr, ptr %t1802, i32 1
  store ptr %t6, ptr %t1805
  call void @__free_recursive(ptr %t6)
  store ptr %t1801, ptr %t3
  store ptr %t1802, ptr %t4
  br label %tco.loop.0
tco.case.arm.114.1806:
  %t1807 = getelementptr ptr, ptr %t5, i32 1
  %t1808 = load ptr, ptr %t1807
  %t1809 = getelementptr ptr, ptr %t5, i32 2
  %t1810 = load ptr, ptr %t1809
  %t1811 = getelementptr i8, ptr %t5, i64 -8
  %t1812 = load i32, ptr %t1811
  %t1813 = icmp eq i32 %t1812, 1
  br i1 %t1813, label %reuse.in_place.1814, label %reuse.copy.1815
reuse.in_place.1814:
  %t1817 = inttoptr i64 83 to ptr
  %t1818 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1817, ptr %t1818
  br label %reuse.join.1816
reuse.copy.1815:
  %t1819 = call ptr @__alloc(i64 24, i32 2)
  %t1820 = inttoptr i64 83 to ptr
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
  %t1826 = inttoptr i64 231 to ptr
  %t1827 = getelementptr ptr, ptr %t1825, i32 0
  store ptr %t1826, ptr %t1827
  call void @__inc_ref(ptr %t6)
  %t1828 = getelementptr ptr, ptr %t1825, i32 1
  store ptr %t6, ptr %t1828
  call void @__free_recursive(ptr %t6)
  store ptr %t1824, ptr %t3
  store ptr %t1825, ptr %t4
  br label %tco.loop.0
tco.case.arm.115.1829:
  %t1830 = getelementptr ptr, ptr %t5, i32 1
  %t1831 = load ptr, ptr %t1830
  %t1832 = getelementptr ptr, ptr %t5, i32 2
  %t1833 = load ptr, ptr %t1832
  %t1834 = getelementptr i8, ptr %t5, i64 -8
  %t1835 = load i32, ptr %t1834
  %t1836 = icmp eq i32 %t1835, 1
  br i1 %t1836, label %reuse.in_place.1837, label %reuse.copy.1838
reuse.in_place.1837:
  %t1840 = inttoptr i64 83 to ptr
  %t1841 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1840, ptr %t1841
  br label %reuse.join.1839
reuse.copy.1838:
  %t1842 = call ptr @__alloc(i64 24, i32 2)
  %t1843 = inttoptr i64 83 to ptr
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
  %t1849 = inttoptr i64 232 to ptr
  %t1850 = getelementptr ptr, ptr %t1848, i32 0
  store ptr %t1849, ptr %t1850
  call void @__inc_ref(ptr %t6)
  %t1851 = getelementptr ptr, ptr %t1848, i32 1
  store ptr %t6, ptr %t1851
  call void @__free_recursive(ptr %t6)
  store ptr %t1847, ptr %t3
  store ptr %t1848, ptr %t4
  br label %tco.loop.0
tco.case.arm.116.1852:
  %t1853 = getelementptr ptr, ptr %t5, i32 1
  %t1854 = load ptr, ptr %t1853
  %t1855 = getelementptr ptr, ptr %t5, i32 2
  %t1856 = load ptr, ptr %t1855
  %t1857 = getelementptr i8, ptr %t5, i64 -8
  %t1858 = load i32, ptr %t1857
  %t1859 = icmp eq i32 %t1858, 1
  br i1 %t1859, label %reuse.in_place.1860, label %reuse.copy.1861
reuse.in_place.1860:
  %t1863 = inttoptr i64 83 to ptr
  %t1864 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1863, ptr %t1864
  br label %reuse.join.1862
reuse.copy.1861:
  %t1865 = call ptr @__alloc(i64 24, i32 2)
  %t1866 = inttoptr i64 83 to ptr
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
  %t1872 = inttoptr i64 233 to ptr
  %t1873 = getelementptr ptr, ptr %t1871, i32 0
  store ptr %t1872, ptr %t1873
  call void @__inc_ref(ptr %t6)
  %t1874 = getelementptr ptr, ptr %t1871, i32 1
  store ptr %t6, ptr %t1874
  call void @__free_recursive(ptr %t6)
  store ptr %t1870, ptr %t3
  store ptr %t1871, ptr %t4
  br label %tco.loop.0
tco.case.arm.117.1875:
  %t1876 = getelementptr ptr, ptr %t5, i32 1
  %t1877 = load ptr, ptr %t1876
  %t1878 = getelementptr ptr, ptr %t5, i32 2
  %t1879 = load ptr, ptr %t1878
  %t1880 = getelementptr i8, ptr %t5, i64 -8
  %t1881 = load i32, ptr %t1880
  %t1882 = icmp eq i32 %t1881, 1
  br i1 %t1882, label %reuse.in_place.1883, label %reuse.copy.1884
reuse.in_place.1883:
  %t1886 = inttoptr i64 83 to ptr
  %t1887 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1886, ptr %t1887
  br label %reuse.join.1885
reuse.copy.1884:
  %t1888 = call ptr @__alloc(i64 24, i32 2)
  %t1889 = inttoptr i64 83 to ptr
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
  %t1895 = inttoptr i64 234 to ptr
  %t1896 = getelementptr ptr, ptr %t1894, i32 0
  store ptr %t1895, ptr %t1896
  call void @__inc_ref(ptr %t6)
  %t1897 = getelementptr ptr, ptr %t1894, i32 1
  store ptr %t6, ptr %t1897
  call void @__free_recursive(ptr %t6)
  store ptr %t1893, ptr %t3
  store ptr %t1894, ptr %t4
  br label %tco.loop.0
tco.case.arm.118.1898:
  %t1899 = getelementptr ptr, ptr %t5, i32 1
  %t1900 = load ptr, ptr %t1899
  %t1901 = getelementptr ptr, ptr %t5, i32 2
  %t1902 = load ptr, ptr %t1901
  %t1903 = getelementptr i8, ptr %t5, i64 -8
  %t1904 = load i32, ptr %t1903
  %t1905 = icmp eq i32 %t1904, 1
  br i1 %t1905, label %reuse.in_place.1906, label %reuse.copy.1907
reuse.in_place.1906:
  %t1909 = inttoptr i64 83 to ptr
  %t1910 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1909, ptr %t1910
  br label %reuse.join.1908
reuse.copy.1907:
  %t1911 = call ptr @__alloc(i64 24, i32 2)
  %t1912 = inttoptr i64 83 to ptr
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
  %t1918 = inttoptr i64 235 to ptr
  %t1919 = getelementptr ptr, ptr %t1917, i32 0
  store ptr %t1918, ptr %t1919
  call void @__inc_ref(ptr %t6)
  %t1920 = getelementptr ptr, ptr %t1917, i32 1
  store ptr %t6, ptr %t1920
  call void @__free_recursive(ptr %t6)
  store ptr %t1916, ptr %t3
  store ptr %t1917, ptr %t4
  br label %tco.loop.0
tco.case.arm.119.1921:
  %t1922 = getelementptr ptr, ptr %t5, i32 1
  %t1923 = load ptr, ptr %t1922
  %t1924 = getelementptr ptr, ptr %t5, i32 2
  %t1925 = load ptr, ptr %t1924
  %t1926 = getelementptr i8, ptr %t5, i64 -8
  %t1927 = load i32, ptr %t1926
  %t1928 = icmp eq i32 %t1927, 1
  br i1 %t1928, label %reuse.in_place.1929, label %reuse.copy.1930
reuse.in_place.1929:
  %t1932 = inttoptr i64 83 to ptr
  %t1933 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1932, ptr %t1933
  br label %reuse.join.1931
reuse.copy.1930:
  %t1934 = call ptr @__alloc(i64 24, i32 2)
  %t1935 = inttoptr i64 83 to ptr
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
  %t1941 = inttoptr i64 236 to ptr
  %t1942 = getelementptr ptr, ptr %t1940, i32 0
  store ptr %t1941, ptr %t1942
  call void @__inc_ref(ptr %t6)
  %t1943 = getelementptr ptr, ptr %t1940, i32 1
  store ptr %t6, ptr %t1943
  call void @__free_recursive(ptr %t6)
  store ptr %t1939, ptr %t3
  store ptr %t1940, ptr %t4
  br label %tco.loop.0
tco.case.arm.120.1944:
  %t1945 = getelementptr ptr, ptr %t5, i32 1
  %t1946 = load ptr, ptr %t1945
  call void @__inc_ref(ptr %t1946)
  %t1947 = getelementptr ptr, ptr %t5, i32 2
  %t1948 = load ptr, ptr %t1947
  call void @__inc_ref(ptr %t1948)
  %t1949 = getelementptr ptr, ptr %t5, i32 3
  %t1950 = load ptr, ptr %t1949
  call void @__inc_ref(ptr %t1950)
  %t1951 = call ptr @__alloc(i64 24, i32 2)
  %t1952 = inttoptr i64 83 to ptr
  %t1953 = getelementptr ptr, ptr %t1951, i32 0
  store ptr %t1952, ptr %t1953
  call void @__inc_ref(ptr %t1946)
  %t1954 = getelementptr ptr, ptr %t1951, i32 1
  store ptr %t1946, ptr %t1954
  call void @__inc_ref(ptr %t1948)
  %t1955 = getelementptr ptr, ptr %t1951, i32 2
  store ptr %t1948, ptr %t1955
  %t1956 = call ptr @__alloc(i64 24, i32 2)
  %t1957 = inttoptr i64 237 to ptr
  %t1958 = getelementptr ptr, ptr %t1956, i32 0
  store ptr %t1957, ptr %t1958
  call void @__inc_ref(ptr %t6)
  %t1959 = getelementptr ptr, ptr %t1956, i32 1
  store ptr %t6, ptr %t1959
  call void @__inc_ref(ptr %t1950)
  %t1960 = getelementptr ptr, ptr %t1956, i32 2
  store ptr %t1950, ptr %t1960
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t1950)
  call void @__free_recursive(ptr %t1948)
  call void @__free_recursive(ptr %t1946)
  store ptr %t1951, ptr %t3
  store ptr %t1956, ptr %t4
  br label %tco.loop.0
tco.case.arm.121.1961:
  %t1962 = getelementptr ptr, ptr %t5, i32 1
  %t1963 = load ptr, ptr %t1962
  %t1964 = getelementptr ptr, ptr %t5, i32 2
  %t1965 = load ptr, ptr %t1964
  %t1966 = getelementptr i8, ptr %t5, i64 -8
  %t1967 = load i32, ptr %t1966
  %t1968 = icmp eq i32 %t1967, 1
  br i1 %t1968, label %reuse.in_place.1969, label %reuse.copy.1970
reuse.in_place.1969:
  %t1972 = inttoptr i64 83 to ptr
  %t1973 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1972, ptr %t1973
  br label %reuse.join.1971
reuse.copy.1970:
  %t1974 = call ptr @__alloc(i64 24, i32 2)
  %t1975 = inttoptr i64 83 to ptr
  %t1976 = getelementptr ptr, ptr %t1974, i32 0
  store ptr %t1975, ptr %t1976
  call void @__inc_ref(ptr %t1963)
  %t1977 = getelementptr ptr, ptr %t1974, i32 1
  store ptr %t1963, ptr %t1977
  call void @__inc_ref(ptr %t1965)
  %t1978 = getelementptr ptr, ptr %t1974, i32 2
  store ptr %t1965, ptr %t1978
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1971
reuse.join.1971:
  %t1979 = phi ptr [ %t5, %reuse.in_place.1969 ], [ %t1974, %reuse.copy.1970 ]
  %t1980 = call ptr @__alloc(i64 16, i32 1)
  %t1981 = inttoptr i64 238 to ptr
  %t1982 = getelementptr ptr, ptr %t1980, i32 0
  store ptr %t1981, ptr %t1982
  call void @__inc_ref(ptr %t6)
  %t1983 = getelementptr ptr, ptr %t1980, i32 1
  store ptr %t6, ptr %t1983
  call void @__free_recursive(ptr %t6)
  store ptr %t1979, ptr %t3
  store ptr %t1980, ptr %t4
  br label %tco.loop.0
tco.case.arm.122.1984:
  %t1985 = getelementptr ptr, ptr %t5, i32 1
  %t1986 = load ptr, ptr %t1985
  %t1987 = getelementptr ptr, ptr %t5, i32 2
  %t1988 = load ptr, ptr %t1987
  %t1989 = getelementptr i8, ptr %t5, i64 -8
  %t1990 = load i32, ptr %t1989
  %t1991 = icmp eq i32 %t1990, 1
  br i1 %t1991, label %reuse.in_place.1992, label %reuse.copy.1993
reuse.in_place.1992:
  %t1995 = inttoptr i64 83 to ptr
  %t1996 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1995, ptr %t1996
  br label %reuse.join.1994
reuse.copy.1993:
  %t1997 = call ptr @__alloc(i64 24, i32 2)
  %t1998 = inttoptr i64 83 to ptr
  %t1999 = getelementptr ptr, ptr %t1997, i32 0
  store ptr %t1998, ptr %t1999
  call void @__inc_ref(ptr %t1986)
  %t2000 = getelementptr ptr, ptr %t1997, i32 1
  store ptr %t1986, ptr %t2000
  call void @__inc_ref(ptr %t1988)
  %t2001 = getelementptr ptr, ptr %t1997, i32 2
  store ptr %t1988, ptr %t2001
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1994
reuse.join.1994:
  %t2002 = phi ptr [ %t5, %reuse.in_place.1992 ], [ %t1997, %reuse.copy.1993 ]
  %t2003 = call ptr @__alloc(i64 16, i32 1)
  %t2004 = inttoptr i64 239 to ptr
  %t2005 = getelementptr ptr, ptr %t2003, i32 0
  store ptr %t2004, ptr %t2005
  call void @__inc_ref(ptr %t6)
  %t2006 = getelementptr ptr, ptr %t2003, i32 1
  store ptr %t6, ptr %t2006
  call void @__free_recursive(ptr %t6)
  store ptr %t2002, ptr %t3
  store ptr %t2003, ptr %t4
  br label %tco.loop.0
tco.case.arm.123.2007:
  %t2008 = getelementptr ptr, ptr %t5, i32 1
  %t2009 = load ptr, ptr %t2008
  %t2010 = getelementptr ptr, ptr %t5, i32 2
  %t2011 = load ptr, ptr %t2010
  %t2012 = getelementptr i8, ptr %t5, i64 -8
  %t2013 = load i32, ptr %t2012
  %t2014 = icmp eq i32 %t2013, 1
  br i1 %t2014, label %reuse.in_place.2015, label %reuse.copy.2016
reuse.in_place.2015:
  %t2018 = inttoptr i64 83 to ptr
  %t2019 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2018, ptr %t2019
  br label %reuse.join.2017
reuse.copy.2016:
  %t2020 = call ptr @__alloc(i64 24, i32 2)
  %t2021 = inttoptr i64 83 to ptr
  %t2022 = getelementptr ptr, ptr %t2020, i32 0
  store ptr %t2021, ptr %t2022
  call void @__inc_ref(ptr %t2009)
  %t2023 = getelementptr ptr, ptr %t2020, i32 1
  store ptr %t2009, ptr %t2023
  call void @__inc_ref(ptr %t2011)
  %t2024 = getelementptr ptr, ptr %t2020, i32 2
  store ptr %t2011, ptr %t2024
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2017
reuse.join.2017:
  %t2025 = phi ptr [ %t5, %reuse.in_place.2015 ], [ %t2020, %reuse.copy.2016 ]
  %t2026 = call ptr @__alloc(i64 16, i32 1)
  %t2027 = inttoptr i64 240 to ptr
  %t2028 = getelementptr ptr, ptr %t2026, i32 0
  store ptr %t2027, ptr %t2028
  call void @__inc_ref(ptr %t6)
  %t2029 = getelementptr ptr, ptr %t2026, i32 1
  store ptr %t6, ptr %t2029
  call void @__free_recursive(ptr %t6)
  store ptr %t2025, ptr %t3
  store ptr %t2026, ptr %t4
  br label %tco.loop.0
tco.case.arm.124.2030:
  %t2031 = getelementptr ptr, ptr %t5, i32 1
  %t2032 = load ptr, ptr %t2031
  %t2033 = getelementptr ptr, ptr %t5, i32 2
  %t2034 = load ptr, ptr %t2033
  %t2035 = getelementptr i8, ptr %t5, i64 -8
  %t2036 = load i32, ptr %t2035
  %t2037 = icmp eq i32 %t2036, 1
  br i1 %t2037, label %reuse.in_place.2038, label %reuse.copy.2039
reuse.in_place.2038:
  %t2041 = inttoptr i64 83 to ptr
  %t2042 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2041, ptr %t2042
  br label %reuse.join.2040
reuse.copy.2039:
  %t2043 = call ptr @__alloc(i64 24, i32 2)
  %t2044 = inttoptr i64 83 to ptr
  %t2045 = getelementptr ptr, ptr %t2043, i32 0
  store ptr %t2044, ptr %t2045
  call void @__inc_ref(ptr %t2032)
  %t2046 = getelementptr ptr, ptr %t2043, i32 1
  store ptr %t2032, ptr %t2046
  call void @__inc_ref(ptr %t2034)
  %t2047 = getelementptr ptr, ptr %t2043, i32 2
  store ptr %t2034, ptr %t2047
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2040
reuse.join.2040:
  %t2048 = phi ptr [ %t5, %reuse.in_place.2038 ], [ %t2043, %reuse.copy.2039 ]
  %t2049 = call ptr @__alloc(i64 16, i32 1)
  %t2050 = inttoptr i64 241 to ptr
  %t2051 = getelementptr ptr, ptr %t2049, i32 0
  store ptr %t2050, ptr %t2051
  call void @__inc_ref(ptr %t6)
  %t2052 = getelementptr ptr, ptr %t2049, i32 1
  store ptr %t6, ptr %t2052
  call void @__free_recursive(ptr %t6)
  store ptr %t2048, ptr %t3
  store ptr %t2049, ptr %t4
  br label %tco.loop.0
tco.case.arm.125.2053:
  %t2054 = getelementptr ptr, ptr %t5, i32 1
  %t2055 = load ptr, ptr %t2054
  %t2056 = getelementptr ptr, ptr %t5, i32 2
  %t2057 = load ptr, ptr %t2056
  %t2058 = getelementptr i8, ptr %t5, i64 -8
  %t2059 = load i32, ptr %t2058
  %t2060 = icmp eq i32 %t2059, 1
  br i1 %t2060, label %reuse.in_place.2061, label %reuse.copy.2062
reuse.in_place.2061:
  %t2064 = inttoptr i64 83 to ptr
  %t2065 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2064, ptr %t2065
  br label %reuse.join.2063
reuse.copy.2062:
  %t2066 = call ptr @__alloc(i64 24, i32 2)
  %t2067 = inttoptr i64 83 to ptr
  %t2068 = getelementptr ptr, ptr %t2066, i32 0
  store ptr %t2067, ptr %t2068
  call void @__inc_ref(ptr %t2055)
  %t2069 = getelementptr ptr, ptr %t2066, i32 1
  store ptr %t2055, ptr %t2069
  call void @__inc_ref(ptr %t2057)
  %t2070 = getelementptr ptr, ptr %t2066, i32 2
  store ptr %t2057, ptr %t2070
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2063
reuse.join.2063:
  %t2071 = phi ptr [ %t5, %reuse.in_place.2061 ], [ %t2066, %reuse.copy.2062 ]
  %t2072 = call ptr @__alloc(i64 16, i32 1)
  %t2073 = inttoptr i64 242 to ptr
  %t2074 = getelementptr ptr, ptr %t2072, i32 0
  store ptr %t2073, ptr %t2074
  call void @__inc_ref(ptr %t6)
  %t2075 = getelementptr ptr, ptr %t2072, i32 1
  store ptr %t6, ptr %t2075
  call void @__free_recursive(ptr %t6)
  store ptr %t2071, ptr %t3
  store ptr %t2072, ptr %t4
  br label %tco.loop.0
tco.case.arm.126.2076:
  %t2077 = getelementptr ptr, ptr %t5, i32 1
  %t2078 = load ptr, ptr %t2077
  %t2079 = getelementptr ptr, ptr %t5, i32 2
  %t2080 = load ptr, ptr %t2079
  %t2081 = getelementptr i8, ptr %t5, i64 -8
  %t2082 = load i32, ptr %t2081
  %t2083 = icmp eq i32 %t2082, 1
  br i1 %t2083, label %reuse.in_place.2084, label %reuse.copy.2085
reuse.in_place.2084:
  %t2087 = inttoptr i64 83 to ptr
  %t2088 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2087, ptr %t2088
  br label %reuse.join.2086
reuse.copy.2085:
  %t2089 = call ptr @__alloc(i64 24, i32 2)
  %t2090 = inttoptr i64 83 to ptr
  %t2091 = getelementptr ptr, ptr %t2089, i32 0
  store ptr %t2090, ptr %t2091
  call void @__inc_ref(ptr %t2078)
  %t2092 = getelementptr ptr, ptr %t2089, i32 1
  store ptr %t2078, ptr %t2092
  call void @__inc_ref(ptr %t2080)
  %t2093 = getelementptr ptr, ptr %t2089, i32 2
  store ptr %t2080, ptr %t2093
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2086
reuse.join.2086:
  %t2094 = phi ptr [ %t5, %reuse.in_place.2084 ], [ %t2089, %reuse.copy.2085 ]
  %t2095 = call ptr @__alloc(i64 16, i32 1)
  %t2096 = inttoptr i64 243 to ptr
  %t2097 = getelementptr ptr, ptr %t2095, i32 0
  store ptr %t2096, ptr %t2097
  call void @__inc_ref(ptr %t6)
  %t2098 = getelementptr ptr, ptr %t2095, i32 1
  store ptr %t6, ptr %t2098
  call void @__free_recursive(ptr %t6)
  store ptr %t2094, ptr %t3
  store ptr %t2095, ptr %t4
  br label %tco.loop.0
tco.case.arm.127.2099:
  %t2100 = getelementptr ptr, ptr %t5, i32 1
  %t2101 = load ptr, ptr %t2100
  %t2102 = getelementptr ptr, ptr %t5, i32 2
  %t2103 = load ptr, ptr %t2102
  %t2104 = getelementptr i8, ptr %t5, i64 -8
  %t2105 = load i32, ptr %t2104
  %t2106 = icmp eq i32 %t2105, 1
  br i1 %t2106, label %reuse.in_place.2107, label %reuse.copy.2108
reuse.in_place.2107:
  %t2110 = inttoptr i64 83 to ptr
  %t2111 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2110, ptr %t2111
  br label %reuse.join.2109
reuse.copy.2108:
  %t2112 = call ptr @__alloc(i64 24, i32 2)
  %t2113 = inttoptr i64 83 to ptr
  %t2114 = getelementptr ptr, ptr %t2112, i32 0
  store ptr %t2113, ptr %t2114
  call void @__inc_ref(ptr %t2101)
  %t2115 = getelementptr ptr, ptr %t2112, i32 1
  store ptr %t2101, ptr %t2115
  call void @__inc_ref(ptr %t2103)
  %t2116 = getelementptr ptr, ptr %t2112, i32 2
  store ptr %t2103, ptr %t2116
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2109
reuse.join.2109:
  %t2117 = phi ptr [ %t5, %reuse.in_place.2107 ], [ %t2112, %reuse.copy.2108 ]
  %t2118 = call ptr @__alloc(i64 16, i32 1)
  %t2119 = inttoptr i64 244 to ptr
  %t2120 = getelementptr ptr, ptr %t2118, i32 0
  store ptr %t2119, ptr %t2120
  call void @__inc_ref(ptr %t6)
  %t2121 = getelementptr ptr, ptr %t2118, i32 1
  store ptr %t6, ptr %t2121
  call void @__free_recursive(ptr %t6)
  store ptr %t2117, ptr %t3
  store ptr %t2118, ptr %t4
  br label %tco.loop.0
tco.case.arm.128.2122:
  %t2123 = getelementptr ptr, ptr %t5, i32 1
  %t2124 = load ptr, ptr %t2123
  %t2125 = getelementptr ptr, ptr %t5, i32 2
  %t2126 = load ptr, ptr %t2125
  %t2127 = getelementptr i8, ptr %t5, i64 -8
  %t2128 = load i32, ptr %t2127
  %t2129 = icmp eq i32 %t2128, 1
  br i1 %t2129, label %reuse.in_place.2130, label %reuse.copy.2131
reuse.in_place.2130:
  %t2133 = inttoptr i64 83 to ptr
  %t2134 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2133, ptr %t2134
  br label %reuse.join.2132
reuse.copy.2131:
  %t2135 = call ptr @__alloc(i64 24, i32 2)
  %t2136 = inttoptr i64 83 to ptr
  %t2137 = getelementptr ptr, ptr %t2135, i32 0
  store ptr %t2136, ptr %t2137
  call void @__inc_ref(ptr %t2124)
  %t2138 = getelementptr ptr, ptr %t2135, i32 1
  store ptr %t2124, ptr %t2138
  call void @__inc_ref(ptr %t2126)
  %t2139 = getelementptr ptr, ptr %t2135, i32 2
  store ptr %t2126, ptr %t2139
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2132
reuse.join.2132:
  %t2140 = phi ptr [ %t5, %reuse.in_place.2130 ], [ %t2135, %reuse.copy.2131 ]
  %t2141 = call ptr @__alloc(i64 16, i32 1)
  %t2142 = inttoptr i64 245 to ptr
  %t2143 = getelementptr ptr, ptr %t2141, i32 0
  store ptr %t2142, ptr %t2143
  call void @__inc_ref(ptr %t6)
  %t2144 = getelementptr ptr, ptr %t2141, i32 1
  store ptr %t6, ptr %t2144
  call void @__free_recursive(ptr %t6)
  store ptr %t2140, ptr %t3
  store ptr %t2141, ptr %t4
  br label %tco.loop.0
tco.case.arm.129.2145:
  %t2146 = getelementptr ptr, ptr %t5, i32 1
  %t2147 = load ptr, ptr %t2146
  %t2148 = getelementptr ptr, ptr %t5, i32 2
  %t2149 = load ptr, ptr %t2148
  %t2150 = getelementptr i8, ptr %t5, i64 -8
  %t2151 = load i32, ptr %t2150
  %t2152 = icmp eq i32 %t2151, 1
  br i1 %t2152, label %reuse.in_place.2153, label %reuse.copy.2154
reuse.in_place.2153:
  %t2156 = inttoptr i64 83 to ptr
  %t2157 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2156, ptr %t2157
  br label %reuse.join.2155
reuse.copy.2154:
  %t2158 = call ptr @__alloc(i64 24, i32 2)
  %t2159 = inttoptr i64 83 to ptr
  %t2160 = getelementptr ptr, ptr %t2158, i32 0
  store ptr %t2159, ptr %t2160
  call void @__inc_ref(ptr %t2147)
  %t2161 = getelementptr ptr, ptr %t2158, i32 1
  store ptr %t2147, ptr %t2161
  call void @__inc_ref(ptr %t2149)
  %t2162 = getelementptr ptr, ptr %t2158, i32 2
  store ptr %t2149, ptr %t2162
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2155
reuse.join.2155:
  %t2163 = phi ptr [ %t5, %reuse.in_place.2153 ], [ %t2158, %reuse.copy.2154 ]
  %t2164 = call ptr @__alloc(i64 16, i32 1)
  %t2165 = inttoptr i64 246 to ptr
  %t2166 = getelementptr ptr, ptr %t2164, i32 0
  store ptr %t2165, ptr %t2166
  call void @__inc_ref(ptr %t6)
  %t2167 = getelementptr ptr, ptr %t2164, i32 1
  store ptr %t6, ptr %t2167
  call void @__free_recursive(ptr %t6)
  store ptr %t2163, ptr %t3
  store ptr %t2164, ptr %t4
  br label %tco.loop.0
tco.case.arm.130.2168:
  %t2169 = getelementptr ptr, ptr %t5, i32 1
  %t2170 = load ptr, ptr %t2169
  %t2171 = getelementptr ptr, ptr %t5, i32 2
  %t2172 = load ptr, ptr %t2171
  %t2173 = getelementptr i8, ptr %t5, i64 -8
  %t2174 = load i32, ptr %t2173
  %t2175 = icmp eq i32 %t2174, 1
  br i1 %t2175, label %reuse.in_place.2176, label %reuse.copy.2177
reuse.in_place.2176:
  %t2179 = inttoptr i64 83 to ptr
  %t2180 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2179, ptr %t2180
  br label %reuse.join.2178
reuse.copy.2177:
  %t2181 = call ptr @__alloc(i64 24, i32 2)
  %t2182 = inttoptr i64 83 to ptr
  %t2183 = getelementptr ptr, ptr %t2181, i32 0
  store ptr %t2182, ptr %t2183
  call void @__inc_ref(ptr %t2170)
  %t2184 = getelementptr ptr, ptr %t2181, i32 1
  store ptr %t2170, ptr %t2184
  call void @__inc_ref(ptr %t2172)
  %t2185 = getelementptr ptr, ptr %t2181, i32 2
  store ptr %t2172, ptr %t2185
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2178
reuse.join.2178:
  %t2186 = phi ptr [ %t5, %reuse.in_place.2176 ], [ %t2181, %reuse.copy.2177 ]
  %t2187 = call ptr @__alloc(i64 16, i32 1)
  %t2188 = inttoptr i64 247 to ptr
  %t2189 = getelementptr ptr, ptr %t2187, i32 0
  store ptr %t2188, ptr %t2189
  call void @__inc_ref(ptr %t6)
  %t2190 = getelementptr ptr, ptr %t2187, i32 1
  store ptr %t6, ptr %t2190
  call void @__free_recursive(ptr %t6)
  store ptr %t2186, ptr %t3
  store ptr %t2187, ptr %t4
  br label %tco.loop.0
tco.case.arm.131.2191:
  %t2192 = getelementptr ptr, ptr %t5, i32 1
  %t2193 = load ptr, ptr %t2192
  %t2194 = getelementptr ptr, ptr %t5, i32 2
  %t2195 = load ptr, ptr %t2194
  %t2196 = getelementptr i8, ptr %t5, i64 -8
  %t2197 = load i32, ptr %t2196
  %t2198 = icmp eq i32 %t2197, 1
  br i1 %t2198, label %reuse.in_place.2199, label %reuse.copy.2200
reuse.in_place.2199:
  %t2202 = inttoptr i64 83 to ptr
  %t2203 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2202, ptr %t2203
  br label %reuse.join.2201
reuse.copy.2200:
  %t2204 = call ptr @__alloc(i64 24, i32 2)
  %t2205 = inttoptr i64 83 to ptr
  %t2206 = getelementptr ptr, ptr %t2204, i32 0
  store ptr %t2205, ptr %t2206
  call void @__inc_ref(ptr %t2193)
  %t2207 = getelementptr ptr, ptr %t2204, i32 1
  store ptr %t2193, ptr %t2207
  call void @__inc_ref(ptr %t2195)
  %t2208 = getelementptr ptr, ptr %t2204, i32 2
  store ptr %t2195, ptr %t2208
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2201
reuse.join.2201:
  %t2209 = phi ptr [ %t5, %reuse.in_place.2199 ], [ %t2204, %reuse.copy.2200 ]
  %t2210 = call ptr @__alloc(i64 16, i32 1)
  %t2211 = inttoptr i64 248 to ptr
  %t2212 = getelementptr ptr, ptr %t2210, i32 0
  store ptr %t2211, ptr %t2212
  call void @__inc_ref(ptr %t6)
  %t2213 = getelementptr ptr, ptr %t2210, i32 1
  store ptr %t6, ptr %t2213
  call void @__free_recursive(ptr %t6)
  store ptr %t2209, ptr %t3
  store ptr %t2210, ptr %t4
  br label %tco.loop.0
tco.case.arm.132.2214:
  %t2215 = getelementptr ptr, ptr %t5, i32 1
  %t2216 = load ptr, ptr %t2215
  %t2217 = getelementptr ptr, ptr %t5, i32 2
  %t2218 = load ptr, ptr %t2217
  %t2219 = getelementptr i8, ptr %t5, i64 -8
  %t2220 = load i32, ptr %t2219
  %t2221 = icmp eq i32 %t2220, 1
  br i1 %t2221, label %reuse.in_place.2222, label %reuse.copy.2223
reuse.in_place.2222:
  %t2225 = inttoptr i64 83 to ptr
  %t2226 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2225, ptr %t2226
  br label %reuse.join.2224
reuse.copy.2223:
  %t2227 = call ptr @__alloc(i64 24, i32 2)
  %t2228 = inttoptr i64 83 to ptr
  %t2229 = getelementptr ptr, ptr %t2227, i32 0
  store ptr %t2228, ptr %t2229
  call void @__inc_ref(ptr %t2216)
  %t2230 = getelementptr ptr, ptr %t2227, i32 1
  store ptr %t2216, ptr %t2230
  call void @__inc_ref(ptr %t2218)
  %t2231 = getelementptr ptr, ptr %t2227, i32 2
  store ptr %t2218, ptr %t2231
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2224
reuse.join.2224:
  %t2232 = phi ptr [ %t5, %reuse.in_place.2222 ], [ %t2227, %reuse.copy.2223 ]
  %t2233 = call ptr @__alloc(i64 16, i32 1)
  %t2234 = inttoptr i64 249 to ptr
  %t2235 = getelementptr ptr, ptr %t2233, i32 0
  store ptr %t2234, ptr %t2235
  call void @__inc_ref(ptr %t6)
  %t2236 = getelementptr ptr, ptr %t2233, i32 1
  store ptr %t6, ptr %t2236
  call void @__free_recursive(ptr %t6)
  store ptr %t2232, ptr %t3
  store ptr %t2233, ptr %t4
  br label %tco.loop.0
tco.case.arm.133.2237:
  %t2238 = getelementptr ptr, ptr %t5, i32 1
  %t2239 = load ptr, ptr %t2238
  %t2240 = getelementptr ptr, ptr %t5, i32 2
  %t2241 = load ptr, ptr %t2240
  %t2242 = getelementptr i8, ptr %t5, i64 -8
  %t2243 = load i32, ptr %t2242
  %t2244 = icmp eq i32 %t2243, 1
  br i1 %t2244, label %reuse.in_place.2245, label %reuse.copy.2246
reuse.in_place.2245:
  %t2248 = inttoptr i64 83 to ptr
  %t2249 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2248, ptr %t2249
  br label %reuse.join.2247
reuse.copy.2246:
  %t2250 = call ptr @__alloc(i64 24, i32 2)
  %t2251 = inttoptr i64 83 to ptr
  %t2252 = getelementptr ptr, ptr %t2250, i32 0
  store ptr %t2251, ptr %t2252
  call void @__inc_ref(ptr %t2239)
  %t2253 = getelementptr ptr, ptr %t2250, i32 1
  store ptr %t2239, ptr %t2253
  call void @__inc_ref(ptr %t2241)
  %t2254 = getelementptr ptr, ptr %t2250, i32 2
  store ptr %t2241, ptr %t2254
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2247
reuse.join.2247:
  %t2255 = phi ptr [ %t5, %reuse.in_place.2245 ], [ %t2250, %reuse.copy.2246 ]
  %t2256 = call ptr @__alloc(i64 16, i32 1)
  %t2257 = inttoptr i64 250 to ptr
  %t2258 = getelementptr ptr, ptr %t2256, i32 0
  store ptr %t2257, ptr %t2258
  call void @__inc_ref(ptr %t6)
  %t2259 = getelementptr ptr, ptr %t2256, i32 1
  store ptr %t6, ptr %t2259
  call void @__free_recursive(ptr %t6)
  store ptr %t2255, ptr %t3
  store ptr %t2256, ptr %t4
  br label %tco.loop.0
tco.case.arm.134.2260:
  %t2261 = getelementptr ptr, ptr %t5, i32 1
  %t2262 = load ptr, ptr %t2261
  %t2263 = getelementptr ptr, ptr %t5, i32 2
  %t2264 = load ptr, ptr %t2263
  %t2265 = getelementptr i8, ptr %t5, i64 -8
  %t2266 = load i32, ptr %t2265
  %t2267 = icmp eq i32 %t2266, 1
  br i1 %t2267, label %reuse.in_place.2268, label %reuse.copy.2269
reuse.in_place.2268:
  %t2271 = inttoptr i64 83 to ptr
  %t2272 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2271, ptr %t2272
  br label %reuse.join.2270
reuse.copy.2269:
  %t2273 = call ptr @__alloc(i64 24, i32 2)
  %t2274 = inttoptr i64 83 to ptr
  %t2275 = getelementptr ptr, ptr %t2273, i32 0
  store ptr %t2274, ptr %t2275
  call void @__inc_ref(ptr %t2262)
  %t2276 = getelementptr ptr, ptr %t2273, i32 1
  store ptr %t2262, ptr %t2276
  call void @__inc_ref(ptr %t2264)
  %t2277 = getelementptr ptr, ptr %t2273, i32 2
  store ptr %t2264, ptr %t2277
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2270
reuse.join.2270:
  %t2278 = phi ptr [ %t5, %reuse.in_place.2268 ], [ %t2273, %reuse.copy.2269 ]
  %t2279 = call ptr @__alloc(i64 16, i32 1)
  %t2280 = inttoptr i64 251 to ptr
  %t2281 = getelementptr ptr, ptr %t2279, i32 0
  store ptr %t2280, ptr %t2281
  call void @__inc_ref(ptr %t6)
  %t2282 = getelementptr ptr, ptr %t2279, i32 1
  store ptr %t6, ptr %t2282
  call void @__free_recursive(ptr %t6)
  store ptr %t2278, ptr %t3
  store ptr %t2279, ptr %t4
  br label %tco.loop.0
tco.case.arm.135.2283:
  %t2284 = getelementptr ptr, ptr %t5, i32 1
  %t2285 = load ptr, ptr %t2284
  %t2286 = getelementptr ptr, ptr %t5, i32 2
  %t2287 = load ptr, ptr %t2286
  %t2288 = getelementptr i8, ptr %t5, i64 -8
  %t2289 = load i32, ptr %t2288
  %t2290 = icmp eq i32 %t2289, 1
  br i1 %t2290, label %reuse.in_place.2291, label %reuse.copy.2292
reuse.in_place.2291:
  %t2294 = inttoptr i64 83 to ptr
  %t2295 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2294, ptr %t2295
  br label %reuse.join.2293
reuse.copy.2292:
  %t2296 = call ptr @__alloc(i64 24, i32 2)
  %t2297 = inttoptr i64 83 to ptr
  %t2298 = getelementptr ptr, ptr %t2296, i32 0
  store ptr %t2297, ptr %t2298
  call void @__inc_ref(ptr %t2285)
  %t2299 = getelementptr ptr, ptr %t2296, i32 1
  store ptr %t2285, ptr %t2299
  call void @__inc_ref(ptr %t2287)
  %t2300 = getelementptr ptr, ptr %t2296, i32 2
  store ptr %t2287, ptr %t2300
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2293
reuse.join.2293:
  %t2301 = phi ptr [ %t5, %reuse.in_place.2291 ], [ %t2296, %reuse.copy.2292 ]
  %t2302 = call ptr @__alloc(i64 16, i32 1)
  %t2303 = inttoptr i64 252 to ptr
  %t2304 = getelementptr ptr, ptr %t2302, i32 0
  store ptr %t2303, ptr %t2304
  call void @__inc_ref(ptr %t6)
  %t2305 = getelementptr ptr, ptr %t2302, i32 1
  store ptr %t6, ptr %t2305
  call void @__free_recursive(ptr %t6)
  store ptr %t2301, ptr %t3
  store ptr %t2302, ptr %t4
  br label %tco.loop.0
tco.case.arm.136.2306:
  %t2307 = getelementptr ptr, ptr %t5, i32 1
  %t2308 = load ptr, ptr %t2307
  %t2309 = getelementptr ptr, ptr %t5, i32 2
  %t2310 = load ptr, ptr %t2309
  %t2311 = getelementptr i8, ptr %t5, i64 -8
  %t2312 = load i32, ptr %t2311
  %t2313 = icmp eq i32 %t2312, 1
  br i1 %t2313, label %reuse.in_place.2314, label %reuse.copy.2315
reuse.in_place.2314:
  %t2317 = inttoptr i64 83 to ptr
  %t2318 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2317, ptr %t2318
  br label %reuse.join.2316
reuse.copy.2315:
  %t2319 = call ptr @__alloc(i64 24, i32 2)
  %t2320 = inttoptr i64 83 to ptr
  %t2321 = getelementptr ptr, ptr %t2319, i32 0
  store ptr %t2320, ptr %t2321
  call void @__inc_ref(ptr %t2308)
  %t2322 = getelementptr ptr, ptr %t2319, i32 1
  store ptr %t2308, ptr %t2322
  call void @__inc_ref(ptr %t2310)
  %t2323 = getelementptr ptr, ptr %t2319, i32 2
  store ptr %t2310, ptr %t2323
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2316
reuse.join.2316:
  %t2324 = phi ptr [ %t5, %reuse.in_place.2314 ], [ %t2319, %reuse.copy.2315 ]
  %t2325 = call ptr @__alloc(i64 16, i32 1)
  %t2326 = inttoptr i64 253 to ptr
  %t2327 = getelementptr ptr, ptr %t2325, i32 0
  store ptr %t2326, ptr %t2327
  call void @__inc_ref(ptr %t6)
  %t2328 = getelementptr ptr, ptr %t2325, i32 1
  store ptr %t6, ptr %t2328
  call void @__free_recursive(ptr %t6)
  store ptr %t2324, ptr %t3
  store ptr %t2325, ptr %t4
  br label %tco.loop.0
tco.case.arm.139.2329:
  %t2330 = getelementptr ptr, ptr %t5, i32 1
  %t2331 = load ptr, ptr %t2330
  %t2332 = getelementptr ptr, ptr %t5, i32 2
  %t2333 = load ptr, ptr %t2332
  %t2334 = getelementptr i8, ptr %t5, i64 -8
  %t2335 = load i32, ptr %t2334
  %t2336 = icmp eq i32 %t2335, 1
  br i1 %t2336, label %reuse.in_place.2337, label %reuse.copy.2338
reuse.in_place.2337:
  %t2340 = inttoptr i64 83 to ptr
  %t2341 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2340, ptr %t2341
  br label %reuse.join.2339
reuse.copy.2338:
  %t2342 = call ptr @__alloc(i64 24, i32 2)
  %t2343 = inttoptr i64 83 to ptr
  %t2344 = getelementptr ptr, ptr %t2342, i32 0
  store ptr %t2343, ptr %t2344
  call void @__inc_ref(ptr %t2331)
  %t2345 = getelementptr ptr, ptr %t2342, i32 1
  store ptr %t2331, ptr %t2345
  call void @__inc_ref(ptr %t2333)
  %t2346 = getelementptr ptr, ptr %t2342, i32 2
  store ptr %t2333, ptr %t2346
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.2339
reuse.join.2339:
  %t2347 = phi ptr [ %t5, %reuse.in_place.2337 ], [ %t2342, %reuse.copy.2338 ]
  %t2348 = call ptr @__alloc(i64 16, i32 1)
  %t2349 = inttoptr i64 256 to ptr
  %t2350 = getelementptr ptr, ptr %t2348, i32 0
  store ptr %t2349, ptr %t2350
  call void @__inc_ref(ptr %t6)
  %t2351 = getelementptr ptr, ptr %t2348, i32 1
  store ptr %t6, ptr %t2351
  call void @__free_recursive(ptr %t6)
  store ptr %t2347, ptr %t3
  store ptr %t2348, ptr %t4
  br label %tco.loop.0
tco.case.arm.140.2352:
  %t2353 = getelementptr ptr, ptr %t5, i32 1
  %t2354 = load ptr, ptr %t2353
  %t2355 = getelementptr ptr, ptr %t5, i32 2
  %t2356 = load ptr, ptr %t2355
  %t2357 = getelementptr i8, ptr %t5, i64 -8
  %t2358 = load i32, ptr %t2357
  %t2359 = icmp eq i32 %t2358, 1
  br i1 %t2359, label %reuse.in_place.2360, label %reuse.copy.2361
reuse.in_place.2360:
  %t2363 = inttoptr i64 83 to ptr
  %t2364 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2363, ptr %t2364
  br label %reuse.join.2362
reuse.copy.2361:
  %t2365 = call ptr @__alloc(i64 24, i32 2)
  %t2366 = inttoptr i64 83 to ptr
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
  %t2372 = inttoptr i64 257 to ptr
  %t2373 = getelementptr ptr, ptr %t2371, i32 0
  store ptr %t2372, ptr %t2373
  call void @__inc_ref(ptr %t6)
  %t2374 = getelementptr ptr, ptr %t2371, i32 1
  store ptr %t6, ptr %t2374
  call void @__free_recursive(ptr %t6)
  store ptr %t2370, ptr %t3
  store ptr %t2371, ptr %t4
  br label %tco.loop.0
tco.case.arm.141.2375:
  %t2376 = getelementptr ptr, ptr %t5, i32 1
  %t2377 = load ptr, ptr %t2376
  %t2378 = getelementptr ptr, ptr %t5, i32 2
  %t2379 = load ptr, ptr %t2378
  %t2380 = getelementptr i8, ptr %t5, i64 -8
  %t2381 = load i32, ptr %t2380
  %t2382 = icmp eq i32 %t2381, 1
  br i1 %t2382, label %reuse.in_place.2383, label %reuse.copy.2384
reuse.in_place.2383:
  %t2386 = inttoptr i64 83 to ptr
  %t2387 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t2386, ptr %t2387
  br label %reuse.join.2385
reuse.copy.2384:
  %t2388 = call ptr @__alloc(i64 24, i32 2)
  %t2389 = inttoptr i64 83 to ptr
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
  %t2395 = inttoptr i64 258 to ptr
  %t2396 = getelementptr ptr, ptr %t2394, i32 0
  store ptr %t2395, ptr %t2396
  call void @__inc_ref(ptr %t6)
  %t2397 = getelementptr ptr, ptr %t2394, i32 1
  store ptr %t6, ptr %t2397
  call void @__free_recursive(ptr %t6)
  store ptr %t2393, ptr %t3
  store ptr %t2394, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t2398 = load ptr, ptr %t2
  ret ptr %t2398
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
  %t5 = call ptr @v__scc__apply1__df__lam_10_1__df__lam_10_10__df__lam_10_13__df__lam_10_16__df__lam_10_22__df__lam_10_31__df__lam_10_34__df__lam_10_4__df__lam_10_7__df__lam_11_11__df__lam_11_14__df__lam_11_17__df__lam_11_2__df__lam_11_23__df__lam_11_32__df__lam_11_35__df__lam_11_5__df__lam_11_8__df__lam_26_37__df__lam_27_38__df__lam_4_19__df__lam_4_25__df__lam_4_40__df__lam_4_43__df__lam_4_46__df__lam_4_49__df__lam_4_52__df__lam_4_55__df__lam_4_58__df__lam_4_61__df__lam_4_64__df__lam_4_67__df__lam_4_70__df__lam_5_20__df__lam_5_26__df__lam_5_41__df__lam_5_44__df__lam_5_47__df__lam_5_50__df__lam_5_53__df__lam_5_56__df__lam_5_59__df__lam_5_62__df__lam_5_65__df__lam_5_68__df__lam_5_71__df__lam_6_28__df__lam_7_29__lift_17__lift_18__lift_2__lift_21__lift_22__lift_24__lift_25__lift_3__lift_32__lift_33(ptr %t0)
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
