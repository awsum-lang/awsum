; External C declarations
declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare ptr @memcpy(ptr, ptr, i64)
declare i64 @write(i32, ptr, i64)
declare i64 @strlen(ptr)

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
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [9 x i8]} { i32 0, i32 0, i32 0, i32 9, i32 9, [9 x i8] c"more-more" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [18 x i8]} { i32 0, i32 0, i32 0, i32 18, i32 18, [18 x i8] c"more-one-bool-bool" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [8 x i8]} { i32 0, i32 0, i32 0, i32 8, i32 8, [8 x i8] c"one-bool" }

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
  %t21 = inttoptr i64 52 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = call ptr @__alloc(i64 24, i32 2)
  %t24 = inttoptr i64 31 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  %t26 = getelementptr ptr, ptr %t4, i32 1
  %t27 = load ptr, ptr %t26
  call void @__inc_ref(ptr %t27)
  %t28 = getelementptr ptr, ptr %t23, i32 1
  store ptr %t27, ptr %t28
  call void @__inc_ref(ptr %t19)
  %t29 = getelementptr ptr, ptr %t23, i32 2
  store ptr %t19, ptr %t29
  %t30 = getelementptr ptr, ptr %t20, i32 1
  store ptr %t23, ptr %t30
  %t31 = call ptr @__alloc(i64 8, i32 0)
  %t32 = inttoptr i64 41 to ptr
  %t33 = getelementptr ptr, ptr %t31, i32 0
  store ptr %t32, ptr %t33
  %t34 = getelementptr ptr, ptr %t20, i32 2
  store ptr %t31, ptr %t34
  %t35 = call ptr @v_$scc$$apply$$scc$$apply1__$df$$lam$13$7__$df$$lam$9$3__$df$$rowmono$0$andThenIO$6__$df$mapPerfect$0__$df$mapPerfect$1__bimapTuple2__run2__$cps$$scc$$apply1__$df$$lam$13$7__$df$$lam$9$3__$df$$rowmono$0$andThenIO$6__$df$mapPerfect$0__$df$mapPerfect$1__bimapTuple2__run2(ptr %t20)
  call void @__free_recursive(ptr %t19)
  call void @__free_recursive(ptr %t4)
  store ptr %t35, ptr %t3
  br label %tco.loop.0
tco.case.default.8:
  unreachable
tco.exit.1:
  %t36 = load ptr, ptr %t2
  ret ptr %t36
}

define internal ptr @v_main() {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 52 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 16, i32 1)
  %t4 = inttoptr i64 34 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = call ptr @__alloc(i64 16, i32 1)
  %t7 = inttoptr i64 8 to ptr
  %t8 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t7, ptr %t8
  %t9 = call ptr @__alloc(i64 8, i32 0)
  %t10 = inttoptr i64 28 to ptr
  %t11 = getelementptr ptr, ptr %t9, i32 0
  store ptr %t10, ptr %t11
  %t12 = getelementptr ptr, ptr %t6, i32 1
  store ptr %t9, ptr %t12
  %t13 = getelementptr ptr, ptr %t3, i32 1
  store ptr %t6, ptr %t13
  %t14 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t14
  %t15 = call ptr @__alloc(i64 8, i32 0)
  %t16 = inttoptr i64 41 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t15, ptr %t18
  %t19 = call ptr @v_$scc$$apply$$scc$$apply1__$df$$lam$13$7__$df$$lam$9$3__$df$$rowmono$0$andThenIO$6__$df$mapPerfect$0__$df$mapPerfect$1__bimapTuple2__run2__$cps$$scc$$apply1__$df$$lam$13$7__$df$$lam$9$3__$df$$rowmono$0$andThenIO$6__$df$mapPerfect$0__$df$mapPerfect$1__bimapTuple2__run2(ptr %t0)
  %t20 = call ptr @__alloc(i64 8, i32 0)
  %t21 = inttoptr i64 39 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = call ptr @v_$cps$$df$handleErrorIO$2(ptr %t19, ptr %t20)
  ret ptr %t23
}

define internal ptr @v_$cps$$df$handleErrorIO$2(ptr %v_io, ptr %v_$k) {
entry:
  %t3 = alloca ptr
  store ptr %v_io, ptr %t3
  %t4 = alloca ptr
  store ptr %v_$k, ptr %t4
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t5 = load ptr, ptr %t3
  %t6 = load ptr, ptr %t4
  %t7 = getelementptr ptr, ptr %t5, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.13 i64 7, label %tco.case.arm.7.51 i64 8, label %tco.case.arm.8.76 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t12 = call ptr @v_$apply$$df$handleErrorIO$2(ptr %t6, ptr %t5)
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
  switch i64 %t18, label %case.default.19 [ i64 502975519, label %case.arm.502975519.21 i64 589989748, label %case.arm.589989748.35 ]
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
case.default.19:
  unreachable
case.join.20:
  %t49 = phi ptr [ %t23, %case.end.502975519.22 ], [ %t37, %case.end.589989748.36 ]
  call void @__free_recursive(ptr %t15)
  %t50 = call ptr @v_$apply$$df$handleErrorIO$2(ptr %t6, ptr %t49)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t50, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.51:
  %t52 = getelementptr ptr, ptr %t5, i32 1
  %t53 = load ptr, ptr %t52
  %t54 = getelementptr ptr, ptr %t5, i32 2
  %t55 = load ptr, ptr %t54
  call void @__inc_ref(ptr %t55)
  %t62 = getelementptr i8, ptr %t5, i64 -8
  %t63 = load i32, ptr %t62
  %t64 = icmp eq i32 %t63, 1
  br i1 %t64, label %reuse.in_place.65, label %reuse.copy.66
reuse.in_place.65:
  %t56 = getelementptr ptr, ptr %t5, i32 2
  %t57 = load ptr, ptr %t56
  call void @__free_recursive(ptr %t57)
  %t60 = inttoptr i64 40 to ptr
  %t61 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t60, ptr %t61
  call void @__inc_ref(ptr %t6)
  %t58 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t58
  %t59 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t53, ptr %t59
  br label %reuse.in_place.end.68
reuse.in_place.end.68:
  br label %reuse.join.67
reuse.copy.66:
  %t70 = call ptr @__alloc(i64 24, i32 2)
  %t71 = inttoptr i64 40 to ptr
  %t72 = getelementptr ptr, ptr %t70, i32 0
  store ptr %t71, ptr %t72
  call void @__inc_ref(ptr %t6)
  %t73 = getelementptr ptr, ptr %t70, i32 1
  store ptr %t6, ptr %t73
  call void @__inc_ref(ptr %t53)
  %t74 = getelementptr ptr, ptr %t70, i32 2
  store ptr %t53, ptr %t74
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.69
reuse.copy.end.69:
  br label %reuse.join.67
reuse.join.67:
  %t75 = phi ptr [ %t5, %reuse.in_place.end.68 ], [ %t70, %reuse.copy.end.69 ]
  call void @__free_recursive(ptr %t6)
  store ptr %t55, ptr %t3
  store ptr %t75, ptr %t4
  br label %tco.loop.0
tco.case.arm.8.76:
  %t77 = getelementptr ptr, ptr %t5, i32 1
  %t78 = load ptr, ptr %t77
  call void @__inc_ref(ptr %t78)
  call void @__inc_ref(ptr %t6)
  %t79 = call ptr @__alloc(i64 16, i32 1)
  %t80 = inttoptr i64 8 to ptr
  %t81 = getelementptr ptr, ptr %t79, i32 0
  store ptr %t80, ptr %t81
  %t82 = call ptr @__alloc(i64 16, i32 1)
  %t83 = inttoptr i64 27 to ptr
  %t84 = getelementptr ptr, ptr %t82, i32 0
  store ptr %t83, ptr %t84
  call void @__inc_ref(ptr %t78)
  %t85 = getelementptr ptr, ptr %t82, i32 1
  store ptr %t78, ptr %t85
  %t86 = getelementptr ptr, ptr %t79, i32 1
  store ptr %t82, ptr %t86
  %t87 = call ptr @v_$apply$$df$handleErrorIO$2(ptr %t6, ptr %t79)
  call void @__free_recursive(ptr %t78)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t87, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t88 = load ptr, ptr %t2
  ret ptr %t88
}

