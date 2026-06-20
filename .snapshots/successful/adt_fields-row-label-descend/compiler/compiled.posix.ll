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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"y" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"n" }

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
  %t4 = inttoptr i64 26 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = call ptr @__alloc(i64 16, i32 1)
  %t7 = inttoptr i64 2124115655 to ptr
  %t8 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t7, ptr %t8
  %t9 = call ptr @__alloc(i64 8, i32 0)
  %t10 = inttoptr i64 24 to ptr
  %t11 = getelementptr ptr, ptr %t9, i32 0
  store ptr %t10, ptr %t11
  %t12 = getelementptr ptr, ptr %t6, i32 1
  store ptr %t9, ptr %t12
  %t13 = getelementptr ptr, ptr %t3, i32 1
  store ptr %t6, ptr %t13
  %t14 = getelementptr ptr, ptr %t3, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %case.default.17 [ i64 26, label %case.arm.26.19 ]
case.arm.26.19:
  %t21 = getelementptr ptr, ptr %t3, i32 1
  %t22 = load ptr, ptr %t21
  call void @__inc_ref(ptr %t22)
  %t23 = getelementptr ptr, ptr %t22, i32 0
  %t24 = load ptr, ptr %t23
  %t25 = ptrtoint ptr %t24 to i64
  switch i64 %t25, label %case.default.26 [ i64 2124115655, label %case.arm.2124115655.28 i64 2711245919, label %case.arm.2711245919.42 ]
case.arm.2124115655.28:
  %t30 = getelementptr ptr, ptr %t22, i32 1
  %t31 = load ptr, ptr %t30
  call void @__inc_ref(ptr %t31)
  %t32 = getelementptr ptr, ptr %t31, i32 0
  %t33 = load ptr, ptr %t32
  %t34 = ptrtoint ptr %t33 to i64
  switch i64 %t34, label %case.default.35 [ i64 24, label %case.arm.24.37 i64 25, label %case.arm.25.39 ]
case.arm.24.37:
  br label %case.end.24.38
case.end.24.38:
  br label %case.join.36
case.arm.25.39:
  br label %case.end.25.40
case.end.25.40:
  br label %case.join.36
case.default.35:
  unreachable
case.join.36:
  %t41 = phi ptr [ getelementptr inbounds (i8, ptr @.str.0, i64 12), %case.end.24.38 ], [ getelementptr inbounds (i8, ptr @.str.1, i64 12), %case.end.25.40 ]
  call void @__free_recursive(ptr %t31)
  br label %case.end.2124115655.29
case.end.2124115655.29:
  br label %case.join.27
case.arm.2711245919.42:
  %t44 = getelementptr ptr, ptr %t22, i32 1
  %t45 = load ptr, ptr %t44
  call void @__inc_ref(ptr %t45)
  %t46 = call ptr @__showInt32(ptr %t45)
  br label %case.end.2711245919.43
case.end.2711245919.43:
  br label %case.join.27
case.default.26:
  unreachable
case.join.27:
  %t47 = phi ptr [ %t41, %case.end.2124115655.29 ], [ %t46, %case.end.2711245919.43 ]
  br label %case.end.26.20
case.end.26.20:
  br label %case.join.18
case.default.17:
  unreachable
