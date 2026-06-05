; External C declarations
declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare ptr @memcpy(ptr, ptr, i64)
declare i64 @write(i32, ptr, i64)
declare i32 @snprintf(ptr, i64, ptr, ...)

@.fmt_i32 = private unnamed_addr constant [3 x i8] c"%d\00"

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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [9 x i8]} { i32 0, i32 0, i32 0, i32 9, i32 9, [9 x i8] c"underflow" }

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


define internal ptr @__showInt32(ptr %p) {
  %v = load i32, ptr %p
  %buf = call ptr @__alloc(i64 24, i32 0)
  %payload = getelementptr i8, ptr %buf, i64 8
  %n = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %payload, i64 16, ptr @.fmt_i32, i32 %v)
  store i32 %n, ptr %buf
  %u16p = getelementptr i8, ptr %buf, i64 4
  store i32 %n, ptr %u16p
  call void @__free_recursive(ptr %p)
  ret ptr %buf
}


define internal ptr @__predInt32(ptr %p) {
  %v = load i32, ptr %p
  %is_min = icmp eq i32 %v, -2147483648
  br i1 %is_min, label %overflow, label %ok
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
  %newv = sub i32 %v, 1
  %box = call ptr @__alloc(i64 4, i32 0)
  store i32 %newv, ptr %box
  %right = call ptr @__alloc(i64 16, i32 1)
  %right_tag = inttoptr i64 4 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %box, ptr %right_f
  call void @__free_recursive(ptr %p)
  ret ptr %right
}


define internal ptr @__eqInt32(ptr %a, ptr %b) {
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

define internal ptr @v_bBox() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 24 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 8, i32 0)
  %t4 = inttoptr i64 25 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  ret ptr %t0
}

define internal ptr @v_main() {
  %t0 = call ptr @__alloc(i64 4, i32 0)
  store i32 1000000, ptr %t0
  %t1 = call ptr @v_a(ptr %t0)
  %t2 = getelementptr ptr, ptr %t1, i32 0
  %t3 = load ptr, ptr %t2
  %t4 = ptrtoint ptr %t3 to i64
  switch i64 %t4, label %case.default.5 [ i64 3, label %case.arm.3.7 i64 4, label %case.arm.4.23 ]
case.arm.3.7:
  %t9 = getelementptr ptr, ptr %t1, i32 1
  %t10 = load ptr, ptr %t9
  call void @__inc_ref(ptr %t10)
  %t11 = call ptr @__alloc(i64 24, i32 2)
  %t12 = inttoptr i64 7 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  %t14 = getelementptr ptr, ptr %t11, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t14
  %t15 = call ptr @__alloc(i64 16, i32 1)
  %t16 = inttoptr i64 5 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = call ptr @__alloc(i64 8, i32 0)
  %t19 = inttoptr i64 0 to ptr
  %t20 = getelementptr ptr, ptr %t18, i32 0
  store ptr %t19, ptr %t20
  %t21 = getelementptr ptr, ptr %t15, i32 1
  store ptr %t18, ptr %t21
  %t22 = getelementptr ptr, ptr %t11, i32 2
  store ptr %t15, ptr %t22
  br label %case.end.3.8
case.end.3.8:
  br label %case.join.6
case.arm.4.23:
  %t25 = getelementptr ptr, ptr %t1, i32 1
  %t26 = load ptr, ptr %t25
  call void @__inc_ref(ptr %t26)
  %t27 = call ptr @__alloc(i64 24, i32 2)
  %t28 = inttoptr i64 7 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  call void @__inc_ref(ptr %t26)
  %t30 = call ptr @__showInt32(ptr %t26)
  %t31 = getelementptr ptr, ptr %t27, i32 1
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
  %t39 = getelementptr ptr, ptr %t27, i32 2
  store ptr %t32, ptr %t39
  br label %case.end.4.24
case.end.4.24:
  br label %case.join.6
case.default.5:
  unreachable
case.join.6:
  %t40 = phi ptr [ %t11, %case.end.3.8 ], [ %t27, %case.end.4.24 ]
  call void @__free_recursive(ptr %t1)
  ret ptr %t40
}

