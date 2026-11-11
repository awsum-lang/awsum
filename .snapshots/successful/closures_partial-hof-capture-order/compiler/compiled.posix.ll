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
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [11 x i8]} { i32 0, i32 0, i32 0, i32 11, i32 11, [11 x i8] c"MISSING_ARG" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [8 x i8]} { i32 0, i32 0, i32 0, i32 8, i32 8, [8 x i8] c"captured" }

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
  %t21 = inttoptr i64 43 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = call ptr @__alloc(i64 24, i32 2)
  %t24 = inttoptr i64 29 to ptr
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
  %t32 = inttoptr i64 37 to ptr
  %t33 = getelementptr ptr, ptr %t31, i32 0
  store ptr %t32, ptr %t33
  %t34 = getelementptr ptr, ptr %t20, i32 2
  store ptr %t31, ptr %t34
  %t35 = call ptr @v_$scc$$apply$$scc$$apply1__$df$$lam$13$6__$df$$lam$$x$453351457(ptr %t20)
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
  %t1 = inttoptr i64 43 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 16, i32 1)
  %t4 = inttoptr i64 32 to ptr
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
  %t16 = inttoptr i64 37 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t15, ptr %t18
  %t19 = call ptr @v_$scc$$apply$$scc$$apply1__$df$$lam$13$6__$df$$lam$$x$453351457(ptr %t0)
  %t20 = call ptr @__alloc(i64 8, i32 0)
  %t21 = inttoptr i64 35 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = call ptr @v_$cps$$df$handleErrorIO$1(ptr %t19, ptr %t20)
  ret ptr %t23
}

