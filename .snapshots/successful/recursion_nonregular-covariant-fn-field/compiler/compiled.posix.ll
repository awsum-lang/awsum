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
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [9 x i8]} { i32 0, i32 0, i32 0, i32 9, i32 9, [9 x i8] c"hold-true" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [10 x i8]} { i32 0, i32 0, i32 0, i32 10, i32 10, [10 x i8] c"hold-false" }

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
  %t21 = inttoptr i64 50 to ptr
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
  %t35 = call ptr @v_$scc$$apply$$scc$$apply1__$df$$lam$17$9__$df$$lam$$x$1823383003(ptr %t20)
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
  %t1 = inttoptr i64 50 to ptr
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
  %t10 = inttoptr i64 29 to ptr
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
  %t19 = call ptr @v_$scc$$apply$$scc$$apply1__$df$$lam$17$9__$df$$lam$$x$1823383003(ptr %t0)
  %t20 = call ptr @__alloc(i64 8, i32 0)
  %t21 = inttoptr i64 40 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = call ptr @v_$cps$$df$handleErrorIO$4(ptr %t19, ptr %t20)
  ret ptr %t23
}

define internal ptr @v_$cps$$df$handleErrorIO$4(ptr %v_io, ptr %v_$k) {
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
  %t12 = call ptr @v_$apply$$df$handleErrorIO$4(ptr %t6, ptr %t5)
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
  %t50 = call ptr @v_$apply$$df$handleErrorIO$4(ptr %t6, ptr %t49)
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
  %t87 = call ptr @v_$apply$$df$handleErrorIO$4(ptr %t6, ptr %t79)
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

define internal ptr @v_$apply$$df$handleErrorIO$4(ptr %v_$k, ptr %v_$x) {
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

define internal ptr @v_$scc$$apply$$scc$$apply1__$df$$lam$17$9__$df$$lam$$x$1823383003(ptr %v_$args$1) {
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
  switch i64 %t7, label %tco.case.default.8 [ i64 49, label %tco.case.arm.49.9 i64 50, label %tco.case.arm.50.129 ]
tco.case.arm.49.9:
  %t10 = getelementptr ptr, ptr %t4, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  %t12 = getelementptr ptr, ptr %t4, i32 2
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t11, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %tco.case.default.17 [ i64 42, label %tco.case.arm.42.18 i64 43, label %tco.case.arm.43.19 i64 44, label %tco.case.arm.44.34 i64 45, label %tco.case.arm.45.49 i64 46, label %tco.case.arm.46.64 i64 47, label %tco.case.arm.47.79 i64 48, label %tco.case.arm.48.102 ]
tco.case.arm.42.18:
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %t4)
  store ptr %t13, ptr %t2
  br label %tco.exit.1
tco.case.arm.43.19:
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
  %t32 = inttoptr i64 50 to ptr
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
  %t40 = call ptr @v_$cps$$df$handleErrorIO$4(ptr %t13, ptr %t37)
  %t41 = getelementptr ptr, ptr %t4, i32 1
  %t42 = load ptr, ptr %t41
  call void @__free_recursive(ptr %t42)
  %t43 = getelementptr ptr, ptr %t4, i32 2
  %t44 = load ptr, ptr %t43
  call void @__free_recursive(ptr %t44)
  %t47 = inttoptr i64 49 to ptr
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
  %t53 = inttoptr i64 796142685 to ptr
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
  %t62 = inttoptr i64 49 to ptr
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
  %t65 = call ptr @__alloc(i64 24, i32 2)
  %t66 = inttoptr i64 49 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  %t68 = getelementptr ptr, ptr %t11, i32 1
  %t69 = load ptr, ptr %t68
  call void @__inc_ref(ptr %t69)
  %t70 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t69, ptr %t70
  %t71 = getelementptr ptr, ptr %t11, i32 2
  %t72 = load ptr, ptr %t71
  call void @__inc_ref(ptr %t72)
  %t73 = getelementptr ptr, ptr %t4, i32 1
  %t74 = load ptr, ptr %t73
  call void @__free_recursive(ptr %t74)
  %t76 = inttoptr i64 7 to ptr
  %t77 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t76, ptr %t77
  %t75 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t72, ptr %t75
  %t78 = getelementptr ptr, ptr %t65, i32 2
  store ptr %t4, ptr %t78
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t65, ptr %t3
  br label %tco.loop.0
tco.case.arm.47.79:
  %t80 = call ptr @__alloc(i64 24, i32 2)
  %t81 = inttoptr i64 49 to ptr
  %t82 = getelementptr ptr, ptr %t80, i32 0
  store ptr %t81, ptr %t82
  %t83 = getelementptr ptr, ptr %t11, i32 1
  %t84 = load ptr, ptr %t83
  call void @__inc_ref(ptr %t84)
  %t85 = getelementptr ptr, ptr %t80, i32 1
  store ptr %t84, ptr %t85
  %t86 = call ptr @__alloc(i64 16, i32 1)
  %t87 = inttoptr i64 5 to ptr
  %t88 = getelementptr ptr, ptr %t86, i32 0
  store ptr %t87, ptr %t88
  %t89 = call ptr @__alloc(i64 8, i32 0)
  %t90 = inttoptr i64 0 to ptr
  %t91 = getelementptr ptr, ptr %t89, i32 0
  store ptr %t90, ptr %t91
  %t92 = getelementptr ptr, ptr %t86, i32 1
  store ptr %t89, ptr %t92
  %t93 = getelementptr ptr, ptr %t4, i32 1
  %t94 = load ptr, ptr %t93
  call void @__free_recursive(ptr %t94)
  %t95 = getelementptr ptr, ptr %t4, i32 2
  %t96 = load ptr, ptr %t95
  call void @__free_recursive(ptr %t96)
  %t99 = inttoptr i64 7 to ptr
  %t100 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t99, ptr %t100
  call void @__inc_ref(ptr %t13)
  %t97 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t13, ptr %t97
  %t98 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t86, ptr %t98
  %t101 = getelementptr ptr, ptr %t80, i32 2
  store ptr %t4, ptr %t101
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t80, ptr %t3
  br label %tco.loop.0
tco.case.arm.48.102:
  %t103 = getelementptr ptr, ptr %t11, i32 1
  %t104 = load ptr, ptr %t103
  call void @__inc_ref(ptr %t104)
  %t105 = getelementptr ptr, ptr %t13, i32 1
  %t106 = load ptr, ptr %t105
  call void @__inc_ref(ptr %t106)
  %t107 = getelementptr ptr, ptr %t106, i32 0
  %t108 = load ptr, ptr %t107
  %t109 = ptrtoint ptr %t108 to i64
  switch i64 %t109, label %tco.case.default.110 [ i64 1, label %tco.case.arm.1.111 i64 2, label %tco.case.arm.2.120 ]
tco.case.arm.1.111:
  %t112 = getelementptr ptr, ptr %t4, i32 1
  %t113 = load ptr, ptr %t112
  call void @__free_recursive(ptr %t113)
  %t114 = getelementptr ptr, ptr %t4, i32 2
  %t115 = load ptr, ptr %t114
  call void @__free_recursive(ptr %t115)
  %t118 = inttoptr i64 49 to ptr
  %t119 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t118, ptr %t119
  call void @__inc_ref(ptr %t104)
  %t116 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t104, ptr %t116
  %t117 = getelementptr ptr, ptr %t4, i32 2
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t117
  call void @__free_recursive(ptr %t106)
  call void @__free_recursive(ptr %t104)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.2.120:
  %t121 = getelementptr ptr, ptr %t4, i32 1
  %t122 = load ptr, ptr %t121
  call void @__free_recursive(ptr %t122)
  %t123 = getelementptr ptr, ptr %t4, i32 2
  %t124 = load ptr, ptr %t123
  call void @__free_recursive(ptr %t124)
  %t127 = inttoptr i64 49 to ptr
  %t128 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t127, ptr %t128
  call void @__inc_ref(ptr %t104)
  %t125 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t104, ptr %t125
  %t126 = getelementptr ptr, ptr %t4, i32 2
  store ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t126
  call void @__free_recursive(ptr %t106)
  call void @__free_recursive(ptr %t104)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.110:
  unreachable
tco.case.default.17:
  unreachable
tco.case.arm.50.129:
  %t130 = getelementptr ptr, ptr %t4, i32 1
  %t131 = load ptr, ptr %t130
  call void @__inc_ref(ptr %t131)
  %t132 = getelementptr ptr, ptr %t4, i32 2
  %t133 = load ptr, ptr %t132
  call void @__inc_ref(ptr %t133)
  %t134 = getelementptr ptr, ptr %t131, i32 0
  %t135 = load ptr, ptr %t134
  %t136 = ptrtoint ptr %t135 to i64
  switch i64 %t136, label %tco.case.default.137 [ i64 32, label %tco.case.arm.32.138 i64 33, label %tco.case.arm.33.241 i64 34, label %tco.case.arm.34.260 i64 35, label %tco.case.arm.35.279 i64 36, label %tco.case.arm.36.298 i64 37, label %tco.case.arm.37.370 i64 38, label %tco.case.arm.38.387 i64 39, label %tco.case.arm.39.429 ]
tco.case.arm.32.138:
  %t139 = getelementptr ptr, ptr %t131, i32 1
  %t140 = load ptr, ptr %t139
  call void @__inc_ref(ptr %t140)
  %t141 = getelementptr ptr, ptr %t131, i32 2
  %t142 = load ptr, ptr %t141
  call void @__inc_ref(ptr %t142)
  %t143 = getelementptr ptr, ptr %t140, i32 0
  %t144 = load ptr, ptr %t143
  %t145 = ptrtoint ptr %t144 to i64
  switch i64 %t145, label %tco.case.default.146 [ i64 26, label %tco.case.arm.26.147 i64 27, label %tco.case.arm.27.160 i64 28, label %tco.case.arm.28.173 i64 29, label %tco.case.arm.29.186 i64 30, label %tco.case.arm.30.217 i64 31, label %tco.case.arm.31.229 ]
tco.case.arm.26.147:
  %t148 = getelementptr ptr, ptr %t4, i32 1
  %t149 = load ptr, ptr %t148
  call void @__free_recursive(ptr %t149)
  %t158 = inttoptr i64 50 to ptr
  %t159 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t158, ptr %t159
  %t150 = getelementptr ptr, ptr %t140, i32 1
  %t151 = load ptr, ptr %t150
  call void @__inc_ref(ptr %t151)
  %t152 = getelementptr ptr, ptr %t131, i32 1
  %t153 = load ptr, ptr %t152
  call void @__free_recursive(ptr %t153)
  %t155 = inttoptr i64 33 to ptr
  %t156 = getelementptr ptr, ptr %t131, i32 0
  store ptr %t155, ptr %t156
  %t154 = getelementptr ptr, ptr %t131, i32 1
  store ptr %t151, ptr %t154
  %t157 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t131, ptr %t157
  call void @__free_recursive(ptr %t142)
  call void @__free_recursive(ptr %t140)
  call void @__free_recursive(ptr %t133)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.27.160:
  %t161 = getelementptr ptr, ptr %t4, i32 1
  %t162 = load ptr, ptr %t161
  call void @__free_recursive(ptr %t162)
  %t171 = inttoptr i64 50 to ptr
  %t172 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t171, ptr %t172
  %t163 = getelementptr ptr, ptr %t140, i32 1
  %t164 = load ptr, ptr %t163
  call void @__inc_ref(ptr %t164)
  %t165 = getelementptr ptr, ptr %t131, i32 1
  %t166 = load ptr, ptr %t165
  call void @__free_recursive(ptr %t166)
  %t168 = inttoptr i64 34 to ptr
  %t169 = getelementptr ptr, ptr %t131, i32 0
  store ptr %t168, ptr %t169
  %t167 = getelementptr ptr, ptr %t131, i32 1
  store ptr %t164, ptr %t167
  %t170 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t131, ptr %t170
  call void @__free_recursive(ptr %t142)
  call void @__free_recursive(ptr %t140)
  call void @__free_recursive(ptr %t133)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.28.173:
  %t174 = getelementptr ptr, ptr %t4, i32 1
  %t175 = load ptr, ptr %t174
  call void @__free_recursive(ptr %t175)
  %t184 = inttoptr i64 50 to ptr
  %t185 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t184, ptr %t185
  %t176 = getelementptr ptr, ptr %t140, i32 1
  %t177 = load ptr, ptr %t176
  call void @__inc_ref(ptr %t177)
  %t178 = getelementptr ptr, ptr %t131, i32 1
  %t179 = load ptr, ptr %t178
  call void @__free_recursive(ptr %t179)
  %t181 = inttoptr i64 35 to ptr
  %t182 = getelementptr ptr, ptr %t131, i32 0
  store ptr %t181, ptr %t182
  %t180 = getelementptr ptr, ptr %t131, i32 1
  store ptr %t177, ptr %t180
  %t183 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t131, ptr %t183
  call void @__free_recursive(ptr %t142)
  call void @__free_recursive(ptr %t140)
  call void @__free_recursive(ptr %t133)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.29.186:
  %t187 = getelementptr ptr, ptr %t142, i32 0
  %t188 = load ptr, ptr %t187
  %t189 = ptrtoint ptr %t188 to i64
  switch i64 %t189, label %case.default.190 [ i64 3, label %case.arm.3.192 i64 4, label %case.arm.4.200 ]
case.arm.3.192:
  %t194 = call ptr @__alloc(i64 16, i32 1)
  %t195 = inttoptr i64 6 to ptr
  %t196 = getelementptr ptr, ptr %t194, i32 0
  store ptr %t195, ptr %t196
  %t197 = getelementptr ptr, ptr %t142, i32 1
  %t198 = load ptr, ptr %t197
  call void @__inc_ref(ptr %t198)
  %t199 = getelementptr ptr, ptr %t194, i32 1
  store ptr %t198, ptr %t199
  br label %case.end.3.193
case.end.3.193:
  br label %case.join.191
case.arm.4.200:
  %t202 = call ptr @__alloc(i64 16, i32 1)
  %t203 = inttoptr i64 5 to ptr
  %t204 = getelementptr ptr, ptr %t202, i32 0
  store ptr %t203, ptr %t204
  %t205 = getelementptr ptr, ptr %t142, i32 1
  %t206 = load ptr, ptr %t205
  call void @__inc_ref(ptr %t206)
  %t207 = getelementptr ptr, ptr %t202, i32 1
  store ptr %t206, ptr %t207
  br label %case.end.4.201
case.end.4.201:
  br label %case.join.191
case.default.190:
  unreachable
case.join.191:
  %t208 = phi ptr [ %t194, %case.end.3.193 ], [ %t202, %case.end.4.201 ]
  %t209 = getelementptr ptr, ptr %t131, i32 1
  %t210 = load ptr, ptr %t209
  call void @__free_recursive(ptr %t210)
  %t211 = getelementptr ptr, ptr %t131, i32 2
  %t212 = load ptr, ptr %t211
  call void @__free_recursive(ptr %t212)
  %t215 = inttoptr i64 49 to ptr
  %t216 = getelementptr ptr, ptr %t131, i32 0
  store ptr %t215, ptr %t216
  call void @__inc_ref(ptr %t133)
  %t213 = getelementptr ptr, ptr %t131, i32 1
  store ptr %t133, ptr %t213
  %t214 = getelementptr ptr, ptr %t131, i32 2
  store ptr %t208, ptr %t214
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t142)
  call void @__free_recursive(ptr %t140)
  call void @__free_recursive(ptr %t133)
  store ptr %t131, ptr %t3
  br label %tco.loop.0
tco.case.arm.30.217:
  %t218 = call ptr @__alloc(i64 8, i32 0)
  %t219 = inttoptr i64 1 to ptr
  %t220 = getelementptr ptr, ptr %t218, i32 0
  store ptr %t219, ptr %t220
  %t221 = getelementptr ptr, ptr %t131, i32 1
  %t222 = load ptr, ptr %t221
  call void @__free_recursive(ptr %t222)
  %t223 = getelementptr ptr, ptr %t131, i32 2
  %t224 = load ptr, ptr %t223
  call void @__free_recursive(ptr %t224)
  %t227 = inttoptr i64 49 to ptr
  %t228 = getelementptr ptr, ptr %t131, i32 0
  store ptr %t227, ptr %t228
  call void @__inc_ref(ptr %t133)
  %t225 = getelementptr ptr, ptr %t131, i32 1
  store ptr %t133, ptr %t225
  %t226 = getelementptr ptr, ptr %t131, i32 2
  store ptr %t218, ptr %t226
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t142)
  call void @__free_recursive(ptr %t140)
  call void @__free_recursive(ptr %t133)
  store ptr %t131, ptr %t3
  br label %tco.loop.0
