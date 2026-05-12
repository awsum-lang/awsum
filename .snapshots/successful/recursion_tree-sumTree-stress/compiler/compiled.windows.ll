; External C declarations
declare ptr @malloc(i64)
declare void @free(ptr)
declare ptr @memcpy(ptr, ptr, i64)
declare i64 @strlen(ptr)
declare i64 @write(i32, ptr, i64)
declare i32 @printf(ptr, ...)
declare i32 @snprintf(ptr, i64, ptr, ...)
declare {i32, i1} @llvm.sadd.with.overflow.i32(i32, i32)

@.fmt_i32 = private unnamed_addr constant [3 x i8] c"%d\00"
@.fmt_u8 = private unnamed_addr constant [3 x i8] c"%u\00"
@.empty = private unnamed_addr constant {i32, i32, i32, i32, i32} { i32 0, i32 0, i32 0, i32 0, i32 0 }
@.cli_arg = internal global ptr null

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

define internal void @__free(ptr %p) {
  %hdr_ptr = getelementptr i8, ptr %p, i64 -12
  %flag = load i32, ptr %hdr_ptr
  %is_heap = icmp eq i32 %flag, 1
  br i1 %is_heap, label %do_free, label %skip
do_free:
  call void @free(ptr %hdr_ptr)
  br label %skip
skip:
  ret void
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

define internal void @__free_recursive(ptr %p_arg) {
entry:
  br label %top
top:
  %p = phi ptr [ %p_arg, %entry ], [ %p_next, %tail_jump ]
  %hdr_ptr = getelementptr i8, ptr %p, i64 -12
  %flag = load i32, ptr %hdr_ptr
  %is_heap = icmp eq i32 %flag, 1
  br i1 %is_heap, label %do_dec, label %skip_dec
do_dec:
  %rc_p = getelementptr i8, ptr %p, i64 -8
  %rc_old = load i32, ptr %rc_p
  %rc_new = sub i32 %rc_old, 1
  store i32 %rc_new, ptr %rc_p
  %is_zero = icmp eq i32 %rc_new, 0
  br i1 %is_zero, label %do_cascade, label %skip_dec
do_cascade:
  %shape_p = getelementptr i8, ptr %p, i64 -4
  %shape = load i32, ptr %shape_p
  %shape_zero = icmp eq i32 %shape, 0
  br i1 %shape_zero, label %loop_done, label %loop_check
loop_check:
  %i = phi i32 [ 1, %do_cascade ], [ %i_next, %loop_body ]
  %cmp = icmp ult i32 %i, %shape
  br i1 %cmp, label %loop_body, label %tail_jump_prep
loop_body:
  %i64 = zext i32 %i to i64
  %slot_p = getelementptr ptr, ptr %p, i64 %i64
  %child = load ptr, ptr %slot_p
  call void @__free_recursive(ptr %child)
  %i_next = add i32 %i, 1
  br label %loop_check
tail_jump_prep:
  %shape64 = zext i32 %shape to i64
  %last_slot_p = getelementptr ptr, ptr %p, i64 %shape64
  %p_next = load ptr, ptr %last_slot_p
  call void @free(ptr %hdr_ptr)
  br label %tail_jump
tail_jump:
  br label %top
loop_done:
  call void @free(ptr %hdr_ptr)
  br label %skip_dec
skip_dec:
  ret void
}

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [9 x i8]} { i32 0, i32 0, i32 0, i32 9, i32 9, [9 x i8] c"UNDERFLOW" }

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
  %oe_tag = inttoptr i64 13 to ptr
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
  %inner_tag_idx = select i1 %is_pos, i64 14, i64 13
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
  switch i64 %t11, label %tco.case.default.12 [ i64 1, label %tco.case.arm.1.13 i64 2, label %tco.case.arm.2.18 ]
tco.case.arm.1.13:
  %t14 = call ptr @__alloc(i64 16, i32 1)
  %t15 = inttoptr i64 4 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  call void @__inc_ref(ptr %t6)
  %t17 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t6, ptr %t17
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t14, ptr %t2
  br label %tco.exit.1