define internal ptr @v_$cps$$df$handleErrorIO$1(ptr %v_io, ptr %v_$k) {
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
  %t12 = call ptr @v_$apply$$df$handleErrorIO$1(ptr %t6, ptr %t5)
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
  %t50 = call ptr @v_$apply$$df$handleErrorIO$1(ptr %t6, ptr %t49)
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
  %t60 = inttoptr i64 36 to ptr
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
  %t71 = inttoptr i64 36 to ptr
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
  %t83 = inttoptr i64 26 to ptr
  %t84 = getelementptr ptr, ptr %t82, i32 0
  store ptr %t83, ptr %t84
  call void @__inc_ref(ptr %t78)
  %t85 = getelementptr ptr, ptr %t82, i32 1
  store ptr %t78, ptr %t85
  %t86 = getelementptr ptr, ptr %t79, i32 1
  store ptr %t82, ptr %t86
  %t87 = call ptr @v_$apply$$df$handleErrorIO$1(ptr %t6, ptr %t79)
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

define internal ptr @v_$apply$$df$handleErrorIO$1(ptr %v_$k, ptr %v_$x) {
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

define internal ptr @v_$scc$$apply$$scc$$apply1__$df$$lam$13$6__$df$$lam$$x$453351457(ptr %v_$args$1) {
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
  switch i64 %t7, label %tco.case.default.8 [ i64 42, label %tco.case.arm.42.9 i64 43, label %tco.case.arm.43.87 ]
tco.case.arm.42.9:
  %t10 = getelementptr ptr, ptr %t4, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  %t12 = getelementptr ptr, ptr %t4, i32 2
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t11, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %tco.case.default.17 [ i64 37, label %tco.case.arm.37.18 i64 38, label %tco.case.arm.38.19 i64 39, label %tco.case.arm.39.34 i64 40, label %tco.case.arm.40.49 i64 41, label %tco.case.arm.41.64 ]
tco.case.arm.37.18:
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %t4)
  store ptr %t13, ptr %t2
  br label %tco.exit.1
tco.case.arm.38.19:
  %t20 = call ptr @__alloc(i64 16, i32 1)
  %t21 = inttoptr i64 32 to ptr
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
  %t32 = inttoptr i64 43 to ptr
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
tco.case.arm.39.34:
  %t35 = getelementptr ptr, ptr %t11, i32 1
  %t36 = load ptr, ptr %t35
  call void @__inc_ref(ptr %t36)
  call void @__inc_ref(ptr %t13)
  %t37 = call ptr @__alloc(i64 8, i32 0)
  %t38 = inttoptr i64 35 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = call ptr @v_$cps$$df$handleErrorIO$1(ptr %t13, ptr %t37)
  %t41 = getelementptr ptr, ptr %t4, i32 1
  %t42 = load ptr, ptr %t41
  call void @__free_recursive(ptr %t42)
  %t43 = getelementptr ptr, ptr %t4, i32 2
  %t44 = load ptr, ptr %t43
  call void @__free_recursive(ptr %t44)
  %t47 = inttoptr i64 42 to ptr
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
tco.case.arm.40.49:
  %t50 = call ptr @__alloc(i64 24, i32 2)
  %t51 = inttoptr i64 42 to ptr
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
tco.case.arm.41.64:
  %t65 = call ptr @__alloc(i64 24, i32 2)
  %t66 = inttoptr i64 42 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  %t68 = getelementptr ptr, ptr %t11, i32 1
  %t69 = load ptr, ptr %t68
  call void @__inc_ref(ptr %t69)
  %t70 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t69, ptr %t70
  %t71 = call ptr @__alloc(i64 16, i32 1)
  %t72 = inttoptr i64 5 to ptr
  %t73 = getelementptr ptr, ptr %t71, i32 0
  store ptr %t72, ptr %t73
  %t74 = call ptr @__alloc(i64 8, i32 0)
  %t75 = inttoptr i64 0 to ptr
  %t76 = getelementptr ptr, ptr %t74, i32 0
  store ptr %t75, ptr %t76
  %t77 = getelementptr ptr, ptr %t71, i32 1
  store ptr %t74, ptr %t77
  %t78 = getelementptr ptr, ptr %t4, i32 1
  %t79 = load ptr, ptr %t78
  call void @__free_recursive(ptr %t79)
  %t80 = getelementptr ptr, ptr %t4, i32 2
  %t81 = load ptr, ptr %t80
  call void @__free_recursive(ptr %t81)
  %t84 = inttoptr i64 7 to ptr
  %t85 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t84, ptr %t85
  call void @__inc_ref(ptr %t13)
  %t82 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t13, ptr %t82
  %t83 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t71, ptr %t83
  %t86 = getelementptr ptr, ptr %t65, i32 2
  store ptr %t4, ptr %t86
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t65, ptr %t3
  br label %tco.loop.0
tco.case.default.17:
  unreachable
tco.case.arm.43.87:
  %t88 = getelementptr ptr, ptr %t4, i32 1
  %t89 = load ptr, ptr %t88
  call void @__inc_ref(ptr %t89)
  %t90 = getelementptr ptr, ptr %t4, i32 2
  %t91 = load ptr, ptr %t90
  call void @__inc_ref(ptr %t91)
  %t92 = getelementptr ptr, ptr %t89, i32 0
  %t93 = load ptr, ptr %t92
  %t94 = ptrtoint ptr %t93 to i64
  switch i64 %t94, label %tco.case.default.95 [ i64 29, label %tco.case.arm.29.96 i64 30, label %tco.case.arm.30.173 i64 31, label %tco.case.arm.31.192 i64 32, label %tco.case.arm.32.211 i64 33, label %tco.case.arm.33.283 i64 34, label %tco.case.arm.34.300 ]
tco.case.arm.29.96:
  %t97 = getelementptr ptr, ptr %t89, i32 1
  %t98 = load ptr, ptr %t97
  call void @__inc_ref(ptr %t98)
  %t99 = getelementptr ptr, ptr %t89, i32 2
  %t100 = load ptr, ptr %t99
  call void @__inc_ref(ptr %t100)
  %t101 = getelementptr ptr, ptr %t98, i32 0
  %t102 = load ptr, ptr %t101
  %t103 = ptrtoint ptr %t102 to i64
  switch i64 %t103, label %tco.case.default.104 [ i64 25, label %tco.case.arm.25.105 i64 26, label %tco.case.arm.26.118 i64 27, label %tco.case.arm.27.131 i64 28, label %tco.case.arm.28.142 ]
tco.case.arm.25.105:
  %t106 = getelementptr ptr, ptr %t4, i32 1
  %t107 = load ptr, ptr %t106
  call void @__free_recursive(ptr %t107)
  %t116 = inttoptr i64 43 to ptr
  %t117 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t116, ptr %t117
  %t108 = getelementptr ptr, ptr %t98, i32 1
  %t109 = load ptr, ptr %t108
  call void @__inc_ref(ptr %t109)
  %t110 = getelementptr ptr, ptr %t89, i32 1
  %t111 = load ptr, ptr %t110
  call void @__free_recursive(ptr %t111)
  %t113 = inttoptr i64 30 to ptr
  %t114 = getelementptr ptr, ptr %t89, i32 0
  store ptr %t113, ptr %t114
  %t112 = getelementptr ptr, ptr %t89, i32 1
  store ptr %t109, ptr %t112
  %t115 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t89, ptr %t115
  call void @__free_recursive(ptr %t100)
  call void @__free_recursive(ptr %t98)
  call void @__free_recursive(ptr %t91)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.26.118:
  %t119 = getelementptr ptr, ptr %t4, i32 1
  %t120 = load ptr, ptr %t119
  call void @__free_recursive(ptr %t120)
  %t129 = inttoptr i64 43 to ptr
  %t130 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t129, ptr %t130
  %t121 = getelementptr ptr, ptr %t98, i32 1
  %t122 = load ptr, ptr %t121
  call void @__inc_ref(ptr %t122)
  %t123 = getelementptr ptr, ptr %t89, i32 1
  %t124 = load ptr, ptr %t123
  call void @__free_recursive(ptr %t124)
  %t126 = inttoptr i64 31 to ptr
  %t127 = getelementptr ptr, ptr %t89, i32 0
  store ptr %t126, ptr %t127
  %t125 = getelementptr ptr, ptr %t89, i32 1
  store ptr %t122, ptr %t125
  %t128 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t89, ptr %t128
  call void @__free_recursive(ptr %t100)
  call void @__free_recursive(ptr %t98)
  call void @__free_recursive(ptr %t91)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.27.131:
  %t132 = getelementptr ptr, ptr %t98, i32 1
  %t133 = load ptr, ptr %t132
  call void @__inc_ref(ptr %t133)
  %t134 = getelementptr ptr, ptr %t89, i32 1
  %t135 = load ptr, ptr %t134
  call void @__free_recursive(ptr %t135)
  %t136 = getelementptr ptr, ptr %t89, i32 2
  %t137 = load ptr, ptr %t136
  call void @__free_recursive(ptr %t137)
  %t140 = inttoptr i64 42 to ptr
  %t141 = getelementptr ptr, ptr %t89, i32 0
  store ptr %t140, ptr %t141
  call void @__inc_ref(ptr %t91)
  %t138 = getelementptr ptr, ptr %t89, i32 1
  store ptr %t91, ptr %t138
  %t139 = getelementptr ptr, ptr %t89, i32 2
  store ptr %t133, ptr %t139
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t100)
  call void @__free_recursive(ptr %t98)
  call void @__free_recursive(ptr %t91)
  store ptr %t89, ptr %t3
  br label %tco.loop.0
tco.case.arm.28.142:
  %t143 = getelementptr ptr, ptr %t100, i32 0
  %t144 = load ptr, ptr %t143
  %t145 = ptrtoint ptr %t144 to i64
  switch i64 %t145, label %case.default.146 [ i64 3, label %case.arm.3.148 i64 4, label %case.arm.4.156 ]
case.arm.3.148:
  %t150 = call ptr @__alloc(i64 16, i32 1)
  %t151 = inttoptr i64 6 to ptr
  %t152 = getelementptr ptr, ptr %t150, i32 0
  store ptr %t151, ptr %t152
  %t153 = getelementptr ptr, ptr %t100, i32 1
  %t154 = load ptr, ptr %t153
  call void @__inc_ref(ptr %t154)
  %t155 = getelementptr ptr, ptr %t150, i32 1
  store ptr %t154, ptr %t155
  br label %case.end.3.149
case.end.3.149:
  br label %case.join.147
case.arm.4.156:
  %t158 = call ptr @__alloc(i64 16, i32 1)
  %t159 = inttoptr i64 5 to ptr
  %t160 = getelementptr ptr, ptr %t158, i32 0
  store ptr %t159, ptr %t160
  %t161 = getelementptr ptr, ptr %t100, i32 1
  %t162 = load ptr, ptr %t161
  call void @__inc_ref(ptr %t162)
  %t163 = getelementptr ptr, ptr %t158, i32 1
  store ptr %t162, ptr %t163
  br label %case.end.4.157
case.end.4.157:
  br label %case.join.147
case.default.146:
  unreachable
case.join.147:
  %t164 = phi ptr [ %t150, %case.end.3.149 ], [ %t158, %case.end.4.157 ]
  %t165 = getelementptr ptr, ptr %t89, i32 1
  %t166 = load ptr, ptr %t165
  call void @__free_recursive(ptr %t166)
  %t167 = getelementptr ptr, ptr %t89, i32 2
  %t168 = load ptr, ptr %t167
  call void @__free_recursive(ptr %t168)
  %t171 = inttoptr i64 42 to ptr
  %t172 = getelementptr ptr, ptr %t89, i32 0
  store ptr %t171, ptr %t172
  call void @__inc_ref(ptr %t91)
  %t169 = getelementptr ptr, ptr %t89, i32 1
  store ptr %t91, ptr %t169
  %t170 = getelementptr ptr, ptr %t89, i32 2
  store ptr %t164, ptr %t170
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t100)
  call void @__free_recursive(ptr %t98)
  call void @__free_recursive(ptr %t91)
  store ptr %t89, ptr %t3
  br label %tco.loop.0
