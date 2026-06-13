; External C declarations
declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare ptr @memcpy(ptr, ptr, i64)
declare i64 @write(i32, ptr, i64)
declare i32 @snprintf(ptr, i64, ptr, ...)
declare {i32, i1} @llvm.smul.with.overflow.i32(i32, i32)

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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"[" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c", " }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"]" }

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


define internal ptr @__mulInt32(ptr %pa, ptr %pb) {
  %a = load i32, ptr %pa
  %b = load i32, ptr %pb
  %res = call {i32, i1} @llvm.smul.with.overflow.i32(i32 %a, i32 %b)
  %prod = extractvalue {i32, i1} %res, 0
  %ovf = extractvalue {i32, i1} %res, 1
  br i1 %ovf, label %err, label %ok
err:
  %xor_ab = xor i32 %a, %b
  %same_sign = icmp sge i32 %xor_ab, 0
  %row_tag_idx = select i1 %same_sign, i64 882564211, i64 3768445577
  %inner = call ptr @__alloc(i64 8, i32 0)
  %inner_tag = inttoptr i64 0 to ptr
  store ptr %inner_tag, ptr %inner
  %row = call ptr @__alloc(i64 16, i32 1)
  %row_tag = inttoptr i64 %row_tag_idx to ptr
  store ptr %row_tag, ptr %row
  %row_f = getelementptr ptr, ptr %row, i32 1
  store ptr %inner, ptr %row_f
  %left = call ptr @__alloc(i64 16, i32 1)
  %left_tag = inttoptr i64 3 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %row, ptr %left_f
  br label %join
ok:
  %box = call ptr @__alloc(i64 4, i32 0)
  store i32 %prod, ptr %box
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
  %v__inl14_scrut.jslot = alloca ptr
  %t0 = call ptr @__alloc(i64 4, i32 0)
  store i32 5, ptr %t0
  call void @__inc_ref(ptr %t0)
  %t1 = call ptr @__alloc(i64 4, i32 0)
  store i32 2, ptr %t1
  %t2 = call ptr @__mulInt32(ptr %t0, ptr %t1)
  %t3 = getelementptr ptr, ptr %t2, i32 0
  %t4 = load ptr, ptr %t3
  %t5 = ptrtoint ptr %t4 to i64
  switch i64 %t5, label %case.default.6 [ i64 3, label %case.arm.3.8 i64 4, label %case.arm.4.15 ]
case.arm.3.8:
  %t10 = call ptr @__alloc(i64 24, i32 2)
  %t11 = inttoptr i64 15 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  call void @__inc_ref(ptr %t0)
  %t13 = getelementptr ptr, ptr %t10, i32 1
  store ptr %t0, ptr %t13
  call void @__inc_ref(ptr %t0)
  %t14 = getelementptr ptr, ptr %t10, i32 2
  store ptr %t0, ptr %t14
  br label %case.end.3.9
case.end.3.9:
  br label %case.join.7
case.arm.4.15:
  %t17 = getelementptr ptr, ptr %t2, i32 1
  %t18 = load ptr, ptr %t17
  call void @__inc_ref(ptr %t18)
  %t19 = call ptr @__alloc(i64 24, i32 2)
  %t20 = inttoptr i64 15 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  call void @__inc_ref(ptr %t0)
  %t22 = getelementptr ptr, ptr %t19, i32 1
  store ptr %t0, ptr %t22
  call void @__inc_ref(ptr %t18)
  %t23 = getelementptr ptr, ptr %t19, i32 2
  store ptr %t18, ptr %t23
  br label %case.end.4.16
case.end.4.16:
  br label %case.join.7
case.default.6:
  unreachable
case.join.7:
  %t24 = phi ptr [ %t10, %case.end.3.9 ], [ %t19, %case.end.4.16 ]
  call void @__free_recursive(ptr %t2)
  call void @__free_recursive(ptr %t0)
  %t27 = getelementptr ptr, ptr %t24, i32 1
  %t28 = load ptr, ptr %t27
  call void @__inc_ref(ptr %t28)
  %t29 = call ptr @__showInt32(ptr %t28)
  %t30 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t29)
  %t31 = getelementptr ptr, ptr %t30, i32 0
  %t32 = load ptr, ptr %t31
  %t33 = ptrtoint ptr %t32 to i64
  switch i64 %t33, label %join.case.default.34 [ i64 3, label %join.case.arm.3.35 i64 4, label %join.case.arm.4.49 ]
