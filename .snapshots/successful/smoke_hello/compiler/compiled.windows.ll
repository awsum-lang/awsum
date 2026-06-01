; External C declarations
declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare ptr @memcpy(ptr, ptr, i64)
declare i64 @write(i32, ptr, i64)
declare i64 @strlen(ptr)
declare i64 @read(i32, ptr, i64)

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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [7 x i8]} { i32 0, i32 0, i32 0, i32 7, i32 7, [7 x i8] c"Hello, " }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"!" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [24 x i8]} { i32 0, i32 0, i32 0, i32 24, i32 24, [24 x i8] c"UNPAIRED_UTF16_SURROGATE" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [6 x i8]} { i32 0, i32 0, i32 0, i32 6, i32 6, [6 x i8] c"NO_ARG" }

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
  %stl_tag = inttoptr i64 18 to ptr
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
  %result = phi ptr [%left, %too_long], [%right, %ok]
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


define internal ptr @v_nothingAsLeft(ptr %v_e, ptr %v_m) {
  %t0 = getelementptr ptr, ptr %v_m, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 10, label %case.arm.10.4 i64 11, label %case.arm.11.9 ]
case.arm.10.4:
  %t5 = call ptr @__alloc(i64 16, i32 1)
  %t6 = inttoptr i64 3 to ptr
  %t7 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t6, ptr %t7
  call void @__inc_ref(ptr %v_e)
  %t8 = getelementptr ptr, ptr %t5, i32 1
  store ptr %v_e, ptr %t8
  call void @__free_recursive(ptr %v_e)
  call void @__free_recursive(ptr %v_m)
  ret ptr %t5
case.arm.11.9:
  %t10 = getelementptr ptr, ptr %v_m, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  %t12 = call ptr @__alloc(i64 16, i32 1)
  %t13 = inttoptr i64 4 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  call void @__inc_ref(ptr %t11)
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t11, ptr %t15
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %v_e)
  call void @__free_recursive(ptr %v_m)
  ret ptr %t12
case.default.3:
  unreachable
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

define internal ptr @v_headList(ptr %v_xs) {
  %t0 = getelementptr ptr, ptr %v_xs, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 12, label %case.arm.12.4 i64 13, label %case.arm.13.8 ]
case.arm.12.4:
  %t5 = call ptr @__alloc(i64 8, i32 0)
  %t6 = inttoptr i64 10 to ptr
  %t7 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t6, ptr %t7
  call void @__free_recursive(ptr %v_xs)
  ret ptr %t5
case.arm.13.8:
  %t9 = getelementptr ptr, ptr %v_xs, i32 1
  %t10 = load ptr, ptr %t9
  call void @__inc_ref(ptr %t10)
  %t11 = getelementptr ptr, ptr %v_xs, i32 2
  %t12 = load ptr, ptr %t11
  call void @__inc_ref(ptr %t12)
  %t13 = call ptr @__alloc(i64 16, i32 1)
  %t14 = inttoptr i64 11 to ptr
  %t15 = getelementptr ptr, ptr %t13, i32 0
  store ptr %t14, ptr %t15
  call void @__inc_ref(ptr %t10)
  %t16 = getelementptr ptr, ptr %t13, i32 1
  store ptr %t10, ptr %t16
  call void @__free_recursive(ptr %t12)
  call void @__free_recursive(ptr %t10)
  call void @__free_recursive(ptr %v_xs)
  ret ptr %t13
case.default.3:
  unreachable
}

define internal ptr @v_main() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 8 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 8, i32 0)
  %t4 = inttoptr i64 31 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  %t7 = call ptr @v__df__rowspec_24_6(ptr %t0)
  %t8 = call ptr @v__lift_19(ptr %t7)
  %t9 = call ptr @v__df__rowspec_15_3(ptr %t8)
  %t10 = call ptr @v__df_handleErrorIO_0(ptr %t9)
  ret ptr %t10
}

define internal ptr @v_greet(ptr %v_args) {
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 22 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  call void @__inc_ref(ptr %v_args)
  %t3 = call ptr @v_headList(ptr %v_args)
  %t4 = call ptr @v__lift_32(ptr %t3)
  %t5 = call ptr @v_nothingAsLeft(ptr %t0, ptr %t4)
  %t6 = getelementptr ptr, ptr %t5, i32 0
  %t7 = load ptr, ptr %t6
  %t8 = ptrtoint ptr %t7 to i64
  switch i64 %t8, label %case.default.9 [ i64 3, label %case.arm.3.10 i64 4, label %case.arm.4.21 ]
case.arm.3.10:
  %t11 = getelementptr ptr, ptr %t5, i32 1
  %t12 = load ptr, ptr %t11
  call void @__inc_ref(ptr %t12)
  %t13 = call ptr @__alloc(i64 16, i32 1)
  %t14 = inttoptr i64 3 to ptr
  %t15 = getelementptr ptr, ptr %t13, i32 0
  store ptr %t14, ptr %t15
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 3864168810 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  call void @__inc_ref(ptr %t12)
  %t19 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t12, ptr %t19
  %t20 = getelementptr ptr, ptr %t13, i32 1
  store ptr %t16, ptr %t20
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t12)
  call void @__free_recursive(ptr %v_args)
  ret ptr %t13
case.arm.4.21:
  %t22 = getelementptr ptr, ptr %t5, i32 1
  %t23 = load ptr, ptr %t22
  call void @__inc_ref(ptr %t23)
  call void @__inc_ref(ptr %t23)
  %t24 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t23)
  %t25 = getelementptr ptr, ptr %t24, i32 0
  %t26 = load ptr, ptr %t25
  %t27 = ptrtoint ptr %t26 to i64
  switch i64 %t27, label %case.default.28 [ i64 3, label %case.arm.3.29 i64 4, label %case.arm.4.40 ]
case.arm.3.29:
  %t30 = getelementptr ptr, ptr %t24, i32 1
  %t31 = load ptr, ptr %t30
  call void @__inc_ref(ptr %t31)
  %t32 = call ptr @__alloc(i64 16, i32 1)
  %t33 = inttoptr i64 3 to ptr
  %t34 = getelementptr ptr, ptr %t32, i32 0
  store ptr %t33, ptr %t34
  %t35 = call ptr @__alloc(i64 16, i32 1)
  %t36 = inttoptr i64 589989748 to ptr
  %t37 = getelementptr ptr, ptr %t35, i32 0
  store ptr %t36, ptr %t37
  call void @__inc_ref(ptr %t31)
  %t38 = getelementptr ptr, ptr %t35, i32 1
  store ptr %t31, ptr %t38
  %t39 = getelementptr ptr, ptr %t32, i32 1
  store ptr %t35, ptr %t39
  call void @__free_recursive(ptr %t24)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t31)
  call void @__free_recursive(ptr %t23)
  call void @__free_recursive(ptr %v_args)
  ret ptr %t32
case.arm.4.40:
  %t41 = getelementptr ptr, ptr %t24, i32 1
  %t42 = load ptr, ptr %t41
  call void @__inc_ref(ptr %t42)
  call void @__inc_ref(ptr %t42)
  %t43 = call ptr @__concat(ptr %t42, ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  call void @__free_recursive(ptr %t24)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t42)
  call void @__free_recursive(ptr %t23)
  call void @__free_recursive(ptr %v_args)
  ret ptr %t43
case.default.28:
  unreachable
case.default.9:
  unreachable
}

define internal ptr @v_printError(ptr %v_e) {
  %t0 = getelementptr ptr, ptr %v_e, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 502975519, label %case.arm.502975519.4 i64 589989748, label %case.arm.589989748.24 i64 3864168810, label %case.arm.3864168810.44 ]
case.arm.502975519.4:
  %t5 = getelementptr ptr, ptr %v_e, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = getelementptr ptr, ptr %t6, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %case.default.10 [ i64 19, label %case.arm.19.11 ]
case.arm.19.11:
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t15
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
case.default.10:
  unreachable
case.arm.589989748.24:
  %t25 = getelementptr ptr, ptr %v_e, i32 1
  %t26 = load ptr, ptr %t25
  call void @__inc_ref(ptr %t26)
  %t27 = getelementptr ptr, ptr %t26, i32 0
  %t28 = load ptr, ptr %t27
  %t29 = ptrtoint ptr %t28 to i64
  switch i64 %t29, label %case.default.30 [ i64 18, label %case.arm.18.31 ]
case.arm.18.31:
  %t32 = call ptr @__alloc(i64 24, i32 2)
  %t33 = inttoptr i64 7 to ptr
  %t34 = getelementptr ptr, ptr %t32, i32 0
  store ptr %t33, ptr %t34
  %t35 = getelementptr ptr, ptr %t32, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t35
  %t36 = call ptr @__alloc(i64 16, i32 1)
  %t37 = inttoptr i64 5 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = call ptr @__alloc(i64 8, i32 0)
  %t40 = inttoptr i64 0 to ptr
  %t41 = getelementptr ptr, ptr %t39, i32 0
  store ptr %t40, ptr %t41
  %t42 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t39, ptr %t42
  %t43 = getelementptr ptr, ptr %t32, i32 2
  store ptr %t36, ptr %t43
  call void @__free_recursive(ptr %t26)
  call void @__free_recursive(ptr %v_e)
  ret ptr %t32
case.default.30:
  unreachable
case.arm.3864168810.44:
  %t45 = getelementptr ptr, ptr %v_e, i32 1
  %t46 = load ptr, ptr %t45
  call void @__inc_ref(ptr %t46)
  %t47 = getelementptr ptr, ptr %t46, i32 0
  %t48 = load ptr, ptr %t47
  %t49 = ptrtoint ptr %t48 to i64
  switch i64 %t49, label %case.default.50 [ i64 22, label %case.arm.22.51 ]
case.arm.22.51:
  %t52 = call ptr @__alloc(i64 24, i32 2)
  %t53 = inttoptr i64 7 to ptr
  %t54 = getelementptr ptr, ptr %t52, i32 0
  store ptr %t53, ptr %t54
  %t55 = getelementptr ptr, ptr %t52, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t55
  %t56 = call ptr @__alloc(i64 16, i32 1)
  %t57 = inttoptr i64 5 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  %t59 = call ptr @__alloc(i64 8, i32 0)
  %t60 = inttoptr i64 0 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  %t62 = getelementptr ptr, ptr %t56, i32 1
  store ptr %t59, ptr %t62
  %t63 = getelementptr ptr, ptr %t52, i32 2
  store ptr %t56, ptr %t63
  call void @__free_recursive(ptr %t46)
  call void @__free_recursive(ptr %v_e)
  ret ptr %t52
case.default.50:
  unreachable
case.default.3:
  unreachable
}

define internal ptr @v__lift_1(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 61 to ptr
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
  %t42 = inttoptr i64 62 to ptr
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
  %t45 = inttoptr i64 62 to ptr
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
  %t57 = inttoptr i64 36 to ptr
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
  %t69 = inttoptr i64 41 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 61, label %tco.case.arm.61.11 i64 62, label %tco.case.arm.62.12 ]
