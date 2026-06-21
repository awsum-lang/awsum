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

define internal ptr @v_buildLeft(ptr %v_n, ptr %v_acc) {
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
  %t7 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t7
  %t8 = call ptr @__eqInt32(ptr %t5, ptr %t7)
  %t9 = getelementptr ptr, ptr %t8, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %tco.case.default.12 [ i64 1, label %tco.case.arm.1.13 i64 2, label %tco.case.arm.2.14 ]
tco.case.arm.1.13:
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.2.14:
  call void @__inc_ref(ptr %t5)
  %t15 = call ptr @__predInt32(ptr %t5)
  %t16 = getelementptr ptr, ptr %t15, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %tco.case.default.19 [ i64 3, label %tco.case.arm.3.20 i64 4, label %tco.case.arm.4.21 ]
tco.case.arm.3.20:
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.21:
  %t22 = getelementptr ptr, ptr %t15, i32 1
  %t23 = load ptr, ptr %t22
  call void @__inc_ref(ptr %t23)
  %t24 = call ptr @__alloc(i64 32, i32 3)
  %t25 = inttoptr i64 25 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  call void @__inc_ref(ptr %t6)
  %t27 = getelementptr ptr, ptr %t24, i32 1
  store ptr %t6, ptr %t27
  %t28 = call ptr @__alloc(i64 16, i32 1)
  %t29 = inttoptr i64 2711245919 to ptr
  %t30 = getelementptr ptr, ptr %t28, i32 0
  store ptr %t29, ptr %t30
  %t31 = call ptr @__alloc(i64 4, i32 0)
  store i32 1, ptr %t31
  %t32 = getelementptr ptr, ptr %t28, i32 1
  store ptr %t31, ptr %t32
  %t33 = getelementptr ptr, ptr %t24, i32 2
  store ptr %t28, ptr %t33
  %t34 = call ptr @__alloc(i64 8, i32 0)
  %t35 = inttoptr i64 24 to ptr
  %t36 = getelementptr ptr, ptr %t34, i32 0
  store ptr %t35, ptr %t36
  %t37 = getelementptr ptr, ptr %t24, i32 3
  store ptr %t34, ptr %t37
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  store ptr %t23, ptr %t3
  store ptr %t24, ptr %t4
  br label %tco.loop.0
tco.case.default.19:
  unreachable
tco.case.default.12:
  unreachable
tco.exit.1:
  %t38 = load ptr, ptr %t2
  ret ptr %t38
}

define internal ptr @v_main() {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 7 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 24, i32 2)
  %t4 = inttoptr i64 30 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = call ptr @__alloc(i64 4, i32 0)
  store i32 200000, ptr %t6
  %t7 = call ptr @__alloc(i64 8, i32 0)
  %t8 = inttoptr i64 24 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = call ptr @v_buildLeft(ptr %t6, ptr %t7)
  %t11 = getelementptr ptr, ptr %t3, i32 1
  store ptr %t10, ptr %t11
  %t12 = call ptr @__alloc(i64 8, i32 0)
  %t13 = inttoptr i64 26 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t3, i32 2
  store ptr %t12, ptr %t15
  %t16 = call ptr @v__scc__apply_sumTree__cps_sumTree(ptr %t3)
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

define internal ptr @v__scc__apply_sumTree__cps_sumTree(ptr %v__args) {
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
  switch i64 %t7, label %tco.case.default.8 [ i64 29, label %tco.case.arm.29.9 i64 30, label %tco.case.arm.30.91 ]
tco.case.arm.29.9:
  %t10 = getelementptr ptr, ptr %t4, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  %t12 = getelementptr ptr, ptr %t4, i32 2
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t11, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %tco.case.default.17 [ i64 26, label %tco.case.arm.26.18 i64 28, label %tco.case.arm.28.19 i64 27, label %tco.case.arm.27.70 ]
tco.case.arm.26.18:
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %t4)
  store ptr %t13, ptr %t2
  br label %tco.exit.1
tco.case.arm.28.19:
  %t20 = getelementptr ptr, ptr %t11, i32 1
  %t21 = load ptr, ptr %t20
  call void @__inc_ref(ptr %t21)
  %t22 = getelementptr ptr, ptr %t11, i32 2
  %t23 = load ptr, ptr %t22
  call void @__inc_ref(ptr %t23)
  call void @__inc_ref(ptr %t13)
  %t24 = call ptr @__addInt32(ptr %t23, ptr %t13)
  %t25 = getelementptr ptr, ptr %t24, i32 0
  %t26 = load ptr, ptr %t25
  %t27 = ptrtoint ptr %t26 to i64
  switch i64 %t27, label %tco.case.default.28 [ i64 3, label %tco.case.arm.3.29 i64 4, label %tco.case.arm.4.39 ]
