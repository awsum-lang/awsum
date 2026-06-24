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
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [13 x i8]} { i32 0, i32 0, i32 0, i32 13, i32 13, [13 x i8] c"deeper-deeper" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [19 x i8]} { i32 0, i32 0, i32 0, i32 19, i32 19, [19 x i8] c"deeper-base-nothing" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [21 x i8]} { i32 0, i32 0, i32 0, i32 21, i32 21, [21 x i8] c"deeper-base-just-bool" }
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [9 x i8]} { i32 0, i32 0, i32 0, i32 9, i32 9, [9 x i8] c"base-bool" }

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
  %t21 = inttoptr i64 51 to ptr
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
  %t35 = call ptr @v_$scc$$apply$$scc$$apply1__$df$$lam$13$7__$df$$lam$9$3__$df$$rowmono$0$andThenIO$6__$df$mapNest$0__$df$mapNest$1__mapMaybe2__run2__$cps$$scc$$apply1__$df$$lam$13$7__$df$$lam$9$3__$df$$rowmono$0$andThenIO$6__$df$mapNest$0__$df$mapNest$1__mapMaybe2__run2(ptr %t20)
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
  %t1 = inttoptr i64 51 to ptr
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
  %t19 = call ptr @v_$scc$$apply$$scc$$apply1__$df$$lam$13$7__$df$$lam$9$3__$df$$rowmono$0$andThenIO$6__$df$mapNest$0__$df$mapNest$1__mapMaybe2__run2__$cps$$scc$$apply1__$df$$lam$13$7__$df$$lam$9$3__$df$$rowmono$0$andThenIO$6__$df$mapNest$0__$df$mapNest$1__mapMaybe2__run2(ptr %t0)
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

