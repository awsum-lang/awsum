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

@.str.0 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"seedS" }
@.str.1 = private unnamed_addr constant {i32, i32, i32, i32, i32, [2 x i8]} { i32 0, i32 0, i32 0, i32 2, i32 2, [2 x i8] c"kS" }
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"=" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"\0A" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"nevOk" }
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"ErrA" }
@.str.6 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"wOk" }
@.str.7 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"First" }
@.str.8 = private unnamed_addr constant {i32, i32, i32, i32, i32, [6 x i8]} { i32 0, i32 0, i32 0, i32 6, i32 6, [6 x i8] c"Second" }
@.str.9 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"wE3" }
@.str.10 = private unnamed_addr constant {i32, i32, i32, i32, i32, [6 x i8]} { i32 0, i32 0, i32 0, i32 6, i32 6, [6 x i8] c"wE2str" }
@.str.11 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"wE1" }
@.str.12 = private unnamed_addr constant {i32, i32, i32, i32, i32, [11 x i8]} { i32 0, i32 0, i32 0, i32 11, i32 11, [11 x i8] c"idem2Second" }
@.str.13 = private unnamed_addr constant {i32, i32, i32, i32, i32, [10 x i8]} { i32 0, i32 0, i32 0, i32 10, i32 10, [10 x i8] c"idem2First" }
@.str.14 = private unnamed_addr constant {i32, i32, i32, i32, i32, [6 x i8]} { i32 0, i32 0, i32 0, i32 6, i32 6, [6 x i8] c"idemE2" }
@.str.15 = private unnamed_addr constant {i32, i32, i32, i32, i32, [6 x i8]} { i32 0, i32 0, i32 0, i32 6, i32 6, [6 x i8] c"idemE1" }
@.str.16 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"twoOk" }
@.str.17 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"twoE2" }
@.str.18 = private unnamed_addr constant {i32, i32, i32, i32, i32, [9 x i8]} { i32 0, i32 0, i32 0, i32 9, i32 9, [9 x i8] c"twoSecond" }
@.str.19 = private unnamed_addr constant {i32, i32, i32, i32, i32, [8 x i8]} { i32 0, i32 0, i32 0, i32 8, i32 8, [8 x i8] c"twoFirst" }
@.str.20 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"abE2" }
@.str.21 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"ErrB" }
@.str.22 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"abE1" }
@.str.23 = private unnamed_addr constant {i32, i32, i32, i32, i32, [7 x i8]} { i32 0, i32 0, i32 0, i32 7, i32 7, [7 x i8] c"strIdem" }
@.str.24 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"strE2" }
@.str.25 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"strE1" }
@.str.26 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"strOk" }
@.str.27 = private unnamed_addr constant {i32, i32, i32, i32, i32, [9 x i8]} { i32 0, i32 0, i32 0, i32 9, i32 9, [9 x i8] c"pureNever" }
@.str.28 = private unnamed_addr constant {i32, i32, i32, i32, i32, [10 x i8]} { i32 0, i32 0, i32 0, i32 10, i32 10, [10 x i8] c"nevRightE1" }
@.str.29 = private unnamed_addr constant {i32, i32, i32, i32, i32, [10 x i8]} { i32 0, i32 0, i32 0, i32 10, i32 10, [10 x i8] c"nevRightOk" }
@.str.30 = private unnamed_addr constant {i32, i32, i32, i32, i32, [7 x i8]} { i32 0, i32 0, i32 0, i32 7, i32 7, [7 x i8] c"nevFail" }
@.str.31 = private unnamed_addr constant {i32, i32, i32, i32, i32, [15 x i8]} { i32 0, i32 0, i32 0, i32 15, i32 15, [15 x i8] c"STRING_TOO_LONG" }

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

define internal ptr @v_seedNever() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 4 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 4, i32 0)
  store i32 1, ptr %t3
  %t4 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t4
  ret ptr %t0
}

define internal ptr @v_seedA() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 4 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 4, i32 0)
  store i32 2, ptr %t3
  %t4 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t4
  ret ptr %t0
}

define internal ptr @v_seedLeftA() {
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

define internal ptr @v_seedS() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 4 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 4, i32 0)
  store i32 3, ptr %t3
  %t4 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t4
  ret ptr %t0
}

define internal ptr @v_seedLeftS() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 3 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.0, i64 12), ptr %t3
  ret ptr %t0
}

define internal ptr @v_seedT() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 4 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 4, i32 0)
  store i32 4, ptr %t3
  %t4 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t4
  ret ptr %t0
}

define internal ptr @v_seedFirst() {
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

define internal ptr @v_seedSecond() {
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

define internal ptr @v_nevOk() {
  %t0 = call ptr @v_seedNever()
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 3, label %case.arm.3.6 i64 4, label %case.arm.4.8 ]
case.arm.3.6:
  call void @__inc_ref(ptr %t0)
  br label %case.end.3.7
case.end.3.7:
  br label %case.join.5
case.arm.4.8:
  %t10 = call ptr @__alloc(i64 16, i32 1)
  %t11 = inttoptr i64 4 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  %t13 = getelementptr ptr, ptr %t0, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  %t15 = getelementptr ptr, ptr %t10, i32 1
  store ptr %t14, ptr %t15
  br label %case.end.4.9
case.end.4.9:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t16 = phi ptr [ %t0, %case.end.3.7 ], [ %t10, %case.end.4.9 ]
  call void @__free_recursive(ptr %t0)
  ret ptr %t16
}

define internal ptr @v_nevFail() {
  %t0 = call ptr @v_seedNever()
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 3, label %case.arm.3.6 i64 4, label %case.arm.4.8 ]
case.arm.3.6:
  call void @__inc_ref(ptr %t0)
  br label %case.end.3.7
case.end.3.7:
  br label %case.join.5
case.arm.4.8:
  %t10 = call ptr @__alloc(i64 16, i32 1)
  %t11 = inttoptr i64 3 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  %t13 = call ptr @__alloc(i64 8, i32 0)
  %t14 = inttoptr i64 24 to ptr
  %t15 = getelementptr ptr, ptr %t13, i32 0
  store ptr %t14, ptr %t15
  %t16 = getelementptr ptr, ptr %t10, i32 1
  store ptr %t13, ptr %t16
  br label %case.end.4.9
case.end.4.9:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t17 = phi ptr [ %t0, %case.end.3.7 ], [ %t10, %case.end.4.9 ]
  call void @__free_recursive(ptr %t0)
  ret ptr %t17
}

define internal ptr @v_nevRightOk() {
  %t0 = call ptr @v_seedA()
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 3, label %case.arm.3.6 i64 4, label %case.arm.4.8 ]
case.arm.3.6:
  call void @__inc_ref(ptr %t0)
  br label %case.end.3.7
case.end.3.7:
  br label %case.join.5
case.arm.4.8:
  %t10 = call ptr @__alloc(i64 16, i32 1)
  %t11 = inttoptr i64 4 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  %t13 = getelementptr ptr, ptr %t0, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  %t15 = getelementptr ptr, ptr %t10, i32 1
  store ptr %t14, ptr %t15
  br label %case.end.4.9
case.end.4.9:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t16 = phi ptr [ %t0, %case.end.3.7 ], [ %t10, %case.end.4.9 ]
  call void @__free_recursive(ptr %t0)
  ret ptr %t16
}

define internal ptr @v_nevRightE1() {
  %t0 = call ptr @v_seedLeftA()
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 3, label %case.arm.3.6 i64 4, label %case.arm.4.8 ]
case.arm.3.6:
  call void @__inc_ref(ptr %t0)
  br label %case.end.3.7
case.end.3.7:
  br label %case.join.5
case.arm.4.8:
  %t10 = call ptr @__alloc(i64 16, i32 1)
  %t11 = inttoptr i64 4 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  %t13 = getelementptr ptr, ptr %t0, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  %t15 = getelementptr ptr, ptr %t10, i32 1
  store ptr %t14, ptr %t15
  br label %case.end.4.9
case.end.4.9:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t16 = phi ptr [ %t0, %case.end.3.7 ], [ %t10, %case.end.4.9 ]
  call void @__free_recursive(ptr %t0)
  ret ptr %t16
}

define internal ptr @v_pureNever() {
  %t0 = call ptr @v_seedNever()
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 3, label %case.arm.3.6 i64 4, label %case.arm.4.8 ]
case.arm.3.6:
  call void @__inc_ref(ptr %t0)
  br label %case.end.3.7
case.end.3.7:
  br label %case.join.5
case.arm.4.8:
  %t10 = call ptr @__alloc(i64 16, i32 1)
  %t11 = inttoptr i64 4 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  %t13 = getelementptr ptr, ptr %t0, i32 1
  %t14 = load ptr, ptr %t13
  call void @__inc_ref(ptr %t14)
  %t15 = getelementptr ptr, ptr %t10, i32 1
  store ptr %t14, ptr %t15
  br label %case.end.4.9
case.end.4.9:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t16 = phi ptr [ %t0, %case.end.3.7 ], [ %t10, %case.end.4.9 ]
  call void @__free_recursive(ptr %t0)
  ret ptr %t16
}

define internal ptr @v_strOk() {
  %t0 = call ptr @v_seedS()
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
  %t20 = call ptr @__alloc(i64 16, i32 1)
  %t21 = inttoptr i64 4 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = getelementptr ptr, ptr %t0, i32 1
  %t24 = load ptr, ptr %t23
  call void @__inc_ref(ptr %t24)
  %t25 = getelementptr ptr, ptr %t20, i32 1
  store ptr %t24, ptr %t25
  %t26 = getelementptr ptr, ptr %t20, i32 0
  %t27 = load ptr, ptr %t26
  %t28 = ptrtoint ptr %t27 to i64
  switch i64 %t28, label %case.default.29 [ i64 3, label %case.arm.3.31 i64 4, label %case.arm.4.43 ]
case.arm.3.31:
  %t33 = call ptr @__alloc(i64 16, i32 1)
  %t34 = inttoptr i64 3 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = call ptr @__alloc(i64 16, i32 1)
  %t37 = inttoptr i64 2252990199 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t20, i32 1
  %t40 = load ptr, ptr %t39
  call void @__inc_ref(ptr %t40)
  %t41 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t40, ptr %t41
  %t42 = getelementptr ptr, ptr %t33, i32 1
  store ptr %t36, ptr %t42
  br label %case.end.3.32
case.end.3.32:
  br label %case.join.30
case.arm.4.43:
  call void @__inc_ref(ptr %t20)
  br label %case.end.4.44
case.end.4.44:
  br label %case.join.30
case.default.29:
  unreachable
case.join.30:
  %t45 = phi ptr [ %t33, %case.end.3.32 ], [ %t20, %case.end.4.44 ]
  call void @__free_recursive(ptr %t20)
  br label %case.end.4.19
case.end.4.19:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t46 = phi ptr [ %t8, %case.end.3.7 ], [ %t45, %case.end.4.19 ]
  call void @__free_recursive(ptr %t0)
  ret ptr %t46
}

define internal ptr @v_strE1() {
  %t0 = call ptr @v_seedLeftS()
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
  %t20 = call ptr @__alloc(i64 16, i32 1)
  %t21 = inttoptr i64 4 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = getelementptr ptr, ptr %t0, i32 1
  %t24 = load ptr, ptr %t23
  call void @__inc_ref(ptr %t24)
  %t25 = getelementptr ptr, ptr %t20, i32 1
  store ptr %t24, ptr %t25
  %t26 = getelementptr ptr, ptr %t20, i32 0
  %t27 = load ptr, ptr %t26
  %t28 = ptrtoint ptr %t27 to i64
  switch i64 %t28, label %case.default.29 [ i64 3, label %case.arm.3.31 i64 4, label %case.arm.4.43 ]
case.arm.3.31:
  %t33 = call ptr @__alloc(i64 16, i32 1)
  %t34 = inttoptr i64 3 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = call ptr @__alloc(i64 16, i32 1)
  %t37 = inttoptr i64 2252990199 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t20, i32 1
  %t40 = load ptr, ptr %t39
  call void @__inc_ref(ptr %t40)
  %t41 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t40, ptr %t41
  %t42 = getelementptr ptr, ptr %t33, i32 1
  store ptr %t36, ptr %t42
  br label %case.end.3.32
case.end.3.32:
  br label %case.join.30
case.arm.4.43:
  call void @__inc_ref(ptr %t20)
  br label %case.end.4.44
case.end.4.44:
  br label %case.join.30
case.default.29:
  unreachable
case.join.30:
  %t45 = phi ptr [ %t33, %case.end.3.32 ], [ %t20, %case.end.4.44 ]
  call void @__free_recursive(ptr %t20)
  br label %case.end.4.19
case.end.4.19:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t46 = phi ptr [ %t8, %case.end.3.7 ], [ %t45, %case.end.4.19 ]
  call void @__free_recursive(ptr %t0)
  ret ptr %t46
}

define internal ptr @v_strE2() {
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
  %t7 = getelementptr ptr, ptr %t0, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %case.default.10 [ i64 3, label %case.arm.3.12 i64 4, label %case.arm.4.24 ]
case.arm.3.12:
  %t14 = call ptr @__alloc(i64 16, i32 1)
  %t15 = inttoptr i64 3 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  %t17 = call ptr @__alloc(i64 16, i32 1)
  %t18 = inttoptr i64 2252990199 to ptr
  %t19 = getelementptr ptr, ptr %t17, i32 0
  store ptr %t18, ptr %t19
  %t20 = getelementptr ptr, ptr %t0, i32 1
  %t21 = load ptr, ptr %t20
  call void @__inc_ref(ptr %t21)
  %t22 = getelementptr ptr, ptr %t17, i32 1
  store ptr %t21, ptr %t22
  %t23 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t17, ptr %t23
  br label %case.end.3.13
case.end.3.13:
  br label %case.join.11
case.arm.4.24:
  call void @__inc_ref(ptr %t0)
  br label %case.end.4.25
case.end.4.25:
  br label %case.join.11
case.default.10:
  unreachable
case.join.11:
  %t26 = phi ptr [ %t14, %case.end.3.13 ], [ %t0, %case.end.4.25 ]
  call void @__free_recursive(ptr %t0)
  ret ptr %t26
}

define internal ptr @v_strIdem() {
  %t0 = call ptr @v_seedS()
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 3, label %case.arm.3.6 i64 4, label %case.arm.4.8 ]
case.arm.3.6:
  call void @__inc_ref(ptr %t0)
  br label %case.end.3.7
case.end.3.7:
  br label %case.join.5
case.arm.4.8:
  %t10 = call ptr @__alloc(i64 16, i32 1)
  %t11 = inttoptr i64 3 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  %t13 = getelementptr ptr, ptr %t10, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t13
  br label %case.end.4.9
case.end.4.9:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t14 = phi ptr [ %t0, %case.end.3.7 ], [ %t10, %case.end.4.9 ]
  call void @__free_recursive(ptr %t0)
  ret ptr %t14
}

define internal ptr @v_abE1() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 3 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = call ptr @__alloc(i64 16, i32 1)
  %t4 = inttoptr i64 2252990199 to ptr
  %t5 = getelementptr ptr, ptr %t3, i32 0
  store ptr %t4, ptr %t5
  %t6 = call ptr @__alloc(i64 8, i32 0)
  %t7 = inttoptr i64 24 to ptr
  %t8 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t7, ptr %t8
  %t9 = getelementptr ptr, ptr %t3, i32 1
  store ptr %t6, ptr %t9
  %t10 = getelementptr ptr, ptr %t0, i32 1
  store ptr %t3, ptr %t10
  ret ptr %t0
}

define internal ptr @v_abE2() {
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
  %t7 = getelementptr ptr, ptr %t0, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %case.default.10 [ i64 3, label %case.arm.3.12 i64 4, label %case.arm.4.24 ]
case.arm.3.12:
  %t14 = call ptr @__alloc(i64 16, i32 1)
  %t15 = inttoptr i64 3 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  %t17 = call ptr @__alloc(i64 16, i32 1)
  %t18 = inttoptr i64 2269767818 to ptr
  %t19 = getelementptr ptr, ptr %t17, i32 0
  store ptr %t18, ptr %t19
  %t20 = getelementptr ptr, ptr %t0, i32 1
  %t21 = load ptr, ptr %t20
  call void @__inc_ref(ptr %t21)
  %t22 = getelementptr ptr, ptr %t17, i32 1
  store ptr %t21, ptr %t22
  %t23 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t17, ptr %t23
  br label %case.end.3.13
case.end.3.13:
  br label %case.join.11
case.arm.4.24:
  call void @__inc_ref(ptr %t0)
  br label %case.end.4.25
case.end.4.25:
  br label %case.join.11
case.default.10:
  unreachable
case.join.11:
  %t26 = phi ptr [ %t14, %case.end.3.13 ], [ %t0, %case.end.4.25 ]
  call void @__free_recursive(ptr %t0)
  ret ptr %t26
}

define internal ptr @v_twoFirst() {
  %t0 = call ptr @v_seedFirst()
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
  %t12 = inttoptr i64 925038822 to ptr
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
  %t20 = call ptr @__alloc(i64 16, i32 1)
  %t21 = inttoptr i64 4 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = getelementptr ptr, ptr %t0, i32 1
  %t24 = load ptr, ptr %t23
  call void @__inc_ref(ptr %t24)
  %t25 = getelementptr ptr, ptr %t20, i32 1
  store ptr %t24, ptr %t25
  %t26 = getelementptr ptr, ptr %t20, i32 0
  %t27 = load ptr, ptr %t26
  %t28 = ptrtoint ptr %t27 to i64
  switch i64 %t28, label %case.default.29 [ i64 3, label %case.arm.3.31 i64 4, label %case.arm.4.43 ]
case.arm.3.31:
  %t33 = call ptr @__alloc(i64 16, i32 1)
  %t34 = inttoptr i64 3 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = call ptr @__alloc(i64 16, i32 1)
  %t37 = inttoptr i64 2252990199 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t20, i32 1
  %t40 = load ptr, ptr %t39
  call void @__inc_ref(ptr %t40)
  %t41 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t40, ptr %t41
  %t42 = getelementptr ptr, ptr %t33, i32 1
  store ptr %t36, ptr %t42
  br label %case.end.3.32
case.end.3.32:
  br label %case.join.30
case.arm.4.43:
  call void @__inc_ref(ptr %t20)
  br label %case.end.4.44
case.end.4.44:
  br label %case.join.30
case.default.29:
  unreachable
case.join.30:
  %t45 = phi ptr [ %t33, %case.end.3.32 ], [ %t20, %case.end.4.44 ]
  call void @__free_recursive(ptr %t20)
  br label %case.end.4.19
case.end.4.19:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t46 = phi ptr [ %t8, %case.end.3.7 ], [ %t45, %case.end.4.19 ]
  call void @__free_recursive(ptr %t0)
  ret ptr %t46
}

define internal ptr @v_twoSecond() {
  %t0 = call ptr @v_seedSecond()
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
  %t12 = inttoptr i64 925038822 to ptr
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
  %t20 = call ptr @__alloc(i64 16, i32 1)
  %t21 = inttoptr i64 4 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = getelementptr ptr, ptr %t0, i32 1
  %t24 = load ptr, ptr %t23
  call void @__inc_ref(ptr %t24)
  %t25 = getelementptr ptr, ptr %t20, i32 1
  store ptr %t24, ptr %t25
  %t26 = getelementptr ptr, ptr %t20, i32 0
  %t27 = load ptr, ptr %t26
  %t28 = ptrtoint ptr %t27 to i64
  switch i64 %t28, label %case.default.29 [ i64 3, label %case.arm.3.31 i64 4, label %case.arm.4.43 ]
case.arm.3.31:
  %t33 = call ptr @__alloc(i64 16, i32 1)
  %t34 = inttoptr i64 3 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = call ptr @__alloc(i64 16, i32 1)
  %t37 = inttoptr i64 2252990199 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t20, i32 1
  %t40 = load ptr, ptr %t39
  call void @__inc_ref(ptr %t40)
  %t41 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t40, ptr %t41
  %t42 = getelementptr ptr, ptr %t33, i32 1
  store ptr %t36, ptr %t42
  br label %case.end.3.32
case.end.3.32:
  br label %case.join.30
case.arm.4.43:
  call void @__inc_ref(ptr %t20)
  br label %case.end.4.44
case.end.4.44:
  br label %case.join.30
case.default.29:
  unreachable
case.join.30:
  %t45 = phi ptr [ %t33, %case.end.3.32 ], [ %t20, %case.end.4.44 ]
  call void @__free_recursive(ptr %t20)
  br label %case.end.4.19
case.end.4.19:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t46 = phi ptr [ %t8, %case.end.3.7 ], [ %t45, %case.end.4.19 ]
  call void @__free_recursive(ptr %t0)
  ret ptr %t46
}

