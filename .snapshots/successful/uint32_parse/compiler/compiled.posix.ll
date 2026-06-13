; External C declarations
declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare ptr @memcpy(ptr, ptr, i64)
declare i64 @write(i32, ptr, i64)
declare i32 @snprintf(ptr, i64, ptr, ...)

@.fmt_u8 = private unnamed_addr constant [3 x i8] c"%u\00"

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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"0" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"err" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"ok:" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [10 x i8]} { i32 0, i32 0, i32 0, i32 10, i32 10, [10 x i8] c"4294967295" }
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [10 x i8]} { i32 0, i32 0, i32 0, i32 10, i32 10, [10 x i8] c"4294967296" }
@.str.6 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"-1" }
@.str.7 = private unnamed_addr constant {i32, i32, i32, i32, i32, [0 x i8]} { i32 0, i32 0, i32 0, i32 0, i32 0, [0 x i8] zeroinitializer }
@.str.8 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"abc" }
@.str.9 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c" 5" }
@.str.10 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"12a" }
@.str.11 = private unnamed_addr constant {i32, i32, i32, i32, i32, [10 x i8]} { i32 0, i32 0, i32 0, i32 10, i32 10, [10 x i8] c"2147483648" }
@.str.12 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c", " }

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
  %v__inl31_scrut.jslot = alloca ptr
  %t0 = call ptr @__parseUInt32(ptr getelementptr inbounds (i8, ptr @.str.0, i64 12))
  %t3 = getelementptr ptr, ptr %t0, i32 0
  %t4 = load ptr, ptr %t3
  %t5 = ptrtoint ptr %t4 to i64
  switch i64 %t5, label %case.default.6 [ i64 3, label %case.arm.3.8 i64 4, label %case.arm.4.14 ]
case.arm.3.8:
  %t10 = call ptr @__alloc(i64 16, i32 1)
  %t11 = inttoptr i64 4 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  %t13 = getelementptr ptr, ptr %t10, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t13
  br label %case.end.3.9
case.end.3.9:
  br label %case.join.7
case.arm.4.14:
  %t16 = getelementptr ptr, ptr %t0, i32 1
  %t17 = load ptr, ptr %t16
  call void @__inc_ref(ptr %t17)
  %t18 = call ptr @__showUInt32(ptr %t17)
  %t19 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t18)
  br label %case.end.4.15
case.end.4.15:
  br label %case.join.7
case.default.6:
  unreachable
case.join.7:
  %t20 = phi ptr [ %t10, %case.end.3.9 ], [ %t19, %case.end.4.15 ]
  %t21 = getelementptr ptr, ptr %t20, i32 0
  %t22 = load ptr, ptr %t21
  %t23 = ptrtoint ptr %t22 to i64
  switch i64 %t23, label %join.case.default.24 [ i64 3, label %join.case.arm.3.25 i64 4, label %join.case.arm.4.39 ]
join.case.arm.3.25:
  %t26 = call ptr @__alloc(i64 24, i32 2)
  %t27 = inttoptr i64 7 to ptr
  %t28 = getelementptr ptr, ptr %t26, i32 0
  store ptr %t27, ptr %t28
  %t29 = getelementptr ptr, ptr %t26, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t29
  %t30 = call ptr @__alloc(i64 16, i32 1)
  %t31 = inttoptr i64 5 to ptr
  %t32 = getelementptr ptr, ptr %t30, i32 0
  store ptr %t31, ptr %t32
  %t33 = call ptr @__alloc(i64 8, i32 0)
  %t34 = inttoptr i64 0 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = getelementptr ptr, ptr %t30, i32 1
  store ptr %t33, ptr %t36
  %t37 = getelementptr ptr, ptr %t26, i32 2
  store ptr %t30, ptr %t37
  call void @__free_recursive(ptr %t20)
  br label %join.val.38
join.val.38:
  br label %join.after.2
join.case.arm.4.39:
  %t40 = getelementptr ptr, ptr %t20, i32 1
  %t41 = load ptr, ptr %t40
  call void @__inc_ref(ptr %t41)
  %t42 = call ptr @__parseUInt32(ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  %t43 = getelementptr ptr, ptr %t42, i32 0
  %t44 = load ptr, ptr %t43
  %t45 = ptrtoint ptr %t44 to i64
  switch i64 %t45, label %case.default.46 [ i64 3, label %case.arm.3.48 i64 4, label %case.arm.4.54 ]
case.arm.3.48:
  %t50 = call ptr @__alloc(i64 16, i32 1)
  %t51 = inttoptr i64 4 to ptr
  %t52 = getelementptr ptr, ptr %t50, i32 0
  store ptr %t51, ptr %t52
  %t53 = getelementptr ptr, ptr %t50, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t53
  br label %case.end.3.49
case.end.3.49:
  br label %case.join.47
case.arm.4.54:
  %t56 = getelementptr ptr, ptr %t42, i32 1
  %t57 = load ptr, ptr %t56
  call void @__inc_ref(ptr %t57)
  %t58 = call ptr @__showUInt32(ptr %t57)
  %t59 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t58)
  br label %case.end.4.55
case.end.4.55:
  br label %case.join.47
case.default.46:
  unreachable
case.join.47:
  %t60 = phi ptr [ %t50, %case.end.3.49 ], [ %t59, %case.end.4.55 ]
  %t61 = getelementptr ptr, ptr %t60, i32 0
  %t62 = load ptr, ptr %t61
  %t63 = ptrtoint ptr %t62 to i64
  switch i64 %t63, label %case.default.64 [ i64 3, label %case.arm.3.66 i64 4, label %case.arm.4.74 ]
case.arm.3.66:
  %t68 = getelementptr ptr, ptr %t60, i32 1
  %t69 = load ptr, ptr %t68
  call void @__inc_ref(ptr %t69)
  %t70 = call ptr @__alloc(i64 16, i32 1)
  %t71 = inttoptr i64 3 to ptr
  %t72 = getelementptr ptr, ptr %t70, i32 0
  store ptr %t71, ptr %t72
  call void @__inc_ref(ptr %t69)
  %t73 = getelementptr ptr, ptr %t70, i32 1
  store ptr %t69, ptr %t73
  br label %case.end.3.67
case.end.3.67:
  br label %case.join.65
case.arm.4.74:
  %t76 = getelementptr ptr, ptr %t60, i32 1
  %t77 = load ptr, ptr %t76
  call void @__inc_ref(ptr %t77)
  %t78 = call ptr @__parseUInt32(ptr getelementptr inbounds (i8, ptr @.str.5, i64 12))
  %t79 = getelementptr ptr, ptr %t78, i32 0
  %t80 = load ptr, ptr %t79
  %t81 = ptrtoint ptr %t80 to i64
  switch i64 %t81, label %case.default.82 [ i64 3, label %case.arm.3.84 i64 4, label %case.arm.4.90 ]