define internal ptr @v_$scc$$apply$$scc$$apply1__$df$$lam$13$7__$df$$lam$9$3__$df$$rowmono$0$andThenIO$6__$df$mapNest$0__$df$mapNest$1__mapMaybe2__run2__$cps$$scc$$apply1__$df$$lam$13$7__$df$$lam$9$3__$df$$rowmono$0$andThenIO$6__$df$mapNest$0__$df$mapNest$1__mapMaybe2__run2(ptr %v_$args$1) {
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
  switch i64 %t7, label %tco.case.default.8 [ i64 50, label %tco.case.arm.50.9 i64 51, label %tco.case.arm.51.181 ]
tco.case.arm.50.9:
  %t10 = getelementptr ptr, ptr %t4, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  %t12 = getelementptr ptr, ptr %t4, i32 2
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t11, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %tco.case.default.17 [ i64 41, label %tco.case.arm.41.18 i64 42, label %tco.case.arm.42.19 i64 43, label %tco.case.arm.43.34 i64 44, label %tco.case.arm.44.49 i64 45, label %tco.case.arm.45.64 i64 46, label %tco.case.arm.46.79 i64 47, label %tco.case.arm.47.94 i64 48, label %tco.case.arm.48.109 i64 49, label %tco.case.arm.49.124 ]
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
  %t32 = inttoptr i64 51 to ptr
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
  %t47 = inttoptr i64 50 to ptr
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
  %t51 = inttoptr i64 50 to ptr
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
  %t77 = inttoptr i64 50 to ptr
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
  %t92 = inttoptr i64 50 to ptr
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
  %t107 = inttoptr i64 50 to ptr
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
tco.case.arm.48.109:
  %t110 = getelementptr ptr, ptr %t11, i32 1
  %t111 = load ptr, ptr %t110
  call void @__inc_ref(ptr %t111)
  %t112 = call ptr @__alloc(i64 16, i32 1)
  %t113 = inttoptr i64 12 to ptr
  %t114 = getelementptr ptr, ptr %t112, i32 0
  store ptr %t113, ptr %t114
  call void @__inc_ref(ptr %t13)
  %t115 = getelementptr ptr, ptr %t112, i32 1
  store ptr %t13, ptr %t115
  %t116 = getelementptr ptr, ptr %t4, i32 1
  %t117 = load ptr, ptr %t116
  call void @__free_recursive(ptr %t117)
  %t118 = getelementptr ptr, ptr %t4, i32 2
  %t119 = load ptr, ptr %t118
  call void @__free_recursive(ptr %t119)
  %t122 = inttoptr i64 50 to ptr
  %t123 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t122, ptr %t123
  %t120 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t111, ptr %t120
  %t121 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t112, ptr %t121
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.49.124:
  %t125 = call ptr @__alloc(i64 24, i32 2)
  %t126 = inttoptr i64 50 to ptr
  %t127 = getelementptr ptr, ptr %t125, i32 0
  store ptr %t126, ptr %t127
  %t128 = getelementptr ptr, ptr %t11, i32 1
  %t129 = load ptr, ptr %t128
  call void @__inc_ref(ptr %t129)
  %t130 = getelementptr ptr, ptr %t125, i32 1
  store ptr %t129, ptr %t130
  %t131 = getelementptr ptr, ptr %t13, i32 0
  %t132 = load ptr, ptr %t131
  %t133 = ptrtoint ptr %t132 to i64
  switch i64 %t133, label %case.default.134 [ i64 24, label %case.arm.24.136 i64 25, label %case.arm.25.162 ]
case.arm.24.136:
  %t138 = getelementptr ptr, ptr %t13, i32 1
  %t139 = load ptr, ptr %t138
  call void @__inc_ref(ptr %t139)
  %t140 = getelementptr ptr, ptr %t139, i32 0
  %t141 = load ptr, ptr %t140
  %t142 = ptrtoint ptr %t141 to i64
  switch i64 %t142, label %case.default.143 [ i64 24, label %case.arm.24.145 i64 25, label %case.arm.25.147 ]
case.arm.24.145:
  br label %case.end.24.146
case.end.24.146:
  br label %case.join.144
case.arm.25.147:
  %t149 = getelementptr ptr, ptr %t139, i32 1
  %t150 = load ptr, ptr %t149
  call void @__inc_ref(ptr %t150)
  %t151 = getelementptr ptr, ptr %t150, i32 0
  %t152 = load ptr, ptr %t151
  %t153 = ptrtoint ptr %t152 to i64
  switch i64 %t153, label %case.default.154 [ i64 11, label %case.arm.11.156 i64 12, label %case.arm.12.158 ]
case.arm.11.156:
  br label %case.end.11.157
case.end.11.157:
  br label %case.join.155
case.arm.12.158:
  br label %case.end.12.159
case.end.12.159:
  br label %case.join.155
case.default.154:
  unreachable
case.join.155:
  %t160 = phi ptr [ getelementptr inbounds (i8, ptr @.str.3, i64 12), %case.end.11.157 ], [ getelementptr inbounds (i8, ptr @.str.4, i64 12), %case.end.12.159 ]
  call void @__free_recursive(ptr %t150)
  br label %case.end.25.148
case.end.25.148:
  br label %case.join.144
case.default.143:
  unreachable
case.join.144:
  %t161 = phi ptr [ getelementptr inbounds (i8, ptr @.str.2, i64 12), %case.end.24.146 ], [ %t160, %case.end.25.148 ]
  call void @__free_recursive(ptr %t139)
  br label %case.end.24.137
case.end.24.137:
  br label %case.join.135
case.arm.25.162:
  br label %case.end.25.163
case.end.25.163:
  br label %case.join.135
case.default.134:
  unreachable
case.join.135:
  %t164 = phi ptr [ %t161, %case.end.24.137 ], [ getelementptr inbounds (i8, ptr @.str.5, i64 12), %case.end.25.163 ]
  %t165 = call ptr @__alloc(i64 16, i32 1)
  %t166 = inttoptr i64 5 to ptr
  %t167 = getelementptr ptr, ptr %t165, i32 0
  store ptr %t166, ptr %t167
  %t168 = call ptr @__alloc(i64 8, i32 0)
  %t169 = inttoptr i64 0 to ptr
  %t170 = getelementptr ptr, ptr %t168, i32 0
  store ptr %t169, ptr %t170
  %t171 = getelementptr ptr, ptr %t165, i32 1
  store ptr %t168, ptr %t171
  %t172 = getelementptr ptr, ptr %t4, i32 1
  %t173 = load ptr, ptr %t172
  call void @__free_recursive(ptr %t173)
  %t174 = getelementptr ptr, ptr %t4, i32 2
  %t175 = load ptr, ptr %t174
  call void @__free_recursive(ptr %t175)
  %t178 = inttoptr i64 7 to ptr
  %t179 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t178, ptr %t179
  %t176 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t164, ptr %t176
  %t177 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t165, ptr %t177
  %t180 = getelementptr ptr, ptr %t125, i32 2
  store ptr %t4, ptr %t180
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t125, ptr %t3
  br label %tco.loop.0
tco.case.default.17:
  unreachable
tco.case.arm.51.181:
  %t182 = getelementptr ptr, ptr %t4, i32 1
  %t183 = load ptr, ptr %t182
  call void @__inc_ref(ptr %t183)
  %t184 = getelementptr ptr, ptr %t4, i32 2
  %t185 = load ptr, ptr %t184
  call void @__inc_ref(ptr %t185)
  %t186 = getelementptr ptr, ptr %t183, i32 0
  %t187 = load ptr, ptr %t186
  %t188 = ptrtoint ptr %t187 to i64
  switch i64 %t188, label %tco.case.default.189 [ i64 31, label %tco.case.arm.31.190 i64 32, label %tco.case.arm.32.282 i64 33, label %tco.case.arm.33.301 i64 34, label %tco.case.arm.34.320 i64 35, label %tco.case.arm.35.392 i64 36, label %tco.case.arm.36.479 i64 37, label %tco.case.arm.37.556 i64 38, label %tco.case.arm.38.589 ]
tco.case.arm.31.190:
  %t191 = getelementptr ptr, ptr %t183, i32 1
  %t192 = load ptr, ptr %t191
  call void @__inc_ref(ptr %t192)
  %t193 = getelementptr ptr, ptr %t183, i32 2
  %t194 = load ptr, ptr %t193
  call void @__inc_ref(ptr %t194)
  %t195 = getelementptr ptr, ptr %t192, i32 0
  %t196 = load ptr, ptr %t195
  %t197 = ptrtoint ptr %t196 to i64
  switch i64 %t197, label %tco.case.default.198 [ i64 26, label %tco.case.arm.26.199 i64 27, label %tco.case.arm.27.212 i64 28, label %tco.case.arm.28.225 i64 29, label %tco.case.arm.29.256 i64 30, label %tco.case.arm.30.269 ]
tco.case.arm.26.199:
  %t200 = getelementptr ptr, ptr %t4, i32 1
  %t201 = load ptr, ptr %t200
  call void @__free_recursive(ptr %t201)
  %t210 = inttoptr i64 51 to ptr
  %t211 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t210, ptr %t211
  %t202 = getelementptr ptr, ptr %t192, i32 1
  %t203 = load ptr, ptr %t202
  call void @__inc_ref(ptr %t203)
  %t204 = getelementptr ptr, ptr %t183, i32 1
  %t205 = load ptr, ptr %t204
  call void @__free_recursive(ptr %t205)
  %t207 = inttoptr i64 32 to ptr
  %t208 = getelementptr ptr, ptr %t183, i32 0
  store ptr %t207, ptr %t208
  %t206 = getelementptr ptr, ptr %t183, i32 1
  store ptr %t203, ptr %t206
  %t209 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t183, ptr %t209
  call void @__free_recursive(ptr %t194)
  call void @__free_recursive(ptr %t192)
  call void @__free_recursive(ptr %t185)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.27.212:
  %t213 = getelementptr ptr, ptr %t4, i32 1
  %t214 = load ptr, ptr %t213
  call void @__free_recursive(ptr %t214)
  %t223 = inttoptr i64 51 to ptr
  %t224 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t223, ptr %t224
  %t215 = getelementptr ptr, ptr %t192, i32 1
  %t216 = load ptr, ptr %t215
  call void @__inc_ref(ptr %t216)
  %t217 = getelementptr ptr, ptr %t183, i32 1
  %t218 = load ptr, ptr %t217
  call void @__free_recursive(ptr %t218)
  %t220 = inttoptr i64 33 to ptr
  %t221 = getelementptr ptr, ptr %t183, i32 0
  store ptr %t220, ptr %t221
  %t219 = getelementptr ptr, ptr %t183, i32 1
  store ptr %t216, ptr %t219
  %t222 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t183, ptr %t222
  call void @__free_recursive(ptr %t194)
  call void @__free_recursive(ptr %t192)
  call void @__free_recursive(ptr %t185)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.28.225:
  %t226 = getelementptr ptr, ptr %t194, i32 0
  %t227 = load ptr, ptr %t226
  %t228 = ptrtoint ptr %t227 to i64
  switch i64 %t228, label %case.default.229 [ i64 3, label %case.arm.3.231 i64 4, label %case.arm.4.239 ]
case.arm.3.231:
  %t233 = call ptr @__alloc(i64 16, i32 1)
  %t234 = inttoptr i64 6 to ptr
  %t235 = getelementptr ptr, ptr %t233, i32 0
  store ptr %t234, ptr %t235
  %t236 = getelementptr ptr, ptr %t194, i32 1
  %t237 = load ptr, ptr %t236
  call void @__inc_ref(ptr %t237)
  %t238 = getelementptr ptr, ptr %t233, i32 1
  store ptr %t237, ptr %t238
  br label %case.end.3.232
case.end.3.232:
  br label %case.join.230
case.arm.4.239:
  %t241 = call ptr @__alloc(i64 16, i32 1)
  %t242 = inttoptr i64 5 to ptr
  %t243 = getelementptr ptr, ptr %t241, i32 0
  store ptr %t242, ptr %t243
  %t244 = getelementptr ptr, ptr %t194, i32 1
  %t245 = load ptr, ptr %t244
  call void @__inc_ref(ptr %t245)
  %t246 = getelementptr ptr, ptr %t241, i32 1
  store ptr %t245, ptr %t246
  br label %case.end.4.240
case.end.4.240:
  br label %case.join.230
case.default.229:
  unreachable
case.join.230:
  %t247 = phi ptr [ %t233, %case.end.3.232 ], [ %t241, %case.end.4.240 ]
  %t248 = getelementptr ptr, ptr %t183, i32 1
  %t249 = load ptr, ptr %t248
  call void @__free_recursive(ptr %t249)
  %t250 = getelementptr ptr, ptr %t183, i32 2
  %t251 = load ptr, ptr %t250
  call void @__free_recursive(ptr %t251)
  %t254 = inttoptr i64 50 to ptr
  %t255 = getelementptr ptr, ptr %t183, i32 0
  store ptr %t254, ptr %t255
  call void @__inc_ref(ptr %t185)
  %t252 = getelementptr ptr, ptr %t183, i32 1
  store ptr %t185, ptr %t252
  %t253 = getelementptr ptr, ptr %t183, i32 2
  store ptr %t247, ptr %t253
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t194)
  call void @__free_recursive(ptr %t192)
  call void @__free_recursive(ptr %t185)
  store ptr %t183, ptr %t3
  br label %tco.loop.0
