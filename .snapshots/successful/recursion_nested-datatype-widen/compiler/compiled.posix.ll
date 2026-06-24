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
  %t35 = call ptr @v_$scc$$apply$$scc$$apply1__$df$$lam$14$7__$df$$lam$9$3__$df$$map$Nest$0__$df$$map$Nest$1__$df$$rowmono$0$andThenIO$6__$map$Maybe__run2__$cps$$scc$$apply1__$df$$lam$14$7__$df$$lam$9$3__$df$$map$Nest$0__$df$$map$Nest$1__$df$$rowmono$0$andThenIO$6__$map$Maybe__run2(ptr %t20)
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
  %t4 = inttoptr i64 36 to ptr
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
  %t19 = call ptr @v_$scc$$apply$$scc$$apply1__$df$$lam$14$7__$df$$lam$9$3__$df$$map$Nest$0__$df$$map$Nest$1__$df$$rowmono$0$andThenIO$6__$map$Maybe__run2__$cps$$scc$$apply1__$df$$lam$14$7__$df$$lam$9$3__$df$$map$Nest$0__$df$$map$Nest$1__$df$$rowmono$0$andThenIO$6__$map$Maybe__run2(ptr %t0)
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

define internal ptr @v_$scc$$apply$$scc$$apply1__$df$$lam$14$7__$df$$lam$9$3__$df$$map$Nest$0__$df$$map$Nest$1__$df$$rowmono$0$andThenIO$6__$map$Maybe__run2__$cps$$scc$$apply1__$df$$lam$14$7__$df$$lam$9$3__$df$$map$Nest$0__$df$$map$Nest$1__$df$$rowmono$0$andThenIO$6__$map$Maybe__run2(ptr %v_$args$1) {
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
  %t21 = inttoptr i64 36 to ptr
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
  %t62 = inttoptr i64 50 to ptr
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
  %t95 = call ptr @__alloc(i64 24, i32 2)
  %t96 = inttoptr i64 50 to ptr
  %t97 = getelementptr ptr, ptr %t95, i32 0
  store ptr %t96, ptr %t97
  %t98 = getelementptr ptr, ptr %t11, i32 1
  %t99 = load ptr, ptr %t98
  call void @__inc_ref(ptr %t99)
  %t100 = getelementptr ptr, ptr %t95, i32 1
  store ptr %t99, ptr %t100
  %t101 = getelementptr ptr, ptr %t11, i32 2
  %t102 = load ptr, ptr %t101
  call void @__inc_ref(ptr %t102)
  %t103 = getelementptr ptr, ptr %t4, i32 1
  %t104 = load ptr, ptr %t103
  call void @__free_recursive(ptr %t104)
  %t106 = inttoptr i64 7 to ptr
  %t107 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t106, ptr %t107
  %t105 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t102, ptr %t105
  %t108 = getelementptr ptr, ptr %t95, i32 2
  store ptr %t4, ptr %t108
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t95, ptr %t3
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
  switch i64 %t188, label %tco.case.default.189 [ i64 31, label %tco.case.arm.31.190 i64 32, label %tco.case.arm.32.282 i64 33, label %tco.case.arm.33.301 i64 34, label %tco.case.arm.34.320 i64 35, label %tco.case.arm.35.397 i64 36, label %tco.case.arm.36.484 i64 37, label %tco.case.arm.37.556 i64 38, label %tco.case.arm.38.589 ]
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
  switch i64 %t325, label %tco.case.default.326 [ i64 24, label %tco.case.arm.24.327 i64 25, label %tco.case.arm.25.364 ]
tco.case.arm.24.327:
  %t328 = getelementptr ptr, ptr %t322, i32 1
  %t329 = load ptr, ptr %t328
  call void @__inc_ref(ptr %t329)
  %t330 = call ptr @__alloc(i64 24, i32 2)
  %t331 = inttoptr i64 51 to ptr
  %t332 = getelementptr ptr, ptr %t330, i32 0
  store ptr %t331, ptr %t332
  %t333 = call ptr @__alloc(i64 8, i32 0)
  %t334 = inttoptr i64 29 to ptr
  %t335 = getelementptr ptr, ptr %t333, i32 0
  store ptr %t334, ptr %t335
  %t336 = getelementptr ptr, ptr %t4, i32 1
  %t337 = load ptr, ptr %t336
  call void @__free_recursive(ptr %t337)
  %t338 = getelementptr ptr, ptr %t4, i32 2
  %t339 = load ptr, ptr %t338
  call void @__free_recursive(ptr %t339)
  %t342 = inttoptr i64 35 to ptr
  %t343 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t342, ptr %t343
  call void @__inc_ref(ptr %t329)
  %t340 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t329, ptr %t340
  %t341 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t333, ptr %t341
  %t344 = getelementptr ptr, ptr %t330, i32 1
  store ptr %t4, ptr %t344
  %t350 = getelementptr i8, ptr %t322, i64 -8
  %t351 = load i32, ptr %t350
  %t352 = icmp eq i32 %t351, 1
  br i1 %t352, label %reuse.in_place.353, label %reuse.copy.354
reuse.in_place.353:
  %t345 = getelementptr ptr, ptr %t322, i32 1
  %t346 = load ptr, ptr %t345
  call void @__free_recursive(ptr %t346)
  %t348 = inttoptr i64 44 to ptr
  %t349 = getelementptr ptr, ptr %t322, i32 0
  store ptr %t348, ptr %t349
  call void @__inc_ref(ptr %t185)
  %t347 = getelementptr ptr, ptr %t322, i32 1
  store ptr %t185, ptr %t347
  br label %reuse.in_place.end.356
reuse.in_place.end.356:
  br label %reuse.join.355
reuse.copy.354:
  %t358 = call ptr @__alloc(i64 16, i32 1)
  %t359 = inttoptr i64 44 to ptr
  %t360 = getelementptr ptr, ptr %t358, i32 0
  store ptr %t359, ptr %t360
  call void @__inc_ref(ptr %t185)
  %t361 = getelementptr ptr, ptr %t358, i32 1
  store ptr %t185, ptr %t361
  call void @__free_recursive(ptr %t322)
  br label %reuse.copy.end.357
reuse.copy.end.357:
  br label %reuse.join.355
reuse.join.355:
  %t362 = phi ptr [ %t322, %reuse.in_place.end.356 ], [ %t358, %reuse.copy.end.357 ]
  %t363 = getelementptr ptr, ptr %t330, i32 2
  store ptr %t362, ptr %t363
  call void @__free_recursive(ptr %t329)
  call void @__free_recursive(ptr %t183)
  call void @__free_recursive(ptr %t185)
  store ptr %t330, ptr %t3
  br label %tco.loop.0
tco.case.arm.25.364:
  %t365 = getelementptr ptr, ptr %t322, i32 1
  %t366 = load ptr, ptr %t365
  call void @__inc_ref(ptr %t366)
  %t367 = getelementptr ptr, ptr %t4, i32 1
  %t368 = load ptr, ptr %t367
  call void @__free_recursive(ptr %t368)
  %t369 = getelementptr ptr, ptr %t4, i32 2
  %t370 = load ptr, ptr %t369
  call void @__free_recursive(ptr %t370)
  %t395 = inttoptr i64 50 to ptr
  %t396 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t395, ptr %t396
  call void @__inc_ref(ptr %t185)
  %t371 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t185, ptr %t371
  %t372 = call ptr @__alloc(i64 16, i32 1)
  %t373 = inttoptr i64 796142685 to ptr
  %t374 = getelementptr ptr, ptr %t372, i32 0
  store ptr %t373, ptr %t374
  call void @__inc_ref(ptr %t366)
  %t375 = getelementptr ptr, ptr %t372, i32 1
  store ptr %t366, ptr %t375
  %t381 = getelementptr i8, ptr %t322, i64 -8
  %t382 = load i32, ptr %t381
  %t383 = icmp eq i32 %t382, 1
  br i1 %t383, label %reuse.in_place.384, label %reuse.copy.385
reuse.in_place.384:
  %t376 = getelementptr ptr, ptr %t322, i32 1
  %t377 = load ptr, ptr %t376
  call void @__free_recursive(ptr %t377)
  %t379 = inttoptr i64 25 to ptr
  %t380 = getelementptr ptr, ptr %t322, i32 0
  store ptr %t379, ptr %t380
  %t378 = getelementptr ptr, ptr %t322, i32 1
  store ptr %t372, ptr %t378
  br label %reuse.in_place.end.387
reuse.in_place.end.387:
  br label %reuse.join.386
reuse.copy.385:
  %t389 = call ptr @__alloc(i64 16, i32 1)
  %t390 = inttoptr i64 25 to ptr
  %t391 = getelementptr ptr, ptr %t389, i32 0
  store ptr %t390, ptr %t391
  %t392 = getelementptr ptr, ptr %t389, i32 1
  store ptr %t372, ptr %t392
  call void @__free_recursive(ptr %t322)
  br label %reuse.copy.end.388
reuse.copy.end.388:
  br label %reuse.join.386
reuse.join.386:
  %t393 = phi ptr [ %t322, %reuse.in_place.end.387 ], [ %t389, %reuse.copy.end.388 ]
  %t394 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t393, ptr %t394
  call void @__free_recursive(ptr %t366)
  call void @__free_recursive(ptr %t183)
  call void @__free_recursive(ptr %t185)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.326:
  unreachable
tco.case.arm.35.397:
  %t398 = getelementptr ptr, ptr %t183, i32 1
  %t399 = load ptr, ptr %t398
  call void @__inc_ref(ptr %t399)
  %t400 = getelementptr ptr, ptr %t183, i32 2
  %t401 = load ptr, ptr %t400
  call void @__inc_ref(ptr %t401)
  %t402 = getelementptr ptr, ptr %t399, i32 0
  %t403 = load ptr, ptr %t402
  %t404 = ptrtoint ptr %t403 to i64
  switch i64 %t404, label %tco.case.default.405 [ i64 24, label %tco.case.arm.24.406 i64 25, label %tco.case.arm.25.447 ]
tco.case.arm.24.406:
  %t407 = getelementptr ptr, ptr %t399, i32 1
  %t408 = load ptr, ptr %t407
  call void @__inc_ref(ptr %t408)
  %t409 = call ptr @__alloc(i64 16, i32 1)
  %t410 = inttoptr i64 45 to ptr
  %t411 = getelementptr ptr, ptr %t409, i32 0
  store ptr %t410, ptr %t411
  call void @__inc_ref(ptr %t185)
  %t412 = getelementptr ptr, ptr %t409, i32 1
  store ptr %t185, ptr %t412
  %t413 = getelementptr ptr, ptr %t4, i32 1
  %t414 = load ptr, ptr %t413
  call void @__free_recursive(ptr %t414)
  %t415 = getelementptr ptr, ptr %t4, i32 2
  %t416 = load ptr, ptr %t415
  call void @__free_recursive(ptr %t416)
  %t445 = inttoptr i64 51 to ptr
  %t446 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t445, ptr %t446
  %t417 = getelementptr ptr, ptr %t183, i32 1
  %t418 = load ptr, ptr %t417
  call void @__free_recursive(ptr %t418)
  %t419 = getelementptr ptr, ptr %t183, i32 2
  %t420 = load ptr, ptr %t419
  call void @__free_recursive(ptr %t420)
  %t441 = inttoptr i64 35 to ptr
  %t442 = getelementptr ptr, ptr %t183, i32 0
  store ptr %t441, ptr %t442
  call void @__inc_ref(ptr %t408)
  %t421 = getelementptr ptr, ptr %t183, i32 1
  store ptr %t408, ptr %t421
  %t427 = getelementptr i8, ptr %t399, i64 -8
  %t428 = load i32, ptr %t427
  %t429 = icmp eq i32 %t428, 1
  br i1 %t429, label %reuse.in_place.430, label %reuse.copy.431
reuse.in_place.430:
  %t422 = getelementptr ptr, ptr %t399, i32 1
  %t423 = load ptr, ptr %t422
  call void @__free_recursive(ptr %t423)
  %t425 = inttoptr i64 30 to ptr
  %t426 = getelementptr ptr, ptr %t399, i32 0
  store ptr %t425, ptr %t426
  call void @__inc_ref(ptr %t401)
  %t424 = getelementptr ptr, ptr %t399, i32 1
  store ptr %t401, ptr %t424
  br label %reuse.in_place.end.433
reuse.in_place.end.433:
  br label %reuse.join.432
reuse.copy.431:
  %t435 = call ptr @__alloc(i64 16, i32 1)
  %t436 = inttoptr i64 30 to ptr
  %t437 = getelementptr ptr, ptr %t435, i32 0
  store ptr %t436, ptr %t437
  call void @__inc_ref(ptr %t401)
  %t438 = getelementptr ptr, ptr %t435, i32 1
  store ptr %t401, ptr %t438
  call void @__free_recursive(ptr %t399)
  br label %reuse.copy.end.434
reuse.copy.end.434:
  br label %reuse.join.432
reuse.join.432:
  %t439 = phi ptr [ %t399, %reuse.in_place.end.433 ], [ %t435, %reuse.copy.end.434 ]
  %t440 = getelementptr ptr, ptr %t183, i32 2
  store ptr %t439, ptr %t440
  %t443 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t183, ptr %t443
  %t444 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t409, ptr %t444
  call void @__free_recursive(ptr %t408)
  call void @__free_recursive(ptr %t401)
  call void @__free_recursive(ptr %t185)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.25.447:
  %t448 = getelementptr ptr, ptr %t399, i32 1
  %t449 = load ptr, ptr %t448
  call void @__inc_ref(ptr %t449)
  %t450 = getelementptr ptr, ptr %t4, i32 1
  %t451 = load ptr, ptr %t450
  call void @__free_recursive(ptr %t451)
  %t452 = getelementptr ptr, ptr %t4, i32 2
  %t453 = load ptr, ptr %t452
  call void @__free_recursive(ptr %t453)
  %t482 = inttoptr i64 51 to ptr
  %t483 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t482, ptr %t483
  %t454 = getelementptr ptr, ptr %t183, i32 1
  %t455 = load ptr, ptr %t454
  call void @__free_recursive(ptr %t455)
  %t456 = getelementptr ptr, ptr %t183, i32 2
  %t457 = load ptr, ptr %t456
  call void @__free_recursive(ptr %t457)
  %t460 = inttoptr i64 37 to ptr
  %t461 = getelementptr ptr, ptr %t183, i32 0
  store ptr %t460, ptr %t461
  call void @__inc_ref(ptr %t401)
  %t458 = getelementptr ptr, ptr %t183, i32 1
  store ptr %t401, ptr %t458
  call void @__inc_ref(ptr %t449)
  %t459 = getelementptr ptr, ptr %t183, i32 2
  store ptr %t449, ptr %t459
  %t462 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t183, ptr %t462
  %t468 = getelementptr i8, ptr %t399, i64 -8
  %t469 = load i32, ptr %t468
  %t470 = icmp eq i32 %t469, 1
  br i1 %t470, label %reuse.in_place.471, label %reuse.copy.472
reuse.in_place.471:
  %t463 = getelementptr ptr, ptr %t399, i32 1
  %t464 = load ptr, ptr %t463
  call void @__free_recursive(ptr %t464)
  %t466 = inttoptr i64 46 to ptr
  %t467 = getelementptr ptr, ptr %t399, i32 0
  store ptr %t466, ptr %t467
  call void @__inc_ref(ptr %t185)
  %t465 = getelementptr ptr, ptr %t399, i32 1
  store ptr %t185, ptr %t465
  br label %reuse.in_place.end.474
reuse.in_place.end.474:
  br label %reuse.join.473
reuse.copy.472:
  %t476 = call ptr @__alloc(i64 16, i32 1)
  %t477 = inttoptr i64 46 to ptr
  %t478 = getelementptr ptr, ptr %t476, i32 0
  store ptr %t477, ptr %t478
  call void @__inc_ref(ptr %t185)
  %t479 = getelementptr ptr, ptr %t476, i32 1
  store ptr %t185, ptr %t479
  call void @__free_recursive(ptr %t399)
  br label %reuse.copy.end.475
reuse.copy.end.475:
  br label %reuse.join.473
reuse.join.473:
  %t480 = phi ptr [ %t399, %reuse.in_place.end.474 ], [ %t476, %reuse.copy.end.475 ]
  %t481 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t480, ptr %t481
  call void @__free_recursive(ptr %t449)
  call void @__free_recursive(ptr %t401)
  call void @__free_recursive(ptr %t185)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.405:
  unreachable
tco.case.arm.36.484:
  %t485 = getelementptr ptr, ptr %t183, i32 1
  %t486 = load ptr, ptr %t485
  call void @__inc_ref(ptr %t486)
  %t487 = getelementptr ptr, ptr %t486, i32 0
  %t488 = load ptr, ptr %t487
  %t489 = ptrtoint ptr %t488 to i64
  switch i64 %t489, label %tco.case.default.490 [ i64 5, label %tco.case.arm.5.491 i64 6, label %tco.case.arm.6.504 i64 7, label %tco.case.arm.7.513 i64 8, label %tco.case.arm.8.536 ]
tco.case.arm.5.491:
  %t492 = getelementptr ptr, ptr %t4, i32 1
  %t493 = load ptr, ptr %t492
  call void @__free_recursive(ptr %t493)
  %t502 = inttoptr i64 51 to ptr
  %t503 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t502, ptr %t503
  %t494 = getelementptr ptr, ptr %t486, i32 1
  %t495 = load ptr, ptr %t494
  call void @__inc_ref(ptr %t495)
  %t496 = getelementptr ptr, ptr %t183, i32 1
  %t497 = load ptr, ptr %t496
  call void @__free_recursive(ptr %t497)
  %t499 = inttoptr i64 38 to ptr
  %t500 = getelementptr ptr, ptr %t183, i32 0
  store ptr %t499, ptr %t500
  %t498 = getelementptr ptr, ptr %t183, i32 1
  store ptr %t495, ptr %t498
  %t501 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t183, ptr %t501
  call void @__free_recursive(ptr %t486)
  call void @__free_recursive(ptr %t185)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.6.504:
  %t505 = getelementptr ptr, ptr %t4, i32 1
  %t506 = load ptr, ptr %t505
  call void @__free_recursive(ptr %t506)
  %t507 = getelementptr ptr, ptr %t4, i32 2
  %t508 = load ptr, ptr %t507
  call void @__free_recursive(ptr %t508)
  %t511 = inttoptr i64 50 to ptr
  %t512 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t511, ptr %t512
  call void @__inc_ref(ptr %t185)
  %t509 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t185, ptr %t509
  call void @__inc_ref(ptr %t486)
  %t510 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t486, ptr %t510
  call void @__free_recursive(ptr %t183)
  call void @__free_recursive(ptr %t486)
  call void @__free_recursive(ptr %t185)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.7.513:
  %t514 = call ptr @__alloc(i64 24, i32 2)
  %t515 = inttoptr i64 51 to ptr
  %t516 = getelementptr ptr, ptr %t514, i32 0
  store ptr %t515, ptr %t516
  %t517 = getelementptr ptr, ptr %t486, i32 2
  %t518 = load ptr, ptr %t517
  call void @__inc_ref(ptr %t518)
  %t519 = getelementptr ptr, ptr %t183, i32 1
  %t520 = load ptr, ptr %t519
  call void @__free_recursive(ptr %t520)
  %t522 = inttoptr i64 36 to ptr
  %t523 = getelementptr ptr, ptr %t183, i32 0
  store ptr %t522, ptr %t523
  %t521 = getelementptr ptr, ptr %t183, i32 1
  store ptr %t518, ptr %t521
  %t524 = getelementptr ptr, ptr %t514, i32 1
  store ptr %t183, ptr %t524
  %t525 = getelementptr ptr, ptr %t486, i32 1
  %t526 = load ptr, ptr %t525
  call void @__inc_ref(ptr %t526)
  %t527 = getelementptr ptr, ptr %t4, i32 1
  %t528 = load ptr, ptr %t527
  call void @__free_recursive(ptr %t528)
  %t529 = getelementptr ptr, ptr %t4, i32 2
  %t530 = load ptr, ptr %t529
  call void @__free_recursive(ptr %t530)
  %t533 = inttoptr i64 47 to ptr
  %t534 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t533, ptr %t534
  call void @__inc_ref(ptr %t185)
  %t531 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t185, ptr %t531
  %t532 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t526, ptr %t532
  %t535 = getelementptr ptr, ptr %t514, i32 2
  store ptr %t4, ptr %t535
  call void @__free_recursive(ptr %t486)
  call void @__free_recursive(ptr %t185)
  store ptr %t514, ptr %t3
  br label %tco.loop.0
tco.case.arm.8.536:
  %t537 = getelementptr ptr, ptr %t4, i32 1
  %t538 = load ptr, ptr %t537
  call void @__free_recursive(ptr %t538)
  %t539 = getelementptr ptr, ptr %t4, i32 2
  %t540 = load ptr, ptr %t539
  call void @__free_recursive(ptr %t540)
  %t554 = inttoptr i64 50 to ptr
  %t555 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t554, ptr %t555
  call void @__inc_ref(ptr %t185)
  %t541 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t185, ptr %t541
  %t542 = call ptr @__alloc(i64 16, i32 1)
  %t543 = inttoptr i64 8 to ptr
  %t544 = getelementptr ptr, ptr %t542, i32 0
  store ptr %t543, ptr %t544
  %t545 = getelementptr ptr, ptr %t486, i32 1
  %t546 = load ptr, ptr %t545
  call void @__inc_ref(ptr %t546)
  %t547 = getelementptr ptr, ptr %t183, i32 1
  %t548 = load ptr, ptr %t547
  call void @__free_recursive(ptr %t548)
  %t550 = inttoptr i64 26 to ptr
  %t551 = getelementptr ptr, ptr %t183, i32 0
  store ptr %t550, ptr %t551
  %t549 = getelementptr ptr, ptr %t183, i32 1
  store ptr %t546, ptr %t549
  %t552 = getelementptr ptr, ptr %t542, i32 1
  store ptr %t183, ptr %t552
  %t553 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t542, ptr %t553
  call void @__free_recursive(ptr %t486)
  call void @__free_recursive(ptr %t185)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.490:
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
  %t601 = inttoptr i64 34 to ptr
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
