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
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"err" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"ok:" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [10 x i8]} { i32 0, i32 0, i32 0, i32 10, i32 10, [10 x i8] c"4294967295" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [10 x i8]} { i32 0, i32 0, i32 0, i32 10, i32 10, [10 x i8] c"4294967296" }
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"-1" }
@.str.6 = private unnamed_addr constant {i32, i32, i32, i32, i32, [0 x i8]} { i32 0, i32 0, i32 0, i32 0, i32 0, [0 x i8] zeroinitializer }
@.str.7 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"abc" }
@.str.8 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c" 5" }
@.str.9 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"12a" }
@.str.10 = private unnamed_addr constant {i32, i32, i32, i32, i32, [10 x i8]} { i32 0, i32 0, i32 0, i32 10, i32 10, [10 x i8] c"2147483648" }
@.str.11 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c", " }
@.str.12 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }

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

define internal ptr @v_res() {
  %t0 = call ptr @__parseUInt32(ptr getelementptr inbounds (i8, ptr @.str.0, i64 12))
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 3, label %case.arm.3.6 i64 4, label %case.arm.4.12 ]
case.arm.3.6:
  %t8 = call ptr @__alloc(i64 16, i32 1)
  %t9 = inttoptr i64 4 to ptr
  %t10 = getelementptr ptr, ptr %t8, i32 0
  store ptr %t9, ptr %t10
  %t11 = getelementptr ptr, ptr %t8, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t11
  br label %case.end.3.7
case.end.3.7:
  br label %case.join.5
case.arm.4.12:
  %t14 = getelementptr ptr, ptr %t0, i32 1
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  %t16 = call ptr @__showUInt32(ptr %t15)
  %t17 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t16)
  br label %case.end.4.13
case.end.4.13:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t18 = phi ptr [ %t8, %case.end.3.7 ], [ %t17, %case.end.4.13 ]
  %t19 = getelementptr ptr, ptr %t18, i32 0
  %t20 = load ptr, ptr %t19
  %t21 = ptrtoint ptr %t20 to i64
  switch i64 %t21, label %case.default.22 [ i64 3, label %case.arm.3.24 i64 4, label %case.arm.4.32 ]
case.arm.3.24:
  %t26 = getelementptr ptr, ptr %t18, i32 1
  %t27 = load ptr, ptr %t26
  call void @__inc_ref(ptr %t27)
  %t28 = call ptr @__alloc(i64 16, i32 1)
  %t29 = inttoptr i64 3 to ptr
  %t30 = getelementptr ptr, ptr %t28, i32 0
  store ptr %t29, ptr %t30
  call void @__inc_ref(ptr %t27)
  %t31 = getelementptr ptr, ptr %t28, i32 1
  store ptr %t27, ptr %t31
  br label %case.end.3.25
case.end.3.25:
  br label %case.join.23
case.arm.4.32:
  %t34 = getelementptr ptr, ptr %t18, i32 1
  %t35 = load ptr, ptr %t34
  call void @__inc_ref(ptr %t35)
  %t36 = call ptr @__parseUInt32(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12))
  %t37 = getelementptr ptr, ptr %t36, i32 0
  %t38 = load ptr, ptr %t37
  %t39 = ptrtoint ptr %t38 to i64
  switch i64 %t39, label %case.default.40 [ i64 3, label %case.arm.3.42 i64 4, label %case.arm.4.48 ]
case.arm.3.42:
  %t44 = call ptr @__alloc(i64 16, i32 1)
  %t45 = inttoptr i64 4 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  %t47 = getelementptr ptr, ptr %t44, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t47
  br label %case.end.3.43
case.end.3.43:
  br label %case.join.41
case.arm.4.48:
  %t50 = getelementptr ptr, ptr %t36, i32 1
  %t51 = load ptr, ptr %t50
  call void @__inc_ref(ptr %t51)
  %t52 = call ptr @__showUInt32(ptr %t51)
  %t53 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t52)
  br label %case.end.4.49
case.end.4.49:
  br label %case.join.41
case.default.40:
  unreachable
case.join.41:
  %t54 = phi ptr [ %t44, %case.end.3.43 ], [ %t53, %case.end.4.49 ]
  %t55 = getelementptr ptr, ptr %t54, i32 0
  %t56 = load ptr, ptr %t55
  %t57 = ptrtoint ptr %t56 to i64
  switch i64 %t57, label %case.default.58 [ i64 3, label %case.arm.3.60 i64 4, label %case.arm.4.68 ]
case.arm.3.60:
  %t62 = getelementptr ptr, ptr %t54, i32 1
  %t63 = load ptr, ptr %t62
  call void @__inc_ref(ptr %t63)
  %t64 = call ptr @__alloc(i64 16, i32 1)
  %t65 = inttoptr i64 3 to ptr
  %t66 = getelementptr ptr, ptr %t64, i32 0
  store ptr %t65, ptr %t66
  call void @__inc_ref(ptr %t63)
  %t67 = getelementptr ptr, ptr %t64, i32 1
  store ptr %t63, ptr %t67
  br label %case.end.3.61
case.end.3.61:
  br label %case.join.59
case.arm.4.68:
  %t70 = getelementptr ptr, ptr %t54, i32 1
  %t71 = load ptr, ptr %t70
  call void @__inc_ref(ptr %t71)
  %t72 = call ptr @__parseUInt32(ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  %t73 = getelementptr ptr, ptr %t72, i32 0
  %t74 = load ptr, ptr %t73
  %t75 = ptrtoint ptr %t74 to i64
  switch i64 %t75, label %case.default.76 [ i64 3, label %case.arm.3.78 i64 4, label %case.arm.4.84 ]
case.arm.3.78:
  %t80 = call ptr @__alloc(i64 16, i32 1)
  %t81 = inttoptr i64 4 to ptr
  %t82 = getelementptr ptr, ptr %t80, i32 0
  store ptr %t81, ptr %t82
  %t83 = getelementptr ptr, ptr %t80, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t83
  br label %case.end.3.79
case.end.3.79:
  br label %case.join.77
case.arm.4.84:
  %t86 = getelementptr ptr, ptr %t72, i32 1
  %t87 = load ptr, ptr %t86
  call void @__inc_ref(ptr %t87)
  %t88 = call ptr @__showUInt32(ptr %t87)
  %t89 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t88)
  br label %case.end.4.85
case.end.4.85:
  br label %case.join.77
case.default.76:
  unreachable
case.join.77:
  %t90 = phi ptr [ %t80, %case.end.3.79 ], [ %t89, %case.end.4.85 ]
  %t91 = getelementptr ptr, ptr %t90, i32 0
  %t92 = load ptr, ptr %t91
  %t93 = ptrtoint ptr %t92 to i64
  switch i64 %t93, label %case.default.94 [ i64 3, label %case.arm.3.96 i64 4, label %case.arm.4.104 ]
