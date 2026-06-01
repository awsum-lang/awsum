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
  %oe_tag = inttoptr i64 16 to ptr
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
  %inner_tag_idx = select i1 %is_pos, i64 17, i64 16
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
  %result = phi ptr [%left, %err], [%right, %ok]
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
  switch i64 %t18, label %tco.case.default.19 [ i64 3, label %tco.case.arm.3.20 i64 4, label %tco.case.arm.4.23 ]
tco.case.arm.3.20:
  %t21 = getelementptr ptr, ptr %t15, i32 1
  %t22 = load ptr, ptr %t21
  call void @__inc_ref(ptr %t22)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t22)
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.23:
  %t24 = getelementptr ptr, ptr %t15, i32 1
  %t25 = load ptr, ptr %t24
  call void @__inc_ref(ptr %t25)
  %t26 = call ptr @__alloc(i64 32, i32 3)
  %t27 = inttoptr i64 23 to ptr
  %t28 = getelementptr ptr, ptr %t26, i32 0
  store ptr %t27, ptr %t28
  call void @__inc_ref(ptr %t6)
  %t29 = getelementptr ptr, ptr %t26, i32 1
  store ptr %t6, ptr %t29
  %t30 = call ptr @__alloc(i64 16, i32 1)
  %t31 = inttoptr i64 2711245919 to ptr
  %t32 = getelementptr ptr, ptr %t30, i32 0
  store ptr %t31, ptr %t32
  %t33 = call ptr @__alloc(i64 4, i32 0)
  store i32 1, ptr %t33
  %t34 = getelementptr ptr, ptr %t30, i32 1
  store ptr %t33, ptr %t34
  %t35 = getelementptr ptr, ptr %t26, i32 2
  store ptr %t30, ptr %t35
  %t36 = call ptr @__alloc(i64 8, i32 0)
  %t37 = inttoptr i64 22 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t26, i32 3
  store ptr %t36, ptr %t39
  call void @__inc_ref(ptr %t25)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t25)
  store ptr %t25, ptr %t3
  store ptr %t26, ptr %t4
  br label %tco.loop.0
tco.case.default.19:
  unreachable
tco.case.default.12:
  unreachable
tco.exit.1:
  %t40 = load ptr, ptr %t2
  ret ptr %t40
}

define internal ptr @v_sumTree(ptr %v_t) {
  call void @__inc_ref(ptr %v_t)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 24 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps_sumTree(ptr %v_t, ptr %t0)
  call void @__free_recursive(ptr %v_t)
  ret ptr %t3
}

define internal ptr @v_main() {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 7 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 4, i32 0)
  store i32 200000, ptr %t3
  %t4 = call ptr @__alloc(i64 8, i32 0)
  %t5 = inttoptr i64 22 to ptr
  %t6 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5, ptr %t6
  %t7 = call ptr @v_buildLeft(ptr %t3, ptr %t4)
  %t8 = call ptr @v_sumTree(ptr %t7)
  %t9 = call ptr @__showInt32(ptr %t8)
  %t10 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t9, ptr %t10
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
  %t18 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t11, ptr %t18
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
  switch i64 %t7, label %tco.case.default.8 [ i64 27, label %tco.case.arm.27.9 i64 28, label %tco.case.arm.28.143 ]
tco.case.arm.27.9:
  %t10 = getelementptr ptr, ptr %t4, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  %t12 = getelementptr ptr, ptr %t4, i32 2
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t11, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %tco.case.default.17 [ i64 24, label %tco.case.arm.24.18 i64 26, label %tco.case.arm.26.19 i64 25, label %tco.case.arm.25.110 ]
tco.case.arm.24.18:
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %t4)
  store ptr %t13, ptr %t2
  br label %tco.exit.1
tco.case.arm.26.19:
  %t20 = getelementptr ptr, ptr %t11, i32 1
  %t21 = load ptr, ptr %t20
  call void @__inc_ref(ptr %t21)
  %t22 = getelementptr ptr, ptr %t11, i32 2
  %t23 = load ptr, ptr %t22
  call void @__inc_ref(ptr %t23)
  %t24 = getelementptr ptr, ptr %t11, i32 3
  %t25 = load ptr, ptr %t24
  call void @__inc_ref(ptr %t25)
  call void @__inc_ref(ptr %t23)
  call void @__inc_ref(ptr %t13)
  %t26 = call ptr @__addInt32(ptr %t23, ptr %t13)
  %t27 = getelementptr ptr, ptr %t26, i32 0
  %t28 = load ptr, ptr %t27
  %t29 = ptrtoint ptr %t28 to i64
  switch i64 %t29, label %tco.case.default.30 [ i64 3, label %tco.case.arm.3.31 i64 4, label %tco.case.arm.4.55 ]
