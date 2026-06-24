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
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [20 x i8]} { i32 0, i32 0, i32 0, i32 20, i32 20, [20 x i8] c"more-done-tuple-bool" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"done" }

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
  %t21 = inttoptr i64 53 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = call ptr @__alloc(i64 24, i32 2)
  %t24 = inttoptr i64 32 to ptr
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
  %t32 = inttoptr i64 42 to ptr
  %t33 = getelementptr ptr, ptr %t31, i32 0
  store ptr %t32, ptr %t33
  %t34 = getelementptr ptr, ptr %t20, i32 2
  store ptr %t31, ptr %t34
  %t35 = call ptr @v_$scc$$apply$$scc$$apply1__$df$$lam$14$7__$df$$lam$9$3__$df$$map$Tw$0__$df$$map$Tw$1__$df$$rowmono$0$andThenIO$6__$map$Tuple2__run2__$cps$$scc$$apply1__$df$$lam$14$7__$df$$lam$9$3__$df$$map$Tw$0__$df$$map$Tw$1__$df$$rowmono$0$andThenIO$6__$map$Tuple2__run2(ptr %t20)
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
  %t1 = inttoptr i64 53 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 16, i32 1)
  %t4 = inttoptr i64 37 to ptr
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
  %t16 = inttoptr i64 42 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t15, ptr %t18
  %t19 = call ptr @v_$scc$$apply$$scc$$apply1__$df$$lam$14$7__$df$$lam$9$3__$df$$map$Tw$0__$df$$map$Tw$1__$df$$rowmono$0$andThenIO$6__$map$Tuple2__run2__$cps$$scc$$apply1__$df$$lam$14$7__$df$$lam$9$3__$df$$map$Tw$0__$df$$map$Tw$1__$df$$rowmono$0$andThenIO$6__$map$Tuple2__run2(ptr %t0)
  %t20 = call ptr @__alloc(i64 8, i32 0)
  %t21 = inttoptr i64 40 to ptr
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
  %t60 = inttoptr i64 41 to ptr
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
  %t71 = inttoptr i64 41 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 40, label %tco.case.arm.40.11 i64 41, label %tco.case.arm.41.12 ]
tco.case.arm.40.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.41.12:
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

define internal ptr @v_$scc$$apply$$scc$$apply1__$df$$lam$14$7__$df$$lam$9$3__$df$$map$Tw$0__$df$$map$Tw$1__$df$$rowmono$0$andThenIO$6__$map$Tuple2__run2__$cps$$scc$$apply1__$df$$lam$14$7__$df$$lam$9$3__$df$$map$Tw$0__$df$$map$Tw$1__$df$$rowmono$0$andThenIO$6__$map$Tuple2__run2(ptr %v_$args$1) {
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
  switch i64 %t7, label %tco.case.default.8 [ i64 52, label %tco.case.arm.52.9 i64 53, label %tco.case.arm.53.197 ]
tco.case.arm.52.9:
  %t10 = getelementptr ptr, ptr %t4, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  %t12 = getelementptr ptr, ptr %t4, i32 2
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t11, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %tco.case.default.17 [ i64 42, label %tco.case.arm.42.18 i64 43, label %tco.case.arm.43.19 i64 44, label %tco.case.arm.44.34 i64 45, label %tco.case.arm.45.49 i64 46, label %tco.case.arm.46.64 i64 47, label %tco.case.arm.47.79 i64 48, label %tco.case.arm.48.97 i64 50, label %tco.case.arm.50.112 i64 49, label %tco.case.arm.49.127 i64 51, label %tco.case.arm.51.152 ]
tco.case.arm.42.18:
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %t4)
  store ptr %t13, ptr %t2
  br label %tco.exit.1
tco.case.arm.43.19:
  %t20 = call ptr @__alloc(i64 16, i32 1)
  %t21 = inttoptr i64 37 to ptr
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
  %t32 = inttoptr i64 53 to ptr
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
tco.case.arm.44.34:
  %t35 = getelementptr ptr, ptr %t11, i32 1
  %t36 = load ptr, ptr %t35
  call void @__inc_ref(ptr %t36)
  call void @__inc_ref(ptr %t13)
  %t37 = call ptr @__alloc(i64 8, i32 0)
  %t38 = inttoptr i64 40 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = call ptr @v_$cps$$df$handleErrorIO$2(ptr %t13, ptr %t37)
  %t41 = getelementptr ptr, ptr %t4, i32 1
  %t42 = load ptr, ptr %t41
  call void @__free_recursive(ptr %t42)
  %t43 = getelementptr ptr, ptr %t4, i32 2
  %t44 = load ptr, ptr %t43
  call void @__free_recursive(ptr %t44)
  %t47 = inttoptr i64 52 to ptr
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
tco.case.arm.45.49:
  %t50 = getelementptr ptr, ptr %t11, i32 1
  %t51 = load ptr, ptr %t50
  call void @__inc_ref(ptr %t51)
  %t52 = call ptr @__alloc(i64 16, i32 1)
  %t53 = inttoptr i64 24 to ptr
  %t54 = getelementptr ptr, ptr %t52, i32 0
  store ptr %t53, ptr %t54
  call void @__inc_ref(ptr %t13)
  %t55 = getelementptr ptr, ptr %t52, i32 1
  store ptr %t13, ptr %t55
  %t56 = getelementptr ptr, ptr %t4, i32 1
  %t57 = load ptr, ptr %t56
  call void @__free_recursive(ptr %t57)
  %t58 = getelementptr ptr, ptr %t4, i32 2
  %t59 = load ptr, ptr %t58
  call void @__free_recursive(ptr %t59)
  %t62 = inttoptr i64 52 to ptr
  %t63 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t62, ptr %t63
  %t60 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t51, ptr %t60
  %t61 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t52, ptr %t61
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.46.64:
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
  %t77 = inttoptr i64 52 to ptr
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
tco.case.arm.47.79:
  %t80 = call ptr @__alloc(i64 24, i32 2)
  %t81 = inttoptr i64 52 to ptr
  %t82 = getelementptr ptr, ptr %t80, i32 0
  store ptr %t81, ptr %t82
  %t83 = getelementptr ptr, ptr %t11, i32 1
  %t84 = load ptr, ptr %t83
  call void @__inc_ref(ptr %t84)
  %t85 = getelementptr ptr, ptr %t80, i32 1
  store ptr %t84, ptr %t85
  %t86 = getelementptr ptr, ptr %t11, i32 2
  %t87 = load ptr, ptr %t86
  call void @__inc_ref(ptr %t87)
  %t88 = getelementptr ptr, ptr %t4, i32 1
  %t89 = load ptr, ptr %t88
  call void @__free_recursive(ptr %t89)
  %t90 = getelementptr ptr, ptr %t4, i32 2
  %t91 = load ptr, ptr %t90
  call void @__free_recursive(ptr %t91)
  %t94 = inttoptr i64 25 to ptr
  %t95 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t94, ptr %t95
  call void @__inc_ref(ptr %t13)
  %t92 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t13, ptr %t92
  %t93 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t87, ptr %t93
  %t96 = getelementptr ptr, ptr %t80, i32 2
  store ptr %t4, ptr %t96
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t80, ptr %t3
  br label %tco.loop.0
