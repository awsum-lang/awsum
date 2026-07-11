; External C declarations
declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare ptr @memcpy(ptr, ptr, i64)
declare i64 @write(i32, ptr, i64)
declare i32 @snprintf(ptr, i64, ptr, ...)
declare {i32, i1} @llvm.sadd.with.overflow.i32(i32, i32)

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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [8 x i8]} { i32 0, i32 0, i32 0, i32 8, i32 8, [8 x i8] c"OVERFLOW" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [9 x i8]} { i32 0, i32 0, i32 0, i32 9, i32 9, [9 x i8] c"UNDERFLOW" }

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


define internal ptr @__addInt32(ptr %pa, ptr %pb) {
  %a = load i32, ptr %pa
  %b = load i32, ptr %pb
  %res = call {i32, i1} @llvm.sadd.with.overflow.i32(i32 %a, i32 %b)
  %sum = extractvalue {i32, i1} %res, 0
  %ovf = extractvalue {i32, i1} %res, 1
  br i1 %ovf, label %err, label %ok
err:
  %is_pos = icmp sge i32 %a, 0
  %row_tag_idx = select i1 %is_pos, i64 882564211, i64 3768445577
  %inner_tag_idx = select i1 %is_pos, i64 18, i64 17
  %inner = call ptr @__alloc(i64 8, i32 0)
  %inner_tag = inttoptr i64 %inner_tag_idx to ptr
  store ptr %inner_tag, ptr %inner
  %row = call ptr @__alloc(i64 16, i32 1)
  %row_tag = inttoptr i64 %row_tag_idx to ptr
  store ptr %row_tag, ptr %row
  %row_f = getelementptr ptr, ptr %row, i32 1
  store ptr %inner, ptr %row_f
  %left = call ptr @__alloc(i64 16, i32 1)
  %left_tag = inttoptr i64 3 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %row, ptr %left_f
  br label %join
ok:
  %box = call ptr @__alloc(i64 4, i32 0)
  store i32 %sum, ptr %box
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

define internal ptr @v_seven() {
  %t0 = call ptr @__alloc(i64 4, i32 0)
  store i32 7, ptr %t0
  ret ptr %t0
}

define internal ptr @v_direct() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 24 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 4, i32 0)
  store i32 7, ptr %t3
  %t4 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t4
  ret ptr %t0
}

define internal ptr @v_nested() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 25 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 16, i32 1)
  %t4 = inttoptr i64 1730259187 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = call ptr @__alloc(i64 16, i32 1)
  %t7 = inttoptr i64 24 to ptr
  %t8 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t7, ptr %t8
  %t9 = call ptr @__alloc(i64 4, i32 0)
  store i32 7, ptr %t9
  %t10 = getelementptr ptr, ptr %t6, i32 1
  store ptr %t9, ptr %t10
  %t11 = getelementptr ptr, ptr %t3, i32 1
  store ptr %t6, ptr %t11
  %t12 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t12
  ret ptr %t0
}

define internal ptr @v_bare() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 25 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 16, i32 1)
  %t4 = inttoptr i64 2711245919 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = call ptr @__alloc(i64 4, i32 0)
  store i32 7, ptr %t6
  %t7 = getelementptr ptr, ptr %t3, i32 1
  store ptr %t6, ptr %t7
  %t8 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t8
  ret ptr %t0
}

define internal ptr @v_ascribed() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 25 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 16, i32 1)
  %t4 = inttoptr i64 1730259187 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = call ptr @__alloc(i64 16, i32 1)
  %t7 = inttoptr i64 24 to ptr
  %t8 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t7, ptr %t8
  %t9 = call ptr @__alloc(i64 4, i32 0)
  store i32 7, ptr %t9
  %t10 = getelementptr ptr, ptr %t6, i32 1
  store ptr %t9, ptr %t10
  %t11 = getelementptr ptr, ptr %t3, i32 1
  store ptr %t6, ptr %t11
  %t12 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t12
  ret ptr %t0
}