tco.case.arm.3.31:
  %t32 = getelementptr ptr, ptr %t26, i32 1
  %t33 = load ptr, ptr %t32
  call void @__inc_ref(ptr %t33)
  %t34 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t34
  %t35 = getelementptr i8, ptr %t4, i64 -8
  %t36 = load i32, ptr %t35
  %t37 = icmp eq i32 %t36, 1
  br i1 %t37, label %reuse.in_place.38, label %reuse.copy.39
reuse.in_place.38:
  %t41 = getelementptr ptr, ptr %t4, i32 1
  %t42 = load ptr, ptr %t41
  call void @__free_recursive(ptr %t42)
  %t43 = getelementptr ptr, ptr %t4, i32 2
  %t44 = load ptr, ptr %t43
  call void @__free_recursive(ptr %t44)
  %t47 = inttoptr i64 27 to ptr
  %t48 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t47, ptr %t48
  call void @__inc_ref(ptr %t21)
  %t45 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t21, ptr %t45
  %t46 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t34, ptr %t46
  br label %reuse.join.40
reuse.copy.39:
  %t49 = call ptr @__alloc(i64 24, i32 2)
  %t50 = inttoptr i64 27 to ptr
  %t51 = getelementptr ptr, ptr %t49, i32 0
  store ptr %t50, ptr %t51
  call void @__inc_ref(ptr %t21)
  %t52 = getelementptr ptr, ptr %t49, i32 1
  store ptr %t21, ptr %t52
  %t53 = getelementptr ptr, ptr %t49, i32 2
  store ptr %t34, ptr %t53
  call void @__free_recursive(ptr %t4)
  br label %reuse.join.40
reuse.join.40:
  %t54 = phi ptr [ %t4, %reuse.in_place.38 ], [ %t49, %reuse.copy.39 ]
  call void @__free_recursive(ptr %t26)
  call void @__free_recursive(ptr %t33)
  call void @__free_recursive(ptr %t25)
  call void @__free_recursive(ptr %t23)
  call void @__free_recursive(ptr %t21)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t54, ptr %t3
  br label %tco.loop.0
tco.case.arm.4.55:
  %t56 = getelementptr ptr, ptr %t26, i32 1
  %t57 = load ptr, ptr %t56
  call void @__inc_ref(ptr %t57)
  call void @__inc_ref(ptr %t57)
  call void @__inc_ref(ptr %t25)
  %t58 = call ptr @__addInt32(ptr %t57, ptr %t25)
  %t59 = getelementptr ptr, ptr %t58, i32 0
  %t60 = load ptr, ptr %t59
  %t61 = ptrtoint ptr %t60 to i64
  switch i64 %t61, label %tco.case.default.62 [ i64 3, label %tco.case.arm.3.63 i64 4, label %tco.case.arm.4.87 ]
tco.case.arm.3.63:
  %t64 = getelementptr ptr, ptr %t58, i32 1
  %t65 = load ptr, ptr %t64
  call void @__inc_ref(ptr %t65)
  %t66 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t66
  %t67 = getelementptr i8, ptr %t4, i64 -8
  %t68 = load i32, ptr %t67
  %t69 = icmp eq i32 %t68, 1
  br i1 %t69, label %reuse.in_place.70, label %reuse.copy.71
reuse.in_place.70:
  %t73 = getelementptr ptr, ptr %t4, i32 1
  %t74 = load ptr, ptr %t73
  call void @__free_recursive(ptr %t74)
  %t75 = getelementptr ptr, ptr %t4, i32 2
  %t76 = load ptr, ptr %t75
  call void @__free_recursive(ptr %t76)
  %t79 = inttoptr i64 27 to ptr
  %t80 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t79, ptr %t80
  call void @__inc_ref(ptr %t21)
  %t77 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t21, ptr %t77
  %t78 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t66, ptr %t78
  br label %reuse.join.72