tco.case.arm.29.256:
  %t257 = call ptr @__alloc(i64 16, i32 1)
  %t258 = inttoptr i64 796142685 to ptr
  %t259 = getelementptr ptr, ptr %t257, i32 0
  store ptr %t258, ptr %t259
  call void @__inc_ref(ptr %t194)
  %t260 = getelementptr ptr, ptr %t257, i32 1
  store ptr %t194, ptr %t260
  %t261 = getelementptr ptr, ptr %t183, i32 1
  %t262 = load ptr, ptr %t261
  call void @__free_recursive(ptr %t262)
  %t263 = getelementptr ptr, ptr %t183, i32 2
  %t264 = load ptr, ptr %t263
  call void @__free_recursive(ptr %t264)
  %t267 = inttoptr i64 50 to ptr
  %t268 = getelementptr ptr, ptr %t183, i32 0
  store ptr %t267, ptr %t268
  call void @__inc_ref(ptr %t185)
  %t265 = getelementptr ptr, ptr %t183, i32 1
  store ptr %t185, ptr %t265
  %t266 = getelementptr ptr, ptr %t183, i32 2
  store ptr %t257, ptr %t266
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t194)
  call void @__free_recursive(ptr %t192)
  call void @__free_recursive(ptr %t185)
  store ptr %t183, ptr %t3
  br label %tco.loop.0
tco.case.arm.30.269:
  %t270 = getelementptr ptr, ptr %t4, i32 1
  %t271 = load ptr, ptr %t270
  call void @__free_recursive(ptr %t271)
  %t280 = inttoptr i64 51 to ptr
  %t281 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t280, ptr %t281
  %t272 = getelementptr ptr, ptr %t192, i32 1
  %t273 = load ptr, ptr %t272
  call void @__inc_ref(ptr %t273)
  %t274 = getelementptr ptr, ptr %t183, i32 1
  %t275 = load ptr, ptr %t274
  call void @__free_recursive(ptr %t275)
  %t277 = inttoptr i64 37 to ptr
  %t278 = getelementptr ptr, ptr %t183, i32 0
  store ptr %t277, ptr %t278
  %t276 = getelementptr ptr, ptr %t183, i32 1
  store ptr %t273, ptr %t276
  %t279 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t183, ptr %t279
  call void @__free_recursive(ptr %t194)
  call void @__free_recursive(ptr %t192)
  call void @__free_recursive(ptr %t185)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.198:
  unreachable
