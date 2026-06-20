; External C declarations
declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare ptr @memcpy(ptr, ptr, i64)
declare i64 @write(i32, ptr, i64)


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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"sA" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"sB" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"iA" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"iB" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"x" }

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
  %t3 = call ptr @__alloc(i64 24, i32 2)
  %t4 = inttoptr i64 26 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = call ptr @__alloc(i64 16, i32 1)
  %t7 = inttoptr i64 2711245919 to ptr
  %t8 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t7, ptr %t8
  %t9 = call ptr @__alloc(i64 4, i32 0)
  store i32 1, ptr %t9
  %t10 = getelementptr ptr, ptr %t6, i32 1
  store ptr %t9, ptr %t10
  %t11 = getelementptr ptr, ptr %t3, i32 1
  store ptr %t6, ptr %t11
  %t12 = call ptr @__alloc(i64 8, i32 0)
  %t13 = inttoptr i64 24 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t3, i32 2
  store ptr %t12, ptr %t15
  %t16 = getelementptr ptr, ptr %t3, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %case.default.19 [ i64 26, label %case.arm.26.21 ]
case.arm.26.21:
  %t23 = getelementptr ptr, ptr %t3, i32 2
  %t24 = load ptr, ptr %t23
  call void @__inc_ref(ptr %t24)
  %t25 = getelementptr ptr, ptr %t3, i32 1
  %t26 = load ptr, ptr %t25
  call void @__inc_ref(ptr %t26)
  %t27 = getelementptr ptr, ptr %t26, i32 0
  %t28 = load ptr, ptr %t27
  %t29 = ptrtoint ptr %t28 to i64
  switch i64 %t29, label %case.default.30 [ i64 1615808600, label %case.arm.1615808600.32 i64 2711245919, label %case.arm.2711245919.44 ]
case.arm.1615808600.32:
  %t34 = getelementptr ptr, ptr %t24, i32 0
  %t35 = load ptr, ptr %t34
  %t36 = ptrtoint ptr %t35 to i64
  switch i64 %t36, label %case.default.37 [ i64 24, label %case.arm.24.39 i64 25, label %case.arm.25.41 ]
case.arm.24.39:
  br label %case.end.24.40
case.end.24.40:
  br label %case.join.38
case.arm.25.41:
  br label %case.end.25.42
case.end.25.42:
  br label %case.join.38
case.default.37:
  unreachable
case.join.38:
  %t43 = phi ptr [ getelementptr inbounds (i8, ptr @.str.0, i64 12), %case.end.24.40 ], [ getelementptr inbounds (i8, ptr @.str.1, i64 12), %case.end.25.42 ]
  br label %case.end.1615808600.33
case.end.1615808600.33:
  br label %case.join.31
case.arm.2711245919.44:
  %t46 = getelementptr ptr, ptr %t24, i32 0
  %t47 = load ptr, ptr %t46
  %t48 = ptrtoint ptr %t47 to i64
  switch i64 %t48, label %case.default.49 [ i64 24, label %case.arm.24.51 i64 25, label %case.arm.25.53 ]
case.arm.24.51:
  br label %case.end.24.52
case.end.24.52:
  br label %case.join.50
case.arm.25.53:
  br label %case.end.25.54
case.end.25.54:
  br label %case.join.50
case.default.49:
  unreachable
case.join.50:
  %t55 = phi ptr [ getelementptr inbounds (i8, ptr @.str.2, i64 12), %case.end.24.52 ], [ getelementptr inbounds (i8, ptr @.str.3, i64 12), %case.end.25.54 ]
  br label %case.end.2711245919.45
case.end.2711245919.45:
  br label %case.join.31
case.default.30:
  unreachable
case.join.31:
  %t56 = phi ptr [ %t43, %case.end.1615808600.33 ], [ %t55, %case.end.2711245919.45 ]
  call void @__free_recursive(ptr %t26)
  br label %case.end.26.22
case.end.26.22:
  br label %case.join.20
case.default.19:
  unreachable
