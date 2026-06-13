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
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [10 x i8]} { i32 0, i32 0, i32 0, i32 10, i32 10, [10 x i8] c"overflow: " }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [13 x i8]} { i32 0, i32 0, i32 0, i32 13, i32 13, [13 x i8] c"OverflowError" }
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


define internal ptr @__showUInt8(ptr %p) {
  %b = load i8, ptr %p
  %v = zext i8 %b to i32
  %buf = call ptr @__alloc(i64 24, i32 0)
  %payload = getelementptr i8, ptr %buf, i64 8
  %n = call i32 (ptr, i64, ptr, ...) @snprintf(ptr %payload, i64 16, ptr @.fmt_u8, i32 %v)
  store i32 %n, ptr %buf
  %u16p = getelementptr i8, ptr %buf, i64 4
  store i32 %n, ptr %u16p
  call void @__free_recursive(ptr %p)
  ret ptr %buf
}


define internal ptr @__succUInt8(ptr %p) {
  %v = load i8, ptr %p
  %is_max = icmp eq i8 %v, 255
  br i1 %is_max, label %overflow, label %ok
overflow:
  %oe = call ptr @__alloc(i64 8, i32 0)
  %oe_tag = inttoptr i64 18 to ptr
  store ptr %oe_tag, ptr %oe
  %left = call ptr @__alloc(i64 16, i32 1)
  %left_tag = inttoptr i64 3 to ptr
  store ptr %left_tag, ptr %left
  %left_f = getelementptr ptr, ptr %left, i32 1
  store ptr %oe, ptr %left_f
  call void @__free_recursive(ptr %p)
  ret ptr %left
ok:
  %newv = add i8 %v, 1
  %box = call ptr @__alloc(i64 1, i32 0)
  store i8 %newv, ptr %box
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

define internal ptr @v_minUInt8() {
  %t0 = call ptr @__alloc(i64 1, i32 0)
  store i8 0, ptr %t0
  ret ptr %t0
}

define internal ptr @v_maxUInt8() {
  %t0 = call ptr @__alloc(i64 1, i32 0)
  store i8 255, ptr %t0
  ret ptr %t0
}

define internal ptr @v_main() {
  %v__inl13_scrut.jslot = alloca ptr
  %t0 = call ptr @v_maxUInt8()
  %t1 = call ptr @__succUInt8(ptr %t0)
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
  %t16 = call ptr @__showUInt8(ptr %t15)
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
  %t43 = call ptr @__alloc(i64 1, i32 0)
  store i8 255, ptr %t43
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
  %t57 = call ptr @__showUInt8(ptr %t56)
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
  %t77 = call ptr @v_minUInt8()
  %t78 = call ptr @__succUInt8(ptr %t77)
  %t79 = getelementptr ptr, ptr %t78, i32 0
  %t80 = load ptr, ptr %t79
  %t81 = ptrtoint ptr %t80 to i64
  switch i64 %t81, label %case.default.82 [ i64 3, label %case.arm.3.84 i64 4, label %case.arm.4.87 ]
case.arm.3.84:
  %t86 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
  br label %case.end.3.85
case.end.3.85:
  br label %case.join.83
case.arm.4.87:
  %t89 = getelementptr ptr, ptr %t78, i32 1
  %t90 = load ptr, ptr %t89
  call void @__inc_ref(ptr %t90)
  %t91 = call ptr @__showUInt8(ptr %t90)
  %t92 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t91)
  br label %case.end.4.88
case.end.4.88:
  br label %case.join.83
case.default.82:
  unreachable
case.join.83:
  %t93 = phi ptr [ %t86, %case.end.3.85 ], [ %t92, %case.end.4.88 ]
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
  call void @__inc_ref(ptr %t39)
  %t111 = call ptr @__concat(ptr %t39, ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
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
  call void @__inc_ref(ptr %t76)
  %t129 = call ptr @__concat(ptr %t128, ptr %t76)
  %t130 = getelementptr ptr, ptr %t129, i32 0
  %t131 = load ptr, ptr %t130
  %t132 = ptrtoint ptr %t131 to i64
  switch i64 %t132, label %case.default.133 [ i64 3, label %case.arm.3.135 i64 4, label %case.arm.4.143 ]
case.arm.3.135:
  %t137 = getelementptr ptr, ptr %t129, i32 1
  %t138 = load ptr, ptr %t137
  call void @__inc_ref(ptr %t138)
  %t139 = call ptr @__alloc(i64 16, i32 1)
  %t140 = inttoptr i64 3 to ptr
  %t141 = getelementptr ptr, ptr %t139, i32 0
  store ptr %t140, ptr %t141
  call void @__inc_ref(ptr %t138)
  %t142 = getelementptr ptr, ptr %t139, i32 1
  store ptr %t138, ptr %t142
  br label %case.end.3.136
case.end.3.136:
  br label %case.join.134
case.arm.4.143:
  %t145 = getelementptr ptr, ptr %t129, i32 1
  %t146 = load ptr, ptr %t145
  call void @__inc_ref(ptr %t146)
  call void @__inc_ref(ptr %t146)
  %t147 = call ptr @__concat(ptr %t146, ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  %t148 = getelementptr ptr, ptr %t147, i32 0
  %t149 = load ptr, ptr %t148
  %t150 = ptrtoint ptr %t149 to i64
  switch i64 %t150, label %case.default.151 [ i64 3, label %case.arm.3.153 i64 4, label %case.arm.4.161 ]
case.arm.3.153:
  %t155 = getelementptr ptr, ptr %t147, i32 1
  %t156 = load ptr, ptr %t155
  call void @__inc_ref(ptr %t156)
  %t157 = call ptr @__alloc(i64 16, i32 1)
  %t158 = inttoptr i64 3 to ptr
  %t159 = getelementptr ptr, ptr %t157, i32 0
  store ptr %t158, ptr %t159
  call void @__inc_ref(ptr %t156)
  %t160 = getelementptr ptr, ptr %t157, i32 1
  store ptr %t156, ptr %t160
  br label %case.end.3.154
case.end.3.154:
  br label %case.join.152
case.arm.4.161:
  %t163 = getelementptr ptr, ptr %t147, i32 1
  %t164 = load ptr, ptr %t163
  call void @__inc_ref(ptr %t164)
  call void @__inc_ref(ptr %t164)
  call void @__inc_ref(ptr %t110)
  %t165 = call ptr @__concat(ptr %t164, ptr %t110)
  br label %case.end.4.162
case.end.4.162:
  br label %case.join.152
case.default.151:
  unreachable
case.join.152:
  %t166 = phi ptr [ %t157, %case.end.3.154 ], [ %t165, %case.end.4.162 ]
  call void @__free_recursive(ptr %t147)
  br label %case.end.4.144
case.end.4.144:
  br label %case.join.134
case.default.133:
  unreachable
case.join.134:
  %t167 = phi ptr [ %t139, %case.end.3.136 ], [ %t166, %case.end.4.144 ]
  call void @__free_recursive(ptr %t129)
  br label %case.end.4.126
case.end.4.126:
  br label %case.join.116
case.default.115:
  unreachable
case.join.116:
  %t168 = phi ptr [ %t121, %case.end.3.118 ], [ %t167, %case.end.4.126 ]
  call void @__free_recursive(ptr %t111)
  br label %case.end.4.108
case.end.4.108:
  br label %case.join.98
case.default.97:
  unreachable
case.join.98:
  %t169 = phi ptr [ %t103, %case.end.3.100 ], [ %t168, %case.end.4.108 ]
  call void @__free_recursive(ptr %t93)
  call void @__free_recursive(ptr %t78)
  br label %case.end.4.74
case.end.4.74:
  br label %case.join.64
case.default.63:
  unreachable
case.join.64:
  %t170 = phi ptr [ %t69, %case.end.3.66 ], [ %t169, %case.end.4.74 ]
  call void @__free_recursive(ptr %t59)
  call void @__free_recursive(ptr %t40)
  call void @__free_recursive(ptr %t18)
  store ptr %t170, ptr %v__inl13_scrut.jslot
  br label %join.2
join.case.default.22:
  unreachable
join.2:
  %t171 = load ptr, ptr %v__inl13_scrut.jslot
  %t172 = getelementptr ptr, ptr %t171, i32 0
  %t173 = load ptr, ptr %t172
  %t174 = ptrtoint ptr %t173 to i64
  switch i64 %t174, label %case.default.175 [ i64 3, label %case.arm.3.177 i64 4, label %case.arm.4.191 ]
case.arm.3.177:
  %t179 = call ptr @__alloc(i64 24, i32 2)
  %t180 = inttoptr i64 7 to ptr
  %t181 = getelementptr ptr, ptr %t179, i32 0
  store ptr %t180, ptr %t181
  %t182 = getelementptr ptr, ptr %t179, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t182
  %t183 = call ptr @__alloc(i64 16, i32 1)
  %t184 = inttoptr i64 5 to ptr
  %t185 = getelementptr ptr, ptr %t183, i32 0
  store ptr %t184, ptr %t185
  %t186 = call ptr @__alloc(i64 8, i32 0)
  %t187 = inttoptr i64 0 to ptr
  %t188 = getelementptr ptr, ptr %t186, i32 0
  store ptr %t187, ptr %t188
  %t189 = getelementptr ptr, ptr %t183, i32 1
  store ptr %t186, ptr %t189
  %t190 = getelementptr ptr, ptr %t179, i32 2
  store ptr %t183, ptr %t190
  br label %case.end.3.178
case.end.3.178:
  br label %case.join.176
case.arm.4.191:
  %t193 = call ptr @__alloc(i64 24, i32 2)
  %t194 = inttoptr i64 7 to ptr
  %t195 = getelementptr ptr, ptr %t193, i32 0
  store ptr %t194, ptr %t195
  %t196 = getelementptr ptr, ptr %t171, i32 1
  %t197 = load ptr, ptr %t196
  call void @__inc_ref(ptr %t197)
  %t198 = getelementptr ptr, ptr %t193, i32 1
  store ptr %t197, ptr %t198
  %t199 = call ptr @__alloc(i64 16, i32 1)
  %t200 = inttoptr i64 5 to ptr
  %t201 = getelementptr ptr, ptr %t199, i32 0
  store ptr %t200, ptr %t201
  %t202 = call ptr @__alloc(i64 8, i32 0)
  %t203 = inttoptr i64 0 to ptr
  %t204 = getelementptr ptr, ptr %t202, i32 0
  store ptr %t203, ptr %t204
  %t205 = getelementptr ptr, ptr %t199, i32 1
  store ptr %t202, ptr %t205
  %t206 = getelementptr ptr, ptr %t193, i32 2
  store ptr %t199, ptr %t206
  br label %case.end.4.192
case.end.4.192:
  br label %case.join.176
case.default.175:
  unreachable
case.join.176:
  %t207 = phi ptr [ %t179, %case.end.3.178 ], [ %t193, %case.end.4.192 ]
  call void @__free_recursive(ptr %t171)
  br label %join.end.208
join.end.208:
  br label %join.after.3
join.after.3:
  %t209 = phi ptr [ %t24, %join.val.36 ], [ %t207, %join.end.208 ]
  call void @__free_recursive(ptr %t1)
  ret ptr %t209
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
