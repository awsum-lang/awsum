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
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [11 x i8]} { i32 0, i32 0, i32 0, i32 11, i32 11, [11 x i8] c"MISSING_ARG" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"|" }

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
  %stl_tag = inttoptr i64 19 to ptr
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
  %result = phi ptr [ %left, %too_long ], [ %right, %ok ]
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
  %t21 = inttoptr i64 67 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = call ptr @__alloc(i64 24, i32 2)
  %t24 = inttoptr i64 36 to ptr
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
  %t32 = inttoptr i64 51 to ptr
  %t33 = getelementptr ptr, ptr %t31, i32 0
  store ptr %t32, ptr %t33
  %t34 = getelementptr ptr, ptr %t20, i32 2
  store ptr %t31, ptr %t34
  %t35 = call ptr @v_$scc$$apply$$scc$$apply1__$apply2__$apply3__$df$$la$x$1235868101(ptr %t20)
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
  %t1 = inttoptr i64 67 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 16, i32 1)
  %t4 = inttoptr i64 42 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = call ptr @__alloc(i64 16, i32 1)
  %t7 = inttoptr i64 8 to ptr
  %t8 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t7, ptr %t8
  %t9 = call ptr @__alloc(i64 8, i32 0)
  %t10 = inttoptr i64 32 to ptr
  %t11 = getelementptr ptr, ptr %t9, i32 0
  store ptr %t10, ptr %t11
  %t12 = getelementptr ptr, ptr %t6, i32 1
  store ptr %t9, ptr %t12
  %t13 = getelementptr ptr, ptr %t3, i32 1
  store ptr %t6, ptr %t13
  %t14 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t14
  %t15 = call ptr @__alloc(i64 8, i32 0)
  %t16 = inttoptr i64 51 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t15, ptr %t18
  %t19 = call ptr @v_$scc$$apply$$scc$$apply1__$apply2__$apply3__$df$$la$x$1235868101(ptr %t0)
  %t20 = call ptr @__alloc(i64 8, i32 0)
  %t21 = inttoptr i64 49 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = call ptr @v_$cps$$df$$rowmono$0$andThenIO$7(ptr %t19, ptr %t20)
  %t24 = call ptr @__alloc(i64 8, i32 0)
  %t25 = inttoptr i64 47 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v_$cps$$df$handleErrorIO$3(ptr %t23, ptr %t24)
  ret ptr %t27
}

define internal ptr @v_$cps$$df$handleErrorIO$3(ptr %v_io, ptr %v_$k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.13 i64 7, label %tco.case.arm.7.65 i64 8, label %tco.case.arm.8.90 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t12 = call ptr @v_$apply$$df$handleErrorIO$3(ptr %t6, ptr %t5)
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
  switch i64 %t18, label %case.default.19 [ i64 502975519, label %case.arm.502975519.21 i64 589989748, label %case.arm.589989748.35 i64 2671988933, label %case.arm.2671988933.49 ]
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
case.arm.2671988933.49:
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
  br label %case.end.2671988933.50
case.end.2671988933.50:
  br label %case.join.20
case.default.19:
  unreachable
case.join.20:
  %t63 = phi ptr [ %t23, %case.end.502975519.22 ], [ %t37, %case.end.589989748.36 ], [ %t51, %case.end.2671988933.50 ]
  call void @__free_recursive(ptr %t15)
  %t64 = call ptr @v_$apply$$df$handleErrorIO$3(ptr %t6, ptr %t63)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t64, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.65:
  %t66 = getelementptr ptr, ptr %t5, i32 1
  %t67 = load ptr, ptr %t66
  %t68 = getelementptr ptr, ptr %t5, i32 2
  %t69 = load ptr, ptr %t68
  call void @__inc_ref(ptr %t69)
  %t76 = getelementptr i8, ptr %t5, i64 -8
  %t77 = load i32, ptr %t76
  %t78 = icmp eq i32 %t77, 1
  br i1 %t78, label %reuse.in_place.79, label %reuse.copy.80
reuse.in_place.79:
  %t70 = getelementptr ptr, ptr %t5, i32 2
  %t71 = load ptr, ptr %t70
  call void @__free_recursive(ptr %t71)
  %t74 = inttoptr i64 48 to ptr
  %t75 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t74, ptr %t75
  call void @__inc_ref(ptr %t6)
  %t72 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t72
  %t73 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t67, ptr %t73
  br label %reuse.in_place.end.82
reuse.in_place.end.82:
  br label %reuse.join.81
reuse.copy.80:
  %t84 = call ptr @__alloc(i64 24, i32 2)
  %t85 = inttoptr i64 48 to ptr
  %t86 = getelementptr ptr, ptr %t84, i32 0
  store ptr %t85, ptr %t86
  call void @__inc_ref(ptr %t6)
  %t87 = getelementptr ptr, ptr %t84, i32 1
  store ptr %t6, ptr %t87
  call void @__inc_ref(ptr %t67)
  %t88 = getelementptr ptr, ptr %t84, i32 2
  store ptr %t67, ptr %t88
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.83
reuse.copy.end.83:
  br label %reuse.join.81
reuse.join.81:
  %t89 = phi ptr [ %t5, %reuse.in_place.end.82 ], [ %t84, %reuse.copy.end.83 ]
  call void @__free_recursive(ptr %t6)
  store ptr %t69, ptr %t3
  store ptr %t89, ptr %t4
  br label %tco.loop.0
tco.case.arm.8.90:
  %t91 = getelementptr ptr, ptr %t5, i32 1
  %t92 = load ptr, ptr %t91
  call void @__inc_ref(ptr %t92)
  call void @__inc_ref(ptr %t6)
  %t93 = call ptr @__alloc(i64 16, i32 1)
  %t94 = inttoptr i64 8 to ptr
  %t95 = getelementptr ptr, ptr %t93, i32 0
  store ptr %t94, ptr %t95
  %t96 = call ptr @__alloc(i64 16, i32 1)
  %t97 = inttoptr i64 28 to ptr
  %t98 = getelementptr ptr, ptr %t96, i32 0
  store ptr %t97, ptr %t98
  call void @__inc_ref(ptr %t92)
  %t99 = getelementptr ptr, ptr %t96, i32 1
  store ptr %t92, ptr %t99
  %t100 = getelementptr ptr, ptr %t93, i32 1
  store ptr %t96, ptr %t100
  %t101 = call ptr @v_$apply$$df$handleErrorIO$3(ptr %t6, ptr %t93)
  call void @__free_recursive(ptr %t92)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t101, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t102 = load ptr, ptr %t2
  ret ptr %t102
}

define internal ptr @v_$apply$$df$handleErrorIO$3(ptr %v_$k, ptr %v_$x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 47, label %tco.case.arm.47.11 i64 48, label %tco.case.arm.48.12 ]
tco.case.arm.47.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.48.12:
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