tco.case.arm.32.282:
  %t283 = getelementptr ptr, ptr %t183, i32 1
  %t284 = load ptr, ptr %t283
  %t285 = getelementptr ptr, ptr %t183, i32 2
  %t286 = load ptr, ptr %t285
  %t287 = call ptr @__alloc(i64 16, i32 1)
  %t288 = inttoptr i64 42 to ptr
  %t289 = getelementptr ptr, ptr %t287, i32 0
  store ptr %t288, ptr %t289
  call void @__inc_ref(ptr %t185)
  %t290 = getelementptr ptr, ptr %t287, i32 1
  store ptr %t185, ptr %t290
  %t291 = getelementptr ptr, ptr %t4, i32 1
  %t292 = load ptr, ptr %t291
  call void @__free_recursive(ptr %t292)
  %t293 = getelementptr ptr, ptr %t4, i32 2
  %t294 = load ptr, ptr %t293
  call void @__free_recursive(ptr %t294)
  %t299 = inttoptr i64 51 to ptr
  %t300 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t299, ptr %t300
  %t295 = inttoptr i64 31 to ptr
  %t296 = getelementptr ptr, ptr %t183, i32 0
  store ptr %t295, ptr %t296
  %t297 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t183, ptr %t297
  %t298 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t287, ptr %t298
  call void @__free_recursive(ptr %t185)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.33.301:
  %t302 = getelementptr ptr, ptr %t183, i32 1
  %t303 = load ptr, ptr %t302
  %t304 = getelementptr ptr, ptr %t183, i32 2
  %t305 = load ptr, ptr %t304
  %t306 = call ptr @__alloc(i64 16, i32 1)
  %t307 = inttoptr i64 43 to ptr
  %t308 = getelementptr ptr, ptr %t306, i32 0
  store ptr %t307, ptr %t308
  call void @__inc_ref(ptr %t185)
  %t309 = getelementptr ptr, ptr %t306, i32 1
  store ptr %t185, ptr %t309
  %t310 = getelementptr ptr, ptr %t4, i32 1
  %t311 = load ptr, ptr %t310
  call void @__free_recursive(ptr %t311)
  %t312 = getelementptr ptr, ptr %t4, i32 2
  %t313 = load ptr, ptr %t312
  call void @__free_recursive(ptr %t313)
  %t318 = inttoptr i64 51 to ptr
  %t319 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t318, ptr %t319
  %t314 = inttoptr i64 31 to ptr
  %t315 = getelementptr ptr, ptr %t183, i32 0
  store ptr %t314, ptr %t315
  %t316 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t183, ptr %t316
  %t317 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t306, ptr %t317
  call void @__free_recursive(ptr %t185)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.34.320:
  %t321 = getelementptr ptr, ptr %t183, i32 1
  %t322 = load ptr, ptr %t321
  call void @__inc_ref(ptr %t322)
  %t323 = getelementptr ptr, ptr %t322, i32 0
  %t324 = load ptr, ptr %t323
  %t325 = ptrtoint ptr %t324 to i64
  switch i64 %t325, label %tco.case.default.326 [ i64 5, label %tco.case.arm.5.327 i64 6, label %tco.case.arm.6.340 i64 7, label %tco.case.arm.7.349 i64 8, label %tco.case.arm.8.372 ]
tco.case.arm.5.327:
  %t328 = getelementptr ptr, ptr %t4, i32 1
  %t329 = load ptr, ptr %t328
  call void @__free_recursive(ptr %t329)
  %t338 = inttoptr i64 51 to ptr
  %t339 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t338, ptr %t339
  %t330 = getelementptr ptr, ptr %t322, i32 1
  %t331 = load ptr, ptr %t330
  call void @__inc_ref(ptr %t331)
  %t332 = getelementptr ptr, ptr %t183, i32 1
  %t333 = load ptr, ptr %t332
  call void @__free_recursive(ptr %t333)
  %t335 = inttoptr i64 38 to ptr
  %t336 = getelementptr ptr, ptr %t183, i32 0
  store ptr %t335, ptr %t336
  %t334 = getelementptr ptr, ptr %t183, i32 1
  store ptr %t331, ptr %t334
  %t337 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t183, ptr %t337
  call void @__free_recursive(ptr %t322)
  call void @__free_recursive(ptr %t185)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.6.340:
  %t341 = getelementptr ptr, ptr %t4, i32 1
  %t342 = load ptr, ptr %t341
  call void @__free_recursive(ptr %t342)
  %t343 = getelementptr ptr, ptr %t4, i32 2
  %t344 = load ptr, ptr %t343
  call void @__free_recursive(ptr %t344)
  %t347 = inttoptr i64 50 to ptr
  %t348 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t347, ptr %t348
  call void @__inc_ref(ptr %t185)
  %t345 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t185, ptr %t345
  call void @__inc_ref(ptr %t322)
  %t346 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t322, ptr %t346
  call void @__free_recursive(ptr %t183)
  call void @__free_recursive(ptr %t322)
  call void @__free_recursive(ptr %t185)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.7.349:
  %t350 = call ptr @__alloc(i64 24, i32 2)
  %t351 = inttoptr i64 51 to ptr
  %t352 = getelementptr ptr, ptr %t350, i32 0
  store ptr %t351, ptr %t352
  %t353 = getelementptr ptr, ptr %t322, i32 2
  %t354 = load ptr, ptr %t353
  call void @__inc_ref(ptr %t354)
  %t355 = getelementptr ptr, ptr %t183, i32 1
  %t356 = load ptr, ptr %t355
  call void @__free_recursive(ptr %t356)
  %t358 = inttoptr i64 34 to ptr
  %t359 = getelementptr ptr, ptr %t183, i32 0
  store ptr %t358, ptr %t359
  %t357 = getelementptr ptr, ptr %t183, i32 1
  store ptr %t354, ptr %t357
  %t360 = getelementptr ptr, ptr %t350, i32 1
  store ptr %t183, ptr %t360
  %t361 = getelementptr ptr, ptr %t322, i32 1
  %t362 = load ptr, ptr %t361
  call void @__inc_ref(ptr %t362)
  %t363 = getelementptr ptr, ptr %t4, i32 1
  %t364 = load ptr, ptr %t363
  call void @__free_recursive(ptr %t364)
  %t365 = getelementptr ptr, ptr %t4, i32 2
  %t366 = load ptr, ptr %t365
  call void @__free_recursive(ptr %t366)
  %t369 = inttoptr i64 44 to ptr
  %t370 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t369, ptr %t370
  call void @__inc_ref(ptr %t185)
  %t367 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t185, ptr %t367
  %t368 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t362, ptr %t368
  %t371 = getelementptr ptr, ptr %t350, i32 2
  store ptr %t4, ptr %t371
  call void @__free_recursive(ptr %t322)
  call void @__free_recursive(ptr %t185)
  store ptr %t350, ptr %t3
  br label %tco.loop.0
