; External C declarations
declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare ptr @memcpy(ptr, ptr, i64)
declare i64 @write(i32, ptr, i64)
declare i64 @strlen(ptr)
declare i32 @snprintf(ptr, i64, ptr, ...)
declare {i32, i1} @llvm.sadd.with.overflow.i32(i32, i32)

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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [24 x i8]} { i32 0, i32 0, i32 0, i32 24, i32 24, [24 x i8] c"UNPAIRED_UTF16_SURROGATE" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [11 x i8]} { i32 0, i32 0, i32 0, i32 11, i32 11, [11 x i8] c"PARSE_ERROR" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [6 x i8]} { i32 0, i32 0, i32 0, i32 6, i32 6, [6 x i8] c"NO_ARG" }

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


define internal ptr @__addInt32(ptr %pa, ptr %pb) {
  %a = load i32, ptr %pa
  %b = load i32, ptr %pb
  %res = call {i32, i1} @llvm.sadd.with.overflow.i32(i32 %a, i32 %b)
  %sum = extractvalue {i32, i1} %res, 0
  %ovf = extractvalue {i32, i1} %res, 1
  br i1 %ovf, label %err, label %ok
err:
  %is_pos = icmp sge i32 %a, 0
  %row_tag_idx = select i1 %is_pos, i64 882564211, i64 3768445577
  %inner_tag_idx = select i1 %is_pos, i64 18, i64 17
  %inner = call ptr @__alloc(i64 8, i32 0)
  %inner_tag = inttoptr i64 %inner_tag_idx to ptr
  store ptr %inner_tag, ptr %inner
  %row = call ptr @__alloc(i64 16, i32 1)
  %row_tag = inttoptr i64 %row_tag_idx to ptr
  store ptr %row_tag, ptr %row
  %row_f = getelementptr ptr, ptr %row, i32 1
  store ptr %inner, ptr %row_f
  %left = call ptr @__alloc(i64 16, i32 1)
  %left_tag = inttoptr i64 3 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %row, ptr %left_f
  br label %join
ok:
  %box = call ptr @__alloc(i64 4, i32 0)
  store i32 %sum, ptr %box
  %right = call ptr @__alloc(i64 16, i32 1)
  %right_tag = inttoptr i64 4 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %box, ptr %right_f
  br label %join
join:
  %result = phi ptr [ %left, %err ], [ %right, %ok ]
  call void @__free_recursive(ptr %pa)
  call void @__free_recursive(ptr %pb)
  ret ptr %result
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
  switch i64 %t7, label %tco.case.default.8 [ i64 5, label %tco.case.arm.5.9 i64 7, label %tco.case.arm.7.12 i64 8, label %tco.case.arm.8.18 ]
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
  %t15 = call ptr @__print(ptr %t14)
  %t16 = getelementptr ptr, ptr %t4, i32 2
  %t17 = load ptr, ptr %t16
  call void @__inc_ref(ptr %t17)
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t15)
  store ptr %t17, ptr %t3
  br label %tco.loop.0
tco.case.arm.8.18:
  %t19 = call ptr @__getArgs()
  %t20 = call ptr @__alloc(i64 24, i32 2)
  %t21 = inttoptr i64 29 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = getelementptr ptr, ptr %t4, i32 1
  %t24 = load ptr, ptr %t23
  call void @__inc_ref(ptr %t24)
  %t25 = getelementptr ptr, ptr %t20, i32 1
  store ptr %t24, ptr %t25
  call void @__inc_ref(ptr %t19)
  %t26 = getelementptr ptr, ptr %t20, i32 2
  store ptr %t19, ptr %t26
  %t27 = call ptr @__alloc(i64 8, i32 0)
  %t28 = inttoptr i64 39 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  %t30 = call ptr @v__cps__scc__apply1__df__lam_14_5__df__lam_17_9__df__lam_9_1(ptr %t20, ptr %t27)
  call void @__free_recursive(ptr %t19)
  call void @__free_recursive(ptr %t4)
  store ptr %t30, ptr %t3
  br label %tco.loop.0
tco.case.default.8:
  unreachable
tco.exit.1:
  %t31 = load ptr, ptr %t2
  ret ptr %t31
}

