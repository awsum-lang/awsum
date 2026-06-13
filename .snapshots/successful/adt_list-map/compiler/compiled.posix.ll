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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"a" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"b" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"c" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"!" }
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [0 x i8]} { i32 0, i32 0, i32 0, i32 0, i32 0, [0 x i8] zeroinitializer }
@.str.6 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"," }

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
  %stl_tag = inttoptr i64 19 to ptr
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
  %result = phi ptr [ %left, %too_long ], [ %right, %ok ]
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
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 15 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 24, i32 2)
  %t4 = inttoptr i64 14 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t3, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t6
  %t7 = call ptr @__alloc(i64 24, i32 2)
  %t8 = inttoptr i64 14 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = getelementptr ptr, ptr %t7, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t10
  %t11 = call ptr @__alloc(i64 24, i32 2)
  %t12 = inttoptr i64 14 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  %t14 = getelementptr ptr, ptr %t11, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t14
  %t15 = call ptr @__alloc(i64 8, i32 0)
  %t16 = inttoptr i64 13 to ptr
  %t17 = getelementptr ptr, ptr %t15, i32 0
  store ptr %t16, ptr %t17
  %t18 = getelementptr ptr, ptr %t11, i32 2
  store ptr %t15, ptr %t18
  %t19 = getelementptr ptr, ptr %t7, i32 2
  store ptr %t11, ptr %t19
  %t20 = getelementptr ptr, ptr %t3, i32 2
  store ptr %t7, ptr %t20
  %t21 = call ptr @__alloc(i64 8, i32 0)
  %t22 = inttoptr i64 17 to ptr
  %t23 = getelementptr ptr, ptr %t21, i32 0
  store ptr %t22, ptr %t23
  %t24 = call ptr @v__cps__df_map_0(ptr %t3, ptr %t21)
  %t25 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t24, ptr %t25
  %t26 = call ptr @__alloc(i64 8, i32 0)
  %t27 = inttoptr i64 19 to ptr
  %t28 = getelementptr ptr, ptr %t26, i32 0
  store ptr %t27, ptr %t28
  %t29 = call ptr @v__cps__scc_show_showCons(ptr %t0, ptr %t26)
  %t30 = getelementptr ptr, ptr %t29, i32 0
  %t31 = load ptr, ptr %t30
  %t32 = ptrtoint ptr %t31 to i64
  switch i64 %t32, label %case.default.33 [ i64 3, label %case.arm.3.35 i64 4, label %case.arm.4.49 ]
case.arm.3.35:
  %t37 = call ptr @__alloc(i64 24, i32 2)
  %t38 = inttoptr i64 7 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = getelementptr ptr, ptr %t37, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t40
  %t41 = call ptr @__alloc(i64 16, i32 1)
  %t42 = inttoptr i64 5 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = call ptr @__alloc(i64 8, i32 0)
  %t45 = inttoptr i64 0 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  %t47 = getelementptr ptr, ptr %t41, i32 1
  store ptr %t44, ptr %t47
  %t48 = getelementptr ptr, ptr %t37, i32 2
  store ptr %t41, ptr %t48
  br label %case.end.3.36
case.end.3.36:
  br label %case.join.34
case.arm.4.49:
  %t51 = getelementptr ptr, ptr %t29, i32 1
  %t52 = load ptr, ptr %t51
  call void @__inc_ref(ptr %t52)
  %t53 = call ptr @__alloc(i64 24, i32 2)
  %t54 = inttoptr i64 7 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  call void @__inc_ref(ptr %t52)
  %t56 = getelementptr ptr, ptr %t53, i32 1
  store ptr %t52, ptr %t56
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
  %t64 = getelementptr ptr, ptr %t53, i32 2
  store ptr %t57, ptr %t64
  br label %case.end.4.50
case.end.4.50:
  br label %case.join.34
case.default.33:
  unreachable
case.join.34:
  %t65 = phi ptr [ %t37, %case.end.3.36 ], [ %t53, %case.end.4.50 ]
  call void @__free_recursive(ptr %t29)
  ret ptr %t65
}

