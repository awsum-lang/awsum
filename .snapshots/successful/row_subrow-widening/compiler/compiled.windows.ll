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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"hi" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"tt" }

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

define internal ptr @v_asc() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 1615808600 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t3
  ret ptr %t0
}

define internal ptr @v_main() {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 7 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_asc()
  %t4 = getelementptr ptr, ptr %t3, i32 0
  %t5 = load ptr, ptr %t4
  %t6 = ptrtoint ptr %t5 to i64
  switch i64 %t6, label %case.default.7 [ i64 1615808600, label %case.arm.1615808600.9 i64 2711245919, label %case.arm.2711245919.13 ]
case.arm.1615808600.9:
  %t11 = getelementptr ptr, ptr %t3, i32 1
  %t12 = load ptr, ptr %t11
  call void @__inc_ref(ptr %t12)
  br label %case.end.1615808600.10
case.end.1615808600.10:
  br label %case.join.8
case.arm.2711245919.13:
  %t15 = getelementptr ptr, ptr %t3, i32 1
  %t16 = load ptr, ptr %t15
  call void @__inc_ref(ptr %t16)
  %t17 = call ptr @__showInt32(ptr %t16)
  br label %case.end.2711245919.14
case.end.2711245919.14:
  br label %case.join.8
case.default.7:
  unreachable
case.join.8:
  %t18 = phi ptr [ %t12, %case.end.1615808600.10 ], [ %t17, %case.end.2711245919.14 ]
  call void @__free_recursive(ptr %t3)
  %t19 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t18, ptr %t19
  %t20 = call ptr @__alloc(i64 16, i32 1)
  %t21 = inttoptr i64 5 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = call ptr @__alloc(i64 8, i32 0)
  %t24 = inttoptr i64 0 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  %t26 = getelementptr ptr, ptr %t20, i32 1
  store ptr %t23, ptr %t26
  %t27 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t20, ptr %t27
  %t28 = call ptr @__alloc(i64 8, i32 0)
  %t29 = inttoptr i64 10 to ptr
  %t30 = getelementptr ptr, ptr %t28, i32 0
  store ptr %t29, ptr %t30
  %t31 = call ptr @v__cps__df_andThenIO_4(ptr %t0, ptr %t28)
  %t32 = call ptr @__alloc(i64 8, i32 0)
  %t33 = inttoptr i64 8 to ptr
  %t34 = getelementptr ptr, ptr %t32, i32 0
  store ptr %t33, ptr %t34
  %t35 = call ptr @v__cps__df_andThenIO_0(ptr %t31, ptr %t32)
  ret ptr %t35
}

