; External C declarations
declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare ptr @memcpy(ptr, ptr, i64)
declare i64 @write(i32, ptr, i64)


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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [7 x i8]} { i32 0, i32 0, i32 0, i32 7, i32 7, [7 x i8] c"Nothing" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"Just(" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"|" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c")" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"," }
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"a,b,c" }
@.str.6 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"::" }
@.str.7 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"user::42::admin" }
@.str.8 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"x" }
@.str.9 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"abc" }
@.str.10 = private unnamed_addr constant {i32, i32, i32, i32, i32, [0 x i8]} { i32 0, i32 0, i32 0, i32 0, i32 0, [0 x i8] zeroinitializer }
@.str.11 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c":" }
@.str.12 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c":foo" }
@.str.13 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"foo:" }
@.str.14 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"abcde" }
@.str.15 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"ab" }
@.str.16 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c", " }
@.str.17 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }

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


define internal ptr @__splitOnFirst(ptr %sep, ptr %str) {
entry:
  %sep_len32 = load i32, ptr %sep
  %str_len32 = load i32, ptr %str
  %sep_len = zext i32 %sep_len32 to i64
  %str_len = zext i32 %str_len32 to i64
  %sep_payload = getelementptr i8, ptr %sep, i64 8
  %str_payload = getelementptr i8, ptr %str, i64 8
  %too_long = icmp ugt i64 %sep_len, %str_len
  br i1 %too_long, label %not_found, label %search_init
search_init:
  %limit = sub i64 %str_len, %sep_len
  %i_p = alloca i64, align 8
  store i64 0, ptr %i_p
  br label %outer
outer:
  %i = load i64, ptr %i_p
  %i_done = icmp ugt i64 %i, %limit
  br i1 %i_done, label %not_found, label %inner_init
inner_init:
  %j_p = alloca i64, align 8
  store i64 0, ptr %j_p
  br label %inner
inner:
  %j = load i64, ptr %j_p
  %j_done = icmp uge i64 %j, %sep_len
  br i1 %j_done, label %match, label %inner_step
inner_step:
  %ij = add i64 %i, %j
  %sp = getelementptr i8, ptr %str_payload, i64 %ij
  %sb = load i8, ptr %sp
  %sepp = getelementptr i8, ptr %sep_payload, i64 %j
  %sepb = load i8, ptr %sepp
  %eq = icmp eq i8 %sb, %sepb
  br i1 %eq, label %inner_advance, label %outer_advance
inner_advance:
  %j1 = add i64 %j, 1
  store i64 %j1, ptr %j_p
  br label %inner
outer_advance:
  %i1 = add i64 %i, 1
  store i64 %i1, ptr %i_p
  br label %outer
match:
  %prefix_blen = phi i64 [ %i, %inner ]
  %prefix_after = add i64 %i, %sep_len
  %suffix_blen = sub i64 %str_len, %prefix_after
  %suffix_start = getelementptr i8, ptr %str_payload, i64 %prefix_after
  %prefix_u16 = call i32 @__utf16OfRange(ptr %str_payload, i64 %prefix_blen)
  %prefix_alloc = add i64 %prefix_blen, 8
  %prefix = call ptr @__alloc(i64 %prefix_alloc, i32 0)
  %prefix_blen32 = trunc i64 %prefix_blen to i32
  store i32 %prefix_blen32, ptr %prefix
  %prefix_u16p = getelementptr i8, ptr %prefix, i64 4
  store i32 %prefix_u16, ptr %prefix_u16p
  %prefix_payload = getelementptr i8, ptr %prefix, i64 8
  call ptr @memcpy(ptr %prefix_payload, ptr %str_payload, i64 %prefix_blen)
  %suffix_u16 = call i32 @__utf16OfRange(ptr %suffix_start, i64 %suffix_blen)
  %suffix_alloc = add i64 %suffix_blen, 8
  %suffix = call ptr @__alloc(i64 %suffix_alloc, i32 0)
  %suffix_blen32 = trunc i64 %suffix_blen to i32
  store i32 %suffix_blen32, ptr %suffix
  %suffix_u16p = getelementptr i8, ptr %suffix, i64 4
  store i32 %suffix_u16, ptr %suffix_u16p
  %suffix_payload = getelementptr i8, ptr %suffix, i64 8
  call ptr @memcpy(ptr %suffix_payload, ptr %suffix_start, i64 %suffix_blen)
  %tuple = call ptr @__alloc(i64 24, i32 2)
  %tuple_tag = inttoptr i64 15 to ptr
  store ptr %tuple_tag, ptr %tuple
  %tuple_a = getelementptr ptr, ptr %tuple, i32 1
  store ptr %prefix, ptr %tuple_a
  %tuple_b = getelementptr ptr, ptr %tuple, i32 2
  store ptr %suffix, ptr %tuple_b
  %just = call ptr @__alloc(i64 16, i32 1)
  %just_tag = inttoptr i64 12 to ptr
  store ptr %just_tag, ptr %just
  %just_f = getelementptr ptr, ptr %just, i32 1
  store ptr %tuple, ptr %just_f
  br label %join
not_found:
  %nothing = call ptr @__alloc(i64 8, i32 0)
  %nothing_tag = inttoptr i64 11 to ptr
  store ptr %nothing_tag, ptr %nothing
  br label %join
join:
  %result = phi ptr [ %just, %match ], [ %nothing, %not_found ]
  call void @__free_recursive(ptr %sep)
  call void @__free_recursive(ptr %str)
  ret ptr %result
}