tco.case.arm.61.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.62.12:
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
  %t1 = inttoptr i64 63 to ptr
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
  %t42 = inttoptr i64 64 to ptr
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
  %t45 = inttoptr i64 64 to ptr
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
  %t57 = inttoptr i64 32 to ptr
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
  %t69 = inttoptr i64 33 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 63, label %tco.case.arm.63.11 i64 64, label %tco.case.arm.64.12 ]
tco.case.arm.63.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.64.12:
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
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 65 to ptr
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
  %t25 = call ptr @__alloc(i64 16, i32 1)
  %t26 = inttoptr i64 3801428867 to ptr
  %t27 = getelementptr ptr, ptr %t25, i32 0
  store ptr %t26, ptr %t27
  call void @__inc_ref(ptr %t21)
  %t28 = getelementptr ptr, ptr %t25, i32 1
  store ptr %t21, ptr %t28
  %t29 = getelementptr ptr, ptr %t22, i32 1
  store ptr %t25, ptr %t29
  %t30 = call ptr @v__apply__lift_16(ptr %t6, ptr %t22)
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
  %t46 = inttoptr i64 66 to ptr
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
  %t49 = inttoptr i64 66 to ptr
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
  %t61 = inttoptr i64 34 to ptr
  %t62 = getelementptr ptr, ptr %t60, i32 0
  store ptr %t61, ptr %t62
  call void @__inc_ref(ptr %t56)
  %t63 = getelementptr ptr, ptr %t60, i32 1
  store ptr %t56, ptr %t63
  %t64 = getelementptr ptr, ptr %t57, i32 1
  store ptr %t60, ptr %t64
  %t65 = call ptr @v__apply__lift_16(ptr %t6, ptr %t57)
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
  %t73 = inttoptr i64 35 to ptr
  %t74 = getelementptr ptr, ptr %t72, i32 0
  store ptr %t73, ptr %t74
  call void @__inc_ref(ptr %t68)
  %t75 = getelementptr ptr, ptr %t72, i32 1
  store ptr %t68, ptr %t75
  %t76 = getelementptr ptr, ptr %t69, i32 1
  store ptr %t72, ptr %t76
  %t77 = call ptr @v__apply__lift_16(ptr %t6, ptr %t69)
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
  switch i64 %t9, label %tco.case.default.10 [ i64 65, label %tco.case.arm.65.11 i64 66, label %tco.case.arm.66.12 ]
tco.case.arm.65.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.66.12:
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

define internal ptr @v__lift_19(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 67 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__lift_19(ptr %v___input, ptr %t0)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t3
}

