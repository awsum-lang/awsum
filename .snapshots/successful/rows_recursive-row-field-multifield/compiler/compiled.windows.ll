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

define internal ptr @v_v() {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 25 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 16, i32 1)
  %t4 = inttoptr i64 1907350996 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = call ptr @__alloc(i64 24, i32 2)
  %t7 = inttoptr i64 25 to ptr
  %t8 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t7, ptr %t8
  %t9 = call ptr @__alloc(i64 16, i32 1)
  %t10 = inttoptr i64 1907350996 to ptr
  %t11 = getelementptr ptr, ptr %t9, i32 0
  store ptr %t10, ptr %t11
  %t12 = call ptr @__alloc(i64 16, i32 1)
  %t13 = inttoptr i64 24 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = call ptr @__alloc(i64 4, i32 0)
  store i32 1, ptr %t15
  %t16 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t15, ptr %t16
  %t17 = getelementptr ptr, ptr %t9, i32 1
  store ptr %t12, ptr %t17
  %t18 = getelementptr ptr, ptr %t6, i32 1
  store ptr %t9, ptr %t18
  %t19 = call ptr @__alloc(i64 16, i32 1)
  %t20 = inttoptr i64 1907350996 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = call ptr @__alloc(i64 16, i32 1)
  %t23 = inttoptr i64 24 to ptr
  %t24 = getelementptr ptr, ptr %t22, i32 0
  store ptr %t23, ptr %t24
  %t25 = call ptr @__alloc(i64 4, i32 0)
  store i32 2, ptr %t25
  %t26 = getelementptr ptr, ptr %t22, i32 1
  store ptr %t25, ptr %t26
  %t27 = getelementptr ptr, ptr %t19, i32 1
  store ptr %t22, ptr %t27
  %t28 = getelementptr ptr, ptr %t6, i32 2
  store ptr %t19, ptr %t28
  %t29 = getelementptr ptr, ptr %t3, i32 1
  store ptr %t6, ptr %t29
  %t30 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t30
  %t31 = call ptr @__alloc(i64 16, i32 1)
  %t32 = inttoptr i64 1907350996 to ptr
  %t33 = getelementptr ptr, ptr %t31, i32 0
  store ptr %t32, ptr %t33
  %t34 = call ptr @__alloc(i64 16, i32 1)
  %t35 = inttoptr i64 24 to ptr
  %t36 = getelementptr ptr, ptr %t34, i32 0
  store ptr %t35, ptr %t36
  %t37 = call ptr @__alloc(i64 4, i32 0)
  store i32 3, ptr %t37
  %t38 = getelementptr ptr, ptr %t34, i32 1
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t31, i32 1
  store ptr %t34, ptr %t39
  %t40 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t31, ptr %t40
  ret ptr %t0
}

define internal ptr @v_main() {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 7 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 24, i32 2)
  %t4 = inttoptr i64 32 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = call ptr @__alloc(i64 16, i32 1)
  %t7 = inttoptr i64 27 to ptr
  %t8 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t7, ptr %t8
  %t9 = call ptr @v_v()
  %t10 = getelementptr ptr, ptr %t6, i32 1
  store ptr %t9, ptr %t10
  %t11 = getelementptr ptr, ptr %t3, i32 1
  store ptr %t6, ptr %t11
  %t12 = call ptr @__alloc(i64 8, i32 0)
  %t13 = inttoptr i64 28 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t3, i32 2
  store ptr %t12, ptr %t15
  %t16 = call ptr @v_$scc$$apply$$scc$sumSide__sumT__$cps$$scc$sumSide__sumT(ptr %t3)
  %t17 = call ptr @__showInt32(ptr %t16)
  %t18 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t17, ptr %t18
  %t19 = call ptr @__alloc(i64 16, i32 1)
  %t20 = inttoptr i64 5 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = call ptr @__alloc(i64 8, i32 0)
  %t23 = inttoptr i64 0 to ptr
  %t24 = getelementptr ptr, ptr %t22, i32 0
  store ptr %t23, ptr %t24
  %t25 = getelementptr ptr, ptr %t19, i32 1
  store ptr %t22, ptr %t25
  %t26 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t19, ptr %t26
  ret ptr %t0
}

define internal ptr @v_$scc$$apply$$scc$sumSide__sumT__$cps$$scc$sumSide__sumT(ptr %v_$args$1) {
entry:
  %t3 = alloca ptr
  store ptr %v_$args$1, ptr %t3
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t4 = load ptr, ptr %t3
  %t5 = getelementptr ptr, ptr %t4, i32 0
  %t6 = load ptr, ptr %t5
  %t7 = ptrtoint ptr %t6 to i64
  switch i64 %t7, label %tco.case.default.8 [ i64 31, label %tco.case.arm.31.9 i64 32, label %tco.case.arm.32.66 ]
tco.case.arm.31.9:
  %t10 = getelementptr ptr, ptr %t4, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  %t12 = getelementptr ptr, ptr %t4, i32 2
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t11, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %tco.case.default.17 [ i64 28, label %tco.case.arm.28.18 i64 30, label %tco.case.arm.30.19 i64 29, label %tco.case.arm.29.44 ]
tco.case.arm.28.18:
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %t4)
  store ptr %t13, ptr %t2
  br label %tco.exit.1
