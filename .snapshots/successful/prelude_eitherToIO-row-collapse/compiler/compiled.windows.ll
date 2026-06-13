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
@.str.2 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"nevOk" }
@.str.3 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"ErrA" }
@.str.4 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"First" }
@.str.5 = private unnamed_addr constant {i32, i32, i32, i32, i32, [6 x i8]} { i32 0, i32 0, i32 0, i32 6, i32 6, [6 x i8] c"Second" }
@.str.6 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"ErrB" }
@.str.7 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"\0A" }
@.str.8 = private unnamed_addr constant {i32, i32, i32, i32, i32, [1 x i8]} { i32 0, i32 0, i32 0, i32 1, i32 1, [1 x i8] c"=" }
@.str.9 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"wOk" }
@.str.10 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"wE3" }
@.str.11 = private unnamed_addr constant {i32, i32, i32, i32, i32, [6 x i8]} { i32 0, i32 0, i32 0, i32 6, i32 6, [6 x i8] c"wE2str" }
@.str.12 = private unnamed_addr constant {i32, i32, i32, i32, i32, [3 x i8]} { i32 0, i32 0, i32 0, i32 3, i32 3, [3 x i8] c"wE1" }
@.str.13 = private unnamed_addr constant {i32, i32, i32, i32, i32, [11 x i8]} { i32 0, i32 0, i32 0, i32 11, i32 11, [11 x i8] c"idem2Second" }
@.str.14 = private unnamed_addr constant {i32, i32, i32, i32, i32, [10 x i8]} { i32 0, i32 0, i32 0, i32 10, i32 10, [10 x i8] c"idem2First" }
@.str.15 = private unnamed_addr constant {i32, i32, i32, i32, i32, [6 x i8]} { i32 0, i32 0, i32 0, i32 6, i32 6, [6 x i8] c"idemE2" }
@.str.16 = private unnamed_addr constant {i32, i32, i32, i32, i32, [6 x i8]} { i32 0, i32 0, i32 0, i32 6, i32 6, [6 x i8] c"idemE1" }
@.str.17 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"twoOk" }
@.str.18 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"twoE2" }
@.str.19 = private unnamed_addr constant {i32, i32, i32, i32, i32, [9 x i8]} { i32 0, i32 0, i32 0, i32 9, i32 9, [9 x i8] c"twoSecond" }
@.str.20 = private unnamed_addr constant {i32, i32, i32, i32, i32, [8 x i8]} { i32 0, i32 0, i32 0, i32 8, i32 8, [8 x i8] c"twoFirst" }
@.str.21 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"abE2" }
@.str.22 = private unnamed_addr constant {i32, i32, i32, i32, i32, [4 x i8]} { i32 0, i32 0, i32 0, i32 4, i32 4, [4 x i8] c"abE1" }
@.str.23 = private unnamed_addr constant {i32, i32, i32, i32, i32, [7 x i8]} { i32 0, i32 0, i32 0, i32 7, i32 7, [7 x i8] c"strIdem" }
@.str.24 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"strE2" }
@.str.25 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"strE1" }
@.str.26 = private unnamed_addr constant {i32, i32, i32, i32, i32, [5 x i8]} { i32 0, i32 0, i32 0, i32 5, i32 5, [5 x i8] c"strOk" }
@.str.27 = private unnamed_addr constant {i32, i32, i32, i32, i32, [9 x i8]} { i32 0, i32 0, i32 0, i32 9, i32 9, [9 x i8] c"pureNever" }
@.str.28 = private unnamed_addr constant {i32, i32, i32, i32, i32, [10 x i8]} { i32 0, i32 0, i32 0, i32 10, i32 10, [10 x i8] c"nevRightE1" }
@.str.29 = private unnamed_addr constant {i32, i32, i32, i32, i32, [10 x i8]} { i32 0, i32 0, i32 0, i32 10, i32 10, [10 x i8] c"nevRightOk" }
@.str.30 = private unnamed_addr constant {i32, i32, i32, i32, i32, [7 x i8]} { i32 0, i32 0, i32 0, i32 7, i32 7, [7 x i8] c"nevFail" }

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

define internal ptr @v_main() {
  %t0 = call ptr @__alloc(i64 24, i32 2)
  %t1 = inttoptr i64 7 to ptr
  %t2 = getelementptr ptr, ptr %t0, i32 0
  store ptr %t1, ptr %t2
  %t3 = getelementptr ptr, ptr %t0, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.2, i64 12), ptr %t3
  %t4 = call ptr @__alloc(i64 16, i32 1)
  %t5 = inttoptr i64 5 to ptr
  %t6 = getelementptr ptr, ptr %t4, i32 0
  store ptr %t5, ptr %t6
  %t7 = call ptr @__alloc(i64 8, i32 0)
  %t8 = inttoptr i64 0 to ptr
  %t9 = getelementptr ptr, ptr %t7, i32 0
  store ptr %t8, ptr %t9
  %t10 = getelementptr ptr, ptr %t4, i32 1
  store ptr %t7, ptr %t10
  %t11 = getelementptr ptr, ptr %t0, i32 2
  store ptr %t4, ptr %t11
  %t12 = call ptr @__alloc(i64 8, i32 0)
  %t13 = inttoptr i64 58 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = call ptr @v__cps__df_andThenIO_74(ptr %t0, ptr %t12)
  %t16 = call ptr @v_nevOk()
  %t17 = getelementptr ptr, ptr %t16, i32 0
  %t18 = load ptr, ptr %t17
  %t19 = ptrtoint ptr %t18 to i64
  switch i64 %t19, label %case.default.20 [ i64 3, label %case.arm.3.22 i64 4, label %case.arm.4.30 ]
case.arm.3.22:
  %t24 = call ptr @__alloc(i64 16, i32 1)
  %t25 = inttoptr i64 6 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = getelementptr ptr, ptr %t16, i32 1
  %t28 = load ptr, ptr %t27
  call void @__inc_ref(ptr %t28)
  %t29 = getelementptr ptr, ptr %t24, i32 1
  store ptr %t28, ptr %t29
  br label %case.end.3.23
case.end.3.23:
  br label %case.join.21
case.arm.4.30:
  %t32 = call ptr @__alloc(i64 16, i32 1)
  %t33 = inttoptr i64 5 to ptr
  %t34 = getelementptr ptr, ptr %t32, i32 0
  store ptr %t33, ptr %t34
  %t35 = getelementptr ptr, ptr %t16, i32 1
  %t36 = load ptr, ptr %t35
  call void @__inc_ref(ptr %t36)
  %t37 = getelementptr ptr, ptr %t32, i32 1
  store ptr %t36, ptr %t37
  br label %case.end.4.31
case.end.4.31:
  br label %case.join.21
case.default.20:
  unreachable
case.join.21:
  %t38 = phi ptr [ %t24, %case.end.3.23 ], [ %t32, %case.end.4.31 ]
  %t39 = call ptr @__alloc(i64 8, i32 0)
  %t40 = inttoptr i64 32 to ptr
  %t41 = getelementptr ptr, ptr %t39, i32 0
  store ptr %t40, ptr %t41
  %t42 = call ptr @v__cps__df_mapIO_22(ptr %t38, ptr %t39)
  %t43 = call ptr @__alloc(i64 8, i32 0)
  %t44 = inttoptr i64 30 to ptr
  %t45 = getelementptr ptr, ptr %t43, i32 0
  store ptr %t44, ptr %t45
  %t46 = call ptr @v__cps__df_andThenIO_18(ptr %t42, ptr %t43)
  %t47 = call ptr @__alloc(i64 8, i32 0)
  %t48 = inttoptr i64 28 to ptr
  %t49 = getelementptr ptr, ptr %t47, i32 0
  store ptr %t48, ptr %t49
  %t50 = call ptr @v__cps__df_handleErrorIO_14(ptr %t46, ptr %t47)
  call void @__free_recursive(ptr %t16)
  %t51 = call ptr @__alloc(i64 8, i32 0)
  %t52 = inttoptr i64 56 to ptr
  %t53 = getelementptr ptr, ptr %t51, i32 0
  store ptr %t52, ptr %t53
  %t54 = call ptr @v__cps__df_andThenIO_70(ptr %t15, ptr %t50, ptr %t51)
  %t55 = call ptr @__alloc(i64 8, i32 0)
  %t56 = inttoptr i64 54 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  %t58 = call ptr @v__cps__df_andThenIO_66(ptr %t54, ptr %t55)
  %t59 = call ptr @__alloc(i64 8, i32 0)
  %t60 = inttoptr i64 102 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  %t62 = call ptr @v__cps__df_andThenIO_162(ptr %t58, ptr %t59)
  %t63 = call ptr @__alloc(i64 8, i32 0)
  %t64 = inttoptr i64 100 to ptr
  %t65 = getelementptr ptr, ptr %t63, i32 0
  store ptr %t64, ptr %t65
  %t66 = call ptr @v__cps__df_andThenIO_158(ptr %t62, ptr %t63)
  %t67 = call ptr @__alloc(i64 8, i32 0)
  %t68 = inttoptr i64 98 to ptr
  %t69 = getelementptr ptr, ptr %t67, i32 0
  store ptr %t68, ptr %t69
  %t70 = call ptr @v__cps__df_andThenIO_154(ptr %t66, ptr %t67)
  %t71 = call ptr @__alloc(i64 8, i32 0)
  %t72 = inttoptr i64 96 to ptr
  %t73 = getelementptr ptr, ptr %t71, i32 0
  store ptr %t72, ptr %t73
  %t74 = call ptr @v__cps__df_andThenIO_150(ptr %t70, ptr %t71)
  %t75 = call ptr @__alloc(i64 8, i32 0)
  %t76 = inttoptr i64 94 to ptr
  %t77 = getelementptr ptr, ptr %t75, i32 0
  store ptr %t76, ptr %t77
  %t78 = call ptr @v__cps__df_andThenIO_146(ptr %t74, ptr %t75)
  %t79 = call ptr @__alloc(i64 8, i32 0)
  %t80 = inttoptr i64 92 to ptr
  %t81 = getelementptr ptr, ptr %t79, i32 0
  store ptr %t80, ptr %t81
  %t82 = call ptr @v__cps__df_andThenIO_142(ptr %t78, ptr %t79)
  %t83 = call ptr @__alloc(i64 8, i32 0)
  %t84 = inttoptr i64 90 to ptr
  %t85 = getelementptr ptr, ptr %t83, i32 0
  store ptr %t84, ptr %t85
  %t86 = call ptr @v__cps__df_andThenIO_138(ptr %t82, ptr %t83)
  %t87 = call ptr @__alloc(i64 8, i32 0)
  %t88 = inttoptr i64 88 to ptr
  %t89 = getelementptr ptr, ptr %t87, i32 0
  store ptr %t88, ptr %t89
  %t90 = call ptr @v__cps__df_andThenIO_134(ptr %t86, ptr %t87)
  %t91 = call ptr @__alloc(i64 8, i32 0)
  %t92 = inttoptr i64 86 to ptr
  %t93 = getelementptr ptr, ptr %t91, i32 0
  store ptr %t92, ptr %t93
  %t94 = call ptr @v__cps__df_andThenIO_130(ptr %t90, ptr %t91)
  %t95 = call ptr @__alloc(i64 8, i32 0)
  %t96 = inttoptr i64 84 to ptr
  %t97 = getelementptr ptr, ptr %t95, i32 0
  store ptr %t96, ptr %t97
  %t98 = call ptr @v__cps__df_andThenIO_126(ptr %t94, ptr %t95)
  %t99 = call ptr @__alloc(i64 8, i32 0)
  %t100 = inttoptr i64 82 to ptr
  %t101 = getelementptr ptr, ptr %t99, i32 0
  store ptr %t100, ptr %t101
  %t102 = call ptr @v__cps__df_andThenIO_122(ptr %t98, ptr %t99)
  %t103 = call ptr @__alloc(i64 8, i32 0)
  %t104 = inttoptr i64 80 to ptr
  %t105 = getelementptr ptr, ptr %t103, i32 0
  store ptr %t104, ptr %t105
  %t106 = call ptr @v__cps__df_andThenIO_118(ptr %t102, ptr %t103)
  %t107 = call ptr @__alloc(i64 8, i32 0)
  %t108 = inttoptr i64 78 to ptr
  %t109 = getelementptr ptr, ptr %t107, i32 0
  store ptr %t108, ptr %t109
  %t110 = call ptr @v__cps__df_andThenIO_114(ptr %t106, ptr %t107)
  %t111 = call ptr @__alloc(i64 8, i32 0)
  %t112 = inttoptr i64 76 to ptr
  %t113 = getelementptr ptr, ptr %t111, i32 0
  store ptr %t112, ptr %t113
  %t114 = call ptr @v__cps__df_andThenIO_110(ptr %t110, ptr %t111)
  %t115 = call ptr @__alloc(i64 8, i32 0)
  %t116 = inttoptr i64 74 to ptr
  %t117 = getelementptr ptr, ptr %t115, i32 0
  store ptr %t116, ptr %t117
  %t118 = call ptr @v__cps__df_andThenIO_106(ptr %t114, ptr %t115)
  %t119 = call ptr @__alloc(i64 8, i32 0)
  %t120 = inttoptr i64 72 to ptr
  %t121 = getelementptr ptr, ptr %t119, i32 0
  store ptr %t120, ptr %t121
  %t122 = call ptr @v__cps__df_andThenIO_102(ptr %t118, ptr %t119)
  %t123 = call ptr @__alloc(i64 8, i32 0)
  %t124 = inttoptr i64 70 to ptr
  %t125 = getelementptr ptr, ptr %t123, i32 0
  store ptr %t124, ptr %t125
  %t126 = call ptr @v__cps__df_andThenIO_98(ptr %t122, ptr %t123)
  %t127 = call ptr @__alloc(i64 8, i32 0)
  %t128 = inttoptr i64 68 to ptr
  %t129 = getelementptr ptr, ptr %t127, i32 0
  store ptr %t128, ptr %t129
  %t130 = call ptr @v__cps__df_andThenIO_94(ptr %t126, ptr %t127)
  %t131 = call ptr @__alloc(i64 8, i32 0)
  %t132 = inttoptr i64 66 to ptr
  %t133 = getelementptr ptr, ptr %t131, i32 0
  store ptr %t132, ptr %t133
  %t134 = call ptr @v__cps__df_andThenIO_90(ptr %t130, ptr %t131)
  %t135 = call ptr @__alloc(i64 8, i32 0)
  %t136 = inttoptr i64 64 to ptr
  %t137 = getelementptr ptr, ptr %t135, i32 0
  store ptr %t136, ptr %t137
  %t138 = call ptr @v__cps__df_andThenIO_86(ptr %t134, ptr %t135)
  %t139 = call ptr @__alloc(i64 8, i32 0)
  %t140 = inttoptr i64 62 to ptr
  %t141 = getelementptr ptr, ptr %t139, i32 0
  store ptr %t140, ptr %t141
  %t142 = call ptr @v__cps__df_andThenIO_82(ptr %t138, ptr %t139)
  %t143 = call ptr @__alloc(i64 8, i32 0)
  %t144 = inttoptr i64 60 to ptr
  %t145 = getelementptr ptr, ptr %t143, i32 0
  store ptr %t144, ptr %t145
  %t146 = call ptr @v__cps__df_andThenIO_78(ptr %t142, ptr %t143)
  ret ptr %t146
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
  store ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t17
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

define internal ptr @v__cps__df_mapIO_22(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.20 i64 7, label %tco.case.arm.7.22 ]
tco.case.arm.5.11:
  %t12 = getelementptr ptr, ptr %t5, i32 1
  %t13 = load ptr, ptr %t12
  call void @__inc_ref(ptr %t13)
  call void @__inc_ref(ptr %t6)
  %t14 = call ptr @__alloc(i64 16, i32 1)
  %t15 = inttoptr i64 5 to ptr
  %t16 = getelementptr ptr, ptr %t14, i32 0
  store ptr %t15, ptr %t16
  call void @__inc_ref(ptr %t13)
  %t17 = call ptr @__showInt32(ptr %t13)
  %t18 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t17, ptr %t18
  %t19 = call ptr @v__apply__df_mapIO_22(ptr %t6, ptr %t14)
  call void @__free_recursive(ptr %t13)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t19, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.20:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t21 = call ptr @v__apply__df_mapIO_22(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t21, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.22:
  %t23 = getelementptr ptr, ptr %t5, i32 1
  %t24 = load ptr, ptr %t23
  %t25 = getelementptr ptr, ptr %t5, i32 2
  %t26 = load ptr, ptr %t25
  call void @__inc_ref(ptr %t26)
  %t33 = getelementptr i8, ptr %t5, i64 -8
  %t34 = load i32, ptr %t33
  %t35 = icmp eq i32 %t34, 1
  br i1 %t35, label %reuse.in_place.36, label %reuse.copy.37
reuse.in_place.36:
  %t27 = getelementptr ptr, ptr %t5, i32 2
  %t28 = load ptr, ptr %t27
  call void @__free_recursive(ptr %t28)
  %t31 = inttoptr i64 33 to ptr
  %t32 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t31, ptr %t32
  call void @__inc_ref(ptr %t6)
  %t29 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t29
  %t30 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t24, ptr %t30
  br label %reuse.in_place.end.39
reuse.in_place.end.39:
  br label %reuse.join.38
reuse.copy.37:
  %t41 = call ptr @__alloc(i64 24, i32 2)
  %t42 = inttoptr i64 33 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  call void @__inc_ref(ptr %t6)
  %t44 = getelementptr ptr, ptr %t41, i32 1
  store ptr %t6, ptr %t44
  call void @__inc_ref(ptr %t24)
  %t45 = getelementptr ptr, ptr %t41, i32 2
  store ptr %t24, ptr %t45
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.40
reuse.copy.end.40:
  br label %reuse.join.38
reuse.join.38:
  %t46 = phi ptr [ %t5, %reuse.in_place.end.39 ], [ %t41, %reuse.copy.end.40 ]
  call void @__inc_ref(ptr %t26)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t26)
  store ptr %t26, ptr %t3
  store ptr %t46, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t47 = load ptr, ptr %t2
  ret ptr %t47
}

define internal ptr @v__apply__df_mapIO_22(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 32, label %tco.case.arm.32.11 i64 33, label %tco.case.arm.33.12 ]
tco.case.arm.32.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.33.12:
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

define internal ptr @v__cps__df_handleErrorIO_26(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.13 i64 7, label %tco.case.arm.7.51 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t12 = call ptr @v__apply__df_handleErrorIO_26(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t12, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.13:
  call void @__inc_ref(ptr %t6)
  %t14 = getelementptr ptr, ptr %t5, i32 1
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  %t16 = getelementptr ptr, ptr %t15, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %case.default.19 [ i64 26, label %case.arm.26.21 i64 27, label %case.arm.27.35 ]
case.arm.26.21:
  %t23 = call ptr @__alloc(i64 24, i32 2)
  %t24 = inttoptr i64 7 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  %t26 = getelementptr ptr, ptr %t23, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t26
  %t27 = call ptr @__alloc(i64 16, i32 1)
  %t28 = inttoptr i64 5 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  %t30 = call ptr @__alloc(i64 8, i32 0)
  %t31 = inttoptr i64 0 to ptr
  %t32 = getelementptr ptr, ptr %t30, i32 0
  store ptr %t31, ptr %t32
  %t33 = getelementptr ptr, ptr %t27, i32 1
  store ptr %t30, ptr %t33
  %t34 = getelementptr ptr, ptr %t23, i32 2
  store ptr %t27, ptr %t34
  br label %case.end.26.22
case.end.26.22:
  br label %case.join.20
case.arm.27.35:
  %t37 = call ptr @__alloc(i64 24, i32 2)
  %t38 = inttoptr i64 7 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = getelementptr ptr, ptr %t37, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.5, i64 12), ptr %t40
  %t41 = call ptr @__alloc(i64 16, i32 1)
  %t42 = inttoptr i64 5 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = call ptr @__alloc(i64 8, i32 0)
  %t45 = inttoptr i64 0 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  %t47 = getelementptr ptr, ptr %t41, i32 1
  store ptr %t44, ptr %t47
  %t48 = getelementptr ptr, ptr %t37, i32 2
  store ptr %t41, ptr %t48
  br label %case.end.27.36
case.end.27.36:
  br label %case.join.20
case.default.19:
  unreachable
case.join.20:
  %t49 = phi ptr [ %t23, %case.end.26.22 ], [ %t37, %case.end.27.36 ]
  call void @__free_recursive(ptr %t15)
  %t50 = call ptr @v__apply__df_handleErrorIO_26(ptr %t6, ptr %t49)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t50, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.51:
  %t52 = getelementptr ptr, ptr %t5, i32 1
  %t53 = load ptr, ptr %t52
  %t54 = getelementptr ptr, ptr %t5, i32 2
  %t55 = load ptr, ptr %t54
  call void @__inc_ref(ptr %t55)
  %t62 = getelementptr i8, ptr %t5, i64 -8
  %t63 = load i32, ptr %t62
  %t64 = icmp eq i32 %t63, 1
  br i1 %t64, label %reuse.in_place.65, label %reuse.copy.66
reuse.in_place.65:
  %t56 = getelementptr ptr, ptr %t5, i32 2
  %t57 = load ptr, ptr %t56
  call void @__free_recursive(ptr %t57)
  %t60 = inttoptr i64 35 to ptr
  %t61 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t60, ptr %t61
  call void @__inc_ref(ptr %t6)
  %t58 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t58
  %t59 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t53, ptr %t59
  br label %reuse.in_place.end.68
reuse.in_place.end.68:
  br label %reuse.join.67
reuse.copy.66:
  %t70 = call ptr @__alloc(i64 24, i32 2)
  %t71 = inttoptr i64 35 to ptr
  %t72 = getelementptr ptr, ptr %t70, i32 0
  store ptr %t71, ptr %t72
  call void @__inc_ref(ptr %t6)
  %t73 = getelementptr ptr, ptr %t70, i32 1
  store ptr %t6, ptr %t73
  call void @__inc_ref(ptr %t53)
  %t74 = getelementptr ptr, ptr %t70, i32 2
  store ptr %t53, ptr %t74
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.69
reuse.copy.end.69:
  br label %reuse.join.67
reuse.join.67:
  %t75 = phi ptr [ %t5, %reuse.in_place.end.68 ], [ %t70, %reuse.copy.end.69 ]
  call void @__inc_ref(ptr %t55)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t55)
  store ptr %t55, ptr %t3
  store ptr %t75, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t76 = load ptr, ptr %t2
  ret ptr %t76
}

define internal ptr @v__apply__df_handleErrorIO_26(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 34, label %tco.case.arm.34.11 i64 35, label %tco.case.arm.35.12 ]
tco.case.arm.34.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.35.12:
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