define internal ptr @v_$apply$$df$handleErrorIO$2(ptr %v_$k, ptr %v_$x) {
entry:
  %t3 = alloca ptr
  store ptr %v_$k, ptr %t3
  %t4 = alloca ptr
  store ptr %v_$x, ptr %t4
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t5 = load ptr, ptr %t3
  %t6 = load ptr, ptr %t4
  %t7 = getelementptr ptr, ptr %t5, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %tco.case.default.10 [ i64 39, label %tco.case.arm.39.11 i64 40, label %tco.case.arm.40.12 ]
tco.case.arm.39.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.40.12:
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
  call void @__free_recursive(ptr %t6)
  store ptr %t14, ptr %t3
  store ptr %t5, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t23 = load ptr, ptr %t2
  ret ptr %t23
}

define internal ptr @v_$scc$$apply$$scc$$apply1__$df$$lam$13$7__$df$$lam$9$3__$df$$rowmono$0$andThenIO$6__$df$mapPerfect$0__$df$mapPerfect$1__bimapTuple2__run2__$cps$$scc$$apply1__$df$$lam$13$7__$df$$lam$9$3__$df$$rowmono$0$andThenIO$6__$df$mapPerfect$0__$df$mapPerfect$1__bimapTuple2__run2(ptr %v_$args$1) {
entry:
  %t3 = alloca ptr
  store ptr %v_$args$1, ptr %t3
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t4 = load ptr, ptr %t3
  %t5 = getelementptr ptr, ptr %t4, i32 0
  %t6 = load ptr, ptr %t5
  %t7 = ptrtoint ptr %t6 to i64
  switch i64 %t7, label %tco.case.default.8 [ i64 51, label %tco.case.arm.51.9 i64 52, label %tco.case.arm.52.194 ]
tco.case.arm.51.9:
  %t10 = getelementptr ptr, ptr %t4, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  %t12 = getelementptr ptr, ptr %t4, i32 2
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t11, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %tco.case.default.17 [ i64 41, label %tco.case.arm.41.18 i64 42, label %tco.case.arm.42.19 i64 43, label %tco.case.arm.43.34 i64 44, label %tco.case.arm.44.49 i64 45, label %tco.case.arm.45.64 i64 46, label %tco.case.arm.46.79 i64 47, label %tco.case.arm.47.94 i64 49, label %tco.case.arm.49.109 i64 48, label %tco.case.arm.48.124 i64 50, label %tco.case.arm.50.149 ]
tco.case.arm.41.18:
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %t4)
  store ptr %t13, ptr %t2
  br label %tco.exit.1
tco.case.arm.42.19:
  %t20 = call ptr @__alloc(i64 16, i32 1)
  %t21 = inttoptr i64 34 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  call void @__inc_ref(ptr %t13)
  %t23 = getelementptr ptr, ptr %t20, i32 1
  store ptr %t13, ptr %t23
  %t24 = getelementptr ptr, ptr %t11, i32 1
  %t25 = load ptr, ptr %t24
  call void @__inc_ref(ptr %t25)
  %t26 = getelementptr ptr, ptr %t4, i32 1
  %t27 = load ptr, ptr %t26
  call void @__free_recursive(ptr %t27)
  %t28 = getelementptr ptr, ptr %t4, i32 2
  %t29 = load ptr, ptr %t28
  call void @__free_recursive(ptr %t29)
  %t32 = inttoptr i64 52 to ptr
  %t33 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t32, ptr %t33
  %t30 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t20, ptr %t30
  %t31 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t25, ptr %t31
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.43.34:
  %t35 = getelementptr ptr, ptr %t11, i32 1
  %t36 = load ptr, ptr %t35
  call void @__inc_ref(ptr %t36)
  call void @__inc_ref(ptr %t13)
  %t37 = call ptr @__alloc(i64 8, i32 0)
  %t38 = inttoptr i64 39 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = call ptr @v_$cps$$df$handleErrorIO$2(ptr %t13, ptr %t37)
  %t41 = getelementptr ptr, ptr %t4, i32 1
  %t42 = load ptr, ptr %t41
  call void @__free_recursive(ptr %t42)
  %t43 = getelementptr ptr, ptr %t4, i32 2
  %t44 = load ptr, ptr %t43
  call void @__free_recursive(ptr %t44)
  %t47 = inttoptr i64 51 to ptr
  %t48 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t47, ptr %t48
  %t45 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t36, ptr %t45
  %t46 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t40, ptr %t46
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.44.49:
  %t50 = call ptr @__alloc(i64 24, i32 2)
  %t51 = inttoptr i64 51 to ptr
  %t52 = getelementptr ptr, ptr %t50, i32 0
  store ptr %t51, ptr %t52
  %t53 = getelementptr ptr, ptr %t11, i32 1
  %t54 = load ptr, ptr %t53
  call void @__inc_ref(ptr %t54)
  %t55 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t54, ptr %t55
  %t56 = getelementptr ptr, ptr %t11, i32 2
  %t57 = load ptr, ptr %t56
  call void @__inc_ref(ptr %t57)
  %t58 = getelementptr ptr, ptr %t4, i32 1
  %t59 = load ptr, ptr %t58
  call void @__free_recursive(ptr %t59)
  %t61 = inttoptr i64 7 to ptr
  %t62 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t61, ptr %t62
  %t60 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t57, ptr %t60
  %t63 = getelementptr ptr, ptr %t50, i32 2
  store ptr %t4, ptr %t63
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t50, ptr %t3
  br label %tco.loop.0
tco.case.arm.45.64:
  %t65 = getelementptr ptr, ptr %t11, i32 1
  %t66 = load ptr, ptr %t65
  call void @__inc_ref(ptr %t66)
  %t67 = call ptr @__alloc(i64 16, i32 1)
  %t68 = inttoptr i64 24 to ptr
  %t69 = getelementptr ptr, ptr %t67, i32 0
  store ptr %t68, ptr %t69
  call void @__inc_ref(ptr %t13)
  %t70 = getelementptr ptr, ptr %t67, i32 1
  store ptr %t13, ptr %t70
  %t71 = getelementptr ptr, ptr %t4, i32 1
  %t72 = load ptr, ptr %t71
  call void @__free_recursive(ptr %t72)
  %t73 = getelementptr ptr, ptr %t4, i32 2
  %t74 = load ptr, ptr %t73
  call void @__free_recursive(ptr %t74)
  %t77 = inttoptr i64 51 to ptr
  %t78 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t77, ptr %t78
  %t75 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t66, ptr %t75
  %t76 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t67, ptr %t76
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.46.79:
  %t80 = getelementptr ptr, ptr %t11, i32 1
  %t81 = load ptr, ptr %t80
  call void @__inc_ref(ptr %t81)
  %t82 = call ptr @__alloc(i64 16, i32 1)
  %t83 = inttoptr i64 25 to ptr
  %t84 = getelementptr ptr, ptr %t82, i32 0
  store ptr %t83, ptr %t84
  call void @__inc_ref(ptr %t13)
  %t85 = getelementptr ptr, ptr %t82, i32 1
  store ptr %t13, ptr %t85
  %t86 = getelementptr ptr, ptr %t4, i32 1
  %t87 = load ptr, ptr %t86
  call void @__free_recursive(ptr %t87)
  %t88 = getelementptr ptr, ptr %t4, i32 2
  %t89 = load ptr, ptr %t88
  call void @__free_recursive(ptr %t89)
  %t92 = inttoptr i64 51 to ptr
  %t93 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t92, ptr %t93
  %t90 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t81, ptr %t90
  %t91 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t82, ptr %t91
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.47.94:
  %t95 = getelementptr ptr, ptr %t11, i32 1
  %t96 = load ptr, ptr %t95
  call void @__inc_ref(ptr %t96)
  %t97 = call ptr @__alloc(i64 16, i32 1)
  %t98 = inttoptr i64 24 to ptr
  %t99 = getelementptr ptr, ptr %t97, i32 0
  store ptr %t98, ptr %t99
  call void @__inc_ref(ptr %t13)
  %t100 = getelementptr ptr, ptr %t97, i32 1
  store ptr %t13, ptr %t100
  %t101 = getelementptr ptr, ptr %t4, i32 1
  %t102 = load ptr, ptr %t101
  call void @__free_recursive(ptr %t102)
  %t103 = getelementptr ptr, ptr %t4, i32 2
  %t104 = load ptr, ptr %t103
  call void @__free_recursive(ptr %t104)
  %t107 = inttoptr i64 51 to ptr
  %t108 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t107, ptr %t108
  %t105 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t96, ptr %t105
  %t106 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t97, ptr %t106
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.49.109:
  %t110 = call ptr @__alloc(i64 24, i32 2)
  %t111 = inttoptr i64 51 to ptr
  %t112 = getelementptr ptr, ptr %t110, i32 0
  store ptr %t111, ptr %t112
  %t113 = getelementptr ptr, ptr %t11, i32 1
  %t114 = load ptr, ptr %t113
  call void @__inc_ref(ptr %t114)
  %t115 = getelementptr ptr, ptr %t110, i32 1
  store ptr %t114, ptr %t115
  %t116 = getelementptr ptr, ptr %t11, i32 2
  %t117 = load ptr, ptr %t116
  call void @__inc_ref(ptr %t117)
  %t118 = getelementptr ptr, ptr %t4, i32 1
  %t119 = load ptr, ptr %t118
  call void @__free_recursive(ptr %t119)
  %t121 = inttoptr i64 15 to ptr
  %t122 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t121, ptr %t122
  %t120 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t117, ptr %t120
  %t123 = getelementptr ptr, ptr %t110, i32 2
  store ptr %t4, ptr %t123
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t110, ptr %t3
  br label %tco.loop.0
