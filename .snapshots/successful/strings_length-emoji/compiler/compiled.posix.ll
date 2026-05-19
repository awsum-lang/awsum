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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"=ok" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"=FAIL(expected=" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [6 x i8]} { i32 0, i32 0, i32 0, i32 6, i32 6, [6 x i8] c", got=" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c")" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 2, [4 x i8] c"\F0\9F\94\A5" }
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [16 x i8]} { i32 0, i32 0, i32 0, i32 16, i32 16, [16 x i8] c"lengthCodePoints" }
@.str.6 = private unnamed_addr constant {i32, i32, i32, i32, i32, [20 x i8]} { i32 0, i32 0, i32 0, i32 20, i32 20, [20 x i8] c"lengthUtf16CodeUnits" }
@.str.7 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"lengthUtf8Bytes" }
@.str.8 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c", " }
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
  %stl_tag = inttoptr i64 16 to ptr
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


define internal ptr @__eqUInt32(ptr %a, ptr %b) {
  %va = load i32, ptr %a
  %vb = load i32, ptr %b
  %eq = icmp eq i32 %va, %vb
  %tag = select i1 %eq, i64 1, i64 2
  %box = call ptr @__alloc(i64 8, i32 0)
  %tag_ptr = inttoptr i64 %tag to ptr
  store ptr %tag_ptr, ptr %box
  call void @__free_recursive(ptr %a)
  call void @__free_recursive(ptr %b)
  ret ptr %box
}


define internal ptr @__lengthCodePoints(ptr %s) {
entry:
  %total_bytes = load i32, ptr %s
  %total_bytes_64 = zext i32 %total_bytes to i64
  %payload = getelementptr i8, ptr %s, i64 8
  %i_p = alloca i64, align 8
  store i64 0, ptr %i_p
  %n_p = alloca i32, align 4
  store i32 0, ptr %n_p
  br label %head
head:
  %i = load i64, ptr %i_p
  %at_end = icmp uge i64 %i, %total_bytes_64
  br i1 %at_end, label %done, label %body
body:
  %bp = getelementptr i8, ptr %payload, i64 %i
  %b = load i8, ptr %bp
  %bz = zext i8 %b to i32
  %top2 = and i32 %bz, 192
  %is_cont = icmp eq i32 %top2, 128
  br i1 %is_cont, label %step, label %inc
inc:
  %n0 = load i32, ptr %n_p
  %n1 = add i32 %n0, 1
  store i32 %n1, ptr %n_p
  br label %step
step:
  %i1 = add i64 %i, 1
  store i64 %i1, ptr %i_p
  br label %head
done:
  %nf = load i32, ptr %n_p
  %box = call ptr @__alloc(i64 4, i32 0)
  store i32 %nf, ptr %box
  call void @__free_recursive(ptr %s)
  ret ptr %box
}


define internal ptr @__lengthUtf16CodeUnits(ptr %s) {
  %u16p = getelementptr i8, ptr %s, i64 4
  %u16 = load i32, ptr %u16p
  %box = call ptr @__alloc(i64 4, i32 0)
  store i32 %u16, ptr %box
  call void @__free_recursive(ptr %s)
  ret ptr %box
}


define internal ptr @__lengthUtf8Bytes(ptr %s) {
  %len32 = load i32, ptr %s
  %box = call ptr @__alloc(i64 4, i32 0)
  store i32 %len32, ptr %box
  call void @__free_recursive(ptr %s)
  ret ptr %box
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

define internal ptr @v_check(ptr %v_expected, ptr %v_actual, ptr %v_label) {
  call void @__inc_ref(ptr %v_expected)
  call void @__inc_ref(ptr %v_actual)
  %t0 = call ptr @__eqUInt32(ptr %v_expected, ptr %v_actual)
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 1, label %case.arm.1.5 i64 2, label %case.arm.2.7 ]
case.arm.1.5:
  call void @__inc_ref(ptr %v_label)
  %t6 = call ptr @__concat(ptr %v_label, ptr getelementptr inbounds (i8, ptr @.str.0, i64 12))
  call void @__free_recursive(ptr %t0)
  call void @__free_recursive(ptr %v_expected)
  call void @__free_recursive(ptr %v_actual)
  call void @__free_recursive(ptr %v_label)
  ret ptr %t6
case.arm.2.7:
  call void @__inc_ref(ptr %v_label)
  %t8 = call ptr @__concat(ptr %v_label, ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  %t9 = getelementptr ptr, ptr %t8, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %case.default.12 [ i64 3, label %case.arm.3.13 i64 4, label %case.arm.4.20 ]
case.arm.3.13:
  %t14 = getelementptr ptr, ptr %t8, i32 1
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 3 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  call void @__inc_ref(ptr %t15)
  %t19 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t15, ptr %t19
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t0)
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %v_expected)
  call void @__free_recursive(ptr %v_actual)
  call void @__free_recursive(ptr %v_label)
  ret ptr %t16
