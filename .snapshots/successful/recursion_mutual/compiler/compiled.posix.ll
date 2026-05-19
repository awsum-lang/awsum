; External C declarations
declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare ptr @memcpy(ptr, ptr, i64)
declare i64 @strlen(ptr)
declare i64 @write(i32, ptr, i64)
declare i32 @printf(ptr, ...)
declare i32 @snprintf(ptr, i64, ptr, ...)

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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [0 x i8]} { i32 0, i32 0, i32 0, i32 0, i32 0, [0 x i8] zeroinitializer }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"A" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"B" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"C" }

define internal ptr @__concat(ptr %a, ptr %b) {
  %ba = load i32, ptr %a
  %ua_p = getelementptr i8, ptr %a, i64 4
  %ua = load i32, ptr %ua_p
  %bb = load i32, ptr %b
  %ub_p = getelementptr i8, ptr %b, i64 4
  %ub = load i32, ptr %ub_p
  %ua64 = zext i32 %ua to i64
  %ub64 = zext i32 %ub to i64
  %usum64 = add i64 %ua64, %ub64
  %over = icmp ugt i64 %usum64, 134217728
  br i1 %over, label %too_long, label %ok
too_long:
  %stl = call ptr @__alloc(i64 8, i32 0)
  %stl_tag = inttoptr i64 15 to ptr
  store ptr %stl_tag, ptr %stl
  %left = call ptr @__alloc(i64 16, i32 1)
  %left_tag = inttoptr i64 3 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %stl, ptr %left_f
  br label %join
ok:
  %ba64 = zext i32 %ba to i64
  %bb64 = zext i32 %bb to i64
  %bsum64 = add i64 %ba64, %bb64
  %alloc64 = add i64 %bsum64, 8
  %buf = call ptr @__alloc(i64 %alloc64, i32 0)
  %bsum32 = trunc i64 %bsum64 to i32
  store i32 %bsum32, ptr %buf
  %usum32 = trunc i64 %usum64 to i32
  %buf_u16p = getelementptr i8, ptr %buf, i64 4
  store i32 %usum32, ptr %buf_u16p
  %buf_payload = getelementptr i8, ptr %buf, i64 8
  %a_payload = getelementptr i8, ptr %a, i64 8
  call ptr @memcpy(ptr %buf_payload, ptr %a_payload, i64 %ba64)
  %buf_payload_b = getelementptr i8, ptr %buf_payload, i64 %ba64
  %b_payload = getelementptr i8, ptr %b, i64 8
  call ptr @memcpy(ptr %buf_payload_b, ptr %b_payload, i64 %bb64)
  %right = call ptr @__alloc(i64 16, i32 1)
  %right_tag = inttoptr i64 4 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %buf, ptr %right_f
  br label %join
join:
  %result = phi ptr [%left, %too_long], [%right, %ok]
  call void @__free_recursive(ptr %a)
  call void @__free_recursive(ptr %b)
  ret ptr %result
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

define internal ptr @v_main() {
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 19 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v_handleA(ptr %t0)
  %t4 = call ptr @v__let_7(ptr %t3)
  ret ptr %t4
}

define internal ptr @v__let_7(ptr %v_res) {
  %t0 = getelementptr ptr, ptr %v_res, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 3, label %case.arm.3.4 i64 4, label %case.arm.4.19 ]
case.arm.3.4:
  %t5 = getelementptr ptr, ptr %v_res, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = call ptr @__alloc(i64 24, i32 2)
  %t8 = inttoptr i64 7 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = getelementptr ptr, ptr %t7, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t10
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
  %t18 = getelementptr ptr, ptr %t7, i32 2
  store ptr %t11, ptr %t18
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_res)
  ret ptr %t7