define internal ptr @v_$cps$$df$$rowmono$0$andThenIO$7(ptr %v_io, ptr %v_$k) {
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
  %t26 = call ptr @v_$apply$$df$$rowmono$0$andThenIO$7(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t26, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.27:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t28 = call ptr @v_$apply$$df$$rowmono$0$andThenIO$7(ptr %t6, ptr %t5)
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
  %t38 = inttoptr i64 50 to ptr
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
  %t49 = inttoptr i64 50 to ptr
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
  call void @__free_recursive(ptr %t6)
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
  %t61 = inttoptr i64 26 to ptr
  %t62 = getelementptr ptr, ptr %t60, i32 0
  store ptr %t61, ptr %t62
  call void @__inc_ref(ptr %t56)
  %t63 = getelementptr ptr, ptr %t60, i32 1
  store ptr %t56, ptr %t63
  %t64 = getelementptr ptr, ptr %t57, i32 1
  store ptr %t60, ptr %t64
  %t65 = call ptr @v_$apply$$df$$rowmono$0$andThenIO$7(ptr %t6, ptr %t57)
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

define internal ptr @v_$apply$$df$$rowmono$0$andThenIO$7(ptr %v_$k, ptr %v_$x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 49, label %tco.case.arm.49.11 i64 50, label %tco.case.arm.50.12 ]
tco.case.arm.49.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.50.12:
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

define internal ptr @v_$scc$$apply$$scc$$apply1__$apply2__$apply3__$df$$la$x$1235868101(ptr %v_$args$1) {
entry:
  %t3 = alloca ptr
  store ptr %v_$args$1, ptr %t3
  %v_$inl18$scrut.jslot = alloca ptr
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t4 = load ptr, ptr %t3
  %t5 = getelementptr ptr, ptr %t4, i32 0
  %t6 = load ptr, ptr %t5
  %t7 = ptrtoint ptr %t6 to i64
  switch i64 %t7, label %tco.case.default.8 [ i64 66, label %tco.case.arm.66.9 i64 67, label %tco.case.arm.67.411 ]
tco.case.arm.66.9:
  %t10 = getelementptr ptr, ptr %t4, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  %t12 = getelementptr ptr, ptr %t4, i32 2
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t11, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %tco.case.default.17 [ i64 51, label %tco.case.arm.51.18 i64 52, label %tco.case.arm.52.19 i64 53, label %tco.case.arm.53.37 i64 54, label %tco.case.arm.54.55 i64 55, label %tco.case.arm.55.73 i64 56, label %tco.case.arm.56.94 i64 57, label %tco.case.arm.57.115 i64 58, label %tco.case.arm.58.136 i64 59, label %tco.case.arm.59.151 i64 60, label %tco.case.arm.60.166 i64 61, label %tco.case.arm.61.181 i64 62, label %tco.case.arm.62.196 i64 65, label %tco.case.arm.65.229 i64 64, label %tco.case.arm.64.263 i64 63, label %tco.case.arm.63.349 ]
tco.case.arm.51.18:
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %t4)
  store ptr %t13, ptr %t2
  br label %tco.exit.1
tco.case.arm.52.19:
  %t20 = call ptr @__alloc(i64 24, i32 2)
  %t21 = inttoptr i64 67 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = getelementptr ptr, ptr %t11, i32 2
  %t24 = load ptr, ptr %t23
  call void @__inc_ref(ptr %t24)
  %t25 = getelementptr ptr, ptr %t4, i32 1
  %t26 = load ptr, ptr %t25
  call void @__free_recursive(ptr %t26)
  %t27 = getelementptr ptr, ptr %t4, i32 2
  %t28 = load ptr, ptr %t27
  call void @__free_recursive(ptr %t28)
  %t31 = inttoptr i64 36 to ptr
  %t32 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t31, ptr %t32
  call void @__inc_ref(ptr %t13)
  %t29 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t13, ptr %t29
  %t30 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t24, ptr %t30
  %t33 = getelementptr ptr, ptr %t20, i32 1
  store ptr %t4, ptr %t33
  %t34 = getelementptr ptr, ptr %t11, i32 1
  %t35 = load ptr, ptr %t34
  call void @__inc_ref(ptr %t35)
  %t36 = getelementptr ptr, ptr %t20, i32 2
  store ptr %t35, ptr %t36
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t20, ptr %t3
  br label %tco.loop.0
tco.case.arm.53.37:
  %t38 = call ptr @__alloc(i64 24, i32 2)
  %t39 = inttoptr i64 67 to ptr
  %t40 = getelementptr ptr, ptr %t38, i32 0
  store ptr %t39, ptr %t40
  %t41 = getelementptr ptr, ptr %t11, i32 2
  %t42 = load ptr, ptr %t41
  call void @__inc_ref(ptr %t42)
  %t43 = getelementptr ptr, ptr %t4, i32 1
  %t44 = load ptr, ptr %t43
  call void @__free_recursive(ptr %t44)
  %t45 = getelementptr ptr, ptr %t4, i32 2
  %t46 = load ptr, ptr %t45
  call void @__free_recursive(ptr %t46)
  %t49 = inttoptr i64 36 to ptr
  %t50 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t49, ptr %t50
  call void @__inc_ref(ptr %t13)
  %t47 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t13, ptr %t47
  %t48 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t42, ptr %t48
  %t51 = getelementptr ptr, ptr %t38, i32 1
  store ptr %t4, ptr %t51
  %t52 = getelementptr ptr, ptr %t11, i32 1
  %t53 = load ptr, ptr %t52
  call void @__inc_ref(ptr %t53)
  %t54 = getelementptr ptr, ptr %t38, i32 2
  store ptr %t53, ptr %t54
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t38, ptr %t3
  br label %tco.loop.0
tco.case.arm.54.55:
  %t56 = call ptr @__alloc(i64 24, i32 2)
  %t57 = inttoptr i64 67 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  %t59 = getelementptr ptr, ptr %t11, i32 2
  %t60 = load ptr, ptr %t59
  call void @__inc_ref(ptr %t60)
  %t61 = getelementptr ptr, ptr %t4, i32 1
  %t62 = load ptr, ptr %t61
  call void @__free_recursive(ptr %t62)
  %t63 = getelementptr ptr, ptr %t4, i32 2
  %t64 = load ptr, ptr %t63
  call void @__free_recursive(ptr %t64)
  %t67 = inttoptr i64 36 to ptr
  %t68 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t13)
  %t65 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t13, ptr %t65
  %t66 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t60, ptr %t66
  %t69 = getelementptr ptr, ptr %t56, i32 1
  store ptr %t4, ptr %t69
  %t70 = getelementptr ptr, ptr %t11, i32 1
  %t71 = load ptr, ptr %t70
  call void @__inc_ref(ptr %t71)
  %t72 = getelementptr ptr, ptr %t56, i32 2
  store ptr %t71, ptr %t72
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t56, ptr %t3
  br label %tco.loop.0
tco.case.arm.55.73:
  %t74 = call ptr @__alloc(i64 32, i32 3)
  %t75 = inttoptr i64 37 to ptr
  %t76 = getelementptr ptr, ptr %t74, i32 0
  store ptr %t75, ptr %t76
  call void @__inc_ref(ptr %t13)
  %t77 = getelementptr ptr, ptr %t74, i32 1
  store ptr %t13, ptr %t77
  %t78 = getelementptr ptr, ptr %t11, i32 2
  %t79 = load ptr, ptr %t78
  call void @__inc_ref(ptr %t79)
  %t80 = getelementptr ptr, ptr %t74, i32 2
  store ptr %t79, ptr %t80
  %t81 = getelementptr ptr, ptr %t11, i32 3
  %t82 = load ptr, ptr %t81
  call void @__inc_ref(ptr %t82)
  %t83 = getelementptr ptr, ptr %t74, i32 3
  store ptr %t82, ptr %t83
  %t84 = getelementptr ptr, ptr %t11, i32 1
  %t85 = load ptr, ptr %t84
  call void @__inc_ref(ptr %t85)
  %t86 = getelementptr ptr, ptr %t4, i32 1
  %t87 = load ptr, ptr %t86
  call void @__free_recursive(ptr %t87)
  %t88 = getelementptr ptr, ptr %t4, i32 2
  %t89 = load ptr, ptr %t88
  call void @__free_recursive(ptr %t89)
  %t92 = inttoptr i64 67 to ptr
  %t93 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t92, ptr %t93
  %t90 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t74, ptr %t90
  %t91 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t85, ptr %t91
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.56.94:
  %t95 = call ptr @__alloc(i64 32, i32 3)
  %t96 = inttoptr i64 37 to ptr
  %t97 = getelementptr ptr, ptr %t95, i32 0
  store ptr %t96, ptr %t97
  call void @__inc_ref(ptr %t13)
  %t98 = getelementptr ptr, ptr %t95, i32 1
  store ptr %t13, ptr %t98
  %t99 = getelementptr ptr, ptr %t11, i32 2
  %t100 = load ptr, ptr %t99
  call void @__inc_ref(ptr %t100)
  %t101 = getelementptr ptr, ptr %t95, i32 2
  store ptr %t100, ptr %t101
  %t102 = getelementptr ptr, ptr %t11, i32 3
  %t103 = load ptr, ptr %t102
  call void @__inc_ref(ptr %t103)
  %t104 = getelementptr ptr, ptr %t95, i32 3
  store ptr %t103, ptr %t104
  %t105 = getelementptr ptr, ptr %t11, i32 1
  %t106 = load ptr, ptr %t105
  call void @__inc_ref(ptr %t106)
  %t107 = getelementptr ptr, ptr %t4, i32 1
  %t108 = load ptr, ptr %t107
  call void @__free_recursive(ptr %t108)
  %t109 = getelementptr ptr, ptr %t4, i32 2
  %t110 = load ptr, ptr %t109
  call void @__free_recursive(ptr %t110)
  %t113 = inttoptr i64 67 to ptr
  %t114 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t113, ptr %t114
  %t111 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t95, ptr %t111
  %t112 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t106, ptr %t112
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.57.115:
  %t116 = call ptr @__alloc(i64 32, i32 3)
  %t117 = inttoptr i64 37 to ptr
  %t118 = getelementptr ptr, ptr %t116, i32 0
  store ptr %t117, ptr %t118
  call void @__inc_ref(ptr %t13)
  %t119 = getelementptr ptr, ptr %t116, i32 1
  store ptr %t13, ptr %t119
  %t120 = getelementptr ptr, ptr %t11, i32 2
  %t121 = load ptr, ptr %t120
  call void @__inc_ref(ptr %t121)
  %t122 = getelementptr ptr, ptr %t116, i32 2
  store ptr %t121, ptr %t122
  %t123 = getelementptr ptr, ptr %t11, i32 3
  %t124 = load ptr, ptr %t123
  call void @__inc_ref(ptr %t124)
  %t125 = getelementptr ptr, ptr %t116, i32 3
  store ptr %t124, ptr %t125
  %t126 = getelementptr ptr, ptr %t11, i32 1
  %t127 = load ptr, ptr %t126
  call void @__inc_ref(ptr %t127)
  %t128 = getelementptr ptr, ptr %t4, i32 1
  %t129 = load ptr, ptr %t128
  call void @__free_recursive(ptr %t129)
  %t130 = getelementptr ptr, ptr %t4, i32 2
  %t131 = load ptr, ptr %t130
  call void @__free_recursive(ptr %t131)
  %t134 = inttoptr i64 67 to ptr
  %t135 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t134, ptr %t135
  %t132 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t116, ptr %t132
  %t133 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t127, ptr %t133
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.58.136:
  %t137 = getelementptr ptr, ptr %t11, i32 1
  %t138 = load ptr, ptr %t137
  call void @__inc_ref(ptr %t138)
  call void @__inc_ref(ptr %t13)
  %t139 = call ptr @__alloc(i64 8, i32 0)
  %t140 = inttoptr i64 49 to ptr
  %t141 = getelementptr ptr, ptr %t139, i32 0
  store ptr %t140, ptr %t141
  %t142 = call ptr @v_$cps$$df$$rowmono$0$andThenIO$7(ptr %t13, ptr %t139)
  %t143 = getelementptr ptr, ptr %t4, i32 1
  %t144 = load ptr, ptr %t143
  call void @__free_recursive(ptr %t144)
  %t145 = getelementptr ptr, ptr %t4, i32 2
  %t146 = load ptr, ptr %t145
  call void @__free_recursive(ptr %t146)
  %t149 = inttoptr i64 66 to ptr
  %t150 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t149, ptr %t150
  %t147 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t138, ptr %t147
  %t148 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t142, ptr %t148
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.59.151:
  %t152 = call ptr @__alloc(i64 16, i32 1)
  %t153 = inttoptr i64 42 to ptr
  %t154 = getelementptr ptr, ptr %t152, i32 0
  store ptr %t153, ptr %t154
  call void @__inc_ref(ptr %t13)
  %t155 = getelementptr ptr, ptr %t152, i32 1
  store ptr %t13, ptr %t155
  %t156 = getelementptr ptr, ptr %t11, i32 1
  %t157 = load ptr, ptr %t156
  call void @__inc_ref(ptr %t157)
  %t158 = getelementptr ptr, ptr %t4, i32 1
  %t159 = load ptr, ptr %t158
  call void @__free_recursive(ptr %t159)
  %t160 = getelementptr ptr, ptr %t4, i32 2
  %t161 = load ptr, ptr %t160
  call void @__free_recursive(ptr %t161)
  %t164 = inttoptr i64 67 to ptr
  %t165 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t164, ptr %t165
  %t162 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t152, ptr %t162
  %t163 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t157, ptr %t163
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.60.166:
  %t167 = getelementptr ptr, ptr %t11, i32 1
  %t168 = load ptr, ptr %t167
  call void @__inc_ref(ptr %t168)
  call void @__inc_ref(ptr %t13)
  %t169 = call ptr @__alloc(i64 8, i32 0)
  %t170 = inttoptr i64 47 to ptr
  %t171 = getelementptr ptr, ptr %t169, i32 0
  store ptr %t170, ptr %t171
  %t172 = call ptr @v_$cps$$df$handleErrorIO$3(ptr %t13, ptr %t169)
  %t173 = getelementptr ptr, ptr %t4, i32 1
  %t174 = load ptr, ptr %t173
  call void @__free_recursive(ptr %t174)
  %t175 = getelementptr ptr, ptr %t4, i32 2
  %t176 = load ptr, ptr %t175
  call void @__free_recursive(ptr %t176)
  %t179 = inttoptr i64 66 to ptr
  %t180 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t179, ptr %t180
  %t177 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t168, ptr %t177
  %t178 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t172, ptr %t178
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.61.181:
  %t182 = call ptr @__alloc(i64 24, i32 2)
  %t183 = inttoptr i64 66 to ptr
  %t184 = getelementptr ptr, ptr %t182, i32 0
  store ptr %t183, ptr %t184
  %t185 = getelementptr ptr, ptr %t11, i32 1
  %t186 = load ptr, ptr %t185
  call void @__inc_ref(ptr %t186)
  %t187 = getelementptr ptr, ptr %t182, i32 1
  store ptr %t186, ptr %t187
  %t188 = getelementptr ptr, ptr %t11, i32 2
  %t189 = load ptr, ptr %t188
  call void @__inc_ref(ptr %t189)
  %t190 = getelementptr ptr, ptr %t4, i32 1
  %t191 = load ptr, ptr %t190
  call void @__free_recursive(ptr %t191)
  %t193 = inttoptr i64 7 to ptr
  %t194 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t193, ptr %t194
  %t192 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t189, ptr %t192
  %t195 = getelementptr ptr, ptr %t182, i32 2
  store ptr %t4, ptr %t195
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t182, ptr %t3
  br label %tco.loop.0
tco.case.arm.62.196:
  %t197 = getelementptr ptr, ptr %t11, i32 1
  %t198 = load ptr, ptr %t197
  call void @__inc_ref(ptr %t198)
  %t199 = getelementptr ptr, ptr %t13, i32 0
  %t200 = load ptr, ptr %t199
  %t201 = ptrtoint ptr %t200 to i64
  switch i64 %t201, label %case.default.202 [ i64 3, label %case.arm.3.204 i64 4, label %case.arm.4.212 ]
case.arm.3.204:
  %t206 = call ptr @__alloc(i64 16, i32 1)
  %t207 = inttoptr i64 6 to ptr
  %t208 = getelementptr ptr, ptr %t206, i32 0
  store ptr %t207, ptr %t208
  %t209 = getelementptr ptr, ptr %t13, i32 1
  %t210 = load ptr, ptr %t209
  call void @__inc_ref(ptr %t210)
  %t211 = getelementptr ptr, ptr %t206, i32 1
  store ptr %t210, ptr %t211
  br label %case.end.3.205
case.end.3.205:
  br label %case.join.203
case.arm.4.212:
  %t214 = call ptr @__alloc(i64 16, i32 1)
  %t215 = inttoptr i64 5 to ptr
  %t216 = getelementptr ptr, ptr %t214, i32 0
  store ptr %t215, ptr %t216
  %t217 = getelementptr ptr, ptr %t13, i32 1
  %t218 = load ptr, ptr %t217
  call void @__inc_ref(ptr %t218)
  %t219 = getelementptr ptr, ptr %t214, i32 1
  store ptr %t218, ptr %t219
  br label %case.end.4.213
case.end.4.213:
  br label %case.join.203
case.default.202:
  unreachable
case.join.203:
  %t220 = phi ptr [ %t206, %case.end.3.205 ], [ %t214, %case.end.4.213 ]
  %t221 = getelementptr ptr, ptr %t4, i32 1
  %t222 = load ptr, ptr %t221
  call void @__free_recursive(ptr %t222)
  %t223 = getelementptr ptr, ptr %t4, i32 2
  %t224 = load ptr, ptr %t223
  call void @__free_recursive(ptr %t224)
  %t227 = inttoptr i64 66 to ptr
  %t228 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t227, ptr %t228
  %t225 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t198, ptr %t225
  %t226 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t220, ptr %t226
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.65.229:
  %t230 = getelementptr ptr, ptr %t11, i32 1
  %t231 = load ptr, ptr %t230
  call void @__inc_ref(ptr %t231)
  %t232 = getelementptr ptr, ptr %t11, i32 2
  %t233 = load ptr, ptr %t232
  call void @__inc_ref(ptr %t233)
  call void @__inc_ref(ptr %t13)
  %t234 = call ptr @__concat(ptr %t233, ptr %t13)
  %t235 = getelementptr ptr, ptr %t234, i32 0
  %t236 = load ptr, ptr %t235
  %t237 = ptrtoint ptr %t236 to i64
  switch i64 %t237, label %case.default.238 [ i64 3, label %case.arm.3.240 i64 4, label %case.arm.4.252 ]
case.arm.3.240:
  %t242 = call ptr @__alloc(i64 16, i32 1)
  %t243 = inttoptr i64 3 to ptr
  %t244 = getelementptr ptr, ptr %t242, i32 0
  store ptr %t243, ptr %t244
  %t245 = call ptr @__alloc(i64 16, i32 1)
  %t246 = inttoptr i64 589989748 to ptr
  %t247 = getelementptr ptr, ptr %t245, i32 0
  store ptr %t246, ptr %t247
  %t248 = getelementptr ptr, ptr %t234, i32 1
  %t249 = load ptr, ptr %t248
  call void @__inc_ref(ptr %t249)
  %t250 = getelementptr ptr, ptr %t245, i32 1
  store ptr %t249, ptr %t250
  %t251 = getelementptr ptr, ptr %t242, i32 1
  store ptr %t245, ptr %t251
  br label %case.end.3.241
case.end.3.241:
  br label %case.join.239
case.arm.4.252:
  call void @__inc_ref(ptr %t234)
  br label %case.end.4.253
case.end.4.253:
  br label %case.join.239
case.default.238:
  unreachable
case.join.239:
  %t254 = phi ptr [ %t242, %case.end.3.241 ], [ %t234, %case.end.4.253 ]
  call void @__free_recursive(ptr %t234)
  %t255 = getelementptr ptr, ptr %t4, i32 1
  %t256 = load ptr, ptr %t255
  call void @__free_recursive(ptr %t256)
  %t257 = getelementptr ptr, ptr %t4, i32 2
  %t258 = load ptr, ptr %t257
  call void @__free_recursive(ptr %t258)
  %t261 = inttoptr i64 66 to ptr
  %t262 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t261, ptr %t262
  %t259 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t231, ptr %t259
  %t260 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t254, ptr %t260
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.64.263:
  %t264 = getelementptr ptr, ptr %t11, i32 1
  %t265 = load ptr, ptr %t264
  call void @__inc_ref(ptr %t265)
  %t266 = getelementptr ptr, ptr %t11, i32 3
  %t267 = load ptr, ptr %t266
  call void @__inc_ref(ptr %t267)
  call void @__inc_ref(ptr %t13)
  %t268 = call ptr @__concat(ptr %t267, ptr %t13)
  %t269 = getelementptr ptr, ptr %t268, i32 0
  %t270 = load ptr, ptr %t269
  %t271 = ptrtoint ptr %t270 to i64
  switch i64 %t271, label %tco.case.default.272 [ i64 3, label %tco.case.arm.3.273 i64 4, label %tco.case.arm.4.292 ]
tco.case.arm.3.273:
  %t274 = getelementptr ptr, ptr %t268, i32 1
  %t275 = load ptr, ptr %t274
  call void @__inc_ref(ptr %t275)
  call void @__free_recursive(ptr %t268)
  %t276 = call ptr @__alloc(i64 16, i32 1)
  %t277 = inttoptr i64 3 to ptr
  %t278 = getelementptr ptr, ptr %t276, i32 0
  store ptr %t277, ptr %t278
  %t279 = call ptr @__alloc(i64 16, i32 1)
  %t280 = inttoptr i64 589989748 to ptr
  %t281 = getelementptr ptr, ptr %t279, i32 0
  store ptr %t280, ptr %t281
  call void @__inc_ref(ptr %t275)
  %t282 = getelementptr ptr, ptr %t279, i32 1
  store ptr %t275, ptr %t282
  %t283 = getelementptr ptr, ptr %t276, i32 1
  store ptr %t279, ptr %t283
  %t284 = getelementptr ptr, ptr %t4, i32 1
  %t285 = load ptr, ptr %t284
  call void @__free_recursive(ptr %t285)
  %t286 = getelementptr ptr, ptr %t4, i32 2
  %t287 = load ptr, ptr %t286
  call void @__free_recursive(ptr %t287)
  %t290 = inttoptr i64 66 to ptr
  %t291 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t290, ptr %t291
  call void @__inc_ref(ptr %t265)
  %t288 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t265, ptr %t288
  %t289 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t276, ptr %t289
  call void @__free_recursive(ptr %t275)
  call void @__free_recursive(ptr %t265)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.4.292:
  %t293 = getelementptr ptr, ptr %t268, i32 1
  %t294 = load ptr, ptr %t293
  call void @__inc_ref(ptr %t294)
  call void @__free_recursive(ptr %t268)
  call void @__inc_ref(ptr %t294)
  %t295 = call ptr @__concat(ptr %t294, ptr getelementptr inbounds (i8, ptr @.str.3, i64 12))
  %t296 = getelementptr ptr, ptr %t295, i32 0
  %t297 = load ptr, ptr %t296
  %t298 = ptrtoint ptr %t297 to i64
  switch i64 %t298, label %tco.case.default.299 [ i64 3, label %tco.case.arm.3.300 i64 4, label %tco.case.arm.4.319 ]
tco.case.arm.3.300:
  %t301 = getelementptr ptr, ptr %t295, i32 1
  %t302 = load ptr, ptr %t301
  call void @__inc_ref(ptr %t302)
  call void @__free_recursive(ptr %t295)
  %t303 = call ptr @__alloc(i64 16, i32 1)
  %t304 = inttoptr i64 3 to ptr
  %t305 = getelementptr ptr, ptr %t303, i32 0
  store ptr %t304, ptr %t305
  %t306 = call ptr @__alloc(i64 16, i32 1)
  %t307 = inttoptr i64 589989748 to ptr
  %t308 = getelementptr ptr, ptr %t306, i32 0
  store ptr %t307, ptr %t308
  call void @__inc_ref(ptr %t302)
  %t309 = getelementptr ptr, ptr %t306, i32 1
  store ptr %t302, ptr %t309
  %t310 = getelementptr ptr, ptr %t303, i32 1
  store ptr %t306, ptr %t310
  %t311 = getelementptr ptr, ptr %t4, i32 1
  %t312 = load ptr, ptr %t311
  call void @__free_recursive(ptr %t312)
  %t313 = getelementptr ptr, ptr %t4, i32 2
  %t314 = load ptr, ptr %t313
  call void @__free_recursive(ptr %t314)
  %t317 = inttoptr i64 66 to ptr
  %t318 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t317, ptr %t318
  call void @__inc_ref(ptr %t265)
  %t315 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t265, ptr %t315
  %t316 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t303, ptr %t316
  call void @__free_recursive(ptr %t302)
  call void @__free_recursive(ptr %t294)
  call void @__free_recursive(ptr %t265)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.4.319:
  %t320 = getelementptr ptr, ptr %t295, i32 1
  %t321 = load ptr, ptr %t320
  call void @__inc_ref(ptr %t321)
  call void @__free_recursive(ptr %t295)
  %t322 = call ptr @__alloc(i64 24, i32 2)
  %t323 = inttoptr i64 67 to ptr
  %t324 = getelementptr ptr, ptr %t322, i32 0
  store ptr %t323, ptr %t324
  %t325 = call ptr @__alloc(i64 16, i32 1)
  %t326 = inttoptr i64 24 to ptr
  %t327 = getelementptr ptr, ptr %t325, i32 0
  store ptr %t326, ptr %t327
  %t328 = call ptr @__alloc(i64 8, i32 0)
  %t329 = inttoptr i64 35 to ptr
  %t330 = getelementptr ptr, ptr %t328, i32 0
  store ptr %t329, ptr %t330
  %t331 = getelementptr ptr, ptr %t325, i32 1
  store ptr %t328, ptr %t331
  %t332 = getelementptr ptr, ptr %t11, i32 2
  %t333 = load ptr, ptr %t332
  call void @__inc_ref(ptr %t333)
  %t334 = getelementptr ptr, ptr %t4, i32 1
  %t335 = load ptr, ptr %t334
  call void @__free_recursive(ptr %t335)
  %t336 = getelementptr ptr, ptr %t4, i32 2
  %t337 = load ptr, ptr %t336
  call void @__free_recursive(ptr %t337)
  %t340 = inttoptr i64 44 to ptr
  %t341 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t340, ptr %t341
  %t338 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t325, ptr %t338
  %t339 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t333, ptr %t339
  %t342 = getelementptr ptr, ptr %t322, i32 1
  store ptr %t4, ptr %t342
  %t343 = call ptr @__alloc(i64 24, i32 2)
  %t344 = inttoptr i64 65 to ptr
  %t345 = getelementptr ptr, ptr %t343, i32 0
  store ptr %t344, ptr %t345
  call void @__inc_ref(ptr %t265)
  %t346 = getelementptr ptr, ptr %t343, i32 1
  store ptr %t265, ptr %t346
  call void @__inc_ref(ptr %t321)
  %t347 = getelementptr ptr, ptr %t343, i32 2
  store ptr %t321, ptr %t347
  %t348 = getelementptr ptr, ptr %t322, i32 2
  store ptr %t343, ptr %t348
  call void @__free_recursive(ptr %t321)
  call void @__free_recursive(ptr %t294)
  call void @__free_recursive(ptr %t265)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t322, ptr %t3
  br label %tco.loop.0
tco.case.default.299:
  unreachable
tco.case.default.272:
  unreachable
tco.case.arm.63.349:
  %t350 = getelementptr ptr, ptr %t11, i32 1
  %t351 = load ptr, ptr %t350
  call void @__inc_ref(ptr %t351)
  %t352 = getelementptr ptr, ptr %t11, i32 2
  %t353 = load ptr, ptr %t352
  call void @__inc_ref(ptr %t353)
  call void @__inc_ref(ptr %t13)
  %t354 = call ptr @__concat(ptr %t13, ptr getelementptr inbounds (i8, ptr @.str.3, i64 12))
  %t355 = getelementptr ptr, ptr %t354, i32 0
  %t356 = load ptr, ptr %t355
  %t357 = ptrtoint ptr %t356 to i64
  switch i64 %t357, label %tco.case.default.358 [ i64 3, label %tco.case.arm.3.359 i64 4, label %tco.case.arm.4.378 ]
tco.case.arm.3.359:
  %t360 = getelementptr ptr, ptr %t354, i32 1
  %t361 = load ptr, ptr %t360
  call void @__inc_ref(ptr %t361)
  call void @__free_recursive(ptr %t354)
  %t362 = call ptr @__alloc(i64 16, i32 1)
  %t363 = inttoptr i64 3 to ptr
  %t364 = getelementptr ptr, ptr %t362, i32 0
  store ptr %t363, ptr %t364
  %t365 = call ptr @__alloc(i64 16, i32 1)
  %t366 = inttoptr i64 589989748 to ptr
  %t367 = getelementptr ptr, ptr %t365, i32 0
  store ptr %t366, ptr %t367
  call void @__inc_ref(ptr %t361)
  %t368 = getelementptr ptr, ptr %t365, i32 1
  store ptr %t361, ptr %t368
  %t369 = getelementptr ptr, ptr %t362, i32 1
  store ptr %t365, ptr %t369
  %t370 = getelementptr ptr, ptr %t4, i32 1
  %t371 = load ptr, ptr %t370
  call void @__free_recursive(ptr %t371)
  %t372 = getelementptr ptr, ptr %t4, i32 2
  %t373 = load ptr, ptr %t372
  call void @__free_recursive(ptr %t373)
  %t376 = inttoptr i64 66 to ptr
  %t377 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t376, ptr %t377
  call void @__inc_ref(ptr %t351)
  %t374 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t351, ptr %t374
  %t375 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t362, ptr %t375
  call void @__free_recursive(ptr %t361)
  call void @__free_recursive(ptr %t353)
  call void @__free_recursive(ptr %t351)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.4.378:
  %t379 = getelementptr ptr, ptr %t354, i32 1
  %t380 = load ptr, ptr %t379
  call void @__inc_ref(ptr %t380)
  call void @__free_recursive(ptr %t354)
  %t381 = call ptr @__alloc(i64 24, i32 2)
  %t382 = inttoptr i64 67 to ptr
  %t383 = getelementptr ptr, ptr %t381, i32 0
  store ptr %t382, ptr %t383
  %t384 = call ptr @__alloc(i64 16, i32 1)
  %t385 = inttoptr i64 24 to ptr
  %t386 = getelementptr ptr, ptr %t384, i32 0
  store ptr %t385, ptr %t386
  %t387 = call ptr @__alloc(i64 16, i32 1)
  %t388 = inttoptr i64 30 to ptr
  %t389 = getelementptr ptr, ptr %t387, i32 0
  store ptr %t388, ptr %t389
  %t390 = call ptr @__alloc(i64 8, i32 0)
  %t391 = inttoptr i64 34 to ptr
  %t392 = getelementptr ptr, ptr %t390, i32 0
  store ptr %t391, ptr %t392
  %t393 = getelementptr ptr, ptr %t387, i32 1
  store ptr %t390, ptr %t393
  %t394 = getelementptr ptr, ptr %t384, i32 1
  store ptr %t387, ptr %t394
  %t395 = getelementptr ptr, ptr %t4, i32 1
  %t396 = load ptr, ptr %t395
  call void @__free_recursive(ptr %t396)
  %t397 = getelementptr ptr, ptr %t4, i32 2
  %t398 = load ptr, ptr %t397
  call void @__free_recursive(ptr %t398)
  %t401 = inttoptr i64 44 to ptr
  %t402 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t401, ptr %t402
  %t399 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t384, ptr %t399
  call void @__inc_ref(ptr %t353)
  %t400 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t353, ptr %t400
  %t403 = getelementptr ptr, ptr %t381, i32 1
  store ptr %t4, ptr %t403
  %t404 = call ptr @__alloc(i64 32, i32 3)
  %t405 = inttoptr i64 64 to ptr
  %t406 = getelementptr ptr, ptr %t404, i32 0
  store ptr %t405, ptr %t406
  call void @__inc_ref(ptr %t351)
  %t407 = getelementptr ptr, ptr %t404, i32 1
  store ptr %t351, ptr %t407
  call void @__inc_ref(ptr %t353)
  %t408 = getelementptr ptr, ptr %t404, i32 2
  store ptr %t353, ptr %t408
  call void @__inc_ref(ptr %t380)
  %t409 = getelementptr ptr, ptr %t404, i32 3
  store ptr %t380, ptr %t409
  %t410 = getelementptr ptr, ptr %t381, i32 2
  store ptr %t404, ptr %t410
  call void @__free_recursive(ptr %t380)
  call void @__free_recursive(ptr %t353)
  call void @__free_recursive(ptr %t351)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t381, ptr %t3
  br label %tco.loop.0
tco.case.default.358:
  unreachable
tco.case.default.17:
  unreachable
tco.case.arm.67.411:
  %t412 = getelementptr ptr, ptr %t4, i32 1
  %t413 = load ptr, ptr %t412
  call void @__inc_ref(ptr %t413)
  %t414 = getelementptr ptr, ptr %t4, i32 2
  %t415 = load ptr, ptr %t414
  call void @__inc_ref(ptr %t415)
  %t416 = getelementptr ptr, ptr %t413, i32 0
  %t417 = load ptr, ptr %t416
  %t418 = ptrtoint ptr %t417 to i64
  switch i64 %t418, label %tco.case.default.419 [ i64 36, label %tco.case.arm.36.420 i64 37, label %tco.case.arm.37.568 i64 38, label %tco.case.arm.38.774 i64 39, label %tco.case.arm.39.978 i64 40, label %tco.case.arm.40.997 i64 41, label %tco.case.arm.41.1016 i64 42, label %tco.case.arm.42.1035 i64 43, label %tco.case.arm.43.1107 i64 44, label %tco.case.arm.44.1124 i64 45, label %tco.case.arm.45.1146 i64 46, label %tco.case.arm.46.1167 ]
tco.case.arm.36.420:
  %t421 = getelementptr ptr, ptr %t413, i32 1
  %t422 = load ptr, ptr %t421
  call void @__inc_ref(ptr %t422)
  %t423 = getelementptr ptr, ptr %t413, i32 2
  %t424 = load ptr, ptr %t423
  call void @__inc_ref(ptr %t424)
  %t425 = getelementptr ptr, ptr %t422, i32 0
  %t426 = load ptr, ptr %t425
  %t427 = ptrtoint ptr %t426 to i64
  switch i64 %t427, label %tco.case.default.428 [ i64 26, label %tco.case.arm.26.429 i64 27, label %tco.case.arm.27.442 i64 28, label %tco.case.arm.28.455 i64 29, label %tco.case.arm.29.468 i64 30, label %tco.case.arm.30.480 i64 31, label %tco.case.arm.31.495 i64 32, label %tco.case.arm.32.507 i64 33, label %tco.case.arm.33.538 i64 34, label %tco.case.arm.34.549 i64 35, label %tco.case.arm.35.555 ]
tco.case.arm.26.429:
  %t430 = getelementptr ptr, ptr %t4, i32 1
  %t431 = load ptr, ptr %t430
  call void @__free_recursive(ptr %t431)
  %t440 = inttoptr i64 67 to ptr
  %t441 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t440, ptr %t441
  %t432 = getelementptr ptr, ptr %t422, i32 1
  %t433 = load ptr, ptr %t432
  call void @__inc_ref(ptr %t433)
  %t434 = getelementptr ptr, ptr %t413, i32 1
  %t435 = load ptr, ptr %t434
  call void @__free_recursive(ptr %t435)
  %t437 = inttoptr i64 39 to ptr
  %t438 = getelementptr ptr, ptr %t413, i32 0
  store ptr %t437, ptr %t438
  %t436 = getelementptr ptr, ptr %t413, i32 1
  store ptr %t433, ptr %t436
  %t439 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t413, ptr %t439
  call void @__free_recursive(ptr %t424)
  call void @__free_recursive(ptr %t422)
  call void @__free_recursive(ptr %t415)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.27.442:
  %t443 = getelementptr ptr, ptr %t4, i32 1
  %t444 = load ptr, ptr %t443
  call void @__free_recursive(ptr %t444)
  %t453 = inttoptr i64 67 to ptr
  %t454 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t453, ptr %t454
  %t445 = getelementptr ptr, ptr %t422, i32 1
  %t446 = load ptr, ptr %t445
  call void @__inc_ref(ptr %t446)
  %t447 = getelementptr ptr, ptr %t413, i32 1
  %t448 = load ptr, ptr %t447
  call void @__free_recursive(ptr %t448)
  %t450 = inttoptr i64 40 to ptr
  %t451 = getelementptr ptr, ptr %t413, i32 0
  store ptr %t450, ptr %t451
  %t449 = getelementptr ptr, ptr %t413, i32 1
  store ptr %t446, ptr %t449
  %t452 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t413, ptr %t452
  call void @__free_recursive(ptr %t424)
  call void @__free_recursive(ptr %t422)
  call void @__free_recursive(ptr %t415)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.28.455:
  %t456 = getelementptr ptr, ptr %t4, i32 1
  %t457 = load ptr, ptr %t456
  call void @__free_recursive(ptr %t457)
  %t466 = inttoptr i64 67 to ptr
  %t467 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t466, ptr %t467
  %t458 = getelementptr ptr, ptr %t422, i32 1
  %t459 = load ptr, ptr %t458
  call void @__inc_ref(ptr %t459)
  %t460 = getelementptr ptr, ptr %t413, i32 1
  %t461 = load ptr, ptr %t460
  call void @__free_recursive(ptr %t461)
  %t463 = inttoptr i64 41 to ptr
  %t464 = getelementptr ptr, ptr %t413, i32 0
  store ptr %t463, ptr %t464
  %t462 = getelementptr ptr, ptr %t413, i32 1
  store ptr %t459, ptr %t462
  %t465 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t413, ptr %t465
  call void @__free_recursive(ptr %t424)
  call void @__free_recursive(ptr %t422)
  call void @__free_recursive(ptr %t415)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.29.468:
  %t469 = call ptr @__alloc(i64 8, i32 0)
  %t470 = inttoptr i64 34 to ptr
  %t471 = getelementptr ptr, ptr %t469, i32 0
  store ptr %t470, ptr %t471
  %t472 = getelementptr ptr, ptr %t413, i32 1
  %t473 = load ptr, ptr %t472
  call void @__free_recursive(ptr %t473)
  %t474 = getelementptr ptr, ptr %t413, i32 2
  %t475 = load ptr, ptr %t474
  call void @__free_recursive(ptr %t475)
  %t478 = inttoptr i64 66 to ptr
  %t479 = getelementptr ptr, ptr %t413, i32 0
  store ptr %t478, ptr %t479
  call void @__inc_ref(ptr %t415)
  %t476 = getelementptr ptr, ptr %t413, i32 1
  store ptr %t415, ptr %t476
  %t477 = getelementptr ptr, ptr %t413, i32 2
  store ptr %t469, ptr %t477
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t424)
  call void @__free_recursive(ptr %t422)
  call void @__free_recursive(ptr %t415)
  store ptr %t413, ptr %t3
  br label %tco.loop.0