tco.case.arm.30.19:
  %t20 = getelementptr ptr, ptr %t11, i32 1
  %t21 = load ptr, ptr %t20
  call void @__inc_ref(ptr %t21)
  %t22 = getelementptr ptr, ptr %t11, i32 2
  %t23 = load ptr, ptr %t22
  call void @__inc_ref(ptr %t23)
  call void @__inc_ref(ptr %t23)
  call void @__inc_ref(ptr %t13)
  %t24 = call ptr @__addInt32(ptr %t23, ptr %t13)
  %t25 = getelementptr ptr, ptr %t24, i32 0
  %t26 = load ptr, ptr %t25
  %t27 = ptrtoint ptr %t26 to i64
  switch i64 %t27, label %tco.case.default.28 [ i64 3, label %tco.case.arm.3.29 i64 4, label %tco.case.arm.4.36 ]
tco.case.arm.3.29:
  call void @__free_recursive(ptr %t24)
  %t30 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t30
  %t31 = getelementptr ptr, ptr %t11, i32 2
  %t32 = load ptr, ptr %t31
  call void @__free_recursive(ptr %t32)
  %t34 = inttoptr i64 31 to ptr
  %t35 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t34, ptr %t35
  %t33 = getelementptr ptr, ptr %t11, i32 2
  store ptr %t30, ptr %t33
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t23)
  call void @__free_recursive(ptr %t21)
  call void @__free_recursive(ptr %t13)
  store ptr %t11, ptr %t3
  br label %tco.loop.0
tco.case.arm.4.36:
  %t37 = getelementptr ptr, ptr %t24, i32 1
  %t38 = load ptr, ptr %t37
  call void @__inc_ref(ptr %t38)
  call void @__free_recursive(ptr %t24)
  %t39 = getelementptr ptr, ptr %t11, i32 2
  %t40 = load ptr, ptr %t39
  call void @__free_recursive(ptr %t40)
  %t42 = inttoptr i64 31 to ptr
  %t43 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t42, ptr %t43
  call void @__inc_ref(ptr %t38)
  %t41 = getelementptr ptr, ptr %t11, i32 2
  store ptr %t38, ptr %t41
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t38)
  call void @__free_recursive(ptr %t23)
  call void @__free_recursive(ptr %t21)
  call void @__free_recursive(ptr %t13)
  store ptr %t11, ptr %t3
  br label %tco.loop.0
tco.case.default.28:
  unreachable
tco.case.arm.29.44:
  %t45 = getelementptr ptr, ptr %t11, i32 1
  %t46 = load ptr, ptr %t45
  %t47 = getelementptr ptr, ptr %t11, i32 2
  %t48 = load ptr, ptr %t47
  call void @__inc_ref(ptr %t48)
  %t49 = call ptr @__alloc(i64 16, i32 1)
  %t50 = inttoptr i64 26 to ptr
  %t51 = getelementptr ptr, ptr %t49, i32 0
  store ptr %t50, ptr %t51
  call void @__inc_ref(ptr %t48)
  %t52 = getelementptr ptr, ptr %t49, i32 1
  store ptr %t48, ptr %t52
  %t53 = getelementptr ptr, ptr %t4, i32 1
  %t54 = load ptr, ptr %t53
  call void @__free_recursive(ptr %t54)
  %t55 = getelementptr ptr, ptr %t4, i32 2
  %t56 = load ptr, ptr %t55
  call void @__free_recursive(ptr %t56)
  %t64 = inttoptr i64 32 to ptr
  %t65 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t64, ptr %t65
  %t57 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t49, ptr %t57
  %t58 = getelementptr ptr, ptr %t11, i32 2
  %t59 = load ptr, ptr %t58
  call void @__free_recursive(ptr %t59)
  %t61 = inttoptr i64 30 to ptr
  %t62 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t61, ptr %t62
  call void @__inc_ref(ptr %t13)
  %t60 = getelementptr ptr, ptr %t11, i32 2
  store ptr %t13, ptr %t60
  %t63 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t11, ptr %t63
  call void @__free_recursive(ptr %t48)
  call void @__free_recursive(ptr %t13)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.17:
  unreachable
tco.case.arm.32.66:
  %t67 = getelementptr ptr, ptr %t4, i32 1
  %t68 = load ptr, ptr %t67
  call void @__inc_ref(ptr %t68)
  %t69 = getelementptr ptr, ptr %t4, i32 2
  %t70 = load ptr, ptr %t69
  call void @__inc_ref(ptr %t70)
  %t71 = getelementptr ptr, ptr %t68, i32 0
  %t72 = load ptr, ptr %t71
  %t73 = ptrtoint ptr %t72 to i64
  switch i64 %t73, label %tco.case.default.74 [ i64 26, label %tco.case.arm.26.75 i64 27, label %tco.case.arm.27.90 ]