define internal ptr @v__cps__lift_19(ptr %v___input, ptr %v__k) {
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
  %t18 = call ptr @v__apply__lift_19(ptr %t6, ptr %t14)
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
  %t26 = call ptr @v__apply__lift_19(ptr %t6, ptr %t22)
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
  %t42 = inttoptr i64 68 to ptr
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
  %t45 = inttoptr i64 68 to ptr
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
  %t57 = inttoptr i64 37 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  call void @__inc_ref(ptr %t52)
  %t59 = getelementptr ptr, ptr %t56, i32 1
  store ptr %t52, ptr %t59
  %t60 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t56, ptr %t60
  %t61 = call ptr @v__apply__lift_19(ptr %t6, ptr %t53)
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
  %t69 = inttoptr i64 38 to ptr
  %t70 = getelementptr ptr, ptr %t68, i32 0
  store ptr %t69, ptr %t70
  call void @__inc_ref(ptr %t64)
  %t71 = getelementptr ptr, ptr %t68, i32 1
  store ptr %t64, ptr %t71
  %t72 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t68, ptr %t72
  %t73 = call ptr @v__apply__lift_19(ptr %t6, ptr %t65)
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

define internal ptr @v__apply__lift_19(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 67, label %tco.case.arm.67.11 i64 68, label %tco.case.arm.68.12 ]
tco.case.arm.67.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.68.12:
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

define internal ptr @v__lift_25(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 69 to ptr
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
  %t42 = inttoptr i64 70 to ptr
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
  %t45 = inttoptr i64 70 to ptr
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
  %t57 = inttoptr i64 39 to ptr
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
  %t69 = inttoptr i64 40 to ptr
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
tco.case.default.10:
  unreachable
tco.exit.1:
  %t74 = load ptr, ptr %t2
  ret ptr %t74
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
  switch i64 %t9, label %tco.case.default.10 [ i64 69, label %tco.case.arm.69.11 i64 70, label %tco.case.arm.70.12 ]
tco.case.arm.69.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.70.12:
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

define internal ptr @v__lift_30(ptr %v___input) {
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

define internal ptr @v__lam_31(ptr %v_args) {
  call void @__inc_ref(ptr %v_args)
  %t0 = call ptr @v_greet(ptr %v_args)
  %t1 = call ptr @v__lift_30(ptr %t0)
  %t2 = call ptr @v_eitherToIO(ptr %t1)
  call void @__free_recursive(ptr %v_args)
  ret ptr %t2
}

define internal ptr @v__lift_32(ptr %v___input) {
  %t0 = getelementptr ptr, ptr %v___input, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 10, label %case.arm.10.4 i64 11, label %case.arm.11.8 ]
case.arm.10.4:
  %t5 = call ptr @__alloc(i64 8, i32 0)
  %t6 = inttoptr i64 10 to ptr
  %t7 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t6, ptr %t7
  call void @__free_recursive(ptr %v___input)
  ret ptr %t5
case.arm.11.8:
  %t9 = getelementptr ptr, ptr %v___input, i32 1
  %t10 = load ptr, ptr %t9
  call void @__inc_ref(ptr %t10)
  %t11 = call ptr @__alloc(i64 16, i32 1)
  %t12 = inttoptr i64 11 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  call void @__inc_ref(ptr %t10)
  %t14 = getelementptr ptr, ptr %t11, i32 1
  store ptr %t10, ptr %t14
  call void @__free_recursive(ptr %t10)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t11
case.default.3:
  unreachable
}

define internal ptr @v__io_getargs_cont(ptr %v_result) {
  %t0 = getelementptr ptr, ptr %v_result, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.11 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v_result, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = call ptr @__alloc(i64 16, i32 1)
  %t8 = inttoptr i64 6 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  call void @__inc_ref(ptr %t6)
  %t10 = getelementptr ptr, ptr %t7, i32 1
  store ptr %t6, ptr %t10
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_result)
  ret ptr %t7
case.arm.4.11:
  %t12 = getelementptr ptr, ptr %v_result, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @__alloc(i64 16, i32 1)
  %t15 = inttoptr i64 5 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  call void @__inc_ref(ptr %t13)
  %t17 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t13, ptr %t17
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %v_result)
  ret ptr %t14
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

define internal ptr @v__df_handleErrorIO_0(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 71 to ptr
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
  %t22 = call ptr @v_printError(ptr %t21)
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
  %t39 = inttoptr i64 72 to ptr
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
  %t42 = inttoptr i64 72 to ptr
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
  %t54 = inttoptr i64 23 to ptr
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
  %t66 = inttoptr i64 24 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 71, label %tco.case.arm.71.11 i64 72, label %tco.case.arm.72.12 ]
tco.case.arm.71.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.72.12:
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

define internal ptr @v__df__rowspec_15_3(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 73 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df__rowspec_15_3(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df__rowspec_15_3(ptr %v_io, ptr %v__k) {
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
  %t15 = call ptr @v__lift_16(ptr %t14)
  %t16 = call ptr @v__apply__df__rowspec_15_3(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df__rowspec_15_3(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 74 to ptr
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
  %t43 = inttoptr i64 74 to ptr
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
  %t55 = inttoptr i64 25 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df__rowspec_15_3(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 26 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df__rowspec_15_3(ptr %t6, ptr %t63)
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

define internal ptr @v__apply__df__rowspec_15_3(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 73, label %tco.case.arm.73.11 i64 74, label %tco.case.arm.74.12 ]
tco.case.arm.73.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.74.12:
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
  %t1 = inttoptr i64 75 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.17 i64 7, label %tco.case.arm.7.25 i64 8, label %tco.case.arm.8.48 i64 9, label %tco.case.arm.9.60 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_31(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_8(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_8(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 76 to ptr
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
  %t43 = inttoptr i64 76 to ptr
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
  %t55 = inttoptr i64 29 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df_andThenIO_8(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 30 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df_andThenIO_8(ptr %t6, ptr %t63)
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
  switch i64 %t9, label %tco.case.default.10 [ i64 75, label %tco.case.arm.75.11 i64 76, label %tco.case.arm.76.12 ]
tco.case.arm.75.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.76.12:
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

define internal ptr @v__df__rowspec_24_6(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 77 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df__rowspec_24_6(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df__rowspec_24_6(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.16 i64 7, label %tco.case.arm.7.24 i64 8, label %tco.case.arm.8.47 i64 9, label %tco.case.arm.9.59 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @v__lam_31(ptr %t13)
  %t15 = call ptr @v__apply__df__rowspec_24_6(ptr %t6, ptr %t14)
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
  %t23 = call ptr @v__apply__df__rowspec_24_6(ptr %t6, ptr %t19)
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
  %t39 = inttoptr i64 78 to ptr
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
  %t42 = inttoptr i64 78 to ptr
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
  %t58 = call ptr @v__apply__df__rowspec_24_6(ptr %t6, ptr %t50)
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
  %t66 = inttoptr i64 28 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  call void @__inc_ref(ptr %t61)
  %t68 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t61, ptr %t68
  %t69 = getelementptr ptr, ptr %t62, i32 1
  store ptr %t65, ptr %t69
  %t70 = call ptr @v__apply__df__rowspec_24_6(ptr %t6, ptr %t62)
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

define internal ptr @v__apply__df__rowspec_24_6(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 77, label %tco.case.arm.77.11 i64 78, label %tco.case.arm.78.12 ]
tco.case.arm.77.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.78.12:
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

define internal ptr @v__scc__apply1__df__lam_10_1__df__lam_11_2__df__lam_22_4__df__lam_23_5__df__lam_28_7__df__lam_29_11__df__lam_4_9__df__lam_5_10__lift_13__lift_14__lift_17__lift_18__lift_2__lift_20__lift_21__lift_26__lift_27__lift_3(ptr %v__args) {
  call void @__inc_ref(ptr %v__args)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 79 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__scc__apply1__df__lam_10_1__df__lam_11_2__df__lam_22_4__df__lam_23_5__df__lam_28_7__df__lam_29_11__df__lam_4_9__df__lam_5_10__lift_13__lift_14__lift_17__lift_18__lift_2__lift_20__lift_21__lift_26__lift_27__lift_3(ptr %v__args, ptr %t0)
  call void @__free_recursive(ptr %v__args)
  ret ptr %t3
}

define internal ptr @v__cps__scc__apply1__df__lam_10_1__df__lam_11_2__df__lam_22_4__df__lam_23_5__df__lam_28_7__df__lam_29_11__df__lam_4_9__df__lam_5_10__lift_13__lift_14__lift_17__lift_18__lift_2__lift_20__lift_21__lift_26__lift_27__lift_3(ptr %v__args, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 42, label %tco.case.arm.42.11 i64 43, label %tco.case.arm.43.383 i64 44, label %tco.case.arm.44.406 i64 45, label %tco.case.arm.45.429 i64 46, label %tco.case.arm.46.452 i64 47, label %tco.case.arm.47.475 i64 48, label %tco.case.arm.48.498 i64 49, label %tco.case.arm.49.521 i64 50, label %tco.case.arm.50.544 i64 51, label %tco.case.arm.51.567 i64 52, label %tco.case.arm.52.590 i64 53, label %tco.case.arm.53.613 i64 54, label %tco.case.arm.54.636 i64 55, label %tco.case.arm.55.659 i64 56, label %tco.case.arm.56.682 i64 57, label %tco.case.arm.57.705 i64 58, label %tco.case.arm.58.728 i64 59, label %tco.case.arm.59.751 i64 60, label %tco.case.arm.60.774 ]
tco.case.arm.42.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t5, i32 2
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  %t16 = getelementptr ptr, ptr %t13, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %tco.case.default.19 [ i64 23, label %tco.case.arm.23.20 i64 24, label %tco.case.arm.24.40 i64 25, label %tco.case.arm.25.60 i64 26, label %tco.case.arm.26.80 i64 27, label %tco.case.arm.27.100 i64 28, label %tco.case.arm.28.120 i64 29, label %tco.case.arm.29.140 i64 30, label %tco.case.arm.30.160 i64 31, label %tco.case.arm.31.180 i64 32, label %tco.case.arm.32.183 i64 33, label %tco.case.arm.33.203 i64 34, label %tco.case.arm.34.223 i64 35, label %tco.case.arm.35.243 i64 36, label %tco.case.arm.36.263 i64 37, label %tco.case.arm.37.283 i64 38, label %tco.case.arm.38.303 i64 39, label %tco.case.arm.39.323 i64 40, label %tco.case.arm.40.343 i64 41, label %tco.case.arm.41.363 ]
tco.case.arm.23.20:
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
  %t32 = inttoptr i64 43 to ptr
  %t33 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t32, ptr %t33
  call void @__inc_ref(ptr %t22)
  %t31 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t22, ptr %t31
  br label %reuse.join.28
reuse.copy.27:
  %t34 = call ptr @__alloc(i64 24, i32 2)
  %t35 = inttoptr i64 43 to ptr
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
tco.case.arm.24.40:
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
  %t52 = inttoptr i64 44 to ptr
  %t53 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t52, ptr %t53
  call void @__inc_ref(ptr %t42)
  %t51 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t42, ptr %t51
  br label %reuse.join.48
reuse.copy.47:
  %t54 = call ptr @__alloc(i64 24, i32 2)
  %t55 = inttoptr i64 44 to ptr
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
tco.case.arm.25.60:
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
  %t72 = inttoptr i64 45 to ptr
  %t73 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t72, ptr %t73
  call void @__inc_ref(ptr %t62)
  %t71 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t62, ptr %t71
  br label %reuse.join.68
reuse.copy.67:
  %t74 = call ptr @__alloc(i64 24, i32 2)
  %t75 = inttoptr i64 45 to ptr
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
tco.case.arm.26.80:
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
  %t92 = inttoptr i64 46 to ptr
  %t93 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t92, ptr %t93
  call void @__inc_ref(ptr %t82)
  %t91 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t82, ptr %t91
  br label %reuse.join.88
reuse.copy.87:
  %t94 = call ptr @__alloc(i64 24, i32 2)
  %t95 = inttoptr i64 46 to ptr
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
tco.case.arm.27.100:
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
  %t112 = inttoptr i64 47 to ptr
  %t113 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t112, ptr %t113
  call void @__inc_ref(ptr %t102)
  %t111 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t102, ptr %t111
  br label %reuse.join.108
reuse.copy.107:
  %t114 = call ptr @__alloc(i64 24, i32 2)
  %t115 = inttoptr i64 47 to ptr
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
tco.case.arm.28.120:
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
  %t132 = inttoptr i64 48 to ptr
  %t133 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t132, ptr %t133
  call void @__inc_ref(ptr %t122)
  %t131 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t122, ptr %t131
  br label %reuse.join.128
reuse.copy.127:
  %t134 = call ptr @__alloc(i64 24, i32 2)
  %t135 = inttoptr i64 48 to ptr
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
tco.case.arm.29.140:
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
  %t152 = inttoptr i64 49 to ptr
  %t153 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t152, ptr %t153
  call void @__inc_ref(ptr %t142)
  %t151 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t142, ptr %t151
  br label %reuse.join.148
reuse.copy.147:
  %t154 = call ptr @__alloc(i64 24, i32 2)
  %t155 = inttoptr i64 49 to ptr
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
tco.case.arm.30.160:
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
  %t172 = inttoptr i64 50 to ptr
  %t173 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t172, ptr %t173
  call void @__inc_ref(ptr %t162)
  %t171 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t162, ptr %t171
  br label %reuse.join.168
reuse.copy.167:
  %t174 = call ptr @__alloc(i64 24, i32 2)
  %t175 = inttoptr i64 50 to ptr
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
tco.case.arm.31.180:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t15)
  %t181 = call ptr @v__io_getargs_cont(ptr %t15)
  %t182 = call ptr @v__apply__scc__apply1__df__lam_10_1__df__lam_11_2__df__lam_22_4__df__lam_23_5__df__lam_28_7__df__lam_29_11__df__lam_4_9__df__lam_5_10__lift_13__lift_14__lift_17__lift_18__lift_2__lift_20__lift_21__lift_26__lift_27__lift_3(ptr %t6, ptr %t181)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t182, ptr %t2
  br label %tco.exit.1
tco.case.arm.32.183:
  %t184 = getelementptr ptr, ptr %t13, i32 1
  %t185 = load ptr, ptr %t184
  call void @__inc_ref(ptr %t185)
  %t186 = getelementptr i8, ptr %t5, i64 -8
  %t187 = load i32, ptr %t186
  %t188 = icmp eq i32 %t187, 1
  br i1 %t188, label %reuse.in_place.189, label %reuse.copy.190
reuse.in_place.189:
  %t192 = getelementptr ptr, ptr %t5, i32 1
  %t193 = load ptr, ptr %t192
  call void @__free_recursive(ptr %t193)
  %t195 = inttoptr i64 51 to ptr
  %t196 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t195, ptr %t196
  call void @__inc_ref(ptr %t185)
  %t194 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t185, ptr %t194
  br label %reuse.join.191
reuse.copy.190:
  %t197 = call ptr @__alloc(i64 24, i32 2)
  %t198 = inttoptr i64 51 to ptr
  %t199 = getelementptr ptr, ptr %t197, i32 0
  store ptr %t198, ptr %t199
  call void @__inc_ref(ptr %t185)
  %t200 = getelementptr ptr, ptr %t197, i32 1
  store ptr %t185, ptr %t200
  call void @__inc_ref(ptr %t15)
  %t201 = getelementptr ptr, ptr %t197, i32 2
  store ptr %t15, ptr %t201
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.191
reuse.join.191:
  %t202 = phi ptr [ %t5, %reuse.in_place.189 ], [ %t197, %reuse.copy.190 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t185)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t202, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.33.203:
  %t204 = getelementptr ptr, ptr %t13, i32 1
  %t205 = load ptr, ptr %t204
  call void @__inc_ref(ptr %t205)
  %t206 = getelementptr i8, ptr %t5, i64 -8
  %t207 = load i32, ptr %t206
  %t208 = icmp eq i32 %t207, 1
  br i1 %t208, label %reuse.in_place.209, label %reuse.copy.210
reuse.in_place.209:
  %t212 = getelementptr ptr, ptr %t5, i32 1
  %t213 = load ptr, ptr %t212
  call void @__free_recursive(ptr %t213)
  %t215 = inttoptr i64 52 to ptr
  %t216 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t215, ptr %t216
  call void @__inc_ref(ptr %t205)
  %t214 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t205, ptr %t214
  br label %reuse.join.211
reuse.copy.210:
  %t217 = call ptr @__alloc(i64 24, i32 2)
  %t218 = inttoptr i64 52 to ptr
  %t219 = getelementptr ptr, ptr %t217, i32 0
  store ptr %t218, ptr %t219
  call void @__inc_ref(ptr %t205)
  %t220 = getelementptr ptr, ptr %t217, i32 1
  store ptr %t205, ptr %t220
  call void @__inc_ref(ptr %t15)
  %t221 = getelementptr ptr, ptr %t217, i32 2
  store ptr %t15, ptr %t221
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.211
reuse.join.211:
  %t222 = phi ptr [ %t5, %reuse.in_place.209 ], [ %t217, %reuse.copy.210 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t205)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t222, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.34.223:
  %t224 = getelementptr ptr, ptr %t13, i32 1
  %t225 = load ptr, ptr %t224
  call void @__inc_ref(ptr %t225)
  %t226 = getelementptr i8, ptr %t5, i64 -8
  %t227 = load i32, ptr %t226
  %t228 = icmp eq i32 %t227, 1
  br i1 %t228, label %reuse.in_place.229, label %reuse.copy.230
reuse.in_place.229:
  %t232 = getelementptr ptr, ptr %t5, i32 1
  %t233 = load ptr, ptr %t232
  call void @__free_recursive(ptr %t233)
  %t235 = inttoptr i64 53 to ptr
  %t236 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t235, ptr %t236
  call void @__inc_ref(ptr %t225)
  %t234 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t225, ptr %t234
  br label %reuse.join.231
reuse.copy.230:
  %t237 = call ptr @__alloc(i64 24, i32 2)
  %t238 = inttoptr i64 53 to ptr
  %t239 = getelementptr ptr, ptr %t237, i32 0
  store ptr %t238, ptr %t239
  call void @__inc_ref(ptr %t225)
  %t240 = getelementptr ptr, ptr %t237, i32 1
  store ptr %t225, ptr %t240
  call void @__inc_ref(ptr %t15)
  %t241 = getelementptr ptr, ptr %t237, i32 2
  store ptr %t15, ptr %t241
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.231
reuse.join.231:
  %t242 = phi ptr [ %t5, %reuse.in_place.229 ], [ %t237, %reuse.copy.230 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t225)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t242, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.35.243:
  %t244 = getelementptr ptr, ptr %t13, i32 1
  %t245 = load ptr, ptr %t244
  call void @__inc_ref(ptr %t245)
  %t246 = getelementptr i8, ptr %t5, i64 -8
  %t247 = load i32, ptr %t246
  %t248 = icmp eq i32 %t247, 1
  br i1 %t248, label %reuse.in_place.249, label %reuse.copy.250
reuse.in_place.249:
  %t252 = getelementptr ptr, ptr %t5, i32 1
  %t253 = load ptr, ptr %t252
  call void @__free_recursive(ptr %t253)
  %t255 = inttoptr i64 54 to ptr
  %t256 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t255, ptr %t256
  call void @__inc_ref(ptr %t245)
  %t254 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t245, ptr %t254
  br label %reuse.join.251
reuse.copy.250:
  %t257 = call ptr @__alloc(i64 24, i32 2)
  %t258 = inttoptr i64 54 to ptr
  %t259 = getelementptr ptr, ptr %t257, i32 0
  store ptr %t258, ptr %t259
  call void @__inc_ref(ptr %t245)
  %t260 = getelementptr ptr, ptr %t257, i32 1
  store ptr %t245, ptr %t260
  call void @__inc_ref(ptr %t15)
  %t261 = getelementptr ptr, ptr %t257, i32 2
  store ptr %t15, ptr %t261
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.251
reuse.join.251:
  %t262 = phi ptr [ %t5, %reuse.in_place.249 ], [ %t257, %reuse.copy.250 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t245)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t262, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.36.263:
  %t264 = getelementptr ptr, ptr %t13, i32 1
  %t265 = load ptr, ptr %t264
  call void @__inc_ref(ptr %t265)
  %t266 = getelementptr i8, ptr %t5, i64 -8
  %t267 = load i32, ptr %t266
  %t268 = icmp eq i32 %t267, 1
  br i1 %t268, label %reuse.in_place.269, label %reuse.copy.270
reuse.in_place.269:
  %t272 = getelementptr ptr, ptr %t5, i32 1
  %t273 = load ptr, ptr %t272
  call void @__free_recursive(ptr %t273)
  %t275 = inttoptr i64 55 to ptr
  %t276 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t275, ptr %t276
  call void @__inc_ref(ptr %t265)
  %t274 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t265, ptr %t274
  br label %reuse.join.271
reuse.copy.270:
  %t277 = call ptr @__alloc(i64 24, i32 2)
  %t278 = inttoptr i64 55 to ptr
  %t279 = getelementptr ptr, ptr %t277, i32 0
  store ptr %t278, ptr %t279
  call void @__inc_ref(ptr %t265)
  %t280 = getelementptr ptr, ptr %t277, i32 1
  store ptr %t265, ptr %t280
  call void @__inc_ref(ptr %t15)
  %t281 = getelementptr ptr, ptr %t277, i32 2
  store ptr %t15, ptr %t281
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.271
reuse.join.271:
  %t282 = phi ptr [ %t5, %reuse.in_place.269 ], [ %t277, %reuse.copy.270 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t265)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t282, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.37.283:
  %t284 = getelementptr ptr, ptr %t13, i32 1
  %t285 = load ptr, ptr %t284
  call void @__inc_ref(ptr %t285)
  %t286 = getelementptr i8, ptr %t5, i64 -8
  %t287 = load i32, ptr %t286
  %t288 = icmp eq i32 %t287, 1
  br i1 %t288, label %reuse.in_place.289, label %reuse.copy.290
reuse.in_place.289:
  %t292 = getelementptr ptr, ptr %t5, i32 1
  %t293 = load ptr, ptr %t292
  call void @__free_recursive(ptr %t293)
  %t295 = inttoptr i64 56 to ptr
  %t296 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t295, ptr %t296
  call void @__inc_ref(ptr %t285)
  %t294 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t285, ptr %t294
  br label %reuse.join.291
reuse.copy.290:
  %t297 = call ptr @__alloc(i64 24, i32 2)
  %t298 = inttoptr i64 56 to ptr
  %t299 = getelementptr ptr, ptr %t297, i32 0
  store ptr %t298, ptr %t299
  call void @__inc_ref(ptr %t285)
  %t300 = getelementptr ptr, ptr %t297, i32 1
  store ptr %t285, ptr %t300
  call void @__inc_ref(ptr %t15)
  %t301 = getelementptr ptr, ptr %t297, i32 2
  store ptr %t15, ptr %t301
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.291
reuse.join.291:
  %t302 = phi ptr [ %t5, %reuse.in_place.289 ], [ %t297, %reuse.copy.290 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t285)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t302, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.38.303:
  %t304 = getelementptr ptr, ptr %t13, i32 1
  %t305 = load ptr, ptr %t304
  call void @__inc_ref(ptr %t305)
  %t306 = getelementptr i8, ptr %t5, i64 -8
  %t307 = load i32, ptr %t306
  %t308 = icmp eq i32 %t307, 1
  br i1 %t308, label %reuse.in_place.309, label %reuse.copy.310
reuse.in_place.309:
  %t312 = getelementptr ptr, ptr %t5, i32 1
  %t313 = load ptr, ptr %t312
  call void @__free_recursive(ptr %t313)
  %t315 = inttoptr i64 57 to ptr
  %t316 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t315, ptr %t316
  call void @__inc_ref(ptr %t305)
  %t314 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t305, ptr %t314
  br label %reuse.join.311
reuse.copy.310:
  %t317 = call ptr @__alloc(i64 24, i32 2)
  %t318 = inttoptr i64 57 to ptr
  %t319 = getelementptr ptr, ptr %t317, i32 0
  store ptr %t318, ptr %t319
  call void @__inc_ref(ptr %t305)
  %t320 = getelementptr ptr, ptr %t317, i32 1
  store ptr %t305, ptr %t320
  call void @__inc_ref(ptr %t15)
  %t321 = getelementptr ptr, ptr %t317, i32 2
  store ptr %t15, ptr %t321
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.311
reuse.join.311:
  %t322 = phi ptr [ %t5, %reuse.in_place.309 ], [ %t317, %reuse.copy.310 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t305)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t322, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.39.323:
  %t324 = getelementptr ptr, ptr %t13, i32 1
  %t325 = load ptr, ptr %t324
  call void @__inc_ref(ptr %t325)
  %t326 = getelementptr i8, ptr %t5, i64 -8
  %t327 = load i32, ptr %t326
  %t328 = icmp eq i32 %t327, 1
  br i1 %t328, label %reuse.in_place.329, label %reuse.copy.330
reuse.in_place.329:
  %t332 = getelementptr ptr, ptr %t5, i32 1
  %t333 = load ptr, ptr %t332
  call void @__free_recursive(ptr %t333)
  %t335 = inttoptr i64 58 to ptr
  %t336 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t335, ptr %t336
  call void @__inc_ref(ptr %t325)
  %t334 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t325, ptr %t334
  br label %reuse.join.331
reuse.copy.330:
  %t337 = call ptr @__alloc(i64 24, i32 2)
  %t338 = inttoptr i64 58 to ptr
  %t339 = getelementptr ptr, ptr %t337, i32 0
  store ptr %t338, ptr %t339
  call void @__inc_ref(ptr %t325)
  %t340 = getelementptr ptr, ptr %t337, i32 1
  store ptr %t325, ptr %t340
  call void @__inc_ref(ptr %t15)
  %t341 = getelementptr ptr, ptr %t337, i32 2
  store ptr %t15, ptr %t341
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.331
reuse.join.331:
  %t342 = phi ptr [ %t5, %reuse.in_place.329 ], [ %t337, %reuse.copy.330 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t325)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t342, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.40.343:
  %t344 = getelementptr ptr, ptr %t13, i32 1
  %t345 = load ptr, ptr %t344
  call void @__inc_ref(ptr %t345)
  %t346 = getelementptr i8, ptr %t5, i64 -8
  %t347 = load i32, ptr %t346
  %t348 = icmp eq i32 %t347, 1
  br i1 %t348, label %reuse.in_place.349, label %reuse.copy.350
reuse.in_place.349:
  %t352 = getelementptr ptr, ptr %t5, i32 1
  %t353 = load ptr, ptr %t352
  call void @__free_recursive(ptr %t353)
  %t355 = inttoptr i64 59 to ptr
  %t356 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t355, ptr %t356
  call void @__inc_ref(ptr %t345)
  %t354 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t345, ptr %t354
  br label %reuse.join.351
reuse.copy.350:
  %t357 = call ptr @__alloc(i64 24, i32 2)
  %t358 = inttoptr i64 59 to ptr
  %t359 = getelementptr ptr, ptr %t357, i32 0
  store ptr %t358, ptr %t359
  call void @__inc_ref(ptr %t345)
  %t360 = getelementptr ptr, ptr %t357, i32 1
  store ptr %t345, ptr %t360
  call void @__inc_ref(ptr %t15)
  %t361 = getelementptr ptr, ptr %t357, i32 2
  store ptr %t15, ptr %t361
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.351
reuse.join.351:
  %t362 = phi ptr [ %t5, %reuse.in_place.349 ], [ %t357, %reuse.copy.350 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t345)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t362, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.41.363:
  %t364 = getelementptr ptr, ptr %t13, i32 1
  %t365 = load ptr, ptr %t364
  call void @__inc_ref(ptr %t365)
  %t366 = getelementptr i8, ptr %t5, i64 -8
  %t367 = load i32, ptr %t366
  %t368 = icmp eq i32 %t367, 1
  br i1 %t368, label %reuse.in_place.369, label %reuse.copy.370
reuse.in_place.369:
  %t372 = getelementptr ptr, ptr %t5, i32 1
  %t373 = load ptr, ptr %t372
  call void @__free_recursive(ptr %t373)
  %t375 = inttoptr i64 60 to ptr
  %t376 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t375, ptr %t376
  call void @__inc_ref(ptr %t365)
  %t374 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t365, ptr %t374
  br label %reuse.join.371
reuse.copy.370:
  %t377 = call ptr @__alloc(i64 24, i32 2)
  %t378 = inttoptr i64 60 to ptr
  %t379 = getelementptr ptr, ptr %t377, i32 0
  store ptr %t378, ptr %t379
  call void @__inc_ref(ptr %t365)
  %t380 = getelementptr ptr, ptr %t377, i32 1
  store ptr %t365, ptr %t380
  call void @__inc_ref(ptr %t15)
  %t381 = getelementptr ptr, ptr %t377, i32 2
  store ptr %t15, ptr %t381
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.371
reuse.join.371:
  %t382 = phi ptr [ %t5, %reuse.in_place.369 ], [ %t377, %reuse.copy.370 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t365)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t382, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.default.19:
  unreachable
tco.case.arm.43.383:
  %t384 = getelementptr ptr, ptr %t5, i32 1
  %t385 = load ptr, ptr %t384
  %t386 = getelementptr ptr, ptr %t5, i32 2
  %t387 = load ptr, ptr %t386
  %t388 = getelementptr i8, ptr %t5, i64 -8
  %t389 = load i32, ptr %t388
  %t390 = icmp eq i32 %t389, 1
  br i1 %t390, label %reuse.in_place.391, label %reuse.copy.392
reuse.in_place.391:
  %t394 = inttoptr i64 42 to ptr
  %t395 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t394, ptr %t395
  br label %reuse.join.393
reuse.copy.392:
  %t396 = call ptr @__alloc(i64 24, i32 2)
  %t397 = inttoptr i64 42 to ptr
  %t398 = getelementptr ptr, ptr %t396, i32 0
  store ptr %t397, ptr %t398
  call void @__inc_ref(ptr %t385)
  %t399 = getelementptr ptr, ptr %t396, i32 1
  store ptr %t385, ptr %t399
  call void @__inc_ref(ptr %t387)
  %t400 = getelementptr ptr, ptr %t396, i32 2
  store ptr %t387, ptr %t400
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.393
reuse.join.393:
  %t401 = phi ptr [ %t5, %reuse.in_place.391 ], [ %t396, %reuse.copy.392 ]
  %t402 = call ptr @__alloc(i64 16, i32 1)
  %t403 = inttoptr i64 80 to ptr
  %t404 = getelementptr ptr, ptr %t402, i32 0
  store ptr %t403, ptr %t404
  call void @__inc_ref(ptr %t6)
  %t405 = getelementptr ptr, ptr %t402, i32 1
  store ptr %t6, ptr %t405
  call void @__free_recursive(ptr %t6)
  store ptr %t401, ptr %t3
  store ptr %t402, ptr %t4
  br label %tco.loop.0
tco.case.arm.44.406:
  %t407 = getelementptr ptr, ptr %t5, i32 1
  %t408 = load ptr, ptr %t407
  %t409 = getelementptr ptr, ptr %t5, i32 2
  %t410 = load ptr, ptr %t409
  %t411 = getelementptr i8, ptr %t5, i64 -8
  %t412 = load i32, ptr %t411
  %t413 = icmp eq i32 %t412, 1
  br i1 %t413, label %reuse.in_place.414, label %reuse.copy.415
reuse.in_place.414:
  %t417 = inttoptr i64 42 to ptr
  %t418 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t417, ptr %t418
  br label %reuse.join.416
reuse.copy.415:
  %t419 = call ptr @__alloc(i64 24, i32 2)
  %t420 = inttoptr i64 42 to ptr
  %t421 = getelementptr ptr, ptr %t419, i32 0
  store ptr %t420, ptr %t421
  call void @__inc_ref(ptr %t408)
  %t422 = getelementptr ptr, ptr %t419, i32 1
  store ptr %t408, ptr %t422
  call void @__inc_ref(ptr %t410)
  %t423 = getelementptr ptr, ptr %t419, i32 2
  store ptr %t410, ptr %t423
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.416
reuse.join.416:
  %t424 = phi ptr [ %t5, %reuse.in_place.414 ], [ %t419, %reuse.copy.415 ]
  %t425 = call ptr @__alloc(i64 16, i32 1)
  %t426 = inttoptr i64 81 to ptr
  %t427 = getelementptr ptr, ptr %t425, i32 0
  store ptr %t426, ptr %t427
  call void @__inc_ref(ptr %t6)
  %t428 = getelementptr ptr, ptr %t425, i32 1
  store ptr %t6, ptr %t428
  call void @__free_recursive(ptr %t6)
  store ptr %t424, ptr %t3
  store ptr %t425, ptr %t4
  br label %tco.loop.0
tco.case.arm.45.429:
  %t430 = getelementptr ptr, ptr %t5, i32 1
  %t431 = load ptr, ptr %t430
  %t432 = getelementptr ptr, ptr %t5, i32 2
  %t433 = load ptr, ptr %t432
  %t434 = getelementptr i8, ptr %t5, i64 -8
  %t435 = load i32, ptr %t434
  %t436 = icmp eq i32 %t435, 1
  br i1 %t436, label %reuse.in_place.437, label %reuse.copy.438
reuse.in_place.437:
  %t440 = inttoptr i64 42 to ptr
  %t441 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t440, ptr %t441
  br label %reuse.join.439
reuse.copy.438:
  %t442 = call ptr @__alloc(i64 24, i32 2)
  %t443 = inttoptr i64 42 to ptr
  %t444 = getelementptr ptr, ptr %t442, i32 0
  store ptr %t443, ptr %t444
  call void @__inc_ref(ptr %t431)
  %t445 = getelementptr ptr, ptr %t442, i32 1
  store ptr %t431, ptr %t445
  call void @__inc_ref(ptr %t433)
  %t446 = getelementptr ptr, ptr %t442, i32 2
  store ptr %t433, ptr %t446
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.439
reuse.join.439:
  %t447 = phi ptr [ %t5, %reuse.in_place.437 ], [ %t442, %reuse.copy.438 ]
  %t448 = call ptr @__alloc(i64 16, i32 1)
  %t449 = inttoptr i64 82 to ptr
  %t450 = getelementptr ptr, ptr %t448, i32 0
  store ptr %t449, ptr %t450
  call void @__inc_ref(ptr %t6)
  %t451 = getelementptr ptr, ptr %t448, i32 1
  store ptr %t6, ptr %t451
  call void @__free_recursive(ptr %t6)
  store ptr %t447, ptr %t3
  store ptr %t448, ptr %t4
  br label %tco.loop.0
tco.case.arm.46.452:
  %t453 = getelementptr ptr, ptr %t5, i32 1
  %t454 = load ptr, ptr %t453
  %t455 = getelementptr ptr, ptr %t5, i32 2
  %t456 = load ptr, ptr %t455
  %t457 = getelementptr i8, ptr %t5, i64 -8
  %t458 = load i32, ptr %t457
  %t459 = icmp eq i32 %t458, 1
  br i1 %t459, label %reuse.in_place.460, label %reuse.copy.461
reuse.in_place.460:
  %t463 = inttoptr i64 42 to ptr
  %t464 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t463, ptr %t464
  br label %reuse.join.462
reuse.copy.461:
  %t465 = call ptr @__alloc(i64 24, i32 2)
  %t466 = inttoptr i64 42 to ptr
  %t467 = getelementptr ptr, ptr %t465, i32 0
  store ptr %t466, ptr %t467
  call void @__inc_ref(ptr %t454)
  %t468 = getelementptr ptr, ptr %t465, i32 1
  store ptr %t454, ptr %t468
  call void @__inc_ref(ptr %t456)
  %t469 = getelementptr ptr, ptr %t465, i32 2
  store ptr %t456, ptr %t469
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.462
reuse.join.462:
  %t470 = phi ptr [ %t5, %reuse.in_place.460 ], [ %t465, %reuse.copy.461 ]
  %t471 = call ptr @__alloc(i64 16, i32 1)
  %t472 = inttoptr i64 83 to ptr
  %t473 = getelementptr ptr, ptr %t471, i32 0
  store ptr %t472, ptr %t473
  call void @__inc_ref(ptr %t6)
  %t474 = getelementptr ptr, ptr %t471, i32 1
  store ptr %t6, ptr %t474
  call void @__free_recursive(ptr %t6)
  store ptr %t470, ptr %t3
  store ptr %t471, ptr %t4
  br label %tco.loop.0
tco.case.arm.47.475:
  %t476 = getelementptr ptr, ptr %t5, i32 1
  %t477 = load ptr, ptr %t476
  %t478 = getelementptr ptr, ptr %t5, i32 2
  %t479 = load ptr, ptr %t478
  %t480 = getelementptr i8, ptr %t5, i64 -8
  %t481 = load i32, ptr %t480
  %t482 = icmp eq i32 %t481, 1
  br i1 %t482, label %reuse.in_place.483, label %reuse.copy.484
reuse.in_place.483:
  %t486 = inttoptr i64 42 to ptr
  %t487 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t486, ptr %t487
  br label %reuse.join.485
reuse.copy.484:
  %t488 = call ptr @__alloc(i64 24, i32 2)
  %t489 = inttoptr i64 42 to ptr
  %t490 = getelementptr ptr, ptr %t488, i32 0
  store ptr %t489, ptr %t490
  call void @__inc_ref(ptr %t477)
  %t491 = getelementptr ptr, ptr %t488, i32 1
  store ptr %t477, ptr %t491
  call void @__inc_ref(ptr %t479)
  %t492 = getelementptr ptr, ptr %t488, i32 2
  store ptr %t479, ptr %t492
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.485
reuse.join.485:
  %t493 = phi ptr [ %t5, %reuse.in_place.483 ], [ %t488, %reuse.copy.484 ]
  %t494 = call ptr @__alloc(i64 16, i32 1)
  %t495 = inttoptr i64 84 to ptr
  %t496 = getelementptr ptr, ptr %t494, i32 0
  store ptr %t495, ptr %t496
  call void @__inc_ref(ptr %t6)
  %t497 = getelementptr ptr, ptr %t494, i32 1
  store ptr %t6, ptr %t497
  call void @__free_recursive(ptr %t6)
  store ptr %t493, ptr %t3
  store ptr %t494, ptr %t4
  br label %tco.loop.0
tco.case.arm.48.498:
  %t499 = getelementptr ptr, ptr %t5, i32 1
  %t500 = load ptr, ptr %t499
  %t501 = getelementptr ptr, ptr %t5, i32 2
  %t502 = load ptr, ptr %t501
  %t503 = getelementptr i8, ptr %t5, i64 -8
  %t504 = load i32, ptr %t503
  %t505 = icmp eq i32 %t504, 1
  br i1 %t505, label %reuse.in_place.506, label %reuse.copy.507
reuse.in_place.506:
  %t509 = inttoptr i64 42 to ptr
  %t510 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t509, ptr %t510
  br label %reuse.join.508
reuse.copy.507:
  %t511 = call ptr @__alloc(i64 24, i32 2)
  %t512 = inttoptr i64 42 to ptr
  %t513 = getelementptr ptr, ptr %t511, i32 0
  store ptr %t512, ptr %t513
  call void @__inc_ref(ptr %t500)
  %t514 = getelementptr ptr, ptr %t511, i32 1
  store ptr %t500, ptr %t514
  call void @__inc_ref(ptr %t502)
  %t515 = getelementptr ptr, ptr %t511, i32 2
  store ptr %t502, ptr %t515
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.508
reuse.join.508:
  %t516 = phi ptr [ %t5, %reuse.in_place.506 ], [ %t511, %reuse.copy.507 ]
  %t517 = call ptr @__alloc(i64 16, i32 1)
  %t518 = inttoptr i64 85 to ptr
  %t519 = getelementptr ptr, ptr %t517, i32 0
  store ptr %t518, ptr %t519
  call void @__inc_ref(ptr %t6)
  %t520 = getelementptr ptr, ptr %t517, i32 1
  store ptr %t6, ptr %t520
  call void @__free_recursive(ptr %t6)
  store ptr %t516, ptr %t3
  store ptr %t517, ptr %t4
  br label %tco.loop.0
tco.case.arm.49.521:
  %t522 = getelementptr ptr, ptr %t5, i32 1
  %t523 = load ptr, ptr %t522
  %t524 = getelementptr ptr, ptr %t5, i32 2
  %t525 = load ptr, ptr %t524
  %t526 = getelementptr i8, ptr %t5, i64 -8
  %t527 = load i32, ptr %t526
  %t528 = icmp eq i32 %t527, 1
  br i1 %t528, label %reuse.in_place.529, label %reuse.copy.530
reuse.in_place.529:
  %t532 = inttoptr i64 42 to ptr
  %t533 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t532, ptr %t533
  br label %reuse.join.531
reuse.copy.530:
  %t534 = call ptr @__alloc(i64 24, i32 2)
  %t535 = inttoptr i64 42 to ptr
  %t536 = getelementptr ptr, ptr %t534, i32 0
  store ptr %t535, ptr %t536
  call void @__inc_ref(ptr %t523)
  %t537 = getelementptr ptr, ptr %t534, i32 1
  store ptr %t523, ptr %t537
  call void @__inc_ref(ptr %t525)
  %t538 = getelementptr ptr, ptr %t534, i32 2
  store ptr %t525, ptr %t538
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.531
reuse.join.531:
  %t539 = phi ptr [ %t5, %reuse.in_place.529 ], [ %t534, %reuse.copy.530 ]
  %t540 = call ptr @__alloc(i64 16, i32 1)
  %t541 = inttoptr i64 86 to ptr
  %t542 = getelementptr ptr, ptr %t540, i32 0
  store ptr %t541, ptr %t542
  call void @__inc_ref(ptr %t6)
  %t543 = getelementptr ptr, ptr %t540, i32 1
  store ptr %t6, ptr %t543
  call void @__free_recursive(ptr %t6)
  store ptr %t539, ptr %t3
  store ptr %t540, ptr %t4
  br label %tco.loop.0
tco.case.arm.50.544:
  %t545 = getelementptr ptr, ptr %t5, i32 1
  %t546 = load ptr, ptr %t545
  %t547 = getelementptr ptr, ptr %t5, i32 2
  %t548 = load ptr, ptr %t547
  %t549 = getelementptr i8, ptr %t5, i64 -8
  %t550 = load i32, ptr %t549
  %t551 = icmp eq i32 %t550, 1
  br i1 %t551, label %reuse.in_place.552, label %reuse.copy.553
reuse.in_place.552:
  %t555 = inttoptr i64 42 to ptr
  %t556 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t555, ptr %t556
  br label %reuse.join.554
reuse.copy.553:
  %t557 = call ptr @__alloc(i64 24, i32 2)
  %t558 = inttoptr i64 42 to ptr
  %t559 = getelementptr ptr, ptr %t557, i32 0
  store ptr %t558, ptr %t559
  call void @__inc_ref(ptr %t546)
  %t560 = getelementptr ptr, ptr %t557, i32 1
  store ptr %t546, ptr %t560
  call void @__inc_ref(ptr %t548)
  %t561 = getelementptr ptr, ptr %t557, i32 2
  store ptr %t548, ptr %t561
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.554
reuse.join.554:
  %t562 = phi ptr [ %t5, %reuse.in_place.552 ], [ %t557, %reuse.copy.553 ]
  %t563 = call ptr @__alloc(i64 16, i32 1)
  %t564 = inttoptr i64 87 to ptr
  %t565 = getelementptr ptr, ptr %t563, i32 0
  store ptr %t564, ptr %t565
  call void @__inc_ref(ptr %t6)
  %t566 = getelementptr ptr, ptr %t563, i32 1
  store ptr %t6, ptr %t566
  call void @__free_recursive(ptr %t6)
  store ptr %t562, ptr %t3
  store ptr %t563, ptr %t4
  br label %tco.loop.0
tco.case.arm.51.567:
  %t568 = getelementptr ptr, ptr %t5, i32 1
  %t569 = load ptr, ptr %t568
  %t570 = getelementptr ptr, ptr %t5, i32 2
  %t571 = load ptr, ptr %t570
  %t572 = getelementptr i8, ptr %t5, i64 -8
  %t573 = load i32, ptr %t572
  %t574 = icmp eq i32 %t573, 1
  br i1 %t574, label %reuse.in_place.575, label %reuse.copy.576
reuse.in_place.575:
  %t578 = inttoptr i64 42 to ptr
  %t579 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t578, ptr %t579
  br label %reuse.join.577
reuse.copy.576:
  %t580 = call ptr @__alloc(i64 24, i32 2)
  %t581 = inttoptr i64 42 to ptr
  %t582 = getelementptr ptr, ptr %t580, i32 0
  store ptr %t581, ptr %t582
  call void @__inc_ref(ptr %t569)
  %t583 = getelementptr ptr, ptr %t580, i32 1
  store ptr %t569, ptr %t583
  call void @__inc_ref(ptr %t571)
  %t584 = getelementptr ptr, ptr %t580, i32 2
  store ptr %t571, ptr %t584
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.577
reuse.join.577:
  %t585 = phi ptr [ %t5, %reuse.in_place.575 ], [ %t580, %reuse.copy.576 ]
  %t586 = call ptr @__alloc(i64 16, i32 1)
  %t587 = inttoptr i64 88 to ptr
  %t588 = getelementptr ptr, ptr %t586, i32 0
  store ptr %t587, ptr %t588
  call void @__inc_ref(ptr %t6)
  %t589 = getelementptr ptr, ptr %t586, i32 1
  store ptr %t6, ptr %t589
  call void @__free_recursive(ptr %t6)
  store ptr %t585, ptr %t3
  store ptr %t586, ptr %t4
  br label %tco.loop.0
tco.case.arm.52.590:
  %t591 = getelementptr ptr, ptr %t5, i32 1
  %t592 = load ptr, ptr %t591
  %t593 = getelementptr ptr, ptr %t5, i32 2
  %t594 = load ptr, ptr %t593
  %t595 = getelementptr i8, ptr %t5, i64 -8
  %t596 = load i32, ptr %t595
  %t597 = icmp eq i32 %t596, 1
  br i1 %t597, label %reuse.in_place.598, label %reuse.copy.599
reuse.in_place.598:
  %t601 = inttoptr i64 42 to ptr
  %t602 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t601, ptr %t602
  br label %reuse.join.600
reuse.copy.599:
  %t603 = call ptr @__alloc(i64 24, i32 2)
  %t604 = inttoptr i64 42 to ptr
  %t605 = getelementptr ptr, ptr %t603, i32 0
  store ptr %t604, ptr %t605
  call void @__inc_ref(ptr %t592)
  %t606 = getelementptr ptr, ptr %t603, i32 1
  store ptr %t592, ptr %t606
  call void @__inc_ref(ptr %t594)
  %t607 = getelementptr ptr, ptr %t603, i32 2
  store ptr %t594, ptr %t607
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.600
reuse.join.600:
  %t608 = phi ptr [ %t5, %reuse.in_place.598 ], [ %t603, %reuse.copy.599 ]
  %t609 = call ptr @__alloc(i64 16, i32 1)
  %t610 = inttoptr i64 89 to ptr
  %t611 = getelementptr ptr, ptr %t609, i32 0
  store ptr %t610, ptr %t611
  call void @__inc_ref(ptr %t6)
  %t612 = getelementptr ptr, ptr %t609, i32 1
  store ptr %t6, ptr %t612
  call void @__free_recursive(ptr %t6)
  store ptr %t608, ptr %t3
  store ptr %t609, ptr %t4
  br label %tco.loop.0
tco.case.arm.53.613:
  %t614 = getelementptr ptr, ptr %t5, i32 1
  %t615 = load ptr, ptr %t614
  %t616 = getelementptr ptr, ptr %t5, i32 2
  %t617 = load ptr, ptr %t616
  %t618 = getelementptr i8, ptr %t5, i64 -8
  %t619 = load i32, ptr %t618
  %t620 = icmp eq i32 %t619, 1
  br i1 %t620, label %reuse.in_place.621, label %reuse.copy.622
reuse.in_place.621:
  %t624 = inttoptr i64 42 to ptr
  %t625 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t624, ptr %t625
  br label %reuse.join.623
reuse.copy.622:
  %t626 = call ptr @__alloc(i64 24, i32 2)
  %t627 = inttoptr i64 42 to ptr
  %t628 = getelementptr ptr, ptr %t626, i32 0
  store ptr %t627, ptr %t628
  call void @__inc_ref(ptr %t615)
  %t629 = getelementptr ptr, ptr %t626, i32 1
  store ptr %t615, ptr %t629
  call void @__inc_ref(ptr %t617)
  %t630 = getelementptr ptr, ptr %t626, i32 2
  store ptr %t617, ptr %t630
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.623
reuse.join.623:
  %t631 = phi ptr [ %t5, %reuse.in_place.621 ], [ %t626, %reuse.copy.622 ]
  %t632 = call ptr @__alloc(i64 16, i32 1)
  %t633 = inttoptr i64 90 to ptr
  %t634 = getelementptr ptr, ptr %t632, i32 0
  store ptr %t633, ptr %t634
  call void @__inc_ref(ptr %t6)
  %t635 = getelementptr ptr, ptr %t632, i32 1
  store ptr %t6, ptr %t635
  call void @__free_recursive(ptr %t6)
  store ptr %t631, ptr %t3
  store ptr %t632, ptr %t4
  br label %tco.loop.0
tco.case.arm.54.636:
  %t637 = getelementptr ptr, ptr %t5, i32 1
  %t638 = load ptr, ptr %t637
  %t639 = getelementptr ptr, ptr %t5, i32 2
  %t640 = load ptr, ptr %t639
  %t641 = getelementptr i8, ptr %t5, i64 -8
  %t642 = load i32, ptr %t641
  %t643 = icmp eq i32 %t642, 1
  br i1 %t643, label %reuse.in_place.644, label %reuse.copy.645
reuse.in_place.644:
  %t647 = inttoptr i64 42 to ptr
  %t648 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t647, ptr %t648
  br label %reuse.join.646
reuse.copy.645:
  %t649 = call ptr @__alloc(i64 24, i32 2)
  %t650 = inttoptr i64 42 to ptr
  %t651 = getelementptr ptr, ptr %t649, i32 0
  store ptr %t650, ptr %t651
  call void @__inc_ref(ptr %t638)
  %t652 = getelementptr ptr, ptr %t649, i32 1
  store ptr %t638, ptr %t652
  call void @__inc_ref(ptr %t640)
  %t653 = getelementptr ptr, ptr %t649, i32 2
  store ptr %t640, ptr %t653
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.646
reuse.join.646:
  %t654 = phi ptr [ %t5, %reuse.in_place.644 ], [ %t649, %reuse.copy.645 ]
  %t655 = call ptr @__alloc(i64 16, i32 1)
  %t656 = inttoptr i64 91 to ptr
  %t657 = getelementptr ptr, ptr %t655, i32 0
  store ptr %t656, ptr %t657
  call void @__inc_ref(ptr %t6)
  %t658 = getelementptr ptr, ptr %t655, i32 1
  store ptr %t6, ptr %t658
  call void @__free_recursive(ptr %t6)
  store ptr %t654, ptr %t3
  store ptr %t655, ptr %t4
  br label %tco.loop.0
tco.case.arm.55.659:
  %t660 = getelementptr ptr, ptr %t5, i32 1
  %t661 = load ptr, ptr %t660
  %t662 = getelementptr ptr, ptr %t5, i32 2
  %t663 = load ptr, ptr %t662
  %t664 = getelementptr i8, ptr %t5, i64 -8
  %t665 = load i32, ptr %t664
  %t666 = icmp eq i32 %t665, 1
  br i1 %t666, label %reuse.in_place.667, label %reuse.copy.668
reuse.in_place.667:
  %t670 = inttoptr i64 42 to ptr
  %t671 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t670, ptr %t671
  br label %reuse.join.669
reuse.copy.668:
  %t672 = call ptr @__alloc(i64 24, i32 2)
  %t673 = inttoptr i64 42 to ptr
  %t674 = getelementptr ptr, ptr %t672, i32 0
  store ptr %t673, ptr %t674
  call void @__inc_ref(ptr %t661)
  %t675 = getelementptr ptr, ptr %t672, i32 1
  store ptr %t661, ptr %t675
  call void @__inc_ref(ptr %t663)
  %t676 = getelementptr ptr, ptr %t672, i32 2
  store ptr %t663, ptr %t676
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.669
reuse.join.669:
  %t677 = phi ptr [ %t5, %reuse.in_place.667 ], [ %t672, %reuse.copy.668 ]
  %t678 = call ptr @__alloc(i64 16, i32 1)
  %t679 = inttoptr i64 92 to ptr
  %t680 = getelementptr ptr, ptr %t678, i32 0
  store ptr %t679, ptr %t680
  call void @__inc_ref(ptr %t6)
  %t681 = getelementptr ptr, ptr %t678, i32 1
  store ptr %t6, ptr %t681
  call void @__free_recursive(ptr %t6)
  store ptr %t677, ptr %t3
  store ptr %t678, ptr %t4
  br label %tco.loop.0
tco.case.arm.56.682:
  %t683 = getelementptr ptr, ptr %t5, i32 1
  %t684 = load ptr, ptr %t683
  %t685 = getelementptr ptr, ptr %t5, i32 2
  %t686 = load ptr, ptr %t685
  %t687 = getelementptr i8, ptr %t5, i64 -8
  %t688 = load i32, ptr %t687
  %t689 = icmp eq i32 %t688, 1
  br i1 %t689, label %reuse.in_place.690, label %reuse.copy.691
reuse.in_place.690:
  %t693 = inttoptr i64 42 to ptr
  %t694 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t693, ptr %t694
  br label %reuse.join.692
reuse.copy.691:
  %t695 = call ptr @__alloc(i64 24, i32 2)
  %t696 = inttoptr i64 42 to ptr
  %t697 = getelementptr ptr, ptr %t695, i32 0
  store ptr %t696, ptr %t697
  call void @__inc_ref(ptr %t684)
  %t698 = getelementptr ptr, ptr %t695, i32 1
  store ptr %t684, ptr %t698
  call void @__inc_ref(ptr %t686)
  %t699 = getelementptr ptr, ptr %t695, i32 2
  store ptr %t686, ptr %t699
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.692
reuse.join.692:
  %t700 = phi ptr [ %t5, %reuse.in_place.690 ], [ %t695, %reuse.copy.691 ]
  %t701 = call ptr @__alloc(i64 16, i32 1)
  %t702 = inttoptr i64 93 to ptr
  %t703 = getelementptr ptr, ptr %t701, i32 0
  store ptr %t702, ptr %t703
  call void @__inc_ref(ptr %t6)
  %t704 = getelementptr ptr, ptr %t701, i32 1
  store ptr %t6, ptr %t704
  call void @__free_recursive(ptr %t6)
  store ptr %t700, ptr %t3
  store ptr %t701, ptr %t4
  br label %tco.loop.0
tco.case.arm.57.705:
  %t706 = getelementptr ptr, ptr %t5, i32 1
  %t707 = load ptr, ptr %t706
  %t708 = getelementptr ptr, ptr %t5, i32 2
  %t709 = load ptr, ptr %t708
  %t710 = getelementptr i8, ptr %t5, i64 -8
  %t711 = load i32, ptr %t710
  %t712 = icmp eq i32 %t711, 1
  br i1 %t712, label %reuse.in_place.713, label %reuse.copy.714
reuse.in_place.713:
  %t716 = inttoptr i64 42 to ptr
  %t717 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t716, ptr %t717
  br label %reuse.join.715
reuse.copy.714:
  %t718 = call ptr @__alloc(i64 24, i32 2)
  %t719 = inttoptr i64 42 to ptr
  %t720 = getelementptr ptr, ptr %t718, i32 0
  store ptr %t719, ptr %t720
  call void @__inc_ref(ptr %t707)
  %t721 = getelementptr ptr, ptr %t718, i32 1
  store ptr %t707, ptr %t721
  call void @__inc_ref(ptr %t709)
  %t722 = getelementptr ptr, ptr %t718, i32 2
  store ptr %t709, ptr %t722
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.715
reuse.join.715:
  %t723 = phi ptr [ %t5, %reuse.in_place.713 ], [ %t718, %reuse.copy.714 ]
  %t724 = call ptr @__alloc(i64 16, i32 1)
  %t725 = inttoptr i64 94 to ptr
  %t726 = getelementptr ptr, ptr %t724, i32 0
  store ptr %t725, ptr %t726
  call void @__inc_ref(ptr %t6)
  %t727 = getelementptr ptr, ptr %t724, i32 1
  store ptr %t6, ptr %t727
  call void @__free_recursive(ptr %t6)
  store ptr %t723, ptr %t3
  store ptr %t724, ptr %t4
  br label %tco.loop.0
tco.case.arm.58.728:
  %t729 = getelementptr ptr, ptr %t5, i32 1
  %t730 = load ptr, ptr %t729
  %t731 = getelementptr ptr, ptr %t5, i32 2
  %t732 = load ptr, ptr %t731
  %t733 = getelementptr i8, ptr %t5, i64 -8
  %t734 = load i32, ptr %t733
  %t735 = icmp eq i32 %t734, 1
  br i1 %t735, label %reuse.in_place.736, label %reuse.copy.737
reuse.in_place.736:
  %t739 = inttoptr i64 42 to ptr
  %t740 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t739, ptr %t740
  br label %reuse.join.738
reuse.copy.737:
  %t741 = call ptr @__alloc(i64 24, i32 2)
  %t742 = inttoptr i64 42 to ptr
  %t743 = getelementptr ptr, ptr %t741, i32 0
  store ptr %t742, ptr %t743
  call void @__inc_ref(ptr %t730)
  %t744 = getelementptr ptr, ptr %t741, i32 1
  store ptr %t730, ptr %t744
  call void @__inc_ref(ptr %t732)
  %t745 = getelementptr ptr, ptr %t741, i32 2
  store ptr %t732, ptr %t745
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.738
reuse.join.738:
  %t746 = phi ptr [ %t5, %reuse.in_place.736 ], [ %t741, %reuse.copy.737 ]
  %t747 = call ptr @__alloc(i64 16, i32 1)
  %t748 = inttoptr i64 95 to ptr
  %t749 = getelementptr ptr, ptr %t747, i32 0
  store ptr %t748, ptr %t749
  call void @__inc_ref(ptr %t6)
  %t750 = getelementptr ptr, ptr %t747, i32 1
  store ptr %t6, ptr %t750
  call void @__free_recursive(ptr %t6)
  store ptr %t746, ptr %t3
  store ptr %t747, ptr %t4
  br label %tco.loop.0
tco.case.arm.59.751:
  %t752 = getelementptr ptr, ptr %t5, i32 1
  %t753 = load ptr, ptr %t752
  %t754 = getelementptr ptr, ptr %t5, i32 2
  %t755 = load ptr, ptr %t754
  %t756 = getelementptr i8, ptr %t5, i64 -8
  %t757 = load i32, ptr %t756
  %t758 = icmp eq i32 %t757, 1
  br i1 %t758, label %reuse.in_place.759, label %reuse.copy.760
reuse.in_place.759:
  %t762 = inttoptr i64 42 to ptr
  %t763 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t762, ptr %t763
  br label %reuse.join.761
reuse.copy.760:
  %t764 = call ptr @__alloc(i64 24, i32 2)
  %t765 = inttoptr i64 42 to ptr
  %t766 = getelementptr ptr, ptr %t764, i32 0
  store ptr %t765, ptr %t766
  call void @__inc_ref(ptr %t753)
  %t767 = getelementptr ptr, ptr %t764, i32 1
  store ptr %t753, ptr %t767
  call void @__inc_ref(ptr %t755)
  %t768 = getelementptr ptr, ptr %t764, i32 2
  store ptr %t755, ptr %t768
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.761
reuse.join.761:
  %t769 = phi ptr [ %t5, %reuse.in_place.759 ], [ %t764, %reuse.copy.760 ]
  %t770 = call ptr @__alloc(i64 16, i32 1)
  %t771 = inttoptr i64 96 to ptr
  %t772 = getelementptr ptr, ptr %t770, i32 0
  store ptr %t771, ptr %t772
  call void @__inc_ref(ptr %t6)
  %t773 = getelementptr ptr, ptr %t770, i32 1
  store ptr %t6, ptr %t773
  call void @__free_recursive(ptr %t6)
  store ptr %t769, ptr %t3
  store ptr %t770, ptr %t4
  br label %tco.loop.0
tco.case.arm.60.774:
  %t775 = getelementptr ptr, ptr %t5, i32 1
  %t776 = load ptr, ptr %t775
  %t777 = getelementptr ptr, ptr %t5, i32 2
  %t778 = load ptr, ptr %t777
  %t779 = getelementptr i8, ptr %t5, i64 -8
  %t780 = load i32, ptr %t779
  %t781 = icmp eq i32 %t780, 1
  br i1 %t781, label %reuse.in_place.782, label %reuse.copy.783
reuse.in_place.782:
  %t785 = inttoptr i64 42 to ptr
  %t786 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t785, ptr %t786
  br label %reuse.join.784
reuse.copy.783:
  %t787 = call ptr @__alloc(i64 24, i32 2)
  %t788 = inttoptr i64 42 to ptr
  %t789 = getelementptr ptr, ptr %t787, i32 0
  store ptr %t788, ptr %t789
  call void @__inc_ref(ptr %t776)
  %t790 = getelementptr ptr, ptr %t787, i32 1
  store ptr %t776, ptr %t790
  call void @__inc_ref(ptr %t778)
  %t791 = getelementptr ptr, ptr %t787, i32 2
  store ptr %t778, ptr %t791
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.784
reuse.join.784:
  %t792 = phi ptr [ %t5, %reuse.in_place.782 ], [ %t787, %reuse.copy.783 ]
  %t793 = call ptr @__alloc(i64 16, i32 1)
  %t794 = inttoptr i64 97 to ptr
  %t795 = getelementptr ptr, ptr %t793, i32 0
  store ptr %t794, ptr %t795
  call void @__inc_ref(ptr %t6)
  %t796 = getelementptr ptr, ptr %t793, i32 1
  store ptr %t6, ptr %t796
  call void @__free_recursive(ptr %t6)
  store ptr %t792, ptr %t3
  store ptr %t793, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t797 = load ptr, ptr %t2
  ret ptr %t797
}

define internal ptr @v__apply__scc__apply1__df__lam_10_1__df__lam_11_2__df__lam_22_4__df__lam_23_5__df__lam_28_7__df__lam_29_11__df__lam_4_9__df__lam_5_10__lift_13__lift_14__lift_17__lift_18__lift_2__lift_20__lift_21__lift_26__lift_27__lift_3(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 79, label %tco.case.arm.79.11 i64 80, label %tco.case.arm.80.12 i64 81, label %tco.case.arm.81.16 i64 82, label %tco.case.arm.82.20 i64 83, label %tco.case.arm.83.25 i64 84, label %tco.case.arm.84.30 i64 85, label %tco.case.arm.85.35 i64 86, label %tco.case.arm.86.40 i64 87, label %tco.case.arm.87.44 i64 88, label %tco.case.arm.88.48 i64 89, label %tco.case.arm.89.52 i64 90, label %tco.case.arm.90.56 i64 91, label %tco.case.arm.91.60 i64 92, label %tco.case.arm.92.64 i64 93, label %tco.case.arm.93.68 i64 94, label %tco.case.arm.94.72 i64 95, label %tco.case.arm.95.76 i64 96, label %tco.case.arm.96.80 i64 97, label %tco.case.arm.97.84 ]
tco.case.arm.79.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.80.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  call void @__inc_ref(ptr %t6)
  %t15 = call ptr @v__df_handleErrorIO_0(ptr %t6)
  call void @__inc_ref(ptr %t14)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t14)
  store ptr %t14, ptr %t3
  store ptr %t15, ptr %t4
  br label %tco.loop.0
tco.case.arm.81.16:
  %t17 = getelementptr ptr, ptr %t5, i32 1
  %t18 = load ptr, ptr %t17
  call void @__inc_ref(ptr %t18)
  call void @__inc_ref(ptr %t6)
  %t19 = call ptr @v__df_handleErrorIO_0(ptr %t6)
  call void @__inc_ref(ptr %t18)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t18)
  store ptr %t18, ptr %t3
  store ptr %t19, ptr %t4
  br label %tco.loop.0
tco.case.arm.82.20:
  %t21 = getelementptr ptr, ptr %t5, i32 1
  %t22 = load ptr, ptr %t21
  call void @__inc_ref(ptr %t22)
  call void @__inc_ref(ptr %t6)
  %t23 = call ptr @v__lift_19(ptr %t6)
  %t24 = call ptr @v__df__rowspec_15_3(ptr %t23)
  call void @__inc_ref(ptr %t22)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t22)
  store ptr %t22, ptr %t3
  store ptr %t24, ptr %t4
  br label %tco.loop.0
tco.case.arm.83.25:
  %t26 = getelementptr ptr, ptr %t5, i32 1
  %t27 = load ptr, ptr %t26
  call void @__inc_ref(ptr %t27)
  call void @__inc_ref(ptr %t6)
  %t28 = call ptr @v__lift_19(ptr %t6)
  %t29 = call ptr @v__df__rowspec_15_3(ptr %t28)
  call void @__inc_ref(ptr %t27)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t27)
  store ptr %t27, ptr %t3
  store ptr %t29, ptr %t4
  br label %tco.loop.0
tco.case.arm.84.30:
  %t31 = getelementptr ptr, ptr %t5, i32 1
  %t32 = load ptr, ptr %t31
  call void @__inc_ref(ptr %t32)
  call void @__inc_ref(ptr %t6)
  %t33 = call ptr @v__lift_25(ptr %t6)
  %t34 = call ptr @v__df_andThenIO_8(ptr %t33)
  call void @__inc_ref(ptr %t32)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t32)
  store ptr %t32, ptr %t3
  store ptr %t34, ptr %t4
  br label %tco.loop.0
tco.case.arm.85.35:
  %t36 = getelementptr ptr, ptr %t5, i32 1
  %t37 = load ptr, ptr %t36
  call void @__inc_ref(ptr %t37)
  call void @__inc_ref(ptr %t6)
  %t38 = call ptr @v__lift_25(ptr %t6)
  %t39 = call ptr @v__df_andThenIO_8(ptr %t38)
  call void @__inc_ref(ptr %t37)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t37)
  store ptr %t37, ptr %t3
  store ptr %t39, ptr %t4
  br label %tco.loop.0
tco.case.arm.86.40:
  %t41 = getelementptr ptr, ptr %t5, i32 1
  %t42 = load ptr, ptr %t41
  call void @__inc_ref(ptr %t42)
  call void @__inc_ref(ptr %t6)
  %t43 = call ptr @v__df_andThenIO_8(ptr %t6)
  call void @__inc_ref(ptr %t42)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t42)
  store ptr %t42, ptr %t3
  store ptr %t43, ptr %t4
  br label %tco.loop.0
tco.case.arm.87.44:
  %t45 = getelementptr ptr, ptr %t5, i32 1
  %t46 = load ptr, ptr %t45
  call void @__inc_ref(ptr %t46)
  call void @__inc_ref(ptr %t6)
  %t47 = call ptr @v__df_andThenIO_8(ptr %t6)
  call void @__inc_ref(ptr %t46)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t46)
  store ptr %t46, ptr %t3
  store ptr %t47, ptr %t4
  br label %tco.loop.0
tco.case.arm.88.48:
  %t49 = getelementptr ptr, ptr %t5, i32 1
  %t50 = load ptr, ptr %t49
  call void @__inc_ref(ptr %t50)
  call void @__inc_ref(ptr %t6)
  %t51 = call ptr @v__lift_12(ptr %t6)
  call void @__inc_ref(ptr %t50)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t50)
  store ptr %t50, ptr %t3
  store ptr %t51, ptr %t4
  br label %tco.loop.0
tco.case.arm.89.52:
  %t53 = getelementptr ptr, ptr %t5, i32 1
  %t54 = load ptr, ptr %t53
  call void @__inc_ref(ptr %t54)
  call void @__inc_ref(ptr %t6)
  %t55 = call ptr @v__lift_12(ptr %t6)
  call void @__inc_ref(ptr %t54)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t54)
  store ptr %t54, ptr %t3
  store ptr %t55, ptr %t4
  br label %tco.loop.0
tco.case.arm.90.56:
  %t57 = getelementptr ptr, ptr %t5, i32 1
  %t58 = load ptr, ptr %t57
  call void @__inc_ref(ptr %t58)
  call void @__inc_ref(ptr %t6)
  %t59 = call ptr @v__lift_16(ptr %t6)
  call void @__inc_ref(ptr %t58)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t58)
  store ptr %t58, ptr %t3
  store ptr %t59, ptr %t4
  br label %tco.loop.0
tco.case.arm.91.60:
  %t61 = getelementptr ptr, ptr %t5, i32 1
  %t62 = load ptr, ptr %t61
  call void @__inc_ref(ptr %t62)
  call void @__inc_ref(ptr %t6)
  %t63 = call ptr @v__lift_16(ptr %t6)
  call void @__inc_ref(ptr %t62)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t62)
  store ptr %t62, ptr %t3
  store ptr %t63, ptr %t4
  br label %tco.loop.0