define internal ptr @v_main() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 8 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 8, i32 0)
  %t4 = inttoptr i64 28 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  %t7 = call ptr @__alloc(i64 8, i32 0)
  %t8 = inttoptr i64 37 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = call ptr @v__cps__df__rowmono_1_andThenIO_8(ptr %t0, ptr %t7)
  %t11 = call ptr @__alloc(i64 8, i32 0)
  %t12 = inttoptr i64 35 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  %t14 = call ptr @v__cps__df__rowmono_0_andThenIO_4(ptr %t10, ptr %t11)
  %t15 = call ptr @__alloc(i64 8, i32 0)
  %t16 = inttoptr i64 33 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = call ptr @v__cps__df_handleErrorIO_0(ptr %t14, ptr %t15)
  ret ptr %t18
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.13 i64 7, label %tco.case.arm.7.79 i64 8, label %tco.case.arm.8.104 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t12 = call ptr @v__apply__df_handleErrorIO_0(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t12, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.13:
  call void @__inc_ref(ptr %t6)
  %t14 = getelementptr ptr, ptr %t5, i32 1
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  %t16 = getelementptr ptr, ptr %t15, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %case.default.19 [ i64 502975519, label %case.arm.502975519.21 i64 589989748, label %case.arm.589989748.35 i64 2448244154, label %case.arm.2448244154.49 i64 3864168810, label %case.arm.3864168810.63 ]
case.arm.502975519.21:
  %t23 = call ptr @__alloc(i64 24, i32 2)
  %t24 = inttoptr i64 7 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  %t26 = getelementptr ptr, ptr %t23, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t26
  %t27 = call ptr @__alloc(i64 16, i32 1)
  %t28 = inttoptr i64 5 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  %t30 = call ptr @__alloc(i64 8, i32 0)
  %t31 = inttoptr i64 0 to ptr
  %t32 = getelementptr ptr, ptr %t30, i32 0
  store ptr %t31, ptr %t32
  %t33 = getelementptr ptr, ptr %t27, i32 1
  store ptr %t30, ptr %t33
  %t34 = getelementptr ptr, ptr %t23, i32 2
  store ptr %t27, ptr %t34
  br label %case.end.502975519.22
case.end.502975519.22:
  br label %case.join.20
case.arm.589989748.35:
  %t37 = call ptr @__alloc(i64 24, i32 2)
  %t38 = inttoptr i64 7 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = getelementptr ptr, ptr %t37, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t40
  %t41 = call ptr @__alloc(i64 16, i32 1)
  %t42 = inttoptr i64 5 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = call ptr @__alloc(i64 8, i32 0)
  %t45 = inttoptr i64 0 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  %t47 = getelementptr ptr, ptr %t41, i32 1
  store ptr %t44, ptr %t47
  %t48 = getelementptr ptr, ptr %t37, i32 2
  store ptr %t41, ptr %t48
  br label %case.end.589989748.36
case.end.589989748.36:
  br label %case.join.20
case.arm.2448244154.49:
  %t51 = call ptr @__alloc(i64 24, i32 2)
  %t52 = inttoptr i64 7 to ptr
  %t53 = getelementptr ptr, ptr %t51, i32 0
  store ptr %t52, ptr %t53
  %t54 = getelementptr ptr, ptr %t51, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t54
  %t55 = call ptr @__alloc(i64 16, i32 1)
  %t56 = inttoptr i64 5 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  %t58 = call ptr @__alloc(i64 8, i32 0)
  %t59 = inttoptr i64 0 to ptr
  %t60 = getelementptr ptr, ptr %t58, i32 0
  store ptr %t59, ptr %t60
  %t61 = getelementptr ptr, ptr %t55, i32 1
  store ptr %t58, ptr %t61
  %t62 = getelementptr ptr, ptr %t51, i32 2
  store ptr %t55, ptr %t62
  br label %case.end.2448244154.50
case.end.2448244154.50:
  br label %case.join.20
case.arm.3864168810.63:
  %t65 = call ptr @__alloc(i64 24, i32 2)
  %t66 = inttoptr i64 7 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  %t68 = getelementptr ptr, ptr %t65, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t68
  %t69 = call ptr @__alloc(i64 16, i32 1)
  %t70 = inttoptr i64 5 to ptr
  %t71 = getelementptr ptr, ptr %t69, i32 0
  store ptr %t70, ptr %t71
  %t72 = call ptr @__alloc(i64 8, i32 0)
  %t73 = inttoptr i64 0 to ptr
  %t74 = getelementptr ptr, ptr %t72, i32 0
  store ptr %t73, ptr %t74
  %t75 = getelementptr ptr, ptr %t69, i32 1
  store ptr %t72, ptr %t75
  %t76 = getelementptr ptr, ptr %t65, i32 2
  store ptr %t69, ptr %t76
  br label %case.end.3864168810.64
case.end.3864168810.64:
  br label %case.join.20
case.default.19:
  unreachable
case.join.20:
  %t77 = phi ptr [ %t23, %case.end.502975519.22 ], [ %t37, %case.end.589989748.36 ], [ %t51, %case.end.2448244154.50 ], [ %t65, %case.end.3864168810.64 ]
  call void @__free_recursive(ptr %t15)
  %t78 = call ptr @v__apply__df_handleErrorIO_0(ptr %t6, ptr %t77)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t78, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.79:
  %t80 = getelementptr ptr, ptr %t5, i32 1
  %t81 = load ptr, ptr %t80
  %t82 = getelementptr ptr, ptr %t5, i32 2
  %t83 = load ptr, ptr %t82
  call void @__inc_ref(ptr %t83)
  %t90 = getelementptr i8, ptr %t5, i64 -8
  %t91 = load i32, ptr %t90
  %t92 = icmp eq i32 %t91, 1
  br i1 %t92, label %reuse.in_place.93, label %reuse.copy.94
reuse.in_place.93:
  %t84 = getelementptr ptr, ptr %t5, i32 2
  %t85 = load ptr, ptr %t84
  call void @__free_recursive(ptr %t85)
  %t88 = inttoptr i64 34 to ptr
  %t89 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t88, ptr %t89
  call void @__inc_ref(ptr %t6)
  %t86 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t86
  %t87 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t81, ptr %t87
  br label %reuse.in_place.end.96
reuse.in_place.end.96:
  br label %reuse.join.95
reuse.copy.94:
  %t98 = call ptr @__alloc(i64 24, i32 2)
  %t99 = inttoptr i64 34 to ptr
  %t100 = getelementptr ptr, ptr %t98, i32 0
  store ptr %t99, ptr %t100
  call void @__inc_ref(ptr %t6)
  %t101 = getelementptr ptr, ptr %t98, i32 1
  store ptr %t6, ptr %t101
  call void @__inc_ref(ptr %t81)
  %t102 = getelementptr ptr, ptr %t98, i32 2
  store ptr %t81, ptr %t102
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.97
reuse.copy.end.97:
  br label %reuse.join.95
reuse.join.95:
  %t103 = phi ptr [ %t5, %reuse.in_place.end.96 ], [ %t98, %reuse.copy.end.97 ]
  call void @__inc_ref(ptr %t83)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t83)
  store ptr %t83, ptr %t3
  store ptr %t103, ptr %t4
  br label %tco.loop.0
