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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [6 x i8]} { i32 0, i32 0, i32 0, i32 6, i32 6, [6 x i8] c"strErr" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"=" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"\0A" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [11 x i8]} { i32 0, i32 0, i32 0, i32 11, i32 11, [11 x i8] c"defBodyLeft" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"ErrA" }
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"ErrB" }
@.str.6 = private unnamed_addr constant {i32, i32, i32, i32, i32, [8 x i8]} { i32 0, i32 0, i32 0, i32 8, i32 8, [8 x i8] c"strWiden" }
@.str.7 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"nestedJustFalse" }
@.str.8 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"First" }
@.str.9 = private unnamed_addr constant {i32, i32, i32, i32, i32, [6 x i8]} { i32 0, i32 0, i32 0, i32 6, i32 6, [6 x i8] c"Second" }
@.str.10 = private unnamed_addr constant {i32, i32, i32, i32, i32, [14 x i8]} { i32 0, i32 0, i32 0, i32 14, i32 14, [14 x i8] c"nestedJustTrue" }
@.str.11 = private unnamed_addr constant {i32, i32, i32, i32, i32, [13 x i8]} { i32 0, i32 0, i32 0, i32 13, i32 13, [13 x i8] c"nestedNothing" }
@.str.12 = private unnamed_addr constant {i32, i32, i32, i32, i32, [9 x i8]} { i32 0, i32 0, i32 0, i32 9, i32 9, [9 x i8] c"caseFalse" }
@.str.13 = private unnamed_addr constant {i32, i32, i32, i32, i32, [8 x i8]} { i32 0, i32 0, i32 0, i32 8, i32 8, [8 x i8] c"caseTrue" }
@.str.14 = private unnamed_addr constant {i32, i32, i32, i32, i32, [7 x i8]} { i32 0, i32 0, i32 0, i32 7, i32 7, [7 x i8] c"letBody" }
@.str.15 = private unnamed_addr constant {i32, i32, i32, i32, i32, [12 x i8]} { i32 0, i32 0, i32 0, i32 12, i32 12, [12 x i8] c"defBodyRight" }
@.str.16 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }

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

define internal ptr @v_vErrA() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 3 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 8, i32 0)
  %t4 = inttoptr i64 24 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  ret ptr %t0
}

define internal ptr @v_vErrB() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 3 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 8, i32 0)
  %t4 = inttoptr i64 25 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  ret ptr %t0
}

define internal ptr @v_vOkA() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 4 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 4, i32 0)
  store i32 7, ptr %t3
  %t4 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t4
  ret ptr %t0
}

define internal ptr @v_vFirst() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 3 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 8, i32 0)
  %t4 = inttoptr i64 26 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  ret ptr %t0
}

define internal ptr @v_vSecond() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 3 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 8, i32 0)
  %t4 = inttoptr i64 27 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t6
  ret ptr %t0
}

define internal ptr @v_vStr() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 3 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t3
  ret ptr %t0
}

define internal ptr @v_defBodyLeft() {
  %t0 = call ptr @v_vErrA()
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 3, label %case.arm.3.6 i64 4, label %case.arm.4.18 ]
case.arm.3.6:
  %t8 = call ptr @__alloc(i64 16, i32 1)
  %t9 = inttoptr i64 3 to ptr
  %t10 = getelementptr ptr, ptr %t8, i32 0
  store ptr %t9, ptr %t10
  %t11 = call ptr @__alloc(i64 16, i32 1)
  %t12 = inttoptr i64 2252990199 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  %t14 = getelementptr ptr, ptr %t0, i32 1
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  %t16 = getelementptr ptr, ptr %t11, i32 1
  store ptr %t15, ptr %t16
  %t17 = getelementptr ptr, ptr %t8, i32 1
  store ptr %t11, ptr %t17
  br label %case.end.3.7
case.end.3.7:
  br label %case.join.5
case.arm.4.18:
  call void @__inc_ref(ptr %t0)
  br label %case.end.4.19
case.end.4.19:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t20 = phi ptr [ %t8, %case.end.3.7 ], [ %t0, %case.end.4.19 ]
  call void @__free_recursive(ptr %t0)
  ret ptr %t20
}

define internal ptr @v_defBodyRight() {
  %t0 = call ptr @v_vOkA()
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 3, label %case.arm.3.6 i64 4, label %case.arm.4.18 ]
case.arm.3.6:
  %t8 = call ptr @__alloc(i64 16, i32 1)
  %t9 = inttoptr i64 3 to ptr
  %t10 = getelementptr ptr, ptr %t8, i32 0
  store ptr %t9, ptr %t10
  %t11 = call ptr @__alloc(i64 16, i32 1)
  %t12 = inttoptr i64 2252990199 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  %t14 = getelementptr ptr, ptr %t0, i32 1
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  %t16 = getelementptr ptr, ptr %t11, i32 1
  store ptr %t15, ptr %t16
  %t17 = getelementptr ptr, ptr %t8, i32 1
  store ptr %t11, ptr %t17
  br label %case.end.3.7
case.end.3.7:
  br label %case.join.5
case.arm.4.18:
  call void @__inc_ref(ptr %t0)
  br label %case.end.4.19
case.end.4.19:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t20 = phi ptr [ %t8, %case.end.3.7 ], [ %t0, %case.end.4.19 ]
  call void @__free_recursive(ptr %t0)
  ret ptr %t20
}

define internal ptr @v_letBody() {
  %t0 = call ptr @v_vErrB()
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 3, label %case.arm.3.6 i64 4, label %case.arm.4.18 ]
case.arm.3.6:
  %t8 = call ptr @__alloc(i64 16, i32 1)
  %t9 = inttoptr i64 3 to ptr
  %t10 = getelementptr ptr, ptr %t8, i32 0
  store ptr %t9, ptr %t10
  %t11 = call ptr @__alloc(i64 16, i32 1)
  %t12 = inttoptr i64 2269767818 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  %t14 = getelementptr ptr, ptr %t0, i32 1
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  %t16 = getelementptr ptr, ptr %t11, i32 1
  store ptr %t15, ptr %t16
  %t17 = getelementptr ptr, ptr %t8, i32 1
  store ptr %t11, ptr %t17
  br label %case.end.3.7
case.end.3.7:
  br label %case.join.5
case.arm.4.18:
  call void @__inc_ref(ptr %t0)
  br label %case.end.4.19
case.end.4.19:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t20 = phi ptr [ %t8, %case.end.3.7 ], [ %t0, %case.end.4.19 ]
  call void @__free_recursive(ptr %t0)
  ret ptr %t20
}

define internal ptr @v_caseUnion(ptr %v_flag) {
  %t0 = getelementptr ptr, ptr %v_flag, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 1, label %case.arm.1.4 i64 2, label %case.arm.2.22 ]
case.arm.1.4:
  %t5 = call ptr @v_vErrA()
  %t6 = getelementptr ptr, ptr %t5, i32 0
  %t7 = load ptr, ptr %t6
  %t8 = ptrtoint ptr %t7 to i64
  switch i64 %t8, label %case.default.9 [ i64 3, label %case.arm.3.10 i64 4, label %case.arm.4.21 ]
case.arm.3.10:
  %t11 = call ptr @__alloc(i64 16, i32 1)
  %t12 = inttoptr i64 3 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  %t14 = call ptr @__alloc(i64 16, i32 1)
  %t15 = inttoptr i64 2252990199 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  %t17 = getelementptr ptr, ptr %t5, i32 1
  %t18 = load ptr, ptr %t17
  call void @__inc_ref(ptr %t18)
  %t19 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t18, ptr %t19
  %t20 = getelementptr ptr, ptr %t11, i32 1
  store ptr %t14, ptr %t20
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %v_flag)
  ret ptr %t11
case.arm.4.21:
  call void @__free_recursive(ptr %v_flag)
  ret ptr %t5
case.default.9:
  unreachable
case.arm.2.22:
  %t23 = call ptr @v_vErrB()
  %t24 = getelementptr ptr, ptr %t23, i32 0
  %t25 = load ptr, ptr %t24
  %t26 = ptrtoint ptr %t25 to i64
  switch i64 %t26, label %case.default.27 [ i64 3, label %case.arm.3.28 i64 4, label %case.arm.4.39 ]
case.arm.3.28:
  %t29 = call ptr @__alloc(i64 16, i32 1)
  %t30 = inttoptr i64 3 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = call ptr @__alloc(i64 16, i32 1)
  %t33 = inttoptr i64 2269767818 to ptr
  %t34 = getelementptr ptr, ptr %t32, i32 0
  store ptr %t33, ptr %t34
  %t35 = getelementptr ptr, ptr %t23, i32 1
  %t36 = load ptr, ptr %t35
  call void @__inc_ref(ptr %t36)
  %t37 = getelementptr ptr, ptr %t32, i32 1
  store ptr %t36, ptr %t37
  %t38 = getelementptr ptr, ptr %t29, i32 1
  store ptr %t32, ptr %t38
  call void @__free_recursive(ptr %t23)
  call void @__free_recursive(ptr %v_flag)
  ret ptr %t29
case.arm.4.39:
  call void @__free_recursive(ptr %v_flag)
  ret ptr %t23
case.default.27:
  unreachable
case.default.3:
  unreachable
}