case.join.18:
  %t48 = phi ptr [ %t47, %case.end.26.20 ]
  call void @__free_recursive(ptr %t3)
  %t49 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t48, ptr %t49
  %t50 = call ptr @__alloc(i64 16, i32 1)
  %t51 = inttoptr i64 5 to ptr
  %t52 = getelementptr ptr, ptr %t50, i32 0
  store ptr %t51, ptr %t52
  %t53 = call ptr @__alloc(i64 8, i32 0)
  %t54 = inttoptr i64 0 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  %t56 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t53, ptr %t56
  %t57 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t50, ptr %t57
  %t58 = call ptr @__alloc(i64 8, i32 0)
  %t59 = inttoptr i64 29 to ptr
  %t60 = getelementptr ptr, ptr %t58, i32 0
  store ptr %t59, ptr %t60
  %t61 = call ptr @v__cps__df_andThenIO_4(ptr %t0, ptr %t58)
  %t62 = call ptr @__alloc(i64 8, i32 0)
  %t63 = inttoptr i64 27 to ptr
  %t64 = getelementptr ptr, ptr %t62, i32 0
  store ptr %t63, ptr %t64
  %t65 = call ptr @v__cps__df_andThenIO_0(ptr %t61, ptr %t62)
  ret ptr %t65
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 7, label %tco.case.arm.7.69 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = call ptr @__alloc(i64 16, i32 1)
  %t16 = inttoptr i64 26 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = call ptr @__alloc(i64 16, i32 1)
  %t19 = inttoptr i64 2711245919 to ptr
  %t20 = getelementptr ptr, ptr %t18, i32 0
  store ptr %t19, ptr %t20
  %t21 = call ptr @__alloc(i64 4, i32 0)
  store i32 5, ptr %t21
  %t22 = getelementptr ptr, ptr %t18, i32 1
  store ptr %t21, ptr %t22
  %t23 = getelementptr ptr, ptr %t15, i32 1
  store ptr %t18, ptr %t23
  %t24 = getelementptr ptr, ptr %t15, i32 0
  %t25 = load ptr, ptr %t24
  %t26 = ptrtoint ptr %t25 to i64
  switch i64 %t26, label %case.default.27 [ i64 26, label %case.arm.26.29 ]
case.arm.26.29:
  %t31 = getelementptr ptr, ptr %t15, i32 1
  %t32 = load ptr, ptr %t31
  call void @__inc_ref(ptr %t32)
  %t33 = getelementptr ptr, ptr %t32, i32 0
  %t34 = load ptr, ptr %t33
  %t35 = ptrtoint ptr %t34 to i64
  switch i64 %t35, label %case.default.36 [ i64 2124115655, label %case.arm.2124115655.38 i64 2711245919, label %case.arm.2711245919.52 ]
case.arm.2124115655.38:
  %t40 = getelementptr ptr, ptr %t32, i32 1
  %t41 = load ptr, ptr %t40
  call void @__inc_ref(ptr %t41)
  %t42 = getelementptr ptr, ptr %t41, i32 0
  %t43 = load ptr, ptr %t42
  %t44 = ptrtoint ptr %t43 to i64
  switch i64 %t44, label %case.default.45 [ i64 24, label %case.arm.24.47 i64 25, label %case.arm.25.49 ]
case.arm.24.47:
  br label %case.end.24.48
case.end.24.48:
  br label %case.join.46
case.arm.25.49:
  br label %case.end.25.50
case.end.25.50:
  br label %case.join.46
case.default.45:
  unreachable
case.join.46:
  %t51 = phi ptr [ getelementptr inbounds (i8, ptr @.str.0, i64 12), %case.end.24.48 ], [ getelementptr inbounds (i8, ptr @.str.1, i64 12), %case.end.25.50 ]
  call void @__free_recursive(ptr %t41)
  br label %case.end.2124115655.39
case.end.2124115655.39:
  br label %case.join.37
case.arm.2711245919.52:
  %t54 = getelementptr ptr, ptr %t32, i32 1
  %t55 = load ptr, ptr %t54
  call void @__inc_ref(ptr %t55)
  %t56 = call ptr @__showInt32(ptr %t55)
  br label %case.end.2711245919.53
case.end.2711245919.53:
  br label %case.join.37
case.default.36:
  unreachable
case.join.37:
  %t57 = phi ptr [ %t51, %case.end.2124115655.39 ], [ %t56, %case.end.2711245919.53 ]
  call void @__free_recursive(ptr %t32)
  br label %case.end.26.30
case.end.26.30:
  br label %case.join.28
case.default.27:
  unreachable
