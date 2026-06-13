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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"," }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [0 x i8]} { i32 0, i32 0, i32 0, i32 0, i32 0, [0 x i8] zeroinitializer }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [6 x i8]} { i32 0, i32 0, i32 0, i32 6, i32 6, [6 x i8] c"left: " }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [14 x i8]} { i32 0, i32 0, i32 0, i32 14, i32 14, [14 x i8] c"UnderflowError" }
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [7 x i8]} { i32 0, i32 0, i32 0, i32 7, i32 7, [7 x i8] c"right: " }

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


define internal ptr @__showUInt8(ptr %p) {
  %b = load i8, ptr %p
  %v = zext i8 %b to i32
  %buf = call ptr @__alloc(i64 24, i32 0)
  %payload = getelementptr i8, ptr %buf, i64 8
  %n = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %payload, i64 16, ptr @.fmt_u8, i32 %v)
  store i32 %n, ptr %buf
  %u16p = getelementptr i8, ptr %buf, i64 4
  store i32 %n, ptr %u16p
  call void @__free_recursive(ptr %p)
  ret ptr %buf
}


define internal ptr @__predUInt8(ptr %p) {
  %v = load i8, ptr %p
  %is_zero = icmp eq i8 %v, 0
  br i1 %is_zero, label %overflow, label %ok
overflow:
  %oe = call ptr @__alloc(i64 8, i32 0)
  %oe_tag = inttoptr i64 17 to ptr
  store ptr %oe_tag, ptr %oe
  %left = call ptr @__alloc(i64 16, i32 1)
  %left_tag = inttoptr i64 3 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %oe, ptr %left_f
  call void @__free_recursive(ptr %p)
  ret ptr %left
ok:
  %newv = sub i8 %v, 1
  %box = call ptr @__alloc(i64 1, i32 0)
  store i8 %newv, ptr %box
  %right = call ptr @__alloc(i64 16, i32 1)
  %right_tag = inttoptr i64 4 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %box, ptr %right_f
  call void @__free_recursive(ptr %p)
  ret ptr %right
}


define internal ptr @__eqUInt8(ptr %a, ptr %b) {
  %va = load i8, ptr %a
  %vb = load i8, ptr %b
  %eq = icmp eq i8 %va, %vb
  %tag = select i1 %eq, i64 1, i64 2
  %box = call ptr @__alloc(i64 8, i32 0)
  %tag_ptr = inttoptr i64 %tag to ptr
  store ptr %tag_ptr, ptr %box
  call void @__free_recursive(ptr %a)
  call void @__free_recursive(ptr %b)
  ret ptr %box
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

define internal ptr @v_countDown(ptr %v_n, ptr %v_acc) {
entry:
  %t3 = alloca ptr
  store ptr %v_n, ptr %t3
  %t4 = alloca ptr
  store ptr %v_acc, ptr %t4
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t5 = load ptr, ptr %t3
  %t6 = load ptr, ptr %t4
  call void @__inc_ref(ptr %t5)
  %t7 = call ptr @__alloc(i64 1, i32 0)
  store i8 0, ptr %t7
  %t8 = call ptr @__eqUInt8(ptr %t5, ptr %t7)
  %t9 = getelementptr ptr, ptr %t8, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %tco.case.default.12 [ i64 1, label %tco.case.arm.1.13 i64 2, label %tco.case.arm.2.32 ]
tco.case.arm.1.13:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t14 = call ptr @__showUInt8(ptr %t5)
  %t15 = call ptr @__concat(ptr %t6, ptr %t14)
  %t16 = getelementptr ptr, ptr %t15, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %tco.case.default.19 [ i64 3, label %tco.case.arm.3.20 i64 4, label %tco.case.arm.4.31 ]
tco.case.arm.3.20:
  %t21 = call ptr @__alloc(i64 16, i32 1)
  %t22 = inttoptr i64 3 to ptr
  %t23 = getelementptr ptr, ptr %t21, i32 0
  store ptr %t22, ptr %t23
  %t24 = call ptr @__alloc(i64 16, i32 1)
  %t25 = inttoptr i64 589989748 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = getelementptr ptr, ptr %t15, i32 1
  %t28 = load ptr, ptr %t27
  call void @__inc_ref(ptr %t28)
  %t29 = getelementptr ptr, ptr %t24, i32 1
  store ptr %t28, ptr %t29
  %t30 = getelementptr ptr, ptr %t21, i32 1
  store ptr %t24, ptr %t30
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t21, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.31:
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t15, ptr %t2
  br label %tco.exit.1
tco.case.default.19:
  unreachable
tco.case.arm.2.32:
  call void @__inc_ref(ptr %t5)
  %t33 = call ptr @__predUInt8(ptr %t5)
  %t34 = getelementptr ptr, ptr %t33, i32 0
  %t35 = load ptr, ptr %t34
  %t36 = ptrtoint ptr %t35 to i64
  switch i64 %t36, label %tco.case.default.37 [ i64 3, label %tco.case.arm.3.38 i64 4, label %tco.case.arm.4.49 ]
tco.case.arm.3.38:
  %t39 = getelementptr ptr, ptr %t33, i32 1
  %t40 = load ptr, ptr %t39
  call void @__inc_ref(ptr %t40)
  %t41 = call ptr @__alloc(i64 16, i32 1)
  %t42 = inttoptr i64 3 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = call ptr @__alloc(i64 16, i32 1)
  %t45 = inttoptr i64 3768445577 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  call void @__inc_ref(ptr %t40)
  %t47 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t40, ptr %t47
  %t48 = getelementptr ptr, ptr %t41, i32 1
  store ptr %t44, ptr %t48
  call void @__free_recursive(ptr %t33)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t40)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t41, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.49:
  %t50 = getelementptr ptr, ptr %t33, i32 1
  %t51 = load ptr, ptr %t50
  call void @__inc_ref(ptr %t51)
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t52 = call ptr @__showUInt8(ptr %t5)
  %t53 = call ptr @__concat(ptr %t6, ptr %t52)
  %t54 = getelementptr ptr, ptr %t53, i32 0
  %t55 = load ptr, ptr %t54
  %t56 = ptrtoint ptr %t55 to i64
  switch i64 %t56, label %tco.case.default.57 [ i64 3, label %tco.case.arm.3.58 i64 4, label %tco.case.arm.4.69 ]
tco.case.arm.3.58:
  %t59 = getelementptr ptr, ptr %t53, i32 1
  %t60 = load ptr, ptr %t59
  call void @__inc_ref(ptr %t60)
  %t61 = call ptr @__alloc(i64 16, i32 1)
  %t62 = inttoptr i64 3 to ptr
  %t63 = getelementptr ptr, ptr %t61, i32 0
  store ptr %t62, ptr %t63
  %t64 = call ptr @__alloc(i64 16, i32 1)
  %t65 = inttoptr i64 589989748 to ptr
  %t66 = getelementptr ptr, ptr %t64, i32 0
  store ptr %t65, ptr %t66
  call void @__inc_ref(ptr %t60)
  %t67 = getelementptr ptr, ptr %t64, i32 1
  store ptr %t60, ptr %t67
  %t68 = getelementptr ptr, ptr %t61, i32 1
  store ptr %t64, ptr %t68
  call void @__free_recursive(ptr %t53)
  call void @__free_recursive(ptr %t33)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t60)
  call void @__free_recursive(ptr %t51)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t61, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.69:
  %t70 = getelementptr ptr, ptr %t53, i32 1
  %t71 = load ptr, ptr %t70
  call void @__inc_ref(ptr %t71)
  call void @__inc_ref(ptr %t71)
  %t72 = call ptr @__concat(ptr %t71, ptr getelementptr inbounds (i8, ptr @.str.0, i64 12))
  %t73 = getelementptr ptr, ptr %t72, i32 0
  %t74 = load ptr, ptr %t73
  %t75 = ptrtoint ptr %t74 to i64
  switch i64 %t75, label %tco.case.default.76 [ i64 3, label %tco.case.arm.3.77 i64 4, label %tco.case.arm.4.88 ]