tco.case.arm.48.124:
  %t125 = call ptr @__alloc(i64 24, i32 2)
  %t126 = inttoptr i64 52 to ptr
  %t127 = getelementptr ptr, ptr %t125, i32 0
  store ptr %t126, ptr %t127
  %t128 = getelementptr ptr, ptr %t11, i32 3
  %t129 = load ptr, ptr %t128
  call void @__inc_ref(ptr %t129)
  %t130 = getelementptr ptr, ptr %t11, i32 2
  %t131 = load ptr, ptr %t130
  call void @__inc_ref(ptr %t131)
  %t132 = getelementptr ptr, ptr %t4, i32 1
  %t133 = load ptr, ptr %t132
  call void @__free_recursive(ptr %t133)
  %t134 = getelementptr ptr, ptr %t4, i32 2
  %t135 = load ptr, ptr %t134
  call void @__free_recursive(ptr %t135)
  %t138 = inttoptr i64 31 to ptr
  %t139 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t138, ptr %t139
  %t136 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t129, ptr %t136
  %t137 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t131, ptr %t137
  %t140 = getelementptr ptr, ptr %t125, i32 1
  store ptr %t4, ptr %t140
  %t141 = call ptr @__alloc(i64 24, i32 2)
  %t142 = inttoptr i64 49 to ptr
  %t143 = getelementptr ptr, ptr %t141, i32 0
  store ptr %t142, ptr %t143
  %t144 = getelementptr ptr, ptr %t11, i32 1
  %t145 = load ptr, ptr %t144
  call void @__inc_ref(ptr %t145)
  %t146 = getelementptr ptr, ptr %t141, i32 1
  store ptr %t145, ptr %t146
  call void @__inc_ref(ptr %t13)
  %t147 = getelementptr ptr, ptr %t141, i32 2
  store ptr %t13, ptr %t147
  %t148 = getelementptr ptr, ptr %t125, i32 2
  store ptr %t141, ptr %t148
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t125, ptr %t3
  br label %tco.loop.0
tco.case.arm.50.149:
  %t150 = call ptr @__alloc(i64 24, i32 2)
  %t151 = inttoptr i64 51 to ptr
  %t152 = getelementptr ptr, ptr %t150, i32 0
  store ptr %t151, ptr %t152
  %t153 = getelementptr ptr, ptr %t11, i32 1
  %t154 = load ptr, ptr %t153
  call void @__inc_ref(ptr %t154)
  %t155 = getelementptr ptr, ptr %t150, i32 1
  store ptr %t154, ptr %t155
  %t156 = getelementptr ptr, ptr %t13, i32 0
  %t157 = load ptr, ptr %t156
  %t158 = ptrtoint ptr %t157 to i64
  switch i64 %t158, label %case.default.159 [ i64 24, label %case.arm.24.161 i64 25, label %case.arm.25.175 ]
case.arm.24.161:
  %t163 = getelementptr ptr, ptr %t13, i32 1
  %t164 = load ptr, ptr %t163
  call void @__inc_ref(ptr %t164)
  %t165 = getelementptr ptr, ptr %t164, i32 0
  %t166 = load ptr, ptr %t165
  %t167 = ptrtoint ptr %t166 to i64
  switch i64 %t167, label %case.default.168 [ i64 24, label %case.arm.24.170 i64 25, label %case.arm.25.172 ]
case.arm.24.170:
  br label %case.end.24.171
case.end.24.171:
  br label %case.join.169
case.arm.25.172:
  br label %case.end.25.173
case.end.25.173:
  br label %case.join.169
case.default.168:
  unreachable
case.join.169:
  %t174 = phi ptr [ getelementptr inbounds (i8, ptr @.str.2, i64 12), %case.end.24.171 ], [ getelementptr inbounds (i8, ptr @.str.3, i64 12), %case.end.25.173 ]
  call void @__free_recursive(ptr %t164)
  br label %case.end.24.162
case.end.24.162:
  br label %case.join.160
case.arm.25.175:
  br label %case.end.25.176
case.end.25.176:
  br label %case.join.160
case.default.159:
  unreachable
case.join.160:
  %t177 = phi ptr [ %t174, %case.end.24.162 ], [ getelementptr inbounds (i8, ptr @.str.4, i64 12), %case.end.25.176 ]
  %t178 = call ptr @__alloc(i64 16, i32 1)
  %t179 = inttoptr i64 5 to ptr
  %t180 = getelementptr ptr, ptr %t178, i32 0
  store ptr %t179, ptr %t180
  %t181 = call ptr @__alloc(i64 8, i32 0)
  %t182 = inttoptr i64 0 to ptr
  %t183 = getelementptr ptr, ptr %t181, i32 0
  store ptr %t182, ptr %t183
  %t184 = getelementptr ptr, ptr %t178, i32 1
  store ptr %t181, ptr %t184
  %t185 = getelementptr ptr, ptr %t4, i32 1
  %t186 = load ptr, ptr %t185
  call void @__free_recursive(ptr %t186)
  %t187 = getelementptr ptr, ptr %t4, i32 2
  %t188 = load ptr, ptr %t187
  call void @__free_recursive(ptr %t188)
  %t191 = inttoptr i64 7 to ptr
  %t192 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t191, ptr %t192
  %t189 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t177, ptr %t189
  %t190 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t178, ptr %t190
  %t193 = getelementptr ptr, ptr %t150, i32 2
  store ptr %t4, ptr %t193
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t150, ptr %t3
  br label %tco.loop.0
tco.case.default.17:
  unreachable
tco.case.arm.52.194:
  %t195 = getelementptr ptr, ptr %t4, i32 1
  %t196 = load ptr, ptr %t195
  call void @__inc_ref(ptr %t196)
  %t197 = getelementptr ptr, ptr %t4, i32 2
  %t198 = load ptr, ptr %t197
  call void @__inc_ref(ptr %t198)
  %t199 = getelementptr ptr, ptr %t196, i32 0
  %t200 = load ptr, ptr %t199
  %t201 = ptrtoint ptr %t200 to i64
  switch i64 %t201, label %tco.case.default.202 [ i64 31, label %tco.case.arm.31.203 i64 32, label %tco.case.arm.32.301 i64 33, label %tco.case.arm.33.320 i64 34, label %tco.case.arm.34.339 i64 35, label %tco.case.arm.35.411 i64 36, label %tco.case.arm.36.512 i64 37, label %tco.case.arm.37.593 i64 38, label %tco.case.arm.38.646 ]
tco.case.arm.31.203:
  %t204 = getelementptr ptr, ptr %t196, i32 1
  %t205 = load ptr, ptr %t204
  call void @__inc_ref(ptr %t205)
  %t206 = getelementptr ptr, ptr %t196, i32 2
  %t207 = load ptr, ptr %t206
  call void @__inc_ref(ptr %t207)
  %t208 = getelementptr ptr, ptr %t205, i32 0
  %t209 = load ptr, ptr %t208
  %t210 = ptrtoint ptr %t209 to i64
  switch i64 %t210, label %tco.case.default.211 [ i64 26, label %tco.case.arm.26.212 i64 27, label %tco.case.arm.27.225 i64 28, label %tco.case.arm.28.238 i64 29, label %tco.case.arm.29.269 i64 30, label %tco.case.arm.30.288 ]