tco.case.arm.8.104:
  %t105 = getelementptr ptr, ptr %t5, i32 1
  %t106 = load ptr, ptr %t105
  call void @__inc_ref(ptr %t106)
  call void @__inc_ref(ptr %t6)
  %t107 = call ptr @__alloc(i64 16, i32 1)
  %t108 = inttoptr i64 8 to ptr
  %t109 = getelementptr ptr, ptr %t107, i32 0
  store ptr %t108, ptr %t109
  %t110 = call ptr @__alloc(i64 16, i32 1)
  %t111 = inttoptr i64 27 to ptr
  %t112 = getelementptr ptr, ptr %t110, i32 0
  store ptr %t111, ptr %t112
  call void @__inc_ref(ptr %t106)
  %t113 = getelementptr ptr, ptr %t110, i32 1
  store ptr %t106, ptr %t113
  %t114 = getelementptr ptr, ptr %t107, i32 1
  store ptr %t110, ptr %t114
  %t115 = call ptr @v__apply__df_handleErrorIO_0(ptr %t6, ptr %t107)
  call void @__free_recursive(ptr %t106)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t115, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t116 = load ptr, ptr %t2
  ret ptr %t116
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
  switch i64 %t9, label %tco.case.default.10 [ i64 33, label %tco.case.arm.33.11 i64 34, label %tco.case.arm.34.12 ]
tco.case.arm.33.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.34.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  %t15 = getelementptr ptr, ptr %t5, i32 2
  %t16 = load ptr, ptr %t15
  %t17 = getelementptr ptr, ptr %t5, i32 1
  %t18 = load ptr, ptr %t17
  call void @__free_recursive(ptr %t18)
  %t21 = inttoptr i64 7 to ptr
  %t22 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t21, ptr %t22
  %t19 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t16, ptr %t19
  call void @__inc_ref(ptr %t6)
  %t20 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t6, ptr %t20
  call void @__inc_ref(ptr %t14)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t14)
  store ptr %t14, ptr %t3
  store ptr %t5, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t23 = load ptr, ptr %t2
  ret ptr %t23
}

