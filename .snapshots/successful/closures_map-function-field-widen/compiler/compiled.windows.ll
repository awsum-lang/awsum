; External C declarations
declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare ptr @memcpy(ptr, ptr, i64)
declare i64 @write(i32, ptr, i64)
declare i64 @strlen(ptr)

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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [24 x i8]} { i32 0, i32 0, i32 0, i32 24, i32 24, [24 x i8] c"UNPAIRED_UTF16_SURROGATE" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"bool" }

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
  %t21 = inttoptr i64 47 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = call ptr @__alloc(i64 24, i32 2)
  %t24 = inttoptr i64 30 to ptr
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
  %t32 = inttoptr i64 40 to ptr
  %t33 = getelementptr ptr, ptr %t31, i32 0
  store ptr %t32, ptr %t33
  %t34 = getelementptr ptr, ptr %t20, i32 2
  store ptr %t31, ptr %t34
  %t35 = call ptr @v_$scc$$apply$$scc$$apply1__$df$$lam$13$1__$df$$lam$$x$1360977481(ptr %t20)
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
  %t1 = inttoptr i64 47 to ptr
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
  %t16 = inttoptr i64 40 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t15, ptr %t18
  %t19 = call ptr @v_$scc$$apply$$scc$$apply1__$df$$lam$13$1__$df$$lam$$x$1360977481(ptr %t0)
  %t20 = call ptr @__alloc(i64 8, i32 0)
  %t21 = inttoptr i64 38 to ptr
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
  %t60 = inttoptr i64 39 to ptr
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
  %t71 = inttoptr i64 39 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 38, label %tco.case.arm.38.11 i64 39, label %tco.case.arm.39.12 ]
tco.case.arm.38.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.39.12:
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

define internal ptr @v_$scc$$apply$$scc$$apply1__$df$$lam$13$1__$df$$lam$$x$1360977481(ptr %v_$args$1) {
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
  switch i64 %t7, label %tco.case.default.8 [ i64 46, label %tco.case.arm.46.9 i64 47, label %tco.case.arm.47.102 ]
tco.case.arm.46.9:
  %t10 = getelementptr ptr, ptr %t4, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  %t12 = getelementptr ptr, ptr %t4, i32 2
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t11, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %tco.case.default.17 [ i64 40, label %tco.case.arm.40.18 i64 41, label %tco.case.arm.41.19 i64 42, label %tco.case.arm.42.34 i64 43, label %tco.case.arm.43.49 i64 44, label %tco.case.arm.44.64 i64 45, label %tco.case.arm.45.79 ]
tco.case.arm.40.18:
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %t4)
  store ptr %t13, ptr %t2
  br label %tco.exit.1
