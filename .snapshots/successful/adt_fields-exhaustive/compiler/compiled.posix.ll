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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"AA" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"AB" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"BA" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"BB" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"A?" }
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"B?" }

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
  %t4 = inttoptr i64 15 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = call ptr @__alloc(i64 8, i32 0)
  %t7 = inttoptr i64 24 to ptr
  %t8 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t7, ptr %t8
  %t9 = getelementptr ptr, ptr %t3, i32 1
  store ptr %t6, ptr %t9
  %t10 = call ptr @__alloc(i64 8, i32 0)
  %t11 = inttoptr i64 25 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  %t13 = getelementptr ptr, ptr %t3, i32 2
  store ptr %t10, ptr %t13
  %t14 = getelementptr ptr, ptr %t3, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %case.default.17 [ i64 15, label %case.arm.15.19 ]
case.arm.15.19:
  %t21 = getelementptr ptr, ptr %t3, i32 2
  %t22 = load ptr, ptr %t21
  call void @__inc_ref(ptr %t22)
  %t23 = getelementptr ptr, ptr %t3, i32 1
  %t24 = load ptr, ptr %t23
  call void @__inc_ref(ptr %t24)
  %t25 = getelementptr ptr, ptr %t24, i32 0
  %t26 = load ptr, ptr %t25
  %t27 = ptrtoint ptr %t26 to i64
  switch i64 %t27, label %case.default.28 [ i64 24, label %case.arm.24.30 i64 25, label %case.arm.25.42 ]
case.arm.24.30:
  %t32 = getelementptr ptr, ptr %t22, i32 0
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
  br label %case.end.24.31
case.end.24.31:
  br label %case.join.29
case.arm.25.42:
  %t44 = getelementptr ptr, ptr %t22, i32 0
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
  %t53 = phi ptr [ getelementptr inbounds (i8, ptr @.str.2, i64 12), %case.end.24.50 ], [ getelementptr inbounds (i8, ptr @.str.3, i64 12), %case.end.25.52 ]
  br label %case.end.25.43
case.end.25.43:
  br label %case.join.29
case.default.28:
  unreachable
case.join.29:
  %t54 = phi ptr [ %t41, %case.end.24.31 ], [ %t53, %case.end.25.43 ]
  call void @__free_recursive(ptr %t24)
  br label %case.end.15.20
case.end.15.20:
  br label %case.join.18
case.default.17:
  unreachable
case.join.18:
  %t55 = phi ptr [ %t54, %case.end.15.20 ]
  call void @__free_recursive(ptr %t3)
  %t56 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t55, ptr %t56
  %t57 = call ptr @__alloc(i64 16, i32 1)
  %t58 = inttoptr i64 5 to ptr
  %t59 = getelementptr ptr, ptr %t57, i32 0
  store ptr %t58, ptr %t59
  %t60 = call ptr @__alloc(i64 8, i32 0)
  %t61 = inttoptr i64 0 to ptr
  %t62 = getelementptr ptr, ptr %t60, i32 0
  store ptr %t61, ptr %t62
  %t63 = getelementptr ptr, ptr %t57, i32 1
  store ptr %t60, ptr %t63
  %t64 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t57, ptr %t64
  %t65 = call ptr @__alloc(i64 8, i32 0)
  %t66 = inttoptr i64 26 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  %t68 = call ptr @v_$cps$$df$andThenIO$0(ptr %t0, ptr %t65)
  ret ptr %t68
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 7, label %tco.case.arm.7.48 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = call ptr @__alloc(i64 24, i32 2)
  %t16 = inttoptr i64 15 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = call ptr @__alloc(i64 8, i32 0)
  %t19 = inttoptr i64 25 to ptr
  %t20 = getelementptr ptr, ptr %t18, i32 0
  store ptr %t19, ptr %t20
  %t21 = getelementptr ptr, ptr %t15, i32 1
  store ptr %t18, ptr %t21
  %t22 = call ptr @__alloc(i64 8, i32 0)
  %t23 = inttoptr i64 24 to ptr
  %t24 = getelementptr ptr, ptr %t22, i32 0
  store ptr %t23, ptr %t24
  %t25 = getelementptr ptr, ptr %t15, i32 2
  store ptr %t22, ptr %t25
  %t26 = getelementptr ptr, ptr %t15, i32 1
  %t27 = load ptr, ptr %t26
  call void @__inc_ref(ptr %t27)
  %t28 = getelementptr ptr, ptr %t27, i32 0
  %t29 = load ptr, ptr %t28
  %t30 = ptrtoint ptr %t29 to i64
  switch i64 %t30, label %case.default.31 [ i64 24, label %case.arm.24.33 i64 25, label %case.arm.25.35 ]