define internal ptr @v__cps__df__rowmono_0_andThenIO_4(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.27 i64 7, label %tco.case.arm.7.29 i64 8, label %tco.case.arm.8.54 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t5, i32 1
  %t16 = load ptr, ptr %t15
  call void @__inc_ref(ptr %t16)
  %t17 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t16, ptr %t17
  %t18 = call ptr @__alloc(i64 16, i32 1)
  %t19 = inttoptr i64 5 to ptr
  %t20 = getelementptr ptr, ptr %t18, i32 0
  store ptr %t19, ptr %t20
  %t21 = call ptr @__alloc(i64 8, i32 0)
  %t22 = inttoptr i64 0 to ptr
  %t23 = getelementptr ptr, ptr %t21, i32 0
  store ptr %t22, ptr %t23
  %t24 = getelementptr ptr, ptr %t18, i32 1
  store ptr %t21, ptr %t24
  %t25 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t18, ptr %t25
  %t26 = call ptr @v__apply__df__rowmono_0_andThenIO_4(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t26, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.27:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t28 = call ptr @v__apply__df__rowmono_0_andThenIO_4(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t28, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.29:
  %t30 = getelementptr ptr, ptr %t5, i32 1
  %t31 = load ptr, ptr %t30
  %t32 = getelementptr ptr, ptr %t5, i32 2
  %t33 = load ptr, ptr %t32
  call void @__inc_ref(ptr %t33)
  %t40 = getelementptr i8, ptr %t5, i64 -8
  %t41 = load i32, ptr %t40
  %t42 = icmp eq i32 %t41, 1
  br i1 %t42, label %reuse.in_place.43, label %reuse.copy.44
reuse.in_place.43:
  %t34 = getelementptr ptr, ptr %t5, i32 2
  %t35 = load ptr, ptr %t34
  call void @__free_recursive(ptr %t35)
  %t38 = inttoptr i64 36 to ptr
  %t39 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t38, ptr %t39
  call void @__inc_ref(ptr %t6)
  %t36 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t36
  %t37 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t31, ptr %t37
  br label %reuse.in_place.end.46
reuse.in_place.end.46:
  br label %reuse.join.45
reuse.copy.44:
  %t48 = call ptr @__alloc(i64 24, i32 2)
  %t49 = inttoptr i64 36 to ptr
  %t50 = getelementptr ptr, ptr %t48, i32 0
  store ptr %t49, ptr %t50
  call void @__inc_ref(ptr %t6)
  %t51 = getelementptr ptr, ptr %t48, i32 1
  store ptr %t6, ptr %t51
  call void @__inc_ref(ptr %t31)
  %t52 = getelementptr ptr, ptr %t48, i32 2
  store ptr %t31, ptr %t52
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.47
reuse.copy.end.47:
  br label %reuse.join.45
reuse.join.45:
  %t53 = phi ptr [ %t5, %reuse.in_place.end.46 ], [ %t48, %reuse.copy.end.47 ]
  call void @__inc_ref(ptr %t33)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t33)
  store ptr %t33, ptr %t3
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
  %t61 = inttoptr i64 25 to ptr
  %t62 = getelementptr ptr, ptr %t60, i32 0
  store ptr %t61, ptr %t62
  call void @__inc_ref(ptr %t56)
  %t63 = getelementptr ptr, ptr %t60, i32 1
  store ptr %t56, ptr %t63
  %t64 = getelementptr ptr, ptr %t57, i32 1
  store ptr %t60, ptr %t64
  %t65 = call ptr @v__apply__df__rowmono_0_andThenIO_4(ptr %t6, ptr %t57)
  call void @__free_recursive(ptr %t56)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t65, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t66 = load ptr, ptr %t2
  ret ptr %t66
}

define internal ptr @v__apply__df__rowmono_0_andThenIO_4(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 35, label %tco.case.arm.35.11 i64 36, label %tco.case.arm.36.12 ]
tco.case.arm.35.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.36.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  %t15 = getelementptr ptr, ptr %t5, i32 2
  %t16 = load ptr, ptr %t15
  %t17 = getelementptr ptr, ptr %t5, i32 1
  %t18 = load ptr, ptr %t17
  call void @__free_recursive(ptr %t18)
  %t21 = inttoptr i64 7 to ptr
  %t22 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t21, ptr %t22
  %t19 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t16, ptr %t19
  call void @__inc_ref(ptr %t6)
  %t20 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t6, ptr %t20
  call void @__inc_ref(ptr %t14)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t14)
  store ptr %t14, ptr %t3
  store ptr %t5, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t23 = load ptr, ptr %t2
  ret ptr %t23
}