tco.case.arm.48.97:
  %t98 = call ptr @__alloc(i64 24, i32 2)
  %t99 = inttoptr i64 52 to ptr
  %t100 = getelementptr ptr, ptr %t98, i32 0
  store ptr %t99, ptr %t100
  %t101 = getelementptr ptr, ptr %t11, i32 1
  %t102 = load ptr, ptr %t101
  call void @__inc_ref(ptr %t102)
  %t103 = getelementptr ptr, ptr %t98, i32 1
  store ptr %t102, ptr %t103
  %t104 = getelementptr ptr, ptr %t11, i32 2
  %t105 = load ptr, ptr %t104
  call void @__inc_ref(ptr %t105)
  %t106 = getelementptr ptr, ptr %t4, i32 1
  %t107 = load ptr, ptr %t106
  call void @__free_recursive(ptr %t107)
  %t109 = inttoptr i64 7 to ptr
  %t110 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t109, ptr %t110
  %t108 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t105, ptr %t108
  %t111 = getelementptr ptr, ptr %t98, i32 2
  store ptr %t4, ptr %t111
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t98, ptr %t3
  br label %tco.loop.0
tco.case.arm.50.112:
  %t113 = call ptr @__alloc(i64 24, i32 2)
  %t114 = inttoptr i64 52 to ptr
  %t115 = getelementptr ptr, ptr %t113, i32 0
  store ptr %t114, ptr %t115
  %t116 = getelementptr ptr, ptr %t11, i32 1
  %t117 = load ptr, ptr %t116
  call void @__inc_ref(ptr %t117)
  %t118 = getelementptr ptr, ptr %t113, i32 1
  store ptr %t117, ptr %t118
  %t119 = getelementptr ptr, ptr %t11, i32 2
  %t120 = load ptr, ptr %t119
  call void @__inc_ref(ptr %t120)
  %t121 = getelementptr ptr, ptr %t4, i32 1
  %t122 = load ptr, ptr %t121
  call void @__free_recursive(ptr %t122)
  %t124 = inttoptr i64 15 to ptr
  %t125 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t124, ptr %t125
  %t123 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t120, ptr %t123
  %t126 = getelementptr ptr, ptr %t113, i32 2
  store ptr %t4, ptr %t126
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t113, ptr %t3
  br label %tco.loop.0
tco.case.arm.49.127:
  %t128 = call ptr @__alloc(i64 24, i32 2)
  %t129 = inttoptr i64 53 to ptr
  %t130 = getelementptr ptr, ptr %t128, i32 0
  store ptr %t129, ptr %t130
  %t131 = getelementptr ptr, ptr %t11, i32 2
  %t132 = load ptr, ptr %t131
  call void @__inc_ref(ptr %t132)
  %t133 = getelementptr ptr, ptr %t11, i32 3
  %t134 = load ptr, ptr %t133
  call void @__inc_ref(ptr %t134)
  %t135 = getelementptr ptr, ptr %t4, i32 1
  %t136 = load ptr, ptr %t135
  call void @__free_recursive(ptr %t136)
  %t137 = getelementptr ptr, ptr %t4, i32 2
  %t138 = load ptr, ptr %t137
  call void @__free_recursive(ptr %t138)
  %t141 = inttoptr i64 32 to ptr
  %t142 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t141, ptr %t142
  %t139 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t132, ptr %t139
  %t140 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t134, ptr %t140
  %t143 = getelementptr ptr, ptr %t128, i32 1
  store ptr %t4, ptr %t143
  %t144 = call ptr @__alloc(i64 24, i32 2)
  %t145 = inttoptr i64 50 to ptr
  %t146 = getelementptr ptr, ptr %t144, i32 0
  store ptr %t145, ptr %t146
  %t147 = getelementptr ptr, ptr %t11, i32 1
  %t148 = load ptr, ptr %t147
  call void @__inc_ref(ptr %t148)
  %t149 = getelementptr ptr, ptr %t144, i32 1
  store ptr %t148, ptr %t149
  call void @__inc_ref(ptr %t13)
  %t150 = getelementptr ptr, ptr %t144, i32 2
  store ptr %t13, ptr %t150
  %t151 = getelementptr ptr, ptr %t128, i32 2
  store ptr %t144, ptr %t151
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t128, ptr %t3
  br label %tco.loop.0
tco.case.arm.51.152:
  %t153 = call ptr @__alloc(i64 24, i32 2)
  %t154 = inttoptr i64 52 to ptr
  %t155 = getelementptr ptr, ptr %t153, i32 0
  store ptr %t154, ptr %t155
  %t156 = getelementptr ptr, ptr %t11, i32 1
  %t157 = load ptr, ptr %t156
  call void @__inc_ref(ptr %t157)
  %t158 = getelementptr ptr, ptr %t153, i32 1
  store ptr %t157, ptr %t158
  %t159 = getelementptr ptr, ptr %t13, i32 0
  %t160 = load ptr, ptr %t159
  %t161 = ptrtoint ptr %t160 to i64
  switch i64 %t161, label %case.default.162 [ i64 24, label %case.arm.24.164 i64 25, label %case.arm.25.178 ]
case.arm.24.164:
  %t166 = getelementptr ptr, ptr %t13, i32 1
  %t167 = load ptr, ptr %t166
  call void @__inc_ref(ptr %t167)
  %t168 = getelementptr ptr, ptr %t167, i32 0
  %t169 = load ptr, ptr %t168
  %t170 = ptrtoint ptr %t169 to i64
  switch i64 %t170, label %case.default.171 [ i64 24, label %case.arm.24.173 i64 25, label %case.arm.25.175 ]
case.arm.24.173:
  br label %case.end.24.174
case.end.24.174:
  br label %case.join.172
case.arm.25.175:
  br label %case.end.25.176
case.end.25.176:
  br label %case.join.172
case.default.171:
  unreachable
case.join.172:
  %t177 = phi ptr [ getelementptr inbounds (i8, ptr @.str.2, i64 12), %case.end.24.174 ], [ getelementptr inbounds (i8, ptr @.str.3, i64 12), %case.end.25.176 ]
  call void @__free_recursive(ptr %t167)
  br label %case.end.24.165
case.end.24.165:
  br label %case.join.163
case.arm.25.178:
  br label %case.end.25.179
case.end.25.179:
  br label %case.join.163
case.default.162:
  unreachable
case.join.163:
  %t180 = phi ptr [ %t177, %case.end.24.165 ], [ getelementptr inbounds (i8, ptr @.str.4, i64 12), %case.end.25.179 ]
  %t181 = call ptr @__alloc(i64 16, i32 1)
  %t182 = inttoptr i64 5 to ptr
  %t183 = getelementptr ptr, ptr %t181, i32 0
  store ptr %t182, ptr %t183
  %t184 = call ptr @__alloc(i64 8, i32 0)
  %t185 = inttoptr i64 0 to ptr
  %t186 = getelementptr ptr, ptr %t184, i32 0
  store ptr %t185, ptr %t186
  %t187 = getelementptr ptr, ptr %t181, i32 1
  store ptr %t184, ptr %t187
  %t188 = getelementptr ptr, ptr %t4, i32 1
  %t189 = load ptr, ptr %t188
  call void @__free_recursive(ptr %t189)
  %t190 = getelementptr ptr, ptr %t4, i32 2
  %t191 = load ptr, ptr %t190
  call void @__free_recursive(ptr %t191)
  %t194 = inttoptr i64 7 to ptr
  %t195 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t194, ptr %t195
  %t192 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t180, ptr %t192
  %t193 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t181, ptr %t193
  %t196 = getelementptr ptr, ptr %t153, i32 2
  store ptr %t4, ptr %t196
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t153, ptr %t3
  br label %tco.loop.0
tco.case.default.17:
  unreachable