define internal ptr @v_named() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 25 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 16, i32 1)
  %t4 = inttoptr i64 1730259187 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = call ptr @__alloc(i64 16, i32 1)
  %t7 = inttoptr i64 24 to ptr
  %t8 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t7, ptr %t8
  %t9 = call ptr @v_seven()
  %t10 = getelementptr ptr, ptr %t6, i32 1
  store ptr %t9, ptr %t10
  %t11 = getelementptr ptr, ptr %t3, i32 1
  store ptr %t6, ptr %t11
  %t12 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t12
  ret ptr %t0
}

define internal ptr @v_wrapped() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 28 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 16, i32 1)
  %t4 = inttoptr i64 1519763639 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = call ptr @__alloc(i64 16, i32 1)
  %t7 = inttoptr i64 26 to ptr
  %t8 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t7, ptr %t8
  %t9 = call ptr @__alloc(i64 4, i32 0)
  store i32 7, ptr %t9
  %t10 = getelementptr ptr, ptr %t6, i32 1
  store ptr %t9, ptr %t10
  %t11 = getelementptr ptr, ptr %t3, i32 1
  store ptr %t6, ptr %t11
  %t12 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t12
  ret ptr %t0
}

define internal ptr @v_shown() {
  %t0 = call ptr @v_direct()
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 24, label %case.arm.24.6 i64 25, label %case.arm.25.10 ]
case.arm.24.6:
  %t8 = getelementptr ptr, ptr %t0, i32 1
  %t9 = load ptr, ptr %t8
  call void @__inc_ref(ptr %t9)
  br label %case.end.24.7
case.end.24.7:
  br label %case.join.5
case.arm.25.10:
  %t12 = getelementptr ptr, ptr %t0, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t13, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %case.default.17 [ i64 1730259187, label %case.arm.1730259187.19 i64 2711245919, label %case.arm.2711245919.36 ]
case.arm.1730259187.19:
  %t21 = getelementptr ptr, ptr %t13, i32 1
  %t22 = load ptr, ptr %t21
  call void @__inc_ref(ptr %t22)
  %t23 = getelementptr ptr, ptr %t22, i32 0
  %t24 = load ptr, ptr %t23
  %t25 = ptrtoint ptr %t24 to i64
  switch i64 %t25, label %case.default.26 [ i64 24, label %case.arm.24.28 i64 25, label %case.arm.25.32 ]
case.arm.24.28:
  %t30 = getelementptr ptr, ptr %t22, i32 1
  %t31 = load ptr, ptr %t30
  call void @__inc_ref(ptr %t31)
  br label %case.end.24.29
case.end.24.29:
  br label %case.join.27
case.arm.25.32:
  %t34 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t34
  br label %case.end.25.33
case.end.25.33:
  br label %case.join.27
case.default.26:
  unreachable
case.join.27:
  %t35 = phi ptr [ %t31, %case.end.24.29 ], [ %t34, %case.end.25.33 ]
  br label %case.end.1730259187.20
case.end.1730259187.20:
  br label %case.join.18
case.arm.2711245919.36:
  %t38 = getelementptr ptr, ptr %t13, i32 1
  %t39 = load ptr, ptr %t38
  call void @__inc_ref(ptr %t39)
  br label %case.end.2711245919.37
case.end.2711245919.37:
  br label %case.join.18
case.default.17:
  unreachable
case.join.18:
  %t40 = phi ptr [ %t35, %case.end.1730259187.20 ], [ %t39, %case.end.2711245919.37 ]
  br label %case.end.25.11
case.end.25.11:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t41 = phi ptr [ %t9, %case.end.24.7 ], [ %t40, %case.end.25.11 ]
  call void @__free_recursive(ptr %t0)
  %t42 = call ptr @v_nested()
  %t43 = getelementptr ptr, ptr %t42, i32 0
  %t44 = load ptr, ptr %t43
  %t45 = ptrtoint ptr %t44 to i64
  switch i64 %t45, label %case.default.46 [ i64 24, label %case.arm.24.48 i64 25, label %case.arm.25.52 ]
case.arm.24.48:
  %t50 = getelementptr ptr, ptr %t42, i32 1
  %t51 = load ptr, ptr %t50
  call void @__inc_ref(ptr %t51)
  br label %case.end.24.49
case.end.24.49:
  br label %case.join.47