case.arm.3.96:
  %t98 = getelementptr ptr, ptr %t90, i32 1
  %t99 = load ptr, ptr %t98
  call void @__inc_ref(ptr %t99)
  %t100 = call ptr @__alloc(i64 16, i32 1)
  %t101 = inttoptr i64 3 to ptr
  %t102 = getelementptr ptr, ptr %t100, i32 0
  store ptr %t101, ptr %t102
  call void @__inc_ref(ptr %t99)
  %t103 = getelementptr ptr, ptr %t100, i32 1
  store ptr %t99, ptr %t103
  br label %case.end.3.97
case.end.3.97:
  br label %case.join.95
case.arm.4.104:
  %t106 = getelementptr ptr, ptr %t90, i32 1
  %t107 = load ptr, ptr %t106
  call void @__inc_ref(ptr %t107)
  %t108 = call ptr @__parseUInt32(ptr getelementptr inbounds (i8, ptr @.str.5, i64 12))
  %t109 = getelementptr ptr, ptr %t108, i32 0
  %t110 = load ptr, ptr %t109
  %t111 = ptrtoint ptr %t110 to i64
  switch i64 %t111, label %case.default.112 [ i64 3, label %case.arm.3.114 i64 4, label %case.arm.4.120 ]
case.arm.3.114:
  %t116 = call ptr @__alloc(i64 16, i32 1)
  %t117 = inttoptr i64 4 to ptr
  %t118 = getelementptr ptr, ptr %t116, i32 0
  store ptr %t117, ptr %t118
  %t119 = getelementptr ptr, ptr %t116, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t119
  br label %case.end.3.115
case.end.3.115:
  br label %case.join.113
case.arm.4.120:
  %t122 = getelementptr ptr, ptr %t108, i32 1
  %t123 = load ptr, ptr %t122
  call void @__inc_ref(ptr %t123)
  %t124 = call ptr @__showUInt32(ptr %t123)
  %t125 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t124)
  br label %case.end.4.121
case.end.4.121:
  br label %case.join.113
case.default.112:
  unreachable
case.join.113:
  %t126 = phi ptr [ %t116, %case.end.3.115 ], [ %t125, %case.end.4.121 ]
  %t127 = getelementptr ptr, ptr %t126, i32 0
  %t128 = load ptr, ptr %t127
  %t129 = ptrtoint ptr %t128 to i64
  switch i64 %t129, label %case.default.130 [ i64 3, label %case.arm.3.132 i64 4, label %case.arm.4.140 ]
case.arm.3.132:
  %t134 = getelementptr ptr, ptr %t126, i32 1
  %t135 = load ptr, ptr %t134
  call void @__inc_ref(ptr %t135)
  %t136 = call ptr @__alloc(i64 16, i32 1)
  %t137 = inttoptr i64 3 to ptr
  %t138 = getelementptr ptr, ptr %t136, i32 0
  store ptr %t137, ptr %t138
  call void @__inc_ref(ptr %t135)
  %t139 = getelementptr ptr, ptr %t136, i32 1
  store ptr %t135, ptr %t139
  br label %case.end.3.133
case.end.3.133:
  br label %case.join.131
case.arm.4.140:
  %t142 = getelementptr ptr, ptr %t126, i32 1
  %t143 = load ptr, ptr %t142
  call void @__inc_ref(ptr %t143)
  %t144 = call ptr @__parseUInt32(ptr getelementptr inbounds (i8, ptr @.str.6, i64 12))
  %t145 = getelementptr ptr, ptr %t144, i32 0
  %t146 = load ptr, ptr %t145
  %t147 = ptrtoint ptr %t146 to i64
  switch i64 %t147, label %case.default.148 [ i64 3, label %case.arm.3.150 i64 4, label %case.arm.4.156 ]
case.arm.3.150:
  %t152 = call ptr @__alloc(i64 16, i32 1)
  %t153 = inttoptr i64 4 to ptr
  %t154 = getelementptr ptr, ptr %t152, i32 0
  store ptr %t153, ptr %t154
  %t155 = getelementptr ptr, ptr %t152, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t155
  br label %case.end.3.151
case.end.3.151:
  br label %case.join.149
case.arm.4.156:
  %t158 = getelementptr ptr, ptr %t144, i32 1
  %t159 = load ptr, ptr %t158
  call void @__inc_ref(ptr %t159)
  %t160 = call ptr @__showUInt32(ptr %t159)
  %t161 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t160)
  br label %case.end.4.157
case.end.4.157:
  br label %case.join.149
case.default.148:
  unreachable
case.join.149:
  %t162 = phi ptr [ %t152, %case.end.3.151 ], [ %t161, %case.end.4.157 ]
  %t163 = getelementptr ptr, ptr %t162, i32 0
  %t164 = load ptr, ptr %t163
  %t165 = ptrtoint ptr %t164 to i64
  switch i64 %t165, label %case.default.166 [ i64 3, label %case.arm.3.168 i64 4, label %case.arm.4.176 ]
case.arm.3.168:
  %t170 = getelementptr ptr, ptr %t162, i32 1
  %t171 = load ptr, ptr %t170
  call void @__inc_ref(ptr %t171)
  %t172 = call ptr @__alloc(i64 16, i32 1)
  %t173 = inttoptr i64 3 to ptr
  %t174 = getelementptr ptr, ptr %t172, i32 0
  store ptr %t173, ptr %t174
  call void @__inc_ref(ptr %t171)
  %t175 = getelementptr ptr, ptr %t172, i32 1
  store ptr %t171, ptr %t175
  br label %case.end.3.169
case.end.3.169:
  br label %case.join.167
case.arm.4.176:
  %t178 = getelementptr ptr, ptr %t162, i32 1
  %t179 = load ptr, ptr %t178
  call void @__inc_ref(ptr %t179)
  %t180 = call ptr @__parseUInt32(ptr getelementptr inbounds (i8, ptr @.str.7, i64 12))
  %t181 = getelementptr ptr, ptr %t180, i32 0
  %t182 = load ptr, ptr %t181
  %t183 = ptrtoint ptr %t182 to i64
  switch i64 %t183, label %case.default.184 [ i64 3, label %case.arm.3.186 i64 4, label %case.arm.4.192 ]
case.arm.3.186:
  %t188 = call ptr @__alloc(i64 16, i32 1)
  %t189 = inttoptr i64 4 to ptr
  %t190 = getelementptr ptr, ptr %t188, i32 0
  store ptr %t189, ptr %t190
  %t191 = getelementptr ptr, ptr %t188, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t191
  br label %case.end.3.187
case.end.3.187:
  br label %case.join.185
case.arm.4.192:
  %t194 = getelementptr ptr, ptr %t180, i32 1
  %t195 = load ptr, ptr %t194
  call void @__inc_ref(ptr %t195)
  %t196 = call ptr @__showUInt32(ptr %t195)
  %t197 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t196)
  br label %case.end.4.193
case.end.4.193:
  br label %case.join.185
case.default.184:
  unreachable