tco.case.arm.26.212:
  %t213 = getelementptr ptr, ptr %t4, i32 1
  %t214 = load ptr, ptr %t213
  call void @__free_recursive(ptr %t214)
  %t223 = inttoptr i64 52 to ptr
  %t224 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t223, ptr %t224
  %t215 = getelementptr ptr, ptr %t205, i32 1
  %t216 = load ptr, ptr %t215
  call void @__inc_ref(ptr %t216)
  %t217 = getelementptr ptr, ptr %t196, i32 1
  %t218 = load ptr, ptr %t217
  call void @__free_recursive(ptr %t218)
  %t220 = inttoptr i64 32 to ptr
  %t221 = getelementptr ptr, ptr %t196, i32 0
  store ptr %t220, ptr %t221
  %t219 = getelementptr ptr, ptr %t196, i32 1
  store ptr %t216, ptr %t219
  %t222 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t196, ptr %t222
  call void @__free_recursive(ptr %t207)
  call void @__free_recursive(ptr %t205)
  call void @__free_recursive(ptr %t198)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.27.225:
  %t226 = getelementptr ptr, ptr %t4, i32 1
  %t227 = load ptr, ptr %t226
  call void @__free_recursive(ptr %t227)
  %t236 = inttoptr i64 52 to ptr
  %t237 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t236, ptr %t237
  %t228 = getelementptr ptr, ptr %t205, i32 1
  %t229 = load ptr, ptr %t228
  call void @__inc_ref(ptr %t229)
  %t230 = getelementptr ptr, ptr %t196, i32 1
  %t231 = load ptr, ptr %t230
  call void @__free_recursive(ptr %t231)
  %t233 = inttoptr i64 33 to ptr
  %t234 = getelementptr ptr, ptr %t196, i32 0
  store ptr %t233, ptr %t234
  %t232 = getelementptr ptr, ptr %t196, i32 1
  store ptr %t229, ptr %t232
  %t235 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t196, ptr %t235
  call void @__free_recursive(ptr %t207)
  call void @__free_recursive(ptr %t205)
  call void @__free_recursive(ptr %t198)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.28.238:
  %t239 = getelementptr ptr, ptr %t207, i32 0
  %t240 = load ptr, ptr %t239
  %t241 = ptrtoint ptr %t240 to i64
  switch i64 %t241, label %case.default.242 [ i64 3, label %case.arm.3.244 i64 4, label %case.arm.4.252 ]
case.arm.3.244:
  %t246 = call ptr @__alloc(i64 16, i32 1)
  %t247 = inttoptr i64 6 to ptr
  %t248 = getelementptr ptr, ptr %t246, i32 0
  store ptr %t247, ptr %t248
  %t249 = getelementptr ptr, ptr %t207, i32 1
  %t250 = load ptr, ptr %t249
  call void @__inc_ref(ptr %t250)
  %t251 = getelementptr ptr, ptr %t246, i32 1
  store ptr %t250, ptr %t251
  br label %case.end.3.245
case.end.3.245:
  br label %case.join.243
case.arm.4.252:
  %t254 = call ptr @__alloc(i64 16, i32 1)
  %t255 = inttoptr i64 5 to ptr
  %t256 = getelementptr ptr, ptr %t254, i32 0
  store ptr %t255, ptr %t256
  %t257 = getelementptr ptr, ptr %t207, i32 1
  %t258 = load ptr, ptr %t257
  call void @__inc_ref(ptr %t258)
  %t259 = getelementptr ptr, ptr %t254, i32 1
  store ptr %t258, ptr %t259
  br label %case.end.4.253
case.end.4.253:
  br label %case.join.243
case.default.242:
  unreachable
case.join.243:
  %t260 = phi ptr [ %t246, %case.end.3.245 ], [ %t254, %case.end.4.253 ]
  %t261 = getelementptr ptr, ptr %t196, i32 1
  %t262 = load ptr, ptr %t261
  call void @__free_recursive(ptr %t262)
  %t263 = getelementptr ptr, ptr %t196, i32 2
  %t264 = load ptr, ptr %t263
  call void @__free_recursive(ptr %t264)
  %t267 = inttoptr i64 51 to ptr
  %t268 = getelementptr ptr, ptr %t196, i32 0
  store ptr %t267, ptr %t268
  call void @__inc_ref(ptr %t198)
  %t265 = getelementptr ptr, ptr %t196, i32 1
  store ptr %t198, ptr %t265
  %t266 = getelementptr ptr, ptr %t196, i32 2
  store ptr %t260, ptr %t266
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t207)
  call void @__free_recursive(ptr %t205)
  call void @__free_recursive(ptr %t198)
  store ptr %t196, ptr %t3
  br label %tco.loop.0
tco.case.arm.29.269:
  %t270 = call ptr @__alloc(i64 32, i32 3)
  %t271 = inttoptr i64 37 to ptr
  %t272 = getelementptr ptr, ptr %t270, i32 0
  store ptr %t271, ptr %t272
  %t273 = getelementptr ptr, ptr %t205, i32 1
  %t274 = load ptr, ptr %t273
  call void @__inc_ref(ptr %t274)
  %t275 = getelementptr ptr, ptr %t270, i32 1
  store ptr %t274, ptr %t275
  %t276 = getelementptr ptr, ptr %t205, i32 2
  %t277 = load ptr, ptr %t276
  call void @__inc_ref(ptr %t277)
  %t278 = getelementptr ptr, ptr %t270, i32 2
  store ptr %t277, ptr %t278
  call void @__inc_ref(ptr %t207)
  %t279 = getelementptr ptr, ptr %t270, i32 3
  store ptr %t207, ptr %t279
  %t280 = getelementptr ptr, ptr %t196, i32 1
  %t281 = load ptr, ptr %t280
  call void @__free_recursive(ptr %t281)
  %t282 = getelementptr ptr, ptr %t196, i32 2
  %t283 = load ptr, ptr %t282
  call void @__free_recursive(ptr %t283)
  %t286 = inttoptr i64 52 to ptr
  %t287 = getelementptr ptr, ptr %t196, i32 0
  store ptr %t286, ptr %t287
  %t284 = getelementptr ptr, ptr %t196, i32 1
  store ptr %t270, ptr %t284
  call void @__inc_ref(ptr %t198)
  %t285 = getelementptr ptr, ptr %t196, i32 2
  store ptr %t198, ptr %t285
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t207)
  call void @__free_recursive(ptr %t205)
  call void @__free_recursive(ptr %t198)
  store ptr %t196, ptr %t3
  br label %tco.loop.0
tco.case.arm.30.288:
  %t289 = call ptr @__alloc(i64 16, i32 1)
  %t290 = inttoptr i64 796142685 to ptr
  %t291 = getelementptr ptr, ptr %t289, i32 0
  store ptr %t290, ptr %t291
  call void @__inc_ref(ptr %t207)
  %t292 = getelementptr ptr, ptr %t289, i32 1
  store ptr %t207, ptr %t292
  %t293 = getelementptr ptr, ptr %t196, i32 1
  %t294 = load ptr, ptr %t293
  call void @__free_recursive(ptr %t294)
  %t295 = getelementptr ptr, ptr %t196, i32 2
  %t296 = load ptr, ptr %t295
  call void @__free_recursive(ptr %t296)
  %t299 = inttoptr i64 51 to ptr
  %t300 = getelementptr ptr, ptr %t196, i32 0
  store ptr %t299, ptr %t300
  call void @__inc_ref(ptr %t198)
  %t297 = getelementptr ptr, ptr %t196, i32 1
  store ptr %t198, ptr %t297
  %t298 = getelementptr ptr, ptr %t196, i32 2
  store ptr %t289, ptr %t298
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t207)
  call void @__free_recursive(ptr %t205)
  call void @__free_recursive(ptr %t198)
  store ptr %t196, ptr %t3
  br label %tco.loop.0
tco.case.default.211:
  unreachable