case.arm.3.84:
  %t86 = call ptr @__alloc(i64 16, i32 1)
  %t87 = inttoptr i64 4 to ptr
  %t88 = getelementptr ptr, ptr %t86, i32 0
  store ptr %t87, ptr %t88
  %t89 = getelementptr ptr, ptr %t86, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t89
  br label %case.end.3.85
case.end.3.85:
  br label %case.join.83
case.arm.4.90:
  %t92 = getelementptr ptr, ptr %t78, i32 1
  %t93 = load ptr, ptr %t92
  call void @__inc_ref(ptr %t93)
  %t94 = call ptr @__showUInt32(ptr %t93)
  %t95 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t94)
  br label %case.end.4.91
case.end.4.91:
  br label %case.join.83
case.default.82:
  unreachable
case.join.83:
  %t96 = phi ptr [ %t86, %case.end.3.85 ], [ %t95, %case.end.4.91 ]
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
  %t114 = call ptr @__parseUInt32(ptr getelementptr inbounds (i8, ptr @.str.6, i64 12))
  %t115 = getelementptr ptr, ptr %t114, i32 0
  %t116 = load ptr, ptr %t115
  %t117 = ptrtoint ptr %t116 to i64
  switch i64 %t117, label %case.default.118 [ i64 3, label %case.arm.3.120 i64 4, label %case.arm.4.126 ]
case.arm.3.120:
  %t122 = call ptr @__alloc(i64 16, i32 1)
  %t123 = inttoptr i64 4 to ptr
  %t124 = getelementptr ptr, ptr %t122, i32 0
  store ptr %t123, ptr %t124
  %t125 = getelementptr ptr, ptr %t122, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t125
  br label %case.end.3.121
case.end.3.121:
  br label %case.join.119
case.arm.4.126:
  %t128 = getelementptr ptr, ptr %t114, i32 1
  %t129 = load ptr, ptr %t128
  call void @__inc_ref(ptr %t129)
  %t130 = call ptr @__showUInt32(ptr %t129)
  %t131 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t130)
  br label %case.end.4.127
case.end.4.127:
  br label %case.join.119
case.default.118:
  unreachable
case.join.119:
  %t132 = phi ptr [ %t122, %case.end.3.121 ], [ %t131, %case.end.4.127 ]
  %t133 = getelementptr ptr, ptr %t132, i32 0
  %t134 = load ptr, ptr %t133
  %t135 = ptrtoint ptr %t134 to i64
  switch i64 %t135, label %case.default.136 [ i64 3, label %case.arm.3.138 i64 4, label %case.arm.4.146 ]
case.arm.3.138:
  %t140 = getelementptr ptr, ptr %t132, i32 1
  %t141 = load ptr, ptr %t140
  call void @__inc_ref(ptr %t141)
  %t142 = call ptr @__alloc(i64 16, i32 1)
  %t143 = inttoptr i64 3 to ptr
  %t144 = getelementptr ptr, ptr %t142, i32 0
  store ptr %t143, ptr %t144
  call void @__inc_ref(ptr %t141)
  %t145 = getelementptr ptr, ptr %t142, i32 1
  store ptr %t141, ptr %t145
  br label %case.end.3.139
case.end.3.139:
  br label %case.join.137
case.arm.4.146:
  %t148 = getelementptr ptr, ptr %t132, i32 1
  %t149 = load ptr, ptr %t148
  call void @__inc_ref(ptr %t149)
  %t150 = call ptr @__parseUInt32(ptr getelementptr inbounds (i8, ptr @.str.7, i64 12))
  %t151 = getelementptr ptr, ptr %t150, i32 0
  %t152 = load ptr, ptr %t151
  %t153 = ptrtoint ptr %t152 to i64
  switch i64 %t153, label %case.default.154 [ i64 3, label %case.arm.3.156 i64 4, label %case.arm.4.162 ]
case.arm.3.156:
  %t158 = call ptr @__alloc(i64 16, i32 1)
  %t159 = inttoptr i64 4 to ptr
  %t160 = getelementptr ptr, ptr %t158, i32 0
  store ptr %t159, ptr %t160
  %t161 = getelementptr ptr, ptr %t158, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t161
  br label %case.end.3.157
case.end.3.157:
  br label %case.join.155
case.arm.4.162:
  %t164 = getelementptr ptr, ptr %t150, i32 1
  %t165 = load ptr, ptr %t164
  call void @__inc_ref(ptr %t165)
  %t166 = call ptr @__showUInt32(ptr %t165)
  %t167 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t166)
  br label %case.end.4.163
case.end.4.163:
  br label %case.join.155
case.default.154:
  unreachable
case.join.155:
  %t168 = phi ptr [ %t158, %case.end.3.157 ], [ %t167, %case.end.4.163 ]
  %t169 = getelementptr ptr, ptr %t168, i32 0
  %t170 = load ptr, ptr %t169
  %t171 = ptrtoint ptr %t170 to i64
  switch i64 %t171, label %case.default.172 [ i64 3, label %case.arm.3.174 i64 4, label %case.arm.4.182 ]
case.arm.3.174:
  %t176 = getelementptr ptr, ptr %t168, i32 1
  %t177 = load ptr, ptr %t176
  call void @__inc_ref(ptr %t177)
  %t178 = call ptr @__alloc(i64 16, i32 1)
  %t179 = inttoptr i64 3 to ptr
  %t180 = getelementptr ptr, ptr %t178, i32 0
  store ptr %t179, ptr %t180
  call void @__inc_ref(ptr %t177)
  %t181 = getelementptr ptr, ptr %t178, i32 1
  store ptr %t177, ptr %t181
  br label %case.end.3.175
case.end.3.175:
  br label %case.join.173
case.arm.4.182:
  %t184 = getelementptr ptr, ptr %t168, i32 1
  %t185 = load ptr, ptr %t184
  call void @__inc_ref(ptr %t185)
  %t186 = call ptr @__parseUInt32(ptr getelementptr inbounds (i8, ptr @.str.8, i64 12))
  %t187 = getelementptr ptr, ptr %t186, i32 0
  %t188 = load ptr, ptr %t187
  %t189 = ptrtoint ptr %t188 to i64
  switch i64 %t189, label %case.default.190 [ i64 3, label %case.arm.3.192 i64 4, label %case.arm.4.198 ]