case.arm.25.52:
  %t54 = getelementptr ptr, ptr %t42, i32 1
  %t55 = load ptr, ptr %t54
  call void @__inc_ref(ptr %t55)
  %t56 = getelementptr ptr, ptr %t55, i32 0
  %t57 = load ptr, ptr %t56
  %t58 = ptrtoint ptr %t57 to i64
  switch i64 %t58, label %case.default.59 [ i64 1730259187, label %case.arm.1730259187.61 i64 2711245919, label %case.arm.2711245919.78 ]
case.arm.1730259187.61:
  %t63 = getelementptr ptr, ptr %t55, i32 1
  %t64 = load ptr, ptr %t63
  call void @__inc_ref(ptr %t64)
  %t65 = getelementptr ptr, ptr %t64, i32 0
  %t66 = load ptr, ptr %t65
  %t67 = ptrtoint ptr %t66 to i64
  switch i64 %t67, label %case.default.68 [ i64 24, label %case.arm.24.70 i64 25, label %case.arm.25.74 ]
case.arm.24.70:
  %t72 = getelementptr ptr, ptr %t64, i32 1
  %t73 = load ptr, ptr %t72
  call void @__inc_ref(ptr %t73)
  br label %case.end.24.71
case.end.24.71:
  br label %case.join.69
case.arm.25.74:
  %t76 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t76
  br label %case.end.25.75
case.end.25.75:
  br label %case.join.69
case.default.68:
  unreachable
case.join.69:
  %t77 = phi ptr [ %t73, %case.end.24.71 ], [ %t76, %case.end.25.75 ]
  br label %case.end.1730259187.62
case.end.1730259187.62:
  br label %case.join.60
case.arm.2711245919.78:
  %t80 = getelementptr ptr, ptr %t55, i32 1
  %t81 = load ptr, ptr %t80
  call void @__inc_ref(ptr %t81)
  br label %case.end.2711245919.79
case.end.2711245919.79:
  br label %case.join.60
case.default.59:
  unreachable
case.join.60:
  %t82 = phi ptr [ %t77, %case.end.1730259187.62 ], [ %t81, %case.end.2711245919.79 ]
  br label %case.end.25.53
case.end.25.53:
  br label %case.join.47
case.default.46:
  unreachable
case.join.47:
  %t83 = phi ptr [ %t51, %case.end.24.49 ], [ %t82, %case.end.25.53 ]
  call void @__free_recursive(ptr %t42)
  %t84 = call ptr @__addInt32(ptr %t41, ptr %t83)
  %t85 = getelementptr ptr, ptr %t84, i32 0
  %t86 = load ptr, ptr %t85
  %t87 = ptrtoint ptr %t86 to i64
  switch i64 %t87, label %case.default.88 [ i64 3, label %case.arm.3.90 i64 4, label %case.arm.4.98 ]
case.arm.3.90:
  %t92 = getelementptr ptr, ptr %t84, i32 1
  %t93 = load ptr, ptr %t92
  call void @__inc_ref(ptr %t93)
  %t94 = call ptr @__alloc(i64 16, i32 1)
  %t95 = inttoptr i64 3 to ptr
  %t96 = getelementptr ptr, ptr %t94, i32 0
  store ptr %t95, ptr %t96
  call void @__inc_ref(ptr %t93)
  %t97 = getelementptr ptr, ptr %t94, i32 1
  store ptr %t93, ptr %t97
  br label %case.end.3.91
case.end.3.91:
  br label %case.join.89
case.arm.4.98:
  %t100 = getelementptr ptr, ptr %t84, i32 1
  %t101 = load ptr, ptr %t100
  call void @__inc_ref(ptr %t101)
  call void @__inc_ref(ptr %t101)
  %t102 = call ptr @v_bare()
  %t103 = getelementptr ptr, ptr %t102, i32 0
  %t104 = load ptr, ptr %t103
  %t105 = ptrtoint ptr %t104 to i64
  switch i64 %t105, label %case.default.106 [ i64 24, label %case.arm.24.108 i64 25, label %case.arm.25.112 ]
case.arm.24.108:
  %t110 = getelementptr ptr, ptr %t102, i32 1
  %t111 = load ptr, ptr %t110
  call void @__inc_ref(ptr %t111)
  br label %case.end.24.109