tco.case.default.104:
  unreachable
tco.case.arm.30.173:
  %t174 = getelementptr ptr, ptr %t89, i32 1
  %t175 = load ptr, ptr %t174
  %t176 = getelementptr ptr, ptr %t89, i32 2
  %t177 = load ptr, ptr %t176
  %t178 = call ptr @__alloc(i64 16, i32 1)
  %t179 = inttoptr i64 38 to ptr
  %t180 = getelementptr ptr, ptr %t178, i32 0
  store ptr %t179, ptr %t180
  call void @__inc_ref(ptr %t91)
  %t181 = getelementptr ptr, ptr %t178, i32 1
  store ptr %t91, ptr %t181
  %t182 = getelementptr ptr, ptr %t4, i32 1
  %t183 = load ptr, ptr %t182
  call void @__free_recursive(ptr %t183)
  %t184 = getelementptr ptr, ptr %t4, i32 2
  %t185 = load ptr, ptr %t184
  call void @__free_recursive(ptr %t185)
  %t190 = inttoptr i64 43 to ptr
  %t191 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t190, ptr %t191
  %t186 = inttoptr i64 29 to ptr
  %t187 = getelementptr ptr, ptr %t89, i32 0
  store ptr %t186, ptr %t187
  %t188 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t89, ptr %t188
  %t189 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t178, ptr %t189
  call void @__free_recursive(ptr %t91)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.31.192:
  %t193 = getelementptr ptr, ptr %t89, i32 1
  %t194 = load ptr, ptr %t193
  %t195 = getelementptr ptr, ptr %t89, i32 2
  %t196 = load ptr, ptr %t195
  %t197 = call ptr @__alloc(i64 16, i32 1)
  %t198 = inttoptr i64 39 to ptr
  %t199 = getelementptr ptr, ptr %t197, i32 0
  store ptr %t198, ptr %t199
  call void @__inc_ref(ptr %t91)
  %t200 = getelementptr ptr, ptr %t197, i32 1
  store ptr %t91, ptr %t200
  %t201 = getelementptr ptr, ptr %t4, i32 1
  %t202 = load ptr, ptr %t201
  call void @__free_recursive(ptr %t202)
  %t203 = getelementptr ptr, ptr %t4, i32 2
  %t204 = load ptr, ptr %t203
  call void @__free_recursive(ptr %t204)
  %t209 = inttoptr i64 43 to ptr
  %t210 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t209, ptr %t210
  %t205 = inttoptr i64 29 to ptr
  %t206 = getelementptr ptr, ptr %t89, i32 0
  store ptr %t205, ptr %t206
  %t207 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t89, ptr %t207
  %t208 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t197, ptr %t208
  call void @__free_recursive(ptr %t91)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.32.211:
  %t212 = getelementptr ptr, ptr %t89, i32 1
  %t213 = load ptr, ptr %t212
  call void @__inc_ref(ptr %t213)
  %t214 = getelementptr ptr, ptr %t213, i32 0
  %t215 = load ptr, ptr %t214
  %t216 = ptrtoint ptr %t215 to i64
  switch i64 %t216, label %tco.case.default.217 [ i64 5, label %tco.case.arm.5.218 i64 6, label %tco.case.arm.6.231 i64 7, label %tco.case.arm.7.240 i64 8, label %tco.case.arm.8.263 ]