case.arm.4.19:
  %t20 = getelementptr ptr, ptr %v_res, i32 1
  %t21 = load ptr, ptr %t20
  call void @__inc_ref(ptr %t21)
  %t22 = call ptr @__alloc(i64 24, i32 2)
  %t23 = inttoptr i64 7 to ptr
  %t24 = getelementptr ptr, ptr %t22, i32 0
  store ptr %t23, ptr %t24
  call void @__inc_ref(ptr %t21)
  %t25 = getelementptr ptr, ptr %t22, i32 1
  store ptr %t21, ptr %t25
  %t26 = call ptr @__alloc(i64 16, i32 1)
  %t27 = inttoptr i64 5 to ptr
  %t28 = getelementptr ptr, ptr %t26, i32 0
  store ptr %t27, ptr %t28
  %t29 = call ptr @__alloc(i64 8, i32 0)
  %t30 = inttoptr i64 0 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = getelementptr ptr, ptr %t26, i32 1
  store ptr %t29, ptr %t32
  %t33 = getelementptr ptr, ptr %t22, i32 2
  store ptr %t26, ptr %t33
  call void @__free_recursive(ptr %t21)
  call void @__free_recursive(ptr %v_res)
  ret ptr %t22
case.default.3:
  unreachable
}

define internal ptr @v__scc_handleA_handleB(ptr %v__args) {
  call void @__inc_ref(ptr %v__args)
  %t0 = call ptr @__alloc(i64 8, i32 0)
  %t1 = inttoptr i64 25 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @v__cps__scc_handleA_handleB(ptr %v__args, ptr %t0)
  call void @__free_recursive(ptr %v__args)
  ret ptr %t3
}

define internal ptr @v__cps__scc_handleA_handleB(ptr %v__args, ptr %v__k) {
entry:
  %t3 = alloca ptr
  store ptr %v__args, ptr %t3
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
  switch i64 %t9, label %tco.case.default.10 [ i64 23, label %tco.case.arm.23.11 i64 24, label %tco.case.arm.24.76 ]
tco.case.arm.23.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t13, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %tco.case.default.17 [ i64 19, label %tco.case.arm.19.18 i64 20, label %tco.case.arm.20.42 i64 21, label %tco.case.arm.21.56 i64 22, label %tco.case.arm.22.70 ]
tco.case.arm.19.18:
  %t19 = call ptr @__alloc(i64 8, i32 0)
  %t20 = inttoptr i64 20 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr i8, ptr %t5, i64 -8
  %t23 = load i32, ptr %t22
  %t24 = icmp eq i32 %t23, 1
  br i1 %t24, label %reuse.in_place.25, label %reuse.copy.26
reuse.in_place.25:
  %t28 = getelementptr ptr, ptr %t5, i32 1
  %t29 = load ptr, ptr %t28
  call void @__free_recursive(ptr %t29)
  %t31 = inttoptr i64 24 to ptr
  %t32 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t31, ptr %t32
  %t30 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t19, ptr %t30
  br label %reuse.join.27
reuse.copy.26:
  %t33 = call ptr @__alloc(i64 16, i32 1)
  %t34 = inttoptr i64 24 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = getelementptr ptr, ptr %t33, i32 1
  store ptr %t19, ptr %t36
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.27
reuse.join.27:
  %t37 = phi ptr [ %t5, %reuse.in_place.25 ], [ %t33, %reuse.copy.26 ]
  %t38 = call ptr @__alloc(i64 16, i32 1)
  %t39 = inttoptr i64 26 to ptr
  %t40 = getelementptr ptr, ptr %t38, i32 0
  store ptr %t39, ptr %t40
  call void @__inc_ref(ptr %t6)
  %t41 = getelementptr ptr, ptr %t38, i32 1
  store ptr %t6, ptr %t41
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t13)
  store ptr %t37, ptr %t3
  store ptr %t38, ptr %t4
  br label %tco.loop.0
tco.case.arm.20.42:
  %t43 = getelementptr i8, ptr %t5, i64 -8
  %t44 = load i32, ptr %t43
  %t45 = icmp eq i32 %t44, 1
  br i1 %t45, label %reuse.in_place.46, label %reuse.copy.47
reuse.in_place.46:
  %t49 = inttoptr i64 24 to ptr
  %t50 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t49, ptr %t50
  br label %reuse.join.48