case.join.20:
  %t57 = phi ptr [ %t56, %case.end.26.22 ]
  call void @__free_recursive(ptr %t3)
  %t58 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t57, ptr %t58
  %t59 = call ptr @__alloc(i64 16, i32 1)
  %t60 = inttoptr i64 5 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  %t62 = call ptr @__alloc(i64 8, i32 0)
  %t63 = inttoptr i64 0 to ptr
  %t64 = getelementptr ptr, ptr %t62, i32 0
  store ptr %t63, ptr %t64
  %t65 = getelementptr ptr, ptr %t59, i32 1
  store ptr %t62, ptr %t65
  %t66 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t59, ptr %t66
  %t67 = call ptr @__alloc(i64 8, i32 0)
  %t68 = inttoptr i64 31 to ptr
  %t69 = getelementptr ptr, ptr %t67, i32 0
  store ptr %t68, ptr %t69
  %t70 = call ptr @v__cps__df_andThenIO_8(ptr %t0, ptr %t67)
  %t71 = call ptr @__alloc(i64 8, i32 0)
  %t72 = inttoptr i64 29 to ptr
  %t73 = getelementptr ptr, ptr %t71, i32 0
  store ptr %t72, ptr %t73
  %t74 = call ptr @v__cps__df_andThenIO_4(ptr %t70, ptr %t71)
  %t75 = call ptr @__alloc(i64 8, i32 0)
  %t76 = inttoptr i64 27 to ptr
  %t77 = getelementptr ptr, ptr %t75, i32 0
  store ptr %t76, ptr %t77
  %t78 = call ptr @v__cps__df_andThenIO_0(ptr %t74, ptr %t75)
  ret ptr %t78
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 7, label %tco.case.arm.7.79 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = call ptr @__alloc(i64 24, i32 2)
  %t16 = inttoptr i64 26 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = call ptr @__alloc(i64 16, i32 1)
  %t19 = inttoptr i64 1615808600 to ptr
  %t20 = getelementptr ptr, ptr %t18, i32 0
  store ptr %t19, ptr %t20
  %t21 = getelementptr ptr, ptr %t18, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t21
  %t22 = getelementptr ptr, ptr %t15, i32 1
  store ptr %t18, ptr %t22
  %t23 = call ptr @__alloc(i64 8, i32 0)
  %t24 = inttoptr i64 25 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  %t26 = getelementptr ptr, ptr %t15, i32 2
  store ptr %t23, ptr %t26
  %t27 = getelementptr ptr, ptr %t15, i32 0
  %t28 = load ptr, ptr %t27
  %t29 = ptrtoint ptr %t28 to i64
  switch i64 %t29, label %case.default.30 [ i64 26, label %case.arm.26.32 ]
case.arm.26.32:
  %t34 = getelementptr ptr, ptr %t15, i32 2
  %t35 = load ptr, ptr %t34
  call void @__inc_ref(ptr %t35)
  %t36 = getelementptr ptr, ptr %t15, i32 1
  %t37 = load ptr, ptr %t36
  call void @__inc_ref(ptr %t37)
  %t38 = getelementptr ptr, ptr %t37, i32 0
  %t39 = load ptr, ptr %t38
  %t40 = ptrtoint ptr %t39 to i64
  switch i64 %t40, label %case.default.41 [ i64 1615808600, label %case.arm.1615808600.43 i64 2711245919, label %case.arm.2711245919.55 ]
case.arm.1615808600.43:
  %t45 = getelementptr ptr, ptr %t35, i32 0
  %t46 = load ptr, ptr %t45
  %t47 = ptrtoint ptr %t46 to i64
  switch i64 %t47, label %case.default.48 [ i64 24, label %case.arm.24.50 i64 25, label %case.arm.25.52 ]
case.arm.24.50:
  br label %case.end.24.51
case.end.24.51:
  br label %case.join.49
case.arm.25.52:
  br label %case.end.25.53
case.end.25.53:
  br label %case.join.49
case.default.48:
  unreachable
case.join.49:
  %t54 = phi ptr [ getelementptr inbounds (i8, ptr @.str.0, i64 12), %case.end.24.51 ], [ getelementptr inbounds (i8, ptr @.str.1, i64 12), %case.end.25.53 ]
  br label %case.end.1615808600.44
case.end.1615808600.44:
  br label %case.join.42
case.arm.2711245919.55:
  %t57 = getelementptr ptr, ptr %t35, i32 0
  %t58 = load ptr, ptr %t57
  %t59 = ptrtoint ptr %t58 to i64
  switch i64 %t59, label %case.default.60 [ i64 24, label %case.arm.24.62 i64 25, label %case.arm.25.64 ]
case.arm.24.62:
  br label %case.end.24.63
case.end.24.63:
  br label %case.join.61