tco.case.arm.5.218:
  %t219 = getelementptr ptr, ptr %t4, i32 1
  %t220 = load ptr, ptr %t219
  call void @__free_recursive(ptr %t220)
  %t229 = inttoptr i64 43 to ptr
  %t230 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t229, ptr %t230
  %t221 = getelementptr ptr, ptr %t213, i32 1
  %t222 = load ptr, ptr %t221
  call void @__inc_ref(ptr %t222)
  %t223 = getelementptr ptr, ptr %t89, i32 1
  %t224 = load ptr, ptr %t223
  call void @__free_recursive(ptr %t224)
  %t226 = inttoptr i64 34 to ptr
  %t227 = getelementptr ptr, ptr %t89, i32 0
  store ptr %t226, ptr %t227
  %t225 = getelementptr ptr, ptr %t89, i32 1
  store ptr %t222, ptr %t225
  %t228 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t89, ptr %t228
  call void @__free_recursive(ptr %t213)
  call void @__free_recursive(ptr %t91)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.6.231:
  %t232 = getelementptr ptr, ptr %t4, i32 1
  %t233 = load ptr, ptr %t232
  call void @__free_recursive(ptr %t233)
  %t234 = getelementptr ptr, ptr %t4, i32 2
  %t235 = load ptr, ptr %t234
  call void @__free_recursive(ptr %t235)
  %t238 = inttoptr i64 42 to ptr
  %t239 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t238, ptr %t239
  call void @__inc_ref(ptr %t91)
  %t236 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t91, ptr %t236
  call void @__inc_ref(ptr %t213)
  %t237 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t213, ptr %t237
  call void @__free_recursive(ptr %t89)
  call void @__free_recursive(ptr %t213)
  call void @__free_recursive(ptr %t91)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.7.240:
  %t241 = call ptr @__alloc(i64 24, i32 2)
  %t242 = inttoptr i64 43 to ptr
  %t243 = getelementptr ptr, ptr %t241, i32 0
  store ptr %t242, ptr %t243
  %t244 = getelementptr ptr, ptr %t213, i32 2
  %t245 = load ptr, ptr %t244
  call void @__inc_ref(ptr %t245)
  %t246 = getelementptr ptr, ptr %t89, i32 1
  %t247 = load ptr, ptr %t246
  call void @__free_recursive(ptr %t247)
  %t249 = inttoptr i64 32 to ptr
  %t250 = getelementptr ptr, ptr %t89, i32 0
  store ptr %t249, ptr %t250
  %t248 = getelementptr ptr, ptr %t89, i32 1
  store ptr %t245, ptr %t248
  %t251 = getelementptr ptr, ptr %t241, i32 1
  store ptr %t89, ptr %t251
  %t252 = getelementptr ptr, ptr %t213, i32 1
  %t253 = load ptr, ptr %t252
  call void @__inc_ref(ptr %t253)
  %t254 = getelementptr ptr, ptr %t4, i32 1
  %t255 = load ptr, ptr %t254
  call void @__free_recursive(ptr %t255)
  %t256 = getelementptr ptr, ptr %t4, i32 2
  %t257 = load ptr, ptr %t256
  call void @__free_recursive(ptr %t257)
  %t260 = inttoptr i64 40 to ptr
  %t261 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t260, ptr %t261
  call void @__inc_ref(ptr %t91)
  %t258 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t91, ptr %t258
  %t259 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t253, ptr %t259
  %t262 = getelementptr ptr, ptr %t241, i32 2
  store ptr %t4, ptr %t262
  call void @__free_recursive(ptr %t213)
  call void @__free_recursive(ptr %t91)
  store ptr %t241, ptr %t3
  br label %tco.loop.0