define internal ptr @v__cps__df__rowmono_1_andThenIO_8(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.138 i64 7, label %tco.case.arm.7.140 i64 8, label %tco.case.arm.8.165 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t13, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %case.default.17 [ i64 13, label %case.arm.13.19 i64 14, label %case.arm.14.32 ]
case.arm.13.19:
  %t21 = call ptr @__alloc(i64 16, i32 1)
  %t22 = inttoptr i64 3 to ptr
  %t23 = getelementptr ptr, ptr %t21, i32 0
  store ptr %t22, ptr %t23
  %t24 = call ptr @__alloc(i64 16, i32 1)
  %t25 = inttoptr i64 3864168810 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @__alloc(i64 8, i32 0)
  %t28 = inttoptr i64 24 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  %t30 = getelementptr ptr, ptr %t24, i32 1
  store ptr %t27, ptr %t30
  %t31 = getelementptr ptr, ptr %t21, i32 1
  store ptr %t24, ptr %t31
  br label %case.end.13.20
case.end.13.20:
  br label %case.join.18
case.arm.14.32:
  %t34 = call ptr @__alloc(i64 16, i32 1)
  %t35 = inttoptr i64 4 to ptr
  %t36 = getelementptr ptr, ptr %t34, i32 0
  store ptr %t35, ptr %t36
  %t37 = call ptr @__alloc(i64 32, i32 3)
  %t38 = inttoptr i64 16 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = call ptr @__alloc(i64 4, i32 0)
  store i32 1, ptr %t40
  %t41 = getelementptr ptr, ptr %t37, i32 1
  store ptr %t40, ptr %t41
  %t42 = call ptr @__alloc(i64 4, i32 0)
  store i32 2, ptr %t42
  %t43 = getelementptr ptr, ptr %t37, i32 2
  store ptr %t42, ptr %t43
  %t44 = call ptr @__alloc(i64 4, i32 0)
  store i32 3, ptr %t44
  %t45 = getelementptr ptr, ptr %t37, i32 3
  store ptr %t44, ptr %t45
  %t46 = getelementptr ptr, ptr %t34, i32 1
  store ptr %t37, ptr %t46
  %t47 = getelementptr ptr, ptr %t34, i32 0
  %t48 = load ptr, ptr %t47
  %t49 = ptrtoint ptr %t48 to i64
  switch i64 %t49, label %case.default.50 [ i64 3, label %case.arm.3.52 i64 4, label %case.arm.4.64 ]
case.arm.3.52:
  %t54 = getelementptr ptr, ptr %t34, i32 1
  %t55 = load ptr, ptr %t54
  call void @__inc_ref(ptr %t55)
  %t56 = call ptr @__alloc(i64 16, i32 1)
  %t57 = inttoptr i64 3 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  %t59 = call ptr @__alloc(i64 16, i32 1)
  %t60 = inttoptr i64 2448244154 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  call void @__inc_ref(ptr %t55)
  %t62 = getelementptr ptr, ptr %t59, i32 1
  store ptr %t55, ptr %t62
  %t63 = getelementptr ptr, ptr %t56, i32 1
  store ptr %t59, ptr %t63
  call void @__free_recursive(ptr %t55)
  br label %case.end.3.53
case.end.3.53:
  br label %case.join.51
case.arm.4.64:
  %t66 = getelementptr ptr, ptr %t34, i32 1
  %t67 = load ptr, ptr %t66
  call void @__inc_ref(ptr %t67)
  %t68 = getelementptr ptr, ptr %t67, i32 0
  %t69 = load ptr, ptr %t68
  %t70 = ptrtoint ptr %t69 to i64
  switch i64 %t70, label %case.default.71 [ i64 16, label %case.arm.16.73 ]
case.arm.16.73:
  %t75 = getelementptr ptr, ptr %t67, i32 3
  %t76 = load ptr, ptr %t75
  call void @__inc_ref(ptr %t76)
  %t77 = call ptr @__alloc(i64 16, i32 1)
  %t78 = inttoptr i64 4 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  %t80 = getelementptr ptr, ptr %t67, i32 1
  %t81 = load ptr, ptr %t80
  call void @__inc_ref(ptr %t81)
  %t82 = getelementptr ptr, ptr %t67, i32 2
  %t83 = load ptr, ptr %t82
  call void @__inc_ref(ptr %t83)
  %t84 = call ptr @__addInt32(ptr %t81, ptr %t83)
  %t85 = getelementptr ptr, ptr %t84, i32 0
  %t86 = load ptr, ptr %t85
  %t87 = ptrtoint ptr %t86 to i64
  switch i64 %t87, label %case.default.88 [ i64 3, label %case.arm.3.90 i64 4, label %case.arm.4.92 ]
case.arm.3.90:
  call void @__inc_ref(ptr %t76)
  br label %case.end.3.91
case.end.3.91:
  br label %case.join.89
case.arm.4.92:
  %t94 = getelementptr ptr, ptr %t84, i32 1
  %t95 = load ptr, ptr %t94
  call void @__inc_ref(ptr %t95)
  call void @__inc_ref(ptr %t95)
  call void @__inc_ref(ptr %t76)
  %t96 = call ptr @__addInt32(ptr %t95, ptr %t76)
  %t97 = getelementptr ptr, ptr %t96, i32 0
  %t98 = load ptr, ptr %t97
  %t99 = ptrtoint ptr %t98 to i64
  switch i64 %t99, label %case.default.100 [ i64 3, label %case.arm.3.102 i64 4, label %case.arm.4.104 ]
case.arm.3.102:
  call void @__inc_ref(ptr %t76)
  br label %case.end.3.103
case.end.3.103:
  br label %case.join.101
case.arm.4.104:
  %t106 = getelementptr ptr, ptr %t96, i32 1
  %t107 = load ptr, ptr %t106
  call void @__inc_ref(ptr %t107)
  call void @__inc_ref(ptr %t107)
  call void @__free_recursive(ptr %t107)
  br label %case.end.4.105
case.end.4.105:
  br label %case.join.101
case.default.100:
  unreachable
case.join.101:
  %t108 = phi ptr [ %t76, %case.end.3.103 ], [ %t107, %case.end.4.105 ]
  call void @__free_recursive(ptr %t96)
  call void @__free_recursive(ptr %t95)
  br label %case.end.4.93
case.end.4.93:
  br label %case.join.89
case.default.88:
  unreachable
case.join.89:
  %t109 = phi ptr [ %t76, %case.end.3.91 ], [ %t108, %case.end.4.93 ]
  call void @__free_recursive(ptr %t84)
  %t110 = call ptr @__showInt32(ptr %t109)
  %t111 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t110, ptr %t111
  call void @__free_recursive(ptr %t76)
  br label %case.end.16.74
case.end.16.74:
  br label %case.join.72
case.default.71:
  unreachable
case.join.72:
  %t112 = phi ptr [ %t77, %case.end.16.74 ]
  call void @__free_recursive(ptr %t67)
  br label %case.end.4.65
case.end.4.65:
  br label %case.join.51
case.default.50:
  unreachable
case.join.51:
  %t113 = phi ptr [ %t56, %case.end.3.53 ], [ %t112, %case.end.4.65 ]
  call void @__free_recursive(ptr %t34)
  br label %case.end.14.33
case.end.14.33:
  br label %case.join.18
case.default.17:
  unreachable
case.join.18:
  %t114 = phi ptr [ %t21, %case.end.13.20 ], [ %t113, %case.end.14.33 ]
  call void @__free_recursive(ptr %t13)
  %t115 = getelementptr ptr, ptr %t114, i32 0
  %t116 = load ptr, ptr %t115
  %t117 = ptrtoint ptr %t116 to i64
  switch i64 %t117, label %case.default.118 [ i64 3, label %case.arm.3.120 i64 4, label %case.arm.4.128 ]
case.arm.3.120:
  %t122 = call ptr @__alloc(i64 16, i32 1)
  %t123 = inttoptr i64 6 to ptr
  %t124 = getelementptr ptr, ptr %t122, i32 0
  store ptr %t123, ptr %t124
  %t125 = getelementptr ptr, ptr %t114, i32 1
  %t126 = load ptr, ptr %t125
  call void @__inc_ref(ptr %t126)
  %t127 = getelementptr ptr, ptr %t122, i32 1
  store ptr %t126, ptr %t127
  br label %case.end.3.121
case.end.3.121:
  br label %case.join.119
case.arm.4.128:
  %t130 = call ptr @__alloc(i64 16, i32 1)
  %t131 = inttoptr i64 5 to ptr
  %t132 = getelementptr ptr, ptr %t130, i32 0
  store ptr %t131, ptr %t132
  %t133 = getelementptr ptr, ptr %t114, i32 1
  %t134 = load ptr, ptr %t133
  call void @__inc_ref(ptr %t134)
  %t135 = getelementptr ptr, ptr %t130, i32 1
  store ptr %t134, ptr %t135
  br label %case.end.4.129
case.end.4.129:
  br label %case.join.119
case.default.118:
  unreachable
case.join.119:
  %t136 = phi ptr [ %t122, %case.end.3.121 ], [ %t130, %case.end.4.129 ]
  call void @__free_recursive(ptr %t114)
  %t137 = call ptr @v__apply__df__rowmono_1_andThenIO_8(ptr %t6, ptr %t136)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t137, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.138:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t139 = call ptr @v__apply__df__rowmono_1_andThenIO_8(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t139, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.140:
  %t141 = getelementptr ptr, ptr %t5, i32 1
  %t142 = load ptr, ptr %t141
  %t143 = getelementptr ptr, ptr %t5, i32 2
  %t144 = load ptr, ptr %t143
  call void @__inc_ref(ptr %t144)
  %t151 = getelementptr i8, ptr %t5, i64 -8
  %t152 = load i32, ptr %t151
  %t153 = icmp eq i32 %t152, 1
  br i1 %t153, label %reuse.in_place.154, label %reuse.copy.155
reuse.in_place.154:
  %t145 = getelementptr ptr, ptr %t5, i32 2
  %t146 = load ptr, ptr %t145
  call void @__free_recursive(ptr %t146)
  %t149 = inttoptr i64 38 to ptr
  %t150 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t149, ptr %t150
  call void @__inc_ref(ptr %t6)
  %t147 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t147
  %t148 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t142, ptr %t148
  br label %reuse.in_place.end.157
reuse.in_place.end.157:
  br label %reuse.join.156
reuse.copy.155:
  %t159 = call ptr @__alloc(i64 24, i32 2)
  %t160 = inttoptr i64 38 to ptr
  %t161 = getelementptr ptr, ptr %t159, i32 0
  store ptr %t160, ptr %t161
  call void @__inc_ref(ptr %t6)
  %t162 = getelementptr ptr, ptr %t159, i32 1
  store ptr %t6, ptr %t162
  call void @__inc_ref(ptr %t142)
  %t163 = getelementptr ptr, ptr %t159, i32 2
  store ptr %t142, ptr %t163
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.158
reuse.copy.end.158:
  br label %reuse.join.156
reuse.join.156:
  %t164 = phi ptr [ %t5, %reuse.in_place.end.157 ], [ %t159, %reuse.copy.end.158 ]
  call void @__inc_ref(ptr %t144)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t144)
  store ptr %t144, ptr %t3
  store ptr %t164, ptr %t4
  br label %tco.loop.0
tco.case.arm.8.165:
  %t166 = getelementptr ptr, ptr %t5, i32 1
  %t167 = load ptr, ptr %t166
  call void @__inc_ref(ptr %t167)
  call void @__inc_ref(ptr %t6)
  %t168 = call ptr @__alloc(i64 16, i32 1)
  %t169 = inttoptr i64 8 to ptr
  %t170 = getelementptr ptr, ptr %t168, i32 0
  store ptr %t169, ptr %t170
  %t171 = call ptr @__alloc(i64 16, i32 1)
  %t172 = inttoptr i64 26 to ptr
  %t173 = getelementptr ptr, ptr %t171, i32 0
  store ptr %t172, ptr %t173
  call void @__inc_ref(ptr %t167)
  %t174 = getelementptr ptr, ptr %t171, i32 1
  store ptr %t167, ptr %t174
  %t175 = getelementptr ptr, ptr %t168, i32 1
  store ptr %t171, ptr %t175
  %t176 = call ptr @v__apply__df__rowmono_1_andThenIO_8(ptr %t6, ptr %t168)
  call void @__free_recursive(ptr %t167)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t176, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t177 = load ptr, ptr %t2
  ret ptr %t177
}