tco.case.arm.53.197:
  %t198 = getelementptr ptr, ptr %t4, i32 1
  %t199 = load ptr, ptr %t198
  call void @__inc_ref(ptr %t199)
  %t200 = getelementptr ptr, ptr %t4, i32 2
  %t201 = load ptr, ptr %t200
  call void @__inc_ref(ptr %t201)
  %t202 = getelementptr ptr, ptr %t199, i32 0
  %t203 = load ptr, ptr %t202
  %t204 = ptrtoint ptr %t203 to i64
  switch i64 %t204, label %tco.case.default.205 [ i64 32, label %tco.case.arm.32.206 i64 33, label %tco.case.arm.33.310 i64 34, label %tco.case.arm.34.329 i64 35, label %tco.case.arm.35.348 i64 36, label %tco.case.arm.36.432 i64 37, label %tco.case.arm.37.534 i64 38, label %tco.case.arm.38.606 i64 39, label %tco.case.arm.39.658 ]
tco.case.arm.32.206:
  %t207 = getelementptr ptr, ptr %t199, i32 1
  %t208 = load ptr, ptr %t207
  call void @__inc_ref(ptr %t208)
  %t209 = getelementptr ptr, ptr %t199, i32 2
  %t210 = load ptr, ptr %t209
  call void @__inc_ref(ptr %t210)
  %t211 = getelementptr ptr, ptr %t208, i32 0
  %t212 = load ptr, ptr %t211
  %t213 = ptrtoint ptr %t212 to i64
  switch i64 %t213, label %tco.case.default.214 [ i64 26, label %tco.case.arm.26.215 i64 27, label %tco.case.arm.27.228 i64 28, label %tco.case.arm.28.241 i64 29, label %tco.case.arm.29.272 i64 30, label %tco.case.arm.30.285 i64 31, label %tco.case.arm.31.304 ]
tco.case.arm.26.215:
  %t216 = getelementptr ptr, ptr %t4, i32 1
  %t217 = load ptr, ptr %t216
  call void @__free_recursive(ptr %t217)
  %t226 = inttoptr i64 53 to ptr
  %t227 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t226, ptr %t227
  %t218 = getelementptr ptr, ptr %t208, i32 1
  %t219 = load ptr, ptr %t218
  call void @__inc_ref(ptr %t219)
  %t220 = getelementptr ptr, ptr %t199, i32 1
  %t221 = load ptr, ptr %t220
  call void @__free_recursive(ptr %t221)
  %t223 = inttoptr i64 33 to ptr
  %t224 = getelementptr ptr, ptr %t199, i32 0
  store ptr %t223, ptr %t224
  %t222 = getelementptr ptr, ptr %t199, i32 1
  store ptr %t219, ptr %t222
  %t225 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t199, ptr %t225
  call void @__free_recursive(ptr %t210)
  call void @__free_recursive(ptr %t208)
  call void @__free_recursive(ptr %t201)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.27.228:
  %t229 = getelementptr ptr, ptr %t4, i32 1
  %t230 = load ptr, ptr %t229
  call void @__free_recursive(ptr %t230)
  %t239 = inttoptr i64 53 to ptr
  %t240 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t239, ptr %t240
  %t231 = getelementptr ptr, ptr %t208, i32 1
  %t232 = load ptr, ptr %t231
  call void @__inc_ref(ptr %t232)
  %t233 = getelementptr ptr, ptr %t199, i32 1
  %t234 = load ptr, ptr %t233
  call void @__free_recursive(ptr %t234)
  %t236 = inttoptr i64 34 to ptr
  %t237 = getelementptr ptr, ptr %t199, i32 0
  store ptr %t236, ptr %t237
  %t235 = getelementptr ptr, ptr %t199, i32 1
  store ptr %t232, ptr %t235
  %t238 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t199, ptr %t238
  call void @__free_recursive(ptr %t210)
  call void @__free_recursive(ptr %t208)
  call void @__free_recursive(ptr %t201)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.28.241:
  %t242 = getelementptr ptr, ptr %t210, i32 0
  %t243 = load ptr, ptr %t242
  %t244 = ptrtoint ptr %t243 to i64
  switch i64 %t244, label %case.default.245 [ i64 3, label %case.arm.3.247 i64 4, label %case.arm.4.255 ]
case.arm.3.247:
  %t249 = call ptr @__alloc(i64 16, i32 1)
  %t250 = inttoptr i64 6 to ptr
  %t251 = getelementptr ptr, ptr %t249, i32 0
  store ptr %t250, ptr %t251
  %t252 = getelementptr ptr, ptr %t210, i32 1
  %t253 = load ptr, ptr %t252
  call void @__inc_ref(ptr %t253)
  %t254 = getelementptr ptr, ptr %t249, i32 1
  store ptr %t253, ptr %t254
  br label %case.end.3.248
case.end.3.248:
  br label %case.join.246
case.arm.4.255:
  %t257 = call ptr @__alloc(i64 16, i32 1)
  %t258 = inttoptr i64 5 to ptr
  %t259 = getelementptr ptr, ptr %t257, i32 0
  store ptr %t258, ptr %t259
  %t260 = getelementptr ptr, ptr %t210, i32 1
  %t261 = load ptr, ptr %t260
  call void @__inc_ref(ptr %t261)
  %t262 = getelementptr ptr, ptr %t257, i32 1
  store ptr %t261, ptr %t262
  br label %case.end.4.256
case.end.4.256:
  br label %case.join.246
case.default.245:
  unreachable
case.join.246:
  %t263 = phi ptr [ %t249, %case.end.3.248 ], [ %t257, %case.end.4.256 ]
  %t264 = getelementptr ptr, ptr %t199, i32 1
  %t265 = load ptr, ptr %t264
  call void @__free_recursive(ptr %t265)
  %t266 = getelementptr ptr, ptr %t199, i32 2
  %t267 = load ptr, ptr %t266
  call void @__free_recursive(ptr %t267)
  %t270 = inttoptr i64 52 to ptr
  %t271 = getelementptr ptr, ptr %t199, i32 0
  store ptr %t270, ptr %t271
  call void @__inc_ref(ptr %t201)
  %t268 = getelementptr ptr, ptr %t199, i32 1
  store ptr %t201, ptr %t268
  %t269 = getelementptr ptr, ptr %t199, i32 2
  store ptr %t263, ptr %t269
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t210)
  call void @__free_recursive(ptr %t208)
  call void @__free_recursive(ptr %t201)
  store ptr %t199, ptr %t3
  br label %tco.loop.0
tco.case.arm.29.272:
  %t273 = call ptr @__alloc(i64 16, i32 1)
  %t274 = inttoptr i64 796142685 to ptr
  %t275 = getelementptr ptr, ptr %t273, i32 0
  store ptr %t274, ptr %t275
  call void @__inc_ref(ptr %t210)
  %t276 = getelementptr ptr, ptr %t273, i32 1
  store ptr %t210, ptr %t276
  %t277 = getelementptr ptr, ptr %t199, i32 1
  %t278 = load ptr, ptr %t277
  call void @__free_recursive(ptr %t278)
  %t279 = getelementptr ptr, ptr %t199, i32 2
  %t280 = load ptr, ptr %t279
  call void @__free_recursive(ptr %t280)
  %t283 = inttoptr i64 52 to ptr
  %t284 = getelementptr ptr, ptr %t199, i32 0
  store ptr %t283, ptr %t284
  call void @__inc_ref(ptr %t201)
  %t281 = getelementptr ptr, ptr %t199, i32 1
  store ptr %t201, ptr %t281
  %t282 = getelementptr ptr, ptr %t199, i32 2
  store ptr %t273, ptr %t282
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t210)
  call void @__free_recursive(ptr %t208)
  call void @__free_recursive(ptr %t201)
  store ptr %t199, ptr %t3
  br label %tco.loop.0