tco.case.arm.8.263:
  %t264 = getelementptr ptr, ptr %t4, i32 1
  %t265 = load ptr, ptr %t264
  call void @__free_recursive(ptr %t265)
  %t266 = getelementptr ptr, ptr %t4, i32 2
  %t267 = load ptr, ptr %t266
  call void @__free_recursive(ptr %t267)
  %t281 = inttoptr i64 42 to ptr
  %t282 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t281, ptr %t282
  call void @__inc_ref(ptr %t91)
  %t268 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t91, ptr %t268
  %t269 = call ptr @__alloc(i64 16, i32 1)
  %t270 = inttoptr i64 8 to ptr
  %t271 = getelementptr ptr, ptr %t269, i32 0
  store ptr %t270, ptr %t271
  %t272 = getelementptr ptr, ptr %t213, i32 1
  %t273 = load ptr, ptr %t272
  call void @__inc_ref(ptr %t273)
  %t274 = getelementptr ptr, ptr %t89, i32 1
  %t275 = load ptr, ptr %t274
  call void @__free_recursive(ptr %t275)
  %t277 = inttoptr i64 25 to ptr
  %t278 = getelementptr ptr, ptr %t89, i32 0
  store ptr %t277, ptr %t278
  %t276 = getelementptr ptr, ptr %t89, i32 1
  store ptr %t273, ptr %t276
  %t279 = getelementptr ptr, ptr %t269, i32 1
  store ptr %t89, ptr %t279
  %t280 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t269, ptr %t280
  call void @__free_recursive(ptr %t213)
  call void @__free_recursive(ptr %t91)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.217:
  unreachable
