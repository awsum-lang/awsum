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
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"," }
@.str.6 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"a,b,c" }
@.str.7 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"::" }
@.str.8 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"user::42::admin" }
@.str.9 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"x" }
@.str.10 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"abc" }
@.str.11 = private unnamed_addr constant {i32, i32, i32, i32, i32, [0 x i8]} { i32 0, i32 0, i32 0, i32 0, i32 0, [0 x i8] zeroinitializer }
@.str.12 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c":" }
@.str.13 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c":foo" }
@.str.14 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"foo:" }
@.str.15 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"abcde" }
@.str.16 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"ab" }
@.str.17 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c", " }

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
  %t15 = call ptr @__print(ptr %t14)
  %t16 = getelementptr ptr, ptr %t4, i32 2
  %t17 = load ptr, ptr %t16
  call void @__inc_ref(ptr %t17)
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t15)
  store ptr %t17, ptr %t3
  br label %tco.loop.0
tco.case.default.8:
  unreachable
tco.exit.1:
  %t18 = load ptr, ptr %t2
  ret ptr %t18
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
  %t12 = getelementptr ptr, ptr %t11, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t13)
  %t15 = getelementptr ptr, ptr %t14, i32 0
  %t16 = load ptr, ptr %t15
  %t17 = ptrtoint ptr %t16 to i64
  switch i64 %t17, label %case.default.18 [ i64 3, label %case.arm.3.19 i64 4, label %case.arm.4.26 ]
case.arm.3.19:
  %t20 = getelementptr ptr, ptr %t14, i32 1
  %t21 = load ptr, ptr %t20
  call void @__inc_ref(ptr %t21)
  %t22 = call ptr @__alloc(i64 16, i32 1)
  %t23 = inttoptr i64 3 to ptr
  %t24 = getelementptr ptr, ptr %t22, i32 0
  store ptr %t23, ptr %t24
  call void @__inc_ref(ptr %t21)
  %t25 = getelementptr ptr, ptr %t22, i32 1
  store ptr %t21, ptr %t25
  call void @__free_recursive(ptr %t14)
  call void @__free_recursive(ptr %t21)
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %v_r)
  ret ptr %t22
case.arm.4.26:
  %t27 = getelementptr ptr, ptr %t14, i32 1
  %t28 = load ptr, ptr %t27
  call void @__inc_ref(ptr %t28)
  call void @__inc_ref(ptr %t28)
  %t29 = call ptr @__concat(ptr %t28, ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
  %t30 = getelementptr ptr, ptr %t29, i32 0
  %t31 = load ptr, ptr %t30
  %t32 = ptrtoint ptr %t31 to i64
  switch i64 %t32, label %case.default.33 [ i64 3, label %case.arm.3.34 i64 4, label %case.arm.4.41 ]
case.arm.3.34:
  %t35 = getelementptr ptr, ptr %t29, i32 1
  %t36 = load ptr, ptr %t35
  call void @__inc_ref(ptr %t36)
  %t37 = call ptr @__alloc(i64 16, i32 1)
  %t38 = inttoptr i64 3 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  call void @__inc_ref(ptr %t36)
  %t40 = getelementptr ptr, ptr %t37, i32 1
  store ptr %t36, ptr %t40
  call void @__free_recursive(ptr %t29)
  call void @__free_recursive(ptr %t14)
  call void @__free_recursive(ptr %t36)
  call void @__free_recursive(ptr %t28)
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %v_r)
  ret ptr %t37
case.arm.4.41:
  %t42 = getelementptr ptr, ptr %t29, i32 1
  %t43 = load ptr, ptr %t42
  call void @__inc_ref(ptr %t43)
  call void @__inc_ref(ptr %t43)
  %t44 = getelementptr ptr, ptr %t11, i32 2
  %t45 = load ptr, ptr %t44
  call void @__inc_ref(ptr %t45)
  %t46 = call ptr @__concat(ptr %t43, ptr %t45)
  %t47 = getelementptr ptr, ptr %t46, i32 0
  %t48 = load ptr, ptr %t47
  %t49 = ptrtoint ptr %t48 to i64
  switch i64 %t49, label %case.default.50 [ i64 3, label %case.arm.3.51 i64 4, label %case.arm.4.58 ]
case.arm.3.51:
  %t52 = getelementptr ptr, ptr %t46, i32 1
  %t53 = load ptr, ptr %t52
  call void @__inc_ref(ptr %t53)
  %t54 = call ptr @__alloc(i64 16, i32 1)
  %t55 = inttoptr i64 3 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t53)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t53, ptr %t57
  call void @__free_recursive(ptr %t46)
  call void @__free_recursive(ptr %t29)
  call void @__free_recursive(ptr %t14)
  call void @__free_recursive(ptr %t53)
  call void @__free_recursive(ptr %t43)
  call void @__free_recursive(ptr %t28)
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %v_r)
  ret ptr %t54
case.arm.4.58:
  %t59 = getelementptr ptr, ptr %t46, i32 1
  %t60 = load ptr, ptr %t59
  call void @__inc_ref(ptr %t60)
  call void @__inc_ref(ptr %t60)
  %t61 = call ptr @__concat(ptr %t60, ptr getelementptr inbounds (i8, ptr @.str.3, i64 12))
  call void @__free_recursive(ptr %t46)
  call void @__free_recursive(ptr %t29)
  call void @__free_recursive(ptr %t14)
  call void @__free_recursive(ptr %t60)
  call void @__free_recursive(ptr %t43)
  call void @__free_recursive(ptr %t28)
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %v_r)
  ret ptr %t61