tco.case.arm.3.29:
  %t30 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t30
  %t31 = getelementptr ptr, ptr %t4, i32 1
  %t32 = load ptr, ptr %t31
  call void @__free_recursive(ptr %t32)
  %t33 = getelementptr ptr, ptr %t4, i32 2
  %t34 = load ptr, ptr %t33
  call void @__free_recursive(ptr %t34)
  %t37 = inttoptr i64 29 to ptr
  %t38 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t37, ptr %t38
  call void @__inc_ref(ptr %t21)
  %t35 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t21, ptr %t35
  %t36 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t30, ptr %t36
  call void @__free_recursive(ptr %t24)
  call void @__free_recursive(ptr %t21)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.4.39:
  %t40 = getelementptr ptr, ptr %t24, i32 1
  %t41 = load ptr, ptr %t40
  call void @__inc_ref(ptr %t41)
  call void @__inc_ref(ptr %t41)
  %t42 = getelementptr ptr, ptr %t11, i32 3
  %t43 = load ptr, ptr %t42
  call void @__inc_ref(ptr %t43)
  %t44 = call ptr @__addInt32(ptr %t41, ptr %t43)
  %t45 = getelementptr ptr, ptr %t44, i32 0
  %t46 = load ptr, ptr %t45
  %t47 = ptrtoint ptr %t46 to i64
  switch i64 %t47, label %tco.case.default.48 [ i64 3, label %tco.case.arm.3.49 i64 4, label %tco.case.arm.4.59 ]
tco.case.arm.3.49:
  %t50 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t50
  %t51 = getelementptr ptr, ptr %t4, i32 1
  %t52 = load ptr, ptr %t51
  call void @__free_recursive(ptr %t52)
  %t53 = getelementptr ptr, ptr %t4, i32 2
  %t54 = load ptr, ptr %t53
  call void @__free_recursive(ptr %t54)
  %t57 = inttoptr i64 29 to ptr
  %t58 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t57, ptr %t58
  call void @__inc_ref(ptr %t21)
  %t55 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t21, ptr %t55
  %t56 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t50, ptr %t56
  call void @__free_recursive(ptr %t44)
  call void @__free_recursive(ptr %t24)
  call void @__free_recursive(ptr %t41)
  call void @__free_recursive(ptr %t21)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.4.59:
  %t60 = getelementptr ptr, ptr %t44, i32 1
  %t61 = load ptr, ptr %t60
  call void @__inc_ref(ptr %t61)
  %t62 = getelementptr ptr, ptr %t4, i32 1
  %t63 = load ptr, ptr %t62
  call void @__free_recursive(ptr %t63)
  %t64 = getelementptr ptr, ptr %t4, i32 2
  %t65 = load ptr, ptr %t64
  call void @__free_recursive(ptr %t65)
  %t68 = inttoptr i64 29 to ptr
  %t69 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t68, ptr %t69
  call void @__inc_ref(ptr %t21)
  %t66 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t21, ptr %t66
  call void @__inc_ref(ptr %t61)
  %t67 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t61, ptr %t67
  call void @__free_recursive(ptr %t44)
  call void @__free_recursive(ptr %t24)
  call void @__free_recursive(ptr %t61)
  call void @__free_recursive(ptr %t41)
  call void @__free_recursive(ptr %t21)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.48:
  unreachable
tco.case.default.28:
  unreachable
tco.case.arm.27.70:
  %t71 = getelementptr ptr, ptr %t11, i32 3
  %t72 = load ptr, ptr %t71
  call void @__inc_ref(ptr %t72)
  %t73 = call ptr @__alloc(i64 32, i32 3)
  %t74 = inttoptr i64 28 to ptr
  %t75 = getelementptr ptr, ptr %t73, i32 0
  store ptr %t74, ptr %t75
  %t76 = getelementptr ptr, ptr %t11, i32 1
  %t77 = load ptr, ptr %t76
  call void @__inc_ref(ptr %t77)
  %t78 = getelementptr ptr, ptr %t73, i32 1
  store ptr %t77, ptr %t78
  call void @__inc_ref(ptr %t13)
  %t79 = getelementptr ptr, ptr %t73, i32 2
  store ptr %t13, ptr %t79
  %t80 = getelementptr ptr, ptr %t11, i32 2
  %t81 = load ptr, ptr %t80
  call void @__inc_ref(ptr %t81)
  %t82 = getelementptr ptr, ptr %t73, i32 3
  store ptr %t81, ptr %t82
  %t83 = getelementptr ptr, ptr %t4, i32 1
  %t84 = load ptr, ptr %t83
  call void @__free_recursive(ptr %t84)
  %t85 = getelementptr ptr, ptr %t4, i32 2
  %t86 = load ptr, ptr %t85
  call void @__free_recursive(ptr %t86)
  %t89 = inttoptr i64 30 to ptr
  %t90 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t89, ptr %t90
  %t87 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t72, ptr %t87
  %t88 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t73, ptr %t88
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.17:
  unreachable
