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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"1" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"," }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"2" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"3" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"4" }
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"5" }
@.str.6 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"6" }
@.str.7 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"7" }
@.str.8 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"8" }
@.str.9 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }

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
  %stl_tag = inttoptr i64 18 to ptr
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

define internal ptr @v_unwrap(ptr %v_r) {
  %t0 = getelementptr ptr, ptr %v_r, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 22, label %case.arm.22.4 i64 23, label %case.arm.23.37 ]
case.arm.22.4:
  %t5 = getelementptr ptr, ptr %v_r, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  %t7 = getelementptr ptr, ptr %t6, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %case.default.10 [ i64 22, label %case.arm.22.11 i64 23, label %case.arm.23.24 ]
case.arm.22.11:
  %t12 = getelementptr ptr, ptr %t6, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = getelementptr ptr, ptr %t13, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %case.default.17 [ i64 22, label %case.arm.22.18 i64 23, label %case.arm.23.21 ]
case.arm.22.18:
  %t19 = getelementptr ptr, ptr %t13, i32 1
  %t20 = load ptr, ptr %t19
  call void @__inc_ref(ptr %t20)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_r)
  ret ptr %t20
case.arm.23.21:
  %t22 = getelementptr ptr, ptr %t13, i32 1
  %t23 = load ptr, ptr %t22
  call void @__inc_ref(ptr %t23)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_r)
  ret ptr %t23
case.default.17:
  unreachable
case.arm.23.24:
  %t25 = getelementptr ptr, ptr %t6, i32 1
  %t26 = load ptr, ptr %t25
  call void @__inc_ref(ptr %t26)
  %t27 = getelementptr ptr, ptr %t26, i32 0
  %t28 = load ptr, ptr %t27
  %t29 = ptrtoint ptr %t28 to i64
  switch i64 %t29, label %case.default.30 [ i64 22, label %case.arm.22.31 i64 23, label %case.arm.23.34 ]
case.arm.22.31:
  %t32 = getelementptr ptr, ptr %t26, i32 1
  %t33 = load ptr, ptr %t32
  call void @__inc_ref(ptr %t33)
  call void @__free_recursive(ptr %t26)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_r)
  ret ptr %t33
case.arm.23.34:
  %t35 = getelementptr ptr, ptr %t26, i32 1
  %t36 = load ptr, ptr %t35
  call void @__inc_ref(ptr %t36)
  call void @__free_recursive(ptr %t26)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_r)
  ret ptr %t36
case.default.30:
  unreachable
case.default.10:
  unreachable
case.arm.23.37:
  %t38 = getelementptr ptr, ptr %v_r, i32 1
  %t39 = load ptr, ptr %t38
  call void @__inc_ref(ptr %t39)
  %t40 = getelementptr ptr, ptr %t39, i32 0
  %t41 = load ptr, ptr %t40
  %t42 = ptrtoint ptr %t41 to i64
  switch i64 %t42, label %case.default.43 [ i64 22, label %case.arm.22.44 i64 23, label %case.arm.23.57 ]
case.arm.22.44:
  %t45 = getelementptr ptr, ptr %t39, i32 1
  %t46 = load ptr, ptr %t45
  call void @__inc_ref(ptr %t46)
  %t47 = getelementptr ptr, ptr %t46, i32 0
  %t48 = load ptr, ptr %t47
  %t49 = ptrtoint ptr %t48 to i64
  switch i64 %t49, label %case.default.50 [ i64 22, label %case.arm.22.51 i64 23, label %case.arm.23.54 ]
case.arm.22.51:
  %t52 = getelementptr ptr, ptr %t46, i32 1
  %t53 = load ptr, ptr %t52
  call void @__inc_ref(ptr %t53)
  call void @__free_recursive(ptr %t46)
  call void @__free_recursive(ptr %t39)
  call void @__free_recursive(ptr %v_r)
  ret ptr %t53
case.arm.23.54:
  %t55 = getelementptr ptr, ptr %t46, i32 1
  %t56 = load ptr, ptr %t55
  call void @__inc_ref(ptr %t56)
  call void @__free_recursive(ptr %t46)
  call void @__free_recursive(ptr %t39)
  call void @__free_recursive(ptr %v_r)
  ret ptr %t56
