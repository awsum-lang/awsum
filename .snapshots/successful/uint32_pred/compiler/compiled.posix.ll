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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [11 x i8]} { i32 0, i32 0, i32 0, i32 11, i32 11, [11 x i8] c"underflow: " }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [14 x i8]} { i32 0, i32 0, i32 0, i32 14, i32 14, [14 x i8] c"UnderflowError" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"ok: " }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c", " }

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


define internal ptr @__predUInt32(ptr %p) {
  %v = load i32, ptr %p
  %is_zero = icmp eq i32 %v, 0
  br i1 %is_zero, label %overflow, label %ok
overflow:
  %ue = call ptr @__alloc(i64 8, i32 0)
  %ue_tag = inttoptr i64 17 to ptr
  store ptr %ue_tag, ptr %ue
  %left = call ptr @__alloc(i64 16, i32 1)
  %left_tag = inttoptr i64 3 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %ue, ptr %left_f
  call void @__free_recursive(ptr %p)
  ret ptr %left
ok:
  %newv = sub i32 %v, 1
  %box = call ptr @__alloc(i64 4, i32 0)
  store i32 %newv, ptr %box
  %right = call ptr @__alloc(i64 16, i32 1)
  %right_tag = inttoptr i64 4 to ptr
  store ptr %right_tag, ptr %right
  %right_f = getelementptr ptr, ptr %right, i32 1
  store ptr %box, ptr %right_f
  call void @__free_recursive(ptr %p)
  ret ptr %right
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

define internal ptr @v_minUInt32() {
  %t0 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t0
  ret ptr %t0
}

define internal ptr @v_maxUInt32() {
  %t0 = call ptr @__alloc(i64 4, i32 0)
  store i32 -1, ptr %t0
  ret ptr %t0
}

define internal ptr @v_main() {
  %v__inl16_scrut.jslot = alloca ptr
  %t0 = call ptr @v_minUInt32()
  %t1 = call ptr @__predUInt32(ptr %t0)
  %t4 = getelementptr ptr, ptr %t1, i32 0
  %t5 = load ptr, ptr %t4
  %t6 = ptrtoint ptr %t5 to i64
  switch i64 %t6, label %case.default.7 [ i64 3, label %case.arm.3.9 i64 4, label %case.arm.4.12 ]
case.arm.3.9:
  %t11 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
  br label %case.end.3.10
case.end.3.10:
  br label %case.join.8
case.arm.4.12:
  %t14 = getelementptr ptr, ptr %t1, i32 1
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  %t16 = call ptr @__showUInt32(ptr %t15)
  %t17 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t16)
  br label %case.end.4.13
case.end.4.13:
  br label %case.join.8
case.default.7:
  unreachable
case.join.8:
  %t18 = phi ptr [ %t11, %case.end.3.10 ], [ %t17, %case.end.4.13 ]
  %t19 = getelementptr ptr, ptr %t18, i32 0
  %t20 = load ptr, ptr %t19
  %t21 = ptrtoint ptr %t20 to i64
  switch i64 %t21, label %join.case.default.22 [ i64 3, label %join.case.arm.3.23 i64 4, label %join.case.arm.4.37 ]
join.case.arm.3.23:
  %t24 = call ptr @__alloc(i64 24, i32 2)
  %t25 = inttoptr i64 7 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = getelementptr ptr, ptr %t24, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t27
  %t28 = call ptr @__alloc(i64 16, i32 1)
  %t29 = inttoptr i64 5 to ptr
  %t30 = getelementptr ptr, ptr %t28, i32 0
  store ptr %t29, ptr %t30
  %t31 = call ptr @__alloc(i64 8, i32 0)
  %t32 = inttoptr i64 0 to ptr
  %t33 = getelementptr ptr, ptr %t31, i32 0
  store ptr %t32, ptr %t33
  %t34 = getelementptr ptr, ptr %t28, i32 1
  store ptr %t31, ptr %t34
  %t35 = getelementptr ptr, ptr %t24, i32 2
  store ptr %t28, ptr %t35
  call void @__free_recursive(ptr %t18)
  br label %join.val.36
join.val.36:
  br label %join.after.3
join.case.arm.4.37:
  %t38 = getelementptr ptr, ptr %t18, i32 1
  %t39 = load ptr, ptr %t38
  call void @__inc_ref(ptr %t39)
  %t40 = call ptr @__alloc(i64 16, i32 1)
  %t41 = inttoptr i64 4 to ptr
  %t42 = getelementptr ptr, ptr %t40, i32 0
  store ptr %t41, ptr %t42
  %t43 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t43
  %t44 = getelementptr ptr, ptr %t40, i32 1
  store ptr %t43, ptr %t44
  %t45 = getelementptr ptr, ptr %t40, i32 0
  %t46 = load ptr, ptr %t45
  %t47 = ptrtoint ptr %t46 to i64
  switch i64 %t47, label %case.default.48 [ i64 3, label %case.arm.3.50 i64 4, label %case.arm.4.53 ]
case.arm.3.50:
  %t52 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
  br label %case.end.3.51
case.end.3.51:
  br label %case.join.49
case.arm.4.53:
  %t55 = getelementptr ptr, ptr %t40, i32 1
  %t56 = load ptr, ptr %t55
  call void @__inc_ref(ptr %t56)
  %t57 = call ptr @__showUInt32(ptr %t56)
  %t58 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t57)
  br label %case.end.4.54