case.join.185:
  %t198 = phi ptr [ %t188, %case.end.3.187 ], [ %t197, %case.end.4.193 ]
  %t199 = getelementptr ptr, ptr %t198, i32 0
  %t200 = load ptr, ptr %t199
  %t201 = ptrtoint ptr %t200 to i64
  switch i64 %t201, label %case.default.202 [ i64 3, label %case.arm.3.204 i64 4, label %case.arm.4.212 ]
case.arm.3.204:
  %t206 = getelementptr ptr, ptr %t198, i32 1
  %t207 = load ptr, ptr %t206
  call void @__inc_ref(ptr %t207)
  %t208 = call ptr @__alloc(i64 16, i32 1)
  %t209 = inttoptr i64 3 to ptr
  %t210 = getelementptr ptr, ptr %t208, i32 0
  store ptr %t209, ptr %t210
  call void @__inc_ref(ptr %t207)
  %t211 = getelementptr ptr, ptr %t208, i32 1
  store ptr %t207, ptr %t211
  br label %case.end.3.205
case.end.3.205:
  br label %case.join.203
case.arm.4.212:
  %t214 = getelementptr ptr, ptr %t198, i32 1
  %t215 = load ptr, ptr %t214
  call void @__inc_ref(ptr %t215)
  %t216 = call ptr @__parseUInt32(ptr getelementptr inbounds (i8, ptr @.str.8, i64 12))
  %t217 = getelementptr ptr, ptr %t216, i32 0
  %t218 = load ptr, ptr %t217
  %t219 = ptrtoint ptr %t218 to i64
  switch i64 %t219, label %case.default.220 [ i64 3, label %case.arm.3.222 i64 4, label %case.arm.4.228 ]
case.arm.3.222:
  %t224 = call ptr @__alloc(i64 16, i32 1)
  %t225 = inttoptr i64 4 to ptr
  %t226 = getelementptr ptr, ptr %t224, i32 0
  store ptr %t225, ptr %t226
  %t227 = getelementptr ptr, ptr %t224, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t227
  br label %case.end.3.223
case.end.3.223:
  br label %case.join.221
case.arm.4.228:
  %t230 = getelementptr ptr, ptr %t216, i32 1
  %t231 = load ptr, ptr %t230
  call void @__inc_ref(ptr %t231)
  %t232 = call ptr @__showUInt32(ptr %t231)
  %t233 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t232)
  br label %case.end.4.229
case.end.4.229:
  br label %case.join.221
case.default.220:
  unreachable
case.join.221:
  %t234 = phi ptr [ %t224, %case.end.3.223 ], [ %t233, %case.end.4.229 ]
  %t235 = getelementptr ptr, ptr %t234, i32 0
  %t236 = load ptr, ptr %t235
  %t237 = ptrtoint ptr %t236 to i64
  switch i64 %t237, label %case.default.238 [ i64 3, label %case.arm.3.240 i64 4, label %case.arm.4.248 ]
case.arm.3.240:
  %t242 = getelementptr ptr, ptr %t234, i32 1
  %t243 = load ptr, ptr %t242
  call void @__inc_ref(ptr %t243)
  %t244 = call ptr @__alloc(i64 16, i32 1)
  %t245 = inttoptr i64 3 to ptr
  %t246 = getelementptr ptr, ptr %t244, i32 0
  store ptr %t245, ptr %t246
  call void @__inc_ref(ptr %t243)
  %t247 = getelementptr ptr, ptr %t244, i32 1
  store ptr %t243, ptr %t247
  br label %case.end.3.241
case.end.3.241:
  br label %case.join.239
case.arm.4.248:
  %t250 = getelementptr ptr, ptr %t234, i32 1
  %t251 = load ptr, ptr %t250
  call void @__inc_ref(ptr %t251)
  %t252 = call ptr @__parseUInt32(ptr getelementptr inbounds (i8, ptr @.str.9, i64 12))
  %t253 = getelementptr ptr, ptr %t252, i32 0
  %t254 = load ptr, ptr %t253
  %t255 = ptrtoint ptr %t254 to i64
  switch i64 %t255, label %case.default.256 [ i64 3, label %case.arm.3.258 i64 4, label %case.arm.4.264 ]
case.arm.3.258:
  %t260 = call ptr @__alloc(i64 16, i32 1)
  %t261 = inttoptr i64 4 to ptr
  %t262 = getelementptr ptr, ptr %t260, i32 0
  store ptr %t261, ptr %t262
  %t263 = getelementptr ptr, ptr %t260, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t263
  br label %case.end.3.259
case.end.3.259:
  br label %case.join.257
case.arm.4.264:
  %t266 = getelementptr ptr, ptr %t252, i32 1
  %t267 = load ptr, ptr %t266
  call void @__inc_ref(ptr %t267)
  %t268 = call ptr @__showUInt32(ptr %t267)
  %t269 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t268)
  br label %case.end.4.265
case.end.4.265:
  br label %case.join.257
case.default.256:
  unreachable
case.join.257:
  %t270 = phi ptr [ %t260, %case.end.3.259 ], [ %t269, %case.end.4.265 ]
  %t271 = getelementptr ptr, ptr %t270, i32 0
  %t272 = load ptr, ptr %t271
  %t273 = ptrtoint ptr %t272 to i64
  switch i64 %t273, label %case.default.274 [ i64 3, label %case.arm.3.276 i64 4, label %case.arm.4.284 ]
case.arm.3.276:
  %t278 = getelementptr ptr, ptr %t270, i32 1
  %t279 = load ptr, ptr %t278
  call void @__inc_ref(ptr %t279)
  %t280 = call ptr @__alloc(i64 16, i32 1)
  %t281 = inttoptr i64 3 to ptr
  %t282 = getelementptr ptr, ptr %t280, i32 0
  store ptr %t281, ptr %t282
  call void @__inc_ref(ptr %t279)
  %t283 = getelementptr ptr, ptr %t280, i32 1
  store ptr %t279, ptr %t283
  br label %case.end.3.277
case.end.3.277:
  br label %case.join.275
case.arm.4.284:
  %t286 = getelementptr ptr, ptr %t270, i32 1
  %t287 = load ptr, ptr %t286
  call void @__inc_ref(ptr %t287)
  %t288 = call ptr @__parseUInt32(ptr getelementptr inbounds (i8, ptr @.str.10, i64 12))
  %t289 = getelementptr ptr, ptr %t288, i32 0
  %t290 = load ptr, ptr %t289
  %t291 = ptrtoint ptr %t290 to i64
  switch i64 %t291, label %case.default.292 [ i64 3, label %case.arm.3.294 i64 4, label %case.arm.4.300 ]
case.arm.3.294:
  %t296 = call ptr @__alloc(i64 16, i32 1)
  %t297 = inttoptr i64 4 to ptr
  %t298 = getelementptr ptr, ptr %t296, i32 0
  store ptr %t297, ptr %t298
  %t299 = getelementptr ptr, ptr %t296, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t299
  br label %case.end.3.295