reuse.copy.47:
  %t51 = call ptr @__alloc(i64 16, i32 1)
  %t52 = inttoptr i64 24 to ptr
  %t53 = getelementptr ptr, ptr %t51, i32 0
  store ptr %t52, ptr %t53
  call void @__inc_ref(ptr %t13)
  %t54 = getelementptr ptr, ptr %t51, i32 1
  store ptr %t13, ptr %t54
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.48
reuse.join.48:
  %t55 = phi ptr [ %t5, %reuse.in_place.46 ], [ %t51, %reuse.copy.47 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t13)
  store ptr %t55, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.21.56:
  %t57 = getelementptr i8, ptr %t5, i64 -8
  %t58 = load i32, ptr %t57
  %t59 = icmp eq i32 %t58, 1
  br i1 %t59, label %reuse.in_place.60, label %reuse.copy.61
reuse.in_place.60:
  %t63 = inttoptr i64 24 to ptr
  %t64 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t63, ptr %t64
  br label %reuse.join.62
reuse.copy.61:
  %t65 = call ptr @__alloc(i64 16, i32 1)
  %t66 = inttoptr i64 24 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  call void @__inc_ref(ptr %t13)
  %t68 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t13, ptr %t68
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.62
reuse.join.62:
  %t69 = phi ptr [ %t5, %reuse.in_place.60 ], [ %t65, %reuse.copy.61 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t13)
  store ptr %t69, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.22.70:
  call void @__inc_ref(ptr %t6)
  %t71 = call ptr @__alloc(i64 16, i32 1)
  %t72 = inttoptr i64 4 to ptr
  %t73 = getelementptr ptr, ptr %t71, i32 0
  store ptr %t72, ptr %t73
  %t74 = getelementptr ptr, ptr %t71, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t74
  %t75 = call ptr @v__apply__scc_handleA_handleB(ptr %t6, ptr %t71)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t75, ptr %t2
  br label %tco.exit.1
tco.case.default.17:
  unreachable
tco.case.arm.24.76:
  %t77 = getelementptr ptr, ptr %t5, i32 1
  %t78 = load ptr, ptr %t77
  call void @__inc_ref(ptr %t78)
  %t79 = getelementptr ptr, ptr %t78, i32 0
  %t80 = load ptr, ptr %t79
  %t81 = ptrtoint ptr %t80 to i64
  switch i64 %t81, label %tco.case.default.82 [ i64 19, label %tco.case.arm.19.83 i64 20, label %tco.case.arm.20.97 i64 21, label %tco.case.arm.21.121 i64 22, label %tco.case.arm.22.145 ]
tco.case.arm.19.83:
  %t84 = getelementptr i8, ptr %t5, i64 -8
  %t85 = load i32, ptr %t84
  %t86 = icmp eq i32 %t85, 1
  br i1 %t86, label %reuse.in_place.87, label %reuse.copy.88
reuse.in_place.87:
  %t90 = inttoptr i64 23 to ptr
  %t91 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t90, ptr %t91
  br label %reuse.join.89
reuse.copy.88:
  %t92 = call ptr @__alloc(i64 16, i32 1)
  %t93 = inttoptr i64 23 to ptr
  %t94 = getelementptr ptr, ptr %t92, i32 0
  store ptr %t93, ptr %t94
  call void @__inc_ref(ptr %t78)
  %t95 = getelementptr ptr, ptr %t92, i32 1
  store ptr %t78, ptr %t95
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.89
reuse.join.89:
  %t96 = phi ptr [ %t5, %reuse.in_place.87 ], [ %t92, %reuse.copy.88 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t78)
  store ptr %t96, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.20.97:
  %t98 = call ptr @__alloc(i64 8, i32 0)
  %t99 = inttoptr i64 21 to ptr
  %t100 = getelementptr ptr, ptr %t98, i32 0
  store ptr %t99, ptr %t100
  %t101 = getelementptr i8, ptr %t5, i64 -8
  %t102 = load i32, ptr %t101
  %t103 = icmp eq i32 %t102, 1
  br i1 %t103, label %reuse.in_place.104, label %reuse.copy.105