define internal ptr @v__cps__df_map_0(ptr %v_list, ptr %v__k) {
entry:
  %t3 = alloca ptr
  store ptr %v_list, ptr %t3
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
  switch i64 %t9, label %tco.case.default.10 [ i64 13, label %tco.case.arm.13.11 i64 14, label %tco.case.arm.14.13 ]
tco.case.arm.13.11:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t12 = call ptr @v__apply__df_map_0(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t12, ptr %t2
  br label %tco.exit.1
tco.case.arm.14.13:
  %t14 = getelementptr ptr, ptr %t5, i32 1
  %t15 = load ptr, ptr %t14
  %t16 = getelementptr ptr, ptr %t5, i32 2
  %t17 = load ptr, ptr %t16
  call void @__inc_ref(ptr %t17)
  %t24 = getelementptr i8, ptr %t5, i64 -8
  %t25 = load i32, ptr %t24
  %t26 = icmp eq i32 %t25, 1
  br i1 %t26, label %reuse.in_place.27, label %reuse.copy.28
reuse.in_place.27:
  %t18 = getelementptr ptr, ptr %t5, i32 2
  %t19 = load ptr, ptr %t18
  call void @__free_recursive(ptr %t19)
  %t22 = inttoptr i64 18 to ptr
  %t23 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t22, ptr %t23
  call void @__inc_ref(ptr %t6)
  %t20 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t20
  %t21 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t15, ptr %t21
  br label %reuse.in_place.end.30
reuse.in_place.end.30:
  br label %reuse.join.29
reuse.copy.28:
  %t32 = call ptr @__alloc(i64 24, i32 2)
  %t33 = inttoptr i64 18 to ptr
  %t34 = getelementptr ptr, ptr %t32, i32 0
  store ptr %t33, ptr %t34
  call void @__inc_ref(ptr %t6)
  %t35 = getelementptr ptr, ptr %t32, i32 1
  store ptr %t6, ptr %t35
  call void @__inc_ref(ptr %t15)
  %t36 = getelementptr ptr, ptr %t32, i32 2
  store ptr %t15, ptr %t36
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.31
reuse.copy.end.31:
  br label %reuse.join.29
reuse.join.29:
  %t37 = phi ptr [ %t5, %reuse.in_place.end.30 ], [ %t32, %reuse.copy.end.31 ]
  call void @__inc_ref(ptr %t17)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t17)
  store ptr %t17, ptr %t3
  store ptr %t37, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t38 = load ptr, ptr %t2
  ret ptr %t38
}

define internal ptr @v__apply__df_map_0(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 17, label %tco.case.arm.17.11 i64 18, label %tco.case.arm.18.12 ]
tco.case.arm.17.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.18.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  %t15 = getelementptr ptr, ptr %t5, i32 2
  %t16 = load ptr, ptr %t15
  call void @__inc_ref(ptr %t16)
  call void @__inc_ref(ptr %t16)
  %t17 = call ptr @__concat(ptr %t16, ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  %t18 = getelementptr ptr, ptr %t5, i32 1
  %t19 = load ptr, ptr %t18
  call void @__free_recursive(ptr %t19)
  %t20 = getelementptr ptr, ptr %t5, i32 2
  %t21 = load ptr, ptr %t20
  call void @__free_recursive(ptr %t21)
  %t24 = inttoptr i64 14 to ptr
  %t25 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t24, ptr %t25
  %t22 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t17, ptr %t22
  call void @__inc_ref(ptr %t6)
  %t23 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t6, ptr %t23
  call void @__inc_ref(ptr %t14)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t16)
  call void @__free_recursive(ptr %t14)
  store ptr %t14, ptr %t3
  store ptr %t5, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t26 = load ptr, ptr %t2
  ret ptr %t26
}

define internal ptr @v__cps__scc_show_showCons(ptr %v__args, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 15, label %tco.case.arm.15.11 i64 16, label %tco.case.arm.16.45 ]
tco.case.arm.15.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t13, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %tco.case.default.17 [ i64 13, label %tco.case.arm.13.18 i64 14, label %tco.case.arm.14.24 ]
tco.case.arm.13.18:
  call void @__inc_ref(ptr %t6)
  %t19 = call ptr @__alloc(i64 16, i32 1)
  %t20 = inttoptr i64 4 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr ptr, ptr %t19, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.5, i64 12), ptr %t22
  %t23 = call ptr @v__apply__scc_show_showCons(ptr %t6, ptr %t19)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t23, ptr %t2
  br label %tco.exit.1