tco.case.arm.31.229:
  %t230 = call ptr @__alloc(i64 8, i32 0)
  %t231 = inttoptr i64 2 to ptr
  %t232 = getelementptr ptr, ptr %t230, i32 0
  store ptr %t231, ptr %t232
  %t233 = getelementptr ptr, ptr %t131, i32 1
  %t234 = load ptr, ptr %t233
  call void @__free_recursive(ptr %t234)
  %t235 = getelementptr ptr, ptr %t131, i32 2
  %t236 = load ptr, ptr %t235
  call void @__free_recursive(ptr %t236)
  %t239 = inttoptr i64 49 to ptr
  %t240 = getelementptr ptr, ptr %t131, i32 0
  store ptr %t239, ptr %t240
  call void @__inc_ref(ptr %t133)
  %t237 = getelementptr ptr, ptr %t131, i32 1
  store ptr %t133, ptr %t237
  %t238 = getelementptr ptr, ptr %t131, i32 2
  store ptr %t230, ptr %t238
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t142)
  call void @__free_recursive(ptr %t140)
  call void @__free_recursive(ptr %t133)
  store ptr %t131, ptr %t3
  br label %tco.loop.0
tco.case.default.146:
  unreachable
tco.case.arm.33.241:
  %t242 = getelementptr ptr, ptr %t131, i32 1
  %t243 = load ptr, ptr %t242
  %t244 = getelementptr ptr, ptr %t131, i32 2
  %t245 = load ptr, ptr %t244
  %t246 = call ptr @__alloc(i64 16, i32 1)
  %t247 = inttoptr i64 43 to ptr
  %t248 = getelementptr ptr, ptr %t246, i32 0
  store ptr %t247, ptr %t248
  call void @__inc_ref(ptr %t133)
  %t249 = getelementptr ptr, ptr %t246, i32 1
  store ptr %t133, ptr %t249
  %t250 = getelementptr ptr, ptr %t4, i32 1
  %t251 = load ptr, ptr %t250
  call void @__free_recursive(ptr %t251)
  %t252 = getelementptr ptr, ptr %t4, i32 2
  %t253 = load ptr, ptr %t252
  call void @__free_recursive(ptr %t253)
  %t258 = inttoptr i64 50 to ptr
  %t259 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t258, ptr %t259
  %t254 = inttoptr i64 32 to ptr
  %t255 = getelementptr ptr, ptr %t131, i32 0
  store ptr %t254, ptr %t255
  %t256 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t131, ptr %t256
  %t257 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t246, ptr %t257
  call void @__free_recursive(ptr %t133)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.34.260:
  %t261 = getelementptr ptr, ptr %t131, i32 1
  %t262 = load ptr, ptr %t261
  %t263 = getelementptr ptr, ptr %t131, i32 2
  %t264 = load ptr, ptr %t263
  %t265 = call ptr @__alloc(i64 16, i32 1)
  %t266 = inttoptr i64 44 to ptr
  %t267 = getelementptr ptr, ptr %t265, i32 0
  store ptr %t266, ptr %t267
  call void @__inc_ref(ptr %t133)
  %t268 = getelementptr ptr, ptr %t265, i32 1
  store ptr %t133, ptr %t268
  %t269 = getelementptr ptr, ptr %t4, i32 1
  %t270 = load ptr, ptr %t269
  call void @__free_recursive(ptr %t270)
  %t271 = getelementptr ptr, ptr %t4, i32 2
  %t272 = load ptr, ptr %t271
  call void @__free_recursive(ptr %t272)
  %t277 = inttoptr i64 50 to ptr
  %t278 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t277, ptr %t278
  %t273 = inttoptr i64 32 to ptr
  %t274 = getelementptr ptr, ptr %t131, i32 0
  store ptr %t273, ptr %t274
  %t275 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t131, ptr %t275
  %t276 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t265, ptr %t276
  call void @__free_recursive(ptr %t133)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.35.279:
  %t280 = getelementptr ptr, ptr %t131, i32 1
  %t281 = load ptr, ptr %t280
  %t282 = getelementptr ptr, ptr %t131, i32 2
  %t283 = load ptr, ptr %t282
  %t284 = call ptr @__alloc(i64 16, i32 1)
  %t285 = inttoptr i64 45 to ptr
  %t286 = getelementptr ptr, ptr %t284, i32 0
  store ptr %t285, ptr %t286
  call void @__inc_ref(ptr %t133)
  %t287 = getelementptr ptr, ptr %t284, i32 1
  store ptr %t133, ptr %t287
  %t288 = getelementptr ptr, ptr %t4, i32 1
  %t289 = load ptr, ptr %t288
  call void @__free_recursive(ptr %t289)
  %t290 = getelementptr ptr, ptr %t4, i32 2
  %t291 = load ptr, ptr %t290
  call void @__free_recursive(ptr %t291)
  %t296 = inttoptr i64 50 to ptr
  %t297 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t296, ptr %t297
  %t292 = inttoptr i64 32 to ptr
  %t293 = getelementptr ptr, ptr %t131, i32 0
  store ptr %t292, ptr %t293
  %t294 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t131, ptr %t294
  %t295 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t284, ptr %t295
  call void @__free_recursive(ptr %t133)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.36.298:
  %t299 = getelementptr ptr, ptr %t131, i32 1
  %t300 = load ptr, ptr %t299
  call void @__inc_ref(ptr %t300)
  %t301 = getelementptr ptr, ptr %t300, i32 0
  %t302 = load ptr, ptr %t301
  %t303 = ptrtoint ptr %t302 to i64
  switch i64 %t303, label %tco.case.default.304 [ i64 5, label %tco.case.arm.5.305 i64 6, label %tco.case.arm.6.318 i64 7, label %tco.case.arm.7.327 i64 8, label %tco.case.arm.8.350 ]