tco.case.arm.32.301:
  %t302 = getelementptr ptr, ptr %t196, i32 1
  %t303 = load ptr, ptr %t302
  %t304 = getelementptr ptr, ptr %t196, i32 2
  %t305 = load ptr, ptr %t304
  %t306 = call ptr @__alloc(i64 16, i32 1)
  %t307 = inttoptr i64 42 to ptr
  %t308 = getelementptr ptr, ptr %t306, i32 0
  store ptr %t307, ptr %t308
  call void @__inc_ref(ptr %t198)
  %t309 = getelementptr ptr, ptr %t306, i32 1
  store ptr %t198, ptr %t309
  %t310 = getelementptr ptr, ptr %t4, i32 1
  %t311 = load ptr, ptr %t310
  call void @__free_recursive(ptr %t311)
  %t312 = getelementptr ptr, ptr %t4, i32 2
  %t313 = load ptr, ptr %t312
  call void @__free_recursive(ptr %t313)
  %t318 = inttoptr i64 52 to ptr
  %t319 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t318, ptr %t319
  %t314 = inttoptr i64 31 to ptr
  %t315 = getelementptr ptr, ptr %t196, i32 0
  store ptr %t314, ptr %t315
  %t316 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t196, ptr %t316
  %t317 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t306, ptr %t317
  call void @__free_recursive(ptr %t198)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.33.320:
  %t321 = getelementptr ptr, ptr %t196, i32 1
  %t322 = load ptr, ptr %t321
  %t323 = getelementptr ptr, ptr %t196, i32 2
  %t324 = load ptr, ptr %t323
  %t325 = call ptr @__alloc(i64 16, i32 1)
  %t326 = inttoptr i64 43 to ptr
  %t327 = getelementptr ptr, ptr %t325, i32 0
  store ptr %t326, ptr %t327
  call void @__inc_ref(ptr %t198)
  %t328 = getelementptr ptr, ptr %t325, i32 1
  store ptr %t198, ptr %t328
  %t329 = getelementptr ptr, ptr %t4, i32 1
  %t330 = load ptr, ptr %t329
  call void @__free_recursive(ptr %t330)
  %t331 = getelementptr ptr, ptr %t4, i32 2
  %t332 = load ptr, ptr %t331
  call void @__free_recursive(ptr %t332)
  %t337 = inttoptr i64 52 to ptr
  %t338 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t337, ptr %t338
  %t333 = inttoptr i64 31 to ptr
  %t334 = getelementptr ptr, ptr %t196, i32 0
  store ptr %t333, ptr %t334
  %t335 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t196, ptr %t335
  %t336 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t325, ptr %t336
  call void @__free_recursive(ptr %t198)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.34.339:
  %t340 = getelementptr ptr, ptr %t196, i32 1
  %t341 = load ptr, ptr %t340
  call void @__inc_ref(ptr %t341)
  %t342 = getelementptr ptr, ptr %t341, i32 0
  %t343 = load ptr, ptr %t342
  %t344 = ptrtoint ptr %t343 to i64
  switch i64 %t344, label %tco.case.default.345 [ i64 5, label %tco.case.arm.5.346 i64 6, label %tco.case.arm.6.359 i64 7, label %tco.case.arm.7.368 i64 8, label %tco.case.arm.8.391 ]
tco.case.arm.5.346:
  %t347 = getelementptr ptr, ptr %t4, i32 1
  %t348 = load ptr, ptr %t347
  call void @__free_recursive(ptr %t348)
  %t357 = inttoptr i64 52 to ptr
  %t358 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t357, ptr %t358
  %t349 = getelementptr ptr, ptr %t341, i32 1
  %t350 = load ptr, ptr %t349
  call void @__inc_ref(ptr %t350)
  %t351 = getelementptr ptr, ptr %t196, i32 1
  %t352 = load ptr, ptr %t351
  call void @__free_recursive(ptr %t352)
  %t354 = inttoptr i64 38 to ptr
  %t355 = getelementptr ptr, ptr %t196, i32 0
  store ptr %t354, ptr %t355
  %t353 = getelementptr ptr, ptr %t196, i32 1
  store ptr %t350, ptr %t353
  %t356 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t196, ptr %t356
  call void @__free_recursive(ptr %t341)
  call void @__free_recursive(ptr %t198)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.6.359:
  %t360 = getelementptr ptr, ptr %t4, i32 1
  %t361 = load ptr, ptr %t360
  call void @__free_recursive(ptr %t361)
  %t362 = getelementptr ptr, ptr %t4, i32 2
  %t363 = load ptr, ptr %t362
  call void @__free_recursive(ptr %t363)
  %t366 = inttoptr i64 51 to ptr
  %t367 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t366, ptr %t367
  call void @__inc_ref(ptr %t198)
  %t364 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t198, ptr %t364
  call void @__inc_ref(ptr %t341)
  %t365 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t341, ptr %t365
  call void @__free_recursive(ptr %t196)
  call void @__free_recursive(ptr %t341)
  call void @__free_recursive(ptr %t198)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.7.368:
  %t369 = call ptr @__alloc(i64 24, i32 2)
  %t370 = inttoptr i64 52 to ptr
  %t371 = getelementptr ptr, ptr %t369, i32 0
  store ptr %t370, ptr %t371
  %t372 = getelementptr ptr, ptr %t341, i32 2
  %t373 = load ptr, ptr %t372
  call void @__inc_ref(ptr %t373)
  %t374 = getelementptr ptr, ptr %t196, i32 1
  %t375 = load ptr, ptr %t374
  call void @__free_recursive(ptr %t375)
  %t377 = inttoptr i64 34 to ptr
  %t378 = getelementptr ptr, ptr %t196, i32 0
  store ptr %t377, ptr %t378
  %t376 = getelementptr ptr, ptr %t196, i32 1
  store ptr %t373, ptr %t376
  %t379 = getelementptr ptr, ptr %t369, i32 1
  store ptr %t196, ptr %t379
  %t380 = getelementptr ptr, ptr %t341, i32 1
  %t381 = load ptr, ptr %t380
  call void @__inc_ref(ptr %t381)
  %t382 = getelementptr ptr, ptr %t4, i32 1
  %t383 = load ptr, ptr %t382
  call void @__free_recursive(ptr %t383)
  %t384 = getelementptr ptr, ptr %t4, i32 2
  %t385 = load ptr, ptr %t384
  call void @__free_recursive(ptr %t385)
  %t388 = inttoptr i64 44 to ptr
  %t389 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t388, ptr %t389
  call void @__inc_ref(ptr %t198)
  %t386 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t198, ptr %t386
  %t387 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t381, ptr %t387
  %t390 = getelementptr ptr, ptr %t369, i32 2
  store ptr %t4, ptr %t390
  call void @__free_recursive(ptr %t341)
  call void @__free_recursive(ptr %t198)
  store ptr %t369, ptr %t3
  br label %tco.loop.0
tco.case.arm.8.391:
  %t392 = getelementptr ptr, ptr %t4, i32 1
  %t393 = load ptr, ptr %t392
  call void @__free_recursive(ptr %t393)
  %t394 = getelementptr ptr, ptr %t4, i32 2
  %t395 = load ptr, ptr %t394
  call void @__free_recursive(ptr %t395)
  %t409 = inttoptr i64 51 to ptr
  %t410 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t409, ptr %t410
  call void @__inc_ref(ptr %t198)
  %t396 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t198, ptr %t396
  %t397 = call ptr @__alloc(i64 16, i32 1)
  %t398 = inttoptr i64 8 to ptr
  %t399 = getelementptr ptr, ptr %t397, i32 0
  store ptr %t398, ptr %t399
  %t400 = getelementptr ptr, ptr %t341, i32 1
  %t401 = load ptr, ptr %t400
  call void @__inc_ref(ptr %t401)
  %t402 = getelementptr ptr, ptr %t196, i32 1
  %t403 = load ptr, ptr %t402
  call void @__free_recursive(ptr %t403)
  %t405 = inttoptr i64 26 to ptr
  %t406 = getelementptr ptr, ptr %t196, i32 0
  store ptr %t405, ptr %t406
  %t404 = getelementptr ptr, ptr %t196, i32 1
  store ptr %t401, ptr %t404
  %t407 = getelementptr ptr, ptr %t397, i32 1
  store ptr %t196, ptr %t407
  %t408 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t397, ptr %t408
  call void @__free_recursive(ptr %t341)
  call void @__free_recursive(ptr %t198)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.345:
  unreachable
tco.case.arm.35.411:
  %t412 = getelementptr ptr, ptr %t196, i32 1
  %t413 = load ptr, ptr %t412
  call void @__inc_ref(ptr %t413)
  %t414 = getelementptr ptr, ptr %t196, i32 2
  %t415 = load ptr, ptr %t414
  call void @__inc_ref(ptr %t415)
  %t416 = getelementptr ptr, ptr %t196, i32 3
  %t417 = load ptr, ptr %t416
  call void @__inc_ref(ptr %t417)
  %t418 = getelementptr ptr, ptr %t413, i32 0
  %t419 = load ptr, ptr %t418
  %t420 = ptrtoint ptr %t419 to i64
  switch i64 %t420, label %tco.case.default.421 [ i64 24, label %tco.case.arm.24.422 i64 25, label %tco.case.arm.25.472 ]