case.arm.24.33:
  br label %case.end.24.34
case.end.24.34:
  br label %case.join.32
case.arm.25.35:
  br label %case.end.25.36
case.end.25.36:
  br label %case.join.32
case.default.31:
  unreachable
case.join.32:
  %t37 = phi ptr [ getelementptr inbounds (i8, ptr @.str.4, i64 12), %case.end.24.34 ], [ getelementptr inbounds (i8, ptr @.str.5, i64 12), %case.end.25.36 ]
  call void @__free_recursive(ptr %t27)
  call void @__free_recursive(ptr %t15)
  %t38 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t37, ptr %t38
  %t39 = call ptr @__alloc(i64 16, i32 1)
  %t40 = inttoptr i64 5 to ptr
  %t41 = getelementptr ptr, ptr %t39, i32 0
  store ptr %t40, ptr %t41
  %t42 = call ptr @__alloc(i64 8, i32 0)
  %t43 = inttoptr i64 0 to ptr
  %t44 = getelementptr ptr, ptr %t42, i32 0
  store ptr %t43, ptr %t44
  %t45 = getelementptr ptr, ptr %t39, i32 1
  store ptr %t42, ptr %t45
  %t46 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t39, ptr %t46
  %t47 = call ptr @v_$apply$$df$andThenIO$0(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t47, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.48:
  %t49 = getelementptr ptr, ptr %t5, i32 1
  %t50 = load ptr, ptr %t49
  %t51 = getelementptr ptr, ptr %t5, i32 2
  %t52 = load ptr, ptr %t51
  call void @__inc_ref(ptr %t52)
  %t59 = getelementptr i8, ptr %t5, i64 -8
  %t60 = load i32, ptr %t59
  %t61 = icmp eq i32 %t60, 1
  br i1 %t61, label %reuse.in_place.62, label %reuse.copy.63
reuse.in_place.62:
  %t53 = getelementptr ptr, ptr %t5, i32 2
  %t54 = load ptr, ptr %t53
  call void @__free_recursive(ptr %t54)
  %t57 = inttoptr i64 27 to ptr
  %t58 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t57, ptr %t58
  call void @__inc_ref(ptr %t6)
  %t55 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t55
  %t56 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t50, ptr %t56
  br label %reuse.in_place.end.65
reuse.in_place.end.65:
  br label %reuse.join.64
reuse.copy.63:
  %t67 = call ptr @__alloc(i64 24, i32 2)
  %t68 = inttoptr i64 27 to ptr
  %t69 = getelementptr ptr, ptr %t67, i32 0
  store ptr %t68, ptr %t69
  call void @__inc_ref(ptr %t6)
  %t70 = getelementptr ptr, ptr %t67, i32 1
  store ptr %t6, ptr %t70
  call void @__inc_ref(ptr %t50)
  %t71 = getelementptr ptr, ptr %t67, i32 2
  store ptr %t50, ptr %t71
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.66
reuse.copy.end.66:
  br label %reuse.join.64
reuse.join.64:
  %t72 = phi ptr [ %t5, %reuse.in_place.end.65 ], [ %t67, %reuse.copy.end.66 ]
  call void @__free_recursive(ptr %t6)
  store ptr %t52, ptr %t3
  store ptr %t72, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t73 = load ptr, ptr %t2
  ret ptr %t73
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

define i32 @main(i32 %argc, ptr %argv) {
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