case.arm.3.192:
  %t194 = call ptr @__alloc(i64 16, i32 1)
  %t195 = inttoptr i64 4 to ptr
  %t196 = getelementptr ptr, ptr %t194, i32 0
  store ptr %t195, ptr %t196
  %t197 = getelementptr ptr, ptr %t194, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t197
  br label %case.end.3.193
case.end.3.193:
  br label %case.join.191
case.arm.4.198:
  %t200 = getelementptr ptr, ptr %t186, i32 1
  %t201 = load ptr, ptr %t200
  call void @__inc_ref(ptr %t201)
  %t202 = call ptr @__showUInt32(ptr %t201)
  %t203 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t202)
  br label %case.end.4.199
case.end.4.199:
  br label %case.join.191
case.default.190:
  unreachable
case.join.191:
  %t204 = phi ptr [ %t194, %case.end.3.193 ], [ %t203, %case.end.4.199 ]
  %t205 = getelementptr ptr, ptr %t204, i32 0
  %t206 = load ptr, ptr %t205
  %t207 = ptrtoint ptr %t206 to i64
  switch i64 %t207, label %case.default.208 [ i64 3, label %case.arm.3.210 i64 4, label %case.arm.4.218 ]
case.arm.3.210:
  %t212 = getelementptr ptr, ptr %t204, i32 1
  %t213 = load ptr, ptr %t212
  call void @__inc_ref(ptr %t213)
  %t214 = call ptr @__alloc(i64 16, i32 1)
  %t215 = inttoptr i64 3 to ptr
  %t216 = getelementptr ptr, ptr %t214, i32 0
  store ptr %t215, ptr %t216
  call void @__inc_ref(ptr %t213)
  %t217 = getelementptr ptr, ptr %t214, i32 1
  store ptr %t213, ptr %t217
  br label %case.end.3.211
case.end.3.211:
  br label %case.join.209
case.arm.4.218:
  %t220 = getelementptr ptr, ptr %t204, i32 1
  %t221 = load ptr, ptr %t220
  call void @__inc_ref(ptr %t221)
  %t222 = call ptr @__parseUInt32(ptr getelementptr inbounds (i8, ptr @.str.9, i64 12))
  %t223 = getelementptr ptr, ptr %t222, i32 0
  %t224 = load ptr, ptr %t223
  %t225 = ptrtoint ptr %t224 to i64
  switch i64 %t225, label %case.default.226 [ i64 3, label %case.arm.3.228 i64 4, label %case.arm.4.234 ]
case.arm.3.228:
  %t230 = call ptr @__alloc(i64 16, i32 1)
  %t231 = inttoptr i64 4 to ptr
  %t232 = getelementptr ptr, ptr %t230, i32 0
  store ptr %t231, ptr %t232
  %t233 = getelementptr ptr, ptr %t230, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t233
  br label %case.end.3.229
case.end.3.229:
  br label %case.join.227
case.arm.4.234:
  %t236 = getelementptr ptr, ptr %t222, i32 1
  %t237 = load ptr, ptr %t236
  call void @__inc_ref(ptr %t237)
  %t238 = call ptr @__showUInt32(ptr %t237)
  %t239 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t238)
  br label %case.end.4.235
case.end.4.235:
  br label %case.join.227
case.default.226:
  unreachable
case.join.227:
  %t240 = phi ptr [ %t230, %case.end.3.229 ], [ %t239, %case.end.4.235 ]
  %t241 = getelementptr ptr, ptr %t240, i32 0
  %t242 = load ptr, ptr %t241
  %t243 = ptrtoint ptr %t242 to i64
  switch i64 %t243, label %case.default.244 [ i64 3, label %case.arm.3.246 i64 4, label %case.arm.4.254 ]
case.arm.3.246:
  %t248 = getelementptr ptr, ptr %t240, i32 1
  %t249 = load ptr, ptr %t248
  call void @__inc_ref(ptr %t249)
  %t250 = call ptr @__alloc(i64 16, i32 1)
  %t251 = inttoptr i64 3 to ptr
  %t252 = getelementptr ptr, ptr %t250, i32 0
  store ptr %t251, ptr %t252
  call void @__inc_ref(ptr %t249)
  %t253 = getelementptr ptr, ptr %t250, i32 1
  store ptr %t249, ptr %t253
  br label %case.end.3.247
case.end.3.247:
  br label %case.join.245
case.arm.4.254:
  %t256 = getelementptr ptr, ptr %t240, i32 1
  %t257 = load ptr, ptr %t256
  call void @__inc_ref(ptr %t257)
  %t258 = call ptr @__parseUInt32(ptr getelementptr inbounds (i8, ptr @.str.10, i64 12))
  %t259 = getelementptr ptr, ptr %t258, i32 0
  %t260 = load ptr, ptr %t259
  %t261 = ptrtoint ptr %t260 to i64
  switch i64 %t261, label %case.default.262 [ i64 3, label %case.arm.3.264 i64 4, label %case.arm.4.270 ]
case.arm.3.264:
  %t266 = call ptr @__alloc(i64 16, i32 1)
  %t267 = inttoptr i64 4 to ptr
  %t268 = getelementptr ptr, ptr %t266, i32 0
  store ptr %t267, ptr %t268
  %t269 = getelementptr ptr, ptr %t266, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t269
  br label %case.end.3.265
case.end.3.265:
  br label %case.join.263
case.arm.4.270:
  %t272 = getelementptr ptr, ptr %t258, i32 1
  %t273 = load ptr, ptr %t272
  call void @__inc_ref(ptr %t273)
  %t274 = call ptr @__showUInt32(ptr %t273)
  %t275 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t274)
  br label %case.end.4.271
case.end.4.271:
  br label %case.join.263
case.default.262:
  unreachable
case.join.263:
  %t276 = phi ptr [ %t266, %case.end.3.265 ], [ %t275, %case.end.4.271 ]
  %t277 = getelementptr ptr, ptr %t276, i32 0
  %t278 = load ptr, ptr %t277
  %t279 = ptrtoint ptr %t278 to i64
  switch i64 %t279, label %case.default.280 [ i64 3, label %case.arm.3.282 i64 4, label %case.arm.4.290 ]
case.arm.3.282:
  %t284 = getelementptr ptr, ptr %t276, i32 1
  %t285 = load ptr, ptr %t284
  call void @__inc_ref(ptr %t285)
  %t286 = call ptr @__alloc(i64 16, i32 1)
  %t287 = inttoptr i64 3 to ptr
  %t288 = getelementptr ptr, ptr %t286, i32 0
  store ptr %t287, ptr %t288
  call void @__inc_ref(ptr %t285)
  %t289 = getelementptr ptr, ptr %t286, i32 1
  store ptr %t285, ptr %t289
  br label %case.end.3.283