define internal ptr @v__apply__df__rowmono_1_andThenIO_8(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 37, label %tco.case.arm.37.11 i64 38, label %tco.case.arm.38.12 ]
tco.case.arm.37.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.38.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  %t15 = getelementptr ptr, ptr %t5, i32 2
  %t16 = load ptr, ptr %t15
  %t17 = getelementptr ptr, ptr %t5, i32 1
  %t18 = load ptr, ptr %t17
  call void @__free_recursive(ptr %t18)
  %t21 = inttoptr i64 7 to ptr
  %t22 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t21, ptr %t22
  %t19 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t16, ptr %t19
  call void @__inc_ref(ptr %t6)
  %t20 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t6, ptr %t20
  call void @__inc_ref(ptr %t14)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t14)
  store ptr %t14, ptr %t3
  store ptr %t5, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t23 = load ptr, ptr %t2
  ret ptr %t23
}

define internal ptr @v__cps__scc__apply1__df__lam_14_5__df__lam_17_9__df__lam_9_1(ptr %v__args, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 29, label %tco.case.arm.29.11 i64 30, label %tco.case.arm.30.68 i64 31, label %tco.case.arm.31.79 i64 32, label %tco.case.arm.32.90 ]
tco.case.arm.29.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t5, i32 2
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  %t16 = getelementptr ptr, ptr %t13, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %tco.case.default.19 [ i64 25, label %tco.case.arm.25.20 i64 26, label %tco.case.arm.26.28 i64 27, label %tco.case.arm.27.36 i64 28, label %tco.case.arm.28.44 ]
tco.case.arm.25.20:
  %t21 = getelementptr ptr, ptr %t13, i32 1
  %t22 = load ptr, ptr %t21
  call void @__inc_ref(ptr %t22)
  %t23 = getelementptr ptr, ptr %t5, i32 1
  %t24 = load ptr, ptr %t23
  call void @__free_recursive(ptr %t24)
  %t26 = inttoptr i64 30 to ptr
  %t27 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t26, ptr %t27
  %t25 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t22, ptr %t25
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t5, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.26.28:
  %t29 = getelementptr ptr, ptr %t13, i32 1
  %t30 = load ptr, ptr %t29
  call void @__inc_ref(ptr %t30)
  %t31 = getelementptr ptr, ptr %t5, i32 1
  %t32 = load ptr, ptr %t31
  call void @__free_recursive(ptr %t32)
  %t34 = inttoptr i64 31 to ptr
  %t35 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t34, ptr %t35
  %t33 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t30, ptr %t33
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t5, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.27.36:
  %t37 = getelementptr ptr, ptr %t13, i32 1
  %t38 = load ptr, ptr %t37
  call void @__inc_ref(ptr %t38)
  %t39 = getelementptr ptr, ptr %t5, i32 1
  %t40 = load ptr, ptr %t39
  call void @__free_recursive(ptr %t40)
  %t42 = inttoptr i64 32 to ptr
  %t43 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t42, ptr %t43
  %t41 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t38, ptr %t41
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  store ptr %t5, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.28.44:
  call void @__inc_ref(ptr %t6)
  %t45 = getelementptr ptr, ptr %t15, i32 0
  %t46 = load ptr, ptr %t45
  %t47 = ptrtoint ptr %t46 to i64
  switch i64 %t47, label %case.default.48 [ i64 3, label %case.arm.3.50 i64 4, label %case.arm.4.58 ]