define internal ptr @v__scc__apply1__lam_23_a_b(ptr %v__args) {
entry:
  %t3 = alloca ptr
  store ptr %v__args, ptr %t3
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t4 = load ptr, ptr %t3
  %t5 = getelementptr ptr, ptr %t4, i32 0
  %t6 = load ptr, ptr %t5
  %t7 = ptrtoint ptr %t6 to i64
  switch i64 %t7, label %tco.case.default.8 [ i64 26, label %tco.case.arm.26.9 i64 27, label %tco.case.arm.27.23 i64 28, label %tco.case.arm.28.39 i64 29, label %tco.case.arm.29.83 ]
tco.case.arm.26.9:
  %t10 = getelementptr ptr, ptr %t4, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  %t12 = getelementptr ptr, ptr %t4, i32 2
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t11, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %tco.case.default.17 [ i64 25, label %tco.case.arm.25.18 ]
tco.case.arm.25.18:
  %t19 = call ptr @__alloc(i64 16, i32 1)
  %t20 = inttoptr i64 27 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  call void @__inc_ref(ptr %t13)
  %t22 = getelementptr ptr, ptr %t19, i32 1
  store ptr %t13, ptr %t22
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t19, ptr %t3
  br label %tco.loop.0
tco.case.default.17:
  unreachable
tco.case.arm.27.23:
  %t24 = getelementptr ptr, ptr %t4, i32 1
  %t25 = load ptr, ptr %t24
  %t26 = getelementptr i8, ptr %t4, i64 -8
  %t27 = load i32, ptr %t26
  %t28 = icmp eq i32 %t27, 1
  br i1 %t28, label %reuse.in_place.29, label %reuse.copy.30
reuse.in_place.29:
  %t32 = inttoptr i64 29 to ptr
  %t33 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t32, ptr %t33
  br label %reuse.join.31
reuse.copy.30:
  %t34 = call ptr @__alloc(i64 16, i32 1)
  %t35 = inttoptr i64 29 to ptr
  %t36 = getelementptr ptr, ptr %t34, i32 0
  store ptr %t35, ptr %t36
  call void @__inc_ref(ptr %t25)
  %t37 = getelementptr ptr, ptr %t34, i32 1
  store ptr %t25, ptr %t37
  call void @__free_recursive(ptr %t4)
  br label %reuse.join.31
reuse.join.31:
  %t38 = phi ptr [ %t4, %reuse.in_place.29 ], [ %t34, %reuse.copy.30 ]
  store ptr %t38, ptr %t3
  br label %tco.loop.0
tco.case.arm.28.39:
  %t40 = getelementptr ptr, ptr %t4, i32 1
  %t41 = load ptr, ptr %t40
  call void @__inc_ref(ptr %t41)
  call void @__inc_ref(ptr %t41)
  %t42 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t42
  %t43 = call ptr @__eqInt32(ptr %t41, ptr %t42)
  %t44 = getelementptr ptr, ptr %t43, i32 0
  %t45 = load ptr, ptr %t44
  %t46 = ptrtoint ptr %t45 to i64
  switch i64 %t46, label %tco.case.default.47 [ i64 1, label %tco.case.arm.1.48 i64 2, label %tco.case.arm.2.54 ]
tco.case.arm.1.48:
  %t49 = call ptr @__alloc(i64 16, i32 1)
  %t50 = inttoptr i64 4 to ptr
  %t51 = getelementptr ptr, ptr %t49, i32 0
  store ptr %t50, ptr %t51
  %t52 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t52
  %t53 = getelementptr ptr, ptr %t49, i32 1
  store ptr %t52, ptr %t53
  call void @__free_recursive(ptr %t43)
  call void @__free_recursive(ptr %t41)
  call void @__free_recursive(ptr %t4)
  store ptr %t49, ptr %t2
  br label %tco.exit.1
tco.case.arm.2.54:
  call void @__inc_ref(ptr %t41)
  %t55 = call ptr @__predInt32(ptr %t41)
  %t56 = getelementptr ptr, ptr %t55, i32 0
  %t57 = load ptr, ptr %t56
  %t58 = ptrtoint ptr %t57 to i64
  switch i64 %t58, label %tco.case.default.59 [ i64 3, label %tco.case.arm.3.60 i64 4, label %tco.case.arm.4.67 ]
tco.case.arm.3.60:
  %t61 = getelementptr ptr, ptr %t55, i32 1
  %t62 = load ptr, ptr %t61
  call void @__inc_ref(ptr %t62)
  %t63 = call ptr @__alloc(i64 16, i32 1)
  %t64 = inttoptr i64 3 to ptr
  %t65 = getelementptr ptr, ptr %t63, i32 0
  store ptr %t64, ptr %t65
  call void @__inc_ref(ptr %t62)
  %t66 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t62, ptr %t66
  call void @__free_recursive(ptr %t55)
  call void @__free_recursive(ptr %t43)
  call void @__free_recursive(ptr %t62)
  call void @__free_recursive(ptr %t41)
  call void @__free_recursive(ptr %t4)
  store ptr %t63, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.67:
  %t68 = getelementptr ptr, ptr %t55, i32 1
  %t69 = load ptr, ptr %t68
  call void @__inc_ref(ptr %t69)
  %t70 = call ptr @v_bBox()
  %t71 = getelementptr ptr, ptr %t70, i32 0
  %t72 = load ptr, ptr %t71
  %t73 = ptrtoint ptr %t72 to i64
  switch i64 %t73, label %tco.case.default.74 [ i64 24, label %tco.case.arm.24.75 ]
tco.case.arm.24.75:
  %t76 = getelementptr ptr, ptr %t70, i32 1
  %t77 = load ptr, ptr %t76
  call void @__inc_ref(ptr %t77)
  %t78 = call ptr @__alloc(i64 24, i32 2)
  %t79 = inttoptr i64 26 to ptr
  %t80 = getelementptr ptr, ptr %t78, i32 0
  store ptr %t79, ptr %t80
  call void @__inc_ref(ptr %t77)
  %t81 = getelementptr ptr, ptr %t78, i32 1
  store ptr %t77, ptr %t81
  call void @__inc_ref(ptr %t69)
  %t82 = getelementptr ptr, ptr %t78, i32 2
  store ptr %t69, ptr %t82
  call void @__free_recursive(ptr %t70)
  call void @__free_recursive(ptr %t55)
  call void @__free_recursive(ptr %t43)
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t77)
  call void @__free_recursive(ptr %t69)
  call void @__free_recursive(ptr %t41)
  store ptr %t78, ptr %t3
  br label %tco.loop.0