tco.case.arm.8.372:
  %t373 = getelementptr ptr, ptr %t4, i32 1
  %t374 = load ptr, ptr %t373
  call void @__free_recursive(ptr %t374)
  %t375 = getelementptr ptr, ptr %t4, i32 2
  %t376 = load ptr, ptr %t375
  call void @__free_recursive(ptr %t376)
  %t390 = inttoptr i64 50 to ptr
  %t391 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t390, ptr %t391
  call void @__inc_ref(ptr %t185)
  %t377 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t185, ptr %t377
  %t378 = call ptr @__alloc(i64 16, i32 1)
  %t379 = inttoptr i64 8 to ptr
  %t380 = getelementptr ptr, ptr %t378, i32 0
  store ptr %t379, ptr %t380
  %t381 = getelementptr ptr, ptr %t322, i32 1
  %t382 = load ptr, ptr %t381
  call void @__inc_ref(ptr %t382)
  %t383 = getelementptr ptr, ptr %t183, i32 1
  %t384 = load ptr, ptr %t383
  call void @__free_recursive(ptr %t384)
  %t386 = inttoptr i64 26 to ptr
  %t387 = getelementptr ptr, ptr %t183, i32 0
  store ptr %t386, ptr %t387
  %t385 = getelementptr ptr, ptr %t183, i32 1
  store ptr %t382, ptr %t385
  %t388 = getelementptr ptr, ptr %t378, i32 1
  store ptr %t183, ptr %t388
  %t389 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t378, ptr %t389
  call void @__free_recursive(ptr %t322)
  call void @__free_recursive(ptr %t185)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.326:
  unreachable
tco.case.arm.35.392:
  %t393 = getelementptr ptr, ptr %t183, i32 1
  %t394 = load ptr, ptr %t393
  call void @__inc_ref(ptr %t394)
  %t395 = getelementptr ptr, ptr %t183, i32 2
  %t396 = load ptr, ptr %t395
  call void @__inc_ref(ptr %t396)
  %t397 = getelementptr ptr, ptr %t394, i32 0
  %t398 = load ptr, ptr %t397
  %t399 = ptrtoint ptr %t398 to i64
  switch i64 %t399, label %tco.case.default.400 [ i64 24, label %tco.case.arm.24.401 i64 25, label %tco.case.arm.25.442 ]
tco.case.arm.24.401:
  %t402 = getelementptr ptr, ptr %t394, i32 1
  %t403 = load ptr, ptr %t402
  call void @__inc_ref(ptr %t403)
  %t404 = call ptr @__alloc(i64 16, i32 1)
  %t405 = inttoptr i64 45 to ptr
  %t406 = getelementptr ptr, ptr %t404, i32 0
  store ptr %t405, ptr %t406
  call void @__inc_ref(ptr %t185)
  %t407 = getelementptr ptr, ptr %t404, i32 1
  store ptr %t185, ptr %t407
  %t408 = getelementptr ptr, ptr %t4, i32 1
  %t409 = load ptr, ptr %t408
  call void @__free_recursive(ptr %t409)
  %t410 = getelementptr ptr, ptr %t4, i32 2
  %t411 = load ptr, ptr %t410
  call void @__free_recursive(ptr %t411)
  %t440 = inttoptr i64 51 to ptr
  %t441 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t440, ptr %t441
  %t412 = getelementptr ptr, ptr %t183, i32 1
  %t413 = load ptr, ptr %t412
  call void @__free_recursive(ptr %t413)
  %t414 = getelementptr ptr, ptr %t183, i32 2
  %t415 = load ptr, ptr %t414
  call void @__free_recursive(ptr %t415)
  %t436 = inttoptr i64 35 to ptr
  %t437 = getelementptr ptr, ptr %t183, i32 0
  store ptr %t436, ptr %t437
  call void @__inc_ref(ptr %t403)
  %t416 = getelementptr ptr, ptr %t183, i32 1
  store ptr %t403, ptr %t416
  %t422 = getelementptr i8, ptr %t394, i64 -8
  %t423 = load i32, ptr %t422
  %t424 = icmp eq i32 %t423, 1
  br i1 %t424, label %reuse.in_place.425, label %reuse.copy.426
reuse.in_place.425:
  %t417 = getelementptr ptr, ptr %t394, i32 1
  %t418 = load ptr, ptr %t417
  call void @__free_recursive(ptr %t418)
  %t420 = inttoptr i64 30 to ptr
  %t421 = getelementptr ptr, ptr %t394, i32 0
  store ptr %t420, ptr %t421
  call void @__inc_ref(ptr %t396)
  %t419 = getelementptr ptr, ptr %t394, i32 1
  store ptr %t396, ptr %t419
  br label %reuse.in_place.end.428
reuse.in_place.end.428:
  br label %reuse.join.427
reuse.copy.426:
  %t430 = call ptr @__alloc(i64 16, i32 1)
  %t431 = inttoptr i64 30 to ptr
  %t432 = getelementptr ptr, ptr %t430, i32 0
  store ptr %t431, ptr %t432
  call void @__inc_ref(ptr %t396)
  %t433 = getelementptr ptr, ptr %t430, i32 1
  store ptr %t396, ptr %t433
  call void @__free_recursive(ptr %t394)
  br label %reuse.copy.end.429
reuse.copy.end.429:
  br label %reuse.join.427
