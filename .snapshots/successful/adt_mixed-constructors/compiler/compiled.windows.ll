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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"word:" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"num:" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"," }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"<eof>" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"hello" }
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"42" }
@.str.6 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c" " }
@.str.7 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }

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

define internal ptr @v_showToken(ptr %v_token) {
  %t0 = getelementptr ptr, ptr %v_token, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 22, label %case.arm.22.4 i64 23, label %case.arm.23.8 i64 24, label %case.arm.24.12 i64 25, label %case.arm.25.17 ]
case.arm.22.4:
  %t5 = getelementptr ptr, ptr %v_token, i32 1
  %t6 = load ptr, ptr %t5
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t6)
  %t7 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %v_token)
  ret ptr %t7
case.arm.23.8:
  %t9 = getelementptr ptr, ptr %v_token, i32 1
  %t10 = load ptr, ptr %t9
  call void @__inc_ref(ptr %t10)
  call void @__inc_ref(ptr %t10)
  %t11 = call ptr @__concat(ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t10)
  call void @__free_recursive(ptr %t10)
  call void @__free_recursive(ptr %v_token)
  ret ptr %t11
case.arm.24.12:
  %t13 = call ptr @__alloc(i64 16, i32 1)
  %t14 = inttoptr i64 4 to ptr
  %t15 = getelementptr ptr, ptr %t13, i32 0
  store ptr %t14, ptr %t15
  %t16 = getelementptr ptr, ptr %t13, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t16
  call void @__free_recursive(ptr %v_token)
  ret ptr %t13
case.arm.25.17:
  %t18 = call ptr @__alloc(i64 16, i32 1)
  %t19 = inttoptr i64 4 to ptr
  %t20 = getelementptr ptr, ptr %t18, i32 0
  store ptr %t19, ptr %t20
  %t21 = getelementptr ptr, ptr %t18, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t21
  call void @__free_recursive(ptr %v_token)
  ret ptr %t18
case.default.3:
  unreachable
}

define internal ptr @v_main() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 22 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t3
  %t4 = call ptr @v_showToken(ptr %t0)
  %t5 = getelementptr ptr, ptr %t4, i32 0
  %t6 = load ptr, ptr %t5
  %t7 = ptrtoint ptr %t6 to i64
  switch i64 %t7, label %case.default.8 [ i64 3, label %case.arm.3.10 i64 4, label %case.arm.4.18 ]
case.arm.3.10:
  %t12 = getelementptr ptr, ptr %t4, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  %t14 = call ptr @__alloc(i64 16, i32 1)
  %t15 = inttoptr i64 3 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  call void @__inc_ref(ptr %t13)
  %t17 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t13, ptr %t17
  br label %case.end.3.11
case.end.3.11:
  br label %case.join.9
case.arm.4.18:
  %t20 = getelementptr ptr, ptr %t4, i32 1
  %t21 = load ptr, ptr %t20
  call void @__inc_ref(ptr %t21)
  %t22 = call ptr @__alloc(i64 8, i32 0)
  %t23 = inttoptr i64 24 to ptr
  %t24 = getelementptr ptr, ptr %t22, i32 0
  store ptr %t23, ptr %t24
  %t25 = call ptr @v_showToken(ptr %t22)
  %t26 = getelementptr ptr, ptr %t25, i32 0
  %t27 = load ptr, ptr %t26
  %t28 = ptrtoint ptr %t27 to i64
  switch i64 %t28, label %case.default.29 [ i64 3, label %case.arm.3.31 i64 4, label %case.arm.4.39 ]
case.arm.3.31:
  %t33 = getelementptr ptr, ptr %t25, i32 1
  %t34 = load ptr, ptr %t33
  call void @__inc_ref(ptr %t34)
  %t35 = call ptr @__alloc(i64 16, i32 1)
  %t36 = inttoptr i64 3 to ptr
  %t37 = getelementptr ptr, ptr %t35, i32 0
  store ptr %t36, ptr %t37
  call void @__inc_ref(ptr %t34)
  %t38 = getelementptr ptr, ptr %t35, i32 1
  store ptr %t34, ptr %t38
  br label %case.end.3.32
case.end.3.32:
  br label %case.join.30
