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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"none" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"empty" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"ok" }

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

define internal ptr @v_main() {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 7 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 16, i32 1)
  %t4 = inttoptr i64 12 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = call ptr @__alloc(i64 4, i32 0)
  store i32 5, ptr %t6
  %t7 = getelementptr ptr, ptr %t3, i32 1
  store ptr %t6, ptr %t7
  %t8 = getelementptr ptr, ptr %t3, i32 0
  %t9 = load ptr, ptr %t8
  %t10 = ptrtoint ptr %t9 to i64
  switch i64 %t10, label %case.default.11 [ i64 11, label %case.arm.11.13 i64 12, label %case.arm.12.15 ]
case.arm.11.13:
  br label %case.end.11.14
case.end.11.14:
  br label %case.join.12
case.arm.12.15:
  %t17 = getelementptr ptr, ptr %t3, i32 1
  %t18 = load ptr, ptr %t17
  call void @__inc_ref(ptr %t18)
  %t19 = call ptr @__showInt32(ptr %t18)
  br label %case.end.12.16
case.end.12.16:
  br label %case.join.12
case.default.11:
  unreachable
case.join.12:
  %t20 = phi ptr [ getelementptr inbounds (i8, ptr @.str.0, i64 12), %case.end.11.14 ], [ %t19, %case.end.12.16 ]
  call void @__free_recursive(ptr %t3)
  %t21 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t20, ptr %t21
  %t22 = call ptr @__alloc(i64 16, i32 1)
  %t23 = inttoptr i64 5 to ptr
  %t24 = getelementptr ptr, ptr %t22, i32 0
  store ptr %t23, ptr %t24
  %t25 = call ptr @__alloc(i64 8, i32 0)
  %t26 = inttoptr i64 0 to ptr
  %t27 = getelementptr ptr, ptr %t25, i32 0
  store ptr %t26, ptr %t27
  %t28 = getelementptr ptr, ptr %t22, i32 1
  store ptr %t25, ptr %t28
  %t29 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t22, ptr %t29
  %t30 = call ptr @__alloc(i64 8, i32 0)
  %t31 = inttoptr i64 29 to ptr
  %t32 = getelementptr ptr, ptr %t30, i32 0
  store ptr %t31, ptr %t32
  %t33 = call ptr @v__cps__df_andThenIO_8(ptr %t0, ptr %t30)
  %t34 = call ptr @__alloc(i64 8, i32 0)
  %t35 = inttoptr i64 27 to ptr
  %t36 = getelementptr ptr, ptr %t34, i32 0
  store ptr %t35, ptr %t36
  %t37 = call ptr @v__cps__df_andThenIO_4(ptr %t33, ptr %t34)
  %t38 = call ptr @__alloc(i64 8, i32 0)
  %t39 = inttoptr i64 25 to ptr
  %t40 = getelementptr ptr, ptr %t38, i32 0
  store ptr %t39, ptr %t40
  %t41 = call ptr @v__cps__df_andThenIO_0(ptr %t37, ptr %t38)
  ret ptr %t41
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 7, label %tco.case.arm.7.49 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = call ptr @__alloc(i64 16, i32 1)
  %t16 = inttoptr i64 12 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = call ptr @__alloc(i64 16, i32 1)
  %t19 = inttoptr i64 24 to ptr
  %t20 = getelementptr ptr, ptr %t18, i32 0
  store ptr %t19, ptr %t20
  %t21 = call ptr @__alloc(i64 4, i32 0)
  store i32 6, ptr %t21
  %t22 = getelementptr ptr, ptr %t18, i32 1
  store ptr %t21, ptr %t22
  %t23 = getelementptr ptr, ptr %t15, i32 1
  store ptr %t18, ptr %t23
  %t24 = getelementptr ptr, ptr %t15, i32 0
  %t25 = load ptr, ptr %t24
  %t26 = ptrtoint ptr %t25 to i64
  switch i64 %t26, label %case.default.27 [ i64 11, label %case.arm.11.29 i64 12, label %case.arm.12.31 ]
case.arm.11.29:
  br label %case.end.11.30
case.end.11.30:
  br label %case.join.28
case.arm.12.31:
  %t33 = getelementptr ptr, ptr %t15, i32 1
  %t34 = load ptr, ptr %t33
  call void @__inc_ref(ptr %t34)
  %t35 = getelementptr ptr, ptr %t34, i32 1
  %t36 = load ptr, ptr %t35
  call void @__inc_ref(ptr %t36)
  %t37 = call ptr @__showInt32(ptr %t36)
  call void @__free_recursive(ptr %t34)
  br label %case.end.12.32
case.end.12.32:
  br label %case.join.28
case.default.27:
  unreachable
case.join.28:
  %t38 = phi ptr [ getelementptr inbounds (i8, ptr @.str.0, i64 12), %case.end.11.30 ], [ %t37, %case.end.12.32 ]
  call void @__free_recursive(ptr %t15)
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
  %t48 = call ptr @v__apply__df_andThenIO_0(ptr %t6, ptr %t12)
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
  %t58 = inttoptr i64 26 to ptr
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
  %t69 = inttoptr i64 26 to ptr
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
  switch i64 %t9, label %tco.case.default.10 [ i64 25, label %tco.case.arm.25.11 i64 26, label %tco.case.arm.26.12 ]