define internal ptr @v_nestedUnion(ptr %v_m) {
  %t0 = getelementptr ptr, ptr %v_m, i32 0
  %t1 = load ptr, ptr %t0
  %t2 = ptrtoint ptr %t1 to i64
  switch i64 %t2, label %case.default.3 [ i64 11, label %case.arm.11.4 i64 12, label %case.arm.12.22 ]
case.arm.11.4:
  %t5 = call ptr @v_vFirst()
  %t6 = getelementptr ptr, ptr %t5, i32 0
  %t7 = load ptr, ptr %t6
  %t8 = ptrtoint ptr %t7 to i64
  switch i64 %t8, label %case.default.9 [ i64 3, label %case.arm.3.10 i64 4, label %case.arm.4.21 ]
case.arm.3.10:
  %t11 = call ptr @__alloc(i64 16, i32 1)
  %t12 = inttoptr i64 3 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  %t14 = call ptr @__alloc(i64 16, i32 1)
  %t15 = inttoptr i64 925038822 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  %t17 = getelementptr ptr, ptr %t5, i32 1
  %t18 = load ptr, ptr %t17
  call void @__inc_ref(ptr %t18)
  %t19 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t18, ptr %t19
  %t20 = getelementptr ptr, ptr %t11, i32 1
  store ptr %t14, ptr %t20
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %v_m)
  ret ptr %t11
case.arm.4.21:
  call void @__free_recursive(ptr %v_m)
  ret ptr %t5
case.default.9:
  unreachable
case.arm.12.22:
  %t23 = getelementptr ptr, ptr %v_m, i32 1
  %t24 = load ptr, ptr %t23
  call void @__inc_ref(ptr %t24)
  %t25 = getelementptr ptr, ptr %t24, i32 0
  %t26 = load ptr, ptr %t25
  %t27 = ptrtoint ptr %t26 to i64
  switch i64 %t27, label %case.default.28 [ i64 1, label %case.arm.1.29 i64 2, label %case.arm.2.47 ]
case.arm.1.29:
  %t30 = call ptr @v_vErrA()
  %t31 = getelementptr ptr, ptr %t30, i32 0
  %t32 = load ptr, ptr %t31
  %t33 = ptrtoint ptr %t32 to i64
  switch i64 %t33, label %case.default.34 [ i64 3, label %case.arm.3.35 i64 4, label %case.arm.4.46 ]
case.arm.3.35:
  %t36 = call ptr @__alloc(i64 16, i32 1)
  %t37 = inttoptr i64 3 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = call ptr @__alloc(i64 16, i32 1)
  %t40 = inttoptr i64 2252990199 to ptr
  %t41 = getelementptr ptr, ptr %t39, i32 0
  store ptr %t40, ptr %t41
  %t42 = getelementptr ptr, ptr %t30, i32 1
  %t43 = load ptr, ptr %t42
  call void @__inc_ref(ptr %t43)
  %t44 = getelementptr ptr, ptr %t39, i32 1
  store ptr %t43, ptr %t44
  %t45 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t39, ptr %t45
  call void @__free_recursive(ptr %t24)
  call void @__free_recursive(ptr %t30)
  call void @__free_recursive(ptr %v_m)
  ret ptr %t36
case.arm.4.46:
  call void @__free_recursive(ptr %t24)
  call void @__free_recursive(ptr %v_m)
  ret ptr %t30
case.default.34:
  unreachable
case.arm.2.47:
  %t48 = call ptr @v_vSecond()
  %t49 = getelementptr ptr, ptr %t48, i32 0
  %t50 = load ptr, ptr %t49
  %t51 = ptrtoint ptr %t50 to i64
  switch i64 %t51, label %case.default.52 [ i64 3, label %case.arm.3.53 i64 4, label %case.arm.4.64 ]
case.arm.3.53:
  %t54 = call ptr @__alloc(i64 16, i32 1)
  %t55 = inttoptr i64 3 to ptr
  %t56 = getelementptr ptr, ptr %t54, i32 0
  store ptr %t55, ptr %t56
  %t57 = call ptr @__alloc(i64 16, i32 1)
  %t58 = inttoptr i64 925038822 to ptr
  %t59 = getelementptr ptr, ptr %t57, i32 0
  store ptr %t58, ptr %t59
  %t60 = getelementptr ptr, ptr %t48, i32 1
  %t61 = load ptr, ptr %t60
  call void @__inc_ref(ptr %t61)
  %t62 = getelementptr ptr, ptr %t57, i32 1
  store ptr %t61, ptr %t62
  %t63 = getelementptr ptr, ptr %t54, i32 1
  store ptr %t57, ptr %t63
  call void @__free_recursive(ptr %t24)
  call void @__free_recursive(ptr %t48)
  call void @__free_recursive(ptr %v_m)
  ret ptr %t54
case.arm.4.64:
  call void @__free_recursive(ptr %t24)
  call void @__free_recursive(ptr %v_m)
  ret ptr %t48
case.default.52:
  unreachable
case.default.28:
  unreachable
case.default.3:
  unreachable
}

define internal ptr @v_strWiden() {
  %t0 = call ptr @v_vStr()
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 3, label %case.arm.3.6 i64 4, label %case.arm.4.18 ]
case.arm.3.6:
  %t8 = call ptr @__alloc(i64 16, i32 1)
  %t9 = inttoptr i64 3 to ptr
  %t10 = getelementptr ptr, ptr %t8, i32 0
  store ptr %t9, ptr %t10
  %t11 = call ptr @__alloc(i64 16, i32 1)
  %t12 = inttoptr i64 1615808600 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  %t14 = getelementptr ptr, ptr %t0, i32 1
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  %t16 = getelementptr ptr, ptr %t11, i32 1
  store ptr %t15, ptr %t16
  %t17 = getelementptr ptr, ptr %t8, i32 1
  store ptr %t11, ptr %t17
  br label %case.end.3.7
case.end.3.7:
  br label %case.join.5
case.arm.4.18:
  call void @__inc_ref(ptr %t0)
  br label %case.end.4.19
case.end.4.19:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t20 = phi ptr [ %t8, %case.end.3.7 ], [ %t0, %case.end.4.19 ]
  call void @__free_recursive(ptr %t0)
  ret ptr %t20
}

define internal ptr @v_tagged(ptr %v_label, ptr %v_val) {
  call void @__inc_ref(ptr %v_label)
  %t0 = call ptr @__concat(ptr %v_label, ptr getelementptr inbounds (i8, ptr @.str.1, i64 12))
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 3, label %case.arm.3.5 i64 4, label %case.arm.4.12 ]
case.arm.3.5:
  %t6 = getelementptr ptr, ptr %t0, i32 1
  %t7 = load ptr, ptr %t6
  call void @__inc_ref(ptr %t7)
  %t8 = call ptr @__alloc(i64 16, i32 1)
  %t9 = inttoptr i64 3 to ptr
  %t10 = getelementptr ptr, ptr %t8, i32 0
  store ptr %t9, ptr %t10
  call void @__inc_ref(ptr %t7)
  %t11 = getelementptr ptr, ptr %t8, i32 1
  store ptr %t7, ptr %t11
  call void @__free_recursive(ptr %t0)
  call void @__free_recursive(ptr %t7)
  call void @__free_recursive(ptr %v_label)
  call void @__free_recursive(ptr %v_val)
  ret ptr %t8
case.arm.4.12:
  %t13 = getelementptr ptr, ptr %t0, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  call void @__inc_ref(ptr %t14)
  call void @__inc_ref(ptr %v_val)
  %t15 = call ptr @__concat(ptr %t14, ptr %v_val)
  %t16 = getelementptr ptr, ptr %t15, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %case.default.19 [ i64 3, label %case.arm.3.20 i64 4, label %case.arm.4.27 ]
case.arm.3.20:
  %t21 = getelementptr ptr, ptr %t15, i32 1
  %t22 = load ptr, ptr %t21
  call void @__inc_ref(ptr %t22)
  %t23 = call ptr @__alloc(i64 16, i32 1)
  %t24 = inttoptr i64 3 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  call void @__inc_ref(ptr %t22)
  %t26 = getelementptr ptr, ptr %t23, i32 1
  store ptr %t22, ptr %t26
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t0)
  call void @__free_recursive(ptr %t22)
  call void @__free_recursive(ptr %t14)
  call void @__free_recursive(ptr %v_label)
  call void @__free_recursive(ptr %v_val)
  ret ptr %t23
case.arm.4.27:
  %t28 = getelementptr ptr, ptr %t15, i32 1
  %t29 = load ptr, ptr %t28
  call void @__inc_ref(ptr %t29)
  call void @__inc_ref(ptr %t29)
  %t30 = call ptr @__concat(ptr %t29, ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
  call void @__free_recursive(ptr %t15)
  call void @__free_recursive(ptr %t0)
  call void @__free_recursive(ptr %t29)
  call void @__free_recursive(ptr %t14)
  call void @__free_recursive(ptr %v_label)
  call void @__free_recursive(ptr %v_val)
  ret ptr %t30
case.default.19:
  unreachable
case.default.4:
  unreachable
}