define internal ptr @v_twoE2() {
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
  %t7 = getelementptr ptr, ptr %t0, i32 0
  %t8 = load ptr, ptr %t7
  %t9 = ptrtoint ptr %t8 to i64
  switch i64 %t9, label %case.default.10 [ i64 3, label %case.arm.3.12 i64 4, label %case.arm.4.24 ]
case.arm.3.12:
  %t14 = call ptr @__alloc(i64 16, i32 1)
  %t15 = inttoptr i64 3 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  %t17 = call ptr @__alloc(i64 16, i32 1)
  %t18 = inttoptr i64 2252990199 to ptr
  %t19 = getelementptr ptr, ptr %t17, i32 0
  store ptr %t18, ptr %t19
  %t20 = getelementptr ptr, ptr %t0, i32 1
  %t21 = load ptr, ptr %t20
  call void @__inc_ref(ptr %t21)
  %t22 = getelementptr ptr, ptr %t17, i32 1
  store ptr %t21, ptr %t22
  %t23 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t17, ptr %t23
  br label %case.end.3.13
case.end.3.13:
  br label %case.join.11
case.arm.4.24:
  call void @__inc_ref(ptr %t0)
  br label %case.end.4.25
case.end.4.25:
  br label %case.join.11
case.default.10:
  unreachable
case.join.11:
  %t26 = phi ptr [ %t14, %case.end.3.13 ], [ %t0, %case.end.4.25 ]
  call void @__free_recursive(ptr %t0)
  ret ptr %t26
}

define internal ptr @v_twoOk() {
  %t0 = call ptr @v_seedT()
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
  %t12 = inttoptr i64 925038822 to ptr
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
  %t20 = call ptr @__alloc(i64 16, i32 1)
  %t21 = inttoptr i64 4 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = getelementptr ptr, ptr %t0, i32 1
  %t24 = load ptr, ptr %t23
  call void @__inc_ref(ptr %t24)
  %t25 = getelementptr ptr, ptr %t20, i32 1
  store ptr %t24, ptr %t25
  %t26 = getelementptr ptr, ptr %t20, i32 0
  %t27 = load ptr, ptr %t26
  %t28 = ptrtoint ptr %t27 to i64
  switch i64 %t28, label %case.default.29 [ i64 3, label %case.arm.3.31 i64 4, label %case.arm.4.43 ]
case.arm.3.31:
  %t33 = call ptr @__alloc(i64 16, i32 1)
  %t34 = inttoptr i64 3 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = call ptr @__alloc(i64 16, i32 1)
  %t37 = inttoptr i64 2252990199 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t20, i32 1
  %t40 = load ptr, ptr %t39
  call void @__inc_ref(ptr %t40)
  %t41 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t40, ptr %t41
  %t42 = getelementptr ptr, ptr %t33, i32 1
  store ptr %t36, ptr %t42
  br label %case.end.3.32
case.end.3.32:
  br label %case.join.30
case.arm.4.43:
  call void @__inc_ref(ptr %t20)
  br label %case.end.4.44
case.end.4.44:
  br label %case.join.30
case.default.29:
  unreachable
case.join.30:
  %t45 = phi ptr [ %t33, %case.end.3.32 ], [ %t20, %case.end.4.44 ]
  call void @__free_recursive(ptr %t20)
  br label %case.end.4.19
case.end.4.19:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t46 = phi ptr [ %t8, %case.end.3.7 ], [ %t45, %case.end.4.19 ]
  call void @__free_recursive(ptr %t0)
  ret ptr %t46
}

define internal ptr @v_idemE1() {
  %t0 = call ptr @v_seedLeftA()
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 3, label %case.arm.3.6 i64 4, label %case.arm.4.8 ]
case.arm.3.6:
  call void @__inc_ref(ptr %t0)
  br label %case.end.3.7
case.end.3.7:
  br label %case.join.5
case.arm.4.8:
  %t10 = call ptr @__alloc(i64 16, i32 1)
  %t11 = inttoptr i64 3 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  %t13 = call ptr @__alloc(i64 8, i32 0)
  %t14 = inttoptr i64 24 to ptr
  %t15 = getelementptr ptr, ptr %t13, i32 0
  store ptr %t14, ptr %t15
  %t16 = getelementptr ptr, ptr %t10, i32 1
  store ptr %t13, ptr %t16
  br label %case.end.4.9
case.end.4.9:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t17 = phi ptr [ %t0, %case.end.3.7 ], [ %t10, %case.end.4.9 ]
  call void @__free_recursive(ptr %t0)
  ret ptr %t17
}

define internal ptr @v_idemE2() {
  %t0 = call ptr @v_seedA()
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 3, label %case.arm.3.6 i64 4, label %case.arm.4.8 ]
case.arm.3.6:
  call void @__inc_ref(ptr %t0)
  br label %case.end.3.7
case.end.3.7:
  br label %case.join.5
case.arm.4.8:
  %t10 = call ptr @__alloc(i64 16, i32 1)
  %t11 = inttoptr i64 3 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  %t13 = call ptr @__alloc(i64 8, i32 0)
  %t14 = inttoptr i64 24 to ptr
  %t15 = getelementptr ptr, ptr %t13, i32 0
  store ptr %t14, ptr %t15
  %t16 = getelementptr ptr, ptr %t10, i32 1
  store ptr %t13, ptr %t16
  br label %case.end.4.9
case.end.4.9:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t17 = phi ptr [ %t0, %case.end.3.7 ], [ %t10, %case.end.4.9 ]
  call void @__free_recursive(ptr %t0)
  ret ptr %t17
}

define internal ptr @v_idem2First() {
  %t0 = call ptr @v_seedFirst()
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 3, label %case.arm.3.6 i64 4, label %case.arm.4.8 ]
case.arm.3.6:
  call void @__inc_ref(ptr %t0)
  br label %case.end.3.7
case.end.3.7:
  br label %case.join.5
case.arm.4.8:
  %t10 = call ptr @__alloc(i64 16, i32 1)
  %t11 = inttoptr i64 3 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  %t13 = call ptr @__alloc(i64 8, i32 0)
  %t14 = inttoptr i64 27 to ptr
  %t15 = getelementptr ptr, ptr %t13, i32 0
  store ptr %t14, ptr %t15
  %t16 = getelementptr ptr, ptr %t10, i32 1
  store ptr %t13, ptr %t16
  br label %case.end.4.9
case.end.4.9:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t17 = phi ptr [ %t0, %case.end.3.7 ], [ %t10, %case.end.4.9 ]
  call void @__free_recursive(ptr %t0)
  ret ptr %t17
}

define internal ptr @v_idem2Second() {
  %t0 = call ptr @v_seedT()
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 3, label %case.arm.3.6 i64 4, label %case.arm.4.8 ]
case.arm.3.6:
  call void @__inc_ref(ptr %t0)
  br label %case.end.3.7
case.end.3.7:
  br label %case.join.5
case.arm.4.8:
  %t10 = call ptr @__alloc(i64 16, i32 1)
  %t11 = inttoptr i64 3 to ptr
  %t12 = getelementptr ptr, ptr %t10, i32 0
  store ptr %t11, ptr %t12
  %t13 = call ptr @__alloc(i64 8, i32 0)
  %t14 = inttoptr i64 27 to ptr
  %t15 = getelementptr ptr, ptr %t13, i32 0
  store ptr %t14, ptr %t15
  %t16 = getelementptr ptr, ptr %t10, i32 1
  store ptr %t13, ptr %t16
  br label %case.end.4.9
case.end.4.9:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t17 = phi ptr [ %t0, %case.end.3.7 ], [ %t10, %case.end.4.9 ]
  call void @__free_recursive(ptr %t0)
  ret ptr %t17
}

define internal ptr @v_wE1() {
  %t0 = call ptr @v_seedFirst()
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
  %t12 = inttoptr i64 925038822 to ptr
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
  %t20 = call ptr @__alloc(i64 16, i32 1)
  %t21 = inttoptr i64 4 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = getelementptr ptr, ptr %t0, i32 1
  %t24 = load ptr, ptr %t23
  call void @__inc_ref(ptr %t24)
  %t25 = getelementptr ptr, ptr %t20, i32 1
  store ptr %t24, ptr %t25
  %t26 = getelementptr ptr, ptr %t20, i32 0
  %t27 = load ptr, ptr %t26
  %t28 = ptrtoint ptr %t27 to i64
  switch i64 %t28, label %case.default.29 [ i64 3, label %case.arm.3.31 i64 4, label %case.arm.4.43 ]
case.arm.3.31:
  %t33 = call ptr @__alloc(i64 16, i32 1)
  %t34 = inttoptr i64 3 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = call ptr @__alloc(i64 16, i32 1)
  %t37 = inttoptr i64 1615808600 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t20, i32 1
  %t40 = load ptr, ptr %t39
  call void @__inc_ref(ptr %t40)
  %t41 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t40, ptr %t41
  %t42 = getelementptr ptr, ptr %t33, i32 1
  store ptr %t36, ptr %t42
  br label %case.end.3.32
case.end.3.32:
  br label %case.join.30
case.arm.4.43:
  call void @__inc_ref(ptr %t20)
  br label %case.end.4.44
case.end.4.44:
  br label %case.join.30
case.default.29:
  unreachable
case.join.30:
  %t45 = phi ptr [ %t33, %case.end.3.32 ], [ %t20, %case.end.4.44 ]
  call void @__free_recursive(ptr %t20)
  br label %case.end.4.19
case.end.4.19:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t46 = phi ptr [ %t8, %case.end.3.7 ], [ %t45, %case.end.4.19 ]
  call void @__free_recursive(ptr %t0)
  %t47 = getelementptr ptr, ptr %t46, i32 0
  %t48 = load ptr, ptr %t47
  %t49 = ptrtoint ptr %t48 to i64
  switch i64 %t49, label %case.default.50 [ i64 3, label %case.arm.3.52 i64 4, label %case.arm.4.54 ]
case.arm.3.52:
  call void @__inc_ref(ptr %t46)
  br label %case.end.3.53
case.end.3.53:
  br label %case.join.51
case.arm.4.54:
  %t56 = call ptr @__alloc(i64 16, i32 1)
  %t57 = inttoptr i64 4 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  %t59 = getelementptr ptr, ptr %t46, i32 1
  %t60 = load ptr, ptr %t59
  call void @__inc_ref(ptr %t60)
  %t61 = getelementptr ptr, ptr %t56, i32 1
  store ptr %t60, ptr %t61
  %t62 = getelementptr ptr, ptr %t56, i32 0
  %t63 = load ptr, ptr %t62
  %t64 = ptrtoint ptr %t63 to i64
  switch i64 %t64, label %case.default.65 [ i64 3, label %case.arm.3.67 i64 4, label %case.arm.4.79 ]
case.arm.3.67:
  %t69 = call ptr @__alloc(i64 16, i32 1)
  %t70 = inttoptr i64 3 to ptr
  %t71 = getelementptr ptr, ptr %t69, i32 0
  store ptr %t70, ptr %t71
  %t72 = call ptr @__alloc(i64 16, i32 1)
  %t73 = inttoptr i64 2252990199 to ptr
  %t74 = getelementptr ptr, ptr %t72, i32 0
  store ptr %t73, ptr %t74
  %t75 = getelementptr ptr, ptr %t56, i32 1
  %t76 = load ptr, ptr %t75
  call void @__inc_ref(ptr %t76)
  %t77 = getelementptr ptr, ptr %t72, i32 1
  store ptr %t76, ptr %t77
  %t78 = getelementptr ptr, ptr %t69, i32 1
  store ptr %t72, ptr %t78
  br label %case.end.3.68
case.end.3.68:
  br label %case.join.66
case.arm.4.79:
  call void @__inc_ref(ptr %t56)
  br label %case.end.4.80
case.end.4.80:
  br label %case.join.66
case.default.65:
  unreachable
case.join.66:
  %t81 = phi ptr [ %t69, %case.end.3.68 ], [ %t56, %case.end.4.80 ]
  call void @__free_recursive(ptr %t56)
  br label %case.end.4.55
case.end.4.55:
  br label %case.join.51
case.default.50:
  unreachable
case.join.51:
  %t82 = phi ptr [ %t46, %case.end.3.53 ], [ %t81, %case.end.4.55 ]
  call void @__free_recursive(ptr %t46)
  ret ptr %t82
}

define internal ptr @v_wE2str() {
  %t0 = call ptr @__alloc(i64 16, i32 1)
  %t1 = inttoptr i64 3 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.1, i64 12), ptr %t3
  %t4 = getelementptr ptr, ptr %t0, i32 0
  %t5 = load ptr, ptr %t4
  %t6 = ptrtoint ptr %t5 to i64
  switch i64 %t6, label %case.default.7 [ i64 3, label %case.arm.3.9 i64 4, label %case.arm.4.21 ]
case.arm.3.9:
  %t11 = call ptr @__alloc(i64 16, i32 1)
  %t12 = inttoptr i64 3 to ptr
  %t13 = getelementptr ptr, ptr %t11, i32 0
  store ptr %t12, ptr %t13
  %t14 = call ptr @__alloc(i64 16, i32 1)
  %t15 = inttoptr i64 1615808600 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  %t17 = getelementptr ptr, ptr %t0, i32 1
  %t18 = load ptr, ptr %t17
  call void @__inc_ref(ptr %t18)
  %t19 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t18, ptr %t19
  %t20 = getelementptr ptr, ptr %t11, i32 1
  store ptr %t14, ptr %t20
  br label %case.end.3.10
case.end.3.10:
  br label %case.join.8
case.arm.4.21:
  call void @__inc_ref(ptr %t0)
  br label %case.end.4.22
case.end.4.22:
  br label %case.join.8
case.default.7:
  unreachable
case.join.8:
  %t23 = phi ptr [ %t11, %case.end.3.10 ], [ %t0, %case.end.4.22 ]
  call void @__free_recursive(ptr %t0)
  %t24 = getelementptr ptr, ptr %t23, i32 0
  %t25 = load ptr, ptr %t24
  %t26 = ptrtoint ptr %t25 to i64
  switch i64 %t26, label %case.default.27 [ i64 3, label %case.arm.3.29 i64 4, label %case.arm.4.31 ]
case.arm.3.29:
  call void @__inc_ref(ptr %t23)
  br label %case.end.3.30
case.end.3.30:
  br label %case.join.28
case.arm.4.31:
  %t33 = call ptr @__alloc(i64 16, i32 1)
  %t34 = inttoptr i64 4 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = getelementptr ptr, ptr %t23, i32 1
  %t37 = load ptr, ptr %t36
  call void @__inc_ref(ptr %t37)
  %t38 = getelementptr ptr, ptr %t33, i32 1
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t33, i32 0
  %t40 = load ptr, ptr %t39
  %t41 = ptrtoint ptr %t40 to i64
  switch i64 %t41, label %case.default.42 [ i64 3, label %case.arm.3.44 i64 4, label %case.arm.4.56 ]
case.arm.3.44:
  %t46 = call ptr @__alloc(i64 16, i32 1)
  %t47 = inttoptr i64 3 to ptr
  %t48 = getelementptr ptr, ptr %t46, i32 0
  store ptr %t47, ptr %t48
  %t49 = call ptr @__alloc(i64 16, i32 1)
  %t50 = inttoptr i64 2252990199 to ptr
  %t51 = getelementptr ptr, ptr %t49, i32 0
  store ptr %t50, ptr %t51
  %t52 = getelementptr ptr, ptr %t33, i32 1
  %t53 = load ptr, ptr %t52
  call void @__inc_ref(ptr %t53)
  %t54 = getelementptr ptr, ptr %t49, i32 1
  store ptr %t53, ptr %t54
  %t55 = getelementptr ptr, ptr %t46, i32 1
  store ptr %t49, ptr %t55
  br label %case.end.3.45
case.end.3.45:
  br label %case.join.43
case.arm.4.56:
  call void @__inc_ref(ptr %t33)
  br label %case.end.4.57
case.end.4.57:
  br label %case.join.43
case.default.42:
  unreachable
case.join.43:
  %t58 = phi ptr [ %t46, %case.end.3.45 ], [ %t33, %case.end.4.57 ]
  call void @__free_recursive(ptr %t33)
  br label %case.end.4.32
case.end.4.32:
  br label %case.join.28
case.default.27:
  unreachable
case.join.28:
  %t59 = phi ptr [ %t23, %case.end.3.30 ], [ %t58, %case.end.4.32 ]
  call void @__free_recursive(ptr %t23)
  ret ptr %t59
}

define internal ptr @v_wE3() {
  %t0 = call ptr @v_seedT()
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
  %t12 = inttoptr i64 925038822 to ptr
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
  %t20 = call ptr @__alloc(i64 16, i32 1)
  %t21 = inttoptr i64 4 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = getelementptr ptr, ptr %t0, i32 1
  %t24 = load ptr, ptr %t23
  call void @__inc_ref(ptr %t24)
  %t25 = getelementptr ptr, ptr %t20, i32 1
  store ptr %t24, ptr %t25
  %t26 = getelementptr ptr, ptr %t20, i32 0
  %t27 = load ptr, ptr %t26
  %t28 = ptrtoint ptr %t27 to i64
  switch i64 %t28, label %case.default.29 [ i64 3, label %case.arm.3.31 i64 4, label %case.arm.4.43 ]
case.arm.3.31:
  %t33 = call ptr @__alloc(i64 16, i32 1)
  %t34 = inttoptr i64 3 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = call ptr @__alloc(i64 16, i32 1)
  %t37 = inttoptr i64 1615808600 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t20, i32 1
  %t40 = load ptr, ptr %t39
  call void @__inc_ref(ptr %t40)
  %t41 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t40, ptr %t41
  %t42 = getelementptr ptr, ptr %t33, i32 1
  store ptr %t36, ptr %t42
  br label %case.end.3.32
case.end.3.32:
  br label %case.join.30
case.arm.4.43:
  call void @__inc_ref(ptr %t20)
  br label %case.end.4.44
case.end.4.44:
  br label %case.join.30
case.default.29:
  unreachable
case.join.30:
  %t45 = phi ptr [ %t33, %case.end.3.32 ], [ %t20, %case.end.4.44 ]
  call void @__free_recursive(ptr %t20)
  br label %case.end.4.19
case.end.4.19:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t46 = phi ptr [ %t8, %case.end.3.7 ], [ %t45, %case.end.4.19 ]
  call void @__free_recursive(ptr %t0)
  %t47 = getelementptr ptr, ptr %t46, i32 0
  %t48 = load ptr, ptr %t47
  %t49 = ptrtoint ptr %t48 to i64
  switch i64 %t49, label %case.default.50 [ i64 3, label %case.arm.3.52 i64 4, label %case.arm.4.54 ]
case.arm.3.52:
  call void @__inc_ref(ptr %t46)
  br label %case.end.3.53
case.end.3.53:
  br label %case.join.51
case.arm.4.54:
  %t56 = call ptr @__alloc(i64 16, i32 1)
  %t57 = inttoptr i64 3 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  %t59 = call ptr @__alloc(i64 8, i32 0)
  %t60 = inttoptr i64 24 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  %t62 = getelementptr ptr, ptr %t56, i32 1
  store ptr %t59, ptr %t62
  %t63 = getelementptr ptr, ptr %t56, i32 0
  %t64 = load ptr, ptr %t63
  %t65 = ptrtoint ptr %t64 to i64
  switch i64 %t65, label %case.default.66 [ i64 3, label %case.arm.3.68 i64 4, label %case.arm.4.80 ]
case.arm.3.68:
  %t70 = call ptr @__alloc(i64 16, i32 1)
  %t71 = inttoptr i64 3 to ptr
  %t72 = getelementptr ptr, ptr %t70, i32 0
  store ptr %t71, ptr %t72
  %t73 = call ptr @__alloc(i64 16, i32 1)
  %t74 = inttoptr i64 2252990199 to ptr
  %t75 = getelementptr ptr, ptr %t73, i32 0
  store ptr %t74, ptr %t75
  %t76 = getelementptr ptr, ptr %t56, i32 1
  %t77 = load ptr, ptr %t76
  call void @__inc_ref(ptr %t77)
  %t78 = getelementptr ptr, ptr %t73, i32 1
  store ptr %t77, ptr %t78
  %t79 = getelementptr ptr, ptr %t70, i32 1
  store ptr %t73, ptr %t79
  br label %case.end.3.69
case.end.3.69:
  br label %case.join.67
case.arm.4.80:
  call void @__inc_ref(ptr %t56)
  br label %case.end.4.81
case.end.4.81:
  br label %case.join.67
case.default.66:
  unreachable
case.join.67:
  %t82 = phi ptr [ %t70, %case.end.3.69 ], [ %t56, %case.end.4.81 ]
  call void @__free_recursive(ptr %t56)
  br label %case.end.4.55
case.end.4.55:
  br label %case.join.51
case.default.50:
  unreachable
case.join.51:
  %t83 = phi ptr [ %t46, %case.end.3.53 ], [ %t82, %case.end.4.55 ]
  call void @__free_recursive(ptr %t46)
  ret ptr %t83
}