define internal ptr @v__cps__df_handleErrorIO_30(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.13 i64 7, label %tco.case.arm.7.29 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t12 = call ptr @v__apply__df_handleErrorIO_30(ptr %t6, ptr %t5)
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
  %t17 = getelementptr ptr, ptr %t5, i32 1
  %t18 = load ptr, ptr %t17
  call void @__inc_ref(ptr %t18)
  %t19 = getelementptr ptr, ptr %t14, i32 1
  store ptr %t18, ptr %t19
  %t20 = call ptr @__alloc(i64 16, i32 1)
  %t21 = inttoptr i64 5 to ptr
  %t22 = getelementptr ptr, ptr %t20, i32 0
  store ptr %t21, ptr %t22
  %t23 = call ptr @__alloc(i64 8, i32 0)
  %t24 = inttoptr i64 0 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  %t26 = getelementptr ptr, ptr %t20, i32 1
  store ptr %t23, ptr %t26
  %t27 = getelementptr ptr, ptr %t14, i32 2
  store ptr %t20, ptr %t27
  %t28 = call ptr @v__apply__df_handleErrorIO_30(ptr %t6, ptr %t14)
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
  %t38 = inttoptr i64 37 to ptr
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
  %t49 = inttoptr i64 37 to ptr
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

define internal ptr @v__apply__df_handleErrorIO_30(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 36, label %tco.case.arm.36.11 i64 37, label %tco.case.arm.37.12 ]
tco.case.arm.36.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.37.12:
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

define internal ptr @v__cps__df_handleErrorIO_34(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.13 i64 7, label %tco.case.arm.7.53 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t12 = call ptr @v__apply__df_handleErrorIO_34(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t12, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.13:
  call void @__inc_ref(ptr %t6)
  %t14 = getelementptr ptr, ptr %t5, i32 1
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  %t16 = getelementptr ptr, ptr %t15, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %case.default.19 [ i64 1615808600, label %case.arm.1615808600.21 i64 2252990199, label %case.arm.2252990199.37 ]
case.arm.1615808600.21:
  %t23 = call ptr @__alloc(i64 24, i32 2)
  %t24 = inttoptr i64 7 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  %t26 = getelementptr ptr, ptr %t15, i32 1
  %t27 = load ptr, ptr %t26
  call void @__inc_ref(ptr %t27)
  %t28 = getelementptr ptr, ptr %t23, i32 1
  store ptr %t27, ptr %t28
  %t29 = call ptr @__alloc(i64 16, i32 1)
  %t30 = inttoptr i64 5 to ptr
  %t31 = getelementptr ptr, ptr %t29, i32 0
  store ptr %t30, ptr %t31
  %t32 = call ptr @__alloc(i64 8, i32 0)
  %t33 = inttoptr i64 0 to ptr
  %t34 = getelementptr ptr, ptr %t32, i32 0
  store ptr %t33, ptr %t34
  %t35 = getelementptr ptr, ptr %t29, i32 1
  store ptr %t32, ptr %t35
  %t36 = getelementptr ptr, ptr %t23, i32 2
  store ptr %t29, ptr %t36
  br label %case.end.1615808600.22
case.end.1615808600.22:
  br label %case.join.20
case.arm.2252990199.37:
  %t39 = call ptr @__alloc(i64 24, i32 2)
  %t40 = inttoptr i64 7 to ptr
  %t41 = getelementptr ptr, ptr %t39, i32 0
  store ptr %t40, ptr %t41
  %t42 = getelementptr ptr, ptr %t39, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t42
  %t43 = call ptr @__alloc(i64 16, i32 1)
  %t44 = inttoptr i64 5 to ptr
  %t45 = getelementptr ptr, ptr %t43, i32 0
  store ptr %t44, ptr %t45
  %t46 = call ptr @__alloc(i64 8, i32 0)
  %t47 = inttoptr i64 0 to ptr
  %t48 = getelementptr ptr, ptr %t46, i32 0
  store ptr %t47, ptr %t48
  %t49 = getelementptr ptr, ptr %t43, i32 1
  store ptr %t46, ptr %t49
  %t50 = getelementptr ptr, ptr %t39, i32 2
  store ptr %t43, ptr %t50
  br label %case.end.2252990199.38
case.end.2252990199.38:
  br label %case.join.20
case.default.19:
  unreachable
case.join.20:
  %t51 = phi ptr [ %t23, %case.end.1615808600.22 ], [ %t39, %case.end.2252990199.38 ]
  call void @__free_recursive(ptr %t15)
  %t52 = call ptr @v__apply__df_handleErrorIO_34(ptr %t6, ptr %t51)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t52, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.53:
  %t54 = getelementptr ptr, ptr %t5, i32 1
  %t55 = load ptr, ptr %t54
  %t56 = getelementptr ptr, ptr %t5, i32 2
  %t57 = load ptr, ptr %t56
  call void @__inc_ref(ptr %t57)
  %t64 = getelementptr i8, ptr %t5, i64 -8
  %t65 = load i32, ptr %t64
  %t66 = icmp eq i32 %t65, 1
  br i1 %t66, label %reuse.in_place.67, label %reuse.copy.68
reuse.in_place.67:
  %t58 = getelementptr ptr, ptr %t5, i32 2
  %t59 = load ptr, ptr %t58
  call void @__free_recursive(ptr %t59)
  %t62 = inttoptr i64 39 to ptr
  %t63 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t62, ptr %t63
  call void @__inc_ref(ptr %t6)
  %t60 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t60
  %t61 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t55, ptr %t61
  br label %reuse.in_place.end.70
reuse.in_place.end.70:
  br label %reuse.join.69
reuse.copy.68:
  %t72 = call ptr @__alloc(i64 24, i32 2)
  %t73 = inttoptr i64 39 to ptr
  %t74 = getelementptr ptr, ptr %t72, i32 0
  store ptr %t73, ptr %t74
  call void @__inc_ref(ptr %t6)
  %t75 = getelementptr ptr, ptr %t72, i32 1
  store ptr %t6, ptr %t75
  call void @__inc_ref(ptr %t55)
  %t76 = getelementptr ptr, ptr %t72, i32 2
  store ptr %t55, ptr %t76
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.71
reuse.copy.end.71:
  br label %reuse.join.69
reuse.join.69:
  %t77 = phi ptr [ %t5, %reuse.in_place.end.70 ], [ %t72, %reuse.copy.end.71 ]
  call void @__inc_ref(ptr %t57)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t57)
  store ptr %t57, ptr %t3
  store ptr %t77, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t78 = load ptr, ptr %t2
  ret ptr %t78
}

define internal ptr @v__apply__df_handleErrorIO_34(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 38, label %tco.case.arm.38.11 i64 39, label %tco.case.arm.39.12 ]
tco.case.arm.38.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.39.12:
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

define internal ptr @v__cps__df__rowmono_5_andThenIO_38(ptr %v_io, ptr %v__k) {
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
  %t26 = call ptr @v__apply__df__rowmono_5_andThenIO_38(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t26, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.27:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t28 = call ptr @v__apply__df__rowmono_5_andThenIO_38(ptr %t6, ptr %t5)
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
  %t38 = inttoptr i64 41 to ptr
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
  %t49 = inttoptr i64 41 to ptr
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

define internal ptr @v__apply__df__rowmono_5_andThenIO_38(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 40, label %tco.case.arm.40.11 i64 41, label %tco.case.arm.41.12 ]
tco.case.arm.40.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.41.12:
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

define internal ptr @v__cps__df_handleErrorIO_42(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.13 i64 7, label %tco.case.arm.7.51 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t12 = call ptr @v__apply__df_handleErrorIO_42(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t12, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.13:
  call void @__inc_ref(ptr %t6)
  %t14 = getelementptr ptr, ptr %t5, i32 1
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  %t16 = getelementptr ptr, ptr %t15, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %case.default.19 [ i64 2252990199, label %case.arm.2252990199.21 i64 2269767818, label %case.arm.2269767818.35 ]
case.arm.2252990199.21:
  %t23 = call ptr @__alloc(i64 24, i32 2)
  %t24 = inttoptr i64 7 to ptr
  %t25 = getelementptr ptr, ptr %t23, i32 0
  store ptr %t24, ptr %t25
  %t26 = getelementptr ptr, ptr %t23, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t26
  %t27 = call ptr @__alloc(i64 16, i32 1)
  %t28 = inttoptr i64 5 to ptr
  %t29 = getelementptr ptr, ptr %t27, i32 0
  store ptr %t28, ptr %t29
  %t30 = call ptr @__alloc(i64 8, i32 0)
  %t31 = inttoptr i64 0 to ptr
  %t32 = getelementptr ptr, ptr %t30, i32 0
  store ptr %t31, ptr %t32
  %t33 = getelementptr ptr, ptr %t27, i32 1
  store ptr %t30, ptr %t33
  %t34 = getelementptr ptr, ptr %t23, i32 2
  store ptr %t27, ptr %t34
  br label %case.end.2252990199.22
case.end.2252990199.22:
  br label %case.join.20
case.arm.2269767818.35:
  %t37 = call ptr @__alloc(i64 24, i32 2)
  %t38 = inttoptr i64 7 to ptr
  %t39 = getelementptr ptr, ptr %t37, i32 0
  store ptr %t38, ptr %t39
  %t40 = getelementptr ptr, ptr %t37, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.6, i64 12), ptr %t40
  %t41 = call ptr @__alloc(i64 16, i32 1)
  %t42 = inttoptr i64 5 to ptr
  %t43 = getelementptr ptr, ptr %t41, i32 0
  store ptr %t42, ptr %t43
  %t44 = call ptr @__alloc(i64 8, i32 0)
  %t45 = inttoptr i64 0 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  %t47 = getelementptr ptr, ptr %t41, i32 1
  store ptr %t44, ptr %t47
  %t48 = getelementptr ptr, ptr %t37, i32 2
  store ptr %t41, ptr %t48
  br label %case.end.2269767818.36
case.end.2269767818.36:
  br label %case.join.20
case.default.19:
  unreachable
case.join.20:
  %t49 = phi ptr [ %t23, %case.end.2252990199.22 ], [ %t37, %case.end.2269767818.36 ]
  call void @__free_recursive(ptr %t15)
  %t50 = call ptr @v__apply__df_handleErrorIO_42(ptr %t6, ptr %t49)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t50, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.51:
  %t52 = getelementptr ptr, ptr %t5, i32 1
  %t53 = load ptr, ptr %t52
  %t54 = getelementptr ptr, ptr %t5, i32 2
  %t55 = load ptr, ptr %t54
  call void @__inc_ref(ptr %t55)
  %t62 = getelementptr i8, ptr %t5, i64 -8
  %t63 = load i32, ptr %t62
  %t64 = icmp eq i32 %t63, 1
  br i1 %t64, label %reuse.in_place.65, label %reuse.copy.66
reuse.in_place.65:
  %t56 = getelementptr ptr, ptr %t5, i32 2
  %t57 = load ptr, ptr %t56
  call void @__free_recursive(ptr %t57)
  %t60 = inttoptr i64 43 to ptr
  %t61 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t60, ptr %t61
  call void @__inc_ref(ptr %t6)
  %t58 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t58
  %t59 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t53, ptr %t59
  br label %reuse.in_place.end.68
reuse.in_place.end.68:
  br label %reuse.join.67
reuse.copy.66:
  %t70 = call ptr @__alloc(i64 24, i32 2)
  %t71 = inttoptr i64 43 to ptr
  %t72 = getelementptr ptr, ptr %t70, i32 0
  store ptr %t71, ptr %t72
  call void @__inc_ref(ptr %t6)
  %t73 = getelementptr ptr, ptr %t70, i32 1
  store ptr %t6, ptr %t73
  call void @__inc_ref(ptr %t53)
  %t74 = getelementptr ptr, ptr %t70, i32 2
  store ptr %t53, ptr %t74
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.69
reuse.copy.end.69:
  br label %reuse.join.67
reuse.join.67:
  %t75 = phi ptr [ %t5, %reuse.in_place.end.68 ], [ %t70, %reuse.copy.end.69 ]
  call void @__inc_ref(ptr %t55)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t55)
  store ptr %t55, ptr %t3
  store ptr %t75, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t76 = load ptr, ptr %t2
  ret ptr %t76
}

define internal ptr @v__apply__df_handleErrorIO_42(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 42, label %tco.case.arm.42.11 i64 43, label %tco.case.arm.43.12 ]
tco.case.arm.42.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.43.12:
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

define internal ptr @v__cps__df__rowmono_6_andThenIO_46(ptr %v_io, ptr %v__k) {
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
  %t26 = call ptr @v__apply__df__rowmono_6_andThenIO_46(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t26, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.27:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t28 = call ptr @v__apply__df__rowmono_6_andThenIO_46(ptr %t6, ptr %t5)
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
  %t38 = inttoptr i64 45 to ptr
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
  %t49 = inttoptr i64 45 to ptr
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

define internal ptr @v__apply__df__rowmono_6_andThenIO_46(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 44, label %tco.case.arm.44.11 i64 45, label %tco.case.arm.45.12 ]
tco.case.arm.44.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.45.12:
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

define internal ptr @v__cps__df_handleErrorIO_50(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.13 i64 7, label %tco.case.arm.7.75 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t12 = call ptr @v__apply__df_handleErrorIO_50(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t12, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.13:
  call void @__inc_ref(ptr %t6)
  %t14 = getelementptr ptr, ptr %t5, i32 1
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  %t16 = getelementptr ptr, ptr %t15, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %case.default.19 [ i64 925038822, label %case.arm.925038822.21 i64 2252990199, label %case.arm.2252990199.59 ]
case.arm.925038822.21:
  %t23 = getelementptr ptr, ptr %t15, i32 1
  %t24 = load ptr, ptr %t23
  call void @__inc_ref(ptr %t24)
  %t25 = getelementptr ptr, ptr %t24, i32 0
  %t26 = load ptr, ptr %t25
  %t27 = ptrtoint ptr %t26 to i64
  switch i64 %t27, label %case.default.28 [ i64 26, label %case.arm.26.30 i64 27, label %case.arm.27.44 ]
case.arm.26.30:
  %t32 = call ptr @__alloc(i64 24, i32 2)
  %t33 = inttoptr i64 7 to ptr
  %t34 = getelementptr ptr, ptr %t32, i32 0
  store ptr %t33, ptr %t34
  %t35 = getelementptr ptr, ptr %t32, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t35
  %t36 = call ptr @__alloc(i64 16, i32 1)
  %t37 = inttoptr i64 5 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = call ptr @__alloc(i64 8, i32 0)
  %t40 = inttoptr i64 0 to ptr
  %t41 = getelementptr ptr, ptr %t39, i32 0
  store ptr %t40, ptr %t41
  %t42 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t39, ptr %t42
  %t43 = getelementptr ptr, ptr %t32, i32 2
  store ptr %t36, ptr %t43
  br label %case.end.26.31
case.end.26.31:
  br label %case.join.29
case.arm.27.44:
  %t46 = call ptr @__alloc(i64 24, i32 2)
  %t47 = inttoptr i64 7 to ptr
  %t48 = getelementptr ptr, ptr %t46, i32 0
  store ptr %t47, ptr %t48
  %t49 = getelementptr ptr, ptr %t46, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.5, i64 12), ptr %t49
  %t50 = call ptr @__alloc(i64 16, i32 1)
  %t51 = inttoptr i64 5 to ptr
  %t52 = getelementptr ptr, ptr %t50, i32 0
  store ptr %t51, ptr %t52
  %t53 = call ptr @__alloc(i64 8, i32 0)
  %t54 = inttoptr i64 0 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  %t56 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t53, ptr %t56
  %t57 = getelementptr ptr, ptr %t46, i32 2
  store ptr %t50, ptr %t57
  br label %case.end.27.45
case.end.27.45:
  br label %case.join.29
case.default.28:
  unreachable
case.join.29:
  %t58 = phi ptr [ %t32, %case.end.26.31 ], [ %t46, %case.end.27.45 ]
  call void @__free_recursive(ptr %t24)
  br label %case.end.925038822.22
case.end.925038822.22:
  br label %case.join.20
case.arm.2252990199.59:
  %t61 = call ptr @__alloc(i64 24, i32 2)
  %t62 = inttoptr i64 7 to ptr
  %t63 = getelementptr ptr, ptr %t61, i32 0
  store ptr %t62, ptr %t63
  %t64 = getelementptr ptr, ptr %t61, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t64
  %t65 = call ptr @__alloc(i64 16, i32 1)
  %t66 = inttoptr i64 5 to ptr
  %t67 = getelementptr ptr, ptr %t65, i32 0
  store ptr %t66, ptr %t67
  %t68 = call ptr @__alloc(i64 8, i32 0)
  %t69 = inttoptr i64 0 to ptr
  %t70 = getelementptr ptr, ptr %t68, i32 0
  store ptr %t69, ptr %t70
  %t71 = getelementptr ptr, ptr %t65, i32 1
  store ptr %t68, ptr %t71
  %t72 = getelementptr ptr, ptr %t61, i32 2
  store ptr %t65, ptr %t72
  br label %case.end.2252990199.60
case.end.2252990199.60:
  br label %case.join.20
case.default.19:
  unreachable
case.join.20:
  %t73 = phi ptr [ %t58, %case.end.925038822.22 ], [ %t61, %case.end.2252990199.60 ]
  call void @__free_recursive(ptr %t15)
  %t74 = call ptr @v__apply__df_handleErrorIO_50(ptr %t6, ptr %t73)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t74, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.75:
  %t76 = getelementptr ptr, ptr %t5, i32 1
  %t77 = load ptr, ptr %t76
  %t78 = getelementptr ptr, ptr %t5, i32 2
  %t79 = load ptr, ptr %t78
  call void @__inc_ref(ptr %t79)
  %t86 = getelementptr i8, ptr %t5, i64 -8
  %t87 = load i32, ptr %t86
  %t88 = icmp eq i32 %t87, 1
  br i1 %t88, label %reuse.in_place.89, label %reuse.copy.90
reuse.in_place.89:
  %t80 = getelementptr ptr, ptr %t5, i32 2
  %t81 = load ptr, ptr %t80
  call void @__free_recursive(ptr %t81)
  %t84 = inttoptr i64 47 to ptr
  %t85 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t84, ptr %t85
  call void @__inc_ref(ptr %t6)
  %t82 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t82
  %t83 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t77, ptr %t83
  br label %reuse.in_place.end.92
reuse.in_place.end.92:
  br label %reuse.join.91
reuse.copy.90:
  %t94 = call ptr @__alloc(i64 24, i32 2)
  %t95 = inttoptr i64 47 to ptr
  %t96 = getelementptr ptr, ptr %t94, i32 0
  store ptr %t95, ptr %t96
  call void @__inc_ref(ptr %t6)
  %t97 = getelementptr ptr, ptr %t94, i32 1
  store ptr %t6, ptr %t97
  call void @__inc_ref(ptr %t77)
  %t98 = getelementptr ptr, ptr %t94, i32 2
  store ptr %t77, ptr %t98
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.93
reuse.copy.end.93:
  br label %reuse.join.91
reuse.join.91:
  %t99 = phi ptr [ %t5, %reuse.in_place.end.92 ], [ %t94, %reuse.copy.end.93 ]
  call void @__inc_ref(ptr %t79)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t79)
  store ptr %t79, ptr %t3
  store ptr %t99, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t100 = load ptr, ptr %t2
  ret ptr %t100
}

define internal ptr @v__apply__df_handleErrorIO_50(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 46, label %tco.case.arm.46.11 i64 47, label %tco.case.arm.47.12 ]
tco.case.arm.46.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.47.12:
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

define internal ptr @v__cps__df__rowmono_7_andThenIO_54(ptr %v_io, ptr %v__k) {
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
  %t26 = call ptr @v__apply__df__rowmono_7_andThenIO_54(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t26, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.27:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t28 = call ptr @v__apply__df__rowmono_7_andThenIO_54(ptr %t6, ptr %t5)
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
  %t38 = inttoptr i64 49 to ptr
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
  %t49 = inttoptr i64 49 to ptr
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

define internal ptr @v__apply__df__rowmono_7_andThenIO_54(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 48, label %tco.case.arm.48.11 i64 49, label %tco.case.arm.49.12 ]
tco.case.arm.48.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.49.12:
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

define internal ptr @v__cps__df_handleErrorIO_58(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.13 i64 7, label %tco.case.arm.7.91 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t12 = call ptr @v__apply__df_handleErrorIO_58(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t12, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.13:
  call void @__inc_ref(ptr %t6)
  %t14 = getelementptr ptr, ptr %t5, i32 1
  %t15 = load ptr, ptr %t14
  call void @__inc_ref(ptr %t15)
  %t16 = getelementptr ptr, ptr %t15, i32 0
  %t17 = load ptr, ptr %t16
  %t18 = ptrtoint ptr %t17 to i64
  switch i64 %t18, label %case.default.19 [ i64 925038822, label %case.arm.925038822.21 i64 1615808600, label %case.arm.1615808600.59 i64 2252990199, label %case.arm.2252990199.75 ]
case.arm.925038822.21:
  %t23 = getelementptr ptr, ptr %t15, i32 1
  %t24 = load ptr, ptr %t23
  call void @__inc_ref(ptr %t24)
  %t25 = getelementptr ptr, ptr %t24, i32 0
  %t26 = load ptr, ptr %t25
  %t27 = ptrtoint ptr %t26 to i64
  switch i64 %t27, label %case.default.28 [ i64 26, label %case.arm.26.30 i64 27, label %case.arm.27.44 ]
case.arm.26.30:
  %t32 = call ptr @__alloc(i64 24, i32 2)
  %t33 = inttoptr i64 7 to ptr
  %t34 = getelementptr ptr, ptr %t32, i32 0
  store ptr %t33, ptr %t34
  %t35 = getelementptr ptr, ptr %t32, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.4, i64 12), ptr %t35
  %t36 = call ptr @__alloc(i64 16, i32 1)
  %t37 = inttoptr i64 5 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = call ptr @__alloc(i64 8, i32 0)
  %t40 = inttoptr i64 0 to ptr
  %t41 = getelementptr ptr, ptr %t39, i32 0
  store ptr %t40, ptr %t41
  %t42 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t39, ptr %t42
  %t43 = getelementptr ptr, ptr %t32, i32 2
  store ptr %t36, ptr %t43
  br label %case.end.26.31
case.end.26.31:
  br label %case.join.29
case.arm.27.44:
  %t46 = call ptr @__alloc(i64 24, i32 2)
  %t47 = inttoptr i64 7 to ptr
  %t48 = getelementptr ptr, ptr %t46, i32 0
  store ptr %t47, ptr %t48
  %t49 = getelementptr ptr, ptr %t46, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.5, i64 12), ptr %t49
  %t50 = call ptr @__alloc(i64 16, i32 1)
  %t51 = inttoptr i64 5 to ptr
  %t52 = getelementptr ptr, ptr %t50, i32 0
  store ptr %t51, ptr %t52
  %t53 = call ptr @__alloc(i64 8, i32 0)
  %t54 = inttoptr i64 0 to ptr
  %t55 = getelementptr ptr, ptr %t53, i32 0
  store ptr %t54, ptr %t55
  %t56 = getelementptr ptr, ptr %t50, i32 1
  store ptr %t53, ptr %t56
  %t57 = getelementptr ptr, ptr %t46, i32 2
  store ptr %t50, ptr %t57
  br label %case.end.27.45
case.end.27.45:
  br label %case.join.29
case.default.28:
  unreachable
case.join.29:
  %t58 = phi ptr [ %t32, %case.end.26.31 ], [ %t46, %case.end.27.45 ]
  call void @__free_recursive(ptr %t24)
  br label %case.end.925038822.22
case.end.925038822.22:
  br label %case.join.20
case.arm.1615808600.59:
  %t61 = call ptr @__alloc(i64 24, i32 2)
  %t62 = inttoptr i64 7 to ptr
  %t63 = getelementptr ptr, ptr %t61, i32 0
  store ptr %t62, ptr %t63
  %t64 = getelementptr ptr, ptr %t15, i32 1
  %t65 = load ptr, ptr %t64
  call void @__inc_ref(ptr %t65)
  %t66 = getelementptr ptr, ptr %t61, i32 1
  store ptr %t65, ptr %t66
  %t67 = call ptr @__alloc(i64 16, i32 1)
  %t68 = inttoptr i64 5 to ptr
  %t69 = getelementptr ptr, ptr %t67, i32 0
  store ptr %t68, ptr %t69
  %t70 = call ptr @__alloc(i64 8, i32 0)
  %t71 = inttoptr i64 0 to ptr
  %t72 = getelementptr ptr, ptr %t70, i32 0
  store ptr %t71, ptr %t72
  %t73 = getelementptr ptr, ptr %t67, i32 1
  store ptr %t70, ptr %t73
  %t74 = getelementptr ptr, ptr %t61, i32 2
  store ptr %t67, ptr %t74
  br label %case.end.1615808600.60
case.end.1615808600.60:
  br label %case.join.20
case.arm.2252990199.75:
  %t77 = call ptr @__alloc(i64 24, i32 2)
  %t78 = inttoptr i64 7 to ptr
  %t79 = getelementptr ptr, ptr %t77, i32 0
  store ptr %t78, ptr %t79
  %t80 = getelementptr ptr, ptr %t77, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.3, i64 12), ptr %t80
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
  br label %case.end.2252990199.76
case.end.2252990199.76:
  br label %case.join.20
case.default.19:
  unreachable
case.join.20:
  %t89 = phi ptr [ %t58, %case.end.925038822.22 ], [ %t61, %case.end.1615808600.60 ], [ %t77, %case.end.2252990199.76 ]
  call void @__free_recursive(ptr %t15)
  %t90 = call ptr @v__apply__df_handleErrorIO_58(ptr %t6, ptr %t89)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t90, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.91:
  %t92 = getelementptr ptr, ptr %t5, i32 1
  %t93 = load ptr, ptr %t92
  %t94 = getelementptr ptr, ptr %t5, i32 2
  %t95 = load ptr, ptr %t94
  call void @__inc_ref(ptr %t95)
  %t102 = getelementptr i8, ptr %t5, i64 -8
  %t103 = load i32, ptr %t102
  %t104 = icmp eq i32 %t103, 1
  br i1 %t104, label %reuse.in_place.105, label %reuse.copy.106
reuse.in_place.105:
  %t96 = getelementptr ptr, ptr %t5, i32 2
  %t97 = load ptr, ptr %t96
  call void @__free_recursive(ptr %t97)
  %t100 = inttoptr i64 51 to ptr
  %t101 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t100, ptr %t101
  call void @__inc_ref(ptr %t6)
  %t98 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t98
  %t99 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t93, ptr %t99
  br label %reuse.in_place.end.108
reuse.in_place.end.108:
  br label %reuse.join.107
reuse.copy.106:
  %t110 = call ptr @__alloc(i64 24, i32 2)
  %t111 = inttoptr i64 51 to ptr
  %t112 = getelementptr ptr, ptr %t110, i32 0
  store ptr %t111, ptr %t112
  call void @__inc_ref(ptr %t6)
  %t113 = getelementptr ptr, ptr %t110, i32 1
  store ptr %t6, ptr %t113
  call void @__inc_ref(ptr %t93)
  %t114 = getelementptr ptr, ptr %t110, i32 2
  store ptr %t93, ptr %t114
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.109
reuse.copy.end.109:
  br label %reuse.join.107
reuse.join.107:
  %t115 = phi ptr [ %t5, %reuse.in_place.end.108 ], [ %t110, %reuse.copy.end.109 ]
  call void @__inc_ref(ptr %t95)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t95)
  store ptr %t95, ptr %t3
  store ptr %t115, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t116 = load ptr, ptr %t2
  ret ptr %t116
}

define internal ptr @v__apply__df_handleErrorIO_58(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 50, label %tco.case.arm.50.11 i64 51, label %tco.case.arm.51.12 ]
tco.case.arm.50.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.51.12:
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

define internal ptr @v__cps__df__rowmono_8_andThenIO_62(ptr %v_io, ptr %v__k) {
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
  %t26 = call ptr @v__apply__df__rowmono_8_andThenIO_62(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t26, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.27:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t28 = call ptr @v__apply__df__rowmono_8_andThenIO_62(ptr %t6, ptr %t5)
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
  %t38 = inttoptr i64 53 to ptr
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
  %t49 = inttoptr i64 53 to ptr
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

define internal ptr @v__apply__df__rowmono_8_andThenIO_62(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 52, label %tco.case.arm.52.11 i64 53, label %tco.case.arm.53.12 ]
tco.case.arm.52.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.53.12:
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

define internal ptr @v__cps__df_andThenIO_66(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.25 i64 7, label %tco.case.arm.7.27 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.7, i64 12), ptr %t15
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 5 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = call ptr @__alloc(i64 8, i32 0)
  %t20 = inttoptr i64 0 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t19, ptr %t22
  %t23 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t16, ptr %t23
  %t24 = call ptr @v__apply__df_andThenIO_66(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t24, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.25:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t26 = call ptr @v__apply__df_andThenIO_66(ptr %t6, ptr %t5)
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
  %t36 = inttoptr i64 55 to ptr
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
  %t47 = inttoptr i64 55 to ptr
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

define internal ptr @v__apply__df_andThenIO_66(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 54, label %tco.case.arm.54.11 i64 55, label %tco.case.arm.55.12 ]
tco.case.arm.54.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.55.12:
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

define internal ptr @v__cps__df_andThenIO_70(ptr %v_io, ptr %v__df_andThenIO_70_cap0_0, ptr %v__k) {
entry:
  %t3 = alloca ptr
  store ptr %v_io, ptr %t3
  %t4 = alloca ptr
  store ptr %v__df_andThenIO_70_cap0_0, ptr %t4
  %t5 = alloca ptr
  store ptr %v__k, ptr %t5
  %t2 = alloca ptr
  br label %tco.loop.0
tco.loop.0:
  %t6 = load ptr, ptr %t3
  %t7 = load ptr, ptr %t4
  %t8 = load ptr, ptr %t5
  %t9 = getelementptr ptr, ptr %t6, i32 0
  %t10 = load ptr, ptr %t9
  %t11 = ptrtoint ptr %t10 to i64
  switch i64 %t11, label %tco.case.default.12 [ i64 5, label %tco.case.arm.5.13 i64 6, label %tco.case.arm.6.15 i64 7, label %tco.case.arm.7.17 ]
tco.case.arm.5.13:
  call void @__inc_ref(ptr %t8)
  call void @__inc_ref(ptr %t7)
  %t14 = call ptr @v__apply__df_andThenIO_70(ptr %t8, ptr %t7)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t7)
  call void @__free_recursive(ptr %t8)
  store ptr %t14, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.15:
  call void @__inc_ref(ptr %t8)
  call void @__inc_ref(ptr %t6)
  %t16 = call ptr @v__apply__df_andThenIO_70(ptr %t8, ptr %t6)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t7)
  call void @__free_recursive(ptr %t8)
  store ptr %t16, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.17:
  %t18 = getelementptr ptr, ptr %t6, i32 1
  %t19 = load ptr, ptr %t18
  %t20 = getelementptr ptr, ptr %t6, i32 2
  %t21 = load ptr, ptr %t20
  call void @__inc_ref(ptr %t21)
  %t28 = getelementptr i8, ptr %t6, i64 -8
  %t29 = load i32, ptr %t28
  %t30 = icmp eq i32 %t29, 1
  br i1 %t30, label %reuse.in_place.31, label %reuse.copy.32
reuse.in_place.31:
  %t22 = getelementptr ptr, ptr %t6, i32 2
  %t23 = load ptr, ptr %t22
  call void @__free_recursive(ptr %t23)
  %t26 = inttoptr i64 57 to ptr
  %t27 = getelementptr ptr, ptr %t6, i32 0
  store ptr %t26, ptr %t27
  call void @__inc_ref(ptr %t8)
  %t24 = getelementptr ptr, ptr %t6, i32 1
  store ptr %t8, ptr %t24
  %t25 = getelementptr ptr, ptr %t6, i32 2
  store ptr %t19, ptr %t25
  br label %reuse.in_place.end.34
reuse.in_place.end.34:
  br label %reuse.join.33
reuse.copy.32:
  %t36 = call ptr @__alloc(i64 24, i32 2)
  %t37 = inttoptr i64 57 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  call void @__inc_ref(ptr %t8)
  %t39 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t8, ptr %t39
  call void @__inc_ref(ptr %t19)
  %t40 = getelementptr ptr, ptr %t36, i32 2
  store ptr %t19, ptr %t40
  call void @__free_recursive(ptr %t6)
  br label %reuse.copy.end.35
reuse.copy.end.35:
  br label %reuse.join.33
reuse.join.33:
  %t41 = phi ptr [ %t6, %reuse.in_place.end.34 ], [ %t36, %reuse.copy.end.35 ]
  call void @__inc_ref(ptr %t21)
  call void @__inc_ref(ptr %t7)
  call void @__free_recursive(ptr %t8)
  call void @__free_recursive(ptr %t7)
  call void @__free_recursive(ptr %t21)
  store ptr %t21, ptr %t3
  store ptr %t7, ptr %t4
  store ptr %t41, ptr %t5
  br label %tco.loop.0
tco.case.default.12:
  unreachable
tco.exit.1:
  %t42 = load ptr, ptr %t2
  ret ptr %t42
}

define internal ptr @v__apply__df_andThenIO_70(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 56, label %tco.case.arm.56.11 i64 57, label %tco.case.arm.57.12 ]
tco.case.arm.56.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.57.12:
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

define internal ptr @v__cps__df_andThenIO_74(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.25 i64 7, label %tco.case.arm.7.27 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.8, i64 12), ptr %t15
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 5 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = call ptr @__alloc(i64 8, i32 0)
  %t20 = inttoptr i64 0 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t19, ptr %t22
  %t23 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t16, ptr %t23
  %t24 = call ptr @v__apply__df_andThenIO_74(ptr %t6, ptr %t12)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t24, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.25:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t26 = call ptr @v__apply__df_andThenIO_74(ptr %t6, ptr %t5)
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
  %t36 = inttoptr i64 59 to ptr
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
  %t47 = inttoptr i64 59 to ptr
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

define internal ptr @v__apply__df_andThenIO_74(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 58, label %tco.case.arm.58.11 i64 59, label %tco.case.arm.59.12 ]
tco.case.arm.58.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.59.12:
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

define internal ptr @v__cps__df_andThenIO_78(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.72 i64 7, label %tco.case.arm.7.74 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.9, i64 12), ptr %t15
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 5 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = call ptr @__alloc(i64 8, i32 0)
  %t20 = inttoptr i64 0 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t19, ptr %t22
  %t23 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t16, ptr %t23
  %t24 = call ptr @__alloc(i64 8, i32 0)
  %t25 = inttoptr i64 58 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_74(ptr %t12, ptr %t24)
  %t28 = call ptr @v_wOk()
  %t29 = getelementptr ptr, ptr %t28, i32 0
  %t30 = load ptr, ptr %t29
  %t31 = ptrtoint ptr %t30 to i64
  switch i64 %t31, label %case.default.32 [ i64 3, label %case.arm.3.34 i64 4, label %case.arm.4.42 ]
case.arm.3.34:
  %t36 = call ptr @__alloc(i64 16, i32 1)
  %t37 = inttoptr i64 6 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t28, i32 1
  %t40 = load ptr, ptr %t39
  call void @__inc_ref(ptr %t40)
  %t41 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t40, ptr %t41
  br label %case.end.3.35
case.end.3.35:
  br label %case.join.33
case.arm.4.42:
  %t44 = call ptr @__alloc(i64 16, i32 1)
  %t45 = inttoptr i64 5 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  %t47 = getelementptr ptr, ptr %t28, i32 1
  %t48 = load ptr, ptr %t47
  call void @__inc_ref(ptr %t48)
  %t49 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t48, ptr %t49
  br label %case.end.4.43
case.end.4.43:
  br label %case.join.33
case.default.32:
  unreachable
case.join.33:
  %t50 = phi ptr [ %t36, %case.end.3.35 ], [ %t44, %case.end.4.43 ]
  %t51 = call ptr @__alloc(i64 8, i32 0)
  %t52 = inttoptr i64 32 to ptr
  %t53 = getelementptr ptr, ptr %t51, i32 0
  store ptr %t52, ptr %t53
  %t54 = call ptr @v__cps__df_mapIO_22(ptr %t50, ptr %t51)
  %t55 = call ptr @__alloc(i64 8, i32 0)
  %t56 = inttoptr i64 52 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  %t58 = call ptr @v__cps__df__rowmono_8_andThenIO_62(ptr %t54, ptr %t55)
  %t59 = call ptr @__alloc(i64 8, i32 0)
  %t60 = inttoptr i64 50 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  %t62 = call ptr @v__cps__df_handleErrorIO_58(ptr %t58, ptr %t59)
  call void @__free_recursive(ptr %t28)
  %t63 = call ptr @__alloc(i64 8, i32 0)
  %t64 = inttoptr i64 56 to ptr
  %t65 = getelementptr ptr, ptr %t63, i32 0
  store ptr %t64, ptr %t65
  %t66 = call ptr @v__cps__df_andThenIO_70(ptr %t27, ptr %t62, ptr %t63)
  %t67 = call ptr @__alloc(i64 8, i32 0)
  %t68 = inttoptr i64 54 to ptr
  %t69 = getelementptr ptr, ptr %t67, i32 0
  store ptr %t68, ptr %t69
  %t70 = call ptr @v__cps__df_andThenIO_66(ptr %t66, ptr %t67)
  %t71 = call ptr @v__apply__df_andThenIO_78(ptr %t6, ptr %t70)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.72:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t73 = call ptr @v__apply__df_andThenIO_78(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t73, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.74:
  %t75 = getelementptr ptr, ptr %t5, i32 1
  %t76 = load ptr, ptr %t75
  %t77 = getelementptr ptr, ptr %t5, i32 2
  %t78 = load ptr, ptr %t77
  call void @__inc_ref(ptr %t78)
  %t85 = getelementptr i8, ptr %t5, i64 -8
  %t86 = load i32, ptr %t85
  %t87 = icmp eq i32 %t86, 1
  br i1 %t87, label %reuse.in_place.88, label %reuse.copy.89
reuse.in_place.88:
  %t79 = getelementptr ptr, ptr %t5, i32 2
  %t80 = load ptr, ptr %t79
  call void @__free_recursive(ptr %t80)
  %t83 = inttoptr i64 61 to ptr
  %t84 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t83, ptr %t84
  call void @__inc_ref(ptr %t6)
  %t81 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t81
  %t82 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t76, ptr %t82
  br label %reuse.in_place.end.91
reuse.in_place.end.91:
  br label %reuse.join.90
reuse.copy.89:
  %t93 = call ptr @__alloc(i64 24, i32 2)
  %t94 = inttoptr i64 61 to ptr
  %t95 = getelementptr ptr, ptr %t93, i32 0
  store ptr %t94, ptr %t95
  call void @__inc_ref(ptr %t6)
  %t96 = getelementptr ptr, ptr %t93, i32 1
  store ptr %t6, ptr %t96
  call void @__inc_ref(ptr %t76)
  %t97 = getelementptr ptr, ptr %t93, i32 2
  store ptr %t76, ptr %t97
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.92
reuse.copy.end.92:
  br label %reuse.join.90
reuse.join.90:
  %t98 = phi ptr [ %t5, %reuse.in_place.end.91 ], [ %t93, %reuse.copy.end.92 ]
  call void @__inc_ref(ptr %t78)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t78)
  store ptr %t78, ptr %t3
  store ptr %t98, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t99 = load ptr, ptr %t2
  ret ptr %t99
}

define internal ptr @v__apply__df_andThenIO_78(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 60, label %tco.case.arm.60.11 i64 61, label %tco.case.arm.61.12 ]
tco.case.arm.60.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.61.12:
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

define internal ptr @v__cps__df_andThenIO_82(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.72 i64 7, label %tco.case.arm.7.74 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.10, i64 12), ptr %t15
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 5 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = call ptr @__alloc(i64 8, i32 0)
  %t20 = inttoptr i64 0 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t19, ptr %t22
  %t23 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t16, ptr %t23
  %t24 = call ptr @__alloc(i64 8, i32 0)
  %t25 = inttoptr i64 58 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_74(ptr %t12, ptr %t24)
  %t28 = call ptr @v_wE3()
  %t29 = getelementptr ptr, ptr %t28, i32 0
  %t30 = load ptr, ptr %t29
  %t31 = ptrtoint ptr %t30 to i64
  switch i64 %t31, label %case.default.32 [ i64 3, label %case.arm.3.34 i64 4, label %case.arm.4.42 ]
case.arm.3.34:
  %t36 = call ptr @__alloc(i64 16, i32 1)
  %t37 = inttoptr i64 6 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t28, i32 1
  %t40 = load ptr, ptr %t39
  call void @__inc_ref(ptr %t40)
  %t41 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t40, ptr %t41
  br label %case.end.3.35
case.end.3.35:
  br label %case.join.33
case.arm.4.42:
  %t44 = call ptr @__alloc(i64 16, i32 1)
  %t45 = inttoptr i64 5 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  %t47 = getelementptr ptr, ptr %t28, i32 1
  %t48 = load ptr, ptr %t47
  call void @__inc_ref(ptr %t48)
  %t49 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t48, ptr %t49
  br label %case.end.4.43
case.end.4.43:
  br label %case.join.33
case.default.32:
  unreachable
case.join.33:
  %t50 = phi ptr [ %t36, %case.end.3.35 ], [ %t44, %case.end.4.43 ]
  %t51 = call ptr @__alloc(i64 8, i32 0)
  %t52 = inttoptr i64 32 to ptr
  %t53 = getelementptr ptr, ptr %t51, i32 0
  store ptr %t52, ptr %t53
  %t54 = call ptr @v__cps__df_mapIO_22(ptr %t50, ptr %t51)
  %t55 = call ptr @__alloc(i64 8, i32 0)
  %t56 = inttoptr i64 52 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  %t58 = call ptr @v__cps__df__rowmono_8_andThenIO_62(ptr %t54, ptr %t55)
  %t59 = call ptr @__alloc(i64 8, i32 0)
  %t60 = inttoptr i64 50 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  %t62 = call ptr @v__cps__df_handleErrorIO_58(ptr %t58, ptr %t59)
  call void @__free_recursive(ptr %t28)
  %t63 = call ptr @__alloc(i64 8, i32 0)
  %t64 = inttoptr i64 56 to ptr
  %t65 = getelementptr ptr, ptr %t63, i32 0
  store ptr %t64, ptr %t65
  %t66 = call ptr @v__cps__df_andThenIO_70(ptr %t27, ptr %t62, ptr %t63)
  %t67 = call ptr @__alloc(i64 8, i32 0)
  %t68 = inttoptr i64 54 to ptr
  %t69 = getelementptr ptr, ptr %t67, i32 0
  store ptr %t68, ptr %t69
  %t70 = call ptr @v__cps__df_andThenIO_66(ptr %t66, ptr %t67)
  %t71 = call ptr @v__apply__df_andThenIO_82(ptr %t6, ptr %t70)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.72:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t73 = call ptr @v__apply__df_andThenIO_82(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t73, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.74:
  %t75 = getelementptr ptr, ptr %t5, i32 1
  %t76 = load ptr, ptr %t75
  %t77 = getelementptr ptr, ptr %t5, i32 2
  %t78 = load ptr, ptr %t77
  call void @__inc_ref(ptr %t78)
  %t85 = getelementptr i8, ptr %t5, i64 -8
  %t86 = load i32, ptr %t85
  %t87 = icmp eq i32 %t86, 1
  br i1 %t87, label %reuse.in_place.88, label %reuse.copy.89
reuse.in_place.88:
  %t79 = getelementptr ptr, ptr %t5, i32 2
  %t80 = load ptr, ptr %t79
  call void @__free_recursive(ptr %t80)
  %t83 = inttoptr i64 63 to ptr
  %t84 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t83, ptr %t84
  call void @__inc_ref(ptr %t6)
  %t81 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t81
  %t82 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t76, ptr %t82
  br label %reuse.in_place.end.91
reuse.in_place.end.91:
  br label %reuse.join.90
reuse.copy.89:
  %t93 = call ptr @__alloc(i64 24, i32 2)
  %t94 = inttoptr i64 63 to ptr
  %t95 = getelementptr ptr, ptr %t93, i32 0
  store ptr %t94, ptr %t95
  call void @__inc_ref(ptr %t6)
  %t96 = getelementptr ptr, ptr %t93, i32 1
  store ptr %t6, ptr %t96
  call void @__inc_ref(ptr %t76)
  %t97 = getelementptr ptr, ptr %t93, i32 2
  store ptr %t76, ptr %t97
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.92
reuse.copy.end.92:
  br label %reuse.join.90
reuse.join.90:
  %t98 = phi ptr [ %t5, %reuse.in_place.end.91 ], [ %t93, %reuse.copy.end.92 ]
  call void @__inc_ref(ptr %t78)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t78)
  store ptr %t78, ptr %t3
  store ptr %t98, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t99 = load ptr, ptr %t2
  ret ptr %t99
}

define internal ptr @v__apply__df_andThenIO_82(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 62, label %tco.case.arm.62.11 i64 63, label %tco.case.arm.63.12 ]
tco.case.arm.62.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.63.12:
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

define internal ptr @v__cps__df_andThenIO_86(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.72 i64 7, label %tco.case.arm.7.74 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.11, i64 12), ptr %t15
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 5 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = call ptr @__alloc(i64 8, i32 0)
  %t20 = inttoptr i64 0 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t19, ptr %t22
  %t23 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t16, ptr %t23
  %t24 = call ptr @__alloc(i64 8, i32 0)
  %t25 = inttoptr i64 58 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_74(ptr %t12, ptr %t24)
  %t28 = call ptr @v_wE2str()
  %t29 = getelementptr ptr, ptr %t28, i32 0
  %t30 = load ptr, ptr %t29
  %t31 = ptrtoint ptr %t30 to i64
  switch i64 %t31, label %case.default.32 [ i64 3, label %case.arm.3.34 i64 4, label %case.arm.4.42 ]
case.arm.3.34:
  %t36 = call ptr @__alloc(i64 16, i32 1)
  %t37 = inttoptr i64 6 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t28, i32 1
  %t40 = load ptr, ptr %t39
  call void @__inc_ref(ptr %t40)
  %t41 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t40, ptr %t41
  br label %case.end.3.35
case.end.3.35:
  br label %case.join.33
case.arm.4.42:
  %t44 = call ptr @__alloc(i64 16, i32 1)
  %t45 = inttoptr i64 5 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  %t47 = getelementptr ptr, ptr %t28, i32 1
  %t48 = load ptr, ptr %t47
  call void @__inc_ref(ptr %t48)
  %t49 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t48, ptr %t49
  br label %case.end.4.43
case.end.4.43:
  br label %case.join.33
case.default.32:
  unreachable
case.join.33:
  %t50 = phi ptr [ %t36, %case.end.3.35 ], [ %t44, %case.end.4.43 ]
  %t51 = call ptr @__alloc(i64 8, i32 0)
  %t52 = inttoptr i64 32 to ptr
  %t53 = getelementptr ptr, ptr %t51, i32 0
  store ptr %t52, ptr %t53
  %t54 = call ptr @v__cps__df_mapIO_22(ptr %t50, ptr %t51)
  %t55 = call ptr @__alloc(i64 8, i32 0)
  %t56 = inttoptr i64 52 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  %t58 = call ptr @v__cps__df__rowmono_8_andThenIO_62(ptr %t54, ptr %t55)
  %t59 = call ptr @__alloc(i64 8, i32 0)
  %t60 = inttoptr i64 50 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  %t62 = call ptr @v__cps__df_handleErrorIO_58(ptr %t58, ptr %t59)
  call void @__free_recursive(ptr %t28)
  %t63 = call ptr @__alloc(i64 8, i32 0)
  %t64 = inttoptr i64 56 to ptr
  %t65 = getelementptr ptr, ptr %t63, i32 0
  store ptr %t64, ptr %t65
  %t66 = call ptr @v__cps__df_andThenIO_70(ptr %t27, ptr %t62, ptr %t63)
  %t67 = call ptr @__alloc(i64 8, i32 0)
  %t68 = inttoptr i64 54 to ptr
  %t69 = getelementptr ptr, ptr %t67, i32 0
  store ptr %t68, ptr %t69
  %t70 = call ptr @v__cps__df_andThenIO_66(ptr %t66, ptr %t67)
  %t71 = call ptr @v__apply__df_andThenIO_86(ptr %t6, ptr %t70)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.72:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t73 = call ptr @v__apply__df_andThenIO_86(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t73, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.74:
  %t75 = getelementptr ptr, ptr %t5, i32 1
  %t76 = load ptr, ptr %t75
  %t77 = getelementptr ptr, ptr %t5, i32 2
  %t78 = load ptr, ptr %t77
  call void @__inc_ref(ptr %t78)
  %t85 = getelementptr i8, ptr %t5, i64 -8
  %t86 = load i32, ptr %t85
  %t87 = icmp eq i32 %t86, 1
  br i1 %t87, label %reuse.in_place.88, label %reuse.copy.89
reuse.in_place.88:
  %t79 = getelementptr ptr, ptr %t5, i32 2
  %t80 = load ptr, ptr %t79
  call void @__free_recursive(ptr %t80)
  %t83 = inttoptr i64 65 to ptr
  %t84 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t83, ptr %t84
  call void @__inc_ref(ptr %t6)
  %t81 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t81
  %t82 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t76, ptr %t82
  br label %reuse.in_place.end.91
reuse.in_place.end.91:
  br label %reuse.join.90
reuse.copy.89:
  %t93 = call ptr @__alloc(i64 24, i32 2)
  %t94 = inttoptr i64 65 to ptr
  %t95 = getelementptr ptr, ptr %t93, i32 0
  store ptr %t94, ptr %t95
  call void @__inc_ref(ptr %t6)
  %t96 = getelementptr ptr, ptr %t93, i32 1
  store ptr %t6, ptr %t96
  call void @__inc_ref(ptr %t76)
  %t97 = getelementptr ptr, ptr %t93, i32 2
  store ptr %t76, ptr %t97
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.92
reuse.copy.end.92:
  br label %reuse.join.90
reuse.join.90:
  %t98 = phi ptr [ %t5, %reuse.in_place.end.91 ], [ %t93, %reuse.copy.end.92 ]
  call void @__inc_ref(ptr %t78)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t78)
  store ptr %t78, ptr %t3
  store ptr %t98, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t99 = load ptr, ptr %t2
  ret ptr %t99
}