case.arm.3.50:
  %t52 = call ptr @__alloc(i64 16, i32 1)
  %t53 = inttoptr i64 6 to ptr
  %t54 = getelementptr ptr, ptr %t52, i32 0
  store ptr %t53, ptr %t54
  %t55 = getelementptr ptr, ptr %t15, i32 1
  %t56 = load ptr, ptr %t55
  call void @__inc_ref(ptr %t56)
  %t57 = getelementptr ptr, ptr %t52, i32 1
  store ptr %t56, ptr %t57
  br label %case.end.3.51
case.end.3.51:
  br label %case.join.49
case.arm.4.58:
  %t60 = call ptr @__alloc(i64 16, i32 1)
  %t61 = inttoptr i64 5 to ptr
  %t62 = getelementptr ptr, ptr %t60, i32 0
  store ptr %t61, ptr %t62
  %t63 = getelementptr ptr, ptr %t15, i32 1
  %t64 = load ptr, ptr %t63
  call void @__inc_ref(ptr %t64)
  %t65 = getelementptr ptr, ptr %t60, i32 1
  store ptr %t64, ptr %t65
  br label %case.end.4.59
case.end.4.59:
  br label %case.join.49
case.default.48:
  unreachable
case.join.49:
  %t66 = phi ptr [ %t52, %case.end.3.51 ], [ %t60, %case.end.4.59 ]
  %t67 = call ptr @v__apply__scc__apply1__df__lam_14_5__df__lam_17_9__df__lam_9_1(ptr %t6, ptr %t66)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t67, ptr %t2
  br label %tco.exit.1