reuse.join.427:
  %t434 = phi ptr [ %t394, %reuse.in_place.end.428 ], [ %t430, %reuse.copy.end.429 ]
  %t435 = getelementptr ptr, ptr %t183, i32 2
  store ptr %t434, ptr %t435
  %t438 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t183, ptr %t438
  %t439 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t404, ptr %t439
  call void @__free_recursive(ptr %t403)
  call void @__free_recursive(ptr %t396)
  call void @__free_recursive(ptr %t185)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.25.442:
  %t443 = getelementptr ptr, ptr %t394, i32 1
  %t444 = load ptr, ptr %t443
  call void @__inc_ref(ptr %t444)
  %t445 = getelementptr ptr, ptr %t4, i32 1
  %t446 = load ptr, ptr %t445
  call void @__free_recursive(ptr %t446)
  %t447 = getelementptr ptr, ptr %t4, i32 2
  %t448 = load ptr, ptr %t447
  call void @__free_recursive(ptr %t448)
  %t477 = inttoptr i64 51 to ptr
  %t478 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t477, ptr %t478
  %t449 = getelementptr ptr, ptr %t183, i32 1
  %t450 = load ptr, ptr %t449
  call void @__free_recursive(ptr %t450)
  %t451 = getelementptr ptr, ptr %t183, i32 2
  %t452 = load ptr, ptr %t451
  call void @__free_recursive(ptr %t452)
  %t455 = inttoptr i64 37 to ptr
  %t456 = getelementptr ptr, ptr %t183, i32 0
  store ptr %t455, ptr %t456
  call void @__inc_ref(ptr %t396)
  %t453 = getelementptr ptr, ptr %t183, i32 1
  store ptr %t396, ptr %t453
  call void @__inc_ref(ptr %t444)
  %t454 = getelementptr ptr, ptr %t183, i32 2
  store ptr %t444, ptr %t454
  %t457 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t183, ptr %t457
  %t463 = getelementptr i8, ptr %t394, i64 -8
  %t464 = load i32, ptr %t463
  %t465 = icmp eq i32 %t464, 1
  br i1 %t465, label %reuse.in_place.466, label %reuse.copy.467
reuse.in_place.466:
  %t458 = getelementptr ptr, ptr %t394, i32 1
  %t459 = load ptr, ptr %t458
  call void @__free_recursive(ptr %t459)
  %t461 = inttoptr i64 46 to ptr
  %t462 = getelementptr ptr, ptr %t394, i32 0
  store ptr %t461, ptr %t462
  call void @__inc_ref(ptr %t185)
  %t460 = getelementptr ptr, ptr %t394, i32 1
  store ptr %t185, ptr %t460
  br label %reuse.in_place.end.469
reuse.in_place.end.469:
  br label %reuse.join.468
reuse.copy.467:
  %t471 = call ptr @__alloc(i64 16, i32 1)
  %t472 = inttoptr i64 46 to ptr
  %t473 = getelementptr ptr, ptr %t471, i32 0
  store ptr %t472, ptr %t473
  call void @__inc_ref(ptr %t185)
  %t474 = getelementptr ptr, ptr %t471, i32 1
  store ptr %t185, ptr %t474
  call void @__free_recursive(ptr %t394)
  br label %reuse.copy.end.470
reuse.copy.end.470:
  br label %reuse.join.468
reuse.join.468:
  %t475 = phi ptr [ %t394, %reuse.in_place.end.469 ], [ %t471, %reuse.copy.end.470 ]
  %t476 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t475, ptr %t476
  call void @__free_recursive(ptr %t444)
  call void @__free_recursive(ptr %t396)
  call void @__free_recursive(ptr %t185)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.400:
  unreachable
tco.case.arm.36.479:
  %t480 = getelementptr ptr, ptr %t183, i32 1
  %t481 = load ptr, ptr %t480
  call void @__inc_ref(ptr %t481)
  %t482 = getelementptr ptr, ptr %t481, i32 0
  %t483 = load ptr, ptr %t482
  %t484 = ptrtoint ptr %t483 to i64
  switch i64 %t484, label %tco.case.default.485 [ i64 24, label %tco.case.arm.24.486 i64 25, label %tco.case.arm.25.523 ]
tco.case.arm.24.486:
  %t487 = getelementptr ptr, ptr %t481, i32 1
  %t488 = load ptr, ptr %t487
  call void @__inc_ref(ptr %t488)
  %t489 = call ptr @__alloc(i64 24, i32 2)
  %t490 = inttoptr i64 51 to ptr
  %t491 = getelementptr ptr, ptr %t489, i32 0
  store ptr %t490, ptr %t491
  %t492 = call ptr @__alloc(i64 8, i32 0)
  %t493 = inttoptr i64 29 to ptr
  %t494 = getelementptr ptr, ptr %t492, i32 0
  store ptr %t493, ptr %t494
  %t495 = getelementptr ptr, ptr %t4, i32 1
  %t496 = load ptr, ptr %t495
  call void @__free_recursive(ptr %t496)
  %t497 = getelementptr ptr, ptr %t4, i32 2
  %t498 = load ptr, ptr %t497
  call void @__free_recursive(ptr %t498)
  %t501 = inttoptr i64 35 to ptr
  %t502 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t501, ptr %t502
  call void @__inc_ref(ptr %t488)
  %t499 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t488, ptr %t499
  %t500 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t492, ptr %t500
  %t503 = getelementptr ptr, ptr %t489, i32 1
  store ptr %t4, ptr %t503
  %t509 = getelementptr i8, ptr %t481, i64 -8
  %t510 = load i32, ptr %t509
  %t511 = icmp eq i32 %t510, 1
  br i1 %t511, label %reuse.in_place.512, label %reuse.copy.513
reuse.in_place.512:
  %t504 = getelementptr ptr, ptr %t481, i32 1
  %t505 = load ptr, ptr %t504
  call void @__free_recursive(ptr %t505)
  %t507 = inttoptr i64 47 to ptr
  %t508 = getelementptr ptr, ptr %t481, i32 0
  store ptr %t507, ptr %t508
  call void @__inc_ref(ptr %t185)
  %t506 = getelementptr ptr, ptr %t481, i32 1
  store ptr %t185, ptr %t506
  br label %reuse.in_place.end.515