case.arm.4.20:
  %t21 = getelementptr ptr, ptr %t8, i32 1
  %t22 = load ptr, ptr %t21
  call void @__inc_ref(ptr %t22)
  call void @__inc_ref(ptr %t22)
  call void @__inc_ref(ptr %v_expected)
  %t23 = call ptr @__showUInt32(ptr %v_expected)
  %t24 = call ptr @__concat(ptr %t22, ptr %t23)
  %t25 = getelementptr ptr, ptr %t24, i32 0
  %t26 = load ptr, ptr %t25
  %t27 = ptrtoint ptr %t26 to i64
  switch i64 %t27, label %case.default.28 [ i64 3, label %case.arm.3.29 i64 4, label %case.arm.4.36 ]
case.arm.3.29:
  %t30 = getelementptr ptr, ptr %t24, i32 1
  %t31 = load ptr, ptr %t30
  call void @__inc_ref(ptr %t31)
  %t32 = call ptr @__alloc(i64 16, i32 1)
  %t33 = inttoptr i64 3 to ptr
  %t34 = getelementptr ptr, ptr %t32, i32 0
  store ptr %t33, ptr %t34
  call void @__inc_ref(ptr %t31)
  %t35 = getelementptr ptr, ptr %t32, i32 1
  store ptr %t31, ptr %t35
  call void @__free_recursive(ptr %t24)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t0)
  call void @__free_recursive(ptr %t31)
  call void @__free_recursive(ptr %t22)
  call void @__free_recursive(ptr %v_expected)
  call void @__free_recursive(ptr %v_actual)
  call void @__free_recursive(ptr %v_label)
  ret ptr %t32
case.arm.4.36:
  %t37 = getelementptr ptr, ptr %t24, i32 1
  %t38 = load ptr, ptr %t37
  call void @__inc_ref(ptr %t38)
  call void @__inc_ref(ptr %t38)
  %t39 = call ptr @__concat(ptr %t38, ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
  %t40 = getelementptr ptr, ptr %t39, i32 0
  %t41 = load ptr, ptr %t40
  %t42 = ptrtoint ptr %t41 to i64
  switch i64 %t42, label %case.default.43 [ i64 3, label %case.arm.3.44 i64 4, label %case.arm.4.51 ]
case.arm.3.44:
  %t45 = getelementptr ptr, ptr %t39, i32 1
  %t46 = load ptr, ptr %t45
  call void @__inc_ref(ptr %t46)
  %t47 = call ptr @__alloc(i64 16, i32 1)
  %t48 = inttoptr i64 3 to ptr
  %t49 = getelementptr ptr, ptr %t47, i32 0
  store ptr %t48, ptr %t49
  call void @__inc_ref(ptr %t46)
  %t50 = getelementptr ptr, ptr %t47, i32 1
  store ptr %t46, ptr %t50
  call void @__free_recursive(ptr %t39)
  call void @__free_recursive(ptr %t24)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t0)
  call void @__free_recursive(ptr %t46)
  call void @__free_recursive(ptr %t38)
  call void @__free_recursive(ptr %t22)
  call void @__free_recursive(ptr %v_expected)
  call void @__free_recursive(ptr %v_actual)
  call void @__free_recursive(ptr %v_label)
  ret ptr %t47
case.arm.4.51:
  %t52 = getelementptr ptr, ptr %t39, i32 1
  %t53 = load ptr, ptr %t52
  call void @__inc_ref(ptr %t53)
  call void @__inc_ref(ptr %t53)
  call void @__inc_ref(ptr %v_actual)
  %t54 = call ptr @__showUInt32(ptr %v_actual)
  %t55 = call ptr @__concat(ptr %t53, ptr %t54)
  %t56 = getelementptr ptr, ptr %t55, i32 0
  %t57 = load ptr, ptr %t56
  %t58 = ptrtoint ptr %t57 to i64
  switch i64 %t58, label %case.default.59 [ i64 3, label %case.arm.3.60 i64 4, label %case.arm.4.67 ]