tco.case.arm.14.24:
  %t25 = getelementptr ptr, ptr %t13, i32 1
  %t26 = load ptr, ptr %t25
  %t27 = getelementptr ptr, ptr %t13, i32 2
  %t28 = load ptr, ptr %t27
  %t31 = getelementptr i8, ptr %t13, i64 -8
  %t32 = load i32, ptr %t31
  %t33 = icmp eq i32 %t32, 1
  br i1 %t33, label %reuse.in_place.34, label %reuse.copy.35
reuse.in_place.34:
  %t29 = inttoptr i64 16 to ptr
  %t30 = getelementptr ptr, ptr %t13, i32 0
  store ptr %t29, ptr %t30
  br label %reuse.in_place.end.37
reuse.in_place.end.37:
  br label %reuse.join.36
reuse.copy.35:
  %t39 = call ptr @__alloc(i64 24, i32 2)
  %t40 = inttoptr i64 16 to ptr
  %t41 = getelementptr ptr, ptr %t39, i32 0
  store ptr %t40, ptr %t41
  call void @__inc_ref(ptr %t26)
  %t42 = getelementptr ptr, ptr %t39, i32 1
  store ptr %t26, ptr %t42
  call void @__inc_ref(ptr %t28)
  %t43 = getelementptr ptr, ptr %t39, i32 2
  store ptr %t28, ptr %t43
  call void @__free_recursive(ptr %t13)
  br label %reuse.copy.end.38
reuse.copy.end.38:
  br label %reuse.join.36
reuse.join.36:
  %t44 = phi ptr [ %t13, %reuse.in_place.end.37 ], [ %t39, %reuse.copy.end.38 ]
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  store ptr %t44, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.default.17:
  unreachable
tco.case.arm.16.45:
  %t46 = getelementptr ptr, ptr %t5, i32 1
  %t47 = load ptr, ptr %t46
  call void @__inc_ref(ptr %t47)
  %t48 = getelementptr ptr, ptr %t5, i32 2
  %t49 = load ptr, ptr %t48
  call void @__inc_ref(ptr %t49)
  %t50 = getelementptr ptr, ptr %t47, i32 0
  %t51 = load ptr, ptr %t50
  %t52 = ptrtoint ptr %t51 to i64
  switch i64 %t52, label %tco.case.default.53 [ i64 3, label %tco.case.arm.3.54 i64 4, label %tco.case.arm.4.56 ]
tco.case.arm.3.54:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t47)
  %t55 = call ptr @v__apply__scc_show_showCons(ptr %t6, ptr %t47)
  call void @__free_recursive(ptr %t49)
  call void @__free_recursive(ptr %t47)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t55, ptr %t2
  br label %tco.exit.1
tco.case.arm.4.56:
  %t57 = call ptr @__alloc(i64 16, i32 1)
  %t58 = inttoptr i64 15 to ptr
  %t59 = getelementptr ptr, ptr %t57, i32 0
  store ptr %t58, ptr %t59
  call void @__inc_ref(ptr %t49)
  %t60 = getelementptr ptr, ptr %t57, i32 1
  store ptr %t49, ptr %t60
  %t61 = getelementptr ptr, ptr %t47, i32 1
  %t62 = load ptr, ptr %t61
  call void @__inc_ref(ptr %t62)
  %t63 = getelementptr ptr, ptr %t5, i32 1
  %t64 = load ptr, ptr %t63
  call void @__free_recursive(ptr %t64)
  %t65 = getelementptr ptr, ptr %t5, i32 2
  %t66 = load ptr, ptr %t65
  call void @__free_recursive(ptr %t66)
  %t69 = inttoptr i64 20 to ptr
  %t70 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t69, ptr %t70
  call void @__inc_ref(ptr %t6)
  %t67 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t67
  %t68 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t62, ptr %t68
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t49)
  call void @__free_recursive(ptr %t47)
  store ptr %t57, ptr %t3
  store ptr %t5, ptr %t4
  br label %tco.loop.0
tco.case.default.53:
  unreachable
tco.case.default.10:
  unreachable
tco.exit.1:
  %t71 = load ptr, ptr %t2
  ret ptr %t71
}

