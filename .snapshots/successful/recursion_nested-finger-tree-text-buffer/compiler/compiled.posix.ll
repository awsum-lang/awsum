; External C declarations
declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare ptr @memcpy(ptr, ptr, i64)
declare i64 @write(i32, ptr, i64)
declare i64 @strlen(ptr)
declare i32 @snprintf(ptr, i64, ptr, ...)
declare i32 @memcmp(ptr, ptr, i64)

@.fmt_u8 = private unnamed_addr constant [3 x i8] c"%u\00"
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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"/" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [24 x i8]} { i32 0, i32 0, i32 0, i32 24, i32 24, [24 x i8] c"UNPAIRED_UTF16_SURROGATE" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [11 x i8]} { i32 0, i32 0, i32 0, i32 11, i32 11, [11 x i8] c"PARSE_ERROR" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [12 x i8]} { i32 0, i32 0, i32 0, i32 12, i32 12, [12 x i8] c"NO_SUCH_LINE" }
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [14 x i8]} { i32 0, i32 0, i32 0, i32 14, i32 14, [14 x i8] c"MISSING_SCRIPT" }
@.str.6 = private unnamed_addr constant {i32, i32, i32, i32, i32, [11 x i8]} { i32 0, i32 0, i32 0, i32 11, i32 11, [11 x i8] c"BAD_COMMAND" }
@.str.7 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c";" }
@.str.8 = private unnamed_addr constant {i32, i32, i32, i32, i32, [0 x i8]} { i32 0, i32 0, i32 0, i32 0, i32 0, [0 x i8] zeroinitializer }
@.str.9 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"," }
@.str.10 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c" " }
@.str.11 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"dup" }
@.str.12 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"show" }
@.str.13 = private unnamed_addr constant {i32, i32, i32, i32, i32, [6 x i8]} { i32 0, i32 0, i32 0, i32 6, i32 6, [6 x i8] c"offset" }
@.str.14 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"line" }
@.str.15 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"ins" }
@.str.16 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"del" }

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


define internal ptr @__eqString(ptr %a, ptr %b) {
  %ba = load i32, ptr %a
  %bb = load i32, ptr %b
  %len_eq = icmp eq i32 %ba, %bb
  br i1 %len_eq, label %cmp, label %ne
cmp:
  %a_payload = getelementptr i8, ptr %a, i64 8
  %b_payload = getelementptr i8, ptr %b, i64 8
  %ba64 = zext i32 %ba to i64
  %r = call i32 @memcmp(ptr %a_payload, ptr %b_payload, i64 %ba64)
  %bytes_eq = icmp eq i32 %r, 0
  br i1 %bytes_eq, label %eq, label %ne
eq:
  %tag_t = inttoptr i64 1 to ptr
  %box_t = call ptr @__alloc(i64 8, i32 0)
  store ptr %tag_t, ptr %box_t
  br label %done
ne:
  %tag_f = inttoptr i64 2 to ptr
  %box_f = call ptr @__alloc(i64 8, i32 0)
  store ptr %tag_f, ptr %box_f
  br label %done
done:
  %result = phi ptr [ %box_t, %eq ], [ %box_f, %ne ]
  call void @__free_recursive(ptr %a)
  call void @__free_recursive(ptr %b)
  ret ptr %result
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


define internal ptr @__showUInt32(ptr %p) {
  %v = load i32, ptr %p
  %buf = call ptr @__alloc(i64 24, i32 0)
  %payload = getelementptr i8, ptr %buf, i64 8
  %n = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %payload, i64 16, ptr @.fmt_u8, i32 %v)
  store i32 %n, ptr %buf
  %u16p = getelementptr i8, ptr %buf, i64 4
  store i32 %n, ptr %u16p
  call void @__free_recursive(ptr %p)
  ret ptr %buf
}


define internal ptr @__eqUInt32(ptr %a, ptr %b) {
  %va = load i32, ptr %a
  %vb = load i32, ptr %b
  %eq = icmp eq i32 %va, %vb
  %tag = select i1 %eq, i64 1, i64 2
  %box = call ptr @__alloc(i64 8, i32 0)
  %tag_ptr = inttoptr i64 %tag to ptr
  store ptr %tag_ptr, ptr %box
  call void @__free_recursive(ptr %a)
  call void @__free_recursive(ptr %b)
  ret ptr %box
}


define internal ptr @__addUInt32(ptr %pa, ptr %pb) {
  %a = load i32, ptr %pa
  %b = load i32, ptr %pb
  %a64 = zext i32 %a to i64
  %b64 = zext i32 %b to i64
  %sum64 = add i64 %a64, %b64
  %ovf = icmp ugt i64 %sum64, 4294967295
  br i1 %ovf, label %err, label %ok
err:
  %oe = call ptr @__alloc(i64 8, i32 0)
  %oe_tag = inttoptr i64 18 to ptr
  store ptr %oe_tag, ptr %oe
  %left = call ptr @__alloc(i64 16, i32 1)
  %left_tag = inttoptr i64 3 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %oe, ptr %left_f
  br label %join
ok:
  %newv = trunc i64 %sum64 to i32
  %box = call ptr @__alloc(i64 4, i32 0)
  store i32 %newv, ptr %box
  %right = call ptr @__alloc(i64 16, i32 1)
  %right_tag = inttoptr i64 4 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %box, ptr %right_f
  br label %join
join:
  %result = phi ptr [ %left, %err ], [ %right, %ok ]
  call void @__free_recursive(ptr %pa)
  call void @__free_recursive(ptr %pb)
  ret ptr %result
}


define internal ptr @__subUInt32(ptr %pa, ptr %pb) {
  %a = load i32, ptr %pa
  %b = load i32, ptr %pb
  %unf = icmp ult i32 %a, %b
  br i1 %unf, label %err, label %ok
err:
  %ue = call ptr @__alloc(i64 8, i32 0)
  %ue_tag = inttoptr i64 17 to ptr
  store ptr %ue_tag, ptr %ue
  %left = call ptr @__alloc(i64 16, i32 1)
  %left_tag = inttoptr i64 3 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %ue, ptr %left_f
  br label %join
ok:
  %newv = sub i32 %a, %b
  %box = call ptr @__alloc(i64 4, i32 0)
  store i32 %newv, ptr %box
  %right = call ptr @__alloc(i64 16, i32 1)
  %right_tag = inttoptr i64 4 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %box, ptr %right_f
  br label %join
join:
  %result = phi ptr [ %left, %err ], [ %right, %ok ]
  call void @__free_recursive(ptr %pa)
  call void @__free_recursive(ptr %pb)
  ret ptr %result
}


define internal ptr @__parseUInt32(ptr %s) {
entry:
  %i_alloca = alloca i64, align 8
  store i64 0, ptr %i_alloca
  %acc_alloca = alloca i64, align 8
  store i64 0, ptr %acc_alloca
  %len32 = load i32, ptr %s
  %len = zext i32 %len32 to i64
  %payload = getelementptr i8, ptr %s, i64 8
  %is_empty = icmp eq i64 %len, 0
  br i1 %is_empty, label %fail, label %loop_head
loop_head:
  %i = load i64, ptr %i_alloca
  %acc = load i64, ptr %acc_alloca
  %cond = icmp ult i64 %i, %len
  br i1 %cond, label %body, label %ok
body:
  %ptr_c = getelementptr i8, ptr %payload, i64 %i
  %c = load i8, ptr %ptr_c
  %c_i32 = zext i8 %c to i32
  %low = icmp ult i32 %c_i32, 48
  %high = icmp ugt i32 %c_i32, 57
  %bad = or i1 %low, %high
  br i1 %bad, label %fail, label %parse
parse:
  %d = sub i32 %c_i32, 48
  %d_i64 = zext i32 %d to i64
  %x10 = mul i64 %acc, 10
  %acc_next = add i64 %x10, %d_i64
  %big = icmp ugt i64 %acc_next, 4294967295
  br i1 %big, label %fail, label %body_end
body_end:
  store i64 %acc_next, ptr %acc_alloca
  %i_next = add i64 %i, 1
  store i64 %i_next, ptr %i_alloca
  br label %loop_head
ok:
  %result_i32 = trunc i64 %acc to i32
  %box = call ptr @__alloc(i64 4, i32 0)
  store i32 %result_i32, ptr %box
  %right = call ptr @__alloc(i64 16, i32 1)
  %right_tag = inttoptr i64 4 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %box, ptr %right_f
  br label %join
fail:
  %pe = call ptr @__alloc(i64 8, i32 0)
  %pe_tag = inttoptr i64 22 to ptr
  store ptr %pe_tag, ptr %pe
  %left = call ptr @__alloc(i64 16, i32 1)
  %left_tag = inttoptr i64 3 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %pe, ptr %left_f
  br label %join
join:
  %res = phi ptr [ %right, %ok ], [ %left, %fail ]
  call void @__free_recursive(ptr %s)
  ret ptr %res
}


define internal ptr @__lengthUtf16CodeUnits(ptr %s) {
  %u16p = getelementptr i8, ptr %s, i64 4
  %u16 = load i32, ptr %u16p
  %box = call ptr @__alloc(i64 4, i32 0)
  store i32 %u16, ptr %box
  call void @__free_recursive(ptr %s)
  ret ptr %box
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
  %t21 = inttoptr i64 280 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = call ptr @__alloc(i64 24, i32 2)
  %t24 = inttoptr i64 53 to ptr
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
  %t32 = inttoptr i64 126 to ptr
  %t33 = getelementptr ptr, ptr %t31, i32 0
  store ptr %t32, ptr %t33
  %t34 = getelementptr ptr, ptr %t20, i32 2
  store ptr %t31, ptr %t34
  %t35 = call ptr @v_$scc$$apply$$scc$$apply1__$apply2__$df$$lam$21$32__$x$2741112381(ptr %t20)
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

define internal ptr @v_maxUInt32() {
  %t0 = call ptr @__alloc(i64 4, i32 0)
  store i32 -1, ptr %t0
  ret ptr %t0
}

define internal ptr @v_$cps$appendList(ptr %v_xs, ptr %v_ys, ptr %v_$k) {
entry:
  %t3 = alloca ptr
  store ptr %v_xs, ptr %t3
  %t4 = alloca ptr
  store ptr %v_ys, ptr %t4
  %t5 = alloca ptr
  store ptr %v_$k, ptr %t5
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t6 = load ptr, ptr %t3
  %t7 = load ptr, ptr %t4
  %t8 = load ptr, ptr %t5
  %t9 = getelementptr ptr, ptr %t6, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %tco.case.default.12 [ i64 13, label %tco.case.arm.13.13 i64 14, label %tco.case.arm.14.15 ]
tco.case.arm.13.13:
  call void @__inc_ref(ptr %t8)
  call void @__inc_ref(ptr %t7)
  %t14 = call ptr @v_$apply$appendList(ptr %t8, ptr %t7)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t7)
  call void @__free_recursive(ptr %t8)
  store ptr %t14, ptr %t2
  br label %tco.exit.1
tco.case.arm.14.15:
  %t16 = getelementptr ptr, ptr %t6, i32 1
  %t17 = load ptr, ptr %t16
  %t18 = getelementptr ptr, ptr %t6, i32 2
  %t19 = load ptr, ptr %t18
  call void @__inc_ref(ptr %t19)
  %t26 = getelementptr i8, ptr %t6, i64 -8
  %t27 = load i32, ptr %t26
  %t28 = icmp eq i32 %t27, 1
  br i1 %t28, label %reuse.in_place.29, label %reuse.copy.30
reuse.in_place.29:
  %t20 = getelementptr ptr, ptr %t6, i32 2
  %t21 = load ptr, ptr %t20
  call void @__free_recursive(ptr %t21)
  %t24 = inttoptr i64 119 to ptr
  %t25 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t24, ptr %t25
  call void @__inc_ref(ptr %t8)
  %t22 = getelementptr ptr, ptr %t6, i32 1
  store ptr %t8, ptr %t22
  %t23 = getelementptr ptr, ptr %t6, i32 2
  store ptr %t17, ptr %t23
  br label %reuse.in_place.end.32
reuse.in_place.end.32:
  br label %reuse.join.31
reuse.copy.30:
  %t34 = call ptr @__alloc(i64 24, i32 2)
  %t35 = inttoptr i64 119 to ptr
  %t36 = getelementptr ptr, ptr %t34, i32 0
  store ptr %t35, ptr %t36
  call void @__inc_ref(ptr %t8)
  %t37 = getelementptr ptr, ptr %t34, i32 1
  store ptr %t8, ptr %t37
  call void @__inc_ref(ptr %t17)
  %t38 = getelementptr ptr, ptr %t34, i32 2
  store ptr %t17, ptr %t38
  call void @__free_recursive(ptr %t6)
  br label %reuse.copy.end.33
reuse.copy.end.33:
  br label %reuse.join.31
reuse.join.31:
  %t39 = phi ptr [ %t6, %reuse.in_place.end.32 ], [ %t34, %reuse.copy.end.33 ]
  call void @__free_recursive(ptr %t8)
  store ptr %t19, ptr %t3
  store ptr %t7, ptr %t4
  store ptr %t39, ptr %t5
  br label %tco.loop.0
tco.case.default.12:
  unreachable
tco.exit.1:
  %t40 = load ptr, ptr %t2
  ret ptr %t40
}

define internal ptr @v_$apply$appendList(ptr %v_$k, ptr %v_$x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 118, label %tco.case.arm.118.11 i64 119, label %tco.case.arm.119.12 ]
tco.case.arm.118.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.119.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  %t15 = getelementptr ptr, ptr %t5, i32 2
  %t16 = load ptr, ptr %t15
  %t17 = getelementptr ptr, ptr %t5, i32 1
  %t18 = load ptr, ptr %t17
  call void @__free_recursive(ptr %t18)
  %t21 = inttoptr i64 14 to ptr
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

define internal ptr @v_addStats(ptr %v_$arg__4, ptr %v_$arg__5) {
  %t0 = getelementptr ptr, ptr %v_$arg__4, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 35, label %case.arm.35.4 ]
case.arm.35.4:
  %t5 = getelementptr ptr, ptr %v_$arg__4, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = getelementptr ptr, ptr %v_$arg__4, i32 2
  %t8 = load ptr, ptr %t7
  call void @__inc_ref(ptr %t8)
  %t9 = getelementptr ptr, ptr %v_$arg__5, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %case.default.12 [ i64 35, label %case.arm.35.13 ]
case.arm.35.13:
  %t14 = getelementptr ptr, ptr %v_$arg__5, i32 1
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  %t16 = getelementptr ptr, ptr %v_$arg__5, i32 2
  %t17 = load ptr, ptr %t16
  call void @__inc_ref(ptr %t17)
  %t18 = call ptr @__alloc(i64 24, i32 2)
  %t19 = inttoptr i64 35 to ptr
  %t20 = getelementptr ptr, ptr %t18, i32 0
  store ptr %t19, ptr %t20
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t15)
  %t21 = call ptr @__addUInt32(ptr %t6, ptr %t15)
  %t22 = getelementptr ptr, ptr %t21, i32 0
  %t23 = load ptr, ptr %t22
  %t24 = ptrtoint ptr %t23 to i64
  switch i64 %t24, label %case.default.25 [ i64 3, label %case.arm.3.27 i64 4, label %case.arm.4.30 ]
case.arm.3.27:
  %t29 = call ptr @v_maxUInt32()
  br label %case.end.3.28
case.end.3.28:
  br label %case.join.26
case.arm.4.30:
  %t32 = getelementptr ptr, ptr %t21, i32 1
  %t33 = load ptr, ptr %t32
  call void @__inc_ref(ptr %t33)
  call void @__inc_ref(ptr %t33)
  call void @__free_recursive(ptr %t33)
  br label %case.end.4.31
case.end.4.31:
  br label %case.join.26
case.default.25:
  unreachable
case.join.26:
  %t34 = phi ptr [ %t29, %case.end.3.28 ], [ %t33, %case.end.4.31 ]
  call void @__free_recursive(ptr %t21)
  %t35 = getelementptr ptr, ptr %t18, i32 1
  store ptr %t34, ptr %t35
  call void @__inc_ref(ptr %t8)
  call void @__inc_ref(ptr %t17)
  %t36 = call ptr @__addUInt32(ptr %t8, ptr %t17)
  %t37 = getelementptr ptr, ptr %t36, i32 0
  %t38 = load ptr, ptr %t37
  %t39 = ptrtoint ptr %t38 to i64
  switch i64 %t39, label %case.default.40 [ i64 3, label %case.arm.3.42 i64 4, label %case.arm.4.45 ]
case.arm.3.42:
  %t44 = call ptr @v_maxUInt32()
  br label %case.end.3.43
case.end.3.43:
  br label %case.join.41
case.arm.4.45:
  %t47 = getelementptr ptr, ptr %t36, i32 1
  %t48 = load ptr, ptr %t47
  call void @__inc_ref(ptr %t48)
  call void @__inc_ref(ptr %t48)
  call void @__free_recursive(ptr %t48)
  br label %case.end.4.46
case.end.4.46:
  br label %case.join.41
case.default.40:
  unreachable
case.join.41:
  %t49 = phi ptr [ %t44, %case.end.3.43 ], [ %t48, %case.end.4.46 ]
  call void @__free_recursive(ptr %t36)
  %t50 = getelementptr ptr, ptr %t18, i32 2
  store ptr %t49, ptr %t50
  call void @__free_recursive(ptr %t17)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_$arg__4)
  call void @__free_recursive(ptr %v_$arg__5)
  ret ptr %t18
case.default.12:
  unreachable
case.default.3:
  unreachable
}

define internal ptr @v_noStats() {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 35 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t3
  %t4 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t4
  %t5 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t5, ptr %t6
  ret ptr %t0
}

define internal ptr @v_lineMeasure() {
  %t0 = call ptr @__alloc(i64 32, i32 3)
  %t1 = inttoptr i64 33 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 8, i32 0)
  %t4 = inttoptr i64 48 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  %t7 = call ptr @__alloc(i64 8, i32 0)
  %t8 = inttoptr i64 51 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t7, ptr %t10
  %t11 = call ptr @v_noStats()
  %t12 = getelementptr ptr, ptr %t0, i32 3
  store ptr %t11, ptr %t12
  ret ptr %t0
}

define internal ptr @v_joinOnto(ptr %v_acc, ptr %v_ls) {
entry:
  %t3 = alloca ptr
  store ptr %v_acc, ptr %t3
  %t4 = alloca ptr
  store ptr %v_ls, ptr %t4
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t5 = load ptr, ptr %t3
  %t6 = load ptr, ptr %t4
  %t7 = getelementptr ptr, ptr %t6, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %tco.case.default.10 [ i64 13, label %tco.case.arm.13.11 i64 14, label %tco.case.arm.14.16 ]
tco.case.arm.13.11:
  %t12 = call ptr @__alloc(i64 16, i32 1)
  %t13 = inttoptr i64 4 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  call void @__inc_ref(ptr %t5)
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t5, ptr %t15
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t12, ptr %t2
  br label %tco.exit.1
tco.case.arm.14.16:
  call void @__inc_ref(ptr %t5)
  %t17 = call ptr @__concat(ptr %t5, ptr getelementptr inbounds (i8, ptr @.str.0, i64 12))
  %t18 = getelementptr ptr, ptr %t17, i32 0
  %t19 = load ptr, ptr %t18
  %t20 = ptrtoint ptr %t19 to i64
  switch i64 %t20, label %tco.case.default.21 [ i64 3, label %tco.case.arm.3.22 i64 4, label %tco.case.arm.4.29 ]
tco.case.arm.3.22:
  %t23 = getelementptr ptr, ptr %t17, i32 1
  %t24 = load ptr, ptr %t23
  call void @__inc_ref(ptr %t24)
  call void @__free_recursive(ptr %t17)
  %t25 = call ptr @__alloc(i64 16, i32 1)
  %t26 = inttoptr i64 3 to ptr
  %t27 = getelementptr ptr, ptr %t25, i32 0
  store ptr %t26, ptr %t27
  call void @__inc_ref(ptr %t24)
  %t28 = getelementptr ptr, ptr %t25, i32 1
  store ptr %t24, ptr %t28
  call void @__free_recursive(ptr %t24)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t25, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.29:
  %t30 = getelementptr ptr, ptr %t17, i32 1
  %t31 = load ptr, ptr %t30
  call void @__inc_ref(ptr %t31)
  call void @__free_recursive(ptr %t17)
  call void @__inc_ref(ptr %t31)
  %t32 = getelementptr ptr, ptr %t6, i32 1
  %t33 = load ptr, ptr %t32
  call void @__inc_ref(ptr %t33)
  %t34 = call ptr @__concat(ptr %t31, ptr %t33)
  %t35 = getelementptr ptr, ptr %t34, i32 0
  %t36 = load ptr, ptr %t35
  %t37 = ptrtoint ptr %t36 to i64
  switch i64 %t37, label %tco.case.default.38 [ i64 3, label %tco.case.arm.3.39 i64 4, label %tco.case.arm.4.46 ]
tco.case.arm.3.39:
  %t40 = getelementptr ptr, ptr %t34, i32 1
  %t41 = load ptr, ptr %t40
  call void @__inc_ref(ptr %t41)
  call void @__free_recursive(ptr %t34)
  %t42 = call ptr @__alloc(i64 16, i32 1)
  %t43 = inttoptr i64 3 to ptr
  %t44 = getelementptr ptr, ptr %t42, i32 0
  store ptr %t43, ptr %t44
  call void @__inc_ref(ptr %t41)
  %t45 = getelementptr ptr, ptr %t42, i32 1
  store ptr %t41, ptr %t45
  call void @__free_recursive(ptr %t41)
  call void @__free_recursive(ptr %t31)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t42, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.46:
  %t47 = getelementptr ptr, ptr %t34, i32 1
  %t48 = load ptr, ptr %t47
  call void @__inc_ref(ptr %t48)
  call void @__free_recursive(ptr %t34)
  %t49 = getelementptr ptr, ptr %t6, i32 2
  %t50 = load ptr, ptr %t49
  call void @__inc_ref(ptr %t50)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t31)
  store ptr %t48, ptr %t3
  store ptr %t50, ptr %t4
  br label %tco.loop.0
tco.case.default.38:
  unreachable
tco.case.default.21:
  unreachable
tco.case.default.10:
  unreachable
tco.exit.1:
  %t51 = load ptr, ptr %t2
  ret ptr %t51
}

define internal ptr @v_$cps$splitAll(ptr %v_sep, ptr %v_src, ptr %v_$k) {
entry:
  %t3 = alloca ptr
  store ptr %v_sep, ptr %t3
  %t4 = alloca ptr
  store ptr %v_src, ptr %t4
  %t5 = alloca ptr
  store ptr %v_$k, ptr %t5
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t6 = load ptr, ptr %t3
  %t7 = load ptr, ptr %t4
  %t8 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t7)
  %t9 = call ptr @__splitOnFirst(ptr %t6, ptr %t7)
  %t10 = getelementptr ptr, ptr %t9, i32 0
  %t11 = load ptr, ptr %t10
  %t12 = ptrtoint ptr %t11 to i64
  switch i64 %t12, label %tco.case.default.13 [ i64 11, label %tco.case.arm.11.14 i64 12, label %tco.case.arm.12.24 ]
tco.case.arm.11.14:
  call void @__free_recursive(ptr %t9)
  call void @__inc_ref(ptr %t8)
  %t15 = call ptr @__alloc(i64 24, i32 2)
  %t16 = inttoptr i64 14 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  call void @__inc_ref(ptr %t7)
  %t18 = getelementptr ptr, ptr %t15, i32 1
  store ptr %t7, ptr %t18
  %t19 = call ptr @__alloc(i64 8, i32 0)
  %t20 = inttoptr i64 13 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr ptr, ptr %t15, i32 2
  store ptr %t19, ptr %t22
  %t23 = call ptr @v_$apply$splitAll(ptr %t8, ptr %t15)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t7)
  call void @__free_recursive(ptr %t8)
  store ptr %t23, ptr %t2
  br label %tco.exit.1
tco.case.arm.12.24:
  %t25 = getelementptr ptr, ptr %t9, i32 1
  %t26 = load ptr, ptr %t25
  call void @__inc_ref(ptr %t26)
  call void @__free_recursive(ptr %t9)
  %t27 = getelementptr ptr, ptr %t26, i32 0
  %t28 = load ptr, ptr %t27
  %t29 = ptrtoint ptr %t28 to i64
  switch i64 %t29, label %tco.case.default.30 [ i64 15, label %tco.case.arm.15.31 ]
tco.case.arm.15.31:
  %t32 = getelementptr ptr, ptr %t26, i32 1
  %t33 = load ptr, ptr %t32
  %t34 = getelementptr ptr, ptr %t26, i32 2
  %t35 = load ptr, ptr %t34
  call void @__inc_ref(ptr %t35)
  %t42 = getelementptr i8, ptr %t26, i64 -8
  %t43 = load i32, ptr %t42
  %t44 = icmp eq i32 %t43, 1
  br i1 %t44, label %reuse.in_place.45, label %reuse.copy.46
reuse.in_place.45:
  %t36 = getelementptr ptr, ptr %t26, i32 2
  %t37 = load ptr, ptr %t36
  call void @__free_recursive(ptr %t37)
  %t40 = inttoptr i64 121 to ptr
  %t41 = getelementptr ptr, ptr %t26, i32 0
  store ptr %t40, ptr %t41
  call void @__inc_ref(ptr %t8)
  %t38 = getelementptr ptr, ptr %t26, i32 1
  store ptr %t8, ptr %t38
  %t39 = getelementptr ptr, ptr %t26, i32 2
  store ptr %t33, ptr %t39
  br label %reuse.in_place.end.48
reuse.in_place.end.48:
  br label %reuse.join.47
reuse.copy.46:
  %t50 = call ptr @__alloc(i64 24, i32 2)
  %t51 = inttoptr i64 121 to ptr
  %t52 = getelementptr ptr, ptr %t50, i32 0
  store ptr %t51, ptr %t52
  call void @__inc_ref(ptr %t8)
  %t53 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t8, ptr %t53
  call void @__inc_ref(ptr %t33)
  %t54 = getelementptr ptr, ptr %t50, i32 2
  store ptr %t33, ptr %t54
  call void @__free_recursive(ptr %t26)
  br label %reuse.copy.end.49
reuse.copy.end.49:
  br label %reuse.join.47
reuse.join.47:
  %t55 = phi ptr [ %t26, %reuse.in_place.end.48 ], [ %t50, %reuse.copy.end.49 ]
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t7)
  store ptr %t6, ptr %t3
  store ptr %t35, ptr %t4
  store ptr %t55, ptr %t5
  br label %tco.loop.0
tco.case.default.30:
  unreachable
tco.case.default.13:
  unreachable
tco.exit.1:
  %t56 = load ptr, ptr %t2
  ret ptr %t56
}

define internal ptr @v_$apply$splitAll(ptr %v_$k, ptr %v_$x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 120, label %tco.case.arm.120.11 i64 121, label %tco.case.arm.121.12 ]
tco.case.arm.120.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.121.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  %t15 = getelementptr ptr, ptr %t5, i32 2
  %t16 = load ptr, ptr %t15
  %t17 = getelementptr ptr, ptr %t5, i32 1
  %t18 = load ptr, ptr %t17
  call void @__free_recursive(ptr %t18)
  %t21 = inttoptr i64 14 to ptr
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

define internal ptr @v_main() {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 280 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 16, i32 1)
  %t4 = inttoptr i64 70 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = call ptr @__alloc(i64 16, i32 1)
  %t7 = inttoptr i64 8 to ptr
  %t8 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t7, ptr %t8
  %t9 = call ptr @__alloc(i64 8, i32 0)
  %t10 = inttoptr i64 45 to ptr
  %t11 = getelementptr ptr, ptr %t9, i32 0
  store ptr %t10, ptr %t11
  %t12 = getelementptr ptr, ptr %t6, i32 1
  store ptr %t9, ptr %t12
  %t13 = getelementptr ptr, ptr %t3, i32 1
  store ptr %t6, ptr %t13
  %t14 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t14
  %t15 = call ptr @__alloc(i64 8, i32 0)
  %t16 = inttoptr i64 126 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t15, ptr %t18
  %t19 = call ptr @v_$scc$$apply$$scc$$apply1__$apply2__$df$$lam$21$32__$x$2741112381(ptr %t0)
  %t20 = call ptr @__alloc(i64 8, i32 0)
  %t21 = inttoptr i64 124 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = call ptr @v_$cps$$df$$rowmono$0$andThenIO$31(ptr %t19, ptr %t20)
  %t24 = call ptr @__alloc(i64 8, i32 0)
  %t25 = inttoptr i64 122 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v_$cps$$df$handleErrorIO$27(ptr %t23, ptr %t24)
  ret ptr %t27
}

define internal ptr @v_$df$foldDigit$12(ptr %v_digit, ptr %v_acc) {
  %t0 = getelementptr ptr, ptr %v_digit, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 24, label %case.arm.24.4 i64 25, label %case.arm.25.12 i64 26, label %case.arm.26.27 i64 27, label %case.arm.27.49 ]
case.arm.24.4:
  %t5 = call ptr @__alloc(i64 24, i32 2)
  %t6 = inttoptr i64 14 to ptr
  %t7 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t6, ptr %t7
  %t8 = getelementptr ptr, ptr %v_digit, i32 1
  %t9 = load ptr, ptr %t8
  call void @__inc_ref(ptr %t9)
  %t10 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t9, ptr %t10
  call void @__inc_ref(ptr %v_acc)
  %t11 = getelementptr ptr, ptr %t5, i32 2
  store ptr %v_acc, ptr %t11
  call void @__free_recursive(ptr %v_digit)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t5
case.arm.25.12:
  %t13 = call ptr @__alloc(i64 24, i32 2)
  %t14 = inttoptr i64 14 to ptr
  %t15 = getelementptr ptr, ptr %t13, i32 0
  store ptr %t14, ptr %t15
  %t16 = getelementptr ptr, ptr %v_digit, i32 1
  %t17 = load ptr, ptr %t16
  call void @__inc_ref(ptr %t17)
  %t18 = getelementptr ptr, ptr %t13, i32 1
  store ptr %t17, ptr %t18
  %t19 = call ptr @__alloc(i64 24, i32 2)
  %t20 = inttoptr i64 14 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr ptr, ptr %v_digit, i32 2
  %t23 = load ptr, ptr %t22
  call void @__inc_ref(ptr %t23)
  %t24 = getelementptr ptr, ptr %t19, i32 1
  store ptr %t23, ptr %t24
  call void @__inc_ref(ptr %v_acc)
  %t25 = getelementptr ptr, ptr %t19, i32 2
  store ptr %v_acc, ptr %t25
  %t26 = getelementptr ptr, ptr %t13, i32 2
  store ptr %t19, ptr %t26
  call void @__free_recursive(ptr %v_digit)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t13
case.arm.26.27:
  %t28 = call ptr @__alloc(i64 24, i32 2)
  %t29 = inttoptr i64 14 to ptr
  %t30 = getelementptr ptr, ptr %t28, i32 0
  store ptr %t29, ptr %t30
  %t31 = getelementptr ptr, ptr %v_digit, i32 1
  %t32 = load ptr, ptr %t31
  call void @__inc_ref(ptr %t32)
  %t33 = getelementptr ptr, ptr %t28, i32 1
  store ptr %t32, ptr %t33
  %t34 = call ptr @__alloc(i64 24, i32 2)
  %t35 = inttoptr i64 14 to ptr
  %t36 = getelementptr ptr, ptr %t34, i32 0
  store ptr %t35, ptr %t36
  %t37 = getelementptr ptr, ptr %v_digit, i32 2
  %t38 = load ptr, ptr %t37
  call void @__inc_ref(ptr %t38)
  %t39 = getelementptr ptr, ptr %t34, i32 1
  store ptr %t38, ptr %t39
  %t40 = call ptr @__alloc(i64 24, i32 2)
  %t41 = inttoptr i64 14 to ptr
  %t42 = getelementptr ptr, ptr %t40, i32 0
  store ptr %t41, ptr %t42
  %t43 = getelementptr ptr, ptr %v_digit, i32 3
  %t44 = load ptr, ptr %t43
  call void @__inc_ref(ptr %t44)
  %t45 = getelementptr ptr, ptr %t40, i32 1
  store ptr %t44, ptr %t45
  call void @__inc_ref(ptr %v_acc)
  %t46 = getelementptr ptr, ptr %t40, i32 2
  store ptr %v_acc, ptr %t46
  %t47 = getelementptr ptr, ptr %t34, i32 2
  store ptr %t40, ptr %t47
  %t48 = getelementptr ptr, ptr %t28, i32 2
  store ptr %t34, ptr %t48
  call void @__free_recursive(ptr %v_digit)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t28
case.arm.27.49:
  %t50 = call ptr @__alloc(i64 24, i32 2)
  %t51 = inttoptr i64 14 to ptr
  %t52 = getelementptr ptr, ptr %t50, i32 0
  store ptr %t51, ptr %t52
  %t53 = getelementptr ptr, ptr %v_digit, i32 1
  %t54 = load ptr, ptr %t53
  call void @__inc_ref(ptr %t54)
  %t55 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t54, ptr %t55
  %t56 = call ptr @__alloc(i64 24, i32 2)
  %t57 = inttoptr i64 14 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  %t59 = getelementptr ptr, ptr %v_digit, i32 2
  %t60 = load ptr, ptr %t59
  call void @__inc_ref(ptr %t60)
  %t61 = getelementptr ptr, ptr %t56, i32 1
  store ptr %t60, ptr %t61
  %t62 = call ptr @__alloc(i64 24, i32 2)
  %t63 = inttoptr i64 14 to ptr
  %t64 = getelementptr ptr, ptr %t62, i32 0
  store ptr %t63, ptr %t64
  %t65 = getelementptr ptr, ptr %v_digit, i32 3
  %t66 = load ptr, ptr %t65
  call void @__inc_ref(ptr %t66)
  %t67 = getelementptr ptr, ptr %t62, i32 1
  store ptr %t66, ptr %t67
  %t68 = call ptr @__alloc(i64 24, i32 2)
  %t69 = inttoptr i64 14 to ptr
  %t70 = getelementptr ptr, ptr %t68, i32 0
  store ptr %t69, ptr %t70
  %t71 = getelementptr ptr, ptr %v_digit, i32 4
  %t72 = load ptr, ptr %t71
  call void @__inc_ref(ptr %t72)
  %t73 = getelementptr ptr, ptr %t68, i32 1
  store ptr %t72, ptr %t73
  call void @__inc_ref(ptr %v_acc)
  %t74 = getelementptr ptr, ptr %t68, i32 2
  store ptr %v_acc, ptr %t74
  %t75 = getelementptr ptr, ptr %t62, i32 2
  store ptr %t68, ptr %t75
  %t76 = getelementptr ptr, ptr %t56, i32 2
  store ptr %t62, ptr %t76
  %t77 = getelementptr ptr, ptr %t50, i32 2
  store ptr %t56, ptr %t77
  call void @__free_recursive(ptr %v_digit)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t50
case.default.3:
  unreachable
}

define internal ptr @v_$cps$$df$handleErrorIO$27(ptr %v_io, ptr %v_$k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.13 i64 7, label %tco.case.arm.7.107 i64 8, label %tco.case.arm.8.132 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t12 = call ptr @v_$apply$$df$handleErrorIO$27(ptr %t6, ptr %t5)
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
  switch i64 %t18, label %case.default.19 [ i64 502975519, label %case.arm.502975519.21 i64 589989748, label %case.arm.589989748.35 i64 2448244154, label %case.arm.2448244154.49 i64 3150992243, label %case.arm.3150992243.63 i64 3471307616, label %case.arm.3471307616.77 i64 3932148625, label %case.arm.3932148625.91 ]
case.arm.502975519.21:
  %t23 = call ptr @__alloc(i64 24, i32 2)
  %t24 = inttoptr i64 7 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  %t26 = getelementptr ptr, ptr %t23, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t26
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
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t40
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
case.arm.2448244154.49:
  %t51 = call ptr @__alloc(i64 24, i32 2)
  %t52 = inttoptr i64 7 to ptr
  %t53 = getelementptr ptr, ptr %t51, i32 0
  store ptr %t52, ptr %t53
  %t54 = getelementptr ptr, ptr %t51, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t54
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
  br label %case.end.2448244154.50
case.end.2448244154.50:
  br label %case.join.20
case.arm.3150992243.63:
  %t65 = call ptr @__alloc(i64 24, i32 2)
  %t66 = inttoptr i64 7 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  %t68 = getelementptr ptr, ptr %t65, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t68
  %t69 = call ptr @__alloc(i64 16, i32 1)
  %t70 = inttoptr i64 5 to ptr
  %t71 = getelementptr ptr, ptr %t69, i32 0
  store ptr %t70, ptr %t71
  %t72 = call ptr @__alloc(i64 8, i32 0)
  %t73 = inttoptr i64 0 to ptr
  %t74 = getelementptr ptr, ptr %t72, i32 0
  store ptr %t73, ptr %t74
  %t75 = getelementptr ptr, ptr %t69, i32 1
  store ptr %t72, ptr %t75
  %t76 = getelementptr ptr, ptr %t65, i32 2
  store ptr %t69, ptr %t76
  br label %case.end.3150992243.64
case.end.3150992243.64:
  br label %case.join.20
case.arm.3471307616.77:
  %t79 = call ptr @__alloc(i64 24, i32 2)
  %t80 = inttoptr i64 7 to ptr
  %t81 = getelementptr ptr, ptr %t79, i32 0
  store ptr %t80, ptr %t81
  %t82 = getelementptr ptr, ptr %t79, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.5, i64 12), ptr %t82
  %t83 = call ptr @__alloc(i64 16, i32 1)
  %t84 = inttoptr i64 5 to ptr
  %t85 = getelementptr ptr, ptr %t83, i32 0
  store ptr %t84, ptr %t85
  %t86 = call ptr @__alloc(i64 8, i32 0)
  %t87 = inttoptr i64 0 to ptr
  %t88 = getelementptr ptr, ptr %t86, i32 0
  store ptr %t87, ptr %t88
  %t89 = getelementptr ptr, ptr %t83, i32 1
  store ptr %t86, ptr %t89
  %t90 = getelementptr ptr, ptr %t79, i32 2
  store ptr %t83, ptr %t90
  br label %case.end.3471307616.78
case.end.3471307616.78:
  br label %case.join.20
case.arm.3932148625.91:
  %t93 = call ptr @__alloc(i64 24, i32 2)
  %t94 = inttoptr i64 7 to ptr
  %t95 = getelementptr ptr, ptr %t93, i32 0
  store ptr %t94, ptr %t95
  %t96 = getelementptr ptr, ptr %t93, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.6, i64 12), ptr %t96
  %t97 = call ptr @__alloc(i64 16, i32 1)
  %t98 = inttoptr i64 5 to ptr
  %t99 = getelementptr ptr, ptr %t97, i32 0
  store ptr %t98, ptr %t99
  %t100 = call ptr @__alloc(i64 8, i32 0)
  %t101 = inttoptr i64 0 to ptr
  %t102 = getelementptr ptr, ptr %t100, i32 0
  store ptr %t101, ptr %t102
  %t103 = getelementptr ptr, ptr %t97, i32 1
  store ptr %t100, ptr %t103
  %t104 = getelementptr ptr, ptr %t93, i32 2
  store ptr %t97, ptr %t104
  br label %case.end.3932148625.92
case.end.3932148625.92:
  br label %case.join.20
case.default.19:
  unreachable
case.join.20:
  %t105 = phi ptr [ %t23, %case.end.502975519.22 ], [ %t37, %case.end.589989748.36 ], [ %t51, %case.end.2448244154.50 ], [ %t65, %case.end.3150992243.64 ], [ %t79, %case.end.3471307616.78 ], [ %t93, %case.end.3932148625.92 ]
  call void @__free_recursive(ptr %t15)
  %t106 = call ptr @v_$apply$$df$handleErrorIO$27(ptr %t6, ptr %t105)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t106, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.107:
  %t108 = getelementptr ptr, ptr %t5, i32 1
  %t109 = load ptr, ptr %t108
  %t110 = getelementptr ptr, ptr %t5, i32 2
  %t111 = load ptr, ptr %t110
  call void @__inc_ref(ptr %t111)
  %t118 = getelementptr i8, ptr %t5, i64 -8
  %t119 = load i32, ptr %t118
  %t120 = icmp eq i32 %t119, 1
  br i1 %t120, label %reuse.in_place.121, label %reuse.copy.122
reuse.in_place.121:
  %t112 = getelementptr ptr, ptr %t5, i32 2
  %t113 = load ptr, ptr %t112
  call void @__free_recursive(ptr %t113)
  %t116 = inttoptr i64 123 to ptr
  %t117 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t116, ptr %t117
  call void @__inc_ref(ptr %t6)
  %t114 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t114
  %t115 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t109, ptr %t115
  br label %reuse.in_place.end.124
reuse.in_place.end.124:
  br label %reuse.join.123
reuse.copy.122:
  %t126 = call ptr @__alloc(i64 24, i32 2)
  %t127 = inttoptr i64 123 to ptr
  %t128 = getelementptr ptr, ptr %t126, i32 0
  store ptr %t127, ptr %t128
  call void @__inc_ref(ptr %t6)
  %t129 = getelementptr ptr, ptr %t126, i32 1
  store ptr %t6, ptr %t129
  call void @__inc_ref(ptr %t109)
  %t130 = getelementptr ptr, ptr %t126, i32 2
  store ptr %t109, ptr %t130
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.125
reuse.copy.end.125:
  br label %reuse.join.123
reuse.join.123:
  %t131 = phi ptr [ %t5, %reuse.in_place.end.124 ], [ %t126, %reuse.copy.end.125 ]
  call void @__free_recursive(ptr %t6)
  store ptr %t111, ptr %t3
  store ptr %t131, ptr %t4
  br label %tco.loop.0
tco.case.arm.8.132:
  %t133 = getelementptr ptr, ptr %t5, i32 1
  %t134 = load ptr, ptr %t133
  call void @__inc_ref(ptr %t134)
  call void @__inc_ref(ptr %t6)
  %t135 = call ptr @__alloc(i64 16, i32 1)
  %t136 = inttoptr i64 8 to ptr
  %t137 = getelementptr ptr, ptr %t135, i32 0
  store ptr %t136, ptr %t137
  %t138 = call ptr @__alloc(i64 16, i32 1)
  %t139 = inttoptr i64 44 to ptr
  %t140 = getelementptr ptr, ptr %t138, i32 0
  store ptr %t139, ptr %t140
  call void @__inc_ref(ptr %t134)
  %t141 = getelementptr ptr, ptr %t138, i32 1
  store ptr %t134, ptr %t141
  %t142 = getelementptr ptr, ptr %t135, i32 1
  store ptr %t138, ptr %t142
  %t143 = call ptr @v_$apply$$df$handleErrorIO$27(ptr %t6, ptr %t135)
  call void @__free_recursive(ptr %t134)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t143, ptr %t2
  br label %tco.exit.1
tco.case.default.10:
  unreachable
tco.exit.1:
  %t144 = load ptr, ptr %t2
  ret ptr %t144
}

define internal ptr @v_$apply$$df$handleErrorIO$27(ptr %v_$k, ptr %v_$x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 122, label %tco.case.arm.122.11 i64 123, label %tco.case.arm.123.12 ]
tco.case.arm.122.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.123.12:
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

define internal ptr @v_$cps$$df$$rowmono$0$andThenIO$31(ptr %v_io, ptr %v_$k) {
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
  %t26 = call ptr @v_$apply$$df$$rowmono$0$andThenIO$31(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t26, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.27:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t28 = call ptr @v_$apply$$df$$rowmono$0$andThenIO$31(ptr %t6, ptr %t5)
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
  %t38 = inttoptr i64 125 to ptr
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
  %t49 = inttoptr i64 125 to ptr
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
  %t61 = inttoptr i64 42 to ptr
  %t62 = getelementptr ptr, ptr %t60, i32 0
  store ptr %t61, ptr %t62
  call void @__inc_ref(ptr %t56)
  %t63 = getelementptr ptr, ptr %t60, i32 1
  store ptr %t56, ptr %t63
  %t64 = getelementptr ptr, ptr %t57, i32 1
  store ptr %t60, ptr %t64
  %t65 = call ptr @v_$apply$$df$$rowmono$0$andThenIO$31(ptr %t6, ptr %t57)
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

define internal ptr @v_$apply$$df$$rowmono$0$andThenIO$31(ptr %v_$k, ptr %v_$x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 124, label %tco.case.arm.124.11 i64 125, label %tco.case.arm.125.12 ]
tco.case.arm.124.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.125.12:
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

define internal ptr @v_$scc$$apply$$scc$$apply1__$apply2__$df$$lam$21$32__$x$2741112381(ptr %v_$args$1) {
entry:
  %t3 = alloca ptr
  store ptr %v_$args$1, ptr %t3
  %v_$inl177$scrut.jslot = alloca ptr
  %v_$inl179$scrut.jslot = alloca ptr
  %v_$inl181$scrut.jslot = alloca ptr
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t4 = load ptr, ptr %t3
  %t5 = getelementptr ptr, ptr %t4, i32 0
  %t6 = load ptr, ptr %t5
  %t7 = ptrtoint ptr %t6 to i64
  switch i64 %t7, label %tco.case.default.8 [ i64 279, label %tco.case.arm.279.9 i64 280, label %tco.case.arm.280.5250 ]
tco.case.arm.279.9:
  %t10 = getelementptr ptr, ptr %t4, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  %t12 = getelementptr ptr, ptr %t4, i32 2
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t11, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %tco.case.default.17 [ i64 126, label %tco.case.arm.126.18 i64 127, label %tco.case.arm.127.19 i64 128, label %tco.case.arm.128.37 i64 129, label %tco.case.arm.129.55 i64 130, label %tco.case.arm.130.73 i64 131, label %tco.case.arm.131.91 i64 132, label %tco.case.arm.132.106 i64 133, label %tco.case.arm.133.121 i64 135, label %tco.case.arm.135.136 i64 134, label %tco.case.arm.134.212 i64 137, label %tco.case.arm.137.249 i64 136, label %tco.case.arm.136.325 i64 139, label %tco.case.arm.139.362 i64 138, label %tco.case.arm.138.442 i64 141, label %tco.case.arm.141.482 i64 140, label %tco.case.arm.140.562 i64 143, label %tco.case.arm.143.602 i64 142, label %tco.case.arm.142.635 i64 145, label %tco.case.arm.145.676 i64 144, label %tco.case.arm.144.709 i64 148, label %tco.case.arm.148.750 i64 147, label %tco.case.arm.147.775 i64 146, label %tco.case.arm.146.809 i64 151, label %tco.case.arm.151.852 i64 150, label %tco.case.arm.150.877 i64 149, label %tco.case.arm.149.911 i64 154, label %tco.case.arm.154.954 i64 153, label %tco.case.arm.153.990 i64 152, label %tco.case.arm.152.1034 i64 157, label %tco.case.arm.157.1109 i64 156, label %tco.case.arm.156.1134 i64 155, label %tco.case.arm.155.1162 i64 160, label %tco.case.arm.160.1199 i64 159, label %tco.case.arm.159.1235 i64 158, label %tco.case.arm.158.1279 i64 163, label %tco.case.arm.163.1354 i64 162, label %tco.case.arm.162.1379 i64 161, label %tco.case.arm.161.1407 i64 166, label %tco.case.arm.166.1444 i64 165, label %tco.case.arm.165.1469 i64 164, label %tco.case.arm.164.1503 i64 168, label %tco.case.arm.168.1540 i64 167, label %tco.case.arm.167.1573 i64 171, label %tco.case.arm.171.1612 i64 170, label %tco.case.arm.170.1637 i64 169, label %tco.case.arm.169.1671 i64 173, label %tco.case.arm.173.1708 i64 172, label %tco.case.arm.172.1741 i64 174, label %tco.case.arm.174.1780 i64 175, label %tco.case.arm.175.1795 i64 176, label %tco.case.arm.176.1867 i64 177, label %tco.case.arm.177.1939 i64 179, label %tco.case.arm.179.1960 i64 178, label %tco.case.arm.178.1981 i64 182, label %tco.case.arm.182.2010 i64 181, label %tco.case.arm.181.2031 i64 180, label %tco.case.arm.180.2060 i64 184, label %tco.case.arm.184.2092 i64 183, label %tco.case.arm.183.2113 i64 185, label %tco.case.arm.185.2146 i64 186, label %tco.case.arm.186.2160 i64 187, label %tco.case.arm.187.2204 i64 189, label %tco.case.arm.189.2248 i64 188, label %tco.case.arm.188.2316 i64 191, label %tco.case.arm.191.2350 i64 190, label %tco.case.arm.190.2380 i64 193, label %tco.case.arm.193.2418 i64 192, label %tco.case.arm.192.2451 i64 195, label %tco.case.arm.195.2492 i64 194, label %tco.case.arm.194.2560 i64 197, label %tco.case.arm.197.2594 i64 196, label %tco.case.arm.196.2624 i64 199, label %tco.case.arm.199.2662 i64 198, label %tco.case.arm.198.2695 i64 201, label %tco.case.arm.201.2736 i64 200, label %tco.case.arm.200.2769 i64 203, label %tco.case.arm.203.2808 i64 202, label %tco.case.arm.202.2841 i64 205, label %tco.case.arm.205.2880 i64 204, label %tco.case.arm.204.2895 i64 207, label %tco.case.arm.207.2931 i64 206, label %tco.case.arm.206.2946 i64 208, label %tco.case.arm.208.2982 i64 209, label %tco.case.arm.209.3015 i64 210, label %tco.case.arm.210.3036 i64 212, label %tco.case.arm.212.3057 i64 211, label %tco.case.arm.211.3081 i64 213, label %tco.case.arm.213.3129 i64 215, label %tco.case.arm.215.3152 i64 214, label %tco.case.arm.214.3183 i64 216, label %tco.case.arm.216.3231 i64 221, label %tco.case.arm.221.3252 i64 220, label %tco.case.arm.220.3276 i64 219, label %tco.case.arm.219.3310 i64 218, label %tco.case.arm.218.3348 i64 217, label %tco.case.arm.217.3384 i64 222, label %tco.case.arm.222.3430 i64 223, label %tco.case.arm.223.3513 i64 225, label %tco.case.arm.225.3596 i64 224, label %tco.case.arm.224.3611 i64 226, label %tco.case.arm.226.3654 i64 228, label %tco.case.arm.228.3675 i64 227, label %tco.case.arm.227.3696 i64 231, label %tco.case.arm.231.3725 i64 230, label %tco.case.arm.230.3746 i64 229, label %tco.case.arm.229.3775 i64 234, label %tco.case.arm.234.3807 i64 233, label %tco.case.arm.233.3822 i64 235, label %tco.case.arm.235.3870 i64 232, label %tco.case.arm.232.3885 i64 237, label %tco.case.arm.237.3962 i64 236, label %tco.case.arm.236.3983 i64 241, label %tco.case.arm.241.4009 i64 240, label %tco.case.arm.240.4030 i64 239, label %tco.case.arm.239.4059 i64 238, label %tco.case.arm.238.4088 i64 247, label %tco.case.arm.247.4117 i64 246, label %tco.case.arm.246.4138 i64 245, label %tco.case.arm.245.4167 i64 244, label %tco.case.arm.244.4199 i64 243, label %tco.case.arm.243.4231 i64 242, label %tco.case.arm.242.4263 i64 250, label %tco.case.arm.250.4295 i64 249, label %tco.case.arm.249.4316 i64 248, label %tco.case.arm.248.4347 i64 255, label %tco.case.arm.255.4377 i64 254, label %tco.case.arm.254.4401 i64 253, label %tco.case.arm.253.4435 i64 252, label %tco.case.arm.252.4468 i64 251, label %tco.case.arm.251.4503 i64 256, label %tco.case.arm.256.4536 i64 257, label %tco.case.arm.257.4555 i64 259, label %tco.case.arm.259.4574 i64 258, label %tco.case.arm.258.4600 i64 261, label %tco.case.arm.261.4625 i64 260, label %tco.case.arm.260.4640 i64 262, label %tco.case.arm.262.4668 i64 263, label %tco.case.arm.263.4687 i64 264, label %tco.case.arm.264.4738 i64 265, label %tco.case.arm.265.4784 i64 266, label %tco.case.arm.266.4830 i64 267, label %tco.case.arm.267.4864 i64 269, label %tco.case.arm.269.4986 i64 268, label %tco.case.arm.268.5017 i64 270, label %tco.case.arm.270.5065 i64 271, label %tco.case.arm.271.5086 i64 272, label %tco.case.arm.272.5108 i64 273, label %tco.case.arm.273.5130 i64 274, label %tco.case.arm.274.5152 i64 275, label %tco.case.arm.275.5174 i64 276, label %tco.case.arm.276.5193 i64 277, label %tco.case.arm.277.5212 i64 278, label %tco.case.arm.278.5231 ]
tco.case.arm.126.18:
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %t4)
  store ptr %t13, ptr %t2
  br label %tco.exit.1
tco.case.arm.127.19:
  %t20 = call ptr @__alloc(i64 24, i32 2)
  %t21 = inttoptr i64 280 to ptr
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
  %t31 = inttoptr i64 53 to ptr
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
tco.case.arm.128.37:
  %t38 = call ptr @__alloc(i64 24, i32 2)
  %t39 = inttoptr i64 280 to ptr
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
  %t49 = inttoptr i64 53 to ptr
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
tco.case.arm.129.55:
  %t56 = call ptr @__alloc(i64 24, i32 2)
  %t57 = inttoptr i64 280 to ptr
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
  %t67 = inttoptr i64 53 to ptr
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
tco.case.arm.130.73:
  %t74 = call ptr @__alloc(i64 24, i32 2)
  %t75 = inttoptr i64 280 to ptr
  %t76 = getelementptr ptr, ptr %t74, i32 0
  store ptr %t75, ptr %t76
  %t77 = getelementptr ptr, ptr %t11, i32 2
  %t78 = load ptr, ptr %t77
  call void @__inc_ref(ptr %t78)
  %t79 = getelementptr ptr, ptr %t4, i32 1
  %t80 = load ptr, ptr %t79
  call void @__free_recursive(ptr %t80)
  %t81 = getelementptr ptr, ptr %t4, i32 2
  %t82 = load ptr, ptr %t81
  call void @__free_recursive(ptr %t82)
  %t85 = inttoptr i64 53 to ptr
  %t86 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t85, ptr %t86
  call void @__inc_ref(ptr %t13)
  %t83 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t13, ptr %t83
  %t84 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t78, ptr %t84
  %t87 = getelementptr ptr, ptr %t74, i32 1
  store ptr %t4, ptr %t87
  %t88 = getelementptr ptr, ptr %t11, i32 1
  %t89 = load ptr, ptr %t88
  call void @__inc_ref(ptr %t89)
  %t90 = getelementptr ptr, ptr %t74, i32 2
  store ptr %t89, ptr %t90
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t74, ptr %t3
  br label %tco.loop.0
tco.case.arm.131.91:
  %t92 = getelementptr ptr, ptr %t11, i32 1
  %t93 = load ptr, ptr %t92
  call void @__inc_ref(ptr %t93)
  call void @__inc_ref(ptr %t13)
  %t94 = call ptr @__alloc(i64 8, i32 0)
  %t95 = inttoptr i64 124 to ptr
  %t96 = getelementptr ptr, ptr %t94, i32 0
  store ptr %t95, ptr %t96
  %t97 = call ptr @v_$cps$$df$$rowmono$0$andThenIO$31(ptr %t13, ptr %t94)
  %t98 = getelementptr ptr, ptr %t4, i32 1
  %t99 = load ptr, ptr %t98
  call void @__free_recursive(ptr %t99)
  %t100 = getelementptr ptr, ptr %t4, i32 2
  %t101 = load ptr, ptr %t100
  call void @__free_recursive(ptr %t101)
  %t104 = inttoptr i64 279 to ptr
  %t105 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t104, ptr %t105
  %t102 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t93, ptr %t102
  %t103 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t97, ptr %t103
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.132.106:
  %t107 = call ptr @__alloc(i64 16, i32 1)
  %t108 = inttoptr i64 70 to ptr
  %t109 = getelementptr ptr, ptr %t107, i32 0
  store ptr %t108, ptr %t109
  call void @__inc_ref(ptr %t13)
  %t110 = getelementptr ptr, ptr %t107, i32 1
  store ptr %t13, ptr %t110
  %t111 = getelementptr ptr, ptr %t11, i32 1
  %t112 = load ptr, ptr %t111
  call void @__inc_ref(ptr %t112)
  %t113 = getelementptr ptr, ptr %t4, i32 1
  %t114 = load ptr, ptr %t113
  call void @__free_recursive(ptr %t114)
  %t115 = getelementptr ptr, ptr %t4, i32 2
  %t116 = load ptr, ptr %t115
  call void @__free_recursive(ptr %t116)
  %t119 = inttoptr i64 280 to ptr
  %t120 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t119, ptr %t120
  %t117 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t107, ptr %t117
  %t118 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t112, ptr %t118
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.133.121:
  %t122 = getelementptr ptr, ptr %t11, i32 1
  %t123 = load ptr, ptr %t122
  call void @__inc_ref(ptr %t123)
  call void @__inc_ref(ptr %t13)
  %t124 = call ptr @__alloc(i64 8, i32 0)
  %t125 = inttoptr i64 122 to ptr
  %t126 = getelementptr ptr, ptr %t124, i32 0
  store ptr %t125, ptr %t126
  %t127 = call ptr @v_$cps$$df$handleErrorIO$27(ptr %t13, ptr %t124)
  %t128 = getelementptr ptr, ptr %t4, i32 1
  %t129 = load ptr, ptr %t128
  call void @__free_recursive(ptr %t129)
  %t130 = getelementptr ptr, ptr %t4, i32 2
  %t131 = load ptr, ptr %t130
  call void @__free_recursive(ptr %t131)
  %t134 = inttoptr i64 279 to ptr
  %t135 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t134, ptr %t135
  %t132 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t123, ptr %t132
  %t133 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t127, ptr %t133
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.135.136:
  %t137 = getelementptr ptr, ptr %t11, i32 1
  %t138 = load ptr, ptr %t137
  call void @__inc_ref(ptr %t138)
  %t139 = getelementptr ptr, ptr %t11, i32 3
  %t140 = load ptr, ptr %t139
  call void @__inc_ref(ptr %t140)
  %t141 = getelementptr ptr, ptr %t11, i32 4
  %t142 = load ptr, ptr %t141
  call void @__inc_ref(ptr %t142)
  %t143 = getelementptr ptr, ptr %t11, i32 5
  %t144 = load ptr, ptr %t143
  call void @__inc_ref(ptr %t144)
  %t145 = getelementptr ptr, ptr %t11, i32 2
  %t146 = load ptr, ptr %t145
  call void @__inc_ref(ptr %t146)
  %t147 = getelementptr ptr, ptr %t13, i32 2
  %t148 = load ptr, ptr %t147
  call void @__inc_ref(ptr %t148)
  %t149 = call ptr @__subUInt32(ptr %t146, ptr %t148)
  %t150 = getelementptr ptr, ptr %t149, i32 0
  %t151 = load ptr, ptr %t150
  %t152 = ptrtoint ptr %t151 to i64
  switch i64 %t152, label %tco.case.default.153 [ i64 3, label %tco.case.arm.3.154 i64 4, label %tco.case.arm.4.185 ]
tco.case.arm.3.154:
  call void @__free_recursive(ptr %t149)
  %t155 = call ptr @__alloc(i64 32, i32 3)
  %t156 = inttoptr i64 34 to ptr
  %t157 = getelementptr ptr, ptr %t155, i32 0
  store ptr %t156, ptr %t157
  %t158 = call ptr @__alloc(i64 16, i32 1)
  %t159 = inttoptr i64 12 to ptr
  %t160 = getelementptr ptr, ptr %t158, i32 0
  store ptr %t159, ptr %t160
  %t161 = call ptr @__alloc(i64 16, i32 1)
  %t162 = inttoptr i64 24 to ptr
  %t163 = getelementptr ptr, ptr %t161, i32 0
  store ptr %t162, ptr %t163
  call void @__inc_ref(ptr %t140)
  %t164 = getelementptr ptr, ptr %t161, i32 1
  store ptr %t140, ptr %t164
  %t165 = getelementptr ptr, ptr %t158, i32 1
  store ptr %t161, ptr %t165
  %t166 = getelementptr ptr, ptr %t155, i32 1
  store ptr %t158, ptr %t166
  call void @__inc_ref(ptr %t142)
  %t167 = getelementptr ptr, ptr %t155, i32 2
  store ptr %t142, ptr %t167
  %t168 = call ptr @__alloc(i64 16, i32 1)
  %t169 = inttoptr i64 12 to ptr
  %t170 = getelementptr ptr, ptr %t168, i32 0
  store ptr %t169, ptr %t170
  %t171 = call ptr @__alloc(i64 16, i32 1)
  %t172 = inttoptr i64 24 to ptr
  %t173 = getelementptr ptr, ptr %t171, i32 0
  store ptr %t172, ptr %t173
  call void @__inc_ref(ptr %t144)
  %t174 = getelementptr ptr, ptr %t171, i32 1
  store ptr %t144, ptr %t174
  %t175 = getelementptr ptr, ptr %t168, i32 1
  store ptr %t171, ptr %t175
  %t176 = getelementptr ptr, ptr %t155, i32 3
  store ptr %t168, ptr %t176
  %t177 = getelementptr ptr, ptr %t4, i32 1
  %t178 = load ptr, ptr %t177
  call void @__free_recursive(ptr %t178)
  %t179 = getelementptr ptr, ptr %t4, i32 2
  %t180 = load ptr, ptr %t179
  call void @__free_recursive(ptr %t180)
  %t183 = inttoptr i64 279 to ptr
  %t184 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t183, ptr %t184
  call void @__inc_ref(ptr %t138)
  %t181 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t138, ptr %t181
  %t182 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t155, ptr %t182
  call void @__free_recursive(ptr %t144)
  call void @__free_recursive(ptr %t142)
  call void @__free_recursive(ptr %t140)
  call void @__free_recursive(ptr %t138)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.4.185:
  call void @__free_recursive(ptr %t149)
  %t186 = call ptr @__alloc(i64 24, i32 2)
  %t187 = inttoptr i64 279 to ptr
  %t188 = getelementptr ptr, ptr %t186, i32 0
  store ptr %t187, ptr %t188
  call void @__inc_ref(ptr %t138)
  %t189 = getelementptr ptr, ptr %t186, i32 1
  store ptr %t138, ptr %t189
  %t190 = call ptr @__alloc(i64 32, i32 3)
  %t191 = inttoptr i64 34 to ptr
  %t192 = getelementptr ptr, ptr %t190, i32 0
  store ptr %t191, ptr %t192
  %t193 = call ptr @__alloc(i64 16, i32 1)
  %t194 = inttoptr i64 12 to ptr
  %t195 = getelementptr ptr, ptr %t193, i32 0
  store ptr %t194, ptr %t195
  %t196 = getelementptr ptr, ptr %t4, i32 1
  %t197 = load ptr, ptr %t196
  call void @__free_recursive(ptr %t197)
  %t198 = getelementptr ptr, ptr %t4, i32 2
  %t199 = load ptr, ptr %t198
  call void @__free_recursive(ptr %t199)
  %t202 = inttoptr i64 25 to ptr
  %t203 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t202, ptr %t203
  call void @__inc_ref(ptr %t140)
  %t200 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t140, ptr %t200
  call void @__inc_ref(ptr %t142)
  %t201 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t142, ptr %t201
  %t204 = getelementptr ptr, ptr %t193, i32 1
  store ptr %t4, ptr %t204
  %t205 = getelementptr ptr, ptr %t190, i32 1
  store ptr %t193, ptr %t205
  call void @__inc_ref(ptr %t144)
  %t206 = getelementptr ptr, ptr %t190, i32 2
  store ptr %t144, ptr %t206
  %t207 = call ptr @__alloc(i64 8, i32 0)
  %t208 = inttoptr i64 11 to ptr
  %t209 = getelementptr ptr, ptr %t207, i32 0
  store ptr %t208, ptr %t209
  %t210 = getelementptr ptr, ptr %t190, i32 3
  store ptr %t207, ptr %t210
  %t211 = getelementptr ptr, ptr %t186, i32 2
  store ptr %t190, ptr %t211
  call void @__free_recursive(ptr %t144)
  call void @__free_recursive(ptr %t142)
  call void @__free_recursive(ptr %t140)
  call void @__free_recursive(ptr %t138)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t186, ptr %t3
  br label %tco.loop.0
tco.case.default.153:
  unreachable
tco.case.arm.134.212:
  %t213 = call ptr @__alloc(i64 32, i32 3)
  %t214 = inttoptr i64 88 to ptr
  %t215 = getelementptr ptr, ptr %t213, i32 0
  store ptr %t214, ptr %t215
  %t216 = getelementptr ptr, ptr %t11, i32 6
  %t217 = load ptr, ptr %t216
  call void @__inc_ref(ptr %t217)
  %t218 = getelementptr ptr, ptr %t213, i32 1
  store ptr %t217, ptr %t218
  %t219 = getelementptr ptr, ptr %t11, i32 7
  %t220 = load ptr, ptr %t219
  call void @__inc_ref(ptr %t220)
  %t221 = getelementptr ptr, ptr %t213, i32 2
  store ptr %t220, ptr %t221
  call void @__inc_ref(ptr %t13)
  %t222 = getelementptr ptr, ptr %t213, i32 3
  store ptr %t13, ptr %t222
  %t223 = call ptr @__alloc(i64 48, i32 5)
  %t224 = inttoptr i64 135 to ptr
  %t225 = getelementptr ptr, ptr %t223, i32 0
  store ptr %t224, ptr %t225
  %t226 = getelementptr ptr, ptr %t11, i32 1
  %t227 = load ptr, ptr %t226
  call void @__inc_ref(ptr %t227)
  %t228 = getelementptr ptr, ptr %t223, i32 1
  store ptr %t227, ptr %t228
  %t229 = getelementptr ptr, ptr %t11, i32 2
  %t230 = load ptr, ptr %t229
  call void @__inc_ref(ptr %t230)
  %t231 = getelementptr ptr, ptr %t223, i32 2
  store ptr %t230, ptr %t231
  %t232 = getelementptr ptr, ptr %t11, i32 3
  %t233 = load ptr, ptr %t232
  call void @__inc_ref(ptr %t233)
  %t234 = getelementptr ptr, ptr %t223, i32 3
  store ptr %t233, ptr %t234
  %t235 = getelementptr ptr, ptr %t11, i32 4
  %t236 = load ptr, ptr %t235
  call void @__inc_ref(ptr %t236)
  %t237 = getelementptr ptr, ptr %t223, i32 4
  store ptr %t236, ptr %t237
  %t238 = getelementptr ptr, ptr %t11, i32 5
  %t239 = load ptr, ptr %t238
  call void @__inc_ref(ptr %t239)
  %t240 = getelementptr ptr, ptr %t223, i32 5
  store ptr %t239, ptr %t240
  %t241 = getelementptr ptr, ptr %t4, i32 1
  %t242 = load ptr, ptr %t241
  call void @__free_recursive(ptr %t242)
  %t243 = getelementptr ptr, ptr %t4, i32 2
  %t244 = load ptr, ptr %t243
  call void @__free_recursive(ptr %t244)
  %t247 = inttoptr i64 280 to ptr
  %t248 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t247, ptr %t248
  %t245 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t213, ptr %t245
  %t246 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t223, ptr %t246
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.137.249:
  %t250 = getelementptr ptr, ptr %t11, i32 1
  %t251 = load ptr, ptr %t250
  call void @__inc_ref(ptr %t251)
  %t252 = getelementptr ptr, ptr %t11, i32 3
  %t253 = load ptr, ptr %t252
  call void @__inc_ref(ptr %t253)
  %t254 = getelementptr ptr, ptr %t11, i32 4
  %t255 = load ptr, ptr %t254
  call void @__inc_ref(ptr %t255)
  %t256 = getelementptr ptr, ptr %t11, i32 5
  %t257 = load ptr, ptr %t256
  call void @__inc_ref(ptr %t257)
  %t258 = getelementptr ptr, ptr %t11, i32 2
  %t259 = load ptr, ptr %t258
  call void @__inc_ref(ptr %t259)
  %t260 = getelementptr ptr, ptr %t13, i32 1
  %t261 = load ptr, ptr %t260
  call void @__inc_ref(ptr %t261)
  %t262 = call ptr @__subUInt32(ptr %t259, ptr %t261)
  %t263 = getelementptr ptr, ptr %t262, i32 0
  %t264 = load ptr, ptr %t263
  %t265 = ptrtoint ptr %t264 to i64
  switch i64 %t265, label %tco.case.default.266 [ i64 3, label %tco.case.arm.3.267 i64 4, label %tco.case.arm.4.298 ]
tco.case.arm.3.267:
  call void @__free_recursive(ptr %t262)
  %t268 = call ptr @__alloc(i64 32, i32 3)
  %t269 = inttoptr i64 34 to ptr
  %t270 = getelementptr ptr, ptr %t268, i32 0
  store ptr %t269, ptr %t270
  %t271 = call ptr @__alloc(i64 16, i32 1)
  %t272 = inttoptr i64 12 to ptr
  %t273 = getelementptr ptr, ptr %t271, i32 0
  store ptr %t272, ptr %t273
  %t274 = call ptr @__alloc(i64 16, i32 1)
  %t275 = inttoptr i64 24 to ptr
  %t276 = getelementptr ptr, ptr %t274, i32 0
  store ptr %t275, ptr %t276
  call void @__inc_ref(ptr %t253)
  %t277 = getelementptr ptr, ptr %t274, i32 1
  store ptr %t253, ptr %t277
  %t278 = getelementptr ptr, ptr %t271, i32 1
  store ptr %t274, ptr %t278
  %t279 = getelementptr ptr, ptr %t268, i32 1
  store ptr %t271, ptr %t279
  call void @__inc_ref(ptr %t255)
  %t280 = getelementptr ptr, ptr %t268, i32 2
  store ptr %t255, ptr %t280
  %t281 = call ptr @__alloc(i64 16, i32 1)
  %t282 = inttoptr i64 12 to ptr
  %t283 = getelementptr ptr, ptr %t281, i32 0
  store ptr %t282, ptr %t283
  %t284 = call ptr @__alloc(i64 16, i32 1)
  %t285 = inttoptr i64 24 to ptr
  %t286 = getelementptr ptr, ptr %t284, i32 0
  store ptr %t285, ptr %t286
  call void @__inc_ref(ptr %t257)
  %t287 = getelementptr ptr, ptr %t284, i32 1
  store ptr %t257, ptr %t287
  %t288 = getelementptr ptr, ptr %t281, i32 1
  store ptr %t284, ptr %t288
  %t289 = getelementptr ptr, ptr %t268, i32 3
  store ptr %t281, ptr %t289
  %t290 = getelementptr ptr, ptr %t4, i32 1
  %t291 = load ptr, ptr %t290
  call void @__free_recursive(ptr %t291)
  %t292 = getelementptr ptr, ptr %t4, i32 2
  %t293 = load ptr, ptr %t292
  call void @__free_recursive(ptr %t293)
  %t296 = inttoptr i64 279 to ptr
  %t297 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t296, ptr %t297
  call void @__inc_ref(ptr %t251)
  %t294 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t251, ptr %t294
  %t295 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t268, ptr %t295
  call void @__free_recursive(ptr %t257)
  call void @__free_recursive(ptr %t255)
  call void @__free_recursive(ptr %t253)
  call void @__free_recursive(ptr %t251)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.4.298:
  call void @__free_recursive(ptr %t262)
  %t299 = call ptr @__alloc(i64 24, i32 2)
  %t300 = inttoptr i64 279 to ptr
  %t301 = getelementptr ptr, ptr %t299, i32 0
  store ptr %t300, ptr %t301
  call void @__inc_ref(ptr %t251)
  %t302 = getelementptr ptr, ptr %t299, i32 1
  store ptr %t251, ptr %t302
  %t303 = call ptr @__alloc(i64 32, i32 3)
  %t304 = inttoptr i64 34 to ptr
  %t305 = getelementptr ptr, ptr %t303, i32 0
  store ptr %t304, ptr %t305
  %t306 = call ptr @__alloc(i64 16, i32 1)
  %t307 = inttoptr i64 12 to ptr
  %t308 = getelementptr ptr, ptr %t306, i32 0
  store ptr %t307, ptr %t308
  %t309 = getelementptr ptr, ptr %t4, i32 1
  %t310 = load ptr, ptr %t309
  call void @__free_recursive(ptr %t310)
  %t311 = getelementptr ptr, ptr %t4, i32 2
  %t312 = load ptr, ptr %t311
  call void @__free_recursive(ptr %t312)
  %t315 = inttoptr i64 25 to ptr
  %t316 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t315, ptr %t316
  call void @__inc_ref(ptr %t253)
  %t313 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t253, ptr %t313
  call void @__inc_ref(ptr %t255)
  %t314 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t255, ptr %t314
  %t317 = getelementptr ptr, ptr %t306, i32 1
  store ptr %t4, ptr %t317
  %t318 = getelementptr ptr, ptr %t303, i32 1
  store ptr %t306, ptr %t318
  call void @__inc_ref(ptr %t257)
  %t319 = getelementptr ptr, ptr %t303, i32 2
  store ptr %t257, ptr %t319
  %t320 = call ptr @__alloc(i64 8, i32 0)
  %t321 = inttoptr i64 11 to ptr
  %t322 = getelementptr ptr, ptr %t320, i32 0
  store ptr %t321, ptr %t322
  %t323 = getelementptr ptr, ptr %t303, i32 3
  store ptr %t320, ptr %t323
  %t324 = getelementptr ptr, ptr %t299, i32 2
  store ptr %t303, ptr %t324
  call void @__free_recursive(ptr %t257)
  call void @__free_recursive(ptr %t255)
  call void @__free_recursive(ptr %t253)
  call void @__free_recursive(ptr %t251)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t299, ptr %t3
  br label %tco.loop.0
tco.case.default.266:
  unreachable
tco.case.arm.136.325:
  %t326 = call ptr @__alloc(i64 32, i32 3)
  %t327 = inttoptr i64 88 to ptr
  %t328 = getelementptr ptr, ptr %t326, i32 0
  store ptr %t327, ptr %t328
  %t329 = getelementptr ptr, ptr %t11, i32 6
  %t330 = load ptr, ptr %t329
  call void @__inc_ref(ptr %t330)
  %t331 = getelementptr ptr, ptr %t326, i32 1
  store ptr %t330, ptr %t331
  %t332 = getelementptr ptr, ptr %t11, i32 7
  %t333 = load ptr, ptr %t332
  call void @__inc_ref(ptr %t333)
  %t334 = getelementptr ptr, ptr %t326, i32 2
  store ptr %t333, ptr %t334
  call void @__inc_ref(ptr %t13)
  %t335 = getelementptr ptr, ptr %t326, i32 3
  store ptr %t13, ptr %t335
  %t336 = call ptr @__alloc(i64 48, i32 5)
  %t337 = inttoptr i64 137 to ptr
  %t338 = getelementptr ptr, ptr %t336, i32 0
  store ptr %t337, ptr %t338
  %t339 = getelementptr ptr, ptr %t11, i32 1
  %t340 = load ptr, ptr %t339
  call void @__inc_ref(ptr %t340)
  %t341 = getelementptr ptr, ptr %t336, i32 1
  store ptr %t340, ptr %t341
  %t342 = getelementptr ptr, ptr %t11, i32 2
  %t343 = load ptr, ptr %t342
  call void @__inc_ref(ptr %t343)
  %t344 = getelementptr ptr, ptr %t336, i32 2
  store ptr %t343, ptr %t344
  %t345 = getelementptr ptr, ptr %t11, i32 3
  %t346 = load ptr, ptr %t345
  call void @__inc_ref(ptr %t346)
  %t347 = getelementptr ptr, ptr %t336, i32 3
  store ptr %t346, ptr %t347
  %t348 = getelementptr ptr, ptr %t11, i32 4
  %t349 = load ptr, ptr %t348
  call void @__inc_ref(ptr %t349)
  %t350 = getelementptr ptr, ptr %t336, i32 4
  store ptr %t349, ptr %t350
  %t351 = getelementptr ptr, ptr %t11, i32 5
  %t352 = load ptr, ptr %t351
  call void @__inc_ref(ptr %t352)
  %t353 = getelementptr ptr, ptr %t336, i32 5
  store ptr %t352, ptr %t353
  %t354 = getelementptr ptr, ptr %t4, i32 1
  %t355 = load ptr, ptr %t354
  call void @__free_recursive(ptr %t355)
  %t356 = getelementptr ptr, ptr %t4, i32 2
  %t357 = load ptr, ptr %t356
  call void @__free_recursive(ptr %t357)
  %t360 = inttoptr i64 280 to ptr
  %t361 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t360, ptr %t361
  %t358 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t326, ptr %t358
  %t359 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t336, ptr %t359
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.139.362:
  %t363 = getelementptr ptr, ptr %t11, i32 1
  %t364 = load ptr, ptr %t363
  call void @__inc_ref(ptr %t364)
  %t365 = getelementptr ptr, ptr %t11, i32 3
  %t366 = load ptr, ptr %t365
  call void @__inc_ref(ptr %t366)
  %t367 = getelementptr ptr, ptr %t11, i32 4
  %t368 = load ptr, ptr %t367
  call void @__inc_ref(ptr %t368)
  %t369 = getelementptr ptr, ptr %t11, i32 5
  %t370 = load ptr, ptr %t369
  call void @__inc_ref(ptr %t370)
  %t371 = getelementptr ptr, ptr %t11, i32 6
  %t372 = load ptr, ptr %t371
  call void @__inc_ref(ptr %t372)
  %t373 = getelementptr ptr, ptr %t11, i32 2
  %t374 = load ptr, ptr %t373
  call void @__inc_ref(ptr %t374)
  %t375 = getelementptr ptr, ptr %t13, i32 2
  %t376 = load ptr, ptr %t375
  call void @__inc_ref(ptr %t376)
  %t377 = call ptr @__subUInt32(ptr %t374, ptr %t376)
  %t378 = getelementptr ptr, ptr %t377, i32 0
  %t379 = load ptr, ptr %t378
  %t380 = ptrtoint ptr %t379 to i64
  switch i64 %t380, label %tco.case.default.381 [ i64 3, label %tco.case.arm.3.382 i64 4, label %tco.case.arm.4.414 ]
tco.case.arm.3.382:
  call void @__free_recursive(ptr %t377)
  %t383 = call ptr @__alloc(i64 24, i32 2)
  %t384 = inttoptr i64 279 to ptr
  %t385 = getelementptr ptr, ptr %t383, i32 0
  store ptr %t384, ptr %t385
  call void @__inc_ref(ptr %t364)
  %t386 = getelementptr ptr, ptr %t383, i32 1
  store ptr %t364, ptr %t386
  %t387 = call ptr @__alloc(i64 32, i32 3)
  %t388 = inttoptr i64 34 to ptr
  %t389 = getelementptr ptr, ptr %t387, i32 0
  store ptr %t388, ptr %t389
  %t390 = call ptr @__alloc(i64 16, i32 1)
  %t391 = inttoptr i64 12 to ptr
  %t392 = getelementptr ptr, ptr %t390, i32 0
  store ptr %t391, ptr %t392
  %t393 = getelementptr ptr, ptr %t4, i32 1
  %t394 = load ptr, ptr %t393
  call void @__free_recursive(ptr %t394)
  %t395 = getelementptr ptr, ptr %t4, i32 2
  %t396 = load ptr, ptr %t395
  call void @__free_recursive(ptr %t396)
  %t399 = inttoptr i64 25 to ptr
  %t400 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t399, ptr %t400
  call void @__inc_ref(ptr %t366)
  %t397 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t366, ptr %t397
  call void @__inc_ref(ptr %t368)
  %t398 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t368, ptr %t398
  %t401 = getelementptr ptr, ptr %t390, i32 1
  store ptr %t4, ptr %t401
  %t402 = getelementptr ptr, ptr %t387, i32 1
  store ptr %t390, ptr %t402
  call void @__inc_ref(ptr %t370)
  %t403 = getelementptr ptr, ptr %t387, i32 2
  store ptr %t370, ptr %t403
  %t404 = call ptr @__alloc(i64 16, i32 1)
  %t405 = inttoptr i64 12 to ptr
  %t406 = getelementptr ptr, ptr %t404, i32 0
  store ptr %t405, ptr %t406
  %t407 = call ptr @__alloc(i64 16, i32 1)
  %t408 = inttoptr i64 24 to ptr
  %t409 = getelementptr ptr, ptr %t407, i32 0
  store ptr %t408, ptr %t409
  call void @__inc_ref(ptr %t372)
  %t410 = getelementptr ptr, ptr %t407, i32 1
  store ptr %t372, ptr %t410
  %t411 = getelementptr ptr, ptr %t404, i32 1
  store ptr %t407, ptr %t411
  %t412 = getelementptr ptr, ptr %t387, i32 3
  store ptr %t404, ptr %t412
  %t413 = getelementptr ptr, ptr %t383, i32 2
  store ptr %t387, ptr %t413
  call void @__free_recursive(ptr %t372)
  call void @__free_recursive(ptr %t370)
  call void @__free_recursive(ptr %t368)
  call void @__free_recursive(ptr %t366)
  call void @__free_recursive(ptr %t364)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t383, ptr %t3
  br label %tco.loop.0
tco.case.arm.4.414:
  call void @__free_recursive(ptr %t377)
  %t415 = call ptr @__alloc(i64 32, i32 3)
  %t416 = inttoptr i64 34 to ptr
  %t417 = getelementptr ptr, ptr %t415, i32 0
  store ptr %t416, ptr %t417
  %t418 = call ptr @__alloc(i64 16, i32 1)
  %t419 = inttoptr i64 12 to ptr
  %t420 = getelementptr ptr, ptr %t418, i32 0
  store ptr %t419, ptr %t420
  %t421 = call ptr @__alloc(i64 32, i32 3)
  %t422 = inttoptr i64 26 to ptr
  %t423 = getelementptr ptr, ptr %t421, i32 0
  store ptr %t422, ptr %t423
  call void @__inc_ref(ptr %t366)
  %t424 = getelementptr ptr, ptr %t421, i32 1
  store ptr %t366, ptr %t424
  call void @__inc_ref(ptr %t368)
  %t425 = getelementptr ptr, ptr %t421, i32 2
  store ptr %t368, ptr %t425
  call void @__inc_ref(ptr %t370)
  %t426 = getelementptr ptr, ptr %t421, i32 3
  store ptr %t370, ptr %t426
  %t427 = getelementptr ptr, ptr %t418, i32 1
  store ptr %t421, ptr %t427
  %t428 = getelementptr ptr, ptr %t415, i32 1
  store ptr %t418, ptr %t428
  call void @__inc_ref(ptr %t372)
  %t429 = getelementptr ptr, ptr %t415, i32 2
  store ptr %t372, ptr %t429
  %t430 = call ptr @__alloc(i64 8, i32 0)
  %t431 = inttoptr i64 11 to ptr
  %t432 = getelementptr ptr, ptr %t430, i32 0
  store ptr %t431, ptr %t432
  %t433 = getelementptr ptr, ptr %t415, i32 3
  store ptr %t430, ptr %t433
  %t434 = getelementptr ptr, ptr %t4, i32 1
  %t435 = load ptr, ptr %t434
  call void @__free_recursive(ptr %t435)
  %t436 = getelementptr ptr, ptr %t4, i32 2
  %t437 = load ptr, ptr %t436
  call void @__free_recursive(ptr %t437)
  %t440 = inttoptr i64 279 to ptr
  %t441 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t440, ptr %t441
  call void @__inc_ref(ptr %t364)
  %t438 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t364, ptr %t438
  %t439 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t415, ptr %t439
  call void @__free_recursive(ptr %t372)
  call void @__free_recursive(ptr %t370)
  call void @__free_recursive(ptr %t368)
  call void @__free_recursive(ptr %t366)
  call void @__free_recursive(ptr %t364)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.381:
  unreachable
tco.case.arm.138.442:
  %t443 = call ptr @__alloc(i64 32, i32 3)
  %t444 = inttoptr i64 88 to ptr
  %t445 = getelementptr ptr, ptr %t443, i32 0
  store ptr %t444, ptr %t445
  %t446 = getelementptr ptr, ptr %t11, i32 7
  %t447 = load ptr, ptr %t446
  call void @__inc_ref(ptr %t447)
  %t448 = getelementptr ptr, ptr %t443, i32 1
  store ptr %t447, ptr %t448
  %t449 = getelementptr ptr, ptr %t11, i32 8
  %t450 = load ptr, ptr %t449
  call void @__inc_ref(ptr %t450)
  %t451 = getelementptr ptr, ptr %t443, i32 2
  store ptr %t450, ptr %t451
  call void @__inc_ref(ptr %t13)
  %t452 = getelementptr ptr, ptr %t443, i32 3
  store ptr %t13, ptr %t452
  %t453 = call ptr @__alloc(i64 56, i32 6)
  %t454 = inttoptr i64 139 to ptr
  %t455 = getelementptr ptr, ptr %t453, i32 0
  store ptr %t454, ptr %t455
  %t456 = getelementptr ptr, ptr %t11, i32 1
  %t457 = load ptr, ptr %t456
  call void @__inc_ref(ptr %t457)
  %t458 = getelementptr ptr, ptr %t453, i32 1
  store ptr %t457, ptr %t458
  %t459 = getelementptr ptr, ptr %t11, i32 2
  %t460 = load ptr, ptr %t459
  call void @__inc_ref(ptr %t460)
  %t461 = getelementptr ptr, ptr %t453, i32 2
  store ptr %t460, ptr %t461
  %t462 = getelementptr ptr, ptr %t11, i32 3
  %t463 = load ptr, ptr %t462
  call void @__inc_ref(ptr %t463)
  %t464 = getelementptr ptr, ptr %t453, i32 3
  store ptr %t463, ptr %t464
  %t465 = getelementptr ptr, ptr %t11, i32 4
  %t466 = load ptr, ptr %t465
  call void @__inc_ref(ptr %t466)
  %t467 = getelementptr ptr, ptr %t453, i32 4
  store ptr %t466, ptr %t467
  %t468 = getelementptr ptr, ptr %t11, i32 5
  %t469 = load ptr, ptr %t468
  call void @__inc_ref(ptr %t469)
  %t470 = getelementptr ptr, ptr %t453, i32 5
  store ptr %t469, ptr %t470
  %t471 = getelementptr ptr, ptr %t11, i32 6
  %t472 = load ptr, ptr %t471
  call void @__inc_ref(ptr %t472)
  %t473 = getelementptr ptr, ptr %t453, i32 6
  store ptr %t472, ptr %t473
  %t474 = getelementptr ptr, ptr %t4, i32 1
  %t475 = load ptr, ptr %t474
  call void @__free_recursive(ptr %t475)
  %t476 = getelementptr ptr, ptr %t4, i32 2
  %t477 = load ptr, ptr %t476
  call void @__free_recursive(ptr %t477)
  %t480 = inttoptr i64 280 to ptr
  %t481 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t480, ptr %t481
  %t478 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t443, ptr %t478
  %t479 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t453, ptr %t479
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.141.482:
  %t483 = getelementptr ptr, ptr %t11, i32 1
  %t484 = load ptr, ptr %t483
  call void @__inc_ref(ptr %t484)
  %t485 = getelementptr ptr, ptr %t11, i32 3
  %t486 = load ptr, ptr %t485
  call void @__inc_ref(ptr %t486)
  %t487 = getelementptr ptr, ptr %t11, i32 4
  %t488 = load ptr, ptr %t487
  call void @__inc_ref(ptr %t488)
  %t489 = getelementptr ptr, ptr %t11, i32 5
  %t490 = load ptr, ptr %t489
  call void @__inc_ref(ptr %t490)
  %t491 = getelementptr ptr, ptr %t11, i32 6
  %t492 = load ptr, ptr %t491
  call void @__inc_ref(ptr %t492)
  %t493 = getelementptr ptr, ptr %t11, i32 2
  %t494 = load ptr, ptr %t493
  call void @__inc_ref(ptr %t494)
  %t495 = getelementptr ptr, ptr %t13, i32 1
  %t496 = load ptr, ptr %t495
  call void @__inc_ref(ptr %t496)
  %t497 = call ptr @__subUInt32(ptr %t494, ptr %t496)
  %t498 = getelementptr ptr, ptr %t497, i32 0
  %t499 = load ptr, ptr %t498
  %t500 = ptrtoint ptr %t499 to i64
  switch i64 %t500, label %tco.case.default.501 [ i64 3, label %tco.case.arm.3.502 i64 4, label %tco.case.arm.4.534 ]
tco.case.arm.3.502:
  call void @__free_recursive(ptr %t497)
  %t503 = call ptr @__alloc(i64 24, i32 2)
  %t504 = inttoptr i64 279 to ptr
  %t505 = getelementptr ptr, ptr %t503, i32 0
  store ptr %t504, ptr %t505
  call void @__inc_ref(ptr %t484)
  %t506 = getelementptr ptr, ptr %t503, i32 1
  store ptr %t484, ptr %t506
  %t507 = call ptr @__alloc(i64 32, i32 3)
  %t508 = inttoptr i64 34 to ptr
  %t509 = getelementptr ptr, ptr %t507, i32 0
  store ptr %t508, ptr %t509
  %t510 = call ptr @__alloc(i64 16, i32 1)
  %t511 = inttoptr i64 12 to ptr
  %t512 = getelementptr ptr, ptr %t510, i32 0
  store ptr %t511, ptr %t512
  %t513 = getelementptr ptr, ptr %t4, i32 1
  %t514 = load ptr, ptr %t513
  call void @__free_recursive(ptr %t514)
  %t515 = getelementptr ptr, ptr %t4, i32 2
  %t516 = load ptr, ptr %t515
  call void @__free_recursive(ptr %t516)
  %t519 = inttoptr i64 25 to ptr
  %t520 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t519, ptr %t520
  call void @__inc_ref(ptr %t486)
  %t517 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t486, ptr %t517
  call void @__inc_ref(ptr %t488)
  %t518 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t488, ptr %t518
  %t521 = getelementptr ptr, ptr %t510, i32 1
  store ptr %t4, ptr %t521
  %t522 = getelementptr ptr, ptr %t507, i32 1
  store ptr %t510, ptr %t522
  call void @__inc_ref(ptr %t490)
  %t523 = getelementptr ptr, ptr %t507, i32 2
  store ptr %t490, ptr %t523
  %t524 = call ptr @__alloc(i64 16, i32 1)
  %t525 = inttoptr i64 12 to ptr
  %t526 = getelementptr ptr, ptr %t524, i32 0
  store ptr %t525, ptr %t526
  %t527 = call ptr @__alloc(i64 16, i32 1)
  %t528 = inttoptr i64 24 to ptr
  %t529 = getelementptr ptr, ptr %t527, i32 0
  store ptr %t528, ptr %t529
  call void @__inc_ref(ptr %t492)
  %t530 = getelementptr ptr, ptr %t527, i32 1
  store ptr %t492, ptr %t530
  %t531 = getelementptr ptr, ptr %t524, i32 1
  store ptr %t527, ptr %t531
  %t532 = getelementptr ptr, ptr %t507, i32 3
  store ptr %t524, ptr %t532
  %t533 = getelementptr ptr, ptr %t503, i32 2
  store ptr %t507, ptr %t533
  call void @__free_recursive(ptr %t492)
  call void @__free_recursive(ptr %t490)
  call void @__free_recursive(ptr %t488)
  call void @__free_recursive(ptr %t486)
  call void @__free_recursive(ptr %t484)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t503, ptr %t3
  br label %tco.loop.0
tco.case.arm.4.534:
  call void @__free_recursive(ptr %t497)
  %t535 = call ptr @__alloc(i64 32, i32 3)
  %t536 = inttoptr i64 34 to ptr
  %t537 = getelementptr ptr, ptr %t535, i32 0
  store ptr %t536, ptr %t537
  %t538 = call ptr @__alloc(i64 16, i32 1)
  %t539 = inttoptr i64 12 to ptr
  %t540 = getelementptr ptr, ptr %t538, i32 0
  store ptr %t539, ptr %t540
  %t541 = call ptr @__alloc(i64 32, i32 3)
  %t542 = inttoptr i64 26 to ptr
  %t543 = getelementptr ptr, ptr %t541, i32 0
  store ptr %t542, ptr %t543
  call void @__inc_ref(ptr %t486)
  %t544 = getelementptr ptr, ptr %t541, i32 1
  store ptr %t486, ptr %t544
  call void @__inc_ref(ptr %t488)
  %t545 = getelementptr ptr, ptr %t541, i32 2
  store ptr %t488, ptr %t545
  call void @__inc_ref(ptr %t490)
  %t546 = getelementptr ptr, ptr %t541, i32 3
  store ptr %t490, ptr %t546
  %t547 = getelementptr ptr, ptr %t538, i32 1
  store ptr %t541, ptr %t547
  %t548 = getelementptr ptr, ptr %t535, i32 1
  store ptr %t538, ptr %t548
  call void @__inc_ref(ptr %t492)
  %t549 = getelementptr ptr, ptr %t535, i32 2
  store ptr %t492, ptr %t549
  %t550 = call ptr @__alloc(i64 8, i32 0)
  %t551 = inttoptr i64 11 to ptr
  %t552 = getelementptr ptr, ptr %t550, i32 0
  store ptr %t551, ptr %t552
  %t553 = getelementptr ptr, ptr %t535, i32 3
  store ptr %t550, ptr %t553
  %t554 = getelementptr ptr, ptr %t4, i32 1
  %t555 = load ptr, ptr %t554
  call void @__free_recursive(ptr %t555)
  %t556 = getelementptr ptr, ptr %t4, i32 2
  %t557 = load ptr, ptr %t556
  call void @__free_recursive(ptr %t557)
  %t560 = inttoptr i64 279 to ptr
  %t561 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t560, ptr %t561
  call void @__inc_ref(ptr %t484)
  %t558 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t484, ptr %t558
  %t559 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t535, ptr %t559
  call void @__free_recursive(ptr %t492)
  call void @__free_recursive(ptr %t490)
  call void @__free_recursive(ptr %t488)
  call void @__free_recursive(ptr %t486)
  call void @__free_recursive(ptr %t484)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.501:
  unreachable
tco.case.arm.140.562:
  %t563 = call ptr @__alloc(i64 32, i32 3)
  %t564 = inttoptr i64 88 to ptr
  %t565 = getelementptr ptr, ptr %t563, i32 0
  store ptr %t564, ptr %t565
  %t566 = getelementptr ptr, ptr %t11, i32 7
  %t567 = load ptr, ptr %t566
  call void @__inc_ref(ptr %t567)
  %t568 = getelementptr ptr, ptr %t563, i32 1
  store ptr %t567, ptr %t568
  %t569 = getelementptr ptr, ptr %t11, i32 8
  %t570 = load ptr, ptr %t569
  call void @__inc_ref(ptr %t570)
  %t571 = getelementptr ptr, ptr %t563, i32 2
  store ptr %t570, ptr %t571
  call void @__inc_ref(ptr %t13)
  %t572 = getelementptr ptr, ptr %t563, i32 3
  store ptr %t13, ptr %t572
  %t573 = call ptr @__alloc(i64 56, i32 6)
  %t574 = inttoptr i64 141 to ptr
  %t575 = getelementptr ptr, ptr %t573, i32 0
  store ptr %t574, ptr %t575
  %t576 = getelementptr ptr, ptr %t11, i32 1
  %t577 = load ptr, ptr %t576
  call void @__inc_ref(ptr %t577)
  %t578 = getelementptr ptr, ptr %t573, i32 1
  store ptr %t577, ptr %t578
  %t579 = getelementptr ptr, ptr %t11, i32 2
  %t580 = load ptr, ptr %t579
  call void @__inc_ref(ptr %t580)
  %t581 = getelementptr ptr, ptr %t573, i32 2
  store ptr %t580, ptr %t581
  %t582 = getelementptr ptr, ptr %t11, i32 3
  %t583 = load ptr, ptr %t582
  call void @__inc_ref(ptr %t583)
  %t584 = getelementptr ptr, ptr %t573, i32 3
  store ptr %t583, ptr %t584
  %t585 = getelementptr ptr, ptr %t11, i32 4
  %t586 = load ptr, ptr %t585
  call void @__inc_ref(ptr %t586)
  %t587 = getelementptr ptr, ptr %t573, i32 4
  store ptr %t586, ptr %t587
  %t588 = getelementptr ptr, ptr %t11, i32 5
  %t589 = load ptr, ptr %t588
  call void @__inc_ref(ptr %t589)
  %t590 = getelementptr ptr, ptr %t573, i32 5
  store ptr %t589, ptr %t590
  %t591 = getelementptr ptr, ptr %t11, i32 6
  %t592 = load ptr, ptr %t591
  call void @__inc_ref(ptr %t592)
  %t593 = getelementptr ptr, ptr %t573, i32 6
  store ptr %t592, ptr %t593
  %t594 = getelementptr ptr, ptr %t4, i32 1
  %t595 = load ptr, ptr %t594
  call void @__free_recursive(ptr %t595)
  %t596 = getelementptr ptr, ptr %t4, i32 2
  %t597 = load ptr, ptr %t596
  call void @__free_recursive(ptr %t597)
  %t600 = inttoptr i64 280 to ptr
  %t601 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t600, ptr %t601
  %t598 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t563, ptr %t598
  %t599 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t573, ptr %t599
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.143.602:
  %t603 = call ptr @__alloc(i64 64, i32 7)
  %t604 = inttoptr i64 60 to ptr
  %t605 = getelementptr ptr, ptr %t603, i32 0
  store ptr %t604, ptr %t605
  %t606 = getelementptr ptr, ptr %t11, i32 2
  %t607 = load ptr, ptr %t606
  call void @__inc_ref(ptr %t607)
  %t608 = getelementptr ptr, ptr %t603, i32 1
  store ptr %t607, ptr %t608
  %t609 = getelementptr ptr, ptr %t11, i32 3
  %t610 = load ptr, ptr %t609
  call void @__inc_ref(ptr %t610)
  %t611 = getelementptr ptr, ptr %t603, i32 2
  store ptr %t610, ptr %t611
  %t612 = getelementptr ptr, ptr %t11, i32 4
  %t613 = load ptr, ptr %t612
  call void @__inc_ref(ptr %t613)
  %t614 = getelementptr ptr, ptr %t603, i32 3
  store ptr %t613, ptr %t614
  %t615 = getelementptr ptr, ptr %t11, i32 5
  %t616 = load ptr, ptr %t615
  call void @__inc_ref(ptr %t616)
  %t617 = getelementptr ptr, ptr %t603, i32 4
  store ptr %t616, ptr %t617
  %t618 = getelementptr ptr, ptr %t11, i32 6
  %t619 = load ptr, ptr %t618
  call void @__inc_ref(ptr %t619)
  %t620 = getelementptr ptr, ptr %t603, i32 5
  store ptr %t619, ptr %t620
  %t621 = getelementptr ptr, ptr %t11, i32 7
  %t622 = load ptr, ptr %t621
  call void @__inc_ref(ptr %t622)
  %t623 = getelementptr ptr, ptr %t603, i32 6
  store ptr %t622, ptr %t623
  call void @__inc_ref(ptr %t13)
  %t624 = getelementptr ptr, ptr %t603, i32 7
  store ptr %t13, ptr %t624
  %t625 = getelementptr ptr, ptr %t11, i32 1
  %t626 = load ptr, ptr %t625
  call void @__inc_ref(ptr %t626)
  %t627 = getelementptr ptr, ptr %t4, i32 1
  %t628 = load ptr, ptr %t627
  call void @__free_recursive(ptr %t628)
  %t629 = getelementptr ptr, ptr %t4, i32 2
  %t630 = load ptr, ptr %t629
  call void @__free_recursive(ptr %t630)
  %t633 = inttoptr i64 280 to ptr
  %t634 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t633, ptr %t634
  %t631 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t603, ptr %t631
  %t632 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t626, ptr %t632
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.142.635:
  %t636 = getelementptr ptr, ptr %t11, i32 7
  %t637 = load ptr, ptr %t636
  call void @__inc_ref(ptr %t637)
  %t638 = call ptr @__alloc(i64 32, i32 3)
  %t639 = inttoptr i64 88 to ptr
  %t640 = getelementptr ptr, ptr %t638, i32 0
  store ptr %t639, ptr %t640
  call void @__inc_ref(ptr %t637)
  %t641 = getelementptr ptr, ptr %t638, i32 1
  store ptr %t637, ptr %t641
  %t642 = getelementptr ptr, ptr %t11, i32 8
  %t643 = load ptr, ptr %t642
  call void @__inc_ref(ptr %t643)
  %t644 = getelementptr ptr, ptr %t638, i32 2
  store ptr %t643, ptr %t644
  call void @__inc_ref(ptr %t13)
  %t645 = getelementptr ptr, ptr %t638, i32 3
  store ptr %t13, ptr %t645
  %t646 = call ptr @__alloc(i64 64, i32 7)
  %t647 = inttoptr i64 143 to ptr
  %t648 = getelementptr ptr, ptr %t646, i32 0
  store ptr %t647, ptr %t648
  %t649 = getelementptr ptr, ptr %t11, i32 1
  %t650 = load ptr, ptr %t649
  call void @__inc_ref(ptr %t650)
  %t651 = getelementptr ptr, ptr %t646, i32 1
  store ptr %t650, ptr %t651
  %t652 = getelementptr ptr, ptr %t11, i32 2
  %t653 = load ptr, ptr %t652
  call void @__inc_ref(ptr %t653)
  %t654 = getelementptr ptr, ptr %t646, i32 2
  store ptr %t653, ptr %t654
  %t655 = getelementptr ptr, ptr %t11, i32 3
  %t656 = load ptr, ptr %t655
  call void @__inc_ref(ptr %t656)
  %t657 = getelementptr ptr, ptr %t646, i32 3
  store ptr %t656, ptr %t657
  %t658 = getelementptr ptr, ptr %t11, i32 4
  %t659 = load ptr, ptr %t658
  call void @__inc_ref(ptr %t659)
  %t660 = getelementptr ptr, ptr %t646, i32 4
  store ptr %t659, ptr %t660
  %t661 = getelementptr ptr, ptr %t11, i32 5
  %t662 = load ptr, ptr %t661
  call void @__inc_ref(ptr %t662)
  %t663 = getelementptr ptr, ptr %t646, i32 5
  store ptr %t662, ptr %t663
  %t664 = getelementptr ptr, ptr %t11, i32 6
  %t665 = load ptr, ptr %t664
  call void @__inc_ref(ptr %t665)
  %t666 = getelementptr ptr, ptr %t646, i32 6
  store ptr %t665, ptr %t666
  call void @__inc_ref(ptr %t637)
  %t667 = getelementptr ptr, ptr %t646, i32 7
  store ptr %t637, ptr %t667
  %t668 = getelementptr ptr, ptr %t4, i32 1
  %t669 = load ptr, ptr %t668
  call void @__free_recursive(ptr %t669)
  %t670 = getelementptr ptr, ptr %t4, i32 2
  %t671 = load ptr, ptr %t670
  call void @__free_recursive(ptr %t671)
  %t674 = inttoptr i64 280 to ptr
  %t675 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t674, ptr %t675
  %t672 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t638, ptr %t672
  %t673 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t646, ptr %t673
  call void @__free_recursive(ptr %t637)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.145.676:
  %t677 = call ptr @__alloc(i64 64, i32 7)
  %t678 = inttoptr i64 61 to ptr
  %t679 = getelementptr ptr, ptr %t677, i32 0
  store ptr %t678, ptr %t679
  %t680 = getelementptr ptr, ptr %t11, i32 2
  %t681 = load ptr, ptr %t680
  call void @__inc_ref(ptr %t681)
  %t682 = getelementptr ptr, ptr %t677, i32 1
  store ptr %t681, ptr %t682
  %t683 = getelementptr ptr, ptr %t11, i32 3
  %t684 = load ptr, ptr %t683
  call void @__inc_ref(ptr %t684)
  %t685 = getelementptr ptr, ptr %t677, i32 2
  store ptr %t684, ptr %t685
  %t686 = getelementptr ptr, ptr %t11, i32 4
  %t687 = load ptr, ptr %t686
  call void @__inc_ref(ptr %t687)
  %t688 = getelementptr ptr, ptr %t677, i32 3
  store ptr %t687, ptr %t688
  %t689 = getelementptr ptr, ptr %t11, i32 5
  %t690 = load ptr, ptr %t689
  call void @__inc_ref(ptr %t690)
  %t691 = getelementptr ptr, ptr %t677, i32 4
  store ptr %t690, ptr %t691
  %t692 = getelementptr ptr, ptr %t11, i32 6
  %t693 = load ptr, ptr %t692
  call void @__inc_ref(ptr %t693)
  %t694 = getelementptr ptr, ptr %t677, i32 5
  store ptr %t693, ptr %t694
  %t695 = getelementptr ptr, ptr %t11, i32 7
  %t696 = load ptr, ptr %t695
  call void @__inc_ref(ptr %t696)
  %t697 = getelementptr ptr, ptr %t677, i32 6
  store ptr %t696, ptr %t697
  call void @__inc_ref(ptr %t13)
  %t698 = getelementptr ptr, ptr %t677, i32 7
  store ptr %t13, ptr %t698
  %t699 = getelementptr ptr, ptr %t11, i32 1
  %t700 = load ptr, ptr %t699
  call void @__inc_ref(ptr %t700)
  %t701 = getelementptr ptr, ptr %t4, i32 1
  %t702 = load ptr, ptr %t701
  call void @__free_recursive(ptr %t702)
  %t703 = getelementptr ptr, ptr %t4, i32 2
  %t704 = load ptr, ptr %t703
  call void @__free_recursive(ptr %t704)
  %t707 = inttoptr i64 280 to ptr
  %t708 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t707, ptr %t708
  %t705 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t677, ptr %t705
  %t706 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t700, ptr %t706
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.144.709:
  %t710 = getelementptr ptr, ptr %t11, i32 7
  %t711 = load ptr, ptr %t710
  call void @__inc_ref(ptr %t711)
  %t712 = call ptr @__alloc(i64 32, i32 3)
  %t713 = inttoptr i64 88 to ptr
  %t714 = getelementptr ptr, ptr %t712, i32 0
  store ptr %t713, ptr %t714
  call void @__inc_ref(ptr %t711)
  %t715 = getelementptr ptr, ptr %t712, i32 1
  store ptr %t711, ptr %t715
  %t716 = getelementptr ptr, ptr %t11, i32 8
  %t717 = load ptr, ptr %t716
  call void @__inc_ref(ptr %t717)
  %t718 = getelementptr ptr, ptr %t712, i32 2
  store ptr %t717, ptr %t718
  call void @__inc_ref(ptr %t13)
  %t719 = getelementptr ptr, ptr %t712, i32 3
  store ptr %t13, ptr %t719
  %t720 = call ptr @__alloc(i64 64, i32 7)
  %t721 = inttoptr i64 145 to ptr
  %t722 = getelementptr ptr, ptr %t720, i32 0
  store ptr %t721, ptr %t722
  %t723 = getelementptr ptr, ptr %t11, i32 1
  %t724 = load ptr, ptr %t723
  call void @__inc_ref(ptr %t724)
  %t725 = getelementptr ptr, ptr %t720, i32 1
  store ptr %t724, ptr %t725
  %t726 = getelementptr ptr, ptr %t11, i32 2
  %t727 = load ptr, ptr %t726
  call void @__inc_ref(ptr %t727)
  %t728 = getelementptr ptr, ptr %t720, i32 2
  store ptr %t727, ptr %t728
  %t729 = getelementptr ptr, ptr %t11, i32 3
  %t730 = load ptr, ptr %t729
  call void @__inc_ref(ptr %t730)
  %t731 = getelementptr ptr, ptr %t720, i32 3
  store ptr %t730, ptr %t731
  %t732 = getelementptr ptr, ptr %t11, i32 4
  %t733 = load ptr, ptr %t732
  call void @__inc_ref(ptr %t733)
  %t734 = getelementptr ptr, ptr %t720, i32 4
  store ptr %t733, ptr %t734
  %t735 = getelementptr ptr, ptr %t11, i32 5
  %t736 = load ptr, ptr %t735
  call void @__inc_ref(ptr %t736)
  %t737 = getelementptr ptr, ptr %t720, i32 5
  store ptr %t736, ptr %t737
  %t738 = getelementptr ptr, ptr %t11, i32 6
  %t739 = load ptr, ptr %t738
  call void @__inc_ref(ptr %t739)
  %t740 = getelementptr ptr, ptr %t720, i32 6
  store ptr %t739, ptr %t740
  call void @__inc_ref(ptr %t711)
  %t741 = getelementptr ptr, ptr %t720, i32 7
  store ptr %t711, ptr %t741
  %t742 = getelementptr ptr, ptr %t4, i32 1
  %t743 = load ptr, ptr %t742
  call void @__free_recursive(ptr %t743)
  %t744 = getelementptr ptr, ptr %t4, i32 2
  %t745 = load ptr, ptr %t744
  call void @__free_recursive(ptr %t745)
  %t748 = inttoptr i64 280 to ptr
  %t749 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t748, ptr %t749
  %t746 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t712, ptr %t746
  %t747 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t720, ptr %t747
  call void @__free_recursive(ptr %t711)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.148.750:
  %t751 = getelementptr ptr, ptr %t11, i32 1
  %t752 = load ptr, ptr %t751
  call void @__inc_ref(ptr %t752)
  %t753 = call ptr @__alloc(i64 16, i32 1)
  %t754 = inttoptr i64 12 to ptr
  %t755 = getelementptr ptr, ptr %t753, i32 0
  store ptr %t754, ptr %t755
  %t756 = call ptr @__alloc(i64 32, i32 3)
  %t757 = inttoptr i64 34 to ptr
  %t758 = getelementptr ptr, ptr %t756, i32 0
  store ptr %t757, ptr %t758
  %t759 = getelementptr ptr, ptr %t11, i32 2
  %t760 = load ptr, ptr %t759
  call void @__inc_ref(ptr %t760)
  %t761 = getelementptr ptr, ptr %t756, i32 1
  store ptr %t760, ptr %t761
  %t762 = getelementptr ptr, ptr %t11, i32 3
  %t763 = load ptr, ptr %t762
  call void @__inc_ref(ptr %t763)
  %t764 = getelementptr ptr, ptr %t756, i32 2
  store ptr %t763, ptr %t764
  call void @__inc_ref(ptr %t13)
  %t765 = getelementptr ptr, ptr %t756, i32 3
  store ptr %t13, ptr %t765
  %t766 = getelementptr ptr, ptr %t753, i32 1
  store ptr %t756, ptr %t766
  %t767 = getelementptr ptr, ptr %t4, i32 1
  %t768 = load ptr, ptr %t767
  call void @__free_recursive(ptr %t768)
  %t769 = getelementptr ptr, ptr %t4, i32 2
  %t770 = load ptr, ptr %t769
  call void @__free_recursive(ptr %t770)
  %t773 = inttoptr i64 279 to ptr
  %t774 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t773, ptr %t774
  %t771 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t752, ptr %t771
  %t772 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t753, ptr %t772
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.147.775:
  %t776 = call ptr @__alloc(i64 40, i32 4)
  %t777 = inttoptr i64 93 to ptr
  %t778 = getelementptr ptr, ptr %t776, i32 0
  store ptr %t777, ptr %t778
  %t779 = getelementptr ptr, ptr %t11, i32 2
  %t780 = load ptr, ptr %t779
  call void @__inc_ref(ptr %t780)
  %t781 = getelementptr ptr, ptr %t776, i32 1
  store ptr %t780, ptr %t781
  %t782 = getelementptr ptr, ptr %t11, i32 4
  %t783 = load ptr, ptr %t782
  call void @__inc_ref(ptr %t783)
  %t784 = getelementptr ptr, ptr %t776, i32 2
  store ptr %t783, ptr %t784
  %t785 = getelementptr ptr, ptr %t11, i32 3
  %t786 = load ptr, ptr %t785
  call void @__inc_ref(ptr %t786)
  %t787 = getelementptr ptr, ptr %t776, i32 3
  store ptr %t786, ptr %t787
  %t788 = getelementptr ptr, ptr %t11, i32 5
  %t789 = load ptr, ptr %t788
  call void @__inc_ref(ptr %t789)
  %t790 = getelementptr ptr, ptr %t776, i32 4
  store ptr %t789, ptr %t790
  %t791 = call ptr @__alloc(i64 32, i32 3)
  %t792 = inttoptr i64 148 to ptr
  %t793 = getelementptr ptr, ptr %t791, i32 0
  store ptr %t792, ptr %t793
  %t794 = getelementptr ptr, ptr %t11, i32 1
  %t795 = load ptr, ptr %t794
  call void @__inc_ref(ptr %t795)
  %t796 = getelementptr ptr, ptr %t791, i32 1
  store ptr %t795, ptr %t796
  call void @__inc_ref(ptr %t13)
  %t797 = getelementptr ptr, ptr %t791, i32 2
  store ptr %t13, ptr %t797
  %t798 = getelementptr ptr, ptr %t11, i32 6
  %t799 = load ptr, ptr %t798
  call void @__inc_ref(ptr %t799)
  %t800 = getelementptr ptr, ptr %t791, i32 3
  store ptr %t799, ptr %t800
  %t801 = getelementptr ptr, ptr %t4, i32 1
  %t802 = load ptr, ptr %t801
  call void @__free_recursive(ptr %t802)
  %t803 = getelementptr ptr, ptr %t4, i32 2
  %t804 = load ptr, ptr %t803
  call void @__free_recursive(ptr %t804)
  %t807 = inttoptr i64 280 to ptr
  %t808 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t807, ptr %t808
  %t805 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t776, ptr %t805
  %t806 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t791, ptr %t806
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.146.809:
  %t810 = getelementptr ptr, ptr %t11, i32 2
  %t811 = load ptr, ptr %t810
  call void @__inc_ref(ptr %t811)
  %t812 = call ptr @__alloc(i64 40, i32 4)
  %t813 = inttoptr i64 94 to ptr
  %t814 = getelementptr ptr, ptr %t812, i32 0
  store ptr %t813, ptr %t814
  call void @__inc_ref(ptr %t811)
  %t815 = getelementptr ptr, ptr %t812, i32 1
  store ptr %t811, ptr %t815
  %t816 = getelementptr ptr, ptr %t11, i32 5
  %t817 = load ptr, ptr %t816
  call void @__inc_ref(ptr %t817)
  %t818 = getelementptr ptr, ptr %t812, i32 2
  store ptr %t817, ptr %t818
  %t819 = getelementptr ptr, ptr %t11, i32 3
  %t820 = load ptr, ptr %t819
  call void @__inc_ref(ptr %t820)
  %t821 = getelementptr ptr, ptr %t812, i32 3
  store ptr %t820, ptr %t821
  %t822 = getelementptr ptr, ptr %t13, i32 1
  %t823 = load ptr, ptr %t822
  call void @__inc_ref(ptr %t823)
  %t824 = getelementptr ptr, ptr %t812, i32 4
  store ptr %t823, ptr %t824
  %t825 = call ptr @__alloc(i64 56, i32 6)
  %t826 = inttoptr i64 147 to ptr
  %t827 = getelementptr ptr, ptr %t825, i32 0
  store ptr %t826, ptr %t827
  %t828 = getelementptr ptr, ptr %t11, i32 1
  %t829 = load ptr, ptr %t828
  call void @__inc_ref(ptr %t829)
  %t830 = getelementptr ptr, ptr %t825, i32 1
  store ptr %t829, ptr %t830
  call void @__inc_ref(ptr %t811)
  %t831 = getelementptr ptr, ptr %t825, i32 2
  store ptr %t811, ptr %t831
  %t832 = getelementptr ptr, ptr %t11, i32 4
  %t833 = load ptr, ptr %t832
  call void @__inc_ref(ptr %t833)
  %t834 = getelementptr ptr, ptr %t825, i32 3
  store ptr %t833, ptr %t834
  %t835 = getelementptr ptr, ptr %t13, i32 3
  %t836 = load ptr, ptr %t835
  call void @__inc_ref(ptr %t836)
  %t837 = getelementptr ptr, ptr %t825, i32 4
  store ptr %t836, ptr %t837
  %t838 = getelementptr ptr, ptr %t11, i32 6
  %t839 = load ptr, ptr %t838
  call void @__inc_ref(ptr %t839)
  %t840 = getelementptr ptr, ptr %t825, i32 5
  store ptr %t839, ptr %t840
  %t841 = getelementptr ptr, ptr %t13, i32 2
  %t842 = load ptr, ptr %t841
  call void @__inc_ref(ptr %t842)
  %t843 = getelementptr ptr, ptr %t825, i32 6
  store ptr %t842, ptr %t843
  %t844 = getelementptr ptr, ptr %t4, i32 1
  %t845 = load ptr, ptr %t844
  call void @__free_recursive(ptr %t845)
  %t846 = getelementptr ptr, ptr %t4, i32 2
  %t847 = load ptr, ptr %t846
  call void @__free_recursive(ptr %t847)
  %t850 = inttoptr i64 280 to ptr
  %t851 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t850, ptr %t851
  %t848 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t812, ptr %t848
  %t849 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t825, ptr %t849
  call void @__free_recursive(ptr %t811)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.151.852:
  %t853 = getelementptr ptr, ptr %t11, i32 1
  %t854 = load ptr, ptr %t853
  call void @__inc_ref(ptr %t854)
  %t855 = call ptr @__alloc(i64 16, i32 1)
  %t856 = inttoptr i64 12 to ptr
  %t857 = getelementptr ptr, ptr %t855, i32 0
  store ptr %t856, ptr %t857
  %t858 = call ptr @__alloc(i64 32, i32 3)
  %t859 = inttoptr i64 34 to ptr
  %t860 = getelementptr ptr, ptr %t858, i32 0
  store ptr %t859, ptr %t860
  %t861 = getelementptr ptr, ptr %t11, i32 2
  %t862 = load ptr, ptr %t861
  call void @__inc_ref(ptr %t862)
  %t863 = getelementptr ptr, ptr %t858, i32 1
  store ptr %t862, ptr %t863
  %t864 = getelementptr ptr, ptr %t11, i32 3
  %t865 = load ptr, ptr %t864
  call void @__inc_ref(ptr %t865)
  %t866 = getelementptr ptr, ptr %t858, i32 2
  store ptr %t865, ptr %t866
  call void @__inc_ref(ptr %t13)
  %t867 = getelementptr ptr, ptr %t858, i32 3
  store ptr %t13, ptr %t867
  %t868 = getelementptr ptr, ptr %t855, i32 1
  store ptr %t858, ptr %t868
  %t869 = getelementptr ptr, ptr %t4, i32 1
  %t870 = load ptr, ptr %t869
  call void @__free_recursive(ptr %t870)
  %t871 = getelementptr ptr, ptr %t4, i32 2
  %t872 = load ptr, ptr %t871
  call void @__free_recursive(ptr %t872)
  %t875 = inttoptr i64 279 to ptr
  %t876 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t875, ptr %t876
  %t873 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t854, ptr %t873
  %t874 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t855, ptr %t874
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.150.877:
  %t878 = call ptr @__alloc(i64 40, i32 4)
  %t879 = inttoptr i64 93 to ptr
  %t880 = getelementptr ptr, ptr %t878, i32 0
  store ptr %t879, ptr %t880
  %t881 = getelementptr ptr, ptr %t11, i32 2
  %t882 = load ptr, ptr %t881
  call void @__inc_ref(ptr %t882)
  %t883 = getelementptr ptr, ptr %t878, i32 1
  store ptr %t882, ptr %t883
  %t884 = getelementptr ptr, ptr %t11, i32 4
  %t885 = load ptr, ptr %t884
  call void @__inc_ref(ptr %t885)
  %t886 = getelementptr ptr, ptr %t878, i32 2
  store ptr %t885, ptr %t886
  %t887 = getelementptr ptr, ptr %t11, i32 3
  %t888 = load ptr, ptr %t887
  call void @__inc_ref(ptr %t888)
  %t889 = getelementptr ptr, ptr %t878, i32 3
  store ptr %t888, ptr %t889
  %t890 = getelementptr ptr, ptr %t11, i32 5
  %t891 = load ptr, ptr %t890
  call void @__inc_ref(ptr %t891)
  %t892 = getelementptr ptr, ptr %t878, i32 4
  store ptr %t891, ptr %t892
  %t893 = call ptr @__alloc(i64 32, i32 3)
  %t894 = inttoptr i64 151 to ptr
  %t895 = getelementptr ptr, ptr %t893, i32 0
  store ptr %t894, ptr %t895
  %t896 = getelementptr ptr, ptr %t11, i32 1
  %t897 = load ptr, ptr %t896
  call void @__inc_ref(ptr %t897)
  %t898 = getelementptr ptr, ptr %t893, i32 1
  store ptr %t897, ptr %t898
  call void @__inc_ref(ptr %t13)
  %t899 = getelementptr ptr, ptr %t893, i32 2
  store ptr %t13, ptr %t899
  %t900 = getelementptr ptr, ptr %t11, i32 6
  %t901 = load ptr, ptr %t900
  call void @__inc_ref(ptr %t901)
  %t902 = getelementptr ptr, ptr %t893, i32 3
  store ptr %t901, ptr %t902
  %t903 = getelementptr ptr, ptr %t4, i32 1
  %t904 = load ptr, ptr %t903
  call void @__free_recursive(ptr %t904)
  %t905 = getelementptr ptr, ptr %t4, i32 2
  %t906 = load ptr, ptr %t905
  call void @__free_recursive(ptr %t906)
  %t909 = inttoptr i64 280 to ptr
  %t910 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t909, ptr %t910
  %t907 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t878, ptr %t907
  %t908 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t893, ptr %t908
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.149.911:
  %t912 = getelementptr ptr, ptr %t11, i32 2
  %t913 = load ptr, ptr %t912
  call void @__inc_ref(ptr %t913)
  %t914 = call ptr @__alloc(i64 40, i32 4)
  %t915 = inttoptr i64 94 to ptr
  %t916 = getelementptr ptr, ptr %t914, i32 0
  store ptr %t915, ptr %t916
  call void @__inc_ref(ptr %t913)
  %t917 = getelementptr ptr, ptr %t914, i32 1
  store ptr %t913, ptr %t917
  %t918 = getelementptr ptr, ptr %t11, i32 5
  %t919 = load ptr, ptr %t918
  call void @__inc_ref(ptr %t919)
  %t920 = getelementptr ptr, ptr %t914, i32 2
  store ptr %t919, ptr %t920
  %t921 = getelementptr ptr, ptr %t11, i32 3
  %t922 = load ptr, ptr %t921
  call void @__inc_ref(ptr %t922)
  %t923 = getelementptr ptr, ptr %t914, i32 3
  store ptr %t922, ptr %t923
  %t924 = getelementptr ptr, ptr %t13, i32 1
  %t925 = load ptr, ptr %t924
  call void @__inc_ref(ptr %t925)
  %t926 = getelementptr ptr, ptr %t914, i32 4
  store ptr %t925, ptr %t926
  %t927 = call ptr @__alloc(i64 56, i32 6)
  %t928 = inttoptr i64 150 to ptr
  %t929 = getelementptr ptr, ptr %t927, i32 0
  store ptr %t928, ptr %t929
  %t930 = getelementptr ptr, ptr %t11, i32 1
  %t931 = load ptr, ptr %t930
  call void @__inc_ref(ptr %t931)
  %t932 = getelementptr ptr, ptr %t927, i32 1
  store ptr %t931, ptr %t932
  call void @__inc_ref(ptr %t913)
  %t933 = getelementptr ptr, ptr %t927, i32 2
  store ptr %t913, ptr %t933
  %t934 = getelementptr ptr, ptr %t11, i32 4
  %t935 = load ptr, ptr %t934
  call void @__inc_ref(ptr %t935)
  %t936 = getelementptr ptr, ptr %t927, i32 3
  store ptr %t935, ptr %t936
  %t937 = getelementptr ptr, ptr %t13, i32 3
  %t938 = load ptr, ptr %t937
  call void @__inc_ref(ptr %t938)
  %t939 = getelementptr ptr, ptr %t927, i32 4
  store ptr %t938, ptr %t939
  %t940 = getelementptr ptr, ptr %t11, i32 6
  %t941 = load ptr, ptr %t940
  call void @__inc_ref(ptr %t941)
  %t942 = getelementptr ptr, ptr %t927, i32 5
  store ptr %t941, ptr %t942
  %t943 = getelementptr ptr, ptr %t13, i32 2
  %t944 = load ptr, ptr %t943
  call void @__inc_ref(ptr %t944)
  %t945 = getelementptr ptr, ptr %t927, i32 6
  store ptr %t944, ptr %t945
  %t946 = getelementptr ptr, ptr %t4, i32 1
  %t947 = load ptr, ptr %t946
  call void @__free_recursive(ptr %t947)
  %t948 = getelementptr ptr, ptr %t4, i32 2
  %t949 = load ptr, ptr %t948
  call void @__free_recursive(ptr %t949)
  %t952 = inttoptr i64 280 to ptr
  %t953 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t952, ptr %t953
  %t950 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t914, ptr %t950
  %t951 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t927, ptr %t951
  call void @__free_recursive(ptr %t913)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.154.954:
  %t955 = call ptr @__alloc(i64 72, i32 8)
  %t956 = inttoptr i64 65 to ptr
  %t957 = getelementptr ptr, ptr %t955, i32 0
  store ptr %t956, ptr %t957
  %t958 = getelementptr ptr, ptr %t11, i32 2
  %t959 = load ptr, ptr %t958
  call void @__inc_ref(ptr %t959)
  %t960 = getelementptr ptr, ptr %t955, i32 1
  store ptr %t959, ptr %t960
  %t961 = getelementptr ptr, ptr %t11, i32 3
  %t962 = load ptr, ptr %t961
  call void @__inc_ref(ptr %t962)
  %t963 = getelementptr ptr, ptr %t955, i32 2
  store ptr %t962, ptr %t963
  %t964 = getelementptr ptr, ptr %t11, i32 4
  %t965 = load ptr, ptr %t964
  call void @__inc_ref(ptr %t965)
  %t966 = getelementptr ptr, ptr %t955, i32 3
  store ptr %t965, ptr %t966
  %t967 = getelementptr ptr, ptr %t11, i32 5
  %t968 = load ptr, ptr %t967
  call void @__inc_ref(ptr %t968)
  %t969 = getelementptr ptr, ptr %t955, i32 4
  store ptr %t968, ptr %t969
  %t970 = getelementptr ptr, ptr %t11, i32 6
  %t971 = load ptr, ptr %t970
  call void @__inc_ref(ptr %t971)
  %t972 = getelementptr ptr, ptr %t955, i32 5
  store ptr %t971, ptr %t972
  %t973 = getelementptr ptr, ptr %t11, i32 7
  %t974 = load ptr, ptr %t973
  call void @__inc_ref(ptr %t974)
  %t975 = getelementptr ptr, ptr %t955, i32 6
  store ptr %t974, ptr %t975
  %t976 = getelementptr ptr, ptr %t11, i32 8
  %t977 = load ptr, ptr %t976
  call void @__inc_ref(ptr %t977)
  %t978 = getelementptr ptr, ptr %t955, i32 7
  store ptr %t977, ptr %t978
  call void @__inc_ref(ptr %t13)
  %t979 = getelementptr ptr, ptr %t955, i32 8
  store ptr %t13, ptr %t979
  %t980 = getelementptr ptr, ptr %t11, i32 1
  %t981 = load ptr, ptr %t980
  call void @__inc_ref(ptr %t981)
  %t982 = getelementptr ptr, ptr %t4, i32 1
  %t983 = load ptr, ptr %t982
  call void @__free_recursive(ptr %t983)
  %t984 = getelementptr ptr, ptr %t4, i32 2
  %t985 = load ptr, ptr %t984
  call void @__free_recursive(ptr %t985)
  %t988 = inttoptr i64 280 to ptr
  %t989 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t988, ptr %t989
  %t986 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t955, ptr %t986
  %t987 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t981, ptr %t987
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.153.990:
  %t991 = getelementptr ptr, ptr %t11, i32 3
  %t992 = load ptr, ptr %t991
  call void @__inc_ref(ptr %t992)
  %t993 = call ptr @__alloc(i64 32, i32 3)
  %t994 = inttoptr i64 88 to ptr
  %t995 = getelementptr ptr, ptr %t993, i32 0
  store ptr %t994, ptr %t995
  call void @__inc_ref(ptr %t992)
  %t996 = getelementptr ptr, ptr %t993, i32 1
  store ptr %t992, ptr %t996
  %t997 = getelementptr ptr, ptr %t11, i32 9
  %t998 = load ptr, ptr %t997
  call void @__inc_ref(ptr %t998)
  %t999 = getelementptr ptr, ptr %t993, i32 2
  store ptr %t998, ptr %t999
  call void @__inc_ref(ptr %t13)
  %t1000 = getelementptr ptr, ptr %t993, i32 3
  store ptr %t13, ptr %t1000
  %t1001 = call ptr @__alloc(i64 72, i32 8)
  %t1002 = inttoptr i64 154 to ptr
  %t1003 = getelementptr ptr, ptr %t1001, i32 0
  store ptr %t1002, ptr %t1003
  %t1004 = getelementptr ptr, ptr %t11, i32 1
  %t1005 = load ptr, ptr %t1004
  call void @__inc_ref(ptr %t1005)
  %t1006 = getelementptr ptr, ptr %t1001, i32 1
  store ptr %t1005, ptr %t1006
  %t1007 = getelementptr ptr, ptr %t11, i32 2
  %t1008 = load ptr, ptr %t1007
  call void @__inc_ref(ptr %t1008)
  %t1009 = getelementptr ptr, ptr %t1001, i32 2
  store ptr %t1008, ptr %t1009
  call void @__inc_ref(ptr %t992)
  %t1010 = getelementptr ptr, ptr %t1001, i32 3
  store ptr %t992, ptr %t1010
  %t1011 = getelementptr ptr, ptr %t11, i32 4
  %t1012 = load ptr, ptr %t1011
  call void @__inc_ref(ptr %t1012)
  %t1013 = getelementptr ptr, ptr %t1001, i32 4
  store ptr %t1012, ptr %t1013
  %t1014 = getelementptr ptr, ptr %t11, i32 5
  %t1015 = load ptr, ptr %t1014
  call void @__inc_ref(ptr %t1015)
  %t1016 = getelementptr ptr, ptr %t1001, i32 5
  store ptr %t1015, ptr %t1016
  %t1017 = getelementptr ptr, ptr %t11, i32 6
  %t1018 = load ptr, ptr %t1017
  call void @__inc_ref(ptr %t1018)
  %t1019 = getelementptr ptr, ptr %t1001, i32 6
  store ptr %t1018, ptr %t1019
  %t1020 = getelementptr ptr, ptr %t11, i32 7
  %t1021 = load ptr, ptr %t1020
  call void @__inc_ref(ptr %t1021)
  %t1022 = getelementptr ptr, ptr %t1001, i32 7
  store ptr %t1021, ptr %t1022
  %t1023 = getelementptr ptr, ptr %t11, i32 8
  %t1024 = load ptr, ptr %t1023
  call void @__inc_ref(ptr %t1024)
  %t1025 = getelementptr ptr, ptr %t1001, i32 8
  store ptr %t1024, ptr %t1025
  %t1026 = getelementptr ptr, ptr %t4, i32 1
  %t1027 = load ptr, ptr %t1026
  call void @__free_recursive(ptr %t1027)
  %t1028 = getelementptr ptr, ptr %t4, i32 2
  %t1029 = load ptr, ptr %t1028
  call void @__free_recursive(ptr %t1029)
  %t1032 = inttoptr i64 280 to ptr
  %t1033 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t1032, ptr %t1033
  %t1030 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t993, ptr %t1030
  %t1031 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t1001, ptr %t1031
  call void @__free_recursive(ptr %t992)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.152.1034:
  %t1035 = getelementptr ptr, ptr %t11, i32 1
  %t1036 = load ptr, ptr %t1035
  call void @__inc_ref(ptr %t1036)
  %t1037 = getelementptr ptr, ptr %t11, i32 3
  %t1038 = load ptr, ptr %t1037
  call void @__inc_ref(ptr %t1038)
  %t1039 = getelementptr ptr, ptr %t13, i32 0
  %t1040 = load ptr, ptr %t1039
  %t1041 = ptrtoint ptr %t1040 to i64
  switch i64 %t1041, label %tco.case.default.1042 [ i64 11, label %tco.case.arm.11.1043 i64 12, label %tco.case.arm.12.1049 ]
tco.case.arm.11.1043:
  %t1044 = getelementptr ptr, ptr %t4, i32 1
  %t1045 = load ptr, ptr %t1044
  call void @__free_recursive(ptr %t1045)
  %t1047 = inttoptr i64 279 to ptr
  %t1048 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t1047, ptr %t1048
  call void @__inc_ref(ptr %t1036)
  %t1046 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t1036, ptr %t1046
  call void @__free_recursive(ptr %t1038)
  call void @__free_recursive(ptr %t1036)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.12.1049:
  %t1050 = getelementptr ptr, ptr %t13, i32 1
  %t1051 = load ptr, ptr %t1050
  call void @__inc_ref(ptr %t1051)
  %t1052 = getelementptr ptr, ptr %t1051, i32 0
  %t1053 = load ptr, ptr %t1052
  %t1054 = ptrtoint ptr %t1053 to i64
  switch i64 %t1054, label %tco.case.default.1055 [ i64 34, label %tco.case.arm.34.1056 ]
tco.case.arm.34.1056:
  %t1057 = getelementptr ptr, ptr %t1051, i32 1
  %t1058 = load ptr, ptr %t1057
  call void @__inc_ref(ptr %t1058)
  %t1059 = call ptr @__alloc(i64 24, i32 2)
  %t1060 = inttoptr i64 280 to ptr
  %t1061 = getelementptr ptr, ptr %t1059, i32 0
  store ptr %t1060, ptr %t1061
  %t1062 = call ptr @__alloc(i64 32, i32 3)
  %t1063 = inttoptr i64 33 to ptr
  %t1064 = getelementptr ptr, ptr %t1062, i32 0
  store ptr %t1063, ptr %t1064
  %t1065 = call ptr @__alloc(i64 8, i32 0)
  %t1066 = inttoptr i64 49 to ptr
  %t1067 = getelementptr ptr, ptr %t1065, i32 0
  store ptr %t1066, ptr %t1067
  %t1068 = getelementptr ptr, ptr %t1062, i32 1
  store ptr %t1065, ptr %t1068
  %t1069 = getelementptr ptr, ptr %t1038, i32 2
  %t1070 = load ptr, ptr %t1069
  call void @__inc_ref(ptr %t1070)
  %t1071 = getelementptr ptr, ptr %t1062, i32 2
  store ptr %t1070, ptr %t1071
  %t1072 = getelementptr ptr, ptr %t1038, i32 3
  %t1073 = load ptr, ptr %t1072
  call void @__inc_ref(ptr %t1073)
  %t1074 = getelementptr ptr, ptr %t1062, i32 3
  store ptr %t1073, ptr %t1074
  %t1075 = getelementptr ptr, ptr %t4, i32 1
  %t1076 = load ptr, ptr %t1075
  call void @__free_recursive(ptr %t1076)
  %t1077 = getelementptr ptr, ptr %t4, i32 2
  %t1078 = load ptr, ptr %t1077
  call void @__free_recursive(ptr %t1078)
  %t1081 = inttoptr i64 103 to ptr
  %t1082 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t1081, ptr %t1082
  %t1079 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t1062, ptr %t1079
  call void @__inc_ref(ptr %t1058)
  %t1080 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t1058, ptr %t1080
  %t1083 = getelementptr ptr, ptr %t1059, i32 1
  store ptr %t4, ptr %t1083
  %t1084 = call ptr @__alloc(i64 80, i32 9)
  %t1085 = inttoptr i64 153 to ptr
  %t1086 = getelementptr ptr, ptr %t1084, i32 0
  store ptr %t1085, ptr %t1086
  call void @__inc_ref(ptr %t1036)
  %t1087 = getelementptr ptr, ptr %t1084, i32 1
  store ptr %t1036, ptr %t1087
  %t1088 = getelementptr ptr, ptr %t11, i32 2
  %t1089 = load ptr, ptr %t1088
  call void @__inc_ref(ptr %t1089)
  %t1090 = getelementptr ptr, ptr %t1084, i32 2
  store ptr %t1089, ptr %t1090
  call void @__inc_ref(ptr %t1038)
  %t1091 = getelementptr ptr, ptr %t1084, i32 3
  store ptr %t1038, ptr %t1091
  call void @__inc_ref(ptr %t1058)
  %t1092 = getelementptr ptr, ptr %t1084, i32 4
  store ptr %t1058, ptr %t1092
  %t1093 = getelementptr ptr, ptr %t1051, i32 3
  %t1094 = load ptr, ptr %t1093
  call void @__inc_ref(ptr %t1094)
  %t1095 = getelementptr ptr, ptr %t1084, i32 5
  store ptr %t1094, ptr %t1095
  %t1096 = getelementptr ptr, ptr %t1051, i32 2
  %t1097 = load ptr, ptr %t1096
  call void @__inc_ref(ptr %t1097)
  %t1098 = getelementptr ptr, ptr %t1084, i32 6
  store ptr %t1097, ptr %t1098
  %t1099 = getelementptr ptr, ptr %t11, i32 4
  %t1100 = load ptr, ptr %t1099
  call void @__inc_ref(ptr %t1100)
  %t1101 = getelementptr ptr, ptr %t1084, i32 7
  store ptr %t1100, ptr %t1101
  %t1102 = getelementptr ptr, ptr %t11, i32 5
  %t1103 = load ptr, ptr %t1102
  call void @__inc_ref(ptr %t1103)
  %t1104 = getelementptr ptr, ptr %t1084, i32 8
  store ptr %t1103, ptr %t1104
  %t1105 = getelementptr ptr, ptr %t11, i32 6
  %t1106 = load ptr, ptr %t1105
  call void @__inc_ref(ptr %t1106)
  %t1107 = getelementptr ptr, ptr %t1084, i32 9
  store ptr %t1106, ptr %t1107
  %t1108 = getelementptr ptr, ptr %t1059, i32 2
  store ptr %t1084, ptr %t1108
  call void @__free_recursive(ptr %t1058)
  call void @__free_recursive(ptr %t1051)
  call void @__free_recursive(ptr %t1038)
  call void @__free_recursive(ptr %t1036)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t1059, ptr %t3
  br label %tco.loop.0
tco.case.default.1055:
  unreachable
tco.case.default.1042:
  unreachable
tco.case.arm.157.1109:
  %t1110 = getelementptr ptr, ptr %t11, i32 1
  %t1111 = load ptr, ptr %t1110
  call void @__inc_ref(ptr %t1111)
  %t1112 = call ptr @__alloc(i64 16, i32 1)
  %t1113 = inttoptr i64 12 to ptr
  %t1114 = getelementptr ptr, ptr %t1112, i32 0
  store ptr %t1113, ptr %t1114
  %t1115 = call ptr @__alloc(i64 32, i32 3)
  %t1116 = inttoptr i64 34 to ptr
  %t1117 = getelementptr ptr, ptr %t1115, i32 0
  store ptr %t1116, ptr %t1117
  %t1118 = getelementptr ptr, ptr %t11, i32 2
  %t1119 = load ptr, ptr %t1118
  call void @__inc_ref(ptr %t1119)
  %t1120 = getelementptr ptr, ptr %t1115, i32 1
  store ptr %t1119, ptr %t1120
  %t1121 = getelementptr ptr, ptr %t11, i32 3
  %t1122 = load ptr, ptr %t1121
  call void @__inc_ref(ptr %t1122)
  %t1123 = getelementptr ptr, ptr %t1115, i32 2
  store ptr %t1122, ptr %t1123
  call void @__inc_ref(ptr %t13)
  %t1124 = getelementptr ptr, ptr %t1115, i32 3
  store ptr %t13, ptr %t1124
  %t1125 = getelementptr ptr, ptr %t1112, i32 1
  store ptr %t1115, ptr %t1125
  %t1126 = getelementptr ptr, ptr %t4, i32 1
  %t1127 = load ptr, ptr %t1126
  call void @__free_recursive(ptr %t1127)
  %t1128 = getelementptr ptr, ptr %t4, i32 2
  %t1129 = load ptr, ptr %t1128
  call void @__free_recursive(ptr %t1129)
  %t1132 = inttoptr i64 279 to ptr
  %t1133 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t1132, ptr %t1133
  %t1130 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t1111, ptr %t1130
  %t1131 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t1112, ptr %t1131
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.156.1134:
  %t1135 = call ptr @__alloc(i64 24, i32 2)
  %t1136 = inttoptr i64 280 to ptr
  %t1137 = getelementptr ptr, ptr %t1135, i32 0
  store ptr %t1136, ptr %t1137
  %t1138 = getelementptr ptr, ptr %t11, i32 2
  %t1139 = load ptr, ptr %t1138
  call void @__inc_ref(ptr %t1139)
  %t1140 = getelementptr ptr, ptr %t11, i32 3
  %t1141 = load ptr, ptr %t1140
  call void @__inc_ref(ptr %t1141)
  %t1142 = getelementptr ptr, ptr %t4, i32 1
  %t1143 = load ptr, ptr %t1142
  call void @__free_recursive(ptr %t1143)
  %t1144 = getelementptr ptr, ptr %t4, i32 2
  %t1145 = load ptr, ptr %t1144
  call void @__free_recursive(ptr %t1145)
  %t1148 = inttoptr i64 107 to ptr
  %t1149 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t1148, ptr %t1149
  %t1146 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t1139, ptr %t1146
  %t1147 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t1141, ptr %t1147
  %t1150 = getelementptr ptr, ptr %t1135, i32 1
  store ptr %t4, ptr %t1150
  %t1151 = call ptr @__alloc(i64 32, i32 3)
  %t1152 = inttoptr i64 157 to ptr
  %t1153 = getelementptr ptr, ptr %t1151, i32 0
  store ptr %t1152, ptr %t1153
  %t1154 = getelementptr ptr, ptr %t11, i32 1
  %t1155 = load ptr, ptr %t1154
  call void @__inc_ref(ptr %t1155)
  %t1156 = getelementptr ptr, ptr %t1151, i32 1
  store ptr %t1155, ptr %t1156
  call void @__inc_ref(ptr %t13)
  %t1157 = getelementptr ptr, ptr %t1151, i32 2
  store ptr %t13, ptr %t1157
  %t1158 = getelementptr ptr, ptr %t11, i32 4
  %t1159 = load ptr, ptr %t1158
  call void @__inc_ref(ptr %t1159)
  %t1160 = getelementptr ptr, ptr %t1151, i32 3
  store ptr %t1159, ptr %t1160
  %t1161 = getelementptr ptr, ptr %t1135, i32 2
  store ptr %t1151, ptr %t1161
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t1135, ptr %t3
  br label %tco.loop.0
tco.case.arm.155.1162:
  %t1163 = getelementptr ptr, ptr %t11, i32 2
  %t1164 = load ptr, ptr %t1163
  call void @__inc_ref(ptr %t1164)
  %t1165 = call ptr @__alloc(i64 40, i32 4)
  %t1166 = inttoptr i64 94 to ptr
  %t1167 = getelementptr ptr, ptr %t1165, i32 0
  store ptr %t1166, ptr %t1167
  call void @__inc_ref(ptr %t1164)
  %t1168 = getelementptr ptr, ptr %t1165, i32 1
  store ptr %t1164, ptr %t1168
  %t1169 = getelementptr ptr, ptr %t11, i32 4
  %t1170 = load ptr, ptr %t1169
  call void @__inc_ref(ptr %t1170)
  %t1171 = getelementptr ptr, ptr %t1165, i32 2
  store ptr %t1170, ptr %t1171
  %t1172 = getelementptr ptr, ptr %t11, i32 3
  %t1173 = load ptr, ptr %t1172
  call void @__inc_ref(ptr %t1173)
  %t1174 = getelementptr ptr, ptr %t1165, i32 3
  store ptr %t1173, ptr %t1174
  %t1175 = getelementptr ptr, ptr %t13, i32 1
  %t1176 = load ptr, ptr %t1175
  call void @__inc_ref(ptr %t1176)
  %t1177 = getelementptr ptr, ptr %t1165, i32 4
  store ptr %t1176, ptr %t1177
  %t1178 = call ptr @__alloc(i64 40, i32 4)
  %t1179 = inttoptr i64 156 to ptr
  %t1180 = getelementptr ptr, ptr %t1178, i32 0
  store ptr %t1179, ptr %t1180
  %t1181 = getelementptr ptr, ptr %t11, i32 1
  %t1182 = load ptr, ptr %t1181
  call void @__inc_ref(ptr %t1182)
  %t1183 = getelementptr ptr, ptr %t1178, i32 1
  store ptr %t1182, ptr %t1183
  call void @__inc_ref(ptr %t1164)
  %t1184 = getelementptr ptr, ptr %t1178, i32 2
  store ptr %t1164, ptr %t1184
  %t1185 = getelementptr ptr, ptr %t13, i32 3
  %t1186 = load ptr, ptr %t1185
  call void @__inc_ref(ptr %t1186)
  %t1187 = getelementptr ptr, ptr %t1178, i32 3
  store ptr %t1186, ptr %t1187
  %t1188 = getelementptr ptr, ptr %t13, i32 2
  %t1189 = load ptr, ptr %t1188
  call void @__inc_ref(ptr %t1189)
  %t1190 = getelementptr ptr, ptr %t1178, i32 4
  store ptr %t1189, ptr %t1190
  %t1191 = getelementptr ptr, ptr %t4, i32 1
  %t1192 = load ptr, ptr %t1191
  call void @__free_recursive(ptr %t1192)
  %t1193 = getelementptr ptr, ptr %t4, i32 2
  %t1194 = load ptr, ptr %t1193
  call void @__free_recursive(ptr %t1194)
  %t1197 = inttoptr i64 280 to ptr
  %t1198 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t1197, ptr %t1198
  %t1195 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t1165, ptr %t1195
  %t1196 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t1178, ptr %t1196
  call void @__free_recursive(ptr %t1164)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.160.1199:
  %t1200 = call ptr @__alloc(i64 72, i32 8)
  %t1201 = inttoptr i64 64 to ptr
  %t1202 = getelementptr ptr, ptr %t1200, i32 0
  store ptr %t1201, ptr %t1202
  %t1203 = getelementptr ptr, ptr %t11, i32 2
  %t1204 = load ptr, ptr %t1203
  call void @__inc_ref(ptr %t1204)
  %t1205 = getelementptr ptr, ptr %t1200, i32 1
  store ptr %t1204, ptr %t1205
  %t1206 = getelementptr ptr, ptr %t11, i32 3
  %t1207 = load ptr, ptr %t1206
  call void @__inc_ref(ptr %t1207)
  %t1208 = getelementptr ptr, ptr %t1200, i32 2
  store ptr %t1207, ptr %t1208
  %t1209 = getelementptr ptr, ptr %t11, i32 4
  %t1210 = load ptr, ptr %t1209
  call void @__inc_ref(ptr %t1210)
  %t1211 = getelementptr ptr, ptr %t1200, i32 3
  store ptr %t1210, ptr %t1211
  %t1212 = getelementptr ptr, ptr %t11, i32 5
  %t1213 = load ptr, ptr %t1212
  call void @__inc_ref(ptr %t1213)
  %t1214 = getelementptr ptr, ptr %t1200, i32 4
  store ptr %t1213, ptr %t1214
  %t1215 = getelementptr ptr, ptr %t11, i32 6
  %t1216 = load ptr, ptr %t1215
  call void @__inc_ref(ptr %t1216)
  %t1217 = getelementptr ptr, ptr %t1200, i32 5
  store ptr %t1216, ptr %t1217
  %t1218 = getelementptr ptr, ptr %t11, i32 7
  %t1219 = load ptr, ptr %t1218
  call void @__inc_ref(ptr %t1219)
  %t1220 = getelementptr ptr, ptr %t1200, i32 6
  store ptr %t1219, ptr %t1220
  %t1221 = getelementptr ptr, ptr %t11, i32 8
  %t1222 = load ptr, ptr %t1221
  call void @__inc_ref(ptr %t1222)
  %t1223 = getelementptr ptr, ptr %t1200, i32 7
  store ptr %t1222, ptr %t1223
  call void @__inc_ref(ptr %t13)
  %t1224 = getelementptr ptr, ptr %t1200, i32 8
  store ptr %t13, ptr %t1224
  %t1225 = getelementptr ptr, ptr %t11, i32 1
  %t1226 = load ptr, ptr %t1225
  call void @__inc_ref(ptr %t1226)
  %t1227 = getelementptr ptr, ptr %t4, i32 1
  %t1228 = load ptr, ptr %t1227
  call void @__free_recursive(ptr %t1228)
  %t1229 = getelementptr ptr, ptr %t4, i32 2
  %t1230 = load ptr, ptr %t1229
  call void @__free_recursive(ptr %t1230)
  %t1233 = inttoptr i64 280 to ptr
  %t1234 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t1233, ptr %t1234
  %t1231 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t1200, ptr %t1231
  %t1232 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t1226, ptr %t1232
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.159.1235:
  %t1236 = getelementptr ptr, ptr %t11, i32 3
  %t1237 = load ptr, ptr %t1236
  call void @__inc_ref(ptr %t1237)
  %t1238 = call ptr @__alloc(i64 32, i32 3)
  %t1239 = inttoptr i64 88 to ptr
  %t1240 = getelementptr ptr, ptr %t1238, i32 0
  store ptr %t1239, ptr %t1240
  call void @__inc_ref(ptr %t1237)
  %t1241 = getelementptr ptr, ptr %t1238, i32 1
  store ptr %t1237, ptr %t1241
  %t1242 = getelementptr ptr, ptr %t11, i32 9
  %t1243 = load ptr, ptr %t1242
  call void @__inc_ref(ptr %t1243)
  %t1244 = getelementptr ptr, ptr %t1238, i32 2
  store ptr %t1243, ptr %t1244
  call void @__inc_ref(ptr %t13)
  %t1245 = getelementptr ptr, ptr %t1238, i32 3
  store ptr %t13, ptr %t1245
  %t1246 = call ptr @__alloc(i64 72, i32 8)
  %t1247 = inttoptr i64 160 to ptr
  %t1248 = getelementptr ptr, ptr %t1246, i32 0
  store ptr %t1247, ptr %t1248
  %t1249 = getelementptr ptr, ptr %t11, i32 1
  %t1250 = load ptr, ptr %t1249
  call void @__inc_ref(ptr %t1250)
  %t1251 = getelementptr ptr, ptr %t1246, i32 1
  store ptr %t1250, ptr %t1251
  %t1252 = getelementptr ptr, ptr %t11, i32 2
  %t1253 = load ptr, ptr %t1252
  call void @__inc_ref(ptr %t1253)
  %t1254 = getelementptr ptr, ptr %t1246, i32 2
  store ptr %t1253, ptr %t1254
  call void @__inc_ref(ptr %t1237)
  %t1255 = getelementptr ptr, ptr %t1246, i32 3
  store ptr %t1237, ptr %t1255
  %t1256 = getelementptr ptr, ptr %t11, i32 4
  %t1257 = load ptr, ptr %t1256
  call void @__inc_ref(ptr %t1257)
  %t1258 = getelementptr ptr, ptr %t1246, i32 4
  store ptr %t1257, ptr %t1258
  %t1259 = getelementptr ptr, ptr %t11, i32 5
  %t1260 = load ptr, ptr %t1259
  call void @__inc_ref(ptr %t1260)
  %t1261 = getelementptr ptr, ptr %t1246, i32 5
  store ptr %t1260, ptr %t1261
  %t1262 = getelementptr ptr, ptr %t11, i32 6
  %t1263 = load ptr, ptr %t1262
  call void @__inc_ref(ptr %t1263)
  %t1264 = getelementptr ptr, ptr %t1246, i32 6
  store ptr %t1263, ptr %t1264
  %t1265 = getelementptr ptr, ptr %t11, i32 7
  %t1266 = load ptr, ptr %t1265
  call void @__inc_ref(ptr %t1266)
  %t1267 = getelementptr ptr, ptr %t1246, i32 7
  store ptr %t1266, ptr %t1267
  %t1268 = getelementptr ptr, ptr %t11, i32 8
  %t1269 = load ptr, ptr %t1268
  call void @__inc_ref(ptr %t1269)
  %t1270 = getelementptr ptr, ptr %t1246, i32 8
  store ptr %t1269, ptr %t1270
  %t1271 = getelementptr ptr, ptr %t4, i32 1
  %t1272 = load ptr, ptr %t1271
  call void @__free_recursive(ptr %t1272)
  %t1273 = getelementptr ptr, ptr %t4, i32 2
  %t1274 = load ptr, ptr %t1273
  call void @__free_recursive(ptr %t1274)
  %t1277 = inttoptr i64 280 to ptr
  %t1278 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t1277, ptr %t1278
  %t1275 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t1238, ptr %t1275
  %t1276 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t1246, ptr %t1276
  call void @__free_recursive(ptr %t1237)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.158.1279:
  %t1280 = getelementptr ptr, ptr %t11, i32 1
  %t1281 = load ptr, ptr %t1280
  call void @__inc_ref(ptr %t1281)
  %t1282 = getelementptr ptr, ptr %t11, i32 3
  %t1283 = load ptr, ptr %t1282
  call void @__inc_ref(ptr %t1283)
  %t1284 = getelementptr ptr, ptr %t13, i32 0
  %t1285 = load ptr, ptr %t1284
  %t1286 = ptrtoint ptr %t1285 to i64
  switch i64 %t1286, label %tco.case.default.1287 [ i64 11, label %tco.case.arm.11.1288 i64 12, label %tco.case.arm.12.1294 ]
tco.case.arm.11.1288:
  %t1289 = getelementptr ptr, ptr %t4, i32 1
  %t1290 = load ptr, ptr %t1289
  call void @__free_recursive(ptr %t1290)
  %t1292 = inttoptr i64 279 to ptr
  %t1293 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t1292, ptr %t1293
  call void @__inc_ref(ptr %t1281)
  %t1291 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t1281, ptr %t1291
  call void @__free_recursive(ptr %t1283)
  call void @__free_recursive(ptr %t1281)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.12.1294:
  %t1295 = getelementptr ptr, ptr %t13, i32 1
  %t1296 = load ptr, ptr %t1295
  call void @__inc_ref(ptr %t1296)
  %t1297 = getelementptr ptr, ptr %t1296, i32 0
  %t1298 = load ptr, ptr %t1297
  %t1299 = ptrtoint ptr %t1298 to i64
  switch i64 %t1299, label %tco.case.default.1300 [ i64 34, label %tco.case.arm.34.1301 ]
tco.case.arm.34.1301:
  %t1302 = getelementptr ptr, ptr %t1296, i32 1
  %t1303 = load ptr, ptr %t1302
  call void @__inc_ref(ptr %t1303)
  %t1304 = call ptr @__alloc(i64 24, i32 2)
  %t1305 = inttoptr i64 280 to ptr
  %t1306 = getelementptr ptr, ptr %t1304, i32 0
  store ptr %t1305, ptr %t1306
  %t1307 = call ptr @__alloc(i64 32, i32 3)
  %t1308 = inttoptr i64 33 to ptr
  %t1309 = getelementptr ptr, ptr %t1307, i32 0
  store ptr %t1308, ptr %t1309
  %t1310 = call ptr @__alloc(i64 8, i32 0)
  %t1311 = inttoptr i64 49 to ptr
  %t1312 = getelementptr ptr, ptr %t1310, i32 0
  store ptr %t1311, ptr %t1312
  %t1313 = getelementptr ptr, ptr %t1307, i32 1
  store ptr %t1310, ptr %t1313
  %t1314 = getelementptr ptr, ptr %t1283, i32 2
  %t1315 = load ptr, ptr %t1314
  call void @__inc_ref(ptr %t1315)
  %t1316 = getelementptr ptr, ptr %t1307, i32 2
  store ptr %t1315, ptr %t1316
  %t1317 = getelementptr ptr, ptr %t1283, i32 3
  %t1318 = load ptr, ptr %t1317
  call void @__inc_ref(ptr %t1318)
  %t1319 = getelementptr ptr, ptr %t1307, i32 3
  store ptr %t1318, ptr %t1319
  %t1320 = getelementptr ptr, ptr %t4, i32 1
  %t1321 = load ptr, ptr %t1320
  call void @__free_recursive(ptr %t1321)
  %t1322 = getelementptr ptr, ptr %t4, i32 2
  %t1323 = load ptr, ptr %t1322
  call void @__free_recursive(ptr %t1323)
  %t1326 = inttoptr i64 103 to ptr
  %t1327 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t1326, ptr %t1327
  %t1324 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t1307, ptr %t1324
  call void @__inc_ref(ptr %t1303)
  %t1325 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t1303, ptr %t1325
  %t1328 = getelementptr ptr, ptr %t1304, i32 1
  store ptr %t4, ptr %t1328
  %t1329 = call ptr @__alloc(i64 80, i32 9)
  %t1330 = inttoptr i64 159 to ptr
  %t1331 = getelementptr ptr, ptr %t1329, i32 0
  store ptr %t1330, ptr %t1331
  call void @__inc_ref(ptr %t1281)
  %t1332 = getelementptr ptr, ptr %t1329, i32 1
  store ptr %t1281, ptr %t1332
  %t1333 = getelementptr ptr, ptr %t11, i32 2
  %t1334 = load ptr, ptr %t1333
  call void @__inc_ref(ptr %t1334)
  %t1335 = getelementptr ptr, ptr %t1329, i32 2
  store ptr %t1334, ptr %t1335
  call void @__inc_ref(ptr %t1283)
  %t1336 = getelementptr ptr, ptr %t1329, i32 3
  store ptr %t1283, ptr %t1336
  call void @__inc_ref(ptr %t1303)
  %t1337 = getelementptr ptr, ptr %t1329, i32 4
  store ptr %t1303, ptr %t1337
  %t1338 = getelementptr ptr, ptr %t1296, i32 3
  %t1339 = load ptr, ptr %t1338
  call void @__inc_ref(ptr %t1339)
  %t1340 = getelementptr ptr, ptr %t1329, i32 5
  store ptr %t1339, ptr %t1340
  %t1341 = getelementptr ptr, ptr %t1296, i32 2
  %t1342 = load ptr, ptr %t1341
  call void @__inc_ref(ptr %t1342)
  %t1343 = getelementptr ptr, ptr %t1329, i32 6
  store ptr %t1342, ptr %t1343
  %t1344 = getelementptr ptr, ptr %t11, i32 4
  %t1345 = load ptr, ptr %t1344
  call void @__inc_ref(ptr %t1345)
  %t1346 = getelementptr ptr, ptr %t1329, i32 7
  store ptr %t1345, ptr %t1346
  %t1347 = getelementptr ptr, ptr %t11, i32 5
  %t1348 = load ptr, ptr %t1347
  call void @__inc_ref(ptr %t1348)
  %t1349 = getelementptr ptr, ptr %t1329, i32 8
  store ptr %t1348, ptr %t1349
  %t1350 = getelementptr ptr, ptr %t11, i32 6
  %t1351 = load ptr, ptr %t1350
  call void @__inc_ref(ptr %t1351)
  %t1352 = getelementptr ptr, ptr %t1329, i32 9
  store ptr %t1351, ptr %t1352
  %t1353 = getelementptr ptr, ptr %t1304, i32 2
  store ptr %t1329, ptr %t1353
  call void @__free_recursive(ptr %t1303)
  call void @__free_recursive(ptr %t1296)
  call void @__free_recursive(ptr %t1283)
  call void @__free_recursive(ptr %t1281)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t1304, ptr %t3
  br label %tco.loop.0
tco.case.default.1300:
  unreachable
tco.case.default.1287:
  unreachable
tco.case.arm.163.1354:
  %t1355 = getelementptr ptr, ptr %t11, i32 1
  %t1356 = load ptr, ptr %t1355
  call void @__inc_ref(ptr %t1356)
  %t1357 = call ptr @__alloc(i64 16, i32 1)
  %t1358 = inttoptr i64 12 to ptr
  %t1359 = getelementptr ptr, ptr %t1357, i32 0
  store ptr %t1358, ptr %t1359
  %t1360 = call ptr @__alloc(i64 32, i32 3)
  %t1361 = inttoptr i64 34 to ptr
  %t1362 = getelementptr ptr, ptr %t1360, i32 0
  store ptr %t1361, ptr %t1362
  %t1363 = getelementptr ptr, ptr %t11, i32 2
  %t1364 = load ptr, ptr %t1363
  call void @__inc_ref(ptr %t1364)
  %t1365 = getelementptr ptr, ptr %t1360, i32 1
  store ptr %t1364, ptr %t1365
  %t1366 = getelementptr ptr, ptr %t11, i32 3
  %t1367 = load ptr, ptr %t1366
  call void @__inc_ref(ptr %t1367)
  %t1368 = getelementptr ptr, ptr %t1360, i32 2
  store ptr %t1367, ptr %t1368
  call void @__inc_ref(ptr %t13)
  %t1369 = getelementptr ptr, ptr %t1360, i32 3
  store ptr %t13, ptr %t1369
  %t1370 = getelementptr ptr, ptr %t1357, i32 1
  store ptr %t1360, ptr %t1370
  %t1371 = getelementptr ptr, ptr %t4, i32 1
  %t1372 = load ptr, ptr %t1371
  call void @__free_recursive(ptr %t1372)
  %t1373 = getelementptr ptr, ptr %t4, i32 2
  %t1374 = load ptr, ptr %t1373
  call void @__free_recursive(ptr %t1374)
  %t1377 = inttoptr i64 279 to ptr
  %t1378 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t1377, ptr %t1378
  %t1375 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t1356, ptr %t1375
  %t1376 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t1357, ptr %t1376
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.162.1379:
  %t1380 = call ptr @__alloc(i64 24, i32 2)
  %t1381 = inttoptr i64 280 to ptr
  %t1382 = getelementptr ptr, ptr %t1380, i32 0
  store ptr %t1381, ptr %t1382
  %t1383 = getelementptr ptr, ptr %t11, i32 2
  %t1384 = load ptr, ptr %t1383
  call void @__inc_ref(ptr %t1384)
  %t1385 = getelementptr ptr, ptr %t11, i32 3
  %t1386 = load ptr, ptr %t1385
  call void @__inc_ref(ptr %t1386)
  %t1387 = getelementptr ptr, ptr %t4, i32 1
  %t1388 = load ptr, ptr %t1387
  call void @__free_recursive(ptr %t1388)
  %t1389 = getelementptr ptr, ptr %t4, i32 2
  %t1390 = load ptr, ptr %t1389
  call void @__free_recursive(ptr %t1390)
  %t1393 = inttoptr i64 107 to ptr
  %t1394 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t1393, ptr %t1394
  %t1391 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t1384, ptr %t1391
  %t1392 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t1386, ptr %t1392
  %t1395 = getelementptr ptr, ptr %t1380, i32 1
  store ptr %t4, ptr %t1395
  %t1396 = call ptr @__alloc(i64 32, i32 3)
  %t1397 = inttoptr i64 163 to ptr
  %t1398 = getelementptr ptr, ptr %t1396, i32 0
  store ptr %t1397, ptr %t1398
  %t1399 = getelementptr ptr, ptr %t11, i32 1
  %t1400 = load ptr, ptr %t1399
  call void @__inc_ref(ptr %t1400)
  %t1401 = getelementptr ptr, ptr %t1396, i32 1
  store ptr %t1400, ptr %t1401
  call void @__inc_ref(ptr %t13)
  %t1402 = getelementptr ptr, ptr %t1396, i32 2
  store ptr %t13, ptr %t1402
  %t1403 = getelementptr ptr, ptr %t11, i32 4
  %t1404 = load ptr, ptr %t1403
  call void @__inc_ref(ptr %t1404)
  %t1405 = getelementptr ptr, ptr %t1396, i32 3
  store ptr %t1404, ptr %t1405
  %t1406 = getelementptr ptr, ptr %t1380, i32 2
  store ptr %t1396, ptr %t1406
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t1380, ptr %t3
  br label %tco.loop.0
tco.case.arm.161.1407:
  %t1408 = getelementptr ptr, ptr %t11, i32 2
  %t1409 = load ptr, ptr %t1408
  call void @__inc_ref(ptr %t1409)
  %t1410 = call ptr @__alloc(i64 40, i32 4)
  %t1411 = inttoptr i64 94 to ptr
  %t1412 = getelementptr ptr, ptr %t1410, i32 0
  store ptr %t1411, ptr %t1412
  call void @__inc_ref(ptr %t1409)
  %t1413 = getelementptr ptr, ptr %t1410, i32 1
  store ptr %t1409, ptr %t1413
  %t1414 = getelementptr ptr, ptr %t11, i32 4
  %t1415 = load ptr, ptr %t1414
  call void @__inc_ref(ptr %t1415)
  %t1416 = getelementptr ptr, ptr %t1410, i32 2
  store ptr %t1415, ptr %t1416
  %t1417 = getelementptr ptr, ptr %t11, i32 3
  %t1418 = load ptr, ptr %t1417
  call void @__inc_ref(ptr %t1418)
  %t1419 = getelementptr ptr, ptr %t1410, i32 3
  store ptr %t1418, ptr %t1419
  %t1420 = getelementptr ptr, ptr %t13, i32 1
  %t1421 = load ptr, ptr %t1420
  call void @__inc_ref(ptr %t1421)
  %t1422 = getelementptr ptr, ptr %t1410, i32 4
  store ptr %t1421, ptr %t1422
  %t1423 = call ptr @__alloc(i64 40, i32 4)
  %t1424 = inttoptr i64 162 to ptr
  %t1425 = getelementptr ptr, ptr %t1423, i32 0
  store ptr %t1424, ptr %t1425
  %t1426 = getelementptr ptr, ptr %t11, i32 1
  %t1427 = load ptr, ptr %t1426
  call void @__inc_ref(ptr %t1427)
  %t1428 = getelementptr ptr, ptr %t1423, i32 1
  store ptr %t1427, ptr %t1428
  call void @__inc_ref(ptr %t1409)
  %t1429 = getelementptr ptr, ptr %t1423, i32 2
  store ptr %t1409, ptr %t1429
  %t1430 = getelementptr ptr, ptr %t13, i32 3
  %t1431 = load ptr, ptr %t1430
  call void @__inc_ref(ptr %t1431)
  %t1432 = getelementptr ptr, ptr %t1423, i32 3
  store ptr %t1431, ptr %t1432
  %t1433 = getelementptr ptr, ptr %t13, i32 2
  %t1434 = load ptr, ptr %t1433
  call void @__inc_ref(ptr %t1434)
  %t1435 = getelementptr ptr, ptr %t1423, i32 4
  store ptr %t1434, ptr %t1435
  %t1436 = getelementptr ptr, ptr %t4, i32 1
  %t1437 = load ptr, ptr %t1436
  call void @__free_recursive(ptr %t1437)
  %t1438 = getelementptr ptr, ptr %t4, i32 2
  %t1439 = load ptr, ptr %t1438
  call void @__free_recursive(ptr %t1439)
  %t1442 = inttoptr i64 280 to ptr
  %t1443 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t1442, ptr %t1443
  %t1440 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t1410, ptr %t1440
  %t1441 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t1423, ptr %t1441
  call void @__free_recursive(ptr %t1409)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.166.1444:
  %t1445 = getelementptr ptr, ptr %t11, i32 1
  %t1446 = load ptr, ptr %t1445
  call void @__inc_ref(ptr %t1446)
  %t1447 = call ptr @__alloc(i64 16, i32 1)
  %t1448 = inttoptr i64 12 to ptr
  %t1449 = getelementptr ptr, ptr %t1447, i32 0
  store ptr %t1448, ptr %t1449
  %t1450 = call ptr @__alloc(i64 32, i32 3)
  %t1451 = inttoptr i64 34 to ptr
  %t1452 = getelementptr ptr, ptr %t1450, i32 0
  store ptr %t1451, ptr %t1452
  %t1453 = getelementptr ptr, ptr %t11, i32 2
  %t1454 = load ptr, ptr %t1453
  call void @__inc_ref(ptr %t1454)
  %t1455 = getelementptr ptr, ptr %t1450, i32 1
  store ptr %t1454, ptr %t1455
  %t1456 = getelementptr ptr, ptr %t11, i32 3
  %t1457 = load ptr, ptr %t1456
  call void @__inc_ref(ptr %t1457)
  %t1458 = getelementptr ptr, ptr %t1450, i32 2
  store ptr %t1457, ptr %t1458
  call void @__inc_ref(ptr %t13)
  %t1459 = getelementptr ptr, ptr %t1450, i32 3
  store ptr %t13, ptr %t1459
  %t1460 = getelementptr ptr, ptr %t1447, i32 1
  store ptr %t1450, ptr %t1460
  %t1461 = getelementptr ptr, ptr %t4, i32 1
  %t1462 = load ptr, ptr %t1461
  call void @__free_recursive(ptr %t1462)
  %t1463 = getelementptr ptr, ptr %t4, i32 2
  %t1464 = load ptr, ptr %t1463
  call void @__free_recursive(ptr %t1464)
  %t1467 = inttoptr i64 279 to ptr
  %t1468 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t1467, ptr %t1468
  %t1465 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t1446, ptr %t1465
  %t1466 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t1447, ptr %t1466
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.165.1469:
  %t1470 = call ptr @__alloc(i64 40, i32 4)
  %t1471 = inttoptr i64 93 to ptr
  %t1472 = getelementptr ptr, ptr %t1470, i32 0
  store ptr %t1471, ptr %t1472
  %t1473 = getelementptr ptr, ptr %t11, i32 2
  %t1474 = load ptr, ptr %t1473
  call void @__inc_ref(ptr %t1474)
  %t1475 = getelementptr ptr, ptr %t1470, i32 1
  store ptr %t1474, ptr %t1475
  %t1476 = getelementptr ptr, ptr %t11, i32 4
  %t1477 = load ptr, ptr %t1476
  call void @__inc_ref(ptr %t1477)
  %t1478 = getelementptr ptr, ptr %t1470, i32 2
  store ptr %t1477, ptr %t1478
  %t1479 = getelementptr ptr, ptr %t11, i32 3
  %t1480 = load ptr, ptr %t1479
  call void @__inc_ref(ptr %t1480)
  %t1481 = getelementptr ptr, ptr %t1470, i32 3
  store ptr %t1480, ptr %t1481
  %t1482 = getelementptr ptr, ptr %t11, i32 5
  %t1483 = load ptr, ptr %t1482
  call void @__inc_ref(ptr %t1483)
  %t1484 = getelementptr ptr, ptr %t1470, i32 4
  store ptr %t1483, ptr %t1484
  %t1485 = call ptr @__alloc(i64 32, i32 3)
  %t1486 = inttoptr i64 166 to ptr
  %t1487 = getelementptr ptr, ptr %t1485, i32 0
  store ptr %t1486, ptr %t1487
  %t1488 = getelementptr ptr, ptr %t11, i32 1
  %t1489 = load ptr, ptr %t1488
  call void @__inc_ref(ptr %t1489)
  %t1490 = getelementptr ptr, ptr %t1485, i32 1
  store ptr %t1489, ptr %t1490
  call void @__inc_ref(ptr %t13)
  %t1491 = getelementptr ptr, ptr %t1485, i32 2
  store ptr %t13, ptr %t1491
  %t1492 = getelementptr ptr, ptr %t11, i32 6
  %t1493 = load ptr, ptr %t1492
  call void @__inc_ref(ptr %t1493)
  %t1494 = getelementptr ptr, ptr %t1485, i32 3
  store ptr %t1493, ptr %t1494
  %t1495 = getelementptr ptr, ptr %t4, i32 1
  %t1496 = load ptr, ptr %t1495
  call void @__free_recursive(ptr %t1496)
  %t1497 = getelementptr ptr, ptr %t4, i32 2
  %t1498 = load ptr, ptr %t1497
  call void @__free_recursive(ptr %t1498)
  %t1501 = inttoptr i64 280 to ptr
  %t1502 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t1501, ptr %t1502
  %t1499 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t1470, ptr %t1499
  %t1500 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t1485, ptr %t1500
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.164.1503:
  %t1504 = getelementptr ptr, ptr %t11, i32 2
  %t1505 = load ptr, ptr %t1504
  call void @__inc_ref(ptr %t1505)
  %t1506 = call ptr @__alloc(i64 24, i32 2)
  %t1507 = inttoptr i64 280 to ptr
  %t1508 = getelementptr ptr, ptr %t1506, i32 0
  store ptr %t1507, ptr %t1508
  %t1509 = getelementptr ptr, ptr %t13, i32 1
  %t1510 = load ptr, ptr %t1509
  call void @__inc_ref(ptr %t1510)
  %t1511 = getelementptr ptr, ptr %t4, i32 1
  %t1512 = load ptr, ptr %t1511
  call void @__free_recursive(ptr %t1512)
  %t1513 = getelementptr ptr, ptr %t4, i32 2
  %t1514 = load ptr, ptr %t1513
  call void @__free_recursive(ptr %t1514)
  %t1517 = inttoptr i64 107 to ptr
  %t1518 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t1517, ptr %t1518
  call void @__inc_ref(ptr %t1505)
  %t1515 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t1505, ptr %t1515
  %t1516 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t1510, ptr %t1516
  %t1519 = getelementptr ptr, ptr %t1506, i32 1
  store ptr %t4, ptr %t1519
  %t1520 = call ptr @__alloc(i64 56, i32 6)
  %t1521 = inttoptr i64 165 to ptr
  %t1522 = getelementptr ptr, ptr %t1520, i32 0
  store ptr %t1521, ptr %t1522
  %t1523 = getelementptr ptr, ptr %t11, i32 1
  %t1524 = load ptr, ptr %t1523
  call void @__inc_ref(ptr %t1524)
  %t1525 = getelementptr ptr, ptr %t1520, i32 1
  store ptr %t1524, ptr %t1525
  call void @__inc_ref(ptr %t1505)
  %t1526 = getelementptr ptr, ptr %t1520, i32 2
  store ptr %t1505, ptr %t1526
  %t1527 = getelementptr ptr, ptr %t11, i32 3
  %t1528 = load ptr, ptr %t1527
  call void @__inc_ref(ptr %t1528)
  %t1529 = getelementptr ptr, ptr %t1520, i32 3
  store ptr %t1528, ptr %t1529
  %t1530 = getelementptr ptr, ptr %t13, i32 3
  %t1531 = load ptr, ptr %t1530
  call void @__inc_ref(ptr %t1531)
  %t1532 = getelementptr ptr, ptr %t1520, i32 4
  store ptr %t1531, ptr %t1532
  %t1533 = getelementptr ptr, ptr %t11, i32 4
  %t1534 = load ptr, ptr %t1533
  call void @__inc_ref(ptr %t1534)
  %t1535 = getelementptr ptr, ptr %t1520, i32 5
  store ptr %t1534, ptr %t1535
  %t1536 = getelementptr ptr, ptr %t13, i32 2
  %t1537 = load ptr, ptr %t1536
  call void @__inc_ref(ptr %t1537)
  %t1538 = getelementptr ptr, ptr %t1520, i32 6
  store ptr %t1537, ptr %t1538
  %t1539 = getelementptr ptr, ptr %t1506, i32 2
  store ptr %t1520, ptr %t1539
  call void @__free_recursive(ptr %t1505)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t1506, ptr %t3
  br label %tco.loop.0
tco.case.arm.168.1540:
  %t1541 = call ptr @__alloc(i64 64, i32 7)
  %t1542 = inttoptr i64 66 to ptr
  %t1543 = getelementptr ptr, ptr %t1541, i32 0
  store ptr %t1542, ptr %t1543
  %t1544 = getelementptr ptr, ptr %t11, i32 2
  %t1545 = load ptr, ptr %t1544
  call void @__inc_ref(ptr %t1545)
  %t1546 = getelementptr ptr, ptr %t1541, i32 1
  store ptr %t1545, ptr %t1546
  %t1547 = getelementptr ptr, ptr %t11, i32 3
  %t1548 = load ptr, ptr %t1547
  call void @__inc_ref(ptr %t1548)
  %t1549 = getelementptr ptr, ptr %t1541, i32 2
  store ptr %t1548, ptr %t1549
  %t1550 = getelementptr ptr, ptr %t11, i32 4
  %t1551 = load ptr, ptr %t1550
  call void @__inc_ref(ptr %t1551)
  %t1552 = getelementptr ptr, ptr %t1541, i32 3
  store ptr %t1551, ptr %t1552
  %t1553 = getelementptr ptr, ptr %t11, i32 5
  %t1554 = load ptr, ptr %t1553
  call void @__inc_ref(ptr %t1554)
  %t1555 = getelementptr ptr, ptr %t1541, i32 4
  store ptr %t1554, ptr %t1555
  %t1556 = getelementptr ptr, ptr %t11, i32 6
  %t1557 = load ptr, ptr %t1556
  call void @__inc_ref(ptr %t1557)
  %t1558 = getelementptr ptr, ptr %t1541, i32 5
  store ptr %t1557, ptr %t1558
  %t1559 = getelementptr ptr, ptr %t11, i32 7
  %t1560 = load ptr, ptr %t1559
  call void @__inc_ref(ptr %t1560)
  %t1561 = getelementptr ptr, ptr %t1541, i32 6
  store ptr %t1560, ptr %t1561
  call void @__inc_ref(ptr %t13)
  %t1562 = getelementptr ptr, ptr %t1541, i32 7
  store ptr %t13, ptr %t1562
  %t1563 = getelementptr ptr, ptr %t11, i32 1
  %t1564 = load ptr, ptr %t1563
  call void @__inc_ref(ptr %t1564)
  %t1565 = getelementptr ptr, ptr %t4, i32 1
  %t1566 = load ptr, ptr %t1565
  call void @__free_recursive(ptr %t1566)
  %t1567 = getelementptr ptr, ptr %t4, i32 2
  %t1568 = load ptr, ptr %t1567
  call void @__free_recursive(ptr %t1568)
  %t1571 = inttoptr i64 280 to ptr
  %t1572 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t1571, ptr %t1572
  %t1569 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t1541, ptr %t1569
  %t1570 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t1564, ptr %t1570
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.167.1573:
  %t1574 = getelementptr ptr, ptr %t11, i32 3
  %t1575 = load ptr, ptr %t1574
  call void @__inc_ref(ptr %t1575)
  %t1576 = getelementptr ptr, ptr %t11, i32 7
  %t1577 = load ptr, ptr %t1576
  call void @__inc_ref(ptr %t1577)
  %t1578 = call ptr @__alloc(i64 32, i32 3)
  %t1579 = inttoptr i64 88 to ptr
  %t1580 = getelementptr ptr, ptr %t1578, i32 0
  store ptr %t1579, ptr %t1580
  call void @__inc_ref(ptr %t1575)
  %t1581 = getelementptr ptr, ptr %t1578, i32 1
  store ptr %t1575, ptr %t1581
  call void @__inc_ref(ptr %t1577)
  %t1582 = getelementptr ptr, ptr %t1578, i32 2
  store ptr %t1577, ptr %t1582
  call void @__inc_ref(ptr %t13)
  %t1583 = getelementptr ptr, ptr %t1578, i32 3
  store ptr %t13, ptr %t1583
  %t1584 = call ptr @__alloc(i64 64, i32 7)
  %t1585 = inttoptr i64 168 to ptr
  %t1586 = getelementptr ptr, ptr %t1584, i32 0
  store ptr %t1585, ptr %t1586
  %t1587 = getelementptr ptr, ptr %t11, i32 1
  %t1588 = load ptr, ptr %t1587
  call void @__inc_ref(ptr %t1588)
  %t1589 = getelementptr ptr, ptr %t1584, i32 1
  store ptr %t1588, ptr %t1589
  %t1590 = getelementptr ptr, ptr %t11, i32 2
  %t1591 = load ptr, ptr %t1590
  call void @__inc_ref(ptr %t1591)
  %t1592 = getelementptr ptr, ptr %t1584, i32 2
  store ptr %t1591, ptr %t1592
  call void @__inc_ref(ptr %t1575)
  %t1593 = getelementptr ptr, ptr %t1584, i32 3
  store ptr %t1575, ptr %t1593
  %t1594 = getelementptr ptr, ptr %t11, i32 4
  %t1595 = load ptr, ptr %t1594
  call void @__inc_ref(ptr %t1595)
  %t1596 = getelementptr ptr, ptr %t1584, i32 4
  store ptr %t1595, ptr %t1596
  %t1597 = getelementptr ptr, ptr %t11, i32 5
  %t1598 = load ptr, ptr %t1597
  call void @__inc_ref(ptr %t1598)
  %t1599 = getelementptr ptr, ptr %t1584, i32 5
  store ptr %t1598, ptr %t1599
  %t1600 = getelementptr ptr, ptr %t11, i32 6
  %t1601 = load ptr, ptr %t1600
  call void @__inc_ref(ptr %t1601)
  %t1602 = getelementptr ptr, ptr %t1584, i32 6
  store ptr %t1601, ptr %t1602
  call void @__inc_ref(ptr %t1577)
  %t1603 = getelementptr ptr, ptr %t1584, i32 7
  store ptr %t1577, ptr %t1603
  %t1604 = getelementptr ptr, ptr %t4, i32 1
  %t1605 = load ptr, ptr %t1604
  call void @__free_recursive(ptr %t1605)
  %t1606 = getelementptr ptr, ptr %t4, i32 2
  %t1607 = load ptr, ptr %t1606
  call void @__free_recursive(ptr %t1607)
  %t1610 = inttoptr i64 280 to ptr
  %t1611 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t1610, ptr %t1611
  %t1608 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t1578, ptr %t1608
  %t1609 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t1584, ptr %t1609
  call void @__free_recursive(ptr %t1577)
  call void @__free_recursive(ptr %t1575)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.171.1612:
  %t1613 = getelementptr ptr, ptr %t11, i32 1
  %t1614 = load ptr, ptr %t1613
  call void @__inc_ref(ptr %t1614)
  %t1615 = call ptr @__alloc(i64 16, i32 1)
  %t1616 = inttoptr i64 12 to ptr
  %t1617 = getelementptr ptr, ptr %t1615, i32 0
  store ptr %t1616, ptr %t1617
  %t1618 = call ptr @__alloc(i64 32, i32 3)
  %t1619 = inttoptr i64 34 to ptr
  %t1620 = getelementptr ptr, ptr %t1618, i32 0
  store ptr %t1619, ptr %t1620
  %t1621 = getelementptr ptr, ptr %t11, i32 2
  %t1622 = load ptr, ptr %t1621
  call void @__inc_ref(ptr %t1622)
  %t1623 = getelementptr ptr, ptr %t1618, i32 1
  store ptr %t1622, ptr %t1623
  %t1624 = getelementptr ptr, ptr %t11, i32 3
  %t1625 = load ptr, ptr %t1624
  call void @__inc_ref(ptr %t1625)
  %t1626 = getelementptr ptr, ptr %t1618, i32 2
  store ptr %t1625, ptr %t1626
  call void @__inc_ref(ptr %t13)
  %t1627 = getelementptr ptr, ptr %t1618, i32 3
  store ptr %t13, ptr %t1627
  %t1628 = getelementptr ptr, ptr %t1615, i32 1
  store ptr %t1618, ptr %t1628
  %t1629 = getelementptr ptr, ptr %t4, i32 1
  %t1630 = load ptr, ptr %t1629
  call void @__free_recursive(ptr %t1630)
  %t1631 = getelementptr ptr, ptr %t4, i32 2
  %t1632 = load ptr, ptr %t1631
  call void @__free_recursive(ptr %t1632)
  %t1635 = inttoptr i64 279 to ptr
  %t1636 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t1635, ptr %t1636
  %t1633 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t1614, ptr %t1633
  %t1634 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t1615, ptr %t1634
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.170.1637:
  %t1638 = call ptr @__alloc(i64 40, i32 4)
  %t1639 = inttoptr i64 93 to ptr
  %t1640 = getelementptr ptr, ptr %t1638, i32 0
  store ptr %t1639, ptr %t1640
  %t1641 = getelementptr ptr, ptr %t11, i32 2
  %t1642 = load ptr, ptr %t1641
  call void @__inc_ref(ptr %t1642)
  %t1643 = getelementptr ptr, ptr %t1638, i32 1
  store ptr %t1642, ptr %t1643
  %t1644 = getelementptr ptr, ptr %t11, i32 4
  %t1645 = load ptr, ptr %t1644
  call void @__inc_ref(ptr %t1645)
  %t1646 = getelementptr ptr, ptr %t1638, i32 2
  store ptr %t1645, ptr %t1646
  %t1647 = getelementptr ptr, ptr %t11, i32 3
  %t1648 = load ptr, ptr %t1647
  call void @__inc_ref(ptr %t1648)
  %t1649 = getelementptr ptr, ptr %t1638, i32 3
  store ptr %t1648, ptr %t1649
  %t1650 = getelementptr ptr, ptr %t11, i32 5
  %t1651 = load ptr, ptr %t1650
  call void @__inc_ref(ptr %t1651)
  %t1652 = getelementptr ptr, ptr %t1638, i32 4
  store ptr %t1651, ptr %t1652
  %t1653 = call ptr @__alloc(i64 32, i32 3)
  %t1654 = inttoptr i64 171 to ptr
  %t1655 = getelementptr ptr, ptr %t1653, i32 0
  store ptr %t1654, ptr %t1655
  %t1656 = getelementptr ptr, ptr %t11, i32 1
  %t1657 = load ptr, ptr %t1656
  call void @__inc_ref(ptr %t1657)
  %t1658 = getelementptr ptr, ptr %t1653, i32 1
  store ptr %t1657, ptr %t1658
  call void @__inc_ref(ptr %t13)
  %t1659 = getelementptr ptr, ptr %t1653, i32 2
  store ptr %t13, ptr %t1659
  %t1660 = getelementptr ptr, ptr %t11, i32 6
  %t1661 = load ptr, ptr %t1660
  call void @__inc_ref(ptr %t1661)
  %t1662 = getelementptr ptr, ptr %t1653, i32 3
  store ptr %t1661, ptr %t1662
  %t1663 = getelementptr ptr, ptr %t4, i32 1
  %t1664 = load ptr, ptr %t1663
  call void @__free_recursive(ptr %t1664)
  %t1665 = getelementptr ptr, ptr %t4, i32 2
  %t1666 = load ptr, ptr %t1665
  call void @__free_recursive(ptr %t1666)
  %t1669 = inttoptr i64 280 to ptr
  %t1670 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t1669, ptr %t1670
  %t1667 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t1638, ptr %t1667
  %t1668 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t1653, ptr %t1668
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.169.1671:
  %t1672 = getelementptr ptr, ptr %t11, i32 2
  %t1673 = load ptr, ptr %t1672
  call void @__inc_ref(ptr %t1673)
  %t1674 = call ptr @__alloc(i64 24, i32 2)
  %t1675 = inttoptr i64 280 to ptr
  %t1676 = getelementptr ptr, ptr %t1674, i32 0
  store ptr %t1675, ptr %t1676
  %t1677 = getelementptr ptr, ptr %t13, i32 1
  %t1678 = load ptr, ptr %t1677
  call void @__inc_ref(ptr %t1678)
  %t1679 = getelementptr ptr, ptr %t4, i32 1
  %t1680 = load ptr, ptr %t1679
  call void @__free_recursive(ptr %t1680)
  %t1681 = getelementptr ptr, ptr %t4, i32 2
  %t1682 = load ptr, ptr %t1681
  call void @__free_recursive(ptr %t1682)
  %t1685 = inttoptr i64 107 to ptr
  %t1686 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t1685, ptr %t1686
  call void @__inc_ref(ptr %t1673)
  %t1683 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t1673, ptr %t1683
  %t1684 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t1678, ptr %t1684
  %t1687 = getelementptr ptr, ptr %t1674, i32 1
  store ptr %t4, ptr %t1687
  %t1688 = call ptr @__alloc(i64 56, i32 6)
  %t1689 = inttoptr i64 170 to ptr
  %t1690 = getelementptr ptr, ptr %t1688, i32 0
  store ptr %t1689, ptr %t1690
  %t1691 = getelementptr ptr, ptr %t11, i32 1
  %t1692 = load ptr, ptr %t1691
  call void @__inc_ref(ptr %t1692)
  %t1693 = getelementptr ptr, ptr %t1688, i32 1
  store ptr %t1692, ptr %t1693
  call void @__inc_ref(ptr %t1673)
  %t1694 = getelementptr ptr, ptr %t1688, i32 2
  store ptr %t1673, ptr %t1694
  %t1695 = getelementptr ptr, ptr %t11, i32 3
  %t1696 = load ptr, ptr %t1695
  call void @__inc_ref(ptr %t1696)
  %t1697 = getelementptr ptr, ptr %t1688, i32 3
  store ptr %t1696, ptr %t1697
  %t1698 = getelementptr ptr, ptr %t13, i32 3
  %t1699 = load ptr, ptr %t1698
  call void @__inc_ref(ptr %t1699)
  %t1700 = getelementptr ptr, ptr %t1688, i32 4
  store ptr %t1699, ptr %t1700
  %t1701 = getelementptr ptr, ptr %t11, i32 4
  %t1702 = load ptr, ptr %t1701
  call void @__inc_ref(ptr %t1702)
  %t1703 = getelementptr ptr, ptr %t1688, i32 5
  store ptr %t1702, ptr %t1703
  %t1704 = getelementptr ptr, ptr %t13, i32 2
  %t1705 = load ptr, ptr %t1704
  call void @__inc_ref(ptr %t1705)
  %t1706 = getelementptr ptr, ptr %t1688, i32 6
  store ptr %t1705, ptr %t1706
  %t1707 = getelementptr ptr, ptr %t1674, i32 2
  store ptr %t1688, ptr %t1707
  call void @__free_recursive(ptr %t1673)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t1674, ptr %t3
  br label %tco.loop.0
tco.case.arm.173.1708:
  %t1709 = call ptr @__alloc(i64 64, i32 7)
  %t1710 = inttoptr i64 67 to ptr
  %t1711 = getelementptr ptr, ptr %t1709, i32 0
  store ptr %t1710, ptr %t1711
  %t1712 = getelementptr ptr, ptr %t11, i32 2
  %t1713 = load ptr, ptr %t1712
  call void @__inc_ref(ptr %t1713)
  %t1714 = getelementptr ptr, ptr %t1709, i32 1
  store ptr %t1713, ptr %t1714
  %t1715 = getelementptr ptr, ptr %t11, i32 3
  %t1716 = load ptr, ptr %t1715
  call void @__inc_ref(ptr %t1716)
  %t1717 = getelementptr ptr, ptr %t1709, i32 2
  store ptr %t1716, ptr %t1717
  %t1718 = getelementptr ptr, ptr %t11, i32 4
  %t1719 = load ptr, ptr %t1718
  call void @__inc_ref(ptr %t1719)
  %t1720 = getelementptr ptr, ptr %t1709, i32 3
  store ptr %t1719, ptr %t1720
  %t1721 = getelementptr ptr, ptr %t11, i32 5
  %t1722 = load ptr, ptr %t1721
  call void @__inc_ref(ptr %t1722)
  %t1723 = getelementptr ptr, ptr %t1709, i32 4
  store ptr %t1722, ptr %t1723
  %t1724 = getelementptr ptr, ptr %t11, i32 6
  %t1725 = load ptr, ptr %t1724
  call void @__inc_ref(ptr %t1725)
  %t1726 = getelementptr ptr, ptr %t1709, i32 5
  store ptr %t1725, ptr %t1726
  %t1727 = getelementptr ptr, ptr %t11, i32 7
  %t1728 = load ptr, ptr %t1727
  call void @__inc_ref(ptr %t1728)
  %t1729 = getelementptr ptr, ptr %t1709, i32 6
  store ptr %t1728, ptr %t1729
  call void @__inc_ref(ptr %t13)
  %t1730 = getelementptr ptr, ptr %t1709, i32 7
  store ptr %t13, ptr %t1730
  %t1731 = getelementptr ptr, ptr %t11, i32 1
  %t1732 = load ptr, ptr %t1731
  call void @__inc_ref(ptr %t1732)
  %t1733 = getelementptr ptr, ptr %t4, i32 1
  %t1734 = load ptr, ptr %t1733
  call void @__free_recursive(ptr %t1734)
  %t1735 = getelementptr ptr, ptr %t4, i32 2
  %t1736 = load ptr, ptr %t1735
  call void @__free_recursive(ptr %t1736)
  %t1739 = inttoptr i64 280 to ptr
  %t1740 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t1739, ptr %t1740
  %t1737 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t1709, ptr %t1737
  %t1738 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t1732, ptr %t1738
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.172.1741:
  %t1742 = getelementptr ptr, ptr %t11, i32 3
  %t1743 = load ptr, ptr %t1742
  call void @__inc_ref(ptr %t1743)
  %t1744 = getelementptr ptr, ptr %t11, i32 7
  %t1745 = load ptr, ptr %t1744
  call void @__inc_ref(ptr %t1745)
  %t1746 = call ptr @__alloc(i64 32, i32 3)
  %t1747 = inttoptr i64 88 to ptr
  %t1748 = getelementptr ptr, ptr %t1746, i32 0
  store ptr %t1747, ptr %t1748
  call void @__inc_ref(ptr %t1743)
  %t1749 = getelementptr ptr, ptr %t1746, i32 1
  store ptr %t1743, ptr %t1749
  call void @__inc_ref(ptr %t1745)
  %t1750 = getelementptr ptr, ptr %t1746, i32 2
  store ptr %t1745, ptr %t1750
  call void @__inc_ref(ptr %t13)
  %t1751 = getelementptr ptr, ptr %t1746, i32 3
  store ptr %t13, ptr %t1751
  %t1752 = call ptr @__alloc(i64 64, i32 7)
  %t1753 = inttoptr i64 173 to ptr
  %t1754 = getelementptr ptr, ptr %t1752, i32 0
  store ptr %t1753, ptr %t1754
  %t1755 = getelementptr ptr, ptr %t11, i32 1
  %t1756 = load ptr, ptr %t1755
  call void @__inc_ref(ptr %t1756)
  %t1757 = getelementptr ptr, ptr %t1752, i32 1
  store ptr %t1756, ptr %t1757
  %t1758 = getelementptr ptr, ptr %t11, i32 2
  %t1759 = load ptr, ptr %t1758
  call void @__inc_ref(ptr %t1759)
  %t1760 = getelementptr ptr, ptr %t1752, i32 2
  store ptr %t1759, ptr %t1760
  call void @__inc_ref(ptr %t1743)
  %t1761 = getelementptr ptr, ptr %t1752, i32 3
  store ptr %t1743, ptr %t1761
  %t1762 = getelementptr ptr, ptr %t11, i32 4
  %t1763 = load ptr, ptr %t1762
  call void @__inc_ref(ptr %t1763)
  %t1764 = getelementptr ptr, ptr %t1752, i32 4
  store ptr %t1763, ptr %t1764
  %t1765 = getelementptr ptr, ptr %t11, i32 5
  %t1766 = load ptr, ptr %t1765
  call void @__inc_ref(ptr %t1766)
  %t1767 = getelementptr ptr, ptr %t1752, i32 5
  store ptr %t1766, ptr %t1767
  %t1768 = getelementptr ptr, ptr %t11, i32 6
  %t1769 = load ptr, ptr %t1768
  call void @__inc_ref(ptr %t1769)
  %t1770 = getelementptr ptr, ptr %t1752, i32 6
  store ptr %t1769, ptr %t1770
  call void @__inc_ref(ptr %t1745)
  %t1771 = getelementptr ptr, ptr %t1752, i32 7
  store ptr %t1745, ptr %t1771
  %t1772 = getelementptr ptr, ptr %t4, i32 1
  %t1773 = load ptr, ptr %t1772
  call void @__free_recursive(ptr %t1773)
  %t1774 = getelementptr ptr, ptr %t4, i32 2
  %t1775 = load ptr, ptr %t1774
  call void @__free_recursive(ptr %t1775)
  %t1778 = inttoptr i64 280 to ptr
  %t1779 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t1778, ptr %t1779
  %t1776 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t1746, ptr %t1776
  %t1777 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t1752, ptr %t1777
  call void @__free_recursive(ptr %t1745)
  call void @__free_recursive(ptr %t1743)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.174.1780:
  %t1781 = call ptr @__alloc(i64 24, i32 2)
  %t1782 = inttoptr i64 279 to ptr
  %t1783 = getelementptr ptr, ptr %t1781, i32 0
  store ptr %t1782, ptr %t1783
  %t1784 = getelementptr ptr, ptr %t11, i32 1
  %t1785 = load ptr, ptr %t1784
  call void @__inc_ref(ptr %t1785)
  %t1786 = getelementptr ptr, ptr %t1781, i32 1
  store ptr %t1785, ptr %t1786
  %t1787 = getelementptr ptr, ptr %t11, i32 2
  %t1788 = load ptr, ptr %t1787
  call void @__inc_ref(ptr %t1788)
  %t1789 = getelementptr ptr, ptr %t4, i32 1
  %t1790 = load ptr, ptr %t1789
  call void @__free_recursive(ptr %t1790)
  %t1792 = inttoptr i64 7 to ptr
  %t1793 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t1792, ptr %t1793
  %t1791 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t1788, ptr %t1791
  %t1794 = getelementptr ptr, ptr %t1781, i32 2
  store ptr %t4, ptr %t1794
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t1781, ptr %t3
  br label %tco.loop.0
tco.case.arm.175.1795:
  %t1796 = getelementptr ptr, ptr %t11, i32 1
  %t1797 = load ptr, ptr %t1796
  call void @__inc_ref(ptr %t1797)
  %t1799 = getelementptr ptr, ptr %t13, i32 0
  %t1800 = load ptr, ptr %t1799
  %t1801 = ptrtoint ptr %t1800 to i64
  switch i64 %t1801, label %tco.case.default.1802 [ i64 11, label %tco.case.arm.11.1803 i64 12, label %tco.case.arm.12.1820 ]
tco.case.arm.11.1803:
  %t1804 = call ptr @__alloc(i64 24, i32 2)
  %t1805 = inttoptr i64 279 to ptr
  %t1806 = getelementptr ptr, ptr %t1804, i32 0
  store ptr %t1805, ptr %t1806
  call void @__inc_ref(ptr %t1797)
  %t1807 = getelementptr ptr, ptr %t1804, i32 1
  store ptr %t1797, ptr %t1807
  %t1808 = call ptr @__alloc(i64 16, i32 1)
  %t1809 = inttoptr i64 3 to ptr
  %t1810 = getelementptr ptr, ptr %t1808, i32 0
  store ptr %t1809, ptr %t1810
  %t1811 = call ptr @__alloc(i64 16, i32 1)
  %t1812 = inttoptr i64 3150992243 to ptr
  %t1813 = getelementptr ptr, ptr %t1811, i32 0
  store ptr %t1812, ptr %t1813
  %t1814 = call ptr @__alloc(i64 8, i32 0)
  %t1815 = inttoptr i64 37 to ptr
  %t1816 = getelementptr ptr, ptr %t1814, i32 0
  store ptr %t1815, ptr %t1816
  %t1817 = getelementptr ptr, ptr %t1811, i32 1
  store ptr %t1814, ptr %t1817
  %t1818 = getelementptr ptr, ptr %t1808, i32 1
  store ptr %t1811, ptr %t1818
  %t1819 = getelementptr ptr, ptr %t1804, i32 2
  store ptr %t1808, ptr %t1819
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t1797)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t1804, ptr %t3
  br label %tco.loop.0
tco.case.arm.12.1820:
  %t1821 = call ptr @__alloc(i64 16, i32 1)
  %t1822 = inttoptr i64 4 to ptr
  %t1823 = getelementptr ptr, ptr %t1821, i32 0
  store ptr %t1822, ptr %t1823
  %t1824 = getelementptr ptr, ptr %t13, i32 1
  %t1825 = load ptr, ptr %t1824
  call void @__inc_ref(ptr %t1825)
  %t1826 = getelementptr ptr, ptr %t1821, i32 1
  store ptr %t1825, ptr %t1826
  store ptr %t1821, ptr %v_$inl177$scrut.jslot
  br label %join.1798
tco.case.default.1802:
  unreachable
join.1798:
  %t1827 = load ptr, ptr %v_$inl177$scrut.jslot
  %t1828 = getelementptr ptr, ptr %t1827, i32 0
  %t1829 = load ptr, ptr %t1828
  %t1830 = ptrtoint ptr %t1829 to i64
  switch i64 %t1830, label %tco.case.default.1831 [ i64 3, label %tco.case.arm.3.1832 i64 4, label %tco.case.arm.4.1848 ]
tco.case.arm.3.1832:
  %t1833 = call ptr @__alloc(i64 24, i32 2)
  %t1834 = inttoptr i64 279 to ptr
  %t1835 = getelementptr ptr, ptr %t1833, i32 0
  store ptr %t1834, ptr %t1835
  call void @__inc_ref(ptr %t1797)
  %t1836 = getelementptr ptr, ptr %t1833, i32 1
  store ptr %t1797, ptr %t1836
  %t1837 = call ptr @__alloc(i64 16, i32 1)
  %t1838 = inttoptr i64 3 to ptr
  %t1839 = getelementptr ptr, ptr %t1837, i32 0
  store ptr %t1838, ptr %t1839
  %t1840 = call ptr @__alloc(i64 16, i32 1)
  %t1841 = inttoptr i64 3150992243 to ptr
  %t1842 = getelementptr ptr, ptr %t1840, i32 0
  store ptr %t1841, ptr %t1842
  %t1843 = getelementptr ptr, ptr %t1827, i32 1
  %t1844 = load ptr, ptr %t1843
  call void @__inc_ref(ptr %t1844)
  %t1845 = getelementptr ptr, ptr %t1840, i32 1
  store ptr %t1844, ptr %t1845
  %t1846 = getelementptr ptr, ptr %t1837, i32 1
  store ptr %t1840, ptr %t1846
  %t1847 = getelementptr ptr, ptr %t1833, i32 2
  store ptr %t1837, ptr %t1847
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t1827)
  call void @__free_recursive(ptr %t1797)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t1833, ptr %t3
  br label %tco.loop.0
tco.case.arm.4.1848:
  %t1849 = getelementptr ptr, ptr %t1827, i32 1
  %t1850 = load ptr, ptr %t1849
  call void @__inc_ref(ptr %t1850)
  %t1851 = call ptr @__alloc(i64 24, i32 2)
  %t1852 = inttoptr i64 279 to ptr
  %t1853 = getelementptr ptr, ptr %t1851, i32 0
  store ptr %t1852, ptr %t1853
  call void @__inc_ref(ptr %t1797)
  %t1854 = getelementptr ptr, ptr %t1851, i32 1
  store ptr %t1797, ptr %t1854
  %t1855 = call ptr @__alloc(i64 16, i32 1)
  %t1856 = inttoptr i64 4 to ptr
  %t1857 = getelementptr ptr, ptr %t1855, i32 0
  store ptr %t1856, ptr %t1857
  %t1858 = call ptr @__alloc(i64 16, i32 1)
  %t1859 = inttoptr i64 40 to ptr
  %t1860 = getelementptr ptr, ptr %t1858, i32 0
  store ptr %t1859, ptr %t1860
  %t1861 = getelementptr ptr, ptr %t1850, i32 2
  %t1862 = load ptr, ptr %t1861
  call void @__inc_ref(ptr %t1862)
  %t1863 = call ptr @__showUInt32(ptr %t1862)
  %t1864 = getelementptr ptr, ptr %t1858, i32 1
  store ptr %t1863, ptr %t1864
  %t1865 = getelementptr ptr, ptr %t1855, i32 1
  store ptr %t1858, ptr %t1865
  %t1866 = getelementptr ptr, ptr %t1851, i32 2
  store ptr %t1855, ptr %t1866
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t1850)
  call void @__free_recursive(ptr %t1827)
  call void @__free_recursive(ptr %t1797)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t1851, ptr %t3
  br label %tco.loop.0
tco.case.default.1831:
  unreachable
tco.case.arm.176.1867:
  %t1868 = getelementptr ptr, ptr %t11, i32 1
  %t1869 = load ptr, ptr %t1868
  call void @__inc_ref(ptr %t1869)
  %t1871 = getelementptr ptr, ptr %t13, i32 0
  %t1872 = load ptr, ptr %t1871
  %t1873 = ptrtoint ptr %t1872 to i64
  switch i64 %t1873, label %tco.case.default.1874 [ i64 11, label %tco.case.arm.11.1875 i64 12, label %tco.case.arm.12.1892 ]
tco.case.arm.11.1875:
  %t1876 = call ptr @__alloc(i64 24, i32 2)
  %t1877 = inttoptr i64 279 to ptr
  %t1878 = getelementptr ptr, ptr %t1876, i32 0
  store ptr %t1877, ptr %t1878
  call void @__inc_ref(ptr %t1869)
  %t1879 = getelementptr ptr, ptr %t1876, i32 1
  store ptr %t1869, ptr %t1879
  %t1880 = call ptr @__alloc(i64 16, i32 1)
  %t1881 = inttoptr i64 3 to ptr
  %t1882 = getelementptr ptr, ptr %t1880, i32 0
  store ptr %t1881, ptr %t1882
  %t1883 = call ptr @__alloc(i64 16, i32 1)
  %t1884 = inttoptr i64 3150992243 to ptr
  %t1885 = getelementptr ptr, ptr %t1883, i32 0
  store ptr %t1884, ptr %t1885
  %t1886 = call ptr @__alloc(i64 8, i32 0)
  %t1887 = inttoptr i64 37 to ptr
  %t1888 = getelementptr ptr, ptr %t1886, i32 0
  store ptr %t1887, ptr %t1888
  %t1889 = getelementptr ptr, ptr %t1883, i32 1
  store ptr %t1886, ptr %t1889
  %t1890 = getelementptr ptr, ptr %t1880, i32 1
  store ptr %t1883, ptr %t1890
  %t1891 = getelementptr ptr, ptr %t1876, i32 2
  store ptr %t1880, ptr %t1891
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t1869)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t1876, ptr %t3
  br label %tco.loop.0
tco.case.arm.12.1892:
  %t1893 = call ptr @__alloc(i64 16, i32 1)
  %t1894 = inttoptr i64 4 to ptr
  %t1895 = getelementptr ptr, ptr %t1893, i32 0
  store ptr %t1894, ptr %t1895
  %t1896 = getelementptr ptr, ptr %t13, i32 1
  %t1897 = load ptr, ptr %t1896
  call void @__inc_ref(ptr %t1897)
  %t1898 = getelementptr ptr, ptr %t1893, i32 1
  store ptr %t1897, ptr %t1898
  store ptr %t1893, ptr %v_$inl179$scrut.jslot
  br label %join.1870
tco.case.default.1874:
  unreachable
join.1870:
  %t1899 = load ptr, ptr %v_$inl179$scrut.jslot
  %t1900 = getelementptr ptr, ptr %t1899, i32 0
  %t1901 = load ptr, ptr %t1900
  %t1902 = ptrtoint ptr %t1901 to i64
  switch i64 %t1902, label %tco.case.default.1903 [ i64 3, label %tco.case.arm.3.1904 i64 4, label %tco.case.arm.4.1920 ]
tco.case.arm.3.1904:
  %t1905 = call ptr @__alloc(i64 24, i32 2)
  %t1906 = inttoptr i64 279 to ptr
  %t1907 = getelementptr ptr, ptr %t1905, i32 0
  store ptr %t1906, ptr %t1907
  call void @__inc_ref(ptr %t1869)
  %t1908 = getelementptr ptr, ptr %t1905, i32 1
  store ptr %t1869, ptr %t1908
  %t1909 = call ptr @__alloc(i64 16, i32 1)
  %t1910 = inttoptr i64 3 to ptr
  %t1911 = getelementptr ptr, ptr %t1909, i32 0
  store ptr %t1910, ptr %t1911
  %t1912 = call ptr @__alloc(i64 16, i32 1)
  %t1913 = inttoptr i64 3150992243 to ptr
  %t1914 = getelementptr ptr, ptr %t1912, i32 0
  store ptr %t1913, ptr %t1914
  %t1915 = getelementptr ptr, ptr %t1899, i32 1
  %t1916 = load ptr, ptr %t1915
  call void @__inc_ref(ptr %t1916)
  %t1917 = getelementptr ptr, ptr %t1912, i32 1
  store ptr %t1916, ptr %t1917
  %t1918 = getelementptr ptr, ptr %t1909, i32 1
  store ptr %t1912, ptr %t1918
  %t1919 = getelementptr ptr, ptr %t1905, i32 2
  store ptr %t1909, ptr %t1919
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t1899)
  call void @__free_recursive(ptr %t1869)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t1905, ptr %t3
  br label %tco.loop.0
tco.case.arm.4.1920:
  %t1921 = getelementptr ptr, ptr %t1899, i32 1
  %t1922 = load ptr, ptr %t1921
  call void @__inc_ref(ptr %t1922)
  %t1923 = call ptr @__alloc(i64 24, i32 2)
  %t1924 = inttoptr i64 279 to ptr
  %t1925 = getelementptr ptr, ptr %t1923, i32 0
  store ptr %t1924, ptr %t1925
  call void @__inc_ref(ptr %t1869)
  %t1926 = getelementptr ptr, ptr %t1923, i32 1
  store ptr %t1869, ptr %t1926
  %t1927 = call ptr @__alloc(i64 16, i32 1)
  %t1928 = inttoptr i64 4 to ptr
  %t1929 = getelementptr ptr, ptr %t1927, i32 0
  store ptr %t1928, ptr %t1929
  %t1930 = call ptr @__alloc(i64 16, i32 1)
  %t1931 = inttoptr i64 40 to ptr
  %t1932 = getelementptr ptr, ptr %t1930, i32 0
  store ptr %t1931, ptr %t1932
  %t1933 = getelementptr ptr, ptr %t1922, i32 1
  %t1934 = load ptr, ptr %t1933
  call void @__inc_ref(ptr %t1934)
  %t1935 = call ptr @__showUInt32(ptr %t1934)
  %t1936 = getelementptr ptr, ptr %t1930, i32 1
  store ptr %t1935, ptr %t1936
  %t1937 = getelementptr ptr, ptr %t1927, i32 1
  store ptr %t1930, ptr %t1937
  %t1938 = getelementptr ptr, ptr %t1923, i32 2
  store ptr %t1927, ptr %t1938
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t1922)
  call void @__free_recursive(ptr %t1899)
  call void @__free_recursive(ptr %t1869)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t1923, ptr %t3
  br label %tco.loop.0
tco.case.default.1903:
  unreachable
tco.case.arm.177.1939:
  %t1940 = call ptr @__alloc(i64 32, i32 3)
  %t1941 = inttoptr i64 98 to ptr
  %t1942 = getelementptr ptr, ptr %t1940, i32 0
  store ptr %t1941, ptr %t1942
  %t1943 = getelementptr ptr, ptr %t11, i32 2
  %t1944 = load ptr, ptr %t1943
  call void @__inc_ref(ptr %t1944)
  %t1945 = getelementptr ptr, ptr %t1940, i32 1
  store ptr %t1944, ptr %t1945
  %t1946 = getelementptr ptr, ptr %t11, i32 3
  %t1947 = load ptr, ptr %t1946
  call void @__inc_ref(ptr %t1947)
  %t1948 = getelementptr ptr, ptr %t1940, i32 2
  store ptr %t1947, ptr %t1948
  call void @__inc_ref(ptr %t13)
  %t1949 = getelementptr ptr, ptr %t1940, i32 3
  store ptr %t13, ptr %t1949
  %t1950 = getelementptr ptr, ptr %t11, i32 1
  %t1951 = load ptr, ptr %t1950
  call void @__inc_ref(ptr %t1951)
  %t1952 = getelementptr ptr, ptr %t4, i32 1
  %t1953 = load ptr, ptr %t1952
  call void @__free_recursive(ptr %t1953)
  %t1954 = getelementptr ptr, ptr %t4, i32 2
  %t1955 = load ptr, ptr %t1954
  call void @__free_recursive(ptr %t1955)
  %t1958 = inttoptr i64 280 to ptr
  %t1959 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t1958, ptr %t1959
  %t1956 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t1940, ptr %t1956
  %t1957 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t1951, ptr %t1957
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.179.1960:
  %t1961 = call ptr @__alloc(i64 32, i32 3)
  %t1962 = inttoptr i64 98 to ptr
  %t1963 = getelementptr ptr, ptr %t1961, i32 0
  store ptr %t1962, ptr %t1963
  %t1964 = getelementptr ptr, ptr %t11, i32 2
  %t1965 = load ptr, ptr %t1964
  call void @__inc_ref(ptr %t1965)
  %t1966 = getelementptr ptr, ptr %t1961, i32 1
  store ptr %t1965, ptr %t1966
  %t1967 = getelementptr ptr, ptr %t11, i32 3
  %t1968 = load ptr, ptr %t1967
  call void @__inc_ref(ptr %t1968)
  %t1969 = getelementptr ptr, ptr %t1961, i32 2
  store ptr %t1968, ptr %t1969
  call void @__inc_ref(ptr %t13)
  %t1970 = getelementptr ptr, ptr %t1961, i32 3
  store ptr %t13, ptr %t1970
  %t1971 = getelementptr ptr, ptr %t11, i32 1
  %t1972 = load ptr, ptr %t1971
  call void @__inc_ref(ptr %t1972)
  %t1973 = getelementptr ptr, ptr %t4, i32 1
  %t1974 = load ptr, ptr %t1973
  call void @__free_recursive(ptr %t1974)
  %t1975 = getelementptr ptr, ptr %t4, i32 2
  %t1976 = load ptr, ptr %t1975
  call void @__free_recursive(ptr %t1976)
  %t1979 = inttoptr i64 280 to ptr
  %t1980 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t1979, ptr %t1980
  %t1977 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t1961, ptr %t1977
  %t1978 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t1972, ptr %t1978
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.178.1981:
  %t1982 = getelementptr ptr, ptr %t11, i32 2
  %t1983 = load ptr, ptr %t1982
  call void @__inc_ref(ptr %t1983)
  %t1984 = call ptr @__alloc(i64 32, i32 3)
  %t1985 = inttoptr i64 98 to ptr
  %t1986 = getelementptr ptr, ptr %t1984, i32 0
  store ptr %t1985, ptr %t1986
  call void @__inc_ref(ptr %t1983)
  %t1987 = getelementptr ptr, ptr %t1984, i32 1
  store ptr %t1983, ptr %t1987
  %t1988 = getelementptr ptr, ptr %t11, i32 4
  %t1989 = load ptr, ptr %t1988
  call void @__inc_ref(ptr %t1989)
  %t1990 = getelementptr ptr, ptr %t1984, i32 2
  store ptr %t1989, ptr %t1990
  call void @__inc_ref(ptr %t13)
  %t1991 = getelementptr ptr, ptr %t1984, i32 3
  store ptr %t13, ptr %t1991
  %t1992 = call ptr @__alloc(i64 32, i32 3)
  %t1993 = inttoptr i64 179 to ptr
  %t1994 = getelementptr ptr, ptr %t1992, i32 0
  store ptr %t1993, ptr %t1994
  %t1995 = getelementptr ptr, ptr %t11, i32 1
  %t1996 = load ptr, ptr %t1995
  call void @__inc_ref(ptr %t1996)
  %t1997 = getelementptr ptr, ptr %t1992, i32 1
  store ptr %t1996, ptr %t1997
  call void @__inc_ref(ptr %t1983)
  %t1998 = getelementptr ptr, ptr %t1992, i32 2
  store ptr %t1983, ptr %t1998
  %t1999 = getelementptr ptr, ptr %t11, i32 3
  %t2000 = load ptr, ptr %t1999
  call void @__inc_ref(ptr %t2000)
  %t2001 = getelementptr ptr, ptr %t1992, i32 3
  store ptr %t2000, ptr %t2001
  %t2002 = getelementptr ptr, ptr %t4, i32 1
  %t2003 = load ptr, ptr %t2002
  call void @__free_recursive(ptr %t2003)
  %t2004 = getelementptr ptr, ptr %t4, i32 2
  %t2005 = load ptr, ptr %t2004
  call void @__free_recursive(ptr %t2005)
  %t2008 = inttoptr i64 280 to ptr
  %t2009 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t2008, ptr %t2009
  %t2006 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t1984, ptr %t2006
  %t2007 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t1992, ptr %t2007
  call void @__free_recursive(ptr %t1983)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.182.2010:
  %t2011 = call ptr @__alloc(i64 32, i32 3)
  %t2012 = inttoptr i64 98 to ptr
  %t2013 = getelementptr ptr, ptr %t2011, i32 0
  store ptr %t2012, ptr %t2013
  %t2014 = getelementptr ptr, ptr %t11, i32 2
  %t2015 = load ptr, ptr %t2014
  call void @__inc_ref(ptr %t2015)
  %t2016 = getelementptr ptr, ptr %t2011, i32 1
  store ptr %t2015, ptr %t2016
  %t2017 = getelementptr ptr, ptr %t11, i32 3
  %t2018 = load ptr, ptr %t2017
  call void @__inc_ref(ptr %t2018)
  %t2019 = getelementptr ptr, ptr %t2011, i32 2
  store ptr %t2018, ptr %t2019
  call void @__inc_ref(ptr %t13)
  %t2020 = getelementptr ptr, ptr %t2011, i32 3
  store ptr %t13, ptr %t2020
  %t2021 = getelementptr ptr, ptr %t11, i32 1
  %t2022 = load ptr, ptr %t2021
  call void @__inc_ref(ptr %t2022)
  %t2023 = getelementptr ptr, ptr %t4, i32 1
  %t2024 = load ptr, ptr %t2023
  call void @__free_recursive(ptr %t2024)
  %t2025 = getelementptr ptr, ptr %t4, i32 2
  %t2026 = load ptr, ptr %t2025
  call void @__free_recursive(ptr %t2026)
  %t2029 = inttoptr i64 280 to ptr
  %t2030 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t2029, ptr %t2030
  %t2027 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t2011, ptr %t2027
  %t2028 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t2022, ptr %t2028
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.181.2031:
  %t2032 = getelementptr ptr, ptr %t11, i32 2
  %t2033 = load ptr, ptr %t2032
  call void @__inc_ref(ptr %t2033)
  %t2034 = call ptr @__alloc(i64 32, i32 3)
  %t2035 = inttoptr i64 98 to ptr
  %t2036 = getelementptr ptr, ptr %t2034, i32 0
  store ptr %t2035, ptr %t2036
  call void @__inc_ref(ptr %t2033)
  %t2037 = getelementptr ptr, ptr %t2034, i32 1
  store ptr %t2033, ptr %t2037
  %t2038 = getelementptr ptr, ptr %t11, i32 4
  %t2039 = load ptr, ptr %t2038
  call void @__inc_ref(ptr %t2039)
  %t2040 = getelementptr ptr, ptr %t2034, i32 2
  store ptr %t2039, ptr %t2040
  call void @__inc_ref(ptr %t13)
  %t2041 = getelementptr ptr, ptr %t2034, i32 3
  store ptr %t13, ptr %t2041
  %t2042 = call ptr @__alloc(i64 32, i32 3)
  %t2043 = inttoptr i64 182 to ptr
  %t2044 = getelementptr ptr, ptr %t2042, i32 0
  store ptr %t2043, ptr %t2044
  %t2045 = getelementptr ptr, ptr %t11, i32 1
  %t2046 = load ptr, ptr %t2045
  call void @__inc_ref(ptr %t2046)
  %t2047 = getelementptr ptr, ptr %t2042, i32 1
  store ptr %t2046, ptr %t2047
  call void @__inc_ref(ptr %t2033)
  %t2048 = getelementptr ptr, ptr %t2042, i32 2
  store ptr %t2033, ptr %t2048
  %t2049 = getelementptr ptr, ptr %t11, i32 3
  %t2050 = load ptr, ptr %t2049
  call void @__inc_ref(ptr %t2050)
  %t2051 = getelementptr ptr, ptr %t2042, i32 3
  store ptr %t2050, ptr %t2051
  %t2052 = getelementptr ptr, ptr %t4, i32 1
  %t2053 = load ptr, ptr %t2052
  call void @__free_recursive(ptr %t2053)
  %t2054 = getelementptr ptr, ptr %t4, i32 2
  %t2055 = load ptr, ptr %t2054
  call void @__free_recursive(ptr %t2055)
  %t2058 = inttoptr i64 280 to ptr
  %t2059 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t2058, ptr %t2059
  %t2056 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t2034, ptr %t2056
  %t2057 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t2042, ptr %t2057
  call void @__free_recursive(ptr %t2033)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.180.2060:
  %t2061 = getelementptr ptr, ptr %t11, i32 2
  %t2062 = load ptr, ptr %t2061
  call void @__inc_ref(ptr %t2062)
  %t2063 = call ptr @__alloc(i64 32, i32 3)
  %t2064 = inttoptr i64 98 to ptr
  %t2065 = getelementptr ptr, ptr %t2063, i32 0
  store ptr %t2064, ptr %t2065
  call void @__inc_ref(ptr %t2062)
  %t2066 = getelementptr ptr, ptr %t2063, i32 1
  store ptr %t2062, ptr %t2066
  %t2067 = getelementptr ptr, ptr %t11, i32 5
  %t2068 = load ptr, ptr %t2067
  call void @__inc_ref(ptr %t2068)
  %t2069 = getelementptr ptr, ptr %t2063, i32 2
  store ptr %t2068, ptr %t2069
  call void @__inc_ref(ptr %t13)
  %t2070 = getelementptr ptr, ptr %t2063, i32 3
  store ptr %t13, ptr %t2070
  %t2071 = call ptr @__alloc(i64 40, i32 4)
  %t2072 = inttoptr i64 181 to ptr
  %t2073 = getelementptr ptr, ptr %t2071, i32 0
  store ptr %t2072, ptr %t2073
  %t2074 = getelementptr ptr, ptr %t11, i32 1
  %t2075 = load ptr, ptr %t2074
  call void @__inc_ref(ptr %t2075)
  %t2076 = getelementptr ptr, ptr %t2071, i32 1
  store ptr %t2075, ptr %t2076
  call void @__inc_ref(ptr %t2062)
  %t2077 = getelementptr ptr, ptr %t2071, i32 2
  store ptr %t2062, ptr %t2077
  %t2078 = getelementptr ptr, ptr %t11, i32 3
  %t2079 = load ptr, ptr %t2078
  call void @__inc_ref(ptr %t2079)
  %t2080 = getelementptr ptr, ptr %t2071, i32 3
  store ptr %t2079, ptr %t2080
  %t2081 = getelementptr ptr, ptr %t11, i32 4
  %t2082 = load ptr, ptr %t2081
  call void @__inc_ref(ptr %t2082)
  %t2083 = getelementptr ptr, ptr %t2071, i32 4
  store ptr %t2082, ptr %t2083
  %t2084 = getelementptr ptr, ptr %t4, i32 1
  %t2085 = load ptr, ptr %t2084
  call void @__free_recursive(ptr %t2085)
  %t2086 = getelementptr ptr, ptr %t4, i32 2
  %t2087 = load ptr, ptr %t2086
  call void @__free_recursive(ptr %t2087)
  %t2090 = inttoptr i64 280 to ptr
  %t2091 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t2090, ptr %t2091
  %t2088 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t2063, ptr %t2088
  %t2089 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t2071, ptr %t2089
  call void @__free_recursive(ptr %t2062)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.184.2092:
  %t2093 = call ptr @__alloc(i64 32, i32 3)
  %t2094 = inttoptr i64 73 to ptr
  %t2095 = getelementptr ptr, ptr %t2093, i32 0
  store ptr %t2094, ptr %t2095
  %t2096 = getelementptr ptr, ptr %t11, i32 2
  %t2097 = load ptr, ptr %t2096
  call void @__inc_ref(ptr %t2097)
  %t2098 = getelementptr ptr, ptr %t2093, i32 1
  store ptr %t2097, ptr %t2098
  %t2099 = getelementptr ptr, ptr %t11, i32 3
  %t2100 = load ptr, ptr %t2099
  call void @__inc_ref(ptr %t2100)
  %t2101 = getelementptr ptr, ptr %t2093, i32 2
  store ptr %t2100, ptr %t2101
  call void @__inc_ref(ptr %t13)
  %t2102 = getelementptr ptr, ptr %t2093, i32 3
  store ptr %t13, ptr %t2102
  %t2103 = getelementptr ptr, ptr %t11, i32 1
  %t2104 = load ptr, ptr %t2103
  call void @__inc_ref(ptr %t2104)
  %t2105 = getelementptr ptr, ptr %t4, i32 1
  %t2106 = load ptr, ptr %t2105
  call void @__free_recursive(ptr %t2106)
  %t2107 = getelementptr ptr, ptr %t4, i32 2
  %t2108 = load ptr, ptr %t2107
  call void @__free_recursive(ptr %t2108)
  %t2111 = inttoptr i64 280 to ptr
  %t2112 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t2111, ptr %t2112
  %t2109 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t2093, ptr %t2109
  %t2110 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t2104, ptr %t2110
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.183.2113:
  %t2114 = getelementptr ptr, ptr %t11, i32 2
  %t2115 = load ptr, ptr %t2114
  call void @__inc_ref(ptr %t2115)
  %t2116 = call ptr @__alloc(i64 32, i32 3)
  %t2117 = inttoptr i64 74 to ptr
  %t2118 = getelementptr ptr, ptr %t2116, i32 0
  store ptr %t2117, ptr %t2118
  %t2119 = call ptr @__alloc(i64 16, i32 1)
  %t2120 = inttoptr i64 52 to ptr
  %t2121 = getelementptr ptr, ptr %t2119, i32 0
  store ptr %t2120, ptr %t2121
  call void @__inc_ref(ptr %t2115)
  %t2122 = getelementptr ptr, ptr %t2119, i32 1
  store ptr %t2115, ptr %t2122
  %t2123 = getelementptr ptr, ptr %t2116, i32 1
  store ptr %t2119, ptr %t2123
  %t2124 = getelementptr ptr, ptr %t11, i32 3
  %t2125 = load ptr, ptr %t2124
  call void @__inc_ref(ptr %t2125)
  %t2126 = getelementptr ptr, ptr %t2116, i32 2
  store ptr %t2125, ptr %t2126
  call void @__inc_ref(ptr %t13)
  %t2127 = getelementptr ptr, ptr %t2116, i32 3
  store ptr %t13, ptr %t2127
  %t2128 = call ptr @__alloc(i64 32, i32 3)
  %t2129 = inttoptr i64 184 to ptr
  %t2130 = getelementptr ptr, ptr %t2128, i32 0
  store ptr %t2129, ptr %t2130
  %t2131 = getelementptr ptr, ptr %t11, i32 1
  %t2132 = load ptr, ptr %t2131
  call void @__inc_ref(ptr %t2132)
  %t2133 = getelementptr ptr, ptr %t2128, i32 1
  store ptr %t2132, ptr %t2133
  call void @__inc_ref(ptr %t2115)
  %t2134 = getelementptr ptr, ptr %t2128, i32 2
  store ptr %t2115, ptr %t2134
  %t2135 = getelementptr ptr, ptr %t11, i32 4
  %t2136 = load ptr, ptr %t2135
  call void @__inc_ref(ptr %t2136)
  %t2137 = getelementptr ptr, ptr %t2128, i32 3
  store ptr %t2136, ptr %t2137
  %t2138 = getelementptr ptr, ptr %t4, i32 1
  %t2139 = load ptr, ptr %t2138
  call void @__free_recursive(ptr %t2139)
  %t2140 = getelementptr ptr, ptr %t4, i32 2
  %t2141 = load ptr, ptr %t2140
  call void @__free_recursive(ptr %t2141)
  %t2144 = inttoptr i64 280 to ptr
  %t2145 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t2144, ptr %t2145
  %t2142 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t2116, ptr %t2142
  %t2143 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t2128, ptr %t2143
  call void @__free_recursive(ptr %t2115)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.185.2146:
  %t2147 = getelementptr ptr, ptr %t11, i32 1
  %t2148 = load ptr, ptr %t2147
  call void @__inc_ref(ptr %t2148)
  %t2149 = getelementptr ptr, ptr %t11, i32 2
  %t2150 = load ptr, ptr %t2149
  call void @__inc_ref(ptr %t2150)
  call void @__inc_ref(ptr %t13)
  %t2151 = call ptr @v_$df$foldDigit$12(ptr %t2150, ptr %t13)
  %t2152 = getelementptr ptr, ptr %t4, i32 1
  %t2153 = load ptr, ptr %t2152
  call void @__free_recursive(ptr %t2153)
  %t2154 = getelementptr ptr, ptr %t4, i32 2
  %t2155 = load ptr, ptr %t2154
  call void @__free_recursive(ptr %t2155)
  %t2158 = inttoptr i64 279 to ptr
  %t2159 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t2158, ptr %t2159
  %t2156 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t2148, ptr %t2156
  %t2157 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t2151, ptr %t2157
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.186.2160:
  %t2161 = getelementptr ptr, ptr %t11, i32 1
  %t2162 = load ptr, ptr %t2161
  call void @__inc_ref(ptr %t2162)
  %t2163 = getelementptr ptr, ptr %t11, i32 2
  %t2164 = load ptr, ptr %t2163
  call void @__inc_ref(ptr %t2164)
  call void @__inc_ref(ptr %t2164)
  %t2165 = getelementptr ptr, ptr %t13, i32 2
  %t2166 = load ptr, ptr %t2165
  call void @__inc_ref(ptr %t2166)
  %t2167 = call ptr @__subUInt32(ptr %t2164, ptr %t2166)
  %t2168 = getelementptr ptr, ptr %t2167, i32 0
  %t2169 = load ptr, ptr %t2168
  %t2170 = ptrtoint ptr %t2169 to i64
  switch i64 %t2170, label %tco.case.default.2171 [ i64 3, label %tco.case.arm.3.2172 i64 4, label %tco.case.arm.4.2192 ]
tco.case.arm.3.2172:
  call void @__free_recursive(ptr %t2167)
  %t2173 = call ptr @__alloc(i64 40, i32 4)
  %t2174 = inttoptr i64 80 to ptr
  %t2175 = getelementptr ptr, ptr %t2173, i32 0
  store ptr %t2174, ptr %t2175
  call void @__inc_ref(ptr %t2164)
  %t2176 = getelementptr ptr, ptr %t2173, i32 1
  store ptr %t2164, ptr %t2176
  %t2177 = call ptr @v_lineMeasure()
  %t2178 = getelementptr ptr, ptr %t2173, i32 2
  store ptr %t2177, ptr %t2178
  %t2179 = call ptr @v_noStats()
  %t2180 = getelementptr ptr, ptr %t2173, i32 3
  store ptr %t2179, ptr %t2180
  %t2181 = getelementptr ptr, ptr %t11, i32 3
  %t2182 = load ptr, ptr %t2181
  call void @__inc_ref(ptr %t2182)
  %t2183 = getelementptr ptr, ptr %t2173, i32 4
  store ptr %t2182, ptr %t2183
  %t2184 = getelementptr ptr, ptr %t4, i32 1
  %t2185 = load ptr, ptr %t2184
  call void @__free_recursive(ptr %t2185)
  %t2186 = getelementptr ptr, ptr %t4, i32 2
  %t2187 = load ptr, ptr %t2186
  call void @__free_recursive(ptr %t2187)
  %t2190 = inttoptr i64 280 to ptr
  %t2191 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t2190, ptr %t2191
  %t2188 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t2173, ptr %t2188
  call void @__inc_ref(ptr %t2162)
  %t2189 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t2162, ptr %t2189
  call void @__free_recursive(ptr %t2164)
  call void @__free_recursive(ptr %t2162)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.4.2192:
  call void @__free_recursive(ptr %t2167)
  %t2193 = call ptr @__alloc(i64 8, i32 0)
  %t2194 = inttoptr i64 11 to ptr
  %t2195 = getelementptr ptr, ptr %t2193, i32 0
  store ptr %t2194, ptr %t2195
  %t2196 = getelementptr ptr, ptr %t4, i32 1
  %t2197 = load ptr, ptr %t2196
  call void @__free_recursive(ptr %t2197)
  %t2198 = getelementptr ptr, ptr %t4, i32 2
  %t2199 = load ptr, ptr %t2198
  call void @__free_recursive(ptr %t2199)
  %t2202 = inttoptr i64 279 to ptr
  %t2203 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t2202, ptr %t2203
  call void @__inc_ref(ptr %t2162)
  %t2200 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t2162, ptr %t2200
  %t2201 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t2193, ptr %t2201
  call void @__free_recursive(ptr %t2164)
  call void @__free_recursive(ptr %t2162)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.2171:
  unreachable
tco.case.arm.187.2204:
  %t2205 = getelementptr ptr, ptr %t11, i32 1
  %t2206 = load ptr, ptr %t2205
  call void @__inc_ref(ptr %t2206)
  %t2207 = getelementptr ptr, ptr %t11, i32 2
  %t2208 = load ptr, ptr %t2207
  call void @__inc_ref(ptr %t2208)
  call void @__inc_ref(ptr %t2208)
  %t2209 = getelementptr ptr, ptr %t13, i32 1
  %t2210 = load ptr, ptr %t2209
  call void @__inc_ref(ptr %t2210)
  %t2211 = call ptr @__subUInt32(ptr %t2208, ptr %t2210)
  %t2212 = getelementptr ptr, ptr %t2211, i32 0
  %t2213 = load ptr, ptr %t2212
  %t2214 = ptrtoint ptr %t2213 to i64
  switch i64 %t2214, label %tco.case.default.2215 [ i64 3, label %tco.case.arm.3.2216 i64 4, label %tco.case.arm.4.2236 ]
tco.case.arm.3.2216:
  call void @__free_recursive(ptr %t2211)
  %t2217 = call ptr @__alloc(i64 40, i32 4)
  %t2218 = inttoptr i64 81 to ptr
  %t2219 = getelementptr ptr, ptr %t2217, i32 0
  store ptr %t2218, ptr %t2219
  call void @__inc_ref(ptr %t2208)
  %t2220 = getelementptr ptr, ptr %t2217, i32 1
  store ptr %t2208, ptr %t2220
  %t2221 = call ptr @v_lineMeasure()
  %t2222 = getelementptr ptr, ptr %t2217, i32 2
  store ptr %t2221, ptr %t2222
  %t2223 = call ptr @v_noStats()
  %t2224 = getelementptr ptr, ptr %t2217, i32 3
  store ptr %t2223, ptr %t2224
  %t2225 = getelementptr ptr, ptr %t11, i32 3
  %t2226 = load ptr, ptr %t2225
  call void @__inc_ref(ptr %t2226)
  %t2227 = getelementptr ptr, ptr %t2217, i32 4
  store ptr %t2226, ptr %t2227
  %t2228 = getelementptr ptr, ptr %t4, i32 1
  %t2229 = load ptr, ptr %t2228
  call void @__free_recursive(ptr %t2229)
  %t2230 = getelementptr ptr, ptr %t4, i32 2
  %t2231 = load ptr, ptr %t2230
  call void @__free_recursive(ptr %t2231)
  %t2234 = inttoptr i64 280 to ptr
  %t2235 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t2234, ptr %t2235
  %t2232 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t2217, ptr %t2232
  call void @__inc_ref(ptr %t2206)
  %t2233 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t2206, ptr %t2233
  call void @__free_recursive(ptr %t2208)
  call void @__free_recursive(ptr %t2206)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.4.2236:
  call void @__free_recursive(ptr %t2211)
  %t2237 = call ptr @__alloc(i64 8, i32 0)
  %t2238 = inttoptr i64 11 to ptr
  %t2239 = getelementptr ptr, ptr %t2237, i32 0
  store ptr %t2238, ptr %t2239
  %t2240 = getelementptr ptr, ptr %t4, i32 1
  %t2241 = load ptr, ptr %t2240
  call void @__free_recursive(ptr %t2241)
  %t2242 = getelementptr ptr, ptr %t4, i32 2
  %t2243 = load ptr, ptr %t2242
  call void @__free_recursive(ptr %t2243)
  %t2246 = inttoptr i64 279 to ptr
  %t2247 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t2246, ptr %t2247
  call void @__inc_ref(ptr %t2206)
  %t2244 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t2206, ptr %t2244
  %t2245 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t2237, ptr %t2245
  call void @__free_recursive(ptr %t2208)
  call void @__free_recursive(ptr %t2206)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.2215:
  unreachable
tco.case.arm.189.2248:
  %t2249 = getelementptr ptr, ptr %t11, i32 1
  %t2250 = load ptr, ptr %t2249
  call void @__inc_ref(ptr %t2250)
  %t2251 = getelementptr ptr, ptr %t11, i32 3
  %t2252 = load ptr, ptr %t2251
  call void @__inc_ref(ptr %t2252)
  %t2253 = getelementptr ptr, ptr %t11, i32 4
  %t2254 = load ptr, ptr %t2253
  call void @__inc_ref(ptr %t2254)
  %t2255 = getelementptr ptr, ptr %t11, i32 2
  %t2256 = load ptr, ptr %t2255
  call void @__inc_ref(ptr %t2256)
  %t2257 = getelementptr ptr, ptr %t13, i32 2
  %t2258 = load ptr, ptr %t2257
  call void @__inc_ref(ptr %t2258)
  %t2259 = call ptr @__subUInt32(ptr %t2256, ptr %t2258)
  %t2260 = getelementptr ptr, ptr %t2259, i32 0
  %t2261 = load ptr, ptr %t2260
  %t2262 = ptrtoint ptr %t2261 to i64
  switch i64 %t2262, label %tco.case.default.2263 [ i64 3, label %tco.case.arm.3.2264 i64 4, label %tco.case.arm.4.2290 ]
tco.case.arm.3.2264:
  call void @__free_recursive(ptr %t2259)
  %t2265 = call ptr @__alloc(i64 32, i32 3)
  %t2266 = inttoptr i64 34 to ptr
  %t2267 = getelementptr ptr, ptr %t2265, i32 0
  store ptr %t2266, ptr %t2267
  %t2268 = call ptr @__alloc(i64 8, i32 0)
  %t2269 = inttoptr i64 11 to ptr
  %t2270 = getelementptr ptr, ptr %t2268, i32 0
  store ptr %t2269, ptr %t2270
  %t2271 = getelementptr ptr, ptr %t2265, i32 1
  store ptr %t2268, ptr %t2271
  call void @__inc_ref(ptr %t2252)
  %t2272 = getelementptr ptr, ptr %t2265, i32 2
  store ptr %t2252, ptr %t2272
  %t2273 = call ptr @__alloc(i64 16, i32 1)
  %t2274 = inttoptr i64 12 to ptr
  %t2275 = getelementptr ptr, ptr %t2273, i32 0
  store ptr %t2274, ptr %t2275
  %t2276 = call ptr @__alloc(i64 16, i32 1)
  %t2277 = inttoptr i64 24 to ptr
  %t2278 = getelementptr ptr, ptr %t2276, i32 0
  store ptr %t2277, ptr %t2278
  call void @__inc_ref(ptr %t2254)
  %t2279 = getelementptr ptr, ptr %t2276, i32 1
  store ptr %t2254, ptr %t2279
  %t2280 = getelementptr ptr, ptr %t2273, i32 1
  store ptr %t2276, ptr %t2280
  %t2281 = getelementptr ptr, ptr %t2265, i32 3
  store ptr %t2273, ptr %t2281
  %t2282 = getelementptr ptr, ptr %t4, i32 1
  %t2283 = load ptr, ptr %t2282
  call void @__free_recursive(ptr %t2283)
  %t2284 = getelementptr ptr, ptr %t4, i32 2
  %t2285 = load ptr, ptr %t2284
  call void @__free_recursive(ptr %t2285)
  %t2288 = inttoptr i64 279 to ptr
  %t2289 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t2288, ptr %t2289
  call void @__inc_ref(ptr %t2250)
  %t2286 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t2250, ptr %t2286
  %t2287 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t2265, ptr %t2287
  call void @__free_recursive(ptr %t2254)
  call void @__free_recursive(ptr %t2252)
  call void @__free_recursive(ptr %t2250)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.4.2290:
  call void @__free_recursive(ptr %t2259)
  %t2291 = call ptr @__alloc(i64 32, i32 3)
  %t2292 = inttoptr i64 34 to ptr
  %t2293 = getelementptr ptr, ptr %t2291, i32 0
  store ptr %t2292, ptr %t2293
  %t2294 = call ptr @__alloc(i64 16, i32 1)
  %t2295 = inttoptr i64 12 to ptr
  %t2296 = getelementptr ptr, ptr %t2294, i32 0
  store ptr %t2295, ptr %t2296
  %t2297 = call ptr @__alloc(i64 16, i32 1)
  %t2298 = inttoptr i64 24 to ptr
  %t2299 = getelementptr ptr, ptr %t2297, i32 0
  store ptr %t2298, ptr %t2299
  call void @__inc_ref(ptr %t2252)
  %t2300 = getelementptr ptr, ptr %t2297, i32 1
  store ptr %t2252, ptr %t2300
  %t2301 = getelementptr ptr, ptr %t2294, i32 1
  store ptr %t2297, ptr %t2301
  %t2302 = getelementptr ptr, ptr %t2291, i32 1
  store ptr %t2294, ptr %t2302
  call void @__inc_ref(ptr %t2254)
  %t2303 = getelementptr ptr, ptr %t2291, i32 2
  store ptr %t2254, ptr %t2303
  %t2304 = call ptr @__alloc(i64 8, i32 0)
  %t2305 = inttoptr i64 11 to ptr
  %t2306 = getelementptr ptr, ptr %t2304, i32 0
  store ptr %t2305, ptr %t2306
  %t2307 = getelementptr ptr, ptr %t2291, i32 3
  store ptr %t2304, ptr %t2307
  %t2308 = getelementptr ptr, ptr %t4, i32 1
  %t2309 = load ptr, ptr %t2308
  call void @__free_recursive(ptr %t2309)
  %t2310 = getelementptr ptr, ptr %t4, i32 2
  %t2311 = load ptr, ptr %t2310
  call void @__free_recursive(ptr %t2311)
  %t2314 = inttoptr i64 279 to ptr
  %t2315 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t2314, ptr %t2315
  call void @__inc_ref(ptr %t2250)
  %t2312 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t2250, ptr %t2312
  %t2313 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t2291, ptr %t2313
  call void @__free_recursive(ptr %t2254)
  call void @__free_recursive(ptr %t2252)
  call void @__free_recursive(ptr %t2250)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.2263:
  unreachable
tco.case.arm.188.2316:
  %t2317 = call ptr @__alloc(i64 32, i32 3)
  %t2318 = inttoptr i64 88 to ptr
  %t2319 = getelementptr ptr, ptr %t2317, i32 0
  store ptr %t2318, ptr %t2319
  %t2320 = getelementptr ptr, ptr %t11, i32 6
  %t2321 = load ptr, ptr %t2320
  call void @__inc_ref(ptr %t2321)
  %t2322 = getelementptr ptr, ptr %t2317, i32 1
  store ptr %t2321, ptr %t2322
  %t2323 = getelementptr ptr, ptr %t11, i32 4
  %t2324 = load ptr, ptr %t2323
  call void @__inc_ref(ptr %t2324)
  %t2325 = getelementptr ptr, ptr %t2317, i32 2
  store ptr %t2324, ptr %t2325
  call void @__inc_ref(ptr %t13)
  %t2326 = getelementptr ptr, ptr %t2317, i32 3
  store ptr %t13, ptr %t2326
  %t2327 = call ptr @__alloc(i64 40, i32 4)
  %t2328 = inttoptr i64 189 to ptr
  %t2329 = getelementptr ptr, ptr %t2327, i32 0
  store ptr %t2328, ptr %t2329
  %t2330 = getelementptr ptr, ptr %t11, i32 1
  %t2331 = load ptr, ptr %t2330
  call void @__inc_ref(ptr %t2331)
  %t2332 = getelementptr ptr, ptr %t2327, i32 1
  store ptr %t2331, ptr %t2332
  %t2333 = getelementptr ptr, ptr %t11, i32 2
  %t2334 = load ptr, ptr %t2333
  call void @__inc_ref(ptr %t2334)
  %t2335 = getelementptr ptr, ptr %t2327, i32 2
  store ptr %t2334, ptr %t2335
  %t2336 = getelementptr ptr, ptr %t11, i32 3
  %t2337 = load ptr, ptr %t2336
  call void @__inc_ref(ptr %t2337)
  %t2338 = getelementptr ptr, ptr %t2327, i32 3
  store ptr %t2337, ptr %t2338
  %t2339 = getelementptr ptr, ptr %t11, i32 5
  %t2340 = load ptr, ptr %t2339
  call void @__inc_ref(ptr %t2340)
  %t2341 = getelementptr ptr, ptr %t2327, i32 4
  store ptr %t2340, ptr %t2341
  %t2342 = getelementptr ptr, ptr %t4, i32 1
  %t2343 = load ptr, ptr %t2342
  call void @__free_recursive(ptr %t2343)
  %t2344 = getelementptr ptr, ptr %t4, i32 2
  %t2345 = load ptr, ptr %t2344
  call void @__free_recursive(ptr %t2345)
  %t2348 = inttoptr i64 280 to ptr
  %t2349 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t2348, ptr %t2349
  %t2346 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t2317, ptr %t2346
  %t2347 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t2327, ptr %t2347
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.191.2350:
  %t2351 = call ptr @__alloc(i64 56, i32 6)
  %t2352 = inttoptr i64 58 to ptr
  %t2353 = getelementptr ptr, ptr %t2351, i32 0
  store ptr %t2352, ptr %t2353
  %t2354 = getelementptr ptr, ptr %t11, i32 2
  %t2355 = load ptr, ptr %t2354
  call void @__inc_ref(ptr %t2355)
  %t2356 = getelementptr ptr, ptr %t2351, i32 1
  store ptr %t2355, ptr %t2356
  %t2357 = getelementptr ptr, ptr %t11, i32 3
  %t2358 = load ptr, ptr %t2357
  call void @__inc_ref(ptr %t2358)
  %t2359 = getelementptr ptr, ptr %t2351, i32 2
  store ptr %t2358, ptr %t2359
  %t2360 = getelementptr ptr, ptr %t11, i32 4
  %t2361 = load ptr, ptr %t2360
  call void @__inc_ref(ptr %t2361)
  %t2362 = getelementptr ptr, ptr %t2351, i32 3
  store ptr %t2361, ptr %t2362
  %t2363 = getelementptr ptr, ptr %t11, i32 5
  %t2364 = load ptr, ptr %t2363
  call void @__inc_ref(ptr %t2364)
  %t2365 = getelementptr ptr, ptr %t2351, i32 4
  store ptr %t2364, ptr %t2365
  %t2366 = getelementptr ptr, ptr %t11, i32 6
  %t2367 = load ptr, ptr %t2366
  call void @__inc_ref(ptr %t2367)
  %t2368 = getelementptr ptr, ptr %t2351, i32 5
  store ptr %t2367, ptr %t2368
  call void @__inc_ref(ptr %t13)
  %t2369 = getelementptr ptr, ptr %t2351, i32 6
  store ptr %t13, ptr %t2369
  %t2370 = getelementptr ptr, ptr %t11, i32 1
  %t2371 = load ptr, ptr %t2370
  call void @__inc_ref(ptr %t2371)
  %t2372 = getelementptr ptr, ptr %t4, i32 1
  %t2373 = load ptr, ptr %t2372
  call void @__free_recursive(ptr %t2373)
  %t2374 = getelementptr ptr, ptr %t4, i32 2
  %t2375 = load ptr, ptr %t2374
  call void @__free_recursive(ptr %t2375)
  %t2378 = inttoptr i64 280 to ptr
  %t2379 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t2378, ptr %t2379
  %t2376 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t2351, ptr %t2376
  %t2377 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t2371, ptr %t2377
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.190.2380:
  %t2381 = getelementptr ptr, ptr %t11, i32 7
  %t2382 = load ptr, ptr %t2381
  call void @__inc_ref(ptr %t2382)
  %t2383 = call ptr @__alloc(i64 32, i32 3)
  %t2384 = inttoptr i64 88 to ptr
  %t2385 = getelementptr ptr, ptr %t2383, i32 0
  store ptr %t2384, ptr %t2385
  call void @__inc_ref(ptr %t2382)
  %t2386 = getelementptr ptr, ptr %t2383, i32 1
  store ptr %t2382, ptr %t2386
  %t2387 = getelementptr ptr, ptr %t11, i32 4
  %t2388 = load ptr, ptr %t2387
  call void @__inc_ref(ptr %t2388)
  %t2389 = getelementptr ptr, ptr %t2383, i32 2
  store ptr %t2388, ptr %t2389
  call void @__inc_ref(ptr %t13)
  %t2390 = getelementptr ptr, ptr %t2383, i32 3
  store ptr %t13, ptr %t2390
  %t2391 = call ptr @__alloc(i64 56, i32 6)
  %t2392 = inttoptr i64 191 to ptr
  %t2393 = getelementptr ptr, ptr %t2391, i32 0
  store ptr %t2392, ptr %t2393
  %t2394 = getelementptr ptr, ptr %t11, i32 1
  %t2395 = load ptr, ptr %t2394
  call void @__inc_ref(ptr %t2395)
  %t2396 = getelementptr ptr, ptr %t2391, i32 1
  store ptr %t2395, ptr %t2396
  %t2397 = getelementptr ptr, ptr %t11, i32 2
  %t2398 = load ptr, ptr %t2397
  call void @__inc_ref(ptr %t2398)
  %t2399 = getelementptr ptr, ptr %t2391, i32 2
  store ptr %t2398, ptr %t2399
  %t2400 = getelementptr ptr, ptr %t11, i32 3
  %t2401 = load ptr, ptr %t2400
  call void @__inc_ref(ptr %t2401)
  %t2402 = getelementptr ptr, ptr %t2391, i32 3
  store ptr %t2401, ptr %t2402
  %t2403 = getelementptr ptr, ptr %t11, i32 5
  %t2404 = load ptr, ptr %t2403
  call void @__inc_ref(ptr %t2404)
  %t2405 = getelementptr ptr, ptr %t2391, i32 4
  store ptr %t2404, ptr %t2405
  %t2406 = getelementptr ptr, ptr %t11, i32 6
  %t2407 = load ptr, ptr %t2406
  call void @__inc_ref(ptr %t2407)
  %t2408 = getelementptr ptr, ptr %t2391, i32 5
  store ptr %t2407, ptr %t2408
  call void @__inc_ref(ptr %t2382)
  %t2409 = getelementptr ptr, ptr %t2391, i32 6
  store ptr %t2382, ptr %t2409
  %t2410 = getelementptr ptr, ptr %t4, i32 1
  %t2411 = load ptr, ptr %t2410
  call void @__free_recursive(ptr %t2411)
  %t2412 = getelementptr ptr, ptr %t4, i32 2
  %t2413 = load ptr, ptr %t2412
  call void @__free_recursive(ptr %t2413)
  %t2416 = inttoptr i64 280 to ptr
  %t2417 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t2416, ptr %t2417
  %t2414 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t2383, ptr %t2414
  %t2415 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t2391, ptr %t2415
  call void @__free_recursive(ptr %t2382)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.193.2418:
  %t2419 = call ptr @__alloc(i64 64, i32 7)
  %t2420 = inttoptr i64 62 to ptr
  %t2421 = getelementptr ptr, ptr %t2419, i32 0
  store ptr %t2420, ptr %t2421
  %t2422 = getelementptr ptr, ptr %t11, i32 2
  %t2423 = load ptr, ptr %t2422
  call void @__inc_ref(ptr %t2423)
  %t2424 = getelementptr ptr, ptr %t2419, i32 1
  store ptr %t2423, ptr %t2424
  %t2425 = getelementptr ptr, ptr %t11, i32 3
  %t2426 = load ptr, ptr %t2425
  call void @__inc_ref(ptr %t2426)
  %t2427 = getelementptr ptr, ptr %t2419, i32 2
  store ptr %t2426, ptr %t2427
  %t2428 = getelementptr ptr, ptr %t11, i32 4
  %t2429 = load ptr, ptr %t2428
  call void @__inc_ref(ptr %t2429)
  %t2430 = getelementptr ptr, ptr %t2419, i32 3
  store ptr %t2429, ptr %t2430
  %t2431 = getelementptr ptr, ptr %t11, i32 5
  %t2432 = load ptr, ptr %t2431
  call void @__inc_ref(ptr %t2432)
  %t2433 = getelementptr ptr, ptr %t2419, i32 4
  store ptr %t2432, ptr %t2433
  %t2434 = getelementptr ptr, ptr %t11, i32 6
  %t2435 = load ptr, ptr %t2434
  call void @__inc_ref(ptr %t2435)
  %t2436 = getelementptr ptr, ptr %t2419, i32 5
  store ptr %t2435, ptr %t2436
  %t2437 = getelementptr ptr, ptr %t11, i32 7
  %t2438 = load ptr, ptr %t2437
  call void @__inc_ref(ptr %t2438)
  %t2439 = getelementptr ptr, ptr %t2419, i32 6
  store ptr %t2438, ptr %t2439
  call void @__inc_ref(ptr %t13)
  %t2440 = getelementptr ptr, ptr %t2419, i32 7
  store ptr %t13, ptr %t2440
  %t2441 = getelementptr ptr, ptr %t11, i32 1
  %t2442 = load ptr, ptr %t2441
  call void @__inc_ref(ptr %t2442)
  %t2443 = getelementptr ptr, ptr %t4, i32 1
  %t2444 = load ptr, ptr %t2443
  call void @__free_recursive(ptr %t2444)
  %t2445 = getelementptr ptr, ptr %t4, i32 2
  %t2446 = load ptr, ptr %t2445
  call void @__free_recursive(ptr %t2446)
  %t2449 = inttoptr i64 280 to ptr
  %t2450 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t2449, ptr %t2450
  %t2447 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t2419, ptr %t2447
  %t2448 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t2442, ptr %t2448
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.192.2451:
  %t2452 = getelementptr ptr, ptr %t11, i32 8
  %t2453 = load ptr, ptr %t2452
  call void @__inc_ref(ptr %t2453)
  %t2454 = call ptr @__alloc(i64 32, i32 3)
  %t2455 = inttoptr i64 88 to ptr
  %t2456 = getelementptr ptr, ptr %t2454, i32 0
  store ptr %t2455, ptr %t2456
  call void @__inc_ref(ptr %t2453)
  %t2457 = getelementptr ptr, ptr %t2454, i32 1
  store ptr %t2453, ptr %t2457
  %t2458 = getelementptr ptr, ptr %t11, i32 4
  %t2459 = load ptr, ptr %t2458
  call void @__inc_ref(ptr %t2459)
  %t2460 = getelementptr ptr, ptr %t2454, i32 2
  store ptr %t2459, ptr %t2460
  call void @__inc_ref(ptr %t13)
  %t2461 = getelementptr ptr, ptr %t2454, i32 3
  store ptr %t13, ptr %t2461
  %t2462 = call ptr @__alloc(i64 64, i32 7)
  %t2463 = inttoptr i64 193 to ptr
  %t2464 = getelementptr ptr, ptr %t2462, i32 0
  store ptr %t2463, ptr %t2464
  %t2465 = getelementptr ptr, ptr %t11, i32 1
  %t2466 = load ptr, ptr %t2465
  call void @__inc_ref(ptr %t2466)
  %t2467 = getelementptr ptr, ptr %t2462, i32 1
  store ptr %t2466, ptr %t2467
  %t2468 = getelementptr ptr, ptr %t11, i32 2
  %t2469 = load ptr, ptr %t2468
  call void @__inc_ref(ptr %t2469)
  %t2470 = getelementptr ptr, ptr %t2462, i32 2
  store ptr %t2469, ptr %t2470
  %t2471 = getelementptr ptr, ptr %t11, i32 3
  %t2472 = load ptr, ptr %t2471
  call void @__inc_ref(ptr %t2472)
  %t2473 = getelementptr ptr, ptr %t2462, i32 3
  store ptr %t2472, ptr %t2473
  %t2474 = getelementptr ptr, ptr %t11, i32 5
  %t2475 = load ptr, ptr %t2474
  call void @__inc_ref(ptr %t2475)
  %t2476 = getelementptr ptr, ptr %t2462, i32 4
  store ptr %t2475, ptr %t2476
  %t2477 = getelementptr ptr, ptr %t11, i32 6
  %t2478 = load ptr, ptr %t2477
  call void @__inc_ref(ptr %t2478)
  %t2479 = getelementptr ptr, ptr %t2462, i32 5
  store ptr %t2478, ptr %t2479
  %t2480 = getelementptr ptr, ptr %t11, i32 7
  %t2481 = load ptr, ptr %t2480
  call void @__inc_ref(ptr %t2481)
  %t2482 = getelementptr ptr, ptr %t2462, i32 6
  store ptr %t2481, ptr %t2482
  call void @__inc_ref(ptr %t2453)
  %t2483 = getelementptr ptr, ptr %t2462, i32 7
  store ptr %t2453, ptr %t2483
  %t2484 = getelementptr ptr, ptr %t4, i32 1
  %t2485 = load ptr, ptr %t2484
  call void @__free_recursive(ptr %t2485)
  %t2486 = getelementptr ptr, ptr %t4, i32 2
  %t2487 = load ptr, ptr %t2486
  call void @__free_recursive(ptr %t2487)
  %t2490 = inttoptr i64 280 to ptr
  %t2491 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t2490, ptr %t2491
  %t2488 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t2454, ptr %t2488
  %t2489 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t2462, ptr %t2489
  call void @__free_recursive(ptr %t2453)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.195.2492:
  %t2493 = getelementptr ptr, ptr %t11, i32 1
  %t2494 = load ptr, ptr %t2493
  call void @__inc_ref(ptr %t2494)
  %t2495 = getelementptr ptr, ptr %t11, i32 3
  %t2496 = load ptr, ptr %t2495
  call void @__inc_ref(ptr %t2496)
  %t2497 = getelementptr ptr, ptr %t11, i32 4
  %t2498 = load ptr, ptr %t2497
  call void @__inc_ref(ptr %t2498)
  %t2499 = getelementptr ptr, ptr %t11, i32 2
  %t2500 = load ptr, ptr %t2499
  call void @__inc_ref(ptr %t2500)
  %t2501 = getelementptr ptr, ptr %t13, i32 1
  %t2502 = load ptr, ptr %t2501
  call void @__inc_ref(ptr %t2502)
  %t2503 = call ptr @__subUInt32(ptr %t2500, ptr %t2502)
  %t2504 = getelementptr ptr, ptr %t2503, i32 0
  %t2505 = load ptr, ptr %t2504
  %t2506 = ptrtoint ptr %t2505 to i64
  switch i64 %t2506, label %tco.case.default.2507 [ i64 3, label %tco.case.arm.3.2508 i64 4, label %tco.case.arm.4.2534 ]
tco.case.arm.3.2508:
  call void @__free_recursive(ptr %t2503)
  %t2509 = call ptr @__alloc(i64 32, i32 3)
  %t2510 = inttoptr i64 34 to ptr
  %t2511 = getelementptr ptr, ptr %t2509, i32 0
  store ptr %t2510, ptr %t2511
  %t2512 = call ptr @__alloc(i64 8, i32 0)
  %t2513 = inttoptr i64 11 to ptr
  %t2514 = getelementptr ptr, ptr %t2512, i32 0
  store ptr %t2513, ptr %t2514
  %t2515 = getelementptr ptr, ptr %t2509, i32 1
  store ptr %t2512, ptr %t2515
  call void @__inc_ref(ptr %t2496)
  %t2516 = getelementptr ptr, ptr %t2509, i32 2
  store ptr %t2496, ptr %t2516
  %t2517 = call ptr @__alloc(i64 16, i32 1)
  %t2518 = inttoptr i64 12 to ptr
  %t2519 = getelementptr ptr, ptr %t2517, i32 0
  store ptr %t2518, ptr %t2519
  %t2520 = call ptr @__alloc(i64 16, i32 1)
  %t2521 = inttoptr i64 24 to ptr
  %t2522 = getelementptr ptr, ptr %t2520, i32 0
  store ptr %t2521, ptr %t2522
  call void @__inc_ref(ptr %t2498)
  %t2523 = getelementptr ptr, ptr %t2520, i32 1
  store ptr %t2498, ptr %t2523
  %t2524 = getelementptr ptr, ptr %t2517, i32 1
  store ptr %t2520, ptr %t2524
  %t2525 = getelementptr ptr, ptr %t2509, i32 3
  store ptr %t2517, ptr %t2525
  %t2526 = getelementptr ptr, ptr %t4, i32 1
  %t2527 = load ptr, ptr %t2526
  call void @__free_recursive(ptr %t2527)
  %t2528 = getelementptr ptr, ptr %t4, i32 2
  %t2529 = load ptr, ptr %t2528
  call void @__free_recursive(ptr %t2529)
  %t2532 = inttoptr i64 279 to ptr
  %t2533 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t2532, ptr %t2533
  call void @__inc_ref(ptr %t2494)
  %t2530 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t2494, ptr %t2530
  %t2531 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t2509, ptr %t2531
  call void @__free_recursive(ptr %t2498)
  call void @__free_recursive(ptr %t2496)
  call void @__free_recursive(ptr %t2494)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.4.2534:
  call void @__free_recursive(ptr %t2503)
  %t2535 = call ptr @__alloc(i64 32, i32 3)
  %t2536 = inttoptr i64 34 to ptr
  %t2537 = getelementptr ptr, ptr %t2535, i32 0
  store ptr %t2536, ptr %t2537
  %t2538 = call ptr @__alloc(i64 16, i32 1)
  %t2539 = inttoptr i64 12 to ptr
  %t2540 = getelementptr ptr, ptr %t2538, i32 0
  store ptr %t2539, ptr %t2540
  %t2541 = call ptr @__alloc(i64 16, i32 1)
  %t2542 = inttoptr i64 24 to ptr
  %t2543 = getelementptr ptr, ptr %t2541, i32 0
  store ptr %t2542, ptr %t2543
  call void @__inc_ref(ptr %t2496)
  %t2544 = getelementptr ptr, ptr %t2541, i32 1
  store ptr %t2496, ptr %t2544
  %t2545 = getelementptr ptr, ptr %t2538, i32 1
  store ptr %t2541, ptr %t2545
  %t2546 = getelementptr ptr, ptr %t2535, i32 1
  store ptr %t2538, ptr %t2546
  call void @__inc_ref(ptr %t2498)
  %t2547 = getelementptr ptr, ptr %t2535, i32 2
  store ptr %t2498, ptr %t2547
  %t2548 = call ptr @__alloc(i64 8, i32 0)
  %t2549 = inttoptr i64 11 to ptr
  %t2550 = getelementptr ptr, ptr %t2548, i32 0
  store ptr %t2549, ptr %t2550
  %t2551 = getelementptr ptr, ptr %t2535, i32 3
  store ptr %t2548, ptr %t2551
  %t2552 = getelementptr ptr, ptr %t4, i32 1
  %t2553 = load ptr, ptr %t2552
  call void @__free_recursive(ptr %t2553)
  %t2554 = getelementptr ptr, ptr %t4, i32 2
  %t2555 = load ptr, ptr %t2554
  call void @__free_recursive(ptr %t2555)
  %t2558 = inttoptr i64 279 to ptr
  %t2559 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t2558, ptr %t2559
  call void @__inc_ref(ptr %t2494)
  %t2556 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t2494, ptr %t2556
  %t2557 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t2535, ptr %t2557
  call void @__free_recursive(ptr %t2498)
  call void @__free_recursive(ptr %t2496)
  call void @__free_recursive(ptr %t2494)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.2507:
  unreachable
tco.case.arm.194.2560:
  %t2561 = call ptr @__alloc(i64 32, i32 3)
  %t2562 = inttoptr i64 88 to ptr
  %t2563 = getelementptr ptr, ptr %t2561, i32 0
  store ptr %t2562, ptr %t2563
  %t2564 = getelementptr ptr, ptr %t11, i32 6
  %t2565 = load ptr, ptr %t2564
  call void @__inc_ref(ptr %t2565)
  %t2566 = getelementptr ptr, ptr %t2561, i32 1
  store ptr %t2565, ptr %t2566
  %t2567 = getelementptr ptr, ptr %t11, i32 4
  %t2568 = load ptr, ptr %t2567
  call void @__inc_ref(ptr %t2568)
  %t2569 = getelementptr ptr, ptr %t2561, i32 2
  store ptr %t2568, ptr %t2569
  call void @__inc_ref(ptr %t13)
  %t2570 = getelementptr ptr, ptr %t2561, i32 3
  store ptr %t13, ptr %t2570
  %t2571 = call ptr @__alloc(i64 40, i32 4)
  %t2572 = inttoptr i64 195 to ptr
  %t2573 = getelementptr ptr, ptr %t2571, i32 0
  store ptr %t2572, ptr %t2573
  %t2574 = getelementptr ptr, ptr %t11, i32 1
  %t2575 = load ptr, ptr %t2574
  call void @__inc_ref(ptr %t2575)
  %t2576 = getelementptr ptr, ptr %t2571, i32 1
  store ptr %t2575, ptr %t2576
  %t2577 = getelementptr ptr, ptr %t11, i32 2
  %t2578 = load ptr, ptr %t2577
  call void @__inc_ref(ptr %t2578)
  %t2579 = getelementptr ptr, ptr %t2571, i32 2
  store ptr %t2578, ptr %t2579
  %t2580 = getelementptr ptr, ptr %t11, i32 3
  %t2581 = load ptr, ptr %t2580
  call void @__inc_ref(ptr %t2581)
  %t2582 = getelementptr ptr, ptr %t2571, i32 3
  store ptr %t2581, ptr %t2582
  %t2583 = getelementptr ptr, ptr %t11, i32 5
  %t2584 = load ptr, ptr %t2583
  call void @__inc_ref(ptr %t2584)
  %t2585 = getelementptr ptr, ptr %t2571, i32 4
  store ptr %t2584, ptr %t2585
  %t2586 = getelementptr ptr, ptr %t4, i32 1
  %t2587 = load ptr, ptr %t2586
  call void @__free_recursive(ptr %t2587)
  %t2588 = getelementptr ptr, ptr %t4, i32 2
  %t2589 = load ptr, ptr %t2588
  call void @__free_recursive(ptr %t2589)
  %t2592 = inttoptr i64 280 to ptr
  %t2593 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t2592, ptr %t2593
  %t2590 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t2561, ptr %t2590
  %t2591 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t2571, ptr %t2591
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.197.2594:
  %t2595 = call ptr @__alloc(i64 56, i32 6)
  %t2596 = inttoptr i64 59 to ptr
  %t2597 = getelementptr ptr, ptr %t2595, i32 0
  store ptr %t2596, ptr %t2597
  %t2598 = getelementptr ptr, ptr %t11, i32 2
  %t2599 = load ptr, ptr %t2598
  call void @__inc_ref(ptr %t2599)
  %t2600 = getelementptr ptr, ptr %t2595, i32 1
  store ptr %t2599, ptr %t2600
  %t2601 = getelementptr ptr, ptr %t11, i32 3
  %t2602 = load ptr, ptr %t2601
  call void @__inc_ref(ptr %t2602)
  %t2603 = getelementptr ptr, ptr %t2595, i32 2
  store ptr %t2602, ptr %t2603
  %t2604 = getelementptr ptr, ptr %t11, i32 4
  %t2605 = load ptr, ptr %t2604
  call void @__inc_ref(ptr %t2605)
  %t2606 = getelementptr ptr, ptr %t2595, i32 3
  store ptr %t2605, ptr %t2606
  %t2607 = getelementptr ptr, ptr %t11, i32 5
  %t2608 = load ptr, ptr %t2607
  call void @__inc_ref(ptr %t2608)
  %t2609 = getelementptr ptr, ptr %t2595, i32 4
  store ptr %t2608, ptr %t2609
  %t2610 = getelementptr ptr, ptr %t11, i32 6
  %t2611 = load ptr, ptr %t2610
  call void @__inc_ref(ptr %t2611)
  %t2612 = getelementptr ptr, ptr %t2595, i32 5
  store ptr %t2611, ptr %t2612
  call void @__inc_ref(ptr %t13)
  %t2613 = getelementptr ptr, ptr %t2595, i32 6
  store ptr %t13, ptr %t2613
  %t2614 = getelementptr ptr, ptr %t11, i32 1
  %t2615 = load ptr, ptr %t2614
  call void @__inc_ref(ptr %t2615)
  %t2616 = getelementptr ptr, ptr %t4, i32 1
  %t2617 = load ptr, ptr %t2616
  call void @__free_recursive(ptr %t2617)
  %t2618 = getelementptr ptr, ptr %t4, i32 2
  %t2619 = load ptr, ptr %t2618
  call void @__free_recursive(ptr %t2619)
  %t2622 = inttoptr i64 280 to ptr
  %t2623 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t2622, ptr %t2623
  %t2620 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t2595, ptr %t2620
  %t2621 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t2615, ptr %t2621
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.196.2624:
  %t2625 = getelementptr ptr, ptr %t11, i32 7
  %t2626 = load ptr, ptr %t2625
  call void @__inc_ref(ptr %t2626)
  %t2627 = call ptr @__alloc(i64 32, i32 3)
  %t2628 = inttoptr i64 88 to ptr
  %t2629 = getelementptr ptr, ptr %t2627, i32 0
  store ptr %t2628, ptr %t2629
  call void @__inc_ref(ptr %t2626)
  %t2630 = getelementptr ptr, ptr %t2627, i32 1
  store ptr %t2626, ptr %t2630
  %t2631 = getelementptr ptr, ptr %t11, i32 4
  %t2632 = load ptr, ptr %t2631
  call void @__inc_ref(ptr %t2632)
  %t2633 = getelementptr ptr, ptr %t2627, i32 2
  store ptr %t2632, ptr %t2633
  call void @__inc_ref(ptr %t13)
  %t2634 = getelementptr ptr, ptr %t2627, i32 3
  store ptr %t13, ptr %t2634
  %t2635 = call ptr @__alloc(i64 56, i32 6)
  %t2636 = inttoptr i64 197 to ptr
  %t2637 = getelementptr ptr, ptr %t2635, i32 0
  store ptr %t2636, ptr %t2637
  %t2638 = getelementptr ptr, ptr %t11, i32 1
  %t2639 = load ptr, ptr %t2638
  call void @__inc_ref(ptr %t2639)
  %t2640 = getelementptr ptr, ptr %t2635, i32 1
  store ptr %t2639, ptr %t2640
  %t2641 = getelementptr ptr, ptr %t11, i32 2
  %t2642 = load ptr, ptr %t2641
  call void @__inc_ref(ptr %t2642)
  %t2643 = getelementptr ptr, ptr %t2635, i32 2
  store ptr %t2642, ptr %t2643
  %t2644 = getelementptr ptr, ptr %t11, i32 3
  %t2645 = load ptr, ptr %t2644
  call void @__inc_ref(ptr %t2645)
  %t2646 = getelementptr ptr, ptr %t2635, i32 3
  store ptr %t2645, ptr %t2646
  %t2647 = getelementptr ptr, ptr %t11, i32 5
  %t2648 = load ptr, ptr %t2647
  call void @__inc_ref(ptr %t2648)
  %t2649 = getelementptr ptr, ptr %t2635, i32 4
  store ptr %t2648, ptr %t2649
  %t2650 = getelementptr ptr, ptr %t11, i32 6
  %t2651 = load ptr, ptr %t2650
  call void @__inc_ref(ptr %t2651)
  %t2652 = getelementptr ptr, ptr %t2635, i32 5
  store ptr %t2651, ptr %t2652
  call void @__inc_ref(ptr %t2626)
  %t2653 = getelementptr ptr, ptr %t2635, i32 6
  store ptr %t2626, ptr %t2653
  %t2654 = getelementptr ptr, ptr %t4, i32 1
  %t2655 = load ptr, ptr %t2654
  call void @__free_recursive(ptr %t2655)
  %t2656 = getelementptr ptr, ptr %t4, i32 2
  %t2657 = load ptr, ptr %t2656
  call void @__free_recursive(ptr %t2657)
  %t2660 = inttoptr i64 280 to ptr
  %t2661 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t2660, ptr %t2661
  %t2658 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t2627, ptr %t2658
  %t2659 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t2635, ptr %t2659
  call void @__free_recursive(ptr %t2626)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.199.2662:
  %t2663 = call ptr @__alloc(i64 64, i32 7)
  %t2664 = inttoptr i64 63 to ptr
  %t2665 = getelementptr ptr, ptr %t2663, i32 0
  store ptr %t2664, ptr %t2665
  %t2666 = getelementptr ptr, ptr %t11, i32 2
  %t2667 = load ptr, ptr %t2666
  call void @__inc_ref(ptr %t2667)
  %t2668 = getelementptr ptr, ptr %t2663, i32 1
  store ptr %t2667, ptr %t2668
  %t2669 = getelementptr ptr, ptr %t11, i32 3
  %t2670 = load ptr, ptr %t2669
  call void @__inc_ref(ptr %t2670)
  %t2671 = getelementptr ptr, ptr %t2663, i32 2
  store ptr %t2670, ptr %t2671
  %t2672 = getelementptr ptr, ptr %t11, i32 4
  %t2673 = load ptr, ptr %t2672
  call void @__inc_ref(ptr %t2673)
  %t2674 = getelementptr ptr, ptr %t2663, i32 3
  store ptr %t2673, ptr %t2674
  %t2675 = getelementptr ptr, ptr %t11, i32 5
  %t2676 = load ptr, ptr %t2675
  call void @__inc_ref(ptr %t2676)
  %t2677 = getelementptr ptr, ptr %t2663, i32 4
  store ptr %t2676, ptr %t2677
  %t2678 = getelementptr ptr, ptr %t11, i32 6
  %t2679 = load ptr, ptr %t2678
  call void @__inc_ref(ptr %t2679)
  %t2680 = getelementptr ptr, ptr %t2663, i32 5
  store ptr %t2679, ptr %t2680
  %t2681 = getelementptr ptr, ptr %t11, i32 7
  %t2682 = load ptr, ptr %t2681
  call void @__inc_ref(ptr %t2682)
  %t2683 = getelementptr ptr, ptr %t2663, i32 6
  store ptr %t2682, ptr %t2683
  call void @__inc_ref(ptr %t13)
  %t2684 = getelementptr ptr, ptr %t2663, i32 7
  store ptr %t13, ptr %t2684
  %t2685 = getelementptr ptr, ptr %t11, i32 1
  %t2686 = load ptr, ptr %t2685
  call void @__inc_ref(ptr %t2686)
  %t2687 = getelementptr ptr, ptr %t4, i32 1
  %t2688 = load ptr, ptr %t2687
  call void @__free_recursive(ptr %t2688)
  %t2689 = getelementptr ptr, ptr %t4, i32 2
  %t2690 = load ptr, ptr %t2689
  call void @__free_recursive(ptr %t2690)
  %t2693 = inttoptr i64 280 to ptr
  %t2694 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t2693, ptr %t2694
  %t2691 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t2663, ptr %t2691
  %t2692 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t2686, ptr %t2692
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.198.2695:
  %t2696 = getelementptr ptr, ptr %t11, i32 8
  %t2697 = load ptr, ptr %t2696
  call void @__inc_ref(ptr %t2697)
  %t2698 = call ptr @__alloc(i64 32, i32 3)
  %t2699 = inttoptr i64 88 to ptr
  %t2700 = getelementptr ptr, ptr %t2698, i32 0
  store ptr %t2699, ptr %t2700
  call void @__inc_ref(ptr %t2697)
  %t2701 = getelementptr ptr, ptr %t2698, i32 1
  store ptr %t2697, ptr %t2701
  %t2702 = getelementptr ptr, ptr %t11, i32 4
  %t2703 = load ptr, ptr %t2702
  call void @__inc_ref(ptr %t2703)
  %t2704 = getelementptr ptr, ptr %t2698, i32 2
  store ptr %t2703, ptr %t2704
  call void @__inc_ref(ptr %t13)
  %t2705 = getelementptr ptr, ptr %t2698, i32 3
  store ptr %t13, ptr %t2705
  %t2706 = call ptr @__alloc(i64 64, i32 7)
  %t2707 = inttoptr i64 199 to ptr
  %t2708 = getelementptr ptr, ptr %t2706, i32 0
  store ptr %t2707, ptr %t2708
  %t2709 = getelementptr ptr, ptr %t11, i32 1
  %t2710 = load ptr, ptr %t2709
  call void @__inc_ref(ptr %t2710)
  %t2711 = getelementptr ptr, ptr %t2706, i32 1
  store ptr %t2710, ptr %t2711
  %t2712 = getelementptr ptr, ptr %t11, i32 2
  %t2713 = load ptr, ptr %t2712
  call void @__inc_ref(ptr %t2713)
  %t2714 = getelementptr ptr, ptr %t2706, i32 2
  store ptr %t2713, ptr %t2714
  %t2715 = getelementptr ptr, ptr %t11, i32 3
  %t2716 = load ptr, ptr %t2715
  call void @__inc_ref(ptr %t2716)
  %t2717 = getelementptr ptr, ptr %t2706, i32 3
  store ptr %t2716, ptr %t2717
  %t2718 = getelementptr ptr, ptr %t11, i32 5
  %t2719 = load ptr, ptr %t2718
  call void @__inc_ref(ptr %t2719)
  %t2720 = getelementptr ptr, ptr %t2706, i32 4
  store ptr %t2719, ptr %t2720
  %t2721 = getelementptr ptr, ptr %t11, i32 6
  %t2722 = load ptr, ptr %t2721
  call void @__inc_ref(ptr %t2722)
  %t2723 = getelementptr ptr, ptr %t2706, i32 5
  store ptr %t2722, ptr %t2723
  %t2724 = getelementptr ptr, ptr %t11, i32 7
  %t2725 = load ptr, ptr %t2724
  call void @__inc_ref(ptr %t2725)
  %t2726 = getelementptr ptr, ptr %t2706, i32 6
  store ptr %t2725, ptr %t2726
  call void @__inc_ref(ptr %t2697)
  %t2727 = getelementptr ptr, ptr %t2706, i32 7
  store ptr %t2697, ptr %t2727
  %t2728 = getelementptr ptr, ptr %t4, i32 1
  %t2729 = load ptr, ptr %t2728
  call void @__free_recursive(ptr %t2729)
  %t2730 = getelementptr ptr, ptr %t4, i32 2
  %t2731 = load ptr, ptr %t2730
  call void @__free_recursive(ptr %t2731)
  %t2734 = inttoptr i64 280 to ptr
  %t2735 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t2734, ptr %t2735
  %t2732 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t2698, ptr %t2732
  %t2733 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t2706, ptr %t2733
  call void @__free_recursive(ptr %t2697)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.201.2736:
  %t2737 = call ptr @__alloc(i64 64, i32 7)
  %t2738 = inttoptr i64 68 to ptr
  %t2739 = getelementptr ptr, ptr %t2737, i32 0
  store ptr %t2738, ptr %t2739
  %t2740 = getelementptr ptr, ptr %t11, i32 2
  %t2741 = load ptr, ptr %t2740
  call void @__inc_ref(ptr %t2741)
  %t2742 = getelementptr ptr, ptr %t2737, i32 1
  store ptr %t2741, ptr %t2742
  %t2743 = getelementptr ptr, ptr %t11, i32 3
  %t2744 = load ptr, ptr %t2743
  call void @__inc_ref(ptr %t2744)
  %t2745 = getelementptr ptr, ptr %t2737, i32 2
  store ptr %t2744, ptr %t2745
  %t2746 = getelementptr ptr, ptr %t11, i32 4
  %t2747 = load ptr, ptr %t2746
  call void @__inc_ref(ptr %t2747)
  %t2748 = getelementptr ptr, ptr %t2737, i32 3
  store ptr %t2747, ptr %t2748
  %t2749 = getelementptr ptr, ptr %t11, i32 5
  %t2750 = load ptr, ptr %t2749
  call void @__inc_ref(ptr %t2750)
  %t2751 = getelementptr ptr, ptr %t2737, i32 4
  store ptr %t2750, ptr %t2751
  %t2752 = getelementptr ptr, ptr %t11, i32 6
  %t2753 = load ptr, ptr %t2752
  call void @__inc_ref(ptr %t2753)
  %t2754 = getelementptr ptr, ptr %t2737, i32 5
  store ptr %t2753, ptr %t2754
  %t2755 = getelementptr ptr, ptr %t11, i32 7
  %t2756 = load ptr, ptr %t2755
  call void @__inc_ref(ptr %t2756)
  %t2757 = getelementptr ptr, ptr %t2737, i32 6
  store ptr %t2756, ptr %t2757
  call void @__inc_ref(ptr %t13)
  %t2758 = getelementptr ptr, ptr %t2737, i32 7
  store ptr %t13, ptr %t2758
  %t2759 = getelementptr ptr, ptr %t11, i32 1
  %t2760 = load ptr, ptr %t2759
  call void @__inc_ref(ptr %t2760)
  %t2761 = getelementptr ptr, ptr %t4, i32 1
  %t2762 = load ptr, ptr %t2761
  call void @__free_recursive(ptr %t2762)
  %t2763 = getelementptr ptr, ptr %t4, i32 2
  %t2764 = load ptr, ptr %t2763
  call void @__free_recursive(ptr %t2764)
  %t2767 = inttoptr i64 280 to ptr
  %t2768 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t2767, ptr %t2768
  %t2765 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t2737, ptr %t2765
  %t2766 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t2760, ptr %t2766
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.200.2769:
  %t2770 = getelementptr ptr, ptr %t11, i32 3
  %t2771 = load ptr, ptr %t2770
  call void @__inc_ref(ptr %t2771)
  %t2772 = getelementptr ptr, ptr %t11, i32 4
  %t2773 = load ptr, ptr %t2772
  call void @__inc_ref(ptr %t2773)
  %t2774 = call ptr @__alloc(i64 32, i32 3)
  %t2775 = inttoptr i64 88 to ptr
  %t2776 = getelementptr ptr, ptr %t2774, i32 0
  store ptr %t2775, ptr %t2776
  call void @__inc_ref(ptr %t2773)
  %t2777 = getelementptr ptr, ptr %t2774, i32 1
  store ptr %t2773, ptr %t2777
  call void @__inc_ref(ptr %t2771)
  %t2778 = getelementptr ptr, ptr %t2774, i32 2
  store ptr %t2771, ptr %t2778
  call void @__inc_ref(ptr %t13)
  %t2779 = getelementptr ptr, ptr %t2774, i32 3
  store ptr %t13, ptr %t2779
  %t2780 = call ptr @__alloc(i64 64, i32 7)
  %t2781 = inttoptr i64 201 to ptr
  %t2782 = getelementptr ptr, ptr %t2780, i32 0
  store ptr %t2781, ptr %t2782
  %t2783 = getelementptr ptr, ptr %t11, i32 1
  %t2784 = load ptr, ptr %t2783
  call void @__inc_ref(ptr %t2784)
  %t2785 = getelementptr ptr, ptr %t2780, i32 1
  store ptr %t2784, ptr %t2785
  %t2786 = getelementptr ptr, ptr %t11, i32 2
  %t2787 = load ptr, ptr %t2786
  call void @__inc_ref(ptr %t2787)
  %t2788 = getelementptr ptr, ptr %t2780, i32 2
  store ptr %t2787, ptr %t2788
  call void @__inc_ref(ptr %t2771)
  %t2789 = getelementptr ptr, ptr %t2780, i32 3
  store ptr %t2771, ptr %t2789
  call void @__inc_ref(ptr %t2773)
  %t2790 = getelementptr ptr, ptr %t2780, i32 4
  store ptr %t2773, ptr %t2790
  %t2791 = getelementptr ptr, ptr %t11, i32 5
  %t2792 = load ptr, ptr %t2791
  call void @__inc_ref(ptr %t2792)
  %t2793 = getelementptr ptr, ptr %t2780, i32 5
  store ptr %t2792, ptr %t2793
  %t2794 = getelementptr ptr, ptr %t11, i32 6
  %t2795 = load ptr, ptr %t2794
  call void @__inc_ref(ptr %t2795)
  %t2796 = getelementptr ptr, ptr %t2780, i32 6
  store ptr %t2795, ptr %t2796
  %t2797 = getelementptr ptr, ptr %t11, i32 7
  %t2798 = load ptr, ptr %t2797
  call void @__inc_ref(ptr %t2798)
  %t2799 = getelementptr ptr, ptr %t2780, i32 7
  store ptr %t2798, ptr %t2799
  %t2800 = getelementptr ptr, ptr %t4, i32 1
  %t2801 = load ptr, ptr %t2800
  call void @__free_recursive(ptr %t2801)
  %t2802 = getelementptr ptr, ptr %t4, i32 2
  %t2803 = load ptr, ptr %t2802
  call void @__free_recursive(ptr %t2803)
  %t2806 = inttoptr i64 280 to ptr
  %t2807 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t2806, ptr %t2807
  %t2804 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t2774, ptr %t2804
  %t2805 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t2780, ptr %t2805
  call void @__free_recursive(ptr %t2773)
  call void @__free_recursive(ptr %t2771)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.203.2808:
  %t2809 = call ptr @__alloc(i64 64, i32 7)
  %t2810 = inttoptr i64 69 to ptr
  %t2811 = getelementptr ptr, ptr %t2809, i32 0
  store ptr %t2810, ptr %t2811
  %t2812 = getelementptr ptr, ptr %t11, i32 2
  %t2813 = load ptr, ptr %t2812
  call void @__inc_ref(ptr %t2813)
  %t2814 = getelementptr ptr, ptr %t2809, i32 1
  store ptr %t2813, ptr %t2814
  %t2815 = getelementptr ptr, ptr %t11, i32 3
  %t2816 = load ptr, ptr %t2815
  call void @__inc_ref(ptr %t2816)
  %t2817 = getelementptr ptr, ptr %t2809, i32 2
  store ptr %t2816, ptr %t2817
  %t2818 = getelementptr ptr, ptr %t11, i32 4
  %t2819 = load ptr, ptr %t2818
  call void @__inc_ref(ptr %t2819)
  %t2820 = getelementptr ptr, ptr %t2809, i32 3
  store ptr %t2819, ptr %t2820
  %t2821 = getelementptr ptr, ptr %t11, i32 5
  %t2822 = load ptr, ptr %t2821
  call void @__inc_ref(ptr %t2822)
  %t2823 = getelementptr ptr, ptr %t2809, i32 4
  store ptr %t2822, ptr %t2823
  %t2824 = getelementptr ptr, ptr %t11, i32 6
  %t2825 = load ptr, ptr %t2824
  call void @__inc_ref(ptr %t2825)
  %t2826 = getelementptr ptr, ptr %t2809, i32 5
  store ptr %t2825, ptr %t2826
  %t2827 = getelementptr ptr, ptr %t11, i32 7
  %t2828 = load ptr, ptr %t2827
  call void @__inc_ref(ptr %t2828)
  %t2829 = getelementptr ptr, ptr %t2809, i32 6
  store ptr %t2828, ptr %t2829
  call void @__inc_ref(ptr %t13)
  %t2830 = getelementptr ptr, ptr %t2809, i32 7
  store ptr %t13, ptr %t2830
  %t2831 = getelementptr ptr, ptr %t11, i32 1
  %t2832 = load ptr, ptr %t2831
  call void @__inc_ref(ptr %t2832)
  %t2833 = getelementptr ptr, ptr %t4, i32 1
  %t2834 = load ptr, ptr %t2833
  call void @__free_recursive(ptr %t2834)
  %t2835 = getelementptr ptr, ptr %t4, i32 2
  %t2836 = load ptr, ptr %t2835
  call void @__free_recursive(ptr %t2836)
  %t2839 = inttoptr i64 280 to ptr
  %t2840 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t2839, ptr %t2840
  %t2837 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t2809, ptr %t2837
  %t2838 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t2832, ptr %t2838
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.202.2841:
  %t2842 = getelementptr ptr, ptr %t11, i32 3
  %t2843 = load ptr, ptr %t2842
  call void @__inc_ref(ptr %t2843)
  %t2844 = getelementptr ptr, ptr %t11, i32 4
  %t2845 = load ptr, ptr %t2844
  call void @__inc_ref(ptr %t2845)
  %t2846 = call ptr @__alloc(i64 32, i32 3)
  %t2847 = inttoptr i64 88 to ptr
  %t2848 = getelementptr ptr, ptr %t2846, i32 0
  store ptr %t2847, ptr %t2848
  call void @__inc_ref(ptr %t2845)
  %t2849 = getelementptr ptr, ptr %t2846, i32 1
  store ptr %t2845, ptr %t2849
  call void @__inc_ref(ptr %t2843)
  %t2850 = getelementptr ptr, ptr %t2846, i32 2
  store ptr %t2843, ptr %t2850
  call void @__inc_ref(ptr %t13)
  %t2851 = getelementptr ptr, ptr %t2846, i32 3
  store ptr %t13, ptr %t2851
  %t2852 = call ptr @__alloc(i64 64, i32 7)
  %t2853 = inttoptr i64 203 to ptr
  %t2854 = getelementptr ptr, ptr %t2852, i32 0
  store ptr %t2853, ptr %t2854
  %t2855 = getelementptr ptr, ptr %t11, i32 1
  %t2856 = load ptr, ptr %t2855
  call void @__inc_ref(ptr %t2856)
  %t2857 = getelementptr ptr, ptr %t2852, i32 1
  store ptr %t2856, ptr %t2857
  %t2858 = getelementptr ptr, ptr %t11, i32 2
  %t2859 = load ptr, ptr %t2858
  call void @__inc_ref(ptr %t2859)
  %t2860 = getelementptr ptr, ptr %t2852, i32 2
  store ptr %t2859, ptr %t2860
  call void @__inc_ref(ptr %t2843)
  %t2861 = getelementptr ptr, ptr %t2852, i32 3
  store ptr %t2843, ptr %t2861
  call void @__inc_ref(ptr %t2845)
  %t2862 = getelementptr ptr, ptr %t2852, i32 4
  store ptr %t2845, ptr %t2862
  %t2863 = getelementptr ptr, ptr %t11, i32 5
  %t2864 = load ptr, ptr %t2863
  call void @__inc_ref(ptr %t2864)
  %t2865 = getelementptr ptr, ptr %t2852, i32 5
  store ptr %t2864, ptr %t2865
  %t2866 = getelementptr ptr, ptr %t11, i32 6
  %t2867 = load ptr, ptr %t2866
  call void @__inc_ref(ptr %t2867)
  %t2868 = getelementptr ptr, ptr %t2852, i32 6
  store ptr %t2867, ptr %t2868
  %t2869 = getelementptr ptr, ptr %t11, i32 7
  %t2870 = load ptr, ptr %t2869
  call void @__inc_ref(ptr %t2870)
  %t2871 = getelementptr ptr, ptr %t2852, i32 7
  store ptr %t2870, ptr %t2871
  %t2872 = getelementptr ptr, ptr %t4, i32 1
  %t2873 = load ptr, ptr %t2872
  call void @__free_recursive(ptr %t2873)
  %t2874 = getelementptr ptr, ptr %t4, i32 2
  %t2875 = load ptr, ptr %t2874
  call void @__free_recursive(ptr %t2875)
  %t2878 = inttoptr i64 280 to ptr
  %t2879 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t2878, ptr %t2879
  %t2876 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t2846, ptr %t2876
  %t2877 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t2852, ptr %t2877
  call void @__free_recursive(ptr %t2845)
  call void @__free_recursive(ptr %t2843)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.205.2880:
  %t2881 = getelementptr ptr, ptr %t11, i32 1
  %t2882 = load ptr, ptr %t2881
  call void @__inc_ref(ptr %t2882)
  %t2883 = call ptr @__alloc(i64 16, i32 1)
  %t2884 = inttoptr i64 12 to ptr
  %t2885 = getelementptr ptr, ptr %t2883, i32 0
  store ptr %t2884, ptr %t2885
  call void @__inc_ref(ptr %t13)
  %t2886 = getelementptr ptr, ptr %t2883, i32 1
  store ptr %t13, ptr %t2886
  %t2887 = getelementptr ptr, ptr %t4, i32 1
  %t2888 = load ptr, ptr %t2887
  call void @__free_recursive(ptr %t2888)
  %t2889 = getelementptr ptr, ptr %t4, i32 2
  %t2890 = load ptr, ptr %t2889
  call void @__free_recursive(ptr %t2890)
  %t2893 = inttoptr i64 279 to ptr
  %t2894 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t2893, ptr %t2894
  %t2891 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t2882, ptr %t2891
  %t2892 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t2883, ptr %t2892
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.204.2895:
  %t2896 = getelementptr ptr, ptr %t11, i32 1
  %t2897 = load ptr, ptr %t2896
  call void @__inc_ref(ptr %t2897)
  %t2898 = getelementptr ptr, ptr %t13, i32 0
  %t2899 = load ptr, ptr %t2898
  %t2900 = ptrtoint ptr %t2899 to i64
  switch i64 %t2900, label %tco.case.default.2901 [ i64 11, label %tco.case.arm.11.2902 i64 12, label %tco.case.arm.12.2908 ]
tco.case.arm.11.2902:
  %t2903 = getelementptr ptr, ptr %t4, i32 1
  %t2904 = load ptr, ptr %t2903
  call void @__free_recursive(ptr %t2904)
  %t2906 = inttoptr i64 279 to ptr
  %t2907 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t2906, ptr %t2907
  call void @__inc_ref(ptr %t2897)
  %t2905 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t2897, ptr %t2905
  call void @__free_recursive(ptr %t2897)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.12.2908:
  %t2909 = getelementptr ptr, ptr %t13, i32 1
  %t2910 = load ptr, ptr %t2909
  call void @__inc_ref(ptr %t2910)
  %t2911 = call ptr @__alloc(i64 24, i32 2)
  %t2912 = inttoptr i64 280 to ptr
  %t2913 = getelementptr ptr, ptr %t2911, i32 0
  store ptr %t2912, ptr %t2913
  %t2914 = call ptr @v_lineMeasure()
  %t2915 = getelementptr ptr, ptr %t2910, i32 1
  %t2916 = load ptr, ptr %t2915
  call void @__inc_ref(ptr %t2916)
  %t2917 = getelementptr ptr, ptr %t4, i32 1
  %t2918 = load ptr, ptr %t2917
  call void @__free_recursive(ptr %t2918)
  %t2919 = getelementptr ptr, ptr %t4, i32 2
  %t2920 = load ptr, ptr %t2919
  call void @__free_recursive(ptr %t2920)
  %t2923 = inttoptr i64 103 to ptr
  %t2924 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t2923, ptr %t2924
  %t2921 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t2914, ptr %t2921
  %t2922 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t2916, ptr %t2922
  %t2925 = getelementptr ptr, ptr %t2911, i32 1
  store ptr %t4, ptr %t2925
  %t2926 = call ptr @__alloc(i64 16, i32 1)
  %t2927 = inttoptr i64 205 to ptr
  %t2928 = getelementptr ptr, ptr %t2926, i32 0
  store ptr %t2927, ptr %t2928
  call void @__inc_ref(ptr %t2897)
  %t2929 = getelementptr ptr, ptr %t2926, i32 1
  store ptr %t2897, ptr %t2929
  %t2930 = getelementptr ptr, ptr %t2911, i32 2
  store ptr %t2926, ptr %t2930
  call void @__free_recursive(ptr %t2910)
  call void @__free_recursive(ptr %t2897)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t2911, ptr %t3
  br label %tco.loop.0
tco.case.default.2901:
  unreachable
tco.case.arm.207.2931:
  %t2932 = getelementptr ptr, ptr %t11, i32 1
  %t2933 = load ptr, ptr %t2932
  call void @__inc_ref(ptr %t2933)
  %t2934 = call ptr @__alloc(i64 16, i32 1)
  %t2935 = inttoptr i64 12 to ptr
  %t2936 = getelementptr ptr, ptr %t2934, i32 0
  store ptr %t2935, ptr %t2936
  call void @__inc_ref(ptr %t13)
  %t2937 = getelementptr ptr, ptr %t2934, i32 1
  store ptr %t13, ptr %t2937
  %t2938 = getelementptr ptr, ptr %t4, i32 1
  %t2939 = load ptr, ptr %t2938
  call void @__free_recursive(ptr %t2939)
  %t2940 = getelementptr ptr, ptr %t4, i32 2
  %t2941 = load ptr, ptr %t2940
  call void @__free_recursive(ptr %t2941)
  %t2944 = inttoptr i64 279 to ptr
  %t2945 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t2944, ptr %t2945
  %t2942 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t2933, ptr %t2942
  %t2943 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t2934, ptr %t2943
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.206.2946:
  %t2947 = getelementptr ptr, ptr %t11, i32 1
  %t2948 = load ptr, ptr %t2947
  call void @__inc_ref(ptr %t2948)
  %t2949 = getelementptr ptr, ptr %t13, i32 0
  %t2950 = load ptr, ptr %t2949
  %t2951 = ptrtoint ptr %t2950 to i64
  switch i64 %t2951, label %tco.case.default.2952 [ i64 11, label %tco.case.arm.11.2953 i64 12, label %tco.case.arm.12.2959 ]
tco.case.arm.11.2953:
  %t2954 = getelementptr ptr, ptr %t4, i32 1
  %t2955 = load ptr, ptr %t2954
  call void @__free_recursive(ptr %t2955)
  %t2957 = inttoptr i64 279 to ptr
  %t2958 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t2957, ptr %t2958
  call void @__inc_ref(ptr %t2948)
  %t2956 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t2948, ptr %t2956
  call void @__free_recursive(ptr %t2948)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.12.2959:
  %t2960 = getelementptr ptr, ptr %t13, i32 1
  %t2961 = load ptr, ptr %t2960
  call void @__inc_ref(ptr %t2961)
  %t2962 = call ptr @__alloc(i64 24, i32 2)
  %t2963 = inttoptr i64 280 to ptr
  %t2964 = getelementptr ptr, ptr %t2962, i32 0
  store ptr %t2963, ptr %t2964
  %t2965 = call ptr @v_lineMeasure()
  %t2966 = getelementptr ptr, ptr %t2961, i32 1
  %t2967 = load ptr, ptr %t2966
  call void @__inc_ref(ptr %t2967)
  %t2968 = getelementptr ptr, ptr %t4, i32 1
  %t2969 = load ptr, ptr %t2968
  call void @__free_recursive(ptr %t2969)
  %t2970 = getelementptr ptr, ptr %t4, i32 2
  %t2971 = load ptr, ptr %t2970
  call void @__free_recursive(ptr %t2971)
  %t2974 = inttoptr i64 103 to ptr
  %t2975 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t2974, ptr %t2975
  %t2972 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t2965, ptr %t2972
  %t2973 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t2967, ptr %t2973
  %t2976 = getelementptr ptr, ptr %t2962, i32 1
  store ptr %t4, ptr %t2976
  %t2977 = call ptr @__alloc(i64 16, i32 1)
  %t2978 = inttoptr i64 207 to ptr
  %t2979 = getelementptr ptr, ptr %t2977, i32 0
  store ptr %t2978, ptr %t2979
  call void @__inc_ref(ptr %t2948)
  %t2980 = getelementptr ptr, ptr %t2977, i32 1
  store ptr %t2948, ptr %t2980
  %t2981 = getelementptr ptr, ptr %t2962, i32 2
  store ptr %t2977, ptr %t2981
  call void @__free_recursive(ptr %t2961)
  call void @__free_recursive(ptr %t2948)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t2962, ptr %t3
  br label %tco.loop.0
tco.case.default.2952:
  unreachable
tco.case.arm.208.2982:
  %t2983 = getelementptr ptr, ptr %t11, i32 1
  %t2984 = load ptr, ptr %t2983
  call void @__inc_ref(ptr %t2984)
  %t2985 = getelementptr ptr, ptr %t13, i32 0
  %t2986 = load ptr, ptr %t2985
  %t2987 = ptrtoint ptr %t2986 to i64
  switch i64 %t2987, label %case.default.2988 [ i64 3, label %case.arm.3.2990 i64 4, label %case.arm.4.2998 ]
case.arm.3.2990:
  %t2992 = call ptr @__alloc(i64 16, i32 1)
  %t2993 = inttoptr i64 6 to ptr
  %t2994 = getelementptr ptr, ptr %t2992, i32 0
  store ptr %t2993, ptr %t2994
  %t2995 = getelementptr ptr, ptr %t13, i32 1
  %t2996 = load ptr, ptr %t2995
  call void @__inc_ref(ptr %t2996)
  %t2997 = getelementptr ptr, ptr %t2992, i32 1
  store ptr %t2996, ptr %t2997
  br label %case.end.3.2991
case.end.3.2991:
  br label %case.join.2989
case.arm.4.2998:
  %t3000 = call ptr @__alloc(i64 16, i32 1)
  %t3001 = inttoptr i64 5 to ptr
  %t3002 = getelementptr ptr, ptr %t3000, i32 0
  store ptr %t3001, ptr %t3002
  %t3003 = getelementptr ptr, ptr %t13, i32 1
  %t3004 = load ptr, ptr %t3003
  call void @__inc_ref(ptr %t3004)
  %t3005 = getelementptr ptr, ptr %t3000, i32 1
  store ptr %t3004, ptr %t3005
  br label %case.end.4.2999
case.end.4.2999:
  br label %case.join.2989
case.default.2988:
  unreachable
case.join.2989:
  %t3006 = phi ptr [ %t2992, %case.end.3.2991 ], [ %t3000, %case.end.4.2999 ]
  %t3007 = getelementptr ptr, ptr %t4, i32 1
  %t3008 = load ptr, ptr %t3007
  call void @__free_recursive(ptr %t3008)
  %t3009 = getelementptr ptr, ptr %t4, i32 2
  %t3010 = load ptr, ptr %t3009
  call void @__free_recursive(ptr %t3010)
  %t3013 = inttoptr i64 279 to ptr
  %t3014 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t3013, ptr %t3014
  %t3011 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t2984, ptr %t3011
  %t3012 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t3006, ptr %t3012
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.209.3015:
  %t3016 = call ptr @__alloc(i64 32, i32 3)
  %t3017 = inttoptr i64 90 to ptr
  %t3018 = getelementptr ptr, ptr %t3016, i32 0
  store ptr %t3017, ptr %t3018
  %t3019 = getelementptr ptr, ptr %t11, i32 2
  %t3020 = load ptr, ptr %t3019
  call void @__inc_ref(ptr %t3020)
  %t3021 = getelementptr ptr, ptr %t3016, i32 1
  store ptr %t3020, ptr %t3021
  %t3022 = getelementptr ptr, ptr %t11, i32 3
  %t3023 = load ptr, ptr %t3022
  call void @__inc_ref(ptr %t3023)
  %t3024 = getelementptr ptr, ptr %t3016, i32 2
  store ptr %t3023, ptr %t3024
  call void @__inc_ref(ptr %t13)
  %t3025 = getelementptr ptr, ptr %t3016, i32 3
  store ptr %t13, ptr %t3025
  %t3026 = getelementptr ptr, ptr %t11, i32 1
  %t3027 = load ptr, ptr %t3026
  call void @__inc_ref(ptr %t3027)
  %t3028 = getelementptr ptr, ptr %t4, i32 1
  %t3029 = load ptr, ptr %t3028
  call void @__free_recursive(ptr %t3029)
  %t3030 = getelementptr ptr, ptr %t4, i32 2
  %t3031 = load ptr, ptr %t3030
  call void @__free_recursive(ptr %t3031)
  %t3034 = inttoptr i64 280 to ptr
  %t3035 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t3034, ptr %t3035
  %t3032 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t3016, ptr %t3032
  %t3033 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t3027, ptr %t3033
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.210.3036:
  %t3037 = call ptr @__alloc(i64 32, i32 3)
  %t3038 = inttoptr i64 114 to ptr
  %t3039 = getelementptr ptr, ptr %t3037, i32 0
  store ptr %t3038, ptr %t3039
  %t3040 = getelementptr ptr, ptr %t11, i32 2
  %t3041 = load ptr, ptr %t3040
  call void @__inc_ref(ptr %t3041)
  %t3042 = getelementptr ptr, ptr %t3037, i32 1
  store ptr %t3041, ptr %t3042
  call void @__inc_ref(ptr %t13)
  %t3043 = getelementptr ptr, ptr %t3037, i32 2
  store ptr %t13, ptr %t3043
  %t3044 = getelementptr ptr, ptr %t11, i32 3
  %t3045 = load ptr, ptr %t3044
  call void @__inc_ref(ptr %t3045)
  %t3046 = getelementptr ptr, ptr %t3037, i32 3
  store ptr %t3045, ptr %t3046
  %t3047 = getelementptr ptr, ptr %t11, i32 1
  %t3048 = load ptr, ptr %t3047
  call void @__inc_ref(ptr %t3048)
  %t3049 = getelementptr ptr, ptr %t4, i32 1
  %t3050 = load ptr, ptr %t3049
  call void @__free_recursive(ptr %t3050)
  %t3051 = getelementptr ptr, ptr %t4, i32 2
  %t3052 = load ptr, ptr %t3051
  call void @__free_recursive(ptr %t3052)
  %t3055 = inttoptr i64 280 to ptr
  %t3056 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t3055, ptr %t3056
  %t3053 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t3037, ptr %t3053
  %t3054 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t3048, ptr %t3054
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.212.3057:
  %t3058 = call ptr @__alloc(i64 40, i32 4)
  %t3059 = inttoptr i64 92 to ptr
  %t3060 = getelementptr ptr, ptr %t3058, i32 0
  store ptr %t3059, ptr %t3060
  %t3061 = getelementptr ptr, ptr %t11, i32 2
  %t3062 = load ptr, ptr %t3061
  call void @__inc_ref(ptr %t3062)
  %t3063 = getelementptr ptr, ptr %t3058, i32 1
  store ptr %t3062, ptr %t3063
  %t3064 = getelementptr ptr, ptr %t11, i32 3
  %t3065 = load ptr, ptr %t3064
  call void @__inc_ref(ptr %t3065)
  %t3066 = getelementptr ptr, ptr %t3058, i32 2
  store ptr %t3065, ptr %t3066
  call void @__inc_ref(ptr %t13)
  %t3067 = getelementptr ptr, ptr %t3058, i32 3
  store ptr %t13, ptr %t3067
  %t3068 = getelementptr ptr, ptr %t11, i32 4
  %t3069 = load ptr, ptr %t3068
  call void @__inc_ref(ptr %t3069)
  %t3070 = getelementptr ptr, ptr %t3058, i32 4
  store ptr %t3069, ptr %t3070
  %t3071 = getelementptr ptr, ptr %t11, i32 1
  %t3072 = load ptr, ptr %t3071
  call void @__inc_ref(ptr %t3072)
  %t3073 = getelementptr ptr, ptr %t4, i32 1
  %t3074 = load ptr, ptr %t3073
  call void @__free_recursive(ptr %t3074)
  %t3075 = getelementptr ptr, ptr %t4, i32 2
  %t3076 = load ptr, ptr %t3075
  call void @__free_recursive(ptr %t3076)
  %t3079 = inttoptr i64 280 to ptr
  %t3080 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t3079, ptr %t3080
  %t3077 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t3058, ptr %t3077
  %t3078 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t3072, ptr %t3078
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.211.3081:
  %t3082 = getelementptr ptr, ptr %t11, i32 2
  %t3083 = load ptr, ptr %t3082
  call void @__inc_ref(ptr %t3083)
  %t3084 = call ptr @__alloc(i64 40, i32 4)
  %t3085 = inttoptr i64 85 to ptr
  %t3086 = getelementptr ptr, ptr %t3084, i32 0
  store ptr %t3085, ptr %t3086
  %t3087 = call ptr @__alloc(i64 32, i32 3)
  %t3088 = inttoptr i64 33 to ptr
  %t3089 = getelementptr ptr, ptr %t3087, i32 0
  store ptr %t3088, ptr %t3089
  %t3090 = call ptr @__alloc(i64 8, i32 0)
  %t3091 = inttoptr i64 49 to ptr
  %t3092 = getelementptr ptr, ptr %t3090, i32 0
  store ptr %t3091, ptr %t3092
  %t3093 = getelementptr ptr, ptr %t3087, i32 1
  store ptr %t3090, ptr %t3093
  %t3094 = getelementptr ptr, ptr %t3083, i32 2
  %t3095 = load ptr, ptr %t3094
  call void @__inc_ref(ptr %t3095)
  %t3096 = getelementptr ptr, ptr %t3087, i32 2
  store ptr %t3095, ptr %t3096
  %t3097 = getelementptr ptr, ptr %t3083, i32 3
  %t3098 = load ptr, ptr %t3097
  call void @__inc_ref(ptr %t3098)
  %t3099 = getelementptr ptr, ptr %t3087, i32 3
  store ptr %t3098, ptr %t3099
  %t3100 = getelementptr ptr, ptr %t3084, i32 1
  store ptr %t3087, ptr %t3100
  %t3101 = getelementptr ptr, ptr %t11, i32 3
  %t3102 = load ptr, ptr %t3101
  call void @__inc_ref(ptr %t3102)
  %t3103 = getelementptr ptr, ptr %t3084, i32 2
  store ptr %t3102, ptr %t3103
  call void @__inc_ref(ptr %t13)
  %t3104 = getelementptr ptr, ptr %t3084, i32 3
  store ptr %t13, ptr %t3104
  %t3105 = getelementptr ptr, ptr %t11, i32 4
  %t3106 = load ptr, ptr %t3105
  call void @__inc_ref(ptr %t3106)
  %t3107 = getelementptr ptr, ptr %t3084, i32 4
  store ptr %t3106, ptr %t3107
  %t3108 = call ptr @__alloc(i64 40, i32 4)
  %t3109 = inttoptr i64 212 to ptr
  %t3110 = getelementptr ptr, ptr %t3108, i32 0
  store ptr %t3109, ptr %t3110
  %t3111 = getelementptr ptr, ptr %t11, i32 1
  %t3112 = load ptr, ptr %t3111
  call void @__inc_ref(ptr %t3112)
  %t3113 = getelementptr ptr, ptr %t3108, i32 1
  store ptr %t3112, ptr %t3113
  call void @__inc_ref(ptr %t3083)
  %t3114 = getelementptr ptr, ptr %t3108, i32 2
  store ptr %t3083, ptr %t3114
  %t3115 = getelementptr ptr, ptr %t11, i32 5
  %t3116 = load ptr, ptr %t3115
  call void @__inc_ref(ptr %t3116)
  %t3117 = getelementptr ptr, ptr %t3108, i32 3
  store ptr %t3116, ptr %t3117
  %t3118 = getelementptr ptr, ptr %t11, i32 6
  %t3119 = load ptr, ptr %t3118
  call void @__inc_ref(ptr %t3119)
  %t3120 = getelementptr ptr, ptr %t3108, i32 4
  store ptr %t3119, ptr %t3120
  %t3121 = getelementptr ptr, ptr %t4, i32 1
  %t3122 = load ptr, ptr %t3121
  call void @__free_recursive(ptr %t3122)
  %t3123 = getelementptr ptr, ptr %t4, i32 2
  %t3124 = load ptr, ptr %t3123
  call void @__free_recursive(ptr %t3124)
  %t3127 = inttoptr i64 280 to ptr
  %t3128 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t3127, ptr %t3128
  %t3125 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t3084, ptr %t3125
  %t3126 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t3108, ptr %t3126
  call void @__free_recursive(ptr %t3083)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.213.3129:
  %t3130 = call ptr @__alloc(i64 32, i32 3)
  %t3131 = inttoptr i64 113 to ptr
  %t3132 = getelementptr ptr, ptr %t3130, i32 0
  store ptr %t3131, ptr %t3132
  call void @__inc_ref(ptr %t13)
  %t3133 = getelementptr ptr, ptr %t3130, i32 1
  store ptr %t13, ptr %t3133
  %t3134 = getelementptr ptr, ptr %t11, i32 2
  %t3135 = load ptr, ptr %t3134
  call void @__inc_ref(ptr %t3135)
  %t3136 = call ptr @__alloc(i64 8, i32 0)
  %t3137 = inttoptr i64 120 to ptr
  %t3138 = getelementptr ptr, ptr %t3136, i32 0
  store ptr %t3137, ptr %t3138
  %t3139 = call ptr @v_$cps$splitAll(ptr getelementptr inbounds (i8, ptr @.str.7, i64 12), ptr %t3135, ptr %t3136)
  %t3140 = getelementptr ptr, ptr %t3130, i32 2
  store ptr %t3139, ptr %t3140
  %t3141 = getelementptr ptr, ptr %t3130, i32 3
  store ptr getelementptr inbounds (i8, ptr @.str.8, i64 12), ptr %t3141
  %t3142 = getelementptr ptr, ptr %t11, i32 1
  %t3143 = load ptr, ptr %t3142
  call void @__inc_ref(ptr %t3143)
  %t3144 = getelementptr ptr, ptr %t4, i32 1
  %t3145 = load ptr, ptr %t3144
  call void @__free_recursive(ptr %t3145)
  %t3146 = getelementptr ptr, ptr %t4, i32 2
  %t3147 = load ptr, ptr %t3146
  call void @__free_recursive(ptr %t3147)
  %t3150 = inttoptr i64 280 to ptr
  %t3151 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t3150, ptr %t3151
  %t3148 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t3130, ptr %t3148
  %t3149 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t3143, ptr %t3149
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.215.3152:
  %t3153 = call ptr @__alloc(i64 24, i32 2)
  %t3154 = inttoptr i64 280 to ptr
  %t3155 = getelementptr ptr, ptr %t3153, i32 0
  store ptr %t3154, ptr %t3155
  %t3156 = call ptr @__alloc(i64 40, i32 4)
  %t3157 = inttoptr i64 92 to ptr
  %t3158 = getelementptr ptr, ptr %t3156, i32 0
  store ptr %t3157, ptr %t3158
  %t3159 = getelementptr ptr, ptr %t11, i32 3
  %t3160 = load ptr, ptr %t3159
  call void @__inc_ref(ptr %t3160)
  %t3161 = getelementptr ptr, ptr %t3156, i32 1
  store ptr %t3160, ptr %t3161
  %t3162 = getelementptr ptr, ptr %t11, i32 5
  %t3163 = load ptr, ptr %t3162
  call void @__inc_ref(ptr %t3163)
  %t3164 = getelementptr ptr, ptr %t11, i32 2
  %t3165 = load ptr, ptr %t3164
  call void @__inc_ref(ptr %t3165)
  %t3166 = getelementptr ptr, ptr %t4, i32 1
  %t3167 = load ptr, ptr %t3166
  call void @__free_recursive(ptr %t3167)
  %t3168 = getelementptr ptr, ptr %t4, i32 2
  %t3169 = load ptr, ptr %t3168
  call void @__free_recursive(ptr %t3169)
  %t3172 = inttoptr i64 25 to ptr
  %t3173 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t3172, ptr %t3173
  %t3170 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t3163, ptr %t3170
  %t3171 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t3165, ptr %t3171
  %t3174 = getelementptr ptr, ptr %t3156, i32 2
  store ptr %t4, ptr %t3174
  call void @__inc_ref(ptr %t13)
  %t3175 = getelementptr ptr, ptr %t3156, i32 3
  store ptr %t13, ptr %t3175
  %t3176 = getelementptr ptr, ptr %t11, i32 4
  %t3177 = load ptr, ptr %t3176
  call void @__inc_ref(ptr %t3177)
  %t3178 = getelementptr ptr, ptr %t3156, i32 4
  store ptr %t3177, ptr %t3178
  %t3179 = getelementptr ptr, ptr %t3153, i32 1
  store ptr %t3156, ptr %t3179
  %t3180 = getelementptr ptr, ptr %t11, i32 1
  %t3181 = load ptr, ptr %t3180
  call void @__inc_ref(ptr %t3181)
  %t3182 = getelementptr ptr, ptr %t3153, i32 2
  store ptr %t3181, ptr %t3182
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t3153, ptr %t3
  br label %tco.loop.0
tco.case.arm.214.3183:
  %t3184 = getelementptr ptr, ptr %t11, i32 3
  %t3185 = load ptr, ptr %t3184
  call void @__inc_ref(ptr %t3185)
  %t3186 = call ptr @__alloc(i64 32, i32 3)
  %t3187 = inttoptr i64 90 to ptr
  %t3188 = getelementptr ptr, ptr %t3186, i32 0
  store ptr %t3187, ptr %t3188
  %t3189 = call ptr @__alloc(i64 32, i32 3)
  %t3190 = inttoptr i64 33 to ptr
  %t3191 = getelementptr ptr, ptr %t3189, i32 0
  store ptr %t3190, ptr %t3191
  %t3192 = call ptr @__alloc(i64 8, i32 0)
  %t3193 = inttoptr i64 49 to ptr
  %t3194 = getelementptr ptr, ptr %t3192, i32 0
  store ptr %t3193, ptr %t3194
  %t3195 = getelementptr ptr, ptr %t3189, i32 1
  store ptr %t3192, ptr %t3195
  %t3196 = getelementptr ptr, ptr %t3185, i32 2
  %t3197 = load ptr, ptr %t3196
  call void @__inc_ref(ptr %t3197)
  %t3198 = getelementptr ptr, ptr %t3189, i32 2
  store ptr %t3197, ptr %t3198
  %t3199 = getelementptr ptr, ptr %t3185, i32 3
  %t3200 = load ptr, ptr %t3199
  call void @__inc_ref(ptr %t3200)
  %t3201 = getelementptr ptr, ptr %t3189, i32 3
  store ptr %t3200, ptr %t3201
  %t3202 = getelementptr ptr, ptr %t3186, i32 1
  store ptr %t3189, ptr %t3202
  call void @__inc_ref(ptr %t13)
  %t3203 = getelementptr ptr, ptr %t3186, i32 2
  store ptr %t13, ptr %t3203
  %t3204 = getelementptr ptr, ptr %t11, i32 4
  %t3205 = load ptr, ptr %t3204
  call void @__inc_ref(ptr %t3205)
  %t3206 = getelementptr ptr, ptr %t3186, i32 3
  store ptr %t3205, ptr %t3206
  %t3207 = call ptr @__alloc(i64 48, i32 5)
  %t3208 = inttoptr i64 215 to ptr
  %t3209 = getelementptr ptr, ptr %t3207, i32 0
  store ptr %t3208, ptr %t3209
  %t3210 = getelementptr ptr, ptr %t11, i32 1
  %t3211 = load ptr, ptr %t3210
  call void @__inc_ref(ptr %t3211)
  %t3212 = getelementptr ptr, ptr %t3207, i32 1
  store ptr %t3211, ptr %t3212
  %t3213 = getelementptr ptr, ptr %t11, i32 2
  %t3214 = load ptr, ptr %t3213
  call void @__inc_ref(ptr %t3214)
  %t3215 = getelementptr ptr, ptr %t3207, i32 2
  store ptr %t3214, ptr %t3215
  call void @__inc_ref(ptr %t3185)
  %t3216 = getelementptr ptr, ptr %t3207, i32 3
  store ptr %t3185, ptr %t3216
  %t3217 = getelementptr ptr, ptr %t11, i32 5
  %t3218 = load ptr, ptr %t3217
  call void @__inc_ref(ptr %t3218)
  %t3219 = getelementptr ptr, ptr %t3207, i32 4
  store ptr %t3218, ptr %t3219
  %t3220 = getelementptr ptr, ptr %t11, i32 6
  %t3221 = load ptr, ptr %t3220
  call void @__inc_ref(ptr %t3221)
  %t3222 = getelementptr ptr, ptr %t3207, i32 5
  store ptr %t3221, ptr %t3222
  %t3223 = getelementptr ptr, ptr %t4, i32 1
  %t3224 = load ptr, ptr %t3223
  call void @__free_recursive(ptr %t3224)
  %t3225 = getelementptr ptr, ptr %t4, i32 2
  %t3226 = load ptr, ptr %t3225
  call void @__free_recursive(ptr %t3226)
  %t3229 = inttoptr i64 280 to ptr
  %t3230 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t3229, ptr %t3230
  %t3227 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t3186, ptr %t3227
  %t3228 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t3207, ptr %t3228
  call void @__free_recursive(ptr %t3185)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.216.3231:
  %t3232 = call ptr @__alloc(i64 32, i32 3)
  %t3233 = inttoptr i64 90 to ptr
  %t3234 = getelementptr ptr, ptr %t3232, i32 0
  store ptr %t3233, ptr %t3234
  %t3235 = getelementptr ptr, ptr %t11, i32 2
  %t3236 = load ptr, ptr %t3235
  call void @__inc_ref(ptr %t3236)
  %t3237 = getelementptr ptr, ptr %t3232, i32 1
  store ptr %t3236, ptr %t3237
  %t3238 = getelementptr ptr, ptr %t11, i32 3
  %t3239 = load ptr, ptr %t3238
  call void @__inc_ref(ptr %t3239)
  %t3240 = getelementptr ptr, ptr %t3232, i32 2
  store ptr %t3239, ptr %t3240
  call void @__inc_ref(ptr %t13)
  %t3241 = getelementptr ptr, ptr %t3232, i32 3
  store ptr %t13, ptr %t3241
  %t3242 = getelementptr ptr, ptr %t11, i32 1
  %t3243 = load ptr, ptr %t3242
  call void @__inc_ref(ptr %t3243)
  %t3244 = getelementptr ptr, ptr %t4, i32 1
  %t3245 = load ptr, ptr %t3244
  call void @__free_recursive(ptr %t3245)
  %t3246 = getelementptr ptr, ptr %t4, i32 2
  %t3247 = load ptr, ptr %t3246
  call void @__free_recursive(ptr %t3247)
  %t3250 = inttoptr i64 280 to ptr
  %t3251 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t3250, ptr %t3251
  %t3248 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t3232, ptr %t3248
  %t3249 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t3243, ptr %t3249
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.221.3252:
  %t3253 = getelementptr ptr, ptr %t11, i32 1
  %t3254 = load ptr, ptr %t3253
  call void @__inc_ref(ptr %t3254)
  %t3255 = call ptr @__alloc(i64 40, i32 4)
  %t3256 = inttoptr i64 32 to ptr
  %t3257 = getelementptr ptr, ptr %t3255, i32 0
  store ptr %t3256, ptr %t3257
  call void @__inc_ref(ptr %t13)
  %t3258 = getelementptr ptr, ptr %t3255, i32 1
  store ptr %t13, ptr %t3258
  %t3259 = getelementptr ptr, ptr %t11, i32 3
  %t3260 = load ptr, ptr %t3259
  call void @__inc_ref(ptr %t3260)
  %t3261 = getelementptr ptr, ptr %t3255, i32 2
  store ptr %t3260, ptr %t3261
  %t3262 = getelementptr ptr, ptr %t11, i32 2
  %t3263 = load ptr, ptr %t3262
  call void @__inc_ref(ptr %t3263)
  %t3264 = getelementptr ptr, ptr %t3255, i32 3
  store ptr %t3263, ptr %t3264
  %t3265 = getelementptr ptr, ptr %t11, i32 4
  %t3266 = load ptr, ptr %t3265
  call void @__inc_ref(ptr %t3266)
  %t3267 = getelementptr ptr, ptr %t3255, i32 4
  store ptr %t3266, ptr %t3267
  %t3268 = getelementptr ptr, ptr %t4, i32 1
  %t3269 = load ptr, ptr %t3268
  call void @__free_recursive(ptr %t3269)
  %t3270 = getelementptr ptr, ptr %t4, i32 2
  %t3271 = load ptr, ptr %t3270
  call void @__free_recursive(ptr %t3271)
  %t3274 = inttoptr i64 279 to ptr
  %t3275 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t3274, ptr %t3275
  %t3272 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t3254, ptr %t3272
  %t3273 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t3255, ptr %t3273
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.220.3276:
  %t3277 = call ptr @__alloc(i64 32, i32 3)
  %t3278 = inttoptr i64 88 to ptr
  %t3279 = getelementptr ptr, ptr %t3277, i32 0
  store ptr %t3278, ptr %t3279
  %t3280 = getelementptr ptr, ptr %t11, i32 3
  %t3281 = load ptr, ptr %t3280
  call void @__inc_ref(ptr %t3281)
  %t3282 = getelementptr ptr, ptr %t3277, i32 1
  store ptr %t3281, ptr %t3282
  %t3283 = getelementptr ptr, ptr %t11, i32 2
  %t3284 = load ptr, ptr %t3283
  call void @__inc_ref(ptr %t3284)
  %t3285 = getelementptr ptr, ptr %t3277, i32 2
  store ptr %t3284, ptr %t3285
  call void @__inc_ref(ptr %t13)
  %t3286 = getelementptr ptr, ptr %t3277, i32 3
  store ptr %t13, ptr %t3286
  %t3287 = call ptr @__alloc(i64 40, i32 4)
  %t3288 = inttoptr i64 221 to ptr
  %t3289 = getelementptr ptr, ptr %t3287, i32 0
  store ptr %t3288, ptr %t3289
  %t3290 = getelementptr ptr, ptr %t11, i32 1
  %t3291 = load ptr, ptr %t3290
  call void @__inc_ref(ptr %t3291)
  %t3292 = getelementptr ptr, ptr %t3287, i32 1
  store ptr %t3291, ptr %t3292
  %t3293 = getelementptr ptr, ptr %t11, i32 4
  %t3294 = load ptr, ptr %t3293
  call void @__inc_ref(ptr %t3294)
  %t3295 = getelementptr ptr, ptr %t3287, i32 2
  store ptr %t3294, ptr %t3295
  %t3296 = getelementptr ptr, ptr %t11, i32 5
  %t3297 = load ptr, ptr %t3296
  call void @__inc_ref(ptr %t3297)
  %t3298 = getelementptr ptr, ptr %t3287, i32 3
  store ptr %t3297, ptr %t3298
  %t3299 = getelementptr ptr, ptr %t11, i32 6
  %t3300 = load ptr, ptr %t3299
  call void @__inc_ref(ptr %t3300)
  %t3301 = getelementptr ptr, ptr %t3287, i32 4
  store ptr %t3300, ptr %t3301
  %t3302 = getelementptr ptr, ptr %t4, i32 1
  %t3303 = load ptr, ptr %t3302
  call void @__free_recursive(ptr %t3303)
  %t3304 = getelementptr ptr, ptr %t4, i32 2
  %t3305 = load ptr, ptr %t3304
  call void @__free_recursive(ptr %t3305)
  %t3308 = inttoptr i64 280 to ptr
  %t3309 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t3308, ptr %t3309
  %t3306 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t3277, ptr %t3306
  %t3307 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t3287, ptr %t3307
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.219.3310:
  %t3311 = getelementptr ptr, ptr %t11, i32 4
  %t3312 = load ptr, ptr %t3311
  call void @__inc_ref(ptr %t3312)
  %t3313 = call ptr @__alloc(i64 32, i32 3)
  %t3314 = inttoptr i64 88 to ptr
  %t3315 = getelementptr ptr, ptr %t3313, i32 0
  store ptr %t3314, ptr %t3315
  call void @__inc_ref(ptr %t3312)
  %t3316 = getelementptr ptr, ptr %t3313, i32 1
  store ptr %t3312, ptr %t3316
  %t3317 = getelementptr ptr, ptr %t11, i32 3
  %t3318 = load ptr, ptr %t3317
  call void @__inc_ref(ptr %t3318)
  %t3319 = getelementptr ptr, ptr %t3313, i32 2
  store ptr %t3318, ptr %t3319
  call void @__inc_ref(ptr %t13)
  %t3320 = getelementptr ptr, ptr %t3313, i32 3
  store ptr %t13, ptr %t3320
  %t3321 = call ptr @__alloc(i64 56, i32 6)
  %t3322 = inttoptr i64 220 to ptr
  %t3323 = getelementptr ptr, ptr %t3321, i32 0
  store ptr %t3322, ptr %t3323
  %t3324 = getelementptr ptr, ptr %t11, i32 1
  %t3325 = load ptr, ptr %t3324
  call void @__inc_ref(ptr %t3325)
  %t3326 = getelementptr ptr, ptr %t3321, i32 1
  store ptr %t3325, ptr %t3326
  %t3327 = getelementptr ptr, ptr %t11, i32 2
  %t3328 = load ptr, ptr %t3327
  call void @__inc_ref(ptr %t3328)
  %t3329 = getelementptr ptr, ptr %t3321, i32 2
  store ptr %t3328, ptr %t3329
  call void @__inc_ref(ptr %t3312)
  %t3330 = getelementptr ptr, ptr %t3321, i32 3
  store ptr %t3312, ptr %t3330
  %t3331 = getelementptr ptr, ptr %t11, i32 5
  %t3332 = load ptr, ptr %t3331
  call void @__inc_ref(ptr %t3332)
  %t3333 = getelementptr ptr, ptr %t3321, i32 4
  store ptr %t3332, ptr %t3333
  %t3334 = getelementptr ptr, ptr %t11, i32 6
  %t3335 = load ptr, ptr %t3334
  call void @__inc_ref(ptr %t3335)
  %t3336 = getelementptr ptr, ptr %t3321, i32 5
  store ptr %t3335, ptr %t3336
  %t3337 = getelementptr ptr, ptr %t11, i32 7
  %t3338 = load ptr, ptr %t3337
  call void @__inc_ref(ptr %t3338)
  %t3339 = getelementptr ptr, ptr %t3321, i32 6
  store ptr %t3338, ptr %t3339
  %t3340 = getelementptr ptr, ptr %t4, i32 1
  %t3341 = load ptr, ptr %t3340
  call void @__free_recursive(ptr %t3341)
  %t3342 = getelementptr ptr, ptr %t4, i32 2
  %t3343 = load ptr, ptr %t3342
  call void @__free_recursive(ptr %t3343)
  %t3346 = inttoptr i64 280 to ptr
  %t3347 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t3346, ptr %t3347
  %t3344 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t3313, ptr %t3344
  %t3345 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t3321, ptr %t3345
  call void @__free_recursive(ptr %t3312)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.218.3348:
  %t3349 = getelementptr ptr, ptr %t11, i32 3
  %t3350 = load ptr, ptr %t3349
  call void @__inc_ref(ptr %t3350)
  %t3351 = getelementptr ptr, ptr %t11, i32 6
  %t3352 = load ptr, ptr %t3351
  call void @__inc_ref(ptr %t3352)
  %t3353 = call ptr @__alloc(i64 24, i32 2)
  %t3354 = inttoptr i64 280 to ptr
  %t3355 = getelementptr ptr, ptr %t3353, i32 0
  store ptr %t3354, ptr %t3355
  %t3356 = getelementptr ptr, ptr %t4, i32 1
  %t3357 = load ptr, ptr %t3356
  call void @__free_recursive(ptr %t3357)
  %t3358 = getelementptr ptr, ptr %t4, i32 2
  %t3359 = load ptr, ptr %t3358
  call void @__free_recursive(ptr %t3359)
  %t3362 = inttoptr i64 102 to ptr
  %t3363 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t3362, ptr %t3363
  call void @__inc_ref(ptr %t3350)
  %t3360 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t3350, ptr %t3360
  call void @__inc_ref(ptr %t3352)
  %t3361 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t3352, ptr %t3361
  %t3364 = getelementptr ptr, ptr %t3353, i32 1
  store ptr %t4, ptr %t3364
  %t3365 = call ptr @__alloc(i64 64, i32 7)
  %t3366 = inttoptr i64 219 to ptr
  %t3367 = getelementptr ptr, ptr %t3365, i32 0
  store ptr %t3366, ptr %t3367
  %t3368 = getelementptr ptr, ptr %t11, i32 1
  %t3369 = load ptr, ptr %t3368
  call void @__inc_ref(ptr %t3369)
  %t3370 = getelementptr ptr, ptr %t3365, i32 1
  store ptr %t3369, ptr %t3370
  %t3371 = getelementptr ptr, ptr %t11, i32 2
  %t3372 = load ptr, ptr %t3371
  call void @__inc_ref(ptr %t3372)
  %t3373 = getelementptr ptr, ptr %t3365, i32 2
  store ptr %t3372, ptr %t3373
  call void @__inc_ref(ptr %t13)
  %t3374 = getelementptr ptr, ptr %t3365, i32 3
  store ptr %t13, ptr %t3374
  call void @__inc_ref(ptr %t3350)
  %t3375 = getelementptr ptr, ptr %t3365, i32 4
  store ptr %t3350, ptr %t3375
  %t3376 = getelementptr ptr, ptr %t11, i32 4
  %t3377 = load ptr, ptr %t3376
  call void @__inc_ref(ptr %t3377)
  %t3378 = getelementptr ptr, ptr %t3365, i32 5
  store ptr %t3377, ptr %t3378
  %t3379 = getelementptr ptr, ptr %t11, i32 5
  %t3380 = load ptr, ptr %t3379
  call void @__inc_ref(ptr %t3380)
  %t3381 = getelementptr ptr, ptr %t3365, i32 6
  store ptr %t3380, ptr %t3381
  call void @__inc_ref(ptr %t3352)
  %t3382 = getelementptr ptr, ptr %t3365, i32 7
  store ptr %t3352, ptr %t3382
  %t3383 = getelementptr ptr, ptr %t3353, i32 2
  store ptr %t3365, ptr %t3383
  call void @__free_recursive(ptr %t3352)
  call void @__free_recursive(ptr %t3350)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t3353, ptr %t3
  br label %tco.loop.0
tco.case.arm.217.3384:
  %t3385 = getelementptr ptr, ptr %t11, i32 2
  %t3386 = load ptr, ptr %t3385
  call void @__inc_ref(ptr %t3386)
  %t3387 = getelementptr ptr, ptr %t11, i32 3
  %t3388 = load ptr, ptr %t3387
  call void @__inc_ref(ptr %t3388)
  %t3389 = call ptr @__alloc(i64 24, i32 2)
  %t3390 = inttoptr i64 280 to ptr
  %t3391 = getelementptr ptr, ptr %t3389, i32 0
  store ptr %t3390, ptr %t3391
  %t3392 = call ptr @__alloc(i64 32, i32 3)
  %t3393 = inttoptr i64 33 to ptr
  %t3394 = getelementptr ptr, ptr %t3392, i32 0
  store ptr %t3393, ptr %t3394
  %t3395 = call ptr @__alloc(i64 8, i32 0)
  %t3396 = inttoptr i64 49 to ptr
  %t3397 = getelementptr ptr, ptr %t3395, i32 0
  store ptr %t3396, ptr %t3397
  %t3398 = getelementptr ptr, ptr %t3392, i32 1
  store ptr %t3395, ptr %t3398
  %t3399 = getelementptr ptr, ptr %t3386, i32 2
  %t3400 = load ptr, ptr %t3399
  call void @__inc_ref(ptr %t3400)
  %t3401 = getelementptr ptr, ptr %t3392, i32 2
  store ptr %t3400, ptr %t3401
  %t3402 = getelementptr ptr, ptr %t3386, i32 3
  %t3403 = load ptr, ptr %t3402
  call void @__inc_ref(ptr %t3403)
  %t3404 = getelementptr ptr, ptr %t3392, i32 3
  store ptr %t3403, ptr %t3404
  %t3405 = getelementptr ptr, ptr %t4, i32 1
  %t3406 = load ptr, ptr %t3405
  call void @__free_recursive(ptr %t3406)
  %t3407 = getelementptr ptr, ptr %t4, i32 2
  %t3408 = load ptr, ptr %t3407
  call void @__free_recursive(ptr %t3408)
  %t3411 = inttoptr i64 103 to ptr
  %t3412 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t3411, ptr %t3412
  %t3409 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t3392, ptr %t3409
  call void @__inc_ref(ptr %t3388)
  %t3410 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t3388, ptr %t3410
  %t3413 = getelementptr ptr, ptr %t3389, i32 1
  store ptr %t4, ptr %t3413
  %t3414 = call ptr @__alloc(i64 56, i32 6)
  %t3415 = inttoptr i64 218 to ptr
  %t3416 = getelementptr ptr, ptr %t3414, i32 0
  store ptr %t3415, ptr %t3416
  %t3417 = getelementptr ptr, ptr %t11, i32 1
  %t3418 = load ptr, ptr %t3417
  call void @__inc_ref(ptr %t3418)
  %t3419 = getelementptr ptr, ptr %t3414, i32 1
  store ptr %t3418, ptr %t3419
  call void @__inc_ref(ptr %t13)
  %t3420 = getelementptr ptr, ptr %t3414, i32 2
  store ptr %t13, ptr %t3420
  call void @__inc_ref(ptr %t3386)
  %t3421 = getelementptr ptr, ptr %t3414, i32 3
  store ptr %t3386, ptr %t3421
  call void @__inc_ref(ptr %t3388)
  %t3422 = getelementptr ptr, ptr %t3414, i32 4
  store ptr %t3388, ptr %t3422
  %t3423 = getelementptr ptr, ptr %t11, i32 4
  %t3424 = load ptr, ptr %t3423
  call void @__inc_ref(ptr %t3424)
  %t3425 = getelementptr ptr, ptr %t3414, i32 5
  store ptr %t3424, ptr %t3425
  %t3426 = getelementptr ptr, ptr %t11, i32 5
  %t3427 = load ptr, ptr %t3426
  call void @__inc_ref(ptr %t3427)
  %t3428 = getelementptr ptr, ptr %t3414, i32 6
  store ptr %t3427, ptr %t3428
  %t3429 = getelementptr ptr, ptr %t3389, i32 2
  store ptr %t3414, ptr %t3429
  call void @__free_recursive(ptr %t3388)
  call void @__free_recursive(ptr %t3386)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t3389, ptr %t3
  br label %tco.loop.0
tco.case.arm.222.3430:
  %t3431 = getelementptr ptr, ptr %t11, i32 1
  %t3432 = load ptr, ptr %t3431
  call void @__inc_ref(ptr %t3432)
  %t3433 = getelementptr ptr, ptr %t11, i32 2
  %t3434 = load ptr, ptr %t3433
  call void @__inc_ref(ptr %t3434)
  %t3435 = getelementptr ptr, ptr %t11, i32 3
  %t3436 = load ptr, ptr %t3435
  call void @__inc_ref(ptr %t3436)
  %t3437 = getelementptr ptr, ptr %t13, i32 0
  %t3438 = load ptr, ptr %t3437
  %t3439 = ptrtoint ptr %t3438 to i64
  switch i64 %t3439, label %tco.case.default.3440 [ i64 11, label %tco.case.arm.11.3441 i64 12, label %tco.case.arm.12.3455 ]
tco.case.arm.11.3441:
  %t3442 = call ptr @__alloc(i64 24, i32 2)
  %t3443 = inttoptr i64 280 to ptr
  %t3444 = getelementptr ptr, ptr %t3442, i32 0
  store ptr %t3443, ptr %t3444
  %t3445 = getelementptr ptr, ptr %t4, i32 1
  %t3446 = load ptr, ptr %t3445
  call void @__free_recursive(ptr %t3446)
  %t3447 = getelementptr ptr, ptr %t4, i32 2
  %t3448 = load ptr, ptr %t3447
  call void @__free_recursive(ptr %t3448)
  %t3451 = inttoptr i64 96 to ptr
  %t3452 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t3451, ptr %t3452
  call void @__inc_ref(ptr %t3434)
  %t3449 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t3434, ptr %t3449
  call void @__inc_ref(ptr %t3436)
  %t3450 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t3436, ptr %t3450
  %t3453 = getelementptr ptr, ptr %t3442, i32 1
  store ptr %t4, ptr %t3453
  call void @__inc_ref(ptr %t3432)
  %t3454 = getelementptr ptr, ptr %t3442, i32 2
  store ptr %t3432, ptr %t3454
  call void @__free_recursive(ptr %t3436)
  call void @__free_recursive(ptr %t3434)
  call void @__free_recursive(ptr %t3432)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t3442, ptr %t3
  br label %tco.loop.0
tco.case.arm.12.3455:
  %t3456 = getelementptr ptr, ptr %t13, i32 1
  %t3457 = load ptr, ptr %t3456
  call void @__inc_ref(ptr %t3457)
  %t3458 = getelementptr ptr, ptr %t3457, i32 0
  %t3459 = load ptr, ptr %t3458
  %t3460 = ptrtoint ptr %t3459 to i64
  switch i64 %t3460, label %tco.case.default.3461 [ i64 15, label %tco.case.arm.15.3462 ]
tco.case.arm.15.3462:
  %t3463 = getelementptr ptr, ptr %t3457, i32 1
  %t3464 = load ptr, ptr %t3463
  call void @__inc_ref(ptr %t3464)
  %t3465 = getelementptr ptr, ptr %t3457, i32 2
  %t3466 = load ptr, ptr %t3465
  call void @__inc_ref(ptr %t3466)
  call void @__free_recursive(ptr %t3457)
  %t3467 = call ptr @__alloc(i64 24, i32 2)
  %t3468 = inttoptr i64 280 to ptr
  %t3469 = getelementptr ptr, ptr %t3467, i32 0
  store ptr %t3468, ptr %t3469
  %t3470 = call ptr @__alloc(i64 40, i32 4)
  %t3471 = inttoptr i64 92 to ptr
  %t3472 = getelementptr ptr, ptr %t3470, i32 0
  store ptr %t3471, ptr %t3472
  call void @__inc_ref(ptr %t3434)
  %t3473 = getelementptr ptr, ptr %t3470, i32 1
  store ptr %t3434, ptr %t3473
  %t3474 = getelementptr ptr, ptr %t3464, i32 0
  %t3475 = load ptr, ptr %t3474
  %t3476 = ptrtoint ptr %t3475 to i64
  switch i64 %t3476, label %case.default.3477 [ i64 28, label %case.arm.28.3479 i64 29, label %case.arm.29.3493 ]
case.arm.28.3479:
  %t3481 = getelementptr ptr, ptr %t3464, i32 2
  %t3482 = load ptr, ptr %t3481
  call void @__inc_ref(ptr %t3482)
  %t3483 = getelementptr ptr, ptr %t3464, i32 3
  %t3484 = load ptr, ptr %t3483
  call void @__inc_ref(ptr %t3484)
  %t3485 = getelementptr ptr, ptr %t4, i32 1
  %t3486 = load ptr, ptr %t3485
  call void @__free_recursive(ptr %t3486)
  %t3487 = getelementptr ptr, ptr %t4, i32 2
  %t3488 = load ptr, ptr %t3487
  call void @__free_recursive(ptr %t3488)
  %t3491 = inttoptr i64 25 to ptr
  %t3492 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t3491, ptr %t3492
  %t3489 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t3482, ptr %t3489
  %t3490 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t3484, ptr %t3490
  br label %case.end.28.3480
case.end.28.3480:
  br label %case.join.3478
case.arm.29.3493:
  %t3495 = call ptr @__alloc(i64 32, i32 3)
  %t3496 = inttoptr i64 26 to ptr
  %t3497 = getelementptr ptr, ptr %t3495, i32 0
  store ptr %t3496, ptr %t3497
  %t3498 = getelementptr ptr, ptr %t3464, i32 2
  %t3499 = load ptr, ptr %t3498
  call void @__inc_ref(ptr %t3499)
  %t3500 = getelementptr ptr, ptr %t3495, i32 1
  store ptr %t3499, ptr %t3500
  %t3501 = getelementptr ptr, ptr %t3464, i32 3
  %t3502 = load ptr, ptr %t3501
  call void @__inc_ref(ptr %t3502)
  %t3503 = getelementptr ptr, ptr %t3495, i32 2
  store ptr %t3502, ptr %t3503
  %t3504 = getelementptr ptr, ptr %t3464, i32 4
  %t3505 = load ptr, ptr %t3504
  call void @__inc_ref(ptr %t3505)
  %t3506 = getelementptr ptr, ptr %t3495, i32 3
  store ptr %t3505, ptr %t3506
  call void @__free_recursive(ptr %t4)
  br label %case.end.29.3494
case.end.29.3494:
  br label %case.join.3478
case.default.3477:
  unreachable
case.join.3478:
  %t3507 = phi ptr [ %t4, %case.end.28.3480 ], [ %t3495, %case.end.29.3494 ]
  %t3508 = getelementptr ptr, ptr %t3470, i32 2
  store ptr %t3507, ptr %t3508
  call void @__inc_ref(ptr %t3466)
  %t3509 = getelementptr ptr, ptr %t3470, i32 3
  store ptr %t3466, ptr %t3509
  call void @__inc_ref(ptr %t3436)
  %t3510 = getelementptr ptr, ptr %t3470, i32 4
  store ptr %t3436, ptr %t3510
  %t3511 = getelementptr ptr, ptr %t3467, i32 1
  store ptr %t3470, ptr %t3511
  call void @__inc_ref(ptr %t3432)
  %t3512 = getelementptr ptr, ptr %t3467, i32 2
  store ptr %t3432, ptr %t3512
  call void @__free_recursive(ptr %t3466)
  call void @__free_recursive(ptr %t3464)
  call void @__free_recursive(ptr %t3436)
  call void @__free_recursive(ptr %t3434)
  call void @__free_recursive(ptr %t3432)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t3467, ptr %t3
  br label %tco.loop.0
tco.case.default.3461:
  unreachable
tco.case.default.3440:
  unreachable
tco.case.arm.223.3513:
  %t3514 = getelementptr ptr, ptr %t11, i32 1
  %t3515 = load ptr, ptr %t3514
  call void @__inc_ref(ptr %t3515)
  %t3516 = getelementptr ptr, ptr %t11, i32 2
  %t3517 = load ptr, ptr %t3516
  call void @__inc_ref(ptr %t3517)
  %t3518 = getelementptr ptr, ptr %t11, i32 3
  %t3519 = load ptr, ptr %t3518
  call void @__inc_ref(ptr %t3519)
  %t3520 = getelementptr ptr, ptr %t13, i32 0
  %t3521 = load ptr, ptr %t3520
  %t3522 = ptrtoint ptr %t3521 to i64
  switch i64 %t3522, label %tco.case.default.3523 [ i64 11, label %tco.case.arm.11.3524 i64 12, label %tco.case.arm.12.3538 ]
tco.case.arm.11.3524:
  %t3525 = call ptr @__alloc(i64 24, i32 2)
  %t3526 = inttoptr i64 280 to ptr
  %t3527 = getelementptr ptr, ptr %t3525, i32 0
  store ptr %t3526, ptr %t3527
  %t3528 = getelementptr ptr, ptr %t4, i32 1
  %t3529 = load ptr, ptr %t3528
  call void @__free_recursive(ptr %t3529)
  %t3530 = getelementptr ptr, ptr %t4, i32 2
  %t3531 = load ptr, ptr %t3530
  call void @__free_recursive(ptr %t3531)
  %t3534 = inttoptr i64 96 to ptr
  %t3535 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t3534, ptr %t3535
  call void @__inc_ref(ptr %t3517)
  %t3532 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t3517, ptr %t3532
  call void @__inc_ref(ptr %t3519)
  %t3533 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t3519, ptr %t3533
  %t3536 = getelementptr ptr, ptr %t3525, i32 1
  store ptr %t4, ptr %t3536
  call void @__inc_ref(ptr %t3515)
  %t3537 = getelementptr ptr, ptr %t3525, i32 2
  store ptr %t3515, ptr %t3537
  call void @__free_recursive(ptr %t3519)
  call void @__free_recursive(ptr %t3517)
  call void @__free_recursive(ptr %t3515)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t3525, ptr %t3
  br label %tco.loop.0
tco.case.arm.12.3538:
  %t3539 = getelementptr ptr, ptr %t13, i32 1
  %t3540 = load ptr, ptr %t3539
  call void @__inc_ref(ptr %t3540)
  %t3541 = getelementptr ptr, ptr %t3540, i32 0
  %t3542 = load ptr, ptr %t3541
  %t3543 = ptrtoint ptr %t3542 to i64
  switch i64 %t3543, label %tco.case.default.3544 [ i64 15, label %tco.case.arm.15.3545 ]
tco.case.arm.15.3545:
  %t3546 = getelementptr ptr, ptr %t3540, i32 1
  %t3547 = load ptr, ptr %t3546
  call void @__inc_ref(ptr %t3547)
  %t3548 = getelementptr ptr, ptr %t3540, i32 2
  %t3549 = load ptr, ptr %t3548
  call void @__inc_ref(ptr %t3549)
  call void @__free_recursive(ptr %t3540)
  %t3550 = call ptr @__alloc(i64 24, i32 2)
  %t3551 = inttoptr i64 280 to ptr
  %t3552 = getelementptr ptr, ptr %t3550, i32 0
  store ptr %t3551, ptr %t3552
  %t3553 = call ptr @__alloc(i64 40, i32 4)
  %t3554 = inttoptr i64 92 to ptr
  %t3555 = getelementptr ptr, ptr %t3553, i32 0
  store ptr %t3554, ptr %t3555
  call void @__inc_ref(ptr %t3517)
  %t3556 = getelementptr ptr, ptr %t3553, i32 1
  store ptr %t3517, ptr %t3556
  call void @__inc_ref(ptr %t3519)
  %t3557 = getelementptr ptr, ptr %t3553, i32 2
  store ptr %t3519, ptr %t3557
  call void @__inc_ref(ptr %t3547)
  %t3558 = getelementptr ptr, ptr %t3553, i32 3
  store ptr %t3547, ptr %t3558
  %t3559 = getelementptr ptr, ptr %t3549, i32 0
  %t3560 = load ptr, ptr %t3559
  %t3561 = ptrtoint ptr %t3560 to i64
  switch i64 %t3561, label %case.default.3562 [ i64 28, label %case.arm.28.3564 i64 29, label %case.arm.29.3578 ]
case.arm.28.3564:
  %t3566 = getelementptr ptr, ptr %t3549, i32 2
  %t3567 = load ptr, ptr %t3566
  call void @__inc_ref(ptr %t3567)
  %t3568 = getelementptr ptr, ptr %t3549, i32 3
  %t3569 = load ptr, ptr %t3568
  call void @__inc_ref(ptr %t3569)
  %t3570 = getelementptr ptr, ptr %t4, i32 1
  %t3571 = load ptr, ptr %t3570
  call void @__free_recursive(ptr %t3571)
  %t3572 = getelementptr ptr, ptr %t4, i32 2
  %t3573 = load ptr, ptr %t3572
  call void @__free_recursive(ptr %t3573)
  %t3576 = inttoptr i64 25 to ptr
  %t3577 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t3576, ptr %t3577
  %t3574 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t3567, ptr %t3574
  %t3575 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t3569, ptr %t3575
  br label %case.end.28.3565
case.end.28.3565:
  br label %case.join.3563
case.arm.29.3578:
  %t3580 = call ptr @__alloc(i64 32, i32 3)
  %t3581 = inttoptr i64 26 to ptr
  %t3582 = getelementptr ptr, ptr %t3580, i32 0
  store ptr %t3581, ptr %t3582
  %t3583 = getelementptr ptr, ptr %t3549, i32 2
  %t3584 = load ptr, ptr %t3583
  call void @__inc_ref(ptr %t3584)
  %t3585 = getelementptr ptr, ptr %t3580, i32 1
  store ptr %t3584, ptr %t3585
  %t3586 = getelementptr ptr, ptr %t3549, i32 3
  %t3587 = load ptr, ptr %t3586
  call void @__inc_ref(ptr %t3587)
  %t3588 = getelementptr ptr, ptr %t3580, i32 2
  store ptr %t3587, ptr %t3588
  %t3589 = getelementptr ptr, ptr %t3549, i32 4
  %t3590 = load ptr, ptr %t3589
  call void @__inc_ref(ptr %t3590)
  %t3591 = getelementptr ptr, ptr %t3580, i32 3
  store ptr %t3590, ptr %t3591
  call void @__free_recursive(ptr %t4)
  br label %case.end.29.3579
case.end.29.3579:
  br label %case.join.3563
case.default.3562:
  unreachable
case.join.3563:
  %t3592 = phi ptr [ %t4, %case.end.28.3565 ], [ %t3580, %case.end.29.3579 ]
  %t3593 = getelementptr ptr, ptr %t3553, i32 4
  store ptr %t3592, ptr %t3593
  %t3594 = getelementptr ptr, ptr %t3550, i32 1
  store ptr %t3553, ptr %t3594
  call void @__inc_ref(ptr %t3515)
  %t3595 = getelementptr ptr, ptr %t3550, i32 2
  store ptr %t3515, ptr %t3595
  call void @__free_recursive(ptr %t3549)
  call void @__free_recursive(ptr %t3547)
  call void @__free_recursive(ptr %t3519)
  call void @__free_recursive(ptr %t3517)
  call void @__free_recursive(ptr %t3515)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t3550, ptr %t3
  br label %tco.loop.0
tco.case.default.3544:
  unreachable
tco.case.default.3523:
  unreachable
tco.case.arm.225.3596:
  %t3597 = getelementptr ptr, ptr %t11, i32 1
  %t3598 = load ptr, ptr %t3597
  call void @__inc_ref(ptr %t3598)
  %t3599 = call ptr @__alloc(i64 16, i32 1)
  %t3600 = inttoptr i64 12 to ptr
  %t3601 = getelementptr ptr, ptr %t3599, i32 0
  store ptr %t3600, ptr %t3601
  call void @__inc_ref(ptr %t13)
  %t3602 = getelementptr ptr, ptr %t3599, i32 1
  store ptr %t13, ptr %t3602
  %t3603 = getelementptr ptr, ptr %t4, i32 1
  %t3604 = load ptr, ptr %t3603
  call void @__free_recursive(ptr %t3604)
  %t3605 = getelementptr ptr, ptr %t4, i32 2
  %t3606 = load ptr, ptr %t3605
  call void @__free_recursive(ptr %t3606)
  %t3609 = inttoptr i64 279 to ptr
  %t3610 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t3609, ptr %t3610
  %t3607 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t3598, ptr %t3607
  %t3608 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t3599, ptr %t3608
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.224.3611:
  %t3612 = getelementptr ptr, ptr %t11, i32 1
  %t3613 = load ptr, ptr %t3612
  call void @__inc_ref(ptr %t3613)
  %t3614 = getelementptr ptr, ptr %t13, i32 0
  %t3615 = load ptr, ptr %t3614
  %t3616 = ptrtoint ptr %t3615 to i64
  switch i64 %t3616, label %tco.case.default.3617 [ i64 11, label %tco.case.arm.11.3618 i64 12, label %tco.case.arm.12.3624 ]
tco.case.arm.11.3618:
  %t3619 = getelementptr ptr, ptr %t4, i32 1
  %t3620 = load ptr, ptr %t3619
  call void @__free_recursive(ptr %t3620)
  %t3622 = inttoptr i64 279 to ptr
  %t3623 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t3622, ptr %t3623
  call void @__inc_ref(ptr %t3613)
  %t3621 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t3613, ptr %t3621
  call void @__free_recursive(ptr %t3613)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.12.3624:
  %t3625 = getelementptr ptr, ptr %t13, i32 1
  %t3626 = load ptr, ptr %t3625
  call void @__inc_ref(ptr %t3626)
  %t3627 = call ptr @__alloc(i64 40, i32 4)
  %t3628 = inttoptr i64 85 to ptr
  %t3629 = getelementptr ptr, ptr %t3627, i32 0
  store ptr %t3628, ptr %t3629
  %t3630 = call ptr @v_lineMeasure()
  %t3631 = getelementptr ptr, ptr %t3627, i32 1
  store ptr %t3630, ptr %t3631
  %t3632 = getelementptr ptr, ptr %t3626, i32 1
  %t3633 = load ptr, ptr %t3632
  call void @__inc_ref(ptr %t3633)
  %t3634 = getelementptr ptr, ptr %t3627, i32 2
  store ptr %t3633, ptr %t3634
  %t3635 = call ptr @__alloc(i64 8, i32 0)
  %t3636 = inttoptr i64 13 to ptr
  %t3637 = getelementptr ptr, ptr %t3635, i32 0
  store ptr %t3636, ptr %t3637
  %t3638 = getelementptr ptr, ptr %t3627, i32 3
  store ptr %t3635, ptr %t3638
  %t3639 = getelementptr ptr, ptr %t3626, i32 3
  %t3640 = load ptr, ptr %t3639
  call void @__inc_ref(ptr %t3640)
  %t3641 = getelementptr ptr, ptr %t3627, i32 4
  store ptr %t3640, ptr %t3641
  %t3642 = call ptr @__alloc(i64 16, i32 1)
  %t3643 = inttoptr i64 225 to ptr
  %t3644 = getelementptr ptr, ptr %t3642, i32 0
  store ptr %t3643, ptr %t3644
  call void @__inc_ref(ptr %t3613)
  %t3645 = getelementptr ptr, ptr %t3642, i32 1
  store ptr %t3613, ptr %t3645
  %t3646 = getelementptr ptr, ptr %t4, i32 1
  %t3647 = load ptr, ptr %t3646
  call void @__free_recursive(ptr %t3647)
  %t3648 = getelementptr ptr, ptr %t4, i32 2
  %t3649 = load ptr, ptr %t3648
  call void @__free_recursive(ptr %t3649)
  %t3652 = inttoptr i64 280 to ptr
  %t3653 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t3652, ptr %t3653
  %t3650 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t3627, ptr %t3650
  %t3651 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t3642, ptr %t3651
  call void @__free_recursive(ptr %t3626)
  call void @__free_recursive(ptr %t3613)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.3617:
  unreachable
tco.case.arm.226.3654:
  %t3655 = call ptr @__alloc(i64 32, i32 3)
  %t3656 = inttoptr i64 54 to ptr
  %t3657 = getelementptr ptr, ptr %t3655, i32 0
  store ptr %t3656, ptr %t3657
  %t3658 = getelementptr ptr, ptr %t11, i32 3
  %t3659 = load ptr, ptr %t3658
  call void @__inc_ref(ptr %t3659)
  %t3660 = getelementptr ptr, ptr %t3655, i32 1
  store ptr %t3659, ptr %t3660
  %t3661 = getelementptr ptr, ptr %t11, i32 2
  %t3662 = load ptr, ptr %t3661
  call void @__inc_ref(ptr %t3662)
  %t3663 = getelementptr ptr, ptr %t3655, i32 2
  store ptr %t3662, ptr %t3663
  call void @__inc_ref(ptr %t13)
  %t3664 = getelementptr ptr, ptr %t3655, i32 3
  store ptr %t13, ptr %t3664
  %t3665 = getelementptr ptr, ptr %t11, i32 1
  %t3666 = load ptr, ptr %t3665
  call void @__inc_ref(ptr %t3666)
  %t3667 = getelementptr ptr, ptr %t4, i32 1
  %t3668 = load ptr, ptr %t3667
  call void @__free_recursive(ptr %t3668)
  %t3669 = getelementptr ptr, ptr %t4, i32 2
  %t3670 = load ptr, ptr %t3669
  call void @__free_recursive(ptr %t3670)
  %t3673 = inttoptr i64 280 to ptr
  %t3674 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t3673, ptr %t3674
  %t3671 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t3655, ptr %t3671
  %t3672 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t3666, ptr %t3672
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.228.3675:
  %t3676 = call ptr @__alloc(i64 32, i32 3)
  %t3677 = inttoptr i64 54 to ptr
  %t3678 = getelementptr ptr, ptr %t3676, i32 0
  store ptr %t3677, ptr %t3678
  %t3679 = getelementptr ptr, ptr %t11, i32 3
  %t3680 = load ptr, ptr %t3679
  call void @__inc_ref(ptr %t3680)
  %t3681 = getelementptr ptr, ptr %t3676, i32 1
  store ptr %t3680, ptr %t3681
  %t3682 = getelementptr ptr, ptr %t11, i32 2
  %t3683 = load ptr, ptr %t3682
  call void @__inc_ref(ptr %t3683)
  %t3684 = getelementptr ptr, ptr %t3676, i32 2
  store ptr %t3683, ptr %t3684
  call void @__inc_ref(ptr %t13)
  %t3685 = getelementptr ptr, ptr %t3676, i32 3
  store ptr %t13, ptr %t3685
  %t3686 = getelementptr ptr, ptr %t11, i32 1
  %t3687 = load ptr, ptr %t3686
  call void @__inc_ref(ptr %t3687)
  %t3688 = getelementptr ptr, ptr %t4, i32 1
  %t3689 = load ptr, ptr %t3688
  call void @__free_recursive(ptr %t3689)
  %t3690 = getelementptr ptr, ptr %t4, i32 2
  %t3691 = load ptr, ptr %t3690
  call void @__free_recursive(ptr %t3691)
  %t3694 = inttoptr i64 280 to ptr
  %t3695 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t3694, ptr %t3695
  %t3692 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t3676, ptr %t3692
  %t3693 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t3687, ptr %t3693
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.227.3696:
  %t3697 = getelementptr ptr, ptr %t11, i32 4
  %t3698 = load ptr, ptr %t3697
  call void @__inc_ref(ptr %t3698)
  %t3699 = call ptr @__alloc(i64 32, i32 3)
  %t3700 = inttoptr i64 54 to ptr
  %t3701 = getelementptr ptr, ptr %t3699, i32 0
  store ptr %t3700, ptr %t3701
  call void @__inc_ref(ptr %t3698)
  %t3702 = getelementptr ptr, ptr %t3699, i32 1
  store ptr %t3698, ptr %t3702
  %t3703 = getelementptr ptr, ptr %t11, i32 3
  %t3704 = load ptr, ptr %t3703
  call void @__inc_ref(ptr %t3704)
  %t3705 = getelementptr ptr, ptr %t3699, i32 2
  store ptr %t3704, ptr %t3705
  call void @__inc_ref(ptr %t13)
  %t3706 = getelementptr ptr, ptr %t3699, i32 3
  store ptr %t13, ptr %t3706
  %t3707 = call ptr @__alloc(i64 32, i32 3)
  %t3708 = inttoptr i64 228 to ptr
  %t3709 = getelementptr ptr, ptr %t3707, i32 0
  store ptr %t3708, ptr %t3709
  %t3710 = getelementptr ptr, ptr %t11, i32 1
  %t3711 = load ptr, ptr %t3710
  call void @__inc_ref(ptr %t3711)
  %t3712 = getelementptr ptr, ptr %t3707, i32 1
  store ptr %t3711, ptr %t3712
  %t3713 = getelementptr ptr, ptr %t11, i32 2
  %t3714 = load ptr, ptr %t3713
  call void @__inc_ref(ptr %t3714)
  %t3715 = getelementptr ptr, ptr %t3707, i32 2
  store ptr %t3714, ptr %t3715
  call void @__inc_ref(ptr %t3698)
  %t3716 = getelementptr ptr, ptr %t3707, i32 3
  store ptr %t3698, ptr %t3716
  %t3717 = getelementptr ptr, ptr %t4, i32 1
  %t3718 = load ptr, ptr %t3717
  call void @__free_recursive(ptr %t3718)
  %t3719 = getelementptr ptr, ptr %t4, i32 2
  %t3720 = load ptr, ptr %t3719
  call void @__free_recursive(ptr %t3720)
  %t3723 = inttoptr i64 280 to ptr
  %t3724 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t3723, ptr %t3724
  %t3721 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t3699, ptr %t3721
  %t3722 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t3707, ptr %t3722
  call void @__free_recursive(ptr %t3698)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.231.3725:
  %t3726 = call ptr @__alloc(i64 32, i32 3)
  %t3727 = inttoptr i64 54 to ptr
  %t3728 = getelementptr ptr, ptr %t3726, i32 0
  store ptr %t3727, ptr %t3728
  %t3729 = getelementptr ptr, ptr %t11, i32 3
  %t3730 = load ptr, ptr %t3729
  call void @__inc_ref(ptr %t3730)
  %t3731 = getelementptr ptr, ptr %t3726, i32 1
  store ptr %t3730, ptr %t3731
  %t3732 = getelementptr ptr, ptr %t11, i32 2
  %t3733 = load ptr, ptr %t3732
  call void @__inc_ref(ptr %t3733)
  %t3734 = getelementptr ptr, ptr %t3726, i32 2
  store ptr %t3733, ptr %t3734
  call void @__inc_ref(ptr %t13)
  %t3735 = getelementptr ptr, ptr %t3726, i32 3
  store ptr %t13, ptr %t3735
  %t3736 = getelementptr ptr, ptr %t11, i32 1
  %t3737 = load ptr, ptr %t3736
  call void @__inc_ref(ptr %t3737)
  %t3738 = getelementptr ptr, ptr %t4, i32 1
  %t3739 = load ptr, ptr %t3738
  call void @__free_recursive(ptr %t3739)
  %t3740 = getelementptr ptr, ptr %t4, i32 2
  %t3741 = load ptr, ptr %t3740
  call void @__free_recursive(ptr %t3741)
  %t3744 = inttoptr i64 280 to ptr
  %t3745 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t3744, ptr %t3745
  %t3742 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t3726, ptr %t3742
  %t3743 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t3737, ptr %t3743
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.230.3746:
  %t3747 = getelementptr ptr, ptr %t11, i32 4
  %t3748 = load ptr, ptr %t3747
  call void @__inc_ref(ptr %t3748)
  %t3749 = call ptr @__alloc(i64 32, i32 3)
  %t3750 = inttoptr i64 54 to ptr
  %t3751 = getelementptr ptr, ptr %t3749, i32 0
  store ptr %t3750, ptr %t3751
  call void @__inc_ref(ptr %t3748)
  %t3752 = getelementptr ptr, ptr %t3749, i32 1
  store ptr %t3748, ptr %t3752
  %t3753 = getelementptr ptr, ptr %t11, i32 3
  %t3754 = load ptr, ptr %t3753
  call void @__inc_ref(ptr %t3754)
  %t3755 = getelementptr ptr, ptr %t3749, i32 2
  store ptr %t3754, ptr %t3755
  call void @__inc_ref(ptr %t13)
  %t3756 = getelementptr ptr, ptr %t3749, i32 3
  store ptr %t13, ptr %t3756
  %t3757 = call ptr @__alloc(i64 32, i32 3)
  %t3758 = inttoptr i64 231 to ptr
  %t3759 = getelementptr ptr, ptr %t3757, i32 0
  store ptr %t3758, ptr %t3759
  %t3760 = getelementptr ptr, ptr %t11, i32 1
  %t3761 = load ptr, ptr %t3760
  call void @__inc_ref(ptr %t3761)
  %t3762 = getelementptr ptr, ptr %t3757, i32 1
  store ptr %t3761, ptr %t3762
  %t3763 = getelementptr ptr, ptr %t11, i32 2
  %t3764 = load ptr, ptr %t3763
  call void @__inc_ref(ptr %t3764)
  %t3765 = getelementptr ptr, ptr %t3757, i32 2
  store ptr %t3764, ptr %t3765
  call void @__inc_ref(ptr %t3748)
  %t3766 = getelementptr ptr, ptr %t3757, i32 3
  store ptr %t3748, ptr %t3766
  %t3767 = getelementptr ptr, ptr %t4, i32 1
  %t3768 = load ptr, ptr %t3767
  call void @__free_recursive(ptr %t3768)
  %t3769 = getelementptr ptr, ptr %t4, i32 2
  %t3770 = load ptr, ptr %t3769
  call void @__free_recursive(ptr %t3770)
  %t3773 = inttoptr i64 280 to ptr
  %t3774 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t3773, ptr %t3774
  %t3771 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t3749, ptr %t3771
  %t3772 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t3757, ptr %t3772
  call void @__free_recursive(ptr %t3748)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.229.3775:
  %t3776 = getelementptr ptr, ptr %t11, i32 5
  %t3777 = load ptr, ptr %t3776
  call void @__inc_ref(ptr %t3777)
  %t3778 = call ptr @__alloc(i64 32, i32 3)
  %t3779 = inttoptr i64 54 to ptr
  %t3780 = getelementptr ptr, ptr %t3778, i32 0
  store ptr %t3779, ptr %t3780
  call void @__inc_ref(ptr %t3777)
  %t3781 = getelementptr ptr, ptr %t3778, i32 1
  store ptr %t3777, ptr %t3781
  %t3782 = getelementptr ptr, ptr %t11, i32 4
  %t3783 = load ptr, ptr %t3782
  call void @__inc_ref(ptr %t3783)
  %t3784 = getelementptr ptr, ptr %t3778, i32 2
  store ptr %t3783, ptr %t3784
  call void @__inc_ref(ptr %t13)
  %t3785 = getelementptr ptr, ptr %t3778, i32 3
  store ptr %t13, ptr %t3785
  %t3786 = call ptr @__alloc(i64 40, i32 4)
  %t3787 = inttoptr i64 230 to ptr
  %t3788 = getelementptr ptr, ptr %t3786, i32 0
  store ptr %t3787, ptr %t3788
  %t3789 = getelementptr ptr, ptr %t11, i32 1
  %t3790 = load ptr, ptr %t3789
  call void @__inc_ref(ptr %t3790)
  %t3791 = getelementptr ptr, ptr %t3786, i32 1
  store ptr %t3790, ptr %t3791
  %t3792 = getelementptr ptr, ptr %t11, i32 2
  %t3793 = load ptr, ptr %t3792
  call void @__inc_ref(ptr %t3793)
  %t3794 = getelementptr ptr, ptr %t3786, i32 2
  store ptr %t3793, ptr %t3794
  %t3795 = getelementptr ptr, ptr %t11, i32 3
  %t3796 = load ptr, ptr %t3795
  call void @__inc_ref(ptr %t3796)
  %t3797 = getelementptr ptr, ptr %t3786, i32 3
  store ptr %t3796, ptr %t3797
  call void @__inc_ref(ptr %t3777)
  %t3798 = getelementptr ptr, ptr %t3786, i32 4
  store ptr %t3777, ptr %t3798
  %t3799 = getelementptr ptr, ptr %t4, i32 1
  %t3800 = load ptr, ptr %t3799
  call void @__free_recursive(ptr %t3800)
  %t3801 = getelementptr ptr, ptr %t4, i32 2
  %t3802 = load ptr, ptr %t3801
  call void @__free_recursive(ptr %t3802)
  %t3805 = inttoptr i64 280 to ptr
  %t3806 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t3805, ptr %t3806
  %t3803 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t3778, ptr %t3803
  %t3804 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t3786, ptr %t3804
  call void @__free_recursive(ptr %t3777)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.234.3807:
  %t3808 = getelementptr ptr, ptr %t11, i32 1
  %t3809 = load ptr, ptr %t3808
  call void @__inc_ref(ptr %t3809)
  %t3810 = call ptr @__alloc(i64 16, i32 1)
  %t3811 = inttoptr i64 12 to ptr
  %t3812 = getelementptr ptr, ptr %t3810, i32 0
  store ptr %t3811, ptr %t3812
  call void @__inc_ref(ptr %t13)
  %t3813 = getelementptr ptr, ptr %t3810, i32 1
  store ptr %t13, ptr %t3813
  %t3814 = getelementptr ptr, ptr %t4, i32 1
  %t3815 = load ptr, ptr %t3814
  call void @__free_recursive(ptr %t3815)
  %t3816 = getelementptr ptr, ptr %t4, i32 2
  %t3817 = load ptr, ptr %t3816
  call void @__free_recursive(ptr %t3817)
  %t3820 = inttoptr i64 279 to ptr
  %t3821 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t3820, ptr %t3821
  %t3818 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t3809, ptr %t3818
  %t3819 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t3810, ptr %t3819
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.233.3822:
  %t3823 = getelementptr ptr, ptr %t11, i32 1
  %t3824 = load ptr, ptr %t3823
  call void @__inc_ref(ptr %t3824)
  %t3825 = getelementptr ptr, ptr %t11, i32 3
  %t3826 = load ptr, ptr %t3825
  call void @__inc_ref(ptr %t3826)
  %t3827 = getelementptr ptr, ptr %t13, i32 1
  %t3828 = load ptr, ptr %t3827
  call void @__inc_ref(ptr %t3828)
  %t3829 = call ptr @__eqUInt32(ptr %t3826, ptr %t3828)
  %t3830 = getelementptr ptr, ptr %t3829, i32 0
  %t3831 = load ptr, ptr %t3830
  %t3832 = ptrtoint ptr %t3831 to i64
  switch i64 %t3832, label %tco.case.default.3833 [ i64 1, label %tco.case.arm.1.3834 i64 2, label %tco.case.arm.2.3858 ]
tco.case.arm.1.3834:
  call void @__free_recursive(ptr %t3829)
  %t3835 = call ptr @__alloc(i64 32, i32 3)
  %t3836 = inttoptr i64 114 to ptr
  %t3837 = getelementptr ptr, ptr %t3835, i32 0
  store ptr %t3836, ptr %t3837
  %t3838 = call ptr @v_lineMeasure()
  %t3839 = getelementptr ptr, ptr %t3835, i32 1
  store ptr %t3838, ptr %t3839
  %t3840 = getelementptr ptr, ptr %t11, i32 2
  %t3841 = load ptr, ptr %t3840
  call void @__inc_ref(ptr %t3841)
  %t3842 = getelementptr ptr, ptr %t3835, i32 2
  store ptr %t3841, ptr %t3842
  %t3843 = getelementptr ptr, ptr %t11, i32 4
  %t3844 = load ptr, ptr %t3843
  call void @__inc_ref(ptr %t3844)
  %t3845 = getelementptr ptr, ptr %t3835, i32 3
  store ptr %t3844, ptr %t3845
  %t3846 = call ptr @__alloc(i64 16, i32 1)
  %t3847 = inttoptr i64 234 to ptr
  %t3848 = getelementptr ptr, ptr %t3846, i32 0
  store ptr %t3847, ptr %t3848
  call void @__inc_ref(ptr %t3824)
  %t3849 = getelementptr ptr, ptr %t3846, i32 1
  store ptr %t3824, ptr %t3849
  %t3850 = getelementptr ptr, ptr %t4, i32 1
  %t3851 = load ptr, ptr %t3850
  call void @__free_recursive(ptr %t3851)
  %t3852 = getelementptr ptr, ptr %t4, i32 2
  %t3853 = load ptr, ptr %t3852
  call void @__free_recursive(ptr %t3853)
  %t3856 = inttoptr i64 280 to ptr
  %t3857 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t3856, ptr %t3857
  %t3854 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t3835, ptr %t3854
  %t3855 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t3846, ptr %t3855
  call void @__free_recursive(ptr %t3824)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.2.3858:
  call void @__free_recursive(ptr %t3829)
  %t3859 = call ptr @__alloc(i64 8, i32 0)
  %t3860 = inttoptr i64 11 to ptr
  %t3861 = getelementptr ptr, ptr %t3859, i32 0
  store ptr %t3860, ptr %t3861
  %t3862 = getelementptr ptr, ptr %t4, i32 1
  %t3863 = load ptr, ptr %t3862
  call void @__free_recursive(ptr %t3863)
  %t3864 = getelementptr ptr, ptr %t4, i32 2
  %t3865 = load ptr, ptr %t3864
  call void @__free_recursive(ptr %t3865)
  %t3868 = inttoptr i64 279 to ptr
  %t3869 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t3868, ptr %t3869
  call void @__inc_ref(ptr %t3824)
  %t3866 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t3824, ptr %t3866
  %t3867 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t3859, ptr %t3867
  call void @__free_recursive(ptr %t3824)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.3833:
  unreachable
tco.case.arm.235.3870:
  %t3871 = getelementptr ptr, ptr %t11, i32 1
  %t3872 = load ptr, ptr %t3871
  call void @__inc_ref(ptr %t3872)
  %t3873 = call ptr @__alloc(i64 16, i32 1)
  %t3874 = inttoptr i64 12 to ptr
  %t3875 = getelementptr ptr, ptr %t3873, i32 0
  store ptr %t3874, ptr %t3875
  call void @__inc_ref(ptr %t13)
  %t3876 = getelementptr ptr, ptr %t3873, i32 1
  store ptr %t13, ptr %t3876
  %t3877 = getelementptr ptr, ptr %t4, i32 1
  %t3878 = load ptr, ptr %t3877
  call void @__free_recursive(ptr %t3878)
  %t3879 = getelementptr ptr, ptr %t4, i32 2
  %t3880 = load ptr, ptr %t3879
  call void @__free_recursive(ptr %t3880)
  %t3883 = inttoptr i64 279 to ptr
  %t3884 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t3883, ptr %t3884
  %t3881 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t3872, ptr %t3881
  %t3882 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t3873, ptr %t3882
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.232.3885:
  %t3886 = getelementptr ptr, ptr %t11, i32 1
  %t3887 = load ptr, ptr %t3886
  call void @__inc_ref(ptr %t3887)
  %t3888 = getelementptr ptr, ptr %t11, i32 2
  %t3889 = load ptr, ptr %t3888
  call void @__inc_ref(ptr %t3889)
  %t3890 = getelementptr ptr, ptr %t11, i32 4
  %t3891 = load ptr, ptr %t3890
  call void @__inc_ref(ptr %t3891)
  %t3892 = getelementptr ptr, ptr %t13, i32 0
  %t3893 = load ptr, ptr %t3892
  %t3894 = ptrtoint ptr %t3893 to i64
  switch i64 %t3894, label %tco.case.default.3895 [ i64 11, label %tco.case.arm.11.3896 i64 12, label %tco.case.arm.12.3920 ]
tco.case.arm.11.3896:
  %t3897 = call ptr @__alloc(i64 24, i32 2)
  %t3898 = inttoptr i64 280 to ptr
  %t3899 = getelementptr ptr, ptr %t3897, i32 0
  store ptr %t3898, ptr %t3899
  %t3900 = call ptr @v_lineMeasure()
  %t3901 = getelementptr ptr, ptr %t4, i32 1
  %t3902 = load ptr, ptr %t3901
  call void @__free_recursive(ptr %t3902)
  %t3903 = getelementptr ptr, ptr %t4, i32 2
  %t3904 = load ptr, ptr %t3903
  call void @__free_recursive(ptr %t3904)
  %t3907 = inttoptr i64 103 to ptr
  %t3908 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t3907, ptr %t3908
  %t3905 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t3900, ptr %t3905
  call void @__inc_ref(ptr %t3889)
  %t3906 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t3889, ptr %t3906
  %t3909 = getelementptr ptr, ptr %t3897, i32 1
  store ptr %t4, ptr %t3909
  %t3910 = call ptr @__alloc(i64 40, i32 4)
  %t3911 = inttoptr i64 233 to ptr
  %t3912 = getelementptr ptr, ptr %t3910, i32 0
  store ptr %t3911, ptr %t3912
  call void @__inc_ref(ptr %t3887)
  %t3913 = getelementptr ptr, ptr %t3910, i32 1
  store ptr %t3887, ptr %t3913
  call void @__inc_ref(ptr %t3889)
  %t3914 = getelementptr ptr, ptr %t3910, i32 2
  store ptr %t3889, ptr %t3914
  %t3915 = getelementptr ptr, ptr %t11, i32 3
  %t3916 = load ptr, ptr %t3915
  call void @__inc_ref(ptr %t3916)
  %t3917 = getelementptr ptr, ptr %t3910, i32 3
  store ptr %t3916, ptr %t3917
  call void @__inc_ref(ptr %t3891)
  %t3918 = getelementptr ptr, ptr %t3910, i32 4
  store ptr %t3891, ptr %t3918
  %t3919 = getelementptr ptr, ptr %t3897, i32 2
  store ptr %t3910, ptr %t3919
  call void @__free_recursive(ptr %t3891)
  call void @__free_recursive(ptr %t3889)
  call void @__free_recursive(ptr %t3887)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t3897, ptr %t3
  br label %tco.loop.0
tco.case.arm.12.3920:
  %t3921 = getelementptr ptr, ptr %t13, i32 1
  %t3922 = load ptr, ptr %t3921
  call void @__inc_ref(ptr %t3922)
  %t3923 = call ptr @__alloc(i64 24, i32 2)
  %t3924 = inttoptr i64 280 to ptr
  %t3925 = getelementptr ptr, ptr %t3923, i32 0
  store ptr %t3924, ptr %t3925
  %t3926 = call ptr @__alloc(i64 40, i32 4)
  %t3927 = inttoptr i64 85 to ptr
  %t3928 = getelementptr ptr, ptr %t3926, i32 0
  store ptr %t3927, ptr %t3928
  %t3929 = call ptr @v_lineMeasure()
  %t3930 = getelementptr ptr, ptr %t3926, i32 1
  store ptr %t3929, ptr %t3930
  %t3931 = getelementptr ptr, ptr %t3922, i32 1
  %t3932 = load ptr, ptr %t3931
  call void @__inc_ref(ptr %t3932)
  %t3933 = getelementptr ptr, ptr %t3926, i32 2
  store ptr %t3932, ptr %t3933
  %t3934 = call ptr @__alloc(i64 24, i32 2)
  %t3935 = inttoptr i64 14 to ptr
  %t3936 = getelementptr ptr, ptr %t3934, i32 0
  store ptr %t3935, ptr %t3936
  call void @__inc_ref(ptr %t3891)
  %t3937 = getelementptr ptr, ptr %t3934, i32 1
  store ptr %t3891, ptr %t3937
  %t3938 = getelementptr ptr, ptr %t3922, i32 2
  %t3939 = load ptr, ptr %t3938
  call void @__inc_ref(ptr %t3939)
  %t3940 = call ptr @__alloc(i64 8, i32 0)
  %t3941 = inttoptr i64 13 to ptr
  %t3942 = getelementptr ptr, ptr %t3940, i32 0
  store ptr %t3941, ptr %t3942
  %t3943 = getelementptr ptr, ptr %t4, i32 1
  %t3944 = load ptr, ptr %t3943
  call void @__free_recursive(ptr %t3944)
  %t3945 = getelementptr ptr, ptr %t4, i32 2
  %t3946 = load ptr, ptr %t3945
  call void @__free_recursive(ptr %t3946)
  %t3949 = inttoptr i64 14 to ptr
  %t3950 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t3949, ptr %t3950
  %t3947 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t3939, ptr %t3947
  %t3948 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t3940, ptr %t3948
  %t3951 = getelementptr ptr, ptr %t3934, i32 2
  store ptr %t4, ptr %t3951
  %t3952 = getelementptr ptr, ptr %t3926, i32 3
  store ptr %t3934, ptr %t3952
  %t3953 = getelementptr ptr, ptr %t3922, i32 3
  %t3954 = load ptr, ptr %t3953
  call void @__inc_ref(ptr %t3954)
  %t3955 = getelementptr ptr, ptr %t3926, i32 4
  store ptr %t3954, ptr %t3955
  %t3956 = getelementptr ptr, ptr %t3923, i32 1
  store ptr %t3926, ptr %t3956
  %t3957 = call ptr @__alloc(i64 16, i32 1)
  %t3958 = inttoptr i64 235 to ptr
  %t3959 = getelementptr ptr, ptr %t3957, i32 0
  store ptr %t3958, ptr %t3959
  call void @__inc_ref(ptr %t3887)
  %t3960 = getelementptr ptr, ptr %t3957, i32 1
  store ptr %t3887, ptr %t3960
  %t3961 = getelementptr ptr, ptr %t3923, i32 2
  store ptr %t3957, ptr %t3961
  call void @__free_recursive(ptr %t3922)
  call void @__free_recursive(ptr %t3891)
  call void @__free_recursive(ptr %t3889)
  call void @__free_recursive(ptr %t3887)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t3923, ptr %t3
  br label %tco.loop.0
tco.case.default.3895:
  unreachable
tco.case.arm.237.3962:
  %t3963 = call ptr @__alloc(i64 32, i32 3)
  %t3964 = inttoptr i64 88 to ptr
  %t3965 = getelementptr ptr, ptr %t3963, i32 0
  store ptr %t3964, ptr %t3965
  %t3966 = getelementptr ptr, ptr %t11, i32 3
  %t3967 = load ptr, ptr %t3966
  call void @__inc_ref(ptr %t3967)
  %t3968 = getelementptr ptr, ptr %t3963, i32 1
  store ptr %t3967, ptr %t3968
  %t3969 = getelementptr ptr, ptr %t11, i32 2
  %t3970 = load ptr, ptr %t3969
  call void @__inc_ref(ptr %t3970)
  %t3971 = getelementptr ptr, ptr %t3963, i32 2
  store ptr %t3970, ptr %t3971
  call void @__inc_ref(ptr %t13)
  %t3972 = getelementptr ptr, ptr %t3963, i32 3
  store ptr %t13, ptr %t3972
  %t3973 = getelementptr ptr, ptr %t11, i32 1
  %t3974 = load ptr, ptr %t3973
  call void @__inc_ref(ptr %t3974)
  %t3975 = getelementptr ptr, ptr %t4, i32 1
  %t3976 = load ptr, ptr %t3975
  call void @__free_recursive(ptr %t3976)
  %t3977 = getelementptr ptr, ptr %t4, i32 2
  %t3978 = load ptr, ptr %t3977
  call void @__free_recursive(ptr %t3978)
  %t3981 = inttoptr i64 280 to ptr
  %t3982 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t3981, ptr %t3982
  %t3979 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t3963, ptr %t3979
  %t3980 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t3974, ptr %t3980
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.236.3983:
  %t3984 = getelementptr ptr, ptr %t11, i32 3
  %t3985 = load ptr, ptr %t3984
  call void @__inc_ref(ptr %t3985)
  %t3986 = call ptr @__alloc(i64 24, i32 2)
  %t3987 = inttoptr i64 280 to ptr
  %t3988 = getelementptr ptr, ptr %t3986, i32 0
  store ptr %t3987, ptr %t3988
  %t3989 = getelementptr ptr, ptr %t11, i32 2
  %t3990 = load ptr, ptr %t3989
  call void @__inc_ref(ptr %t3990)
  %t3991 = getelementptr ptr, ptr %t4, i32 1
  %t3992 = load ptr, ptr %t3991
  call void @__free_recursive(ptr %t3992)
  %t3993 = getelementptr ptr, ptr %t4, i32 2
  %t3994 = load ptr, ptr %t3993
  call void @__free_recursive(ptr %t3994)
  %t3997 = inttoptr i64 101 to ptr
  %t3998 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t3997, ptr %t3998
  call void @__inc_ref(ptr %t3985)
  %t3995 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t3985, ptr %t3995
  %t3996 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t3990, ptr %t3996
  %t3999 = getelementptr ptr, ptr %t3986, i32 1
  store ptr %t4, ptr %t3999
  %t4000 = call ptr @__alloc(i64 32, i32 3)
  %t4001 = inttoptr i64 237 to ptr
  %t4002 = getelementptr ptr, ptr %t4000, i32 0
  store ptr %t4001, ptr %t4002
  %t4003 = getelementptr ptr, ptr %t11, i32 1
  %t4004 = load ptr, ptr %t4003
  call void @__inc_ref(ptr %t4004)
  %t4005 = getelementptr ptr, ptr %t4000, i32 1
  store ptr %t4004, ptr %t4005
  call void @__inc_ref(ptr %t13)
  %t4006 = getelementptr ptr, ptr %t4000, i32 2
  store ptr %t13, ptr %t4006
  call void @__inc_ref(ptr %t3985)
  %t4007 = getelementptr ptr, ptr %t4000, i32 3
  store ptr %t3985, ptr %t4007
  %t4008 = getelementptr ptr, ptr %t3986, i32 2
  store ptr %t4000, ptr %t4008
  call void @__free_recursive(ptr %t3985)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t3986, ptr %t3
  br label %tco.loop.0
tco.case.arm.241.4009:
  %t4010 = call ptr @__alloc(i64 32, i32 3)
  %t4011 = inttoptr i64 88 to ptr
  %t4012 = getelementptr ptr, ptr %t4010, i32 0
  store ptr %t4011, ptr %t4012
  %t4013 = getelementptr ptr, ptr %t11, i32 3
  %t4014 = load ptr, ptr %t4013
  call void @__inc_ref(ptr %t4014)
  %t4015 = getelementptr ptr, ptr %t4010, i32 1
  store ptr %t4014, ptr %t4015
  %t4016 = getelementptr ptr, ptr %t11, i32 2
  %t4017 = load ptr, ptr %t4016
  call void @__inc_ref(ptr %t4017)
  %t4018 = getelementptr ptr, ptr %t4010, i32 2
  store ptr %t4017, ptr %t4018
  call void @__inc_ref(ptr %t13)
  %t4019 = getelementptr ptr, ptr %t4010, i32 3
  store ptr %t13, ptr %t4019
  %t4020 = getelementptr ptr, ptr %t11, i32 1
  %t4021 = load ptr, ptr %t4020
  call void @__inc_ref(ptr %t4021)
  %t4022 = getelementptr ptr, ptr %t4, i32 1
  %t4023 = load ptr, ptr %t4022
  call void @__free_recursive(ptr %t4023)
  %t4024 = getelementptr ptr, ptr %t4, i32 2
  %t4025 = load ptr, ptr %t4024
  call void @__free_recursive(ptr %t4025)
  %t4028 = inttoptr i64 280 to ptr
  %t4029 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t4028, ptr %t4029
  %t4026 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t4010, ptr %t4026
  %t4027 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t4021, ptr %t4027
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.240.4030:
  %t4031 = getelementptr ptr, ptr %t11, i32 4
  %t4032 = load ptr, ptr %t4031
  call void @__inc_ref(ptr %t4032)
  %t4033 = call ptr @__alloc(i64 32, i32 3)
  %t4034 = inttoptr i64 88 to ptr
  %t4035 = getelementptr ptr, ptr %t4033, i32 0
  store ptr %t4034, ptr %t4035
  call void @__inc_ref(ptr %t4032)
  %t4036 = getelementptr ptr, ptr %t4033, i32 1
  store ptr %t4032, ptr %t4036
  %t4037 = getelementptr ptr, ptr %t11, i32 3
  %t4038 = load ptr, ptr %t4037
  call void @__inc_ref(ptr %t4038)
  %t4039 = getelementptr ptr, ptr %t4033, i32 2
  store ptr %t4038, ptr %t4039
  call void @__inc_ref(ptr %t13)
  %t4040 = getelementptr ptr, ptr %t4033, i32 3
  store ptr %t13, ptr %t4040
  %t4041 = call ptr @__alloc(i64 32, i32 3)
  %t4042 = inttoptr i64 241 to ptr
  %t4043 = getelementptr ptr, ptr %t4041, i32 0
  store ptr %t4042, ptr %t4043
  %t4044 = getelementptr ptr, ptr %t11, i32 1
  %t4045 = load ptr, ptr %t4044
  call void @__inc_ref(ptr %t4045)
  %t4046 = getelementptr ptr, ptr %t4041, i32 1
  store ptr %t4045, ptr %t4046
  %t4047 = getelementptr ptr, ptr %t11, i32 2
  %t4048 = load ptr, ptr %t4047
  call void @__inc_ref(ptr %t4048)
  %t4049 = getelementptr ptr, ptr %t4041, i32 2
  store ptr %t4048, ptr %t4049
  call void @__inc_ref(ptr %t4032)
  %t4050 = getelementptr ptr, ptr %t4041, i32 3
  store ptr %t4032, ptr %t4050
  %t4051 = getelementptr ptr, ptr %t4, i32 1
  %t4052 = load ptr, ptr %t4051
  call void @__free_recursive(ptr %t4052)
  %t4053 = getelementptr ptr, ptr %t4, i32 2
  %t4054 = load ptr, ptr %t4053
  call void @__free_recursive(ptr %t4054)
  %t4057 = inttoptr i64 280 to ptr
  %t4058 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t4057, ptr %t4058
  %t4055 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t4033, ptr %t4055
  %t4056 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t4041, ptr %t4056
  call void @__free_recursive(ptr %t4032)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.239.4059:
  %t4060 = getelementptr ptr, ptr %t11, i32 4
  %t4061 = load ptr, ptr %t4060
  call void @__inc_ref(ptr %t4061)
  %t4062 = call ptr @__alloc(i64 24, i32 2)
  %t4063 = inttoptr i64 280 to ptr
  %t4064 = getelementptr ptr, ptr %t4062, i32 0
  store ptr %t4063, ptr %t4064
  %t4065 = getelementptr ptr, ptr %t11, i32 3
  %t4066 = load ptr, ptr %t4065
  call void @__inc_ref(ptr %t4066)
  %t4067 = getelementptr ptr, ptr %t4, i32 1
  %t4068 = load ptr, ptr %t4067
  call void @__free_recursive(ptr %t4068)
  %t4069 = getelementptr ptr, ptr %t4, i32 2
  %t4070 = load ptr, ptr %t4069
  call void @__free_recursive(ptr %t4070)
  %t4073 = inttoptr i64 101 to ptr
  %t4074 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t4073, ptr %t4074
  call void @__inc_ref(ptr %t4061)
  %t4071 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t4061, ptr %t4071
  %t4072 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t4066, ptr %t4072
  %t4075 = getelementptr ptr, ptr %t4062, i32 1
  store ptr %t4, ptr %t4075
  %t4076 = call ptr @__alloc(i64 40, i32 4)
  %t4077 = inttoptr i64 240 to ptr
  %t4078 = getelementptr ptr, ptr %t4076, i32 0
  store ptr %t4077, ptr %t4078
  %t4079 = getelementptr ptr, ptr %t11, i32 1
  %t4080 = load ptr, ptr %t4079
  call void @__inc_ref(ptr %t4080)
  %t4081 = getelementptr ptr, ptr %t4076, i32 1
  store ptr %t4080, ptr %t4081
  %t4082 = getelementptr ptr, ptr %t11, i32 2
  %t4083 = load ptr, ptr %t4082
  call void @__inc_ref(ptr %t4083)
  %t4084 = getelementptr ptr, ptr %t4076, i32 2
  store ptr %t4083, ptr %t4084
  call void @__inc_ref(ptr %t13)
  %t4085 = getelementptr ptr, ptr %t4076, i32 3
  store ptr %t13, ptr %t4085
  call void @__inc_ref(ptr %t4061)
  %t4086 = getelementptr ptr, ptr %t4076, i32 4
  store ptr %t4061, ptr %t4086
  %t4087 = getelementptr ptr, ptr %t4062, i32 2
  store ptr %t4076, ptr %t4087
  call void @__free_recursive(ptr %t4061)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4062, ptr %t3
  br label %tco.loop.0
tco.case.arm.238.4088:
  %t4089 = getelementptr ptr, ptr %t11, i32 4
  %t4090 = load ptr, ptr %t4089
  call void @__inc_ref(ptr %t4090)
  %t4091 = call ptr @__alloc(i64 24, i32 2)
  %t4092 = inttoptr i64 280 to ptr
  %t4093 = getelementptr ptr, ptr %t4091, i32 0
  store ptr %t4092, ptr %t4093
  %t4094 = getelementptr ptr, ptr %t11, i32 2
  %t4095 = load ptr, ptr %t4094
  call void @__inc_ref(ptr %t4095)
  %t4096 = getelementptr ptr, ptr %t4, i32 1
  %t4097 = load ptr, ptr %t4096
  call void @__free_recursive(ptr %t4097)
  %t4098 = getelementptr ptr, ptr %t4, i32 2
  %t4099 = load ptr, ptr %t4098
  call void @__free_recursive(ptr %t4099)
  %t4102 = inttoptr i64 101 to ptr
  %t4103 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t4102, ptr %t4103
  call void @__inc_ref(ptr %t4090)
  %t4100 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t4090, ptr %t4100
  %t4101 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t4095, ptr %t4101
  %t4104 = getelementptr ptr, ptr %t4091, i32 1
  store ptr %t4, ptr %t4104
  %t4105 = call ptr @__alloc(i64 40, i32 4)
  %t4106 = inttoptr i64 239 to ptr
  %t4107 = getelementptr ptr, ptr %t4105, i32 0
  store ptr %t4106, ptr %t4107
  %t4108 = getelementptr ptr, ptr %t11, i32 1
  %t4109 = load ptr, ptr %t4108
  call void @__inc_ref(ptr %t4109)
  %t4110 = getelementptr ptr, ptr %t4105, i32 1
  store ptr %t4109, ptr %t4110
  call void @__inc_ref(ptr %t13)
  %t4111 = getelementptr ptr, ptr %t4105, i32 2
  store ptr %t13, ptr %t4111
  %t4112 = getelementptr ptr, ptr %t11, i32 3
  %t4113 = load ptr, ptr %t4112
  call void @__inc_ref(ptr %t4113)
  %t4114 = getelementptr ptr, ptr %t4105, i32 3
  store ptr %t4113, ptr %t4114
  call void @__inc_ref(ptr %t4090)
  %t4115 = getelementptr ptr, ptr %t4105, i32 4
  store ptr %t4090, ptr %t4115
  %t4116 = getelementptr ptr, ptr %t4091, i32 2
  store ptr %t4105, ptr %t4116
  call void @__free_recursive(ptr %t4090)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4091, ptr %t3
  br label %tco.loop.0
tco.case.arm.247.4117:
  %t4118 = call ptr @__alloc(i64 32, i32 3)
  %t4119 = inttoptr i64 88 to ptr
  %t4120 = getelementptr ptr, ptr %t4118, i32 0
  store ptr %t4119, ptr %t4120
  %t4121 = getelementptr ptr, ptr %t11, i32 3
  %t4122 = load ptr, ptr %t4121
  call void @__inc_ref(ptr %t4122)
  %t4123 = getelementptr ptr, ptr %t4118, i32 1
  store ptr %t4122, ptr %t4123
  %t4124 = getelementptr ptr, ptr %t11, i32 2
  %t4125 = load ptr, ptr %t4124
  call void @__inc_ref(ptr %t4125)
  %t4126 = getelementptr ptr, ptr %t4118, i32 2
  store ptr %t4125, ptr %t4126
  call void @__inc_ref(ptr %t13)
  %t4127 = getelementptr ptr, ptr %t4118, i32 3
  store ptr %t13, ptr %t4127
  %t4128 = getelementptr ptr, ptr %t11, i32 1
  %t4129 = load ptr, ptr %t4128
  call void @__inc_ref(ptr %t4129)
  %t4130 = getelementptr ptr, ptr %t4, i32 1
  %t4131 = load ptr, ptr %t4130
  call void @__free_recursive(ptr %t4131)
  %t4132 = getelementptr ptr, ptr %t4, i32 2
  %t4133 = load ptr, ptr %t4132
  call void @__free_recursive(ptr %t4133)
  %t4136 = inttoptr i64 280 to ptr
  %t4137 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t4136, ptr %t4137
  %t4134 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t4118, ptr %t4134
  %t4135 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t4129, ptr %t4135
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.246.4138:
  %t4139 = getelementptr ptr, ptr %t11, i32 4
  %t4140 = load ptr, ptr %t4139
  call void @__inc_ref(ptr %t4140)
  %t4141 = call ptr @__alloc(i64 32, i32 3)
  %t4142 = inttoptr i64 88 to ptr
  %t4143 = getelementptr ptr, ptr %t4141, i32 0
  store ptr %t4142, ptr %t4143
  call void @__inc_ref(ptr %t4140)
  %t4144 = getelementptr ptr, ptr %t4141, i32 1
  store ptr %t4140, ptr %t4144
  %t4145 = getelementptr ptr, ptr %t11, i32 3
  %t4146 = load ptr, ptr %t4145
  call void @__inc_ref(ptr %t4146)
  %t4147 = getelementptr ptr, ptr %t4141, i32 2
  store ptr %t4146, ptr %t4147
  call void @__inc_ref(ptr %t13)
  %t4148 = getelementptr ptr, ptr %t4141, i32 3
  store ptr %t13, ptr %t4148
  %t4149 = call ptr @__alloc(i64 32, i32 3)
  %t4150 = inttoptr i64 247 to ptr
  %t4151 = getelementptr ptr, ptr %t4149, i32 0
  store ptr %t4150, ptr %t4151
  %t4152 = getelementptr ptr, ptr %t11, i32 1
  %t4153 = load ptr, ptr %t4152
  call void @__inc_ref(ptr %t4153)
  %t4154 = getelementptr ptr, ptr %t4149, i32 1
  store ptr %t4153, ptr %t4154
  %t4155 = getelementptr ptr, ptr %t11, i32 2
  %t4156 = load ptr, ptr %t4155
  call void @__inc_ref(ptr %t4156)
  %t4157 = getelementptr ptr, ptr %t4149, i32 2
  store ptr %t4156, ptr %t4157
  call void @__inc_ref(ptr %t4140)
  %t4158 = getelementptr ptr, ptr %t4149, i32 3
  store ptr %t4140, ptr %t4158
  %t4159 = getelementptr ptr, ptr %t4, i32 1
  %t4160 = load ptr, ptr %t4159
  call void @__free_recursive(ptr %t4160)
  %t4161 = getelementptr ptr, ptr %t4, i32 2
  %t4162 = load ptr, ptr %t4161
  call void @__free_recursive(ptr %t4162)
  %t4165 = inttoptr i64 280 to ptr
  %t4166 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t4165, ptr %t4166
  %t4163 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t4141, ptr %t4163
  %t4164 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t4149, ptr %t4164
  call void @__free_recursive(ptr %t4140)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.245.4167:
  %t4168 = getelementptr ptr, ptr %t11, i32 5
  %t4169 = load ptr, ptr %t4168
  call void @__inc_ref(ptr %t4169)
  %t4170 = call ptr @__alloc(i64 32, i32 3)
  %t4171 = inttoptr i64 88 to ptr
  %t4172 = getelementptr ptr, ptr %t4170, i32 0
  store ptr %t4171, ptr %t4172
  call void @__inc_ref(ptr %t4169)
  %t4173 = getelementptr ptr, ptr %t4170, i32 1
  store ptr %t4169, ptr %t4173
  %t4174 = getelementptr ptr, ptr %t11, i32 4
  %t4175 = load ptr, ptr %t4174
  call void @__inc_ref(ptr %t4175)
  %t4176 = getelementptr ptr, ptr %t4170, i32 2
  store ptr %t4175, ptr %t4176
  call void @__inc_ref(ptr %t13)
  %t4177 = getelementptr ptr, ptr %t4170, i32 3
  store ptr %t13, ptr %t4177
  %t4178 = call ptr @__alloc(i64 40, i32 4)
  %t4179 = inttoptr i64 246 to ptr
  %t4180 = getelementptr ptr, ptr %t4178, i32 0
  store ptr %t4179, ptr %t4180
  %t4181 = getelementptr ptr, ptr %t11, i32 1
  %t4182 = load ptr, ptr %t4181
  call void @__inc_ref(ptr %t4182)
  %t4183 = getelementptr ptr, ptr %t4178, i32 1
  store ptr %t4182, ptr %t4183
  %t4184 = getelementptr ptr, ptr %t11, i32 2
  %t4185 = load ptr, ptr %t4184
  call void @__inc_ref(ptr %t4185)
  %t4186 = getelementptr ptr, ptr %t4178, i32 2
  store ptr %t4185, ptr %t4186
  %t4187 = getelementptr ptr, ptr %t11, i32 3
  %t4188 = load ptr, ptr %t4187
  call void @__inc_ref(ptr %t4188)
  %t4189 = getelementptr ptr, ptr %t4178, i32 3
  store ptr %t4188, ptr %t4189
  call void @__inc_ref(ptr %t4169)
  %t4190 = getelementptr ptr, ptr %t4178, i32 4
  store ptr %t4169, ptr %t4190
  %t4191 = getelementptr ptr, ptr %t4, i32 1
  %t4192 = load ptr, ptr %t4191
  call void @__free_recursive(ptr %t4192)
  %t4193 = getelementptr ptr, ptr %t4, i32 2
  %t4194 = load ptr, ptr %t4193
  call void @__free_recursive(ptr %t4194)
  %t4197 = inttoptr i64 280 to ptr
  %t4198 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t4197, ptr %t4198
  %t4195 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t4170, ptr %t4195
  %t4196 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t4178, ptr %t4196
  call void @__free_recursive(ptr %t4169)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.244.4199:
  %t4200 = getelementptr ptr, ptr %t11, i32 5
  %t4201 = load ptr, ptr %t4200
  call void @__inc_ref(ptr %t4201)
  %t4202 = call ptr @__alloc(i64 24, i32 2)
  %t4203 = inttoptr i64 280 to ptr
  %t4204 = getelementptr ptr, ptr %t4202, i32 0
  store ptr %t4203, ptr %t4204
  %t4205 = getelementptr ptr, ptr %t11, i32 4
  %t4206 = load ptr, ptr %t4205
  call void @__inc_ref(ptr %t4206)
  %t4207 = getelementptr ptr, ptr %t4, i32 1
  %t4208 = load ptr, ptr %t4207
  call void @__free_recursive(ptr %t4208)
  %t4209 = getelementptr ptr, ptr %t4, i32 2
  %t4210 = load ptr, ptr %t4209
  call void @__free_recursive(ptr %t4210)
  %t4213 = inttoptr i64 101 to ptr
  %t4214 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t4213, ptr %t4214
  call void @__inc_ref(ptr %t4201)
  %t4211 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t4201, ptr %t4211
  %t4212 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t4206, ptr %t4212
  %t4215 = getelementptr ptr, ptr %t4202, i32 1
  store ptr %t4, ptr %t4215
  %t4216 = call ptr @__alloc(i64 48, i32 5)
  %t4217 = inttoptr i64 245 to ptr
  %t4218 = getelementptr ptr, ptr %t4216, i32 0
  store ptr %t4217, ptr %t4218
  %t4219 = getelementptr ptr, ptr %t11, i32 1
  %t4220 = load ptr, ptr %t4219
  call void @__inc_ref(ptr %t4220)
  %t4221 = getelementptr ptr, ptr %t4216, i32 1
  store ptr %t4220, ptr %t4221
  %t4222 = getelementptr ptr, ptr %t11, i32 2
  %t4223 = load ptr, ptr %t4222
  call void @__inc_ref(ptr %t4223)
  %t4224 = getelementptr ptr, ptr %t4216, i32 2
  store ptr %t4223, ptr %t4224
  %t4225 = getelementptr ptr, ptr %t11, i32 3
  %t4226 = load ptr, ptr %t4225
  call void @__inc_ref(ptr %t4226)
  %t4227 = getelementptr ptr, ptr %t4216, i32 3
  store ptr %t4226, ptr %t4227
  call void @__inc_ref(ptr %t13)
  %t4228 = getelementptr ptr, ptr %t4216, i32 4
  store ptr %t13, ptr %t4228
  call void @__inc_ref(ptr %t4201)
  %t4229 = getelementptr ptr, ptr %t4216, i32 5
  store ptr %t4201, ptr %t4229
  %t4230 = getelementptr ptr, ptr %t4202, i32 2
  store ptr %t4216, ptr %t4230
  call void @__free_recursive(ptr %t4201)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4202, ptr %t3
  br label %tco.loop.0
tco.case.arm.243.4231:
  %t4232 = getelementptr ptr, ptr %t11, i32 5
  %t4233 = load ptr, ptr %t4232
  call void @__inc_ref(ptr %t4233)
  %t4234 = call ptr @__alloc(i64 24, i32 2)
  %t4235 = inttoptr i64 280 to ptr
  %t4236 = getelementptr ptr, ptr %t4234, i32 0
  store ptr %t4235, ptr %t4236
  %t4237 = getelementptr ptr, ptr %t11, i32 3
  %t4238 = load ptr, ptr %t4237
  call void @__inc_ref(ptr %t4238)
  %t4239 = getelementptr ptr, ptr %t4, i32 1
  %t4240 = load ptr, ptr %t4239
  call void @__free_recursive(ptr %t4240)
  %t4241 = getelementptr ptr, ptr %t4, i32 2
  %t4242 = load ptr, ptr %t4241
  call void @__free_recursive(ptr %t4242)
  %t4245 = inttoptr i64 101 to ptr
  %t4246 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t4245, ptr %t4246
  call void @__inc_ref(ptr %t4233)
  %t4243 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t4233, ptr %t4243
  %t4244 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t4238, ptr %t4244
  %t4247 = getelementptr ptr, ptr %t4234, i32 1
  store ptr %t4, ptr %t4247
  %t4248 = call ptr @__alloc(i64 48, i32 5)
  %t4249 = inttoptr i64 244 to ptr
  %t4250 = getelementptr ptr, ptr %t4248, i32 0
  store ptr %t4249, ptr %t4250
  %t4251 = getelementptr ptr, ptr %t11, i32 1
  %t4252 = load ptr, ptr %t4251
  call void @__inc_ref(ptr %t4252)
  %t4253 = getelementptr ptr, ptr %t4248, i32 1
  store ptr %t4252, ptr %t4253
  %t4254 = getelementptr ptr, ptr %t11, i32 2
  %t4255 = load ptr, ptr %t4254
  call void @__inc_ref(ptr %t4255)
  %t4256 = getelementptr ptr, ptr %t4248, i32 2
  store ptr %t4255, ptr %t4256
  call void @__inc_ref(ptr %t13)
  %t4257 = getelementptr ptr, ptr %t4248, i32 3
  store ptr %t13, ptr %t4257
  %t4258 = getelementptr ptr, ptr %t11, i32 4
  %t4259 = load ptr, ptr %t4258
  call void @__inc_ref(ptr %t4259)
  %t4260 = getelementptr ptr, ptr %t4248, i32 4
  store ptr %t4259, ptr %t4260
  call void @__inc_ref(ptr %t4233)
  %t4261 = getelementptr ptr, ptr %t4248, i32 5
  store ptr %t4233, ptr %t4261
  %t4262 = getelementptr ptr, ptr %t4234, i32 2
  store ptr %t4248, ptr %t4262
  call void @__free_recursive(ptr %t4233)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4234, ptr %t3
  br label %tco.loop.0
tco.case.arm.242.4263:
  %t4264 = getelementptr ptr, ptr %t11, i32 5
  %t4265 = load ptr, ptr %t4264
  call void @__inc_ref(ptr %t4265)
  %t4266 = call ptr @__alloc(i64 24, i32 2)
  %t4267 = inttoptr i64 280 to ptr
  %t4268 = getelementptr ptr, ptr %t4266, i32 0
  store ptr %t4267, ptr %t4268
  %t4269 = getelementptr ptr, ptr %t11, i32 2
  %t4270 = load ptr, ptr %t4269
  call void @__inc_ref(ptr %t4270)
  %t4271 = getelementptr ptr, ptr %t4, i32 1
  %t4272 = load ptr, ptr %t4271
  call void @__free_recursive(ptr %t4272)
  %t4273 = getelementptr ptr, ptr %t4, i32 2
  %t4274 = load ptr, ptr %t4273
  call void @__free_recursive(ptr %t4274)
  %t4277 = inttoptr i64 101 to ptr
  %t4278 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t4277, ptr %t4278
  call void @__inc_ref(ptr %t4265)
  %t4275 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t4265, ptr %t4275
  %t4276 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t4270, ptr %t4276
  %t4279 = getelementptr ptr, ptr %t4266, i32 1
  store ptr %t4, ptr %t4279
  %t4280 = call ptr @__alloc(i64 48, i32 5)
  %t4281 = inttoptr i64 243 to ptr
  %t4282 = getelementptr ptr, ptr %t4280, i32 0
  store ptr %t4281, ptr %t4282
  %t4283 = getelementptr ptr, ptr %t11, i32 1
  %t4284 = load ptr, ptr %t4283
  call void @__inc_ref(ptr %t4284)
  %t4285 = getelementptr ptr, ptr %t4280, i32 1
  store ptr %t4284, ptr %t4285
  call void @__inc_ref(ptr %t13)
  %t4286 = getelementptr ptr, ptr %t4280, i32 2
  store ptr %t13, ptr %t4286
  %t4287 = getelementptr ptr, ptr %t11, i32 3
  %t4288 = load ptr, ptr %t4287
  call void @__inc_ref(ptr %t4288)
  %t4289 = getelementptr ptr, ptr %t4280, i32 3
  store ptr %t4288, ptr %t4289
  %t4290 = getelementptr ptr, ptr %t11, i32 4
  %t4291 = load ptr, ptr %t4290
  call void @__inc_ref(ptr %t4291)
  %t4292 = getelementptr ptr, ptr %t4280, i32 4
  store ptr %t4291, ptr %t4292
  call void @__inc_ref(ptr %t4265)
  %t4293 = getelementptr ptr, ptr %t4280, i32 5
  store ptr %t4265, ptr %t4293
  %t4294 = getelementptr ptr, ptr %t4266, i32 2
  store ptr %t4280, ptr %t4294
  call void @__free_recursive(ptr %t4265)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4266, ptr %t3
  br label %tco.loop.0
tco.case.arm.250.4295:
  %t4296 = getelementptr ptr, ptr %t11, i32 1
  %t4297 = load ptr, ptr %t4296
  call void @__inc_ref(ptr %t4297)
  %t4298 = call ptr @__alloc(i64 32, i32 3)
  %t4299 = inttoptr i64 28 to ptr
  %t4300 = getelementptr ptr, ptr %t4298, i32 0
  store ptr %t4299, ptr %t4300
  call void @__inc_ref(ptr %t13)
  %t4301 = getelementptr ptr, ptr %t4298, i32 1
  store ptr %t13, ptr %t4301
  %t4302 = getelementptr ptr, ptr %t11, i32 2
  %t4303 = load ptr, ptr %t4302
  call void @__inc_ref(ptr %t4303)
  %t4304 = getelementptr ptr, ptr %t4298, i32 2
  store ptr %t4303, ptr %t4304
  %t4305 = getelementptr ptr, ptr %t11, i32 3
  %t4306 = load ptr, ptr %t4305
  call void @__inc_ref(ptr %t4306)
  %t4307 = getelementptr ptr, ptr %t4298, i32 3
  store ptr %t4306, ptr %t4307
  %t4308 = getelementptr ptr, ptr %t4, i32 1
  %t4309 = load ptr, ptr %t4308
  call void @__free_recursive(ptr %t4309)
  %t4310 = getelementptr ptr, ptr %t4, i32 2
  %t4311 = load ptr, ptr %t4310
  call void @__free_recursive(ptr %t4311)
  %t4314 = inttoptr i64 279 to ptr
  %t4315 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t4314, ptr %t4315
  %t4312 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t4297, ptr %t4312
  %t4313 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t4298, ptr %t4313
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.249.4316:
  %t4317 = call ptr @__alloc(i64 32, i32 3)
  %t4318 = inttoptr i64 88 to ptr
  %t4319 = getelementptr ptr, ptr %t4317, i32 0
  store ptr %t4318, ptr %t4319
  %t4320 = getelementptr ptr, ptr %t11, i32 3
  %t4321 = load ptr, ptr %t4320
  call void @__inc_ref(ptr %t4321)
  %t4322 = getelementptr ptr, ptr %t4317, i32 1
  store ptr %t4321, ptr %t4322
  %t4323 = getelementptr ptr, ptr %t11, i32 2
  %t4324 = load ptr, ptr %t4323
  call void @__inc_ref(ptr %t4324)
  %t4325 = getelementptr ptr, ptr %t4317, i32 2
  store ptr %t4324, ptr %t4325
  call void @__inc_ref(ptr %t13)
  %t4326 = getelementptr ptr, ptr %t4317, i32 3
  store ptr %t13, ptr %t4326
  %t4327 = call ptr @__alloc(i64 32, i32 3)
  %t4328 = inttoptr i64 250 to ptr
  %t4329 = getelementptr ptr, ptr %t4327, i32 0
  store ptr %t4328, ptr %t4329
  %t4330 = getelementptr ptr, ptr %t11, i32 1
  %t4331 = load ptr, ptr %t4330
  call void @__inc_ref(ptr %t4331)
  %t4332 = getelementptr ptr, ptr %t4327, i32 1
  store ptr %t4331, ptr %t4332
  %t4333 = getelementptr ptr, ptr %t11, i32 4
  %t4334 = load ptr, ptr %t4333
  call void @__inc_ref(ptr %t4334)
  %t4335 = getelementptr ptr, ptr %t4327, i32 2
  store ptr %t4334, ptr %t4335
  %t4336 = getelementptr ptr, ptr %t11, i32 5
  %t4337 = load ptr, ptr %t4336
  call void @__inc_ref(ptr %t4337)
  %t4338 = getelementptr ptr, ptr %t4327, i32 3
  store ptr %t4337, ptr %t4338
  %t4339 = getelementptr ptr, ptr %t4, i32 1
  %t4340 = load ptr, ptr %t4339
  call void @__free_recursive(ptr %t4340)
  %t4341 = getelementptr ptr, ptr %t4, i32 2
  %t4342 = load ptr, ptr %t4341
  call void @__free_recursive(ptr %t4342)
  %t4345 = inttoptr i64 280 to ptr
  %t4346 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t4345, ptr %t4346
  %t4343 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t4317, ptr %t4343
  %t4344 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t4327, ptr %t4344
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.248.4347:
  %t4348 = getelementptr ptr, ptr %t11, i32 2
  %t4349 = load ptr, ptr %t4348
  call void @__inc_ref(ptr %t4349)
  %t4350 = getelementptr ptr, ptr %t11, i32 4
  %t4351 = load ptr, ptr %t4350
  call void @__inc_ref(ptr %t4351)
  %t4352 = call ptr @__alloc(i64 24, i32 2)
  %t4353 = inttoptr i64 280 to ptr
  %t4354 = getelementptr ptr, ptr %t4352, i32 0
  store ptr %t4353, ptr %t4354
  %t4355 = getelementptr ptr, ptr %t4, i32 1
  %t4356 = load ptr, ptr %t4355
  call void @__free_recursive(ptr %t4356)
  %t4357 = getelementptr ptr, ptr %t4, i32 2
  %t4358 = load ptr, ptr %t4357
  call void @__free_recursive(ptr %t4358)
  %t4361 = inttoptr i64 101 to ptr
  %t4362 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t4361, ptr %t4362
  call void @__inc_ref(ptr %t4349)
  %t4359 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t4349, ptr %t4359
  call void @__inc_ref(ptr %t4351)
  %t4360 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t4351, ptr %t4360
  %t4363 = getelementptr ptr, ptr %t4352, i32 1
  store ptr %t4, ptr %t4363
  %t4364 = call ptr @__alloc(i64 48, i32 5)
  %t4365 = inttoptr i64 249 to ptr
  %t4366 = getelementptr ptr, ptr %t4364, i32 0
  store ptr %t4365, ptr %t4366
  %t4367 = getelementptr ptr, ptr %t11, i32 1
  %t4368 = load ptr, ptr %t4367
  call void @__inc_ref(ptr %t4368)
  %t4369 = getelementptr ptr, ptr %t4364, i32 1
  store ptr %t4368, ptr %t4369
  call void @__inc_ref(ptr %t13)
  %t4370 = getelementptr ptr, ptr %t4364, i32 2
  store ptr %t13, ptr %t4370
  call void @__inc_ref(ptr %t4349)
  %t4371 = getelementptr ptr, ptr %t4364, i32 3
  store ptr %t4349, ptr %t4371
  %t4372 = getelementptr ptr, ptr %t11, i32 3
  %t4373 = load ptr, ptr %t4372
  call void @__inc_ref(ptr %t4373)
  %t4374 = getelementptr ptr, ptr %t4364, i32 4
  store ptr %t4373, ptr %t4374
  call void @__inc_ref(ptr %t4351)
  %t4375 = getelementptr ptr, ptr %t4364, i32 5
  store ptr %t4351, ptr %t4375
  %t4376 = getelementptr ptr, ptr %t4352, i32 2
  store ptr %t4364, ptr %t4376
  call void @__free_recursive(ptr %t4351)
  call void @__free_recursive(ptr %t4349)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4352, ptr %t3
  br label %tco.loop.0
tco.case.arm.255.4377:
  %t4378 = getelementptr ptr, ptr %t11, i32 1
  %t4379 = load ptr, ptr %t4378
  call void @__inc_ref(ptr %t4379)
  %t4380 = call ptr @__alloc(i64 40, i32 4)
  %t4381 = inttoptr i64 29 to ptr
  %t4382 = getelementptr ptr, ptr %t4380, i32 0
  store ptr %t4381, ptr %t4382
  call void @__inc_ref(ptr %t13)
  %t4383 = getelementptr ptr, ptr %t4380, i32 1
  store ptr %t13, ptr %t4383
  %t4384 = getelementptr ptr, ptr %t11, i32 2
  %t4385 = load ptr, ptr %t4384
  call void @__inc_ref(ptr %t4385)
  %t4386 = getelementptr ptr, ptr %t4380, i32 2
  store ptr %t4385, ptr %t4386
  %t4387 = getelementptr ptr, ptr %t11, i32 3
  %t4388 = load ptr, ptr %t4387
  call void @__inc_ref(ptr %t4388)
  %t4389 = getelementptr ptr, ptr %t4380, i32 3
  store ptr %t4388, ptr %t4389
  %t4390 = getelementptr ptr, ptr %t11, i32 4
  %t4391 = load ptr, ptr %t4390
  call void @__inc_ref(ptr %t4391)
  %t4392 = getelementptr ptr, ptr %t4380, i32 4
  store ptr %t4391, ptr %t4392
  %t4393 = getelementptr ptr, ptr %t4, i32 1
  %t4394 = load ptr, ptr %t4393
  call void @__free_recursive(ptr %t4394)
  %t4395 = getelementptr ptr, ptr %t4, i32 2
  %t4396 = load ptr, ptr %t4395
  call void @__free_recursive(ptr %t4396)
  %t4399 = inttoptr i64 279 to ptr
  %t4400 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t4399, ptr %t4400
  %t4397 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t4379, ptr %t4397
  %t4398 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t4380, ptr %t4398
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.254.4401:
  %t4402 = call ptr @__alloc(i64 32, i32 3)
  %t4403 = inttoptr i64 88 to ptr
  %t4404 = getelementptr ptr, ptr %t4402, i32 0
  store ptr %t4403, ptr %t4404
  %t4405 = getelementptr ptr, ptr %t11, i32 3
  %t4406 = load ptr, ptr %t4405
  call void @__inc_ref(ptr %t4406)
  %t4407 = getelementptr ptr, ptr %t4402, i32 1
  store ptr %t4406, ptr %t4407
  %t4408 = getelementptr ptr, ptr %t11, i32 2
  %t4409 = load ptr, ptr %t4408
  call void @__inc_ref(ptr %t4409)
  %t4410 = getelementptr ptr, ptr %t4402, i32 2
  store ptr %t4409, ptr %t4410
  call void @__inc_ref(ptr %t13)
  %t4411 = getelementptr ptr, ptr %t4402, i32 3
  store ptr %t13, ptr %t4411
  %t4412 = call ptr @__alloc(i64 40, i32 4)
  %t4413 = inttoptr i64 255 to ptr
  %t4414 = getelementptr ptr, ptr %t4412, i32 0
  store ptr %t4413, ptr %t4414
  %t4415 = getelementptr ptr, ptr %t11, i32 1
  %t4416 = load ptr, ptr %t4415
  call void @__inc_ref(ptr %t4416)
  %t4417 = getelementptr ptr, ptr %t4412, i32 1
  store ptr %t4416, ptr %t4417
  %t4418 = getelementptr ptr, ptr %t11, i32 4
  %t4419 = load ptr, ptr %t4418
  call void @__inc_ref(ptr %t4419)
  %t4420 = getelementptr ptr, ptr %t4412, i32 2
  store ptr %t4419, ptr %t4420
  %t4421 = getelementptr ptr, ptr %t11, i32 5
  %t4422 = load ptr, ptr %t4421
  call void @__inc_ref(ptr %t4422)
  %t4423 = getelementptr ptr, ptr %t4412, i32 3
  store ptr %t4422, ptr %t4423
  %t4424 = getelementptr ptr, ptr %t11, i32 6
  %t4425 = load ptr, ptr %t4424
  call void @__inc_ref(ptr %t4425)
  %t4426 = getelementptr ptr, ptr %t4412, i32 4
  store ptr %t4425, ptr %t4426
  %t4427 = getelementptr ptr, ptr %t4, i32 1
  %t4428 = load ptr, ptr %t4427
  call void @__free_recursive(ptr %t4428)
  %t4429 = getelementptr ptr, ptr %t4, i32 2
  %t4430 = load ptr, ptr %t4429
  call void @__free_recursive(ptr %t4430)
  %t4433 = inttoptr i64 280 to ptr
  %t4434 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t4433, ptr %t4434
  %t4431 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t4402, ptr %t4431
  %t4432 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t4412, ptr %t4432
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.253.4435:
  %t4436 = getelementptr ptr, ptr %t11, i32 2
  %t4437 = load ptr, ptr %t4436
  call void @__inc_ref(ptr %t4437)
  %t4438 = getelementptr ptr, ptr %t11, i32 5
  %t4439 = load ptr, ptr %t4438
  call void @__inc_ref(ptr %t4439)
  %t4440 = call ptr @__alloc(i64 24, i32 2)
  %t4441 = inttoptr i64 280 to ptr
  %t4442 = getelementptr ptr, ptr %t4440, i32 0
  store ptr %t4441, ptr %t4442
  %t4443 = getelementptr ptr, ptr %t4, i32 1
  %t4444 = load ptr, ptr %t4443
  call void @__free_recursive(ptr %t4444)
  %t4445 = getelementptr ptr, ptr %t4, i32 2
  %t4446 = load ptr, ptr %t4445
  call void @__free_recursive(ptr %t4446)
  %t4449 = inttoptr i64 101 to ptr
  %t4450 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t4449, ptr %t4450
  call void @__inc_ref(ptr %t4437)
  %t4447 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t4437, ptr %t4447
  call void @__inc_ref(ptr %t4439)
  %t4448 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t4439, ptr %t4448
  %t4451 = getelementptr ptr, ptr %t4440, i32 1
  store ptr %t4, ptr %t4451
  %t4452 = call ptr @__alloc(i64 56, i32 6)
  %t4453 = inttoptr i64 254 to ptr
  %t4454 = getelementptr ptr, ptr %t4452, i32 0
  store ptr %t4453, ptr %t4454
  %t4455 = getelementptr ptr, ptr %t11, i32 1
  %t4456 = load ptr, ptr %t4455
  call void @__inc_ref(ptr %t4456)
  %t4457 = getelementptr ptr, ptr %t4452, i32 1
  store ptr %t4456, ptr %t4457
  call void @__inc_ref(ptr %t13)
  %t4458 = getelementptr ptr, ptr %t4452, i32 2
  store ptr %t13, ptr %t4458
  call void @__inc_ref(ptr %t4437)
  %t4459 = getelementptr ptr, ptr %t4452, i32 3
  store ptr %t4437, ptr %t4459
  %t4460 = getelementptr ptr, ptr %t11, i32 3
  %t4461 = load ptr, ptr %t4460
  call void @__inc_ref(ptr %t4461)
  %t4462 = getelementptr ptr, ptr %t4452, i32 4
  store ptr %t4461, ptr %t4462
  %t4463 = getelementptr ptr, ptr %t11, i32 4
  %t4464 = load ptr, ptr %t4463
  call void @__inc_ref(ptr %t4464)
  %t4465 = getelementptr ptr, ptr %t4452, i32 5
  store ptr %t4464, ptr %t4465
  call void @__inc_ref(ptr %t4439)
  %t4466 = getelementptr ptr, ptr %t4452, i32 6
  store ptr %t4439, ptr %t4466
  %t4467 = getelementptr ptr, ptr %t4440, i32 2
  store ptr %t4452, ptr %t4467
  call void @__free_recursive(ptr %t4439)
  call void @__free_recursive(ptr %t4437)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4440, ptr %t3
  br label %tco.loop.0
tco.case.arm.252.4468:
  %t4469 = getelementptr ptr, ptr %t11, i32 3
  %t4470 = load ptr, ptr %t4469
  call void @__inc_ref(ptr %t4470)
  %t4471 = call ptr @__alloc(i64 32, i32 3)
  %t4472 = inttoptr i64 88 to ptr
  %t4473 = getelementptr ptr, ptr %t4471, i32 0
  store ptr %t4472, ptr %t4473
  call void @__inc_ref(ptr %t4470)
  %t4474 = getelementptr ptr, ptr %t4471, i32 1
  store ptr %t4470, ptr %t4474
  %t4475 = getelementptr ptr, ptr %t11, i32 2
  %t4476 = load ptr, ptr %t4475
  call void @__inc_ref(ptr %t4476)
  %t4477 = getelementptr ptr, ptr %t4471, i32 2
  store ptr %t4476, ptr %t4477
  call void @__inc_ref(ptr %t13)
  %t4478 = getelementptr ptr, ptr %t4471, i32 3
  store ptr %t13, ptr %t4478
  %t4479 = call ptr @__alloc(i64 48, i32 5)
  %t4480 = inttoptr i64 253 to ptr
  %t4481 = getelementptr ptr, ptr %t4479, i32 0
  store ptr %t4480, ptr %t4481
  %t4482 = getelementptr ptr, ptr %t11, i32 1
  %t4483 = load ptr, ptr %t4482
  call void @__inc_ref(ptr %t4483)
  %t4484 = getelementptr ptr, ptr %t4479, i32 1
  store ptr %t4483, ptr %t4484
  call void @__inc_ref(ptr %t4470)
  %t4485 = getelementptr ptr, ptr %t4479, i32 2
  store ptr %t4470, ptr %t4485
  %t4486 = getelementptr ptr, ptr %t11, i32 4
  %t4487 = load ptr, ptr %t4486
  call void @__inc_ref(ptr %t4487)
  %t4488 = getelementptr ptr, ptr %t4479, i32 3
  store ptr %t4487, ptr %t4488
  %t4489 = getelementptr ptr, ptr %t11, i32 5
  %t4490 = load ptr, ptr %t4489
  call void @__inc_ref(ptr %t4490)
  %t4491 = getelementptr ptr, ptr %t4479, i32 4
  store ptr %t4490, ptr %t4491
  %t4492 = getelementptr ptr, ptr %t11, i32 6
  %t4493 = load ptr, ptr %t4492
  call void @__inc_ref(ptr %t4493)
  %t4494 = getelementptr ptr, ptr %t4479, i32 5
  store ptr %t4493, ptr %t4494
  %t4495 = getelementptr ptr, ptr %t4, i32 1
  %t4496 = load ptr, ptr %t4495
  call void @__free_recursive(ptr %t4496)
  %t4497 = getelementptr ptr, ptr %t4, i32 2
  %t4498 = load ptr, ptr %t4497
  call void @__free_recursive(ptr %t4498)
  %t4501 = inttoptr i64 280 to ptr
  %t4502 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t4501, ptr %t4502
  %t4499 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t4471, ptr %t4499
  %t4500 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t4479, ptr %t4500
  call void @__free_recursive(ptr %t4470)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.251.4503:
  %t4504 = getelementptr ptr, ptr %t11, i32 2
  %t4505 = load ptr, ptr %t4504
  call void @__inc_ref(ptr %t4505)
  %t4506 = getelementptr ptr, ptr %t11, i32 4
  %t4507 = load ptr, ptr %t4506
  call void @__inc_ref(ptr %t4507)
  %t4508 = call ptr @__alloc(i64 24, i32 2)
  %t4509 = inttoptr i64 280 to ptr
  %t4510 = getelementptr ptr, ptr %t4508, i32 0
  store ptr %t4509, ptr %t4510
  %t4511 = getelementptr ptr, ptr %t4, i32 1
  %t4512 = load ptr, ptr %t4511
  call void @__free_recursive(ptr %t4512)
  %t4513 = getelementptr ptr, ptr %t4, i32 2
  %t4514 = load ptr, ptr %t4513
  call void @__free_recursive(ptr %t4514)
  %t4517 = inttoptr i64 101 to ptr
  %t4518 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t4517, ptr %t4518
  call void @__inc_ref(ptr %t4505)
  %t4515 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t4505, ptr %t4515
  call void @__inc_ref(ptr %t4507)
  %t4516 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t4507, ptr %t4516
  %t4519 = getelementptr ptr, ptr %t4508, i32 1
  store ptr %t4, ptr %t4519
  %t4520 = call ptr @__alloc(i64 56, i32 6)
  %t4521 = inttoptr i64 252 to ptr
  %t4522 = getelementptr ptr, ptr %t4520, i32 0
  store ptr %t4521, ptr %t4522
  %t4523 = getelementptr ptr, ptr %t11, i32 1
  %t4524 = load ptr, ptr %t4523
  call void @__inc_ref(ptr %t4524)
  %t4525 = getelementptr ptr, ptr %t4520, i32 1
  store ptr %t4524, ptr %t4525
  call void @__inc_ref(ptr %t13)
  %t4526 = getelementptr ptr, ptr %t4520, i32 2
  store ptr %t13, ptr %t4526
  call void @__inc_ref(ptr %t4505)
  %t4527 = getelementptr ptr, ptr %t4520, i32 3
  store ptr %t4505, ptr %t4527
  %t4528 = getelementptr ptr, ptr %t11, i32 3
  %t4529 = load ptr, ptr %t4528
  call void @__inc_ref(ptr %t4529)
  %t4530 = getelementptr ptr, ptr %t4520, i32 4
  store ptr %t4529, ptr %t4530
  call void @__inc_ref(ptr %t4507)
  %t4531 = getelementptr ptr, ptr %t4520, i32 5
  store ptr %t4507, ptr %t4531
  %t4532 = getelementptr ptr, ptr %t11, i32 5
  %t4533 = load ptr, ptr %t4532
  call void @__inc_ref(ptr %t4533)
  %t4534 = getelementptr ptr, ptr %t4520, i32 6
  store ptr %t4533, ptr %t4534
  %t4535 = getelementptr ptr, ptr %t4508, i32 2
  store ptr %t4520, ptr %t4535
  call void @__free_recursive(ptr %t4507)
  call void @__free_recursive(ptr %t4505)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4508, ptr %t3
  br label %tco.loop.0
tco.case.arm.256.4536:
  %t4537 = call ptr @__alloc(i64 24, i32 2)
  %t4538 = inttoptr i64 279 to ptr
  %t4539 = getelementptr ptr, ptr %t4537, i32 0
  store ptr %t4538, ptr %t4539
  %t4540 = getelementptr ptr, ptr %t11, i32 1
  %t4541 = load ptr, ptr %t4540
  call void @__inc_ref(ptr %t4541)
  %t4542 = getelementptr ptr, ptr %t4537, i32 1
  store ptr %t4541, ptr %t4542
  %t4543 = call ptr @__alloc(i64 8, i32 0)
  %t4544 = inttoptr i64 13 to ptr
  %t4545 = getelementptr ptr, ptr %t4543, i32 0
  store ptr %t4544, ptr %t4545
  %t4546 = getelementptr ptr, ptr %t4, i32 1
  %t4547 = load ptr, ptr %t4546
  call void @__free_recursive(ptr %t4547)
  %t4548 = getelementptr ptr, ptr %t4, i32 2
  %t4549 = load ptr, ptr %t4548
  call void @__free_recursive(ptr %t4549)
  %t4552 = inttoptr i64 14 to ptr
  %t4553 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t4552, ptr %t4553
  call void @__inc_ref(ptr %t13)
  %t4550 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t13, ptr %t4550
  %t4551 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t4543, ptr %t4551
  %t4554 = getelementptr ptr, ptr %t4537, i32 2
  store ptr %t4, ptr %t4554
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4537, ptr %t3
  br label %tco.loop.0
tco.case.arm.257.4555:
  %t4556 = call ptr @__alloc(i64 24, i32 2)
  %t4557 = inttoptr i64 279 to ptr
  %t4558 = getelementptr ptr, ptr %t4556, i32 0
  store ptr %t4557, ptr %t4558
  %t4559 = getelementptr ptr, ptr %t11, i32 1
  %t4560 = load ptr, ptr %t4559
  call void @__inc_ref(ptr %t4560)
  %t4561 = getelementptr ptr, ptr %t4556, i32 1
  store ptr %t4560, ptr %t4561
  %t4562 = call ptr @__alloc(i64 8, i32 0)
  %t4563 = inttoptr i64 13 to ptr
  %t4564 = getelementptr ptr, ptr %t4562, i32 0
  store ptr %t4563, ptr %t4564
  %t4565 = getelementptr ptr, ptr %t4, i32 1
  %t4566 = load ptr, ptr %t4565
  call void @__free_recursive(ptr %t4566)
  %t4567 = getelementptr ptr, ptr %t4, i32 2
  %t4568 = load ptr, ptr %t4567
  call void @__free_recursive(ptr %t4568)
  %t4571 = inttoptr i64 14 to ptr
  %t4572 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t4571, ptr %t4572
  call void @__inc_ref(ptr %t13)
  %t4569 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t13, ptr %t4569
  %t4570 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t4562, ptr %t4570
  %t4573 = getelementptr ptr, ptr %t4556, i32 2
  store ptr %t4, ptr %t4573
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4556, ptr %t3
  br label %tco.loop.0
tco.case.arm.259.4574:
  %t4575 = call ptr @__alloc(i64 24, i32 2)
  %t4576 = inttoptr i64 279 to ptr
  %t4577 = getelementptr ptr, ptr %t4575, i32 0
  store ptr %t4576, ptr %t4577
  %t4578 = getelementptr ptr, ptr %t11, i32 1
  %t4579 = load ptr, ptr %t4578
  call void @__inc_ref(ptr %t4579)
  %t4580 = getelementptr ptr, ptr %t4575, i32 1
  store ptr %t4579, ptr %t4580
  %t4581 = call ptr @__alloc(i64 24, i32 2)
  %t4582 = inttoptr i64 14 to ptr
  %t4583 = getelementptr ptr, ptr %t4581, i32 0
  store ptr %t4582, ptr %t4583
  %t4584 = getelementptr ptr, ptr %t11, i32 2
  %t4585 = load ptr, ptr %t4584
  call void @__inc_ref(ptr %t4585)
  %t4586 = getelementptr ptr, ptr %t4581, i32 1
  store ptr %t4585, ptr %t4586
  %t4587 = call ptr @__alloc(i64 8, i32 0)
  %t4588 = inttoptr i64 13 to ptr
  %t4589 = getelementptr ptr, ptr %t4587, i32 0
  store ptr %t4588, ptr %t4589
  %t4590 = getelementptr ptr, ptr %t4, i32 1
  %t4591 = load ptr, ptr %t4590
  call void @__free_recursive(ptr %t4591)
  %t4592 = getelementptr ptr, ptr %t4, i32 2
  %t4593 = load ptr, ptr %t4592
  call void @__free_recursive(ptr %t4593)
  %t4596 = inttoptr i64 14 to ptr
  %t4597 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t4596, ptr %t4597
  call void @__inc_ref(ptr %t13)
  %t4594 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t13, ptr %t4594
  %t4595 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t4587, ptr %t4595
  %t4598 = getelementptr ptr, ptr %t4581, i32 2
  store ptr %t4, ptr %t4598
  %t4599 = getelementptr ptr, ptr %t4575, i32 2
  store ptr %t4581, ptr %t4599
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4575, ptr %t3
  br label %tco.loop.0
tco.case.arm.258.4600:
  %t4601 = call ptr @__alloc(i64 24, i32 2)
  %t4602 = inttoptr i64 280 to ptr
  %t4603 = getelementptr ptr, ptr %t4601, i32 0
  store ptr %t4602, ptr %t4603
  %t4604 = call ptr @__alloc(i64 32, i32 3)
  %t4605 = inttoptr i64 104 to ptr
  %t4606 = getelementptr ptr, ptr %t4604, i32 0
  store ptr %t4605, ptr %t4606
  %t4607 = getelementptr ptr, ptr %t11, i32 4
  %t4608 = load ptr, ptr %t4607
  call void @__inc_ref(ptr %t4608)
  %t4609 = getelementptr ptr, ptr %t4604, i32 1
  store ptr %t4608, ptr %t4609
  %t4610 = getelementptr ptr, ptr %t11, i32 2
  %t4611 = load ptr, ptr %t4610
  call void @__inc_ref(ptr %t4611)
  %t4612 = getelementptr ptr, ptr %t4604, i32 2
  store ptr %t4611, ptr %t4612
  %t4613 = getelementptr ptr, ptr %t11, i32 3
  %t4614 = load ptr, ptr %t4613
  call void @__inc_ref(ptr %t4614)
  %t4615 = getelementptr ptr, ptr %t4604, i32 3
  store ptr %t4614, ptr %t4615
  %t4616 = getelementptr ptr, ptr %t4601, i32 1
  store ptr %t4604, ptr %t4616
  %t4617 = getelementptr ptr, ptr %t11, i32 1
  %t4618 = load ptr, ptr %t4617
  call void @__inc_ref(ptr %t4618)
  %t4619 = getelementptr ptr, ptr %t4, i32 1
  %t4620 = load ptr, ptr %t4619
  call void @__free_recursive(ptr %t4620)
  %t4622 = inttoptr i64 259 to ptr
  %t4623 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t4622, ptr %t4623
  %t4621 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t4618, ptr %t4621
  %t4624 = getelementptr ptr, ptr %t4601, i32 2
  store ptr %t4, ptr %t4624
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4601, ptr %t3
  br label %tco.loop.0
tco.case.arm.261.4625:
  %t4626 = call ptr @__alloc(i64 24, i32 2)
  %t4627 = inttoptr i64 279 to ptr
  %t4628 = getelementptr ptr, ptr %t4626, i32 0
  store ptr %t4627, ptr %t4628
  %t4629 = getelementptr ptr, ptr %t11, i32 1
  %t4630 = load ptr, ptr %t4629
  call void @__inc_ref(ptr %t4630)
  %t4631 = getelementptr ptr, ptr %t4626, i32 1
  store ptr %t4630, ptr %t4631
  %t4632 = getelementptr ptr, ptr %t11, i32 2
  %t4633 = load ptr, ptr %t4632
  call void @__inc_ref(ptr %t4633)
  %t4634 = getelementptr ptr, ptr %t4, i32 1
  %t4635 = load ptr, ptr %t4634
  call void @__free_recursive(ptr %t4635)
  %t4637 = inttoptr i64 14 to ptr
  %t4638 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t4637, ptr %t4638
  %t4636 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t4633, ptr %t4636
  %t4639 = getelementptr ptr, ptr %t4626, i32 2
  store ptr %t4, ptr %t4639
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4626, ptr %t3
  br label %tco.loop.0
tco.case.arm.260.4640:
  %t4641 = call ptr @__alloc(i64 24, i32 2)
  %t4642 = inttoptr i64 280 to ptr
  %t4643 = getelementptr ptr, ptr %t4641, i32 0
  store ptr %t4642, ptr %t4643
  %t4644 = call ptr @__alloc(i64 40, i32 4)
  %t4645 = inttoptr i64 106 to ptr
  %t4646 = getelementptr ptr, ptr %t4644, i32 0
  store ptr %t4645, ptr %t4646
  %t4647 = getelementptr ptr, ptr %t11, i32 4
  %t4648 = load ptr, ptr %t4647
  call void @__inc_ref(ptr %t4648)
  %t4649 = getelementptr ptr, ptr %t4644, i32 1
  store ptr %t4648, ptr %t4649
  %t4650 = getelementptr ptr, ptr %t11, i32 2
  %t4651 = load ptr, ptr %t4650
  call void @__inc_ref(ptr %t4651)
  %t4652 = getelementptr ptr, ptr %t4644, i32 2
  store ptr %t4651, ptr %t4652
  %t4653 = getelementptr ptr, ptr %t11, i32 5
  %t4654 = load ptr, ptr %t4653
  call void @__inc_ref(ptr %t4654)
  %t4655 = getelementptr ptr, ptr %t4644, i32 3
  store ptr %t4654, ptr %t4655
  %t4656 = getelementptr ptr, ptr %t11, i32 3
  %t4657 = load ptr, ptr %t4656
  call void @__inc_ref(ptr %t4657)
  %t4658 = getelementptr ptr, ptr %t4644, i32 4
  store ptr %t4657, ptr %t4658
  %t4659 = getelementptr ptr, ptr %t4641, i32 1
  store ptr %t4644, ptr %t4659
  %t4660 = getelementptr ptr, ptr %t11, i32 1
  %t4661 = load ptr, ptr %t4660
  call void @__inc_ref(ptr %t4661)
  %t4662 = getelementptr ptr, ptr %t4, i32 1
  %t4663 = load ptr, ptr %t4662
  call void @__free_recursive(ptr %t4663)
  %t4665 = inttoptr i64 261 to ptr
  %t4666 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t4665, ptr %t4666
  %t4664 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t4661, ptr %t4664
  %t4667 = getelementptr ptr, ptr %t4641, i32 2
  store ptr %t4, ptr %t4667
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4641, ptr %t3
  br label %tco.loop.0
tco.case.arm.262.4668:
  %t4669 = getelementptr ptr, ptr %t11, i32 1
  %t4670 = load ptr, ptr %t4669
  call void @__inc_ref(ptr %t4670)
  %t4671 = call ptr @__alloc(i64 16, i32 1)
  %t4672 = inttoptr i64 4 to ptr
  %t4673 = getelementptr ptr, ptr %t4671, i32 0
  store ptr %t4672, ptr %t4673
  %t4674 = call ptr @__alloc(i64 16, i32 1)
  %t4675 = inttoptr i64 39 to ptr
  %t4676 = getelementptr ptr, ptr %t4674, i32 0
  store ptr %t4675, ptr %t4676
  call void @__inc_ref(ptr %t13)
  %t4677 = getelementptr ptr, ptr %t4674, i32 1
  store ptr %t13, ptr %t4677
  %t4678 = getelementptr ptr, ptr %t4671, i32 1
  store ptr %t4674, ptr %t4678
  %t4679 = getelementptr ptr, ptr %t4, i32 1
  %t4680 = load ptr, ptr %t4679
  call void @__free_recursive(ptr %t4680)
  %t4681 = getelementptr ptr, ptr %t4, i32 2
  %t4682 = load ptr, ptr %t4681
  call void @__free_recursive(ptr %t4682)
  %t4685 = inttoptr i64 279 to ptr
  %t4686 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t4685, ptr %t4686
  %t4683 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t4670, ptr %t4683
  %t4684 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t4671, ptr %t4684
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.263.4687:
  %t4688 = getelementptr ptr, ptr %t11, i32 1
  %t4689 = load ptr, ptr %t4688
  call void @__inc_ref(ptr %t4689)
  %t4690 = getelementptr ptr, ptr %t13, i32 0
  %t4691 = load ptr, ptr %t4690
  %t4692 = ptrtoint ptr %t4691 to i64
  switch i64 %t4692, label %case.default.4693 [ i64 3, label %case.arm.3.4695 i64 4, label %case.arm.4.4697 ]
case.arm.3.4695:
  call void @__inc_ref(ptr %t13)
  br label %case.end.3.4696
case.end.3.4696:
  br label %case.join.4694
case.arm.4.4697:
  %t4699 = call ptr @__alloc(i64 16, i32 1)
  %t4700 = inttoptr i64 4 to ptr
  %t4701 = getelementptr ptr, ptr %t4699, i32 0
  store ptr %t4700, ptr %t4701
  %t4702 = call ptr @__alloc(i64 16, i32 1)
  %t4703 = inttoptr i64 40 to ptr
  %t4704 = getelementptr ptr, ptr %t4702, i32 0
  store ptr %t4703, ptr %t4704
  %t4705 = getelementptr ptr, ptr %t13, i32 1
  %t4706 = load ptr, ptr %t4705
  call void @__inc_ref(ptr %t4706)
  %t4707 = getelementptr ptr, ptr %t4702, i32 1
  store ptr %t4706, ptr %t4707
  %t4708 = getelementptr ptr, ptr %t4699, i32 1
  store ptr %t4702, ptr %t4708
  br label %case.end.4.4698
case.end.4.4698:
  br label %case.join.4694
case.default.4693:
  unreachable
case.join.4694:
  %t4709 = phi ptr [ %t13, %case.end.3.4696 ], [ %t4699, %case.end.4.4698 ]
  %t4710 = getelementptr ptr, ptr %t4709, i32 0
  %t4711 = load ptr, ptr %t4710
  %t4712 = ptrtoint ptr %t4711 to i64
  switch i64 %t4712, label %case.default.4713 [ i64 3, label %case.arm.3.4715 i64 4, label %case.arm.4.4727 ]
case.arm.3.4715:
  %t4717 = call ptr @__alloc(i64 16, i32 1)
  %t4718 = inttoptr i64 3 to ptr
  %t4719 = getelementptr ptr, ptr %t4717, i32 0
  store ptr %t4718, ptr %t4719
  %t4720 = call ptr @__alloc(i64 16, i32 1)
  %t4721 = inttoptr i64 589989748 to ptr
  %t4722 = getelementptr ptr, ptr %t4720, i32 0
  store ptr %t4721, ptr %t4722
  %t4723 = getelementptr ptr, ptr %t4709, i32 1
  %t4724 = load ptr, ptr %t4723
  call void @__inc_ref(ptr %t4724)
  %t4725 = getelementptr ptr, ptr %t4720, i32 1
  store ptr %t4724, ptr %t4725
  %t4726 = getelementptr ptr, ptr %t4717, i32 1
  store ptr %t4720, ptr %t4726
  br label %case.end.3.4716
case.end.3.4716:
  br label %case.join.4714
case.arm.4.4727:
  call void @__inc_ref(ptr %t4709)
  br label %case.end.4.4728
case.end.4.4728:
  br label %case.join.4714
case.default.4713:
  unreachable
case.join.4714:
  %t4729 = phi ptr [ %t4717, %case.end.3.4716 ], [ %t4709, %case.end.4.4728 ]
  call void @__free_recursive(ptr %t4709)
  %t4730 = getelementptr ptr, ptr %t4, i32 1
  %t4731 = load ptr, ptr %t4730
  call void @__free_recursive(ptr %t4731)
  %t4732 = getelementptr ptr, ptr %t4, i32 2
  %t4733 = load ptr, ptr %t4732
  call void @__free_recursive(ptr %t4733)
  %t4736 = inttoptr i64 279 to ptr
  %t4737 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t4736, ptr %t4737
  %t4734 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t4689, ptr %t4734
  %t4735 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t4729, ptr %t4735
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.264.4738:
  %t4739 = getelementptr ptr, ptr %t11, i32 1
  %t4740 = load ptr, ptr %t4739
  call void @__inc_ref(ptr %t4740)
  %t4741 = getelementptr ptr, ptr %t13, i32 0
  %t4742 = load ptr, ptr %t4741
  %t4743 = ptrtoint ptr %t4742 to i64
  switch i64 %t4743, label %tco.case.default.4744 [ i64 11, label %tco.case.arm.11.4745 i64 12, label %tco.case.arm.12.4765 ]
tco.case.arm.11.4745:
  %t4746 = call ptr @__alloc(i64 16, i32 1)
  %t4747 = inttoptr i64 3 to ptr
  %t4748 = getelementptr ptr, ptr %t4746, i32 0
  store ptr %t4747, ptr %t4748
  %t4749 = call ptr @__alloc(i64 16, i32 1)
  %t4750 = inttoptr i64 3150992243 to ptr
  %t4751 = getelementptr ptr, ptr %t4749, i32 0
  store ptr %t4750, ptr %t4751
  %t4752 = call ptr @__alloc(i64 8, i32 0)
  %t4753 = inttoptr i64 37 to ptr
  %t4754 = getelementptr ptr, ptr %t4752, i32 0
  store ptr %t4753, ptr %t4754
  %t4755 = getelementptr ptr, ptr %t4749, i32 1
  store ptr %t4752, ptr %t4755
  %t4756 = getelementptr ptr, ptr %t4746, i32 1
  store ptr %t4749, ptr %t4756
  %t4757 = getelementptr ptr, ptr %t4, i32 1
  %t4758 = load ptr, ptr %t4757
  call void @__free_recursive(ptr %t4758)
  %t4759 = getelementptr ptr, ptr %t4, i32 2
  %t4760 = load ptr, ptr %t4759
  call void @__free_recursive(ptr %t4760)
  %t4763 = inttoptr i64 279 to ptr
  %t4764 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t4763, ptr %t4764
  call void @__inc_ref(ptr %t4740)
  %t4761 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t4740, ptr %t4761
  %t4762 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t4746, ptr %t4762
  call void @__free_recursive(ptr %t4740)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.12.4765:
  %t4766 = call ptr @__alloc(i64 16, i32 1)
  %t4767 = inttoptr i64 4 to ptr
  %t4768 = getelementptr ptr, ptr %t4766, i32 0
  store ptr %t4767, ptr %t4768
  %t4769 = call ptr @__alloc(i64 16, i32 1)
  %t4770 = inttoptr i64 39 to ptr
  %t4771 = getelementptr ptr, ptr %t4769, i32 0
  store ptr %t4770, ptr %t4771
  %t4772 = getelementptr ptr, ptr %t13, i32 1
  %t4773 = load ptr, ptr %t4772
  call void @__inc_ref(ptr %t4773)
  %t4774 = getelementptr ptr, ptr %t4769, i32 1
  store ptr %t4773, ptr %t4774
  %t4775 = getelementptr ptr, ptr %t4766, i32 1
  store ptr %t4769, ptr %t4775
  %t4776 = getelementptr ptr, ptr %t4, i32 1
  %t4777 = load ptr, ptr %t4776
  call void @__free_recursive(ptr %t4777)
  %t4778 = getelementptr ptr, ptr %t4, i32 2
  %t4779 = load ptr, ptr %t4778
  call void @__free_recursive(ptr %t4779)
  %t4782 = inttoptr i64 279 to ptr
  %t4783 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t4782, ptr %t4783
  call void @__inc_ref(ptr %t4740)
  %t4780 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t4740, ptr %t4780
  %t4781 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t4766, ptr %t4781
  call void @__free_recursive(ptr %t4740)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.4744:
  unreachable
tco.case.arm.265.4784:
  %t4785 = getelementptr ptr, ptr %t11, i32 1
  %t4786 = load ptr, ptr %t4785
  call void @__inc_ref(ptr %t4786)
  %t4787 = getelementptr ptr, ptr %t13, i32 0
  %t4788 = load ptr, ptr %t4787
  %t4789 = ptrtoint ptr %t4788 to i64
  switch i64 %t4789, label %tco.case.default.4790 [ i64 11, label %tco.case.arm.11.4791 i64 12, label %tco.case.arm.12.4811 ]
tco.case.arm.11.4791:
  %t4792 = call ptr @__alloc(i64 16, i32 1)
  %t4793 = inttoptr i64 3 to ptr
  %t4794 = getelementptr ptr, ptr %t4792, i32 0
  store ptr %t4793, ptr %t4794
  %t4795 = call ptr @__alloc(i64 16, i32 1)
  %t4796 = inttoptr i64 3150992243 to ptr
  %t4797 = getelementptr ptr, ptr %t4795, i32 0
  store ptr %t4796, ptr %t4797
  %t4798 = call ptr @__alloc(i64 8, i32 0)
  %t4799 = inttoptr i64 37 to ptr
  %t4800 = getelementptr ptr, ptr %t4798, i32 0
  store ptr %t4799, ptr %t4800
  %t4801 = getelementptr ptr, ptr %t4795, i32 1
  store ptr %t4798, ptr %t4801
  %t4802 = getelementptr ptr, ptr %t4792, i32 1
  store ptr %t4795, ptr %t4802
  %t4803 = getelementptr ptr, ptr %t4, i32 1
  %t4804 = load ptr, ptr %t4803
  call void @__free_recursive(ptr %t4804)
  %t4805 = getelementptr ptr, ptr %t4, i32 2
  %t4806 = load ptr, ptr %t4805
  call void @__free_recursive(ptr %t4806)
  %t4809 = inttoptr i64 279 to ptr
  %t4810 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t4809, ptr %t4810
  call void @__inc_ref(ptr %t4786)
  %t4807 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t4786, ptr %t4807
  %t4808 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t4792, ptr %t4808
  call void @__free_recursive(ptr %t4786)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.12.4811:
  %t4812 = call ptr @__alloc(i64 16, i32 1)
  %t4813 = inttoptr i64 4 to ptr
  %t4814 = getelementptr ptr, ptr %t4812, i32 0
  store ptr %t4813, ptr %t4814
  %t4815 = call ptr @__alloc(i64 16, i32 1)
  %t4816 = inttoptr i64 39 to ptr
  %t4817 = getelementptr ptr, ptr %t4815, i32 0
  store ptr %t4816, ptr %t4817
  %t4818 = getelementptr ptr, ptr %t13, i32 1
  %t4819 = load ptr, ptr %t4818
  call void @__inc_ref(ptr %t4819)
  %t4820 = getelementptr ptr, ptr %t4815, i32 1
  store ptr %t4819, ptr %t4820
  %t4821 = getelementptr ptr, ptr %t4812, i32 1
  store ptr %t4815, ptr %t4821
  %t4822 = getelementptr ptr, ptr %t4, i32 1
  %t4823 = load ptr, ptr %t4822
  call void @__free_recursive(ptr %t4823)
  %t4824 = getelementptr ptr, ptr %t4, i32 2
  %t4825 = load ptr, ptr %t4824
  call void @__free_recursive(ptr %t4825)
  %t4828 = inttoptr i64 279 to ptr
  %t4829 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t4828, ptr %t4829
  call void @__inc_ref(ptr %t4786)
  %t4826 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t4786, ptr %t4826
  %t4827 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t4812, ptr %t4827
  call void @__free_recursive(ptr %t4786)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.4790:
  unreachable
tco.case.arm.266.4830:
  %t4831 = getelementptr ptr, ptr %t11, i32 1
  %t4832 = load ptr, ptr %t4831
  call void @__inc_ref(ptr %t4832)
  %t4833 = getelementptr ptr, ptr %t13, i32 0
  %t4834 = load ptr, ptr %t4833
  %t4835 = ptrtoint ptr %t4834 to i64
  switch i64 %t4835, label %tco.case.default.4836 [ i64 13, label %tco.case.arm.13.4837 i64 14, label %tco.case.arm.14.4850 ]
tco.case.arm.13.4837:
  %t4838 = call ptr @__alloc(i64 16, i32 1)
  %t4839 = inttoptr i64 4 to ptr
  %t4840 = getelementptr ptr, ptr %t4838, i32 0
  store ptr %t4839, ptr %t4840
  %t4841 = getelementptr ptr, ptr %t4838, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.8, i64 12), ptr %t4841
  %t4842 = getelementptr ptr, ptr %t4, i32 1
  %t4843 = load ptr, ptr %t4842
  call void @__free_recursive(ptr %t4843)
  %t4844 = getelementptr ptr, ptr %t4, i32 2
  %t4845 = load ptr, ptr %t4844
  call void @__free_recursive(ptr %t4845)
  %t4848 = inttoptr i64 279 to ptr
  %t4849 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t4848, ptr %t4849
  call void @__inc_ref(ptr %t4832)
  %t4846 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t4832, ptr %t4846
  %t4847 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t4838, ptr %t4847
  call void @__free_recursive(ptr %t4832)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.14.4850:
  %t4851 = getelementptr ptr, ptr %t13, i32 1
  %t4852 = load ptr, ptr %t4851
  call void @__inc_ref(ptr %t4852)
  %t4853 = getelementptr ptr, ptr %t13, i32 2
  %t4854 = load ptr, ptr %t4853
  call void @__inc_ref(ptr %t4854)
  %t4855 = call ptr @v_joinOnto(ptr %t4852, ptr %t4854)
  %t4856 = getelementptr ptr, ptr %t4, i32 1
  %t4857 = load ptr, ptr %t4856
  call void @__free_recursive(ptr %t4857)
  %t4858 = getelementptr ptr, ptr %t4, i32 2
  %t4859 = load ptr, ptr %t4858
  call void @__free_recursive(ptr %t4859)
  %t4862 = inttoptr i64 279 to ptr
  %t4863 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t4862, ptr %t4863
  call void @__inc_ref(ptr %t4832)
  %t4860 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t4832, ptr %t4860
  %t4861 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t4855, ptr %t4861
  call void @__free_recursive(ptr %t4832)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.4836:
  unreachable
tco.case.arm.267.4864:
  %t4865 = getelementptr ptr, ptr %t11, i32 1
  %t4866 = load ptr, ptr %t4865
  call void @__inc_ref(ptr %t4866)
  %t4867 = getelementptr ptr, ptr %t11, i32 3
  %t4868 = load ptr, ptr %t4867
  call void @__inc_ref(ptr %t4868)
  %t4869 = getelementptr ptr, ptr %t11, i32 4
  %t4870 = load ptr, ptr %t4869
  call void @__inc_ref(ptr %t4870)
  %t4871 = getelementptr ptr, ptr %t13, i32 0
  %t4872 = load ptr, ptr %t4871
  %t4873 = ptrtoint ptr %t4872 to i64
  switch i64 %t4873, label %tco.case.default.4874 [ i64 3, label %tco.case.arm.3.4875 i64 4, label %tco.case.arm.4.4881 ]
tco.case.arm.3.4875:
  %t4876 = getelementptr ptr, ptr %t4, i32 1
  %t4877 = load ptr, ptr %t4876
  call void @__free_recursive(ptr %t4877)
  %t4879 = inttoptr i64 279 to ptr
  %t4880 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t4879, ptr %t4880
  call void @__inc_ref(ptr %t4866)
  %t4878 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t4866, ptr %t4878
  call void @__free_recursive(ptr %t4870)
  call void @__free_recursive(ptr %t4868)
  call void @__free_recursive(ptr %t4866)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.4.4881:
  %t4882 = getelementptr ptr, ptr %t13, i32 1
  %t4883 = load ptr, ptr %t4882
  call void @__inc_ref(ptr %t4883)
  %t4884 = getelementptr ptr, ptr %t4883, i32 0
  %t4885 = load ptr, ptr %t4884
  %t4886 = ptrtoint ptr %t4885 to i64
  switch i64 %t4886, label %tco.case.default.4887 [ i64 39, label %tco.case.arm.39.4888 i64 40, label %tco.case.arm.40.4905 ]
tco.case.arm.39.4888:
  %t4889 = call ptr @__alloc(i64 32, i32 3)
  %t4890 = inttoptr i64 113 to ptr
  %t4891 = getelementptr ptr, ptr %t4889, i32 0
  store ptr %t4890, ptr %t4891
  %t4892 = getelementptr ptr, ptr %t4883, i32 1
  %t4893 = load ptr, ptr %t4892
  call void @__inc_ref(ptr %t4893)
  %t4894 = getelementptr ptr, ptr %t4889, i32 1
  store ptr %t4893, ptr %t4894
  call void @__inc_ref(ptr %t4870)
  %t4895 = getelementptr ptr, ptr %t4889, i32 2
  store ptr %t4870, ptr %t4895
  call void @__inc_ref(ptr %t4868)
  %t4896 = getelementptr ptr, ptr %t4889, i32 3
  store ptr %t4868, ptr %t4896
  %t4897 = getelementptr ptr, ptr %t4, i32 1
  %t4898 = load ptr, ptr %t4897
  call void @__free_recursive(ptr %t4898)
  %t4899 = getelementptr ptr, ptr %t4, i32 2
  %t4900 = load ptr, ptr %t4899
  call void @__free_recursive(ptr %t4900)
  %t4903 = inttoptr i64 280 to ptr
  %t4904 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t4903, ptr %t4904
  %t4901 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t4889, ptr %t4901
  call void @__inc_ref(ptr %t4866)
  %t4902 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t4866, ptr %t4902
  call void @__free_recursive(ptr %t4883)
  call void @__free_recursive(ptr %t4870)
  call void @__free_recursive(ptr %t4868)
  call void @__free_recursive(ptr %t4866)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.40.4905:
  %t4906 = getelementptr ptr, ptr %t4883, i32 1
  %t4907 = load ptr, ptr %t4906
  call void @__inc_ref(ptr %t4907)
  call void @__inc_ref(ptr %t4868)
  %t4909 = call ptr @__eqString(ptr %t4868, ptr getelementptr inbounds (i8, ptr @.str.8, i64 12))
  %t4910 = getelementptr ptr, ptr %t4909, i32 0
  %t4911 = load ptr, ptr %t4910
  %t4912 = ptrtoint ptr %t4911 to i64
  switch i64 %t4912, label %tco.case.default.4913 [ i64 1, label %tco.case.arm.1.4914 i64 2, label %tco.case.arm.2.4928 ]
tco.case.arm.1.4914:
  call void @__free_recursive(ptr %t4909)
  %t4915 = call ptr @__alloc(i64 24, i32 2)
  %t4916 = inttoptr i64 280 to ptr
  %t4917 = getelementptr ptr, ptr %t4915, i32 0
  store ptr %t4916, ptr %t4917
  %t4918 = call ptr @__alloc(i64 32, i32 3)
  %t4919 = inttoptr i64 113 to ptr
  %t4920 = getelementptr ptr, ptr %t4918, i32 0
  store ptr %t4919, ptr %t4920
  %t4921 = getelementptr ptr, ptr %t11, i32 2
  %t4922 = load ptr, ptr %t4921
  call void @__inc_ref(ptr %t4922)
  %t4923 = getelementptr ptr, ptr %t4918, i32 1
  store ptr %t4922, ptr %t4923
  call void @__inc_ref(ptr %t4870)
  %t4924 = getelementptr ptr, ptr %t4918, i32 2
  store ptr %t4870, ptr %t4924
  call void @__inc_ref(ptr %t4907)
  %t4925 = getelementptr ptr, ptr %t4918, i32 3
  store ptr %t4907, ptr %t4925
  %t4926 = getelementptr ptr, ptr %t4915, i32 1
  store ptr %t4918, ptr %t4926
  call void @__inc_ref(ptr %t4866)
  %t4927 = getelementptr ptr, ptr %t4915, i32 2
  store ptr %t4866, ptr %t4927
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t4907)
  call void @__free_recursive(ptr %t4883)
  call void @__free_recursive(ptr %t4870)
  call void @__free_recursive(ptr %t4868)
  call void @__free_recursive(ptr %t4866)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4915, ptr %t3
  br label %tco.loop.0
tco.case.arm.2.4928:
  call void @__free_recursive(ptr %t4909)
  call void @__inc_ref(ptr %t4868)
  %t4929 = call ptr @__concat(ptr %t4868, ptr getelementptr inbounds (i8, ptr @.str.9, i64 12))
  %t4930 = getelementptr ptr, ptr %t4929, i32 0
  %t4931 = load ptr, ptr %t4930
  %t4932 = ptrtoint ptr %t4931 to i64
  switch i64 %t4932, label %case.default.4933 [ i64 3, label %case.arm.3.4935 i64 4, label %case.arm.4.4943 ]
case.arm.3.4935:
  %t4937 = getelementptr ptr, ptr %t4929, i32 1
  %t4938 = load ptr, ptr %t4937
  call void @__inc_ref(ptr %t4938)
  %t4939 = call ptr @__alloc(i64 16, i32 1)
  %t4940 = inttoptr i64 3 to ptr
  %t4941 = getelementptr ptr, ptr %t4939, i32 0
  store ptr %t4940, ptr %t4941
  call void @__inc_ref(ptr %t4938)
  %t4942 = getelementptr ptr, ptr %t4939, i32 1
  store ptr %t4938, ptr %t4942
  call void @__free_recursive(ptr %t4938)
  br label %case.end.3.4936
case.end.3.4936:
  br label %case.join.4934
case.arm.4.4943:
  %t4945 = getelementptr ptr, ptr %t4929, i32 1
  %t4946 = load ptr, ptr %t4945
  call void @__inc_ref(ptr %t4946)
  call void @__inc_ref(ptr %t4946)
  call void @__inc_ref(ptr %t4907)
  %t4947 = call ptr @__concat(ptr %t4946, ptr %t4907)
  call void @__free_recursive(ptr %t4946)
  br label %case.end.4.4944
case.end.4.4944:
  br label %case.join.4934
case.default.4933:
  unreachable
case.join.4934:
  %t4948 = phi ptr [ %t4939, %case.end.3.4936 ], [ %t4947, %case.end.4.4944 ]
  call void @__free_recursive(ptr %t4929)
  store ptr %t4948, ptr %v_$inl181$scrut.jslot
  br label %join.4908
tco.case.default.4913:
  unreachable
join.4908:
  %t4949 = load ptr, ptr %v_$inl181$scrut.jslot
  %t4950 = getelementptr ptr, ptr %t4949, i32 0
  %t4951 = load ptr, ptr %t4950
  %t4952 = ptrtoint ptr %t4951 to i64
  switch i64 %t4952, label %tco.case.default.4953 [ i64 3, label %tco.case.arm.3.4954 i64 4, label %tco.case.arm.4.4970 ]
tco.case.arm.3.4954:
  %t4955 = call ptr @__alloc(i64 24, i32 2)
  %t4956 = inttoptr i64 279 to ptr
  %t4957 = getelementptr ptr, ptr %t4955, i32 0
  store ptr %t4956, ptr %t4957
  call void @__inc_ref(ptr %t4866)
  %t4958 = getelementptr ptr, ptr %t4955, i32 1
  store ptr %t4866, ptr %t4958
  %t4959 = call ptr @__alloc(i64 16, i32 1)
  %t4960 = inttoptr i64 3 to ptr
  %t4961 = getelementptr ptr, ptr %t4959, i32 0
  store ptr %t4960, ptr %t4961
  %t4962 = call ptr @__alloc(i64 16, i32 1)
  %t4963 = inttoptr i64 589989748 to ptr
  %t4964 = getelementptr ptr, ptr %t4962, i32 0
  store ptr %t4963, ptr %t4964
  %t4965 = getelementptr ptr, ptr %t4949, i32 1
  %t4966 = load ptr, ptr %t4965
  call void @__inc_ref(ptr %t4966)
  %t4967 = getelementptr ptr, ptr %t4962, i32 1
  store ptr %t4966, ptr %t4967
  %t4968 = getelementptr ptr, ptr %t4959, i32 1
  store ptr %t4962, ptr %t4968
  %t4969 = getelementptr ptr, ptr %t4955, i32 2
  store ptr %t4959, ptr %t4969
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t4949)
  call void @__free_recursive(ptr %t4907)
  call void @__free_recursive(ptr %t4883)
  call void @__free_recursive(ptr %t4870)
  call void @__free_recursive(ptr %t4868)
  call void @__free_recursive(ptr %t4866)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4955, ptr %t3
  br label %tco.loop.0
tco.case.arm.4.4970:
  %t4971 = call ptr @__alloc(i64 24, i32 2)
  %t4972 = inttoptr i64 280 to ptr
  %t4973 = getelementptr ptr, ptr %t4971, i32 0
  store ptr %t4972, ptr %t4973
  %t4974 = call ptr @__alloc(i64 32, i32 3)
  %t4975 = inttoptr i64 113 to ptr
  %t4976 = getelementptr ptr, ptr %t4974, i32 0
  store ptr %t4975, ptr %t4976
  %t4977 = getelementptr ptr, ptr %t11, i32 2
  %t4978 = load ptr, ptr %t4977
  call void @__inc_ref(ptr %t4978)
  %t4979 = getelementptr ptr, ptr %t4974, i32 1
  store ptr %t4978, ptr %t4979
  call void @__inc_ref(ptr %t4870)
  %t4980 = getelementptr ptr, ptr %t4974, i32 2
  store ptr %t4870, ptr %t4980
  %t4981 = getelementptr ptr, ptr %t4949, i32 1
  %t4982 = load ptr, ptr %t4981
  call void @__inc_ref(ptr %t4982)
  %t4983 = getelementptr ptr, ptr %t4974, i32 3
  store ptr %t4982, ptr %t4983
  %t4984 = getelementptr ptr, ptr %t4971, i32 1
  store ptr %t4974, ptr %t4984
  call void @__inc_ref(ptr %t4866)
  %t4985 = getelementptr ptr, ptr %t4971, i32 2
  store ptr %t4866, ptr %t4985
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t4949)
  call void @__free_recursive(ptr %t4907)
  call void @__free_recursive(ptr %t4883)
  call void @__free_recursive(ptr %t4870)
  call void @__free_recursive(ptr %t4868)
  call void @__free_recursive(ptr %t4866)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4971, ptr %t3
  br label %tco.loop.0
tco.case.default.4953:
  unreachable
tco.case.default.4887:
  unreachable
tco.case.default.4874:
  unreachable
tco.case.arm.269.4986:
  %t4987 = call ptr @__alloc(i64 24, i32 2)
  %t4988 = inttoptr i64 280 to ptr
  %t4989 = getelementptr ptr, ptr %t4987, i32 0
  store ptr %t4988, ptr %t4989
  %t4990 = call ptr @__alloc(i64 40, i32 4)
  %t4991 = inttoptr i64 92 to ptr
  %t4992 = getelementptr ptr, ptr %t4990, i32 0
  store ptr %t4991, ptr %t4992
  %t4993 = getelementptr ptr, ptr %t11, i32 3
  %t4994 = load ptr, ptr %t4993
  call void @__inc_ref(ptr %t4994)
  %t4995 = getelementptr ptr, ptr %t4990, i32 1
  store ptr %t4994, ptr %t4995
  %t4996 = getelementptr ptr, ptr %t11, i32 4
  %t4997 = load ptr, ptr %t4996
  call void @__inc_ref(ptr %t4997)
  %t4998 = getelementptr ptr, ptr %t4990, i32 2
  store ptr %t4997, ptr %t4998
  call void @__inc_ref(ptr %t13)
  %t4999 = getelementptr ptr, ptr %t4990, i32 3
  store ptr %t13, ptr %t4999
  %t5000 = getelementptr ptr, ptr %t11, i32 2
  %t5001 = load ptr, ptr %t5000
  call void @__inc_ref(ptr %t5001)
  %t5002 = getelementptr ptr, ptr %t11, i32 5
  %t5003 = load ptr, ptr %t5002
  call void @__inc_ref(ptr %t5003)
  %t5004 = getelementptr ptr, ptr %t4, i32 1
  %t5005 = load ptr, ptr %t5004
  call void @__free_recursive(ptr %t5005)
  %t5006 = getelementptr ptr, ptr %t4, i32 2
  %t5007 = load ptr, ptr %t5006
  call void @__free_recursive(ptr %t5007)
  %t5010 = inttoptr i64 25 to ptr
  %t5011 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5010, ptr %t5011
  %t5008 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5001, ptr %t5008
  %t5009 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t5003, ptr %t5009
  %t5012 = getelementptr ptr, ptr %t4990, i32 4
  store ptr %t4, ptr %t5012
  %t5013 = getelementptr ptr, ptr %t4987, i32 1
  store ptr %t4990, ptr %t5013
  %t5014 = getelementptr ptr, ptr %t11, i32 1
  %t5015 = load ptr, ptr %t5014
  call void @__inc_ref(ptr %t5015)
  %t5016 = getelementptr ptr, ptr %t4987, i32 2
  store ptr %t5015, ptr %t5016
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4987, ptr %t3
  br label %tco.loop.0
tco.case.arm.268.5017:
  %t5018 = getelementptr ptr, ptr %t11, i32 3
  %t5019 = load ptr, ptr %t5018
  call void @__inc_ref(ptr %t5019)
  %t5020 = call ptr @__alloc(i64 32, i32 3)
  %t5021 = inttoptr i64 114 to ptr
  %t5022 = getelementptr ptr, ptr %t5020, i32 0
  store ptr %t5021, ptr %t5022
  %t5023 = call ptr @__alloc(i64 32, i32 3)
  %t5024 = inttoptr i64 33 to ptr
  %t5025 = getelementptr ptr, ptr %t5023, i32 0
  store ptr %t5024, ptr %t5025
  %t5026 = call ptr @__alloc(i64 8, i32 0)
  %t5027 = inttoptr i64 49 to ptr
  %t5028 = getelementptr ptr, ptr %t5026, i32 0
  store ptr %t5027, ptr %t5028
  %t5029 = getelementptr ptr, ptr %t5023, i32 1
  store ptr %t5026, ptr %t5029
  %t5030 = getelementptr ptr, ptr %t5019, i32 2
  %t5031 = load ptr, ptr %t5030
  call void @__inc_ref(ptr %t5031)
  %t5032 = getelementptr ptr, ptr %t5023, i32 2
  store ptr %t5031, ptr %t5032
  %t5033 = getelementptr ptr, ptr %t5019, i32 3
  %t5034 = load ptr, ptr %t5033
  call void @__inc_ref(ptr %t5034)
  %t5035 = getelementptr ptr, ptr %t5023, i32 3
  store ptr %t5034, ptr %t5035
  %t5036 = getelementptr ptr, ptr %t5020, i32 1
  store ptr %t5023, ptr %t5036
  %t5037 = getelementptr ptr, ptr %t11, i32 4
  %t5038 = load ptr, ptr %t5037
  call void @__inc_ref(ptr %t5038)
  %t5039 = getelementptr ptr, ptr %t5020, i32 2
  store ptr %t5038, ptr %t5039
  call void @__inc_ref(ptr %t13)
  %t5040 = getelementptr ptr, ptr %t5020, i32 3
  store ptr %t13, ptr %t5040
  %t5041 = call ptr @__alloc(i64 48, i32 5)
  %t5042 = inttoptr i64 269 to ptr
  %t5043 = getelementptr ptr, ptr %t5041, i32 0
  store ptr %t5042, ptr %t5043
  %t5044 = getelementptr ptr, ptr %t11, i32 1
  %t5045 = load ptr, ptr %t5044
  call void @__inc_ref(ptr %t5045)
  %t5046 = getelementptr ptr, ptr %t5041, i32 1
  store ptr %t5045, ptr %t5046
  %t5047 = getelementptr ptr, ptr %t11, i32 2
  %t5048 = load ptr, ptr %t5047
  call void @__inc_ref(ptr %t5048)
  %t5049 = getelementptr ptr, ptr %t5041, i32 2
  store ptr %t5048, ptr %t5049
  call void @__inc_ref(ptr %t5019)
  %t5050 = getelementptr ptr, ptr %t5041, i32 3
  store ptr %t5019, ptr %t5050
  %t5051 = getelementptr ptr, ptr %t11, i32 5
  %t5052 = load ptr, ptr %t5051
  call void @__inc_ref(ptr %t5052)
  %t5053 = getelementptr ptr, ptr %t5041, i32 4
  store ptr %t5052, ptr %t5053
  %t5054 = getelementptr ptr, ptr %t11, i32 6
  %t5055 = load ptr, ptr %t5054
  call void @__inc_ref(ptr %t5055)
  %t5056 = getelementptr ptr, ptr %t5041, i32 5
  store ptr %t5055, ptr %t5056
  %t5057 = getelementptr ptr, ptr %t4, i32 1
  %t5058 = load ptr, ptr %t5057
  call void @__free_recursive(ptr %t5058)
  %t5059 = getelementptr ptr, ptr %t4, i32 2
  %t5060 = load ptr, ptr %t5059
  call void @__free_recursive(ptr %t5060)
  %t5063 = inttoptr i64 280 to ptr
  %t5064 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5063, ptr %t5064
  %t5061 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5020, ptr %t5061
  %t5062 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t5041, ptr %t5062
  call void @__free_recursive(ptr %t5019)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.270.5065:
  %t5066 = call ptr @__alloc(i64 32, i32 3)
  %t5067 = inttoptr i64 115 to ptr
  %t5068 = getelementptr ptr, ptr %t5066, i32 0
  store ptr %t5067, ptr %t5068
  %t5069 = getelementptr ptr, ptr %t11, i32 2
  %t5070 = load ptr, ptr %t5069
  call void @__inc_ref(ptr %t5070)
  %t5071 = getelementptr ptr, ptr %t5066, i32 1
  store ptr %t5070, ptr %t5071
  call void @__inc_ref(ptr %t13)
  %t5072 = getelementptr ptr, ptr %t5066, i32 2
  store ptr %t13, ptr %t5072
  %t5073 = getelementptr ptr, ptr %t11, i32 3
  %t5074 = load ptr, ptr %t5073
  call void @__inc_ref(ptr %t5074)
  %t5075 = getelementptr ptr, ptr %t5066, i32 3
  store ptr %t5074, ptr %t5075
  %t5076 = getelementptr ptr, ptr %t11, i32 1
  %t5077 = load ptr, ptr %t5076
  call void @__inc_ref(ptr %t5077)
  %t5078 = getelementptr ptr, ptr %t4, i32 1
  %t5079 = load ptr, ptr %t5078
  call void @__free_recursive(ptr %t5079)
  %t5080 = getelementptr ptr, ptr %t4, i32 2
  %t5081 = load ptr, ptr %t5080
  call void @__free_recursive(ptr %t5081)
  %t5084 = inttoptr i64 280 to ptr
  %t5085 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5084, ptr %t5085
  %t5082 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5066, ptr %t5082
  %t5083 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t5077, ptr %t5083
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.271.5086:
  %t5087 = call ptr @__alloc(i64 24, i32 2)
  %t5088 = inttoptr i64 279 to ptr
  %t5089 = getelementptr ptr, ptr %t5087, i32 0
  store ptr %t5088, ptr %t5089
  %t5090 = getelementptr ptr, ptr %t11, i32 1
  %t5091 = load ptr, ptr %t5090
  call void @__inc_ref(ptr %t5091)
  %t5092 = getelementptr ptr, ptr %t5087, i32 1
  store ptr %t5091, ptr %t5092
  %t5093 = call ptr @__alloc(i64 16, i32 1)
  %t5094 = inttoptr i64 12 to ptr
  %t5095 = getelementptr ptr, ptr %t5093, i32 0
  store ptr %t5094, ptr %t5095
  %t5096 = getelementptr ptr, ptr %t11, i32 2
  %t5097 = load ptr, ptr %t5096
  call void @__inc_ref(ptr %t5097)
  %t5098 = getelementptr ptr, ptr %t4, i32 1
  %t5099 = load ptr, ptr %t5098
  call void @__free_recursive(ptr %t5099)
  %t5100 = getelementptr ptr, ptr %t4, i32 2
  %t5101 = load ptr, ptr %t5100
  call void @__free_recursive(ptr %t5101)
  %t5104 = inttoptr i64 15 to ptr
  %t5105 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5104, ptr %t5105
  call void @__inc_ref(ptr %t13)
  %t5102 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t13, ptr %t5102
  %t5103 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t5097, ptr %t5103
  %t5106 = getelementptr ptr, ptr %t5093, i32 1
  store ptr %t4, ptr %t5106
  %t5107 = getelementptr ptr, ptr %t5087, i32 2
  store ptr %t5093, ptr %t5107
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t5087, ptr %t3
  br label %tco.loop.0
tco.case.arm.272.5108:
  %t5109 = call ptr @__alloc(i64 24, i32 2)
  %t5110 = inttoptr i64 279 to ptr
  %t5111 = getelementptr ptr, ptr %t5109, i32 0
  store ptr %t5110, ptr %t5111
  %t5112 = getelementptr ptr, ptr %t11, i32 1
  %t5113 = load ptr, ptr %t5112
  call void @__inc_ref(ptr %t5113)
  %t5114 = getelementptr ptr, ptr %t5109, i32 1
  store ptr %t5113, ptr %t5114
  %t5115 = call ptr @__alloc(i64 16, i32 1)
  %t5116 = inttoptr i64 12 to ptr
  %t5117 = getelementptr ptr, ptr %t5115, i32 0
  store ptr %t5116, ptr %t5117
  %t5118 = getelementptr ptr, ptr %t11, i32 2
  %t5119 = load ptr, ptr %t5118
  call void @__inc_ref(ptr %t5119)
  %t5120 = getelementptr ptr, ptr %t4, i32 1
  %t5121 = load ptr, ptr %t5120
  call void @__free_recursive(ptr %t5121)
  %t5122 = getelementptr ptr, ptr %t4, i32 2
  %t5123 = load ptr, ptr %t5122
  call void @__free_recursive(ptr %t5123)
  %t5126 = inttoptr i64 15 to ptr
  %t5127 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5126, ptr %t5127
  call void @__inc_ref(ptr %t13)
  %t5124 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t13, ptr %t5124
  %t5125 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t5119, ptr %t5125
  %t5128 = getelementptr ptr, ptr %t5115, i32 1
  store ptr %t4, ptr %t5128
  %t5129 = getelementptr ptr, ptr %t5109, i32 2
  store ptr %t5115, ptr %t5129
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t5109, ptr %t3
  br label %tco.loop.0
tco.case.arm.273.5130:
  %t5131 = call ptr @__alloc(i64 24, i32 2)
  %t5132 = inttoptr i64 279 to ptr
  %t5133 = getelementptr ptr, ptr %t5131, i32 0
  store ptr %t5132, ptr %t5133
  %t5134 = getelementptr ptr, ptr %t11, i32 1
  %t5135 = load ptr, ptr %t5134
  call void @__inc_ref(ptr %t5135)
  %t5136 = getelementptr ptr, ptr %t5131, i32 1
  store ptr %t5135, ptr %t5136
  %t5137 = call ptr @__alloc(i64 16, i32 1)
  %t5138 = inttoptr i64 12 to ptr
  %t5139 = getelementptr ptr, ptr %t5137, i32 0
  store ptr %t5138, ptr %t5139
  %t5140 = getelementptr ptr, ptr %t11, i32 2
  %t5141 = load ptr, ptr %t5140
  call void @__inc_ref(ptr %t5141)
  %t5142 = getelementptr ptr, ptr %t4, i32 1
  %t5143 = load ptr, ptr %t5142
  call void @__free_recursive(ptr %t5143)
  %t5144 = getelementptr ptr, ptr %t4, i32 2
  %t5145 = load ptr, ptr %t5144
  call void @__free_recursive(ptr %t5145)
  %t5148 = inttoptr i64 15 to ptr
  %t5149 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5148, ptr %t5149
  call void @__inc_ref(ptr %t13)
  %t5146 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t13, ptr %t5146
  %t5147 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t5141, ptr %t5147
  %t5150 = getelementptr ptr, ptr %t5137, i32 1
  store ptr %t4, ptr %t5150
  %t5151 = getelementptr ptr, ptr %t5131, i32 2
  store ptr %t5137, ptr %t5151
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t5131, ptr %t3
  br label %tco.loop.0
tco.case.arm.274.5152:
  %t5153 = call ptr @__alloc(i64 24, i32 2)
  %t5154 = inttoptr i64 279 to ptr
  %t5155 = getelementptr ptr, ptr %t5153, i32 0
  store ptr %t5154, ptr %t5155
  %t5156 = getelementptr ptr, ptr %t11, i32 1
  %t5157 = load ptr, ptr %t5156
  call void @__inc_ref(ptr %t5157)
  %t5158 = getelementptr ptr, ptr %t5153, i32 1
  store ptr %t5157, ptr %t5158
  %t5159 = call ptr @__alloc(i64 16, i32 1)
  %t5160 = inttoptr i64 12 to ptr
  %t5161 = getelementptr ptr, ptr %t5159, i32 0
  store ptr %t5160, ptr %t5161
  %t5162 = getelementptr ptr, ptr %t11, i32 2
  %t5163 = load ptr, ptr %t5162
  call void @__inc_ref(ptr %t5163)
  %t5164 = getelementptr ptr, ptr %t4, i32 1
  %t5165 = load ptr, ptr %t5164
  call void @__free_recursive(ptr %t5165)
  %t5166 = getelementptr ptr, ptr %t4, i32 2
  %t5167 = load ptr, ptr %t5166
  call void @__free_recursive(ptr %t5167)
  %t5170 = inttoptr i64 15 to ptr
  %t5171 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5170, ptr %t5171
  call void @__inc_ref(ptr %t13)
  %t5168 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t13, ptr %t5168
  %t5169 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t5163, ptr %t5169
  %t5172 = getelementptr ptr, ptr %t5159, i32 1
  store ptr %t4, ptr %t5172
  %t5173 = getelementptr ptr, ptr %t5153, i32 2
  store ptr %t5159, ptr %t5173
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t5153, ptr %t3
  br label %tco.loop.0
tco.case.arm.275.5174:
  %t5175 = call ptr @__alloc(i64 24, i32 2)
  %t5176 = inttoptr i64 279 to ptr
  %t5177 = getelementptr ptr, ptr %t5175, i32 0
  store ptr %t5176, ptr %t5177
  %t5178 = getelementptr ptr, ptr %t11, i32 1
  %t5179 = load ptr, ptr %t5178
  call void @__inc_ref(ptr %t5179)
  %t5180 = getelementptr ptr, ptr %t5175, i32 1
  store ptr %t5179, ptr %t5180
  %t5181 = call ptr @__alloc(i64 16, i32 1)
  %t5182 = inttoptr i64 12 to ptr
  %t5183 = getelementptr ptr, ptr %t5181, i32 0
  store ptr %t5182, ptr %t5183
  %t5184 = getelementptr ptr, ptr %t11, i32 2
  %t5185 = load ptr, ptr %t5184
  call void @__inc_ref(ptr %t5185)
  %t5186 = getelementptr ptr, ptr %t4, i32 1
  %t5187 = load ptr, ptr %t5186
  call void @__free_recursive(ptr %t5187)
  %t5189 = inttoptr i64 15 to ptr
  %t5190 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5189, ptr %t5190
  %t5188 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5185, ptr %t5188
  %t5191 = getelementptr ptr, ptr %t5181, i32 1
  store ptr %t4, ptr %t5191
  %t5192 = getelementptr ptr, ptr %t5175, i32 2
  store ptr %t5181, ptr %t5192
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t5175, ptr %t3
  br label %tco.loop.0
tco.case.arm.276.5193:
  %t5194 = call ptr @__alloc(i64 24, i32 2)
  %t5195 = inttoptr i64 279 to ptr
  %t5196 = getelementptr ptr, ptr %t5194, i32 0
  store ptr %t5195, ptr %t5196
  %t5197 = getelementptr ptr, ptr %t11, i32 1
  %t5198 = load ptr, ptr %t5197
  call void @__inc_ref(ptr %t5198)
  %t5199 = getelementptr ptr, ptr %t5194, i32 1
  store ptr %t5198, ptr %t5199
  %t5200 = call ptr @__alloc(i64 16, i32 1)
  %t5201 = inttoptr i64 12 to ptr
  %t5202 = getelementptr ptr, ptr %t5200, i32 0
  store ptr %t5201, ptr %t5202
  %t5203 = getelementptr ptr, ptr %t11, i32 2
  %t5204 = load ptr, ptr %t5203
  call void @__inc_ref(ptr %t5204)
  %t5205 = getelementptr ptr, ptr %t4, i32 1
  %t5206 = load ptr, ptr %t5205
  call void @__free_recursive(ptr %t5206)
  %t5208 = inttoptr i64 15 to ptr
  %t5209 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5208, ptr %t5209
  %t5207 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5204, ptr %t5207
  %t5210 = getelementptr ptr, ptr %t5200, i32 1
  store ptr %t4, ptr %t5210
  %t5211 = getelementptr ptr, ptr %t5194, i32 2
  store ptr %t5200, ptr %t5211
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t5194, ptr %t3
  br label %tco.loop.0
tco.case.arm.277.5212:
  %t5213 = call ptr @__alloc(i64 24, i32 2)
  %t5214 = inttoptr i64 279 to ptr
  %t5215 = getelementptr ptr, ptr %t5213, i32 0
  store ptr %t5214, ptr %t5215
  %t5216 = getelementptr ptr, ptr %t11, i32 1
  %t5217 = load ptr, ptr %t5216
  call void @__inc_ref(ptr %t5217)
  %t5218 = getelementptr ptr, ptr %t5213, i32 1
  store ptr %t5217, ptr %t5218
  %t5219 = call ptr @__alloc(i64 16, i32 1)
  %t5220 = inttoptr i64 12 to ptr
  %t5221 = getelementptr ptr, ptr %t5219, i32 0
  store ptr %t5220, ptr %t5221
  %t5222 = getelementptr ptr, ptr %t11, i32 2
  %t5223 = load ptr, ptr %t5222
  call void @__inc_ref(ptr %t5223)
  %t5224 = getelementptr ptr, ptr %t4, i32 1
  %t5225 = load ptr, ptr %t5224
  call void @__free_recursive(ptr %t5225)
  %t5227 = inttoptr i64 15 to ptr
  %t5228 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5227, ptr %t5228
  %t5226 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5223, ptr %t5226
  %t5229 = getelementptr ptr, ptr %t5219, i32 1
  store ptr %t4, ptr %t5229
  %t5230 = getelementptr ptr, ptr %t5213, i32 2
  store ptr %t5219, ptr %t5230
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t5213, ptr %t3
  br label %tco.loop.0
tco.case.arm.278.5231:
  %t5232 = call ptr @__alloc(i64 24, i32 2)
  %t5233 = inttoptr i64 279 to ptr
  %t5234 = getelementptr ptr, ptr %t5232, i32 0
  store ptr %t5233, ptr %t5234
  %t5235 = getelementptr ptr, ptr %t11, i32 1
  %t5236 = load ptr, ptr %t5235
  call void @__inc_ref(ptr %t5236)
  %t5237 = getelementptr ptr, ptr %t5232, i32 1
  store ptr %t5236, ptr %t5237
  %t5238 = call ptr @__alloc(i64 16, i32 1)
  %t5239 = inttoptr i64 12 to ptr
  %t5240 = getelementptr ptr, ptr %t5238, i32 0
  store ptr %t5239, ptr %t5240
  %t5241 = getelementptr ptr, ptr %t11, i32 2
  %t5242 = load ptr, ptr %t5241
  call void @__inc_ref(ptr %t5242)
  %t5243 = getelementptr ptr, ptr %t4, i32 1
  %t5244 = load ptr, ptr %t5243
  call void @__free_recursive(ptr %t5244)
  %t5246 = inttoptr i64 15 to ptr
  %t5247 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5246, ptr %t5247
  %t5245 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5242, ptr %t5245
  %t5248 = getelementptr ptr, ptr %t5238, i32 1
  store ptr %t4, ptr %t5248
  %t5249 = getelementptr ptr, ptr %t5232, i32 2
  store ptr %t5238, ptr %t5249
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t5232, ptr %t3
  br label %tco.loop.0
tco.case.default.17:
  unreachable
tco.case.arm.280.5250:
  %t5251 = getelementptr ptr, ptr %t4, i32 1
  %t5252 = load ptr, ptr %t5251
  call void @__inc_ref(ptr %t5252)
  %t5253 = getelementptr ptr, ptr %t4, i32 2
  %t5254 = load ptr, ptr %t5253
  call void @__inc_ref(ptr %t5254)
  %t5255 = getelementptr ptr, ptr %t5252, i32 0
  %t5256 = load ptr, ptr %t5255
  %t5257 = ptrtoint ptr %t5256 to i64
  switch i64 %t5257, label %tco.case.default.5258 [ i64 53, label %tco.case.arm.53.5259 i64 54, label %tco.case.arm.54.5475 i64 55, label %tco.case.arm.55.5737 i64 56, label %tco.case.arm.56.5759 i64 57, label %tco.case.arm.57.5781 i64 58, label %tco.case.arm.58.5803 i64 59, label %tco.case.arm.59.5874 i64 60, label %tco.case.arm.60.5945 i64 61, label %tco.case.arm.61.6024 i64 62, label %tco.case.arm.62.6103 i64 63, label %tco.case.arm.63.6178 i64 64, label %tco.case.arm.64.6253 i64 65, label %tco.case.arm.65.6325 i64 66, label %tco.case.arm.66.6397 i64 67, label %tco.case.arm.67.6480 i64 68, label %tco.case.arm.68.6563 i64 69, label %tco.case.arm.69.6645 i64 70, label %tco.case.arm.70.6727 i64 71, label %tco.case.arm.71.6796 i64 72, label %tco.case.arm.72.6845 i64 73, label %tco.case.arm.73.6894 i64 74, label %tco.case.arm.74.7003 i64 75, label %tco.case.arm.75.7065 i64 76, label %tco.case.arm.76.7129 i64 77, label %tco.case.arm.77.7154 i64 78, label %tco.case.arm.78.7179 i64 79, label %tco.case.arm.79.7305 i64 80, label %tco.case.arm.80.7431 i64 81, label %tco.case.arm.81.7513 i64 82, label %tco.case.arm.82.7595 i64 83, label %tco.case.arm.83.7617 i64 84, label %tco.case.arm.84.7639 i64 85, label %tco.case.arm.85.7658 i64 86, label %tco.case.arm.86.7783 i64 87, label %tco.case.arm.87.7801 i64 88, label %tco.case.arm.88.7819 i64 89, label %tco.case.arm.89.7844 i64 90, label %tco.case.arm.90.7952 i64 91, label %tco.case.arm.91.8118 i64 92, label %tco.case.arm.92.8163 i64 93, label %tco.case.arm.93.8193 i64 94, label %tco.case.arm.94.8254 i64 95, label %tco.case.arm.95.8315 i64 96, label %tco.case.arm.96.8337 i64 97, label %tco.case.arm.97.8460 i64 98, label %tco.case.arm.98.8569 i64 99, label %tco.case.arm.99.8621 i64 100, label %tco.case.arm.100.8897 i64 101, label %tco.case.arm.101.8924 i64 102, label %tco.case.arm.102.8944 i64 103, label %tco.case.arm.103.9050 i64 104, label %tco.case.arm.104.9097 i64 105, label %tco.case.arm.105.9124 i64 106, label %tco.case.arm.106.9154 i64 107, label %tco.case.arm.107.9302 i64 108, label %tco.case.arm.108.9339 i64 109, label %tco.case.arm.109.9462 i64 110, label %tco.case.arm.110.9511 i64 111, label %tco.case.arm.111.9626 i64 112, label %tco.case.arm.112.9732 i64 113, label %tco.case.arm.113.9755 i64 114, label %tco.case.arm.114.9804 i64 115, label %tco.case.arm.115.9970 i64 116, label %tco.case.arm.116.10015 i64 117, label %tco.case.arm.117.10192 ]
tco.case.arm.53.5259:
  %t5260 = getelementptr ptr, ptr %t5252, i32 1
  %t5261 = load ptr, ptr %t5260
  call void @__inc_ref(ptr %t5261)
  %t5262 = getelementptr ptr, ptr %t5252, i32 2
  %t5263 = load ptr, ptr %t5262
  call void @__inc_ref(ptr %t5263)
  %t5264 = getelementptr ptr, ptr %t5261, i32 0
  %t5265 = load ptr, ptr %t5264
  %t5266 = ptrtoint ptr %t5265 to i64
  switch i64 %t5266, label %tco.case.default.5267 [ i64 41, label %tco.case.arm.41.5268 i64 42, label %tco.case.arm.42.5284 i64 43, label %tco.case.arm.43.5300 i64 44, label %tco.case.arm.44.5316 i64 45, label %tco.case.arm.45.5332 i64 46, label %tco.case.arm.46.5363 i64 47, label %tco.case.arm.47.5375 i64 48, label %tco.case.arm.48.5391 i64 49, label %tco.case.arm.49.5422 i64 50, label %tco.case.arm.50.5433 i64 51, label %tco.case.arm.51.5446 i64 52, label %tco.case.arm.52.5459 ]
tco.case.arm.41.5268:
  %t5269 = call ptr @__alloc(i64 24, i32 2)
  %t5270 = inttoptr i64 279 to ptr
  %t5271 = getelementptr ptr, ptr %t5269, i32 0
  store ptr %t5270, ptr %t5271
  call void @__inc_ref(ptr %t5254)
  %t5272 = getelementptr ptr, ptr %t5269, i32 1
  store ptr %t5254, ptr %t5272
  %t5273 = getelementptr ptr, ptr %t5261, i32 1
  %t5274 = load ptr, ptr %t5273
  call void @__inc_ref(ptr %t5274)
  %t5275 = getelementptr ptr, ptr %t4, i32 1
  %t5276 = load ptr, ptr %t5275
  call void @__free_recursive(ptr %t5276)
  %t5277 = getelementptr ptr, ptr %t4, i32 2
  %t5278 = load ptr, ptr %t5277
  call void @__free_recursive(ptr %t5278)
  %t5281 = inttoptr i64 14 to ptr
  %t5282 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5281, ptr %t5282
  %t5279 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5274, ptr %t5279
  call void @__inc_ref(ptr %t5263)
  %t5280 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t5263, ptr %t5280
  %t5283 = getelementptr ptr, ptr %t5269, i32 2
  store ptr %t4, ptr %t5283
  call void @__free_recursive(ptr %t5263)
  call void @__free_recursive(ptr %t5261)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t5269, ptr %t3
  br label %tco.loop.0
tco.case.arm.42.5284:
  %t5285 = call ptr @__alloc(i64 24, i32 2)
  %t5286 = inttoptr i64 280 to ptr
  %t5287 = getelementptr ptr, ptr %t5285, i32 0
  store ptr %t5286, ptr %t5287
  %t5288 = getelementptr ptr, ptr %t5261, i32 1
  %t5289 = load ptr, ptr %t5288
  call void @__inc_ref(ptr %t5289)
  %t5290 = getelementptr ptr, ptr %t4, i32 1
  %t5291 = load ptr, ptr %t5290
  call void @__free_recursive(ptr %t5291)
  %t5292 = getelementptr ptr, ptr %t4, i32 2
  %t5293 = load ptr, ptr %t5292
  call void @__free_recursive(ptr %t5293)
  %t5296 = inttoptr i64 55 to ptr
  %t5297 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5296, ptr %t5297
  %t5294 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5289, ptr %t5294
  call void @__inc_ref(ptr %t5263)
  %t5295 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t5263, ptr %t5295
  %t5298 = getelementptr ptr, ptr %t5285, i32 1
  store ptr %t4, ptr %t5298
  call void @__inc_ref(ptr %t5254)
  %t5299 = getelementptr ptr, ptr %t5285, i32 2
  store ptr %t5254, ptr %t5299
  call void @__free_recursive(ptr %t5263)
  call void @__free_recursive(ptr %t5261)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t5285, ptr %t3
  br label %tco.loop.0
tco.case.arm.43.5300:
  %t5301 = call ptr @__alloc(i64 24, i32 2)
  %t5302 = inttoptr i64 280 to ptr
  %t5303 = getelementptr ptr, ptr %t5301, i32 0
  store ptr %t5302, ptr %t5303
  %t5304 = getelementptr ptr, ptr %t5261, i32 1
  %t5305 = load ptr, ptr %t5304
  call void @__inc_ref(ptr %t5305)
  %t5306 = getelementptr ptr, ptr %t4, i32 1
  %t5307 = load ptr, ptr %t5306
  call void @__free_recursive(ptr %t5307)
  %t5308 = getelementptr ptr, ptr %t4, i32 2
  %t5309 = load ptr, ptr %t5308
  call void @__free_recursive(ptr %t5309)
  %t5312 = inttoptr i64 56 to ptr
  %t5313 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5312, ptr %t5313
  %t5310 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5305, ptr %t5310
  call void @__inc_ref(ptr %t5263)
  %t5311 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t5263, ptr %t5311
  %t5314 = getelementptr ptr, ptr %t5301, i32 1
  store ptr %t4, ptr %t5314
  call void @__inc_ref(ptr %t5254)
  %t5315 = getelementptr ptr, ptr %t5301, i32 2
  store ptr %t5254, ptr %t5315
  call void @__free_recursive(ptr %t5263)
  call void @__free_recursive(ptr %t5261)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t5301, ptr %t3
  br label %tco.loop.0
tco.case.arm.44.5316:
  %t5317 = call ptr @__alloc(i64 24, i32 2)
  %t5318 = inttoptr i64 280 to ptr
  %t5319 = getelementptr ptr, ptr %t5317, i32 0
  store ptr %t5318, ptr %t5319
  %t5320 = getelementptr ptr, ptr %t5261, i32 1
  %t5321 = load ptr, ptr %t5320
  call void @__inc_ref(ptr %t5321)
  %t5322 = getelementptr ptr, ptr %t4, i32 1
  %t5323 = load ptr, ptr %t5322
  call void @__free_recursive(ptr %t5323)
  %t5324 = getelementptr ptr, ptr %t4, i32 2
  %t5325 = load ptr, ptr %t5324
  call void @__free_recursive(ptr %t5325)
  %t5328 = inttoptr i64 57 to ptr
  %t5329 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5328, ptr %t5329
  %t5326 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5321, ptr %t5326
  call void @__inc_ref(ptr %t5263)
  %t5327 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t5263, ptr %t5327
  %t5330 = getelementptr ptr, ptr %t5317, i32 1
  store ptr %t4, ptr %t5330
  call void @__inc_ref(ptr %t5254)
  %t5331 = getelementptr ptr, ptr %t5317, i32 2
  store ptr %t5254, ptr %t5331
  call void @__free_recursive(ptr %t5263)
  call void @__free_recursive(ptr %t5261)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t5317, ptr %t3
  br label %tco.loop.0
tco.case.arm.45.5332:
  %t5333 = getelementptr ptr, ptr %t5263, i32 0
  %t5334 = load ptr, ptr %t5333
  %t5335 = ptrtoint ptr %t5334 to i64
  switch i64 %t5335, label %case.default.5336 [ i64 3, label %case.arm.3.5338 i64 4, label %case.arm.4.5346 ]
case.arm.3.5338:
  %t5340 = call ptr @__alloc(i64 16, i32 1)
  %t5341 = inttoptr i64 6 to ptr
  %t5342 = getelementptr ptr, ptr %t5340, i32 0
  store ptr %t5341, ptr %t5342
  %t5343 = getelementptr ptr, ptr %t5263, i32 1
  %t5344 = load ptr, ptr %t5343
  call void @__inc_ref(ptr %t5344)
  %t5345 = getelementptr ptr, ptr %t5340, i32 1
  store ptr %t5344, ptr %t5345
  br label %case.end.3.5339
case.end.3.5339:
  br label %case.join.5337
case.arm.4.5346:
  %t5348 = call ptr @__alloc(i64 16, i32 1)
  %t5349 = inttoptr i64 5 to ptr
  %t5350 = getelementptr ptr, ptr %t5348, i32 0
  store ptr %t5349, ptr %t5350
  %t5351 = getelementptr ptr, ptr %t5263, i32 1
  %t5352 = load ptr, ptr %t5351
  call void @__inc_ref(ptr %t5352)
  %t5353 = getelementptr ptr, ptr %t5348, i32 1
  store ptr %t5352, ptr %t5353
  br label %case.end.4.5347
case.end.4.5347:
  br label %case.join.5337
case.default.5336:
  unreachable
case.join.5337:
  %t5354 = phi ptr [ %t5340, %case.end.3.5339 ], [ %t5348, %case.end.4.5347 ]
  %t5355 = getelementptr ptr, ptr %t4, i32 1
  %t5356 = load ptr, ptr %t5355
  call void @__free_recursive(ptr %t5356)
  %t5357 = getelementptr ptr, ptr %t4, i32 2
  %t5358 = load ptr, ptr %t5357
  call void @__free_recursive(ptr %t5358)
  %t5361 = inttoptr i64 279 to ptr
  %t5362 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5361, ptr %t5362
  call void @__inc_ref(ptr %t5254)
  %t5359 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t5359
  %t5360 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t5354, ptr %t5360
  call void @__free_recursive(ptr %t5263)
  call void @__free_recursive(ptr %t5261)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.46.5363:
  %t5364 = getelementptr ptr, ptr %t5261, i32 1
  %t5365 = load ptr, ptr %t5364
  call void @__inc_ref(ptr %t5365)
  call void @__inc_ref(ptr %t5263)
  %t5366 = call ptr @v_addStats(ptr %t5365, ptr %t5263)
  %t5367 = getelementptr ptr, ptr %t4, i32 1
  %t5368 = load ptr, ptr %t5367
  call void @__free_recursive(ptr %t5368)
  %t5369 = getelementptr ptr, ptr %t4, i32 2
  %t5370 = load ptr, ptr %t5369
  call void @__free_recursive(ptr %t5370)
  %t5373 = inttoptr i64 279 to ptr
  %t5374 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5373, ptr %t5374
  call void @__inc_ref(ptr %t5254)
  %t5371 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t5371
  %t5372 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t5366, ptr %t5372
  call void @__free_recursive(ptr %t5263)
  call void @__free_recursive(ptr %t5261)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.47.5375:
  %t5376 = call ptr @__alloc(i64 32, i32 3)
  %t5377 = inttoptr i64 98 to ptr
  %t5378 = getelementptr ptr, ptr %t5376, i32 0
  store ptr %t5377, ptr %t5378
  %t5379 = getelementptr ptr, ptr %t5261, i32 1
  %t5380 = load ptr, ptr %t5379
  call void @__inc_ref(ptr %t5380)
  %t5381 = getelementptr ptr, ptr %t5376, i32 1
  store ptr %t5380, ptr %t5381
  %t5382 = getelementptr ptr, ptr %t5261, i32 2
  %t5383 = load ptr, ptr %t5382
  call void @__inc_ref(ptr %t5383)
  %t5384 = getelementptr ptr, ptr %t5376, i32 2
  store ptr %t5383, ptr %t5384
  call void @__inc_ref(ptr %t5263)
  %t5385 = getelementptr ptr, ptr %t5376, i32 3
  store ptr %t5263, ptr %t5385
  %t5386 = getelementptr ptr, ptr %t4, i32 1
  %t5387 = load ptr, ptr %t5386
  call void @__free_recursive(ptr %t5387)
  %t5389 = inttoptr i64 280 to ptr
  %t5390 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5389, ptr %t5390
  %t5388 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5376, ptr %t5388
  call void @__free_recursive(ptr %t5263)
  call void @__free_recursive(ptr %t5261)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.48.5391:
  %t5392 = call ptr @__alloc(i64 24, i32 2)
  %t5393 = inttoptr i64 279 to ptr
  %t5394 = getelementptr ptr, ptr %t5392, i32 0
  store ptr %t5393, ptr %t5394
  call void @__inc_ref(ptr %t5254)
  %t5395 = getelementptr ptr, ptr %t5392, i32 1
  store ptr %t5254, ptr %t5395
  %t5396 = call ptr @__alloc(i64 4, i32 0)
  store i32 1, ptr %t5396
  call void @__inc_ref(ptr %t5263)
  %t5397 = call ptr @__lengthUtf16CodeUnits(ptr %t5263)
  %t5398 = call ptr @__alloc(i64 4, i32 0)
  store i32 1, ptr %t5398
  %t5399 = call ptr @__addUInt32(ptr %t5397, ptr %t5398)
  %t5400 = getelementptr ptr, ptr %t5399, i32 0
  %t5401 = load ptr, ptr %t5400
  %t5402 = ptrtoint ptr %t5401 to i64
  switch i64 %t5402, label %case.default.5403 [ i64 3, label %case.arm.3.5405 i64 4, label %case.arm.4.5408 ]
case.arm.3.5405:
  %t5407 = call ptr @v_maxUInt32()
  br label %case.end.3.5406
case.end.3.5406:
  br label %case.join.5404
case.arm.4.5408:
  %t5410 = getelementptr ptr, ptr %t5399, i32 1
  %t5411 = load ptr, ptr %t5410
  call void @__inc_ref(ptr %t5411)
  call void @__inc_ref(ptr %t5411)
  call void @__free_recursive(ptr %t5411)
  br label %case.end.4.5409
case.end.4.5409:
  br label %case.join.5404
case.default.5403:
  unreachable
case.join.5404:
  %t5412 = phi ptr [ %t5407, %case.end.3.5406 ], [ %t5411, %case.end.4.5409 ]
  call void @__free_recursive(ptr %t5399)
  %t5413 = getelementptr ptr, ptr %t4, i32 1
  %t5414 = load ptr, ptr %t5413
  call void @__free_recursive(ptr %t5414)
  %t5415 = getelementptr ptr, ptr %t4, i32 2
  %t5416 = load ptr, ptr %t5415
  call void @__free_recursive(ptr %t5416)
  %t5419 = inttoptr i64 35 to ptr
  %t5420 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5419, ptr %t5420
  %t5417 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5396, ptr %t5417
  %t5418 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t5412, ptr %t5418
  %t5421 = getelementptr ptr, ptr %t5392, i32 2
  store ptr %t4, ptr %t5421
  call void @__free_recursive(ptr %t5263)
  call void @__free_recursive(ptr %t5261)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t5392, ptr %t3
  br label %tco.loop.0
tco.case.arm.49.5422:
  %t5423 = getelementptr ptr, ptr %t5263, i32 1
  %t5424 = load ptr, ptr %t5423
  call void @__inc_ref(ptr %t5424)
  %t5425 = getelementptr ptr, ptr %t4, i32 1
  %t5426 = load ptr, ptr %t5425
  call void @__free_recursive(ptr %t5426)
  %t5427 = getelementptr ptr, ptr %t4, i32 2
  %t5428 = load ptr, ptr %t5427
  call void @__free_recursive(ptr %t5428)
  %t5431 = inttoptr i64 279 to ptr
  %t5432 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5431, ptr %t5432
  call void @__inc_ref(ptr %t5254)
  %t5429 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t5429
  %t5430 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t5424, ptr %t5430
  call void @__free_recursive(ptr %t5263)
  call void @__free_recursive(ptr %t5261)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.50.5433:
  %t5434 = call ptr @__alloc(i64 16, i32 1)
  %t5435 = inttoptr i64 41 to ptr
  %t5436 = getelementptr ptr, ptr %t5434, i32 0
  store ptr %t5435, ptr %t5436
  call void @__inc_ref(ptr %t5263)
  %t5437 = getelementptr ptr, ptr %t5434, i32 1
  store ptr %t5263, ptr %t5437
  %t5438 = getelementptr ptr, ptr %t4, i32 1
  %t5439 = load ptr, ptr %t5438
  call void @__free_recursive(ptr %t5439)
  %t5440 = getelementptr ptr, ptr %t4, i32 2
  %t5441 = load ptr, ptr %t5440
  call void @__free_recursive(ptr %t5441)
  %t5444 = inttoptr i64 279 to ptr
  %t5445 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5444, ptr %t5445
  call void @__inc_ref(ptr %t5254)
  %t5442 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t5442
  %t5443 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t5434, ptr %t5443
  call void @__free_recursive(ptr %t5263)
  call void @__free_recursive(ptr %t5261)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.51.5446:
  %t5447 = call ptr @__alloc(i64 16, i32 1)
  %t5448 = inttoptr i64 46 to ptr
  %t5449 = getelementptr ptr, ptr %t5447, i32 0
  store ptr %t5448, ptr %t5449
  call void @__inc_ref(ptr %t5263)
  %t5450 = getelementptr ptr, ptr %t5447, i32 1
  store ptr %t5263, ptr %t5450
  %t5451 = getelementptr ptr, ptr %t4, i32 1
  %t5452 = load ptr, ptr %t5451
  call void @__free_recursive(ptr %t5452)
  %t5453 = getelementptr ptr, ptr %t4, i32 2
  %t5454 = load ptr, ptr %t5453
  call void @__free_recursive(ptr %t5454)
  %t5457 = inttoptr i64 279 to ptr
  %t5458 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5457, ptr %t5458
  call void @__inc_ref(ptr %t5254)
  %t5455 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t5455
  %t5456 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t5447, ptr %t5456
  call void @__free_recursive(ptr %t5263)
  call void @__free_recursive(ptr %t5261)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.52.5459:
  %t5460 = call ptr @__alloc(i64 24, i32 2)
  %t5461 = inttoptr i64 279 to ptr
  %t5462 = getelementptr ptr, ptr %t5460, i32 0
  store ptr %t5461, ptr %t5462
  call void @__inc_ref(ptr %t5254)
  %t5463 = getelementptr ptr, ptr %t5460, i32 1
  store ptr %t5254, ptr %t5463
  %t5464 = getelementptr ptr, ptr %t5261, i32 1
  %t5465 = load ptr, ptr %t5464
  call void @__inc_ref(ptr %t5465)
  %t5466 = getelementptr ptr, ptr %t4, i32 1
  %t5467 = load ptr, ptr %t5466
  call void @__free_recursive(ptr %t5467)
  %t5468 = getelementptr ptr, ptr %t4, i32 2
  %t5469 = load ptr, ptr %t5468
  call void @__free_recursive(ptr %t5469)
  %t5472 = inttoptr i64 47 to ptr
  %t5473 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5472, ptr %t5473
  %t5470 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5465, ptr %t5470
  call void @__inc_ref(ptr %t5263)
  %t5471 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t5263, ptr %t5471
  %t5474 = getelementptr ptr, ptr %t5460, i32 2
  store ptr %t4, ptr %t5474
  call void @__free_recursive(ptr %t5263)
  call void @__free_recursive(ptr %t5261)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t5460, ptr %t3
  br label %tco.loop.0
tco.case.default.5267:
  unreachable
tco.case.arm.54.5475:
  %t5476 = getelementptr ptr, ptr %t5252, i32 1
  %t5477 = load ptr, ptr %t5476
  call void @__inc_ref(ptr %t5477)
  %t5478 = getelementptr ptr, ptr %t5252, i32 2
  %t5479 = load ptr, ptr %t5478
  call void @__inc_ref(ptr %t5479)
  %t5480 = getelementptr ptr, ptr %t5252, i32 3
  %t5481 = load ptr, ptr %t5480
  call void @__inc_ref(ptr %t5481)
  %t5482 = getelementptr ptr, ptr %t5477, i32 0
  %t5483 = load ptr, ptr %t5482
  %t5484 = ptrtoint ptr %t5483 to i64
  switch i64 %t5484, label %tco.case.default.5485 [ i64 41, label %tco.case.arm.41.5486 i64 42, label %tco.case.arm.42.5507 i64 43, label %tco.case.arm.43.5528 i64 44, label %tco.case.arm.44.5549 i64 45, label %tco.case.arm.45.5570 i64 46, label %tco.case.arm.46.5606 i64 47, label %tco.case.arm.47.5623 i64 48, label %tco.case.arm.48.5647 i64 49, label %tco.case.arm.49.5683 i64 50, label %tco.case.arm.50.5699 i64 51, label %tco.case.arm.51.5713 i64 52, label %tco.case.arm.52.5723 ]
tco.case.arm.41.5486:
  %t5487 = call ptr @__alloc(i64 24, i32 2)
  %t5488 = inttoptr i64 280 to ptr
  %t5489 = getelementptr ptr, ptr %t5487, i32 0
  store ptr %t5488, ptr %t5489
  %t5490 = call ptr @__alloc(i64 24, i32 2)
  %t5491 = inttoptr i64 53 to ptr
  %t5492 = getelementptr ptr, ptr %t5490, i32 0
  store ptr %t5491, ptr %t5492
  %t5493 = getelementptr ptr, ptr %t5477, i32 1
  %t5494 = load ptr, ptr %t5493
  call void @__inc_ref(ptr %t5494)
  %t5495 = getelementptr ptr, ptr %t4, i32 1
  %t5496 = load ptr, ptr %t5495
  call void @__free_recursive(ptr %t5496)
  %t5497 = getelementptr ptr, ptr %t4, i32 2
  %t5498 = load ptr, ptr %t5497
  call void @__free_recursive(ptr %t5498)
  %t5501 = inttoptr i64 14 to ptr
  %t5502 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5501, ptr %t5502
  %t5499 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5494, ptr %t5499
  call void @__inc_ref(ptr %t5479)
  %t5500 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t5479, ptr %t5500
  %t5503 = getelementptr ptr, ptr %t5490, i32 1
  store ptr %t4, ptr %t5503
  call void @__inc_ref(ptr %t5481)
  %t5504 = getelementptr ptr, ptr %t5490, i32 2
  store ptr %t5481, ptr %t5504
  %t5505 = getelementptr ptr, ptr %t5487, i32 1
  store ptr %t5490, ptr %t5505
  call void @__inc_ref(ptr %t5254)
  %t5506 = getelementptr ptr, ptr %t5487, i32 2
  store ptr %t5254, ptr %t5506
  call void @__free_recursive(ptr %t5481)
  call void @__free_recursive(ptr %t5479)
  call void @__free_recursive(ptr %t5477)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t5487, ptr %t3
  br label %tco.loop.0
tco.case.arm.42.5507:
  %t5508 = call ptr @__alloc(i64 24, i32 2)
  %t5509 = inttoptr i64 280 to ptr
  %t5510 = getelementptr ptr, ptr %t5508, i32 0
  store ptr %t5509, ptr %t5510
  %t5511 = getelementptr ptr, ptr %t5477, i32 1
  %t5512 = load ptr, ptr %t5511
  call void @__inc_ref(ptr %t5512)
  %t5513 = getelementptr ptr, ptr %t4, i32 1
  %t5514 = load ptr, ptr %t5513
  call void @__free_recursive(ptr %t5514)
  %t5515 = getelementptr ptr, ptr %t4, i32 2
  %t5516 = load ptr, ptr %t5515
  call void @__free_recursive(ptr %t5516)
  %t5519 = inttoptr i64 55 to ptr
  %t5520 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5519, ptr %t5520
  %t5517 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5512, ptr %t5517
  call void @__inc_ref(ptr %t5479)
  %t5518 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t5479, ptr %t5518
  %t5521 = getelementptr ptr, ptr %t5508, i32 1
  store ptr %t4, ptr %t5521
  %t5522 = call ptr @__alloc(i64 24, i32 2)
  %t5523 = inttoptr i64 127 to ptr
  %t5524 = getelementptr ptr, ptr %t5522, i32 0
  store ptr %t5523, ptr %t5524
  call void @__inc_ref(ptr %t5254)
  %t5525 = getelementptr ptr, ptr %t5522, i32 1
  store ptr %t5254, ptr %t5525
  call void @__inc_ref(ptr %t5481)
  %t5526 = getelementptr ptr, ptr %t5522, i32 2
  store ptr %t5481, ptr %t5526
  %t5527 = getelementptr ptr, ptr %t5508, i32 2
  store ptr %t5522, ptr %t5527
  call void @__free_recursive(ptr %t5481)
  call void @__free_recursive(ptr %t5479)
  call void @__free_recursive(ptr %t5477)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t5508, ptr %t3
  br label %tco.loop.0
tco.case.arm.43.5528:
  %t5529 = call ptr @__alloc(i64 24, i32 2)
  %t5530 = inttoptr i64 280 to ptr
  %t5531 = getelementptr ptr, ptr %t5529, i32 0
  store ptr %t5530, ptr %t5531
  %t5532 = getelementptr ptr, ptr %t5477, i32 1
  %t5533 = load ptr, ptr %t5532
  call void @__inc_ref(ptr %t5533)
  %t5534 = getelementptr ptr, ptr %t4, i32 1
  %t5535 = load ptr, ptr %t5534
  call void @__free_recursive(ptr %t5535)
  %t5536 = getelementptr ptr, ptr %t4, i32 2
  %t5537 = load ptr, ptr %t5536
  call void @__free_recursive(ptr %t5537)
  %t5540 = inttoptr i64 56 to ptr
  %t5541 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5540, ptr %t5541
  %t5538 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5533, ptr %t5538
  call void @__inc_ref(ptr %t5479)
  %t5539 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t5479, ptr %t5539
  %t5542 = getelementptr ptr, ptr %t5529, i32 1
  store ptr %t4, ptr %t5542
  %t5543 = call ptr @__alloc(i64 24, i32 2)
  %t5544 = inttoptr i64 128 to ptr
  %t5545 = getelementptr ptr, ptr %t5543, i32 0
  store ptr %t5544, ptr %t5545
  call void @__inc_ref(ptr %t5254)
  %t5546 = getelementptr ptr, ptr %t5543, i32 1
  store ptr %t5254, ptr %t5546
  call void @__inc_ref(ptr %t5481)
  %t5547 = getelementptr ptr, ptr %t5543, i32 2
  store ptr %t5481, ptr %t5547
  %t5548 = getelementptr ptr, ptr %t5529, i32 2
  store ptr %t5543, ptr %t5548
  call void @__free_recursive(ptr %t5481)
  call void @__free_recursive(ptr %t5479)
  call void @__free_recursive(ptr %t5477)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t5529, ptr %t3
  br label %tco.loop.0
tco.case.arm.44.5549:
  %t5550 = call ptr @__alloc(i64 24, i32 2)
  %t5551 = inttoptr i64 280 to ptr
  %t5552 = getelementptr ptr, ptr %t5550, i32 0
  store ptr %t5551, ptr %t5552
  %t5553 = getelementptr ptr, ptr %t5477, i32 1
  %t5554 = load ptr, ptr %t5553
  call void @__inc_ref(ptr %t5554)
  %t5555 = getelementptr ptr, ptr %t4, i32 1
  %t5556 = load ptr, ptr %t5555
  call void @__free_recursive(ptr %t5556)
  %t5557 = getelementptr ptr, ptr %t4, i32 2
  %t5558 = load ptr, ptr %t5557
  call void @__free_recursive(ptr %t5558)
  %t5561 = inttoptr i64 57 to ptr
  %t5562 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5561, ptr %t5562
  %t5559 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5554, ptr %t5559
  call void @__inc_ref(ptr %t5479)
  %t5560 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t5479, ptr %t5560
  %t5563 = getelementptr ptr, ptr %t5550, i32 1
  store ptr %t4, ptr %t5563
  %t5564 = call ptr @__alloc(i64 24, i32 2)
  %t5565 = inttoptr i64 129 to ptr
  %t5566 = getelementptr ptr, ptr %t5564, i32 0
  store ptr %t5565, ptr %t5566
  call void @__inc_ref(ptr %t5254)
  %t5567 = getelementptr ptr, ptr %t5564, i32 1
  store ptr %t5254, ptr %t5567
  call void @__inc_ref(ptr %t5481)
  %t5568 = getelementptr ptr, ptr %t5564, i32 2
  store ptr %t5481, ptr %t5568
  %t5569 = getelementptr ptr, ptr %t5550, i32 2
  store ptr %t5564, ptr %t5569
  call void @__free_recursive(ptr %t5481)
  call void @__free_recursive(ptr %t5479)
  call void @__free_recursive(ptr %t5477)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t5550, ptr %t3
  br label %tco.loop.0
tco.case.arm.45.5570:
  %t5571 = call ptr @__alloc(i64 24, i32 2)
  %t5572 = inttoptr i64 280 to ptr
  %t5573 = getelementptr ptr, ptr %t5571, i32 0
  store ptr %t5572, ptr %t5573
  %t5574 = getelementptr ptr, ptr %t5479, i32 0
  %t5575 = load ptr, ptr %t5574
  %t5576 = ptrtoint ptr %t5575 to i64
  switch i64 %t5576, label %case.default.5577 [ i64 3, label %case.arm.3.5579 i64 4, label %case.arm.4.5587 ]
case.arm.3.5579:
  %t5581 = call ptr @__alloc(i64 16, i32 1)
  %t5582 = inttoptr i64 6 to ptr
  %t5583 = getelementptr ptr, ptr %t5581, i32 0
  store ptr %t5582, ptr %t5583
  %t5584 = getelementptr ptr, ptr %t5479, i32 1
  %t5585 = load ptr, ptr %t5584
  call void @__inc_ref(ptr %t5585)
  %t5586 = getelementptr ptr, ptr %t5581, i32 1
  store ptr %t5585, ptr %t5586
  br label %case.end.3.5580
case.end.3.5580:
  br label %case.join.5578
case.arm.4.5587:
  %t5589 = call ptr @__alloc(i64 16, i32 1)
  %t5590 = inttoptr i64 5 to ptr
  %t5591 = getelementptr ptr, ptr %t5589, i32 0
  store ptr %t5590, ptr %t5591
  %t5592 = getelementptr ptr, ptr %t5479, i32 1
  %t5593 = load ptr, ptr %t5592
  call void @__inc_ref(ptr %t5593)
  %t5594 = getelementptr ptr, ptr %t5589, i32 1
  store ptr %t5593, ptr %t5594
  br label %case.end.4.5588
case.end.4.5588:
  br label %case.join.5578
case.default.5577:
  unreachable
case.join.5578:
  %t5595 = phi ptr [ %t5581, %case.end.3.5580 ], [ %t5589, %case.end.4.5588 ]
  %t5596 = getelementptr ptr, ptr %t4, i32 1
  %t5597 = load ptr, ptr %t5596
  call void @__free_recursive(ptr %t5597)
  %t5598 = getelementptr ptr, ptr %t4, i32 2
  %t5599 = load ptr, ptr %t5598
  call void @__free_recursive(ptr %t5599)
  %t5602 = inttoptr i64 53 to ptr
  %t5603 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5602, ptr %t5603
  %t5600 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5595, ptr %t5600
  call void @__inc_ref(ptr %t5481)
  %t5601 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t5481, ptr %t5601
  %t5604 = getelementptr ptr, ptr %t5571, i32 1
  store ptr %t4, ptr %t5604
  call void @__inc_ref(ptr %t5254)
  %t5605 = getelementptr ptr, ptr %t5571, i32 2
  store ptr %t5254, ptr %t5605
  call void @__free_recursive(ptr %t5481)
  call void @__free_recursive(ptr %t5479)
  call void @__free_recursive(ptr %t5477)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t5571, ptr %t3
  br label %tco.loop.0
tco.case.arm.46.5606:
  %t5607 = call ptr @__alloc(i64 24, i32 2)
  %t5608 = inttoptr i64 280 to ptr
  %t5609 = getelementptr ptr, ptr %t5607, i32 0
  store ptr %t5608, ptr %t5609
  %t5610 = getelementptr ptr, ptr %t5477, i32 1
  %t5611 = load ptr, ptr %t5610
  call void @__inc_ref(ptr %t5611)
  call void @__inc_ref(ptr %t5479)
  %t5612 = call ptr @v_addStats(ptr %t5611, ptr %t5479)
  %t5613 = getelementptr ptr, ptr %t4, i32 1
  %t5614 = load ptr, ptr %t5613
  call void @__free_recursive(ptr %t5614)
  %t5615 = getelementptr ptr, ptr %t4, i32 2
  %t5616 = load ptr, ptr %t5615
  call void @__free_recursive(ptr %t5616)
  %t5619 = inttoptr i64 53 to ptr
  %t5620 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5619, ptr %t5620
  %t5617 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5612, ptr %t5617
  call void @__inc_ref(ptr %t5481)
  %t5618 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t5481, ptr %t5618
  %t5621 = getelementptr ptr, ptr %t5607, i32 1
  store ptr %t4, ptr %t5621
  call void @__inc_ref(ptr %t5254)
  %t5622 = getelementptr ptr, ptr %t5607, i32 2
  store ptr %t5254, ptr %t5622
  call void @__free_recursive(ptr %t5481)
  call void @__free_recursive(ptr %t5479)
  call void @__free_recursive(ptr %t5477)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t5607, ptr %t3
  br label %tco.loop.0
tco.case.arm.47.5623:
  %t5624 = call ptr @__alloc(i64 24, i32 2)
  %t5625 = inttoptr i64 280 to ptr
  %t5626 = getelementptr ptr, ptr %t5624, i32 0
  store ptr %t5625, ptr %t5626
  %t5627 = call ptr @__alloc(i64 32, i32 3)
  %t5628 = inttoptr i64 98 to ptr
  %t5629 = getelementptr ptr, ptr %t5627, i32 0
  store ptr %t5628, ptr %t5629
  %t5630 = getelementptr ptr, ptr %t5477, i32 1
  %t5631 = load ptr, ptr %t5630
  call void @__inc_ref(ptr %t5631)
  %t5632 = getelementptr ptr, ptr %t5627, i32 1
  store ptr %t5631, ptr %t5632
  %t5633 = getelementptr ptr, ptr %t5477, i32 2
  %t5634 = load ptr, ptr %t5633
  call void @__inc_ref(ptr %t5634)
  %t5635 = getelementptr ptr, ptr %t5627, i32 2
  store ptr %t5634, ptr %t5635
  call void @__inc_ref(ptr %t5479)
  %t5636 = getelementptr ptr, ptr %t5627, i32 3
  store ptr %t5479, ptr %t5636
  %t5637 = getelementptr ptr, ptr %t5624, i32 1
  store ptr %t5627, ptr %t5637
  %t5638 = getelementptr ptr, ptr %t4, i32 1
  %t5639 = load ptr, ptr %t5638
  call void @__free_recursive(ptr %t5639)
  %t5640 = getelementptr ptr, ptr %t4, i32 2
  %t5641 = load ptr, ptr %t5640
  call void @__free_recursive(ptr %t5641)
  %t5644 = inttoptr i64 130 to ptr
  %t5645 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5644, ptr %t5645
  call void @__inc_ref(ptr %t5254)
  %t5642 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t5642
  call void @__inc_ref(ptr %t5481)
  %t5643 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t5481, ptr %t5643
  %t5646 = getelementptr ptr, ptr %t5624, i32 2
  store ptr %t4, ptr %t5646
  call void @__free_recursive(ptr %t5481)
  call void @__free_recursive(ptr %t5479)
  call void @__free_recursive(ptr %t5477)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t5624, ptr %t3
  br label %tco.loop.0
tco.case.arm.48.5647:
  %t5648 = call ptr @__alloc(i64 24, i32 2)
  %t5649 = inttoptr i64 280 to ptr
  %t5650 = getelementptr ptr, ptr %t5648, i32 0
  store ptr %t5649, ptr %t5650
  %t5651 = call ptr @__alloc(i64 24, i32 2)
  %t5652 = inttoptr i64 53 to ptr
  %t5653 = getelementptr ptr, ptr %t5651, i32 0
  store ptr %t5652, ptr %t5653
  %t5654 = call ptr @__alloc(i64 4, i32 0)
  store i32 1, ptr %t5654
  call void @__inc_ref(ptr %t5479)
  %t5655 = call ptr @__lengthUtf16CodeUnits(ptr %t5479)
  %t5656 = call ptr @__alloc(i64 4, i32 0)
  store i32 1, ptr %t5656
  %t5657 = call ptr @__addUInt32(ptr %t5655, ptr %t5656)
  %t5658 = getelementptr ptr, ptr %t5657, i32 0
  %t5659 = load ptr, ptr %t5658
  %t5660 = ptrtoint ptr %t5659 to i64
  switch i64 %t5660, label %case.default.5661 [ i64 3, label %case.arm.3.5663 i64 4, label %case.arm.4.5666 ]
case.arm.3.5663:
  %t5665 = call ptr @v_maxUInt32()
  br label %case.end.3.5664
case.end.3.5664:
  br label %case.join.5662
case.arm.4.5666:
  %t5668 = getelementptr ptr, ptr %t5657, i32 1
  %t5669 = load ptr, ptr %t5668
  call void @__inc_ref(ptr %t5669)
  call void @__inc_ref(ptr %t5669)
  call void @__free_recursive(ptr %t5669)
  br label %case.end.4.5667
case.end.4.5667:
  br label %case.join.5662
case.default.5661:
  unreachable
case.join.5662:
  %t5670 = phi ptr [ %t5665, %case.end.3.5664 ], [ %t5669, %case.end.4.5667 ]
  call void @__free_recursive(ptr %t5657)
  %t5671 = getelementptr ptr, ptr %t4, i32 1
  %t5672 = load ptr, ptr %t5671
  call void @__free_recursive(ptr %t5672)
  %t5673 = getelementptr ptr, ptr %t4, i32 2
  %t5674 = load ptr, ptr %t5673
  call void @__free_recursive(ptr %t5674)
  %t5677 = inttoptr i64 35 to ptr
  %t5678 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5677, ptr %t5678
  %t5675 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5654, ptr %t5675
  %t5676 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t5670, ptr %t5676
  %t5679 = getelementptr ptr, ptr %t5651, i32 1
  store ptr %t4, ptr %t5679
  call void @__inc_ref(ptr %t5481)
  %t5680 = getelementptr ptr, ptr %t5651, i32 2
  store ptr %t5481, ptr %t5680
  %t5681 = getelementptr ptr, ptr %t5648, i32 1
  store ptr %t5651, ptr %t5681
  call void @__inc_ref(ptr %t5254)
  %t5682 = getelementptr ptr, ptr %t5648, i32 2
  store ptr %t5254, ptr %t5682
  call void @__free_recursive(ptr %t5481)
  call void @__free_recursive(ptr %t5479)
  call void @__free_recursive(ptr %t5477)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t5648, ptr %t3
  br label %tco.loop.0
tco.case.arm.49.5683:
  %t5684 = call ptr @__alloc(i64 24, i32 2)
  %t5685 = inttoptr i64 280 to ptr
  %t5686 = getelementptr ptr, ptr %t5684, i32 0
  store ptr %t5685, ptr %t5686
  %t5687 = getelementptr ptr, ptr %t5479, i32 1
  %t5688 = load ptr, ptr %t5687
  call void @__inc_ref(ptr %t5688)
  %t5689 = getelementptr ptr, ptr %t4, i32 1
  %t5690 = load ptr, ptr %t5689
  call void @__free_recursive(ptr %t5690)
  %t5691 = getelementptr ptr, ptr %t4, i32 2
  %t5692 = load ptr, ptr %t5691
  call void @__free_recursive(ptr %t5692)
  %t5695 = inttoptr i64 53 to ptr
  %t5696 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5695, ptr %t5696
  %t5693 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5688, ptr %t5693
  call void @__inc_ref(ptr %t5481)
  %t5694 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t5481, ptr %t5694
  %t5697 = getelementptr ptr, ptr %t5684, i32 1
  store ptr %t4, ptr %t5697
  call void @__inc_ref(ptr %t5254)
  %t5698 = getelementptr ptr, ptr %t5684, i32 2
  store ptr %t5254, ptr %t5698
  call void @__free_recursive(ptr %t5481)
  call void @__free_recursive(ptr %t5479)
  call void @__free_recursive(ptr %t5477)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t5684, ptr %t3
  br label %tco.loop.0
tco.case.arm.50.5699:
  %t5700 = call ptr @__alloc(i64 24, i32 2)
  %t5701 = inttoptr i64 279 to ptr
  %t5702 = getelementptr ptr, ptr %t5700, i32 0
  store ptr %t5701, ptr %t5702
  call void @__inc_ref(ptr %t5254)
  %t5703 = getelementptr ptr, ptr %t5700, i32 1
  store ptr %t5254, ptr %t5703
  %t5704 = getelementptr ptr, ptr %t4, i32 1
  %t5705 = load ptr, ptr %t5704
  call void @__free_recursive(ptr %t5705)
  %t5706 = getelementptr ptr, ptr %t4, i32 2
  %t5707 = load ptr, ptr %t5706
  call void @__free_recursive(ptr %t5707)
  %t5710 = inttoptr i64 14 to ptr
  %t5711 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5710, ptr %t5711
  call void @__inc_ref(ptr %t5479)
  %t5708 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5479, ptr %t5708
  call void @__inc_ref(ptr %t5481)
  %t5709 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t5481, ptr %t5709
  %t5712 = getelementptr ptr, ptr %t5700, i32 2
  store ptr %t4, ptr %t5712
  call void @__free_recursive(ptr %t5481)
  call void @__free_recursive(ptr %t5479)
  call void @__free_recursive(ptr %t5477)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t5700, ptr %t3
  br label %tco.loop.0
tco.case.arm.51.5713:
  call void @__inc_ref(ptr %t5479)
  call void @__inc_ref(ptr %t5481)
  %t5714 = call ptr @v_addStats(ptr %t5479, ptr %t5481)
  %t5715 = getelementptr ptr, ptr %t4, i32 1
  %t5716 = load ptr, ptr %t5715
  call void @__free_recursive(ptr %t5716)
  %t5717 = getelementptr ptr, ptr %t4, i32 2
  %t5718 = load ptr, ptr %t5717
  call void @__free_recursive(ptr %t5718)
  %t5721 = inttoptr i64 279 to ptr
  %t5722 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5721, ptr %t5722
  call void @__inc_ref(ptr %t5254)
  %t5719 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t5719
  %t5720 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t5714, ptr %t5720
  call void @__free_recursive(ptr %t5481)
  call void @__free_recursive(ptr %t5479)
  call void @__free_recursive(ptr %t5477)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.52.5723:
  %t5724 = call ptr @__alloc(i64 32, i32 3)
  %t5725 = inttoptr i64 98 to ptr
  %t5726 = getelementptr ptr, ptr %t5724, i32 0
  store ptr %t5725, ptr %t5726
  %t5727 = getelementptr ptr, ptr %t5477, i32 1
  %t5728 = load ptr, ptr %t5727
  call void @__inc_ref(ptr %t5728)
  %t5729 = getelementptr ptr, ptr %t5724, i32 1
  store ptr %t5728, ptr %t5729
  call void @__inc_ref(ptr %t5479)
  %t5730 = getelementptr ptr, ptr %t5724, i32 2
  store ptr %t5479, ptr %t5730
  call void @__inc_ref(ptr %t5481)
  %t5731 = getelementptr ptr, ptr %t5724, i32 3
  store ptr %t5481, ptr %t5731
  %t5732 = getelementptr ptr, ptr %t4, i32 1
  %t5733 = load ptr, ptr %t5732
  call void @__free_recursive(ptr %t5733)
  %t5735 = inttoptr i64 280 to ptr
  %t5736 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5735, ptr %t5736
  %t5734 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5724, ptr %t5734
  call void @__free_recursive(ptr %t5481)
  call void @__free_recursive(ptr %t5479)
  call void @__free_recursive(ptr %t5477)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.5485:
  unreachable
tco.case.arm.55.5737:
  %t5738 = call ptr @__alloc(i64 24, i32 2)
  %t5739 = inttoptr i64 280 to ptr
  %t5740 = getelementptr ptr, ptr %t5738, i32 0
  store ptr %t5739, ptr %t5740
  %t5741 = getelementptr ptr, ptr %t5252, i32 1
  %t5742 = load ptr, ptr %t5741
  call void @__inc_ref(ptr %t5742)
  %t5743 = getelementptr ptr, ptr %t5252, i32 2
  %t5744 = load ptr, ptr %t5743
  call void @__inc_ref(ptr %t5744)
  %t5745 = getelementptr ptr, ptr %t4, i32 1
  %t5746 = load ptr, ptr %t5745
  call void @__free_recursive(ptr %t5746)
  %t5747 = getelementptr ptr, ptr %t4, i32 2
  %t5748 = load ptr, ptr %t5747
  call void @__free_recursive(ptr %t5748)
  %t5751 = inttoptr i64 53 to ptr
  %t5752 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5751, ptr %t5752
  %t5749 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5742, ptr %t5749
  %t5750 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t5744, ptr %t5750
  %t5753 = getelementptr ptr, ptr %t5738, i32 1
  store ptr %t4, ptr %t5753
  %t5754 = call ptr @__alloc(i64 16, i32 1)
  %t5755 = inttoptr i64 131 to ptr
  %t5756 = getelementptr ptr, ptr %t5754, i32 0
  store ptr %t5755, ptr %t5756
  call void @__inc_ref(ptr %t5254)
  %t5757 = getelementptr ptr, ptr %t5754, i32 1
  store ptr %t5254, ptr %t5757
  %t5758 = getelementptr ptr, ptr %t5738, i32 2
  store ptr %t5754, ptr %t5758
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t5738, ptr %t3
  br label %tco.loop.0
tco.case.arm.56.5759:
  %t5760 = call ptr @__alloc(i64 24, i32 2)
  %t5761 = inttoptr i64 280 to ptr
  %t5762 = getelementptr ptr, ptr %t5760, i32 0
  store ptr %t5761, ptr %t5762
  %t5763 = getelementptr ptr, ptr %t5252, i32 1
  %t5764 = load ptr, ptr %t5763
  call void @__inc_ref(ptr %t5764)
  %t5765 = getelementptr ptr, ptr %t5252, i32 2
  %t5766 = load ptr, ptr %t5765
  call void @__inc_ref(ptr %t5766)
  %t5767 = getelementptr ptr, ptr %t4, i32 1
  %t5768 = load ptr, ptr %t5767
  call void @__free_recursive(ptr %t5768)
  %t5769 = getelementptr ptr, ptr %t4, i32 2
  %t5770 = load ptr, ptr %t5769
  call void @__free_recursive(ptr %t5770)
  %t5773 = inttoptr i64 53 to ptr
  %t5774 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5773, ptr %t5774
  %t5771 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5764, ptr %t5771
  %t5772 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t5766, ptr %t5772
  %t5775 = getelementptr ptr, ptr %t5760, i32 1
  store ptr %t4, ptr %t5775
  %t5776 = call ptr @__alloc(i64 16, i32 1)
  %t5777 = inttoptr i64 132 to ptr
  %t5778 = getelementptr ptr, ptr %t5776, i32 0
  store ptr %t5777, ptr %t5778
  call void @__inc_ref(ptr %t5254)
  %t5779 = getelementptr ptr, ptr %t5776, i32 1
  store ptr %t5254, ptr %t5779
  %t5780 = getelementptr ptr, ptr %t5760, i32 2
  store ptr %t5776, ptr %t5780
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t5760, ptr %t3
  br label %tco.loop.0
tco.case.arm.57.5781:
  %t5782 = call ptr @__alloc(i64 24, i32 2)
  %t5783 = inttoptr i64 280 to ptr
  %t5784 = getelementptr ptr, ptr %t5782, i32 0
  store ptr %t5783, ptr %t5784
  %t5785 = getelementptr ptr, ptr %t5252, i32 1
  %t5786 = load ptr, ptr %t5785
  call void @__inc_ref(ptr %t5786)
  %t5787 = getelementptr ptr, ptr %t5252, i32 2
  %t5788 = load ptr, ptr %t5787
  call void @__inc_ref(ptr %t5788)
  %t5789 = getelementptr ptr, ptr %t4, i32 1
  %t5790 = load ptr, ptr %t5789
  call void @__free_recursive(ptr %t5790)
  %t5791 = getelementptr ptr, ptr %t4, i32 2
  %t5792 = load ptr, ptr %t5791
  call void @__free_recursive(ptr %t5792)
  %t5795 = inttoptr i64 53 to ptr
  %t5796 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5795, ptr %t5796
  %t5793 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5786, ptr %t5793
  %t5794 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t5788, ptr %t5794
  %t5797 = getelementptr ptr, ptr %t5782, i32 1
  store ptr %t4, ptr %t5797
  %t5798 = call ptr @__alloc(i64 16, i32 1)
  %t5799 = inttoptr i64 133 to ptr
  %t5800 = getelementptr ptr, ptr %t5798, i32 0
  store ptr %t5799, ptr %t5800
  call void @__inc_ref(ptr %t5254)
  %t5801 = getelementptr ptr, ptr %t5798, i32 1
  store ptr %t5254, ptr %t5801
  %t5802 = getelementptr ptr, ptr %t5782, i32 2
  store ptr %t5798, ptr %t5802
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t5782, ptr %t3
  br label %tco.loop.0
tco.case.arm.58.5803:
  %t5804 = getelementptr ptr, ptr %t5252, i32 1
  %t5805 = load ptr, ptr %t5804
  call void @__inc_ref(ptr %t5805)
  %t5806 = getelementptr ptr, ptr %t5252, i32 2
  %t5807 = load ptr, ptr %t5806
  call void @__inc_ref(ptr %t5807)
  %t5808 = getelementptr ptr, ptr %t5252, i32 3
  %t5809 = load ptr, ptr %t5808
  call void @__inc_ref(ptr %t5809)
  %t5810 = getelementptr ptr, ptr %t5252, i32 4
  %t5811 = load ptr, ptr %t5810
  call void @__inc_ref(ptr %t5811)
  %t5812 = getelementptr ptr, ptr %t5252, i32 5
  %t5813 = load ptr, ptr %t5812
  call void @__inc_ref(ptr %t5813)
  %t5814 = getelementptr ptr, ptr %t5252, i32 6
  %t5815 = load ptr, ptr %t5814
  call void @__inc_ref(ptr %t5815)
  call void @__inc_ref(ptr %t5805)
  %t5816 = getelementptr ptr, ptr %t5815, i32 2
  %t5817 = load ptr, ptr %t5816
  call void @__inc_ref(ptr %t5817)
  %t5818 = call ptr @__subUInt32(ptr %t5805, ptr %t5817)
  %t5819 = getelementptr ptr, ptr %t5818, i32 0
  %t5820 = load ptr, ptr %t5819
  %t5821 = ptrtoint ptr %t5820 to i64
  switch i64 %t5821, label %tco.case.default.5822 [ i64 3, label %tco.case.arm.3.5823 i64 4, label %tco.case.arm.4.5850 ]
tco.case.arm.3.5823:
  call void @__free_recursive(ptr %t5818)
  %t5824 = call ptr @__alloc(i64 24, i32 2)
  %t5825 = inttoptr i64 279 to ptr
  %t5826 = getelementptr ptr, ptr %t5824, i32 0
  store ptr %t5825, ptr %t5826
  call void @__inc_ref(ptr %t5254)
  %t5827 = getelementptr ptr, ptr %t5824, i32 1
  store ptr %t5254, ptr %t5827
  %t5828 = call ptr @__alloc(i64 32, i32 3)
  %t5829 = inttoptr i64 34 to ptr
  %t5830 = getelementptr ptr, ptr %t5828, i32 0
  store ptr %t5829, ptr %t5830
  %t5831 = call ptr @__alloc(i64 8, i32 0)
  %t5832 = inttoptr i64 11 to ptr
  %t5833 = getelementptr ptr, ptr %t5831, i32 0
  store ptr %t5832, ptr %t5833
  %t5834 = getelementptr ptr, ptr %t5828, i32 1
  store ptr %t5831, ptr %t5834
  call void @__inc_ref(ptr %t5807)
  %t5835 = getelementptr ptr, ptr %t5828, i32 2
  store ptr %t5807, ptr %t5835
  %t5836 = call ptr @__alloc(i64 16, i32 1)
  %t5837 = inttoptr i64 12 to ptr
  %t5838 = getelementptr ptr, ptr %t5836, i32 0
  store ptr %t5837, ptr %t5838
  %t5839 = getelementptr ptr, ptr %t4, i32 1
  %t5840 = load ptr, ptr %t5839
  call void @__free_recursive(ptr %t5840)
  %t5841 = getelementptr ptr, ptr %t4, i32 2
  %t5842 = load ptr, ptr %t5841
  call void @__free_recursive(ptr %t5842)
  %t5845 = inttoptr i64 25 to ptr
  %t5846 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5845, ptr %t5846
  call void @__inc_ref(ptr %t5809)
  %t5843 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5809, ptr %t5843
  call void @__inc_ref(ptr %t5811)
  %t5844 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t5811, ptr %t5844
  %t5847 = getelementptr ptr, ptr %t5836, i32 1
  store ptr %t4, ptr %t5847
  %t5848 = getelementptr ptr, ptr %t5828, i32 3
  store ptr %t5836, ptr %t5848
  %t5849 = getelementptr ptr, ptr %t5824, i32 2
  store ptr %t5828, ptr %t5849
  call void @__free_recursive(ptr %t5815)
  call void @__free_recursive(ptr %t5813)
  call void @__free_recursive(ptr %t5811)
  call void @__free_recursive(ptr %t5809)
  call void @__free_recursive(ptr %t5807)
  call void @__free_recursive(ptr %t5805)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t5824, ptr %t3
  br label %tco.loop.0
tco.case.arm.4.5850:
  call void @__free_recursive(ptr %t5818)
  %t5851 = call ptr @__alloc(i64 24, i32 2)
  %t5852 = inttoptr i64 280 to ptr
  %t5853 = getelementptr ptr, ptr %t5851, i32 0
  store ptr %t5852, ptr %t5853
  %t5854 = getelementptr ptr, ptr %t4, i32 1
  %t5855 = load ptr, ptr %t5854
  call void @__free_recursive(ptr %t5855)
  %t5856 = getelementptr ptr, ptr %t4, i32 2
  %t5857 = load ptr, ptr %t5856
  call void @__free_recursive(ptr %t5857)
  %t5860 = inttoptr i64 101 to ptr
  %t5861 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5860, ptr %t5861
  call void @__inc_ref(ptr %t5813)
  %t5858 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5813, ptr %t5858
  call void @__inc_ref(ptr %t5809)
  %t5859 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t5809, ptr %t5859
  %t5862 = getelementptr ptr, ptr %t5851, i32 1
  store ptr %t4, ptr %t5862
  %t5863 = call ptr @__alloc(i64 64, i32 7)
  %t5864 = inttoptr i64 134 to ptr
  %t5865 = getelementptr ptr, ptr %t5863, i32 0
  store ptr %t5864, ptr %t5865
  call void @__inc_ref(ptr %t5254)
  %t5866 = getelementptr ptr, ptr %t5863, i32 1
  store ptr %t5254, ptr %t5866
  call void @__inc_ref(ptr %t5805)
  %t5867 = getelementptr ptr, ptr %t5863, i32 2
  store ptr %t5805, ptr %t5867
  call void @__inc_ref(ptr %t5807)
  %t5868 = getelementptr ptr, ptr %t5863, i32 3
  store ptr %t5807, ptr %t5868
  call void @__inc_ref(ptr %t5809)
  %t5869 = getelementptr ptr, ptr %t5863, i32 4
  store ptr %t5809, ptr %t5869
  call void @__inc_ref(ptr %t5811)
  %t5870 = getelementptr ptr, ptr %t5863, i32 5
  store ptr %t5811, ptr %t5870
  call void @__inc_ref(ptr %t5813)
  %t5871 = getelementptr ptr, ptr %t5863, i32 6
  store ptr %t5813, ptr %t5871
  call void @__inc_ref(ptr %t5815)
  %t5872 = getelementptr ptr, ptr %t5863, i32 7
  store ptr %t5815, ptr %t5872
  %t5873 = getelementptr ptr, ptr %t5851, i32 2
  store ptr %t5863, ptr %t5873
  call void @__free_recursive(ptr %t5815)
  call void @__free_recursive(ptr %t5813)
  call void @__free_recursive(ptr %t5811)
  call void @__free_recursive(ptr %t5809)
  call void @__free_recursive(ptr %t5807)
  call void @__free_recursive(ptr %t5805)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t5851, ptr %t3
  br label %tco.loop.0
tco.case.default.5822:
  unreachable
tco.case.arm.59.5874:
  %t5875 = getelementptr ptr, ptr %t5252, i32 1
  %t5876 = load ptr, ptr %t5875
  call void @__inc_ref(ptr %t5876)
  %t5877 = getelementptr ptr, ptr %t5252, i32 2
  %t5878 = load ptr, ptr %t5877
  call void @__inc_ref(ptr %t5878)
  %t5879 = getelementptr ptr, ptr %t5252, i32 3
  %t5880 = load ptr, ptr %t5879
  call void @__inc_ref(ptr %t5880)
  %t5881 = getelementptr ptr, ptr %t5252, i32 4
  %t5882 = load ptr, ptr %t5881
  call void @__inc_ref(ptr %t5882)
  %t5883 = getelementptr ptr, ptr %t5252, i32 5
  %t5884 = load ptr, ptr %t5883
  call void @__inc_ref(ptr %t5884)
  %t5885 = getelementptr ptr, ptr %t5252, i32 6
  %t5886 = load ptr, ptr %t5885
  call void @__inc_ref(ptr %t5886)
  call void @__inc_ref(ptr %t5876)
  %t5887 = getelementptr ptr, ptr %t5886, i32 1
  %t5888 = load ptr, ptr %t5887
  call void @__inc_ref(ptr %t5888)
  %t5889 = call ptr @__subUInt32(ptr %t5876, ptr %t5888)
  %t5890 = getelementptr ptr, ptr %t5889, i32 0
  %t5891 = load ptr, ptr %t5890
  %t5892 = ptrtoint ptr %t5891 to i64
  switch i64 %t5892, label %tco.case.default.5893 [ i64 3, label %tco.case.arm.3.5894 i64 4, label %tco.case.arm.4.5921 ]
tco.case.arm.3.5894:
  call void @__free_recursive(ptr %t5889)
  %t5895 = call ptr @__alloc(i64 24, i32 2)
  %t5896 = inttoptr i64 279 to ptr
  %t5897 = getelementptr ptr, ptr %t5895, i32 0
  store ptr %t5896, ptr %t5897
  call void @__inc_ref(ptr %t5254)
  %t5898 = getelementptr ptr, ptr %t5895, i32 1
  store ptr %t5254, ptr %t5898
  %t5899 = call ptr @__alloc(i64 32, i32 3)
  %t5900 = inttoptr i64 34 to ptr
  %t5901 = getelementptr ptr, ptr %t5899, i32 0
  store ptr %t5900, ptr %t5901
  %t5902 = call ptr @__alloc(i64 8, i32 0)
  %t5903 = inttoptr i64 11 to ptr
  %t5904 = getelementptr ptr, ptr %t5902, i32 0
  store ptr %t5903, ptr %t5904
  %t5905 = getelementptr ptr, ptr %t5899, i32 1
  store ptr %t5902, ptr %t5905
  call void @__inc_ref(ptr %t5878)
  %t5906 = getelementptr ptr, ptr %t5899, i32 2
  store ptr %t5878, ptr %t5906
  %t5907 = call ptr @__alloc(i64 16, i32 1)
  %t5908 = inttoptr i64 12 to ptr
  %t5909 = getelementptr ptr, ptr %t5907, i32 0
  store ptr %t5908, ptr %t5909
  %t5910 = getelementptr ptr, ptr %t4, i32 1
  %t5911 = load ptr, ptr %t5910
  call void @__free_recursive(ptr %t5911)
  %t5912 = getelementptr ptr, ptr %t4, i32 2
  %t5913 = load ptr, ptr %t5912
  call void @__free_recursive(ptr %t5913)
  %t5916 = inttoptr i64 25 to ptr
  %t5917 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5916, ptr %t5917
  call void @__inc_ref(ptr %t5880)
  %t5914 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5880, ptr %t5914
  call void @__inc_ref(ptr %t5882)
  %t5915 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t5882, ptr %t5915
  %t5918 = getelementptr ptr, ptr %t5907, i32 1
  store ptr %t4, ptr %t5918
  %t5919 = getelementptr ptr, ptr %t5899, i32 3
  store ptr %t5907, ptr %t5919
  %t5920 = getelementptr ptr, ptr %t5895, i32 2
  store ptr %t5899, ptr %t5920
  call void @__free_recursive(ptr %t5886)
  call void @__free_recursive(ptr %t5884)
  call void @__free_recursive(ptr %t5882)
  call void @__free_recursive(ptr %t5880)
  call void @__free_recursive(ptr %t5878)
  call void @__free_recursive(ptr %t5876)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t5895, ptr %t3
  br label %tco.loop.0
tco.case.arm.4.5921:
  call void @__free_recursive(ptr %t5889)
  %t5922 = call ptr @__alloc(i64 24, i32 2)
  %t5923 = inttoptr i64 280 to ptr
  %t5924 = getelementptr ptr, ptr %t5922, i32 0
  store ptr %t5923, ptr %t5924
  %t5925 = getelementptr ptr, ptr %t4, i32 1
  %t5926 = load ptr, ptr %t5925
  call void @__free_recursive(ptr %t5926)
  %t5927 = getelementptr ptr, ptr %t4, i32 2
  %t5928 = load ptr, ptr %t5927
  call void @__free_recursive(ptr %t5928)
  %t5931 = inttoptr i64 101 to ptr
  %t5932 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5931, ptr %t5932
  call void @__inc_ref(ptr %t5884)
  %t5929 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5884, ptr %t5929
  call void @__inc_ref(ptr %t5880)
  %t5930 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t5880, ptr %t5930
  %t5933 = getelementptr ptr, ptr %t5922, i32 1
  store ptr %t4, ptr %t5933
  %t5934 = call ptr @__alloc(i64 64, i32 7)
  %t5935 = inttoptr i64 136 to ptr
  %t5936 = getelementptr ptr, ptr %t5934, i32 0
  store ptr %t5935, ptr %t5936
  call void @__inc_ref(ptr %t5254)
  %t5937 = getelementptr ptr, ptr %t5934, i32 1
  store ptr %t5254, ptr %t5937
  call void @__inc_ref(ptr %t5876)
  %t5938 = getelementptr ptr, ptr %t5934, i32 2
  store ptr %t5876, ptr %t5938
  call void @__inc_ref(ptr %t5878)
  %t5939 = getelementptr ptr, ptr %t5934, i32 3
  store ptr %t5878, ptr %t5939
  call void @__inc_ref(ptr %t5880)
  %t5940 = getelementptr ptr, ptr %t5934, i32 4
  store ptr %t5880, ptr %t5940
  call void @__inc_ref(ptr %t5882)
  %t5941 = getelementptr ptr, ptr %t5934, i32 5
  store ptr %t5882, ptr %t5941
  call void @__inc_ref(ptr %t5884)
  %t5942 = getelementptr ptr, ptr %t5934, i32 6
  store ptr %t5884, ptr %t5942
  call void @__inc_ref(ptr %t5886)
  %t5943 = getelementptr ptr, ptr %t5934, i32 7
  store ptr %t5886, ptr %t5943
  %t5944 = getelementptr ptr, ptr %t5922, i32 2
  store ptr %t5934, ptr %t5944
  call void @__free_recursive(ptr %t5886)
  call void @__free_recursive(ptr %t5884)
  call void @__free_recursive(ptr %t5882)
  call void @__free_recursive(ptr %t5880)
  call void @__free_recursive(ptr %t5878)
  call void @__free_recursive(ptr %t5876)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t5922, ptr %t3
  br label %tco.loop.0
tco.case.default.5893:
  unreachable
tco.case.arm.60.5945:
  %t5946 = getelementptr ptr, ptr %t5252, i32 1
  %t5947 = load ptr, ptr %t5946
  call void @__inc_ref(ptr %t5947)
  %t5948 = getelementptr ptr, ptr %t5252, i32 2
  %t5949 = load ptr, ptr %t5948
  call void @__inc_ref(ptr %t5949)
  %t5950 = getelementptr ptr, ptr %t5252, i32 3
  %t5951 = load ptr, ptr %t5950
  call void @__inc_ref(ptr %t5951)
  %t5952 = getelementptr ptr, ptr %t5252, i32 4
  %t5953 = load ptr, ptr %t5952
  call void @__inc_ref(ptr %t5953)
  %t5954 = getelementptr ptr, ptr %t5252, i32 5
  %t5955 = load ptr, ptr %t5954
  call void @__inc_ref(ptr %t5955)
  %t5956 = getelementptr ptr, ptr %t5252, i32 6
  %t5957 = load ptr, ptr %t5956
  call void @__inc_ref(ptr %t5957)
  %t5958 = getelementptr ptr, ptr %t5252, i32 7
  %t5959 = load ptr, ptr %t5958
  call void @__inc_ref(ptr %t5959)
  call void @__inc_ref(ptr %t5947)
  %t5960 = getelementptr ptr, ptr %t5959, i32 2
  %t5961 = load ptr, ptr %t5960
  call void @__inc_ref(ptr %t5961)
  %t5962 = call ptr @__subUInt32(ptr %t5947, ptr %t5961)
  %t5963 = getelementptr ptr, ptr %t5962, i32 0
  %t5964 = load ptr, ptr %t5963
  %t5965 = ptrtoint ptr %t5964 to i64
  switch i64 %t5965, label %tco.case.default.5966 [ i64 3, label %tco.case.arm.3.5967 i64 4, label %tco.case.arm.4.5999 ]
tco.case.arm.3.5967:
  call void @__free_recursive(ptr %t5962)
  %t5968 = call ptr @__alloc(i64 24, i32 2)
  %t5969 = inttoptr i64 279 to ptr
  %t5970 = getelementptr ptr, ptr %t5968, i32 0
  store ptr %t5969, ptr %t5970
  call void @__inc_ref(ptr %t5254)
  %t5971 = getelementptr ptr, ptr %t5968, i32 1
  store ptr %t5254, ptr %t5971
  %t5972 = call ptr @__alloc(i64 32, i32 3)
  %t5973 = inttoptr i64 34 to ptr
  %t5974 = getelementptr ptr, ptr %t5972, i32 0
  store ptr %t5973, ptr %t5974
  %t5975 = call ptr @__alloc(i64 16, i32 1)
  %t5976 = inttoptr i64 12 to ptr
  %t5977 = getelementptr ptr, ptr %t5975, i32 0
  store ptr %t5976, ptr %t5977
  %t5978 = call ptr @__alloc(i64 16, i32 1)
  %t5979 = inttoptr i64 24 to ptr
  %t5980 = getelementptr ptr, ptr %t5978, i32 0
  store ptr %t5979, ptr %t5980
  call void @__inc_ref(ptr %t5949)
  %t5981 = getelementptr ptr, ptr %t5978, i32 1
  store ptr %t5949, ptr %t5981
  %t5982 = getelementptr ptr, ptr %t5975, i32 1
  store ptr %t5978, ptr %t5982
  %t5983 = getelementptr ptr, ptr %t5972, i32 1
  store ptr %t5975, ptr %t5983
  call void @__inc_ref(ptr %t5951)
  %t5984 = getelementptr ptr, ptr %t5972, i32 2
  store ptr %t5951, ptr %t5984
  %t5985 = call ptr @__alloc(i64 16, i32 1)
  %t5986 = inttoptr i64 12 to ptr
  %t5987 = getelementptr ptr, ptr %t5985, i32 0
  store ptr %t5986, ptr %t5987
  %t5988 = getelementptr ptr, ptr %t4, i32 1
  %t5989 = load ptr, ptr %t5988
  call void @__free_recursive(ptr %t5989)
  %t5990 = getelementptr ptr, ptr %t4, i32 2
  %t5991 = load ptr, ptr %t5990
  call void @__free_recursive(ptr %t5991)
  %t5994 = inttoptr i64 25 to ptr
  %t5995 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5994, ptr %t5995
  call void @__inc_ref(ptr %t5953)
  %t5992 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5953, ptr %t5992
  call void @__inc_ref(ptr %t5955)
  %t5993 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t5955, ptr %t5993
  %t5996 = getelementptr ptr, ptr %t5985, i32 1
  store ptr %t4, ptr %t5996
  %t5997 = getelementptr ptr, ptr %t5972, i32 3
  store ptr %t5985, ptr %t5997
  %t5998 = getelementptr ptr, ptr %t5968, i32 2
  store ptr %t5972, ptr %t5998
  call void @__free_recursive(ptr %t5959)
  call void @__free_recursive(ptr %t5957)
  call void @__free_recursive(ptr %t5955)
  call void @__free_recursive(ptr %t5953)
  call void @__free_recursive(ptr %t5951)
  call void @__free_recursive(ptr %t5949)
  call void @__free_recursive(ptr %t5947)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t5968, ptr %t3
  br label %tco.loop.0
tco.case.arm.4.5999:
  call void @__free_recursive(ptr %t5962)
  %t6000 = call ptr @__alloc(i64 24, i32 2)
  %t6001 = inttoptr i64 280 to ptr
  %t6002 = getelementptr ptr, ptr %t6000, i32 0
  store ptr %t6001, ptr %t6002
  %t6003 = getelementptr ptr, ptr %t4, i32 1
  %t6004 = load ptr, ptr %t6003
  call void @__free_recursive(ptr %t6004)
  %t6005 = getelementptr ptr, ptr %t4, i32 2
  %t6006 = load ptr, ptr %t6005
  call void @__free_recursive(ptr %t6006)
  %t6009 = inttoptr i64 101 to ptr
  %t6010 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t6009, ptr %t6010
  call void @__inc_ref(ptr %t5957)
  %t6007 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5957, ptr %t6007
  call void @__inc_ref(ptr %t5953)
  %t6008 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t5953, ptr %t6008
  %t6011 = getelementptr ptr, ptr %t6000, i32 1
  store ptr %t4, ptr %t6011
  %t6012 = call ptr @__alloc(i64 72, i32 8)
  %t6013 = inttoptr i64 138 to ptr
  %t6014 = getelementptr ptr, ptr %t6012, i32 0
  store ptr %t6013, ptr %t6014
  call void @__inc_ref(ptr %t5254)
  %t6015 = getelementptr ptr, ptr %t6012, i32 1
  store ptr %t5254, ptr %t6015
  call void @__inc_ref(ptr %t5947)
  %t6016 = getelementptr ptr, ptr %t6012, i32 2
  store ptr %t5947, ptr %t6016
  call void @__inc_ref(ptr %t5949)
  %t6017 = getelementptr ptr, ptr %t6012, i32 3
  store ptr %t5949, ptr %t6017
  call void @__inc_ref(ptr %t5951)
  %t6018 = getelementptr ptr, ptr %t6012, i32 4
  store ptr %t5951, ptr %t6018
  call void @__inc_ref(ptr %t5953)
  %t6019 = getelementptr ptr, ptr %t6012, i32 5
  store ptr %t5953, ptr %t6019
  call void @__inc_ref(ptr %t5955)
  %t6020 = getelementptr ptr, ptr %t6012, i32 6
  store ptr %t5955, ptr %t6020
  call void @__inc_ref(ptr %t5957)
  %t6021 = getelementptr ptr, ptr %t6012, i32 7
  store ptr %t5957, ptr %t6021
  call void @__inc_ref(ptr %t5959)
  %t6022 = getelementptr ptr, ptr %t6012, i32 8
  store ptr %t5959, ptr %t6022
  %t6023 = getelementptr ptr, ptr %t6000, i32 2
  store ptr %t6012, ptr %t6023
  call void @__free_recursive(ptr %t5959)
  call void @__free_recursive(ptr %t5957)
  call void @__free_recursive(ptr %t5955)
  call void @__free_recursive(ptr %t5953)
  call void @__free_recursive(ptr %t5951)
  call void @__free_recursive(ptr %t5949)
  call void @__free_recursive(ptr %t5947)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t6000, ptr %t3
  br label %tco.loop.0
tco.case.default.5966:
  unreachable
tco.case.arm.61.6024:
  %t6025 = getelementptr ptr, ptr %t5252, i32 1
  %t6026 = load ptr, ptr %t6025
  call void @__inc_ref(ptr %t6026)
  %t6027 = getelementptr ptr, ptr %t5252, i32 2
  %t6028 = load ptr, ptr %t6027
  call void @__inc_ref(ptr %t6028)
  %t6029 = getelementptr ptr, ptr %t5252, i32 3
  %t6030 = load ptr, ptr %t6029
  call void @__inc_ref(ptr %t6030)
  %t6031 = getelementptr ptr, ptr %t5252, i32 4
  %t6032 = load ptr, ptr %t6031
  call void @__inc_ref(ptr %t6032)
  %t6033 = getelementptr ptr, ptr %t5252, i32 5
  %t6034 = load ptr, ptr %t6033
  call void @__inc_ref(ptr %t6034)
  %t6035 = getelementptr ptr, ptr %t5252, i32 6
  %t6036 = load ptr, ptr %t6035
  call void @__inc_ref(ptr %t6036)
  %t6037 = getelementptr ptr, ptr %t5252, i32 7
  %t6038 = load ptr, ptr %t6037
  call void @__inc_ref(ptr %t6038)
  call void @__inc_ref(ptr %t6026)
  %t6039 = getelementptr ptr, ptr %t6038, i32 1
  %t6040 = load ptr, ptr %t6039
  call void @__inc_ref(ptr %t6040)
  %t6041 = call ptr @__subUInt32(ptr %t6026, ptr %t6040)
  %t6042 = getelementptr ptr, ptr %t6041, i32 0
  %t6043 = load ptr, ptr %t6042
  %t6044 = ptrtoint ptr %t6043 to i64
  switch i64 %t6044, label %tco.case.default.6045 [ i64 3, label %tco.case.arm.3.6046 i64 4, label %tco.case.arm.4.6078 ]
tco.case.arm.3.6046:
  call void @__free_recursive(ptr %t6041)
  %t6047 = call ptr @__alloc(i64 24, i32 2)
  %t6048 = inttoptr i64 279 to ptr
  %t6049 = getelementptr ptr, ptr %t6047, i32 0
  store ptr %t6048, ptr %t6049
  call void @__inc_ref(ptr %t5254)
  %t6050 = getelementptr ptr, ptr %t6047, i32 1
  store ptr %t5254, ptr %t6050
  %t6051 = call ptr @__alloc(i64 32, i32 3)
  %t6052 = inttoptr i64 34 to ptr
  %t6053 = getelementptr ptr, ptr %t6051, i32 0
  store ptr %t6052, ptr %t6053
  %t6054 = call ptr @__alloc(i64 16, i32 1)
  %t6055 = inttoptr i64 12 to ptr
  %t6056 = getelementptr ptr, ptr %t6054, i32 0
  store ptr %t6055, ptr %t6056
  %t6057 = call ptr @__alloc(i64 16, i32 1)
  %t6058 = inttoptr i64 24 to ptr
  %t6059 = getelementptr ptr, ptr %t6057, i32 0
  store ptr %t6058, ptr %t6059
  call void @__inc_ref(ptr %t6028)
  %t6060 = getelementptr ptr, ptr %t6057, i32 1
  store ptr %t6028, ptr %t6060
  %t6061 = getelementptr ptr, ptr %t6054, i32 1
  store ptr %t6057, ptr %t6061
  %t6062 = getelementptr ptr, ptr %t6051, i32 1
  store ptr %t6054, ptr %t6062
  call void @__inc_ref(ptr %t6030)
  %t6063 = getelementptr ptr, ptr %t6051, i32 2
  store ptr %t6030, ptr %t6063
  %t6064 = call ptr @__alloc(i64 16, i32 1)
  %t6065 = inttoptr i64 12 to ptr
  %t6066 = getelementptr ptr, ptr %t6064, i32 0
  store ptr %t6065, ptr %t6066
  %t6067 = getelementptr ptr, ptr %t4, i32 1
  %t6068 = load ptr, ptr %t6067
  call void @__free_recursive(ptr %t6068)
  %t6069 = getelementptr ptr, ptr %t4, i32 2
  %t6070 = load ptr, ptr %t6069
  call void @__free_recursive(ptr %t6070)
  %t6073 = inttoptr i64 25 to ptr
  %t6074 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t6073, ptr %t6074
  call void @__inc_ref(ptr %t6032)
  %t6071 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t6032, ptr %t6071
  call void @__inc_ref(ptr %t6034)
  %t6072 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t6034, ptr %t6072
  %t6075 = getelementptr ptr, ptr %t6064, i32 1
  store ptr %t4, ptr %t6075
  %t6076 = getelementptr ptr, ptr %t6051, i32 3
  store ptr %t6064, ptr %t6076
  %t6077 = getelementptr ptr, ptr %t6047, i32 2
  store ptr %t6051, ptr %t6077
  call void @__free_recursive(ptr %t6038)
  call void @__free_recursive(ptr %t6036)
  call void @__free_recursive(ptr %t6034)
  call void @__free_recursive(ptr %t6032)
  call void @__free_recursive(ptr %t6030)
  call void @__free_recursive(ptr %t6028)
  call void @__free_recursive(ptr %t6026)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t6047, ptr %t3
  br label %tco.loop.0
tco.case.arm.4.6078:
  call void @__free_recursive(ptr %t6041)
  %t6079 = call ptr @__alloc(i64 24, i32 2)
  %t6080 = inttoptr i64 280 to ptr
  %t6081 = getelementptr ptr, ptr %t6079, i32 0
  store ptr %t6080, ptr %t6081
  %t6082 = getelementptr ptr, ptr %t4, i32 1
  %t6083 = load ptr, ptr %t6082
  call void @__free_recursive(ptr %t6083)
  %t6084 = getelementptr ptr, ptr %t4, i32 2
  %t6085 = load ptr, ptr %t6084
  call void @__free_recursive(ptr %t6085)
  %t6088 = inttoptr i64 101 to ptr
  %t6089 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t6088, ptr %t6089
  call void @__inc_ref(ptr %t6036)
  %t6086 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t6036, ptr %t6086
  call void @__inc_ref(ptr %t6032)
  %t6087 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t6032, ptr %t6087
  %t6090 = getelementptr ptr, ptr %t6079, i32 1
  store ptr %t4, ptr %t6090
  %t6091 = call ptr @__alloc(i64 72, i32 8)
  %t6092 = inttoptr i64 140 to ptr
  %t6093 = getelementptr ptr, ptr %t6091, i32 0
  store ptr %t6092, ptr %t6093
  call void @__inc_ref(ptr %t5254)
  %t6094 = getelementptr ptr, ptr %t6091, i32 1
  store ptr %t5254, ptr %t6094
  call void @__inc_ref(ptr %t6026)
  %t6095 = getelementptr ptr, ptr %t6091, i32 2
  store ptr %t6026, ptr %t6095
  call void @__inc_ref(ptr %t6028)
  %t6096 = getelementptr ptr, ptr %t6091, i32 3
  store ptr %t6028, ptr %t6096
  call void @__inc_ref(ptr %t6030)
  %t6097 = getelementptr ptr, ptr %t6091, i32 4
  store ptr %t6030, ptr %t6097
  call void @__inc_ref(ptr %t6032)
  %t6098 = getelementptr ptr, ptr %t6091, i32 5
  store ptr %t6032, ptr %t6098
  call void @__inc_ref(ptr %t6034)
  %t6099 = getelementptr ptr, ptr %t6091, i32 6
  store ptr %t6034, ptr %t6099
  call void @__inc_ref(ptr %t6036)
  %t6100 = getelementptr ptr, ptr %t6091, i32 7
  store ptr %t6036, ptr %t6100
  call void @__inc_ref(ptr %t6038)
  %t6101 = getelementptr ptr, ptr %t6091, i32 8
  store ptr %t6038, ptr %t6101
  %t6102 = getelementptr ptr, ptr %t6079, i32 2
  store ptr %t6091, ptr %t6102
  call void @__free_recursive(ptr %t6038)
  call void @__free_recursive(ptr %t6036)
  call void @__free_recursive(ptr %t6034)
  call void @__free_recursive(ptr %t6032)
  call void @__free_recursive(ptr %t6030)
  call void @__free_recursive(ptr %t6028)
  call void @__free_recursive(ptr %t6026)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t6079, ptr %t3
  br label %tco.loop.0
tco.case.default.6045:
  unreachable
tco.case.arm.62.6103:
  %t6104 = getelementptr ptr, ptr %t5252, i32 1
  %t6105 = load ptr, ptr %t6104
  call void @__inc_ref(ptr %t6105)
  %t6106 = getelementptr ptr, ptr %t5252, i32 2
  %t6107 = load ptr, ptr %t6106
  call void @__inc_ref(ptr %t6107)
  %t6108 = getelementptr ptr, ptr %t5252, i32 3
  %t6109 = load ptr, ptr %t6108
  call void @__inc_ref(ptr %t6109)
  %t6110 = getelementptr ptr, ptr %t5252, i32 4
  %t6111 = load ptr, ptr %t6110
  call void @__inc_ref(ptr %t6111)
  %t6112 = getelementptr ptr, ptr %t5252, i32 5
  %t6113 = load ptr, ptr %t6112
  call void @__inc_ref(ptr %t6113)
  %t6114 = getelementptr ptr, ptr %t5252, i32 6
  %t6115 = load ptr, ptr %t6114
  call void @__inc_ref(ptr %t6115)
  %t6116 = getelementptr ptr, ptr %t5252, i32 7
  %t6117 = load ptr, ptr %t6116
  call void @__inc_ref(ptr %t6117)
  call void @__inc_ref(ptr %t6105)
  %t6118 = getelementptr ptr, ptr %t6117, i32 2
  %t6119 = load ptr, ptr %t6118
  call void @__inc_ref(ptr %t6119)
  %t6120 = call ptr @__subUInt32(ptr %t6105, ptr %t6119)
  %t6121 = getelementptr ptr, ptr %t6120, i32 0
  %t6122 = load ptr, ptr %t6121
  %t6123 = ptrtoint ptr %t6122 to i64
  switch i64 %t6123, label %tco.case.default.6124 [ i64 3, label %tco.case.arm.3.6125 i64 4, label %tco.case.arm.4.6153 ]
tco.case.arm.3.6125:
  call void @__free_recursive(ptr %t6120)
  %t6126 = call ptr @__alloc(i64 32, i32 3)
  %t6127 = inttoptr i64 34 to ptr
  %t6128 = getelementptr ptr, ptr %t6126, i32 0
  store ptr %t6127, ptr %t6128
  %t6129 = call ptr @__alloc(i64 8, i32 0)
  %t6130 = inttoptr i64 11 to ptr
  %t6131 = getelementptr ptr, ptr %t6129, i32 0
  store ptr %t6130, ptr %t6131
  %t6132 = getelementptr ptr, ptr %t6126, i32 1
  store ptr %t6129, ptr %t6132
  call void @__inc_ref(ptr %t6107)
  %t6133 = getelementptr ptr, ptr %t6126, i32 2
  store ptr %t6107, ptr %t6133
  %t6134 = call ptr @__alloc(i64 16, i32 1)
  %t6135 = inttoptr i64 12 to ptr
  %t6136 = getelementptr ptr, ptr %t6134, i32 0
  store ptr %t6135, ptr %t6136
  %t6137 = call ptr @__alloc(i64 32, i32 3)
  %t6138 = inttoptr i64 26 to ptr
  %t6139 = getelementptr ptr, ptr %t6137, i32 0
  store ptr %t6138, ptr %t6139
  call void @__inc_ref(ptr %t6109)
  %t6140 = getelementptr ptr, ptr %t6137, i32 1
  store ptr %t6109, ptr %t6140
  call void @__inc_ref(ptr %t6111)
  %t6141 = getelementptr ptr, ptr %t6137, i32 2
  store ptr %t6111, ptr %t6141
  call void @__inc_ref(ptr %t6113)
  %t6142 = getelementptr ptr, ptr %t6137, i32 3
  store ptr %t6113, ptr %t6142
  %t6143 = getelementptr ptr, ptr %t6134, i32 1
  store ptr %t6137, ptr %t6143
  %t6144 = getelementptr ptr, ptr %t6126, i32 3
  store ptr %t6134, ptr %t6144
  %t6145 = getelementptr ptr, ptr %t4, i32 1
  %t6146 = load ptr, ptr %t6145
  call void @__free_recursive(ptr %t6146)
  %t6147 = getelementptr ptr, ptr %t4, i32 2
  %t6148 = load ptr, ptr %t6147
  call void @__free_recursive(ptr %t6148)
  %t6151 = inttoptr i64 279 to ptr
  %t6152 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t6151, ptr %t6152
  call void @__inc_ref(ptr %t5254)
  %t6149 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t6149
  %t6150 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t6126, ptr %t6150
  call void @__free_recursive(ptr %t6117)
  call void @__free_recursive(ptr %t6115)
  call void @__free_recursive(ptr %t6113)
  call void @__free_recursive(ptr %t6111)
  call void @__free_recursive(ptr %t6109)
  call void @__free_recursive(ptr %t6107)
  call void @__free_recursive(ptr %t6105)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.4.6153:
  call void @__free_recursive(ptr %t6120)
  %t6154 = call ptr @__alloc(i64 24, i32 2)
  %t6155 = inttoptr i64 280 to ptr
  %t6156 = getelementptr ptr, ptr %t6154, i32 0
  store ptr %t6155, ptr %t6156
  %t6157 = getelementptr ptr, ptr %t4, i32 1
  %t6158 = load ptr, ptr %t6157
  call void @__free_recursive(ptr %t6158)
  %t6159 = getelementptr ptr, ptr %t4, i32 2
  %t6160 = load ptr, ptr %t6159
  call void @__free_recursive(ptr %t6160)
  %t6163 = inttoptr i64 101 to ptr
  %t6164 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t6163, ptr %t6164
  call void @__inc_ref(ptr %t6115)
  %t6161 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t6115, ptr %t6161
  call void @__inc_ref(ptr %t6109)
  %t6162 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t6109, ptr %t6162
  %t6165 = getelementptr ptr, ptr %t6154, i32 1
  store ptr %t4, ptr %t6165
  %t6166 = call ptr @__alloc(i64 72, i32 8)
  %t6167 = inttoptr i64 142 to ptr
  %t6168 = getelementptr ptr, ptr %t6166, i32 0
  store ptr %t6167, ptr %t6168
  call void @__inc_ref(ptr %t5254)
  %t6169 = getelementptr ptr, ptr %t6166, i32 1
  store ptr %t5254, ptr %t6169
  call void @__inc_ref(ptr %t6105)
  %t6170 = getelementptr ptr, ptr %t6166, i32 2
  store ptr %t6105, ptr %t6170
  call void @__inc_ref(ptr %t6107)
  %t6171 = getelementptr ptr, ptr %t6166, i32 3
  store ptr %t6107, ptr %t6171
  call void @__inc_ref(ptr %t6109)
  %t6172 = getelementptr ptr, ptr %t6166, i32 4
  store ptr %t6109, ptr %t6172
  call void @__inc_ref(ptr %t6111)
  %t6173 = getelementptr ptr, ptr %t6166, i32 5
  store ptr %t6111, ptr %t6173
  call void @__inc_ref(ptr %t6113)
  %t6174 = getelementptr ptr, ptr %t6166, i32 6
  store ptr %t6113, ptr %t6174
  call void @__inc_ref(ptr %t6115)
  %t6175 = getelementptr ptr, ptr %t6166, i32 7
  store ptr %t6115, ptr %t6175
  call void @__inc_ref(ptr %t6117)
  %t6176 = getelementptr ptr, ptr %t6166, i32 8
  store ptr %t6117, ptr %t6176
  %t6177 = getelementptr ptr, ptr %t6154, i32 2
  store ptr %t6166, ptr %t6177
  call void @__free_recursive(ptr %t6117)
  call void @__free_recursive(ptr %t6115)
  call void @__free_recursive(ptr %t6113)
  call void @__free_recursive(ptr %t6111)
  call void @__free_recursive(ptr %t6109)
  call void @__free_recursive(ptr %t6107)
  call void @__free_recursive(ptr %t6105)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t6154, ptr %t3
  br label %tco.loop.0
tco.case.default.6124:
  unreachable
tco.case.arm.63.6178:
  %t6179 = getelementptr ptr, ptr %t5252, i32 1
  %t6180 = load ptr, ptr %t6179
  call void @__inc_ref(ptr %t6180)
  %t6181 = getelementptr ptr, ptr %t5252, i32 2
  %t6182 = load ptr, ptr %t6181
  call void @__inc_ref(ptr %t6182)
  %t6183 = getelementptr ptr, ptr %t5252, i32 3
  %t6184 = load ptr, ptr %t6183
  call void @__inc_ref(ptr %t6184)
  %t6185 = getelementptr ptr, ptr %t5252, i32 4
  %t6186 = load ptr, ptr %t6185
  call void @__inc_ref(ptr %t6186)
  %t6187 = getelementptr ptr, ptr %t5252, i32 5
  %t6188 = load ptr, ptr %t6187
  call void @__inc_ref(ptr %t6188)
  %t6189 = getelementptr ptr, ptr %t5252, i32 6
  %t6190 = load ptr, ptr %t6189
  call void @__inc_ref(ptr %t6190)
  %t6191 = getelementptr ptr, ptr %t5252, i32 7
  %t6192 = load ptr, ptr %t6191
  call void @__inc_ref(ptr %t6192)
  call void @__inc_ref(ptr %t6180)
  %t6193 = getelementptr ptr, ptr %t6192, i32 1
  %t6194 = load ptr, ptr %t6193
  call void @__inc_ref(ptr %t6194)
  %t6195 = call ptr @__subUInt32(ptr %t6180, ptr %t6194)
  %t6196 = getelementptr ptr, ptr %t6195, i32 0
  %t6197 = load ptr, ptr %t6196
  %t6198 = ptrtoint ptr %t6197 to i64
  switch i64 %t6198, label %tco.case.default.6199 [ i64 3, label %tco.case.arm.3.6200 i64 4, label %tco.case.arm.4.6228 ]
tco.case.arm.3.6200:
  call void @__free_recursive(ptr %t6195)
  %t6201 = call ptr @__alloc(i64 32, i32 3)
  %t6202 = inttoptr i64 34 to ptr
  %t6203 = getelementptr ptr, ptr %t6201, i32 0
  store ptr %t6202, ptr %t6203
  %t6204 = call ptr @__alloc(i64 8, i32 0)
  %t6205 = inttoptr i64 11 to ptr
  %t6206 = getelementptr ptr, ptr %t6204, i32 0
  store ptr %t6205, ptr %t6206
  %t6207 = getelementptr ptr, ptr %t6201, i32 1
  store ptr %t6204, ptr %t6207
  call void @__inc_ref(ptr %t6182)
  %t6208 = getelementptr ptr, ptr %t6201, i32 2
  store ptr %t6182, ptr %t6208
  %t6209 = call ptr @__alloc(i64 16, i32 1)
  %t6210 = inttoptr i64 12 to ptr
  %t6211 = getelementptr ptr, ptr %t6209, i32 0
  store ptr %t6210, ptr %t6211
  %t6212 = call ptr @__alloc(i64 32, i32 3)
  %t6213 = inttoptr i64 26 to ptr
  %t6214 = getelementptr ptr, ptr %t6212, i32 0
  store ptr %t6213, ptr %t6214
  call void @__inc_ref(ptr %t6184)
  %t6215 = getelementptr ptr, ptr %t6212, i32 1
  store ptr %t6184, ptr %t6215
  call void @__inc_ref(ptr %t6186)
  %t6216 = getelementptr ptr, ptr %t6212, i32 2
  store ptr %t6186, ptr %t6216
  call void @__inc_ref(ptr %t6188)
  %t6217 = getelementptr ptr, ptr %t6212, i32 3
  store ptr %t6188, ptr %t6217
  %t6218 = getelementptr ptr, ptr %t6209, i32 1
  store ptr %t6212, ptr %t6218
  %t6219 = getelementptr ptr, ptr %t6201, i32 3
  store ptr %t6209, ptr %t6219
  %t6220 = getelementptr ptr, ptr %t4, i32 1
  %t6221 = load ptr, ptr %t6220
  call void @__free_recursive(ptr %t6221)
  %t6222 = getelementptr ptr, ptr %t4, i32 2
  %t6223 = load ptr, ptr %t6222
  call void @__free_recursive(ptr %t6223)
  %t6226 = inttoptr i64 279 to ptr
  %t6227 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t6226, ptr %t6227
  call void @__inc_ref(ptr %t5254)
  %t6224 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t6224
  %t6225 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t6201, ptr %t6225
  call void @__free_recursive(ptr %t6192)
  call void @__free_recursive(ptr %t6190)
  call void @__free_recursive(ptr %t6188)
  call void @__free_recursive(ptr %t6186)
  call void @__free_recursive(ptr %t6184)
  call void @__free_recursive(ptr %t6182)
  call void @__free_recursive(ptr %t6180)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.4.6228:
  call void @__free_recursive(ptr %t6195)
  %t6229 = call ptr @__alloc(i64 24, i32 2)
  %t6230 = inttoptr i64 280 to ptr
  %t6231 = getelementptr ptr, ptr %t6229, i32 0
  store ptr %t6230, ptr %t6231
  %t6232 = getelementptr ptr, ptr %t4, i32 1
  %t6233 = load ptr, ptr %t6232
  call void @__free_recursive(ptr %t6233)
  %t6234 = getelementptr ptr, ptr %t4, i32 2
  %t6235 = load ptr, ptr %t6234
  call void @__free_recursive(ptr %t6235)
  %t6238 = inttoptr i64 101 to ptr
  %t6239 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t6238, ptr %t6239
  call void @__inc_ref(ptr %t6190)
  %t6236 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t6190, ptr %t6236
  call void @__inc_ref(ptr %t6184)
  %t6237 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t6184, ptr %t6237
  %t6240 = getelementptr ptr, ptr %t6229, i32 1
  store ptr %t4, ptr %t6240
  %t6241 = call ptr @__alloc(i64 72, i32 8)
  %t6242 = inttoptr i64 144 to ptr
  %t6243 = getelementptr ptr, ptr %t6241, i32 0
  store ptr %t6242, ptr %t6243
  call void @__inc_ref(ptr %t5254)
  %t6244 = getelementptr ptr, ptr %t6241, i32 1
  store ptr %t5254, ptr %t6244
  call void @__inc_ref(ptr %t6180)
  %t6245 = getelementptr ptr, ptr %t6241, i32 2
  store ptr %t6180, ptr %t6245
  call void @__inc_ref(ptr %t6182)
  %t6246 = getelementptr ptr, ptr %t6241, i32 3
  store ptr %t6182, ptr %t6246
  call void @__inc_ref(ptr %t6184)
  %t6247 = getelementptr ptr, ptr %t6241, i32 4
  store ptr %t6184, ptr %t6247
  call void @__inc_ref(ptr %t6186)
  %t6248 = getelementptr ptr, ptr %t6241, i32 5
  store ptr %t6186, ptr %t6248
  call void @__inc_ref(ptr %t6188)
  %t6249 = getelementptr ptr, ptr %t6241, i32 6
  store ptr %t6188, ptr %t6249
  call void @__inc_ref(ptr %t6190)
  %t6250 = getelementptr ptr, ptr %t6241, i32 7
  store ptr %t6190, ptr %t6250
  call void @__inc_ref(ptr %t6192)
  %t6251 = getelementptr ptr, ptr %t6241, i32 8
  store ptr %t6192, ptr %t6251
  %t6252 = getelementptr ptr, ptr %t6229, i32 2
  store ptr %t6241, ptr %t6252
  call void @__free_recursive(ptr %t6192)
  call void @__free_recursive(ptr %t6190)
  call void @__free_recursive(ptr %t6188)
  call void @__free_recursive(ptr %t6186)
  call void @__free_recursive(ptr %t6184)
  call void @__free_recursive(ptr %t6182)
  call void @__free_recursive(ptr %t6180)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t6229, ptr %t3
  br label %tco.loop.0
tco.case.default.6199:
  unreachable
tco.case.arm.64.6253:
  %t6254 = getelementptr ptr, ptr %t5252, i32 2
  %t6255 = load ptr, ptr %t6254
  call void @__inc_ref(ptr %t6255)
  %t6256 = call ptr @__alloc(i64 24, i32 2)
  %t6257 = inttoptr i64 280 to ptr
  %t6258 = getelementptr ptr, ptr %t6256, i32 0
  store ptr %t6257, ptr %t6258
  %t6259 = call ptr @__alloc(i64 40, i32 4)
  %t6260 = inttoptr i64 79 to ptr
  %t6261 = getelementptr ptr, ptr %t6259, i32 0
  store ptr %t6260, ptr %t6261
  %t6262 = getelementptr ptr, ptr %t5252, i32 1
  %t6263 = load ptr, ptr %t6262
  call void @__inc_ref(ptr %t6263)
  %t6264 = getelementptr ptr, ptr %t6259, i32 1
  store ptr %t6263, ptr %t6264
  call void @__inc_ref(ptr %t6255)
  %t6265 = getelementptr ptr, ptr %t6259, i32 2
  store ptr %t6255, ptr %t6265
  %t6266 = getelementptr ptr, ptr %t5252, i32 8
  %t6267 = load ptr, ptr %t6266
  call void @__inc_ref(ptr %t6267)
  %t6268 = getelementptr ptr, ptr %t6259, i32 3
  store ptr %t6267, ptr %t6268
  %t6269 = getelementptr ptr, ptr %t5252, i32 5
  %t6270 = load ptr, ptr %t6269
  call void @__inc_ref(ptr %t6270)
  %t6271 = getelementptr ptr, ptr %t6270, i32 0
  %t6272 = load ptr, ptr %t6271
  %t6273 = ptrtoint ptr %t6272 to i64
  switch i64 %t6273, label %case.default.6274 [ i64 28, label %case.arm.28.6276 i64 29, label %case.arm.29.6290 ]
case.arm.28.6276:
  %t6278 = getelementptr ptr, ptr %t6270, i32 2
  %t6279 = load ptr, ptr %t6278
  call void @__inc_ref(ptr %t6279)
  %t6280 = getelementptr ptr, ptr %t6270, i32 3
  %t6281 = load ptr, ptr %t6280
  call void @__inc_ref(ptr %t6281)
  %t6282 = getelementptr ptr, ptr %t4, i32 1
  %t6283 = load ptr, ptr %t6282
  call void @__free_recursive(ptr %t6283)
  %t6284 = getelementptr ptr, ptr %t4, i32 2
  %t6285 = load ptr, ptr %t6284
  call void @__free_recursive(ptr %t6285)
  %t6288 = inttoptr i64 25 to ptr
  %t6289 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t6288, ptr %t6289
  %t6286 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t6279, ptr %t6286
  %t6287 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t6281, ptr %t6287
  br label %case.end.28.6277
case.end.28.6277:
  br label %case.join.6275
case.arm.29.6290:
  %t6292 = call ptr @__alloc(i64 32, i32 3)
  %t6293 = inttoptr i64 26 to ptr
  %t6294 = getelementptr ptr, ptr %t6292, i32 0
  store ptr %t6293, ptr %t6294
  %t6295 = getelementptr ptr, ptr %t6270, i32 2
  %t6296 = load ptr, ptr %t6295
  call void @__inc_ref(ptr %t6296)
  %t6297 = getelementptr ptr, ptr %t6292, i32 1
  store ptr %t6296, ptr %t6297
  %t6298 = getelementptr ptr, ptr %t6270, i32 3
  %t6299 = load ptr, ptr %t6298
  call void @__inc_ref(ptr %t6299)
  %t6300 = getelementptr ptr, ptr %t6292, i32 2
  store ptr %t6299, ptr %t6300
  %t6301 = getelementptr ptr, ptr %t6270, i32 4
  %t6302 = load ptr, ptr %t6301
  call void @__inc_ref(ptr %t6302)
  %t6303 = getelementptr ptr, ptr %t6292, i32 3
  store ptr %t6302, ptr %t6303
  call void @__free_recursive(ptr %t4)
  br label %case.end.29.6291
case.end.29.6291:
  br label %case.join.6275
case.default.6274:
  unreachable
case.join.6275:
  %t6304 = phi ptr [ %t4, %case.end.28.6277 ], [ %t6292, %case.end.29.6291 ]
  call void @__free_recursive(ptr %t6270)
  %t6305 = getelementptr ptr, ptr %t6259, i32 4
  store ptr %t6304, ptr %t6305
  %t6306 = getelementptr ptr, ptr %t6256, i32 1
  store ptr %t6259, ptr %t6306
  %t6307 = call ptr @__alloc(i64 56, i32 6)
  %t6308 = inttoptr i64 146 to ptr
  %t6309 = getelementptr ptr, ptr %t6307, i32 0
  store ptr %t6308, ptr %t6309
  call void @__inc_ref(ptr %t5254)
  %t6310 = getelementptr ptr, ptr %t6307, i32 1
  store ptr %t5254, ptr %t6310
  call void @__inc_ref(ptr %t6255)
  %t6311 = getelementptr ptr, ptr %t6307, i32 2
  store ptr %t6255, ptr %t6311
  %t6312 = getelementptr ptr, ptr %t5252, i32 3
  %t6313 = load ptr, ptr %t6312
  call void @__inc_ref(ptr %t6313)
  %t6314 = getelementptr ptr, ptr %t6307, i32 3
  store ptr %t6313, ptr %t6314
  %t6315 = getelementptr ptr, ptr %t5252, i32 4
  %t6316 = load ptr, ptr %t6315
  call void @__inc_ref(ptr %t6316)
  %t6317 = getelementptr ptr, ptr %t6307, i32 4
  store ptr %t6316, ptr %t6317
  %t6318 = getelementptr ptr, ptr %t5252, i32 6
  %t6319 = load ptr, ptr %t6318
  call void @__inc_ref(ptr %t6319)
  %t6320 = getelementptr ptr, ptr %t6307, i32 5
  store ptr %t6319, ptr %t6320
  %t6321 = getelementptr ptr, ptr %t5252, i32 7
  %t6322 = load ptr, ptr %t6321
  call void @__inc_ref(ptr %t6322)
  %t6323 = getelementptr ptr, ptr %t6307, i32 6
  store ptr %t6322, ptr %t6323
  %t6324 = getelementptr ptr, ptr %t6256, i32 2
  store ptr %t6307, ptr %t6324
  call void @__free_recursive(ptr %t6255)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t6256, ptr %t3
  br label %tco.loop.0
tco.case.arm.65.6325:
  %t6326 = getelementptr ptr, ptr %t5252, i32 2
  %t6327 = load ptr, ptr %t6326
  call void @__inc_ref(ptr %t6327)
  %t6328 = call ptr @__alloc(i64 24, i32 2)
  %t6329 = inttoptr i64 280 to ptr
  %t6330 = getelementptr ptr, ptr %t6328, i32 0
  store ptr %t6329, ptr %t6330
  %t6331 = call ptr @__alloc(i64 40, i32 4)
  %t6332 = inttoptr i64 78 to ptr
  %t6333 = getelementptr ptr, ptr %t6331, i32 0
  store ptr %t6332, ptr %t6333
  %t6334 = getelementptr ptr, ptr %t5252, i32 1
  %t6335 = load ptr, ptr %t6334
  call void @__inc_ref(ptr %t6335)
  %t6336 = getelementptr ptr, ptr %t6331, i32 1
  store ptr %t6335, ptr %t6336
  call void @__inc_ref(ptr %t6327)
  %t6337 = getelementptr ptr, ptr %t6331, i32 2
  store ptr %t6327, ptr %t6337
  %t6338 = getelementptr ptr, ptr %t5252, i32 8
  %t6339 = load ptr, ptr %t6338
  call void @__inc_ref(ptr %t6339)
  %t6340 = getelementptr ptr, ptr %t6331, i32 3
  store ptr %t6339, ptr %t6340
  %t6341 = getelementptr ptr, ptr %t5252, i32 5
  %t6342 = load ptr, ptr %t6341
  call void @__inc_ref(ptr %t6342)
  %t6343 = getelementptr ptr, ptr %t6342, i32 0
  %t6344 = load ptr, ptr %t6343
  %t6345 = ptrtoint ptr %t6344 to i64
  switch i64 %t6345, label %case.default.6346 [ i64 28, label %case.arm.28.6348 i64 29, label %case.arm.29.6362 ]
case.arm.28.6348:
  %t6350 = getelementptr ptr, ptr %t6342, i32 2
  %t6351 = load ptr, ptr %t6350
  call void @__inc_ref(ptr %t6351)
  %t6352 = getelementptr ptr, ptr %t6342, i32 3
  %t6353 = load ptr, ptr %t6352
  call void @__inc_ref(ptr %t6353)
  %t6354 = getelementptr ptr, ptr %t4, i32 1
  %t6355 = load ptr, ptr %t6354
  call void @__free_recursive(ptr %t6355)
  %t6356 = getelementptr ptr, ptr %t4, i32 2
  %t6357 = load ptr, ptr %t6356
  call void @__free_recursive(ptr %t6357)
  %t6360 = inttoptr i64 25 to ptr
  %t6361 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t6360, ptr %t6361
  %t6358 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t6351, ptr %t6358
  %t6359 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t6353, ptr %t6359
  br label %case.end.28.6349
case.end.28.6349:
  br label %case.join.6347
case.arm.29.6362:
  %t6364 = call ptr @__alloc(i64 32, i32 3)
  %t6365 = inttoptr i64 26 to ptr
  %t6366 = getelementptr ptr, ptr %t6364, i32 0
  store ptr %t6365, ptr %t6366
  %t6367 = getelementptr ptr, ptr %t6342, i32 2
  %t6368 = load ptr, ptr %t6367
  call void @__inc_ref(ptr %t6368)
  %t6369 = getelementptr ptr, ptr %t6364, i32 1
  store ptr %t6368, ptr %t6369
  %t6370 = getelementptr ptr, ptr %t6342, i32 3
  %t6371 = load ptr, ptr %t6370
  call void @__inc_ref(ptr %t6371)
  %t6372 = getelementptr ptr, ptr %t6364, i32 2
  store ptr %t6371, ptr %t6372
  %t6373 = getelementptr ptr, ptr %t6342, i32 4
  %t6374 = load ptr, ptr %t6373
  call void @__inc_ref(ptr %t6374)
  %t6375 = getelementptr ptr, ptr %t6364, i32 3
  store ptr %t6374, ptr %t6375
  call void @__free_recursive(ptr %t4)
  br label %case.end.29.6363
case.end.29.6363:
  br label %case.join.6347
case.default.6346:
  unreachable
case.join.6347:
  %t6376 = phi ptr [ %t4, %case.end.28.6349 ], [ %t6364, %case.end.29.6363 ]
  call void @__free_recursive(ptr %t6342)
  %t6377 = getelementptr ptr, ptr %t6331, i32 4
  store ptr %t6376, ptr %t6377
  %t6378 = getelementptr ptr, ptr %t6328, i32 1
  store ptr %t6331, ptr %t6378
  %t6379 = call ptr @__alloc(i64 56, i32 6)
  %t6380 = inttoptr i64 149 to ptr
  %t6381 = getelementptr ptr, ptr %t6379, i32 0
  store ptr %t6380, ptr %t6381
  call void @__inc_ref(ptr %t5254)
  %t6382 = getelementptr ptr, ptr %t6379, i32 1
  store ptr %t5254, ptr %t6382
  call void @__inc_ref(ptr %t6327)
  %t6383 = getelementptr ptr, ptr %t6379, i32 2
  store ptr %t6327, ptr %t6383
  %t6384 = getelementptr ptr, ptr %t5252, i32 3
  %t6385 = load ptr, ptr %t6384
  call void @__inc_ref(ptr %t6385)
  %t6386 = getelementptr ptr, ptr %t6379, i32 3
  store ptr %t6385, ptr %t6386
  %t6387 = getelementptr ptr, ptr %t5252, i32 4
  %t6388 = load ptr, ptr %t6387
  call void @__inc_ref(ptr %t6388)
  %t6389 = getelementptr ptr, ptr %t6379, i32 4
  store ptr %t6388, ptr %t6389
  %t6390 = getelementptr ptr, ptr %t5252, i32 6
  %t6391 = load ptr, ptr %t6390
  call void @__inc_ref(ptr %t6391)
  %t6392 = getelementptr ptr, ptr %t6379, i32 5
  store ptr %t6391, ptr %t6392
  %t6393 = getelementptr ptr, ptr %t5252, i32 7
  %t6394 = load ptr, ptr %t6393
  call void @__inc_ref(ptr %t6394)
  %t6395 = getelementptr ptr, ptr %t6379, i32 6
  store ptr %t6394, ptr %t6395
  %t6396 = getelementptr ptr, ptr %t6328, i32 2
  store ptr %t6379, ptr %t6396
  call void @__free_recursive(ptr %t6327)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t6328, ptr %t3
  br label %tco.loop.0
tco.case.arm.66.6397:
  %t6398 = getelementptr ptr, ptr %t5252, i32 1
  %t6399 = load ptr, ptr %t6398
  call void @__inc_ref(ptr %t6399)
  %t6400 = getelementptr ptr, ptr %t5252, i32 2
  %t6401 = load ptr, ptr %t6400
  call void @__inc_ref(ptr %t6401)
  %t6402 = getelementptr ptr, ptr %t5252, i32 3
  %t6403 = load ptr, ptr %t6402
  call void @__inc_ref(ptr %t6403)
  %t6404 = getelementptr ptr, ptr %t5252, i32 4
  %t6405 = load ptr, ptr %t6404
  call void @__inc_ref(ptr %t6405)
  %t6406 = getelementptr ptr, ptr %t5252, i32 5
  %t6407 = load ptr, ptr %t6406
  call void @__inc_ref(ptr %t6407)
  %t6408 = getelementptr ptr, ptr %t5252, i32 6
  %t6409 = load ptr, ptr %t6408
  call void @__inc_ref(ptr %t6409)
  %t6410 = getelementptr ptr, ptr %t5252, i32 7
  %t6411 = load ptr, ptr %t6410
  call void @__inc_ref(ptr %t6411)
  call void @__inc_ref(ptr %t6399)
  %t6412 = getelementptr ptr, ptr %t6411, i32 2
  %t6413 = load ptr, ptr %t6412
  call void @__inc_ref(ptr %t6413)
  %t6414 = call ptr @__subUInt32(ptr %t6399, ptr %t6413)
  %t6415 = getelementptr ptr, ptr %t6414, i32 0
  %t6416 = load ptr, ptr %t6415
  %t6417 = ptrtoint ptr %t6416 to i64
  switch i64 %t6417, label %tco.case.default.6418 [ i64 3, label %tco.case.arm.3.6419 i64 4, label %tco.case.arm.4.6457 ]
tco.case.arm.3.6419:
  call void @__free_recursive(ptr %t6414)
  %t6420 = call ptr @__alloc(i64 40, i32 4)
  %t6421 = inttoptr i64 80 to ptr
  %t6422 = getelementptr ptr, ptr %t6420, i32 0
  store ptr %t6421, ptr %t6422
  call void @__inc_ref(ptr %t6399)
  %t6423 = getelementptr ptr, ptr %t6420, i32 1
  store ptr %t6399, ptr %t6423
  %t6424 = call ptr @__alloc(i64 32, i32 3)
  %t6425 = inttoptr i64 33 to ptr
  %t6426 = getelementptr ptr, ptr %t6424, i32 0
  store ptr %t6425, ptr %t6426
  %t6427 = call ptr @__alloc(i64 8, i32 0)
  %t6428 = inttoptr i64 49 to ptr
  %t6429 = getelementptr ptr, ptr %t6427, i32 0
  store ptr %t6428, ptr %t6429
  %t6430 = getelementptr ptr, ptr %t6424, i32 1
  store ptr %t6427, ptr %t6430
  %t6431 = getelementptr ptr, ptr %t6401, i32 2
  %t6432 = load ptr, ptr %t6431
  call void @__inc_ref(ptr %t6432)
  %t6433 = getelementptr ptr, ptr %t6424, i32 2
  store ptr %t6432, ptr %t6433
  %t6434 = getelementptr ptr, ptr %t6401, i32 3
  %t6435 = load ptr, ptr %t6434
  call void @__inc_ref(ptr %t6435)
  %t6436 = getelementptr ptr, ptr %t6424, i32 3
  store ptr %t6435, ptr %t6436
  %t6437 = getelementptr ptr, ptr %t6420, i32 2
  store ptr %t6424, ptr %t6437
  call void @__inc_ref(ptr %t6409)
  %t6438 = getelementptr ptr, ptr %t6420, i32 3
  store ptr %t6409, ptr %t6438
  call void @__inc_ref(ptr %t6403)
  %t6439 = getelementptr ptr, ptr %t6420, i32 4
  store ptr %t6403, ptr %t6439
  %t6440 = call ptr @__alloc(i64 56, i32 6)
  %t6441 = inttoptr i64 152 to ptr
  %t6442 = getelementptr ptr, ptr %t6440, i32 0
  store ptr %t6441, ptr %t6442
  call void @__inc_ref(ptr %t5254)
  %t6443 = getelementptr ptr, ptr %t6440, i32 1
  store ptr %t5254, ptr %t6443
  call void @__inc_ref(ptr %t6399)
  %t6444 = getelementptr ptr, ptr %t6440, i32 2
  store ptr %t6399, ptr %t6444
  call void @__inc_ref(ptr %t6401)
  %t6445 = getelementptr ptr, ptr %t6440, i32 3
  store ptr %t6401, ptr %t6445
  call void @__inc_ref(ptr %t6405)
  %t6446 = getelementptr ptr, ptr %t6440, i32 4
  store ptr %t6405, ptr %t6446
  call void @__inc_ref(ptr %t6407)
  %t6447 = getelementptr ptr, ptr %t6440, i32 5
  store ptr %t6407, ptr %t6447
  call void @__inc_ref(ptr %t6409)
  %t6448 = getelementptr ptr, ptr %t6440, i32 6
  store ptr %t6409, ptr %t6448
  %t6449 = getelementptr ptr, ptr %t4, i32 1
  %t6450 = load ptr, ptr %t6449
  call void @__free_recursive(ptr %t6450)
  %t6451 = getelementptr ptr, ptr %t4, i32 2
  %t6452 = load ptr, ptr %t6451
  call void @__free_recursive(ptr %t6452)
  %t6455 = inttoptr i64 280 to ptr
  %t6456 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t6455, ptr %t6456
  %t6453 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t6420, ptr %t6453
  %t6454 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t6440, ptr %t6454
  call void @__free_recursive(ptr %t6411)
  call void @__free_recursive(ptr %t6409)
  call void @__free_recursive(ptr %t6407)
  call void @__free_recursive(ptr %t6405)
  call void @__free_recursive(ptr %t6403)
  call void @__free_recursive(ptr %t6401)
  call void @__free_recursive(ptr %t6399)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.4.6457:
  call void @__free_recursive(ptr %t6414)
  %t6458 = call ptr @__alloc(i64 40, i32 4)
  %t6459 = inttoptr i64 78 to ptr
  %t6460 = getelementptr ptr, ptr %t6458, i32 0
  store ptr %t6459, ptr %t6460
  call void @__inc_ref(ptr %t6399)
  %t6461 = getelementptr ptr, ptr %t6458, i32 1
  store ptr %t6399, ptr %t6461
  call void @__inc_ref(ptr %t6401)
  %t6462 = getelementptr ptr, ptr %t6458, i32 2
  store ptr %t6401, ptr %t6462
  call void @__inc_ref(ptr %t6411)
  %t6463 = getelementptr ptr, ptr %t6458, i32 3
  store ptr %t6411, ptr %t6463
  call void @__inc_ref(ptr %t6407)
  %t6464 = getelementptr ptr, ptr %t6458, i32 4
  store ptr %t6407, ptr %t6464
  %t6465 = call ptr @__alloc(i64 40, i32 4)
  %t6466 = inttoptr i64 155 to ptr
  %t6467 = getelementptr ptr, ptr %t6465, i32 0
  store ptr %t6466, ptr %t6467
  call void @__inc_ref(ptr %t5254)
  %t6468 = getelementptr ptr, ptr %t6465, i32 1
  store ptr %t5254, ptr %t6468
  call void @__inc_ref(ptr %t6401)
  %t6469 = getelementptr ptr, ptr %t6465, i32 2
  store ptr %t6401, ptr %t6469
  call void @__inc_ref(ptr %t6403)
  %t6470 = getelementptr ptr, ptr %t6465, i32 3
  store ptr %t6403, ptr %t6470
  call void @__inc_ref(ptr %t6405)
  %t6471 = getelementptr ptr, ptr %t6465, i32 4
  store ptr %t6405, ptr %t6471
  %t6472 = getelementptr ptr, ptr %t4, i32 1
  %t6473 = load ptr, ptr %t6472
  call void @__free_recursive(ptr %t6473)
  %t6474 = getelementptr ptr, ptr %t4, i32 2
  %t6475 = load ptr, ptr %t6474
  call void @__free_recursive(ptr %t6475)
  %t6478 = inttoptr i64 280 to ptr
  %t6479 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t6478, ptr %t6479
  %t6476 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t6458, ptr %t6476
  %t6477 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t6465, ptr %t6477
  call void @__free_recursive(ptr %t6411)
  call void @__free_recursive(ptr %t6409)
  call void @__free_recursive(ptr %t6407)
  call void @__free_recursive(ptr %t6405)
  call void @__free_recursive(ptr %t6403)
  call void @__free_recursive(ptr %t6401)
  call void @__free_recursive(ptr %t6399)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.6418:
  unreachable
tco.case.arm.67.6480:
  %t6481 = getelementptr ptr, ptr %t5252, i32 1
  %t6482 = load ptr, ptr %t6481
  call void @__inc_ref(ptr %t6482)
  %t6483 = getelementptr ptr, ptr %t5252, i32 2
  %t6484 = load ptr, ptr %t6483
  call void @__inc_ref(ptr %t6484)
  %t6485 = getelementptr ptr, ptr %t5252, i32 3
  %t6486 = load ptr, ptr %t6485
  call void @__inc_ref(ptr %t6486)
  %t6487 = getelementptr ptr, ptr %t5252, i32 4
  %t6488 = load ptr, ptr %t6487
  call void @__inc_ref(ptr %t6488)
  %t6489 = getelementptr ptr, ptr %t5252, i32 5
  %t6490 = load ptr, ptr %t6489
  call void @__inc_ref(ptr %t6490)
  %t6491 = getelementptr ptr, ptr %t5252, i32 6
  %t6492 = load ptr, ptr %t6491
  call void @__inc_ref(ptr %t6492)
  %t6493 = getelementptr ptr, ptr %t5252, i32 7
  %t6494 = load ptr, ptr %t6493
  call void @__inc_ref(ptr %t6494)
  call void @__inc_ref(ptr %t6482)
  %t6495 = getelementptr ptr, ptr %t6494, i32 1
  %t6496 = load ptr, ptr %t6495
  call void @__inc_ref(ptr %t6496)
  %t6497 = call ptr @__subUInt32(ptr %t6482, ptr %t6496)
  %t6498 = getelementptr ptr, ptr %t6497, i32 0
  %t6499 = load ptr, ptr %t6498
  %t6500 = ptrtoint ptr %t6499 to i64
  switch i64 %t6500, label %tco.case.default.6501 [ i64 3, label %tco.case.arm.3.6502 i64 4, label %tco.case.arm.4.6540 ]
tco.case.arm.3.6502:
  call void @__free_recursive(ptr %t6497)
  %t6503 = call ptr @__alloc(i64 40, i32 4)
  %t6504 = inttoptr i64 81 to ptr
  %t6505 = getelementptr ptr, ptr %t6503, i32 0
  store ptr %t6504, ptr %t6505
  call void @__inc_ref(ptr %t6482)
  %t6506 = getelementptr ptr, ptr %t6503, i32 1
  store ptr %t6482, ptr %t6506
  %t6507 = call ptr @__alloc(i64 32, i32 3)
  %t6508 = inttoptr i64 33 to ptr
  %t6509 = getelementptr ptr, ptr %t6507, i32 0
  store ptr %t6508, ptr %t6509
  %t6510 = call ptr @__alloc(i64 8, i32 0)
  %t6511 = inttoptr i64 49 to ptr
  %t6512 = getelementptr ptr, ptr %t6510, i32 0
  store ptr %t6511, ptr %t6512
  %t6513 = getelementptr ptr, ptr %t6507, i32 1
  store ptr %t6510, ptr %t6513
  %t6514 = getelementptr ptr, ptr %t6484, i32 2
  %t6515 = load ptr, ptr %t6514
  call void @__inc_ref(ptr %t6515)
  %t6516 = getelementptr ptr, ptr %t6507, i32 2
  store ptr %t6515, ptr %t6516
  %t6517 = getelementptr ptr, ptr %t6484, i32 3
  %t6518 = load ptr, ptr %t6517
  call void @__inc_ref(ptr %t6518)
  %t6519 = getelementptr ptr, ptr %t6507, i32 3
  store ptr %t6518, ptr %t6519
  %t6520 = getelementptr ptr, ptr %t6503, i32 2
  store ptr %t6507, ptr %t6520
  call void @__inc_ref(ptr %t6492)
  %t6521 = getelementptr ptr, ptr %t6503, i32 3
  store ptr %t6492, ptr %t6521
  call void @__inc_ref(ptr %t6486)
  %t6522 = getelementptr ptr, ptr %t6503, i32 4
  store ptr %t6486, ptr %t6522
  %t6523 = call ptr @__alloc(i64 56, i32 6)
  %t6524 = inttoptr i64 158 to ptr
  %t6525 = getelementptr ptr, ptr %t6523, i32 0
  store ptr %t6524, ptr %t6525
  call void @__inc_ref(ptr %t5254)
  %t6526 = getelementptr ptr, ptr %t6523, i32 1
  store ptr %t5254, ptr %t6526
  call void @__inc_ref(ptr %t6482)
  %t6527 = getelementptr ptr, ptr %t6523, i32 2
  store ptr %t6482, ptr %t6527
  call void @__inc_ref(ptr %t6484)
  %t6528 = getelementptr ptr, ptr %t6523, i32 3
  store ptr %t6484, ptr %t6528
  call void @__inc_ref(ptr %t6488)
  %t6529 = getelementptr ptr, ptr %t6523, i32 4
  store ptr %t6488, ptr %t6529
  call void @__inc_ref(ptr %t6490)
  %t6530 = getelementptr ptr, ptr %t6523, i32 5
  store ptr %t6490, ptr %t6530
  call void @__inc_ref(ptr %t6492)
  %t6531 = getelementptr ptr, ptr %t6523, i32 6
  store ptr %t6492, ptr %t6531
  %t6532 = getelementptr ptr, ptr %t4, i32 1
  %t6533 = load ptr, ptr %t6532
  call void @__free_recursive(ptr %t6533)
  %t6534 = getelementptr ptr, ptr %t4, i32 2
  %t6535 = load ptr, ptr %t6534
  call void @__free_recursive(ptr %t6535)
  %t6538 = inttoptr i64 280 to ptr
  %t6539 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t6538, ptr %t6539
  %t6536 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t6503, ptr %t6536
  %t6537 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t6523, ptr %t6537
  call void @__free_recursive(ptr %t6494)
  call void @__free_recursive(ptr %t6492)
  call void @__free_recursive(ptr %t6490)
  call void @__free_recursive(ptr %t6488)
  call void @__free_recursive(ptr %t6486)
  call void @__free_recursive(ptr %t6484)
  call void @__free_recursive(ptr %t6482)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.4.6540:
  call void @__free_recursive(ptr %t6497)
  %t6541 = call ptr @__alloc(i64 40, i32 4)
  %t6542 = inttoptr i64 79 to ptr
  %t6543 = getelementptr ptr, ptr %t6541, i32 0
  store ptr %t6542, ptr %t6543
  call void @__inc_ref(ptr %t6482)
  %t6544 = getelementptr ptr, ptr %t6541, i32 1
  store ptr %t6482, ptr %t6544
  call void @__inc_ref(ptr %t6484)
  %t6545 = getelementptr ptr, ptr %t6541, i32 2
  store ptr %t6484, ptr %t6545
  call void @__inc_ref(ptr %t6494)
  %t6546 = getelementptr ptr, ptr %t6541, i32 3
  store ptr %t6494, ptr %t6546
  call void @__inc_ref(ptr %t6490)
  %t6547 = getelementptr ptr, ptr %t6541, i32 4
  store ptr %t6490, ptr %t6547
  %t6548 = call ptr @__alloc(i64 40, i32 4)
  %t6549 = inttoptr i64 161 to ptr
  %t6550 = getelementptr ptr, ptr %t6548, i32 0
  store ptr %t6549, ptr %t6550
  call void @__inc_ref(ptr %t5254)
  %t6551 = getelementptr ptr, ptr %t6548, i32 1
  store ptr %t5254, ptr %t6551
  call void @__inc_ref(ptr %t6484)
  %t6552 = getelementptr ptr, ptr %t6548, i32 2
  store ptr %t6484, ptr %t6552
  call void @__inc_ref(ptr %t6486)
  %t6553 = getelementptr ptr, ptr %t6548, i32 3
  store ptr %t6486, ptr %t6553
  call void @__inc_ref(ptr %t6488)
  %t6554 = getelementptr ptr, ptr %t6548, i32 4
  store ptr %t6488, ptr %t6554
  %t6555 = getelementptr ptr, ptr %t4, i32 1
  %t6556 = load ptr, ptr %t6555
  call void @__free_recursive(ptr %t6556)
  %t6557 = getelementptr ptr, ptr %t4, i32 2
  %t6558 = load ptr, ptr %t6557
  call void @__free_recursive(ptr %t6558)
  %t6561 = inttoptr i64 280 to ptr
  %t6562 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t6561, ptr %t6562
  %t6559 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t6541, ptr %t6559
  %t6560 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t6548, ptr %t6560
  call void @__free_recursive(ptr %t6494)
  call void @__free_recursive(ptr %t6492)
  call void @__free_recursive(ptr %t6490)
  call void @__free_recursive(ptr %t6488)
  call void @__free_recursive(ptr %t6486)
  call void @__free_recursive(ptr %t6484)
  call void @__free_recursive(ptr %t6482)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.6501:
  unreachable
tco.case.arm.68.6563:
  %t6564 = getelementptr ptr, ptr %t5252, i32 1
  %t6565 = load ptr, ptr %t6564
  call void @__inc_ref(ptr %t6565)
  %t6566 = getelementptr ptr, ptr %t5252, i32 3
  %t6567 = load ptr, ptr %t6566
  call void @__inc_ref(ptr %t6567)
  %t6568 = getelementptr ptr, ptr %t5252, i32 4
  %t6569 = load ptr, ptr %t6568
  call void @__inc_ref(ptr %t6569)
  %t6570 = getelementptr ptr, ptr %t5252, i32 5
  %t6571 = load ptr, ptr %t6570
  call void @__inc_ref(ptr %t6571)
  %t6572 = getelementptr ptr, ptr %t5252, i32 6
  %t6573 = load ptr, ptr %t6572
  call void @__inc_ref(ptr %t6573)
  %t6574 = getelementptr ptr, ptr %t5252, i32 7
  %t6575 = load ptr, ptr %t6574
  call void @__inc_ref(ptr %t6575)
  call void @__inc_ref(ptr %t6565)
  %t6576 = getelementptr ptr, ptr %t6575, i32 2
  %t6577 = load ptr, ptr %t6576
  call void @__inc_ref(ptr %t6577)
  %t6578 = call ptr @__subUInt32(ptr %t6565, ptr %t6577)
  %t6579 = getelementptr ptr, ptr %t6578, i32 0
  %t6580 = load ptr, ptr %t6579
  %t6581 = ptrtoint ptr %t6580 to i64
  switch i64 %t6581, label %tco.case.default.6582 [ i64 3, label %tco.case.arm.3.6583 i64 4, label %tco.case.arm.4.6608 ]
tco.case.arm.3.6583:
  call void @__free_recursive(ptr %t6578)
  %t6584 = call ptr @__alloc(i64 40, i32 4)
  %t6585 = inttoptr i64 78 to ptr
  %t6586 = getelementptr ptr, ptr %t6584, i32 0
  store ptr %t6585, ptr %t6586
  call void @__inc_ref(ptr %t6565)
  %t6587 = getelementptr ptr, ptr %t6584, i32 1
  store ptr %t6565, ptr %t6587
  call void @__inc_ref(ptr %t6567)
  %t6588 = getelementptr ptr, ptr %t6584, i32 2
  store ptr %t6567, ptr %t6588
  %t6589 = getelementptr ptr, ptr %t5252, i32 2
  %t6590 = load ptr, ptr %t6589
  call void @__inc_ref(ptr %t6590)
  %t6591 = getelementptr ptr, ptr %t6584, i32 3
  store ptr %t6590, ptr %t6591
  call void @__inc_ref(ptr %t6571)
  %t6592 = getelementptr ptr, ptr %t6584, i32 4
  store ptr %t6571, ptr %t6592
  %t6593 = call ptr @__alloc(i64 40, i32 4)
  %t6594 = inttoptr i64 164 to ptr
  %t6595 = getelementptr ptr, ptr %t6593, i32 0
  store ptr %t6594, ptr %t6595
  call void @__inc_ref(ptr %t5254)
  %t6596 = getelementptr ptr, ptr %t6593, i32 1
  store ptr %t5254, ptr %t6596
  call void @__inc_ref(ptr %t6567)
  %t6597 = getelementptr ptr, ptr %t6593, i32 2
  store ptr %t6567, ptr %t6597
  call void @__inc_ref(ptr %t6569)
  %t6598 = getelementptr ptr, ptr %t6593, i32 3
  store ptr %t6569, ptr %t6598
  call void @__inc_ref(ptr %t6573)
  %t6599 = getelementptr ptr, ptr %t6593, i32 4
  store ptr %t6573, ptr %t6599
  %t6600 = getelementptr ptr, ptr %t4, i32 1
  %t6601 = load ptr, ptr %t6600
  call void @__free_recursive(ptr %t6601)
  %t6602 = getelementptr ptr, ptr %t4, i32 2
  %t6603 = load ptr, ptr %t6602
  call void @__free_recursive(ptr %t6603)
  %t6606 = inttoptr i64 280 to ptr
  %t6607 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t6606, ptr %t6607
  %t6604 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t6584, ptr %t6604
  %t6605 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t6593, ptr %t6605
  call void @__free_recursive(ptr %t6575)
  call void @__free_recursive(ptr %t6573)
  call void @__free_recursive(ptr %t6571)
  call void @__free_recursive(ptr %t6569)
  call void @__free_recursive(ptr %t6567)
  call void @__free_recursive(ptr %t6565)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.4.6608:
  call void @__free_recursive(ptr %t6578)
  %t6609 = call ptr @__alloc(i64 24, i32 2)
  %t6610 = inttoptr i64 280 to ptr
  %t6611 = getelementptr ptr, ptr %t6609, i32 0
  store ptr %t6610, ptr %t6611
  %t6612 = call ptr @__alloc(i64 32, i32 3)
  %t6613 = inttoptr i64 33 to ptr
  %t6614 = getelementptr ptr, ptr %t6612, i32 0
  store ptr %t6613, ptr %t6614
  %t6615 = call ptr @__alloc(i64 8, i32 0)
  %t6616 = inttoptr i64 49 to ptr
  %t6617 = getelementptr ptr, ptr %t6615, i32 0
  store ptr %t6616, ptr %t6617
  %t6618 = getelementptr ptr, ptr %t6612, i32 1
  store ptr %t6615, ptr %t6618
  %t6619 = getelementptr ptr, ptr %t6567, i32 2
  %t6620 = load ptr, ptr %t6619
  call void @__inc_ref(ptr %t6620)
  %t6621 = getelementptr ptr, ptr %t6612, i32 2
  store ptr %t6620, ptr %t6621
  %t6622 = getelementptr ptr, ptr %t6567, i32 3
  %t6623 = load ptr, ptr %t6622
  call void @__inc_ref(ptr %t6623)
  %t6624 = getelementptr ptr, ptr %t6612, i32 3
  store ptr %t6623, ptr %t6624
  %t6625 = getelementptr ptr, ptr %t4, i32 1
  %t6626 = load ptr, ptr %t6625
  call void @__free_recursive(ptr %t6626)
  %t6627 = getelementptr ptr, ptr %t4, i32 2
  %t6628 = load ptr, ptr %t6627
  call void @__free_recursive(ptr %t6628)
  %t6631 = inttoptr i64 103 to ptr
  %t6632 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t6631, ptr %t6632
  %t6629 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t6612, ptr %t6629
  call void @__inc_ref(ptr %t6569)
  %t6630 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t6569, ptr %t6630
  %t6633 = getelementptr ptr, ptr %t6609, i32 1
  store ptr %t4, ptr %t6633
  %t6634 = call ptr @__alloc(i64 64, i32 7)
  %t6635 = inttoptr i64 167 to ptr
  %t6636 = getelementptr ptr, ptr %t6634, i32 0
  store ptr %t6635, ptr %t6636
  call void @__inc_ref(ptr %t5254)
  %t6637 = getelementptr ptr, ptr %t6634, i32 1
  store ptr %t5254, ptr %t6637
  call void @__inc_ref(ptr %t6565)
  %t6638 = getelementptr ptr, ptr %t6634, i32 2
  store ptr %t6565, ptr %t6638
  call void @__inc_ref(ptr %t6567)
  %t6639 = getelementptr ptr, ptr %t6634, i32 3
  store ptr %t6567, ptr %t6639
  call void @__inc_ref(ptr %t6569)
  %t6640 = getelementptr ptr, ptr %t6634, i32 4
  store ptr %t6569, ptr %t6640
  call void @__inc_ref(ptr %t6571)
  %t6641 = getelementptr ptr, ptr %t6634, i32 5
  store ptr %t6571, ptr %t6641
  call void @__inc_ref(ptr %t6573)
  %t6642 = getelementptr ptr, ptr %t6634, i32 6
  store ptr %t6573, ptr %t6642
  call void @__inc_ref(ptr %t6575)
  %t6643 = getelementptr ptr, ptr %t6634, i32 7
  store ptr %t6575, ptr %t6643
  %t6644 = getelementptr ptr, ptr %t6609, i32 2
  store ptr %t6634, ptr %t6644
  call void @__free_recursive(ptr %t6575)
  call void @__free_recursive(ptr %t6573)
  call void @__free_recursive(ptr %t6571)
  call void @__free_recursive(ptr %t6569)
  call void @__free_recursive(ptr %t6567)
  call void @__free_recursive(ptr %t6565)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t6609, ptr %t3
  br label %tco.loop.0
tco.case.default.6582:
  unreachable
tco.case.arm.69.6645:
  %t6646 = getelementptr ptr, ptr %t5252, i32 1
  %t6647 = load ptr, ptr %t6646
  call void @__inc_ref(ptr %t6647)
  %t6648 = getelementptr ptr, ptr %t5252, i32 3
  %t6649 = load ptr, ptr %t6648
  call void @__inc_ref(ptr %t6649)
  %t6650 = getelementptr ptr, ptr %t5252, i32 4
  %t6651 = load ptr, ptr %t6650
  call void @__inc_ref(ptr %t6651)
  %t6652 = getelementptr ptr, ptr %t5252, i32 5
  %t6653 = load ptr, ptr %t6652
  call void @__inc_ref(ptr %t6653)
  %t6654 = getelementptr ptr, ptr %t5252, i32 6
  %t6655 = load ptr, ptr %t6654
  call void @__inc_ref(ptr %t6655)
  %t6656 = getelementptr ptr, ptr %t5252, i32 7
  %t6657 = load ptr, ptr %t6656
  call void @__inc_ref(ptr %t6657)
  call void @__inc_ref(ptr %t6647)
  %t6658 = getelementptr ptr, ptr %t6657, i32 1
  %t6659 = load ptr, ptr %t6658
  call void @__inc_ref(ptr %t6659)
  %t6660 = call ptr @__subUInt32(ptr %t6647, ptr %t6659)
  %t6661 = getelementptr ptr, ptr %t6660, i32 0
  %t6662 = load ptr, ptr %t6661
  %t6663 = ptrtoint ptr %t6662 to i64
  switch i64 %t6663, label %tco.case.default.6664 [ i64 3, label %tco.case.arm.3.6665 i64 4, label %tco.case.arm.4.6690 ]
tco.case.arm.3.6665:
  call void @__free_recursive(ptr %t6660)
  %t6666 = call ptr @__alloc(i64 40, i32 4)
  %t6667 = inttoptr i64 79 to ptr
  %t6668 = getelementptr ptr, ptr %t6666, i32 0
  store ptr %t6667, ptr %t6668
  call void @__inc_ref(ptr %t6647)
  %t6669 = getelementptr ptr, ptr %t6666, i32 1
  store ptr %t6647, ptr %t6669
  call void @__inc_ref(ptr %t6649)
  %t6670 = getelementptr ptr, ptr %t6666, i32 2
  store ptr %t6649, ptr %t6670
  %t6671 = getelementptr ptr, ptr %t5252, i32 2
  %t6672 = load ptr, ptr %t6671
  call void @__inc_ref(ptr %t6672)
  %t6673 = getelementptr ptr, ptr %t6666, i32 3
  store ptr %t6672, ptr %t6673
  call void @__inc_ref(ptr %t6653)
  %t6674 = getelementptr ptr, ptr %t6666, i32 4
  store ptr %t6653, ptr %t6674
  %t6675 = call ptr @__alloc(i64 40, i32 4)
  %t6676 = inttoptr i64 169 to ptr
  %t6677 = getelementptr ptr, ptr %t6675, i32 0
  store ptr %t6676, ptr %t6677
  call void @__inc_ref(ptr %t5254)
  %t6678 = getelementptr ptr, ptr %t6675, i32 1
  store ptr %t5254, ptr %t6678
  call void @__inc_ref(ptr %t6649)
  %t6679 = getelementptr ptr, ptr %t6675, i32 2
  store ptr %t6649, ptr %t6679
  call void @__inc_ref(ptr %t6651)
  %t6680 = getelementptr ptr, ptr %t6675, i32 3
  store ptr %t6651, ptr %t6680
  call void @__inc_ref(ptr %t6655)
  %t6681 = getelementptr ptr, ptr %t6675, i32 4
  store ptr %t6655, ptr %t6681
  %t6682 = getelementptr ptr, ptr %t4, i32 1
  %t6683 = load ptr, ptr %t6682
  call void @__free_recursive(ptr %t6683)
  %t6684 = getelementptr ptr, ptr %t4, i32 2
  %t6685 = load ptr, ptr %t6684
  call void @__free_recursive(ptr %t6685)
  %t6688 = inttoptr i64 280 to ptr
  %t6689 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t6688, ptr %t6689
  %t6686 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t6666, ptr %t6686
  %t6687 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t6675, ptr %t6687
  call void @__free_recursive(ptr %t6657)
  call void @__free_recursive(ptr %t6655)
  call void @__free_recursive(ptr %t6653)
  call void @__free_recursive(ptr %t6651)
  call void @__free_recursive(ptr %t6649)
  call void @__free_recursive(ptr %t6647)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.4.6690:
  call void @__free_recursive(ptr %t6660)
  %t6691 = call ptr @__alloc(i64 24, i32 2)
  %t6692 = inttoptr i64 280 to ptr
  %t6693 = getelementptr ptr, ptr %t6691, i32 0
  store ptr %t6692, ptr %t6693
  %t6694 = call ptr @__alloc(i64 32, i32 3)
  %t6695 = inttoptr i64 33 to ptr
  %t6696 = getelementptr ptr, ptr %t6694, i32 0
  store ptr %t6695, ptr %t6696
  %t6697 = call ptr @__alloc(i64 8, i32 0)
  %t6698 = inttoptr i64 49 to ptr
  %t6699 = getelementptr ptr, ptr %t6697, i32 0
  store ptr %t6698, ptr %t6699
  %t6700 = getelementptr ptr, ptr %t6694, i32 1
  store ptr %t6697, ptr %t6700
  %t6701 = getelementptr ptr, ptr %t6649, i32 2
  %t6702 = load ptr, ptr %t6701
  call void @__inc_ref(ptr %t6702)
  %t6703 = getelementptr ptr, ptr %t6694, i32 2
  store ptr %t6702, ptr %t6703
  %t6704 = getelementptr ptr, ptr %t6649, i32 3
  %t6705 = load ptr, ptr %t6704
  call void @__inc_ref(ptr %t6705)
  %t6706 = getelementptr ptr, ptr %t6694, i32 3
  store ptr %t6705, ptr %t6706
  %t6707 = getelementptr ptr, ptr %t4, i32 1
  %t6708 = load ptr, ptr %t6707
  call void @__free_recursive(ptr %t6708)
  %t6709 = getelementptr ptr, ptr %t4, i32 2
  %t6710 = load ptr, ptr %t6709
  call void @__free_recursive(ptr %t6710)
  %t6713 = inttoptr i64 103 to ptr
  %t6714 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t6713, ptr %t6714
  %t6711 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t6694, ptr %t6711
  call void @__inc_ref(ptr %t6651)
  %t6712 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t6651, ptr %t6712
  %t6715 = getelementptr ptr, ptr %t6691, i32 1
  store ptr %t4, ptr %t6715
  %t6716 = call ptr @__alloc(i64 64, i32 7)
  %t6717 = inttoptr i64 172 to ptr
  %t6718 = getelementptr ptr, ptr %t6716, i32 0
  store ptr %t6717, ptr %t6718
  call void @__inc_ref(ptr %t5254)
  %t6719 = getelementptr ptr, ptr %t6716, i32 1
  store ptr %t5254, ptr %t6719
  call void @__inc_ref(ptr %t6647)
  %t6720 = getelementptr ptr, ptr %t6716, i32 2
  store ptr %t6647, ptr %t6720
  call void @__inc_ref(ptr %t6649)
  %t6721 = getelementptr ptr, ptr %t6716, i32 3
  store ptr %t6649, ptr %t6721
  call void @__inc_ref(ptr %t6651)
  %t6722 = getelementptr ptr, ptr %t6716, i32 4
  store ptr %t6651, ptr %t6722
  call void @__inc_ref(ptr %t6653)
  %t6723 = getelementptr ptr, ptr %t6716, i32 5
  store ptr %t6653, ptr %t6723
  call void @__inc_ref(ptr %t6655)
  %t6724 = getelementptr ptr, ptr %t6716, i32 6
  store ptr %t6655, ptr %t6724
  call void @__inc_ref(ptr %t6657)
  %t6725 = getelementptr ptr, ptr %t6716, i32 7
  store ptr %t6657, ptr %t6725
  %t6726 = getelementptr ptr, ptr %t6691, i32 2
  store ptr %t6716, ptr %t6726
  call void @__free_recursive(ptr %t6657)
  call void @__free_recursive(ptr %t6655)
  call void @__free_recursive(ptr %t6653)
  call void @__free_recursive(ptr %t6651)
  call void @__free_recursive(ptr %t6649)
  call void @__free_recursive(ptr %t6647)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t6691, ptr %t3
  br label %tco.loop.0
tco.case.default.6664:
  unreachable
tco.case.arm.70.6727:
  %t6728 = getelementptr ptr, ptr %t5252, i32 1
  %t6729 = load ptr, ptr %t6728
  call void @__inc_ref(ptr %t6729)
  %t6730 = getelementptr ptr, ptr %t6729, i32 0
  %t6731 = load ptr, ptr %t6730
  %t6732 = ptrtoint ptr %t6731 to i64
  switch i64 %t6732, label %tco.case.default.6733 [ i64 5, label %tco.case.arm.5.6734 i64 6, label %tco.case.arm.6.6746 i64 7, label %tco.case.arm.7.6755 i64 8, label %tco.case.arm.8.6777 ]
tco.case.arm.5.6734:
  %t6735 = call ptr @__alloc(i64 16, i32 1)
  %t6736 = inttoptr i64 84 to ptr
  %t6737 = getelementptr ptr, ptr %t6735, i32 0
  store ptr %t6736, ptr %t6737
  %t6738 = getelementptr ptr, ptr %t6729, i32 1
  %t6739 = load ptr, ptr %t6738
  call void @__inc_ref(ptr %t6739)
  %t6740 = getelementptr ptr, ptr %t6735, i32 1
  store ptr %t6739, ptr %t6740
  %t6741 = getelementptr ptr, ptr %t4, i32 1
  %t6742 = load ptr, ptr %t6741
  call void @__free_recursive(ptr %t6742)
  %t6744 = inttoptr i64 280 to ptr
  %t6745 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t6744, ptr %t6745
  %t6743 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t6735, ptr %t6743
  call void @__free_recursive(ptr %t6729)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.6.6746:
  %t6747 = getelementptr ptr, ptr %t4, i32 1
  %t6748 = load ptr, ptr %t6747
  call void @__free_recursive(ptr %t6748)
  %t6749 = getelementptr ptr, ptr %t4, i32 2
  %t6750 = load ptr, ptr %t6749
  call void @__free_recursive(ptr %t6750)
  %t6753 = inttoptr i64 279 to ptr
  %t6754 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t6753, ptr %t6754
  call void @__inc_ref(ptr %t5254)
  %t6751 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t6751
  call void @__inc_ref(ptr %t6729)
  %t6752 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t6729, ptr %t6752
  call void @__free_recursive(ptr %t6729)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.7.6755:
  %t6756 = call ptr @__alloc(i64 24, i32 2)
  %t6757 = inttoptr i64 280 to ptr
  %t6758 = getelementptr ptr, ptr %t6756, i32 0
  store ptr %t6757, ptr %t6758
  %t6759 = call ptr @__alloc(i64 16, i32 1)
  %t6760 = inttoptr i64 70 to ptr
  %t6761 = getelementptr ptr, ptr %t6759, i32 0
  store ptr %t6760, ptr %t6761
  %t6762 = getelementptr ptr, ptr %t6729, i32 2
  %t6763 = load ptr, ptr %t6762
  call void @__inc_ref(ptr %t6763)
  %t6764 = getelementptr ptr, ptr %t6759, i32 1
  store ptr %t6763, ptr %t6764
  %t6765 = getelementptr ptr, ptr %t6756, i32 1
  store ptr %t6759, ptr %t6765
  %t6766 = getelementptr ptr, ptr %t6729, i32 1
  %t6767 = load ptr, ptr %t6766
  call void @__inc_ref(ptr %t6767)
  %t6768 = getelementptr ptr, ptr %t4, i32 1
  %t6769 = load ptr, ptr %t6768
  call void @__free_recursive(ptr %t6769)
  %t6770 = getelementptr ptr, ptr %t4, i32 2
  %t6771 = load ptr, ptr %t6770
  call void @__free_recursive(ptr %t6771)
  %t6774 = inttoptr i64 174 to ptr
  %t6775 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t6774, ptr %t6775
  call void @__inc_ref(ptr %t5254)
  %t6772 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t6772
  %t6773 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t6767, ptr %t6773
  %t6776 = getelementptr ptr, ptr %t6756, i32 2
  store ptr %t4, ptr %t6776
  call void @__free_recursive(ptr %t6729)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t6756, ptr %t3
  br label %tco.loop.0
tco.case.arm.8.6777:
  %t6778 = call ptr @__alloc(i64 16, i32 1)
  %t6779 = inttoptr i64 8 to ptr
  %t6780 = getelementptr ptr, ptr %t6778, i32 0
  store ptr %t6779, ptr %t6780
  %t6781 = call ptr @__alloc(i64 16, i32 1)
  %t6782 = inttoptr i64 43 to ptr
  %t6783 = getelementptr ptr, ptr %t6781, i32 0
  store ptr %t6782, ptr %t6783
  %t6784 = getelementptr ptr, ptr %t6729, i32 1
  %t6785 = load ptr, ptr %t6784
  call void @__inc_ref(ptr %t6785)
  %t6786 = getelementptr ptr, ptr %t6781, i32 1
  store ptr %t6785, ptr %t6786
  %t6787 = getelementptr ptr, ptr %t6778, i32 1
  store ptr %t6781, ptr %t6787
  %t6788 = getelementptr ptr, ptr %t4, i32 1
  %t6789 = load ptr, ptr %t6788
  call void @__free_recursive(ptr %t6789)
  %t6790 = getelementptr ptr, ptr %t4, i32 2
  %t6791 = load ptr, ptr %t6790
  call void @__free_recursive(ptr %t6791)
  %t6794 = inttoptr i64 279 to ptr
  %t6795 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t6794, ptr %t6795
  call void @__inc_ref(ptr %t5254)
  %t6792 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t6792
  %t6793 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t6778, ptr %t6793
  call void @__free_recursive(ptr %t6729)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.6733:
  unreachable
tco.case.arm.71.6796:
  %t6797 = getelementptr ptr, ptr %t5252, i32 1
  %t6798 = load ptr, ptr %t6797
  call void @__inc_ref(ptr %t6798)
  %t6799 = call ptr @__parseUInt32(ptr %t6798)
  %t6800 = getelementptr ptr, ptr %t6799, i32 0
  %t6801 = load ptr, ptr %t6800
  %t6802 = ptrtoint ptr %t6801 to i64
  switch i64 %t6802, label %tco.case.default.6803 [ i64 3, label %tco.case.arm.3.6804 i64 4, label %tco.case.arm.4.6823 ]
tco.case.arm.3.6804:
  %t6805 = getelementptr ptr, ptr %t6799, i32 1
  %t6806 = load ptr, ptr %t6805
  call void @__inc_ref(ptr %t6806)
  call void @__free_recursive(ptr %t6799)
  %t6807 = call ptr @__alloc(i64 16, i32 1)
  %t6808 = inttoptr i64 3 to ptr
  %t6809 = getelementptr ptr, ptr %t6807, i32 0
  store ptr %t6808, ptr %t6809
  %t6810 = call ptr @__alloc(i64 16, i32 1)
  %t6811 = inttoptr i64 2448244154 to ptr
  %t6812 = getelementptr ptr, ptr %t6810, i32 0
  store ptr %t6811, ptr %t6812
  call void @__inc_ref(ptr %t6806)
  %t6813 = getelementptr ptr, ptr %t6810, i32 1
  store ptr %t6806, ptr %t6813
  %t6814 = getelementptr ptr, ptr %t6807, i32 1
  store ptr %t6810, ptr %t6814
  %t6815 = getelementptr ptr, ptr %t4, i32 1
  %t6816 = load ptr, ptr %t6815
  call void @__free_recursive(ptr %t6816)
  %t6817 = getelementptr ptr, ptr %t4, i32 2
  %t6818 = load ptr, ptr %t6817
  call void @__free_recursive(ptr %t6818)
  %t6821 = inttoptr i64 279 to ptr
  %t6822 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t6821, ptr %t6822
  call void @__inc_ref(ptr %t5254)
  %t6819 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t6819
  %t6820 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t6807, ptr %t6820
  call void @__free_recursive(ptr %t6806)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.4.6823:
  %t6824 = getelementptr ptr, ptr %t6799, i32 1
  %t6825 = load ptr, ptr %t6824
  call void @__inc_ref(ptr %t6825)
  call void @__free_recursive(ptr %t6799)
  %t6826 = call ptr @__alloc(i64 24, i32 2)
  %t6827 = inttoptr i64 280 to ptr
  %t6828 = getelementptr ptr, ptr %t6826, i32 0
  store ptr %t6827, ptr %t6828
  %t6829 = getelementptr ptr, ptr %t5252, i32 2
  %t6830 = load ptr, ptr %t6829
  call void @__inc_ref(ptr %t6830)
  %t6831 = getelementptr ptr, ptr %t4, i32 1
  %t6832 = load ptr, ptr %t6831
  call void @__free_recursive(ptr %t6832)
  %t6833 = getelementptr ptr, ptr %t4, i32 2
  %t6834 = load ptr, ptr %t6833
  call void @__free_recursive(ptr %t6834)
  %t6837 = inttoptr i64 86 to ptr
  %t6838 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t6837, ptr %t6838
  call void @__inc_ref(ptr %t6825)
  %t6835 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t6825, ptr %t6835
  %t6836 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t6830, ptr %t6836
  %t6839 = getelementptr ptr, ptr %t6826, i32 1
  store ptr %t4, ptr %t6839
  %t6840 = call ptr @__alloc(i64 16, i32 1)
  %t6841 = inttoptr i64 175 to ptr
  %t6842 = getelementptr ptr, ptr %t6840, i32 0
  store ptr %t6841, ptr %t6842
  call void @__inc_ref(ptr %t5254)
  %t6843 = getelementptr ptr, ptr %t6840, i32 1
  store ptr %t5254, ptr %t6843
  %t6844 = getelementptr ptr, ptr %t6826, i32 2
  store ptr %t6840, ptr %t6844
  call void @__free_recursive(ptr %t6825)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t6826, ptr %t3
  br label %tco.loop.0
tco.case.default.6803:
  unreachable
tco.case.arm.72.6845:
  %t6846 = getelementptr ptr, ptr %t5252, i32 1
  %t6847 = load ptr, ptr %t6846
  call void @__inc_ref(ptr %t6847)
  %t6848 = call ptr @__parseUInt32(ptr %t6847)
  %t6849 = getelementptr ptr, ptr %t6848, i32 0
  %t6850 = load ptr, ptr %t6849
  %t6851 = ptrtoint ptr %t6850 to i64
  switch i64 %t6851, label %tco.case.default.6852 [ i64 3, label %tco.case.arm.3.6853 i64 4, label %tco.case.arm.4.6872 ]
tco.case.arm.3.6853:
  %t6854 = getelementptr ptr, ptr %t6848, i32 1
  %t6855 = load ptr, ptr %t6854
  call void @__inc_ref(ptr %t6855)
  call void @__free_recursive(ptr %t6848)
  %t6856 = call ptr @__alloc(i64 16, i32 1)
  %t6857 = inttoptr i64 3 to ptr
  %t6858 = getelementptr ptr, ptr %t6856, i32 0
  store ptr %t6857, ptr %t6858
  %t6859 = call ptr @__alloc(i64 16, i32 1)
  %t6860 = inttoptr i64 2448244154 to ptr
  %t6861 = getelementptr ptr, ptr %t6859, i32 0
  store ptr %t6860, ptr %t6861
  call void @__inc_ref(ptr %t6855)
  %t6862 = getelementptr ptr, ptr %t6859, i32 1
  store ptr %t6855, ptr %t6862
  %t6863 = getelementptr ptr, ptr %t6856, i32 1
  store ptr %t6859, ptr %t6863
  %t6864 = getelementptr ptr, ptr %t4, i32 1
  %t6865 = load ptr, ptr %t6864
  call void @__free_recursive(ptr %t6865)
  %t6866 = getelementptr ptr, ptr %t4, i32 2
  %t6867 = load ptr, ptr %t6866
  call void @__free_recursive(ptr %t6867)
  %t6870 = inttoptr i64 279 to ptr
  %t6871 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t6870, ptr %t6871
  call void @__inc_ref(ptr %t5254)
  %t6868 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t6868
  %t6869 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t6856, ptr %t6869
  call void @__free_recursive(ptr %t6855)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.4.6872:
  %t6873 = getelementptr ptr, ptr %t6848, i32 1
  %t6874 = load ptr, ptr %t6873
  call void @__inc_ref(ptr %t6874)
  call void @__free_recursive(ptr %t6848)
  %t6875 = call ptr @__alloc(i64 24, i32 2)
  %t6876 = inttoptr i64 280 to ptr
  %t6877 = getelementptr ptr, ptr %t6875, i32 0
  store ptr %t6876, ptr %t6877
  %t6878 = getelementptr ptr, ptr %t5252, i32 2
  %t6879 = load ptr, ptr %t6878
  call void @__inc_ref(ptr %t6879)
  %t6880 = getelementptr ptr, ptr %t4, i32 1
  %t6881 = load ptr, ptr %t6880
  call void @__free_recursive(ptr %t6881)
  %t6882 = getelementptr ptr, ptr %t4, i32 2
  %t6883 = load ptr, ptr %t6882
  call void @__free_recursive(ptr %t6883)
  %t6886 = inttoptr i64 87 to ptr
  %t6887 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t6886, ptr %t6887
  call void @__inc_ref(ptr %t6874)
  %t6884 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t6874, ptr %t6884
  %t6885 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t6879, ptr %t6885
  %t6888 = getelementptr ptr, ptr %t6875, i32 1
  store ptr %t4, ptr %t6888
  %t6889 = call ptr @__alloc(i64 16, i32 1)
  %t6890 = inttoptr i64 176 to ptr
  %t6891 = getelementptr ptr, ptr %t6889, i32 0
  store ptr %t6890, ptr %t6891
  call void @__inc_ref(ptr %t5254)
  %t6892 = getelementptr ptr, ptr %t6889, i32 1
  store ptr %t5254, ptr %t6892
  %t6893 = getelementptr ptr, ptr %t6875, i32 2
  store ptr %t6889, ptr %t6893
  call void @__free_recursive(ptr %t6874)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t6875, ptr %t3
  br label %tco.loop.0
tco.case.default.6852:
  unreachable
tco.case.arm.73.6894:
  %t6895 = getelementptr ptr, ptr %t5252, i32 1
  %t6896 = load ptr, ptr %t6895
  call void @__inc_ref(ptr %t6896)
  %t6897 = getelementptr ptr, ptr %t5252, i32 2
  %t6898 = load ptr, ptr %t6897
  call void @__inc_ref(ptr %t6898)
  %t6899 = getelementptr ptr, ptr %t5252, i32 3
  %t6900 = load ptr, ptr %t6899
  call void @__inc_ref(ptr %t6900)
  %t6901 = getelementptr ptr, ptr %t6898, i32 0
  %t6902 = load ptr, ptr %t6901
  %t6903 = ptrtoint ptr %t6902 to i64
  switch i64 %t6903, label %tco.case.default.6904 [ i64 24, label %tco.case.arm.24.6905 i64 25, label %tco.case.arm.25.6919 i64 26, label %tco.case.arm.26.6944 i64 27, label %tco.case.arm.27.6972 ]
tco.case.arm.24.6905:
  %t6906 = call ptr @__alloc(i64 32, i32 3)
  %t6907 = inttoptr i64 98 to ptr
  %t6908 = getelementptr ptr, ptr %t6906, i32 0
  store ptr %t6907, ptr %t6908
  call void @__inc_ref(ptr %t6896)
  %t6909 = getelementptr ptr, ptr %t6906, i32 1
  store ptr %t6896, ptr %t6909
  %t6910 = getelementptr ptr, ptr %t6898, i32 1
  %t6911 = load ptr, ptr %t6910
  call void @__inc_ref(ptr %t6911)
  %t6912 = getelementptr ptr, ptr %t6906, i32 2
  store ptr %t6911, ptr %t6912
  call void @__inc_ref(ptr %t6900)
  %t6913 = getelementptr ptr, ptr %t6906, i32 3
  store ptr %t6900, ptr %t6913
  %t6914 = getelementptr ptr, ptr %t4, i32 1
  %t6915 = load ptr, ptr %t6914
  call void @__free_recursive(ptr %t6915)
  %t6917 = inttoptr i64 280 to ptr
  %t6918 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t6917, ptr %t6918
  %t6916 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t6906, ptr %t6916
  call void @__free_recursive(ptr %t6900)
  call void @__free_recursive(ptr %t6898)
  call void @__free_recursive(ptr %t6896)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.25.6919:
  %t6920 = call ptr @__alloc(i64 32, i32 3)
  %t6921 = inttoptr i64 98 to ptr
  %t6922 = getelementptr ptr, ptr %t6920, i32 0
  store ptr %t6921, ptr %t6922
  call void @__inc_ref(ptr %t6896)
  %t6923 = getelementptr ptr, ptr %t6920, i32 1
  store ptr %t6896, ptr %t6923
  %t6924 = getelementptr ptr, ptr %t6898, i32 2
  %t6925 = load ptr, ptr %t6924
  call void @__inc_ref(ptr %t6925)
  %t6926 = getelementptr ptr, ptr %t6920, i32 2
  store ptr %t6925, ptr %t6926
  call void @__inc_ref(ptr %t6900)
  %t6927 = getelementptr ptr, ptr %t6920, i32 3
  store ptr %t6900, ptr %t6927
  %t6928 = call ptr @__alloc(i64 32, i32 3)
  %t6929 = inttoptr i64 177 to ptr
  %t6930 = getelementptr ptr, ptr %t6928, i32 0
  store ptr %t6929, ptr %t6930
  call void @__inc_ref(ptr %t5254)
  %t6931 = getelementptr ptr, ptr %t6928, i32 1
  store ptr %t5254, ptr %t6931
  call void @__inc_ref(ptr %t6896)
  %t6932 = getelementptr ptr, ptr %t6928, i32 2
  store ptr %t6896, ptr %t6932
  %t6933 = getelementptr ptr, ptr %t6898, i32 1
  %t6934 = load ptr, ptr %t6933
  call void @__inc_ref(ptr %t6934)
  %t6935 = getelementptr ptr, ptr %t6928, i32 3
  store ptr %t6934, ptr %t6935
  %t6936 = getelementptr ptr, ptr %t4, i32 1
  %t6937 = load ptr, ptr %t6936
  call void @__free_recursive(ptr %t6937)
  %t6938 = getelementptr ptr, ptr %t4, i32 2
  %t6939 = load ptr, ptr %t6938
  call void @__free_recursive(ptr %t6939)
  %t6942 = inttoptr i64 280 to ptr
  %t6943 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t6942, ptr %t6943
  %t6940 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t6920, ptr %t6940
  %t6941 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t6928, ptr %t6941
  call void @__free_recursive(ptr %t6900)
  call void @__free_recursive(ptr %t6898)
  call void @__free_recursive(ptr %t6896)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.26.6944:
  %t6945 = call ptr @__alloc(i64 32, i32 3)
  %t6946 = inttoptr i64 98 to ptr
  %t6947 = getelementptr ptr, ptr %t6945, i32 0
  store ptr %t6946, ptr %t6947
  call void @__inc_ref(ptr %t6896)
  %t6948 = getelementptr ptr, ptr %t6945, i32 1
  store ptr %t6896, ptr %t6948
  %t6949 = getelementptr ptr, ptr %t6898, i32 3
  %t6950 = load ptr, ptr %t6949
  call void @__inc_ref(ptr %t6950)
  %t6951 = getelementptr ptr, ptr %t6945, i32 2
  store ptr %t6950, ptr %t6951
  call void @__inc_ref(ptr %t6900)
  %t6952 = getelementptr ptr, ptr %t6945, i32 3
  store ptr %t6900, ptr %t6952
  %t6953 = call ptr @__alloc(i64 40, i32 4)
  %t6954 = inttoptr i64 178 to ptr
  %t6955 = getelementptr ptr, ptr %t6953, i32 0
  store ptr %t6954, ptr %t6955
  call void @__inc_ref(ptr %t5254)
  %t6956 = getelementptr ptr, ptr %t6953, i32 1
  store ptr %t5254, ptr %t6956
  call void @__inc_ref(ptr %t6896)
  %t6957 = getelementptr ptr, ptr %t6953, i32 2
  store ptr %t6896, ptr %t6957
  %t6958 = getelementptr ptr, ptr %t6898, i32 1
  %t6959 = load ptr, ptr %t6958
  call void @__inc_ref(ptr %t6959)
  %t6960 = getelementptr ptr, ptr %t6953, i32 3
  store ptr %t6959, ptr %t6960
  %t6961 = getelementptr ptr, ptr %t6898, i32 2
  %t6962 = load ptr, ptr %t6961
  call void @__inc_ref(ptr %t6962)
  %t6963 = getelementptr ptr, ptr %t6953, i32 4
  store ptr %t6962, ptr %t6963
  %t6964 = getelementptr ptr, ptr %t4, i32 1
  %t6965 = load ptr, ptr %t6964
  call void @__free_recursive(ptr %t6965)
  %t6966 = getelementptr ptr, ptr %t4, i32 2
  %t6967 = load ptr, ptr %t6966
  call void @__free_recursive(ptr %t6967)
  %t6970 = inttoptr i64 280 to ptr
  %t6971 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t6970, ptr %t6971
  %t6968 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t6945, ptr %t6968
  %t6969 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t6953, ptr %t6969
  call void @__free_recursive(ptr %t6900)
  call void @__free_recursive(ptr %t6898)
  call void @__free_recursive(ptr %t6896)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.27.6972:
  %t6973 = call ptr @__alloc(i64 32, i32 3)
  %t6974 = inttoptr i64 98 to ptr
  %t6975 = getelementptr ptr, ptr %t6973, i32 0
  store ptr %t6974, ptr %t6975
  call void @__inc_ref(ptr %t6896)
  %t6976 = getelementptr ptr, ptr %t6973, i32 1
  store ptr %t6896, ptr %t6976
  %t6977 = getelementptr ptr, ptr %t6898, i32 4
  %t6978 = load ptr, ptr %t6977
  call void @__inc_ref(ptr %t6978)
  %t6979 = getelementptr ptr, ptr %t6973, i32 2
  store ptr %t6978, ptr %t6979
  call void @__inc_ref(ptr %t6900)
  %t6980 = getelementptr ptr, ptr %t6973, i32 3
  store ptr %t6900, ptr %t6980
  %t6981 = call ptr @__alloc(i64 48, i32 5)
  %t6982 = inttoptr i64 180 to ptr
  %t6983 = getelementptr ptr, ptr %t6981, i32 0
  store ptr %t6982, ptr %t6983
  call void @__inc_ref(ptr %t5254)
  %t6984 = getelementptr ptr, ptr %t6981, i32 1
  store ptr %t5254, ptr %t6984
  call void @__inc_ref(ptr %t6896)
  %t6985 = getelementptr ptr, ptr %t6981, i32 2
  store ptr %t6896, ptr %t6985
  %t6986 = getelementptr ptr, ptr %t6898, i32 1
  %t6987 = load ptr, ptr %t6986
  call void @__inc_ref(ptr %t6987)
  %t6988 = getelementptr ptr, ptr %t6981, i32 3
  store ptr %t6987, ptr %t6988
  %t6989 = getelementptr ptr, ptr %t6898, i32 2
  %t6990 = load ptr, ptr %t6989
  call void @__inc_ref(ptr %t6990)
  %t6991 = getelementptr ptr, ptr %t6981, i32 4
  store ptr %t6990, ptr %t6991
  %t6992 = getelementptr ptr, ptr %t6898, i32 3
  %t6993 = load ptr, ptr %t6992
  call void @__inc_ref(ptr %t6993)
  %t6994 = getelementptr ptr, ptr %t6981, i32 5
  store ptr %t6993, ptr %t6994
  %t6995 = getelementptr ptr, ptr %t4, i32 1
  %t6996 = load ptr, ptr %t6995
  call void @__free_recursive(ptr %t6996)
  %t6997 = getelementptr ptr, ptr %t4, i32 2
  %t6998 = load ptr, ptr %t6997
  call void @__free_recursive(ptr %t6998)
  %t7001 = inttoptr i64 280 to ptr
  %t7002 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t7001, ptr %t7002
  %t6999 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t6973, ptr %t6999
  %t7000 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t6981, ptr %t7000
  call void @__free_recursive(ptr %t6900)
  call void @__free_recursive(ptr %t6898)
  call void @__free_recursive(ptr %t6896)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.6904:
  unreachable
tco.case.arm.74.7003:
  %t7004 = getelementptr ptr, ptr %t5252, i32 1
  %t7005 = load ptr, ptr %t7004
  call void @__inc_ref(ptr %t7005)
  %t7006 = getelementptr ptr, ptr %t5252, i32 2
  %t7007 = load ptr, ptr %t7006
  call void @__inc_ref(ptr %t7007)
  %t7008 = getelementptr ptr, ptr %t5252, i32 3
  %t7009 = load ptr, ptr %t7008
  call void @__inc_ref(ptr %t7009)
  %t7010 = getelementptr ptr, ptr %t7007, i32 0
  %t7011 = load ptr, ptr %t7010
  %t7012 = ptrtoint ptr %t7011 to i64
  switch i64 %t7012, label %tco.case.default.7013 [ i64 30, label %tco.case.arm.30.7014 i64 31, label %tco.case.arm.31.7023 i64 32, label %tco.case.arm.32.7037 ]
tco.case.arm.30.7014:
  %t7015 = getelementptr ptr, ptr %t4, i32 1
  %t7016 = load ptr, ptr %t7015
  call void @__free_recursive(ptr %t7016)
  %t7017 = getelementptr ptr, ptr %t4, i32 2
  %t7018 = load ptr, ptr %t7017
  call void @__free_recursive(ptr %t7018)
  %t7021 = inttoptr i64 279 to ptr
  %t7022 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t7021, ptr %t7022
  call void @__inc_ref(ptr %t5254)
  %t7019 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t7019
  call void @__inc_ref(ptr %t7009)
  %t7020 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t7009, ptr %t7020
  call void @__free_recursive(ptr %t7009)
  call void @__free_recursive(ptr %t7007)
  call void @__free_recursive(ptr %t7005)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.31.7023:
  %t7024 = call ptr @__alloc(i64 32, i32 3)
  %t7025 = inttoptr i64 98 to ptr
  %t7026 = getelementptr ptr, ptr %t7024, i32 0
  store ptr %t7025, ptr %t7026
  call void @__inc_ref(ptr %t7005)
  %t7027 = getelementptr ptr, ptr %t7024, i32 1
  store ptr %t7005, ptr %t7027
  %t7028 = getelementptr ptr, ptr %t7007, i32 1
  %t7029 = load ptr, ptr %t7028
  call void @__inc_ref(ptr %t7029)
  %t7030 = getelementptr ptr, ptr %t7024, i32 2
  store ptr %t7029, ptr %t7030
  call void @__inc_ref(ptr %t7009)
  %t7031 = getelementptr ptr, ptr %t7024, i32 3
  store ptr %t7009, ptr %t7031
  %t7032 = getelementptr ptr, ptr %t4, i32 1
  %t7033 = load ptr, ptr %t7032
  call void @__free_recursive(ptr %t7033)
  %t7035 = inttoptr i64 280 to ptr
  %t7036 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t7035, ptr %t7036
  %t7034 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t7024, ptr %t7034
  call void @__free_recursive(ptr %t7009)
  call void @__free_recursive(ptr %t7007)
  call void @__free_recursive(ptr %t7005)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.32.7037:
  %t7038 = call ptr @__alloc(i64 32, i32 3)
  %t7039 = inttoptr i64 73 to ptr
  %t7040 = getelementptr ptr, ptr %t7038, i32 0
  store ptr %t7039, ptr %t7040
  call void @__inc_ref(ptr %t7005)
  %t7041 = getelementptr ptr, ptr %t7038, i32 1
  store ptr %t7005, ptr %t7041
  %t7042 = getelementptr ptr, ptr %t7007, i32 4
  %t7043 = load ptr, ptr %t7042
  call void @__inc_ref(ptr %t7043)
  %t7044 = getelementptr ptr, ptr %t7038, i32 2
  store ptr %t7043, ptr %t7044
  call void @__inc_ref(ptr %t7009)
  %t7045 = getelementptr ptr, ptr %t7038, i32 3
  store ptr %t7009, ptr %t7045
  %t7046 = call ptr @__alloc(i64 40, i32 4)
  %t7047 = inttoptr i64 183 to ptr
  %t7048 = getelementptr ptr, ptr %t7046, i32 0
  store ptr %t7047, ptr %t7048
  call void @__inc_ref(ptr %t5254)
  %t7049 = getelementptr ptr, ptr %t7046, i32 1
  store ptr %t5254, ptr %t7049
  call void @__inc_ref(ptr %t7005)
  %t7050 = getelementptr ptr, ptr %t7046, i32 2
  store ptr %t7005, ptr %t7050
  %t7051 = getelementptr ptr, ptr %t7007, i32 3
  %t7052 = load ptr, ptr %t7051
  call void @__inc_ref(ptr %t7052)
  %t7053 = getelementptr ptr, ptr %t7046, i32 3
  store ptr %t7052, ptr %t7053
  %t7054 = getelementptr ptr, ptr %t7007, i32 2
  %t7055 = load ptr, ptr %t7054
  call void @__inc_ref(ptr %t7055)
  %t7056 = getelementptr ptr, ptr %t7046, i32 4
  store ptr %t7055, ptr %t7056
  %t7057 = getelementptr ptr, ptr %t4, i32 1
  %t7058 = load ptr, ptr %t7057
  call void @__free_recursive(ptr %t7058)
  %t7059 = getelementptr ptr, ptr %t4, i32 2
  %t7060 = load ptr, ptr %t7059
  call void @__free_recursive(ptr %t7060)
  %t7063 = inttoptr i64 280 to ptr
  %t7064 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t7063, ptr %t7064
  %t7061 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t7038, ptr %t7061
  %t7062 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t7046, ptr %t7062
  call void @__free_recursive(ptr %t7009)
  call void @__free_recursive(ptr %t7007)
  call void @__free_recursive(ptr %t7005)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.7013:
  unreachable
tco.case.arm.75.7065:
  %t7066 = getelementptr ptr, ptr %t5252, i32 1
  %t7067 = load ptr, ptr %t7066
  call void @__inc_ref(ptr %t7067)
  %t7068 = getelementptr ptr, ptr %t5252, i32 2
  %t7069 = load ptr, ptr %t7068
  call void @__inc_ref(ptr %t7069)
  %t7070 = getelementptr ptr, ptr %t7067, i32 0
  %t7071 = load ptr, ptr %t7070
  %t7072 = ptrtoint ptr %t7071 to i64
  switch i64 %t7072, label %tco.case.default.7073 [ i64 30, label %tco.case.arm.30.7074 i64 31, label %tco.case.arm.31.7083 i64 32, label %tco.case.arm.32.7099 ]
tco.case.arm.30.7074:
  %t7075 = getelementptr ptr, ptr %t4, i32 1
  %t7076 = load ptr, ptr %t7075
  call void @__free_recursive(ptr %t7076)
  %t7077 = getelementptr ptr, ptr %t4, i32 2
  %t7078 = load ptr, ptr %t7077
  call void @__free_recursive(ptr %t7078)
  %t7081 = inttoptr i64 279 to ptr
  %t7082 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t7081, ptr %t7082
  call void @__inc_ref(ptr %t5254)
  %t7079 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t7079
  call void @__inc_ref(ptr %t7069)
  %t7080 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t7069, ptr %t7080
  call void @__free_recursive(ptr %t7069)
  call void @__free_recursive(ptr %t7067)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.31.7083:
  %t7084 = call ptr @__alloc(i64 24, i32 2)
  %t7085 = inttoptr i64 279 to ptr
  %t7086 = getelementptr ptr, ptr %t7084, i32 0
  store ptr %t7085, ptr %t7086
  call void @__inc_ref(ptr %t5254)
  %t7087 = getelementptr ptr, ptr %t7084, i32 1
  store ptr %t5254, ptr %t7087
  %t7088 = getelementptr ptr, ptr %t7067, i32 1
  %t7089 = load ptr, ptr %t7088
  call void @__inc_ref(ptr %t7089)
  %t7090 = getelementptr ptr, ptr %t4, i32 1
  %t7091 = load ptr, ptr %t7090
  call void @__free_recursive(ptr %t7091)
  %t7092 = getelementptr ptr, ptr %t4, i32 2
  %t7093 = load ptr, ptr %t7092
  call void @__free_recursive(ptr %t7093)
  %t7096 = inttoptr i64 14 to ptr
  %t7097 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t7096, ptr %t7097
  %t7094 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t7089, ptr %t7094
  call void @__inc_ref(ptr %t7069)
  %t7095 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t7069, ptr %t7095
  %t7098 = getelementptr ptr, ptr %t7084, i32 2
  store ptr %t4, ptr %t7098
  call void @__free_recursive(ptr %t7069)
  call void @__free_recursive(ptr %t7067)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t7084, ptr %t3
  br label %tco.loop.0
tco.case.arm.32.7099:
  %t7100 = call ptr @__alloc(i64 24, i32 2)
  %t7101 = inttoptr i64 280 to ptr
  %t7102 = getelementptr ptr, ptr %t7100, i32 0
  store ptr %t7101, ptr %t7102
  %t7103 = call ptr @__alloc(i64 32, i32 3)
  %t7104 = inttoptr i64 74 to ptr
  %t7105 = getelementptr ptr, ptr %t7103, i32 0
  store ptr %t7104, ptr %t7105
  %t7106 = call ptr @__alloc(i64 8, i32 0)
  %t7107 = inttoptr i64 50 to ptr
  %t7108 = getelementptr ptr, ptr %t7106, i32 0
  store ptr %t7107, ptr %t7108
  %t7109 = getelementptr ptr, ptr %t7103, i32 1
  store ptr %t7106, ptr %t7109
  %t7110 = getelementptr ptr, ptr %t7067, i32 3
  %t7111 = load ptr, ptr %t7110
  call void @__inc_ref(ptr %t7111)
  %t7112 = getelementptr ptr, ptr %t7103, i32 2
  store ptr %t7111, ptr %t7112
  %t7113 = getelementptr ptr, ptr %t7067, i32 4
  %t7114 = load ptr, ptr %t7113
  call void @__inc_ref(ptr %t7114)
  call void @__inc_ref(ptr %t7069)
  %t7115 = call ptr @v_$df$foldDigit$12(ptr %t7114, ptr %t7069)
  %t7116 = getelementptr ptr, ptr %t7103, i32 3
  store ptr %t7115, ptr %t7116
  %t7117 = getelementptr ptr, ptr %t7100, i32 1
  store ptr %t7103, ptr %t7117
  %t7118 = getelementptr ptr, ptr %t7067, i32 2
  %t7119 = load ptr, ptr %t7118
  call void @__inc_ref(ptr %t7119)
  %t7120 = getelementptr ptr, ptr %t4, i32 1
  %t7121 = load ptr, ptr %t7120
  call void @__free_recursive(ptr %t7121)
  %t7122 = getelementptr ptr, ptr %t4, i32 2
  %t7123 = load ptr, ptr %t7122
  call void @__free_recursive(ptr %t7123)
  %t7126 = inttoptr i64 185 to ptr
  %t7127 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t7126, ptr %t7127
  call void @__inc_ref(ptr %t5254)
  %t7124 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t7124
  %t7125 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t7119, ptr %t7125
  %t7128 = getelementptr ptr, ptr %t7100, i32 2
  store ptr %t4, ptr %t7128
  call void @__free_recursive(ptr %t7069)
  call void @__free_recursive(ptr %t7067)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t7100, ptr %t3
  br label %tco.loop.0
tco.case.default.7073:
  unreachable
tco.case.arm.76.7129:
  %t7130 = getelementptr ptr, ptr %t5252, i32 2
  %t7131 = load ptr, ptr %t7130
  call void @__inc_ref(ptr %t7131)
  %t7132 = call ptr @__alloc(i64 24, i32 2)
  %t7133 = inttoptr i64 280 to ptr
  %t7134 = getelementptr ptr, ptr %t7132, i32 0
  store ptr %t7133, ptr %t7134
  %t7135 = call ptr @v_lineMeasure()
  %t7136 = getelementptr ptr, ptr %t4, i32 1
  %t7137 = load ptr, ptr %t7136
  call void @__free_recursive(ptr %t7137)
  %t7138 = getelementptr ptr, ptr %t4, i32 2
  %t7139 = load ptr, ptr %t7138
  call void @__free_recursive(ptr %t7139)
  %t7142 = inttoptr i64 103 to ptr
  %t7143 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t7142, ptr %t7143
  %t7140 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t7135, ptr %t7140
  call void @__inc_ref(ptr %t7131)
  %t7141 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t7131, ptr %t7141
  %t7144 = getelementptr ptr, ptr %t7132, i32 1
  store ptr %t4, ptr %t7144
  %t7145 = call ptr @__alloc(i64 32, i32 3)
  %t7146 = inttoptr i64 186 to ptr
  %t7147 = getelementptr ptr, ptr %t7145, i32 0
  store ptr %t7146, ptr %t7147
  call void @__inc_ref(ptr %t5254)
  %t7148 = getelementptr ptr, ptr %t7145, i32 1
  store ptr %t5254, ptr %t7148
  %t7149 = getelementptr ptr, ptr %t5252, i32 1
  %t7150 = load ptr, ptr %t7149
  call void @__inc_ref(ptr %t7150)
  %t7151 = getelementptr ptr, ptr %t7145, i32 2
  store ptr %t7150, ptr %t7151
  call void @__inc_ref(ptr %t7131)
  %t7152 = getelementptr ptr, ptr %t7145, i32 3
  store ptr %t7131, ptr %t7152
  %t7153 = getelementptr ptr, ptr %t7132, i32 2
  store ptr %t7145, ptr %t7153
  call void @__free_recursive(ptr %t7131)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t7132, ptr %t3
  br label %tco.loop.0
tco.case.arm.77.7154:
  %t7155 = getelementptr ptr, ptr %t5252, i32 2
  %t7156 = load ptr, ptr %t7155
  call void @__inc_ref(ptr %t7156)
  %t7157 = call ptr @__alloc(i64 24, i32 2)
  %t7158 = inttoptr i64 280 to ptr
  %t7159 = getelementptr ptr, ptr %t7157, i32 0
  store ptr %t7158, ptr %t7159
  %t7160 = call ptr @v_lineMeasure()
  %t7161 = getelementptr ptr, ptr %t4, i32 1
  %t7162 = load ptr, ptr %t7161
  call void @__free_recursive(ptr %t7162)
  %t7163 = getelementptr ptr, ptr %t4, i32 2
  %t7164 = load ptr, ptr %t7163
  call void @__free_recursive(ptr %t7164)
  %t7167 = inttoptr i64 103 to ptr
  %t7168 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t7167, ptr %t7168
  %t7165 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t7160, ptr %t7165
  call void @__inc_ref(ptr %t7156)
  %t7166 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t7156, ptr %t7166
  %t7169 = getelementptr ptr, ptr %t7157, i32 1
  store ptr %t4, ptr %t7169
  %t7170 = call ptr @__alloc(i64 32, i32 3)
  %t7171 = inttoptr i64 187 to ptr
  %t7172 = getelementptr ptr, ptr %t7170, i32 0
  store ptr %t7171, ptr %t7172
  call void @__inc_ref(ptr %t5254)
  %t7173 = getelementptr ptr, ptr %t7170, i32 1
  store ptr %t5254, ptr %t7173
  %t7174 = getelementptr ptr, ptr %t5252, i32 1
  %t7175 = load ptr, ptr %t7174
  call void @__inc_ref(ptr %t7175)
  %t7176 = getelementptr ptr, ptr %t7170, i32 2
  store ptr %t7175, ptr %t7176
  call void @__inc_ref(ptr %t7156)
  %t7177 = getelementptr ptr, ptr %t7170, i32 3
  store ptr %t7156, ptr %t7177
  %t7178 = getelementptr ptr, ptr %t7157, i32 2
  store ptr %t7170, ptr %t7178
  call void @__free_recursive(ptr %t7156)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t7157, ptr %t3
  br label %tco.loop.0
tco.case.arm.78.7179:
  %t7180 = getelementptr ptr, ptr %t5252, i32 1
  %t7181 = load ptr, ptr %t7180
  call void @__inc_ref(ptr %t7181)
  %t7182 = getelementptr ptr, ptr %t5252, i32 2
  %t7183 = load ptr, ptr %t7182
  call void @__inc_ref(ptr %t7183)
  %t7184 = getelementptr ptr, ptr %t5252, i32 3
  %t7185 = load ptr, ptr %t7184
  call void @__inc_ref(ptr %t7185)
  %t7186 = getelementptr ptr, ptr %t5252, i32 4
  %t7187 = load ptr, ptr %t7186
  call void @__inc_ref(ptr %t7187)
  %t7188 = getelementptr ptr, ptr %t7187, i32 0
  %t7189 = load ptr, ptr %t7188
  %t7190 = ptrtoint ptr %t7189 to i64
  switch i64 %t7190, label %tco.case.default.7191 [ i64 24, label %tco.case.arm.24.7192 i64 25, label %tco.case.arm.25.7215 i64 26, label %tco.case.arm.26.7242 i64 27, label %tco.case.arm.27.7272 ]
tco.case.arm.24.7192:
  %t7193 = call ptr @__alloc(i64 32, i32 3)
  %t7194 = inttoptr i64 34 to ptr
  %t7195 = getelementptr ptr, ptr %t7193, i32 0
  store ptr %t7194, ptr %t7195
  %t7196 = call ptr @__alloc(i64 8, i32 0)
  %t7197 = inttoptr i64 11 to ptr
  %t7198 = getelementptr ptr, ptr %t7196, i32 0
  store ptr %t7197, ptr %t7198
  %t7199 = getelementptr ptr, ptr %t7193, i32 1
  store ptr %t7196, ptr %t7199
  %t7200 = getelementptr ptr, ptr %t7187, i32 1
  %t7201 = load ptr, ptr %t7200
  call void @__inc_ref(ptr %t7201)
  %t7202 = getelementptr ptr, ptr %t7193, i32 2
  store ptr %t7201, ptr %t7202
  %t7203 = call ptr @__alloc(i64 8, i32 0)
  %t7204 = inttoptr i64 11 to ptr
  %t7205 = getelementptr ptr, ptr %t7203, i32 0
  store ptr %t7204, ptr %t7205
  %t7206 = getelementptr ptr, ptr %t7193, i32 3
  store ptr %t7203, ptr %t7206
  %t7207 = getelementptr ptr, ptr %t4, i32 1
  %t7208 = load ptr, ptr %t7207
  call void @__free_recursive(ptr %t7208)
  %t7209 = getelementptr ptr, ptr %t4, i32 2
  %t7210 = load ptr, ptr %t7209
  call void @__free_recursive(ptr %t7210)
  %t7213 = inttoptr i64 279 to ptr
  %t7214 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t7213, ptr %t7214
  call void @__inc_ref(ptr %t5254)
  %t7211 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t7211
  %t7212 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t7193, ptr %t7212
  call void @__free_recursive(ptr %t7187)
  call void @__free_recursive(ptr %t7185)
  call void @__free_recursive(ptr %t7183)
  call void @__free_recursive(ptr %t7181)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.25.7215:
  %t7216 = getelementptr ptr, ptr %t7187, i32 1
  %t7217 = load ptr, ptr %t7216
  call void @__inc_ref(ptr %t7217)
  %t7218 = call ptr @__alloc(i64 24, i32 2)
  %t7219 = inttoptr i64 280 to ptr
  %t7220 = getelementptr ptr, ptr %t7218, i32 0
  store ptr %t7219, ptr %t7220
  %t7221 = getelementptr ptr, ptr %t4, i32 1
  %t7222 = load ptr, ptr %t7221
  call void @__free_recursive(ptr %t7222)
  %t7223 = getelementptr ptr, ptr %t4, i32 2
  %t7224 = load ptr, ptr %t7223
  call void @__free_recursive(ptr %t7224)
  %t7227 = inttoptr i64 101 to ptr
  %t7228 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t7227, ptr %t7228
  call void @__inc_ref(ptr %t7183)
  %t7225 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t7183, ptr %t7225
  call void @__inc_ref(ptr %t7217)
  %t7226 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t7217, ptr %t7226
  %t7229 = getelementptr ptr, ptr %t7218, i32 1
  store ptr %t4, ptr %t7229
  %t7230 = call ptr @__alloc(i64 56, i32 6)
  %t7231 = inttoptr i64 188 to ptr
  %t7232 = getelementptr ptr, ptr %t7230, i32 0
  store ptr %t7231, ptr %t7232
  call void @__inc_ref(ptr %t5254)
  %t7233 = getelementptr ptr, ptr %t7230, i32 1
  store ptr %t5254, ptr %t7233
  call void @__inc_ref(ptr %t7181)
  %t7234 = getelementptr ptr, ptr %t7230, i32 2
  store ptr %t7181, ptr %t7234
  call void @__inc_ref(ptr %t7217)
  %t7235 = getelementptr ptr, ptr %t7230, i32 3
  store ptr %t7217, ptr %t7235
  call void @__inc_ref(ptr %t7185)
  %t7236 = getelementptr ptr, ptr %t7230, i32 4
  store ptr %t7185, ptr %t7236
  %t7237 = getelementptr ptr, ptr %t7187, i32 2
  %t7238 = load ptr, ptr %t7237
  call void @__inc_ref(ptr %t7238)
  %t7239 = getelementptr ptr, ptr %t7230, i32 5
  store ptr %t7238, ptr %t7239
  call void @__inc_ref(ptr %t7183)
  %t7240 = getelementptr ptr, ptr %t7230, i32 6
  store ptr %t7183, ptr %t7240
  %t7241 = getelementptr ptr, ptr %t7218, i32 2
  store ptr %t7230, ptr %t7241
  call void @__free_recursive(ptr %t7217)
  call void @__free_recursive(ptr %t7187)
  call void @__free_recursive(ptr %t7185)
  call void @__free_recursive(ptr %t7183)
  call void @__free_recursive(ptr %t7181)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t7218, ptr %t3
  br label %tco.loop.0
tco.case.arm.26.7242:
  %t7243 = getelementptr ptr, ptr %t7187, i32 1
  %t7244 = load ptr, ptr %t7243
  call void @__inc_ref(ptr %t7244)
  %t7245 = call ptr @__alloc(i64 24, i32 2)
  %t7246 = inttoptr i64 280 to ptr
  %t7247 = getelementptr ptr, ptr %t7245, i32 0
  store ptr %t7246, ptr %t7247
  %t7248 = getelementptr ptr, ptr %t4, i32 1
  %t7249 = load ptr, ptr %t7248
  call void @__free_recursive(ptr %t7249)
  %t7250 = getelementptr ptr, ptr %t4, i32 2
  %t7251 = load ptr, ptr %t7250
  call void @__free_recursive(ptr %t7251)
  %t7254 = inttoptr i64 101 to ptr
  %t7255 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t7254, ptr %t7255
  call void @__inc_ref(ptr %t7183)
  %t7252 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t7183, ptr %t7252
  call void @__inc_ref(ptr %t7244)
  %t7253 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t7244, ptr %t7253
  %t7256 = getelementptr ptr, ptr %t7245, i32 1
  store ptr %t4, ptr %t7256
  %t7257 = call ptr @__alloc(i64 64, i32 7)
  %t7258 = inttoptr i64 190 to ptr
  %t7259 = getelementptr ptr, ptr %t7257, i32 0
  store ptr %t7258, ptr %t7259
  call void @__inc_ref(ptr %t5254)
  %t7260 = getelementptr ptr, ptr %t7257, i32 1
  store ptr %t5254, ptr %t7260
  call void @__inc_ref(ptr %t7181)
  %t7261 = getelementptr ptr, ptr %t7257, i32 2
  store ptr %t7181, ptr %t7261
  call void @__inc_ref(ptr %t7244)
  %t7262 = getelementptr ptr, ptr %t7257, i32 3
  store ptr %t7244, ptr %t7262
  call void @__inc_ref(ptr %t7185)
  %t7263 = getelementptr ptr, ptr %t7257, i32 4
  store ptr %t7185, ptr %t7263
  %t7264 = getelementptr ptr, ptr %t7187, i32 2
  %t7265 = load ptr, ptr %t7264
  call void @__inc_ref(ptr %t7265)
  %t7266 = getelementptr ptr, ptr %t7257, i32 5
  store ptr %t7265, ptr %t7266
  %t7267 = getelementptr ptr, ptr %t7187, i32 3
  %t7268 = load ptr, ptr %t7267
  call void @__inc_ref(ptr %t7268)
  %t7269 = getelementptr ptr, ptr %t7257, i32 6
  store ptr %t7268, ptr %t7269
  call void @__inc_ref(ptr %t7183)
  %t7270 = getelementptr ptr, ptr %t7257, i32 7
  store ptr %t7183, ptr %t7270
  %t7271 = getelementptr ptr, ptr %t7245, i32 2
  store ptr %t7257, ptr %t7271
  call void @__free_recursive(ptr %t7244)
  call void @__free_recursive(ptr %t7187)
  call void @__free_recursive(ptr %t7185)
  call void @__free_recursive(ptr %t7183)
  call void @__free_recursive(ptr %t7181)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t7245, ptr %t3
  br label %tco.loop.0
tco.case.arm.27.7272:
  %t7273 = getelementptr ptr, ptr %t7187, i32 1
  %t7274 = load ptr, ptr %t7273
  call void @__inc_ref(ptr %t7274)
  %t7275 = call ptr @__alloc(i64 24, i32 2)
  %t7276 = inttoptr i64 280 to ptr
  %t7277 = getelementptr ptr, ptr %t7275, i32 0
  store ptr %t7276, ptr %t7277
  %t7278 = getelementptr ptr, ptr %t4, i32 1
  %t7279 = load ptr, ptr %t7278
  call void @__free_recursive(ptr %t7279)
  %t7280 = getelementptr ptr, ptr %t4, i32 2
  %t7281 = load ptr, ptr %t7280
  call void @__free_recursive(ptr %t7281)
  %t7284 = inttoptr i64 101 to ptr
  %t7285 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t7284, ptr %t7285
  call void @__inc_ref(ptr %t7183)
  %t7282 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t7183, ptr %t7282
  call void @__inc_ref(ptr %t7274)
  %t7283 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t7274, ptr %t7283
  %t7286 = getelementptr ptr, ptr %t7275, i32 1
  store ptr %t4, ptr %t7286
  %t7287 = call ptr @__alloc(i64 72, i32 8)
  %t7288 = inttoptr i64 192 to ptr
  %t7289 = getelementptr ptr, ptr %t7287, i32 0
  store ptr %t7288, ptr %t7289
  call void @__inc_ref(ptr %t5254)
  %t7290 = getelementptr ptr, ptr %t7287, i32 1
  store ptr %t5254, ptr %t7290
  call void @__inc_ref(ptr %t7181)
  %t7291 = getelementptr ptr, ptr %t7287, i32 2
  store ptr %t7181, ptr %t7291
  call void @__inc_ref(ptr %t7274)
  %t7292 = getelementptr ptr, ptr %t7287, i32 3
  store ptr %t7274, ptr %t7292
  call void @__inc_ref(ptr %t7185)
  %t7293 = getelementptr ptr, ptr %t7287, i32 4
  store ptr %t7185, ptr %t7293
  %t7294 = getelementptr ptr, ptr %t7187, i32 2
  %t7295 = load ptr, ptr %t7294
  call void @__inc_ref(ptr %t7295)
  %t7296 = getelementptr ptr, ptr %t7287, i32 5
  store ptr %t7295, ptr %t7296
  %t7297 = getelementptr ptr, ptr %t7187, i32 3
  %t7298 = load ptr, ptr %t7297
  call void @__inc_ref(ptr %t7298)
  %t7299 = getelementptr ptr, ptr %t7287, i32 6
  store ptr %t7298, ptr %t7299
  %t7300 = getelementptr ptr, ptr %t7187, i32 4
  %t7301 = load ptr, ptr %t7300
  call void @__inc_ref(ptr %t7301)
  %t7302 = getelementptr ptr, ptr %t7287, i32 7
  store ptr %t7301, ptr %t7302
  call void @__inc_ref(ptr %t7183)
  %t7303 = getelementptr ptr, ptr %t7287, i32 8
  store ptr %t7183, ptr %t7303
  %t7304 = getelementptr ptr, ptr %t7275, i32 2
  store ptr %t7287, ptr %t7304
  call void @__free_recursive(ptr %t7274)
  call void @__free_recursive(ptr %t7187)
  call void @__free_recursive(ptr %t7185)
  call void @__free_recursive(ptr %t7183)
  call void @__free_recursive(ptr %t7181)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t7275, ptr %t3
  br label %tco.loop.0
tco.case.default.7191:
  unreachable
tco.case.arm.79.7305:
  %t7306 = getelementptr ptr, ptr %t5252, i32 1
  %t7307 = load ptr, ptr %t7306
  call void @__inc_ref(ptr %t7307)
  %t7308 = getelementptr ptr, ptr %t5252, i32 2
  %t7309 = load ptr, ptr %t7308
  call void @__inc_ref(ptr %t7309)
  %t7310 = getelementptr ptr, ptr %t5252, i32 3
  %t7311 = load ptr, ptr %t7310
  call void @__inc_ref(ptr %t7311)
  %t7312 = getelementptr ptr, ptr %t5252, i32 4
  %t7313 = load ptr, ptr %t7312
  call void @__inc_ref(ptr %t7313)
  %t7314 = getelementptr ptr, ptr %t7313, i32 0
  %t7315 = load ptr, ptr %t7314
  %t7316 = ptrtoint ptr %t7315 to i64
  switch i64 %t7316, label %tco.case.default.7317 [ i64 24, label %tco.case.arm.24.7318 i64 25, label %tco.case.arm.25.7341 i64 26, label %tco.case.arm.26.7368 i64 27, label %tco.case.arm.27.7398 ]
tco.case.arm.24.7318:
  %t7319 = call ptr @__alloc(i64 32, i32 3)
  %t7320 = inttoptr i64 34 to ptr
  %t7321 = getelementptr ptr, ptr %t7319, i32 0
  store ptr %t7320, ptr %t7321
  %t7322 = call ptr @__alloc(i64 8, i32 0)
  %t7323 = inttoptr i64 11 to ptr
  %t7324 = getelementptr ptr, ptr %t7322, i32 0
  store ptr %t7323, ptr %t7324
  %t7325 = getelementptr ptr, ptr %t7319, i32 1
  store ptr %t7322, ptr %t7325
  %t7326 = getelementptr ptr, ptr %t7313, i32 1
  %t7327 = load ptr, ptr %t7326
  call void @__inc_ref(ptr %t7327)
  %t7328 = getelementptr ptr, ptr %t7319, i32 2
  store ptr %t7327, ptr %t7328
  %t7329 = call ptr @__alloc(i64 8, i32 0)
  %t7330 = inttoptr i64 11 to ptr
  %t7331 = getelementptr ptr, ptr %t7329, i32 0
  store ptr %t7330, ptr %t7331
  %t7332 = getelementptr ptr, ptr %t7319, i32 3
  store ptr %t7329, ptr %t7332
  %t7333 = getelementptr ptr, ptr %t4, i32 1
  %t7334 = load ptr, ptr %t7333
  call void @__free_recursive(ptr %t7334)
  %t7335 = getelementptr ptr, ptr %t4, i32 2
  %t7336 = load ptr, ptr %t7335
  call void @__free_recursive(ptr %t7336)
  %t7339 = inttoptr i64 279 to ptr
  %t7340 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t7339, ptr %t7340
  call void @__inc_ref(ptr %t5254)
  %t7337 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t7337
  %t7338 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t7319, ptr %t7338
  call void @__free_recursive(ptr %t7313)
  call void @__free_recursive(ptr %t7311)
  call void @__free_recursive(ptr %t7309)
  call void @__free_recursive(ptr %t7307)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.25.7341:
  %t7342 = getelementptr ptr, ptr %t7313, i32 1
  %t7343 = load ptr, ptr %t7342
  call void @__inc_ref(ptr %t7343)
  %t7344 = call ptr @__alloc(i64 24, i32 2)
  %t7345 = inttoptr i64 280 to ptr
  %t7346 = getelementptr ptr, ptr %t7344, i32 0
  store ptr %t7345, ptr %t7346
  %t7347 = getelementptr ptr, ptr %t4, i32 1
  %t7348 = load ptr, ptr %t7347
  call void @__free_recursive(ptr %t7348)
  %t7349 = getelementptr ptr, ptr %t4, i32 2
  %t7350 = load ptr, ptr %t7349
  call void @__free_recursive(ptr %t7350)
  %t7353 = inttoptr i64 101 to ptr
  %t7354 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t7353, ptr %t7354
  call void @__inc_ref(ptr %t7309)
  %t7351 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t7309, ptr %t7351
  call void @__inc_ref(ptr %t7343)
  %t7352 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t7343, ptr %t7352
  %t7355 = getelementptr ptr, ptr %t7344, i32 1
  store ptr %t4, ptr %t7355
  %t7356 = call ptr @__alloc(i64 56, i32 6)
  %t7357 = inttoptr i64 194 to ptr
  %t7358 = getelementptr ptr, ptr %t7356, i32 0
  store ptr %t7357, ptr %t7358
  call void @__inc_ref(ptr %t5254)
  %t7359 = getelementptr ptr, ptr %t7356, i32 1
  store ptr %t5254, ptr %t7359
  call void @__inc_ref(ptr %t7307)
  %t7360 = getelementptr ptr, ptr %t7356, i32 2
  store ptr %t7307, ptr %t7360
  call void @__inc_ref(ptr %t7343)
  %t7361 = getelementptr ptr, ptr %t7356, i32 3
  store ptr %t7343, ptr %t7361
  call void @__inc_ref(ptr %t7311)
  %t7362 = getelementptr ptr, ptr %t7356, i32 4
  store ptr %t7311, ptr %t7362
  %t7363 = getelementptr ptr, ptr %t7313, i32 2
  %t7364 = load ptr, ptr %t7363
  call void @__inc_ref(ptr %t7364)
  %t7365 = getelementptr ptr, ptr %t7356, i32 5
  store ptr %t7364, ptr %t7365
  call void @__inc_ref(ptr %t7309)
  %t7366 = getelementptr ptr, ptr %t7356, i32 6
  store ptr %t7309, ptr %t7366
  %t7367 = getelementptr ptr, ptr %t7344, i32 2
  store ptr %t7356, ptr %t7367
  call void @__free_recursive(ptr %t7343)
  call void @__free_recursive(ptr %t7313)
  call void @__free_recursive(ptr %t7311)
  call void @__free_recursive(ptr %t7309)
  call void @__free_recursive(ptr %t7307)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t7344, ptr %t3
  br label %tco.loop.0
tco.case.arm.26.7368:
  %t7369 = getelementptr ptr, ptr %t7313, i32 1
  %t7370 = load ptr, ptr %t7369
  call void @__inc_ref(ptr %t7370)
  %t7371 = call ptr @__alloc(i64 24, i32 2)
  %t7372 = inttoptr i64 280 to ptr
  %t7373 = getelementptr ptr, ptr %t7371, i32 0
  store ptr %t7372, ptr %t7373
  %t7374 = getelementptr ptr, ptr %t4, i32 1
  %t7375 = load ptr, ptr %t7374
  call void @__free_recursive(ptr %t7375)
  %t7376 = getelementptr ptr, ptr %t4, i32 2
  %t7377 = load ptr, ptr %t7376
  call void @__free_recursive(ptr %t7377)
  %t7380 = inttoptr i64 101 to ptr
  %t7381 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t7380, ptr %t7381
  call void @__inc_ref(ptr %t7309)
  %t7378 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t7309, ptr %t7378
  call void @__inc_ref(ptr %t7370)
  %t7379 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t7370, ptr %t7379
  %t7382 = getelementptr ptr, ptr %t7371, i32 1
  store ptr %t4, ptr %t7382
  %t7383 = call ptr @__alloc(i64 64, i32 7)
  %t7384 = inttoptr i64 196 to ptr
  %t7385 = getelementptr ptr, ptr %t7383, i32 0
  store ptr %t7384, ptr %t7385
  call void @__inc_ref(ptr %t5254)
  %t7386 = getelementptr ptr, ptr %t7383, i32 1
  store ptr %t5254, ptr %t7386
  call void @__inc_ref(ptr %t7307)
  %t7387 = getelementptr ptr, ptr %t7383, i32 2
  store ptr %t7307, ptr %t7387
  call void @__inc_ref(ptr %t7370)
  %t7388 = getelementptr ptr, ptr %t7383, i32 3
  store ptr %t7370, ptr %t7388
  call void @__inc_ref(ptr %t7311)
  %t7389 = getelementptr ptr, ptr %t7383, i32 4
  store ptr %t7311, ptr %t7389
  %t7390 = getelementptr ptr, ptr %t7313, i32 2
  %t7391 = load ptr, ptr %t7390
  call void @__inc_ref(ptr %t7391)
  %t7392 = getelementptr ptr, ptr %t7383, i32 5
  store ptr %t7391, ptr %t7392
  %t7393 = getelementptr ptr, ptr %t7313, i32 3
  %t7394 = load ptr, ptr %t7393
  call void @__inc_ref(ptr %t7394)
  %t7395 = getelementptr ptr, ptr %t7383, i32 6
  store ptr %t7394, ptr %t7395
  call void @__inc_ref(ptr %t7309)
  %t7396 = getelementptr ptr, ptr %t7383, i32 7
  store ptr %t7309, ptr %t7396
  %t7397 = getelementptr ptr, ptr %t7371, i32 2
  store ptr %t7383, ptr %t7397
  call void @__free_recursive(ptr %t7370)
  call void @__free_recursive(ptr %t7313)
  call void @__free_recursive(ptr %t7311)
  call void @__free_recursive(ptr %t7309)
  call void @__free_recursive(ptr %t7307)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t7371, ptr %t3
  br label %tco.loop.0
tco.case.arm.27.7398:
  %t7399 = getelementptr ptr, ptr %t7313, i32 1
  %t7400 = load ptr, ptr %t7399
  call void @__inc_ref(ptr %t7400)
  %t7401 = call ptr @__alloc(i64 24, i32 2)
  %t7402 = inttoptr i64 280 to ptr
  %t7403 = getelementptr ptr, ptr %t7401, i32 0
  store ptr %t7402, ptr %t7403
  %t7404 = getelementptr ptr, ptr %t4, i32 1
  %t7405 = load ptr, ptr %t7404
  call void @__free_recursive(ptr %t7405)
  %t7406 = getelementptr ptr, ptr %t4, i32 2
  %t7407 = load ptr, ptr %t7406
  call void @__free_recursive(ptr %t7407)
  %t7410 = inttoptr i64 101 to ptr
  %t7411 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t7410, ptr %t7411
  call void @__inc_ref(ptr %t7309)
  %t7408 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t7309, ptr %t7408
  call void @__inc_ref(ptr %t7400)
  %t7409 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t7400, ptr %t7409
  %t7412 = getelementptr ptr, ptr %t7401, i32 1
  store ptr %t4, ptr %t7412
  %t7413 = call ptr @__alloc(i64 72, i32 8)
  %t7414 = inttoptr i64 198 to ptr
  %t7415 = getelementptr ptr, ptr %t7413, i32 0
  store ptr %t7414, ptr %t7415
  call void @__inc_ref(ptr %t5254)
  %t7416 = getelementptr ptr, ptr %t7413, i32 1
  store ptr %t5254, ptr %t7416
  call void @__inc_ref(ptr %t7307)
  %t7417 = getelementptr ptr, ptr %t7413, i32 2
  store ptr %t7307, ptr %t7417
  call void @__inc_ref(ptr %t7400)
  %t7418 = getelementptr ptr, ptr %t7413, i32 3
  store ptr %t7400, ptr %t7418
  call void @__inc_ref(ptr %t7311)
  %t7419 = getelementptr ptr, ptr %t7413, i32 4
  store ptr %t7311, ptr %t7419
  %t7420 = getelementptr ptr, ptr %t7313, i32 2
  %t7421 = load ptr, ptr %t7420
  call void @__inc_ref(ptr %t7421)
  %t7422 = getelementptr ptr, ptr %t7413, i32 5
  store ptr %t7421, ptr %t7422
  %t7423 = getelementptr ptr, ptr %t7313, i32 3
  %t7424 = load ptr, ptr %t7423
  call void @__inc_ref(ptr %t7424)
  %t7425 = getelementptr ptr, ptr %t7413, i32 6
  store ptr %t7424, ptr %t7425
  %t7426 = getelementptr ptr, ptr %t7313, i32 4
  %t7427 = load ptr, ptr %t7426
  call void @__inc_ref(ptr %t7427)
  %t7428 = getelementptr ptr, ptr %t7413, i32 7
  store ptr %t7427, ptr %t7428
  call void @__inc_ref(ptr %t7309)
  %t7429 = getelementptr ptr, ptr %t7413, i32 8
  store ptr %t7309, ptr %t7429
  %t7430 = getelementptr ptr, ptr %t7401, i32 2
  store ptr %t7413, ptr %t7430
  call void @__free_recursive(ptr %t7400)
  call void @__free_recursive(ptr %t7313)
  call void @__free_recursive(ptr %t7311)
  call void @__free_recursive(ptr %t7309)
  call void @__free_recursive(ptr %t7307)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t7401, ptr %t3
  br label %tco.loop.0
tco.case.default.7317:
  unreachable
tco.case.arm.80.7431:
  %t7432 = getelementptr ptr, ptr %t5252, i32 2
  %t7433 = load ptr, ptr %t7432
  call void @__inc_ref(ptr %t7433)
  %t7434 = getelementptr ptr, ptr %t5252, i32 4
  %t7435 = load ptr, ptr %t7434
  call void @__inc_ref(ptr %t7435)
  %t7436 = getelementptr ptr, ptr %t7435, i32 0
  %t7437 = load ptr, ptr %t7436
  %t7438 = ptrtoint ptr %t7437 to i64
  switch i64 %t7438, label %tco.case.default.7439 [ i64 30, label %tco.case.arm.30.7440 i64 31, label %tco.case.arm.31.7452 i64 32, label %tco.case.arm.32.7479 ]
tco.case.arm.30.7440:
  %t7441 = call ptr @__alloc(i64 8, i32 0)
  %t7442 = inttoptr i64 11 to ptr
  %t7443 = getelementptr ptr, ptr %t7441, i32 0
  store ptr %t7442, ptr %t7443
  %t7444 = getelementptr ptr, ptr %t4, i32 1
  %t7445 = load ptr, ptr %t7444
  call void @__free_recursive(ptr %t7445)
  %t7446 = getelementptr ptr, ptr %t4, i32 2
  %t7447 = load ptr, ptr %t7446
  call void @__free_recursive(ptr %t7447)
  %t7450 = inttoptr i64 279 to ptr
  %t7451 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t7450, ptr %t7451
  call void @__inc_ref(ptr %t5254)
  %t7448 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t7448
  %t7449 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t7441, ptr %t7449
  call void @__free_recursive(ptr %t7435)
  call void @__free_recursive(ptr %t7433)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.31.7452:
  %t7453 = call ptr @__alloc(i64 16, i32 1)
  %t7454 = inttoptr i64 12 to ptr
  %t7455 = getelementptr ptr, ptr %t7453, i32 0
  store ptr %t7454, ptr %t7455
  %t7456 = call ptr @__alloc(i64 32, i32 3)
  %t7457 = inttoptr i64 34 to ptr
  %t7458 = getelementptr ptr, ptr %t7456, i32 0
  store ptr %t7457, ptr %t7458
  %t7459 = call ptr @__alloc(i64 8, i32 0)
  %t7460 = inttoptr i64 30 to ptr
  %t7461 = getelementptr ptr, ptr %t7459, i32 0
  store ptr %t7460, ptr %t7461
  %t7462 = getelementptr ptr, ptr %t7456, i32 1
  store ptr %t7459, ptr %t7462
  %t7463 = getelementptr ptr, ptr %t7435, i32 1
  %t7464 = load ptr, ptr %t7463
  call void @__inc_ref(ptr %t7464)
  %t7465 = getelementptr ptr, ptr %t7456, i32 2
  store ptr %t7464, ptr %t7465
  %t7466 = call ptr @__alloc(i64 8, i32 0)
  %t7467 = inttoptr i64 30 to ptr
  %t7468 = getelementptr ptr, ptr %t7466, i32 0
  store ptr %t7467, ptr %t7468
  %t7469 = getelementptr ptr, ptr %t7456, i32 3
  store ptr %t7466, ptr %t7469
  %t7470 = getelementptr ptr, ptr %t7453, i32 1
  store ptr %t7456, ptr %t7470
  %t7471 = getelementptr ptr, ptr %t4, i32 1
  %t7472 = load ptr, ptr %t7471
  call void @__free_recursive(ptr %t7472)
  %t7473 = getelementptr ptr, ptr %t4, i32 2
  %t7474 = load ptr, ptr %t7473
  call void @__free_recursive(ptr %t7474)
  %t7477 = inttoptr i64 279 to ptr
  %t7478 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t7477, ptr %t7478
  call void @__inc_ref(ptr %t5254)
  %t7475 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t7475
  %t7476 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t7453, ptr %t7476
  call void @__free_recursive(ptr %t7435)
  call void @__free_recursive(ptr %t7433)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.32.7479:
  %t7480 = getelementptr ptr, ptr %t7435, i32 2
  %t7481 = load ptr, ptr %t7480
  call void @__inc_ref(ptr %t7481)
  %t7482 = call ptr @__alloc(i64 24, i32 2)
  %t7483 = inttoptr i64 280 to ptr
  %t7484 = getelementptr ptr, ptr %t7482, i32 0
  store ptr %t7483, ptr %t7484
  %t7485 = getelementptr ptr, ptr %t4, i32 1
  %t7486 = load ptr, ptr %t7485
  call void @__free_recursive(ptr %t7486)
  %t7487 = getelementptr ptr, ptr %t4, i32 2
  %t7488 = load ptr, ptr %t7487
  call void @__free_recursive(ptr %t7488)
  %t7491 = inttoptr i64 102 to ptr
  %t7492 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t7491, ptr %t7492
  call void @__inc_ref(ptr %t7433)
  %t7489 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t7433, ptr %t7489
  call void @__inc_ref(ptr %t7481)
  %t7490 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t7481, ptr %t7490
  %t7493 = getelementptr ptr, ptr %t7482, i32 1
  store ptr %t4, ptr %t7493
  %t7494 = call ptr @__alloc(i64 64, i32 7)
  %t7495 = inttoptr i64 200 to ptr
  %t7496 = getelementptr ptr, ptr %t7494, i32 0
  store ptr %t7495, ptr %t7496
  call void @__inc_ref(ptr %t5254)
  %t7497 = getelementptr ptr, ptr %t7494, i32 1
  store ptr %t5254, ptr %t7497
  %t7498 = getelementptr ptr, ptr %t5252, i32 1
  %t7499 = load ptr, ptr %t7498
  call void @__inc_ref(ptr %t7499)
  %t7500 = getelementptr ptr, ptr %t7494, i32 2
  store ptr %t7499, ptr %t7500
  %t7501 = getelementptr ptr, ptr %t5252, i32 3
  %t7502 = load ptr, ptr %t7501
  call void @__inc_ref(ptr %t7502)
  %t7503 = getelementptr ptr, ptr %t7494, i32 3
  store ptr %t7502, ptr %t7503
  call void @__inc_ref(ptr %t7433)
  %t7504 = getelementptr ptr, ptr %t7494, i32 4
  store ptr %t7433, ptr %t7504
  %t7505 = getelementptr ptr, ptr %t7435, i32 3
  %t7506 = load ptr, ptr %t7505
  call void @__inc_ref(ptr %t7506)
  %t7507 = getelementptr ptr, ptr %t7494, i32 5
  store ptr %t7506, ptr %t7507
  call void @__inc_ref(ptr %t7481)
  %t7508 = getelementptr ptr, ptr %t7494, i32 6
  store ptr %t7481, ptr %t7508
  %t7509 = getelementptr ptr, ptr %t7435, i32 4
  %t7510 = load ptr, ptr %t7509
  call void @__inc_ref(ptr %t7510)
  %t7511 = getelementptr ptr, ptr %t7494, i32 7
  store ptr %t7510, ptr %t7511
  %t7512 = getelementptr ptr, ptr %t7482, i32 2
  store ptr %t7494, ptr %t7512
  call void @__free_recursive(ptr %t7481)
  call void @__free_recursive(ptr %t7435)
  call void @__free_recursive(ptr %t7433)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t7482, ptr %t3
  br label %tco.loop.0
tco.case.default.7439:
  unreachable
tco.case.arm.81.7513:
  %t7514 = getelementptr ptr, ptr %t5252, i32 2
  %t7515 = load ptr, ptr %t7514
  call void @__inc_ref(ptr %t7515)
  %t7516 = getelementptr ptr, ptr %t5252, i32 4
  %t7517 = load ptr, ptr %t7516
  call void @__inc_ref(ptr %t7517)
  %t7518 = getelementptr ptr, ptr %t7517, i32 0
  %t7519 = load ptr, ptr %t7518
  %t7520 = ptrtoint ptr %t7519 to i64
  switch i64 %t7520, label %tco.case.default.7521 [ i64 30, label %tco.case.arm.30.7522 i64 31, label %tco.case.arm.31.7534 i64 32, label %tco.case.arm.32.7561 ]
tco.case.arm.30.7522:
  %t7523 = call ptr @__alloc(i64 8, i32 0)
  %t7524 = inttoptr i64 11 to ptr
  %t7525 = getelementptr ptr, ptr %t7523, i32 0
  store ptr %t7524, ptr %t7525
  %t7526 = getelementptr ptr, ptr %t4, i32 1
  %t7527 = load ptr, ptr %t7526
  call void @__free_recursive(ptr %t7527)
  %t7528 = getelementptr ptr, ptr %t4, i32 2
  %t7529 = load ptr, ptr %t7528
  call void @__free_recursive(ptr %t7529)
  %t7532 = inttoptr i64 279 to ptr
  %t7533 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t7532, ptr %t7533
  call void @__inc_ref(ptr %t5254)
  %t7530 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t7530
  %t7531 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t7523, ptr %t7531
  call void @__free_recursive(ptr %t7517)
  call void @__free_recursive(ptr %t7515)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.31.7534:
  %t7535 = call ptr @__alloc(i64 16, i32 1)
  %t7536 = inttoptr i64 12 to ptr
  %t7537 = getelementptr ptr, ptr %t7535, i32 0
  store ptr %t7536, ptr %t7537
  %t7538 = call ptr @__alloc(i64 32, i32 3)
  %t7539 = inttoptr i64 34 to ptr
  %t7540 = getelementptr ptr, ptr %t7538, i32 0
  store ptr %t7539, ptr %t7540
  %t7541 = call ptr @__alloc(i64 8, i32 0)
  %t7542 = inttoptr i64 30 to ptr
  %t7543 = getelementptr ptr, ptr %t7541, i32 0
  store ptr %t7542, ptr %t7543
  %t7544 = getelementptr ptr, ptr %t7538, i32 1
  store ptr %t7541, ptr %t7544
  %t7545 = getelementptr ptr, ptr %t7517, i32 1
  %t7546 = load ptr, ptr %t7545
  call void @__inc_ref(ptr %t7546)
  %t7547 = getelementptr ptr, ptr %t7538, i32 2
  store ptr %t7546, ptr %t7547
  %t7548 = call ptr @__alloc(i64 8, i32 0)
  %t7549 = inttoptr i64 30 to ptr
  %t7550 = getelementptr ptr, ptr %t7548, i32 0
  store ptr %t7549, ptr %t7550
  %t7551 = getelementptr ptr, ptr %t7538, i32 3
  store ptr %t7548, ptr %t7551
  %t7552 = getelementptr ptr, ptr %t7535, i32 1
  store ptr %t7538, ptr %t7552
  %t7553 = getelementptr ptr, ptr %t4, i32 1
  %t7554 = load ptr, ptr %t7553
  call void @__free_recursive(ptr %t7554)
  %t7555 = getelementptr ptr, ptr %t4, i32 2
  %t7556 = load ptr, ptr %t7555
  call void @__free_recursive(ptr %t7556)
  %t7559 = inttoptr i64 279 to ptr
  %t7560 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t7559, ptr %t7560
  call void @__inc_ref(ptr %t5254)
  %t7557 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t7557
  %t7558 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t7535, ptr %t7558
  call void @__free_recursive(ptr %t7517)
  call void @__free_recursive(ptr %t7515)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.32.7561:
  %t7562 = getelementptr ptr, ptr %t7517, i32 2
  %t7563 = load ptr, ptr %t7562
  call void @__inc_ref(ptr %t7563)
  %t7564 = call ptr @__alloc(i64 24, i32 2)
  %t7565 = inttoptr i64 280 to ptr
  %t7566 = getelementptr ptr, ptr %t7564, i32 0
  store ptr %t7565, ptr %t7566
  %t7567 = getelementptr ptr, ptr %t4, i32 1
  %t7568 = load ptr, ptr %t7567
  call void @__free_recursive(ptr %t7568)
  %t7569 = getelementptr ptr, ptr %t4, i32 2
  %t7570 = load ptr, ptr %t7569
  call void @__free_recursive(ptr %t7570)
  %t7573 = inttoptr i64 102 to ptr
  %t7574 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t7573, ptr %t7574
  call void @__inc_ref(ptr %t7515)
  %t7571 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t7515, ptr %t7571
  call void @__inc_ref(ptr %t7563)
  %t7572 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t7563, ptr %t7572
  %t7575 = getelementptr ptr, ptr %t7564, i32 1
  store ptr %t4, ptr %t7575
  %t7576 = call ptr @__alloc(i64 64, i32 7)
  %t7577 = inttoptr i64 202 to ptr
  %t7578 = getelementptr ptr, ptr %t7576, i32 0
  store ptr %t7577, ptr %t7578
  call void @__inc_ref(ptr %t5254)
  %t7579 = getelementptr ptr, ptr %t7576, i32 1
  store ptr %t5254, ptr %t7579
  %t7580 = getelementptr ptr, ptr %t5252, i32 1
  %t7581 = load ptr, ptr %t7580
  call void @__inc_ref(ptr %t7581)
  %t7582 = getelementptr ptr, ptr %t7576, i32 2
  store ptr %t7581, ptr %t7582
  %t7583 = getelementptr ptr, ptr %t5252, i32 3
  %t7584 = load ptr, ptr %t7583
  call void @__inc_ref(ptr %t7584)
  %t7585 = getelementptr ptr, ptr %t7576, i32 3
  store ptr %t7584, ptr %t7585
  call void @__inc_ref(ptr %t7515)
  %t7586 = getelementptr ptr, ptr %t7576, i32 4
  store ptr %t7515, ptr %t7586
  %t7587 = getelementptr ptr, ptr %t7517, i32 3
  %t7588 = load ptr, ptr %t7587
  call void @__inc_ref(ptr %t7588)
  %t7589 = getelementptr ptr, ptr %t7576, i32 5
  store ptr %t7588, ptr %t7589
  call void @__inc_ref(ptr %t7563)
  %t7590 = getelementptr ptr, ptr %t7576, i32 6
  store ptr %t7563, ptr %t7590
  %t7591 = getelementptr ptr, ptr %t7517, i32 4
  %t7592 = load ptr, ptr %t7591
  call void @__inc_ref(ptr %t7592)
  %t7593 = getelementptr ptr, ptr %t7576, i32 7
  store ptr %t7592, ptr %t7593
  %t7594 = getelementptr ptr, ptr %t7564, i32 2
  store ptr %t7576, ptr %t7594
  call void @__free_recursive(ptr %t7563)
  call void @__free_recursive(ptr %t7517)
  call void @__free_recursive(ptr %t7515)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t7564, ptr %t3
  br label %tco.loop.0
tco.case.default.7521:
  unreachable
tco.case.arm.82.7595:
  %t7596 = call ptr @__alloc(i64 24, i32 2)
  %t7597 = inttoptr i64 280 to ptr
  %t7598 = getelementptr ptr, ptr %t7596, i32 0
  store ptr %t7597, ptr %t7598
  %t7599 = getelementptr ptr, ptr %t5252, i32 1
  %t7600 = load ptr, ptr %t7599
  call void @__inc_ref(ptr %t7600)
  %t7601 = getelementptr ptr, ptr %t5252, i32 2
  %t7602 = load ptr, ptr %t7601
  call void @__inc_ref(ptr %t7602)
  %t7603 = getelementptr ptr, ptr %t4, i32 1
  %t7604 = load ptr, ptr %t7603
  call void @__free_recursive(ptr %t7604)
  %t7605 = getelementptr ptr, ptr %t4, i32 2
  %t7606 = load ptr, ptr %t7605
  call void @__free_recursive(ptr %t7606)
  %t7609 = inttoptr i64 77 to ptr
  %t7610 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t7609, ptr %t7610
  %t7607 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t7600, ptr %t7607
  %t7608 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t7602, ptr %t7608
  %t7611 = getelementptr ptr, ptr %t7596, i32 1
  store ptr %t4, ptr %t7611
  %t7612 = call ptr @__alloc(i64 16, i32 1)
  %t7613 = inttoptr i64 204 to ptr
  %t7614 = getelementptr ptr, ptr %t7612, i32 0
  store ptr %t7613, ptr %t7614
  call void @__inc_ref(ptr %t5254)
  %t7615 = getelementptr ptr, ptr %t7612, i32 1
  store ptr %t5254, ptr %t7615
  %t7616 = getelementptr ptr, ptr %t7596, i32 2
  store ptr %t7612, ptr %t7616
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t7596, ptr %t3
  br label %tco.loop.0
tco.case.arm.83.7617:
  %t7618 = call ptr @__alloc(i64 24, i32 2)
  %t7619 = inttoptr i64 280 to ptr
  %t7620 = getelementptr ptr, ptr %t7618, i32 0
  store ptr %t7619, ptr %t7620
  %t7621 = getelementptr ptr, ptr %t5252, i32 1
  %t7622 = load ptr, ptr %t7621
  call void @__inc_ref(ptr %t7622)
  %t7623 = getelementptr ptr, ptr %t5252, i32 2
  %t7624 = load ptr, ptr %t7623
  call void @__inc_ref(ptr %t7624)
  %t7625 = getelementptr ptr, ptr %t4, i32 1
  %t7626 = load ptr, ptr %t7625
  call void @__free_recursive(ptr %t7626)
  %t7627 = getelementptr ptr, ptr %t4, i32 2
  %t7628 = load ptr, ptr %t7627
  call void @__free_recursive(ptr %t7628)
  %t7631 = inttoptr i64 76 to ptr
  %t7632 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t7631, ptr %t7632
  %t7629 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t7622, ptr %t7629
  %t7630 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t7624, ptr %t7630
  %t7633 = getelementptr ptr, ptr %t7618, i32 1
  store ptr %t4, ptr %t7633
  %t7634 = call ptr @__alloc(i64 16, i32 1)
  %t7635 = inttoptr i64 206 to ptr
  %t7636 = getelementptr ptr, ptr %t7634, i32 0
  store ptr %t7635, ptr %t7636
  call void @__inc_ref(ptr %t5254)
  %t7637 = getelementptr ptr, ptr %t7634, i32 1
  store ptr %t5254, ptr %t7637
  %t7638 = getelementptr ptr, ptr %t7618, i32 2
  store ptr %t7634, ptr %t7638
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t7618, ptr %t3
  br label %tco.loop.0
tco.case.arm.84.7639:
  %t7640 = call ptr @__alloc(i64 16, i32 1)
  %t7641 = inttoptr i64 89 to ptr
  %t7642 = getelementptr ptr, ptr %t7640, i32 0
  store ptr %t7641, ptr %t7642
  %t7643 = getelementptr ptr, ptr %t5252, i32 1
  %t7644 = load ptr, ptr %t7643
  call void @__inc_ref(ptr %t7644)
  %t7645 = getelementptr ptr, ptr %t7640, i32 1
  store ptr %t7644, ptr %t7645
  %t7646 = call ptr @__alloc(i64 16, i32 1)
  %t7647 = inttoptr i64 208 to ptr
  %t7648 = getelementptr ptr, ptr %t7646, i32 0
  store ptr %t7647, ptr %t7648
  call void @__inc_ref(ptr %t5254)
  %t7649 = getelementptr ptr, ptr %t7646, i32 1
  store ptr %t5254, ptr %t7649
  %t7650 = getelementptr ptr, ptr %t4, i32 1
  %t7651 = load ptr, ptr %t7650
  call void @__free_recursive(ptr %t7651)
  %t7652 = getelementptr ptr, ptr %t4, i32 2
  %t7653 = load ptr, ptr %t7652
  call void @__free_recursive(ptr %t7653)
  %t7656 = inttoptr i64 280 to ptr
  %t7657 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t7656, ptr %t7657
  %t7654 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t7640, ptr %t7654
  %t7655 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t7646, ptr %t7655
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.85.7658:
  %t7659 = getelementptr ptr, ptr %t5252, i32 1
  %t7660 = load ptr, ptr %t7659
  call void @__inc_ref(ptr %t7660)
  %t7661 = getelementptr ptr, ptr %t5252, i32 2
  %t7662 = load ptr, ptr %t7661
  call void @__inc_ref(ptr %t7662)
  %t7663 = getelementptr ptr, ptr %t5252, i32 3
  %t7664 = load ptr, ptr %t7663
  call void @__inc_ref(ptr %t7664)
  %t7665 = getelementptr ptr, ptr %t5252, i32 4
  %t7666 = load ptr, ptr %t7665
  call void @__inc_ref(ptr %t7666)
  %t7667 = getelementptr ptr, ptr %t7662, i32 0
  %t7668 = load ptr, ptr %t7667
  %t7669 = ptrtoint ptr %t7668 to i64
  switch i64 %t7669, label %tco.case.default.7670 [ i64 30, label %tco.case.arm.30.7671 i64 31, label %tco.case.arm.31.7683 i64 32, label %tco.case.arm.32.7706 ]
tco.case.arm.30.7671:
  %t7672 = call ptr @__alloc(i64 32, i32 3)
  %t7673 = inttoptr i64 91 to ptr
  %t7674 = getelementptr ptr, ptr %t7672, i32 0
  store ptr %t7673, ptr %t7674
  call void @__inc_ref(ptr %t7660)
  %t7675 = getelementptr ptr, ptr %t7672, i32 1
  store ptr %t7660, ptr %t7675
  call void @__inc_ref(ptr %t7664)
  %t7676 = getelementptr ptr, ptr %t7672, i32 2
  store ptr %t7664, ptr %t7676
  call void @__inc_ref(ptr %t7666)
  %t7677 = getelementptr ptr, ptr %t7672, i32 3
  store ptr %t7666, ptr %t7677
  %t7678 = getelementptr ptr, ptr %t4, i32 1
  %t7679 = load ptr, ptr %t7678
  call void @__free_recursive(ptr %t7679)
  %t7681 = inttoptr i64 280 to ptr
  %t7682 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t7681, ptr %t7682
  %t7680 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t7672, ptr %t7680
  call void @__free_recursive(ptr %t7666)
  call void @__free_recursive(ptr %t7664)
  call void @__free_recursive(ptr %t7662)
  call void @__free_recursive(ptr %t7660)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.31.7683:
  %t7684 = call ptr @__alloc(i64 32, i32 3)
  %t7685 = inttoptr i64 91 to ptr
  %t7686 = getelementptr ptr, ptr %t7684, i32 0
  store ptr %t7685, ptr %t7686
  call void @__inc_ref(ptr %t7660)
  %t7687 = getelementptr ptr, ptr %t7684, i32 1
  store ptr %t7660, ptr %t7687
  call void @__inc_ref(ptr %t7664)
  %t7688 = getelementptr ptr, ptr %t7684, i32 2
  store ptr %t7664, ptr %t7688
  call void @__inc_ref(ptr %t7666)
  %t7689 = getelementptr ptr, ptr %t7684, i32 3
  store ptr %t7666, ptr %t7689
  %t7690 = call ptr @__alloc(i64 32, i32 3)
  %t7691 = inttoptr i64 209 to ptr
  %t7692 = getelementptr ptr, ptr %t7690, i32 0
  store ptr %t7691, ptr %t7692
  call void @__inc_ref(ptr %t5254)
  %t7693 = getelementptr ptr, ptr %t7690, i32 1
  store ptr %t5254, ptr %t7693
  call void @__inc_ref(ptr %t7660)
  %t7694 = getelementptr ptr, ptr %t7690, i32 2
  store ptr %t7660, ptr %t7694
  %t7695 = getelementptr ptr, ptr %t7662, i32 1
  %t7696 = load ptr, ptr %t7695
  call void @__inc_ref(ptr %t7696)
  %t7697 = getelementptr ptr, ptr %t7690, i32 3
  store ptr %t7696, ptr %t7697
  %t7698 = getelementptr ptr, ptr %t4, i32 1
  %t7699 = load ptr, ptr %t7698
  call void @__free_recursive(ptr %t7699)
  %t7700 = getelementptr ptr, ptr %t4, i32 2
  %t7701 = load ptr, ptr %t7700
  call void @__free_recursive(ptr %t7701)
  %t7704 = inttoptr i64 280 to ptr
  %t7705 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t7704, ptr %t7705
  %t7702 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t7684, ptr %t7702
  %t7703 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t7690, ptr %t7703
  call void @__free_recursive(ptr %t7666)
  call void @__free_recursive(ptr %t7664)
  call void @__free_recursive(ptr %t7662)
  call void @__free_recursive(ptr %t7660)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.32.7706:
  %t7707 = getelementptr ptr, ptr %t7666, i32 0
  %t7708 = load ptr, ptr %t7707
  %t7709 = ptrtoint ptr %t7708 to i64
  switch i64 %t7709, label %tco.case.default.7710 [ i64 30, label %tco.case.arm.30.7711 i64 31, label %tco.case.arm.31.7723 i64 32, label %tco.case.arm.32.7746 ]
tco.case.arm.30.7711:
  %t7712 = call ptr @__alloc(i64 32, i32 3)
  %t7713 = inttoptr i64 115 to ptr
  %t7714 = getelementptr ptr, ptr %t7712, i32 0
  store ptr %t7713, ptr %t7714
  call void @__inc_ref(ptr %t7660)
  %t7715 = getelementptr ptr, ptr %t7712, i32 1
  store ptr %t7660, ptr %t7715
  call void @__inc_ref(ptr %t7662)
  %t7716 = getelementptr ptr, ptr %t7712, i32 2
  store ptr %t7662, ptr %t7716
  call void @__inc_ref(ptr %t7664)
  %t7717 = getelementptr ptr, ptr %t7712, i32 3
  store ptr %t7664, ptr %t7717
  %t7718 = getelementptr ptr, ptr %t4, i32 1
  %t7719 = load ptr, ptr %t7718
  call void @__free_recursive(ptr %t7719)
  %t7721 = inttoptr i64 280 to ptr
  %t7722 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t7721, ptr %t7722
  %t7720 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t7712, ptr %t7720
  call void @__free_recursive(ptr %t7666)
  call void @__free_recursive(ptr %t7664)
  call void @__free_recursive(ptr %t7662)
  call void @__free_recursive(ptr %t7660)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.31.7723:
  %t7724 = call ptr @__alloc(i64 32, i32 3)
  %t7725 = inttoptr i64 115 to ptr
  %t7726 = getelementptr ptr, ptr %t7724, i32 0
  store ptr %t7725, ptr %t7726
  call void @__inc_ref(ptr %t7660)
  %t7727 = getelementptr ptr, ptr %t7724, i32 1
  store ptr %t7660, ptr %t7727
  call void @__inc_ref(ptr %t7662)
  %t7728 = getelementptr ptr, ptr %t7724, i32 2
  store ptr %t7662, ptr %t7728
  call void @__inc_ref(ptr %t7664)
  %t7729 = getelementptr ptr, ptr %t7724, i32 3
  store ptr %t7664, ptr %t7729
  %t7730 = call ptr @__alloc(i64 32, i32 3)
  %t7731 = inttoptr i64 210 to ptr
  %t7732 = getelementptr ptr, ptr %t7730, i32 0
  store ptr %t7731, ptr %t7732
  call void @__inc_ref(ptr %t5254)
  %t7733 = getelementptr ptr, ptr %t7730, i32 1
  store ptr %t5254, ptr %t7733
  call void @__inc_ref(ptr %t7660)
  %t7734 = getelementptr ptr, ptr %t7730, i32 2
  store ptr %t7660, ptr %t7734
  %t7735 = getelementptr ptr, ptr %t7666, i32 1
  %t7736 = load ptr, ptr %t7735
  call void @__inc_ref(ptr %t7736)
  %t7737 = getelementptr ptr, ptr %t7730, i32 3
  store ptr %t7736, ptr %t7737
  %t7738 = getelementptr ptr, ptr %t4, i32 1
  %t7739 = load ptr, ptr %t7738
  call void @__free_recursive(ptr %t7739)
  %t7740 = getelementptr ptr, ptr %t4, i32 2
  %t7741 = load ptr, ptr %t7740
  call void @__free_recursive(ptr %t7741)
  %t7744 = inttoptr i64 280 to ptr
  %t7745 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t7744, ptr %t7745
  %t7742 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t7724, ptr %t7742
  %t7743 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t7730, ptr %t7743
  call void @__free_recursive(ptr %t7666)
  call void @__free_recursive(ptr %t7664)
  call void @__free_recursive(ptr %t7662)
  call void @__free_recursive(ptr %t7660)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.32.7746:
  %t7747 = call ptr @__alloc(i64 40, i32 4)
  %t7748 = inttoptr i64 99 to ptr
  %t7749 = getelementptr ptr, ptr %t7747, i32 0
  store ptr %t7748, ptr %t7749
  call void @__inc_ref(ptr %t7660)
  %t7750 = getelementptr ptr, ptr %t7747, i32 1
  store ptr %t7660, ptr %t7750
  %t7751 = getelementptr ptr, ptr %t7662, i32 4
  %t7752 = load ptr, ptr %t7751
  call void @__inc_ref(ptr %t7752)
  %t7753 = getelementptr ptr, ptr %t7747, i32 2
  store ptr %t7752, ptr %t7753
  call void @__inc_ref(ptr %t7664)
  %t7754 = getelementptr ptr, ptr %t7747, i32 3
  store ptr %t7664, ptr %t7754
  %t7755 = getelementptr ptr, ptr %t7666, i32 2
  %t7756 = load ptr, ptr %t7755
  call void @__inc_ref(ptr %t7756)
  %t7757 = getelementptr ptr, ptr %t7747, i32 4
  store ptr %t7756, ptr %t7757
  %t7758 = call ptr @__alloc(i64 56, i32 6)
  %t7759 = inttoptr i64 211 to ptr
  %t7760 = getelementptr ptr, ptr %t7758, i32 0
  store ptr %t7759, ptr %t7760
  call void @__inc_ref(ptr %t5254)
  %t7761 = getelementptr ptr, ptr %t7758, i32 1
  store ptr %t5254, ptr %t7761
  call void @__inc_ref(ptr %t7660)
  %t7762 = getelementptr ptr, ptr %t7758, i32 2
  store ptr %t7660, ptr %t7762
  %t7763 = getelementptr ptr, ptr %t7662, i32 3
  %t7764 = load ptr, ptr %t7763
  call void @__inc_ref(ptr %t7764)
  %t7765 = getelementptr ptr, ptr %t7758, i32 3
  store ptr %t7764, ptr %t7765
  %t7766 = getelementptr ptr, ptr %t7666, i32 3
  %t7767 = load ptr, ptr %t7766
  call void @__inc_ref(ptr %t7767)
  %t7768 = getelementptr ptr, ptr %t7758, i32 4
  store ptr %t7767, ptr %t7768
  %t7769 = getelementptr ptr, ptr %t7662, i32 2
  %t7770 = load ptr, ptr %t7769
  call void @__inc_ref(ptr %t7770)
  %t7771 = getelementptr ptr, ptr %t7758, i32 5
  store ptr %t7770, ptr %t7771
  %t7772 = getelementptr ptr, ptr %t7666, i32 4
  %t7773 = load ptr, ptr %t7772
  call void @__inc_ref(ptr %t7773)
  %t7774 = getelementptr ptr, ptr %t7758, i32 6
  store ptr %t7773, ptr %t7774
  %t7775 = getelementptr ptr, ptr %t4, i32 1
  %t7776 = load ptr, ptr %t7775
  call void @__free_recursive(ptr %t7776)
  %t7777 = getelementptr ptr, ptr %t4, i32 2
  %t7778 = load ptr, ptr %t7777
  call void @__free_recursive(ptr %t7778)
  %t7781 = inttoptr i64 280 to ptr
  %t7782 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t7781, ptr %t7782
  %t7779 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t7747, ptr %t7779
  %t7780 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t7758, ptr %t7780
  call void @__free_recursive(ptr %t7666)
  call void @__free_recursive(ptr %t7664)
  call void @__free_recursive(ptr %t7662)
  call void @__free_recursive(ptr %t7660)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.7710:
  unreachable
tco.case.default.7670:
  unreachable
tco.case.arm.86.7783:
  %t7784 = call ptr @__alloc(i64 24, i32 2)
  %t7785 = inttoptr i64 280 to ptr
  %t7786 = getelementptr ptr, ptr %t7784, i32 0
  store ptr %t7785, ptr %t7786
  %t7787 = getelementptr ptr, ptr %t5252, i32 1
  %t7788 = load ptr, ptr %t7787
  call void @__inc_ref(ptr %t7788)
  %t7789 = getelementptr ptr, ptr %t5252, i32 2
  %t7790 = load ptr, ptr %t7789
  call void @__inc_ref(ptr %t7790)
  %t7791 = getelementptr ptr, ptr %t4, i32 1
  %t7792 = load ptr, ptr %t7791
  call void @__free_recursive(ptr %t7792)
  %t7793 = getelementptr ptr, ptr %t4, i32 2
  %t7794 = load ptr, ptr %t7793
  call void @__free_recursive(ptr %t7794)
  %t7797 = inttoptr i64 82 to ptr
  %t7798 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t7797, ptr %t7798
  %t7795 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t7788, ptr %t7795
  %t7796 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t7790, ptr %t7796
  %t7799 = getelementptr ptr, ptr %t7784, i32 1
  store ptr %t4, ptr %t7799
  call void @__inc_ref(ptr %t5254)
  %t7800 = getelementptr ptr, ptr %t7784, i32 2
  store ptr %t5254, ptr %t7800
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t7784, ptr %t3
  br label %tco.loop.0
tco.case.arm.87.7801:
  %t7802 = call ptr @__alloc(i64 24, i32 2)
  %t7803 = inttoptr i64 280 to ptr
  %t7804 = getelementptr ptr, ptr %t7802, i32 0
  store ptr %t7803, ptr %t7804
  %t7805 = getelementptr ptr, ptr %t5252, i32 1
  %t7806 = load ptr, ptr %t7805
  call void @__inc_ref(ptr %t7806)
  %t7807 = getelementptr ptr, ptr %t5252, i32 2
  %t7808 = load ptr, ptr %t7807
  call void @__inc_ref(ptr %t7808)
  %t7809 = getelementptr ptr, ptr %t4, i32 1
  %t7810 = load ptr, ptr %t7809
  call void @__free_recursive(ptr %t7810)
  %t7811 = getelementptr ptr, ptr %t4, i32 2
  %t7812 = load ptr, ptr %t7811
  call void @__free_recursive(ptr %t7812)
  %t7815 = inttoptr i64 83 to ptr
  %t7816 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t7815, ptr %t7816
  %t7813 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t7806, ptr %t7813
  %t7814 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t7808, ptr %t7814
  %t7817 = getelementptr ptr, ptr %t7802, i32 1
  store ptr %t4, ptr %t7817
  call void @__inc_ref(ptr %t5254)
  %t7818 = getelementptr ptr, ptr %t7802, i32 2
  store ptr %t5254, ptr %t7818
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t7802, ptr %t3
  br label %tco.loop.0
tco.case.arm.88.7819:
  %t7820 = getelementptr ptr, ptr %t5252, i32 1
  %t7821 = load ptr, ptr %t7820
  call void @__inc_ref(ptr %t7821)
  %t7822 = getelementptr ptr, ptr %t7821, i32 0
  %t7823 = load ptr, ptr %t7822
  %t7824 = ptrtoint ptr %t7823 to i64
  switch i64 %t7824, label %tco.case.default.7825 [ i64 33, label %tco.case.arm.33.7826 ]
tco.case.arm.33.7826:
  %t7827 = getelementptr ptr, ptr %t7821, i32 2
  %t7828 = load ptr, ptr %t7827
  call void @__inc_ref(ptr %t7828)
  call void @__free_recursive(ptr %t7821)
  %t7829 = call ptr @__alloc(i64 32, i32 3)
  %t7830 = inttoptr i64 54 to ptr
  %t7831 = getelementptr ptr, ptr %t7829, i32 0
  store ptr %t7830, ptr %t7831
  call void @__inc_ref(ptr %t7828)
  %t7832 = getelementptr ptr, ptr %t7829, i32 1
  store ptr %t7828, ptr %t7832
  %t7833 = getelementptr ptr, ptr %t5252, i32 2
  %t7834 = load ptr, ptr %t7833
  call void @__inc_ref(ptr %t7834)
  %t7835 = getelementptr ptr, ptr %t7829, i32 2
  store ptr %t7834, ptr %t7835
  %t7836 = getelementptr ptr, ptr %t5252, i32 3
  %t7837 = load ptr, ptr %t7836
  call void @__inc_ref(ptr %t7837)
  %t7838 = getelementptr ptr, ptr %t7829, i32 3
  store ptr %t7837, ptr %t7838
  %t7839 = getelementptr ptr, ptr %t4, i32 1
  %t7840 = load ptr, ptr %t7839
  call void @__free_recursive(ptr %t7840)
  %t7842 = inttoptr i64 280 to ptr
  %t7843 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t7842, ptr %t7843
  %t7841 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t7829, ptr %t7841
  call void @__free_recursive(ptr %t7828)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.7825:
  unreachable
tco.case.arm.89.7844:
  %t7845 = getelementptr ptr, ptr %t5252, i32 1
  %t7846 = load ptr, ptr %t7845
  call void @__inc_ref(ptr %t7846)
  %t7847 = getelementptr ptr, ptr %t7846, i32 0
  %t7848 = load ptr, ptr %t7847
  %t7849 = ptrtoint ptr %t7848 to i64
  switch i64 %t7849, label %tco.case.default.7850 [ i64 13, label %tco.case.arm.13.7851 i64 14, label %tco.case.arm.14.7871 ]
tco.case.arm.13.7851:
  %t7852 = call ptr @__alloc(i64 16, i32 1)
  %t7853 = inttoptr i64 3 to ptr
  %t7854 = getelementptr ptr, ptr %t7852, i32 0
  store ptr %t7853, ptr %t7854
  %t7855 = call ptr @__alloc(i64 16, i32 1)
  %t7856 = inttoptr i64 3471307616 to ptr
  %t7857 = getelementptr ptr, ptr %t7855, i32 0
  store ptr %t7856, ptr %t7857
  %t7858 = call ptr @__alloc(i64 8, i32 0)
  %t7859 = inttoptr i64 36 to ptr
  %t7860 = getelementptr ptr, ptr %t7858, i32 0
  store ptr %t7859, ptr %t7860
  %t7861 = getelementptr ptr, ptr %t7855, i32 1
  store ptr %t7858, ptr %t7861
  %t7862 = getelementptr ptr, ptr %t7852, i32 1
  store ptr %t7855, ptr %t7862
  %t7863 = getelementptr ptr, ptr %t4, i32 1
  %t7864 = load ptr, ptr %t7863
  call void @__free_recursive(ptr %t7864)
  %t7865 = getelementptr ptr, ptr %t4, i32 2
  %t7866 = load ptr, ptr %t7865
  call void @__free_recursive(ptr %t7866)
  %t7869 = inttoptr i64 279 to ptr
  %t7870 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t7869, ptr %t7870
  call void @__inc_ref(ptr %t5254)
  %t7867 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t7867
  %t7868 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t7852, ptr %t7868
  call void @__free_recursive(ptr %t7846)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.14.7871:
  %t7872 = getelementptr ptr, ptr %t7846, i32 1
  %t7873 = load ptr, ptr %t7872
  call void @__inc_ref(ptr %t7873)
  %t7874 = call ptr @__splitOnFirst(ptr getelementptr inbounds (i8, ptr @.str.7, i64 12), ptr %t7873)
  %t7875 = getelementptr ptr, ptr %t7874, i32 0
  %t7876 = load ptr, ptr %t7875
  %t7877 = ptrtoint ptr %t7876 to i64
  switch i64 %t7877, label %tco.case.default.7878 [ i64 11, label %tco.case.arm.11.7879 i64 12, label %tco.case.arm.12.7899 ]
tco.case.arm.11.7879:
  call void @__free_recursive(ptr %t7874)
  %t7880 = call ptr @__alloc(i64 16, i32 1)
  %t7881 = inttoptr i64 3 to ptr
  %t7882 = getelementptr ptr, ptr %t7880, i32 0
  store ptr %t7881, ptr %t7882
  %t7883 = call ptr @__alloc(i64 16, i32 1)
  %t7884 = inttoptr i64 3471307616 to ptr
  %t7885 = getelementptr ptr, ptr %t7883, i32 0
  store ptr %t7884, ptr %t7885
  %t7886 = call ptr @__alloc(i64 8, i32 0)
  %t7887 = inttoptr i64 36 to ptr
  %t7888 = getelementptr ptr, ptr %t7886, i32 0
  store ptr %t7887, ptr %t7888
  %t7889 = getelementptr ptr, ptr %t7883, i32 1
  store ptr %t7886, ptr %t7889
  %t7890 = getelementptr ptr, ptr %t7880, i32 1
  store ptr %t7883, ptr %t7890
  %t7891 = getelementptr ptr, ptr %t4, i32 1
  %t7892 = load ptr, ptr %t7891
  call void @__free_recursive(ptr %t7892)
  %t7893 = getelementptr ptr, ptr %t4, i32 2
  %t7894 = load ptr, ptr %t7893
  call void @__free_recursive(ptr %t7894)
  %t7897 = inttoptr i64 279 to ptr
  %t7898 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t7897, ptr %t7898
  call void @__inc_ref(ptr %t5254)
  %t7895 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t7895
  %t7896 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t7880, ptr %t7896
  call void @__free_recursive(ptr %t7846)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.12.7899:
  %t7900 = getelementptr ptr, ptr %t7874, i32 1
  %t7901 = load ptr, ptr %t7900
  call void @__inc_ref(ptr %t7901)
  call void @__free_recursive(ptr %t7874)
  %t7902 = getelementptr ptr, ptr %t7901, i32 0
  %t7903 = load ptr, ptr %t7902
  %t7904 = ptrtoint ptr %t7903 to i64
  switch i64 %t7904, label %tco.case.default.7905 [ i64 15, label %tco.case.arm.15.7906 ]
tco.case.arm.15.7906:
  %t7907 = getelementptr ptr, ptr %t7901, i32 1
  %t7908 = load ptr, ptr %t7907
  call void @__inc_ref(ptr %t7908)
  %t7909 = getelementptr ptr, ptr %t7901, i32 2
  %t7910 = load ptr, ptr %t7909
  %t7911 = call ptr @__alloc(i64 32, i32 3)
  %t7912 = inttoptr i64 115 to ptr
  %t7913 = getelementptr ptr, ptr %t7911, i32 0
  store ptr %t7912, ptr %t7913
  %t7914 = call ptr @v_lineMeasure()
  %t7915 = getelementptr ptr, ptr %t7911, i32 1
  store ptr %t7914, ptr %t7915
  %t7916 = call ptr @__alloc(i64 8, i32 0)
  %t7917 = inttoptr i64 30 to ptr
  %t7918 = getelementptr ptr, ptr %t7916, i32 0
  store ptr %t7917, ptr %t7918
  %t7919 = getelementptr ptr, ptr %t7911, i32 2
  store ptr %t7916, ptr %t7919
  call void @__inc_ref(ptr %t7908)
  %t7920 = call ptr @__alloc(i64 8, i32 0)
  %t7921 = inttoptr i64 120 to ptr
  %t7922 = getelementptr ptr, ptr %t7920, i32 0
  store ptr %t7921, ptr %t7922
  %t7923 = call ptr @v_$cps$splitAll(ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t7908, ptr %t7920)
  %t7924 = getelementptr ptr, ptr %t7911, i32 3
  store ptr %t7923, ptr %t7924
  %t7925 = getelementptr ptr, ptr %t4, i32 1
  %t7926 = load ptr, ptr %t7925
  call void @__free_recursive(ptr %t7926)
  %t7927 = getelementptr ptr, ptr %t4, i32 2
  %t7928 = load ptr, ptr %t7927
  call void @__free_recursive(ptr %t7928)
  %t7950 = inttoptr i64 280 to ptr
  %t7951 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t7950, ptr %t7951
  %t7929 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t7911, ptr %t7929
  %t7935 = getelementptr i8, ptr %t7901, i64 -8
  %t7936 = load i32, ptr %t7935
  %t7937 = icmp eq i32 %t7936, 1
  br i1 %t7937, label %reuse.in_place.7938, label %reuse.copy.7939
reuse.in_place.7938:
  %t7930 = getelementptr ptr, ptr %t7901, i32 1
  %t7931 = load ptr, ptr %t7930
  call void @__free_recursive(ptr %t7931)
  %t7933 = inttoptr i64 213 to ptr
  %t7934 = getelementptr ptr, ptr %t7901, i32 0
  store ptr %t7933, ptr %t7934
  call void @__inc_ref(ptr %t5254)
  %t7932 = getelementptr ptr, ptr %t7901, i32 1
  store ptr %t5254, ptr %t7932
  br label %reuse.in_place.end.7941
reuse.in_place.end.7941:
  br label %reuse.join.7940
reuse.copy.7939:
  %t7943 = call ptr @__alloc(i64 24, i32 2)
  %t7944 = inttoptr i64 213 to ptr
  %t7945 = getelementptr ptr, ptr %t7943, i32 0
  store ptr %t7944, ptr %t7945
  call void @__inc_ref(ptr %t5254)
  %t7946 = getelementptr ptr, ptr %t7943, i32 1
  store ptr %t5254, ptr %t7946
  call void @__inc_ref(ptr %t7910)
  %t7947 = getelementptr ptr, ptr %t7943, i32 2
  store ptr %t7910, ptr %t7947
  call void @__free_recursive(ptr %t7901)
  br label %reuse.copy.end.7942
reuse.copy.end.7942:
  br label %reuse.join.7940
reuse.join.7940:
  %t7948 = phi ptr [ %t7901, %reuse.in_place.end.7941 ], [ %t7943, %reuse.copy.end.7942 ]
  %t7949 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t7948, ptr %t7949
  call void @__free_recursive(ptr %t7908)
  call void @__free_recursive(ptr %t7846)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.7905:
  unreachable
tco.case.default.7878:
  unreachable
tco.case.default.7850:
  unreachable
tco.case.arm.90.7952:
  %t7953 = getelementptr ptr, ptr %t5252, i32 1
  %t7954 = load ptr, ptr %t7953
  call void @__inc_ref(ptr %t7954)
  %t7955 = getelementptr ptr, ptr %t5252, i32 2
  %t7956 = load ptr, ptr %t7955
  call void @__inc_ref(ptr %t7956)
  %t7957 = getelementptr ptr, ptr %t5252, i32 3
  %t7958 = load ptr, ptr %t7957
  call void @__inc_ref(ptr %t7958)
  %t7959 = getelementptr ptr, ptr %t7958, i32 0
  %t7960 = load ptr, ptr %t7959
  %t7961 = ptrtoint ptr %t7960 to i64
  switch i64 %t7961, label %tco.case.default.7962 [ i64 30, label %tco.case.arm.30.7963 i64 31, label %tco.case.arm.31.7976 i64 32, label %tco.case.arm.32.8002 ]
tco.case.arm.30.7963:
  call void @__free_recursive(ptr %t7958)
  %t7964 = call ptr @__alloc(i64 16, i32 1)
  %t7965 = inttoptr i64 31 to ptr
  %t7966 = getelementptr ptr, ptr %t7964, i32 0
  store ptr %t7965, ptr %t7966
  call void @__inc_ref(ptr %t7956)
  %t7967 = getelementptr ptr, ptr %t7964, i32 1
  store ptr %t7956, ptr %t7967
  %t7968 = getelementptr ptr, ptr %t4, i32 1
  %t7969 = load ptr, ptr %t7968
  call void @__free_recursive(ptr %t7969)
  %t7970 = getelementptr ptr, ptr %t4, i32 2
  %t7971 = load ptr, ptr %t7970
  call void @__free_recursive(ptr %t7971)
  %t7974 = inttoptr i64 279 to ptr
  %t7975 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t7974, ptr %t7975
  call void @__inc_ref(ptr %t5254)
  %t7972 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t7972
  %t7973 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t7964, ptr %t7973
  call void @__free_recursive(ptr %t7956)
  call void @__free_recursive(ptr %t7954)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.31.7976:
  %t7977 = getelementptr ptr, ptr %t7958, i32 1
  %t7978 = load ptr, ptr %t7977
  call void @__inc_ref(ptr %t7978)
  call void @__free_recursive(ptr %t7958)
  %t7979 = call ptr @__alloc(i64 40, i32 4)
  %t7980 = inttoptr i64 92 to ptr
  %t7981 = getelementptr ptr, ptr %t7979, i32 0
  store ptr %t7980, ptr %t7981
  call void @__inc_ref(ptr %t7954)
  %t7982 = getelementptr ptr, ptr %t7979, i32 1
  store ptr %t7954, ptr %t7982
  %t7983 = call ptr @__alloc(i64 16, i32 1)
  %t7984 = inttoptr i64 24 to ptr
  %t7985 = getelementptr ptr, ptr %t7983, i32 0
  store ptr %t7984, ptr %t7985
  call void @__inc_ref(ptr %t7956)
  %t7986 = getelementptr ptr, ptr %t7983, i32 1
  store ptr %t7956, ptr %t7986
  %t7987 = getelementptr ptr, ptr %t7979, i32 2
  store ptr %t7983, ptr %t7987
  %t7988 = call ptr @__alloc(i64 8, i32 0)
  %t7989 = inttoptr i64 30 to ptr
  %t7990 = getelementptr ptr, ptr %t7988, i32 0
  store ptr %t7989, ptr %t7990
  %t7991 = getelementptr ptr, ptr %t7979, i32 3
  store ptr %t7988, ptr %t7991
  %t7992 = call ptr @__alloc(i64 16, i32 1)
  %t7993 = inttoptr i64 24 to ptr
  %t7994 = getelementptr ptr, ptr %t7992, i32 0
  store ptr %t7993, ptr %t7994
  call void @__inc_ref(ptr %t7978)
  %t7995 = getelementptr ptr, ptr %t7992, i32 1
  store ptr %t7978, ptr %t7995
  %t7996 = getelementptr ptr, ptr %t7979, i32 4
  store ptr %t7992, ptr %t7996
  %t7997 = getelementptr ptr, ptr %t4, i32 1
  %t7998 = load ptr, ptr %t7997
  call void @__free_recursive(ptr %t7998)
  %t8000 = inttoptr i64 280 to ptr
  %t8001 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t8000, ptr %t8001
  %t7999 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t7979, ptr %t7999
  call void @__free_recursive(ptr %t7978)
  call void @__free_recursive(ptr %t7956)
  call void @__free_recursive(ptr %t7954)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.32.8002:
  %t8003 = getelementptr ptr, ptr %t7958, i32 2
  %t8004 = load ptr, ptr %t8003
  call void @__inc_ref(ptr %t8004)
  %t8005 = getelementptr ptr, ptr %t7958, i32 3
  %t8006 = load ptr, ptr %t8005
  call void @__inc_ref(ptr %t8006)
  %t8007 = getelementptr ptr, ptr %t7958, i32 4
  %t8008 = load ptr, ptr %t8007
  call void @__inc_ref(ptr %t8008)
  call void @__free_recursive(ptr %t7958)
  %t8009 = getelementptr ptr, ptr %t8004, i32 0
  %t8010 = load ptr, ptr %t8009
  %t8011 = ptrtoint ptr %t8010 to i64
  switch i64 %t8011, label %tco.case.default.8012 [ i64 24, label %tco.case.arm.24.8013 i64 25, label %tco.case.arm.25.8036 i64 26, label %tco.case.arm.26.8059 i64 27, label %tco.case.arm.27.8085 ]
tco.case.arm.24.8013:
  %t8014 = call ptr @__alloc(i64 24, i32 2)
  %t8015 = inttoptr i64 280 to ptr
  %t8016 = getelementptr ptr, ptr %t8014, i32 0
  store ptr %t8015, ptr %t8016
  %t8017 = call ptr @__alloc(i64 40, i32 4)
  %t8018 = inttoptr i64 92 to ptr
  %t8019 = getelementptr ptr, ptr %t8017, i32 0
  store ptr %t8018, ptr %t8019
  call void @__inc_ref(ptr %t7954)
  %t8020 = getelementptr ptr, ptr %t8017, i32 1
  store ptr %t7954, ptr %t8020
  %t8021 = getelementptr ptr, ptr %t8004, i32 1
  %t8022 = load ptr, ptr %t8021
  call void @__inc_ref(ptr %t8022)
  %t8023 = getelementptr ptr, ptr %t4, i32 1
  %t8024 = load ptr, ptr %t8023
  call void @__free_recursive(ptr %t8024)
  %t8025 = getelementptr ptr, ptr %t4, i32 2
  %t8026 = load ptr, ptr %t8025
  call void @__free_recursive(ptr %t8026)
  %t8029 = inttoptr i64 25 to ptr
  %t8030 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t8029, ptr %t8030
  call void @__inc_ref(ptr %t7956)
  %t8027 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t7956, ptr %t8027
  %t8028 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t8022, ptr %t8028
  %t8031 = getelementptr ptr, ptr %t8017, i32 2
  store ptr %t4, ptr %t8031
  call void @__inc_ref(ptr %t8006)
  %t8032 = getelementptr ptr, ptr %t8017, i32 3
  store ptr %t8006, ptr %t8032
  call void @__inc_ref(ptr %t8008)
  %t8033 = getelementptr ptr, ptr %t8017, i32 4
  store ptr %t8008, ptr %t8033
  %t8034 = getelementptr ptr, ptr %t8014, i32 1
  store ptr %t8017, ptr %t8034
  call void @__inc_ref(ptr %t5254)
  %t8035 = getelementptr ptr, ptr %t8014, i32 2
  store ptr %t5254, ptr %t8035
  call void @__free_recursive(ptr %t8008)
  call void @__free_recursive(ptr %t8006)
  call void @__free_recursive(ptr %t8004)
  call void @__free_recursive(ptr %t7956)
  call void @__free_recursive(ptr %t7954)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t8014, ptr %t3
  br label %tco.loop.0
tco.case.arm.25.8036:
  %t8037 = call ptr @__alloc(i64 40, i32 4)
  %t8038 = inttoptr i64 92 to ptr
  %t8039 = getelementptr ptr, ptr %t8037, i32 0
  store ptr %t8038, ptr %t8039
  call void @__inc_ref(ptr %t7954)
  %t8040 = getelementptr ptr, ptr %t8037, i32 1
  store ptr %t7954, ptr %t8040
  %t8041 = call ptr @__alloc(i64 32, i32 3)
  %t8042 = inttoptr i64 26 to ptr
  %t8043 = getelementptr ptr, ptr %t8041, i32 0
  store ptr %t8042, ptr %t8043
  call void @__inc_ref(ptr %t7956)
  %t8044 = getelementptr ptr, ptr %t8041, i32 1
  store ptr %t7956, ptr %t8044
  %t8045 = getelementptr ptr, ptr %t8004, i32 1
  %t8046 = load ptr, ptr %t8045
  call void @__inc_ref(ptr %t8046)
  %t8047 = getelementptr ptr, ptr %t8041, i32 2
  store ptr %t8046, ptr %t8047
  %t8048 = getelementptr ptr, ptr %t8004, i32 2
  %t8049 = load ptr, ptr %t8048
  call void @__inc_ref(ptr %t8049)
  %t8050 = getelementptr ptr, ptr %t8041, i32 3
  store ptr %t8049, ptr %t8050
  %t8051 = getelementptr ptr, ptr %t8037, i32 2
  store ptr %t8041, ptr %t8051
  call void @__inc_ref(ptr %t8006)
  %t8052 = getelementptr ptr, ptr %t8037, i32 3
  store ptr %t8006, ptr %t8052
  call void @__inc_ref(ptr %t8008)
  %t8053 = getelementptr ptr, ptr %t8037, i32 4
  store ptr %t8008, ptr %t8053
  %t8054 = getelementptr ptr, ptr %t4, i32 1
  %t8055 = load ptr, ptr %t8054
  call void @__free_recursive(ptr %t8055)
  %t8057 = inttoptr i64 280 to ptr
  %t8058 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t8057, ptr %t8058
  %t8056 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t8037, ptr %t8056
  call void @__free_recursive(ptr %t8008)
  call void @__free_recursive(ptr %t8006)
  call void @__free_recursive(ptr %t8004)
  call void @__free_recursive(ptr %t7956)
  call void @__free_recursive(ptr %t7954)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.26.8059:
  %t8060 = call ptr @__alloc(i64 40, i32 4)
  %t8061 = inttoptr i64 92 to ptr
  %t8062 = getelementptr ptr, ptr %t8060, i32 0
  store ptr %t8061, ptr %t8062
  call void @__inc_ref(ptr %t7954)
  %t8063 = getelementptr ptr, ptr %t8060, i32 1
  store ptr %t7954, ptr %t8063
  %t8064 = call ptr @__alloc(i64 40, i32 4)
  %t8065 = inttoptr i64 27 to ptr
  %t8066 = getelementptr ptr, ptr %t8064, i32 0
  store ptr %t8065, ptr %t8066
  call void @__inc_ref(ptr %t7956)
  %t8067 = getelementptr ptr, ptr %t8064, i32 1
  store ptr %t7956, ptr %t8067
  %t8068 = getelementptr ptr, ptr %t8004, i32 1
  %t8069 = load ptr, ptr %t8068
  call void @__inc_ref(ptr %t8069)
  %t8070 = getelementptr ptr, ptr %t8064, i32 2
  store ptr %t8069, ptr %t8070
  %t8071 = getelementptr ptr, ptr %t8004, i32 2
  %t8072 = load ptr, ptr %t8071
  call void @__inc_ref(ptr %t8072)
  %t8073 = getelementptr ptr, ptr %t8064, i32 3
  store ptr %t8072, ptr %t8073
  %t8074 = getelementptr ptr, ptr %t8004, i32 3
  %t8075 = load ptr, ptr %t8074
  call void @__inc_ref(ptr %t8075)
  %t8076 = getelementptr ptr, ptr %t8064, i32 4
  store ptr %t8075, ptr %t8076
  %t8077 = getelementptr ptr, ptr %t8060, i32 2
  store ptr %t8064, ptr %t8077
  call void @__inc_ref(ptr %t8006)
  %t8078 = getelementptr ptr, ptr %t8060, i32 3
  store ptr %t8006, ptr %t8078
  call void @__inc_ref(ptr %t8008)
  %t8079 = getelementptr ptr, ptr %t8060, i32 4
  store ptr %t8008, ptr %t8079
  %t8080 = getelementptr ptr, ptr %t4, i32 1
  %t8081 = load ptr, ptr %t8080
  call void @__free_recursive(ptr %t8081)
  %t8083 = inttoptr i64 280 to ptr
  %t8084 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t8083, ptr %t8084
  %t8082 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t8060, ptr %t8082
  call void @__free_recursive(ptr %t8008)
  call void @__free_recursive(ptr %t8006)
  call void @__free_recursive(ptr %t8004)
  call void @__free_recursive(ptr %t7956)
  call void @__free_recursive(ptr %t7954)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.27.8085:
  %t8086 = call ptr @__alloc(i64 40, i32 4)
  %t8087 = inttoptr i64 105 to ptr
  %t8088 = getelementptr ptr, ptr %t8086, i32 0
  store ptr %t8087, ptr %t8088
  call void @__inc_ref(ptr %t7954)
  %t8089 = getelementptr ptr, ptr %t8086, i32 1
  store ptr %t7954, ptr %t8089
  %t8090 = getelementptr ptr, ptr %t8004, i32 2
  %t8091 = load ptr, ptr %t8090
  call void @__inc_ref(ptr %t8091)
  %t8092 = getelementptr ptr, ptr %t8086, i32 2
  store ptr %t8091, ptr %t8092
  %t8093 = getelementptr ptr, ptr %t8004, i32 3
  %t8094 = load ptr, ptr %t8093
  call void @__inc_ref(ptr %t8094)
  %t8095 = getelementptr ptr, ptr %t8086, i32 3
  store ptr %t8094, ptr %t8095
  %t8096 = getelementptr ptr, ptr %t8004, i32 4
  %t8097 = load ptr, ptr %t8096
  call void @__inc_ref(ptr %t8097)
  %t8098 = getelementptr ptr, ptr %t8086, i32 4
  store ptr %t8097, ptr %t8098
  %t8099 = call ptr @__alloc(i64 56, i32 6)
  %t8100 = inttoptr i64 214 to ptr
  %t8101 = getelementptr ptr, ptr %t8099, i32 0
  store ptr %t8100, ptr %t8101
  call void @__inc_ref(ptr %t5254)
  %t8102 = getelementptr ptr, ptr %t8099, i32 1
  store ptr %t5254, ptr %t8102
  %t8103 = getelementptr ptr, ptr %t8004, i32 1
  %t8104 = load ptr, ptr %t8103
  call void @__inc_ref(ptr %t8104)
  %t8105 = getelementptr ptr, ptr %t8099, i32 2
  store ptr %t8104, ptr %t8105
  call void @__inc_ref(ptr %t7954)
  %t8106 = getelementptr ptr, ptr %t8099, i32 3
  store ptr %t7954, ptr %t8106
  call void @__inc_ref(ptr %t8006)
  %t8107 = getelementptr ptr, ptr %t8099, i32 4
  store ptr %t8006, ptr %t8107
  call void @__inc_ref(ptr %t8008)
  %t8108 = getelementptr ptr, ptr %t8099, i32 5
  store ptr %t8008, ptr %t8108
  call void @__inc_ref(ptr %t7956)
  %t8109 = getelementptr ptr, ptr %t8099, i32 6
  store ptr %t7956, ptr %t8109
  %t8110 = getelementptr ptr, ptr %t4, i32 1
  %t8111 = load ptr, ptr %t8110
  call void @__free_recursive(ptr %t8111)
  %t8112 = getelementptr ptr, ptr %t4, i32 2
  %t8113 = load ptr, ptr %t8112
  call void @__free_recursive(ptr %t8113)
  %t8116 = inttoptr i64 280 to ptr
  %t8117 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t8116, ptr %t8117
  %t8114 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t8086, ptr %t8114
  %t8115 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t8099, ptr %t8115
  call void @__free_recursive(ptr %t8008)
  call void @__free_recursive(ptr %t8006)
  call void @__free_recursive(ptr %t8004)
  call void @__free_recursive(ptr %t7956)
  call void @__free_recursive(ptr %t7954)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.8012:
  unreachable
tco.case.default.7962:
  unreachable
tco.case.arm.91.8118:
  %t8119 = getelementptr ptr, ptr %t5252, i32 1
  %t8120 = load ptr, ptr %t8119
  call void @__inc_ref(ptr %t8120)
  %t8121 = getelementptr ptr, ptr %t5252, i32 3
  %t8122 = load ptr, ptr %t8121
  call void @__inc_ref(ptr %t8122)
  %t8123 = getelementptr ptr, ptr %t5252, i32 2
  %t8124 = load ptr, ptr %t8123
  call void @__inc_ref(ptr %t8124)
  %t8125 = getelementptr ptr, ptr %t8124, i32 0
  %t8126 = load ptr, ptr %t8125
  %t8127 = ptrtoint ptr %t8126 to i64
  switch i64 %t8127, label %tco.case.default.8128 [ i64 13, label %tco.case.arm.13.8129 i64 14, label %tco.case.arm.14.8138 ]
tco.case.arm.13.8129:
  call void @__free_recursive(ptr %t8124)
  %t8130 = getelementptr ptr, ptr %t4, i32 1
  %t8131 = load ptr, ptr %t8130
  call void @__free_recursive(ptr %t8131)
  %t8132 = getelementptr ptr, ptr %t4, i32 2
  %t8133 = load ptr, ptr %t8132
  call void @__free_recursive(ptr %t8133)
  %t8136 = inttoptr i64 279 to ptr
  %t8137 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t8136, ptr %t8137
  call void @__inc_ref(ptr %t5254)
  %t8134 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t8134
  call void @__inc_ref(ptr %t8122)
  %t8135 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t8122, ptr %t8135
  call void @__free_recursive(ptr %t8122)
  call void @__free_recursive(ptr %t8120)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.14.8138:
  %t8139 = getelementptr ptr, ptr %t8124, i32 1
  %t8140 = load ptr, ptr %t8139
  call void @__inc_ref(ptr %t8140)
  %t8141 = getelementptr ptr, ptr %t8124, i32 2
  %t8142 = load ptr, ptr %t8141
  call void @__inc_ref(ptr %t8142)
  call void @__free_recursive(ptr %t8124)
  %t8143 = call ptr @__alloc(i64 32, i32 3)
  %t8144 = inttoptr i64 91 to ptr
  %t8145 = getelementptr ptr, ptr %t8143, i32 0
  store ptr %t8144, ptr %t8145
  call void @__inc_ref(ptr %t8120)
  %t8146 = getelementptr ptr, ptr %t8143, i32 1
  store ptr %t8120, ptr %t8146
  call void @__inc_ref(ptr %t8142)
  %t8147 = getelementptr ptr, ptr %t8143, i32 2
  store ptr %t8142, ptr %t8147
  call void @__inc_ref(ptr %t8122)
  %t8148 = getelementptr ptr, ptr %t8143, i32 3
  store ptr %t8122, ptr %t8148
  %t8149 = call ptr @__alloc(i64 32, i32 3)
  %t8150 = inttoptr i64 216 to ptr
  %t8151 = getelementptr ptr, ptr %t8149, i32 0
  store ptr %t8150, ptr %t8151
  call void @__inc_ref(ptr %t5254)
  %t8152 = getelementptr ptr, ptr %t8149, i32 1
  store ptr %t5254, ptr %t8152
  call void @__inc_ref(ptr %t8120)
  %t8153 = getelementptr ptr, ptr %t8149, i32 2
  store ptr %t8120, ptr %t8153
  call void @__inc_ref(ptr %t8140)
  %t8154 = getelementptr ptr, ptr %t8149, i32 3
  store ptr %t8140, ptr %t8154
  %t8155 = getelementptr ptr, ptr %t4, i32 1
  %t8156 = load ptr, ptr %t8155
  call void @__free_recursive(ptr %t8156)
  %t8157 = getelementptr ptr, ptr %t4, i32 2
  %t8158 = load ptr, ptr %t8157
  call void @__free_recursive(ptr %t8158)
  %t8161 = inttoptr i64 280 to ptr
  %t8162 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t8161, ptr %t8162
  %t8159 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t8143, ptr %t8159
  %t8160 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t8149, ptr %t8160
  call void @__free_recursive(ptr %t8142)
  call void @__free_recursive(ptr %t8140)
  call void @__free_recursive(ptr %t8122)
  call void @__free_recursive(ptr %t8120)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.8128:
  unreachable
tco.case.arm.92.8163:
  %t8164 = getelementptr ptr, ptr %t5252, i32 1
  %t8165 = load ptr, ptr %t8164
  call void @__inc_ref(ptr %t8165)
  %t8166 = getelementptr ptr, ptr %t5252, i32 2
  %t8167 = load ptr, ptr %t8166
  call void @__inc_ref(ptr %t8167)
  %t8168 = call ptr @__alloc(i64 24, i32 2)
  %t8169 = inttoptr i64 280 to ptr
  %t8170 = getelementptr ptr, ptr %t8168, i32 0
  store ptr %t8169, ptr %t8170
  %t8171 = getelementptr ptr, ptr %t4, i32 1
  %t8172 = load ptr, ptr %t8171
  call void @__free_recursive(ptr %t8172)
  %t8173 = getelementptr ptr, ptr %t4, i32 2
  %t8174 = load ptr, ptr %t8173
  call void @__free_recursive(ptr %t8174)
  %t8177 = inttoptr i64 102 to ptr
  %t8178 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t8177, ptr %t8178
  call void @__inc_ref(ptr %t8165)
  %t8175 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t8165, ptr %t8175
  call void @__inc_ref(ptr %t8167)
  %t8176 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t8167, ptr %t8176
  %t8179 = getelementptr ptr, ptr %t8168, i32 1
  store ptr %t4, ptr %t8179
  %t8180 = call ptr @__alloc(i64 48, i32 5)
  %t8181 = inttoptr i64 217 to ptr
  %t8182 = getelementptr ptr, ptr %t8180, i32 0
  store ptr %t8181, ptr %t8182
  call void @__inc_ref(ptr %t5254)
  %t8183 = getelementptr ptr, ptr %t8180, i32 1
  store ptr %t5254, ptr %t8183
  call void @__inc_ref(ptr %t8165)
  %t8184 = getelementptr ptr, ptr %t8180, i32 2
  store ptr %t8165, ptr %t8184
  %t8185 = getelementptr ptr, ptr %t5252, i32 3
  %t8186 = load ptr, ptr %t8185
  call void @__inc_ref(ptr %t8186)
  %t8187 = getelementptr ptr, ptr %t8180, i32 3
  store ptr %t8186, ptr %t8187
  call void @__inc_ref(ptr %t8167)
  %t8188 = getelementptr ptr, ptr %t8180, i32 4
  store ptr %t8167, ptr %t8188
  %t8189 = getelementptr ptr, ptr %t5252, i32 4
  %t8190 = load ptr, ptr %t8189
  call void @__inc_ref(ptr %t8190)
  %t8191 = getelementptr ptr, ptr %t8180, i32 5
  store ptr %t8190, ptr %t8191
  %t8192 = getelementptr ptr, ptr %t8168, i32 2
  store ptr %t8180, ptr %t8192
  call void @__free_recursive(ptr %t8167)
  call void @__free_recursive(ptr %t8165)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t8168, ptr %t3
  br label %tco.loop.0
tco.case.arm.93.8193:
  %t8194 = getelementptr ptr, ptr %t5252, i32 1
  %t8195 = load ptr, ptr %t8194
  call void @__inc_ref(ptr %t8195)
  %t8196 = getelementptr ptr, ptr %t5252, i32 2
  %t8197 = load ptr, ptr %t8196
  call void @__inc_ref(ptr %t8197)
  %t8198 = getelementptr ptr, ptr %t5252, i32 3
  %t8199 = load ptr, ptr %t8198
  call void @__inc_ref(ptr %t8199)
  %t8200 = getelementptr ptr, ptr %t5252, i32 4
  %t8201 = load ptr, ptr %t8200
  call void @__inc_ref(ptr %t8201)
  %t8202 = getelementptr ptr, ptr %t8197, i32 0
  %t8203 = load ptr, ptr %t8202
  %t8204 = ptrtoint ptr %t8203 to i64
  switch i64 %t8204, label %tco.case.default.8205 [ i64 11, label %tco.case.arm.11.8206 i64 12, label %tco.case.arm.12.8239 ]
tco.case.arm.11.8206:
  %t8207 = call ptr @__alloc(i64 24, i32 2)
  %t8208 = inttoptr i64 280 to ptr
  %t8209 = getelementptr ptr, ptr %t8207, i32 0
  store ptr %t8208, ptr %t8209
  %t8210 = call ptr @__alloc(i64 32, i32 3)
  %t8211 = inttoptr i64 33 to ptr
  %t8212 = getelementptr ptr, ptr %t8210, i32 0
  store ptr %t8211, ptr %t8212
  %t8213 = call ptr @__alloc(i64 8, i32 0)
  %t8214 = inttoptr i64 49 to ptr
  %t8215 = getelementptr ptr, ptr %t8213, i32 0
  store ptr %t8214, ptr %t8215
  %t8216 = getelementptr ptr, ptr %t8210, i32 1
  store ptr %t8213, ptr %t8216
  %t8217 = getelementptr ptr, ptr %t8195, i32 2
  %t8218 = load ptr, ptr %t8217
  call void @__inc_ref(ptr %t8218)
  %t8219 = getelementptr ptr, ptr %t8210, i32 2
  store ptr %t8218, ptr %t8219
  %t8220 = getelementptr ptr, ptr %t8195, i32 3
  %t8221 = load ptr, ptr %t8220
  call void @__inc_ref(ptr %t8221)
  %t8222 = getelementptr ptr, ptr %t8210, i32 3
  store ptr %t8221, ptr %t8222
  %t8223 = getelementptr ptr, ptr %t4, i32 1
  %t8224 = load ptr, ptr %t8223
  call void @__free_recursive(ptr %t8224)
  %t8225 = getelementptr ptr, ptr %t4, i32 2
  %t8226 = load ptr, ptr %t8225
  call void @__free_recursive(ptr %t8226)
  %t8229 = inttoptr i64 117 to ptr
  %t8230 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t8229, ptr %t8230
  %t8227 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t8210, ptr %t8227
  call void @__inc_ref(ptr %t8199)
  %t8228 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t8199, ptr %t8228
  %t8231 = getelementptr ptr, ptr %t8207, i32 1
  store ptr %t4, ptr %t8231
  %t8232 = call ptr @__alloc(i64 32, i32 3)
  %t8233 = inttoptr i64 222 to ptr
  %t8234 = getelementptr ptr, ptr %t8232, i32 0
  store ptr %t8233, ptr %t8234
  call void @__inc_ref(ptr %t5254)
  %t8235 = getelementptr ptr, ptr %t8232, i32 1
  store ptr %t5254, ptr %t8235
  call void @__inc_ref(ptr %t8195)
  %t8236 = getelementptr ptr, ptr %t8232, i32 2
  store ptr %t8195, ptr %t8236
  call void @__inc_ref(ptr %t8201)
  %t8237 = getelementptr ptr, ptr %t8232, i32 3
  store ptr %t8201, ptr %t8237
  %t8238 = getelementptr ptr, ptr %t8207, i32 2
  store ptr %t8232, ptr %t8238
  call void @__free_recursive(ptr %t8201)
  call void @__free_recursive(ptr %t8199)
  call void @__free_recursive(ptr %t8197)
  call void @__free_recursive(ptr %t8195)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t8207, ptr %t3
  br label %tco.loop.0
tco.case.arm.12.8239:
  %t8240 = call ptr @__alloc(i64 40, i32 4)
  %t8241 = inttoptr i64 92 to ptr
  %t8242 = getelementptr ptr, ptr %t8240, i32 0
  store ptr %t8241, ptr %t8242
  call void @__inc_ref(ptr %t8195)
  %t8243 = getelementptr ptr, ptr %t8240, i32 1
  store ptr %t8195, ptr %t8243
  %t8244 = getelementptr ptr, ptr %t8197, i32 1
  %t8245 = load ptr, ptr %t8244
  call void @__inc_ref(ptr %t8245)
  %t8246 = getelementptr ptr, ptr %t8240, i32 2
  store ptr %t8245, ptr %t8246
  call void @__inc_ref(ptr %t8199)
  %t8247 = getelementptr ptr, ptr %t8240, i32 3
  store ptr %t8199, ptr %t8247
  call void @__inc_ref(ptr %t8201)
  %t8248 = getelementptr ptr, ptr %t8240, i32 4
  store ptr %t8201, ptr %t8248
  %t8249 = getelementptr ptr, ptr %t4, i32 1
  %t8250 = load ptr, ptr %t8249
  call void @__free_recursive(ptr %t8250)
  %t8252 = inttoptr i64 280 to ptr
  %t8253 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t8252, ptr %t8253
  %t8251 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t8240, ptr %t8251
  call void @__free_recursive(ptr %t8201)
  call void @__free_recursive(ptr %t8199)
  call void @__free_recursive(ptr %t8197)
  call void @__free_recursive(ptr %t8195)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.8205:
  unreachable
tco.case.arm.94.8254:
  %t8255 = getelementptr ptr, ptr %t5252, i32 1
  %t8256 = load ptr, ptr %t8255
  call void @__inc_ref(ptr %t8256)
  %t8257 = getelementptr ptr, ptr %t5252, i32 2
  %t8258 = load ptr, ptr %t8257
  call void @__inc_ref(ptr %t8258)
  %t8259 = getelementptr ptr, ptr %t5252, i32 3
  %t8260 = load ptr, ptr %t8259
  call void @__inc_ref(ptr %t8260)
  %t8261 = getelementptr ptr, ptr %t5252, i32 4
  %t8262 = load ptr, ptr %t8261
  call void @__inc_ref(ptr %t8262)
  %t8263 = getelementptr ptr, ptr %t8262, i32 0
  %t8264 = load ptr, ptr %t8263
  %t8265 = ptrtoint ptr %t8264 to i64
  switch i64 %t8265, label %tco.case.default.8266 [ i64 11, label %tco.case.arm.11.8267 i64 12, label %tco.case.arm.12.8300 ]
tco.case.arm.11.8267:
  %t8268 = call ptr @__alloc(i64 24, i32 2)
  %t8269 = inttoptr i64 280 to ptr
  %t8270 = getelementptr ptr, ptr %t8268, i32 0
  store ptr %t8269, ptr %t8270
  %t8271 = call ptr @__alloc(i64 32, i32 3)
  %t8272 = inttoptr i64 33 to ptr
  %t8273 = getelementptr ptr, ptr %t8271, i32 0
  store ptr %t8272, ptr %t8273
  %t8274 = call ptr @__alloc(i64 8, i32 0)
  %t8275 = inttoptr i64 49 to ptr
  %t8276 = getelementptr ptr, ptr %t8274, i32 0
  store ptr %t8275, ptr %t8276
  %t8277 = getelementptr ptr, ptr %t8271, i32 1
  store ptr %t8274, ptr %t8277
  %t8278 = getelementptr ptr, ptr %t8256, i32 2
  %t8279 = load ptr, ptr %t8278
  call void @__inc_ref(ptr %t8279)
  %t8280 = getelementptr ptr, ptr %t8271, i32 2
  store ptr %t8279, ptr %t8280
  %t8281 = getelementptr ptr, ptr %t8256, i32 3
  %t8282 = load ptr, ptr %t8281
  call void @__inc_ref(ptr %t8282)
  %t8283 = getelementptr ptr, ptr %t8271, i32 3
  store ptr %t8282, ptr %t8283
  %t8284 = getelementptr ptr, ptr %t4, i32 1
  %t8285 = load ptr, ptr %t8284
  call void @__free_recursive(ptr %t8285)
  %t8286 = getelementptr ptr, ptr %t4, i32 2
  %t8287 = load ptr, ptr %t8286
  call void @__free_recursive(ptr %t8287)
  %t8290 = inttoptr i64 116 to ptr
  %t8291 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t8290, ptr %t8291
  %t8288 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t8271, ptr %t8288
  call void @__inc_ref(ptr %t8260)
  %t8289 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t8260, ptr %t8289
  %t8292 = getelementptr ptr, ptr %t8268, i32 1
  store ptr %t4, ptr %t8292
  %t8293 = call ptr @__alloc(i64 32, i32 3)
  %t8294 = inttoptr i64 223 to ptr
  %t8295 = getelementptr ptr, ptr %t8293, i32 0
  store ptr %t8294, ptr %t8295
  call void @__inc_ref(ptr %t5254)
  %t8296 = getelementptr ptr, ptr %t8293, i32 1
  store ptr %t5254, ptr %t8296
  call void @__inc_ref(ptr %t8256)
  %t8297 = getelementptr ptr, ptr %t8293, i32 2
  store ptr %t8256, ptr %t8297
  call void @__inc_ref(ptr %t8258)
  %t8298 = getelementptr ptr, ptr %t8293, i32 3
  store ptr %t8258, ptr %t8298
  %t8299 = getelementptr ptr, ptr %t8268, i32 2
  store ptr %t8293, ptr %t8299
  call void @__free_recursive(ptr %t8262)
  call void @__free_recursive(ptr %t8260)
  call void @__free_recursive(ptr %t8258)
  call void @__free_recursive(ptr %t8256)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t8268, ptr %t3
  br label %tco.loop.0
tco.case.arm.12.8300:
  %t8301 = call ptr @__alloc(i64 40, i32 4)
  %t8302 = inttoptr i64 92 to ptr
  %t8303 = getelementptr ptr, ptr %t8301, i32 0
  store ptr %t8302, ptr %t8303
  call void @__inc_ref(ptr %t8256)
  %t8304 = getelementptr ptr, ptr %t8301, i32 1
  store ptr %t8256, ptr %t8304
  call void @__inc_ref(ptr %t8258)
  %t8305 = getelementptr ptr, ptr %t8301, i32 2
  store ptr %t8258, ptr %t8305
  call void @__inc_ref(ptr %t8260)
  %t8306 = getelementptr ptr, ptr %t8301, i32 3
  store ptr %t8260, ptr %t8306
  %t8307 = getelementptr ptr, ptr %t8262, i32 1
  %t8308 = load ptr, ptr %t8307
  call void @__inc_ref(ptr %t8308)
  %t8309 = getelementptr ptr, ptr %t8301, i32 4
  store ptr %t8308, ptr %t8309
  %t8310 = getelementptr ptr, ptr %t4, i32 1
  %t8311 = load ptr, ptr %t8310
  call void @__free_recursive(ptr %t8311)
  %t8313 = inttoptr i64 280 to ptr
  %t8314 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t8313, ptr %t8314
  %t8312 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t8301, ptr %t8312
  call void @__free_recursive(ptr %t8262)
  call void @__free_recursive(ptr %t8260)
  call void @__free_recursive(ptr %t8258)
  call void @__free_recursive(ptr %t8256)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.8266:
  unreachable
tco.case.arm.95.8315:
  %t8316 = call ptr @__alloc(i64 24, i32 2)
  %t8317 = inttoptr i64 280 to ptr
  %t8318 = getelementptr ptr, ptr %t8316, i32 0
  store ptr %t8317, ptr %t8318
  %t8319 = getelementptr ptr, ptr %t5252, i32 1
  %t8320 = load ptr, ptr %t8319
  call void @__inc_ref(ptr %t8320)
  %t8321 = getelementptr ptr, ptr %t5252, i32 2
  %t8322 = load ptr, ptr %t8321
  call void @__inc_ref(ptr %t8322)
  %t8323 = getelementptr ptr, ptr %t4, i32 1
  %t8324 = load ptr, ptr %t8323
  call void @__free_recursive(ptr %t8324)
  %t8325 = getelementptr ptr, ptr %t4, i32 2
  %t8326 = load ptr, ptr %t8325
  call void @__free_recursive(ptr %t8326)
  %t8329 = inttoptr i64 77 to ptr
  %t8330 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t8329, ptr %t8330
  %t8327 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t8320, ptr %t8327
  %t8328 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t8322, ptr %t8328
  %t8331 = getelementptr ptr, ptr %t8316, i32 1
  store ptr %t4, ptr %t8331
  %t8332 = call ptr @__alloc(i64 16, i32 1)
  %t8333 = inttoptr i64 224 to ptr
  %t8334 = getelementptr ptr, ptr %t8332, i32 0
  store ptr %t8333, ptr %t8334
  call void @__inc_ref(ptr %t5254)
  %t8335 = getelementptr ptr, ptr %t8332, i32 1
  store ptr %t5254, ptr %t8335
  %t8336 = getelementptr ptr, ptr %t8316, i32 2
  store ptr %t8332, ptr %t8336
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t8316, ptr %t3
  br label %tco.loop.0
tco.case.arm.96.8337:
  %t8338 = getelementptr ptr, ptr %t5252, i32 1
  %t8339 = load ptr, ptr %t8338
  call void @__inc_ref(ptr %t8339)
  %t8340 = getelementptr ptr, ptr %t5252, i32 2
  %t8341 = load ptr, ptr %t8340
  call void @__inc_ref(ptr %t8341)
  %t8342 = getelementptr ptr, ptr %t8341, i32 0
  %t8343 = load ptr, ptr %t8342
  %t8344 = ptrtoint ptr %t8343 to i64
  switch i64 %t8344, label %tco.case.default.8345 [ i64 24, label %tco.case.arm.24.8346 i64 25, label %tco.case.arm.25.8361 i64 26, label %tco.case.arm.26.8389 i64 27, label %tco.case.arm.27.8423 ]
tco.case.arm.24.8346:
  %t8347 = call ptr @__alloc(i64 16, i32 1)
  %t8348 = inttoptr i64 31 to ptr
  %t8349 = getelementptr ptr, ptr %t8347, i32 0
  store ptr %t8348, ptr %t8349
  %t8350 = getelementptr ptr, ptr %t8341, i32 1
  %t8351 = load ptr, ptr %t8350
  call void @__inc_ref(ptr %t8351)
  %t8352 = getelementptr ptr, ptr %t8347, i32 1
  store ptr %t8351, ptr %t8352
  %t8353 = getelementptr ptr, ptr %t4, i32 1
  %t8354 = load ptr, ptr %t8353
  call void @__free_recursive(ptr %t8354)
  %t8355 = getelementptr ptr, ptr %t4, i32 2
  %t8356 = load ptr, ptr %t8355
  call void @__free_recursive(ptr %t8356)
  %t8359 = inttoptr i64 279 to ptr
  %t8360 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t8359, ptr %t8360
  call void @__inc_ref(ptr %t5254)
  %t8357 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t8357
  %t8358 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t8347, ptr %t8358
  call void @__free_recursive(ptr %t8341)
  call void @__free_recursive(ptr %t8339)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.25.8361:
  %t8362 = call ptr @__alloc(i64 40, i32 4)
  %t8363 = inttoptr i64 92 to ptr
  %t8364 = getelementptr ptr, ptr %t8362, i32 0
  store ptr %t8363, ptr %t8364
  call void @__inc_ref(ptr %t8339)
  %t8365 = getelementptr ptr, ptr %t8362, i32 1
  store ptr %t8339, ptr %t8365
  %t8366 = call ptr @__alloc(i64 16, i32 1)
  %t8367 = inttoptr i64 24 to ptr
  %t8368 = getelementptr ptr, ptr %t8366, i32 0
  store ptr %t8367, ptr %t8368
  %t8369 = getelementptr ptr, ptr %t8341, i32 1
  %t8370 = load ptr, ptr %t8369
  call void @__inc_ref(ptr %t8370)
  %t8371 = getelementptr ptr, ptr %t8366, i32 1
  store ptr %t8370, ptr %t8371
  %t8372 = getelementptr ptr, ptr %t8362, i32 2
  store ptr %t8366, ptr %t8372
  %t8373 = call ptr @__alloc(i64 8, i32 0)
  %t8374 = inttoptr i64 30 to ptr
  %t8375 = getelementptr ptr, ptr %t8373, i32 0
  store ptr %t8374, ptr %t8375
  %t8376 = getelementptr ptr, ptr %t8362, i32 3
  store ptr %t8373, ptr %t8376
  %t8377 = call ptr @__alloc(i64 16, i32 1)
  %t8378 = inttoptr i64 24 to ptr
  %t8379 = getelementptr ptr, ptr %t8377, i32 0
  store ptr %t8378, ptr %t8379
  %t8380 = getelementptr ptr, ptr %t8341, i32 2
  %t8381 = load ptr, ptr %t8380
  call void @__inc_ref(ptr %t8381)
  %t8382 = getelementptr ptr, ptr %t8377, i32 1
  store ptr %t8381, ptr %t8382
  %t8383 = getelementptr ptr, ptr %t8362, i32 4
  store ptr %t8377, ptr %t8383
  %t8384 = getelementptr ptr, ptr %t4, i32 1
  %t8385 = load ptr, ptr %t8384
  call void @__free_recursive(ptr %t8385)
  %t8387 = inttoptr i64 280 to ptr
  %t8388 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t8387, ptr %t8388
  %t8386 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t8362, ptr %t8386
  call void @__free_recursive(ptr %t8341)
  call void @__free_recursive(ptr %t8339)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.26.8389:
  %t8390 = call ptr @__alloc(i64 24, i32 2)
  %t8391 = inttoptr i64 280 to ptr
  %t8392 = getelementptr ptr, ptr %t8390, i32 0
  store ptr %t8391, ptr %t8392
  %t8393 = call ptr @__alloc(i64 40, i32 4)
  %t8394 = inttoptr i64 92 to ptr
  %t8395 = getelementptr ptr, ptr %t8393, i32 0
  store ptr %t8394, ptr %t8395
  call void @__inc_ref(ptr %t8339)
  %t8396 = getelementptr ptr, ptr %t8393, i32 1
  store ptr %t8339, ptr %t8396
  %t8397 = getelementptr ptr, ptr %t8341, i32 1
  %t8398 = load ptr, ptr %t8397
  call void @__inc_ref(ptr %t8398)
  %t8399 = getelementptr ptr, ptr %t8341, i32 2
  %t8400 = load ptr, ptr %t8399
  call void @__inc_ref(ptr %t8400)
  %t8401 = getelementptr ptr, ptr %t4, i32 1
  %t8402 = load ptr, ptr %t8401
  call void @__free_recursive(ptr %t8402)
  %t8403 = getelementptr ptr, ptr %t4, i32 2
  %t8404 = load ptr, ptr %t8403
  call void @__free_recursive(ptr %t8404)
  %t8407 = inttoptr i64 25 to ptr
  %t8408 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t8407, ptr %t8408
  %t8405 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t8398, ptr %t8405
  %t8406 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t8400, ptr %t8406
  %t8409 = getelementptr ptr, ptr %t8393, i32 2
  store ptr %t4, ptr %t8409
  %t8410 = call ptr @__alloc(i64 8, i32 0)
  %t8411 = inttoptr i64 30 to ptr
  %t8412 = getelementptr ptr, ptr %t8410, i32 0
  store ptr %t8411, ptr %t8412
  %t8413 = getelementptr ptr, ptr %t8393, i32 3
  store ptr %t8410, ptr %t8413
  %t8414 = call ptr @__alloc(i64 16, i32 1)
  %t8415 = inttoptr i64 24 to ptr
  %t8416 = getelementptr ptr, ptr %t8414, i32 0
  store ptr %t8415, ptr %t8416
  %t8417 = getelementptr ptr, ptr %t8341, i32 3
  %t8418 = load ptr, ptr %t8417
  call void @__inc_ref(ptr %t8418)
  %t8419 = getelementptr ptr, ptr %t8414, i32 1
  store ptr %t8418, ptr %t8419
  %t8420 = getelementptr ptr, ptr %t8393, i32 4
  store ptr %t8414, ptr %t8420
  %t8421 = getelementptr ptr, ptr %t8390, i32 1
  store ptr %t8393, ptr %t8421
  call void @__inc_ref(ptr %t5254)
  %t8422 = getelementptr ptr, ptr %t8390, i32 2
  store ptr %t5254, ptr %t8422
  call void @__free_recursive(ptr %t8341)
  call void @__free_recursive(ptr %t8339)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t8390, ptr %t3
  br label %tco.loop.0
tco.case.arm.27.8423:
  %t8424 = call ptr @__alloc(i64 24, i32 2)
  %t8425 = inttoptr i64 280 to ptr
  %t8426 = getelementptr ptr, ptr %t8424, i32 0
  store ptr %t8425, ptr %t8426
  %t8427 = call ptr @__alloc(i64 40, i32 4)
  %t8428 = inttoptr i64 92 to ptr
  %t8429 = getelementptr ptr, ptr %t8427, i32 0
  store ptr %t8428, ptr %t8429
  call void @__inc_ref(ptr %t8339)
  %t8430 = getelementptr ptr, ptr %t8427, i32 1
  store ptr %t8339, ptr %t8430
  %t8431 = getelementptr ptr, ptr %t8341, i32 1
  %t8432 = load ptr, ptr %t8431
  call void @__inc_ref(ptr %t8432)
  %t8433 = getelementptr ptr, ptr %t8341, i32 2
  %t8434 = load ptr, ptr %t8433
  call void @__inc_ref(ptr %t8434)
  %t8435 = getelementptr ptr, ptr %t4, i32 1
  %t8436 = load ptr, ptr %t8435
  call void @__free_recursive(ptr %t8436)
  %t8437 = getelementptr ptr, ptr %t4, i32 2
  %t8438 = load ptr, ptr %t8437
  call void @__free_recursive(ptr %t8438)
  %t8441 = inttoptr i64 25 to ptr
  %t8442 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t8441, ptr %t8442
  %t8439 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t8432, ptr %t8439
  %t8440 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t8434, ptr %t8440
  %t8443 = getelementptr ptr, ptr %t8427, i32 2
  store ptr %t4, ptr %t8443
  %t8444 = call ptr @__alloc(i64 8, i32 0)
  %t8445 = inttoptr i64 30 to ptr
  %t8446 = getelementptr ptr, ptr %t8444, i32 0
  store ptr %t8445, ptr %t8446
  %t8447 = getelementptr ptr, ptr %t8427, i32 3
  store ptr %t8444, ptr %t8447
  %t8448 = call ptr @__alloc(i64 24, i32 2)
  %t8449 = inttoptr i64 25 to ptr
  %t8450 = getelementptr ptr, ptr %t8448, i32 0
  store ptr %t8449, ptr %t8450
  %t8451 = getelementptr ptr, ptr %t8341, i32 3
  %t8452 = load ptr, ptr %t8451
  call void @__inc_ref(ptr %t8452)
  %t8453 = getelementptr ptr, ptr %t8448, i32 1
  store ptr %t8452, ptr %t8453
  %t8454 = getelementptr ptr, ptr %t8341, i32 4
  %t8455 = load ptr, ptr %t8454
  call void @__inc_ref(ptr %t8455)
  %t8456 = getelementptr ptr, ptr %t8448, i32 2
  store ptr %t8455, ptr %t8456
  %t8457 = getelementptr ptr, ptr %t8427, i32 4
  store ptr %t8448, ptr %t8457
  %t8458 = getelementptr ptr, ptr %t8424, i32 1
  store ptr %t8427, ptr %t8458
  call void @__inc_ref(ptr %t5254)
  %t8459 = getelementptr ptr, ptr %t8424, i32 2
  store ptr %t5254, ptr %t8459
  call void @__free_recursive(ptr %t8341)
  call void @__free_recursive(ptr %t8339)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t8424, ptr %t3
  br label %tco.loop.0
tco.case.default.8345:
  unreachable
tco.case.arm.97.8460:
  %t8461 = getelementptr ptr, ptr %t5252, i32 1
  %t8462 = load ptr, ptr %t8461
  call void @__inc_ref(ptr %t8462)
  %t8463 = getelementptr ptr, ptr %t5252, i32 2
  %t8464 = load ptr, ptr %t8463
  call void @__inc_ref(ptr %t8464)
  %t8465 = getelementptr ptr, ptr %t5252, i32 3
  %t8466 = load ptr, ptr %t8465
  call void @__inc_ref(ptr %t8466)
  %t8467 = getelementptr ptr, ptr %t8464, i32 0
  %t8468 = load ptr, ptr %t8467
  %t8469 = ptrtoint ptr %t8468 to i64
  switch i64 %t8469, label %tco.case.default.8470 [ i64 24, label %tco.case.arm.24.8471 i64 25, label %tco.case.arm.25.8485 i64 26, label %tco.case.arm.26.8510 i64 27, label %tco.case.arm.27.8538 ]
tco.case.arm.24.8471:
  %t8472 = call ptr @__alloc(i64 32, i32 3)
  %t8473 = inttoptr i64 54 to ptr
  %t8474 = getelementptr ptr, ptr %t8472, i32 0
  store ptr %t8473, ptr %t8474
  call void @__inc_ref(ptr %t8462)
  %t8475 = getelementptr ptr, ptr %t8472, i32 1
  store ptr %t8462, ptr %t8475
  %t8476 = getelementptr ptr, ptr %t8464, i32 1
  %t8477 = load ptr, ptr %t8476
  call void @__inc_ref(ptr %t8477)
  %t8478 = getelementptr ptr, ptr %t8472, i32 2
  store ptr %t8477, ptr %t8478
  call void @__inc_ref(ptr %t8466)
  %t8479 = getelementptr ptr, ptr %t8472, i32 3
  store ptr %t8466, ptr %t8479
  %t8480 = getelementptr ptr, ptr %t4, i32 1
  %t8481 = load ptr, ptr %t8480
  call void @__free_recursive(ptr %t8481)
  %t8483 = inttoptr i64 280 to ptr
  %t8484 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t8483, ptr %t8484
  %t8482 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t8472, ptr %t8482
  call void @__free_recursive(ptr %t8466)
  call void @__free_recursive(ptr %t8464)
  call void @__free_recursive(ptr %t8462)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.25.8485:
  %t8486 = call ptr @__alloc(i64 32, i32 3)
  %t8487 = inttoptr i64 54 to ptr
  %t8488 = getelementptr ptr, ptr %t8486, i32 0
  store ptr %t8487, ptr %t8488
  call void @__inc_ref(ptr %t8462)
  %t8489 = getelementptr ptr, ptr %t8486, i32 1
  store ptr %t8462, ptr %t8489
  %t8490 = getelementptr ptr, ptr %t8464, i32 2
  %t8491 = load ptr, ptr %t8490
  call void @__inc_ref(ptr %t8491)
  %t8492 = getelementptr ptr, ptr %t8486, i32 2
  store ptr %t8491, ptr %t8492
  call void @__inc_ref(ptr %t8466)
  %t8493 = getelementptr ptr, ptr %t8486, i32 3
  store ptr %t8466, ptr %t8493
  %t8494 = call ptr @__alloc(i64 32, i32 3)
  %t8495 = inttoptr i64 226 to ptr
  %t8496 = getelementptr ptr, ptr %t8494, i32 0
  store ptr %t8495, ptr %t8496
  call void @__inc_ref(ptr %t5254)
  %t8497 = getelementptr ptr, ptr %t8494, i32 1
  store ptr %t5254, ptr %t8497
  %t8498 = getelementptr ptr, ptr %t8464, i32 1
  %t8499 = load ptr, ptr %t8498
  call void @__inc_ref(ptr %t8499)
  %t8500 = getelementptr ptr, ptr %t8494, i32 2
  store ptr %t8499, ptr %t8500
  call void @__inc_ref(ptr %t8462)
  %t8501 = getelementptr ptr, ptr %t8494, i32 3
  store ptr %t8462, ptr %t8501
  %t8502 = getelementptr ptr, ptr %t4, i32 1
  %t8503 = load ptr, ptr %t8502
  call void @__free_recursive(ptr %t8503)
  %t8504 = getelementptr ptr, ptr %t4, i32 2
  %t8505 = load ptr, ptr %t8504
  call void @__free_recursive(ptr %t8505)
  %t8508 = inttoptr i64 280 to ptr
  %t8509 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t8508, ptr %t8509
  %t8506 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t8486, ptr %t8506
  %t8507 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t8494, ptr %t8507
  call void @__free_recursive(ptr %t8466)
  call void @__free_recursive(ptr %t8464)
  call void @__free_recursive(ptr %t8462)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.26.8510:
  %t8511 = call ptr @__alloc(i64 32, i32 3)
  %t8512 = inttoptr i64 54 to ptr
  %t8513 = getelementptr ptr, ptr %t8511, i32 0
  store ptr %t8512, ptr %t8513
  call void @__inc_ref(ptr %t8462)
  %t8514 = getelementptr ptr, ptr %t8511, i32 1
  store ptr %t8462, ptr %t8514
  %t8515 = getelementptr ptr, ptr %t8464, i32 3
  %t8516 = load ptr, ptr %t8515
  call void @__inc_ref(ptr %t8516)
  %t8517 = getelementptr ptr, ptr %t8511, i32 2
  store ptr %t8516, ptr %t8517
  call void @__inc_ref(ptr %t8466)
  %t8518 = getelementptr ptr, ptr %t8511, i32 3
  store ptr %t8466, ptr %t8518
  %t8519 = call ptr @__alloc(i64 40, i32 4)
  %t8520 = inttoptr i64 227 to ptr
  %t8521 = getelementptr ptr, ptr %t8519, i32 0
  store ptr %t8520, ptr %t8521
  call void @__inc_ref(ptr %t5254)
  %t8522 = getelementptr ptr, ptr %t8519, i32 1
  store ptr %t5254, ptr %t8522
  %t8523 = getelementptr ptr, ptr %t8464, i32 1
  %t8524 = load ptr, ptr %t8523
  call void @__inc_ref(ptr %t8524)
  %t8525 = getelementptr ptr, ptr %t8519, i32 2
  store ptr %t8524, ptr %t8525
  %t8526 = getelementptr ptr, ptr %t8464, i32 2
  %t8527 = load ptr, ptr %t8526
  call void @__inc_ref(ptr %t8527)
  %t8528 = getelementptr ptr, ptr %t8519, i32 3
  store ptr %t8527, ptr %t8528
  call void @__inc_ref(ptr %t8462)
  %t8529 = getelementptr ptr, ptr %t8519, i32 4
  store ptr %t8462, ptr %t8529
  %t8530 = getelementptr ptr, ptr %t4, i32 1
  %t8531 = load ptr, ptr %t8530
  call void @__free_recursive(ptr %t8531)
  %t8532 = getelementptr ptr, ptr %t4, i32 2
  %t8533 = load ptr, ptr %t8532
  call void @__free_recursive(ptr %t8533)
  %t8536 = inttoptr i64 280 to ptr
  %t8537 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t8536, ptr %t8537
  %t8534 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t8511, ptr %t8534
  %t8535 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t8519, ptr %t8535
  call void @__free_recursive(ptr %t8466)
  call void @__free_recursive(ptr %t8464)
  call void @__free_recursive(ptr %t8462)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.27.8538:
  %t8539 = call ptr @__alloc(i64 32, i32 3)
  %t8540 = inttoptr i64 54 to ptr
  %t8541 = getelementptr ptr, ptr %t8539, i32 0
  store ptr %t8540, ptr %t8541
  call void @__inc_ref(ptr %t8462)
  %t8542 = getelementptr ptr, ptr %t8539, i32 1
  store ptr %t8462, ptr %t8542
  %t8543 = getelementptr ptr, ptr %t8464, i32 4
  %t8544 = load ptr, ptr %t8543
  call void @__inc_ref(ptr %t8544)
  %t8545 = getelementptr ptr, ptr %t8539, i32 2
  store ptr %t8544, ptr %t8545
  call void @__inc_ref(ptr %t8466)
  %t8546 = getelementptr ptr, ptr %t8539, i32 3
  store ptr %t8466, ptr %t8546
  %t8547 = call ptr @__alloc(i64 48, i32 5)
  %t8548 = inttoptr i64 229 to ptr
  %t8549 = getelementptr ptr, ptr %t8547, i32 0
  store ptr %t8548, ptr %t8549
  call void @__inc_ref(ptr %t5254)
  %t8550 = getelementptr ptr, ptr %t8547, i32 1
  store ptr %t5254, ptr %t8550
  %t8551 = getelementptr ptr, ptr %t8464, i32 1
  %t8552 = load ptr, ptr %t8551
  call void @__inc_ref(ptr %t8552)
  %t8553 = getelementptr ptr, ptr %t8547, i32 2
  store ptr %t8552, ptr %t8553
  %t8554 = getelementptr ptr, ptr %t8464, i32 2
  %t8555 = load ptr, ptr %t8554
  call void @__inc_ref(ptr %t8555)
  %t8556 = getelementptr ptr, ptr %t8547, i32 3
  store ptr %t8555, ptr %t8556
  %t8557 = getelementptr ptr, ptr %t8464, i32 3
  %t8558 = load ptr, ptr %t8557
  call void @__inc_ref(ptr %t8558)
  %t8559 = getelementptr ptr, ptr %t8547, i32 4
  store ptr %t8558, ptr %t8559
  call void @__inc_ref(ptr %t8462)
  %t8560 = getelementptr ptr, ptr %t8547, i32 5
  store ptr %t8462, ptr %t8560
  %t8561 = getelementptr ptr, ptr %t4, i32 1
  %t8562 = load ptr, ptr %t8561
  call void @__free_recursive(ptr %t8562)
  %t8563 = getelementptr ptr, ptr %t4, i32 2
  %t8564 = load ptr, ptr %t8563
  call void @__free_recursive(ptr %t8564)
  %t8567 = inttoptr i64 280 to ptr
  %t8568 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t8567, ptr %t8568
  %t8565 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t8539, ptr %t8565
  %t8566 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t8547, ptr %t8566
  call void @__free_recursive(ptr %t8466)
  call void @__free_recursive(ptr %t8464)
  call void @__free_recursive(ptr %t8462)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.8470:
  unreachable
tco.case.arm.98.8569:
  %t8570 = call ptr @__alloc(i64 24, i32 2)
  %t8571 = inttoptr i64 280 to ptr
  %t8572 = getelementptr ptr, ptr %t8570, i32 0
  store ptr %t8571, ptr %t8572
  %t8573 = call ptr @__alloc(i64 32, i32 3)
  %t8574 = inttoptr i64 97 to ptr
  %t8575 = getelementptr ptr, ptr %t8573, i32 0
  store ptr %t8574, ptr %t8575
  %t8576 = getelementptr ptr, ptr %t5252, i32 1
  %t8577 = load ptr, ptr %t8576
  call void @__inc_ref(ptr %t8577)
  %t8578 = getelementptr ptr, ptr %t8573, i32 1
  store ptr %t8577, ptr %t8578
  %t8579 = getelementptr ptr, ptr %t5252, i32 2
  %t8580 = load ptr, ptr %t8579
  call void @__inc_ref(ptr %t8580)
  %t8581 = getelementptr ptr, ptr %t8580, i32 0
  %t8582 = load ptr, ptr %t8581
  %t8583 = ptrtoint ptr %t8582 to i64
  switch i64 %t8583, label %case.default.8584 [ i64 28, label %case.arm.28.8586 i64 29, label %case.arm.29.8600 ]
case.arm.28.8586:
  %t8588 = getelementptr ptr, ptr %t8580, i32 2
  %t8589 = load ptr, ptr %t8588
  call void @__inc_ref(ptr %t8589)
  %t8590 = getelementptr ptr, ptr %t8580, i32 3
  %t8591 = load ptr, ptr %t8590
  call void @__inc_ref(ptr %t8591)
  %t8592 = getelementptr ptr, ptr %t4, i32 1
  %t8593 = load ptr, ptr %t8592
  call void @__free_recursive(ptr %t8593)
  %t8594 = getelementptr ptr, ptr %t4, i32 2
  %t8595 = load ptr, ptr %t8594
  call void @__free_recursive(ptr %t8595)
  %t8598 = inttoptr i64 25 to ptr
  %t8599 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t8598, ptr %t8599
  %t8596 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t8589, ptr %t8596
  %t8597 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t8591, ptr %t8597
  br label %case.end.28.8587
case.end.28.8587:
  br label %case.join.8585
case.arm.29.8600:
  %t8602 = call ptr @__alloc(i64 32, i32 3)
  %t8603 = inttoptr i64 26 to ptr
  %t8604 = getelementptr ptr, ptr %t8602, i32 0
  store ptr %t8603, ptr %t8604
  %t8605 = getelementptr ptr, ptr %t8580, i32 2
  %t8606 = load ptr, ptr %t8605
  call void @__inc_ref(ptr %t8606)
  %t8607 = getelementptr ptr, ptr %t8602, i32 1
  store ptr %t8606, ptr %t8607
  %t8608 = getelementptr ptr, ptr %t8580, i32 3
  %t8609 = load ptr, ptr %t8608
  call void @__inc_ref(ptr %t8609)
  %t8610 = getelementptr ptr, ptr %t8602, i32 2
  store ptr %t8609, ptr %t8610
  %t8611 = getelementptr ptr, ptr %t8580, i32 4
  %t8612 = load ptr, ptr %t8611
  call void @__inc_ref(ptr %t8612)
  %t8613 = getelementptr ptr, ptr %t8602, i32 3
  store ptr %t8612, ptr %t8613
  call void @__free_recursive(ptr %t4)
  br label %case.end.29.8601
case.end.29.8601:
  br label %case.join.8585
case.default.8584:
  unreachable
case.join.8585:
  %t8614 = phi ptr [ %t4, %case.end.28.8587 ], [ %t8602, %case.end.29.8601 ]
  call void @__free_recursive(ptr %t8580)
  %t8615 = getelementptr ptr, ptr %t8573, i32 2
  store ptr %t8614, ptr %t8615
  %t8616 = getelementptr ptr, ptr %t5252, i32 3
  %t8617 = load ptr, ptr %t8616
  call void @__inc_ref(ptr %t8617)
  %t8618 = getelementptr ptr, ptr %t8573, i32 3
  store ptr %t8617, ptr %t8618
  %t8619 = getelementptr ptr, ptr %t8570, i32 1
  store ptr %t8573, ptr %t8619
  call void @__inc_ref(ptr %t5254)
  %t8620 = getelementptr ptr, ptr %t8570, i32 2
  store ptr %t5254, ptr %t8620
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t8570, ptr %t3
  br label %tco.loop.0
tco.case.arm.99.8621:
  %t8622 = getelementptr ptr, ptr %t5252, i32 2
  %t8623 = load ptr, ptr %t8622
  call void @__inc_ref(ptr %t8623)
  %t8624 = getelementptr ptr, ptr %t8623, i32 0
  %t8625 = load ptr, ptr %t8624
  %t8626 = ptrtoint ptr %t8625 to i64
  switch i64 %t8626, label %case.default.8627 [ i64 24, label %case.arm.24.8629 i64 25, label %case.arm.25.8641 i64 26, label %case.arm.26.8660 i64 27, label %case.arm.27.8686 ]
case.arm.24.8629:
  %t8631 = call ptr @__alloc(i64 24, i32 2)
  %t8632 = inttoptr i64 15 to ptr
  %t8633 = getelementptr ptr, ptr %t8631, i32 0
  store ptr %t8632, ptr %t8633
  %t8634 = getelementptr ptr, ptr %t8623, i32 1
  %t8635 = load ptr, ptr %t8634
  call void @__inc_ref(ptr %t8635)
  %t8636 = getelementptr ptr, ptr %t8631, i32 1
  store ptr %t8635, ptr %t8636
  %t8637 = call ptr @__alloc(i64 8, i32 0)
  %t8638 = inttoptr i64 13 to ptr
  %t8639 = getelementptr ptr, ptr %t8637, i32 0
  store ptr %t8638, ptr %t8639
  %t8640 = getelementptr ptr, ptr %t8631, i32 2
  store ptr %t8637, ptr %t8640
  br label %case.end.24.8630
case.end.24.8630:
  br label %case.join.8628
case.arm.25.8641:
  %t8643 = call ptr @__alloc(i64 24, i32 2)
  %t8644 = inttoptr i64 15 to ptr
  %t8645 = getelementptr ptr, ptr %t8643, i32 0
  store ptr %t8644, ptr %t8645
  %t8646 = getelementptr ptr, ptr %t8623, i32 1
  %t8647 = load ptr, ptr %t8646
  call void @__inc_ref(ptr %t8647)
  %t8648 = getelementptr ptr, ptr %t8643, i32 1
  store ptr %t8647, ptr %t8648
  %t8649 = call ptr @__alloc(i64 24, i32 2)
  %t8650 = inttoptr i64 14 to ptr
  %t8651 = getelementptr ptr, ptr %t8649, i32 0
  store ptr %t8650, ptr %t8651
  %t8652 = getelementptr ptr, ptr %t8623, i32 2
  %t8653 = load ptr, ptr %t8652
  call void @__inc_ref(ptr %t8653)
  %t8654 = getelementptr ptr, ptr %t8649, i32 1
  store ptr %t8653, ptr %t8654
  %t8655 = call ptr @__alloc(i64 8, i32 0)
  %t8656 = inttoptr i64 13 to ptr
  %t8657 = getelementptr ptr, ptr %t8655, i32 0
  store ptr %t8656, ptr %t8657
  %t8658 = getelementptr ptr, ptr %t8649, i32 2
  store ptr %t8655, ptr %t8658
  %t8659 = getelementptr ptr, ptr %t8643, i32 2
  store ptr %t8649, ptr %t8659
  br label %case.end.25.8642
case.end.25.8642:
  br label %case.join.8628
case.arm.26.8660:
  %t8662 = call ptr @__alloc(i64 24, i32 2)
  %t8663 = inttoptr i64 15 to ptr
  %t8664 = getelementptr ptr, ptr %t8662, i32 0
  store ptr %t8663, ptr %t8664
  %t8665 = getelementptr ptr, ptr %t8623, i32 1
  %t8666 = load ptr, ptr %t8665
  call void @__inc_ref(ptr %t8666)
  %t8667 = getelementptr ptr, ptr %t8662, i32 1
  store ptr %t8666, ptr %t8667
  %t8668 = call ptr @__alloc(i64 24, i32 2)
  %t8669 = inttoptr i64 14 to ptr
  %t8670 = getelementptr ptr, ptr %t8668, i32 0
  store ptr %t8669, ptr %t8670
  %t8671 = getelementptr ptr, ptr %t8623, i32 2
  %t8672 = load ptr, ptr %t8671
  call void @__inc_ref(ptr %t8672)
  %t8673 = getelementptr ptr, ptr %t8668, i32 1
  store ptr %t8672, ptr %t8673
  %t8674 = call ptr @__alloc(i64 24, i32 2)
  %t8675 = inttoptr i64 14 to ptr
  %t8676 = getelementptr ptr, ptr %t8674, i32 0
  store ptr %t8675, ptr %t8676
  %t8677 = getelementptr ptr, ptr %t8623, i32 3
  %t8678 = load ptr, ptr %t8677
  call void @__inc_ref(ptr %t8678)
  %t8679 = getelementptr ptr, ptr %t8674, i32 1
  store ptr %t8678, ptr %t8679
  %t8680 = call ptr @__alloc(i64 8, i32 0)
  %t8681 = inttoptr i64 13 to ptr
  %t8682 = getelementptr ptr, ptr %t8680, i32 0
  store ptr %t8681, ptr %t8682
  %t8683 = getelementptr ptr, ptr %t8674, i32 2
  store ptr %t8680, ptr %t8683
  %t8684 = getelementptr ptr, ptr %t8668, i32 2
  store ptr %t8674, ptr %t8684
  %t8685 = getelementptr ptr, ptr %t8662, i32 2
  store ptr %t8668, ptr %t8685
  br label %case.end.26.8661
case.end.26.8661:
  br label %case.join.8628
case.arm.27.8686:
  %t8688 = call ptr @__alloc(i64 24, i32 2)
  %t8689 = inttoptr i64 15 to ptr
  %t8690 = getelementptr ptr, ptr %t8688, i32 0
  store ptr %t8689, ptr %t8690
  %t8691 = getelementptr ptr, ptr %t8623, i32 1
  %t8692 = load ptr, ptr %t8691
  call void @__inc_ref(ptr %t8692)
  %t8693 = getelementptr ptr, ptr %t8688, i32 1
  store ptr %t8692, ptr %t8693
  %t8694 = call ptr @__alloc(i64 24, i32 2)
  %t8695 = inttoptr i64 14 to ptr
  %t8696 = getelementptr ptr, ptr %t8694, i32 0
  store ptr %t8695, ptr %t8696
  %t8697 = getelementptr ptr, ptr %t8623, i32 2
  %t8698 = load ptr, ptr %t8697
  call void @__inc_ref(ptr %t8698)
  %t8699 = getelementptr ptr, ptr %t8694, i32 1
  store ptr %t8698, ptr %t8699
  %t8700 = call ptr @__alloc(i64 24, i32 2)
  %t8701 = inttoptr i64 14 to ptr
  %t8702 = getelementptr ptr, ptr %t8700, i32 0
  store ptr %t8701, ptr %t8702
  %t8703 = getelementptr ptr, ptr %t8623, i32 3
  %t8704 = load ptr, ptr %t8703
  call void @__inc_ref(ptr %t8704)
  %t8705 = getelementptr ptr, ptr %t8700, i32 1
  store ptr %t8704, ptr %t8705
  %t8706 = call ptr @__alloc(i64 24, i32 2)
  %t8707 = inttoptr i64 14 to ptr
  %t8708 = getelementptr ptr, ptr %t8706, i32 0
  store ptr %t8707, ptr %t8708
  %t8709 = getelementptr ptr, ptr %t8623, i32 4
  %t8710 = load ptr, ptr %t8709
  call void @__inc_ref(ptr %t8710)
  %t8711 = getelementptr ptr, ptr %t8706, i32 1
  store ptr %t8710, ptr %t8711
  %t8712 = call ptr @__alloc(i64 8, i32 0)
  %t8713 = inttoptr i64 13 to ptr
  %t8714 = getelementptr ptr, ptr %t8712, i32 0
  store ptr %t8713, ptr %t8714
  %t8715 = getelementptr ptr, ptr %t8706, i32 2
  store ptr %t8712, ptr %t8715
  %t8716 = getelementptr ptr, ptr %t8700, i32 2
  store ptr %t8706, ptr %t8716
  %t8717 = getelementptr ptr, ptr %t8694, i32 2
  store ptr %t8700, ptr %t8717
  %t8718 = getelementptr ptr, ptr %t8688, i32 2
  store ptr %t8694, ptr %t8718
  br label %case.end.27.8687
case.end.27.8687:
  br label %case.join.8628
case.default.8627:
  unreachable
case.join.8628:
  %t8719 = phi ptr [ %t8631, %case.end.24.8630 ], [ %t8643, %case.end.25.8642 ], [ %t8662, %case.end.26.8661 ], [ %t8688, %case.end.27.8687 ]
  %t8720 = getelementptr ptr, ptr %t8719, i32 0
  %t8721 = load ptr, ptr %t8720
  %t8722 = ptrtoint ptr %t8721 to i64
  switch i64 %t8722, label %tco.case.default.8723 [ i64 15, label %tco.case.arm.15.8724 ]
tco.case.arm.15.8724:
  %t8725 = getelementptr ptr, ptr %t8719, i32 1
  %t8726 = load ptr, ptr %t8725
  call void @__inc_ref(ptr %t8726)
  %t8727 = getelementptr ptr, ptr %t8719, i32 2
  %t8728 = load ptr, ptr %t8727
  call void @__inc_ref(ptr %t8728)
  call void @__free_recursive(ptr %t8719)
  %t8729 = getelementptr ptr, ptr %t5252, i32 4
  %t8730 = load ptr, ptr %t8729
  call void @__inc_ref(ptr %t8730)
  %t8731 = getelementptr ptr, ptr %t8730, i32 0
  %t8732 = load ptr, ptr %t8731
  %t8733 = ptrtoint ptr %t8732 to i64
  switch i64 %t8733, label %tco.case.default.8734 [ i64 24, label %tco.case.arm.24.8735 i64 25, label %tco.case.arm.25.8765 i64 26, label %tco.case.arm.26.8802 i64 27, label %tco.case.arm.27.8846 ]
tco.case.arm.24.8735:
  %t8736 = call ptr @__alloc(i64 40, i32 4)
  %t8737 = inttoptr i64 106 to ptr
  %t8738 = getelementptr ptr, ptr %t8736, i32 0
  store ptr %t8737, ptr %t8738
  %t8739 = getelementptr ptr, ptr %t5252, i32 1
  %t8740 = load ptr, ptr %t8739
  call void @__inc_ref(ptr %t8740)
  %t8741 = getelementptr ptr, ptr %t8736, i32 1
  store ptr %t8740, ptr %t8741
  call void @__inc_ref(ptr %t8726)
  %t8742 = getelementptr ptr, ptr %t8736, i32 2
  store ptr %t8726, ptr %t8742
  call void @__inc_ref(ptr %t8728)
  %t8743 = getelementptr ptr, ptr %t5252, i32 3
  %t8744 = load ptr, ptr %t8743
  call void @__inc_ref(ptr %t8744)
  %t8745 = call ptr @__alloc(i64 8, i32 0)
  %t8746 = inttoptr i64 13 to ptr
  %t8747 = getelementptr ptr, ptr %t8745, i32 0
  store ptr %t8746, ptr %t8747
  %t8748 = call ptr @__alloc(i64 8, i32 0)
  %t8749 = inttoptr i64 118 to ptr
  %t8750 = getelementptr ptr, ptr %t8748, i32 0
  store ptr %t8749, ptr %t8750
  %t8751 = call ptr @v_$cps$appendList(ptr %t8744, ptr %t8745, ptr %t8748)
  %t8752 = call ptr @__alloc(i64 8, i32 0)
  %t8753 = inttoptr i64 118 to ptr
  %t8754 = getelementptr ptr, ptr %t8752, i32 0
  store ptr %t8753, ptr %t8754
  %t8755 = call ptr @v_$cps$appendList(ptr %t8728, ptr %t8751, ptr %t8752)
  %t8756 = getelementptr ptr, ptr %t8736, i32 3
  store ptr %t8755, ptr %t8756
  %t8757 = getelementptr ptr, ptr %t8730, i32 1
  %t8758 = load ptr, ptr %t8757
  call void @__inc_ref(ptr %t8758)
  %t8759 = getelementptr ptr, ptr %t8736, i32 4
  store ptr %t8758, ptr %t8759
  %t8760 = getelementptr ptr, ptr %t4, i32 1
  %t8761 = load ptr, ptr %t8760
  call void @__free_recursive(ptr %t8761)
  %t8763 = inttoptr i64 280 to ptr
  %t8764 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t8763, ptr %t8764
  %t8762 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t8736, ptr %t8762
  call void @__free_recursive(ptr %t8730)
  call void @__free_recursive(ptr %t8728)
  call void @__free_recursive(ptr %t8726)
  call void @__free_recursive(ptr %t8623)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.25.8765:
  %t8766 = call ptr @__alloc(i64 40, i32 4)
  %t8767 = inttoptr i64 106 to ptr
  %t8768 = getelementptr ptr, ptr %t8766, i32 0
  store ptr %t8767, ptr %t8768
  %t8769 = getelementptr ptr, ptr %t5252, i32 1
  %t8770 = load ptr, ptr %t8769
  call void @__inc_ref(ptr %t8770)
  %t8771 = getelementptr ptr, ptr %t8766, i32 1
  store ptr %t8770, ptr %t8771
  call void @__inc_ref(ptr %t8726)
  %t8772 = getelementptr ptr, ptr %t8766, i32 2
  store ptr %t8726, ptr %t8772
  call void @__inc_ref(ptr %t8728)
  %t8773 = getelementptr ptr, ptr %t5252, i32 3
  %t8774 = load ptr, ptr %t8773
  call void @__inc_ref(ptr %t8774)
  %t8775 = call ptr @__alloc(i64 24, i32 2)
  %t8776 = inttoptr i64 14 to ptr
  %t8777 = getelementptr ptr, ptr %t8775, i32 0
  store ptr %t8776, ptr %t8777
  %t8778 = getelementptr ptr, ptr %t8730, i32 1
  %t8779 = load ptr, ptr %t8778
  call void @__inc_ref(ptr %t8779)
  %t8780 = getelementptr ptr, ptr %t8775, i32 1
  store ptr %t8779, ptr %t8780
  %t8781 = call ptr @__alloc(i64 8, i32 0)
  %t8782 = inttoptr i64 13 to ptr
  %t8783 = getelementptr ptr, ptr %t8781, i32 0
  store ptr %t8782, ptr %t8783
  %t8784 = getelementptr ptr, ptr %t8775, i32 2
  store ptr %t8781, ptr %t8784
  %t8785 = call ptr @__alloc(i64 8, i32 0)
  %t8786 = inttoptr i64 118 to ptr
  %t8787 = getelementptr ptr, ptr %t8785, i32 0
  store ptr %t8786, ptr %t8787
  %t8788 = call ptr @v_$cps$appendList(ptr %t8774, ptr %t8775, ptr %t8785)
  %t8789 = call ptr @__alloc(i64 8, i32 0)
  %t8790 = inttoptr i64 118 to ptr
  %t8791 = getelementptr ptr, ptr %t8789, i32 0
  store ptr %t8790, ptr %t8791
  %t8792 = call ptr @v_$cps$appendList(ptr %t8728, ptr %t8788, ptr %t8789)
  %t8793 = getelementptr ptr, ptr %t8766, i32 3
  store ptr %t8792, ptr %t8793
  %t8794 = getelementptr ptr, ptr %t8730, i32 2
  %t8795 = load ptr, ptr %t8794
  call void @__inc_ref(ptr %t8795)
  %t8796 = getelementptr ptr, ptr %t8766, i32 4
  store ptr %t8795, ptr %t8796
  %t8797 = getelementptr ptr, ptr %t4, i32 1
  %t8798 = load ptr, ptr %t8797
  call void @__free_recursive(ptr %t8798)
  %t8800 = inttoptr i64 280 to ptr
  %t8801 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t8800, ptr %t8801
  %t8799 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t8766, ptr %t8799
  call void @__free_recursive(ptr %t8730)
  call void @__free_recursive(ptr %t8728)
  call void @__free_recursive(ptr %t8726)
  call void @__free_recursive(ptr %t8623)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.26.8802:
  %t8803 = call ptr @__alloc(i64 40, i32 4)
  %t8804 = inttoptr i64 106 to ptr
  %t8805 = getelementptr ptr, ptr %t8803, i32 0
  store ptr %t8804, ptr %t8805
  %t8806 = getelementptr ptr, ptr %t5252, i32 1
  %t8807 = load ptr, ptr %t8806
  call void @__inc_ref(ptr %t8807)
  %t8808 = getelementptr ptr, ptr %t8803, i32 1
  store ptr %t8807, ptr %t8808
  call void @__inc_ref(ptr %t8726)
  %t8809 = getelementptr ptr, ptr %t8803, i32 2
  store ptr %t8726, ptr %t8809
  call void @__inc_ref(ptr %t8728)
  %t8810 = getelementptr ptr, ptr %t5252, i32 3
  %t8811 = load ptr, ptr %t8810
  call void @__inc_ref(ptr %t8811)
  %t8812 = call ptr @__alloc(i64 24, i32 2)
  %t8813 = inttoptr i64 14 to ptr
  %t8814 = getelementptr ptr, ptr %t8812, i32 0
  store ptr %t8813, ptr %t8814
  %t8815 = getelementptr ptr, ptr %t8730, i32 1
  %t8816 = load ptr, ptr %t8815
  call void @__inc_ref(ptr %t8816)
  %t8817 = getelementptr ptr, ptr %t8812, i32 1
  store ptr %t8816, ptr %t8817
  %t8818 = call ptr @__alloc(i64 24, i32 2)
  %t8819 = inttoptr i64 14 to ptr
  %t8820 = getelementptr ptr, ptr %t8818, i32 0
  store ptr %t8819, ptr %t8820
  %t8821 = getelementptr ptr, ptr %t8730, i32 2
  %t8822 = load ptr, ptr %t8821
  call void @__inc_ref(ptr %t8822)
  %t8823 = getelementptr ptr, ptr %t8818, i32 1
  store ptr %t8822, ptr %t8823
  %t8824 = call ptr @__alloc(i64 8, i32 0)
  %t8825 = inttoptr i64 13 to ptr
  %t8826 = getelementptr ptr, ptr %t8824, i32 0
  store ptr %t8825, ptr %t8826
  %t8827 = getelementptr ptr, ptr %t8818, i32 2
  store ptr %t8824, ptr %t8827
  %t8828 = getelementptr ptr, ptr %t8812, i32 2
  store ptr %t8818, ptr %t8828
  %t8829 = call ptr @__alloc(i64 8, i32 0)
  %t8830 = inttoptr i64 118 to ptr
  %t8831 = getelementptr ptr, ptr %t8829, i32 0
  store ptr %t8830, ptr %t8831
  %t8832 = call ptr @v_$cps$appendList(ptr %t8811, ptr %t8812, ptr %t8829)
  %t8833 = call ptr @__alloc(i64 8, i32 0)
  %t8834 = inttoptr i64 118 to ptr
  %t8835 = getelementptr ptr, ptr %t8833, i32 0
  store ptr %t8834, ptr %t8835
  %t8836 = call ptr @v_$cps$appendList(ptr %t8728, ptr %t8832, ptr %t8833)
  %t8837 = getelementptr ptr, ptr %t8803, i32 3
  store ptr %t8836, ptr %t8837
  %t8838 = getelementptr ptr, ptr %t8730, i32 3
  %t8839 = load ptr, ptr %t8838
  call void @__inc_ref(ptr %t8839)
  %t8840 = getelementptr ptr, ptr %t8803, i32 4
  store ptr %t8839, ptr %t8840
  %t8841 = getelementptr ptr, ptr %t4, i32 1
  %t8842 = load ptr, ptr %t8841
  call void @__free_recursive(ptr %t8842)
  %t8844 = inttoptr i64 280 to ptr
  %t8845 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t8844, ptr %t8845
  %t8843 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t8803, ptr %t8843
  call void @__free_recursive(ptr %t8730)
  call void @__free_recursive(ptr %t8728)
  call void @__free_recursive(ptr %t8726)
  call void @__free_recursive(ptr %t8623)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.27.8846:
  %t8847 = call ptr @__alloc(i64 40, i32 4)
  %t8848 = inttoptr i64 106 to ptr
  %t8849 = getelementptr ptr, ptr %t8847, i32 0
  store ptr %t8848, ptr %t8849
  %t8850 = getelementptr ptr, ptr %t5252, i32 1
  %t8851 = load ptr, ptr %t8850
  call void @__inc_ref(ptr %t8851)
  %t8852 = getelementptr ptr, ptr %t8847, i32 1
  store ptr %t8851, ptr %t8852
  call void @__inc_ref(ptr %t8726)
  %t8853 = getelementptr ptr, ptr %t8847, i32 2
  store ptr %t8726, ptr %t8853
  call void @__inc_ref(ptr %t8728)
  %t8854 = getelementptr ptr, ptr %t5252, i32 3
  %t8855 = load ptr, ptr %t8854
  call void @__inc_ref(ptr %t8855)
  %t8856 = call ptr @__alloc(i64 24, i32 2)
  %t8857 = inttoptr i64 14 to ptr
  %t8858 = getelementptr ptr, ptr %t8856, i32 0
  store ptr %t8857, ptr %t8858
  %t8859 = getelementptr ptr, ptr %t8730, i32 1
  %t8860 = load ptr, ptr %t8859
  call void @__inc_ref(ptr %t8860)
  %t8861 = getelementptr ptr, ptr %t8856, i32 1
  store ptr %t8860, ptr %t8861
  %t8862 = call ptr @__alloc(i64 24, i32 2)
  %t8863 = inttoptr i64 14 to ptr
  %t8864 = getelementptr ptr, ptr %t8862, i32 0
  store ptr %t8863, ptr %t8864
  %t8865 = getelementptr ptr, ptr %t8730, i32 2
  %t8866 = load ptr, ptr %t8865
  call void @__inc_ref(ptr %t8866)
  %t8867 = getelementptr ptr, ptr %t8862, i32 1
  store ptr %t8866, ptr %t8867
  %t8868 = call ptr @__alloc(i64 24, i32 2)
  %t8869 = inttoptr i64 14 to ptr
  %t8870 = getelementptr ptr, ptr %t8868, i32 0
  store ptr %t8869, ptr %t8870
  %t8871 = getelementptr ptr, ptr %t8730, i32 3
  %t8872 = load ptr, ptr %t8871
  call void @__inc_ref(ptr %t8872)
  %t8873 = getelementptr ptr, ptr %t8868, i32 1
  store ptr %t8872, ptr %t8873
  %t8874 = call ptr @__alloc(i64 8, i32 0)
  %t8875 = inttoptr i64 13 to ptr
  %t8876 = getelementptr ptr, ptr %t8874, i32 0
  store ptr %t8875, ptr %t8876
  %t8877 = getelementptr ptr, ptr %t8868, i32 2
  store ptr %t8874, ptr %t8877
  %t8878 = getelementptr ptr, ptr %t8862, i32 2
  store ptr %t8868, ptr %t8878
  %t8879 = getelementptr ptr, ptr %t8856, i32 2
  store ptr %t8862, ptr %t8879
  %t8880 = call ptr @__alloc(i64 8, i32 0)
  %t8881 = inttoptr i64 118 to ptr
  %t8882 = getelementptr ptr, ptr %t8880, i32 0
  store ptr %t8881, ptr %t8882
  %t8883 = call ptr @v_$cps$appendList(ptr %t8855, ptr %t8856, ptr %t8880)
  %t8884 = call ptr @__alloc(i64 8, i32 0)
  %t8885 = inttoptr i64 118 to ptr
  %t8886 = getelementptr ptr, ptr %t8884, i32 0
  store ptr %t8885, ptr %t8886
  %t8887 = call ptr @v_$cps$appendList(ptr %t8728, ptr %t8883, ptr %t8884)
  %t8888 = getelementptr ptr, ptr %t8847, i32 3
  store ptr %t8887, ptr %t8888
  %t8889 = getelementptr ptr, ptr %t8730, i32 4
  %t8890 = load ptr, ptr %t8889
  call void @__inc_ref(ptr %t8890)
  %t8891 = getelementptr ptr, ptr %t8847, i32 4
  store ptr %t8890, ptr %t8891
  %t8892 = getelementptr ptr, ptr %t4, i32 1
  %t8893 = load ptr, ptr %t8892
  call void @__free_recursive(ptr %t8893)
  %t8895 = inttoptr i64 280 to ptr
  %t8896 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t8895, ptr %t8896
  %t8894 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t8847, ptr %t8894
  call void @__free_recursive(ptr %t8730)
  call void @__free_recursive(ptr %t8728)
  call void @__free_recursive(ptr %t8726)
  call void @__free_recursive(ptr %t8623)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.8734:
  unreachable
tco.case.default.8723:
  unreachable
tco.case.arm.100.8897:
  %t8898 = getelementptr ptr, ptr %t5252, i32 1
  %t8899 = load ptr, ptr %t8898
  call void @__inc_ref(ptr %t8899)
  %t8900 = getelementptr ptr, ptr %t5252, i32 3
  %t8901 = load ptr, ptr %t8900
  call void @__inc_ref(ptr %t8901)
  %t8902 = call ptr @__alloc(i64 24, i32 2)
  %t8903 = inttoptr i64 280 to ptr
  %t8904 = getelementptr ptr, ptr %t8902, i32 0
  store ptr %t8903, ptr %t8904
  %t8905 = getelementptr ptr, ptr %t4, i32 1
  %t8906 = load ptr, ptr %t8905
  call void @__free_recursive(ptr %t8906)
  %t8907 = getelementptr ptr, ptr %t4, i32 2
  %t8908 = load ptr, ptr %t8907
  call void @__free_recursive(ptr %t8908)
  %t8911 = inttoptr i64 77 to ptr
  %t8912 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t8911, ptr %t8912
  call void @__inc_ref(ptr %t8899)
  %t8909 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t8899, ptr %t8909
  call void @__inc_ref(ptr %t8901)
  %t8910 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t8901, ptr %t8910
  %t8913 = getelementptr ptr, ptr %t8902, i32 1
  store ptr %t4, ptr %t8913
  %t8914 = call ptr @__alloc(i64 40, i32 4)
  %t8915 = inttoptr i64 232 to ptr
  %t8916 = getelementptr ptr, ptr %t8914, i32 0
  store ptr %t8915, ptr %t8916
  call void @__inc_ref(ptr %t5254)
  %t8917 = getelementptr ptr, ptr %t8914, i32 1
  store ptr %t5254, ptr %t8917
  call void @__inc_ref(ptr %t8901)
  %t8918 = getelementptr ptr, ptr %t8914, i32 2
  store ptr %t8901, ptr %t8918
  call void @__inc_ref(ptr %t8899)
  %t8919 = getelementptr ptr, ptr %t8914, i32 3
  store ptr %t8899, ptr %t8919
  %t8920 = getelementptr ptr, ptr %t5252, i32 2
  %t8921 = load ptr, ptr %t8920
  call void @__inc_ref(ptr %t8921)
  %t8922 = getelementptr ptr, ptr %t8914, i32 4
  store ptr %t8921, ptr %t8922
  %t8923 = getelementptr ptr, ptr %t8902, i32 2
  store ptr %t8914, ptr %t8923
  call void @__free_recursive(ptr %t8901)
  call void @__free_recursive(ptr %t8899)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t8902, ptr %t3
  br label %tco.loop.0
tco.case.arm.101.8924:
  %t8925 = getelementptr ptr, ptr %t5252, i32 1
  %t8926 = load ptr, ptr %t8925
  call void @__inc_ref(ptr %t8926)
  %t8927 = call ptr @__alloc(i64 24, i32 2)
  %t8928 = inttoptr i64 280 to ptr
  %t8929 = getelementptr ptr, ptr %t8927, i32 0
  store ptr %t8928, ptr %t8929
  %t8930 = getelementptr ptr, ptr %t8926, i32 1
  %t8931 = load ptr, ptr %t8930
  call void @__inc_ref(ptr %t8931)
  %t8932 = getelementptr ptr, ptr %t5252, i32 2
  %t8933 = load ptr, ptr %t8932
  call void @__inc_ref(ptr %t8933)
  %t8934 = getelementptr ptr, ptr %t4, i32 1
  %t8935 = load ptr, ptr %t8934
  call void @__free_recursive(ptr %t8935)
  %t8936 = getelementptr ptr, ptr %t4, i32 2
  %t8937 = load ptr, ptr %t8936
  call void @__free_recursive(ptr %t8937)
  %t8940 = inttoptr i64 53 to ptr
  %t8941 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t8940, ptr %t8941
  %t8938 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t8931, ptr %t8938
  %t8939 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t8933, ptr %t8939
  %t8942 = getelementptr ptr, ptr %t8927, i32 1
  store ptr %t4, ptr %t8942
  call void @__inc_ref(ptr %t5254)
  %t8943 = getelementptr ptr, ptr %t8927, i32 2
  store ptr %t5254, ptr %t8943
  call void @__free_recursive(ptr %t8926)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t8927, ptr %t3
  br label %tco.loop.0
tco.case.arm.102.8944:
  %t8945 = getelementptr ptr, ptr %t5252, i32 1
  %t8946 = load ptr, ptr %t8945
  call void @__inc_ref(ptr %t8946)
  %t8947 = getelementptr ptr, ptr %t5252, i32 2
  %t8948 = load ptr, ptr %t8947
  call void @__inc_ref(ptr %t8948)
  %t8949 = getelementptr ptr, ptr %t8948, i32 0
  %t8950 = load ptr, ptr %t8949
  %t8951 = ptrtoint ptr %t8950 to i64
  switch i64 %t8951, label %tco.case.default.8952 [ i64 24, label %tco.case.arm.24.8953 i64 25, label %tco.case.arm.25.8969 i64 26, label %tco.case.arm.26.8993 i64 27, label %tco.case.arm.27.9020 ]
tco.case.arm.24.8953:
  %t8954 = call ptr @__alloc(i64 24, i32 2)
  %t8955 = inttoptr i64 280 to ptr
  %t8956 = getelementptr ptr, ptr %t8954, i32 0
  store ptr %t8955, ptr %t8956
  %t8957 = getelementptr ptr, ptr %t8948, i32 1
  %t8958 = load ptr, ptr %t8957
  call void @__inc_ref(ptr %t8958)
  %t8959 = getelementptr ptr, ptr %t4, i32 1
  %t8960 = load ptr, ptr %t8959
  call void @__free_recursive(ptr %t8960)
  %t8961 = getelementptr ptr, ptr %t4, i32 2
  %t8962 = load ptr, ptr %t8961
  call void @__free_recursive(ptr %t8962)
  %t8965 = inttoptr i64 101 to ptr
  %t8966 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t8965, ptr %t8966
  call void @__inc_ref(ptr %t8946)
  %t8963 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t8946, ptr %t8963
  %t8964 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t8958, ptr %t8964
  %t8967 = getelementptr ptr, ptr %t8954, i32 1
  store ptr %t4, ptr %t8967
  call void @__inc_ref(ptr %t5254)
  %t8968 = getelementptr ptr, ptr %t8954, i32 2
  store ptr %t5254, ptr %t8968
  call void @__free_recursive(ptr %t8948)
  call void @__free_recursive(ptr %t8946)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t8954, ptr %t3
  br label %tco.loop.0
tco.case.arm.25.8969:
  %t8970 = call ptr @__alloc(i64 24, i32 2)
  %t8971 = inttoptr i64 280 to ptr
  %t8972 = getelementptr ptr, ptr %t8970, i32 0
  store ptr %t8971, ptr %t8972
  %t8973 = getelementptr ptr, ptr %t8948, i32 1
  %t8974 = load ptr, ptr %t8973
  call void @__inc_ref(ptr %t8974)
  %t8975 = getelementptr ptr, ptr %t4, i32 1
  %t8976 = load ptr, ptr %t8975
  call void @__free_recursive(ptr %t8976)
  %t8977 = getelementptr ptr, ptr %t4, i32 2
  %t8978 = load ptr, ptr %t8977
  call void @__free_recursive(ptr %t8978)
  %t8981 = inttoptr i64 101 to ptr
  %t8982 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t8981, ptr %t8982
  call void @__inc_ref(ptr %t8946)
  %t8979 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t8946, ptr %t8979
  %t8980 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t8974, ptr %t8980
  %t8983 = getelementptr ptr, ptr %t8970, i32 1
  store ptr %t4, ptr %t8983
  %t8984 = call ptr @__alloc(i64 32, i32 3)
  %t8985 = inttoptr i64 236 to ptr
  %t8986 = getelementptr ptr, ptr %t8984, i32 0
  store ptr %t8985, ptr %t8986
  call void @__inc_ref(ptr %t5254)
  %t8987 = getelementptr ptr, ptr %t8984, i32 1
  store ptr %t5254, ptr %t8987
  %t8988 = getelementptr ptr, ptr %t8948, i32 2
  %t8989 = load ptr, ptr %t8988
  call void @__inc_ref(ptr %t8989)
  %t8990 = getelementptr ptr, ptr %t8984, i32 2
  store ptr %t8989, ptr %t8990
  call void @__inc_ref(ptr %t8946)
  %t8991 = getelementptr ptr, ptr %t8984, i32 3
  store ptr %t8946, ptr %t8991
  %t8992 = getelementptr ptr, ptr %t8970, i32 2
  store ptr %t8984, ptr %t8992
  call void @__free_recursive(ptr %t8948)
  call void @__free_recursive(ptr %t8946)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t8970, ptr %t3
  br label %tco.loop.0
tco.case.arm.26.8993:
  %t8994 = call ptr @__alloc(i64 24, i32 2)
  %t8995 = inttoptr i64 280 to ptr
  %t8996 = getelementptr ptr, ptr %t8994, i32 0
  store ptr %t8995, ptr %t8996
  %t8997 = getelementptr ptr, ptr %t8948, i32 1
  %t8998 = load ptr, ptr %t8997
  call void @__inc_ref(ptr %t8998)
  %t8999 = getelementptr ptr, ptr %t4, i32 1
  %t9000 = load ptr, ptr %t8999
  call void @__free_recursive(ptr %t9000)
  %t9001 = getelementptr ptr, ptr %t4, i32 2
  %t9002 = load ptr, ptr %t9001
  call void @__free_recursive(ptr %t9002)
  %t9005 = inttoptr i64 101 to ptr
  %t9006 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t9005, ptr %t9006
  call void @__inc_ref(ptr %t8946)
  %t9003 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t8946, ptr %t9003
  %t9004 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t8998, ptr %t9004
  %t9007 = getelementptr ptr, ptr %t8994, i32 1
  store ptr %t4, ptr %t9007
  %t9008 = call ptr @__alloc(i64 40, i32 4)
  %t9009 = inttoptr i64 238 to ptr
  %t9010 = getelementptr ptr, ptr %t9008, i32 0
  store ptr %t9009, ptr %t9010
  call void @__inc_ref(ptr %t5254)
  %t9011 = getelementptr ptr, ptr %t9008, i32 1
  store ptr %t5254, ptr %t9011
  %t9012 = getelementptr ptr, ptr %t8948, i32 2
  %t9013 = load ptr, ptr %t9012
  call void @__inc_ref(ptr %t9013)
  %t9014 = getelementptr ptr, ptr %t9008, i32 2
  store ptr %t9013, ptr %t9014
  %t9015 = getelementptr ptr, ptr %t8948, i32 3
  %t9016 = load ptr, ptr %t9015
  call void @__inc_ref(ptr %t9016)
  %t9017 = getelementptr ptr, ptr %t9008, i32 3
  store ptr %t9016, ptr %t9017
  call void @__inc_ref(ptr %t8946)
  %t9018 = getelementptr ptr, ptr %t9008, i32 4
  store ptr %t8946, ptr %t9018
  %t9019 = getelementptr ptr, ptr %t8994, i32 2
  store ptr %t9008, ptr %t9019
  call void @__free_recursive(ptr %t8948)
  call void @__free_recursive(ptr %t8946)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t8994, ptr %t3
  br label %tco.loop.0
tco.case.arm.27.9020:
  %t9021 = call ptr @__alloc(i64 24, i32 2)
  %t9022 = inttoptr i64 280 to ptr
  %t9023 = getelementptr ptr, ptr %t9021, i32 0
  store ptr %t9022, ptr %t9023
  %t9024 = getelementptr ptr, ptr %t8948, i32 1
  %t9025 = load ptr, ptr %t9024
  call void @__inc_ref(ptr %t9025)
  %t9026 = getelementptr ptr, ptr %t4, i32 1
  %t9027 = load ptr, ptr %t9026
  call void @__free_recursive(ptr %t9027)
  %t9028 = getelementptr ptr, ptr %t4, i32 2
  %t9029 = load ptr, ptr %t9028
  call void @__free_recursive(ptr %t9029)
  %t9032 = inttoptr i64 101 to ptr
  %t9033 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t9032, ptr %t9033
  call void @__inc_ref(ptr %t8946)
  %t9030 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t8946, ptr %t9030
  %t9031 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t9025, ptr %t9031
  %t9034 = getelementptr ptr, ptr %t9021, i32 1
  store ptr %t4, ptr %t9034
  %t9035 = call ptr @__alloc(i64 48, i32 5)
  %t9036 = inttoptr i64 242 to ptr
  %t9037 = getelementptr ptr, ptr %t9035, i32 0
  store ptr %t9036, ptr %t9037
  call void @__inc_ref(ptr %t5254)
  %t9038 = getelementptr ptr, ptr %t9035, i32 1
  store ptr %t5254, ptr %t9038
  %t9039 = getelementptr ptr, ptr %t8948, i32 2
  %t9040 = load ptr, ptr %t9039
  call void @__inc_ref(ptr %t9040)
  %t9041 = getelementptr ptr, ptr %t9035, i32 2
  store ptr %t9040, ptr %t9041
  %t9042 = getelementptr ptr, ptr %t8948, i32 3
  %t9043 = load ptr, ptr %t9042
  call void @__inc_ref(ptr %t9043)
  %t9044 = getelementptr ptr, ptr %t9035, i32 3
  store ptr %t9043, ptr %t9044
  %t9045 = getelementptr ptr, ptr %t8948, i32 4
  %t9046 = load ptr, ptr %t9045
  call void @__inc_ref(ptr %t9046)
  %t9047 = getelementptr ptr, ptr %t9035, i32 4
  store ptr %t9046, ptr %t9047
  call void @__inc_ref(ptr %t8946)
  %t9048 = getelementptr ptr, ptr %t9035, i32 5
  store ptr %t8946, ptr %t9048
  %t9049 = getelementptr ptr, ptr %t9021, i32 2
  store ptr %t9035, ptr %t9049
  call void @__free_recursive(ptr %t8948)
  call void @__free_recursive(ptr %t8946)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t9021, ptr %t3
  br label %tco.loop.0
tco.case.default.8952:
  unreachable
tco.case.arm.103.9050:
  %t9051 = getelementptr ptr, ptr %t5252, i32 1
  %t9052 = load ptr, ptr %t9051
  call void @__inc_ref(ptr %t9052)
  %t9053 = getelementptr ptr, ptr %t5252, i32 2
  %t9054 = load ptr, ptr %t9053
  call void @__inc_ref(ptr %t9054)
  %t9055 = getelementptr ptr, ptr %t9054, i32 0
  %t9056 = load ptr, ptr %t9055
  %t9057 = ptrtoint ptr %t9056 to i64
  switch i64 %t9057, label %tco.case.default.9058 [ i64 30, label %tco.case.arm.30.9059 i64 31, label %tco.case.arm.31.9070 i64 32, label %tco.case.arm.32.9086 ]
tco.case.arm.30.9059:
  %t9060 = getelementptr ptr, ptr %t9052, i32 3
  %t9061 = load ptr, ptr %t9060
  call void @__inc_ref(ptr %t9061)
  %t9062 = getelementptr ptr, ptr %t4, i32 1
  %t9063 = load ptr, ptr %t9062
  call void @__free_recursive(ptr %t9063)
  %t9064 = getelementptr ptr, ptr %t4, i32 2
  %t9065 = load ptr, ptr %t9064
  call void @__free_recursive(ptr %t9065)
  %t9068 = inttoptr i64 279 to ptr
  %t9069 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t9068, ptr %t9069
  call void @__inc_ref(ptr %t5254)
  %t9066 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t9066
  %t9067 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t9061, ptr %t9067
  call void @__free_recursive(ptr %t9054)
  call void @__free_recursive(ptr %t9052)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.31.9070:
  %t9071 = call ptr @__alloc(i64 24, i32 2)
  %t9072 = inttoptr i64 280 to ptr
  %t9073 = getelementptr ptr, ptr %t9071, i32 0
  store ptr %t9072, ptr %t9073
  %t9074 = getelementptr ptr, ptr %t9054, i32 1
  %t9075 = load ptr, ptr %t9074
  call void @__inc_ref(ptr %t9075)
  %t9076 = getelementptr ptr, ptr %t4, i32 1
  %t9077 = load ptr, ptr %t9076
  call void @__free_recursive(ptr %t9077)
  %t9078 = getelementptr ptr, ptr %t4, i32 2
  %t9079 = load ptr, ptr %t9078
  call void @__free_recursive(ptr %t9079)
  %t9082 = inttoptr i64 101 to ptr
  %t9083 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t9082, ptr %t9083
  call void @__inc_ref(ptr %t9052)
  %t9080 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t9052, ptr %t9080
  %t9081 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t9075, ptr %t9081
  %t9084 = getelementptr ptr, ptr %t9071, i32 1
  store ptr %t4, ptr %t9084
  call void @__inc_ref(ptr %t5254)
  %t9085 = getelementptr ptr, ptr %t9071, i32 2
  store ptr %t5254, ptr %t9085
  call void @__free_recursive(ptr %t9054)
  call void @__free_recursive(ptr %t9052)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t9071, ptr %t3
  br label %tco.loop.0
tco.case.arm.32.9086:
  %t9087 = getelementptr ptr, ptr %t9054, i32 1
  %t9088 = load ptr, ptr %t9087
  call void @__inc_ref(ptr %t9088)
  %t9089 = getelementptr ptr, ptr %t4, i32 1
  %t9090 = load ptr, ptr %t9089
  call void @__free_recursive(ptr %t9090)
  %t9091 = getelementptr ptr, ptr %t4, i32 2
  %t9092 = load ptr, ptr %t9091
  call void @__free_recursive(ptr %t9092)
  %t9095 = inttoptr i64 279 to ptr
  %t9096 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t9095, ptr %t9096
  call void @__inc_ref(ptr %t5254)
  %t9093 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t9093
  %t9094 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t9088, ptr %t9094
  call void @__free_recursive(ptr %t9054)
  call void @__free_recursive(ptr %t9052)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.9058:
  unreachable
tco.case.arm.104.9097:
  %t9098 = getelementptr ptr, ptr %t5252, i32 1
  %t9099 = load ptr, ptr %t9098
  call void @__inc_ref(ptr %t9099)
  %t9100 = getelementptr ptr, ptr %t5252, i32 2
  %t9101 = load ptr, ptr %t9100
  call void @__inc_ref(ptr %t9101)
  %t9102 = call ptr @__alloc(i64 24, i32 2)
  %t9103 = inttoptr i64 280 to ptr
  %t9104 = getelementptr ptr, ptr %t9102, i32 0
  store ptr %t9103, ptr %t9104
  %t9105 = getelementptr ptr, ptr %t4, i32 1
  %t9106 = load ptr, ptr %t9105
  call void @__free_recursive(ptr %t9106)
  %t9107 = getelementptr ptr, ptr %t4, i32 2
  %t9108 = load ptr, ptr %t9107
  call void @__free_recursive(ptr %t9108)
  %t9111 = inttoptr i64 101 to ptr
  %t9112 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t9111, ptr %t9112
  call void @__inc_ref(ptr %t9099)
  %t9109 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t9099, ptr %t9109
  call void @__inc_ref(ptr %t9101)
  %t9110 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t9101, ptr %t9110
  %t9113 = getelementptr ptr, ptr %t9102, i32 1
  store ptr %t4, ptr %t9113
  %t9114 = call ptr @__alloc(i64 40, i32 4)
  %t9115 = inttoptr i64 248 to ptr
  %t9116 = getelementptr ptr, ptr %t9114, i32 0
  store ptr %t9115, ptr %t9116
  call void @__inc_ref(ptr %t5254)
  %t9117 = getelementptr ptr, ptr %t9114, i32 1
  store ptr %t5254, ptr %t9117
  call void @__inc_ref(ptr %t9099)
  %t9118 = getelementptr ptr, ptr %t9114, i32 2
  store ptr %t9099, ptr %t9118
  call void @__inc_ref(ptr %t9101)
  %t9119 = getelementptr ptr, ptr %t9114, i32 3
  store ptr %t9101, ptr %t9119
  %t9120 = getelementptr ptr, ptr %t5252, i32 3
  %t9121 = load ptr, ptr %t9120
  call void @__inc_ref(ptr %t9121)
  %t9122 = getelementptr ptr, ptr %t9114, i32 4
  store ptr %t9121, ptr %t9122
  %t9123 = getelementptr ptr, ptr %t9102, i32 2
  store ptr %t9114, ptr %t9123
  call void @__free_recursive(ptr %t9101)
  call void @__free_recursive(ptr %t9099)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t9102, ptr %t3
  br label %tco.loop.0
tco.case.arm.105.9124:
  %t9125 = getelementptr ptr, ptr %t5252, i32 1
  %t9126 = load ptr, ptr %t9125
  call void @__inc_ref(ptr %t9126)
  %t9127 = getelementptr ptr, ptr %t5252, i32 2
  %t9128 = load ptr, ptr %t9127
  call void @__inc_ref(ptr %t9128)
  %t9129 = call ptr @__alloc(i64 24, i32 2)
  %t9130 = inttoptr i64 280 to ptr
  %t9131 = getelementptr ptr, ptr %t9129, i32 0
  store ptr %t9130, ptr %t9131
  %t9132 = getelementptr ptr, ptr %t4, i32 1
  %t9133 = load ptr, ptr %t9132
  call void @__free_recursive(ptr %t9133)
  %t9134 = getelementptr ptr, ptr %t4, i32 2
  %t9135 = load ptr, ptr %t9134
  call void @__free_recursive(ptr %t9135)
  %t9138 = inttoptr i64 101 to ptr
  %t9139 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t9138, ptr %t9139
  call void @__inc_ref(ptr %t9126)
  %t9136 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t9126, ptr %t9136
  call void @__inc_ref(ptr %t9128)
  %t9137 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t9128, ptr %t9137
  %t9140 = getelementptr ptr, ptr %t9129, i32 1
  store ptr %t4, ptr %t9140
  %t9141 = call ptr @__alloc(i64 48, i32 5)
  %t9142 = inttoptr i64 251 to ptr
  %t9143 = getelementptr ptr, ptr %t9141, i32 0
  store ptr %t9142, ptr %t9143
  call void @__inc_ref(ptr %t5254)
  %t9144 = getelementptr ptr, ptr %t9141, i32 1
  store ptr %t5254, ptr %t9144
  call void @__inc_ref(ptr %t9126)
  %t9145 = getelementptr ptr, ptr %t9141, i32 2
  store ptr %t9126, ptr %t9145
  call void @__inc_ref(ptr %t9128)
  %t9146 = getelementptr ptr, ptr %t9141, i32 3
  store ptr %t9128, ptr %t9146
  %t9147 = getelementptr ptr, ptr %t5252, i32 3
  %t9148 = load ptr, ptr %t9147
  call void @__inc_ref(ptr %t9148)
  %t9149 = getelementptr ptr, ptr %t9141, i32 4
  store ptr %t9148, ptr %t9149
  %t9150 = getelementptr ptr, ptr %t5252, i32 4
  %t9151 = load ptr, ptr %t9150
  call void @__inc_ref(ptr %t9151)
  %t9152 = getelementptr ptr, ptr %t9141, i32 5
  store ptr %t9151, ptr %t9152
  %t9153 = getelementptr ptr, ptr %t9129, i32 2
  store ptr %t9141, ptr %t9153
  call void @__free_recursive(ptr %t9128)
  call void @__free_recursive(ptr %t9126)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t9129, ptr %t3
  br label %tco.loop.0
tco.case.arm.106.9154:
  %t9155 = getelementptr ptr, ptr %t5252, i32 1
  %t9156 = load ptr, ptr %t9155
  call void @__inc_ref(ptr %t9156)
  %t9157 = getelementptr ptr, ptr %t5252, i32 2
  %t9158 = load ptr, ptr %t9157
  call void @__inc_ref(ptr %t9158)
  %t9159 = getelementptr ptr, ptr %t5252, i32 4
  %t9160 = load ptr, ptr %t9159
  call void @__inc_ref(ptr %t9160)
  %t9161 = getelementptr ptr, ptr %t5252, i32 3
  %t9162 = load ptr, ptr %t9161
  call void @__inc_ref(ptr %t9162)
  %t9163 = getelementptr ptr, ptr %t9162, i32 0
  %t9164 = load ptr, ptr %t9163
  %t9165 = ptrtoint ptr %t9164 to i64
  switch i64 %t9165, label %tco.case.default.9166 [ i64 13, label %tco.case.arm.13.9167 i64 14, label %tco.case.arm.14.9186 ]
tco.case.arm.13.9167:
  call void @__free_recursive(ptr %t9162)
  %t9168 = call ptr @__alloc(i64 32, i32 3)
  %t9169 = inttoptr i64 104 to ptr
  %t9170 = getelementptr ptr, ptr %t9168, i32 0
  store ptr %t9169, ptr %t9170
  call void @__inc_ref(ptr %t9156)
  %t9171 = getelementptr ptr, ptr %t9168, i32 1
  store ptr %t9156, ptr %t9171
  call void @__inc_ref(ptr %t9158)
  %t9172 = getelementptr ptr, ptr %t9168, i32 2
  store ptr %t9158, ptr %t9172
  call void @__inc_ref(ptr %t9160)
  %t9173 = getelementptr ptr, ptr %t9168, i32 3
  store ptr %t9160, ptr %t9173
  %t9174 = call ptr @__alloc(i64 16, i32 1)
  %t9175 = inttoptr i64 256 to ptr
  %t9176 = getelementptr ptr, ptr %t9174, i32 0
  store ptr %t9175, ptr %t9176
  call void @__inc_ref(ptr %t5254)
  %t9177 = getelementptr ptr, ptr %t9174, i32 1
  store ptr %t5254, ptr %t9177
  %t9178 = getelementptr ptr, ptr %t4, i32 1
  %t9179 = load ptr, ptr %t9178
  call void @__free_recursive(ptr %t9179)
  %t9180 = getelementptr ptr, ptr %t4, i32 2
  %t9181 = load ptr, ptr %t9180
  call void @__free_recursive(ptr %t9181)
  %t9184 = inttoptr i64 280 to ptr
  %t9185 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t9184, ptr %t9185
  %t9182 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t9168, ptr %t9182
  %t9183 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t9174, ptr %t9183
  call void @__free_recursive(ptr %t9160)
  call void @__free_recursive(ptr %t9158)
  call void @__free_recursive(ptr %t9156)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.14.9186:
  %t9187 = getelementptr ptr, ptr %t9162, i32 1
  %t9188 = load ptr, ptr %t9187
  call void @__inc_ref(ptr %t9188)
  %t9189 = getelementptr ptr, ptr %t9162, i32 2
  %t9190 = load ptr, ptr %t9189
  call void @__inc_ref(ptr %t9190)
  call void @__free_recursive(ptr %t9162)
  %t9191 = getelementptr ptr, ptr %t9190, i32 0
  %t9192 = load ptr, ptr %t9191
  %t9193 = ptrtoint ptr %t9192 to i64
  switch i64 %t9193, label %tco.case.default.9194 [ i64 13, label %tco.case.arm.13.9195 i64 14, label %tco.case.arm.14.9215 ]
tco.case.arm.13.9195:
  %t9196 = call ptr @__alloc(i64 40, i32 4)
  %t9197 = inttoptr i64 105 to ptr
  %t9198 = getelementptr ptr, ptr %t9196, i32 0
  store ptr %t9197, ptr %t9198
  call void @__inc_ref(ptr %t9156)
  %t9199 = getelementptr ptr, ptr %t9196, i32 1
  store ptr %t9156, ptr %t9199
  call void @__inc_ref(ptr %t9158)
  %t9200 = getelementptr ptr, ptr %t9196, i32 2
  store ptr %t9158, ptr %t9200
  call void @__inc_ref(ptr %t9188)
  %t9201 = getelementptr ptr, ptr %t9196, i32 3
  store ptr %t9188, ptr %t9201
  call void @__inc_ref(ptr %t9160)
  %t9202 = getelementptr ptr, ptr %t9196, i32 4
  store ptr %t9160, ptr %t9202
  %t9203 = call ptr @__alloc(i64 16, i32 1)
  %t9204 = inttoptr i64 257 to ptr
  %t9205 = getelementptr ptr, ptr %t9203, i32 0
  store ptr %t9204, ptr %t9205
  call void @__inc_ref(ptr %t5254)
  %t9206 = getelementptr ptr, ptr %t9203, i32 1
  store ptr %t5254, ptr %t9206
  %t9207 = getelementptr ptr, ptr %t4, i32 1
  %t9208 = load ptr, ptr %t9207
  call void @__free_recursive(ptr %t9208)
  %t9209 = getelementptr ptr, ptr %t4, i32 2
  %t9210 = load ptr, ptr %t9209
  call void @__free_recursive(ptr %t9210)
  %t9213 = inttoptr i64 280 to ptr
  %t9214 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t9213, ptr %t9214
  %t9211 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t9196, ptr %t9211
  %t9212 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t9203, ptr %t9212
  call void @__free_recursive(ptr %t9190)
  call void @__free_recursive(ptr %t9188)
  call void @__free_recursive(ptr %t9160)
  call void @__free_recursive(ptr %t9158)
  call void @__free_recursive(ptr %t9156)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.14.9215:
  %t9216 = getelementptr ptr, ptr %t9190, i32 1
  %t9217 = load ptr, ptr %t9216
  call void @__inc_ref(ptr %t9217)
  %t9218 = getelementptr ptr, ptr %t9190, i32 2
  %t9219 = load ptr, ptr %t9218
  call void @__inc_ref(ptr %t9219)
  %t9220 = getelementptr ptr, ptr %t9219, i32 0
  %t9221 = load ptr, ptr %t9220
  %t9222 = ptrtoint ptr %t9221 to i64
  switch i64 %t9222, label %tco.case.default.9223 [ i64 13, label %tco.case.arm.13.9224 i64 14, label %tco.case.arm.14.9260 ]
tco.case.arm.13.9224:
  %t9225 = call ptr @__alloc(i64 32, i32 3)
  %t9226 = inttoptr i64 104 to ptr
  %t9227 = getelementptr ptr, ptr %t9225, i32 0
  store ptr %t9226, ptr %t9227
  call void @__inc_ref(ptr %t9156)
  %t9228 = getelementptr ptr, ptr %t9225, i32 1
  store ptr %t9156, ptr %t9228
  call void @__inc_ref(ptr %t9158)
  %t9229 = getelementptr ptr, ptr %t9225, i32 2
  store ptr %t9158, ptr %t9229
  call void @__inc_ref(ptr %t9188)
  %t9230 = getelementptr ptr, ptr %t9225, i32 3
  store ptr %t9188, ptr %t9230
  %t9231 = call ptr @__alloc(i64 40, i32 4)
  %t9232 = inttoptr i64 258 to ptr
  %t9233 = getelementptr ptr, ptr %t9231, i32 0
  store ptr %t9232, ptr %t9233
  call void @__inc_ref(ptr %t5254)
  %t9234 = getelementptr ptr, ptr %t9231, i32 1
  store ptr %t5254, ptr %t9234
  call void @__inc_ref(ptr %t9217)
  %t9235 = getelementptr ptr, ptr %t9231, i32 2
  store ptr %t9217, ptr %t9235
  call void @__inc_ref(ptr %t9160)
  %t9236 = getelementptr ptr, ptr %t9231, i32 3
  store ptr %t9160, ptr %t9236
  call void @__inc_ref(ptr %t9156)
  %t9237 = getelementptr ptr, ptr %t9231, i32 4
  store ptr %t9156, ptr %t9237
  %t9246 = getelementptr i8, ptr %t9190, i64 -8
  %t9247 = load i32, ptr %t9246
  %t9248 = icmp eq i32 %t9247, 1
  br i1 %t9248, label %reuse.in_place.9249, label %reuse.copy.9250
reuse.in_place.9249:
  %t9238 = getelementptr ptr, ptr %t9190, i32 1
  %t9239 = load ptr, ptr %t9238
  call void @__free_recursive(ptr %t9239)
  %t9240 = getelementptr ptr, ptr %t9190, i32 2
  %t9241 = load ptr, ptr %t9240
  call void @__free_recursive(ptr %t9241)
  %t9244 = inttoptr i64 280 to ptr
  %t9245 = getelementptr ptr, ptr %t9190, i32 0
  store ptr %t9244, ptr %t9245
  %t9242 = getelementptr ptr, ptr %t9190, i32 1
  store ptr %t9225, ptr %t9242
  %t9243 = getelementptr ptr, ptr %t9190, i32 2
  store ptr %t9231, ptr %t9243
  br label %reuse.in_place.end.9252
reuse.in_place.end.9252:
  br label %reuse.join.9251
reuse.copy.9250:
  %t9254 = call ptr @__alloc(i64 24, i32 2)
  %t9255 = inttoptr i64 280 to ptr
  %t9256 = getelementptr ptr, ptr %t9254, i32 0
  store ptr %t9255, ptr %t9256
  %t9257 = getelementptr ptr, ptr %t9254, i32 1
  store ptr %t9225, ptr %t9257
  %t9258 = getelementptr ptr, ptr %t9254, i32 2
  store ptr %t9231, ptr %t9258
  call void @__free_recursive(ptr %t9190)
  br label %reuse.copy.end.9253
reuse.copy.end.9253:
  br label %reuse.join.9251
reuse.join.9251:
  %t9259 = phi ptr [ %t9190, %reuse.in_place.end.9252 ], [ %t9254, %reuse.copy.end.9253 ]
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t9219)
  call void @__free_recursive(ptr %t9217)
  call void @__free_recursive(ptr %t9188)
  call void @__free_recursive(ptr %t9160)
  call void @__free_recursive(ptr %t9158)
  call void @__free_recursive(ptr %t9156)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t9259, ptr %t3
  br label %tco.loop.0
tco.case.arm.14.9260:
  %t9261 = getelementptr ptr, ptr %t9219, i32 1
  %t9262 = load ptr, ptr %t9261
  call void @__inc_ref(ptr %t9262)
  %t9263 = getelementptr ptr, ptr %t9219, i32 2
  %t9264 = load ptr, ptr %t9263
  call void @__inc_ref(ptr %t9264)
  %t9265 = call ptr @__alloc(i64 40, i32 4)
  %t9266 = inttoptr i64 105 to ptr
  %t9267 = getelementptr ptr, ptr %t9265, i32 0
  store ptr %t9266, ptr %t9267
  call void @__inc_ref(ptr %t9156)
  %t9268 = getelementptr ptr, ptr %t9265, i32 1
  store ptr %t9156, ptr %t9268
  call void @__inc_ref(ptr %t9158)
  %t9269 = getelementptr ptr, ptr %t9265, i32 2
  store ptr %t9158, ptr %t9269
  call void @__inc_ref(ptr %t9188)
  %t9270 = getelementptr ptr, ptr %t9265, i32 3
  store ptr %t9188, ptr %t9270
  call void @__inc_ref(ptr %t9217)
  %t9271 = getelementptr ptr, ptr %t9265, i32 4
  store ptr %t9217, ptr %t9271
  %t9272 = call ptr @__alloc(i64 48, i32 5)
  %t9273 = inttoptr i64 260 to ptr
  %t9274 = getelementptr ptr, ptr %t9272, i32 0
  store ptr %t9273, ptr %t9274
  call void @__inc_ref(ptr %t5254)
  %t9275 = getelementptr ptr, ptr %t9272, i32 1
  store ptr %t5254, ptr %t9275
  call void @__inc_ref(ptr %t9262)
  %t9276 = getelementptr ptr, ptr %t9272, i32 2
  store ptr %t9262, ptr %t9276
  call void @__inc_ref(ptr %t9160)
  %t9277 = getelementptr ptr, ptr %t9272, i32 3
  store ptr %t9160, ptr %t9277
  call void @__inc_ref(ptr %t9156)
  %t9278 = getelementptr ptr, ptr %t9272, i32 4
  store ptr %t9156, ptr %t9278
  call void @__inc_ref(ptr %t9264)
  %t9279 = getelementptr ptr, ptr %t9272, i32 5
  store ptr %t9264, ptr %t9279
  %t9288 = getelementptr i8, ptr %t9219, i64 -8
  %t9289 = load i32, ptr %t9288
  %t9290 = icmp eq i32 %t9289, 1
  br i1 %t9290, label %reuse.in_place.9291, label %reuse.copy.9292
reuse.in_place.9291:
  %t9280 = getelementptr ptr, ptr %t9219, i32 1
  %t9281 = load ptr, ptr %t9280
  call void @__free_recursive(ptr %t9281)
  %t9282 = getelementptr ptr, ptr %t9219, i32 2
  %t9283 = load ptr, ptr %t9282
  call void @__free_recursive(ptr %t9283)
  %t9286 = inttoptr i64 280 to ptr
  %t9287 = getelementptr ptr, ptr %t9219, i32 0
  store ptr %t9286, ptr %t9287
  %t9284 = getelementptr ptr, ptr %t9219, i32 1
  store ptr %t9265, ptr %t9284
  %t9285 = getelementptr ptr, ptr %t9219, i32 2
  store ptr %t9272, ptr %t9285
  br label %reuse.in_place.end.9294
reuse.in_place.end.9294:
  br label %reuse.join.9293
reuse.copy.9292:
  %t9296 = call ptr @__alloc(i64 24, i32 2)
  %t9297 = inttoptr i64 280 to ptr
  %t9298 = getelementptr ptr, ptr %t9296, i32 0
  store ptr %t9297, ptr %t9298
  %t9299 = getelementptr ptr, ptr %t9296, i32 1
  store ptr %t9265, ptr %t9299
  %t9300 = getelementptr ptr, ptr %t9296, i32 2
  store ptr %t9272, ptr %t9300
  call void @__free_recursive(ptr %t9219)
  br label %reuse.copy.end.9295
reuse.copy.end.9295:
  br label %reuse.join.9293
reuse.join.9293:
  %t9301 = phi ptr [ %t9219, %reuse.in_place.end.9294 ], [ %t9296, %reuse.copy.end.9295 ]
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t9264)
  call void @__free_recursive(ptr %t9262)
  call void @__free_recursive(ptr %t9190)
  call void @__free_recursive(ptr %t9217)
  call void @__free_recursive(ptr %t9188)
  call void @__free_recursive(ptr %t9160)
  call void @__free_recursive(ptr %t9158)
  call void @__free_recursive(ptr %t9156)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t9301, ptr %t3
  br label %tco.loop.0
tco.case.default.9223:
  unreachable
tco.case.default.9194:
  unreachable
tco.case.default.9166:
  unreachable
tco.case.arm.107.9302:
  %t9303 = getelementptr ptr, ptr %t5252, i32 2
  %t9304 = load ptr, ptr %t9303
  call void @__inc_ref(ptr %t9304)
  %t9305 = getelementptr ptr, ptr %t9304, i32 0
  %t9306 = load ptr, ptr %t9305
  %t9307 = ptrtoint ptr %t9306 to i64
  switch i64 %t9307, label %tco.case.default.9308 [ i64 11, label %tco.case.arm.11.9309 i64 12, label %tco.case.arm.12.9321 ]
tco.case.arm.11.9309:
  %t9310 = call ptr @__alloc(i64 8, i32 0)
  %t9311 = inttoptr i64 30 to ptr
  %t9312 = getelementptr ptr, ptr %t9310, i32 0
  store ptr %t9311, ptr %t9312
  %t9313 = getelementptr ptr, ptr %t4, i32 1
  %t9314 = load ptr, ptr %t9313
  call void @__free_recursive(ptr %t9314)
  %t9315 = getelementptr ptr, ptr %t4, i32 2
  %t9316 = load ptr, ptr %t9315
  call void @__free_recursive(ptr %t9316)
  %t9319 = inttoptr i64 279 to ptr
  %t9320 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t9319, ptr %t9320
  call void @__inc_ref(ptr %t5254)
  %t9317 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t9317
  %t9318 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t9310, ptr %t9318
  call void @__free_recursive(ptr %t9304)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.12.9321:
  %t9322 = call ptr @__alloc(i64 24, i32 2)
  %t9323 = inttoptr i64 280 to ptr
  %t9324 = getelementptr ptr, ptr %t9322, i32 0
  store ptr %t9323, ptr %t9324
  %t9325 = getelementptr ptr, ptr %t5252, i32 1
  %t9326 = load ptr, ptr %t9325
  call void @__inc_ref(ptr %t9326)
  %t9327 = getelementptr ptr, ptr %t9304, i32 1
  %t9328 = load ptr, ptr %t9327
  call void @__inc_ref(ptr %t9328)
  %t9329 = getelementptr ptr, ptr %t4, i32 1
  %t9330 = load ptr, ptr %t9329
  call void @__free_recursive(ptr %t9330)
  %t9331 = getelementptr ptr, ptr %t4, i32 2
  %t9332 = load ptr, ptr %t9331
  call void @__free_recursive(ptr %t9332)
  %t9335 = inttoptr i64 96 to ptr
  %t9336 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t9335, ptr %t9336
  %t9333 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t9326, ptr %t9333
  %t9334 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t9328, ptr %t9334
  %t9337 = getelementptr ptr, ptr %t9322, i32 1
  store ptr %t4, ptr %t9337
  call void @__inc_ref(ptr %t5254)
  %t9338 = getelementptr ptr, ptr %t9322, i32 2
  store ptr %t5254, ptr %t9338
  call void @__free_recursive(ptr %t9304)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t9322, ptr %t3
  br label %tco.loop.0
tco.case.default.9308:
  unreachable
tco.case.arm.108.9339:
  %t9340 = getelementptr ptr, ptr %t5252, i32 1
  %t9341 = load ptr, ptr %t9340
  call void @__inc_ref(ptr %t9341)
  %t9342 = getelementptr ptr, ptr %t5252, i32 2
  %t9343 = load ptr, ptr %t9342
  call void @__inc_ref(ptr %t9343)
  call void @__inc_ref(ptr %t9341)
  %t9344 = call ptr @__splitOnFirst(ptr getelementptr inbounds (i8, ptr @.str.10, i64 12), ptr %t9341)
  %t9345 = getelementptr ptr, ptr %t9344, i32 0
  %t9346 = load ptr, ptr %t9345
  %t9347 = ptrtoint ptr %t9346 to i64
  switch i64 %t9347, label %tco.case.default.9348 [ i64 11, label %tco.case.arm.11.9349 i64 12, label %tco.case.arm.12.9422 ]
tco.case.arm.11.9349:
  call void @__free_recursive(ptr %t9344)
  call void @__inc_ref(ptr %t9341)
  %t9350 = call ptr @__eqString(ptr %t9341, ptr getelementptr inbounds (i8, ptr @.str.11, i64 12))
  %t9351 = getelementptr ptr, ptr %t9350, i32 0
  %t9352 = load ptr, ptr %t9351
  %t9353 = ptrtoint ptr %t9352 to i64
  switch i64 %t9353, label %tco.case.default.9354 [ i64 1, label %tco.case.arm.1.9355 i64 2, label %tco.case.arm.2.9379 ]
tco.case.arm.1.9355:
  call void @__free_recursive(ptr %t9350)
  %t9356 = call ptr @__alloc(i64 40, i32 4)
  %t9357 = inttoptr i64 85 to ptr
  %t9358 = getelementptr ptr, ptr %t9356, i32 0
  store ptr %t9357, ptr %t9358
  %t9359 = call ptr @v_lineMeasure()
  %t9360 = getelementptr ptr, ptr %t9356, i32 1
  store ptr %t9359, ptr %t9360
  call void @__inc_ref(ptr %t9343)
  %t9361 = getelementptr ptr, ptr %t9356, i32 2
  store ptr %t9343, ptr %t9361
  %t9362 = call ptr @__alloc(i64 8, i32 0)
  %t9363 = inttoptr i64 13 to ptr
  %t9364 = getelementptr ptr, ptr %t9362, i32 0
  store ptr %t9363, ptr %t9364
  %t9365 = getelementptr ptr, ptr %t9356, i32 3
  store ptr %t9362, ptr %t9365
  call void @__inc_ref(ptr %t9343)
  %t9366 = getelementptr ptr, ptr %t9356, i32 4
  store ptr %t9343, ptr %t9366
  %t9367 = call ptr @__alloc(i64 16, i32 1)
  %t9368 = inttoptr i64 262 to ptr
  %t9369 = getelementptr ptr, ptr %t9367, i32 0
  store ptr %t9368, ptr %t9369
  call void @__inc_ref(ptr %t5254)
  %t9370 = getelementptr ptr, ptr %t9367, i32 1
  store ptr %t5254, ptr %t9370
  %t9371 = getelementptr ptr, ptr %t4, i32 1
  %t9372 = load ptr, ptr %t9371
  call void @__free_recursive(ptr %t9372)
  %t9373 = getelementptr ptr, ptr %t4, i32 2
  %t9374 = load ptr, ptr %t9373
  call void @__free_recursive(ptr %t9374)
  %t9377 = inttoptr i64 280 to ptr
  %t9378 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t9377, ptr %t9378
  %t9375 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t9356, ptr %t9375
  %t9376 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t9367, ptr %t9376
  call void @__free_recursive(ptr %t9343)
  call void @__free_recursive(ptr %t9341)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.2.9379:
  call void @__free_recursive(ptr %t9350)
  call void @__inc_ref(ptr %t9341)
  %t9380 = call ptr @__eqString(ptr %t9341, ptr getelementptr inbounds (i8, ptr @.str.12, i64 12))
  %t9381 = getelementptr ptr, ptr %t9380, i32 0
  %t9382 = load ptr, ptr %t9381
  %t9383 = ptrtoint ptr %t9382 to i64
  switch i64 %t9383, label %tco.case.default.9384 [ i64 1, label %tco.case.arm.1.9385 i64 2, label %tco.case.arm.2.9402 ]
tco.case.arm.1.9385:
  call void @__free_recursive(ptr %t9380)
  %t9386 = call ptr @__alloc(i64 16, i32 1)
  %t9387 = inttoptr i64 112 to ptr
  %t9388 = getelementptr ptr, ptr %t9386, i32 0
  store ptr %t9387, ptr %t9388
  call void @__inc_ref(ptr %t9343)
  %t9389 = getelementptr ptr, ptr %t9386, i32 1
  store ptr %t9343, ptr %t9389
  %t9390 = call ptr @__alloc(i64 16, i32 1)
  %t9391 = inttoptr i64 263 to ptr
  %t9392 = getelementptr ptr, ptr %t9390, i32 0
  store ptr %t9391, ptr %t9392
  call void @__inc_ref(ptr %t5254)
  %t9393 = getelementptr ptr, ptr %t9390, i32 1
  store ptr %t5254, ptr %t9393
  %t9394 = getelementptr ptr, ptr %t4, i32 1
  %t9395 = load ptr, ptr %t9394
  call void @__free_recursive(ptr %t9395)
  %t9396 = getelementptr ptr, ptr %t4, i32 2
  %t9397 = load ptr, ptr %t9396
  call void @__free_recursive(ptr %t9397)
  %t9400 = inttoptr i64 280 to ptr
  %t9401 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t9400, ptr %t9401
  %t9398 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t9386, ptr %t9398
  %t9399 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t9390, ptr %t9399
  call void @__free_recursive(ptr %t9343)
  call void @__free_recursive(ptr %t9341)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.2.9402:
  call void @__free_recursive(ptr %t9380)
  %t9403 = call ptr @__alloc(i64 16, i32 1)
  %t9404 = inttoptr i64 3 to ptr
  %t9405 = getelementptr ptr, ptr %t9403, i32 0
  store ptr %t9404, ptr %t9405
  %t9406 = call ptr @__alloc(i64 16, i32 1)
  %t9407 = inttoptr i64 3932148625 to ptr
  %t9408 = getelementptr ptr, ptr %t9406, i32 0
  store ptr %t9407, ptr %t9408
  %t9409 = call ptr @__alloc(i64 8, i32 0)
  %t9410 = inttoptr i64 38 to ptr
  %t9411 = getelementptr ptr, ptr %t9409, i32 0
  store ptr %t9410, ptr %t9411
  %t9412 = getelementptr ptr, ptr %t9406, i32 1
  store ptr %t9409, ptr %t9412
  %t9413 = getelementptr ptr, ptr %t9403, i32 1
  store ptr %t9406, ptr %t9413
  %t9414 = getelementptr ptr, ptr %t4, i32 1
  %t9415 = load ptr, ptr %t9414
  call void @__free_recursive(ptr %t9415)
  %t9416 = getelementptr ptr, ptr %t4, i32 2
  %t9417 = load ptr, ptr %t9416
  call void @__free_recursive(ptr %t9417)
  %t9420 = inttoptr i64 279 to ptr
  %t9421 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t9420, ptr %t9421
  call void @__inc_ref(ptr %t5254)
  %t9418 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t9418
  %t9419 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t9403, ptr %t9419
  call void @__free_recursive(ptr %t9343)
  call void @__free_recursive(ptr %t9341)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.9384:
  unreachable
tco.case.default.9354:
  unreachable
tco.case.arm.12.9422:
  %t9423 = getelementptr ptr, ptr %t9344, i32 1
  %t9424 = load ptr, ptr %t9423
  call void @__inc_ref(ptr %t9424)
  call void @__free_recursive(ptr %t9344)
  %t9425 = getelementptr ptr, ptr %t9424, i32 0
  %t9426 = load ptr, ptr %t9425
  %t9427 = ptrtoint ptr %t9426 to i64
  switch i64 %t9427, label %tco.case.default.9428 [ i64 15, label %tco.case.arm.15.9429 ]
tco.case.arm.15.9429:
  %t9430 = getelementptr ptr, ptr %t9424, i32 1
  %t9431 = load ptr, ptr %t9430
  call void @__inc_ref(ptr %t9431)
  %t9432 = getelementptr ptr, ptr %t9424, i32 2
  %t9433 = load ptr, ptr %t9432
  call void @__inc_ref(ptr %t9433)
  %t9434 = call ptr @__alloc(i64 32, i32 3)
  %t9435 = inttoptr i64 111 to ptr
  %t9436 = getelementptr ptr, ptr %t9434, i32 0
  store ptr %t9435, ptr %t9436
  call void @__inc_ref(ptr %t9431)
  %t9437 = getelementptr ptr, ptr %t9434, i32 1
  store ptr %t9431, ptr %t9437
  call void @__inc_ref(ptr %t9433)
  %t9438 = getelementptr ptr, ptr %t9434, i32 2
  store ptr %t9433, ptr %t9438
  call void @__inc_ref(ptr %t9343)
  %t9439 = getelementptr ptr, ptr %t9434, i32 3
  store ptr %t9343, ptr %t9439
  %t9448 = getelementptr i8, ptr %t9424, i64 -8
  %t9449 = load i32, ptr %t9448
  %t9450 = icmp eq i32 %t9449, 1
  br i1 %t9450, label %reuse.in_place.9451, label %reuse.copy.9452
reuse.in_place.9451:
  %t9440 = getelementptr ptr, ptr %t9424, i32 1
  %t9441 = load ptr, ptr %t9440
  call void @__free_recursive(ptr %t9441)
  %t9442 = getelementptr ptr, ptr %t9424, i32 2
  %t9443 = load ptr, ptr %t9442
  call void @__free_recursive(ptr %t9443)
  %t9446 = inttoptr i64 280 to ptr
  %t9447 = getelementptr ptr, ptr %t9424, i32 0
  store ptr %t9446, ptr %t9447
  %t9444 = getelementptr ptr, ptr %t9424, i32 1
  store ptr %t9434, ptr %t9444
  call void @__inc_ref(ptr %t5254)
  %t9445 = getelementptr ptr, ptr %t9424, i32 2
  store ptr %t5254, ptr %t9445
  br label %reuse.in_place.end.9454
reuse.in_place.end.9454:
  br label %reuse.join.9453
reuse.copy.9452:
  %t9456 = call ptr @__alloc(i64 24, i32 2)
  %t9457 = inttoptr i64 280 to ptr
  %t9458 = getelementptr ptr, ptr %t9456, i32 0
  store ptr %t9457, ptr %t9458
  %t9459 = getelementptr ptr, ptr %t9456, i32 1
  store ptr %t9434, ptr %t9459
  call void @__inc_ref(ptr %t5254)
  %t9460 = getelementptr ptr, ptr %t9456, i32 2
  store ptr %t5254, ptr %t9460
  call void @__free_recursive(ptr %t9424)
  br label %reuse.copy.end.9455
reuse.copy.end.9455:
  br label %reuse.join.9453
reuse.join.9453:
  %t9461 = phi ptr [ %t9424, %reuse.in_place.end.9454 ], [ %t9456, %reuse.copy.end.9455 ]
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t9433)
  call void @__free_recursive(ptr %t9431)
  call void @__free_recursive(ptr %t9343)
  call void @__free_recursive(ptr %t9341)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t9461, ptr %t3
  br label %tco.loop.0
tco.case.default.9428:
  unreachable
tco.case.default.9348:
  unreachable
tco.case.arm.109.9462:
  %t9463 = getelementptr ptr, ptr %t5252, i32 1
  %t9464 = load ptr, ptr %t9463
  call void @__inc_ref(ptr %t9464)
  %t9465 = call ptr @__parseUInt32(ptr %t9464)
  %t9466 = getelementptr ptr, ptr %t9465, i32 0
  %t9467 = load ptr, ptr %t9466
  %t9468 = ptrtoint ptr %t9467 to i64
  switch i64 %t9468, label %tco.case.default.9469 [ i64 3, label %tco.case.arm.3.9470 i64 4, label %tco.case.arm.4.9489 ]
tco.case.arm.3.9470:
  %t9471 = getelementptr ptr, ptr %t9465, i32 1
  %t9472 = load ptr, ptr %t9471
  call void @__inc_ref(ptr %t9472)
  call void @__free_recursive(ptr %t9465)
  %t9473 = call ptr @__alloc(i64 16, i32 1)
  %t9474 = inttoptr i64 3 to ptr
  %t9475 = getelementptr ptr, ptr %t9473, i32 0
  store ptr %t9474, ptr %t9475
  %t9476 = call ptr @__alloc(i64 16, i32 1)
  %t9477 = inttoptr i64 2448244154 to ptr
  %t9478 = getelementptr ptr, ptr %t9476, i32 0
  store ptr %t9477, ptr %t9478
  call void @__inc_ref(ptr %t9472)
  %t9479 = getelementptr ptr, ptr %t9476, i32 1
  store ptr %t9472, ptr %t9479
  %t9480 = getelementptr ptr, ptr %t9473, i32 1
  store ptr %t9476, ptr %t9480
  %t9481 = getelementptr ptr, ptr %t4, i32 1
  %t9482 = load ptr, ptr %t9481
  call void @__free_recursive(ptr %t9482)
  %t9483 = getelementptr ptr, ptr %t4, i32 2
  %t9484 = load ptr, ptr %t9483
  call void @__free_recursive(ptr %t9484)
  %t9487 = inttoptr i64 279 to ptr
  %t9488 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t9487, ptr %t9488
  call void @__inc_ref(ptr %t5254)
  %t9485 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t9485
  %t9486 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t9473, ptr %t9486
  call void @__free_recursive(ptr %t9472)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.4.9489:
  %t9490 = getelementptr ptr, ptr %t9465, i32 1
  %t9491 = load ptr, ptr %t9490
  call void @__inc_ref(ptr %t9491)
  call void @__free_recursive(ptr %t9465)
  %t9492 = call ptr @__alloc(i64 24, i32 2)
  %t9493 = inttoptr i64 280 to ptr
  %t9494 = getelementptr ptr, ptr %t9492, i32 0
  store ptr %t9493, ptr %t9494
  %t9495 = getelementptr ptr, ptr %t5252, i32 2
  %t9496 = load ptr, ptr %t9495
  call void @__inc_ref(ptr %t9496)
  %t9497 = getelementptr ptr, ptr %t4, i32 1
  %t9498 = load ptr, ptr %t9497
  call void @__free_recursive(ptr %t9498)
  %t9499 = getelementptr ptr, ptr %t4, i32 2
  %t9500 = load ptr, ptr %t9499
  call void @__free_recursive(ptr %t9500)
  %t9503 = inttoptr i64 95 to ptr
  %t9504 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t9503, ptr %t9504
  call void @__inc_ref(ptr %t9491)
  %t9501 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t9491, ptr %t9501
  %t9502 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t9496, ptr %t9502
  %t9505 = getelementptr ptr, ptr %t9492, i32 1
  store ptr %t4, ptr %t9505
  %t9506 = call ptr @__alloc(i64 16, i32 1)
  %t9507 = inttoptr i64 264 to ptr
  %t9508 = getelementptr ptr, ptr %t9506, i32 0
  store ptr %t9507, ptr %t9508
  call void @__inc_ref(ptr %t5254)
  %t9509 = getelementptr ptr, ptr %t9506, i32 1
  store ptr %t5254, ptr %t9509
  %t9510 = getelementptr ptr, ptr %t9492, i32 2
  store ptr %t9506, ptr %t9510
  call void @__free_recursive(ptr %t9491)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t9492, ptr %t3
  br label %tco.loop.0
tco.case.default.9469:
  unreachable
tco.case.arm.110.9511:
  %t9512 = getelementptr ptr, ptr %t5252, i32 1
  %t9513 = load ptr, ptr %t9512
  call void @__inc_ref(ptr %t9513)
  %t9514 = call ptr @__splitOnFirst(ptr getelementptr inbounds (i8, ptr @.str.10, i64 12), ptr %t9513)
  %t9515 = getelementptr ptr, ptr %t9514, i32 0
  %t9516 = load ptr, ptr %t9515
  %t9517 = ptrtoint ptr %t9516 to i64
  switch i64 %t9517, label %tco.case.default.9518 [ i64 11, label %tco.case.arm.11.9519 i64 12, label %tco.case.arm.12.9539 ]
tco.case.arm.11.9519:
  call void @__free_recursive(ptr %t9514)
  %t9520 = call ptr @__alloc(i64 16, i32 1)
  %t9521 = inttoptr i64 3 to ptr
  %t9522 = getelementptr ptr, ptr %t9520, i32 0
  store ptr %t9521, ptr %t9522
  %t9523 = call ptr @__alloc(i64 16, i32 1)
  %t9524 = inttoptr i64 3932148625 to ptr
  %t9525 = getelementptr ptr, ptr %t9523, i32 0
  store ptr %t9524, ptr %t9525
  %t9526 = call ptr @__alloc(i64 8, i32 0)
  %t9527 = inttoptr i64 38 to ptr
  %t9528 = getelementptr ptr, ptr %t9526, i32 0
  store ptr %t9527, ptr %t9528
  %t9529 = getelementptr ptr, ptr %t9523, i32 1
  store ptr %t9526, ptr %t9529
  %t9530 = getelementptr ptr, ptr %t9520, i32 1
  store ptr %t9523, ptr %t9530
  %t9531 = getelementptr ptr, ptr %t4, i32 1
  %t9532 = load ptr, ptr %t9531
  call void @__free_recursive(ptr %t9532)
  %t9533 = getelementptr ptr, ptr %t4, i32 2
  %t9534 = load ptr, ptr %t9533
  call void @__free_recursive(ptr %t9534)
  %t9537 = inttoptr i64 279 to ptr
  %t9538 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t9537, ptr %t9538
  call void @__inc_ref(ptr %t5254)
  %t9535 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t9535
  %t9536 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t9520, ptr %t9536
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.12.9539:
  %t9540 = getelementptr ptr, ptr %t9514, i32 1
  %t9541 = load ptr, ptr %t9540
  call void @__inc_ref(ptr %t9541)
  call void @__free_recursive(ptr %t9514)
  %t9542 = getelementptr ptr, ptr %t9541, i32 0
  %t9543 = load ptr, ptr %t9542
  %t9544 = ptrtoint ptr %t9543 to i64
  switch i64 %t9544, label %tco.case.default.9545 [ i64 15, label %tco.case.arm.15.9546 ]
tco.case.arm.15.9546:
  %t9547 = getelementptr ptr, ptr %t9541, i32 1
  %t9548 = load ptr, ptr %t9547
  call void @__inc_ref(ptr %t9548)
  %t9549 = getelementptr ptr, ptr %t9541, i32 2
  %t9550 = load ptr, ptr %t9549
  call void @__inc_ref(ptr %t9550)
  call void @__inc_ref(ptr %t9548)
  %t9551 = call ptr @__parseUInt32(ptr %t9548)
  %t9552 = getelementptr ptr, ptr %t9551, i32 0
  %t9553 = load ptr, ptr %t9552
  %t9554 = ptrtoint ptr %t9553 to i64
  switch i64 %t9554, label %tco.case.default.9555 [ i64 3, label %tco.case.arm.3.9556 i64 4, label %tco.case.arm.4.9589 ]
tco.case.arm.3.9556:
  %t9557 = getelementptr ptr, ptr %t9551, i32 1
  %t9558 = load ptr, ptr %t9557
  call void @__inc_ref(ptr %t9558)
  call void @__free_recursive(ptr %t9551)
  %t9559 = call ptr @__alloc(i64 16, i32 1)
  %t9560 = inttoptr i64 3 to ptr
  %t9561 = getelementptr ptr, ptr %t9559, i32 0
  store ptr %t9560, ptr %t9561
  %t9562 = call ptr @__alloc(i64 16, i32 1)
  %t9563 = inttoptr i64 2448244154 to ptr
  %t9564 = getelementptr ptr, ptr %t9562, i32 0
  store ptr %t9563, ptr %t9564
  call void @__inc_ref(ptr %t9558)
  %t9565 = getelementptr ptr, ptr %t9562, i32 1
  store ptr %t9558, ptr %t9565
  %t9566 = getelementptr ptr, ptr %t9559, i32 1
  store ptr %t9562, ptr %t9566
  %t9575 = getelementptr i8, ptr %t9541, i64 -8
  %t9576 = load i32, ptr %t9575
  %t9577 = icmp eq i32 %t9576, 1
  br i1 %t9577, label %reuse.in_place.9578, label %reuse.copy.9579
reuse.in_place.9578:
  %t9567 = getelementptr ptr, ptr %t9541, i32 1
  %t9568 = load ptr, ptr %t9567
  call void @__free_recursive(ptr %t9568)
  %t9569 = getelementptr ptr, ptr %t9541, i32 2
  %t9570 = load ptr, ptr %t9569
  call void @__free_recursive(ptr %t9570)
  %t9573 = inttoptr i64 279 to ptr
  %t9574 = getelementptr ptr, ptr %t9541, i32 0
  store ptr %t9573, ptr %t9574
  call void @__inc_ref(ptr %t5254)
  %t9571 = getelementptr ptr, ptr %t9541, i32 1
  store ptr %t5254, ptr %t9571
  %t9572 = getelementptr ptr, ptr %t9541, i32 2
  store ptr %t9559, ptr %t9572
  br label %reuse.in_place.end.9581
reuse.in_place.end.9581:
  br label %reuse.join.9580
reuse.copy.9579:
  %t9583 = call ptr @__alloc(i64 24, i32 2)
  %t9584 = inttoptr i64 279 to ptr
  %t9585 = getelementptr ptr, ptr %t9583, i32 0
  store ptr %t9584, ptr %t9585
  call void @__inc_ref(ptr %t5254)
  %t9586 = getelementptr ptr, ptr %t9583, i32 1
  store ptr %t5254, ptr %t9586
  %t9587 = getelementptr ptr, ptr %t9583, i32 2
  store ptr %t9559, ptr %t9587
  call void @__free_recursive(ptr %t9541)
  br label %reuse.copy.end.9582
reuse.copy.end.9582:
  br label %reuse.join.9580
reuse.join.9580:
  %t9588 = phi ptr [ %t9541, %reuse.in_place.end.9581 ], [ %t9583, %reuse.copy.end.9582 ]
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t9558)
  call void @__free_recursive(ptr %t9550)
  call void @__free_recursive(ptr %t9548)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t9588, ptr %t3
  br label %tco.loop.0
tco.case.arm.4.9589:
  %t9590 = getelementptr ptr, ptr %t9551, i32 1
  %t9591 = load ptr, ptr %t9590
  call void @__inc_ref(ptr %t9591)
  call void @__free_recursive(ptr %t9551)
  %t9592 = call ptr @__alloc(i64 32, i32 3)
  %t9593 = inttoptr i64 100 to ptr
  %t9594 = getelementptr ptr, ptr %t9592, i32 0
  store ptr %t9593, ptr %t9594
  call void @__inc_ref(ptr %t9591)
  %t9595 = getelementptr ptr, ptr %t9592, i32 1
  store ptr %t9591, ptr %t9595
  call void @__inc_ref(ptr %t9550)
  %t9596 = getelementptr ptr, ptr %t9592, i32 2
  store ptr %t9550, ptr %t9596
  %t9597 = getelementptr ptr, ptr %t5252, i32 2
  %t9598 = load ptr, ptr %t9597
  call void @__inc_ref(ptr %t9598)
  %t9599 = getelementptr ptr, ptr %t9592, i32 3
  store ptr %t9598, ptr %t9599
  %t9600 = call ptr @__alloc(i64 16, i32 1)
  %t9601 = inttoptr i64 265 to ptr
  %t9602 = getelementptr ptr, ptr %t9600, i32 0
  store ptr %t9601, ptr %t9602
  call void @__inc_ref(ptr %t5254)
  %t9603 = getelementptr ptr, ptr %t9600, i32 1
  store ptr %t5254, ptr %t9603
  %t9612 = getelementptr i8, ptr %t9541, i64 -8
  %t9613 = load i32, ptr %t9612
  %t9614 = icmp eq i32 %t9613, 1
  br i1 %t9614, label %reuse.in_place.9615, label %reuse.copy.9616
reuse.in_place.9615:
  %t9604 = getelementptr ptr, ptr %t9541, i32 1
  %t9605 = load ptr, ptr %t9604
  call void @__free_recursive(ptr %t9605)
  %t9606 = getelementptr ptr, ptr %t9541, i32 2
  %t9607 = load ptr, ptr %t9606
  call void @__free_recursive(ptr %t9607)
  %t9610 = inttoptr i64 280 to ptr
  %t9611 = getelementptr ptr, ptr %t9541, i32 0
  store ptr %t9610, ptr %t9611
  %t9608 = getelementptr ptr, ptr %t9541, i32 1
  store ptr %t9592, ptr %t9608
  %t9609 = getelementptr ptr, ptr %t9541, i32 2
  store ptr %t9600, ptr %t9609
  br label %reuse.in_place.end.9618
reuse.in_place.end.9618:
  br label %reuse.join.9617
reuse.copy.9616:
  %t9620 = call ptr @__alloc(i64 24, i32 2)
  %t9621 = inttoptr i64 280 to ptr
  %t9622 = getelementptr ptr, ptr %t9620, i32 0
  store ptr %t9621, ptr %t9622
  %t9623 = getelementptr ptr, ptr %t9620, i32 1
  store ptr %t9592, ptr %t9623
  %t9624 = getelementptr ptr, ptr %t9620, i32 2
  store ptr %t9600, ptr %t9624
  call void @__free_recursive(ptr %t9541)
  br label %reuse.copy.end.9619
reuse.copy.end.9619:
  br label %reuse.join.9617
reuse.join.9617:
  %t9625 = phi ptr [ %t9541, %reuse.in_place.end.9618 ], [ %t9620, %reuse.copy.end.9619 ]
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t9591)
  call void @__free_recursive(ptr %t9550)
  call void @__free_recursive(ptr %t9548)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t9625, ptr %t3
  br label %tco.loop.0
tco.case.default.9555:
  unreachable
tco.case.default.9545:
  unreachable
tco.case.default.9518:
  unreachable
tco.case.arm.111.9626:
  %t9627 = getelementptr ptr, ptr %t5252, i32 1
  %t9628 = load ptr, ptr %t9627
  call void @__inc_ref(ptr %t9628)
  %t9629 = getelementptr ptr, ptr %t5252, i32 2
  %t9630 = load ptr, ptr %t9629
  call void @__inc_ref(ptr %t9630)
  %t9631 = getelementptr ptr, ptr %t5252, i32 3
  %t9632 = load ptr, ptr %t9631
  call void @__inc_ref(ptr %t9632)
  call void @__inc_ref(ptr %t9628)
  %t9633 = call ptr @__eqString(ptr %t9628, ptr getelementptr inbounds (i8, ptr @.str.13, i64 12))
  %t9634 = getelementptr ptr, ptr %t9633, i32 0
  %t9635 = load ptr, ptr %t9634
  %t9636 = ptrtoint ptr %t9635 to i64
  switch i64 %t9636, label %tco.case.default.9637 [ i64 1, label %tco.case.arm.1.9638 i64 2, label %tco.case.arm.2.9652 ]
tco.case.arm.1.9638:
  call void @__free_recursive(ptr %t9633)
  %t9639 = call ptr @__alloc(i64 24, i32 2)
  %t9640 = inttoptr i64 280 to ptr
  %t9641 = getelementptr ptr, ptr %t9639, i32 0
  store ptr %t9640, ptr %t9641
  %t9642 = getelementptr ptr, ptr %t4, i32 1
  %t9643 = load ptr, ptr %t9642
  call void @__free_recursive(ptr %t9643)
  %t9644 = getelementptr ptr, ptr %t4, i32 2
  %t9645 = load ptr, ptr %t9644
  call void @__free_recursive(ptr %t9645)
  %t9648 = inttoptr i64 71 to ptr
  %t9649 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t9648, ptr %t9649
  call void @__inc_ref(ptr %t9630)
  %t9646 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t9630, ptr %t9646
  call void @__inc_ref(ptr %t9632)
  %t9647 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t9632, ptr %t9647
  %t9650 = getelementptr ptr, ptr %t9639, i32 1
  store ptr %t4, ptr %t9650
  call void @__inc_ref(ptr %t5254)
  %t9651 = getelementptr ptr, ptr %t9639, i32 2
  store ptr %t5254, ptr %t9651
  call void @__free_recursive(ptr %t9632)
  call void @__free_recursive(ptr %t9630)
  call void @__free_recursive(ptr %t9628)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t9639, ptr %t3
  br label %tco.loop.0
tco.case.arm.2.9652:
  call void @__free_recursive(ptr %t9633)
  call void @__inc_ref(ptr %t9628)
  %t9653 = call ptr @__eqString(ptr %t9628, ptr getelementptr inbounds (i8, ptr @.str.14, i64 12))
  %t9654 = getelementptr ptr, ptr %t9653, i32 0
  %t9655 = load ptr, ptr %t9654
  %t9656 = ptrtoint ptr %t9655 to i64
  switch i64 %t9656, label %tco.case.default.9657 [ i64 1, label %tco.case.arm.1.9658 i64 2, label %tco.case.arm.2.9672 ]
tco.case.arm.1.9658:
  call void @__free_recursive(ptr %t9653)
  %t9659 = call ptr @__alloc(i64 24, i32 2)
  %t9660 = inttoptr i64 280 to ptr
  %t9661 = getelementptr ptr, ptr %t9659, i32 0
  store ptr %t9660, ptr %t9661
  %t9662 = getelementptr ptr, ptr %t4, i32 1
  %t9663 = load ptr, ptr %t9662
  call void @__free_recursive(ptr %t9663)
  %t9664 = getelementptr ptr, ptr %t4, i32 2
  %t9665 = load ptr, ptr %t9664
  call void @__free_recursive(ptr %t9665)
  %t9668 = inttoptr i64 72 to ptr
  %t9669 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t9668, ptr %t9669
  call void @__inc_ref(ptr %t9630)
  %t9666 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t9630, ptr %t9666
  call void @__inc_ref(ptr %t9632)
  %t9667 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t9632, ptr %t9667
  %t9670 = getelementptr ptr, ptr %t9659, i32 1
  store ptr %t4, ptr %t9670
  call void @__inc_ref(ptr %t5254)
  %t9671 = getelementptr ptr, ptr %t9659, i32 2
  store ptr %t5254, ptr %t9671
  call void @__free_recursive(ptr %t9632)
  call void @__free_recursive(ptr %t9630)
  call void @__free_recursive(ptr %t9628)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t9659, ptr %t3
  br label %tco.loop.0
tco.case.arm.2.9672:
  call void @__free_recursive(ptr %t9653)
  call void @__inc_ref(ptr %t9628)
  %t9673 = call ptr @__eqString(ptr %t9628, ptr getelementptr inbounds (i8, ptr @.str.15, i64 12))
  %t9674 = getelementptr ptr, ptr %t9673, i32 0
  %t9675 = load ptr, ptr %t9674
  %t9676 = ptrtoint ptr %t9675 to i64
  switch i64 %t9676, label %tco.case.default.9677 [ i64 1, label %tco.case.arm.1.9678 i64 2, label %tco.case.arm.2.9692 ]
tco.case.arm.1.9678:
  call void @__free_recursive(ptr %t9673)
  %t9679 = call ptr @__alloc(i64 24, i32 2)
  %t9680 = inttoptr i64 280 to ptr
  %t9681 = getelementptr ptr, ptr %t9679, i32 0
  store ptr %t9680, ptr %t9681
  %t9682 = getelementptr ptr, ptr %t4, i32 1
  %t9683 = load ptr, ptr %t9682
  call void @__free_recursive(ptr %t9683)
  %t9684 = getelementptr ptr, ptr %t4, i32 2
  %t9685 = load ptr, ptr %t9684
  call void @__free_recursive(ptr %t9685)
  %t9688 = inttoptr i64 110 to ptr
  %t9689 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t9688, ptr %t9689
  call void @__inc_ref(ptr %t9630)
  %t9686 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t9630, ptr %t9686
  call void @__inc_ref(ptr %t9632)
  %t9687 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t9632, ptr %t9687
  %t9690 = getelementptr ptr, ptr %t9679, i32 1
  store ptr %t4, ptr %t9690
  call void @__inc_ref(ptr %t5254)
  %t9691 = getelementptr ptr, ptr %t9679, i32 2
  store ptr %t5254, ptr %t9691
  call void @__free_recursive(ptr %t9632)
  call void @__free_recursive(ptr %t9630)
  call void @__free_recursive(ptr %t9628)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t9679, ptr %t3
  br label %tco.loop.0
tco.case.arm.2.9692:
  call void @__free_recursive(ptr %t9673)
  call void @__inc_ref(ptr %t9628)
  %t9693 = call ptr @__eqString(ptr %t9628, ptr getelementptr inbounds (i8, ptr @.str.16, i64 12))
  %t9694 = getelementptr ptr, ptr %t9693, i32 0
  %t9695 = load ptr, ptr %t9694
  %t9696 = ptrtoint ptr %t9695 to i64
  switch i64 %t9696, label %tco.case.default.9697 [ i64 1, label %tco.case.arm.1.9698 i64 2, label %tco.case.arm.2.9712 ]
tco.case.arm.1.9698:
  call void @__free_recursive(ptr %t9693)
  %t9699 = call ptr @__alloc(i64 24, i32 2)
  %t9700 = inttoptr i64 280 to ptr
  %t9701 = getelementptr ptr, ptr %t9699, i32 0
  store ptr %t9700, ptr %t9701
  %t9702 = getelementptr ptr, ptr %t4, i32 1
  %t9703 = load ptr, ptr %t9702
  call void @__free_recursive(ptr %t9703)
  %t9704 = getelementptr ptr, ptr %t4, i32 2
  %t9705 = load ptr, ptr %t9704
  call void @__free_recursive(ptr %t9705)
  %t9708 = inttoptr i64 109 to ptr
  %t9709 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t9708, ptr %t9709
  call void @__inc_ref(ptr %t9630)
  %t9706 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t9630, ptr %t9706
  call void @__inc_ref(ptr %t9632)
  %t9707 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t9632, ptr %t9707
  %t9710 = getelementptr ptr, ptr %t9699, i32 1
  store ptr %t4, ptr %t9710
  call void @__inc_ref(ptr %t5254)
  %t9711 = getelementptr ptr, ptr %t9699, i32 2
  store ptr %t5254, ptr %t9711
  call void @__free_recursive(ptr %t9632)
  call void @__free_recursive(ptr %t9630)
  call void @__free_recursive(ptr %t9628)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t9699, ptr %t3
  br label %tco.loop.0
tco.case.arm.2.9712:
  call void @__free_recursive(ptr %t9693)
  %t9713 = call ptr @__alloc(i64 16, i32 1)
  %t9714 = inttoptr i64 3 to ptr
  %t9715 = getelementptr ptr, ptr %t9713, i32 0
  store ptr %t9714, ptr %t9715
  %t9716 = call ptr @__alloc(i64 16, i32 1)
  %t9717 = inttoptr i64 3932148625 to ptr
  %t9718 = getelementptr ptr, ptr %t9716, i32 0
  store ptr %t9717, ptr %t9718
  %t9719 = call ptr @__alloc(i64 8, i32 0)
  %t9720 = inttoptr i64 38 to ptr
  %t9721 = getelementptr ptr, ptr %t9719, i32 0
  store ptr %t9720, ptr %t9721
  %t9722 = getelementptr ptr, ptr %t9716, i32 1
  store ptr %t9719, ptr %t9722
  %t9723 = getelementptr ptr, ptr %t9713, i32 1
  store ptr %t9716, ptr %t9723
  %t9724 = getelementptr ptr, ptr %t4, i32 1
  %t9725 = load ptr, ptr %t9724
  call void @__free_recursive(ptr %t9725)
  %t9726 = getelementptr ptr, ptr %t4, i32 2
  %t9727 = load ptr, ptr %t9726
  call void @__free_recursive(ptr %t9727)
  %t9730 = inttoptr i64 279 to ptr
  %t9731 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t9730, ptr %t9731
  call void @__inc_ref(ptr %t5254)
  %t9728 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t9728
  %t9729 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t9713, ptr %t9729
  call void @__free_recursive(ptr %t9632)
  call void @__free_recursive(ptr %t9630)
  call void @__free_recursive(ptr %t9628)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.9697:
  unreachable
tco.case.default.9677:
  unreachable
tco.case.default.9657:
  unreachable
tco.case.default.9637:
  unreachable
tco.case.arm.112.9732:
  %t9733 = call ptr @__alloc(i64 24, i32 2)
  %t9734 = inttoptr i64 280 to ptr
  %t9735 = getelementptr ptr, ptr %t9733, i32 0
  store ptr %t9734, ptr %t9735
  %t9736 = getelementptr ptr, ptr %t5252, i32 1
  %t9737 = load ptr, ptr %t9736
  call void @__inc_ref(ptr %t9737)
  %t9738 = call ptr @__alloc(i64 8, i32 0)
  %t9739 = inttoptr i64 13 to ptr
  %t9740 = getelementptr ptr, ptr %t9738, i32 0
  store ptr %t9739, ptr %t9740
  %t9741 = getelementptr ptr, ptr %t4, i32 1
  %t9742 = load ptr, ptr %t9741
  call void @__free_recursive(ptr %t9742)
  %t9743 = getelementptr ptr, ptr %t4, i32 2
  %t9744 = load ptr, ptr %t9743
  call void @__free_recursive(ptr %t9744)
  %t9747 = inttoptr i64 75 to ptr
  %t9748 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t9747, ptr %t9748
  %t9745 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t9737, ptr %t9745
  %t9746 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t9738, ptr %t9746
  %t9749 = getelementptr ptr, ptr %t9733, i32 1
  store ptr %t4, ptr %t9749
  %t9750 = call ptr @__alloc(i64 16, i32 1)
  %t9751 = inttoptr i64 266 to ptr
  %t9752 = getelementptr ptr, ptr %t9750, i32 0
  store ptr %t9751, ptr %t9752
  call void @__inc_ref(ptr %t5254)
  %t9753 = getelementptr ptr, ptr %t9750, i32 1
  store ptr %t5254, ptr %t9753
  %t9754 = getelementptr ptr, ptr %t9733, i32 2
  store ptr %t9750, ptr %t9754
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t9733, ptr %t3
  br label %tco.loop.0
tco.case.arm.113.9755:
  %t9756 = getelementptr ptr, ptr %t5252, i32 1
  %t9757 = load ptr, ptr %t9756
  call void @__inc_ref(ptr %t9757)
  %t9758 = getelementptr ptr, ptr %t5252, i32 3
  %t9759 = load ptr, ptr %t9758
  call void @__inc_ref(ptr %t9759)
  %t9760 = getelementptr ptr, ptr %t5252, i32 2
  %t9761 = load ptr, ptr %t9760
  call void @__inc_ref(ptr %t9761)
  %t9762 = getelementptr ptr, ptr %t9761, i32 0
  %t9763 = load ptr, ptr %t9762
  %t9764 = ptrtoint ptr %t9763 to i64
  switch i64 %t9764, label %tco.case.default.9765 [ i64 13, label %tco.case.arm.13.9766 i64 14, label %tco.case.arm.14.9779 ]
tco.case.arm.13.9766:
  call void @__free_recursive(ptr %t9761)
  %t9767 = call ptr @__alloc(i64 16, i32 1)
  %t9768 = inttoptr i64 4 to ptr
  %t9769 = getelementptr ptr, ptr %t9767, i32 0
  store ptr %t9768, ptr %t9769
  call void @__inc_ref(ptr %t9759)
  %t9770 = getelementptr ptr, ptr %t9767, i32 1
  store ptr %t9759, ptr %t9770
  %t9771 = getelementptr ptr, ptr %t4, i32 1
  %t9772 = load ptr, ptr %t9771
  call void @__free_recursive(ptr %t9772)
  %t9773 = getelementptr ptr, ptr %t4, i32 2
  %t9774 = load ptr, ptr %t9773
  call void @__free_recursive(ptr %t9774)
  %t9777 = inttoptr i64 279 to ptr
  %t9778 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t9777, ptr %t9778
  call void @__inc_ref(ptr %t5254)
  %t9775 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t9775
  %t9776 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t9767, ptr %t9776
  call void @__free_recursive(ptr %t9759)
  call void @__free_recursive(ptr %t9757)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.14.9779:
  %t9780 = getelementptr ptr, ptr %t9761, i32 1
  %t9781 = load ptr, ptr %t9780
  call void @__inc_ref(ptr %t9781)
  %t9782 = getelementptr ptr, ptr %t9761, i32 2
  %t9783 = load ptr, ptr %t9782
  call void @__inc_ref(ptr %t9783)
  call void @__free_recursive(ptr %t9761)
  %t9784 = call ptr @__alloc(i64 24, i32 2)
  %t9785 = inttoptr i64 280 to ptr
  %t9786 = getelementptr ptr, ptr %t9784, i32 0
  store ptr %t9785, ptr %t9786
  %t9787 = getelementptr ptr, ptr %t4, i32 1
  %t9788 = load ptr, ptr %t9787
  call void @__free_recursive(ptr %t9788)
  %t9789 = getelementptr ptr, ptr %t4, i32 2
  %t9790 = load ptr, ptr %t9789
  call void @__free_recursive(ptr %t9790)
  %t9793 = inttoptr i64 108 to ptr
  %t9794 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t9793, ptr %t9794
  call void @__inc_ref(ptr %t9781)
  %t9791 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t9781, ptr %t9791
  call void @__inc_ref(ptr %t9757)
  %t9792 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t9757, ptr %t9792
  %t9795 = getelementptr ptr, ptr %t9784, i32 1
  store ptr %t4, ptr %t9795
  %t9796 = call ptr @__alloc(i64 40, i32 4)
  %t9797 = inttoptr i64 267 to ptr
  %t9798 = getelementptr ptr, ptr %t9796, i32 0
  store ptr %t9797, ptr %t9798
  call void @__inc_ref(ptr %t5254)
  %t9799 = getelementptr ptr, ptr %t9796, i32 1
  store ptr %t5254, ptr %t9799
  call void @__inc_ref(ptr %t9757)
  %t9800 = getelementptr ptr, ptr %t9796, i32 2
  store ptr %t9757, ptr %t9800
  call void @__inc_ref(ptr %t9759)
  %t9801 = getelementptr ptr, ptr %t9796, i32 3
  store ptr %t9759, ptr %t9801
  call void @__inc_ref(ptr %t9783)
  %t9802 = getelementptr ptr, ptr %t9796, i32 4
  store ptr %t9783, ptr %t9802
  %t9803 = getelementptr ptr, ptr %t9784, i32 2
  store ptr %t9796, ptr %t9803
  call void @__free_recursive(ptr %t9783)
  call void @__free_recursive(ptr %t9781)
  call void @__free_recursive(ptr %t9759)
  call void @__free_recursive(ptr %t9757)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t9784, ptr %t3
  br label %tco.loop.0
tco.case.default.9765:
  unreachable
tco.case.arm.114.9804:
  %t9805 = getelementptr ptr, ptr %t5252, i32 1
  %t9806 = load ptr, ptr %t9805
  call void @__inc_ref(ptr %t9806)
  %t9807 = getelementptr ptr, ptr %t5252, i32 3
  %t9808 = load ptr, ptr %t9807
  call void @__inc_ref(ptr %t9808)
  %t9809 = getelementptr ptr, ptr %t5252, i32 2
  %t9810 = load ptr, ptr %t9809
  call void @__inc_ref(ptr %t9810)
  %t9811 = getelementptr ptr, ptr %t9810, i32 0
  %t9812 = load ptr, ptr %t9811
  %t9813 = ptrtoint ptr %t9812 to i64
  switch i64 %t9813, label %tco.case.default.9814 [ i64 30, label %tco.case.arm.30.9815 i64 31, label %tco.case.arm.31.9828 i64 32, label %tco.case.arm.32.9854 ]
tco.case.arm.30.9815:
  call void @__free_recursive(ptr %t9810)
  %t9816 = call ptr @__alloc(i64 16, i32 1)
  %t9817 = inttoptr i64 31 to ptr
  %t9818 = getelementptr ptr, ptr %t9816, i32 0
  store ptr %t9817, ptr %t9818
  call void @__inc_ref(ptr %t9808)
  %t9819 = getelementptr ptr, ptr %t9816, i32 1
  store ptr %t9808, ptr %t9819
  %t9820 = getelementptr ptr, ptr %t4, i32 1
  %t9821 = load ptr, ptr %t9820
  call void @__free_recursive(ptr %t9821)
  %t9822 = getelementptr ptr, ptr %t4, i32 2
  %t9823 = load ptr, ptr %t9822
  call void @__free_recursive(ptr %t9823)
  %t9826 = inttoptr i64 279 to ptr
  %t9827 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t9826, ptr %t9827
  call void @__inc_ref(ptr %t5254)
  %t9824 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t9824
  %t9825 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t9816, ptr %t9825
  call void @__free_recursive(ptr %t9808)
  call void @__free_recursive(ptr %t9806)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.31.9828:
  %t9829 = getelementptr ptr, ptr %t9810, i32 1
  %t9830 = load ptr, ptr %t9829
  call void @__inc_ref(ptr %t9830)
  call void @__free_recursive(ptr %t9810)
  %t9831 = call ptr @__alloc(i64 40, i32 4)
  %t9832 = inttoptr i64 92 to ptr
  %t9833 = getelementptr ptr, ptr %t9831, i32 0
  store ptr %t9832, ptr %t9833
  call void @__inc_ref(ptr %t9806)
  %t9834 = getelementptr ptr, ptr %t9831, i32 1
  store ptr %t9806, ptr %t9834
  %t9835 = call ptr @__alloc(i64 16, i32 1)
  %t9836 = inttoptr i64 24 to ptr
  %t9837 = getelementptr ptr, ptr %t9835, i32 0
  store ptr %t9836, ptr %t9837
  call void @__inc_ref(ptr %t9830)
  %t9838 = getelementptr ptr, ptr %t9835, i32 1
  store ptr %t9830, ptr %t9838
  %t9839 = getelementptr ptr, ptr %t9831, i32 2
  store ptr %t9835, ptr %t9839
  %t9840 = call ptr @__alloc(i64 8, i32 0)
  %t9841 = inttoptr i64 30 to ptr
  %t9842 = getelementptr ptr, ptr %t9840, i32 0
  store ptr %t9841, ptr %t9842
  %t9843 = getelementptr ptr, ptr %t9831, i32 3
  store ptr %t9840, ptr %t9843
  %t9844 = call ptr @__alloc(i64 16, i32 1)
  %t9845 = inttoptr i64 24 to ptr
  %t9846 = getelementptr ptr, ptr %t9844, i32 0
  store ptr %t9845, ptr %t9846
  call void @__inc_ref(ptr %t9808)
  %t9847 = getelementptr ptr, ptr %t9844, i32 1
  store ptr %t9808, ptr %t9847
  %t9848 = getelementptr ptr, ptr %t9831, i32 4
  store ptr %t9844, ptr %t9848
  %t9849 = getelementptr ptr, ptr %t4, i32 1
  %t9850 = load ptr, ptr %t9849
  call void @__free_recursive(ptr %t9850)
  %t9852 = inttoptr i64 280 to ptr
  %t9853 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t9852, ptr %t9853
  %t9851 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t9831, ptr %t9851
  call void @__free_recursive(ptr %t9830)
  call void @__free_recursive(ptr %t9808)
  call void @__free_recursive(ptr %t9806)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.32.9854:
  %t9855 = getelementptr ptr, ptr %t9810, i32 2
  %t9856 = load ptr, ptr %t9855
  call void @__inc_ref(ptr %t9856)
  %t9857 = getelementptr ptr, ptr %t9810, i32 3
  %t9858 = load ptr, ptr %t9857
  call void @__inc_ref(ptr %t9858)
  %t9859 = getelementptr ptr, ptr %t9810, i32 4
  %t9860 = load ptr, ptr %t9859
  call void @__inc_ref(ptr %t9860)
  call void @__free_recursive(ptr %t9810)
  %t9861 = getelementptr ptr, ptr %t9860, i32 0
  %t9862 = load ptr, ptr %t9861
  %t9863 = ptrtoint ptr %t9862 to i64
  switch i64 %t9863, label %tco.case.default.9864 [ i64 24, label %tco.case.arm.24.9865 i64 25, label %tco.case.arm.25.9888 i64 26, label %tco.case.arm.26.9911 i64 27, label %tco.case.arm.27.9937 ]
tco.case.arm.24.9865:
  %t9866 = call ptr @__alloc(i64 24, i32 2)
  %t9867 = inttoptr i64 280 to ptr
  %t9868 = getelementptr ptr, ptr %t9866, i32 0
  store ptr %t9867, ptr %t9868
  %t9869 = call ptr @__alloc(i64 40, i32 4)
  %t9870 = inttoptr i64 92 to ptr
  %t9871 = getelementptr ptr, ptr %t9869, i32 0
  store ptr %t9870, ptr %t9871
  call void @__inc_ref(ptr %t9806)
  %t9872 = getelementptr ptr, ptr %t9869, i32 1
  store ptr %t9806, ptr %t9872
  call void @__inc_ref(ptr %t9856)
  %t9873 = getelementptr ptr, ptr %t9869, i32 2
  store ptr %t9856, ptr %t9873
  call void @__inc_ref(ptr %t9858)
  %t9874 = getelementptr ptr, ptr %t9869, i32 3
  store ptr %t9858, ptr %t9874
  %t9875 = getelementptr ptr, ptr %t9860, i32 1
  %t9876 = load ptr, ptr %t9875
  call void @__inc_ref(ptr %t9876)
  %t9877 = getelementptr ptr, ptr %t4, i32 1
  %t9878 = load ptr, ptr %t9877
  call void @__free_recursive(ptr %t9878)
  %t9879 = getelementptr ptr, ptr %t4, i32 2
  %t9880 = load ptr, ptr %t9879
  call void @__free_recursive(ptr %t9880)
  %t9883 = inttoptr i64 25 to ptr
  %t9884 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t9883, ptr %t9884
  %t9881 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t9876, ptr %t9881
  call void @__inc_ref(ptr %t9808)
  %t9882 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t9808, ptr %t9882
  %t9885 = getelementptr ptr, ptr %t9869, i32 4
  store ptr %t4, ptr %t9885
  %t9886 = getelementptr ptr, ptr %t9866, i32 1
  store ptr %t9869, ptr %t9886
  call void @__inc_ref(ptr %t5254)
  %t9887 = getelementptr ptr, ptr %t9866, i32 2
  store ptr %t5254, ptr %t9887
  call void @__free_recursive(ptr %t9860)
  call void @__free_recursive(ptr %t9858)
  call void @__free_recursive(ptr %t9856)
  call void @__free_recursive(ptr %t9808)
  call void @__free_recursive(ptr %t9806)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t9866, ptr %t3
  br label %tco.loop.0
tco.case.arm.25.9888:
  %t9889 = call ptr @__alloc(i64 40, i32 4)
  %t9890 = inttoptr i64 92 to ptr
  %t9891 = getelementptr ptr, ptr %t9889, i32 0
  store ptr %t9890, ptr %t9891
  call void @__inc_ref(ptr %t9806)
  %t9892 = getelementptr ptr, ptr %t9889, i32 1
  store ptr %t9806, ptr %t9892
  call void @__inc_ref(ptr %t9856)
  %t9893 = getelementptr ptr, ptr %t9889, i32 2
  store ptr %t9856, ptr %t9893
  call void @__inc_ref(ptr %t9858)
  %t9894 = getelementptr ptr, ptr %t9889, i32 3
  store ptr %t9858, ptr %t9894
  %t9895 = call ptr @__alloc(i64 32, i32 3)
  %t9896 = inttoptr i64 26 to ptr
  %t9897 = getelementptr ptr, ptr %t9895, i32 0
  store ptr %t9896, ptr %t9897
  %t9898 = getelementptr ptr, ptr %t9860, i32 1
  %t9899 = load ptr, ptr %t9898
  call void @__inc_ref(ptr %t9899)
  %t9900 = getelementptr ptr, ptr %t9895, i32 1
  store ptr %t9899, ptr %t9900
  %t9901 = getelementptr ptr, ptr %t9860, i32 2
  %t9902 = load ptr, ptr %t9901
  call void @__inc_ref(ptr %t9902)
  %t9903 = getelementptr ptr, ptr %t9895, i32 2
  store ptr %t9902, ptr %t9903
  call void @__inc_ref(ptr %t9808)
  %t9904 = getelementptr ptr, ptr %t9895, i32 3
  store ptr %t9808, ptr %t9904
  %t9905 = getelementptr ptr, ptr %t9889, i32 4
  store ptr %t9895, ptr %t9905
  %t9906 = getelementptr ptr, ptr %t4, i32 1
  %t9907 = load ptr, ptr %t9906
  call void @__free_recursive(ptr %t9907)
  %t9909 = inttoptr i64 280 to ptr
  %t9910 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t9909, ptr %t9910
  %t9908 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t9889, ptr %t9908
  call void @__free_recursive(ptr %t9860)
  call void @__free_recursive(ptr %t9858)
  call void @__free_recursive(ptr %t9856)
  call void @__free_recursive(ptr %t9808)
  call void @__free_recursive(ptr %t9806)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.26.9911:
  %t9912 = call ptr @__alloc(i64 40, i32 4)
  %t9913 = inttoptr i64 92 to ptr
  %t9914 = getelementptr ptr, ptr %t9912, i32 0
  store ptr %t9913, ptr %t9914
  call void @__inc_ref(ptr %t9806)
  %t9915 = getelementptr ptr, ptr %t9912, i32 1
  store ptr %t9806, ptr %t9915
  call void @__inc_ref(ptr %t9856)
  %t9916 = getelementptr ptr, ptr %t9912, i32 2
  store ptr %t9856, ptr %t9916
  call void @__inc_ref(ptr %t9858)
  %t9917 = getelementptr ptr, ptr %t9912, i32 3
  store ptr %t9858, ptr %t9917
  %t9918 = call ptr @__alloc(i64 40, i32 4)
  %t9919 = inttoptr i64 27 to ptr
  %t9920 = getelementptr ptr, ptr %t9918, i32 0
  store ptr %t9919, ptr %t9920
  %t9921 = getelementptr ptr, ptr %t9860, i32 1
  %t9922 = load ptr, ptr %t9921
  call void @__inc_ref(ptr %t9922)
  %t9923 = getelementptr ptr, ptr %t9918, i32 1
  store ptr %t9922, ptr %t9923
  %t9924 = getelementptr ptr, ptr %t9860, i32 2
  %t9925 = load ptr, ptr %t9924
  call void @__inc_ref(ptr %t9925)
  %t9926 = getelementptr ptr, ptr %t9918, i32 2
  store ptr %t9925, ptr %t9926
  %t9927 = getelementptr ptr, ptr %t9860, i32 3
  %t9928 = load ptr, ptr %t9927
  call void @__inc_ref(ptr %t9928)
  %t9929 = getelementptr ptr, ptr %t9918, i32 3
  store ptr %t9928, ptr %t9929
  call void @__inc_ref(ptr %t9808)
  %t9930 = getelementptr ptr, ptr %t9918, i32 4
  store ptr %t9808, ptr %t9930
  %t9931 = getelementptr ptr, ptr %t9912, i32 4
  store ptr %t9918, ptr %t9931
  %t9932 = getelementptr ptr, ptr %t4, i32 1
  %t9933 = load ptr, ptr %t9932
  call void @__free_recursive(ptr %t9933)
  %t9935 = inttoptr i64 280 to ptr
  %t9936 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t9935, ptr %t9936
  %t9934 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t9912, ptr %t9934
  call void @__free_recursive(ptr %t9860)
  call void @__free_recursive(ptr %t9858)
  call void @__free_recursive(ptr %t9856)
  call void @__free_recursive(ptr %t9808)
  call void @__free_recursive(ptr %t9806)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.27.9937:
  %t9938 = call ptr @__alloc(i64 40, i32 4)
  %t9939 = inttoptr i64 105 to ptr
  %t9940 = getelementptr ptr, ptr %t9938, i32 0
  store ptr %t9939, ptr %t9940
  call void @__inc_ref(ptr %t9806)
  %t9941 = getelementptr ptr, ptr %t9938, i32 1
  store ptr %t9806, ptr %t9941
  %t9942 = getelementptr ptr, ptr %t9860, i32 1
  %t9943 = load ptr, ptr %t9942
  call void @__inc_ref(ptr %t9943)
  %t9944 = getelementptr ptr, ptr %t9938, i32 2
  store ptr %t9943, ptr %t9944
  %t9945 = getelementptr ptr, ptr %t9860, i32 2
  %t9946 = load ptr, ptr %t9945
  call void @__inc_ref(ptr %t9946)
  %t9947 = getelementptr ptr, ptr %t9938, i32 3
  store ptr %t9946, ptr %t9947
  %t9948 = getelementptr ptr, ptr %t9860, i32 3
  %t9949 = load ptr, ptr %t9948
  call void @__inc_ref(ptr %t9949)
  %t9950 = getelementptr ptr, ptr %t9938, i32 4
  store ptr %t9949, ptr %t9950
  %t9951 = call ptr @__alloc(i64 56, i32 6)
  %t9952 = inttoptr i64 268 to ptr
  %t9953 = getelementptr ptr, ptr %t9951, i32 0
  store ptr %t9952, ptr %t9953
  call void @__inc_ref(ptr %t5254)
  %t9954 = getelementptr ptr, ptr %t9951, i32 1
  store ptr %t5254, ptr %t9954
  %t9955 = getelementptr ptr, ptr %t9860, i32 4
  %t9956 = load ptr, ptr %t9955
  call void @__inc_ref(ptr %t9956)
  %t9957 = getelementptr ptr, ptr %t9951, i32 2
  store ptr %t9956, ptr %t9957
  call void @__inc_ref(ptr %t9806)
  %t9958 = getelementptr ptr, ptr %t9951, i32 3
  store ptr %t9806, ptr %t9958
  call void @__inc_ref(ptr %t9858)
  %t9959 = getelementptr ptr, ptr %t9951, i32 4
  store ptr %t9858, ptr %t9959
  call void @__inc_ref(ptr %t9856)
  %t9960 = getelementptr ptr, ptr %t9951, i32 5
  store ptr %t9856, ptr %t9960
  call void @__inc_ref(ptr %t9808)
  %t9961 = getelementptr ptr, ptr %t9951, i32 6
  store ptr %t9808, ptr %t9961
  %t9962 = getelementptr ptr, ptr %t4, i32 1
  %t9963 = load ptr, ptr %t9962
  call void @__free_recursive(ptr %t9963)
  %t9964 = getelementptr ptr, ptr %t4, i32 2
  %t9965 = load ptr, ptr %t9964
  call void @__free_recursive(ptr %t9965)
  %t9968 = inttoptr i64 280 to ptr
  %t9969 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t9968, ptr %t9969
  %t9966 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t9938, ptr %t9966
  %t9967 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t9951, ptr %t9967
  call void @__free_recursive(ptr %t9860)
  call void @__free_recursive(ptr %t9858)
  call void @__free_recursive(ptr %t9856)
  call void @__free_recursive(ptr %t9808)
  call void @__free_recursive(ptr %t9806)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.9864:
  unreachable
tco.case.default.9814:
  unreachable
tco.case.arm.115.9970:
  %t9971 = getelementptr ptr, ptr %t5252, i32 1
  %t9972 = load ptr, ptr %t9971
  call void @__inc_ref(ptr %t9972)
  %t9973 = getelementptr ptr, ptr %t5252, i32 2
  %t9974 = load ptr, ptr %t9973
  call void @__inc_ref(ptr %t9974)
  %t9975 = getelementptr ptr, ptr %t5252, i32 3
  %t9976 = load ptr, ptr %t9975
  call void @__inc_ref(ptr %t9976)
  %t9977 = getelementptr ptr, ptr %t9976, i32 0
  %t9978 = load ptr, ptr %t9977
  %t9979 = ptrtoint ptr %t9978 to i64
  switch i64 %t9979, label %tco.case.default.9980 [ i64 13, label %tco.case.arm.13.9981 i64 14, label %tco.case.arm.14.9990 ]
tco.case.arm.13.9981:
  call void @__free_recursive(ptr %t9976)
  %t9982 = getelementptr ptr, ptr %t4, i32 1
  %t9983 = load ptr, ptr %t9982
  call void @__free_recursive(ptr %t9983)
  %t9984 = getelementptr ptr, ptr %t4, i32 2
  %t9985 = load ptr, ptr %t9984
  call void @__free_recursive(ptr %t9985)
  %t9988 = inttoptr i64 279 to ptr
  %t9989 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t9988, ptr %t9989
  call void @__inc_ref(ptr %t5254)
  %t9986 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t9986
  call void @__inc_ref(ptr %t9974)
  %t9987 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t9974, ptr %t9987
  call void @__free_recursive(ptr %t9974)
  call void @__free_recursive(ptr %t9972)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.14.9990:
  %t9991 = getelementptr ptr, ptr %t9976, i32 1
  %t9992 = load ptr, ptr %t9991
  call void @__inc_ref(ptr %t9992)
  %t9993 = getelementptr ptr, ptr %t9976, i32 2
  %t9994 = load ptr, ptr %t9993
  call void @__inc_ref(ptr %t9994)
  call void @__free_recursive(ptr %t9976)
  %t9995 = call ptr @__alloc(i64 32, i32 3)
  %t9996 = inttoptr i64 114 to ptr
  %t9997 = getelementptr ptr, ptr %t9995, i32 0
  store ptr %t9996, ptr %t9997
  call void @__inc_ref(ptr %t9972)
  %t9998 = getelementptr ptr, ptr %t9995, i32 1
  store ptr %t9972, ptr %t9998
  call void @__inc_ref(ptr %t9974)
  %t9999 = getelementptr ptr, ptr %t9995, i32 2
  store ptr %t9974, ptr %t9999
  call void @__inc_ref(ptr %t9992)
  %t10000 = getelementptr ptr, ptr %t9995, i32 3
  store ptr %t9992, ptr %t10000
  %t10001 = call ptr @__alloc(i64 32, i32 3)
  %t10002 = inttoptr i64 270 to ptr
  %t10003 = getelementptr ptr, ptr %t10001, i32 0
  store ptr %t10002, ptr %t10003
  call void @__inc_ref(ptr %t5254)
  %t10004 = getelementptr ptr, ptr %t10001, i32 1
  store ptr %t5254, ptr %t10004
  call void @__inc_ref(ptr %t9972)
  %t10005 = getelementptr ptr, ptr %t10001, i32 2
  store ptr %t9972, ptr %t10005
  call void @__inc_ref(ptr %t9994)
  %t10006 = getelementptr ptr, ptr %t10001, i32 3
  store ptr %t9994, ptr %t10006
  %t10007 = getelementptr ptr, ptr %t4, i32 1
  %t10008 = load ptr, ptr %t10007
  call void @__free_recursive(ptr %t10008)
  %t10009 = getelementptr ptr, ptr %t4, i32 2
  %t10010 = load ptr, ptr %t10009
  call void @__free_recursive(ptr %t10010)
  %t10013 = inttoptr i64 280 to ptr
  %t10014 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t10013, ptr %t10014
  %t10011 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t9995, ptr %t10011
  %t10012 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t10001, ptr %t10012
  call void @__free_recursive(ptr %t9994)
  call void @__free_recursive(ptr %t9992)
  call void @__free_recursive(ptr %t9974)
  call void @__free_recursive(ptr %t9972)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.9980:
  unreachable
tco.case.arm.116.10015:
  %t10016 = getelementptr ptr, ptr %t5252, i32 1
  %t10017 = load ptr, ptr %t10016
  call void @__inc_ref(ptr %t10017)
  %t10018 = getelementptr ptr, ptr %t5252, i32 2
  %t10019 = load ptr, ptr %t10018
  call void @__inc_ref(ptr %t10019)
  %t10020 = getelementptr ptr, ptr %t10019, i32 0
  %t10021 = load ptr, ptr %t10020
  %t10022 = ptrtoint ptr %t10021 to i64
  switch i64 %t10022, label %tco.case.default.10023 [ i64 30, label %tco.case.arm.30.10024 i64 31, label %tco.case.arm.31.10036 i64 32, label %tco.case.arm.32.10059 ]
tco.case.arm.30.10024:
  call void @__free_recursive(ptr %t10019)
  %t10025 = call ptr @__alloc(i64 8, i32 0)
  %t10026 = inttoptr i64 11 to ptr
  %t10027 = getelementptr ptr, ptr %t10025, i32 0
  store ptr %t10026, ptr %t10027
  %t10028 = getelementptr ptr, ptr %t4, i32 1
  %t10029 = load ptr, ptr %t10028
  call void @__free_recursive(ptr %t10029)
  %t10030 = getelementptr ptr, ptr %t4, i32 2
  %t10031 = load ptr, ptr %t10030
  call void @__free_recursive(ptr %t10031)
  %t10034 = inttoptr i64 279 to ptr
  %t10035 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t10034, ptr %t10035
  call void @__inc_ref(ptr %t5254)
  %t10032 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t10032
  %t10033 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t10025, ptr %t10033
  call void @__free_recursive(ptr %t10017)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.31.10036:
  %t10037 = getelementptr ptr, ptr %t10019, i32 1
  %t10038 = load ptr, ptr %t10037
  call void @__inc_ref(ptr %t10038)
  call void @__free_recursive(ptr %t10019)
  %t10039 = call ptr @__alloc(i64 24, i32 2)
  %t10040 = inttoptr i64 279 to ptr
  %t10041 = getelementptr ptr, ptr %t10039, i32 0
  store ptr %t10040, ptr %t10041
  call void @__inc_ref(ptr %t5254)
  %t10042 = getelementptr ptr, ptr %t10039, i32 1
  store ptr %t5254, ptr %t10042
  %t10043 = call ptr @__alloc(i64 16, i32 1)
  %t10044 = inttoptr i64 12 to ptr
  %t10045 = getelementptr ptr, ptr %t10043, i32 0
  store ptr %t10044, ptr %t10045
  %t10046 = call ptr @__alloc(i64 8, i32 0)
  %t10047 = inttoptr i64 30 to ptr
  %t10048 = getelementptr ptr, ptr %t10046, i32 0
  store ptr %t10047, ptr %t10048
  %t10049 = getelementptr ptr, ptr %t4, i32 1
  %t10050 = load ptr, ptr %t10049
  call void @__free_recursive(ptr %t10050)
  %t10051 = getelementptr ptr, ptr %t4, i32 2
  %t10052 = load ptr, ptr %t10051
  call void @__free_recursive(ptr %t10052)
  %t10055 = inttoptr i64 15 to ptr
  %t10056 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t10055, ptr %t10056
  %t10053 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t10046, ptr %t10053
  call void @__inc_ref(ptr %t10038)
  %t10054 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t10038, ptr %t10054
  %t10057 = getelementptr ptr, ptr %t10043, i32 1
  store ptr %t4, ptr %t10057
  %t10058 = getelementptr ptr, ptr %t10039, i32 2
  store ptr %t10043, ptr %t10058
  call void @__free_recursive(ptr %t10038)
  call void @__free_recursive(ptr %t10017)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t10039, ptr %t3
  br label %tco.loop.0
tco.case.arm.32.10059:
  %t10060 = getelementptr ptr, ptr %t10019, i32 2
  %t10061 = load ptr, ptr %t10060
  call void @__inc_ref(ptr %t10061)
  %t10062 = getelementptr ptr, ptr %t10019, i32 3
  %t10063 = load ptr, ptr %t10062
  call void @__inc_ref(ptr %t10063)
  %t10064 = getelementptr ptr, ptr %t10019, i32 4
  %t10065 = load ptr, ptr %t10064
  call void @__inc_ref(ptr %t10065)
  call void @__free_recursive(ptr %t10019)
  %t10066 = getelementptr ptr, ptr %t10065, i32 0
  %t10067 = load ptr, ptr %t10066
  %t10068 = ptrtoint ptr %t10067 to i64
  switch i64 %t10068, label %tco.case.default.10069 [ i64 24, label %tco.case.arm.24.10070 i64 25, label %tco.case.arm.25.10096 i64 26, label %tco.case.arm.26.10125 i64 27, label %tco.case.arm.27.10157 ]
tco.case.arm.24.10070:
  %t10071 = call ptr @__alloc(i64 24, i32 2)
  %t10072 = inttoptr i64 280 to ptr
  %t10073 = getelementptr ptr, ptr %t10071, i32 0
  store ptr %t10072, ptr %t10073
  %t10074 = call ptr @__alloc(i64 40, i32 4)
  %t10075 = inttoptr i64 94 to ptr
  %t10076 = getelementptr ptr, ptr %t10074, i32 0
  store ptr %t10075, ptr %t10076
  call void @__inc_ref(ptr %t10017)
  %t10077 = getelementptr ptr, ptr %t10074, i32 1
  store ptr %t10017, ptr %t10077
  call void @__inc_ref(ptr %t10061)
  %t10078 = getelementptr ptr, ptr %t10074, i32 2
  store ptr %t10061, ptr %t10078
  call void @__inc_ref(ptr %t10063)
  %t10079 = getelementptr ptr, ptr %t10074, i32 3
  store ptr %t10063, ptr %t10079
  %t10080 = call ptr @__alloc(i64 8, i32 0)
  %t10081 = inttoptr i64 11 to ptr
  %t10082 = getelementptr ptr, ptr %t10080, i32 0
  store ptr %t10081, ptr %t10082
  %t10083 = getelementptr ptr, ptr %t10074, i32 4
  store ptr %t10080, ptr %t10083
  %t10084 = getelementptr ptr, ptr %t10071, i32 1
  store ptr %t10074, ptr %t10084
  %t10085 = getelementptr ptr, ptr %t10065, i32 1
  %t10086 = load ptr, ptr %t10085
  call void @__inc_ref(ptr %t10086)
  %t10087 = getelementptr ptr, ptr %t4, i32 1
  %t10088 = load ptr, ptr %t10087
  call void @__free_recursive(ptr %t10088)
  %t10089 = getelementptr ptr, ptr %t4, i32 2
  %t10090 = load ptr, ptr %t10089
  call void @__free_recursive(ptr %t10090)
  %t10093 = inttoptr i64 271 to ptr
  %t10094 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t10093, ptr %t10094
  call void @__inc_ref(ptr %t5254)
  %t10091 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t10091
  %t10092 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t10086, ptr %t10092
  %t10095 = getelementptr ptr, ptr %t10071, i32 2
  store ptr %t4, ptr %t10095
  call void @__free_recursive(ptr %t10065)
  call void @__free_recursive(ptr %t10063)
  call void @__free_recursive(ptr %t10061)
  call void @__free_recursive(ptr %t10017)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t10071, ptr %t3
  br label %tco.loop.0
tco.case.arm.25.10096:
  %t10097 = call ptr @__alloc(i64 24, i32 2)
  %t10098 = inttoptr i64 280 to ptr
  %t10099 = getelementptr ptr, ptr %t10097, i32 0
  store ptr %t10098, ptr %t10099
  %t10100 = call ptr @__alloc(i64 40, i32 4)
  %t10101 = inttoptr i64 92 to ptr
  %t10102 = getelementptr ptr, ptr %t10100, i32 0
  store ptr %t10101, ptr %t10102
  call void @__inc_ref(ptr %t10017)
  %t10103 = getelementptr ptr, ptr %t10100, i32 1
  store ptr %t10017, ptr %t10103
  call void @__inc_ref(ptr %t10061)
  %t10104 = getelementptr ptr, ptr %t10100, i32 2
  store ptr %t10061, ptr %t10104
  call void @__inc_ref(ptr %t10063)
  %t10105 = getelementptr ptr, ptr %t10100, i32 3
  store ptr %t10063, ptr %t10105
  %t10106 = call ptr @__alloc(i64 16, i32 1)
  %t10107 = inttoptr i64 24 to ptr
  %t10108 = getelementptr ptr, ptr %t10106, i32 0
  store ptr %t10107, ptr %t10108
  %t10109 = getelementptr ptr, ptr %t10065, i32 1
  %t10110 = load ptr, ptr %t10109
  call void @__inc_ref(ptr %t10110)
  %t10111 = getelementptr ptr, ptr %t10106, i32 1
  store ptr %t10110, ptr %t10111
  %t10112 = getelementptr ptr, ptr %t10100, i32 4
  store ptr %t10106, ptr %t10112
  %t10113 = getelementptr ptr, ptr %t10097, i32 1
  store ptr %t10100, ptr %t10113
  %t10114 = getelementptr ptr, ptr %t10065, i32 2
  %t10115 = load ptr, ptr %t10114
  call void @__inc_ref(ptr %t10115)
  %t10116 = getelementptr ptr, ptr %t4, i32 1
  %t10117 = load ptr, ptr %t10116
  call void @__free_recursive(ptr %t10117)
  %t10118 = getelementptr ptr, ptr %t4, i32 2
  %t10119 = load ptr, ptr %t10118
  call void @__free_recursive(ptr %t10119)
  %t10122 = inttoptr i64 272 to ptr
  %t10123 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t10122, ptr %t10123
  call void @__inc_ref(ptr %t5254)
  %t10120 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t10120
  %t10121 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t10115, ptr %t10121
  %t10124 = getelementptr ptr, ptr %t10097, i32 2
  store ptr %t4, ptr %t10124
  call void @__free_recursive(ptr %t10065)
  call void @__free_recursive(ptr %t10063)
  call void @__free_recursive(ptr %t10061)
  call void @__free_recursive(ptr %t10017)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t10097, ptr %t3
  br label %tco.loop.0
tco.case.arm.26.10125:
  %t10126 = call ptr @__alloc(i64 24, i32 2)
  %t10127 = inttoptr i64 280 to ptr
  %t10128 = getelementptr ptr, ptr %t10126, i32 0
  store ptr %t10127, ptr %t10128
  %t10129 = call ptr @__alloc(i64 40, i32 4)
  %t10130 = inttoptr i64 92 to ptr
  %t10131 = getelementptr ptr, ptr %t10129, i32 0
  store ptr %t10130, ptr %t10131
  call void @__inc_ref(ptr %t10017)
  %t10132 = getelementptr ptr, ptr %t10129, i32 1
  store ptr %t10017, ptr %t10132
  call void @__inc_ref(ptr %t10061)
  %t10133 = getelementptr ptr, ptr %t10129, i32 2
  store ptr %t10061, ptr %t10133
  call void @__inc_ref(ptr %t10063)
  %t10134 = getelementptr ptr, ptr %t10129, i32 3
  store ptr %t10063, ptr %t10134
  %t10135 = getelementptr ptr, ptr %t10065, i32 1
  %t10136 = load ptr, ptr %t10135
  call void @__inc_ref(ptr %t10136)
  %t10137 = getelementptr ptr, ptr %t10065, i32 2
  %t10138 = load ptr, ptr %t10137
  call void @__inc_ref(ptr %t10138)
  %t10139 = getelementptr ptr, ptr %t4, i32 1
  %t10140 = load ptr, ptr %t10139
  call void @__free_recursive(ptr %t10140)
  %t10141 = getelementptr ptr, ptr %t4, i32 2
  %t10142 = load ptr, ptr %t10141
  call void @__free_recursive(ptr %t10142)
  %t10145 = inttoptr i64 25 to ptr
  %t10146 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t10145, ptr %t10146
  %t10143 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t10136, ptr %t10143
  %t10144 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t10138, ptr %t10144
  %t10147 = getelementptr ptr, ptr %t10129, i32 4
  store ptr %t4, ptr %t10147
  %t10148 = getelementptr ptr, ptr %t10126, i32 1
  store ptr %t10129, ptr %t10148
  %t10149 = call ptr @__alloc(i64 24, i32 2)
  %t10150 = inttoptr i64 273 to ptr
  %t10151 = getelementptr ptr, ptr %t10149, i32 0
  store ptr %t10150, ptr %t10151
  call void @__inc_ref(ptr %t5254)
  %t10152 = getelementptr ptr, ptr %t10149, i32 1
  store ptr %t5254, ptr %t10152
  %t10153 = getelementptr ptr, ptr %t10065, i32 3
  %t10154 = load ptr, ptr %t10153
  call void @__inc_ref(ptr %t10154)
  %t10155 = getelementptr ptr, ptr %t10149, i32 2
  store ptr %t10154, ptr %t10155
  %t10156 = getelementptr ptr, ptr %t10126, i32 2
  store ptr %t10149, ptr %t10156
  call void @__free_recursive(ptr %t10065)
  call void @__free_recursive(ptr %t10063)
  call void @__free_recursive(ptr %t10061)
  call void @__free_recursive(ptr %t10017)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t10126, ptr %t3
  br label %tco.loop.0
tco.case.arm.27.10157:
  %t10158 = call ptr @__alloc(i64 24, i32 2)
  %t10159 = inttoptr i64 280 to ptr
  %t10160 = getelementptr ptr, ptr %t10158, i32 0
  store ptr %t10159, ptr %t10160
  %t10161 = call ptr @__alloc(i64 40, i32 4)
  %t10162 = inttoptr i64 92 to ptr
  %t10163 = getelementptr ptr, ptr %t10161, i32 0
  store ptr %t10162, ptr %t10163
  call void @__inc_ref(ptr %t10017)
  %t10164 = getelementptr ptr, ptr %t10161, i32 1
  store ptr %t10017, ptr %t10164
  call void @__inc_ref(ptr %t10061)
  %t10165 = getelementptr ptr, ptr %t10161, i32 2
  store ptr %t10061, ptr %t10165
  call void @__inc_ref(ptr %t10063)
  %t10166 = getelementptr ptr, ptr %t10161, i32 3
  store ptr %t10063, ptr %t10166
  %t10167 = call ptr @__alloc(i64 32, i32 3)
  %t10168 = inttoptr i64 26 to ptr
  %t10169 = getelementptr ptr, ptr %t10167, i32 0
  store ptr %t10168, ptr %t10169
  %t10170 = getelementptr ptr, ptr %t10065, i32 1
  %t10171 = load ptr, ptr %t10170
  call void @__inc_ref(ptr %t10171)
  %t10172 = getelementptr ptr, ptr %t10167, i32 1
  store ptr %t10171, ptr %t10172
  %t10173 = getelementptr ptr, ptr %t10065, i32 2
  %t10174 = load ptr, ptr %t10173
  call void @__inc_ref(ptr %t10174)
  %t10175 = getelementptr ptr, ptr %t10167, i32 2
  store ptr %t10174, ptr %t10175
  %t10176 = getelementptr ptr, ptr %t10065, i32 3
  %t10177 = load ptr, ptr %t10176
  call void @__inc_ref(ptr %t10177)
  %t10178 = getelementptr ptr, ptr %t10167, i32 3
  store ptr %t10177, ptr %t10178
  %t10179 = getelementptr ptr, ptr %t10161, i32 4
  store ptr %t10167, ptr %t10179
  %t10180 = getelementptr ptr, ptr %t10158, i32 1
  store ptr %t10161, ptr %t10180
  %t10181 = getelementptr ptr, ptr %t10065, i32 4
  %t10182 = load ptr, ptr %t10181
  call void @__inc_ref(ptr %t10182)
  %t10183 = getelementptr ptr, ptr %t4, i32 1
  %t10184 = load ptr, ptr %t10183
  call void @__free_recursive(ptr %t10184)
  %t10185 = getelementptr ptr, ptr %t4, i32 2
  %t10186 = load ptr, ptr %t10185
  call void @__free_recursive(ptr %t10186)
  %t10189 = inttoptr i64 274 to ptr
  %t10190 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t10189, ptr %t10190
  call void @__inc_ref(ptr %t5254)
  %t10187 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t10187
  %t10188 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t10182, ptr %t10188
  %t10191 = getelementptr ptr, ptr %t10158, i32 2
  store ptr %t4, ptr %t10191
  call void @__free_recursive(ptr %t10065)
  call void @__free_recursive(ptr %t10063)
  call void @__free_recursive(ptr %t10061)
  call void @__free_recursive(ptr %t10017)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t10158, ptr %t3
  br label %tco.loop.0
tco.case.default.10069:
  unreachable
tco.case.default.10023:
  unreachable
tco.case.arm.117.10192:
  %t10193 = getelementptr ptr, ptr %t5252, i32 1
  %t10194 = load ptr, ptr %t10193
  call void @__inc_ref(ptr %t10194)
  %t10195 = getelementptr ptr, ptr %t5252, i32 2
  %t10196 = load ptr, ptr %t10195
  call void @__inc_ref(ptr %t10196)
  %t10197 = getelementptr ptr, ptr %t10196, i32 0
  %t10198 = load ptr, ptr %t10197
  %t10199 = ptrtoint ptr %t10198 to i64
  switch i64 %t10199, label %tco.case.default.10200 [ i64 30, label %tco.case.arm.30.10201 i64 31, label %tco.case.arm.31.10213 i64 32, label %tco.case.arm.32.10236 ]
tco.case.arm.30.10201:
  call void @__free_recursive(ptr %t10196)
  %t10202 = call ptr @__alloc(i64 8, i32 0)
  %t10203 = inttoptr i64 11 to ptr
  %t10204 = getelementptr ptr, ptr %t10202, i32 0
  store ptr %t10203, ptr %t10204
  %t10205 = getelementptr ptr, ptr %t4, i32 1
  %t10206 = load ptr, ptr %t10205
  call void @__free_recursive(ptr %t10206)
  %t10207 = getelementptr ptr, ptr %t4, i32 2
  %t10208 = load ptr, ptr %t10207
  call void @__free_recursive(ptr %t10208)
  %t10211 = inttoptr i64 279 to ptr
  %t10212 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t10211, ptr %t10212
  call void @__inc_ref(ptr %t5254)
  %t10209 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t10209
  %t10210 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t10202, ptr %t10210
  call void @__free_recursive(ptr %t10194)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.31.10213:
  %t10214 = getelementptr ptr, ptr %t10196, i32 1
  %t10215 = load ptr, ptr %t10214
  call void @__inc_ref(ptr %t10215)
  call void @__free_recursive(ptr %t10196)
  %t10216 = call ptr @__alloc(i64 24, i32 2)
  %t10217 = inttoptr i64 279 to ptr
  %t10218 = getelementptr ptr, ptr %t10216, i32 0
  store ptr %t10217, ptr %t10218
  call void @__inc_ref(ptr %t5254)
  %t10219 = getelementptr ptr, ptr %t10216, i32 1
  store ptr %t5254, ptr %t10219
  %t10220 = call ptr @__alloc(i64 16, i32 1)
  %t10221 = inttoptr i64 12 to ptr
  %t10222 = getelementptr ptr, ptr %t10220, i32 0
  store ptr %t10221, ptr %t10222
  %t10223 = call ptr @__alloc(i64 8, i32 0)
  %t10224 = inttoptr i64 30 to ptr
  %t10225 = getelementptr ptr, ptr %t10223, i32 0
  store ptr %t10224, ptr %t10225
  %t10226 = getelementptr ptr, ptr %t4, i32 1
  %t10227 = load ptr, ptr %t10226
  call void @__free_recursive(ptr %t10227)
  %t10228 = getelementptr ptr, ptr %t4, i32 2
  %t10229 = load ptr, ptr %t10228
  call void @__free_recursive(ptr %t10229)
  %t10232 = inttoptr i64 15 to ptr
  %t10233 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t10232, ptr %t10233
  call void @__inc_ref(ptr %t10215)
  %t10230 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t10215, ptr %t10230
  %t10231 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t10223, ptr %t10231
  %t10234 = getelementptr ptr, ptr %t10220, i32 1
  store ptr %t4, ptr %t10234
  %t10235 = getelementptr ptr, ptr %t10216, i32 2
  store ptr %t10220, ptr %t10235
  call void @__free_recursive(ptr %t10215)
  call void @__free_recursive(ptr %t10194)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t10216, ptr %t3
  br label %tco.loop.0
tco.case.arm.32.10236:
  %t10237 = getelementptr ptr, ptr %t10196, i32 2
  %t10238 = load ptr, ptr %t10237
  call void @__inc_ref(ptr %t10238)
  %t10239 = getelementptr ptr, ptr %t10196, i32 3
  %t10240 = load ptr, ptr %t10239
  call void @__inc_ref(ptr %t10240)
  %t10241 = getelementptr ptr, ptr %t10196, i32 4
  %t10242 = load ptr, ptr %t10241
  call void @__inc_ref(ptr %t10242)
  call void @__free_recursive(ptr %t10196)
  %t10243 = getelementptr ptr, ptr %t10238, i32 0
  %t10244 = load ptr, ptr %t10243
  %t10245 = ptrtoint ptr %t10244 to i64
  switch i64 %t10245, label %tco.case.default.10246 [ i64 24, label %tco.case.arm.24.10247 i64 25, label %tco.case.arm.25.10273 i64 26, label %tco.case.arm.26.10302 i64 27, label %tco.case.arm.27.10334 ]
tco.case.arm.24.10247:
  %t10248 = call ptr @__alloc(i64 24, i32 2)
  %t10249 = inttoptr i64 280 to ptr
  %t10250 = getelementptr ptr, ptr %t10248, i32 0
  store ptr %t10249, ptr %t10250
  %t10251 = call ptr @__alloc(i64 40, i32 4)
  %t10252 = inttoptr i64 93 to ptr
  %t10253 = getelementptr ptr, ptr %t10251, i32 0
  store ptr %t10252, ptr %t10253
  call void @__inc_ref(ptr %t10194)
  %t10254 = getelementptr ptr, ptr %t10251, i32 1
  store ptr %t10194, ptr %t10254
  %t10255 = call ptr @__alloc(i64 8, i32 0)
  %t10256 = inttoptr i64 11 to ptr
  %t10257 = getelementptr ptr, ptr %t10255, i32 0
  store ptr %t10256, ptr %t10257
  %t10258 = getelementptr ptr, ptr %t10251, i32 2
  store ptr %t10255, ptr %t10258
  call void @__inc_ref(ptr %t10240)
  %t10259 = getelementptr ptr, ptr %t10251, i32 3
  store ptr %t10240, ptr %t10259
  call void @__inc_ref(ptr %t10242)
  %t10260 = getelementptr ptr, ptr %t10251, i32 4
  store ptr %t10242, ptr %t10260
  %t10261 = getelementptr ptr, ptr %t10248, i32 1
  store ptr %t10251, ptr %t10261
  %t10262 = getelementptr ptr, ptr %t10238, i32 1
  %t10263 = load ptr, ptr %t10262
  call void @__inc_ref(ptr %t10263)
  %t10264 = getelementptr ptr, ptr %t4, i32 1
  %t10265 = load ptr, ptr %t10264
  call void @__free_recursive(ptr %t10265)
  %t10266 = getelementptr ptr, ptr %t4, i32 2
  %t10267 = load ptr, ptr %t10266
  call void @__free_recursive(ptr %t10267)
  %t10270 = inttoptr i64 275 to ptr
  %t10271 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t10270, ptr %t10271
  call void @__inc_ref(ptr %t5254)
  %t10268 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t10268
  %t10269 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t10263, ptr %t10269
  %t10272 = getelementptr ptr, ptr %t10248, i32 2
  store ptr %t4, ptr %t10272
  call void @__free_recursive(ptr %t10242)
  call void @__free_recursive(ptr %t10240)
  call void @__free_recursive(ptr %t10238)
  call void @__free_recursive(ptr %t10194)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t10248, ptr %t3
  br label %tco.loop.0
tco.case.arm.25.10273:
  %t10274 = call ptr @__alloc(i64 24, i32 2)
  %t10275 = inttoptr i64 280 to ptr
  %t10276 = getelementptr ptr, ptr %t10274, i32 0
  store ptr %t10275, ptr %t10276
  %t10277 = call ptr @__alloc(i64 40, i32 4)
  %t10278 = inttoptr i64 92 to ptr
  %t10279 = getelementptr ptr, ptr %t10277, i32 0
  store ptr %t10278, ptr %t10279
  call void @__inc_ref(ptr %t10194)
  %t10280 = getelementptr ptr, ptr %t10277, i32 1
  store ptr %t10194, ptr %t10280
  %t10281 = call ptr @__alloc(i64 16, i32 1)
  %t10282 = inttoptr i64 24 to ptr
  %t10283 = getelementptr ptr, ptr %t10281, i32 0
  store ptr %t10282, ptr %t10283
  %t10284 = getelementptr ptr, ptr %t10238, i32 2
  %t10285 = load ptr, ptr %t10284
  call void @__inc_ref(ptr %t10285)
  %t10286 = getelementptr ptr, ptr %t10281, i32 1
  store ptr %t10285, ptr %t10286
  %t10287 = getelementptr ptr, ptr %t10277, i32 2
  store ptr %t10281, ptr %t10287
  call void @__inc_ref(ptr %t10240)
  %t10288 = getelementptr ptr, ptr %t10277, i32 3
  store ptr %t10240, ptr %t10288
  call void @__inc_ref(ptr %t10242)
  %t10289 = getelementptr ptr, ptr %t10277, i32 4
  store ptr %t10242, ptr %t10289
  %t10290 = getelementptr ptr, ptr %t10274, i32 1
  store ptr %t10277, ptr %t10290
  %t10291 = getelementptr ptr, ptr %t10238, i32 1
  %t10292 = load ptr, ptr %t10291
  call void @__inc_ref(ptr %t10292)
  %t10293 = getelementptr ptr, ptr %t4, i32 1
  %t10294 = load ptr, ptr %t10293
  call void @__free_recursive(ptr %t10294)
  %t10295 = getelementptr ptr, ptr %t4, i32 2
  %t10296 = load ptr, ptr %t10295
  call void @__free_recursive(ptr %t10296)
  %t10299 = inttoptr i64 276 to ptr
  %t10300 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t10299, ptr %t10300
  call void @__inc_ref(ptr %t5254)
  %t10297 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t10297
  %t10298 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t10292, ptr %t10298
  %t10301 = getelementptr ptr, ptr %t10274, i32 2
  store ptr %t4, ptr %t10301
  call void @__free_recursive(ptr %t10242)
  call void @__free_recursive(ptr %t10240)
  call void @__free_recursive(ptr %t10238)
  call void @__free_recursive(ptr %t10194)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t10274, ptr %t3
  br label %tco.loop.0
tco.case.arm.26.10302:
  %t10303 = call ptr @__alloc(i64 24, i32 2)
  %t10304 = inttoptr i64 280 to ptr
  %t10305 = getelementptr ptr, ptr %t10303, i32 0
  store ptr %t10304, ptr %t10305
  %t10306 = call ptr @__alloc(i64 40, i32 4)
  %t10307 = inttoptr i64 92 to ptr
  %t10308 = getelementptr ptr, ptr %t10306, i32 0
  store ptr %t10307, ptr %t10308
  call void @__inc_ref(ptr %t10194)
  %t10309 = getelementptr ptr, ptr %t10306, i32 1
  store ptr %t10194, ptr %t10309
  %t10310 = getelementptr ptr, ptr %t10238, i32 2
  %t10311 = load ptr, ptr %t10310
  call void @__inc_ref(ptr %t10311)
  %t10312 = getelementptr ptr, ptr %t10238, i32 3
  %t10313 = load ptr, ptr %t10312
  call void @__inc_ref(ptr %t10313)
  %t10314 = getelementptr ptr, ptr %t4, i32 1
  %t10315 = load ptr, ptr %t10314
  call void @__free_recursive(ptr %t10315)
  %t10316 = getelementptr ptr, ptr %t4, i32 2
  %t10317 = load ptr, ptr %t10316
  call void @__free_recursive(ptr %t10317)
  %t10320 = inttoptr i64 25 to ptr
  %t10321 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t10320, ptr %t10321
  %t10318 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t10311, ptr %t10318
  %t10319 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t10313, ptr %t10319
  %t10322 = getelementptr ptr, ptr %t10306, i32 2
  store ptr %t4, ptr %t10322
  call void @__inc_ref(ptr %t10240)
  %t10323 = getelementptr ptr, ptr %t10306, i32 3
  store ptr %t10240, ptr %t10323
  call void @__inc_ref(ptr %t10242)
  %t10324 = getelementptr ptr, ptr %t10306, i32 4
  store ptr %t10242, ptr %t10324
  %t10325 = getelementptr ptr, ptr %t10303, i32 1
  store ptr %t10306, ptr %t10325
  %t10326 = call ptr @__alloc(i64 24, i32 2)
  %t10327 = inttoptr i64 277 to ptr
  %t10328 = getelementptr ptr, ptr %t10326, i32 0
  store ptr %t10327, ptr %t10328
  call void @__inc_ref(ptr %t5254)
  %t10329 = getelementptr ptr, ptr %t10326, i32 1
  store ptr %t5254, ptr %t10329
  %t10330 = getelementptr ptr, ptr %t10238, i32 1
  %t10331 = load ptr, ptr %t10330
  call void @__inc_ref(ptr %t10331)
  %t10332 = getelementptr ptr, ptr %t10326, i32 2
  store ptr %t10331, ptr %t10332
  %t10333 = getelementptr ptr, ptr %t10303, i32 2
  store ptr %t10326, ptr %t10333
  call void @__free_recursive(ptr %t10242)
  call void @__free_recursive(ptr %t10240)
  call void @__free_recursive(ptr %t10238)
  call void @__free_recursive(ptr %t10194)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t10303, ptr %t3
  br label %tco.loop.0
tco.case.arm.27.10334:
  %t10335 = call ptr @__alloc(i64 24, i32 2)
  %t10336 = inttoptr i64 280 to ptr
  %t10337 = getelementptr ptr, ptr %t10335, i32 0
  store ptr %t10336, ptr %t10337
  %t10338 = call ptr @__alloc(i64 40, i32 4)
  %t10339 = inttoptr i64 92 to ptr
  %t10340 = getelementptr ptr, ptr %t10338, i32 0
  store ptr %t10339, ptr %t10340
  call void @__inc_ref(ptr %t10194)
  %t10341 = getelementptr ptr, ptr %t10338, i32 1
  store ptr %t10194, ptr %t10341
  %t10342 = call ptr @__alloc(i64 32, i32 3)
  %t10343 = inttoptr i64 26 to ptr
  %t10344 = getelementptr ptr, ptr %t10342, i32 0
  store ptr %t10343, ptr %t10344
  %t10345 = getelementptr ptr, ptr %t10238, i32 2
  %t10346 = load ptr, ptr %t10345
  call void @__inc_ref(ptr %t10346)
  %t10347 = getelementptr ptr, ptr %t10342, i32 1
  store ptr %t10346, ptr %t10347
  %t10348 = getelementptr ptr, ptr %t10238, i32 3
  %t10349 = load ptr, ptr %t10348
  call void @__inc_ref(ptr %t10349)
  %t10350 = getelementptr ptr, ptr %t10342, i32 2
  store ptr %t10349, ptr %t10350
  %t10351 = getelementptr ptr, ptr %t10238, i32 4
  %t10352 = load ptr, ptr %t10351
  call void @__inc_ref(ptr %t10352)
  %t10353 = getelementptr ptr, ptr %t10342, i32 3
  store ptr %t10352, ptr %t10353
  %t10354 = getelementptr ptr, ptr %t10338, i32 2
  store ptr %t10342, ptr %t10354
  call void @__inc_ref(ptr %t10240)
  %t10355 = getelementptr ptr, ptr %t10338, i32 3
  store ptr %t10240, ptr %t10355
  call void @__inc_ref(ptr %t10242)
  %t10356 = getelementptr ptr, ptr %t10338, i32 4
  store ptr %t10242, ptr %t10356
  %t10357 = getelementptr ptr, ptr %t10335, i32 1
  store ptr %t10338, ptr %t10357
  %t10358 = getelementptr ptr, ptr %t10238, i32 1
  %t10359 = load ptr, ptr %t10358
  call void @__inc_ref(ptr %t10359)
  %t10360 = getelementptr ptr, ptr %t4, i32 1
  %t10361 = load ptr, ptr %t10360
  call void @__free_recursive(ptr %t10361)
  %t10362 = getelementptr ptr, ptr %t4, i32 2
  %t10363 = load ptr, ptr %t10362
  call void @__free_recursive(ptr %t10363)
  %t10366 = inttoptr i64 278 to ptr
  %t10367 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t10366, ptr %t10367
  call void @__inc_ref(ptr %t5254)
  %t10364 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t5254, ptr %t10364
  %t10365 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t10359, ptr %t10365
  %t10368 = getelementptr ptr, ptr %t10335, i32 2
  store ptr %t4, ptr %t10368
  call void @__free_recursive(ptr %t10242)
  call void @__free_recursive(ptr %t10240)
  call void @__free_recursive(ptr %t10238)
  call void @__free_recursive(ptr %t10194)
  call void @__free_recursive(ptr %t5254)
  call void @__free_recursive(ptr %t5252)
  store ptr %t10335, ptr %t3
  br label %tco.loop.0
tco.case.default.10246:
  unreachable
tco.case.default.10200:
  unreachable
tco.case.default.5258:
  unreachable
tco.case.default.8:
  unreachable
tco.exit.1:
  %t10369 = load ptr, ptr %t2
  ret ptr %t10369
}

define i32 @main(i32 %argc, ptr %argv) {
  %argc64 = sext i32 %argc to i64
  store i64 %argc64, ptr @.cli_argc
  store ptr %argv, ptr @.cli_argv
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
