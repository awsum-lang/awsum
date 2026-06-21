; External C declarations
declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare ptr @memcpy(ptr, ptr, i64)
declare i64 @write(i32, ptr, i64)
declare i32 @snprintf(ptr, i64, ptr, ...)

@.fmt_u8 = private unnamed_addr constant [3 x i8] c"%u\00"

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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"one" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"abc" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"zz" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [8 x i8]} { i32 0, i32 0, i32 0, i32 8, i32 8, [8 x i8] c"OVERFLOW" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"no" }

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


define internal ptr @__showUInt32(ptr %p) {
  %v = load i32, ptr %p
  %buf = call ptr @__alloc(i64 24, i32 0)
  %payload = getelementptr i8, ptr %buf, i64 8
  %n = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %payload, i64 16, ptr @.fmt_u8, i32 %v)
  store i32 %n, ptr %buf
  %u16p = getelementptr i8, ptr %buf, i64 4
  store i32 %n, ptr %u16p
  call void @__free_recursive(ptr %p)
  ret ptr %buf
}


define internal ptr @__eqUInt32(ptr %a, ptr %b) {
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


define internal ptr @__addUInt32(ptr %pa, ptr %pb) {
  %a = load i32, ptr %pa
  %b = load i32, ptr %pb
  %a64 = zext i32 %a to i64
  %b64 = zext i32 %b to i64
  %sum64 = add i64 %a64, %b64
  %ovf = icmp ugt i64 %sum64, 4294967295
  br i1 %ovf, label %err, label %ok
err:
  %oe = call ptr @__alloc(i64 8, i32 0)
  %oe_tag = inttoptr i64 18 to ptr
  store ptr %oe_tag, ptr %oe
  %left = call ptr @__alloc(i64 16, i32 1)
  %left_tag = inttoptr i64 3 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %oe, ptr %left_f
  br label %join
ok:
  %newv = trunc i64 %sum64 to i32
  %box = call ptr @__alloc(i64 4, i32 0)
  store i32 %newv, ptr %box
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


define internal ptr @__lengthUtf8Bytes(ptr %s) {
  %len32 = load i32, ptr %s
  %box = call ptr @__alloc(i64 4, i32 0)
  store i32 %len32, ptr %box
  call void @__free_recursive(ptr %s)
  ret ptr %box
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
  %t3 = call ptr @__lengthUtf8Bytes(ptr getelementptr inbounds (i8, ptr @.str.0, i64 12))
  %t4 = call ptr @__alloc(i64 4, i32 0)
  store i32 3, ptr %t4
  %t5 = call ptr @__eqUInt32(ptr %t3, ptr %t4)
  %t6 = getelementptr ptr, ptr %t5, i32 0
  %t7 = load ptr, ptr %t6
  %t8 = ptrtoint ptr %t7 to i64
  switch i64 %t8, label %case.default.9 [ i64 1, label %case.arm.1.11 i64 2, label %case.arm.2.14 ]
case.arm.1.11:
  %t13 = call ptr @__lengthUtf8Bytes(ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  br label %case.end.1.12
case.end.1.12:
  br label %case.join.10
case.arm.2.14:
  %t16 = call ptr @__lengthUtf8Bytes(ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
  br label %case.end.2.15
case.end.2.15:
  br label %case.join.10
case.default.9:
  unreachable
case.join.10:
  %t17 = phi ptr [ %t13, %case.end.1.12 ], [ %t16, %case.end.2.15 ]
  call void @__free_recursive(ptr %t5)
  call void @__inc_ref(ptr %t17)
  call void @__inc_ref(ptr %t17)
  %t18 = call ptr @__addUInt32(ptr %t17, ptr %t17)
  %t19 = getelementptr ptr, ptr %t18, i32 0
  %t20 = load ptr, ptr %t19
  %t21 = ptrtoint ptr %t20 to i64
  switch i64 %t21, label %case.default.22 [ i64 3, label %case.arm.3.24 i64 4, label %case.arm.4.26 ]
case.arm.3.24:
  br label %case.end.3.25
case.end.3.25:
  br label %case.join.23
case.arm.4.26:
  %t28 = getelementptr ptr, ptr %t18, i32 1
  %t29 = load ptr, ptr %t28
  call void @__inc_ref(ptr %t29)
  call void @__inc_ref(ptr %t29)
  %t30 = call ptr @__showUInt32(ptr %t29)
  br label %case.end.4.27
case.end.4.27:
  br label %case.join.23
case.default.22:
  unreachable
case.join.23:
  %t31 = phi ptr [ getelementptr inbounds (i8, ptr @.str.3, i64 12), %case.end.3.25 ], [ %t30, %case.end.4.27 ]
  call void @__free_recursive(ptr %t18)
  call void @__free_recursive(ptr %t17)
  %t32 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t31, ptr %t32
  %t33 = call ptr @__alloc(i64 16, i32 1)
  %t34 = inttoptr i64 5 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = call ptr @__alloc(i64 8, i32 0)
  %t37 = inttoptr i64 0 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t33, i32 1
  store ptr %t36, ptr %t39
  %t40 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t33, ptr %t40
  %t41 = call ptr @__alloc(i64 8, i32 0)
  %t42 = inttoptr i64 8 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = call ptr @v__cps__df_andThenIO_0(ptr %t0, ptr %t41)
  ret ptr %t44
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 7, label %tco.case.arm.7.54 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = call ptr @__lengthUtf8Bytes(ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  %t16 = call ptr @__alloc(i64 4, i32 0)
  store i32 3, ptr %t16
  %t17 = call ptr @__eqUInt32(ptr %t15, ptr %t16)
  %t18 = getelementptr ptr, ptr %t17, i32 0
  %t19 = load ptr, ptr %t18
  %t20 = ptrtoint ptr %t19 to i64
  switch i64 %t20, label %case.default.21 [ i64 1, label %case.arm.1.23 i64 2, label %case.arm.2.26 ]
case.arm.1.23:
  %t25 = call ptr @__lengthUtf8Bytes(ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  br label %case.end.1.24
case.end.1.24:
  br label %case.join.22
case.arm.2.26:
  %t28 = call ptr @__lengthUtf8Bytes(ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
  br label %case.end.2.27
case.end.2.27:
  br label %case.join.22
case.default.21:
  unreachable
case.join.22:
  %t29 = phi ptr [ %t25, %case.end.1.24 ], [ %t28, %case.end.2.27 ]
  call void @__free_recursive(ptr %t17)
  call void @__inc_ref(ptr %t29)
  call void @__inc_ref(ptr %t29)
  %t30 = call ptr @__addUInt32(ptr %t29, ptr %t29)
  %t31 = getelementptr ptr, ptr %t30, i32 0
  %t32 = load ptr, ptr %t31
  %t33 = ptrtoint ptr %t32 to i64
  switch i64 %t33, label %case.default.34 [ i64 3, label %case.arm.3.36 i64 4, label %case.arm.4.38 ]
case.arm.3.36:
  br label %case.end.3.37
case.end.3.37:
  br label %case.join.35
case.arm.4.38:
  %t40 = getelementptr ptr, ptr %t30, i32 1
  %t41 = load ptr, ptr %t40
  call void @__inc_ref(ptr %t41)
  call void @__inc_ref(ptr %t41)
  %t42 = call ptr @__showUInt32(ptr %t41)
  call void @__free_recursive(ptr %t41)
  br label %case.end.4.39
case.end.4.39:
  br label %case.join.35
case.default.34:
  unreachable
case.join.35:
  %t43 = phi ptr [ getelementptr inbounds (i8, ptr @.str.3, i64 12), %case.end.3.37 ], [ %t42, %case.end.4.39 ]
  call void @__free_recursive(ptr %t30)
  call void @__free_recursive(ptr %t29)
  %t44 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t43, ptr %t44
  %t45 = call ptr @__alloc(i64 16, i32 1)
  %t46 = inttoptr i64 5 to ptr
  %t47 = getelementptr ptr, ptr %t45, i32 0
  store ptr %t46, ptr %t47
  %t48 = call ptr @__alloc(i64 8, i32 0)
  %t49 = inttoptr i64 0 to ptr
  %t50 = getelementptr ptr, ptr %t48, i32 0
  store ptr %t49, ptr %t50
  %t51 = getelementptr ptr, ptr %t45, i32 1
  store ptr %t48, ptr %t51
  %t52 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t45, ptr %t52
  %t53 = call ptr @v__apply__df_andThenIO_0(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t53, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.54:
  %t55 = getelementptr ptr, ptr %t5, i32 1
  %t56 = load ptr, ptr %t55
  %t57 = getelementptr ptr, ptr %t5, i32 2
  %t58 = load ptr, ptr %t57
  call void @__inc_ref(ptr %t58)
  %t65 = getelementptr i8, ptr %t5, i64 -8
  %t66 = load i32, ptr %t65
  %t67 = icmp eq i32 %t66, 1
  br i1 %t67, label %reuse.in_place.68, label %reuse.copy.69
reuse.in_place.68:
  %t59 = getelementptr ptr, ptr %t5, i32 2
  %t60 = load ptr, ptr %t59
  call void @__free_recursive(ptr %t60)
  %t63 = inttoptr i64 9 to ptr
  %t64 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t63, ptr %t64
  call void @__inc_ref(ptr %t6)
  %t61 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t61
  %t62 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t56, ptr %t62
  br label %reuse.in_place.end.71
reuse.in_place.end.71:
  br label %reuse.join.70
reuse.copy.69:
  %t73 = call ptr @__alloc(i64 24, i32 2)
  %t74 = inttoptr i64 9 to ptr
  %t75 = getelementptr ptr, ptr %t73, i32 0
  store ptr %t74, ptr %t75
  call void @__inc_ref(ptr %t6)
  %t76 = getelementptr ptr, ptr %t73, i32 1
  store ptr %t6, ptr %t76
  call void @__inc_ref(ptr %t56)
  %t77 = getelementptr ptr, ptr %t73, i32 2
  store ptr %t56, ptr %t77
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.72
reuse.copy.end.72:
  br label %reuse.join.70
reuse.join.70:
  %t78 = phi ptr [ %t5, %reuse.in_place.end.71 ], [ %t73, %reuse.copy.end.72 ]
  call void @__free_recursive(ptr %t6)
  store ptr %t58, ptr %t3
  store ptr %t78, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t79 = load ptr, ptr %t2
  ret ptr %t79
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

declare i32 @_setmode(i32, i32)

define i32 @main(i32 %argc_posix, ptr %argv_posix) {
entry:
  call i32 @_setmode(i32 1, i32 32768)
  call i32 @_setmode(i32 0, i32 32768)
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