tco.case.arm.41.19:
  %t20 = getelementptr ptr, ptr %t11, i32 1
  %t21 = load ptr, ptr %t20
  call void @__inc_ref(ptr %t21)
  %t22 = call ptr @__alloc(i64 16, i32 1)
  %t23 = inttoptr i64 796142685 to ptr
  %t24 = getelementptr ptr, ptr %t22, i32 0
  store ptr %t23, ptr %t24
  call void @__inc_ref(ptr %t13)
  %t25 = getelementptr ptr, ptr %t22, i32 1
  store ptr %t13, ptr %t25
  %t26 = getelementptr ptr, ptr %t4, i32 1
  %t27 = load ptr, ptr %t26
  call void @__free_recursive(ptr %t27)
  %t28 = getelementptr ptr, ptr %t4, i32 2
  %t29 = load ptr, ptr %t28
  call void @__free_recursive(ptr %t29)
  %t32 = inttoptr i64 46 to ptr
  %t33 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t32, ptr %t33
  %t30 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t21, ptr %t30
  %t31 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t22, ptr %t31
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.42.34:
  %t35 = call ptr @__alloc(i64 16, i32 1)
  %t36 = inttoptr i64 34 to ptr
  %t37 = getelementptr ptr, ptr %t35, i32 0
  store ptr %t36, ptr %t37
  call void @__inc_ref(ptr %t13)
  %t38 = getelementptr ptr, ptr %t35, i32 1
  store ptr %t13, ptr %t38
  %t39 = getelementptr ptr, ptr %t11, i32 1
  %t40 = load ptr, ptr %t39
  call void @__inc_ref(ptr %t40)
  %t41 = getelementptr ptr, ptr %t4, i32 1
  %t42 = load ptr, ptr %t41
  call void @__free_recursive(ptr %t42)
  %t43 = getelementptr ptr, ptr %t4, i32 2
  %t44 = load ptr, ptr %t43
  call void @__free_recursive(ptr %t44)
  %t47 = inttoptr i64 47 to ptr
  %t48 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t47, ptr %t48
  %t45 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t35, ptr %t45
  %t46 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t40, ptr %t46
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.43.49:
  %t50 = getelementptr ptr, ptr %t11, i32 1
  %t51 = load ptr, ptr %t50
  call void @__inc_ref(ptr %t51)
  call void @__inc_ref(ptr %t13)
  %t52 = call ptr @__alloc(i64 8, i32 0)
  %t53 = inttoptr i64 38 to ptr
  %t54 = getelementptr ptr, ptr %t52, i32 0
  store ptr %t53, ptr %t54
  %t55 = call ptr @v_$cps$$df$handleErrorIO$2(ptr %t13, ptr %t52)
  %t56 = getelementptr ptr, ptr %t4, i32 1
  %t57 = load ptr, ptr %t56
  call void @__free_recursive(ptr %t57)
  %t58 = getelementptr ptr, ptr %t4, i32 2
  %t59 = load ptr, ptr %t58
  call void @__free_recursive(ptr %t59)
  %t62 = inttoptr i64 46 to ptr
  %t63 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t62, ptr %t63
  %t60 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t51, ptr %t60
  %t61 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t55, ptr %t61
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.44.64:
  %t65 = call ptr @__alloc(i64 24, i32 2)
  %t66 = inttoptr i64 46 to ptr
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
tco.case.arm.45.79:
  %t80 = call ptr @__alloc(i64 24, i32 2)
  %t81 = inttoptr i64 46 to ptr
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
  %t97 = getelementptr ptr, ptr %t4, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t97
  %t98 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t86, ptr %t98
  %t101 = getelementptr ptr, ptr %t80, i32 2
  store ptr %t4, ptr %t101
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t80, ptr %t3
  br label %tco.loop.0
tco.case.default.17:
  unreachable
tco.case.arm.47.102:
  %t103 = getelementptr ptr, ptr %t4, i32 1
  %t104 = load ptr, ptr %t103
  call void @__inc_ref(ptr %t104)
  %t105 = getelementptr ptr, ptr %t4, i32 2
  %t106 = load ptr, ptr %t105
  call void @__inc_ref(ptr %t106)
  %t107 = getelementptr ptr, ptr %t104, i32 0
  %t108 = load ptr, ptr %t107
  %t109 = ptrtoint ptr %t108 to i64
  switch i64 %t109, label %tco.case.default.110 [ i64 30, label %tco.case.arm.30.111 i64 31, label %tco.case.arm.31.201 i64 32, label %tco.case.arm.32.220 i64 33, label %tco.case.arm.33.239 i64 34, label %tco.case.arm.34.258 i64 35, label %tco.case.arm.35.330 i64 36, label %tco.case.arm.36.352 i64 37, label %tco.case.arm.37.369 ]
tco.case.arm.30.111:
  %t112 = getelementptr ptr, ptr %t104, i32 1
  %t113 = load ptr, ptr %t112
  call void @__inc_ref(ptr %t113)
  %t114 = getelementptr ptr, ptr %t104, i32 2
  %t115 = load ptr, ptr %t114
  call void @__inc_ref(ptr %t115)
  %t116 = getelementptr ptr, ptr %t113, i32 0
  %t117 = load ptr, ptr %t116
  %t118 = ptrtoint ptr %t117 to i64
  switch i64 %t118, label %tco.case.default.119 [ i64 25, label %tco.case.arm.25.120 i64 26, label %tco.case.arm.26.133 i64 27, label %tco.case.arm.27.146 i64 28, label %tco.case.arm.28.159 i64 29, label %tco.case.arm.29.190 ]