tco.case.arm.30.91:
  %t92 = getelementptr ptr, ptr %t4, i32 1
  %t93 = load ptr, ptr %t92
  call void @__inc_ref(ptr %t93)
  %t94 = getelementptr ptr, ptr %t4, i32 2
  %t95 = load ptr, ptr %t94
  call void @__inc_ref(ptr %t95)
  %t96 = getelementptr ptr, ptr %t93, i32 0
  %t97 = load ptr, ptr %t96
  %t98 = ptrtoint ptr %t97 to i64
  switch i64 %t98, label %tco.case.default.99 [ i64 24, label %tco.case.arm.24.100 i64 25, label %tco.case.arm.25.110 ]
tco.case.arm.24.100:
  %t101 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t101
  %t102 = getelementptr ptr, ptr %t4, i32 1
  %t103 = load ptr, ptr %t102
  call void @__free_recursive(ptr %t103)
  %t104 = getelementptr ptr, ptr %t4, i32 2
  %t105 = load ptr, ptr %t104
  call void @__free_recursive(ptr %t105)
  %t108 = inttoptr i64 29 to ptr
  %t109 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t108, ptr %t109
  call void @__inc_ref(ptr %t95)
  %t106 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t95, ptr %t106
  %t107 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t101, ptr %t107
  call void @__free_recursive(ptr %t93)
  call void @__free_recursive(ptr %t95)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.arm.25.110:
  %t111 = getelementptr ptr, ptr %t93, i32 1
  %t112 = load ptr, ptr %t111
  call void @__inc_ref(ptr %t112)
  %t113 = getelementptr ptr, ptr %t93, i32 2
  %t114 = load ptr, ptr %t113
  call void @__inc_ref(ptr %t114)
  %t115 = getelementptr ptr, ptr %t93, i32 3
  %t116 = load ptr, ptr %t115
  %t117 = getelementptr ptr, ptr %t4, i32 1
  %t118 = load ptr, ptr %t117
  call void @__free_recursive(ptr %t118)
  %t119 = getelementptr ptr, ptr %t4, i32 2
  %t120 = load ptr, ptr %t119
  call void @__free_recursive(ptr %t120)
  %t148 = inttoptr i64 30 to ptr
  %t149 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t148, ptr %t149
  call void @__inc_ref(ptr %t112)
  %t121 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t112, ptr %t121
  %t122 = getelementptr ptr, ptr %t114, i32 1
  %t123 = load ptr, ptr %t122
  call void @__inc_ref(ptr %t123)
  %t132 = getelementptr i8, ptr %t93, i64 -8
  %t133 = load i32, ptr %t132
  %t134 = icmp eq i32 %t133, 1
  br i1 %t134, label %reuse.in_place.135, label %reuse.copy.136
reuse.in_place.135:
  %t124 = getelementptr ptr, ptr %t93, i32 1
  %t125 = load ptr, ptr %t124
  call void @__free_recursive(ptr %t125)
  %t126 = getelementptr ptr, ptr %t93, i32 2
  %t127 = load ptr, ptr %t126
  call void @__free_recursive(ptr %t127)
  %t130 = inttoptr i64 27 to ptr
  %t131 = getelementptr ptr, ptr %t93, i32 0
  store ptr %t130, ptr %t131
  call void @__inc_ref(ptr %t95)
  %t128 = getelementptr ptr, ptr %t93, i32 1
  store ptr %t95, ptr %t128
  %t129 = getelementptr ptr, ptr %t93, i32 2
  store ptr %t123, ptr %t129
  br label %reuse.in_place.end.138
reuse.in_place.end.138:
  br label %reuse.join.137
reuse.copy.136:
  %t140 = call ptr @__alloc(i64 32, i32 3)
  %t141 = inttoptr i64 27 to ptr
  %t142 = getelementptr ptr, ptr %t140, i32 0
  store ptr %t141, ptr %t142
  call void @__inc_ref(ptr %t95)
  %t143 = getelementptr ptr, ptr %t140, i32 1
  store ptr %t95, ptr %t143
  %t144 = getelementptr ptr, ptr %t140, i32 2
  store ptr %t123, ptr %t144
  call void @__inc_ref(ptr %t116)
  %t145 = getelementptr ptr, ptr %t140, i32 3
  store ptr %t116, ptr %t145
  call void @__free_recursive(ptr %t93)
  br label %reuse.copy.end.139
reuse.copy.end.139:
  br label %reuse.join.137
reuse.join.137:
  %t146 = phi ptr [ %t93, %reuse.in_place.end.138 ], [ %t140, %reuse.copy.end.139 ]
  %t147 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t146, ptr %t147
  call void @__free_recursive(ptr %t114)
  call void @__free_recursive(ptr %t112)
  call void @__free_recursive(ptr %t95)
  store ptr %t4, ptr %t3
  br label %tco.loop.0
tco.case.default.99:
  unreachable
tco.case.default.8:
  unreachable
tco.exit.1:
  %t150 = load ptr, ptr %t2
  ret ptr %t150
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