case.default.50:
  unreachable
case.default.33:
  unreachable
case.default.18:
  unreachable
case.default.3:
  unreachable
}

define internal ptr @v_main() {
  %v__inl10_scrut.jslot = alloca ptr
  %t2 = call ptr @__splitOnFirst(ptr getelementptr inbounds (i8, ptr @.str.5, i64 12), ptr getelementptr inbounds (i8, ptr @.str.6, i64 12))
  %t3 = call ptr @v_render(ptr %t2)
  %t4 = getelementptr ptr, ptr %t3, i32 0
  %t5 = load ptr, ptr %t4
  %t6 = ptrtoint ptr %t5 to i64
  switch i64 %t6, label %join.case.default.7 [ i64 3, label %join.case.arm.3.8 i64 4, label %join.case.arm.4.22 ]
join.case.arm.3.8:
  %t9 = call ptr @__alloc(i64 24, i32 2)
  %t10 = inttoptr i64 7 to ptr
  %t11 = getelementptr ptr, ptr %t9, i32 0
  store ptr %t10, ptr %t11
  %t12 = getelementptr ptr, ptr %t9, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t12
  %t13 = call ptr @__alloc(i64 16, i32 1)
  %t14 = inttoptr i64 5 to ptr
  %t15 = getelementptr ptr, ptr %t13, i32 0
  store ptr %t14, ptr %t15
  %t16 = call ptr @__alloc(i64 8, i32 0)
  %t17 = inttoptr i64 0 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = getelementptr ptr, ptr %t13, i32 1
  store ptr %t16, ptr %t19
  %t20 = getelementptr ptr, ptr %t9, i32 2
  store ptr %t13, ptr %t20
  call void @__free_recursive(ptr %t3)
  br label %join.val.21
join.val.21:
  br label %join.after.1
join.case.arm.4.22:
  %t23 = getelementptr ptr, ptr %t3, i32 1
  %t24 = load ptr, ptr %t23
  call void @__inc_ref(ptr %t24)
  %t25 = call ptr @__splitOnFirst(ptr getelementptr inbounds (i8, ptr @.str.7, i64 12), ptr getelementptr inbounds (i8, ptr @.str.8, i64 12))
  %t26 = call ptr @v_render(ptr %t25)
  %t27 = getelementptr ptr, ptr %t26, i32 0
  %t28 = load ptr, ptr %t27
  %t29 = ptrtoint ptr %t28 to i64
  switch i64 %t29, label %case.default.30 [ i64 3, label %case.arm.3.32 i64 4, label %case.arm.4.40 ]
case.arm.3.32:
  %t34 = getelementptr ptr, ptr %t26, i32 1
  %t35 = load ptr, ptr %t34
  call void @__inc_ref(ptr %t35)
  %t36 = call ptr @__alloc(i64 16, i32 1)
  %t37 = inttoptr i64 3 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  call void @__inc_ref(ptr %t35)
  %t39 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t35, ptr %t39
  br label %case.end.3.33
case.end.3.33:
  br label %case.join.31
case.arm.4.40:
  %t42 = getelementptr ptr, ptr %t26, i32 1
  %t43 = load ptr, ptr %t42
  call void @__inc_ref(ptr %t43)
  %t44 = call ptr @__splitOnFirst(ptr getelementptr inbounds (i8, ptr @.str.9, i64 12), ptr getelementptr inbounds (i8, ptr @.str.10, i64 12))
  %t45 = call ptr @v_render(ptr %t44)
  %t46 = getelementptr ptr, ptr %t45, i32 0
  %t47 = load ptr, ptr %t46
  %t48 = ptrtoint ptr %t47 to i64
  switch i64 %t48, label %case.default.49 [ i64 3, label %case.arm.3.51 i64 4, label %case.arm.4.59 ]
case.arm.3.51:
  %t53 = getelementptr ptr, ptr %t45, i32 1
  %t54 = load ptr, ptr %t53
  call void @__inc_ref(ptr %t54)
  %t55 = call ptr @__alloc(i64 16, i32 1)
  %t56 = inttoptr i64 3 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  call void @__inc_ref(ptr %t54)
  %t58 = getelementptr ptr, ptr %t55, i32 1
  store ptr %t54, ptr %t58
  br label %case.end.3.52
case.end.3.52:
  br label %case.join.50
case.arm.4.59:
  %t61 = getelementptr ptr, ptr %t45, i32 1
  %t62 = load ptr, ptr %t61
  call void @__inc_ref(ptr %t62)
  %t63 = call ptr @__splitOnFirst(ptr getelementptr inbounds (i8, ptr @.str.11, i64 12), ptr getelementptr inbounds (i8, ptr @.str.10, i64 12))
  %t64 = call ptr @v_render(ptr %t63)
  %t65 = getelementptr ptr, ptr %t64, i32 0
  %t66 = load ptr, ptr %t65
  %t67 = ptrtoint ptr %t66 to i64
  switch i64 %t67, label %case.default.68 [ i64 3, label %case.arm.3.70 i64 4, label %case.arm.4.78 ]
case.arm.3.70:
  %t72 = getelementptr ptr, ptr %t64, i32 1
  %t73 = load ptr, ptr %t72
  call void @__inc_ref(ptr %t73)
  %t74 = call ptr @__alloc(i64 16, i32 1)
  %t75 = inttoptr i64 3 to ptr
  %t76 = getelementptr ptr, ptr %t74, i32 0
  store ptr %t75, ptr %t76
  call void @__inc_ref(ptr %t73)
  %t77 = getelementptr ptr, ptr %t74, i32 1
  store ptr %t73, ptr %t77
  br label %case.end.3.71
case.end.3.71:
  br label %case.join.69
case.arm.4.78:
  %t80 = getelementptr ptr, ptr %t64, i32 1
  %t81 = load ptr, ptr %t80
  call void @__inc_ref(ptr %t81)
  %t82 = call ptr @__splitOnFirst(ptr getelementptr inbounds (i8, ptr @.str.12, i64 12), ptr getelementptr inbounds (i8, ptr @.str.13, i64 12))
  %t83 = call ptr @v_render(ptr %t82)
  %t84 = getelementptr ptr, ptr %t83, i32 0
  %t85 = load ptr, ptr %t84
  %t86 = ptrtoint ptr %t85 to i64
  switch i64 %t86, label %case.default.87 [ i64 3, label %case.arm.3.89 i64 4, label %case.arm.4.97 ]
case.arm.3.89:
  %t91 = getelementptr ptr, ptr %t83, i32 1
  %t92 = load ptr, ptr %t91
  call void @__inc_ref(ptr %t92)
  %t93 = call ptr @__alloc(i64 16, i32 1)
  %t94 = inttoptr i64 3 to ptr
  %t95 = getelementptr ptr, ptr %t93, i32 0
  store ptr %t94, ptr %t95
  call void @__inc_ref(ptr %t92)
  %t96 = getelementptr ptr, ptr %t93, i32 1
  store ptr %t92, ptr %t96
  br label %case.end.3.90
case.end.3.90:
  br label %case.join.88
case.arm.4.97:
  %t99 = getelementptr ptr, ptr %t83, i32 1
  %t100 = load ptr, ptr %t99
  call void @__inc_ref(ptr %t100)
  %t101 = call ptr @__splitOnFirst(ptr getelementptr inbounds (i8, ptr @.str.12, i64 12), ptr getelementptr inbounds (i8, ptr @.str.14, i64 12))
  %t102 = call ptr @v_render(ptr %t101)
  %t103 = getelementptr ptr, ptr %t102, i32 0
  %t104 = load ptr, ptr %t103
  %t105 = ptrtoint ptr %t104 to i64
  switch i64 %t105, label %case.default.106 [ i64 3, label %case.arm.3.108 i64 4, label %case.arm.4.116 ]
case.arm.3.108:
  %t110 = getelementptr ptr, ptr %t102, i32 1
  %t111 = load ptr, ptr %t110
  call void @__inc_ref(ptr %t111)
  %t112 = call ptr @__alloc(i64 16, i32 1)
  %t113 = inttoptr i64 3 to ptr
  %t114 = getelementptr ptr, ptr %t112, i32 0
  store ptr %t113, ptr %t114
  call void @__inc_ref(ptr %t111)
  %t115 = getelementptr ptr, ptr %t112, i32 1
  store ptr %t111, ptr %t115
  br label %case.end.3.109
case.end.3.109:
  br label %case.join.107
case.arm.4.116:
  %t118 = getelementptr ptr, ptr %t102, i32 1
  %t119 = load ptr, ptr %t118
  call void @__inc_ref(ptr %t119)
  %t120 = call ptr @__splitOnFirst(ptr getelementptr inbounds (i8, ptr @.str.10, i64 12), ptr getelementptr inbounds (i8, ptr @.str.10, i64 12))
  %t121 = call ptr @v_render(ptr %t120)
  %t122 = getelementptr ptr, ptr %t121, i32 0
  %t123 = load ptr, ptr %t122
  %t124 = ptrtoint ptr %t123 to i64
  switch i64 %t124, label %case.default.125 [ i64 3, label %case.arm.3.127 i64 4, label %case.arm.4.135 ]
case.arm.3.127:
  %t129 = getelementptr ptr, ptr %t121, i32 1
  %t130 = load ptr, ptr %t129
  call void @__inc_ref(ptr %t130)
  %t131 = call ptr @__alloc(i64 16, i32 1)
  %t132 = inttoptr i64 3 to ptr
  %t133 = getelementptr ptr, ptr %t131, i32 0
  store ptr %t132, ptr %t133
  call void @__inc_ref(ptr %t130)
  %t134 = getelementptr ptr, ptr %t131, i32 1
  store ptr %t130, ptr %t134
  br label %case.end.3.128
case.end.3.128:
  br label %case.join.126
case.arm.4.135:
  %t137 = getelementptr ptr, ptr %t121, i32 1
  %t138 = load ptr, ptr %t137
  call void @__inc_ref(ptr %t138)
  %t139 = call ptr @__splitOnFirst(ptr getelementptr inbounds (i8, ptr @.str.15, i64 12), ptr getelementptr inbounds (i8, ptr @.str.16, i64 12))
  %t140 = call ptr @v_render(ptr %t139)
  %t141 = getelementptr ptr, ptr %t140, i32 0
  %t142 = load ptr, ptr %t141
  %t143 = ptrtoint ptr %t142 to i64
  switch i64 %t143, label %case.default.144 [ i64 3, label %case.arm.3.146 i64 4, label %case.arm.4.154 ]
case.arm.3.146:
  %t148 = getelementptr ptr, ptr %t140, i32 1
  %t149 = load ptr, ptr %t148
  call void @__inc_ref(ptr %t149)
  %t150 = call ptr @__alloc(i64 16, i32 1)
  %t151 = inttoptr i64 3 to ptr
  %t152 = getelementptr ptr, ptr %t150, i32 0
  store ptr %t151, ptr %t152
  call void @__inc_ref(ptr %t149)
  %t153 = getelementptr ptr, ptr %t150, i32 1
  store ptr %t149, ptr %t153
  br label %case.end.3.147
case.end.3.147:
  br label %case.join.145
case.arm.4.154:
  %t156 = getelementptr ptr, ptr %t140, i32 1
  %t157 = load ptr, ptr %t156
  call void @__inc_ref(ptr %t157)
  call void @__inc_ref(ptr %t24)
  %t158 = call ptr @__concat(ptr %t24, ptr getelementptr inbounds (i8, ptr @.str.17, i64 12))
  %t159 = getelementptr ptr, ptr %t158, i32 0
  %t160 = load ptr, ptr %t159
  %t161 = ptrtoint ptr %t160 to i64
  switch i64 %t161, label %case.default.162 [ i64 3, label %case.arm.3.164 i64 4, label %case.arm.4.172 ]
case.arm.3.164:
  %t166 = getelementptr ptr, ptr %t158, i32 1
  %t167 = load ptr, ptr %t166
  call void @__inc_ref(ptr %t167)
  %t168 = call ptr @__alloc(i64 16, i32 1)
  %t169 = inttoptr i64 3 to ptr
  %t170 = getelementptr ptr, ptr %t168, i32 0
  store ptr %t169, ptr %t170
  call void @__inc_ref(ptr %t167)
  %t171 = getelementptr ptr, ptr %t168, i32 1
  store ptr %t167, ptr %t171
  br label %case.end.3.165
case.end.3.165:
  br label %case.join.163
case.arm.4.172:
  %t174 = getelementptr ptr, ptr %t158, i32 1
  %t175 = load ptr, ptr %t174
  call void @__inc_ref(ptr %t175)
  call void @__inc_ref(ptr %t175)
  call void @__inc_ref(ptr %t43)
  %t176 = call ptr @__concat(ptr %t175, ptr %t43)
  %t177 = getelementptr ptr, ptr %t176, i32 0
  %t178 = load ptr, ptr %t177
  %t179 = ptrtoint ptr %t178 to i64
  switch i64 %t179, label %case.default.180 [ i64 3, label %case.arm.3.182 i64 4, label %case.arm.4.190 ]
case.arm.3.182:
  %t184 = getelementptr ptr, ptr %t176, i32 1
  %t185 = load ptr, ptr %t184
  call void @__inc_ref(ptr %t185)
  %t186 = call ptr @__alloc(i64 16, i32 1)
  %t187 = inttoptr i64 3 to ptr
  %t188 = getelementptr ptr, ptr %t186, i32 0
  store ptr %t187, ptr %t188
  call void @__inc_ref(ptr %t185)
  %t189 = getelementptr ptr, ptr %t186, i32 1
  store ptr %t185, ptr %t189
  br label %case.end.3.183
case.end.3.183:
  br label %case.join.181
case.arm.4.190:
  %t192 = getelementptr ptr, ptr %t176, i32 1
  %t193 = load ptr, ptr %t192
  call void @__inc_ref(ptr %t193)
  call void @__inc_ref(ptr %t193)
  %t194 = call ptr @__concat(ptr %t193, ptr getelementptr inbounds (i8, ptr @.str.17, i64 12))
  %t195 = getelementptr ptr, ptr %t194, i32 0
  %t196 = load ptr, ptr %t195
  %t197 = ptrtoint ptr %t196 to i64
  switch i64 %t197, label %case.default.198 [ i64 3, label %case.arm.3.200 i64 4, label %case.arm.4.208 ]
case.arm.3.200:
  %t202 = getelementptr ptr, ptr %t194, i32 1
  %t203 = load ptr, ptr %t202
  call void @__inc_ref(ptr %t203)
  %t204 = call ptr @__alloc(i64 16, i32 1)
  %t205 = inttoptr i64 3 to ptr
  %t206 = getelementptr ptr, ptr %t204, i32 0
  store ptr %t205, ptr %t206
  call void @__inc_ref(ptr %t203)
  %t207 = getelementptr ptr, ptr %t204, i32 1
  store ptr %t203, ptr %t207
  br label %case.end.3.201
case.end.3.201:
  br label %case.join.199
case.arm.4.208:
  %t210 = getelementptr ptr, ptr %t194, i32 1
  %t211 = load ptr, ptr %t210
  call void @__inc_ref(ptr %t211)
  call void @__inc_ref(ptr %t211)
  call void @__inc_ref(ptr %t62)
  %t212 = call ptr @__concat(ptr %t211, ptr %t62)
  %t213 = getelementptr ptr, ptr %t212, i32 0
  %t214 = load ptr, ptr %t213
  %t215 = ptrtoint ptr %t214 to i64
  switch i64 %t215, label %case.default.216 [ i64 3, label %case.arm.3.218 i64 4, label %case.arm.4.226 ]
case.arm.3.218:
  %t220 = getelementptr ptr, ptr %t212, i32 1
  %t221 = load ptr, ptr %t220
  call void @__inc_ref(ptr %t221)
  %t222 = call ptr @__alloc(i64 16, i32 1)
  %t223 = inttoptr i64 3 to ptr
  %t224 = getelementptr ptr, ptr %t222, i32 0
  store ptr %t223, ptr %t224
  call void @__inc_ref(ptr %t221)
  %t225 = getelementptr ptr, ptr %t222, i32 1
  store ptr %t221, ptr %t225
  br label %case.end.3.219
case.end.3.219:
  br label %case.join.217
case.arm.4.226:
  %t228 = getelementptr ptr, ptr %t212, i32 1
  %t229 = load ptr, ptr %t228
  call void @__inc_ref(ptr %t229)
  call void @__inc_ref(ptr %t229)
  %t230 = call ptr @__concat(ptr %t229, ptr getelementptr inbounds (i8, ptr @.str.17, i64 12))
  %t231 = getelementptr ptr, ptr %t230, i32 0
  %t232 = load ptr, ptr %t231
  %t233 = ptrtoint ptr %t232 to i64
  switch i64 %t233, label %case.default.234 [ i64 3, label %case.arm.3.236 i64 4, label %case.arm.4.244 ]
case.arm.3.236:
  %t238 = getelementptr ptr, ptr %t230, i32 1
  %t239 = load ptr, ptr %t238
  call void @__inc_ref(ptr %t239)
  %t240 = call ptr @__alloc(i64 16, i32 1)
  %t241 = inttoptr i64 3 to ptr
  %t242 = getelementptr ptr, ptr %t240, i32 0
  store ptr %t241, ptr %t242
  call void @__inc_ref(ptr %t239)
  %t243 = getelementptr ptr, ptr %t240, i32 1
  store ptr %t239, ptr %t243
  br label %case.end.3.237
case.end.3.237:
  br label %case.join.235
case.arm.4.244:
  %t246 = getelementptr ptr, ptr %t230, i32 1
  %t247 = load ptr, ptr %t246
  call void @__inc_ref(ptr %t247)
  call void @__inc_ref(ptr %t247)
  call void @__inc_ref(ptr %t81)
  %t248 = call ptr @__concat(ptr %t247, ptr %t81)
  %t249 = getelementptr ptr, ptr %t248, i32 0
  %t250 = load ptr, ptr %t249
  %t251 = ptrtoint ptr %t250 to i64
  switch i64 %t251, label %case.default.252 [ i64 3, label %case.arm.3.254 i64 4, label %case.arm.4.262 ]
case.arm.3.254:
  %t256 = getelementptr ptr, ptr %t248, i32 1
  %t257 = load ptr, ptr %t256
  call void @__inc_ref(ptr %t257)
  %t258 = call ptr @__alloc(i64 16, i32 1)
  %t259 = inttoptr i64 3 to ptr
  %t260 = getelementptr ptr, ptr %t258, i32 0
  store ptr %t259, ptr %t260
  call void @__inc_ref(ptr %t257)
  %t261 = getelementptr ptr, ptr %t258, i32 1
  store ptr %t257, ptr %t261
  br label %case.end.3.255
case.end.3.255:
  br label %case.join.253
case.arm.4.262:
  %t264 = getelementptr ptr, ptr %t248, i32 1
  %t265 = load ptr, ptr %t264
  call void @__inc_ref(ptr %t265)
  call void @__inc_ref(ptr %t265)
  %t266 = call ptr @__concat(ptr %t265, ptr getelementptr inbounds (i8, ptr @.str.17, i64 12))
  %t267 = getelementptr ptr, ptr %t266, i32 0
  %t268 = load ptr, ptr %t267
  %t269 = ptrtoint ptr %t268 to i64
  switch i64 %t269, label %case.default.270 [ i64 3, label %case.arm.3.272 i64 4, label %case.arm.4.280 ]
case.arm.3.272:
  %t274 = getelementptr ptr, ptr %t266, i32 1
  %t275 = load ptr, ptr %t274
  call void @__inc_ref(ptr %t275)
  %t276 = call ptr @__alloc(i64 16, i32 1)
  %t277 = inttoptr i64 3 to ptr
  %t278 = getelementptr ptr, ptr %t276, i32 0
  store ptr %t277, ptr %t278
  call void @__inc_ref(ptr %t275)
  %t279 = getelementptr ptr, ptr %t276, i32 1
  store ptr %t275, ptr %t279
  br label %case.end.3.273
case.end.3.273:
  br label %case.join.271
case.arm.4.280:
  %t282 = getelementptr ptr, ptr %t266, i32 1
  %t283 = load ptr, ptr %t282
  call void @__inc_ref(ptr %t283)
  call void @__inc_ref(ptr %t283)
  call void @__inc_ref(ptr %t100)
  %t284 = call ptr @__concat(ptr %t283, ptr %t100)
  %t285 = getelementptr ptr, ptr %t284, i32 0
  %t286 = load ptr, ptr %t285
  %t287 = ptrtoint ptr %t286 to i64
  switch i64 %t287, label %case.default.288 [ i64 3, label %case.arm.3.290 i64 4, label %case.arm.4.298 ]
case.arm.3.290:
  %t292 = getelementptr ptr, ptr %t284, i32 1
  %t293 = load ptr, ptr %t292
  call void @__inc_ref(ptr %t293)
  %t294 = call ptr @__alloc(i64 16, i32 1)
  %t295 = inttoptr i64 3 to ptr
  %t296 = getelementptr ptr, ptr %t294, i32 0
  store ptr %t295, ptr %t296
  call void @__inc_ref(ptr %t293)
  %t297 = getelementptr ptr, ptr %t294, i32 1
  store ptr %t293, ptr %t297
  br label %case.end.3.291
case.end.3.291:
  br label %case.join.289
case.arm.4.298:
  %t300 = getelementptr ptr, ptr %t284, i32 1
  %t301 = load ptr, ptr %t300
  call void @__inc_ref(ptr %t301)
  call void @__inc_ref(ptr %t301)
  %t302 = call ptr @__concat(ptr %t301, ptr getelementptr inbounds (i8, ptr @.str.17, i64 12))
  %t303 = getelementptr ptr, ptr %t302, i32 0
  %t304 = load ptr, ptr %t303
  %t305 = ptrtoint ptr %t304 to i64
  switch i64 %t305, label %case.default.306 [ i64 3, label %case.arm.3.308 i64 4, label %case.arm.4.316 ]
case.arm.3.308:
  %t310 = getelementptr ptr, ptr %t302, i32 1
  %t311 = load ptr, ptr %t310
  call void @__inc_ref(ptr %t311)
  %t312 = call ptr @__alloc(i64 16, i32 1)
  %t313 = inttoptr i64 3 to ptr
  %t314 = getelementptr ptr, ptr %t312, i32 0
  store ptr %t313, ptr %t314
  call void @__inc_ref(ptr %t311)
  %t315 = getelementptr ptr, ptr %t312, i32 1
  store ptr %t311, ptr %t315
  br label %case.end.3.309
case.end.3.309:
  br label %case.join.307
case.arm.4.316:
  %t318 = getelementptr ptr, ptr %t302, i32 1
  %t319 = load ptr, ptr %t318
  call void @__inc_ref(ptr %t319)
  call void @__inc_ref(ptr %t319)
  call void @__inc_ref(ptr %t119)
  %t320 = call ptr @__concat(ptr %t319, ptr %t119)
  %t321 = getelementptr ptr, ptr %t320, i32 0
  %t322 = load ptr, ptr %t321
  %t323 = ptrtoint ptr %t322 to i64
  switch i64 %t323, label %case.default.324 [ i64 3, label %case.arm.3.326 i64 4, label %case.arm.4.334 ]
case.arm.3.326:
  %t328 = getelementptr ptr, ptr %t320, i32 1
  %t329 = load ptr, ptr %t328
  call void @__inc_ref(ptr %t329)
  %t330 = call ptr @__alloc(i64 16, i32 1)
  %t331 = inttoptr i64 3 to ptr
  %t332 = getelementptr ptr, ptr %t330, i32 0
  store ptr %t331, ptr %t332
  call void @__inc_ref(ptr %t329)
  %t333 = getelementptr ptr, ptr %t330, i32 1
  store ptr %t329, ptr %t333
  br label %case.end.3.327
case.end.3.327:
  br label %case.join.325
case.arm.4.334:
  %t336 = getelementptr ptr, ptr %t320, i32 1
  %t337 = load ptr, ptr %t336
  call void @__inc_ref(ptr %t337)
  call void @__inc_ref(ptr %t337)
  %t338 = call ptr @__concat(ptr %t337, ptr getelementptr inbounds (i8, ptr @.str.17, i64 12))
  %t339 = getelementptr ptr, ptr %t338, i32 0
  %t340 = load ptr, ptr %t339
  %t341 = ptrtoint ptr %t340 to i64
  switch i64 %t341, label %case.default.342 [ i64 3, label %case.arm.3.344 i64 4, label %case.arm.4.352 ]
case.arm.3.344:
  %t346 = getelementptr ptr, ptr %t338, i32 1
  %t347 = load ptr, ptr %t346
  call void @__inc_ref(ptr %t347)
  %t348 = call ptr @__alloc(i64 16, i32 1)
  %t349 = inttoptr i64 3 to ptr
  %t350 = getelementptr ptr, ptr %t348, i32 0
  store ptr %t349, ptr %t350
  call void @__inc_ref(ptr %t347)
  %t351 = getelementptr ptr, ptr %t348, i32 1
  store ptr %t347, ptr %t351
  br label %case.end.3.345
case.end.3.345:
  br label %case.join.343
case.arm.4.352:
  %t354 = getelementptr ptr, ptr %t338, i32 1
  %t355 = load ptr, ptr %t354
  call void @__inc_ref(ptr %t355)
  call void @__inc_ref(ptr %t355)
  call void @__inc_ref(ptr %t138)
  %t356 = call ptr @__concat(ptr %t355, ptr %t138)
  %t357 = getelementptr ptr, ptr %t356, i32 0
  %t358 = load ptr, ptr %t357
  %t359 = ptrtoint ptr %t358 to i64
  switch i64 %t359, label %case.default.360 [ i64 3, label %case.arm.3.362 i64 4, label %case.arm.4.370 ]
case.arm.3.362:
  %t364 = getelementptr ptr, ptr %t356, i32 1
  %t365 = load ptr, ptr %t364
  call void @__inc_ref(ptr %t365)
  %t366 = call ptr @__alloc(i64 16, i32 1)
  %t367 = inttoptr i64 3 to ptr
  %t368 = getelementptr ptr, ptr %t366, i32 0
  store ptr %t367, ptr %t368
  call void @__inc_ref(ptr %t365)
  %t369 = getelementptr ptr, ptr %t366, i32 1
  store ptr %t365, ptr %t369
  br label %case.end.3.363
case.end.3.363:
  br label %case.join.361
case.arm.4.370:
  %t372 = getelementptr ptr, ptr %t356, i32 1
  %t373 = load ptr, ptr %t372
  call void @__inc_ref(ptr %t373)
  call void @__inc_ref(ptr %t373)
  %t374 = call ptr @__concat(ptr %t373, ptr getelementptr inbounds (i8, ptr @.str.17, i64 12))
  %t375 = getelementptr ptr, ptr %t374, i32 0
  %t376 = load ptr, ptr %t375
  %t377 = ptrtoint ptr %t376 to i64
  switch i64 %t377, label %case.default.378 [ i64 3, label %case.arm.3.380 i64 4, label %case.arm.4.388 ]
case.arm.3.380:
  %t382 = getelementptr ptr, ptr %t374, i32 1
  %t383 = load ptr, ptr %t382
  call void @__inc_ref(ptr %t383)
  %t384 = call ptr @__alloc(i64 16, i32 1)
  %t385 = inttoptr i64 3 to ptr
  %t386 = getelementptr ptr, ptr %t384, i32 0
  store ptr %t385, ptr %t386
  call void @__inc_ref(ptr %t383)
  %t387 = getelementptr ptr, ptr %t384, i32 1
  store ptr %t383, ptr %t387
  br label %case.end.3.381
case.end.3.381:
  br label %case.join.379
case.arm.4.388:
  %t390 = getelementptr ptr, ptr %t374, i32 1
  %t391 = load ptr, ptr %t390
  call void @__inc_ref(ptr %t391)
  call void @__inc_ref(ptr %t391)
  call void @__inc_ref(ptr %t157)
  %t392 = call ptr @__concat(ptr %t391, ptr %t157)
  br label %case.end.4.389
case.end.4.389:
  br label %case.join.379
case.default.378:
  unreachable
case.join.379:
  %t393 = phi ptr [ %t384, %case.end.3.381 ], [ %t392, %case.end.4.389 ]
  call void @__free_recursive(ptr %t374)
  br label %case.end.4.371
case.end.4.371:
  br label %case.join.361
case.default.360:
  unreachable
case.join.361:
  %t394 = phi ptr [ %t366, %case.end.3.363 ], [ %t393, %case.end.4.371 ]
  call void @__free_recursive(ptr %t356)
  br label %case.end.4.353
case.end.4.353:
  br label %case.join.343
case.default.342:
  unreachable
case.join.343:
  %t395 = phi ptr [ %t348, %case.end.3.345 ], [ %t394, %case.end.4.353 ]
  call void @__free_recursive(ptr %t338)
  br label %case.end.4.335
case.end.4.335:
  br label %case.join.325
case.default.324:
  unreachable
case.join.325:
  %t396 = phi ptr [ %t330, %case.end.3.327 ], [ %t395, %case.end.4.335 ]
  call void @__free_recursive(ptr %t320)
  br label %case.end.4.317
case.end.4.317:
  br label %case.join.307
case.default.306:
  unreachable
case.join.307:
  %t397 = phi ptr [ %t312, %case.end.3.309 ], [ %t396, %case.end.4.317 ]
  call void @__free_recursive(ptr %t302)
  br label %case.end.4.299
case.end.4.299:
  br label %case.join.289
case.default.288:
  unreachable
case.join.289:
  %t398 = phi ptr [ %t294, %case.end.3.291 ], [ %t397, %case.end.4.299 ]
  call void @__free_recursive(ptr %t284)
  br label %case.end.4.281
case.end.4.281:
  br label %case.join.271
case.default.270:
  unreachable
case.join.271:
  %t399 = phi ptr [ %t276, %case.end.3.273 ], [ %t398, %case.end.4.281 ]
  call void @__free_recursive(ptr %t266)
  br label %case.end.4.263
case.end.4.263:
  br label %case.join.253
case.default.252:
  unreachable
case.join.253:
  %t400 = phi ptr [ %t258, %case.end.3.255 ], [ %t399, %case.end.4.263 ]
  call void @__free_recursive(ptr %t248)
  br label %case.end.4.245
case.end.4.245:
  br label %case.join.235
case.default.234:
  unreachable
case.join.235:
  %t401 = phi ptr [ %t240, %case.end.3.237 ], [ %t400, %case.end.4.245 ]
  call void @__free_recursive(ptr %t230)
  br label %case.end.4.227
case.end.4.227:
  br label %case.join.217
case.default.216:
  unreachable
case.join.217:
  %t402 = phi ptr [ %t222, %case.end.3.219 ], [ %t401, %case.end.4.227 ]
  call void @__free_recursive(ptr %t212)
  br label %case.end.4.209
case.end.4.209:
  br label %case.join.199
case.default.198:
  unreachable
case.join.199:
  %t403 = phi ptr [ %t204, %case.end.3.201 ], [ %t402, %case.end.4.209 ]
  call void @__free_recursive(ptr %t194)
  br label %case.end.4.191
case.end.4.191:
  br label %case.join.181
case.default.180:
  unreachable
case.join.181:
  %t404 = phi ptr [ %t186, %case.end.3.183 ], [ %t403, %case.end.4.191 ]
  call void @__free_recursive(ptr %t176)
  br label %case.end.4.173
case.end.4.173:
  br label %case.join.163
case.default.162:
  unreachable
case.join.163:
  %t405 = phi ptr [ %t168, %case.end.3.165 ], [ %t404, %case.end.4.173 ]
  call void @__free_recursive(ptr %t158)
  br label %case.end.4.155
case.end.4.155:
  br label %case.join.145
case.default.144:
  unreachable
case.join.145:
  %t406 = phi ptr [ %t150, %case.end.3.147 ], [ %t405, %case.end.4.155 ]
  call void @__free_recursive(ptr %t140)
  br label %case.end.4.136
case.end.4.136:
  br label %case.join.126
case.default.125:
  unreachable
case.join.126:
  %t407 = phi ptr [ %t131, %case.end.3.128 ], [ %t406, %case.end.4.136 ]
  call void @__free_recursive(ptr %t121)
  br label %case.end.4.117
case.end.4.117:
  br label %case.join.107
case.default.106:
  unreachable
case.join.107:
  %t408 = phi ptr [ %t112, %case.end.3.109 ], [ %t407, %case.end.4.117 ]
  call void @__free_recursive(ptr %t102)
  br label %case.end.4.98
case.end.4.98:
  br label %case.join.88
case.default.87:
  unreachable
case.join.88:
  %t409 = phi ptr [ %t93, %case.end.3.90 ], [ %t408, %case.end.4.98 ]
  call void @__free_recursive(ptr %t83)
  br label %case.end.4.79
case.end.4.79:
  br label %case.join.69
case.default.68:
  unreachable
case.join.69:
  %t410 = phi ptr [ %t74, %case.end.3.71 ], [ %t409, %case.end.4.79 ]
  call void @__free_recursive(ptr %t64)
  br label %case.end.4.60
case.end.4.60:
  br label %case.join.50
case.default.49:
  unreachable
case.join.50:
  %t411 = phi ptr [ %t55, %case.end.3.52 ], [ %t410, %case.end.4.60 ]
  call void @__free_recursive(ptr %t45)
  br label %case.end.4.41
case.end.4.41:
  br label %case.join.31
case.default.30:
  unreachable
case.join.31:
  %t412 = phi ptr [ %t36, %case.end.3.33 ], [ %t411, %case.end.4.41 ]
  call void @__free_recursive(ptr %t26)
  call void @__free_recursive(ptr %t3)
  store ptr %t412, ptr %v__inl10_scrut.jslot
  br label %join.0
join.case.default.7:
  unreachable
join.0:
  %t413 = load ptr, ptr %v__inl10_scrut.jslot
  %t414 = getelementptr ptr, ptr %t413, i32 0
  %t415 = load ptr, ptr %t414
  %t416 = ptrtoint ptr %t415 to i64
  switch i64 %t416, label %case.default.417 [ i64 3, label %case.arm.3.419 i64 4, label %case.arm.4.433 ]
case.arm.3.419:
  %t421 = call ptr @__alloc(i64 24, i32 2)
  %t422 = inttoptr i64 7 to ptr
  %t423 = getelementptr ptr, ptr %t421, i32 0
  store ptr %t422, ptr %t423
  %t424 = getelementptr ptr, ptr %t421, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t424
  %t425 = call ptr @__alloc(i64 16, i32 1)
  %t426 = inttoptr i64 5 to ptr
  %t427 = getelementptr ptr, ptr %t425, i32 0
  store ptr %t426, ptr %t427
  %t428 = call ptr @__alloc(i64 8, i32 0)
  %t429 = inttoptr i64 0 to ptr
  %t430 = getelementptr ptr, ptr %t428, i32 0
  store ptr %t429, ptr %t430
  %t431 = getelementptr ptr, ptr %t425, i32 1
  store ptr %t428, ptr %t431
  %t432 = getelementptr ptr, ptr %t421, i32 2
  store ptr %t425, ptr %t432
  br label %case.end.3.420
case.end.3.420:
  br label %case.join.418
case.arm.4.433:
  %t435 = call ptr @__alloc(i64 24, i32 2)
  %t436 = inttoptr i64 7 to ptr
  %t437 = getelementptr ptr, ptr %t435, i32 0
  store ptr %t436, ptr %t437
  %t438 = getelementptr ptr, ptr %t413, i32 1
  %t439 = load ptr, ptr %t438
  call void @__inc_ref(ptr %t439)
  %t440 = getelementptr ptr, ptr %t435, i32 1
  store ptr %t439, ptr %t440
  %t441 = call ptr @__alloc(i64 16, i32 1)
  %t442 = inttoptr i64 5 to ptr
  %t443 = getelementptr ptr, ptr %t441, i32 0
  store ptr %t442, ptr %t443
  %t444 = call ptr @__alloc(i64 8, i32 0)
  %t445 = inttoptr i64 0 to ptr
  %t446 = getelementptr ptr, ptr %t444, i32 0
  store ptr %t445, ptr %t446
  %t447 = getelementptr ptr, ptr %t441, i32 1
  store ptr %t444, ptr %t447
  %t448 = getelementptr ptr, ptr %t435, i32 2
  store ptr %t441, ptr %t448
  br label %case.end.4.434
case.end.4.434:
  br label %case.join.418
case.default.417:
  unreachable
case.join.418:
  %t449 = phi ptr [ %t421, %case.end.3.420 ], [ %t435, %case.end.4.434 ]
  call void @__free_recursive(ptr %t413)
  br label %join.end.450
join.end.450:
  br label %join.after.1
join.after.1:
  %t451 = phi ptr [ %t9, %join.val.21 ], [ %t449, %join.end.450 ]
  ret ptr %t451
}

define i32 @main(i32 %argc, ptr %argv) {
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