case.end.4.54:
  br label %case.join.49
case.default.48:
  unreachable
case.join.49:
  %t59 = phi ptr [ %t52, %case.end.3.51 ], [ %t58, %case.end.4.54 ]
  %t60 = getelementptr ptr, ptr %t59, i32 0
  %t61 = load ptr, ptr %t60
  %t62 = ptrtoint ptr %t61 to i64
  switch i64 %t62, label %case.default.63 [ i64 3, label %case.arm.3.65 i64 4, label %case.arm.4.73 ]
case.arm.3.65:
  %t67 = getelementptr ptr, ptr %t59, i32 1
  %t68 = load ptr, ptr %t67
  call void @__inc_ref(ptr %t68)
  %t69 = call ptr @__alloc(i64 16, i32 1)
  %t70 = inttoptr i64 3 to ptr
  %t71 = getelementptr ptr, ptr %t69, i32 0
  store ptr %t70, ptr %t71
  call void @__inc_ref(ptr %t68)
  %t72 = getelementptr ptr, ptr %t69, i32 1
  store ptr %t68, ptr %t72
  br label %case.end.3.66
case.end.3.66:
  br label %case.join.64
case.arm.4.73:
  %t75 = getelementptr ptr, ptr %t59, i32 1
  %t76 = load ptr, ptr %t75
  call void @__inc_ref(ptr %t76)
  %t77 = call ptr @__alloc(i64 16, i32 1)
  %t78 = inttoptr i64 4 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  %t80 = call ptr @__alloc(i64 4, i32 0)
  store i32 2147483647, ptr %t80
  %t81 = getelementptr ptr, ptr %t77, i32 1
  store ptr %t80, ptr %t81
  %t82 = getelementptr ptr, ptr %t77, i32 0
  %t83 = load ptr, ptr %t82
  %t84 = ptrtoint ptr %t83 to i64
  switch i64 %t84, label %case.default.85 [ i64 3, label %case.arm.3.87 i64 4, label %case.arm.4.90 ]
case.arm.3.87:
  %t89 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
  br label %case.end.3.88
case.end.3.88:
  br label %case.join.86
case.arm.4.90:
  %t92 = getelementptr ptr, ptr %t77, i32 1
  %t93 = load ptr, ptr %t92
  call void @__inc_ref(ptr %t93)
  %t94 = call ptr @__showUInt32(ptr %t93)
  %t95 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t94)
  br label %case.end.4.91
case.end.4.91:
  br label %case.join.86
case.default.85:
  unreachable