tco.case.arm.30.480:
  %t481 = call ptr @__alloc(i64 16, i32 1)
  %t482 = inttoptr i64 33 to ptr
  %t483 = getelementptr ptr, ptr %t481, i32 0
  store ptr %t482, ptr %t483
  %t484 = getelementptr ptr, ptr %t422, i32 1
  %t485 = load ptr, ptr %t484
  call void @__inc_ref(ptr %t485)
  %t486 = getelementptr ptr, ptr %t481, i32 1
  store ptr %t485, ptr %t486
  %t487 = getelementptr ptr, ptr %t413, i32 1
  %t488 = load ptr, ptr %t487
  call void @__free_recursive(ptr %t488)
  %t489 = getelementptr ptr, ptr %t413, i32 2
  %t490 = load ptr, ptr %t489
  call void @__free_recursive(ptr %t490)
  %t493 = inttoptr i64 66 to ptr
  %t494 = getelementptr ptr, ptr %t413, i32 0
  store ptr %t493, ptr %t494
  call void @__inc_ref(ptr %t415)
  %t491 = getelementptr ptr, ptr %t413, i32 1
  store ptr %t415, ptr %t491
  %t492 = getelementptr ptr, ptr %t413, i32 2
  store ptr %t481, ptr %t492
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t424)
  call void @__free_recursive(ptr %t422)
  call void @__free_recursive(ptr %t415)
  store ptr %t413, ptr %t3
  br label %tco.loop.0