tco.case.arm.30.285:
  %t286 = call ptr @__alloc(i64 32, i32 3)
  %t287 = inttoptr i64 38 to ptr
  %t288 = getelementptr ptr, ptr %t286, i32 0
  store ptr %t287, ptr %t288
  %t289 = getelementptr ptr, ptr %t208, i32 1
  %t290 = load ptr, ptr %t289
  call void @__inc_ref(ptr %t290)
  %t291 = getelementptr ptr, ptr %t286, i32 1
  store ptr %t290, ptr %t291
  %t292 = getelementptr ptr, ptr %t208, i32 2
  %t293 = load ptr, ptr %t292
  call void @__inc_ref(ptr %t293)
  %t294 = getelementptr ptr, ptr %t286, i32 2
  store ptr %t293, ptr %t294
  call void @__inc_ref(ptr %t210)
  %t295 = getelementptr ptr, ptr %t286, i32 3
  store ptr %t210, ptr %t295
  %t296 = getelementptr ptr, ptr %t199, i32 1
  %t297 = load ptr, ptr %t296
  call void @__free_recursive(ptr %t297)
  %t298 = getelementptr ptr, ptr %t199, i32 2
  %t299 = load ptr, ptr %t298
  call void @__free_recursive(ptr %t299)
  %t302 = inttoptr i64 53 to ptr
  %t303 = getelementptr ptr, ptr %t199, i32 0
  store ptr %t302, ptr %t303
  %t300 = getelementptr ptr, ptr %t199, i32 1
  store ptr %t286, ptr %t300
  call void @__inc_ref(ptr %t201)
  %t301 = getelementptr ptr, ptr %t199, i32 2
  store ptr %t201, ptr %t301
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t210)
  call void @__free_recursive(ptr %t208)
  call void @__free_recursive(ptr %t201)
  store ptr %t199, ptr %t3
  br label %tco.loop.0
tco.case.arm.31.304:
  %t305 = getelementptr ptr, ptr %t199, i32 1
  %t306 = load ptr, ptr %t305
  call void @__free_recursive(ptr %t306)
  %t308 = inttoptr i64 52 to ptr
  %t309 = getelementptr ptr, ptr %t199, i32 0
  store ptr %t308, ptr %t309
  call void @__inc_ref(ptr %t201)
  %t307 = getelementptr ptr, ptr %t199, i32 1
  store ptr %t201, ptr %t307
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t210)
  call void @__free_recursive(ptr %t208)
  call void @__free_recursive(ptr %t201)
  store ptr %t199, ptr %t3
  br label %tco.loop.0
tco.case.default.214:
  unreachable
tco.case.arm.33.310:
  %t311 = getelementptr ptr, ptr %t199, i32 1
  %t312 = load ptr, ptr %t311
  %t313 = getelementptr ptr, ptr %t199, i32 2
  %t314 = load ptr, ptr %t313
  %t315 = call ptr @__alloc(i64 16, i32 1)
  %t316 = inttoptr i64 43 to ptr
  %t317 = getelementptr ptr, ptr %t315, i32 0
  store ptr %t316, ptr %t317
  call void @__inc_ref(ptr %t201)
  %t318 = getelementptr ptr, ptr %t315, i32 1
  store ptr %t201, ptr %t318
  %t319 = getelementptr ptr, ptr %t4, i32 1
  %t320 = load ptr, ptr %t319
  call void @__free_recursive(ptr %t320)
  %t321 = getelementptr ptr, ptr %t4, i32 2
  %t322 = load ptr, ptr %t321
  call void @__free_recursive(ptr %t322)
  %t327 = inttoptr i64 53 to ptr
  %t328 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t327, ptr %t328
  %t323 = inttoptr i64 32 to ptr
  %t324 = getelementptr ptr, ptr %t199, i32 0
  store ptr %t323, ptr %t324
  %t325 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t199, ptr %t325
  %t326 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t315, ptr %t326
  call void @__free_recursive(ptr %t201)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.34.329:
  %t330 = getelementptr ptr, ptr %t199, i32 1
  %t331 = load ptr, ptr %t330
  %t332 = getelementptr ptr, ptr %t199, i32 2
  %t333 = load ptr, ptr %t332
  %t334 = call ptr @__alloc(i64 16, i32 1)
  %t335 = inttoptr i64 44 to ptr
  %t336 = getelementptr ptr, ptr %t334, i32 0
  store ptr %t335, ptr %t336
  call void @__inc_ref(ptr %t201)
  %t337 = getelementptr ptr, ptr %t334, i32 1
  store ptr %t201, ptr %t337
  %t338 = getelementptr ptr, ptr %t4, i32 1
  %t339 = load ptr, ptr %t338
  call void @__free_recursive(ptr %t339)
  %t340 = getelementptr ptr, ptr %t4, i32 2
  %t341 = load ptr, ptr %t340
  call void @__free_recursive(ptr %t341)
  %t346 = inttoptr i64 53 to ptr
  %t347 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t346, ptr %t347
  %t342 = inttoptr i64 32 to ptr
  %t343 = getelementptr ptr, ptr %t199, i32 0
  store ptr %t342, ptr %t343
  %t344 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t199, ptr %t344
  %t345 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t334, ptr %t345
  call void @__free_recursive(ptr %t201)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.35.348:
  %t349 = getelementptr ptr, ptr %t199, i32 1
  %t350 = load ptr, ptr %t349
  call void @__inc_ref(ptr %t350)
  %t351 = getelementptr ptr, ptr %t350, i32 0
  %t352 = load ptr, ptr %t351
  %t353 = ptrtoint ptr %t352 to i64
  switch i64 %t353, label %tco.case.default.354 [ i64 24, label %tco.case.arm.24.355 i64 25, label %tco.case.arm.25.396 ]
tco.case.arm.24.355:
  %t356 = getelementptr ptr, ptr %t350, i32 1
  %t357 = load ptr, ptr %t356
  call void @__inc_ref(ptr %t357)
  %t358 = call ptr @__alloc(i64 32, i32 3)
  %t359 = inttoptr i64 36 to ptr
  %t360 = getelementptr ptr, ptr %t358, i32 0
  store ptr %t359, ptr %t360
  call void @__inc_ref(ptr %t357)
  %t361 = getelementptr ptr, ptr %t358, i32 1
  store ptr %t357, ptr %t361
  %t362 = call ptr @__alloc(i64 8, i32 0)
  %t363 = inttoptr i64 29 to ptr
  %t364 = getelementptr ptr, ptr %t362, i32 0
  store ptr %t363, ptr %t364
  %t365 = getelementptr ptr, ptr %t358, i32 2
  store ptr %t362, ptr %t365
  %t366 = call ptr @__alloc(i64 8, i32 0)
  %t367 = inttoptr i64 31 to ptr
  %t368 = getelementptr ptr, ptr %t366, i32 0
  store ptr %t367, ptr %t368
  %t369 = getelementptr ptr, ptr %t358, i32 3
  store ptr %t366, ptr %t369
  %t370 = getelementptr ptr, ptr %t4, i32 1
  %t371 = load ptr, ptr %t370
  call void @__free_recursive(ptr %t371)
  %t372 = getelementptr ptr, ptr %t4, i32 2
  %t373 = load ptr, ptr %t372
  call void @__free_recursive(ptr %t373)
  %t394 = inttoptr i64 53 to ptr
  %t395 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t394, ptr %t395
  %t374 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t358, ptr %t374
  %t380 = getelementptr i8, ptr %t350, i64 -8
  %t381 = load i32, ptr %t380
  %t382 = icmp eq i32 %t381, 1
  br i1 %t382, label %reuse.in_place.383, label %reuse.copy.384