case.end.3.295:
  br label %case.join.293
case.arm.4.300:
  %t302 = getelementptr ptr, ptr %t288, i32 1
  %t303 = load ptr, ptr %t302
  call void @__inc_ref(ptr %t303)
  %t304 = call ptr @__showUInt32(ptr %t303)
  %t305 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t304)
  br label %case.end.4.301
case.end.4.301:
  br label %case.join.293
case.default.292:
  unreachable
case.join.293:
  %t306 = phi ptr [ %t296, %case.end.3.295 ], [ %t305, %case.end.4.301 ]
  %t307 = getelementptr ptr, ptr %t306, i32 0
  %t308 = load ptr, ptr %t307
  %t309 = ptrtoint ptr %t308 to i64
  switch i64 %t309, label %case.default.310 [ i64 3, label %case.arm.3.312 i64 4, label %case.arm.4.320 ]
case.arm.3.312:
  %t314 = getelementptr ptr, ptr %t306, i32 1
  %t315 = load ptr, ptr %t314
  call void @__inc_ref(ptr %t315)
  %t316 = call ptr @__alloc(i64 16, i32 1)
  %t317 = inttoptr i64 3 to ptr
  %t318 = getelementptr ptr, ptr %t316, i32 0
  store ptr %t317, ptr %t318
  call void @__inc_ref(ptr %t315)
  %t319 = getelementptr ptr, ptr %t316, i32 1
  store ptr %t315, ptr %t319
  br label %case.end.3.313
case.end.3.313:
  br label %case.join.311
case.arm.4.320:
  %t322 = getelementptr ptr, ptr %t306, i32 1
  %t323 = load ptr, ptr %t322
  call void @__inc_ref(ptr %t323)
  call void @__inc_ref(ptr %t35)
  %t324 = call ptr @__concat(ptr %t35, ptr getelementptr inbounds (i8, ptr @.str.11, i64 12))
  %t325 = getelementptr ptr, ptr %t324, i32 0
  %t326 = load ptr, ptr %t325
  %t327 = ptrtoint ptr %t326 to i64
  switch i64 %t327, label %case.default.328 [ i64 3, label %case.arm.3.330 i64 4, label %case.arm.4.338 ]
case.arm.3.330:
  %t332 = getelementptr ptr, ptr %t324, i32 1
  %t333 = load ptr, ptr %t332
  call void @__inc_ref(ptr %t333)
  %t334 = call ptr @__alloc(i64 16, i32 1)
  %t335 = inttoptr i64 3 to ptr
  %t336 = getelementptr ptr, ptr %t334, i32 0
  store ptr %t335, ptr %t336
  call void @__inc_ref(ptr %t333)
  %t337 = getelementptr ptr, ptr %t334, i32 1
  store ptr %t333, ptr %t337
  br label %case.end.3.331
case.end.3.331:
  br label %case.join.329
case.arm.4.338:
  %t340 = getelementptr ptr, ptr %t324, i32 1
  %t341 = load ptr, ptr %t340
  call void @__inc_ref(ptr %t341)
  call void @__inc_ref(ptr %t341)
  call void @__inc_ref(ptr %t71)
  %t342 = call ptr @__concat(ptr %t341, ptr %t71)
  %t343 = getelementptr ptr, ptr %t342, i32 0
  %t344 = load ptr, ptr %t343
  %t345 = ptrtoint ptr %t344 to i64
  switch i64 %t345, label %case.default.346 [ i64 3, label %case.arm.3.348 i64 4, label %case.arm.4.356 ]
case.arm.3.348:
  %t350 = getelementptr ptr, ptr %t342, i32 1
  %t351 = load ptr, ptr %t350
  call void @__inc_ref(ptr %t351)
  %t352 = call ptr @__alloc(i64 16, i32 1)
  %t353 = inttoptr i64 3 to ptr
  %t354 = getelementptr ptr, ptr %t352, i32 0
  store ptr %t353, ptr %t354
  call void @__inc_ref(ptr %t351)
  %t355 = getelementptr ptr, ptr %t352, i32 1
  store ptr %t351, ptr %t355
  br label %case.end.3.349
case.end.3.349:
  br label %case.join.347
case.arm.4.356:
  %t358 = getelementptr ptr, ptr %t342, i32 1
  %t359 = load ptr, ptr %t358
  call void @__inc_ref(ptr %t359)
  call void @__inc_ref(ptr %t359)
  %t360 = call ptr @__concat(ptr %t359, ptr getelementptr inbounds (i8, ptr @.str.11, i64 12))
  %t361 = getelementptr ptr, ptr %t360, i32 0
  %t362 = load ptr, ptr %t361
  %t363 = ptrtoint ptr %t362 to i64
  switch i64 %t363, label %case.default.364 [ i64 3, label %case.arm.3.366 i64 4, label %case.arm.4.374 ]
case.arm.3.366:
  %t368 = getelementptr ptr, ptr %t360, i32 1
  %t369 = load ptr, ptr %t368
  call void @__inc_ref(ptr %t369)
  %t370 = call ptr @__alloc(i64 16, i32 1)
  %t371 = inttoptr i64 3 to ptr
  %t372 = getelementptr ptr, ptr %t370, i32 0
  store ptr %t371, ptr %t372
  call void @__inc_ref(ptr %t369)
  %t373 = getelementptr ptr, ptr %t370, i32 1
  store ptr %t369, ptr %t373
  br label %case.end.3.367
case.end.3.367:
  br label %case.join.365
case.arm.4.374:
  %t376 = getelementptr ptr, ptr %t360, i32 1
  %t377 = load ptr, ptr %t376
  call void @__inc_ref(ptr %t377)
  call void @__inc_ref(ptr %t377)
  call void @__inc_ref(ptr %t107)
  %t378 = call ptr @__concat(ptr %t377, ptr %t107)
  %t379 = getelementptr ptr, ptr %t378, i32 0
  %t380 = load ptr, ptr %t379
  %t381 = ptrtoint ptr %t380 to i64
  switch i64 %t381, label %case.default.382 [ i64 3, label %case.arm.3.384 i64 4, label %case.arm.4.392 ]
case.arm.3.384:
  %t386 = getelementptr ptr, ptr %t378, i32 1
  %t387 = load ptr, ptr %t386
  call void @__inc_ref(ptr %t387)
  %t388 = call ptr @__alloc(i64 16, i32 1)
  %t389 = inttoptr i64 3 to ptr
  %t390 = getelementptr ptr, ptr %t388, i32 0
  store ptr %t389, ptr %t390
  call void @__inc_ref(ptr %t387)
  %t391 = getelementptr ptr, ptr %t388, i32 1
  store ptr %t387, ptr %t391
  br label %case.end.3.385
case.end.3.385:
  br label %case.join.383