tco.case.arm.25.120:
  %t121 = getelementptr ptr, ptr %t4, i32 1
  %t122 = load ptr, ptr %t121
  call void @__free_recursive(ptr %t122)
  %t131 = inttoptr i64 47 to ptr
  %t132 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t131, ptr %t132
  %t123 = getelementptr ptr, ptr %t113, i32 1
  %t124 = load ptr, ptr %t123
  call void @__inc_ref(ptr %t124)
  %t125 = getelementptr ptr, ptr %t104, i32 1
  %t126 = load ptr, ptr %t125
  call void @__free_recursive(ptr %t126)
  %t128 = inttoptr i64 31 to ptr
  %t129 = getelementptr ptr, ptr %t104, i32 0
  store ptr %t128, ptr %t129
  %t127 = getelementptr ptr, ptr %t104, i32 1
  store ptr %t124, ptr %t127
  %t130 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t104, ptr %t130
  call void @__free_recursive(ptr %t115)
  call void @__free_recursive(ptr %t113)
  call void @__free_recursive(ptr %t106)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.26.133:
  %t134 = getelementptr ptr, ptr %t4, i32 1
  %t135 = load ptr, ptr %t134
  call void @__free_recursive(ptr %t135)
  %t144 = inttoptr i64 47 to ptr
  %t145 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t144, ptr %t145
  %t136 = getelementptr ptr, ptr %t113, i32 1
  %t137 = load ptr, ptr %t136
  call void @__inc_ref(ptr %t137)
  %t138 = getelementptr ptr, ptr %t104, i32 1
  %t139 = load ptr, ptr %t138
  call void @__free_recursive(ptr %t139)
  %t141 = inttoptr i64 32 to ptr
  %t142 = getelementptr ptr, ptr %t104, i32 0
  store ptr %t141, ptr %t142
  %t140 = getelementptr ptr, ptr %t104, i32 1
  store ptr %t137, ptr %t140
  %t143 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t104, ptr %t143
  call void @__free_recursive(ptr %t115)
  call void @__free_recursive(ptr %t113)
  call void @__free_recursive(ptr %t106)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.27.146:
  %t147 = getelementptr ptr, ptr %t4, i32 1
  %t148 = load ptr, ptr %t147
  call void @__free_recursive(ptr %t148)
  %t157 = inttoptr i64 47 to ptr
  %t158 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t157, ptr %t158
  %t149 = getelementptr ptr, ptr %t113, i32 1
  %t150 = load ptr, ptr %t149
  call void @__inc_ref(ptr %t150)
  %t151 = getelementptr ptr, ptr %t104, i32 1
  %t152 = load ptr, ptr %t151
  call void @__free_recursive(ptr %t152)
  %t154 = inttoptr i64 33 to ptr
  %t155 = getelementptr ptr, ptr %t104, i32 0
  store ptr %t154, ptr %t155
  %t153 = getelementptr ptr, ptr %t104, i32 1
  store ptr %t150, ptr %t153
  %t156 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t104, ptr %t156
  call void @__free_recursive(ptr %t115)
  call void @__free_recursive(ptr %t113)
  call void @__free_recursive(ptr %t106)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.28.159:
  %t160 = getelementptr ptr, ptr %t115, i32 0
  %t161 = load ptr, ptr %t160
  %t162 = ptrtoint ptr %t161 to i64
  switch i64 %t162, label %case.default.163 [ i64 3, label %case.arm.3.165 i64 4, label %case.arm.4.173 ]
case.arm.3.165:
  %t167 = call ptr @__alloc(i64 16, i32 1)
  %t168 = inttoptr i64 6 to ptr
  %t169 = getelementptr ptr, ptr %t167, i32 0
  store ptr %t168, ptr %t169
  %t170 = getelementptr ptr, ptr %t115, i32 1
  %t171 = load ptr, ptr %t170
  call void @__inc_ref(ptr %t171)
  %t172 = getelementptr ptr, ptr %t167, i32 1
  store ptr %t171, ptr %t172
  br label %case.end.3.166
case.end.3.166:
  br label %case.join.164
