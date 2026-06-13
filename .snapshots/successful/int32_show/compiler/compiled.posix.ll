; External C declarations
declare ptr @malloc(i64)
declare ptr @realloc(ptr, i64)
declare void @free(ptr)
declare ptr @memcpy(ptr, ptr, i64)
declare i64 @write(i32, ptr, i64)
declare i32 @snprintf(ptr, i64, ptr, ...)

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
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c", " }

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

define internal ptr @v_minInt32() {
  %t0 = call ptr @__alloc(i64 4, i32 0)
  store i32 -2147483648, ptr %t0
  ret ptr %t0
}

define internal ptr @v_maxInt32() {
  %t0 = call ptr @__alloc(i64 4, i32 0)
  store i32 2147483647, ptr %t0
  ret ptr %t0
}

define internal ptr @v_main() {
  %v__inl4_scrut.jslot = alloca ptr
  %t2 = call ptr @v_minInt32()
  %t3 = call ptr @__showInt32(ptr %t2)
  %t4 = call ptr @__concat(ptr %t3, ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  %t5 = getelementptr ptr, ptr %t4, i32 0
  %t6 = load ptr, ptr %t5
  %t7 = ptrtoint ptr %t6 to i64
  switch i64 %t7, label %join.case.default.8 [ i64 3, label %join.case.arm.3.9 i64 4, label %join.case.arm.4.23 ]
join.case.arm.3.9:
  %t10 = call ptr @__alloc(i64 24, i32 2)
  %t11 = inttoptr i64 7 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  %t13 = getelementptr ptr, ptr %t10, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t13
  %t14 = call ptr @__alloc(i64 16, i32 1)
  %t15 = inttoptr i64 5 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  %t17 = call ptr @__alloc(i64 8, i32 0)
  %t18 = inttoptr i64 0 to ptr
  %t19 = getelementptr ptr, ptr %t17, i32 0
  store ptr %t18, ptr %t19
  %t20 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t17, ptr %t20
  %t21 = getelementptr ptr, ptr %t10, i32 2
  store ptr %t14, ptr %t21
  call void @__free_recursive(ptr %t4)
  br label %join.val.22
join.val.22:
  br label %join.after.1
join.case.arm.4.23:
  %t24 = getelementptr ptr, ptr %t4, i32 1
  %t25 = load ptr, ptr %t24
  call void @__inc_ref(ptr %t25)
  call void @__inc_ref(ptr %t25)
  %t26 = call ptr @__alloc(i64 4, i32 0)
  store i32 -42, ptr %t26
  %t27 = call ptr @__showInt32(ptr %t26)
  %t28 = call ptr @__concat(ptr %t25, ptr %t27)
  %t29 = getelementptr ptr, ptr %t28, i32 0
  %t30 = load ptr, ptr %t29
  %t31 = ptrtoint ptr %t30 to i64
  switch i64 %t31, label %case.default.32 [ i64 3, label %case.arm.3.34 i64 4, label %case.arm.4.42 ]
case.arm.3.34:
  %t36 = getelementptr ptr, ptr %t28, i32 1
  %t37 = load ptr, ptr %t36
  call void @__inc_ref(ptr %t37)
  %t38 = call ptr @__alloc(i64 16, i32 1)
  %t39 = inttoptr i64 3 to ptr
  %t40 = getelementptr ptr, ptr %t38, i32 0
  store ptr %t39, ptr %t40
  call void @__inc_ref(ptr %t37)
  %t41 = getelementptr ptr, ptr %t38, i32 1
  store ptr %t37, ptr %t41
  br label %case.end.3.35
case.end.3.35:
  br label %case.join.33
case.arm.4.42:
  %t44 = getelementptr ptr, ptr %t28, i32 1
  %t45 = load ptr, ptr %t44
  call void @__inc_ref(ptr %t45)
  call void @__inc_ref(ptr %t45)
  %t46 = call ptr @__concat(ptr %t45, ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  %t47 = getelementptr ptr, ptr %t46, i32 0
  %t48 = load ptr, ptr %t47
  %t49 = ptrtoint ptr %t48 to i64
  switch i64 %t49, label %case.default.50 [ i64 3, label %case.arm.3.52 i64 4, label %case.arm.4.60 ]
case.arm.3.52:
  %t54 = getelementptr ptr, ptr %t46, i32 1
  %t55 = load ptr, ptr %t54
  call void @__inc_ref(ptr %t55)
  %t56 = call ptr @__alloc(i64 16, i32 1)
  %t57 = inttoptr i64 3 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  call void @__inc_ref(ptr %t55)
  %t59 = getelementptr ptr, ptr %t56, i32 1
  store ptr %t55, ptr %t59
  br label %case.end.3.53
case.end.3.53:
  br label %case.join.51
case.arm.4.60:
  %t62 = getelementptr ptr, ptr %t46, i32 1
  %t63 = load ptr, ptr %t62
  call void @__inc_ref(ptr %t63)
  call void @__inc_ref(ptr %t63)
  %t64 = call ptr @__alloc(i64 4, i32 0)
  store i32 0, ptr %t64
  %t65 = call ptr @__showInt32(ptr %t64)
  %t66 = call ptr @__concat(ptr %t63, ptr %t65)
  %t67 = getelementptr ptr, ptr %t66, i32 0
  %t68 = load ptr, ptr %t67
  %t69 = ptrtoint ptr %t68 to i64
  switch i64 %t69, label %case.default.70 [ i64 3, label %case.arm.3.72 i64 4, label %case.arm.4.80 ]
case.arm.3.72:
  %t74 = getelementptr ptr, ptr %t66, i32 1
  %t75 = load ptr, ptr %t74
  call void @__inc_ref(ptr %t75)
  %t76 = call ptr @__alloc(i64 16, i32 1)
  %t77 = inttoptr i64 3 to ptr
  %t78 = getelementptr ptr, ptr %t76, i32 0
  store ptr %t77, ptr %t78
  call void @__inc_ref(ptr %t75)
  %t79 = getelementptr ptr, ptr %t76, i32 1
  store ptr %t75, ptr %t79
  br label %case.end.3.73
case.end.3.73:
  br label %case.join.71
case.arm.4.80:
  %t82 = getelementptr ptr, ptr %t66, i32 1
  %t83 = load ptr, ptr %t82
  call void @__inc_ref(ptr %t83)
  call void @__inc_ref(ptr %t83)
  %t84 = call ptr @__concat(ptr %t83, ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  %t85 = getelementptr ptr, ptr %t84, i32 0
  %t86 = load ptr, ptr %t85
  %t87 = ptrtoint ptr %t86 to i64
  switch i64 %t87, label %case.default.88 [ i64 3, label %case.arm.3.90 i64 4, label %case.arm.4.98 ]
case.arm.3.90:
  %t92 = getelementptr ptr, ptr %t84, i32 1
  %t93 = load ptr, ptr %t92
  call void @__inc_ref(ptr %t93)
  %t94 = call ptr @__alloc(i64 16, i32 1)
  %t95 = inttoptr i64 3 to ptr
  %t96 = getelementptr ptr, ptr %t94, i32 0
  store ptr %t95, ptr %t96
  call void @__inc_ref(ptr %t93)
  %t97 = getelementptr ptr, ptr %t94, i32 1
  store ptr %t93, ptr %t97
  br label %case.end.3.91
case.end.3.91:
  br label %case.join.89
case.arm.4.98:
  %t100 = getelementptr ptr, ptr %t84, i32 1
  %t101 = load ptr, ptr %t100
  call void @__inc_ref(ptr %t101)
  call void @__inc_ref(ptr %t101)
  %t102 = call ptr @__alloc(i64 4, i32 0)
  store i32 7, ptr %t102
  %t103 = call ptr @__showInt32(ptr %t102)
  %t104 = call ptr @__concat(ptr %t101, ptr %t103)
  %t105 = getelementptr ptr, ptr %t104, i32 0
  %t106 = load ptr, ptr %t105
  %t107 = ptrtoint ptr %t106 to i64
  switch i64 %t107, label %case.default.108 [ i64 3, label %case.arm.3.110 i64 4, label %case.arm.4.118 ]
case.arm.3.110:
  %t112 = getelementptr ptr, ptr %t104, i32 1
  %t113 = load ptr, ptr %t112
  call void @__inc_ref(ptr %t113)
  %t114 = call ptr @__alloc(i64 16, i32 1)
  %t115 = inttoptr i64 3 to ptr
  %t116 = getelementptr ptr, ptr %t114, i32 0
  store ptr %t115, ptr %t116
  call void @__inc_ref(ptr %t113)
  %t117 = getelementptr ptr, ptr %t114, i32 1
  store ptr %t113, ptr %t117
  br label %case.end.3.111
case.end.3.111:
  br label %case.join.109
case.arm.4.118:
  %t120 = getelementptr ptr, ptr %t104, i32 1
  %t121 = load ptr, ptr %t120
  call void @__inc_ref(ptr %t121)
  call void @__inc_ref(ptr %t121)
  %t122 = call ptr @__concat(ptr %t121, ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  %t123 = getelementptr ptr, ptr %t122, i32 0
  %t124 = load ptr, ptr %t123
  %t125 = ptrtoint ptr %t124 to i64
  switch i64 %t125, label %case.default.126 [ i64 3, label %case.arm.3.128 i64 4, label %case.arm.4.136 ]
case.arm.3.128:
  %t130 = getelementptr ptr, ptr %t122, i32 1
  %t131 = load ptr, ptr %t130
  call void @__inc_ref(ptr %t131)
  %t132 = call ptr @__alloc(i64 16, i32 1)
  %t133 = inttoptr i64 3 to ptr
  %t134 = getelementptr ptr, ptr %t132, i32 0
  store ptr %t133, ptr %t134
  call void @__inc_ref(ptr %t131)
  %t135 = getelementptr ptr, ptr %t132, i32 1
  store ptr %t131, ptr %t135
  br label %case.end.3.129
case.end.3.129:
  br label %case.join.127
case.arm.4.136:
  %t138 = getelementptr ptr, ptr %t122, i32 1
  %t139 = load ptr, ptr %t138
  call void @__inc_ref(ptr %t139)
  call void @__inc_ref(ptr %t139)
  %t140 = call ptr @__alloc(i64 4, i32 0)
  store i32 1234567, ptr %t140
  %t141 = call ptr @__showInt32(ptr %t140)
  %t142 = call ptr @__concat(ptr %t139, ptr %t141)
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
  %t178 = call ptr @v_maxInt32()
  %t179 = call ptr @__showInt32(ptr %t178)
  %t180 = call ptr @__concat(ptr %t177, ptr %t179)
  br label %case.end.4.175
case.end.4.175:
  br label %case.join.165
case.default.164:
  unreachable
case.join.165:
  %t181 = phi ptr [ %t170, %case.end.3.167 ], [ %t180, %case.end.4.175 ]
  call void @__free_recursive(ptr %t160)
  br label %case.end.4.157
case.end.4.157:
  br label %case.join.147
case.default.146:
  unreachable
case.join.147:
  %t182 = phi ptr [ %t152, %case.end.3.149 ], [ %t181, %case.end.4.157 ]
  call void @__free_recursive(ptr %t142)
  br label %case.end.4.137
case.end.4.137:
  br label %case.join.127
case.default.126:
  unreachable
case.join.127:
  %t183 = phi ptr [ %t132, %case.end.3.129 ], [ %t182, %case.end.4.137 ]
  call void @__free_recursive(ptr %t122)
  br label %case.end.4.119
case.end.4.119:
  br label %case.join.109
case.default.108:
  unreachable
case.join.109:
  %t184 = phi ptr [ %t114, %case.end.3.111 ], [ %t183, %case.end.4.119 ]
  call void @__free_recursive(ptr %t104)
  br label %case.end.4.99
case.end.4.99:
  br label %case.join.89
case.default.88:
  unreachable
case.join.89:
  %t185 = phi ptr [ %t94, %case.end.3.91 ], [ %t184, %case.end.4.99 ]
  call void @__free_recursive(ptr %t84)
  br label %case.end.4.81
case.end.4.81:
  br label %case.join.71
case.default.70:
  unreachable
case.join.71:
  %t186 = phi ptr [ %t76, %case.end.3.73 ], [ %t185, %case.end.4.81 ]
  call void @__free_recursive(ptr %t66)
  br label %case.end.4.61
case.end.4.61:
  br label %case.join.51
case.default.50:
  unreachable
case.join.51:
  %t187 = phi ptr [ %t56, %case.end.3.53 ], [ %t186, %case.end.4.61 ]
  call void @__free_recursive(ptr %t46)
  br label %case.end.4.43
case.end.4.43:
  br label %case.join.33
case.default.32:
  unreachable
case.join.33:
  %t188 = phi ptr [ %t38, %case.end.3.35 ], [ %t187, %case.end.4.43 ]
  call void @__free_recursive(ptr %t28)
  call void @__free_recursive(ptr %t4)
  store ptr %t188, ptr %v__inl4_scrut.jslot
  br label %join.0
join.case.default.8:
  unreachable
join.0:
  %t189 = load ptr, ptr %v__inl4_scrut.jslot
  %t190 = getelementptr ptr, ptr %t189, i32 0
  %t191 = load ptr, ptr %t190
  %t192 = ptrtoint ptr %t191 to i64
  switch i64 %t192, label %case.default.193 [ i64 3, label %case.arm.3.195 i64 4, label %case.arm.4.209 ]
case.arm.3.195:
  %t197 = call ptr @__alloc(i64 24, i32 2)
  %t198 = inttoptr i64 7 to ptr
  %t199 = getelementptr ptr, ptr %t197, i32 0
  store ptr %t198, ptr %t199
  %t200 = getelementptr ptr, ptr %t197, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t200
  %t201 = call ptr @__alloc(i64 16, i32 1)
  %t202 = inttoptr i64 5 to ptr
  %t203 = getelementptr ptr, ptr %t201, i32 0
  store ptr %t202, ptr %t203
  %t204 = call ptr @__alloc(i64 8, i32 0)
  %t205 = inttoptr i64 0 to ptr
  %t206 = getelementptr ptr, ptr %t204, i32 0
  store ptr %t205, ptr %t206
  %t207 = getelementptr ptr, ptr %t201, i32 1
  store ptr %t204, ptr %t207
  %t208 = getelementptr ptr, ptr %t197, i32 2
  store ptr %t201, ptr %t208
  br label %case.end.3.196
case.end.3.196:
  br label %case.join.194
case.arm.4.209:
  %t211 = call ptr @__alloc(i64 24, i32 2)
  %t212 = inttoptr i64 7 to ptr
  %t213 = getelementptr ptr, ptr %t211, i32 0
  store ptr %t212, ptr %t213
  %t214 = getelementptr ptr, ptr %t189, i32 1
  %t215 = load ptr, ptr %t214
  call void @__inc_ref(ptr %t215)
  %t216 = getelementptr ptr, ptr %t211, i32 1
  store ptr %t215, ptr %t216
  %t217 = call ptr @__alloc(i64 16, i32 1)
  %t218 = inttoptr i64 5 to ptr
  %t219 = getelementptr ptr, ptr %t217, i32 0
  store ptr %t218, ptr %t219
  %t220 = call ptr @__alloc(i64 8, i32 0)
  %t221 = inttoptr i64 0 to ptr
  %t222 = getelementptr ptr, ptr %t220, i32 0
  store ptr %t221, ptr %t222
  %t223 = getelementptr ptr, ptr %t217, i32 1
  store ptr %t220, ptr %t223
  %t224 = getelementptr ptr, ptr %t211, i32 2
  store ptr %t217, ptr %t224
  br label %case.end.4.210
case.end.4.210:
  br label %case.join.194
case.default.193:
  unreachable
case.join.194:
  %t225 = phi ptr [ %t197, %case.end.3.196 ], [ %t211, %case.end.4.210 ]
  call void @__free_recursive(ptr %t189)
  br label %join.end.226
join.end.226:
  br label %join.after.1
join.after.1:
  %t227 = phi ptr [ %t10, %join.val.22 ], [ %t225, %join.end.226 ]
  ret ptr %t227
}

define i32 @main(i32 %argc, ptr %argv) {
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