tco.case.arm.2.18:
  call void @__inc_ref(ptr %t5)
  %t19 = call ptr @__predInt32(ptr %t5)
  %t20 = getelementptr ptr, ptr %t19, i32 0
  %t21 = load ptr, ptr %t20
  %t22 = ptrtoint ptr %t21 to i64
  switch i64 %t22, label %tco.case.default.23 [ i64 3, label %tco.case.arm.3.24 i64 4, label %tco.case.arm.4.31 ]
tco.case.arm.3.24:
  %t25 = getelementptr ptr, ptr %t19, i32 1
  %t26 = load ptr, ptr %t25
  call void @__inc_ref(ptr %t26)
  %t27 = call ptr @__alloc(i64 16, i32 1)
  %t28 = inttoptr i64 3 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  call void @__inc_ref(ptr %t26)
  %t30 = getelementptr ptr, ptr %t27, i32 1
  store ptr %t26, ptr %t30
  call void @__free_recursive(ptr %t19)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t26)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t27, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.31:
  %t32 = getelementptr ptr, ptr %t19, i32 1
  %t33 = load ptr, ptr %t32
  call void @__inc_ref(ptr %t33)
  %t34 = call ptr @__alloc(i64 32, i32 3)
  %t35 = inttoptr i64 20 to ptr
  %t36 = getelementptr ptr, ptr %t34, i32 0
  store ptr %t35, ptr %t36
  call void @__inc_ref(ptr %t6)
  %t37 = getelementptr ptr, ptr %t34, i32 1
  store ptr %t6, ptr %t37
  %t38 = call ptr @__alloc(i64 4, i32 0)
  store i32 1, ptr %t38
  %t39 = getelementptr ptr, ptr %t34, i32 2
  store ptr %t38, ptr %t39
  %t40 = call ptr @__alloc(i64 8, i32 0)
  %t41 = inttoptr i64 19 to ptr
  %t42 = getelementptr ptr, ptr %t40, i32 0
  store ptr %t41, ptr %t42
  %t43 = getelementptr ptr, ptr %t34, i32 3
  store ptr %t40, ptr %t43
  call void @__inc_ref(ptr %t33)
  call void @__free_recursive(ptr %t19)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t33)
  store ptr %t33, ptr %t3
  store ptr %t34, ptr %t4
  br label %tco.loop.0
tco.case.default.23:
  unreachable
tco.case.default.12:
  unreachable
tco.exit.1:
  %t44 = load ptr, ptr %t2
  ret ptr %t44
}

define internal ptr @v_addOr0(ptr %v_a, ptr %v_b) {
  call void @__inc_ref(ptr %v_a)
  call void @__inc_ref(ptr %v_b)
  %t0 = call ptr @__addInt32(ptr %v_a, ptr %v_b)
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 3, label %case.arm.3.5 i64 4, label %case.arm.4.9 ]
case.arm.3.5:
  %t6 = getelementptr ptr, ptr %t0, i32 1
  %t7 = load ptr, ptr %t6
  call void @__inc_ref(ptr %t7)
  %t8 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t8
  call void @__free_recursive(ptr %t0)
  call void @__free_recursive(ptr %t7)
  call void @__free_recursive(ptr %v_a)
  call void @__free_recursive(ptr %v_b)
  ret ptr %t8
case.arm.4.9:
  %t10 = getelementptr ptr, ptr %t0, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  call void @__free_recursive(ptr %t0)
  call void @__free_recursive(ptr %v_a)
  call void @__free_recursive(ptr %v_b)
  ret ptr %t11
case.default.4:
  unreachable
}

define internal ptr @v_sumTree(ptr %v_t, ptr %v_acc) {
  call void @__inc_ref(ptr %v_t)
  call void @__inc_ref(ptr %v_acc)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 21 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps_sumTree(ptr %v_t, ptr %v_acc, ptr %t0)
  call void @__free_recursive(ptr %v_t)
  call void @__free_recursive(ptr %v_acc)
  ret ptr %t3
}

