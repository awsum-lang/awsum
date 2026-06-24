; External C declarations
declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare ptr @memcpy(ptr, ptr, i64)
declare i64 @write(i32, ptr, i64)
declare i32 @snprintf(ptr, i64, ptr, ...)
declare {i32, i1} @llvm.sadd.with.overflow.i32(i32, i32)
declare {i32, i1} @llvm.ssub.with.overflow.i32(i32, i32)

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


define internal ptr @__subInt32(ptr %pa, ptr %pb) {
  %a = load i32, ptr %pa
  %b = load i32, ptr %pb
  %res = call {i32, i1} @llvm.ssub.with.overflow.i32(i32 %a, i32 %b)
  %diff = extractvalue {i32, i1} %res, 0
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
  store i32 %diff, ptr %box
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

define internal ptr @v_g(ptr %v_n) {
entry:
  %t3 = alloca ptr
  store ptr %v_n, ptr %t3
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t4 = load ptr, ptr %t3
  call void @__inc_ref(ptr %t4)
  %t5 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t5
  %t6 = call ptr @__eqInt32(ptr %t4, ptr %t5)
  %t7 = getelementptr ptr, ptr %t6, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %tco.case.default.10 [ i64 1, label %tco.case.arm.1.11 i64 2, label %tco.case.arm.2.13 ]
tco.case.arm.1.11:
  call void @__free_recursive(ptr %t6)
  %t12 = call ptr @__alloc(i64 4, i32 0)
  store i32 7, ptr %t12
  call void @__free_recursive(ptr %t4)
  store ptr %t12, ptr %t2
  br label %tco.exit.1
tco.case.arm.2.13:
  call void @__free_recursive(ptr %t6)
  call void @__inc_ref(ptr %t4)
  %t14 = call ptr @__alloc(i64 4, i32 0)
  store i32 1, ptr %t14
  %t15 = call ptr @__subInt32(ptr %t4, ptr %t14)
  %t16 = getelementptr ptr, ptr %t15, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %tco.case.default.19 [ i64 3, label %tco.case.arm.3.20 i64 4, label %tco.case.arm.4.22 ]
tco.case.arm.3.20:
  call void @__free_recursive(ptr %t15)
  %t21 = call ptr @__alloc(i64 4, i32 0)
  store i32 7, ptr %t21
  call void @__free_recursive(ptr %t4)
  store ptr %t21, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.22:
  %t23 = getelementptr ptr, ptr %t15, i32 1
  %t24 = load ptr, ptr %t23
  call void @__inc_ref(ptr %t24)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t4)
  store ptr %t24, ptr %t3
  br label %tco.loop.0
tco.case.default.19:
  unreachable
tco.case.default.10:
  unreachable
tco.exit.1:
  %t25 = load ptr, ptr %t2
  ret ptr %t25
}

