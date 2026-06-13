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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c":" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"X:Y:Z" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [8 x i8]} { i32 0, i32 0, i32 0, i32 8, i32 8, [8 x i8] c"NO_OUTER" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [8 x i8]} { i32 0, i32 0, i32 0, i32 8, i32 8, [8 x i8] c"NO_INNER" }

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

define internal ptr @v_main() {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 7 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__splitOnFirst(ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  %t4 = getelementptr ptr, ptr %t3, i32 0
  %t5 = load ptr, ptr %t4
  %t6 = ptrtoint ptr %t5 to i64
  switch i64 %t6, label %case.default.7 [ i64 11, label %case.arm.11.9 i64 12, label %case.arm.12.11 ]
case.arm.11.9:
  br label %case.end.11.10
case.end.11.10:
  br label %case.join.8
case.arm.12.11:
  %t13 = getelementptr ptr, ptr %t3, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  %t15 = getelementptr ptr, ptr %t14, i32 2
  %t16 = load ptr, ptr %t15
  call void @__inc_ref(ptr %t16)
  %t17 = call ptr @__splitOnFirst(ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t16)
  %t18 = getelementptr ptr, ptr %t17, i32 0
  %t19 = load ptr, ptr %t18
  %t20 = ptrtoint ptr %t19 to i64
  switch i64 %t20, label %case.default.21 [ i64 11, label %case.arm.11.23 i64 12, label %case.arm.12.25 ]
case.arm.11.23:
  br label %case.end.11.24
case.end.11.24:
  br label %case.join.22
case.arm.12.25:
  %t27 = getelementptr ptr, ptr %t14, i32 1
  %t28 = load ptr, ptr %t27
  call void @__inc_ref(ptr %t28)
  br label %case.end.12.26
case.end.12.26:
  br label %case.join.22
case.default.21:
  unreachable
case.join.22:
  %t29 = phi ptr [ getelementptr inbounds (i8, ptr @.str.3, i64 12), %case.end.11.24 ], [ %t28, %case.end.12.26 ]
  call void @__free_recursive(ptr %t17)
  br label %case.end.12.12
case.end.12.12:
  br label %case.join.8
case.default.7:
  unreachable
case.join.8:
  %t30 = phi ptr [ getelementptr inbounds (i8, ptr @.str.2, i64 12), %case.end.11.10 ], [ %t29, %case.end.12.12 ]
  call void @__free_recursive(ptr %t3)
  %t31 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t30, ptr %t31
  %t32 = call ptr @__alloc(i64 16, i32 1)
  %t33 = inttoptr i64 5 to ptr
  %t34 = getelementptr ptr, ptr %t32, i32 0
  store ptr %t33, ptr %t34
  %t35 = call ptr @__alloc(i64 8, i32 0)
  %t36 = inttoptr i64 0 to ptr
  %t37 = getelementptr ptr, ptr %t35, i32 0
  store ptr %t36, ptr %t37
  %t38 = getelementptr ptr, ptr %t32, i32 1
  store ptr %t35, ptr %t38
  %t39 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t32, ptr %t39
  ret ptr %t0
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