reuse.in_place.104:
  %t107 = getelementptr ptr, ptr %t5, i32 1
  %t108 = load ptr, ptr %t107
  call void @__free_recursive(ptr %t108)
  %t110 = inttoptr i64 23 to ptr
  %t111 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t110, ptr %t111
  %t109 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t98, ptr %t109
  br label %reuse.join.106
reuse.copy.105:
  %t112 = call ptr @__alloc(i64 16, i32 1)
  %t113 = inttoptr i64 23 to ptr
  %t114 = getelementptr ptr, ptr %t112, i32 0
  store ptr %t113, ptr %t114
  %t115 = getelementptr ptr, ptr %t112, i32 1
  store ptr %t98, ptr %t115
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.106
reuse.join.106:
  %t116 = phi ptr [ %t5, %reuse.in_place.104 ], [ %t112, %reuse.copy.105 ]
  %t117 = call ptr @__alloc(i64 16, i32 1)
  %t118 = inttoptr i64 27 to ptr
  %t119 = getelementptr ptr, ptr %t117, i32 0
  store ptr %t118, ptr %t119
  call void @__inc_ref(ptr %t6)
  %t120 = getelementptr ptr, ptr %t117, i32 1
  store ptr %t6, ptr %t120
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t78)
  store ptr %t116, ptr %t3
  store ptr %t117, ptr %t4
  br label %tco.loop.0
tco.case.arm.21.121:
  %t122 = call ptr @__alloc(i64 8, i32 0)
  %t123 = inttoptr i64 22 to ptr
  %t124 = getelementptr ptr, ptr %t122, i32 0
  store ptr %t123, ptr %t124
  %t125 = getelementptr i8, ptr %t5, i64 -8
  %t126 = load i32, ptr %t125
  %t127 = icmp eq i32 %t126, 1
  br i1 %t127, label %reuse.in_place.128, label %reuse.copy.129
reuse.in_place.128:
  %t131 = getelementptr ptr, ptr %t5, i32 1
  %t132 = load ptr, ptr %t131
  call void @__free_recursive(ptr %t132)
  %t134 = inttoptr i64 23 to ptr
  %t135 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t134, ptr %t135
  %t133 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t122, ptr %t133
  br label %reuse.join.130
reuse.copy.129:
  %t136 = call ptr @__alloc(i64 16, i32 1)
  %t137 = inttoptr i64 23 to ptr
  %t138 = getelementptr ptr, ptr %t136, i32 0
  store ptr %t137, ptr %t138
  %t139 = getelementptr ptr, ptr %t136, i32 1
  store ptr %t122, ptr %t139
  call void @__free_recursive(ptr %t5)
  br label %reuse.join.130
reuse.join.130:
  %t140 = phi ptr [ %t5, %reuse.in_place.128 ], [ %t136, %reuse.copy.129 ]
  %t141 = call ptr @__alloc(i64 16, i32 1)
  %t142 = inttoptr i64 28 to ptr
  %t143 = getelementptr ptr, ptr %t141, i32 0
  store ptr %t142, ptr %t143
  call void @__inc_ref(ptr %t6)
  %t144 = getelementptr ptr, ptr %t141, i32 1
  store ptr %t6, ptr %t144
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t78)
  store ptr %t140, ptr %t3
  store ptr %t141, ptr %t4
  br label %tco.loop.0
tco.case.arm.22.145:
  call void @__inc_ref(ptr %t6)
  %t146 = call ptr @__alloc(i64 16, i32 1)
  %t147 = inttoptr i64 4 to ptr
  %t148 = getelementptr ptr, ptr %t146, i32 0
  store ptr %t147, ptr %t148
  %t149 = getelementptr ptr, ptr %t146, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t149
  %t150 = call ptr @v__apply__scc_handleA_handleB(ptr %t6, ptr %t146)
  call void @__free_recursive(ptr %t78)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t150, ptr %t2
  br label %tco.exit.1
tco.case.default.82:
  unreachable
tco.case.default.10:
  unreachable
tco.exit.1:
  %t151 = load ptr, ptr %t2
  ret ptr %t151
}