case.arm.4.39:
  %t41 = getelementptr ptr, ptr %t25, i32 1
  %t42 = load ptr, ptr %t41
  call void @__inc_ref(ptr %t42)
  %t43 = call ptr @__alloc(i64 16, i32 1)
  %t44 = inttoptr i64 23 to ptr
  %t45 = getelementptr ptr, ptr %t43, i32 0
  store ptr %t44, ptr %t45
  %t46 = getelementptr ptr, ptr %t43, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.5, i64 12), ptr %t46
  %t47 = call ptr @v_showToken(ptr %t43)
  %t48 = getelementptr ptr, ptr %t47, i32 0
  %t49 = load ptr, ptr %t48
  %t50 = ptrtoint ptr %t49 to i64
  switch i64 %t50, label %case.default.51 [ i64 3, label %case.arm.3.53 i64 4, label %case.arm.4.61 ]
case.arm.3.53:
  %t55 = getelementptr ptr, ptr %t47, i32 1
  %t56 = load ptr, ptr %t55
  call void @__inc_ref(ptr %t56)
  %t57 = call ptr @__alloc(i64 16, i32 1)
  %t58 = inttoptr i64 3 to ptr
  %t59 = getelementptr ptr, ptr %t57, i32 0
  store ptr %t58, ptr %t59
  call void @__inc_ref(ptr %t56)
  %t60 = getelementptr ptr, ptr %t57, i32 1
  store ptr %t56, ptr %t60
  br label %case.end.3.54
case.end.3.54:
  br label %case.join.52
case.arm.4.61:
  %t63 = getelementptr ptr, ptr %t47, i32 1
  %t64 = load ptr, ptr %t63
  call void @__inc_ref(ptr %t64)
  %t65 = call ptr @__alloc(i64 8, i32 0)
  %t66 = inttoptr i64 25 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  %t68 = call ptr @v_showToken(ptr %t65)
  %t69 = getelementptr ptr, ptr %t68, i32 0
  %t70 = load ptr, ptr %t69
  %t71 = ptrtoint ptr %t70 to i64
  switch i64 %t71, label %case.default.72 [ i64 3, label %case.arm.3.74 i64 4, label %case.arm.4.82 ]
case.arm.3.74:
  %t76 = getelementptr ptr, ptr %t68, i32 1
  %t77 = load ptr, ptr %t76
  call void @__inc_ref(ptr %t77)
  %t78 = call ptr @__alloc(i64 16, i32 1)
  %t79 = inttoptr i64 3 to ptr
  %t80 = getelementptr ptr, ptr %t78, i32 0
  store ptr %t79, ptr %t80
  call void @__inc_ref(ptr %t77)
  %t81 = getelementptr ptr, ptr %t78, i32 1
  store ptr %t77, ptr %t81
  br label %case.end.3.75
case.end.3.75:
  br label %case.join.73
case.arm.4.82:
  %t84 = getelementptr ptr, ptr %t68, i32 1
  %t85 = load ptr, ptr %t84
  call void @__inc_ref(ptr %t85)
  call void @__inc_ref(ptr %t21)
  %t86 = call ptr @__concat(ptr %t21, ptr getelementptr inbounds (i8, ptr @.str.6, i64 12))
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
  call void @__inc_ref(ptr %t42)
  %t104 = call ptr @__concat(ptr %t103, ptr %t42)
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
  %t122 = call ptr @__concat(ptr %t121, ptr getelementptr inbounds (i8, ptr @.str.6, i64 12))
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
  call void @__inc_ref(ptr %t64)
  %t140 = call ptr @__concat(ptr %t139, ptr %t64)
  %t141 = getelementptr ptr, ptr %t140, i32 0
  %t142 = load ptr, ptr %t141
  %t143 = ptrtoint ptr %t142 to i64
  switch i64 %t143, label %case.default.144 [ i64 3, label %case.arm.3.146 i64 4, label %case.arm.4.154 ]
case.arm.3.146:
  %t148 = getelementptr ptr, ptr %t140, i32 1
  %t149 = load ptr, ptr %t148
  call void @__inc_ref(ptr %t149)
  %t150 = call ptr @__alloc(i64 16, i32 1)
  %t151 = inttoptr i64 3 to ptr
  %t152 = getelementptr ptr, ptr %t150, i32 0
  store ptr %t151, ptr %t152
  call void @__inc_ref(ptr %t149)
  %t153 = getelementptr ptr, ptr %t150, i32 1
  store ptr %t149, ptr %t153
  br label %case.end.3.147
case.end.3.147:
  br label %case.join.145