case.join.28:
  %t58 = phi ptr [ %t57, %case.end.26.30 ]
  call void @__free_recursive(ptr %t15)
  %t59 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t58, ptr %t59
  %t60 = call ptr @__alloc(i64 16, i32 1)
  %t61 = inttoptr i64 5 to ptr
  %t62 = getelementptr ptr, ptr %t60, i32 0
  store ptr %t61, ptr %t62
  %t63 = call ptr @__alloc(i64 8, i32 0)
  %t64 = inttoptr i64 0 to ptr
  %t65 = getelementptr ptr, ptr %t63, i32 0
  store ptr %t64, ptr %t65
  %t66 = getelementptr ptr, ptr %t60, i32 1
  store ptr %t63, ptr %t66
  %t67 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t60, ptr %t67
  %t68 = call ptr @v__apply__df_andThenIO_0(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t68, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.69:
  %t70 = getelementptr ptr, ptr %t5, i32 1
  %t71 = load ptr, ptr %t70
  %t72 = getelementptr ptr, ptr %t5, i32 2
  %t73 = load ptr, ptr %t72
  call void @__inc_ref(ptr %t73)
  %t80 = getelementptr i8, ptr %t5, i64 -8
  %t81 = load i32, ptr %t80
  %t82 = icmp eq i32 %t81, 1
  br i1 %t82, label %reuse.in_place.83, label %reuse.copy.84
reuse.in_place.83:
  %t74 = getelementptr ptr, ptr %t5, i32 2
  %t75 = load ptr, ptr %t74
  call void @__free_recursive(ptr %t75)
  %t78 = inttoptr i64 28 to ptr
  %t79 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t78, ptr %t79
  call void @__inc_ref(ptr %t6)
  %t76 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t76
  %t77 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t71, ptr %t77
  br label %reuse.in_place.end.86
reuse.in_place.end.86:
  br label %reuse.join.85
reuse.copy.84:
  %t88 = call ptr @__alloc(i64 24, i32 2)
  %t89 = inttoptr i64 28 to ptr
  %t90 = getelementptr ptr, ptr %t88, i32 0
  store ptr %t89, ptr %t90
  call void @__inc_ref(ptr %t6)
  %t91 = getelementptr ptr, ptr %t88, i32 1
  store ptr %t6, ptr %t91
  call void @__inc_ref(ptr %t71)
  %t92 = getelementptr ptr, ptr %t88, i32 2
  store ptr %t71, ptr %t92
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.87
reuse.copy.end.87:
  br label %reuse.join.85
reuse.join.85:
  %t93 = phi ptr [ %t5, %reuse.in_place.end.86 ], [ %t88, %reuse.copy.end.87 ]
  call void @__inc_ref(ptr %t73)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t73)
  store ptr %t73, ptr %t3
  store ptr %t93, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t94 = load ptr, ptr %t2
  ret ptr %t94
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
  call void @__inc_ref(ptr %t14)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t14)
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 7, label %tco.case.arm.7.71 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = call ptr @__alloc(i64 16, i32 1)
  %t16 = inttoptr i64 26 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = call ptr @__alloc(i64 16, i32 1)
  %t19 = inttoptr i64 2124115655 to ptr
  %t20 = getelementptr ptr, ptr %t18, i32 0
  store ptr %t19, ptr %t20
  %t21 = call ptr @__alloc(i64 8, i32 0)
  %t22 = inttoptr i64 25 to ptr
  %t23 = getelementptr ptr, ptr %t21, i32 0
  store ptr %t22, ptr %t23
  %t24 = getelementptr ptr, ptr %t18, i32 1
  store ptr %t21, ptr %t24
  %t25 = getelementptr ptr, ptr %t15, i32 1
  store ptr %t18, ptr %t25
  %t26 = getelementptr ptr, ptr %t15, i32 0
  %t27 = load ptr, ptr %t26
  %t28 = ptrtoint ptr %t27 to i64
  switch i64 %t28, label %case.default.29 [ i64 26, label %case.arm.26.31 ]
case.arm.26.31:
  %t33 = getelementptr ptr, ptr %t15, i32 1
  %t34 = load ptr, ptr %t33
  call void @__inc_ref(ptr %t34)
  %t35 = getelementptr ptr, ptr %t34, i32 0
  %t36 = load ptr, ptr %t35
  %t37 = ptrtoint ptr %t36 to i64
  switch i64 %t37, label %case.default.38 [ i64 2124115655, label %case.arm.2124115655.40 i64 2711245919, label %case.arm.2711245919.54 ]
case.arm.2124115655.40:
  %t42 = getelementptr ptr, ptr %t34, i32 1
  %t43 = load ptr, ptr %t42
  call void @__inc_ref(ptr %t43)
  %t44 = getelementptr ptr, ptr %t43, i32 0
  %t45 = load ptr, ptr %t44
  %t46 = ptrtoint ptr %t45 to i64
  switch i64 %t46, label %case.default.47 [ i64 24, label %case.arm.24.49 i64 25, label %case.arm.25.51 ]