tco.case.arm.24.422:
  %t423 = getelementptr ptr, ptr %t413, i32 1
  %t424 = load ptr, ptr %t423
  call void @__inc_ref(ptr %t424)
  %t425 = getelementptr ptr, ptr %t4, i32 1
  %t426 = load ptr, ptr %t425
  call void @__free_recursive(ptr %t426)
  %t427 = getelementptr ptr, ptr %t4, i32 2
  %t428 = load ptr, ptr %t427
  call void @__free_recursive(ptr %t428)
  %t470 = inttoptr i64 52 to ptr
  %t471 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t470, ptr %t471
  %t429 = call ptr @__alloc(i64 24, i32 2)
  %t430 = inttoptr i64 29 to ptr
  %t431 = getelementptr ptr, ptr %t429, i32 0
  store ptr %t430, ptr %t431
  call void @__inc_ref(ptr %t415)
  %t432 = getelementptr ptr, ptr %t429, i32 1
  store ptr %t415, ptr %t432
  call void @__inc_ref(ptr %t417)
  %t433 = getelementptr ptr, ptr %t429, i32 2
  store ptr %t417, ptr %t433
  %t434 = call ptr @__alloc(i64 24, i32 2)
  %t435 = inttoptr i64 29 to ptr
  %t436 = getelementptr ptr, ptr %t434, i32 0
  store ptr %t435, ptr %t436
  call void @__inc_ref(ptr %t415)
  %t437 = getelementptr ptr, ptr %t434, i32 1
  store ptr %t415, ptr %t437
  call void @__inc_ref(ptr %t417)
  %t438 = getelementptr ptr, ptr %t434, i32 2
  store ptr %t417, ptr %t438
  %t439 = getelementptr ptr, ptr %t196, i32 1
  %t440 = load ptr, ptr %t439
  call void @__free_recursive(ptr %t440)
  %t441 = getelementptr ptr, ptr %t196, i32 2
  %t442 = load ptr, ptr %t441
  call void @__free_recursive(ptr %t442)
  %t443 = getelementptr ptr, ptr %t196, i32 3
  %t444 = load ptr, ptr %t443
  call void @__free_recursive(ptr %t444)
  %t448 = inttoptr i64 35 to ptr
  %t449 = getelementptr ptr, ptr %t196, i32 0
  store ptr %t448, ptr %t449
  call void @__inc_ref(ptr %t424)
  %t445 = getelementptr ptr, ptr %t196, i32 1
  store ptr %t424, ptr %t445
  %t446 = getelementptr ptr, ptr %t196, i32 2
  store ptr %t429, ptr %t446
  %t447 = getelementptr ptr, ptr %t196, i32 3
  store ptr %t434, ptr %t447
  %t450 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t196, ptr %t450
  %t456 = getelementptr i8, ptr %t413, i64 -8
  %t457 = load i32, ptr %t456
  %t458 = icmp eq i32 %t457, 1
  br i1 %t458, label %reuse.in_place.459, label %reuse.copy.460
reuse.in_place.459:
  %t451 = getelementptr ptr, ptr %t413, i32 1
  %t452 = load ptr, ptr %t451
  call void @__free_recursive(ptr %t452)
  %t454 = inttoptr i64 45 to ptr
  %t455 = getelementptr ptr, ptr %t413, i32 0
  store ptr %t454, ptr %t455
  call void @__inc_ref(ptr %t198)
  %t453 = getelementptr ptr, ptr %t413, i32 1
  store ptr %t198, ptr %t453
  br label %reuse.in_place.end.462
reuse.in_place.end.462:
  br label %reuse.join.461
reuse.copy.460:
  %t464 = call ptr @__alloc(i64 16, i32 1)
  %t465 = inttoptr i64 45 to ptr
  %t466 = getelementptr ptr, ptr %t464, i32 0
  store ptr %t465, ptr %t466
  call void @__inc_ref(ptr %t198)
  %t467 = getelementptr ptr, ptr %t464, i32 1
  store ptr %t198, ptr %t467
  call void @__free_recursive(ptr %t413)
  br label %reuse.copy.end.463
reuse.copy.end.463:
  br label %reuse.join.461
reuse.join.461:
  %t468 = phi ptr [ %t413, %reuse.in_place.end.462 ], [ %t464, %reuse.copy.end.463 ]
  %t469 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t468, ptr %t469
  call void @__free_recursive(ptr %t424)
  call void @__free_recursive(ptr %t417)
  call void @__free_recursive(ptr %t415)
  call void @__free_recursive(ptr %t198)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.25.472:
  %t473 = getelementptr ptr, ptr %t413, i32 1
  %t474 = load ptr, ptr %t473
  call void @__inc_ref(ptr %t474)
  %t475 = getelementptr ptr, ptr %t4, i32 1
  %t476 = load ptr, ptr %t475
  call void @__free_recursive(ptr %t476)
  %t477 = getelementptr ptr, ptr %t4, i32 2
  %t478 = load ptr, ptr %t477
  call void @__free_recursive(ptr %t478)
  %t510 = inttoptr i64 52 to ptr
  %t511 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t510, ptr %t511
  %t479 = getelementptr ptr, ptr %t196, i32 1
  %t480 = load ptr, ptr %t479
  call void @__free_recursive(ptr %t480)
  %t481 = getelementptr ptr, ptr %t196, i32 2
  %t482 = load ptr, ptr %t481
  call void @__free_recursive(ptr %t482)
  %t483 = getelementptr ptr, ptr %t196, i32 3
  %t484 = load ptr, ptr %t483
  call void @__free_recursive(ptr %t484)
  %t488 = inttoptr i64 37 to ptr
  %t489 = getelementptr ptr, ptr %t196, i32 0
  store ptr %t488, ptr %t489
  call void @__inc_ref(ptr %t415)
  %t485 = getelementptr ptr, ptr %t196, i32 1
  store ptr %t415, ptr %t485
  call void @__inc_ref(ptr %t417)
  %t486 = getelementptr ptr, ptr %t196, i32 2
  store ptr %t417, ptr %t486
  call void @__inc_ref(ptr %t474)
  %t487 = getelementptr ptr, ptr %t196, i32 3
  store ptr %t474, ptr %t487
  %t490 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t196, ptr %t490
  %t496 = getelementptr i8, ptr %t413, i64 -8
  %t497 = load i32, ptr %t496
  %t498 = icmp eq i32 %t497, 1
  br i1 %t498, label %reuse.in_place.499, label %reuse.copy.500
reuse.in_place.499:
  %t491 = getelementptr ptr, ptr %t413, i32 1
  %t492 = load ptr, ptr %t491
  call void @__free_recursive(ptr %t492)
  %t494 = inttoptr i64 46 to ptr
  %t495 = getelementptr ptr, ptr %t413, i32 0
  store ptr %t494, ptr %t495
  call void @__inc_ref(ptr %t198)
  %t493 = getelementptr ptr, ptr %t413, i32 1
  store ptr %t198, ptr %t493
  br label %reuse.in_place.end.502
reuse.in_place.end.502:
  br label %reuse.join.501
reuse.copy.500:
  %t504 = call ptr @__alloc(i64 16, i32 1)
  %t505 = inttoptr i64 46 to ptr
  %t506 = getelementptr ptr, ptr %t504, i32 0
  store ptr %t505, ptr %t506
  call void @__inc_ref(ptr %t198)
  %t507 = getelementptr ptr, ptr %t504, i32 1
  store ptr %t198, ptr %t507
  call void @__free_recursive(ptr %t413)
  br label %reuse.copy.end.503
reuse.copy.end.503:
  br label %reuse.join.501
reuse.join.501:
  %t508 = phi ptr [ %t413, %reuse.in_place.end.502 ], [ %t504, %reuse.copy.end.503 ]
  %t509 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t508, ptr %t509
  call void @__free_recursive(ptr %t474)
  call void @__free_recursive(ptr %t417)
  call void @__free_recursive(ptr %t415)
  call void @__free_recursive(ptr %t198)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.421:
  unreachable
tco.case.arm.36.512:
  %t513 = getelementptr ptr, ptr %t196, i32 1
  %t514 = load ptr, ptr %t513
  call void @__inc_ref(ptr %t514)
  %t515 = getelementptr ptr, ptr %t514, i32 0
  %t516 = load ptr, ptr %t515
  %t517 = ptrtoint ptr %t516 to i64
  switch i64 %t517, label %tco.case.default.518 [ i64 24, label %tco.case.arm.24.519 i64 25, label %tco.case.arm.25.560 ]