reuse.copy.71:
  %t81 = call ptr @__alloc(i64 24, i32 2)
  %t82 = inttoptr i64 27 to ptr
  %t83 = getelementptr ptr, ptr %t81, i32 0
  store ptr %t82, ptr %t83
  call void @__inc_ref(ptr %t21)
  %t84 = getelementptr ptr, ptr %t81, i32 1
  store ptr %t21, ptr %t84
  %t85 = getelementptr ptr, ptr %t81, i32 2
  store ptr %t66, ptr %t85
  call void @__free_recursive(ptr %t4)
  br label %reuse.join.72
reuse.join.72:
  %t86 = phi ptr [ %t4, %reuse.in_place.70 ], [ %t81, %reuse.copy.71 ]
  call void @__free_recursive(ptr %t58)
  call void @__free_recursive(ptr %t26)
  call void @__free_recursive(ptr %t65)
  call void @__free_recursive(ptr %t57)
  call void @__free_recursive(ptr %t25)
  call void @__free_recursive(ptr %t23)
  call void @__free_recursive(ptr %t21)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t86, ptr %t3
  br label %tco.loop.0
tco.case.arm.4.87:
  %t88 = getelementptr ptr, ptr %t58, i32 1
  %t89 = load ptr, ptr %t88
  call void @__inc_ref(ptr %t89)
  %t90 = getelementptr i8, ptr %t4, i64 -8
  %t91 = load i32, ptr %t90
  %t92 = icmp eq i32 %t91, 1
  br i1 %t92, label %reuse.in_place.93, label %reuse.copy.94
reuse.in_place.93:
  %t96 = getelementptr ptr, ptr %t4, i32 1
  %t97 = load ptr, ptr %t96
  call void @__free_recursive(ptr %t97)
  %t98 = getelementptr ptr, ptr %t4, i32 2
  %t99 = load ptr, ptr %t98
  call void @__free_recursive(ptr %t99)
  %t102 = inttoptr i64 27 to ptr
  %t103 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t102, ptr %t103
  call void @__inc_ref(ptr %t21)
  %t100 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t21, ptr %t100
  call void @__inc_ref(ptr %t89)
  %t101 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t89, ptr %t101
  br label %reuse.join.95
reuse.copy.94:
  %t104 = call ptr @__alloc(i64 24, i32 2)
  %t105 = inttoptr i64 27 to ptr
  %t106 = getelementptr ptr, ptr %t104, i32 0
  store ptr %t105, ptr %t106
  call void @__inc_ref(ptr %t21)
  %t107 = getelementptr ptr, ptr %t104, i32 1
  store ptr %t21, ptr %t107
  call void @__inc_ref(ptr %t89)
  %t108 = getelementptr ptr, ptr %t104, i32 2
  store ptr %t89, ptr %t108
  call void @__free_recursive(ptr %t4)
  br label %reuse.join.95
reuse.join.95:
  %t109 = phi ptr [ %t4, %reuse.in_place.93 ], [ %t104, %reuse.copy.94 ]
  call void @__free_recursive(ptr %t58)
  call void @__free_recursive(ptr %t26)
  call void @__free_recursive(ptr %t89)
  call void @__free_recursive(ptr %t57)
  call void @__free_recursive(ptr %t25)
  call void @__free_recursive(ptr %t23)
  call void @__free_recursive(ptr %t21)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t109, ptr %t3
  br label %tco.loop.0
tco.case.default.62:
  unreachable
tco.case.default.30:
  unreachable
tco.case.arm.25.110:
  %t111 = getelementptr ptr, ptr %t11, i32 1
  %t112 = load ptr, ptr %t111
  call void @__inc_ref(ptr %t112)
  %t113 = getelementptr ptr, ptr %t11, i32 2
  %t114 = load ptr, ptr %t113
  call void @__inc_ref(ptr %t114)
  %t115 = getelementptr ptr, ptr %t11, i32 3
  %t116 = load ptr, ptr %t115
  call void @__inc_ref(ptr %t116)
  %t117 = call ptr @__alloc(i64 32, i32 3)
  %t118 = inttoptr i64 26 to ptr
  %t119 = getelementptr ptr, ptr %t117, i32 0
  store ptr %t118, ptr %t119
  call void @__inc_ref(ptr %t112)
  %t120 = getelementptr ptr, ptr %t117, i32 1
  store ptr %t112, ptr %t120
  call void @__inc_ref(ptr %t13)
  %t121 = getelementptr ptr, ptr %t117, i32 2
  store ptr %t13, ptr %t121
  call void @__inc_ref(ptr %t114)
  %t122 = getelementptr ptr, ptr %t117, i32 3
  store ptr %t114, ptr %t122
  %t123 = getelementptr i8, ptr %t4, i64 -8
  %t124 = load i32, ptr %t123
  %t125 = icmp eq i32 %t124, 1
  br i1 %t125, label %reuse.in_place.126, label %reuse.copy.127
