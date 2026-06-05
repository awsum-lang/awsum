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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"err" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"ok:" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"0" }
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
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.11 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v_r, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = call ptr @__alloc(i64 16, i32 1)
  %t8 = inttoptr i64 4 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = getelementptr ptr, ptr %t7, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t10
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_r)
  ret ptr %t7
case.arm.4.11:
  %t12 = getelementptr ptr, ptr %v_r, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @__showUInt32(ptr %t13)
  %t15 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t14)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %v_r)
  ret ptr %t15
case.default.3:
  unreachable
}

define internal ptr @v_main() {
  %t0 = call ptr @__parseUInt32(ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
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
  %t19 = call ptr @__parseUInt32(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12))
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
  %t38 = call ptr @__parseUInt32(ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
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
  %t57 = call ptr @__parseUInt32(ptr getelementptr inbounds (i8, ptr @.str.5, i64 12))
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
  %t76 = call ptr @__parseUInt32(ptr getelementptr inbounds (i8, ptr @.str.6, i64 12))
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
  %t95 = call ptr @__parseUInt32(ptr getelementptr inbounds (i8, ptr @.str.7, i64 12))
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
  %t114 = call ptr @__parseUInt32(ptr getelementptr inbounds (i8, ptr @.str.8, i64 12))
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
  %t133 = call ptr @__parseUInt32(ptr getelementptr inbounds (i8, ptr @.str.9, i64 12))
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
  %t152 = call ptr @__parseUInt32(ptr getelementptr inbounds (i8, ptr @.str.10, i64 12))
  %t153 = call ptr @v_render(ptr %t152)
  %t154 = getelementptr ptr, ptr %t153, i32 0
  %t155 = load ptr, ptr %t154
  %t156 = ptrtoint ptr %t155 to i64
  switch i64 %t156, label %case.default.157 [ i64 3, label %case.arm.3.159 i64 4, label %case.arm.4.167 ]
case.arm.3.159:
  %t161 = getelementptr ptr, ptr %t153, i32 1
  %t162 = load ptr, ptr %t161
  call void @__inc_ref(ptr %t162)
  %t163 = call ptr @__alloc(i64 16, i32 1)
  %t164 = inttoptr i64 3 to ptr
  %t165 = getelementptr ptr, ptr %t163, i32 0
  store ptr %t164, ptr %t165
  call void @__inc_ref(ptr %t162)
  %t166 = getelementptr ptr, ptr %t163, i32 1
  store ptr %t162, ptr %t166
  br label %case.end.3.160
case.end.3.160:
  br label %case.join.158
case.arm.4.167:
  %t169 = getelementptr ptr, ptr %t153, i32 1
  %t170 = load ptr, ptr %t169
  call void @__inc_ref(ptr %t170)
  call void @__inc_ref(ptr %t18)
  %t171 = call ptr @__concat(ptr %t18, ptr getelementptr inbounds (i8, ptr @.str.11, i64 12))
  %t172 = getelementptr ptr, ptr %t171, i32 0
  %t173 = load ptr, ptr %t172
  %t174 = ptrtoint ptr %t173 to i64
  switch i64 %t174, label %case.default.175 [ i64 3, label %case.arm.3.177 i64 4, label %case.arm.4.185 ]
case.arm.3.177:
  %t179 = getelementptr ptr, ptr %t171, i32 1
  %t180 = load ptr, ptr %t179
  call void @__inc_ref(ptr %t180)
  %t181 = call ptr @__alloc(i64 16, i32 1)
  %t182 = inttoptr i64 3 to ptr
  %t183 = getelementptr ptr, ptr %t181, i32 0
  store ptr %t182, ptr %t183
  call void @__inc_ref(ptr %t180)
  %t184 = getelementptr ptr, ptr %t181, i32 1
  store ptr %t180, ptr %t184
  br label %case.end.3.178
case.end.3.178:
  br label %case.join.176
case.arm.4.185:
  %t187 = getelementptr ptr, ptr %t171, i32 1
  %t188 = load ptr, ptr %t187
  call void @__inc_ref(ptr %t188)
  call void @__inc_ref(ptr %t188)
  call void @__inc_ref(ptr %t37)
  %t189 = call ptr @__concat(ptr %t188, ptr %t37)
  %t190 = getelementptr ptr, ptr %t189, i32 0
  %t191 = load ptr, ptr %t190
  %t192 = ptrtoint ptr %t191 to i64
  switch i64 %t192, label %case.default.193 [ i64 3, label %case.arm.3.195 i64 4, label %case.arm.4.203 ]
case.arm.3.195:
  %t197 = getelementptr ptr, ptr %t189, i32 1
  %t198 = load ptr, ptr %t197
  call void @__inc_ref(ptr %t198)
  %t199 = call ptr @__alloc(i64 16, i32 1)
  %t200 = inttoptr i64 3 to ptr
  %t201 = getelementptr ptr, ptr %t199, i32 0
  store ptr %t200, ptr %t201
  call void @__inc_ref(ptr %t198)
  %t202 = getelementptr ptr, ptr %t199, i32 1
  store ptr %t198, ptr %t202
  br label %case.end.3.196
case.end.3.196:
  br label %case.join.194
case.arm.4.203:
  %t205 = getelementptr ptr, ptr %t189, i32 1
  %t206 = load ptr, ptr %t205
  call void @__inc_ref(ptr %t206)
  call void @__inc_ref(ptr %t206)
  %t207 = call ptr @__concat(ptr %t206, ptr getelementptr inbounds (i8, ptr @.str.11, i64 12))
  %t208 = getelementptr ptr, ptr %t207, i32 0
  %t209 = load ptr, ptr %t208
  %t210 = ptrtoint ptr %t209 to i64
  switch i64 %t210, label %case.default.211 [ i64 3, label %case.arm.3.213 i64 4, label %case.arm.4.221 ]
case.arm.3.213:
  %t215 = getelementptr ptr, ptr %t207, i32 1
  %t216 = load ptr, ptr %t215
  call void @__inc_ref(ptr %t216)
  %t217 = call ptr @__alloc(i64 16, i32 1)
  %t218 = inttoptr i64 3 to ptr
  %t219 = getelementptr ptr, ptr %t217, i32 0
  store ptr %t218, ptr %t219
  call void @__inc_ref(ptr %t216)
  %t220 = getelementptr ptr, ptr %t217, i32 1
  store ptr %t216, ptr %t220
  br label %case.end.3.214
case.end.3.214:
  br label %case.join.212
case.arm.4.221:
  %t223 = getelementptr ptr, ptr %t207, i32 1
  %t224 = load ptr, ptr %t223
  call void @__inc_ref(ptr %t224)
  call void @__inc_ref(ptr %t224)
  call void @__inc_ref(ptr %t56)
  %t225 = call ptr @__concat(ptr %t224, ptr %t56)
  %t226 = getelementptr ptr, ptr %t225, i32 0
  %t227 = load ptr, ptr %t226
  %t228 = ptrtoint ptr %t227 to i64
  switch i64 %t228, label %case.default.229 [ i64 3, label %case.arm.3.231 i64 4, label %case.arm.4.239 ]
case.arm.3.231:
  %t233 = getelementptr ptr, ptr %t225, i32 1
  %t234 = load ptr, ptr %t233
  call void @__inc_ref(ptr %t234)
  %t235 = call ptr @__alloc(i64 16, i32 1)
  %t236 = inttoptr i64 3 to ptr
  %t237 = getelementptr ptr, ptr %t235, i32 0
  store ptr %t236, ptr %t237
  call void @__inc_ref(ptr %t234)
  %t238 = getelementptr ptr, ptr %t235, i32 1
  store ptr %t234, ptr %t238
  br label %case.end.3.232
case.end.3.232:
  br label %case.join.230
case.arm.4.239:
  %t241 = getelementptr ptr, ptr %t225, i32 1
  %t242 = load ptr, ptr %t241
  call void @__inc_ref(ptr %t242)
  call void @__inc_ref(ptr %t242)
  %t243 = call ptr @__concat(ptr %t242, ptr getelementptr inbounds (i8, ptr @.str.11, i64 12))
  %t244 = getelementptr ptr, ptr %t243, i32 0
  %t245 = load ptr, ptr %t244
  %t246 = ptrtoint ptr %t245 to i64
  switch i64 %t246, label %case.default.247 [ i64 3, label %case.arm.3.249 i64 4, label %case.arm.4.257 ]
case.arm.3.249:
  %t251 = getelementptr ptr, ptr %t243, i32 1
  %t252 = load ptr, ptr %t251
  call void @__inc_ref(ptr %t252)
  %t253 = call ptr @__alloc(i64 16, i32 1)
  %t254 = inttoptr i64 3 to ptr
  %t255 = getelementptr ptr, ptr %t253, i32 0
  store ptr %t254, ptr %t255
  call void @__inc_ref(ptr %t252)
  %t256 = getelementptr ptr, ptr %t253, i32 1
  store ptr %t252, ptr %t256
  br label %case.end.3.250
case.end.3.250:
  br label %case.join.248
case.arm.4.257:
  %t259 = getelementptr ptr, ptr %t243, i32 1
  %t260 = load ptr, ptr %t259
  call void @__inc_ref(ptr %t260)
  call void @__inc_ref(ptr %t260)
  call void @__inc_ref(ptr %t75)
  %t261 = call ptr @__concat(ptr %t260, ptr %t75)
  %t262 = getelementptr ptr, ptr %t261, i32 0
  %t263 = load ptr, ptr %t262
  %t264 = ptrtoint ptr %t263 to i64
  switch i64 %t264, label %case.default.265 [ i64 3, label %case.arm.3.267 i64 4, label %case.arm.4.275 ]
case.arm.3.267:
  %t269 = getelementptr ptr, ptr %t261, i32 1
  %t270 = load ptr, ptr %t269
  call void @__inc_ref(ptr %t270)
  %t271 = call ptr @__alloc(i64 16, i32 1)
  %t272 = inttoptr i64 3 to ptr
  %t273 = getelementptr ptr, ptr %t271, i32 0
  store ptr %t272, ptr %t273
  call void @__inc_ref(ptr %t270)
  %t274 = getelementptr ptr, ptr %t271, i32 1
  store ptr %t270, ptr %t274
  br label %case.end.3.268
case.end.3.268:
  br label %case.join.266
case.arm.4.275:
  %t277 = getelementptr ptr, ptr %t261, i32 1
  %t278 = load ptr, ptr %t277
  call void @__inc_ref(ptr %t278)
  call void @__inc_ref(ptr %t278)
  %t279 = call ptr @__concat(ptr %t278, ptr getelementptr inbounds (i8, ptr @.str.11, i64 12))
  %t280 = getelementptr ptr, ptr %t279, i32 0
  %t281 = load ptr, ptr %t280
  %t282 = ptrtoint ptr %t281 to i64
  switch i64 %t282, label %case.default.283 [ i64 3, label %case.arm.3.285 i64 4, label %case.arm.4.293 ]
case.arm.3.285:
  %t287 = getelementptr ptr, ptr %t279, i32 1
  %t288 = load ptr, ptr %t287
  call void @__inc_ref(ptr %t288)
  %t289 = call ptr @__alloc(i64 16, i32 1)
  %t290 = inttoptr i64 3 to ptr
  %t291 = getelementptr ptr, ptr %t289, i32 0
  store ptr %t290, ptr %t291
  call void @__inc_ref(ptr %t288)
  %t292 = getelementptr ptr, ptr %t289, i32 1
  store ptr %t288, ptr %t292
  br label %case.end.3.286
case.end.3.286:
  br label %case.join.284
case.arm.4.293:
  %t295 = getelementptr ptr, ptr %t279, i32 1
  %t296 = load ptr, ptr %t295
  call void @__inc_ref(ptr %t296)
  call void @__inc_ref(ptr %t296)
  call void @__inc_ref(ptr %t94)
  %t297 = call ptr @__concat(ptr %t296, ptr %t94)
  %t298 = getelementptr ptr, ptr %t297, i32 0
  %t299 = load ptr, ptr %t298
  %t300 = ptrtoint ptr %t299 to i64
  switch i64 %t300, label %case.default.301 [ i64 3, label %case.arm.3.303 i64 4, label %case.arm.4.311 ]
case.arm.3.303:
  %t305 = getelementptr ptr, ptr %t297, i32 1
  %t306 = load ptr, ptr %t305
  call void @__inc_ref(ptr %t306)
  %t307 = call ptr @__alloc(i64 16, i32 1)
  %t308 = inttoptr i64 3 to ptr
  %t309 = getelementptr ptr, ptr %t307, i32 0
  store ptr %t308, ptr %t309
  call void @__inc_ref(ptr %t306)
  %t310 = getelementptr ptr, ptr %t307, i32 1
  store ptr %t306, ptr %t310
  br label %case.end.3.304
case.end.3.304:
  br label %case.join.302
case.arm.4.311:
  %t313 = getelementptr ptr, ptr %t297, i32 1
  %t314 = load ptr, ptr %t313
  call void @__inc_ref(ptr %t314)
  call void @__inc_ref(ptr %t314)
  %t315 = call ptr @__concat(ptr %t314, ptr getelementptr inbounds (i8, ptr @.str.11, i64 12))
  %t316 = getelementptr ptr, ptr %t315, i32 0
  %t317 = load ptr, ptr %t316
  %t318 = ptrtoint ptr %t317 to i64
  switch i64 %t318, label %case.default.319 [ i64 3, label %case.arm.3.321 i64 4, label %case.arm.4.329 ]
case.arm.3.321:
  %t323 = getelementptr ptr, ptr %t315, i32 1
  %t324 = load ptr, ptr %t323
  call void @__inc_ref(ptr %t324)
  %t325 = call ptr @__alloc(i64 16, i32 1)
  %t326 = inttoptr i64 3 to ptr
  %t327 = getelementptr ptr, ptr %t325, i32 0
  store ptr %t326, ptr %t327
  call void @__inc_ref(ptr %t324)
  %t328 = getelementptr ptr, ptr %t325, i32 1
  store ptr %t324, ptr %t328
  br label %case.end.3.322
case.end.3.322:
  br label %case.join.320
case.arm.4.329:
  %t331 = getelementptr ptr, ptr %t315, i32 1
  %t332 = load ptr, ptr %t331
  call void @__inc_ref(ptr %t332)
  call void @__inc_ref(ptr %t332)
  call void @__inc_ref(ptr %t113)
  %t333 = call ptr @__concat(ptr %t332, ptr %t113)
  %t334 = getelementptr ptr, ptr %t333, i32 0
  %t335 = load ptr, ptr %t334
  %t336 = ptrtoint ptr %t335 to i64
  switch i64 %t336, label %case.default.337 [ i64 3, label %case.arm.3.339 i64 4, label %case.arm.4.347 ]
case.arm.3.339:
  %t341 = getelementptr ptr, ptr %t333, i32 1
  %t342 = load ptr, ptr %t341
  call void @__inc_ref(ptr %t342)
  %t343 = call ptr @__alloc(i64 16, i32 1)
  %t344 = inttoptr i64 3 to ptr
  %t345 = getelementptr ptr, ptr %t343, i32 0
  store ptr %t344, ptr %t345
  call void @__inc_ref(ptr %t342)
  %t346 = getelementptr ptr, ptr %t343, i32 1
  store ptr %t342, ptr %t346
  br label %case.end.3.340
case.end.3.340:
  br label %case.join.338
case.arm.4.347:
  %t349 = getelementptr ptr, ptr %t333, i32 1
  %t350 = load ptr, ptr %t349
  call void @__inc_ref(ptr %t350)
  call void @__inc_ref(ptr %t350)
  %t351 = call ptr @__concat(ptr %t350, ptr getelementptr inbounds (i8, ptr @.str.11, i64 12))
  %t352 = getelementptr ptr, ptr %t351, i32 0
  %t353 = load ptr, ptr %t352
  %t354 = ptrtoint ptr %t353 to i64
  switch i64 %t354, label %case.default.355 [ i64 3, label %case.arm.3.357 i64 4, label %case.arm.4.365 ]
case.arm.3.357:
  %t359 = getelementptr ptr, ptr %t351, i32 1
  %t360 = load ptr, ptr %t359
  call void @__inc_ref(ptr %t360)
  %t361 = call ptr @__alloc(i64 16, i32 1)
  %t362 = inttoptr i64 3 to ptr
  %t363 = getelementptr ptr, ptr %t361, i32 0
  store ptr %t362, ptr %t363
  call void @__inc_ref(ptr %t360)
  %t364 = getelementptr ptr, ptr %t361, i32 1
  store ptr %t360, ptr %t364
  br label %case.end.3.358
case.end.3.358:
  br label %case.join.356
case.arm.4.365:
  %t367 = getelementptr ptr, ptr %t351, i32 1
  %t368 = load ptr, ptr %t367
  call void @__inc_ref(ptr %t368)
  call void @__inc_ref(ptr %t368)
  call void @__inc_ref(ptr %t132)
  %t369 = call ptr @__concat(ptr %t368, ptr %t132)
  %t370 = getelementptr ptr, ptr %t369, i32 0
  %t371 = load ptr, ptr %t370
  %t372 = ptrtoint ptr %t371 to i64
  switch i64 %t372, label %case.default.373 [ i64 3, label %case.arm.3.375 i64 4, label %case.arm.4.383 ]
case.arm.3.375:
  %t377 = getelementptr ptr, ptr %t369, i32 1
  %t378 = load ptr, ptr %t377
  call void @__inc_ref(ptr %t378)
  %t379 = call ptr @__alloc(i64 16, i32 1)
  %t380 = inttoptr i64 3 to ptr
  %t381 = getelementptr ptr, ptr %t379, i32 0
  store ptr %t380, ptr %t381
  call void @__inc_ref(ptr %t378)
  %t382 = getelementptr ptr, ptr %t379, i32 1
  store ptr %t378, ptr %t382
  br label %case.end.3.376
case.end.3.376:
  br label %case.join.374
case.arm.4.383:
  %t385 = getelementptr ptr, ptr %t369, i32 1
  %t386 = load ptr, ptr %t385
  call void @__inc_ref(ptr %t386)
  call void @__inc_ref(ptr %t386)
  %t387 = call ptr @__concat(ptr %t386, ptr getelementptr inbounds (i8, ptr @.str.11, i64 12))
  %t388 = getelementptr ptr, ptr %t387, i32 0
  %t389 = load ptr, ptr %t388
  %t390 = ptrtoint ptr %t389 to i64
  switch i64 %t390, label %case.default.391 [ i64 3, label %case.arm.3.393 i64 4, label %case.arm.4.401 ]
case.arm.3.393:
  %t395 = getelementptr ptr, ptr %t387, i32 1
  %t396 = load ptr, ptr %t395
  call void @__inc_ref(ptr %t396)
  %t397 = call ptr @__alloc(i64 16, i32 1)
  %t398 = inttoptr i64 3 to ptr
  %t399 = getelementptr ptr, ptr %t397, i32 0
  store ptr %t398, ptr %t399
  call void @__inc_ref(ptr %t396)
  %t400 = getelementptr ptr, ptr %t397, i32 1
  store ptr %t396, ptr %t400
  br label %case.end.3.394
case.end.3.394:
  br label %case.join.392
case.arm.4.401:
  %t403 = getelementptr ptr, ptr %t387, i32 1
  %t404 = load ptr, ptr %t403
  call void @__inc_ref(ptr %t404)
  call void @__inc_ref(ptr %t404)
  call void @__inc_ref(ptr %t151)
  %t405 = call ptr @__concat(ptr %t404, ptr %t151)
  %t406 = getelementptr ptr, ptr %t405, i32 0
  %t407 = load ptr, ptr %t406
  %t408 = ptrtoint ptr %t407 to i64
  switch i64 %t408, label %case.default.409 [ i64 3, label %case.arm.3.411 i64 4, label %case.arm.4.419 ]
case.arm.3.411:
  %t413 = getelementptr ptr, ptr %t405, i32 1
  %t414 = load ptr, ptr %t413
  call void @__inc_ref(ptr %t414)
  %t415 = call ptr @__alloc(i64 16, i32 1)
  %t416 = inttoptr i64 3 to ptr
  %t417 = getelementptr ptr, ptr %t415, i32 0
  store ptr %t416, ptr %t417
  call void @__inc_ref(ptr %t414)
  %t418 = getelementptr ptr, ptr %t415, i32 1
  store ptr %t414, ptr %t418
  br label %case.end.3.412
case.end.3.412:
  br label %case.join.410
case.arm.4.419:
  %t421 = getelementptr ptr, ptr %t405, i32 1
  %t422 = load ptr, ptr %t421
  call void @__inc_ref(ptr %t422)
  call void @__inc_ref(ptr %t422)
  %t423 = call ptr @__concat(ptr %t422, ptr getelementptr inbounds (i8, ptr @.str.11, i64 12))
  %t424 = getelementptr ptr, ptr %t423, i32 0
  %t425 = load ptr, ptr %t424
  %t426 = ptrtoint ptr %t425 to i64
  switch i64 %t426, label %case.default.427 [ i64 3, label %case.arm.3.429 i64 4, label %case.arm.4.437 ]
case.arm.3.429:
  %t431 = getelementptr ptr, ptr %t423, i32 1
  %t432 = load ptr, ptr %t431
  call void @__inc_ref(ptr %t432)
  %t433 = call ptr @__alloc(i64 16, i32 1)
  %t434 = inttoptr i64 3 to ptr
  %t435 = getelementptr ptr, ptr %t433, i32 0
  store ptr %t434, ptr %t435
  call void @__inc_ref(ptr %t432)
  %t436 = getelementptr ptr, ptr %t433, i32 1
  store ptr %t432, ptr %t436
  br label %case.end.3.430
case.end.3.430:
  br label %case.join.428
case.arm.4.437:
  %t439 = getelementptr ptr, ptr %t423, i32 1
  %t440 = load ptr, ptr %t439
  call void @__inc_ref(ptr %t440)
  call void @__inc_ref(ptr %t440)
  call void @__inc_ref(ptr %t170)
  %t441 = call ptr @__concat(ptr %t440, ptr %t170)
  br label %case.end.4.438
case.end.4.438:
  br label %case.join.428
case.default.427:
  unreachable
case.join.428:
  %t442 = phi ptr [ %t433, %case.end.3.430 ], [ %t441, %case.end.4.438 ]
  call void @__free_recursive(ptr %t423)
  br label %case.end.4.420
case.end.4.420:
  br label %case.join.410
case.default.409:
  unreachable
case.join.410:
  %t443 = phi ptr [ %t415, %case.end.3.412 ], [ %t442, %case.end.4.420 ]
  call void @__free_recursive(ptr %t405)
  br label %case.end.4.402
case.end.4.402:
  br label %case.join.392
case.default.391:
  unreachable
case.join.392:
  %t444 = phi ptr [ %t397, %case.end.3.394 ], [ %t443, %case.end.4.402 ]
  call void @__free_recursive(ptr %t387)
  br label %case.end.4.384
case.end.4.384:
  br label %case.join.374
case.default.373:
  unreachable
case.join.374:
  %t445 = phi ptr [ %t379, %case.end.3.376 ], [ %t444, %case.end.4.384 ]
  call void @__free_recursive(ptr %t369)
  br label %case.end.4.366
case.end.4.366:
  br label %case.join.356
case.default.355:
  unreachable
case.join.356:
  %t446 = phi ptr [ %t361, %case.end.3.358 ], [ %t445, %case.end.4.366 ]
  call void @__free_recursive(ptr %t351)
  br label %case.end.4.348
case.end.4.348:
  br label %case.join.338
case.default.337:
  unreachable
case.join.338:
  %t447 = phi ptr [ %t343, %case.end.3.340 ], [ %t446, %case.end.4.348 ]
  call void @__free_recursive(ptr %t333)
  br label %case.end.4.330
case.end.4.330:
  br label %case.join.320
case.default.319:
  unreachable
case.join.320:
  %t448 = phi ptr [ %t325, %case.end.3.322 ], [ %t447, %case.end.4.330 ]
  call void @__free_recursive(ptr %t315)
  br label %case.end.4.312
case.end.4.312:
  br label %case.join.302
case.default.301:
  unreachable
case.join.302:
  %t449 = phi ptr [ %t307, %case.end.3.304 ], [ %t448, %case.end.4.312 ]
  call void @__free_recursive(ptr %t297)
  br label %case.end.4.294
case.end.4.294:
  br label %case.join.284
case.default.283:
  unreachable
case.join.284:
  %t450 = phi ptr [ %t289, %case.end.3.286 ], [ %t449, %case.end.4.294 ]
  call void @__free_recursive(ptr %t279)
  br label %case.end.4.276
case.end.4.276:
  br label %case.join.266
case.default.265:
  unreachable
case.join.266:
  %t451 = phi ptr [ %t271, %case.end.3.268 ], [ %t450, %case.end.4.276 ]
  call void @__free_recursive(ptr %t261)
  br label %case.end.4.258
case.end.4.258:
  br label %case.join.248
case.default.247:
  unreachable
case.join.248:
  %t452 = phi ptr [ %t253, %case.end.3.250 ], [ %t451, %case.end.4.258 ]
  call void @__free_recursive(ptr %t243)
  br label %case.end.4.240
case.end.4.240:
  br label %case.join.230
case.default.229:
  unreachable
case.join.230:
  %t453 = phi ptr [ %t235, %case.end.3.232 ], [ %t452, %case.end.4.240 ]
  call void @__free_recursive(ptr %t225)
  br label %case.end.4.222
case.end.4.222:
  br label %case.join.212
case.default.211:
  unreachable
case.join.212:
  %t454 = phi ptr [ %t217, %case.end.3.214 ], [ %t453, %case.end.4.222 ]
  call void @__free_recursive(ptr %t207)
  br label %case.end.4.204
case.end.4.204:
  br label %case.join.194
case.default.193:
  unreachable
case.join.194:
  %t455 = phi ptr [ %t199, %case.end.3.196 ], [ %t454, %case.end.4.204 ]
  call void @__free_recursive(ptr %t189)
  br label %case.end.4.186
case.end.4.186:
  br label %case.join.176
case.default.175:
  unreachable
case.join.176:
  %t456 = phi ptr [ %t181, %case.end.3.178 ], [ %t455, %case.end.4.186 ]
  call void @__free_recursive(ptr %t171)
  br label %case.end.4.168
case.end.4.168:
  br label %case.join.158
case.default.157:
  unreachable
case.join.158:
  %t457 = phi ptr [ %t163, %case.end.3.160 ], [ %t456, %case.end.4.168 ]
  call void @__free_recursive(ptr %t153)
  br label %case.end.4.149
case.end.4.149:
  br label %case.join.139
case.default.138:
  unreachable
case.join.139:
  %t458 = phi ptr [ %t144, %case.end.3.141 ], [ %t457, %case.end.4.149 ]
  call void @__free_recursive(ptr %t134)
  br label %case.end.4.130
case.end.4.130:
  br label %case.join.120
case.default.119:
  unreachable
case.join.120:
  %t459 = phi ptr [ %t125, %case.end.3.122 ], [ %t458, %case.end.4.130 ]
  call void @__free_recursive(ptr %t115)
  br label %case.end.4.111
case.end.4.111:
  br label %case.join.101
case.default.100:
  unreachable
case.join.101:
  %t460 = phi ptr [ %t106, %case.end.3.103 ], [ %t459, %case.end.4.111 ]
  call void @__free_recursive(ptr %t96)
  br label %case.end.4.92
case.end.4.92:
  br label %case.join.82
case.default.81:
  unreachable
case.join.82:
  %t461 = phi ptr [ %t87, %case.end.3.84 ], [ %t460, %case.end.4.92 ]
  call void @__free_recursive(ptr %t77)
  br label %case.end.4.73
case.end.4.73:
  br label %case.join.63
case.default.62:
  unreachable
case.join.63:
  %t462 = phi ptr [ %t68, %case.end.3.65 ], [ %t461, %case.end.4.73 ]
  call void @__free_recursive(ptr %t58)
  br label %case.end.4.54
case.end.4.54:
  br label %case.join.44
case.default.43:
  unreachable
case.join.44:
  %t463 = phi ptr [ %t49, %case.end.3.46 ], [ %t462, %case.end.4.54 ]
  call void @__free_recursive(ptr %t39)
  br label %case.end.4.35
case.end.4.35:
  br label %case.join.25
case.default.24:
  unreachable
case.join.25:
  %t464 = phi ptr [ %t30, %case.end.3.27 ], [ %t463, %case.end.4.35 ]
  call void @__free_recursive(ptr %t20)
  br label %case.end.4.16
case.end.4.16:
  br label %case.join.6
case.default.5:
  unreachable
case.join.6:
  %t465 = phi ptr [ %t11, %case.end.3.8 ], [ %t464, %case.end.4.16 ]
  call void @__free_recursive(ptr %t1)
  %t466 = call ptr @v__let_23(ptr %t465)
  ret ptr %t466
}

define internal ptr @v__let_23(ptr %v_res) {
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
  store ptr getelementptr inbounds (i8, ptr @.str.12, i64 12), ptr %t10
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

define i32 @main(i32 %argc, ptr %argv) {
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