define internal ptr @v_mk2(ptr %v_n) {
entry:
  %t3 = alloca ptr
  store ptr %v_n, ptr %t3
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t4 = load ptr, ptr %t3
  call void @__inc_ref(ptr %t4)
  %t5 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t5
  %t6 = call ptr @__eqInt32(ptr %t4, ptr %t5)
  %t7 = getelementptr ptr, ptr %t6, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %tco.case.default.10 [ i64 1, label %tco.case.arm.1.11 i64 2, label %tco.case.arm.2.15 ]
tco.case.arm.1.11:
  call void @__free_recursive(ptr %t6)
  %t12 = call ptr @__alloc(i64 8, i32 0)
  %t13 = inttoptr i64 25 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  call void @__free_recursive(ptr %t4)
  store ptr %t12, ptr %t2
  br label %tco.exit.1
tco.case.arm.2.15:
  call void @__free_recursive(ptr %t6)
  call void @__inc_ref(ptr %t4)
  %t16 = call ptr @__alloc(i64 4, i32 0)
  store i32 1, ptr %t16
  %t17 = call ptr @__subInt32(ptr %t4, ptr %t16)
  %t18 = getelementptr ptr, ptr %t17, i32 0
  %t19 = load ptr, ptr %t18
  %t20 = ptrtoint ptr %t19 to i64
  switch i64 %t20, label %tco.case.default.21 [ i64 3, label %tco.case.arm.3.22 i64 4, label %tco.case.arm.4.26 ]
tco.case.arm.3.22:
  call void @__free_recursive(ptr %t17)
  %t23 = call ptr @__alloc(i64 8, i32 0)
  %t24 = inttoptr i64 24 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  call void @__free_recursive(ptr %t4)
  store ptr %t23, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.26:
  %t27 = getelementptr ptr, ptr %t17, i32 1
  %t28 = load ptr, ptr %t27
  call void @__inc_ref(ptr %t28)
  call void @__free_recursive(ptr %t17)
  call void @__free_recursive(ptr %t4)
  store ptr %t28, ptr %t3
  br label %tco.loop.0
tco.case.default.21:
  unreachable
tco.case.default.10:
  unreachable
tco.exit.1:
  %t29 = load ptr, ptr %t2
  ret ptr %t29
}

define internal ptr @v_run(ptr %v_b, ptr %v_x) {
  %v_$inl4$scrut.jslot = alloca ptr
  %t1 = getelementptr ptr, ptr %v_b, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 1, label %case.arm.1.5 i64 2, label %case.arm.2.12 ]
case.arm.1.5:
  call void @__inc_ref(ptr %v_x)
  %t6 = call ptr @v_g(ptr %v_x)
  %t7 = call ptr @__alloc(i64 24, i32 2)
  %t8 = inttoptr i64 15 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  call void @__inc_ref(ptr %t6)
  %t10 = getelementptr ptr, ptr %t7, i32 1
  store ptr %t6, ptr %t10
  call void @__inc_ref(ptr %t6)
  %t11 = getelementptr ptr, ptr %t7, i32 2
  store ptr %t6, ptr %t11
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_b)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t7
case.arm.2.12:
  call void @__inc_ref(ptr %v_x)
  %t13 = call ptr @v_mk2(ptr %v_x)
  store ptr %t13, ptr %v_$inl4$scrut.jslot
  br label %join.0
case.default.4:
  unreachable
join.0:
  %t14 = load ptr, ptr %v_$inl4$scrut.jslot
  %t15 = getelementptr ptr, ptr %t14, i32 0
  %t16 = load ptr, ptr %t15
  %t17 = ptrtoint ptr %t16 to i64
  switch i64 %t17, label %case.default.18 [ i64 24, label %case.arm.24.19 i64 25, label %case.arm.25.26 ]
case.arm.24.19:
  call void @__inc_ref(ptr %v_x)
  %t20 = call ptr @v_g(ptr %v_x)
  %t21 = call ptr @__alloc(i64 24, i32 2)
  %t22 = inttoptr i64 15 to ptr
  %t23 = getelementptr ptr, ptr %t21, i32 0
  store ptr %t22, ptr %t23
  call void @__inc_ref(ptr %t20)
  %t24 = getelementptr ptr, ptr %t21, i32 1
  store ptr %t20, ptr %t24
  call void @__inc_ref(ptr %t20)
  %t25 = getelementptr ptr, ptr %t21, i32 2
  store ptr %t20, ptr %t25
  call void @__free_recursive(ptr %t20)
  call void @__free_recursive(ptr %t14)
  call void @__free_recursive(ptr %v_b)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t21
case.arm.25.26:
  %t27 = call ptr @__alloc(i64 24, i32 2)
  %t28 = inttoptr i64 15 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  call void @__inc_ref(ptr %v_x)
  %t30 = getelementptr ptr, ptr %t27, i32 1
  store ptr %v_x, ptr %t30
  call void @__inc_ref(ptr %v_x)
  %t31 = getelementptr ptr, ptr %t27, i32 2
  store ptr %v_x, ptr %t31
  call void @__free_recursive(ptr %t14)
  call void @__free_recursive(ptr %v_b)
  call void @__free_recursive(ptr %v_x)
  ret ptr %t27