tco.case.arm.5.305:
  %t306 = getelementptr ptr, ptr %t4, i32 1
  %t307 = load ptr, ptr %t306
  call void @__free_recursive(ptr %t307)
  %t316 = inttoptr i64 50 to ptr
  %t317 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t316, ptr %t317
  %t308 = getelementptr ptr, ptr %t300, i32 1
  %t309 = load ptr, ptr %t308
  call void @__inc_ref(ptr %t309)
  %t310 = getelementptr ptr, ptr %t131, i32 1
  %t311 = load ptr, ptr %t310
  call void @__free_recursive(ptr %t311)
  %t313 = inttoptr i64 39 to ptr
  %t314 = getelementptr ptr, ptr %t131, i32 0
  store ptr %t313, ptr %t314
  %t312 = getelementptr ptr, ptr %t131, i32 1
  store ptr %t309, ptr %t312
  %t315 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t131, ptr %t315
  call void @__free_recursive(ptr %t300)
  call void @__free_recursive(ptr %t133)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.6.318:
  %t319 = getelementptr ptr, ptr %t4, i32 1
  %t320 = load ptr, ptr %t319
  call void @__free_recursive(ptr %t320)
  %t321 = getelementptr ptr, ptr %t4, i32 2
  %t322 = load ptr, ptr %t321
  call void @__free_recursive(ptr %t322)
  %t325 = inttoptr i64 49 to ptr
  %t326 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t325, ptr %t326
  call void @__inc_ref(ptr %t133)
  %t323 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t133, ptr %t323
  call void @__inc_ref(ptr %t300)
  %t324 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t300, ptr %t324
  call void @__free_recursive(ptr %t131)
  call void @__free_recursive(ptr %t300)
  call void @__free_recursive(ptr %t133)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.7.327:
  %t328 = call ptr @__alloc(i64 24, i32 2)
  %t329 = inttoptr i64 50 to ptr
  %t330 = getelementptr ptr, ptr %t328, i32 0
  store ptr %t329, ptr %t330
  %t331 = getelementptr ptr, ptr %t300, i32 2
  %t332 = load ptr, ptr %t331
  call void @__inc_ref(ptr %t332)
  %t333 = getelementptr ptr, ptr %t131, i32 1
  %t334 = load ptr, ptr %t333
  call void @__free_recursive(ptr %t334)
  %t336 = inttoptr i64 36 to ptr
  %t337 = getelementptr ptr, ptr %t131, i32 0
  store ptr %t336, ptr %t337
  %t335 = getelementptr ptr, ptr %t131, i32 1
  store ptr %t332, ptr %t335
  %t338 = getelementptr ptr, ptr %t328, i32 1
  store ptr %t131, ptr %t338
  %t339 = getelementptr ptr, ptr %t300, i32 1
  %t340 = load ptr, ptr %t339
  call void @__inc_ref(ptr %t340)
  %t341 = getelementptr ptr, ptr %t4, i32 1
  %t342 = load ptr, ptr %t341
  call void @__free_recursive(ptr %t342)
  %t343 = getelementptr ptr, ptr %t4, i32 2
  %t344 = load ptr, ptr %t343
  call void @__free_recursive(ptr %t344)
  %t347 = inttoptr i64 46 to ptr
  %t348 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t347, ptr %t348
  call void @__inc_ref(ptr %t133)
  %t345 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t133, ptr %t345
  %t346 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t340, ptr %t346
  %t349 = getelementptr ptr, ptr %t328, i32 2
  store ptr %t4, ptr %t349
  call void @__free_recursive(ptr %t300)
  call void @__free_recursive(ptr %t133)
  store ptr %t328, ptr %t3
  br label %tco.loop.0