tco.case.arm.31.495:
  %t496 = call ptr @__alloc(i64 8, i32 0)
  %t497 = inttoptr i64 34 to ptr
  %t498 = getelementptr ptr, ptr %t496, i32 0
  store ptr %t497, ptr %t498
  %t499 = getelementptr ptr, ptr %t413, i32 1
  %t500 = load ptr, ptr %t499
  call void @__free_recursive(ptr %t500)
  %t501 = getelementptr ptr, ptr %t413, i32 2
  %t502 = load ptr, ptr %t501
  call void @__free_recursive(ptr %t502)
  %t505 = inttoptr i64 66 to ptr
  %t506 = getelementptr ptr, ptr %t413, i32 0
  store ptr %t505, ptr %t506
  call void @__inc_ref(ptr %t415)
  %t503 = getelementptr ptr, ptr %t413, i32 1
  store ptr %t415, ptr %t503
  %t504 = getelementptr ptr, ptr %t413, i32 2
  store ptr %t496, ptr %t504
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t424)
  call void @__free_recursive(ptr %t422)
  call void @__free_recursive(ptr %t415)
  store ptr %t413, ptr %t3
  br label %tco.loop.0
tco.case.arm.32.507:
  %t508 = getelementptr ptr, ptr %t424, i32 0
  %t509 = load ptr, ptr %t508
  %t510 = ptrtoint ptr %t509 to i64
  switch i64 %t510, label %case.default.511 [ i64 3, label %case.arm.3.513 i64 4, label %case.arm.4.521 ]
case.arm.3.513:
  %t515 = call ptr @__alloc(i64 16, i32 1)
  %t516 = inttoptr i64 6 to ptr
  %t517 = getelementptr ptr, ptr %t515, i32 0
  store ptr %t516, ptr %t517
  %t518 = getelementptr ptr, ptr %t424, i32 1
  %t519 = load ptr, ptr %t518
  call void @__inc_ref(ptr %t519)
  %t520 = getelementptr ptr, ptr %t515, i32 1
  store ptr %t519, ptr %t520
  br label %case.end.3.514
case.end.3.514:
  br label %case.join.512
case.arm.4.521:
  %t523 = call ptr @__alloc(i64 16, i32 1)
  %t524 = inttoptr i64 5 to ptr
  %t525 = getelementptr ptr, ptr %t523, i32 0
  store ptr %t524, ptr %t525
  %t526 = getelementptr ptr, ptr %t424, i32 1
  %t527 = load ptr, ptr %t526
  call void @__inc_ref(ptr %t527)
  %t528 = getelementptr ptr, ptr %t523, i32 1
  store ptr %t527, ptr %t528
  br label %case.end.4.522
case.end.4.522:
  br label %case.join.512
case.default.511:
  unreachable
case.join.512:
  %t529 = phi ptr [ %t515, %case.end.3.514 ], [ %t523, %case.end.4.522 ]
  %t530 = getelementptr ptr, ptr %t413, i32 1
  %t531 = load ptr, ptr %t530
  call void @__free_recursive(ptr %t531)
  %t532 = getelementptr ptr, ptr %t413, i32 2
  %t533 = load ptr, ptr %t532
  call void @__free_recursive(ptr %t533)
  %t536 = inttoptr i64 66 to ptr
  %t537 = getelementptr ptr, ptr %t413, i32 0
  store ptr %t536, ptr %t537
  call void @__inc_ref(ptr %t415)
  %t534 = getelementptr ptr, ptr %t413, i32 1
  store ptr %t415, ptr %t534
  %t535 = getelementptr ptr, ptr %t413, i32 2
  store ptr %t529, ptr %t535
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t424)
  call void @__free_recursive(ptr %t422)
  call void @__free_recursive(ptr %t415)
  store ptr %t413, ptr %t3
  br label %tco.loop.0
tco.case.arm.33.538:
  %t539 = getelementptr ptr, ptr %t422, i32 1
  %t540 = load ptr, ptr %t539
  call void @__inc_ref(ptr %t540)
  %t541 = getelementptr ptr, ptr %t413, i32 1
  %t542 = load ptr, ptr %t541
  call void @__free_recursive(ptr %t542)
  %t543 = getelementptr ptr, ptr %t413, i32 2
  %t544 = load ptr, ptr %t543
  call void @__free_recursive(ptr %t544)
  %t547 = inttoptr i64 66 to ptr
  %t548 = getelementptr ptr, ptr %t413, i32 0
  store ptr %t547, ptr %t548
  call void @__inc_ref(ptr %t415)
  %t545 = getelementptr ptr, ptr %t413, i32 1
  store ptr %t415, ptr %t545
  %t546 = getelementptr ptr, ptr %t413, i32 2
  store ptr %t540, ptr %t546
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t424)
  call void @__free_recursive(ptr %t422)
  call void @__free_recursive(ptr %t415)
  store ptr %t413, ptr %t3
  br label %tco.loop.0
tco.case.arm.34.549:
  %t550 = getelementptr ptr, ptr %t413, i32 1
  %t551 = load ptr, ptr %t550
  call void @__free_recursive(ptr %t551)
  %t553 = inttoptr i64 66 to ptr
  %t554 = getelementptr ptr, ptr %t413, i32 0
  store ptr %t553, ptr %t554
  call void @__inc_ref(ptr %t415)
  %t552 = getelementptr ptr, ptr %t413, i32 1
  store ptr %t415, ptr %t552
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t424)
  call void @__free_recursive(ptr %t422)
  call void @__free_recursive(ptr %t415)
  store ptr %t413, ptr %t3
  br label %tco.loop.0
tco.case.arm.35.555:
  %t556 = call ptr @__alloc(i64 16, i32 1)
  %t557 = inttoptr i64 31 to ptr
  %t558 = getelementptr ptr, ptr %t556, i32 0
  store ptr %t557, ptr %t558
  call void @__inc_ref(ptr %t424)
  %t559 = getelementptr ptr, ptr %t556, i32 1
  store ptr %t424, ptr %t559
  %t560 = getelementptr ptr, ptr %t413, i32 1
  %t561 = load ptr, ptr %t560
  call void @__free_recursive(ptr %t561)
  %t562 = getelementptr ptr, ptr %t413, i32 2
  %t563 = load ptr, ptr %t562
  call void @__free_recursive(ptr %t563)
  %t566 = inttoptr i64 66 to ptr
  %t567 = getelementptr ptr, ptr %t413, i32 0
  store ptr %t566, ptr %t567
  call void @__inc_ref(ptr %t415)
  %t564 = getelementptr ptr, ptr %t413, i32 1
  store ptr %t415, ptr %t564
  %t565 = getelementptr ptr, ptr %t413, i32 2
  store ptr %t556, ptr %t565
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t424)
  call void @__free_recursive(ptr %t422)
  call void @__free_recursive(ptr %t415)
  store ptr %t413, ptr %t3
  br label %tco.loop.0
tco.case.default.428:
  unreachable
tco.case.arm.37.568:
  %t569 = getelementptr ptr, ptr %t413, i32 1
  %t570 = load ptr, ptr %t569
  call void @__inc_ref(ptr %t570)
  %t571 = getelementptr ptr, ptr %t413, i32 2
  %t572 = load ptr, ptr %t571
  call void @__inc_ref(ptr %t572)
  %t573 = getelementptr ptr, ptr %t413, i32 3
  %t574 = load ptr, ptr %t573
  call void @__inc_ref(ptr %t574)
  %t575 = getelementptr ptr, ptr %t570, i32 0
  %t576 = load ptr, ptr %t575
  %t577 = ptrtoint ptr %t576 to i64
  switch i64 %t577, label %tco.case.default.578 [ i64 26, label %tco.case.arm.26.579 i64 27, label %tco.case.arm.27.600 i64 28, label %tco.case.arm.28.621 i64 29, label %tco.case.arm.29.642 i64 30, label %tco.case.arm.30.659 i64 31, label %tco.case.arm.31.679 i64 32, label %tco.case.arm.32.696 i64 33, label %tco.case.arm.33.732 i64 34, label %tco.case.arm.34.748 i64 35, label %tco.case.arm.35.762 ]
tco.case.arm.26.579:
  %t580 = call ptr @__alloc(i64 24, i32 2)
  %t581 = inttoptr i64 67 to ptr
  %t582 = getelementptr ptr, ptr %t580, i32 0
  store ptr %t581, ptr %t582
  %t583 = getelementptr ptr, ptr %t570, i32 1
  %t584 = load ptr, ptr %t583
  call void @__inc_ref(ptr %t584)
  %t585 = getelementptr ptr, ptr %t4, i32 1
  %t586 = load ptr, ptr %t585
  call void @__free_recursive(ptr %t586)
  %t587 = getelementptr ptr, ptr %t4, i32 2
  %t588 = load ptr, ptr %t587
  call void @__free_recursive(ptr %t588)
  %t591 = inttoptr i64 39 to ptr
  %t592 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t591, ptr %t592
  %t589 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t584, ptr %t589
  call void @__inc_ref(ptr %t572)
  %t590 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t572, ptr %t590
  %t593 = getelementptr ptr, ptr %t580, i32 1
  store ptr %t4, ptr %t593
  %t594 = call ptr @__alloc(i64 24, i32 2)
  %t595 = inttoptr i64 52 to ptr
  %t596 = getelementptr ptr, ptr %t594, i32 0
  store ptr %t595, ptr %t596
  call void @__inc_ref(ptr %t415)
  %t597 = getelementptr ptr, ptr %t594, i32 1
  store ptr %t415, ptr %t597
  call void @__inc_ref(ptr %t574)
  %t598 = getelementptr ptr, ptr %t594, i32 2
  store ptr %t574, ptr %t598
  %t599 = getelementptr ptr, ptr %t580, i32 2
  store ptr %t594, ptr %t599
  call void @__free_recursive(ptr %t574)
  call void @__free_recursive(ptr %t572)
  call void @__free_recursive(ptr %t570)
  call void @__free_recursive(ptr %t413)
  call void @__free_recursive(ptr %t415)
  store ptr %t580, ptr %t3
  br label %tco.loop.0