reuse.in_place.126:
  %t129 = getelementptr ptr, ptr %t4, i32 1
  %t130 = load ptr, ptr %t129
  call void @__free_recursive(ptr %t130)
  %t131 = getelementptr ptr, ptr %t4, i32 2
  %t132 = load ptr, ptr %t131
  call void @__free_recursive(ptr %t132)
  %t135 = inttoptr i64 28 to ptr
  %t136 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t135, ptr %t136
  call void @__inc_ref(ptr %t116)
  %t133 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t116, ptr %t133
  %t134 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t117, ptr %t134
  br label %reuse.join.128
reuse.copy.127:
  %t137 = call ptr @__alloc(i64 24, i32 2)
  %t138 = inttoptr i64 28 to ptr
  %t139 = getelementptr ptr, ptr %t137, i32 0
  store ptr %t138, ptr %t139
  call void @__inc_ref(ptr %t116)
  %t140 = getelementptr ptr, ptr %t137, i32 1
  store ptr %t116, ptr %t140
  %t141 = getelementptr ptr, ptr %t137, i32 2
  store ptr %t117, ptr %t141
  call void @__free_recursive(ptr %t4)
  br label %reuse.join.128
reuse.join.128:
  %t142 = phi ptr [ %t4, %reuse.in_place.126 ], [ %t137, %reuse.copy.127 ]
  call void @__free_recursive(ptr %t116)
  call void @__free_recursive(ptr %t114)
  call void @__free_recursive(ptr %t112)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t142, ptr %t3
  br label %tco.loop.0
tco.case.default.17:
  unreachable
tco.case.arm.28.143:
  %t144 = getelementptr ptr, ptr %t4, i32 1
  %t145 = load ptr, ptr %t144
  call void @__inc_ref(ptr %t145)
  %t146 = getelementptr ptr, ptr %t4, i32 2
  %t147 = load ptr, ptr %t146
  call void @__inc_ref(ptr %t147)
  %t148 = getelementptr ptr, ptr %t145, i32 0
  %t149 = load ptr, ptr %t148
  %t150 = ptrtoint ptr %t149 to i64
  switch i64 %t150, label %tco.case.default.151 [ i64 22, label %tco.case.arm.22.152 i64 23, label %tco.case.arm.23.174 ]
tco.case.arm.22.152:
  %t153 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t153
  %t154 = getelementptr i8, ptr %t4, i64 -8
  %t155 = load i32, ptr %t154
  %t156 = icmp eq i32 %t155, 1
  br i1 %t156, label %reuse.in_place.157, label %reuse.copy.158
reuse.in_place.157:
  %t160 = getelementptr ptr, ptr %t4, i32 1
  %t161 = load ptr, ptr %t160
  call void @__free_recursive(ptr %t161)
  %t162 = getelementptr ptr, ptr %t4, i32 2
  %t163 = load ptr, ptr %t162
  call void @__free_recursive(ptr %t163)
  %t166 = inttoptr i64 27 to ptr
  %t167 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t166, ptr %t167
  call void @__inc_ref(ptr %t147)
  %t164 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t147, ptr %t164
  %t165 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t153, ptr %t165
  br label %reuse.join.159
reuse.copy.158:
  %t168 = call ptr @__alloc(i64 24, i32 2)
  %t169 = inttoptr i64 27 to ptr
  %t170 = getelementptr ptr, ptr %t168, i32 0
  store ptr %t169, ptr %t170
  call void @__inc_ref(ptr %t147)
  %t171 = getelementptr ptr, ptr %t168, i32 1
  store ptr %t147, ptr %t171
  %t172 = getelementptr ptr, ptr %t168, i32 2
  store ptr %t153, ptr %t172
  call void @__free_recursive(ptr %t4)
  br label %reuse.join.159
reuse.join.159:
  %t173 = phi ptr [ %t4, %reuse.in_place.157 ], [ %t168, %reuse.copy.158 ]
  call void @__free_recursive(ptr %t147)
  call void @__free_recursive(ptr %t145)
  store ptr %t173, ptr %t3
  br label %tco.loop.0