case.arm.4.173:
  %t175 = call ptr @__alloc(i64 16, i32 1)
  %t176 = inttoptr i64 5 to ptr
  %t177 = getelementptr ptr, ptr %t175, i32 0
  store ptr %t176, ptr %t177
  %t178 = getelementptr ptr, ptr %t115, i32 1
  %t179 = load ptr, ptr %t178
  call void @__inc_ref(ptr %t179)
  %t180 = getelementptr ptr, ptr %t175, i32 1
  store ptr %t179, ptr %t180
  br label %case.end.4.174
case.end.4.174:
  br label %case.join.164
case.default.163:
  unreachable
case.join.164:
  %t181 = phi ptr [ %t167, %case.end.3.166 ], [ %t175, %case.end.4.174 ]
  %t182 = getelementptr ptr, ptr %t104, i32 1
  %t183 = load ptr, ptr %t182
  call void @__free_recursive(ptr %t183)
  %t184 = getelementptr ptr, ptr %t104, i32 2
  %t185 = load ptr, ptr %t184
  call void @__free_recursive(ptr %t185)
  %t188 = inttoptr i64 46 to ptr
  %t189 = getelementptr ptr, ptr %t104, i32 0
  store ptr %t188, ptr %t189
  call void @__inc_ref(ptr %t106)
  %t186 = getelementptr ptr, ptr %t104, i32 1
  store ptr %t106, ptr %t186
  %t187 = getelementptr ptr, ptr %t104, i32 2
  store ptr %t181, ptr %t187
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t115)
  call void @__free_recursive(ptr %t113)
  call void @__free_recursive(ptr %t106)
  store ptr %t104, ptr %t3
  br label %tco.loop.0
tco.case.arm.29.190:
  %t191 = getelementptr ptr, ptr %t113, i32 1
  %t192 = load ptr, ptr %t191
  call void @__inc_ref(ptr %t192)
  %t193 = getelementptr ptr, ptr %t104, i32 1
  %t194 = load ptr, ptr %t193
  call void @__free_recursive(ptr %t194)
  %t195 = getelementptr ptr, ptr %t104, i32 2
  %t196 = load ptr, ptr %t195
  call void @__free_recursive(ptr %t196)
  %t199 = inttoptr i64 46 to ptr
  %t200 = getelementptr ptr, ptr %t104, i32 0
  store ptr %t199, ptr %t200
  call void @__inc_ref(ptr %t106)
  %t197 = getelementptr ptr, ptr %t104, i32 1
  store ptr %t106, ptr %t197
  %t198 = getelementptr ptr, ptr %t104, i32 2
  store ptr %t192, ptr %t198
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t115)
  call void @__free_recursive(ptr %t113)
  call void @__free_recursive(ptr %t106)
  store ptr %t104, ptr %t3
  br label %tco.loop.0
tco.case.default.119:
  unreachable