reuse.in_place.383:
  %t375 = getelementptr ptr, ptr %t350, i32 1
  %t376 = load ptr, ptr %t375
  call void @__free_recursive(ptr %t376)
  %t378 = inttoptr i64 45 to ptr
  %t379 = getelementptr ptr, ptr %t350, i32 0
  store ptr %t378, ptr %t379
  call void @__inc_ref(ptr %t201)
  %t377 = getelementptr ptr, ptr %t350, i32 1
  store ptr %t201, ptr %t377
  br label %reuse.in_place.end.386
reuse.in_place.end.386:
  br label %reuse.join.385
reuse.copy.384:
  %t388 = call ptr @__alloc(i64 16, i32 1)
  %t389 = inttoptr i64 45 to ptr
  %t390 = getelementptr ptr, ptr %t388, i32 0
  store ptr %t389, ptr %t390
  call void @__inc_ref(ptr %t201)
  %t391 = getelementptr ptr, ptr %t388, i32 1
  store ptr %t201, ptr %t391
  call void @__free_recursive(ptr %t350)
  br label %reuse.copy.end.387
reuse.copy.end.387:
  br label %reuse.join.385
reuse.join.385:
  %t392 = phi ptr [ %t350, %reuse.in_place.end.386 ], [ %t388, %reuse.copy.end.387 ]
  %t393 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t392, ptr %t393
  call void @__free_recursive(ptr %t357)
  call void @__free_recursive(ptr %t199)
  call void @__free_recursive(ptr %t201)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.25.396:
  %t397 = getelementptr ptr, ptr %t350, i32 1
  %t398 = load ptr, ptr %t397
  call void @__inc_ref(ptr %t398)
  %t399 = getelementptr ptr, ptr %t350, i32 2
  %t400 = load ptr, ptr %t399
  %t401 = getelementptr ptr, ptr %t4, i32 1
  %t402 = load ptr, ptr %t401
  call void @__free_recursive(ptr %t402)
  %t403 = getelementptr ptr, ptr %t4, i32 2
  %t404 = load ptr, ptr %t403
  call void @__free_recursive(ptr %t404)
  %t430 = inttoptr i64 52 to ptr
  %t431 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t430, ptr %t431
  call void @__inc_ref(ptr %t201)
  %t405 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t201, ptr %t405
  %t406 = call ptr @__alloc(i64 16, i32 1)
  %t407 = inttoptr i64 796142685 to ptr
  %t408 = getelementptr ptr, ptr %t406, i32 0
  store ptr %t407, ptr %t408
  call void @__inc_ref(ptr %t398)
  %t409 = getelementptr ptr, ptr %t406, i32 1
  store ptr %t398, ptr %t409
  %t415 = getelementptr i8, ptr %t350, i64 -8
  %t416 = load i32, ptr %t415
  %t417 = icmp eq i32 %t416, 1
  br i1 %t417, label %reuse.in_place.418, label %reuse.copy.419
reuse.in_place.418:
  %t410 = getelementptr ptr, ptr %t350, i32 1
  %t411 = load ptr, ptr %t410
  call void @__free_recursive(ptr %t411)
  %t413 = inttoptr i64 25 to ptr
  %t414 = getelementptr ptr, ptr %t350, i32 0
  store ptr %t413, ptr %t414
  %t412 = getelementptr ptr, ptr %t350, i32 1
  store ptr %t406, ptr %t412
  br label %reuse.in_place.end.421
reuse.in_place.end.421:
  br label %reuse.join.420
reuse.copy.419:
  %t423 = call ptr @__alloc(i64 24, i32 2)
  %t424 = inttoptr i64 25 to ptr
  %t425 = getelementptr ptr, ptr %t423, i32 0
  store ptr %t424, ptr %t425
  %t426 = getelementptr ptr, ptr %t423, i32 1
  store ptr %t406, ptr %t426
  call void @__inc_ref(ptr %t400)
  %t427 = getelementptr ptr, ptr %t423, i32 2
  store ptr %t400, ptr %t427
  call void @__free_recursive(ptr %t350)
  br label %reuse.copy.end.422
reuse.copy.end.422:
  br label %reuse.join.420
reuse.join.420:
  %t428 = phi ptr [ %t350, %reuse.in_place.end.421 ], [ %t423, %reuse.copy.end.422 ]
  %t429 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t428, ptr %t429
  call void @__free_recursive(ptr %t398)
  call void @__free_recursive(ptr %t199)
  call void @__free_recursive(ptr %t201)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.354:
  unreachable
tco.case.arm.36.432:
  %t433 = getelementptr ptr, ptr %t199, i32 1
  %t434 = load ptr, ptr %t433
  call void @__inc_ref(ptr %t434)
  %t435 = getelementptr ptr, ptr %t199, i32 2
  %t436 = load ptr, ptr %t435
  call void @__inc_ref(ptr %t436)
  %t437 = getelementptr ptr, ptr %t199, i32 3
  %t438 = load ptr, ptr %t437
  call void @__inc_ref(ptr %t438)
  %t439 = getelementptr ptr, ptr %t434, i32 0
  %t440 = load ptr, ptr %t439
  %t441 = ptrtoint ptr %t440 to i64
  switch i64 %t441, label %tco.case.default.442 [ i64 24, label %tco.case.arm.24.443 i64 25, label %tco.case.arm.25.491 ]
tco.case.arm.24.443:
  %t444 = getelementptr ptr, ptr %t434, i32 1
  %t445 = load ptr, ptr %t444
  call void @__inc_ref(ptr %t445)
  %t446 = getelementptr ptr, ptr %t4, i32 1
  %t447 = load ptr, ptr %t446
  call void @__free_recursive(ptr %t447)
  %t448 = getelementptr ptr, ptr %t4, i32 2
  %t449 = load ptr, ptr %t448
  call void @__free_recursive(ptr %t449)
  %t489 = inttoptr i64 53 to ptr
  %t490 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t489, ptr %t490
  %t450 = call ptr @__alloc(i64 24, i32 2)
  %t451 = inttoptr i64 30 to ptr
  %t452 = getelementptr ptr, ptr %t450, i32 0
  store ptr %t451, ptr %t452
  call void @__inc_ref(ptr %t436)
  %t453 = getelementptr ptr, ptr %t450, i32 1
  store ptr %t436, ptr %t453
  call void @__inc_ref(ptr %t438)
  %t454 = getelementptr ptr, ptr %t450, i32 2
  store ptr %t438, ptr %t454
  %t455 = call ptr @__alloc(i64 8, i32 0)
  %t456 = inttoptr i64 31 to ptr
  %t457 = getelementptr ptr, ptr %t455, i32 0
  store ptr %t456, ptr %t457
  %t458 = getelementptr ptr, ptr %t199, i32 1
  %t459 = load ptr, ptr %t458
  call void @__free_recursive(ptr %t459)
  %t460 = getelementptr ptr, ptr %t199, i32 2
  %t461 = load ptr, ptr %t460
  call void @__free_recursive(ptr %t461)
  %t462 = getelementptr ptr, ptr %t199, i32 3
  %t463 = load ptr, ptr %t462
  call void @__free_recursive(ptr %t463)
  %t467 = inttoptr i64 36 to ptr
  %t468 = getelementptr ptr, ptr %t199, i32 0
  store ptr %t467, ptr %t468
  call void @__inc_ref(ptr %t445)
  %t464 = getelementptr ptr, ptr %t199, i32 1
  store ptr %t445, ptr %t464
  %t465 = getelementptr ptr, ptr %t199, i32 2
  store ptr %t450, ptr %t465
  %t466 = getelementptr ptr, ptr %t199, i32 3
  store ptr %t455, ptr %t466
  %t469 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t199, ptr %t469
  %t475 = getelementptr i8, ptr %t434, i64 -8
  %t476 = load i32, ptr %t475
  %t477 = icmp eq i32 %t476, 1
  br i1 %t477, label %reuse.in_place.478, label %reuse.copy.479