define internal ptr @v_render() {
  %v__inl92_scrut.jslot = alloca ptr
  %v__inl94_scrut.jslot = alloca ptr
  %v__inl96_scrut.jslot = alloca ptr
  %v__inl98_scrut.jslot = alloca ptr
  %v__inl100_scrut.jslot = alloca ptr
  %v__inl102_scrut.jslot = alloca ptr
  %v__inl104_scrut.jslot = alloca ptr
  %t0 = call ptr @v_defBodyLeft()
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 3, label %case.arm.3.6 i64 4, label %case.arm.4.20 ]
case.arm.3.6:
  %t8 = getelementptr ptr, ptr %t0, i32 1
  %t9 = load ptr, ptr %t8
  call void @__inc_ref(ptr %t9)
  %t10 = getelementptr ptr, ptr %t9, i32 0
  %t11 = load ptr, ptr %t10
  %t12 = ptrtoint ptr %t11 to i64
  switch i64 %t12, label %case.default.13 [ i64 2252990199, label %case.arm.2252990199.15 i64 2269767818, label %case.arm.2269767818.17 ]
case.arm.2252990199.15:
  br label %case.end.2252990199.16
case.end.2252990199.16:
  br label %case.join.14
case.arm.2269767818.17:
  br label %case.end.2269767818.18
case.end.2269767818.18:
  br label %case.join.14
case.default.13:
  unreachable
case.join.14:
  %t19 = phi ptr [ getelementptr inbounds (i8, ptr @.str.4, i64 12), %case.end.2252990199.16 ], [ getelementptr inbounds (i8, ptr @.str.5, i64 12), %case.end.2269767818.18 ]
  call void @__free_recursive(ptr %t9)
  br label %case.end.3.7
case.end.3.7:
  br label %case.join.5
case.arm.4.20:
  %t22 = getelementptr ptr, ptr %t0, i32 1
  %t23 = load ptr, ptr %t22
  call void @__inc_ref(ptr %t23)
  %t24 = call ptr @__showInt32(ptr %t23)
  br label %case.end.4.21
case.end.4.21:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t25 = phi ptr [ %t19, %case.end.3.7 ], [ %t24, %case.end.4.21 ]
  call void @__free_recursive(ptr %t0)
  %t26 = call ptr @v_tagged(ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t25)
  %t27 = getelementptr ptr, ptr %t26, i32 0
  %t28 = load ptr, ptr %t27
  %t29 = ptrtoint ptr %t28 to i64
  switch i64 %t29, label %case.default.30 [ i64 3, label %case.arm.3.32 i64 4, label %case.arm.4.40 ]
case.arm.3.32:
  %t34 = getelementptr ptr, ptr %t26, i32 1
  %t35 = load ptr, ptr %t34
  call void @__inc_ref(ptr %t35)
  %t36 = call ptr @__alloc(i64 16, i32 1)
  %t37 = inttoptr i64 3 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  call void @__inc_ref(ptr %t35)
  %t39 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t35, ptr %t39
  br label %case.end.3.33
case.end.3.33:
  br label %case.join.31
case.arm.4.40:
  %t42 = getelementptr ptr, ptr %t26, i32 1
  %t43 = load ptr, ptr %t42
  call void @__inc_ref(ptr %t43)
  %t46 = call ptr @v_defBodyRight()
  %t47 = getelementptr ptr, ptr %t46, i32 0
  %t48 = load ptr, ptr %t47
  %t49 = ptrtoint ptr %t48 to i64
  switch i64 %t49, label %case.default.50 [ i64 3, label %case.arm.3.52 i64 4, label %case.arm.4.66 ]
case.arm.3.52:
  %t54 = getelementptr ptr, ptr %t46, i32 1
  %t55 = load ptr, ptr %t54
  call void @__inc_ref(ptr %t55)
  %t56 = getelementptr ptr, ptr %t55, i32 0
  %t57 = load ptr, ptr %t56
  %t58 = ptrtoint ptr %t57 to i64
  switch i64 %t58, label %case.default.59 [ i64 2252990199, label %case.arm.2252990199.61 i64 2269767818, label %case.arm.2269767818.63 ]
case.arm.2252990199.61:
  br label %case.end.2252990199.62
case.end.2252990199.62:
  br label %case.join.60
case.arm.2269767818.63:
  br label %case.end.2269767818.64
case.end.2269767818.64:
  br label %case.join.60
case.default.59:
  unreachable
case.join.60:
  %t65 = phi ptr [ getelementptr inbounds (i8, ptr @.str.4, i64 12), %case.end.2252990199.62 ], [ getelementptr inbounds (i8, ptr @.str.5, i64 12), %case.end.2269767818.64 ]
  call void @__free_recursive(ptr %t55)
  br label %case.end.3.53
case.end.3.53:
  br label %case.join.51
case.arm.4.66:
  %t68 = getelementptr ptr, ptr %t46, i32 1
  %t69 = load ptr, ptr %t68
  call void @__inc_ref(ptr %t69)
  %t70 = call ptr @__showInt32(ptr %t69)
  br label %case.end.4.67
case.end.4.67:
  br label %case.join.51
case.default.50:
  unreachable
case.join.51:
  %t71 = phi ptr [ %t65, %case.end.3.53 ], [ %t70, %case.end.4.67 ]
  call void @__free_recursive(ptr %t46)
  %t72 = call ptr @v_tagged(ptr getelementptr inbounds (i8, ptr @.str.15, i64 12), ptr %t71)
  %t73 = getelementptr ptr, ptr %t72, i32 0
  %t74 = load ptr, ptr %t73
  %t75 = ptrtoint ptr %t74 to i64
  switch i64 %t75, label %join.case.default.76 [ i64 3, label %join.case.arm.3.77 i64 4, label %join.case.arm.4.85 ]
join.case.arm.3.77:
  %t78 = getelementptr ptr, ptr %t72, i32 1
  %t79 = load ptr, ptr %t78
  call void @__inc_ref(ptr %t79)
  %t80 = call ptr @__alloc(i64 16, i32 1)
  %t81 = inttoptr i64 3 to ptr
  %t82 = getelementptr ptr, ptr %t80, i32 0
  store ptr %t81, ptr %t82
  call void @__inc_ref(ptr %t79)
  %t83 = getelementptr ptr, ptr %t80, i32 1
  store ptr %t79, ptr %t83
  call void @__free_recursive(ptr %t72)
  br label %join.val.84
join.val.84:
  br label %join.after.45
join.case.arm.4.85:
  %t86 = getelementptr ptr, ptr %t72, i32 1
  %t87 = load ptr, ptr %t86
  call void @__inc_ref(ptr %t87)
  call void @__inc_ref(ptr %t43)
  call void @__inc_ref(ptr %t87)
  %t88 = call ptr @__concat(ptr %t43, ptr %t87)
  call void @__free_recursive(ptr %t72)
  store ptr %t88, ptr %v__inl92_scrut.jslot
  br label %join.44
join.case.default.76:
  unreachable
join.44:
  %t89 = load ptr, ptr %v__inl92_scrut.jslot
  %t90 = getelementptr ptr, ptr %t89, i32 0
  %t91 = load ptr, ptr %t90
  %t92 = ptrtoint ptr %t91 to i64
  switch i64 %t92, label %case.default.93 [ i64 3, label %case.arm.3.95 i64 4, label %case.arm.4.97 ]
case.arm.3.95:
  call void @__inc_ref(ptr %t89)
  br label %case.end.3.96
case.end.3.96:
  br label %case.join.94
case.arm.4.97:
  %t101 = call ptr @v_letBody()
  %t102 = getelementptr ptr, ptr %t101, i32 0
  %t103 = load ptr, ptr %t102
  %t104 = ptrtoint ptr %t103 to i64
  switch i64 %t104, label %case.default.105 [ i64 3, label %case.arm.3.107 i64 4, label %case.arm.4.121 ]
case.arm.3.107:
  %t109 = getelementptr ptr, ptr %t101, i32 1
  %t110 = load ptr, ptr %t109
  call void @__inc_ref(ptr %t110)
  %t111 = getelementptr ptr, ptr %t110, i32 0
  %t112 = load ptr, ptr %t111
  %t113 = ptrtoint ptr %t112 to i64
  switch i64 %t113, label %case.default.114 [ i64 2252990199, label %case.arm.2252990199.116 i64 2269767818, label %case.arm.2269767818.118 ]
case.arm.2252990199.116:
  br label %case.end.2252990199.117
case.end.2252990199.117:
  br label %case.join.115
case.arm.2269767818.118:
  br label %case.end.2269767818.119
case.end.2269767818.119:
  br label %case.join.115
case.default.114:
  unreachable
case.join.115:
  %t120 = phi ptr [ getelementptr inbounds (i8, ptr @.str.4, i64 12), %case.end.2252990199.117 ], [ getelementptr inbounds (i8, ptr @.str.5, i64 12), %case.end.2269767818.119 ]
  call void @__free_recursive(ptr %t110)
  br label %case.end.3.108
case.end.3.108:
  br label %case.join.106
case.arm.4.121:
  %t123 = getelementptr ptr, ptr %t101, i32 1
  %t124 = load ptr, ptr %t123
  call void @__inc_ref(ptr %t124)
  %t125 = call ptr @__showInt32(ptr %t124)
  br label %case.end.4.122
case.end.4.122:
  br label %case.join.106
case.default.105:
  unreachable
case.join.106:
  %t126 = phi ptr [ %t120, %case.end.3.108 ], [ %t125, %case.end.4.122 ]
  call void @__free_recursive(ptr %t101)
  %t127 = call ptr @v_tagged(ptr getelementptr inbounds (i8, ptr @.str.14, i64 12), ptr %t126)
  %t128 = getelementptr ptr, ptr %t127, i32 0
  %t129 = load ptr, ptr %t128
  %t130 = ptrtoint ptr %t129 to i64
  switch i64 %t130, label %join.case.default.131 [ i64 3, label %join.case.arm.3.132 i64 4, label %join.case.arm.4.140 ]