case.arm.25.64:
  br label %case.end.25.65
case.end.25.65:
  br label %case.join.61
case.default.60:
  unreachable
case.join.61:
  %t66 = phi ptr [ getelementptr inbounds (i8, ptr @.str.2, i64 12), %case.end.24.63 ], [ getelementptr inbounds (i8, ptr @.str.3, i64 12), %case.end.25.65 ]
  br label %case.end.2711245919.56
case.end.2711245919.56:
  br label %case.join.42
case.default.41:
  unreachable
case.join.42:
  %t67 = phi ptr [ %t54, %case.end.1615808600.44 ], [ %t66, %case.end.2711245919.56 ]
  call void @__free_recursive(ptr %t37)
  call void @__free_recursive(ptr %t35)
  br label %case.end.26.33
case.end.26.33:
  br label %case.join.31
case.default.30:
  unreachable
case.join.31:
  %t68 = phi ptr [ %t67, %case.end.26.33 ]
  call void @__free_recursive(ptr %t15)
  %t69 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t68, ptr %t69
  %t70 = call ptr @__alloc(i64 16, i32 1)
  %t71 = inttoptr i64 5 to ptr
  %t72 = getelementptr ptr, ptr %t70, i32 0
  store ptr %t71, ptr %t72
  %t73 = call ptr @__alloc(i64 8, i32 0)
  %t74 = inttoptr i64 0 to ptr
  %t75 = getelementptr ptr, ptr %t73, i32 0
  store ptr %t74, ptr %t75
  %t76 = getelementptr ptr, ptr %t70, i32 1
  store ptr %t73, ptr %t76
  %t77 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t70, ptr %t77
  %t78 = call ptr @v__apply__df_andThenIO_0(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t78, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.79:
  %t80 = getelementptr ptr, ptr %t5, i32 1
  %t81 = load ptr, ptr %t80
  %t82 = getelementptr ptr, ptr %t5, i32 2
  %t83 = load ptr, ptr %t82
  call void @__inc_ref(ptr %t83)
  %t90 = getelementptr i8, ptr %t5, i64 -8
  %t91 = load i32, ptr %t90
  %t92 = icmp eq i32 %t91, 1
  br i1 %t92, label %reuse.in_place.93, label %reuse.copy.94
reuse.in_place.93:
  %t84 = getelementptr ptr, ptr %t5, i32 2
  %t85 = load ptr, ptr %t84
  call void @__free_recursive(ptr %t85)
  %t88 = inttoptr i64 28 to ptr
  %t89 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t88, ptr %t89
  call void @__inc_ref(ptr %t6)
  %t86 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t86
  %t87 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t81, ptr %t87
  br label %reuse.in_place.end.96
reuse.in_place.end.96:
  br label %reuse.join.95
reuse.copy.94:
  %t98 = call ptr @__alloc(i64 24, i32 2)
  %t99 = inttoptr i64 28 to ptr
  %t100 = getelementptr ptr, ptr %t98, i32 0
  store ptr %t99, ptr %t100
  call void @__inc_ref(ptr %t6)
  %t101 = getelementptr ptr, ptr %t98, i32 1
  store ptr %t6, ptr %t101
  call void @__inc_ref(ptr %t81)
  %t102 = getelementptr ptr, ptr %t98, i32 2
  store ptr %t81, ptr %t102
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.97
reuse.copy.end.97:
  br label %reuse.join.95
reuse.join.95:
  %t103 = phi ptr [ %t5, %reuse.in_place.end.96 ], [ %t98, %reuse.copy.end.97 ]
  call void @__inc_ref(ptr %t83)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t83)
  store ptr %t83, ptr %t3
  store ptr %t103, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t104 = load ptr, ptr %t2
  ret ptr %t104
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 7, label %tco.case.arm.7.79 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = call ptr @__alloc(i64 24, i32 2)
  %t16 = inttoptr i64 26 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = call ptr @__alloc(i64 16, i32 1)
  %t19 = inttoptr i64 1615808600 to ptr
  %t20 = getelementptr ptr, ptr %t18, i32 0
  store ptr %t19, ptr %t20
  %t21 = getelementptr ptr, ptr %t18, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t21
  %t22 = getelementptr ptr, ptr %t15, i32 1
  store ptr %t18, ptr %t22
  %t23 = call ptr @__alloc(i64 8, i32 0)
  %t24 = inttoptr i64 24 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  %t26 = getelementptr ptr, ptr %t15, i32 2
  store ptr %t23, ptr %t26
  %t27 = getelementptr ptr, ptr %t15, i32 0
  %t28 = load ptr, ptr %t27
  %t29 = ptrtoint ptr %t28 to i64
  switch i64 %t29, label %case.default.30 [ i64 26, label %case.arm.26.32 ]