define internal ptr @v_wOk() {
  %t0 = call ptr @v_seedT()
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
  %t12 = inttoptr i64 925038822 to ptr
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
  %t20 = call ptr @__alloc(i64 16, i32 1)
  %t21 = inttoptr i64 4 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = getelementptr ptr, ptr %t0, i32 1
  %t24 = load ptr, ptr %t23
  call void @__inc_ref(ptr %t24)
  %t25 = getelementptr ptr, ptr %t20, i32 1
  store ptr %t24, ptr %t25
  %t26 = getelementptr ptr, ptr %t20, i32 0
  %t27 = load ptr, ptr %t26
  %t28 = ptrtoint ptr %t27 to i64
  switch i64 %t28, label %case.default.29 [ i64 3, label %case.arm.3.31 i64 4, label %case.arm.4.43 ]
case.arm.3.31:
  %t33 = call ptr @__alloc(i64 16, i32 1)
  %t34 = inttoptr i64 3 to ptr
  %t35 = getelementptr ptr, ptr %t33, i32 0
  store ptr %t34, ptr %t35
  %t36 = call ptr @__alloc(i64 16, i32 1)
  %t37 = inttoptr i64 1615808600 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t20, i32 1
  %t40 = load ptr, ptr %t39
  call void @__inc_ref(ptr %t40)
  %t41 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t40, ptr %t41
  %t42 = getelementptr ptr, ptr %t33, i32 1
  store ptr %t36, ptr %t42
  br label %case.end.3.32
case.end.3.32:
  br label %case.join.30
case.arm.4.43:
  call void @__inc_ref(ptr %t20)
  br label %case.end.4.44
case.end.4.44:
  br label %case.join.30
case.default.29:
  unreachable
case.join.30:
  %t45 = phi ptr [ %t33, %case.end.3.32 ], [ %t20, %case.end.4.44 ]
  call void @__free_recursive(ptr %t20)
  br label %case.end.4.19
case.end.4.19:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t46 = phi ptr [ %t8, %case.end.3.7 ], [ %t45, %case.end.4.19 ]
  call void @__free_recursive(ptr %t0)
  %t47 = getelementptr ptr, ptr %t46, i32 0
  %t48 = load ptr, ptr %t47
  %t49 = ptrtoint ptr %t48 to i64
  switch i64 %t49, label %case.default.50 [ i64 3, label %case.arm.3.52 i64 4, label %case.arm.4.54 ]
case.arm.3.52:
  call void @__inc_ref(ptr %t46)
  br label %case.end.3.53
case.end.3.53:
  br label %case.join.51
case.arm.4.54:
  %t56 = call ptr @__alloc(i64 16, i32 1)
  %t57 = inttoptr i64 4 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  %t59 = getelementptr ptr, ptr %t46, i32 1
  %t60 = load ptr, ptr %t59
  call void @__inc_ref(ptr %t60)
  %t61 = getelementptr ptr, ptr %t56, i32 1
  store ptr %t60, ptr %t61
  %t62 = getelementptr ptr, ptr %t56, i32 0
  %t63 = load ptr, ptr %t62
  %t64 = ptrtoint ptr %t63 to i64
  switch i64 %t64, label %case.default.65 [ i64 3, label %case.arm.3.67 i64 4, label %case.arm.4.79 ]
case.arm.3.67:
  %t69 = call ptr @__alloc(i64 16, i32 1)
  %t70 = inttoptr i64 3 to ptr
  %t71 = getelementptr ptr, ptr %t69, i32 0
  store ptr %t70, ptr %t71
  %t72 = call ptr @__alloc(i64 16, i32 1)
  %t73 = inttoptr i64 2252990199 to ptr
  %t74 = getelementptr ptr, ptr %t72, i32 0
  store ptr %t73, ptr %t74
  %t75 = getelementptr ptr, ptr %t56, i32 1
  %t76 = load ptr, ptr %t75
  call void @__inc_ref(ptr %t76)
  %t77 = getelementptr ptr, ptr %t72, i32 1
  store ptr %t76, ptr %t77
  %t78 = getelementptr ptr, ptr %t69, i32 1
  store ptr %t72, ptr %t78
  br label %case.end.3.68
case.end.3.68:
  br label %case.join.66
case.arm.4.79:
  call void @__inc_ref(ptr %t56)
  br label %case.end.4.80
case.end.4.80:
  br label %case.join.66
case.default.65:
  unreachable
case.join.66:
  %t81 = phi ptr [ %t69, %case.end.3.68 ], [ %t56, %case.end.4.80 ]
  call void @__free_recursive(ptr %t56)
  br label %case.end.4.55
case.end.4.55:
  br label %case.join.51
case.default.50:
  unreachable
case.join.51:
  %t82 = phi ptr [ %t46, %case.end.3.53 ], [ %t81, %case.end.4.55 ]
  call void @__free_recursive(ptr %t46)
  ret ptr %t82
}