case.end.3.283:
  br label %case.join.281
case.arm.4.290:
  %t292 = getelementptr ptr, ptr %t276, i32 1
  %t293 = load ptr, ptr %t292
  call void @__inc_ref(ptr %t293)
  %t294 = call ptr @__parseUInt32(ptr getelementptr inbounds (i8, ptr @.str.11, i64 12))
  %t295 = getelementptr ptr, ptr %t294, i32 0
  %t296 = load ptr, ptr %t295
  %t297 = ptrtoint ptr %t296 to i64
  switch i64 %t297, label %case.default.298 [ i64 3, label %case.arm.3.300 i64 4, label %case.arm.4.306 ]
case.arm.3.300:
  %t302 = call ptr @__alloc(i64 16, i32 1)
  %t303 = inttoptr i64 4 to ptr
  %t304 = getelementptr ptr, ptr %t302, i32 0
  store ptr %t303, ptr %t304
  %t305 = getelementptr ptr, ptr %t302, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t305
  br label %case.end.3.301
case.end.3.301:
  br label %case.join.299
case.arm.4.306:
  %t308 = getelementptr ptr, ptr %t294, i32 1
  %t309 = load ptr, ptr %t308
  call void @__inc_ref(ptr %t309)
  %t310 = call ptr @__showUInt32(ptr %t309)
  %t311 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t310)
  br label %case.end.4.307
case.end.4.307:
  br label %case.join.299
case.default.298:
  unreachable
case.join.299:
  %t312 = phi ptr [ %t302, %case.end.3.301 ], [ %t311, %case.end.4.307 ]
  %t313 = getelementptr ptr, ptr %t312, i32 0
  %t314 = load ptr, ptr %t313
  %t315 = ptrtoint ptr %t314 to i64
  switch i64 %t315, label %case.default.316 [ i64 3, label %case.arm.3.318 i64 4, label %case.arm.4.326 ]
case.arm.3.318:
  %t320 = getelementptr ptr, ptr %t312, i32 1
  %t321 = load ptr, ptr %t320
  call void @__inc_ref(ptr %t321)
  %t322 = call ptr @__alloc(i64 16, i32 1)
  %t323 = inttoptr i64 3 to ptr
  %t324 = getelementptr ptr, ptr %t322, i32 0
  store ptr %t323, ptr %t324
  call void @__inc_ref(ptr %t321)
  %t325 = getelementptr ptr, ptr %t322, i32 1
  store ptr %t321, ptr %t325
  br label %case.end.3.319
case.end.3.319:
  br label %case.join.317
case.arm.4.326:
  %t328 = getelementptr ptr, ptr %t312, i32 1
  %t329 = load ptr, ptr %t328
  call void @__inc_ref(ptr %t329)
  call void @__inc_ref(ptr %t41)
  %t330 = call ptr @__concat(ptr %t41, ptr getelementptr inbounds (i8, ptr @.str.12, i64 12))
  %t331 = getelementptr ptr, ptr %t330, i32 0
  %t332 = load ptr, ptr %t331
  %t333 = ptrtoint ptr %t332 to i64
  switch i64 %t333, label %case.default.334 [ i64 3, label %case.arm.3.336 i64 4, label %case.arm.4.344 ]
case.arm.3.336:
  %t338 = getelementptr ptr, ptr %t330, i32 1
  %t339 = load ptr, ptr %t338
  call void @__inc_ref(ptr %t339)
  %t340 = call ptr @__alloc(i64 16, i32 1)
  %t341 = inttoptr i64 3 to ptr
  %t342 = getelementptr ptr, ptr %t340, i32 0
  store ptr %t341, ptr %t342
  call void @__inc_ref(ptr %t339)
  %t343 = getelementptr ptr, ptr %t340, i32 1
  store ptr %t339, ptr %t343
  br label %case.end.3.337
case.end.3.337:
  br label %case.join.335
case.arm.4.344:
  %t346 = getelementptr ptr, ptr %t330, i32 1
  %t347 = load ptr, ptr %t346
  call void @__inc_ref(ptr %t347)
  call void @__inc_ref(ptr %t347)
  call void @__inc_ref(ptr %t77)
  %t348 = call ptr @__concat(ptr %t347, ptr %t77)
  %t349 = getelementptr ptr, ptr %t348, i32 0
  %t350 = load ptr, ptr %t349
  %t351 = ptrtoint ptr %t350 to i64
  switch i64 %t351, label %case.default.352 [ i64 3, label %case.arm.3.354 i64 4, label %case.arm.4.362 ]
case.arm.3.354:
  %t356 = getelementptr ptr, ptr %t348, i32 1
  %t357 = load ptr, ptr %t356
  call void @__inc_ref(ptr %t357)
  %t358 = call ptr @__alloc(i64 16, i32 1)
  %t359 = inttoptr i64 3 to ptr
  %t360 = getelementptr ptr, ptr %t358, i32 0
  store ptr %t359, ptr %t360
  call void @__inc_ref(ptr %t357)
  %t361 = getelementptr ptr, ptr %t358, i32 1
  store ptr %t357, ptr %t361
  br label %case.end.3.355
case.end.3.355:
  br label %case.join.353
case.arm.4.362:
  %t364 = getelementptr ptr, ptr %t348, i32 1
  %t365 = load ptr, ptr %t364
  call void @__inc_ref(ptr %t365)
  call void @__inc_ref(ptr %t365)
  %t366 = call ptr @__concat(ptr %t365, ptr getelementptr inbounds (i8, ptr @.str.12, i64 12))
  %t367 = getelementptr ptr, ptr %t366, i32 0
  %t368 = load ptr, ptr %t367
  %t369 = ptrtoint ptr %t368 to i64
  switch i64 %t369, label %case.default.370 [ i64 3, label %case.arm.3.372 i64 4, label %case.arm.4.380 ]
case.arm.3.372:
  %t374 = getelementptr ptr, ptr %t366, i32 1
  %t375 = load ptr, ptr %t374
  call void @__inc_ref(ptr %t375)
  %t376 = call ptr @__alloc(i64 16, i32 1)
  %t377 = inttoptr i64 3 to ptr
  %t378 = getelementptr ptr, ptr %t376, i32 0
  store ptr %t377, ptr %t378
  call void @__inc_ref(ptr %t375)
  %t379 = getelementptr ptr, ptr %t376, i32 1
  store ptr %t375, ptr %t379
  br label %case.end.3.373
case.end.3.373:
  br label %case.join.371