tco.case.arm.8.350:
  %t351 = getelementptr ptr, ptr %t4, i32 1
  %t352 = load ptr, ptr %t351
  call void @__free_recursive(ptr %t352)
  %t353 = getelementptr ptr, ptr %t4, i32 2
  %t354 = load ptr, ptr %t353
  call void @__free_recursive(ptr %t354)
  %t368 = inttoptr i64 49 to ptr
  %t369 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t368, ptr %t369
  call void @__inc_ref(ptr %t133)
  %t355 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t133, ptr %t355
  %t356 = call ptr @__alloc(i64 16, i32 1)
  %t357 = inttoptr i64 8 to ptr
  %t358 = getelementptr ptr, ptr %t356, i32 0
  store ptr %t357, ptr %t358
  %t359 = getelementptr ptr, ptr %t300, i32 1
  %t360 = load ptr, ptr %t359
  call void @__inc_ref(ptr %t360)
  %t361 = getelementptr ptr, ptr %t131, i32 1
  %t362 = load ptr, ptr %t361
  call void @__free_recursive(ptr %t362)
  %t364 = inttoptr i64 26 to ptr
  %t365 = getelementptr ptr, ptr %t131, i32 0
  store ptr %t364, ptr %t365
  %t363 = getelementptr ptr, ptr %t131, i32 1
  store ptr %t360, ptr %t363
  %t366 = getelementptr ptr, ptr %t356, i32 1
  store ptr %t131, ptr %t366
  %t367 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t356, ptr %t367
  call void @__free_recursive(ptr %t300)
  call void @__free_recursive(ptr %t133)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.304:
  unreachable