case.arm.3.60:
  %t61 = getelementptr ptr, ptr %t55, i32 1
  %t62 = load ptr, ptr %t61
  call void @__inc_ref(ptr %t62)
  %t63 = call ptr @__alloc(i64 16, i32 1)
  %t64 = inttoptr i64 3 to ptr
  %t65 = getelementptr ptr, ptr %t63, i32 0
  store ptr %t64, ptr %t65
  call void @__inc_ref(ptr %t62)
  %t66 = getelementptr ptr, ptr %t63, i32 1
  store ptr %t62, ptr %t66
  call void @__free_recursive(ptr %t55)
  call void @__free_recursive(ptr %t39)
  call void @__free_recursive(ptr %t24)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t0)
  call void @__free_recursive(ptr %t62)
  call void @__free_recursive(ptr %t53)
  call void @__free_recursive(ptr %t38)
  call void @__free_recursive(ptr %t22)
  call void @__free_recursive(ptr %v_expected)
  call void @__free_recursive(ptr %v_actual)
  call void @__free_recursive(ptr %v_label)
  ret ptr %t63
case.arm.4.67:
  %t68 = getelementptr ptr, ptr %t55, i32 1
  %t69 = load ptr, ptr %t68
  call void @__inc_ref(ptr %t69)
  call void @__inc_ref(ptr %t69)
  %t70 = call ptr @__concat(ptr %t69, ptr getelementptr inbounds (i8, ptr @.str.3, i64 12))
  call void @__free_recursive(ptr %t55)
  call void @__free_recursive(ptr %t39)
  call void @__free_recursive(ptr %t24)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t0)
  call void @__free_recursive(ptr %t69)
  call void @__free_recursive(ptr %t53)
  call void @__free_recursive(ptr %t38)
  call void @__free_recursive(ptr %t22)
  call void @__free_recursive(ptr %v_expected)
  call void @__free_recursive(ptr %v_actual)
  call void @__free_recursive(ptr %v_label)
  ret ptr %t70
case.default.59:
  unreachable
case.default.43:
  unreachable
case.default.28:
  unreachable
case.default.12:
  unreachable
case.default.4:
  unreachable
}