case.arm.4.380:
  %t382 = getelementptr ptr, ptr %t366, i32 1
  %t383 = load ptr, ptr %t382
  call void @__inc_ref(ptr %t383)
  call void @__inc_ref(ptr %t383)
  call void @__inc_ref(ptr %t113)
  %t384 = call ptr @__concat(ptr %t383, ptr %t113)
  %t385 = getelementptr ptr, ptr %t384, i32 0
  %t386 = load ptr, ptr %t385
  %t387 = ptrtoint ptr %t386 to i64
  switch i64 %t387, label %case.default.388 [ i64 3, label %case.arm.3.390 i64 4, label %case.arm.4.398 ]
case.arm.3.390:
  %t392 = getelementptr ptr, ptr %t384, i32 1
  %t393 = load ptr, ptr %t392
  call void @__inc_ref(ptr %t393)
  %t394 = call ptr @__alloc(i64 16, i32 1)
  %t395 = inttoptr i64 3 to ptr
  %t396 = getelementptr ptr, ptr %t394, i32 0
  store ptr %t395, ptr %t396
  call void @__inc_ref(ptr %t393)
  %t397 = getelementptr ptr, ptr %t394, i32 1
  store ptr %t393, ptr %t397
  br label %case.end.3.391
case.end.3.391:
  br label %case.join.389
case.arm.4.398:
  %t400 = getelementptr ptr, ptr %t384, i32 1
  %t401 = load ptr, ptr %t400
  call void @__inc_ref(ptr %t401)
  call void @__inc_ref(ptr %t401)
  %t402 = call ptr @__concat(ptr %t401, ptr getelementptr inbounds (i8, ptr @.str.12, i64 12))
  %t403 = getelementptr ptr, ptr %t402, i32 0
  %t404 = load ptr, ptr %t403
  %t405 = ptrtoint ptr %t404 to i64
  switch i64 %t405, label %case.default.406 [ i64 3, label %case.arm.3.408 i64 4, label %case.arm.4.416 ]
case.arm.3.408:
  %t410 = getelementptr ptr, ptr %t402, i32 1
  %t411 = load ptr, ptr %t410
  call void @__inc_ref(ptr %t411)
  %t412 = call ptr @__alloc(i64 16, i32 1)
  %t413 = inttoptr i64 3 to ptr
  %t414 = getelementptr ptr, ptr %t412, i32 0
  store ptr %t413, ptr %t414
  call void @__inc_ref(ptr %t411)
  %t415 = getelementptr ptr, ptr %t412, i32 1
  store ptr %t411, ptr %t415
  br label %case.end.3.409
case.end.3.409:
  br label %case.join.407
case.arm.4.416:
  %t418 = getelementptr ptr, ptr %t402, i32 1
  %t419 = load ptr, ptr %t418
  call void @__inc_ref(ptr %t419)
  call void @__inc_ref(ptr %t419)
  call void @__inc_ref(ptr %t149)
  %t420 = call ptr @__concat(ptr %t419, ptr %t149)
  %t421 = getelementptr ptr, ptr %t420, i32 0
  %t422 = load ptr, ptr %t421
  %t423 = ptrtoint ptr %t422 to i64
  switch i64 %t423, label %case.default.424 [ i64 3, label %case.arm.3.426 i64 4, label %case.arm.4.434 ]
case.arm.3.426:
  %t428 = getelementptr ptr, ptr %t420, i32 1
  %t429 = load ptr, ptr %t428
  call void @__inc_ref(ptr %t429)
  %t430 = call ptr @__alloc(i64 16, i32 1)
  %t431 = inttoptr i64 3 to ptr
  %t432 = getelementptr ptr, ptr %t430, i32 0
  store ptr %t431, ptr %t432
  call void @__inc_ref(ptr %t429)
  %t433 = getelementptr ptr, ptr %t430, i32 1
  store ptr %t429, ptr %t433
  br label %case.end.3.427
case.end.3.427:
  br label %case.join.425
case.arm.4.434:
  %t436 = getelementptr ptr, ptr %t420, i32 1
  %t437 = load ptr, ptr %t436
  call void @__inc_ref(ptr %t437)
  call void @__inc_ref(ptr %t437)
  %t438 = call ptr @__concat(ptr %t437, ptr getelementptr inbounds (i8, ptr @.str.12, i64 12))
  %t439 = getelementptr ptr, ptr %t438, i32 0
  %t440 = load ptr, ptr %t439
  %t441 = ptrtoint ptr %t440 to i64
  switch i64 %t441, label %case.default.442 [ i64 3, label %case.arm.3.444 i64 4, label %case.arm.4.452 ]
case.arm.3.444:
  %t446 = getelementptr ptr, ptr %t438, i32 1
  %t447 = load ptr, ptr %t446
  call void @__inc_ref(ptr %t447)
  %t448 = call ptr @__alloc(i64 16, i32 1)
  %t449 = inttoptr i64 3 to ptr
  %t450 = getelementptr ptr, ptr %t448, i32 0
  store ptr %t449, ptr %t450
  call void @__inc_ref(ptr %t447)
  %t451 = getelementptr ptr, ptr %t448, i32 1
  store ptr %t447, ptr %t451
  br label %case.end.3.445
case.end.3.445:
  br label %case.join.443
case.arm.4.452:
  %t454 = getelementptr ptr, ptr %t438, i32 1
  %t455 = load ptr, ptr %t454
  call void @__inc_ref(ptr %t455)
  call void @__inc_ref(ptr %t455)
  call void @__inc_ref(ptr %t185)
  %t456 = call ptr @__concat(ptr %t455, ptr %t185)
  %t457 = getelementptr ptr, ptr %t456, i32 0
  %t458 = load ptr, ptr %t457
  %t459 = ptrtoint ptr %t458 to i64
  switch i64 %t459, label %case.default.460 [ i64 3, label %case.arm.3.462 i64 4, label %case.arm.4.470 ]
case.arm.3.462:
  %t464 = getelementptr ptr, ptr %t456, i32 1
  %t465 = load ptr, ptr %t464
  call void @__inc_ref(ptr %t465)
  %t466 = call ptr @__alloc(i64 16, i32 1)
  %t467 = inttoptr i64 3 to ptr
  %t468 = getelementptr ptr, ptr %t466, i32 0
  store ptr %t467, ptr %t468
  call void @__inc_ref(ptr %t465)
  %t469 = getelementptr ptr, ptr %t466, i32 1
  store ptr %t465, ptr %t469
  br label %case.end.3.463
case.end.3.463:
  br label %case.join.461