define internal ptr @v__cps__df_andThenIO_0(ptr %v_io, ptr %v__k) {
entry:
  %t3 = alloca ptr
  store ptr %v_io, ptr %t3
  %t4 = alloca ptr
  store ptr %v__k, ptr %t4
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t5 = load ptr, ptr %t3
  %t6 = load ptr, ptr %t4
  %t7 = getelementptr ptr, ptr %t5, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 7, label %tco.case.arm.7.45 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = call ptr @__alloc(i64 16, i32 1)
  %t16 = inttoptr i64 2711245919 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = call ptr @__alloc(i64 4, i32 0)
  store i32 2, ptr %t18
  %t19 = getelementptr ptr, ptr %t15, i32 1
  store ptr %t18, ptr %t19
  %t20 = getelementptr ptr, ptr %t15, i32 0
  %t21 = load ptr, ptr %t20
  %t22 = ptrtoint ptr %t21 to i64
  switch i64 %t22, label %case.default.23 [ i64 1615808600, label %case.arm.1615808600.25 i64 2711245919, label %case.arm.2711245919.29 ]
case.arm.1615808600.25:
  %t27 = getelementptr ptr, ptr %t15, i32 1
  %t28 = load ptr, ptr %t27
  call void @__inc_ref(ptr %t28)
  br label %case.end.1615808600.26
case.end.1615808600.26:
  br label %case.join.24
case.arm.2711245919.29:
  %t31 = getelementptr ptr, ptr %t15, i32 1
  %t32 = load ptr, ptr %t31
  call void @__inc_ref(ptr %t32)
  %t33 = call ptr @__showInt32(ptr %t32)
  br label %case.end.2711245919.30
case.end.2711245919.30:
  br label %case.join.24
case.default.23:
  unreachable
case.join.24:
  %t34 = phi ptr [ %t28, %case.end.1615808600.26 ], [ %t33, %case.end.2711245919.30 ]
  call void @__free_recursive(ptr %t15)
  %t35 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t34, ptr %t35
  %t36 = call ptr @__alloc(i64 16, i32 1)
  %t37 = inttoptr i64 5 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = call ptr @__alloc(i64 8, i32 0)
  %t40 = inttoptr i64 0 to ptr
  %t41 = getelementptr ptr, ptr %t39, i32 0
  store ptr %t40, ptr %t41
  %t42 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t39, ptr %t42
  %t43 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t36, ptr %t43
  %t44 = call ptr @v__apply__df_andThenIO_0(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t44, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.45:
  %t46 = getelementptr ptr, ptr %t5, i32 1
  %t47 = load ptr, ptr %t46
  %t48 = getelementptr ptr, ptr %t5, i32 2
  %t49 = load ptr, ptr %t48
  call void @__inc_ref(ptr %t49)
  %t56 = getelementptr i8, ptr %t5, i64 -8
  %t57 = load i32, ptr %t56
  %t58 = icmp eq i32 %t57, 1
  br i1 %t58, label %reuse.in_place.59, label %reuse.copy.60
reuse.in_place.59:
  %t50 = getelementptr ptr, ptr %t5, i32 2
  %t51 = load ptr, ptr %t50
  call void @__free_recursive(ptr %t51)
  %t54 = inttoptr i64 9 to ptr
  %t55 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t54, ptr %t55
  call void @__inc_ref(ptr %t6)
  %t52 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t52
  %t53 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t47, ptr %t53
  br label %reuse.in_place.end.62
reuse.in_place.end.62:
  br label %reuse.join.61
reuse.copy.60:
  %t64 = call ptr @__alloc(i64 24, i32 2)
  %t65 = inttoptr i64 9 to ptr
  %t66 = getelementptr ptr, ptr %t64, i32 0
  store ptr %t65, ptr %t66
  call void @__inc_ref(ptr %t6)
  %t67 = getelementptr ptr, ptr %t64, i32 1
  store ptr %t6, ptr %t67
  call void @__inc_ref(ptr %t47)
  %t68 = getelementptr ptr, ptr %t64, i32 2
  store ptr %t47, ptr %t68
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.63
reuse.copy.end.63:
  br label %reuse.join.61
reuse.join.61:
  %t69 = phi ptr [ %t5, %reuse.in_place.end.62 ], [ %t64, %reuse.copy.end.63 ]
  call void @__free_recursive(ptr %t6)
  store ptr %t49, ptr %t3
  store ptr %t69, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t70 = load ptr, ptr %t2
  ret ptr %t70
}

define internal ptr @v__apply__df_andThenIO_0(ptr %v__k, ptr %v__x) {
entry:
  %t3 = alloca ptr
  store ptr %v__k, ptr %t3
  %t4 = alloca ptr
  store ptr %v__x, ptr %t4
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t5 = load ptr, ptr %t3
  %t6 = load ptr, ptr %t4
  %t7 = getelementptr ptr, ptr %t5, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %tco.case.default.10 [ i64 8, label %tco.case.arm.8.11 i64 9, label %tco.case.arm.9.12 ]
tco.case.arm.8.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.9.12:
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

define internal ptr @v__cps__df_andThenIO_4(ptr %v_io, ptr %v__k) {
entry:
  %t3 = alloca ptr
  store ptr %v_io, ptr %t3
  %t4 = alloca ptr
  store ptr %v__k, ptr %t4
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t5 = load ptr, ptr %t3
  %t6 = load ptr, ptr %t4
  %t7 = getelementptr ptr, ptr %t5, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 7, label %tco.case.arm.7.44 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = call ptr @__alloc(i64 16, i32 1)
  %t16 = inttoptr i64 1615808600 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = getelementptr ptr, ptr %t15, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t18
  %t19 = getelementptr ptr, ptr %t15, i32 0
  %t20 = load ptr, ptr %t19
  %t21 = ptrtoint ptr %t20 to i64
  switch i64 %t21, label %case.default.22 [ i64 1615808600, label %case.arm.1615808600.24 i64 2711245919, label %case.arm.2711245919.28 ]
case.arm.1615808600.24:
  %t26 = getelementptr ptr, ptr %t15, i32 1
  %t27 = load ptr, ptr %t26
  call void @__inc_ref(ptr %t27)
  br label %case.end.1615808600.25
case.end.1615808600.25:
  br label %case.join.23
case.arm.2711245919.28:
  %t30 = getelementptr ptr, ptr %t15, i32 1
  %t31 = load ptr, ptr %t30
  call void @__inc_ref(ptr %t31)
  %t32 = call ptr @__showInt32(ptr %t31)
  br label %case.end.2711245919.29
case.end.2711245919.29:
  br label %case.join.23
case.default.22:
  unreachable
case.join.23:
  %t33 = phi ptr [ %t27, %case.end.1615808600.25 ], [ %t32, %case.end.2711245919.29 ]
  call void @__free_recursive(ptr %t15)
  %t34 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t33, ptr %t34
  %t35 = call ptr @__alloc(i64 16, i32 1)
  %t36 = inttoptr i64 5 to ptr
  %t37 = getelementptr ptr, ptr %t35, i32 0
  store ptr %t36, ptr %t37
  %t38 = call ptr @__alloc(i64 8, i32 0)
  %t39 = inttoptr i64 0 to ptr
  %t40 = getelementptr ptr, ptr %t38, i32 0
  store ptr %t39, ptr %t40
  %t41 = getelementptr ptr, ptr %t35, i32 1
  store ptr %t38, ptr %t41
  %t42 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t35, ptr %t42
  %t43 = call ptr @v__apply__df_andThenIO_4(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t43, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.44:
  %t45 = getelementptr ptr, ptr %t5, i32 1
  %t46 = load ptr, ptr %t45
  %t47 = getelementptr ptr, ptr %t5, i32 2
  %t48 = load ptr, ptr %t47
  call void @__inc_ref(ptr %t48)
  %t55 = getelementptr i8, ptr %t5, i64 -8
  %t56 = load i32, ptr %t55
  %t57 = icmp eq i32 %t56, 1
  br i1 %t57, label %reuse.in_place.58, label %reuse.copy.59
reuse.in_place.58:
  %t49 = getelementptr ptr, ptr %t5, i32 2
  %t50 = load ptr, ptr %t49
  call void @__free_recursive(ptr %t50)
  %t53 = inttoptr i64 11 to ptr
  %t54 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t53, ptr %t54
  call void @__inc_ref(ptr %t6)
  %t51 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t51
  %t52 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t46, ptr %t52
  br label %reuse.in_place.end.61
reuse.in_place.end.61:
  br label %reuse.join.60
reuse.copy.59:
  %t63 = call ptr @__alloc(i64 24, i32 2)
  %t64 = inttoptr i64 11 to ptr
  %t65 = getelementptr ptr, ptr %t63, i32 0
  store ptr %t64, ptr %t65
  call void @__inc_ref(ptr %t6)
  %t66 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t6, ptr %t66
  call void @__inc_ref(ptr %t46)
  %t67 = getelementptr ptr, ptr %t63, i32 2
  store ptr %t46, ptr %t67
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.62
reuse.copy.end.62:
  br label %reuse.join.60
reuse.join.60:
  %t68 = phi ptr [ %t5, %reuse.in_place.end.61 ], [ %t63, %reuse.copy.end.62 ]
  call void @__free_recursive(ptr %t6)
  store ptr %t48, ptr %t3
  store ptr %t68, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t69 = load ptr, ptr %t2
  ret ptr %t69
}

define internal ptr @v__apply__df_andThenIO_4(ptr %v__k, ptr %v__x) {
entry:
  %t3 = alloca ptr
  store ptr %v__k, ptr %t3
  %t4 = alloca ptr
  store ptr %v__x, ptr %t4
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t5 = load ptr, ptr %t3
  %t6 = load ptr, ptr %t4
  %t7 = getelementptr ptr, ptr %t5, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %tco.case.default.10 [ i64 10, label %tco.case.arm.10.11 i64 11, label %tco.case.arm.11.12 ]
tco.case.arm.10.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.11.12:
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