reuse.in_place.478:
  %t470 = getelementptr ptr, ptr %t434, i32 1
  %t471 = load ptr, ptr %t470
  call void @__free_recursive(ptr %t471)
  %t473 = inttoptr i64 46 to ptr
  %t474 = getelementptr ptr, ptr %t434, i32 0
  store ptr %t473, ptr %t474
  call void @__inc_ref(ptr %t201)
  %t472 = getelementptr ptr, ptr %t434, i32 1
  store ptr %t201, ptr %t472
  br label %reuse.in_place.end.481
reuse.in_place.end.481:
  br label %reuse.join.480
reuse.copy.479:
  %t483 = call ptr @__alloc(i64 16, i32 1)
  %t484 = inttoptr i64 46 to ptr
  %t485 = getelementptr ptr, ptr %t483, i32 0
  store ptr %t484, ptr %t485
  call void @__inc_ref(ptr %t201)
  %t486 = getelementptr ptr, ptr %t483, i32 1
  store ptr %t201, ptr %t486
  call void @__free_recursive(ptr %t434)
  br label %reuse.copy.end.482
reuse.copy.end.482:
  br label %reuse.join.480
reuse.join.480:
  %t487 = phi ptr [ %t434, %reuse.in_place.end.481 ], [ %t483, %reuse.copy.end.482 ]
  %t488 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t487, ptr %t488
  call void @__free_recursive(ptr %t445)
  call void @__free_recursive(ptr %t438)
  call void @__free_recursive(ptr %t436)
  call void @__free_recursive(ptr %t201)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.25.491:
  %t492 = getelementptr ptr, ptr %t434, i32 1
  %t493 = load ptr, ptr %t492
  call void @__inc_ref(ptr %t493)
  %t494 = getelementptr ptr, ptr %t434, i32 2
  %t495 = load ptr, ptr %t494
  %t496 = getelementptr ptr, ptr %t4, i32 1
  %t497 = load ptr, ptr %t496
  call void @__free_recursive(ptr %t497)
  %t498 = getelementptr ptr, ptr %t4, i32 2
  %t499 = load ptr, ptr %t498
  call void @__free_recursive(ptr %t499)
  %t532 = inttoptr i64 53 to ptr
  %t533 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t532, ptr %t533
  %t500 = getelementptr ptr, ptr %t199, i32 1
  %t501 = load ptr, ptr %t500
  call void @__free_recursive(ptr %t501)
  %t502 = getelementptr ptr, ptr %t199, i32 2
  %t503 = load ptr, ptr %t502
  call void @__free_recursive(ptr %t503)
  %t504 = getelementptr ptr, ptr %t199, i32 3
  %t505 = load ptr, ptr %t504
  call void @__free_recursive(ptr %t505)
  %t509 = inttoptr i64 38 to ptr
  %t510 = getelementptr ptr, ptr %t199, i32 0
  store ptr %t509, ptr %t510
  call void @__inc_ref(ptr %t436)
  %t506 = getelementptr ptr, ptr %t199, i32 1
  store ptr %t436, ptr %t506
  call void @__inc_ref(ptr %t438)
  %t507 = getelementptr ptr, ptr %t199, i32 2
  store ptr %t438, ptr %t507
  call void @__inc_ref(ptr %t493)
  %t508 = getelementptr ptr, ptr %t199, i32 3
  store ptr %t493, ptr %t508
  %t511 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t199, ptr %t511
  %t517 = getelementptr i8, ptr %t434, i64 -8
  %t518 = load i32, ptr %t517
  %t519 = icmp eq i32 %t518, 1
  br i1 %t519, label %reuse.in_place.520, label %reuse.copy.521
reuse.in_place.520:
  %t512 = getelementptr ptr, ptr %t434, i32 1
  %t513 = load ptr, ptr %t512
  call void @__free_recursive(ptr %t513)
  %t515 = inttoptr i64 47 to ptr
  %t516 = getelementptr ptr, ptr %t434, i32 0
  store ptr %t515, ptr %t516
  call void @__inc_ref(ptr %t201)
  %t514 = getelementptr ptr, ptr %t434, i32 1
  store ptr %t201, ptr %t514
  br label %reuse.in_place.end.523
reuse.in_place.end.523:
  br label %reuse.join.522
reuse.copy.521:
  %t525 = call ptr @__alloc(i64 24, i32 2)
  %t526 = inttoptr i64 47 to ptr
  %t527 = getelementptr ptr, ptr %t525, i32 0
  store ptr %t526, ptr %t527
  call void @__inc_ref(ptr %t201)
  %t528 = getelementptr ptr, ptr %t525, i32 1
  store ptr %t201, ptr %t528
  call void @__inc_ref(ptr %t495)
  %t529 = getelementptr ptr, ptr %t525, i32 2
  store ptr %t495, ptr %t529
  call void @__free_recursive(ptr %t434)
  br label %reuse.copy.end.524
reuse.copy.end.524:
  br label %reuse.join.522
reuse.join.522:
  %t530 = phi ptr [ %t434, %reuse.in_place.end.523 ], [ %t525, %reuse.copy.end.524 ]
  %t531 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t530, ptr %t531
  call void @__free_recursive(ptr %t493)
  call void @__free_recursive(ptr %t438)
  call void @__free_recursive(ptr %t436)
  call void @__free_recursive(ptr %t201)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.442:
  unreachable
tco.case.arm.37.534:
  %t535 = getelementptr ptr, ptr %t199, i32 1
  %t536 = load ptr, ptr %t535
  call void @__inc_ref(ptr %t536)
  %t537 = getelementptr ptr, ptr %t536, i32 0
  %t538 = load ptr, ptr %t537
  %t539 = ptrtoint ptr %t538 to i64
  switch i64 %t539, label %tco.case.default.540 [ i64 5, label %tco.case.arm.5.541 i64 6, label %tco.case.arm.6.554 i64 7, label %tco.case.arm.7.563 i64 8, label %tco.case.arm.8.586 ]