case.arm.4.470:
  %t472 = getelementptr ptr, ptr %t456, i32 1
  %t473 = load ptr, ptr %t472
  call void @__inc_ref(ptr %t473)
  call void @__inc_ref(ptr %t473)
  %t474 = call ptr @__concat(ptr %t473, ptr getelementptr inbounds (i8, ptr @.str.12, i64 12))
  %t475 = getelementptr ptr, ptr %t474, i32 0
  %t476 = load ptr, ptr %t475
  %t477 = ptrtoint ptr %t476 to i64
  switch i64 %t477, label %case.default.478 [ i64 3, label %case.arm.3.480 i64 4, label %case.arm.4.488 ]
case.arm.3.480:
  %t482 = getelementptr ptr, ptr %t474, i32 1
  %t483 = load ptr, ptr %t482
  call void @__inc_ref(ptr %t483)
  %t484 = call ptr @__alloc(i64 16, i32 1)
  %t485 = inttoptr i64 3 to ptr
  %t486 = getelementptr ptr, ptr %t484, i32 0
  store ptr %t485, ptr %t486
  call void @__inc_ref(ptr %t483)
  %t487 = getelementptr ptr, ptr %t484, i32 1
  store ptr %t483, ptr %t487
  br label %case.end.3.481
case.end.3.481:
  br label %case.join.479
case.arm.4.488:
  %t490 = getelementptr ptr, ptr %t474, i32 1
  %t491 = load ptr, ptr %t490
  call void @__inc_ref(ptr %t491)
  call void @__inc_ref(ptr %t491)
  call void @__inc_ref(ptr %t221)
  %t492 = call ptr @__concat(ptr %t491, ptr %t221)
  %t493 = getelementptr ptr, ptr %t492, i32 0
  %t494 = load ptr, ptr %t493
  %t495 = ptrtoint ptr %t494 to i64
  switch i64 %t495, label %case.default.496 [ i64 3, label %case.arm.3.498 i64 4, label %case.arm.4.506 ]
case.arm.3.498:
  %t500 = getelementptr ptr, ptr %t492, i32 1
  %t501 = load ptr, ptr %t500
  call void @__inc_ref(ptr %t501)
  %t502 = call ptr @__alloc(i64 16, i32 1)
  %t503 = inttoptr i64 3 to ptr
  %t504 = getelementptr ptr, ptr %t502, i32 0
  store ptr %t503, ptr %t504
  call void @__inc_ref(ptr %t501)
  %t505 = getelementptr ptr, ptr %t502, i32 1
  store ptr %t501, ptr %t505
  br label %case.end.3.499
case.end.3.499:
  br label %case.join.497
case.arm.4.506:
  %t508 = getelementptr ptr, ptr %t492, i32 1
  %t509 = load ptr, ptr %t508
  call void @__inc_ref(ptr %t509)
  call void @__inc_ref(ptr %t509)
  %t510 = call ptr @__concat(ptr %t509, ptr getelementptr inbounds (i8, ptr @.str.12, i64 12))
  %t511 = getelementptr ptr, ptr %t510, i32 0
  %t512 = load ptr, ptr %t511
  %t513 = ptrtoint ptr %t512 to i64
  switch i64 %t513, label %case.default.514 [ i64 3, label %case.arm.3.516 i64 4, label %case.arm.4.524 ]
case.arm.3.516:
  %t518 = getelementptr ptr, ptr %t510, i32 1
  %t519 = load ptr, ptr %t518
  call void @__inc_ref(ptr %t519)
  %t520 = call ptr @__alloc(i64 16, i32 1)
  %t521 = inttoptr i64 3 to ptr
  %t522 = getelementptr ptr, ptr %t520, i32 0
  store ptr %t521, ptr %t522
  call void @__inc_ref(ptr %t519)
  %t523 = getelementptr ptr, ptr %t520, i32 1
  store ptr %t519, ptr %t523
  br label %case.end.3.517
case.end.3.517:
  br label %case.join.515
case.arm.4.524:
  %t526 = getelementptr ptr, ptr %t510, i32 1
  %t527 = load ptr, ptr %t526
  call void @__inc_ref(ptr %t527)
  call void @__inc_ref(ptr %t527)
  call void @__inc_ref(ptr %t257)
  %t528 = call ptr @__concat(ptr %t527, ptr %t257)
  %t529 = getelementptr ptr, ptr %t528, i32 0
  %t530 = load ptr, ptr %t529
  %t531 = ptrtoint ptr %t530 to i64
  switch i64 %t531, label %case.default.532 [ i64 3, label %case.arm.3.534 i64 4, label %case.arm.4.542 ]
case.arm.3.534:
  %t536 = getelementptr ptr, ptr %t528, i32 1
  %t537 = load ptr, ptr %t536
  call void @__inc_ref(ptr %t537)
  %t538 = call ptr @__alloc(i64 16, i32 1)
  %t539 = inttoptr i64 3 to ptr
  %t540 = getelementptr ptr, ptr %t538, i32 0
  store ptr %t539, ptr %t540
  call void @__inc_ref(ptr %t537)
  %t541 = getelementptr ptr, ptr %t538, i32 1
  store ptr %t537, ptr %t541
  br label %case.end.3.535
case.end.3.535:
  br label %case.join.533
case.arm.4.542:
  %t544 = getelementptr ptr, ptr %t528, i32 1
  %t545 = load ptr, ptr %t544
  call void @__inc_ref(ptr %t545)
  call void @__inc_ref(ptr %t545)
  %t546 = call ptr @__concat(ptr %t545, ptr getelementptr inbounds (i8, ptr @.str.12, i64 12))
  %t547 = getelementptr ptr, ptr %t546, i32 0
  %t548 = load ptr, ptr %t547
  %t549 = ptrtoint ptr %t548 to i64
  switch i64 %t549, label %case.default.550 [ i64 3, label %case.arm.3.552 i64 4, label %case.arm.4.560 ]
case.arm.3.552:
  %t554 = getelementptr ptr, ptr %t546, i32 1
  %t555 = load ptr, ptr %t554
  call void @__inc_ref(ptr %t555)
  %t556 = call ptr @__alloc(i64 16, i32 1)
  %t557 = inttoptr i64 3 to ptr
  %t558 = getelementptr ptr, ptr %t556, i32 0
  store ptr %t557, ptr %t558
  call void @__inc_ref(ptr %t555)
  %t559 = getelementptr ptr, ptr %t556, i32 1
  store ptr %t555, ptr %t559
  br label %case.end.3.553
case.end.3.553:
  br label %case.join.551