case.join.86:
  %t96 = phi ptr [ %t89, %case.end.3.88 ], [ %t95, %case.end.4.91 ]
  %t97 = getelementptr ptr, ptr %t96, i32 0
  %t98 = load ptr, ptr %t97
  %t99 = ptrtoint ptr %t98 to i64
  switch i64 %t99, label %case.default.100 [ i64 3, label %case.arm.3.102 i64 4, label %case.arm.4.110 ]
case.arm.3.102:
  %t104 = getelementptr ptr, ptr %t96, i32 1
  %t105 = load ptr, ptr %t104
  call void @__inc_ref(ptr %t105)
  %t106 = call ptr @__alloc(i64 16, i32 1)
  %t107 = inttoptr i64 3 to ptr
  %t108 = getelementptr ptr, ptr %t106, i32 0
  store ptr %t107, ptr %t108
  call void @__inc_ref(ptr %t105)
  %t109 = getelementptr ptr, ptr %t106, i32 1
  store ptr %t105, ptr %t109
  br label %case.end.3.103
case.end.3.103:
  br label %case.join.101
case.arm.4.110:
  %t112 = getelementptr ptr, ptr %t96, i32 1
  %t113 = load ptr, ptr %t112
  call void @__inc_ref(ptr %t113)
  %t114 = call ptr @v_maxUInt32()
  %t115 = call ptr @__predUInt32(ptr %t114)
  %t116 = getelementptr ptr, ptr %t115, i32 0
  %t117 = load ptr, ptr %t116
  %t118 = ptrtoint ptr %t117 to i64
  switch i64 %t118, label %case.default.119 [ i64 3, label %case.arm.3.121 i64 4, label %case.arm.4.124 ]
case.arm.3.121:
  %t123 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
  br label %case.end.3.122
case.end.3.122:
  br label %case.join.120
case.arm.4.124:
  %t126 = getelementptr ptr, ptr %t115, i32 1
  %t127 = load ptr, ptr %t126
  call void @__inc_ref(ptr %t127)
  %t128 = call ptr @__showUInt32(ptr %t127)
  %t129 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t128)
  br label %case.end.4.125
case.end.4.125:
  br label %case.join.120
case.default.119:
  unreachable
case.join.120:
  %t130 = phi ptr [ %t123, %case.end.3.122 ], [ %t129, %case.end.4.125 ]
  %t131 = getelementptr ptr, ptr %t130, i32 0
  %t132 = load ptr, ptr %t131
  %t133 = ptrtoint ptr %t132 to i64
  switch i64 %t133, label %case.default.134 [ i64 3, label %case.arm.3.136 i64 4, label %case.arm.4.144 ]
case.arm.3.136:
  %t138 = getelementptr ptr, ptr %t130, i32 1
  %t139 = load ptr, ptr %t138
  call void @__inc_ref(ptr %t139)
  %t140 = call ptr @__alloc(i64 16, i32 1)
  %t141 = inttoptr i64 3 to ptr
  %t142 = getelementptr ptr, ptr %t140, i32 0
  store ptr %t141, ptr %t142
  call void @__inc_ref(ptr %t139)
  %t143 = getelementptr ptr, ptr %t140, i32 1
  store ptr %t139, ptr %t143
  br label %case.end.3.137
case.end.3.137:
  br label %case.join.135