case.end.24.109:
  br label %case.join.107
case.arm.25.112:
  %t114 = getelementptr ptr, ptr %t102, i32 1
  %t115 = load ptr, ptr %t114
  call void @__inc_ref(ptr %t115)
  %t116 = getelementptr ptr, ptr %t115, i32 0
  %t117 = load ptr, ptr %t116
  %t118 = ptrtoint ptr %t117 to i64
  switch i64 %t118, label %case.default.119 [ i64 1730259187, label %case.arm.1730259187.121 i64 2711245919, label %case.arm.2711245919.138 ]
case.arm.1730259187.121:
  %t123 = getelementptr ptr, ptr %t115, i32 1
  %t124 = load ptr, ptr %t123
  call void @__inc_ref(ptr %t124)
  %t125 = getelementptr ptr, ptr %t124, i32 0
  %t126 = load ptr, ptr %t125
  %t127 = ptrtoint ptr %t126 to i64
  switch i64 %t127, label %case.default.128 [ i64 24, label %case.arm.24.130 i64 25, label %case.arm.25.134 ]
case.arm.24.130:
  %t132 = getelementptr ptr, ptr %t124, i32 1
  %t133 = load ptr, ptr %t132
  call void @__inc_ref(ptr %t133)
  br label %case.end.24.131
case.end.24.131:
  br label %case.join.129
case.arm.25.134:
  %t136 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t136
  br label %case.end.25.135
case.end.25.135:
  br label %case.join.129
case.default.128:
  unreachable
case.join.129:
  %t137 = phi ptr [ %t133, %case.end.24.131 ], [ %t136, %case.end.25.135 ]
  br label %case.end.1730259187.122
case.end.1730259187.122:
  br label %case.join.120
case.arm.2711245919.138:
  %t140 = getelementptr ptr, ptr %t115, i32 1
  %t141 = load ptr, ptr %t140
  call void @__inc_ref(ptr %t141)
  br label %case.end.2711245919.139
case.end.2711245919.139:
  br label %case.join.120
case.default.119:
  unreachable
case.join.120:
  %t142 = phi ptr [ %t137, %case.end.1730259187.122 ], [ %t141, %case.end.2711245919.139 ]
  br label %case.end.25.113
case.end.25.113:
  br label %case.join.107
case.default.106:
  unreachable
case.join.107:
  %t143 = phi ptr [ %t111, %case.end.24.109 ], [ %t142, %case.end.25.113 ]
  call void @__free_recursive(ptr %t102)
  %t144 = call ptr @__addInt32(ptr %t101, ptr %t143)
  %t145 = getelementptr ptr, ptr %t144, i32 0
  %t146 = load ptr, ptr %t145
  %t147 = ptrtoint ptr %t146 to i64
  switch i64 %t147, label %case.default.148 [ i64 3, label %case.arm.3.150 i64 4, label %case.arm.4.158 ]
case.arm.3.150:
  %t152 = getelementptr ptr, ptr %t144, i32 1
  %t153 = load ptr, ptr %t152
  call void @__inc_ref(ptr %t153)
  %t154 = call ptr @__alloc(i64 16, i32 1)
  %t155 = inttoptr i64 3 to ptr
  %t156 = getelementptr ptr, ptr %t154, i32 0
  store ptr %t155, ptr %t156
  call void @__inc_ref(ptr %t153)
  %t157 = getelementptr ptr, ptr %t154, i32 1
  store ptr %t153, ptr %t157
  br label %case.end.3.151
case.end.3.151:
  br label %case.join.149
case.arm.4.158:
  %t160 = getelementptr ptr, ptr %t144, i32 1
  %t161 = load ptr, ptr %t160
  call void @__inc_ref(ptr %t161)
  call void @__inc_ref(ptr %t161)
  %t162 = call ptr @v_ascribed()
  %t163 = getelementptr ptr, ptr %t162, i32 0
  %t164 = load ptr, ptr %t163
  %t165 = ptrtoint ptr %t164 to i64
  switch i64 %t165, label %case.default.166 [ i64 24, label %case.arm.24.168 i64 25, label %case.arm.25.172 ]