case.arm.26.32:
  %t34 = getelementptr ptr, ptr %t15, i32 2
  %t35 = load ptr, ptr %t34
  call void @__inc_ref(ptr %t35)
  %t36 = getelementptr ptr, ptr %t15, i32 1
  %t37 = load ptr, ptr %t36
  call void @__inc_ref(ptr %t37)
  %t38 = getelementptr ptr, ptr %t37, i32 0
  %t39 = load ptr, ptr %t38
  %t40 = ptrtoint ptr %t39 to i64
  switch i64 %t40, label %case.default.41 [ i64 1615808600, label %case.arm.1615808600.43 i64 2711245919, label %case.arm.2711245919.55 ]
case.arm.1615808600.43:
  %t45 = getelementptr ptr, ptr %t35, i32 0
  %t46 = load ptr, ptr %t45
  %t47 = ptrtoint ptr %t46 to i64
  switch i64 %t47, label %case.default.48 [ i64 24, label %case.arm.24.50 i64 25, label %case.arm.25.52 ]
case.arm.24.50:
  br label %case.end.24.51
case.end.24.51:
  br label %case.join.49
case.arm.25.52:
  br label %case.end.25.53
case.end.25.53:
  br label %case.join.49
case.default.48:
  unreachable
case.join.49:
  %t54 = phi ptr [ getelementptr inbounds (i8, ptr @.str.0, i64 12), %case.end.24.51 ], [ getelementptr inbounds (i8, ptr @.str.1, i64 12), %case.end.25.53 ]
  br label %case.end.1615808600.44
case.end.1615808600.44:
  br label %case.join.42
case.arm.2711245919.55:
  %t57 = getelementptr ptr, ptr %t35, i32 0
  %t58 = load ptr, ptr %t57
  %t59 = ptrtoint ptr %t58 to i64
  switch i64 %t59, label %case.default.60 [ i64 24, label %case.arm.24.62 i64 25, label %case.arm.25.64 ]
case.arm.24.62:
  br label %case.end.24.63
case.end.24.63:
  br label %case.join.61
case.arm.25.64:
  br label %case.end.25.65
case.end.25.65:
  br label %case.join.61
case.default.60:
  unreachable
case.join.61:
  %t66 = phi ptr [ getelementptr inbounds (i8, ptr @.str.2, i64 12), %case.end.24.63 ], [ getelementptr inbounds (i8, ptr @.str.3, i64 12), %case.end.25.65 ]
  br label %case.end.2711245919.56
case.end.2711245919.56:
  br label %case.join.42
case.default.41:
  unreachable
case.join.42:
  %t67 = phi ptr [ %t54, %case.end.1615808600.44 ], [ %t66, %case.end.2711245919.56 ]
  call void @__free_recursive(ptr %t37)
  call void @__free_recursive(ptr %t35)
  br label %case.end.26.33
case.end.26.33:
  br label %case.join.31
case.default.30:
  unreachable