tco.case.arm.31.201:
  %t202 = getelementptr ptr, ptr %t104, i32 1
  %t203 = load ptr, ptr %t202
  %t204 = getelementptr ptr, ptr %t104, i32 2
  %t205 = load ptr, ptr %t204
  %t206 = call ptr @__alloc(i64 16, i32 1)
  %t207 = inttoptr i64 41 to ptr
  %t208 = getelementptr ptr, ptr %t206, i32 0
  store ptr %t207, ptr %t208
  call void @__inc_ref(ptr %t106)
  %t209 = getelementptr ptr, ptr %t206, i32 1
  store ptr %t106, ptr %t209
  %t210 = getelementptr ptr, ptr %t4, i32 1
  %t211 = load ptr, ptr %t210
  call void @__free_recursive(ptr %t211)
  %t212 = getelementptr ptr, ptr %t4, i32 2
  %t213 = load ptr, ptr %t212
  call void @__free_recursive(ptr %t213)
  %t218 = inttoptr i64 47 to ptr
  %t219 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t218, ptr %t219
  %t214 = inttoptr i64 30 to ptr
  %t215 = getelementptr ptr, ptr %t104, i32 0
  store ptr %t214, ptr %t215
  %t216 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t104, ptr %t216
  %t217 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t206, ptr %t217
  call void @__free_recursive(ptr %t106)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.32.220:
  %t221 = getelementptr ptr, ptr %t104, i32 1
  %t222 = load ptr, ptr %t221
  %t223 = getelementptr ptr, ptr %t104, i32 2
  %t224 = load ptr, ptr %t223
  %t225 = call ptr @__alloc(i64 16, i32 1)
  %t226 = inttoptr i64 42 to ptr
  %t227 = getelementptr ptr, ptr %t225, i32 0
  store ptr %t226, ptr %t227
  call void @__inc_ref(ptr %t106)
  %t228 = getelementptr ptr, ptr %t225, i32 1
  store ptr %t106, ptr %t228
  %t229 = getelementptr ptr, ptr %t4, i32 1
  %t230 = load ptr, ptr %t229
  call void @__free_recursive(ptr %t230)
  %t231 = getelementptr ptr, ptr %t4, i32 2
  %t232 = load ptr, ptr %t231
  call void @__free_recursive(ptr %t232)
  %t237 = inttoptr i64 47 to ptr
  %t238 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t237, ptr %t238
  %t233 = inttoptr i64 30 to ptr
  %t234 = getelementptr ptr, ptr %t104, i32 0
  store ptr %t233, ptr %t234
  %t235 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t104, ptr %t235
  %t236 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t225, ptr %t236
  call void @__free_recursive(ptr %t106)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.33.239:
  %t240 = getelementptr ptr, ptr %t104, i32 1
  %t241 = load ptr, ptr %t240
  %t242 = getelementptr ptr, ptr %t104, i32 2
  %t243 = load ptr, ptr %t242
  %t244 = call ptr @__alloc(i64 16, i32 1)
  %t245 = inttoptr i64 43 to ptr
  %t246 = getelementptr ptr, ptr %t244, i32 0
  store ptr %t245, ptr %t246
  call void @__inc_ref(ptr %t106)
  %t247 = getelementptr ptr, ptr %t244, i32 1
  store ptr %t106, ptr %t247
  %t248 = getelementptr ptr, ptr %t4, i32 1
  %t249 = load ptr, ptr %t248
  call void @__free_recursive(ptr %t249)
  %t250 = getelementptr ptr, ptr %t4, i32 2
  %t251 = load ptr, ptr %t250
  call void @__free_recursive(ptr %t251)
  %t256 = inttoptr i64 47 to ptr
  %t257 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t256, ptr %t257
  %t252 = inttoptr i64 30 to ptr
  %t253 = getelementptr ptr, ptr %t104, i32 0
  store ptr %t252, ptr %t253
  %t254 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t104, ptr %t254
  %t255 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t244, ptr %t255
  call void @__free_recursive(ptr %t106)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.34.258:
  %t259 = getelementptr ptr, ptr %t104, i32 1
  %t260 = load ptr, ptr %t259
  call void @__inc_ref(ptr %t260)
  %t261 = getelementptr ptr, ptr %t260, i32 0
  %t262 = load ptr, ptr %t261
  %t263 = ptrtoint ptr %t262 to i64
  switch i64 %t263, label %tco.case.default.264 [ i64 5, label %tco.case.arm.5.265 i64 6, label %tco.case.arm.6.278 i64 7, label %tco.case.arm.7.287 i64 8, label %tco.case.arm.8.310 ]