define internal ptr @v__apply__df_andThenIO_86(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 64, label %tco.case.arm.64.11 i64 65, label %tco.case.arm.65.12 ]
tco.case.arm.64.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.65.12:
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

define internal ptr @v__cps__df_andThenIO_90(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.72 i64 7, label %tco.case.arm.7.74 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.12, i64 12), ptr %t15
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 5 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = call ptr @__alloc(i64 8, i32 0)
  %t20 = inttoptr i64 0 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t19, ptr %t22
  %t23 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t16, ptr %t23
  %t24 = call ptr @__alloc(i64 8, i32 0)
  %t25 = inttoptr i64 58 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_74(ptr %t12, ptr %t24)
  %t28 = call ptr @v_wE1()
  %t29 = getelementptr ptr, ptr %t28, i32 0
  %t30 = load ptr, ptr %t29
  %t31 = ptrtoint ptr %t30 to i64
  switch i64 %t31, label %case.default.32 [ i64 3, label %case.arm.3.34 i64 4, label %case.arm.4.42 ]
case.arm.3.34:
  %t36 = call ptr @__alloc(i64 16, i32 1)
  %t37 = inttoptr i64 6 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t28, i32 1
  %t40 = load ptr, ptr %t39
  call void @__inc_ref(ptr %t40)
  %t41 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t40, ptr %t41
  br label %case.end.3.35