case.default.50:
  unreachable
case.arm.23.57:
  %t58 = getelementptr ptr, ptr %t39, i32 1
  %t59 = load ptr, ptr %t58
  call void @__inc_ref(ptr %t59)
  %t60 = getelementptr ptr, ptr %t59, i32 0
  %t61 = load ptr, ptr %t60
  %t62 = ptrtoint ptr %t61 to i64
  switch i64 %t62, label %case.default.63 [ i64 22, label %case.arm.22.64 i64 23, label %case.arm.23.67 ]
case.arm.22.64:
  %t65 = getelementptr ptr, ptr %t59, i32 1
  %t66 = load ptr, ptr %t65
  call void @__inc_ref(ptr %t66)
  call void @__free_recursive(ptr %t59)
  call void @__free_recursive(ptr %t39)
  call void @__free_recursive(ptr %v_r)
  ret ptr %t66
case.arm.23.67:
  %t68 = getelementptr ptr, ptr %t59, i32 1
  %t69 = load ptr, ptr %t68
  call void @__inc_ref(ptr %t69)
  call void @__free_recursive(ptr %t59)
  call void @__free_recursive(ptr %t39)
  call void @__free_recursive(ptr %v_r)
  ret ptr %t69
case.default.63:
  unreachable
case.default.43:
  unreachable
case.default.3:
  unreachable
}