reuse.in_place.end.515:
  br label %reuse.join.514
reuse.copy.513:
  %t517 = call ptr @__alloc(i64 16, i32 1)
  %t518 = inttoptr i64 47 to ptr
  %t519 = getelementptr ptr, ptr %t517, i32 0
  store ptr %t518, ptr %t519
  call void @__inc_ref(ptr %t185)
  %t520 = getelementptr ptr, ptr %t517, i32 1
  store ptr %t185, ptr %t520
  call void @__free_recursive(ptr %t481)
  br label %reuse.copy.end.516
reuse.copy.end.516:
  br label %reuse.join.514
reuse.join.514:
  %t521 = phi ptr [ %t481, %reuse.in_place.end.515 ], [ %t517, %reuse.copy.end.516 ]
  %t522 = getelementptr ptr, ptr %t489, i32 2
  store ptr %t521, ptr %t522
  call void @__free_recursive(ptr %t488)
  call void @__free_recursive(ptr %t183)
  call void @__free_recursive(ptr %t185)
  store ptr %t489, ptr %t3
  br label %tco.loop.0
tco.case.arm.25.523:
  %t524 = getelementptr ptr, ptr %t481, i32 1
  %t525 = load ptr, ptr %t524
  call void @__inc_ref(ptr %t525)
  %t526 = getelementptr ptr, ptr %t4, i32 1
  %t527 = load ptr, ptr %t526
  call void @__free_recursive(ptr %t527)
  %t528 = getelementptr ptr, ptr %t4, i32 2
  %t529 = load ptr, ptr %t528
  call void @__free_recursive(ptr %t529)
  %t554 = inttoptr i64 50 to ptr
  %t555 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t554, ptr %t555
  call void @__inc_ref(ptr %t185)
  %t530 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t185, ptr %t530
  %t531 = call ptr @__alloc(i64 16, i32 1)
  %t532 = inttoptr i64 796142685 to ptr
  %t533 = getelementptr ptr, ptr %t531, i32 0
  store ptr %t532, ptr %t533
  call void @__inc_ref(ptr %t525)
  %t534 = getelementptr ptr, ptr %t531, i32 1
  store ptr %t525, ptr %t534
  %t540 = getelementptr i8, ptr %t481, i64 -8
  %t541 = load i32, ptr %t540
  %t542 = icmp eq i32 %t541, 1
  br i1 %t542, label %reuse.in_place.543, label %reuse.copy.544
reuse.in_place.543:
  %t535 = getelementptr ptr, ptr %t481, i32 1
  %t536 = load ptr, ptr %t535
  call void @__free_recursive(ptr %t536)
  %t538 = inttoptr i64 25 to ptr
  %t539 = getelementptr ptr, ptr %t481, i32 0
  store ptr %t538, ptr %t539
  %t537 = getelementptr ptr, ptr %t481, i32 1
  store ptr %t531, ptr %t537
  br label %reuse.in_place.end.546
reuse.in_place.end.546:
  br label %reuse.join.545
reuse.copy.544:
  %t548 = call ptr @__alloc(i64 16, i32 1)
  %t549 = inttoptr i64 25 to ptr
  %t550 = getelementptr ptr, ptr %t548, i32 0
  store ptr %t549, ptr %t550
  %t551 = getelementptr ptr, ptr %t548, i32 1
  store ptr %t531, ptr %t551
  call void @__free_recursive(ptr %t481)
  br label %reuse.copy.end.547
reuse.copy.end.547:
  br label %reuse.join.545
reuse.join.545:
  %t552 = phi ptr [ %t481, %reuse.in_place.end.546 ], [ %t548, %reuse.copy.end.547 ]
  %t553 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t552, ptr %t553
  call void @__free_recursive(ptr %t525)
  call void @__free_recursive(ptr %t183)
  call void @__free_recursive(ptr %t185)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.485:
  unreachable
tco.case.arm.37.556:
  %t557 = getelementptr ptr, ptr %t183, i32 1
  %t558 = load ptr, ptr %t557
  %t559 = getelementptr ptr, ptr %t183, i32 2
  %t560 = load ptr, ptr %t559
  call void @__inc_ref(ptr %t560)
  %t561 = getelementptr ptr, ptr %t560, i32 0
  %t562 = load ptr, ptr %t561
  %t563 = ptrtoint ptr %t562 to i64
  switch i64 %t563, label %tco.case.default.564 [ i64 11, label %tco.case.arm.11.565 i64 12, label %tco.case.arm.12.569 ]
tco.case.arm.11.565:
  %t567 = inttoptr i64 50 to ptr
  %t568 = getelementptr ptr, ptr %t183, i32 0
  store ptr %t567, ptr %t568
  call void @__inc_ref(ptr %t185)
  %t566 = getelementptr ptr, ptr %t183, i32 1
  store ptr %t185, ptr %t566
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t560)
  call void @__free_recursive(ptr %t185)
  store ptr %t183, ptr %t3
  br label %tco.loop.0
tco.case.arm.12.569:
  %t570 = call ptr @__alloc(i64 16, i32 1)
  %t571 = inttoptr i64 48 to ptr
  %t572 = getelementptr ptr, ptr %t570, i32 0
  store ptr %t571, ptr %t572
  call void @__inc_ref(ptr %t185)
  %t573 = getelementptr ptr, ptr %t570, i32 1
  store ptr %t185, ptr %t573
  %t574 = getelementptr ptr, ptr %t4, i32 1
  %t575 = load ptr, ptr %t574
  call void @__free_recursive(ptr %t575)
  %t576 = getelementptr ptr, ptr %t4, i32 2
  %t577 = load ptr, ptr %t576
  call void @__free_recursive(ptr %t577)
  %t587 = inttoptr i64 51 to ptr
  %t588 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t587, ptr %t588
  %t578 = getelementptr ptr, ptr %t560, i32 1
  %t579 = load ptr, ptr %t578
  call void @__inc_ref(ptr %t579)
  %t580 = getelementptr ptr, ptr %t183, i32 2
  %t581 = load ptr, ptr %t580
  call void @__free_recursive(ptr %t581)
  %t583 = inttoptr i64 31 to ptr
  %t584 = getelementptr ptr, ptr %t183, i32 0
  store ptr %t583, ptr %t584
  %t582 = getelementptr ptr, ptr %t183, i32 2
  store ptr %t579, ptr %t582
  %t585 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t183, ptr %t585
  %t586 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t570, ptr %t586
  call void @__free_recursive(ptr %t560)
  call void @__free_recursive(ptr %t185)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.564:
  unreachable