case.arm.4.392:
  %t394 = getelementptr ptr, ptr %t378, i32 1
  %t395 = load ptr, ptr %t394
  call void @__inc_ref(ptr %t395)
  call void @__inc_ref(ptr %t395)
  %t396 = call ptr @__concat(ptr %t395, ptr getelementptr inbounds (i8, ptr @.str.11, i64 12))
  %t397 = getelementptr ptr, ptr %t396, i32 0
  %t398 = load ptr, ptr %t397
  %t399 = ptrtoint ptr %t398 to i64
  switch i64 %t399, label %case.default.400 [ i64 3, label %case.arm.3.402 i64 4, label %case.arm.4.410 ]
case.arm.3.402:
  %t404 = getelementptr ptr, ptr %t396, i32 1
  %t405 = load ptr, ptr %t404
  call void @__inc_ref(ptr %t405)
  %t406 = call ptr @__alloc(i64 16, i32 1)
  %t407 = inttoptr i64 3 to ptr
  %t408 = getelementptr ptr, ptr %t406, i32 0
  store ptr %t407, ptr %t408
  call void @__inc_ref(ptr %t405)
  %t409 = getelementptr ptr, ptr %t406, i32 1
  store ptr %t405, ptr %t409
  br label %case.end.3.403
case.end.3.403:
  br label %case.join.401
case.arm.4.410:
  %t412 = getelementptr ptr, ptr %t396, i32 1
  %t413 = load ptr, ptr %t412
  call void @__inc_ref(ptr %t413)
  call void @__inc_ref(ptr %t413)
  call void @__inc_ref(ptr %t143)
  %t414 = call ptr @__concat(ptr %t413, ptr %t143)
  %t415 = getelementptr ptr, ptr %t414, i32 0
  %t416 = load ptr, ptr %t415
  %t417 = ptrtoint ptr %t416 to i64
  switch i64 %t417, label %case.default.418 [ i64 3, label %case.arm.3.420 i64 4, label %case.arm.4.428 ]
case.arm.3.420:
  %t422 = getelementptr ptr, ptr %t414, i32 1
  %t423 = load ptr, ptr %t422
  call void @__inc_ref(ptr %t423)
  %t424 = call ptr @__alloc(i64 16, i32 1)
  %t425 = inttoptr i64 3 to ptr
  %t426 = getelementptr ptr, ptr %t424, i32 0
  store ptr %t425, ptr %t426
  call void @__inc_ref(ptr %t423)
  %t427 = getelementptr ptr, ptr %t424, i32 1
  store ptr %t423, ptr %t427
  br label %case.end.3.421
case.end.3.421:
  br label %case.join.419
case.arm.4.428:
  %t430 = getelementptr ptr, ptr %t414, i32 1
  %t431 = load ptr, ptr %t430
  call void @__inc_ref(ptr %t431)
  call void @__inc_ref(ptr %t431)
  %t432 = call ptr @__concat(ptr %t431, ptr getelementptr inbounds (i8, ptr @.str.11, i64 12))
  %t433 = getelementptr ptr, ptr %t432, i32 0
  %t434 = load ptr, ptr %t433
  %t435 = ptrtoint ptr %t434 to i64
  switch i64 %t435, label %case.default.436 [ i64 3, label %case.arm.3.438 i64 4, label %case.arm.4.446 ]
case.arm.3.438:
  %t440 = getelementptr ptr, ptr %t432, i32 1
  %t441 = load ptr, ptr %t440
  call void @__inc_ref(ptr %t441)
  %t442 = call ptr @__alloc(i64 16, i32 1)
  %t443 = inttoptr i64 3 to ptr
  %t444 = getelementptr ptr, ptr %t442, i32 0
  store ptr %t443, ptr %t444
  call void @__inc_ref(ptr %t441)
  %t445 = getelementptr ptr, ptr %t442, i32 1
  store ptr %t441, ptr %t445
  br label %case.end.3.439
case.end.3.439:
  br label %case.join.437
case.arm.4.446:
  %t448 = getelementptr ptr, ptr %t432, i32 1
  %t449 = load ptr, ptr %t448
  call void @__inc_ref(ptr %t449)
  call void @__inc_ref(ptr %t449)
  call void @__inc_ref(ptr %t179)
  %t450 = call ptr @__concat(ptr %t449, ptr %t179)
  %t451 = getelementptr ptr, ptr %t450, i32 0
  %t452 = load ptr, ptr %t451
  %t453 = ptrtoint ptr %t452 to i64
  switch i64 %t453, label %case.default.454 [ i64 3, label %case.arm.3.456 i64 4, label %case.arm.4.464 ]
case.arm.3.456:
  %t458 = getelementptr ptr, ptr %t450, i32 1
  %t459 = load ptr, ptr %t458
  call void @__inc_ref(ptr %t459)
  %t460 = call ptr @__alloc(i64 16, i32 1)
  %t461 = inttoptr i64 3 to ptr
  %t462 = getelementptr ptr, ptr %t460, i32 0
  store ptr %t461, ptr %t462
  call void @__inc_ref(ptr %t459)
  %t463 = getelementptr ptr, ptr %t460, i32 1
  store ptr %t459, ptr %t463
  br label %case.end.3.457
case.end.3.457:
  br label %case.join.455
case.arm.4.464:
  %t466 = getelementptr ptr, ptr %t450, i32 1
  %t467 = load ptr, ptr %t466
  call void @__inc_ref(ptr %t467)
  call void @__inc_ref(ptr %t467)
  %t468 = call ptr @__concat(ptr %t467, ptr getelementptr inbounds (i8, ptr @.str.11, i64 12))
  %t469 = getelementptr ptr, ptr %t468, i32 0
  %t470 = load ptr, ptr %t469
  %t471 = ptrtoint ptr %t470 to i64
  switch i64 %t471, label %case.default.472 [ i64 3, label %case.arm.3.474 i64 4, label %case.arm.4.482 ]
case.arm.3.474:
  %t476 = getelementptr ptr, ptr %t468, i32 1
  %t477 = load ptr, ptr %t476
  call void @__inc_ref(ptr %t477)
  %t478 = call ptr @__alloc(i64 16, i32 1)
  %t479 = inttoptr i64 3 to ptr
  %t480 = getelementptr ptr, ptr %t478, i32 0
  store ptr %t479, ptr %t480
  call void @__inc_ref(ptr %t477)
  %t481 = getelementptr ptr, ptr %t478, i32 1
  store ptr %t477, ptr %t481
  br label %case.end.3.475
case.end.3.475:
  br label %case.join.473
case.arm.4.482:
  %t484 = getelementptr ptr, ptr %t468, i32 1
  %t485 = load ptr, ptr %t484
  call void @__inc_ref(ptr %t485)
  call void @__inc_ref(ptr %t485)
  call void @__inc_ref(ptr %t215)
  %t486 = call ptr @__concat(ptr %t485, ptr %t215)
  %t487 = getelementptr ptr, ptr %t486, i32 0
  %t488 = load ptr, ptr %t487
  %t489 = ptrtoint ptr %t488 to i64
  switch i64 %t489, label %case.default.490 [ i64 3, label %case.arm.3.492 i64 4, label %case.arm.4.500 ]