define internal ptr @v_tagged(ptr %v_label, ptr %v_val) {
  call void @__inc_ref(ptr %v_label)
  %t0 = call ptr @__concat(ptr %v_label, ptr getelementptr inbounds (i8, ptr @.str.2, i64 12))
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
  %t30 = call ptr @__concat(ptr %t29, ptr getelementptr inbounds (i8, ptr @.str.3, i64 12))
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
  %v__inl297_scrut.jslot = alloca ptr
  %v__inl299_scrut.jslot = alloca ptr
  %v__inl301_scrut.jslot = alloca ptr
  %v__inl303_scrut.jslot = alloca ptr
  %v__inl305_scrut.jslot = alloca ptr
  %v__inl307_scrut.jslot = alloca ptr
  %v__inl309_scrut.jslot = alloca ptr
  %v__inl311_scrut.jslot = alloca ptr
  %v__inl313_scrut.jslot = alloca ptr
  %v__inl315_scrut.jslot = alloca ptr
  %v__inl317_scrut.jslot = alloca ptr
  %v__inl319_scrut.jslot = alloca ptr
  %v__inl321_scrut.jslot = alloca ptr
  %v__inl323_scrut.jslot = alloca ptr
  %v__inl325_scrut.jslot = alloca ptr
  %v__inl327_scrut.jslot = alloca ptr
  %v__inl329_scrut.jslot = alloca ptr
  %v__inl331_scrut.jslot = alloca ptr
  %v__inl333_scrut.jslot = alloca ptr
  %v__inl335_scrut.jslot = alloca ptr
  %v__inl337_scrut.jslot = alloca ptr
  %t0 = call ptr @v_nevOk()
  %t1 = getelementptr ptr, ptr %t0, i32 0
  %t2 = load ptr, ptr %t1
  %t3 = ptrtoint ptr %t2 to i64
  switch i64 %t3, label %case.default.4 [ i64 3, label %case.arm.3.6 i64 4, label %case.arm.4.8 ]
case.arm.3.6:
  br label %case.end.3.7
case.end.3.7:
  br label %case.join.5
case.arm.4.8:
  %t10 = getelementptr ptr, ptr %t0, i32 1
  %t11 = load ptr, ptr %t10
  call void @__inc_ref(ptr %t11)
  %t12 = call ptr @__showInt32(ptr %t11)
  br label %case.end.4.9
case.end.4.9:
  br label %case.join.5
case.default.4:
  unreachable
case.join.5:
  %t13 = phi ptr [ getelementptr inbounds (i8, ptr @.str.5, i64 12), %case.end.3.7 ], [ %t12, %case.end.4.9 ]
  call void @__free_recursive(ptr %t0)
  %t14 = call ptr @v_tagged(ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t13)
  %t15 = getelementptr ptr, ptr %t14, i32 0
  %t16 = load ptr, ptr %t15
  %t17 = ptrtoint ptr %t16 to i64
  switch i64 %t17, label %case.default.18 [ i64 3, label %case.arm.3.20 i64 4, label %case.arm.4.28 ]
case.arm.3.20:
  %t22 = getelementptr ptr, ptr %t14, i32 1
  %t23 = load ptr, ptr %t22
  call void @__inc_ref(ptr %t23)
  %t24 = call ptr @__alloc(i64 16, i32 1)
  %t25 = inttoptr i64 3 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  call void @__inc_ref(ptr %t23)
  %t27 = getelementptr ptr, ptr %t24, i32 1
  store ptr %t23, ptr %t27
  br label %case.end.3.21
case.end.3.21:
  br label %case.join.19
case.arm.4.28:
  %t30 = getelementptr ptr, ptr %t14, i32 1
  %t31 = load ptr, ptr %t30
  call void @__inc_ref(ptr %t31)
  %t34 = call ptr @v_nevFail()
  %t35 = getelementptr ptr, ptr %t34, i32 0
  %t36 = load ptr, ptr %t35
  %t37 = ptrtoint ptr %t36 to i64
  switch i64 %t37, label %case.default.38 [ i64 3, label %case.arm.3.40 i64 4, label %case.arm.4.42 ]
case.arm.3.40:
  br label %case.end.3.41
case.end.3.41:
  br label %case.join.39
case.arm.4.42:
  %t44 = getelementptr ptr, ptr %t34, i32 1
  %t45 = load ptr, ptr %t44
  call void @__inc_ref(ptr %t45)
  %t46 = call ptr @__showInt32(ptr %t45)
  br label %case.end.4.43
case.end.4.43:
  br label %case.join.39
case.default.38:
  unreachable
case.join.39:
  %t47 = phi ptr [ getelementptr inbounds (i8, ptr @.str.5, i64 12), %case.end.3.41 ], [ %t46, %case.end.4.43 ]
  call void @__free_recursive(ptr %t34)
  %t48 = call ptr @v_tagged(ptr getelementptr inbounds (i8, ptr @.str.30, i64 12), ptr %t47)
  %t49 = getelementptr ptr, ptr %t48, i32 0
  %t50 = load ptr, ptr %t49
  %t51 = ptrtoint ptr %t50 to i64
  switch i64 %t51, label %join.case.default.52 [ i64 3, label %join.case.arm.3.53 i64 4, label %join.case.arm.4.61 ]
join.case.arm.3.53:
  %t54 = getelementptr ptr, ptr %t48, i32 1
  %t55 = load ptr, ptr %t54
  call void @__inc_ref(ptr %t55)
  %t56 = call ptr @__alloc(i64 16, i32 1)
  %t57 = inttoptr i64 3 to ptr
  %t58 = getelementptr ptr, ptr %t56, i32 0
  store ptr %t57, ptr %t58
  call void @__inc_ref(ptr %t55)
  %t59 = getelementptr ptr, ptr %t56, i32 1
  store ptr %t55, ptr %t59
  call void @__free_recursive(ptr %t48)
  br label %join.val.60
join.val.60:
  br label %join.after.33
join.case.arm.4.61:
  %t62 = getelementptr ptr, ptr %t48, i32 1
  %t63 = load ptr, ptr %t62
  call void @__inc_ref(ptr %t63)
  call void @__inc_ref(ptr %t31)
  call void @__inc_ref(ptr %t63)
  %t64 = call ptr @__concat(ptr %t31, ptr %t63)
  call void @__free_recursive(ptr %t48)
  store ptr %t64, ptr %v__inl297_scrut.jslot
  br label %join.32
join.case.default.52:
  unreachable
join.32:
  %t65 = load ptr, ptr %v__inl297_scrut.jslot
  %t66 = getelementptr ptr, ptr %t65, i32 0
  %t67 = load ptr, ptr %t66
  %t68 = ptrtoint ptr %t67 to i64
  switch i64 %t68, label %case.default.69 [ i64 3, label %case.arm.3.71 i64 4, label %case.arm.4.73 ]
case.arm.3.71:
  call void @__inc_ref(ptr %t65)
  br label %case.end.3.72
case.end.3.72:
  br label %case.join.70
case.arm.4.73:
  %t77 = call ptr @v_nevRightOk()
  %t78 = getelementptr ptr, ptr %t77, i32 0
  %t79 = load ptr, ptr %t78
  %t80 = ptrtoint ptr %t79 to i64
  switch i64 %t80, label %case.default.81 [ i64 3, label %case.arm.3.83 i64 4, label %case.arm.4.85 ]
case.arm.3.83:
  br label %case.end.3.84
case.end.3.84:
  br label %case.join.82
case.arm.4.85:
  %t87 = getelementptr ptr, ptr %t77, i32 1
  %t88 = load ptr, ptr %t87
  call void @__inc_ref(ptr %t88)
  %t89 = call ptr @__showInt32(ptr %t88)
  br label %case.end.4.86
case.end.4.86:
  br label %case.join.82
case.default.81:
  unreachable
case.join.82:
  %t90 = phi ptr [ getelementptr inbounds (i8, ptr @.str.5, i64 12), %case.end.3.84 ], [ %t89, %case.end.4.86 ]
  call void @__free_recursive(ptr %t77)
  %t91 = call ptr @v_tagged(ptr getelementptr inbounds (i8, ptr @.str.29, i64 12), ptr %t90)
  %t92 = getelementptr ptr, ptr %t91, i32 0
  %t93 = load ptr, ptr %t92
  %t94 = ptrtoint ptr %t93 to i64
  switch i64 %t94, label %join.case.default.95 [ i64 3, label %join.case.arm.3.96 i64 4, label %join.case.arm.4.104 ]
join.case.arm.3.96:
  %t97 = getelementptr ptr, ptr %t91, i32 1
  %t98 = load ptr, ptr %t97
  call void @__inc_ref(ptr %t98)
  %t99 = call ptr @__alloc(i64 16, i32 1)
  %t100 = inttoptr i64 3 to ptr
  %t101 = getelementptr ptr, ptr %t99, i32 0
  store ptr %t100, ptr %t101
  call void @__inc_ref(ptr %t98)
  %t102 = getelementptr ptr, ptr %t99, i32 1
  store ptr %t98, ptr %t102
  call void @__free_recursive(ptr %t98)
  call void @__free_recursive(ptr %t91)
  br label %join.val.103
join.val.103:
  br label %join.after.76
join.case.arm.4.104:
  %t105 = getelementptr ptr, ptr %t91, i32 1
  %t106 = load ptr, ptr %t105
  call void @__inc_ref(ptr %t106)
  %t107 = getelementptr ptr, ptr %t65, i32 1
  %t108 = load ptr, ptr %t107
  call void @__inc_ref(ptr %t108)
  call void @__inc_ref(ptr %t106)
  %t109 = call ptr @__concat(ptr %t108, ptr %t106)
  call void @__free_recursive(ptr %t106)
  call void @__free_recursive(ptr %t91)
  store ptr %t109, ptr %v__inl299_scrut.jslot
  br label %join.75
join.case.default.95:
  unreachable
join.75:
  %t110 = load ptr, ptr %v__inl299_scrut.jslot
  %t111 = getelementptr ptr, ptr %t110, i32 0
  %t112 = load ptr, ptr %t111
  %t113 = ptrtoint ptr %t112 to i64
  switch i64 %t113, label %case.default.114 [ i64 3, label %case.arm.3.116 i64 4, label %case.arm.4.118 ]
case.arm.3.116:
  call void @__inc_ref(ptr %t110)
  br label %case.end.3.117
case.end.3.117:
  br label %case.join.115
case.arm.4.118:
  %t122 = call ptr @v_nevRightE1()
  %t123 = getelementptr ptr, ptr %t122, i32 0
  %t124 = load ptr, ptr %t123
  %t125 = ptrtoint ptr %t124 to i64
  switch i64 %t125, label %case.default.126 [ i64 3, label %case.arm.3.128 i64 4, label %case.arm.4.130 ]
case.arm.3.128:
  br label %case.end.3.129
case.end.3.129:
  br label %case.join.127
case.arm.4.130:
  %t132 = getelementptr ptr, ptr %t122, i32 1
  %t133 = load ptr, ptr %t132
  call void @__inc_ref(ptr %t133)
  %t134 = call ptr @__showInt32(ptr %t133)
  br label %case.end.4.131
case.end.4.131:
  br label %case.join.127
case.default.126:
  unreachable
case.join.127:
  %t135 = phi ptr [ getelementptr inbounds (i8, ptr @.str.5, i64 12), %case.end.3.129 ], [ %t134, %case.end.4.131 ]
  call void @__free_recursive(ptr %t122)
  %t136 = call ptr @v_tagged(ptr getelementptr inbounds (i8, ptr @.str.28, i64 12), ptr %t135)
  %t137 = getelementptr ptr, ptr %t136, i32 0
  %t138 = load ptr, ptr %t137
  %t139 = ptrtoint ptr %t138 to i64
  switch i64 %t139, label %join.case.default.140 [ i64 3, label %join.case.arm.3.141 i64 4, label %join.case.arm.4.149 ]
join.case.arm.3.141:
  %t142 = getelementptr ptr, ptr %t136, i32 1
  %t143 = load ptr, ptr %t142
  call void @__inc_ref(ptr %t143)
  %t144 = call ptr @__alloc(i64 16, i32 1)
  %t145 = inttoptr i64 3 to ptr
  %t146 = getelementptr ptr, ptr %t144, i32 0
  store ptr %t145, ptr %t146
  call void @__inc_ref(ptr %t143)
  %t147 = getelementptr ptr, ptr %t144, i32 1
  store ptr %t143, ptr %t147
  call void @__free_recursive(ptr %t143)
  call void @__free_recursive(ptr %t136)
  br label %join.val.148
join.val.148:
  br label %join.after.121
join.case.arm.4.149:
  %t150 = getelementptr ptr, ptr %t136, i32 1
  %t151 = load ptr, ptr %t150
  call void @__inc_ref(ptr %t151)
  %t152 = getelementptr ptr, ptr %t110, i32 1
  %t153 = load ptr, ptr %t152
  call void @__inc_ref(ptr %t153)
  call void @__inc_ref(ptr %t151)
  %t154 = call ptr @__concat(ptr %t153, ptr %t151)
  call void @__free_recursive(ptr %t151)
  call void @__free_recursive(ptr %t136)
  store ptr %t154, ptr %v__inl301_scrut.jslot
  br label %join.120
join.case.default.140:
  unreachable
join.120:
  %t155 = load ptr, ptr %v__inl301_scrut.jslot
  %t156 = getelementptr ptr, ptr %t155, i32 0
  %t157 = load ptr, ptr %t156
  %t158 = ptrtoint ptr %t157 to i64
  switch i64 %t158, label %case.default.159 [ i64 3, label %case.arm.3.161 i64 4, label %case.arm.4.163 ]
case.arm.3.161:
  call void @__inc_ref(ptr %t155)
  br label %case.end.3.162
case.end.3.162:
  br label %case.join.160
case.arm.4.163:
  %t167 = call ptr @v_pureNever()
  %t168 = getelementptr ptr, ptr %t167, i32 1
  %t169 = load ptr, ptr %t168
  call void @__inc_ref(ptr %t169)
  %t170 = call ptr @__showInt32(ptr %t169)
  call void @__free_recursive(ptr %t167)
  %t171 = call ptr @v_tagged(ptr getelementptr inbounds (i8, ptr @.str.27, i64 12), ptr %t170)
  %t172 = getelementptr ptr, ptr %t171, i32 0
  %t173 = load ptr, ptr %t172
  %t174 = ptrtoint ptr %t173 to i64
  switch i64 %t174, label %join.case.default.175 [ i64 3, label %join.case.arm.3.176 i64 4, label %join.case.arm.4.184 ]
join.case.arm.3.176:
  %t177 = getelementptr ptr, ptr %t171, i32 1
  %t178 = load ptr, ptr %t177
  call void @__inc_ref(ptr %t178)
  %t179 = call ptr @__alloc(i64 16, i32 1)
  %t180 = inttoptr i64 3 to ptr
  %t181 = getelementptr ptr, ptr %t179, i32 0
  store ptr %t180, ptr %t181
  call void @__inc_ref(ptr %t178)
  %t182 = getelementptr ptr, ptr %t179, i32 1
  store ptr %t178, ptr %t182
  call void @__free_recursive(ptr %t178)
  call void @__free_recursive(ptr %t171)
  br label %join.val.183
join.val.183:
  br label %join.after.166
join.case.arm.4.184:
  %t185 = getelementptr ptr, ptr %t171, i32 1
  %t186 = load ptr, ptr %t185
  call void @__inc_ref(ptr %t186)
  %t187 = getelementptr ptr, ptr %t155, i32 1
  %t188 = load ptr, ptr %t187
  call void @__inc_ref(ptr %t188)
  call void @__inc_ref(ptr %t186)
  %t189 = call ptr @__concat(ptr %t188, ptr %t186)
  call void @__free_recursive(ptr %t186)
  call void @__free_recursive(ptr %t171)
  store ptr %t189, ptr %v__inl303_scrut.jslot
  br label %join.165
join.case.default.175:
  unreachable
join.165:
  %t190 = load ptr, ptr %v__inl303_scrut.jslot
  %t191 = getelementptr ptr, ptr %t190, i32 0
  %t192 = load ptr, ptr %t191
  %t193 = ptrtoint ptr %t192 to i64
  switch i64 %t193, label %case.default.194 [ i64 3, label %case.arm.3.196 i64 4, label %case.arm.4.198 ]
case.arm.3.196:
  call void @__inc_ref(ptr %t190)
  br label %case.end.3.197
case.end.3.197:
  br label %case.join.195
case.arm.4.198:
  %t202 = call ptr @v_strOk()
  %t203 = getelementptr ptr, ptr %t202, i32 0
  %t204 = load ptr, ptr %t203
  %t205 = ptrtoint ptr %t204 to i64
  switch i64 %t205, label %case.default.206 [ i64 3, label %case.arm.3.208 i64 4, label %case.arm.4.224 ]
case.arm.3.208:
  %t210 = getelementptr ptr, ptr %t202, i32 1
  %t211 = load ptr, ptr %t210
  call void @__inc_ref(ptr %t211)
  %t212 = getelementptr ptr, ptr %t211, i32 0
  %t213 = load ptr, ptr %t212
  %t214 = ptrtoint ptr %t213 to i64
  switch i64 %t214, label %case.default.215 [ i64 1615808600, label %case.arm.1615808600.217 i64 2252990199, label %case.arm.2252990199.221 ]
case.arm.1615808600.217:
  %t219 = getelementptr ptr, ptr %t211, i32 1
  %t220 = load ptr, ptr %t219
  call void @__inc_ref(ptr %t220)
  br label %case.end.1615808600.218
case.end.1615808600.218:
  br label %case.join.216
case.arm.2252990199.221:
  br label %case.end.2252990199.222
case.end.2252990199.222:
  br label %case.join.216
case.default.215:
  unreachable
case.join.216:
  %t223 = phi ptr [ %t220, %case.end.1615808600.218 ], [ getelementptr inbounds (i8, ptr @.str.5, i64 12), %case.end.2252990199.222 ]
  call void @__free_recursive(ptr %t211)
  br label %case.end.3.209
case.end.3.209:
  br label %case.join.207
case.arm.4.224:
  %t226 = getelementptr ptr, ptr %t202, i32 1
  %t227 = load ptr, ptr %t226
  call void @__inc_ref(ptr %t227)
  %t228 = call ptr @__showInt32(ptr %t227)
  br label %case.end.4.225
case.end.4.225:
  br label %case.join.207
case.default.206:
  unreachable
case.join.207:
  %t229 = phi ptr [ %t223, %case.end.3.209 ], [ %t228, %case.end.4.225 ]
  call void @__free_recursive(ptr %t202)
  %t230 = call ptr @v_tagged(ptr getelementptr inbounds (i8, ptr @.str.26, i64 12), ptr %t229)
  %t231 = getelementptr ptr, ptr %t230, i32 0
  %t232 = load ptr, ptr %t231
  %t233 = ptrtoint ptr %t232 to i64
  switch i64 %t233, label %join.case.default.234 [ i64 3, label %join.case.arm.3.235 i64 4, label %join.case.arm.4.243 ]
join.case.arm.3.235:
  %t236 = getelementptr ptr, ptr %t230, i32 1
  %t237 = load ptr, ptr %t236
  call void @__inc_ref(ptr %t237)
  %t238 = call ptr @__alloc(i64 16, i32 1)
  %t239 = inttoptr i64 3 to ptr
  %t240 = getelementptr ptr, ptr %t238, i32 0
  store ptr %t239, ptr %t240
  call void @__inc_ref(ptr %t237)
  %t241 = getelementptr ptr, ptr %t238, i32 1
  store ptr %t237, ptr %t241
  call void @__free_recursive(ptr %t237)
  call void @__free_recursive(ptr %t230)
  br label %join.val.242
join.val.242:
  br label %join.after.201
join.case.arm.4.243:
  %t244 = getelementptr ptr, ptr %t230, i32 1
  %t245 = load ptr, ptr %t244
  call void @__inc_ref(ptr %t245)
  %t246 = getelementptr ptr, ptr %t190, i32 1
  %t247 = load ptr, ptr %t246
  call void @__inc_ref(ptr %t247)
  call void @__inc_ref(ptr %t245)
  %t248 = call ptr @__concat(ptr %t247, ptr %t245)
  call void @__free_recursive(ptr %t245)
  call void @__free_recursive(ptr %t230)
  store ptr %t248, ptr %v__inl305_scrut.jslot
  br label %join.200
join.case.default.234:
  unreachable
join.200:
  %t249 = load ptr, ptr %v__inl305_scrut.jslot
  %t250 = getelementptr ptr, ptr %t249, i32 0
  %t251 = load ptr, ptr %t250
  %t252 = ptrtoint ptr %t251 to i64
  switch i64 %t252, label %case.default.253 [ i64 3, label %case.arm.3.255 i64 4, label %case.arm.4.257 ]
case.arm.3.255:
  call void @__inc_ref(ptr %t249)
  br label %case.end.3.256
case.end.3.256:
  br label %case.join.254
case.arm.4.257:
  %t261 = call ptr @v_strE1()
  %t262 = getelementptr ptr, ptr %t261, i32 0
  %t263 = load ptr, ptr %t262
  %t264 = ptrtoint ptr %t263 to i64
  switch i64 %t264, label %case.default.265 [ i64 3, label %case.arm.3.267 i64 4, label %case.arm.4.283 ]
case.arm.3.267:
  %t269 = getelementptr ptr, ptr %t261, i32 1
  %t270 = load ptr, ptr %t269
  call void @__inc_ref(ptr %t270)
  %t271 = getelementptr ptr, ptr %t270, i32 0
  %t272 = load ptr, ptr %t271
  %t273 = ptrtoint ptr %t272 to i64
  switch i64 %t273, label %case.default.274 [ i64 1615808600, label %case.arm.1615808600.276 i64 2252990199, label %case.arm.2252990199.280 ]
case.arm.1615808600.276:
  %t278 = getelementptr ptr, ptr %t270, i32 1
  %t279 = load ptr, ptr %t278
  call void @__inc_ref(ptr %t279)
  br label %case.end.1615808600.277
case.end.1615808600.277:
  br label %case.join.275
case.arm.2252990199.280:
  br label %case.end.2252990199.281
case.end.2252990199.281:
  br label %case.join.275
case.default.274:
  unreachable
case.join.275:
  %t282 = phi ptr [ %t279, %case.end.1615808600.277 ], [ getelementptr inbounds (i8, ptr @.str.5, i64 12), %case.end.2252990199.281 ]
  call void @__free_recursive(ptr %t270)
  br label %case.end.3.268
case.end.3.268:
  br label %case.join.266
case.arm.4.283:
  %t285 = getelementptr ptr, ptr %t261, i32 1
  %t286 = load ptr, ptr %t285
  call void @__inc_ref(ptr %t286)
  %t287 = call ptr @__showInt32(ptr %t286)
  br label %case.end.4.284
case.end.4.284:
  br label %case.join.266
case.default.265:
  unreachable
case.join.266:
  %t288 = phi ptr [ %t282, %case.end.3.268 ], [ %t287, %case.end.4.284 ]
  call void @__free_recursive(ptr %t261)
  %t289 = call ptr @v_tagged(ptr getelementptr inbounds (i8, ptr @.str.25, i64 12), ptr %t288)
  %t290 = getelementptr ptr, ptr %t289, i32 0
  %t291 = load ptr, ptr %t290
  %t292 = ptrtoint ptr %t291 to i64
  switch i64 %t292, label %join.case.default.293 [ i64 3, label %join.case.arm.3.294 i64 4, label %join.case.arm.4.302 ]
join.case.arm.3.294:
  %t295 = getelementptr ptr, ptr %t289, i32 1
  %t296 = load ptr, ptr %t295
  call void @__inc_ref(ptr %t296)
  %t297 = call ptr @__alloc(i64 16, i32 1)
  %t298 = inttoptr i64 3 to ptr
  %t299 = getelementptr ptr, ptr %t297, i32 0
  store ptr %t298, ptr %t299
  call void @__inc_ref(ptr %t296)
  %t300 = getelementptr ptr, ptr %t297, i32 1
  store ptr %t296, ptr %t300
  call void @__free_recursive(ptr %t296)
  call void @__free_recursive(ptr %t289)
  br label %join.val.301
join.val.301:
  br label %join.after.260
join.case.arm.4.302:
  %t303 = getelementptr ptr, ptr %t289, i32 1
  %t304 = load ptr, ptr %t303
  call void @__inc_ref(ptr %t304)
  %t305 = getelementptr ptr, ptr %t249, i32 1
  %t306 = load ptr, ptr %t305
  call void @__inc_ref(ptr %t306)
  call void @__inc_ref(ptr %t304)
  %t307 = call ptr @__concat(ptr %t306, ptr %t304)
  call void @__free_recursive(ptr %t304)
  call void @__free_recursive(ptr %t289)
  store ptr %t307, ptr %v__inl307_scrut.jslot
  br label %join.259
join.case.default.293:
  unreachable
join.259:
  %t308 = load ptr, ptr %v__inl307_scrut.jslot
  %t309 = getelementptr ptr, ptr %t308, i32 0
  %t310 = load ptr, ptr %t309
  %t311 = ptrtoint ptr %t310 to i64
  switch i64 %t311, label %case.default.312 [ i64 3, label %case.arm.3.314 i64 4, label %case.arm.4.316 ]
case.arm.3.314:
  call void @__inc_ref(ptr %t308)
  br label %case.end.3.315
case.end.3.315:
  br label %case.join.313
case.arm.4.316:
  %t320 = call ptr @v_strE2()
  %t321 = getelementptr ptr, ptr %t320, i32 0
  %t322 = load ptr, ptr %t321
  %t323 = ptrtoint ptr %t322 to i64
  switch i64 %t323, label %case.default.324 [ i64 3, label %case.arm.3.326 i64 4, label %case.arm.4.342 ]
case.arm.3.326:
  %t328 = getelementptr ptr, ptr %t320, i32 1
  %t329 = load ptr, ptr %t328
  call void @__inc_ref(ptr %t329)
  %t330 = getelementptr ptr, ptr %t329, i32 0
  %t331 = load ptr, ptr %t330
  %t332 = ptrtoint ptr %t331 to i64
  switch i64 %t332, label %case.default.333 [ i64 1615808600, label %case.arm.1615808600.335 i64 2252990199, label %case.arm.2252990199.339 ]
case.arm.1615808600.335:
  %t337 = getelementptr ptr, ptr %t329, i32 1
  %t338 = load ptr, ptr %t337
  call void @__inc_ref(ptr %t338)
  br label %case.end.1615808600.336
case.end.1615808600.336:
  br label %case.join.334
case.arm.2252990199.339:
  br label %case.end.2252990199.340
case.end.2252990199.340:
  br label %case.join.334
case.default.333:
  unreachable
case.join.334:
  %t341 = phi ptr [ %t338, %case.end.1615808600.336 ], [ getelementptr inbounds (i8, ptr @.str.5, i64 12), %case.end.2252990199.340 ]
  call void @__free_recursive(ptr %t329)
  br label %case.end.3.327
case.end.3.327:
  br label %case.join.325
case.arm.4.342:
  %t344 = getelementptr ptr, ptr %t320, i32 1
  %t345 = load ptr, ptr %t344
  call void @__inc_ref(ptr %t345)
  %t346 = call ptr @__showInt32(ptr %t345)
  br label %case.end.4.343
case.end.4.343:
  br label %case.join.325
case.default.324:
  unreachable
case.join.325:
  %t347 = phi ptr [ %t341, %case.end.3.327 ], [ %t346, %case.end.4.343 ]
  call void @__free_recursive(ptr %t320)
  %t348 = call ptr @v_tagged(ptr getelementptr inbounds (i8, ptr @.str.24, i64 12), ptr %t347)
  %t349 = getelementptr ptr, ptr %t348, i32 0
  %t350 = load ptr, ptr %t349
  %t351 = ptrtoint ptr %t350 to i64
  switch i64 %t351, label %join.case.default.352 [ i64 3, label %join.case.arm.3.353 i64 4, label %join.case.arm.4.361 ]
join.case.arm.3.353:
  %t354 = getelementptr ptr, ptr %t348, i32 1
  %t355 = load ptr, ptr %t354
  call void @__inc_ref(ptr %t355)
  %t356 = call ptr @__alloc(i64 16, i32 1)
  %t357 = inttoptr i64 3 to ptr
  %t358 = getelementptr ptr, ptr %t356, i32 0
  store ptr %t357, ptr %t358
  call void @__inc_ref(ptr %t355)
  %t359 = getelementptr ptr, ptr %t356, i32 1
  store ptr %t355, ptr %t359
  call void @__free_recursive(ptr %t355)
  call void @__free_recursive(ptr %t348)
  br label %join.val.360
join.val.360:
  br label %join.after.319
join.case.arm.4.361:
  %t362 = getelementptr ptr, ptr %t348, i32 1
  %t363 = load ptr, ptr %t362
  call void @__inc_ref(ptr %t363)
  %t364 = getelementptr ptr, ptr %t308, i32 1
  %t365 = load ptr, ptr %t364
  call void @__inc_ref(ptr %t365)
  call void @__inc_ref(ptr %t363)
  %t366 = call ptr @__concat(ptr %t365, ptr %t363)
  call void @__free_recursive(ptr %t363)
  call void @__free_recursive(ptr %t348)
  store ptr %t366, ptr %v__inl309_scrut.jslot
  br label %join.318
join.case.default.352:
  unreachable
join.318:
  %t367 = load ptr, ptr %v__inl309_scrut.jslot
  %t368 = getelementptr ptr, ptr %t367, i32 0
  %t369 = load ptr, ptr %t368
  %t370 = ptrtoint ptr %t369 to i64
  switch i64 %t370, label %case.default.371 [ i64 3, label %case.arm.3.373 i64 4, label %case.arm.4.375 ]
case.arm.3.373:
  call void @__inc_ref(ptr %t367)
  br label %case.end.3.374
case.end.3.374:
  br label %case.join.372
case.arm.4.375:
  %t379 = call ptr @v_strIdem()
  %t380 = getelementptr ptr, ptr %t379, i32 0
  %t381 = load ptr, ptr %t380
  %t382 = ptrtoint ptr %t381 to i64
  switch i64 %t382, label %case.default.383 [ i64 3, label %case.arm.3.385 i64 4, label %case.arm.4.389 ]
case.arm.3.385:
  %t387 = getelementptr ptr, ptr %t379, i32 1
  %t388 = load ptr, ptr %t387
  call void @__inc_ref(ptr %t388)
  br label %case.end.3.386
case.end.3.386:
  br label %case.join.384
case.arm.4.389:
  %t391 = getelementptr ptr, ptr %t379, i32 1
  %t392 = load ptr, ptr %t391
  call void @__inc_ref(ptr %t392)
  %t393 = call ptr @__showInt32(ptr %t392)
  br label %case.end.4.390
case.end.4.390:
  br label %case.join.384
case.default.383:
  unreachable
case.join.384:
  %t394 = phi ptr [ %t388, %case.end.3.386 ], [ %t393, %case.end.4.390 ]
  call void @__free_recursive(ptr %t379)
  %t395 = call ptr @v_tagged(ptr getelementptr inbounds (i8, ptr @.str.23, i64 12), ptr %t394)
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
  br label %join.after.378
join.case.arm.4.408:
  %t409 = getelementptr ptr, ptr %t395, i32 1
  %t410 = load ptr, ptr %t409
  call void @__inc_ref(ptr %t410)
  %t411 = getelementptr ptr, ptr %t367, i32 1
  %t412 = load ptr, ptr %t411
  call void @__inc_ref(ptr %t412)
  call void @__inc_ref(ptr %t410)
  %t413 = call ptr @__concat(ptr %t412, ptr %t410)
  call void @__free_recursive(ptr %t410)
  call void @__free_recursive(ptr %t395)
  store ptr %t413, ptr %v__inl311_scrut.jslot
  br label %join.377
join.case.default.399:
  unreachable
join.377:
  %t414 = load ptr, ptr %v__inl311_scrut.jslot
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
  %t426 = call ptr @v_abE1()
  %t427 = getelementptr ptr, ptr %t426, i32 0
  %t428 = load ptr, ptr %t427
  %t429 = ptrtoint ptr %t428 to i64
  switch i64 %t429, label %case.default.430 [ i64 3, label %case.arm.3.432 i64 4, label %case.arm.4.446 ]
case.arm.3.432:
  %t434 = getelementptr ptr, ptr %t426, i32 1
  %t435 = load ptr, ptr %t434
  call void @__inc_ref(ptr %t435)
  %t436 = getelementptr ptr, ptr %t435, i32 0
  %t437 = load ptr, ptr %t436
  %t438 = ptrtoint ptr %t437 to i64
  switch i64 %t438, label %case.default.439 [ i64 2252990199, label %case.arm.2252990199.441 i64 2269767818, label %case.arm.2269767818.443 ]
case.arm.2252990199.441:
  br label %case.end.2252990199.442
case.end.2252990199.442:
  br label %case.join.440
case.arm.2269767818.443:
  br label %case.end.2269767818.444
case.end.2269767818.444:
  br label %case.join.440
case.default.439:
  unreachable
case.join.440:
  %t445 = phi ptr [ getelementptr inbounds (i8, ptr @.str.5, i64 12), %case.end.2252990199.442 ], [ getelementptr inbounds (i8, ptr @.str.21, i64 12), %case.end.2269767818.444 ]
  call void @__free_recursive(ptr %t435)
  br label %case.end.3.433
case.end.3.433:
  br label %case.join.431
case.arm.4.446:
  %t448 = getelementptr ptr, ptr %t426, i32 1
  %t449 = load ptr, ptr %t448
  call void @__inc_ref(ptr %t449)
  %t450 = call ptr @__showInt32(ptr %t449)
  br label %case.end.4.447
case.end.4.447:
  br label %case.join.431
case.default.430:
  unreachable
case.join.431:
  %t451 = phi ptr [ %t445, %case.end.3.433 ], [ %t450, %case.end.4.447 ]
  call void @__free_recursive(ptr %t426)
  %t452 = call ptr @v_tagged(ptr getelementptr inbounds (i8, ptr @.str.22, i64 12), ptr %t451)
  %t453 = getelementptr ptr, ptr %t452, i32 0
  %t454 = load ptr, ptr %t453
  %t455 = ptrtoint ptr %t454 to i64
  switch i64 %t455, label %join.case.default.456 [ i64 3, label %join.case.arm.3.457 i64 4, label %join.case.arm.4.465 ]
join.case.arm.3.457:
  %t458 = getelementptr ptr, ptr %t452, i32 1
  %t459 = load ptr, ptr %t458
  call void @__inc_ref(ptr %t459)
  %t460 = call ptr @__alloc(i64 16, i32 1)
  %t461 = inttoptr i64 3 to ptr
  %t462 = getelementptr ptr, ptr %t460, i32 0
  store ptr %t461, ptr %t462
  call void @__inc_ref(ptr %t459)
  %t463 = getelementptr ptr, ptr %t460, i32 1
  store ptr %t459, ptr %t463
  call void @__free_recursive(ptr %t459)
  call void @__free_recursive(ptr %t452)
  br label %join.val.464
join.val.464:
  br label %join.after.425
join.case.arm.4.465:
  %t466 = getelementptr ptr, ptr %t452, i32 1
  %t467 = load ptr, ptr %t466
  call void @__inc_ref(ptr %t467)
  %t468 = getelementptr ptr, ptr %t414, i32 1
  %t469 = load ptr, ptr %t468
  call void @__inc_ref(ptr %t469)
  call void @__inc_ref(ptr %t467)
  %t470 = call ptr @__concat(ptr %t469, ptr %t467)
  call void @__free_recursive(ptr %t467)
  call void @__free_recursive(ptr %t452)
  store ptr %t470, ptr %v__inl313_scrut.jslot
  br label %join.424
join.case.default.456:
  unreachable
join.424:
  %t471 = load ptr, ptr %v__inl313_scrut.jslot
  %t472 = getelementptr ptr, ptr %t471, i32 0
  %t473 = load ptr, ptr %t472
  %t474 = ptrtoint ptr %t473 to i64
  switch i64 %t474, label %case.default.475 [ i64 3, label %case.arm.3.477 i64 4, label %case.arm.4.479 ]
case.arm.3.477:
  call void @__inc_ref(ptr %t471)
  br label %case.end.3.478
case.end.3.478:
  br label %case.join.476
case.arm.4.479:
  %t483 = call ptr @v_abE2()
  %t484 = getelementptr ptr, ptr %t483, i32 0
  %t485 = load ptr, ptr %t484
  %t486 = ptrtoint ptr %t485 to i64
  switch i64 %t486, label %case.default.487 [ i64 3, label %case.arm.3.489 i64 4, label %case.arm.4.503 ]
case.arm.3.489:
  %t491 = getelementptr ptr, ptr %t483, i32 1
  %t492 = load ptr, ptr %t491
  call void @__inc_ref(ptr %t492)
  %t493 = getelementptr ptr, ptr %t492, i32 0
  %t494 = load ptr, ptr %t493
  %t495 = ptrtoint ptr %t494 to i64
  switch i64 %t495, label %case.default.496 [ i64 2252990199, label %case.arm.2252990199.498 i64 2269767818, label %case.arm.2269767818.500 ]
case.arm.2252990199.498:
  br label %case.end.2252990199.499
case.end.2252990199.499:
  br label %case.join.497
case.arm.2269767818.500:
  br label %case.end.2269767818.501
case.end.2269767818.501:
  br label %case.join.497
case.default.496:
  unreachable
case.join.497:
  %t502 = phi ptr [ getelementptr inbounds (i8, ptr @.str.5, i64 12), %case.end.2252990199.499 ], [ getelementptr inbounds (i8, ptr @.str.21, i64 12), %case.end.2269767818.501 ]
  call void @__free_recursive(ptr %t492)
  br label %case.end.3.490
case.end.3.490:
  br label %case.join.488
case.arm.4.503:
  %t505 = getelementptr ptr, ptr %t483, i32 1
  %t506 = load ptr, ptr %t505
  call void @__inc_ref(ptr %t506)
  %t507 = call ptr @__showInt32(ptr %t506)
  br label %case.end.4.504
case.end.4.504:
  br label %case.join.488
case.default.487:
  unreachable
case.join.488:
  %t508 = phi ptr [ %t502, %case.end.3.490 ], [ %t507, %case.end.4.504 ]
  call void @__free_recursive(ptr %t483)
  %t509 = call ptr @v_tagged(ptr getelementptr inbounds (i8, ptr @.str.20, i64 12), ptr %t508)
  %t510 = getelementptr ptr, ptr %t509, i32 0
  %t511 = load ptr, ptr %t510
  %t512 = ptrtoint ptr %t511 to i64
  switch i64 %t512, label %join.case.default.513 [ i64 3, label %join.case.arm.3.514 i64 4, label %join.case.arm.4.522 ]
join.case.arm.3.514:
  %t515 = getelementptr ptr, ptr %t509, i32 1
  %t516 = load ptr, ptr %t515
  call void @__inc_ref(ptr %t516)
  %t517 = call ptr @__alloc(i64 16, i32 1)
  %t518 = inttoptr i64 3 to ptr
  %t519 = getelementptr ptr, ptr %t517, i32 0
  store ptr %t518, ptr %t519
  call void @__inc_ref(ptr %t516)
  %t520 = getelementptr ptr, ptr %t517, i32 1
  store ptr %t516, ptr %t520
  call void @__free_recursive(ptr %t516)
  call void @__free_recursive(ptr %t509)
  br label %join.val.521
join.val.521:
  br label %join.after.482
join.case.arm.4.522:
  %t523 = getelementptr ptr, ptr %t509, i32 1
  %t524 = load ptr, ptr %t523
  call void @__inc_ref(ptr %t524)
  %t525 = getelementptr ptr, ptr %t471, i32 1
  %t526 = load ptr, ptr %t525
  call void @__inc_ref(ptr %t526)
  call void @__inc_ref(ptr %t524)
  %t527 = call ptr @__concat(ptr %t526, ptr %t524)
  call void @__free_recursive(ptr %t524)
  call void @__free_recursive(ptr %t509)
  store ptr %t527, ptr %v__inl315_scrut.jslot
  br label %join.481
join.case.default.513:
  unreachable
join.481:
  %t528 = load ptr, ptr %v__inl315_scrut.jslot
  %t529 = getelementptr ptr, ptr %t528, i32 0
  %t530 = load ptr, ptr %t529
  %t531 = ptrtoint ptr %t530 to i64
  switch i64 %t531, label %case.default.532 [ i64 3, label %case.arm.3.534 i64 4, label %case.arm.4.536 ]
case.arm.3.534:
  call void @__inc_ref(ptr %t528)
  br label %case.end.3.535
case.end.3.535:
  br label %case.join.533
case.arm.4.536:
  %t540 = call ptr @v_twoFirst()
  %t541 = getelementptr ptr, ptr %t540, i32 0
  %t542 = load ptr, ptr %t541
  %t543 = ptrtoint ptr %t542 to i64
  switch i64 %t543, label %case.default.544 [ i64 3, label %case.arm.3.546 i64 4, label %case.arm.4.572 ]
case.arm.3.546:
  %t548 = getelementptr ptr, ptr %t540, i32 1
  %t549 = load ptr, ptr %t548
  call void @__inc_ref(ptr %t549)
  %t550 = getelementptr ptr, ptr %t549, i32 0
  %t551 = load ptr, ptr %t550
  %t552 = ptrtoint ptr %t551 to i64
  switch i64 %t552, label %case.default.553 [ i64 925038822, label %case.arm.925038822.555 i64 2252990199, label %case.arm.2252990199.569 ]
case.arm.925038822.555:
  %t557 = getelementptr ptr, ptr %t549, i32 1
  %t558 = load ptr, ptr %t557
  call void @__inc_ref(ptr %t558)
  %t559 = getelementptr ptr, ptr %t558, i32 0
  %t560 = load ptr, ptr %t559
  %t561 = ptrtoint ptr %t560 to i64
  switch i64 %t561, label %case.default.562 [ i64 26, label %case.arm.26.564 i64 27, label %case.arm.27.566 ]
case.arm.26.564:
  br label %case.end.26.565
case.end.26.565:
  br label %case.join.563
case.arm.27.566:
  br label %case.end.27.567
case.end.27.567:
  br label %case.join.563
case.default.562:
  unreachable
case.join.563:
  %t568 = phi ptr [ getelementptr inbounds (i8, ptr @.str.7, i64 12), %case.end.26.565 ], [ getelementptr inbounds (i8, ptr @.str.8, i64 12), %case.end.27.567 ]
  call void @__free_recursive(ptr %t558)
  br label %case.end.925038822.556
case.end.925038822.556:
  br label %case.join.554
case.arm.2252990199.569:
  br label %case.end.2252990199.570
case.end.2252990199.570:
  br label %case.join.554
case.default.553:
  unreachable
case.join.554:
  %t571 = phi ptr [ %t568, %case.end.925038822.556 ], [ getelementptr inbounds (i8, ptr @.str.5, i64 12), %case.end.2252990199.570 ]
  call void @__free_recursive(ptr %t549)
  br label %case.end.3.547
case.end.3.547:
  br label %case.join.545
case.arm.4.572:
  %t574 = getelementptr ptr, ptr %t540, i32 1
  %t575 = load ptr, ptr %t574
  call void @__inc_ref(ptr %t575)
  %t576 = call ptr @__showInt32(ptr %t575)
  br label %case.end.4.573
case.end.4.573:
  br label %case.join.545
case.default.544:
  unreachable
case.join.545:
  %t577 = phi ptr [ %t571, %case.end.3.547 ], [ %t576, %case.end.4.573 ]
  call void @__free_recursive(ptr %t540)
  %t578 = call ptr @v_tagged(ptr getelementptr inbounds (i8, ptr @.str.19, i64 12), ptr %t577)
  %t579 = getelementptr ptr, ptr %t578, i32 0
  %t580 = load ptr, ptr %t579
  %t581 = ptrtoint ptr %t580 to i64
  switch i64 %t581, label %join.case.default.582 [ i64 3, label %join.case.arm.3.583 i64 4, label %join.case.arm.4.591 ]
join.case.arm.3.583:
  %t584 = getelementptr ptr, ptr %t578, i32 1
  %t585 = load ptr, ptr %t584
  call void @__inc_ref(ptr %t585)
  %t586 = call ptr @__alloc(i64 16, i32 1)
  %t587 = inttoptr i64 3 to ptr
  %t588 = getelementptr ptr, ptr %t586, i32 0
  store ptr %t587, ptr %t588
  call void @__inc_ref(ptr %t585)
  %t589 = getelementptr ptr, ptr %t586, i32 1
  store ptr %t585, ptr %t589
  call void @__free_recursive(ptr %t585)
  call void @__free_recursive(ptr %t578)
  br label %join.val.590
join.val.590:
  br label %join.after.539
join.case.arm.4.591:
  %t592 = getelementptr ptr, ptr %t578, i32 1
  %t593 = load ptr, ptr %t592
  call void @__inc_ref(ptr %t593)
  %t594 = getelementptr ptr, ptr %t528, i32 1
  %t595 = load ptr, ptr %t594
  call void @__inc_ref(ptr %t595)
  call void @__inc_ref(ptr %t593)
  %t596 = call ptr @__concat(ptr %t595, ptr %t593)
  call void @__free_recursive(ptr %t593)
  call void @__free_recursive(ptr %t578)
  store ptr %t596, ptr %v__inl317_scrut.jslot
  br label %join.538
join.case.default.582:
  unreachable
join.538:
  %t597 = load ptr, ptr %v__inl317_scrut.jslot
  %t598 = getelementptr ptr, ptr %t597, i32 0
  %t599 = load ptr, ptr %t598
  %t600 = ptrtoint ptr %t599 to i64
  switch i64 %t600, label %case.default.601 [ i64 3, label %case.arm.3.603 i64 4, label %case.arm.4.605 ]
case.arm.3.603:
  call void @__inc_ref(ptr %t597)
  br label %case.end.3.604
case.end.3.604:
  br label %case.join.602
case.arm.4.605:
  %t609 = call ptr @v_twoSecond()
  %t610 = getelementptr ptr, ptr %t609, i32 0
  %t611 = load ptr, ptr %t610
  %t612 = ptrtoint ptr %t611 to i64
  switch i64 %t612, label %case.default.613 [ i64 3, label %case.arm.3.615 i64 4, label %case.arm.4.641 ]
case.arm.3.615:
  %t617 = getelementptr ptr, ptr %t609, i32 1
  %t618 = load ptr, ptr %t617
  call void @__inc_ref(ptr %t618)
  %t619 = getelementptr ptr, ptr %t618, i32 0
  %t620 = load ptr, ptr %t619
  %t621 = ptrtoint ptr %t620 to i64
  switch i64 %t621, label %case.default.622 [ i64 925038822, label %case.arm.925038822.624 i64 2252990199, label %case.arm.2252990199.638 ]
case.arm.925038822.624:
  %t626 = getelementptr ptr, ptr %t618, i32 1
  %t627 = load ptr, ptr %t626
  call void @__inc_ref(ptr %t627)
  %t628 = getelementptr ptr, ptr %t627, i32 0
  %t629 = load ptr, ptr %t628
  %t630 = ptrtoint ptr %t629 to i64
  switch i64 %t630, label %case.default.631 [ i64 26, label %case.arm.26.633 i64 27, label %case.arm.27.635 ]
case.arm.26.633:
  br label %case.end.26.634
case.end.26.634:
  br label %case.join.632
case.arm.27.635:
  br label %case.end.27.636
case.end.27.636:
  br label %case.join.632
case.default.631:
  unreachable
case.join.632:
  %t637 = phi ptr [ getelementptr inbounds (i8, ptr @.str.7, i64 12), %case.end.26.634 ], [ getelementptr inbounds (i8, ptr @.str.8, i64 12), %case.end.27.636 ]
  call void @__free_recursive(ptr %t627)
  br label %case.end.925038822.625
case.end.925038822.625:
  br label %case.join.623
case.arm.2252990199.638:
  br label %case.end.2252990199.639
case.end.2252990199.639:
  br label %case.join.623
case.default.622:
  unreachable
case.join.623:
  %t640 = phi ptr [ %t637, %case.end.925038822.625 ], [ getelementptr inbounds (i8, ptr @.str.5, i64 12), %case.end.2252990199.639 ]
  call void @__free_recursive(ptr %t618)
  br label %case.end.3.616
case.end.3.616:
  br label %case.join.614
case.arm.4.641:
  %t643 = getelementptr ptr, ptr %t609, i32 1
  %t644 = load ptr, ptr %t643
  call void @__inc_ref(ptr %t644)
  %t645 = call ptr @__showInt32(ptr %t644)
  br label %case.end.4.642
case.end.4.642:
  br label %case.join.614
case.default.613:
  unreachable
case.join.614:
  %t646 = phi ptr [ %t640, %case.end.3.616 ], [ %t645, %case.end.4.642 ]
  call void @__free_recursive(ptr %t609)
  %t647 = call ptr @v_tagged(ptr getelementptr inbounds (i8, ptr @.str.18, i64 12), ptr %t646)
  %t648 = getelementptr ptr, ptr %t647, i32 0
  %t649 = load ptr, ptr %t648
  %t650 = ptrtoint ptr %t649 to i64
  switch i64 %t650, label %join.case.default.651 [ i64 3, label %join.case.arm.3.652 i64 4, label %join.case.arm.4.660 ]
join.case.arm.3.652:
  %t653 = getelementptr ptr, ptr %t647, i32 1
  %t654 = load ptr, ptr %t653
  call void @__inc_ref(ptr %t654)
  %t655 = call ptr @__alloc(i64 16, i32 1)
  %t656 = inttoptr i64 3 to ptr
  %t657 = getelementptr ptr, ptr %t655, i32 0
  store ptr %t656, ptr %t657
  call void @__inc_ref(ptr %t654)
  %t658 = getelementptr ptr, ptr %t655, i32 1
  store ptr %t654, ptr %t658
  call void @__free_recursive(ptr %t654)
  call void @__free_recursive(ptr %t647)
  br label %join.val.659
join.val.659:
  br label %join.after.608
join.case.arm.4.660:
  %t661 = getelementptr ptr, ptr %t647, i32 1
  %t662 = load ptr, ptr %t661
  call void @__inc_ref(ptr %t662)
  %t663 = getelementptr ptr, ptr %t597, i32 1
  %t664 = load ptr, ptr %t663
  call void @__inc_ref(ptr %t664)
  call void @__inc_ref(ptr %t662)
  %t665 = call ptr @__concat(ptr %t664, ptr %t662)
  call void @__free_recursive(ptr %t662)
  call void @__free_recursive(ptr %t647)
  store ptr %t665, ptr %v__inl319_scrut.jslot
  br label %join.607
join.case.default.651:
  unreachable
join.607:
  %t666 = load ptr, ptr %v__inl319_scrut.jslot
  %t667 = getelementptr ptr, ptr %t666, i32 0
  %t668 = load ptr, ptr %t667
  %t669 = ptrtoint ptr %t668 to i64
  switch i64 %t669, label %case.default.670 [ i64 3, label %case.arm.3.672 i64 4, label %case.arm.4.674 ]
case.arm.3.672:
  call void @__inc_ref(ptr %t666)
  br label %case.end.3.673
case.end.3.673:
  br label %case.join.671
case.arm.4.674:
  %t678 = call ptr @v_twoE2()
  %t679 = getelementptr ptr, ptr %t678, i32 0
  %t680 = load ptr, ptr %t679
  %t681 = ptrtoint ptr %t680 to i64
  switch i64 %t681, label %case.default.682 [ i64 3, label %case.arm.3.684 i64 4, label %case.arm.4.710 ]
case.arm.3.684:
  %t686 = getelementptr ptr, ptr %t678, i32 1
  %t687 = load ptr, ptr %t686
  call void @__inc_ref(ptr %t687)
  %t688 = getelementptr ptr, ptr %t687, i32 0
  %t689 = load ptr, ptr %t688
  %t690 = ptrtoint ptr %t689 to i64
  switch i64 %t690, label %case.default.691 [ i64 925038822, label %case.arm.925038822.693 i64 2252990199, label %case.arm.2252990199.707 ]
case.arm.925038822.693:
  %t695 = getelementptr ptr, ptr %t687, i32 1
  %t696 = load ptr, ptr %t695
  call void @__inc_ref(ptr %t696)
  %t697 = getelementptr ptr, ptr %t696, i32 0
  %t698 = load ptr, ptr %t697
  %t699 = ptrtoint ptr %t698 to i64
  switch i64 %t699, label %case.default.700 [ i64 26, label %case.arm.26.702 i64 27, label %case.arm.27.704 ]
case.arm.26.702:
  br label %case.end.26.703
case.end.26.703:
  br label %case.join.701
case.arm.27.704:
  br label %case.end.27.705
case.end.27.705:
  br label %case.join.701
case.default.700:
  unreachable
case.join.701:
  %t706 = phi ptr [ getelementptr inbounds (i8, ptr @.str.7, i64 12), %case.end.26.703 ], [ getelementptr inbounds (i8, ptr @.str.8, i64 12), %case.end.27.705 ]
  call void @__free_recursive(ptr %t696)
  br label %case.end.925038822.694
case.end.925038822.694:
  br label %case.join.692
case.arm.2252990199.707:
  br label %case.end.2252990199.708
case.end.2252990199.708:
  br label %case.join.692
case.default.691:
  unreachable
case.join.692:
  %t709 = phi ptr [ %t706, %case.end.925038822.694 ], [ getelementptr inbounds (i8, ptr @.str.5, i64 12), %case.end.2252990199.708 ]
  call void @__free_recursive(ptr %t687)
  br label %case.end.3.685
case.end.3.685:
  br label %case.join.683
case.arm.4.710:
  %t712 = getelementptr ptr, ptr %t678, i32 1
  %t713 = load ptr, ptr %t712
  call void @__inc_ref(ptr %t713)
  %t714 = call ptr @__showInt32(ptr %t713)
  br label %case.end.4.711
case.end.4.711:
  br label %case.join.683
case.default.682:
  unreachable
case.join.683:
  %t715 = phi ptr [ %t709, %case.end.3.685 ], [ %t714, %case.end.4.711 ]
  call void @__free_recursive(ptr %t678)
  %t716 = call ptr @v_tagged(ptr getelementptr inbounds (i8, ptr @.str.17, i64 12), ptr %t715)
  %t717 = getelementptr ptr, ptr %t716, i32 0
  %t718 = load ptr, ptr %t717
  %t719 = ptrtoint ptr %t718 to i64
  switch i64 %t719, label %join.case.default.720 [ i64 3, label %join.case.arm.3.721 i64 4, label %join.case.arm.4.729 ]
join.case.arm.3.721:
  %t722 = getelementptr ptr, ptr %t716, i32 1
  %t723 = load ptr, ptr %t722
  call void @__inc_ref(ptr %t723)
  %t724 = call ptr @__alloc(i64 16, i32 1)
  %t725 = inttoptr i64 3 to ptr
  %t726 = getelementptr ptr, ptr %t724, i32 0
  store ptr %t725, ptr %t726
  call void @__inc_ref(ptr %t723)
  %t727 = getelementptr ptr, ptr %t724, i32 1
  store ptr %t723, ptr %t727
  call void @__free_recursive(ptr %t723)
  call void @__free_recursive(ptr %t716)
  br label %join.val.728
join.val.728:
  br label %join.after.677
join.case.arm.4.729:
  %t730 = getelementptr ptr, ptr %t716, i32 1
  %t731 = load ptr, ptr %t730
  call void @__inc_ref(ptr %t731)
  %t732 = getelementptr ptr, ptr %t666, i32 1
  %t733 = load ptr, ptr %t732
  call void @__inc_ref(ptr %t733)
  call void @__inc_ref(ptr %t731)
  %t734 = call ptr @__concat(ptr %t733, ptr %t731)
  call void @__free_recursive(ptr %t731)
  call void @__free_recursive(ptr %t716)
  store ptr %t734, ptr %v__inl321_scrut.jslot
  br label %join.676
join.case.default.720:
  unreachable
join.676:
  %t735 = load ptr, ptr %v__inl321_scrut.jslot
  %t736 = getelementptr ptr, ptr %t735, i32 0
  %t737 = load ptr, ptr %t736
  %t738 = ptrtoint ptr %t737 to i64
  switch i64 %t738, label %case.default.739 [ i64 3, label %case.arm.3.741 i64 4, label %case.arm.4.743 ]
case.arm.3.741:
  call void @__inc_ref(ptr %t735)
  br label %case.end.3.742
case.end.3.742:
  br label %case.join.740
case.arm.4.743:
  %t747 = call ptr @v_twoOk()
  %t748 = getelementptr ptr, ptr %t747, i32 0
  %t749 = load ptr, ptr %t748
  %t750 = ptrtoint ptr %t749 to i64
  switch i64 %t750, label %case.default.751 [ i64 3, label %case.arm.3.753 i64 4, label %case.arm.4.779 ]
case.arm.3.753:
  %t755 = getelementptr ptr, ptr %t747, i32 1
  %t756 = load ptr, ptr %t755
  call void @__inc_ref(ptr %t756)
  %t757 = getelementptr ptr, ptr %t756, i32 0
  %t758 = load ptr, ptr %t757
  %t759 = ptrtoint ptr %t758 to i64
  switch i64 %t759, label %case.default.760 [ i64 925038822, label %case.arm.925038822.762 i64 2252990199, label %case.arm.2252990199.776 ]
case.arm.925038822.762:
  %t764 = getelementptr ptr, ptr %t756, i32 1
  %t765 = load ptr, ptr %t764
  call void @__inc_ref(ptr %t765)
  %t766 = getelementptr ptr, ptr %t765, i32 0
  %t767 = load ptr, ptr %t766
  %t768 = ptrtoint ptr %t767 to i64
  switch i64 %t768, label %case.default.769 [ i64 26, label %case.arm.26.771 i64 27, label %case.arm.27.773 ]
case.arm.26.771:
  br label %case.end.26.772
case.end.26.772:
  br label %case.join.770
case.arm.27.773:
  br label %case.end.27.774
case.end.27.774:
  br label %case.join.770
case.default.769:
  unreachable
case.join.770:
  %t775 = phi ptr [ getelementptr inbounds (i8, ptr @.str.7, i64 12), %case.end.26.772 ], [ getelementptr inbounds (i8, ptr @.str.8, i64 12), %case.end.27.774 ]
  call void @__free_recursive(ptr %t765)
  br label %case.end.925038822.763
case.end.925038822.763:
  br label %case.join.761
case.arm.2252990199.776:
  br label %case.end.2252990199.777
case.end.2252990199.777:
  br label %case.join.761
case.default.760:
  unreachable
case.join.761:
  %t778 = phi ptr [ %t775, %case.end.925038822.763 ], [ getelementptr inbounds (i8, ptr @.str.5, i64 12), %case.end.2252990199.777 ]
  call void @__free_recursive(ptr %t756)
  br label %case.end.3.754
case.end.3.754:
  br label %case.join.752
case.arm.4.779:
  %t781 = getelementptr ptr, ptr %t747, i32 1
  %t782 = load ptr, ptr %t781
  call void @__inc_ref(ptr %t782)
  %t783 = call ptr @__showInt32(ptr %t782)
  br label %case.end.4.780
case.end.4.780:
  br label %case.join.752
case.default.751:
  unreachable
case.join.752:
  %t784 = phi ptr [ %t778, %case.end.3.754 ], [ %t783, %case.end.4.780 ]
  call void @__free_recursive(ptr %t747)
  %t785 = call ptr @v_tagged(ptr getelementptr inbounds (i8, ptr @.str.16, i64 12), ptr %t784)
  %t786 = getelementptr ptr, ptr %t785, i32 0
  %t787 = load ptr, ptr %t786
  %t788 = ptrtoint ptr %t787 to i64
  switch i64 %t788, label %join.case.default.789 [ i64 3, label %join.case.arm.3.790 i64 4, label %join.case.arm.4.798 ]
join.case.arm.3.790:
  %t791 = getelementptr ptr, ptr %t785, i32 1
  %t792 = load ptr, ptr %t791
  call void @__inc_ref(ptr %t792)
  %t793 = call ptr @__alloc(i64 16, i32 1)
  %t794 = inttoptr i64 3 to ptr
  %t795 = getelementptr ptr, ptr %t793, i32 0
  store ptr %t794, ptr %t795
  call void @__inc_ref(ptr %t792)
  %t796 = getelementptr ptr, ptr %t793, i32 1
  store ptr %t792, ptr %t796
  call void @__free_recursive(ptr %t792)
  call void @__free_recursive(ptr %t785)
  br label %join.val.797
join.val.797:
  br label %join.after.746
join.case.arm.4.798:
  %t799 = getelementptr ptr, ptr %t785, i32 1
  %t800 = load ptr, ptr %t799
  call void @__inc_ref(ptr %t800)
  %t801 = getelementptr ptr, ptr %t735, i32 1
  %t802 = load ptr, ptr %t801
  call void @__inc_ref(ptr %t802)
  call void @__inc_ref(ptr %t800)
  %t803 = call ptr @__concat(ptr %t802, ptr %t800)
  call void @__free_recursive(ptr %t800)
  call void @__free_recursive(ptr %t785)
  store ptr %t803, ptr %v__inl323_scrut.jslot
  br label %join.745
join.case.default.789:
  unreachable
join.745:
  %t804 = load ptr, ptr %v__inl323_scrut.jslot
  %t805 = getelementptr ptr, ptr %t804, i32 0
  %t806 = load ptr, ptr %t805
  %t807 = ptrtoint ptr %t806 to i64
  switch i64 %t807, label %case.default.808 [ i64 3, label %case.arm.3.810 i64 4, label %case.arm.4.812 ]
case.arm.3.810:
  call void @__inc_ref(ptr %t804)
  br label %case.end.3.811
case.end.3.811:
  br label %case.join.809
case.arm.4.812:
  %t816 = call ptr @v_idemE1()
  %t817 = getelementptr ptr, ptr %t816, i32 0
  %t818 = load ptr, ptr %t817
  %t819 = ptrtoint ptr %t818 to i64
  switch i64 %t819, label %case.default.820 [ i64 3, label %case.arm.3.822 i64 4, label %case.arm.4.824 ]
case.arm.3.822:
  br label %case.end.3.823
case.end.3.823:
  br label %case.join.821
case.arm.4.824:
  %t826 = getelementptr ptr, ptr %t816, i32 1
  %t827 = load ptr, ptr %t826
  call void @__inc_ref(ptr %t827)
  %t828 = call ptr @__showInt32(ptr %t827)
  br label %case.end.4.825
case.end.4.825:
  br label %case.join.821
case.default.820:
  unreachable
case.join.821:
  %t829 = phi ptr [ getelementptr inbounds (i8, ptr @.str.5, i64 12), %case.end.3.823 ], [ %t828, %case.end.4.825 ]
  call void @__free_recursive(ptr %t816)
  %t830 = call ptr @v_tagged(ptr getelementptr inbounds (i8, ptr @.str.15, i64 12), ptr %t829)
  %t831 = getelementptr ptr, ptr %t830, i32 0
  %t832 = load ptr, ptr %t831
  %t833 = ptrtoint ptr %t832 to i64
  switch i64 %t833, label %join.case.default.834 [ i64 3, label %join.case.arm.3.835 i64 4, label %join.case.arm.4.843 ]
join.case.arm.3.835:
  %t836 = getelementptr ptr, ptr %t830, i32 1
  %t837 = load ptr, ptr %t836
  call void @__inc_ref(ptr %t837)
  %t838 = call ptr @__alloc(i64 16, i32 1)
  %t839 = inttoptr i64 3 to ptr
  %t840 = getelementptr ptr, ptr %t838, i32 0
  store ptr %t839, ptr %t840
  call void @__inc_ref(ptr %t837)
  %t841 = getelementptr ptr, ptr %t838, i32 1
  store ptr %t837, ptr %t841
  call void @__free_recursive(ptr %t837)
  call void @__free_recursive(ptr %t830)
  br label %join.val.842
join.val.842:
  br label %join.after.815
join.case.arm.4.843:
  %t844 = getelementptr ptr, ptr %t830, i32 1
  %t845 = load ptr, ptr %t844
  call void @__inc_ref(ptr %t845)
  %t846 = getelementptr ptr, ptr %t804, i32 1
  %t847 = load ptr, ptr %t846
  call void @__inc_ref(ptr %t847)
  call void @__inc_ref(ptr %t845)
  %t848 = call ptr @__concat(ptr %t847, ptr %t845)
  call void @__free_recursive(ptr %t845)
  call void @__free_recursive(ptr %t830)
  store ptr %t848, ptr %v__inl325_scrut.jslot
  br label %join.814
join.case.default.834:
  unreachable
join.814:
  %t849 = load ptr, ptr %v__inl325_scrut.jslot
  %t850 = getelementptr ptr, ptr %t849, i32 0
  %t851 = load ptr, ptr %t850
  %t852 = ptrtoint ptr %t851 to i64
  switch i64 %t852, label %case.default.853 [ i64 3, label %case.arm.3.855 i64 4, label %case.arm.4.857 ]
case.arm.3.855:
  call void @__inc_ref(ptr %t849)
  br label %case.end.3.856
case.end.3.856:
  br label %case.join.854
case.arm.4.857:
  %t861 = call ptr @v_idemE2()
  %t862 = getelementptr ptr, ptr %t861, i32 0
  %t863 = load ptr, ptr %t862
  %t864 = ptrtoint ptr %t863 to i64
  switch i64 %t864, label %case.default.865 [ i64 3, label %case.arm.3.867 i64 4, label %case.arm.4.869 ]
case.arm.3.867:
  br label %case.end.3.868
case.end.3.868:
  br label %case.join.866
case.arm.4.869:
  %t871 = getelementptr ptr, ptr %t861, i32 1
  %t872 = load ptr, ptr %t871
  call void @__inc_ref(ptr %t872)
  %t873 = call ptr @__showInt32(ptr %t872)
  br label %case.end.4.870
case.end.4.870:
  br label %case.join.866
case.default.865:
  unreachable
case.join.866:
  %t874 = phi ptr [ getelementptr inbounds (i8, ptr @.str.5, i64 12), %case.end.3.868 ], [ %t873, %case.end.4.870 ]
  call void @__free_recursive(ptr %t861)
  %t875 = call ptr @v_tagged(ptr getelementptr inbounds (i8, ptr @.str.14, i64 12), ptr %t874)
  %t876 = getelementptr ptr, ptr %t875, i32 0
  %t877 = load ptr, ptr %t876
  %t878 = ptrtoint ptr %t877 to i64
  switch i64 %t878, label %join.case.default.879 [ i64 3, label %join.case.arm.3.880 i64 4, label %join.case.arm.4.888 ]
join.case.arm.3.880:
  %t881 = getelementptr ptr, ptr %t875, i32 1
  %t882 = load ptr, ptr %t881
  call void @__inc_ref(ptr %t882)
  %t883 = call ptr @__alloc(i64 16, i32 1)
  %t884 = inttoptr i64 3 to ptr
  %t885 = getelementptr ptr, ptr %t883, i32 0
  store ptr %t884, ptr %t885
  call void @__inc_ref(ptr %t882)
  %t886 = getelementptr ptr, ptr %t883, i32 1
  store ptr %t882, ptr %t886
  call void @__free_recursive(ptr %t882)
  call void @__free_recursive(ptr %t875)
  br label %join.val.887
join.val.887:
  br label %join.after.860
join.case.arm.4.888:
  %t889 = getelementptr ptr, ptr %t875, i32 1
  %t890 = load ptr, ptr %t889
  call void @__inc_ref(ptr %t890)
  %t891 = getelementptr ptr, ptr %t849, i32 1
  %t892 = load ptr, ptr %t891
  call void @__inc_ref(ptr %t892)
  call void @__inc_ref(ptr %t890)
  %t893 = call ptr @__concat(ptr %t892, ptr %t890)
  call void @__free_recursive(ptr %t890)
  call void @__free_recursive(ptr %t875)
  store ptr %t893, ptr %v__inl327_scrut.jslot
  br label %join.859
join.case.default.879:
  unreachable
join.859:
  %t894 = load ptr, ptr %v__inl327_scrut.jslot
  %t895 = getelementptr ptr, ptr %t894, i32 0
  %t896 = load ptr, ptr %t895
  %t897 = ptrtoint ptr %t896 to i64
  switch i64 %t897, label %case.default.898 [ i64 3, label %case.arm.3.900 i64 4, label %case.arm.4.902 ]
case.arm.3.900:
  call void @__inc_ref(ptr %t894)
  br label %case.end.3.901
case.end.3.901:
  br label %case.join.899
case.arm.4.902:
  %t906 = call ptr @v_idem2First()
  %t907 = getelementptr ptr, ptr %t906, i32 0
  %t908 = load ptr, ptr %t907
  %t909 = ptrtoint ptr %t908 to i64
  switch i64 %t909, label %case.default.910 [ i64 3, label %case.arm.3.912 i64 4, label %case.arm.4.926 ]
case.arm.3.912:
  %t914 = getelementptr ptr, ptr %t906, i32 1
  %t915 = load ptr, ptr %t914
  call void @__inc_ref(ptr %t915)
  %t916 = getelementptr ptr, ptr %t915, i32 0
  %t917 = load ptr, ptr %t916
  %t918 = ptrtoint ptr %t917 to i64
  switch i64 %t918, label %case.default.919 [ i64 26, label %case.arm.26.921 i64 27, label %case.arm.27.923 ]
case.arm.26.921:
  br label %case.end.26.922
case.end.26.922:
  br label %case.join.920
case.arm.27.923:
  br label %case.end.27.924
case.end.27.924:
  br label %case.join.920
case.default.919:
  unreachable
case.join.920:
  %t925 = phi ptr [ getelementptr inbounds (i8, ptr @.str.7, i64 12), %case.end.26.922 ], [ getelementptr inbounds (i8, ptr @.str.8, i64 12), %case.end.27.924 ]
  call void @__free_recursive(ptr %t915)
  br label %case.end.3.913
case.end.3.913:
  br label %case.join.911
case.arm.4.926:
  %t928 = getelementptr ptr, ptr %t906, i32 1
  %t929 = load ptr, ptr %t928
  call void @__inc_ref(ptr %t929)
  %t930 = call ptr @__showInt32(ptr %t929)
  br label %case.end.4.927
case.end.4.927:
  br label %case.join.911
case.default.910:
  unreachable
case.join.911:
  %t931 = phi ptr [ %t925, %case.end.3.913 ], [ %t930, %case.end.4.927 ]
  call void @__free_recursive(ptr %t906)
  %t932 = call ptr @v_tagged(ptr getelementptr inbounds (i8, ptr @.str.13, i64 12), ptr %t931)
  %t933 = getelementptr ptr, ptr %t932, i32 0
  %t934 = load ptr, ptr %t933
  %t935 = ptrtoint ptr %t934 to i64
  switch i64 %t935, label %join.case.default.936 [ i64 3, label %join.case.arm.3.937 i64 4, label %join.case.arm.4.945 ]
join.case.arm.3.937:
  %t938 = getelementptr ptr, ptr %t932, i32 1
  %t939 = load ptr, ptr %t938
  call void @__inc_ref(ptr %t939)
  %t940 = call ptr @__alloc(i64 16, i32 1)
  %t941 = inttoptr i64 3 to ptr
  %t942 = getelementptr ptr, ptr %t940, i32 0
  store ptr %t941, ptr %t942
  call void @__inc_ref(ptr %t939)
  %t943 = getelementptr ptr, ptr %t940, i32 1
  store ptr %t939, ptr %t943
  call void @__free_recursive(ptr %t939)
  call void @__free_recursive(ptr %t932)
  br label %join.val.944
join.val.944:
  br label %join.after.905
join.case.arm.4.945:
  %t946 = getelementptr ptr, ptr %t932, i32 1
  %t947 = load ptr, ptr %t946
  call void @__inc_ref(ptr %t947)
  %t948 = getelementptr ptr, ptr %t894, i32 1
  %t949 = load ptr, ptr %t948
  call void @__inc_ref(ptr %t949)
  call void @__inc_ref(ptr %t947)
  %t950 = call ptr @__concat(ptr %t949, ptr %t947)
  call void @__free_recursive(ptr %t947)
  call void @__free_recursive(ptr %t932)
  store ptr %t950, ptr %v__inl329_scrut.jslot
  br label %join.904
join.case.default.936:
  unreachable
join.904:
  %t951 = load ptr, ptr %v__inl329_scrut.jslot
  %t952 = getelementptr ptr, ptr %t951, i32 0
  %t953 = load ptr, ptr %t952
  %t954 = ptrtoint ptr %t953 to i64
  switch i64 %t954, label %case.default.955 [ i64 3, label %case.arm.3.957 i64 4, label %case.arm.4.959 ]
case.arm.3.957:
  call void @__inc_ref(ptr %t951)
  br label %case.end.3.958
case.end.3.958:
  br label %case.join.956
case.arm.4.959:
  %t963 = call ptr @v_idem2Second()
  %t964 = getelementptr ptr, ptr %t963, i32 0
  %t965 = load ptr, ptr %t964
  %t966 = ptrtoint ptr %t965 to i64
  switch i64 %t966, label %case.default.967 [ i64 3, label %case.arm.3.969 i64 4, label %case.arm.4.983 ]
case.arm.3.969:
  %t971 = getelementptr ptr, ptr %t963, i32 1
  %t972 = load ptr, ptr %t971
  call void @__inc_ref(ptr %t972)
  %t973 = getelementptr ptr, ptr %t972, i32 0
  %t974 = load ptr, ptr %t973
  %t975 = ptrtoint ptr %t974 to i64
  switch i64 %t975, label %case.default.976 [ i64 26, label %case.arm.26.978 i64 27, label %case.arm.27.980 ]
case.arm.26.978:
  br label %case.end.26.979
case.end.26.979:
  br label %case.join.977
case.arm.27.980:
  br label %case.end.27.981
case.end.27.981:
  br label %case.join.977
case.default.976:
  unreachable
case.join.977:
  %t982 = phi ptr [ getelementptr inbounds (i8, ptr @.str.7, i64 12), %case.end.26.979 ], [ getelementptr inbounds (i8, ptr @.str.8, i64 12), %case.end.27.981 ]
  call void @__free_recursive(ptr %t972)
  br label %case.end.3.970
case.end.3.970:
  br label %case.join.968
case.arm.4.983:
  %t985 = getelementptr ptr, ptr %t963, i32 1
  %t986 = load ptr, ptr %t985
  call void @__inc_ref(ptr %t986)
  %t987 = call ptr @__showInt32(ptr %t986)
  br label %case.end.4.984
case.end.4.984:
  br label %case.join.968
case.default.967:
  unreachable
case.join.968:
  %t988 = phi ptr [ %t982, %case.end.3.970 ], [ %t987, %case.end.4.984 ]
  call void @__free_recursive(ptr %t963)
  %t989 = call ptr @v_tagged(ptr getelementptr inbounds (i8, ptr @.str.12, i64 12), ptr %t988)
  %t990 = getelementptr ptr, ptr %t989, i32 0
  %t991 = load ptr, ptr %t990
  %t992 = ptrtoint ptr %t991 to i64
  switch i64 %t992, label %join.case.default.993 [ i64 3, label %join.case.arm.3.994 i64 4, label %join.case.arm.4.1002 ]
join.case.arm.3.994:
  %t995 = getelementptr ptr, ptr %t989, i32 1
  %t996 = load ptr, ptr %t995
  call void @__inc_ref(ptr %t996)
  %t997 = call ptr @__alloc(i64 16, i32 1)
  %t998 = inttoptr i64 3 to ptr
  %t999 = getelementptr ptr, ptr %t997, i32 0
  store ptr %t998, ptr %t999
  call void @__inc_ref(ptr %t996)
  %t1000 = getelementptr ptr, ptr %t997, i32 1
  store ptr %t996, ptr %t1000
  call void @__free_recursive(ptr %t996)
  call void @__free_recursive(ptr %t989)
  br label %join.val.1001
join.val.1001:
  br label %join.after.962
join.case.arm.4.1002:
  %t1003 = getelementptr ptr, ptr %t989, i32 1
  %t1004 = load ptr, ptr %t1003
  call void @__inc_ref(ptr %t1004)
  %t1005 = getelementptr ptr, ptr %t951, i32 1
  %t1006 = load ptr, ptr %t1005
  call void @__inc_ref(ptr %t1006)
  call void @__inc_ref(ptr %t1004)
  %t1007 = call ptr @__concat(ptr %t1006, ptr %t1004)
  call void @__free_recursive(ptr %t1004)
  call void @__free_recursive(ptr %t989)
  store ptr %t1007, ptr %v__inl331_scrut.jslot
  br label %join.961
join.case.default.993:
  unreachable
join.961:
  %t1008 = load ptr, ptr %v__inl331_scrut.jslot
  %t1009 = getelementptr ptr, ptr %t1008, i32 0
  %t1010 = load ptr, ptr %t1009
  %t1011 = ptrtoint ptr %t1010 to i64
  switch i64 %t1011, label %case.default.1012 [ i64 3, label %case.arm.3.1014 i64 4, label %case.arm.4.1016 ]
case.arm.3.1014:
  call void @__inc_ref(ptr %t1008)
  br label %case.end.3.1015
case.end.3.1015:
  br label %case.join.1013
case.arm.4.1016:
  %t1020 = call ptr @v_wE1()
  %t1021 = getelementptr ptr, ptr %t1020, i32 0
  %t1022 = load ptr, ptr %t1021
  %t1023 = ptrtoint ptr %t1022 to i64
  switch i64 %t1023, label %case.default.1024 [ i64 3, label %case.arm.3.1026 i64 4, label %case.arm.4.1056 ]
case.arm.3.1026:
  %t1028 = getelementptr ptr, ptr %t1020, i32 1
  %t1029 = load ptr, ptr %t1028
  call void @__inc_ref(ptr %t1029)
  %t1030 = getelementptr ptr, ptr %t1029, i32 0
  %t1031 = load ptr, ptr %t1030
  %t1032 = ptrtoint ptr %t1031 to i64
  switch i64 %t1032, label %case.default.1033 [ i64 925038822, label %case.arm.925038822.1035 i64 1615808600, label %case.arm.1615808600.1049 i64 2252990199, label %case.arm.2252990199.1053 ]
case.arm.925038822.1035:
  %t1037 = getelementptr ptr, ptr %t1029, i32 1
  %t1038 = load ptr, ptr %t1037
  call void @__inc_ref(ptr %t1038)
  %t1039 = getelementptr ptr, ptr %t1038, i32 0
  %t1040 = load ptr, ptr %t1039
  %t1041 = ptrtoint ptr %t1040 to i64
  switch i64 %t1041, label %case.default.1042 [ i64 26, label %case.arm.26.1044 i64 27, label %case.arm.27.1046 ]
case.arm.26.1044:
  br label %case.end.26.1045
case.end.26.1045:
  br label %case.join.1043
case.arm.27.1046:
  br label %case.end.27.1047
case.end.27.1047:
  br label %case.join.1043
case.default.1042:
  unreachable
case.join.1043:
  %t1048 = phi ptr [ getelementptr inbounds (i8, ptr @.str.7, i64 12), %case.end.26.1045 ], [ getelementptr inbounds (i8, ptr @.str.8, i64 12), %case.end.27.1047 ]
  call void @__free_recursive(ptr %t1038)
  br label %case.end.925038822.1036
case.end.925038822.1036:
  br label %case.join.1034
case.arm.1615808600.1049:
  %t1051 = getelementptr ptr, ptr %t1029, i32 1
  %t1052 = load ptr, ptr %t1051
  call void @__inc_ref(ptr %t1052)
  br label %case.end.1615808600.1050
case.end.1615808600.1050:
  br label %case.join.1034
case.arm.2252990199.1053:
  br label %case.end.2252990199.1054
case.end.2252990199.1054:
  br label %case.join.1034
case.default.1033:
  unreachable
case.join.1034:
  %t1055 = phi ptr [ %t1048, %case.end.925038822.1036 ], [ %t1052, %case.end.1615808600.1050 ], [ getelementptr inbounds (i8, ptr @.str.5, i64 12), %case.end.2252990199.1054 ]
  call void @__free_recursive(ptr %t1029)
  br label %case.end.3.1027
case.end.3.1027:
  br label %case.join.1025
case.arm.4.1056:
  %t1058 = getelementptr ptr, ptr %t1020, i32 1
  %t1059 = load ptr, ptr %t1058
  call void @__inc_ref(ptr %t1059)
  %t1060 = call ptr @__showInt32(ptr %t1059)
  br label %case.end.4.1057
case.end.4.1057:
  br label %case.join.1025
case.default.1024:
  unreachable
case.join.1025:
  %t1061 = phi ptr [ %t1055, %case.end.3.1027 ], [ %t1060, %case.end.4.1057 ]
  call void @__free_recursive(ptr %t1020)
  %t1062 = call ptr @v_tagged(ptr getelementptr inbounds (i8, ptr @.str.11, i64 12), ptr %t1061)
  %t1063 = getelementptr ptr, ptr %t1062, i32 0
  %t1064 = load ptr, ptr %t1063
  %t1065 = ptrtoint ptr %t1064 to i64
  switch i64 %t1065, label %join.case.default.1066 [ i64 3, label %join.case.arm.3.1067 i64 4, label %join.case.arm.4.1075 ]
join.case.arm.3.1067:
  %t1068 = getelementptr ptr, ptr %t1062, i32 1
  %t1069 = load ptr, ptr %t1068
  call void @__inc_ref(ptr %t1069)
  %t1070 = call ptr @__alloc(i64 16, i32 1)
  %t1071 = inttoptr i64 3 to ptr
  %t1072 = getelementptr ptr, ptr %t1070, i32 0
  store ptr %t1071, ptr %t1072
  call void @__inc_ref(ptr %t1069)
  %t1073 = getelementptr ptr, ptr %t1070, i32 1
  store ptr %t1069, ptr %t1073
  call void @__free_recursive(ptr %t1069)
  call void @__free_recursive(ptr %t1062)
  br label %join.val.1074
join.val.1074:
  br label %join.after.1019
join.case.arm.4.1075:
  %t1076 = getelementptr ptr, ptr %t1062, i32 1
  %t1077 = load ptr, ptr %t1076
  call void @__inc_ref(ptr %t1077)
  %t1078 = getelementptr ptr, ptr %t1008, i32 1
  %t1079 = load ptr, ptr %t1078
  call void @__inc_ref(ptr %t1079)
  call void @__inc_ref(ptr %t1077)
  %t1080 = call ptr @__concat(ptr %t1079, ptr %t1077)
  call void @__free_recursive(ptr %t1077)
  call void @__free_recursive(ptr %t1062)
  store ptr %t1080, ptr %v__inl333_scrut.jslot
  br label %join.1018
join.case.default.1066:
  unreachable
join.1018:
  %t1081 = load ptr, ptr %v__inl333_scrut.jslot
  %t1082 = getelementptr ptr, ptr %t1081, i32 0
  %t1083 = load ptr, ptr %t1082
  %t1084 = ptrtoint ptr %t1083 to i64
  switch i64 %t1084, label %case.default.1085 [ i64 3, label %case.arm.3.1087 i64 4, label %case.arm.4.1089 ]
case.arm.3.1087:
  call void @__inc_ref(ptr %t1081)
  br label %case.end.3.1088
case.end.3.1088:
  br label %case.join.1086
case.arm.4.1089:
  %t1093 = call ptr @v_wE2str()
  %t1094 = getelementptr ptr, ptr %t1093, i32 0
  %t1095 = load ptr, ptr %t1094
  %t1096 = ptrtoint ptr %t1095 to i64
  switch i64 %t1096, label %case.default.1097 [ i64 3, label %case.arm.3.1099 i64 4, label %case.arm.4.1129 ]
case.arm.3.1099:
  %t1101 = getelementptr ptr, ptr %t1093, i32 1
  %t1102 = load ptr, ptr %t1101
  call void @__inc_ref(ptr %t1102)
  %t1103 = getelementptr ptr, ptr %t1102, i32 0
  %t1104 = load ptr, ptr %t1103
  %t1105 = ptrtoint ptr %t1104 to i64
  switch i64 %t1105, label %case.default.1106 [ i64 925038822, label %case.arm.925038822.1108 i64 1615808600, label %case.arm.1615808600.1122 i64 2252990199, label %case.arm.2252990199.1126 ]
case.arm.925038822.1108:
  %t1110 = getelementptr ptr, ptr %t1102, i32 1
  %t1111 = load ptr, ptr %t1110
  call void @__inc_ref(ptr %t1111)
  %t1112 = getelementptr ptr, ptr %t1111, i32 0
  %t1113 = load ptr, ptr %t1112
  %t1114 = ptrtoint ptr %t1113 to i64
  switch i64 %t1114, label %case.default.1115 [ i64 26, label %case.arm.26.1117 i64 27, label %case.arm.27.1119 ]
case.arm.26.1117:
  br label %case.end.26.1118
case.end.26.1118:
  br label %case.join.1116
case.arm.27.1119:
  br label %case.end.27.1120
case.end.27.1120:
  br label %case.join.1116
case.default.1115:
  unreachable
case.join.1116:
  %t1121 = phi ptr [ getelementptr inbounds (i8, ptr @.str.7, i64 12), %case.end.26.1118 ], [ getelementptr inbounds (i8, ptr @.str.8, i64 12), %case.end.27.1120 ]
  call void @__free_recursive(ptr %t1111)
  br label %case.end.925038822.1109
case.end.925038822.1109:
  br label %case.join.1107
case.arm.1615808600.1122:
  %t1124 = getelementptr ptr, ptr %t1102, i32 1
  %t1125 = load ptr, ptr %t1124
  call void @__inc_ref(ptr %t1125)
  br label %case.end.1615808600.1123
case.end.1615808600.1123:
  br label %case.join.1107
case.arm.2252990199.1126:
  br label %case.end.2252990199.1127
case.end.2252990199.1127:
  br label %case.join.1107
case.default.1106:
  unreachable
case.join.1107:
  %t1128 = phi ptr [ %t1121, %case.end.925038822.1109 ], [ %t1125, %case.end.1615808600.1123 ], [ getelementptr inbounds (i8, ptr @.str.5, i64 12), %case.end.2252990199.1127 ]
  call void @__free_recursive(ptr %t1102)
  br label %case.end.3.1100
case.end.3.1100:
  br label %case.join.1098
case.arm.4.1129:
  %t1131 = getelementptr ptr, ptr %t1093, i32 1
  %t1132 = load ptr, ptr %t1131
  call void @__inc_ref(ptr %t1132)
  %t1133 = call ptr @__showInt32(ptr %t1132)
  br label %case.end.4.1130
case.end.4.1130:
  br label %case.join.1098
case.default.1097:
  unreachable
case.join.1098:
  %t1134 = phi ptr [ %t1128, %case.end.3.1100 ], [ %t1133, %case.end.4.1130 ]
  call void @__free_recursive(ptr %t1093)
  %t1135 = call ptr @v_tagged(ptr getelementptr inbounds (i8, ptr @.str.10, i64 12), ptr %t1134)
  %t1136 = getelementptr ptr, ptr %t1135, i32 0
  %t1137 = load ptr, ptr %t1136
  %t1138 = ptrtoint ptr %t1137 to i64
  switch i64 %t1138, label %join.case.default.1139 [ i64 3, label %join.case.arm.3.1140 i64 4, label %join.case.arm.4.1148 ]
join.case.arm.3.1140:
  %t1141 = getelementptr ptr, ptr %t1135, i32 1
  %t1142 = load ptr, ptr %t1141
  call void @__inc_ref(ptr %t1142)
  %t1143 = call ptr @__alloc(i64 16, i32 1)
  %t1144 = inttoptr i64 3 to ptr
  %t1145 = getelementptr ptr, ptr %t1143, i32 0
  store ptr %t1144, ptr %t1145
  call void @__inc_ref(ptr %t1142)
  %t1146 = getelementptr ptr, ptr %t1143, i32 1
  store ptr %t1142, ptr %t1146
  call void @__free_recursive(ptr %t1142)
  call void @__free_recursive(ptr %t1135)
  br label %join.val.1147
join.val.1147:
  br label %join.after.1092
join.case.arm.4.1148:
  %t1149 = getelementptr ptr, ptr %t1135, i32 1
  %t1150 = load ptr, ptr %t1149
  call void @__inc_ref(ptr %t1150)
  %t1151 = getelementptr ptr, ptr %t1081, i32 1
  %t1152 = load ptr, ptr %t1151
  call void @__inc_ref(ptr %t1152)
  call void @__inc_ref(ptr %t1150)
  %t1153 = call ptr @__concat(ptr %t1152, ptr %t1150)
  call void @__free_recursive(ptr %t1150)
  call void @__free_recursive(ptr %t1135)
  store ptr %t1153, ptr %v__inl335_scrut.jslot
  br label %join.1091
join.case.default.1139:
  unreachable
join.1091:
  %t1154 = load ptr, ptr %v__inl335_scrut.jslot
  %t1155 = getelementptr ptr, ptr %t1154, i32 0
  %t1156 = load ptr, ptr %t1155
  %t1157 = ptrtoint ptr %t1156 to i64
  switch i64 %t1157, label %case.default.1158 [ i64 3, label %case.arm.3.1160 i64 4, label %case.arm.4.1162 ]
case.arm.3.1160:
  call void @__inc_ref(ptr %t1154)
  br label %case.end.3.1161
case.end.3.1161:
  br label %case.join.1159
case.arm.4.1162:
  %t1166 = call ptr @v_wE3()
  %t1167 = getelementptr ptr, ptr %t1166, i32 0
  %t1168 = load ptr, ptr %t1167
  %t1169 = ptrtoint ptr %t1168 to i64
  switch i64 %t1169, label %case.default.1170 [ i64 3, label %case.arm.3.1172 i64 4, label %case.arm.4.1202 ]
case.arm.3.1172:
  %t1174 = getelementptr ptr, ptr %t1166, i32 1
  %t1175 = load ptr, ptr %t1174
  call void @__inc_ref(ptr %t1175)
  %t1176 = getelementptr ptr, ptr %t1175, i32 0
  %t1177 = load ptr, ptr %t1176
  %t1178 = ptrtoint ptr %t1177 to i64
  switch i64 %t1178, label %case.default.1179 [ i64 925038822, label %case.arm.925038822.1181 i64 1615808600, label %case.arm.1615808600.1195 i64 2252990199, label %case.arm.2252990199.1199 ]
case.arm.925038822.1181:
  %t1183 = getelementptr ptr, ptr %t1175, i32 1
  %t1184 = load ptr, ptr %t1183
  call void @__inc_ref(ptr %t1184)
  %t1185 = getelementptr ptr, ptr %t1184, i32 0
  %t1186 = load ptr, ptr %t1185
  %t1187 = ptrtoint ptr %t1186 to i64
  switch i64 %t1187, label %case.default.1188 [ i64 26, label %case.arm.26.1190 i64 27, label %case.arm.27.1192 ]
case.arm.26.1190:
  br label %case.end.26.1191
case.end.26.1191:
  br label %case.join.1189
case.arm.27.1192:
  br label %case.end.27.1193
case.end.27.1193:
  br label %case.join.1189
case.default.1188:
  unreachable
case.join.1189:
  %t1194 = phi ptr [ getelementptr inbounds (i8, ptr @.str.7, i64 12), %case.end.26.1191 ], [ getelementptr inbounds (i8, ptr @.str.8, i64 12), %case.end.27.1193 ]
  call void @__free_recursive(ptr %t1184)
  br label %case.end.925038822.1182
case.end.925038822.1182:
  br label %case.join.1180
case.arm.1615808600.1195:
  %t1197 = getelementptr ptr, ptr %t1175, i32 1
  %t1198 = load ptr, ptr %t1197
  call void @__inc_ref(ptr %t1198)
  br label %case.end.1615808600.1196
case.end.1615808600.1196:
  br label %case.join.1180
case.arm.2252990199.1199:
  br label %case.end.2252990199.1200
case.end.2252990199.1200:
  br label %case.join.1180
case.default.1179:
  unreachable
case.join.1180:
  %t1201 = phi ptr [ %t1194, %case.end.925038822.1182 ], [ %t1198, %case.end.1615808600.1196 ], [ getelementptr inbounds (i8, ptr @.str.5, i64 12), %case.end.2252990199.1200 ]
  call void @__free_recursive(ptr %t1175)
  br label %case.end.3.1173
case.end.3.1173:
  br label %case.join.1171
case.arm.4.1202:
  %t1204 = getelementptr ptr, ptr %t1166, i32 1
  %t1205 = load ptr, ptr %t1204
  call void @__inc_ref(ptr %t1205)
  %t1206 = call ptr @__showInt32(ptr %t1205)
  br label %case.end.4.1203
case.end.4.1203:
  br label %case.join.1171
case.default.1170:
  unreachable
case.join.1171:
  %t1207 = phi ptr [ %t1201, %case.end.3.1173 ], [ %t1206, %case.end.4.1203 ]
  call void @__free_recursive(ptr %t1166)
  %t1208 = call ptr @v_tagged(ptr getelementptr inbounds (i8, ptr @.str.9, i64 12), ptr %t1207)
  %t1209 = getelementptr ptr, ptr %t1208, i32 0
  %t1210 = load ptr, ptr %t1209
  %t1211 = ptrtoint ptr %t1210 to i64
  switch i64 %t1211, label %join.case.default.1212 [ i64 3, label %join.case.arm.3.1213 i64 4, label %join.case.arm.4.1221 ]
join.case.arm.3.1213:
  %t1214 = getelementptr ptr, ptr %t1208, i32 1
  %t1215 = load ptr, ptr %t1214
  call void @__inc_ref(ptr %t1215)
  %t1216 = call ptr @__alloc(i64 16, i32 1)
  %t1217 = inttoptr i64 3 to ptr
  %t1218 = getelementptr ptr, ptr %t1216, i32 0
  store ptr %t1217, ptr %t1218
  call void @__inc_ref(ptr %t1215)
  %t1219 = getelementptr ptr, ptr %t1216, i32 1
  store ptr %t1215, ptr %t1219
  call void @__free_recursive(ptr %t1215)
  call void @__free_recursive(ptr %t1208)
  br label %join.val.1220
join.val.1220:
  br label %join.after.1165
join.case.arm.4.1221:
  %t1222 = getelementptr ptr, ptr %t1208, i32 1
  %t1223 = load ptr, ptr %t1222
  call void @__inc_ref(ptr %t1223)
  %t1224 = getelementptr ptr, ptr %t1154, i32 1
  %t1225 = load ptr, ptr %t1224
  call void @__inc_ref(ptr %t1225)
  call void @__inc_ref(ptr %t1223)
  %t1226 = call ptr @__concat(ptr %t1225, ptr %t1223)
  call void @__free_recursive(ptr %t1223)
  call void @__free_recursive(ptr %t1208)
  store ptr %t1226, ptr %v__inl337_scrut.jslot
  br label %join.1164
join.case.default.1212:
  unreachable
join.1164:
  %t1227 = load ptr, ptr %v__inl337_scrut.jslot
  %t1228 = getelementptr ptr, ptr %t1227, i32 0
  %t1229 = load ptr, ptr %t1228
  %t1230 = ptrtoint ptr %t1229 to i64
  switch i64 %t1230, label %case.default.1231 [ i64 3, label %case.arm.3.1233 i64 4, label %case.arm.4.1235 ]
case.arm.3.1233:
  call void @__inc_ref(ptr %t1227)
  br label %case.end.3.1234
case.end.3.1234:
  br label %case.join.1232
case.arm.4.1235:
  %t1237 = call ptr @v_wOk()
  %t1238 = getelementptr ptr, ptr %t1237, i32 0
  %t1239 = load ptr, ptr %t1238
  %t1240 = ptrtoint ptr %t1239 to i64
  switch i64 %t1240, label %case.default.1241 [ i64 3, label %case.arm.3.1243 i64 4, label %case.arm.4.1273 ]
case.arm.3.1243:
  %t1245 = getelementptr ptr, ptr %t1237, i32 1
  %t1246 = load ptr, ptr %t1245
  call void @__inc_ref(ptr %t1246)
  %t1247 = getelementptr ptr, ptr %t1246, i32 0
  %t1248 = load ptr, ptr %t1247
  %t1249 = ptrtoint ptr %t1248 to i64
  switch i64 %t1249, label %case.default.1250 [ i64 925038822, label %case.arm.925038822.1252 i64 1615808600, label %case.arm.1615808600.1266 i64 2252990199, label %case.arm.2252990199.1270 ]
case.arm.925038822.1252:
  %t1254 = getelementptr ptr, ptr %t1246, i32 1
  %t1255 = load ptr, ptr %t1254
  call void @__inc_ref(ptr %t1255)
  %t1256 = getelementptr ptr, ptr %t1255, i32 0
  %t1257 = load ptr, ptr %t1256
  %t1258 = ptrtoint ptr %t1257 to i64
  switch i64 %t1258, label %case.default.1259 [ i64 26, label %case.arm.26.1261 i64 27, label %case.arm.27.1263 ]
case.arm.26.1261:
  br label %case.end.26.1262
case.end.26.1262:
  br label %case.join.1260
case.arm.27.1263:
  br label %case.end.27.1264
case.end.27.1264:
  br label %case.join.1260
case.default.1259:
  unreachable
case.join.1260:
  %t1265 = phi ptr [ getelementptr inbounds (i8, ptr @.str.7, i64 12), %case.end.26.1262 ], [ getelementptr inbounds (i8, ptr @.str.8, i64 12), %case.end.27.1264 ]
  call void @__free_recursive(ptr %t1255)
  br label %case.end.925038822.1253
case.end.925038822.1253:
  br label %case.join.1251
case.arm.1615808600.1266:
  %t1268 = getelementptr ptr, ptr %t1246, i32 1
  %t1269 = load ptr, ptr %t1268
  call void @__inc_ref(ptr %t1269)
  br label %case.end.1615808600.1267
case.end.1615808600.1267:
  br label %case.join.1251
case.arm.2252990199.1270:
  br label %case.end.2252990199.1271
case.end.2252990199.1271:
  br label %case.join.1251
case.default.1250:
  unreachable
case.join.1251:
  %t1272 = phi ptr [ %t1265, %case.end.925038822.1253 ], [ %t1269, %case.end.1615808600.1267 ], [ getelementptr inbounds (i8, ptr @.str.5, i64 12), %case.end.2252990199.1271 ]
  call void @__free_recursive(ptr %t1246)
  br label %case.end.3.1244
case.end.3.1244:
  br label %case.join.1242
case.arm.4.1273:
  %t1275 = getelementptr ptr, ptr %t1237, i32 1
  %t1276 = load ptr, ptr %t1275
  call void @__inc_ref(ptr %t1276)
  %t1277 = call ptr @__showInt32(ptr %t1276)
  br label %case.end.4.1274
case.end.4.1274:
  br label %case.join.1242
case.default.1241:
  unreachable
case.join.1242:
  %t1278 = phi ptr [ %t1272, %case.end.3.1244 ], [ %t1277, %case.end.4.1274 ]
  call void @__free_recursive(ptr %t1237)
  %t1279 = call ptr @v_tagged(ptr getelementptr inbounds (i8, ptr @.str.6, i64 12), ptr %t1278)
  %t1280 = getelementptr ptr, ptr %t1279, i32 0
  %t1281 = load ptr, ptr %t1280
  %t1282 = ptrtoint ptr %t1281 to i64
  switch i64 %t1282, label %case.default.1283 [ i64 3, label %case.arm.3.1285 i64 4, label %case.arm.4.1293 ]
case.arm.3.1285:
  %t1287 = getelementptr ptr, ptr %t1279, i32 1
  %t1288 = load ptr, ptr %t1287
  call void @__inc_ref(ptr %t1288)
  %t1289 = call ptr @__alloc(i64 16, i32 1)
  %t1290 = inttoptr i64 3 to ptr
  %t1291 = getelementptr ptr, ptr %t1289, i32 0
  store ptr %t1290, ptr %t1291
  call void @__inc_ref(ptr %t1288)
  %t1292 = getelementptr ptr, ptr %t1289, i32 1
  store ptr %t1288, ptr %t1292
  call void @__free_recursive(ptr %t1288)
  br label %case.end.3.1286
case.end.3.1286:
  br label %case.join.1284
case.arm.4.1293:
  %t1295 = getelementptr ptr, ptr %t1279, i32 1
  %t1296 = load ptr, ptr %t1295
  call void @__inc_ref(ptr %t1296)
  %t1297 = getelementptr ptr, ptr %t1227, i32 1
  %t1298 = load ptr, ptr %t1297
  call void @__inc_ref(ptr %t1298)
  call void @__inc_ref(ptr %t1296)
  %t1299 = call ptr @__concat(ptr %t1298, ptr %t1296)
  call void @__free_recursive(ptr %t1296)
  br label %case.end.4.1294
case.end.4.1294:
  br label %case.join.1284
case.default.1283:
  unreachable
case.join.1284:
  %t1300 = phi ptr [ %t1289, %case.end.3.1286 ], [ %t1299, %case.end.4.1294 ]
  call void @__free_recursive(ptr %t1279)
  br label %case.end.4.1236
case.end.4.1236:
  br label %case.join.1232
case.default.1231:
  unreachable
case.join.1232:
  %t1301 = phi ptr [ %t1227, %case.end.3.1234 ], [ %t1300, %case.end.4.1236 ]
  call void @__free_recursive(ptr %t1227)
  br label %join.end.1302
join.end.1302:
  br label %join.after.1165
join.after.1165:
  %t1303 = phi ptr [ %t1216, %join.val.1220 ], [ %t1301, %join.end.1302 ]
  br label %case.end.4.1163
case.end.4.1163:
  br label %case.join.1159
case.default.1158:
  unreachable
case.join.1159:
  %t1304 = phi ptr [ %t1154, %case.end.3.1161 ], [ %t1303, %case.end.4.1163 ]
  call void @__free_recursive(ptr %t1154)
  br label %join.end.1305
join.end.1305:
  br label %join.after.1092
join.after.1092:
  %t1306 = phi ptr [ %t1143, %join.val.1147 ], [ %t1304, %join.end.1305 ]
  br label %case.end.4.1090
case.end.4.1090:
  br label %case.join.1086
case.default.1085:
  unreachable
case.join.1086:
  %t1307 = phi ptr [ %t1081, %case.end.3.1088 ], [ %t1306, %case.end.4.1090 ]
  call void @__free_recursive(ptr %t1081)
  br label %join.end.1308
join.end.1308:
  br label %join.after.1019
join.after.1019:
  %t1309 = phi ptr [ %t1070, %join.val.1074 ], [ %t1307, %join.end.1308 ]
  br label %case.end.4.1017
case.end.4.1017:
  br label %case.join.1013
case.default.1012:
  unreachable
case.join.1013:
  %t1310 = phi ptr [ %t1008, %case.end.3.1015 ], [ %t1309, %case.end.4.1017 ]
  call void @__free_recursive(ptr %t1008)
  br label %join.end.1311
join.end.1311:
  br label %join.after.962
join.after.962:
  %t1312 = phi ptr [ %t997, %join.val.1001 ], [ %t1310, %join.end.1311 ]
  br label %case.end.4.960
case.end.4.960:
  br label %case.join.956
case.default.955:
  unreachable
case.join.956:
  %t1313 = phi ptr [ %t951, %case.end.3.958 ], [ %t1312, %case.end.4.960 ]
  call void @__free_recursive(ptr %t951)
  br label %join.end.1314
join.end.1314:
  br label %join.after.905
join.after.905:
  %t1315 = phi ptr [ %t940, %join.val.944 ], [ %t1313, %join.end.1314 ]
  br label %case.end.4.903
case.end.4.903:
  br label %case.join.899
case.default.898:
  unreachable
case.join.899:
  %t1316 = phi ptr [ %t894, %case.end.3.901 ], [ %t1315, %case.end.4.903 ]
  call void @__free_recursive(ptr %t894)
  br label %join.end.1317
join.end.1317:
  br label %join.after.860
join.after.860:
  %t1318 = phi ptr [ %t883, %join.val.887 ], [ %t1316, %join.end.1317 ]
  br label %case.end.4.858
case.end.4.858:
  br label %case.join.854
case.default.853:
  unreachable
case.join.854:
  %t1319 = phi ptr [ %t849, %case.end.3.856 ], [ %t1318, %case.end.4.858 ]
  call void @__free_recursive(ptr %t849)
  br label %join.end.1320
join.end.1320:
  br label %join.after.815
join.after.815:
  %t1321 = phi ptr [ %t838, %join.val.842 ], [ %t1319, %join.end.1320 ]
  br label %case.end.4.813
case.end.4.813:
  br label %case.join.809
case.default.808:
  unreachable
case.join.809:
  %t1322 = phi ptr [ %t804, %case.end.3.811 ], [ %t1321, %case.end.4.813 ]
  call void @__free_recursive(ptr %t804)
  br label %join.end.1323
join.end.1323:
  br label %join.after.746
join.after.746:
  %t1324 = phi ptr [ %t793, %join.val.797 ], [ %t1322, %join.end.1323 ]
  br label %case.end.4.744
case.end.4.744:
  br label %case.join.740
case.default.739:
  unreachable
case.join.740:
  %t1325 = phi ptr [ %t735, %case.end.3.742 ], [ %t1324, %case.end.4.744 ]
  call void @__free_recursive(ptr %t735)
  br label %join.end.1326
join.end.1326:
  br label %join.after.677
join.after.677:
  %t1327 = phi ptr [ %t724, %join.val.728 ], [ %t1325, %join.end.1326 ]
  br label %case.end.4.675
case.end.4.675:
  br label %case.join.671
case.default.670:
  unreachable
case.join.671:
  %t1328 = phi ptr [ %t666, %case.end.3.673 ], [ %t1327, %case.end.4.675 ]
  call void @__free_recursive(ptr %t666)
  br label %join.end.1329
join.end.1329:
  br label %join.after.608
join.after.608:
  %t1330 = phi ptr [ %t655, %join.val.659 ], [ %t1328, %join.end.1329 ]
  br label %case.end.4.606
case.end.4.606:
  br label %case.join.602
case.default.601:
  unreachable
case.join.602:
  %t1331 = phi ptr [ %t597, %case.end.3.604 ], [ %t1330, %case.end.4.606 ]
  call void @__free_recursive(ptr %t597)
  br label %join.end.1332
join.end.1332:
  br label %join.after.539
join.after.539:
  %t1333 = phi ptr [ %t586, %join.val.590 ], [ %t1331, %join.end.1332 ]
  br label %case.end.4.537
case.end.4.537:
  br label %case.join.533
case.default.532:
  unreachable
case.join.533:
  %t1334 = phi ptr [ %t528, %case.end.3.535 ], [ %t1333, %case.end.4.537 ]
  call void @__free_recursive(ptr %t528)
  br label %join.end.1335
join.end.1335:
  br label %join.after.482
join.after.482:
  %t1336 = phi ptr [ %t517, %join.val.521 ], [ %t1334, %join.end.1335 ]
  br label %case.end.4.480
case.end.4.480:
  br label %case.join.476
case.default.475:
  unreachable
case.join.476:
  %t1337 = phi ptr [ %t471, %case.end.3.478 ], [ %t1336, %case.end.4.480 ]
  call void @__free_recursive(ptr %t471)
  br label %join.end.1338
join.end.1338:
  br label %join.after.425
join.after.425:
  %t1339 = phi ptr [ %t460, %join.val.464 ], [ %t1337, %join.end.1338 ]
  br label %case.end.4.423
case.end.4.423:
  br label %case.join.419
case.default.418:
  unreachable
case.join.419:
  %t1340 = phi ptr [ %t414, %case.end.3.421 ], [ %t1339, %case.end.4.423 ]
  call void @__free_recursive(ptr %t414)
  br label %join.end.1341
join.end.1341:
  br label %join.after.378
join.after.378:
  %t1342 = phi ptr [ %t403, %join.val.407 ], [ %t1340, %join.end.1341 ]
  br label %case.end.4.376
case.end.4.376:
  br label %case.join.372
case.default.371:
  unreachable
case.join.372:
  %t1343 = phi ptr [ %t367, %case.end.3.374 ], [ %t1342, %case.end.4.376 ]
  call void @__free_recursive(ptr %t367)
  br label %join.end.1344
join.end.1344:
  br label %join.after.319
join.after.319:
  %t1345 = phi ptr [ %t356, %join.val.360 ], [ %t1343, %join.end.1344 ]
  br label %case.end.4.317
case.end.4.317:
  br label %case.join.313
case.default.312:
  unreachable
case.join.313:
  %t1346 = phi ptr [ %t308, %case.end.3.315 ], [ %t1345, %case.end.4.317 ]
  call void @__free_recursive(ptr %t308)
  br label %join.end.1347
join.end.1347:
  br label %join.after.260
join.after.260:
  %t1348 = phi ptr [ %t297, %join.val.301 ], [ %t1346, %join.end.1347 ]
  br label %case.end.4.258
case.end.4.258:
  br label %case.join.254
case.default.253:
  unreachable
case.join.254:
  %t1349 = phi ptr [ %t249, %case.end.3.256 ], [ %t1348, %case.end.4.258 ]
  call void @__free_recursive(ptr %t249)
  br label %join.end.1350
join.end.1350:
  br label %join.after.201
join.after.201:
  %t1351 = phi ptr [ %t238, %join.val.242 ], [ %t1349, %join.end.1350 ]
  br label %case.end.4.199
case.end.4.199:
  br label %case.join.195
case.default.194:
  unreachable
case.join.195:
  %t1352 = phi ptr [ %t190, %case.end.3.197 ], [ %t1351, %case.end.4.199 ]
  call void @__free_recursive(ptr %t190)
  br label %join.end.1353
join.end.1353:
  br label %join.after.166
join.after.166:
  %t1354 = phi ptr [ %t179, %join.val.183 ], [ %t1352, %join.end.1353 ]
  br label %case.end.4.164
case.end.4.164:
  br label %case.join.160
case.default.159:
  unreachable
case.join.160:
  %t1355 = phi ptr [ %t155, %case.end.3.162 ], [ %t1354, %case.end.4.164 ]
  call void @__free_recursive(ptr %t155)
  br label %join.end.1356
join.end.1356:
  br label %join.after.121
join.after.121:
  %t1357 = phi ptr [ %t144, %join.val.148 ], [ %t1355, %join.end.1356 ]
  br label %case.end.4.119
case.end.4.119:
  br label %case.join.115
case.default.114:
  unreachable
case.join.115:
  %t1358 = phi ptr [ %t110, %case.end.3.117 ], [ %t1357, %case.end.4.119 ]
  call void @__free_recursive(ptr %t110)
  br label %join.end.1359
join.end.1359:
  br label %join.after.76
join.after.76:
  %t1360 = phi ptr [ %t99, %join.val.103 ], [ %t1358, %join.end.1359 ]
  br label %case.end.4.74
case.end.4.74:
  br label %case.join.70
case.default.69:
  unreachable
case.join.70:
  %t1361 = phi ptr [ %t65, %case.end.3.72 ], [ %t1360, %case.end.4.74 ]
  call void @__free_recursive(ptr %t65)
  br label %join.end.1362
join.end.1362:
  br label %join.after.33
join.after.33:
  %t1363 = phi ptr [ %t56, %join.val.60 ], [ %t1361, %join.end.1362 ]
  br label %case.end.4.29
case.end.4.29:
  br label %case.join.19
case.default.18:
  unreachable
case.join.19:
  %t1364 = phi ptr [ %t24, %case.end.3.21 ], [ %t1363, %case.end.4.29 ]
  call void @__free_recursive(ptr %t14)
  ret ptr %t1364
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
  %t26 = call ptr @v__cps__df_andThenIO_18(ptr %t22, ptr %t23)
  %t27 = call ptr @__alloc(i64 8, i32 0)
  %t28 = inttoptr i64 28 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  %t30 = call ptr @v__cps__df_handleErrorIO_14(ptr %t26, ptr %t27)
  ret ptr %t30
}