case.arm.24.168:
  %t170 = getelementptr ptr, ptr %t162, i32 1
  %t171 = load ptr, ptr %t170
  call void @__inc_ref(ptr %t171)
  br label %case.end.24.169
case.end.24.169:
  br label %case.join.167
case.arm.25.172:
  %t174 = getelementptr ptr, ptr %t162, i32 1
  %t175 = load ptr, ptr %t174
  call void @__inc_ref(ptr %t175)
  %t176 = getelementptr ptr, ptr %t175, i32 0
  %t177 = load ptr, ptr %t176
  %t178 = ptrtoint ptr %t177 to i64
  switch i64 %t178, label %case.default.179 [ i64 1730259187, label %case.arm.1730259187.181 i64 2711245919, label %case.arm.2711245919.198 ]
case.arm.1730259187.181:
  %t183 = getelementptr ptr, ptr %t175, i32 1
  %t184 = load ptr, ptr %t183
  call void @__inc_ref(ptr %t184)
  %t185 = getelementptr ptr, ptr %t184, i32 0
  %t186 = load ptr, ptr %t185
  %t187 = ptrtoint ptr %t186 to i64
  switch i64 %t187, label %case.default.188 [ i64 24, label %case.arm.24.190 i64 25, label %case.arm.25.194 ]
case.arm.24.190:
  %t192 = getelementptr ptr, ptr %t184, i32 1
  %t193 = load ptr, ptr %t192
  call void @__inc_ref(ptr %t193)
  br label %case.end.24.191
case.end.24.191:
  br label %case.join.189
case.arm.25.194:
  %t196 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t196
  br label %case.end.25.195
case.end.25.195:
  br label %case.join.189
case.default.188:
  unreachable
case.join.189:
  %t197 = phi ptr [ %t193, %case.end.24.191 ], [ %t196, %case.end.25.195 ]
  br label %case.end.1730259187.182
case.end.1730259187.182:
  br label %case.join.180
case.arm.2711245919.198:
  %t200 = getelementptr ptr, ptr %t175, i32 1
  %t201 = load ptr, ptr %t200
  call void @__inc_ref(ptr %t201)
  br label %case.end.2711245919.199
case.end.2711245919.199:
  br label %case.join.180
case.default.179:
  unreachable
case.join.180:
  %t202 = phi ptr [ %t197, %case.end.1730259187.182 ], [ %t201, %case.end.2711245919.199 ]
  br label %case.end.25.173
case.end.25.173:
  br label %case.join.167
case.default.166:
  unreachable
case.join.167:
  %t203 = phi ptr [ %t171, %case.end.24.169 ], [ %t202, %case.end.25.173 ]
  call void @__free_recursive(ptr %t162)
  %t204 = call ptr @__addInt32(ptr %t161, ptr %t203)
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
  call void @__inc_ref(ptr %t221)
  %t222 = call ptr @v_named()
  %t223 = getelementptr ptr, ptr %t222, i32 0
  %t224 = load ptr, ptr %t223
  %t225 = ptrtoint ptr %t224 to i64
  switch i64 %t225, label %case.default.226 [ i64 24, label %case.arm.24.228 i64 25, label %case.arm.25.232 ]
case.arm.24.228:
  %t230 = getelementptr ptr, ptr %t222, i32 1
  %t231 = load ptr, ptr %t230
  call void @__inc_ref(ptr %t231)
  br label %case.end.24.229
case.end.24.229:
  br label %case.join.227
case.arm.25.232:
  %t234 = getelementptr ptr, ptr %t222, i32 1
  %t235 = load ptr, ptr %t234
  call void @__inc_ref(ptr %t235)
  %t236 = getelementptr ptr, ptr %t235, i32 0
  %t237 = load ptr, ptr %t236
  %t238 = ptrtoint ptr %t237 to i64
  switch i64 %t238, label %case.default.239 [ i64 1730259187, label %case.arm.1730259187.241 i64 2711245919, label %case.arm.2711245919.258 ]