tco.case.arm.27.600:
  %t601 = call ptr @__alloc(i64 24, i32 2)
  %t602 = inttoptr i64 67 to ptr
  %t603 = getelementptr ptr, ptr %t601, i32 0
  store ptr %t602, ptr %t603
  %t604 = getelementptr ptr, ptr %t570, i32 1
  %t605 = load ptr, ptr %t604
  call void @__inc_ref(ptr %t605)
  %t606 = getelementptr ptr, ptr %t4, i32 1
  %t607 = load ptr, ptr %t606
  call void @__free_recursive(ptr %t607)
  %t608 = getelementptr ptr, ptr %t4, i32 2
  %t609 = load ptr, ptr %t608
  call void @__free_recursive(ptr %t609)
  %t612 = inttoptr i64 40 to ptr
  %t613 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t612, ptr %t613
  %t610 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t605, ptr %t610
  call void @__inc_ref(ptr %t572)
  %t611 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t572, ptr %t611
  %t614 = getelementptr ptr, ptr %t601, i32 1
  store ptr %t4, ptr %t614
  %t615 = call ptr @__alloc(i64 24, i32 2)
  %t616 = inttoptr i64 53 to ptr
  %t617 = getelementptr ptr, ptr %t615, i32 0
  store ptr %t616, ptr %t617
  call void @__inc_ref(ptr %t415)
  %t618 = getelementptr ptr, ptr %t615, i32 1
  store ptr %t415, ptr %t618
  call void @__inc_ref(ptr %t574)
  %t619 = getelementptr ptr, ptr %t615, i32 2
  store ptr %t574, ptr %t619
  %t620 = getelementptr ptr, ptr %t601, i32 2
  store ptr %t615, ptr %t620
  call void @__free_recursive(ptr %t574)
  call void @__free_recursive(ptr %t572)
  call void @__free_recursive(ptr %t570)
  call void @__free_recursive(ptr %t413)
  call void @__free_recursive(ptr %t415)
  store ptr %t601, ptr %t3
  br label %tco.loop.0
tco.case.arm.28.621:
  %t622 = call ptr @__alloc(i64 24, i32 2)
  %t623 = inttoptr i64 67 to ptr
  %t624 = getelementptr ptr, ptr %t622, i32 0
  store ptr %t623, ptr %t624
  %t625 = getelementptr ptr, ptr %t570, i32 1
  %t626 = load ptr, ptr %t625
  call void @__inc_ref(ptr %t626)
  %t627 = getelementptr ptr, ptr %t4, i32 1
  %t628 = load ptr, ptr %t627
  call void @__free_recursive(ptr %t628)
  %t629 = getelementptr ptr, ptr %t4, i32 2
  %t630 = load ptr, ptr %t629
  call void @__free_recursive(ptr %t630)
  %t633 = inttoptr i64 41 to ptr
  %t634 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t633, ptr %t634
  %t631 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t626, ptr %t631
  call void @__inc_ref(ptr %t572)
  %t632 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t572, ptr %t632
  %t635 = getelementptr ptr, ptr %t622, i32 1
  store ptr %t4, ptr %t635
  %t636 = call ptr @__alloc(i64 24, i32 2)
  %t637 = inttoptr i64 54 to ptr
  %t638 = getelementptr ptr, ptr %t636, i32 0
  store ptr %t637, ptr %t638
  call void @__inc_ref(ptr %t415)
  %t639 = getelementptr ptr, ptr %t636, i32 1
  store ptr %t415, ptr %t639
  call void @__inc_ref(ptr %t574)
  %t640 = getelementptr ptr, ptr %t636, i32 2
  store ptr %t574, ptr %t640
  %t641 = getelementptr ptr, ptr %t622, i32 2
  store ptr %t636, ptr %t641
  call void @__free_recursive(ptr %t574)
  call void @__free_recursive(ptr %t572)
  call void @__free_recursive(ptr %t570)
  call void @__free_recursive(ptr %t413)
  call void @__free_recursive(ptr %t415)
  store ptr %t622, ptr %t3
  br label %tco.loop.0
tco.case.arm.29.642:
  %t643 = call ptr @__alloc(i64 24, i32 2)
  %t644 = inttoptr i64 67 to ptr
  %t645 = getelementptr ptr, ptr %t643, i32 0
  store ptr %t644, ptr %t645
  %t646 = call ptr @__alloc(i64 8, i32 0)
  %t647 = inttoptr i64 34 to ptr
  %t648 = getelementptr ptr, ptr %t646, i32 0
  store ptr %t647, ptr %t648
  %t649 = getelementptr ptr, ptr %t4, i32 1
  %t650 = load ptr, ptr %t649
  call void @__free_recursive(ptr %t650)
  %t651 = getelementptr ptr, ptr %t4, i32 2
  %t652 = load ptr, ptr %t651
  call void @__free_recursive(ptr %t652)
  %t655 = inttoptr i64 36 to ptr
  %t656 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t655, ptr %t656
  %t653 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t646, ptr %t653
  call void @__inc_ref(ptr %t574)
  %t654 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t574, ptr %t654
  %t657 = getelementptr ptr, ptr %t643, i32 1
  store ptr %t4, ptr %t657
  call void @__inc_ref(ptr %t415)
  %t658 = getelementptr ptr, ptr %t643, i32 2
  store ptr %t415, ptr %t658
  call void @__free_recursive(ptr %t574)
  call void @__free_recursive(ptr %t572)
  call void @__free_recursive(ptr %t570)
  call void @__free_recursive(ptr %t413)
  call void @__free_recursive(ptr %t415)
  store ptr %t643, ptr %t3
  br label %tco.loop.0
tco.case.arm.30.659:
  %t660 = call ptr @__alloc(i64 24, i32 2)
  %t661 = inttoptr i64 67 to ptr
  %t662 = getelementptr ptr, ptr %t660, i32 0
  store ptr %t661, ptr %t662
  %t663 = call ptr @__alloc(i64 16, i32 1)
  %t664 = inttoptr i64 33 to ptr
  %t665 = getelementptr ptr, ptr %t663, i32 0
  store ptr %t664, ptr %t665
  %t666 = getelementptr ptr, ptr %t570, i32 1
  %t667 = load ptr, ptr %t666
  call void @__inc_ref(ptr %t667)
  %t668 = getelementptr ptr, ptr %t663, i32 1
  store ptr %t667, ptr %t668
  %t669 = getelementptr ptr, ptr %t4, i32 1
  %t670 = load ptr, ptr %t669
  call void @__free_recursive(ptr %t670)
  %t671 = getelementptr ptr, ptr %t4, i32 2
  %t672 = load ptr, ptr %t671
  call void @__free_recursive(ptr %t672)
  %t675 = inttoptr i64 36 to ptr
  %t676 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t675, ptr %t676
  %t673 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t663, ptr %t673
  call void @__inc_ref(ptr %t574)
  %t674 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t574, ptr %t674
  %t677 = getelementptr ptr, ptr %t660, i32 1
  store ptr %t4, ptr %t677
  call void @__inc_ref(ptr %t415)
  %t678 = getelementptr ptr, ptr %t660, i32 2
  store ptr %t415, ptr %t678
  call void @__free_recursive(ptr %t574)
  call void @__free_recursive(ptr %t572)
  call void @__free_recursive(ptr %t570)
  call void @__free_recursive(ptr %t413)
  call void @__free_recursive(ptr %t415)
  store ptr %t660, ptr %t3
  br label %tco.loop.0
tco.case.arm.31.679:
  %t680 = call ptr @__alloc(i64 24, i32 2)
  %t681 = inttoptr i64 67 to ptr
  %t682 = getelementptr ptr, ptr %t680, i32 0
  store ptr %t681, ptr %t682
  %t683 = call ptr @__alloc(i64 8, i32 0)
  %t684 = inttoptr i64 34 to ptr
  %t685 = getelementptr ptr, ptr %t683, i32 0
  store ptr %t684, ptr %t685
  %t686 = getelementptr ptr, ptr %t4, i32 1
  %t687 = load ptr, ptr %t686
  call void @__free_recursive(ptr %t687)
  %t688 = getelementptr ptr, ptr %t4, i32 2
  %t689 = load ptr, ptr %t688
  call void @__free_recursive(ptr %t689)
  %t692 = inttoptr i64 36 to ptr
  %t693 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t692, ptr %t693
  %t690 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t683, ptr %t690
  call void @__inc_ref(ptr %t574)
  %t691 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t574, ptr %t691
  %t694 = getelementptr ptr, ptr %t680, i32 1
  store ptr %t4, ptr %t694
  call void @__inc_ref(ptr %t415)
  %t695 = getelementptr ptr, ptr %t680, i32 2
  store ptr %t415, ptr %t695
  call void @__free_recursive(ptr %t574)
  call void @__free_recursive(ptr %t572)
  call void @__free_recursive(ptr %t570)
  call void @__free_recursive(ptr %t413)
  call void @__free_recursive(ptr %t415)
  store ptr %t680, ptr %t3
  br label %tco.loop.0
tco.case.arm.32.696:
  %t697 = call ptr @__alloc(i64 24, i32 2)
  %t698 = inttoptr i64 67 to ptr
  %t699 = getelementptr ptr, ptr %t697, i32 0
  store ptr %t698, ptr %t699
  %t700 = getelementptr ptr, ptr %t572, i32 0
  %t701 = load ptr, ptr %t700
  %t702 = ptrtoint ptr %t701 to i64
  switch i64 %t702, label %case.default.703 [ i64 3, label %case.arm.3.705 i64 4, label %case.arm.4.713 ]
case.arm.3.705:
  %t707 = call ptr @__alloc(i64 16, i32 1)
  %t708 = inttoptr i64 6 to ptr
  %t709 = getelementptr ptr, ptr %t707, i32 0
  store ptr %t708, ptr %t709
  %t710 = getelementptr ptr, ptr %t572, i32 1
  %t711 = load ptr, ptr %t710
  call void @__inc_ref(ptr %t711)
  %t712 = getelementptr ptr, ptr %t707, i32 1
  store ptr %t711, ptr %t712
  br label %case.end.3.706
case.end.3.706:
  br label %case.join.704
case.arm.4.713:
  %t715 = call ptr @__alloc(i64 16, i32 1)
  %t716 = inttoptr i64 5 to ptr
  %t717 = getelementptr ptr, ptr %t715, i32 0
  store ptr %t716, ptr %t717
  %t718 = getelementptr ptr, ptr %t572, i32 1
  %t719 = load ptr, ptr %t718
  call void @__inc_ref(ptr %t719)
  %t720 = getelementptr ptr, ptr %t715, i32 1
  store ptr %t719, ptr %t720
  br label %case.end.4.714
case.end.4.714:
  br label %case.join.704
case.default.703:
  unreachable
case.join.704:
  %t721 = phi ptr [ %t707, %case.end.3.706 ], [ %t715, %case.end.4.714 ]
  %t722 = getelementptr ptr, ptr %t4, i32 1
  %t723 = load ptr, ptr %t722
  call void @__free_recursive(ptr %t723)
  %t724 = getelementptr ptr, ptr %t4, i32 2
  %t725 = load ptr, ptr %t724
  call void @__free_recursive(ptr %t725)
  %t728 = inttoptr i64 36 to ptr
  %t729 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t728, ptr %t729
  %t726 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t721, ptr %t726
  call void @__inc_ref(ptr %t574)
  %t727 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t574, ptr %t727
  %t730 = getelementptr ptr, ptr %t697, i32 1
  store ptr %t4, ptr %t730
  call void @__inc_ref(ptr %t415)
  %t731 = getelementptr ptr, ptr %t697, i32 2
  store ptr %t415, ptr %t731
  call void @__free_recursive(ptr %t574)
  call void @__free_recursive(ptr %t572)
  call void @__free_recursive(ptr %t570)
  call void @__free_recursive(ptr %t413)
  call void @__free_recursive(ptr %t415)
  store ptr %t697, ptr %t3
  br label %tco.loop.0
tco.case.arm.33.732:
  %t733 = call ptr @__alloc(i64 24, i32 2)
  %t734 = inttoptr i64 67 to ptr
  %t735 = getelementptr ptr, ptr %t733, i32 0
  store ptr %t734, ptr %t735
  %t736 = getelementptr ptr, ptr %t570, i32 1
  %t737 = load ptr, ptr %t736
  call void @__inc_ref(ptr %t737)
  %t738 = getelementptr ptr, ptr %t4, i32 1
  %t739 = load ptr, ptr %t738
  call void @__free_recursive(ptr %t739)
  %t740 = getelementptr ptr, ptr %t4, i32 2
  %t741 = load ptr, ptr %t740
  call void @__free_recursive(ptr %t741)
  %t744 = inttoptr i64 36 to ptr
  %t745 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t744, ptr %t745
  %t742 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t737, ptr %t742
  call void @__inc_ref(ptr %t574)
  %t743 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t574, ptr %t743
  %t746 = getelementptr ptr, ptr %t733, i32 1
  store ptr %t4, ptr %t746
  call void @__inc_ref(ptr %t415)
  %t747 = getelementptr ptr, ptr %t733, i32 2
  store ptr %t415, ptr %t747
  call void @__free_recursive(ptr %t574)
  call void @__free_recursive(ptr %t572)
  call void @__free_recursive(ptr %t570)
  call void @__free_recursive(ptr %t413)
  call void @__free_recursive(ptr %t415)
  store ptr %t733, ptr %t3
  br label %tco.loop.0
tco.case.arm.34.748:
  %t749 = call ptr @__alloc(i64 24, i32 2)
  %t750 = inttoptr i64 67 to ptr
  %t751 = getelementptr ptr, ptr %t749, i32 0
  store ptr %t750, ptr %t751
  %t752 = getelementptr ptr, ptr %t4, i32 1
  %t753 = load ptr, ptr %t752
  call void @__free_recursive(ptr %t753)
  %t754 = getelementptr ptr, ptr %t4, i32 2
  %t755 = load ptr, ptr %t754
  call void @__free_recursive(ptr %t755)
  %t758 = inttoptr i64 36 to ptr
  %t759 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t758, ptr %t759
  call void @__inc_ref(ptr %t572)
  %t756 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t572, ptr %t756
  call void @__inc_ref(ptr %t574)
  %t757 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t574, ptr %t757
  %t760 = getelementptr ptr, ptr %t749, i32 1
  store ptr %t4, ptr %t760
  call void @__inc_ref(ptr %t415)
  %t761 = getelementptr ptr, ptr %t749, i32 2
  store ptr %t415, ptr %t761
  call void @__free_recursive(ptr %t574)
  call void @__free_recursive(ptr %t572)
  call void @__free_recursive(ptr %t570)
  call void @__free_recursive(ptr %t413)
  call void @__free_recursive(ptr %t415)
  store ptr %t749, ptr %t3
  br label %tco.loop.0
tco.case.arm.35.762:
  %t763 = call ptr @__alloc(i64 8, i32 0)
  %t764 = inttoptr i64 34 to ptr
  %t765 = getelementptr ptr, ptr %t763, i32 0
  store ptr %t764, ptr %t765
  %t766 = getelementptr ptr, ptr %t4, i32 1
  %t767 = load ptr, ptr %t766
  call void @__free_recursive(ptr %t767)
  %t768 = getelementptr ptr, ptr %t4, i32 2
  %t769 = load ptr, ptr %t768
  call void @__free_recursive(ptr %t769)
  %t772 = inttoptr i64 66 to ptr
  %t773 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t772, ptr %t773
  call void @__inc_ref(ptr %t415)
  %t770 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t415, ptr %t770
  %t771 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t763, ptr %t771
  call void @__free_recursive(ptr %t574)
  call void @__free_recursive(ptr %t572)
  call void @__free_recursive(ptr %t570)
  call void @__free_recursive(ptr %t413)
  call void @__free_recursive(ptr %t415)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.578:
  unreachable