define internal i32 @__utf16OfRange(ptr %p, i64 %len) {
entry:
  %i_p = alloca i64, align 8
  store i64 0, ptr %i_p
  %n_p = alloca i32, align 4
  store i32 0, ptr %n_p
  br label %head
head:
  %i = load i64, ptr %i_p
  %done = icmp uge i64 %i, %len
  br i1 %done, label %end, label %body
body:
  %bp = getelementptr i8, ptr %p, i64 %i
  %b = load i8, ptr %bp
  %bz = zext i8 %b to i32
  %top2 = and i32 %bz, 192
  %is_cont = icmp eq i32 %top2, 128
  br i1 %is_cont, label %step, label %check4
check4:
  %top5 = and i32 %bz, 248
  %is_4 = icmp eq i32 %top5, 240
  br i1 %is_4, label %add2, label %add1
add2:
  %n2 = load i32, ptr %n_p
  %n2_new = add i32 %n2, 2
  store i32 %n2_new, ptr %n_p
  br label %step
add1:
  %n1 = load i32, ptr %n_p
  %n1_new = add i32 %n1, 1
  store i32 %n1_new, ptr %n_p
  br label %step
step:
  %i1 = add i64 %i, 1
  store i64 %i1, ptr %i_p
  br label %head
end:
  %nf = load i32, ptr %n_p
  ret i32 %nf
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
  switch i64 %t7, label %tco.case.default.8 [ i64 5, label %tco.case.arm.5.9 i64 7, label %tco.case.arm.7.12 ]
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
tco.case.default.8:
  unreachable
tco.exit.1:
  %t23 = load ptr, ptr %t2
  ret ptr %t23
}

define internal ptr @v_render(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 11, label %case.arm.11.4 i64 12, label %case.arm.12.9 ]
case.arm.11.4:
  %t5 = call ptr @__alloc(i64 16, i32 1)
  %t6 = inttoptr i64 4 to ptr
  %t7 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t6, ptr %t7
  %t8 = getelementptr ptr, ptr %t5, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t8
  call void @__free_recursive(ptr %v_r)
  ret ptr %t5
case.arm.12.9:
  %t10 = getelementptr ptr, ptr %v_r, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  %t12 = getelementptr ptr, ptr %t11, i32 0
  %t13 = load ptr, ptr %t12
  %t14 = ptrtoint ptr %t13 to i64
  switch i64 %t14, label %case.default.15 [ i64 15, label %case.arm.15.16 ]
case.arm.15.16:
  %t17 = getelementptr ptr, ptr %t11, i32 1
  %t18 = load ptr, ptr %t17
  call void @__inc_ref(ptr %t18)
  %t19 = getelementptr ptr, ptr %t11, i32 2
  %t20 = load ptr, ptr %t19
  call void @__inc_ref(ptr %t20)
  call void @__inc_ref(ptr %t18)
  call void @__inc_ref(ptr %t20)
  %t21 = call ptr @v_renderTuple(ptr %t18, ptr %t20)
  call void @__free_recursive(ptr %t20)
  call void @__free_recursive(ptr %t18)
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %v_r)
  ret ptr %t21
case.default.15:
  unreachable
case.default.3:
  unreachable
}

define internal ptr @v_renderTuple(ptr %v_a, ptr %v_b) {
  call void @__inc_ref(ptr %v_a)
  %t0 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %v_a)
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 3, label %case.arm.3.5 i64 4, label %case.arm.4.12 ]
case.arm.3.5:
  %t6 = getelementptr ptr, ptr %t0, i32 1
  %t7 = load ptr, ptr %t6
  call void @__inc_ref(ptr %t7)
  %t8 = call ptr @__alloc(i64 16, i32 1)
  %t9 = inttoptr i64 3 to ptr
  %t10 = getelementptr ptr, ptr %t8, i32 0
  store ptr %t9, ptr %t10
  call void @__inc_ref(ptr %t7)
  %t11 = getelementptr ptr, ptr %t8, i32 1
  store ptr %t7, ptr %t11
  call void @__free_recursive(ptr %t0)
  call void @__free_recursive(ptr %t7)
  call void @__free_recursive(ptr %v_a)
  call void @__free_recursive(ptr %v_b)
  ret ptr %t8
case.arm.4.12:
  %t13 = getelementptr ptr, ptr %t0, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  call void @__inc_ref(ptr %t14)
  %t15 = call ptr @__concat(ptr %t14, ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
  %t16 = getelementptr ptr, ptr %t15, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %case.default.19 [ i64 3, label %case.arm.3.20 i64 4, label %case.arm.4.27 ]
case.arm.3.20:
  %t21 = getelementptr ptr, ptr %t15, i32 1
  %t22 = load ptr, ptr %t21
  call void @__inc_ref(ptr %t22)
  %t23 = call ptr @__alloc(i64 16, i32 1)
  %t24 = inttoptr i64 3 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  call void @__inc_ref(ptr %t22)
  %t26 = getelementptr ptr, ptr %t23, i32 1
  store ptr %t22, ptr %t26
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t0)
  call void @__free_recursive(ptr %t22)
  call void @__free_recursive(ptr %t14)
  call void @__free_recursive(ptr %v_a)
  call void @__free_recursive(ptr %v_b)
  ret ptr %t23
case.arm.4.27:
  %t28 = getelementptr ptr, ptr %t15, i32 1
  %t29 = load ptr, ptr %t28
  call void @__inc_ref(ptr %t29)
  call void @__inc_ref(ptr %t29)
  call void @__inc_ref(ptr %v_b)
  %t30 = call ptr @__concat(ptr %t29, ptr %v_b)
  %t31 = getelementptr ptr, ptr %t30, i32 0
  %t32 = load ptr, ptr %t31
  %t33 = ptrtoint ptr %t32 to i64
  switch i64 %t33, label %case.default.34 [ i64 3, label %case.arm.3.35 i64 4, label %case.arm.4.42 ]
case.arm.3.35:
  %t36 = getelementptr ptr, ptr %t30, i32 1
  %t37 = load ptr, ptr %t36
  call void @__inc_ref(ptr %t37)
  %t38 = call ptr @__alloc(i64 16, i32 1)
  %t39 = inttoptr i64 3 to ptr
  %t40 = getelementptr ptr, ptr %t38, i32 0
  store ptr %t39, ptr %t40
  call void @__inc_ref(ptr %t37)
  %t41 = getelementptr ptr, ptr %t38, i32 1
  store ptr %t37, ptr %t41
  call void @__free_recursive(ptr %t30)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t0)
  call void @__free_recursive(ptr %t37)
  call void @__free_recursive(ptr %t29)
  call void @__free_recursive(ptr %t14)
  call void @__free_recursive(ptr %v_a)
  call void @__free_recursive(ptr %v_b)
  ret ptr %t38