tco.case.arm.3.77:
  %t78 = getelementptr ptr, ptr %t72, i32 1
  %t79 = load ptr, ptr %t78
  call void @__inc_ref(ptr %t79)
  %t80 = call ptr @__alloc(i64 16, i32 1)
  %t81 = inttoptr i64 3 to ptr
  %t82 = getelementptr ptr, ptr %t80, i32 0
  store ptr %t81, ptr %t82
  %t83 = call ptr @__alloc(i64 16, i32 1)
  %t84 = inttoptr i64 589989748 to ptr
  %t85 = getelementptr ptr, ptr %t83, i32 0
  store ptr %t84, ptr %t85
  call void @__inc_ref(ptr %t79)
  %t86 = getelementptr ptr, ptr %t83, i32 1
  store ptr %t79, ptr %t86
  %t87 = getelementptr ptr, ptr %t80, i32 1
  store ptr %t83, ptr %t87
  call void @__free_recursive(ptr %t72)
  call void @__free_recursive(ptr %t53)
  call void @__free_recursive(ptr %t33)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t79)
  call void @__free_recursive(ptr %t71)
  call void @__free_recursive(ptr %t51)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t80, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.88:
  %t89 = getelementptr ptr, ptr %t72, i32 1
  %t90 = load ptr, ptr %t89
  call void @__inc_ref(ptr %t90)
  call void @__inc_ref(ptr %t51)
  call void @__inc_ref(ptr %t90)
  call void @__free_recursive(ptr %t72)
  call void @__free_recursive(ptr %t53)
  call void @__free_recursive(ptr %t33)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t90)
  call void @__free_recursive(ptr %t71)
  call void @__free_recursive(ptr %t51)
  store ptr %t51, ptr %t3
  store ptr %t90, ptr %t4
  br label %tco.loop.0
tco.case.default.76:
  unreachable
tco.case.default.57:
  unreachable
tco.case.default.37:
  unreachable
tco.case.default.12:
  unreachable
tco.exit.1:
  %t91 = load ptr, ptr %t2
  ret ptr %t91
}