define internal ptr @v_main() {
  %t0 = call ptr @__alloc(i64 4, i32 0)
  store i32 100000, ptr %t0
  %t1 = call ptr @__alloc(i64 8, i32 0)
  %t2 = inttoptr i64 19 to ptr
  %t3 = getelementptr ptr, ptr %t1, i32 0
  store ptr %t2, ptr %t3
  %t4 = call ptr @v_buildLeft(ptr %t0, ptr %t1)
  %t5 = getelementptr ptr, ptr %t4, i32 0
  %t6 = load ptr, ptr %t5
  %t7 = ptrtoint ptr %t6 to i64
  switch i64 %t7, label %case.default.8 [ i64 3, label %case.arm.3.10 i64 4, label %case.arm.4.26 ]
case.arm.3.10:
  %t12 = getelementptr ptr, ptr %t4, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @__alloc(i64 24, i32 2)
  %t15 = inttoptr i64 7 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  %t17 = getelementptr ptr, ptr %t14, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t17
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
  br label %case.end.3.11
case.end.3.11:
  br label %case.join.9
case.arm.4.26:
  %t28 = getelementptr ptr, ptr %t4, i32 1
  %t29 = load ptr, ptr %t28
  call void @__inc_ref(ptr %t29)
  %t30 = call ptr @__alloc(i64 24, i32 2)
  %t31 = inttoptr i64 7 to ptr
  %t32 = getelementptr ptr, ptr %t30, i32 0
  store ptr %t31, ptr %t32
  call void @__inc_ref(ptr %t29)
  %t33 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t33
  %t34 = call ptr @v_sumTree(ptr %t29, ptr %t33)
  %t35 = call ptr @__showInt32(ptr %t34)
  %t36 = getelementptr ptr, ptr %t30, i32 1
  store ptr %t35, ptr %t36
  %t37 = call ptr @__alloc(i64 16, i32 1)
  %t38 = inttoptr i64 5 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = call ptr @__alloc(i64 8, i32 0)
  %t41 = inttoptr i64 0 to ptr
  %t42 = getelementptr ptr, ptr %t40, i32 0
  store ptr %t41, ptr %t42
  %t43 = getelementptr ptr, ptr %t37, i32 1
  store ptr %t40, ptr %t43
  %t44 = getelementptr ptr, ptr %t30, i32 2
  store ptr %t37, ptr %t44
  br label %case.end.4.27
case.end.4.27:
  br label %case.join.9
case.default.8:
  unreachable
case.join.9:
  %t45 = phi ptr [%t14, %case.end.3.11], [%t30, %case.end.4.27]
  call void @__free_recursive(ptr %t4)
  ret ptr %t45
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
  switch i64 %t7, label %tco.case.default.8 [ i64 23, label %tco.case.arm.23.9 i64 24, label %tco.case.arm.24.30 ]
tco.case.arm.23.9:
  %t10 = getelementptr ptr, ptr %t4, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  %t12 = getelementptr ptr, ptr %t4, i32 2
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t11, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %tco.case.default.17 [ i64 21, label %tco.case.arm.21.18 i64 22, label %tco.case.arm.22.19 ]
tco.case.arm.21.18:
  call void @__free_recursive(ptr %t11)
  call void @__free_recursive(ptr %t4)
  store ptr %t13, ptr %t2
  br label %tco.exit.1
tco.case.arm.22.19:
  %t20 = getelementptr ptr, ptr %t11, i32 1
  %t21 = load ptr, ptr %t20
  call void @__inc_ref(ptr %t21)
  %t22 = getelementptr ptr, ptr %t11, i32 2
  %t23 = load ptr, ptr %t22
  call void @__inc_ref(ptr %t23)
  %t24 = call ptr @__alloc(i64 32, i32 3)
  %t25 = inttoptr i64 24 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  call void @__inc_ref(ptr %t23)
  %t27 = getelementptr ptr, ptr %t24, i32 1
  store ptr %t23, ptr %t27
  call void @__inc_ref(ptr %t13)
  %t28 = getelementptr ptr, ptr %t24, i32 2
  store ptr %t13, ptr %t28
  call void @__inc_ref(ptr %t21)
  %t29 = getelementptr ptr, ptr %t24, i32 3
  store ptr %t21, ptr %t29
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t23)
  call void @__free_recursive(ptr %t21)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t11)
  store ptr %t24, ptr %t3
  br label %tco.loop.0