tco.case.arm.5.265:
  %t266 = getelementptr ptr, ptr %t4, i32 1
  %t267 = load ptr, ptr %t266
  call void @__free_recursive(ptr %t267)
  %t276 = inttoptr i64 47 to ptr
  %t277 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t276, ptr %t277
  %t268 = getelementptr ptr, ptr %t260, i32 1
  %t269 = load ptr, ptr %t268
  call void @__inc_ref(ptr %t269)
  %t270 = getelementptr ptr, ptr %t104, i32 1
  %t271 = load ptr, ptr %t270
  call void @__free_recursive(ptr %t271)
  %t273 = inttoptr i64 37 to ptr
  %t274 = getelementptr ptr, ptr %t104, i32 0
  store ptr %t273, ptr %t274
  %t272 = getelementptr ptr, ptr %t104, i32 1
  store ptr %t269, ptr %t272
  %t275 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t104, ptr %t275
  call void @__free_recursive(ptr %t260)
  call void @__free_recursive(ptr %t106)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.6.278:
  %t279 = getelementptr ptr, ptr %t4, i32 1
  %t280 = load ptr, ptr %t279
  call void @__free_recursive(ptr %t280)
  %t281 = getelementptr ptr, ptr %t4, i32 2
  %t282 = load ptr, ptr %t281
  call void @__free_recursive(ptr %t282)
  %t285 = inttoptr i64 46 to ptr
  %t286 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t285, ptr %t286
  call void @__inc_ref(ptr %t106)
  %t283 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t106, ptr %t283
  call void @__inc_ref(ptr %t260)
  %t284 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t260, ptr %t284
  call void @__free_recursive(ptr %t104)
  call void @__free_recursive(ptr %t260)
  call void @__free_recursive(ptr %t106)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.7.287:
  %t288 = call ptr @__alloc(i64 24, i32 2)
  %t289 = inttoptr i64 47 to ptr
  %t290 = getelementptr ptr, ptr %t288, i32 0
  store ptr %t289, ptr %t290
  %t291 = getelementptr ptr, ptr %t260, i32 2
  %t292 = load ptr, ptr %t291
  call void @__inc_ref(ptr %t292)
  %t293 = getelementptr ptr, ptr %t104, i32 1
  %t294 = load ptr, ptr %t293
  call void @__free_recursive(ptr %t294)
  %t296 = inttoptr i64 34 to ptr
  %t297 = getelementptr ptr, ptr %t104, i32 0
  store ptr %t296, ptr %t297
  %t295 = getelementptr ptr, ptr %t104, i32 1
  store ptr %t292, ptr %t295
  %t298 = getelementptr ptr, ptr %t288, i32 1
  store ptr %t104, ptr %t298
  %t299 = getelementptr ptr, ptr %t260, i32 1
  %t300 = load ptr, ptr %t299
  call void @__inc_ref(ptr %t300)
  %t301 = getelementptr ptr, ptr %t4, i32 1
  %t302 = load ptr, ptr %t301
  call void @__free_recursive(ptr %t302)
  %t303 = getelementptr ptr, ptr %t4, i32 2
  %t304 = load ptr, ptr %t303
  call void @__free_recursive(ptr %t304)
  %t307 = inttoptr i64 44 to ptr
  %t308 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t307, ptr %t308
  call void @__inc_ref(ptr %t106)
  %t305 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t106, ptr %t305
  %t306 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t300, ptr %t306
  %t309 = getelementptr ptr, ptr %t288, i32 2
  store ptr %t4, ptr %t309
  call void @__free_recursive(ptr %t260)
  call void @__free_recursive(ptr %t106)
  store ptr %t288, ptr %t3
  br label %tco.loop.0
tco.case.arm.8.310:
  %t311 = getelementptr ptr, ptr %t4, i32 1
  %t312 = load ptr, ptr %t311
  call void @__free_recursive(ptr %t312)
  %t313 = getelementptr ptr, ptr %t4, i32 2
  %t314 = load ptr, ptr %t313
  call void @__free_recursive(ptr %t314)
  %t328 = inttoptr i64 46 to ptr
  %t329 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t328, ptr %t329
  call void @__inc_ref(ptr %t106)
  %t315 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t106, ptr %t315
  %t316 = call ptr @__alloc(i64 16, i32 1)
  %t317 = inttoptr i64 8 to ptr
  %t318 = getelementptr ptr, ptr %t316, i32 0
  store ptr %t317, ptr %t318
  %t319 = getelementptr ptr, ptr %t260, i32 1
  %t320 = load ptr, ptr %t319
  call void @__inc_ref(ptr %t320)
  %t321 = getelementptr ptr, ptr %t104, i32 1
  %t322 = load ptr, ptr %t321
  call void @__free_recursive(ptr %t322)
  %t324 = inttoptr i64 26 to ptr
  %t325 = getelementptr ptr, ptr %t104, i32 0
  store ptr %t324, ptr %t325
  %t323 = getelementptr ptr, ptr %t104, i32 1
  store ptr %t320, ptr %t323
  %t326 = getelementptr ptr, ptr %t316, i32 1
  store ptr %t104, ptr %t326
  %t327 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t316, ptr %t327
  call void @__free_recursive(ptr %t260)
  call void @__free_recursive(ptr %t106)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.264:
  unreachable
