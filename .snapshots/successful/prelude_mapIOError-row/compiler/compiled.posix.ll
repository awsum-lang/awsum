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

define internal ptr @v_toRowA(ptr %v__s) {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 2252990199 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 8, i32 0)
  %t4 = inttoptr i64 25 to ptr
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
  %t4 = inttoptr i64 26 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  call void @__free_recursive(ptr %v__s)
  ret ptr %t0
}

define internal ptr @v_failSrc() {
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 22 to ptr
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
  %t1 = call ptr @v__df_mapIOError_3(ptr %t0)
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
  %t11 = inttoptr i64 26 to ptr
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
  %t21 = inttoptr i64 25 to ptr
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
  %t4 = inttoptr i64 23 to ptr
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
  %t4 = inttoptr i64 24 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  %t7 = call ptr @v_failIO(ptr %t0)
  ret ptr %t7
}

define internal ptr @v_remappedX() {
  %t0 = call ptr @v_failX()
  %t1 = call ptr @v__df_mapIOError_6(ptr %t0)
  ret ptr %t1
}

define internal ptr @v_remappedY() {
  %t0 = call ptr @v_failY()
  %t1 = call ptr @v__df_mapIOError_6(ptr %t0)
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
  %t0 = call ptr @v__df_mapIO_15(ptr %v_io)
  %t1 = call ptr @v__df__rowspec_15_12(ptr %t0)
  %t2 = call ptr @v__df_handleErrorIO_9(ptr %t1)
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
  %t0 = call ptr @v__df_mapIO_15(ptr %v_io)
  %t1 = call ptr @v__lift_28(ptr %t0)
  %t2 = call ptr @v__df__rowspec_24_21(ptr %t1)
  %t3 = call ptr @v__df_handleErrorIO_18(ptr %t2)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
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
  %t12 = call ptr @v__lift_36(ptr %t0)
  %t13 = call ptr @v__df_andThenIO_30(ptr %t12)
  call void @__inc_ref(ptr %v_act)
  %t14 = call ptr @v__df_andThenIO_27(ptr %t13, ptr %v_act)
  %t15 = call ptr @v__df_andThenIO_24(ptr %t14)
  call void @__free_recursive(ptr %v_label)
  call void @__free_recursive(ptr %v_act)
  ret ptr %t15
}

define internal ptr @v_main() {
  %t0 = call ptr @v_mappedA()
  %t1 = call ptr @v_observeAB(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_36(ptr %t2)
  %t4 = call ptr @v__df_andThenIO_42(ptr %t3)
  %t5 = call ptr @v__df_andThenIO_39(ptr %t4)
  %t6 = call ptr @v__df_andThenIO_36(ptr %t5)
  %t7 = call ptr @v__df_andThenIO_33(ptr %t6)
  ret ptr %t7
}

define internal ptr @v__lift_1(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 112 to ptr
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
  %t42 = inttoptr i64 113 to ptr
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
  %t45 = inttoptr i64 113 to ptr
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
  %t57 = inttoptr i64 59 to ptr
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
  %t69 = inttoptr i64 65 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 112, label %tco.case.arm.112.11 i64 113, label %tco.case.arm.113.12 ]
tco.case.arm.112.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.113.12:
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
  %t1 = inttoptr i64 114 to ptr
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
  %t46 = inttoptr i64 115 to ptr
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
  %t49 = inttoptr i64 115 to ptr
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
  %t61 = inttoptr i64 57 to ptr
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
  %t73 = inttoptr i64 58 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 114, label %tco.case.arm.114.11 i64 115, label %tco.case.arm.115.12 ]
tco.case.arm.114.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.115.12:
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
  %t1 = inttoptr i64 118 to ptr
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
  %t25 = call ptr @__alloc(i64 16, i32 1)
  %t26 = inttoptr i64 3801428867 to ptr
  %t27 = getelementptr ptr, ptr %t25, i32 0
  store ptr %t26, ptr %t27
  call void @__inc_ref(ptr %t21)
  %t28 = getelementptr ptr, ptr %t25, i32 1
  store ptr %t21, ptr %t28
  %t29 = getelementptr ptr, ptr %t22, i32 1
  store ptr %t25, ptr %t29
  %t30 = call ptr @v__apply__lift_25(ptr %t6, ptr %t22)
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
  %t46 = inttoptr i64 119 to ptr
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
  %t49 = inttoptr i64 119 to ptr
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
  %t61 = inttoptr i64 62 to ptr
  %t62 = getelementptr ptr, ptr %t60, i32 0
  store ptr %t61, ptr %t62
  call void @__inc_ref(ptr %t56)
  %t63 = getelementptr ptr, ptr %t60, i32 1
  store ptr %t56, ptr %t63
  %t64 = getelementptr ptr, ptr %t57, i32 1
  store ptr %t60, ptr %t64
  %t65 = call ptr @v__apply__lift_25(ptr %t6, ptr %t57)
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
  %t73 = inttoptr i64 63 to ptr
  %t74 = getelementptr ptr, ptr %t72, i32 0
  store ptr %t73, ptr %t74
  call void @__inc_ref(ptr %t68)
  %t75 = getelementptr ptr, ptr %t72, i32 1
  store ptr %t68, ptr %t75
  %t76 = getelementptr ptr, ptr %t69, i32 1
  store ptr %t72, ptr %t76
  %t77 = call ptr @v__apply__lift_25(ptr %t6, ptr %t69)
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
  switch i64 %t9, label %tco.case.default.10 [ i64 118, label %tco.case.arm.118.11 i64 119, label %tco.case.arm.119.12 ]
tco.case.arm.118.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.119.12:
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

define internal ptr @v__lift_28(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 120 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__lift_28(ptr %v___input, ptr %t0)
  call void @__free_recursive(ptr %v___input)
  ret ptr %t3
}