tco.case.default.74:
  unreachable
tco.case.default.59:
  unreachable
tco.case.default.47:
  unreachable
tco.case.arm.29.83:
  %t84 = getelementptr ptr, ptr %t4, i32 1
  %t85 = load ptr, ptr %t84
  call void @__inc_ref(ptr %t85)
  call void @__inc_ref(ptr %t85)
  %t86 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t86
  %t87 = call ptr @__eqInt32(ptr %t85, ptr %t86)
  %t88 = getelementptr ptr, ptr %t87, i32 0
  %t89 = load ptr, ptr %t88
  %t90 = ptrtoint ptr %t89 to i64
  switch i64 %t90, label %tco.case.default.91 [ i64 1, label %tco.case.arm.1.92 i64 2, label %tco.case.arm.2.98 ]
tco.case.arm.1.92:
  %t93 = call ptr @__alloc(i64 16, i32 1)
  %t94 = inttoptr i64 4 to ptr
  %t95 = getelementptr ptr, ptr %t93, i32 0
  store ptr %t94, ptr %t95
  %t96 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t96
  %t97 = getelementptr ptr, ptr %t93, i32 1
  store ptr %t96, ptr %t97
  call void @__free_recursive(ptr %t87)
  call void @__free_recursive(ptr %t85)
  call void @__free_recursive(ptr %t4)
  store ptr %t93, ptr %t2
  br label %tco.exit.1