case.arm.1730259187.241:
  %t243 = getelementptr ptr, ptr %t235, i32 1
  %t244 = load ptr, ptr %t243
  call void @__inc_ref(ptr %t244)
  %t245 = getelementptr ptr, ptr %t244, i32 0
  %t246 = load ptr, ptr %t245
  %t247 = ptrtoint ptr %t246 to i64
  switch i64 %t247, label %case.default.248 [ i64 24, label %case.arm.24.250 i64 25, label %case.arm.25.254 ]
case.arm.24.250:
  %t252 = getelementptr ptr, ptr %t244, i32 1
  %t253 = load ptr, ptr %t252
  call void @__inc_ref(ptr %t253)
  br label %case.end.24.251
case.end.24.251:
  br label %case.join.249
case.arm.25.254:
  %t256 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t256
  br label %case.end.25.255
case.end.25.255:
  br label %case.join.249
case.default.248:
  unreachable
case.join.249:
  %t257 = phi ptr [ %t253, %case.end.24.251 ], [ %t256, %case.end.25.255 ]
  br label %case.end.1730259187.242
case.end.1730259187.242:
  br label %case.join.240
case.arm.2711245919.258:
  %t260 = getelementptr ptr, ptr %t235, i32 1
  %t261 = load ptr, ptr %t260
  call void @__inc_ref(ptr %t261)
  br label %case.end.2711245919.259
case.end.2711245919.259:
  br label %case.join.240
case.default.239:
  unreachable
case.join.240:
  %t262 = phi ptr [ %t257, %case.end.1730259187.242 ], [ %t261, %case.end.2711245919.259 ]
  br label %case.end.25.233
case.end.25.233:
  br label %case.join.227
case.default.226:
  unreachable
case.join.227:
  %t263 = phi ptr [ %t231, %case.end.24.229 ], [ %t262, %case.end.25.233 ]
  call void @__free_recursive(ptr %t222)
  %t264 = call ptr @__addInt32(ptr %t221, ptr %t263)
  %t265 = getelementptr ptr, ptr %t264, i32 0
  %t266 = load ptr, ptr %t265
  %t267 = ptrtoint ptr %t266 to i64
  switch i64 %t267, label %case.default.268 [ i64 3, label %case.arm.3.270 i64 4, label %case.arm.4.278 ]
case.arm.3.270:
  %t272 = getelementptr ptr, ptr %t264, i32 1
  %t273 = load ptr, ptr %t272
  call void @__inc_ref(ptr %t273)
  %t274 = call ptr @__alloc(i64 16, i32 1)
  %t275 = inttoptr i64 3 to ptr
  %t276 = getelementptr ptr, ptr %t274, i32 0
  store ptr %t275, ptr %t276
  call void @__inc_ref(ptr %t273)
  %t277 = getelementptr ptr, ptr %t274, i32 1
  store ptr %t273, ptr %t277
  br label %case.end.3.271
case.end.3.271:
  br label %case.join.269
case.arm.4.278:
  %t280 = getelementptr ptr, ptr %t264, i32 1
  %t281 = load ptr, ptr %t280
  call void @__inc_ref(ptr %t281)
  call void @__inc_ref(ptr %t281)
  %t282 = call ptr @v_wrapped()
  %t283 = getelementptr ptr, ptr %t282, i32 0
  %t284 = load ptr, ptr %t283
  %t285 = ptrtoint ptr %t284 to i64
  switch i64 %t285, label %case.default.286 [ i64 28, label %case.arm.28.288 ]
case.arm.28.288:
  %t290 = getelementptr ptr, ptr %t282, i32 1
  %t291 = load ptr, ptr %t290
  call void @__inc_ref(ptr %t291)
  %t292 = getelementptr ptr, ptr %t291, i32 0
  %t293 = load ptr, ptr %t292
  %t294 = ptrtoint ptr %t293 to i64
  switch i64 %t294, label %case.default.295 [ i64 1519763639, label %case.arm.1519763639.297 i64 2711245919, label %case.arm.2711245919.303 ]
case.arm.1519763639.297:
  %t299 = getelementptr ptr, ptr %t291, i32 1
  %t300 = load ptr, ptr %t299
  call void @__inc_ref(ptr %t300)
  %t301 = getelementptr ptr, ptr %t300, i32 1
  %t302 = load ptr, ptr %t301
  call void @__inc_ref(ptr %t302)
  br label %case.end.1519763639.298