define internal ptr @v__apply__scc_show_showCons(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 19, label %tco.case.arm.19.11 i64 20, label %tco.case.arm.20.12 ]
tco.case.arm.19.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.20.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  %t15 = getelementptr ptr, ptr %t6, i32 0
  %t16 = load ptr, ptr %t15
  %t17 = ptrtoint ptr %t16 to i64
  switch i64 %t17, label %tco.case.default.18 [ i64 3, label %tco.case.arm.3.19 i64 4, label %tco.case.arm.4.20 ]
tco.case.arm.3.19:
  call void @__inc_ref(ptr %t14)
  call void @__inc_ref(ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t14)
  store ptr %t14, ptr %t3
  store ptr %t6, ptr %t4
  br label %tco.loop.0
tco.case.arm.4.20:
  %t21 = getelementptr ptr, ptr %t6, i32 1
  %t22 = load ptr, ptr %t21
  call void @__inc_ref(ptr %t22)
  %t23 = getelementptr ptr, ptr %t5, i32 2
  %t24 = load ptr, ptr %t23
  call void @__inc_ref(ptr %t24)
  %t25 = call ptr @__concat(ptr %t24, ptr getelementptr inbounds (i8, ptr @.str.6, i64 12))
  %t26 = getelementptr ptr, ptr %t25, i32 0
  %t27 = load ptr, ptr %t26
  %t28 = ptrtoint ptr %t27 to i64
  switch i64 %t28, label %tco.case.default.29 [ i64 3, label %tco.case.arm.3.30 i64 4, label %tco.case.arm.4.51 ]
tco.case.arm.3.30:
  %t31 = getelementptr ptr, ptr %t25, i32 1
  %t32 = load ptr, ptr %t31
  call void @__inc_ref(ptr %t32)
  %t38 = getelementptr i8, ptr %t6, i64 -8
  %t39 = load i32, ptr %t38
  %t40 = icmp eq i32 %t39, 1
  br i1 %t40, label %reuse.in_place.41, label %reuse.copy.42
reuse.in_place.41:
  %t33 = getelementptr ptr, ptr %t6, i32 1
  %t34 = load ptr, ptr %t33
  call void @__free_recursive(ptr %t34)
  %t36 = inttoptr i64 3 to ptr
  %t37 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t36, ptr %t37
  call void @__inc_ref(ptr %t32)
  %t35 = getelementptr ptr, ptr %t6, i32 1
  store ptr %t32, ptr %t35
  br label %reuse.in_place.end.44
reuse.in_place.end.44:
  br label %reuse.join.43
reuse.copy.42:
  %t46 = call ptr @__alloc(i64 16, i32 1)
  %t47 = inttoptr i64 3 to ptr
  %t48 = getelementptr ptr, ptr %t46, i32 0
  store ptr %t47, ptr %t48
  call void @__inc_ref(ptr %t32)
  %t49 = getelementptr ptr, ptr %t46, i32 1
  store ptr %t32, ptr %t49
  call void @__free_recursive(ptr %t6)
  br label %reuse.copy.end.45
reuse.copy.end.45:
  br label %reuse.join.43
reuse.join.43:
  %t50 = phi ptr [ %t6, %reuse.in_place.end.44 ], [ %t46, %reuse.copy.end.45 ]
  call void @__inc_ref(ptr %t14)
  call void @__free_recursive(ptr %t25)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t32)
  call void @__free_recursive(ptr %t22)
  call void @__free_recursive(ptr %t14)
  store ptr %t14, ptr %t3
  store ptr %t50, ptr %t4
  br label %tco.loop.0
tco.case.arm.4.51:
  %t52 = getelementptr ptr, ptr %t25, i32 1
  %t53 = load ptr, ptr %t52
  call void @__inc_ref(ptr %t53)
  call void @__inc_ref(ptr %t53)
  call void @__inc_ref(ptr %t22)
  %t54 = call ptr @__concat(ptr %t53, ptr %t22)
  call void @__inc_ref(ptr %t14)
  call void @__free_recursive(ptr %t25)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t53)
  call void @__free_recursive(ptr %t22)
  call void @__free_recursive(ptr %t14)
  store ptr %t14, ptr %t3
  store ptr %t54, ptr %t4
  br label %tco.loop.0
tco.case.default.29:
  unreachable
tco.case.default.18:
  unreachable
tco.case.default.10:
  unreachable
tco.exit.1:
  %t55 = load ptr, ptr %t2
  ret ptr %t55
}

define i32 @main(i32 %argc, ptr %argv) {
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