tco.case.arm.38.774:
  %t775 = getelementptr ptr, ptr %t413, i32 1
  %t776 = load ptr, ptr %t775
  call void @__inc_ref(ptr %t776)
  %t777 = getelementptr ptr, ptr %t413, i32 2
  %t778 = load ptr, ptr %t777
  call void @__inc_ref(ptr %t778)
  %t779 = getelementptr ptr, ptr %t413, i32 3
  %t780 = load ptr, ptr %t779
  call void @__inc_ref(ptr %t780)
  %t781 = getelementptr ptr, ptr %t413, i32 4
  %t782 = load ptr, ptr %t781
  call void @__inc_ref(ptr %t782)
  %t783 = getelementptr ptr, ptr %t776, i32 0
  %t784 = load ptr, ptr %t783
  %t785 = ptrtoint ptr %t784 to i64
  switch i64 %t785, label %tco.case.default.786 [ i64 26, label %tco.case.arm.26.787 i64 27, label %tco.case.arm.27.809 i64 28, label %tco.case.arm.28.831 i64 29, label %tco.case.arm.29.853 i64 30, label %tco.case.arm.30.868 i64 31, label %tco.case.arm.31.886 i64 32, label %tco.case.arm.32.901 i64 33, label %tco.case.arm.33.935 i64 34, label %tco.case.arm.34.949 i64 35, label %tco.case.arm.35.961 ]
tco.case.arm.26.787:
  %t788 = call ptr @__alloc(i64 24, i32 2)
  %t789 = inttoptr i64 67 to ptr
  %t790 = getelementptr ptr, ptr %t788, i32 0
  store ptr %t789, ptr %t790
  %t791 = getelementptr ptr, ptr %t776, i32 1
  %t792 = load ptr, ptr %t791
  call void @__inc_ref(ptr %t792)
  %t793 = getelementptr ptr, ptr %t4, i32 1
  %t794 = load ptr, ptr %t793
  call void @__free_recursive(ptr %t794)
  %t795 = getelementptr ptr, ptr %t4, i32 2
  %t796 = load ptr, ptr %t795
  call void @__free_recursive(ptr %t796)
  %t799 = inttoptr i64 39 to ptr
  %t800 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t799, ptr %t800
  %t797 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t792, ptr %t797
  call void @__inc_ref(ptr %t778)
  %t798 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t778, ptr %t798
  %t801 = getelementptr ptr, ptr %t788, i32 1
  store ptr %t4, ptr %t801
  %t802 = call ptr @__alloc(i64 32, i32 3)
  %t803 = inttoptr i64 55 to ptr
  %t804 = getelementptr ptr, ptr %t802, i32 0
  store ptr %t803, ptr %t804
  call void @__inc_ref(ptr %t415)
  %t805 = getelementptr ptr, ptr %t802, i32 1
  store ptr %t415, ptr %t805
  call void @__inc_ref(ptr %t780)
  %t806 = getelementptr ptr, ptr %t802, i32 2
  store ptr %t780, ptr %t806
  call void @__inc_ref(ptr %t782)
  %t807 = getelementptr ptr, ptr %t802, i32 3
  store ptr %t782, ptr %t807
  %t808 = getelementptr ptr, ptr %t788, i32 2
  store ptr %t802, ptr %t808
  call void @__free_recursive(ptr %t782)
  call void @__free_recursive(ptr %t780)
  call void @__free_recursive(ptr %t778)
  call void @__free_recursive(ptr %t776)
  call void @__free_recursive(ptr %t413)
  call void @__free_recursive(ptr %t415)
  store ptr %t788, ptr %t3
  br label %tco.loop.0
tco.case.arm.27.809:
  %t810 = call ptr @__alloc(i64 24, i32 2)
  %t811 = inttoptr i64 67 to ptr
  %t812 = getelementptr ptr, ptr %t810, i32 0
  store ptr %t811, ptr %t812
  %t813 = getelementptr ptr, ptr %t776, i32 1
  %t814 = load ptr, ptr %t813
  call void @__inc_ref(ptr %t814)
  %t815 = getelementptr ptr, ptr %t4, i32 1
  %t816 = load ptr, ptr %t815
  call void @__free_recursive(ptr %t816)
  %t817 = getelementptr ptr, ptr %t4, i32 2
  %t818 = load ptr, ptr %t817
  call void @__free_recursive(ptr %t818)
  %t821 = inttoptr i64 40 to ptr
  %t822 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t821, ptr %t822
  %t819 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t814, ptr %t819
  call void @__inc_ref(ptr %t778)
  %t820 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t778, ptr %t820
  %t823 = getelementptr ptr, ptr %t810, i32 1
  store ptr %t4, ptr %t823
  %t824 = call ptr @__alloc(i64 32, i32 3)
  %t825 = inttoptr i64 56 to ptr
  %t826 = getelementptr ptr, ptr %t824, i32 0
  store ptr %t825, ptr %t826
  call void @__inc_ref(ptr %t415)
  %t827 = getelementptr ptr, ptr %t824, i32 1
  store ptr %t415, ptr %t827
  call void @__inc_ref(ptr %t780)
  %t828 = getelementptr ptr, ptr %t824, i32 2
  store ptr %t780, ptr %t828
  call void @__inc_ref(ptr %t782)
  %t829 = getelementptr ptr, ptr %t824, i32 3
  store ptr %t782, ptr %t829
  %t830 = getelementptr ptr, ptr %t810, i32 2
  store ptr %t824, ptr %t830
  call void @__free_recursive(ptr %t782)
  call void @__free_recursive(ptr %t780)
  call void @__free_recursive(ptr %t778)
  call void @__free_recursive(ptr %t776)
  call void @__free_recursive(ptr %t413)
  call void @__free_recursive(ptr %t415)
  store ptr %t810, ptr %t3
  br label %tco.loop.0
tco.case.arm.28.831:
  %t832 = call ptr @__alloc(i64 24, i32 2)
  %t833 = inttoptr i64 67 to ptr
  %t834 = getelementptr ptr, ptr %t832, i32 0
  store ptr %t833, ptr %t834
  %t835 = getelementptr ptr, ptr %t776, i32 1
  %t836 = load ptr, ptr %t835
  call void @__inc_ref(ptr %t836)
  %t837 = getelementptr ptr, ptr %t4, i32 1
  %t838 = load ptr, ptr %t837
  call void @__free_recursive(ptr %t838)
  %t839 = getelementptr ptr, ptr %t4, i32 2
  %t840 = load ptr, ptr %t839
  call void @__free_recursive(ptr %t840)
  %t843 = inttoptr i64 41 to ptr
  %t844 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t843, ptr %t844
  %t841 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t836, ptr %t841
  call void @__inc_ref(ptr %t778)
  %t842 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t778, ptr %t842
  %t845 = getelementptr ptr, ptr %t832, i32 1
  store ptr %t4, ptr %t845
  %t846 = call ptr @__alloc(i64 32, i32 3)
  %t847 = inttoptr i64 57 to ptr
  %t848 = getelementptr ptr, ptr %t846, i32 0
  store ptr %t847, ptr %t848
  call void @__inc_ref(ptr %t415)
  %t849 = getelementptr ptr, ptr %t846, i32 1
  store ptr %t415, ptr %t849
  call void @__inc_ref(ptr %t780)
  %t850 = getelementptr ptr, ptr %t846, i32 2
  store ptr %t780, ptr %t850
  call void @__inc_ref(ptr %t782)
  %t851 = getelementptr ptr, ptr %t846, i32 3
  store ptr %t782, ptr %t851
  %t852 = getelementptr ptr, ptr %t832, i32 2
  store ptr %t846, ptr %t852
  call void @__free_recursive(ptr %t782)
  call void @__free_recursive(ptr %t780)
  call void @__free_recursive(ptr %t778)
  call void @__free_recursive(ptr %t776)
  call void @__free_recursive(ptr %t413)
  call void @__free_recursive(ptr %t415)
  store ptr %t832, ptr %t3
  br label %tco.loop.0
tco.case.arm.29.853:
  %t854 = call ptr @__alloc(i64 32, i32 3)
  %t855 = inttoptr i64 37 to ptr
  %t856 = getelementptr ptr, ptr %t854, i32 0
  store ptr %t855, ptr %t856
  %t857 = call ptr @__alloc(i64 8, i32 0)
  %t858 = inttoptr i64 34 to ptr
  %t859 = getelementptr ptr, ptr %t857, i32 0
  store ptr %t858, ptr %t859
  %t860 = getelementptr ptr, ptr %t854, i32 1
  store ptr %t857, ptr %t860
  call void @__inc_ref(ptr %t780)
  %t861 = getelementptr ptr, ptr %t854, i32 2
  store ptr %t780, ptr %t861
  call void @__inc_ref(ptr %t782)
  %t862 = getelementptr ptr, ptr %t854, i32 3
  store ptr %t782, ptr %t862
  %t863 = getelementptr ptr, ptr %t4, i32 1
  %t864 = load ptr, ptr %t863
  call void @__free_recursive(ptr %t864)
  %t866 = inttoptr i64 67 to ptr
  %t867 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t866, ptr %t867
  %t865 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t854, ptr %t865
  call void @__free_recursive(ptr %t782)
  call void @__free_recursive(ptr %t780)
  call void @__free_recursive(ptr %t778)
  call void @__free_recursive(ptr %t776)
  call void @__free_recursive(ptr %t413)
  call void @__free_recursive(ptr %t415)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.30.868:
  %t869 = call ptr @__alloc(i64 32, i32 3)
  %t870 = inttoptr i64 37 to ptr
  %t871 = getelementptr ptr, ptr %t869, i32 0
  store ptr %t870, ptr %t871
  %t872 = call ptr @__alloc(i64 16, i32 1)
  %t873 = inttoptr i64 33 to ptr
  %t874 = getelementptr ptr, ptr %t872, i32 0
  store ptr %t873, ptr %t874
  %t875 = getelementptr ptr, ptr %t776, i32 1
  %t876 = load ptr, ptr %t875
  call void @__inc_ref(ptr %t876)
  %t877 = getelementptr ptr, ptr %t872, i32 1
  store ptr %t876, ptr %t877
  %t878 = getelementptr ptr, ptr %t869, i32 1
  store ptr %t872, ptr %t878
  call void @__inc_ref(ptr %t780)
  %t879 = getelementptr ptr, ptr %t869, i32 2
  store ptr %t780, ptr %t879
  call void @__inc_ref(ptr %t782)
  %t880 = getelementptr ptr, ptr %t869, i32 3
  store ptr %t782, ptr %t880
  %t881 = getelementptr ptr, ptr %t4, i32 1
  %t882 = load ptr, ptr %t881
  call void @__free_recursive(ptr %t882)
  %t884 = inttoptr i64 67 to ptr
  %t885 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t884, ptr %t885
  %t883 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t869, ptr %t883
  call void @__free_recursive(ptr %t782)
  call void @__free_recursive(ptr %t780)
  call void @__free_recursive(ptr %t778)
  call void @__free_recursive(ptr %t776)
  call void @__free_recursive(ptr %t413)
  call void @__free_recursive(ptr %t415)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.31.886:
  %t887 = call ptr @__alloc(i64 32, i32 3)
  %t888 = inttoptr i64 37 to ptr
  %t889 = getelementptr ptr, ptr %t887, i32 0
  store ptr %t888, ptr %t889
  %t890 = call ptr @__alloc(i64 8, i32 0)
  %t891 = inttoptr i64 34 to ptr
  %t892 = getelementptr ptr, ptr %t890, i32 0
  store ptr %t891, ptr %t892
  %t893 = getelementptr ptr, ptr %t887, i32 1
  store ptr %t890, ptr %t893
  call void @__inc_ref(ptr %t780)
  %t894 = getelementptr ptr, ptr %t887, i32 2
  store ptr %t780, ptr %t894
  call void @__inc_ref(ptr %t782)
  %t895 = getelementptr ptr, ptr %t887, i32 3
  store ptr %t782, ptr %t895
  %t896 = getelementptr ptr, ptr %t4, i32 1
  %t897 = load ptr, ptr %t896
  call void @__free_recursive(ptr %t897)
  %t899 = inttoptr i64 67 to ptr
  %t900 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t899, ptr %t900
  %t898 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t887, ptr %t898
  call void @__free_recursive(ptr %t782)
  call void @__free_recursive(ptr %t780)
  call void @__free_recursive(ptr %t778)
  call void @__free_recursive(ptr %t776)
  call void @__free_recursive(ptr %t413)
  call void @__free_recursive(ptr %t415)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.32.901:
  %t902 = call ptr @__alloc(i64 32, i32 3)
  %t903 = inttoptr i64 37 to ptr
  %t904 = getelementptr ptr, ptr %t902, i32 0
  store ptr %t903, ptr %t904
  %t905 = getelementptr ptr, ptr %t778, i32 0
  %t906 = load ptr, ptr %t905
  %t907 = ptrtoint ptr %t906 to i64
  switch i64 %t907, label %case.default.908 [ i64 3, label %case.arm.3.910 i64 4, label %case.arm.4.918 ]
case.arm.3.910:
  %t912 = call ptr @__alloc(i64 16, i32 1)
  %t913 = inttoptr i64 6 to ptr
  %t914 = getelementptr ptr, ptr %t912, i32 0
  store ptr %t913, ptr %t914
  %t915 = getelementptr ptr, ptr %t778, i32 1
  %t916 = load ptr, ptr %t915
  call void @__inc_ref(ptr %t916)
  %t917 = getelementptr ptr, ptr %t912, i32 1
  store ptr %t916, ptr %t917
  br label %case.end.3.911
case.end.3.911:
  br label %case.join.909
case.arm.4.918:
  %t920 = call ptr @__alloc(i64 16, i32 1)
  %t921 = inttoptr i64 5 to ptr
  %t922 = getelementptr ptr, ptr %t920, i32 0
  store ptr %t921, ptr %t922
  %t923 = getelementptr ptr, ptr %t778, i32 1
  %t924 = load ptr, ptr %t923
  call void @__inc_ref(ptr %t924)
  %t925 = getelementptr ptr, ptr %t920, i32 1
  store ptr %t924, ptr %t925
  br label %case.end.4.919
case.end.4.919:
  br label %case.join.909