case.join.31:
  %t68 = phi ptr [ %t67, %case.end.26.33 ]
  call void @__free_recursive(ptr %t15)
  %t69 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t68, ptr %t69
  %t70 = call ptr @__alloc(i64 16, i32 1)
  %t71 = inttoptr i64 5 to ptr
  %t72 = getelementptr ptr, ptr %t70, i32 0
  store ptr %t71, ptr %t72
  %t73 = call ptr @__alloc(i64 8, i32 0)
  %t74 = inttoptr i64 0 to ptr
  %t75 = getelementptr ptr, ptr %t73, i32 0
  store ptr %t74, ptr %t75
  %t76 = getelementptr ptr, ptr %t70, i32 1
  store ptr %t73, ptr %t76
  %t77 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t70, ptr %t77
  %t78 = call ptr @v__apply__df_andThenIO_4(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t78, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.79:
  %t80 = getelementptr ptr, ptr %t5, i32 1
  %t81 = load ptr, ptr %t80
  %t82 = getelementptr ptr, ptr %t5, i32 2
  %t83 = load ptr, ptr %t82
  call void @__inc_ref(ptr %t83)
  %t90 = getelementptr i8, ptr %t5, i64 -8
  %t91 = load i32, ptr %t90
  %t92 = icmp eq i32 %t91, 1
  br i1 %t92, label %reuse.in_place.93, label %reuse.copy.94
reuse.in_place.93:
  %t84 = getelementptr ptr, ptr %t5, i32 2
  %t85 = load ptr, ptr %t84
  call void @__free_recursive(ptr %t85)
  %t88 = inttoptr i64 30 to ptr
  %t89 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t88, ptr %t89
  call void @__inc_ref(ptr %t6)
  %t86 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t86
  %t87 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t81, ptr %t87
  br label %reuse.in_place.end.96
reuse.in_place.end.96:
  br label %reuse.join.95
reuse.copy.94:
  %t98 = call ptr @__alloc(i64 24, i32 2)
  %t99 = inttoptr i64 30 to ptr
  %t100 = getelementptr ptr, ptr %t98, i32 0
  store ptr %t99, ptr %t100
  call void @__inc_ref(ptr %t6)
  %t101 = getelementptr ptr, ptr %t98, i32 1
  store ptr %t6, ptr %t101
  call void @__inc_ref(ptr %t81)
  %t102 = getelementptr ptr, ptr %t98, i32 2
  store ptr %t81, ptr %t102
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.97
reuse.copy.end.97:
  br label %reuse.join.95
reuse.join.95:
  %t103 = phi ptr [ %t5, %reuse.in_place.end.96 ], [ %t98, %reuse.copy.end.97 ]
  call void @__inc_ref(ptr %t83)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t83)
  store ptr %t83, ptr %t3
  store ptr %t103, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t104 = load ptr, ptr %t2
  ret ptr %t104
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 7, label %tco.case.arm.7.80 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = call ptr @__alloc(i64 24, i32 2)
  %t16 = inttoptr i64 26 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = call ptr @__alloc(i64 16, i32 1)
  %t19 = inttoptr i64 2711245919 to ptr
  %t20 = getelementptr ptr, ptr %t18, i32 0
  store ptr %t19, ptr %t20
  %t21 = call ptr @__alloc(i64 4, i32 0)
  store i32 1, ptr %t21
  %t22 = getelementptr ptr, ptr %t18, i32 1
  store ptr %t21, ptr %t22
  %t23 = getelementptr ptr, ptr %t15, i32 1
  store ptr %t18, ptr %t23
  %t24 = call ptr @__alloc(i64 8, i32 0)
  %t25 = inttoptr i64 25 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = getelementptr ptr, ptr %t15, i32 2
  store ptr %t24, ptr %t27
  %t28 = getelementptr ptr, ptr %t15, i32 0
  %t29 = load ptr, ptr %t28
  %t30 = ptrtoint ptr %t29 to i64
  switch i64 %t30, label %case.default.31 [ i64 26, label %case.arm.26.33 ]
case.arm.26.33:
  %t35 = getelementptr ptr, ptr %t15, i32 2
  %t36 = load ptr, ptr %t35
  call void @__inc_ref(ptr %t36)
  %t37 = getelementptr ptr, ptr %t15, i32 1
  %t38 = load ptr, ptr %t37
  call void @__inc_ref(ptr %t38)
  %t39 = getelementptr ptr, ptr %t38, i32 0
  %t40 = load ptr, ptr %t39
  %t41 = ptrtoint ptr %t40 to i64
  switch i64 %t41, label %case.default.42 [ i64 1615808600, label %case.arm.1615808600.44 i64 2711245919, label %case.arm.2711245919.56 ]
case.arm.1615808600.44:
  %t46 = getelementptr ptr, ptr %t36, i32 0
  %t47 = load ptr, ptr %t46
  %t48 = ptrtoint ptr %t47 to i64
  switch i64 %t48, label %case.default.49 [ i64 24, label %case.arm.24.51 i64 25, label %case.arm.25.53 ]
case.arm.24.51:
  br label %case.end.24.52
case.end.24.52:
  br label %case.join.50
case.arm.25.53:
  br label %case.end.25.54
case.end.25.54:
  br label %case.join.50
case.default.49:
  unreachable
case.join.50:
  %t55 = phi ptr [ getelementptr inbounds (i8, ptr @.str.0, i64 12), %case.end.24.52 ], [ getelementptr inbounds (i8, ptr @.str.1, i64 12), %case.end.25.54 ]
  br label %case.end.1615808600.45