tco.case.arm.24.519:
  %t520 = getelementptr ptr, ptr %t514, i32 1
  %t521 = load ptr, ptr %t520
  call void @__inc_ref(ptr %t521)
  %t522 = call ptr @__alloc(i64 32, i32 3)
  %t523 = inttoptr i64 35 to ptr
  %t524 = getelementptr ptr, ptr %t522, i32 0
  store ptr %t523, ptr %t524
  call void @__inc_ref(ptr %t521)
  %t525 = getelementptr ptr, ptr %t522, i32 1
  store ptr %t521, ptr %t525
  %t526 = call ptr @__alloc(i64 8, i32 0)
  %t527 = inttoptr i64 30 to ptr
  %t528 = getelementptr ptr, ptr %t526, i32 0
  store ptr %t527, ptr %t528
  %t529 = getelementptr ptr, ptr %t522, i32 2
  store ptr %t526, ptr %t529
  %t530 = call ptr @__alloc(i64 8, i32 0)
  %t531 = inttoptr i64 30 to ptr
  %t532 = getelementptr ptr, ptr %t530, i32 0
  store ptr %t531, ptr %t532
  %t533 = getelementptr ptr, ptr %t522, i32 3
  store ptr %t530, ptr %t533
  %t534 = getelementptr ptr, ptr %t4, i32 1
  %t535 = load ptr, ptr %t534
  call void @__free_recursive(ptr %t535)
  %t536 = getelementptr ptr, ptr %t4, i32 2
  %t537 = load ptr, ptr %t536
  call void @__free_recursive(ptr %t537)
  %t558 = inttoptr i64 52 to ptr
  %t559 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t558, ptr %t559
  %t538 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t522, ptr %t538
  %t544 = getelementptr i8, ptr %t514, i64 -8
  %t545 = load i32, ptr %t544
  %t546 = icmp eq i32 %t545, 1
  br i1 %t546, label %reuse.in_place.547, label %reuse.copy.548
reuse.in_place.547:
  %t539 = getelementptr ptr, ptr %t514, i32 1
  %t540 = load ptr, ptr %t539
  call void @__free_recursive(ptr %t540)
  %t542 = inttoptr i64 47 to ptr
  %t543 = getelementptr ptr, ptr %t514, i32 0
  store ptr %t542, ptr %t543
  call void @__inc_ref(ptr %t198)
  %t541 = getelementptr ptr, ptr %t514, i32 1
  store ptr %t198, ptr %t541
  br label %reuse.in_place.end.550
reuse.in_place.end.550:
  br label %reuse.join.549
reuse.copy.548:
  %t552 = call ptr @__alloc(i64 16, i32 1)
  %t553 = inttoptr i64 47 to ptr
  %t554 = getelementptr ptr, ptr %t552, i32 0
  store ptr %t553, ptr %t554
  call void @__inc_ref(ptr %t198)
  %t555 = getelementptr ptr, ptr %t552, i32 1
  store ptr %t198, ptr %t555
  call void @__free_recursive(ptr %t514)
  br label %reuse.copy.end.551
reuse.copy.end.551:
  br label %reuse.join.549
reuse.join.549:
  %t556 = phi ptr [ %t514, %reuse.in_place.end.550 ], [ %t552, %reuse.copy.end.551 ]
  %t557 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t556, ptr %t557
  call void @__free_recursive(ptr %t521)
  call void @__free_recursive(ptr %t196)
  call void @__free_recursive(ptr %t198)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.25.560:
  %t561 = getelementptr ptr, ptr %t514, i32 1
  %t562 = load ptr, ptr %t561
  call void @__inc_ref(ptr %t562)
  %t563 = getelementptr ptr, ptr %t4, i32 1
  %t564 = load ptr, ptr %t563
  call void @__free_recursive(ptr %t564)
  %t565 = getelementptr ptr, ptr %t4, i32 2
  %t566 = load ptr, ptr %t565
  call void @__free_recursive(ptr %t566)
  %t591 = inttoptr i64 51 to ptr
  %t592 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t591, ptr %t592
  call void @__inc_ref(ptr %t198)
  %t567 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t198, ptr %t567
  %t568 = call ptr @__alloc(i64 16, i32 1)
  %t569 = inttoptr i64 796142685 to ptr
  %t570 = getelementptr ptr, ptr %t568, i32 0
  store ptr %t569, ptr %t570
  call void @__inc_ref(ptr %t562)
  %t571 = getelementptr ptr, ptr %t568, i32 1
  store ptr %t562, ptr %t571
  %t577 = getelementptr i8, ptr %t514, i64 -8
  %t578 = load i32, ptr %t577
  %t579 = icmp eq i32 %t578, 1
  br i1 %t579, label %reuse.in_place.580, label %reuse.copy.581
reuse.in_place.580:
  %t572 = getelementptr ptr, ptr %t514, i32 1
  %t573 = load ptr, ptr %t572
  call void @__free_recursive(ptr %t573)
  %t575 = inttoptr i64 25 to ptr
  %t576 = getelementptr ptr, ptr %t514, i32 0
  store ptr %t575, ptr %t576
  %t574 = getelementptr ptr, ptr %t514, i32 1
  store ptr %t568, ptr %t574
  br label %reuse.in_place.end.583
reuse.in_place.end.583:
  br label %reuse.join.582
reuse.copy.581:
  %t585 = call ptr @__alloc(i64 16, i32 1)
  %t586 = inttoptr i64 25 to ptr
  %t587 = getelementptr ptr, ptr %t585, i32 0
  store ptr %t586, ptr %t587
  %t588 = getelementptr ptr, ptr %t585, i32 1
  store ptr %t568, ptr %t588
  call void @__free_recursive(ptr %t514)
  br label %reuse.copy.end.584
reuse.copy.end.584:
  br label %reuse.join.582
reuse.join.582:
  %t589 = phi ptr [ %t514, %reuse.in_place.end.583 ], [ %t585, %reuse.copy.end.584 ]
  %t590 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t589, ptr %t590
  call void @__free_recursive(ptr %t562)
  call void @__free_recursive(ptr %t196)
  call void @__free_recursive(ptr %t198)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.518:
  unreachable
tco.case.arm.37.593:
  %t594 = getelementptr ptr, ptr %t196, i32 1
  %t595 = load ptr, ptr %t594
  call void @__inc_ref(ptr %t595)
  %t596 = getelementptr ptr, ptr %t196, i32 2
  %t597 = load ptr, ptr %t596
  %t598 = getelementptr ptr, ptr %t196, i32 3
  %t599 = load ptr, ptr %t598
  call void @__inc_ref(ptr %t599)
  %t600 = getelementptr ptr, ptr %t599, i32 0
  %t601 = load ptr, ptr %t600
  %t602 = ptrtoint ptr %t601 to i64
  switch i64 %t602, label %tco.case.default.603 [ i64 15, label %tco.case.arm.15.604 ]
tco.case.arm.15.604:
  %t605 = getelementptr ptr, ptr %t599, i32 1
  %t606 = load ptr, ptr %t605
  %t607 = getelementptr ptr, ptr %t599, i32 2
  %t608 = load ptr, ptr %t607
  call void @__inc_ref(ptr %t608)
  %t609 = getelementptr ptr, ptr %t4, i32 1
  %t610 = load ptr, ptr %t609
  call void @__free_recursive(ptr %t610)
  %t611 = getelementptr ptr, ptr %t4, i32 2
  %t612 = load ptr, ptr %t611
  call void @__free_recursive(ptr %t612)
  %t644 = inttoptr i64 52 to ptr
  %t645 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t644, ptr %t645
  %t619 = getelementptr i8, ptr %t599, i64 -8
  %t620 = load i32, ptr %t619
  %t621 = icmp eq i32 %t620, 1
  br i1 %t621, label %reuse.in_place.622, label %reuse.copy.623
reuse.in_place.622:
  %t613 = getelementptr ptr, ptr %t599, i32 2
  %t614 = load ptr, ptr %t613
  call void @__free_recursive(ptr %t614)
  %t617 = inttoptr i64 31 to ptr
  %t618 = getelementptr ptr, ptr %t599, i32 0
  store ptr %t617, ptr %t618
  call void @__inc_ref(ptr %t595)
  %t615 = getelementptr ptr, ptr %t599, i32 1
  store ptr %t595, ptr %t615
  %t616 = getelementptr ptr, ptr %t599, i32 2
  store ptr %t606, ptr %t616
  br label %reuse.in_place.end.625
reuse.in_place.end.625:
  br label %reuse.join.624