define internal ptr @v__apply__scc_handleA_handleB(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 25, label %tco.case.arm.25.11 i64 26, label %tco.case.arm.26.12 i64 27, label %tco.case.arm.27.39 i64 28, label %tco.case.arm.28.66 ]
tco.case.arm.25.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.26.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  %t15 = getelementptr ptr, ptr %t6, i32 0
  %t16 = load ptr, ptr %t15
  %t17 = ptrtoint ptr %t16 to i64
  switch i64 %t17, label %tco.case.default.18 [ i64 3, label %tco.case.arm.3.19 i64 4, label %tco.case.arm.4.35 ]
tco.case.arm.3.19:
  %t20 = getelementptr ptr, ptr %t6, i32 1
  %t21 = load ptr, ptr %t20
  %t22 = getelementptr i8, ptr %t6, i64 -8
  %t23 = load i32, ptr %t22
  %t24 = icmp eq i32 %t23, 1
  br i1 %t24, label %reuse.in_place.25, label %reuse.copy.26
reuse.in_place.25:
  %t28 = inttoptr i64 3 to ptr
  %t29 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t28, ptr %t29
  br label %reuse.join.27
reuse.copy.26:
  %t30 = call ptr @__alloc(i64 16, i32 1)
  %t31 = inttoptr i64 3 to ptr
  %t32 = getelementptr ptr, ptr %t30, i32 0
  store ptr %t31, ptr %t32
  call void @__inc_ref(ptr %t21)
  %t33 = getelementptr ptr, ptr %t30, i32 1
  store ptr %t21, ptr %t33
  call void @__free_recursive(ptr %t6)
  br label %reuse.join.27
reuse.join.27:
  %t34 = phi ptr [ %t6, %reuse.in_place.25 ], [ %t30, %reuse.copy.26 ]
  call void @__inc_ref(ptr %t14)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t14)
  store ptr %t14, ptr %t3
  store ptr %t34, ptr %t4
  br label %tco.loop.0
tco.case.arm.4.35:
  %t36 = getelementptr ptr, ptr %t6, i32 1
  %t37 = load ptr, ptr %t36
  call void @__inc_ref(ptr %t37)
  call void @__inc_ref(ptr %t37)
  %t38 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t37)
  call void @__inc_ref(ptr %t14)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t37)
  call void @__free_recursive(ptr %t14)
  store ptr %t14, ptr %t3
  store ptr %t38, ptr %t4
  br label %tco.loop.0
tco.case.default.18:
  unreachable
tco.case.arm.27.39:
  %t40 = getelementptr ptr, ptr %t5, i32 1
  %t41 = load ptr, ptr %t40
  call void @__inc_ref(ptr %t41)
  %t42 = getelementptr ptr, ptr %t6, i32 0
  %t43 = load ptr, ptr %t42
  %t44 = ptrtoint ptr %t43 to i64
  switch i64 %t44, label %tco.case.default.45 [ i64 3, label %tco.case.arm.3.46 i64 4, label %tco.case.arm.4.62 ]
tco.case.arm.3.46:
  %t47 = getelementptr ptr, ptr %t6, i32 1
  %t48 = load ptr, ptr %t47
  %t49 = getelementptr i8, ptr %t6, i64 -8
  %t50 = load i32, ptr %t49
  %t51 = icmp eq i32 %t50, 1
  br i1 %t51, label %reuse.in_place.52, label %reuse.copy.53
reuse.in_place.52:
  %t55 = inttoptr i64 3 to ptr
  %t56 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t55, ptr %t56
  br label %reuse.join.54
reuse.copy.53:
  %t57 = call ptr @__alloc(i64 16, i32 1)
  %t58 = inttoptr i64 3 to ptr
  %t59 = getelementptr ptr, ptr %t57, i32 0
  store ptr %t58, ptr %t59
  call void @__inc_ref(ptr %t48)
  %t60 = getelementptr ptr, ptr %t57, i32 1
  store ptr %t48, ptr %t60
  call void @__free_recursive(ptr %t6)
  br label %reuse.join.54