tco.case.arm.37.370:
  %t371 = getelementptr ptr, ptr %t131, i32 1
  %t372 = load ptr, ptr %t371
  %t373 = call ptr @__alloc(i64 16, i32 1)
  %t374 = inttoptr i64 47 to ptr
  %t375 = getelementptr ptr, ptr %t373, i32 0
  store ptr %t374, ptr %t375
  call void @__inc_ref(ptr %t133)
  %t376 = getelementptr ptr, ptr %t373, i32 1
  store ptr %t133, ptr %t376
  %t377 = getelementptr ptr, ptr %t4, i32 1
  %t378 = load ptr, ptr %t377
  call void @__free_recursive(ptr %t378)
  %t379 = getelementptr ptr, ptr %t4, i32 2
  %t380 = load ptr, ptr %t379
  call void @__free_recursive(ptr %t380)
  %t385 = inttoptr i64 50 to ptr
  %t386 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t385, ptr %t386
  %t381 = inttoptr i64 38 to ptr
  %t382 = getelementptr ptr, ptr %t131, i32 0
  store ptr %t381, ptr %t382
  %t383 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t131, ptr %t383
  %t384 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t373, ptr %t384
  call void @__free_recursive(ptr %t133)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.38.387:
  %t388 = getelementptr ptr, ptr %t131, i32 1
  %t389 = load ptr, ptr %t388
  call void @__inc_ref(ptr %t389)
  %t390 = getelementptr ptr, ptr %t389, i32 0
  %t391 = load ptr, ptr %t390
  %t392 = ptrtoint ptr %t391 to i64
  switch i64 %t392, label %tco.case.default.393 [ i64 25, label %tco.case.arm.25.394 ]