case.arm.3.492:
  %t494 = getelementptr ptr, ptr %t486, i32 1
  %t495 = load ptr, ptr %t494
  call void @__inc_ref(ptr %t495)
  %t496 = call ptr @__alloc(i64 16, i32 1)
  %t497 = inttoptr i64 3 to ptr
  %t498 = getelementptr ptr, ptr %t496, i32 0
  store ptr %t497, ptr %t498
  call void @__inc_ref(ptr %t495)
  %t499 = getelementptr ptr, ptr %t496, i32 1
  store ptr %t495, ptr %t499
  br label %case.end.3.493
case.end.3.493:
  br label %case.join.491
case.arm.4.500:
  %t502 = getelementptr ptr, ptr %t486, i32 1
  %t503 = load ptr, ptr %t502
  call void @__inc_ref(ptr %t503)
  call void @__inc_ref(ptr %t503)
  %t504 = call ptr @__concat(ptr %t503, ptr getelementptr inbounds (i8, ptr @.str.11, i64 12))
  %t505 = getelementptr ptr, ptr %t504, i32 0
  %t506 = load ptr, ptr %t505
  %t507 = ptrtoint ptr %t506 to i64
  switch i64 %t507, label %case.default.508 [ i64 3, label %case.arm.3.510 i64 4, label %case.arm.4.518 ]
case.arm.3.510:
  %t512 = getelementptr ptr, ptr %t504, i32 1
  %t513 = load ptr, ptr %t512
  call void @__inc_ref(ptr %t513)
  %t514 = call ptr @__alloc(i64 16, i32 1)
  %t515 = inttoptr i64 3 to ptr
  %t516 = getelementptr ptr, ptr %t514, i32 0
  store ptr %t515, ptr %t516
  call void @__inc_ref(ptr %t513)
  %t517 = getelementptr ptr, ptr %t514, i32 1
  store ptr %t513, ptr %t517
  br label %case.end.3.511
case.end.3.511:
  br label %case.join.509
case.arm.4.518:
  %t520 = getelementptr ptr, ptr %t504, i32 1
  %t521 = load ptr, ptr %t520
  call void @__inc_ref(ptr %t521)
  call void @__inc_ref(ptr %t521)
  call void @__inc_ref(ptr %t251)
  %t522 = call ptr @__concat(ptr %t521, ptr %t251)
  %t523 = getelementptr ptr, ptr %t522, i32 0
  %t524 = load ptr, ptr %t523
  %t525 = ptrtoint ptr %t524 to i64
  switch i64 %t525, label %case.default.526 [ i64 3, label %case.arm.3.528 i64 4, label %case.arm.4.536 ]
case.arm.3.528:
  %t530 = getelementptr ptr, ptr %t522, i32 1
  %t531 = load ptr, ptr %t530
  call void @__inc_ref(ptr %t531)
  %t532 = call ptr @__alloc(i64 16, i32 1)
  %t533 = inttoptr i64 3 to ptr
  %t534 = getelementptr ptr, ptr %t532, i32 0
  store ptr %t533, ptr %t534
  call void @__inc_ref(ptr %t531)
  %t535 = getelementptr ptr, ptr %t532, i32 1
  store ptr %t531, ptr %t535
  br label %case.end.3.529
case.end.3.529:
  br label %case.join.527
case.arm.4.536:
  %t538 = getelementptr ptr, ptr %t522, i32 1
  %t539 = load ptr, ptr %t538
  call void @__inc_ref(ptr %t539)
  call void @__inc_ref(ptr %t539)
  %t540 = call ptr @__concat(ptr %t539, ptr getelementptr inbounds (i8, ptr @.str.11, i64 12))
  %t541 = getelementptr ptr, ptr %t540, i32 0
  %t542 = load ptr, ptr %t541
  %t543 = ptrtoint ptr %t542 to i64
  switch i64 %t543, label %case.default.544 [ i64 3, label %case.arm.3.546 i64 4, label %case.arm.4.554 ]
case.arm.3.546:
  %t548 = getelementptr ptr, ptr %t540, i32 1
  %t549 = load ptr, ptr %t548
  call void @__inc_ref(ptr %t549)
  %t550 = call ptr @__alloc(i64 16, i32 1)
  %t551 = inttoptr i64 3 to ptr
  %t552 = getelementptr ptr, ptr %t550, i32 0
  store ptr %t551, ptr %t552
  call void @__inc_ref(ptr %t549)
  %t553 = getelementptr ptr, ptr %t550, i32 1
  store ptr %t549, ptr %t553
  br label %case.end.3.547
case.end.3.547:
  br label %case.join.545
case.arm.4.554:
  %t556 = getelementptr ptr, ptr %t540, i32 1
  %t557 = load ptr, ptr %t556
  call void @__inc_ref(ptr %t557)
  call void @__inc_ref(ptr %t557)
  call void @__inc_ref(ptr %t287)
  %t558 = call ptr @__concat(ptr %t557, ptr %t287)
  %t559 = getelementptr ptr, ptr %t558, i32 0
  %t560 = load ptr, ptr %t559
  %t561 = ptrtoint ptr %t560 to i64
  switch i64 %t561, label %case.default.562 [ i64 3, label %case.arm.3.564 i64 4, label %case.arm.4.572 ]
case.arm.3.564:
  %t566 = getelementptr ptr, ptr %t558, i32 1
  %t567 = load ptr, ptr %t566
  call void @__inc_ref(ptr %t567)
  %t568 = call ptr @__alloc(i64 16, i32 1)
  %t569 = inttoptr i64 3 to ptr
  %t570 = getelementptr ptr, ptr %t568, i32 0
  store ptr %t569, ptr %t570
  call void @__inc_ref(ptr %t567)
  %t571 = getelementptr ptr, ptr %t568, i32 1
  store ptr %t567, ptr %t571
  br label %case.end.3.565
case.end.3.565:
  br label %case.join.563
case.arm.4.572:
  %t574 = getelementptr ptr, ptr %t558, i32 1
  %t575 = load ptr, ptr %t574
  call void @__inc_ref(ptr %t575)
  call void @__inc_ref(ptr %t575)
  %t576 = call ptr @__concat(ptr %t575, ptr getelementptr inbounds (i8, ptr @.str.11, i64 12))
  %t577 = getelementptr ptr, ptr %t576, i32 0
  %t578 = load ptr, ptr %t577
  %t579 = ptrtoint ptr %t578 to i64
  switch i64 %t579, label %case.default.580 [ i64 3, label %case.arm.3.582 i64 4, label %case.arm.4.590 ]