case.end.3.35:
  br label %case.join.33
case.arm.4.42:
  %t44 = call ptr @__alloc(i64 16, i32 1)
  %t45 = inttoptr i64 5 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  %t47 = getelementptr ptr, ptr %t28, i32 1
  %t48 = load ptr, ptr %t47
  call void @__inc_ref(ptr %t48)
  %t49 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t48, ptr %t49
  br label %case.end.4.43
case.end.4.43:
  br label %case.join.33
case.default.32:
  unreachable
case.join.33:
  %t50 = phi ptr [ %t36, %case.end.3.35 ], [ %t44, %case.end.4.43 ]
  %t51 = call ptr @__alloc(i64 8, i32 0)
  %t52 = inttoptr i64 32 to ptr
  %t53 = getelementptr ptr, ptr %t51, i32 0
  store ptr %t52, ptr %t53
  %t54 = call ptr @v__cps__df_mapIO_22(ptr %t50, ptr %t51)
  %t55 = call ptr @__alloc(i64 8, i32 0)
  %t56 = inttoptr i64 52 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  %t58 = call ptr @v__cps__df__rowmono_8_andThenIO_62(ptr %t54, ptr %t55)
  %t59 = call ptr @__alloc(i64 8, i32 0)
  %t60 = inttoptr i64 50 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  %t62 = call ptr @v__cps__df_handleErrorIO_58(ptr %t58, ptr %t59)
  call void @__free_recursive(ptr %t28)
  %t63 = call ptr @__alloc(i64 8, i32 0)
  %t64 = inttoptr i64 56 to ptr
  %t65 = getelementptr ptr, ptr %t63, i32 0
  store ptr %t64, ptr %t65
  %t66 = call ptr @v__cps__df_andThenIO_70(ptr %t27, ptr %t62, ptr %t63)
  %t67 = call ptr @__alloc(i64 8, i32 0)
  %t68 = inttoptr i64 54 to ptr
  %t69 = getelementptr ptr, ptr %t67, i32 0
  store ptr %t68, ptr %t69
  %t70 = call ptr @v__cps__df_andThenIO_66(ptr %t66, ptr %t67)
  %t71 = call ptr @v__apply__df_andThenIO_90(ptr %t6, ptr %t70)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.72:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t73 = call ptr @v__apply__df_andThenIO_90(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t73, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.74:
  %t75 = getelementptr ptr, ptr %t5, i32 1
  %t76 = load ptr, ptr %t75
  %t77 = getelementptr ptr, ptr %t5, i32 2
  %t78 = load ptr, ptr %t77
  call void @__inc_ref(ptr %t78)
  %t85 = getelementptr i8, ptr %t5, i64 -8
  %t86 = load i32, ptr %t85
  %t87 = icmp eq i32 %t86, 1
  br i1 %t87, label %reuse.in_place.88, label %reuse.copy.89
reuse.in_place.88:
  %t79 = getelementptr ptr, ptr %t5, i32 2
  %t80 = load ptr, ptr %t79
  call void @__free_recursive(ptr %t80)
  %t83 = inttoptr i64 67 to ptr
  %t84 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t83, ptr %t84
  call void @__inc_ref(ptr %t6)
  %t81 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t81
  %t82 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t76, ptr %t82
  br label %reuse.in_place.end.91
reuse.in_place.end.91:
  br label %reuse.join.90
reuse.copy.89:
  %t93 = call ptr @__alloc(i64 24, i32 2)
  %t94 = inttoptr i64 67 to ptr
  %t95 = getelementptr ptr, ptr %t93, i32 0
  store ptr %t94, ptr %t95
  call void @__inc_ref(ptr %t6)
  %t96 = getelementptr ptr, ptr %t93, i32 1
  store ptr %t6, ptr %t96
  call void @__inc_ref(ptr %t76)
  %t97 = getelementptr ptr, ptr %t93, i32 2
  store ptr %t76, ptr %t97
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.92
reuse.copy.end.92:
  br label %reuse.join.90
reuse.join.90:
  %t98 = phi ptr [ %t5, %reuse.in_place.end.91 ], [ %t93, %reuse.copy.end.92 ]
  call void @__inc_ref(ptr %t78)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t78)
  store ptr %t78, ptr %t3
  store ptr %t98, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t99 = load ptr, ptr %t2
  ret ptr %t99
}

define internal ptr @v__apply__df_andThenIO_90(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 66, label %tco.case.arm.66.11 i64 67, label %tco.case.arm.67.12 ]
tco.case.arm.66.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.67.12:
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

define internal ptr @v__cps__df_andThenIO_94(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.72 i64 7, label %tco.case.arm.7.74 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.13, i64 12), ptr %t15
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 5 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = call ptr @__alloc(i64 8, i32 0)
  %t20 = inttoptr i64 0 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t19, ptr %t22
  %t23 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t16, ptr %t23
  %t24 = call ptr @__alloc(i64 8, i32 0)
  %t25 = inttoptr i64 58 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_74(ptr %t12, ptr %t24)
  %t28 = call ptr @v_idem2Second()
  %t29 = getelementptr ptr, ptr %t28, i32 0
  %t30 = load ptr, ptr %t29
  %t31 = ptrtoint ptr %t30 to i64
  switch i64 %t31, label %case.default.32 [ i64 3, label %case.arm.3.34 i64 4, label %case.arm.4.42 ]
case.arm.3.34:
  %t36 = call ptr @__alloc(i64 16, i32 1)
  %t37 = inttoptr i64 6 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t28, i32 1
  %t40 = load ptr, ptr %t39
  call void @__inc_ref(ptr %t40)
  %t41 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t40, ptr %t41
  br label %case.end.3.35
case.end.3.35:
  br label %case.join.33
case.arm.4.42:
  %t44 = call ptr @__alloc(i64 16, i32 1)
  %t45 = inttoptr i64 5 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  %t47 = getelementptr ptr, ptr %t28, i32 1
  %t48 = load ptr, ptr %t47
  call void @__inc_ref(ptr %t48)
  %t49 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t48, ptr %t49
  br label %case.end.4.43
case.end.4.43:
  br label %case.join.33
case.default.32:
  unreachable
case.join.33:
  %t50 = phi ptr [ %t36, %case.end.3.35 ], [ %t44, %case.end.4.43 ]
  %t51 = call ptr @__alloc(i64 8, i32 0)
  %t52 = inttoptr i64 32 to ptr
  %t53 = getelementptr ptr, ptr %t51, i32 0
  store ptr %t52, ptr %t53
  %t54 = call ptr @v__cps__df_mapIO_22(ptr %t50, ptr %t51)
  %t55 = call ptr @__alloc(i64 8, i32 0)
  %t56 = inttoptr i64 30 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  %t58 = call ptr @v__cps__df_andThenIO_18(ptr %t54, ptr %t55)
  %t59 = call ptr @__alloc(i64 8, i32 0)
  %t60 = inttoptr i64 34 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  %t62 = call ptr @v__cps__df_handleErrorIO_26(ptr %t58, ptr %t59)
  call void @__free_recursive(ptr %t28)
  %t63 = call ptr @__alloc(i64 8, i32 0)
  %t64 = inttoptr i64 56 to ptr
  %t65 = getelementptr ptr, ptr %t63, i32 0
  store ptr %t64, ptr %t65
  %t66 = call ptr @v__cps__df_andThenIO_70(ptr %t27, ptr %t62, ptr %t63)
  %t67 = call ptr @__alloc(i64 8, i32 0)
  %t68 = inttoptr i64 54 to ptr
  %t69 = getelementptr ptr, ptr %t67, i32 0
  store ptr %t68, ptr %t69
  %t70 = call ptr @v__cps__df_andThenIO_66(ptr %t66, ptr %t67)
  %t71 = call ptr @v__apply__df_andThenIO_94(ptr %t6, ptr %t70)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.72:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t73 = call ptr @v__apply__df_andThenIO_94(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t73, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.74:
  %t75 = getelementptr ptr, ptr %t5, i32 1
  %t76 = load ptr, ptr %t75
  %t77 = getelementptr ptr, ptr %t5, i32 2
  %t78 = load ptr, ptr %t77
  call void @__inc_ref(ptr %t78)
  %t85 = getelementptr i8, ptr %t5, i64 -8
  %t86 = load i32, ptr %t85
  %t87 = icmp eq i32 %t86, 1
  br i1 %t87, label %reuse.in_place.88, label %reuse.copy.89
reuse.in_place.88:
  %t79 = getelementptr ptr, ptr %t5, i32 2
  %t80 = load ptr, ptr %t79
  call void @__free_recursive(ptr %t80)
  %t83 = inttoptr i64 69 to ptr
  %t84 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t83, ptr %t84
  call void @__inc_ref(ptr %t6)
  %t81 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t81
  %t82 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t76, ptr %t82
  br label %reuse.in_place.end.91
reuse.in_place.end.91:
  br label %reuse.join.90
reuse.copy.89:
  %t93 = call ptr @__alloc(i64 24, i32 2)
  %t94 = inttoptr i64 69 to ptr
  %t95 = getelementptr ptr, ptr %t93, i32 0
  store ptr %t94, ptr %t95
  call void @__inc_ref(ptr %t6)
  %t96 = getelementptr ptr, ptr %t93, i32 1
  store ptr %t6, ptr %t96
  call void @__inc_ref(ptr %t76)
  %t97 = getelementptr ptr, ptr %t93, i32 2
  store ptr %t76, ptr %t97
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.92
reuse.copy.end.92:
  br label %reuse.join.90
reuse.join.90:
  %t98 = phi ptr [ %t5, %reuse.in_place.end.91 ], [ %t93, %reuse.copy.end.92 ]
  call void @__inc_ref(ptr %t78)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t78)
  store ptr %t78, ptr %t3
  store ptr %t98, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t99 = load ptr, ptr %t2
  ret ptr %t99
}

define internal ptr @v__apply__df_andThenIO_94(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 68, label %tco.case.arm.68.11 i64 69, label %tco.case.arm.69.12 ]
tco.case.arm.68.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.69.12:
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

define internal ptr @v__cps__df_andThenIO_98(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.72 i64 7, label %tco.case.arm.7.74 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.14, i64 12), ptr %t15
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 5 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = call ptr @__alloc(i64 8, i32 0)
  %t20 = inttoptr i64 0 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t19, ptr %t22
  %t23 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t16, ptr %t23
  %t24 = call ptr @__alloc(i64 8, i32 0)
  %t25 = inttoptr i64 58 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_74(ptr %t12, ptr %t24)
  %t28 = call ptr @v_idem2First()
  %t29 = getelementptr ptr, ptr %t28, i32 0
  %t30 = load ptr, ptr %t29
  %t31 = ptrtoint ptr %t30 to i64
  switch i64 %t31, label %case.default.32 [ i64 3, label %case.arm.3.34 i64 4, label %case.arm.4.42 ]
case.arm.3.34:
  %t36 = call ptr @__alloc(i64 16, i32 1)
  %t37 = inttoptr i64 6 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t28, i32 1
  %t40 = load ptr, ptr %t39
  call void @__inc_ref(ptr %t40)
  %t41 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t40, ptr %t41
  br label %case.end.3.35
case.end.3.35:
  br label %case.join.33
case.arm.4.42:
  %t44 = call ptr @__alloc(i64 16, i32 1)
  %t45 = inttoptr i64 5 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  %t47 = getelementptr ptr, ptr %t28, i32 1
  %t48 = load ptr, ptr %t47
  call void @__inc_ref(ptr %t48)
  %t49 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t48, ptr %t49
  br label %case.end.4.43
case.end.4.43:
  br label %case.join.33
case.default.32:
  unreachable
case.join.33:
  %t50 = phi ptr [ %t36, %case.end.3.35 ], [ %t44, %case.end.4.43 ]
  %t51 = call ptr @__alloc(i64 8, i32 0)
  %t52 = inttoptr i64 32 to ptr
  %t53 = getelementptr ptr, ptr %t51, i32 0
  store ptr %t52, ptr %t53
  %t54 = call ptr @v__cps__df_mapIO_22(ptr %t50, ptr %t51)
  %t55 = call ptr @__alloc(i64 8, i32 0)
  %t56 = inttoptr i64 30 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  %t58 = call ptr @v__cps__df_andThenIO_18(ptr %t54, ptr %t55)
  %t59 = call ptr @__alloc(i64 8, i32 0)
  %t60 = inttoptr i64 34 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  %t62 = call ptr @v__cps__df_handleErrorIO_26(ptr %t58, ptr %t59)
  call void @__free_recursive(ptr %t28)
  %t63 = call ptr @__alloc(i64 8, i32 0)
  %t64 = inttoptr i64 56 to ptr
  %t65 = getelementptr ptr, ptr %t63, i32 0
  store ptr %t64, ptr %t65
  %t66 = call ptr @v__cps__df_andThenIO_70(ptr %t27, ptr %t62, ptr %t63)
  %t67 = call ptr @__alloc(i64 8, i32 0)
  %t68 = inttoptr i64 54 to ptr
  %t69 = getelementptr ptr, ptr %t67, i32 0
  store ptr %t68, ptr %t69
  %t70 = call ptr @v__cps__df_andThenIO_66(ptr %t66, ptr %t67)
  %t71 = call ptr @v__apply__df_andThenIO_98(ptr %t6, ptr %t70)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.72:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t73 = call ptr @v__apply__df_andThenIO_98(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t73, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.74:
  %t75 = getelementptr ptr, ptr %t5, i32 1
  %t76 = load ptr, ptr %t75
  %t77 = getelementptr ptr, ptr %t5, i32 2
  %t78 = load ptr, ptr %t77
  call void @__inc_ref(ptr %t78)
  %t85 = getelementptr i8, ptr %t5, i64 -8
  %t86 = load i32, ptr %t85
  %t87 = icmp eq i32 %t86, 1
  br i1 %t87, label %reuse.in_place.88, label %reuse.copy.89
reuse.in_place.88:
  %t79 = getelementptr ptr, ptr %t5, i32 2
  %t80 = load ptr, ptr %t79
  call void @__free_recursive(ptr %t80)
  %t83 = inttoptr i64 71 to ptr
  %t84 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t83, ptr %t84
  call void @__inc_ref(ptr %t6)
  %t81 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t81
  %t82 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t76, ptr %t82
  br label %reuse.in_place.end.91
reuse.in_place.end.91:
  br label %reuse.join.90
reuse.copy.89:
  %t93 = call ptr @__alloc(i64 24, i32 2)
  %t94 = inttoptr i64 71 to ptr
  %t95 = getelementptr ptr, ptr %t93, i32 0
  store ptr %t94, ptr %t95
  call void @__inc_ref(ptr %t6)
  %t96 = getelementptr ptr, ptr %t93, i32 1
  store ptr %t6, ptr %t96
  call void @__inc_ref(ptr %t76)
  %t97 = getelementptr ptr, ptr %t93, i32 2
  store ptr %t76, ptr %t97
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.92
reuse.copy.end.92:
  br label %reuse.join.90
reuse.join.90:
  %t98 = phi ptr [ %t5, %reuse.in_place.end.91 ], [ %t93, %reuse.copy.end.92 ]
  call void @__inc_ref(ptr %t78)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t78)
  store ptr %t78, ptr %t3
  store ptr %t98, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t99 = load ptr, ptr %t2
  ret ptr %t99
}

define internal ptr @v__apply__df_andThenIO_98(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 70, label %tco.case.arm.70.11 i64 71, label %tco.case.arm.71.12 ]
tco.case.arm.70.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.71.12:
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

define internal ptr @v__cps__df_andThenIO_102(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.72 i64 7, label %tco.case.arm.7.74 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.15, i64 12), ptr %t15
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 5 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = call ptr @__alloc(i64 8, i32 0)
  %t20 = inttoptr i64 0 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t19, ptr %t22
  %t23 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t16, ptr %t23
  %t24 = call ptr @__alloc(i64 8, i32 0)
  %t25 = inttoptr i64 58 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_74(ptr %t12, ptr %t24)
  %t28 = call ptr @v_idemE2()
  %t29 = getelementptr ptr, ptr %t28, i32 0
  %t30 = load ptr, ptr %t29
  %t31 = ptrtoint ptr %t30 to i64
  switch i64 %t31, label %case.default.32 [ i64 3, label %case.arm.3.34 i64 4, label %case.arm.4.42 ]