tco.case.arm.5.541:
  %t542 = getelementptr ptr, ptr %t4, i32 1
  %t543 = load ptr, ptr %t542
  call void @__free_recursive(ptr %t543)
  %t552 = inttoptr i64 53 to ptr
  %t553 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t552, ptr %t553
  %t544 = getelementptr ptr, ptr %t536, i32 1
  %t545 = load ptr, ptr %t544
  call void @__inc_ref(ptr %t545)
  %t546 = getelementptr ptr, ptr %t199, i32 1
  %t547 = load ptr, ptr %t546
  call void @__free_recursive(ptr %t547)
  %t549 = inttoptr i64 39 to ptr
  %t550 = getelementptr ptr, ptr %t199, i32 0
  store ptr %t549, ptr %t550
  %t548 = getelementptr ptr, ptr %t199, i32 1
  store ptr %t545, ptr %t548
  %t551 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t199, ptr %t551
  call void @__free_recursive(ptr %t536)
  call void @__free_recursive(ptr %t201)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.6.554:
  %t555 = getelementptr ptr, ptr %t4, i32 1
  %t556 = load ptr, ptr %t555
  call void @__free_recursive(ptr %t556)
  %t557 = getelementptr ptr, ptr %t4, i32 2
  %t558 = load ptr, ptr %t557
  call void @__free_recursive(ptr %t558)
  %t561 = inttoptr i64 52 to ptr
  %t562 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t561, ptr %t562
  call void @__inc_ref(ptr %t201)
  %t559 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t201, ptr %t559
  call void @__inc_ref(ptr %t536)
  %t560 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t536, ptr %t560
  call void @__free_recursive(ptr %t199)
  call void @__free_recursive(ptr %t536)
  call void @__free_recursive(ptr %t201)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.7.563:
  %t564 = call ptr @__alloc(i64 24, i32 2)
  %t565 = inttoptr i64 53 to ptr
  %t566 = getelementptr ptr, ptr %t564, i32 0
  store ptr %t565, ptr %t566
  %t567 = getelementptr ptr, ptr %t536, i32 2
  %t568 = load ptr, ptr %t567
  call void @__inc_ref(ptr %t568)
  %t569 = getelementptr ptr, ptr %t199, i32 1
  %t570 = load ptr, ptr %t569
  call void @__free_recursive(ptr %t570)
  %t572 = inttoptr i64 37 to ptr
  %t573 = getelementptr ptr, ptr %t199, i32 0
  store ptr %t572, ptr %t573
  %t571 = getelementptr ptr, ptr %t199, i32 1
  store ptr %t568, ptr %t571
  %t574 = getelementptr ptr, ptr %t564, i32 1
  store ptr %t199, ptr %t574
  %t575 = getelementptr ptr, ptr %t536, i32 1
  %t576 = load ptr, ptr %t575
  call void @__inc_ref(ptr %t576)
  %t577 = getelementptr ptr, ptr %t4, i32 1
  %t578 = load ptr, ptr %t577
  call void @__free_recursive(ptr %t578)
  %t579 = getelementptr ptr, ptr %t4, i32 2
  %t580 = load ptr, ptr %t579
  call void @__free_recursive(ptr %t580)
  %t583 = inttoptr i64 48 to ptr
  %t584 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t583, ptr %t584
  call void @__inc_ref(ptr %t201)
  %t581 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t201, ptr %t581
  %t582 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t576, ptr %t582
  %t585 = getelementptr ptr, ptr %t564, i32 2
  store ptr %t4, ptr %t585
  call void @__free_recursive(ptr %t536)
  call void @__free_recursive(ptr %t201)
  store ptr %t564, ptr %t3
  br label %tco.loop.0
tco.case.arm.8.586:
  %t587 = getelementptr ptr, ptr %t4, i32 1
  %t588 = load ptr, ptr %t587
  call void @__free_recursive(ptr %t588)
  %t589 = getelementptr ptr, ptr %t4, i32 2
  %t590 = load ptr, ptr %t589
  call void @__free_recursive(ptr %t590)
  %t604 = inttoptr i64 52 to ptr
  %t605 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t604, ptr %t605
  call void @__inc_ref(ptr %t201)
  %t591 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t201, ptr %t591
  %t592 = call ptr @__alloc(i64 16, i32 1)
  %t593 = inttoptr i64 8 to ptr
  %t594 = getelementptr ptr, ptr %t592, i32 0
  store ptr %t593, ptr %t594
  %t595 = getelementptr ptr, ptr %t536, i32 1
  %t596 = load ptr, ptr %t595
  call void @__inc_ref(ptr %t596)
  %t597 = getelementptr ptr, ptr %t199, i32 1
  %t598 = load ptr, ptr %t597
  call void @__free_recursive(ptr %t598)
  %t600 = inttoptr i64 26 to ptr
  %t601 = getelementptr ptr, ptr %t199, i32 0
  store ptr %t600, ptr %t601
  %t599 = getelementptr ptr, ptr %t199, i32 1
  store ptr %t596, ptr %t599
  %t602 = getelementptr ptr, ptr %t592, i32 1
  store ptr %t199, ptr %t602
  %t603 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t592, ptr %t603
  call void @__free_recursive(ptr %t536)
  call void @__free_recursive(ptr %t201)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.540:
  unreachable
tco.case.arm.38.606:
  %t607 = getelementptr ptr, ptr %t199, i32 1
  %t608 = load ptr, ptr %t607
  call void @__inc_ref(ptr %t608)
  %t609 = getelementptr ptr, ptr %t199, i32 2
  %t610 = load ptr, ptr %t609
  %t611 = getelementptr ptr, ptr %t199, i32 3
  %t612 = load ptr, ptr %t611
  call void @__inc_ref(ptr %t612)
  %t613 = getelementptr ptr, ptr %t612, i32 0
  %t614 = load ptr, ptr %t613
  %t615 = ptrtoint ptr %t614 to i64
  switch i64 %t615, label %tco.case.default.616 [ i64 15, label %tco.case.arm.15.617 ]
tco.case.arm.15.617:
  %t618 = getelementptr ptr, ptr %t612, i32 1
  %t619 = load ptr, ptr %t618
  %t620 = getelementptr ptr, ptr %t612, i32 2
  %t621 = load ptr, ptr %t620
  call void @__inc_ref(ptr %t621)
  %t622 = getelementptr ptr, ptr %t4, i32 1
  %t623 = load ptr, ptr %t622
  call void @__free_recursive(ptr %t623)
  %t624 = getelementptr ptr, ptr %t4, i32 2
  %t625 = load ptr, ptr %t624
  call void @__free_recursive(ptr %t625)
  %t656 = inttoptr i64 53 to ptr
  %t657 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t656, ptr %t657
  %t632 = getelementptr i8, ptr %t612, i64 -8
  %t633 = load i32, ptr %t632
  %t634 = icmp eq i32 %t633, 1
  br i1 %t634, label %reuse.in_place.635, label %reuse.copy.636
reuse.in_place.635:
  %t626 = getelementptr ptr, ptr %t612, i32 2
  %t627 = load ptr, ptr %t626
  call void @__free_recursive(ptr %t627)
  %t630 = inttoptr i64 32 to ptr
  %t631 = getelementptr ptr, ptr %t612, i32 0
  store ptr %t630, ptr %t631
  call void @__inc_ref(ptr %t608)
  %t628 = getelementptr ptr, ptr %t612, i32 1
  store ptr %t608, ptr %t628
  %t629 = getelementptr ptr, ptr %t612, i32 2
  store ptr %t619, ptr %t629
  br label %reuse.in_place.end.638
reuse.in_place.end.638:
  br label %reuse.join.637
reuse.copy.636:
  %t640 = call ptr @__alloc(i64 24, i32 2)
  %t641 = inttoptr i64 32 to ptr
  %t642 = getelementptr ptr, ptr %t640, i32 0
  store ptr %t641, ptr %t642
  call void @__inc_ref(ptr %t608)
  %t643 = getelementptr ptr, ptr %t640, i32 1
  store ptr %t608, ptr %t643
  call void @__inc_ref(ptr %t619)
  %t644 = getelementptr ptr, ptr %t640, i32 2
  store ptr %t619, ptr %t644
  call void @__free_recursive(ptr %t612)
  br label %reuse.copy.end.639
reuse.copy.end.639:
  br label %reuse.join.637
reuse.join.637:
  %t645 = phi ptr [ %t612, %reuse.in_place.end.638 ], [ %t640, %reuse.copy.end.639 ]
  %t646 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t645, ptr %t646
  %t647 = getelementptr ptr, ptr %t199, i32 1
  %t648 = load ptr, ptr %t647
  call void @__free_recursive(ptr %t648)
  %t649 = getelementptr ptr, ptr %t199, i32 3
  %t650 = load ptr, ptr %t649
  call void @__free_recursive(ptr %t650)
  %t653 = inttoptr i64 49 to ptr
  %t654 = getelementptr ptr, ptr %t199, i32 0
  store ptr %t653, ptr %t654
  call void @__inc_ref(ptr %t201)
  %t651 = getelementptr ptr, ptr %t199, i32 1
  store ptr %t201, ptr %t651
  call void @__inc_ref(ptr %t621)
  %t652 = getelementptr ptr, ptr %t199, i32 3
  store ptr %t621, ptr %t652
  %t655 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t199, ptr %t655
  call void @__free_recursive(ptr %t621)
  call void @__free_recursive(ptr %t608)
  call void @__free_recursive(ptr %t201)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.616:
  unreachable