reuse.copy.623:
  %t627 = call ptr @__alloc(i64 24, i32 2)
  %t628 = inttoptr i64 31 to ptr
  %t629 = getelementptr ptr, ptr %t627, i32 0
  store ptr %t628, ptr %t629
  call void @__inc_ref(ptr %t595)
  %t630 = getelementptr ptr, ptr %t627, i32 1
  store ptr %t595, ptr %t630
  call void @__inc_ref(ptr %t606)
  %t631 = getelementptr ptr, ptr %t627, i32 2
  store ptr %t606, ptr %t631
  call void @__free_recursive(ptr %t599)
  br label %reuse.copy.end.626
reuse.copy.end.626:
  br label %reuse.join.624
reuse.join.624:
  %t632 = phi ptr [ %t599, %reuse.in_place.end.625 ], [ %t627, %reuse.copy.end.626 ]
  %t633 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t632, ptr %t633
  %t634 = getelementptr ptr, ptr %t196, i32 1
  %t635 = load ptr, ptr %t634
  call void @__free_recursive(ptr %t635)
  %t636 = getelementptr ptr, ptr %t196, i32 3
  %t637 = load ptr, ptr %t636
  call void @__free_recursive(ptr %t637)
  %t641 = inttoptr i64 48 to ptr
  %t642 = getelementptr ptr, ptr %t196, i32 0
  store ptr %t641, ptr %t642
  call void @__inc_ref(ptr %t198)
  %t638 = getelementptr ptr, ptr %t196, i32 1
  store ptr %t198, ptr %t638
  call void @__inc_ref(ptr %t608)
  %t639 = getelementptr ptr, ptr %t196, i32 2
  store ptr %t608, ptr %t639
  %t640 = getelementptr ptr, ptr %t196, i32 3
  store ptr %t597, ptr %t640
  %t643 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t196, ptr %t643
  call void @__free_recursive(ptr %t608)
  call void @__free_recursive(ptr %t595)
  call void @__free_recursive(ptr %t198)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.603:
  unreachable
tco.case.arm.38.646:
  %t647 = getelementptr ptr, ptr %t196, i32 1
  %t648 = load ptr, ptr %t647
  call void @__inc_ref(ptr %t648)
  %t649 = call ptr @__alloc(i64 16, i32 1)
  %t650 = inttoptr i64 50 to ptr
  %t651 = getelementptr ptr, ptr %t649, i32 0
  store ptr %t650, ptr %t651
  call void @__inc_ref(ptr %t198)
  %t652 = getelementptr ptr, ptr %t649, i32 1
  store ptr %t198, ptr %t652
  %t653 = getelementptr ptr, ptr %t4, i32 1
  %t654 = load ptr, ptr %t653
  call void @__free_recursive(ptr %t654)
  %t655 = getelementptr ptr, ptr %t4, i32 2
  %t656 = load ptr, ptr %t655
  call void @__free_recursive(ptr %t656)
  %t725 = inttoptr i64 52 to ptr
  %t726 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t725, ptr %t726
  %t657 = call ptr @__alloc(i64 16, i32 1)
  %t658 = inttoptr i64 36 to ptr
  %t659 = getelementptr ptr, ptr %t657, i32 0
  store ptr %t658, ptr %t659
  %t660 = getelementptr ptr, ptr %t648, i32 0
  %t661 = load ptr, ptr %t660
  %t662 = ptrtoint ptr %t661 to i64
  switch i64 %t662, label %case.default.663 [ i64 13, label %case.arm.13.665 i64 14, label %case.arm.14.686 ]
case.arm.13.665:
  %t667 = getelementptr ptr, ptr %t196, i32 1
  %t668 = load ptr, ptr %t667
  call void @__free_recursive(ptr %t668)
  %t684 = inttoptr i64 25 to ptr
  %t685 = getelementptr ptr, ptr %t196, i32 0
  store ptr %t684, ptr %t685
  %t671 = getelementptr i8, ptr %t648, i64 -8
  %t672 = load i32, ptr %t671
  %t673 = icmp eq i32 %t672, 1
  br i1 %t673, label %reuse.in_place.674, label %reuse.copy.675
reuse.in_place.674:
  %t669 = inttoptr i64 1 to ptr
  %t670 = getelementptr ptr, ptr %t648, i32 0
  store ptr %t669, ptr %t670
  br label %reuse.in_place.end.677
reuse.in_place.end.677:
  br label %reuse.join.676
reuse.copy.675:
  %t679 = call ptr @__alloc(i64 8, i32 0)
  %t680 = inttoptr i64 1 to ptr
  %t681 = getelementptr ptr, ptr %t679, i32 0
  store ptr %t680, ptr %t681
  call void @__free_recursive(ptr %t648)
  br label %reuse.copy.end.678
reuse.copy.end.678:
  br label %reuse.join.676
reuse.join.676:
  %t682 = phi ptr [ %t648, %reuse.in_place.end.677 ], [ %t679, %reuse.copy.end.678 ]
  %t683 = getelementptr ptr, ptr %t196, i32 1
  store ptr %t682, ptr %t683
  br label %case.end.13.666
case.end.13.666:
  br label %case.join.664
case.arm.14.686:
  %t688 = call ptr @__alloc(i64 16, i32 1)
  %t689 = inttoptr i64 24 to ptr
  %t690 = getelementptr ptr, ptr %t688, i32 0
  store ptr %t689, ptr %t690
  %t691 = getelementptr ptr, ptr %t196, i32 1
  %t692 = load ptr, ptr %t691
  call void @__free_recursive(ptr %t692)
  %t718 = inttoptr i64 25 to ptr
  %t719 = getelementptr ptr, ptr %t196, i32 0
  store ptr %t718, ptr %t719
  %t693 = call ptr @__alloc(i64 8, i32 0)
  %t694 = inttoptr i64 1 to ptr
  %t695 = getelementptr ptr, ptr %t693, i32 0
  store ptr %t694, ptr %t695
  %t696 = call ptr @__alloc(i64 8, i32 0)
  %t697 = inttoptr i64 2 to ptr
  %t698 = getelementptr ptr, ptr %t696, i32 0
  store ptr %t697, ptr %t698
  %t703 = getelementptr i8, ptr %t648, i64 -8
  %t704 = load i32, ptr %t703
  %t705 = icmp eq i32 %t704, 1
  br i1 %t705, label %reuse.in_place.706, label %reuse.copy.707
reuse.in_place.706:
  %t701 = inttoptr i64 15 to ptr
  %t702 = getelementptr ptr, ptr %t648, i32 0
  store ptr %t701, ptr %t702
  %t699 = getelementptr ptr, ptr %t648, i32 1
  store ptr %t693, ptr %t699
  %t700 = getelementptr ptr, ptr %t648, i32 2
  store ptr %t696, ptr %t700
  br label %reuse.in_place.end.709
reuse.in_place.end.709:
  br label %reuse.join.708
reuse.copy.707:
  %t711 = call ptr @__alloc(i64 24, i32 2)
  %t712 = inttoptr i64 15 to ptr
  %t713 = getelementptr ptr, ptr %t711, i32 0
  store ptr %t712, ptr %t713
  %t714 = getelementptr ptr, ptr %t711, i32 1
  store ptr %t693, ptr %t714
  %t715 = getelementptr ptr, ptr %t711, i32 2
  store ptr %t696, ptr %t715
  call void @__free_recursive(ptr %t648)
  br label %reuse.copy.end.710
reuse.copy.end.710:
  br label %reuse.join.708
reuse.join.708:
  %t716 = phi ptr [ %t648, %reuse.in_place.end.709 ], [ %t711, %reuse.copy.end.710 ]
  %t717 = getelementptr ptr, ptr %t196, i32 1
  store ptr %t716, ptr %t717
  %t720 = getelementptr ptr, ptr %t688, i32 1
  store ptr %t196, ptr %t720
  br label %case.end.14.687
case.end.14.687:
  br label %case.join.664
case.default.663:
  unreachable
case.join.664:
  %t721 = phi ptr [ %t196, %case.end.13.666 ], [ %t688, %case.end.14.687 ]
  %t722 = getelementptr ptr, ptr %t657, i32 1
  store ptr %t721, ptr %t722
  %t723 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t657, ptr %t723
  %t724 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t649, ptr %t724
  call void @__free_recursive(ptr %t198)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.202:
  unreachable
tco.case.default.8:
  unreachable
tco.exit.1:
  %t727 = load ptr, ptr %t2
  ret ptr %t727
}

define i32 @main(i32 %argc, ptr %argv) {
  %argc64 = sext i32 %argc to i64
  store i64 %argc64, ptr @.cli_argc
  store ptr %argv, ptr @.cli_argv
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