case.arm.3.34:
  %t36 = call ptr @__alloc(i64 16, i32 1)
  %t37 = inttoptr i64 6 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t28, i32 1
  %t40 = load ptr, ptr %t39
  call void @__inc_ref(ptr %t40)
  %t41 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t40, ptr %t41
  br label %case.end.3.35
case.end.3.35:
  br label %case.join.33
case.arm.4.42:
  %t44 = call ptr @__alloc(i64 16, i32 1)
  %t45 = inttoptr i64 5 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  %t47 = getelementptr ptr, ptr %t28, i32 1
  %t48 = load ptr, ptr %t47
  call void @__inc_ref(ptr %t48)
  %t49 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t48, ptr %t49
  br label %case.end.4.43
case.end.4.43:
  br label %case.join.33
case.default.32:
  unreachable
case.join.33:
  %t50 = phi ptr [ %t36, %case.end.3.35 ], [ %t44, %case.end.4.43 ]
  %t51 = call ptr @__alloc(i64 8, i32 0)
  %t52 = inttoptr i64 32 to ptr
  %t53 = getelementptr ptr, ptr %t51, i32 0
  store ptr %t52, ptr %t53
  %t54 = call ptr @v__cps__df_mapIO_22(ptr %t50, ptr %t51)
  %t55 = call ptr @__alloc(i64 8, i32 0)
  %t56 = inttoptr i64 30 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  %t58 = call ptr @v__cps__df_andThenIO_18(ptr %t54, ptr %t55)
  %t59 = call ptr @__alloc(i64 8, i32 0)
  %t60 = inttoptr i64 28 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  %t62 = call ptr @v__cps__df_handleErrorIO_14(ptr %t58, ptr %t59)
  call void @__free_recursive(ptr %t28)
  %t63 = call ptr @__alloc(i64 8, i32 0)
  %t64 = inttoptr i64 56 to ptr
  %t65 = getelementptr ptr, ptr %t63, i32 0
  store ptr %t64, ptr %t65
  %t66 = call ptr @v__cps__df_andThenIO_70(ptr %t27, ptr %t62, ptr %t63)
  %t67 = call ptr @__alloc(i64 8, i32 0)
  %t68 = inttoptr i64 54 to ptr
  %t69 = getelementptr ptr, ptr %t67, i32 0
  store ptr %t68, ptr %t69
  %t70 = call ptr @v__cps__df_andThenIO_66(ptr %t66, ptr %t67)
  %t71 = call ptr @v__apply__df_andThenIO_102(ptr %t6, ptr %t70)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.72:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t73 = call ptr @v__apply__df_andThenIO_102(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t73, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.74:
  %t75 = getelementptr ptr, ptr %t5, i32 1
  %t76 = load ptr, ptr %t75
  %t77 = getelementptr ptr, ptr %t5, i32 2
  %t78 = load ptr, ptr %t77
  call void @__inc_ref(ptr %t78)
  %t85 = getelementptr i8, ptr %t5, i64 -8
  %t86 = load i32, ptr %t85
  %t87 = icmp eq i32 %t86, 1
  br i1 %t87, label %reuse.in_place.88, label %reuse.copy.89
reuse.in_place.88:
  %t79 = getelementptr ptr, ptr %t5, i32 2
  %t80 = load ptr, ptr %t79
  call void @__free_recursive(ptr %t80)
  %t83 = inttoptr i64 73 to ptr
  %t84 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t83, ptr %t84
  call void @__inc_ref(ptr %t6)
  %t81 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t81
  %t82 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t76, ptr %t82
  br label %reuse.in_place.end.91
reuse.in_place.end.91:
  br label %reuse.join.90
reuse.copy.89:
  %t93 = call ptr @__alloc(i64 24, i32 2)
  %t94 = inttoptr i64 73 to ptr
  %t95 = getelementptr ptr, ptr %t93, i32 0
  store ptr %t94, ptr %t95
  call void @__inc_ref(ptr %t6)
  %t96 = getelementptr ptr, ptr %t93, i32 1
  store ptr %t6, ptr %t96
  call void @__inc_ref(ptr %t76)
  %t97 = getelementptr ptr, ptr %t93, i32 2
  store ptr %t76, ptr %t97
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.92
reuse.copy.end.92:
  br label %reuse.join.90
reuse.join.90:
  %t98 = phi ptr [ %t5, %reuse.in_place.end.91 ], [ %t93, %reuse.copy.end.92 ]
  call void @__inc_ref(ptr %t78)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t78)
  store ptr %t78, ptr %t3
  store ptr %t98, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t99 = load ptr, ptr %t2
  ret ptr %t99
}

define internal ptr @v__apply__df_andThenIO_102(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 72, label %tco.case.arm.72.11 i64 73, label %tco.case.arm.73.12 ]
tco.case.arm.72.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.73.12:
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

define internal ptr @v__cps__df_andThenIO_106(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.72 i64 7, label %tco.case.arm.7.74 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.16, i64 12), ptr %t15
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 5 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = call ptr @__alloc(i64 8, i32 0)
  %t20 = inttoptr i64 0 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t19, ptr %t22
  %t23 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t16, ptr %t23
  %t24 = call ptr @__alloc(i64 8, i32 0)
  %t25 = inttoptr i64 58 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_74(ptr %t12, ptr %t24)
  %t28 = call ptr @v_idemE1()
  %t29 = getelementptr ptr, ptr %t28, i32 0
  %t30 = load ptr, ptr %t29
  %t31 = ptrtoint ptr %t30 to i64
  switch i64 %t31, label %case.default.32 [ i64 3, label %case.arm.3.34 i64 4, label %case.arm.4.42 ]
case.arm.3.34:
  %t36 = call ptr @__alloc(i64 16, i32 1)
  %t37 = inttoptr i64 6 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t28, i32 1
  %t40 = load ptr, ptr %t39
  call void @__inc_ref(ptr %t40)
  %t41 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t40, ptr %t41
  br label %case.end.3.35
case.end.3.35:
  br label %case.join.33
case.arm.4.42:
  %t44 = call ptr @__alloc(i64 16, i32 1)
  %t45 = inttoptr i64 5 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  %t47 = getelementptr ptr, ptr %t28, i32 1
  %t48 = load ptr, ptr %t47
  call void @__inc_ref(ptr %t48)
  %t49 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t48, ptr %t49
  br label %case.end.4.43
case.end.4.43:
  br label %case.join.33
case.default.32:
  unreachable
case.join.33:
  %t50 = phi ptr [ %t36, %case.end.3.35 ], [ %t44, %case.end.4.43 ]
  %t51 = call ptr @__alloc(i64 8, i32 0)
  %t52 = inttoptr i64 32 to ptr
  %t53 = getelementptr ptr, ptr %t51, i32 0
  store ptr %t52, ptr %t53
  %t54 = call ptr @v__cps__df_mapIO_22(ptr %t50, ptr %t51)
  %t55 = call ptr @__alloc(i64 8, i32 0)
  %t56 = inttoptr i64 30 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  %t58 = call ptr @v__cps__df_andThenIO_18(ptr %t54, ptr %t55)
  %t59 = call ptr @__alloc(i64 8, i32 0)
  %t60 = inttoptr i64 28 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  %t62 = call ptr @v__cps__df_handleErrorIO_14(ptr %t58, ptr %t59)
  call void @__free_recursive(ptr %t28)
  %t63 = call ptr @__alloc(i64 8, i32 0)
  %t64 = inttoptr i64 56 to ptr
  %t65 = getelementptr ptr, ptr %t63, i32 0
  store ptr %t64, ptr %t65
  %t66 = call ptr @v__cps__df_andThenIO_70(ptr %t27, ptr %t62, ptr %t63)
  %t67 = call ptr @__alloc(i64 8, i32 0)
  %t68 = inttoptr i64 54 to ptr
  %t69 = getelementptr ptr, ptr %t67, i32 0
  store ptr %t68, ptr %t69
  %t70 = call ptr @v__cps__df_andThenIO_66(ptr %t66, ptr %t67)
  %t71 = call ptr @v__apply__df_andThenIO_106(ptr %t6, ptr %t70)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.72:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t73 = call ptr @v__apply__df_andThenIO_106(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t73, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.74:
  %t75 = getelementptr ptr, ptr %t5, i32 1
  %t76 = load ptr, ptr %t75
  %t77 = getelementptr ptr, ptr %t5, i32 2
  %t78 = load ptr, ptr %t77
  call void @__inc_ref(ptr %t78)
  %t85 = getelementptr i8, ptr %t5, i64 -8
  %t86 = load i32, ptr %t85
  %t87 = icmp eq i32 %t86, 1
  br i1 %t87, label %reuse.in_place.88, label %reuse.copy.89
reuse.in_place.88:
  %t79 = getelementptr ptr, ptr %t5, i32 2
  %t80 = load ptr, ptr %t79
  call void @__free_recursive(ptr %t80)
  %t83 = inttoptr i64 75 to ptr
  %t84 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t83, ptr %t84
  call void @__inc_ref(ptr %t6)
  %t81 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t81
  %t82 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t76, ptr %t82
  br label %reuse.in_place.end.91
reuse.in_place.end.91:
  br label %reuse.join.90
reuse.copy.89:
  %t93 = call ptr @__alloc(i64 24, i32 2)
  %t94 = inttoptr i64 75 to ptr
  %t95 = getelementptr ptr, ptr %t93, i32 0
  store ptr %t94, ptr %t95
  call void @__inc_ref(ptr %t6)
  %t96 = getelementptr ptr, ptr %t93, i32 1
  store ptr %t6, ptr %t96
  call void @__inc_ref(ptr %t76)
  %t97 = getelementptr ptr, ptr %t93, i32 2
  store ptr %t76, ptr %t97
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.92
reuse.copy.end.92:
  br label %reuse.join.90
reuse.join.90:
  %t98 = phi ptr [ %t5, %reuse.in_place.end.91 ], [ %t93, %reuse.copy.end.92 ]
  call void @__inc_ref(ptr %t78)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t78)
  store ptr %t78, ptr %t3
  store ptr %t98, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t99 = load ptr, ptr %t2
  ret ptr %t99
}

define internal ptr @v__apply__df_andThenIO_106(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 74, label %tco.case.arm.74.11 i64 75, label %tco.case.arm.75.12 ]
tco.case.arm.74.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.75.12:
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

define internal ptr @v__cps__df_andThenIO_110(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.72 i64 7, label %tco.case.arm.7.74 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.17, i64 12), ptr %t15
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 5 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = call ptr @__alloc(i64 8, i32 0)
  %t20 = inttoptr i64 0 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t19, ptr %t22
  %t23 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t16, ptr %t23
  %t24 = call ptr @__alloc(i64 8, i32 0)
  %t25 = inttoptr i64 58 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_74(ptr %t12, ptr %t24)
  %t28 = call ptr @v_twoOk()
  %t29 = getelementptr ptr, ptr %t28, i32 0
  %t30 = load ptr, ptr %t29
  %t31 = ptrtoint ptr %t30 to i64
  switch i64 %t31, label %case.default.32 [ i64 3, label %case.arm.3.34 i64 4, label %case.arm.4.42 ]
case.arm.3.34:
  %t36 = call ptr @__alloc(i64 16, i32 1)
  %t37 = inttoptr i64 6 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t28, i32 1
  %t40 = load ptr, ptr %t39
  call void @__inc_ref(ptr %t40)
  %t41 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t40, ptr %t41
  br label %case.end.3.35
case.end.3.35:
  br label %case.join.33
case.arm.4.42:
  %t44 = call ptr @__alloc(i64 16, i32 1)
  %t45 = inttoptr i64 5 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  %t47 = getelementptr ptr, ptr %t28, i32 1
  %t48 = load ptr, ptr %t47
  call void @__inc_ref(ptr %t48)
  %t49 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t48, ptr %t49
  br label %case.end.4.43
case.end.4.43:
  br label %case.join.33
case.default.32:
  unreachable
case.join.33:
  %t50 = phi ptr [ %t36, %case.end.3.35 ], [ %t44, %case.end.4.43 ]
  %t51 = call ptr @__alloc(i64 8, i32 0)
  %t52 = inttoptr i64 32 to ptr
  %t53 = getelementptr ptr, ptr %t51, i32 0
  store ptr %t52, ptr %t53
  %t54 = call ptr @v__cps__df_mapIO_22(ptr %t50, ptr %t51)
  %t55 = call ptr @__alloc(i64 8, i32 0)
  %t56 = inttoptr i64 48 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  %t58 = call ptr @v__cps__df__rowmono_7_andThenIO_54(ptr %t54, ptr %t55)
  %t59 = call ptr @__alloc(i64 8, i32 0)
  %t60 = inttoptr i64 46 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  %t62 = call ptr @v__cps__df_handleErrorIO_50(ptr %t58, ptr %t59)
  call void @__free_recursive(ptr %t28)
  %t63 = call ptr @__alloc(i64 8, i32 0)
  %t64 = inttoptr i64 56 to ptr
  %t65 = getelementptr ptr, ptr %t63, i32 0
  store ptr %t64, ptr %t65
  %t66 = call ptr @v__cps__df_andThenIO_70(ptr %t27, ptr %t62, ptr %t63)
  %t67 = call ptr @__alloc(i64 8, i32 0)
  %t68 = inttoptr i64 54 to ptr
  %t69 = getelementptr ptr, ptr %t67, i32 0
  store ptr %t68, ptr %t69
  %t70 = call ptr @v__cps__df_andThenIO_66(ptr %t66, ptr %t67)
  %t71 = call ptr @v__apply__df_andThenIO_110(ptr %t6, ptr %t70)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.72:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t73 = call ptr @v__apply__df_andThenIO_110(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t73, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.74:
  %t75 = getelementptr ptr, ptr %t5, i32 1
  %t76 = load ptr, ptr %t75
  %t77 = getelementptr ptr, ptr %t5, i32 2
  %t78 = load ptr, ptr %t77
  call void @__inc_ref(ptr %t78)
  %t85 = getelementptr i8, ptr %t5, i64 -8
  %t86 = load i32, ptr %t85
  %t87 = icmp eq i32 %t86, 1
  br i1 %t87, label %reuse.in_place.88, label %reuse.copy.89
reuse.in_place.88:
  %t79 = getelementptr ptr, ptr %t5, i32 2
  %t80 = load ptr, ptr %t79
  call void @__free_recursive(ptr %t80)
  %t83 = inttoptr i64 77 to ptr
  %t84 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t83, ptr %t84
  call void @__inc_ref(ptr %t6)
  %t81 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t81
  %t82 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t76, ptr %t82
  br label %reuse.in_place.end.91
reuse.in_place.end.91:
  br label %reuse.join.90
reuse.copy.89:
  %t93 = call ptr @__alloc(i64 24, i32 2)
  %t94 = inttoptr i64 77 to ptr
  %t95 = getelementptr ptr, ptr %t93, i32 0
  store ptr %t94, ptr %t95
  call void @__inc_ref(ptr %t6)
  %t96 = getelementptr ptr, ptr %t93, i32 1
  store ptr %t6, ptr %t96
  call void @__inc_ref(ptr %t76)
  %t97 = getelementptr ptr, ptr %t93, i32 2
  store ptr %t76, ptr %t97
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.92
reuse.copy.end.92:
  br label %reuse.join.90
reuse.join.90:
  %t98 = phi ptr [ %t5, %reuse.in_place.end.91 ], [ %t93, %reuse.copy.end.92 ]
  call void @__inc_ref(ptr %t78)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t78)
  store ptr %t78, ptr %t3
  store ptr %t98, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t99 = load ptr, ptr %t2
  ret ptr %t99
}

define internal ptr @v__apply__df_andThenIO_110(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 76, label %tco.case.arm.76.11 i64 77, label %tco.case.arm.77.12 ]
tco.case.arm.76.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.77.12:
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

define internal ptr @v__cps__df_andThenIO_114(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.72 i64 7, label %tco.case.arm.7.74 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.18, i64 12), ptr %t15
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 5 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = call ptr @__alloc(i64 8, i32 0)
  %t20 = inttoptr i64 0 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t19, ptr %t22
  %t23 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t16, ptr %t23
  %t24 = call ptr @__alloc(i64 8, i32 0)
  %t25 = inttoptr i64 58 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_74(ptr %t12, ptr %t24)
  %t28 = call ptr @v_twoE2()
  %t29 = getelementptr ptr, ptr %t28, i32 0
  %t30 = load ptr, ptr %t29
  %t31 = ptrtoint ptr %t30 to i64
  switch i64 %t31, label %case.default.32 [ i64 3, label %case.arm.3.34 i64 4, label %case.arm.4.42 ]
case.arm.3.34:
  %t36 = call ptr @__alloc(i64 16, i32 1)
  %t37 = inttoptr i64 6 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t28, i32 1
  %t40 = load ptr, ptr %t39
  call void @__inc_ref(ptr %t40)
  %t41 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t40, ptr %t41
  br label %case.end.3.35
case.end.3.35:
  br label %case.join.33
case.arm.4.42:
  %t44 = call ptr @__alloc(i64 16, i32 1)
  %t45 = inttoptr i64 5 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  %t47 = getelementptr ptr, ptr %t28, i32 1
  %t48 = load ptr, ptr %t47
  call void @__inc_ref(ptr %t48)
  %t49 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t48, ptr %t49
  br label %case.end.4.43
case.end.4.43:
  br label %case.join.33
case.default.32:
  unreachable
case.join.33:
  %t50 = phi ptr [ %t36, %case.end.3.35 ], [ %t44, %case.end.4.43 ]
  %t51 = call ptr @__alloc(i64 8, i32 0)
  %t52 = inttoptr i64 32 to ptr
  %t53 = getelementptr ptr, ptr %t51, i32 0
  store ptr %t52, ptr %t53
  %t54 = call ptr @v__cps__df_mapIO_22(ptr %t50, ptr %t51)
  %t55 = call ptr @__alloc(i64 8, i32 0)
  %t56 = inttoptr i64 48 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  %t58 = call ptr @v__cps__df__rowmono_7_andThenIO_54(ptr %t54, ptr %t55)
  %t59 = call ptr @__alloc(i64 8, i32 0)
  %t60 = inttoptr i64 46 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  %t62 = call ptr @v__cps__df_handleErrorIO_50(ptr %t58, ptr %t59)
  call void @__free_recursive(ptr %t28)
  %t63 = call ptr @__alloc(i64 8, i32 0)
  %t64 = inttoptr i64 56 to ptr
  %t65 = getelementptr ptr, ptr %t63, i32 0
  store ptr %t64, ptr %t65
  %t66 = call ptr @v__cps__df_andThenIO_70(ptr %t27, ptr %t62, ptr %t63)
  %t67 = call ptr @__alloc(i64 8, i32 0)
  %t68 = inttoptr i64 54 to ptr
  %t69 = getelementptr ptr, ptr %t67, i32 0
  store ptr %t68, ptr %t69
  %t70 = call ptr @v__cps__df_andThenIO_66(ptr %t66, ptr %t67)
  %t71 = call ptr @v__apply__df_andThenIO_114(ptr %t6, ptr %t70)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.72:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t73 = call ptr @v__apply__df_andThenIO_114(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t73, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.74:
  %t75 = getelementptr ptr, ptr %t5, i32 1
  %t76 = load ptr, ptr %t75
  %t77 = getelementptr ptr, ptr %t5, i32 2
  %t78 = load ptr, ptr %t77
  call void @__inc_ref(ptr %t78)
  %t85 = getelementptr i8, ptr %t5, i64 -8
  %t86 = load i32, ptr %t85
  %t87 = icmp eq i32 %t86, 1
  br i1 %t87, label %reuse.in_place.88, label %reuse.copy.89
reuse.in_place.88:
  %t79 = getelementptr ptr, ptr %t5, i32 2
  %t80 = load ptr, ptr %t79
  call void @__free_recursive(ptr %t80)
  %t83 = inttoptr i64 79 to ptr
  %t84 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t83, ptr %t84
  call void @__inc_ref(ptr %t6)
  %t81 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t81
  %t82 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t76, ptr %t82
  br label %reuse.in_place.end.91
reuse.in_place.end.91:
  br label %reuse.join.90
reuse.copy.89:
  %t93 = call ptr @__alloc(i64 24, i32 2)
  %t94 = inttoptr i64 79 to ptr
  %t95 = getelementptr ptr, ptr %t93, i32 0
  store ptr %t94, ptr %t95
  call void @__inc_ref(ptr %t6)
  %t96 = getelementptr ptr, ptr %t93, i32 1
  store ptr %t6, ptr %t96
  call void @__inc_ref(ptr %t76)
  %t97 = getelementptr ptr, ptr %t93, i32 2
  store ptr %t76, ptr %t97
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.92
reuse.copy.end.92:
  br label %reuse.join.90
reuse.join.90:
  %t98 = phi ptr [ %t5, %reuse.in_place.end.91 ], [ %t93, %reuse.copy.end.92 ]
  call void @__inc_ref(ptr %t78)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t78)
  store ptr %t78, ptr %t3
  store ptr %t98, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t99 = load ptr, ptr %t2
  ret ptr %t99
}

define internal ptr @v__apply__df_andThenIO_114(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 78, label %tco.case.arm.78.11 i64 79, label %tco.case.arm.79.12 ]
tco.case.arm.78.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.79.12:
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

define internal ptr @v__cps__df_andThenIO_118(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.72 i64 7, label %tco.case.arm.7.74 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.19, i64 12), ptr %t15
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 5 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = call ptr @__alloc(i64 8, i32 0)
  %t20 = inttoptr i64 0 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t19, ptr %t22
  %t23 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t16, ptr %t23
  %t24 = call ptr @__alloc(i64 8, i32 0)
  %t25 = inttoptr i64 58 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_74(ptr %t12, ptr %t24)
  %t28 = call ptr @v_twoSecond()
  %t29 = getelementptr ptr, ptr %t28, i32 0
  %t30 = load ptr, ptr %t29
  %t31 = ptrtoint ptr %t30 to i64
  switch i64 %t31, label %case.default.32 [ i64 3, label %case.arm.3.34 i64 4, label %case.arm.4.42 ]
case.arm.3.34:
  %t36 = call ptr @__alloc(i64 16, i32 1)
  %t37 = inttoptr i64 6 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t28, i32 1
  %t40 = load ptr, ptr %t39
  call void @__inc_ref(ptr %t40)
  %t41 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t40, ptr %t41
  br label %case.end.3.35