case.default.18:
  unreachable
}

define internal ptr @v_main() {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 7 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 8, i32 0)
  %t4 = inttoptr i64 1 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = call ptr @__alloc(i64 4, i32 0)
  store i32 3, ptr %t6
  %t7 = call ptr @v_run(ptr %t3, ptr %t6)
  %t8 = getelementptr ptr, ptr %t7, i32 1
  %t9 = load ptr, ptr %t8
  call void @__inc_ref(ptr %t9)
  %t10 = getelementptr ptr, ptr %t7, i32 2
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  %t12 = call ptr @__addInt32(ptr %t9, ptr %t11)
  %t13 = getelementptr ptr, ptr %t12, i32 0
  %t14 = load ptr, ptr %t13
  %t15 = ptrtoint ptr %t14 to i64
  switch i64 %t15, label %case.default.16 [ i64 3, label %case.arm.3.18 i64 4, label %case.arm.4.21 ]
case.arm.3.18:
  %t20 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t20
  br label %case.end.3.19
case.end.3.19:
  br label %case.join.17
case.arm.4.21:
  %t23 = getelementptr ptr, ptr %t12, i32 1
  %t24 = load ptr, ptr %t23
  call void @__inc_ref(ptr %t24)
  call void @__inc_ref(ptr %t24)
  br label %case.end.4.22
case.end.4.22:
  br label %case.join.17
case.default.16:
  unreachable
case.join.17:
  %t25 = phi ptr [ %t20, %case.end.3.19 ], [ %t24, %case.end.4.22 ]
  call void @__free_recursive(ptr %t12)
  call void @__free_recursive(ptr %t7)
  %t26 = call ptr @__showInt32(ptr %t25)
  %t27 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t26, ptr %t27
  %t28 = call ptr @__alloc(i64 16, i32 1)
  %t29 = inttoptr i64 5 to ptr
  %t30 = getelementptr ptr, ptr %t28, i32 0
  store ptr %t29, ptr %t30
  %t31 = call ptr @__alloc(i64 8, i32 0)
  %t32 = inttoptr i64 0 to ptr
  %t33 = getelementptr ptr, ptr %t31, i32 0
  store ptr %t32, ptr %t33
  %t34 = getelementptr ptr, ptr %t28, i32 1
  store ptr %t31, ptr %t34
  %t35 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t28, ptr %t35
  %t36 = call ptr @__alloc(i64 8, i32 0)
  %t37 = inttoptr i64 26 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = call ptr @v_$cps$$df$andThenIO$0(ptr %t0, ptr %t36)
  ret ptr %t39
}