tco.case.arm.38.589:
  %t590 = getelementptr ptr, ptr %t183, i32 1
  %t591 = load ptr, ptr %t590
  call void @__inc_ref(ptr %t591)
  %t592 = call ptr @__alloc(i64 16, i32 1)
  %t593 = inttoptr i64 49 to ptr
  %t594 = getelementptr ptr, ptr %t592, i32 0
  store ptr %t593, ptr %t594
  call void @__inc_ref(ptr %t185)
  %t595 = getelementptr ptr, ptr %t592, i32 1
  store ptr %t185, ptr %t595
  %t596 = getelementptr ptr, ptr %t4, i32 1
  %t597 = load ptr, ptr %t596
  call void @__free_recursive(ptr %t597)
  %t598 = getelementptr ptr, ptr %t4, i32 2
  %t599 = load ptr, ptr %t598
  call void @__free_recursive(ptr %t599)
  %t651 = inttoptr i64 51 to ptr
  %t652 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t651, ptr %t652
  %t600 = call ptr @__alloc(i64 16, i32 1)
  %t601 = inttoptr i64 36 to ptr
  %t602 = getelementptr ptr, ptr %t600, i32 0
  store ptr %t601, ptr %t602
  %t603 = getelementptr ptr, ptr %t591, i32 0
  %t604 = load ptr, ptr %t603
  %t605 = ptrtoint ptr %t604 to i64
  switch i64 %t605, label %case.default.606 [ i64 13, label %case.arm.13.608 i64 14, label %case.arm.14.629 ]
case.arm.13.608:
  %t610 = getelementptr ptr, ptr %t183, i32 1
  %t611 = load ptr, ptr %t610
  call void @__free_recursive(ptr %t611)
  %t627 = inttoptr i64 25 to ptr
  %t628 = getelementptr ptr, ptr %t183, i32 0
  store ptr %t627, ptr %t628
  %t614 = getelementptr i8, ptr %t591, i64 -8
  %t615 = load i32, ptr %t614
  %t616 = icmp eq i32 %t615, 1
  br i1 %t616, label %reuse.in_place.617, label %reuse.copy.618
reuse.in_place.617:
  %t612 = inttoptr i64 1 to ptr
  %t613 = getelementptr ptr, ptr %t591, i32 0
  store ptr %t612, ptr %t613
  br label %reuse.in_place.end.620
reuse.in_place.end.620:
  br label %reuse.join.619
reuse.copy.618:
  %t622 = call ptr @__alloc(i64 8, i32 0)
  %t623 = inttoptr i64 1 to ptr
  %t624 = getelementptr ptr, ptr %t622, i32 0
  store ptr %t623, ptr %t624
  call void @__free_recursive(ptr %t591)
  br label %reuse.copy.end.621
reuse.copy.end.621:
  br label %reuse.join.619
reuse.join.619:
  %t625 = phi ptr [ %t591, %reuse.in_place.end.620 ], [ %t622, %reuse.copy.end.621 ]
  %t626 = getelementptr ptr, ptr %t183, i32 1
  store ptr %t625, ptr %t626
  br label %case.end.13.609
case.end.13.609:
  br label %case.join.607
case.arm.14.629:
  %t631 = call ptr @__alloc(i64 16, i32 1)
  %t632 = inttoptr i64 24 to ptr
  %t633 = getelementptr ptr, ptr %t631, i32 0
  store ptr %t632, ptr %t633
  %t634 = call ptr @__alloc(i64 16, i32 1)
  %t635 = inttoptr i64 25 to ptr
  %t636 = getelementptr ptr, ptr %t634, i32 0
  store ptr %t635, ptr %t636
  %t637 = call ptr @__alloc(i64 8, i32 0)
  %t638 = inttoptr i64 1 to ptr
  %t639 = getelementptr ptr, ptr %t637, i32 0
  store ptr %t638, ptr %t639
  %t640 = getelementptr ptr, ptr %t183, i32 1
  %t641 = load ptr, ptr %t640
  call void @__free_recursive(ptr %t641)
  %t643 = inttoptr i64 12 to ptr
  %t644 = getelementptr ptr, ptr %t183, i32 0
  store ptr %t643, ptr %t644
  %t642 = getelementptr ptr, ptr %t183, i32 1
  store ptr %t637, ptr %t642
  %t645 = getelementptr ptr, ptr %t634, i32 1
  store ptr %t183, ptr %t645
  %t646 = getelementptr ptr, ptr %t631, i32 1
  store ptr %t634, ptr %t646
  call void @__free_recursive(ptr %t591)
  br label %case.end.14.630
case.end.14.630:
  br label %case.join.607
case.default.606:
  unreachable
case.join.607:
  %t647 = phi ptr [ %t183, %case.end.13.609 ], [ %t631, %case.end.14.630 ]
  %t648 = getelementptr ptr, ptr %t600, i32 1
  store ptr %t647, ptr %t648
  %t649 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t600, ptr %t649
  %t650 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t592, ptr %t650
  call void @__free_recursive(ptr %t185)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.189:
  unreachable
tco.case.default.8:
  unreachable
tco.exit.1:
  %t653 = load ptr, ptr %t2
  ret ptr %t653
}

define i32 @main(i32 %argc, ptr %argv) {
  %argc64 = sext i32 %argc to i64
  store i64 %argc64, ptr @.cli_argc
  store ptr %argv, ptr @.cli_argv
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