case.end.3.35:
  br label %case.join.33
case.arm.4.42:
  %t44 = call ptr @__alloc(i64 16, i32 1)
  %t45 = inttoptr i64 5 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  %t47 = getelementptr ptr, ptr %t28, i32 1
  %t48 = load ptr, ptr %t47
  call void @__inc_ref(ptr %t48)
  %t49 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t48, ptr %t49
  br label %case.end.4.43
case.end.4.43:
  br label %case.join.33
case.default.32:
  unreachable
case.join.33:
  %t50 = phi ptr [ %t36, %case.end.3.35 ], [ %t44, %case.end.4.43 ]
  %t51 = call ptr @__alloc(i64 8, i32 0)
  %t52 = inttoptr i64 32 to ptr
  %t53 = getelementptr ptr, ptr %t51, i32 0
  store ptr %t52, ptr %t53
  %t54 = call ptr @v__cps__df_mapIO_22(ptr %t50, ptr %t51)
  %t55 = call ptr @__alloc(i64 8, i32 0)
  %t56 = inttoptr i64 48 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  %t58 = call ptr @v__cps__df__rowmono_7_andThenIO_54(ptr %t54, ptr %t55)
  %t59 = call ptr @__alloc(i64 8, i32 0)
  %t60 = inttoptr i64 46 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  %t62 = call ptr @v__cps__df_handleErrorIO_50(ptr %t58, ptr %t59)
  call void @__free_recursive(ptr %t28)
  %t63 = call ptr @__alloc(i64 8, i32 0)
  %t64 = inttoptr i64 56 to ptr
  %t65 = getelementptr ptr, ptr %t63, i32 0
  store ptr %t64, ptr %t65
  %t66 = call ptr @v__cps__df_andThenIO_70(ptr %t27, ptr %t62, ptr %t63)
  %t67 = call ptr @__alloc(i64 8, i32 0)
  %t68 = inttoptr i64 54 to ptr
  %t69 = getelementptr ptr, ptr %t67, i32 0
  store ptr %t68, ptr %t69
  %t70 = call ptr @v__cps__df_andThenIO_66(ptr %t66, ptr %t67)
  %t71 = call ptr @v__apply__df_andThenIO_118(ptr %t6, ptr %t70)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.72:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t73 = call ptr @v__apply__df_andThenIO_118(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t73, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.74:
  %t75 = getelementptr ptr, ptr %t5, i32 1
  %t76 = load ptr, ptr %t75
  %t77 = getelementptr ptr, ptr %t5, i32 2
  %t78 = load ptr, ptr %t77
  call void @__inc_ref(ptr %t78)
  %t85 = getelementptr i8, ptr %t5, i64 -8
  %t86 = load i32, ptr %t85
  %t87 = icmp eq i32 %t86, 1
  br i1 %t87, label %reuse.in_place.88, label %reuse.copy.89
reuse.in_place.88:
  %t79 = getelementptr ptr, ptr %t5, i32 2
  %t80 = load ptr, ptr %t79
  call void @__free_recursive(ptr %t80)
  %t83 = inttoptr i64 81 to ptr
  %t84 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t83, ptr %t84
  call void @__inc_ref(ptr %t6)
  %t81 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t81
  %t82 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t76, ptr %t82
  br label %reuse.in_place.end.91
reuse.in_place.end.91:
  br label %reuse.join.90
reuse.copy.89:
  %t93 = call ptr @__alloc(i64 24, i32 2)
  %t94 = inttoptr i64 81 to ptr
  %t95 = getelementptr ptr, ptr %t93, i32 0
  store ptr %t94, ptr %t95
  call void @__inc_ref(ptr %t6)
  %t96 = getelementptr ptr, ptr %t93, i32 1
  store ptr %t6, ptr %t96
  call void @__inc_ref(ptr %t76)
  %t97 = getelementptr ptr, ptr %t93, i32 2
  store ptr %t76, ptr %t97
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.92
reuse.copy.end.92:
  br label %reuse.join.90
reuse.join.90:
  %t98 = phi ptr [ %t5, %reuse.in_place.end.91 ], [ %t93, %reuse.copy.end.92 ]
  call void @__inc_ref(ptr %t78)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t78)
  store ptr %t78, ptr %t3
  store ptr %t98, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t99 = load ptr, ptr %t2
  ret ptr %t99
}

define internal ptr @v__apply__df_andThenIO_118(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 80, label %tco.case.arm.80.11 i64 81, label %tco.case.arm.81.12 ]
tco.case.arm.80.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.81.12:
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

define internal ptr @v__cps__df_andThenIO_122(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.72 i64 7, label %tco.case.arm.7.74 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.20, i64 12), ptr %t15
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 5 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = call ptr @__alloc(i64 8, i32 0)
  %t20 = inttoptr i64 0 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t19, ptr %t22
  %t23 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t16, ptr %t23
  %t24 = call ptr @__alloc(i64 8, i32 0)
  %t25 = inttoptr i64 58 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_74(ptr %t12, ptr %t24)
  %t28 = call ptr @v_twoFirst()
  %t29 = getelementptr ptr, ptr %t28, i32 0
  %t30 = load ptr, ptr %t29
  %t31 = ptrtoint ptr %t30 to i64
  switch i64 %t31, label %case.default.32 [ i64 3, label %case.arm.3.34 i64 4, label %case.arm.4.42 ]
case.arm.3.34:
  %t36 = call ptr @__alloc(i64 16, i32 1)
  %t37 = inttoptr i64 6 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t28, i32 1
  %t40 = load ptr, ptr %t39
  call void @__inc_ref(ptr %t40)
  %t41 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t40, ptr %t41
  br label %case.end.3.35
case.end.3.35:
  br label %case.join.33
case.arm.4.42:
  %t44 = call ptr @__alloc(i64 16, i32 1)
  %t45 = inttoptr i64 5 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  %t47 = getelementptr ptr, ptr %t28, i32 1
  %t48 = load ptr, ptr %t47
  call void @__inc_ref(ptr %t48)
  %t49 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t48, ptr %t49
  br label %case.end.4.43
case.end.4.43:
  br label %case.join.33
case.default.32:
  unreachable
case.join.33:
  %t50 = phi ptr [ %t36, %case.end.3.35 ], [ %t44, %case.end.4.43 ]
  %t51 = call ptr @__alloc(i64 8, i32 0)
  %t52 = inttoptr i64 32 to ptr
  %t53 = getelementptr ptr, ptr %t51, i32 0
  store ptr %t52, ptr %t53
  %t54 = call ptr @v__cps__df_mapIO_22(ptr %t50, ptr %t51)
  %t55 = call ptr @__alloc(i64 8, i32 0)
  %t56 = inttoptr i64 48 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  %t58 = call ptr @v__cps__df__rowmono_7_andThenIO_54(ptr %t54, ptr %t55)
  %t59 = call ptr @__alloc(i64 8, i32 0)
  %t60 = inttoptr i64 46 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  %t62 = call ptr @v__cps__df_handleErrorIO_50(ptr %t58, ptr %t59)
  call void @__free_recursive(ptr %t28)
  %t63 = call ptr @__alloc(i64 8, i32 0)
  %t64 = inttoptr i64 56 to ptr
  %t65 = getelementptr ptr, ptr %t63, i32 0
  store ptr %t64, ptr %t65
  %t66 = call ptr @v__cps__df_andThenIO_70(ptr %t27, ptr %t62, ptr %t63)
  %t67 = call ptr @__alloc(i64 8, i32 0)
  %t68 = inttoptr i64 54 to ptr
  %t69 = getelementptr ptr, ptr %t67, i32 0
  store ptr %t68, ptr %t69
  %t70 = call ptr @v__cps__df_andThenIO_66(ptr %t66, ptr %t67)
  %t71 = call ptr @v__apply__df_andThenIO_122(ptr %t6, ptr %t70)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.72:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t73 = call ptr @v__apply__df_andThenIO_122(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t73, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.74:
  %t75 = getelementptr ptr, ptr %t5, i32 1
  %t76 = load ptr, ptr %t75
  %t77 = getelementptr ptr, ptr %t5, i32 2
  %t78 = load ptr, ptr %t77
  call void @__inc_ref(ptr %t78)
  %t85 = getelementptr i8, ptr %t5, i64 -8
  %t86 = load i32, ptr %t85
  %t87 = icmp eq i32 %t86, 1
  br i1 %t87, label %reuse.in_place.88, label %reuse.copy.89
reuse.in_place.88:
  %t79 = getelementptr ptr, ptr %t5, i32 2
  %t80 = load ptr, ptr %t79
  call void @__free_recursive(ptr %t80)
  %t83 = inttoptr i64 83 to ptr
  %t84 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t83, ptr %t84
  call void @__inc_ref(ptr %t6)
  %t81 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t81
  %t82 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t76, ptr %t82
  br label %reuse.in_place.end.91
reuse.in_place.end.91:
  br label %reuse.join.90
reuse.copy.89:
  %t93 = call ptr @__alloc(i64 24, i32 2)
  %t94 = inttoptr i64 83 to ptr
  %t95 = getelementptr ptr, ptr %t93, i32 0
  store ptr %t94, ptr %t95
  call void @__inc_ref(ptr %t6)
  %t96 = getelementptr ptr, ptr %t93, i32 1
  store ptr %t6, ptr %t96
  call void @__inc_ref(ptr %t76)
  %t97 = getelementptr ptr, ptr %t93, i32 2
  store ptr %t76, ptr %t97
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.92
reuse.copy.end.92:
  br label %reuse.join.90
reuse.join.90:
  %t98 = phi ptr [ %t5, %reuse.in_place.end.91 ], [ %t93, %reuse.copy.end.92 ]
  call void @__inc_ref(ptr %t78)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t78)
  store ptr %t78, ptr %t3
  store ptr %t98, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t99 = load ptr, ptr %t2
  ret ptr %t99
}

define internal ptr @v__apply__df_andThenIO_122(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 82, label %tco.case.arm.82.11 i64 83, label %tco.case.arm.83.12 ]
tco.case.arm.82.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.83.12:
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

define internal ptr @v__cps__df_andThenIO_126(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.72 i64 7, label %tco.case.arm.7.74 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.21, i64 12), ptr %t15
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 5 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = call ptr @__alloc(i64 8, i32 0)
  %t20 = inttoptr i64 0 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t19, ptr %t22
  %t23 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t16, ptr %t23
  %t24 = call ptr @__alloc(i64 8, i32 0)
  %t25 = inttoptr i64 58 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_74(ptr %t12, ptr %t24)
  %t28 = call ptr @v_abE2()
  %t29 = getelementptr ptr, ptr %t28, i32 0
  %t30 = load ptr, ptr %t29
  %t31 = ptrtoint ptr %t30 to i64
  switch i64 %t31, label %case.default.32 [ i64 3, label %case.arm.3.34 i64 4, label %case.arm.4.42 ]
case.arm.3.34:
  %t36 = call ptr @__alloc(i64 16, i32 1)
  %t37 = inttoptr i64 6 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t28, i32 1
  %t40 = load ptr, ptr %t39
  call void @__inc_ref(ptr %t40)
  %t41 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t40, ptr %t41
  br label %case.end.3.35
case.end.3.35:
  br label %case.join.33
case.arm.4.42:
  %t44 = call ptr @__alloc(i64 16, i32 1)
  %t45 = inttoptr i64 5 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  %t47 = getelementptr ptr, ptr %t28, i32 1
  %t48 = load ptr, ptr %t47
  call void @__inc_ref(ptr %t48)
  %t49 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t48, ptr %t49
  br label %case.end.4.43
case.end.4.43:
  br label %case.join.33
case.default.32:
  unreachable
case.join.33:
  %t50 = phi ptr [ %t36, %case.end.3.35 ], [ %t44, %case.end.4.43 ]
  %t51 = call ptr @__alloc(i64 8, i32 0)
  %t52 = inttoptr i64 32 to ptr
  %t53 = getelementptr ptr, ptr %t51, i32 0
  store ptr %t52, ptr %t53
  %t54 = call ptr @v__cps__df_mapIO_22(ptr %t50, ptr %t51)
  %t55 = call ptr @__alloc(i64 8, i32 0)
  %t56 = inttoptr i64 44 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  %t58 = call ptr @v__cps__df__rowmono_6_andThenIO_46(ptr %t54, ptr %t55)
  %t59 = call ptr @__alloc(i64 8, i32 0)
  %t60 = inttoptr i64 42 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  %t62 = call ptr @v__cps__df_handleErrorIO_42(ptr %t58, ptr %t59)
  call void @__free_recursive(ptr %t28)
  %t63 = call ptr @__alloc(i64 8, i32 0)
  %t64 = inttoptr i64 56 to ptr
  %t65 = getelementptr ptr, ptr %t63, i32 0
  store ptr %t64, ptr %t65
  %t66 = call ptr @v__cps__df_andThenIO_70(ptr %t27, ptr %t62, ptr %t63)
  %t67 = call ptr @__alloc(i64 8, i32 0)
  %t68 = inttoptr i64 54 to ptr
  %t69 = getelementptr ptr, ptr %t67, i32 0
  store ptr %t68, ptr %t69
  %t70 = call ptr @v__cps__df_andThenIO_66(ptr %t66, ptr %t67)
  %t71 = call ptr @v__apply__df_andThenIO_126(ptr %t6, ptr %t70)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.72:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t73 = call ptr @v__apply__df_andThenIO_126(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t73, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.74:
  %t75 = getelementptr ptr, ptr %t5, i32 1
  %t76 = load ptr, ptr %t75
  %t77 = getelementptr ptr, ptr %t5, i32 2
  %t78 = load ptr, ptr %t77
  call void @__inc_ref(ptr %t78)
  %t85 = getelementptr i8, ptr %t5, i64 -8
  %t86 = load i32, ptr %t85
  %t87 = icmp eq i32 %t86, 1
  br i1 %t87, label %reuse.in_place.88, label %reuse.copy.89
reuse.in_place.88:
  %t79 = getelementptr ptr, ptr %t5, i32 2
  %t80 = load ptr, ptr %t79
  call void @__free_recursive(ptr %t80)
  %t83 = inttoptr i64 85 to ptr
  %t84 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t83, ptr %t84
  call void @__inc_ref(ptr %t6)
  %t81 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t81
  %t82 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t76, ptr %t82
  br label %reuse.in_place.end.91
reuse.in_place.end.91:
  br label %reuse.join.90
reuse.copy.89:
  %t93 = call ptr @__alloc(i64 24, i32 2)
  %t94 = inttoptr i64 85 to ptr
  %t95 = getelementptr ptr, ptr %t93, i32 0
  store ptr %t94, ptr %t95
  call void @__inc_ref(ptr %t6)
  %t96 = getelementptr ptr, ptr %t93, i32 1
  store ptr %t6, ptr %t96
  call void @__inc_ref(ptr %t76)
  %t97 = getelementptr ptr, ptr %t93, i32 2
  store ptr %t76, ptr %t97
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.92
reuse.copy.end.92:
  br label %reuse.join.90
reuse.join.90:
  %t98 = phi ptr [ %t5, %reuse.in_place.end.91 ], [ %t93, %reuse.copy.end.92 ]
  call void @__inc_ref(ptr %t78)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t78)
  store ptr %t78, ptr %t3
  store ptr %t98, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t99 = load ptr, ptr %t2
  ret ptr %t99
}

define internal ptr @v__apply__df_andThenIO_126(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 84, label %tco.case.arm.84.11 i64 85, label %tco.case.arm.85.12 ]
tco.case.arm.84.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.85.12:
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

define internal ptr @v__cps__df_andThenIO_130(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.72 i64 7, label %tco.case.arm.7.74 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.22, i64 12), ptr %t15
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 5 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = call ptr @__alloc(i64 8, i32 0)
  %t20 = inttoptr i64 0 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t19, ptr %t22
  %t23 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t16, ptr %t23
  %t24 = call ptr @__alloc(i64 8, i32 0)
  %t25 = inttoptr i64 58 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_74(ptr %t12, ptr %t24)
  %t28 = call ptr @v_abE1()
  %t29 = getelementptr ptr, ptr %t28, i32 0
  %t30 = load ptr, ptr %t29
  %t31 = ptrtoint ptr %t30 to i64
  switch i64 %t31, label %case.default.32 [ i64 3, label %case.arm.3.34 i64 4, label %case.arm.4.42 ]
case.arm.3.34:
  %t36 = call ptr @__alloc(i64 16, i32 1)
  %t37 = inttoptr i64 6 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t28, i32 1
  %t40 = load ptr, ptr %t39
  call void @__inc_ref(ptr %t40)
  %t41 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t40, ptr %t41
  br label %case.end.3.35
case.end.3.35:
  br label %case.join.33
case.arm.4.42:
  %t44 = call ptr @__alloc(i64 16, i32 1)
  %t45 = inttoptr i64 5 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  %t47 = getelementptr ptr, ptr %t28, i32 1
  %t48 = load ptr, ptr %t47
  call void @__inc_ref(ptr %t48)
  %t49 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t48, ptr %t49
  br label %case.end.4.43
case.end.4.43:
  br label %case.join.33
case.default.32:
  unreachable
case.join.33:
  %t50 = phi ptr [ %t36, %case.end.3.35 ], [ %t44, %case.end.4.43 ]
  %t51 = call ptr @__alloc(i64 8, i32 0)
  %t52 = inttoptr i64 32 to ptr
  %t53 = getelementptr ptr, ptr %t51, i32 0
  store ptr %t52, ptr %t53
  %t54 = call ptr @v__cps__df_mapIO_22(ptr %t50, ptr %t51)
  %t55 = call ptr @__alloc(i64 8, i32 0)
  %t56 = inttoptr i64 44 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  %t58 = call ptr @v__cps__df__rowmono_6_andThenIO_46(ptr %t54, ptr %t55)
  %t59 = call ptr @__alloc(i64 8, i32 0)
  %t60 = inttoptr i64 42 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  %t62 = call ptr @v__cps__df_handleErrorIO_42(ptr %t58, ptr %t59)
  call void @__free_recursive(ptr %t28)
  %t63 = call ptr @__alloc(i64 8, i32 0)
  %t64 = inttoptr i64 56 to ptr
  %t65 = getelementptr ptr, ptr %t63, i32 0
  store ptr %t64, ptr %t65
  %t66 = call ptr @v__cps__df_andThenIO_70(ptr %t27, ptr %t62, ptr %t63)
  %t67 = call ptr @__alloc(i64 8, i32 0)
  %t68 = inttoptr i64 54 to ptr
  %t69 = getelementptr ptr, ptr %t67, i32 0
  store ptr %t68, ptr %t69
  %t70 = call ptr @v__cps__df_andThenIO_66(ptr %t66, ptr %t67)
  %t71 = call ptr @v__apply__df_andThenIO_130(ptr %t6, ptr %t70)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.72:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t73 = call ptr @v__apply__df_andThenIO_130(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t73, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.74:
  %t75 = getelementptr ptr, ptr %t5, i32 1
  %t76 = load ptr, ptr %t75
  %t77 = getelementptr ptr, ptr %t5, i32 2
  %t78 = load ptr, ptr %t77
  call void @__inc_ref(ptr %t78)
  %t85 = getelementptr i8, ptr %t5, i64 -8
  %t86 = load i32, ptr %t85
  %t87 = icmp eq i32 %t86, 1
  br i1 %t87, label %reuse.in_place.88, label %reuse.copy.89
reuse.in_place.88:
  %t79 = getelementptr ptr, ptr %t5, i32 2
  %t80 = load ptr, ptr %t79
  call void @__free_recursive(ptr %t80)
  %t83 = inttoptr i64 87 to ptr
  %t84 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t83, ptr %t84
  call void @__inc_ref(ptr %t6)
  %t81 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t81
  %t82 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t76, ptr %t82
  br label %reuse.in_place.end.91
reuse.in_place.end.91:
  br label %reuse.join.90
reuse.copy.89:
  %t93 = call ptr @__alloc(i64 24, i32 2)
  %t94 = inttoptr i64 87 to ptr
  %t95 = getelementptr ptr, ptr %t93, i32 0
  store ptr %t94, ptr %t95
  call void @__inc_ref(ptr %t6)
  %t96 = getelementptr ptr, ptr %t93, i32 1
  store ptr %t6, ptr %t96
  call void @__inc_ref(ptr %t76)
  %t97 = getelementptr ptr, ptr %t93, i32 2
  store ptr %t76, ptr %t97
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.92
reuse.copy.end.92:
  br label %reuse.join.90
reuse.join.90:
  %t98 = phi ptr [ %t5, %reuse.in_place.end.91 ], [ %t93, %reuse.copy.end.92 ]
  call void @__inc_ref(ptr %t78)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t78)
  store ptr %t78, ptr %t3
  store ptr %t98, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t99 = load ptr, ptr %t2
  ret ptr %t99
}

define internal ptr @v__apply__df_andThenIO_130(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 86, label %tco.case.arm.86.11 i64 87, label %tco.case.arm.87.12 ]
tco.case.arm.86.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.87.12:
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

define internal ptr @v__cps__df_andThenIO_134(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.72 i64 7, label %tco.case.arm.7.74 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.23, i64 12), ptr %t15
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 5 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = call ptr @__alloc(i64 8, i32 0)
  %t20 = inttoptr i64 0 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t19, ptr %t22
  %t23 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t16, ptr %t23
  %t24 = call ptr @__alloc(i64 8, i32 0)
  %t25 = inttoptr i64 58 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_74(ptr %t12, ptr %t24)
  %t28 = call ptr @v_strIdem()
  %t29 = getelementptr ptr, ptr %t28, i32 0
  %t30 = load ptr, ptr %t29
  %t31 = ptrtoint ptr %t30 to i64
  switch i64 %t31, label %case.default.32 [ i64 3, label %case.arm.3.34 i64 4, label %case.arm.4.42 ]
case.arm.3.34:
  %t36 = call ptr @__alloc(i64 16, i32 1)
  %t37 = inttoptr i64 6 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t28, i32 1
  %t40 = load ptr, ptr %t39
  call void @__inc_ref(ptr %t40)
  %t41 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t40, ptr %t41
  br label %case.end.3.35
case.end.3.35:
  br label %case.join.33
case.arm.4.42:
  %t44 = call ptr @__alloc(i64 16, i32 1)
  %t45 = inttoptr i64 5 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  %t47 = getelementptr ptr, ptr %t28, i32 1
  %t48 = load ptr, ptr %t47
  call void @__inc_ref(ptr %t48)
  %t49 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t48, ptr %t49
  br label %case.end.4.43
case.end.4.43:
  br label %case.join.33
case.default.32:
  unreachable