define internal ptr @v_$cps$$df$andThenIO$0(ptr %v_io, ptr %v_$k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 7, label %tco.case.arm.7.49 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = call ptr @__alloc(i64 8, i32 0)
  %t16 = inttoptr i64 2 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = call ptr @__alloc(i64 4, i32 0)
  store i32 4, ptr %t18
  %t19 = call ptr @v_run(ptr %t15, ptr %t18)
  %t20 = getelementptr ptr, ptr %t19, i32 1
  %t21 = load ptr, ptr %t20
  call void @__inc_ref(ptr %t21)
  %t22 = getelementptr ptr, ptr %t19, i32 2
  %t23 = load ptr, ptr %t22
  call void @__inc_ref(ptr %t23)
  %t24 = call ptr @__addInt32(ptr %t21, ptr %t23)
  %t25 = getelementptr ptr, ptr %t24, i32 0
  %t26 = load ptr, ptr %t25
  %t27 = ptrtoint ptr %t26 to i64
  switch i64 %t27, label %case.default.28 [ i64 3, label %case.arm.3.30 i64 4, label %case.arm.4.33 ]
case.arm.3.30:
  %t32 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t32
  br label %case.end.3.31
case.end.3.31:
  br label %case.join.29
case.arm.4.33:
  %t35 = getelementptr ptr, ptr %t24, i32 1
  %t36 = load ptr, ptr %t35
  call void @__inc_ref(ptr %t36)
  call void @__inc_ref(ptr %t36)
  call void @__free_recursive(ptr %t36)
  br label %case.end.4.34
case.end.4.34:
  br label %case.join.29
case.default.28:
  unreachable
case.join.29:
  %t37 = phi ptr [ %t32, %case.end.3.31 ], [ %t36, %case.end.4.34 ]
  call void @__free_recursive(ptr %t24)
  call void @__free_recursive(ptr %t19)
  %t38 = call ptr @__showInt32(ptr %t37)
  %t39 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t38, ptr %t39
  %t40 = call ptr @__alloc(i64 16, i32 1)
  %t41 = inttoptr i64 5 to ptr
  %t42 = getelementptr ptr, ptr %t40, i32 0
  store ptr %t41, ptr %t42
  %t43 = call ptr @__alloc(i64 8, i32 0)
  %t44 = inttoptr i64 0 to ptr
  %t45 = getelementptr ptr, ptr %t43, i32 0
  store ptr %t44, ptr %t45
  %t46 = getelementptr ptr, ptr %t40, i32 1
  store ptr %t43, ptr %t46
  %t47 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t40, ptr %t47
  %t48 = call ptr @v_$apply$$df$andThenIO$0(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t48, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.49:
  %t50 = getelementptr ptr, ptr %t5, i32 1
  %t51 = load ptr, ptr %t50
  %t52 = getelementptr ptr, ptr %t5, i32 2
  %t53 = load ptr, ptr %t52
  call void @__inc_ref(ptr %t53)
  %t60 = getelementptr i8, ptr %t5, i64 -8
  %t61 = load i32, ptr %t60
  %t62 = icmp eq i32 %t61, 1
  br i1 %t62, label %reuse.in_place.63, label %reuse.copy.64
reuse.in_place.63:
  %t54 = getelementptr ptr, ptr %t5, i32 2
  %t55 = load ptr, ptr %t54
  call void @__free_recursive(ptr %t55)
  %t58 = inttoptr i64 27 to ptr
  %t59 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t58, ptr %t59
  call void @__inc_ref(ptr %t6)
  %t56 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t56
  %t57 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t51, ptr %t57
  br label %reuse.in_place.end.66
reuse.in_place.end.66:
  br label %reuse.join.65
reuse.copy.64:
  %t68 = call ptr @__alloc(i64 24, i32 2)
  %t69 = inttoptr i64 27 to ptr
  %t70 = getelementptr ptr, ptr %t68, i32 0
  store ptr %t69, ptr %t70
  call void @__inc_ref(ptr %t6)
  %t71 = getelementptr ptr, ptr %t68, i32 1
  store ptr %t6, ptr %t71
  call void @__inc_ref(ptr %t51)
  %t72 = getelementptr ptr, ptr %t68, i32 2
  store ptr %t51, ptr %t72
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.67
reuse.copy.end.67:
  br label %reuse.join.65
reuse.join.65:
  %t73 = phi ptr [ %t5, %reuse.in_place.end.66 ], [ %t68, %reuse.copy.end.67 ]
  call void @__free_recursive(ptr %t6)
  store ptr %t53, ptr %t3
  store ptr %t73, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t74 = load ptr, ptr %t2
  ret ptr %t74
}

define internal ptr @v_$apply$$df$andThenIO$0(ptr %v_$k, ptr %v_$x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 26, label %tco.case.arm.26.11 i64 27, label %tco.case.arm.27.12 ]
tco.case.arm.26.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.27.12:
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