tco.case.arm.25.394:
  %t395 = getelementptr ptr, ptr %t389, i32 1
  %t396 = load ptr, ptr %t395
  call void @__inc_ref(ptr %t396)
  %t397 = call ptr @__alloc(i64 24, i32 2)
  %t398 = inttoptr i64 50 to ptr
  %t399 = getelementptr ptr, ptr %t397, i32 0
  store ptr %t398, ptr %t399
  %t400 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t400
  %t401 = getelementptr ptr, ptr %t4, i32 1
  %t402 = load ptr, ptr %t401
  call void @__free_recursive(ptr %t402)
  %t403 = getelementptr ptr, ptr %t4, i32 2
  %t404 = load ptr, ptr %t403
  call void @__free_recursive(ptr %t404)
  %t407 = inttoptr i64 32 to ptr
  %t408 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t407, ptr %t408
  call void @__inc_ref(ptr %t396)
  %t405 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t396, ptr %t405
  %t406 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t400, ptr %t406
  %t409 = getelementptr ptr, ptr %t397, i32 1
  store ptr %t4, ptr %t409
  %t415 = getelementptr i8, ptr %t389, i64 -8
  %t416 = load i32, ptr %t415
  %t417 = icmp eq i32 %t416, 1
  br i1 %t417, label %reuse.in_place.418, label %reuse.copy.419