reuse.join.54:
  %t61 = phi ptr [ %t6, %reuse.in_place.52 ], [ %t57, %reuse.copy.53 ]
  call void @__inc_ref(ptr %t41)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t41)
  store ptr %t41, ptr %t3
  store ptr %t61, ptr %t4
  br label %tco.loop.0
tco.case.arm.4.62:
  %t63 = getelementptr ptr, ptr %t6, i32 1
  %t64 = load ptr, ptr %t63
  call void @__inc_ref(ptr %t64)
  call void @__inc_ref(ptr %t64)
  %t65 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t64)
  call void @__inc_ref(ptr %t41)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t64)
  call void @__free_recursive(ptr %t41)
  store ptr %t41, ptr %t3
  store ptr %t65, ptr %t4
  br label %tco.loop.0
tco.case.default.45:
  unreachable
tco.case.arm.28.66:
  %t67 = getelementptr ptr, ptr %t5, i32 1
  %t68 = load ptr, ptr %t67
  call void @__inc_ref(ptr %t68)
  %t69 = getelementptr ptr, ptr %t6, i32 0
  %t70 = load ptr, ptr %t69
  %t71 = ptrtoint ptr %t70 to i64
  switch i64 %t71, label %tco.case.default.72 [ i64 3, label %tco.case.arm.3.73 i64 4, label %tco.case.arm.4.89 ]
tco.case.arm.3.73:
  %t74 = getelementptr ptr, ptr %t6, i32 1
  %t75 = load ptr, ptr %t74
  %t76 = getelementptr i8, ptr %t6, i64 -8
  %t77 = load i32, ptr %t76
  %t78 = icmp eq i32 %t77, 1
  br i1 %t78, label %reuse.in_place.79, label %reuse.copy.80
reuse.in_place.79:
  %t82 = inttoptr i64 3 to ptr
  %t83 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t82, ptr %t83
  br label %reuse.join.81
reuse.copy.80:
  %t84 = call ptr @__alloc(i64 16, i32 1)
  %t85 = inttoptr i64 3 to ptr
  %t86 = getelementptr ptr, ptr %t84, i32 0
  store ptr %t85, ptr %t86
  call void @__inc_ref(ptr %t75)
  %t87 = getelementptr ptr, ptr %t84, i32 1
  store ptr %t75, ptr %t87
  call void @__free_recursive(ptr %t6)
  br label %reuse.join.81
reuse.join.81:
  %t88 = phi ptr [ %t6, %reuse.in_place.79 ], [ %t84, %reuse.copy.80 ]
  call void @__inc_ref(ptr %t68)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t68)
  store ptr %t68, ptr %t3
  store ptr %t88, ptr %t4
  br label %tco.loop.0
tco.case.arm.4.89:
  %t90 = getelementptr ptr, ptr %t6, i32 1
  %t91 = load ptr, ptr %t90
  call void @__inc_ref(ptr %t91)
  call void @__inc_ref(ptr %t91)
  %t92 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t91)
  call void @__inc_ref(ptr %t68)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t91)
  call void @__free_recursive(ptr %t68)
  store ptr %t68, ptr %t3
  store ptr %t92, ptr %t4
  br label %tco.loop.0
tco.case.default.72:
  unreachable
tco.case.default.10:
  unreachable
tco.exit.1:
  %t93 = load ptr, ptr %t2
  ret ptr %t93
}

define internal ptr @v_handleA(ptr %v_step) {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 23 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  call void @__inc_ref(ptr %v_step)
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr %v_step, ptr %t3
  %t4 = call ptr @v__scc_handleA_handleB(ptr %t0)
  call void @__free_recursive(ptr %v_step)
  ret ptr %t4
}

define i32 @main(i32 %argc, ptr %argv) {
  %has_arg = icmp sgt i32 %argc, 1
  br i1 %has_arg, label %with_arg, label %no_arg
with_arg:
  %argptr = getelementptr ptr, ptr %argv, i64 1
  %arg = load ptr, ptr %argptr
  br label %call_main
no_arg:
  br label %call_main
call_main:
  %input = phi ptr [%arg, %with_arg], [getelementptr inbounds (i8, ptr @.empty, i64 12), %no_arg]
  store ptr %input, ptr @.cli_arg
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