join.case.arm.3.132:
  %t133 = getelementptr ptr, ptr %t127, i32 1
  %t134 = load ptr, ptr %t133
  call void @__inc_ref(ptr %t134)
  %t135 = call ptr @__alloc(i64 16, i32 1)
  %t136 = inttoptr i64 3 to ptr
  %t137 = getelementptr ptr, ptr %t135, i32 0
  store ptr %t136, ptr %t137
  call void @__inc_ref(ptr %t134)
  %t138 = getelementptr ptr, ptr %t135, i32 1
  store ptr %t134, ptr %t138
  call void @__free_recursive(ptr %t134)
  call void @__free_recursive(ptr %t127)
  br label %join.val.139
join.val.139:
  br label %join.after.100
join.case.arm.4.140:
  %t141 = getelementptr ptr, ptr %t127, i32 1
  %t142 = load ptr, ptr %t141
  call void @__inc_ref(ptr %t142)
  %t143 = getelementptr ptr, ptr %t89, i32 1
  %t144 = load ptr, ptr %t143
  call void @__inc_ref(ptr %t144)
  call void @__inc_ref(ptr %t142)
  %t145 = call ptr @__concat(ptr %t144, ptr %t142)
  call void @__free_recursive(ptr %t142)
  call void @__free_recursive(ptr %t127)
  store ptr %t145, ptr %v__inl94_scrut.jslot
  br label %join.99
join.case.default.131:
  unreachable
join.99:
  %t146 = load ptr, ptr %v__inl94_scrut.jslot
  %t147 = getelementptr ptr, ptr %t146, i32 0
  %t148 = load ptr, ptr %t147
  %t149 = ptrtoint ptr %t148 to i64
  switch i64 %t149, label %case.default.150 [ i64 3, label %case.arm.3.152 i64 4, label %case.arm.4.154 ]
case.arm.3.152:
  call void @__inc_ref(ptr %t146)
  br label %case.end.3.153
case.end.3.153:
  br label %case.join.151
case.arm.4.154:
  %t158 = call ptr @__alloc(i64 8, i32 0)
  %t159 = inttoptr i64 1 to ptr
  %t160 = getelementptr ptr, ptr %t158, i32 0
  store ptr %t159, ptr %t160
  %t161 = call ptr @v_caseUnion(ptr %t158)
  %t162 = getelementptr ptr, ptr %t161, i32 0
  %t163 = load ptr, ptr %t162
  %t164 = ptrtoint ptr %t163 to i64
  switch i64 %t164, label %case.default.165 [ i64 3, label %case.arm.3.167 i64 4, label %case.arm.4.181 ]
case.arm.3.167:
  %t169 = getelementptr ptr, ptr %t161, i32 1
  %t170 = load ptr, ptr %t169
  call void @__inc_ref(ptr %t170)
  %t171 = getelementptr ptr, ptr %t170, i32 0
  %t172 = load ptr, ptr %t171
  %t173 = ptrtoint ptr %t172 to i64
  switch i64 %t173, label %case.default.174 [ i64 2252990199, label %case.arm.2252990199.176 i64 2269767818, label %case.arm.2269767818.178 ]
case.arm.2252990199.176:
  br label %case.end.2252990199.177
case.end.2252990199.177:
  br label %case.join.175
case.arm.2269767818.178:
  br label %case.end.2269767818.179
case.end.2269767818.179:
  br label %case.join.175
case.default.174:
  unreachable
case.join.175:
  %t180 = phi ptr [ getelementptr inbounds (i8, ptr @.str.4, i64 12), %case.end.2252990199.177 ], [ getelementptr inbounds (i8, ptr @.str.5, i64 12), %case.end.2269767818.179 ]
  call void @__free_recursive(ptr %t170)
  br label %case.end.3.168
case.end.3.168:
  br label %case.join.166
case.arm.4.181:
  %t183 = getelementptr ptr, ptr %t161, i32 1
  %t184 = load ptr, ptr %t183
  call void @__inc_ref(ptr %t184)
  %t185 = call ptr @__showInt32(ptr %t184)
  br label %case.end.4.182
case.end.4.182:
  br label %case.join.166
case.default.165:
  unreachable
case.join.166:
  %t186 = phi ptr [ %t180, %case.end.3.168 ], [ %t185, %case.end.4.182 ]
  call void @__free_recursive(ptr %t161)
  %t187 = call ptr @v_tagged(ptr getelementptr inbounds (i8, ptr @.str.13, i64 12), ptr %t186)
  %t188 = getelementptr ptr, ptr %t187, i32 0
  %t189 = load ptr, ptr %t188
  %t190 = ptrtoint ptr %t189 to i64
  switch i64 %t190, label %join.case.default.191 [ i64 3, label %join.case.arm.3.192 i64 4, label %join.case.arm.4.200 ]
join.case.arm.3.192:
  %t193 = getelementptr ptr, ptr %t187, i32 1
  %t194 = load ptr, ptr %t193
  call void @__inc_ref(ptr %t194)
  %t195 = call ptr @__alloc(i64 16, i32 1)
  %t196 = inttoptr i64 3 to ptr
  %t197 = getelementptr ptr, ptr %t195, i32 0
  store ptr %t196, ptr %t197
  call void @__inc_ref(ptr %t194)
  %t198 = getelementptr ptr, ptr %t195, i32 1
  store ptr %t194, ptr %t198
  call void @__free_recursive(ptr %t194)
  call void @__free_recursive(ptr %t187)
  br label %join.val.199
join.val.199:
  br label %join.after.157
join.case.arm.4.200:
  %t201 = getelementptr ptr, ptr %t187, i32 1
  %t202 = load ptr, ptr %t201
  call void @__inc_ref(ptr %t202)
  %t203 = getelementptr ptr, ptr %t146, i32 1
  %t204 = load ptr, ptr %t203
  call void @__inc_ref(ptr %t204)
  call void @__inc_ref(ptr %t202)
  %t205 = call ptr @__concat(ptr %t204, ptr %t202)
  call void @__free_recursive(ptr %t202)
  call void @__free_recursive(ptr %t187)
  store ptr %t205, ptr %v__inl96_scrut.jslot
  br label %join.156
join.case.default.191:
  unreachable
join.156:
  %t206 = load ptr, ptr %v__inl96_scrut.jslot
  %t207 = getelementptr ptr, ptr %t206, i32 0
  %t208 = load ptr, ptr %t207
  %t209 = ptrtoint ptr %t208 to i64
  switch i64 %t209, label %case.default.210 [ i64 3, label %case.arm.3.212 i64 4, label %case.arm.4.214 ]
case.arm.3.212:
  call void @__inc_ref(ptr %t206)
  br label %case.end.3.213
case.end.3.213:
  br label %case.join.211
case.arm.4.214:
  %t218 = call ptr @__alloc(i64 8, i32 0)
  %t219 = inttoptr i64 2 to ptr
  %t220 = getelementptr ptr, ptr %t218, i32 0
  store ptr %t219, ptr %t220
  %t221 = call ptr @v_caseUnion(ptr %t218)
  %t222 = getelementptr ptr, ptr %t221, i32 0
  %t223 = load ptr, ptr %t222
  %t224 = ptrtoint ptr %t223 to i64
  switch i64 %t224, label %case.default.225 [ i64 3, label %case.arm.3.227 i64 4, label %case.arm.4.241 ]
case.arm.3.227:
  %t229 = getelementptr ptr, ptr %t221, i32 1
  %t230 = load ptr, ptr %t229
  call void @__inc_ref(ptr %t230)
  %t231 = getelementptr ptr, ptr %t230, i32 0
  %t232 = load ptr, ptr %t231
  %t233 = ptrtoint ptr %t232 to i64
  switch i64 %t233, label %case.default.234 [ i64 2252990199, label %case.arm.2252990199.236 i64 2269767818, label %case.arm.2269767818.238 ]
case.arm.2252990199.236:
  br label %case.end.2252990199.237
case.end.2252990199.237:
  br label %case.join.235
case.arm.2269767818.238:
  br label %case.end.2269767818.239
case.end.2269767818.239:
  br label %case.join.235
case.default.234:
  unreachable
case.join.235:
  %t240 = phi ptr [ getelementptr inbounds (i8, ptr @.str.4, i64 12), %case.end.2252990199.237 ], [ getelementptr inbounds (i8, ptr @.str.5, i64 12), %case.end.2269767818.239 ]
  call void @__free_recursive(ptr %t230)
  br label %case.end.3.228
case.end.3.228:
  br label %case.join.226
case.arm.4.241:
  %t243 = getelementptr ptr, ptr %t221, i32 1
  %t244 = load ptr, ptr %t243
  call void @__inc_ref(ptr %t244)
  %t245 = call ptr @__showInt32(ptr %t244)
  br label %case.end.4.242
case.end.4.242:
  br label %case.join.226
case.default.225:
  unreachable
case.join.226:
  %t246 = phi ptr [ %t240, %case.end.3.228 ], [ %t245, %case.end.4.242 ]
  call void @__free_recursive(ptr %t221)
  %t247 = call ptr @v_tagged(ptr getelementptr inbounds (i8, ptr @.str.12, i64 12), ptr %t246)
  %t248 = getelementptr ptr, ptr %t247, i32 0
  %t249 = load ptr, ptr %t248
  %t250 = ptrtoint ptr %t249 to i64
  switch i64 %t250, label %join.case.default.251 [ i64 3, label %join.case.arm.3.252 i64 4, label %join.case.arm.4.260 ]