reuse.in_place.418:
  %t410 = getelementptr ptr, ptr %t389, i32 1
  %t411 = load ptr, ptr %t410
  call void @__free_recursive(ptr %t411)
  %t413 = inttoptr i64 48 to ptr
  %t414 = getelementptr ptr, ptr %t389, i32 0
  store ptr %t413, ptr %t414
  call void @__inc_ref(ptr %t133)
  %t412 = getelementptr ptr, ptr %t389, i32 1
  store ptr %t133, ptr %t412
  br label %reuse.in_place.end.421
reuse.in_place.end.421:
  br label %reuse.join.420
reuse.copy.419:
  %t423 = call ptr @__alloc(i64 16, i32 1)
  %t424 = inttoptr i64 48 to ptr
  %t425 = getelementptr ptr, ptr %t423, i32 0
  store ptr %t424, ptr %t425
  call void @__inc_ref(ptr %t133)
  %t426 = getelementptr ptr, ptr %t423, i32 1
  store ptr %t133, ptr %t426
  call void @__free_recursive(ptr %t389)
  br label %reuse.copy.end.422
reuse.copy.end.422:
  br label %reuse.join.420
reuse.join.420:
  %t427 = phi ptr [ %t389, %reuse.in_place.end.421 ], [ %t423, %reuse.copy.end.422 ]
  %t428 = getelementptr ptr, ptr %t397, i32 2
  store ptr %t427, ptr %t428
  call void @__free_recursive(ptr %t396)
  call void @__free_recursive(ptr %t131)
  call void @__free_recursive(ptr %t133)
  store ptr %t397, ptr %t3
  br label %tco.loop.0
tco.case.default.393:
  unreachable