tco.case.arm.2.98:
  call void @__inc_ref(ptr %t85)
  %t99 = call ptr @__predInt32(ptr %t85)
  %t100 = getelementptr ptr, ptr %t99, i32 0
  %t101 = load ptr, ptr %t100
  %t102 = ptrtoint ptr %t101 to i64
  switch i64 %t102, label %tco.case.default.103 [ i64 3, label %tco.case.arm.3.104 i64 4, label %tco.case.arm.4.111 ]
tco.case.arm.3.104:
  %t105 = getelementptr ptr, ptr %t99, i32 1
  %t106 = load ptr, ptr %t105
  call void @__inc_ref(ptr %t106)
  %t107 = call ptr @__alloc(i64 16, i32 1)
  %t108 = inttoptr i64 3 to ptr
  %t109 = getelementptr ptr, ptr %t107, i32 0
  store ptr %t108, ptr %t109
  call void @__inc_ref(ptr %t106)
  %t110 = getelementptr ptr, ptr %t107, i32 1
  store ptr %t106, ptr %t110
  call void @__free_recursive(ptr %t99)
  call void @__free_recursive(ptr %t87)
  call void @__free_recursive(ptr %t106)
  call void @__free_recursive(ptr %t85)
  call void @__free_recursive(ptr %t4)
  store ptr %t107, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.111:
  %t112 = getelementptr ptr, ptr %t99, i32 1
  %t113 = load ptr, ptr %t112
  call void @__inc_ref(ptr %t113)
  %t114 = getelementptr i8, ptr %t4, i64 -8
  %t115 = load i32, ptr %t114
  %t116 = icmp eq i32 %t115, 1
  br i1 %t116, label %reuse.in_place.117, label %reuse.copy.118
reuse.in_place.117:
  %t120 = getelementptr ptr, ptr %t4, i32 1
  %t121 = load ptr, ptr %t120
  call void @__free_recursive(ptr %t121)
  %t123 = inttoptr i64 28 to ptr
  %t124 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t123, ptr %t124
  call void @__inc_ref(ptr %t113)
  %t122 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t113, ptr %t122
  br label %reuse.join.119
reuse.copy.118:
  %t125 = call ptr @__alloc(i64 16, i32 1)
  %t126 = inttoptr i64 28 to ptr
  %t127 = getelementptr ptr, ptr %t125, i32 0
  store ptr %t126, ptr %t127
  call void @__inc_ref(ptr %t113)
  %t128 = getelementptr ptr, ptr %t125, i32 1
  store ptr %t113, ptr %t128
  call void @__free_recursive(ptr %t4)
  br label %reuse.join.119
reuse.join.119:
  %t129 = phi ptr [ %t4, %reuse.in_place.117 ], [ %t125, %reuse.copy.118 ]
  call void @__free_recursive(ptr %t99)
  call void @__free_recursive(ptr %t87)
  call void @__free_recursive(ptr %t113)
  call void @__free_recursive(ptr %t85)
  store ptr %t129, ptr %t3
  br label %tco.loop.0
tco.case.default.103:
  unreachable
tco.case.default.91:
  unreachable
tco.case.default.8:
  unreachable
tco.exit.1:
  %t130 = load ptr, ptr %t2
  ret ptr %t130
}

define internal ptr @v_a(ptr %v_n) {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 28 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  call void @__inc_ref(ptr %v_n)
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v_n, ptr %t3
  %t4 = call ptr @v__scc__apply1__lam_23_a_b(ptr %t0)
  call void @__free_recursive(ptr %v_n)
  ret ptr %t4
}

define i32 @main(i32 %argc, ptr %argv) {
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