tco.case.arm.35.330:
  %t331 = getelementptr ptr, ptr %t104, i32 1
  %t332 = load ptr, ptr %t331
  call void @__inc_ref(ptr %t332)
  %t333 = call ptr @__alloc(i64 24, i32 2)
  %t334 = inttoptr i64 47 to ptr
  %t335 = getelementptr ptr, ptr %t333, i32 0
  store ptr %t334, ptr %t335
  %t336 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t336
  %t337 = getelementptr ptr, ptr %t4, i32 1
  %t338 = load ptr, ptr %t337
  call void @__free_recursive(ptr %t338)
  %t339 = getelementptr ptr, ptr %t4, i32 2
  %t340 = load ptr, ptr %t339
  call void @__free_recursive(ptr %t340)
  %t343 = inttoptr i64 36 to ptr
  %t344 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t343, ptr %t344
  call void @__inc_ref(ptr %t332)
  %t341 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t332, ptr %t341
  %t342 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t336, ptr %t342
  %t345 = getelementptr ptr, ptr %t333, i32 1
  store ptr %t4, ptr %t345
  %t346 = getelementptr ptr, ptr %t104, i32 1
  %t347 = load ptr, ptr %t346
  call void @__free_recursive(ptr %t347)
  %t349 = inttoptr i64 45 to ptr
  %t350 = getelementptr ptr, ptr %t104, i32 0
  store ptr %t349, ptr %t350
  call void @__inc_ref(ptr %t106)
  %t348 = getelementptr ptr, ptr %t104, i32 1
  store ptr %t106, ptr %t348
  %t351 = getelementptr ptr, ptr %t333, i32 2
  store ptr %t104, ptr %t351
  call void @__free_recursive(ptr %t332)
  call void @__free_recursive(ptr %t106)
  store ptr %t333, ptr %t3
  br label %tco.loop.0
tco.case.arm.36.352:
  %t353 = getelementptr ptr, ptr %t104, i32 1
  %t354 = load ptr, ptr %t353
  call void @__inc_ref(ptr %t354)
  %t355 = getelementptr ptr, ptr %t104, i32 2
  %t356 = load ptr, ptr %t355
  %t357 = getelementptr ptr, ptr %t4, i32 1
  %t358 = load ptr, ptr %t357
  call void @__free_recursive(ptr %t358)
  %t367 = inttoptr i64 47 to ptr
  %t368 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t367, ptr %t368
  %t359 = getelementptr ptr, ptr %t354, i32 1
  %t360 = load ptr, ptr %t359
  call void @__inc_ref(ptr %t360)
  %t361 = getelementptr ptr, ptr %t104, i32 1
  %t362 = load ptr, ptr %t361
  call void @__free_recursive(ptr %t362)
  %t364 = inttoptr i64 30 to ptr
  %t365 = getelementptr ptr, ptr %t104, i32 0
  store ptr %t364, ptr %t365
  %t363 = getelementptr ptr, ptr %t104, i32 1
  store ptr %t360, ptr %t363
  %t366 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t104, ptr %t366
  call void @__free_recursive(ptr %t354)
  call void @__free_recursive(ptr %t106)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.37.369:
  %t370 = getelementptr ptr, ptr %t104, i32 1
  %t371 = load ptr, ptr %t370
  call void @__inc_ref(ptr %t371)
  %t372 = getelementptr ptr, ptr %t4, i32 1
  %t373 = load ptr, ptr %t372
  call void @__free_recursive(ptr %t373)
  %t432 = inttoptr i64 47 to ptr
  %t433 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t432, ptr %t433
  %t374 = call ptr @__alloc(i64 16, i32 1)
  %t375 = inttoptr i64 35 to ptr
  %t376 = getelementptr ptr, ptr %t374, i32 0
  store ptr %t375, ptr %t376
  %t377 = getelementptr ptr, ptr %t371, i32 0
  %t378 = load ptr, ptr %t377
  %t379 = ptrtoint ptr %t378 to i64
  switch i64 %t379, label %case.default.380 [ i64 13, label %case.arm.13.382 i64 14, label %case.arm.14.411 ]