case.default.908:
  unreachable
case.join.909:
  %t926 = phi ptr [ %t912, %case.end.3.911 ], [ %t920, %case.end.4.919 ]
  %t927 = getelementptr ptr, ptr %t902, i32 1
  store ptr %t926, ptr %t927
  call void @__inc_ref(ptr %t780)
  %t928 = getelementptr ptr, ptr %t902, i32 2
  store ptr %t780, ptr %t928
  call void @__inc_ref(ptr %t782)
  %t929 = getelementptr ptr, ptr %t902, i32 3
  store ptr %t782, ptr %t929
  %t930 = getelementptr ptr, ptr %t4, i32 1
  %t931 = load ptr, ptr %t930
  call void @__free_recursive(ptr %t931)
  %t933 = inttoptr i64 67 to ptr
  %t934 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t933, ptr %t934
  %t932 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t902, ptr %t932
  call void @__free_recursive(ptr %t782)
  call void @__free_recursive(ptr %t780)
  call void @__free_recursive(ptr %t778)
  call void @__free_recursive(ptr %t776)
  call void @__free_recursive(ptr %t413)
  call void @__free_recursive(ptr %t415)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.33.935:
  %t936 = call ptr @__alloc(i64 32, i32 3)
  %t937 = inttoptr i64 37 to ptr
  %t938 = getelementptr ptr, ptr %t936, i32 0
  store ptr %t937, ptr %t938
  %t939 = getelementptr ptr, ptr %t776, i32 1
  %t940 = load ptr, ptr %t939
  call void @__inc_ref(ptr %t940)
  %t941 = getelementptr ptr, ptr %t936, i32 1
  store ptr %t940, ptr %t941
  call void @__inc_ref(ptr %t780)
  %t942 = getelementptr ptr, ptr %t936, i32 2
  store ptr %t780, ptr %t942
  call void @__inc_ref(ptr %t782)
  %t943 = getelementptr ptr, ptr %t936, i32 3
  store ptr %t782, ptr %t943
  %t944 = getelementptr ptr, ptr %t4, i32 1
  %t945 = load ptr, ptr %t944
  call void @__free_recursive(ptr %t945)
  %t947 = inttoptr i64 67 to ptr
  %t948 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t947, ptr %t948
  %t946 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t936, ptr %t946
  call void @__free_recursive(ptr %t782)
  call void @__free_recursive(ptr %t780)
  call void @__free_recursive(ptr %t778)
  call void @__free_recursive(ptr %t776)
  call void @__free_recursive(ptr %t413)
  call void @__free_recursive(ptr %t415)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.34.949:
  %t950 = call ptr @__alloc(i64 32, i32 3)
  %t951 = inttoptr i64 37 to ptr
  %t952 = getelementptr ptr, ptr %t950, i32 0
  store ptr %t951, ptr %t952
  call void @__inc_ref(ptr %t778)
  %t953 = getelementptr ptr, ptr %t950, i32 1
  store ptr %t778, ptr %t953
  call void @__inc_ref(ptr %t780)
  %t954 = getelementptr ptr, ptr %t950, i32 2
  store ptr %t780, ptr %t954
  call void @__inc_ref(ptr %t782)
  %t955 = getelementptr ptr, ptr %t950, i32 3
  store ptr %t782, ptr %t955
  %t956 = getelementptr ptr, ptr %t4, i32 1
  %t957 = load ptr, ptr %t956
  call void @__free_recursive(ptr %t957)
  %t959 = inttoptr i64 67 to ptr
  %t960 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t959, ptr %t960
  %t958 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t950, ptr %t958
  call void @__free_recursive(ptr %t782)
  call void @__free_recursive(ptr %t780)
  call void @__free_recursive(ptr %t778)
  call void @__free_recursive(ptr %t776)
  call void @__free_recursive(ptr %t413)
  call void @__free_recursive(ptr %t415)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.35.961:
  %t962 = call ptr @__alloc(i64 24, i32 2)
  %t963 = inttoptr i64 67 to ptr
  %t964 = getelementptr ptr, ptr %t962, i32 0
  store ptr %t963, ptr %t964
  %t965 = call ptr @__alloc(i64 8, i32 0)
  %t966 = inttoptr i64 34 to ptr
  %t967 = getelementptr ptr, ptr %t965, i32 0
  store ptr %t966, ptr %t967
  %t968 = getelementptr ptr, ptr %t4, i32 1
  %t969 = load ptr, ptr %t968
  call void @__free_recursive(ptr %t969)
  %t970 = getelementptr ptr, ptr %t4, i32 2
  %t971 = load ptr, ptr %t970
  call void @__free_recursive(ptr %t971)
  %t974 = inttoptr i64 36 to ptr
  %t975 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t974, ptr %t975
  %t972 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t965, ptr %t972
  call void @__inc_ref(ptr %t782)
  %t973 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t782, ptr %t973
  %t976 = getelementptr ptr, ptr %t962, i32 1
  store ptr %t4, ptr %t976
  call void @__inc_ref(ptr %t415)
  %t977 = getelementptr ptr, ptr %t962, i32 2
  store ptr %t415, ptr %t977
  call void @__free_recursive(ptr %t782)
  call void @__free_recursive(ptr %t780)
  call void @__free_recursive(ptr %t778)
  call void @__free_recursive(ptr %t776)
  call void @__free_recursive(ptr %t413)
  call void @__free_recursive(ptr %t415)
  store ptr %t962, ptr %t3
  br label %tco.loop.0
tco.case.default.786:
  unreachable
tco.case.arm.39.978:
  %t979 = getelementptr ptr, ptr %t413, i32 1
  %t980 = load ptr, ptr %t979
  %t981 = getelementptr ptr, ptr %t413, i32 2
  %t982 = load ptr, ptr %t981
  %t983 = call ptr @__alloc(i64 16, i32 1)
  %t984 = inttoptr i64 58 to ptr
  %t985 = getelementptr ptr, ptr %t983, i32 0
  store ptr %t984, ptr %t985
  call void @__inc_ref(ptr %t415)
  %t986 = getelementptr ptr, ptr %t983, i32 1
  store ptr %t415, ptr %t986
  %t987 = getelementptr ptr, ptr %t4, i32 1
  %t988 = load ptr, ptr %t987
  call void @__free_recursive(ptr %t988)
  %t989 = getelementptr ptr, ptr %t4, i32 2
  %t990 = load ptr, ptr %t989
  call void @__free_recursive(ptr %t990)
  %t995 = inttoptr i64 67 to ptr
  %t996 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t995, ptr %t996
  %t991 = inttoptr i64 36 to ptr
  %t992 = getelementptr ptr, ptr %t413, i32 0
  store ptr %t991, ptr %t992
  %t993 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t413, ptr %t993
  %t994 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t983, ptr %t994
  call void @__free_recursive(ptr %t415)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.40.997:
  %t998 = getelementptr ptr, ptr %t413, i32 1
  %t999 = load ptr, ptr %t998
  %t1000 = getelementptr ptr, ptr %t413, i32 2
  %t1001 = load ptr, ptr %t1000
  %t1002 = call ptr @__alloc(i64 16, i32 1)
  %t1003 = inttoptr i64 59 to ptr
  %t1004 = getelementptr ptr, ptr %t1002, i32 0
  store ptr %t1003, ptr %t1004
  call void @__inc_ref(ptr %t415)
  %t1005 = getelementptr ptr, ptr %t1002, i32 1
  store ptr %t415, ptr %t1005
  %t1006 = getelementptr ptr, ptr %t4, i32 1
  %t1007 = load ptr, ptr %t1006
  call void @__free_recursive(ptr %t1007)
  %t1008 = getelementptr ptr, ptr %t4, i32 2
  %t1009 = load ptr, ptr %t1008
  call void @__free_recursive(ptr %t1009)
  %t1014 = inttoptr i64 67 to ptr
  %t1015 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t1014, ptr %t1015
  %t1010 = inttoptr i64 36 to ptr
  %t1011 = getelementptr ptr, ptr %t413, i32 0
  store ptr %t1010, ptr %t1011
  %t1012 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t413, ptr %t1012
  %t1013 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t1002, ptr %t1013
  call void @__free_recursive(ptr %t415)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.41.1016:
  %t1017 = getelementptr ptr, ptr %t413, i32 1
  %t1018 = load ptr, ptr %t1017
  %t1019 = getelementptr ptr, ptr %t413, i32 2
  %t1020 = load ptr, ptr %t1019
  %t1021 = call ptr @__alloc(i64 16, i32 1)
  %t1022 = inttoptr i64 60 to ptr
  %t1023 = getelementptr ptr, ptr %t1021, i32 0
  store ptr %t1022, ptr %t1023
  call void @__inc_ref(ptr %t415)
  %t1024 = getelementptr ptr, ptr %t1021, i32 1
  store ptr %t415, ptr %t1024
  %t1025 = getelementptr ptr, ptr %t4, i32 1
  %t1026 = load ptr, ptr %t1025
  call void @__free_recursive(ptr %t1026)
  %t1027 = getelementptr ptr, ptr %t4, i32 2
  %t1028 = load ptr, ptr %t1027
  call void @__free_recursive(ptr %t1028)
  %t1033 = inttoptr i64 67 to ptr
  %t1034 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t1033, ptr %t1034
  %t1029 = inttoptr i64 36 to ptr
  %t1030 = getelementptr ptr, ptr %t413, i32 0
  store ptr %t1029, ptr %t1030
  %t1031 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t413, ptr %t1031
  %t1032 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t1021, ptr %t1032
  call void @__free_recursive(ptr %t415)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.42.1035:
  %t1036 = getelementptr ptr, ptr %t413, i32 1
  %t1037 = load ptr, ptr %t1036
  call void @__inc_ref(ptr %t1037)
  %t1038 = getelementptr ptr, ptr %t1037, i32 0
  %t1039 = load ptr, ptr %t1038
  %t1040 = ptrtoint ptr %t1039 to i64
  switch i64 %t1040, label %tco.case.default.1041 [ i64 5, label %tco.case.arm.5.1042 i64 6, label %tco.case.arm.6.1055 i64 7, label %tco.case.arm.7.1064 i64 8, label %tco.case.arm.8.1087 ]
tco.case.arm.5.1042:
  %t1043 = getelementptr ptr, ptr %t4, i32 1
  %t1044 = load ptr, ptr %t1043
  call void @__free_recursive(ptr %t1044)
  %t1053 = inttoptr i64 67 to ptr
  %t1054 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t1053, ptr %t1054
  %t1045 = getelementptr ptr, ptr %t1037, i32 1
  %t1046 = load ptr, ptr %t1045
  call void @__inc_ref(ptr %t1046)
  %t1047 = getelementptr ptr, ptr %t413, i32 1
  %t1048 = load ptr, ptr %t1047
  call void @__free_recursive(ptr %t1048)
  %t1050 = inttoptr i64 43 to ptr
  %t1051 = getelementptr ptr, ptr %t413, i32 0
  store ptr %t1050, ptr %t1051
  %t1049 = getelementptr ptr, ptr %t413, i32 1
  store ptr %t1046, ptr %t1049
  %t1052 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t413, ptr %t1052
  call void @__free_recursive(ptr %t1037)
  call void @__free_recursive(ptr %t415)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.6.1055:
  %t1056 = getelementptr ptr, ptr %t4, i32 1
  %t1057 = load ptr, ptr %t1056
  call void @__free_recursive(ptr %t1057)
  %t1058 = getelementptr ptr, ptr %t4, i32 2
  %t1059 = load ptr, ptr %t1058
  call void @__free_recursive(ptr %t1059)
  %t1062 = inttoptr i64 66 to ptr
  %t1063 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t1062, ptr %t1063
  call void @__inc_ref(ptr %t415)
  %t1060 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t415, ptr %t1060
  call void @__inc_ref(ptr %t1037)
  %t1061 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t1037, ptr %t1061
  call void @__free_recursive(ptr %t413)
  call void @__free_recursive(ptr %t1037)
  call void @__free_recursive(ptr %t415)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.7.1064:
  %t1065 = call ptr @__alloc(i64 24, i32 2)
  %t1066 = inttoptr i64 67 to ptr
  %t1067 = getelementptr ptr, ptr %t1065, i32 0
  store ptr %t1066, ptr %t1067
  %t1068 = getelementptr ptr, ptr %t1037, i32 2
  %t1069 = load ptr, ptr %t1068
  call void @__inc_ref(ptr %t1069)
  %t1070 = getelementptr ptr, ptr %t413, i32 1
  %t1071 = load ptr, ptr %t1070
  call void @__free_recursive(ptr %t1071)
  %t1073 = inttoptr i64 42 to ptr
  %t1074 = getelementptr ptr, ptr %t413, i32 0
  store ptr %t1073, ptr %t1074
  %t1072 = getelementptr ptr, ptr %t413, i32 1
  store ptr %t1069, ptr %t1072
  %t1075 = getelementptr ptr, ptr %t1065, i32 1
  store ptr %t413, ptr %t1075
  %t1076 = getelementptr ptr, ptr %t1037, i32 1
  %t1077 = load ptr, ptr %t1076
  call void @__inc_ref(ptr %t1077)
  %t1078 = getelementptr ptr, ptr %t4, i32 1
  %t1079 = load ptr, ptr %t1078
  call void @__free_recursive(ptr %t1079)
  %t1080 = getelementptr ptr, ptr %t4, i32 2
  %t1081 = load ptr, ptr %t1080
  call void @__free_recursive(ptr %t1081)
  %t1084 = inttoptr i64 61 to ptr
  %t1085 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t1084, ptr %t1085
  call void @__inc_ref(ptr %t415)
  %t1082 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t415, ptr %t1082
  %t1083 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t1077, ptr %t1083
  %t1086 = getelementptr ptr, ptr %t1065, i32 2
  store ptr %t4, ptr %t1086
  call void @__free_recursive(ptr %t1037)
  call void @__free_recursive(ptr %t415)
  store ptr %t1065, ptr %t3
  br label %tco.loop.0