define internal ptr @v__cps__df_handleErrorIO_14(ptr %v_io, ptr %v__k) {
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
  %t12 = call ptr @v__apply__df_handleErrorIO_14(ptr %t6, ptr %t5)
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
  store ptr getelementptr inbounds (i8, ptr @.str.31, i64 12), ptr %t17
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
  %t26 = call ptr @v__apply__df_handleErrorIO_14(ptr %t6, ptr %t14)
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
  call void @__free_recursive(ptr %t6)
  store ptr %t31, ptr %t3
  store ptr %t51, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t52 = load ptr, ptr %t2
  ret ptr %t52
}

define internal ptr @v__apply__df_handleErrorIO_14(ptr %v__k, ptr %v__x) {
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
  call void @__free_recursive(ptr %t6)
  store ptr %t14, ptr %t3
  store ptr %t5, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t23 = load ptr, ptr %t2
  ret ptr %t23
}

define internal ptr @v__cps__df_andThenIO_18(ptr %v_io, ptr %v__k) {
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
  %t26 = call ptr @v__apply__df_andThenIO_18(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t26, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.27:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t28 = call ptr @v__apply__df_andThenIO_18(ptr %t6, ptr %t5)
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
  call void @__free_recursive(ptr %t6)
  store ptr %t33, ptr %t3
  store ptr %t53, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t54 = load ptr, ptr %t2
  ret ptr %t54
}

define internal ptr @v__apply__df_andThenIO_18(ptr %v__k, ptr %v__x) {
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
  call void @__free_recursive(ptr %t6)
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