join.case.arm.3.35:
  %t36 = call ptr @__alloc(i64 24, i32 2)
  %t37 = inttoptr i64 7 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t36, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t39
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
  %t47 = getelementptr ptr, ptr %t36, i32 2
  store ptr %t40, ptr %t47
  call void @__free_recursive(ptr %t30)
  br label %join.val.48
join.val.48:
  br label %join.after.26
join.case.arm.4.49:
  %t50 = getelementptr ptr, ptr %t30, i32 1
  %t51 = load ptr, ptr %t50
  call void @__inc_ref(ptr %t51)
  call void @__inc_ref(ptr %t51)
  %t52 = call ptr @__concat(ptr %t51, ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
  %t53 = getelementptr ptr, ptr %t52, i32 0
  %t54 = load ptr, ptr %t53
  %t55 = ptrtoint ptr %t54 to i64
  switch i64 %t55, label %case.default.56 [ i64 3, label %case.arm.3.58 i64 4, label %case.arm.4.66 ]
case.arm.3.58:
  %t60 = getelementptr ptr, ptr %t52, i32 1
  %t61 = load ptr, ptr %t60
  call void @__inc_ref(ptr %t61)
  %t62 = call ptr @__alloc(i64 16, i32 1)
  %t63 = inttoptr i64 3 to ptr
  %t64 = getelementptr ptr, ptr %t62, i32 0
  store ptr %t63, ptr %t64
  call void @__inc_ref(ptr %t61)
  %t65 = getelementptr ptr, ptr %t62, i32 1
  store ptr %t61, ptr %t65
  br label %case.end.3.59
case.end.3.59:
  br label %case.join.57
case.arm.4.66:
  %t68 = getelementptr ptr, ptr %t52, i32 1
  %t69 = load ptr, ptr %t68
  call void @__inc_ref(ptr %t69)
  call void @__inc_ref(ptr %t69)
  %t70 = getelementptr ptr, ptr %t24, i32 2
  %t71 = load ptr, ptr %t70
  call void @__inc_ref(ptr %t71)
  %t72 = call ptr @__showInt32(ptr %t71)
  %t73 = call ptr @__concat(ptr %t69, ptr %t72)
  %t74 = getelementptr ptr, ptr %t73, i32 0
  %t75 = load ptr, ptr %t74
  %t76 = ptrtoint ptr %t75 to i64
  switch i64 %t76, label %case.default.77 [ i64 3, label %case.arm.3.79 i64 4, label %case.arm.4.87 ]
case.arm.3.79:
  %t81 = getelementptr ptr, ptr %t73, i32 1
  %t82 = load ptr, ptr %t81
  call void @__inc_ref(ptr %t82)
  %t83 = call ptr @__alloc(i64 16, i32 1)
  %t84 = inttoptr i64 3 to ptr
  %t85 = getelementptr ptr, ptr %t83, i32 0
  store ptr %t84, ptr %t85
  call void @__inc_ref(ptr %t82)
  %t86 = getelementptr ptr, ptr %t83, i32 1
  store ptr %t82, ptr %t86
  br label %case.end.3.80
case.end.3.80:
  br label %case.join.78
case.arm.4.87:
  %t89 = getelementptr ptr, ptr %t73, i32 1
  %t90 = load ptr, ptr %t89
  call void @__inc_ref(ptr %t90)
  call void @__inc_ref(ptr %t90)
  %t91 = call ptr @__concat(ptr %t90, ptr getelementptr inbounds (i8, ptr @.str.3, i64 12))
  br label %case.end.4.88
case.end.4.88:
  br label %case.join.78
case.default.77:
  unreachable
case.join.78:
  %t92 = phi ptr [ %t83, %case.end.3.80 ], [ %t91, %case.end.4.88 ]
  call void @__free_recursive(ptr %t73)
  br label %case.end.4.67
case.end.4.67:
  br label %case.join.57
case.default.56:
  unreachable
case.join.57:
  %t93 = phi ptr [ %t62, %case.end.3.59 ], [ %t92, %case.end.4.67 ]
  call void @__free_recursive(ptr %t52)
  call void @__free_recursive(ptr %t30)
  store ptr %t93, ptr %v__inl14_scrut.jslot
  br label %join.25
join.case.default.34:
  unreachable
join.25:
  %t94 = load ptr, ptr %v__inl14_scrut.jslot
  %t95 = getelementptr ptr, ptr %t94, i32 0
  %t96 = load ptr, ptr %t95
  %t97 = ptrtoint ptr %t96 to i64
  switch i64 %t97, label %case.default.98 [ i64 3, label %case.arm.3.100 i64 4, label %case.arm.4.114 ]
case.arm.3.100:
  %t102 = call ptr @__alloc(i64 24, i32 2)
  %t103 = inttoptr i64 7 to ptr
  %t104 = getelementptr ptr, ptr %t102, i32 0
  store ptr %t103, ptr %t104
  %t105 = getelementptr ptr, ptr %t102, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t105
  %t106 = call ptr @__alloc(i64 16, i32 1)
  %t107 = inttoptr i64 5 to ptr
  %t108 = getelementptr ptr, ptr %t106, i32 0
  store ptr %t107, ptr %t108
  %t109 = call ptr @__alloc(i64 8, i32 0)
  %t110 = inttoptr i64 0 to ptr
  %t111 = getelementptr ptr, ptr %t109, i32 0
  store ptr %t110, ptr %t111
  %t112 = getelementptr ptr, ptr %t106, i32 1
  store ptr %t109, ptr %t112
  %t113 = getelementptr ptr, ptr %t102, i32 2
  store ptr %t106, ptr %t113
  br label %case.end.3.101
case.end.3.101:
  br label %case.join.99
case.arm.4.114:
  %t116 = call ptr @__alloc(i64 24, i32 2)
  %t117 = inttoptr i64 7 to ptr
  %t118 = getelementptr ptr, ptr %t116, i32 0
  store ptr %t117, ptr %t118
  %t119 = getelementptr ptr, ptr %t94, i32 1
  %t120 = load ptr, ptr %t119
  call void @__inc_ref(ptr %t120)
  %t121 = getelementptr ptr, ptr %t116, i32 1
  store ptr %t120, ptr %t121
  %t122 = call ptr @__alloc(i64 16, i32 1)
  %t123 = inttoptr i64 5 to ptr
  %t124 = getelementptr ptr, ptr %t122, i32 0
  store ptr %t123, ptr %t124
  %t125 = call ptr @__alloc(i64 8, i32 0)
  %t126 = inttoptr i64 0 to ptr
  %t127 = getelementptr ptr, ptr %t125, i32 0
  store ptr %t126, ptr %t127
  %t128 = getelementptr ptr, ptr %t122, i32 1
  store ptr %t125, ptr %t128
  %t129 = getelementptr ptr, ptr %t116, i32 2
  store ptr %t122, ptr %t129
  br label %case.end.4.115
case.end.4.115:
  br label %case.join.99
case.default.98:
  unreachable
case.join.99:
  %t130 = phi ptr [ %t102, %case.end.3.101 ], [ %t116, %case.end.4.115 ]
  call void @__free_recursive(ptr %t94)
  br label %join.end.131
join.end.131:
  br label %join.after.26
join.after.26:
  %t132 = phi ptr [ %t36, %join.val.48 ], [ %t130, %join.end.131 ]
  call void @__free_recursive(ptr %t24)
  ret ptr %t132
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
