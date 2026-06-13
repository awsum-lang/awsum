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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"red" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"green" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c" " }

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
  %v__inl8_scrut.jslot = alloca ptr
  %t2 = call ptr @__alloc(i64 16, i32 1)
  %t3 = inttoptr i64 27 to ptr
  %t4 = getelementptr ptr, ptr %t2, i32 0
  store ptr %t3, ptr %t4
  %t5 = call ptr @__alloc(i64 8, i32 0)
  %t6 = inttoptr i64 24 to ptr
  %t7 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t6, ptr %t7
  %t8 = getelementptr ptr, ptr %t2, i32 1
  store ptr %t5, ptr %t8
  %t9 = getelementptr ptr, ptr %t2, i32 1
  %t10 = load ptr, ptr %t9
  call void @__inc_ref(ptr %t10)
  %t11 = getelementptr ptr, ptr %t10, i32 0
  %t12 = load ptr, ptr %t11
  %t13 = ptrtoint ptr %t12 to i64
  switch i64 %t13, label %case.default.14 [ i64 24, label %case.arm.24.16 i64 25, label %case.arm.25.18 ]
case.arm.24.16:
  br label %case.end.24.17
case.end.24.17:
  br label %case.join.15
case.arm.25.18:
  br label %case.end.25.19
case.end.25.19:
  br label %case.join.15
case.default.14:
  unreachable
case.join.15:
  %t20 = phi ptr [ getelementptr inbounds (i8, ptr @.str.1, i64 12), %case.end.24.17 ], [ getelementptr inbounds (i8, ptr @.str.2, i64 12), %case.end.25.19 ]
  call void @__free_recursive(ptr %t10)
  call void @__free_recursive(ptr %t2)
  %t21 = call ptr @__concat(ptr %t20, ptr getelementptr inbounds (i8, ptr @.str.3, i64 12))
  %t22 = getelementptr ptr, ptr %t21, i32 0
  %t23 = load ptr, ptr %t22
  %t24 = ptrtoint ptr %t23 to i64
  switch i64 %t24, label %join.case.default.25 [ i64 3, label %join.case.arm.3.26 i64 4, label %join.case.arm.4.40 ]
join.case.arm.3.26:
  %t27 = call ptr @__alloc(i64 24, i32 2)
  %t28 = inttoptr i64 7 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  %t30 = getelementptr ptr, ptr %t27, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t30
  %t31 = call ptr @__alloc(i64 16, i32 1)
  %t32 = inttoptr i64 5 to ptr
  %t33 = getelementptr ptr, ptr %t31, i32 0
  store ptr %t32, ptr %t33
  %t34 = call ptr @__alloc(i64 8, i32 0)
  %t35 = inttoptr i64 0 to ptr
  %t36 = getelementptr ptr, ptr %t34, i32 0
  store ptr %t35, ptr %t36
  %t37 = getelementptr ptr, ptr %t31, i32 1
  store ptr %t34, ptr %t37
  %t38 = getelementptr ptr, ptr %t27, i32 2
  store ptr %t31, ptr %t38
  call void @__free_recursive(ptr %t21)
  br label %join.val.39
join.val.39:
  br label %join.after.1