tco.case.arm.39.429:
  %t430 = getelementptr ptr, ptr %t131, i32 1
  %t431 = load ptr, ptr %t430
  call void @__inc_ref(ptr %t431)
  %t432 = getelementptr ptr, ptr %t4, i32 1
  %t433 = load ptr, ptr %t432
  call void @__free_recursive(ptr %t433)
  %t484 = inttoptr i64 50 to ptr
  %t485 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t484, ptr %t485
  %t434 = call ptr @__alloc(i64 16, i32 1)
  %t435 = inttoptr i64 37 to ptr
  %t436 = getelementptr ptr, ptr %t434, i32 0
  store ptr %t435, ptr %t436
  %t437 = getelementptr ptr, ptr %t431, i32 0
  %t438 = load ptr, ptr %t437
  %t439 = ptrtoint ptr %t438 to i64
  switch i64 %t439, label %case.default.440 [ i64 13, label %case.arm.13.442 i64 14, label %case.arm.14.467 ]
case.arm.13.442:
  %t444 = call ptr @__alloc(i64 16, i32 1)
  %t445 = inttoptr i64 25 to ptr
  %t446 = getelementptr ptr, ptr %t444, i32 0
  store ptr %t445, ptr %t446
  %t447 = getelementptr ptr, ptr %t131, i32 1
  %t448 = load ptr, ptr %t447
  call void @__free_recursive(ptr %t448)
  %t464 = inttoptr i64 28 to ptr
  %t465 = getelementptr ptr, ptr %t131, i32 0
  store ptr %t464, ptr %t465
  %t451 = getelementptr i8, ptr %t431, i64 -8
  %t452 = load i32, ptr %t451
  %t453 = icmp eq i32 %t452, 1
  br i1 %t453, label %reuse.in_place.454, label %reuse.copy.455
reuse.in_place.454:
  %t449 = inttoptr i64 30 to ptr
  %t450 = getelementptr ptr, ptr %t431, i32 0
  store ptr %t449, ptr %t450
  br label %reuse.in_place.end.457
reuse.in_place.end.457:
  br label %reuse.join.456
reuse.copy.455:
  %t459 = call ptr @__alloc(i64 8, i32 0)
  %t460 = inttoptr i64 30 to ptr
  %t461 = getelementptr ptr, ptr %t459, i32 0
  store ptr %t460, ptr %t461
  call void @__free_recursive(ptr %t431)
  br label %reuse.copy.end.458
reuse.copy.end.458:
  br label %reuse.join.456
reuse.join.456:
  %t462 = phi ptr [ %t431, %reuse.in_place.end.457 ], [ %t459, %reuse.copy.end.458 ]
  %t463 = getelementptr ptr, ptr %t131, i32 1
  store ptr %t462, ptr %t463
  %t466 = getelementptr ptr, ptr %t444, i32 1
  store ptr %t131, ptr %t466
  br label %case.end.13.443
case.end.13.443:
  br label %case.join.441
case.arm.14.467:
  %t469 = call ptr @__alloc(i64 16, i32 1)
  %t470 = inttoptr i64 25 to ptr
  %t471 = getelementptr ptr, ptr %t469, i32 0
  store ptr %t470, ptr %t471
  %t472 = call ptr @__alloc(i64 8, i32 0)
  %t473 = inttoptr i64 31 to ptr
  %t474 = getelementptr ptr, ptr %t472, i32 0
  store ptr %t473, ptr %t474
  %t475 = getelementptr ptr, ptr %t131, i32 1
  %t476 = load ptr, ptr %t475
  call void @__free_recursive(ptr %t476)
  %t478 = inttoptr i64 28 to ptr
  %t479 = getelementptr ptr, ptr %t131, i32 0
  store ptr %t478, ptr %t479
  %t477 = getelementptr ptr, ptr %t131, i32 1
  store ptr %t472, ptr %t477
  %t480 = getelementptr ptr, ptr %t469, i32 1
  store ptr %t131, ptr %t480
  call void @__free_recursive(ptr %t431)
  br label %case.end.14.468
case.end.14.468:
  br label %case.join.441
case.default.440:
  unreachable
case.join.441:
  %t481 = phi ptr [ %t444, %case.end.13.443 ], [ %t469, %case.end.14.468 ]
  %t482 = getelementptr ptr, ptr %t434, i32 1
  store ptr %t481, ptr %t482
  %t483 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t434, ptr %t483
  call void @__free_recursive(ptr %t133)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.137:
  unreachable
tco.case.default.8:
  unreachable
tco.exit.1:
  %t486 = load ptr, ptr %t2
  ret ptr %t486
}

define i32 @main(i32 %argc, ptr %argv) {
  %argc64 = sext i32 %argc to i64
  store i64 %argc64, ptr @.cli_argc
  store ptr %argv, ptr @.cli_argv
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