case.arm.3.582:
  %t584 = getelementptr ptr, ptr %t576, i32 1
  %t585 = load ptr, ptr %t584
  call void @__inc_ref(ptr %t585)
  %t586 = call ptr @__alloc(i64 16, i32 1)
  %t587 = inttoptr i64 3 to ptr
  %t588 = getelementptr ptr, ptr %t586, i32 0
  store ptr %t587, ptr %t588
  call void @__inc_ref(ptr %t585)
  %t589 = getelementptr ptr, ptr %t586, i32 1
  store ptr %t585, ptr %t589
  br label %case.end.3.583
case.end.3.583:
  br label %case.join.581
case.arm.4.590:
  %t592 = getelementptr ptr, ptr %t576, i32 1
  %t593 = load ptr, ptr %t592
  call void @__inc_ref(ptr %t593)
  call void @__inc_ref(ptr %t593)
  call void @__inc_ref(ptr %t323)
  %t594 = call ptr @__concat(ptr %t593, ptr %t323)
  br label %case.end.4.591
case.end.4.591:
  br label %case.join.581
case.default.580:
  unreachable
case.join.581:
  %t595 = phi ptr [ %t586, %case.end.3.583 ], [ %t594, %case.end.4.591 ]
  call void @__free_recursive(ptr %t576)
  br label %case.end.4.573
case.end.4.573:
  br label %case.join.563
case.default.562:
  unreachable
case.join.563:
  %t596 = phi ptr [ %t568, %case.end.3.565 ], [ %t595, %case.end.4.573 ]
  call void @__free_recursive(ptr %t558)
  br label %case.end.4.555
case.end.4.555:
  br label %case.join.545
case.default.544:
  unreachable
case.join.545:
  %t597 = phi ptr [ %t550, %case.end.3.547 ], [ %t596, %case.end.4.555 ]
  call void @__free_recursive(ptr %t540)
  br label %case.end.4.537
case.end.4.537:
  br label %case.join.527
case.default.526:
  unreachable
case.join.527:
  %t598 = phi ptr [ %t532, %case.end.3.529 ], [ %t597, %case.end.4.537 ]
  call void @__free_recursive(ptr %t522)
  br label %case.end.4.519
case.end.4.519:
  br label %case.join.509
case.default.508:
  unreachable
case.join.509:
  %t599 = phi ptr [ %t514, %case.end.3.511 ], [ %t598, %case.end.4.519 ]
  call void @__free_recursive(ptr %t504)
  br label %case.end.4.501
case.end.4.501:
  br label %case.join.491
case.default.490:
  unreachable
case.join.491:
  %t600 = phi ptr [ %t496, %case.end.3.493 ], [ %t599, %case.end.4.501 ]
  call void @__free_recursive(ptr %t486)
  br label %case.end.4.483
case.end.4.483:
  br label %case.join.473
case.default.472:
  unreachable
case.join.473:
  %t601 = phi ptr [ %t478, %case.end.3.475 ], [ %t600, %case.end.4.483 ]
  call void @__free_recursive(ptr %t468)
  br label %case.end.4.465
case.end.4.465:
  br label %case.join.455
case.default.454:
  unreachable
case.join.455:
  %t602 = phi ptr [ %t460, %case.end.3.457 ], [ %t601, %case.end.4.465 ]
  call void @__free_recursive(ptr %t450)
  br label %case.end.4.447
case.end.4.447:
  br label %case.join.437
case.default.436:
  unreachable
case.join.437:
  %t603 = phi ptr [ %t442, %case.end.3.439 ], [ %t602, %case.end.4.447 ]
  call void @__free_recursive(ptr %t432)
  br label %case.end.4.429
case.end.4.429:
  br label %case.join.419
case.default.418:
  unreachable
case.join.419:
  %t604 = phi ptr [ %t424, %case.end.3.421 ], [ %t603, %case.end.4.429 ]
  call void @__free_recursive(ptr %t414)
  br label %case.end.4.411
case.end.4.411:
  br label %case.join.401
case.default.400:
  unreachable
case.join.401:
  %t605 = phi ptr [ %t406, %case.end.3.403 ], [ %t604, %case.end.4.411 ]
  call void @__free_recursive(ptr %t396)
  br label %case.end.4.393
case.end.4.393:
  br label %case.join.383
case.default.382:
  unreachable
case.join.383:
  %t606 = phi ptr [ %t388, %case.end.3.385 ], [ %t605, %case.end.4.393 ]
  call void @__free_recursive(ptr %t378)
  br label %case.end.4.375
case.end.4.375:
  br label %case.join.365
case.default.364:
  unreachable
case.join.365:
  %t607 = phi ptr [ %t370, %case.end.3.367 ], [ %t606, %case.end.4.375 ]
  call void @__free_recursive(ptr %t360)
  br label %case.end.4.357
case.end.4.357:
  br label %case.join.347
case.default.346:
  unreachable
case.join.347:
  %t608 = phi ptr [ %t352, %case.end.3.349 ], [ %t607, %case.end.4.357 ]
  call void @__free_recursive(ptr %t342)
  br label %case.end.4.339
case.end.4.339:
  br label %case.join.329
case.default.328:
  unreachable
case.join.329:
  %t609 = phi ptr [ %t334, %case.end.3.331 ], [ %t608, %case.end.4.339 ]
  call void @__free_recursive(ptr %t324)
  br label %case.end.4.321
case.end.4.321:
  br label %case.join.311
case.default.310:
  unreachable
case.join.311:
  %t610 = phi ptr [ %t316, %case.end.3.313 ], [ %t609, %case.end.4.321 ]
  call void @__free_recursive(ptr %t306)
  call void @__free_recursive(ptr %t288)
  br label %case.end.4.285
case.end.4.285:
  br label %case.join.275
case.default.274:
  unreachable
case.join.275:
  %t611 = phi ptr [ %t280, %case.end.3.277 ], [ %t610, %case.end.4.285 ]
  call void @__free_recursive(ptr %t270)
  call void @__free_recursive(ptr %t252)
  br label %case.end.4.249
case.end.4.249:
  br label %case.join.239
case.default.238:
  unreachable
case.join.239:
  %t612 = phi ptr [ %t244, %case.end.3.241 ], [ %t611, %case.end.4.249 ]
  call void @__free_recursive(ptr %t234)
  call void @__free_recursive(ptr %t216)
  br label %case.end.4.213
case.end.4.213:
  br label %case.join.203
case.default.202:
  unreachable
case.join.203:
  %t613 = phi ptr [ %t208, %case.end.3.205 ], [ %t612, %case.end.4.213 ]
  call void @__free_recursive(ptr %t198)
  call void @__free_recursive(ptr %t180)
  br label %case.end.4.177
case.end.4.177:
  br label %case.join.167
case.default.166:
  unreachable
case.join.167:
  %t614 = phi ptr [ %t172, %case.end.3.169 ], [ %t613, %case.end.4.177 ]
  call void @__free_recursive(ptr %t162)
  call void @__free_recursive(ptr %t144)
  br label %case.end.4.141
case.end.4.141:
  br label %case.join.131
case.default.130:
  unreachable