tco.case.arm.92.64:
  %t65 = getelementptr ptr, ptr %t5, i32 1
  %t66 = load ptr, ptr %t65
  call void @__inc_ref(ptr %t66)
  call void @__inc_ref(ptr %t6)
  %t67 = call ptr @v__lift_1(ptr %t6)
  call void @__inc_ref(ptr %t66)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t66)
  store ptr %t66, ptr %t3
  store ptr %t67, ptr %t4
  br label %tco.loop.0
tco.case.arm.93.68:
  %t69 = getelementptr ptr, ptr %t5, i32 1
  %t70 = load ptr, ptr %t69
  call void @__inc_ref(ptr %t70)
  call void @__inc_ref(ptr %t6)
  %t71 = call ptr @v__lift_19(ptr %t6)
  call void @__inc_ref(ptr %t70)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t70)
  store ptr %t70, ptr %t3
  store ptr %t71, ptr %t4
  br label %tco.loop.0
tco.case.arm.94.72:
  %t73 = getelementptr ptr, ptr %t5, i32 1
  %t74 = load ptr, ptr %t73
  call void @__inc_ref(ptr %t74)
  call void @__inc_ref(ptr %t6)
  %t75 = call ptr @v__lift_19(ptr %t6)
  call void @__inc_ref(ptr %t74)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t74)
  store ptr %t74, ptr %t3
  store ptr %t75, ptr %t4
  br label %tco.loop.0