tco.case.arm.8.1087:
  %t1088 = getelementptr ptr, ptr %t4, i32 1
  %t1089 = load ptr, ptr %t1088
  call void @__free_recursive(ptr %t1089)
  %t1090 = getelementptr ptr, ptr %t4, i32 2
  %t1091 = load ptr, ptr %t1090
  call void @__free_recursive(ptr %t1091)
  %t1105 = inttoptr i64 66 to ptr
  %t1106 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t1105, ptr %t1106
  call void @__inc_ref(ptr %t415)
  %t1092 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t415, ptr %t1092
  %t1093 = call ptr @__alloc(i64 16, i32 1)
  %t1094 = inttoptr i64 8 to ptr
  %t1095 = getelementptr ptr, ptr %t1093, i32 0
  store ptr %t1094, ptr %t1095
  %t1096 = getelementptr ptr, ptr %t1037, i32 1
  %t1097 = load ptr, ptr %t1096
  call void @__inc_ref(ptr %t1097)
  %t1098 = getelementptr ptr, ptr %t413, i32 1
  %t1099 = load ptr, ptr %t1098
  call void @__free_recursive(ptr %t1099)
  %t1101 = inttoptr i64 27 to ptr
  %t1102 = getelementptr ptr, ptr %t413, i32 0
  store ptr %t1101, ptr %t1102
  %t1100 = getelementptr ptr, ptr %t413, i32 1
  store ptr %t1097, ptr %t1100
  %t1103 = getelementptr ptr, ptr %t1093, i32 1
  store ptr %t413, ptr %t1103
  %t1104 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t1093, ptr %t1104
  call void @__free_recursive(ptr %t1037)
  call void @__free_recursive(ptr %t415)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.1041:
  unreachable
tco.case.arm.43.1107:
  %t1108 = getelementptr ptr, ptr %t413, i32 1
  %t1109 = load ptr, ptr %t1108
  %t1110 = call ptr @__alloc(i64 16, i32 1)
  %t1111 = inttoptr i64 62 to ptr
  %t1112 = getelementptr ptr, ptr %t1110, i32 0
  store ptr %t1111, ptr %t1112
  call void @__inc_ref(ptr %t415)
  %t1113 = getelementptr ptr, ptr %t1110, i32 1
  store ptr %t415, ptr %t1113
  %t1114 = getelementptr ptr, ptr %t4, i32 1
  %t1115 = load ptr, ptr %t1114
  call void @__free_recursive(ptr %t1115)
  %t1116 = getelementptr ptr, ptr %t4, i32 2
  %t1117 = load ptr, ptr %t1116
  call void @__free_recursive(ptr %t1117)
  %t1122 = inttoptr i64 67 to ptr
  %t1123 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t1122, ptr %t1123
  %t1118 = inttoptr i64 46 to ptr
  %t1119 = getelementptr ptr, ptr %t413, i32 0
  store ptr %t1118, ptr %t1119
  %t1120 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t413, ptr %t1120
  %t1121 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t1110, ptr %t1121
  call void @__free_recursive(ptr %t415)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.44.1124:
  %t1125 = getelementptr ptr, ptr %t413, i32 1
  %t1126 = load ptr, ptr %t1125
  call void @__inc_ref(ptr %t1126)
  %t1127 = getelementptr ptr, ptr %t413, i32 2
  %t1128 = load ptr, ptr %t1127
  call void @__inc_ref(ptr %t1128)
  %t1129 = call ptr @__alloc(i64 40, i32 4)
  %t1130 = inttoptr i64 38 to ptr
  %t1131 = getelementptr ptr, ptr %t1129, i32 0
  store ptr %t1130, ptr %t1131
  %t1132 = getelementptr ptr, ptr %t1126, i32 1
  %t1133 = load ptr, ptr %t1132
  call void @__inc_ref(ptr %t1133)
  %t1134 = getelementptr ptr, ptr %t1129, i32 1
  store ptr %t1133, ptr %t1134
  call void @__inc_ref(ptr %t1128)
  %t1135 = getelementptr ptr, ptr %t1129, i32 2
  store ptr %t1128, ptr %t1135
  call void @__inc_ref(ptr %t1128)
  %t1136 = getelementptr ptr, ptr %t1129, i32 3
  store ptr %t1128, ptr %t1136
  call void @__inc_ref(ptr %t1128)
  %t1137 = getelementptr ptr, ptr %t1129, i32 4
  store ptr %t1128, ptr %t1137
  %t1138 = getelementptr ptr, ptr %t413, i32 1
  %t1139 = load ptr, ptr %t1138
  call void @__free_recursive(ptr %t1139)
  %t1140 = getelementptr ptr, ptr %t413, i32 2
  %t1141 = load ptr, ptr %t1140
  call void @__free_recursive(ptr %t1141)
  %t1144 = inttoptr i64 67 to ptr
  %t1145 = getelementptr ptr, ptr %t413, i32 0
  store ptr %t1144, ptr %t1145
  %t1142 = getelementptr ptr, ptr %t413, i32 1
  store ptr %t1129, ptr %t1142
  call void @__inc_ref(ptr %t415)
  %t1143 = getelementptr ptr, ptr %t413, i32 2
  store ptr %t415, ptr %t1143
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t1128)
  call void @__free_recursive(ptr %t1126)
  call void @__free_recursive(ptr %t415)
  store ptr %t413, ptr %t3
  br label %tco.loop.0
tco.case.arm.45.1146:
  %t1147 = getelementptr ptr, ptr %t413, i32 1
  %t1148 = load ptr, ptr %t1147
  call void @__inc_ref(ptr %t1148)
  %t1149 = getelementptr ptr, ptr %t413, i32 2
  %t1150 = load ptr, ptr %t1149
  call void @__inc_ref(ptr %t1150)
  %t1151 = call ptr @__alloc(i64 32, i32 3)
  %t1152 = inttoptr i64 37 to ptr
  %t1153 = getelementptr ptr, ptr %t1151, i32 0
  store ptr %t1152, ptr %t1153
  %t1154 = getelementptr ptr, ptr %t1148, i32 1
  %t1155 = load ptr, ptr %t1154
  call void @__inc_ref(ptr %t1155)
  %t1156 = getelementptr ptr, ptr %t1151, i32 1
  store ptr %t1155, ptr %t1156
  call void @__inc_ref(ptr %t1150)
  %t1157 = getelementptr ptr, ptr %t1151, i32 2
  store ptr %t1150, ptr %t1157
  call void @__inc_ref(ptr %t1150)
  %t1158 = getelementptr ptr, ptr %t1151, i32 3
  store ptr %t1150, ptr %t1158
  %t1159 = getelementptr ptr, ptr %t413, i32 1
  %t1160 = load ptr, ptr %t1159
  call void @__free_recursive(ptr %t1160)
  %t1161 = getelementptr ptr, ptr %t413, i32 2
  %t1162 = load ptr, ptr %t1161
  call void @__free_recursive(ptr %t1162)
  %t1165 = inttoptr i64 67 to ptr
  %t1166 = getelementptr ptr, ptr %t413, i32 0
  store ptr %t1165, ptr %t1166
  %t1163 = getelementptr ptr, ptr %t413, i32 1
  store ptr %t1151, ptr %t1163
  call void @__inc_ref(ptr %t415)
  %t1164 = getelementptr ptr, ptr %t413, i32 2
  store ptr %t415, ptr %t1164
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t1150)
  call void @__free_recursive(ptr %t1148)
  call void @__free_recursive(ptr %t415)
  store ptr %t413, ptr %t3
  br label %tco.loop.0
tco.case.arm.46.1167:
  %t1168 = getelementptr ptr, ptr %t413, i32 1
  %t1169 = load ptr, ptr %t1168
  call void @__inc_ref(ptr %t1169)
  %t1171 = getelementptr ptr, ptr %t1169, i32 0
  %t1172 = load ptr, ptr %t1171
  %t1173 = ptrtoint ptr %t1172 to i64
  switch i64 %t1173, label %tco.case.default.1174 [ i64 13, label %tco.case.arm.13.1175 i64 14, label %tco.case.arm.14.1192 ]
tco.case.arm.13.1175:
  %t1176 = call ptr @__alloc(i64 24, i32 2)
  %t1177 = inttoptr i64 66 to ptr
  %t1178 = getelementptr ptr, ptr %t1176, i32 0
  store ptr %t1177, ptr %t1178
  call void @__inc_ref(ptr %t415)
  %t1179 = getelementptr ptr, ptr %t1176, i32 1
  store ptr %t415, ptr %t1179
  %t1180 = call ptr @__alloc(i64 16, i32 1)
  %t1181 = inttoptr i64 3 to ptr
  %t1182 = getelementptr ptr, ptr %t1180, i32 0
  store ptr %t1181, ptr %t1182
  %t1183 = call ptr @__alloc(i64 16, i32 1)
  %t1184 = inttoptr i64 2671988933 to ptr
  %t1185 = getelementptr ptr, ptr %t1183, i32 0
  store ptr %t1184, ptr %t1185
  %t1186 = call ptr @__alloc(i64 8, i32 0)
  %t1187 = inttoptr i64 25 to ptr
  %t1188 = getelementptr ptr, ptr %t1186, i32 0
  store ptr %t1187, ptr %t1188
  %t1189 = getelementptr ptr, ptr %t1183, i32 1
  store ptr %t1186, ptr %t1189
  %t1190 = getelementptr ptr, ptr %t1180, i32 1
  store ptr %t1183, ptr %t1190
  %t1191 = getelementptr ptr, ptr %t1176, i32 2
  store ptr %t1180, ptr %t1191
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t1169)
  call void @__free_recursive(ptr %t413)
  call void @__free_recursive(ptr %t415)
  store ptr %t1176, ptr %t3
  br label %tco.loop.0
tco.case.arm.14.1192:
  %t1193 = call ptr @__alloc(i64 16, i32 1)
  %t1194 = inttoptr i64 4 to ptr
  %t1195 = getelementptr ptr, ptr %t1193, i32 0
  store ptr %t1194, ptr %t1195
  %t1196 = getelementptr ptr, ptr %t1169, i32 1
  %t1197 = load ptr, ptr %t1196
  call void @__inc_ref(ptr %t1197)
  %t1198 = getelementptr ptr, ptr %t1193, i32 1
  store ptr %t1197, ptr %t1198
  store ptr %t1193, ptr %v_$inl18$scrut.jslot
  br label %join.1170
tco.case.default.1174:
  unreachable
join.1170:
  %t1199 = load ptr, ptr %v_$inl18$scrut.jslot
  %t1200 = getelementptr ptr, ptr %t1199, i32 0
  %t1201 = load ptr, ptr %t1200
  %t1202 = ptrtoint ptr %t1201 to i64
  switch i64 %t1202, label %tco.case.default.1203 [ i64 3, label %tco.case.arm.3.1204 i64 4, label %tco.case.arm.4.1220 ]
tco.case.arm.3.1204:
  %t1205 = call ptr @__alloc(i64 24, i32 2)
  %t1206 = inttoptr i64 66 to ptr
  %t1207 = getelementptr ptr, ptr %t1205, i32 0
  store ptr %t1206, ptr %t1207
  call void @__inc_ref(ptr %t415)
  %t1208 = getelementptr ptr, ptr %t1205, i32 1
  store ptr %t415, ptr %t1208
  %t1209 = call ptr @__alloc(i64 16, i32 1)
  %t1210 = inttoptr i64 3 to ptr
  %t1211 = getelementptr ptr, ptr %t1209, i32 0
  store ptr %t1210, ptr %t1211
  %t1212 = call ptr @__alloc(i64 16, i32 1)
  %t1213 = inttoptr i64 2671988933 to ptr
  %t1214 = getelementptr ptr, ptr %t1212, i32 0
  store ptr %t1213, ptr %t1214
  %t1215 = getelementptr ptr, ptr %t1199, i32 1
  %t1216 = load ptr, ptr %t1215
  call void @__inc_ref(ptr %t1216)
  %t1217 = getelementptr ptr, ptr %t1212, i32 1
  store ptr %t1216, ptr %t1217
  %t1218 = getelementptr ptr, ptr %t1209, i32 1
  store ptr %t1212, ptr %t1218
  %t1219 = getelementptr ptr, ptr %t1205, i32 2
  store ptr %t1209, ptr %t1219
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t1199)
  call void @__free_recursive(ptr %t1169)
  call void @__free_recursive(ptr %t413)
  call void @__free_recursive(ptr %t415)
  store ptr %t1205, ptr %t3
  br label %tco.loop.0
tco.case.arm.4.1220:
  %t1221 = getelementptr ptr, ptr %t1199, i32 1
  %t1222 = load ptr, ptr %t1221
  call void @__inc_ref(ptr %t1222)
  %t1223 = call ptr @__alloc(i64 24, i32 2)
  %t1224 = inttoptr i64 67 to ptr
  %t1225 = getelementptr ptr, ptr %t1223, i32 0
  store ptr %t1224, ptr %t1225
  %t1226 = call ptr @__alloc(i64 24, i32 2)
  %t1227 = inttoptr i64 45 to ptr
  %t1228 = getelementptr ptr, ptr %t1226, i32 0
  store ptr %t1227, ptr %t1228
  %t1229 = call ptr @__alloc(i64 16, i32 1)
  %t1230 = inttoptr i64 24 to ptr
  %t1231 = getelementptr ptr, ptr %t1229, i32 0
  store ptr %t1230, ptr %t1231
  %t1232 = call ptr @__alloc(i64 8, i32 0)
  %t1233 = inttoptr i64 29 to ptr
  %t1234 = getelementptr ptr, ptr %t1232, i32 0
  store ptr %t1233, ptr %t1234
  %t1235 = getelementptr ptr, ptr %t1229, i32 1
  store ptr %t1232, ptr %t1235
  %t1236 = getelementptr ptr, ptr %t1226, i32 1
  store ptr %t1229, ptr %t1236
  call void @__inc_ref(ptr %t1222)
  %t1237 = getelementptr ptr, ptr %t1226, i32 2
  store ptr %t1222, ptr %t1237
  %t1238 = getelementptr ptr, ptr %t1223, i32 1
  store ptr %t1226, ptr %t1238
  %t1239 = call ptr @__alloc(i64 24, i32 2)
  %t1240 = inttoptr i64 63 to ptr
  %t1241 = getelementptr ptr, ptr %t1239, i32 0
  store ptr %t1240, ptr %t1241
  call void @__inc_ref(ptr %t415)
  %t1242 = getelementptr ptr, ptr %t1239, i32 1
  store ptr %t415, ptr %t1242
  call void @__inc_ref(ptr %t1222)
  %t1243 = getelementptr ptr, ptr %t1239, i32 2
  store ptr %t1222, ptr %t1243
  %t1244 = getelementptr ptr, ptr %t1223, i32 2
  store ptr %t1239, ptr %t1244
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t1222)
  call void @__free_recursive(ptr %t1199)
  call void @__free_recursive(ptr %t1169)
  call void @__free_recursive(ptr %t413)
  call void @__free_recursive(ptr %t415)
  store ptr %t1223, ptr %t3
  br label %tco.loop.0
tco.case.default.1203:
  unreachable
tco.case.default.419:
  unreachable
tco.case.default.8:
  unreachable
tco.exit.1:
  %t1245 = load ptr, ptr %t2
  ret ptr %t1245
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