tco.case.default.17:
  unreachable
tco.case.arm.24.30:
  %t31 = getelementptr ptr, ptr %t4, i32 1
  %t32 = load ptr, ptr %t31
  call void @__inc_ref(ptr %t32)
  %t33 = getelementptr ptr, ptr %t4, i32 2
  %t34 = load ptr, ptr %t33
  call void @__inc_ref(ptr %t34)
  %t35 = getelementptr ptr, ptr %t4, i32 3
  %t36 = load ptr, ptr %t35
  call void @__inc_ref(ptr %t36)
  %t37 = getelementptr ptr, ptr %t32, i32 0
  %t38 = load ptr, ptr %t37
  %t39 = ptrtoint ptr %t38 to i64
  switch i64 %t39, label %tco.case.default.40 [ i64 19, label %tco.case.arm.19.41 i64 20, label %tco.case.arm.20.47 ]
tco.case.arm.19.41:
  %t42 = call ptr @__alloc(i64 24, i32 2)
  %t43 = inttoptr i64 23 to ptr
  %t44 = getelementptr ptr, ptr %t42, i32 0
  store ptr %t43, ptr %t44
  call void @__inc_ref(ptr %t36)
  %t45 = getelementptr ptr, ptr %t42, i32 1
  store ptr %t36, ptr %t45
  call void @__inc_ref(ptr %t34)
  %t46 = getelementptr ptr, ptr %t42, i32 2
  store ptr %t34, ptr %t46
  call void @__free_recursive(ptr %t4)
  call void @__free_recursive(ptr %t36)
  call void @__free_recursive(ptr %t34)
  call void @__free_recursive(ptr %t32)
  store ptr %t42, ptr %t3
  br label %tco.loop.0
tco.case.arm.20.47:
  %t48 = getelementptr ptr, ptr %t32, i32 1
  %t49 = load ptr, ptr %t48
  call void @__inc_ref(ptr %t49)
  %t50 = getelementptr ptr, ptr %t32, i32 2
  %t51 = load ptr, ptr %t50
  call void @__inc_ref(ptr %t51)
  %t52 = getelementptr ptr, ptr %t32, i32 3
  %t53 = load ptr, ptr %t52
  call void @__inc_ref(ptr %t53)
  call void @__inc_ref(ptr %t34)
  call void @__inc_ref(ptr %t51)
  %t54 = call ptr @v_addOr0(ptr %t34, ptr %t51)
  %t55 = call ptr @__alloc(i64 24, i32 2)
  %t56 = inttoptr i64 22 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  call void @__inc_ref(ptr %t36)
  %t58 = getelementptr ptr, ptr %t55, i32 1
  store ptr %t36, ptr %t58
  call void @__inc_ref(ptr %t53)
  %t59 = getelementptr ptr, ptr %t55, i32 2
  store ptr %t53, ptr %t59
  %t60 = getelementptr i8, ptr %t4, i64 -8
  %t61 = load i32, ptr %t60
  %t62 = icmp eq i32 %t61, 1
  br i1 %t62, label %reuse.in_place.63, label %reuse.copy.64
reuse.in_place.63:
  %t66 = getelementptr ptr, ptr %t4, i32 1
  %t67 = load ptr, ptr %t66
  call void @__free_recursive(ptr %t67)
  %t68 = getelementptr ptr, ptr %t4, i32 2
  %t69 = load ptr, ptr %t68
  call void @__free_recursive(ptr %t69)
  %t70 = getelementptr ptr, ptr %t4, i32 3
  %t71 = load ptr, ptr %t70
  call void @__free_recursive(ptr %t71)
  %t75 = inttoptr i64 24 to ptr
  %t76 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t75, ptr %t76
  call void @__inc_ref(ptr %t49)
  %t72 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t49, ptr %t72
  %t73 = getelementptr ptr, ptr %t4, i32 2
  store ptr %t54, ptr %t73
  %t74 = getelementptr ptr, ptr %t4, i32 3
  store ptr %t55, ptr %t74
  br label %reuse.join.65