tco.case.default.19:
  unreachable
tco.case.arm.30.68:
  %t69 = getelementptr ptr, ptr %t5, i32 1
  %t70 = load ptr, ptr %t69
  %t71 = getelementptr ptr, ptr %t5, i32 2
  %t72 = load ptr, ptr %t71
  %t73 = inttoptr i64 29 to ptr
  %t74 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t73, ptr %t74
  %t75 = call ptr @__alloc(i64 16, i32 1)
  %t76 = inttoptr i64 40 to ptr
  %t77 = getelementptr ptr, ptr %t75, i32 0
  store ptr %t76, ptr %t77
  call void @__inc_ref(ptr %t6)
  %t78 = getelementptr ptr, ptr %t75, i32 1
  store ptr %t6, ptr %t78
  call void @__free_recursive(ptr %t6)
  store ptr %t5, ptr %t3
  store ptr %t75, ptr %t4
  br label %tco.loop.0
tco.case.arm.31.79:
  %t80 = getelementptr ptr, ptr %t5, i32 1
  %t81 = load ptr, ptr %t80
  %t82 = getelementptr ptr, ptr %t5, i32 2
  %t83 = load ptr, ptr %t82
  %t84 = inttoptr i64 29 to ptr
  %t85 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t84, ptr %t85
  %t86 = call ptr @__alloc(i64 16, i32 1)
  %t87 = inttoptr i64 41 to ptr
  %t88 = getelementptr ptr, ptr %t86, i32 0
  store ptr %t87, ptr %t88
  call void @__inc_ref(ptr %t6)
  %t89 = getelementptr ptr, ptr %t86, i32 1
  store ptr %t6, ptr %t89
  call void @__free_recursive(ptr %t6)
  store ptr %t5, ptr %t3
  store ptr %t86, ptr %t4
  br label %tco.loop.0
tco.case.arm.32.90:
  %t91 = getelementptr ptr, ptr %t5, i32 1
  %t92 = load ptr, ptr %t91
  %t93 = getelementptr ptr, ptr %t5, i32 2
  %t94 = load ptr, ptr %t93
  %t95 = inttoptr i64 29 to ptr
  %t96 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t95, ptr %t96
  %t97 = call ptr @__alloc(i64 16, i32 1)
  %t98 = inttoptr i64 42 to ptr
  %t99 = getelementptr ptr, ptr %t97, i32 0
  store ptr %t98, ptr %t99
  call void @__inc_ref(ptr %t6)
  %t100 = getelementptr ptr, ptr %t97, i32 1
  store ptr %t6, ptr %t100
  call void @__free_recursive(ptr %t6)
  store ptr %t5, ptr %t3
  store ptr %t97, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t101 = load ptr, ptr %t2
  ret ptr %t101
}

define internal ptr @v__apply__scc__apply1__df__lam_14_5__df__lam_17_9__df__lam_9_1(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 39, label %tco.case.arm.39.11 i64 40, label %tco.case.arm.40.12 i64 41, label %tco.case.arm.41.19 i64 42, label %tco.case.arm.42.26 ]
tco.case.arm.39.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.40.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  call void @__inc_ref(ptr %t6)
  %t15 = call ptr @__alloc(i64 8, i32 0)
  %t16 = inttoptr i64 35 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = call ptr @v__cps__df__rowmono_0_andThenIO_4(ptr %t6, ptr %t15)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  store ptr %t14, ptr %t3
  store ptr %t18, ptr %t4
  br label %tco.loop.0
tco.case.arm.41.19:
  %t20 = getelementptr ptr, ptr %t5, i32 1
  %t21 = load ptr, ptr %t20
  call void @__inc_ref(ptr %t21)
  call void @__inc_ref(ptr %t6)
  %t22 = call ptr @__alloc(i64 8, i32 0)
  %t23 = inttoptr i64 37 to ptr
  %t24 = getelementptr ptr, ptr %t22, i32 0
  store ptr %t23, ptr %t24
  %t25 = call ptr @v__cps__df__rowmono_1_andThenIO_8(ptr %t6, ptr %t22)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  store ptr %t21, ptr %t3
  store ptr %t25, ptr %t4
  br label %tco.loop.0
tco.case.arm.42.26:
  %t27 = getelementptr ptr, ptr %t5, i32 1
  %t28 = load ptr, ptr %t27
  call void @__inc_ref(ptr %t28)
  call void @__inc_ref(ptr %t6)
  %t29 = call ptr @__alloc(i64 8, i32 0)
  %t30 = inttoptr i64 33 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = call ptr @v__cps__df_handleErrorIO_0(ptr %t6, ptr %t29)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  store ptr %t28, ptr %t3
  store ptr %t32, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t33 = load ptr, ptr %t2
  ret ptr %t33
}

define i32 @main(i32 %argc, ptr %argv) {
  %argc64 = sext i32 %argc to i64
  store i64 %argc64, ptr @.cli_argc
  store ptr %argv, ptr @.cli_argv
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