case.arm.4.154:
  %t156 = getelementptr ptr, ptr %t140, i32 1
  %t157 = load ptr, ptr %t156
  call void @__inc_ref(ptr %t157)
  call void @__inc_ref(ptr %t157)
  %t158 = call ptr @__concat(ptr %t157, ptr getelementptr inbounds (i8, ptr @.str.6, i64 12))
  %t159 = getelementptr ptr, ptr %t158, i32 0
  %t160 = load ptr, ptr %t159
  %t161 = ptrtoint ptr %t160 to i64
  switch i64 %t161, label %case.default.162 [ i64 3, label %case.arm.3.164 i64 4, label %case.arm.4.172 ]
case.arm.3.164:
  %t166 = getelementptr ptr, ptr %t158, i32 1
  %t167 = load ptr, ptr %t166
  call void @__inc_ref(ptr %t167)
  %t168 = call ptr @__alloc(i64 16, i32 1)
  %t169 = inttoptr i64 3 to ptr
  %t170 = getelementptr ptr, ptr %t168, i32 0
  store ptr %t169, ptr %t170
  call void @__inc_ref(ptr %t167)
  %t171 = getelementptr ptr, ptr %t168, i32 1
  store ptr %t167, ptr %t171
  br label %case.end.3.165
case.end.3.165:
  br label %case.join.163
case.arm.4.172:
  %t174 = getelementptr ptr, ptr %t158, i32 1
  %t175 = load ptr, ptr %t174
  call void @__inc_ref(ptr %t175)
  call void @__inc_ref(ptr %t175)
  call void @__inc_ref(ptr %t85)
  %t176 = call ptr @__concat(ptr %t175, ptr %t85)
  br label %case.end.4.173
case.end.4.173:
  br label %case.join.163
case.default.162:
  unreachable
case.join.163:
  %t177 = phi ptr [%t168, %case.end.3.165], [%t176, %case.end.4.173]
  call void @__free_recursive(ptr %t158)
  br label %case.end.4.155
case.end.4.155:
  br label %case.join.145
case.default.144:
  unreachable
case.join.145:
  %t178 = phi ptr [%t150, %case.end.3.147], [%t177, %case.end.4.155]
  call void @__free_recursive(ptr %t140)
  br label %case.end.4.137
case.end.4.137:
  br label %case.join.127
case.default.126:
  unreachable
case.join.127:
  %t179 = phi ptr [%t132, %case.end.3.129], [%t178, %case.end.4.137]
  call void @__free_recursive(ptr %t122)
  br label %case.end.4.119
case.end.4.119:
  br label %case.join.109
case.default.108:
  unreachable
case.join.109:
  %t180 = phi ptr [%t114, %case.end.3.111], [%t179, %case.end.4.119]
  call void @__free_recursive(ptr %t104)
  br label %case.end.4.101
case.end.4.101:
  br label %case.join.91
case.default.90:
  unreachable
case.join.91:
  %t181 = phi ptr [%t96, %case.end.3.93], [%t180, %case.end.4.101]
  call void @__free_recursive(ptr %t86)
  br label %case.end.4.83
case.end.4.83:
  br label %case.join.73
case.default.72:
  unreachable
case.join.73:
  %t182 = phi ptr [%t78, %case.end.3.75], [%t181, %case.end.4.83]
  call void @__free_recursive(ptr %t68)
  br label %case.end.4.62
case.end.4.62:
  br label %case.join.52
case.default.51:
  unreachable
case.join.52:
  %t183 = phi ptr [%t57, %case.end.3.54], [%t182, %case.end.4.62]
  call void @__free_recursive(ptr %t47)
  br label %case.end.4.40
case.end.4.40:
  br label %case.join.30
case.default.29:
  unreachable
case.join.30:
  %t184 = phi ptr [%t35, %case.end.3.32], [%t183, %case.end.4.40]
  call void @__free_recursive(ptr %t25)
  br label %case.end.4.19
case.end.4.19:
  br label %case.join.9
case.default.8:
  unreachable
case.join.9:
  %t185 = phi ptr [%t14, %case.end.3.11], [%t184, %case.end.4.19]
  call void @__free_recursive(ptr %t4)
  %t186 = call ptr @v__let_15(ptr %t185)
  ret ptr %t186
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
  store ptr getelementptr inbounds (i8, ptr @.str.7, i64 12), ptr %t10
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

declare i32 @_setmode(i32, i32)

define i32 @main(i32 %argc_posix, ptr %argv_posix) {
entry:
  call i32 @_setmode(i32 1, i32 32768)
  call i32 @_setmode(i32 0, i32 32768)
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