case.arm.24.49:
  br label %case.end.24.50
case.end.24.50:
  br label %case.join.48
case.arm.25.51:
  br label %case.end.25.52
case.end.25.52:
  br label %case.join.48
case.default.47:
  unreachable
case.join.48:
  %t53 = phi ptr [ getelementptr inbounds (i8, ptr @.str.0, i64 12), %case.end.24.50 ], [ getelementptr inbounds (i8, ptr @.str.1, i64 12), %case.end.25.52 ]
  call void @__free_recursive(ptr %t43)
  br label %case.end.2124115655.41
case.end.2124115655.41:
  br label %case.join.39
case.arm.2711245919.54:
  %t56 = getelementptr ptr, ptr %t34, i32 1
  %t57 = load ptr, ptr %t56
  call void @__inc_ref(ptr %t57)
  %t58 = call ptr @__showInt32(ptr %t57)
  br label %case.end.2711245919.55
case.end.2711245919.55:
  br label %case.join.39
case.default.38:
  unreachable
case.join.39:
  %t59 = phi ptr [ %t53, %case.end.2124115655.41 ], [ %t58, %case.end.2711245919.55 ]
  call void @__free_recursive(ptr %t34)
  br label %case.end.26.32
case.end.26.32:
  br label %case.join.30
case.default.29:
  unreachable
case.join.30:
  %t60 = phi ptr [ %t59, %case.end.26.32 ]
  call void @__free_recursive(ptr %t15)
  %t61 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t60, ptr %t61
  %t62 = call ptr @__alloc(i64 16, i32 1)
  %t63 = inttoptr i64 5 to ptr
  %t64 = getelementptr ptr, ptr %t62, i32 0
  store ptr %t63, ptr %t64
  %t65 = call ptr @__alloc(i64 8, i32 0)
  %t66 = inttoptr i64 0 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  %t68 = getelementptr ptr, ptr %t62, i32 1
  store ptr %t65, ptr %t68
  %t69 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t62, ptr %t69
  %t70 = call ptr @v__apply__df_andThenIO_4(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t70, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.71:
  %t72 = getelementptr ptr, ptr %t5, i32 1
  %t73 = load ptr, ptr %t72
  %t74 = getelementptr ptr, ptr %t5, i32 2
  %t75 = load ptr, ptr %t74
  call void @__inc_ref(ptr %t75)
  %t82 = getelementptr i8, ptr %t5, i64 -8
  %t83 = load i32, ptr %t82
  %t84 = icmp eq i32 %t83, 1
  br i1 %t84, label %reuse.in_place.85, label %reuse.copy.86
reuse.in_place.85:
  %t76 = getelementptr ptr, ptr %t5, i32 2
  %t77 = load ptr, ptr %t76
  call void @__free_recursive(ptr %t77)
  %t80 = inttoptr i64 30 to ptr
  %t81 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t80, ptr %t81
  call void @__inc_ref(ptr %t6)
  %t78 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t78
  %t79 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t73, ptr %t79
  br label %reuse.in_place.end.88
reuse.in_place.end.88:
  br label %reuse.join.87
reuse.copy.86:
  %t90 = call ptr @__alloc(i64 24, i32 2)
  %t91 = inttoptr i64 30 to ptr
  %t92 = getelementptr ptr, ptr %t90, i32 0
  store ptr %t91, ptr %t92
  call void @__inc_ref(ptr %t6)
  %t93 = getelementptr ptr, ptr %t90, i32 1
  store ptr %t6, ptr %t93
  call void @__inc_ref(ptr %t73)
  %t94 = getelementptr ptr, ptr %t90, i32 2
  store ptr %t73, ptr %t94
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.89
reuse.copy.end.89:
  br label %reuse.join.87
reuse.join.87:
  %t95 = phi ptr [ %t5, %reuse.in_place.end.88 ], [ %t90, %reuse.copy.end.89 ]
  call void @__inc_ref(ptr %t75)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t75)
  store ptr %t75, ptr %t3
  store ptr %t95, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t96 = load ptr, ptr %t2
  ret ptr %t96
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
  call void @__inc_ref(ptr %t14)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t14)
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