join.case.arm.3.252:
  %t253 = getelementptr ptr, ptr %t247, i32 1
  %t254 = load ptr, ptr %t253
  call void @__inc_ref(ptr %t254)
  %t255 = call ptr @__alloc(i64 16, i32 1)
  %t256 = inttoptr i64 3 to ptr
  %t257 = getelementptr ptr, ptr %t255, i32 0
  store ptr %t256, ptr %t257
  call void @__inc_ref(ptr %t254)
  %t258 = getelementptr ptr, ptr %t255, i32 1
  store ptr %t254, ptr %t258
  call void @__free_recursive(ptr %t254)
  call void @__free_recursive(ptr %t247)
  br label %join.val.259
join.val.259:
  br label %join.after.217
join.case.arm.4.260:
  %t261 = getelementptr ptr, ptr %t247, i32 1
  %t262 = load ptr, ptr %t261
  call void @__inc_ref(ptr %t262)
  %t263 = getelementptr ptr, ptr %t206, i32 1
  %t264 = load ptr, ptr %t263
  call void @__inc_ref(ptr %t264)
  call void @__inc_ref(ptr %t262)
  %t265 = call ptr @__concat(ptr %t264, ptr %t262)
  call void @__free_recursive(ptr %t262)
  call void @__free_recursive(ptr %t247)
  store ptr %t265, ptr %v__inl98_scrut.jslot
  br label %join.216
join.case.default.251:
  unreachable
join.216:
  %t266 = load ptr, ptr %v__inl98_scrut.jslot
  %t267 = getelementptr ptr, ptr %t266, i32 0
  %t268 = load ptr, ptr %t267
  %t269 = ptrtoint ptr %t268 to i64
  switch i64 %t269, label %case.default.270 [ i64 3, label %case.arm.3.272 i64 4, label %case.arm.4.274 ]
case.arm.3.272:
  call void @__inc_ref(ptr %t266)
  br label %case.end.3.273
case.end.3.273:
  br label %case.join.271
case.arm.4.274:
  %t278 = call ptr @__alloc(i64 8, i32 0)
  %t279 = inttoptr i64 11 to ptr
  %t280 = getelementptr ptr, ptr %t278, i32 0
  store ptr %t279, ptr %t280
  %t281 = call ptr @v_nestedUnion(ptr %t278)
  %t282 = getelementptr ptr, ptr %t281, i32 0
  %t283 = load ptr, ptr %t282
  %t284 = ptrtoint ptr %t283 to i64
  switch i64 %t284, label %case.default.285 [ i64 3, label %case.arm.3.287 i64 4, label %case.arm.4.313 ]
case.arm.3.287:
  %t289 = getelementptr ptr, ptr %t281, i32 1
  %t290 = load ptr, ptr %t289
  call void @__inc_ref(ptr %t290)
  %t291 = getelementptr ptr, ptr %t290, i32 0
  %t292 = load ptr, ptr %t291
  %t293 = ptrtoint ptr %t292 to i64
  switch i64 %t293, label %case.default.294 [ i64 925038822, label %case.arm.925038822.296 i64 2252990199, label %case.arm.2252990199.310 ]
case.arm.925038822.296:
  %t298 = getelementptr ptr, ptr %t290, i32 1
  %t299 = load ptr, ptr %t298
  call void @__inc_ref(ptr %t299)
  %t300 = getelementptr ptr, ptr %t299, i32 0
  %t301 = load ptr, ptr %t300
  %t302 = ptrtoint ptr %t301 to i64
  switch i64 %t302, label %case.default.303 [ i64 26, label %case.arm.26.305 i64 27, label %case.arm.27.307 ]
case.arm.26.305:
  br label %case.end.26.306
case.end.26.306:
  br label %case.join.304
case.arm.27.307:
  br label %case.end.27.308
case.end.27.308:
  br label %case.join.304
case.default.303:
  unreachable
case.join.304:
  %t309 = phi ptr [ getelementptr inbounds (i8, ptr @.str.8, i64 12), %case.end.26.306 ], [ getelementptr inbounds (i8, ptr @.str.9, i64 12), %case.end.27.308 ]
  call void @__free_recursive(ptr %t299)
  br label %case.end.925038822.297
case.end.925038822.297:
  br label %case.join.295
case.arm.2252990199.310:
  br label %case.end.2252990199.311
case.end.2252990199.311:
  br label %case.join.295
case.default.294:
  unreachable
case.join.295:
  %t312 = phi ptr [ %t309, %case.end.925038822.297 ], [ getelementptr inbounds (i8, ptr @.str.4, i64 12), %case.end.2252990199.311 ]
  call void @__free_recursive(ptr %t290)
  br label %case.end.3.288
case.end.3.288:
  br label %case.join.286
case.arm.4.313:
  %t315 = getelementptr ptr, ptr %t281, i32 1
  %t316 = load ptr, ptr %t315
  call void @__inc_ref(ptr %t316)
  %t317 = call ptr @__showInt32(ptr %t316)
  br label %case.end.4.314
case.end.4.314:
  br label %case.join.286
case.default.285:
  unreachable
case.join.286:
  %t318 = phi ptr [ %t312, %case.end.3.288 ], [ %t317, %case.end.4.314 ]
  call void @__free_recursive(ptr %t281)
  %t319 = call ptr @v_tagged(ptr getelementptr inbounds (i8, ptr @.str.11, i64 12), ptr %t318)
  %t320 = getelementptr ptr, ptr %t319, i32 0
  %t321 = load ptr, ptr %t320
  %t322 = ptrtoint ptr %t321 to i64
  switch i64 %t322, label %join.case.default.323 [ i64 3, label %join.case.arm.3.324 i64 4, label %join.case.arm.4.332 ]
join.case.arm.3.324:
  %t325 = getelementptr ptr, ptr %t319, i32 1
  %t326 = load ptr, ptr %t325
  call void @__inc_ref(ptr %t326)
  %t327 = call ptr @__alloc(i64 16, i32 1)
  %t328 = inttoptr i64 3 to ptr
  %t329 = getelementptr ptr, ptr %t327, i32 0
  store ptr %t328, ptr %t329
  call void @__inc_ref(ptr %t326)
  %t330 = getelementptr ptr, ptr %t327, i32 1
  store ptr %t326, ptr %t330
  call void @__free_recursive(ptr %t326)
  call void @__free_recursive(ptr %t319)
  br label %join.val.331
join.val.331:
  br label %join.after.277
join.case.arm.4.332:
  %t333 = getelementptr ptr, ptr %t319, i32 1
  %t334 = load ptr, ptr %t333
  call void @__inc_ref(ptr %t334)
  %t335 = getelementptr ptr, ptr %t266, i32 1
  %t336 = load ptr, ptr %t335
  call void @__inc_ref(ptr %t336)
  call void @__inc_ref(ptr %t334)
  %t337 = call ptr @__concat(ptr %t336, ptr %t334)
  call void @__free_recursive(ptr %t334)
  call void @__free_recursive(ptr %t319)
  store ptr %t337, ptr %v__inl100_scrut.jslot
  br label %join.276
join.case.default.323:
  unreachable
join.276:
  %t338 = load ptr, ptr %v__inl100_scrut.jslot
  %t339 = getelementptr ptr, ptr %t338, i32 0
  %t340 = load ptr, ptr %t339
  %t341 = ptrtoint ptr %t340 to i64
  switch i64 %t341, label %case.default.342 [ i64 3, label %case.arm.3.344 i64 4, label %case.arm.4.346 ]
case.arm.3.344:
  call void @__inc_ref(ptr %t338)
  br label %case.end.3.345
case.end.3.345:
  br label %case.join.343
case.arm.4.346:
  %t350 = call ptr @__alloc(i64 16, i32 1)
  %t351 = inttoptr i64 12 to ptr
  %t352 = getelementptr ptr, ptr %t350, i32 0
  store ptr %t351, ptr %t352
  %t353 = call ptr @__alloc(i64 8, i32 0)
  %t354 = inttoptr i64 1 to ptr
  %t355 = getelementptr ptr, ptr %t353, i32 0
  store ptr %t354, ptr %t355
  %t356 = getelementptr ptr, ptr %t350, i32 1
  store ptr %t353, ptr %t356
  %t357 = call ptr @v_nestedUnion(ptr %t350)
  %t358 = getelementptr ptr, ptr %t357, i32 0
  %t359 = load ptr, ptr %t358
  %t360 = ptrtoint ptr %t359 to i64
  switch i64 %t360, label %case.default.361 [ i64 3, label %case.arm.3.363 i64 4, label %case.arm.4.389 ]
case.arm.3.363:
  %t365 = getelementptr ptr, ptr %t357, i32 1
  %t366 = load ptr, ptr %t365
  call void @__inc_ref(ptr %t366)
  %t367 = getelementptr ptr, ptr %t366, i32 0
  %t368 = load ptr, ptr %t367
  %t369 = ptrtoint ptr %t368 to i64
  switch i64 %t369, label %case.default.370 [ i64 925038822, label %case.arm.925038822.372 i64 2252990199, label %case.arm.2252990199.386 ]