tco.case.arm.23.174:
  %t175 = getelementptr ptr, ptr %t145, i32 1
  %t176 = load ptr, ptr %t175
  call void @__inc_ref(ptr %t176)
  %t177 = getelementptr ptr, ptr %t145, i32 2
  %t178 = load ptr, ptr %t177
  call void @__inc_ref(ptr %t178)
  %t179 = getelementptr ptr, ptr %t145, i32 3
  %t180 = load ptr, ptr %t179
  call void @__inc_ref(ptr %t180)
  %t181 = getelementptr ptr, ptr %t178, i32 0
  %t182 = load ptr, ptr %t181
  %t183 = ptrtoint ptr %t182 to i64
  switch i64 %t183, label %tco.case.default.184 [ i64 2711245919, label %tco.case.arm.2711245919.185 ]
tco.case.arm.2711245919.185:
  %t186 = getelementptr ptr, ptr %t178, i32 1
  %t187 = load ptr, ptr %t186
  call void @__inc_ref(ptr %t187)
  %t188 = call ptr @__alloc(i64 32, i32 3)
  %t189 = inttoptr i64 25 to ptr
  %t190 = getelementptr ptr, ptr %t188, i32 0
  store ptr %t189, ptr %t190
  call void @__inc_ref(ptr %t147)
  %t191 = getelementptr ptr, ptr %t188, i32 1
  store ptr %t147, ptr %t191
  call void @__inc_ref(ptr %t187)
  %t192 = getelementptr ptr, ptr %t188, i32 2
  store ptr %t187, ptr %t192
  call void @__inc_ref(ptr %t180)
  %t193 = getelementptr ptr, ptr %t188, i32 3
  store ptr %t180, ptr %t193
  %t194 = getelementptr i8, ptr %t4, i64 -8
  %t195 = load i32, ptr %t194
  %t196 = icmp eq i32 %t195, 1
  br i1 %t196, label %reuse.in_place.197, label %reuse.copy.198
reuse.in_place.197:
  %t200 = getelementptr ptr, ptr %t4, i32 1
  %t201 = load ptr, ptr %t200
  call void @__free_recursive(ptr %t201)
  %t202 = getelementptr ptr, ptr %t4, i32 2
  %t203 = load ptr, ptr %t202
  call void @__free_recursive(ptr %t203)
  %t206 = inttoptr i64 28 to ptr
  %t207 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t206, ptr %t207
  call void @__inc_ref(ptr %t176)
  %t204 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t176, ptr %t204
  %t205 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t188, ptr %t205
  br label %reuse.join.199
reuse.copy.198:
  %t208 = call ptr @__alloc(i64 24, i32 2)
  %t209 = inttoptr i64 28 to ptr
  %t210 = getelementptr ptr, ptr %t208, i32 0
  store ptr %t209, ptr %t210
  call void @__inc_ref(ptr %t176)
  %t211 = getelementptr ptr, ptr %t208, i32 1
  store ptr %t176, ptr %t211
  %t212 = getelementptr ptr, ptr %t208, i32 2
  store ptr %t188, ptr %t212
  call void @__free_recursive(ptr %t4)
  br label %reuse.join.199
reuse.join.199:
  %t213 = phi ptr [ %t4, %reuse.in_place.197 ], [ %t208, %reuse.copy.198 ]
  call void @__free_recursive(ptr %t187)
  call void @__free_recursive(ptr %t180)
  call void @__free_recursive(ptr %t178)
  call void @__free_recursive(ptr %t176)
  call void @__free_recursive(ptr %t147)
  call void @__free_recursive(ptr %t145)
  store ptr %t213, ptr %t3
  br label %tco.loop.0
tco.case.default.184:
  unreachable
tco.case.default.151:
  unreachable
tco.case.default.8:
  unreachable
tco.exit.1:
  %t214 = load ptr, ptr %t2
  ret ptr %t214
}

define internal ptr @v__cps_sumTree(ptr %v_t, ptr %v__k) {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 28 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  call void @__inc_ref(ptr %v_t)
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v_t, ptr %t3
  call void @__inc_ref(ptr %v__k)
  %t4 = getelementptr ptr, ptr %t0, i32 2
  store ptr %v__k, ptr %t4
  %t5 = call ptr @v__scc__apply_sumTree__cps_sumTree(ptr %t0)
  call void @__free_recursive(ptr %v_t)
  call void @__free_recursive(ptr %v__k)
  ret ptr %t5
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