define internal ptr @v_run() {
  %t0 = call ptr @__alloc(i64 4, i32 0)
  store i32 1, ptr %t0
  %t1 = call ptr @__lengthCodePoints(ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  %t2 = call ptr @v_check(ptr %t0, ptr %t1, ptr getelementptr inbounds (i8, ptr @.str.5, i64 12))
  %t3 = getelementptr ptr, ptr %t2, i32 0
  %t4 = load ptr, ptr %t3
  %t5 = ptrtoint ptr %t4 to i64
  switch i64 %t5, label %case.default.6 [ i64 3, label %case.arm.3.8 i64 4, label %case.arm.4.16 ]
case.arm.3.8:
  %t10 = getelementptr ptr, ptr %t2, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  %t12 = call ptr @__alloc(i64 16, i32 1)
  %t13 = inttoptr i64 3 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  call void @__inc_ref(ptr %t11)
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t11, ptr %t15
  br label %case.end.3.9
case.end.3.9:
  br label %case.join.7
case.arm.4.16:
  %t18 = getelementptr ptr, ptr %t2, i32 1
  %t19 = load ptr, ptr %t18
  call void @__inc_ref(ptr %t19)
  %t20 = call ptr @__alloc(i64 4, i32 0)
  store i32 2, ptr %t20
  %t21 = call ptr @__lengthUtf16CodeUnits(ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  %t22 = call ptr @v_check(ptr %t20, ptr %t21, ptr getelementptr inbounds (i8, ptr @.str.6, i64 12))
  %t23 = getelementptr ptr, ptr %t22, i32 0
  %t24 = load ptr, ptr %t23
  %t25 = ptrtoint ptr %t24 to i64
  switch i64 %t25, label %case.default.26 [ i64 3, label %case.arm.3.28 i64 4, label %case.arm.4.36 ]
case.arm.3.28:
  %t30 = getelementptr ptr, ptr %t22, i32 1
  %t31 = load ptr, ptr %t30
  call void @__inc_ref(ptr %t31)
  %t32 = call ptr @__alloc(i64 16, i32 1)
  %t33 = inttoptr i64 3 to ptr
  %t34 = getelementptr ptr, ptr %t32, i32 0
  store ptr %t33, ptr %t34
  call void @__inc_ref(ptr %t31)
  %t35 = getelementptr ptr, ptr %t32, i32 1
  store ptr %t31, ptr %t35
  br label %case.end.3.29
case.end.3.29:
  br label %case.join.27
case.arm.4.36:
  %t38 = getelementptr ptr, ptr %t22, i32 1
  %t39 = load ptr, ptr %t38
  call void @__inc_ref(ptr %t39)
  %t40 = call ptr @__alloc(i64 4, i32 0)
  store i32 4, ptr %t40
  %t41 = call ptr @__lengthUtf8Bytes(ptr getelementptr inbounds (i8, ptr @.str.4, i64 12))
  %t42 = call ptr @v_check(ptr %t40, ptr %t41, ptr getelementptr inbounds (i8, ptr @.str.7, i64 12))
  %t43 = getelementptr ptr, ptr %t42, i32 0
  %t44 = load ptr, ptr %t43
  %t45 = ptrtoint ptr %t44 to i64
  switch i64 %t45, label %case.default.46 [ i64 3, label %case.arm.3.48 i64 4, label %case.arm.4.56 ]
case.arm.3.48:
  %t50 = getelementptr ptr, ptr %t42, i32 1
  %t51 = load ptr, ptr %t50
  call void @__inc_ref(ptr %t51)
  %t52 = call ptr @__alloc(i64 16, i32 1)
  %t53 = inttoptr i64 3 to ptr
  %t54 = getelementptr ptr, ptr %t52, i32 0
  store ptr %t53, ptr %t54
  call void @__inc_ref(ptr %t51)
  %t55 = getelementptr ptr, ptr %t52, i32 1
  store ptr %t51, ptr %t55
  br label %case.end.3.49
case.end.3.49:
  br label %case.join.47
case.arm.4.56:
  %t58 = getelementptr ptr, ptr %t42, i32 1
  %t59 = load ptr, ptr %t58
  call void @__inc_ref(ptr %t59)
  call void @__inc_ref(ptr %t19)
  %t60 = call ptr @__concat(ptr %t19, ptr getelementptr inbounds (i8, ptr @.str.8, i64 12))
  %t61 = getelementptr ptr, ptr %t60, i32 0
  %t62 = load ptr, ptr %t61
  %t63 = ptrtoint ptr %t62 to i64
  switch i64 %t63, label %case.default.64 [ i64 3, label %case.arm.3.66 i64 4, label %case.arm.4.74 ]
case.arm.3.66:
  %t68 = getelementptr ptr, ptr %t60, i32 1
  %t69 = load ptr, ptr %t68
  call void @__inc_ref(ptr %t69)
  %t70 = call ptr @__alloc(i64 16, i32 1)
  %t71 = inttoptr i64 3 to ptr
  %t72 = getelementptr ptr, ptr %t70, i32 0
  store ptr %t71, ptr %t72
  call void @__inc_ref(ptr %t69)
  %t73 = getelementptr ptr, ptr %t70, i32 1
  store ptr %t69, ptr %t73
  br label %case.end.3.67
case.end.3.67:
  br label %case.join.65
case.arm.4.74:
  %t76 = getelementptr ptr, ptr %t60, i32 1
  %t77 = load ptr, ptr %t76
  call void @__inc_ref(ptr %t77)
  call void @__inc_ref(ptr %t77)
  call void @__inc_ref(ptr %t39)
  %t78 = call ptr @__concat(ptr %t77, ptr %t39)
  %t79 = getelementptr ptr, ptr %t78, i32 0
  %t80 = load ptr, ptr %t79
  %t81 = ptrtoint ptr %t80 to i64
  switch i64 %t81, label %case.default.82 [ i64 3, label %case.arm.3.84 i64 4, label %case.arm.4.92 ]
case.arm.3.84:
  %t86 = getelementptr ptr, ptr %t78, i32 1
  %t87 = load ptr, ptr %t86
  call void @__inc_ref(ptr %t87)
  %t88 = call ptr @__alloc(i64 16, i32 1)
  %t89 = inttoptr i64 3 to ptr
  %t90 = getelementptr ptr, ptr %t88, i32 0
  store ptr %t89, ptr %t90
  call void @__inc_ref(ptr %t87)
  %t91 = getelementptr ptr, ptr %t88, i32 1
  store ptr %t87, ptr %t91
  br label %case.end.3.85
case.end.3.85:
  br label %case.join.83
case.arm.4.92:
  %t94 = getelementptr ptr, ptr %t78, i32 1
  %t95 = load ptr, ptr %t94
  call void @__inc_ref(ptr %t95)
  call void @__inc_ref(ptr %t95)
  %t96 = call ptr @__concat(ptr %t95, ptr getelementptr inbounds (i8, ptr @.str.8, i64 12))
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
  call void @__inc_ref(ptr %t113)
  call void @__inc_ref(ptr %t59)
  %t114 = call ptr @__concat(ptr %t113, ptr %t59)
  br label %case.end.4.111
case.end.4.111:
  br label %case.join.101
case.default.100:
  unreachable
case.join.101:
  %t115 = phi ptr [%t106, %case.end.3.103], [%t114, %case.end.4.111]
  call void @__free_recursive(ptr %t96)
  br label %case.end.4.93
case.end.4.93:
  br label %case.join.83
case.default.82:
  unreachable
case.join.83:
  %t116 = phi ptr [%t88, %case.end.3.85], [%t115, %case.end.4.93]
  call void @__free_recursive(ptr %t78)
  br label %case.end.4.75
case.end.4.75:
  br label %case.join.65
case.default.64:
  unreachable
case.join.65:
  %t117 = phi ptr [%t70, %case.end.3.67], [%t116, %case.end.4.75]
  call void @__free_recursive(ptr %t60)
  br label %case.end.4.57
case.end.4.57:
  br label %case.join.47
case.default.46:
  unreachable
case.join.47:
  %t118 = phi ptr [%t52, %case.end.3.49], [%t117, %case.end.4.57]
  call void @__free_recursive(ptr %t42)
  br label %case.end.4.37
case.end.4.37:
  br label %case.join.27
case.default.26:
  unreachable
case.join.27:
  %t119 = phi ptr [%t32, %case.end.3.29], [%t118, %case.end.4.37]
  call void @__free_recursive(ptr %t22)
  br label %case.end.4.17
case.end.4.17:
  br label %case.join.7
case.default.6:
  unreachable
case.join.7:
  %t120 = phi ptr [%t12, %case.end.3.9], [%t119, %case.end.4.17]
  call void @__free_recursive(ptr %t2)
  ret ptr %t120
}

define internal ptr @v_main() {
  %t0 = call ptr @v_run()
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 3, label %case.arm.3.6 i64 4, label %case.arm.4.22 ]
case.arm.3.6:
  %t8 = getelementptr ptr, ptr %t0, i32 1
  %t9 = load ptr, ptr %t8
  call void @__inc_ref(ptr %t9)
  %t10 = call ptr @__alloc(i64 24, i32 2)
  %t11 = inttoptr i64 7 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  %t13 = getelementptr ptr, ptr %t10, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.9, i64 12), ptr %t13
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
  br label %case.end.3.7
case.end.3.7:
  br label %case.join.5
case.arm.4.22:
  %t24 = getelementptr ptr, ptr %t0, i32 1
  %t25 = load ptr, ptr %t24
  call void @__inc_ref(ptr %t25)
  %t26 = call ptr @__alloc(i64 24, i32 2)
  %t27 = inttoptr i64 7 to ptr
  %t28 = getelementptr ptr, ptr %t26, i32 0
  store ptr %t27, ptr %t28
  call void @__inc_ref(ptr %t25)
  %t29 = getelementptr ptr, ptr %t26, i32 1
  store ptr %t25, ptr %t29
  %t30 = call ptr @__alloc(i64 16, i32 1)
  %t31 = inttoptr i64 5 to ptr
  %t32 = getelementptr ptr, ptr %t30, i32 0
  store ptr %t31, ptr %t32
  %t33 = call ptr @__alloc(i64 8, i32 0)
  %t34 = inttoptr i64 0 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = getelementptr ptr, ptr %t30, i32 1
  store ptr %t33, ptr %t36
  %t37 = getelementptr ptr, ptr %t26, i32 2
  store ptr %t30, ptr %t37
  br label %case.end.4.23
case.end.4.23:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t38 = phi ptr [%t10, %case.end.3.7], [%t26, %case.end.4.23]
  call void @__free_recursive(ptr %t0)
  ret ptr %t38
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