case.join.33:
  %t50 = phi ptr [ %t36, %case.end.3.35 ], [ %t44, %case.end.4.43 ]
  %t51 = call ptr @__alloc(i64 8, i32 0)
  %t52 = inttoptr i64 32 to ptr
  %t53 = getelementptr ptr, ptr %t51, i32 0
  store ptr %t52, ptr %t53
  %t54 = call ptr @v__cps__df_mapIO_22(ptr %t50, ptr %t51)
  %t55 = call ptr @__alloc(i64 8, i32 0)
  %t56 = inttoptr i64 30 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  %t58 = call ptr @v__cps__df_andThenIO_18(ptr %t54, ptr %t55)
  %t59 = call ptr @__alloc(i64 8, i32 0)
  %t60 = inttoptr i64 36 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  %t62 = call ptr @v__cps__df_handleErrorIO_30(ptr %t58, ptr %t59)
  call void @__free_recursive(ptr %t28)
  %t63 = call ptr @__alloc(i64 8, i32 0)
  %t64 = inttoptr i64 56 to ptr
  %t65 = getelementptr ptr, ptr %t63, i32 0
  store ptr %t64, ptr %t65
  %t66 = call ptr @v__cps__df_andThenIO_70(ptr %t27, ptr %t62, ptr %t63)
  %t67 = call ptr @__alloc(i64 8, i32 0)
  %t68 = inttoptr i64 54 to ptr
  %t69 = getelementptr ptr, ptr %t67, i32 0
  store ptr %t68, ptr %t69
  %t70 = call ptr @v__cps__df_andThenIO_66(ptr %t66, ptr %t67)
  %t71 = call ptr @v__apply__df_andThenIO_134(ptr %t6, ptr %t70)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.72:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t73 = call ptr @v__apply__df_andThenIO_134(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t73, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.74:
  %t75 = getelementptr ptr, ptr %t5, i32 1
  %t76 = load ptr, ptr %t75
  %t77 = getelementptr ptr, ptr %t5, i32 2
  %t78 = load ptr, ptr %t77
  call void @__inc_ref(ptr %t78)
  %t85 = getelementptr i8, ptr %t5, i64 -8
  %t86 = load i32, ptr %t85
  %t87 = icmp eq i32 %t86, 1
  br i1 %t87, label %reuse.in_place.88, label %reuse.copy.89
reuse.in_place.88:
  %t79 = getelementptr ptr, ptr %t5, i32 2
  %t80 = load ptr, ptr %t79
  call void @__free_recursive(ptr %t80)
  %t83 = inttoptr i64 89 to ptr
  %t84 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t83, ptr %t84
  call void @__inc_ref(ptr %t6)
  %t81 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t81
  %t82 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t76, ptr %t82
  br label %reuse.in_place.end.91
reuse.in_place.end.91:
  br label %reuse.join.90
reuse.copy.89:
  %t93 = call ptr @__alloc(i64 24, i32 2)
  %t94 = inttoptr i64 89 to ptr
  %t95 = getelementptr ptr, ptr %t93, i32 0
  store ptr %t94, ptr %t95
  call void @__inc_ref(ptr %t6)
  %t96 = getelementptr ptr, ptr %t93, i32 1
  store ptr %t6, ptr %t96
  call void @__inc_ref(ptr %t76)
  %t97 = getelementptr ptr, ptr %t93, i32 2
  store ptr %t76, ptr %t97
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.92
reuse.copy.end.92:
  br label %reuse.join.90
reuse.join.90:
  %t98 = phi ptr [ %t5, %reuse.in_place.end.91 ], [ %t93, %reuse.copy.end.92 ]
  call void @__inc_ref(ptr %t78)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t78)
  store ptr %t78, ptr %t3
  store ptr %t98, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t99 = load ptr, ptr %t2
  ret ptr %t99
}

define internal ptr @v__apply__df_andThenIO_134(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 88, label %tco.case.arm.88.11 i64 89, label %tco.case.arm.89.12 ]
tco.case.arm.88.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.89.12:
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

define internal ptr @v__cps__df_andThenIO_138(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.72 i64 7, label %tco.case.arm.7.74 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.24, i64 12), ptr %t15
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 5 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = call ptr @__alloc(i64 8, i32 0)
  %t20 = inttoptr i64 0 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t19, ptr %t22
  %t23 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t16, ptr %t23
  %t24 = call ptr @__alloc(i64 8, i32 0)
  %t25 = inttoptr i64 58 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_74(ptr %t12, ptr %t24)
  %t28 = call ptr @v_strE2()
  %t29 = getelementptr ptr, ptr %t28, i32 0
  %t30 = load ptr, ptr %t29
  %t31 = ptrtoint ptr %t30 to i64
  switch i64 %t31, label %case.default.32 [ i64 3, label %case.arm.3.34 i64 4, label %case.arm.4.42 ]
case.arm.3.34:
  %t36 = call ptr @__alloc(i64 16, i32 1)
  %t37 = inttoptr i64 6 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t28, i32 1
  %t40 = load ptr, ptr %t39
  call void @__inc_ref(ptr %t40)
  %t41 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t40, ptr %t41
  br label %case.end.3.35
case.end.3.35:
  br label %case.join.33
case.arm.4.42:
  %t44 = call ptr @__alloc(i64 16, i32 1)
  %t45 = inttoptr i64 5 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  %t47 = getelementptr ptr, ptr %t28, i32 1
  %t48 = load ptr, ptr %t47
  call void @__inc_ref(ptr %t48)
  %t49 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t48, ptr %t49
  br label %case.end.4.43
case.end.4.43:
  br label %case.join.33
case.default.32:
  unreachable
case.join.33:
  %t50 = phi ptr [ %t36, %case.end.3.35 ], [ %t44, %case.end.4.43 ]
  %t51 = call ptr @__alloc(i64 8, i32 0)
  %t52 = inttoptr i64 32 to ptr
  %t53 = getelementptr ptr, ptr %t51, i32 0
  store ptr %t52, ptr %t53
  %t54 = call ptr @v__cps__df_mapIO_22(ptr %t50, ptr %t51)
  %t55 = call ptr @__alloc(i64 8, i32 0)
  %t56 = inttoptr i64 40 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  %t58 = call ptr @v__cps__df__rowmono_5_andThenIO_38(ptr %t54, ptr %t55)
  %t59 = call ptr @__alloc(i64 8, i32 0)
  %t60 = inttoptr i64 38 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  %t62 = call ptr @v__cps__df_handleErrorIO_34(ptr %t58, ptr %t59)
  call void @__free_recursive(ptr %t28)
  %t63 = call ptr @__alloc(i64 8, i32 0)
  %t64 = inttoptr i64 56 to ptr
  %t65 = getelementptr ptr, ptr %t63, i32 0
  store ptr %t64, ptr %t65
  %t66 = call ptr @v__cps__df_andThenIO_70(ptr %t27, ptr %t62, ptr %t63)
  %t67 = call ptr @__alloc(i64 8, i32 0)
  %t68 = inttoptr i64 54 to ptr
  %t69 = getelementptr ptr, ptr %t67, i32 0
  store ptr %t68, ptr %t69
  %t70 = call ptr @v__cps__df_andThenIO_66(ptr %t66, ptr %t67)
  %t71 = call ptr @v__apply__df_andThenIO_138(ptr %t6, ptr %t70)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.72:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t73 = call ptr @v__apply__df_andThenIO_138(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t73, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.74:
  %t75 = getelementptr ptr, ptr %t5, i32 1
  %t76 = load ptr, ptr %t75
  %t77 = getelementptr ptr, ptr %t5, i32 2
  %t78 = load ptr, ptr %t77
  call void @__inc_ref(ptr %t78)
  %t85 = getelementptr i8, ptr %t5, i64 -8
  %t86 = load i32, ptr %t85
  %t87 = icmp eq i32 %t86, 1
  br i1 %t87, label %reuse.in_place.88, label %reuse.copy.89
reuse.in_place.88:
  %t79 = getelementptr ptr, ptr %t5, i32 2
  %t80 = load ptr, ptr %t79
  call void @__free_recursive(ptr %t80)
  %t83 = inttoptr i64 91 to ptr
  %t84 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t83, ptr %t84
  call void @__inc_ref(ptr %t6)
  %t81 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t81
  %t82 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t76, ptr %t82
  br label %reuse.in_place.end.91
reuse.in_place.end.91:
  br label %reuse.join.90
reuse.copy.89:
  %t93 = call ptr @__alloc(i64 24, i32 2)
  %t94 = inttoptr i64 91 to ptr
  %t95 = getelementptr ptr, ptr %t93, i32 0
  store ptr %t94, ptr %t95
  call void @__inc_ref(ptr %t6)
  %t96 = getelementptr ptr, ptr %t93, i32 1
  store ptr %t6, ptr %t96
  call void @__inc_ref(ptr %t76)
  %t97 = getelementptr ptr, ptr %t93, i32 2
  store ptr %t76, ptr %t97
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.92
reuse.copy.end.92:
  br label %reuse.join.90
reuse.join.90:
  %t98 = phi ptr [ %t5, %reuse.in_place.end.91 ], [ %t93, %reuse.copy.end.92 ]
  call void @__inc_ref(ptr %t78)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t78)
  store ptr %t78, ptr %t3
  store ptr %t98, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t99 = load ptr, ptr %t2
  ret ptr %t99
}

define internal ptr @v__apply__df_andThenIO_138(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 90, label %tco.case.arm.90.11 i64 91, label %tco.case.arm.91.12 ]
tco.case.arm.90.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.91.12:
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

define internal ptr @v__cps__df_andThenIO_142(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.72 i64 7, label %tco.case.arm.7.74 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.25, i64 12), ptr %t15
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 5 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = call ptr @__alloc(i64 8, i32 0)
  %t20 = inttoptr i64 0 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t19, ptr %t22
  %t23 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t16, ptr %t23
  %t24 = call ptr @__alloc(i64 8, i32 0)
  %t25 = inttoptr i64 58 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_74(ptr %t12, ptr %t24)
  %t28 = call ptr @v_strE1()
  %t29 = getelementptr ptr, ptr %t28, i32 0
  %t30 = load ptr, ptr %t29
  %t31 = ptrtoint ptr %t30 to i64
  switch i64 %t31, label %case.default.32 [ i64 3, label %case.arm.3.34 i64 4, label %case.arm.4.42 ]
case.arm.3.34:
  %t36 = call ptr @__alloc(i64 16, i32 1)
  %t37 = inttoptr i64 6 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t28, i32 1
  %t40 = load ptr, ptr %t39
  call void @__inc_ref(ptr %t40)
  %t41 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t40, ptr %t41
  br label %case.end.3.35
case.end.3.35:
  br label %case.join.33
case.arm.4.42:
  %t44 = call ptr @__alloc(i64 16, i32 1)
  %t45 = inttoptr i64 5 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  %t47 = getelementptr ptr, ptr %t28, i32 1
  %t48 = load ptr, ptr %t47
  call void @__inc_ref(ptr %t48)
  %t49 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t48, ptr %t49
  br label %case.end.4.43
case.end.4.43:
  br label %case.join.33
case.default.32:
  unreachable
case.join.33:
  %t50 = phi ptr [ %t36, %case.end.3.35 ], [ %t44, %case.end.4.43 ]
  %t51 = call ptr @__alloc(i64 8, i32 0)
  %t52 = inttoptr i64 32 to ptr
  %t53 = getelementptr ptr, ptr %t51, i32 0
  store ptr %t52, ptr %t53
  %t54 = call ptr @v__cps__df_mapIO_22(ptr %t50, ptr %t51)
  %t55 = call ptr @__alloc(i64 8, i32 0)
  %t56 = inttoptr i64 40 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  %t58 = call ptr @v__cps__df__rowmono_5_andThenIO_38(ptr %t54, ptr %t55)
  %t59 = call ptr @__alloc(i64 8, i32 0)
  %t60 = inttoptr i64 38 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  %t62 = call ptr @v__cps__df_handleErrorIO_34(ptr %t58, ptr %t59)
  call void @__free_recursive(ptr %t28)
  %t63 = call ptr @__alloc(i64 8, i32 0)
  %t64 = inttoptr i64 56 to ptr
  %t65 = getelementptr ptr, ptr %t63, i32 0
  store ptr %t64, ptr %t65
  %t66 = call ptr @v__cps__df_andThenIO_70(ptr %t27, ptr %t62, ptr %t63)
  %t67 = call ptr @__alloc(i64 8, i32 0)
  %t68 = inttoptr i64 54 to ptr
  %t69 = getelementptr ptr, ptr %t67, i32 0
  store ptr %t68, ptr %t69
  %t70 = call ptr @v__cps__df_andThenIO_66(ptr %t66, ptr %t67)
  %t71 = call ptr @v__apply__df_andThenIO_142(ptr %t6, ptr %t70)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.72:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t73 = call ptr @v__apply__df_andThenIO_142(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t73, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.74:
  %t75 = getelementptr ptr, ptr %t5, i32 1
  %t76 = load ptr, ptr %t75
  %t77 = getelementptr ptr, ptr %t5, i32 2
  %t78 = load ptr, ptr %t77
  call void @__inc_ref(ptr %t78)
  %t85 = getelementptr i8, ptr %t5, i64 -8
  %t86 = load i32, ptr %t85
  %t87 = icmp eq i32 %t86, 1
  br i1 %t87, label %reuse.in_place.88, label %reuse.copy.89
reuse.in_place.88:
  %t79 = getelementptr ptr, ptr %t5, i32 2
  %t80 = load ptr, ptr %t79
  call void @__free_recursive(ptr %t80)
  %t83 = inttoptr i64 93 to ptr
  %t84 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t83, ptr %t84
  call void @__inc_ref(ptr %t6)
  %t81 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t81
  %t82 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t76, ptr %t82
  br label %reuse.in_place.end.91
reuse.in_place.end.91:
  br label %reuse.join.90
reuse.copy.89:
  %t93 = call ptr @__alloc(i64 24, i32 2)
  %t94 = inttoptr i64 93 to ptr
  %t95 = getelementptr ptr, ptr %t93, i32 0
  store ptr %t94, ptr %t95
  call void @__inc_ref(ptr %t6)
  %t96 = getelementptr ptr, ptr %t93, i32 1
  store ptr %t6, ptr %t96
  call void @__inc_ref(ptr %t76)
  %t97 = getelementptr ptr, ptr %t93, i32 2
  store ptr %t76, ptr %t97
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.92
reuse.copy.end.92:
  br label %reuse.join.90
reuse.join.90:
  %t98 = phi ptr [ %t5, %reuse.in_place.end.91 ], [ %t93, %reuse.copy.end.92 ]
  call void @__inc_ref(ptr %t78)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t78)
  store ptr %t78, ptr %t3
  store ptr %t98, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t99 = load ptr, ptr %t2
  ret ptr %t99
}

define internal ptr @v__apply__df_andThenIO_142(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 92, label %tco.case.arm.92.11 i64 93, label %tco.case.arm.93.12 ]
tco.case.arm.92.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.93.12:
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

define internal ptr @v__cps__df_andThenIO_146(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.72 i64 7, label %tco.case.arm.7.74 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.26, i64 12), ptr %t15
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 5 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = call ptr @__alloc(i64 8, i32 0)
  %t20 = inttoptr i64 0 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t19, ptr %t22
  %t23 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t16, ptr %t23
  %t24 = call ptr @__alloc(i64 8, i32 0)
  %t25 = inttoptr i64 58 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_74(ptr %t12, ptr %t24)
  %t28 = call ptr @v_strOk()
  %t29 = getelementptr ptr, ptr %t28, i32 0
  %t30 = load ptr, ptr %t29
  %t31 = ptrtoint ptr %t30 to i64
  switch i64 %t31, label %case.default.32 [ i64 3, label %case.arm.3.34 i64 4, label %case.arm.4.42 ]
case.arm.3.34:
  %t36 = call ptr @__alloc(i64 16, i32 1)
  %t37 = inttoptr i64 6 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t28, i32 1
  %t40 = load ptr, ptr %t39
  call void @__inc_ref(ptr %t40)
  %t41 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t40, ptr %t41
  br label %case.end.3.35
case.end.3.35:
  br label %case.join.33
case.arm.4.42:
  %t44 = call ptr @__alloc(i64 16, i32 1)
  %t45 = inttoptr i64 5 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  %t47 = getelementptr ptr, ptr %t28, i32 1
  %t48 = load ptr, ptr %t47
  call void @__inc_ref(ptr %t48)
  %t49 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t48, ptr %t49
  br label %case.end.4.43
case.end.4.43:
  br label %case.join.33
case.default.32:
  unreachable
case.join.33:
  %t50 = phi ptr [ %t36, %case.end.3.35 ], [ %t44, %case.end.4.43 ]
  %t51 = call ptr @__alloc(i64 8, i32 0)
  %t52 = inttoptr i64 32 to ptr
  %t53 = getelementptr ptr, ptr %t51, i32 0
  store ptr %t52, ptr %t53
  %t54 = call ptr @v__cps__df_mapIO_22(ptr %t50, ptr %t51)
  %t55 = call ptr @__alloc(i64 8, i32 0)
  %t56 = inttoptr i64 40 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  %t58 = call ptr @v__cps__df__rowmono_5_andThenIO_38(ptr %t54, ptr %t55)
  %t59 = call ptr @__alloc(i64 8, i32 0)
  %t60 = inttoptr i64 38 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  %t62 = call ptr @v__cps__df_handleErrorIO_34(ptr %t58, ptr %t59)
  call void @__free_recursive(ptr %t28)
  %t63 = call ptr @__alloc(i64 8, i32 0)
  %t64 = inttoptr i64 56 to ptr
  %t65 = getelementptr ptr, ptr %t63, i32 0
  store ptr %t64, ptr %t65
  %t66 = call ptr @v__cps__df_andThenIO_70(ptr %t27, ptr %t62, ptr %t63)
  %t67 = call ptr @__alloc(i64 8, i32 0)
  %t68 = inttoptr i64 54 to ptr
  %t69 = getelementptr ptr, ptr %t67, i32 0
  store ptr %t68, ptr %t69
  %t70 = call ptr @v__cps__df_andThenIO_66(ptr %t66, ptr %t67)
  %t71 = call ptr @v__apply__df_andThenIO_146(ptr %t6, ptr %t70)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.72:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t73 = call ptr @v__apply__df_andThenIO_146(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t73, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.74:
  %t75 = getelementptr ptr, ptr %t5, i32 1
  %t76 = load ptr, ptr %t75
  %t77 = getelementptr ptr, ptr %t5, i32 2
  %t78 = load ptr, ptr %t77
  call void @__inc_ref(ptr %t78)
  %t85 = getelementptr i8, ptr %t5, i64 -8
  %t86 = load i32, ptr %t85
  %t87 = icmp eq i32 %t86, 1
  br i1 %t87, label %reuse.in_place.88, label %reuse.copy.89
reuse.in_place.88:
  %t79 = getelementptr ptr, ptr %t5, i32 2
  %t80 = load ptr, ptr %t79
  call void @__free_recursive(ptr %t80)
  %t83 = inttoptr i64 95 to ptr
  %t84 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t83, ptr %t84
  call void @__inc_ref(ptr %t6)
  %t81 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t81
  %t82 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t76, ptr %t82
  br label %reuse.in_place.end.91
reuse.in_place.end.91:
  br label %reuse.join.90
reuse.copy.89:
  %t93 = call ptr @__alloc(i64 24, i32 2)
  %t94 = inttoptr i64 95 to ptr
  %t95 = getelementptr ptr, ptr %t93, i32 0
  store ptr %t94, ptr %t95
  call void @__inc_ref(ptr %t6)
  %t96 = getelementptr ptr, ptr %t93, i32 1
  store ptr %t6, ptr %t96
  call void @__inc_ref(ptr %t76)
  %t97 = getelementptr ptr, ptr %t93, i32 2
  store ptr %t76, ptr %t97
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.92
reuse.copy.end.92:
  br label %reuse.join.90
reuse.join.90:
  %t98 = phi ptr [ %t5, %reuse.in_place.end.91 ], [ %t93, %reuse.copy.end.92 ]
  call void @__inc_ref(ptr %t78)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t78)
  store ptr %t78, ptr %t3
  store ptr %t98, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t99 = load ptr, ptr %t2
  ret ptr %t99
}

define internal ptr @v__apply__df_andThenIO_146(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 94, label %tco.case.arm.94.11 i64 95, label %tco.case.arm.95.12 ]
tco.case.arm.94.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.95.12:
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

define internal ptr @v__cps__df_andThenIO_150(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.68 i64 7, label %tco.case.arm.7.70 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.27, i64 12), ptr %t15
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 5 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = call ptr @__alloc(i64 8, i32 0)
  %t20 = inttoptr i64 0 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t19, ptr %t22
  %t23 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t16, ptr %t23
  %t24 = call ptr @__alloc(i64 8, i32 0)
  %t25 = inttoptr i64 58 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_74(ptr %t12, ptr %t24)
  %t28 = call ptr @v_pureNever()
  %t29 = getelementptr ptr, ptr %t28, i32 0
  %t30 = load ptr, ptr %t29
  %t31 = ptrtoint ptr %t30 to i64
  switch i64 %t31, label %case.default.32 [ i64 3, label %case.arm.3.34 i64 4, label %case.arm.4.42 ]
case.arm.3.34:
  %t36 = call ptr @__alloc(i64 16, i32 1)
  %t37 = inttoptr i64 6 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t28, i32 1
  %t40 = load ptr, ptr %t39
  call void @__inc_ref(ptr %t40)
  %t41 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t40, ptr %t41
  br label %case.end.3.35
case.end.3.35:
  br label %case.join.33
case.arm.4.42:
  %t44 = call ptr @__alloc(i64 16, i32 1)
  %t45 = inttoptr i64 5 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  %t47 = getelementptr ptr, ptr %t28, i32 1
  %t48 = load ptr, ptr %t47
  call void @__inc_ref(ptr %t48)
  %t49 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t48, ptr %t49
  br label %case.end.4.43
case.end.4.43:
  br label %case.join.33
case.default.32:
  unreachable