case.end.1519763639.298:
  br label %case.join.296
case.arm.2711245919.303:
  %t305 = getelementptr ptr, ptr %t291, i32 1
  %t306 = load ptr, ptr %t305
  call void @__inc_ref(ptr %t306)
  br label %case.end.2711245919.304
case.end.2711245919.304:
  br label %case.join.296
case.default.295:
  unreachable
case.join.296:
  %t307 = phi ptr [ %t302, %case.end.1519763639.298 ], [ %t306, %case.end.2711245919.304 ]
  br label %case.end.28.289
case.end.28.289:
  br label %case.join.287
case.default.286:
  unreachable
case.join.287:
  %t308 = phi ptr [ %t307, %case.end.28.289 ]
  call void @__free_recursive(ptr %t282)
  %t309 = call ptr @__addInt32(ptr %t281, ptr %t308)
  %t310 = getelementptr ptr, ptr %t309, i32 0
  %t311 = load ptr, ptr %t310
  %t312 = ptrtoint ptr %t311 to i64
  switch i64 %t312, label %case.default.313 [ i64 3, label %case.arm.3.315 i64 4, label %case.arm.4.323 ]
case.arm.3.315:
  %t317 = getelementptr ptr, ptr %t309, i32 1
  %t318 = load ptr, ptr %t317
  call void @__inc_ref(ptr %t318)
  %t319 = call ptr @__alloc(i64 16, i32 1)
  %t320 = inttoptr i64 3 to ptr
  %t321 = getelementptr ptr, ptr %t319, i32 0
  store ptr %t320, ptr %t321
  call void @__inc_ref(ptr %t318)
  %t322 = getelementptr ptr, ptr %t319, i32 1
  store ptr %t318, ptr %t322
  br label %case.end.3.316
case.end.3.316:
  br label %case.join.314
case.arm.4.323:
  %t325 = getelementptr ptr, ptr %t309, i32 1
  %t326 = load ptr, ptr %t325
  call void @__inc_ref(ptr %t326)
  %t327 = call ptr @__alloc(i64 16, i32 1)
  %t328 = inttoptr i64 4 to ptr
  %t329 = getelementptr ptr, ptr %t327, i32 0
  store ptr %t328, ptr %t329
  call void @__inc_ref(ptr %t326)
  %t330 = call ptr @__showInt32(ptr %t326)
  %t331 = getelementptr ptr, ptr %t327, i32 1
  store ptr %t330, ptr %t331
  br label %case.end.4.324
case.end.4.324:
  br label %case.join.314
case.default.313:
  unreachable
case.join.314:
  %t332 = phi ptr [ %t319, %case.end.3.316 ], [ %t327, %case.end.4.324 ]
  call void @__free_recursive(ptr %t309)
  br label %case.end.4.279
case.end.4.279:
  br label %case.join.269
case.default.268:
  unreachable
case.join.269:
  %t333 = phi ptr [ %t274, %case.end.3.271 ], [ %t332, %case.end.4.279 ]
  call void @__free_recursive(ptr %t264)
  br label %case.end.4.219
case.end.4.219:
  br label %case.join.209
case.default.208:
  unreachable
case.join.209:
  %t334 = phi ptr [ %t214, %case.end.3.211 ], [ %t333, %case.end.4.219 ]
  call void @__free_recursive(ptr %t204)
  br label %case.end.4.159
case.end.4.159:
  br label %case.join.149
case.default.148:
  unreachable
case.join.149:
  %t335 = phi ptr [ %t154, %case.end.3.151 ], [ %t334, %case.end.4.159 ]
  call void @__free_recursive(ptr %t144)
  br label %case.end.4.99
case.end.4.99:
  br label %case.join.89
case.default.88:
  unreachable
case.join.89:
  %t336 = phi ptr [ %t94, %case.end.3.91 ], [ %t335, %case.end.4.99 ]
  call void @__free_recursive(ptr %t84)
  ret ptr %t336
}

