; External C declarations
declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare ptr @memcpy(ptr, ptr, i64)
declare i64 @write(i32, ptr, i64)
declare i32 @memcmp(ptr, ptr, i64)


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
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [0 x i8]} { i32 0, i32 0, i32 0, i32 0, i32 0, [0 x i8] zeroinitializer }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"T" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"F" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"abc" }
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"a" }
@.str.6 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"ab" }
@.str.7 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"abd" }
@.str.8 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 2, [4 x i8] c"\F0\9F\94\A5" }

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


define internal ptr @__eqString(ptr %a, ptr %b) {
  %ba = load i32, ptr %a
  %bb = load i32, ptr %b
  %len_eq = icmp eq i32 %ba, %bb
  br i1 %len_eq, label %cmp, label %ne
cmp:
  %a_payload = getelementptr i8, ptr %a, i64 8
  %b_payload = getelementptr i8, ptr %b, i64 8
  %ba64 = zext i32 %ba to i64
  %r = call i32 @memcmp(ptr %a_payload, ptr %b_payload, i64 %ba64)
  %bytes_eq = icmp eq i32 %r, 0
  br i1 %bytes_eq, label %eq, label %ne
eq:
  %tag_t = inttoptr i64 1 to ptr
  %box_t = call ptr @__alloc(i64 8, i32 0)
  store ptr %tag_t, ptr %box_t
  br label %done
ne:
  %tag_f = inttoptr i64 2 to ptr
  %box_f = call ptr @__alloc(i64 8, i32 0)
  store ptr %tag_f, ptr %box_f
  br label %done
done:
  %result = phi ptr [ %box_t, %eq ], [ %box_f, %ne ]
  call void @__free_recursive(ptr %a)
  call void @__free_recursive(ptr %b)
  ret ptr %result
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
  %v__inl4_scrut.jslot = alloca ptr
  %t2 = call ptr @__eqString(ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  %t3 = getelementptr ptr, ptr %t2, i32 0
  %t4 = load ptr, ptr %t3
  %t5 = ptrtoint ptr %t4 to i64
  switch i64 %t5, label %case.default.6 [ i64 1, label %case.arm.1.8 i64 2, label %case.arm.2.10 ]
case.arm.1.8:
  br label %case.end.1.9
case.end.1.9:
  br label %case.join.7
case.arm.2.10:
  br label %case.end.2.11
case.end.2.11:
  br label %case.join.7
case.default.6:
  unreachable
case.join.7:
  %t12 = phi ptr [ getelementptr inbounds (i8, ptr @.str.2, i64 12), %case.end.1.9 ], [ getelementptr inbounds (i8, ptr @.str.3, i64 12), %case.end.2.11 ]
  call void @__free_recursive(ptr %t2)
  %t13 = call ptr @__eqString(ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  %t14 = getelementptr ptr, ptr %t13, i32 0
  %t15 = load ptr, ptr %t14
  %t16 = ptrtoint ptr %t15 to i64
  switch i64 %t16, label %case.default.17 [ i64 1, label %case.arm.1.19 i64 2, label %case.arm.2.21 ]
case.arm.1.19:
  br label %case.end.1.20
case.end.1.20:
  br label %case.join.18
case.arm.2.21:
  br label %case.end.2.22
case.end.2.22:
  br label %case.join.18
case.default.17:
  unreachable
case.join.18:
  %t23 = phi ptr [ getelementptr inbounds (i8, ptr @.str.2, i64 12), %case.end.1.20 ], [ getelementptr inbounds (i8, ptr @.str.3, i64 12), %case.end.2.22 ]
  call void @__free_recursive(ptr %t13)
  %t24 = call ptr @__concat(ptr %t12, ptr %t23)
  %t25 = getelementptr ptr, ptr %t24, i32 0
  %t26 = load ptr, ptr %t25
  %t27 = ptrtoint ptr %t26 to i64
  switch i64 %t27, label %join.case.default.28 [ i64 3, label %join.case.arm.3.29 i64 4, label %join.case.arm.4.43 ]
join.case.arm.3.29:
  %t30 = call ptr @__alloc(i64 24, i32 2)
  %t31 = inttoptr i64 7 to ptr
  %t32 = getelementptr ptr, ptr %t30, i32 0
  store ptr %t31, ptr %t32
  %t33 = getelementptr ptr, ptr %t30, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t33
  %t34 = call ptr @__alloc(i64 16, i32 1)
  %t35 = inttoptr i64 5 to ptr
  %t36 = getelementptr ptr, ptr %t34, i32 0
  store ptr %t35, ptr %t36
  %t37 = call ptr @__alloc(i64 8, i32 0)
  %t38 = inttoptr i64 0 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = getelementptr ptr, ptr %t34, i32 1
  store ptr %t37, ptr %t40
  %t41 = getelementptr ptr, ptr %t30, i32 2
  store ptr %t34, ptr %t41
  call void @__free_recursive(ptr %t24)
  br label %join.val.42
join.val.42:
  br label %join.after.1
join.case.arm.4.43:
  %t44 = getelementptr ptr, ptr %t24, i32 1
  %t45 = load ptr, ptr %t44
  call void @__inc_ref(ptr %t45)
  call void @__inc_ref(ptr %t45)
  %t46 = call ptr @__eqString(ptr getelementptr inbounds (i8, ptr @.str.5, i64 12), ptr getelementptr inbounds (i8, ptr @.str.6, i64 12))
  %t47 = getelementptr ptr, ptr %t46, i32 0
  %t48 = load ptr, ptr %t47
  %t49 = ptrtoint ptr %t48 to i64
  switch i64 %t49, label %case.default.50 [ i64 1, label %case.arm.1.52 i64 2, label %case.arm.2.54 ]
case.arm.1.52:
  br label %case.end.1.53
case.end.1.53:
  br label %case.join.51
case.arm.2.54:
  br label %case.end.2.55
case.end.2.55:
  br label %case.join.51
case.default.50:
  unreachable
case.join.51:
  %t56 = phi ptr [ getelementptr inbounds (i8, ptr @.str.2, i64 12), %case.end.1.53 ], [ getelementptr inbounds (i8, ptr @.str.3, i64 12), %case.end.2.55 ]
  call void @__free_recursive(ptr %t46)
  %t57 = call ptr @__concat(ptr %t45, ptr %t56)
  %t58 = getelementptr ptr, ptr %t57, i32 0
  %t59 = load ptr, ptr %t58
  %t60 = ptrtoint ptr %t59 to i64
  switch i64 %t60, label %case.default.61 [ i64 3, label %case.arm.3.63 i64 4, label %case.arm.4.71 ]
case.arm.3.63:
  %t65 = getelementptr ptr, ptr %t57, i32 1
  %t66 = load ptr, ptr %t65
  call void @__inc_ref(ptr %t66)
  %t67 = call ptr @__alloc(i64 16, i32 1)
  %t68 = inttoptr i64 3 to ptr
  %t69 = getelementptr ptr, ptr %t67, i32 0
  store ptr %t68, ptr %t69
  call void @__inc_ref(ptr %t66)
  %t70 = getelementptr ptr, ptr %t67, i32 1
  store ptr %t66, ptr %t70
  br label %case.end.3.64
case.end.3.64:
  br label %case.join.62
case.arm.4.71:
  %t73 = getelementptr ptr, ptr %t57, i32 1
  %t74 = load ptr, ptr %t73
  call void @__inc_ref(ptr %t74)
  call void @__inc_ref(ptr %t74)
  %t75 = call ptr @__eqString(ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr getelementptr inbounds (i8, ptr @.str.7, i64 12))
  %t76 = getelementptr ptr, ptr %t75, i32 0
  %t77 = load ptr, ptr %t76
  %t78 = ptrtoint ptr %t77 to i64
  switch i64 %t78, label %case.default.79 [ i64 1, label %case.arm.1.81 i64 2, label %case.arm.2.83 ]
case.arm.1.81:
  br label %case.end.1.82
case.end.1.82:
  br label %case.join.80
case.arm.2.83:
  br label %case.end.2.84
case.end.2.84:
  br label %case.join.80
case.default.79:
  unreachable
case.join.80:
  %t85 = phi ptr [ getelementptr inbounds (i8, ptr @.str.2, i64 12), %case.end.1.82 ], [ getelementptr inbounds (i8, ptr @.str.3, i64 12), %case.end.2.84 ]
  call void @__free_recursive(ptr %t75)
  %t86 = call ptr @__concat(ptr %t74, ptr %t85)
  %t87 = getelementptr ptr, ptr %t86, i32 0
  %t88 = load ptr, ptr %t87
  %t89 = ptrtoint ptr %t88 to i64
  switch i64 %t89, label %case.default.90 [ i64 3, label %case.arm.3.92 i64 4, label %case.arm.4.100 ]
case.arm.3.92:
  %t94 = getelementptr ptr, ptr %t86, i32 1
  %t95 = load ptr, ptr %t94
  call void @__inc_ref(ptr %t95)
  %t96 = call ptr @__alloc(i64 16, i32 1)
  %t97 = inttoptr i64 3 to ptr
  %t98 = getelementptr ptr, ptr %t96, i32 0
  store ptr %t97, ptr %t98
  call void @__inc_ref(ptr %t95)
  %t99 = getelementptr ptr, ptr %t96, i32 1
  store ptr %t95, ptr %t99
  br label %case.end.3.93
case.end.3.93:
  br label %case.join.91
case.arm.4.100:
  %t102 = getelementptr ptr, ptr %t86, i32 1
  %t103 = load ptr, ptr %t102
  call void @__inc_ref(ptr %t103)
  call void @__inc_ref(ptr %t103)
  %t104 = call ptr @__eqString(ptr getelementptr inbounds (i8, ptr @.str.8, i64 12), ptr getelementptr inbounds (i8, ptr @.str.8, i64 12))
  %t105 = getelementptr ptr, ptr %t104, i32 0
  %t106 = load ptr, ptr %t105
  %t107 = ptrtoint ptr %t106 to i64
  switch i64 %t107, label %case.default.108 [ i64 1, label %case.arm.1.110 i64 2, label %case.arm.2.112 ]
case.arm.1.110:
  br label %case.end.1.111
case.end.1.111:
  br label %case.join.109
case.arm.2.112:
  br label %case.end.2.113
case.end.2.113:
  br label %case.join.109
case.default.108:
  unreachable
case.join.109:
  %t114 = phi ptr [ getelementptr inbounds (i8, ptr @.str.2, i64 12), %case.end.1.111 ], [ getelementptr inbounds (i8, ptr @.str.3, i64 12), %case.end.2.113 ]
  call void @__free_recursive(ptr %t104)
  %t115 = call ptr @__concat(ptr %t103, ptr %t114)
  br label %case.end.4.101
case.end.4.101:
  br label %case.join.91
case.default.90:
  unreachable
case.join.91:
  %t116 = phi ptr [ %t96, %case.end.3.93 ], [ %t115, %case.end.4.101 ]
  call void @__free_recursive(ptr %t86)
  br label %case.end.4.72
case.end.4.72:
  br label %case.join.62
case.default.61:
  unreachable
case.join.62:
  %t117 = phi ptr [ %t67, %case.end.3.64 ], [ %t116, %case.end.4.72 ]
  call void @__free_recursive(ptr %t57)
  call void @__free_recursive(ptr %t24)
  store ptr %t117, ptr %v__inl4_scrut.jslot
  br label %join.0
join.case.default.28:
  unreachable
join.0:
  %t118 = load ptr, ptr %v__inl4_scrut.jslot
  %t119 = getelementptr ptr, ptr %t118, i32 0
  %t120 = load ptr, ptr %t119
  %t121 = ptrtoint ptr %t120 to i64
  switch i64 %t121, label %case.default.122 [ i64 3, label %case.arm.3.124 i64 4, label %case.arm.4.138 ]
case.arm.3.124:
  %t126 = call ptr @__alloc(i64 24, i32 2)
  %t127 = inttoptr i64 7 to ptr
  %t128 = getelementptr ptr, ptr %t126, i32 0
  store ptr %t127, ptr %t128
  %t129 = getelementptr ptr, ptr %t126, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t129
  %t130 = call ptr @__alloc(i64 16, i32 1)
  %t131 = inttoptr i64 5 to ptr
  %t132 = getelementptr ptr, ptr %t130, i32 0
  store ptr %t131, ptr %t132
  %t133 = call ptr @__alloc(i64 8, i32 0)
  %t134 = inttoptr i64 0 to ptr
  %t135 = getelementptr ptr, ptr %t133, i32 0
  store ptr %t134, ptr %t135
  %t136 = getelementptr ptr, ptr %t130, i32 1
  store ptr %t133, ptr %t136
  %t137 = getelementptr ptr, ptr %t126, i32 2
  store ptr %t130, ptr %t137
  br label %case.end.3.125
case.end.3.125:
  br label %case.join.123
case.arm.4.138:
  %t140 = call ptr @__alloc(i64 24, i32 2)
  %t141 = inttoptr i64 7 to ptr
  %t142 = getelementptr ptr, ptr %t140, i32 0
  store ptr %t141, ptr %t142
  %t143 = getelementptr ptr, ptr %t118, i32 1
  %t144 = load ptr, ptr %t143
  call void @__inc_ref(ptr %t144)
  %t145 = getelementptr ptr, ptr %t140, i32 1
  store ptr %t144, ptr %t145
  %t146 = call ptr @__alloc(i64 16, i32 1)
  %t147 = inttoptr i64 5 to ptr
  %t148 = getelementptr ptr, ptr %t146, i32 0
  store ptr %t147, ptr %t148
  %t149 = call ptr @__alloc(i64 8, i32 0)
  %t150 = inttoptr i64 0 to ptr
  %t151 = getelementptr ptr, ptr %t149, i32 0
  store ptr %t150, ptr %t151
  %t152 = getelementptr ptr, ptr %t146, i32 1
  store ptr %t149, ptr %t152
  %t153 = getelementptr ptr, ptr %t140, i32 2
  store ptr %t146, ptr %t153
  br label %case.end.4.139
case.end.4.139:
  br label %case.join.123
case.default.122:
  unreachable
case.join.123:
  %t154 = phi ptr [ %t126, %case.end.3.125 ], [ %t140, %case.end.4.139 ]
  call void @__free_recursive(ptr %t118)
  br label %join.end.155
join.end.155:
  br label %join.after.1
join.after.1:
  %t156 = phi ptr [ %t30, %join.val.42 ], [ %t154, %join.end.155 ]
  ret ptr %t156
}

define i32 @main(i32 %argc, ptr %argv) {
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