case.arm.4.560:
  %t562 = getelementptr ptr, ptr %t546, i32 1
  %t563 = load ptr, ptr %t562
  call void @__inc_ref(ptr %t563)
  call void @__inc_ref(ptr %t563)
  call void @__inc_ref(ptr %t293)
  %t564 = call ptr @__concat(ptr %t563, ptr %t293)
  %t565 = getelementptr ptr, ptr %t564, i32 0
  %t566 = load ptr, ptr %t565
  %t567 = ptrtoint ptr %t566 to i64
  switch i64 %t567, label %case.default.568 [ i64 3, label %case.arm.3.570 i64 4, label %case.arm.4.578 ]
case.arm.3.570:
  %t572 = getelementptr ptr, ptr %t564, i32 1
  %t573 = load ptr, ptr %t572
  call void @__inc_ref(ptr %t573)
  %t574 = call ptr @__alloc(i64 16, i32 1)
  %t575 = inttoptr i64 3 to ptr
  %t576 = getelementptr ptr, ptr %t574, i32 0
  store ptr %t575, ptr %t576
  call void @__inc_ref(ptr %t573)
  %t577 = getelementptr ptr, ptr %t574, i32 1
  store ptr %t573, ptr %t577
  br label %case.end.3.571
case.end.3.571:
  br label %case.join.569
case.arm.4.578:
  %t580 = getelementptr ptr, ptr %t564, i32 1
  %t581 = load ptr, ptr %t580
  call void @__inc_ref(ptr %t581)
  call void @__inc_ref(ptr %t581)
  %t582 = call ptr @__concat(ptr %t581, ptr getelementptr inbounds (i8, ptr @.str.12, i64 12))
  %t583 = getelementptr ptr, ptr %t582, i32 0
  %t584 = load ptr, ptr %t583
  %t585 = ptrtoint ptr %t584 to i64
  switch i64 %t585, label %case.default.586 [ i64 3, label %case.arm.3.588 i64 4, label %case.arm.4.596 ]
case.arm.3.588:
  %t590 = getelementptr ptr, ptr %t582, i32 1
  %t591 = load ptr, ptr %t590
  call void @__inc_ref(ptr %t591)
  %t592 = call ptr @__alloc(i64 16, i32 1)
  %t593 = inttoptr i64 3 to ptr
  %t594 = getelementptr ptr, ptr %t592, i32 0
  store ptr %t593, ptr %t594
  call void @__inc_ref(ptr %t591)
  %t595 = getelementptr ptr, ptr %t592, i32 1
  store ptr %t591, ptr %t595
  br label %case.end.3.589
case.end.3.589:
  br label %case.join.587
case.arm.4.596:
  %t598 = getelementptr ptr, ptr %t582, i32 1
  %t599 = load ptr, ptr %t598
  call void @__inc_ref(ptr %t599)
  call void @__inc_ref(ptr %t599)
  call void @__inc_ref(ptr %t329)
  %t600 = call ptr @__concat(ptr %t599, ptr %t329)
  br label %case.end.4.597
case.end.4.597:
  br label %case.join.587
case.default.586:
  unreachable
case.join.587:
  %t601 = phi ptr [ %t592, %case.end.3.589 ], [ %t600, %case.end.4.597 ]
  call void @__free_recursive(ptr %t582)
  br label %case.end.4.579
case.end.4.579:
  br label %case.join.569
case.default.568:
  unreachable
case.join.569:
  %t602 = phi ptr [ %t574, %case.end.3.571 ], [ %t601, %case.end.4.579 ]
  call void @__free_recursive(ptr %t564)
  br label %case.end.4.561
case.end.4.561:
  br label %case.join.551
case.default.550:
  unreachable
case.join.551:
  %t603 = phi ptr [ %t556, %case.end.3.553 ], [ %t602, %case.end.4.561 ]
  call void @__free_recursive(ptr %t546)
  br label %case.end.4.543
case.end.4.543:
  br label %case.join.533
case.default.532:
  unreachable
case.join.533:
  %t604 = phi ptr [ %t538, %case.end.3.535 ], [ %t603, %case.end.4.543 ]
  call void @__free_recursive(ptr %t528)
  br label %case.end.4.525
case.end.4.525:
  br label %case.join.515
case.default.514:
  unreachable
case.join.515:
  %t605 = phi ptr [ %t520, %case.end.3.517 ], [ %t604, %case.end.4.525 ]
  call void @__free_recursive(ptr %t510)
  br label %case.end.4.507
case.end.4.507:
  br label %case.join.497
case.default.496:
  unreachable
case.join.497:
  %t606 = phi ptr [ %t502, %case.end.3.499 ], [ %t605, %case.end.4.507 ]
  call void @__free_recursive(ptr %t492)
  br label %case.end.4.489
case.end.4.489:
  br label %case.join.479
case.default.478:
  unreachable
case.join.479:
  %t607 = phi ptr [ %t484, %case.end.3.481 ], [ %t606, %case.end.4.489 ]
  call void @__free_recursive(ptr %t474)
  br label %case.end.4.471
case.end.4.471:
  br label %case.join.461
case.default.460:
  unreachable
case.join.461:
  %t608 = phi ptr [ %t466, %case.end.3.463 ], [ %t607, %case.end.4.471 ]
  call void @__free_recursive(ptr %t456)
  br label %case.end.4.453
case.end.4.453:
  br label %case.join.443
case.default.442:
  unreachable
case.join.443:
  %t609 = phi ptr [ %t448, %case.end.3.445 ], [ %t608, %case.end.4.453 ]
  call void @__free_recursive(ptr %t438)
  br label %case.end.4.435
case.end.4.435:
  br label %case.join.425
case.default.424:
  unreachable
case.join.425:
  %t610 = phi ptr [ %t430, %case.end.3.427 ], [ %t609, %case.end.4.435 ]
  call void @__free_recursive(ptr %t420)
  br label %case.end.4.417
case.end.4.417:
  br label %case.join.407
case.default.406:
  unreachable
case.join.407:
  %t611 = phi ptr [ %t412, %case.end.3.409 ], [ %t610, %case.end.4.417 ]
  call void @__free_recursive(ptr %t402)
  br label %case.end.4.399
case.end.4.399:
  br label %case.join.389
case.default.388:
  unreachable
case.join.389:
  %t612 = phi ptr [ %t394, %case.end.3.391 ], [ %t611, %case.end.4.399 ]
  call void @__free_recursive(ptr %t384)
  br label %case.end.4.381
case.end.4.381:
  br label %case.join.371
case.default.370:
  unreachable
case.join.371:
  %t613 = phi ptr [ %t376, %case.end.3.373 ], [ %t612, %case.end.4.381 ]
  call void @__free_recursive(ptr %t366)
  br label %case.end.4.363
case.end.4.363:
  br label %case.join.353