case.arm.4.42:
  %t43 = getelementptr ptr, ptr %t30, i32 1
  %t44 = load ptr, ptr %t43
  call void @__inc_ref(ptr %t44)
  call void @__inc_ref(ptr %t44)
  %t45 = call ptr @__concat(ptr %t44, ptr getelementptr inbounds (i8, ptr @.str.3, i64 12))
  call void @__free_recursive(ptr %t30)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t0)
  call void @__free_recursive(ptr %t44)
  call void @__free_recursive(ptr %t29)
  call void @__free_recursive(ptr %t14)
  call void @__free_recursive(ptr %v_a)
  call void @__free_recursive(ptr %v_b)
  ret ptr %t45
case.default.34:
  unreachable
case.default.19:
  unreachable
case.default.4:
  unreachable
}

define internal ptr @v_main() {
  %t0 = call ptr @__splitOnFirst(ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr getelementptr inbounds (i8, ptr @.str.5, i64 12))
  %t1 = call ptr @v_render(ptr %t0)
  %t2 = getelementptr ptr, ptr %t1, i32 0
  %t3 = load ptr, ptr %t2
  %t4 = ptrtoint ptr %t3 to i64
  switch i64 %t4, label %case.default.5 [ i64 3, label %case.arm.3.7 i64 4, label %case.arm.4.15 ]
case.arm.3.7:
  %t9 = getelementptr ptr, ptr %t1, i32 1
  %t10 = load ptr, ptr %t9
  call void @__inc_ref(ptr %t10)
  %t11 = call ptr @__alloc(i64 16, i32 1)
  %t12 = inttoptr i64 3 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  call void @__inc_ref(ptr %t10)
  %t14 = getelementptr ptr, ptr %t11, i32 1
  store ptr %t10, ptr %t14
  br label %case.end.3.8
case.end.3.8:
  br label %case.join.6
case.arm.4.15:
  %t17 = getelementptr ptr, ptr %t1, i32 1
  %t18 = load ptr, ptr %t17
  call void @__inc_ref(ptr %t18)
  %t19 = call ptr @__splitOnFirst(ptr getelementptr inbounds (i8, ptr @.str.6, i64 12), ptr getelementptr inbounds (i8, ptr @.str.7, i64 12))
  %t20 = call ptr @v_render(ptr %t19)
  %t21 = getelementptr ptr, ptr %t20, i32 0
  %t22 = load ptr, ptr %t21
  %t23 = ptrtoint ptr %t22 to i64
  switch i64 %t23, label %case.default.24 [ i64 3, label %case.arm.3.26 i64 4, label %case.arm.4.34 ]
case.arm.3.26:
  %t28 = getelementptr ptr, ptr %t20, i32 1
  %t29 = load ptr, ptr %t28
  call void @__inc_ref(ptr %t29)
  %t30 = call ptr @__alloc(i64 16, i32 1)
  %t31 = inttoptr i64 3 to ptr
  %t32 = getelementptr ptr, ptr %t30, i32 0
  store ptr %t31, ptr %t32
  call void @__inc_ref(ptr %t29)
  %t33 = getelementptr ptr, ptr %t30, i32 1
  store ptr %t29, ptr %t33
  br label %case.end.3.27
case.end.3.27:
  br label %case.join.25
case.arm.4.34:
  %t36 = getelementptr ptr, ptr %t20, i32 1
  %t37 = load ptr, ptr %t36
  call void @__inc_ref(ptr %t37)
  %t38 = call ptr @__splitOnFirst(ptr getelementptr inbounds (i8, ptr @.str.8, i64 12), ptr getelementptr inbounds (i8, ptr @.str.9, i64 12))
  %t39 = call ptr @v_render(ptr %t38)
  %t40 = getelementptr ptr, ptr %t39, i32 0
  %t41 = load ptr, ptr %t40
  %t42 = ptrtoint ptr %t41 to i64
  switch i64 %t42, label %case.default.43 [ i64 3, label %case.arm.3.45 i64 4, label %case.arm.4.53 ]
case.arm.3.45:
  %t47 = getelementptr ptr, ptr %t39, i32 1
  %t48 = load ptr, ptr %t47
  call void @__inc_ref(ptr %t48)
  %t49 = call ptr @__alloc(i64 16, i32 1)
  %t50 = inttoptr i64 3 to ptr
  %t51 = getelementptr ptr, ptr %t49, i32 0
  store ptr %t50, ptr %t51
  call void @__inc_ref(ptr %t48)
  %t52 = getelementptr ptr, ptr %t49, i32 1
  store ptr %t48, ptr %t52
  br label %case.end.3.46
case.end.3.46:
  br label %case.join.44
case.arm.4.53:
  %t55 = getelementptr ptr, ptr %t39, i32 1
  %t56 = load ptr, ptr %t55
  call void @__inc_ref(ptr %t56)
  %t57 = call ptr @__splitOnFirst(ptr getelementptr inbounds (i8, ptr @.str.10, i64 12), ptr getelementptr inbounds (i8, ptr @.str.9, i64 12))
  %t58 = call ptr @v_render(ptr %t57)
  %t59 = getelementptr ptr, ptr %t58, i32 0
  %t60 = load ptr, ptr %t59
  %t61 = ptrtoint ptr %t60 to i64
  switch i64 %t61, label %case.default.62 [ i64 3, label %case.arm.3.64 i64 4, label %case.arm.4.72 ]
case.arm.3.64:
  %t66 = getelementptr ptr, ptr %t58, i32 1
  %t67 = load ptr, ptr %t66
  call void @__inc_ref(ptr %t67)
  %t68 = call ptr @__alloc(i64 16, i32 1)
  %t69 = inttoptr i64 3 to ptr
  %t70 = getelementptr ptr, ptr %t68, i32 0
  store ptr %t69, ptr %t70
  call void @__inc_ref(ptr %t67)
  %t71 = getelementptr ptr, ptr %t68, i32 1
  store ptr %t67, ptr %t71
  br label %case.end.3.65
case.end.3.65:
  br label %case.join.63
case.arm.4.72:
  %t74 = getelementptr ptr, ptr %t58, i32 1
  %t75 = load ptr, ptr %t74
  call void @__inc_ref(ptr %t75)
  %t76 = call ptr @__splitOnFirst(ptr getelementptr inbounds (i8, ptr @.str.11, i64 12), ptr getelementptr inbounds (i8, ptr @.str.12, i64 12))
  %t77 = call ptr @v_render(ptr %t76)
  %t78 = getelementptr ptr, ptr %t77, i32 0
  %t79 = load ptr, ptr %t78
  %t80 = ptrtoint ptr %t79 to i64
  switch i64 %t80, label %case.default.81 [ i64 3, label %case.arm.3.83 i64 4, label %case.arm.4.91 ]
case.arm.3.83:
  %t85 = getelementptr ptr, ptr %t77, i32 1
  %t86 = load ptr, ptr %t85
  call void @__inc_ref(ptr %t86)
  %t87 = call ptr @__alloc(i64 16, i32 1)
  %t88 = inttoptr i64 3 to ptr
  %t89 = getelementptr ptr, ptr %t87, i32 0
  store ptr %t88, ptr %t89
  call void @__inc_ref(ptr %t86)
  %t90 = getelementptr ptr, ptr %t87, i32 1
  store ptr %t86, ptr %t90
  br label %case.end.3.84
case.end.3.84:
  br label %case.join.82
case.arm.4.91:
  %t93 = getelementptr ptr, ptr %t77, i32 1
  %t94 = load ptr, ptr %t93
  call void @__inc_ref(ptr %t94)
  %t95 = call ptr @__splitOnFirst(ptr getelementptr inbounds (i8, ptr @.str.11, i64 12), ptr getelementptr inbounds (i8, ptr @.str.13, i64 12))
  %t96 = call ptr @v_render(ptr %t95)
  %t97 = getelementptr ptr, ptr %t96, i32 0
  %t98 = load ptr, ptr %t97
  %t99 = ptrtoint ptr %t98 to i64
  switch i64 %t99, label %case.default.100 [ i64 3, label %case.arm.3.102 i64 4, label %case.arm.4.110 ]
case.arm.3.102:
  %t104 = getelementptr ptr, ptr %t96, i32 1
  %t105 = load ptr, ptr %t104
  call void @__inc_ref(ptr %t105)
  %t106 = call ptr @__alloc(i64 16, i32 1)
  %t107 = inttoptr i64 3 to ptr
  %t108 = getelementptr ptr, ptr %t106, i32 0
  store ptr %t107, ptr %t108
  call void @__inc_ref(ptr %t105)
  %t109 = getelementptr ptr, ptr %t106, i32 1
  store ptr %t105, ptr %t109
  br label %case.end.3.103
case.end.3.103:
  br label %case.join.101
case.arm.4.110:
  %t112 = getelementptr ptr, ptr %t96, i32 1
  %t113 = load ptr, ptr %t112
  call void @__inc_ref(ptr %t113)
  %t114 = call ptr @__splitOnFirst(ptr getelementptr inbounds (i8, ptr @.str.9, i64 12), ptr getelementptr inbounds (i8, ptr @.str.9, i64 12))
  %t115 = call ptr @v_render(ptr %t114)
  %t116 = getelementptr ptr, ptr %t115, i32 0
  %t117 = load ptr, ptr %t116
  %t118 = ptrtoint ptr %t117 to i64
  switch i64 %t118, label %case.default.119 [ i64 3, label %case.arm.3.121 i64 4, label %case.arm.4.129 ]
case.arm.3.121:
  %t123 = getelementptr ptr, ptr %t115, i32 1
  %t124 = load ptr, ptr %t123
  call void @__inc_ref(ptr %t124)
  %t125 = call ptr @__alloc(i64 16, i32 1)
  %t126 = inttoptr i64 3 to ptr
  %t127 = getelementptr ptr, ptr %t125, i32 0
  store ptr %t126, ptr %t127
  call void @__inc_ref(ptr %t124)
  %t128 = getelementptr ptr, ptr %t125, i32 1
  store ptr %t124, ptr %t128
  br label %case.end.3.122
case.end.3.122:
  br label %case.join.120
case.arm.4.129:
  %t131 = getelementptr ptr, ptr %t115, i32 1
  %t132 = load ptr, ptr %t131
  call void @__inc_ref(ptr %t132)
  %t133 = call ptr @__splitOnFirst(ptr getelementptr inbounds (i8, ptr @.str.14, i64 12), ptr getelementptr inbounds (i8, ptr @.str.15, i64 12))
  %t134 = call ptr @v_render(ptr %t133)
  %t135 = getelementptr ptr, ptr %t134, i32 0
  %t136 = load ptr, ptr %t135
  %t137 = ptrtoint ptr %t136 to i64
  switch i64 %t137, label %case.default.138 [ i64 3, label %case.arm.3.140 i64 4, label %case.arm.4.148 ]
case.arm.3.140:
  %t142 = getelementptr ptr, ptr %t134, i32 1
  %t143 = load ptr, ptr %t142
  call void @__inc_ref(ptr %t143)
  %t144 = call ptr @__alloc(i64 16, i32 1)
  %t145 = inttoptr i64 3 to ptr
  %t146 = getelementptr ptr, ptr %t144, i32 0
  store ptr %t145, ptr %t146
  call void @__inc_ref(ptr %t143)
  %t147 = getelementptr ptr, ptr %t144, i32 1
  store ptr %t143, ptr %t147
  br label %case.end.3.141
case.end.3.141:
  br label %case.join.139
case.arm.4.148:
  %t150 = getelementptr ptr, ptr %t134, i32 1
  %t151 = load ptr, ptr %t150
  call void @__inc_ref(ptr %t151)
  call void @__inc_ref(ptr %t18)
  %t152 = call ptr @__concat(ptr %t18, ptr getelementptr inbounds (i8, ptr @.str.16, i64 12))
  %t153 = getelementptr ptr, ptr %t152, i32 0
  %t154 = load ptr, ptr %t153
  %t155 = ptrtoint ptr %t154 to i64
  switch i64 %t155, label %case.default.156 [ i64 3, label %case.arm.3.158 i64 4, label %case.arm.4.166 ]
case.arm.3.158:
  %t160 = getelementptr ptr, ptr %t152, i32 1
  %t161 = load ptr, ptr %t160
  call void @__inc_ref(ptr %t161)
  %t162 = call ptr @__alloc(i64 16, i32 1)
  %t163 = inttoptr i64 3 to ptr
  %t164 = getelementptr ptr, ptr %t162, i32 0
  store ptr %t163, ptr %t164
  call void @__inc_ref(ptr %t161)
  %t165 = getelementptr ptr, ptr %t162, i32 1
  store ptr %t161, ptr %t165
  br label %case.end.3.159
case.end.3.159:
  br label %case.join.157
case.arm.4.166:
  %t168 = getelementptr ptr, ptr %t152, i32 1
  %t169 = load ptr, ptr %t168
  call void @__inc_ref(ptr %t169)
  call void @__inc_ref(ptr %t169)
  call void @__inc_ref(ptr %t37)
  %t170 = call ptr @__concat(ptr %t169, ptr %t37)
  %t171 = getelementptr ptr, ptr %t170, i32 0
  %t172 = load ptr, ptr %t171
  %t173 = ptrtoint ptr %t172 to i64
  switch i64 %t173, label %case.default.174 [ i64 3, label %case.arm.3.176 i64 4, label %case.arm.4.184 ]
case.arm.3.176:
  %t178 = getelementptr ptr, ptr %t170, i32 1
  %t179 = load ptr, ptr %t178
  call void @__inc_ref(ptr %t179)
  %t180 = call ptr @__alloc(i64 16, i32 1)
  %t181 = inttoptr i64 3 to ptr
  %t182 = getelementptr ptr, ptr %t180, i32 0
  store ptr %t181, ptr %t182
  call void @__inc_ref(ptr %t179)
  %t183 = getelementptr ptr, ptr %t180, i32 1
  store ptr %t179, ptr %t183
  br label %case.end.3.177
case.end.3.177:
  br label %case.join.175
case.arm.4.184:
  %t186 = getelementptr ptr, ptr %t170, i32 1
  %t187 = load ptr, ptr %t186
  call void @__inc_ref(ptr %t187)
  call void @__inc_ref(ptr %t187)
  %t188 = call ptr @__concat(ptr %t187, ptr getelementptr inbounds (i8, ptr @.str.16, i64 12))
  %t189 = getelementptr ptr, ptr %t188, i32 0
  %t190 = load ptr, ptr %t189
  %t191 = ptrtoint ptr %t190 to i64
  switch i64 %t191, label %case.default.192 [ i64 3, label %case.arm.3.194 i64 4, label %case.arm.4.202 ]
case.arm.3.194:
  %t196 = getelementptr ptr, ptr %t188, i32 1
  %t197 = load ptr, ptr %t196
  call void @__inc_ref(ptr %t197)
  %t198 = call ptr @__alloc(i64 16, i32 1)
  %t199 = inttoptr i64 3 to ptr
  %t200 = getelementptr ptr, ptr %t198, i32 0
  store ptr %t199, ptr %t200
  call void @__inc_ref(ptr %t197)
  %t201 = getelementptr ptr, ptr %t198, i32 1
  store ptr %t197, ptr %t201
  br label %case.end.3.195
case.end.3.195:
  br label %case.join.193
case.arm.4.202:
  %t204 = getelementptr ptr, ptr %t188, i32 1
  %t205 = load ptr, ptr %t204
  call void @__inc_ref(ptr %t205)
  call void @__inc_ref(ptr %t205)
  call void @__inc_ref(ptr %t56)
  %t206 = call ptr @__concat(ptr %t205, ptr %t56)
  %t207 = getelementptr ptr, ptr %t206, i32 0
  %t208 = load ptr, ptr %t207
  %t209 = ptrtoint ptr %t208 to i64
  switch i64 %t209, label %case.default.210 [ i64 3, label %case.arm.3.212 i64 4, label %case.arm.4.220 ]
case.arm.3.212:
  %t214 = getelementptr ptr, ptr %t206, i32 1
  %t215 = load ptr, ptr %t214
  call void @__inc_ref(ptr %t215)
  %t216 = call ptr @__alloc(i64 16, i32 1)
  %t217 = inttoptr i64 3 to ptr
  %t218 = getelementptr ptr, ptr %t216, i32 0
  store ptr %t217, ptr %t218
  call void @__inc_ref(ptr %t215)
  %t219 = getelementptr ptr, ptr %t216, i32 1
  store ptr %t215, ptr %t219
  br label %case.end.3.213
case.end.3.213:
  br label %case.join.211
case.arm.4.220:
  %t222 = getelementptr ptr, ptr %t206, i32 1
  %t223 = load ptr, ptr %t222
  call void @__inc_ref(ptr %t223)
  call void @__inc_ref(ptr %t223)
  %t224 = call ptr @__concat(ptr %t223, ptr getelementptr inbounds (i8, ptr @.str.16, i64 12))
  %t225 = getelementptr ptr, ptr %t224, i32 0
  %t226 = load ptr, ptr %t225
  %t227 = ptrtoint ptr %t226 to i64
  switch i64 %t227, label %case.default.228 [ i64 3, label %case.arm.3.230 i64 4, label %case.arm.4.238 ]
case.arm.3.230:
  %t232 = getelementptr ptr, ptr %t224, i32 1
  %t233 = load ptr, ptr %t232
  call void @__inc_ref(ptr %t233)
  %t234 = call ptr @__alloc(i64 16, i32 1)
  %t235 = inttoptr i64 3 to ptr
  %t236 = getelementptr ptr, ptr %t234, i32 0
  store ptr %t235, ptr %t236
  call void @__inc_ref(ptr %t233)
  %t237 = getelementptr ptr, ptr %t234, i32 1
  store ptr %t233, ptr %t237
  br label %case.end.3.231
case.end.3.231:
  br label %case.join.229
case.arm.4.238:
  %t240 = getelementptr ptr, ptr %t224, i32 1
  %t241 = load ptr, ptr %t240
  call void @__inc_ref(ptr %t241)
  call void @__inc_ref(ptr %t241)
  call void @__inc_ref(ptr %t75)
  %t242 = call ptr @__concat(ptr %t241, ptr %t75)
  %t243 = getelementptr ptr, ptr %t242, i32 0
  %t244 = load ptr, ptr %t243
  %t245 = ptrtoint ptr %t244 to i64
  switch i64 %t245, label %case.default.246 [ i64 3, label %case.arm.3.248 i64 4, label %case.arm.4.256 ]
case.arm.3.248:
  %t250 = getelementptr ptr, ptr %t242, i32 1
  %t251 = load ptr, ptr %t250
  call void @__inc_ref(ptr %t251)
  %t252 = call ptr @__alloc(i64 16, i32 1)
  %t253 = inttoptr i64 3 to ptr
  %t254 = getelementptr ptr, ptr %t252, i32 0
  store ptr %t253, ptr %t254
  call void @__inc_ref(ptr %t251)
  %t255 = getelementptr ptr, ptr %t252, i32 1
  store ptr %t251, ptr %t255
  br label %case.end.3.249
case.end.3.249:
  br label %case.join.247
case.arm.4.256:
  %t258 = getelementptr ptr, ptr %t242, i32 1
  %t259 = load ptr, ptr %t258
  call void @__inc_ref(ptr %t259)
  call void @__inc_ref(ptr %t259)
  %t260 = call ptr @__concat(ptr %t259, ptr getelementptr inbounds (i8, ptr @.str.16, i64 12))
  %t261 = getelementptr ptr, ptr %t260, i32 0
  %t262 = load ptr, ptr %t261
  %t263 = ptrtoint ptr %t262 to i64
  switch i64 %t263, label %case.default.264 [ i64 3, label %case.arm.3.266 i64 4, label %case.arm.4.274 ]
case.arm.3.266:
  %t268 = getelementptr ptr, ptr %t260, i32 1
  %t269 = load ptr, ptr %t268
  call void @__inc_ref(ptr %t269)
  %t270 = call ptr @__alloc(i64 16, i32 1)
  %t271 = inttoptr i64 3 to ptr
  %t272 = getelementptr ptr, ptr %t270, i32 0
  store ptr %t271, ptr %t272
  call void @__inc_ref(ptr %t269)
  %t273 = getelementptr ptr, ptr %t270, i32 1
  store ptr %t269, ptr %t273
  br label %case.end.3.267
case.end.3.267:
  br label %case.join.265
case.arm.4.274:
  %t276 = getelementptr ptr, ptr %t260, i32 1
  %t277 = load ptr, ptr %t276
  call void @__inc_ref(ptr %t277)
  call void @__inc_ref(ptr %t277)
  call void @__inc_ref(ptr %t94)
  %t278 = call ptr @__concat(ptr %t277, ptr %t94)
  %t279 = getelementptr ptr, ptr %t278, i32 0
  %t280 = load ptr, ptr %t279
  %t281 = ptrtoint ptr %t280 to i64
  switch i64 %t281, label %case.default.282 [ i64 3, label %case.arm.3.284 i64 4, label %case.arm.4.292 ]
case.arm.3.284:
  %t286 = getelementptr ptr, ptr %t278, i32 1
  %t287 = load ptr, ptr %t286
  call void @__inc_ref(ptr %t287)
  %t288 = call ptr @__alloc(i64 16, i32 1)
  %t289 = inttoptr i64 3 to ptr
  %t290 = getelementptr ptr, ptr %t288, i32 0
  store ptr %t289, ptr %t290
  call void @__inc_ref(ptr %t287)
  %t291 = getelementptr ptr, ptr %t288, i32 1
  store ptr %t287, ptr %t291
  br label %case.end.3.285
case.end.3.285:
  br label %case.join.283
case.arm.4.292:
  %t294 = getelementptr ptr, ptr %t278, i32 1
  %t295 = load ptr, ptr %t294
  call void @__inc_ref(ptr %t295)
  call void @__inc_ref(ptr %t295)
  %t296 = call ptr @__concat(ptr %t295, ptr getelementptr inbounds (i8, ptr @.str.16, i64 12))
  %t297 = getelementptr ptr, ptr %t296, i32 0
  %t298 = load ptr, ptr %t297
  %t299 = ptrtoint ptr %t298 to i64
  switch i64 %t299, label %case.default.300 [ i64 3, label %case.arm.3.302 i64 4, label %case.arm.4.310 ]
case.arm.3.302:
  %t304 = getelementptr ptr, ptr %t296, i32 1
  %t305 = load ptr, ptr %t304
  call void @__inc_ref(ptr %t305)
  %t306 = call ptr @__alloc(i64 16, i32 1)
  %t307 = inttoptr i64 3 to ptr
  %t308 = getelementptr ptr, ptr %t306, i32 0
  store ptr %t307, ptr %t308
  call void @__inc_ref(ptr %t305)
  %t309 = getelementptr ptr, ptr %t306, i32 1
  store ptr %t305, ptr %t309
  br label %case.end.3.303
case.end.3.303:
  br label %case.join.301
case.arm.4.310:
  %t312 = getelementptr ptr, ptr %t296, i32 1
  %t313 = load ptr, ptr %t312
  call void @__inc_ref(ptr %t313)
  call void @__inc_ref(ptr %t313)
  call void @__inc_ref(ptr %t113)
  %t314 = call ptr @__concat(ptr %t313, ptr %t113)
  %t315 = getelementptr ptr, ptr %t314, i32 0
  %t316 = load ptr, ptr %t315
  %t317 = ptrtoint ptr %t316 to i64
  switch i64 %t317, label %case.default.318 [ i64 3, label %case.arm.3.320 i64 4, label %case.arm.4.328 ]
case.arm.3.320:
  %t322 = getelementptr ptr, ptr %t314, i32 1
  %t323 = load ptr, ptr %t322
  call void @__inc_ref(ptr %t323)
  %t324 = call ptr @__alloc(i64 16, i32 1)
  %t325 = inttoptr i64 3 to ptr
  %t326 = getelementptr ptr, ptr %t324, i32 0
  store ptr %t325, ptr %t326
  call void @__inc_ref(ptr %t323)
  %t327 = getelementptr ptr, ptr %t324, i32 1
  store ptr %t323, ptr %t327
  br label %case.end.3.321
case.end.3.321:
  br label %case.join.319
case.arm.4.328:
  %t330 = getelementptr ptr, ptr %t314, i32 1
  %t331 = load ptr, ptr %t330
  call void @__inc_ref(ptr %t331)
  call void @__inc_ref(ptr %t331)
  %t332 = call ptr @__concat(ptr %t331, ptr getelementptr inbounds (i8, ptr @.str.16, i64 12))
  %t333 = getelementptr ptr, ptr %t332, i32 0
  %t334 = load ptr, ptr %t333
  %t335 = ptrtoint ptr %t334 to i64
  switch i64 %t335, label %case.default.336 [ i64 3, label %case.arm.3.338 i64 4, label %case.arm.4.346 ]
case.arm.3.338:
  %t340 = getelementptr ptr, ptr %t332, i32 1
  %t341 = load ptr, ptr %t340
  call void @__inc_ref(ptr %t341)
  %t342 = call ptr @__alloc(i64 16, i32 1)
  %t343 = inttoptr i64 3 to ptr
  %t344 = getelementptr ptr, ptr %t342, i32 0
  store ptr %t343, ptr %t344
  call void @__inc_ref(ptr %t341)
  %t345 = getelementptr ptr, ptr %t342, i32 1
  store ptr %t341, ptr %t345
  br label %case.end.3.339
case.end.3.339:
  br label %case.join.337
case.arm.4.346:
  %t348 = getelementptr ptr, ptr %t332, i32 1
  %t349 = load ptr, ptr %t348
  call void @__inc_ref(ptr %t349)
  call void @__inc_ref(ptr %t349)
  call void @__inc_ref(ptr %t132)
  %t350 = call ptr @__concat(ptr %t349, ptr %t132)
  %t351 = getelementptr ptr, ptr %t350, i32 0
  %t352 = load ptr, ptr %t351
  %t353 = ptrtoint ptr %t352 to i64
  switch i64 %t353, label %case.default.354 [ i64 3, label %case.arm.3.356 i64 4, label %case.arm.4.364 ]
case.arm.3.356:
  %t358 = getelementptr ptr, ptr %t350, i32 1
  %t359 = load ptr, ptr %t358
  call void @__inc_ref(ptr %t359)
  %t360 = call ptr @__alloc(i64 16, i32 1)
  %t361 = inttoptr i64 3 to ptr
  %t362 = getelementptr ptr, ptr %t360, i32 0
  store ptr %t361, ptr %t362
  call void @__inc_ref(ptr %t359)
  %t363 = getelementptr ptr, ptr %t360, i32 1
  store ptr %t359, ptr %t363
  br label %case.end.3.357
case.end.3.357:
  br label %case.join.355
case.arm.4.364:
  %t366 = getelementptr ptr, ptr %t350, i32 1
  %t367 = load ptr, ptr %t366
  call void @__inc_ref(ptr %t367)
  call void @__inc_ref(ptr %t367)
  %t368 = call ptr @__concat(ptr %t367, ptr getelementptr inbounds (i8, ptr @.str.16, i64 12))
  %t369 = getelementptr ptr, ptr %t368, i32 0
  %t370 = load ptr, ptr %t369
  %t371 = ptrtoint ptr %t370 to i64
  switch i64 %t371, label %case.default.372 [ i64 3, label %case.arm.3.374 i64 4, label %case.arm.4.382 ]
case.arm.3.374:
  %t376 = getelementptr ptr, ptr %t368, i32 1
  %t377 = load ptr, ptr %t376
  call void @__inc_ref(ptr %t377)
  %t378 = call ptr @__alloc(i64 16, i32 1)
  %t379 = inttoptr i64 3 to ptr
  %t380 = getelementptr ptr, ptr %t378, i32 0
  store ptr %t379, ptr %t380
  call void @__inc_ref(ptr %t377)
  %t381 = getelementptr ptr, ptr %t378, i32 1
  store ptr %t377, ptr %t381
  br label %case.end.3.375
case.end.3.375:
  br label %case.join.373
case.arm.4.382:
  %t384 = getelementptr ptr, ptr %t368, i32 1
  %t385 = load ptr, ptr %t384
  call void @__inc_ref(ptr %t385)
  call void @__inc_ref(ptr %t385)
  call void @__inc_ref(ptr %t151)
  %t386 = call ptr @__concat(ptr %t385, ptr %t151)
  br label %case.end.4.383
case.end.4.383:
  br label %case.join.373
case.default.372:
  unreachable
case.join.373:
  %t387 = phi ptr [ %t378, %case.end.3.375 ], [ %t386, %case.end.4.383 ]
  call void @__free_recursive(ptr %t368)
  br label %case.end.4.365
case.end.4.365:
  br label %case.join.355
case.default.354:
  unreachable
case.join.355:
  %t388 = phi ptr [ %t360, %case.end.3.357 ], [ %t387, %case.end.4.365 ]
  call void @__free_recursive(ptr %t350)
  br label %case.end.4.347
case.end.4.347:
  br label %case.join.337
case.default.336:
  unreachable
case.join.337:
  %t389 = phi ptr [ %t342, %case.end.3.339 ], [ %t388, %case.end.4.347 ]
  call void @__free_recursive(ptr %t332)
  br label %case.end.4.329
case.end.4.329:
  br label %case.join.319
case.default.318:
  unreachable
case.join.319:
  %t390 = phi ptr [ %t324, %case.end.3.321 ], [ %t389, %case.end.4.329 ]
  call void @__free_recursive(ptr %t314)
  br label %case.end.4.311
case.end.4.311:
  br label %case.join.301
case.default.300:
  unreachable
case.join.301:
  %t391 = phi ptr [ %t306, %case.end.3.303 ], [ %t390, %case.end.4.311 ]
  call void @__free_recursive(ptr %t296)
  br label %case.end.4.293
case.end.4.293:
  br label %case.join.283
case.default.282:
  unreachable
case.join.283:
  %t392 = phi ptr [ %t288, %case.end.3.285 ], [ %t391, %case.end.4.293 ]
  call void @__free_recursive(ptr %t278)
  br label %case.end.4.275
case.end.4.275:
  br label %case.join.265
case.default.264:
  unreachable
case.join.265:
  %t393 = phi ptr [ %t270, %case.end.3.267 ], [ %t392, %case.end.4.275 ]
  call void @__free_recursive(ptr %t260)
  br label %case.end.4.257
case.end.4.257:
  br label %case.join.247
case.default.246:
  unreachable
case.join.247:
  %t394 = phi ptr [ %t252, %case.end.3.249 ], [ %t393, %case.end.4.257 ]
  call void @__free_recursive(ptr %t242)
  br label %case.end.4.239
case.end.4.239:
  br label %case.join.229
case.default.228:
  unreachable
case.join.229:
  %t395 = phi ptr [ %t234, %case.end.3.231 ], [ %t394, %case.end.4.239 ]
  call void @__free_recursive(ptr %t224)
  br label %case.end.4.221
case.end.4.221:
  br label %case.join.211
case.default.210:
  unreachable
case.join.211:
  %t396 = phi ptr [ %t216, %case.end.3.213 ], [ %t395, %case.end.4.221 ]
  call void @__free_recursive(ptr %t206)
  br label %case.end.4.203
case.end.4.203:
  br label %case.join.193
case.default.192:
  unreachable
case.join.193:
  %t397 = phi ptr [ %t198, %case.end.3.195 ], [ %t396, %case.end.4.203 ]
  call void @__free_recursive(ptr %t188)
  br label %case.end.4.185
case.end.4.185:
  br label %case.join.175
case.default.174:
  unreachable
case.join.175:
  %t398 = phi ptr [ %t180, %case.end.3.177 ], [ %t397, %case.end.4.185 ]
  call void @__free_recursive(ptr %t170)
  br label %case.end.4.167
case.end.4.167:
  br label %case.join.157
case.default.156:
  unreachable
case.join.157:
  %t399 = phi ptr [ %t162, %case.end.3.159 ], [ %t398, %case.end.4.167 ]
  call void @__free_recursive(ptr %t152)
  br label %case.end.4.149
case.end.4.149:
  br label %case.join.139
case.default.138:
  unreachable
case.join.139:
  %t400 = phi ptr [ %t144, %case.end.3.141 ], [ %t399, %case.end.4.149 ]
  call void @__free_recursive(ptr %t134)
  br label %case.end.4.130
case.end.4.130:
  br label %case.join.120
case.default.119:
  unreachable
case.join.120:
  %t401 = phi ptr [ %t125, %case.end.3.122 ], [ %t400, %case.end.4.130 ]
  call void @__free_recursive(ptr %t115)
  br label %case.end.4.111
case.end.4.111:
  br label %case.join.101
case.default.100:
  unreachable
case.join.101:
  %t402 = phi ptr [ %t106, %case.end.3.103 ], [ %t401, %case.end.4.111 ]
  call void @__free_recursive(ptr %t96)
  br label %case.end.4.92
case.end.4.92:
  br label %case.join.82
case.default.81:
  unreachable
case.join.82:
  %t403 = phi ptr [ %t87, %case.end.3.84 ], [ %t402, %case.end.4.92 ]
  call void @__free_recursive(ptr %t77)
  br label %case.end.4.73
case.end.4.73:
  br label %case.join.63
case.default.62:
  unreachable
case.join.63:
  %t404 = phi ptr [ %t68, %case.end.3.65 ], [ %t403, %case.end.4.73 ]
  call void @__free_recursive(ptr %t58)
  br label %case.end.4.54
case.end.4.54:
  br label %case.join.44
case.default.43:
  unreachable
case.join.44:
  %t405 = phi ptr [ %t49, %case.end.3.46 ], [ %t404, %case.end.4.54 ]
  call void @__free_recursive(ptr %t39)
  br label %case.end.4.35
case.end.4.35:
  br label %case.join.25
case.default.24:
  unreachable
case.join.25:
  %t406 = phi ptr [ %t30, %case.end.3.27 ], [ %t405, %case.end.4.35 ]
  call void @__free_recursive(ptr %t20)
  br label %case.end.4.16
case.end.4.16:
  br label %case.join.6
case.default.5:
  unreachable
case.join.6:
  %t407 = phi ptr [ %t11, %case.end.3.8 ], [ %t406, %case.end.4.16 ]
  call void @__free_recursive(ptr %t1)
  %t408 = call ptr @v__let_13(ptr %t407)
  ret ptr %t408
}