case.arm.4.144:
  %t146 = getelementptr ptr, ptr %t130, i32 1
  %t147 = load ptr, ptr %t146
  call void @__inc_ref(ptr %t147)
  call void @__inc_ref(ptr %t39)
  %t148 = call ptr @__concat(ptr %t39, ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  %t149 = getelementptr ptr, ptr %t148, i32 0
  %t150 = load ptr, ptr %t149
  %t151 = ptrtoint ptr %t150 to i64
  switch i64 %t151, label %case.default.152 [ i64 3, label %case.arm.3.154 i64 4, label %case.arm.4.162 ]
case.arm.3.154:
  %t156 = getelementptr ptr, ptr %t148, i32 1
  %t157 = load ptr, ptr %t156
  call void @__inc_ref(ptr %t157)
  %t158 = call ptr @__alloc(i64 16, i32 1)
  %t159 = inttoptr i64 3 to ptr
  %t160 = getelementptr ptr, ptr %t158, i32 0
  store ptr %t159, ptr %t160
  call void @__inc_ref(ptr %t157)
  %t161 = getelementptr ptr, ptr %t158, i32 1
  store ptr %t157, ptr %t161
  br label %case.end.3.155
case.end.3.155:
  br label %case.join.153
case.arm.4.162:
  %t164 = getelementptr ptr, ptr %t148, i32 1
  %t165 = load ptr, ptr %t164
  call void @__inc_ref(ptr %t165)
  call void @__inc_ref(ptr %t165)
  call void @__inc_ref(ptr %t76)
  %t166 = call ptr @__concat(ptr %t165, ptr %t76)
  %t167 = getelementptr ptr, ptr %t166, i32 0
  %t168 = load ptr, ptr %t167
  %t169 = ptrtoint ptr %t168 to i64
  switch i64 %t169, label %case.default.170 [ i64 3, label %case.arm.3.172 i64 4, label %case.arm.4.180 ]
case.arm.3.172:
  %t174 = getelementptr ptr, ptr %t166, i32 1
  %t175 = load ptr, ptr %t174
  call void @__inc_ref(ptr %t175)
  %t176 = call ptr @__alloc(i64 16, i32 1)
  %t177 = inttoptr i64 3 to ptr
  %t178 = getelementptr ptr, ptr %t176, i32 0
  store ptr %t177, ptr %t178
  call void @__inc_ref(ptr %t175)
  %t179 = getelementptr ptr, ptr %t176, i32 1
  store ptr %t175, ptr %t179
  br label %case.end.3.173
case.end.3.173:
  br label %case.join.171
case.arm.4.180:
  %t182 = getelementptr ptr, ptr %t166, i32 1
  %t183 = load ptr, ptr %t182
  call void @__inc_ref(ptr %t183)
  call void @__inc_ref(ptr %t183)
  %t184 = call ptr @__concat(ptr %t183, ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  %t185 = getelementptr ptr, ptr %t184, i32 0
  %t186 = load ptr, ptr %t185
  %t187 = ptrtoint ptr %t186 to i64
  switch i64 %t187, label %case.default.188 [ i64 3, label %case.arm.3.190 i64 4, label %case.arm.4.198 ]
case.arm.3.190:
  %t192 = getelementptr ptr, ptr %t184, i32 1
  %t193 = load ptr, ptr %t192
  call void @__inc_ref(ptr %t193)
  %t194 = call ptr @__alloc(i64 16, i32 1)
  %t195 = inttoptr i64 3 to ptr
  %t196 = getelementptr ptr, ptr %t194, i32 0
  store ptr %t195, ptr %t196
  call void @__inc_ref(ptr %t193)
  %t197 = getelementptr ptr, ptr %t194, i32 1
  store ptr %t193, ptr %t197
  br label %case.end.3.191
case.end.3.191:
  br label %case.join.189
case.arm.4.198:
  %t200 = getelementptr ptr, ptr %t184, i32 1
  %t201 = load ptr, ptr %t200
  call void @__inc_ref(ptr %t201)
  call void @__inc_ref(ptr %t201)
  call void @__inc_ref(ptr %t113)
  %t202 = call ptr @__concat(ptr %t201, ptr %t113)
  %t203 = getelementptr ptr, ptr %t202, i32 0
  %t204 = load ptr, ptr %t203
  %t205 = ptrtoint ptr %t204 to i64
  switch i64 %t205, label %case.default.206 [ i64 3, label %case.arm.3.208 i64 4, label %case.arm.4.216 ]
case.arm.3.208:
  %t210 = getelementptr ptr, ptr %t202, i32 1
  %t211 = load ptr, ptr %t210
  call void @__inc_ref(ptr %t211)
  %t212 = call ptr @__alloc(i64 16, i32 1)
  %t213 = inttoptr i64 3 to ptr
  %t214 = getelementptr ptr, ptr %t212, i32 0
  store ptr %t213, ptr %t214
  call void @__inc_ref(ptr %t211)
  %t215 = getelementptr ptr, ptr %t212, i32 1
  store ptr %t211, ptr %t215
  br label %case.end.3.209
case.end.3.209:
  br label %case.join.207
case.arm.4.216:
  %t218 = getelementptr ptr, ptr %t202, i32 1
  %t219 = load ptr, ptr %t218
  call void @__inc_ref(ptr %t219)
  call void @__inc_ref(ptr %t219)
  %t220 = call ptr @__concat(ptr %t219, ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  %t221 = getelementptr ptr, ptr %t220, i32 0
  %t222 = load ptr, ptr %t221
  %t223 = ptrtoint ptr %t222 to i64
  switch i64 %t223, label %case.default.224 [ i64 3, label %case.arm.3.226 i64 4, label %case.arm.4.234 ]
case.arm.3.226:
  %t228 = getelementptr ptr, ptr %t220, i32 1
  %t229 = load ptr, ptr %t228
  call void @__inc_ref(ptr %t229)
  %t230 = call ptr @__alloc(i64 16, i32 1)
  %t231 = inttoptr i64 3 to ptr
  %t232 = getelementptr ptr, ptr %t230, i32 0
  store ptr %t231, ptr %t232
  call void @__inc_ref(ptr %t229)
  %t233 = getelementptr ptr, ptr %t230, i32 1
  store ptr %t229, ptr %t233
  br label %case.end.3.227
case.end.3.227:
  br label %case.join.225
case.arm.4.234:
  %t236 = getelementptr ptr, ptr %t220, i32 1
  %t237 = load ptr, ptr %t236
  call void @__inc_ref(ptr %t237)
  call void @__inc_ref(ptr %t237)
  call void @__inc_ref(ptr %t147)
  %t238 = call ptr @__concat(ptr %t237, ptr %t147)
  br label %case.end.4.235
case.end.4.235:
  br label %case.join.225
case.default.224:
  unreachable
case.join.225:
  %t239 = phi ptr [ %t230, %case.end.3.227 ], [ %t238, %case.end.4.235 ]
  call void @__free_recursive(ptr %t220)
  br label %case.end.4.217
case.end.4.217:
  br label %case.join.207
case.default.206:
  unreachable
case.join.207:
  %t240 = phi ptr [ %t212, %case.end.3.209 ], [ %t239, %case.end.4.217 ]
  call void @__free_recursive(ptr %t202)
  br label %case.end.4.199
case.end.4.199:
  br label %case.join.189
case.default.188:
  unreachable
case.join.189:
  %t241 = phi ptr [ %t194, %case.end.3.191 ], [ %t240, %case.end.4.199 ]
  call void @__free_recursive(ptr %t184)
  br label %case.end.4.181
case.end.4.181:
  br label %case.join.171
case.default.170:
  unreachable
case.join.171:
  %t242 = phi ptr [ %t176, %case.end.3.173 ], [ %t241, %case.end.4.181 ]
  call void @__free_recursive(ptr %t166)
  br label %case.end.4.163
case.end.4.163:
  br label %case.join.153
case.default.152:
  unreachable
case.join.153:
  %t243 = phi ptr [ %t158, %case.end.3.155 ], [ %t242, %case.end.4.163 ]
  call void @__free_recursive(ptr %t148)
  br label %case.end.4.145
case.end.4.145:
  br label %case.join.135
case.default.134:
  unreachable
case.join.135:
  %t244 = phi ptr [ %t140, %case.end.3.137 ], [ %t243, %case.end.4.145 ]
  call void @__free_recursive(ptr %t130)
  call void @__free_recursive(ptr %t115)
  br label %case.end.4.111
case.end.4.111:
  br label %case.join.101
case.default.100:
  unreachable
case.join.101:
  %t245 = phi ptr [ %t106, %case.end.3.103 ], [ %t244, %case.end.4.111 ]
  call void @__free_recursive(ptr %t96)
  call void @__free_recursive(ptr %t77)
  br label %case.end.4.74
case.end.4.74:
  br label %case.join.64
case.default.63:
  unreachable
case.join.64:
  %t246 = phi ptr [ %t69, %case.end.3.66 ], [ %t245, %case.end.4.74 ]
  call void @__free_recursive(ptr %t59)
  call void @__free_recursive(ptr %t40)
  call void @__free_recursive(ptr %t18)
  store ptr %t246, ptr %v__inl16_scrut.jslot
  br label %join.2
join.case.default.22:
  unreachable
join.2:
  %t247 = load ptr, ptr %v__inl16_scrut.jslot
  %t248 = getelementptr ptr, ptr %t247, i32 0
  %t249 = load ptr, ptr %t248
  %t250 = ptrtoint ptr %t249 to i64
  switch i64 %t250, label %case.default.251 [ i64 3, label %case.arm.3.253 i64 4, label %case.arm.4.267 ]
case.arm.3.253:
  %t255 = call ptr @__alloc(i64 24, i32 2)
  %t256 = inttoptr i64 7 to ptr
  %t257 = getelementptr ptr, ptr %t255, i32 0
  store ptr %t256, ptr %t257
  %t258 = getelementptr ptr, ptr %t255, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t258
  %t259 = call ptr @__alloc(i64 16, i32 1)
  %t260 = inttoptr i64 5 to ptr
  %t261 = getelementptr ptr, ptr %t259, i32 0
  store ptr %t260, ptr %t261
  %t262 = call ptr @__alloc(i64 8, i32 0)
  %t263 = inttoptr i64 0 to ptr
  %t264 = getelementptr ptr, ptr %t262, i32 0
  store ptr %t263, ptr %t264
  %t265 = getelementptr ptr, ptr %t259, i32 1
  store ptr %t262, ptr %t265
  %t266 = getelementptr ptr, ptr %t255, i32 2
  store ptr %t259, ptr %t266
  br label %case.end.3.254
case.end.3.254:
  br label %case.join.252
case.arm.4.267:
  %t269 = call ptr @__alloc(i64 24, i32 2)
  %t270 = inttoptr i64 7 to ptr
  %t271 = getelementptr ptr, ptr %t269, i32 0
  store ptr %t270, ptr %t271
  %t272 = getelementptr ptr, ptr %t247, i32 1
  %t273 = load ptr, ptr %t272
  call void @__inc_ref(ptr %t273)
  %t274 = getelementptr ptr, ptr %t269, i32 1
  store ptr %t273, ptr %t274
  %t275 = call ptr @__alloc(i64 16, i32 1)
  %t276 = inttoptr i64 5 to ptr
  %t277 = getelementptr ptr, ptr %t275, i32 0
  store ptr %t276, ptr %t277
  %t278 = call ptr @__alloc(i64 8, i32 0)
  %t279 = inttoptr i64 0 to ptr
  %t280 = getelementptr ptr, ptr %t278, i32 0
  store ptr %t279, ptr %t280
  %t281 = getelementptr ptr, ptr %t275, i32 1
  store ptr %t278, ptr %t281
  %t282 = getelementptr ptr, ptr %t269, i32 2
  store ptr %t275, ptr %t282
  br label %case.end.4.268
case.end.4.268:
  br label %case.join.252
case.default.251:
  unreachable
case.join.252:
  %t283 = phi ptr [ %t255, %case.end.3.254 ], [ %t269, %case.end.4.268 ]
  call void @__free_recursive(ptr %t247)
  br label %join.end.284
join.end.284:
  br label %join.after.3
join.after.3:
  %t285 = phi ptr [ %t24, %join.val.36 ], [ %t283, %join.end.284 ]
  call void @__free_recursive(ptr %t1)
  ret ptr %t285
}

define i32 @main(i32 %argc, ptr %argv) {
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