case.arm.13.382:
  %t384 = call ptr @__alloc(i64 16, i32 1)
  %t385 = inttoptr i64 24 to ptr
  %t386 = getelementptr ptr, ptr %t384, i32 0
  store ptr %t385, ptr %t386
  %t387 = call ptr @__alloc(i64 16, i32 1)
  %t388 = inttoptr i64 25 to ptr
  %t389 = getelementptr ptr, ptr %t387, i32 0
  store ptr %t388, ptr %t389
  %t390 = getelementptr ptr, ptr %t104, i32 1
  %t391 = load ptr, ptr %t390
  call void @__free_recursive(ptr %t391)
  %t407 = inttoptr i64 29 to ptr
  %t408 = getelementptr ptr, ptr %t104, i32 0
  store ptr %t407, ptr %t408
  %t394 = getelementptr i8, ptr %t371, i64 -8
  %t395 = load i32, ptr %t394
  %t396 = icmp eq i32 %t395, 1
  br i1 %t396, label %reuse.in_place.397, label %reuse.copy.398
reuse.in_place.397:
  %t392 = inttoptr i64 1 to ptr
  %t393 = getelementptr ptr, ptr %t371, i32 0
  store ptr %t392, ptr %t393
  br label %reuse.in_place.end.400
reuse.in_place.end.400:
  br label %reuse.join.399
reuse.copy.398:
  %t402 = call ptr @__alloc(i64 8, i32 0)
  %t403 = inttoptr i64 1 to ptr
  %t404 = getelementptr ptr, ptr %t402, i32 0
  store ptr %t403, ptr %t404
  call void @__free_recursive(ptr %t371)
  br label %reuse.copy.end.401
reuse.copy.end.401:
  br label %reuse.join.399
reuse.join.399:
  %t405 = phi ptr [ %t371, %reuse.in_place.end.400 ], [ %t402, %reuse.copy.end.401 ]
  %t406 = getelementptr ptr, ptr %t104, i32 1
  store ptr %t405, ptr %t406
  %t409 = getelementptr ptr, ptr %t387, i32 1
  store ptr %t104, ptr %t409
  %t410 = getelementptr ptr, ptr %t384, i32 1
  store ptr %t387, ptr %t410
  br label %case.end.13.383
case.end.13.383:
  br label %case.join.381
case.arm.14.411:
  %t413 = call ptr @__alloc(i64 16, i32 1)
  %t414 = inttoptr i64 24 to ptr
  %t415 = getelementptr ptr, ptr %t413, i32 0
  store ptr %t414, ptr %t415
  %t416 = call ptr @__alloc(i64 16, i32 1)
  %t417 = inttoptr i64 25 to ptr
  %t418 = getelementptr ptr, ptr %t416, i32 0
  store ptr %t417, ptr %t418
  %t419 = call ptr @__alloc(i64 8, i32 0)
  %t420 = inttoptr i64 2 to ptr
  %t421 = getelementptr ptr, ptr %t419, i32 0
  store ptr %t420, ptr %t421
  %t422 = getelementptr ptr, ptr %t104, i32 1
  %t423 = load ptr, ptr %t422
  call void @__free_recursive(ptr %t423)
  %t425 = inttoptr i64 29 to ptr
  %t426 = getelementptr ptr, ptr %t104, i32 0
  store ptr %t425, ptr %t426
  %t424 = getelementptr ptr, ptr %t104, i32 1
  store ptr %t419, ptr %t424
  %t427 = getelementptr ptr, ptr %t416, i32 1
  store ptr %t104, ptr %t427
  %t428 = getelementptr ptr, ptr %t413, i32 1
  store ptr %t416, ptr %t428
  call void @__free_recursive(ptr %t371)
  br label %case.end.14.412
case.end.14.412:
  br label %case.join.381
case.default.380:
  unreachable
case.join.381:
  %t429 = phi ptr [ %t384, %case.end.13.383 ], [ %t413, %case.end.14.412 ]
  %t430 = getelementptr ptr, ptr %t374, i32 1
  store ptr %t429, ptr %t430
  %t431 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t374, ptr %t431
  call void @__free_recursive(ptr %t106)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.110:
  unreachable
tco.case.default.8:
  unreachable
tco.exit.1:
  %t434 = load ptr, ptr %t2
  ret ptr %t434
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