case.arm.925038822.372:
  %t374 = getelementptr ptr, ptr %t366, i32 1
  %t375 = load ptr, ptr %t374
  call void @__inc_ref(ptr %t375)
  %t376 = getelementptr ptr, ptr %t375, i32 0
  %t377 = load ptr, ptr %t376
  %t378 = ptrtoint ptr %t377 to i64
  switch i64 %t378, label %case.default.379 [ i64 26, label %case.arm.26.381 i64 27, label %case.arm.27.383 ]
case.arm.26.381:
  br label %case.end.26.382
case.end.26.382:
  br label %case.join.380
case.arm.27.383:
  br label %case.end.27.384
case.end.27.384:
  br label %case.join.380
case.default.379:
  unreachable
case.join.380:
  %t385 = phi ptr [ getelementptr inbounds (i8, ptr @.str.8, i64 12), %case.end.26.382 ], [ getelementptr inbounds (i8, ptr @.str.9, i64 12), %case.end.27.384 ]
  call void @__free_recursive(ptr %t375)
  br label %case.end.925038822.373
case.end.925038822.373:
  br label %case.join.371
case.arm.2252990199.386:
  br label %case.end.2252990199.387
case.end.2252990199.387:
  br label %case.join.371
case.default.370:
  unreachable
case.join.371:
  %t388 = phi ptr [ %t385, %case.end.925038822.373 ], [ getelementptr inbounds (i8, ptr @.str.4, i64 12), %case.end.2252990199.387 ]
  call void @__free_recursive(ptr %t366)
  br label %case.end.3.364
case.end.3.364:
  br label %case.join.362
case.arm.4.389:
  %t391 = getelementptr ptr, ptr %t357, i32 1
  %t392 = load ptr, ptr %t391
  call void @__inc_ref(ptr %t392)
  %t393 = call ptr @__showInt32(ptr %t392)
  br label %case.end.4.390
case.end.4.390:
  br label %case.join.362
case.default.361:
  unreachable
case.join.362:
  %t394 = phi ptr [ %t388, %case.end.3.364 ], [ %t393, %case.end.4.390 ]
  call void @__free_recursive(ptr %t357)
  %t395 = call ptr @v_tagged(ptr getelementptr inbounds (i8, ptr @.str.10, i64 12), ptr %t394)
  %t396 = getelementptr ptr, ptr %t395, i32 0
  %t397 = load ptr, ptr %t396
  %t398 = ptrtoint ptr %t397 to i64
  switch i64 %t398, label %join.case.default.399 [ i64 3, label %join.case.arm.3.400 i64 4, label %join.case.arm.4.408 ]
join.case.arm.3.400:
  %t401 = getelementptr ptr, ptr %t395, i32 1
  %t402 = load ptr, ptr %t401
  call void @__inc_ref(ptr %t402)
  %t403 = call ptr @__alloc(i64 16, i32 1)
  %t404 = inttoptr i64 3 to ptr
  %t405 = getelementptr ptr, ptr %t403, i32 0
  store ptr %t404, ptr %t405
  call void @__inc_ref(ptr %t402)
  %t406 = getelementptr ptr, ptr %t403, i32 1
  store ptr %t402, ptr %t406
  call void @__free_recursive(ptr %t402)
  call void @__free_recursive(ptr %t395)
  br label %join.val.407
join.val.407:
  br label %join.after.349
join.case.arm.4.408:
  %t409 = getelementptr ptr, ptr %t395, i32 1
  %t410 = load ptr, ptr %t409
  call void @__inc_ref(ptr %t410)
  %t411 = getelementptr ptr, ptr %t338, i32 1
  %t412 = load ptr, ptr %t411
  call void @__inc_ref(ptr %t412)
  call void @__inc_ref(ptr %t410)
  %t413 = call ptr @__concat(ptr %t412, ptr %t410)
  call void @__free_recursive(ptr %t410)
  call void @__free_recursive(ptr %t395)
  store ptr %t413, ptr %v__inl102_scrut.jslot
  br label %join.348
join.case.default.399:
  unreachable
join.348:
  %t414 = load ptr, ptr %v__inl102_scrut.jslot
  %t415 = getelementptr ptr, ptr %t414, i32 0
  %t416 = load ptr, ptr %t415
  %t417 = ptrtoint ptr %t416 to i64
  switch i64 %t417, label %case.default.418 [ i64 3, label %case.arm.3.420 i64 4, label %case.arm.4.422 ]
case.arm.3.420:
  call void @__inc_ref(ptr %t414)
  br label %case.end.3.421
case.end.3.421:
  br label %case.join.419
case.arm.4.422:
  %t426 = call ptr @__alloc(i64 16, i32 1)
  %t427 = inttoptr i64 12 to ptr
  %t428 = getelementptr ptr, ptr %t426, i32 0
  store ptr %t427, ptr %t428
  %t429 = call ptr @__alloc(i64 8, i32 0)
  %t430 = inttoptr i64 2 to ptr
  %t431 = getelementptr ptr, ptr %t429, i32 0
  store ptr %t430, ptr %t431
  %t432 = getelementptr ptr, ptr %t426, i32 1
  store ptr %t429, ptr %t432
  %t433 = call ptr @v_nestedUnion(ptr %t426)
  %t434 = getelementptr ptr, ptr %t433, i32 0
  %t435 = load ptr, ptr %t434
  %t436 = ptrtoint ptr %t435 to i64
  switch i64 %t436, label %case.default.437 [ i64 3, label %case.arm.3.439 i64 4, label %case.arm.4.465 ]
case.arm.3.439:
  %t441 = getelementptr ptr, ptr %t433, i32 1
  %t442 = load ptr, ptr %t441
  call void @__inc_ref(ptr %t442)
  %t443 = getelementptr ptr, ptr %t442, i32 0
  %t444 = load ptr, ptr %t443
  %t445 = ptrtoint ptr %t444 to i64
  switch i64 %t445, label %case.default.446 [ i64 925038822, label %case.arm.925038822.448 i64 2252990199, label %case.arm.2252990199.462 ]
case.arm.925038822.448:
  %t450 = getelementptr ptr, ptr %t442, i32 1
  %t451 = load ptr, ptr %t450
  call void @__inc_ref(ptr %t451)
  %t452 = getelementptr ptr, ptr %t451, i32 0
  %t453 = load ptr, ptr %t452
  %t454 = ptrtoint ptr %t453 to i64
  switch i64 %t454, label %case.default.455 [ i64 26, label %case.arm.26.457 i64 27, label %case.arm.27.459 ]
case.arm.26.457:
  br label %case.end.26.458
case.end.26.458:
  br label %case.join.456
case.arm.27.459:
  br label %case.end.27.460
case.end.27.460:
  br label %case.join.456
case.default.455:
  unreachable
case.join.456:
  %t461 = phi ptr [ getelementptr inbounds (i8, ptr @.str.8, i64 12), %case.end.26.458 ], [ getelementptr inbounds (i8, ptr @.str.9, i64 12), %case.end.27.460 ]
  call void @__free_recursive(ptr %t451)
  br label %case.end.925038822.449
case.end.925038822.449:
  br label %case.join.447
case.arm.2252990199.462:
  br label %case.end.2252990199.463
case.end.2252990199.463:
  br label %case.join.447
case.default.446:
  unreachable
case.join.447:
  %t464 = phi ptr [ %t461, %case.end.925038822.449 ], [ getelementptr inbounds (i8, ptr @.str.4, i64 12), %case.end.2252990199.463 ]
  call void @__free_recursive(ptr %t442)
  br label %case.end.3.440
case.end.3.440:
  br label %case.join.438
case.arm.4.465:
  %t467 = getelementptr ptr, ptr %t433, i32 1
  %t468 = load ptr, ptr %t467
  call void @__inc_ref(ptr %t468)
  %t469 = call ptr @__showInt32(ptr %t468)
  br label %case.end.4.466
case.end.4.466:
  br label %case.join.438
case.default.437:
  unreachable
case.join.438:
  %t470 = phi ptr [ %t464, %case.end.3.440 ], [ %t469, %case.end.4.466 ]
  call void @__free_recursive(ptr %t433)
  %t471 = call ptr @v_tagged(ptr getelementptr inbounds (i8, ptr @.str.7, i64 12), ptr %t470)
  %t472 = getelementptr ptr, ptr %t471, i32 0
  %t473 = load ptr, ptr %t472
  %t474 = ptrtoint ptr %t473 to i64
  switch i64 %t474, label %join.case.default.475 [ i64 3, label %join.case.arm.3.476 i64 4, label %join.case.arm.4.484 ]
join.case.arm.3.476:
  %t477 = getelementptr ptr, ptr %t471, i32 1
  %t478 = load ptr, ptr %t477
  call void @__inc_ref(ptr %t478)
  %t479 = call ptr @__alloc(i64 16, i32 1)
  %t480 = inttoptr i64 3 to ptr
  %t481 = getelementptr ptr, ptr %t479, i32 0
  store ptr %t480, ptr %t481
  call void @__inc_ref(ptr %t478)
  %t482 = getelementptr ptr, ptr %t479, i32 1
  store ptr %t478, ptr %t482
  call void @__free_recursive(ptr %t478)
  call void @__free_recursive(ptr %t471)
  br label %join.val.483
join.val.483:
  br label %join.after.425