case.default.352:
  unreachable
case.join.353:
  %t614 = phi ptr [ %t358, %case.end.3.355 ], [ %t613, %case.end.4.363 ]
  call void @__free_recursive(ptr %t348)
  br label %case.end.4.345
case.end.4.345:
  br label %case.join.335
case.default.334:
  unreachable
case.join.335:
  %t615 = phi ptr [ %t340, %case.end.3.337 ], [ %t614, %case.end.4.345 ]
  call void @__free_recursive(ptr %t330)
  br label %case.end.4.327
case.end.4.327:
  br label %case.join.317
case.default.316:
  unreachable
case.join.317:
  %t616 = phi ptr [ %t322, %case.end.3.319 ], [ %t615, %case.end.4.327 ]
  call void @__free_recursive(ptr %t312)
  call void @__free_recursive(ptr %t294)
  br label %case.end.4.291
case.end.4.291:
  br label %case.join.281
case.default.280:
  unreachable
case.join.281:
  %t617 = phi ptr [ %t286, %case.end.3.283 ], [ %t616, %case.end.4.291 ]
  call void @__free_recursive(ptr %t276)
  call void @__free_recursive(ptr %t258)
  br label %case.end.4.255
case.end.4.255:
  br label %case.join.245
case.default.244:
  unreachable
case.join.245:
  %t618 = phi ptr [ %t250, %case.end.3.247 ], [ %t617, %case.end.4.255 ]
  call void @__free_recursive(ptr %t240)
  call void @__free_recursive(ptr %t222)
  br label %case.end.4.219
case.end.4.219:
  br label %case.join.209
case.default.208:
  unreachable
case.join.209:
  %t619 = phi ptr [ %t214, %case.end.3.211 ], [ %t618, %case.end.4.219 ]
  call void @__free_recursive(ptr %t204)
  call void @__free_recursive(ptr %t186)
  br label %case.end.4.183
case.end.4.183:
  br label %case.join.173
case.default.172:
  unreachable
case.join.173:
  %t620 = phi ptr [ %t178, %case.end.3.175 ], [ %t619, %case.end.4.183 ]
  call void @__free_recursive(ptr %t168)
  call void @__free_recursive(ptr %t150)
  br label %case.end.4.147
case.end.4.147:
  br label %case.join.137
case.default.136:
  unreachable
case.join.137:
  %t621 = phi ptr [ %t142, %case.end.3.139 ], [ %t620, %case.end.4.147 ]
  call void @__free_recursive(ptr %t132)
  call void @__free_recursive(ptr %t114)
  br label %case.end.4.111
case.end.4.111:
  br label %case.join.101
case.default.100:
  unreachable
case.join.101:
  %t622 = phi ptr [ %t106, %case.end.3.103 ], [ %t621, %case.end.4.111 ]
  call void @__free_recursive(ptr %t96)
  call void @__free_recursive(ptr %t78)
  br label %case.end.4.75
case.end.4.75:
  br label %case.join.65
case.default.64:
  unreachable
case.join.65:
  %t623 = phi ptr [ %t70, %case.end.3.67 ], [ %t622, %case.end.4.75 ]
  call void @__free_recursive(ptr %t60)
  call void @__free_recursive(ptr %t42)
  call void @__free_recursive(ptr %t20)
  store ptr %t623, ptr %v__inl31_scrut.jslot
  br label %join.1
join.case.default.24:
  unreachable
join.1:
  %t624 = load ptr, ptr %v__inl31_scrut.jslot
  %t625 = getelementptr ptr, ptr %t624, i32 0
  %t626 = load ptr, ptr %t625
  %t627 = ptrtoint ptr %t626 to i64
  switch i64 %t627, label %case.default.628 [ i64 3, label %case.arm.3.630 i64 4, label %case.arm.4.644 ]
case.arm.3.630:
  %t632 = call ptr @__alloc(i64 24, i32 2)
  %t633 = inttoptr i64 7 to ptr
  %t634 = getelementptr ptr, ptr %t632, i32 0
  store ptr %t633, ptr %t634
  %t635 = getelementptr ptr, ptr %t632, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t635
  %t636 = call ptr @__alloc(i64 16, i32 1)
  %t637 = inttoptr i64 5 to ptr
  %t638 = getelementptr ptr, ptr %t636, i32 0
  store ptr %t637, ptr %t638
  %t639 = call ptr @__alloc(i64 8, i32 0)
  %t640 = inttoptr i64 0 to ptr
  %t641 = getelementptr ptr, ptr %t639, i32 0
  store ptr %t640, ptr %t641
  %t642 = getelementptr ptr, ptr %t636, i32 1
  store ptr %t639, ptr %t642
  %t643 = getelementptr ptr, ptr %t632, i32 2
  store ptr %t636, ptr %t643
  br label %case.end.3.631
case.end.3.631:
  br label %case.join.629
case.arm.4.644:
  %t646 = call ptr @__alloc(i64 24, i32 2)
  %t647 = inttoptr i64 7 to ptr
  %t648 = getelementptr ptr, ptr %t646, i32 0
  store ptr %t647, ptr %t648
  %t649 = getelementptr ptr, ptr %t624, i32 1
  %t650 = load ptr, ptr %t649
  call void @__inc_ref(ptr %t650)
  %t651 = getelementptr ptr, ptr %t646, i32 1
  store ptr %t650, ptr %t651
  %t652 = call ptr @__alloc(i64 16, i32 1)
  %t653 = inttoptr i64 5 to ptr
  %t654 = getelementptr ptr, ptr %t652, i32 0
  store ptr %t653, ptr %t654
  %t655 = call ptr @__alloc(i64 8, i32 0)
  %t656 = inttoptr i64 0 to ptr
  %t657 = getelementptr ptr, ptr %t655, i32 0
  store ptr %t656, ptr %t657
  %t658 = getelementptr ptr, ptr %t652, i32 1
  store ptr %t655, ptr %t658
  %t659 = getelementptr ptr, ptr %t646, i32 2
  store ptr %t652, ptr %t659
  br label %case.end.4.645
case.end.4.645:
  br label %case.join.629
case.default.628:
  unreachable
case.join.629:
  %t660 = phi ptr [ %t632, %case.end.3.631 ], [ %t646, %case.end.4.645 ]
  call void @__free_recursive(ptr %t624)
  br label %join.end.661
join.end.661:
  br label %join.after.2
join.after.2:
  %t662 = phi ptr [ %t26, %join.val.38 ], [ %t660, %join.end.661 ]
  call void @__free_recursive(ptr %t0)
  ret ptr %t662
}

define i32 @main(i32 %argc, ptr %argv) {
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