define internal ptr @v__cps__lift_28(ptr %v___input, ptr %v__k) {
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
  %t18 = call ptr @v__apply__lift_28(ptr %t6, ptr %t14)
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
  %t26 = call ptr @v__apply__lift_28(ptr %t6, ptr %t22)
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
  %t42 = inttoptr i64 121 to ptr
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
  %t45 = inttoptr i64 121 to ptr
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
  %t57 = inttoptr i64 64 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  call void @__inc_ref(ptr %t52)
  %t59 = getelementptr ptr, ptr %t56, i32 1
  store ptr %t52, ptr %t59
  %t60 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t56, ptr %t60
  %t61 = call ptr @v__apply__lift_28(ptr %t6, ptr %t53)
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
  %t69 = inttoptr i64 66 to ptr
  %t70 = getelementptr ptr, ptr %t68, i32 0
  store ptr %t69, ptr %t70
  call void @__inc_ref(ptr %t64)
  %t71 = getelementptr ptr, ptr %t68, i32 1
  store ptr %t64, ptr %t71
  %t72 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t68, ptr %t72
  %t73 = call ptr @v__apply__lift_28(ptr %t6, ptr %t65)
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

define internal ptr @v__apply__lift_28(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__lam_33(ptr %v__u) {
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

define internal ptr @v__lam_34(ptr %v_act, ptr %v__u) {
  call void @__free_recursive(ptr %v__u)
  ret ptr %v_act
}

define internal ptr @v__lam_35(ptr %v__u) {
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

define internal ptr @v__lift_36(ptr %v___input) {
  call void @__inc_ref(ptr %v___input)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 122 to ptr
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
  call void @__inc_ref(ptr %t21)
  %t25 = getelementptr ptr, ptr %t22, i32 1
  store ptr %t21, ptr %t25
  %t26 = call ptr @v__apply__lift_36(ptr %t6, ptr %t22)
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
  %t42 = inttoptr i64 123 to ptr
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
  %t45 = inttoptr i64 123 to ptr
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
  %t57 = inttoptr i64 67 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  call void @__inc_ref(ptr %t52)
  %t59 = getelementptr ptr, ptr %t56, i32 1
  store ptr %t52, ptr %t59
  %t60 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t56, ptr %t60
  %t61 = call ptr @v__apply__lift_36(ptr %t6, ptr %t53)
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
  %t69 = inttoptr i64 68 to ptr
  %t70 = getelementptr ptr, ptr %t68, i32 0
  store ptr %t69, ptr %t70
  call void @__inc_ref(ptr %t64)
  %t71 = getelementptr ptr, ptr %t68, i32 1
  store ptr %t64, ptr %t71
  %t72 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t68, ptr %t72
  %t73 = call ptr @v__apply__lift_36(ptr %t6, ptr %t65)
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

define internal ptr @v__lam_39(ptr %v__u) {
  %t0 = call ptr @v_remappedY()
  %t1 = call ptr @v_observeABC(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.5, i64 12), ptr %t1)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t2
}

define internal ptr @v__lam_40(ptr %v__u) {
  %t0 = call ptr @v_remappedX()
  %t1 = call ptr @v_observeABC(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.6, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_36(ptr %t2)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t3
}

define internal ptr @v__lam_41(ptr %v__u) {
  %t0 = call ptr @v_mappedOk()
  %t1 = call ptr @v_observeAB(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.7, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_36(ptr %t2)
  call void @__free_recursive(ptr %v__u)
  ret ptr %t3
}

define internal ptr @v__lam_42(ptr %v__u) {
  %t0 = call ptr @v_mappedB()
  %t1 = call ptr @v_observeAB(ptr %t0)
  %t2 = call ptr @v_line(ptr getelementptr inbounds (i8, ptr @.str.8, i64 12), ptr %t1)
  %t3 = call ptr @v__lift_36(ptr %t2)
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

define internal ptr @v__df_mapIOError_0(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 124 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.19 i64 7, label %tco.case.arm.7.28 i64 8, label %tco.case.arm.8.51 i64 9, label %tco.case.arm.9.63 ]
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
  %t58 = inttoptr i64 51 to ptr
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
  %t70 = inttoptr i64 54 to ptr
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
tco.case.default.10:
  unreachable
tco.exit.1:
  %t75 = load ptr, ptr %t2
  ret ptr %t75
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

define internal ptr @v__df_mapIOError_3(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 126 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_mapIOError_3(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_mapIOError_3(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.19 i64 7, label %tco.case.arm.7.28 i64 8, label %tco.case.arm.8.51 i64 9, label %tco.case.arm.9.63 ]
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
  %t18 = call ptr @v__apply__df_mapIOError_3(ptr %t6, ptr %t14)
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
  %t27 = call ptr @v__apply__df_mapIOError_3(ptr %t6, ptr %t22)
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
  %t43 = inttoptr i64 127 to ptr
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
  %t46 = inttoptr i64 127 to ptr
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
  %t58 = inttoptr i64 52 to ptr
  %t59 = getelementptr ptr, ptr %t57, i32 0
  store ptr %t58, ptr %t59
  call void @__inc_ref(ptr %t53)
  %t60 = getelementptr ptr, ptr %t57, i32 1
  store ptr %t53, ptr %t60
  %t61 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t57, ptr %t61
  %t62 = call ptr @v__apply__df_mapIOError_3(ptr %t6, ptr %t54)
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
  %t70 = inttoptr i64 55 to ptr
  %t71 = getelementptr ptr, ptr %t69, i32 0
  store ptr %t70, ptr %t71
  call void @__inc_ref(ptr %t65)
  %t72 = getelementptr ptr, ptr %t69, i32 1
  store ptr %t65, ptr %t72
  %t73 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t69, ptr %t73
  %t74 = call ptr @v__apply__df_mapIOError_3(ptr %t6, ptr %t66)
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

define internal ptr @v__apply__df_mapIOError_3(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__df_mapIOError_6(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 128 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_mapIOError_6(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_mapIOError_6(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.19 i64 7, label %tco.case.arm.7.28 i64 8, label %tco.case.arm.8.51 i64 9, label %tco.case.arm.9.63 ]
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
  %t18 = call ptr @v__apply__df_mapIOError_6(ptr %t6, ptr %t14)
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
  %t27 = call ptr @v__apply__df_mapIOError_6(ptr %t6, ptr %t22)
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
  %t43 = inttoptr i64 129 to ptr
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
  %t46 = inttoptr i64 129 to ptr
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
  %t58 = inttoptr i64 53 to ptr
  %t59 = getelementptr ptr, ptr %t57, i32 0
  store ptr %t58, ptr %t59
  call void @__inc_ref(ptr %t53)
  %t60 = getelementptr ptr, ptr %t57, i32 1
  store ptr %t53, ptr %t60
  %t61 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t57, ptr %t61
  %t62 = call ptr @v__apply__df_mapIOError_6(ptr %t6, ptr %t54)
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
  %t70 = inttoptr i64 56 to ptr
  %t71 = getelementptr ptr, ptr %t69, i32 0
  store ptr %t70, ptr %t71
  call void @__inc_ref(ptr %t65)
  %t72 = getelementptr ptr, ptr %t69, i32 1
  store ptr %t65, ptr %t72
  %t73 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t69, ptr %t73
  %t74 = call ptr @v__apply__df_mapIOError_6(ptr %t6, ptr %t66)
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

define internal ptr @v__apply__df_mapIOError_6(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__df_handleErrorIO_9(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 130 to ptr
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
  %t22 = call ptr @v_handlerAB(ptr %t21)
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
  %t39 = inttoptr i64 131 to ptr
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
  %t42 = inttoptr i64 131 to ptr
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
  %t66 = inttoptr i64 29 to ptr
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

define internal ptr @v__df__rowspec_15_12(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 132 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df__rowspec_15_12(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df__rowspec_15_12(ptr %v_io, ptr %v__k) {
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
  %t16 = call ptr @v__apply__df__rowspec_15_12(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df__rowspec_15_12(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 133 to ptr
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
  %t43 = inttoptr i64 133 to ptr
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
  %t55 = inttoptr i64 31 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df__rowspec_15_12(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 32 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df__rowspec_15_12(ptr %t6, ptr %t63)
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

define internal ptr @v__apply__df__rowspec_15_12(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__df_mapIO_15(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 134 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_mapIO_15(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_mapIO_15(ptr %v_io, ptr %v__k) {
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
  %t19 = call ptr @v__apply__df_mapIO_15(ptr %t6, ptr %t14)
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
  %t27 = call ptr @v__apply__df_mapIO_15(ptr %t6, ptr %t23)
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
  %t43 = inttoptr i64 135 to ptr
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
  %t46 = inttoptr i64 135 to ptr
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
  %t58 = inttoptr i64 49 to ptr
  %t59 = getelementptr ptr, ptr %t57, i32 0
  store ptr %t58, ptr %t59
  call void @__inc_ref(ptr %t53)
  %t60 = getelementptr ptr, ptr %t57, i32 1
  store ptr %t53, ptr %t60
  %t61 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t57, ptr %t61
  %t62 = call ptr @v__apply__df_mapIO_15(ptr %t6, ptr %t54)
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
  %t70 = inttoptr i64 50 to ptr
  %t71 = getelementptr ptr, ptr %t69, i32 0
  store ptr %t70, ptr %t71
  call void @__inc_ref(ptr %t65)
  %t72 = getelementptr ptr, ptr %t69, i32 1
  store ptr %t65, ptr %t72
  %t73 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t69, ptr %t73
  %t74 = call ptr @v__apply__df_mapIO_15(ptr %t6, ptr %t66)
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

define internal ptr @v__apply__df_mapIO_15(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__df_handleErrorIO_18(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 136 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_handleErrorIO_18(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_handleErrorIO_18(ptr %v_io, ptr %v__k) {
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
  %t18 = call ptr @v__apply__df_handleErrorIO_18(ptr %t6, ptr %t14)
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
  %t23 = call ptr @v__apply__df_handleErrorIO_18(ptr %t6, ptr %t22)
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
  %t54 = inttoptr i64 28 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  call void @__inc_ref(ptr %t49)
  %t56 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t49, ptr %t56
  %t57 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t53, ptr %t57
  %t58 = call ptr @v__apply__df_handleErrorIO_18(ptr %t6, ptr %t50)
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
  %t70 = call ptr @v__apply__df_handleErrorIO_18(ptr %t6, ptr %t62)
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

define internal ptr @v__apply__df_handleErrorIO_18(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__df__rowspec_24_21(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 138 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df__rowspec_24_21(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df__rowspec_24_21(ptr %v_io, ptr %v__k) {
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
  %t15 = call ptr @v__lift_25(ptr %t14)
  %t16 = call ptr @v__apply__df__rowspec_24_21(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df__rowspec_24_21(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 139 to ptr
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
  %t43 = inttoptr i64 139 to ptr
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
  %t55 = inttoptr i64 33 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df__rowspec_24_21(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 34 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df__rowspec_24_21(ptr %t6, ptr %t63)
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

define internal ptr @v__apply__df__rowspec_24_21(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__df_andThenIO_24(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 140 to ptr
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
  %t14 = call ptr @v__lam_33(ptr %t13)
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
  %t40 = inttoptr i64 141 to ptr
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
  %t43 = inttoptr i64 141 to ptr
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
  %t55 = inttoptr i64 35 to ptr
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
  %t67 = inttoptr i64 42 to ptr
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

define internal ptr @v__df_andThenIO_27(ptr %v_io, ptr %v__df_andThenIO_27_cap0_0) {
  call void @__inc_ref(ptr %v_io)
  call void @__inc_ref(ptr %v__df_andThenIO_27_cap0_0)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 142 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_27(ptr %v_io, ptr %v__df_andThenIO_27_cap0_0, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  call void @__free_recursive(ptr %v__df_andThenIO_27_cap0_0)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_27(ptr %v_io, ptr %v__df_andThenIO_27_cap0_0, ptr %v__k) {
entry:
  %t3 = alloca ptr
  store ptr %v_io, ptr %t3
  %t4 = alloca ptr
  store ptr %v__df_andThenIO_27_cap0_0, ptr %t4
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
  %t16 = call ptr @v__lam_34(ptr %t7, ptr %t15)
  %t17 = call ptr @v__lift_1(ptr %t16)
  %t18 = call ptr @v__apply__df_andThenIO_27(ptr %t8, ptr %t17)
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
  %t26 = call ptr @v__apply__df_andThenIO_27(ptr %t8, ptr %t22)
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
  %t42 = inttoptr i64 143 to ptr
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
  %t45 = inttoptr i64 143 to ptr
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
  %t57 = inttoptr i64 36 to ptr
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
  %t62 = call ptr @v__apply__df_andThenIO_27(ptr %t8, ptr %t53)
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
  %t70 = inttoptr i64 43 to ptr
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
  %t75 = call ptr @v__apply__df_andThenIO_27(ptr %t8, ptr %t66)
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

define internal ptr @v__apply__df_andThenIO_27(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__df_andThenIO_30(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 144 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_30(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_30(ptr %v_io, ptr %v__k) {
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
  %t16 = call ptr @v__apply__df_andThenIO_30(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_30(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 145 to ptr
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
  %t43 = inttoptr i64 145 to ptr
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
  %t55 = inttoptr i64 37 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df_andThenIO_30(ptr %t6, ptr %t51)
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
  %t71 = call ptr @v__apply__df_andThenIO_30(ptr %t6, ptr %t63)
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

define internal ptr @v__apply__df_andThenIO_30(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__df_andThenIO_33(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 146 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_33(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_33(ptr %v_io, ptr %v__k) {
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
  %t16 = call ptr @v__apply__df_andThenIO_33(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_33(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 147 to ptr
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
  %t43 = inttoptr i64 147 to ptr
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
  %t55 = inttoptr i64 38 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df_andThenIO_33(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 45 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df_andThenIO_33(ptr %t6, ptr %t63)
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

define internal ptr @v__apply__df_andThenIO_33(ptr %v__k, ptr %v__x) {
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

define internal ptr @v__df_andThenIO_36(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 148 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_36(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_36(ptr %v_io, ptr %v__k) {
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
  %t16 = call ptr @v__apply__df_andThenIO_36(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_36(ptr %t6, ptr %t20)
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
  %t40 = inttoptr i64 149 to ptr
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
  %t43 = inttoptr i64 149 to ptr
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
  %t55 = inttoptr i64 39 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df_andThenIO_36(ptr %t6, ptr %t51)
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
  %t71 = call ptr @v__apply__df_andThenIO_36(ptr %t6, ptr %t63)
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

define internal ptr @v__df_andThenIO_39(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 150 to ptr
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
  %t14 = call ptr @v__lam_41(ptr %t13)
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
  %t40 = inttoptr i64 151 to ptr
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
  %t43 = inttoptr i64 151 to ptr
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
  %t67 = inttoptr i64 47 to ptr
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

define internal ptr @v__df_andThenIO_42(ptr %v_io) {
  call void @__inc_ref(ptr %v_io)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 152 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__df_andThenIO_42(ptr %v_io, ptr %t0)
  call void @__free_recursive(ptr %v_io)
  ret ptr %t3
}

define internal ptr @v__cps__df_andThenIO_42(ptr %v_io, ptr %v__k) {
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
  %t14 = call ptr @v__lam_42(ptr %t13)
  %t15 = call ptr @v__lift_1(ptr %t14)
  %t16 = call ptr @v__apply__df_andThenIO_42(ptr %t6, ptr %t15)
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
  %t24 = call ptr @v__apply__df_andThenIO_42(ptr %t6, ptr %t20)
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
  %t55 = inttoptr i64 41 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t50)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t50, ptr %t57
  %t58 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @v__apply__df_andThenIO_42(ptr %t6, ptr %t51)
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
  %t67 = inttoptr i64 48 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t62)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t62, ptr %t69
  %t70 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t66, ptr %t70
  %t71 = call ptr @v__apply__df_andThenIO_42(ptr %t6, ptr %t63)
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

define internal ptr @v__scc__apply1__df__lam_10_10__df__lam_10_19__df__lam_11_11__df__lam_11_20__df__lam_22_13__df__lam_23_14__df__lam_31_22__df__lam_32_23__df__lam_4_25__df__lam_4_28__df__lam_4_31__df__lam_4_34__df__lam_4_37__df__lam_4_40__df__lam_4_43__df__lam_5_26__df__lam_5_29__df__lam_5_32__df__lam_5_35__df__lam_5_38__df__lam_5_41__df__lam_5_44__df__lam_6_16__df__lam_7_17__df__lam_8_1__df__lam_8_4__df__lam_8_7__df__lam_9_2__df__lam_9_5__df__lam_9_8__lift_17__lift_18__lift_2__lift_20__lift_21__lift_26__lift_27__lift_29__lift_3__lift_30__lift_37__lift_38(ptr %v__args) {
  call void @__inc_ref(ptr %v__args)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 154 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__scc__apply1__df__lam_10_10__df__lam_10_19__df__lam_11_11__df__lam_11_20__df__lam_22_13__df__lam_23_14__df__lam_31_22__df__lam_32_23__df__lam_4_25__df__lam_4_28__df__lam_4_31__df__lam_4_34__df__lam_4_37__df__lam_4_40__df__lam_4_43__df__lam_5_26__df__lam_5_29__df__lam_5_32__df__lam_5_35__df__lam_5_38__df__lam_5_41__df__lam_5_44__df__lam_6_16__df__lam_7_17__df__lam_8_1__df__lam_8_4__df__lam_8_7__df__lam_9_2__df__lam_9_5__df__lam_9_8__lift_17__lift_18__lift_2__lift_20__lift_21__lift_26__lift_27__lift_29__lift_3__lift_30__lift_37__lift_38(ptr %v__args, ptr %t0)
  call void @__free_recursive(ptr %v__args)
  ret ptr %t3
}

define internal ptr @v__cps__scc__apply1__df__lam_10_10__df__lam_10_19__df__lam_11_11__df__lam_11_20__df__lam_22_13__df__lam_23_14__df__lam_31_22__df__lam_32_23__df__lam_4_25__df__lam_4_28__df__lam_4_31__df__lam_4_34__df__lam_4_37__df__lam_4_40__df__lam_4_43__df__lam_5_26__df__lam_5_29__df__lam_5_32__df__lam_5_35__df__lam_5_38__df__lam_5_41__df__lam_5_44__df__lam_6_16__df__lam_7_17__df__lam_8_1__df__lam_8_4__df__lam_8_7__df__lam_9_2__df__lam_9_5__df__lam_9_8__lift_17__lift_18__lift_2__lift_20__lift_21__lift_26__lift_27__lift_29__lift_3__lift_30__lift_37__lift_38(ptr %v__args, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 69, label %tco.case.arm.69.11 i64 70, label %tco.case.arm.70.802 i64 71, label %tco.case.arm.71.825 i64 72, label %tco.case.arm.72.848 i64 73, label %tco.case.arm.73.871 i64 74, label %tco.case.arm.74.894 i64 75, label %tco.case.arm.75.917 i64 76, label %tco.case.arm.76.940 i64 77, label %tco.case.arm.77.963 i64 78, label %tco.case.arm.78.986 i64 79, label %tco.case.arm.79.1009 i64 80, label %tco.case.arm.80.1026 i64 81, label %tco.case.arm.81.1049 i64 82, label %tco.case.arm.82.1072 i64 83, label %tco.case.arm.83.1095 i64 84, label %tco.case.arm.84.1118 i64 85, label %tco.case.arm.85.1141 i64 86, label %tco.case.arm.86.1164 i64 87, label %tco.case.arm.87.1181 i64 88, label %tco.case.arm.88.1204 i64 89, label %tco.case.arm.89.1227 i64 90, label %tco.case.arm.90.1250 i64 91, label %tco.case.arm.91.1273 i64 92, label %tco.case.arm.92.1296 i64 93, label %tco.case.arm.93.1319 i64 94, label %tco.case.arm.94.1342 i64 95, label %tco.case.arm.95.1365 i64 96, label %tco.case.arm.96.1388 i64 97, label %tco.case.arm.97.1411 i64 98, label %tco.case.arm.98.1434 i64 99, label %tco.case.arm.99.1457 i64 100, label %tco.case.arm.100.1480 i64 101, label %tco.case.arm.101.1503 i64 102, label %tco.case.arm.102.1526 i64 105, label %tco.case.arm.105.1549 i64 106, label %tco.case.arm.106.1572 i64 107, label %tco.case.arm.107.1595 i64 108, label %tco.case.arm.108.1618 i64 109, label %tco.case.arm.109.1641 i64 110, label %tco.case.arm.110.1664 i64 111, label %tco.case.arm.111.1687 ]
tco.case.arm.69.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t5, i32 2
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  %t16 = getelementptr ptr, ptr %t13, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %tco.case.default.19 [ i64 27, label %tco.case.arm.27.20 i64 28, label %tco.case.arm.28.40 i64 29, label %tco.case.arm.29.60 i64 30, label %tco.case.arm.30.80 i64 31, label %tco.case.arm.31.100 i64 32, label %tco.case.arm.32.120 i64 33, label %tco.case.arm.33.140 i64 34, label %tco.case.arm.34.160 i64 35, label %tco.case.arm.35.180 i64 36, label %tco.case.arm.36.200 i64 37, label %tco.case.arm.37.211 i64 38, label %tco.case.arm.38.231 i64 39, label %tco.case.arm.39.251 i64 40, label %tco.case.arm.40.271 i64 41, label %tco.case.arm.41.291 i64 42, label %tco.case.arm.42.311 i64 43, label %tco.case.arm.43.331 i64 44, label %tco.case.arm.44.342 i64 45, label %tco.case.arm.45.362 i64 46, label %tco.case.arm.46.382 i64 47, label %tco.case.arm.47.402 i64 48, label %tco.case.arm.48.422 i64 49, label %tco.case.arm.49.442 i64 50, label %tco.case.arm.50.462 i64 51, label %tco.case.arm.51.482 i64 52, label %tco.case.arm.52.502 i64 53, label %tco.case.arm.53.522 i64 54, label %tco.case.arm.54.542 i64 55, label %tco.case.arm.55.562 i64 56, label %tco.case.arm.56.582 i64 57, label %tco.case.arm.57.602 i64 58, label %tco.case.arm.58.622 i64 59, label %tco.case.arm.59.642 i64 62, label %tco.case.arm.62.662 i64 63, label %tco.case.arm.63.682 i64 64, label %tco.case.arm.64.702 i64 65, label %tco.case.arm.65.722 i64 66, label %tco.case.arm.66.742 i64 67, label %tco.case.arm.67.762 i64 68, label %tco.case.arm.68.782 ]
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
  %t32 = inttoptr i64 70 to ptr
  %t33 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t32, ptr %t33
  call void @__inc_ref(ptr %t22)
  %t31 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t22, ptr %t31
  br label %reuse.join.28
reuse.copy.27:
  %t34 = call ptr @__alloc(i64 24, i32 2)
  %t35 = inttoptr i64 70 to ptr
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
  %t52 = inttoptr i64 71 to ptr
  %t53 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t52, ptr %t53
  call void @__inc_ref(ptr %t42)
  %t51 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t42, ptr %t51
  br label %reuse.join.48
reuse.copy.47:
  %t54 = call ptr @__alloc(i64 24, i32 2)
  %t55 = inttoptr i64 71 to ptr
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
  %t72 = inttoptr i64 72 to ptr
  %t73 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t72, ptr %t73
  call void @__inc_ref(ptr %t62)
  %t71 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t62, ptr %t71
  br label %reuse.join.68
reuse.copy.67:
  %t74 = call ptr @__alloc(i64 24, i32 2)
  %t75 = inttoptr i64 72 to ptr
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
  %t92 = inttoptr i64 73 to ptr
  %t93 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t92, ptr %t93
  call void @__inc_ref(ptr %t82)
  %t91 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t82, ptr %t91
  br label %reuse.join.88
reuse.copy.87:
  %t94 = call ptr @__alloc(i64 24, i32 2)
  %t95 = inttoptr i64 73 to ptr
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
  %t112 = inttoptr i64 74 to ptr
  %t113 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t112, ptr %t113
  call void @__inc_ref(ptr %t102)
  %t111 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t102, ptr %t111
  br label %reuse.join.108
reuse.copy.107:
  %t114 = call ptr @__alloc(i64 24, i32 2)
  %t115 = inttoptr i64 74 to ptr
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
  %t132 = inttoptr i64 75 to ptr
  %t133 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t132, ptr %t133
  call void @__inc_ref(ptr %t122)
  %t131 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t122, ptr %t131
  br label %reuse.join.128
reuse.copy.127:
  %t134 = call ptr @__alloc(i64 24, i32 2)
  %t135 = inttoptr i64 75 to ptr
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
  %t152 = inttoptr i64 76 to ptr
  %t153 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t152, ptr %t153
  call void @__inc_ref(ptr %t142)
  %t151 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t142, ptr %t151
  br label %reuse.join.148
reuse.copy.147:
  %t154 = call ptr @__alloc(i64 24, i32 2)
  %t155 = inttoptr i64 76 to ptr
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
  %t172 = inttoptr i64 77 to ptr
  %t173 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t172, ptr %t173
  call void @__inc_ref(ptr %t162)
  %t171 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t162, ptr %t171
  br label %reuse.join.168
reuse.copy.167:
  %t174 = call ptr @__alloc(i64 24, i32 2)
  %t175 = inttoptr i64 77 to ptr
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
  %t192 = inttoptr i64 78 to ptr
  %t193 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t192, ptr %t193
  call void @__inc_ref(ptr %t182)
  %t191 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t182, ptr %t191
  br label %reuse.join.188
reuse.copy.187:
  %t194 = call ptr @__alloc(i64 24, i32 2)
  %t195 = inttoptr i64 78 to ptr
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
  %t203 = getelementptr ptr, ptr %t13, i32 2
  %t204 = load ptr, ptr %t203
  call void @__inc_ref(ptr %t204)
  %t205 = call ptr @__alloc(i64 32, i32 3)
  %t206 = inttoptr i64 79 to ptr
  %t207 = getelementptr ptr, ptr %t205, i32 0
  store ptr %t206, ptr %t207
  call void @__inc_ref(ptr %t202)
  %t208 = getelementptr ptr, ptr %t205, i32 1
  store ptr %t202, ptr %t208
  call void @__inc_ref(ptr %t204)
  %t209 = getelementptr ptr, ptr %t205, i32 2
  store ptr %t204, ptr %t209
  call void @__inc_ref(ptr %t15)
  %t210 = getelementptr ptr, ptr %t205, i32 3
  store ptr %t15, ptr %t210
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t204)
  call void @__free_recursive(ptr %t202)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t205, ptr %t3
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
  %t223 = inttoptr i64 80 to ptr
  %t224 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t223, ptr %t224
  call void @__inc_ref(ptr %t213)
  %t222 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t213, ptr %t222
  br label %reuse.join.219
reuse.copy.218:
  %t225 = call ptr @__alloc(i64 24, i32 2)
  %t226 = inttoptr i64 80 to ptr
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
  %t243 = inttoptr i64 81 to ptr
  %t244 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t243, ptr %t244
  call void @__inc_ref(ptr %t233)
  %t242 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t233, ptr %t242
  br label %reuse.join.239
reuse.copy.238:
  %t245 = call ptr @__alloc(i64 24, i32 2)
  %t246 = inttoptr i64 81 to ptr
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
  %t263 = inttoptr i64 82 to ptr
  %t264 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t263, ptr %t264
  call void @__inc_ref(ptr %t253)
  %t262 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t253, ptr %t262
  br label %reuse.join.259
reuse.copy.258:
  %t265 = call ptr @__alloc(i64 24, i32 2)
  %t266 = inttoptr i64 82 to ptr
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
  %t283 = inttoptr i64 83 to ptr
  %t284 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t283, ptr %t284
  call void @__inc_ref(ptr %t273)
  %t282 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t273, ptr %t282
  br label %reuse.join.279
reuse.copy.278:
  %t285 = call ptr @__alloc(i64 24, i32 2)
  %t286 = inttoptr i64 83 to ptr
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
  %t303 = inttoptr i64 84 to ptr
  %t304 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t303, ptr %t304
  call void @__inc_ref(ptr %t293)
  %t302 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t293, ptr %t302
  br label %reuse.join.299
reuse.copy.298:
  %t305 = call ptr @__alloc(i64 24, i32 2)
  %t306 = inttoptr i64 84 to ptr
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
  %t323 = inttoptr i64 85 to ptr
  %t324 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t323, ptr %t324
  call void @__inc_ref(ptr %t313)
  %t322 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t313, ptr %t322
  br label %reuse.join.319
reuse.copy.318:
  %t325 = call ptr @__alloc(i64 24, i32 2)
  %t326 = inttoptr i64 85 to ptr
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
  %t337 = inttoptr i64 86 to ptr
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
  %t354 = inttoptr i64 87 to ptr
  %t355 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t354, ptr %t355
  call void @__inc_ref(ptr %t344)
  %t353 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t344, ptr %t353
  br label %reuse.join.350
reuse.copy.349:
  %t356 = call ptr @__alloc(i64 24, i32 2)
  %t357 = inttoptr i64 87 to ptr
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
  %t374 = inttoptr i64 88 to ptr
  %t375 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t374, ptr %t375
  call void @__inc_ref(ptr %t364)
  %t373 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t364, ptr %t373
  br label %reuse.join.370
reuse.copy.369:
  %t376 = call ptr @__alloc(i64 24, i32 2)
  %t377 = inttoptr i64 88 to ptr
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
  %t394 = inttoptr i64 89 to ptr
  %t395 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t394, ptr %t395
  call void @__inc_ref(ptr %t384)
  %t393 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t384, ptr %t393
  br label %reuse.join.390
reuse.copy.389:
  %t396 = call ptr @__alloc(i64 24, i32 2)
  %t397 = inttoptr i64 89 to ptr
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
  %t414 = inttoptr i64 90 to ptr
  %t415 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t414, ptr %t415
  call void @__inc_ref(ptr %t404)
  %t413 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t404, ptr %t413
  br label %reuse.join.410
reuse.copy.409:
  %t416 = call ptr @__alloc(i64 24, i32 2)
  %t417 = inttoptr i64 90 to ptr
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
  %t434 = inttoptr i64 91 to ptr
  %t435 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t434, ptr %t435
  call void @__inc_ref(ptr %t424)
  %t433 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t424, ptr %t433
  br label %reuse.join.430
reuse.copy.429:
  %t436 = call ptr @__alloc(i64 24, i32 2)
  %t437 = inttoptr i64 91 to ptr
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
  %t454 = inttoptr i64 92 to ptr
  %t455 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t454, ptr %t455
  call void @__inc_ref(ptr %t444)
  %t453 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t444, ptr %t453
  br label %reuse.join.450
reuse.copy.449:
  %t456 = call ptr @__alloc(i64 24, i32 2)
  %t457 = inttoptr i64 92 to ptr
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
  %t474 = inttoptr i64 93 to ptr
  %t475 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t474, ptr %t475
  call void @__inc_ref(ptr %t464)
  %t473 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t464, ptr %t473
  br label %reuse.join.470
reuse.copy.469:
  %t476 = call ptr @__alloc(i64 24, i32 2)
  %t477 = inttoptr i64 93 to ptr
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
  %t494 = inttoptr i64 94 to ptr
  %t495 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t494, ptr %t495
  call void @__inc_ref(ptr %t484)
  %t493 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t484, ptr %t493
  br label %reuse.join.490
reuse.copy.489:
  %t496 = call ptr @__alloc(i64 24, i32 2)
  %t497 = inttoptr i64 94 to ptr
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
  %t514 = inttoptr i64 95 to ptr
  %t515 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t514, ptr %t515
  call void @__inc_ref(ptr %t504)
  %t513 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t504, ptr %t513
  br label %reuse.join.510
reuse.copy.509:
  %t516 = call ptr @__alloc(i64 24, i32 2)
  %t517 = inttoptr i64 95 to ptr
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
  %t534 = inttoptr i64 96 to ptr
  %t535 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t534, ptr %t535
  call void @__inc_ref(ptr %t524)
  %t533 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t524, ptr %t533
  br label %reuse.join.530
reuse.copy.529:
  %t536 = call ptr @__alloc(i64 24, i32 2)
  %t537 = inttoptr i64 96 to ptr
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
  %t554 = inttoptr i64 97 to ptr
  %t555 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t554, ptr %t555
  call void @__inc_ref(ptr %t544)
  %t553 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t544, ptr %t553
  br label %reuse.join.550
reuse.copy.549:
  %t556 = call ptr @__alloc(i64 24, i32 2)
  %t557 = inttoptr i64 97 to ptr
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
  %t574 = inttoptr i64 98 to ptr
  %t575 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t574, ptr %t575
  call void @__inc_ref(ptr %t564)
  %t573 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t564, ptr %t573
  br label %reuse.join.570
reuse.copy.569:
  %t576 = call ptr @__alloc(i64 24, i32 2)
  %t577 = inttoptr i64 98 to ptr
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
  %t594 = inttoptr i64 99 to ptr
  %t595 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t594, ptr %t595
  call void @__inc_ref(ptr %t584)
  %t593 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t584, ptr %t593
  br label %reuse.join.590
reuse.copy.589:
  %t596 = call ptr @__alloc(i64 24, i32 2)
  %t597 = inttoptr i64 99 to ptr
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
  %t614 = inttoptr i64 100 to ptr
  %t615 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t614, ptr %t615
  call void @__inc_ref(ptr %t604)
  %t613 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t604, ptr %t613
  br label %reuse.join.610
reuse.copy.609:
  %t616 = call ptr @__alloc(i64 24, i32 2)
  %t617 = inttoptr i64 100 to ptr
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
  %t634 = inttoptr i64 101 to ptr
  %t635 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t634, ptr %t635
  call void @__inc_ref(ptr %t624)
  %t633 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t624, ptr %t633
  br label %reuse.join.630
reuse.copy.629:
  %t636 = call ptr @__alloc(i64 24, i32 2)
  %t637 = inttoptr i64 101 to ptr
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
  %t654 = inttoptr i64 102 to ptr
  %t655 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t654, ptr %t655
  call void @__inc_ref(ptr %t644)
  %t653 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t644, ptr %t653
  br label %reuse.join.650
reuse.copy.649:
  %t656 = call ptr @__alloc(i64 24, i32 2)
  %t657 = inttoptr i64 102 to ptr
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
  %t674 = inttoptr i64 105 to ptr
  %t675 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t674, ptr %t675
  call void @__inc_ref(ptr %t664)
  %t673 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t664, ptr %t673
  br label %reuse.join.670
reuse.copy.669:
  %t676 = call ptr @__alloc(i64 24, i32 2)
  %t677 = inttoptr i64 105 to ptr
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
  %t694 = inttoptr i64 106 to ptr
  %t695 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t694, ptr %t695
  call void @__inc_ref(ptr %t684)
  %t693 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t684, ptr %t693
  br label %reuse.join.690
reuse.copy.689:
  %t696 = call ptr @__alloc(i64 24, i32 2)
  %t697 = inttoptr i64 106 to ptr
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
  %t714 = inttoptr i64 107 to ptr
  %t715 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t714, ptr %t715
  call void @__inc_ref(ptr %t704)
  %t713 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t704, ptr %t713
  br label %reuse.join.710
reuse.copy.709:
  %t716 = call ptr @__alloc(i64 24, i32 2)
  %t717 = inttoptr i64 107 to ptr
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
  %t734 = inttoptr i64 108 to ptr
  %t735 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t734, ptr %t735
  call void @__inc_ref(ptr %t724)
  %t733 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t724, ptr %t733
  br label %reuse.join.730
reuse.copy.729:
  %t736 = call ptr @__alloc(i64 24, i32 2)
  %t737 = inttoptr i64 108 to ptr
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
  %t745 = getelementptr i8, ptr %t5, i64 -8
  %t746 = load i32, ptr %t745
  %t747 = icmp eq i32 %t746, 1
  br i1 %t747, label %reuse.in_place.748, label %reuse.copy.749
reuse.in_place.748:
  %t751 = getelementptr ptr, ptr %t5, i32 1
  %t752 = load ptr, ptr %t751
  call void @__free_recursive(ptr %t752)
  %t754 = inttoptr i64 109 to ptr
  %t755 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t754, ptr %t755
  call void @__inc_ref(ptr %t744)
  %t753 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t744, ptr %t753
  br label %reuse.join.750
reuse.copy.749:
  %t756 = call ptr @__alloc(i64 24, i32 2)
  %t757 = inttoptr i64 109 to ptr
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
tco.case.arm.67.762:
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
  %t774 = inttoptr i64 110 to ptr
  %t775 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t774, ptr %t775
  call void @__inc_ref(ptr %t764)
  %t773 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t764, ptr %t773
  br label %reuse.join.770
reuse.copy.769:
  %t776 = call ptr @__alloc(i64 24, i32 2)
  %t777 = inttoptr i64 110 to ptr
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
tco.case.arm.68.782:
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
  %t794 = inttoptr i64 111 to ptr
  %t795 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t794, ptr %t795
  call void @__inc_ref(ptr %t784)
  %t793 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t784, ptr %t793
  br label %reuse.join.790
reuse.copy.789:
  %t796 = call ptr @__alloc(i64 24, i32 2)
  %t797 = inttoptr i64 111 to ptr
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
tco.case.default.19:
  unreachable
tco.case.arm.70.802:
  %t803 = getelementptr ptr, ptr %t5, i32 1
  %t804 = load ptr, ptr %t803
  %t805 = getelementptr ptr, ptr %t5, i32 2
  %t806 = load ptr, ptr %t805
  %t807 = getelementptr i8, ptr %t5, i64 -8
  %t808 = load i32, ptr %t807
  %t809 = icmp eq i32 %t808, 1
  br i1 %t809, label %reuse.in_place.810, label %reuse.copy.811
reuse.in_place.810:
  %t813 = inttoptr i64 69 to ptr
  %t814 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t813, ptr %t814
  br label %reuse.join.812
reuse.copy.811:
  %t815 = call ptr @__alloc(i64 24, i32 2)
  %t816 = inttoptr i64 69 to ptr
  %t817 = getelementptr ptr, ptr %t815, i32 0
  store ptr %t816, ptr %t817
  call void @__inc_ref(ptr %t804)
  %t818 = getelementptr ptr, ptr %t815, i32 1
  store ptr %t804, ptr %t818
  call void @__inc_ref(ptr %t806)
  %t819 = getelementptr ptr, ptr %t815, i32 2
  store ptr %t806, ptr %t819
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.812
reuse.join.812:
  %t820 = phi ptr [ %t5, %reuse.in_place.810 ], [ %t815, %reuse.copy.811 ]
  %t821 = call ptr @__alloc(i64 16, i32 1)
  %t822 = inttoptr i64 155 to ptr
  %t823 = getelementptr ptr, ptr %t821, i32 0
  store ptr %t822, ptr %t823
  call void @__inc_ref(ptr %t6)
  %t824 = getelementptr ptr, ptr %t821, i32 1
  store ptr %t6, ptr %t824
  call void @__free_recursive(ptr %t6)
  store ptr %t820, ptr %t3
  store ptr %t821, ptr %t4
  br label %tco.loop.0
tco.case.arm.71.825:
  %t826 = getelementptr ptr, ptr %t5, i32 1
  %t827 = load ptr, ptr %t826
  %t828 = getelementptr ptr, ptr %t5, i32 2
  %t829 = load ptr, ptr %t828
  %t830 = getelementptr i8, ptr %t5, i64 -8
  %t831 = load i32, ptr %t830
  %t832 = icmp eq i32 %t831, 1
  br i1 %t832, label %reuse.in_place.833, label %reuse.copy.834
reuse.in_place.833:
  %t836 = inttoptr i64 69 to ptr
  %t837 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t836, ptr %t837
  br label %reuse.join.835
reuse.copy.834:
  %t838 = call ptr @__alloc(i64 24, i32 2)
  %t839 = inttoptr i64 69 to ptr
  %t840 = getelementptr ptr, ptr %t838, i32 0
  store ptr %t839, ptr %t840
  call void @__inc_ref(ptr %t827)
  %t841 = getelementptr ptr, ptr %t838, i32 1
  store ptr %t827, ptr %t841
  call void @__inc_ref(ptr %t829)
  %t842 = getelementptr ptr, ptr %t838, i32 2
  store ptr %t829, ptr %t842
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.835
reuse.join.835:
  %t843 = phi ptr [ %t5, %reuse.in_place.833 ], [ %t838, %reuse.copy.834 ]
  %t844 = call ptr @__alloc(i64 16, i32 1)
  %t845 = inttoptr i64 156 to ptr
  %t846 = getelementptr ptr, ptr %t844, i32 0
  store ptr %t845, ptr %t846
  call void @__inc_ref(ptr %t6)
  %t847 = getelementptr ptr, ptr %t844, i32 1
  store ptr %t6, ptr %t847
  call void @__free_recursive(ptr %t6)
  store ptr %t843, ptr %t3
  store ptr %t844, ptr %t4
  br label %tco.loop.0
tco.case.arm.72.848:
  %t849 = getelementptr ptr, ptr %t5, i32 1
  %t850 = load ptr, ptr %t849
  %t851 = getelementptr ptr, ptr %t5, i32 2
  %t852 = load ptr, ptr %t851
  %t853 = getelementptr i8, ptr %t5, i64 -8
  %t854 = load i32, ptr %t853
  %t855 = icmp eq i32 %t854, 1
  br i1 %t855, label %reuse.in_place.856, label %reuse.copy.857
reuse.in_place.856:
  %t859 = inttoptr i64 69 to ptr
  %t860 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t859, ptr %t860
  br label %reuse.join.858
reuse.copy.857:
  %t861 = call ptr @__alloc(i64 24, i32 2)
  %t862 = inttoptr i64 69 to ptr
  %t863 = getelementptr ptr, ptr %t861, i32 0
  store ptr %t862, ptr %t863
  call void @__inc_ref(ptr %t850)
  %t864 = getelementptr ptr, ptr %t861, i32 1
  store ptr %t850, ptr %t864
  call void @__inc_ref(ptr %t852)
  %t865 = getelementptr ptr, ptr %t861, i32 2
  store ptr %t852, ptr %t865
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.858
reuse.join.858:
  %t866 = phi ptr [ %t5, %reuse.in_place.856 ], [ %t861, %reuse.copy.857 ]
  %t867 = call ptr @__alloc(i64 16, i32 1)
  %t868 = inttoptr i64 157 to ptr
  %t869 = getelementptr ptr, ptr %t867, i32 0
  store ptr %t868, ptr %t869
  call void @__inc_ref(ptr %t6)
  %t870 = getelementptr ptr, ptr %t867, i32 1
  store ptr %t6, ptr %t870
  call void @__free_recursive(ptr %t6)
  store ptr %t866, ptr %t3
  store ptr %t867, ptr %t4
  br label %tco.loop.0
tco.case.arm.73.871:
  %t872 = getelementptr ptr, ptr %t5, i32 1
  %t873 = load ptr, ptr %t872
  %t874 = getelementptr ptr, ptr %t5, i32 2
  %t875 = load ptr, ptr %t874
  %t876 = getelementptr i8, ptr %t5, i64 -8
  %t877 = load i32, ptr %t876
  %t878 = icmp eq i32 %t877, 1
  br i1 %t878, label %reuse.in_place.879, label %reuse.copy.880
reuse.in_place.879:
  %t882 = inttoptr i64 69 to ptr
  %t883 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t882, ptr %t883
  br label %reuse.join.881
reuse.copy.880:
  %t884 = call ptr @__alloc(i64 24, i32 2)
  %t885 = inttoptr i64 69 to ptr
  %t886 = getelementptr ptr, ptr %t884, i32 0
  store ptr %t885, ptr %t886
  call void @__inc_ref(ptr %t873)
  %t887 = getelementptr ptr, ptr %t884, i32 1
  store ptr %t873, ptr %t887
  call void @__inc_ref(ptr %t875)
  %t888 = getelementptr ptr, ptr %t884, i32 2
  store ptr %t875, ptr %t888
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.881
reuse.join.881:
  %t889 = phi ptr [ %t5, %reuse.in_place.879 ], [ %t884, %reuse.copy.880 ]
  %t890 = call ptr @__alloc(i64 16, i32 1)
  %t891 = inttoptr i64 158 to ptr
  %t892 = getelementptr ptr, ptr %t890, i32 0
  store ptr %t891, ptr %t892
  call void @__inc_ref(ptr %t6)
  %t893 = getelementptr ptr, ptr %t890, i32 1
  store ptr %t6, ptr %t893
  call void @__free_recursive(ptr %t6)
  store ptr %t889, ptr %t3
  store ptr %t890, ptr %t4
  br label %tco.loop.0
tco.case.arm.74.894:
  %t895 = getelementptr ptr, ptr %t5, i32 1
  %t896 = load ptr, ptr %t895
  %t897 = getelementptr ptr, ptr %t5, i32 2
  %t898 = load ptr, ptr %t897
  %t899 = getelementptr i8, ptr %t5, i64 -8
  %t900 = load i32, ptr %t899
  %t901 = icmp eq i32 %t900, 1
  br i1 %t901, label %reuse.in_place.902, label %reuse.copy.903
reuse.in_place.902:
  %t905 = inttoptr i64 69 to ptr
  %t906 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t905, ptr %t906
  br label %reuse.join.904
reuse.copy.903:
  %t907 = call ptr @__alloc(i64 24, i32 2)
  %t908 = inttoptr i64 69 to ptr
  %t909 = getelementptr ptr, ptr %t907, i32 0
  store ptr %t908, ptr %t909
  call void @__inc_ref(ptr %t896)
  %t910 = getelementptr ptr, ptr %t907, i32 1
  store ptr %t896, ptr %t910
  call void @__inc_ref(ptr %t898)
  %t911 = getelementptr ptr, ptr %t907, i32 2
  store ptr %t898, ptr %t911
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.904
reuse.join.904:
  %t912 = phi ptr [ %t5, %reuse.in_place.902 ], [ %t907, %reuse.copy.903 ]
  %t913 = call ptr @__alloc(i64 16, i32 1)
  %t914 = inttoptr i64 159 to ptr
  %t915 = getelementptr ptr, ptr %t913, i32 0
  store ptr %t914, ptr %t915
  call void @__inc_ref(ptr %t6)
  %t916 = getelementptr ptr, ptr %t913, i32 1
  store ptr %t6, ptr %t916
  call void @__free_recursive(ptr %t6)
  store ptr %t912, ptr %t3
  store ptr %t913, ptr %t4
  br label %tco.loop.0
tco.case.arm.75.917:
  %t918 = getelementptr ptr, ptr %t5, i32 1
  %t919 = load ptr, ptr %t918
  %t920 = getelementptr ptr, ptr %t5, i32 2
  %t921 = load ptr, ptr %t920
  %t922 = getelementptr i8, ptr %t5, i64 -8
  %t923 = load i32, ptr %t922
  %t924 = icmp eq i32 %t923, 1
  br i1 %t924, label %reuse.in_place.925, label %reuse.copy.926
reuse.in_place.925:
  %t928 = inttoptr i64 69 to ptr
  %t929 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t928, ptr %t929
  br label %reuse.join.927
reuse.copy.926:
  %t930 = call ptr @__alloc(i64 24, i32 2)
  %t931 = inttoptr i64 69 to ptr
  %t932 = getelementptr ptr, ptr %t930, i32 0
  store ptr %t931, ptr %t932
  call void @__inc_ref(ptr %t919)
  %t933 = getelementptr ptr, ptr %t930, i32 1
  store ptr %t919, ptr %t933
  call void @__inc_ref(ptr %t921)
  %t934 = getelementptr ptr, ptr %t930, i32 2
  store ptr %t921, ptr %t934
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.927
reuse.join.927:
  %t935 = phi ptr [ %t5, %reuse.in_place.925 ], [ %t930, %reuse.copy.926 ]
  %t936 = call ptr @__alloc(i64 16, i32 1)
  %t937 = inttoptr i64 160 to ptr
  %t938 = getelementptr ptr, ptr %t936, i32 0
  store ptr %t937, ptr %t938
  call void @__inc_ref(ptr %t6)
  %t939 = getelementptr ptr, ptr %t936, i32 1
  store ptr %t6, ptr %t939
  call void @__free_recursive(ptr %t6)
  store ptr %t935, ptr %t3
  store ptr %t936, ptr %t4
  br label %tco.loop.0
tco.case.arm.76.940:
  %t941 = getelementptr ptr, ptr %t5, i32 1
  %t942 = load ptr, ptr %t941
  %t943 = getelementptr ptr, ptr %t5, i32 2
  %t944 = load ptr, ptr %t943
  %t945 = getelementptr i8, ptr %t5, i64 -8
  %t946 = load i32, ptr %t945
  %t947 = icmp eq i32 %t946, 1
  br i1 %t947, label %reuse.in_place.948, label %reuse.copy.949
reuse.in_place.948:
  %t951 = inttoptr i64 69 to ptr
  %t952 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t951, ptr %t952
  br label %reuse.join.950
reuse.copy.949:
  %t953 = call ptr @__alloc(i64 24, i32 2)
  %t954 = inttoptr i64 69 to ptr
  %t955 = getelementptr ptr, ptr %t953, i32 0
  store ptr %t954, ptr %t955
  call void @__inc_ref(ptr %t942)
  %t956 = getelementptr ptr, ptr %t953, i32 1
  store ptr %t942, ptr %t956
  call void @__inc_ref(ptr %t944)
  %t957 = getelementptr ptr, ptr %t953, i32 2
  store ptr %t944, ptr %t957
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.950
reuse.join.950:
  %t958 = phi ptr [ %t5, %reuse.in_place.948 ], [ %t953, %reuse.copy.949 ]
  %t959 = call ptr @__alloc(i64 16, i32 1)
  %t960 = inttoptr i64 161 to ptr
  %t961 = getelementptr ptr, ptr %t959, i32 0
  store ptr %t960, ptr %t961
  call void @__inc_ref(ptr %t6)
  %t962 = getelementptr ptr, ptr %t959, i32 1
  store ptr %t6, ptr %t962
  call void @__free_recursive(ptr %t6)
  store ptr %t958, ptr %t3
  store ptr %t959, ptr %t4
  br label %tco.loop.0
tco.case.arm.77.963:
  %t964 = getelementptr ptr, ptr %t5, i32 1
  %t965 = load ptr, ptr %t964
  %t966 = getelementptr ptr, ptr %t5, i32 2
  %t967 = load ptr, ptr %t966
  %t968 = getelementptr i8, ptr %t5, i64 -8
  %t969 = load i32, ptr %t968
  %t970 = icmp eq i32 %t969, 1
  br i1 %t970, label %reuse.in_place.971, label %reuse.copy.972
reuse.in_place.971:
  %t974 = inttoptr i64 69 to ptr
  %t975 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t974, ptr %t975
  br label %reuse.join.973
reuse.copy.972:
  %t976 = call ptr @__alloc(i64 24, i32 2)
  %t977 = inttoptr i64 69 to ptr
  %t978 = getelementptr ptr, ptr %t976, i32 0
  store ptr %t977, ptr %t978
  call void @__inc_ref(ptr %t965)
  %t979 = getelementptr ptr, ptr %t976, i32 1
  store ptr %t965, ptr %t979
  call void @__inc_ref(ptr %t967)
  %t980 = getelementptr ptr, ptr %t976, i32 2
  store ptr %t967, ptr %t980
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.973
reuse.join.973:
  %t981 = phi ptr [ %t5, %reuse.in_place.971 ], [ %t976, %reuse.copy.972 ]
  %t982 = call ptr @__alloc(i64 16, i32 1)
  %t983 = inttoptr i64 162 to ptr
  %t984 = getelementptr ptr, ptr %t982, i32 0
  store ptr %t983, ptr %t984
  call void @__inc_ref(ptr %t6)
  %t985 = getelementptr ptr, ptr %t982, i32 1
  store ptr %t6, ptr %t985
  call void @__free_recursive(ptr %t6)
  store ptr %t981, ptr %t3
  store ptr %t982, ptr %t4
  br label %tco.loop.0
tco.case.arm.78.986:
  %t987 = getelementptr ptr, ptr %t5, i32 1
  %t988 = load ptr, ptr %t987
  %t989 = getelementptr ptr, ptr %t5, i32 2
  %t990 = load ptr, ptr %t989
  %t991 = getelementptr i8, ptr %t5, i64 -8
  %t992 = load i32, ptr %t991
  %t993 = icmp eq i32 %t992, 1
  br i1 %t993, label %reuse.in_place.994, label %reuse.copy.995
reuse.in_place.994:
  %t997 = inttoptr i64 69 to ptr
  %t998 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t997, ptr %t998
  br label %reuse.join.996
reuse.copy.995:
  %t999 = call ptr @__alloc(i64 24, i32 2)
  %t1000 = inttoptr i64 69 to ptr
  %t1001 = getelementptr ptr, ptr %t999, i32 0
  store ptr %t1000, ptr %t1001
  call void @__inc_ref(ptr %t988)
  %t1002 = getelementptr ptr, ptr %t999, i32 1
  store ptr %t988, ptr %t1002
  call void @__inc_ref(ptr %t990)
  %t1003 = getelementptr ptr, ptr %t999, i32 2
  store ptr %t990, ptr %t1003
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.996
reuse.join.996:
  %t1004 = phi ptr [ %t5, %reuse.in_place.994 ], [ %t999, %reuse.copy.995 ]
  %t1005 = call ptr @__alloc(i64 16, i32 1)
  %t1006 = inttoptr i64 163 to ptr
  %t1007 = getelementptr ptr, ptr %t1005, i32 0
  store ptr %t1006, ptr %t1007
  call void @__inc_ref(ptr %t6)
  %t1008 = getelementptr ptr, ptr %t1005, i32 1
  store ptr %t6, ptr %t1008
  call void @__free_recursive(ptr %t6)
  store ptr %t1004, ptr %t3
  store ptr %t1005, ptr %t4
  br label %tco.loop.0
tco.case.arm.79.1009:
  %t1010 = getelementptr ptr, ptr %t5, i32 1
  %t1011 = load ptr, ptr %t1010
  call void @__inc_ref(ptr %t1011)
  %t1012 = getelementptr ptr, ptr %t5, i32 2
  %t1013 = load ptr, ptr %t1012
  call void @__inc_ref(ptr %t1013)
  %t1014 = getelementptr ptr, ptr %t5, i32 3
  %t1015 = load ptr, ptr %t1014
  call void @__inc_ref(ptr %t1015)
  %t1016 = call ptr @__alloc(i64 24, i32 2)
  %t1017 = inttoptr i64 69 to ptr
  %t1018 = getelementptr ptr, ptr %t1016, i32 0
  store ptr %t1017, ptr %t1018
  call void @__inc_ref(ptr %t1011)
  %t1019 = getelementptr ptr, ptr %t1016, i32 1
  store ptr %t1011, ptr %t1019
  call void @__inc_ref(ptr %t1013)
  %t1020 = getelementptr ptr, ptr %t1016, i32 2
  store ptr %t1013, ptr %t1020
  %t1021 = call ptr @__alloc(i64 24, i32 2)
  %t1022 = inttoptr i64 164 to ptr
  %t1023 = getelementptr ptr, ptr %t1021, i32 0
  store ptr %t1022, ptr %t1023
  call void @__inc_ref(ptr %t6)
  %t1024 = getelementptr ptr, ptr %t1021, i32 1
  store ptr %t6, ptr %t1024
  call void @__inc_ref(ptr %t1015)
  %t1025 = getelementptr ptr, ptr %t1021, i32 2
  store ptr %t1015, ptr %t1025
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t1015)
  call void @__free_recursive(ptr %t1013)
  call void @__free_recursive(ptr %t1011)
  store ptr %t1016, ptr %t3
  store ptr %t1021, ptr %t4
  br label %tco.loop.0
tco.case.arm.80.1026:
  %t1027 = getelementptr ptr, ptr %t5, i32 1
  %t1028 = load ptr, ptr %t1027
  %t1029 = getelementptr ptr, ptr %t5, i32 2
  %t1030 = load ptr, ptr %t1029
  %t1031 = getelementptr i8, ptr %t5, i64 -8
  %t1032 = load i32, ptr %t1031
  %t1033 = icmp eq i32 %t1032, 1
  br i1 %t1033, label %reuse.in_place.1034, label %reuse.copy.1035
reuse.in_place.1034:
  %t1037 = inttoptr i64 69 to ptr
  %t1038 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1037, ptr %t1038
  br label %reuse.join.1036
reuse.copy.1035:
  %t1039 = call ptr @__alloc(i64 24, i32 2)
  %t1040 = inttoptr i64 69 to ptr
  %t1041 = getelementptr ptr, ptr %t1039, i32 0
  store ptr %t1040, ptr %t1041
  call void @__inc_ref(ptr %t1028)
  %t1042 = getelementptr ptr, ptr %t1039, i32 1
  store ptr %t1028, ptr %t1042
  call void @__inc_ref(ptr %t1030)
  %t1043 = getelementptr ptr, ptr %t1039, i32 2
  store ptr %t1030, ptr %t1043
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1036
reuse.join.1036:
  %t1044 = phi ptr [ %t5, %reuse.in_place.1034 ], [ %t1039, %reuse.copy.1035 ]
  %t1045 = call ptr @__alloc(i64 16, i32 1)
  %t1046 = inttoptr i64 165 to ptr
  %t1047 = getelementptr ptr, ptr %t1045, i32 0
  store ptr %t1046, ptr %t1047
  call void @__inc_ref(ptr %t6)
  %t1048 = getelementptr ptr, ptr %t1045, i32 1
  store ptr %t6, ptr %t1048
  call void @__free_recursive(ptr %t6)
  store ptr %t1044, ptr %t3
  store ptr %t1045, ptr %t4
  br label %tco.loop.0
tco.case.arm.81.1049:
  %t1050 = getelementptr ptr, ptr %t5, i32 1
  %t1051 = load ptr, ptr %t1050
  %t1052 = getelementptr ptr, ptr %t5, i32 2
  %t1053 = load ptr, ptr %t1052
  %t1054 = getelementptr i8, ptr %t5, i64 -8
  %t1055 = load i32, ptr %t1054
  %t1056 = icmp eq i32 %t1055, 1
  br i1 %t1056, label %reuse.in_place.1057, label %reuse.copy.1058
reuse.in_place.1057:
  %t1060 = inttoptr i64 69 to ptr
  %t1061 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1060, ptr %t1061
  br label %reuse.join.1059
reuse.copy.1058:
  %t1062 = call ptr @__alloc(i64 24, i32 2)
  %t1063 = inttoptr i64 69 to ptr
  %t1064 = getelementptr ptr, ptr %t1062, i32 0
  store ptr %t1063, ptr %t1064
  call void @__inc_ref(ptr %t1051)
  %t1065 = getelementptr ptr, ptr %t1062, i32 1
  store ptr %t1051, ptr %t1065
  call void @__inc_ref(ptr %t1053)
  %t1066 = getelementptr ptr, ptr %t1062, i32 2
  store ptr %t1053, ptr %t1066
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1059
reuse.join.1059:
  %t1067 = phi ptr [ %t5, %reuse.in_place.1057 ], [ %t1062, %reuse.copy.1058 ]
  %t1068 = call ptr @__alloc(i64 16, i32 1)
  %t1069 = inttoptr i64 166 to ptr
  %t1070 = getelementptr ptr, ptr %t1068, i32 0
  store ptr %t1069, ptr %t1070
  call void @__inc_ref(ptr %t6)
  %t1071 = getelementptr ptr, ptr %t1068, i32 1
  store ptr %t6, ptr %t1071
  call void @__free_recursive(ptr %t6)
  store ptr %t1067, ptr %t3
  store ptr %t1068, ptr %t4
  br label %tco.loop.0
tco.case.arm.82.1072:
  %t1073 = getelementptr ptr, ptr %t5, i32 1
  %t1074 = load ptr, ptr %t1073
  %t1075 = getelementptr ptr, ptr %t5, i32 2
  %t1076 = load ptr, ptr %t1075
  %t1077 = getelementptr i8, ptr %t5, i64 -8
  %t1078 = load i32, ptr %t1077
  %t1079 = icmp eq i32 %t1078, 1
  br i1 %t1079, label %reuse.in_place.1080, label %reuse.copy.1081
reuse.in_place.1080:
  %t1083 = inttoptr i64 69 to ptr
  %t1084 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1083, ptr %t1084
  br label %reuse.join.1082
reuse.copy.1081:
  %t1085 = call ptr @__alloc(i64 24, i32 2)
  %t1086 = inttoptr i64 69 to ptr
  %t1087 = getelementptr ptr, ptr %t1085, i32 0
  store ptr %t1086, ptr %t1087
  call void @__inc_ref(ptr %t1074)
  %t1088 = getelementptr ptr, ptr %t1085, i32 1
  store ptr %t1074, ptr %t1088
  call void @__inc_ref(ptr %t1076)
  %t1089 = getelementptr ptr, ptr %t1085, i32 2
  store ptr %t1076, ptr %t1089
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1082
reuse.join.1082:
  %t1090 = phi ptr [ %t5, %reuse.in_place.1080 ], [ %t1085, %reuse.copy.1081 ]
  %t1091 = call ptr @__alloc(i64 16, i32 1)
  %t1092 = inttoptr i64 167 to ptr
  %t1093 = getelementptr ptr, ptr %t1091, i32 0
  store ptr %t1092, ptr %t1093
  call void @__inc_ref(ptr %t6)
  %t1094 = getelementptr ptr, ptr %t1091, i32 1
  store ptr %t6, ptr %t1094
  call void @__free_recursive(ptr %t6)
  store ptr %t1090, ptr %t3
  store ptr %t1091, ptr %t4
  br label %tco.loop.0
tco.case.arm.83.1095:
  %t1096 = getelementptr ptr, ptr %t5, i32 1
  %t1097 = load ptr, ptr %t1096
  %t1098 = getelementptr ptr, ptr %t5, i32 2
  %t1099 = load ptr, ptr %t1098
  %t1100 = getelementptr i8, ptr %t5, i64 -8
  %t1101 = load i32, ptr %t1100
  %t1102 = icmp eq i32 %t1101, 1
  br i1 %t1102, label %reuse.in_place.1103, label %reuse.copy.1104
reuse.in_place.1103:
  %t1106 = inttoptr i64 69 to ptr
  %t1107 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1106, ptr %t1107
  br label %reuse.join.1105
reuse.copy.1104:
  %t1108 = call ptr @__alloc(i64 24, i32 2)
  %t1109 = inttoptr i64 69 to ptr
  %t1110 = getelementptr ptr, ptr %t1108, i32 0
  store ptr %t1109, ptr %t1110
  call void @__inc_ref(ptr %t1097)
  %t1111 = getelementptr ptr, ptr %t1108, i32 1
  store ptr %t1097, ptr %t1111
  call void @__inc_ref(ptr %t1099)
  %t1112 = getelementptr ptr, ptr %t1108, i32 2
  store ptr %t1099, ptr %t1112
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1105
reuse.join.1105:
  %t1113 = phi ptr [ %t5, %reuse.in_place.1103 ], [ %t1108, %reuse.copy.1104 ]
  %t1114 = call ptr @__alloc(i64 16, i32 1)
  %t1115 = inttoptr i64 168 to ptr
  %t1116 = getelementptr ptr, ptr %t1114, i32 0
  store ptr %t1115, ptr %t1116
  call void @__inc_ref(ptr %t6)
  %t1117 = getelementptr ptr, ptr %t1114, i32 1
  store ptr %t6, ptr %t1117
  call void @__free_recursive(ptr %t6)
  store ptr %t1113, ptr %t3
  store ptr %t1114, ptr %t4
  br label %tco.loop.0
tco.case.arm.84.1118:
  %t1119 = getelementptr ptr, ptr %t5, i32 1
  %t1120 = load ptr, ptr %t1119
  %t1121 = getelementptr ptr, ptr %t5, i32 2
  %t1122 = load ptr, ptr %t1121
  %t1123 = getelementptr i8, ptr %t5, i64 -8
  %t1124 = load i32, ptr %t1123
  %t1125 = icmp eq i32 %t1124, 1
  br i1 %t1125, label %reuse.in_place.1126, label %reuse.copy.1127
reuse.in_place.1126:
  %t1129 = inttoptr i64 69 to ptr
  %t1130 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1129, ptr %t1130
  br label %reuse.join.1128
reuse.copy.1127:
  %t1131 = call ptr @__alloc(i64 24, i32 2)
  %t1132 = inttoptr i64 69 to ptr
  %t1133 = getelementptr ptr, ptr %t1131, i32 0
  store ptr %t1132, ptr %t1133
  call void @__inc_ref(ptr %t1120)
  %t1134 = getelementptr ptr, ptr %t1131, i32 1
  store ptr %t1120, ptr %t1134
  call void @__inc_ref(ptr %t1122)
  %t1135 = getelementptr ptr, ptr %t1131, i32 2
  store ptr %t1122, ptr %t1135
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1128
reuse.join.1128:
  %t1136 = phi ptr [ %t5, %reuse.in_place.1126 ], [ %t1131, %reuse.copy.1127 ]
  %t1137 = call ptr @__alloc(i64 16, i32 1)
  %t1138 = inttoptr i64 169 to ptr
  %t1139 = getelementptr ptr, ptr %t1137, i32 0
  store ptr %t1138, ptr %t1139
  call void @__inc_ref(ptr %t6)
  %t1140 = getelementptr ptr, ptr %t1137, i32 1
  store ptr %t6, ptr %t1140
  call void @__free_recursive(ptr %t6)
  store ptr %t1136, ptr %t3
  store ptr %t1137, ptr %t4
  br label %tco.loop.0
tco.case.arm.85.1141:
  %t1142 = getelementptr ptr, ptr %t5, i32 1
  %t1143 = load ptr, ptr %t1142
  %t1144 = getelementptr ptr, ptr %t5, i32 2
  %t1145 = load ptr, ptr %t1144
  %t1146 = getelementptr i8, ptr %t5, i64 -8
  %t1147 = load i32, ptr %t1146
  %t1148 = icmp eq i32 %t1147, 1
  br i1 %t1148, label %reuse.in_place.1149, label %reuse.copy.1150
reuse.in_place.1149:
  %t1152 = inttoptr i64 69 to ptr
  %t1153 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1152, ptr %t1153
  br label %reuse.join.1151
reuse.copy.1150:
  %t1154 = call ptr @__alloc(i64 24, i32 2)
  %t1155 = inttoptr i64 69 to ptr
  %t1156 = getelementptr ptr, ptr %t1154, i32 0
  store ptr %t1155, ptr %t1156
  call void @__inc_ref(ptr %t1143)
  %t1157 = getelementptr ptr, ptr %t1154, i32 1
  store ptr %t1143, ptr %t1157
  call void @__inc_ref(ptr %t1145)
  %t1158 = getelementptr ptr, ptr %t1154, i32 2
  store ptr %t1145, ptr %t1158
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1151
reuse.join.1151:
  %t1159 = phi ptr [ %t5, %reuse.in_place.1149 ], [ %t1154, %reuse.copy.1150 ]
  %t1160 = call ptr @__alloc(i64 16, i32 1)
  %t1161 = inttoptr i64 170 to ptr
  %t1162 = getelementptr ptr, ptr %t1160, i32 0
  store ptr %t1161, ptr %t1162
  call void @__inc_ref(ptr %t6)
  %t1163 = getelementptr ptr, ptr %t1160, i32 1
  store ptr %t6, ptr %t1163
  call void @__free_recursive(ptr %t6)
  store ptr %t1159, ptr %t3
  store ptr %t1160, ptr %t4
  br label %tco.loop.0
tco.case.arm.86.1164:
  %t1165 = getelementptr ptr, ptr %t5, i32 1
  %t1166 = load ptr, ptr %t1165
  call void @__inc_ref(ptr %t1166)
  %t1167 = getelementptr ptr, ptr %t5, i32 2
  %t1168 = load ptr, ptr %t1167
  call void @__inc_ref(ptr %t1168)
  %t1169 = getelementptr ptr, ptr %t5, i32 3
  %t1170 = load ptr, ptr %t1169
  call void @__inc_ref(ptr %t1170)
  %t1171 = call ptr @__alloc(i64 24, i32 2)
  %t1172 = inttoptr i64 69 to ptr
  %t1173 = getelementptr ptr, ptr %t1171, i32 0
  store ptr %t1172, ptr %t1173
  call void @__inc_ref(ptr %t1166)
  %t1174 = getelementptr ptr, ptr %t1171, i32 1
  store ptr %t1166, ptr %t1174
  call void @__inc_ref(ptr %t1168)
  %t1175 = getelementptr ptr, ptr %t1171, i32 2
  store ptr %t1168, ptr %t1175
  %t1176 = call ptr @__alloc(i64 24, i32 2)
  %t1177 = inttoptr i64 171 to ptr
  %t1178 = getelementptr ptr, ptr %t1176, i32 0
  store ptr %t1177, ptr %t1178
  call void @__inc_ref(ptr %t6)
  %t1179 = getelementptr ptr, ptr %t1176, i32 1
  store ptr %t6, ptr %t1179
  call void @__inc_ref(ptr %t1170)
  %t1180 = getelementptr ptr, ptr %t1176, i32 2
  store ptr %t1170, ptr %t1180
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t1170)
  call void @__free_recursive(ptr %t1168)
  call void @__free_recursive(ptr %t1166)
  store ptr %t1171, ptr %t3
  store ptr %t1176, ptr %t4
  br label %tco.loop.0
tco.case.arm.87.1181:
  %t1182 = getelementptr ptr, ptr %t5, i32 1
  %t1183 = load ptr, ptr %t1182
  %t1184 = getelementptr ptr, ptr %t5, i32 2
  %t1185 = load ptr, ptr %t1184
  %t1186 = getelementptr i8, ptr %t5, i64 -8
  %t1187 = load i32, ptr %t1186
  %t1188 = icmp eq i32 %t1187, 1
  br i1 %t1188, label %reuse.in_place.1189, label %reuse.copy.1190
reuse.in_place.1189:
  %t1192 = inttoptr i64 69 to ptr
  %t1193 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1192, ptr %t1193
  br label %reuse.join.1191
reuse.copy.1190:
  %t1194 = call ptr @__alloc(i64 24, i32 2)
  %t1195 = inttoptr i64 69 to ptr
  %t1196 = getelementptr ptr, ptr %t1194, i32 0
  store ptr %t1195, ptr %t1196
  call void @__inc_ref(ptr %t1183)
  %t1197 = getelementptr ptr, ptr %t1194, i32 1
  store ptr %t1183, ptr %t1197
  call void @__inc_ref(ptr %t1185)
  %t1198 = getelementptr ptr, ptr %t1194, i32 2
  store ptr %t1185, ptr %t1198
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1191
reuse.join.1191:
  %t1199 = phi ptr [ %t5, %reuse.in_place.1189 ], [ %t1194, %reuse.copy.1190 ]
  %t1200 = call ptr @__alloc(i64 16, i32 1)
  %t1201 = inttoptr i64 172 to ptr
  %t1202 = getelementptr ptr, ptr %t1200, i32 0
  store ptr %t1201, ptr %t1202
  call void @__inc_ref(ptr %t6)
  %t1203 = getelementptr ptr, ptr %t1200, i32 1
  store ptr %t6, ptr %t1203
  call void @__free_recursive(ptr %t6)
  store ptr %t1199, ptr %t3
  store ptr %t1200, ptr %t4
  br label %tco.loop.0
tco.case.arm.88.1204:
  %t1205 = getelementptr ptr, ptr %t5, i32 1
  %t1206 = load ptr, ptr %t1205
  %t1207 = getelementptr ptr, ptr %t5, i32 2
  %t1208 = load ptr, ptr %t1207
  %t1209 = getelementptr i8, ptr %t5, i64 -8
  %t1210 = load i32, ptr %t1209
  %t1211 = icmp eq i32 %t1210, 1
  br i1 %t1211, label %reuse.in_place.1212, label %reuse.copy.1213
reuse.in_place.1212:
  %t1215 = inttoptr i64 69 to ptr
  %t1216 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1215, ptr %t1216
  br label %reuse.join.1214
reuse.copy.1213:
  %t1217 = call ptr @__alloc(i64 24, i32 2)
  %t1218 = inttoptr i64 69 to ptr
  %t1219 = getelementptr ptr, ptr %t1217, i32 0
  store ptr %t1218, ptr %t1219
  call void @__inc_ref(ptr %t1206)
  %t1220 = getelementptr ptr, ptr %t1217, i32 1
  store ptr %t1206, ptr %t1220
  call void @__inc_ref(ptr %t1208)
  %t1221 = getelementptr ptr, ptr %t1217, i32 2
  store ptr %t1208, ptr %t1221
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1214
reuse.join.1214:
  %t1222 = phi ptr [ %t5, %reuse.in_place.1212 ], [ %t1217, %reuse.copy.1213 ]
  %t1223 = call ptr @__alloc(i64 16, i32 1)
  %t1224 = inttoptr i64 173 to ptr
  %t1225 = getelementptr ptr, ptr %t1223, i32 0
  store ptr %t1224, ptr %t1225
  call void @__inc_ref(ptr %t6)
  %t1226 = getelementptr ptr, ptr %t1223, i32 1
  store ptr %t6, ptr %t1226
  call void @__free_recursive(ptr %t6)
  store ptr %t1222, ptr %t3
  store ptr %t1223, ptr %t4
  br label %tco.loop.0
tco.case.arm.89.1227:
  %t1228 = getelementptr ptr, ptr %t5, i32 1
  %t1229 = load ptr, ptr %t1228
  %t1230 = getelementptr ptr, ptr %t5, i32 2
  %t1231 = load ptr, ptr %t1230
  %t1232 = getelementptr i8, ptr %t5, i64 -8
  %t1233 = load i32, ptr %t1232
  %t1234 = icmp eq i32 %t1233, 1
  br i1 %t1234, label %reuse.in_place.1235, label %reuse.copy.1236
reuse.in_place.1235:
  %t1238 = inttoptr i64 69 to ptr
  %t1239 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1238, ptr %t1239
  br label %reuse.join.1237
reuse.copy.1236:
  %t1240 = call ptr @__alloc(i64 24, i32 2)
  %t1241 = inttoptr i64 69 to ptr
  %t1242 = getelementptr ptr, ptr %t1240, i32 0
  store ptr %t1241, ptr %t1242
  call void @__inc_ref(ptr %t1229)
  %t1243 = getelementptr ptr, ptr %t1240, i32 1
  store ptr %t1229, ptr %t1243
  call void @__inc_ref(ptr %t1231)
  %t1244 = getelementptr ptr, ptr %t1240, i32 2
  store ptr %t1231, ptr %t1244
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1237
reuse.join.1237:
  %t1245 = phi ptr [ %t5, %reuse.in_place.1235 ], [ %t1240, %reuse.copy.1236 ]
  %t1246 = call ptr @__alloc(i64 16, i32 1)
  %t1247 = inttoptr i64 174 to ptr
  %t1248 = getelementptr ptr, ptr %t1246, i32 0
  store ptr %t1247, ptr %t1248
  call void @__inc_ref(ptr %t6)
  %t1249 = getelementptr ptr, ptr %t1246, i32 1
  store ptr %t6, ptr %t1249
  call void @__free_recursive(ptr %t6)
  store ptr %t1245, ptr %t3
  store ptr %t1246, ptr %t4
  br label %tco.loop.0
tco.case.arm.90.1250:
  %t1251 = getelementptr ptr, ptr %t5, i32 1
  %t1252 = load ptr, ptr %t1251
  %t1253 = getelementptr ptr, ptr %t5, i32 2
  %t1254 = load ptr, ptr %t1253
  %t1255 = getelementptr i8, ptr %t5, i64 -8
  %t1256 = load i32, ptr %t1255
  %t1257 = icmp eq i32 %t1256, 1
  br i1 %t1257, label %reuse.in_place.1258, label %reuse.copy.1259
reuse.in_place.1258:
  %t1261 = inttoptr i64 69 to ptr
  %t1262 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1261, ptr %t1262
  br label %reuse.join.1260
reuse.copy.1259:
  %t1263 = call ptr @__alloc(i64 24, i32 2)
  %t1264 = inttoptr i64 69 to ptr
  %t1265 = getelementptr ptr, ptr %t1263, i32 0
  store ptr %t1264, ptr %t1265
  call void @__inc_ref(ptr %t1252)
  %t1266 = getelementptr ptr, ptr %t1263, i32 1
  store ptr %t1252, ptr %t1266
  call void @__inc_ref(ptr %t1254)
  %t1267 = getelementptr ptr, ptr %t1263, i32 2
  store ptr %t1254, ptr %t1267
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1260
reuse.join.1260:
  %t1268 = phi ptr [ %t5, %reuse.in_place.1258 ], [ %t1263, %reuse.copy.1259 ]
  %t1269 = call ptr @__alloc(i64 16, i32 1)
  %t1270 = inttoptr i64 175 to ptr
  %t1271 = getelementptr ptr, ptr %t1269, i32 0
  store ptr %t1270, ptr %t1271
  call void @__inc_ref(ptr %t6)
  %t1272 = getelementptr ptr, ptr %t1269, i32 1
  store ptr %t6, ptr %t1272
  call void @__free_recursive(ptr %t6)
  store ptr %t1268, ptr %t3
  store ptr %t1269, ptr %t4
  br label %tco.loop.0
tco.case.arm.91.1273:
  %t1274 = getelementptr ptr, ptr %t5, i32 1
  %t1275 = load ptr, ptr %t1274
  %t1276 = getelementptr ptr, ptr %t5, i32 2
  %t1277 = load ptr, ptr %t1276
  %t1278 = getelementptr i8, ptr %t5, i64 -8
  %t1279 = load i32, ptr %t1278
  %t1280 = icmp eq i32 %t1279, 1
  br i1 %t1280, label %reuse.in_place.1281, label %reuse.copy.1282
reuse.in_place.1281:
  %t1284 = inttoptr i64 69 to ptr
  %t1285 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1284, ptr %t1285
  br label %reuse.join.1283
reuse.copy.1282:
  %t1286 = call ptr @__alloc(i64 24, i32 2)
  %t1287 = inttoptr i64 69 to ptr
  %t1288 = getelementptr ptr, ptr %t1286, i32 0
  store ptr %t1287, ptr %t1288
  call void @__inc_ref(ptr %t1275)
  %t1289 = getelementptr ptr, ptr %t1286, i32 1
  store ptr %t1275, ptr %t1289
  call void @__inc_ref(ptr %t1277)
  %t1290 = getelementptr ptr, ptr %t1286, i32 2
  store ptr %t1277, ptr %t1290
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1283
reuse.join.1283:
  %t1291 = phi ptr [ %t5, %reuse.in_place.1281 ], [ %t1286, %reuse.copy.1282 ]
  %t1292 = call ptr @__alloc(i64 16, i32 1)
  %t1293 = inttoptr i64 176 to ptr
  %t1294 = getelementptr ptr, ptr %t1292, i32 0
  store ptr %t1293, ptr %t1294
  call void @__inc_ref(ptr %t6)
  %t1295 = getelementptr ptr, ptr %t1292, i32 1
  store ptr %t6, ptr %t1295
  call void @__free_recursive(ptr %t6)
  store ptr %t1291, ptr %t3
  store ptr %t1292, ptr %t4
  br label %tco.loop.0
tco.case.arm.92.1296:
  %t1297 = getelementptr ptr, ptr %t5, i32 1
  %t1298 = load ptr, ptr %t1297
  %t1299 = getelementptr ptr, ptr %t5, i32 2
  %t1300 = load ptr, ptr %t1299
  %t1301 = getelementptr i8, ptr %t5, i64 -8
  %t1302 = load i32, ptr %t1301
  %t1303 = icmp eq i32 %t1302, 1
  br i1 %t1303, label %reuse.in_place.1304, label %reuse.copy.1305
reuse.in_place.1304:
  %t1307 = inttoptr i64 69 to ptr
  %t1308 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1307, ptr %t1308
  br label %reuse.join.1306
reuse.copy.1305:
  %t1309 = call ptr @__alloc(i64 24, i32 2)
  %t1310 = inttoptr i64 69 to ptr
  %t1311 = getelementptr ptr, ptr %t1309, i32 0
  store ptr %t1310, ptr %t1311
  call void @__inc_ref(ptr %t1298)
  %t1312 = getelementptr ptr, ptr %t1309, i32 1
  store ptr %t1298, ptr %t1312
  call void @__inc_ref(ptr %t1300)
  %t1313 = getelementptr ptr, ptr %t1309, i32 2
  store ptr %t1300, ptr %t1313
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1306
reuse.join.1306:
  %t1314 = phi ptr [ %t5, %reuse.in_place.1304 ], [ %t1309, %reuse.copy.1305 ]
  %t1315 = call ptr @__alloc(i64 16, i32 1)
  %t1316 = inttoptr i64 177 to ptr
  %t1317 = getelementptr ptr, ptr %t1315, i32 0
  store ptr %t1316, ptr %t1317
  call void @__inc_ref(ptr %t6)
  %t1318 = getelementptr ptr, ptr %t1315, i32 1
  store ptr %t6, ptr %t1318
  call void @__free_recursive(ptr %t6)
  store ptr %t1314, ptr %t3
  store ptr %t1315, ptr %t4
  br label %tco.loop.0
tco.case.arm.93.1319:
  %t1320 = getelementptr ptr, ptr %t5, i32 1
  %t1321 = load ptr, ptr %t1320
  %t1322 = getelementptr ptr, ptr %t5, i32 2
  %t1323 = load ptr, ptr %t1322
  %t1324 = getelementptr i8, ptr %t5, i64 -8
  %t1325 = load i32, ptr %t1324
  %t1326 = icmp eq i32 %t1325, 1
  br i1 %t1326, label %reuse.in_place.1327, label %reuse.copy.1328
reuse.in_place.1327:
  %t1330 = inttoptr i64 69 to ptr
  %t1331 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1330, ptr %t1331
  br label %reuse.join.1329
reuse.copy.1328:
  %t1332 = call ptr @__alloc(i64 24, i32 2)
  %t1333 = inttoptr i64 69 to ptr
  %t1334 = getelementptr ptr, ptr %t1332, i32 0
  store ptr %t1333, ptr %t1334
  call void @__inc_ref(ptr %t1321)
  %t1335 = getelementptr ptr, ptr %t1332, i32 1
  store ptr %t1321, ptr %t1335
  call void @__inc_ref(ptr %t1323)
  %t1336 = getelementptr ptr, ptr %t1332, i32 2
  store ptr %t1323, ptr %t1336
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1329
reuse.join.1329:
  %t1337 = phi ptr [ %t5, %reuse.in_place.1327 ], [ %t1332, %reuse.copy.1328 ]
  %t1338 = call ptr @__alloc(i64 16, i32 1)
  %t1339 = inttoptr i64 178 to ptr
  %t1340 = getelementptr ptr, ptr %t1338, i32 0
  store ptr %t1339, ptr %t1340
  call void @__inc_ref(ptr %t6)
  %t1341 = getelementptr ptr, ptr %t1338, i32 1
  store ptr %t6, ptr %t1341
  call void @__free_recursive(ptr %t6)
  store ptr %t1337, ptr %t3
  store ptr %t1338, ptr %t4
  br label %tco.loop.0
tco.case.arm.94.1342:
  %t1343 = getelementptr ptr, ptr %t5, i32 1
  %t1344 = load ptr, ptr %t1343
  %t1345 = getelementptr ptr, ptr %t5, i32 2
  %t1346 = load ptr, ptr %t1345
  %t1347 = getelementptr i8, ptr %t5, i64 -8
  %t1348 = load i32, ptr %t1347
  %t1349 = icmp eq i32 %t1348, 1
  br i1 %t1349, label %reuse.in_place.1350, label %reuse.copy.1351
reuse.in_place.1350:
  %t1353 = inttoptr i64 69 to ptr
  %t1354 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1353, ptr %t1354
  br label %reuse.join.1352
reuse.copy.1351:
  %t1355 = call ptr @__alloc(i64 24, i32 2)
  %t1356 = inttoptr i64 69 to ptr
  %t1357 = getelementptr ptr, ptr %t1355, i32 0
  store ptr %t1356, ptr %t1357
  call void @__inc_ref(ptr %t1344)
  %t1358 = getelementptr ptr, ptr %t1355, i32 1
  store ptr %t1344, ptr %t1358
  call void @__inc_ref(ptr %t1346)
  %t1359 = getelementptr ptr, ptr %t1355, i32 2
  store ptr %t1346, ptr %t1359
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1352
reuse.join.1352:
  %t1360 = phi ptr [ %t5, %reuse.in_place.1350 ], [ %t1355, %reuse.copy.1351 ]
  %t1361 = call ptr @__alloc(i64 16, i32 1)
  %t1362 = inttoptr i64 179 to ptr
  %t1363 = getelementptr ptr, ptr %t1361, i32 0
  store ptr %t1362, ptr %t1363
  call void @__inc_ref(ptr %t6)
  %t1364 = getelementptr ptr, ptr %t1361, i32 1
  store ptr %t6, ptr %t1364
  call void @__free_recursive(ptr %t6)
  store ptr %t1360, ptr %t3
  store ptr %t1361, ptr %t4
  br label %tco.loop.0
tco.case.arm.95.1365:
  %t1366 = getelementptr ptr, ptr %t5, i32 1
  %t1367 = load ptr, ptr %t1366
  %t1368 = getelementptr ptr, ptr %t5, i32 2
  %t1369 = load ptr, ptr %t1368
  %t1370 = getelementptr i8, ptr %t5, i64 -8
  %t1371 = load i32, ptr %t1370
  %t1372 = icmp eq i32 %t1371, 1
  br i1 %t1372, label %reuse.in_place.1373, label %reuse.copy.1374
reuse.in_place.1373:
  %t1376 = inttoptr i64 69 to ptr
  %t1377 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1376, ptr %t1377
  br label %reuse.join.1375
reuse.copy.1374:
  %t1378 = call ptr @__alloc(i64 24, i32 2)
  %t1379 = inttoptr i64 69 to ptr
  %t1380 = getelementptr ptr, ptr %t1378, i32 0
  store ptr %t1379, ptr %t1380
  call void @__inc_ref(ptr %t1367)
  %t1381 = getelementptr ptr, ptr %t1378, i32 1
  store ptr %t1367, ptr %t1381
  call void @__inc_ref(ptr %t1369)
  %t1382 = getelementptr ptr, ptr %t1378, i32 2
  store ptr %t1369, ptr %t1382
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1375
reuse.join.1375:
  %t1383 = phi ptr [ %t5, %reuse.in_place.1373 ], [ %t1378, %reuse.copy.1374 ]
  %t1384 = call ptr @__alloc(i64 16, i32 1)
  %t1385 = inttoptr i64 180 to ptr
  %t1386 = getelementptr ptr, ptr %t1384, i32 0
  store ptr %t1385, ptr %t1386
  call void @__inc_ref(ptr %t6)
  %t1387 = getelementptr ptr, ptr %t1384, i32 1
  store ptr %t6, ptr %t1387
  call void @__free_recursive(ptr %t6)
  store ptr %t1383, ptr %t3
  store ptr %t1384, ptr %t4
  br label %tco.loop.0
tco.case.arm.96.1388:
  %t1389 = getelementptr ptr, ptr %t5, i32 1
  %t1390 = load ptr, ptr %t1389
  %t1391 = getelementptr ptr, ptr %t5, i32 2
  %t1392 = load ptr, ptr %t1391
  %t1393 = getelementptr i8, ptr %t5, i64 -8
  %t1394 = load i32, ptr %t1393
  %t1395 = icmp eq i32 %t1394, 1
  br i1 %t1395, label %reuse.in_place.1396, label %reuse.copy.1397
reuse.in_place.1396:
  %t1399 = inttoptr i64 69 to ptr
  %t1400 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1399, ptr %t1400
  br label %reuse.join.1398
reuse.copy.1397:
  %t1401 = call ptr @__alloc(i64 24, i32 2)
  %t1402 = inttoptr i64 69 to ptr
  %t1403 = getelementptr ptr, ptr %t1401, i32 0
  store ptr %t1402, ptr %t1403
  call void @__inc_ref(ptr %t1390)
  %t1404 = getelementptr ptr, ptr %t1401, i32 1
  store ptr %t1390, ptr %t1404
  call void @__inc_ref(ptr %t1392)
  %t1405 = getelementptr ptr, ptr %t1401, i32 2
  store ptr %t1392, ptr %t1405
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1398
reuse.join.1398:
  %t1406 = phi ptr [ %t5, %reuse.in_place.1396 ], [ %t1401, %reuse.copy.1397 ]
  %t1407 = call ptr @__alloc(i64 16, i32 1)
  %t1408 = inttoptr i64 181 to ptr
  %t1409 = getelementptr ptr, ptr %t1407, i32 0
  store ptr %t1408, ptr %t1409
  call void @__inc_ref(ptr %t6)
  %t1410 = getelementptr ptr, ptr %t1407, i32 1
  store ptr %t6, ptr %t1410
  call void @__free_recursive(ptr %t6)
  store ptr %t1406, ptr %t3
  store ptr %t1407, ptr %t4
  br label %tco.loop.0
tco.case.arm.97.1411:
  %t1412 = getelementptr ptr, ptr %t5, i32 1
  %t1413 = load ptr, ptr %t1412
  %t1414 = getelementptr ptr, ptr %t5, i32 2
  %t1415 = load ptr, ptr %t1414
  %t1416 = getelementptr i8, ptr %t5, i64 -8
  %t1417 = load i32, ptr %t1416
  %t1418 = icmp eq i32 %t1417, 1
  br i1 %t1418, label %reuse.in_place.1419, label %reuse.copy.1420
reuse.in_place.1419:
  %t1422 = inttoptr i64 69 to ptr
  %t1423 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1422, ptr %t1423
  br label %reuse.join.1421
reuse.copy.1420:
  %t1424 = call ptr @__alloc(i64 24, i32 2)
  %t1425 = inttoptr i64 69 to ptr
  %t1426 = getelementptr ptr, ptr %t1424, i32 0
  store ptr %t1425, ptr %t1426
  call void @__inc_ref(ptr %t1413)
  %t1427 = getelementptr ptr, ptr %t1424, i32 1
  store ptr %t1413, ptr %t1427
  call void @__inc_ref(ptr %t1415)
  %t1428 = getelementptr ptr, ptr %t1424, i32 2
  store ptr %t1415, ptr %t1428
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1421
reuse.join.1421:
  %t1429 = phi ptr [ %t5, %reuse.in_place.1419 ], [ %t1424, %reuse.copy.1420 ]
  %t1430 = call ptr @__alloc(i64 16, i32 1)
  %t1431 = inttoptr i64 182 to ptr
  %t1432 = getelementptr ptr, ptr %t1430, i32 0
  store ptr %t1431, ptr %t1432
  call void @__inc_ref(ptr %t6)
  %t1433 = getelementptr ptr, ptr %t1430, i32 1
  store ptr %t6, ptr %t1433
  call void @__free_recursive(ptr %t6)
  store ptr %t1429, ptr %t3
  store ptr %t1430, ptr %t4
  br label %tco.loop.0
tco.case.arm.98.1434:
  %t1435 = getelementptr ptr, ptr %t5, i32 1
  %t1436 = load ptr, ptr %t1435
  %t1437 = getelementptr ptr, ptr %t5, i32 2
  %t1438 = load ptr, ptr %t1437
  %t1439 = getelementptr i8, ptr %t5, i64 -8
  %t1440 = load i32, ptr %t1439
  %t1441 = icmp eq i32 %t1440, 1
  br i1 %t1441, label %reuse.in_place.1442, label %reuse.copy.1443
reuse.in_place.1442:
  %t1445 = inttoptr i64 69 to ptr
  %t1446 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1445, ptr %t1446
  br label %reuse.join.1444
reuse.copy.1443:
  %t1447 = call ptr @__alloc(i64 24, i32 2)
  %t1448 = inttoptr i64 69 to ptr
  %t1449 = getelementptr ptr, ptr %t1447, i32 0
  store ptr %t1448, ptr %t1449
  call void @__inc_ref(ptr %t1436)
  %t1450 = getelementptr ptr, ptr %t1447, i32 1
  store ptr %t1436, ptr %t1450
  call void @__inc_ref(ptr %t1438)
  %t1451 = getelementptr ptr, ptr %t1447, i32 2
  store ptr %t1438, ptr %t1451
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1444
reuse.join.1444:
  %t1452 = phi ptr [ %t5, %reuse.in_place.1442 ], [ %t1447, %reuse.copy.1443 ]
  %t1453 = call ptr @__alloc(i64 16, i32 1)
  %t1454 = inttoptr i64 183 to ptr
  %t1455 = getelementptr ptr, ptr %t1453, i32 0
  store ptr %t1454, ptr %t1455
  call void @__inc_ref(ptr %t6)
  %t1456 = getelementptr ptr, ptr %t1453, i32 1
  store ptr %t6, ptr %t1456
  call void @__free_recursive(ptr %t6)
  store ptr %t1452, ptr %t3
  store ptr %t1453, ptr %t4
  br label %tco.loop.0
tco.case.arm.99.1457:
  %t1458 = getelementptr ptr, ptr %t5, i32 1
  %t1459 = load ptr, ptr %t1458
  %t1460 = getelementptr ptr, ptr %t5, i32 2
  %t1461 = load ptr, ptr %t1460
  %t1462 = getelementptr i8, ptr %t5, i64 -8
  %t1463 = load i32, ptr %t1462
  %t1464 = icmp eq i32 %t1463, 1
  br i1 %t1464, label %reuse.in_place.1465, label %reuse.copy.1466
reuse.in_place.1465:
  %t1468 = inttoptr i64 69 to ptr
  %t1469 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1468, ptr %t1469
  br label %reuse.join.1467
reuse.copy.1466:
  %t1470 = call ptr @__alloc(i64 24, i32 2)
  %t1471 = inttoptr i64 69 to ptr
  %t1472 = getelementptr ptr, ptr %t1470, i32 0
  store ptr %t1471, ptr %t1472
  call void @__inc_ref(ptr %t1459)
  %t1473 = getelementptr ptr, ptr %t1470, i32 1
  store ptr %t1459, ptr %t1473
  call void @__inc_ref(ptr %t1461)
  %t1474 = getelementptr ptr, ptr %t1470, i32 2
  store ptr %t1461, ptr %t1474
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1467
reuse.join.1467:
  %t1475 = phi ptr [ %t5, %reuse.in_place.1465 ], [ %t1470, %reuse.copy.1466 ]
  %t1476 = call ptr @__alloc(i64 16, i32 1)
  %t1477 = inttoptr i64 184 to ptr
  %t1478 = getelementptr ptr, ptr %t1476, i32 0
  store ptr %t1477, ptr %t1478
  call void @__inc_ref(ptr %t6)
  %t1479 = getelementptr ptr, ptr %t1476, i32 1
  store ptr %t6, ptr %t1479
  call void @__free_recursive(ptr %t6)
  store ptr %t1475, ptr %t3
  store ptr %t1476, ptr %t4
  br label %tco.loop.0
tco.case.arm.100.1480:
  %t1481 = getelementptr ptr, ptr %t5, i32 1
  %t1482 = load ptr, ptr %t1481
  %t1483 = getelementptr ptr, ptr %t5, i32 2
  %t1484 = load ptr, ptr %t1483
  %t1485 = getelementptr i8, ptr %t5, i64 -8
  %t1486 = load i32, ptr %t1485
  %t1487 = icmp eq i32 %t1486, 1
  br i1 %t1487, label %reuse.in_place.1488, label %reuse.copy.1489
reuse.in_place.1488:
  %t1491 = inttoptr i64 69 to ptr
  %t1492 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1491, ptr %t1492
  br label %reuse.join.1490
reuse.copy.1489:
  %t1493 = call ptr @__alloc(i64 24, i32 2)
  %t1494 = inttoptr i64 69 to ptr
  %t1495 = getelementptr ptr, ptr %t1493, i32 0
  store ptr %t1494, ptr %t1495
  call void @__inc_ref(ptr %t1482)
  %t1496 = getelementptr ptr, ptr %t1493, i32 1
  store ptr %t1482, ptr %t1496
  call void @__inc_ref(ptr %t1484)
  %t1497 = getelementptr ptr, ptr %t1493, i32 2
  store ptr %t1484, ptr %t1497
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1490
reuse.join.1490:
  %t1498 = phi ptr [ %t5, %reuse.in_place.1488 ], [ %t1493, %reuse.copy.1489 ]
  %t1499 = call ptr @__alloc(i64 16, i32 1)
  %t1500 = inttoptr i64 185 to ptr
  %t1501 = getelementptr ptr, ptr %t1499, i32 0
  store ptr %t1500, ptr %t1501
  call void @__inc_ref(ptr %t6)
  %t1502 = getelementptr ptr, ptr %t1499, i32 1
  store ptr %t6, ptr %t1502
  call void @__free_recursive(ptr %t6)
  store ptr %t1498, ptr %t3
  store ptr %t1499, ptr %t4
  br label %tco.loop.0
tco.case.arm.101.1503:
  %t1504 = getelementptr ptr, ptr %t5, i32 1
  %t1505 = load ptr, ptr %t1504
  %t1506 = getelementptr ptr, ptr %t5, i32 2
  %t1507 = load ptr, ptr %t1506
  %t1508 = getelementptr i8, ptr %t5, i64 -8
  %t1509 = load i32, ptr %t1508
  %t1510 = icmp eq i32 %t1509, 1
  br i1 %t1510, label %reuse.in_place.1511, label %reuse.copy.1512
reuse.in_place.1511:
  %t1514 = inttoptr i64 69 to ptr
  %t1515 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1514, ptr %t1515
  br label %reuse.join.1513
reuse.copy.1512:
  %t1516 = call ptr @__alloc(i64 24, i32 2)
  %t1517 = inttoptr i64 69 to ptr
  %t1518 = getelementptr ptr, ptr %t1516, i32 0
  store ptr %t1517, ptr %t1518
  call void @__inc_ref(ptr %t1505)
  %t1519 = getelementptr ptr, ptr %t1516, i32 1
  store ptr %t1505, ptr %t1519
  call void @__inc_ref(ptr %t1507)
  %t1520 = getelementptr ptr, ptr %t1516, i32 2
  store ptr %t1507, ptr %t1520
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1513
reuse.join.1513:
  %t1521 = phi ptr [ %t5, %reuse.in_place.1511 ], [ %t1516, %reuse.copy.1512 ]
  %t1522 = call ptr @__alloc(i64 16, i32 1)
  %t1523 = inttoptr i64 186 to ptr
  %t1524 = getelementptr ptr, ptr %t1522, i32 0
  store ptr %t1523, ptr %t1524
  call void @__inc_ref(ptr %t6)
  %t1525 = getelementptr ptr, ptr %t1522, i32 1
  store ptr %t6, ptr %t1525
  call void @__free_recursive(ptr %t6)
  store ptr %t1521, ptr %t3
  store ptr %t1522, ptr %t4
  br label %tco.loop.0
tco.case.arm.102.1526:
  %t1527 = getelementptr ptr, ptr %t5, i32 1
  %t1528 = load ptr, ptr %t1527
  %t1529 = getelementptr ptr, ptr %t5, i32 2
  %t1530 = load ptr, ptr %t1529
  %t1531 = getelementptr i8, ptr %t5, i64 -8
  %t1532 = load i32, ptr %t1531
  %t1533 = icmp eq i32 %t1532, 1
  br i1 %t1533, label %reuse.in_place.1534, label %reuse.copy.1535
reuse.in_place.1534:
  %t1537 = inttoptr i64 69 to ptr
  %t1538 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1537, ptr %t1538
  br label %reuse.join.1536
reuse.copy.1535:
  %t1539 = call ptr @__alloc(i64 24, i32 2)
  %t1540 = inttoptr i64 69 to ptr
  %t1541 = getelementptr ptr, ptr %t1539, i32 0
  store ptr %t1540, ptr %t1541
  call void @__inc_ref(ptr %t1528)
  %t1542 = getelementptr ptr, ptr %t1539, i32 1
  store ptr %t1528, ptr %t1542
  call void @__inc_ref(ptr %t1530)
  %t1543 = getelementptr ptr, ptr %t1539, i32 2
  store ptr %t1530, ptr %t1543
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1536
reuse.join.1536:
  %t1544 = phi ptr [ %t5, %reuse.in_place.1534 ], [ %t1539, %reuse.copy.1535 ]
  %t1545 = call ptr @__alloc(i64 16, i32 1)
  %t1546 = inttoptr i64 187 to ptr
  %t1547 = getelementptr ptr, ptr %t1545, i32 0
  store ptr %t1546, ptr %t1547
  call void @__inc_ref(ptr %t6)
  %t1548 = getelementptr ptr, ptr %t1545, i32 1
  store ptr %t6, ptr %t1548
  call void @__free_recursive(ptr %t6)
  store ptr %t1544, ptr %t3
  store ptr %t1545, ptr %t4
  br label %tco.loop.0
tco.case.arm.105.1549:
  %t1550 = getelementptr ptr, ptr %t5, i32 1
  %t1551 = load ptr, ptr %t1550
  %t1552 = getelementptr ptr, ptr %t5, i32 2
  %t1553 = load ptr, ptr %t1552
  %t1554 = getelementptr i8, ptr %t5, i64 -8
  %t1555 = load i32, ptr %t1554
  %t1556 = icmp eq i32 %t1555, 1
  br i1 %t1556, label %reuse.in_place.1557, label %reuse.copy.1558
reuse.in_place.1557:
  %t1560 = inttoptr i64 69 to ptr
  %t1561 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1560, ptr %t1561
  br label %reuse.join.1559
reuse.copy.1558:
  %t1562 = call ptr @__alloc(i64 24, i32 2)
  %t1563 = inttoptr i64 69 to ptr
  %t1564 = getelementptr ptr, ptr %t1562, i32 0
  store ptr %t1563, ptr %t1564
  call void @__inc_ref(ptr %t1551)
  %t1565 = getelementptr ptr, ptr %t1562, i32 1
  store ptr %t1551, ptr %t1565
  call void @__inc_ref(ptr %t1553)
  %t1566 = getelementptr ptr, ptr %t1562, i32 2
  store ptr %t1553, ptr %t1566
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1559
reuse.join.1559:
  %t1567 = phi ptr [ %t5, %reuse.in_place.1557 ], [ %t1562, %reuse.copy.1558 ]
  %t1568 = call ptr @__alloc(i64 16, i32 1)
  %t1569 = inttoptr i64 190 to ptr
  %t1570 = getelementptr ptr, ptr %t1568, i32 0
  store ptr %t1569, ptr %t1570
  call void @__inc_ref(ptr %t6)
  %t1571 = getelementptr ptr, ptr %t1568, i32 1
  store ptr %t6, ptr %t1571
  call void @__free_recursive(ptr %t6)
  store ptr %t1567, ptr %t3
  store ptr %t1568, ptr %t4
  br label %tco.loop.0
tco.case.arm.106.1572:
  %t1573 = getelementptr ptr, ptr %t5, i32 1
  %t1574 = load ptr, ptr %t1573
  %t1575 = getelementptr ptr, ptr %t5, i32 2
  %t1576 = load ptr, ptr %t1575
  %t1577 = getelementptr i8, ptr %t5, i64 -8
  %t1578 = load i32, ptr %t1577
  %t1579 = icmp eq i32 %t1578, 1
  br i1 %t1579, label %reuse.in_place.1580, label %reuse.copy.1581
reuse.in_place.1580:
  %t1583 = inttoptr i64 69 to ptr
  %t1584 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1583, ptr %t1584
  br label %reuse.join.1582
reuse.copy.1581:
  %t1585 = call ptr @__alloc(i64 24, i32 2)
  %t1586 = inttoptr i64 69 to ptr
  %t1587 = getelementptr ptr, ptr %t1585, i32 0
  store ptr %t1586, ptr %t1587
  call void @__inc_ref(ptr %t1574)
  %t1588 = getelementptr ptr, ptr %t1585, i32 1
  store ptr %t1574, ptr %t1588
  call void @__inc_ref(ptr %t1576)
  %t1589 = getelementptr ptr, ptr %t1585, i32 2
  store ptr %t1576, ptr %t1589
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1582
reuse.join.1582:
  %t1590 = phi ptr [ %t5, %reuse.in_place.1580 ], [ %t1585, %reuse.copy.1581 ]
  %t1591 = call ptr @__alloc(i64 16, i32 1)
  %t1592 = inttoptr i64 191 to ptr
  %t1593 = getelementptr ptr, ptr %t1591, i32 0
  store ptr %t1592, ptr %t1593
  call void @__inc_ref(ptr %t6)
  %t1594 = getelementptr ptr, ptr %t1591, i32 1
  store ptr %t6, ptr %t1594
  call void @__free_recursive(ptr %t6)
  store ptr %t1590, ptr %t3
  store ptr %t1591, ptr %t4
  br label %tco.loop.0
tco.case.arm.107.1595:
  %t1596 = getelementptr ptr, ptr %t5, i32 1
  %t1597 = load ptr, ptr %t1596
  %t1598 = getelementptr ptr, ptr %t5, i32 2
  %t1599 = load ptr, ptr %t1598
  %t1600 = getelementptr i8, ptr %t5, i64 -8
  %t1601 = load i32, ptr %t1600
  %t1602 = icmp eq i32 %t1601, 1
  br i1 %t1602, label %reuse.in_place.1603, label %reuse.copy.1604
reuse.in_place.1603:
  %t1606 = inttoptr i64 69 to ptr
  %t1607 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1606, ptr %t1607
  br label %reuse.join.1605
reuse.copy.1604:
  %t1608 = call ptr @__alloc(i64 24, i32 2)
  %t1609 = inttoptr i64 69 to ptr
  %t1610 = getelementptr ptr, ptr %t1608, i32 0
  store ptr %t1609, ptr %t1610
  call void @__inc_ref(ptr %t1597)
  %t1611 = getelementptr ptr, ptr %t1608, i32 1
  store ptr %t1597, ptr %t1611
  call void @__inc_ref(ptr %t1599)
  %t1612 = getelementptr ptr, ptr %t1608, i32 2
  store ptr %t1599, ptr %t1612
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1605
reuse.join.1605:
  %t1613 = phi ptr [ %t5, %reuse.in_place.1603 ], [ %t1608, %reuse.copy.1604 ]
  %t1614 = call ptr @__alloc(i64 16, i32 1)
  %t1615 = inttoptr i64 192 to ptr
  %t1616 = getelementptr ptr, ptr %t1614, i32 0
  store ptr %t1615, ptr %t1616
  call void @__inc_ref(ptr %t6)
  %t1617 = getelementptr ptr, ptr %t1614, i32 1
  store ptr %t6, ptr %t1617
  call void @__free_recursive(ptr %t6)
  store ptr %t1613, ptr %t3
  store ptr %t1614, ptr %t4
  br label %tco.loop.0
tco.case.arm.108.1618:
  %t1619 = getelementptr ptr, ptr %t5, i32 1
  %t1620 = load ptr, ptr %t1619
  %t1621 = getelementptr ptr, ptr %t5, i32 2
  %t1622 = load ptr, ptr %t1621
  %t1623 = getelementptr i8, ptr %t5, i64 -8
  %t1624 = load i32, ptr %t1623
  %t1625 = icmp eq i32 %t1624, 1
  br i1 %t1625, label %reuse.in_place.1626, label %reuse.copy.1627
reuse.in_place.1626:
  %t1629 = inttoptr i64 69 to ptr
  %t1630 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1629, ptr %t1630
  br label %reuse.join.1628
reuse.copy.1627:
  %t1631 = call ptr @__alloc(i64 24, i32 2)
  %t1632 = inttoptr i64 69 to ptr
  %t1633 = getelementptr ptr, ptr %t1631, i32 0
  store ptr %t1632, ptr %t1633
  call void @__inc_ref(ptr %t1620)
  %t1634 = getelementptr ptr, ptr %t1631, i32 1
  store ptr %t1620, ptr %t1634
  call void @__inc_ref(ptr %t1622)
  %t1635 = getelementptr ptr, ptr %t1631, i32 2
  store ptr %t1622, ptr %t1635
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1628
reuse.join.1628:
  %t1636 = phi ptr [ %t5, %reuse.in_place.1626 ], [ %t1631, %reuse.copy.1627 ]
  %t1637 = call ptr @__alloc(i64 16, i32 1)
  %t1638 = inttoptr i64 193 to ptr
  %t1639 = getelementptr ptr, ptr %t1637, i32 0
  store ptr %t1638, ptr %t1639
  call void @__inc_ref(ptr %t6)
  %t1640 = getelementptr ptr, ptr %t1637, i32 1
  store ptr %t6, ptr %t1640
  call void @__free_recursive(ptr %t6)
  store ptr %t1636, ptr %t3
  store ptr %t1637, ptr %t4
  br label %tco.loop.0
tco.case.arm.109.1641:
  %t1642 = getelementptr ptr, ptr %t5, i32 1
  %t1643 = load ptr, ptr %t1642
  %t1644 = getelementptr ptr, ptr %t5, i32 2
  %t1645 = load ptr, ptr %t1644
  %t1646 = getelementptr i8, ptr %t5, i64 -8
  %t1647 = load i32, ptr %t1646
  %t1648 = icmp eq i32 %t1647, 1
  br i1 %t1648, label %reuse.in_place.1649, label %reuse.copy.1650
reuse.in_place.1649:
  %t1652 = inttoptr i64 69 to ptr
  %t1653 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1652, ptr %t1653
  br label %reuse.join.1651
reuse.copy.1650:
  %t1654 = call ptr @__alloc(i64 24, i32 2)
  %t1655 = inttoptr i64 69 to ptr
  %t1656 = getelementptr ptr, ptr %t1654, i32 0
  store ptr %t1655, ptr %t1656
  call void @__inc_ref(ptr %t1643)
  %t1657 = getelementptr ptr, ptr %t1654, i32 1
  store ptr %t1643, ptr %t1657
  call void @__inc_ref(ptr %t1645)
  %t1658 = getelementptr ptr, ptr %t1654, i32 2
  store ptr %t1645, ptr %t1658
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1651
reuse.join.1651:
  %t1659 = phi ptr [ %t5, %reuse.in_place.1649 ], [ %t1654, %reuse.copy.1650 ]
  %t1660 = call ptr @__alloc(i64 16, i32 1)
  %t1661 = inttoptr i64 194 to ptr
  %t1662 = getelementptr ptr, ptr %t1660, i32 0
  store ptr %t1661, ptr %t1662
  call void @__inc_ref(ptr %t6)
  %t1663 = getelementptr ptr, ptr %t1660, i32 1
  store ptr %t6, ptr %t1663
  call void @__free_recursive(ptr %t6)
  store ptr %t1659, ptr %t3
  store ptr %t1660, ptr %t4
  br label %tco.loop.0
tco.case.arm.110.1664:
  %t1665 = getelementptr ptr, ptr %t5, i32 1
  %t1666 = load ptr, ptr %t1665
  %t1667 = getelementptr ptr, ptr %t5, i32 2
  %t1668 = load ptr, ptr %t1667
  %t1669 = getelementptr i8, ptr %t5, i64 -8
  %t1670 = load i32, ptr %t1669
  %t1671 = icmp eq i32 %t1670, 1
  br i1 %t1671, label %reuse.in_place.1672, label %reuse.copy.1673
reuse.in_place.1672:
  %t1675 = inttoptr i64 69 to ptr
  %t1676 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1675, ptr %t1676
  br label %reuse.join.1674
reuse.copy.1673:
  %t1677 = call ptr @__alloc(i64 24, i32 2)
  %t1678 = inttoptr i64 69 to ptr
  %t1679 = getelementptr ptr, ptr %t1677, i32 0
  store ptr %t1678, ptr %t1679
  call void @__inc_ref(ptr %t1666)
  %t1680 = getelementptr ptr, ptr %t1677, i32 1
  store ptr %t1666, ptr %t1680
  call void @__inc_ref(ptr %t1668)
  %t1681 = getelementptr ptr, ptr %t1677, i32 2
  store ptr %t1668, ptr %t1681
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1674
reuse.join.1674:
  %t1682 = phi ptr [ %t5, %reuse.in_place.1672 ], [ %t1677, %reuse.copy.1673 ]
  %t1683 = call ptr @__alloc(i64 16, i32 1)
  %t1684 = inttoptr i64 195 to ptr
  %t1685 = getelementptr ptr, ptr %t1683, i32 0
  store ptr %t1684, ptr %t1685
  call void @__inc_ref(ptr %t6)
  %t1686 = getelementptr ptr, ptr %t1683, i32 1
  store ptr %t6, ptr %t1686
  call void @__free_recursive(ptr %t6)
  store ptr %t1682, ptr %t3
  store ptr %t1683, ptr %t4
  br label %tco.loop.0
tco.case.arm.111.1687:
  %t1688 = getelementptr ptr, ptr %t5, i32 1
  %t1689 = load ptr, ptr %t1688
  %t1690 = getelementptr ptr, ptr %t5, i32 2
  %t1691 = load ptr, ptr %t1690
  %t1692 = getelementptr i8, ptr %t5, i64 -8
  %t1693 = load i32, ptr %t1692
  %t1694 = icmp eq i32 %t1693, 1
  br i1 %t1694, label %reuse.in_place.1695, label %reuse.copy.1696
reuse.in_place.1695:
  %t1698 = inttoptr i64 69 to ptr
  %t1699 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t1698, ptr %t1699
  br label %reuse.join.1697
reuse.copy.1696:
  %t1700 = call ptr @__alloc(i64 24, i32 2)
  %t1701 = inttoptr i64 69 to ptr
  %t1702 = getelementptr ptr, ptr %t1700, i32 0
  store ptr %t1701, ptr %t1702
  call void @__inc_ref(ptr %t1689)
  %t1703 = getelementptr ptr, ptr %t1700, i32 1
  store ptr %t1689, ptr %t1703
  call void @__inc_ref(ptr %t1691)
  %t1704 = getelementptr ptr, ptr %t1700, i32 2
  store ptr %t1691, ptr %t1704
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.1697
reuse.join.1697:
  %t1705 = phi ptr [ %t5, %reuse.in_place.1695 ], [ %t1700, %reuse.copy.1696 ]
  %t1706 = call ptr @__alloc(i64 16, i32 1)
  %t1707 = inttoptr i64 196 to ptr
  %t1708 = getelementptr ptr, ptr %t1706, i32 0
  store ptr %t1707, ptr %t1708
  call void @__inc_ref(ptr %t6)
  %t1709 = getelementptr ptr, ptr %t1706, i32 1
  store ptr %t6, ptr %t1709
  call void @__free_recursive(ptr %t6)
  store ptr %t1705, ptr %t3
  store ptr %t1706, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t1710 = load ptr, ptr %t2
  ret ptr %t1710
}

define internal ptr @v__apply1(ptr %v__cl, ptr %v__arg0) {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 69 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  call void @__inc_ref(ptr %v__cl)
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v__cl, ptr %t3
  call void @__inc_ref(ptr %v__arg0)
  %t4 = getelementptr ptr, ptr %t0, i32 2
  store ptr %v__arg0, ptr %t4
  %t5 = call ptr @v__scc__apply1__df__lam_10_10__df__lam_10_19__df__lam_11_11__df__lam_11_20__df__lam_22_13__df__lam_23_14__df__lam_31_22__df__lam_32_23__df__lam_4_25__df__lam_4_28__df__lam_4_31__df__lam_4_34__df__lam_4_37__df__lam_4_40__df__lam_4_43__df__lam_5_26__df__lam_5_29__df__lam_5_32__df__lam_5_35__df__lam_5_38__df__lam_5_41__df__lam_5_44__df__lam_6_16__df__lam_7_17__df__lam_8_1__df__lam_8_4__df__lam_8_7__df__lam_9_2__df__lam_9_5__df__lam_9_8__lift_17__lift_18__lift_2__lift_20__lift_21__lift_26__lift_27__lift_29__lift_3__lift_30__lift_37__lift_38(ptr %t0)
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