tco.case.arm.33.283:
  %t284 = getelementptr ptr, ptr %t89, i32 1
  %t285 = load ptr, ptr %t284
  call void @__inc_ref(ptr %t285)
  %t286 = getelementptr ptr, ptr %t89, i32 2
  %t287 = load ptr, ptr %t286
  %t288 = getelementptr ptr, ptr %t4, i32 1
  %t289 = load ptr, ptr %t288
  call void @__free_recursive(ptr %t289)
  %t298 = inttoptr i64 43 to ptr
  %t299 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t298, ptr %t299
  %t290 = getelementptr ptr, ptr %t285, i32 1
  %t291 = load ptr, ptr %t290
  call void @__inc_ref(ptr %t291)
  %t292 = getelementptr ptr, ptr %t89, i32 1
  %t293 = load ptr, ptr %t292
  call void @__free_recursive(ptr %t293)
  %t295 = inttoptr i64 29 to ptr
  %t296 = getelementptr ptr, ptr %t89, i32 0
  store ptr %t295, ptr %t296
  %t294 = getelementptr ptr, ptr %t89, i32 1
  store ptr %t291, ptr %t294
  %t297 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t89, ptr %t297
  call void @__free_recursive(ptr %t285)
  call void @__free_recursive(ptr %t91)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.34.300:
  %t301 = getelementptr ptr, ptr %t89, i32 1
  %t302 = load ptr, ptr %t301
  call void @__inc_ref(ptr %t302)
  %t303 = getelementptr ptr, ptr %t302, i32 0
  %t304 = load ptr, ptr %t303
  %t305 = ptrtoint ptr %t304 to i64
  switch i64 %t305, label %tco.case.default.306 [ i64 13, label %tco.case.arm.13.307 i64 14, label %tco.case.arm.14.329 ]