tco.case.arm.25.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.26.12:
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 7, label %tco.case.arm.7.47 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = call ptr @__alloc(i64 24, i32 2)
  %t16 = inttoptr i64 14 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = call ptr @__alloc(i64 4, i32 0)
  store i32 3, ptr %t18
  %t19 = getelementptr ptr, ptr %t15, i32 1
  store ptr %t18, ptr %t19
  %t20 = call ptr @__alloc(i64 8, i32 0)
  %t21 = inttoptr i64 13 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = getelementptr ptr, ptr %t15, i32 2
  store ptr %t20, ptr %t23
  %t24 = getelementptr ptr, ptr %t15, i32 0
  %t25 = load ptr, ptr %t24
  %t26 = ptrtoint ptr %t25 to i64
  switch i64 %t26, label %case.default.27 [ i64 13, label %case.arm.13.29 i64 14, label %case.arm.14.31 ]
case.arm.13.29:
  br label %case.end.13.30
case.end.13.30:
  br label %case.join.28
case.arm.14.31:
  %t33 = getelementptr ptr, ptr %t15, i32 1
  %t34 = load ptr, ptr %t33
  call void @__inc_ref(ptr %t34)
  %t35 = call ptr @__showInt32(ptr %t34)
  br label %case.end.14.32
case.end.14.32:
  br label %case.join.28
case.default.27:
  unreachable
case.join.28:
  %t36 = phi ptr [ getelementptr inbounds (i8, ptr @.str.1, i64 12), %case.end.13.30 ], [ %t35, %case.end.14.32 ]
  call void @__free_recursive(ptr %t15)
  %t37 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t36, ptr %t37
  %t38 = call ptr @__alloc(i64 16, i32 1)
  %t39 = inttoptr i64 5 to ptr
  %t40 = getelementptr ptr, ptr %t38, i32 0
  store ptr %t39, ptr %t40
  %t41 = call ptr @__alloc(i64 8, i32 0)
  %t42 = inttoptr i64 0 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = getelementptr ptr, ptr %t38, i32 1
  store ptr %t41, ptr %t44
  %t45 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t38, ptr %t45
  %t46 = call ptr @v__apply__df_andThenIO_4(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t46, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.47:
  %t48 = getelementptr ptr, ptr %t5, i32 1
  %t49 = load ptr, ptr %t48
  %t50 = getelementptr ptr, ptr %t5, i32 2
  %t51 = load ptr, ptr %t50
  call void @__inc_ref(ptr %t51)
  %t58 = getelementptr i8, ptr %t5, i64 -8
  %t59 = load i32, ptr %t58
  %t60 = icmp eq i32 %t59, 1
  br i1 %t60, label %reuse.in_place.61, label %reuse.copy.62
reuse.in_place.61:
  %t52 = getelementptr ptr, ptr %t5, i32 2
  %t53 = load ptr, ptr %t52
  call void @__free_recursive(ptr %t53)
  %t56 = inttoptr i64 28 to ptr
  %t57 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t56, ptr %t57
  call void @__inc_ref(ptr %t6)
  %t54 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t54
  %t55 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t49, ptr %t55
  br label %reuse.in_place.end.64
reuse.in_place.end.64:
  br label %reuse.join.63
reuse.copy.62:
  %t66 = call ptr @__alloc(i64 24, i32 2)
  %t67 = inttoptr i64 28 to ptr
  %t68 = getelementptr ptr, ptr %t66, i32 0
  store ptr %t67, ptr %t68
  call void @__inc_ref(ptr %t6)
  %t69 = getelementptr ptr, ptr %t66, i32 1
  store ptr %t6, ptr %t69
  call void @__inc_ref(ptr %t49)
  %t70 = getelementptr ptr, ptr %t66, i32 2
  store ptr %t49, ptr %t70
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.65
reuse.copy.end.65:
  br label %reuse.join.63
reuse.join.63:
  %t71 = phi ptr [ %t5, %reuse.in_place.end.64 ], [ %t66, %reuse.copy.end.65 ]
  call void @__free_recursive(ptr %t6)
  store ptr %t51, ptr %t3
  store ptr %t71, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t72 = load ptr, ptr %t2
  ret ptr %t72
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
  switch i64 %t9, label %tco.case.default.10 [ i64 27, label %tco.case.arm.27.11 i64 28, label %tco.case.arm.28.12 ]
tco.case.arm.27.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.28.12:
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

define internal ptr @v__cps__df_andThenIO_8(ptr %v_io, ptr %v__k) {
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
  %t16 = inttoptr i64 4 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = getelementptr ptr, ptr %t15, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t18
  %t19 = getelementptr ptr, ptr %t15, i32 0
  %t20 = load ptr, ptr %t19
  %t21 = ptrtoint ptr %t20 to i64
  switch i64 %t21, label %case.default.22 [ i64 3, label %case.arm.3.24 i64 4, label %case.arm.4.29 ]
case.arm.3.24:
  %t26 = getelementptr ptr, ptr %t15, i32 1
  %t27 = load ptr, ptr %t26
  call void @__inc_ref(ptr %t27)
  %t28 = call ptr @__showInt32(ptr %t27)
  br label %case.end.3.25
case.end.3.25:
  br label %case.join.23
case.arm.4.29:
  %t31 = getelementptr ptr, ptr %t15, i32 1
  %t32 = load ptr, ptr %t31
  call void @__inc_ref(ptr %t32)
  br label %case.end.4.30
case.end.4.30:
  br label %case.join.23
case.default.22:
  unreachable
case.join.23:
  %t33 = phi ptr [ %t28, %case.end.3.25 ], [ %t32, %case.end.4.30 ]
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
  %t43 = call ptr @v__apply__df_andThenIO_8(ptr %t6, ptr %t12)
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
  %t53 = inttoptr i64 30 to ptr
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
  %t64 = inttoptr i64 30 to ptr
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

define internal ptr @v__apply__df_andThenIO_8(ptr %v__k, ptr %v__x) {
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

define i32 @main(i32 %argc, ptr %argv) {
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