define internal ptr @v_main() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 22 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 16, i32 1)
  %t4 = inttoptr i64 22 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = call ptr @__alloc(i64 16, i32 1)
  %t7 = inttoptr i64 22 to ptr
  %t8 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t7, ptr %t8
  %t9 = getelementptr ptr, ptr %t6, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t9
  %t10 = getelementptr ptr, ptr %t3, i32 1
  store ptr %t6, ptr %t10
  %t11 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t11
  %t12 = call ptr @v_unwrap(ptr %t0)
  %t13 = call ptr @__concat(ptr %t12, ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  %t14 = getelementptr ptr, ptr %t13, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %case.default.17 [ i64 3, label %case.arm.3.19 i64 4, label %case.arm.4.27 ]
case.arm.3.19:
  %t21 = getelementptr ptr, ptr %t13, i32 1
  %t22 = load ptr, ptr %t21
  call void @__inc_ref(ptr %t22)
  %t23 = call ptr @__alloc(i64 16, i32 1)
  %t24 = inttoptr i64 3 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  call void @__inc_ref(ptr %t22)
  %t26 = getelementptr ptr, ptr %t23, i32 1
  store ptr %t22, ptr %t26
  br label %case.end.3.20
case.end.3.20:
  br label %case.join.18
case.arm.4.27:
  %t29 = getelementptr ptr, ptr %t13, i32 1
  %t30 = load ptr, ptr %t29
  call void @__inc_ref(ptr %t30)
  call void @__inc_ref(ptr %t30)
  %t31 = call ptr @__alloc(i64 16, i32 1)
  %t32 = inttoptr i64 22 to ptr
  %t33 = getelementptr ptr, ptr %t31, i32 0
  store ptr %t32, ptr %t33
  %t34 = call ptr @__alloc(i64 16, i32 1)
  %t35 = inttoptr i64 22 to ptr
  %t36 = getelementptr ptr, ptr %t34, i32 0
  store ptr %t35, ptr %t36
  %t37 = call ptr @__alloc(i64 16, i32 1)
  %t38 = inttoptr i64 23 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = getelementptr ptr, ptr %t37, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t40
  %t41 = getelementptr ptr, ptr %t34, i32 1
  store ptr %t37, ptr %t41
  %t42 = getelementptr ptr, ptr %t31, i32 1
  store ptr %t34, ptr %t42
  %t43 = call ptr @v_unwrap(ptr %t31)
  %t44 = call ptr @__concat(ptr %t30, ptr %t43)
  %t45 = getelementptr ptr, ptr %t44, i32 0
  %t46 = load ptr, ptr %t45
  %t47 = ptrtoint ptr %t46 to i64
  switch i64 %t47, label %case.default.48 [ i64 3, label %case.arm.3.50 i64 4, label %case.arm.4.58 ]
case.arm.3.50:
  %t52 = getelementptr ptr, ptr %t44, i32 1
  %t53 = load ptr, ptr %t52
  call void @__inc_ref(ptr %t53)
  %t54 = call ptr @__alloc(i64 16, i32 1)
  %t55 = inttoptr i64 3 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  call void @__inc_ref(ptr %t53)
  %t57 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t53, ptr %t57
  br label %case.end.3.51
case.end.3.51:
  br label %case.join.49
case.arm.4.58:
  %t60 = getelementptr ptr, ptr %t44, i32 1
  %t61 = load ptr, ptr %t60
  call void @__inc_ref(ptr %t61)
  call void @__inc_ref(ptr %t61)
  %t62 = call ptr @__concat(ptr %t61, ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  %t63 = getelementptr ptr, ptr %t62, i32 0
  %t64 = load ptr, ptr %t63
  %t65 = ptrtoint ptr %t64 to i64
  switch i64 %t65, label %case.default.66 [ i64 3, label %case.arm.3.68 i64 4, label %case.arm.4.76 ]
case.arm.3.68:
  %t70 = getelementptr ptr, ptr %t62, i32 1
  %t71 = load ptr, ptr %t70
  call void @__inc_ref(ptr %t71)
  %t72 = call ptr @__alloc(i64 16, i32 1)
  %t73 = inttoptr i64 3 to ptr
  %t74 = getelementptr ptr, ptr %t72, i32 0
  store ptr %t73, ptr %t74
  call void @__inc_ref(ptr %t71)
  %t75 = getelementptr ptr, ptr %t72, i32 1
  store ptr %t71, ptr %t75
  br label %case.end.3.69
case.end.3.69:
  br label %case.join.67
case.arm.4.76:
  %t78 = getelementptr ptr, ptr %t62, i32 1
  %t79 = load ptr, ptr %t78
  call void @__inc_ref(ptr %t79)
  call void @__inc_ref(ptr %t79)
  %t80 = call ptr @__alloc(i64 16, i32 1)
  %t81 = inttoptr i64 22 to ptr
  %t82 = getelementptr ptr, ptr %t80, i32 0
  store ptr %t81, ptr %t82
  %t83 = call ptr @__alloc(i64 16, i32 1)
  %t84 = inttoptr i64 23 to ptr
  %t85 = getelementptr ptr, ptr %t83, i32 0
  store ptr %t84, ptr %t85
  %t86 = call ptr @__alloc(i64 16, i32 1)
  %t87 = inttoptr i64 22 to ptr
  %t88 = getelementptr ptr, ptr %t86, i32 0
  store ptr %t87, ptr %t88
  %t89 = getelementptr ptr, ptr %t86, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t89
  %t90 = getelementptr ptr, ptr %t83, i32 1
  store ptr %t86, ptr %t90
  %t91 = getelementptr ptr, ptr %t80, i32 1
  store ptr %t83, ptr %t91
  %t92 = call ptr @v_unwrap(ptr %t80)
  %t93 = call ptr @__concat(ptr %t79, ptr %t92)
  %t94 = getelementptr ptr, ptr %t93, i32 0
  %t95 = load ptr, ptr %t94
  %t96 = ptrtoint ptr %t95 to i64
  switch i64 %t96, label %case.default.97 [ i64 3, label %case.arm.3.99 i64 4, label %case.arm.4.107 ]
case.arm.3.99:
  %t101 = getelementptr ptr, ptr %t93, i32 1
  %t102 = load ptr, ptr %t101
  call void @__inc_ref(ptr %t102)
  %t103 = call ptr @__alloc(i64 16, i32 1)
  %t104 = inttoptr i64 3 to ptr
  %t105 = getelementptr ptr, ptr %t103, i32 0
  store ptr %t104, ptr %t105
  call void @__inc_ref(ptr %t102)
  %t106 = getelementptr ptr, ptr %t103, i32 1
  store ptr %t102, ptr %t106
  br label %case.end.3.100
case.end.3.100:
  br label %case.join.98
case.arm.4.107:
  %t109 = getelementptr ptr, ptr %t93, i32 1
  %t110 = load ptr, ptr %t109
  call void @__inc_ref(ptr %t110)
  call void @__inc_ref(ptr %t110)
  %t111 = call ptr @__concat(ptr %t110, ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  %t112 = getelementptr ptr, ptr %t111, i32 0
  %t113 = load ptr, ptr %t112
  %t114 = ptrtoint ptr %t113 to i64
  switch i64 %t114, label %case.default.115 [ i64 3, label %case.arm.3.117 i64 4, label %case.arm.4.125 ]
case.arm.3.117:
  %t119 = getelementptr ptr, ptr %t111, i32 1
  %t120 = load ptr, ptr %t119
  call void @__inc_ref(ptr %t120)
  %t121 = call ptr @__alloc(i64 16, i32 1)
  %t122 = inttoptr i64 3 to ptr
  %t123 = getelementptr ptr, ptr %t121, i32 0
  store ptr %t122, ptr %t123
  call void @__inc_ref(ptr %t120)
  %t124 = getelementptr ptr, ptr %t121, i32 1
  store ptr %t120, ptr %t124
  br label %case.end.3.118
case.end.3.118:
  br label %case.join.116
case.arm.4.125:
  %t127 = getelementptr ptr, ptr %t111, i32 1
  %t128 = load ptr, ptr %t127
  call void @__inc_ref(ptr %t128)
  call void @__inc_ref(ptr %t128)
  %t129 = call ptr @__alloc(i64 16, i32 1)
  %t130 = inttoptr i64 22 to ptr
  %t131 = getelementptr ptr, ptr %t129, i32 0
  store ptr %t130, ptr %t131
  %t132 = call ptr @__alloc(i64 16, i32 1)
  %t133 = inttoptr i64 23 to ptr
  %t134 = getelementptr ptr, ptr %t132, i32 0
  store ptr %t133, ptr %t134
  %t135 = call ptr @__alloc(i64 16, i32 1)
  %t136 = inttoptr i64 23 to ptr
  %t137 = getelementptr ptr, ptr %t135, i32 0
  store ptr %t136, ptr %t137
  %t138 = getelementptr ptr, ptr %t135, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t138
  %t139 = getelementptr ptr, ptr %t132, i32 1
  store ptr %t135, ptr %t139
  %t140 = getelementptr ptr, ptr %t129, i32 1
  store ptr %t132, ptr %t140
  %t141 = call ptr @v_unwrap(ptr %t129)
  %t142 = call ptr @__concat(ptr %t128, ptr %t141)
  %t143 = getelementptr ptr, ptr %t142, i32 0
  %t144 = load ptr, ptr %t143
  %t145 = ptrtoint ptr %t144 to i64
  switch i64 %t145, label %case.default.146 [ i64 3, label %case.arm.3.148 i64 4, label %case.arm.4.156 ]
case.arm.3.148:
  %t150 = getelementptr ptr, ptr %t142, i32 1
  %t151 = load ptr, ptr %t150
  call void @__inc_ref(ptr %t151)
  %t152 = call ptr @__alloc(i64 16, i32 1)
  %t153 = inttoptr i64 3 to ptr
  %t154 = getelementptr ptr, ptr %t152, i32 0
  store ptr %t153, ptr %t154
  call void @__inc_ref(ptr %t151)
  %t155 = getelementptr ptr, ptr %t152, i32 1
  store ptr %t151, ptr %t155
  br label %case.end.3.149
case.end.3.149:
  br label %case.join.147
case.arm.4.156:
  %t158 = getelementptr ptr, ptr %t142, i32 1
  %t159 = load ptr, ptr %t158
  call void @__inc_ref(ptr %t159)
  call void @__inc_ref(ptr %t159)
  %t160 = call ptr @__concat(ptr %t159, ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  %t161 = getelementptr ptr, ptr %t160, i32 0
  %t162 = load ptr, ptr %t161
  %t163 = ptrtoint ptr %t162 to i64
  switch i64 %t163, label %case.default.164 [ i64 3, label %case.arm.3.166 i64 4, label %case.arm.4.174 ]
case.arm.3.166:
  %t168 = getelementptr ptr, ptr %t160, i32 1
  %t169 = load ptr, ptr %t168
  call void @__inc_ref(ptr %t169)
  %t170 = call ptr @__alloc(i64 16, i32 1)
  %t171 = inttoptr i64 3 to ptr
  %t172 = getelementptr ptr, ptr %t170, i32 0
  store ptr %t171, ptr %t172
  call void @__inc_ref(ptr %t169)
  %t173 = getelementptr ptr, ptr %t170, i32 1
  store ptr %t169, ptr %t173
  br label %case.end.3.167
case.end.3.167:
  br label %case.join.165
case.arm.4.174:
  %t176 = getelementptr ptr, ptr %t160, i32 1
  %t177 = load ptr, ptr %t176
  call void @__inc_ref(ptr %t177)
  call void @__inc_ref(ptr %t177)
  %t178 = call ptr @__alloc(i64 16, i32 1)
  %t179 = inttoptr i64 23 to ptr
  %t180 = getelementptr ptr, ptr %t178, i32 0
  store ptr %t179, ptr %t180
  %t181 = call ptr @__alloc(i64 16, i32 1)
  %t182 = inttoptr i64 22 to ptr
  %t183 = getelementptr ptr, ptr %t181, i32 0
  store ptr %t182, ptr %t183
  %t184 = call ptr @__alloc(i64 16, i32 1)
  %t185 = inttoptr i64 22 to ptr
  %t186 = getelementptr ptr, ptr %t184, i32 0
  store ptr %t185, ptr %t186
  %t187 = getelementptr ptr, ptr %t184, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.5, i64 12), ptr %t187
  %t188 = getelementptr ptr, ptr %t181, i32 1
  store ptr %t184, ptr %t188
  %t189 = getelementptr ptr, ptr %t178, i32 1
  store ptr %t181, ptr %t189
  %t190 = call ptr @v_unwrap(ptr %t178)
  %t191 = call ptr @__concat(ptr %t177, ptr %t190)
  %t192 = getelementptr ptr, ptr %t191, i32 0
  %t193 = load ptr, ptr %t192
  %t194 = ptrtoint ptr %t193 to i64
  switch i64 %t194, label %case.default.195 [ i64 3, label %case.arm.3.197 i64 4, label %case.arm.4.205 ]
case.arm.3.197:
  %t199 = getelementptr ptr, ptr %t191, i32 1
  %t200 = load ptr, ptr %t199
  call void @__inc_ref(ptr %t200)
  %t201 = call ptr @__alloc(i64 16, i32 1)
  %t202 = inttoptr i64 3 to ptr
  %t203 = getelementptr ptr, ptr %t201, i32 0
  store ptr %t202, ptr %t203
  call void @__inc_ref(ptr %t200)
  %t204 = getelementptr ptr, ptr %t201, i32 1
  store ptr %t200, ptr %t204
  br label %case.end.3.198
case.end.3.198:
  br label %case.join.196
case.arm.4.205:
  %t207 = getelementptr ptr, ptr %t191, i32 1
  %t208 = load ptr, ptr %t207
  call void @__inc_ref(ptr %t208)
  call void @__inc_ref(ptr %t208)
  %t209 = call ptr @__concat(ptr %t208, ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  %t210 = getelementptr ptr, ptr %t209, i32 0
  %t211 = load ptr, ptr %t210
  %t212 = ptrtoint ptr %t211 to i64
  switch i64 %t212, label %case.default.213 [ i64 3, label %case.arm.3.215 i64 4, label %case.arm.4.223 ]
case.arm.3.215:
  %t217 = getelementptr ptr, ptr %t209, i32 1
  %t218 = load ptr, ptr %t217
  call void @__inc_ref(ptr %t218)
  %t219 = call ptr @__alloc(i64 16, i32 1)
  %t220 = inttoptr i64 3 to ptr
  %t221 = getelementptr ptr, ptr %t219, i32 0
  store ptr %t220, ptr %t221
  call void @__inc_ref(ptr %t218)
  %t222 = getelementptr ptr, ptr %t219, i32 1
  store ptr %t218, ptr %t222
  br label %case.end.3.216
case.end.3.216:
  br label %case.join.214
case.arm.4.223:
  %t225 = getelementptr ptr, ptr %t209, i32 1
  %t226 = load ptr, ptr %t225
  call void @__inc_ref(ptr %t226)
  call void @__inc_ref(ptr %t226)
  %t227 = call ptr @__alloc(i64 16, i32 1)
  %t228 = inttoptr i64 23 to ptr
  %t229 = getelementptr ptr, ptr %t227, i32 0
  store ptr %t228, ptr %t229
  %t230 = call ptr @__alloc(i64 16, i32 1)
  %t231 = inttoptr i64 22 to ptr
  %t232 = getelementptr ptr, ptr %t230, i32 0
  store ptr %t231, ptr %t232
  %t233 = call ptr @__alloc(i64 16, i32 1)
  %t234 = inttoptr i64 23 to ptr
  %t235 = getelementptr ptr, ptr %t233, i32 0
  store ptr %t234, ptr %t235
  %t236 = getelementptr ptr, ptr %t233, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.6, i64 12), ptr %t236
  %t237 = getelementptr ptr, ptr %t230, i32 1
  store ptr %t233, ptr %t237
  %t238 = getelementptr ptr, ptr %t227, i32 1
  store ptr %t230, ptr %t238
  %t239 = call ptr @v_unwrap(ptr %t227)
  %t240 = call ptr @__concat(ptr %t226, ptr %t239)
  %t241 = getelementptr ptr, ptr %t240, i32 0
  %t242 = load ptr, ptr %t241
  %t243 = ptrtoint ptr %t242 to i64
  switch i64 %t243, label %case.default.244 [ i64 3, label %case.arm.3.246 i64 4, label %case.arm.4.254 ]
case.arm.3.246:
  %t248 = getelementptr ptr, ptr %t240, i32 1
  %t249 = load ptr, ptr %t248
  call void @__inc_ref(ptr %t249)
  %t250 = call ptr @__alloc(i64 16, i32 1)
  %t251 = inttoptr i64 3 to ptr
  %t252 = getelementptr ptr, ptr %t250, i32 0
  store ptr %t251, ptr %t252
  call void @__inc_ref(ptr %t249)
  %t253 = getelementptr ptr, ptr %t250, i32 1
  store ptr %t249, ptr %t253
  br label %case.end.3.247
case.end.3.247:
  br label %case.join.245
case.arm.4.254:
  %t256 = getelementptr ptr, ptr %t240, i32 1
  %t257 = load ptr, ptr %t256
  call void @__inc_ref(ptr %t257)
  call void @__inc_ref(ptr %t257)
  %t258 = call ptr @__concat(ptr %t257, ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  %t259 = getelementptr ptr, ptr %t258, i32 0
  %t260 = load ptr, ptr %t259
  %t261 = ptrtoint ptr %t260 to i64
  switch i64 %t261, label %case.default.262 [ i64 3, label %case.arm.3.264 i64 4, label %case.arm.4.272 ]
case.arm.3.264:
  %t266 = getelementptr ptr, ptr %t258, i32 1
  %t267 = load ptr, ptr %t266
  call void @__inc_ref(ptr %t267)
  %t268 = call ptr @__alloc(i64 16, i32 1)
  %t269 = inttoptr i64 3 to ptr
  %t270 = getelementptr ptr, ptr %t268, i32 0
  store ptr %t269, ptr %t270
  call void @__inc_ref(ptr %t267)
  %t271 = getelementptr ptr, ptr %t268, i32 1
  store ptr %t267, ptr %t271
  br label %case.end.3.265
case.end.3.265:
  br label %case.join.263
case.arm.4.272:
  %t274 = getelementptr ptr, ptr %t258, i32 1
  %t275 = load ptr, ptr %t274
  call void @__inc_ref(ptr %t275)
  call void @__inc_ref(ptr %t275)
  %t276 = call ptr @__alloc(i64 16, i32 1)
  %t277 = inttoptr i64 23 to ptr
  %t278 = getelementptr ptr, ptr %t276, i32 0
  store ptr %t277, ptr %t278
  %t279 = call ptr @__alloc(i64 16, i32 1)
  %t280 = inttoptr i64 23 to ptr
  %t281 = getelementptr ptr, ptr %t279, i32 0
  store ptr %t280, ptr %t281
  %t282 = call ptr @__alloc(i64 16, i32 1)
  %t283 = inttoptr i64 22 to ptr
  %t284 = getelementptr ptr, ptr %t282, i32 0
  store ptr %t283, ptr %t284
  %t285 = getelementptr ptr, ptr %t282, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.7, i64 12), ptr %t285
  %t286 = getelementptr ptr, ptr %t279, i32 1
  store ptr %t282, ptr %t286
  %t287 = getelementptr ptr, ptr %t276, i32 1
  store ptr %t279, ptr %t287
  %t288 = call ptr @v_unwrap(ptr %t276)
  %t289 = call ptr @__concat(ptr %t275, ptr %t288)
  %t290 = getelementptr ptr, ptr %t289, i32 0
  %t291 = load ptr, ptr %t290
  %t292 = ptrtoint ptr %t291 to i64
  switch i64 %t292, label %case.default.293 [ i64 3, label %case.arm.3.295 i64 4, label %case.arm.4.303 ]
case.arm.3.295:
  %t297 = getelementptr ptr, ptr %t289, i32 1
  %t298 = load ptr, ptr %t297
  call void @__inc_ref(ptr %t298)
  %t299 = call ptr @__alloc(i64 16, i32 1)
  %t300 = inttoptr i64 3 to ptr
  %t301 = getelementptr ptr, ptr %t299, i32 0
  store ptr %t300, ptr %t301
  call void @__inc_ref(ptr %t298)
  %t302 = getelementptr ptr, ptr %t299, i32 1
  store ptr %t298, ptr %t302
  br label %case.end.3.296
case.end.3.296:
  br label %case.join.294
case.arm.4.303:
  %t305 = getelementptr ptr, ptr %t289, i32 1
  %t306 = load ptr, ptr %t305
  call void @__inc_ref(ptr %t306)
  call void @__inc_ref(ptr %t306)
  %t307 = call ptr @__concat(ptr %t306, ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  %t308 = getelementptr ptr, ptr %t307, i32 0
  %t309 = load ptr, ptr %t308
  %t310 = ptrtoint ptr %t309 to i64
  switch i64 %t310, label %case.default.311 [ i64 3, label %case.arm.3.313 i64 4, label %case.arm.4.321 ]
case.arm.3.313:
  %t315 = getelementptr ptr, ptr %t307, i32 1
  %t316 = load ptr, ptr %t315
  call void @__inc_ref(ptr %t316)
  %t317 = call ptr @__alloc(i64 16, i32 1)
  %t318 = inttoptr i64 3 to ptr
  %t319 = getelementptr ptr, ptr %t317, i32 0
  store ptr %t318, ptr %t319
  call void @__inc_ref(ptr %t316)
  %t320 = getelementptr ptr, ptr %t317, i32 1
  store ptr %t316, ptr %t320
  br label %case.end.3.314
case.end.3.314:
  br label %case.join.312
case.arm.4.321:
  %t323 = getelementptr ptr, ptr %t307, i32 1
  %t324 = load ptr, ptr %t323
  call void @__inc_ref(ptr %t324)
  call void @__inc_ref(ptr %t324)
  %t325 = call ptr @__alloc(i64 16, i32 1)
  %t326 = inttoptr i64 23 to ptr
  %t327 = getelementptr ptr, ptr %t325, i32 0
  store ptr %t326, ptr %t327
  %t328 = call ptr @__alloc(i64 16, i32 1)
  %t329 = inttoptr i64 23 to ptr
  %t330 = getelementptr ptr, ptr %t328, i32 0
  store ptr %t329, ptr %t330
  %t331 = call ptr @__alloc(i64 16, i32 1)
  %t332 = inttoptr i64 23 to ptr
  %t333 = getelementptr ptr, ptr %t331, i32 0
  store ptr %t332, ptr %t333
  %t334 = getelementptr ptr, ptr %t331, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.8, i64 12), ptr %t334
  %t335 = getelementptr ptr, ptr %t328, i32 1
  store ptr %t331, ptr %t335
  %t336 = getelementptr ptr, ptr %t325, i32 1
  store ptr %t328, ptr %t336
  %t337 = call ptr @v_unwrap(ptr %t325)
  %t338 = call ptr @__concat(ptr %t324, ptr %t337)
  br label %case.end.4.322
case.end.4.322:
  br label %case.join.312
case.default.311:
  unreachable
case.join.312:
  %t339 = phi ptr [%t317, %case.end.3.314], [%t338, %case.end.4.322]
  call void @__free_recursive(ptr %t307)
  br label %case.end.4.304
case.end.4.304:
  br label %case.join.294
case.default.293:
  unreachable
case.join.294:
  %t340 = phi ptr [%t299, %case.end.3.296], [%t339, %case.end.4.304]
  call void @__free_recursive(ptr %t289)
  br label %case.end.4.273
case.end.4.273:
  br label %case.join.263
case.default.262:
  unreachable
case.join.263:
  %t341 = phi ptr [%t268, %case.end.3.265], [%t340, %case.end.4.273]
  call void @__free_recursive(ptr %t258)
  br label %case.end.4.255
case.end.4.255:
  br label %case.join.245
case.default.244:
  unreachable
case.join.245:
  %t342 = phi ptr [%t250, %case.end.3.247], [%t341, %case.end.4.255]
  call void @__free_recursive(ptr %t240)
  br label %case.end.4.224
case.end.4.224:
  br label %case.join.214
case.default.213:
  unreachable
case.join.214:
  %t343 = phi ptr [%t219, %case.end.3.216], [%t342, %case.end.4.224]
  call void @__free_recursive(ptr %t209)
  br label %case.end.4.206
case.end.4.206:
  br label %case.join.196
case.default.195:
  unreachable
case.join.196:
  %t344 = phi ptr [%t201, %case.end.3.198], [%t343, %case.end.4.206]
  call void @__free_recursive(ptr %t191)
  br label %case.end.4.175
case.end.4.175:
  br label %case.join.165
case.default.164:
  unreachable
case.join.165:
  %t345 = phi ptr [%t170, %case.end.3.167], [%t344, %case.end.4.175]
  call void @__free_recursive(ptr %t160)
  br label %case.end.4.157
case.end.4.157:
  br label %case.join.147
case.default.146:
  unreachable
case.join.147:
  %t346 = phi ptr [%t152, %case.end.3.149], [%t345, %case.end.4.157]
  call void @__free_recursive(ptr %t142)
  br label %case.end.4.126
case.end.4.126:
  br label %case.join.116
case.default.115:
  unreachable
case.join.116:
  %t347 = phi ptr [%t121, %case.end.3.118], [%t346, %case.end.4.126]
  call void @__free_recursive(ptr %t111)
  br label %case.end.4.108
case.end.4.108:
  br label %case.join.98
case.default.97:
  unreachable
case.join.98:
  %t348 = phi ptr [%t103, %case.end.3.100], [%t347, %case.end.4.108]
  call void @__free_recursive(ptr %t93)
  br label %case.end.4.77
case.end.4.77:
  br label %case.join.67
case.default.66:
  unreachable
case.join.67:
  %t349 = phi ptr [%t72, %case.end.3.69], [%t348, %case.end.4.77]
  call void @__free_recursive(ptr %t62)
  br label %case.end.4.59
case.end.4.59:
  br label %case.join.49
case.default.48:
  unreachable
case.join.49:
  %t350 = phi ptr [%t54, %case.end.3.51], [%t349, %case.end.4.59]
  call void @__free_recursive(ptr %t44)
  br label %case.end.4.28
case.end.4.28:
  br label %case.join.18
case.default.17:
  unreachable
case.join.18:
  %t351 = phi ptr [%t23, %case.end.3.20], [%t350, %case.end.4.28]
  call void @__free_recursive(ptr %t13)
  %t352 = call ptr @v__let_15(ptr %t351)
  ret ptr %t352
}

define internal ptr @v__let_15(ptr %v_res) {
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
  store ptr getelementptr inbounds (i8, ptr @.str.9, i64 12), ptr %t10
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

define i32 @main(i32 %argc, ptr %argv) {
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