tco.case.arm.13.307:
  %t308 = call ptr @__alloc(i64 24, i32 2)
  %t309 = inttoptr i64 42 to ptr
  %t310 = getelementptr ptr, ptr %t308, i32 0
  store ptr %t309, ptr %t310
  call void @__inc_ref(ptr %t91)
  %t311 = getelementptr ptr, ptr %t308, i32 1
  store ptr %t91, ptr %t311
  %t312 = getelementptr ptr, ptr %t4, i32 1
  %t313 = load ptr, ptr %t312
  call void @__free_recursive(ptr %t313)
  %t314 = getelementptr ptr, ptr %t4, i32 2
  %t315 = load ptr, ptr %t314
  call void @__free_recursive(ptr %t315)
  %t326 = inttoptr i64 7 to ptr
  %t327 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t326, ptr %t327
  %t316 = getelementptr ptr, ptr %t4, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t316
  %t317 = call ptr @__alloc(i64 8, i32 0)
  %t318 = inttoptr i64 0 to ptr
  %t319 = getelementptr ptr, ptr %t317, i32 0
  store ptr %t318, ptr %t319
  %t320 = getelementptr ptr, ptr %t89, i32 1
  %t321 = load ptr, ptr %t320
  call void @__free_recursive(ptr %t321)
  %t323 = inttoptr i64 5 to ptr
  %t324 = getelementptr ptr, ptr %t89, i32 0
  store ptr %t323, ptr %t324
  %t322 = getelementptr ptr, ptr %t89, i32 1
  store ptr %t317, ptr %t322
  %t325 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t89, ptr %t325
  %t328 = getelementptr ptr, ptr %t308, i32 2
  store ptr %t4, ptr %t328
  call void @__free_recursive(ptr %t302)
  call void @__free_recursive(ptr %t91)
  store ptr %t308, ptr %t3
  br label %tco.loop.0
tco.case.arm.14.329:
  %t330 = call ptr @__alloc(i64 24, i32 2)
  %t331 = inttoptr i64 43 to ptr
  %t332 = getelementptr ptr, ptr %t330, i32 0
  store ptr %t331, ptr %t332
  %t333 = getelementptr ptr, ptr %t302, i32 1
  %t334 = load ptr, ptr %t333
  call void @__inc_ref(ptr %t334)
  %t335 = getelementptr ptr, ptr %t4, i32 1
  %t336 = load ptr, ptr %t335
  call void @__free_recursive(ptr %t336)
  %t337 = getelementptr ptr, ptr %t4, i32 2
  %t338 = load ptr, ptr %t337
  call void @__free_recursive(ptr %t338)
  %t350 = inttoptr i64 33 to ptr
  %t351 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t350, ptr %t351
  %t339 = call ptr @__alloc(i64 16, i32 1)
  %t340 = inttoptr i64 24 to ptr
  %t341 = getelementptr ptr, ptr %t339, i32 0
  store ptr %t340, ptr %t341
  %t342 = getelementptr ptr, ptr %t89, i32 1
  %t343 = load ptr, ptr %t342
  call void @__free_recursive(ptr %t343)
  %t345 = inttoptr i64 27 to ptr
  %t346 = getelementptr ptr, ptr %t89, i32 0
  store ptr %t345, ptr %t346
  %t344 = getelementptr ptr, ptr %t89, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t344
  %t347 = getelementptr ptr, ptr %t339, i32 1
  store ptr %t89, ptr %t347
  %t348 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t339, ptr %t348
  %t349 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t334, ptr %t349
  %t352 = getelementptr ptr, ptr %t330, i32 1
  store ptr %t4, ptr %t352
  %t353 = call ptr @__alloc(i64 16, i32 1)
  %t354 = inttoptr i64 41 to ptr
  %t355 = getelementptr ptr, ptr %t353, i32 0
  store ptr %t354, ptr %t355
  call void @__inc_ref(ptr %t91)
  %t356 = getelementptr ptr, ptr %t353, i32 1
  store ptr %t91, ptr %t356
  %t357 = getelementptr ptr, ptr %t330, i32 2
  store ptr %t353, ptr %t357
  call void @__free_recursive(ptr %t302)
  call void @__free_recursive(ptr %t91)
  store ptr %t330, ptr %t3
  br label %tco.loop.0
tco.case.default.306:
  unreachable
tco.case.default.95:
  unreachable
tco.case.default.8:
  unreachable
tco.exit.1:
  %t358 = load ptr, ptr %t2
  ret ptr %t358
}

define i32 @main(i32 %argc, ptr %argv) {
  %argc64 = sext i32 %argc to i64
  store i64 %argc64, ptr @.cli_argc
  store ptr %argv, ptr @.cli_argv
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