case.join.131:
  %t615 = phi ptr [ %t136, %case.end.3.133 ], [ %t614, %case.end.4.141 ]
  call void @__free_recursive(ptr %t126)
  call void @__free_recursive(ptr %t108)
  br label %case.end.4.105
case.end.4.105:
  br label %case.join.95
case.default.94:
  unreachable
case.join.95:
  %t616 = phi ptr [ %t100, %case.end.3.97 ], [ %t615, %case.end.4.105 ]
  call void @__free_recursive(ptr %t90)
  call void @__free_recursive(ptr %t72)
  br label %case.end.4.69
case.end.4.69:
  br label %case.join.59
case.default.58:
  unreachable
case.join.59:
  %t617 = phi ptr [ %t64, %case.end.3.61 ], [ %t616, %case.end.4.69 ]
  call void @__free_recursive(ptr %t54)
  call void @__free_recursive(ptr %t36)
  br label %case.end.4.33
case.end.4.33:
  br label %case.join.23
case.default.22:
  unreachable
case.join.23:
  %t618 = phi ptr [ %t28, %case.end.3.25 ], [ %t617, %case.end.4.33 ]
  call void @__free_recursive(ptr %t18)
  call void @__free_recursive(ptr %t0)
  ret ptr %t618
}

define internal ptr @v_main() {
  %t0 = call ptr @v_res()
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 3, label %case.arm.3.6 i64 4, label %case.arm.4.14 ]
case.arm.3.6:
  %t8 = call ptr @__alloc(i64 16, i32 1)
  %t9 = inttoptr i64 6 to ptr
  %t10 = getelementptr ptr, ptr %t8, i32 0
  store ptr %t9, ptr %t10
  %t11 = getelementptr ptr, ptr %t0, i32 1
  %t12 = load ptr, ptr %t11
  call void @__inc_ref(ptr %t12)
  %t13 = getelementptr ptr, ptr %t8, i32 1
  store ptr %t12, ptr %t13
  br label %case.end.3.7
case.end.3.7:
  br label %case.join.5
case.arm.4.14:
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 5 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = getelementptr ptr, ptr %t0, i32 1
  %t20 = load ptr, ptr %t19
  call void @__inc_ref(ptr %t20)
  %t21 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t20, ptr %t21
  br label %case.end.4.15
case.end.4.15:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t22 = phi ptr [ %t8, %case.end.3.7 ], [ %t16, %case.end.4.15 ]
  call void @__free_recursive(ptr %t0)
  %t23 = call ptr @__alloc(i64 8, i32 0)
  %t24 = inttoptr i64 22 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  %t26 = call ptr @v_$cps$$df$andThenIO$4(ptr %t22, ptr %t23)
  %t27 = call ptr @__alloc(i64 8, i32 0)
  %t28 = inttoptr i64 20 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  %t30 = call ptr @v_$cps$$df$handleErrorIO$0(ptr %t26, ptr %t27)
  ret ptr %t30
}

define internal ptr @v_$cps$$df$handleErrorIO$0(ptr %v_io, ptr %v_$k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.13 i64 7, label %tco.case.arm.7.27 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t12 = call ptr @v_$apply$$df$handleErrorIO$0(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t12, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.13:
  call void @__inc_ref(ptr %t6)
  %t14 = call ptr @__alloc(i64 24, i32 2)
  %t15 = inttoptr i64 7 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  %t17 = getelementptr ptr, ptr %t14, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.12, i64 12), ptr %t17
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
  %t25 = getelementptr ptr, ptr %t14, i32 2
  store ptr %t18, ptr %t25
  %t26 = call ptr @v_$apply$$df$handleErrorIO$0(ptr %t6, ptr %t14)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t26, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.27:
  %t28 = getelementptr ptr, ptr %t5, i32 1
  %t29 = load ptr, ptr %t28
  %t30 = getelementptr ptr, ptr %t5, i32 2
  %t31 = load ptr, ptr %t30
  call void @__inc_ref(ptr %t31)
  %t38 = getelementptr i8, ptr %t5, i64 -8
  %t39 = load i32, ptr %t38
  %t40 = icmp eq i32 %t39, 1
  br i1 %t40, label %reuse.in_place.41, label %reuse.copy.42
reuse.in_place.41:
  %t32 = getelementptr ptr, ptr %t5, i32 2
  %t33 = load ptr, ptr %t32
  call void @__free_recursive(ptr %t33)
  %t36 = inttoptr i64 21 to ptr
  %t37 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t36, ptr %t37
  call void @__inc_ref(ptr %t6)
  %t34 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t34
  %t35 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t29, ptr %t35
  br label %reuse.in_place.end.44
reuse.in_place.end.44:
  br label %reuse.join.43
reuse.copy.42:
  %t46 = call ptr @__alloc(i64 24, i32 2)
  %t47 = inttoptr i64 21 to ptr
  %t48 = getelementptr ptr, ptr %t46, i32 0
  store ptr %t47, ptr %t48
  call void @__inc_ref(ptr %t6)
  %t49 = getelementptr ptr, ptr %t46, i32 1
  store ptr %t6, ptr %t49
  call void @__inc_ref(ptr %t29)
  %t50 = getelementptr ptr, ptr %t46, i32 2
  store ptr %t29, ptr %t50
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.45
reuse.copy.end.45:
  br label %reuse.join.43
reuse.join.43:
  %t51 = phi ptr [ %t5, %reuse.in_place.end.44 ], [ %t46, %reuse.copy.end.45 ]
  call void @__free_recursive(ptr %t6)
  store ptr %t31, ptr %t3
  store ptr %t51, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t52 = load ptr, ptr %t2
  ret ptr %t52
}

define internal ptr @v_$apply$$df$handleErrorIO$0(ptr %v_$k, ptr %v_$x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 20, label %tco.case.arm.20.11 i64 21, label %tco.case.arm.21.12 ]
tco.case.arm.20.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.21.12:
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

define internal ptr @v_$cps$$df$andThenIO$4(ptr %v_io, ptr %v_$k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.27 i64 7, label %tco.case.arm.7.29 ]
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
  %t26 = call ptr @v_$apply$$df$andThenIO$4(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t26, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.27:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t28 = call ptr @v_$apply$$df$andThenIO$4(ptr %t6, ptr %t5)
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
  %t38 = inttoptr i64 23 to ptr
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
  %t49 = inttoptr i64 23 to ptr
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
tco.case.default.10:
  unreachable
tco.exit.1:
  %t54 = load ptr, ptr %t2
  ret ptr %t54
}

define internal ptr @v_$apply$$df$andThenIO$4(ptr %v_$k, ptr %v_$x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 22, label %tco.case.arm.22.11 i64 23, label %tco.case.arm.23.12 ]
tco.case.arm.22.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.23.12:
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

declare i32 @_setmode(i32, i32)

define i32 @main(i32 %argc_posix, ptr %argv_posix) {
entry:
  call i32 @_setmode(i32 1, i32 32768)
  call i32 @_setmode(i32 0, i32 32768)
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