define internal ptr @v__let_13(ptr %v_res) {
  %t0 = getelementptr ptr, ptr %v_res, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.19 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v_res, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = call ptr @__alloc(i64 24, i32 2)
  %t8 = inttoptr i64 7 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = getelementptr ptr, ptr %t7, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.17, i64 12), ptr %t10
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
  call void @__free_recursive(ptr %v_res)
  ret ptr %t7
case.arm.4.19:
  %t20 = getelementptr ptr, ptr %v_res, i32 1
  %t21 = load ptr, ptr %t20
  call void @__inc_ref(ptr %t21)
  %t22 = call ptr @__alloc(i64 24, i32 2)
  %t23 = inttoptr i64 7 to ptr
  %t24 = getelementptr ptr, ptr %t22, i32 0
  store ptr %t23, ptr %t24
  call void @__inc_ref(ptr %t21)
  %t25 = getelementptr ptr, ptr %t22, i32 1
  store ptr %t21, ptr %t25
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
  call void @__free_recursive(ptr %v_res)
  ret ptr %t22
case.default.3:
  unreachable
}

declare i32 @_setmode(i32, i32)

define i32 @main(i32 %argc_posix, ptr %argv_posix) {
entry:
  call i32 @_setmode(i32 1, i32 32768)
  call i32 @_setmode(i32 0, i32 32768)
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