join.case.arm.4.484:
  %t485 = getelementptr ptr, ptr %t471, i32 1
  %t486 = load ptr, ptr %t485
  call void @__inc_ref(ptr %t486)
  %t487 = getelementptr ptr, ptr %t414, i32 1
  %t488 = load ptr, ptr %t487
  call void @__inc_ref(ptr %t488)
  call void @__inc_ref(ptr %t486)
  %t489 = call ptr @__concat(ptr %t488, ptr %t486)
  call void @__free_recursive(ptr %t486)
  call void @__free_recursive(ptr %t471)
  store ptr %t489, ptr %v__inl104_scrut.jslot
  br label %join.424
join.case.default.475:
  unreachable
join.424:
  %t490 = load ptr, ptr %v__inl104_scrut.jslot
  %t491 = getelementptr ptr, ptr %t490, i32 0
  %t492 = load ptr, ptr %t491
  %t493 = ptrtoint ptr %t492 to i64
  switch i64 %t493, label %case.default.494 [ i64 3, label %case.arm.3.496 i64 4, label %case.arm.4.498 ]
case.arm.3.496:
  call void @__inc_ref(ptr %t490)
  br label %case.end.3.497
case.end.3.497:
  br label %case.join.495
case.arm.4.498:
  %t500 = call ptr @v_strWiden()
  %t501 = getelementptr ptr, ptr %t500, i32 0
  %t502 = load ptr, ptr %t501
  %t503 = ptrtoint ptr %t502 to i64
  switch i64 %t503, label %case.default.504 [ i64 3, label %case.arm.3.506 i64 4, label %case.arm.4.522 ]
case.arm.3.506:
  %t508 = getelementptr ptr, ptr %t500, i32 1
  %t509 = load ptr, ptr %t508
  call void @__inc_ref(ptr %t509)
  %t510 = getelementptr ptr, ptr %t509, i32 0
  %t511 = load ptr, ptr %t510
  %t512 = ptrtoint ptr %t511 to i64
  switch i64 %t512, label %case.default.513 [ i64 1615808600, label %case.arm.1615808600.515 i64 2252990199, label %case.arm.2252990199.519 ]
case.arm.1615808600.515:
  %t517 = getelementptr ptr, ptr %t509, i32 1
  %t518 = load ptr, ptr %t517
  call void @__inc_ref(ptr %t518)
  br label %case.end.1615808600.516
case.end.1615808600.516:
  br label %case.join.514
case.arm.2252990199.519:
  br label %case.end.2252990199.520
case.end.2252990199.520:
  br label %case.join.514
case.default.513:
  unreachable
case.join.514:
  %t521 = phi ptr [ %t518, %case.end.1615808600.516 ], [ getelementptr inbounds (i8, ptr @.str.4, i64 12), %case.end.2252990199.520 ]
  call void @__free_recursive(ptr %t509)
  br label %case.end.3.507
case.end.3.507:
  br label %case.join.505
case.arm.4.522:
  %t524 = getelementptr ptr, ptr %t500, i32 1
  %t525 = load ptr, ptr %t524
  call void @__inc_ref(ptr %t525)
  %t526 = call ptr @__showInt32(ptr %t525)
  br label %case.end.4.523
case.end.4.523:
  br label %case.join.505
case.default.504:
  unreachable
case.join.505:
  %t527 = phi ptr [ %t521, %case.end.3.507 ], [ %t526, %case.end.4.523 ]
  call void @__free_recursive(ptr %t500)
  %t528 = call ptr @v_tagged(ptr getelementptr inbounds (i8, ptr @.str.6, i64 12), ptr %t527)
  %t529 = getelementptr ptr, ptr %t528, i32 0
  %t530 = load ptr, ptr %t529
  %t531 = ptrtoint ptr %t530 to i64
  switch i64 %t531, label %case.default.532 [ i64 3, label %case.arm.3.534 i64 4, label %case.arm.4.542 ]
case.arm.3.534:
  %t536 = getelementptr ptr, ptr %t528, i32 1
  %t537 = load ptr, ptr %t536
  call void @__inc_ref(ptr %t537)
  %t538 = call ptr @__alloc(i64 16, i32 1)
  %t539 = inttoptr i64 3 to ptr
  %t540 = getelementptr ptr, ptr %t538, i32 0
  store ptr %t539, ptr %t540
  call void @__inc_ref(ptr %t537)
  %t541 = getelementptr ptr, ptr %t538, i32 1
  store ptr %t537, ptr %t541
  call void @__free_recursive(ptr %t537)
  br label %case.end.3.535
case.end.3.535:
  br label %case.join.533
case.arm.4.542:
  %t544 = getelementptr ptr, ptr %t528, i32 1
  %t545 = load ptr, ptr %t544
  call void @__inc_ref(ptr %t545)
  %t546 = getelementptr ptr, ptr %t490, i32 1
  %t547 = load ptr, ptr %t546
  call void @__inc_ref(ptr %t547)
  call void @__inc_ref(ptr %t545)
  %t548 = call ptr @__concat(ptr %t547, ptr %t545)
  call void @__free_recursive(ptr %t545)
  br label %case.end.4.543
case.end.4.543:
  br label %case.join.533
case.default.532:
  unreachable
case.join.533:
  %t549 = phi ptr [ %t538, %case.end.3.535 ], [ %t548, %case.end.4.543 ]
  call void @__free_recursive(ptr %t528)
  br label %case.end.4.499
case.end.4.499:
  br label %case.join.495
case.default.494:
  unreachable
case.join.495:
  %t550 = phi ptr [ %t490, %case.end.3.497 ], [ %t549, %case.end.4.499 ]
  call void @__free_recursive(ptr %t490)
  br label %join.end.551
join.end.551:
  br label %join.after.425
join.after.425:
  %t552 = phi ptr [ %t479, %join.val.483 ], [ %t550, %join.end.551 ]
  br label %case.end.4.423
case.end.4.423:
  br label %case.join.419
case.default.418:
  unreachable
case.join.419:
  %t553 = phi ptr [ %t414, %case.end.3.421 ], [ %t552, %case.end.4.423 ]
  call void @__free_recursive(ptr %t414)
  br label %join.end.554
join.end.554:
  br label %join.after.349
join.after.349:
  %t555 = phi ptr [ %t403, %join.val.407 ], [ %t553, %join.end.554 ]
  br label %case.end.4.347
case.end.4.347:
  br label %case.join.343
case.default.342:
  unreachable
case.join.343:
  %t556 = phi ptr [ %t338, %case.end.3.345 ], [ %t555, %case.end.4.347 ]
  call void @__free_recursive(ptr %t338)
  br label %join.end.557
join.end.557:
  br label %join.after.277
join.after.277:
  %t558 = phi ptr [ %t327, %join.val.331 ], [ %t556, %join.end.557 ]
  br label %case.end.4.275
case.end.4.275:
  br label %case.join.271
case.default.270:
  unreachable
case.join.271:
  %t559 = phi ptr [ %t266, %case.end.3.273 ], [ %t558, %case.end.4.275 ]
  call void @__free_recursive(ptr %t266)
  br label %join.end.560
join.end.560:
  br label %join.after.217
join.after.217:
  %t561 = phi ptr [ %t255, %join.val.259 ], [ %t559, %join.end.560 ]
  br label %case.end.4.215
case.end.4.215:
  br label %case.join.211
case.default.210:
  unreachable
case.join.211:
  %t562 = phi ptr [ %t206, %case.end.3.213 ], [ %t561, %case.end.4.215 ]
  call void @__free_recursive(ptr %t206)
  br label %join.end.563
join.end.563:
  br label %join.after.157
join.after.157:
  %t564 = phi ptr [ %t195, %join.val.199 ], [ %t562, %join.end.563 ]
  br label %case.end.4.155
case.end.4.155:
  br label %case.join.151
case.default.150:
  unreachable
case.join.151:
  %t565 = phi ptr [ %t146, %case.end.3.153 ], [ %t564, %case.end.4.155 ]
  call void @__free_recursive(ptr %t146)
  br label %join.end.566
join.end.566:
  br label %join.after.100
join.after.100:
  %t567 = phi ptr [ %t135, %join.val.139 ], [ %t565, %join.end.566 ]
  br label %case.end.4.98
case.end.4.98:
  br label %case.join.94
case.default.93:
  unreachable
case.join.94:
  %t568 = phi ptr [ %t89, %case.end.3.96 ], [ %t567, %case.end.4.98 ]
  call void @__free_recursive(ptr %t89)
  br label %join.end.569
join.end.569:
  br label %join.after.45
join.after.45:
  %t570 = phi ptr [ %t80, %join.val.84 ], [ %t568, %join.end.569 ]
  br label %case.end.4.41
case.end.4.41:
  br label %case.join.31
case.default.30:
  unreachable
case.join.31:
  %t571 = phi ptr [ %t36, %case.end.3.33 ], [ %t570, %case.end.4.41 ]
  call void @__free_recursive(ptr %t26)
  ret ptr %t571
}

define internal ptr @v_main() {
  %t0 = call ptr @v_render()
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 3, label %case.arm.3.6 i64 4, label %case.arm.4.14 ]
case.arm.3.6:
  %t8 = call ptr @__alloc(i64 16, i32 1)
  %t9 = inttoptr i64 6 to ptr
  %t10 = getelementptr ptr, ptr %t8, i32 0
  store ptr %t9, ptr %t10
  %t11 = getelementptr ptr, ptr %t0, i32 1
  %t12 = load ptr, ptr %t11
  call void @__inc_ref(ptr %t12)
  %t13 = getelementptr ptr, ptr %t8, i32 1
  store ptr %t12, ptr %t13
  br label %case.end.3.7