tco.case.arm.39.658:
  %t659 = getelementptr ptr, ptr %t199, i32 1
  %t660 = load ptr, ptr %t659
  call void @__inc_ref(ptr %t660)
  %t661 = call ptr @__alloc(i64 24, i32 2)
  %t662 = inttoptr i64 53 to ptr
  %t663 = getelementptr ptr, ptr %t661, i32 0
  store ptr %t662, ptr %t663
  %t664 = call ptr @__alloc(i64 16, i32 1)
  %t665 = inttoptr i64 35 to ptr
  %t666 = getelementptr ptr, ptr %t664, i32 0
  store ptr %t665, ptr %t666
  %t667 = getelementptr ptr, ptr %t660, i32 0
  %t668 = load ptr, ptr %t667
  %t669 = ptrtoint ptr %t668 to i64
  switch i64 %t669, label %case.default.670 [ i64 13, label %case.arm.13.672 i64 14, label %case.arm.14.699 ]
case.arm.13.672:
  %t674 = call ptr @__alloc(i64 8, i32 0)
  %t675 = inttoptr i64 2 to ptr
  %t676 = getelementptr ptr, ptr %t674, i32 0
  store ptr %t675, ptr %t676
  %t677 = getelementptr ptr, ptr %t4, i32 1
  %t678 = load ptr, ptr %t677
  call void @__free_recursive(ptr %t678)
  %t679 = getelementptr ptr, ptr %t4, i32 2
  %t680 = load ptr, ptr %t679
  call void @__free_recursive(ptr %t680)
  %t697 = inttoptr i64 25 to ptr
  %t698 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t697, ptr %t698
  %t683 = getelementptr i8, ptr %t660, i64 -8
  %t684 = load i32, ptr %t683
  %t685 = icmp eq i32 %t684, 1
  br i1 %t685, label %reuse.in_place.686, label %reuse.copy.687
reuse.in_place.686:
  %t681 = inttoptr i64 1 to ptr
  %t682 = getelementptr ptr, ptr %t660, i32 0
  store ptr %t681, ptr %t682
  br label %reuse.in_place.end.689
reuse.in_place.end.689:
  br label %reuse.join.688
reuse.copy.687:
  %t691 = call ptr @__alloc(i64 8, i32 0)
  %t692 = inttoptr i64 1 to ptr
  %t693 = getelementptr ptr, ptr %t691, i32 0
  store ptr %t692, ptr %t693
  call void @__free_recursive(ptr %t660)
  br label %reuse.copy.end.690
reuse.copy.end.690:
  br label %reuse.join.688
reuse.join.688:
  %t694 = phi ptr [ %t660, %reuse.in_place.end.689 ], [ %t691, %reuse.copy.end.690 ]
  %t695 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t694, ptr %t695
  %t696 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t674, ptr %t696
  call void @__free_recursive(ptr %t199)
  br label %case.end.13.673
case.end.13.673:
  br label %case.join.671
case.arm.14.699:
  %t701 = getelementptr ptr, ptr %t199, i32 1
  %t702 = load ptr, ptr %t701
  call void @__free_recursive(ptr %t702)
  %t736 = inttoptr i64 24 to ptr
  %t737 = getelementptr ptr, ptr %t199, i32 0
  store ptr %t736, ptr %t737
  %t703 = call ptr @__alloc(i64 24, i32 2)
  %t704 = inttoptr i64 25 to ptr
  %t705 = getelementptr ptr, ptr %t703, i32 0
  store ptr %t704, ptr %t705
  %t706 = call ptr @__alloc(i64 8, i32 0)
  %t707 = inttoptr i64 1 to ptr
  %t708 = getelementptr ptr, ptr %t706, i32 0
  store ptr %t707, ptr %t708
  %t709 = call ptr @__alloc(i64 8, i32 0)
  %t710 = inttoptr i64 2 to ptr
  %t711 = getelementptr ptr, ptr %t709, i32 0
  store ptr %t710, ptr %t711
  %t716 = getelementptr i8, ptr %t660, i64 -8
  %t717 = load i32, ptr %t716
  %t718 = icmp eq i32 %t717, 1
  br i1 %t718, label %reuse.in_place.719, label %reuse.copy.720
reuse.in_place.719:
  %t714 = inttoptr i64 15 to ptr
  %t715 = getelementptr ptr, ptr %t660, i32 0
  store ptr %t714, ptr %t715
  %t712 = getelementptr ptr, ptr %t660, i32 1
  store ptr %t706, ptr %t712
  %t713 = getelementptr ptr, ptr %t660, i32 2
  store ptr %t709, ptr %t713
  br label %reuse.in_place.end.722
reuse.in_place.end.722:
  br label %reuse.join.721
reuse.copy.720:
  %t724 = call ptr @__alloc(i64 24, i32 2)
  %t725 = inttoptr i64 15 to ptr
  %t726 = getelementptr ptr, ptr %t724, i32 0
  store ptr %t725, ptr %t726
  %t727 = getelementptr ptr, ptr %t724, i32 1
  store ptr %t706, ptr %t727
  %t728 = getelementptr ptr, ptr %t724, i32 2
  store ptr %t709, ptr %t728
  call void @__free_recursive(ptr %t660)
  br label %reuse.copy.end.723
reuse.copy.end.723:
  br label %reuse.join.721
reuse.join.721:
  %t729 = phi ptr [ %t660, %reuse.in_place.end.722 ], [ %t724, %reuse.copy.end.723 ]
  %t730 = getelementptr ptr, ptr %t703, i32 1
  store ptr %t729, ptr %t730
  %t731 = call ptr @__alloc(i64 8, i32 0)
  %t732 = inttoptr i64 2 to ptr
  %t733 = getelementptr ptr, ptr %t731, i32 0
  store ptr %t732, ptr %t733
  %t734 = getelementptr ptr, ptr %t703, i32 2
  store ptr %t731, ptr %t734
  %t735 = getelementptr ptr, ptr %t199, i32 1
  store ptr %t703, ptr %t735
  call void @__free_recursive(ptr %t4)
  br label %case.end.14.700
case.end.14.700:
  br label %case.join.671
case.default.670:
  unreachable
case.join.671:
  %t738 = phi ptr [ %t4, %case.end.13.673 ], [ %t199, %case.end.14.700 ]
  %t739 = getelementptr ptr, ptr %t664, i32 1
  store ptr %t738, ptr %t739
  %t740 = getelementptr ptr, ptr %t661, i32 1
  store ptr %t664, ptr %t740
  %t741 = call ptr @__alloc(i64 16, i32 1)
  %t742 = inttoptr i64 51 to ptr
  %t743 = getelementptr ptr, ptr %t741, i32 0
  store ptr %t742, ptr %t743
  call void @__inc_ref(ptr %t201)
  %t744 = getelementptr ptr, ptr %t741, i32 1
  store ptr %t201, ptr %t744
  %t745 = getelementptr ptr, ptr %t661, i32 2
  store ptr %t741, ptr %t745
  call void @__free_recursive(ptr %t201)
  store ptr %t661, ptr %t3
  br label %tco.loop.0
tco.case.default.205:
  unreachable
tco.case.default.8:
  unreachable
tco.exit.1:
  %t746 = load ptr, ptr %t2
  ret ptr %t746
}

define i32 @main(i32 %argc, ptr %argv) {
  %argc64 = sext i32 %argc to i64
  store i64 %argc64, ptr @.cli_argc
  store ptr %argv, ptr @.cli_argv
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