join.case.arm.4.40:
  %t41 = getelementptr ptr, ptr %t21, i32 1
  %t42 = load ptr, ptr %t41
  call void @__inc_ref(ptr %t42)
  call void @__inc_ref(ptr %t42)
  %t43 = call ptr @__alloc(i64 16, i32 1)
  %t44 = inttoptr i64 28 to ptr
  %t45 = getelementptr ptr, ptr %t43, i32 0
  store ptr %t44, ptr %t45
  %t46 = call ptr @__alloc(i64 16, i32 1)
  %t47 = inttoptr i64 27 to ptr
  %t48 = getelementptr ptr, ptr %t46, i32 0
  store ptr %t47, ptr %t48
  %t49 = call ptr @__alloc(i64 8, i32 0)
  %t50 = inttoptr i64 25 to ptr
  %t51 = getelementptr ptr, ptr %t49, i32 0
  store ptr %t50, ptr %t51
  %t52 = getelementptr ptr, ptr %t46, i32 1
  store ptr %t49, ptr %t52
  %t53 = getelementptr ptr, ptr %t43, i32 1
  store ptr %t46, ptr %t53
  %t54 = getelementptr ptr, ptr %t43, i32 1
  %t55 = load ptr, ptr %t54
  call void @__inc_ref(ptr %t55)
  %t56 = getelementptr ptr, ptr %t55, i32 1
  %t57 = load ptr, ptr %t56
  call void @__inc_ref(ptr %t57)
  %t58 = getelementptr ptr, ptr %t57, i32 0
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
  %t67 = phi ptr [ getelementptr inbounds (i8, ptr @.str.1, i64 12), %case.end.24.64 ], [ getelementptr inbounds (i8, ptr @.str.2, i64 12), %case.end.25.66 ]
  call void @__free_recursive(ptr %t57)
  call void @__free_recursive(ptr %t55)
  call void @__free_recursive(ptr %t43)
  %t68 = call ptr @__concat(ptr %t42, ptr %t67)
  call void @__free_recursive(ptr %t21)
  store ptr %t68, ptr %v__inl8_scrut.jslot
  br label %join.0
join.case.default.25:
  unreachable
join.0:
  %t69 = load ptr, ptr %v__inl8_scrut.jslot
  %t70 = getelementptr ptr, ptr %t69, i32 0
  %t71 = load ptr, ptr %t70
  %t72 = ptrtoint ptr %t71 to i64
  switch i64 %t72, label %case.default.73 [ i64 3, label %case.arm.3.75 i64 4, label %case.arm.4.89 ]
case.arm.3.75:
  %t77 = call ptr @__alloc(i64 24, i32 2)
  %t78 = inttoptr i64 7 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t80
  %t81 = call ptr @__alloc(i64 16, i32 1)
  %t82 = inttoptr i64 5 to ptr
  %t83 = getelementptr ptr, ptr %t81, i32 0
  store ptr %t82, ptr %t83
  %t84 = call ptr @__alloc(i64 8, i32 0)
  %t85 = inttoptr i64 0 to ptr
  %t86 = getelementptr ptr, ptr %t84, i32 0
  store ptr %t85, ptr %t86
  %t87 = getelementptr ptr, ptr %t81, i32 1
  store ptr %t84, ptr %t87
  %t88 = getelementptr ptr, ptr %t77, i32 2
  store ptr %t81, ptr %t88
  br label %case.end.3.76
case.end.3.76:
  br label %case.join.74
case.arm.4.89:
  %t91 = call ptr @__alloc(i64 24, i32 2)
  %t92 = inttoptr i64 7 to ptr
  %t93 = getelementptr ptr, ptr %t91, i32 0
  store ptr %t92, ptr %t93
  %t94 = getelementptr ptr, ptr %t69, i32 1
  %t95 = load ptr, ptr %t94
  call void @__inc_ref(ptr %t95)
  %t96 = getelementptr ptr, ptr %t91, i32 1
  store ptr %t95, ptr %t96
  %t97 = call ptr @__alloc(i64 16, i32 1)
  %t98 = inttoptr i64 5 to ptr
  %t99 = getelementptr ptr, ptr %t97, i32 0
  store ptr %t98, ptr %t99
  %t100 = call ptr @__alloc(i64 8, i32 0)
  %t101 = inttoptr i64 0 to ptr
  %t102 = getelementptr ptr, ptr %t100, i32 0
  store ptr %t101, ptr %t102
  %t103 = getelementptr ptr, ptr %t97, i32 1
  store ptr %t100, ptr %t103
  %t104 = getelementptr ptr, ptr %t91, i32 2
  store ptr %t97, ptr %t104
  br label %case.end.4.90
case.end.4.90:
  br label %case.join.74
case.default.73:
  unreachable
case.join.74:
  %t105 = phi ptr [ %t77, %case.end.3.76 ], [ %t91, %case.end.4.90 ]
  call void @__free_recursive(ptr %t69)
  br label %join.end.106
join.end.106:
  br label %join.after.1
join.after.1:
  %t107 = phi ptr [ %t27, %join.val.39 ], [ %t105, %join.end.106 ]
  ret ptr %t107
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