case.join.33:
  %t50 = phi ptr [ %t36, %case.end.3.35 ], [ %t44, %case.end.4.43 ]
  %t51 = call ptr @__alloc(i64 8, i32 0)
  %t52 = inttoptr i64 32 to ptr
  %t53 = getelementptr ptr, ptr %t51, i32 0
  store ptr %t52, ptr %t53
  %t54 = call ptr @v__cps__df_mapIO_22(ptr %t50, ptr %t51)
  %t55 = call ptr @__alloc(i64 8, i32 0)
  %t56 = inttoptr i64 30 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  %t58 = call ptr @v__cps__df_andThenIO_18(ptr %t54, ptr %t55)
  call void @__free_recursive(ptr %t28)
  %t59 = call ptr @__alloc(i64 8, i32 0)
  %t60 = inttoptr i64 56 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  %t62 = call ptr @v__cps__df_andThenIO_70(ptr %t27, ptr %t58, ptr %t59)
  %t63 = call ptr @__alloc(i64 8, i32 0)
  %t64 = inttoptr i64 54 to ptr
  %t65 = getelementptr ptr, ptr %t63, i32 0
  store ptr %t64, ptr %t65
  %t66 = call ptr @v__cps__df_andThenIO_66(ptr %t62, ptr %t63)
  %t67 = call ptr @v__apply__df_andThenIO_150(ptr %t6, ptr %t66)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t67, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.68:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t69 = call ptr @v__apply__df_andThenIO_150(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t69, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.70:
  %t71 = getelementptr ptr, ptr %t5, i32 1
  %t72 = load ptr, ptr %t71
  %t73 = getelementptr ptr, ptr %t5, i32 2
  %t74 = load ptr, ptr %t73
  call void @__inc_ref(ptr %t74)
  %t81 = getelementptr i8, ptr %t5, i64 -8
  %t82 = load i32, ptr %t81
  %t83 = icmp eq i32 %t82, 1
  br i1 %t83, label %reuse.in_place.84, label %reuse.copy.85
reuse.in_place.84:
  %t75 = getelementptr ptr, ptr %t5, i32 2
  %t76 = load ptr, ptr %t75
  call void @__free_recursive(ptr %t76)
  %t79 = inttoptr i64 97 to ptr
  %t80 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t79, ptr %t80
  call void @__inc_ref(ptr %t6)
  %t77 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t77
  %t78 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t72, ptr %t78
  br label %reuse.in_place.end.87
reuse.in_place.end.87:
  br label %reuse.join.86
reuse.copy.85:
  %t89 = call ptr @__alloc(i64 24, i32 2)
  %t90 = inttoptr i64 97 to ptr
  %t91 = getelementptr ptr, ptr %t89, i32 0
  store ptr %t90, ptr %t91
  call void @__inc_ref(ptr %t6)
  %t92 = getelementptr ptr, ptr %t89, i32 1
  store ptr %t6, ptr %t92
  call void @__inc_ref(ptr %t72)
  %t93 = getelementptr ptr, ptr %t89, i32 2
  store ptr %t72, ptr %t93
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.88
reuse.copy.end.88:
  br label %reuse.join.86
reuse.join.86:
  %t94 = phi ptr [ %t5, %reuse.in_place.end.87 ], [ %t89, %reuse.copy.end.88 ]
  call void @__inc_ref(ptr %t74)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t74)
  store ptr %t74, ptr %t3
  store ptr %t94, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t95 = load ptr, ptr %t2
  ret ptr %t95
}

define internal ptr @v__apply__df_andThenIO_150(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 96, label %tco.case.arm.96.11 i64 97, label %tco.case.arm.97.12 ]
tco.case.arm.96.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.97.12:
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

define internal ptr @v__cps__df_andThenIO_154(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.72 i64 7, label %tco.case.arm.7.74 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.28, i64 12), ptr %t15
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 5 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = call ptr @__alloc(i64 8, i32 0)
  %t20 = inttoptr i64 0 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t19, ptr %t22
  %t23 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t16, ptr %t23
  %t24 = call ptr @__alloc(i64 8, i32 0)
  %t25 = inttoptr i64 58 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_74(ptr %t12, ptr %t24)
  %t28 = call ptr @v_nevRightE1()
  %t29 = getelementptr ptr, ptr %t28, i32 0
  %t30 = load ptr, ptr %t29
  %t31 = ptrtoint ptr %t30 to i64
  switch i64 %t31, label %case.default.32 [ i64 3, label %case.arm.3.34 i64 4, label %case.arm.4.42 ]
case.arm.3.34:
  %t36 = call ptr @__alloc(i64 16, i32 1)
  %t37 = inttoptr i64 6 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t28, i32 1
  %t40 = load ptr, ptr %t39
  call void @__inc_ref(ptr %t40)
  %t41 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t40, ptr %t41
  br label %case.end.3.35
case.end.3.35:
  br label %case.join.33
case.arm.4.42:
  %t44 = call ptr @__alloc(i64 16, i32 1)
  %t45 = inttoptr i64 5 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  %t47 = getelementptr ptr, ptr %t28, i32 1
  %t48 = load ptr, ptr %t47
  call void @__inc_ref(ptr %t48)
  %t49 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t48, ptr %t49
  br label %case.end.4.43
case.end.4.43:
  br label %case.join.33
case.default.32:
  unreachable
case.join.33:
  %t50 = phi ptr [ %t36, %case.end.3.35 ], [ %t44, %case.end.4.43 ]
  %t51 = call ptr @__alloc(i64 8, i32 0)
  %t52 = inttoptr i64 32 to ptr
  %t53 = getelementptr ptr, ptr %t51, i32 0
  store ptr %t52, ptr %t53
  %t54 = call ptr @v__cps__df_mapIO_22(ptr %t50, ptr %t51)
  %t55 = call ptr @__alloc(i64 8, i32 0)
  %t56 = inttoptr i64 30 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  %t58 = call ptr @v__cps__df_andThenIO_18(ptr %t54, ptr %t55)
  %t59 = call ptr @__alloc(i64 8, i32 0)
  %t60 = inttoptr i64 28 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  %t62 = call ptr @v__cps__df_handleErrorIO_14(ptr %t58, ptr %t59)
  call void @__free_recursive(ptr %t28)
  %t63 = call ptr @__alloc(i64 8, i32 0)
  %t64 = inttoptr i64 56 to ptr
  %t65 = getelementptr ptr, ptr %t63, i32 0
  store ptr %t64, ptr %t65
  %t66 = call ptr @v__cps__df_andThenIO_70(ptr %t27, ptr %t62, ptr %t63)
  %t67 = call ptr @__alloc(i64 8, i32 0)
  %t68 = inttoptr i64 54 to ptr
  %t69 = getelementptr ptr, ptr %t67, i32 0
  store ptr %t68, ptr %t69
  %t70 = call ptr @v__cps__df_andThenIO_66(ptr %t66, ptr %t67)
  %t71 = call ptr @v__apply__df_andThenIO_154(ptr %t6, ptr %t70)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.72:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t73 = call ptr @v__apply__df_andThenIO_154(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t73, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.74:
  %t75 = getelementptr ptr, ptr %t5, i32 1
  %t76 = load ptr, ptr %t75
  %t77 = getelementptr ptr, ptr %t5, i32 2
  %t78 = load ptr, ptr %t77
  call void @__inc_ref(ptr %t78)
  %t85 = getelementptr i8, ptr %t5, i64 -8
  %t86 = load i32, ptr %t85
  %t87 = icmp eq i32 %t86, 1
  br i1 %t87, label %reuse.in_place.88, label %reuse.copy.89
reuse.in_place.88:
  %t79 = getelementptr ptr, ptr %t5, i32 2
  %t80 = load ptr, ptr %t79
  call void @__free_recursive(ptr %t80)
  %t83 = inttoptr i64 99 to ptr
  %t84 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t83, ptr %t84
  call void @__inc_ref(ptr %t6)
  %t81 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t81
  %t82 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t76, ptr %t82
  br label %reuse.in_place.end.91
reuse.in_place.end.91:
  br label %reuse.join.90
reuse.copy.89:
  %t93 = call ptr @__alloc(i64 24, i32 2)
  %t94 = inttoptr i64 99 to ptr
  %t95 = getelementptr ptr, ptr %t93, i32 0
  store ptr %t94, ptr %t95
  call void @__inc_ref(ptr %t6)
  %t96 = getelementptr ptr, ptr %t93, i32 1
  store ptr %t6, ptr %t96
  call void @__inc_ref(ptr %t76)
  %t97 = getelementptr ptr, ptr %t93, i32 2
  store ptr %t76, ptr %t97
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.92
reuse.copy.end.92:
  br label %reuse.join.90
reuse.join.90:
  %t98 = phi ptr [ %t5, %reuse.in_place.end.91 ], [ %t93, %reuse.copy.end.92 ]
  call void @__inc_ref(ptr %t78)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t78)
  store ptr %t78, ptr %t3
  store ptr %t98, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t99 = load ptr, ptr %t2
  ret ptr %t99
}

define internal ptr @v__apply__df_andThenIO_154(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 98, label %tco.case.arm.98.11 i64 99, label %tco.case.arm.99.12 ]
tco.case.arm.98.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.99.12:
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

define internal ptr @v__cps__df_andThenIO_158(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.72 i64 7, label %tco.case.arm.7.74 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.29, i64 12), ptr %t15
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 5 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = call ptr @__alloc(i64 8, i32 0)
  %t20 = inttoptr i64 0 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t19, ptr %t22
  %t23 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t16, ptr %t23
  %t24 = call ptr @__alloc(i64 8, i32 0)
  %t25 = inttoptr i64 58 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_74(ptr %t12, ptr %t24)
  %t28 = call ptr @v_nevRightOk()
  %t29 = getelementptr ptr, ptr %t28, i32 0
  %t30 = load ptr, ptr %t29
  %t31 = ptrtoint ptr %t30 to i64
  switch i64 %t31, label %case.default.32 [ i64 3, label %case.arm.3.34 i64 4, label %case.arm.4.42 ]
case.arm.3.34:
  %t36 = call ptr @__alloc(i64 16, i32 1)
  %t37 = inttoptr i64 6 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t28, i32 1
  %t40 = load ptr, ptr %t39
  call void @__inc_ref(ptr %t40)
  %t41 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t40, ptr %t41
  br label %case.end.3.35
case.end.3.35:
  br label %case.join.33
case.arm.4.42:
  %t44 = call ptr @__alloc(i64 16, i32 1)
  %t45 = inttoptr i64 5 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  %t47 = getelementptr ptr, ptr %t28, i32 1
  %t48 = load ptr, ptr %t47
  call void @__inc_ref(ptr %t48)
  %t49 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t48, ptr %t49
  br label %case.end.4.43
case.end.4.43:
  br label %case.join.33
case.default.32:
  unreachable
case.join.33:
  %t50 = phi ptr [ %t36, %case.end.3.35 ], [ %t44, %case.end.4.43 ]
  %t51 = call ptr @__alloc(i64 8, i32 0)
  %t52 = inttoptr i64 32 to ptr
  %t53 = getelementptr ptr, ptr %t51, i32 0
  store ptr %t52, ptr %t53
  %t54 = call ptr @v__cps__df_mapIO_22(ptr %t50, ptr %t51)
  %t55 = call ptr @__alloc(i64 8, i32 0)
  %t56 = inttoptr i64 30 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  %t58 = call ptr @v__cps__df_andThenIO_18(ptr %t54, ptr %t55)
  %t59 = call ptr @__alloc(i64 8, i32 0)
  %t60 = inttoptr i64 28 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  %t62 = call ptr @v__cps__df_handleErrorIO_14(ptr %t58, ptr %t59)
  call void @__free_recursive(ptr %t28)
  %t63 = call ptr @__alloc(i64 8, i32 0)
  %t64 = inttoptr i64 56 to ptr
  %t65 = getelementptr ptr, ptr %t63, i32 0
  store ptr %t64, ptr %t65
  %t66 = call ptr @v__cps__df_andThenIO_70(ptr %t27, ptr %t62, ptr %t63)
  %t67 = call ptr @__alloc(i64 8, i32 0)
  %t68 = inttoptr i64 54 to ptr
  %t69 = getelementptr ptr, ptr %t67, i32 0
  store ptr %t68, ptr %t69
  %t70 = call ptr @v__cps__df_andThenIO_66(ptr %t66, ptr %t67)
  %t71 = call ptr @v__apply__df_andThenIO_158(ptr %t6, ptr %t70)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.72:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t73 = call ptr @v__apply__df_andThenIO_158(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t73, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.74:
  %t75 = getelementptr ptr, ptr %t5, i32 1
  %t76 = load ptr, ptr %t75
  %t77 = getelementptr ptr, ptr %t5, i32 2
  %t78 = load ptr, ptr %t77
  call void @__inc_ref(ptr %t78)
  %t85 = getelementptr i8, ptr %t5, i64 -8
  %t86 = load i32, ptr %t85
  %t87 = icmp eq i32 %t86, 1
  br i1 %t87, label %reuse.in_place.88, label %reuse.copy.89
reuse.in_place.88:
  %t79 = getelementptr ptr, ptr %t5, i32 2
  %t80 = load ptr, ptr %t79
  call void @__free_recursive(ptr %t80)
  %t83 = inttoptr i64 101 to ptr
  %t84 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t83, ptr %t84
  call void @__inc_ref(ptr %t6)
  %t81 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t81
  %t82 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t76, ptr %t82
  br label %reuse.in_place.end.91
reuse.in_place.end.91:
  br label %reuse.join.90
reuse.copy.89:
  %t93 = call ptr @__alloc(i64 24, i32 2)
  %t94 = inttoptr i64 101 to ptr
  %t95 = getelementptr ptr, ptr %t93, i32 0
  store ptr %t94, ptr %t95
  call void @__inc_ref(ptr %t6)
  %t96 = getelementptr ptr, ptr %t93, i32 1
  store ptr %t6, ptr %t96
  call void @__inc_ref(ptr %t76)
  %t97 = getelementptr ptr, ptr %t93, i32 2
  store ptr %t76, ptr %t97
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.92
reuse.copy.end.92:
  br label %reuse.join.90
reuse.join.90:
  %t98 = phi ptr [ %t5, %reuse.in_place.end.91 ], [ %t93, %reuse.copy.end.92 ]
  call void @__inc_ref(ptr %t78)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t78)
  store ptr %t78, ptr %t3
  store ptr %t98, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t99 = load ptr, ptr %t2
  ret ptr %t99
}

define internal ptr @v__apply__df_andThenIO_158(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 100, label %tco.case.arm.100.11 i64 101, label %tco.case.arm.101.12 ]
tco.case.arm.100.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.101.12:
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

define internal ptr @v__cps__df_andThenIO_162(ptr %v_io, ptr %v__k) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 5, label %tco.case.arm.5.11 i64 6, label %tco.case.arm.6.72 i64 7, label %tco.case.arm.7.74 ]
tco.case.arm.5.11:
  call void @__inc_ref(ptr %t6)
  %t12 = call ptr @__alloc(i64 24, i32 2)
  %t13 = inttoptr i64 7 to ptr
  %t14 = getelementptr ptr, ptr %t12, i32 0
  store ptr %t13, ptr %t14
  %t15 = getelementptr ptr, ptr %t12, i32 1
  store ptr getelementptr inbounds (i8, ptr @.str.30, i64 12), ptr %t15
  %t16 = call ptr @__alloc(i64 16, i32 1)
  %t17 = inttoptr i64 5 to ptr
  %t18 = getelementptr ptr, ptr %t16, i32 0
  store ptr %t17, ptr %t18
  %t19 = call ptr @__alloc(i64 8, i32 0)
  %t20 = inttoptr i64 0 to ptr
  %t21 = getelementptr ptr, ptr %t19, i32 0
  store ptr %t20, ptr %t21
  %t22 = getelementptr ptr, ptr %t16, i32 1
  store ptr %t19, ptr %t22
  %t23 = getelementptr ptr, ptr %t12, i32 2
  store ptr %t16, ptr %t23
  %t24 = call ptr @__alloc(i64 8, i32 0)
  %t25 = inttoptr i64 58 to ptr
  %t26 = getelementptr ptr, ptr %t24, i32 0
  store ptr %t25, ptr %t26
  %t27 = call ptr @v__cps__df_andThenIO_74(ptr %t12, ptr %t24)
  %t28 = call ptr @v_nevFail()
  %t29 = getelementptr ptr, ptr %t28, i32 0
  %t30 = load ptr, ptr %t29
  %t31 = ptrtoint ptr %t30 to i64
  switch i64 %t31, label %case.default.32 [ i64 3, label %case.arm.3.34 i64 4, label %case.arm.4.42 ]
case.arm.3.34:
  %t36 = call ptr @__alloc(i64 16, i32 1)
  %t37 = inttoptr i64 6 to ptr
  %t38 = getelementptr ptr, ptr %t36, i32 0
  store ptr %t37, ptr %t38
  %t39 = getelementptr ptr, ptr %t28, i32 1
  %t40 = load ptr, ptr %t39
  call void @__inc_ref(ptr %t40)
  %t41 = getelementptr ptr, ptr %t36, i32 1
  store ptr %t40, ptr %t41
  br label %case.end.3.35
case.end.3.35:
  br label %case.join.33
case.arm.4.42:
  %t44 = call ptr @__alloc(i64 16, i32 1)
  %t45 = inttoptr i64 5 to ptr
  %t46 = getelementptr ptr, ptr %t44, i32 0
  store ptr %t45, ptr %t46
  %t47 = getelementptr ptr, ptr %t28, i32 1
  %t48 = load ptr, ptr %t47
  call void @__inc_ref(ptr %t48)
  %t49 = getelementptr ptr, ptr %t44, i32 1
  store ptr %t48, ptr %t49
  br label %case.end.4.43
case.end.4.43:
  br label %case.join.33
case.default.32:
  unreachable
case.join.33:
  %t50 = phi ptr [ %t36, %case.end.3.35 ], [ %t44, %case.end.4.43 ]
  %t51 = call ptr @__alloc(i64 8, i32 0)
  %t52 = inttoptr i64 32 to ptr
  %t53 = getelementptr ptr, ptr %t51, i32 0
  store ptr %t52, ptr %t53
  %t54 = call ptr @v__cps__df_mapIO_22(ptr %t50, ptr %t51)
  %t55 = call ptr @__alloc(i64 8, i32 0)
  %t56 = inttoptr i64 30 to ptr
  %t57 = getelementptr ptr, ptr %t55, i32 0
  store ptr %t56, ptr %t57
  %t58 = call ptr @v__cps__df_andThenIO_18(ptr %t54, ptr %t55)
  %t59 = call ptr @__alloc(i64 8, i32 0)
  %t60 = inttoptr i64 28 to ptr
  %t61 = getelementptr ptr, ptr %t59, i32 0
  store ptr %t60, ptr %t61
  %t62 = call ptr @v__cps__df_handleErrorIO_14(ptr %t58, ptr %t59)
  call void @__free_recursive(ptr %t28)
  %t63 = call ptr @__alloc(i64 8, i32 0)
  %t64 = inttoptr i64 56 to ptr
  %t65 = getelementptr ptr, ptr %t63, i32 0
  store ptr %t64, ptr %t65
  %t66 = call ptr @v__cps__df_andThenIO_70(ptr %t27, ptr %t62, ptr %t63)
  %t67 = call ptr @__alloc(i64 8, i32 0)
  %t68 = inttoptr i64 54 to ptr
  %t69 = getelementptr ptr, ptr %t67, i32 0
  store ptr %t68, ptr %t69
  %t70 = call ptr @v__cps__df_andThenIO_66(ptr %t66, ptr %t67)
  %t71 = call ptr @v__apply__df_andThenIO_162(ptr %t6, ptr %t70)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t71, ptr %t2
  br label %tco.exit.1
tco.case.arm.6.72:
  call void @__inc_ref(ptr %t6)
  call void @__inc_ref(ptr %t5)
  %t73 = call ptr @v__apply__df_andThenIO_162(ptr %t6, ptr %t5)
  call void @__free_recursive(ptr %t5)
  call void @__free_recursive(ptr %t6)
  store ptr %t73, ptr %t2
  br label %tco.exit.1
tco.case.arm.7.74:
  %t75 = getelementptr ptr, ptr %t5, i32 1
  %t76 = load ptr, ptr %t75
  %t77 = getelementptr ptr, ptr %t5, i32 2
  %t78 = load ptr, ptr %t77
  call void @__inc_ref(ptr %t78)
  %t85 = getelementptr i8, ptr %t5, i64 -8
  %t86 = load i32, ptr %t85
  %t87 = icmp eq i32 %t86, 1
  br i1 %t87, label %reuse.in_place.88, label %reuse.copy.89
reuse.in_place.88:
  %t79 = getelementptr ptr, ptr %t5, i32 2
  %t80 = load ptr, ptr %t79
  call void @__free_recursive(ptr %t80)
  %t83 = inttoptr i64 103 to ptr
  %t84 = getelementptr ptr, ptr %t5, i32 0
  store ptr %t83, ptr %t84
  call void @__inc_ref(ptr %t6)
  %t81 = getelementptr ptr, ptr %t5, i32 1
  store ptr %t6, ptr %t81
  %t82 = getelementptr ptr, ptr %t5, i32 2
  store ptr %t76, ptr %t82
  br label %reuse.in_place.end.91
reuse.in_place.end.91:
  br label %reuse.join.90
reuse.copy.89:
  %t93 = call ptr @__alloc(i64 24, i32 2)
  %t94 = inttoptr i64 103 to ptr
  %t95 = getelementptr ptr, ptr %t93, i32 0
  store ptr %t94, ptr %t95
  call void @__inc_ref(ptr %t6)
  %t96 = getelementptr ptr, ptr %t93, i32 1
  store ptr %t6, ptr %t96
  call void @__inc_ref(ptr %t76)
  %t97 = getelementptr ptr, ptr %t93, i32 2
  store ptr %t76, ptr %t97
  call void @__free_recursive(ptr %t5)
  br label %reuse.copy.end.92
reuse.copy.end.92:
  br label %reuse.join.90
reuse.join.90:
  %t98 = phi ptr [ %t5, %reuse.in_place.end.91 ], [ %t93, %reuse.copy.end.92 ]
  call void @__inc_ref(ptr %t78)
  call void @__free_recursive(ptr %t6)
  call void @__free_recursive(ptr %t78)
  store ptr %t78, ptr %t3
  store ptr %t98, ptr %t4
  br label %tco.loop.0
tco.case.default.10:
  unreachable
tco.exit.1:
  %t99 = load ptr, ptr %t2
  ret ptr %t99
}

define internal ptr @v__apply__df_andThenIO_162(ptr %v__k, ptr %v__x) {
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
  switch i64 %t9, label %tco.case.default.10 [ i64 102, label %tco.case.arm.102.11 i64 103, label %tco.case.arm.103.12 ]
tco.case.arm.102.11:
  call void @__free_recursive(ptr %t5)
  store ptr %t6, ptr %t2
  br label %tco.exit.1
tco.case.arm.103.12:
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

declare i32 @_setmode(i32, i32)

define i32 @main(i32 %argc_posix, ptr %argv_posix) {
entry:
  call i32 @_setmode(i32 1, i32 32768)
  call i32 @_setmode(i32 0, i32 32768)
  %io = call ptr @v_main()
  call ptr @v_runIO(ptr %io)
  ret i32 0
}