reuse.copy.64:
  %t77 = call ptr @__alloc(i64 32, i32 3)
  %t78 = inttoptr i64 24 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  call void @__inc_ref(ptr %t49)
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t49, ptr %t80
  %t81 = getelementptr ptr, ptr %t77, i32 2
  store ptr %t54, ptr %t81
  %t82 = getelementptr ptr, ptr %t77, i32 3
  store ptr %t55, ptr %t82
  call void @__free_recursive(ptr %t4)
  br label %reuse.join.65
reuse.join.65:
  %t83 = phi ptr [ %t4, %reuse.in_place.63 ], [ %t77, %reuse.copy.64 ]
  call void @__free_recursive(ptr %t53)
  call void @__free_recursive(ptr %t51)
  call void @__free_recursive(ptr %t49)
  call void @__free_recursive(ptr %t36)
  call void @__free_recursive(ptr %t34)
  call void @__free_recursive(ptr %t32)
  store ptr %t83, ptr %t3
  br label %tco.loop.0
tco.case.default.40:
  unreachable
tco.case.default.8:
  unreachable
tco.exit.1:
  %t84 = load ptr, ptr %t2
  ret ptr %t84
}

define internal ptr @v__cps_sumTree(ptr %v_t, ptr %v_acc, ptr %v__k) {
  %t0 = call ptr @__alloc(i64 32, i32 3)
  %t1 = inttoptr i64 24 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  call void @__inc_ref(ptr %v_t)
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v_t, ptr %t3
  call void @__inc_ref(ptr %v_acc)
  %t4 = getelementptr ptr, ptr %t0, i32 2
  store ptr %v_acc, ptr %t4
  call void @__inc_ref(ptr %v__k)
  %t5 = getelementptr ptr, ptr %t0, i32 3
  store ptr %v__k, ptr %t5
  %t6 = call ptr @v__scc__apply_sumTree__cps_sumTree(ptr %t0)
  call void @__free_recursive(ptr %v_t)
  call void @__free_recursive(ptr %v_acc)
  call void @__free_recursive(ptr %v__k)
  ret ptr %t6
}

declare ptr @GetCommandLineW()
declare ptr @CommandLineToArgvW(ptr, ptr)
declare i32 @WideCharToMultiByte(i32, i32, ptr, i32, ptr, i32, ptr, ptr)

define i32 @main(i32 %argc_posix, ptr %argv_posix) {
entry:
  %cmdline = call ptr @GetCommandLineW()
  %argc_slot = alloca i32
  %argv_w = call ptr @CommandLineToArgvW(ptr %cmdline, ptr %argc_slot)
  %argc_w = load i32, ptr %argc_slot
  %has_arg = icmp sgt i32 %argc_w, 1
  br i1 %has_arg, label %with_arg, label %no_arg
with_arg:
  %arg_w_slot = getelementptr ptr, ptr %argv_w, i64 1
  %arg_w = load ptr, ptr %arg_w_slot
  %needed = call i32 @WideCharToMultiByte(i32 65001, i32 0, ptr %arg_w, i32 -1, ptr null, i32 0, ptr null, ptr null)
  %need_ok = icmp sgt i32 %needed, 0
  br i1 %need_ok, label %do_convert, label %no_arg
do_convert:
  %needed64 = sext i32 %needed to i64
  %buf = call ptr @__alloc(i64 %needed64, i32 0)
  %written = call i32 @WideCharToMultiByte(i32 65001, i32 0, ptr %arg_w, i32 -1, ptr %buf, i32 %needed, ptr null, ptr null)
  br label %call_main
no_arg:
  br label %call_main
call_main:
  %input = phi ptr [%buf, %do_convert], [getelementptr inbounds (i8, ptr @.empty, i64 12), %no_arg]
  store ptr %input, ptr @.cli_arg
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