tco.case.arm.26.75:
  %t76 = getelementptr ptr, ptr %t68, i32 1
  %t77 = load ptr, ptr %t76
  call void @__inc_ref(ptr %t77)
  %t78 = getelementptr ptr, ptr %t4, i32 1
  %t79 = load ptr, ptr %t78
  call void @__free_recursive(ptr %t79)
  %t88 = inttoptr i64 32 to ptr
  %t89 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t88, ptr %t89
  %t80 = getelementptr ptr, ptr %t77, i32 1
  %t81 = load ptr, ptr %t80
  call void @__inc_ref(ptr %t81)
  %t82 = getelementptr ptr, ptr %t68, i32 1
  %t83 = load ptr, ptr %t82
  call void @__free_recursive(ptr %t83)
  %t85 = inttoptr i64 27 to ptr
  %t86 = getelementptr ptr, ptr %t68, i32 0
  store ptr %t85, ptr %t86
  %t84 = getelementptr ptr, ptr %t68, i32 1
  store ptr %t81, ptr %t84
  %t87 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t68, ptr %t87
  call void @__free_recursive(ptr %t77)
  call void @__free_recursive(ptr %t70)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.27.90:
  %t91 = getelementptr ptr, ptr %t68, i32 1
  %t92 = load ptr, ptr %t91
  call void @__inc_ref(ptr %t92)
  %t93 = getelementptr ptr, ptr %t92, i32 0
  %t94 = load ptr, ptr %t93
  %t95 = ptrtoint ptr %t94 to i64
  switch i64 %t95, label %tco.case.default.96 [ i64 24, label %tco.case.arm.24.97 i64 25, label %tco.case.arm.25.108 ]
tco.case.arm.24.97:
  %t98 = getelementptr ptr, ptr %t92, i32 1
  %t99 = load ptr, ptr %t98
  call void @__inc_ref(ptr %t99)
  %t100 = getelementptr ptr, ptr %t4, i32 1
  %t101 = load ptr, ptr %t100
  call void @__free_recursive(ptr %t101)
  %t102 = getelementptr ptr, ptr %t4, i32 2
  %t103 = load ptr, ptr %t102
  call void @__free_recursive(ptr %t103)
  %t106 = inttoptr i64 31 to ptr
  %t107 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t106, ptr %t107
  call void @__inc_ref(ptr %t70)
  %t104 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t70, ptr %t104
  %t105 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t99, ptr %t105
  call void @__free_recursive(ptr %t68)
  call void @__free_recursive(ptr %t92)
  call void @__free_recursive(ptr %t70)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.25.108:
  %t109 = call ptr @__alloc(i64 24, i32 2)
  %t110 = inttoptr i64 32 to ptr
  %t111 = getelementptr ptr, ptr %t109, i32 0
  store ptr %t110, ptr %t111
  %t112 = getelementptr ptr, ptr %t92, i32 1
  %t113 = load ptr, ptr %t112
  call void @__inc_ref(ptr %t113)
  %t114 = getelementptr ptr, ptr %t68, i32 1
  %t115 = load ptr, ptr %t114
  call void @__free_recursive(ptr %t115)
  %t117 = inttoptr i64 26 to ptr
  %t118 = getelementptr ptr, ptr %t68, i32 0
  store ptr %t117, ptr %t118
  %t116 = getelementptr ptr, ptr %t68, i32 1
  store ptr %t113, ptr %t116
  %t119 = getelementptr ptr, ptr %t109, i32 1
  store ptr %t68, ptr %t119
  %t120 = getelementptr ptr, ptr %t92, i32 2
  %t121 = load ptr, ptr %t120
  call void @__inc_ref(ptr %t121)
  %t122 = getelementptr ptr, ptr %t4, i32 1
  %t123 = load ptr, ptr %t122
  call void @__free_recursive(ptr %t123)
  %t124 = getelementptr ptr, ptr %t4, i32 2
  %t125 = load ptr, ptr %t124
  call void @__free_recursive(ptr %t125)
  %t128 = inttoptr i64 29 to ptr
  %t129 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t128, ptr %t129
  call void @__inc_ref(ptr %t70)
  %t126 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t70, ptr %t126
  %t127 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t121, ptr %t127
  %t130 = getelementptr ptr, ptr %t109, i32 2
  store ptr %t4, ptr %t130
  call void @__free_recursive(ptr %t92)
  call void @__free_recursive(ptr %t70)
  store ptr %t109, ptr %t3
  br label %tco.loop.0
tco.case.default.96:
  unreachable
tco.case.default.74:
  unreachable
tco.case.default.8:
  unreachable
tco.exit.1:
  %t131 = load ptr, ptr %t2
  ret ptr %t131
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