define internal ptr @v_main() {
  %t0 = call ptr @__alloc(i64 1, i32 0)
  store i8 255, ptr %t0
  %t1 = call ptr @v_countDown(ptr %t0, ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  %t2 = getelementptr ptr, ptr %t1, i32 0
  %t3 = load ptr, ptr %t2
  %t4 = ptrtoint ptr %t3 to i64
  switch i64 %t4, label %case.default.5 [ i64 3, label %case.arm.3.7 i64 4, label %case.arm.4.26 ]
case.arm.3.7:
  %t9 = getelementptr ptr, ptr %t1, i32 1
  %t10 = load ptr, ptr %t9
  call void @__inc_ref(ptr %t10)
  %t11 = getelementptr ptr, ptr %t10, i32 0
  %t12 = load ptr, ptr %t11
  %t13 = ptrtoint ptr %t12 to i64
  switch i64 %t13, label %case.default.14 [ i64 589989748, label %case.arm.589989748.16 i64 3768445577, label %case.arm.3768445577.22 ]
case.arm.589989748.16:
  %t18 = call ptr @__alloc(i64 16, i32 1)
  %t19 = inttoptr i64 4 to ptr
  %t20 = getelementptr ptr, ptr %t18, i32 0
  store ptr %t19, ptr %t20
  %t21 = getelementptr ptr, ptr %t18, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t21
  br label %case.end.589989748.17
case.end.589989748.17:
  br label %case.join.15
case.arm.3768445577.22:
  %t24 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  br label %case.end.3768445577.23
case.end.3768445577.23:
  br label %case.join.15
case.default.14:
  unreachable
case.join.15:
  %t25 = phi ptr [ %t18, %case.end.589989748.17 ], [ %t24, %case.end.3768445577.23 ]
  call void @__free_recursive(ptr %t10)
  br label %case.end.3.8
case.end.3.8:
  br label %case.join.6
case.arm.4.26:
  %t28 = getelementptr ptr, ptr %t1, i32 1
  %t29 = load ptr, ptr %t28
  call void @__inc_ref(ptr %t29)
  %t30 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.5, i64 12), ptr %t29)
  br label %case.end.4.27
case.end.4.27:
  br label %case.join.6
case.default.5:
  unreachable
case.join.6:
  %t31 = phi ptr [ %t25, %case.end.3.8 ], [ %t30, %case.end.4.27 ]
  %t32 = getelementptr ptr, ptr %t31, i32 0
  %t33 = load ptr, ptr %t32
  %t34 = ptrtoint ptr %t33 to i64
  switch i64 %t34, label %case.default.35 [ i64 3, label %case.arm.3.37 i64 4, label %case.arm.4.51 ]
case.arm.3.37:
  %t39 = call ptr @__alloc(i64 24, i32 2)
  %t40 = inttoptr i64 7 to ptr
  %t41 = getelementptr ptr, ptr %t39, i32 0
  store ptr %t40, ptr %t41
  %t42 = getelementptr ptr, ptr %t39, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t42
  %t43 = call ptr @__alloc(i64 16, i32 1)
  %t44 = inttoptr i64 5 to ptr
  %t45 = getelementptr ptr, ptr %t43, i32 0
  store ptr %t44, ptr %t45
  %t46 = call ptr @__alloc(i64 8, i32 0)
  %t47 = inttoptr i64 0 to ptr
  %t48 = getelementptr ptr, ptr %t46, i32 0
  store ptr %t47, ptr %t48
  %t49 = getelementptr ptr, ptr %t43, i32 1
  store ptr %t46, ptr %t49
  %t50 = getelementptr ptr, ptr %t39, i32 2
  store ptr %t43, ptr %t50
  br label %case.end.3.38
case.end.3.38:
  br label %case.join.36
case.arm.4.51:
  %t53 = getelementptr ptr, ptr %t31, i32 1
  %t54 = load ptr, ptr %t53
  call void @__inc_ref(ptr %t54)
  %t55 = call ptr @__alloc(i64 24, i32 2)
  %t56 = inttoptr i64 7 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  call void @__inc_ref(ptr %t54)
  %t58 = getelementptr ptr, ptr %t55, i32 1
  store ptr %t54, ptr %t58
  %t59 = call ptr @__alloc(i64 16, i32 1)
  %t60 = inttoptr i64 5 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  %t62 = call ptr @__alloc(i64 8, i32 0)
  %t63 = inttoptr i64 0 to ptr
  %t64 = getelementptr ptr, ptr %t62, i32 0
  store ptr %t63, ptr %t64
  %t65 = getelementptr ptr, ptr %t59, i32 1
  store ptr %t62, ptr %t65
  %t66 = getelementptr ptr, ptr %t55, i32 2
  store ptr %t59, ptr %t66
  br label %case.end.4.52
case.end.4.52:
  br label %case.join.36
case.default.35:
  unreachable
case.join.36:
  %t67 = phi ptr [ %t39, %case.end.3.38 ], [ %t55, %case.end.4.52 ]
  call void @__free_recursive(ptr %t31)
  call void @__free_recursive(ptr %t1)
  ret ptr %t67
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