case.end.1615808600.45:
  br label %case.join.43
case.arm.2711245919.56:
  %t58 = getelementptr ptr, ptr %t36, i32 0
  %t59 = load ptr, ptr %t58
  %t60 = ptrtoint ptr %t59 to i64
  switch i64 %t60, label %case.default.61 [ i64 24, label %case.arm.24.63 i64 25, label %case.arm.25.65 ]
case.arm.24.63:
  br label %case.end.24.64
case.end.24.64:
  br label %case.join.62
case.arm.25.65:
  br label %case.end.25.66
case.end.25.66:
  br label %case.join.62
case.default.61:
  unreachable
case.join.62:
  %t67 = phi ptr [ getelementptr inbounds (i8, ptr @.str.2, i64 12), %case.end.24.64 ], [ getelementptr inbounds (i8, ptr @.str.3, i64 12), %case.end.25.66 ]
  br label %case.end.2711245919.57
case.end.2711245919.57:
  br label %case.join.43
case.default.42:
  unreachable
case.join.43:
  %t68 = phi ptr [ %t55, %case.end.1615808600.45 ], [ %t67, %case.end.2711245919.57 ]
  call void @__free_recursive(ptr %t38)
  call void @__free_recursive(ptr %t36)
  br label %case.end.26.34
case.end.26.34:
  br label %case.join.32
case.default.31:
  unreachable
case.join.32:
  %t69 = phi ptr [ %t68, %case.end.26.34 ]
  call void @__free_recursive(ptr %t15)
  %t70 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t69, ptr %t70
  %t71 = call ptr @__alloc(i64 16, i32 1)
  %t72 = inttoptr i64 5 to ptr
  %t73 = getelementptr ptr, ptr %t71, i32 0
  store ptr %t72, ptr %t73
  %t74 = call ptr @__alloc(i64 8, i32 0)
  %t75 = inttoptr i64 0 to ptr
  %t76 = getelementptr ptr, ptr %t74, i32 0
  store ptr %t75, ptr %t76
  %t77 = getelementptr ptr, ptr %t71, i32 1
  store ptr %t74, ptr %t77
  %t78 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t71, ptr %t78
  %t79 = call ptr @v__apply__df_andThenIO_8(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t79, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.80:
  %t81 = getelementptr ptr, ptr %t5, i32 1
  %t82 = load ptr, ptr %t81
  %t83 = getelementptr ptr, ptr %t5, i32 2
  %t84 = load ptr, ptr %t83
  call void @__inc_ref(ptr %t84)
  %t91 = getelementptr i8, ptr %t5, i64 -8
  %t92 = load i32, ptr %t91
  %t93 = icmp eq i32 %t92, 1
  br i1 %t93, label %reuse.in_place.94, label %reuse.copy.95
reuse.in_place.94:
  %t85 = getelementptr ptr, ptr %t5, i32 2
  %t86 = load ptr, ptr %t85
  call void @__free_recursive(ptr %t86)
  %t89 = inttoptr i64 32 to ptr
  %t90 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t89, ptr %t90
  call void @__inc_ref(ptr %t6)
  %t87 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t87
  %t88 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t82, ptr %t88
  br label %reuse.in_place.end.97
reuse.in_place.end.97:
  br label %reuse.join.96
reuse.copy.95:
  %t99 = call ptr @__alloc(i64 24, i32 2)
  %t100 = inttoptr i64 32 to ptr
  %t101 = getelementptr ptr, ptr %t99, i32 0
  store ptr %t100, ptr %t101
  call void @__inc_ref(ptr %t6)
  %t102 = getelementptr ptr, ptr %t99, i32 1
  store ptr %t6, ptr %t102
  call void @__inc_ref(ptr %t82)
  %t103 = getelementptr ptr, ptr %t99, i32 2
  store ptr %t82, ptr %t103
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.98
reuse.copy.end.98:
  br label %reuse.join.96
reuse.join.96:
  %t104 = phi ptr [ %t5, %reuse.in_place.end.97 ], [ %t99, %reuse.copy.end.98 ]
  call void @__inc_ref(ptr %t84)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t84)
  store ptr %t84, ptr %t3
  store ptr %t104, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t105 = load ptr, ptr %t2
  ret ptr %t105
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