define internal ptr @v_main() {
  %t0 = call ptr @v_shown()
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
  %t24 = inttoptr i64 31 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  %t26 = call ptr @v_$cps$$df$$rowmono$0$andThenIO$4(ptr %t22, ptr %t23)
  %t27 = call ptr @__alloc(i64 8, i32 0)
  %t28 = inttoptr i64 29 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.13 i64 7, label %tco.case.arm.7.51 ]
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
  %t14 = getelementptr ptr, ptr %t5, i32 1
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  %t16 = getelementptr ptr, ptr %t15, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %case.default.19 [ i64 882564211, label %case.arm.882564211.21 i64 3768445577, label %case.arm.3768445577.35 ]
case.arm.882564211.21:
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
  br label %case.end.882564211.22
case.end.882564211.22:
  br label %case.join.20
case.arm.3768445577.35:
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
  br label %case.end.3768445577.36
case.end.3768445577.36:
  br label %case.join.20
case.default.19:
  unreachable
case.join.20:
  %t49 = phi ptr [ %t23, %case.end.882564211.22 ], [ %t37, %case.end.3768445577.36 ]
  call void @__free_recursive(ptr %t15)
  %t50 = call ptr @v_$apply$$df$handleErrorIO$0(ptr %t6, ptr %t49)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t50, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.51:
  %t52 = getelementptr ptr, ptr %t5, i32 1
  %t53 = load ptr, ptr %t52
  %t54 = getelementptr ptr, ptr %t5, i32 2
  %t55 = load ptr, ptr %t54
  call void @__inc_ref(ptr %t55)
  %t62 = getelementptr i8, ptr %t5, i64 -8
  %t63 = load i32, ptr %t62
  %t64 = icmp eq i32 %t63, 1
  br i1 %t64, label %reuse.in_place.65, label %reuse.copy.66
reuse.in_place.65:
  %t56 = getelementptr ptr, ptr %t5, i32 2
  %t57 = load ptr, ptr %t56
  call void @__free_recursive(ptr %t57)
  %t60 = inttoptr i64 30 to ptr
  %t61 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t60, ptr %t61
  call void @__inc_ref(ptr %t6)
  %t58 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t58
  %t59 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t53, ptr %t59
  br label %reuse.in_place.end.68
reuse.in_place.end.68:
  br label %reuse.join.67
reuse.copy.66:
  %t70 = call ptr @__alloc(i64 24, i32 2)
  %t71 = inttoptr i64 30 to ptr
  %t72 = getelementptr ptr, ptr %t70, i32 0
  store ptr %t71, ptr %t72
  call void @__inc_ref(ptr %t6)
  %t73 = getelementptr ptr, ptr %t70, i32 1
  store ptr %t6, ptr %t73
  call void @__inc_ref(ptr %t53)
  %t74 = getelementptr ptr, ptr %t70, i32 2
  store ptr %t53, ptr %t74
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.69
reuse.copy.end.69:
  br label %reuse.join.67
reuse.join.67:
  %t75 = phi ptr [ %t5, %reuse.in_place.end.68 ], [ %t70, %reuse.copy.end.69 ]
  call void @__free_recursive(ptr %t6)
  store ptr %t55, ptr %t3
  store ptr %t75, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t76 = load ptr, ptr %t2
  ret ptr %t76
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
  switch i64 %t9, label %tco.case.default.10 [ i64 29, label %tco.case.arm.29.11 i64 30, label %tco.case.arm.30.12 ]
tco.case.arm.29.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.30.12:
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

define internal ptr @v_$cps$$df$$rowmono$0$andThenIO$4(ptr %v_io, ptr %v_$k) {
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
  %t26 = call ptr @v_$apply$$df$$rowmono$0$andThenIO$4(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t26, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.27:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t28 = call ptr @v_$apply$$df$$rowmono$0$andThenIO$4(ptr %t6, ptr %t5)
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
  %t38 = inttoptr i64 32 to ptr
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
  %t49 = inttoptr i64 32 to ptr
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

define internal ptr @v_$apply$$df$$rowmono$0$andThenIO$4(ptr %v_$k, ptr %v_$x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 31, label %tco.case.arm.31.11 i64 32, label %tco.case.arm.32.12 ]
tco.case.arm.31.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.32.12:
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

define i32 @main(i32 %argc, ptr %argv) {
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