case.end.3.7:
  br label %case.join.5
case.arm.4.14:
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 5 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = getelementptr ptr, ptr %t0, i32 1
  %t20 = load ptr, ptr %t19
  call void @__inc_ref(ptr %t20)
  %t21 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t20, ptr %t21
  br label %case.end.4.15
case.end.4.15:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t22 = phi ptr [ %t8, %case.end.3.7 ], [ %t16, %case.end.4.15 ]
  call void @__free_recursive(ptr %t0)
  %t23 = call ptr @__alloc(i64 8, i32 0)
  %t24 = inttoptr i64 30 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  %t26 = call ptr @v__cps__df_andThenIO_4(ptr %t22, ptr %t23)
  %t27 = call ptr @__alloc(i64 8, i32 0)
  %t28 = inttoptr i64 28 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  %t30 = call ptr @v__cps__df_handleErrorIO_0(ptr %t26, ptr %t27)
  ret ptr %t30
}

define internal ptr @v__cps__df_handleErrorIO_0(ptr %v_io, ptr %v__k) {
entry:
  %t3 = alloca ptr
  store ptr %v_io, ptr %t3
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.13 i64 7, label %tco.case.arm.7.27 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t12 = call ptr @v__apply__df_handleErrorIO_0(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t12, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.13:
  call void @__inc_ref(ptr %t6)
  %t14 = call ptr @__alloc(i64 24, i32 2)
  %t15 = inttoptr i64 7 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  %t17 = getelementptr ptr, ptr %t14, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.16, i64 12), ptr %t17
  %t18 = call ptr @__alloc(i64 16, i32 1)
  %t19 = inttoptr i64 5 to ptr
  %t20 = getelementptr ptr, ptr %t18, i32 0
  store ptr %t19, ptr %t20
  %t21 = call ptr @__alloc(i64 8, i32 0)
  %t22 = inttoptr i64 0 to ptr
  %t23 = getelementptr ptr, ptr %t21, i32 0
  store ptr %t22, ptr %t23
  %t24 = getelementptr ptr, ptr %t18, i32 1
  store ptr %t21, ptr %t24
  %t25 = getelementptr ptr, ptr %t14, i32 2
  store ptr %t18, ptr %t25
  %t26 = call ptr @v__apply__df_handleErrorIO_0(ptr %t6, ptr %t14)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t26, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.27:
  %t28 = getelementptr ptr, ptr %t5, i32 1
  %t29 = load ptr, ptr %t28
  %t30 = getelementptr ptr, ptr %t5, i32 2
  %t31 = load ptr, ptr %t30
  call void @__inc_ref(ptr %t31)
  %t38 = getelementptr i8, ptr %t5, i64 -8
  %t39 = load i32, ptr %t38
  %t40 = icmp eq i32 %t39, 1
  br i1 %t40, label %reuse.in_place.41, label %reuse.copy.42
reuse.in_place.41:
  %t32 = getelementptr ptr, ptr %t5, i32 2
  %t33 = load ptr, ptr %t32
  call void @__free_recursive(ptr %t33)
  %t36 = inttoptr i64 29 to ptr
  %t37 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t36, ptr %t37
  call void @__inc_ref(ptr %t6)
  %t34 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t34
  %t35 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t29, ptr %t35
  br label %reuse.in_place.end.44
reuse.in_place.end.44:
  br label %reuse.join.43
reuse.copy.42:
  %t46 = call ptr @__alloc(i64 24, i32 2)
  %t47 = inttoptr i64 29 to ptr
  %t48 = getelementptr ptr, ptr %t46, i32 0
  store ptr %t47, ptr %t48
  call void @__inc_ref(ptr %t6)
  %t49 = getelementptr ptr, ptr %t46, i32 1
  store ptr %t6, ptr %t49
  call void @__inc_ref(ptr %t29)
  %t50 = getelementptr ptr, ptr %t46, i32 2
  store ptr %t29, ptr %t50
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.45
reuse.copy.end.45:
  br label %reuse.join.43
reuse.join.43:
  %t51 = phi ptr [ %t5, %reuse.in_place.end.44 ], [ %t46, %reuse.copy.end.45 ]
  call void @__inc_ref(ptr %t31)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t31)
  store ptr %t31, ptr %t3
  store ptr %t51, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t52 = load ptr, ptr %t2
  ret ptr %t52
}

define internal ptr @v__apply__df_handleErrorIO_0(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 28, label %tco.case.arm.28.11 i64 29, label %tco.case.arm.29.12 ]
tco.case.arm.28.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.29.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  %t15 = getelementptr ptr, ptr %t5, i32 2
  %t16 = load ptr, ptr %t15
  %t17 = getelementptr ptr, ptr %t5, i32 1
  %t18 = load ptr, ptr %t17
  call void @__free_recursive(ptr %t18)
  %t21 = inttoptr i64 7 to ptr
  %t22 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t21, ptr %t22
  %t19 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t16, ptr %t19
  call void @__inc_ref(ptr %t6)
  %t20 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t6, ptr %t20
  call void @__inc_ref(ptr %t14)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t14)
  store ptr %t14, ptr %t3
  store ptr %t5, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t23 = load ptr, ptr %t2
  ret ptr %t23
}

define internal ptr @v__cps__df_andThenIO_4(ptr %v_io, ptr %v__k) {
entry:
  %t3 = alloca ptr
  store ptr %v_io, ptr %t3
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.27 i64 7, label %tco.case.arm.7.29 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t5, i32 1
  %t16 = load ptr, ptr %t15
  call void @__inc_ref(ptr %t16)
  %t17 = getelementptr ptr, ptr %t12, i32 1
  store ptr %t16, ptr %t17
  %t18 = call ptr @__alloc(i64 16, i32 1)
  %t19 = inttoptr i64 5 to ptr
  %t20 = getelementptr ptr, ptr %t18, i32 0
  store ptr %t19, ptr %t20
  %t21 = call ptr @__alloc(i64 8, i32 0)
  %t22 = inttoptr i64 0 to ptr
  %t23 = getelementptr ptr, ptr %t21, i32 0
  store ptr %t22, ptr %t23
  %t24 = getelementptr ptr, ptr %t18, i32 1
  store ptr %t21, ptr %t24
  %t25 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t18, ptr %t25
  %t26 = call ptr @v__apply__df_andThenIO_4(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t26, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.27:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t28 = call ptr @v__apply__df_andThenIO_4(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t28, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.29:
  %t30 = getelementptr ptr, ptr %t5, i32 1
  %t31 = load ptr, ptr %t30
  %t32 = getelementptr ptr, ptr %t5, i32 2
  %t33 = load ptr, ptr %t32
  call void @__inc_ref(ptr %t33)
  %t40 = getelementptr i8, ptr %t5, i64 -8
  %t41 = load i32, ptr %t40
  %t42 = icmp eq i32 %t41, 1
  br i1 %t42, label %reuse.in_place.43, label %reuse.copy.44
reuse.in_place.43:
  %t34 = getelementptr ptr, ptr %t5, i32 2
  %t35 = load ptr, ptr %t34
  call void @__free_recursive(ptr %t35)
  %t38 = inttoptr i64 31 to ptr
  %t39 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t38, ptr %t39
  call void @__inc_ref(ptr %t6)
  %t36 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t36
  %t37 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t31, ptr %t37
  br label %reuse.in_place.end.46
reuse.in_place.end.46:
  br label %reuse.join.45
reuse.copy.44:
  %t48 = call ptr @__alloc(i64 24, i32 2)
  %t49 = inttoptr i64 31 to ptr
  %t50 = getelementptr ptr, ptr %t48, i32 0
  store ptr %t49, ptr %t50
  call void @__inc_ref(ptr %t6)
  %t51 = getelementptr ptr, ptr %t48, i32 1
  store ptr %t6, ptr %t51
  call void @__inc_ref(ptr %t31)
  %t52 = getelementptr ptr, ptr %t48, i32 2
  store ptr %t31, ptr %t52
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.47
reuse.copy.end.47:
  br label %reuse.join.45
reuse.join.45:
  %t53 = phi ptr [ %t5, %reuse.in_place.end.46 ], [ %t48, %reuse.copy.end.47 ]
  call void @__inc_ref(ptr %t33)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t33)
  store ptr %t33, ptr %t3
  store ptr %t53, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t54 = load ptr, ptr %t2
  ret ptr %t54
}

define internal ptr @v__apply__df_andThenIO_4(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 30, label %tco.case.arm.30.11 i64 31, label %tco.case.arm.31.12 ]
tco.case.arm.30.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.31.12:
  %t13 = getelementptr ptr, ptr %t5, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  %t15 = getelementptr ptr, ptr %t5, i32 2
  %t16 = load ptr, ptr %t15
  %t17 = getelementptr ptr, ptr %t5, i32 1
  %t18 = load ptr, ptr %t17
  call void @__free_recursive(ptr %t18)
  %t21 = inttoptr i64 7 to ptr
  %t22 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t21, ptr %t22
  %t19 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t16, ptr %t19
  call void @__inc_ref(ptr %t6)
  %t20 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t6, ptr %t20
  call void @__inc_ref(ptr %t14)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t14)
  store ptr %t14, ptr %t3
  store ptr %t5, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t23 = load ptr, ptr %t2
  ret ptr %t23
}

define i32 @main(i32 %argc, ptr %argv) {
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