tco.case.arm.95.76:
  %t77 = getelementptr ptr, ptr %t5, i32 1
  %t78 = load ptr, ptr %t77
  call void @__inc_ref(ptr %t78)
  call void @__inc_ref(ptr %t6)
  %t79 = call ptr @v__lift_25(ptr %t6)
  call void @__inc_ref(ptr %t78)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t78)
  store ptr %t78, ptr %t3
  store ptr %t79, ptr %t4
  br label %tco.loop.0
tco.case.arm.96.80:
  %t81 = getelementptr ptr, ptr %t5, i32 1
  %t82 = load ptr, ptr %t81
  call void @__inc_ref(ptr %t82)
  call void @__inc_ref(ptr %t6)
  %t83 = call ptr @v__lift_25(ptr %t6)
  call void @__inc_ref(ptr %t82)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t82)
  store ptr %t82, ptr %t3
  store ptr %t83, ptr %t4
  br label %tco.loop.0
tco.case.arm.97.84:
  %t85 = getelementptr ptr, ptr %t5, i32 1
  %t86 = load ptr, ptr %t85
  call void @__inc_ref(ptr %t86)
  call void @__inc_ref(ptr %t6)
  %t87 = call ptr @v__lift_1(ptr %t6)
  call void @__inc_ref(ptr %t86)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t86)
  store ptr %t86, ptr %t3
  store ptr %t87, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t88 = load ptr, ptr %t2
  ret ptr %t88
}

define internal ptr @v__apply1(ptr %v__cl, ptr %v__arg0) {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 42 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  call void @__inc_ref(ptr %v__cl)
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v__cl, ptr %t3
  call void @__inc_ref(ptr %v__arg0)
  %t4 = getelementptr ptr, ptr %t0, i32 2
  store ptr %v__arg0, ptr %t4
  %t5 = call ptr @v__scc__apply1__df__lam_10_1__df__lam_11_2__df__lam_22_4__df__lam_23_5__df__lam_28_7__df__lam_29_11__df__lam_4_9__df__lam_5_10__lift_13__lift_14__lift_17__lift_18__lift_2__lift_20__lift_21__lift_26__lift_27__lift_3(ptr %t0)
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
